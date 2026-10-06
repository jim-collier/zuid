//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"bufio"
	"bytes"
	"encoding/hex"
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
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
const expectedVectorRows = 201

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
		case "salt":
			req.Salt = value
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
// test-id: ElmNxqS
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
// test-id: ElmNxqT
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
// test-id: ElpGOHQ
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
// test-id: ElmNxqU
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
// test-id: ElpGOHR
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

// A salt is what stops someone holding identifiers from confirming a host name
// by hashing candidates. The vectors pin the values; this covers the edges.
// test-id: EqAI7se
func TestSalt(t *testing.T) {
	generator := sharedGenerator(t)
	render := func(req zuid.Request) string {
		t.Helper()
		applyEnv(t, generator, 0, defaultEnv())
		got, err := generator.Generate(req)
		if err != nil {
			t.Fatalf("salt %q: %v", req.Salt, err)
		}
		return got
	}

	plain := render(zuid.Request{Format: "%h"})
	salted := render(zuid.Request{Format: "%h", Salt: "pepper"})
	if plain == salted {
		t.Errorf("salted and unsalted host both rendered %q", plain)
	}
	if len([]rune(plain)) != len([]rune(salted)) {
		t.Errorf("salt changed the width: %q against %q", plain, salted)
	}
	// An empty salt hashes the name on its own, which is what keeps every
	// identifier generated before the salt existed valid.
	if empty := render(zuid.Request{Format: "%h", Salt: ""}); empty != plain {
		t.Errorf("empty salt rendered %q, want %q", empty, plain)
	}
	// A literal name never reads the salt.
	if literal := render(zuid.Request{Format: "%h", Salt: "pepper", NoHash: true}); literal != "testhost" {
		t.Errorf("unhashed host rendered %q, want the name itself", literal)
	}

	applyEnv(t, generator, 0, defaultEnv())
	if _, err := generator.Generate(zuid.Request{Format: "%h", Salt: strings.Repeat("s", zuid.MaxSaltBytes)}); err != nil {
		t.Errorf("salt of exactly %d bytes: %v", zuid.MaxSaltBytes, err)
	}
	applyEnv(t, generator, 0, defaultEnv())
	if _, err := generator.Generate(zuid.Request{Format: "%h", Salt: strings.Repeat("s", zuid.MaxSaltBytes+1)}); err == nil {
		t.Errorf("salt of %d bytes was accepted", zuid.MaxSaltBytes+1)
	}
}

// %r has to actually vary, or appending it to a same-tick timestamp buys
// nothing. Live generators read a cryptographic source.
// test-id: ElpGOHS
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

// test-id: ElmNxqV
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

// One failure per row: which refusal in testdata/errors.tsv it is, and the kind
// errors.Is has to find.
type errorCase struct {
	name    string
	refusal string
	opts    []zuid.Option
	req     zuid.Request
	want    error
}

