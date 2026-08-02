<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Requirements

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Initial requirements](#initial-requirements)
	- [Platform and foundations](#platform-and-foundations)
	- [Identifier core](#identifier-core)
	- [Command-line interface](#command-line-interface)
	- [Modules](#modules)
	- [Build, CI/CD, and install](#build-cicd-and-install)
	- [Configuration and persistence](#configuration-and-persistence)
	- [Performance and security](#performance-and-security)
	- [Other](#other)
- [Backlog](#backlog)
	- [Misc to-do](#misc-to-do)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Initial requirements](#done---initial-requirements)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

## Initial requirements

### Platform and foundations

- 🛠️ Two implementations of one spec: Go, and Zig. See `design.md`.
	- ✅ Repo, folder layout, and the architecture decisions behind the split.
	- 🛠️ Shared test vectors (`testdata/vectors.tsv`), which both must reproduce.
		- ✅ Time-only rows, across all four curated bases. Sort guarantee checked against them.
		- 🔘 Rows for the other components, once those are specified.

- 🛠️ Base conversion comes from the sister project `convert-base-v2`, not reimplemented.
	- ✅ Go side imports `convertbase` directly, through a local `replace` until `lib/v0.1.0` is tagged upstream. Goal 3 met: the package works as imported, no changes needed to it.
	- 🔘 Zig side reaches it through a reactor WebAssembly module, hosted by a vendored Wasmtime.

- 🛠️ Upstream the reactor WebAssembly build to `convert-base-v2`. This gates the whole Zig and C side.
	- ✅ Upstream has already designed it, in more depth than anything drafted here. Nothing to propose; do not relitigate their choices.
	- 🔘 Send them zuid's requirements: base metadata (radix and padding symbol) for fixed-width padding, a symbol count rather than a byte count, a stable error enum, and the error text. No streaming needed - inputs are about 13 bytes, so the one-shot surface alone unblocks this side.

### Identifier core

- 🛠️ Identifier spec. Drafted in `design.md`; the time component is implemented on the Go side.
	- ✅ One time encoding (Unix ms UTC), replacing the predecessor's four algorithms and three precisions.
	- ✅ Fixed-width zero padding, which is what actually makes output sortable. Width is derived from the horizon rather than tabulated, so moving the horizon moves the widths.
	- 🔘 Confirm the three open questions at the end of that section before the vectors are frozen. The same-millisecond one now has a worked example behind it.
- 🛠️ Component set: time, host, user, MAC, UUID, random. Each independent of the others.
	- ✅ Time. Reserved verbs are rejected rather than silently dropped, so a format string cannot appear to work.
	- 🔘 Host, user, MAC, UUID, random.
- 🔘 Host and user hashed by default, with an explicit opt-out.
- 🛠️ Clock and random source injectable, so output is reproducible under test. Done on the Go side (`WithClock`, `WithFixedTime`, `WithRandom`); the Zig side has no code yet.

### Command-line interface

- 🔘 Format string selecting and ordering components. Improve on the predecessor's surface rather than porting it.
- 🛠️ Curated base list in the help output: **16, 32w, 36, 62**, default 62. `--base` still accepts any base the library knows. Done in `zuid-go`; the shipped CLI is still the Zig one.
	- Base 64 was dropped: its RFC 4648 alphabet does not sort, and it needs the same 8 characters as base 62, which does.
	- ✅ Alphabets reconciled against `convertbase`. Its `32w` is the same 32 symbols the vectors assume, reached by the same alias. All 24 rows reproduce through the real library rather than a local table.
- 🛠️ Generate more than one identifier per invocation. `--count` works, but a time-only format repeats within a millisecond - see the open question in `design.md`.

### Modules

- ✅ Go module, importable without cgo, keeping static cross-compilation. Builds `CGO_ENABLED=0` for linux/arm64, windows/amd64, and darwin/arm64, now driven by `cicd.bash --cross`.
- 🔘 C module: static and shared library plus `zuid.h`, cross-compiled with `zig cc`.
- 🛠️ Both modules Apache-2.0; the command stays GPL-2.0-or-later.
	- ✅ Go side: `LICENSE` at the repo root (GPL-2.0-or-later, for the CLI), `go/LICENSE` and `go/NOTICE` (Apache-2.0, for the module). The SPDX headers now name the file that applies to them.
	- 🔘 C module, once there is one to license.

### Build, CI/CD, and install

- 🛠️ A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- ✅ Drives both toolchains, checks a version floor on each, and says which one is missing rather than failing somewhere later. `--only go|zig` narrows it to one, and then only that one has to be installed.
	- ✅ Go stage builds, vets, checks formatting, and runs the vectors. `--cross` adds the three cross targets into `dist/`.
	- ✅ Refuses `--commit` on a protected branch, so the script cannot be the thing that lands work straight on `main`.
	- ✅ Zig stage skips itself while there is no `build.zig`, rather than failing on work that has not started.
	- 🔘 Packaging and publishing. Both are recognized and rejected with a reason; they wait on the Zig side.
	- 🔘 Fetch the Wasmtime C API, once the Zig side needs it.

- 🔘 Vendor the Wasmtime C API during build rather than assuming it is installed.

- 🔘 Dev-environment install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort.

- 🔘 Release-install script per platform, runnable via a single `curl`/`wget` and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort.

### Configuration and persistence

- 🔘 Default configuration hard-coded
	- 🔘 Overridden by per-user config file, created the first time a default setting is changed.
		- 🔘 Settings live under `~/.config` (YAML or TOML), resistant to errors (e.g. don't bail on the whole thing due to one bad line).
	- 🔘 Overridden by program options at run-time.
	- 🔘 Config file creation belongs to the command only, never to either module.

### Performance and security

- 🔘 Random component from a cryptographic source.
- 🔘 Confirm the hashed host/user components cannot be reversed to the originals.
- 🛠️ Memory safety on the Zig side. See `design.md`.
	- ✅ Decided: standard-library allocators, no hand-written or third-party one. The bigger win is the core not allocating at all.
	- 🔘 Identifier core takes no allocator - fixed widths, caller-supplied buffer. Same shape serves the C module.
	- 🔘 One arena per invocation for the argument handling and the WebAssembly host, so there are no individual frees.
	- 🔘 `std.heap.DebugAllocator` behind it in debug and test builds, `std.heap.smp_allocator` in release.
	- 🔘 Tests allocate through `std.testing.allocator`, which fails on a leak.
	- ✅ Verified on 0.16 what is actually caught: leaks and double frees, yes; use-after-free reads and writes, no. `never_unmap`/`retain_metadata` widen double-free reporting, they do not detect dangling access. No AddressSanitizer for Zig code, and `zig cc -fsanitize=address` does not link.
	- 🔘 Vendored Wasmtime is C, so its sanitizer run uses system clang or gcc, not `zig cc`. Both verified working.

### Other

- ✅ Real README, replacing the template.
- 🔘 Create the GitHub repo and push. Does not exist yet, so nothing can be pushed.
- 🔘 Contact address in `trademark.md` is still a placeholder. Needs a real one.
- 🔘 No logo. `README.md` dropped the template's `assets/logo.png` references since there is no `assets/`.

## Backlog

### Misc to-do

- ✅ Go side brought up: `go/zuid` plus the `zuid-go` command. All 24 vector rows reproduce, 31 tests pass, `gofmt` and `go vet` clean.
	- ✅ Startup is 57 ms, nearly all of it building the base registry. Fine for now; revisit if the shipped CLI ever routes through Go.
- ✅ Move Zig 0.13.0 -> 0.16.0. Installed and verified; 0.13.0 kept alongside so the symlink flips back.
	- ✅ Drift spike: `main(std.process.Init)`, arena, `Io.File.Writer`, `DebugAllocator`, and the no-allocator render path all build and run. 15 rows of `vectors.tsv` reproduce.
	- ✅ `zig fmt` uses four spaces and cannot be configured, so Zig source is spaces, not tabs. See `style_guide.md`.

### Bugs

### Features and enhancements

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

- ✅ Trimmed the `x9muid1` reference copy from 3039 lines to 1280, so it can be read for what it actually does.
	- Dropped the debug-trace, unit-test, and sudo scaffolding, plus the ~1600-line generic library that nothing in it called.
	- Same output and exit codes across a 25-case matrix (all four dtalgos, all precisions, hashing, error paths).

### Future and/or deferred

- ✋ Swap Wasmtime for a small interpreter such as wasm3 if vendoring proves painful. Speed is not the deciding factor.
- ✋ Hand-written bindings for other languages, if the C module turns out not to cover them.

### Canceled
