// Copyright © 2026 Jim Collier
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! Identifier core: format parsing, components, assembly, fixed-width padding.
//! Deliberately takes no allocator - every intermediate fits a stack buffer and
//! the result goes into a caller-supplied one, so there is no pointer to dangle
//! and no free contract for the C module to get wrong. Base conversion is
//! reached through the Converter interface and the machine's own state through
//! the Env interface; this file touches neither the wasm host nor the operating
//! system directly, which is what lets the tests swap both out.

const std = @import("std");

pub const version = "1.0.0-alpha.1";

pub const default_base = "62";

/// The short list the help screen shows. --base still accepts anything the
/// conversion library knows; these are the ones that sort. The first four
/// transcribe by hand; the wide families trade that away for length, and only
/// one of the two names each radix carries is listed - tt up to 512, tz above
/// it, which is where tt stops existing.
pub const curated_bases = [_][]const u8{
    "16",     "32w",    "36",    "62",
    "64tt",   "128tt",  "256tt", "512tt",
    "1024tz", "2048tz",
};

/// Fingerprint strength a hashed component carries, and %r's. The default
/// widths are whatever these come to in the output base - which is what eight
/// and six base-62 symbols have always held, so base 62 is unchanged and every
/// other base is sized to match its strength rather than its symbol count. A
/// symbol is worth four bits in base 16 and eleven in 2048tz, so a fixed count
/// would mean wildly different strength per base.
pub const hash_bits: u16 = 47;
pub const random_bits: u16 = 35;

/// Upper bound on the width of any one component. The whole identifier is
/// bounded separately, by the output buffer the caller supplies.
pub const max_component_chars: u32 = 64;

/// Bit widths of the fixed-size components, which is what their output widths
/// are derived from.
const mac_bits: u16 = 48;
const uuid_bits: u16 = 128;
const digest_bits: u16 = std.crypto.hash.sha2.Sha256.digest_length * 8;

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

    fn horizon(self: Precision) u64 {
        return horizon_ms / @as(u64, @intCast(self.msPerUnit()));
    }
};

/// Enough for any single rendered component. The worst case is the widest
/// request in a narrow base whose digits are several bytes each, which comes
/// to well under half of this.
pub const component_buf_len = 1024;

/// Sized for a format naming every component, plus literal text between them.
pub const out_buf_len = 4096;

/// Longest name %h, %u, or %f can carry. A fully-qualified name tops out at
/// 253 bytes.
pub const name_buf_len = 256;

/// Bytes any component hands to base conversion. The largest is a random draw
/// filling max_component_chars symbols of the widest base the library carries,
/// whose symbols are 16 bits - two bytes each. A wider base than that would
/// need more, so randomComponent checks rather than trusting the arithmetic.
const raw_buf_len = max_component_chars * 2;

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
    /// The converter failed for a reason of its own; ask it for the text.
    ConvertFailed,
    /// The base renders raw bytes rather than text, so it cannot carry an
    /// identifier.
    BaseNotText,
    /// hash_chars is past what a SHA-256 fills in this base, so the extra
    /// symbols would all be left-fill. maxHashChars has the ceiling.
    HashTooWide,
};

