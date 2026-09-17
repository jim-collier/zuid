//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	SPDX-License-Identifier: Apache-2.0

package zuid_test

import (
	"testing"
	"time"

	"github.com/jim-collier/zuid/go/zuid"
)

// steadyBytes hands back the same byte forever, so two identical requests
// render identically even when the format draws random data. A spent reader
// would fail the second call instead.
type steadyBytes struct{ fill byte }

func (s steadyBytes) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = s.fill
	}
	return len(p), nil
}

// The format string and the base name are the two parts of a request that
// arrive verbatim from whoever is calling, and the format is parsed here rather
// than by anything that has seen it before. Run as an ordinary test this
// replays the seeds; a real run is:
//
//	go test -run=xxx -fuzz=FuzzGenerate -fuzztime=30s ./zuid
func FuzzGenerate(f *testing.F) {
	for _, format := range []string{"%d", "%", "%%", "%z", "%d-%h-%u-%f-%m-%g-%r", "%%%%%d", "\x00%d", "%\xff"} {
		f.Add(format, "62")
	}
	f.Add("%d", "2048tz")
	f.Add("%d", "98keyboard")
	f.Add("%h", "")
	f.Add("%d", "no-such-base")

	generator, err := zuid.New(
		zuid.WithFixedTime(time.UnixMilli(946684800000).UTC()),
		zuid.WithHostname("testhost"),
		zuid.WithUsername("testuser"),
		zuid.WithFQDN("testhost.example.com"),
		zuid.WithMAC([]byte{0x02, 0x00, 0x5e, 0x10, 0x00, 0x00}),
		zuid.WithRandom(steadyBytes{fill: 0x5a}),
	)
	if err != nil {
		f.Fatalf("new generator: %v", err)
	}

	f.Fuzz(func(t *testing.T, format, base string) {
		request := zuid.Request{Format: format, Base: base}
		id, err := generator.Generate(request)
		if err != nil {
			if id != "" {
				t.Errorf("format %q base %q: failed with %q still returned", format, base, id)
			}
			return
		}
		again, err := generator.Generate(request)
		if err != nil {
			t.Errorf("format %q base %q: worked once, then failed: %v", format, base, err)
		}
		if again != id {
			t.Errorf("format %q base %q: %q then %q from the same inputs", format, base, id, again)
		}
	})
}
