// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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

// Pulls in core.zig's and env_windows.zig's own tests. Unnamed, since it
// checks nothing itself.
test {
    _ = core;
    _ = @import("env_windows.zig");
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

/// `text` n times over, as the array `**` gave before 0.17. Zero-terminated,
/// so it passes straight to the C API.
fn repeat(comptime text: []const u8, comptime n: usize) *const [text.len * n:0]u8 {
    const repeated = struct {
        const value: [text.len * n:0]u8 = blk: {
            @setEvalBranchQuota(2 * n + 1000);
            var buf: [text.len * n:0]u8 = undefined;
            for (0..n) |i| @memcpy(buf[i * text.len ..][0..text.len], text);
            break :blk buf;
        };
    };
    return &repeated.value;
}

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
        } else if (std.mem.eql(u8, key, "salt")) {
            opts.salt = value;
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
// test-id: EloUhiz
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

// A module loaded back from its serialized bytes has to render exactly what a
// compiled one does, and bytes that are not a module have to fall back to the
// compiler rather than fail.
// test-id: Ersmdcv
test "a serialized module loads back and reproduces the vectors" {
    var first = try host.Host.init(.auto);
    var compiled = first.serialize() orelse {
        first.deinit();
        return error.SerializeFailed;
    };
    defer compiled.deinit();
    try std.testing.expect(first.compiled_fresh);
    first.deinit();

    var again = try host.Host.initCached(.auto, compiled.bytes());
    defer again.deinit();
    try std.testing.expect(!again.compiled_fresh);
    try runVectors(&again);

    var junk = try host.Host.initCached(.auto, "not a module");
    defer junk.deinit();
    try std.testing.expect(junk.compiled_fresh);
}

/// The C call with only a format and a base, which is most of what gets asked.
fn gen(z: ?*capi.Zuid, format: ?[*:0]const u8, base: ?[*:0]const u8, out: ?[*]u8, out_cap: usize) c_int {
    const req: capi.Request = .{ .format = format, .base = base };
    return capi.zuid_generate(z, &req, out, out_cap);
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
    try std.testing.expect(rows >= 201);
}

// test-id: EloUhj0
test "error paths carry the module's error text" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed = FixedEnv{};
    const e = fixed.interface();
    var out_buf: [core.out_buf_len]u8 = undefined;

    // Unknown base: the module's text includes near-match suggestions.
    try std.testing.expectError(error.UnknownBase, core.generate(h.converter(), e, .{ .base = "hexx", .clock_ms = 0 }, &out_buf));
    try std.testing.expect(h.lastError().len > 0);

    // A name long enough that the module's message outgrows the error buffer.
    // Reading it used to fail, and the real code went with it, so the caller
    // saw a bare ConvertFailed for what is just a typo.
    const long_name = repeat("a", 1000);
    try std.testing.expectError(error.UnknownBase, core.generate(h.converter(), e, .{ .base = long_name, .clock_ms = 0 }, &out_buf));
    try std.testing.expect(h.lastError().len > 0);
    try std.testing.expect(std.unicode.utf8ValidateSlice(h.lastError()));

    try std.testing.expectError(error.UnknownComponent, core.generate(h.converter(), e, .{ .format = "%z", .clock_ms = 0 }, &out_buf));
    try std.testing.expectError(error.BareFormatPercent, core.generate(h.converter(), e, .{ .format = "abc%", .clock_ms = 0 }, &out_buf));
    try std.testing.expectError(error.ClockBeforeEpoch, core.generate(h.converter(), e, .{ .clock_ms = -1 }, &out_buf));
    try std.testing.expectError(error.OptionRange, core.generate(h.converter(), e, .{ .format = "%h", .clock_ms = 0, .hash_chars = 65 }, &out_buf));
    try std.testing.expectError(error.OptionRange, core.generate(h.converter(), e, .{ .format = "%r", .clock_ms = 0, .random_chars = 65 }, &out_buf));

    // A width the format never reads cannot fail the call, so one hash width
    // can serve every base a caller uses.
    _ = try core.generate(h.converter(), e, .{ .clock_ms = 0, .hash_chars = 65, .random_chars = 65 }, &out_buf);
    _ = try core.generate(h.converter(), e, .{ .base = "2048tz", .clock_ms = 0, .hash_chars = 40 }, &out_buf);

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
// test-id: Em2hrcQ
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
            .{ .format = "%h", .want = core.defaultHashChars(radix) },
            .{ .format = "%u", .want = core.defaultHashChars(radix) },
            .{ .format = "%f", .want = core.defaultHashChars(radix) },
            .{ .format = "%r", .want = core.defaultRandomChars(radix) },
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
// test-id: Em2hrcR
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
// test-id: ElpGOHX
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
// test-id: ElpGOHY
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

// Each live name is read once and kept, so %h and %f describe one machine for
// the life of a context even if it is renamed under it. The cache fields are
// plain here, so a name no system would give is planted after the first read,
// and the second read has to hand back that one.
// test-id: ErOhqzP
test "the live environment reads each name once" {
    var live: env.Live = .{};
    const live_env = live.env();
    var buf: [core.name_buf_len]u8 = undefined;

    _ = try live_env.hostname(&buf);
    _ = try live_env.username(&buf);
    _ = try live_env.fqdn(&buf);
    try std.testing.expect(live.host.len != null);
    try std.testing.expect(live.user.len != null);
    try std.testing.expect(live.qualified.len != null);

    const planted = "planted-name";
    for ([_]*@TypeOf(live.host){ &live.host, &live.user, &live.qualified }) |cache| {
        @memcpy(cache.buf[0..planted.len], planted);
        cache.len = planted.len;
    }
    try std.testing.expectEqualStrings(planted, try live_env.hostname(&buf));
    try std.testing.expectEqualStrings(planted, try live_env.username(&buf));
    try std.testing.expectEqualStrings(planted, try live_env.fqdn(&buf));

    live.hardware = .{ 0x02, 0xaa, 0xbb, 0xcc, 0xdd, 0xee };
    try std.testing.expectEqual([6]u8{ 0x02, 0xaa, 0xbb, 0xcc, 0xdd, 0xee }, try live_env.mac());
}

// Only the widths a format spends are checked. A hash width that suits one
// base used to fail a plain timestamp in another. Go has the same test.
// test-id: ErOhqzQ
test "only the widths a format uses are checked" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_]core.Options{
        .{ .format = "%d", .hash_chars = core.max_component_chars + 1, .random_chars = core.max_component_chars + 1, .clock_ms = 0 },
        .{ .format = "%d", .base = "2048tz", .hash_chars = 40, .clock_ms = 0 },
        .{ .format = "%h", .base = "2048tz", .hash_chars = 40, .no_hash = true, .clock_ms = 0 },
    }) |opts| {
        _ = try core.generate(h.converter(), fixed.interface(), opts, &out_buf);
    }

    // A format that does spend the width is still held to it.
    try std.testing.expectError(core.Error.HashTooWide, core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .base = "2048tz", .hash_chars = 40, .clock_ms = 0 }, &out_buf));
    try std.testing.expectError(core.Error.OptionRange, core.generate(h.converter(), fixed.interface(), .{ .format = "%r", .random_chars = core.max_component_chars + 1, .clock_ms = 0 }, &out_buf));
}

