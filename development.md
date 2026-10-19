<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

# Setting up a development environment

Back to the [README](README.md). Installing a release, or building one for daily use, is in [install.md](install.md).

## Prerequisites

| Tool                      | Version       | Needed for
| :---                      | :---          | :---
| Go                        | 1.24 or newer | the Go module, and building the WebAssembly module the Zig side embeds
| Zig                       | 0.17.0        | the command and the C module
| git, curl, tar, sha256sum | any           | fetching and verifying the vendored runtime
| gcc or clang              | any           | checking that a foreign toolchain can use the C module
| shellcheck                | any           | linting the build script
| python3                   | 3.9 or newer  | the test ID check and the profile report

Optional. A stage that wants one skips itself with a note when it's missing, except the 2 that say they stop:

| Tool                                        | Used for
| :---                                        | :---
| llvm-objcopy                                | packaging, on Linux. It strips the release files. A full run skips packaging without it, and `--package` stops.
| nfpm                                        | building `.deb` and `.rpm` packages
| zip                                         | building the Windows `.zip` packages
| objdump, readelf, nm                        | checking the release files for CPU features and library versions
| dpkg-deb, rpm2cpio, cpio                    | checking what the packages install
| Intel SDE                                   | running the release on an emulated old CPU
| python3 3.11 or newer with pillow, gifsicle | rendering the demo animation
| perf, inferno                               | profiling the command
| PSScriptAnalyzer, under pwsh                | checking `install.ps1` against Windows PowerShell 5.1
| docker, on x86_64 Linux                     | staticcheck, govulncheck, the PowerShell lint, the C sanitizer and analyzer checks, the C half of `--leakcheck`, and CodeQL, which run from the pinned images described below. govulncheck also skips offline.
| rar                                         | the backup stage, which stops without it. `--no-backup` skips it.

The conversion module in the release is built with the Go version the Dockerfile pins, whatever Go is on PATH. Go fetches that version the first time, so a release needs the network once. `GOTOOLCHAIN=local` uses the Go on PATH instead, for anything but a release.

If the `zig` on PATH is older, `cicd/cicd.bash` takes the one named by `ZIG`, or a release unpacked as `~/.local/zig-<platform>-0.17.0`, and every stage uses that one.

Nothing has to be installed system-wide beyond those. The WebAssembly runtime and the conversion module are fetched or built into `zig/vendor/`, which is not committed.

On x86_64 Linux with docker, `cicd/cicd.bash --container` needs only git and docker. It builds an image from `cicd/container/Dockerfile` the first time, about 2 GB, with every tool above at a pinned version, and runs the build and tests in it. The demo, the dogfood install and the backup still run outside it, and `--publish` does not go with it. `ZUID_DOCKER` can name another program that takes docker's arguments, such as podman, but only docker has been tried.

## Building and testing

`cicd/cicd.bash` drives everything and is what to run before merging.

~~~bash
cicd/cicd.bash                      # every stage but --publish: build, test, cross-compile, and package where it can
cicd/cicd.bash --quick              # skip fuzzing, profiling, the demo, packaging and the dogfood install
cicd/cicd.bash --gate                 # what the pre-push hook runs: --quick, without the sync, dogfood or backup
cicd/cicd.bash --only go            # one toolchain, so only that one has to exist
cicd/cicd.bash --container          # build and test in the pinned image instead
cicd/cicd.bash --quick --leakcheck  # add the soak tests, the cross-file C analyzer, and CodeQL back to a quick run
cicd/cicd.bash --package            # build the release files into dist/, even on a quick run
cicd/cicd.bash --no-package         # a full run without them
cicd/cicd.bash --no-backup          # skip the archive, commit, and push
cicd/cicd.bash --commit -m "message"  # commit too, refusing on main and dev
~~~

Underneath it's only `cd go && go build ./...` and `cd zig && zig build`. The Zig half needs `cicd/cicd.bash` to have run at least once first, since that is what populates `zig/vendor/`. Zig refuses an empty or non-numeric `SOURCE_DATE_EPOCH` the first time it builds its own C libraries, so unset it rather than leave it empty. `cicd/cicd.bash` drops one like that by itself.

Both sides have to reproduce every row of `testdata/vectors.tsv` before anything merges. That file is the specification in executable form, so a change to the identifier format means regenerating it and re-running both.

Run logs, profiles, and demo renders go under `cicd/artifacts/`, which is rotated and not committed.

`--leakcheck` is on for a full run, and off for `--quick` and `--gate` unless it's asked for. `--no-leakcheck` leaves it out of any run. It soaks each side: the same calls a caller makes, round after round, failing when the heap after round 2N is bigger than after round N by more than a margin. The Go soak runs on the Go on PATH and keeps 2 heap profiles, and `go tool pprof -base` on them shows what grew. The C soak runs in the image, under heaptrack, and keeps heaptrack's report. Both go in `cicd/artifacts/leakcheck/`. It also runs clang's analyzer in cross-file mode over the C tests, so it follows a call from one file into another. All of it takes about 10 minutes.

`--leakcheck` also runs CodeQL, on the Go module and on the C tests. It comes from a second image, built from `cicd/container/codeql/Dockerfile` on top of the first one the first time `--leakcheck` asks for it, about 480 MB more. The Go module is copied to a scratch folder and its dependencies vendored there, since CodeQL only reports on code inside the folder it was given. Any finding in our own code fails the run, and so does a security or correctness finding in third-party code. One that has to wait for a fix upstream goes in `cicd/utility/codeql-suppressions.txt` with its backlog item. The reports go in `cicd/artifacts/leakcheck/` too, as SARIF. Zig isn't a language CodeQL reads, so the C module itself is covered only through its header and the C tests. GitHub's terms for CodeQL allow it on code under an OSI license, so check them before running it on a fork that isn't.

## House style

Three documents, and between them they answer most of what a patch gets sent back for.

- Formatters, naming, comments and error handling are in [style_guide.md](style_guide.md).

- [style-guide_cli.md](style-guide_cli.md) covers the surface a user meets: which stream things print on, what the exit code means, how a flag is spelled, and what an error message looks like.

- For the process side - where to report a bug, and what a useful report has in it - read [contributing.md](contributing.md).
