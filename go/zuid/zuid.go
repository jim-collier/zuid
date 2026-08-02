//	Copyright © 2026 Jim Collier
//	Licensed under the Apache License, Version 2.0. Full text in ./LICENSE, or:
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

// horizonMs is the largest timestamp the fixed width has to hold: 2500-01-01
// UTC. Width is quantized so coarsely that moving this by a century or two
// usually changes nothing, which is why the exact value is not worth arguing
// over. Provisional - the padding horizon is still an open spec question.
const horizonMs = 16725225600000

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
func (g *Generator) Generate(format, baseName string) (string, error) {
	if baseName == "" {
		baseName = DefaultBase
	}
	base, err := g.registry.Lookup(baseName)
	if err != nil {
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
			rendered, err := g.timeComponent(base)
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

// timeComponent renders the clock as milliseconds since the Unix epoch UTC,
// padded to the fixed width for this base.
func (g *Generator) timeComponent(base *convertbase.Base) (string, error) {
	ms := g.now().UTC().UnixMilli()
	if ms < 0 {
		return "", fmt.Errorf("clock predates the Unix epoch: %d ms", ms)
	}
	return pad(strconv.FormatInt(ms, 10), g.decimal, base)
}

// pad converts a decimal string into base and left-fills it to the fixed width
// with that alphabet's zero digit. Lexicographic compare reads left to right,
// so a short identifier and a long one cannot sort chronologically - the fixed
// width is what makes the sort guarantee hold, not the choice of alphabet.
func pad(decimal string, from, to *convertbase.Base) (string, error) {
	converted, err := convertbase.Convert(decimal, from, to, -1)
	if err != nil {
		return "", fmt.Errorf("convert %s to base %s: %w", decimal, to.Name(), err)
	}

	// Count symbols, not bytes: a base can have multi-byte digits.
	symbols, err := to.Tokenize(converted)
	if err != nil {
		return "", fmt.Errorf("tokenize %q in base %s: %w", converted, to.Name(), err)
	}

	width := WidthFor(len(to.Symbols))
	if len(symbols) > width {
		return "", fmt.Errorf("value needs %d symbols in base %s, past the %d-symbol width",
			len(symbols), to.Name(), width)
	}
	return strings.Repeat(to.Symbols[0], width-len(symbols)) + converted, nil
}

// WidthFor is the symbol count a base needs to carry any timestamp up to the
// horizon. For 32w that pads with '2', because its alphabet starts at '2' -
// looks wrong at a glance, is not.
func WidthFor(radix int) int {
	width, capacity := 1, uint64(radix)
	for capacity <= horizonMs {
		capacity *= uint64(radix)
		width++
	}
	return width
}