// test-id: EloUhj1
test "the conversion library reports a version" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var buf: [64]u8 = undefined;
    const v = try h.libVersion(&buf);
    try std.testing.expect(v.len >= 2 and v[0] == 'v');
}

// test-id: EloUhj2
test "C surface end to end" {
    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);

    capi.zuid_set_clock_ms(z, 946684800000);
    var out: [256]u8 = undefined;

    // Defaults: NULL format and base mean %d in base 62, at second precision.
    try std.testing.expectEqual(@as(c_int, 0), gen(z, null, null, &out, out.len));
    try std.testing.expectEqualStrings("124Bxg", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    try std.testing.expectEqual(@as(c_int, 0), gen(z, "%d", "32w", &out, out.len));
    try std.testing.expectEqualStrings("2r8pRr2", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    // Precision comes with the call, and out-of-range is refused.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .precision = 1 }, &out, out.len));
    try std.testing.expectEqualStrings("0GfLcwXQ", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));
    try std.testing.expectEqual(@as(c_int, 8), capi.zuid_generate(z, &.{ .precision = 2 }, &out, out.len));
    try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);
    // Nothing carries over to the next call.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, null, &out, out.len));
    try std.testing.expectEqualStrings("124Bxg", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    // The components come off the live machine here, so only their widths are
    // predictable. Hashing off makes %h the host name itself.
    try std.testing.expectEqual(@as(c_int, 0), gen(z, "%h%g%r", null, &out, out.len));
    try std.testing.expectEqual(@as(usize, 8 + 22 + 6), std.mem.span(@as([*:0]const u8, @ptrCast(&out))).len);

    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h%r", .hash_chars = 5, .random_chars = 12 }, &out, out.len));
    try std.testing.expectEqual(@as(usize, 17), std.mem.span(@as([*:0]const u8, @ptrCast(&out))).len);
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%h", .hash_chars = 65 }, &out, out.len));
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%r", .random_chars = 65 }, &out, out.len));
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%r", .random_chars = -1 }, &out, out.len));
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%h", .hash_chars = -1 }, &out, out.len));
    // A width the format does not spend is not checked, as in Go.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%d", .hash_chars = -1, .random_chars = 65 }, &out, out.len));

    // Zero is the per-base default, which is 8 and 6 here.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h%r" }, &out, out.len));
    try std.testing.expectEqual(@as(usize, 14), std.mem.span(@as([*:0]const u8, @ptrCast(&out))).len);

    // Hashing off makes %h the host name itself, which no hash comes out as.
    var hashed: [64]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), gen(z, "%h", null, &hashed, hashed.len));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h", .no_hash = 1 }, &out, out.len));
    try std.testing.expect(!std.mem.eql(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&hashed))), std.mem.span(@as([*:0]const u8, @ptrCast(&out)))));

    // Past the digest's own width the extra symbols are all left-fill, and the
    // message names the ceiling because it moves with the base.
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%h", .base = "62", .hash_chars = 44 }, &out, out.len));
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(capi.zuid_last_error(z)), "43") != null);
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h", .base = "16", .hash_chars = 44 }, &out, out.len));

    // The salt is read during the call only, so the caller's string is free to
    // change or go away afterwards.
    var salt_buf = [_:0]u8{ 'p', 'e', 'p', 'p', 'e', 'r' };
    try std.testing.expectEqual(@as(c_int, 0), gen(z, "%h", "62", &out, out.len));
    const unsalted = try std.testing.allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&out))));
    defer std.testing.allocator.free(unsalted);
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h", .salt = &salt_buf }, &out, out.len));
    const salted = try std.testing.allocator.dupe(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&out))));
    defer std.testing.allocator.free(salted);
    try std.testing.expect(!std.mem.eql(u8, unsalted, salted));
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, &.{ .format = "%h", .salt = "" }, &out, out.len));
    try std.testing.expectEqualStrings(unsalted, std.mem.span(@as([*:0]const u8, @ptrCast(&out))));
    try std.testing.expectEqual(@as(c_int, 9), capi.zuid_generate(z, &.{ .format = "%h", .salt = repeat("s", core.max_salt_bytes + 1) }, &out, out.len));

    // Error text survives into the C string.
    try std.testing.expectEqual(@as(c_int, 1), gen(z, "%d", "hexx", &out, out.len));
    try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);

    // A buffer that cannot hold the id plus NUL is refused, not truncated.
    try std.testing.expectEqual(@as(c_int, 5), gen(z, "%d", "62", &out, 6));

    try std.testing.expectEqualStrings(core.version, std.mem.span(capi.zuid_version()));
}

