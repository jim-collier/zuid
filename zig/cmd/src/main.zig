// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! The zuid command. A thin surface over the library: every invocation also
//! exercises the upstream wasm module through the embedded runtime, so using
//! this doubles as ongoing validation of that artifact.

const std = @import("std");
const builtin = @import("builtin");
const zuid = @import("zuid");

const build_options = @import("build_options");

/// The curated list, spelled out and wrapped at compile time so help cannot
/// drift from what the library actually offers.
const curated_list = blk: {
    // Where help descriptions start, and where they wrap.
    const desc_col = 30;
    const wrap_col = 80;
    const indent: [desc_col]u8 = @splat(' ');
    var joined: []const u8 = &indent;
    var line_len: usize = desc_col;
    for (zuid.core.curated_bases, 0..) |base, i| {
        const last = i + 1 == zuid.core.curated_bases.len;
        const word = base ++ (if (last) "" else ",");
        if (i > 0) {
            if (line_len + 1 + word.len > wrap_col) {
                joined = joined ++ "\n" ++ indent;
                line_len = desc_col;
            } else {
                joined = joined ++ " ";
                line_len += 1;
            }
        }
        joined = joined ++ word;
        line_len += word.len;
    }
    break :blk joined;
};

/// Minutes since 2000-01-01 UTC in lower-case Crockford base32, stamped from
/// the commit date by build.zig. Empty when nothing stamped it.
const build_number = blk: {
    const epoch_2000 = 946684800;
    const alphabet = "0123456789abcdefghjkmnpqrstvwxyz";
    if (build_options.build_epoch < epoch_2000) break :blk "";
    var minutes: u64 = @intCast(@divFloor(build_options.build_epoch - epoch_2000, 60));
    var digits: []const u8 = "";
    while (true) {
        digits = alphabet[minutes % 32 .. minutes % 32 + 1] ++ digits;
        minutes /= 32;
        if (minutes == 0) break;
    }
    break :blk digits;
};

const version_line = zuid.version ++ (if (build_number.len > 0) " (build " ++ build_number ++ ")" else "");

const about_text = "zuid " ++ version_line ++ "\n" ++
    \\Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ].
    \\Project: https://github.com/jim-collier/zuid
    \\License GPLv2+: GNU GPL version 2 or later, full text at:
    \\    https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
    \\The Go module and the C library are Apache-2.0.
    \\There is no warranty, to the extent permitted by law.
    \\
    \\Short, sortable, privacy-preserving unique identifiers. Components are
    \\zero-padded to fixed widths, so identifiers sort by time as plain text.
    \\
;

const donate_text =
    \\zuid is free software, and stays that way.
    \\
    \\If it saves you time and you want to give something back:
    \\    https://github.com/sponsors/jim-collier
    \\    https://ko-fi.com/jimcollier
    \\
    \\A star on the project, a clear bug report, or a mention to someone who needs
    \\it are worth just as much.
    \\
;

const help_head =
    \\Generates short, sortable, privacy-preserving unique identifiers.
    \\
    \\Syntax: zuid [options]
    \\
    \\A value attaches to its flag with '=' or follows it as the next argument,
    \\so -b=32c, -b 32c, --base=32c, and --base 32c are all the same thing.
    \\
    \\Options:
    \\    -b, --base <name>         Output base (default 62). Curated set:
    \\
;

const help_tail =
    \\
    \\                              Any base the conversion library knows is also
    \\                              accepted, including ones that do not sort.
    \\    -f, --format <fmt>        Format string (default "%d"). See below.
    \\    -p, --precision <-1|0|1>  Time precision: -1 minute, 0 second (default),
    \\                              1 millisecond.
    \\    -n, --count <n>           How many to print, one per line (default 1,
    \\                              most 1000000). One run reads the clock once,
    \\                              so a format without %r repeats itself.
    \\        --no-hash             Emit the host, user, and FQDN names literally
    \\                              instead of hashing them.
    \\        --rand-chars <count>  How many random symbols %r emits. The default
    \\                              depends on the base: 9 in base 16, 6 in 62, 4
    \\                              in 2048tz.
    \\        --salt <text>         Secret hashed ahead of the host, user, and
    \\                              FQDN names, so a name cannot be confirmed by
    \\                              hashing guesses. Machines being compared need
    \\                              the same one, and it shows in the process
    \\                              list.
    \\    -h, --help                This.
    \\    -v, --version             Version and build number.
    \\        --about               Version, copyright, and license.
    \\        --donate              How to support the project.
    \\
    \\Format components:
    \\    %d  Time, as the count of units since the Unix epoch, UTC.
    \\    %h  Short host name, hashed by default.
    \\    %u  User name, hashed by default.
    \\    %f  Fully-qualified host and domain name, hashed by default.
    \\    %m  Hardware address of the lowest-numbered non-loopback interface.
    \\    %g  A random UUID v4, as a plain number in the output base. No dashes.
    \\    %r  Random symbols from a cryptographic source.
    \\    %%  A literal '%'. Anything else in the format goes out as itself.
    \\
    \\Every component but an unhashed %h, %u, or %f is a fixed number of symbols
    \\wide, zero-padded, so identifiers sort chronologically as plain text (byte
    \\order; use LC_COLLATE=C) and can be split by offset. Different bases or
    \\precisions have different widths and do not sort against each other - pick
    \\one combination per use-case.
    \\