/// What the core needs from base conversion, and nothing more: one-shot
/// convert, plus the base metadata that fixed-width padding depends on.
pub const Converter = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Renders value, written in from_base, into to_base, right-aligned to
        /// exactly width symbols: left-filled with the base's zero symbol when
        /// short, cut to the rightmost width when long.
        ///
        /// Convert and fit are one call because every component here wants
        /// both, and each one separately costs a round trip through the wasm
        /// boundary plus a region to marshal the base name into. The whole
        /// pad-or-truncate policy stays on the library side, so the two
        /// implementations cannot drift on the half of it they would otherwise
        /// each write themselves - and the zero symbol is not always '0' (32w
        /// starts at '2').
        convertFit: *const fn (ctx: *anyopaque, value: []const u8, from_base: []const u8, to_base: []const u8, width: u32, out: []u8) Error![]const u8,
        radix: *const fn (ctx: *anyopaque, base: []const u8) Error!u64,
        /// Symbols, not bytes: some bases have multi-byte digits.
        symbolCount: *const fn (ctx: *anyopaque, base: []const u8, digits: []const u8) Error!u64,
        /// The base's zero digit, which is also the padding symbol. Used to
        /// tell a text base from a raw-byte one.
        zeroSymbol: *const fn (ctx: *anyopaque, base: []const u8, out: []u8) Error![]const u8,
    };

    pub fn convertFit(self: Converter, value: []const u8, from_base: []const u8, to_base: []const u8, width: u32, out: []u8) Error![]const u8 {
        return self.vtable.convertFit(self.ctx, value, from_base, to_base, width, out);
    }
    pub fn radix(self: Converter, base: []const u8) Error!u64 {
        return self.vtable.radix(self.ctx, base);
    }
    pub fn symbolCount(self: Converter, base: []const u8, digits: []const u8) Error!u64 {
        return self.vtable.symbolCount(self.ctx, base, digits);
    }
    pub fn zeroSymbol(self: Converter, base: []const u8, out: []u8) Error![]const u8 {
        return self.vtable.zeroSymbol(self.ctx, base, out);
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
    /// Zero means the default width for the output base, which is derived
    /// rather than fixed - see hash_bits.
    hash_chars: u32 = 0,
    random_chars: u32 = 0,
};

/// Smallest symbol count that holds every value up to largest. Lexicographic
/// compare reads left to right, so a short identifier and a long one cannot
/// sort chronologically - this fixed width is what makes the sort guarantee
/// hold, not the choice of alphabet.
pub fn widthForMax(radix: u64, largest: u512) u32 {
    // Below 2 the ladder never terminates. Not reachable from a real base, but
    // this and the width helpers over it are public, and a hang is a worse
    // answer to a bad radix than a visibly useless one.
    if (radix < 2) return 0;

    var width: u32 = 1;
    var capacity: u512 = radix;
    while (capacity <= largest) {
        // radix is at most 2^64 and largest at most 2^256 (the digest), so
        // this tops out around 2^320 - well inside the type.
        capacity *= radix;
        width += 1;
    }
    return width;
}

/// Width for the time component, whose largest value is the padding horizon.
pub fn widthFor(radix: u64, precision: Precision) u32 {
    return widthForMax(radix, precision.horizon());
}

/// Width wherever the largest value is a bit count rather than a date: the
/// MAC's 48, the UUID's 128, the digest's 256, and the strength targets the
/// hashed and random defaults are sized from.
pub fn widthForBits(radix: u64, bits: u16) u32 {
    // Shifting a u512 wants a u9, and every caller is well inside it.
    return widthForMax(radix, (@as(u512, 1) << @intCast(bits)) - 1);
}

/// Width a hashed component takes in this base when the caller does not say.
pub fn defaultHashChars(radix: u64) u32 {
    return widthForBits(radix, hash_bits);
}

/// The same for %r.
pub fn defaultRandomChars(radix: u64) u32 {
    return widthForBits(radix, random_bits);
}

/// How many symbols of a SHA-256 this base can actually carry: 64 in base 16,
/// down to 24 in 2048tz. Past it the extra symbols are all left-fill, so the
/// identifier grows without the fingerprint getting any stronger - worth
/// refusing rather than emitting.
pub fn maxHashChars(radix: u64) u32 {
    return widthForBits(radix, digest_bits);
}