// The header's enum is a C ABI, so each code a call can return is pinned here
// rather than only at the core error level. A renumbering in codeFor then
// fails the build instead of quietly reaching compiled callers.
// test-id: Eq9dPAO
test "the C module's error codes are the ones zuid.h documents" {
    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);
    var out: [256]u8 = undefined;

    // 2, both ways in: an unknown component and a format ending on a bare '%'.
    try std.testing.expectEqual(@as(c_int, 2), gen(z, "%q", "62", &out, out.len));
    try std.testing.expectEqual(@as(c_int, 2), gen(z, "%d%", "62", &out, out.len));

    // 13, the raw-byte base. Its digits are byte values, not text.
    try std.testing.expectEqual(@as(c_int, 13), gen(z, "%d", "bytes", &out, out.len));

    // 6, a clock before the epoch, and 12, one past the padding horizon.
    capi.zuid_set_clock_ms(z, -1);
    try std.testing.expectEqual(@as(c_int, 6), gen(z, "%d", "62", &out, out.len));
    capi.zuid_set_clock_ms(z, @intCast(core.horizon_ms * 1000));
    try std.testing.expectEqual(@as(c_int, 12), gen(z, "%d", "62", &out, out.len));
    capi.zuid_clear_clock(z);

    // Every one of them says something. 10 is left out: it needs a machine that
    // cannot supply a component, and nothing here can stage that.
    for ([_][*:0]const u8{ "%q", "%d%" }) |format| {
        try std.testing.expect(gen(z, format, "62", &out, out.len) != 0);
        try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);
    }
}

