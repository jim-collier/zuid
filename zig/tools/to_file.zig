// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! Build helper: `to_file <output> <command> [args...]` runs the command with
//! its stdout going straight into the output file. build.zig runs
//! `zig translate-c` through it rather than capturing stdout, because Zig
//! 0.17.0 on macOS spins forever copying its result into a pipe.
//!
//! It also drops SOURCE_DATE_EPOCH, which translate-c refuses unless it is a
//! number. Doing that in build.zig copied the whole environment into the
//! step's cache key, so any change to it translated again and rebuilt
//! everything, with new cache paths in the debug info.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) std.process.fatal("usage: to_file <output> <command> [args...]", .{});

    const out = std.Io.Dir.cwd().createFile(io, args[1], .{}) catch |err|
        std.process.fatal("cannot create {s}: {t}", .{ args[1], err });
    defer out.close(io);

    _ = init.environ_map.swapRemove("SOURCE_DATE_EPOCH");
    var child = std.process.spawn(io, .{ .argv = args[2..], .stdout = .{ .file = out }, .environ_map = init.environ_map }) catch |err|
        std.process.fatal("cannot run {s}: {t}", .{ args[2], err });
    switch (try child.wait(io)) {
        .exited => |code| if (code != 0) std.process.exit(code),
        else => std.process.exit(1),
    }
}