;

// Help, about, and donate stand clear of the prompt with a blank line either side.
// --version stays bare, since scripts capture it.
const help_text = "\nzuid " ++ version_line ++ "\n\n" ++ help_head ++ curated_list ++ help_tail ++ "\n";

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_fw: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_fw: std.Io.File.Writer = .init(.stderr(), io, &stderr_buf);
    const stderr = &stderr_fw.interface;

    const args = try init.minimal.args.toSlice(arena);

    var opts = zuid.core.Options{ .clock_ms = 0 };
    var count: usize = 1;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // A value may ride along on the flag ("-b=32c") or follow it as the
        // next argument. Only split a leading-dash argument, so a format
        // string containing '=' passes through untouched.
        var name: []const u8 = arg;
        var attached: ?[]const u8 = null;
        if (arg.len > 1 and arg[0] == '-') {
            if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                name = arg[0..eq];
                attached = arg[eq + 1 ..];
            }
        }
        var vals: Values = .{ .args = args, .at = &i, .attached = attached, .stderr = stderr };

        if (std.mem.eql(u8, name, "-h") or std.mem.eql(u8, name, "--help")) {
            vals.rejectAttached(name);
            stdout.writeAll(help_text) catch stdoutFailed(&stdout_fw, stderr);
            stdout.flush() catch stdoutFailed(&stdout_fw, stderr);
            return;
        } else if (std.mem.eql(u8, name, "-v") or std.mem.eql(u8, name, "--version")) {
            vals.rejectAttached(name);
            stdout.writeAll(version_line ++ "\n") catch stdoutFailed(&stdout_fw, stderr);
            stdout.flush() catch stdoutFailed(&stdout_fw, stderr);
            return;
        } else if (std.mem.eql(u8, name, "--about")) {
            vals.rejectAttached(name);
            stdout.writeAll("\n" ++ about_text ++ "\n") catch stdoutFailed(&stdout_fw, stderr);
            stdout.flush() catch stdoutFailed(&stdout_fw, stderr);
            return;
        } else if (std.mem.eql(u8, name, "--donate")) {
            vals.rejectAttached(name);
            stdout.writeAll("\n" ++ donate_text ++ "\n") catch stdoutFailed(&stdout_fw, stderr);
            stdout.flush() catch stdoutFailed(&stdout_fw, stderr);
            return;
        } else if (std.mem.eql(u8, name, "-b") or std.mem.eql(u8, name, "--base")) {
            opts.base = vals.take(name, "a base name");
            // The library trims, so a blank name reaches it as empty and comes
            // back in its words rather than these. An absent value is still
            // the default, the same as an empty format.
            if (opts.base.len > 0 and std.mem.trim(u8, opts.base, " \t\r\n").len == 0) {
                return die(stderr, "Base name '{s}' is blank. Want a base name; --help lists the curated set.", .{opts.base});
            }
        } else if (std.mem.eql(u8, name, "-f") or std.mem.eql(u8, name, "--format")) {
            opts.format = vals.take(name, "a format string");
        } else if (std.mem.eql(u8, name, "-p") or std.mem.eql(u8, name, "--precision")) {
            const raw = vals.take(name, "-1, 0, or 1");
            const parsed = std.fmt.parseInt(i64, raw, 10) catch {
                return die(stderr, "Precision '{s}' is not a number. Want -1 (minute), 0 (second), or 1 (millisecond).", .{raw});
            };
            opts.precision = zuid.core.Precision.fromInt(parsed) orelse {
                return die(stderr, "Precision {d} is out of range. Want -1 (minute), 0 (second), or 1 (millisecond).", .{parsed});
            };
        } else if (std.mem.eql(u8, name, "-n") or std.mem.eql(u8, name, "--count")) {
            const raw = vals.take(name, "a count");
            const parsed = std.fmt.parseInt(i64, raw, 10) catch {
                return die(stderr, "Count '{s}' is not a number. Want 1 to {d}.", .{ raw, max_count });
            };
            if (parsed < 1 or parsed > max_count) {
                return die(stderr, "Count {d} is out of range. Want 1 to {d}.", .{ parsed, max_count });
            }
            count = @intCast(parsed);
        } else if (std.mem.eql(u8, name, "--no-hash")) {
            vals.rejectAttached(name);
            opts.no_hash = true;
        } else if (std.mem.eql(u8, name, "--rand-chars")) {
            opts.random_chars = charCount(stderr, vals.take(name, "a symbol count"), name);
        } else if (std.mem.eql(u8, name, "--salt")) {
            opts.salt = vals.take(name, "a salt");
        } else {
            return die(stderr, "Argument invalid or not expected: '{s}'. Try --help.", .{arg});
        }
    }
    // An empty format means %d, the same as the Go module's zero Request.Format
    // and the C module's NULL or empty format. Passed straight through it
    // rendered an empty identifier and exited 0, so a script running
    // 'zuid -f "$FMT"' with the variable unset got nothing and no error.
    if (opts.format.len == 0) opts.format = "%d";

    opts.clock_ms = zuid.clock.nowMs() orelse return die(stderr, "The system clock could not be read.", .{});

    const module_cache = ModuleCache.find(arena, init.environ_map);
    const cached = if (module_cache) |mc| mc.load(io, arena) else null;
    var wasm_host = zuid.host.Host.initCached(.auto, cached) catch |err| {
        return die(stderr, "The embedded wasm runtime failed to start: {t}.", .{err});
    };
    defer wasm_host.deinit();
    var live: zuid.env.Live = .{};

    var renderer = Renderer.init(arena) catch return die(stderr, "Out of memory.", .{});

    // Hashes rather than the identifiers themselves, so what this costs does
    // not depend on how long a format renders. Two hashes colliding would say
    // one line repeats when it does not, at odds no run will ever meet. Only
    // tracked past one identifier, so the ordinary run allocates nothing here.
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    var repeats: usize = 0;

    var n: usize = 0;
    while (n < count) : (n += 1) {
        const id = renderer.render(wasm_host.converter(), live.env(), opts) catch |err| {
            dieGenerating(stderr, err, wasm_host.lastError(), opts);
        };

        if (count > 1) {
            const digest = std.hash.Wyhash.hash(0, id);
            const slot = seen.getOrPut(arena, digest) catch return die(stderr, "Out of memory.", .{});
            if (slot.found_existing) repeats += 1;
        }

        stdout.print("{s}\n", .{id}) catch stdoutFailed(&stdout_fw, stderr);
    }
    stdout.flush() catch stdoutFailed(&stdout_fw, stderr);

    // After the identifiers, so a terminal shows the output first. The format
    // means what it says - nothing is appended to make a repeat unique.
    if (repeats > 0) {
        stderr.print(
            "zuid: warning: {d} of {d} identifiers repeat an earlier line. Want unique output: add %r to the format.\n",
            .{ repeats, count },
        ) catch {};
        stderr.flush() catch {};
    }

    // Last, so the output is not kept waiting on a disk write.
    if (module_cache) |mc| {
        if (wasm_host.compiled_fresh) mc.save(io, &wasm_host);
    }
}

