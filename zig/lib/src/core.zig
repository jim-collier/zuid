// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Identifier core: format parsing, components, assembly, fixed-width padding.
//! Deliberately takes no allocator - every intermediate fits a stack buffer and
//! the result lands in a caller-supplied one, so there is no pointer to dangle
//! and no free contract for the C module to get wrong. Base conversion is
//! reached through the Converter interface; this file never touches the wasm
//! host directly, which is what lets the tests swap it out.

const std = @import("std");

pub const version = "0.1.0";

pub const default_base = "62";

/// The short list the help screen shows. --base still accepts anything the
/// conversion library knows; these are the ones that sort and transcribe well.
pub const curated_bases = [_][]const u8{ "16", "32w", "36", "62" };

/// Largest timestamp the fixed width must hold: 2500-01-01 UTC. Width is
/// quantized so coarsely that the exact horizon barely matters; move it and
/// the widths follow.
pub const horizon_ms: u64 = 16725225600000;

/// Enough for any single rendered component: a 13-digit decimal in base 2 is
/// 44 digits, and no base's digit symbol exceeds 4 bytes.
pub const component_buf_len = 256;

/// Sized for several components plus literal text between them.
pub const out_buf_len = 512;

pub const Error = error{
    /// Base name or alias resolves to nothing. The converter's error text
    /// carries near-match suggestions.
    UnknownBase,
    /// The conversion library rejected the input or the request.
    BadInput,
    /// %h %u %f %m %g %r: reserved by the spec, not implemented yet. An error
    /// beats silently dropping them - the format string would look like it
    /// worked.
    ReservedComponent,
    UnknownComponent,
    /// Format string ends on a bare '%'.
    BareFormatPercent,
    ClockBeforeEpoch,
    /// The rendered value needs more symbols than the fixed width allows,
    /// meaning the clock is past the padding horizon.
    WidthOverflow,
    BufferTooSmall,
    /// The converter failed for a reason of its own; ask it for the text.
    ConvertFailed,
};

/// What the core needs from base conversion, and nothing more: one-shot
/// convert, plus the base metadata that fixed-width padding depends on.
pub const Converter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Renders a decimal integer string in the named base, into out.
        convert: *const fn (ctx: *anyopaque, value_dec: []const u8, to_base: []const u8, out: []u8) Error![]const u8,
        radix: *const fn (ctx: *anyopaque, base: []const u8) Error!u64,
        /// The base's first symbol - the padding digit. 32w starts at '2', so
        /// assuming '0' pads wrongly.
        zeroSymbol: *const fn (ctx: *anyopaque, base: []const u8, out: []u8) Error![]const u8,
        /// Symbols, not bytes: some bases have multi-byte digits.
        symbolCount: *const fn (ctx: *anyopaque, base: []const u8, digits: []const u8) Error!u64,
    };

    pub fn convert(self: Converter, value_dec: []const u8, to_base: []const u8, out: []u8) Error![]const u8 {
        return self.vtable.convert(self.ctx, value_dec, to_base, out);
    }
    pub fn radix(self: Converter, base: []const u8) Error!u64 {
        return self.vtable.radix(self.ctx, base);
    }
    pub fn zeroSymbol(self: Converter, base: []const u8, out: []u8) Error![]const u8 {
        return self.vtable.zeroSymbol(self.ctx, base, out);
    }
    pub fn symbolCount(self: Converter, base: []const u8, digits: []const u8) Error!u64 {
        return self.vtable.symbolCount(self.ctx, base, digits);
    }
};

/// Smallest symbol count that holds any timestamp up to the horizon.
/// Lexicographic compare reads left to right, so a short identifier and a long
/// one cannot sort chronologically - this fixed width is what makes the sort
/// guarantee hold, not the choice of alphabet.
pub fn widthFor(radix: u64) u32 {
    var width: u32 = 1;
    var capacity: u64 = radix;
    while (capacity <= horizon_ms) {
        // Grows past horizon_ms well before u64 overflows for any radix >= 2.
        capacity *= radix;
        width += 1;
    }
    return width;
}

/// Renders one identifier into out and returns the filled slice.
/// An empty base_name means the default base.
pub fn generate(conv: Converter, format: []const u8, base_name: []const u8, clock_ms: i64, out: []u8) Error![]const u8 {
    const base = if (base_name.len == 0) default_base else base_name;
    var used: usize = 0;
    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] != '%') {
            if (used == out.len) return Error.BufferTooSmall;
            out[used] = format[i];
            used += 1;
            continue;
        }
        i += 1;
        if (i == format.len) return Error.BareFormatPercent;
        switch (format[i]) {
            '%' => {
                if (used == out.len) return Error.BufferTooSmall;
                out[used] = '%';
                used += 1;
            },
            'd' => {
                const rendered = try timeComponent(conv, base, clock_ms, out[used..]);
                used += rendered.len;
            },
            'h', 'u', 'f', 'm', 'g', 'r' => return Error.ReservedComponent,
            else => return Error.UnknownComponent,
        }
    }
    return out[0..used];
}

/// The clock as milliseconds since the Unix epoch UTC, converted and
/// zero-padded to the fixed width for this base.
fn timeComponent(conv: Converter, base: []const u8, clock_ms: i64, out: []u8) Error![]const u8 {
    if (clock_ms < 0) return Error.ClockBeforeEpoch;

    var dec_buf: [20]u8 = undefined;
    const dec = std.fmt.bufPrint(&dec_buf, "{d}", .{clock_ms}) catch unreachable;

    var conv_buf: [component_buf_len]u8 = undefined;
    const converted = try conv.convert(dec, base, &conv_buf);

    const width = widthFor(try conv.radix(base));
    const count = try conv.symbolCount(base, converted);
    if (count > width) return Error.WidthOverflow;

    var zero_buf: [8]u8 = undefined;
    const zero = try conv.zeroSymbol(base, &zero_buf);

    const pad: usize = @intCast(width - count);
    if (pad * zero.len + converted.len > out.len) return Error.BufferTooSmall;
    var used: usize = 0;
    for (0..pad) |_| {
        @memcpy(out[used .. used + zero.len], zero);
        used += zero.len;
    }
    @memcpy(out[used .. used + converted.len], converted);
    return out[0 .. used + converted.len];
}

test "widthFor matches the design table" {
    try std.testing.expectEqual(@as(u32, 11), widthFor(16));
    try std.testing.expectEqual(@as(u32, 9), widthFor(32));
    try std.testing.expectEqual(@as(u32, 9), widthFor(36));
    try std.testing.expectEqual(@as(u32, 8), widthFor(62));
}
