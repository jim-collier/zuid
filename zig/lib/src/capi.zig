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
    .debug => debug_allocator.allocator(),
    else => std.heap.smp_allocator,
};

// Nothing can call deinit() on that allocator: a C caller never tells the
// library it is done, so there is no last moment to check in. That left the
// design's leak-detection claim resting on a check that never ran. These two
// give the tests somewhere to ask instead.
//
// Debug only, so a release build carries neither the counter nor the chance of
// it wrapping on a caller's double free - which is already outside the
// contract the header states.
const counts_contexts = builtin.mode == .debug;
var live_contexts: usize = 0;

/// Contexts created and not yet freed. Always zero in a release build.
pub fn liveContexts() usize {
    return live_contexts;
}

/// Allocations the debug allocator can still see, with a stack trace printed
/// per leak. Always zero in a release build, which has no such allocator.
pub fn leakCount() usize {
    return switch (builtin.mode) {
        .debug => debug_allocator.detectLeaks(),
        else => 0,
    };
}

// Codes from zuid.h. Kept in one switch so a new core error fails loudly here.
pub fn codeFor(err: core.Error) c_int {
    return switch (err) {
        core.Error.UnknownBase => 1,
        core.Error.BareFormatPercent, core.Error.UnknownComponent => 2,
        core.Error.BadInput => 4,
        core.Error.BufferTooSmall => 5,
        core.Error.ClockBeforeEpoch => 6,
        core.Error.RuntimeFailed => 7,
        core.Error.OptionRange, core.Error.HashTooWide, core.Error.SaltTooLong => 9,
        core.Error.EnvUnavailable => 10,
        core.Error.WidthOverflow => 12,
        core.Error.BaseNotText => 13,
    };
}

/// Explanation for the failures that never reach the conversion library, and
/// so leave it with nothing to say. Empty means the library's own text stands.
pub fn textFor(err: core.Error) []const u8 {
    return switch (err) {
        core.Error.WidthOverflow => "the clock is past the padding horizon, so the timestamp no longer fits its fixed width",
        core.Error.ClockBeforeEpoch => "the clock predates the Unix epoch",
        core.Error.BareFormatPercent => "the format string ends on a bare '%'",
        core.Error.UnknownComponent => "unknown format component; known: %d %h %u %f %m %g %r, and %% for a literal",
        core.Error.OptionRange => std.fmt.comptimePrint("a symbol count is out of range: want 1 to {d}", .{core.max_component_chars}),
        core.Error.HashTooWide => "a hashed component cannot be wider than a SHA-256 fills in that base",
        core.Error.SaltTooLong => "the salt is longer than ZUID_MAX_SALT_BYTES",
        core.Error.EnvUnavailable => "this machine could not supply that component",
        core.Error.BaseNotText => "that base renders raw bytes or control characters rather than text, so it cannot carry an identifier",
        core.Error.BufferTooSmall => "out_cap is too small for the identifier plus its terminating NUL",
        core.Error.RuntimeFailed => "the embedded wasm runtime or its module failed",
        else => "",
    };
}

// Stamped into a live context and cleared on free, so a stale pointer is
// usually rejected rather than followed. Only usually: once the allocator
// hands the pages back there is nothing left to read, which is the
// use-after-free gap the design notes describe. Cheap, and better than
// nothing.
const live_magic: u32 = 0x7A554944;

/// zuid_request from zuid.h. All zero is every default, the same as Go's zero
/// Request, and the field order follows it.
pub const Request = extern struct {
    format: ?[*:0]const u8 = null,
    base: ?[*:0]const u8 = null,
    precision: c_int = 0,
    no_hash: c_int = 0,
    hash_chars: c_int = 0,
    random_chars: c_int = 0,
    salt: ?[*:0]const u8 = null,
};

