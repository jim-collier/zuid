//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"bufio"
	"bytes"
	"encoding/hex"
	"os"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jim-collier/convert-base-v2/lib/convertbase"
	"github.com/jim-collier/zuid/go/zuid"
)

const vectorPath = "../../testdata/vectors.tsv"

// expectedVectorRows guards against a parsing bug that skips most of the file
// and then passes. Bump it when rows are added.
const expectedVectorRows = 190

// Injected state for one row. The defaults match the vectors file's header, so
// a row only spells out what it cares about.
type env struct {
	host   string
	user   string
	fqdn   string
	mac    string
	random []byte
}

func defaultEnv() env {
	return env{host: "testhost", user: "testuser", fqdn: "testhost.example.com", mac: "02005E100000"}
}

type vector struct {
	line     int
	name     string
	request  zuid.Request
	clockMs  int64
	env      env
	expected string
}

func parseEnv(t *testing.T, spec string, req *zuid.Request) env {
	t.Helper()

	result := defaultEnv()
	if spec == "-" {
		return result
	}
	for _, pair := range strings.Split(spec, ",") {
		key, value, ok := strings.Cut(pair, "=")
		if !ok {
			t.Fatalf("env %q: want key=value", pair)
		}
		var err error
		switch key {
		case "host":
			result.host = value
		case "user":
			result.user = value
		case "fqdn":
			result.fqdn = value
		case "mac":
			result.mac = value
		case "rand":
			result.random, err = hex.DecodeString(value)
		case "nohash":
			req.NoHash = value == "1"
		case "hashchars":
			req.HashChars, err = strconv.Atoi(value)
		case "randchars":
			req.RandomChars, err = strconv.Atoi(value)
		default:
			t.Fatalf("env %q: unknown key", key)
		}
		if err != nil {
			t.Fatalf("env %q: %v", pair, err)
		}
	}
	return result
}

func loadVectors(t *testing.T) []vector {
	t.Helper()

	file, err := os.Open(vectorPath)
	if err != nil {
		t.Fatalf("open vectors: %v", err)
	}
	defer file.Close()

	var vectors []vector
	scanner := bufio.NewScanner(file)
	for lineNo := 1; scanner.Scan(); lineNo++ {
		line := scanner.Text()
		if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 7 {
			t.Fatalf("%s:%d: want 7 tab-separated fields, got %d", vectorPath, lineNo, len(fields))
		}
		precision, err := strconv.Atoi(fields[3])
		if err != nil {
			t.Fatalf("%s:%d: precision: %v", vectorPath, lineNo, err)
		}
		clockMs, err := strconv.ParseInt(fields[4], 10, 64)
		if err != nil {
			t.Fatalf("%s:%d: clock_ms: %v", vectorPath, lineNo, err)
		}
		request := zuid.Request{Format: fields[1], Base: fields[2], Precision: zuid.Precision(precision)}
		injected := parseEnv(t, fields[5], &request) // also fills in the request's option fields
		vectors = append(vectors, vector{
			line: lineNo, name: fields[0], request: request, clockMs: clockMs,
			env: injected, expected: fields[6],
		})
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("read vectors: %v", err)
	}
	if len(vectors) == 0 {
		t.Fatal("no vectors loaded")
	}
	return vectors
}

// Building the base registry costs about 50 ms, so the whole file shares one
// generator and re-points its sources per row. Options are plain functions
// over a Generator, which is what makes that possible.
var oneGenerator = sync.OnceValues(func() (*zuid.Generator, error) { return zuid.New() })

func sharedGenerator(t *testing.T) *zuid.Generator {
	t.Helper()
	generator, err := oneGenerator()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	return generator
}

// A second generator, kept on its live sources, for the tests that check the
// machine is actually readable. Injecting into the shared one would leave a
// spent random reader behind for whichever test ran next.
var oneLiveGenerator = sync.OnceValues(func() (*zuid.Generator, error) { return zuid.New() })

func liveGenerator(t *testing.T) *zuid.Generator {
	t.Helper()
	generator, err := oneLiveGenerator()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	return generator
}