/// The compiled wasm module, kept between runs. Compiling it is most of what a
/// run costs, and Wasmtime spreads that over every core. Nothing here is fatal:
/// any failure just means the next run compiles again.
const ModuleCache = struct {
    dir: []const u8,
    name: []const u8,
    file: []const u8,

    const prefix = "module-";
    const suffix = ".cwasm";
    // Far past the 8 MB the module takes, so only a wrong file trips it.
    const max_bytes = 64 << 20;

    /// The module bytes, or null when there are none or they are not what was
    /// saved. The file ends in a hash of the rest; a damaged module would
    /// otherwise run as damaged machine code.
    fn load(self: ModuleCache, io: std.Io, arena: std.mem.Allocator) ?[]const u8 {
        const raw = std.Io.Dir.cwd().readFileAlloc(io, self.file, arena, .limited(max_bytes)) catch return null;
        if (raw.len < 8) return null;
        const body = raw[0 .. raw.len - 8];
        const want = std.mem.readInt(u64, raw[raw.len - 8 ..][0..8], .little);
        if (std.hash.Wyhash.hash(0, body) != want) return null;
        return body;
    }

    fn find(arena: std.mem.Allocator, environ: *const std.process.Environ.Map) ?ModuleCache {
        // Root would be loading native code from wherever HOME points, which
        // under sudo can be a directory some other user writes.
        if (builtin.os.tag != .windows and std.c.geteuid() == 0) return null;
        const dir = cacheRoot(arena, environ) orelse return null;
        const name = std.fmt.allocPrint(arena, prefix ++ "{x:0>16}" ++ suffix, .{zuid.host.Host.moduleId(.auto)}) catch return null;
        const file = std.fs.path.join(arena, &.{ dir, name }) catch return null;
        return .{ .dir = dir, .name = name, .file = file };
    }

    /// The usual per-user cache directory for each OS, plus "zuid".
    fn cacheRoot(arena: std.mem.Allocator, environ: *const std.process.Environ.Map) ?[]const u8 {
        const tail: []const u8, const base: []const u8 = switch (builtin.os.tag) {
            .windows => .{ "zuid", environ.get("LOCALAPPDATA") orelse return null },
            .macos => .{ "Library/Caches/zuid", environ.get("HOME") orelse return null },
            else => if (environ.get("XDG_CACHE_HOME")) |xdg|
                if (std.fs.path.isAbsolute(xdg)) .{ "zuid", xdg } else .{ ".cache/zuid", environ.get("HOME") orelse return null }
            else
                .{ ".cache/zuid", environ.get("HOME") orelse return null },
        };
        if (!std.fs.path.isAbsolute(base)) return null;
        return std.fs.path.join(arena, &.{ base, tail }) catch null;
    }

    fn save(self: ModuleCache, io: std.Io, wasm_host: *zuid.host.Host) void {
        var compiled = wasm_host.serialize() orelse return;
        defer compiled.deinit();
        var dir = std.Io.Dir.cwd().createDirPathOpen(io, self.dir, .{ .open_options = .{ .iterate = true } }) catch return;
        defer dir.close(io);
        var atomic = dir.createFileAtomic(io, self.name, .{ .replace = true }) catch return;
        defer atomic.deinit(io);
        var sum: [8]u8 = undefined;
        std.mem.writeInt(u64, &sum, std.hash.Wyhash.hash(0, compiled.bytes()), .little);
        atomic.file.writeStreamingAll(io, compiled.bytes()) catch return;
        atomic.file.writeStreamingAll(io, &sum) catch return;
        atomic.replace(io) catch return;

        // Whatever older builds left behind. Each is several megabytes, and no
        // build but the one that wrote it will ever load it.
        var it = dir.iterate();
        while (it.next(io) catch return) |entry| {
            if (entry.kind != .file or std.mem.eql(u8, entry.name, self.name)) continue;
            if (!std.mem.startsWith(u8, entry.name, prefix) or !std.mem.endsWith(u8, entry.name, suffix)) continue;
            dir.deleteFile(io, entry.name) catch {};
        }
    }
};

