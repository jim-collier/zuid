//	Copyright © 2026 Jim Collier
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

// Package zuid generates identifiers that sort chronologically as plain text.
//
// The identifier is a format string of components rendered into one output
// base. Only the time component (%d) is specified so far; the rest are
// reserved and reported as unimplemented rather than silently dropped.
//
// Base conversion is not done here. It comes from convertbase, which already
// carries the alphabets and the arbitrary-precision conversion. This package
// contributes the fixed-width padding that makes the result sortable.
package zuid

import (
	"errors"
	"fmt"
	"io"
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

// Generator renders identifiers. The clock and random source are fields rather
// than package-level calls so that output is reproducible under test - that is
// the whole basis of the shared vectors.
type Generator struct {
	registry *convertbase.Registry
	decimal  *convertbase.Base // input side of every conversion
	now      func() time.Time
	random   io.Reader
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

// WithRandom replaces the random source. Unused until the random component is
// specified, but wired now so the shape does not change later.
func WithRandom(source io.Reader) Option {
	return func(g *Generator) { g.random = source }
}

// New builds a Generator with the built-in base registry.
func New(opts ...Option) (*Generator, error) {
	registry, err := convertbase.NewRegistry()
	if err != nil {
		return nil, fmt.Errorf("base registry: %w", err)
	}
	decimal, err := registry.Lookup("10")
	if err != nil {
		return nil, fmt.Errorf("base 10: %w", err)
	}

	g := &Generator{registry: registry, decimal: decimal, now: time.Now}
	for _, opt := range opts {
		opt(g)
	}
	return g, nil
}

// Generate renders one identifier.
func (g *Generator) Generate(format, baseName string, precision Precision) (string, error) {
	if baseName == "" {
		baseName = DefaultBase
	}
	base, err := g.registry.Lookup(baseName)
	if err != nil {
		return "", err
	}
	if _, err := precision.msPerUnit(); err != nil {
		return "", err
	}

	var out strings.Builder
	for i := 0; i < len(format); i++ {
		if format[i] != '%' {
			out.WriteByte(format[i])
			continue
		}
		i++
		if i == len(format) {
			return "", errors.New("format ends on a bare '%'")
		}

		switch verb := format[i]; verb {
		case '%':
			out.WriteByte('%')
		case 'd':
			rendered, err := g.timeComponent(base, precision)
			if err != nil {
				return "", err
			}
			out.WriteString(rendered)
		case 'h', 'u', 'f', 'm', 'g', 'r':
			return "", fmt.Errorf("component %%%c is reserved but not implemented", verb)
		default:
			return "", fmt.Errorf("unknown component %%%c", verb)
		}
	}
	return out.String(), nil
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
	return pad(strconv.FormatInt(ms/divisor, 10), g.decimal, base, precision)
}

// pad converts a decimal string into base and left-fills it to the fixed width
// with that alphabet's zero digit. Lexicographic compare reads left to right,
// so a short identifier and a long one cannot sort chronologically - the fixed
// width is what makes the sort guarantee hold, not the choice of alphabet.
func pad(decimal string, from, to *convertbase.Base, precision Precision) (string, error) {
	converted, err := convertbase.Convert(decimal, from, to, -1)
	if err != nil {
		return "", fmt.Errorf("convert %s to base %s: %w", decimal, to.Name(), err)
	}

	// Count symbols, not bytes: a base can have multi-byte digits.
	symbols, err := to.Tokenize(converted)
	if err != nil {
		return "", fmt.Errorf("tokenize %q in base %s: %w", converted, to.Name(), err)
	}

	width, err := WidthFor(len(to.Symbols), precision)
	if err != nil {
		return "", err
	}
	if len(symbols) > width {
		return "", fmt.Errorf("value needs %d symbols in base %s, past the %d-symbol width",
			len(symbols), to.Name(), width)
	}
	return strings.Repeat(to.Symbols[0], width-len(symbols)) + converted, nil
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