func applyEnv(t *testing.T, generator *zuid.Generator, at int64, e env) {
	t.Helper()
	address, err := hex.DecodeString(e.mac)
	if err != nil {
		t.Fatalf("mac %q: %v", e.mac, err)
	}
	for _, option := range []zuid.Option{
		zuid.WithFixedTime(time.UnixMilli(at).UTC()),
		zuid.WithHostname(e.host),
		zuid.WithUsername(e.user),
		zuid.WithFQDN(e.fqdn),
		zuid.WithMAC(address),
		zuid.WithRandom(bytes.NewReader(e.random)),
	} {
		option(generator)
	}
}

// The vectors are the spec. Both implementations reproduce every row.
func TestVectors(t *testing.T) {
	generator := sharedGenerator(t)
	vectors := loadVectors(t)
	if len(vectors) < expectedVectorRows {
		t.Fatalf("loaded %d vectors, want at least %d", len(vectors), expectedVectorRows)
	}
	for _, v := range vectors {
		applyEnv(t, generator, v.clockMs, v.env)
		got, err := generator.Generate(v.request)
		if err != nil {
			t.Errorf("line %d (%s): generate: %v", v.line, v.name, err)
			continue
		}
		if got != v.expected {
			t.Errorf("line %d (%s): base %s precision %d clock %d\n got %q\nwant %q",
				v.line, v.name, v.request.Base, v.request.Precision, v.clockMs, got, v.expected)
		}
	}
}

// Width is fixed per base and precision, whatever the timestamp. Without this
// the sort guarantee below cannot hold.
func TestFixedWidth(t *testing.T) {
	generator := sharedGenerator(t)
	clocks := []int64{0, 1, 946684800000, 1785585600000, 32503679999999}
	precisions := []zuid.Precision{zuid.PrecisionMinute, zuid.PrecisionSecond, zuid.PrecisionMilli}

	for _, base := range zuid.CuratedBases() {
		for _, precision := range precisions {
			widths := map[int]bool{}
			for _, ms := range clocks {
				applyEnv(t, generator, ms, defaultEnv())
				got, err := generator.Generate(zuid.Request{Base: base, Precision: precision})
				if err != nil {
					t.Fatalf("base %s precision %d clock %d: %v", base, precision, ms, err)
				}
				widths[len([]rune(got))] = true
			}
			if len(widths) != 1 {
				t.Errorf("base %s precision %d: widths vary across clocks: %v", base, precision, widths)
			}
		}
	}
}

// The same applies to the components whose width comes from a bit count rather
// than from the horizon: a low MAC and a high one have to render the same
// length, or an identifier cannot be split by offset.
func TestComponentsAreFixedWidth(t *testing.T) {
	generator := sharedGenerator(t)
	macs := []string{"000000000000", "000000000001", "02005E100000", "FFFFFFFFFFFF"}
	draws := []string{
		strings.Repeat("00", 32),
		strings.Repeat("FF", 32),
		"0F1E2D3C4B5A69788796A5B4C3D2E1F0A1B2C3D4E5F60F1E2D3C4B5A69788796",
	}

	for _, base := range zuid.CuratedBases() {
		for _, format := range []string{"%m", "%g", "%r", "%h"} {
			widths := map[int]bool{}
			for _, mac := range macs {
				for _, draw := range draws {
					e := defaultEnv()
					e.mac = mac
					bytesDrawn, err := hex.DecodeString(draw)
					if err != nil {
						t.Fatalf("draw %q: %v", draw, err)
					}
					e.random = bytesDrawn
					applyEnv(t, generator, 0, e)
					got, err := generator.Generate(zuid.Request{Format: format, Base: base})
					if err != nil {
						t.Fatalf("format %s base %s mac %s: %v", format, base, mac, err)
					}
					widths[len([]rune(got))] = true
				}
			}
			if len(widths) != 1 {
				t.Errorf("format %s base %s: widths vary: %v", format, base, widths)
			}
		}
	}
}