/// Public only so the fuzz test can name the handle type. C sees it as opaque.
/// It holds the runtime and the machine's own values, never a caller's
/// choices: those come with each call, so two callers sharing a context
/// cannot change each other's output.
pub const Zuid = struct {
    magic: u32,
    wasm_host: host.Host,
    live_env: env.Live,
    fixed_clock_ms: ?i64,
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
    fn setHashCeilingText(self: *Zuid, base: []const u8, hash_chars: u32) bool {
        const name = if (base.len == 0) core.default_base else base;
        const radix = self.wasm_host.converter().radix(name) catch return false;
        const written = std.fmt.bufPrint(
            self.err_buf[0 .. self.err_buf.len - 1],
            "hash width {d}: base {s} carries at most {d} symbols of a 256-bit digest",
            .{ hash_chars, name, core.maxHashChars(radix) },
        ) catch return false;
        self.err_buf[written.len] = 0;
        return true;
    }
};

/// Every entry point goes through this, so a null or already-freed context is
/// rejected rather than followed, with ZUID_ERR_CONTEXT where there is a code.
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
    self.err_buf[0] = 0;
    if (counts_contexts) live_contexts += 1;
    return self;
}

pub export fn zuid_free(z: ?*Zuid) void {
    const self = checked(z) orelse return;
    self.magic = 0;
    self.wasm_host.deinit();
    gpa.destroy(self);
    if (counts_contexts) live_contexts -= 1;
}

const err_context = 14;

pub export fn zuid_generate(z: ?*Zuid, request: ?*const Request, out: ?[*]u8, out_cap: usize) c_int {
    const self = checked(z) orelse return err_context;
    const req: Request = if (request) |given| given.* else .{};
    // Cleared before the buffer is checked, so a rejected buffer reports its own
    // reason rather than whatever the previous call left behind.
    self.err_buf[0] = 0;
    // The host keeps its text until something overwrites it, and the failures
    // below can happen before the converter is ever called. Without this,
    // zuid_last_error would answer with the previous call's message.
    self.wasm_host.clearErr();

    const out_ptr = out orelse {
        self.setErrText("out is NULL, so there is nowhere to write the identifier");
        return 5;
    };
    if (out_cap == 0) {
        self.setErrText("out_cap is 0, which leaves no room even for the terminating NUL");
        return 5;
    }
    out_ptr[0] = 0;

    const precision = core.Precision.fromInt(req.precision) orelse {
        self.setErrText("precision is not -1, 0, or 1");
        return 8;
    };
    const fmt: []const u8 = if (req.format) |format_z| std.mem.span(format_z) else "";
    const now = self.fixed_clock_ms orelse clock.nowMs() orelse {
        self.setErrText("the system clock could not be read");
        return 10;
    };
    const opts = core.Options{
        .format = if (fmt.len == 0) "%d" else fmt,
        .base = if (req.base) |base_z| std.mem.span(base_z) else "",
        .precision = precision,
        .clock_ms = now,
        .no_hash = req.no_hash != 0,
        .hash_chars = chars(req.hash_chars),
        .random_chars = chars(req.random_chars),
        .salt = if (req.salt) |salt_z| std.mem.span(salt_z) else "",
    };

    // Straight into the caller's buffer, minus the byte the NUL needs. This
    // used to render into a fixed 4096-byte buffer first, which meant any
    // identifier over that size was refused as ZUID_ERR_BUFFER however large
    // out_cap was - a format the Go module renders happily. The only limit now
    // is the one the header documents.
    const room = out_ptr[0 .. out_cap - 1];
    const id = core.generate(self.wasm_host.converter(), self.live_env.env(), opts, room) catch |err| {
        // Rendering happens in place now, so a failure part way through leaves
        // its own partial output behind. The header promises an empty string.
        out_ptr[0] = 0;
        const reported = self.wasm_host.lastError();
        // The ceiling depends on the base, so "too wide" on its own leaves the
        // caller guessing what would fit. Everything else either has the
        // library's own text or a fixed sentence.
        if (err != core.Error.HashTooWide or !self.setHashCeilingText(opts.base, opts.hash_chars)) {
            self.setErrText(if (reported.len > 0) reported else textFor(err));
        }
        return codeFor(err);
    };
    out_ptr[id.len] = 0;
    return 0;
}

/// A width as the core takes it. A negative one becomes one past the ceiling,
/// so the core refuses it only when the format spends it, as Go does.
fn chars(count: c_int) u32 {
    if (count < 0) return core.max_component_chars + 1;
    return @intCast(count);
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
