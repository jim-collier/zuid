// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Identifier core: format parsing, components, assembly, fixed-width padding.
//! Deliberately takes no allocator - every intermediate fits a stack buffer and
//! the result lands in a caller-supplied one, so there is no pointer to dangle
//! and no free contract for the C module to get wrong. Base conversion is
//! reached through the Converter interface and the machine's own state through
//! the Env interface; this file touches neither the wasm host nor the operating
//! system directly, which is what lets the tests swap both out.

const std = @import("std");

pub const version = "0.1.0";

pub const default_base = "62";

/// The short list the help screen shows. --base still accepts anything the
/// conversion library knows; these are the ones that sort and transcribe well.
pub const curated_bases = [_][]const u8{ "16", "32w", "36", "62" };

/// Symbols kept from a hashed component. Eight in base 62 is around 47 bits of
/// fingerprint, which is enough that two hosts colliding is not a real worry.
pub const default_hash_chars: u32 = 8;

/// Symbols %r emits.
pub const default_random_chars: u32 = 6;

/// Upper bound on both, so a format string cannot ask for an identifier that
/// will not fit a caller's buffer.
pub const max_component_chars: u32 = 64;

/// Bit widths of the fixed-size components, which is what their output widths
/// are derived from.
const mac_bits = 48;
const uuid_bits = 128;

/// Largest timestamp the fixed width must hold: 3000-01-01 UTC. Width is
/// quantized so coarsely that the exact horizon barely matters; move it and
/// the widths follow.
pub const horizon_ms: u64 = 32503680000000;

/// Time unit for the %d component, carrying the predecessor's surface
/// forward: -1 minute, 0 second (the default), 1 millisecond. The clock is
/// always injected in milliseconds; coarser units truncate toward zero.
pub const Precision = enum(i8) {
    minute = -1,
    second = 0,
    milli = 1,

    pub const default: Precision = .second;

    /// The -1|0|1 surface the CLI and C module expose, validated.
    pub fn fromInt(value: i64) ?Precision {
        return switch (value) {
            -1 => .minute,
            0 => .second,
            1 => .milli,
            else => null,
        };
    }

    fn msPerUnit(self: Precision) i64 {
        return switch (self) {
            .minute => 60000,
            .second => 1000,
            .milli => 1,
        };
    }

    fn horizon(self: Precision) u256 {
        return horizon_ms / @as(u64, @intCast(self.msPerUnit()));
    }
};

/// Enough for any single rendered component. The worst case is a 64-byte
/// random draw in base 2, which is 512 symbols.
pub const component_buf_len = 1024;

/// Sized for a format naming every component, plus literal text between them.
pub const out_buf_len = 4096;

/// Longest name %h, %u, or %f can carry. A fully-qualified name tops out at
/// 253 bytes.
pub const name_buf_len = 256;

/// Bytes any component hands to base conversion: the 64-byte cap on a random
/// draw is the largest.
const raw_buf_len = max_component_chars;

pub const Error = error{
    /// Base name or alias resolves to nothing. The converter's error text
    /// carries near-match suggestions.
    UnknownBase,
    /// The conversion library rejected the input or the request.
    BadInput,
    UnknownComponent,
    /// Format string ends on a bare '%'.
    BareFormatPercent,
    ClockBeforeEpoch,
    /// The rendered value needs more symbols than the fixed width allows,
    /// meaning the clock is past the padding horizon.
    WidthOverflow,
    BufferTooSmall,
    /// hash_chars or random_chars is outside 1..max_component_chars.
    OptionRange,
    /// The machine could not supply a component: no host name, no user, no
    /// interface with a hardware address, no random source.
    EnvUnavailable,
    /// The base has multi-byte digits, so a truncated component cannot be
    /// split in it. Padding still works; only %h %u %f %r are affected.
    MultiByteBase,
    /// The converter failed for a reason of its own; ask it for the text.
    ConvertFailed,
};

