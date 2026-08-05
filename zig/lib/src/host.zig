// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Wasmtime host for the upstream convert-base reactor module. Implements the
//! core's Converter interface by driving the module's documented ABI: strings
//! travel through its linear memory via alloc/free regions, results come back
//! packed as (pointer << 32) | length. The module bytes are embedded at build
//! time, so the binary is self-contained.
//!
//! Wasmtime owns all of its memory; on this side the Host is a plain struct
//! the caller places wherever it likes - no allocator here either.

const std = @import("std");
const core = @import("core.zig");

const c = @cImport({
    @cInclude("wasm.h");
    @cInclude("wasi.h");
    @cInclude("wasmtime.h");
});

// Registered in build.zig as an anonymous import pointing at zig/vendor/,
// where cicd builds it from the same pinned convertbase release the Go module
// imports - which is what stops the two sides reaching different library
// versions.
const reactor_wasm = @embedFile("convert-base-reactor.wasm");

// ABI error codes, from the reactor's README. Stable by contract.
const abi_err_unknown_base = 1;
const abi_err_internal = 7;

pub const InitError = error{
    RuntimeFailed,
    ModuleInvalid,
    InstantiateFailed,
    MissingExport,
};

/// Winch compiles the module in well under half the time cranelift takes, but
/// _initialize - the Go runtime building its base registry inside the module -
/// dominates startup and runs a couple of hundred milliseconds slower under
/// winch code. Cranelift wins end to end, so auto is the default; winch stays
/// for the tests to cross-check both compilers against the vectors.
pub const Strategy = enum { auto, winch };

