// Copyright © 2026 Jim Collier
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! The zuid command. A thin surface over the library: every invocation also
//! exercises the upstream wasm module through the embedded runtime, so using
//! this doubles as ongoing validation of that artifact.

const std = @import("std");
const zuid = @import("zuid");

/// The curated list, spelled out at compile time so help cannot drift from
/// what the library actually offers.
const curated_list = blk: {
    var joined: []const u8 = "";
    for (zuid.core.curated_bases, 0..) |base, i| {
        joined = joined ++ (if (i == 0) "" else ", ") ++ base;
    }
    break :blk joined;
};

const help_head =
    \\Generates short, sortable, privacy-preserving unique identifiers.
    \\
    \\Syntax: zuid [options]
    \\
    \\A value attaches to its flag with '=' or follows it as the next argument,
    \\so -b=32c, -b 32c, --base=32c, and --base 32c are all the same thing.
    \\
    \\Options:
    \\    -b, --base <name>    Output base (default 62). Curated set:
    \\
;

const help_tail =
    \\
    \\                         Any base the conversion library knows is also
    \\                         accepted, including ones that do not sort.
    \\    -f, --format <fmt>   Format string (default "%d"). See below.
    \\    -p, --precision <n>  Time precision: -1 minute, 0 second, 1 millisecond
    \\                         (default 0).
    \\        --no-hash        Emit the host, user, and FQDN names literally
    \\                         instead of hashing them.
    \\        --hash-chars <n> Symbols kept from a hashed component. The default
    \\                         is derived from the base, so that every base
    \\                         carries the same fingerprint strength rather than
    \\                         the same symbol count: 12 in base 16, 8 in 62, 5
    \\                         in 2048tz. Capped at what a SHA-256 fills there.
    \\        --rand-chars <n> Symbols %r emits, derived the same way: 9 in base
    \\                         16, 6 in 62, 4 in 2048tz.
    \\    -h, --help           This.
    \\    -v, --version        Version and copyright.
    \\
    \\Format components:
    \\    %d  Time, as the count of units since the Unix epoch, UTC.
    \\    %h  Short host name, hashed by default.
    \\    %u  User name, hashed by default.
    \\    %f  Fully-qualified host and domain name, hashed by default.
    \\    %m  Hardware address of the lowest-numbered non-loopback interface.
    \\        Linux only so far.
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

const help_text = help_head ++ "                         " ++ curated_list ++ "\n" ++ help_tail;

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

        // A value may ride along on the flag ("-b=32c") or follow it as the
        // next argument. Only split a leading-dash argument, so a format
        // string containing '=' passes through untouched.
        var name: []const u8 = arg;
        var attached: ?[]const u8 = null;
        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                name = arg[0..eq];
                attached = arg[eq + 1 ..];
            }
        }
        var vals: Values = .{ .args = args, .at = &i, .attached = attached, .stderr = stderr };

        if (std.mem.eql(u8, name, "-h") or std.mem.eql(u8, name, "--help")) {
            vals.rejectAttached(name);
            try printVersion(stdout);
            try stdout.print("\n{s}", .{help_text});
            try stdout.flush();
            return;
        } else if (std.mem.eql(u8, name, "-v") or std.mem.eql(u8, name, "--version")) {
            vals.rejectAttached(name);
            try printVersion(stdout);
            try stdout.flush();
            return;
        } else if (std.mem.eql(u8, name, "-b") or std.mem.eql(u8, name, "--base")) {
            opts.base = vals.take(name, "a base name");
        } else if (std.mem.eql(u8, name, "-f") or std.mem.eql(u8, name, "--format")) {
            opts.format = vals.take(name, "a format string");
        } else if (std.mem.eql(u8, name, "-p") or std.mem.eql(u8, name, "--precision")) {
            const raw = vals.take(name, "-1, 0, or 1");
            const parsed = std.fmt.parseInt(i64, raw, 10) catch {
                return die(stderr, "Precision '{s}' is not a number. Want -1 (minute), 0 (second), or 1 (millisecond).", .{raw});
            };
            opts.precision = zuid.core.Precision.fromInt(parsed) orelse {
                return die(stderr, "Precision {d} is out of range. Want -1 (minute), 0 (second), or 1 (millisecond).", .{parsed});
            };
        } else if (std.mem.eql(u8, name, "--no-hash")) {
            vals.rejectAttached(name);
            opts.no_hash = true;
        } else if (std.mem.eql(u8, name, "--hash-chars")) {
            opts.hash_chars = charCount(stderr, vals.take(name, "a symbol count"), name);
        } else if (std.mem.eql(u8, name, "--rand-chars")) {
            opts.random_chars = charCount(stderr, vals.take(name, "a symbol count"), name);
        } else {
            return die(stderr, "Argument invalid or not expected: '{s}'. Try --help.", .{arg});
        }
    }
    opts.clock_ms = zuid.clock.nowMs() orelse return die(stderr, "The system clock could not be read.", .{});

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
            error.BaseNotText => die(stderr, "That base renders raw bytes rather than text, so it cannot carry an identifier.", .{}),
            error.EnvUnavailable => die(stderr, "This machine could not supply that component - no name, hardware address, or random source.", .{}),
            error.OptionRange => die(stderr, "A symbol count is out of range. Want 1 to {d}.", .{zuid.core.max_component_chars}),
            error.HashTooWide => {
                // The ceiling moves with the base, so quote it rather than
                // leaving the caller to guess what would fit.
                const name = if (opts.base.len == 0) zuid.core.default_base else opts.base;
                const radix = wasm_host.converter().radix(name) catch
                    die(stderr, "A hashed component cannot be wider than a SHA-256 fills in base {s}.", .{name});
                die(stderr, "Hash width {d}: base {s} carries at most {d} symbols of a 256-bit digest.", .{ opts.hash_chars, name, zuid.core.maxHashChars(radix) });
            },
            else => die(stderr, "Generation failed: {t}.", .{err}),
        };
    };

    try stdout.print("{s}\n", .{id});
    try stdout.flush();
}

/// Resolves a flag's value from either spelling - attached with '=', or the
/// argument after it.
const Values = struct {
    args: []const [:0]const u8,
    at: *usize,
    attached: ?[]const u8,
    stderr: *std.Io.Writer,

    fn take(self: @This(), flag: []const u8, what: []const u8) []const u8 {
        if (self.attached) |v| return v;
        self.at.* += 1;
        if (self.at.* == self.args.len) die(self.stderr, "Expecting {s} after {s}.", .{ what, flag });
        return self.args[self.at.*];
    }

    fn rejectAttached(self: @This(), flag: []const u8) void {
        if (self.attached != null) die(self.stderr, "{s} takes no value.", .{flag});
    }
};

fn charCount(stderr: *std.Io.Writer, raw: []const u8, flag: []const u8) u32 {
    const parsed = std.fmt.parseInt(u32, raw, 10) catch {
        return die(stderr, "'{s}' is not a symbol count. Want 1 to {d}.", .{ raw, zuid.core.max_component_chars });
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
