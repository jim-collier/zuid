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
	- 🔘 Shared test vectors (`testdata/vectors.tsv`), which both must reproduce.

- 🔘 Base conversion comes from the sister project `convert-base-v2`, not reimplemented.
	- 🔘 Go side imports `convertbase` directly. Needs a local `replace` until `lib/v0.1.0` is tagged upstream.
	- 🔘 Zig side reaches it through a reactor WebAssembly module, hosted by a vendored Wasmtime.

- 🔘 Upstream the reactor WebAssembly build to `convert-base-v2`. This gates the whole Zig and C side.

### Identifier core

- 🔘 Component set: time, host, user, MAC, UUID, random. Each independent of the others.
- 🔘 Host and user hashed by default, with an explicit opt-out.
- 🔘 Time component sortable as text once rendered.
- 🔘 Clock and random source injectable, so output is reproducible under test.

### Command-line interface

- 🔘 Format string selecting and ordering components. Improve on the predecessor's surface rather than porting it.
- 🔘 Curated base list in the help output, with `--base` accepting any base the library knows.
- 🔘 Generate more than one identifier per invocation.

### Modules

- 🔘 Go module, importable without cgo, keeping static cross-compilation.
- 🔘 C module: static and shared library plus `zuid.h`, cross-compiled with `zig cc`.
- 🔘 Both modules Apache-2.0; the command stays GPL-2.0-or-later.

### Build, CI/CD, and install

- 🔘 A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- 🔘 Has to drive two toolchains, and fail clearly when either is missing.

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

### Other

- ✅ Real README, replacing the template.
- 🔘 Create the GitHub repo and push. Does not exist yet, so nothing can be pushed.
- 🔘 Contact address in `trademark.md` is still a placeholder. Needs a real one.
- 🔘 No logo. `README.md` dropped the template's `assets/logo.png` references since there is no `assets/`.

## Backlog

### Misc to-do

- 🔘 Zig here is 0.13.0 and the current release is 0.15.x. Decide whether to move before writing much.

### Bugs

### Features and enhancements

### Done

#### Done - Initial requirements

#### Done - Bugs

#### Done - Features and enhancements

### Future and/or deferred

- ✋ Swap Wasmtime for a small interpreter such as wasm3 if vendoring proves painful. Speed is not the deciding factor.
- ✋ Hand-written bindings for other languages, if the C module turns out not to cover them.

### Canceled