pub const Host = struct {
    engine: *c.wasm_engine_t,
    store: *c.wasmtime_store_t,
    context: ?*c.wasmtime_context_t,
    module: ?*c.wasmtime_module_t,
    linker: ?*c.wasmtime_linker_t,
    instance: c.wasmtime_instance_t,
    memory: c.wasmtime_memory_t,
    f_alloc: c.wasmtime_func_t,
    f_free: c.wasmtime_func_t,
    f_convert: c.wasmtime_func_t,
    f_base_radix: c.wasmtime_func_t,
    f_base_zero: c.wasmtime_func_t,
    f_fit: c.wasmtime_func_t,
    f_symbol_count: c.wasmtime_func_t,
    f_last_error_code: c.wasmtime_func_t,
    f_last_error_text: c.wasmtime_func_t,
    f_version: c.wasmtime_func_t,
    f_region_count: c.wasmtime_func_t,
    err_buf: [err_buf_len]u8,
    err_len: usize,
    base_cache: BaseCache,

    pub const err_buf_len = 512;

    /// A base's radix and zero digit do not change, and every component asks
    /// for one or the other. One slot is enough: an identifier renders in a
    /// single base, and a name too long for the slot just misses and calls the
    /// module, which is correct if slower.
    const BaseCache = struct {
        name: [64]u8 = undefined,
        name_len: usize = 0,
        radix: ?u64 = null,
        zero: [16]u8 = undefined,
        zero_len: ?usize = null,

        fn holds(self: *const BaseCache, base: []const u8) bool {
            return self.name_len == base.len and std.mem.eql(u8, self.name[0..self.name_len], base);
        }

        /// Points the slot at base, discarding whatever it held for another one.
        fn aim(self: *BaseCache, base: []const u8) void {
            if (self.holds(base)) return;
            self.name_len = 0;
            self.radix = null;
            self.zero_len = null;
            if (base.len > self.name.len) return;
            @memcpy(self.name[0..base.len], base);
            self.name_len = base.len;
        }
    };

    pub fn init(strategy: Strategy) InitError!Host {
        const config = c.wasm_config_new() orelse return InitError.RuntimeFailed;
        if (strategy == .winch) c.wasmtime_config_strategy_set(config, c.WASMTIME_STRATEGY_WINCH);
        // wasm_engine_new_with_config consumes config, even on failure.
        const engine = c.wasm_engine_new_with_config(config) orelse return InitError.RuntimeFailed;
        errdefer c.wasm_engine_delete(engine);

        const store = c.wasmtime_store_new(engine, null, null) orelse return InitError.RuntimeFailed;
        errdefer c.wasmtime_store_delete(store);
        const context = c.wasmtime_store_context(store);

        // The reactor imports only the standard wasi_snapshot_preview1 set; an
        // empty WASI config grants it no files, no env, no args.
        const wasi = c.wasi_config_new() orelse return InitError.RuntimeFailed;
        if (c.wasmtime_context_set_wasi(context, wasi)) |err| {
            c.wasmtime_error_delete(err);
            return InitError.RuntimeFailed;
        }

        const linker = c.wasmtime_linker_new(engine) orelse return InitError.RuntimeFailed;
        errdefer c.wasmtime_linker_delete(linker);
        if (c.wasmtime_linker_define_wasi(linker)) |err| {
            c.wasmtime_error_delete(err);
            return InitError.RuntimeFailed;
        }

        var module: ?*c.wasmtime_module_t = null;
        if (c.wasmtime_module_new(engine, reactor_wasm.ptr, reactor_wasm.len, &module)) |err| {
            c.wasmtime_error_delete(err);
            return InitError.ModuleInvalid;
        }
        errdefer c.wasmtime_module_delete(module);

        var trap: ?*c.wasm_trap_t = null;
        var instance: c.wasmtime_instance_t = undefined;
        if (c.wasmtime_linker_instantiate(linker, context, module, &instance, &trap)) |err| {
            c.wasmtime_error_delete(err);
            return InitError.InstantiateFailed;
        }
        if (trap) |trapped| {
            c.wasm_trap_delete(trapped);
            return InitError.InstantiateFailed;
        }

        var host = Host{
            .engine = engine,
            .store = store,
            .context = context,
            .module = module,
            .linker = linker,
            .instance = instance,
            .memory = undefined,
            .f_alloc = undefined,
            .f_free = undefined,
            .f_convert = undefined,
            .f_base_radix = undefined,
            .f_base_zero = undefined,
            .f_fit = undefined,
            .f_symbol_count = undefined,
            .f_last_error_code = undefined,
            .f_last_error_text = undefined,
            .f_version = undefined,
            .f_region_count = undefined,
            .err_buf = undefined,
            .err_len = 0,
            .base_cache = .{},
        };

        host.memory = (try host.memoryExport("memory")).of.memory;
        host.f_alloc = (try host.funcExport("alloc")).of.func;
        host.f_free = (try host.funcExport("free")).of.func;
        host.f_convert = (try host.funcExport("convert")).of.func;
        host.f_base_radix = (try host.funcExport("base_radix")).of.func;
        host.f_base_zero = (try host.funcExport("base_zero")).of.func;
        host.f_fit = (try host.funcExport("fit")).of.func;
        host.f_symbol_count = (try host.funcExport("symbol_count")).of.func;
        host.f_last_error_code = (try host.funcExport("last_error_code")).of.func;
        host.f_last_error_text = (try host.funcExport("last_error_text")).of.func;
        host.f_version = (try host.funcExport("version")).of.func;
        host.f_region_count = (try host.funcExport("region_count")).of.func;

        // A reactor is not live until _initialize runs; skipping it reads as a
        // corrupt binary later.
        const f_init = (try host.funcExport("_initialize")).of.func;
        if (c.wasmtime_func_call(context, &f_init, null, 0, null, 0, &trap)) |err| {
            c.wasmtime_error_delete(err);
            return InitError.InstantiateFailed;
        }
        if (trap) |trapped| {
            c.wasm_trap_delete(trapped);
            return InitError.InstantiateFailed;
        }

        return host;
    }

    pub fn deinit(self: *Host) void {
        c.wasmtime_module_delete(self.module);
        c.wasmtime_linker_delete(self.linker);
        c.wasmtime_store_delete(self.store);
        c.wasm_engine_delete(self.engine);
        self.* = undefined;
    }

    /// A named export of the kind asked for. The kind check is what stops a
    /// renamed or retyped upstream export being read through the wrong arm of
    /// the extern union, which would hand Wasmtime a garbage handle instead of
    /// failing here.
    fn exportOf(self: *Host, name: []const u8, kind: c.wasmtime_extern_kind_t) InitError!c.wasmtime_extern_t {
        var item: c.wasmtime_extern_t = undefined;
        if (!c.wasmtime_instance_export_get(self.context, &self.instance, name.ptr, name.len, &item)) {
            return InitError.MissingExport;
        }
        if (item.kind != kind) return InitError.MissingExport;
        return item;
    }

    fn funcExport(self: *Host, name: []const u8) InitError!c.wasmtime_extern_t {
        return self.exportOf(name, c.WASMTIME_EXTERN_FUNC);
    }

    fn memoryExport(self: *Host, name: []const u8) InitError!c.wasmtime_extern_t {
        return self.exportOf(name, c.WASMTIME_EXTERN_MEMORY);
    }

    /// Text of the most recent failure, empty when there was none. Valid until
    /// the next call on this host.
    pub fn lastError(self: *const Host) []const u8 {
        return self.err_buf[0..self.err_len];
    }

    pub fn converter(self: *Host) core.Converter {
        return .{ .ctx = self, .vtable = &converter_vtable };
    }

    /// The conversion library's own version string, for --version output.
    pub fn libVersion(self: *Host, out: []u8) core.Error![]const u8 {
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_version, &.{}, &results);
        const packed_str: u64 = @bitCast(results[0].of.i64);
        if (packed_str == 0) return self.fail();
        return self.readPacked(packed_str, out);
    }

    /// The module's ledger of outstanding regions; the tests hold it at zero.
    pub fn regionCount(self: *Host) core.Error!u32 {
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_region_count, &.{}, &results);
        return @bitCast(results[0].of.i32);
    }

    const converter_vtable = core.Converter.VTable{
        .convert = vtConvert,
        .radix = vtRadix,
        .fit = vtFit,
        .symbolCount = vtSymbolCount,
        .zeroSymbol = vtZeroSymbol,
    };

    fn vtConvert(ctx: *anyopaque, value_in: []const u8, from_base: []const u8, to_base: []const u8, out: []u8) core.Error![]const u8 {
        const self: *Host = @ptrCast(@alignCast(ctx));
        self.clearErr();
        const from = try self.putStr(from_base);
        defer self.freeRegion(from.ptr);
        const to = try self.putStr(to_base);
        defer self.freeRegion(to.ptr);
        const value = try self.putStr(value_in);
        defer self.freeRegion(value.ptr);

        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_convert, &.{
            valU32(from.ptr),  valU32(from.len),
            valU32(to.ptr),    valU32(to.len),
            valU32(value.ptr), valU32(value.len),
            valI32(-1),
        }, &results);
        const packed_str: u64 = @bitCast(results[0].of.i64);
        if (packed_str == 0) return self.fail();
        defer self.freeRegion(@truncate(packed_str >> 32));
        return self.readPacked(packed_str, out);
    }

    fn vtRadix(ctx: *anyopaque, base: []const u8) core.Error!u64 {
        const self: *Host = @ptrCast(@alignCast(ctx));
        self.base_cache.aim(base);
        if (self.base_cache.radix) |cached| return cached;

        self.clearErr();
        const name = try self.putStr(base);
        defer self.freeRegion(name.ptr);
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_base_radix, &.{ valU32(name.ptr), valU32(name.len) }, &results);
        const radix = results[0].of.i64;
        if (radix < 0) return self.fail();

        const value: u64 = @intCast(radix);
        if (self.base_cache.holds(base)) self.base_cache.radix = value;
        return value;
    }

    fn vtFit(ctx: *anyopaque, base: []const u8, digits: []const u8, width: u32, out: []u8) core.Error![]const u8 {
        const self: *Host = @ptrCast(@alignCast(ctx));
        self.clearErr();
        const name = try self.putStr(base);
        defer self.freeRegion(name.ptr);
        const digits_region = try self.putStr(digits);
        defer self.freeRegion(digits_region.ptr);
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_fit, &.{
            valU32(name.ptr),          valU32(name.len),
            valU32(digits_region.ptr), valU32(digits_region.len),
            valU32(width),
        }, &results);
        const packed_str: u64 = @bitCast(results[0].of.i64);
        if (packed_str == 0) return self.fail();
        defer self.freeRegion(@truncate(packed_str >> 32));
        return self.readPacked(packed_str, out);
    }

    fn vtZeroSymbol(ctx: *anyopaque, base: []const u8, out: []u8) core.Error![]const u8 {
        const self: *Host = @ptrCast(@alignCast(ctx));
        self.base_cache.aim(base);
        if (self.base_cache.zero_len) |len| {
            if (len > out.len) return core.Error.BufferTooSmall;
            @memcpy(out[0..len], self.base_cache.zero[0..len]);
            return out[0..len];
        }

        self.clearErr();
        const name = try self.putStr(base);
        defer self.freeRegion(name.ptr);
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_base_zero, &.{ valU32(name.ptr), valU32(name.len) }, &results);
        const packed_str: u64 = @bitCast(results[0].of.i64);
        if (packed_str == 0) return self.fail();
        defer self.freeRegion(@truncate(packed_str >> 32));

        const zero = try self.readPacked(packed_str, out);
        if (self.base_cache.holds(base) and zero.len <= self.base_cache.zero.len) {
            @memcpy(self.base_cache.zero[0..zero.len], zero);
            self.base_cache.zero_len = zero.len;
        }
        return zero;
    }

    fn vtSymbolCount(ctx: *anyopaque, base: []const u8, digits: []const u8) core.Error!u64 {
        const self: *Host = @ptrCast(@alignCast(ctx));
        self.clearErr();
        const name = try self.putStr(base);
        defer self.freeRegion(name.ptr);
        const digits_region = try self.putStr(digits);
        defer self.freeRegion(digits_region.ptr);
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_symbol_count, &.{
            valU32(name.ptr),          valU32(name.len),
            valU32(digits_region.ptr), valU32(digits_region.len),
        }, &results);
        const count = results[0].of.i64;
        if (count < 0) return self.fail();
        return @intCast(count);
    }

    const Region = struct { ptr: u32, len: u32 };

    /// Public because the C module clears it before a call that may fail
    /// before ever reaching the converter - otherwise zuid_last_error would
    /// report whatever the previous call left behind.
    pub fn clearErr(self: *Host) void {
        self.err_len = 0;
    }

    fn setErr(self: *Host, msg: []const u8) void {
        var kept = @min(msg.len, self.err_buf.len);
        // Back off to a codepoint boundary. Near-match suggestions quote base
        // names, and the wide alphabets are several bytes per symbol, so a
        // blind cut can leave a half-written character.
        while (kept > 0 and kept < msg.len and msg[kept] & 0xc0 == 0x80) kept -= 1;
        @memcpy(self.err_buf[0..kept], msg[0..kept]);
        self.err_len = kept;
    }

    /// Captures the module's last-error state and maps its code onto the
    /// core's error set. Copies the text out first - the next call overwrites
    /// the module-owned buffer.
    fn fail(self: *Host) core.Error {
        var results: [1]c.wasmtime_val_t = undefined;
        self.call(&self.f_last_error_code, &.{}, &results) catch return core.Error.ConvertFailed;
        const code = results[0].of.i32;
        self.call(&self.f_last_error_text, &.{}, &results) catch return core.Error.ConvertFailed;
        const packed_str: u64 = @bitCast(results[0].of.i64);
        if (packed_str != 0) {
            var text_buf: [err_buf_len]u8 = undefined;
            const text = self.readPacked(packed_str, &text_buf) catch return core.Error.ConvertFailed;
            self.setErr(text);
        }
        return switch (code) {
            abi_err_unknown_base => core.Error.UnknownBase,
            abi_err_internal => core.Error.ConvertFailed,
            else => core.Error.BadInput,
        };
    }

    /// One export call. Wasmtime errors and traps are both caught here, and
    /// their message becomes the host's error text.
    fn call(self: *Host, func: *const c.wasmtime_func_t, args: []const c.wasmtime_val_t, results: []c.wasmtime_val_t) core.Error!void {
        var trap: ?*c.wasm_trap_t = null;
        const err = c.wasmtime_func_call(self.context, func, args.ptr, args.len, results.ptr, results.len, &trap);
        if (err) |failure| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasmtime_error_message(failure, &msg);
            self.setErr(msg.data[0..msg.size]);
            c.wasm_byte_vec_delete(&msg);
            c.wasmtime_error_delete(failure);
            return core.Error.ConvertFailed;
        }
        if (trap) |trapped| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasm_trap_message(trapped, &msg);
            self.setErr(msg.data[0..msg.size]);
            c.wasm_byte_vec_delete(&msg);
            c.wasm_trap_delete(trapped);
            return core.Error.ConvertFailed;
        }
    }

    /// Copies s into a module region. The data pointer is fetched after the
    /// alloc call: linear memory can move when it grows.
    fn putStr(self: *Host, text: []const u8) core.Error!Region {
        if (text.len == 0) return .{ .ptr = 0, .len = 0 };
        var results: [1]c.wasmtime_val_t = undefined;
        try self.call(&self.f_alloc, &.{valU32(@intCast(text.len))}, &results);
        const ptr: u32 = @bitCast(results[0].of.i32);
        if (ptr == 0) return self.fail();
        const memory = self.memoryBytes();
        if (@as(usize, ptr) + text.len > memory.len) return core.Error.ConvertFailed;
        @memcpy(memory[ptr..][0..text.len], text);
        return .{ .ptr = ptr, .len = @intCast(text.len) };
    }

    /// Linear memory as a bounds-carrying slice. The raw C pointer has no
    /// length, so a pointer the module returned would otherwise be trusted
    /// blind - and the module is rebuilt from upstream, not frozen here.
    fn memoryBytes(self: *Host) []u8 {
        const data = c.wasmtime_memory_data(self.context, &self.memory);
        const size = c.wasmtime_memory_data_size(self.context, &self.memory);
        return data[0..size];
    }

    /// Failing to free is a leak in the module's ledger, not a crash; nothing
    /// useful can be done about it mid-error, so the result is dropped.
    fn freeRegion(self: *Host, ptr: u32) void {
        if (ptr == 0) return;
        var results: [1]c.wasmtime_val_t = undefined;
        self.call(&self.f_free, &.{valU32(ptr)}, &results) catch {};
    }

    fn readPacked(self: *Host, packed_str: u64, out: []u8) core.Error![]const u8 {
        const ptr: u32 = @truncate(packed_str >> 32);
        const len: u32 = @truncate(packed_str);
        if (len > out.len) return core.Error.BufferTooSmall;
        const memory = self.memoryBytes();
        if (@as(usize, ptr) + len > memory.len) return core.Error.ConvertFailed;
        @memcpy(out[0..len], memory[ptr..][0..len]);
        return out[0..len];
    }
};

fn valU32(value: u32) c.wasmtime_val_t {
    return .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = @bitCast(value) } };
}

fn valI32(value: i32) c.wasmtime_val_t {
    return .{ .kind = c.WASMTIME_I32, .of = .{ .i32 = value } };
}
