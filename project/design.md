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

- **Zig** for the identifier core, the command-line tool, and the C module. Its C interoperation is direct, and `zig cc` cross-compiles to every target from one machine, which removes the usual reason a C artifact is expensive to ship.
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
