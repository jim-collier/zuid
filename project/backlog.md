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
	- ✅ Shared test vectors (`testdata/vectors.tsv`), which both must reproduce.
		- ✅ Time-only rows, across all four curated bases and all three precisions, including truncation and horizon-boundary rows. Sort guarantee checked against them.
		- ✅ Rows for the other components: 115 in total. An `env` column carries the injected host, user, FQDN, hardware address, random stream, and width options, so a row states only what it cares about.
		- ✅ Expected values computed a third time, from `design.md` rather than from either implementation, so agreement between the two cannot just mean they are wrong the same way.

- 🛠️ Base conversion comes from the sister project `convert-base-v2`, not reimplemented.
	- ✅ Go side imports `convertbase` directly, through a local `replace` until `lib/v0.1.0` is tagged upstream. Goal 3 met: the package works as imported, no changes needed to it.
	- ✅ Zig side reaches it through a reactor WebAssembly module, hosted by a vendored Wasmtime. Goal 4 met: the module is embedded in the binary, all vectors reproduce through it, and its region ledger stays at zero.

- 🛠️ Upstream the reactor WebAssembly build to `convert-base-v2`. This gates the whole Zig and C side.
	- ✅ Upstream has already designed it, in more depth than anything drafted here. Nothing to propose; do not relitigate their choices.
	- ✅ Sent them zuid's requirements: base metadata (radix and padding symbol) for fixed-width padding, a symbol count rather than a byte count, a stable error enum, and the error text. No streaming needed - inputs are about 13 bytes, so the one-shot surface alone unblocks this side.
	- ✅ Upstream now has a working reactor build. Streaming is still in progress there, but zuid does not use it, so the gate on the Zig side is lifted.

### Identifier core

- 🛠️ Identifier spec. Drafted in `design.md`; the time component is implemented on both sides.
	- ✅ One time encoding (units since the Unix epoch, UTC), replacing the predecessor's four algorithms. Precision stays selectable, carrying its surface forward: -1 minute, 0 second (default), 1 millisecond.
	- ✅ Fixed-width zero padding, which is what actually makes output sortable. Width is derived from the horizon rather than tabulated, so moving the horizon moves the widths.
	- ✅ The three open questions are settled: horizon year 3000, precision as above, same-tick repeats stay literal with a warning once multi-emit lands. Vectors regenerated and frozen for the time component.
- ✅ Component set: time, host, user, FQDN, MAC, UUID, random. Each independent of the others.
	- ✅ Time. An unknown verb is rejected rather than silently dropped, so a format string cannot appear to work.
	- ✅ Host, user, FQDN, MAC, UUID, random, on both sides.
	- ✅ Every component is a fixed symbol count wide, so an identifier can be split by offset - not only sorted. The one exception is an unhashed name, which is text.
	- ✅ `%m` takes the lowest-numbered non-loopback interface rather than the predecessor's default-route one, which would need the routing table on three platforms.
	- ✅ `%g` is a real UUID v4, rendered as the 128-bit number rather than the dashed text form, which does not sort.
	- ✅ Truncated components are refused in a base with multi-byte digits: there is no way to split a converted string at a symbol boundary, so both sides refuse rather than each guess. Padding is unaffected.
- ✅ Host, user, and FQDN hashed by default, with an explicit opt-out. SHA-256, rightmost 8 symbols; `--no-hash` emits the names literally and `--hash-chars` resizes them.
- ✅ Every environment source injectable, so output is reproducible under test. Go has `WithClock`/`WithFixedTime`/`WithRandom`/`WithHostname`/`WithUsername`/`WithFQDN`/`WithMAC`; Zig has an `Env` interface alongside the existing `Converter`, with `env.zig` as its one live implementation.

### Command-line interface

- ✅ Format string selecting and ordering components. Improve on the predecessor's surface rather than porting it.
	- ✅ The CLI exists: `zuid [-b base] [-f format] [-p precision] [--no-hash] [--hash-chars n] [--rand-chars n]`, all seven components plus `%%` literals, unknown verbs rejected with a clear message.
	- ✅ Precision flag: `-p -1|0|1` for minute/second/millisecond, default second - same surface and default as the predecessor.
	- ✅ Two hashing flags rather than the predecessor's six. Per-component widths were exactly the sort of accretion this was meant to improve on.