// The point of the whole exercise: byte-order sort has to match time order.
func TestSortsChronologically(t *testing.T) {
	generator := sharedGenerator(t)
	clocks := []int64{0, 60000, 946684800000, 1785585600000, 1785585660000, 32503679999999}
	precisions := []zuid.Precision{zuid.PrecisionMinute, zuid.PrecisionSecond, zuid.PrecisionMilli}

	for _, base := range zuid.CuratedBases() {
		for _, precision := range precisions {
			ordered := make([]string, 0, len(clocks))
			for _, ms := range clocks {
				e := defaultEnv()
				e.random = bytes.Repeat([]byte{0xA5}, 64)
				applyEnv(t, generator, ms, e)
				// A trailing random component must not disturb the ordering
				// the leading time component establishes.
				got, err := generator.Generate(zuid.Request{Format: "%d%r", Base: base, Precision: precision})
				if err != nil {
					t.Fatalf("base %s precision %d clock %d: %v", base, precision, ms, err)
				}
				ordered = append(ordered, got)
			}

			shuffled := slices.Clone(ordered)
			slices.Sort(shuffled)
			for i := range ordered {
				if ordered[i] != shuffled[i] {
					t.Errorf("base %s precision %d: sort order does not match time order\n time %v\nsorted %v",
						base, precision, ordered, shuffled)
					break
				}
			}
		}
	}
}

// A hashed component is a fingerprint: stable for one name, different for
// another, and not the name itself.
func TestHashedComponentsFingerprint(t *testing.T) {
	generator := sharedGenerator(t)
	render := func(host string) string {
		t.Helper()
		e := defaultEnv()
		e.host = host
		applyEnv(t, generator, 0, e)
		got, err := generator.Generate(zuid.Request{Format: "%h"})
		if err != nil {
			t.Fatalf("host %q: %v", host, err)
		}
		return got
	}

	first, again := render("alpha"), render("alpha")
	if first != again {
		t.Errorf("same host rendered %q then %q", first, again)
	}
	if other := render("beta"); other == first {
		t.Errorf("different hosts both rendered %q", first)
	}
	if strings.Contains(first, "alpha") {
		t.Errorf("hashed host %q still contains the name", first)
	}
	if want := zuid.DefaultHashChars(62); len([]rune(first)) != want {
		t.Errorf("hashed host %q is %d symbols, want %d", first, len([]rune(first)), want)
	}
}

// %r has to actually vary, or appending it to a same-tick timestamp buys
// nothing. Live generators read a cryptographic source.
func TestRandomVaries(t *testing.T) {
	generator := liveGenerator(t)
	seen := map[string]bool{}
	for i := 0; i < 64; i++ {
		got, err := generator.Generate(zuid.Request{Format: "%r"})
		if err != nil {
			t.Fatalf("generate: %v", err)
		}
		seen[got] = true
	}
	if len(seen) < 60 {
		t.Errorf("64 draws produced only %d distinct values", len(seen))
	}
}

func TestFormatErrors(t *testing.T) {
	generator := sharedGenerator(t)
	for _, format := range []string{"%", "%z"} {
		if _, err := generator.Generate(zuid.Request{Format: format, Base: "62"}); err == nil {
			t.Errorf("format %q: want an error, got none", format)
		}
	}
	if _, err := generator.Generate(zuid.Request{Base: "nonesuch"}); err == nil {
		t.Error("unknown base: want an error, got none")
	}
	if _, err := generator.Generate(zuid.Request{Precision: 2}); err == nil {
		t.Error("precision 2: want an error, got none")
	}
	for _, count := range []int{-1, zuid.MaxComponentChars + 1} {
		if _, err := generator.Generate(zuid.Request{Format: "%h", HashChars: count}); err == nil {
			t.Errorf("hash chars %d: want an error, got none", count)
		}
		if _, err := generator.Generate(zuid.Request{Format: "%r", RandomChars: count}); err == nil {
			t.Errorf("random chars %d: want an error, got none", count)
		}
	}
}

