// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! The one place the wall clock is read. Everything downstream takes the
//! milliseconds as a parameter - injectable time is the basis of the shared
//! vectors, so reading the clock at point of use would make this untestable.

const c = @cImport({
    @cInclude("time.h");
});

/// Milliseconds since the Unix epoch, UTC, or null if the clock cannot be
/// read. Goes through libc because the library links it for Wasmtime anyway,
/// and 0.16's std clock wants an Io instance the C module has no business
/// owning.
///
/// The failure case is checked rather than ignored: the timespec is left
/// uninitialized on a failed call, so arithmetic over it would emit a wrong
/// identifier instead of reporting anything.
pub fn nowMs() ?i64 {
    var ts: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_REALTIME, &ts) != 0) return null;
    return @as(i64, ts.tv_sec) * 1000 + @divTrunc(@as(i64, ts.tv_nsec), 1_000_000);
}
