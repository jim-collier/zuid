// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Replays testdata/vectors.tsv - the spec in executable form - through the
//! real wasm host, plus the error paths, the live environment, and the
//! module's own leak ledger. The vectors file is embedded at build time, so
//! the tests need no cwd.

const std = @import("std");
const core = @import("core.zig");
const host = @import("host.zig");
const env = @import("env.zig");
const capi = @import("capi.zig");

const vectors_tsv = @embedFile("vectors.tsv");

test "core unit tests" {
    _ = core;
}

/// Everything a vector row can pin down. The defaults match the vectors
/// file's header, so a row only spells out what it cares about.
const FixedEnv = struct {
    host: []const u8 = "testhost",
    user: []const u8 = "testuser",
    fqdn: []const u8 = "testhost.example.com",
    mac: [6]u8 = .{ 0x02, 0x00, 0x5e, 0x10, 0x00, 0x00 },
    /// Decoded rand= bytes, and how far %g and %r have drawn into them.
    random: [core.max_component_chars * 2]u8 = undefined,
    random_len: usize = 0,
    drawn: usize = 0,

    fn interface(self: *FixedEnv) core.Env {
        return .{ .ctx = self, .vtable = &vtable };
    }

    const vtable = core.Env.VTable{
        .hostname = vtHostname,
        .username = vtUsername,
        .fqdn = vtFqdn,
        .mac = vtMac,
        .randomBytes = vtRandomBytes,
    };

    fn vtHostname(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
        return copy(cast(ctx).host, out);
    }
    fn vtUsername(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
        return copy(cast(ctx).user, out);
    }
    fn vtFqdn(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
        return copy(cast(ctx).fqdn, out);
    }
    fn vtMac(ctx: *anyopaque) core.Error![6]u8 {
        return cast(ctx).mac;
    }
    fn vtRandomBytes(ctx: *anyopaque, out: []u8) core.Error!void {
        const self = cast(ctx);
        if (self.drawn + out.len > self.random_len) return core.Error.EnvUnavailable;
        @memcpy(out, self.random[self.drawn .. self.drawn + out.len]);
        self.drawn += out.len;
    }

    fn cast(ctx: *anyopaque) *FixedEnv {
        return @ptrCast(@alignCast(ctx));
    }
    fn copy(text: []const u8, out: []u8) core.Error![]const u8 {
        if (text.len > out.len) return core.Error.BufferTooSmall;
        @memcpy(out[0..text.len], text);
        return out[0..text.len];
    }
};

fn hexNibble(char: u8) !u8 {
    return switch (char) {
        '0'...'9' => char - '0',
        'A'...'F' => char - 'A' + 10,
        'a'...'f' => char - 'a' + 10,
        else => error.BadVectorRow,
    };
}

/// Applies one row's env column to a FixedEnv and the options it carries.
fn applyEnv(spec: []const u8, fixed: *FixedEnv, opts: *core.Options) !void {
    if (std.mem.eql(u8, spec, "-")) return;
    var pairs = std.mem.splitScalar(u8, spec, ',');
    while (pairs.next()) |pair| {
        const split = std.mem.indexOfScalar(u8, pair, '=') orelse return error.BadVectorRow;
        const key = pair[0..split];
        const value = pair[split + 1 ..];
        if (std.mem.eql(u8, key, "host")) {
            fixed.host = value;
        } else if (std.mem.eql(u8, key, "user")) {
            fixed.user = value;
        } else if (std.mem.eql(u8, key, "fqdn")) {
            fixed.fqdn = value;
        } else if (std.mem.eql(u8, key, "mac")) {
            if (value.len != 12) return error.BadVectorRow;
            for (0..6) |i| {
                fixed.mac[i] = try hexNibble(value[i * 2]) << 4 | try hexNibble(value[i * 2 + 1]);
            }
        } else if (std.mem.eql(u8, key, "rand")) {
            if (value.len % 2 != 0 or value.len / 2 > fixed.random.len) return error.BadVectorRow;
            for (0..value.len / 2) |i| {
                fixed.random[i] = try hexNibble(value[i * 2]) << 4 | try hexNibble(value[i * 2 + 1]);
            }
            fixed.random_len = value.len / 2;
        } else if (std.mem.eql(u8, key, "nohash")) {
            opts.no_hash = std.mem.eql(u8, value, "1");
        } else if (std.mem.eql(u8, key, "hashchars")) {
            opts.hash_chars = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "randchars")) {
            opts.random_chars = try std.fmt.parseInt(u32, value, 10);
        } else {
            return error.BadVectorRow;
        }
    }
}