/// What the core needs from base conversion, and nothing more: one-shot
/// convert, plus the base metadata that fixed-width padding depends on.
pub const Converter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Renders value, written in from_base, into to_base.
        convert: *const fn (ctx: *anyopaque, value: []const u8, from_base: []const u8, to_base: []const u8, out: []u8) Error![]const u8,
        radix: *const fn (ctx: *anyopaque, base: []const u8) Error!u64,
        /// The base's first symbol - the padding digit. 32w starts at '2', so
        /// assuming '0' pads wrongly.
        zeroSymbol: *const fn (ctx: *anyopaque, base: []const u8, out: []u8) Error![]const u8,
        /// Symbols, not bytes: some bases have multi-byte digits.
        symbolCount: *const fn (ctx: *anyopaque, base: []const u8, digits: []const u8) Error!u64,
    };

    pub fn convert(self: Converter, value: []const u8, from_base: []const u8, to_base: []const u8, out: []u8) Error![]const u8 {
        return self.vtable.convert(self.ctx, value, from_base, to_base, out);
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

/// Everything the components read from the machine. Injectable for the same
/// reason the clock is: a generator nobody can pin down cannot be tested, and
/// the shared vectors are the whole verification strategy.
pub const Env = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Short host name, written into out.
        hostname: *const fn (ctx: *anyopaque, out: []u8) Error![]const u8,
        username: *const fn (ctx: *anyopaque, out: []u8) Error![]const u8,
        fqdn: *const fn (ctx: *anyopaque, out: []u8) Error![]const u8,
        mac: *const fn (ctx: *anyopaque) Error![mac_bits / 8]u8,
        /// Fills out entirely, or fails. %g and %r draw in format order.
        randomBytes: *const fn (ctx: *anyopaque, out: []u8) Error!void,
    };

    pub fn hostname(self: Env, out: []u8) Error![]const u8 {
        return self.vtable.hostname(self.ctx, out);
    }
    pub fn username(self: Env, out: []u8) Error![]const u8 {
        return self.vtable.username(self.ctx, out);
    }
    pub fn fqdn(self: Env, out: []u8) Error![]const u8 {
        return self.vtable.fqdn(self.ctx, out);
    }
    pub fn mac(self: Env) Error![mac_bits / 8]u8 {
        return self.vtable.mac(self.ctx);
    }
    pub fn randomBytes(self: Env, out: []u8) Error!void {
        return self.vtable.randomBytes(self.ctx, out);
    }
};

/// One identifier's worth of choices. clock_ms has no default on purpose -
/// nothing downstream reads the wall clock, so every caller states the instant.
pub const Options = struct {
    format: []const u8 = "%d",
    /// Empty means the default base.
    base: []const u8 = "",
    precision: Precision = Precision.default,
    clock_ms: i64,
    /// Emit host, user, and FQDN literally instead of hashed.
    no_hash: bool = false,
    hash_chars: u32 = default_hash_chars,
    random_chars: u32 = default_random_chars,
};

/// Smallest symbol count that holds every value up to largest. Lexicographic
/// compare reads left to right, so a short identifier and a long one cannot
/// sort chronologically - this fixed width is what makes the sort guarantee
/// hold, not the choice of alphabet.
pub fn widthForMax(radix: u64, largest: u256) u32 {
    var width: u32 = 1;
    var capacity: u256 = radix;
    while (capacity <= largest) {
        // radix is at most 2^64 and largest at most 2^128, so this tops out
        // around 2^192 - nowhere near overflowing.
        capacity *= radix;
        width += 1;
    }
    return width;
}

/// Width for the time component, whose largest value is the padding horizon.
pub fn widthFor(radix: u64, precision: Precision) u32 {
    return widthForMax(radix, precision.horizon());
}

/// Width for the components whose largest value is a bit count rather than a
/// date: the MAC's 48 and the UUID's 128.
fn widthForBits(radix: u64, bits: u8) u32 {
    return widthForMax(radix, (@as(u256, 1) << bits) - 1);
}

/// Renders one identifier into out and returns the filled slice.
pub fn generate(conv: Converter, env: Env, opts: Options, out: []u8) Error![]const u8 {
    const base = if (opts.base.len == 0) default_base else opts.base;
    if (opts.hash_chars < 1 or opts.hash_chars > max_component_chars) return Error.OptionRange;
    if (opts.random_chars < 1 or opts.random_chars > max_component_chars) return Error.OptionRange;

    var used: usize = 0;
    var i: usize = 0;
    while (i < opts.format.len) : (i += 1) {
        if (opts.format[i] != '%') {
            if (used == out.len) return Error.BufferTooSmall;
            out[used] = opts.format[i];
            used += 1;
            continue;
        }
        i += 1;
        if (i == opts.format.len) return Error.BareFormatPercent;

        const verb = opts.format[i];
        if (verb == '%') {
            if (used == out.len) return Error.BufferTooSmall;
            out[used] = '%';
            used += 1;
            continue;
        }
        const rendered = switch (verb) {
            'd' => try timeComponent(conv, base, opts.precision, opts.clock_ms, out[used..]),
            'h' => try nameComponent(conv, env, base, opts, .host, out[used..]),
            'u' => try nameComponent(conv, env, base, opts, .user, out[used..]),
            'f' => try nameComponent(conv, env, base, opts, .fqdn, out[used..]),
            'm' => try macComponent(conv, env, base, out[used..]),
            'g' => try uuidComponent(conv, env, base, out[used..]),
            'r' => try randomComponent(conv, env, base, opts.random_chars, out[used..]),
            else => return Error.UnknownComponent,
        };
        used += rendered.len;
    }
    return out[0..used];
}

