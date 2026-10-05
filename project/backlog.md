<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Project backlog

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Introduction](#introduction)
- [Issues](#issues)
- [Old format](#old-format)
	- [Bugs](#bugs)
	- [Features and enhancements](#features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - Features and enhancements](#done---features-and-enhancements)
	- [Deferred](#deferred)
	- [Canceled](#canceled)
- [Template](#template)

<!-- /TOC -->

## Introduction

Going forward, new issues in the new template at the bottom of this file, will go in the '## New format' section only. No more status emojis. Refer to '## Reference' for sort order. Issues in the old format (with status emojis) won't be refactored, but will continue to be worked until moved to closed, canceled, or deferred sections, and emojis updated. (Eventually this will all be moved to nano-git-db anyway. This new template is an intermediate effort to make issues going forward more structured and importable.)

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

Inside Done, loose items come first and code-review rounds after, each run newest first.

An item moves to its matching section under [Done](#done) once it is finished. One that is mostly done gets split: the finished part goes under Done, and the rest stays open.

Each item lists the date it was opened, and the date it was closed once finished. "n/a" means the open date is not known. A deferred item keeps only its opened date.

Notes under an item lead with what they are, such as `Cause:`, `Fixed:`, `Done:`, `Verified:` or `Note:`, so an item can be skimmed by its prefixes.

## Issues

- Windows x86_64 build, cross-built on Linux.
	- ID: 2026100416052035
	- Type: Enhancement
	- Status: Waiting for answers
	- Needs local test suite run?: Yes. `cicd.bash --package` covers it.
	- Needs external testing: Done on vm925w, 20261004.
	- Opened: 20261004-160520
	- Opened by: JC
	- Target OS: Windows 10 and later, x86_64
	- Requirements  [Feature]:
		- The command, `zuid.dll` with its import library, and the static library, built by Zig on the Linux build machine.
		- Every component works there, `%m` included.
		- The Zig tests and `capi_smoke.c` pass on a Windows test box.
	- Progress log:
		- 20261004: Split from the packaging and `%m` items under Old format. Built on the Linux machine, by direct answer 20261004. Both Windows boxes also have a mingw bash and git-bash, off PATH.
		- 20261004: Wasmtime v47.0.3 publishes an x86_64 mingw C API archive. For arm64 there is only the MSVC one.
		- 20261004: Built for `x86_64-windows-gnu` against Wasmtime's mingw archive, pinned by the digest GitHub lists for it and vendored under `--package` as `vendor/wasmtime-x86_64-windows`.
		- 20261004: The live reads go to the Win32 API on Windows: the logon name, the DNS computer name, getaddrinfo for the FQDN, the adapter list for `%m`, and the system RNG.
		- 20261004: `%m` takes the lowest-numbered adapter with a hardware address that is not loopback, numbered as Go numbers it. Go and Zig gave the same `%m` on vm925w. `%h` and `%f` matched too.
		- 20261004: `%u` does not match. Go's `user.Current` gives `VM925W\wintest` on vm925w, and the Zig side gives `wintest`. Design already lets the two sides differ on live values, and it is noted there.
		- 20261004: Question: should `%u` on Windows be the logon name alone, as now, or `DOMAIN\name`, as Go's is? Either side can change to match.
		- 20261004: The DLL also exports four debugger hooks from Wasmtime's own objects, beside the `zuid_*` functions. Those objects mark them for export, and a DLL has no map to hide them. Nothing can displace them, since Windows binds a DLL's own calls inside it. Removing them would mean editing the pinned archive.
		- 20261004: The `--package` check builds into scratch, not `dist/`. The packaging item can point it at the zip.
		- 20261004: MSVC links the DLL through `zuid.lib` and runs. It cannot link `libzuid.a`, which is a mingw archive.
	- Decisions:
		- Names: `zuid.exe`, `zuid.dll`, its import library `zuid.lib`, and the static library `libzuid.a`. Zig calls both libraries `zuid.lib`, so the static one takes mingw's name, since only mingw can link it.
		- The DLL's PDB is not installed, since the command's has the same name.
	- Verified: on vm925w, the cross-built command with `--no-hash -f '%d %h %u %f %m %g %r'`, hashed, the default and `-n 3`. All 30 Zig tests from `zig build test-bin`. `capi_smoke.c` with mingw gcc 16.1 against the DLL and, with the line `zuid.h` gives, against `libzuid.a`, run from a folder with no DLL; MSVC 2022 against the DLL. `capi_interpose.c` with both against the DLL. On Linux, the full pipeline and one with `--package`, which fetched and checked the new pin.
	- Swept: the `%m` notes in the help text, `zuid.h` and design.md. `package.bash`'s note on Windows. `wasmtimeDir` in `build.zig` and `fWasmtimeArchive` in `package.bash` both find `vendor/wasmtime-x86_64-windows`.
	- Branch: winbuild
	- Commit: 8ee3066
	- Test case: ErmM9mS to ErmM9mV under `--package` on Linux: the build and what it is, the DLL's exports, and `capi_smoke.c` linking against each library. Each failed with its fault planted: no Windows headers, the Wasmtime hooks not allowed, `-liphlpapi` dropped, and the static link pointed at the import library. ElpGOHX, the live environment test, passed on vm925w.

- A build with `SOURCE_DATE_EPOCH` empty fails when Zig's global cache is cold.
	- ID: 2026100415475381
	- Type: Bug
	- Status: Waiting on signoff
	- Priority|Severity [Bug]: Avg
	- Opened: 20261004-154753
	- Opened by: JC
	- Related IDs: 2026100318410002, 2026100313583935, 2026093018112445
	- Target OS: Any
	- Steps to reproduce [Bug]:
		- In `zig/`: `SOURCE_DATE_EPOCH= ZIG_GLOBAL_CACHE_DIR=<new dir> zig build --cache-dir <new dir>`, with Zig 0.17.0.
	- Incorrect behavior [Bug]: The build fails. Zig's own libunwind build passes the empty value to clang, which refuses it.
	- Expected behavior [Bug]: The build finishes and takes the commit date, as it does with a warm global cache.
	- Reproduced [Bug]: Yes, 20261004 on Linux, on `main` and on branch `machang`.
	- Possible cause [Bug]: Since 0.17, `build.zig` cannot clear the variable for the compile steps, only for Run steps. `Eq9nb3o` misses it, since it gives the build a fresh local cache but keeps the warm global one.
	- Actual cause [Bug]: Upstream behavior, not this repo. Zig 0.17.0 runs clang with its own environment when it builds libunwind and libc into the global cache, and clang refuses an empty or non-numeric value. A cached copy never runs clang, and the value is not part of the cache key. zuid has no C sources of its own, so these are the only places clang runs.
	- Progress log:
		- 20261004: Reproduced on Linux: the build failed on `UnwindRegistersSave.S` and `UnwindRegistersRestore.S`, plus clang notes from the C files with no file name. With nothing set, the same cold build took 2 min 28 s. An empty program linking libc and libunwind fails the same way, in 4 s.
		- 20261004: Read in 0.17.0's `src/Compilation.zig`: `evalZigLlvmProcess` spawns `zig clang` with no environment of its own, and the Maker spawns compile steps with its own environment too. Outside Debug, Zig passes `-Werror=date-time`, so the value cannot change those libraries.
		- 20261004: No report found on Codeberg or the old GitHub tracker. Draft, not filed: "Zig's own libunwind and libc builds fail with an empty SOURCE_DATE_EPOCH on a cold global cache. `SOURCE_DATE_EPOCH= zig build-exe a.zig -lc -lunwind` with a new `ZIG_GLOBAL_CACHE_DIR` fails with clang's 'must be a non-negative decimal integer' error; with a warm cache it works. Whether a build passes depends on cache state. The variable is not in those libraries' cache keys, and `-Werror=date-time` keeps it from changing them outside Debug. Suggest not passing it to these sub-builds, or dropping an invalid one."
		- 20261004: `Eq9nb3o` stays on the warm global cache. A direct `zig build` with the value empty fails cold whatever this repo does, so a cold `Eq9nb3o` could never pass. A cold run through the scripts would add about 2.5 min, mostly rebuilding Zig's build runner; Zig's own libc, libunwind and compiler_rt take about 8 s of that.
	- Actual fix [Bug]: `cicd.bash`, in preflight, and `package.bash` drop an empty or non-numeric value before running zig, with a note for a non-numeric one, the same as `build.zig` treats it. The README says to unset it for a plain `zig build`.
	- Verified: a full `cicd.bash --no-dogfood --no-backup -q` run with the value empty and a new global cache passed, in 6 min 13 s. The same in a clone of `main`, with `--only zig --quick`, failed in the first Zig build with clang's error.
	- Swept: every `zig` call in `cicd.bash` runs after preflight; `package.bash` is the other script that runs zig, and the harnesses run only stand-in zigs. `install.bash` and `install.ps1` do not build.
	- Branch: emptyepoch
	- Commit: e8f7545
	- Test case: new `ErmER3z` and `ErmER40` in `pipeline-test.bash` check that `cicd.bash` and `package.bash` keep an empty, blank or non-numeric value from zig, and keep a number. Both failed on the old scripts and pass now.

- FreeBSD x86_64 release.
	- ID: 2026100413383571
	- Type: Enhancement
	- Status: Waiting on signoff
	- Needs local test suite run?: Yes. `cicd.bash --package` covers it.
	- Needs external testing: Yes, on `vmFreeBSD`.
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261004-133835
	- Opened by: JC
	- Related IDs: 2026100315241091, 2026100413383471
	- Target OS: FreeBSD 14 and later, x86_64
	- Requirements  [Feature]:
		- A FreeBSD x86_64 tarball and bare binary, cross-built on Linux beside the Linux ones.
		- Wasmtime from FreeBSD's own package, pinned by checksum, since Wasmtime publishes no FreeBSD build.
		- `%m` works there.
		- `install.bash` installs it on FreeBSD, and refuses FreeBSD arm64 and other BSDs by name.
		- `--publish` wants it in the release set.
	- Progress log:
		- 20261004: Reverses 2026100315241091. FreeBSD packages Wasmtime's C library as `libwasmtime`, which that item did not know.
		- 20261004: The pins are `libwasmtime-45.0.0_1` and `zstd-1.5.7_2` from the FreeBSD 14 quarterly repo. FreeBSD's build of Wasmtime calls zstd, so its `libzstd.a` is linked too and ships in the tarball with zstd's BSD license.
		- 20261004: `%m` reads AF_LINK as on macOS. Two lines.
		- 20261004: On `vmFreeBSD`: the tarball's command, every component including `%m`, the 30 Zig tests, and `capi_smoke.c` with the base `cc` against both libraries all pass. `cli-test.bash` panicked the kernel once; see 2026100413383471.
		- 20261004: On `vmFreeBSD`: `cli-test.bash` against the tarball's command passed 69 of 69, 40 times over.
		- 20261004: `pipeline-test.bash` case ErkRrml failed about half the time, before this work too. Its fixture ID came from the clock, and the stray scan skips a word with no digit or capital past its first letter. It now uses a fixed time.
	- Decisions:
		- FreeBSD 14 as the floor, to match the package repo.
		- Wasmtime stays, rather than an interpreter for this one platform.
		- x86_64 only.
	- Branch: freebsd
	- Test case: ErlUUiQ to ErlUUiU under `--package` on Linux: an x86_64 FreeBSD build with zstd and its license, no AVX, no libc past FreeBSD 14, and the two links. Each failed on a release broken for it: no zstd license, a Linux binary, an AVX build, a FreeBSD 15 build, and a static and a shared library with no `zuid_*`. ErlUUiV, ErlUUiW, ErlUUiX and ErlX0RL in `installer-test.bash`, with a stand-in `uname`; the first three failed on the old `install.bash`. Ergbz3Z now uses OpenBSD.

- `cicd.bash` refuses to run in a git worktree.
	- ID: 2026100318410007
	- Type: Bug
	- Status: Waiting on signoff
	- Priority|Severity [Bug]: Low
	- Opened: 20261003-184100
	- Opened by: JC
	- Target OS: Any
	- Steps to reproduce [Bug]:
		- `git worktree add <dir> main`, then run `cicd/cicd.bash` there.
	- Incorrect behavior [Bug]: It stops at once with "Not a git repo".
	- Expected behavior [Bug]: It runs, since a worktree is a full checkout.
	- Reproduced [Bug]: Yes, 20261003.
	- Possible cause [Bug]: The sync and preflight checks look for a `.git` directory, and in a worktree `.git` is a file.
	- Actual cause [Bug]: As above. Both checks tested for a `.git` directory.
	- Progress log:
		- 20261004: The backup stage is skipped in a linked worktree, with a line saying so, and `--backup` asked for by name is refused there. The helper archives the folder above the checkout, which for a worktree is not the project, and it wants a real `.git` directory. Making the backup work from a worktree would mean archiving the main checkout's project instead, which is a bigger change than this item.
		- 20261004: Verified: `cicd.bash --quick --no-dogfood -q` from a scratch worktree passed, with the backup skipped. `--backup` there was refused before any stage. `pipeline-test.bash` 39 of 39, `test-ids.py check` and shellcheck pass.
	- Decisions:
		- Skip the backup in a worktree rather than make it work there. Open to a different call.
	- Actual fix [Bug]: Sync and preflight ask git whether the folder is the top of a checkout. Argument handling spots a linked worktree by its git dir differing from the common one.
	- Swept: every `.git` path test in `cicd/` and the rest of the repo. `package.bash` and the test harnesses had none. The vendored `n8git_backup-and-publish` tests `.git/HEAD` and stays as is, since `cicd.bash` no longer calls it from a worktree.
	- Branch: worktree
	- Commit: 9ff63b7
	- Test case: Erm7vCh, Erm7vCi, Erm7vCk and Erm7vCl in `pipeline-test.bash`, which all failed before the fix. Erm7vCj checks a folder that is not a checkout's top is still refused.

- When creating a release, use a table to group downloads.
	- ID: 2026100409432309
	- Type: Feature
	- Status: Waiting on signoff
	- Opened: 20261004-094323
	- Opened by: JC
	- Target OS: Any
	- Requirements  [Feature]:
		- CPU architecture in columns, and target OS in rows.
	- Progress log:
		- 20261004: `--publish` adds a "Downloads" table to the notes. Rows are Linux, macOS, Windows, FreeBSD; columns are x86_64 and arm64. Each cell links every file for that pair: tarball or zip, bare binary, `.deb`, `.rpm`. A cell with no file shows `-`.
		- A file the table cannot place, such as another CPU or no OS in its name, is linked in a line under the table. `checksums.txt` is linked after that.
		- The links need the repo's address, which comes from `gh repo view`. The preflight refuses if gh cannot name the repo, so no tag is pushed for a release that would fail anyway.
		- Verified: `pipeline-test.bash` 44 passed, `test-ids.py check`, shellcheck. A sample passed through GitHub's markdown renderer kept the spanned cell.
	- Decisions:
		- 20261004: the macOS universal file spans both architecture columns. A markdown table cannot span cells, so the release notes need an HTML table for this.
		- 20261004: the table goes after the changelog section, under its own "Downloads" heading. What changed reads first, and GitHub lists the assets at the bottom of the page anyway. With no changelog section the notes are the table alone, where before they were empty.
		- 20261004: every row shows even with no files, as dashes, so the layout is the same in every release.
	- Branch: dl-table
	- Commit: de03ae4
	- Test case: `pipeline-test.bash` Erm9fTp (rows and columns), Erm9fTq (spanned macOS cell), Erm9fTr (missing target), Erm9fTs (changelog, table, then checksums.txt), ErmAuec (refusal when gh cannot name the repo). All failed before the change.

- Windows release packages, x86_64 and arm64.
	- ID: 2026100416052036
	- Type: Enhancement
	- Status: Waiting on signoff
	- Needs local test suite run?: Done. `cicd.bash --package --no-dogfood --no-backup -q` passed, 20261004.
	- Needs external testing: Yes, on vm925w or b29w. The x86_64 zip and `install.ps1` passed on vm925w, 20261004. The arm64 release has had static checks only, since there is no arm64 Windows machine: `zuid.exe`, `zuid.dll` and `capi_smoke.c` still need a run on one. A system install from an elevated shell was not run either.
	- Opened: 20261004-160520
	- Opened by: JC
	- Prereq IDs: 2026100416052035
	- Target OS: Windows 10 and later, x86_64 and arm64
	- Requirements  [Feature]:
		- `zuid-windows-x86_64.zip` and `zuid-windows-arm64.zip` from `--package` on Linux, with their bare `.exe` files.
		- `install.ps1` installs them.
		- The release checks run on them, as on the other targets.
	- Progress log:
		- 20261004: Split from the packaging item under Old format. Windows ships as a `.zip` for `install.ps1`.
		- 20261004: arm64 has only Wasmtime's MSVC archive. Its `wasmtime.dll` may link from a mingw build, since a DLL's C interface does not depend on the toolchain. Untested.
		- 20261004: arm64 links `wasmtime.dll` through its import library, and the zip has the DLL in `bin/`. That DLL imports only Windows' own DLLs, with no Visual C++ runtime, so a stock Windows 10 or 11 has everything it needs. Wasmtime's static MSVC archive does not link from mingw, since it asks for MSVC's own C runtime.
		- 20261004: `--package` on Linux now builds both zips and the bare x86_64 `.exe`. The zips are laid out like the tarballs, plus Wasmtime's license. The checks that built Windows into scratch now read the zips in `dist/`.
		- 20261004: Packaging also stopped staging every release on one CPU in one folder. The Windows zip would have taken in the Linux files. FreeBSD only escaped it because its file names match Linux's.
		- 20261004: `install.ps1` is meant for PowerShell 7, as the README says. Under Windows PowerShell 5.1 it used to stop with "The variable '$IsWindows' cannot be retrieved". It now says it needs PowerShell 7 and stops before doing anything.
		- 20261004: `install.ps1` and `run-latest.ps1` were not ASCII, from the copyright line and the section rules. They are now, with the copyright written without the ID, and a docs check keeps every `.ps1` that way.
		- 20261004: The Linux, macOS and FreeBSD tarballs have `libwasmtime.a` without Wasmtime's license. Logged as 2026100417324819.
	- Decisions:
		- 20261004, open to change: no bare `.exe` for arm64, since it cannot run without `wasmtime.dll` beside it. The requirement asked for one per target.
		- 20261004, open to change: arm64's import library for `wasmtime.dll` goes in as `lib/wasmtime.lib`, the name `-lwasmtime` finds with mingw's ld, lld and Zig alike. Wasmtime's own `wasmtime.dll.lib` name is found by none of them.
		- 20261004, open to change: `bin/zuid.pdb` is in both zips, as the build installs it, since Zig reads it for a stack trace.
	- Verified: on vm925w with pwsh 7.6.6, against a local release: `install.ps1` picked the x86_64 zip, checked it and installed it to the user location, and the installed `zuid.exe` ran. A second run said it was already installed and downloaded nothing, and `-Uninstall` removed it. The README's one-line form did the same. `-Arch arm64` installed the arm64 zip with `wasmtime.dll` beside `zuid.exe`. With Program Files not writable, the default was the user location and `-Target system` was refused before any download. Under Windows PowerShell 5.1, both the `-File` and the README form stopped with the new message and installed nothing. Every script parsed first. On Linux: the full pipeline with `--package`, which fetched and checked the new pin, `installer-test.bash`, `pipeline-test.bash`, `test-ids.py check` and shellcheck.
	- Swept: `fPublish_Downloads` already places `zuid-windows-x86_64.exe` in the Windows x86_64 cell after its zip; its table test now has one. Every `.ps1` in the repo. `build.zig` and `package.bash` pick the arm64 library the same way. The help text and comments that said Windows files come from `dist-incoming/`. The `zuid.h` link notes and design.md.
	- Branch: winpkg
	- Commit: 0263572
	- Test case: ErmM9mS to ErmM9mV now read the x86_64 zip. New: ErmS0zB, no AVX in code built here, read through the PDB; ErmS0zC and ErmS0zD, every DLL loaded is Windows' own or in the zip, and every function asked of one in the zip is exported; ErmS0zE to ErmS0zH, the arm64 zip's files and machine type, `zuid.dll`'s exports, and `capi_smoke.c` linking against both libraries; ErmS0zI, every `.ps1` is ASCII. Each failed with its fault planted: a missing license, a missing or extra bare `.exe`, a stand-in `wasmtime.dll`, Wasmtime's DLL as `zuid.dll`, x86_64 libraries in the arm64 zip, an x86_64_v3 build, `ws2_32` dropped from the allowed list, and the old `install.ps1` or a byte-order mark. Erm9fTp, the download table, failed with the `.exe` ranked ahead of the zip. The Windows install run is by hand and has no ID.

- The macOS build hangs on Zig 0.17.0.
	- ID: 2026100318410002
	- Type: Bug
	- Status: Waiting for testing
	- Needs local test suite run?: No. A full `cicd.bash --no-dogfood --no-backup --cross -q` passed on Linux with the fix.
	- Needs external testing: Yes. The full pipeline run on b26, batched with 2026100313583935 and the Zig fuzz item.
	- Priority|Severity [Bug]: High
	- Opened: 20261003-184100
	- Opened by: JC
	- Related IDs: 2026100313583935, 2026100415475381
	- Target OS: macOS
	- Steps to reproduce [Bug]:
		- On b26, run `cicd.bash` with Zig 0.17.0.
		- Or by hand: `zig translate-c -lc <any header> | wc -c`.
	- Incorrect behavior [Bug]: The Zig stage never ends. The three header steps sit at full CPU.
	- Expected behavior [Bug]: The build finishes, as it does on Linux.
	- Reproduced [Bug]: Yes, on b26, 20261003. Even a one-line header hangs when the output goes to a pipe. The same command writing to a file finishes at once.
	- Possible cause [Bug]: Zig copies its output to stdout with `fcopyfile`, which fails on a pipe there, and Zig retries forever. The header step reads stdout through a pipe. No upstream report found.
	- Progress log:
		- 20261003: Untested idea: have the step write to its output file through `sh -c`, so Zig never writes to a pipe.
		- 20261004: Reproduced again on b26: piped, a one-line header gave no output in 20 s; to a file it finished at once. `zig translate-c` has no output file option, so the step cannot just name one.
		- 20261004: Not `sh -c`, since a native Windows build has no `sh`. A small Zig helper does the redirect on every host instead.
		- 20261004: Found along the way: `Eq9nb3o` could not see the header step at all. The translator kept its own cache beside `build.zig`, so the test's fresh cache still got a warm translation. Fixed here, since the test pins what this step must keep.
		- 20261004: Also found: a cold global cache fails the empty `SOURCE_DATE_EPOCH` build anyway, in Zig's own libunwind build. Same on `main`. Logged as 2026100415475381.
	- Actual cause [Bug]: `zig translate-c` copies its cached result to stdout with `fcopyfile` on macOS. Read in Zig's source, not traced: an error that is not "unsupported" makes the copy report zero bytes, and the caller asks again forever. Linux takes another path.
	- Actual fix [Bug]: The three header steps run `zig translate-c` through `zig/tools/to_file.zig`, which gives it a file for stdout. Still a Run step, so it still drops `SOURCE_DATE_EPOCH`. The translator now gets the build's cache directory too.
	- Verified: on b26, a fresh-cache build finished in about 23 s, a fresh-cache build with `SOURCE_DATE_EPOCH` empty finished too, and all 30 Zig tests passed. That copy had no git history, so it had no build number to check. On Linux, the translated headers match `zig translate-c` byte for byte, the arm64 Linux and FreeBSD cross builds work, a no-op rebuild takes under a tenth of a second, and the full pipeline passes.
	- Swept: `captureStdOut` and `addSystemCommand` in `build.zig`, and every `zig` call in the scripts. The header steps were the only place Zig wrote a file to a pipe. `cicd.bash`'s `zig fmt` check now covers `zig/tools`.
	- Branch: machang
	- Commit: 47c1134
	- Test case: new `Erm4m6a` fails if `build.zig` captures a command's stdout. It fails on the old `build.zig` and passes now. A Linux build cannot hang, so the hang itself waits on the b26 run. `Eq9nb3o` now fails when the step stops dropping `SOURCE_DATE_EPOCH`; before the cache fix it passed either way.

- FreeBSD kernel panics while zuid runs.
	- ID: 2026100413383471
	- Type: Bug
	- Status: Can't reproduce
	- Needs external testing: Yes, on `vmFreeBSD`.
	- Priority [Feature|Enhancement] | Severity [Bug]: High
	- Opened: 20261004-133835
	- Opened by: JC
	- Parent ID: 2026100413383571
	- Target OS: FreeBSD 15.1, x86_64
	- Test environment: `vmFreeBSD`, 8 CPUs, 8 GB.
	- Version and build: 1.0.0-alpha.1 (build ddg8r), from the `freebsd` branch.
	- Steps to reproduce [Bug]:
		- Run `cli-test.bash --bin <tarball>/bin/zuid` on the VM.
	- Incorrect behavior [Bug]: The kernel panicked about two minutes in: "Fatal trap 12: page fault while in kernel mode", current process zuid. The backtrace runs from a user page fault through `vm_fault` and `vm_page_activate` into `vm_page_pqstate_commit`.
	- Expected behavior [Bug]: No program can panic the kernel. At worst zuid crashes.
	- Reproduced [Bug]: No. It happened once, 20261004, and the test log was lost in the reboot. 40 more runs of `cli-test.bash` did not bring it back: 16 one after another, and 24 four at a time with the Zig tests between them, with every zuid call logged to disk.
	- Possible cause [Bug]: A FreeBSD kernel bug in its page-queue code, reached by Wasmtime's large memory reservations and guard pages. A program cannot cause a kernel page fault by itself. FreeBSD has a page-queue race of the same kind open on powerpc64le under heavy load, bug 296767; not shown to be the same one.
	- Progress log:
		- 20261004: The crash dump is `/var/crash/vmcore.0` on the VM.
		- 20261004: Before it, the tarball's command, the 30 Zig tests and the C smoke test, static and shared, all passed there.
		- 20261004: The 40 runs above passed, 69 of 69 each, and the 24 Zig test runs passed.
	- Decisions:
		- Not a reason to hold the FreeBSD release, since zuid cannot cause or fix a kernel fault. Reopen if it comes back.
	- Branch: freebsd

- Update vmFreeBSD's kernel and every package, then retry the panic.
	- ID: 2026100415162238
	- Type: Task
	- Status: Queued
	- Needs external testing: Yes, on `vmFreeBSD`.
	- Priority [Feature|Enhancement] | Severity [Bug]: Avg
	- Opened: 20261004-151622
	- Opened by: JC
	- Parent ID: 2026100413383471
	- Target OS: FreeBSD 15.1, x86_64
	- Requirements  [Feature]:
		- Update the base system and kernel with FreeBSD's own updater, and every package with `pkg upgrade`. Reboot.
		- Rerun `cli-test.bash` against the release on the VM, logged to disk as before, to see whether the panic still shows up.

- The Linux, macOS and FreeBSD tarballs have `libwasmtime.a` without Wasmtime's license.
	- ID: 2026100417324819
	- Type: Bug
	- Status: Waiting for testing
	- Needs local test suite run?: No. A full `cicd.bash --package --no-dogfood --no-backup -q` passed on Linux with the fix.
	- Needs external testing: Yes. A `--package` run on b26, for the macOS tarball and ErmYT8R. Batch it with the other b26 items.
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-173248
	- Opened by: JC
	- Related IDs: 2026100416052036
	- Steps to reproduce [Bug]:
		- List any `.tgz` from `--package`.
	- Incorrect behavior [Bug]:
		- `lib/libwasmtime.a` is there, and nothing in `share/` is Wasmtime's Apache-2.0 license, which has to go along with a copy of it.
	- Expected behavior [Bug]:
		- `share/LICENSE-wasmtime.txt`, as the Windows zips have. FreeBSD's vendored package keeps no license file yet, so that fetch needs one too.
	- Reproduced [Bug]: 20261004, on the Linux tarballs, `.deb` and `.rpm` from `main`. The command links Wasmtime in statically, so the packages lacked it too, and they also lacked the module's Apache license and NOTICE.
	- Actual cause [Bug]:
		- `package.bash` copied Wasmtime's license only for the Windows zips. The FreeBSD fetch kept zstd's license and not Wasmtime's.
	- Actual fix [Bug]:
		- Every tarball and zip gets `share/LICENSE-wasmtime.txt`, from `LICENSE` in the vendored Wasmtime tree. Linux, macOS and Windows take it from Wasmtime's own pinned archive. FreeBSD's `libwasmtime` package keeps it as `share/licenses/libwasmtime-*/APACHE20`, which is Wasmtime's `LICENSE` word for word, and the fetch now copies it in as `LICENSE`. A FreeBSD tree vendored before this has no `LICENSE`, so it is fetched again.
		- The `.deb` and `.rpm` also get `LICENSE-wasmtime.txt`, `LICENSE-module.txt` and `NOTICE.txt`, beside the GPL text they had.
		- Note: the bare binaries still go out with no license file beside them, as before.
	- Verified: the full `--package` run above. The FreeBSD fetch ran again and its `LICENSE` matches Wasmtime's own. Both macOS archives at the pinned checksums have the same `LICENSE`. Every new check failed against the release built from `main`, and the tarball check failed with the module's license in place of Wasmtime's.
	- Swept: every tarball, both zips, both `.deb` and both `.rpm`. The Windows check now reads for the text only Wasmtime's license has, as the new checks do. `install.bash` and `install.ps1` install the whole tree, so nothing changes there. The macOS tarball change is only read, not run.
	- Branch: wtlicense
	- Commit: 2dd0931
	- Test case: ErmYT8O to ErmYT8V, one per release: the Linux x86_64 and arm64, FreeBSD and macOS tarballs, and each `.deb` and `.rpm`. Each Linux one failed on `main`'s release and passes now. ErmYT8R runs only on a Mac and has not run.

- Move the Zig side to 0.17.0.
	- ID: 2026100313583935
	- Type: Task
	- Status: Queued
	- Needs external testing: on b26, install Zig 0.17.0 beside 0.16.0 as `~/.local/zig-x86_64-macos-0.17.0`, checked against the download index, and run the pipeline with `--package`. That builds the arm64 macOS slice of the universal release, which has only been cross-compiled so far.
	- Opened: 20261003-135839
	- Opened by: JC
	- Prereq IDs: 2026100318410002
	- Target OS: Any
	- Estimated effort: Low
	- Decision: Move to 0.17.0.
		- The pipeline finds its own Zig: `ZIG` if set, else the `zig` on PATH if it is new enough, else `~/.local/zig-<platform>-0.17.0/zig`. Whichever it picks goes first on PATH, so the packaging script and the test scripts use it too. The shared `zig` link stays on 0.16.0 for the other projects.
		- The C headers are translated with Zig's own `translate-c`, not the separate package, so an offline build needs nothing fetched.
		- `DebugAllocator` stays for now. It still builds on 0.17.0.
	- Progress log:
		- 20261003: Zig 0.17.0 came out 2026-10-01. A trial port builds, passes all 30 Zig tests, and the C module still works from gcc. It took small changes in seven files plus three short C headers. `details.md` has the list.
		- 20261003: The Zig fuzz item under Old format waits on this. Fuzz mode works in 0.17.0.
		- 20261003: Other projects on the build machine still pin 0.16.0, so the two versions have to sit side by side there. b26 needs 0.17.0 too.
		- 20261003: Question: go ahead? 0.16.0 is a settled choice, so the move needs a yes first. Answered yes, 20261003.
		- 20261003: Done on branch `zig017`. Ported as the trial did, and 0.17.0 is installed beside 0.16.0 on the build machine.
		- 20261003: An empty `SOURCE_DATE_EPOCH` broke the build on 0.17.0, and the existing test for it caught that. The build script can no longer clear the variable for the header step, so that step now runs as a plain command with it removed.
		- 20261003: Question: move to `SafeAllocator`? Zig 0.17.0 deprecates `DebugAllocator` in its favor, but it is a different allocator, not a rename. It catches more, so the memory-safety section in `design.md` would need rewriting, and the leak test would need another way to count. Kept as is until then.
		- 20261004: Answer: either way. `DebugAllocator` stays. It is unchanged in 0.17.0, and `SafeAllocator` counts leaks only by tearing itself down, which the leak test cannot use. Revisit when a Zig release removes it.
		- 20261003: The ReleaseSafe test run fails the leaked-context test, on 0.16.0 as well. The pipeline tests in Debug, so it only matters to the fuzz item.
		- 20261003: The b26 run failed. The Zig build hangs on macOS, so nothing past the Go stages ran there. Back to Queued until 2026100318410002 is fixed. 0.17.0 is installed on b26 now, checked against the download index.
	- Verified: a full pipeline run (`cicd.bash --no-dogfood --no-backup`) and one with `--cross` both passed on Linux, with no test skipped. A ReleaseSafe build runs. A release package for glibc 2.28 builds. Both macOS slices cross-compile and link. A no-op rebuild takes under a tenth of a second.
	- Swept: every `@cImport`, array `**`, upper-case optimize tag and `build_root` in `zig/`, and every Zig version mention outside the backlog. `cicd.bash` and `package.bash` are the only scripts that run `zig`, and both get the one the pipeline picked.
	- Branch: zig017
	- Commit: 161affa
	- Test case: the existing suites, with no new test. `Eq9nb3o`, the empty `SOURCE_DATE_EPOCH` build, failed on the first port and passes now.

- When a shcl upgrade breaks compatibility with the application config file(s).
	- ID: 2026100313105246
	- Type: Feature
	- Status: Queued
	- Opened: 20261003-131052
	- Opened by: JC
	- Target OS: Any
	- Requirements  [Feature]:
		- Check if the new shcl version has breaking changes. If so:
			- Rename the latest config file `[origname]_backup_YYYYmmDD-HHMMSS_format-v[shcl version].shcl`.
			- Write a new config file with the same previous path and name, from scratch through shcl, using whatever settings and conversions shcl can handle.
		- FYI future versions of shcl might do the config backup and conversion for you. So just be careful not to race, conflict, or trample what shcl might try to do. (And first, while wiring up a new version of shcl in code, see if it has a new API to do or at least assist with the conversion for you.)
	- Progress log:
		- 20261003: waits on the config file item under Old format, which waits on shcl v3. shcl v3 is not cut yet.

- Write a test as part of CICD that creates old shcl file versions for settings, and tests the automatic (non-shcl-assisted) conversion.
	- ID: 2026100313105251
	- Type: Task
	- Status: Queued
	- Opened: 20261003-131052
	- Opened by: JC
	- Parent ID: 2026100313105246
	- Target OS: Any
	- Progress log:
		- 20261003: waits on its parent.

- Release builds target the build machine's CPU.
	- ID: 2026093018112406
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: Any
	- Steps to reproduce [Bug]:
		- `package.bash` runs `zig build` with no `-Dtarget` or `-Dcpu`.
	- Incorrect behavior [Bug]: Zig then builds for the host CPU, so a release binary can use instructions an older x86_64 lacks. On macOS it also targets the host's exact OS version.
	- Expected behavior [Bug]: A baseline CPU, and a stated minimum macOS.
	- Reproduced [Bug]: Yes. A Linux release used AVX in about 190 functions and needed glibc 2.36. A macOS one used AVX and asked for 15.8.
	- Actual cause [Bug]:
		- With no target named, Zig builds for the machine it runs on, glibc included.
	- Decisions:
		- Baseline CPU. The code built here is too small to gain from newer instructions, and Wasmtime checks the CPU itself.
	- Actual fix [Bug]: `package.bash` names a target: glibc 2.28 on Linux, macOS 13.0 on a Mac, both with the baseline CPU. It now builds the macOS tarball and binary on a Mac too.
	- Branch: baseline
	- Commit: 668b432
	- Test case: `ErbFB7B`, `ErbFB7C`, `ErbFB7D`, run with `--package`. Each watched to fail on a build for the host.
	- Closed: 20261002-194500

- `%m` is the same on every Intel Mac with a T2 chip.
	- ID: 2026093018112392
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: High
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: macOS, Intel with a T2 chip
	- Steps to reproduce [Bug]:
		- Run `zuid --no-hash -b 16 -f %m`.
	- Incorrect behavior [Bug]: `ACDE48001122`. That is the T2 bridge interface, `en5`, and every T2 Mac has that address on it.
	- Expected behavior [Bug]: An address that differs between hosts.
	- Reproduced [Bug]: Yes, on macOS 15.8. Go and Zig agree.
	- Actual cause [Bug]:
		- The lowest-numbered interface wins, and `en5` comes before `en0` there.
	- Decisions:
		- Skip that one address on both sides. The lowest-numbered rule stays.
	- Actual fix [Bug]: Both sides skip `ac:de:48:00:11:22`. On the test Mac `%m` is now `ap1`'s address, index 5, which is ahead of `en0`. Both sides agree.
	- Branch: t2mac
	- Commit: 91411c1
	- Test case: `ErU3R79`, `ErU3R7A`. Both watched to fail without the skip.
	- Closed: 20261001-135500

- `install.bash` chose a system install on a Homebrew Mac, and asked for root.
	- ID: 2026093018112432
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: macOS, Intel with Homebrew
	- Steps to reproduce [Bug]:
		- Run `install.bash` with no `--target`, as a user who can write `/usr/local/bin` but not `/opt`.
	- Incorrect behavior [Bug]: It plans `/opt/zuid` and reaches for sudo.
	- Expected behavior [Bug]: A user install, since the system location cannot be written.
	- Reproduced [Bug]: Yes, by `Eq9l4yO` once it stopped skipping there.
	- Actual cause [Bug]:
		- Only the link's directory was checked. `install.ps1` already checked both.
	- Actual fix [Bug]: Both have to be writable, as in `install.ps1`.
	- Branch: macos
	- Commit: 277947e
	- Test case: `Eq9l4yO`. It used to skip wherever `/usr/local/bin` was writable.
	- Closed: 20260930-181124

- A clean build failed with `SOURCE_DATE_EPOCH` set but empty.
	- ID: 2026093018112445
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: Any
	- Steps to reproduce [Bug]:
		- `SOURCE_DATE_EPOCH= zig build` with an empty cache.
	- Incorrect behavior [Bug]: Clang refuses the empty value and every `@cImport` fails.
	- Expected behavior [Bug]: The build falls back to the commit date, which `build.zig` already meant to do.
	- Reproduced [Bug]: Yes, on Linux and macOS.
	- Actual cause [Bug]:
		- `build.zig` ignored the value for its own stamp but left it set for the compiler. A warm cache never runs clang, so `Eq9nb3o` passed anyway.
	- Actual fix [Bug]: `build.zig` drops an empty or non-numeric value before anything compiles.
	- Branch: macos
	- Commit: 277947e
	- Test case: `Eq9nb3o`, now on its own cache. Watched to fail without the fix.
	- Closed: 20260930-181124

- With no `shellcheck`, the pipeline skipped four more stages.
	- ID: 2026093018112458
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: Any
	- Incorrect behavior [Bug]: Test IDs, the pipeline tests, the installer tests and the docs check never ran, with only "shellcheck not installed" to show for it.
	- Expected behavior [Bug]: Only the lint is skipped.
	- Actual cause [Bug]:
		- The lint stage returned early, and it is what calls the other four.
	- Actual fix [Bug]: It skips the lint only.
	- Branch: macos
	- Commit: 277947e
	- Test case: none. It would take a whole pipeline run with `shellcheck` hidden from PATH.
	- Closed: 20260930-181124

- `install.ps1` installed without asking when nothing answered its prompt.
	- ID: 2026093015570558
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Avg
	- Opened: 20260930-155200
	- Opened by: JC
	- Target OS: Any, under pwsh
	- Steps to reproduce [Bug]:
		- Run `install.ps1` without `-Yes`, with stdin at its end, such as from a scheduled task or `< /dev/null`.
	- Incorrect behavior [Bug]: It prints the plan, then downloads and installs.
	- Expected behavior [Bug]: No answer means no, as `[y/N]` says. `install.bash` already stops there.
	- Reproduced [Bug]: Yes, by the new no-answer case in `installer-test.bash`.
	- Actual cause [Bug]:
		- `Read-Host` gives back nothing at the end of stdin, and nothing `-notmatch` a pattern is not true. So the "no" branch never ran.
	- Actual fix [Bug]: The answer is cast to a string before the match, at both prompts.
	- Branch: testids
	- Commit: f4c69e3
	- Test case: `ErOkWfZ`, `ErOkWfb`.
	- Closed: 20260930-155553

- `test-ids.py check` missed test IDs kept in an array.
	- ID: 2026100409004496
	- Type: Bug
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20261004-090044
	- Opened by: JC
	- Related IDs: 2026100317515523
	- Steps to reproduce [Bug]:
		- Keep a check's ID in a bash array instead of on its `fId` line, as the two arm64 link checks did.
		- Run `cicd/utility/test-ids.py check`.
	- Incorrect behavior [Bug]: It passes without reading those IDs, so a duplicate or a malformed one would go through.
	- Expected behavior [Bug]: Every ID in the pipeline is checked, or the check fails.
	- Reproduced [Bug]: 20261004, on `ErgjCkW` and `ErgjCkX` in `cicd.bash`.
	- Actual cause [Bug]:
		- The check only reads IDs at the start of an `fId` or `fWant*` line, and the array put them somewhere else.
	- Actual fix [Bug]:
		- The arm64 link checks use `fId`'s keyed form, like the cross targets.
		- The check also fails on a word that looks like an ID but that no test line names, and on a `// test-id:` mark that is not above a test. A comment is let through, so a retired test can stay in one.
	- Branch: idgaps
	- Test case: `ErkRrmk` to `ErkRrmo` in `pipeline-test.bash`, against a scratch tree. `ErkRrml`, `ErkRrmm` and `ErkRrmo` failed on the old `test-ids.py`. `ErkRrmn` failed with the comment exemption taken out.
	- Closed: 20261004-090044

- The macOS shared library exports all of Wasmtime.
	- ID: 2026093018112419
	- Type: Enhancement
	- Status: Done
	- Priority|Severity [Bug]: Low
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: macOS
	- Requirements  [Feature]:
		- Only `zuid_*` exported, as on Linux.
	- Progress log:
		- 20261003: not tried. The Mac test host was unreachable.
		- 20261003: Done in `build.zig`, so the tests, `capi_smoke.c` and each slice in `package.bash` all get the same dylib. On a Mac it links the dylib again with Apple's linker, from `libzuid.a` plus Wasmtime, and installs it over Zig's copy. The symlinks stay as Zig made them.
		- 20261003: The export list is made from `lib/zuid.map` at build time, so there is no second copy to drift.
		- 20261003: Apple's linker signs the arm64 slice itself, so no `codesign` step. It defaults the compatibility version to 0.0.0, so the relink passes Zig's 1.0.0.
		- 20261003: With no Xcode command line tools, or when building for macOS off a Mac, the build warns and keeps Zig's dylib.
	- Decisions:
		- Zig's Mach-O linker ignores `lib/zuid.map` and has no exported symbols list. A relink with Apple's `ld -exported_symbols_list` would do it.
		- Low, because two-level namespace keeps the library's own calls bound to itself. `Eq9gPQn` passes on macOS.
	- Verified:
		- On b26, the full pipeline with `--package` passes. `Eq9gPQm` runs there now; the only skip left is the Linux-only glibc check.
		- The release dylib's two slices export 12 symbols each, all `zuid_*`. Each keeps `@rpath/libzuid.1.dylib` and macOS 13.0, and the arm64 slice is ad-hoc signed. `capi_smoke.c` runs against the release dylib.
		- The full Linux pipeline passes. The Linux build is unchanged.
	- Swept: every place the dylib is built on a Mac goes through `zig build`: the Zig stage, the C module stage and both slices in `package.bash`. Nothing else links it.
	- Branch: macexports
	- Commit: f3f5558, e011230, 9fd8271
	- Test case: `Eq9gPQm` runs on macOS now, and on both systems reads the allowed names from `lib/zuid.map` and checks every function `zuid.h` declares is exported. It failed on b26 with the old `build.zig` (828 stray exports) and passes with the fix. New `ErfrKRQ` checks each slice of the release dylib under `--package`: exports, install name with its versions, macOS 13.0, and the arm64 signature. Its export check failed on a release built with the old `build.zig`. Its install name check rejects the first relink's dylib, which had compatibility version 0.0.0.
	- Acceptance signoff: Self-closed: the intent was clear, and the tests failed before the fix and pass after.
	- Closed: 20261003-143030

- Drop BSD from the installer and the docs.
	- ID: 2026100315241091
	- Type: Task
	- Status: Done
	- Opened: 20261003-152410
	- Opened by: JC
	- Target OS: BSD
	- Requirements  [Feature]:
		- `install.bash` stops treating any other system as FreeBSD, and says the platform has no build.
		- README drops BSD from the platform list and the install table.
		- `package.bash` stops listing BSD among the builds still to come.
	- Progress log:
		- 20261003: `install.bash` refuses any system other than Linux or macOS, naming it and saying no build exists for it. It used to call any such system FreeBSD and go looking for that tarball.
		- 20261003: `install.ps1` had the same gap: anything not Windows or macOS got the Linux build. It now refuses those the same way.
		- 20261003: README, `package.bash` and an `env.zig` comment drop BSD.
		- Verified: the new test failed on the old `install.bash` and passes on the new one. `installer-test.bash` passed in full, both installers, and `cicd.bash --quick --no-backup` passed. Shellcheck is clean.
		- Swept: README, design.md, contributing.md, changelog.md, `install.ps1`, `cicd/` and `installer-test.bash`. Left alone: "BSD wc" in `cli-test.bash` and "BSD sed" in `installer-test.bash`, which are about the macOS tools; the closed item that listed BSD in the installer; the platform decision under Old format. `cicd.bash`'s `--cross` list has no BSD entry.
	- Decisions:
		- No BSD target. Wasmtime publishes no BSD build, so there is nothing to embed.
	- Branch: nobsd
	- Commit: f835fe0
	- Test case: Ergbz3Z, Ergbz3a in `installer-test.bash`, with a stand-in `uname` reporting FreeBSD. The `install.ps1` refusal has no test, since pwsh's `$IsLinux` cannot be faked from outside.
	- Acceptance signoff: README text changed.
	- Closed: 20261004-073955

- Linux arm64 release, cross-built on the Linux build machine.
	- ID: 2026100317515523
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. The `--package` and `--cross` runs pass.
	- Needs external testing: No. Done on `vmDebARM64`, 20261004.
	- Opened: 20261003-175155
	- Opened by: JC
	- Related IDs: 2026100315241096, 2026100313105241
	- Target OS: Linux, arm64
	- Requirements  [Feature]:
		- A Linux arm64 tarball, bare binary, `.deb` and `.rpm` beside the x86_64 ones, with the same layout.
		- It runs on a plain armv8-a CPU with glibc 2.28.
		- Both installers fetch it on an arm64 Linux machine.
	- Progress log:
		- 20261003: The arm64 Wasmtime pin is the sha256 of the v47.0.3 release asset, downloaded and hashed. It matches the digest GitHub lists for that asset.
		- 20261003: On Linux, `package.bash` builds both architectures whatever the host is, and makes one release for each. The pipeline fetches the other architecture's Wasmtime only for `--package`.
		- 20261003: The new assets are `zuid-linux-arm64`, its `.tgz`, `zuid_<version>_arm64.deb` and `zuid-<version>.aarch64.rpm`.
		- 20261003: Both installers already picked the arm64 asset on an `aarch64` machine. No change there.
		- 20261003: README is unchanged. It lists what is published, and nothing arm64 is yet.
		- 20261003: `package.bash` now stages each release in a function, so the Mac path changed shape too. It still makes one universal release. The b26 run 2026100313583935 waits on covers it.
		- 20261003: On an arm64 Linux host the AVX check skips when its objdump cannot read x86_64, as it used to skip there.
	- Decisions:
		- Cross-built on the x86_64 Linux build machine, since Zig cross-compiles Linux with nothing extra installed.
		- Every `--package` run on Linux builds both. There is no separate switch.
		- The arm64 baseline is plain armv8-a, which Zig picks once the target is named. The check allows the pointer authentication instructions an older CPU runs as no-ops.
		- All three are open to change.
	- Verified:
		- `cicd/cicd.bash --package --no-dogfood --no-backup -q` passes. It fetched and checked the arm64 Wasmtime itself and wrote all eight assets.
		- `cicd/cicd.bash --cross --no-dogfood --no-backup -q` passes.
		- The arm64 tarball lists the same files as the x86_64 one. The `.deb` says arm64 and the `.rpm` says aarch64.
		- `capi_smoke.c` links for arm64 against the tarball's static and shared libraries. Not run, since nothing here runs arm64 code.
		- 20261003, on `vmDebARM64` from a `--package` run of `main` at 0d01af3: the bare binary and the tarball's `bin/zuid` run, with `--version`, the default, `%d%r`, `%m` and `-n 3`. `%m` gives the VM's own network card address.
		- 20261003, on `vmDebARM64`: `capi_smoke.c` built with the VM's gcc runs against the tarball's shared library, and against its static ones both named directly and through the header's link line.
		- 20261003, on `vmDebARM64`: `install.bash --target user` against a local release picked `linux/arm64`, fetched only the arm64 tarball and the checksums, and the installed command runs. A second run said it was already installed.
		- 20261004, on `vmDebARM64`: the arm64 `.deb` installs with apt and puts `zuid` in `/usr/bin`, and the command runs. It removes cleanly.
		- 20261004, on `vmDebARM64` with pwsh 7.6.6: `install.ps1 -Target user` against a local release picked `linux/arm64`, fetched only the arm64 tarball and the checksums, and the installed command runs. A second run said it was already installed, and `-Uninstall` removed it.
	- Swept: every `uname -m` use, asset name and `vendor/wasmtime` path in `cicd/`, `build.zig`, both installers and `installer-test.bash`. The x86_64 release checks now read the x86_64 release on any Linux host.
	- Branch: arm64
	- Commit: 9631a0b
	- Test case: `ErgjCkT` to `ErgjCkX` under `--package` on Linux: arch of every file and package, no instructions past armv8-a, glibc 2.28, and the two links. Each failed on a release broken for it: an x86_64 binary or `.deb` under the arm64 name, a build for a newer CPU, a build for glibc 2.39, an empty `libzuid.a`, and a shared library with no `zuid_*`. `ErgjCkY` and `ErgjCkZ` in `installer-test.bash`, with a stand-in `uname` reporting `aarch64`, failed with `install.bash` picking x86_64. `install.ps1` has no test, since pwsh's architecture cannot be faked from outside.
	- Acceptance signoff: Self-closed: the intent was clear, it builds what was asked, and it passed on an arm64 machine.
	- Closed: 20261004-074509

- macOS gets a universal binary for both amd64 and ARM.
	- ID: 2026100313105241
	- Type: Enhancement
	- Status: Done
	- Needs local test suite run?: No. The full pipeline passes on Linux.
	- Needs external testing:
		- Run the arm64 slice on an Apple Silicon Mac: the command, and `capi_smoke.c` against the tarball's libraries.
		- A live install on a Mac, once a macOS asset is published.
	- Opened: 20261003-131052
	- Opened by: JC
	- Related IDs: 2026093018112406, 2026093018112419
	- Target OS: macOS
	- Progress log:
		- 20261003: The arm64 Wasmtime pin is the sha256 of the v47.0.3 release asset, downloaded and hashed. It matches the digest GitHub lists for that asset.
		- 20261003: Both slices cross-build from Linux and merge into fat files. The one exception is `libwasmtime.a`, which the Linux `lipo` cannot read, so it waits on b26.
		- 20261003: Found along the way: Zig's macOS static library gives its members no read permission, which broke the archive cleanup in `package.bash` on any Mac with llvm-ar. Fixed.
		- 20261003: `package.bash` builds each slice into its own tree now, not `zig-out`. So after `--package` the dogfood install gets the build the tests ran on, not the release build.
		- 20261003: For 2026093018112419, each slice is still a separate tree before the merge, so a per-slice relink can go there.
		- 20261003: The b26 tests pass. Waits on signoff for the one-asset name and the installer change.
		- 20261003: Signed off. The arm64 slice still has not run on an Apple Silicon Mac.
	- Decisions:
		- Fat: the command, `libzuid.a` and `libzuid.dylib`. Also `libwasmtime.a` in the tarball, since `zuid.h` tells a static consumer to link it.
		- The macOS tarball is still built on a Mac, with Apple's `lipo`. The Linux cross-build was only a check.
		- One asset, `zuid-darwin-universal`, instead of one per architecture. Both installers fetch it on any Mac.
		- Both slices ask for macOS 13.0. The arm64 slice gets the M1 as its baseline CPU, the oldest arm64 Mac.
		- A non-host target's Wasmtime goes in `vendor/wasmtime-<platform>`. The build machine's own stays in `vendor/wasmtime`.
		- `--cross` is left alone. Its list is for Go compile checks only.
	- Verified:
		- `zig build` for x86_64 and arm64 macOS, from Linux.
		- `package.bash`'s macOS path, built here: a `zuid-darwin-universal` binary and tarball, with fat files, the dylib symlinks, the right install name, an ad-hoc signed arm64 slice, and minimum macOS 13.0 in both slices.
		- `capi_smoke.c` links against the universal static and shared libraries for both slices.
		- The vendor stage picks, fetches and checks the right archives for an Intel Mac, an Apple Silicon Mac and Linux.
		- A real Linux `package.bash` run gives the same tarball layout as before, and its checks pass.
		- `cicd/cicd.bash --cross` passes, 222 test IDs.
		- 20261003, on b26 at c10d2ee: the full pipeline with `--package` passes. The vendor stage fetched and checked the arm64 Wasmtime itself. The only skips are `ErbFB7C` (Linux only), the CLI profile and the demo.
		- 20261003, on b26: `lipo -info` lists x86_64 and arm64 for `dist/zuid-darwin-universal`, and for `bin/zuid`, `lib/libzuid.a`, `lib/libzuid.1.0.0.dylib` and `lib/libwasmtime.a` from the tarball.
		- 20261003, on b26: the x86_64 slice runs. `--version` and a default identifier work, and `capi_smoke.c` built with clang `-arch x86_64` against the tarball's static and shared libraries runs and passes.
		- 20261003, on b26: `capi_smoke.c` links with clang `-arch arm64`, static and shared.
		- 20261003, on b26: `installer-test.bash` passes for both installers against a local release serving `zuid-darwin-universal.tgz`. Nothing is published for macOS yet, so no live install.
	- Swept: every `vendor/wasmtime` path, `uname -m` use and asset name in `cicd/`, both installers and `installer-test.bash`. `cicd.bash` used to look up an arm64 Mac's pin under `arm64-macos`, which matches nothing; it says `aarch64` now.
	- Branch: universal
	- Commit: d1144f7
	- Test case: `Erfhegq` checks every binary and library has both slices. `ErbFB7B` and `ErbFB7D` read each slice of a fat file now. Each was watched to fail on a broken universal release: a thin binary, a thin `libzuid.a` in the tarball, an arm64 slice asking for macOS 14.0, and an x86_64 slice built for x86_64_v3. They run under `--package` on a Mac.
	- Closed: 20261003-162000

- Build and test on macOS.
	- ID: 2026093018112471
	- Type: Enhancement
	- Status: Done
	- Opened: 20260930-181124
	- Opened by: JC
	- Target OS: macOS, Intel
	- Requirements  [Feature]:
		- The whole pipeline passes on a Mac.
		- `%m` reads a hardware address there.
	- Progress log:
		- `getentropy` comes from `sys/random.h` there.
		- `%m` reads `AF_LINK`.
		- The shared library's install name carries the ABI major, `@rpath/libzuid.1.dylib`.
		- The Wasmtime pin is per platform.
		- The harnesses no longer depend on GNU `sed -i`, `wc` padding or `nproc`.
	- Branch: macos
	- Commit: 277947e
	- Test case: the existing suites, run on macOS. `EqA3RdB` and `EqA3RdC` check the macOS names.
	- Closed: 20260930-181124

- A Linux arm64 test machine.
	- ID: 2026100315241096
	- Type: Task
	- Status: Done
	- Opened: 20261003-152410
	- Opened by: JC
	- Target OS: Linux, arm64
	- Requirements  [Feature]:
		- A libvirt virtual machine beside the others, named `vmDebARM64`, running Debian for arm64.
		- A raw disk image of about 256 GB that grows as used.
	- Progress log:
		- 20261003: Debian 13's arm64 cloud image, checked against Debian's published checksum, turned into a raw image and grown to 256 GB. It takes about 1.3 GB.
		- 20261003: The arm64 CPU is emulated, so builds and tests run several times slower than on the host.
		- 20261003: The first boot set up nothing, because the setup disk was attached over USB and Debian's cloud kernel has no driver for it. Moved to a virtio disk and booted again.
	- Verified: ssh works with the usual key. It reports `aarch64`, Debian 13, a 252 GB root and working sudo. The guest agent reports its address.
	- Test case: none. It is a machine, not code.
	- Acceptance signoff: Self-closed: built as asked.
	- Closed: 20261003-152410

## Old format

### Bugs

### Features and enhancements

- 🔬 Run the Zig fuzz tests in fuzz mode, once a Zig release can build one.
	- Note: the tests are written and replay their corpus on every run. `zig build test --fuzz` fails to compile inside 0.16.0's own test runner, so nothing on this side can fix it. `details.md` has the error.
	- Note: 20261003: the b26 run stopped before the fuzz stage, at the Zig build hang, 2026100318410002.
	- Note: 20261003: Zig 0.17.0 runs fuzz mode, `--fuzz=<limit>` too, on a tiny test and on ours. There is no 0.16 point release with the fix. So this waits on 2026100313583935, the move to 0.17.0. One catch: a run that finds a bad input still exits 0, so the pipeline stage has to read the output. The 0.17.0 download was checked against the sha256 in Zig's download index.
	- Done: 20261003: a full pipeline run fuzzes both Zig fuzz tests after the Zig tests, 50K iterations each. A quick run prints a skip line instead. It takes about 35 s here, and about 13 s more after a change to the Zig source.
	- Decision: 20261003, open to change: 50K iterations, and Debug, since the leaked-context test counts contexts only there. A find fails the stage from the output, not the exit code. Its input is kept in `cicd/artifacts/fuzz/`, which nothing rotates, and printed as a string ready for the test's corpus. The limit is always attached with `=`, since a bare `--fuzz` starts a web server.
	- Verified: a planted two-byte failure in the format test turned the stage red, with Zig's crash line, and the kept input failed the plain test run once added to the corpus. A planted panic in the C test, run through the same command, ended in the same `input saved to` line. No port was opened during a run. A full `cicd.bash --no-dogfood --no-backup -q` passes.
	- Done: 20261004: each fuzz test prints its own line under its own ID, as the Go one does. They used to share one line under `ErgeVve`, so a find could not say whose it was. A find now fails the test that found it, and the other shows as skipped.
	- Test case: `Eq9zVsH` and `Eq9zVsI` in the fuzz stage. `ErkRrmp` to `ErkRrmr` in `pipeline-test.bash` run the stage with a stand-in `zig`: a clean run, a find, and a broken run. All three failed on the old stage. `ErgeVve` is retired.
	- Note: still needs a pipeline run on b26, like 2026100313583935.
	- Opened: 20260917-131500

- 🛠️ `%m` is Linux-only on the Zig side - it reads `getifaddrs` for `AF_PACKET`, and macOS wants `AF_LINK` instead. The Go module is already portable, and the help text and the C header both say so. Do it alongside the cross targets, since nothing on the Zig side cross-compiles yet either.
	- Should work on Windows too.
	- Done: macOS, 20260930. Windows is left.
	- Decision: 20261003, the Windows build may run on a Windows test box, so the MSVC toolchain is open as well as mingw. MSVC is preferred where the box has the build tools, since most Windows C users link with it.
	- Note: 20261004, the Windows build is cross-built on Linux after all, by direct answer. See 2026100416052035.
	- Opened: 20260802-135041

- 🔘 Packaging for other platforms. Needs a Wasmtime archive vendored per target. Blocked on that, and on the Zig side building for Windows at all.
	- Note: x86_64 macOS has its pin and builds natively, 20260930.
	- Note: `package.bash` builds the macOS tarball and binary on a Mac, 20261002. Nothing is published for it yet.
	- Note: `build.zig` and `package.bash` take a non-host target's Wasmtime from `vendor/wasmtime-<platform>`, as the macOS universal build does, 20261003. Another target needs its pin and a fetch.
	- Decision: 20261003, the targets are Linux x86_64 and arm64 on glibc, macOS universal, and Windows x86_64 and arm64. No BSD. Others such as armv7, riscv64, musl and Android are out for now.
	- Note: 20261004, FreeBSD x86_64 is back, from FreeBSD's own Wasmtime package. See 2026100413383571.
	- Decision: 20261003, a Windows package is a `.zip`, installed by `install.ps1`.
	- Decision: 20261003, Linux arm64 is tested on the `vmDebARM64` virtual machine, not only built.
	- Note: 20261003, Linux arm64 is built and checked, and waits on testing on `vmDebARM64`. See 2026100317515523.
	- Note: 20261004, Windows is split out as 2026100416052035 and 2026100416052036.
	- Opened: 20260802-025417

- 🔬 Publishing. `--publish` stays rejected with a reason until there is somewhere to publish to.
	- Note: GitHub releases is that place now. `v1.0.0-alpha.1` was published there by hand.
	- Decision: 20261003, every release also gets a `go/v<version>` tag.
	- Decision: 20261003, the next release is `v1.0.0-beta.1`.
	- Decision: 20261003, the Mac and Windows files are copied back to the Linux box, which creates the release and uploads everything at once with one checksums file.
	- Done: 20261003: `cicd.bash --publish` replaces the refusal and implies `--package`. It refuses unless on `main` with a clean tree, HEAD pushed, `gh` logged in, and no tag yet for the version in `core.zig`. It shows the plan and asks, then tags `v<version>` and `go/v<version>`, pushes both, creates the release with every file and one `checksums.txt`, and waits for the download to answer.
	- Decision: 20261003, open to change: files from the other machines go in `dist-incoming/`, since `--package` empties `dist/`. Only its top level counts, and a `checksums.txt` or dot file there is skipped.
	- Decision: 20261003, open to change: every target needs its file: Linux x86_64 and arm64, macOS universal, Windows x86_64 and arm64. `--allow-partial` publishes without the missing ones and lists them in the plan.
	- Decision: 20261003, open to change: anything but `y` or `yes` at the prompt is a no. `-q` skips the prompt.
	- Decision: 20261003, open to change: a version with a `-` is a prerelease. The notes are that version's section of `changelog.md`, or empty. Both tags are annotated, like `v1.0.0-alpha.1`.
	- Decision: 20261003, open to change: the tags go on HEAD only when it is exactly what the remote branch has, not just somewhere in its history.
	- Decision: 20261003, open to change: `--package` names its files for the version in `core.zig`, not for `git describe`. The Mac and Windows files are built before the tag exists, and have to match. A copied-in tarball from another version is refused.
	- Note: 20261003, `ZUID_GH` names another `gh`. The tests use a stub with a local bare remote, so nothing reaches GitHub.
	- Note: 20261003, the old check that `--publish` is refused (`ErOjF72`) is commented out with the reason.
	- Note: 20261003, branch `publish`. The first real run waits on the Windows build, or on a go-ahead to publish with `--allow-partial`. The version in `core.zig` is still `1.0.0-alpha.1`, so a run today refuses on that tag.
	- Decision: 20261004, the first real run waits on the Windows build. No `--allow-partial`.
	- Test case: `ErgqYt2` to `ErgqYtH` and `ErgqjsR` in `pipeline-test.bash`. Each was seen to fail with its check broken.
	- Opened: 20260802-025417

- 🛠️ Tag the Go module as `go/v<version>` at the next release, so it can be asked for by version. A module in a subdirectory needs the prefix, and the plain `v1.0.0-alpha.1` tag does not reach it - `go get ...@v1.0.0-alpha.1` answers "found, but does not contain package". Deferred because pushing a public tag is a release decision, not a code fix. `README.md` says how to pin a commit meanwhile.
	- Decision: 20261003, yes, with every release, starting at `v1.0.0-beta.1`.
	- Note: 20261003, the code is in: `--publish` pushes `go/v<version>` beside `v<version>` on the same commit. The tag goes out with the first real publish, and README's line saying there is no `go/` tag yet changes then.
	- Test case: `ErgqYtE` in `pipeline-test.bash`.
	- Opened: 20260917-104114

- 🔘 Default configuration hard-coded
	- 🔘 Overridden by per-user config file, created the first time a default setting is changed.
		- 🔘 Settings live under `~/.config` (YAML or TOML), resistant to errors (e.g. don't bail on the whole thing due to one bad line).
			- Notes:
				- This would be shcl now, not YAML or TOML.
				- Wait for v3 to ship.
	- 🔘 Overridden by program options at run-time.
	- 🔘 Config file creation belongs to the command only, never to either module.
	- Opened: 20260801-090104

- 🔘 C module cross targets, cross-compiled with `zig cc`. Needs a vendored Wasmtime archive per target, the same blocker as packaging for other platforms.
	- Note: `build.zig` takes a non-host target's Wasmtime from `vendor/wasmtime-<platform>`, as the macOS universal build does, 20261003. Another target needs its pin and a fetch.
	- Decision: 20261003, the same targets as packaging for other platforms.
	- Note: 20261003, Linux arm64 is built and checked, and waits on testing on `vmDebARM64`. See 2026100317515523.
	- Opened: 20260801-090104

### Done

#### Done - Bugs

- ✅ `install.ps1 -Target system` with nowhere to write downloaded and verified the whole release, then threw a raw permissions error from `New-Item`.
	- Cause: the writability test only ran when no target was named. Asked for by name it was taken on trust, and the write is the last thing the script does. There is no elevation on that side the way `install.bash` has sudo.
	- Fixed: one predicate now answers both questions, and it tests the install directory as well as the link directory - a box where `/usr/local/bin` is writable but `/opt` is not used to pick a system install and fail late. With no target named it still falls back to a user install; asked for by name it stops before downloading and names `-Target user`.
	- Note: found while writing the system-target cases. `install.bash` needs no equivalent.
	- Test case: `EqANb7C`, `EqANb7D`, `EqANb7E`.
	- Opened: 20260917-203000
	- Closed: 20260917-210000

- ✅ One error message read in a different style from every other one. An unknown base came back as the conversion library's own text: lower case, double quotes.
	- Fixed: the command writes its own sentence and keeps the near match the library found, so a typo now reads `Unknown base 'nope'. Did you mean 'nice'?`. With no near match it says where the list is.
	- Fixed: a blank base name is refused by the command too. It used to reach the library as empty and come back as `empty base name`.
	- Note: `style-guide_cli.md` narrows its exception to a failure inside the wasm runtime, which is internal and not about anything the user typed.
	- Test case: `EqABve4`, `EqABve5`, `EqABve6`.
	- Opened: 20260917-133000
	- Closed: 20260917-140000

- ✅ A base name long enough to push the library's message past the 512-byte error buffer lost the error code with it, so a typo came back as `Generation failed: ConvertFailed`.
	- Cause: reading the message refused rather than truncating, and the read failing threw away the code that came with it.
	- Fixed: the text is clamped to what fits, on a codepoint boundary, and the code always survives.
	- Note: found while testing the message above.
	- Test case: `EqABve7`.
	- Opened: 20260917-140000
	- Closed: 20260917-140000

- ✅ Several `.md` files ran their top-level bullets tight, with no blank line between them.
	- Fixed: `contributing.md` and `style_guide.md` are spaced. Auto-generated table of contents blocks are left alone, as the convention says.
	- Decided: `contributing.md` gets reflowed like anything else here, and its generator banner, attribution footer and commented-out template sections are gone. A document that advertises where it was generated from is not wanted.
	- Fixed: same file picked up the `markdownlint-disable` header every other document here has, and a blank quote line in the two block quotes that needed one.
	- Test case: none. The markdown check script lives outside the repo on purpose.
	- Opened: 20260917-133000
	- Closed: 20260917-140000

- ✅ Contact address in `trademark.md` was still a placeholder.
	- Fixed: `zuid@yottacore.com` in `trademark.md`, `contributing.md` and `code_of_conduct.md`. The last one still named the project it was copied from.
	- Test case: `ErOj0WU`.
	- Opened: 20260801-090104
	- Closed: 20260917-124100

- ✅ The `.deb` and `.rpm` checksums did not match the downloaded files.
	- Cause: GitHub rewrites `~` to `.` in an uploaded filename.
	- Fixed: both are named that way to begin with, so `checksums.txt` matches what a downloader ends up with.
	- Note: the version recorded inside each package still carries the `~` that sorts it ahead of the final release.
	- Test case: none. It needs nfpm and a release build, which only `--package` does.
	- Opened: 20260805-014016
	- Closed: 20260805-014958

- ✅ A default install found no release while only a prerelease was published.
	- Cause: the installers asked for `latest`, which only ever answers with a final release.
	- Fixed: the release is chosen from the full list. Default takes the newest stable and falls back to the newest prerelease with a line saying so; `--release dev` takes whatever is newest either way.
	- Test case: `ErOioHp`, `ErOioHq`, `ErOioHr`, `ErOioHs`.
	- Opened: 20260805-014016
	- Closed: 20260805-014958

- ✅ Code review 20260917-104114. Defects by finding id and rank. Details are in the review document.
	- ✅ F4, blocking: several C module error codes are checked by no test, so a renumbering would go unnoticed.
		- Origin: 8ba15ef, the 20260804 review fixes, which added codes 12 and 13. Confirmed.
		- Fixed: codes 2, 6, 12 and 13 are now asserted at the C surface, in both the Zig test and `capi_smoke.c`.
		- Verified: three separate renumberings of `codeFor` each turn both runners red, and the codes they pin go green again once restored.
		- Note: code 10 is left unpinned. It needs a machine that cannot supply a component, and nothing available can stage that.
		- Test case: `Eq9dPAO`, `ElpGOHZ`, `ElpGOHa`.
	- ✅ F8, blocking: the PowerShell installer finds no release at all once more than one is published.
		- Origin: 39f7403, the fix for the earlier "default install found no release" bug. Confirmed.
		- Cause: `Invoke-RestMethod` hands a JSON array to the pipeline as one object, so `@(irm ...)` inline gave a single element holding the whole list, and each release's `draft` flag was then tested as an array.
		- Fixed: the response goes into a variable before it is wrapped. It was the only site of that pattern; the two `Invoke-WebRequest -OutFile` calls do not go through the pipeline.
		- Done: `cicd/utility/installer-test.bash` is new, and runs both installers against a local four-release listing. It is a cicd stage, and the copies it patches assert every rewrite, so a script that moves its URLs fails the harness rather than testing nothing.
		- Verified: reverting the lookup turns both ps1 cases red with "no published release found", which is the reported symptom. A single-release listing still reads correctly.
		- Test case: `Eq9ejdJ`, `Eq9ejdL`.
	- ✅ F9, blocking: `package.bash` wipes whatever directory `--out` names, before it builds anything.
		- Origin: 08c6996. Not seen by an earlier review. Confirmed.
		- Fixed: a `--out` directory is only emptied when the script can show it is one of its own - it left a `.zuid-package-dir` marker there, or the directory is empty or new. Anything else is refused by name. The default `dist/` counts as the script's own, since the script picked that path rather than a caller.
		- Fixed: the clearing moved to after the build, so a failed build now leaves the previous run's artifacts alone. The check still runs up front, so a mistyped `--out` fails in a second rather than after a ReleaseSafe build.
		- Fixed: the contents are cleared rather than the directory itself, so a mount point or a directory with granted permissions survives being reused.
		- Verified: four cases in `installer-test.bash`. Restoring the old `rm -rf "${OUT}"` turns the first two red. Repeated real runs against `dist/` replace the artifacts, and the marker is hashed by nothing and counted in nothing.
		- Test case: `Eq9filc`, `Eq9fild`, `Eq9file`, `Eq9filf`.
	- ✅ F1, should-fix: the shared C library exposes every Wasmtime function it contains, so a program with its own copy takes over the library's calls.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: `zig/lib/zuid.map`, a linker version script naming `zuid_*` global and everything else local. Exports went from 834 to 11. The local half is what matters: the library's internal calls now bind inside it and cannot be displaced at all.
		- Done: two cicd checks. One asserts nothing but `zuid_*` is exported; the other is `zig/lib/test/capi_interpose.c`, a program that defines `wasm_config_new` and must still get a working context.
		- Verified: dropping the version script reports 823 stray symbols and fails the stage. Before the fix that program got a NULL context and its own function was called.
		- Test case: `Eq9gPQm`, `Eq9gPQn`.
	- ✅ F2, should-fix: the static C library holds the Wasmtime archive inside itself, where no linker looks, and the release has no separate copy to link.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: the static module no longer links the Wasmtime archive, so `libzuid.a` holds its own two objects and went from 75 MB to 9.8 MB. Whoever links it supplies Wasmtime, which is what the header always said.
		- Fixed: `package.bash` puts `libwasmtime.a` in the release `lib/`, so the link line the header prints has something to satisfy it.
		- Fixed: member names are re-archived on basenames, so a published archive no longer carries the build machine's cache paths. That needs llvm-ar, since GNU ar lists the members Zig writes and then cannot address them; without it the step warns instead of failing.
		- Fixed: the header's linking paragraph now says where `libwasmtime.a` comes from, and that the shared library exports only the entry points.
		- Done: two cicd checks. One links the smoke test against a tree holding only what is released, with the header's own link line, deliberately not pointed at `vendor/`. The other refuses an archive with another archive inside it.
		- Verified: restoring the nesting fails the archive check. The review's reproduction - a tree holding only `libzuid.a` and `zuid.h` - failed with "have you installed the static version of the wasmtime library ?" before, and the unpacked release tarball now links both static and shared.
		- Test case: `Eq9hexE`, `Eq9hexF`.
	- ✅ F3, should-fix: a C context that is never freed is not reported as a leak, in tests or in debug builds.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Cause: nothing could call the debug allocator's own check. A C caller never says it is finished, so there is no last moment for a `deinit()` to run in.
		- Fixed: `capi.liveContexts()` and `capi.leakCount()` let the tests ask instead, the second one straight through `DebugAllocator.detectLeaks()` so the stack traces the design promises are real. Both are debug-only, so a release build carries no counter.
		- Verified: the review's own injection - replacing the three `defer capi.zuid_free(z)` lines with `_ = &z` - reports "expected 0, found 3", and the allocator half names all three leaked addresses on its own when checked first.
		- Note: the test deliberately does not free twice. The magic check reads memory the allocator has unmapped, so it segfaults rather than returning, which is the recorded reason the header promises no more than C's `free()`.
		- Test case: `Eq9icWm`.
	- ✅ F5, should-fix: the C module reports a buffer too small for any identifier over 4 KB, however large the caller's buffer, and that error never has a message.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: `zuid_generate` renders straight into the caller's buffer, less the byte the NUL needs, so the only limit is the one the header documents. The error path now re-terminates that buffer, since a failure part way through leaves its own partial output where a separate buffer used to hide it.
		- Fixed: `ZUID_ERR_BUFFER` carries text in all three cases - a short `out_cap`, a zero `out_cap`, and a NULL `out`. The clearing moved above the buffer checks so a rejected buffer reports its own reason rather than the previous call's.
		- Swept: the command had the same fixed 4096 buffer and reported `BufferTooSmall` by its error name. It now grows the buffer until the identifier fits, up to 1 MB, and says so in words past that. The Go module returns a string and never had the limit.
		- Done: `cicd/utility/cli-test.bash` is new - 15 cases over what the command prints and exits with, which nothing covered before - and is a cicd stage.
		- Verified: before the fix all four probe cases returned code 5 with empty text, including two that should have rendered. Reverting the module fails the Zig test and three `capi_smoke.c` checks; reverting the command fails three CLI cases.
		- Test case: `Eq9kVKi`, `Eq9kVKp`, `Eq9kVKq`, `Eq9kVKr`.
	- ✅ F10, should-fix: the PowerShell installer picks a system install on Linux and macOS for users who cannot write there.
		- Origin: 08c6996. Not seen by an earlier review. Confirmed.
		- Cause: the test was whether `/usr/local/bin` exists, which it does everywhere, rather than whether it can be written. The install then failed after the whole download, with no elevation path of the kind `install.bash` has through sudo.
		- Fixed: `Test-DirectoryWritable` writes a probe file into the nearest existing ancestor and removes it, rather than reading a mode or an ACL. On Windows the install directory decides; elsewhere the link directory does, which is what `install.bash` tests.
		- Verified: a new harness case. Before the fix nothing landed under `HOME`; after it, the user install happens. It skips itself where the system location is writable, such as a run as root, since system is then the right answer.
		- Note: an explicit `-Target system` never reaches the probe, so that path is unchanged. Not covered by a test, since a system install needs root.
		- Note: the harness gave every case its own `HOME` only on paper - the counter naming them was incremented inside the command substitution that read it, so the subshell kept the new value and all of them shared one directory. Named directories now.
		- Test case: `Eq9l4yO`, `Eq9l4yP`.
	- ✅ F11, should-fix: re-running either installer on the installed version downloads and reinstalls it, though both say that is a no-op.
		- Origin: 08c6996. Reopens the done installer item, whose re-run claim had no test. Confirmed.
		- Cause: both read the installed version for the plan's "Replacing" line and neither compared it with the chosen tag.
		- Fixed: both compare, and a match prints "Already installed" with the version and location, then exits without fetching anything. Reinstalling means `--uninstall` first, which the message says.
		- Verified: the harness counts what the local server was asked for, so the no-op is measured rather than taken from the script's own output. Before the fix a re-run made two requests, the tarball and the checksums. A different version still installs over the old one, in both states, so the check is not a blanket refusal.
		- Test case: `Eq9lTwm`, `Eq9lTwn`, `Eq9lTwo`, `Eq9lTwp`, `Eq9lTwq`, `Eq9lTwr`.
	- ✅ F12, should-fix: the `go get` line in `README.md` leaves a program that imports the package unable to build, and the prerelease cannot be asked for by version.
		- Origin: 2209333. Not seen by an earlier review. Confirmed.
		- Cause: the line named the module root. `go get` on a root adds the module without what its package needs, so the build stopped on a missing `go.sum` entry for `convertbase`.
		- Fixed: `README.md` names the package, `github.com/jim-collier/zuid/go/zuid`, and says why. It also states that pinning needs a `go/`-prefixed tag, which does not exist yet, and how to pin a commit instead.
		- Done: a cicd stage builds and runs a scratch program importing the module, pointed at this tree so it covers what is about to merge. It also refuses a README that tells people to fetch the module root.
		- Verified: reproduced both halves in a scratch module - the missing `go.sum` entry, and the tag resolving to a pseudo-version of `main`. The corrected command pulls `convertbase` v0.1.0, builds, and prints an identifier. Restoring the old README line fails the stage.
		- Note: the `go/` tag itself is deferred, since pushing a public tag is a release decision.
		- Test case: `Eq9m0j2`, `Eq9m0j3`.
	- ✅ F13, should-fix: `zuid -f ''` prints an empty identifier and succeeds, where the Go and C modules treat an empty format as `%d`.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: the command treats an empty format as `%d`, so all three surfaces agree. A script running `zuid -f "$FMT"` with the variable unset no longer gets an empty identifier and success.
		- Verified: three CLI cases, covering an empty format, an empty base, and both together. The first and third go red without the fix. An empty base already defaulted correctly.
		- Test case: `Eq9mL16`, `Eq9mL17`, `Eq9mL18`.
	- ✅ F14, should-fix: the Go module reads the host name again for every identifier, though the design says each source is read once.
		- Origin: 27d8bc1. Not seen by an earlier review. Confirmed.
		- Cause: `liveFQDN` and `liveMAC` were wrapped in `sync.OnceValues` and `liveHostname` was not, so a long-running process whose name changed emitted two `%h` fingerprints for one machine, and `%h` could disagree with the cached `%f`.
		- Fixed: both `liveHostname` and `liveUsername` are wrapped now. The user name was not actually being re-read, since `user.Current` caches internally, but every source in the file answers the same way now.
		- Done: `go/zuid/live_test.go`, inside the package, counts reads of each of the four sources and asserts at most one per process. Plus a case that two host-name reads agree, which is the property the caching exists for.
		- Verified: unwrapping `liveHostname` reports "read the hostname 5 times". The vectors and `TestLiveSources` still pass.
		- Test case: `Eq9mpyS`, `Eq9mpyT`.
	- ✅ F6, nit: the C header says a context takes tens of milliseconds to create. It takes about half a second.
		- Origin: 7677deb. Confirmed.
		- Fixed: the header says around half a second, and names the reason - the module building its base registry - since that is why keeping one context matters.
		- Verified: measured 450 to 570 ms over five runs in both Debug and ReleaseSafe, which matches the deferred note on CLI startup. No test; it is a comment.
		- Test case: none. It is a comment.
	- ✅ F7, nit: an empty `SOURCE_DATE_EPOCH` drops the build number instead of falling back to the commit date.
		- Origin: e8442fb. Confirmed.
		- Cause: the value was parsed with `catch 0`, so both an empty and an unparsable one became zero, which means "no build number".
		- Fixed: an empty or whitespace-only value falls through to the commit date, as does an unparsable one, and that last case warns rather than passing silently. `-Dbuild-epoch` still wins over the variable, and a valid value still wins over the commit date.
		- Done: a cicd check builds with the variable empty and asserts a build number. It fails on the old `build.zig`, reporting the bare version.
		- Test case: `Eq9nb3o`.
	- ✅ F15, nit: `install.bash --release` with no value exits without a message.
		- Origin: 08c6996. Confirmed.
		- Cause: with one argument left, `shift 2` fails, and under `set -e` the script ended with nothing printed.
		- Fixed: `fNeedValue` checks first, so the message names the flag and points at `--help`.
		- Swept: `--target` and `--arch` did the same thing and are fixed with it. `install.ps1` needs nothing - PowerShell's own parameter binding already reports a missing argument by name.
		- Verified: three harness cases, one per flag. All three go red on the old script, exiting 1 with empty output.
		- Test case: `Eq9oNBg`, `Eq9oNBh`, `Eq9oNBi`.
	- ✅ F16, nit: both installers remove or replace a `zuid` at the link path that they did not put there.
		- Origin: 08c6996. Confirmed.
		- Fixed: both work out whether the link is their own - a symlink pointing into the install directory - before touching anything, since once that directory is gone the link dangles and there is nothing left to recognize. Uninstall keeps anything else and says so.
		- Fixed: install still replaces what is there, which is what an installer does, but the plan now names it rather than doing it quietly.
		- Verified: four cases per installer. A plain file planted at the link path survives uninstall, the output says it is being kept, install names what it overwrites, and the installer's own link is still removed. All go red on the old scripts.
		- Note: this is a real collision, not a hypothetical - `README.md` tells a source build that a full cicd run copies the command to `~/.local/bin`.
		- Test case: `Eq9oNBj`, `Eq9oNBk`, `Eq9oNBl`, `Eq9oNBm`, `Eq9oNBn`, `Eq9oNBo`, `Eq9oNBp`, `Eq9oNBq`.
	- ✅ F17, nit: `README.md` says nothing is published yet, and `design.md` says "four things" before a list of five.
		- Origin: 2209333. Confirmed.
		- Fixed: "Packages and installers" says `v1.0.0-alpha.1` is published for x86_64 Linux, and points at the source build for every other platform. `design.md` says five.
		- Done: a cicd check reads the count out of that sentence and compares it with the bullets under it. A number in front of a list drifts as soon as the list grows, and no linter counts.
		- Verified: putting "four" back fails the stage with both numbers named.
		- Test case: `Eq9ofeq`. The README wording has none.
	- Opened: 20260917-104114
	- Closed: 20260917-121500

- ✅ Code review 20260804. Twelve defects, from an adversarial pass over both implementations and the build script.
	- ✅ Fixed: a raw-byte base produced identifiers full of control characters. Both sides now refuse it.
		- Test case: `Em32NzX`, `Em32Nza`, `Eq9kVKx`.
	- ✅ Fixed: a clock far past the horizon wrapped on the Go side and rendered as the epoch instead of erroring.
		- Test case: `Em32NzU`.
	- ✅ Fixed: `WidthFor` never returned for a radix below two.
		- Test case: `Em32NzY`.
	- ✅ Fixed: the C module reported the previous call's error text for any failure that never reached the converter, and left the caller's buffer untouched.
		- Test case: `Em32Nzc`.
	- ✅ Fixed: a clock past the horizon reported a conversion failure with no message. It has its own error code now.
		- Test case: `Em32Nzb`, `Eq9dPAO`.
	- ✅ Fixed: pointers coming back from the WebAssembly module were used to index host memory unchecked, and exports were read without checking their kind.
		- Test case: none. It would take a hostile wasm module, and the one used is built here from a pinned release.
	- ✅ Fixed: a failed clock read returned arithmetic over uninitialized memory.
		- Test case: none. The clock call cannot be made to fail from a test.
	- ✅ Fixed: `--commit` swallowed a following flag as its message, and `-h` or `-v` anywhere inside an argument value triggered help.
		- Test case: `ErOjF6y`, `ErOjF6z`, `ErOjF70`.
	- ✅ Fixed: a pre-release toolchain version passed a floor it was actually below.
		- Test case: `ErOjF74`, `ErOjF75`.
	- ✅ Fixed: a temporary directory leaked whenever the C module stage failed, and the error trap said nothing for the exit code every failing tool actually uses.
		- Test case: none. It needs a compiler that fails part way through a stage.
	- ✅ Fixed: the reactor build discarded its own error output, so a failure silently fell back to a stale module.
		- Test case: none. It needs a broken Go toolchain.
	- ✅ Fixed: re-pinning the vendored runtime kept whatever was vendored first.
		- Test case: none. It needs a second Wasmtime download.
	- Note: its three numbered enhancement items are under Done - New features and enhancements.
	- Opened: 20260804-213000
	- Closed: 20260804-224440

#### Done - Features and enhancements

- ✅ The backup archived every build cache it walked past. Here that was a 12 GB `.zig-cache` and 957 MB of Panoplia audit scratch, and no other project excluded any of it.
	- Cause: the exclude was set from this project's cicd stage, on the reasoning that about 20 projects carry their own fork of the helper and a fix in one reaches none of the others. That left the helper's own generic list with no cache patterns at all, so every other project kept paying.
	- Fixed: the patterns moved into the helper's generic list, in all 22 project copies plus the canonical one, as one dir-and-contents block. It covers `.zig-cache`, ccache, ccls, `CMakeFiles`, `.cache`, and the JS, Haskell and Python caches. The Panoplia `working/audit-*` trees go with them, since each subagent gets a whole copy of the build; the reports beside them are small and stay in.
	- Fixed: `default_rarExcludes` is empty now, with the hook left plumbed for a pattern only this project would want. The stage line says so rather than printing nothing.
	- Verified: archiving the live tree drops from 14 GB to 299 MB, and from 1.1 GB for this project specifically, which was already excluding its Zig cache. `zig-out`, `dist/` and the audit reports are all still in.
	- Note: `zig-out` is deliberately not excluded. The block promises release builds stay in.
	- Test case: none. The excludes live in the shared backup helper, not in this project's code.
	- Opened: 20260917-160000
	- Closed: 20260917-163000

- ✅ A batch spent about a third of a millisecond an identifier, nearly all of it crossing into the wasm module. Every `generate` re-asked whether the base renders text, which is 33 round trips through the tokenizer with an alloc and a free each.
	- Cause: the 98keyboard fix added the control-byte probe and nothing measured after it. The cost was flat across every format, which is what a per-call fixed overhead looks like.
	- Fixed: the verdict is remembered on the host beside the radix and the zero digit, and thrown away when the slot points at another base. The check itself stays in `core`, since which bytes are refused is spec; only the remembering moved.
	- Verified: 16.6 us an identifier for `%r` against 357 us, and 170 us for all seven against 452 us, measured A/B against a library built from the previous commit. `details.md` has the full table.
	- Verified: an injected fault - the slot not cleared when it is aimed at a new base - turns three cases red, including a new one that alternates good, raw-byte and unknown bases on one host.
	- Done: `--count`'s ceiling goes from 100000 to 1000000, which is the same half a minute of work the old ceiling stood for.
	- Note: a single run still pays the probe once, so nothing there got faster. It is about a third of a millisecond against 600 ms of startup.
	- Test case: `EqAew24`, `EqAb38l`. The speed itself is profiled, not asserted.
	- Opened: 20260917-224500
	- Closed: 20260917-233000

- ✅ Generate more than one identifier per invocation. A time-only format repeats within one tick.
	- Decided: output stays literal - nothing is appended silently - but repeats in one invocation's output get a stderr warning suggesting `%r`.
	- Done: `-n`/`--count`, 1 to 100000, one per line. One run reads the clock once, so a format with nothing random in it comes out the same every line.
	- Done: repeats are counted by what actually matched, not by reading the format, so a narrow `--rand-chars` draw that collides on its own is reported too. Tracked as hashes, so the cost does not depend on how long a format renders.
	- Done: batching belongs to the command. The Go and C modules still hand back one identifier, since a caller there already has a loop.
	- Swept: a reader that quits early used to end in Zig's own error trace and a non-zero exit. A closed pipe now ends the run quietly, on the identifiers and on `--help` alike.
	- Verified: three injected faults - a dropped warning, a dropped ceiling check, and the old `try` on stdout - turn five of the new cases red between them. 30 cases in `cli-test.bash` before, 45 after.
	- Test case: `EqAb38a`, `EqAb38b`, `EqAb38c`, `EqAb38d`, `EqAb38e`, `EqAb38f`, `EqAb38g`, `EqAb38h`, `EqAb38i`, `EqAb38j`, `EqAb38k`, `EqAb38l`, `EqAb38m`, `EqAb38n`, `EqAb38o`.
	- Opened: 20260801-090104
	- Closed: 20260917-224500

- ✅ The installers' system-wide destinations are untested.
	- Done: `installer-test.bash` patches a second pair of copies with `/opt` and `/usr/local` moved under its scratch tree, so `--target system` runs with no root anywhere. `sudo` is a shim that runs the command as-is and records that it was asked.
	- Done: covers where the install lands, that the link is a symlink onto it, that nothing is written under `HOME`, that a re-run fetches nothing, and that uninstall takes both the directory and the link. `install.bash` also has to elevate, and say so in the plan beforehand; the user target has to not.
	- Verified: three injected faults - a system target writing into `HOME`, a missing `sudo` prefix, and an uninstall that leaves the link - each fail the new cases.
	- Note: 28 cases before, 49 after.
	- Test case: `EqANb6u` through `EqANb7B`.
	- Opened: 20260804-224440
	- Closed: 20260917-210000

- ✅ Decide whether hashed host and user names need a salt.
	- Decided: supplied, not built in. A constant compiled into a public binary is public, so it would only have defeated a plain SHA-256 table, and it would have changed every identifier ever generated.
	- Done: `--salt` on the command, `Request.Salt` in Go, `zuid_set_salt` in the C module. Empty by default, and an empty salt hashes the name on its own, so the existing 190 vectors are untouched.
	- Done: 11 new vectors cover the salted case, including an empty salt, a one-byte difference, a wide base and a literal name ignoring it.
	- Note: a salt on a command line shows in the process list. Said so in the help and in `design.md`.
	- Test case: `EqAI7se`, `EqAI7sf`, `EqAI7sg`, `EqAI7sh`, `EqAI7si`, `EqAI7sj`, `EqAI7sk`, `EqAI7sl`.
	- Opened: 20260802-135041
	- Closed: 20260917-184500

- ✅ No UI and UX style guide for the command. Write down how help, flags, output and errors are laid out, and point `README.md` at it.
	- Done: `style-guide_cli.md` covers streams and exit codes, flag spelling and value attachment, the shape of an error message, the order of the help screen, and what `--version`, `--about` and `--donate` each print.
	- Done: every claim in it was read off the built command rather than from the source, so it describes what a user meets.
	- Note: it turned up one message that does not follow the convention. Filed as a bug; the guide names it as the exception meanwhile.
	- Test case: `EqA4qmO`. The guide's content was read off the command by hand.
	- Opened: 20260917-104114
	- Closed: 20260917-133000

- ✅ Nothing points at `style_guide.md`. `README.md` should, and so should `contributing.md`, whose style section is still a commented-out stub.
	- Done: `README.md` has a House style section under development setup, listing both style guides and `contributing.md`.
	- Done: `contributing.md`'s stub is a real Style section now, pointing at both guides, with the commit message rules under it.
	- Test case: `EqA4qmO`.
	- Opened: 20260917-104114
	- Closed: 20260917-133000

- ✅ Give the shared C library a versioned name such as `libzuid.so.1`, to go with the error codes that are kept stable.
	- Done: `build.zig` sets the library version from the one version constant in `core.zig`, dropping the prerelease tag. The build now writes `libzuid.so.1.0.0` with `libzuid.so.1` and `libzuid.so` as symlinks onto it, and the soname a linked program records is `libzuid.so.1`.
	- Done: the header says what the major means, so it is not read as the product version. It moves only if an entry point or an error code does.
	- Verified: the C module stage checks the soname and the symlink chain against the version constant. Dropping the version from `build.zig` turns it red.
	- Note: `package.bash` copies with `cp -P` now. A plain `cp` followed the new symlinks and put three copies of a 28 MB library in the tarball.
	- Origin: code review 20260917-104114, idea I4.
	- Test case: `EqA3RdB`, `EqA3RdC`.
	- Opened: 20260917-104114
	- Closed: 20260917-130524

- ✅ The `.deb` and `.rpm` install the C header but no library. Ship the libraries with it, or leave the header out.
	- Done: the header is out. Both packages install the command and its license, nothing else.
	- Why that way round: the shared library is 28 MB, which doubles the download for everyone who only wants the command, and it would need a per-distro library directory and an `ldconfig` step to be found at all. The tarball already ships the whole C module, including the Wasmtime archive the static library needs.
	- Verified: `installer-test.bash` reads the nfpm contents list and fails if a header is listed with no library. Putting the header entry back turns it red.
	- Note: a proper `-dev` package is the real answer eventually. Listed under Future.
	- Origin: code review 20260917-104114, idea I7.
	- Test case: `EqA3RdA`.
	- Opened: 20260917-104114
	- Closed: 20260917-130524

- ✅ Fuzz the Go module's `Generate` call in the pipeline, and the Zig format parser and C generate call alongside it.
	- Done: `FuzzGenerate` drives the format and base name over a fixed environment, and checks that a failed call returns nothing and that the same request twice returns the same identifier. A full run fuzzes for 20 seconds and retries once on Go's own deadline-as-failure bug.
	- Done: the Zig side has the matching pair, over the core parser and over `zuid_generate`, which also check that a call failing part way through handed every wasm region back.
	- Note: the Zig pair only replays its corpus - fuzz mode does not compile on 0.16.0. Split out as its own item above.
	- Origin: code review 20260917-104114, ideas I3 and I5.
	- Test case: `Eq9zVsG`, `Eq9zVsH`, `Eq9zVsI`.
	- Opened: 20260917-104114
	- Closed: 20260917-131500

- ✅ Check only the widths of components the format uses. A hash width that suits one base failed a plain timestamp in another.
	- Done: both sides scan the format first and check only the widths it spends. `--no-hash` puts the hashed width out of reach the same way. The checks still come before rendering.
	- Origin: code review 20260917-104114, idea I1.
	- Test case: `Eq9xBUf`, `ErOhqzQ`.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Refuse bases with tabs or line breaks among their digits, not only the raw-byte one.
	- Done: `98keyboard` is refused on both sides. Its zero digit is `0`, so the alphabet gets read rather than just that one symbol. There is no export that hands back the alphabet, so the Zig side asks the tokenizer one control byte at a time; the Go side reads the same single-byte digits, so neither refuses what the other accepts.
	- Origin: code review 20260917-104114, idea I2. Next to the raw-byte refusal from the 20260804 review.
	- Test case: `Eq9xBUe`, `Eq9xBUg`, `Eq9xBUi`.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Name the unknown component in the command's error, as the Go module does.
	- Done: the command walks the format the way the core does and quotes the verb. A multi-byte one prints whole.
	- Origin: code review 20260917-104114, idea I6.
	- Test case: `Eq9xBUh`, `ErOiQbX`.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Add to demo GIF: ships as module too.
	- Done: the demo closes on the name and the module note. The random step was cut to stay under 45 seconds.
	- Test case: none. It is a rendered animation, checked by eye.
	- Opened: 20260917-092933
	- Closed: 20260917-101749

- ✅ `--donate`, and a fuller `--about`, the same as shcl.
	- Test case: `ErOiQbc`, `ErOiQbd`, `ErOiQbe`.
	- Opened: 20260917-095900
	- Closed: 20260917-101749

- ✅ Make the licensing clear. The GPL file at the repo root read as covering everything.
	- Done: renamed to `license.md`, which now maps each directory to its license. The modules stay Apache-2.0.
	- Test case: `ErOj0WT`, `ErOiQbd`.
	- Opened: 20260917-100900
	- Closed: 20260917-101749

- ✅ Command help and version output cleaned up.
	- Done: `--hash-chars` is gone from the command. Hashed names always use the width derived from the base, and the libraries can still set it.
	- Done: `--version` prints only the version and build number. The copyright and license moved to `--about`.
	- Done: help and about have a blank line before and after, and the options list has no gaps.
	- Note: the build number is minutes since 2000 in base 32, taken from the commit date.
	- Test case: `ErOiQbW`, `ErOiQbZ`, `ErOiQba`, `ErOiQbb`, `ErOiQbg`.
	- Opened: 20260917-094035
	- Closed: 20260917-094035

- ✅ Release-install scripts, runnable as a one-liner and documented in `README.md`.
	- ✅ `install.bash` for Linux, BSD, macOS, and WSL; `install.ps1` for those plus Windows.
	- ✅ Both verify the download against the published checksums, state their plan, and ask before touching anything. Re-running one changes nothing, and `--uninstall` reverses it.
	- ✅ Both run end to end against the published prerelease: lookup, download, checksum, unpack, link, re-install over an existing copy, and uninstall. Tested against a throwaway home directory rather than a clean machine, so the system-wide destinations are still untried.
	- Test case: `Eq9ejdI`, `Eq9ejdJ`, `Eq9ejdK`, `Eq9ejdL`, `ErOkWfU`, `ErOkWfV`, `ErOkWfY`, `ErOkWfZ`, `Eq9lTwm`, `Eq9lTwn`, `Eq9oNBp`, `Eq9oNBq`.
	- Opened: 20260801-090104
	- Closed: 20260805-014958

- ✅ `jim-collier/zuid` exists and carries `main`, the `v1.0.0-alpha.1` tag, and that prerelease with its x86_64 Linux artifacts.
	- Test case: none. It is state on the git host.
	- Opened: 20260801-090104
	- Closed: 20260805-012556

- ✅ Installing the dogfood build is what a full run does now, rather than something to remember to ask for.
	- Note: daily use is always the build that just passed.
	- Done: a quick run skips it, `--dogfood` forces it there, `--no-dogfood` turns it off, and a machine with nowhere to install says so instead of failing.
	- Test case: none. Every full run shows the stage.
	- Opened: 20260805-010000
	- Closed: 20260805-011242

- ✅ A flag's value can attach with `=`.
	- Done: `-b=32c`, `--base=32c`, `-b 32c`, and `--base 32c` are all the same thing. A leading-dash argument splits at its first `=`; anything else passes through, so a format string with an `=` in it still works either way.
	- Fixed: flags that take no value now say so instead of ignoring one silently.
	- Done: the demo and the README examples use the attached form - it makes which value belongs to which flag obvious at a glance, which matters most in a ten-second look.
	- Test case: `ErOiQbN`, `ErOiQbO`, `ErOiQbP`, `ErOiQbQ`, `ErOiQbR`, `ErOiQbS`, `ErOiQbT`, `ErOiQbU`, `ErOiQbV`, `EqAb38d`.
	- Opened: 20260805-004156
	- Closed: 20260805-004817

- ✅ The demo covers both precision extremes, and the screen resets only when the next step would not otherwise fit.
	- Test case: none. It is a rendered animation, checked by eye.
	- Opened: 20260805-000749
	- Closed: 20260805-001410

- ✅ Identifier spec. Drafted in `design.md`, implemented on both sides.
	- ✅ One time encoding (units since the Unix epoch, UTC), replacing the predecessor's four algorithms. Precision stays selectable, carrying its surface forward: -1 minute, 0 second (default), 1 millisecond.
	- ✅ Fixed-width zero padding, which is what actually makes output sortable. Width is derived rather than tabulated, so moving the horizon or a strength target moves the widths with it.
	- ✅ The three open questions are settled: horizon year 3000, precision as above, same-tick repeats stay literal with a warning once multi-emit exists.
	- Test case: `ElmNxqS`, `EloUhiz`, `ElmNxqU`, `Em32NzU`, `Em32Nzb`, `Elom8tE`, `ErOiQbL`, `ErOiQbM`.
	- Opened: 20260801-090515
	- Closed: 20260804-234122

- ✅ Two implementations of one spec: Go, and Zig. See `design.md`.
	- ✅ Repo, folder layout, and the architecture decisions behind the split.
	- ✅ Shared test vectors (`testdata/vectors.tsv`), which both must reproduce.
		- ✅ Time-only rows, across the narrow curated bases and all three precisions, including truncation and horizon-boundary rows. Sort guarantee checked against them.
		- ✅ Rows for the other components, then for the wide bases, then for the derived widths: 190 in total. An `env` column carries the injected host, user, FQDN, hardware address, random stream, and width options, so a row states only what it cares about.
		- ✅ Expected values come from a third independent derivation, worked from `design.md` rather than from either implementation, so agreement between the two cannot just mean they are wrong the same way.
	- Test case: `ElmNxqS`, `EloUhiz`.
	- Opened: 20260801-090104
	- Closed: 20260804-234122

- ✅ A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- ✅ Drives both toolchains, checks a version floor on each, and says which one is missing rather than failing somewhere later. `--only go|zig` narrows it to one, and then only that one has to be installed.
	- ✅ Go stage builds, vets, checks formatting, and runs the vectors under the race detector. `--cross` compile-checks the three cross targets; there is no binary to emit, since the Go side is a module.
	- ✅ Refuses `--commit` on a protected branch or a detached HEAD, so the script cannot be the thing that puts work straight on `main`.
	- ✅ Zig stage vendors what it needs rather than assuming a system install.
	- ✅ Zig stage builds ReleaseSafe, replays the vectors under both Wasmtime compilers, checks `zig fmt`, and then compiles the C smoke test with the system gcc or clang in both link modes. It skips that last part with a note if neither compiler is installed.
	- ✅ Packaging for the host platform. `--package` builds a tarball, the bare binary, `.deb`, `.rpm`, and checksums.
	- Test case: `ErOjF74`, `ErOjF76`, `ErOjF77`, `EloUhiz`, `ElpGOHZ`, `ElpGOHa`, `EloMht2`, `EloMht3`, `EloMht4`.
	- Opened: 20260801-090104
	- Closed: 20260804-224440

- ✅ CI/CD pipeline filled out.
	- ✅ Refreshes from the remote before building rather than at publish time, so what gets pushed is what was tested. `--no-sync` skips it.
	- ✅ `--quick` skips the slow stages; `-m` takes the commit message, and without it the message is asked for up front rather than after the build.
	- ✅ No stage gets more than half the machine's cores.
	- ✅ Every run is logged, profiled, and rotated under `cicd/artifacts/`, which is not committed.
	- ✅ Profiling produces a flamegraph and a hotspot summary each run. The command's own profile needs `kernel.perf_event_paranoid` below 3, and says so when it cannot record.
	- ✅ A demo animation is rendered from a scenario file and copied to `assets/demo.gif`.
	- ✅ `--dogfood` installs the release build; `--package` builds the host platform's artifacts.
	- Test case: none. These are how the pipeline runs, and every run shows them.
	- Opened: 20260804-213000
	- Closed: 20260804-224440

- ✅ Environment values are read once per process rather than once per component.
	- Note: enumerating network interfaces cost twenty times the base conversion it fed, and resolving a qualified name could block on the network.
	- Verified: the full seven-component format went from about 700 to about 210 microseconds.
	- Test case: `Eq9mpyS`, `Eq9mpyT`, `ErOhqzP`. The speed is profiled, not asserted.
	- Opened: 20260804-213000
	- Closed: 20260804-224440

- ✅ Development setup documented in `README.md`, with prerequisites, what each optional tool buys, and the build commands. No separate script: `cicd.bash` already fetches everything the build needs.
	- Test case: none. It is prose.
	- Opened: 20260801-090104
	- Closed: 20260804-224440

- ✅ Real README, replacing the template. Installation, development setup, and the demo animation are in it.
	- Test case: `EqA4qmP`. The rest is prose.
	- Opened: n/a
	- Closed: 20260804-224440

- ✅ The wide bases joined the curated set, and the upstream dependency moved to a release.
	- ✅ Curated set is now **16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz**, default still 62. `tt` up to 512, `tz` above it, which is where `tt` stops existing.
	- ✅ Padding and truncation both delegate to the library's one right-align call, so the two implementations cannot drift on half a policy each.
	- ✅ The multi-byte-digit refusal is gone. Every component works in every base, which is what made the wide families usable at all. Its C error code is retired rather than renumbered.
	- ✅ `%r` draws enough bytes to fill its symbols. One byte each still covers everything up to 256; above that a symbol carries more than eight bits and the leading one would otherwise never vary.
	- ✅ `go.mod` pins the published release; the local `replace` directive is gone. The reactor wasm is built from that same pinned version instead of copied from a neighboring checkout.
	- ✅ Vectors grew 115 -> 187. The new rows come from a third independent derivation, which reproduces all 115 existing rows before generating any new one.
	- Test case: `ElmNxqS`, `EloUhiz`, `Em2hrcO`, `Em2hrcP`, `Em2hrcQ`, `Em2hrcR`, `ErOj0WV`.
	- Opened: 20260802-143233
	- Closed: 20260804-210541

- ✅ Curated base list, in the help output and in both implementations: **16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz**, default 62. Help builds the line from the list itself, so the two cannot drift. `--base` still accepts any base the library knows, and an unknown one gets the library's near-match suggestion. The `zuid-go` command that first carried it was dropped - the Go side is module-only.
	- Decided: the RFC 4648 base 64 variants were dropped. Their alphabet does not sort, and they need the same 8 characters as base 62, which does.
	- Decided: the wide families were added once truncation worked in them. `tt` up to 512, `tz` above it - below 512 the two are one alphabet under two names, at 512 they genuinely differ, and past it only `tz` continues.
	- ✅ Alphabets reconciled against `convertbase`. Its `32w` is the same 32 symbols the vectors assume, reached by the same alias, so every row reproduces through the real library rather than a local table.
	- Test case: `ElmNxqX`, `ErOiQbf`, `ErOiQbh`.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ Upstream the reactor WebAssembly build to `convert-base-v2`. This gated the whole Zig and C side.
	- ✅ Upstream has already designed it, in more depth than anything drafted here. Nothing to propose; do not relitigate their choices.
	- ✅ Sent them zuid's requirements: base metadata (radix and padding symbol) for fixed-width padding, a symbol count rather than a byte count, a stable error enum, and the error text. No streaming needed - inputs are about 13 bytes, so the one-shot surface alone unblocks this side.
	- ✅ Upstream now has a working reactor build. Streaming is still in progress there, but zuid does not use it, so the gate on the Zig side is lifted.
	- ✅ Released, and it exports the symbol slice, the right-align call, and the combined convert-and-fit call this side asked for. zuid builds the module from that pinned release rather than embedding a prebuilt copy.
	- Test case: `EloUhj1`. Every Zig test runs through the module it produced.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ Base conversion comes from the sister project `convert-base-v2`, not reimplemented.
	- ✅ Go side imports `convertbase` directly, now at the published `lib/v0.1.0` rather than through a local `replace`. Goal 3 met: the package works as imported, no changes needed to it.
	- ✅ Padding, truncation, and symbol slicing all come from the library too, so the one piece of policy both implementations share is defined in exactly one place.
	- ✅ Zig side reaches it through a reactor WebAssembly module, hosted by a vendored Wasmtime. Goal 4 met: the module is embedded in the binary, all vectors reproduce through it, and its region ledger stays at zero.
	- Test case: `ElmNxqS`, `EloUhiz`, `EloUhj1`.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ The remaining components are done on both sides, and the vectors grew from 72 rows to 115.
	- ✅ The `Converter` interface now carries a from-base, since hashes, hardware addresses, and UUIDs all arrive as hex rather than decimal.
	- ✅ Zig gained an `Env` interface next to it, so the core still touches neither the runtime nor the operating system.
	- Test case: `ElmNxqS`, `EloUhiz`, `ElpGOHX`.
	- Opened: 20260802-020157
	- Closed: 20260802-135041

- ✅ Component set: time, host, user, FQDN, MAC, UUID, random. Each independent of the others.
	- ✅ Time. An unknown verb is rejected rather than silently dropped, so a format string cannot appear to work.
	- ✅ Host, user, FQDN, MAC, UUID, random, on both sides.
	- ✅ Every component is a fixed symbol count wide, so an identifier can be split by offset - not only sorted. The one exception is an unhashed name, which is text.
	- ✅ `%m` takes the lowest-numbered non-loopback interface rather than the predecessor's default-route one, which would need the routing table on three platforms.
	- ✅ `%g` is a real UUID v4, rendered as the 128-bit number rather than the dashed text form, which does not sort.
	- ✅ Padding and truncation both come from the conversion library, in one call that right-aligns a value to an exact symbol count. Truncation used to be refused in a base with multi-byte digits; the library slices by symbol now, so every component works in every base.
	- Test case: `ElmNxqT`, `ElpGOHQ`, `ElmNxqV`, `Eq9kVKs`, `ElpGOHX`.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Host, user, and FQDN hashed by default, with an explicit opt-out. SHA-256, rightmost few symbols; `--no-hash` emits the names literally and `--hash-chars` resizes them.
	- Test case: `ElpGOHR`, `Eq9kVKk`.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Confirm the hashed host/user components cannot be reversed to the originals.
	- ✅ Not reversible by construction: a hashed component keeps about 47 bits of a 256-bit SHA-256 whatever the base, discarding more than 200, so nothing can be inverted back to a unique name.
	- Note: a dictionary attack was the open half of this, and `--salt` closed it on 20260917.
	- Test case: none. It holds by construction. The width it rests on is pinned by `Em3M9HE` and `Em3M9HG`.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Every environment source injectable, so output is reproducible under test. Go has `WithClock`/`WithFixedTime`/`WithRandom`/`WithHostname`/`WithUsername`/`WithFQDN`/`WithMAC`; Zig has an `Env` interface alongside the existing `Converter`, with `env.zig` as its one live implementation.
	- Test case: `ElmNxqS`, `EloUhiz`. The vectors only reproduce because every source is injected.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Random component from a cryptographic source. Go uses `crypto/rand`; Zig uses `getentropy` through libc, because 0.16 moved randomness onto `Io` the same way it moved the clocks, and the C module has no `Io` to hand it.
	- Test case: `ElpGOHS`, `ElpGOHY`. Which source is used is read from the code, not tested.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Format string selecting and ordering components. Improve on the predecessor's surface rather than porting it.
	- ✅ The CLI exists: `zuid [-b base] [-f format] [-p precision] [--no-hash] [--hash-chars n] [--rand-chars n]`, all seven components plus `%%` literals, unknown verbs rejected with a clear message.
	- ✅ Precision flag: `-p -1|0|1` for minute/second/millisecond, default second - same surface and default as the predecessor.
	- ✅ Two hashing flags rather than the predecessor's six. Per-component widths were exactly the sort of accretion this was meant to improve on.
	- Test case: `ElmNxqV`, `ElmNxqW`, `Eq9kVKs`, `Eq9kVKt`, `Eq9kVKv`, `ErOiQbL`, `ErOiQbM`.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ C module: static and shared library plus `zuid.h`.
	- ✅ Native artifacts: `libzuid.a` (compiler-rt bundled), self-contained `libzuid.so`, and the installed header. Both link modes verified from plain gcc against a fixed clock.
	- ✅ A cicd stage checks it every run, so the C ABI cannot rot unnoticed. It deliberately uses the system compiler - `zig cc` would prove nothing about a foreign toolchain.
	- ✅ Every component reachable from C, with the width options sticky on the context the way precision already was.
	- Note: cross targets are still open.
	- Test case: `EloUhj2`, `ElpGOHZ`, `ElpGOHa`, `Eq9hexE`.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Zig side brought up: `zig/lib` (core, wasm host, C module) and `zig/cmd` (CLI).
	- ✅ Every vector row reproduces through the embedded module, under both of Wasmtime's compilers.
	- ✅ The C header verified from plain gcc, shared and static.
	- ✅ Every CLI run exercises the upstream module end to end, which was the point of making the CLI Zig-only.
	- Test case: `EloUhiz`, `ElpGOHZ`, `ElpGOHa`.
	- Opened: 20260802-101509
	- Closed: 20260802-104116

- ✅ Vendor the Wasmtime C API during build rather than assuming it is installed. Pinned version, checksum verified, extracted into `zig/vendor/`. The reactor wasm is built from the pinned convertbase release, so it cannot drift from the version the Go side imports; an already-vendored copy covers an offline build.
	- Test case: none. The checksum is checked on every fetch, and a mismatch test would need a second download.
	- Opened: 20260801-090104
	- Closed: 20260802-104116

- ✅ Memory safety on the Zig side. See `design.md`.
	- ✅ Decided: standard-library allocators, no hand-written or third-party one. The bigger win is the core not allocating at all.
	- ✅ Identifier core takes no allocator - fixed widths, caller-supplied buffer. Same shape serves the C module.
	- ✅ Further than the arena plan: nothing on the Zig side allocates at all. Argv comes from the process-provided arena, Wasmtime owns its own memory, and the C module is one allocation per context.
	- ✅ `std.heap.DebugAllocator` in debug builds, `std.heap.smp_allocator` in release - the C module's context allocation, the only one there is.
	- ✅ Tests turned out to need no allocator; the vectors file is embedded at build time.
	- ✅ What 0.16 actually catches: leaks and double frees, yes; use-after-free reads and writes, no. `never_unmap`/`retain_metadata` widen double-free reporting, they do not detect dangling access. There is no AddressSanitizer for Zig code, and `zig cc -fsanitize=address` does not link.
	- Note: the sanitizer run on the vendored Wasmtime is deferred.
	- Test case: `Eq9icWm`. Use-after-free cannot be caught, as the item says.
	- Opened: 20260802-012055
	- Closed: 20260802-104116

- ✅ Both modules Apache-2.0; the command stays GPL-2.0-or-later.
	- ✅ Per-directory license files, all `.txt`: repo root and `zig/cmd/` GPL-2.0-or-later; `go/` and `zig/lib/` each Apache-2.0 with a `NOTICE.txt`. Placed ahead of the Zig source so the split is locked in.
	- ✅ Dropping the Go command removed the one awkward case - a GPL command inside the Apache module directory - so no prose has to explain the split anymore.
	- Test case: `ErOj0WT`.
	- Opened: 20260801-090104
	- Closed: 20260802-100930

- ✅ Go module, importable without cgo, keeping static cross-compilation. Builds `CGO_ENABLED=0` for linux/arm64, windows/amd64, and darwin/arm64, now driven by `cicd.bash --cross`.
	- Test case: `ErOgfbn`, `EloMht2`, `EloMht3`, `EloMht4`.
	- Opened: 20260801-090104
	- Closed: 20260802-025417

- ✅ Go side brought up: `go/zuid`. Every vector row reproduces, `gofmt` and `go vet` clean.
	- ✅ Startup is 57 ms, nearly all of it building the base registry. Irrelevant now that nothing user-facing routes through Go.
	- ✅ The `zuid-go` command was later dropped: the CLI is Zig-only, so that every use of it also exercises the upstream WebAssembly module. The module's own tests replay the vectors, which is the differential check from the Go side.
	- Test case: `ElmNxqS`.
	- Opened: n/a
	- Closed: 20260802-020157

- ✅ Move Zig 0.13.0 -> 0.16.0. Installed and verified; 0.13.0 kept alongside so the symlink flips back.
	- ✅ The 0.16 surfaces this project uses: `main(std.process.Init)`, the process arena, `Io.File.Writer`, `DebugAllocator`, and a render path that takes no allocator.
	- ✅ `zig fmt` uses four spaces and cannot be configured, so Zig source is spaces, not tabs. See `style_guide.md`.
	- Test case: `ErOjF74`, `ErOjF75`. The version floor itself is checked every run.
	- Opened: 20260801-090104
	- Closed: 20260802-014045

- ✅ Trimmed the `x9muid1` reference copy from 3039 lines to 1280, so it can be read for what it actually does.
	- Done: dropped the debug-trace, unit-test, and sudo scaffolding, plus the ~1600-line generic library that nothing in it called.
	- Verified: same output and exit codes across every dtalgo, precision, hashing setting, and error path.
	- Test case: none. It is a reference copy, not built or shipped.
	- Opened: n/a
	- Closed: 20260802-010143

- ✅ Code review 20260804, the enhancement half.
	- ✅ Code review 20260804 item 5: component widths carry a strength rather than a symbol count.
		- Cause: a symbol is worth four bits in base 16 and eleven in 2048tz, so the fixed 8-and-6 defaults promised a strength they only delivered in base 62. `%r` was 36 bits there and 24 in base 16, where a birthday collision arrives after about four thousand draws.
		- Fixed: the default width is now derived from a target - 47 bits for a hashed name, 35 for `%r`, which is what 8 and 6 base-62 symbols have always held - so the strength stays put and the width moves: 12 and 9 symbols in base 16, 5 and 4 in 2048tz. Base 62 is unchanged.
		- Note: this is the rule `%d`, `%m`, and `%g` already followed, so all seven components now size themselves one way instead of two.
		- Note: 72 vector rows changed and 3 were added, 190 in total. `--hash-chars` and `--rand-chars` still override; zero now means "use the derived width" on every surface.
		- Test case: `Em3M9HE`, `Em3M9HG`, `ElpGOHV`, `ElmNxqS`, `EloUhiz`.
	- ✅ Code review 20260804 item 7: a hashed component wider than the digest is refused.
		- Cause: `Fit` left-fills, so asking for more symbols than a SHA-256 supplies in that base gave leading padding - at 64 symbols in 2048tz, 40 constant then 24 real. The identifier got longer with no more fingerprint behind it, and nothing said so.
		- Fixed: the ceiling is now derived per base, 64 symbols in base 16 down to 24 in 2048tz, and asking past it is an error naming the number. Refusing rather than capping matches how a past-horizon clock, an unknown verb, and a raw-byte base are already handled.
		- Done: vectors gained a row per wide base sitting exactly on the ceiling.
		- Test case: `Em3M9HF`, `Em3M9HH`.
	- ✅ Code review 20260804 item 17: one crossing into the WebAssembly module per component instead of four.
		- Cause: every component converted, then asked the radix, then counted symbols, then fitted - and each call marshalled the base name in and a result region back out.
		- Done: the module's combined convert-and-fit call does the work in one crossing. The radix is cached on the host, and `%d`'s overflow check became arithmetic against the horizon, which is the same test the symbol count was making.
		- Verified: the seven-component format went from about 220 to about 175 microseconds, and `%d` and `%m` - one component each, so nearly all round trip - from about 25 to about 17.
		- Note: the converter interface lost two of its five calls, and the padded and truncated paths merged into one, since fitting covers both.
		- Test case: none. It is a speed change, profiled each full run rather than asserted.
	- Opened: 20260804-213000
	- Closed: 20260804-234122

### Deferred

- ✋ CLI startup is ~0.5 s, nearly all of it the module's own `_initialize` building the base registry inside the wasm. Options if it starts to matter: ask upstream about lazier registry construction, or cache a precompiled module per machine. Deferred until the surface settles.
	- Opened: 20260802-104116

- ✋ Sanitizer run on the vendored Wasmtime. The vendored artifact turned out to be a prebuilt archive, so there is nothing local to instrument; revisit only if it is ever built from source here.
	- Fixed: `design.md` described this as a pipeline step. It now says no stage runs one, and why. (20260917)
	- Opened: 20260802-012336

- ✋ Swap Wasmtime for a small interpreter such as wasm3 if vendoring proves painful. Speed is not the deciding factor.
	- Opened: 20260801-090104

- ✋ Hand-written bindings for other languages, if the C module turns out not to cover them.
	- Opened: 20260801-090104

- ✋ A `-dev` package, so the C module can be installed by a package manager rather than unpacked from the tarball. Needs the shared library in each distro's own library directory and an `ldconfig` step after it, which is a second nfpm config and a postinstall script. The tarball covers the same ground meanwhile.
	- Opened: 20260917-130524

### Canceled

- 🚫 No logo. `README.md` dropped the template's `assets/logo.png` references since there is no `assets/`.
	- Note: `assets/` exists now, but holds only the demo animation.
	- Opened: 20260801-090104

## Template

### Old format

- 🔘 Not started

- 🛠️ Started, and/or partially complete

- 🔬 Testing not started or finished

- ✋ Defer

- ✅ Complete

- 🚫 Canceled

### New format

- Notes:

	- Only use rows that you actually need or expect will be filled in. Always fill in the title, ID, Type, Status, Opened and Created by.

	- The ID is the local time to the hundredth of a second. Opened is when it was written down, which may differ. (Use a keyboard macro and possibly something like project 'zuid' to generate.)

	- Status values meaning: Testing means the fix is in and checks are running or still to run. Waiting on signoff means automated testing passed. Moot means something else changed that made it irrelevant. Canceled means it still applies but was decided against. Waiting for testing means the fix is in and waits on a long CI run or an outside test host. Can't reproduce means a real attempt to reproduce it failed.

	- As issues are worked, and statuses change, place them in correct sorting order within the list:
		- First by status: Waiting for answers, Waiting on signoff, Testing, Waiting for testing, Can't reproduce, Stalled, Started, Queued, Done, Deferred, Canceled, Moot
		- Then by severity|priority: Critical, High, Avg, Low
		- Then by type: Bugs, [not bugs together]

	- Rows marked [Bug] are for bugs only, and rows marked [Feature] for features and enhancements. Priority and Severity share one row and one scale. Priority is for a Feature or Enhancement, and Severity for a Bug. Children are not nested. They sit at the top level and point back with Parent ID.

Template:

- Title
	- ID: YYYYmmDDHHMMSSNN
	- Type: [Bug|Feature|Enhancement|Task]
	- Status: [Queued|Waiting for answers|Waiting on signoff|Waiting for testing|Started|Testing|Stalled|Can't reproduce|Moot|Canceled|Deferred|Done]
	- Needs local test suite run?:
	- Needs external testing:
	- Priority [Feature|Enhancement] | Severity [Bug]: [Critical|High|Avg|Low]
	- Opened:
	- Opened by:
	- Assigned to:
	- Parent ID:
	- Prereq IDs:
	- Related IDs:
	- Target OS:
	- Test environment:
	- Version and build:
	- Requirements  [Feature]:
		- Hierarchical bulleted list.
	- Steps to reproduce [Bug]:
		- …
	- Incorrect behavior [Bug]:
	- Expected behavior [Bug]:
	- Reproduced [Bug]: [No, or when, where and how]
	- Possible cause [Bug]:
	- Actual cause [Bug]:
		- …
	- Estimated effort: [High|Avg|Low]
	- Actual effort: [High|Avg|Low]
	- Progress log:
		- …
	- Decisions:
		- …
	- Actual fix [Bug]:
	- Branch:
	- Commit:
	- Test case: [Reason not applicable, or CI test case #]
	- Acceptance signoff:
	- Superseded by ID:
	- Closed:
