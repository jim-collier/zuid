//	Copyright © 2026 Jim Collier
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

// Package zuid generates identifiers that sort chronologically as plain text.
//
// The identifier is a format string of components - time, host, user, FQDN,
// MAC, UUID, random - rendered into one output base. Every component is a
// fixed number of symbols wide, which is what makes byte-order sort match time
// order and what lets an identifier be split by offset.
//
// Base conversion is not done here. It comes from convertbase, which already
// carries the alphabets and the arbitrary-precision conversion. This package
// contributes the components and the fixed-width padding.
package zuid

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"os"
	"os/user"
	"strconv"
	"strings"
	"time"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
)

// Curated bases offered in help. --base still accepts anything convertbase
// knows; these are just the four that sort and that a human can transcribe.
var CuratedBases = []string{"16", "32w", "36", "62"}

// DefaultBase is what you get without asking.
const DefaultBase = "62"

const (
	// DefaultHashChars is how many symbols a hashed component keeps. Eight
	// base-62 symbols is around 47 bits of fingerprint.
	DefaultHashChars = 8
	// DefaultRandomChars is how many symbols %r emits.
	DefaultRandomChars = 6
	// MaxComponentChars bounds both, so a format string cannot ask for an
	// identifier that will not fit a caller's buffer.
	MaxComponentChars = 64
)

// Bit widths of the fixed-size components, which is what their output widths
// are derived from.
const (
	macBits  = 48
	uuidBits = 128
)

// Precision selects the time unit, carrying the predecessor's surface
// forward: -1 minute, 0 second, 1 millisecond. The clock is always taken in
// milliseconds and truncated toward zero for the coarser units.
type Precision int

const (
	PrecisionMinute Precision = -1
	PrecisionSecond Precision = 0 // the default
	PrecisionMilli  Precision = 1
)

// DefaultPrecision matches the predecessor's default: seconds.
const DefaultPrecision = PrecisionSecond

// horizonMs is the largest timestamp the fixed width has to hold: 3000-01-01
// UTC. Width is quantized so coarsely that moving this by a century or two
// usually changes nothing.
const horizonMs = 32503680000000

// msPerUnit converts the clock to the precision's unit; also the divisor that
// scales the horizon.
func (p Precision) msPerUnit() (int64, error) {
	switch p {
	case PrecisionMinute:
		return 60000, nil
	case PrecisionSecond:
		return 1000, nil
	case PrecisionMilli:
		return 1, nil
	}
	return 0, fmt.Errorf("precision %d: want -1 (minute), 0 (second), or 1 (millisecond)", p)
}

// Request is one identifier's worth of choices. The zero value is a valid
// request: the default format in the default base at the default precision,
// with hashing on. NoHash is negated for exactly that reason.
type Request struct {
	Format      string    // "" means "%d"
	Base        string    // "" means base 62
	Precision   Precision // -1 minute, 0 second, 1 millisecond
	NoHash      bool      // emit host, user, and FQDN literally instead of hashed
	HashChars   int       // 0 means DefaultHashChars
	RandomChars int       // 0 means DefaultRandomChars
}

// Generator renders identifiers. Every source of environment - clock, random,
// host, user, FQDN, MAC - is a field rather than a package-level call, so that
// output is reproducible under test. That is the whole basis of the shared
// vectors.
type Generator struct {
	registry *convertbase.Registry
	decimal  *convertbase.Base // input side of the time conversion
	hex      *convertbase.Base // input side of every hash, MAC, UUID, and random conversion
	now      func() time.Time
	random   io.Reader
	hostname func() (string, error)
	username func() (string, error)
	fqdn     func() (string, error)
	mac      func() ([]byte, error)
}

// Option configures a Generator.
type Option func(*Generator)

// WithClock replaces the wall clock.
func WithClock(clock func() time.Time) Option {
	return func(g *Generator) { g.now = clock }
}

// WithFixedTime pins the clock to one instant, which is what the vectors need.
func WithFixedTime(at time.Time) Option {
	return WithClock(func() time.Time { return at })
}

// WithRandom replaces the random source. %g and %r draw from it in the order
// they appear in the format string.
func WithRandom(source io.Reader) Option {
	return func(g *Generator) { g.random = source }
}

