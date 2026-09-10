// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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
// itself, smp_allocator in a release build.
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
        core.Error.BadInput, core.Error.ConvertFailed => 4,
        core.Error.BufferTooSmall => 5,
        core.Error.ClockBeforeEpoch => 6,
        core.Error.OptionRange, core.Error.HashTooWide => 9,
        core.Error.EnvUnavailable => 10,
        core.Error.WidthOverflow => 12,
        core.Error.BaseNotText => 13,
    };
}

/// Explanation for the failures that never reach the conversion library, and
/// so leave it with nothing to say. Empty means the library's own text stands.
fn textFor(err: core.Error) []const u8 {
    return switch (err) {
        core.Error.WidthOverflow => "the clock is past the padding horizon, so the timestamp no longer fits its fixed width",
        core.Error.ClockBeforeEpoch => "the clock predates the Unix epoch",
        core.Error.BareFormatPercent => "the format string ends on a bare '%'",
        core.Error.UnknownComponent => "unknown format component; known: %d %h %u %f %m %g %r, and %% for a literal",
        core.Error.OptionRange => "a symbol count is out of range",
        core.Error.HashTooWide => "a hashed component cannot be wider than a SHA-256 fills in that base",
        core.Error.EnvUnavailable => "this machine could not supply that component",
        core.Error.BaseNotText => "that base renders raw bytes rather than text, so it cannot carry an identifier",
        else => "",
    };
}

// Stamped into a live context and cleared on free, so a stale pointer is
// usually rejected rather than followed. Only usually: once the allocator
// hands the pages back there is nothing left to read, which is the
// use-after-free gap the design notes describe. Cheap, and better than
// nothing.
const live_magic: u32 = 0x7A554944;

const Zuid = struct {
    magic: u32,
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
        const kept = @min(text.len, self.err_buf.len - 1);
        @memcpy(self.err_buf[0..kept], text[0..kept]);
        self.err_buf[kept] = 0;
    }

    /// Spells out the ceiling for the base actually being rendered in - 64
    /// symbols in base 16, down to 24 in 2048tz. False if the base could not be
    /// read, and then the caller falls back to the fixed sentence.
    fn setHashCeilingText(self: *Zuid, base: []const u8) bool {
        const name = if (base.len == 0) core.default_base else base;
        const radix = self.wasm_host.converter().radix(name) catch return false;
        const written = std.fmt.bufPrint(
            self.err_buf[0 .. self.err_buf.len - 1],
            "hash width {d}: base {s} carries at most {d} symbols of a 256-bit digest",
            .{ self.hash_chars, name, core.maxHashChars(radix) },
        ) catch return false;
        self.err_buf[written.len] = 0;
        return true;
    }
};

/// Every entry point goes through this, so a null or already-freed context is
/// rejected rather than followed.
fn checked(z: ?*Zuid) ?*Zuid {
    const self = z orelse return null;
    if (self.magic != live_magic) return null;
    return self;
}

pub export fn zuid_new() ?*Zuid {
    const self = gpa.create(Zuid) catch return null;
    self.wasm_host = host.Host.init(.auto) catch {
        gpa.destroy(self);
        return null;
    };
    self.magic = live_magic;
    self.live_env = .{};
    self.fixed_clock_ms = null;
    self.precision = core.Precision.default;
    self.no_hash = false;
    // Zero means the derived default for whatever base each call renders in.
    self.hash_chars = 0;
    self.random_chars = 0;
    self.err_buf[0] = 0;
    return self;
}

pub export fn zuid_free(z: ?*Zuid) void {
    const self = checked(z) orelse return;
    self.magic = 0;
    self.wasm_host.deinit();
    gpa.destroy(self);
}

pub export fn zuid_generate(z: ?*Zuid, format: ?[*:0]const u8, base: ?[*:0]const u8, out: ?[*]u8, out_cap: usize) c_int {
    const self = checked(z) orelse return 7;
    const out_ptr = out orelse return 5;
    if (out_cap == 0) return 5;
    self.err_buf[0] = 0;
    // The host keeps its text until something overwrites it, and the failures
    // below can happen before the converter is ever called. Without this,
    // zuid_last_error would answer with the previous call's message.
    self.wasm_host.clearErr();
    out_ptr[0] = 0;

    const fmt: []const u8 = if (format) |format_z| std.mem.span(format_z) else "";
    const now = self.fixed_clock_ms orelse clock.nowMs() orelse {
        self.setErrText("the system clock could not be read");
        return 10;
    };
    const opts = core.Options{
        .format = if (fmt.len == 0) "%d" else fmt,
        .base = if (base) |base_z| std.mem.span(base_z) else "",
        .precision = self.precision,
        .clock_ms = now,
        .no_hash = self.no_hash,
        .hash_chars = self.hash_chars,
        .random_chars = self.random_chars,
    };

    var id_buf: [core.out_buf_len]u8 = undefined;
    const id = core.generate(self.wasm_host.converter(), self.live_env.env(), opts, &id_buf) catch |err| {
        const reported = self.wasm_host.lastError();
        // The ceiling depends on the base, so "too wide" on its own leaves the
        // caller guessing what would fit. Everything else either has the
        // library's own text or a fixed sentence.
        if (err != core.Error.HashTooWide or !self.setHashCeilingText(opts.base)) {
            self.setErrText(if (reported.len > 0) reported else textFor(err));
        }
        return codeFor(err);
    };
    if (id.len + 1 > out_cap) return 5;
    @memcpy(out_ptr[0..id.len], id);
    out_ptr[id.len] = 0;
    return 0;
}

pub export fn zuid_set_precision(z: ?*Zuid, precision: c_int) c_int {
    const self = checked(z) orelse return 7;
    self.precision = core.Precision.fromInt(precision) orelse return 8;
    return 0;
}

pub export fn zuid_set_hashing(z: ?*Zuid, enabled: c_int) void {
    const self = checked(z) orelse return;
    self.no_hash = enabled == 0;
}

pub export fn zuid_set_hash_chars(z: ?*Zuid, chars: c_int) c_int {
    const self = checked(z) orelse return 7;
    if (!inRange(chars)) return 9;
    self.hash_chars = @intCast(chars);
    return 0;
}

pub export fn zuid_set_random_chars(z: ?*Zuid, chars: c_int) c_int {
    const self = checked(z) orelse return 7;
    if (!inRange(chars)) return 9;
    self.random_chars = @intCast(chars);
    return 0;
}

/// Zero is the way back to the derived default, so it is not out of range.
fn inRange(chars: c_int) bool {
    return chars >= 0 and chars <= core.max_component_chars;
}

pub export fn zuid_set_clock_ms(z: ?*Zuid, ms: c_longlong) void {
    const self = checked(z) orelse return;
    self.fixed_clock_ms = ms;
}

pub export fn zuid_clear_clock(z: ?*Zuid) void {
    const self = checked(z) orelse return;
    self.fixed_clock_ms = null;
}

pub export fn zuid_last_error(z: ?*const Zuid) [*:0]const u8 {
    const self = z orelse return "";
    if (self.magic != live_magic) return "";
    return @ptrCast(&self.err_buf);
}

pub export fn zuid_version() [*:0]const u8 {
    return core.version;
}
