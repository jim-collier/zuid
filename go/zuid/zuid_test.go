//	Copyright © 2026 Jim Collier
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"bufio"
	"os"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jim-collier/zuid/go/zuid"
)

const vectorPath = "../../testdata/vectors.tsv"

type vector struct {
	line     int
	name     string
	format   string
	base     string
	clockMs  int64
	expected string
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
		if len(fields) != 5 {
			t.Fatalf("%s:%d: want 5 tab-separated fields, got %d", vectorPath, lineNo, len(fields))
		}
		clockMs, err := strconv.ParseInt(fields[3], 10, 64)
		if err != nil {
			t.Fatalf("%s:%d: clock_ms: %v", vectorPath, lineNo, err)
		}
		vectors = append(vectors, vector{
			line: lineNo, name: fields[0], format: fields[1],
			base: fields[2], clockMs: clockMs, expected: fields[4],
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

// The vectors are the spec. Both implementations reproduce every row.
func TestVectors(t *testing.T) {
	for _, v := range loadVectors(t) {
		t.Run(v.name+"/"+v.base, func(t *testing.T) {
			at := time.UnixMilli(v.clockMs).UTC()
			generator, err := zuid.New(zuid.WithFixedTime(at))
			if err != nil {
				t.Fatalf("new generator: %v", err)
			}
			got, err := generator.Generate(v.format, v.base)
			if err != nil {
				t.Fatalf("line %d: generate: %v", v.line, err)
			}
			if got != v.expected {
				t.Errorf("line %d: base %s clock %d\n got %q\nwant %q",
					v.line, v.base, v.clockMs, got, v.expected)
			}
		})
	}
}

// Width is fixed per base, whatever the timestamp. Without this the sort
// guarantee below cannot hold.
func TestFixedWidth(t *testing.T) {
	clocks := []int64{0, 1, 946684800000, 1785585600000, 16725225600000}

	for _, base := range zuid.CuratedBases {
		widths := map[int]bool{}
		for _, ms := range clocks {
			generator, err := zuid.New(zuid.WithFixedTime(time.UnixMilli(ms).UTC()))
			if err != nil {
				t.Fatalf("new generator: %v", err)
			}
			got, err := generator.Generate("%d", base)
			if err != nil {
				t.Fatalf("base %s clock %d: %v", base, ms, err)
			}
			widths[len([]rune(got))] = true
		}
		if len(widths) != 1 {
			t.Errorf("base %s: widths vary across clocks: %v", base, widths)
		}
	}
}

// The point of the whole exercise: byte-order sort has to match time order.
func TestSortsChronologically(t *testing.T) {
	clocks := []int64{0, 1, 999, 946684800000, 1785585600000, 1785585600001, 16725225600000}

	for _, base := range zuid.CuratedBases {
		ordered := make([]string, 0, len(clocks))
		for _, ms := range clocks {
			generator, err := zuid.New(zuid.WithFixedTime(time.UnixMilli(ms).UTC()))
			if err != nil {
				t.Fatalf("new generator: %v", err)
			}
			got, err := generator.Generate("%d", base)
			if err != nil {
				t.Fatalf("base %s clock %d: %v", base, ms, err)
			}
			ordered = append(ordered, got)
		}

		shuffled := append([]string(nil), ordered...)
		sort.Strings(shuffled)
		for i := range ordered {
			if ordered[i] != shuffled[i] {
				t.Errorf("base %s: sort order does not match time order\n time %v\nsorted %v",
					base, ordered, shuffled)
				break
			}
		}
	}
}

// Reserved components fail loudly. Silently dropping them would let a format
// string look like it worked.
func TestReservedComponentsRejected(t *testing.T) {
	generator, err := zuid.New()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	for _, format := range []string{"%h", "%u", "%f", "%m", "%g", "%r"} {
		if _, err := generator.Generate(format, "62"); err == nil {
			t.Errorf("format %q: want an error, got none", format)
		}
	}
}

func TestFormatErrors(t *testing.T) {
	generator, err := zuid.New()
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	for _, format := range []string{"%", "%z"} {
		if _, err := generator.Generate(format, "62"); err == nil {
			t.Errorf("format %q: want an error, got none", format)
		}
	}
	if _, err := generator.Generate("%d", "nonesuch"); err == nil {
		t.Error("unknown base: want an error, got none")
	}
}

// Literals pass through, and %% escapes.
func TestLiteralsAndEscape(t *testing.T) {
	generator, err := zuid.New(zuid.WithFixedTime(time.UnixMilli(0).UTC()))
	if err != nil {
		t.Fatalf("new generator: %v", err)
	}
	got, err := generator.Generate("id-%d-%%", "62")
	if err != nil {
		t.Fatalf("generate: %v", err)
	}
	if want := "id-00000000-%"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// Widths are derived from the horizon, not typed in. If the horizon moves,
// these move with it - so this pins the derivation, not the numbers.
func TestWidthForCuratedBases(t *testing.T) {
	for radix, want := range map[int]int{16: 11, 32: 9, 36: 9, 62: 8} {
		if got := zuid.WidthFor(radix); got != want {
			t.Errorf("radix %d: width %d, want %d", radix, got, want)
		}
	}
}