// Past what a SHA-256 fills in the base, the extra symbols are all left-fill:
// a longer identifier carrying no more fingerprint.
// test-id: Em3M9HH
test "a hash wider than the digest is refused" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    for ([_]struct { base: []const u8, ceiling: u32 }{
        .{ .base = "62", .ceiling = 43 },
        .{ .base = "2048tz", .ceiling = 24 },
        .{ .base = "16", .ceiling = 64 },
    }) |case| {
        const at_ceiling = core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .base = case.base, .hash_chars = case.ceiling, .clock_ms = 0 }, &out_buf);
        try std.testing.expectEqual(@as(u64, case.ceiling), try h.converter().symbolCount(case.base, try at_ceiling));

        // Base 16 fills the whole digest in exactly max_component_chars, so
        // there is no room above it for this error to be the one that fires.
        if (case.ceiling >= core.max_component_chars) continue;
        const past = core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .base = case.base, .hash_chars = case.ceiling + 1, .clock_ms = 0 }, &out_buf);
        try std.testing.expectError(core.Error.HashTooWide, past);
    }

    // Nothing is hashed with no_hash, so the ceiling has nothing to say.
    const literal = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .base = "2048tz", .hash_chars = 64, .no_hash = true, .clock_ms = 0 }, &out_buf);
    try std.testing.expectEqualStrings("testhost", literal);
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// Host and user names come from a small space, so the point of the salt is
// that hashing candidate names no longer confirms one. The vectors pin the
// values; this pins the edges around them.
// test-id: EqAI7sf
test "a salt moves the hashed names and leaves the rest alone" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var plain_buf: [core.out_buf_len]u8 = undefined;
    var salted_buf: [core.out_buf_len]u8 = undefined;

    const plain = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .clock_ms = 0 }, &plain_buf);
    const salted = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .salt = "pepper", .clock_ms = 0 }, &salted_buf);
    try std.testing.expect(!std.mem.eql(u8, plain, salted));
    try std.testing.expectEqual(plain.len, salted.len);

    // An empty salt hashes the name on its own, which is what keeps every
    // identifier generated before the salt existed valid.
    const empty = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .salt = "", .clock_ms = 0 }, &salted_buf);
    try std.testing.expectEqualStrings(plain, empty);

    // The time component is not hashed, so the salt has nothing to change.
    const time_plain = try core.generate(h.converter(), fixed.interface(), .{ .format = "%d", .clock_ms = 946684800000 }, &plain_buf);
    const time_salted = try core.generate(h.converter(), fixed.interface(), .{ .format = "%d", .salt = "pepper", .clock_ms = 946684800000 }, &salted_buf);
    try std.testing.expectEqualStrings(time_plain, time_salted);

    // Neither is an unhashed name.
    const literal = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .salt = "pepper", .no_hash = true, .clock_ms = 0 }, &salted_buf);
    try std.testing.expectEqualStrings("testhost", literal);

    // The ceiling is where the C module's fixed buffer stops.
    const at_max = repeat("s", core.max_salt_bytes);
    _ = try core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .salt = at_max, .clock_ms = 0 }, &salted_buf);
    const past_max = core.generate(h.converter(), fixed.interface(), .{ .format = "%h", .salt = at_max ++ "s", .clock_ms = 0 }, &salted_buf);
    try std.testing.expectError(core.Error.SaltTooLong, past_max);

    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// The conversion library carries a base whose digits are raw byte values. It
// converts happily, which is exactly why it has to be refused here.
// test-id: Em32Nza
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