/// Turns a generation failure into the one-line message the style guide asks
/// for. The wasm runtime's own words win where it had any, since those are
/// internal rather than about something that was typed.
fn dieGenerating(stderr: *std.Io.Writer, err: anyerror, detail: []const u8, opts: zuid.core.Options) noreturn {
    if (err == error.UnknownBase) {
        const hint = nearestBase(detail);
        if (hint.len > 0) {
            die(stderr, "Unknown base '{s}'. Did you mean '{s}'?", .{ opts.base, hint });
        }
        die(stderr, "Unknown base '{s}'. Want one the conversion library knows; --help lists the curated set.", .{opts.base});
    }
    if (detail.len > 0) {
        die(stderr, "{s}", .{detail});
    }
    switch (err) {
        error.UnknownComponent => die(stderr, "Unknown format component '%{s}'. Known: %d %h %u %f %m %g %r, and %% for a literal.", .{unknownVerb(opts.format)}),
        error.BareFormatPercent => die(stderr, "The format string ends on a bare '%'.", .{}),
        error.ClockBeforeEpoch => die(stderr, "The clock predates the Unix epoch.", .{}),
        error.BaseNotText => die(stderr, "That base renders raw bytes or control characters rather than text, so it cannot carry an identifier.", .{}),
        error.EnvUnavailable => die(stderr, "This machine could not supply that component - no name, hardware address, or random source.", .{}),
        error.OptionRange => die(stderr, "A symbol count is out of range. Want 1 to {d}.", .{zuid.core.max_component_chars}),
        error.SaltTooLong => die(stderr, "The salt is {d} bytes. Want at most {d}.", .{ opts.salt.len, zuid.core.max_salt_bytes }),
        error.BufferTooSmall => die(stderr, "That format renders more than {d} bytes, which is past what this command will print.", .{max_out_len}),
        else => die(stderr, "Generation failed: {t}.", .{err}),
    }
}