// WithHostname pins the short host name.
func WithHostname(name string) Option {
	return func(g *Generator) { g.hostname = func() (string, error) { return name, nil } }
}

// WithUsername pins the user name.
func WithUsername(name string) Option {
	return func(g *Generator) { g.username = func() (string, error) { return name, nil } }
}

// WithFQDN pins the fully-qualified name.
func WithFQDN(name string) Option {
	return func(g *Generator) { g.fqdn = func() (string, error) { return name, nil } }
}

// WithMAC pins the hardware address, which must be the usual six bytes.
func WithMAC(address []byte) Option {
	pinned := append([]byte(nil), address...)
	return func(g *Generator) {
		g.mac = func() ([]byte, error) {
			if len(pinned) != macBits/8 {
				return nil, fmt.Errorf("MAC address is %d bytes, want %d", len(pinned), macBits/8)
			}
			return pinned, nil
		}
	}
}

// New builds a Generator with the built-in base registry and live sources.
func New(opts ...Option) (*Generator, error) {
	registry, err := convertbase.NewRegistry()
	if err != nil {
		return nil, fmt.Errorf("base registry: %w", err)
	}
	decimal, err := registry.Lookup("10")
	if err != nil {
		return nil, fmt.Errorf("base 10: %w", err)
	}
	hexBase, err := registry.Lookup("16")
	if err != nil {
		return nil, fmt.Errorf("base 16: %w", err)
	}

	g := &Generator{
		registry: registry,
		decimal:  decimal,
		hex:      hexBase,
		now:      time.Now,
		random:   rand.Reader,
		hostname: liveHostname,
		username: liveUsername,
		fqdn:     liveFQDN,
		mac:      liveMAC,
	}
	for _, opt := range opts {
		opt(g)
	}
	return g, nil
}

// Generate renders one identifier.
func (g *Generator) Generate(req Request) (string, error) {
	if req.Format == "" {
		req.Format = "%d"
	}
	if req.Base == "" {
		req.Base = DefaultBase
	}
	if req.HashChars == 0 {
		req.HashChars = DefaultHashChars
	}
	if req.RandomChars == 0 {
		req.RandomChars = DefaultRandomChars
	}
	base, err := g.registry.Lookup(req.Base)
	if err != nil {
		return "", err
	}
	if _, err := req.Precision.msPerUnit(); err != nil {
		return "", err
	}
	if err := checkChars("hash", req.HashChars); err != nil {
		return "", err
	}
	if err := checkChars("random", req.RandomChars); err != nil {
		return "", err
	}

	var out strings.Builder
	for i := 0; i < len(req.Format); i++ {
		if req.Format[i] != '%' {
			out.WriteByte(req.Format[i])
			continue
		}
		i++
		if i == len(req.Format) {
			return "", errors.New("format ends on a bare '%'")
		}

		verb := req.Format[i]
		var rendered string
		switch verb {
		case '%':
			out.WriteByte('%')
			continue
		case 'd':
			rendered, err = g.timeComponent(base, req.Precision)
		case 'h':
			rendered, err = g.namedComponent(g.hostname, base, req)
		case 'u':
			rendered, err = g.namedComponent(g.username, base, req)
		case 'f':
			rendered, err = g.namedComponent(g.fqdn, base, req)
		case 'm':
			rendered, err = g.macComponent(base)
		case 'g':
			rendered, err = g.uuidComponent(base)
		case 'r':
			rendered, err = g.randomComponent(base, req.RandomChars)
		default:
			return "", fmt.Errorf("unknown component %%%c", verb)
		}
		if err != nil {
			return "", fmt.Errorf("component %%%c: %w", verb, err)
		}
		out.WriteString(rendered)
	}
	return out.String(), nil
}

func checkChars(what string, count int) error {
	if count < 1 || count > MaxComponentChars {
		return fmt.Errorf("%s width %d: want 1 to %d", what, count, MaxComponentChars)
	}
	return nil
}

// timeComponent renders the clock as the precision's unit count since the
// Unix epoch UTC, padded to the fixed width for this base and precision.
func (g *Generator) timeComponent(base *convertbase.Base, precision Precision) (string, error) {
	ms := g.now().UTC().UnixMilli()
	if ms < 0 {
		return "", fmt.Errorf("clock predates the Unix epoch: %d ms", ms)
	}
	divisor, err := precision.msPerUnit()
	if err != nil {
		return "", err
	}
	width, err := WidthFor(len(base.Symbols), precision)
	if err != nil {
		return "", err
	}
	converted, err := g.convert(strconv.FormatInt(ms/divisor, 10), g.decimal, base)
	if err != nil {
		return "", err
	}
	return pad(converted, base, width)
}

