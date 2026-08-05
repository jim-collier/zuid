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
