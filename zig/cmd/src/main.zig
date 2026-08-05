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
    \\    -f, --format <fmt>   Format string (default "%d"). See below.
    \\    -p, --precision <n>  Time precision: -1 minute, 0 second, 1 millisecond
    \\                         (default 0).
    \\        --no-hash        Emit the host, user, and FQDN names literally
    \\                         instead of hashing them.
    \\        --hash-chars <n> Symbols kept from a hashed component (default 8).
    \\        --rand-chars <n> Symbols %r emits (default 6).
    \\    -h, --help           This.
    \\    -v, --version        Version and copyright.
    \\
    \\Format components:
    \\    %d  Time, as the count of units since the Unix epoch, UTC.
    \\    %h  Short host name, hashed by default.
    \\    %u  User name, hashed by default.
    \\    %f  Fully-qualified host and domain name, hashed by default.
    \\    %m  Hardware address of the lowest-numbered non-loopback interface.
    \\    %g  A UUID v4, rendered as the 128-bit number it is.
    \\    %r  Random symbols from a cryptographic source.
    \\    %%  A literal '%'. Anything else in the format goes out as itself.
    \\
    \\Every component but an unhashed %h, %u, or %f is a fixed number of symbols
    \\wide, zero-padded, so identifiers sort chronologically as plain text (byte
    \\order; use LC_COLLATE=C) and can be split by offset. Different bases or
    \\precisions have different widths and do not sort against each other - pick
    \\one combination per use-case.
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

    var opts = zuid.core.Options{ .clock_ms = 0 };
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
            opts.base = args[i];
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i == args.len) return die(stderr, "Expecting a format string after {s}.", .{arg});
            opts.format = args[i];
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--precision")) {
            i += 1;
            if (i == args.len) return die(stderr, "Expecting -1, 0, or 1 after {s}.", .{arg});
            const parsed = std.fmt.parseInt(i64, args[i], 10) catch {
                return die(stderr, "Precision '{s}' is not a number. Want -1 (minute), 0 (second), or 1 (millisecond).", .{args[i]});
            };
            opts.precision = zuid.core.Precision.fromInt(parsed) orelse {
                return die(stderr, "Precision {d} is out of range. Want -1 (minute), 0 (second), or 1 (millisecond).", .{parsed});
            };
        } else if (std.mem.eql(u8, arg, "--no-hash")) {
            opts.no_hash = true;
        } else if (std.mem.eql(u8, arg, "--hash-chars")) {
            i += 1;
            opts.hash_chars = charCount(stderr, args, i, arg);
        } else if (std.mem.eql(u8, arg, "--rand-chars")) {
            i += 1;
            opts.random_chars = charCount(stderr, args, i, arg);
        } else {
            return die(stderr, "Argument invalid or not expected: '{s}'. Try --help.", .{arg});
        }
    }
    opts.clock_ms = zuid.clock.nowMs();

    var wasm_host = zuid.host.Host.init(.auto) catch |err| {
        return die(stderr, "The embedded wasm runtime failed to start: {t}.", .{err});
    };
    defer wasm_host.deinit();
    var live: zuid.env.Live = .{};

    var out_buf: [zuid.core.out_buf_len]u8 = undefined;
    const id = zuid.core.generate(wasm_host.converter(), live.env(), opts, &out_buf) catch |err| {
        const detail = wasm_host.lastError();
        if (detail.len > 0) {
            return die(stderr, "{s}", .{detail});
        }
        return switch (err) {
            error.UnknownComponent => die(stderr, "Unknown format component. Known: %d %h %u %f %m %g %r, and %% for a literal.", .{}),
            error.BareFormatPercent => die(stderr, "The format string ends on a bare '%'.", .{}),
            error.ClockBeforeEpoch => die(stderr, "The clock predates the Unix epoch.", .{}),
            error.EnvUnavailable => die(stderr, "This machine could not supply that component - no name, hardware address, or random source.", .{}),
            error.OptionRange => die(stderr, "A symbol count is out of range. Want 1 to {d}.", .{zuid.core.max_component_chars}),
            else => die(stderr, "Generation failed: {t}.", .{err}),
        };
    };

    try stdout.print("{s}\n", .{id});
    try stdout.flush();
}

fn charCount(stderr: *std.Io.Writer, args: []const []const u8, i: usize, flag: []const u8) u32 {
    if (i == args.len) return die(stderr, "Expecting a symbol count after {s}.", .{flag});
    const parsed = std.fmt.parseInt(u32, args[i], 10) catch {
        return die(stderr, "'{s}' is not a symbol count. Want 1 to {d}.", .{ args[i], zuid.core.max_component_chars });
    };
    if (parsed < 1 or parsed > zuid.core.max_component_chars) {
        return die(stderr, "{d} is out of range for {s}. Want 1 to {d}.", .{ parsed, flag, zuid.core.max_component_chars });
    }
    return parsed;
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
