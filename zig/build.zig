// Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
// Licensed under the GPL, Version 2 or later. Full text in LICENSE.txt, or:
//     https://spdx.org/licenses/GPL-2.0-or-later.html
// SPDX-License-Identifier: GPL-2.0-or-later

//! Builds the three Zig-side artifacts from one tree: the zuid command
//! (GPL-2.0-or-later), and the static and shared C libraries (Apache-2.0,
//! see lib/). All of them embed the upstream reactor wasm module and link the
//! vendored Wasmtime C API statically; cicd/cicd.bash fetches both into
//! vendor/ before building.

const std = @import("std");

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
    wireWasmtime(b, capi_static_mod);
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
        .use_llvm = true,
    });
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

/// Everything a module needs to host the reactor: the embedded wasm bytes,
/// the Wasmtime headers, and the static archive with its link dependencies.
fn wireWasmtime(b: *std.Build, mod: *std.Build.Module) void {
    mod.link_libc = true;
    mod.addAnonymousImport("convert-base-reactor.wasm", .{
        .root_source_file = b.path("vendor/convert-base-reactor.wasm"),
    });
    mod.addIncludePath(b.path("vendor/wasmtime/include"));
    mod.addObjectFile(b.path("vendor/wasmtime/lib/libwasmtime.a"));
    // Wasmtime registers unwind frames for its jitted code; Zig bundles this.
    mod.linkSystemLibrary("unwind", .{});
}