// Every component works in a base whose digits are several bytes each. This
// used to be refused outright, because slicing a converted string at a symbol
// boundary was not something the conversion library could do; Fit does it now,
// so the wide bases carry the truncating components as well as the padded
// ones. Widths are counted in symbols, which is the whole point - byte length
// says nothing here.
func TestMultiByteBaseComponents(t *testing.T) {
	registry, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatalf("registry: %v", err)
	}
	generator := sharedGenerator(t)
	e := defaultEnv()
	e.random = bytes.Repeat([]byte{0x5A}, 64)
	applyEnv(t, generator, 0, e)

	for _, baseName := range []string{"256tt", "512tt", "2048tz"} {
		base, err := registry.Lookup(baseName)
		if err != nil {
			t.Fatalf("lookup %s: %v", baseName, err)
		}
		timeWidth, err := zuid.WidthFor(len(base.Symbols), zuid.PrecisionSecond)
		if err != nil {
			t.Fatalf("width for %s: %v", baseName, err)
		}
		for _, tc := range []struct {
			format string
			want   int
		}{
			{"%d", timeWidth},
			{"%h", zuid.DefaultHashChars(len(base.Symbols))},
			{"%u", zuid.DefaultHashChars(len(base.Symbols))},
			{"%f", zuid.DefaultHashChars(len(base.Symbols))},
			{"%r", zuid.DefaultRandomChars(len(base.Symbols))},
		} {
			got, err := generator.Generate(zuid.Request{Format: tc.format, Base: baseName})
			if err != nil {
				t.Errorf("%s in base %s: %v", tc.format, baseName, err)
				continue
			}
			symbols, err := base.Tokenize(got)
			if err != nil {
				t.Errorf("%s in base %s: tokenize %q: %v", tc.format, baseName, got, err)
				continue
			}
			if len(symbols) != tc.want {
				t.Errorf("%s in base %s: got %d symbols, want %d", tc.format, baseName, len(symbols), tc.want)
			}
		}
	}
}

// A random draw has to fill the symbols it claims. One byte per symbol runs
// short above 256, where a symbol carries more than eight bits, and the
// shortfall shows up as a leading zero digit that never varies.
func TestRandomFillsWideBases(t *testing.T) {
	registry, err := convertbase.NewRegistry()
	if err != nil {
		t.Fatalf("registry: %v", err)
	}
	generator := sharedGenerator(t)

	for _, baseName := range []string{"512tt", "1024tz", "2048tz"} {
		base, err := registry.Lookup(baseName)
		if err != nil {
			t.Fatalf("lookup %s: %v", baseName, err)
		}
		leading := map[string]bool{}
		for seed := byte(0); seed < 32; seed++ {
			e := defaultEnv()
			e.random = bytes.Repeat([]byte{seed*8 + 1}, 64)
			applyEnv(t, generator, 0, e)
			got, err := generator.Generate(zuid.Request{Format: "%r", Base: baseName})
			if err != nil {
				t.Fatalf("%%r in base %s: %v", baseName, err)
			}
			symbols, err := base.Tokenize(got)
			if err != nil {
				t.Fatalf("tokenize %q in base %s: %v", got, baseName, err)
			}
			leading[symbols[0]] = true
		}
		if len(leading) == 1 {
			t.Errorf("base %s: the leading %%r symbol never varied, so the draw is short", baseName)
		}
	}
}

// An exhausted random source fails the identifier rather than quietly
// producing a short or repeated one.
func TestRandomSourceExhausted(t *testing.T) {
	generator := sharedGenerator(t)
	e := defaultEnv()
	e.random = []byte{1, 2, 3}
	applyEnv(t, generator, 0, e)
	if _, err := generator.Generate(zuid.Request{Format: "%r"}); err == nil {
		t.Error("short random source: want an error, got none")
	}
}

