//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"testing"

	"github.com/jim-collier/zuid/go/zuid"
)

// Building the base registry is the one expensive thing in the package, and it
// happens once per generator rather than once per identifier. This is what
// says so.
func BenchmarkNew(b *testing.B) {
	for b.Loop() {
		if _, err := zuid.New(); err != nil {
			b.Fatalf("new generator: %v", err)
		}
	}
}

// The per-identifier cost, component by component, which is what the profiler
// stage runs against.
func BenchmarkGenerate(b *testing.B) {
	generator, err := zuid.New()
	if err != nil {
		b.Fatalf("new generator: %v", err)
	}
	for _, format := range []string{"%d", "%h", "%u", "%m", "%g", "%r", "%d%h%u%f%m%g%r"} {
		b.Run(format, func(b *testing.B) {
			request := zuid.Request{Format: format}
			for b.Loop() {
				if _, err := generator.Generate(request); err != nil {
					b.Fatalf("generate %s: %v", format, err)
				}
			}
		})
	}
}

// The wide bases take the multi-byte path through tokenize and fit, which is a
// different shape of work from the byte-per-symbol bases.
func BenchmarkGenerateWideBase(b *testing.B) {
	generator, err := zuid.New()
	if err != nil {
		b.Fatalf("new generator: %v", err)
	}
	request := zuid.Request{Format: "%d%h%g%r", Base: "2048tz"}
	for b.Loop() {
		if _, err := generator.Generate(request); err != nil {
			b.Fatalf("generate: %v", err)
		}
	}
}
