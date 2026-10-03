// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the GPL, Version 2 or later. Full text in zig/cmd/LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! Builds the three Zig-side artifacts from one tree: the zuid command
//! (GPL-2.0-or-later), and the static and shared C libraries (Apache-2.0,
//! see lib/). All of them embed the upstream reactor wasm module and link the
//! vendored Wasmtime C API statically; cicd/cicd.bash fetches both into
//! vendor/ before building.

const std = @import("std");

/// The shared library's soname version. Read from the one version constant so
/// there is nothing to keep in step, with any prerelease tag dropped - an
/// soname has no room for one. The major is the C ABI promise that goes with
/// the error codes: a consumer records libzuid.so.1 and keeps working as long
/// as that number holds.
const abi_version: std.SemanticVersion = v: {
    const parsed = std.SemanticVersion.parse(@import("lib/src/core.zig").version) catch
        @compileError("core.zig version is not a semantic version");
    break :v .{ .major = parsed.major, .minor = parsed.minor, .patch = parsed.patch };
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const wasmtime = wasmtimeDir(b, target);

    // The command, importing the library as a Zig module.
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtime(b, lib_mod, wasmtime);

    const cmd_mod = b.createModule(.{
        .root_source_file = b.path("cmd/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cmd_mod.addImport("zuid", lib_mod);
    const build_options = b.addOptions();
    build_options.addOption(i64, "build_epoch", buildEpoch(b));
    cmd_mod.addOptions("build_options", build_options);

    const exe = b.addExecutable(.{
        .name = "zuid",
        .root_module = cmd_mod,
        // The self-hosted x86_64 backend cannot yet resolve symbols out of the
        // wasmtime archive; LLVM's linker path can.
        .use_llvm = true,
    });
    b.installArtifact(exe);

    // The C module, twice: a self-contained shared library, and a static one
    // whose consumers link the wasmtime archive themselves (zuid.h says how).
    const capi_static_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/capi.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtimeNoArchive(b, capi_static_mod, wasmtime);
    const static_lib = b.addLibrary(.{
        .name = "zuid",
        .linkage = .static,
        .root_module = capi_static_mod,
        .use_llvm = true,
    });
    // A C consumer links with its own toolchain, which has no Zig compiler-rt.
    static_lib.bundle_compiler_rt = true;
    static_lib.installHeader(b.path("lib/include/zuid.h"), "zuid.h");
    b.installArtifact(static_lib);

    const capi_shared_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/capi.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtime(b, capi_shared_mod, wasmtime);
    const shared_lib = b.addLibrary(.{
        .name = "zuid",
        .linkage = .dynamic,
        .root_module = capi_shared_mod,
        .version = abi_version,
        .use_llvm = true,
    });
    // Only the zuid_* entry points are visible, and everything else binds
    // inside the library. zuid.h calls the shared library self-contained, and
    // without this it exported the whole Wasmtime C API for anyone to displace.
    // Zig's Mach-O linker ignores it; see relinkDylib.
    shared_lib.setVersionScript(b.path("lib/zuid.map"));
    // macOS's soname. Zig's default is the bare libzuid.dylib, which would let
    // a program built against ABI 1 load ABI 2.
    if (target.result.os.tag.isDarwin()) {
        shared_lib.install_name = b.fmt("@rpath/libzuid.{d}.dylib", .{abi_version.major});
    }
    shared_lib.installHeader(b.path("lib/include/zuid.h"), "zuid.h");
    const install_shared = b.addInstallArtifact(shared_lib, .{});
    b.getInstallStep().dependOn(&install_shared.step);
    if (target.result.os.tag == .macos) relinkDylib(b, target, shared_lib, static_lib, wasmtime, install_shared);

    // zig build test - the vectors through the real module, plus error paths.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtime(b, test_mod, wasmtime);
    test_mod.addAnonymousImport("vectors.tsv", .{
        .root_source_file = b.path("../testdata/vectors.tsv"),
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = true,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Replay the shared vectors and the error paths");
    test_step.dependOn(&run_tests.step);

    // The same tests as a binary in zig-out/test. Run directly rather than by
    // the build runner, it prints a line per test, which cicd turns into one
    // status line per test ID.
    const install_tests = b.addInstallArtifact(tests, .{ .dest_dir = .{ .override = .{ .custom = "test" } } });
    const test_bin_step = b.step("test-bin", "Build the test binary into zig-out/test");
    test_bin_step.dependOn(&install_tests.step);
}

/// Zig's Mach-O linker ignores lib/zuid.map and has no exported symbols list,
/// so its dylib exports all of Wasmtime. Apple's linker takes such a list, so
/// on a Mac the dylib is linked again with it, from the static library's
/// objects, and installed over Zig's copy, keeping the symlinks Zig made.
/// Apple's linker ad-hoc signs an arm64 slice itself, as Zig's does.
fn relinkDylib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    shared_lib: *std.Build.Step.Compile,
    static_lib: *std.Build.Step.Compile,
    wasmtime: []const u8,
    installed: *std.Build.Step.InstallArtifact,
) void {
    // xcrun with no command line tools opens an installer window rather than
    // failing, so ask xcode-select first.
    var code: u8 = 0;
    const have_tools = b.graph.host.result.os.tag == .macos and
        if (b.runAllowFail(&.{ "xcode-select", "-p" }, &code, .ignore)) |_| true else |_| false;
    if (!have_tools) {
        std.log.warn("no Apple linker here, which takes a Mac with the Xcode command line tools, so libzuid.dylib exports all of Wasmtime rather than only zuid_*", .{});
        return;
    }
    const t = target.result;
    const arch = switch (t.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        else => std.process.fatal("no macOS dylib relink for {t}", .{t.cpu.arch}),
    };
    const min = t.os.version_range.semver.min;
    const exports = b.addWriteFiles().add("zuid.exp", exportedSymbols(b));

    const relink = b.addSystemCommand(&.{ "xcrun", "clang", "-dynamiclib", "-arch", arch });
    relink.addArg(b.fmt("-mmacosx-version-min={d}.{d}.{d}", .{ min.major, min.minor, min.patch }));
    relink.addArgs(&.{ "-install_name", shared_lib.install_name.? });
    relink.addArgs(&.{ "-current_version", b.fmt("{d}.{d}.{d}", .{ abi_version.major, abi_version.minor, abi_version.patch }) });
    // Zig's value. Apple's default is 0.0.0.
    relink.addArgs(&.{ "-compatibility_version", "1.0.0" });
    relink.addPrefixedFileArg("-Wl,-exported_symbols_list,", exports);
    // -force_load takes every object in the archive, compiler-rt included, and
    // -dead_strip then drops what no export reaches.
    relink.addArg("-Wl,-dead_strip");
    relink.addPrefixedFileArg("-Wl,-force_load,", static_lib.getEmittedBin());
    relink.addFileArg(b.path(b.fmt("{s}/lib/libwasmtime.a", .{wasmtime})));
    relink.addArg("-o");
    const relinked = relink.addOutputFileArg(shared_lib.out_filename);

    const install = b.addInstallLibFile(relinked, shared_lib.out_filename);
    install.step.dependOn(&installed.step);
    b.getInstallStep().dependOn(&install.step);
}

/// lib/zuid.map's global patterns as an Apple exported symbols list, so both
/// platforms export one set from one file. Mach-O names take a leading
/// underscore, and both linkers read the * wildcard the same way.
fn exportedSymbols(b: *std.Build) []const u8 {
    const map = b.build_root.handle.readFileAlloc(b.graph.io, "lib/zuid.map", b.allocator, .limited(64 * 1024)) catch |err|
        std.process.fatal("could not read lib/zuid.map: {t}", .{err});
    var list: std.ArrayList(u8) = .empty;
    var in_global = false;
    var lines = std.mem.splitScalar(u8, map, '\n');
    while (lines.next()) |line| {
        const code = line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len];
        var words = std.mem.tokenizeAny(u8, code, " \t\r;{}");
        while (words.next()) |word| {
            if (std.mem.eql(u8, word, "global:")) {
                in_global = true;
            } else if (std.mem.eql(u8, word, "local:")) {
                in_global = false;
            } else if (in_global) {
                list.print(b.allocator, "_{s}\n", .{word}) catch @panic("OOM");
            }
        }
    }
    if (list.items.len == 0) std.process.fatal("lib/zuid.map lists no global symbols", .{});
    return list.items;
}

/// Unix seconds the build number comes from. The commit date rather than the
/// clock, so one commit always builds to the same bytes. A tarball build has
/// no history, so -Dbuild-epoch or SOURCE_DATE_EPOCH can supply it. Zero means
/// no build number.
fn buildEpoch(b: *std.Build) i64 {
    if (b.option(i64, "build-epoch", "Unix seconds to stamp the build number from (default: the HEAD commit date)")) |secs| return secs;

    // An empty SOURCE_DATE_EPOCH is what a tarball script exports when its own
    // lookup came back empty, so it means "no answer" rather than "epoch zero".
    // Taking it literally dropped the build number from a build that had a
    // perfectly good commit date sitting there.
    if (b.graph.environ_map.get("SOURCE_DATE_EPOCH")) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        if (trimmed.len > 0) {
            if (std.fmt.parseInt(i64, trimmed, 10)) |secs| {
                return secs;
            } else |_| {
                // Not fatal, but not silent either: a typo here would otherwise
                // change the build stamp with nothing to show why.
                std.log.warn("SOURCE_DATE_EPOCH is not a number ('{s}'); using the HEAD commit date instead", .{trimmed});
            }
        }
        // Clang reads it too, for @cImport, and refuses anything but a number.
        // A warm cache hid that.
        _ = b.graph.environ_map.swapRemove("SOURCE_DATE_EPOCH");
    }

    var code: u8 = 0;
    const out = b.runAllowFail(&.{ "git", "-C", b.build_root.path orelse ".", "log", "-1", "--format=%ct" }, &code, .ignore) catch return 0;
    return std.fmt.parseInt(i64, std.mem.trim(u8, out, " \r\n"), 10) catch 0;
}

/// Where the target's Wasmtime C API is vendored. vendor/wasmtime is the build
/// machine's own. Any other target's sits beside it under Wasmtime's name for
/// the platform, such as vendor/wasmtime-aarch64-macos, the second slice of a
/// macOS universal build. package.bash picks the same way.
fn wasmtimeDir(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const host = b.graph.host.result;
    const t = target.result;
    if (t.cpu.arch == host.cpu.arch and t.os.tag == host.os.tag) return "vendor/wasmtime";
    const dir = b.fmt("vendor/wasmtime-{s}-{s}", .{ @tagName(t.cpu.arch), @tagName(t.os.tag) });
    // Otherwise the first error is a missing header, which says nothing about why.
    b.build_root.handle.access(b.graph.io, b.fmt("{s}/lib/libwasmtime.a", .{dir}), .{}) catch
        std.process.fatal("no Wasmtime for {s}-{s} in {s}. cicd/cicd.bash vendors one on a Mac for the other macOS slice; for anything else, add its pin there first.", .{ @tagName(t.cpu.arch), @tagName(t.os.tag), dir });
    return dir;
}

/// Everything a module needs to host the reactor: the embedded wasm bytes,
/// the Wasmtime headers, and the static archive with its link dependencies.
fn wireWasmtime(b: *std.Build, mod: *std.Build.Module, wasmtime: []const u8) void {
    wireWasmtimeInner(b, mod, wasmtime, true);
}

/// The static C library's variant. Same headers and wasm bytes, but the
/// Wasmtime archive is left out: whoever links the static library supplies it,
/// which is what zuid.h has always told them to do. Adding it here instead
/// nested a 67 MB archive inside libzuid.a, where no linker looks for it.
fn wireWasmtimeNoArchive(b: *std.Build, mod: *std.Build.Module, wasmtime: []const u8) void {
    wireWasmtimeInner(b, mod, wasmtime, false);
}

fn wireWasmtimeInner(b: *std.Build, mod: *std.Build.Module, wasmtime: []const u8, link_archive: bool) void {
    mod.link_libc = true;
    mod.addAnonymousImport("convert-base-reactor.wasm", .{
        .root_source_file = b.path("vendor/convert-base-reactor.wasm"),
    });
    mod.addIncludePath(b.path(b.fmt("{s}/include", .{wasmtime})));
    if (link_archive) {
        mod.addObjectFile(b.path(b.fmt("{s}/lib/libwasmtime.a", .{wasmtime})));
        // Wasmtime registers unwind frames for its jitted code; Zig bundles this.
        mod.linkSystemLibrary("unwind", .{});
    }
}
