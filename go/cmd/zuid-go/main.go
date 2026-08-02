//	Copyright © 2026 Jim Collier
//	Licensed under the GNU General Public License, version 2 or later.
//	SPDX-License-Identifier: GPL-2.0-or-later

// Command zuid-go renders identifiers from the Go implementation. It exists to
// drive differential tests against the Zig one, so it stays deliberately
// small - the shipped CLI is the Zig binary.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/jim-collier/zuid/go/zuid"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "zuid-go: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	format := flag.String("format", "%d", "format string selecting components")
	base := flag.String("base", zuid.DefaultBase,
		"output base; curated: "+strings.Join(zuid.CuratedBases, ", "))
	count := flag.Int("count", 1, "how many identifiers to emit")
	clockMs := flag.Int64("clock-ms", -1,
		"pin the clock to this many milliseconds since the Unix epoch UTC, for reproducible output")
	flag.Parse()

	if *count < 1 {
		return fmt.Errorf("count must be at least 1, got %d", *count)
	}

	var opts []zuid.Option
	if *clockMs >= 0 {
		opts = append(opts, zuid.WithFixedTime(time.UnixMilli(*clockMs).UTC()))
	}
	generator, err := zuid.New(opts...)
	if err != nil {
		return err
	}

	out := make([]string, 0, *count)
	for i := 0; i < *count; i++ {
		id, err := generator.Generate(*format, *base)
		if err != nil {
			return err
		}
		out = append(out, id)
	}
	_, err = fmt.Println(strings.Join(out, "\n"))
	return err
}