var errorCases = []errorCase{
	{"unknown base", "unknown-base", nil, zuid.Request{Base: "nonesuch"}, zuid.ErrUnknownBase},
	{"bare percent", "bare-percent", nil, zuid.Request{Format: "%d%"}, zuid.ErrBadFormat},
	{"unknown component", "unknown-component", nil, zuid.Request{Format: "%z"}, zuid.ErrBadFormat},
	{"precision 2", "precision", nil, zuid.Request{Precision: 2}, zuid.ErrPrecision},
	{"hash width 65", "width-range", nil, zuid.Request{Format: "%h", HashChars: 65}, zuid.ErrOption},
	{"hash past the digest", "hash-too-wide", nil, zuid.Request{Format: "%h", Base: "2048tz", HashChars: 25}, zuid.ErrOption},
	{"random width -1", "width-range", nil, zuid.Request{Format: "%r", RandomChars: -1}, zuid.ErrOption},
	{"salt too long", "salt-too-long", nil, zuid.Request{Format: "%h", Salt: strings.Repeat("s", zuid.MaxSaltBytes+1)}, zuid.ErrOption},
	{"raw-byte base", "raw-byte-base", nil, zuid.Request{Base: "bytes"}, zuid.ErrBaseNotText},
	{"control digits", "control-char-base", nil, zuid.Request{Base: "98keyboard"}, zuid.ErrBaseNotText},
	{"before the epoch", "before-epoch", []zuid.Option{zuid.WithFixedTime(time.UnixMilli(-1).UTC())}, zuid.Request{}, zuid.ErrClock},
	{"past the horizon", "past-horizon", []zuid.Option{zuid.WithFixedTime(time.Date(4000, 1, 1, 0, 0, 0, 0, time.UTC))}, zuid.Request{}, zuid.ErrHorizon},
	{"random runs dry", "env", []zuid.Option{zuid.WithRandom(strings.NewReader(""))}, zuid.Request{Format: "%r"}, zuid.ErrEnv},
	{"short MAC", "env", []zuid.Option{zuid.WithMAC([]byte{1, 2, 3})}, zuid.Request{Format: "%m"}, zuid.ErrEnv},
	{"empty host name", "env", []zuid.Option{zuid.WithHostname("")}, zuid.Request{Format: "%h"}, zuid.ErrEnv},
}

func (tc errorCase) run(t *testing.T) error {
	t.Helper()
	at := zuid.WithFixedTime(time.UnixMilli(1785703406000).UTC())
	generator, err := zuid.New(append([]zuid.Option{at, zuid.WithHostname("h"), zuid.WithUsername("u"), zuid.WithFQDN("h.example")}, tc.opts...)...)
	if err != nil {
		t.Fatal(err)
	}
	_, err = generator.Generate(tc.req)
	return err
}

// Each failure is one kind a caller can test for with errors.Is, the same kinds
// the C module has codes for. Only one kind may match, and the kind is not
// prepended to the text, so a caller printing the error sees no change.
// test-id: Ersmdcw
func TestErrorKinds(t *testing.T) {
	kinds := []error{zuid.ErrUnknownBase, zuid.ErrBadFormat, zuid.ErrConvert, zuid.ErrClock,
		zuid.ErrPrecision, zuid.ErrOption, zuid.ErrEnv, zuid.ErrHorizon, zuid.ErrBaseNotText}
	for _, tc := range errorCases {
		err := tc.run(t)
		if !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", tc.name, err, tc.want)
			continue
		}
		for _, other := range kinds {
			if other != tc.want && errors.Is(err, other) {
				t.Errorf("%s: also matches %v", tc.name, other)
			}
		}
		if strings.HasPrefix(err.Error(), tc.want.Error()+":") {
			t.Errorf("%s: the kind changed the text: %q", tc.name, err)
		}
	}
}

const errorTablePath = "../../testdata/errors.tsv"

type refusal struct {
	cName    string
	goErr    string
	surfaces []string
	phrase   string
}

func readRefusals(t *testing.T) map[string]refusal {
	t.Helper()
	data, err := os.ReadFile(errorTablePath)
	if err != nil {
		t.Fatal(err)
	}
	rows := map[string]refusal{}
	for i, line := range strings.Split(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 7 {
			t.Fatalf("errors.tsv line %d: %d fields, want 7", i+1, len(fields))
		}
		if _, dup := rows[fields[0]]; dup {
			t.Fatalf("errors.tsv line %d: %s is there twice", i+1, fields[0])
		}
		rows[fields[0]] = refusal{
			cName:    fields[2],
			goErr:    fields[3],
			surfaces: strings.Split(fields[5], ","),
			phrase:   fields[6],
		}
	}
	return rows
}

// holdsPhrase reads ' ... ' in a phrase as a gap, and ignores case.
func holdsPhrase(message, phrase string) bool {
	rest := strings.ToLower(message)
	for _, part := range strings.Split(strings.ToLower(phrase), " ... ") {
		at := strings.Index(rest, part)
		if at < 0 {
			return false
		}
		rest = rest[at+len(part):]
	}
	return true
}