/// A reader that quit early - 'zuid -n 1000000 | head' - is how a run ends, not
/// something to report. Anything else that stops stdout is worth a message.
fn stdoutFailed(fw: *std.Io.File.Writer, stderr: *std.Io.Writer) noreturn {
    if (fw.err) |err| {
        if (err == error.BrokenPipe) std.process.exit(0);
        die(stderr, "Writing to standard output failed: {t}.", .{err});
    }
    die(stderr, "Writing to standard output failed.", .{});
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

/// Where the growing below gives up. Only here so a runaway format ends in a
/// message instead of eating memory; an identifier anyone wants is far shorter.
const max_out_len = 1 << 20;

/// Ceiling on --count. It catches a mistyped count before the run rather than
/// after it: a batch costs around 30 microseconds an identifier, so the ceiling
/// is already half a minute of work. Raise it if that cost comes down again.
const max_count = 1_000_000;

/// Renders into a buffer that grows until the identifier fits. A fixed one
/// refused anything past it, whether the format repeated a component or just
/// carried a long literal, and the module renders into whatever it is handed.
///
/// The buffer is kept between identifiers, so a large --count does not leave a
/// buffer per line behind in the arena. That makes each returned slice good
/// only until the next call - anything kept has to be copied.
const Renderer = struct {
    arena: std.mem.Allocator,
    buf: []u8,

    fn init(arena: std.mem.Allocator) !Renderer {
        return .{ .arena = arena, .buf = try arena.alloc(u8, zuid.core.out_buf_len) };
    }

    fn render(
        self: *Renderer,
        conv: zuid.core.Converter,
        live_env: zuid.core.Env,
        opts: zuid.core.Options,
    ) ![]const u8 {
        while (true) {
            if (zuid.core.generate(conv, live_env, opts, self.buf)) |id| return id else |err| {
                if (err != error.BufferTooSmall or self.buf.len >= max_out_len) return err;
                self.buf = try self.arena.alloc(u8, self.buf.len * 2);
            }
        }
    }
};

/// Resolves a flag's value from either spelling - attached with '=', or the
/// argument after it.
const Values = struct {
    args: []const [:0]const u8,
    at: *usize,
    attached: ?[]const u8,
    stderr: *std.Io.Writer,

    fn take(self: @This(), flag: []const u8, what: []const u8) []const u8 {
        if (self.attached) |v| return v;
        self.at.* += 1;
        if (self.at.* == self.args.len) die(self.stderr, "Expecting {s} after {s}.", .{ what, flag });
        return self.args[self.at.*];
    }

    fn rejectAttached(self: @This(), flag: []const u8) void {
        if (self.attached != null) die(self.stderr, "{s} takes no value.", .{flag});
    }
};

fn charCount(stderr: *std.Io.Writer, raw: []const u8, flag: []const u8) u32 {
    const parsed = std.fmt.parseInt(u32, raw, 10) catch {
        return die(stderr, "'{s}' is not a symbol count. Want 1 to {d}.", .{ raw, zuid.core.max_component_chars });
    };
    if (parsed < 1 or parsed > zuid.core.max_component_chars) {
        return die(stderr, "{d} is out of range for {s}. Want 1 to {d}.", .{ parsed, flag, zuid.core.max_component_chars });
    }
    return parsed;
}

fn die(stderr: *std.Io.Writer, comptime fmt: []const u8, args: anytype) noreturn {
    stderr.print("zuid: " ++ fmt ++ "\n", args) catch {};
    stderr.flush() catch {};
    std.process.exit(1);
}
