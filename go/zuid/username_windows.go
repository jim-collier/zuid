//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package zuid

import (
	"errors"
	"fmt"
	"syscall"
	"unsafe"
)

var lcMapStringEx = syscall.NewLazyDLL("kernel32.dll").NewProc("LCMapStringEx")

const lcmapLowercase = 0x00000100

// accountName is the name alone, lower-cased, since Windows ignores case in
// account names. It is lower-cased by the call the Zig side makes, not
// strings.ToLower, so a name outside ASCII comes out the same on both.
func accountName(name string) (string, error) {
	bare := bareAccountName(name)
	if bare == "" {
		return "", errors.New("no user name available")
	}
	if err := lcMapStringEx.Find(); err != nil {
		return "", fmt.Errorf("user name: %w", err)
	}
	source, err := syscall.UTF16FromString(bare)
	if err != nil {
		return "", fmt.Errorf("user name: %w", err)
	}
	// Without the terminating NUL, as the Zig side passes it.
	source = source[:len(source)-1]
	lower := make([]uint16, len(source))
	// LOCALE_NAME_INVARIANT is the empty string.
	invariant := []uint16{0}
	written, _, callErr := lcMapStringEx.Call(
		uintptr(unsafe.Pointer(&invariant[0])),
		lcmapLowercase,
		uintptr(unsafe.Pointer(&source[0])),
		uintptr(len(source)),
		uintptr(unsafe.Pointer(&lower[0])),
		uintptr(len(lower)),
		0, 0, 0,
	)
	if written == 0 {
		return "", fmt.Errorf("lower-casing the user name: %w", callErr)
	}
	return syscall.UTF16ToString(lower[:written]), nil
}