// The Err values as zuid.go declares them, each with the C name its comment
// gives. Read from the source so a new one cannot miss the table.
func declaredErrs(t *testing.T) map[string]string {
	t.Helper()
	file, err := parser.ParseFile(token.NewFileSet(), "zuid.go", nil, parser.ParseComments)
	if err != nil {
		t.Fatal(err)
	}
	found := map[string]string{}
	for _, decl := range file.Decls {
		gen, ok := decl.(*ast.GenDecl)
		if !ok || gen.Tok != token.VAR {
			continue
		}
		for _, spec := range gen.Specs {
			value := spec.(*ast.ValueSpec)
			for _, name := range value.Names {
				if name.IsExported() && strings.HasPrefix(name.Name, "Err") {
					found[name.Name] = strings.TrimSpace(value.Comment.Text())
				}
			}
		}
	}
	return found
}

// testdata/errors.tsv holds the three surfaces to one name and one phrase per
// failure. This is the Go side: every Err is in it under its C name, and every
// message Go words itself says the row's phrase.
// test-id: ErsxH5C
func TestErrorTable(t *testing.T) {
	rows := readRefusals(t)
	byName := map[string]error{
		"ErrUnknownBase": zuid.ErrUnknownBase, "ErrBadFormat": zuid.ErrBadFormat, "ErrConvert": zuid.ErrConvert,
		"ErrClock": zuid.ErrClock, "ErrPrecision": zuid.ErrPrecision, "ErrOption": zuid.ErrOption,
		"ErrEnv": zuid.ErrEnv, "ErrHorizon": zuid.ErrHorizon, "ErrBaseNotText": zuid.ErrBaseNotText,
	}
	declared := declaredErrs(t)
	for name := range declared {
		if _, ok := byName[name]; !ok {
			t.Errorf("zuid.go declares %s, which this test does not know", name)
		}
	}
	inTable := map[string]bool{}
	for label, row := range rows {
		if row.goErr == "-" {
			continue
		}
		inTable[row.goErr] = true
		cName, ok := declared[row.goErr]
		if !ok {
			t.Errorf("%s: zuid.go has no %s", label, row.goErr)
			continue
		}
		if cName != row.cName {
			t.Errorf("%s: %s is commented %q, the table says %s", label, row.goErr, cName, row.cName)
		}
	}
	for name := range declared {
		if !inTable[name] {
			t.Errorf("%s has no row in errors.tsv", name)
		}
	}

	covered := map[string]bool{}
	for _, tc := range errorCases {
		row, ok := rows[tc.refusal]
		if !ok {
			t.Errorf("%s: no row %q in errors.tsv", tc.name, tc.refusal)
			continue
		}
		covered[tc.refusal] = true
		if byName[row.goErr] != tc.want {
			t.Errorf("%s: the table says %s, the case wants %v", tc.name, row.goErr, tc.want)
		}
		err := tc.run(t)
		if err == nil {
			t.Errorf("%s: no error", tc.name)
			continue
		}
		if slices.Contains(row.surfaces, "go") && !holdsPhrase(err.Error(), row.phrase) {
			t.Errorf("%s: %q does not say %q", tc.name, err, row.phrase)
		}
	}
	for label, row := range rows {
		if slices.Contains(row.surfaces, "go") && !covered[label] {
			t.Errorf("%s: Go words it, but no case here reaches it", label)
		}
	}
}

