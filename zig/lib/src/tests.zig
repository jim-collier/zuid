// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Replays testdata/vectors.tsv - the spec in executable form - through the
//! real wasm host, plus the error paths and the module's own leak ledger.
//! The vectors file is embedded at build time, so the tests need no cwd.

const std = @import("std");
const core = @import("core.zig");
const host = @import("host.zig");
const capi = @import("capi.zig");

const vectors_tsv = @embedFile("vectors.tsv");

test "core unit tests" {
    _ = core;
}

// One host for the whole file: init costs more than every row combined.
// Both compile strategies are exercised, because the CLI prefers winch and
// a winch miscompile would otherwise only surface in production.
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
        const clock_field = fields.next() orelse return error.BadVectorRow;
        const expected = fields.next() orelse return error.BadVectorRow;
        const clock_ms = try std.fmt.parseInt(i64, clock_field, 10);

        var out_buf: [core.out_buf_len]u8 = undefined;
        const got = core.generate(h.converter(), format, base, clock_ms, &out_buf) catch |err| {
            std.debug.print("vector {s} ({s}, base {s}): {t}: {s}\n", .{ name, format, base, err, h.lastError() });
            return err;
        };
        std.testing.expectEqualStrings(expected, got) catch |err| {
            std.debug.print("vector {s} (base {s}, clock {d})\n", .{ name, base, clock_ms });
            return err;
        };
        rows += 1;
    }
    // A parsing bug that skips every row would otherwise pass silently.
    try std.testing.expect(rows >= 24);
}

test "error paths carry the module's error text" {
    var h = try host.Host.init(.auto);
    defer h.deinit();
    var out_buf: [core.out_buf_len]u8 = undefined;

    // Unknown base: the module's text includes near-match suggestions.
    try std.testing.expectError(error.UnknownBase, core.generate(h.converter(), "%d", "hexx", 0, &out_buf));
    try std.testing.expect(h.lastError().len > 0);

    try std.testing.expectError(error.ReservedComponent, core.generate(h.converter(), "%h", "", 0, &out_buf));
    try std.testing.expectError(error.UnknownComponent, core.generate(h.converter(), "%z", "", 0, &out_buf));
    try std.testing.expectError(error.BareFormatPercent, core.generate(h.converter(), "abc%", "", 0, &out_buf));
    try std.testing.expectError(error.ClockBeforeEpoch, core.generate(h.converter(), "%d", "", -1, &out_buf));

    // Literals and %% pass through around the component.
    const got = try core.generate(h.converter(), "id-%%-%d", "62", 0, &out_buf);
    try std.testing.expectEqualStrings("id-%-00000000", got);

    // Region ledger still clean after the error traffic.
    try std.testing.expectEqual(@as(u32, 0), try h.regionCount());
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
    var out: [64]u8 = undefined;

    // Defaults: NULL format and base mean %d in base 62.
    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, null, null, &out, out.len));
    try std.testing.expectEqualStrings("0GfLcwXQ", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    try std.testing.expectEqual(@as(c_int, 0), capi.zuid_generate(z, "%d", "32w", &out, out.len));
    try std.testing.expectEqualStrings("2qVfJxH22", std.mem.span(@as([*:0]const u8, @ptrCast(&out))));

    // Error text survives into the C string.
    try std.testing.expectEqual(@as(c_int, 1), capi.zuid_generate(z, "%d", "hexx", &out, out.len));
    try std.testing.expect(std.mem.span(capi.zuid_last_error(z)).len > 0);

    // A buffer that cannot hold the id plus NUL is refused, not truncated.
    try std.testing.expectEqual(@as(c_int, 5), capi.zuid_generate(z, "%d", "62", &out, 8));

    try std.testing.expectEqualStrings(core.version, std.mem.span(capi.zuid_version()));
}