// One host for the whole file: init costs more than every row combined.
// Both compile strategies are exercised, because a winch miscompile would
// otherwise only surface in production.
test "vectors reproduce through the wasm module, both strategies" {
    for ([_]host.Strategy{ .winch, .auto }) |strategy| {
        var h = host.Host.init(strategy) catch |err| switch (err) {
            // Winch does not support every target; auto still covers the row.
            error.ModuleInvalid => continue,
            else => return err,
        };
        defer h.deinit();
        try runVectors(&h);
        try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
    }
}

fn runVectors(h: *host.Host) !void {
    var rows: usize = 0;
    var lines = std.mem.splitScalar(u8, vectors_tsv, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const name = fields.next() orelse return error.BadVectorRow;
        const format = fields.next() orelse return error.BadVectorRow;
        const base = fields.next() orelse return error.BadVectorRow;
        const precision_field = fields.next() orelse return error.BadVectorRow;
        const clock_field = fields.next() orelse return error.BadVectorRow;
        const env_field = fields.next() orelse return error.BadVectorRow;
        const expected = fields.next() orelse return error.BadVectorRow;

        var opts = core.Options{
            .format = format,
            .base = base,
            .precision = core.Precision.fromInt(try std.fmt.parseInt(i64, precision_field, 10)) orelse
                return error.BadVectorRow,
            .clock_ms = try std.fmt.parseInt(i64, clock_field, 10),
        };
        var fixed = FixedEnv{};
        try applyEnv(env_field, &fixed, &opts);

        var out_buf: [core.out_buf_len]u8 = undefined;
        const got = core.generate(h.converter(), fixed.interface(), opts, &out_buf) catch |err| {
            std.debug.print("vector {s} ({s}, base {s}): {t}: {s}\n", .{ name, format, base, err, h.lastError() });
            return err;
        };
        std.testing.expectEqualStrings(expected, got) catch |err| {
            std.debug.print("vector {s} (base {s}, precision {s}, clock {s})\n", .{ name, base, precision_field, clock_field });
            return err;
        };
        rows += 1;
    }
    // A parsing bug that skips every row would otherwise pass silently.
    try std.testing.expect(rows >= 187);
}