// The text verdict is kept per base. A refused base stays refused on every
// call, whichever base was asked about first, and a good one keeps passing.
// test-id: Ersuqxd
func TestBaseVerdictPerBase(t *testing.T) {
	at := zuid.WithFixedTime(time.UnixMilli(1785703406000).UTC())
	orders := [][]string{
		{"62", "bytes", "62", "98keyboard", "2048tz", "bytes", "98keyboard", "62"},
		{"bytes", "62", "98keyboard", "2048tz", "bytes", "62", "98keyboard"},
		{"98keyboard", "bytes", "2048tz", "62", "98keyboard", "bytes"},
	}
	refused := map[string]bool{"bytes": true, "98keyboard": true}
	for _, order := range orders {
		generator, err := zuid.New(at)
		if err != nil {
			t.Fatal(err)
		}
		texts := map[string]string{}
		for i, name := range order {
			_, err := generator.Generate(zuid.Request{Base: name})
			if !refused[name] {
				if err != nil {
					t.Errorf("%v call %d, %s: %v", order, i, name, err)
				}
				continue
			}
			if !errors.Is(err, zuid.ErrBaseNotText) {
				t.Errorf("%v call %d, %s: got %v, want ErrBaseNotText", order, i, name, err)
				continue
			}
			if first, seen := texts[name]; seen && first != err.Error() {
				t.Errorf("%v call %d, %s: text moved from %q to %q", order, i, name, first, err.Error())
			}
			texts[name] = err.Error()
		}
	}
}

// 98keyboard counts tab, newline and return among its digits, so an identifier
// in it could carry a line break. Its zero digit is '0', which is why the
// alphabet gets read rather than just that one symbol.
// test-id: Eq9xBUe
func TestBaseWithControlDigitsIsRefused(t *testing.T) {
	generator := sharedGenerator(t)
	applyEnv(t, generator, 0, defaultEnv())
	for _, base := range []string{"98keyboard", "bytes"} {
		if _, err := generator.Generate(zuid.Request{Format: "%d", Base: base}); err == nil {
			t.Errorf("base %s: want an error, got none", base)
		}
	}
	if _, err := generator.Generate(zuid.Request{Format: "%d", Base: "62"}); err != nil {
		t.Errorf("base 62 refused: %v", err)
	}
}

// A width the format never reads cannot fail the call, so one hash width can
// serve every base a caller uses.
// test-id: Eq9xBUf
func TestUnusedWidthsAreNotChecked(t *testing.T) {
	generator := sharedGenerator(t)
	applyEnv(t, generator, 0, defaultEnv())
	for _, req := range []zuid.Request{
		{Format: "%d", HashChars: zuid.MaxComponentChars + 1, RandomChars: zuid.MaxComponentChars + 1},
		{Format: "%d", Base: "2048tz", HashChars: 40},
		{Format: "%h", Base: "2048tz", HashChars: 40, NoHash: true},
	} {
		if _, err := generator.Generate(req); err != nil {
			t.Errorf("%+v: %v", req, err)
		}
	}
}

// Every component works in a base whose digits are several bytes each. This
// used to be refused outright, because slicing a converted string at a symbol
// boundary was not something the conversion library could do; Fit does it now,
// so the wide bases carry the truncating components as well as the padded
// ones. Widths are counted in symbols, which is the whole point - byte length
// says nothing here.
// test-id: Em2hrcO
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
// test-id: Em2hrcP
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
// test-id: ElpGOHT
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
// test-id: ElmNxqW
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
// test-id: ElmNxqX
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
// test-id: Em3M9HE
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
// test-id: Em3M9HF
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
// test-id: ElpGOHU
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
// test-id: Em32NzU
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
// test-id: Em32NzV
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
// test-id: Em32NzW
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
// test-id: Em32NzX
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
// test-id: Em32NzY
func TestWidthForRejectsSmallRadix(t *testing.T) {
	for _, radix := range []int{-5, 0, 1} {
		if got, err := zuid.WidthFor(radix, zuid.PrecisionSecond); err == nil {
			t.Errorf("radix %d: want an error, got width %d", radix, got)
		}
	}
}

// Generate is documented as safe from several goroutines at once. Run under
// -race this is the only thing defending that claim.
// test-id: Em32NzZ
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