// 98keyboard counts tab, newline and return among its digits, so an identifier
// in it could carry a line break. Its zero digit is '0', which is why the
// alphabet gets asked about rather than just that one symbol.
// test-id: Eq9xBUg
test "a base with control digits is refused" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    const attempt = core.generate(h.converter(), fixed.interface(), .{ .format = "%d", .base = "98keyboard", .clock_ms = 0 }, &out_buf);
    try std.testing.expectError(core.Error.BaseNotText, attempt);

    _ = try core.generate(h.converter(), fixed.interface(), .{ .format = "%d", .base = "62", .clock_ms = 0 }, &out_buf);
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// The text verdict is remembered on the host so a batch does not re-probe the
// tokenizer 33 times an identifier. One slot means switching bases has to
// throw the old answer away, in both directions, and a name too long for the
// slot must not be filed under whatever was there before.
// test-id: EqAew24
test "a cached text verdict does not follow the base that earned it" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var fixed: FixedEnv = .{};
    var out_buf: [core.out_buf_len]u8 = undefined;

    const long_name = repeat("6", 100);
    const cases = [_]struct { base: []const u8, want: ?core.Error }{
        .{ .base = "62", .want = null },
        .{ .base = "bytes", .want = core.Error.BaseNotText },
        .{ .base = "62", .want = null },
        .{ .base = "98keyboard", .want = core.Error.BaseNotText },
        .{ .base = long_name, .want = core.Error.UnknownBase },
        .{ .base = "62", .want = null },
        .{ .base = long_name, .want = core.Error.UnknownBase },
        .{ .base = "bytes", .want = core.Error.BaseNotText },
        .{ .base = "62", .want = null },
    };
    for (cases) |case| {
        const attempt = core.generate(
            h.converter(),
            fixed.interface(),
            .{ .format = "%d", .base = case.base, .clock_ms = 0 },
            &out_buf,
        );
        if (case.want) |err| {
            try std.testing.expectError(err, attempt);
        } else {
            _ = try attempt;
        }
    }
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// The horizon is what the fixed width comes from, so both sides of it need
// pinning: the last instant that fits, and the first that does not.
// test-id: Em32Nzb
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
// test-id: Em32Nzc
test "the C module does not report a stale error" {
    const z = capi.zuid_new() orelse return error.SkipZigTest;
    defer capi.zuid_free(z);
    var out: [64]u8 = undefined;

    try std.testing.expect(gen(z, "%d", "hexx", &out, out.len) != 0);
    const stale = std.mem.span(capi.zuid_last_error(z));
    try std.testing.expect(std.mem.indexOf(u8, stale, "hexx") != null);

    try std.testing.expect(gen(z, "%q", "62", &out, out.len) != 0);
    const fresh = std.mem.span(capi.zuid_last_error(z));
    try std.testing.expect(std.mem.indexOf(u8, fresh, "hexx") == null);
    try std.testing.expect(fresh.len > 0);
    // Nothing readable is left in the caller's buffer either.
    try std.testing.expectEqual(@as(u8, 0), out[0]);
}

// Every entry point takes a nullable context, so a caller who ignored a null
// from zuid_new gets a code rather than a crash. Its own code, since 7 says the
// runtime failed, which sends a caller looking in the wrong place.
// test-id: Em32Nzd
test "the C module rejects a null context" {
    var out: [64]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 14), gen(null, "%d", "62", &out, out.len));
    capi.zuid_set_clock_ms(null, 0);
    capi.zuid_clear_clock(null);
    capi.zuid_free(null);
    try std.testing.expectEqualStrings("", std.mem.span(capi.zuid_last_error(null)));
}

// ZUID_ERR_BUFFER used to mean two unrelated things: the caller's buffer really
// was too small, or the identifier had passed a fixed 4096-byte buffer inside
// the module that no out_cap could raise. It carried no text either way, so
// there was nothing to tell them apart by. The Go module has no such limit, so
// a format Go rendered, C refused.
// test-id: Eq9kVKi
test "a long identifier is bounded only by the caller's buffer" {
    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);

    var big: [65536]u8 = undefined;
    const spanOf = struct {
        fn f(buf: []const u8) []const u8 {
            return std.mem.span(@as([*:0]const u8, @ptrCast(buf.ptr)));
        }
    }.f;

    // 200 UUIDs in base 62, 22 symbols each: 4400 bytes, past the old ceiling.
    try std.testing.expectEqual(@as(c_int, 0), gen(z, repeat("%g", 200), "62", &big, big.len));
    try std.testing.expectEqual(@as(usize, 200 * 22), spanOf(&big).len);

    // A literal that long as well, since the old buffer bounded the whole
    // rendering rather than any one component.
    try std.testing.expectEqual(@as(c_int, 0), gen(z, repeat("x", 5000), "62", &big, big.len));
    try std.testing.expectEqual(@as(usize, 5000), spanOf(&big).len);

    // Exactly enough room, and one byte short of it. %d in base 62 is 6
    // symbols at second precision, so 7 bytes is the least that can hold it.
    capi.zuid_set_clock_ms(z, 946684800000);
    var tight: [7]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 0), gen(z, "%d", "62", &tight, tight.len));
    try std.testing.expectEqualStrings("124Bxg", spanOf(&tight));
    try std.testing.expectEqual(@as(c_int, 5), gen(z, "%d", "62", &tight, tight.len - 1));
    capi.zuid_clear_clock(z);

    // And every way of being refused now says something.
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(capi.zuid_last_error(z)), "out_cap") != null);
    try std.testing.expectEqual(@as(c_int, 5), gen(z, "%d", "62", &big, 0));
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(capi.zuid_last_error(z)), "out_cap") != null);
    try std.testing.expectEqual(@as(c_int, 5), gen(z, "%d", "62", null, 16));
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(capi.zuid_last_error(z)), "NULL") != null);

    // Nothing readable is left behind when a render runs out of room part way,
    // which it now does inside the caller's own buffer.
    var partial: [12]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 5), gen(z, "%g%g", "62", &partial, partial.len));
    try std.testing.expectEqual(@as(u8, 0), partial[0]);
}