/// The clock as the precision's unit count since the Unix epoch UTC,
/// converted and zero-padded to the fixed width for this base and precision.
fn timeComponent(conv: Converter, base: []const u8, precision: Precision, clock_ms: i64, out: []u8) Error![]const u8 {
    if (clock_ms < 0) return Error.ClockBeforeEpoch;

    var dec_buf: [20]u8 = undefined;
    const units = @divTrunc(clock_ms, precision.msPerUnit());
    const dec = std.fmt.bufPrint(&dec_buf, "{d}", .{units}) catch unreachable;

    var conv_buf: [component_buf_len]u8 = undefined;
    const converted = try conv.convert(dec, "10", base, &conv_buf);
    return padTo(conv, base, converted, widthFor(try conv.radix(base), precision), out);
}

const NameKind = enum { host, user, fqdn };

/// Host, user, or FQDN. Hashed by default: the name goes through SHA-256 and
/// only the rightmost few symbols survive, so what lands in the identifier is
/// a fingerprint rather than an identity. Opting out emits the name itself,
/// which is the one component that is not fixed width.
fn nameComponent(conv: Converter, env: Env, base: []const u8, opts: Options, kind: NameKind, out: []u8) Error![]const u8 {
    var name_buf: [name_buf_len]u8 = undefined;
    const name = switch (kind) {
        .host => try env.hostname(&name_buf),
        .user => try env.username(&name_buf),
        .fqdn => try env.fqdn(&name_buf),
    };
    if (name.len == 0) return Error.EnvUnavailable;

    if (opts.no_hash) {
        if (name.len > out.len) return Error.BufferTooSmall;
        @memcpy(out[0..name.len], name);
        return out[0..name.len];
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &digest, .{});
    return bytesComponent(conv, base, &digest, .{ .keep_right = opts.hash_chars }, out);
}

/// The hardware address as the 48-bit number it is.
fn macComponent(conv: Converter, env: Env, base: []const u8, out: []u8) Error![]const u8 {
    const address = try env.mac();
    const width = widthForBits(try conv.radix(base), mac_bits);
    return bytesComponent(conv, base, &address, .{ .width = width }, out);
}

/// A UUID v4 drawn from the random source, rendered as the 128-bit number it
/// is - not in the dashed text form, which would not sort and would be four
/// times as long.
fn uuidComponent(conv: Converter, env: Env, base: []const u8, out: []u8) Error![]const u8 {
    var uuid: [uuid_bits / 8]u8 = undefined;
    try env.randomBytes(&uuid);
    uuid[6] = (uuid[6] & 0x0f) | 0x40; // version 4
    uuid[8] = (uuid[8] & 0x3f) | 0x80; // variant 10
    const width = widthForBits(try conv.radix(base), uuid_bits);
    return bytesComponent(conv, base, &uuid, .{ .width = width }, out);
}

/// One byte drawn per requested symbol. That is more entropy than any base of
/// 256 symbols or fewer can spend, so the draw never has to know the radix.
fn randomComponent(conv: Converter, env: Env, base: []const u8, count: u32, out: []u8) Error![]const u8 {
    var drawn: [raw_buf_len]u8 = undefined;
    const slice = drawn[0..count];
    try env.randomBytes(slice);
    return bytesComponent(conv, base, slice, .{ .keep_right = count }, out);
}

/// How a rendered component is brought to its final width.
const Fit = union(enum) {
    /// Left-fill to a derived width; overflowing it is an error.
    width: u32,
    /// Keep the rightmost n symbols, left-filling if the value renders short.
    keep_right: u32,
};

/// The path every byte-valued component takes: base 16 in, because that is the
/// cheapest faithful way to hand bytes to the conversion library.
fn bytesComponent(conv: Converter, base: []const u8, raw: []const u8, fit: Fit, out: []u8) Error![]const u8 {
    var hex_buf: [raw_buf_len * 2]u8 = undefined;
    const hexed = hexUpper(raw, &hex_buf);

    var conv_buf: [component_buf_len]u8 = undefined;
    const converted = try conv.convert(hexed, "16", base, &conv_buf);

    return switch (fit) {
        .width => |width| padTo(conv, base, converted, width, out),
        .keep_right => |count| keepRight(conv, base, converted, count, out),
    };
}

