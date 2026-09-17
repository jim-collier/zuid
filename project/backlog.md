<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

<!-- TOC ignore:true -->
# Requirements

This is a product backlog just for pre-v1.0.0 release. After that, bugs, features, and enhancements will be managed in Github Issues.

<!-- TOC ignore:true -->
## Table of contents
<!-- TOC -->

- [Conventions](#conventions)
- [Backlog](#backlog)
	- [Bugs](#bugs)
	- [New features and enhancements](#new-features-and-enhancements)
	- [Done](#done)
		- [Done - Bugs](#done---bugs)
		- [Done - New features and enhancements](#done---new-features-and-enhancements)
	- [Future and/or deferred](#future-andor-deferred)
	- [Canceled](#canceled)

<!-- /TOC -->

## Conventions

In each section, items are listed approximately from newest to oldest. Inside Done, loose items come first and code-review rounds after, each run newest first.

An item moves to its matching section under [Done](#done) once it is finished. One that is mostly done gets split: the finished part goes under Done, and the rest stays open.

| Icon | Status
| :--: | :--
| 🔘   | Not started
| 🛠️   | Started, and/or partially complete
| ✋   | Defer
| ✅   | Complete
| 🚫   | Canceled

Each item lists the date it was opened, and the date it was closed once finished. "n/a" means the open date is not known. A deferred item keeps only its opened date.

Notes under an item lead with what they are, such as `Cause:`, `Fixed:`, `Done:`, `Verified:` or `Note:`, so an item can be skimmed by its prefixes.

## Backlog

### Bugs

None open.

### New features and enhancements

- 🔘 Run the Zig fuzz tests in fuzz mode, once a Zig release can build one.
	- Note: the tests are written and replay their corpus on every run. `zig build test --fuzz` fails to compile inside 0.16.0's own test runner, so nothing on this side can fix it. `details.md` has the error.
	- Opened: 20260917-131500

- 🔘 `%m` is Linux-only on the Zig side - it reads `getifaddrs` for `AF_PACKET`, and macOS wants `AF_LINK` instead. The Go module is already portable, and the help text and the C header both say so. Do it alongside the cross targets, since nothing on the Zig side cross-compiles yet either.
	- Should work on Windows too.
	- Opened: 20260802-135041

- 🔘 Packaging for other platforms. Needs a Wasmtime archive vendored per target. Blocked on that, and on the Zig side building for Windows at all.
	- Opened: 20260802-025417

- 🔘 Publishing. `--publish` stays rejected with a reason until there is somewhere to publish to.
	- Note: GitHub releases is that place now. `v1.0.0-alpha.1` was published there by hand.
	- Opened: 20260802-025417

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
	- Opened: 20260801-090104

### Done

#### Done - Bugs

- ✅ `install.ps1 -Target system` with nowhere to write downloaded and verified the whole release, then threw a raw permissions error from `New-Item`.
	- Cause: the writability test only ran when no target was named. Asked for by name it was taken on trust, and the write is the last thing the script does. There is no elevation on that side the way `install.bash` has sudo.
	- Fixed: one predicate now answers both questions, and it tests the install directory as well as the link directory - a box where `/usr/local/bin` is writable but `/opt` is not used to pick a system install and fail late. With no target named it still falls back to a user install; asked for by name it stops before downloading and names `-Target user`.
	- Note: found while writing the system-target cases. `install.bash` needs no equivalent.
	- Opened: 20260917-203000
	- Closed: 20260917-210000

- ✅ One error message read in a different style from every other one. An unknown base came back as the conversion library's own text: lower case, double quotes.
	- Fixed: the command writes its own sentence and keeps the near match the library found, so a typo now reads `Unknown base 'nope'. Did you mean 'nice'?`. With no near match it says where the list is.
	- Fixed: a blank base name is refused by the command too. It used to reach the library as empty and come back as `empty base name`.
	- Note: `style-guide_cli.md` narrows its exception to a failure inside the wasm runtime, which is internal and not about anything the user typed.
	- Opened: 20260917-133000
	- Closed: 20260917-140000

- ✅ A base name long enough to push the library's message past the 512-byte error buffer lost the error code with it, so a typo came back as `Generation failed: ConvertFailed`.
	- Cause: reading the message refused rather than truncating, and the read failing threw away the code that came with it.
	- Fixed: the text is clamped to what fits, on a codepoint boundary, and the code always survives.
	- Note: found while testing the message above.
	- Opened: 20260917-140000
	- Closed: 20260917-140000

- ✅ Several `.md` files ran their top-level bullets tight, with no blank line between them.
	- Fixed: `contributing.md` and `style_guide.md` are spaced. Auto-generated table of contents blocks are left alone, as the convention says.
	- Decided: `contributing.md` gets reflowed like anything else here, and its generator banner, attribution footer and commented-out template sections are gone. A document that advertises where it was generated from is not wanted.
	- Fixed: same file picked up the `markdownlint-disable` header every other document here has, and a blank quote line in the two block quotes that needed one.
	- Opened: 20260917-133000
	- Closed: 20260917-140000

- ✅ Contact address in `trademark.md` was still a placeholder.
	- Fixed: `zuid@yottacore.com` in `trademark.md`, `contributing.md` and `code_of_conduct.md`. The last one still named the project it was copied from.
	- Opened: 20260801-090104
	- Closed: 20260917-124100

- ✅ The `.deb` and `.rpm` checksums did not match the downloaded files.
	- Cause: GitHub rewrites `~` to `.` in an uploaded filename.
	- Fixed: both are named that way to begin with, so `checksums.txt` matches what a downloader ends up with.
	- Note: the version recorded inside each package still carries the `~` that sorts it ahead of the final release.
	- Opened: 20260805-014016
	- Closed: 20260805-014958

- ✅ A default install found no release while only a prerelease was published.
	- Cause: the installers asked for `latest`, which only ever answers with a final release.
	- Fixed: the release is chosen from the full list. Default takes the newest stable and falls back to the newest prerelease with a line saying so; `--release dev` takes whatever is newest either way.
	- Opened: 20260805-014016
	- Closed: 20260805-014958

- ✅ Code review 20260917-104114. Defects by finding id and rank. Details are in the review document.
	- ✅ F4, blocking: several C module error codes are checked by no test, so a renumbering would go unnoticed.
		- Origin: 8ba15ef, the 20260804 review fixes, which added codes 12 and 13. Confirmed.
		- Fixed: codes 2, 6, 12 and 13 are now asserted at the C surface, in both the Zig test and `capi_smoke.c`.
		- Verified: three separate renumberings of `codeFor` each turn both runners red, and the codes they pin go green again once restored.
		- Note: code 10 is left unpinned. It needs a machine that cannot supply a component, and nothing available can stage that.
	- ✅ F8, blocking: the PowerShell installer finds no release at all once more than one is published.
		- Origin: 39f7403, the fix for the earlier "default install found no release" bug. Confirmed.
		- Cause: `Invoke-RestMethod` hands a JSON array to the pipeline as one object, so `@(irm ...)` inline gave a single element holding the whole list, and each release's `draft` flag was then tested as an array.
		- Fixed: the response goes into a variable before it is wrapped. It was the only site of that pattern; the two `Invoke-WebRequest -OutFile` calls do not go through the pipeline.
		- Done: `cicd/utility/installer-test.bash` is new, and runs both installers against a local four-release listing. It is a cicd stage, and the copies it patches assert every rewrite, so a script that moves its URLs fails the harness rather than testing nothing.
		- Verified: reverting the lookup turns both ps1 cases red with "no published release found", which is the reported symptom. A single-release listing still reads correctly.
	- ✅ F9, blocking: `package.bash` wipes whatever directory `--out` names, before it builds anything.
		- Origin: 08c6996. Not seen by an earlier review. Confirmed.
		- Fixed: a `--out` directory is only emptied when the script can show it is one of its own - it left a `.zuid-package-dir` marker there, or the directory is empty or new. Anything else is refused by name. The default `dist/` counts as the script's own, since the script picked that path rather than a caller.
		- Fixed: the clearing moved to after the build, so a failed build now leaves the previous run's artifacts alone. The check still runs up front, so a mistyped `--out` fails in a second rather than after a ReleaseSafe build.
		- Fixed: the contents are cleared rather than the directory itself, so a mount point or a directory with granted permissions survives being reused.
		- Verified: four cases in `installer-test.bash`. Restoring the old `rm -rf "${OUT}"` turns the first two red. Repeated real runs against `dist/` replace the artifacts, and the marker is hashed by nothing and counted in nothing.
	- ✅ F1, should-fix: the shared C library exposes every Wasmtime function it contains, so a program with its own copy takes over the library's calls.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: `zig/lib/zuid.map`, a linker version script naming `zuid_*` global and everything else local. Exports went from 834 to 11. The local half is what matters: the library's internal calls now bind inside it and cannot be displaced at all.
		- Done: two cicd checks. One asserts nothing but `zuid_*` is exported; the other is `zig/lib/test/capi_interpose.c`, a program that defines `wasm_config_new` and must still get a working context.
		- Verified: dropping the version script reports 823 stray symbols and fails the stage. Before the fix that program got a NULL context and its own function was called.
	- ✅ F2, should-fix: the static C library holds the Wasmtime archive inside itself, where no linker looks, and the release has no separate copy to link.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: the static module no longer links the Wasmtime archive, so `libzuid.a` holds its own two objects and went from 75 MB to 9.8 MB. Whoever links it supplies Wasmtime, which is what the header always said.
		- Fixed: `package.bash` puts `libwasmtime.a` in the release `lib/`, so the link line the header prints has something to satisfy it.
		- Fixed: member names are re-archived on basenames, so a published archive no longer carries the build machine's cache paths. That needs llvm-ar, since GNU ar lists the members Zig writes and then cannot address them; without it the step warns instead of failing.
		- Fixed: the header's linking paragraph now says where `libwasmtime.a` comes from, and that the shared library exports only the entry points.
		- Done: two cicd checks. One links the smoke test against a tree holding only what is released, with the header's own link line, deliberately not pointed at `vendor/`. The other refuses an archive with another archive inside it.
		- Verified: restoring the nesting fails the archive check. The review's reproduction - a tree holding only `libzuid.a` and `zuid.h` - failed with "have you installed the static version of the wasmtime library ?" before, and the unpacked release tarball now links both static and shared.
	- ✅ F3, should-fix: a C context that is never freed is not reported as a leak, in tests or in debug builds.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Cause: nothing could call the debug allocator's own check. A C caller never says it is finished, so there is no last moment for a `deinit()` to run in.
		- Fixed: `capi.liveContexts()` and `capi.leakCount()` let the tests ask instead, the second one straight through `DebugAllocator.detectLeaks()` so the stack traces the design promises are real. Both are debug-only, so a release build carries no counter.
		- Verified: the review's own injection - replacing the three `defer capi.zuid_free(z)` lines with `_ = &z` - reports "expected 0, found 3", and the allocator half names all three leaked addresses on its own when checked first.
		- Note: the test deliberately does not free twice. The magic check reads memory the allocator has unmapped, so it segfaults rather than returning, which is the recorded reason the header promises no more than C's `free()`.
	- ✅ F5, should-fix: the C module reports a buffer too small for any identifier over 4 KB, however large the caller's buffer, and that error never has a message.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: `zuid_generate` renders straight into the caller's buffer, less the byte the NUL needs, so the only limit is the one the header documents. The error path now re-terminates that buffer, since a failure part way through leaves its own partial output where a separate buffer used to hide it.
		- Fixed: `ZUID_ERR_BUFFER` carries text in all three cases - a short `out_cap`, a zero `out_cap`, and a NULL `out`. The clearing moved above the buffer checks so a rejected buffer reports its own reason rather than the previous call's.
		- Swept: the command had the same fixed 4096 buffer and reported `BufferTooSmall` by its error name. It now grows the buffer until the identifier fits, up to 1 MB, and says so in words past that. The Go module returns a string and never had the limit.
		- Done: `cicd/utility/cli-test.bash` is new - 15 cases over what the command prints and exits with, which nothing covered before - and is a cicd stage.
		- Verified: before the fix all four probe cases returned code 5 with empty text, including two that should have rendered. Reverting the module fails the Zig test and three `capi_smoke.c` checks; reverting the command fails three CLI cases.
	- ✅ F10, should-fix: the PowerShell installer picks a system install on Linux and macOS for users who cannot write there.
		- Origin: 08c6996. Not seen by an earlier review. Confirmed.
		- Cause: the test was whether `/usr/local/bin` exists, which it does everywhere, rather than whether it can be written. The install then failed after the whole download, with no elevation path of the kind `install.bash` has through sudo.
		- Fixed: `Test-DirectoryWritable` writes a probe file into the nearest existing ancestor and removes it, rather than reading a mode or an ACL. On Windows the install directory decides; elsewhere the link directory does, which is what `install.bash` tests.
		- Verified: a new harness case. Before the fix nothing landed under `HOME`; after it, the user install happens. It skips itself where the system location is writable, such as a run as root, since system is then the right answer.
		- Note: an explicit `-Target system` never reaches the probe, so that path is unchanged. Not covered by a test, since a system install needs root.
		- Note: the harness gave every case its own `HOME` only on paper - the counter naming them was incremented inside the command substitution that read it, so the subshell kept the new value and all of them shared one directory. Named directories now.
	- ✅ F11, should-fix: re-running either installer on the installed version downloads and reinstalls it, though both say that is a no-op.
		- Origin: 08c6996. Reopens the done installer item, whose re-run claim had no test. Confirmed.
		- Cause: both read the installed version for the plan's "Replacing" line and neither compared it with the chosen tag.
		- Fixed: both compare, and a match prints "Already installed" with the version and location, then exits without fetching anything. Reinstalling means `--uninstall` first, which the message says.
		- Verified: the harness counts what the local server was asked for, so the no-op is measured rather than taken from the script's own output. Before the fix a re-run made two requests, the tarball and the checksums. A different version still installs over the old one, in both states, so the check is not a blanket refusal.
	- ✅ F12, should-fix: the `go get` line in `README.md` leaves a program that imports the package unable to build, and the prerelease cannot be asked for by version.
		- Origin: 2209333. Not seen by an earlier review. Confirmed.
		- Cause: the line named the module root. `go get` on a root adds the module without what its package needs, so the build stopped on a missing `go.sum` entry for `convertbase`.
		- Fixed: `README.md` names the package, `github.com/jim-collier/zuid/go/zuid`, and says why. It also states that pinning needs a `go/`-prefixed tag, which does not exist yet, and how to pin a commit instead.
		- Done: a cicd stage builds and runs a scratch program importing the module, pointed at this tree so it covers what is about to merge. It also refuses a README that tells people to fetch the module root.
		- Verified: reproduced both halves in a scratch module - the missing `go.sum` entry, and the tag resolving to a pseudo-version of `main`. The corrected command pulls `convertbase` v0.1.0, builds, and prints an identifier. Restoring the old README line fails the stage.
		- Note: the `go/` tag itself is deferred, since pushing a public tag is a release decision.
	- ✅ F13, should-fix: `zuid -f ''` prints an empty identifier and succeeds, where the Go and C modules treat an empty format as `%d`.
		- Origin: 7677deb. Not seen by an earlier review. Confirmed.
		- Fixed: the command treats an empty format as `%d`, so all three surfaces agree. A script running `zuid -f "$FMT"` with the variable unset no longer gets an empty identifier and success.
		- Verified: three CLI cases, covering an empty format, an empty base, and both together. The first and third go red without the fix. An empty base already defaulted correctly.
	- ✅ F14, should-fix: the Go module reads the host name again for every identifier, though the design says each source is read once.
		- Origin: 27d8bc1. Not seen by an earlier review. Confirmed.
		- Cause: `liveFQDN` and `liveMAC` were wrapped in `sync.OnceValues` and `liveHostname` was not, so a long-running process whose name changed emitted two `%h` fingerprints for one machine, and `%h` could disagree with the cached `%f`.
		- Fixed: both `liveHostname` and `liveUsername` are wrapped now. The user name was not actually being re-read, since `user.Current` caches internally, but every source in the file answers the same way now.
		- Done: `go/zuid/live_test.go`, inside the package, counts reads of each of the four sources and asserts at most one per process. Plus a case that two host-name reads agree, which is the property the caching exists for.
		- Verified: unwrapping `liveHostname` reports "read the hostname 5 times". The vectors and `TestLiveSources` still pass.
	- ✅ F6, nit: the C header says a context takes tens of milliseconds to create. It takes about half a second.
		- Origin: 7677deb. Confirmed.
		- Fixed: the header says around half a second, and names the reason - the module building its base registry - since that is why keeping one context matters.
		- Verified: measured 450 to 570 ms over five runs in both Debug and ReleaseSafe, which matches the deferred note on CLI startup. No test; it is a comment.
	- ✅ F7, nit: an empty `SOURCE_DATE_EPOCH` drops the build number instead of falling back to the commit date.
		- Origin: e8442fb. Confirmed.
		- Cause: the value was parsed with `catch 0`, so both an empty and an unparsable one became zero, which means "no build number".
		- Fixed: an empty or whitespace-only value falls through to the commit date, as does an unparsable one, and that last case warns rather than passing silently. `-Dbuild-epoch` still wins over the variable, and a valid value still wins over the commit date.
		- Done: a cicd check builds with the variable empty and asserts a build number. It fails on the old `build.zig`, reporting the bare version.
	- ✅ F15, nit: `install.bash --release` with no value exits without a message.
		- Origin: 08c6996. Confirmed.
		- Cause: with one argument left, `shift 2` fails, and under `set -e` the script ended with nothing printed.
		- Fixed: `fNeedValue` checks first, so the message names the flag and points at `--help`.
		- Swept: `--target` and `--arch` did the same thing and are fixed with it. `install.ps1` needs nothing - PowerShell's own parameter binding already reports a missing argument by name.
		- Verified: three harness cases, one per flag. All three go red on the old script, exiting 1 with empty output.
	- ✅ F16, nit: both installers remove or replace a `zuid` at the link path that they did not put there.
		- Origin: 08c6996. Confirmed.
		- Fixed: both work out whether the link is their own - a symlink pointing into the install directory - before touching anything, since once that directory is gone the link dangles and there is nothing left to recognize. Uninstall keeps anything else and says so.
		- Fixed: install still replaces what is there, which is what an installer does, but the plan now names it rather than doing it quietly.
		- Verified: four cases per installer. A plain file planted at the link path survives uninstall, the output says it is being kept, install names what it overwrites, and the installer's own link is still removed. All go red on the old scripts.
		- Note: this is a real collision, not a hypothetical - `README.md` tells a source build that a full cicd run copies the command to `~/.local/bin`.
	- ✅ F17, nit: `README.md` says nothing is published yet, and `design.md` says "four things" before a list of five.
		- Origin: 2209333. Confirmed.
		- Fixed: "Packages and installers" says `v1.0.0-alpha.1` is published for x86_64 Linux, and points at the source build for every other platform. `design.md` says five.
		- Done: a cicd check reads the count out of that sentence and compares it with the bullets under it. A number in front of a list drifts as soon as the list grows, and no linter counts.
		- Verified: putting "four" back fails the stage with both numbers named.
	- Opened: 20260917-104114
	- Closed: 20260917-121500

- ✅ Code review 20260804. Twelve defects, from an adversarial pass over both implementations and the build script.
	- ✅ Fixed: a raw-byte base produced identifiers full of control characters. Both sides now refuse it.
	- ✅ Fixed: a clock far past the horizon wrapped on the Go side and rendered as the epoch instead of erroring.
	- ✅ Fixed: `WidthFor` never returned for a radix below two.
	- ✅ Fixed: the C module reported the previous call's error text for any failure that never reached the converter, and left the caller's buffer untouched.
	- ✅ Fixed: a clock past the horizon reported a conversion failure with no message. It has its own error code now.
	- ✅ Fixed: pointers coming back from the WebAssembly module were used to index host memory unchecked, and exports were read without checking their kind.
	- ✅ Fixed: a failed clock read returned arithmetic over uninitialized memory.
	- ✅ Fixed: `--commit` swallowed a following flag as its message, and `-h` or `-v` anywhere inside an argument value triggered help.
	- ✅ Fixed: a pre-release toolchain version passed a floor it was actually below.
	- ✅ Fixed: a temporary directory leaked whenever the C module stage failed, and the error trap said nothing for the exit code every failing tool actually uses.
	- ✅ Fixed: the reactor build discarded its own error output, so a failure silently fell back to a stale module.
	- ✅ Fixed: re-pinning the vendored runtime kept whatever was vendored first.
	- Note: its three numbered enhancement items are under Done - New features and enhancements.
	- Opened: 20260804-213000
	- Closed: 20260804-224440

#### Done - New features and enhancements

- ✅ A batch spent about a third of a millisecond an identifier, nearly all of it crossing into the wasm module. Every `generate` re-asked whether the base renders text, which is 33 round trips through the tokenizer with an alloc and a free each.
	- Cause: the 98keyboard fix added the control-byte probe and nothing measured after it. The cost was flat across every format, which is what a per-call fixed overhead looks like.
	- Fixed: the verdict is remembered on the host beside the radix and the zero digit, and thrown away when the slot points at another base. The check itself stays in `core`, since which bytes are refused is spec; only the remembering moved.
	- Verified: 16.6 us an identifier for `%r` against 357 us, and 170 us for all seven against 452 us, measured A/B against a library built from the previous commit. `details.md` has the full table.
	- Verified: an injected fault - the slot not cleared when it is aimed at a new base - turns three cases red, including a new one that alternates good, raw-byte and unknown bases on one host.
	- Done: `--count`'s ceiling goes from 100000 to 1000000, which is the same half a minute of work the old ceiling stood for.
	- Note: a single run still pays the probe once, so nothing there got faster. It is about a third of a millisecond against 600 ms of startup.
	- Opened: 20260917-224500
	- Closed: 20260917-233000

- ✅ Generate more than one identifier per invocation. A time-only format repeats within one tick.
	- Decided: output stays literal - nothing is appended silently - but repeats in one invocation's output get a stderr warning suggesting `%r`.
	- Done: `-n`/`--count`, 1 to 100000, one per line. One run reads the clock once, so a format with nothing random in it comes out the same every line.
	- Done: repeats are counted by what actually matched, not by reading the format, so a narrow `--rand-chars` draw that collides on its own is reported too. Tracked as hashes, so the cost does not depend on how long a format renders.
	- Done: batching belongs to the command. The Go and C modules still hand back one identifier, since a caller there already has a loop.
	- Swept: a reader that quits early used to end in Zig's own error trace and a non-zero exit. A closed pipe now ends the run quietly, on the identifiers and on `--help` alike.
	- Verified: three injected faults - a dropped warning, a dropped ceiling check, and the old `try` on stdout - turn five of the new cases red between them. 30 cases in `cli-test.bash` before, 45 after.
	- Opened: 20260801-090104
	- Closed: 20260917-224500

- ✅ The installers' system-wide destinations are untested.
	- Done: `installer-test.bash` patches a second pair of copies with `/opt` and `/usr/local` moved under its scratch tree, so `--target system` runs with no root anywhere. `sudo` is a shim that runs the command as-is and records that it was asked.
	- Done: covers where the install lands, that the link is a symlink onto it, that nothing is written under `HOME`, that a re-run fetches nothing, and that uninstall takes both the directory and the link. `install.bash` also has to elevate, and say so in the plan beforehand; the user target has to not.
	- Verified: three injected faults - a system target writing into `HOME`, a missing `sudo` prefix, and an uninstall that leaves the link - each fail the new cases.
	- Note: 28 cases before, 49 after.
	- Opened: 20260804-224440
	- Closed: 20260917-210000

- ✅ Decide whether hashed host and user names need a salt.
	- Decided: supplied, not built in. A constant compiled into a public binary is public, so it would only have defeated a plain SHA-256 table, and it would have changed every identifier ever generated.
	- Done: `--salt` on the command, `Request.Salt` in Go, `zuid_set_salt` in the C module. Empty by default, and an empty salt hashes the name on its own, so the existing 190 vectors are untouched.
	- Done: 11 new vectors cover the salted case, including an empty salt, a one-byte difference, a wide base and a literal name ignoring it.
	- Note: a salt on a command line shows in the process list. Said so in the help and in `design.md`.
	- Opened: 20260802-135041
	- Closed: 20260917-184500

- ✅ No UI and UX style guide for the command. Write down how help, flags, output and errors are laid out, and point `README.md` at it.
	- Done: `style-guide_cli.md` covers streams and exit codes, flag spelling and value attachment, the shape of an error message, the order of the help screen, and what `--version`, `--about` and `--donate` each print.
	- Done: every claim in it was read off the built command rather than from the source, so it describes what a user meets.
	- Note: it turned up one message that does not follow the convention. Filed as a bug; the guide names it as the exception meanwhile.
	- Opened: 20260917-104114
	- Closed: 20260917-133000

- ✅ Nothing points at `style_guide.md`. `README.md` should, and so should `contributing.md`, whose style section is still a commented-out stub.
	- Done: `README.md` has a House style section under development setup, listing both style guides and `contributing.md`.
	- Done: `contributing.md`'s stub is a real Style section now, pointing at both guides, with the commit message rules under it.
	- Opened: 20260917-104114
	- Closed: 20260917-133000

- ✅ Give the shared C library a versioned name such as `libzuid.so.1`, to go with the error codes that are kept stable.
	- Done: `build.zig` sets the library version from the one version constant in `core.zig`, dropping the prerelease tag. The build now writes `libzuid.so.1.0.0` with `libzuid.so.1` and `libzuid.so` as symlinks onto it, and the soname a linked program records is `libzuid.so.1`.
	- Done: the header says what the major means, so it is not read as the product version. It moves only if an entry point or an error code does.
	- Verified: the C module stage checks the soname and the symlink chain against the version constant. Dropping the version from `build.zig` turns it red.
	- Note: `package.bash` copies with `cp -P` now. A plain `cp` followed the new symlinks and put three copies of a 28 MB library in the tarball.
	- Origin: code review 20260917-104114, idea I4.
	- Opened: 20260917-104114
	- Closed: 20260917-130524

- ✅ The `.deb` and `.rpm` install the C header but no library. Ship the libraries with it, or leave the header out.
	- Done: the header is out. Both packages install the command and its license, nothing else.
	- Why that way round: the shared library is 28 MB, which doubles the download for everyone who only wants the command, and it would need a per-distro library directory and an `ldconfig` step to be found at all. The tarball already ships the whole C module, including the Wasmtime archive the static library needs.
	- Verified: `installer-test.bash` reads the nfpm contents list and fails if a header is listed with no library. Putting the header entry back turns it red.
	- Note: a proper `-dev` package is the real answer eventually. Listed under Future.
	- Origin: code review 20260917-104114, idea I7.
	- Opened: 20260917-104114
	- Closed: 20260917-130524

- ✅ Fuzz the Go module's `Generate` call in the pipeline, and the Zig format parser and C generate call alongside it.
	- Done: `FuzzGenerate` drives the format and base name over a fixed environment, and checks that a failed call returns nothing and that the same request twice returns the same identifier. A full run fuzzes for 20 seconds and retries once on Go's own deadline-as-failure bug.
	- Done: the Zig side has the matching pair, over the core parser and over `zuid_generate`, which also check that a call failing part way through handed every wasm region back.
	- Note: the Zig pair only replays its corpus - fuzz mode does not compile on 0.16.0. Split out as its own item above.
	- Origin: code review 20260917-104114, ideas I3 and I5.
	- Opened: 20260917-104114
	- Closed: 20260917-131500

- ✅ Check only the widths of components the format uses. A hash width that suits one base failed a plain timestamp in another.
	- Done: both sides scan the format first and check only the widths it spends. `--no-hash` puts the hashed width out of reach the same way. The checks still come before rendering.
	- Origin: code review 20260917-104114, idea I1.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Refuse bases with tabs or line breaks among their digits, not only the raw-byte one.
	- Done: `98keyboard` is refused on both sides. Its zero digit is `0`, so the alphabet gets read rather than just that one symbol. There is no export that hands back the alphabet, so the Zig side asks the tokenizer one control byte at a time; the Go side reads the same single-byte digits, so neither refuses what the other accepts.
	- Origin: code review 20260917-104114, idea I2. Next to the raw-byte refusal from the 20260804 review.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Name the unknown component in the command's error, as the Go module does.
	- Done: the command walks the format the way the core does and quotes the verb. A multi-byte one prints whole.
	- Origin: code review 20260917-104114, idea I6.
	- Opened: 20260917-104114
	- Closed: 20260917-124100

- ✅ Add to demo GIF: ships as module too.
	- Done: the demo closes on the name and the module note. The random step was cut to stay under 45 seconds.
	- Opened: 20260917-092933
	- Closed: 20260917-101749

- ✅ `--donate`, and a fuller `--about`, the same as shcl.
	- Opened: 20260917-095900
	- Closed: 20260917-101749

- ✅ Make the licensing clear. The GPL file at the repo root read as covering everything.
	- Done: renamed to `license.md`, which now maps each directory to its license. The modules stay Apache-2.0.
	- Opened: 20260917-100900
	- Closed: 20260917-101749

- ✅ Command help and version output cleaned up.
	- Done: `--hash-chars` is gone from the command. Hashed names always use the width derived from the base, and the libraries can still set it.
	- Done: `--version` prints only the version and build number. The copyright and license moved to `--about`.
	- Done: help and about have a blank line before and after, and the options list has no gaps.
	- Note: the build number is minutes since 2000 in base 32, taken from the commit date.
	- Opened: 20260917-094035
	- Closed: 20260917-094035

- ✅ Release-install scripts, runnable as a one-liner and documented in `README.md`.
	- ✅ `install.bash` for Linux, BSD, macOS, and WSL; `install.ps1` for those plus Windows.
	- ✅ Both verify the download against the published checksums, state their plan, and ask before touching anything. Re-running one changes nothing, and `--uninstall` reverses it.
	- ✅ Both run end to end against the published prerelease: lookup, download, checksum, unpack, link, re-install over an existing copy, and uninstall. Tested against a throwaway home directory rather than a clean machine, so the system-wide destinations are still untried.
	- Opened: 20260801-090104
	- Closed: 20260805-014958

- ✅ `jim-collier/zuid` exists and carries `main`, the `v1.0.0-alpha.1` tag, and that prerelease with its x86_64 Linux artifacts.
	- Opened: 20260801-090104
	- Closed: 20260805-012556

- ✅ Installing the dogfood build is what a full run does now, rather than something to remember to ask for.
	- Note: daily use is always the build that just passed.
	- Done: a quick run skips it, `--dogfood` forces it there, `--no-dogfood` turns it off, and a machine with nowhere to install says so instead of failing.
	- Opened: 20260805-010000
	- Closed: 20260805-011242

- ✅ A flag's value can attach with `=`.
	- Done: `-b=32c`, `--base=32c`, `-b 32c`, and `--base 32c` are all the same thing. A leading-dash argument splits at its first `=`; anything else passes through, so a format string with an `=` in it still works either way.
	- Fixed: flags that take no value now say so instead of ignoring one silently.
	- Done: the demo and the README examples use the attached form - it makes which value belongs to which flag obvious at a glance, which matters most in a ten-second look.
	- Opened: 20260805-004156
	- Closed: 20260805-004817

- ✅ The demo covers both precision extremes, and the screen resets only when the next step would not otherwise fit.
	- Opened: 20260805-000749
	- Closed: 20260805-001410

- ✅ Identifier spec. Drafted in `design.md`, implemented on both sides.
	- ✅ One time encoding (units since the Unix epoch, UTC), replacing the predecessor's four algorithms. Precision stays selectable, carrying its surface forward: -1 minute, 0 second (default), 1 millisecond.
	- ✅ Fixed-width zero padding, which is what actually makes output sortable. Width is derived rather than tabulated, so moving the horizon or a strength target moves the widths with it.
	- ✅ The three open questions are settled: horizon year 3000, precision as above, same-tick repeats stay literal with a warning once multi-emit exists.
	- Opened: 20260801-090515
	- Closed: 20260804-234122

- ✅ Two implementations of one spec: Go, and Zig. See `design.md`.
	- ✅ Repo, folder layout, and the architecture decisions behind the split.
	- ✅ Shared test vectors (`testdata/vectors.tsv`), which both must reproduce.
		- ✅ Time-only rows, across the narrow curated bases and all three precisions, including truncation and horizon-boundary rows. Sort guarantee checked against them.
		- ✅ Rows for the other components, then for the wide bases, then for the derived widths: 190 in total. An `env` column carries the injected host, user, FQDN, hardware address, random stream, and width options, so a row states only what it cares about.
		- ✅ Expected values come from a third independent derivation, worked from `design.md` rather than from either implementation, so agreement between the two cannot just mean they are wrong the same way.
	- Opened: 20260801-090104
	- Closed: 20260804-234122

- ✅ A CI/CD pipeline kicked off by a bash script (`cicd/cicd.bash`): builds, tests, and can commit and push. Packaging and publishing are opt-in.
	- ✅ Drives both toolchains, checks a version floor on each, and says which one is missing rather than failing somewhere later. `--only go|zig` narrows it to one, and then only that one has to be installed.
	- ✅ Go stage builds, vets, checks formatting, and runs the vectors under the race detector. `--cross` compile-checks the three cross targets; there is no binary to emit, since the Go side is a module.
	- ✅ Refuses `--commit` on a protected branch or a detached HEAD, so the script cannot be the thing that puts work straight on `main`.
	- ✅ Zig stage vendors what it needs rather than assuming a system install.
	- ✅ Zig stage builds ReleaseSafe, replays the vectors under both Wasmtime compilers, checks `zig fmt`, and then compiles the C smoke test with the system gcc or clang in both link modes. It skips that last part with a note if neither compiler is installed.
	- ✅ Packaging for the host platform. `--package` builds a tarball, the bare binary, `.deb`, `.rpm`, and checksums.
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
	- Opened: 20260804-213000
	- Closed: 20260804-224440

- ✅ Environment values are read once per process rather than once per component.
	- Note: enumerating network interfaces cost twenty times the base conversion it fed, and resolving a qualified name could block on the network.
	- Verified: the full seven-component format went from about 700 to about 210 microseconds.
	- Opened: 20260804-213000
	- Closed: 20260804-224440

- ✅ Development setup documented in `README.md`, with prerequisites, what each optional tool buys, and the build commands. No separate script: `cicd.bash` already fetches everything the build needs.
	- Opened: 20260801-090104
	- Closed: 20260804-224440

- ✅ Real README, replacing the template. Installation, development setup, and the demo animation are in it.
	- Opened: n/a
	- Closed: 20260804-224440

- ✅ The wide bases joined the curated set, and the upstream dependency moved to a release.
	- ✅ Curated set is now **16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz**, default still 62. `tt` up to 512, `tz` above it, which is where `tt` stops existing.
	- ✅ Padding and truncation both delegate to the library's one right-align call, so the two implementations cannot drift on half a policy each.
	- ✅ The multi-byte-digit refusal is gone. Every component works in every base, which is what made the wide families usable at all. Its C error code is retired rather than renumbered.
	- ✅ `%r` draws enough bytes to fill its symbols. One byte each still covers everything up to 256; above that a symbol carries more than eight bits and the leading one would otherwise never vary.
	- ✅ `go.mod` pins the published release; the local `replace` directive is gone. The reactor wasm is built from that same pinned version instead of copied from a neighboring checkout.
	- ✅ Vectors grew 115 -> 187. The new rows come from a third independent derivation, which reproduces all 115 existing rows before generating any new one.
	- Opened: 20260802-143233
	- Closed: 20260804-210541

- ✅ Curated base list, in the help output and in both implementations: **16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz**, default 62. Help builds the line from the list itself, so the two cannot drift. `--base` still accepts any base the library knows, and an unknown one gets the library's near-match suggestion. The `zuid-go` command that first carried it was dropped - the Go side is module-only.
	- Decided: the RFC 4648 base 64 variants were dropped. Their alphabet does not sort, and they need the same 8 characters as base 62, which does.
	- Decided: the wide families were added once truncation worked in them. `tt` up to 512, `tz` above it - below 512 the two are one alphabet under two names, at 512 they genuinely differ, and past it only `tz` continues.
	- ✅ Alphabets reconciled against `convertbase`. Its `32w` is the same 32 symbols the vectors assume, reached by the same alias, so every row reproduces through the real library rather than a local table.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ Upstream the reactor WebAssembly build to `convert-base-v2`. This gated the whole Zig and C side.
	- ✅ Upstream has already designed it, in more depth than anything drafted here. Nothing to propose; do not relitigate their choices.
	- ✅ Sent them zuid's requirements: base metadata (radix and padding symbol) for fixed-width padding, a symbol count rather than a byte count, a stable error enum, and the error text. No streaming needed - inputs are about 13 bytes, so the one-shot surface alone unblocks this side.
	- ✅ Upstream now has a working reactor build. Streaming is still in progress there, but zuid does not use it, so the gate on the Zig side is lifted.
	- ✅ Released, and it exports the symbol slice, the right-align call, and the combined convert-and-fit call this side asked for. zuid builds the module from that pinned release rather than embedding a prebuilt copy.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ Base conversion comes from the sister project `convert-base-v2`, not reimplemented.
	- ✅ Go side imports `convertbase` directly, now at the published `lib/v0.1.0` rather than through a local `replace`. Goal 3 met: the package works as imported, no changes needed to it.
	- ✅ Padding, truncation, and symbol slicing all come from the library too, so the one piece of policy both implementations share is defined in exactly one place.
	- ✅ Zig side reaches it through a reactor WebAssembly module, hosted by a vendored Wasmtime. Goal 4 met: the module is embedded in the binary, all vectors reproduce through it, and its region ledger stays at zero.
	- Opened: 20260801-090104
	- Closed: 20260804-210541

- ✅ The remaining components are done on both sides, and the vectors grew from 72 rows to 115.
	- ✅ The `Converter` interface now carries a from-base, since hashes, hardware addresses, and UUIDs all arrive as hex rather than decimal.
	- ✅ Zig gained an `Env` interface next to it, so the core still touches neither the runtime nor the operating system.
	- Opened: 20260802-020157
	- Closed: 20260802-135041

- ✅ Component set: time, host, user, FQDN, MAC, UUID, random. Each independent of the others.
	- ✅ Time. An unknown verb is rejected rather than silently dropped, so a format string cannot appear to work.
	- ✅ Host, user, FQDN, MAC, UUID, random, on both sides.
	- ✅ Every component is a fixed symbol count wide, so an identifier can be split by offset - not only sorted. The one exception is an unhashed name, which is text.
	- ✅ `%m` takes the lowest-numbered non-loopback interface rather than the predecessor's default-route one, which would need the routing table on three platforms.
	- ✅ `%g` is a real UUID v4, rendered as the 128-bit number rather than the dashed text form, which does not sort.
	- ✅ Padding and truncation both come from the conversion library, in one call that right-aligns a value to an exact symbol count. Truncation used to be refused in a base with multi-byte digits; the library slices by symbol now, so every component works in every base.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Host, user, and FQDN hashed by default, with an explicit opt-out. SHA-256, rightmost few symbols; `--no-hash` emits the names literally and `--hash-chars` resizes them.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Confirm the hashed host/user components cannot be reversed to the originals.
	- ✅ Not reversible by construction: a hashed component keeps about 47 bits of a 256-bit SHA-256 whatever the base, discarding more than 200, so nothing can be inverted back to a unique name.
	- Note: a dictionary attack was the open half of this, and `--salt` closed it on 20260917.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Every environment source injectable, so output is reproducible under test. Go has `WithClock`/`WithFixedTime`/`WithRandom`/`WithHostname`/`WithUsername`/`WithFQDN`/`WithMAC`; Zig has an `Env` interface alongside the existing `Converter`, with `env.zig` as its one live implementation.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Random component from a cryptographic source. Go uses `crypto/rand`; Zig uses `getentropy` through libc, because 0.16 moved randomness onto `Io` the same way it moved the clocks, and the C module has no `Io` to hand it.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Format string selecting and ordering components. Improve on the predecessor's surface rather than porting it.
	- ✅ The CLI exists: `zuid [-b base] [-f format] [-p precision] [--no-hash] [--hash-chars n] [--rand-chars n]`, all seven components plus `%%` literals, unknown verbs rejected with a clear message.
	- ✅ Precision flag: `-p -1|0|1` for minute/second/millisecond, default second - same surface and default as the predecessor.
	- ✅ Two hashing flags rather than the predecessor's six. Per-component widths were exactly the sort of accretion this was meant to improve on.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ C module: static and shared library plus `zuid.h`.
	- ✅ Native artifacts: `libzuid.a` (compiler-rt bundled), self-contained `libzuid.so`, and the installed header. Both link modes verified from plain gcc against a fixed clock.
	- ✅ A cicd stage checks it every run, so the C ABI cannot rot unnoticed. It deliberately uses the system compiler - `zig cc` would prove nothing about a foreign toolchain.
	- ✅ Every component reachable from C, with the width options sticky on the context the way precision already was.
	- Note: cross targets are still open.
	- Opened: 20260801-090104
	- Closed: 20260802-135041

- ✅ Zig side brought up: `zig/lib` (core, wasm host, C module) and `zig/cmd` (CLI).
	- ✅ Every vector row reproduces through the embedded module, under both of Wasmtime's compilers.
	- ✅ The C header verified from plain gcc, shared and static.
	- ✅ Every CLI run exercises the upstream module end to end, which was the point of making the CLI Zig-only.
	- Opened: 20260802-101509
	- Closed: 20260802-104116

- ✅ Vendor the Wasmtime C API during build rather than assuming it is installed. Pinned version, checksum verified, extracted into `zig/vendor/`. The reactor wasm is built from the pinned convertbase release, so it cannot drift from the version the Go side imports; an already-vendored copy covers an offline build.
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
	- Opened: 20260802-012055
	- Closed: 20260802-104116

- ✅ Both modules Apache-2.0; the command stays GPL-2.0-or-later.
	- ✅ Per-directory license files, all `.txt`: repo root and `zig/cmd/` GPL-2.0-or-later; `go/` and `zig/lib/` each Apache-2.0 with a `NOTICE.txt`. Placed ahead of the Zig source so the split is locked in.
	- ✅ Dropping the Go command removed the one awkward case - a GPL command inside the Apache module directory - so no prose has to explain the split anymore.
	- Opened: 20260801-090104
	- Closed: 20260802-100930

- ✅ Go module, importable without cgo, keeping static cross-compilation. Builds `CGO_ENABLED=0` for linux/arm64, windows/amd64, and darwin/arm64, now driven by `cicd.bash --cross`.
	- Opened: 20260801-090104
	- Closed: 20260802-025417

- ✅ Go side brought up: `go/zuid`. Every vector row reproduces, `gofmt` and `go vet` clean.
	- ✅ Startup is 57 ms, nearly all of it building the base registry. Irrelevant now that nothing user-facing routes through Go.
	- ✅ The `zuid-go` command was later dropped: the CLI is Zig-only, so that every use of it also exercises the upstream WebAssembly module. The module's own tests replay the vectors, which is the differential check from the Go side.
	- Opened: n/a
	- Closed: 20260802-020157

- ✅ Move Zig 0.13.0 -> 0.16.0. Installed and verified; 0.13.0 kept alongside so the symlink flips back.
	- ✅ The 0.16 surfaces this project uses: `main(std.process.Init)`, the process arena, `Io.File.Writer`, `DebugAllocator`, and a render path that takes no allocator.
	- ✅ `zig fmt` uses four spaces and cannot be configured, so Zig source is spaces, not tabs. See `style_guide.md`.
	- Opened: 20260801-090104
	- Closed: 20260802-014045

- ✅ Trimmed the `x9muid1` reference copy from 3039 lines to 1280, so it can be read for what it actually does.
	- Done: dropped the debug-trace, unit-test, and sudo scaffolding, plus the ~1600-line generic library that nothing in it called.
	- Verified: same output and exit codes across every dtalgo, precision, hashing setting, and error path.
	- Opened: n/a
	- Closed: 20260802-010143

- ✅ Code review 20260804, the enhancement half.
	- ✅ Code review 20260804 item 5: component widths carry a strength rather than a symbol count.
		- Cause: a symbol is worth four bits in base 16 and eleven in 2048tz, so the fixed 8-and-6 defaults promised a strength they only delivered in base 62. `%r` was 36 bits there and 24 in base 16, where a birthday collision arrives after about four thousand draws.
		- Fixed: the default width is now derived from a target - 47 bits for a hashed name, 35 for `%r`, which is what 8 and 6 base-62 symbols have always held - so the strength stays put and the width moves: 12 and 9 symbols in base 16, 5 and 4 in 2048tz. Base 62 is unchanged.
		- Note: this is the rule `%d`, `%m`, and `%g` already followed, so all seven components now size themselves one way instead of two.
		- Note: 72 vector rows changed and 3 were added, 190 in total. `--hash-chars` and `--rand-chars` still override; zero now means "use the derived width" on every surface.
	- ✅ Code review 20260804 item 7: a hashed component wider than the digest is refused.
		- Cause: `Fit` left-fills, so asking for more symbols than a SHA-256 supplies in that base gave leading padding - at 64 symbols in 2048tz, 40 constant then 24 real. The identifier got longer with no more fingerprint behind it, and nothing said so.
		- Fixed: the ceiling is now derived per base, 64 symbols in base 16 down to 24 in 2048tz, and asking past it is an error naming the number. Refusing rather than capping matches how a past-horizon clock, an unknown verb, and a raw-byte base are already handled.
		- Done: vectors gained a row per wide base sitting exactly on the ceiling.
	- ✅ Code review 20260804 item 17: one crossing into the WebAssembly module per component instead of four.
		- Cause: every component converted, then asked the radix, then counted symbols, then fitted - and each call marshalled the base name in and a result region back out.
		- Done: the module's combined convert-and-fit call does the work in one crossing. The radix is cached on the host, and `%d`'s overflow check became arithmetic against the horizon, which is the same test the symbol count was making.
		- Verified: the seven-component format went from about 220 to about 175 microseconds, and `%d` and `%m` - one component each, so nearly all round trip - from about 25 to about 17.
		- Note: the converter interface lost two of its five calls, and the padded and truncated paths merged into one, since fitting covers both.
	- Opened: 20260804-213000
	- Closed: 20260804-234122

### Future and/or deferred

- ✋ Tag the Go module as `go/v<version>` at the next release, so it can be asked for by version. A module in a subdirectory needs the prefix, and the plain `v1.0.0-alpha.1` tag does not reach it - `go get ...@v1.0.0-alpha.1` answers "found, but does not contain package". Deferred because pushing a public tag is a release decision, not a code fix. `README.md` says how to pin a commit meanwhile.
	- Opened: 20260917-104114

- ✋ CLI startup is ~0.5 s, nearly all of it the module's own `_initialize` building the base registry inside the wasm. Options if it starts to matter: ask upstream about lazier registry construction, or cache a precompiled module per machine. Deferred until the surface settles.
	- Opened: 20260802-104116

- ✋ Sanitizer run on the vendored Wasmtime. The vendored artifact turned out to be a prebuilt archive, so there is nothing local to instrument; revisit only if it is ever built from source here.
	- Note: `design.md` still describes this as a pipeline step, and no stage runs it.
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
