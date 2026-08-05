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
- [Overview](#overview)
	- [Two implementations, one spec](#two-implementations-one-spec)
	- [Where base conversion comes from](#where-base-conversion-comes-from)
	- [Reaching the library from C](#reaching-the-library-from-c)
	- [Which bases to offer](#which-bases-to-offer)
	- [Memory safety on the Zig side](#memory-safety-on-the-zig-side)
		- [What is actually detected, and what is not](#what-is-actually-detected-and-what-is-not)
- [Identifier specification](#identifier-specification)
	- [One time encoding, not four](#one-time-encoding-not-four)
	- [Fixed width, because sorting depends on it](#fixed-width-because-sorting-depends-on-it)
	- [Format and components](#format-and-components)
	- [Component widths](#component-widths)
	- [Resolved questions](#resolved-questions)
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

A generator of short, sortable, privacy-preserving unique identifiers, in three forms: a command-line tool, a Go module, and a C module.

The identifier is built from a time component, optionally combined with host, user, MAC, UUID, or random components, then rendered in a chosen numeric base. Rendering in a compact base is what makes the result short enough to read aloud and still sort correctly as text.

## Assumptions

- An identifier is generated far more often than it is parsed, so generation speed matters and parsing convenience does not.

- Callers who can start a process should just run the binary. The Go and C modules exist for callers who cannot.

- Sortability is a property worth protecting. Any base whose alphabet does not sort in code-point order breaks it, and that constrains which bases are sensible defaults.

- Privacy defaults matter: host and user components are hashed unless the caller explicitly asks otherwise.

## Overview

### Two implementations, one spec

Among the options considered, we decided on two independent implementations of the same identifier spec rather than one core with bindings around it.

- The Go implementation imports the base-conversion library directly, as any Go caller would.
- The Zig implementation implements the identifier core natively and reaches base conversion through WebAssembly.

The cost is writing the identifier logic twice. Three things buy it back:

- Each implementation genuinely exercises a different artifact of the sister project, which is a stated reason this project exists.
- The two cross-check each other. A shared table of test vectors that both must reproduce catches a mistake in either one, which a single implementation with bindings cannot do.
- Neither is forced into the other's constraints. A single core would have meant either cgo in the Go module, giving up static cross-compilation, or no direct use of the Go library at all.

The command-line tool is built from the Zig implementation, and every use of it exercises the upstream WebAssembly module - so ordinary CLI testing doubles as ongoing validation of that artifact. The Go side is a module only; its tests replay the shared vectors, which is the differential check from that side.

### Where base conversion comes from

Base conversion is not reimplemented here. It comes from the sister project `convert-base-v2`, whose `convertbase` package already carries seventy-odd bases, tail schemes for the large ones, and constant-memory streaming.

Reimplementing that would be a large amount of subtle work, and having two definitions of what a base means is exactly the kind of disagreement that shows up years later in stored data.

### Reaching the library from C

The sister project publishes two WebAssembly builds today, and neither is callable from C:

- The browser build exports only the Go JavaScript runtime shim, and imports twenty-one functions that only `wasm_exec.js` provides.
- The WASI build is the whole command. It is driven by standard input and output, not by function calls.

A third build closes the gap. Go 1.24 added `//go:wasmexport` together with `-buildmode=c-shared` for the `wasip1` target, which produces a reactor-style module: named function exports, an `_initialize` entry point instead of `_start`, and imports limited to the standard `wasi_snapshot_preview1` set that every embeddable runtime provides.

We decided this build belongs upstream in `convert-base-v2` rather than here. Putting it here would have been faster, but the capability is useful to every caller of that project rather than only to this one, and a base-conversion export surface is a poor fit for a repository about identifiers.

The identifier core stays native Zig. Only base conversion crosses the WebAssembly boundary.

Among the runtimes considered, we decided on the Wasmtime C API: it is the reference implementation, has the best-documented C interface, and is the fastest of the options. It is also the heaviest, and it is not present on a stock system, so it is vendored rather than assumed present. The build pins a release, verifies its checksum, and links the static archive, so the binary and the shared library are self-contained; the module bytes are embedded at build time for the same reason.

An interpreter such as wasm3 would vendor far more cleanly and is the fallback if the dependency proves painful. Generating one identifier is microseconds of work either way, so this is a build-complexity decision far more than a speed one.

Two properties of that runtime shape the build:

- Wasmtime's `min` C API build is a fraction of the size but drops both the compiler and WASI support, so it can only run modules precompiled elsewhere. Usable later as a size optimization, not as the starting point.
- Startup is dominated by the module's own `_initialize` - the Go runtime building its base registry inside the wasm - not by compiling the module. Wasmtime's baseline compiler, winch, compiles far faster than cranelift but runs that initialization slower by more than it saves, so the default strategy stays cranelift.

### Which bases to offer

The help screen lists a short curated set chosen for identifiers, and `--base` accepts any base the underlying library knows.

The curated set keeps the common case obvious without walling anything off. The full registry contains bases that are actively wrong for an identifier, and a default listing that offers them invites mistakes.

Sortability turns out to be the sharpest filter, and it rules on the alphabet rather than on the size of the base. Byte-order comparison only tracks numeric order if the alphabet is itself in ascending code-point order, which several standard ones are not:

| Base | Sorts | Note
| :-- | :-- | :--
| 10 | yes |
| 16 | yes |
| 26 | yes |
| 32h, 32c, 32w | yes | base32hex, Crockford, and wordsafe all happen to be ascending
| 32r | **no** | RFC 4648 puts `A-Z` before `2-7`
| 36 | yes |
| 52 | yes |
| 62 | yes |
| 64r, 64u | **no** | RFC 4648 puts `A-Z` before `0-9`
| 64h | yes |
| `*tt`, `*tz` | yes | the wide families, built on ordered alphabets for exactly this reason

That removes the RFC base 64 variants from consideration entirely, which is the reason neither is in the curated list. Base 64 and base 62 need the same 8 characters for a timestamp, and base 62 is already URL-safe and filesystem-safe with no escaping. So base 64 cost the sort guarantee and bought nothing back at this magnitude.

Above base 62 the sensible choices are the two wide families the library carries. They are the same alphabet below 512, diverge at 512, and only `tz` continues past it - so listing both names for one radix would offer a choice that is not really a choice. The curated set takes `tt` up to 512 and `tz` above, which is where `tt` stops existing.

The curated set is therefore **16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz**, with 62 the default. Every one of them sorts.

The first four transcribe by hand. The wide ones trade that away - their digits are two to four bytes each and most are not on anybody's keyboard - and buy back length: a millisecond timestamp is 12 characters in base 16 and 5 in base 512. They are for identifiers that get copied by machines, not read aloud.

`--base` still accepts anything the library knows, including the non-sorting ones. Asking for one of those is a legitimate thing to want; getting one without asking is not.

One base is refused outright. The library carries a raw-byte mode whose 256 digits are literal byte values, and it converts as happily as any other base. An identifier made of control characters and invalid UTF-8 is not an identifier, and that base cannot hold a decimal timestamp at all, so a format mixing `%d` with anything else would only half work. Both implementations test the same thing - the base's zero digit - and refuse it before generating anything.

### Memory safety on the Zig side

Zig has no borrow checker, so memory safety is a design constraint here rather than something the language enforces. It does check bounds, overflow, null unwrap, invalid casts, and alignment in debug and safe builds, and as of 0.16 returning the address of a local is a compile error. What it does not catch on its own is use-after-free and double-free.

Among the options considered - writing an allocator, taking a third-party one, or using the standard library's - we decided the standard library's is already the strongest of the three, and that the larger win is not allocating in the first place. Four rules:

- **The identifier core takes no allocator at all.** Every component has a width fixed by the spec, so each intermediate fits a stack array and the core writes into a buffer the caller supplies. That is also the right shape for the C module, where the caller owns the buffer and there is no free contract to get wrong. A memory bug that cannot be expressed beats one that gets caught.
- **Nothing else on the Zig side allocates either.** This went further than planned. Argument handling uses the arena the process already hands to `main`, the WebAssembly runtime owns its own memory, and the C module makes exactly one allocation: the context itself.
- **`std.heap.DebugAllocator` backs that one allocation in debug builds**, `std.heap.smp_allocator` in release. It is the renamed `GeneralPurposeAllocator`, and it is what a hand-written allocator would be trying to become: leak detection with stack traces, and double-free detection that prints the allocation and both frees.
- **The tests need no allocator at all.** The vectors file is built into the test binary, so there is nothing to read and nothing to free.

Writing our own would mean reproducing all of that and then debugging it, in a project whose entire dynamic-memory need is one arena per run. The third-party options were looked at and none of them is a safety story: `zimalloc` and `zig-slab` are performance and layout work, `zig-composable-allocators` is a construction kit in the Alexandrescu style, and `andrewrk/zig-general-purpose-allocator` is the historical repo that became the standard library's. So no third-party allocator dependency.

#### What is actually detected, and what is not

The 0.16 behaviour, which is narrower than it looks:

- Leaks and double frees are caught, with full stack traces at the allocation and at both frees.
- **A use-after-free read or write is not caught.** `never_unmap` and `retain_metadata` are worth setting, but not for the reason they look like: they keep the mapping alive and the metadata around, which widens *double-free* reporting and turns a would-be segfault into a legible message. The standard library's own doc comments say exactly this. There is no page protection in the implementation, so touching freed memory silently succeeds.
- Zig 0.16 has no AddressSanitizer for Zig code - `zig build-exe` offers only `-fsanitize-c` and `-fsanitize-thread`. `zig cc -fsanitize=address` does not link either, because the ASan runtime is not included.

That gap is the strongest argument for the first rule rather than an argument against it. Since nothing will catch a dangling pointer in Zig, the defense that works is not having one: a core that never takes an allocator has no freeable pointer to dangle, and an arena has no individual free to get wrong.

For the vendored Wasmtime, which is C and allocates on its own, the sanitizer run uses the **system clang or gcc**, not `zig cc`. Both catch heap-use-after-free correctly; that stays a CI/CD step rather than a Zig-side guarantee.

One to keep an eye on, without planning around it: an accepted Zig proposal (ziglang/zig#36237) adds a Fil-C-inspired `fil` target ABI - complete memory safety with no escape hatch, at roughly a 1-6x cost. It is a target choice rather than a source change, so if it arrives it becomes a build flag. Nothing above conflicts with it.

## Identifier specification

`testdata/vectors.tsv` is generated from whatever this section says, and both implementations reproduce every row of it. Changing anything here means regenerating the vectors.

### One time encoding, not four

The predecessor offers four date/time algorithms and three precisions. Two of the four are acknowledged in its own help text as strictly worse than the others, and the combination of algorithm, precision, and base yields well over a hundred encodings that produce similar-looking output with no way to tell them apart after the fact.

Its author's own warning is the clearest statement of the problem:

> For any given use-case, you should never mix type, base, and/or precision, or the very purpose for using this tool could be obviated and you'd wind up hating life at best, or with data collisions and/or loss data at worst.

We decided on a single time encoding: **the count of time units elapsed since the Unix epoch, UTC** - the predecessor's `--dtalgo 1`. The others were rejected: packing `YYYYMMDDHHmmSS` as a decimal integer wastes roughly a third of the range on digit combinations that cannot occur, and subdividing the day to fit the base exactly is clever but makes the value impossible to reason about without the tool that produced it.

Precision, though, stays selectable - the predecessor already deliberated this at length, and its surface carries forward: **`-1` minute, `0` second (the default), `1` millisecond**. Coarser precisions truncate toward zero. The algorithm choice is what gets removed, not the precision choice; an encoding nobody can select wrongly needs no marker saying which one was used, and precision is visible in the output width anyway.

Identifiers of different precisions have different widths and therefore do not sort against each other. That is the same caveat as mixing bases, and the predecessor's warning quoted above covers it: pick one combination per use-case.

### Fixed width, because sorting depends on it

Rendering an integer in a compact base does not by itself produce something that sorts. Lexicographic comparison reads left to right, so a shorter string sorts before a longer one regardless of value, and identifiers generated years apart differ in length.

So output is **zero-padded to a fixed width**, chosen per base and precision as the width that holds any timestamp through the year 3000. The predecessor does not pad at all - its help documents the year each encoding's width grows by one character, which is exactly when its sort order breaks. Padding is what this spec fixes; year 3000 is the chosen horizon. Widths (derived in code, not tabulated):

| Base | Minute | Second | Millisecond
| :-- | --: | --: | --:
| 16 | 8 | 9 | 12
| 32 | 6 | 7 | 9
| 36 | 6 | 7 | 9
| 62 | 5 | 6 | 8
| 64 | 5 | 6 | 8
| 128 | 5 | 5 | 7
| 256 | 4 | 5 | 6
| 512 | 4 | 4 | 5
| 1024 | 3 | 4 | 5
| 2048 | 3 | 4 | 5

Width is quantized, so most of those overshoot the horizon by a wide margin. Base 62 at millisecond precision shows it: 8 characters last until 8888, and the next width down runs out in 2081. At the default second precision base 62 is 6 characters - the same length the predecessor produces today, now with the sort guarantee.

The quantization also explains why the wide bases flatten out at the bottom of the table: 1024 and 2048 need the same width at every precision, because a radix that large clears the horizon in the same number of steps. Past a point, widening the alphabet stops buying characters.

Two consequences follow:

- Sorting is byte-order sorting. It holds under `LC_COLLATE=C`, and does not hold under a locale-aware collation that ignores case, which would fold `A` and `a` together. Any base whose alphabet uses both cases has this property, and it is a property of the locale rather than of the identifier.
- Padding costs nothing today and one character eventually. At the default precision a base 62 timestamp is 6 characters, the same as the predecessor's - the width only diverges from the unpadded length once the unpadded value grows, which is precisely when unpadded output stops sorting.

### Format and components

The format string keeps the predecessor's shape, since it reads well and is the part worth carrying forward:

| Token | Component | Width in base 62
| :-- | :-- | --:
| `%d` | Time, as above. The default format is exactly this. | 6
| `%h` | Short host name, hashed by default | 8
| `%u` | User name, hashed by default | 8
| `%f` | Fully-qualified name, hashed by default | 8
| `%m` | Hardware address of the lowest-numbered non-loopback interface | 9
| `%g` | A UUID v4 | 22
| `%r` | Random data from a cryptographic source | 6
| `%%` | A literal `%`. Anything else in the format goes out as itself. | -

Every component is rendered as a number in the output base, and every one of them is a fixed number of symbols wide. Fixed width is what makes the leading timestamp sort, and it also means an identifier can be split back into its parts by offset. The single exception is an unhashed name, which is emitted as text.

Hashed components are SHA-256 of the raw name, converted from base 16, keeping the **rightmost 8 symbols** by default. Truncation is what makes them short enough to be useful; it also means they are a fingerprint rather than an identity, which is the intent. Eight base-62 symbols is around 47 bits, so a collision between two hosts is not a practical worry.

The byte-valued components all take the same path - hex in, converted from base 16 - because that is the cheapest faithful way to hand bytes to a library whose interface is strings.

- `%m` is the 48-bit address as a number. The predecessor picked the interface holding the default route, which needs the routing table on three different platforms; the lowest-numbered non-loopback interface is stable enough for a value whose only job is to differ between machines, and it needs no route parsing and no subprocess.
- `%g` is a real UUID v4 - 16 bytes from the random source with the version and variant bits forced - but rendered as the 128-bit number it is rather than in the dashed text form, which would not sort and would be four times as long.
- `%r` draws enough bytes to fill the symbols it emits. Below base 256 that is one byte each, which is more entropy than a symbol can spend; above it a symbol carries more than eight bits, so the draw scales with the radix. Details under [Component widths](#component-widths).

Padding and truncation both come from the conversion library, through one call that right-aligns a converted value to an exact symbol count. That is deliberate: the two halves of the policy - left-fill with the base's zero digit when short, keep the rightmost symbols when long - are exactly the kind of thing two implementations drift on if each writes its own. Neither does.

It also removes an earlier limit. Truncation used to need single-byte digits, because nothing could slice a converted string at a symbol boundary, so `%h`, `%u`, `%f`, and `%r` were refused in a base with multi-byte digits. The library slices by symbol now, so every component works in every base, which is what made the wide families usable as curated choices at all.

### What a caller cannot ask for

Both implementations reject the same four things before rendering anything, so neither can produce output the other would refuse:

- A component width outside 1 to 64.
- A precision that is not -1, 0, or 1.
- A base whose digits are raw bytes rather than text.
- A clock before the Unix epoch or past the padding horizon. Past the horizon is an error rather than a truncation, because quietly dropping the high symbols would break the sort instead of reporting it.

### Component widths

`%d` derives its width from the horizon. The other fixed-size components derive theirs from a bit count - 48 for a MAC, 128 for a UUID - by the same rule: the smallest number of symbols that holds the largest possible value.

| Base | `%m` (48 bits) | `%g` (128 bits)
| :-- | --: | --:
| 16 | 12 | 32
| 32 | 10 | 26
| 36 | 10 | 25
| 62 | 9 | 22
| 64 | 8 | 22
| 128 | 7 | 19
| 256 | 6 | 16
| 512 | 6 | 15
| 1024 | 5 | 13
| 2048 | 5 | 12

Hashed and random components are not derived; their width is whatever symbol count was asked for.

`%r` is the one component whose *input* depends on the base. It draws one byte per symbol, which is more entropy than a base of 256 symbols or fewer can spend. Above 256 a symbol carries more than eight bits, so a byte each would leave the leading symbols pinned at the zero digit forever; the draw is `ceil(symbols * bits / 8)` bytes there instead. The floor of one byte per symbol keeps the narrow bases drawing exactly what they always did.

### Resolved questions

Three choices were left open until the vectors froze; all three are now settled:

- **Padding horizon: year 3000.** The predecessor does not pad, so it had no horizon to inherit; 3000 was chosen as a reasonable compromise. Width is quantized so coarsely that most cells clear the horizon by centuries. The tightest are base 32 at second precision and base 32 or 512 at millisecond precision, and even those have decades of headroom, so moving the horizon changes almost nothing.
- **Precision: selectable, `-1|0|1`, defaulting to seconds.** The predecessor already worked through this trade-off, and its answer carries forward: minute, second, and millisecond, second as the default. What was dropped is the algorithm choice, not the precision choice.
- **Same-tick repeats stay literal, with a warning.** A time-only format is fully determined by the clock, so several identifiers generated within one tick come out identical - verified, not hypothetical. The format means what it says: nothing is appended silently. When the command grows the ability to emit more than one identifier per invocation, it will warn on stderr when the output contains repeats and suggest `%r`; callers wanting uniqueness say so in the format.

Four more were settled with the remaining components:

- **Hashed components are 8 symbols, uniformly.** The predecessor used 5 for host and user and 8 for the FQDN. One number is easier to remember than three, and 5 symbols in base 62 is only about 30 bits, which is thin across a large fleet.
- **Two flags rather than six.** `--no-hash` and `--hash-chars` apply to all three name components, where the predecessor had a hashing switch and a width per component. Per-component control is the kind of surface that grew by accretion there, and it is the thing this project set out to improve on.
- **`%r` defaults to 6 symbols**, not the predecessor's 4. Around 36 bits: enough that appending `%r` to a same-tick timestamp actually resolves the collision it exists to resolve.
- **`%m` takes the lowest-numbered non-loopback interface**, for the reasons under [Format and components](#format-and-components).

## Project structure

### Folder structure

```
go/
	zuid/               the Go module; module only, no command
zig/
	lib/                identifier core, WebAssembly host, C module (Apache-2.0)
		include/zuid.h  the C header
		src/
		test/           the C smoke test a system compiler builds
	cmd/                the CLI (GPL-2.0-or-later)
		src/
testdata/
	vectors.tsv         shared spec; both implementations must reproduce it
cicd/
	utility/            helper scripts the pipeline calls
	artifacts/          run logs, profiles, demo renders; rotated, not committed
project/
assets/                 the demo animation the README shows
```

### Logical code structure

Both implementations separate the same three concerns, so a change to the spec falls in matching places on each side:

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

- **Zig 0.16** for the identifier core, the command-line tool, and the C module. Its C interoperation is direct, and `zig cc` cross-compiles to every target from one machine, which removes the usual reason a C artifact is expensive to distribute. Current stable was chosen while no Zig code existed yet: 0.13 through 0.16 rewrote both the I/O and the allocator surfaces, so starting on the old one would have meant porting later for nothing.
- **Go** for the module, importing `convertbase`.
- **WebAssembly** as the bridge from Zig to base conversion.

### Configuration model

Defaults are compiled in, overridden by a per-user file, overridden by command-line options.

The per-user file is written only when a default is first changed, and lives under `~/.config`. A single bad line is skipped rather than failing the whole file. A library must never create files in a caller's home directory, so this belongs to the command alone, not to either module.

### UI

Command line only. The interface is a deliberate improvement on the predecessor rather than a port of it, which is covered under [Relationship to x9muid1](#relationship-to-x9muid1).

### Testing

`testdata/vectors.tsv` is the specification in executable form. Each row fixes the inputs - the clock, the random stream, the host, user, and FQDN names, the hardware address, and the width options - and the expected output. Both implementations run it.

Pinning all of that is what makes an identifier generator testable at all. So neither implementation reads the machine at the point of use: everything arrives through an injectable interface, and there is exactly one live implementation of that interface per side. The vectors then test *rendering*, which both sides must agree on, while acquisition is free to differ per platform - which it has to, since finding a hardware address has nothing in common between Go's portable interface list and a C library call.

Two things follow from acquisition being outside the vectors:

- The two implementations can disagree on what the live machine says. `%f` is the clearest case: one side asks the C resolver, which reads the hosts file before DNS, and the other asks DNS directly. On a host with a hosts-file domain and no DNS record they answer differently. That is accepted rather than fixed - matching two platforms' name resolution exactly is not worth what it would cost - but it means live values are per-machine, not part of the spec.
- Each source is read once per process and kept. None of them can change in a way that should change an identifier mid-run, and the reads are not cheap: walking every network interface costs far more than the base conversion it feeds, and resolving a qualified name can block on the network.

The expected column comes from a third independent derivation, working from this document rather than from either implementation, so that "both sides agree" cannot mean "both sides are wrong the same way".

## Relationship to x9muid1

`cicd/utility/x9muid1` is the 2023 bash predecessor, kept as reference. It defines the problem, not the solution.

Carried forward: the format-string idea, the component set, hashed host and user by default, and time-based sortable output.

Deliberately not carried forward: its base list, which is longer than an identifier generator needs, and its command-line surface, which grew by accretion. Improving on that interface is one of the reasons this project exists.

## Upstream dependency status

Both integration points run against a published release. Nothing is pinned to a working copy any more:

- The `convertbase` package is fetched at a tagged version, like any other dependency. The local `replace` directive that stood in while it was unreleased is gone.
- The reactor WebAssembly module is **built from that same pinned version** rather than copied in as a prebuilt artifact. That is the point: the Go side imports the library and the Zig side calls it through WebAssembly, and building both from one module version is what stops them drifting onto two. It needs a Go 1.24+ toolchain for `//go:wasmexport`; a vendored copy covers an offline build.

The two goals this architecture exists to serve - exercising the upstream Go module and the upstream WebAssembly module - are both met, and now against released artifacts rather than a neighboring directory.

## Licensing

- The command is GPL-2.0-or-later.
- Both modules are Apache-2.0, matching the library they build on, so that neither is encumbered for a caller embedding it.

This split is the same arrangement the sister project uses, and for the same reason: attribution should follow the code into somebody else's product, without reciprocity obligations that would stop anyone linking it.

## Plan

1. ~~Fix the identifier spec and write `testdata/vectors.tsv` from it.~~ Done, for the time component; the other components extend it.
2. ~~Build the Go implementation against a local checkout of `convertbase`.~~ Done.
3. ~~Upstream the reactor WebAssembly build to `convert-base-v2`.~~ Done, upstream.
4. ~~Build the Zig implementation and the C module against that.~~ Done.
5. ~~Run both against the shared vectors, and reconcile.~~ Done; both sides replay every row.
6. ~~The remaining components - host, user, FQDN, MAC, UUID, random.~~ Done, both sides, with the vectors extended to cover them.
7. Configuration, then multi-emit, then packaging.
