// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! The C module: zuid.h's implementation. One allocation per context and a
//! caller-owned output buffer, so the only free contract is zuid_free itself.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
const host = @import("host.zig");
const env = @import("env.zig");
const clock = @import("clock.zig");

// Per the memory-safety decisions: DebugAllocator when debugging the library
// itself, smp_allocator in what ships.
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
const gpa = switch (builtin.mode) {
    .Debug => debug_allocator.allocator(),
    else => std.heap.smp_allocator,
};

// Codes from zuid.h. Kept in one switch so a new core error fails loudly here.
fn codeFor(err: core.Error) c_int {
    return switch (err) {
        core.Error.UnknownBase => 1,
        core.Error.BareFormatPercent, core.Error.UnknownComponent => 2,
        core.Error.BadInput, core.Error.ConvertFailed, core.Error.WidthOverflow => 4,
        core.Error.BufferTooSmall => 5,
        core.Error.ClockBeforeEpoch => 6,
        core.Error.OptionRange => 9,
        core.Error.EnvUnavailable => 10,
        core.Error.MultiByteBase => 11,
    };
}

const Zuid = struct {
    wasm_host: host.Host,
    live_env: env.Live,
    fixed_clock_ms: ?i64,
    precision: core.Precision,
    no_hash: bool,
    hash_chars: u32,
    random_chars: u32,
    // The host's error text plus a NUL, so zuid_last_error can hand out a C string.
    err_buf: [host.Host.err_buf_len + 1]u8,

    fn setErrText(self: *Zuid, text: []const u8) void {
        const n = @min(text.len, self.err_buf.len - 1);
        @memcpy(self.err_buf[0..n], text[0..n]);
        self.err_buf[n] = 0;
    }
};

pub export fn zuid_new() ?*Zuid {
    const self = gpa.create(Zuid) catch return null;
    self.wasm_host = host.Host.init(.auto) catch {
        gpa.destroy(self);
        return null;
    };
    self.live_env = .{};
    self.fixed_clock_ms = null;
    self.precision = core.Precision.default;
    self.no_hash = false;
    self.hash_chars = core.default_hash_chars;
    self.random_chars = core.default_random_chars;
    self.err_buf[0] = 0;
    return self;
}

pub export fn zuid_free(z: ?*Zuid) void {
    const self = z orelse return;
    self.wasm_host.deinit();
    gpa.destroy(self);
}

pub export fn zuid_generate(z: ?*Zuid, format: ?[*:0]const u8, base: ?[*:0]const u8, out: ?[*]u8, out_cap: usize) c_int {
    const self = z orelse return 7;
    const out_ptr = out orelse return 5;
    self.err_buf[0] = 0;

    const fmt: []const u8 = if (format) |f| std.mem.span(f) else "";
    const opts = core.Options{
        .format = if (fmt.len == 0) "%d" else fmt,
        .base = if (base) |b| std.mem.span(b) else "",
        .precision = self.precision,
        .clock_ms = self.fixed_clock_ms orelse clock.nowMs(),
        .no_hash = self.no_hash,
        .hash_chars = self.hash_chars,
        .random_chars = self.random_chars,
    };

    var id_buf: [core.out_buf_len]u8 = undefined;
    const id = core.generate(self.wasm_host.converter(), self.live_env.env(), opts, &id_buf) catch |err| {
        self.setErrText(self.wasm_host.lastError());
        return codeFor(err);
    };
    if (id.len + 1 > out_cap) return 5;
    @memcpy(out_ptr[0..id.len], id);
    out_ptr[id.len] = 0;
    return 0;
}

pub export fn zuid_set_precision(z: ?*Zuid, precision: c_int) c_int {
    const self = z orelse return 7;
    self.precision = core.Precision.fromInt(precision) orelse return 8;
    return 0;
}

pub export fn zuid_set_hashing(z: ?*Zuid, enabled: c_int) void {
    const self = z orelse return;
    self.no_hash = enabled == 0;
}

pub export fn zuid_set_hash_chars(z: ?*Zuid, chars: c_int) c_int {
    const self = z orelse return 7;
    if (!inRange(chars)) return 9;
    self.hash_chars = @intCast(chars);
    return 0;
}

pub export fn zuid_set_random_chars(z: ?*Zuid, chars: c_int) c_int {
    const self = z orelse return 7;
    if (!inRange(chars)) return 9;
    self.random_chars = @intCast(chars);
    return 0;
}

fn inRange(chars: c_int) bool {
    return chars >= 1 and chars <= core.max_component_chars;
}

pub export fn zuid_set_clock_ms(z: ?*Zuid, ms: c_longlong) void {
    const self = z orelse return;
    self.fixed_clock_ms = ms;
}

pub export fn zuid_clear_clock(z: ?*Zuid) void {
    const self = z orelse return;
    self.fixed_clock_ms = null;
}

pub export fn zuid_last_error(z: ?*const Zuid) [*:0]const u8 {
    const self = z orelse return "";
    return @ptrCast(&self.err_buf);
}

pub export fn zuid_version() [*:0]const u8 {
    return core.version;
}
