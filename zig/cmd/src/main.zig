// Copyright © 2026 Jim Collier
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! The zuid command. A thin surface over the library: every invocation also
//! exercises the upstream wasm module through the embedded runtime, so using
//! this doubles as ongoing validation of that artifact.

const std = @import("std");
const zuid = @import("zuid");

const help_text =
    \\Generates short, sortable, privacy-preserving unique identifiers.
    \\
    \\Syntax: zuid [options]
    \\
    \\Options:
    \\    -b, --base <name>    Output base: 16, 32w, 36, or 62 (default 62).
    \\                         Any base the conversion library knows is also
    \\                         accepted, including ones that do not sort.
    \\    -f, --format <fmt>   Format string (default "%d"). %d is the time
    \\                         component; %% is a literal '%'. %h %u %f %m %g %r
    \\                         are reserved and not implemented yet.
    \\    -h, --help           This.
    \\    -v, --version        Version and copyright.
    \\
    \\Output is zero-padded to a fixed width per base, so identifiers sort
    \\chronologically as plain text (byte order; use LC_COLLATE=C).
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_fw: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_fw: std.Io.File.Writer = .init(.stderr(), io, &stderr_buf);
    const stderr = &stderr_fw.interface;

    const args = try init.minimal.args.toSlice(arena);

    var base: []const u8 = "";
    var format: []const u8 = "%d";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printVersion(stdout);
            try stdout.print("\n{s}", .{help_text});
            try stdout.flush();
            return;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            try stdout.flush();
            return;
        } else if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--base")) {
            i += 1;
            if (i == args.len) return die(stderr, "Expecting a base name after {s}.", .{arg});
            base = args[i];
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i == args.len) return die(stderr, "Expecting a format string after {s}.", .{arg});
            format = args[i];
        } else {
            return die(stderr, "Argument invalid or not expected: '{s}'. Try --help.", .{arg});
        }
    }

    var host = zuid.host.Host.init(.auto) catch |err| {
        return die(stderr, "The embedded wasm runtime failed to start: {t}.", .{err});
    };
    defer host.deinit();

    var out_buf: [zuid.core.out_buf_len]u8 = undefined;
    const id = zuid.core.generate(host.converter(), format, base, zuid.clock.nowMs(), &out_buf) catch |err| {
        const detail = host.lastError();
        if (detail.len > 0) {
            return die(stderr, "{s}", .{detail});
        }
        return switch (err) {
            error.ReservedComponent => die(stderr, "That format component is reserved but not implemented yet.", .{}),
            error.UnknownComponent => die(stderr, "Unknown format component. Known: %d (%h %u %f %m %g %r are reserved).", .{}),
            error.BareFormatPercent => die(stderr, "The format string ends on a bare '%'.", .{}),
            error.ClockBeforeEpoch => die(stderr, "The clock predates the Unix epoch.", .{}),
            else => die(stderr, "Generation failed: {t}.", .{err}),
        };
    };

    try stdout.print("{s}\n", .{id});
    try stdout.flush();
}

fn printVersion(w: *std.Io.Writer) !void {
    try w.print(
        \\zuid version {s}
        \\Copyright (c) 2026 Jim Collier.
        \\License GPLv2+: GNU GPL version 2 or later, full text at:
        \\    https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
        \\There is no warranty, to the extent permitted by law.
        \\
    , .{zuid.version});
}

fn die(stderr: *std.Io.Writer, comptime fmt: []const u8, args: anytype) noreturn {
    stderr.print("zuid: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}