- ✅ Curated base list in the help output: **16, 32w, 36, 62**, default 62. `--base` still accepts any base the library knows, and an unknown one surfaces the library's near-match suggestion. The `zuid-go` command that first carried it was dropped - the Go side is module-only.
	- Base 64 was dropped: its RFC 4648 alphabet does not sort, and it needs the same 8 characters as base 62, which does.
	- ✅ Alphabets reconciled against `convertbase`. Its `32w` is the same 32 symbols the vectors assume, reached by the same alias. All 24 rows reproduce through the real library rather than a local table.
- 🔘 Generate more than one identifier per invocation. A time-only format repeats within one tick.
	- Decided: output stays literal - nothing is appended silently - but repeats in one invocation's output get a stderr warning suggesting `%r`.

### Modules

- ✅ Go module, importable without cgo, keeping static cross-compilation. Builds `CGO_ENABLED=0` for linux/arm64, windows/amd64, and darwin/arm64, now driven by `cicd.bash --cross`.
- 🛠️ C module: static and shared library plus `zuid.h`, cross-compiled with `zig cc`.
	- ✅ Native artifacts: `libzuid.a` (compiler-rt bundled), self-contained `libzuid.so`, and the installed header. Both link modes verified from plain gcc against a fixed clock.
	- ✅ That verification is now a cicd stage rather than something done by hand, so the C ABI cannot rot unnoticed. It deliberately uses the system compiler - `zig cc` would prove nothing about a foreign toolchain.
	- ✅ Every component reachable from C, with the width options sticky on the context the way precision already was.
	- 🔘 Cross targets. Needs a vendored Wasmtime archive per target; deferred with packaging.
- ✅ Both modules Apache-2.0; the command stays GPL-2.0-or-later.
	- ✅ Per-directory license files, all `.txt`: repo root and `zig/cmd/` GPL-2.0-or-later; `go/` and `zig/lib/` each Apache-2.0 with a `NOTICE.txt`. Placed ahead of the Zig source so the split is locked in.
	- ✅ Dropping the Go command removed the one awkward case - a GPL command inside the Apache module directory - so no prose has to explain the split anymore.

### Build, CI/CD, and install

- 🛠️ A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- ✅ Drives both toolchains, checks a version floor on each, and says which one is missing rather than failing somewhere later. `--only go|zig` narrows it to one, and then only that one has to be installed.
	- ✅ Go stage builds, vets, checks formatting, and runs the vectors. `--cross` adds the three cross targets into `dist/`.
	- ✅ Refuses `--commit` on a protected branch, so the script cannot be the thing that lands work straight on `main`.
	- ✅ Zig stage skips itself while there is no `build.zig`, rather than failing on work that has not started.
	- ✅ Zig stage builds ReleaseSafe, replays the vectors under both Wasmtime compilers, checks `zig fmt`, and then compiles the C smoke test with the system gcc or clang in both link modes. It skips that last part with a note if neither compiler is installed.
	- 🔘 Packaging and publishing. Both are recognized and rejected with a reason.
	- ✅ Fetch the Wasmtime C API: pinned version, checksum verified, extracted into `zig/vendor/`. The reactor wasm refreshes from the sibling checkout whenever it differs, and an already-vendored copy suffices when the sibling is absent.

- ✅ Vendor the Wasmtime C API during build rather than assuming it is installed.

- 🔘 Dev-environment install script (Linux bash, macOS sh, Windows PowerShell), runnable via a single `curl`/`wget` and documented under "how to develop". Clones main, installs dependencies, and states what it will do with an option to abort.

- 🔘 Release-install script per platform, runnable via a single `curl`/`wget` and documented under "how to install". Downloads, installs, and runs the latest release, with an option to abort.

### Configuration and persistence

