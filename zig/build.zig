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

    // The command, importing the library as a Zig module.
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtime(b, lib_mod);

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
    wireWasmtimeNoArchive(b, capi_static_mod);
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
    wireWasmtime(b, capi_shared_mod);
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
    shared_lib.setVersionScript(b.path("lib/zuid.map"));
    shared_lib.installHeader(b.path("lib/include/zuid.h"), "zuid.h");
    b.installArtifact(shared_lib);

    // zig build test - the vectors through the real module, plus error paths.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("lib/src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    wireWasmtime(b, test_mod);
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
    }

    var code: u8 = 0;
    const out = b.runAllowFail(&.{ "git", "-C", b.build_root.path orelse ".", "log", "-1", "--format=%ct" }, &code, .ignore) catch return 0;
    return std.fmt.parseInt(i64, std.mem.trim(u8, out, " \r\n"), 10) catch 0;
}

/// Everything a module needs to host the reactor: the embedded wasm bytes,
/// the Wasmtime headers, and the static archive with its link dependencies.
fn wireWasmtime(b: *std.Build, mod: *std.Build.Module) void {
    wireWasmtimeInner(b, mod, true);
}

/// The static C library's variant. Same headers and wasm bytes, but the
/// Wasmtime archive is left out: whoever links the static library supplies it,
/// which is what zuid.h has always told them to do. Adding it here instead
/// nested a 67 MB archive inside libzuid.a, where no linker looks for it.
fn wireWasmtimeNoArchive(b: *std.Build, mod: *std.Build.Module) void {
    wireWasmtimeInner(b, mod, false);
}

fn wireWasmtimeInner(b: *std.Build, mod: *std.Build.Module, link_archive: bool) void {
    mod.link_libc = true;
    mod.addAnonymousImport("convert-base-reactor.wasm", .{
        .root_source_file = b.path("vendor/convert-base-reactor.wasm"),
    });
    mod.addIncludePath(b.path("vendor/wasmtime/include"));
    if (link_archive) {
        mod.addObjectFile(b.path("vendor/wasmtime/lib/libwasmtime.a"));
        // Wasmtime registers unwind frames for its jitted code; Zig bundles this.
        mod.linkSystemLibrary("unwind", .{});
    }
}