/// Renders one identifier into out and returns the filled slice.
pub fn generate(conv: Converter, env: Env, opts: Options, out: []u8) Error![]const u8 {
    const base = if (opts.base.len == 0) default_base else opts.base;
    try rejectRawByteBase(conv, base);

    // Widths settle here rather than in Options, because the defaults depend on
    // the base and so does a hashed component's ceiling. The radix is cached on
    // the host after the first ask.
    const radix = try conv.radix(base);
    const widths = Widths{
        .hash = if (opts.hash_chars == 0) defaultHashChars(radix) else opts.hash_chars,
        .random = if (opts.random_chars == 0) defaultRandomChars(radix) else opts.random_chars,
    };
    if (widths.hash > max_component_chars or widths.random > max_component_chars) return Error.OptionRange;
    if (!opts.no_hash and widths.hash > maxHashChars(radix)) return Error.HashTooWide;

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
            'd' => try timeComponent(conv, base, radix, opts.precision, opts.clock_ms, out[used..]),
            'h' => try nameComponent(conv, env, base, opts, widths.hash, .host, out[used..]),
            'u' => try nameComponent(conv, env, base, opts, widths.hash, .user, out[used..]),
            'f' => try nameComponent(conv, env, base, opts, widths.hash, .fqdn, out[used..]),
            'm' => try macComponent(conv, env, base, radix, out[used..]),
            'g' => try uuidComponent(conv, env, base, radix, out[used..]),
            'r' => try randomComponent(conv, env, base, radix, widths.random, out[used..]),
            else => return Error.UnknownComponent,
        };
        used += rendered.len;
    }
    return out[0..used];
}

/// The conversion library carries a base whose 256 digits are literal byte
/// values. It converts happily, which is the problem - an identifier full of
/// control characters and invalid UTF-8 is not an identifier, and that base
/// cannot hold a decimal timestamp at all, so a format mixing %d with anything
/// else would half work. The zero digit is the cheapest thing to test, and it
/// is the one piece of base metadata both implementations can read.
fn rejectRawByteBase(conv: Converter, base: []const u8) Error!void {
    var zero_buf: [16]u8 = undefined;
    const zero = try conv.zeroSymbol(base, &zero_buf);
    for (zero) |byte| {
        if (byte < 0x20 or byte == 0x7f) return Error.BaseNotText;
    }
}

/// The clock as the precision's unit count since the Unix epoch UTC,
/// converted and zero-padded to the fixed width for this base and precision.
fn timeComponent(conv: Converter, base: []const u8, radix: u64, precision: Precision, clock_ms: i64, out: []u8) Error![]const u8 {
    if (clock_ms < 0) return Error.ClockBeforeEpoch;

    const units = @divTrunc(clock_ms, precision.msPerUnit());
    // Fitting would truncate an over-wide value, which is right for a hash and
    // wrong for a timestamp: quietly dropping the high symbols would break the
    // sort rather than report it. The width was derived to hold exactly the
    // horizon, so comparing the units against it is the same test, and does not
    // cost a round trip to count symbols afterwards.
    if (units > precision.horizon()) return Error.WidthOverflow;

    var dec_buf: [20]u8 = undefined;
    // clock_ms is non-negative by the guard above, so units is at most 19
    // digits and the buffer cannot be too small.
    const dec = std.fmt.bufPrint(&dec_buf, "{d}", .{units}) catch unreachable;

    return conv.convertFit(dec, "10", base, widthFor(radix, precision), out);
}

const NameKind = enum { host, user, fqdn };

/// Host, user, or FQDN. Hashed by default: the name goes through SHA-256 and
/// only the rightmost few symbols survive, so the identifier carries a
/// fingerprint rather than an identity. Opting out emits the name itself,
/// which is the one component that is not fixed width.
fn nameComponent(conv: Converter, env: Env, base: []const u8, opts: Options, width: u32, kind: NameKind, out: []u8) Error![]const u8 {
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
    var digest: [digest_bits / 8]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &digest, .{});
    return bytesComponent(conv, base, &digest, width, out);
}

/// The hardware address as the 48-bit number it is.
fn macComponent(conv: Converter, env: Env, base: []const u8, radix: u64, out: []u8) Error![]const u8 {
    const address = try env.mac();
    return bytesComponent(conv, base, &address, widthForBits(radix, mac_bits), out);
}

/// A UUID v4 drawn from the random source, rendered as the 128-bit number it
/// is - not in the dashed text form, which would not sort and would be four
/// times as long.
fn uuidComponent(conv: Converter, env: Env, base: []const u8, radix: u64, out: []u8) Error![]const u8 {
    var uuid: [uuid_bits / 8]u8 = undefined;
    try env.randomBytes(&uuid);
    uuid[6] = (uuid[6] & 0x0f) | 0x40; // version 4
    uuid[8] = (uuid[8] & 0x3f) | 0x80; // variant 10
    return bytesComponent(conv, base, &uuid, widthForBits(radix, uuid_bits), out);
}