test "error paths carry the module's error text" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed = FixedEnv{};
    const e = fixed.interface();
    var out_buf: [core.out_buf_len]u8 = undefined;

    // Unknown base: the module's text includes near-match suggestions.
    try std.testing.expectError(error.UnknownBase, core.generate(h.converter(), e, .{ .base = "hexx", .clock_ms = 0 }, &out_buf));
    try std.testing.expect(h.lastError().len > 0);

    try std.testing.expectError(error.UnknownComponent, core.generate(h.converter(), e, .{ .format = "%z", .clock_ms = 0 }, &out_buf));
    try std.testing.expectError(error.BareFormatPercent, core.generate(h.converter(), e, .{ .format = "abc%", .clock_ms = 0 }, &out_buf));
    try std.testing.expectError(error.ClockBeforeEpoch, core.generate(h.converter(), e, .{ .clock_ms = -1 }, &out_buf));
    try std.testing.expectError(error.OptionRange, core.generate(h.converter(), e, .{ .clock_ms = 0, .hash_chars = 0 }, &out_buf));
    try std.testing.expectError(error.OptionRange, core.generate(h.converter(), e, .{ .clock_ms = 0, .random_chars = 65 }, &out_buf));

    // An exhausted random source fails the identifier rather than quietly
    // producing a short or repeated one.
    try std.testing.expectError(error.EnvUnavailable, core.generate(h.converter(), e, .{ .format = "%r", .clock_ms = 0 }, &out_buf));

    // Literals and %% pass through around the component.
    const got = try core.generate(h.converter(), e, .{ .format = "id-%%-%d", .precision = .milli, .clock_ms = 0 }, &out_buf);
    try std.testing.expectEqualStrings("id-%-00000000", got);

    // Region ledger still clean after the error traffic.
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// Every component works in a base whose digits are several bytes each. This
// used to be refused outright, because slicing a converted string at a symbol
// boundary was not something the conversion library could do; fit does it now,
// so the wide bases carry the truncating components as well as the padded
// ones. Widths are counted in symbols - byte length says nothing here.
test "a multi-byte base carries every component" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed = FixedEnv{};
    fixed.random_len = fixed.random.len;
    @memset(&fixed.random, 0x5a);
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_][]const u8{ "256tt", "512tt", "2048tz" }) |base| {
        const radix = try h.converter().radix(base);
        const cases = [_]struct { format: []const u8, want: u32 }{
            .{ .format = "%d", .want = core.widthFor(radix, .second) },
            .{ .format = "%h", .want = core.default_hash_chars },
            .{ .format = "%u", .want = core.default_hash_chars },
            .{ .format = "%f", .want = core.default_hash_chars },
            .{ .format = "%r", .want = core.default_random_chars },
        };
        for (cases) |case| {
            fixed.drawn = 0;
            const got = try core.generate(h.converter(), fixed.interface(), .{ .format = case.format, .base = base, .clock_ms = 0 }, &out_buf);
            const symbols = try h.converter().symbolCount(base, got);
            try std.testing.expectEqual(@as(u64, case.want), symbols);
        }
    }
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// A random draw has to fill the symbols it claims. One byte per symbol runs
// short above 256, where a symbol carries more than eight bits, and the
// shortfall shows up as a leading zero digit that never varies.
test "a wide base draws enough randomness to fill its symbols" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_][]const u8{ "512tt", "1024tz", "2048tz" }) |base| {
        var first_seen: [core.component_buf_len]u8 = undefined;
        var first_len: usize = 0;
        var varied = false;
        for (0..32) |seed| {
            var fixed = FixedEnv{};
            fixed.random_len = fixed.random.len;
            @memset(&fixed.random, @intCast(seed * 8 + 1));
            const got = try core.generate(h.converter(), fixed.interface(), .{ .format = "%r", .base = base, .clock_ms = 0 }, &out_buf);
            // The leading symbol is whatever fit put first; comparing the
            // prefix byte-wise is enough to see it move.
            const lead = got[0..@min(got.len, 4)];
            if (seed == 0) {
                @memcpy(first_seen[0..lead.len], lead);
                first_len = lead.len;
            } else if (!std.mem.eql(u8, first_seen[0..first_len], lead)) {
                varied = true;
            }
        }
        if (!varied) {
            std.debug.print("base {s}: the leading %r symbol never varied, so the draw is short\n", .{base});
            return error.TestUnexpectedResult;
        }
    }
}

// The live sources have to work on the machine running the tests, or %h %u %f
// %m would only ever be exercised through injected values.
test "the live environment supplies every component" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var live: env.Live = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_][]const u8{ "%h", "%u", "%f", "%g", "%r" }) |format| {
        const got = try core.generate(h.converter(), live.env(), .{ .format = format, .clock_ms = 0 }, &out_buf);
        try std.testing.expect(got.len > 0);
    }
    // A machine with no network interface is legitimate, so %m is allowed to
    // fail - it just has to say so rather than render something wrong.
    if (core.generate(h.converter(), live.env(), .{ .format = "%m", .clock_ms = 0 }, &out_buf)) |got| {
        try std.testing.expectEqual(@as(usize, 9), got.len);
    } else |err| {
        try std.testing.expectEqual(core.Error.EnvUnavailable, err);
    }
}

// %r has to actually vary, or appending it to a same-tick timestamp buys
// nothing.
test "the live random source varies" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var live: env.Live = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    var first: [16]u8 = undefined;
    const seed = try core.generate(h.converter(), live.env(), .{ .format = "%r", .clock_ms = 0 }, &out_buf);
    @memcpy(first[0..seed.len], seed);
    var differed = false;
    for (0..16) |_| {
        const next = try core.generate(h.converter(), live.env(), .{ .format = "%r", .clock_ms = 0 }, &out_buf);
        if (!std.mem.eql(u8, first[0..seed.len], next)) differed = true;
    }
    try std.testing.expect(differed);
}

test "the conversion library reports a version" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var buf: [64]u8 = undefined;
    const v = try h.libVersion(&buf);
    try std.testing.expect(v.len >= 2 and v[0] == 'v');
}