// A context that is never freed used to be reported by nothing: no test and no
// debug build, because the allocator's own check has no moment to run in. A C
// caller never says it is finished, so the tests have to ask instead. This one
// runs last on purpose - it asserts that everything above it cleaned up.
// test-id: Eq9icWm
test "a leaked C context is reported" {
    try std.testing.expectEqual(@as(usize, 0), capi.liveContexts());
    try std.testing.expectEqual(@as(usize, 0), capi.leakCount());

    // One full cycle, to show the counter moves in both directions rather than
    // sitting at zero because nothing ever touches it.
    const z = capi.zuid_new() orelse return error.InitFailed;
    try std.testing.expectEqual(@as(usize, 1), capi.liveContexts());
    capi.zuid_free(z);
    try std.testing.expectEqual(@as(usize, 0), capi.liveContexts());
    try std.testing.expectEqual(@as(usize, 0), capi.leakCount());

    // Not freed twice here on purpose. The magic check reads memory the
    // allocator has already unmapped, so the guard segfaults instead of
    // returning - the recorded reason the header promises no more than C's
    // own free() does.
}

// The format string is the one part of a request that arrives verbatim from
// whoever ran the command, and both surfaces parse it themselves. Run normally
// these replay their corpus and an empty input; real fuzzing is
// 'zig build test --fuzz'.
// test-id: Eq9zVsH
test "the format parser survives arbitrary input" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    try std.testing.fuzz(&h, fuzzFormat, .{
        .corpus = &.{ "%d", "%", "%%", "%z", "%d-%h-%u-%f-%m-%g-%r", "%%%%%d", "\x00%d", "%\xff" },
    });
}

fn fuzzFormat(h: *host.Host, smith: *std.testing.Smith) !void {
    var fmt_buf: [128]u8 = undefined;
    const len = smith.slice(&fmt_buf);

    var fixed = FixedEnv{};
    @memset(&fixed.random, 0x5a);
    fixed.random_len = fixed.random.len;

    var out_buf: [core.out_buf_len]u8 = undefined;
    _ = core.generate(h.converter(), fixed.interface(), .{ .format = fmt_buf[0..len], .clock_ms = 0 }, &out_buf) catch {};

    // Failing part way through still has to hand every wasm region back.
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
}

// test-id: Eq9zVsI
test "the C generate call survives arbitrary input" {
    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);
    capi.zuid_set_clock_ms(z, 946684800000);
    try std.testing.fuzz(z, fuzzCapi, .{
        .corpus = &.{ "%d", "%q", "%d%d%d", "%r" },
    });
}

fn fuzzCapi(z: *capi.Zuid, smith: *std.testing.Smith) !void {
    // An interior NUL just ends the string early, which is the C contract.
    var fmt_buf: [128:0]u8 = undefined;
    const fmt_len = smith.slice(&fmt_buf);
    fmt_buf[fmt_len] = 0;
    var base_buf: [32:0]u8 = undefined;
    const base_len = smith.slice(&base_buf);
    base_buf[base_len] = 0;

    var out: [core.out_buf_len]u8 = undefined;
    const code = gen(z, &fmt_buf, &base_buf, &out, out.len);

    // What the header promises on a failure: an empty string and a reason.
    if (code != 0) {
        try std.testing.expectEqual(@as(u8, 0), out[0]);
        try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);
    }
}

// The T2 bridge address is the same on every Intel Mac that has one, and its
// interface numbers below en0, so it has to be passed over for the next one.
// test-id: ErU3R7A
test "the shared T2 address is never picked for %m" {
    const en0 = [6]u8{ 0x38, 0xf9, 0xd3, 0xc3, 0xd1, 0xad };
    var pick: env.MacPick = .{};
    pick.offer(4, .{ 0xac, 0xde, 0x48, 0x00, 0x11, 0x22 });
    try std.testing.expect(pick.found == null);
    pick.offer(6, en0);
    try std.testing.expectEqualSlices(u8, &en0, &pick.found.?);
}

const errors_tsv = @embedFile("errors.tsv");
const zuid_h = @embedFile("zuid.h");
const cli_messages = @import("cli_messages");