fn hexUpper(raw: []const u8, out: []u8) []const u8 {
    const digits = "0123456789ABCDEF";
    for (raw, 0..) |byte, i| {
        out[i * 2] = digits[byte >> 4];
        out[i * 2 + 1] = digits[byte & 0x0f];
    }
    return out[0 .. raw.len * 2];
}

/// Left-fills converted to width with the base's zero digit.
fn padTo(conv: Converter, base: []const u8, converted: []const u8, width: u32, out: []u8) Error![]const u8 {
    const count = try conv.symbolCount(base, converted);
    if (count > width) return Error.WidthOverflow;

    var zero_buf: [8]u8 = undefined;
    const zero = try conv.zeroSymbol(base, &zero_buf);

    const fill: usize = @intCast(width - count);
    if (fill * zero.len + converted.len > out.len) return Error.BufferTooSmall;
    var used: usize = 0;
    for (0..fill) |_| {
        @memcpy(out[used .. used + zero.len], zero);
        used += zero.len;
    }
    @memcpy(out[used .. used + converted.len], converted);
    return out[0 .. used + converted.len];
}

/// Rightmost count symbols of a hash or a random draw. Truncation is what
/// makes a hash short enough to be useful.
///
/// It needs single-byte digits, because the conversion library offers no way
/// to slice a string at a symbol boundary and the two implementations have to
/// agree on the answer. Every base worth putting in an identifier qualifies;
/// the exotic multi-byte ones are refused rather than guessed at.
fn keepRight(conv: Converter, base: []const u8, converted: []const u8, count: u32, out: []u8) Error![]const u8 {
    const symbols = try conv.symbolCount(base, converted);

    var zero_buf: [8]u8 = undefined;
    const zero = try conv.zeroSymbol(base, &zero_buf);
    if (symbols != converted.len or zero.len != 1) return Error.MultiByteBase;

    if (count > out.len) return Error.BufferTooSmall;
    if (symbols >= count) {
        const tail = converted[converted.len - count ..];
        @memcpy(out[0..count], tail);
        return out[0..count];
    }
    const fill: usize = count - converted.len;
    @memset(out[0..fill], zero[0]);
    @memcpy(out[fill..count], converted);
    return out[0..count];
}

test "widthFor matches the design table" {
    try std.testing.expectEqual(@as(u32, 8), widthFor(16, .minute));
    try std.testing.expectEqual(@as(u32, 6), widthFor(32, .minute));
    try std.testing.expectEqual(@as(u32, 6), widthFor(36, .minute));
    try std.testing.expectEqual(@as(u32, 5), widthFor(62, .minute));
    try std.testing.expectEqual(@as(u32, 9), widthFor(16, .second));
    try std.testing.expectEqual(@as(u32, 7), widthFor(32, .second));
    try std.testing.expectEqual(@as(u32, 7), widthFor(36, .second));
    try std.testing.expectEqual(@as(u32, 6), widthFor(62, .second));
    try std.testing.expectEqual(@as(u32, 12), widthFor(16, .milli));
    try std.testing.expectEqual(@as(u32, 9), widthFor(32, .milli));
    try std.testing.expectEqual(@as(u32, 9), widthFor(36, .milli));
    try std.testing.expectEqual(@as(u32, 8), widthFor(62, .milli));
}

test "component widths come from their bit counts" {
    try std.testing.expectEqual(@as(u32, 12), widthForBits(16, mac_bits));
    try std.testing.expectEqual(@as(u32, 10), widthForBits(32, mac_bits));
    try std.testing.expectEqual(@as(u32, 10), widthForBits(36, mac_bits));
    try std.testing.expectEqual(@as(u32, 9), widthForBits(62, mac_bits));
    try std.testing.expectEqual(@as(u32, 32), widthForBits(16, uuid_bits));
    try std.testing.expectEqual(@as(u32, 26), widthForBits(32, uuid_bits));
    try std.testing.expectEqual(@as(u32, 25), widthForBits(36, uuid_bits));
    try std.testing.expectEqual(@as(u32, 22), widthForBits(62, uuid_bits));
}

test "precision surface round-trips -1|0|1 and rejects the rest" {
    try std.testing.expectEqual(Precision.minute, Precision.fromInt(-1).?);
    try std.testing.expectEqual(Precision.second, Precision.fromInt(0).?);
    try std.testing.expectEqual(Precision.milli, Precision.fromInt(1).?);
    try std.testing.expectEqual(@as(?Precision, null), Precision.fromInt(2));
    try std.testing.expectEqual(Precision.second, Precision.default);
}

test "hex is upper case, which is what base 16 expects" {
    var buf: [8]u8 = undefined;
    try std.testing.expectEqualStrings("00AB5EFF", hexUpper(&[_]u8{ 0x00, 0xab, 0x5e, 0xff }, &buf));
}
