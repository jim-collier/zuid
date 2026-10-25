//	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
//	Licensed under the Apache License, Version 2.0. Full text in go/LICENSE.txt, or:
//		https://spdx.org/licenses/Apache-2.0.html
//	SPDX-License-Identifier: Apache-2.0

package zuid

import (
	"testing"

	"go.uber.org/goleak"
)

// A goroutine still running once every test is done fails the run, whoever
// started it. Per-test VerifyNone doesn't mix with t.Parallel.
//
// test-id: de54c
func TestMain(m *testing.M) {
	goleak.VerifyTestMain(m)
}