// namedComponent renders host, user, or FQDN. Hashed by default: the name goes
// through SHA-256 and only the rightmost few symbols survive, so the result is
// a fingerprint rather than an identity. Opting out emits the name itself,
// which is the one component that is not fixed width.
func (g *Generator) namedComponent(source func() (string, error), base *convertbase.Base, req Request) (string, error) {
	name, err := source()
	if err != nil {
		return "", err
	}
	if name == "" {
		return "", errors.New("the name is empty")
	}
	if req.NoHash {
		return name, nil
	}
	digest := sha256.Sum256([]byte(name))
	converted, err := g.convertHex(digest[:], base)
	if err != nil {
		return "", err
	}
	return keepRight(converted, base, req.HashChars)
}

// macComponent renders the hardware address as the 48-bit number it is.
func (g *Generator) macComponent(base *convertbase.Base) (string, error) {
	address, err := g.mac()
	if err != nil {
		return "", err
	}
	if len(address) != macBits/8 {
		return "", fmt.Errorf("MAC address is %d bytes, want %d", len(address), macBits/8)
	}
	converted, err := g.convertHex(address, base)
	if err != nil {
		return "", err
	}
	return pad(converted, base, widthForBits(len(base.Symbols), macBits))
}

// uuidComponent draws a UUID v4 from the random source and renders it as the
// 128-bit number it is - not in the dashed text form, which would not sort and
// would be four times as long.
func (g *Generator) uuidComponent(base *convertbase.Base) (string, error) {
	var uuid [uuidBits / 8]byte
	if _, err := io.ReadFull(g.random, uuid[:]); err != nil {
		return "", fmt.Errorf("random source: %w", err)
	}
	uuid[6] = uuid[6]&0x0f | 0x40 // version 4
	uuid[8] = uuid[8]&0x3f | 0x80 // variant 10
	converted, err := g.convertHex(uuid[:], base)
	if err != nil {
		return "", err
	}
	return pad(converted, base, widthForBits(len(base.Symbols), uuidBits))
}

// randomComponent draws one byte per requested symbol. That is more entropy
// than any base of 256 symbols or fewer can spend, so the draw never has to
// know the radix.
func (g *Generator) randomComponent(base *convertbase.Base, count int) (string, error) {
	drawn := make([]byte, count)
	if _, err := io.ReadFull(g.random, drawn); err != nil {
		return "", fmt.Errorf("random source: %w", err)
	}
	converted, err := g.convertHex(drawn, base)
	if err != nil {
		return "", err
	}
	return keepRight(converted, base, count)
}

// convertHex is the path every byte-valued component takes: base 16 in,
// because that is the cheapest faithful way to hand bytes to the library.
func (g *Generator) convertHex(raw []byte, to *convertbase.Base) (string, error) {
	return g.convert(strings.ToUpper(hex.EncodeToString(raw)), g.hex, to)
}

func (g *Generator) convert(value string, from, to *convertbase.Base) (string, error) {
	converted, err := convertbase.Convert(value, from, to, -1)
	if err != nil {
		return "", fmt.Errorf("convert %s from base %s to base %s: %w", value, from.Name(), to.Name(), err)
	}
	return converted, nil
}

// pad left-fills to a derived width with the alphabet's zero digit.
// Lexicographic compare reads left to right, so a short identifier and a long
// one cannot sort chronologically - this fixed width is what makes the sort
// guarantee hold, not the choice of alphabet. Overflowing the width means the
// value is past the horizon the width was derived for, which is an error
// rather than something to truncate.
func pad(converted string, base *convertbase.Base, width int) (string, error) {
	symbols, err := symbolCount(converted, base)
	if err != nil {
		return "", err
	}
	if symbols > width {
		return "", fmt.Errorf("value needs %d symbols in base %s, past the %d-symbol width",
			symbols, base.Name(), width)
	}
	return strings.Repeat(base.Symbols[0], width-symbols) + converted, nil
}

