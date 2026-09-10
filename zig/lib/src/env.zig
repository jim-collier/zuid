// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! The live side of core's Env interface: the one place the machine's own
//! state is read. Everything goes through libc, which the library links for
//! Wasmtime anyway, and which keeps this off 0.16's Io-bound file API - the C
//! module has no Io instance to hand it.
//!
//! No allocator here either. Names go into caller buffers and the MAC comes
//! back by value.
//!
//! Each source is read once and kept. None of them changes in a way that
//! should change an identifier mid-run, and the reads are not cheap: walking
//! every interface for a hardware address costs far more than the base
//! conversion it feeds, and resolving a qualified name can block on DNS.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("pwd.h");
    @cInclude("netdb.h");
    @cInclude("ifaddrs.h");
    @cInclude("net/if.h");
    if (builtin.os.tag == .linux) {
        @cInclude("netpacket/packet.h");
    }
});

/// One remembered name. Reading it again would cost a syscall or a lookup for
/// a value that cannot usefully change.
const NameCache = struct {
    buf: [core.name_buf_len]u8 = undefined,
    len: ?usize = null,

    fn get(self: *const NameCache) ?[]const u8 {
        const len = self.len orelse return null;
        return self.buf[0..len];
    }

    fn put(self: *NameCache, name: []const u8) void {
        if (name.len > self.buf.len) return;
        @memcpy(self.buf[0..name.len], name);
        self.len = name.len;
    }
};

/// A live Env. Holds what it has already read, so one instance per context is
/// the intended shape - and, like the C context it sits in, it is not safe to
/// share across threads.
pub const Live = struct {
    host: NameCache = .{},
    user: NameCache = .{},
    qualified: NameCache = .{},
    hardware: ?[6]u8 = null,

    pub fn env(self: *Live) core.Env {
        return .{ .ctx = self, .vtable = &vtable };
    }

    const vtable = core.Env.VTable{
        .hostname = vtHostname,
        .username = vtUsername,
        .fqdn = vtFqdn,
        .mac = vtMac,
        .randomBytes = vtRandomBytes,
    };
};

/// %h is the short name, so a qualified one is cut at the first dot.
fn vtHostname(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
    const self: *Live = @ptrCast(@alignCast(ctx));
    if (self.host.get()) |cached| return copyOut(cached, out);

    const full = try readHostname(out);
    const cut = std.mem.indexOfScalar(u8, full, '.') orelse full.len;
    const short = full[0..cut];
    self.host.put(short);
    return short;
}

fn vtUsername(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
    const self: *Live = @ptrCast(@alignCast(ctx));
    if (self.user.get()) |cached| return copyOut(cached, out);
    const name = try readUsername(out);
    self.user.put(name);
    return name;
}

fn readUsername(out: []u8) core.Error![]const u8 {
    if (c.getpwuid(c.getuid())) |entry| {
        if (entry.*.pw_name) |name| {
            return copyOut(std.mem.span(name), out);
        }
    }
    // No passwd entry is normal in a container; the environment usually knows.
    for ([_][*:0]const u8{ "USER", "LOGNAME", "USERNAME" }) |key| {
        if (c.getenv(key)) |value| {
            const name = std.mem.span(value);
            if (name.len > 0) return copyOut(name, out);
        }
    }
    return core.Error.EnvUnavailable;
}

/// Best-effort. A host with no domain has no qualified name to find, and
/// falling back to the short name beats failing the identifier.
fn vtFqdn(ctx: *anyopaque, out: []u8) core.Error![]const u8 {
    const self: *Live = @ptrCast(@alignCast(ctx));
    if (self.qualified.get()) |cached| return copyOut(cached, out);
    const found = try readFqdn(out);
    self.qualified.put(found);
    return found;
}

fn readFqdn(out: []u8) core.Error![]const u8 {
    const name = try readHostname(out);
    if (std.mem.indexOfScalar(u8, name, '.') != null) return name;

    var name_z: [core.name_buf_len]u8 = undefined;
    if (name.len >= name_z.len) return name;
    @memcpy(name_z[0..name.len], name);
    name_z[name.len] = 0;

    var hints: c.struct_addrinfo = std.mem.zeroes(c.struct_addrinfo);
    hints.ai_flags = c.AI_CANONNAME;
    var results: ?*c.struct_addrinfo = null;
    if (c.getaddrinfo(&name_z, null, &hints, &results) != 0) return name;
    defer c.freeaddrinfo(results);
    const found = results orelse return name;
    const canonical = found.*.ai_canonname orelse return name;

    const qualified = std.mem.span(canonical);
    if (std.mem.indexOfScalar(u8, qualified, '.') == null) return name;
    return copyOut(qualified, out);
}

/// The lowest-numbered non-loopback interface carrying an EUI-48. The
/// predecessor picked the interface holding the default route, which needs the
/// routing table on three platforms; interface order is stable enough for a
/// value whose only job is to differ between hosts.
///
/// Linux only so far. macOS and the BSDs report a hardware address as AF_LINK
/// rather than AF_PACKET, and that path is not written yet.
fn vtMac(ctx: *anyopaque) core.Error![6]u8 {
    const self: *Live = @ptrCast(@alignCast(ctx));
    if (self.hardware) |cached| return cached;
    const address = try readMac();
    self.hardware = address;
    return address;
}

fn readMac() core.Error![6]u8 {
    if (builtin.os.tag != .linux) return core.Error.EnvUnavailable;

    var list: ?*c.struct_ifaddrs = null;
    if (c.getifaddrs(&list) != 0) return core.Error.EnvUnavailable;
    defer c.freeifaddrs(list);

    var found: ?[6]u8 = null;
    var lowest: c_int = std.math.maxInt(c_int);
    var walk = list;
    while (walk) |entry| : (walk = entry.*.ifa_next) {
        if (entry.*.ifa_flags & c.IFF_LOOPBACK != 0) continue;
        const addr = entry.*.ifa_addr orelse continue;
        if (addr.*.sa_family != c.AF_PACKET) continue;

        const link: *const c.struct_sockaddr_ll = @ptrCast(@alignCast(addr));
        if (link.*.sll_halen != 6) continue;
        if (link.*.sll_ifindex >= lowest) continue;

        lowest = link.*.sll_ifindex;
        found = link.*.sll_addr[0..6].*;
    }
    return found orelse core.Error.EnvUnavailable;
}

/// 0.16 moved randomness onto Io, the same way it moved the clocks, so this
/// goes to libc for the same reason clock.zig does. getentropy caps a call at
/// 256 bytes, comfortably above the largest draw the core will ask for.
fn vtRandomBytes(_: *anyopaque, out: []u8) core.Error!void {
    if (out.len > 256) return core.Error.BufferTooSmall;
    if (c.getentropy(out.ptr, out.len) != 0) return core.Error.EnvUnavailable;
}

/// Through std rather than libc, unlike its neighbors: glibc's fortified
/// gethostname does not survive translate-c once optimization turns
/// _FORTIFY_SOURCE on, and it fails only in release builds.
fn readHostname(out: []u8) core.Error![]const u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&buf) catch return core.Error.EnvUnavailable;
    if (name.len == 0) return core.Error.EnvUnavailable;
    return copyOut(name, out);
}

fn copyOut(text: []const u8, out: []u8) core.Error![]const u8 {
    if (text.len > out.len) return core.Error.BufferTooSmall;
    @memcpy(out[0..text.len], text);
    return out[0..text.len];
}
