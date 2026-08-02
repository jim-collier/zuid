<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Design

Design, requirements, and direction. The active pre-v1.0.0 bug/feature task list lives in `backlog.md`.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [What this is](#what-this-is)
- [Assumptions](#assumptions)
- [Direction decisions](#direction-decisions)
	- [Two implementations, one spec](#two-implementations-one-spec)
	- [Where base conversion comes from](#where-base-conversion-comes-from)
	- [Reaching the library from C](#reaching-the-library-from-c)
	- [Which bases to offer](#which-bases-to-offer)
	- [Memory safety on the Zig side](#memory-safety-on-the-zig-side)
- [Project structure](#project-structure)
	- [Folder structure](#folder-structure)
	- [Logical code structure](#logical-code-structure)
	- [Data flow](#data-flow)
- [Architecture](#architecture)
	- [Software stack](#software-stack)
	- [Configuration model](#configuration-model)
	- [UI](#ui)
	- [Testing](#testing)
- [Relationship to x9muid1](#relationship-to-x9muid1)
- [Upstream dependency status](#upstream-dependency-status)
- [Licensing](#licensing)
- [Plan](#plan)

<!-- /TOC -->

## What this is

A generator of short, sortable, privacy-preserving unique identifiers, shipped three ways: a command-line tool, a Go module, and a C module.

The identifier is built from a time component, optionally combined with host, user, MAC, UUID, or random components, then rendered in a chosen numeric base. Rendering in a compact base is what makes the result short enough to read aloud and still sort correctly as text.

## Assumptions

- An identifier is generated far more often than it is parsed, so generation speed matters and parsing convenience does not.
- Callers who can start a process should just run the binary. The Go and C modules exist for callers who cannot.
- Sortability is a property worth protecting. Any base whose alphabet does not sort in code-point order breaks it, and that constrains which bases are sensible defaults.
- Privacy defaults matter: host and user components are hashed unless the caller explicitly asks otherwise.

## Direction decisions

### Two implementations, one spec

Among the options considered, we decided on two independent implementations of the same identifier spec rather than one core with bindings around it.

- The Go implementation imports the base-conversion library directly, as any Go caller would.
- The Zig implementation implements the identifier core natively and reaches base conversion through WebAssembly.

The cost is writing the identifier logic twice. Three things buy it back:

- Each implementation genuinely exercises a different artifact of the sister project, which is a stated reason this project exists.
- The two cross-check each other. A shared table of test vectors that both must reproduce catches a mistake in either one, which a single implementation with bindings cannot do.
- Neither is forced into the other's constraints. A single core would have meant either cgo in the Go module, giving up static cross-compilation, or no direct use of the Go library at all.

The shipped command-line tool is built from the Zig implementation. The Go side ships a module plus a small command used mainly to drive the differential tests.

### Where base conversion comes from

Base conversion is not reimplemented here. It comes from the sister project `convert-base-v2`, whose `convertbase` package already carries sixty-odd bases, tail schemes for the large ones, and constant-memory streaming.

Reimplementing that would be a large amount of subtle work, and having two definitions of what a base means is exactly the kind of disagreement that surfaces years later in stored data.

### Reaching the library from C

The sister project publishes two WebAssembly builds today, and neither is callable from C:

- The browser build exports only the Go JavaScript runtime shim, and imports twenty-one functions that only `wasm_exec.js` provides.
- The WASI build is the whole command. It is driven by standard input and output, not by function calls.

A third build closes the gap. Go 1.24 added `//go:wasmexport` together with `-buildmode=c-shared` for the `wasip1` target, which produces a reactor-style module: named function exports, an `_initialize` entry point instead of `_start`, and imports limited to the standard `wasi_snapshot_preview1` set that every embeddable runtime provides.

We decided this build belongs upstream in `convert-base-v2` rather than here. Putting it here would have been faster, but the capability is useful to every caller of that project rather than only to this one, and a base-conversion export surface is a poor fit for a repository about identifiers.

The identifier core stays native Zig. Only base conversion crosses the WebAssembly boundary.

Among the runtimes considered, we decided on the Wasmtime C API: it is the reference implementation, has the best-documented C interface, and is the fastest of the options. It is also the heaviest, and it is not present on a stock system, so it is vendored rather than assumed.

An interpreter such as wasm3 would vendor far more cleanly and is worth revisiting if the dependency proves painful. Generating one identifier is microseconds of work either way, so this is a build-complexity decision far more than a speed one.

### Which bases to offer

The help screen lists a short curated set chosen for identifiers, and `--base` accepts any base the underlying library knows.

The curated set keeps the common case obvious without walling anything off. The full registry contains bases that are actively wrong for an identifier, and a default listing that offers them invites mistakes.

Sortability turns out to be the sharpest filter, and it rules on the alphabet rather than on the size of the base. Byte-order comparison only tracks numeric order if the alphabet is itself in ascending code-point order, which several standard ones are not:

| Base | Sorts | Note
| :-- | :-- | :--
| 16 | yes |
| 32h, 32c, 32w | yes | base32hex, Crockford, and wordsafe all happen to be ascending
| 32r | **no** | RFC 4648 puts `A-Z` before `2-7`
| 36 | yes |
| 62 | yes |
| 64r, 64u | **no** | RFC 4648 puts `A-Z` before `0-9`

That removes base 64 from consideration entirely, which is worth spelling out because it was in an earlier draft of the curated list. Base 64 and base 62 need the same 8 characters for a timestamp, and base 62 is already URL-safe and filesystem-safe with no escaping. So base 64 costs the sort guarantee and buys nothing back at this magnitude.

The curated set is therefore **16, 32w, 36, 62**, with 62 the default. Every one of them sorts.

`--base` still accepts anything the library knows, including the non-sorting ones. Asking for one of those is a legitimate thing to want; getting one without asking is not.

### Memory safety on the Zig side

Zig has no borrow checker, so memory safety is a design constraint here rather than something the language enforces. It does check bounds, overflow, null unwrap, invalid casts, and alignment in debug and safe builds, and as of 0.16 returning the address of a local is a compile error. What it does not catch on its own is use-after-free and double-free.

Among the options considered - writing an allocator, taking a third-party one, or using the standard library's - we decided the standard library's is already the strongest of the three, and that the larger win is not allocating in the first place. Four rules:

- **The identifier core takes no allocator at all.** Output widths are fixed by the spec (11, 9, 9, and 8 characters for bases 16, 32w, 36, and 62), so every intermediate fits in a stack array and the core writes into a buffer the caller supplies. That is also the right shape for the C module, where the caller owns the buffer and there is no free contract to get wrong. A memory bug that cannot be expressed beats one that gets caught.
- **Whatever must allocate goes through a single arena owned by the command.** Argument handling and the WebAssembly host are the only parts needing dynamic memory, and both are per-invocation. An arena releases the lot at once, so the individual frees that use-after-free depends on never happen.
- **`std.heap.DebugAllocator` backs that arena in debug and test builds.** It is the renamed `GeneralPurposeAllocator`, and it is what a hand-written allocator would be trying to become: leak detection with stack traces, and double-free detection that prints the allocation and both frees. Release builds use `std.heap.smp_allocator`.
- **Tests allocate through `std.testing.allocator`**, which fails the test on a leak rather than reporting it at exit.

Writing our own would mean reproducing all of that and then debugging it, in a project whose entire dynamic-memory need is one arena per run. The third-party options were looked at and none of them is a safety story: `zimalloc` and `zig-slab` are performance and layout work, `zig-composable-allocators` is a construction kit in the Alexandrescu style, and `andrewrk/zig-general-purpose-allocator` is the historical repo that became the standard library's. So no third-party allocator dependency.

#### What is actually detected, and what is not

Measured against 0.16 rather than assumed, because an earlier draft of this section got it wrong:

- Leaks and double frees are caught, with full stack traces at the allocation and at both frees.
- **A use-after-free read or write is not caught.** `never_unmap` and `retain_metadata` are worth setting, but not for the reason they look like: they keep the mapping alive and the metadata around, which widens *double-free* reporting and turns a would-be segfault into a legible message. The standard library's own doc comments say exactly this. There is no page protection in the implementation, so touching freed memory silently succeeds.
- Zig 0.16 has no AddressSanitizer for Zig code - `zig build-exe` offers only `-fsanitize-c` and `-fsanitize-thread`. `zig cc -fsanitize=address` does not link either, because the ASan runtime is not shipped.

That gap is the strongest argument for the first rule rather than an argument against it. Since nothing will catch a dangling pointer in Zig, the defense that works is not having one: a core that never takes an allocator has no freeable pointer to dangle, and an arena has no individual free to get wrong.

For the vendored Wasmtime, which is C and allocates on its own, the sanitizer run uses the **system clang or gcc**, not `zig cc`. Both catch heap-use-after-free correctly; that stays a CI/CD step rather than a Zig-side guarantee.

Worth knowing but not worth planning around: an accepted Zig proposal (ziglang/zig#36237) adds a Fil-C-inspired `fil` target ABI - complete memory safety with no escape hatch, at roughly a 1-6x cost. It is a target choice rather than a source change, so if it lands it becomes a build flag. Nothing above conflicts with it.

## Identifier specification

Draft. This is the part most open to revision, and `testdata/vectors.tsv` is generated from whatever this section says.

### One time encoding, not four

The predecessor offers four date/time algorithms and three precisions. Two of the four are acknowledged in its own help text as strictly worse than the others, and the combination of algorithm, precision, and base yields well over a hundred encodings that produce similar-looking output with no way to tell them apart after the fact.

Its author's warning about this is worth quoting, because it is the clearest statement of the problem:

> For any given use-case, you should never mix type, base, and/or precision, or the very purpose for using this tool could be obviated and you'd wind up hating life at best, or with data collisions and/or loss data at worst.

We decided on a single time encoding: **milliseconds elapsed since the Unix epoch, UTC**. No algorithm choice, and no precision choice.

This is the predecessor's `--dtalgo 1` at millisecond resolution. The others were rejected: packing `YYYYMMDDHHmmSS` as a decimal integer wastes roughly a third of the range on digit combinations that cannot occur, and subdividing the day to fit the base exactly is clever but makes the value impossible to reason about without the tool that produced it.

Removing the choice is the point. An encoding nobody can select wrongly needs no marker saying which one was used.

### Fixed width, because sorting depends on it

Rendering an integer in a compact base does not by itself produce something that sorts. Lexicographic comparison reads left to right, so a shorter string sorts before a longer one regardless of value, and identifiers generated years apart differ in length.

So output is **zero-padded to a fixed width**, chosen per base as the width that holds any timestamp through the year 2500:

| Base | Width | Actually good through
| :-- | --: | :--
| 16 | 11 | 2527
| 32 | 9 | 3084
| 36 | 9 | 5188
| 62 | 8 | 8888
| 64 | 8 | 10889

Width is quantized, so most of those overshoot the horizon by a wide margin and the exact horizon barely matters. Base 62 is the case that shows it: 8 characters last until 8888, and the next width down runs out in 2081. There is no useful choice between them.

Two consequences worth stating plainly:

- Sorting is byte-order sorting. It holds under `LC_COLLATE=C`, and does not hold under a locale-aware collation that ignores case, which would fold `A` and `a` together. Any base whose alphabet uses both cases has this property, and it is a property of the locale rather than of the identifier.
- Padding costs characters the predecessor did not spend. A base 62 timestamp is 8 characters here against its 6, and that is the price of the sort guarantee.

### Format and components

The format string keeps the predecessor's shape, since it reads well and is the part worth carrying forward:

| Token | Component
| :-- | :--
| `%d` | Time, as above. The default format is exactly this.
| `%h` | Host name, hashed by default
| `%u` | User name, hashed by default
| `%f` | Fully-qualified domain name, hashed by default
| `%m` | MAC address of the first interface with a gateway
| `%g` | A UUID v4
| `%r` | Random data from a cryptographic source

Hashed components are SHA-256, rendered in the same base as the rest and truncated to a configurable number of characters. Truncation is what makes them short enough to be useful; it also means they are a fingerprint rather than an identity, which is the intent.

### Open questions

Reversible choices, best-guessed for now, and worth a second opinion before the vectors are frozen:

- Year 2500 as the padding horizon. Mostly moot, per the table above - only base 16 sits anywhere near its limit.
- Milliseconds as the fixed resolution. Seconds would be shorter, microseconds more collision-resistant for rapid generation.
- Whether a run of identifiers generated within the same millisecond should be disambiguated automatically, or left to the caller to add `%r`.

## Project structure

### Folder structure

```
go/
	zuid/               the Go module
	cmd/zuid-go/        command, for differential testing
zig/
	src/                identifier core, and the WebAssembly host
	include/zuid.h      the C header
testdata/
	vectors.tsv         shared spec; both implementations must reproduce it
cicd/
project/
```

### Logical code structure

Both implementations separate the same three concerns, so a change to the spec lands in matching places on each side:

- **Components.** Time, host, user, MAC, UUID, and random. Each produces an integer or a byte string, and each is independent of the others.
- **Assembly.** Combining the selected components in the order the format string specifies.
- **Rendering.** Handing the assembled value to base conversion.

Only rendering differs between the two implementations. Components and assembly are ordinary native code on both sides.

### Data flow

```
format string -> component selection -> assembly -> base conversion -> output
```

Base conversion is a direct function call in Go, and a WebAssembly call through the vendored runtime in Zig.

## Architecture

### Software stack

- **Zig 0.16** for the identifier core, the command-line tool, and the C module. Its C interoperation is direct, and `zig cc` cross-compiles to every target from one machine, which removes the usual reason a C artifact is expensive to ship. The version is pinned to current stable because no Zig code is written yet, and 0.13 through 0.16 rewrote both the I/O and the allocator surfaces - starting on the old one would mean porting later for nothing.
- **Go** for the module, importing `convertbase`.
- **WebAssembly** as the bridge from Zig to base conversion.

### Configuration model

Defaults are compiled in, overridden by a per-user file, overridden by command-line options.

The per-user file is written only when a default is first changed, and lives under `~/.config`. A single bad line is skipped rather than failing the whole file. A library must never create files in a caller's home directory, so this belongs to the command alone, not to either module.

### UI

Command line only. The interface is a deliberate improvement on the predecessor rather than a port of it, which is covered under [Relationship to x9muid1](#relationship-to-x9muid1).

### Testing

`testdata/vectors.tsv` is the specification in executable form. Each row fixes the inputs, including the clock and any random source, and the expected output. Both implementations run it.

Fixing the clock and the random source is what makes an identifier generator testable at all. Both implementations therefore take those as injectable inputs rather than reading them directly at the point of use.

## Relationship to x9muid1

`cicd/utility/x9muid1` is the 2023 bash predecessor, kept as reference. It defines the problem, not the solution.

Carried forward: the format-string idea, the component set, hashed host and user by default, and time-based sortable output.

Deliberately not carried forward: its base list, which is longer than an identifier generator needs, and its command-line surface, which grew by accretion. Improving on that interface is one of the reasons this project exists.

## Upstream dependency status

Both goals depend on `convert-base-v2` work that has not yet landed, and this is currently the critical path:

- The `convertbase` package lives on an unmerged branch. There is no `lib/v0.1.0` tag, so the module is not fetchable, and a local `replace` directive is needed until one exists.
- The reactor WebAssembly build does not exist yet and has to be written and released upstream.

Verified by experiment, not assumed: a `wasip1` reactor module built with `//go:wasmexport` exports its named functions and imports only the standard WASI set. The approach works. What remains is applying it to the real library. A trivial such module is about 1.8 MB, which is the Go runtime floor, so the real one is expected to land somewhere between two and four megabytes.

## Licensing

- The command is GPL-2.0-or-later.
- Both modules are Apache-2.0, matching the library they build on, so that neither is encumbered for a caller embedding it.

This split is the same arrangement the sister project uses, and for the same reason: attribution should follow the code into somebody else's product, without reciprocity obligations that would stop anyone linking it.

## Plan

1. Fix the identifier spec and write `testdata/vectors.tsv` from it.
2. Build the Go implementation against a local checkout of `convertbase`.
3. Upstream the reactor WebAssembly build to `convert-base-v2`.
4. Build the Zig implementation and the C module against that.
5. Run both against the shared vectors, and reconcile.
6. Command-line surface, then configuration, then packaging.

Step 3 gates step 4. Steps 1 and 2 do not depend on it, and come first for that reason.