// keepRight takes the rightmost count symbols of a hash or a random draw,
// left-filling on the rare occasion the value renders shorter than that.
// Truncation is what makes a hash short enough to be useful.
//
// It needs single-byte digits, because the conversion library offers no way to
// slice a string at a symbol boundary and the two implementations have to
// agree on the answer. Every base worth putting in an identifier qualifies;
// the exotic multi-byte ones are refused rather than guessed at.
func keepRight(converted string, base *convertbase.Base, count int) (string, error) {
	symbols, err := symbolCount(converted, base)
	if err != nil {
		return "", err
	}
	if symbols != len(converted) || len(base.Symbols[0]) != 1 {
		return "", fmt.Errorf("base %s has multi-byte digits, so a truncated component cannot be split in it",
			base.Name())
	}
	if symbols >= count {
		return converted[symbols-count:], nil
	}
	return strings.Repeat(base.Symbols[0], count-symbols) + converted, nil
}

// Count symbols, not bytes: a base can have multi-byte digits.
func symbolCount(converted string, base *convertbase.Base) (int, error) {
	symbols, err := base.Tokenize(converted)
	if err != nil {
		return 0, fmt.Errorf("tokenize %q in base %s: %w", converted, base.Name(), err)
	}
	return len(symbols), nil
}

// WidthFor is the symbol count a base needs to carry any timestamp up to the
// horizon, in the precision's unit. For 32w that pads with '2', because its
// alphabet starts at '2' - looks wrong at a glance, is not.
func WidthFor(radix int, precision Precision) (int, error) {
	divisor, err := precision.msPerUnit()
	if err != nil {
		return 0, err
	}
	horizon := uint64(horizonMs / divisor)
	width, capacity := 1, uint64(radix)
	for capacity <= horizon {
		capacity *= uint64(radix)
		width++
	}
	return width, nil
}

// widthForBits is the same derivation for the components whose largest value
// is a bit width rather than a date: the MAC's 48 and the UUID's 128. Those
// overflow uint64, hence the big integer.
func widthForBits(radix, bits int) int {
	largest := new(big.Int).Lsh(big.NewInt(1), uint(bits))
	largest.Sub(largest, big.NewInt(1))
	step := big.NewInt(int64(radix))
	capacity := new(big.Int).Set(step)
	width := 1
	for capacity.Cmp(largest) <= 0 {
		capacity.Mul(capacity, step)
		width++
	}
	return width
}

// -- live sources ------------------------------------------------------------

func liveHostname() (string, error) {
	name, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("host name: %w", err)
	}
	// os.Hostname can already be qualified; %h is the short form.
	if cut := strings.IndexByte(name, '.'); cut > 0 {
		name = name[:cut]
	}
	return name, nil
}

func liveUsername() (string, error) {
	if current, err := user.Current(); err == nil && current.Username != "" {
		return current.Username, nil
	}
	for _, key := range []string{"USER", "LOGNAME", "USERNAME"} {
		if name := os.Getenv(key); name != "" {
			return name, nil
		}
	}
	return "", errors.New("no user name available")
}

// liveFQDN is best-effort. A host with no domain has no qualified name to
// find, and falling back to the short name beats failing the identifier.
func liveFQDN() (string, error) {
	name, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("host name: %w", err)
	}
	if strings.Contains(name, ".") {
		return name, nil
	}
	if cname, err := net.LookupCNAME(name); err == nil {
		if qualified := strings.TrimSuffix(cname, "."); strings.Contains(qualified, ".") {
			return qualified, nil
		}
	}
	return name, nil
}

// liveMAC takes the lowest-numbered non-loopback interface carrying an EUI-48.
// The predecessor picked the interface holding the default route, which needs
// the routing table on three platforms; interface order is stable enough for a
// value whose only job is to differ between hosts.
func liveMAC() ([]byte, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, fmt.Errorf("network interfaces: %w", err)
	}
	var chosen *net.Interface
	for i := range interfaces {
		candidate := &interfaces[i]
		if candidate.Flags&net.FlagLoopback != 0 || len(candidate.HardwareAddr) != macBits/8 {
			continue
		}
		if chosen == nil || candidate.Index < chosen.Index {
			chosen = candidate
		}
	}
	if chosen == nil {
		return nil, errors.New("no non-loopback interface with a hardware address")
	}
	return chosen.HardwareAddr, nil
}