test "C surface end to end" {
    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);

    capi.zuid_set_clock_ms(z, 946684800000);
    var out: [256]u8 = undefined;

    // Defaults: NULL format and base mean %d in base 62, at second precision.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, null, null, &out, out.len));
    try std.testing.expectEqualStrings("124Bxg", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, "%d", "32w", &out, out.len));
    try std.testing.expectEqualStrings("2r8pRr2", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    // Precision is sticky on the context, and out-of-range is refused.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_set_precision(z, 1));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, null, null, &out, out.len));
    try std.testing.expectEqualStrings("0GfLcwXQ", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));
    try std.testing.expectEqual(@as(c_int, 8), capi.zuid_set_precision(z, 2));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_set_precision(z, 0));

    // The components come off the live machine here, so only their widths are
    // predictable. Hashing off makes %h the host name itself.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, "%h%g%r", null, &out, out.len));
    try std.testing.expectEqual(@as(usize, 8 + 22 + 6), std.mem.span(@as([*:0]const u8, @ptrCast(&out))).len);

    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_set_hash_chars(z, 5));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_set_random_chars(z, 12));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, "%h%r", null, &out, out.len));
    try std.testing.expectEqual(@as(usize, 17), std.mem.span(@as([*:0]const u8, @ptrCast(&out))).len);
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_set_hash_chars(z, 0));
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_set_random_chars(z, 65));

    // Error text survives into the C string.
    try std.testing.expectEqual(@as(c_int, 1), capi.zuid_generate(z, "%d", "hexx", &out, out.len));
    try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);

    // A buffer that cannot hold the id plus NUL is refused, not truncated.
    try std.testing.expectEqual(@as(c_int, 5), capi.zuid_generate(z, "%d", "62", &out, 6));

    try std.testing.expectEqualStrings(core.version, std.mem.span(capi.zuid_version()));
}

// The conversion library carries a base whose digits are raw byte values. It
// converts happily, which is exactly why it has to be refused here.
test "a raw-byte base is refused" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_][]const u8{ "%d", "%h", "%g" }) |format| {
        const attempt = core.generate(
            h.converter(),
            fixed.interface(),
            .{ .format = format, .base = "bytes", .clock_ms = 0 },
            &out_buf,
        );
        try std.testing.expectError(core.Error.BaseNotText, attempt);
    }
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// The horizon is what the fixed width comes from, so both sides of it need
// pinning: the last instant that fits, and the first that does not.
test "the padding horizon is a hard edge" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    const eve = try core.generate(
        h.converter(),
        fixed.interface(),
        .{ .precision = .milli, .clock_ms = @intCast(core.horizon_ms - 1) },
        &out_buf,
    );
    try std.testing.expectEqual(@as(usize, 8), eve.len);

    const past = core.generate(
        h.converter(),
        fixed.interface(),
        .{ .precision = .milli, .clock_ms = @intCast(core.horizon_ms * 1000) },
        &out_buf,
    );
    try std.testing.expectError(core.Error.WidthOverflow, past);
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// zuid_last_error used to answer with whatever the previous call left behind,
// because the failures that never reach the converter do not touch its text.
test "the C module does not report a stale error" {
    const z = capi.zuid_new() orelse return error.SkipZigTest;
    defer capi.zuid_free(z);
    var out: [64]u8 = undefined;

    try std.testing.expect(capi.zuid_generate(z, "%d", "hexx", &out, out.len) != 0);
    const stale = std.mem.span(capi.zuid_last_error(z));
    try std.testing.expect(std.mem.indexOf(u8, stale, "hexx") != null);

    try std.testing.expect(capi.zuid_generate(z, "%q", "62", &out, out.len) != 0);
    const fresh = std.mem.span(capi.zuid_last_error(z));
    try std.testing.expect(std.mem.indexOf(u8, fresh, "hexx") == null);
    try std.testing.expect(fresh.len > 0);
    // Nothing readable is left in the caller's buffer either.
    try std.testing.expectEqual(@as(u8, 0), out[0]);
}

// Every entry point takes a nullable context, so a caller who ignored a null
// from zuid_new gets a code rather than a crash.
test "the C module rejects a null context" {
    var out: [64]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 7), capi.zuid_generate(null, "%d", "62", &out, out.len));
    try std.testing.expectEqual(@as(c_int, 7), capi.zuid_set_precision(null, 0));
    try std.testing.expectEqual(@as(c_int, 7), capi.zuid_set_hash_chars(null, 8));
    try std.testing.expectEqualStrings("", std.mem.span(capi.zuid_last_error(null)));
}