/// One row of testdata/errors.tsv.
const Refusal = struct {
    label: []const u8,
    code: c_int,
    c_name: []const u8,
    zig: []const u8,
    surfaces: []const u8,
    phrase: []const u8,

    fn listed(list: []const u8, name: []const u8) bool {
        var it = std.mem.splitScalar(u8, list, ',');
        while (it.next()) |item| {
            if (std.mem.eql(u8, item, name)) return true;
        }
        return false;
    }

    fn wordedBy(self: Refusal, surface: []const u8) bool {
        return listed(self.surfaces, surface);
    }

    fn names(self: Refusal, err_name: []const u8) bool {
        return listed(self.zig, err_name);
    }

    /// ' ... ' in the phrase is a gap; case is ignored.
    fn heldBy(self: Refusal, message: []const u8) bool {
        var at: usize = 0;
        var parts = std.mem.splitSequence(u8, self.phrase, " ... ");
        while (parts.next()) |part| {
            const found = std.ascii.findIgnoreCasePos(message, at, part) orelse return false;
            at = found + part.len;
        }
        return true;
    }
};

fn readRefusals(buf: []Refusal) ![]Refusal {
    var n: usize = 0;
    var lines = std.mem.splitScalar(u8, errors_tsv, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        var cols: [7][]const u8 = undefined;
        for (&cols) |*col| col.* = fields.next() orelse return error.ShortRow;
        if (fields.next() != null) return error.LongRow;
        if (n == buf.len) return error.TooManyRows;
        buf[n] = .{
            .label = cols[0],
            .code = try std.fmt.parseInt(c_int, cols[1], 10),
            .c_name = cols[2],
            .zig = cols[4],
            .surfaces = cols[5],
            .phrase = cols[6],
        };
        n += 1;
    }
    return buf[0..n];
}

fn findRefusal(rows: []const Refusal, label: []const u8) !Refusal {
    for (rows) |row| {
        if (std.mem.eql(u8, row.label, label)) return row;
    }
    std.debug.print("no row '{s}' in errors.tsv\n", .{label});
    return error.NoSuchRow;
}

const core_error_names = @typeInfo(core.Error).error_set.error_names.?;

// The table is only worth anything if it is complete: every error the core can
// return, with the code capi.zig gives it, and every code zuid.h names.
// test-id: ErsxH5D
test "errors.tsv has every core error and every C code" {
    var buf: [32]Refusal = undefined;
    const rows = try readRefusals(&buf);

    inline for (core_error_names) |name| {
        var seen = false;
        for (rows) |row| {
            if (!row.names(name)) continue;
            seen = true;
            const code = capi.codeFor(@field(core.Error, name));
            if (code != row.code) {
                std.debug.print("{s}: codeFor gives {d}, errors.tsv says {d}\n", .{ name, code, row.code });
                return error.CodeMismatch;
            }
        }
        if (!seen) {
            std.debug.print("{s} has no row in errors.tsv\n", .{name});
            return error.MissingRow;
        }
    }
    for (rows) |row| {
        if (std.mem.eql(u8, row.zig, "-")) continue;
        var it = std.mem.splitScalar(u8, row.zig, ',');
        next: while (it.next()) |name| {
            for (core_error_names) |known| {
                if (std.mem.eql(u8, name, known)) continue :next;
            }
            std.debug.print("{s}: core.Error has no {s}\n", .{ row.label, name });
            return error.UnknownError;
        }
    }

    // Both ways between the header's enum and the table.
    var header_codes: usize = 0;
    var lines = std.mem.splitScalar(u8, zuid_h, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "ZUID_ERR_")) continue;
        const eq = std.mem.indexOf(u8, trimmed, " = ") orelse continue;
        const name = std.mem.trimEnd(u8, trimmed[0..eq], " ");
        const rest = trimmed[eq + 3 ..];
        const end = std.mem.indexOfNone(u8, rest, "0123456789") orelse rest.len;
        const code = try std.fmt.parseInt(c_int, rest[0..end], 10);
        header_codes += 1;
        var seen = false;
        for (rows) |row| {
            if (!std.mem.eql(u8, row.c_name, name)) continue;
            seen = true;
            if (row.code != code) {
                std.debug.print("{s}: zuid.h says {d}, errors.tsv says {d}\n", .{ name, code, row.code });
                return error.CodeMismatch;
            }
        }
        if (!seen) {
            std.debug.print("{s} has no row in errors.tsv\n", .{name});
            return error.MissingRow;
        }
    }
    try std.testing.expect(header_codes >= 14);
    for (rows) |row| {
        const in_header = std.mem.indexOf(u8, zuid_h, row.c_name) != null;
        if (!in_header) {
            std.debug.print("{s}: zuid.h has no {s}\n", .{ row.label, row.c_name });
            return error.UnknownCode;
        }
    }
}

