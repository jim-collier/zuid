<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->

# Installing zuid

Back to the [README](README.md). To work on zuid itself, see [development.md](development.md).

## Packages and installers

Preferred. `v1.0.0-alpha.1` is published for x86_64 Linux; on any other platform, build from source with [Do it yourself](#do-it-yourself) below.

| Platform               | Package
| :---                   | :---
| Debian, Ubuntu         | `zuid_<version>_amd64.deb`
| Fedora, RHEL, openSUSE | `zuid-<version>-1.x86_64.rpm`
| Windows                | the `.zip`, or on x86_64 the bare `.exe`
| Anything else          | the `.tgz`, or the bare binary

The `.deb` and `.rpm` install the command. The C module - the header, the static and shared libraries, and the Wasmtime archive the static one needs, plus `libzstd.a` on FreeBSD - comes in the `.tgz`, or the `.zip` on Windows. On arm64 Windows, Wasmtime is `wasmtime.dll`, which has to sit beside `zuid.exe`, so there is no bare `.exe` for it.

Linux arm64, macOS, Windows, and FreeBSD x86_64 builds are produced but not published yet.

## Direct stable and dev install scripts

Both scripts download the latest release, check it against the published checksums, say what they are about to do, and ask before touching anything. Re-running one is a no-op when nothing changed. Pass `--help` (`-Help` for PowerShell) for options. It uses sane defaults and prompts for confirmation.

Linux, macOS, FreeBSD, and WSL. FreeBSD needs `pkg install bash curl` first:

~~~bash
bash <(curl -fsSL https://raw.githubusercontent.com/jim-collier/zuid/main/install.bash)
~~~

Windows, under Windows PowerShell 5.1 or PowerShell 7, and Linux and macOS under PowerShell 7:

~~~powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/jim-collier/zuid/main/install.ps1')))
~~~

Where things go:

| OS      | System install           | Command                               | User install                          | Command
| :---    | :---                     | :---                                  | :---                                  | :---
| Linux   | `/opt/zuid/`             | `/usr/local/bin/zuid`                 | `~/.local/share/zuid/`                | `~/.local/bin/zuid`
| macOS   | `/opt/zuid/`             | `/usr/local/bin/zuid`                 | `~/Library/Application Support/zuid/` | `~/.local/bin/zuid`
| FreeBSD | `/usr/local/zuid/`       | `/usr/local/bin/zuid`                 | `~/.local/share/zuid/`                | `~/.local/bin/zuid`
| Windows | `C:\Program Files\zuid\` | the `bin` folder on the system `PATH` | `%LOCALAPPDATA%\Programs\zuid\`       | the `bin` folder on the user `PATH`

Both install for the user unless told otherwise, even when run as root or an admin. On Windows the `bin` folder is added to `PATH`, and taken off again by an uninstall. Shells that were already open don't see it until they're restarted.

The first run compiles the WebAssembly module built into the command, which takes a few seconds of CPU, and keeps the result in `$XDG_CACHE_HOME/zuid/`, or `~/.cache/zuid/` when that isn't set. On macOS that is `~/Library/Caches/zuid/`, and on Windows `%LOCALAPPDATA%\zuid\`. Later runs load it instead. It is safe to delete, and a run as root does not use it.

## Do it yourself

Clone the repository and run `cicd/cicd.bash --no-backup`. Without that flag a run also archives the tree, then commits and pushes it. It fetches what it needs, builds both sides, and runs the tests. The command ends up at `zig/zig-out/bin/zuid`, and a full run also copies it to the first of `~/.local/bin` or `~/bin` that exists, so what is on your path is the build that just passed. `--no-dogfood` turns that off. A full run on Linux x86_64 or macOS builds the release files into `dist/` as well, and [development.md](development.md) lists what that needs.

For the Go module, no install step is needed:

~~~bash
go get github.com/jim-collier/zuid/go/zuid
~~~

Name the package rather than the module root. `go get` on the root adds the module without what its package needs, and the build then stops on a missing `go.sum` entry for `convertbase`.

The module sits in a subdirectory, so pinning it to a release needs a `go/`-prefixed tag, and there is not one yet. Until there is, that command tracks `main`. To pin, name a commit: `go get github.com/jim-collier/zuid/go/zuid@<commit>`.