/// Enough entropy drawn to fill every symbol emitted.
fn randomComponent(conv: Converter, env: Env, base: []const u8, radix: u64, count: u32, out: []u8) Error![]const u8 {
    var drawn: [raw_buf_len]u8 = undefined;
    const wanted = randomBytesFor(radix, count);
    if (wanted > drawn.len) return Error.BadInput;
    const slice = drawn[0..wanted];
    try env.randomBytes(slice);
    return bytesComponent(conv, base, slice, count, out);
}

/// How many bytes fill count symbols of the given radix. One byte per symbol
/// covers anything up to 256 symbols and is what the narrow bases have always
/// drawn, so the floor keeps their output unchanged. Above 256 a symbol
/// carries more than eight bits, and one byte each would leave the leading
/// symbols permanently at the zero digit.
fn randomBytesFor(radix: u64, count: u32) u32 {
    const bits_per_symbol: u32 = 64 - @clz(radix - 1);
    return @max(count, (count * bits_per_symbol + 7) / 8);
}

/// The resolved widths one identifier renders at.
const Widths = struct { hash: u32, random: u32 };

/// The path every byte-valued component takes: base 16 in, because that is the
/// cheapest faithful way to hand bytes to the conversion library.
///
/// Fitting truncates when the value is wider than the width asked for, which is
/// what makes a 256-bit digest short enough to sit in an identifier. The
/// components whose width comes from their own bit count - the MAC and the
/// UUID - cannot reach that arm, since the width was derived to hold them.
fn bytesComponent(conv: Converter, base: []const u8, raw: []const u8, width: u32, out: []u8) Error![]const u8 {
    var hex_buf: [raw_buf_len * 2]u8 = undefined;
    return conv.convertFit(hexUpper(raw, &hex_buf), "16", base, width, out);
}

fn hexUpper(raw: []const u8, out: []u8) []const u8 {
    const digits = "0123456789ABCDEF";
    for (raw, 0..) |byte, i| {
        out[i * 2] = digits[byte >> 4];
        out[i * 2 + 1] = digits[byte & 0x0f];
    }
    return out[0 .. raw.len * 2];
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

// A symbol is worth four bits in base 16 and eleven in 2048tz, so a fixed
// symbol count would mean wildly different strength per base. The defaults come
// from the strength instead, and base 62 - where the targets were taken from -
// stays where it was.
test "default widths carry the same strength in every base" {
    const cases = [_]struct { radix: u64, hash: u32, random: u32, ceiling: u32 }{
        .{ .radix = 16, .hash = 12, .random = 9, .ceiling = 64 },
        .{ .radix = 32, .hash = 10, .random = 7, .ceiling = 52 },
        .{ .radix = 36, .hash = 10, .random = 7, .ceiling = 50 },
        .{ .radix = 62, .hash = 8, .random = 6, .ceiling = 43 },
        .{ .radix = 64, .hash = 8, .random = 6, .ceiling = 43 },
        .{ .radix = 128, .hash = 7, .random = 5, .ceiling = 37 },
        .{ .radix = 256, .hash = 6, .random = 5, .ceiling = 32 },
        .{ .radix = 512, .hash = 6, .random = 4, .ceiling = 29 },
        .{ .radix = 1024, .hash = 5, .random = 4, .ceiling = 26 },
        .{ .radix = 2048, .hash = 5, .random = 4, .ceiling = 24 },
    };
    for (cases) |case| {
        try std.testing.expectEqual(case.hash, defaultHashChars(case.radix));
        try std.testing.expectEqual(case.random, defaultRandomChars(case.radix));
        try std.testing.expectEqual(case.ceiling, maxHashChars(case.radix));
        // A derived default has to sit inside both bounds, or asking for
        // nothing in particular would fail.
        try std.testing.expect(case.hash <= case.ceiling);
        try std.testing.expect(case.hash <= max_component_chars);
    }
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
