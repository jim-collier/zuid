//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid

// ResetCounter starts %c over, so a test sharing one Generator can replay a
// row from the first identifier of its tick.
func ResetCounter(g *Generator) {
	g.count.mu.Lock()
	defer g.count.mu.Unlock()
	g.count.started, g.count.next = false, 0
}

// WithCountAt has %c carry on from next within the tick that unixMilli falls
// in, which reaches the end of a tick without making a million identifiers.
func WithCountAt(unixMilli int64, precision Precision, next uint32) Option {
	return func(g *Generator) {
		divisor, _ := precision.msPerUnit()
		g.count.started, g.count.tick, g.count.precision, g.count.next = true, unixMilli/divisor, precision, next
	}
}
