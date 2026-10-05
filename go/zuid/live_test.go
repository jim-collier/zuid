//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

// Inside the package, because what it checks is the read counters, which are
// not part of the API. Everything else lives in the external zuid_test.
package zuid

import (
	"net"
	"testing"
)

// design.md says each environment source is read once per process and kept, and
// gives the reason: the FQDN read is a blocking name lookup, and a source that
// changed its answer mid-run would put two fingerprints on one machine.
//
// The host name was not actually wrapped, so %h re-read it for every identifier
// and could disagree with the cached %f.
// test-id: Eq9mpyS
func TestLiveSourcesReadOncePerProcess(t *testing.T) {
	cases := []struct {
		name  string
		reads func() int64
		call  func() error
	}{
		{"hostname", hostnameReads.Load, func() error { _, err := liveHostname(); return err }},
		{"username", usernameReads.Load, func() error { _, err := liveUsername(); return err }},
		{"fqdn", fqdnReads.Load, func() error { _, err := liveFQDN(); return err }},
		{"mac", macReads.Load, func() error { _, err := liveMAC(); return err }},
	}

	for _, each := range cases {
		t.Run(each.name, func(t *testing.T) {
			// Another test may have primed it already, so the first call here
			// is allowed to be the one real read - but only one of them can be.
			before := each.reads()
			for range 5 {
				// An error is fine. A machine with no MAC or no domain is
				// legitimate; what matters is that it is not asked twice.
				_ = each.call()
			}
			if got := each.reads() - before; got > 1 {
				t.Errorf("read the %s %d times, want at most 1 per process", each.name, got)
			}
		})
	}
}

// Two reads of the same source have to agree, which is the property the caching
// exists for: %h and %f describing one machine rather than two.
// test-id: Eq9mpyT
func TestLiveHostnameIsStable(t *testing.T) {
	first, err := liveHostname()
	if err != nil {
		t.Skipf("no host name here: %v", err)
	}
	second, err := liveHostname()
	if err != nil {
		t.Fatalf("second read failed after the first succeeded: %v", err)
	}
	if first != second {
		t.Errorf("host name changed between reads: %q then %q", first, second)
	}
}

// The T2 bridge address is the same on every Intel Mac that has one, and its
// interface numbers below en0, so it has to be passed over for the next one.
// test-id: ErU3R79
func TestPickMACSkipsSharedAddress(t *testing.T) {
	en0 := net.HardwareAddr{0x38, 0xf9, 0xd3, 0xc3, 0xd1, 0xad}
	interfaces := []net.Interface{
		{Index: 1, Name: "lo0", Flags: net.FlagLoopback},
		{Index: 4, Name: "en5", HardwareAddr: net.HardwareAddr{0xac, 0xde, 0x48, 0x00, 0x11, 0x22}},
		{Index: 6, Name: "en0", HardwareAddr: en0},
	}
	if got := pickMAC(interfaces); got.String() != en0.String() {
		t.Errorf("picked %v, want en0's %v", got, en0)
	}
	if got := pickMAC(interfaces[:2]); got != nil {
		t.Errorf("picked %v with only the shared address left, want none", got)
	}
}

// On Windows user.Current gives DOMAIN\name, and Zig's GetUserNameW the name
// alone. %u is the name alone on both.
// test-id: ErmqB7D
func TestBareAccountNameDropsDomain(t *testing.T) {
	cases := map[string]string{
		`VM925W\WinTest`: "WinTest",
		"ÅSA":            "ÅSA",
		`\wintest`:       "wintest",
	}
	for name, want := range cases {
		if got := bareAccountName(name); got != want {
			t.Errorf("bareAccountName(%q) = %q, want %q", name, got, want)
		}
	}
}
