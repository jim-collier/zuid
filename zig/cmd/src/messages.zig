// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! What the command says when generating fails. Kept apart from main.zig, and
//! needing nothing but std, so the library's tests can hold every one of these
//! to testdata/errors.tsv - including the ones no flag can reach.

const std = @import("std");

/// What the message may quote back, and the limits it states.
pub const Given = struct {
    base: []const u8,
    format: []const u8,
    salt_len: usize,
    max_chars: u32,
    max_salt: usize,
    max_out: usize,
};

/// The one sentence the style guide asks for, without the 'zuid: ' or the
/// newline. The wasm runtime's own words win where it had any, since those are
/// internal rather than about something that was typed.
pub fn generating(w: *std.Io.Writer, err: anyerror, detail: []const u8, given: Given) std.Io.Writer.Error!void {
    if (err == error.UnknownBase) {
        const hint = nearestBase(detail);
        if (hint.len > 0) {
            return w.print("Unknown base '{s}'. Did you mean '{s}'?", .{ given.base, hint });
        }
        return w.print("Unknown base '{s}'. Want one the conversion library knows; --help lists the curated set.", .{given.base});
    }
    if (detail.len > 0) return w.writeAll(detail);
    switch (err) {
        error.UnknownComponent => try w.print("Unknown format component '%{s}'. Known: %d %h %u %f %m %g %r, and %% for a literal.", .{unknownVerb(given.format)}),
        error.BareFormatPercent => try w.writeAll("The format string ends on a bare '%'."),
        error.ClockBeforeEpoch => try w.writeAll("The clock predates the Unix epoch."),
        error.WidthOverflow => try w.writeAll("The clock is past the padding horizon, so the timestamp no longer fits its fixed width."),
        error.BaseNotText => try w.writeAll("That base renders raw bytes or control characters rather than text, so it cannot carry an identifier."),
        error.EnvUnavailable => try w.writeAll("This machine could not supply that component - no name, hardware address, or random source."),
        error.OptionRange => try w.print("A symbol count is out of range. Want 1 to {d}.", .{given.max_chars}),
        error.SaltTooLong => try w.print("The salt is {d} bytes. Want at most {d}.", .{ given.salt_len, given.max_salt }),
        error.BufferTooSmall => try w.print("That format renders more than {d} bytes, which is past what this command will print.", .{given.max_out}),
        error.RuntimeFailed => try w.writeAll("The embedded wasm runtime or its module failed."),
        else => try w.print("Generation failed: {t}.", .{err}),
    }
}

/// The near-match the conversion library suggested, or empty when it had none.
/// Its message is `unknown base "x"; did you mean "y"?`, which reads in its
/// style rather than this command's, so only the suggestion is kept.
fn nearestBase(detail: []const u8) []const u8 {
    const lead = "did you mean \"";
    const at = std.mem.indexOf(u8, detail, lead) orelse return "";
    const rest = detail[at + lead.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return "";
    return rest[0..end];
}

/// The first verb the core would not know. It reports which error happened,
/// not which character caused it, so the command walks the format the same way
/// the core's loop does. A multi-byte verb prints whole rather than as the
/// Latin-1 reading of its first byte.
fn unknownVerb(format: []const u8) []const u8 {
    var i: usize = 0;
    while (i + 1 < format.len) : (i += 1) {
        if (format[i] != '%') continue;
        i += 1;
        switch (format[i]) {
            '%', 'd', 'h', 'u', 'f', 'm', 'g', 'r' => {},
            else => {
                const len = std.unicode.utf8ByteSequenceLength(format[i]) catch 1;
                return format[i..@min(i + len, format.len)];
            },
        }
    }
    return "";
}
