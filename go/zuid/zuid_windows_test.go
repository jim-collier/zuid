//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package zuid

import (
	"strings"
	"testing"
)

// Windows ignores case in account names. env_windows.zig checks the same
// pairs, since both sides have to lower-case outside ASCII alike.
//
// test-id: ErmqB7E
func TestAccountNameIsLowerCased(t *testing.T) {
	cases := map[string]string{
		`VM925W\WinTest`:  "wintest",
		`KÖNIG\ÅSA.ÖBERG`: "åsa.öberg",
	}
	for name, want := range cases {
		got, err := accountName(name)
		if err != nil {
			t.Fatalf("accountName(%q): %v", name, err)
		}
		if got != want {
			t.Errorf("accountName(%q) = %q, want %q", name, got, want)
		}
	}

	live, err := liveUsername()
	if err != nil {
		t.Skipf("no user name here: %v", err)
	}
	if strings.Contains(live, `\`) {
		t.Errorf("live user name %q still has its domain", live)
	}
}