// Literals pass through, and %% escapes.
func TestLiteralsAndEscape(t *testing.T) {
	generator := sharedGenerator(t)
	applyEnv(t, generator, 0, defaultEnv())
	got, err := generator.Generate(zuid.Request{Format: "id-%d-%%", Base: "62"})
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	if want := "id-000000-%"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// Widths are derived from the horizon, not typed in. If the horizon moves,
// these move with it - so this pins the derivation, not the numbers.
func TestWidthForCuratedBases(t *testing.T) {
	want := map[zuid.Precision]map[int]int{
		zuid.PrecisionMinute: {16: 8, 32: 6, 36: 6, 62: 5},
		zuid.PrecisionSecond: {16: 9, 32: 7, 36: 7, 62: 6},
		zuid.PrecisionMilli:  {16: 12, 32: 9, 36: 9, 62: 8},
	}
	for precision, byRadix := range want {
		for radix, wantWidth := range byRadix {
			got, err := zuid.WidthFor(radix, precision)
			if err != nil {
				t.Fatalf("radix %d precision %d: %v", radix, precision, err)
			}
			if got != wantWidth {
				t.Errorf("radix %d precision %d: width %d, want %d", radix, precision, got, wantWidth)
			}
		}
	}
}

// A symbol is worth four bits in base 16 and eleven in 2048tz, so a fixed
// symbol count would mean wildly different strength per base. The default
// width is derived from the strength instead, and base 62 - the one the
// targets were taken from - stays where it was.
func TestDefaultWidthsCarryTheSameStrength(t *testing.T) {
	want := map[int]struct{ hash, random, ceiling int }{
		16:   {12, 9, 64},
		32:   {10, 7, 52},
		36:   {10, 7, 50},
		62:   {8, 6, 43},
		64:   {8, 6, 43},
		128:  {7, 5, 37},
		256:  {6, 5, 32},
		512:  {6, 4, 29},
		1024: {5, 4, 26},
		2048: {5, 4, 24},
	}
	for radix, w := range want {
		if got := zuid.DefaultHashChars(radix); got != w.hash {
			t.Errorf("radix %d: hash width %d, want %d", radix, got, w.hash)
		}
		if got := zuid.DefaultRandomChars(radix); got != w.random {
			t.Errorf("radix %d: random width %d, want %d", radix, got, w.random)
		}
		if got := zuid.MaxHashChars(radix); got != w.ceiling {
			t.Errorf("radix %d: digest ceiling %d, want %d", radix, got, w.ceiling)
		}
		// Every derived default has to sit inside both bounds, or asking for
		// nothing in particular would fail.
		if w.hash > w.ceiling || w.hash > zuid.MaxComponentChars {
			t.Errorf("radix %d: default hash width %d is past its own ceiling", radix, w.hash)
		}
	}
}

// Past the digest's own width the extra symbols are all left-fill, so the
// identifier grows without the fingerprint getting any stronger.
func TestHashWiderThanTheDigestIsRefused(t *testing.T) {
	generator := sharedGenerator(t)
	applyEnv(t, generator, 0, defaultEnv())
	for _, tc := range []struct {
		base    string
		ceiling int
	}{{"62", 43}, {"2048tz", 24}, {"16", 64}} {
		if _, err := generator.Generate(zuid.Request{Format: "%h", Base: tc.base, HashChars: tc.ceiling}); err != nil {
			t.Errorf("base %s at its ceiling of %d: %v", tc.base, tc.ceiling, err)
		}
		if tc.ceiling >= zuid.MaxComponentChars {
			continue // the option bound bites first, and is tested elsewhere
		}
		_, err := generator.Generate(zuid.Request{Format: "%h", Base: tc.base, HashChars: tc.ceiling + 1})
		if err == nil {
			t.Errorf("base %s accepted %d symbols of a 256-bit digest", tc.base, tc.ceiling+1)
		}
	}
	// Nothing is hashed with --no-hash, so the ceiling has nothing to say.
	if _, err := generator.Generate(zuid.Request{Format: "%h", Base: "2048tz", HashChars: 64, NoHash: true}); err != nil {
		t.Errorf("unhashed name refused for a hash width: %v", err)
	}
}

// The live sources have to work on the machine running the tests, or %h %u %f
// %m would only ever be exercised through injected values.
func TestLiveSources(t *testing.T) {
	generator := liveGenerator(t)
	for _, format := range []string{"%h", "%u", "%f", "%g", "%r"} {
		got, err := generator.Generate(zuid.Request{Format: format})
		if err != nil {
			t.Errorf("format %s: %v", format, err)
			continue
		}
		if got == "" {
			t.Errorf("format %s: empty output", format)
		}
	}
	// A machine with no network interface is legitimate, so %m is allowed to
	// fail - it just has to say so rather than render something wrong.
	if got, err := generator.Generate(zuid.Request{Format: "%m"}); err != nil {
		t.Logf("no MAC available here: %v", err)
	} else if len([]rune(got)) != 9 {
		t.Errorf("live MAC rendered %q, want 9 symbols in base 62", got)
	}
}

// The horizon is what the fixed width is derived from, so both sides of it
// need pinning: the last instant that fits, and the first that does not.
func TestClockHorizon(t *testing.T) {
	generator := sharedGenerator(t)
	horizon := time.Date(3000, time.January, 1, 0, 0, 0, 0, time.UTC)

	zuid.WithFixedTime(horizon.Add(-time.Millisecond))(generator)
	got, err := generator.Generate(zuid.Request{Precision: zuid.PrecisionMilli})
	if err != nil {
		t.Fatalf("horizon eve: %v", err)
	}
	if len([]rune(got)) != 8 {
		t.Errorf("horizon eve rendered %q, want 8 symbols in base 62", got)
	}

	for _, at := range []time.Time{
		horizon.AddDate(1000, 0, 0),
		time.Unix(1<<55, 0).UTC(), // far enough that UnixMilli wraps
	} {
		zuid.WithFixedTime(at)(generator)
		if got, err := generator.Generate(zuid.Request{Precision: zuid.PrecisionMilli}); err == nil {
			t.Errorf("clock %s: want an error past the horizon, got %q", at.Format(time.RFC3339), got)
		}
	}
}

// A clock before the epoch has no representation here, and must say so rather
// than render a negative count.
func TestClockBeforeEpoch(t *testing.T) {
	generator := sharedGenerator(t)
	for _, at := range []time.Time{time.UnixMilli(-1).UTC(), {}} {
		zuid.WithFixedTime(at)(generator)
		if got, err := generator.Generate(zuid.Request{}); err == nil {
			t.Errorf("clock %s: want an error before the epoch, got %q", at.Format(time.RFC3339), got)
		}
	}
}

// %m is a fixed 48 bits. Anything else is a caller mistake, and both the
// option and the component check for it.
func TestMACWrongLength(t *testing.T) {
	generator := sharedGenerator(t)
	for _, address := range [][]byte{nil, {}, {1, 2, 3, 4, 5}, {1, 2, 3, 4, 5, 6, 7}} {
		zuid.WithMAC(address)(generator)
		if got, err := generator.Generate(zuid.Request{Format: "%m"}); err == nil {
			t.Errorf("MAC of %d bytes: want an error, got %q", len(address), got)
		}
	}
}

// convertbase carries a base whose digits are raw byte values. It converts
// fine, which is the problem - an identifier made of control characters is not
// an identifier.
func TestRawByteBaseRejected(t *testing.T) {
	generator := sharedGenerator(t)
	zuid.WithFixedTime(time.UnixMilli(1785703406000).UTC())(generator)
	for _, format := range []string{"%d", "%h", "%g"} {
		if got, err := generator.Generate(zuid.Request{Format: format, Base: "bytes"}); err == nil {
			t.Errorf("format %s in base bytes: want an error, got %q", format, got)
		}
	}
}

// WidthFor is exported so a caller can size a buffer, which puts a nonsense
// radix within reach. Below 2 the derivation does not terminate.
func TestWidthForRejectsSmallRadix(t *testing.T) {
	for _, radix := range []int{-5, 0, 1} {
		if got, err := zuid.WidthFor(radix, zuid.PrecisionSecond); err == nil {
			t.Errorf("radix %d: want an error, got width %d", radix, got)
		}
	}
}

// Generate is documented as safe from several goroutines at once. Run under
// -race this is the only thing defending that claim.
func TestConcurrentGenerate(t *testing.T) {
	generator := liveGenerator(t)
	var waiting sync.WaitGroup
	for worker := 0; worker < 8; worker++ {
		waiting.Add(1)
		go func() {
			defer waiting.Done()
			for i := 0; i < 50; i++ {
				if _, err := generator.Generate(zuid.Request{Format: "%d%h%g%r"}); err != nil {
					t.Errorf("generate: %v", err)
					return
				}
			}
		}()
	}
	waiting.Wait()
}
