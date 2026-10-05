// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the Apache License, Version 2.0. Full text in zig/lib/LICENSE.txt, or:
//     https://spdx.org/licenses/Apache-2.0.html
// SPDX-License-Identifier: Apache-2.0

//! env.zig's reads on Windows, where libc has no user database, no
//! getifaddrs and no getentropy. Each one asks the Win32 API instead. %m
//! walks the adapter list Go's net.Interfaces walks, and %h comes to the name
//! Go's os.Hostname reads, so the two sides agree on those.

const std = @import("std");
const core = @import("core.zig");
const env = @import("env.zig");

// lib/c/env.h, translated by build.zig.
const c = @import("c_env");

/// The logon name, without the domain. Go's user.Current gives DOMAIN\name.
pub fn username(out: []u8) core.Error![]const u8 {
    var wide: [c.UNLEN + 1]u16 = undefined;
    var len: c.DWORD = wide.len;
    if (c.GetUserNameW(&wide, &len) == 0 or len < 2) return core.Error.EnvUnavailable;
    // The count includes the terminating NUL.
    return toUtf8(wide[0 .. len - 1], out);
}

/// The DNS name with its primary suffix, if the machine has one. %h cuts it at
/// the first dot, which leaves the DNS host name Go's os.Hostname reads.
pub fn hostname(out: []u8) core.Error![]const u8 {
    var wide: [256]u16 = undefined;
    var len: c.DWORD = wide.len;
    if (c.GetComputerNameExW(c.ComputerNamePhysicalDnsFullyQualified, &wide, &len) == 0 or len == 0)
        return core.Error.EnvUnavailable;
    return toUtf8(wide[0..len], out);
}

/// getaddrinfo needs Winsock started. It counts its starts, so this leaves any
/// the caller made alone.
pub fn startSockets() bool {
    var data: c.WSADATA = undefined;
    return c.WSAStartup(0x0202, &data) == 0;
}

pub fn stopSockets() void {
    _ = c.WSACleanup();
}

pub fn randomBytes(out: []u8) core.Error!void {
    if (c.BCryptGenRandom(null, out.ptr, @intCast(out.len), c.BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
        return core.Error.EnvUnavailable;
}

/// The same list Go's net.Interfaces walks, numbered the way it numbers them:
/// the IPv4 index, or the IPv6 one where there is no IPv4.
pub fn mac() core.Error![6]u8 {
    // Most machines fit on the stack. One with many virtual adapters gets the
    // size Windows asks for, asked again a few times in case an adapter
    // appears in between.
    var stack_buf: [16 * 1024]u8 align(8) = undefined;
    var buf: []align(8) u8 = &stack_buf;
    var heap_buf: ?[]align(8) u8 = null;
    defer if (heap_buf) |owned| std.heap.page_allocator.free(owned);

    const flags = c.GAA_FLAG_SKIP_UNICAST | c.GAA_FLAG_SKIP_ANYCAST | c.GAA_FLAG_SKIP_MULTICAST | c.GAA_FLAG_SKIP_DNS_SERVER;
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        var size: c.ULONG = @intCast(buf.len);
        const status = c.GetAdaptersAddresses(c.AF_UNSPEC, flags, null, @ptrCast(buf.ptr), &size);
        if (status == c.NO_ERROR) break;
        if (status != c.ERROR_BUFFER_OVERFLOW or attempts == 3) return core.Error.EnvUnavailable;
        if (heap_buf) |owned| std.heap.page_allocator.free(owned);
        heap_buf = null;
        const grown = std.heap.page_allocator.alignedAlloc(u8, .@"8", size) catch return core.Error.EnvUnavailable;
        heap_buf = grown;
        buf = grown;
    }

    // The records are IP_ADAPTER_ADDRESSES_LH, which translate-c cannot give
    // whole because of a bitfield. The XP form is the same record cut short
    // before anything read here ends.
    var pick: env.MacPick = .{};
    var walk: ?*const c.IP_ADAPTER_ADDRESSES_XP = @ptrCast(buf.ptr);
    while (walk) |adapter| : (walk = adapter.Next) {
        if (adapter.IfType == c.IF_TYPE_SOFTWARE_LOOPBACK) continue;
        if (adapter.PhysicalAddressLength != 6) continue;
        const ipv4_index = adapter.unnamed_0.unnamed_0.IfIndex;
        const raw = if (ipv4_index != 0) ipv4_index else adapter.Ipv6IfIndex;
        const index = std.math.cast(c_int, raw) orelse continue;
        pick.offer(index, adapter.PhysicalAddress[0..6].*);
    }
    return pick.found orelse core.Error.EnvUnavailable;
}

fn toUtf8(wide: []const u16, out: []u8) core.Error![]const u8 {
    if (std.unicode.calcWtf8Len(wide) > out.len) return core.Error.BufferTooSmall;
    return out[0..std.unicode.wtf16LeToWtf8(out, wide)];
}