- 🔘 Default configuration hard-coded
	- 🔘 Overridden by per-user config file, created the first time a default setting is changed.
		- 🔘 Settings live under `~/.config` (YAML or TOML), resistant to errors (e.g. don't bail on the whole thing due to one bad line).
	- 🔘 Overridden by program options at run-time.
	- 🔘 Config file creation belongs to the command only, never to either module.

### Performance and security

- ✅ Random component from a cryptographic source. Go uses `crypto/rand`; Zig uses `getentropy` through libc, because 0.16 moved randomness onto `Io` the same way it moved the clocks, and the C module has no `Io` to hand it.
- 🛠️ Confirm the hashed host/user components cannot be reversed to the originals.
	- ✅ Not reversible by construction: 8 base-62 symbols out of a 256-bit SHA-256 discards about 200 bits, so nothing can be inverted back to a unique name.
	- 🔘 The real exposure is a dictionary attack - host and user names come from a small space, so an attacker can hash candidates and compare. Decide whether that matters enough to want a salt, and where a salt could live given that the same name must hash the same on every machine.
- 🛠️ Memory safety on the Zig side. See `design.md`.
	- ✅ Decided: standard-library allocators, no hand-written or third-party one. The bigger win is the core not allocating at all.
	- ✅ Identifier core takes no allocator - fixed widths, caller-supplied buffer. Same shape serves the C module.
	- ✅ It went further than the arena plan: nothing on the Zig side allocates at all. Argv comes from the process-provided arena, Wasmtime owns its own memory, and the C module is one allocation per context.
	- ✅ `std.heap.DebugAllocator` in debug builds, `std.heap.smp_allocator` in release - the C module's context allocation, the only one there is.
	- ✅ Tests turned out to need no allocator; the vectors file is embedded at build time.
	- ✅ Verified on 0.16 what is actually caught: leaks and double frees, yes; use-after-free reads and writes, no. `never_unmap`/`retain_metadata` widen double-free reporting, they do not detect dangling access. No AddressSanitizer for Zig code, and `zig cc -fsanitize=address` does not link.
	- ✋ Sanitizer run on the vendored Wasmtime. The vendored artifact turned out to be a prebuilt archive, so there is nothing local to instrument; revisit only if it is ever built from source here.

### Other

- ✅ Real README, replacing the template.
- 🔘 Create the GitHub repo and push. Does not exist yet, so nothing can be pushed.
- 🔘 Contact address in `trademark.md` is still a placeholder. Needs a real one.
- 🔘 No logo. `README.md` dropped the template's `assets/logo.png` references since there is no `assets/`.

## Backlog

### Misc to-do

- ✅ The remaining components landed on both sides, and the vectors grew from 72 rows to 115.
	- ✅ The `Converter` interface now carries a from-base, since hashes, hardware addresses, and UUIDs all arrive as hex rather than decimal.
	- ✅ Zig gained an `Env` interface next to it, so the core still touches neither the runtime nor the operating system.
	- 🔘 `%m` is Linux-only on the Zig side - it reads `getifaddrs` for `AF_PACKET`, and macOS wants `AF_LINK` instead. The Go module is already portable. Worth doing alongside the cross targets, since nothing on the Zig side cross-compiles yet either.

- ✅ Zig side brought up: `zig/lib` (core, wasm host, C module) and `zig/cmd` (CLI).
	- ✅ All 24 vector rows reproduce through the embedded module, under both of Wasmtime's compilers.
	- ✅ The C header verified from plain gcc, shared and static.
	- ✅ Every CLI run exercises the upstream module end to end, which was the point of making the CLI Zig-only.
- ✅ Go side brought up: `go/zuid`. All 24 vector rows reproduce, `gofmt` and `go vet` clean.
	- ✅ Startup is 57 ms, nearly all of it building the base registry. Irrelevant now that nothing user-facing routes through Go.
	- ✅ The `zuid-go` command was later dropped: the CLI is Zig-only, so that every use of it also exercises the upstream WebAssembly module. The module's own tests replay the vectors, which is the differential check from the Go side.
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

- ✋ CLI startup is ~0.5 s, nearly all of it the module's own `_initialize` building the base registry inside the wasm. Options if it starts to matter: ask upstream about lazier registry construction, or cache a precompiled module per machine. Not worth it before the surface settles.
- ✋ Swap Wasmtime for a small interpreter such as wasm3 if vendoring proves painful. Speed is not the deciding factor.
- ✋ Hand-written bindings for other languages, if the C module turns out not to cover them.

### Canceled