// What a C caller gets back for each failure: the row's code, and where C
// words it, the row's phrase in zuid_last_error.
// test-id: ErsxH5E
test "the C module says what errors.tsv says" {
    var buf: [32]Refusal = undefined;
    const rows = try readRefusals(&buf);
    var covered: [32]bool = @splat(false);

    const z = capi.zuid_new() orelse return error.InitFailed;
    defer capi.zuid_free(z);
    const now_ms = 946684800000;
    const long_salt: [core.max_salt_bytes + 1:0]u8 = @splat('s');
    const Case = struct {
        label: []const u8,
        req: capi.Request,
        clock_ms: i64 = now_ms,
        out_cap: usize = 256,
    };
    const cases = [_]Case{
        .{ .label = "unknown-base", .req = .{ .base = "nonesuch" } },
        .{ .label = "bare-percent", .req = .{ .format = "%d%" } },
        .{ .label = "unknown-component", .req = .{ .format = "%z" } },
        .{ .label = "buffer", .req = .{}, .out_cap = 2 },
        .{ .label = "before-epoch", .req = .{}, .clock_ms = -1 },
        .{ .label = "precision", .req = .{ .precision = 2 } },
        .{ .label = "width-range", .req = .{ .format = "%r", .random_chars = 65 } },
        .{ .label = "width-range", .req = .{ .format = "%h", .hash_chars = -1 } },
        .{ .label = "hash-too-wide", .req = .{ .format = "%h", .base = "2048tz", .hash_chars = 25 } },
        .{ .label = "salt-too-long", .req = .{ .format = "%h", .salt = &long_salt } },
        .{ .label = "past-horizon", .req = .{}, .clock_ms = @as(i64, @intCast(core.horizon_ms)) + 1000 },
        .{ .label = "raw-byte-base", .req = .{ .base = "bytes" } },
        .{ .label = "control-char-base", .req = .{ .base = "98keyboard" } },
    };
    var out: [256]u8 = undefined;
    for (cases) |case| {
        const row = try findRefusal(rows, case.label);
        capi.zuid_set_clock_ms(z, case.clock_ms);
        const code = capi.zuid_generate(z, &case.req, &out, case.out_cap);
        const said = std.mem.span(capi.zuid_last_error(z));
        if (code != row.code) {
            std.debug.print("{s}: code {d}, errors.tsv says {d} ({s})\n", .{ case.label, code, row.code, said });
            return error.CodeMismatch;
        }
        if (row.wordedBy("c") and !row.heldBy(said)) {
            std.debug.print("{s}: '{s}' does not say '{s}'\n", .{ case.label, said, row.phrase });
            return error.PhraseMissing;
        }
        for (rows, 0..) |r, i| {
            if (std.mem.eql(u8, r.label, case.label)) covered[i] = true;
        }
    }
    try std.testing.expectEqual((try findRefusal(rows, "context")).code, capi.zuid_generate(null, null, &out, out.len));

    // The fixed sentences, including the ones no call here can reach, such as
    // a machine with no host name.
    inline for (core_error_names) |name| {
        const text = capi.textFor(@field(core.Error, name));
        for (rows, 0..) |row, i| {
            if (!row.names(name) or !row.wordedBy("c") or text.len == 0) continue;
            if (!row.heldBy(text)) {
                std.debug.print("{s}: '{s}' does not say '{s}'\n", .{ row.label, text, row.phrase });
                return error.PhraseMissing;
            }
            covered[i] = true;
        }
    }
    for (rows, 0..) |row, i| {
        if (row.wordedBy("c") and !covered[i]) {
            std.debug.print("{s}: C words it, but nothing here reaches it\n", .{row.label});
            return error.Uncovered;
        }
    }
}

// The command's message for every core error, the ones no flag can reach
// included. Its flag checks are held to the same phrases in cli-test.bash.
// test-id: ErsxH5F
test "the command says what errors.tsv says" {
    var buf: [32]Refusal = undefined;
    const rows = try readRefusals(&buf);
    inline for (core_error_names) |name| {
        var text_buf: [512]u8 = undefined;
        var w: std.Io.Writer = .fixed(&text_buf);
        try cli_messages.generating(&w, @field(core.Error, name), "", .{
            .base = "nonesuch",
            .format = "%z",
            .salt_len = core.max_salt_bytes + 1,
            .max_chars = core.max_component_chars,
            .max_salt = core.max_salt_bytes,
            .max_out = 1 << 20,
        });
        const said = w.buffered();
        for (rows) |row| {
            if (!row.names(name) or !row.wordedBy("cli")) continue;
            if (!row.heldBy(said)) {
                std.debug.print("{s}: '{s}' does not say '{s}'\n", .{ row.label, said, row.phrase });
                return error.PhraseMissing;
            }
        }
    }
}
