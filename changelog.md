# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
## vNEXT - DATE

### Notes

### Added

### Changed

### Removed

### Other work
-->

## v1.0.0-beta.1 - 2026-10-14

### Notes

- Second prerelease. The identifier spec hasn't changed: every vector the alpha passed still gives the same identifier.

- The alpha was built for newer CPUs than intended, and stopped with an illegal instruction on many Intel chips from before 2019. This one runs on any x86-64 CPU.

- Release file names have the version now, such as `zuid-1.0.0-beta.1-linux-x86_64.tgz`.

### Added

- Releases for Linux arm64, macOS as one universal build for Intel and Apple Silicon, Windows x86_64 and arm64, and FreeBSD x86_64.

- `--count` prints more than one identifier per run.

- `--salt` and `--salt-file` mix a secret into the hashed host, user, and FQDN names, so a name can't be confirmed by hashing guesses. The file form keeps it out of the process list.

- `--about` and `--donate`. `--version` is one line now, with a build number.

- The command keeps its compiled WebAssembly module in the user's cache dir. A run takes about a tenth of the CPU time it did.

- `install.ps1` runs under Windows PowerShell 5.1 as well as PowerShell 7, and puts zuid on `PATH`.

- Go errors can be matched with `errors.Is`, one kind per C error code.

### Changed

- The C module takes everything about an identifier per call, in a `zuid_request`. The context keeps only the runtime and a pinned clock. A NULL or freed context is the new `ZUID_ERR_CONTEXT`.

- The command, the C module, and the Go module take their error messages from one table. A few wordings changed.

- `%u` on Windows is the bare account name, in lower case.

- `%m` skips the bridge address that every Intel Mac with a T2 chip shares.

- Both installers install for the user unless told otherwise, even as root or an admin, and pick the highest version rather than the newest one listed.

- Release binaries are stripped, so they're about a third smaller.

### Removed

- `--hash-chars`. The Go and C modules still take a hash width.

- The installers' `--arch` and `-Arch`.

### Other work

- Release files are reproducible, between machines too, except the Windows exe and dll.

- The build and tests can also run in a pinned container.

- A pre-push gate on `main`.

## v1.0.0-alpha.1 - 2026-08-05

### Notes

- First prerelease. Nothing was published before it, so nothing here is a change from an earlier version.

- Alpha: the identifier spec is settled and pinned by the shared vectors, but the command-line surface may still move before 1.0.0.

- Binaries are x86_64 Linux only. The other targets need a per-platform Wasmtime archive first.

### Added

- Identifiers from a format string: time, host, user, fully-qualified name, hardware address, UUID, and random data, in any curated base.

- A command, a Go module, and a C module, from two independent implementations of one spec.

- Installer scripts for Bash and PowerShell, and Linux packages.

### Changed

### Removed

### Other work

- A shared table of test vectors that both implementations reproduce.

- A build pipeline covering lint, tests, cross-compile checks, profiling, packaging, and the demo animation.
