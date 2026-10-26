<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

[![Command: GPL v2+](https://img.shields.io/badge/Command-GPLv2%2B-blue.svg)](license.md)
[![Modules: Apache 2.0](https://img.shields.io/badge/Modules-Apache_2.0-green.svg)](license.md)
[![Release](https://img.shields.io/github/v/release/jim-collier/zuid?include_prereleases&sort=semver)](https://github.com/jim-collier/zuid/releases)
[![Go](https://img.shields.io/badge/Go-1.24%2B-00ADD8?logo=go&logoColor=white)](go/go.mod)
[![Zig](https://img.shields.io/badge/Zig-0.17.0-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/download/)

</div>
<!--
[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![made-with-python](https://img.shields.io/badge/Made%20with-Python-1f425f.svg)](https://www.python.org/)
[![made-with-rust](https://img.shields.io/badge/Made%20with-Rust-1f425f.svg)](https://www.rust-lang.org/)
![Made with](https://img.shields.io/badge/Made%20with-C%2B%2B-brightgreen?style=plastic)
![Made with](https://img.shields.io/badge/Made%20with-Unreal%20Engine-critical?style=plastic)
[![made-with-javascript](https://img.shields.io/badge/Made%20with-JavaScript-1f425f.svg)](https://www.javascript.com)
![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)
[![License: GPL v2+](https://img.shields.io/badge/License-GPLv2%2B-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL_2.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)
![Lifecycle: Alpha](https://img.shields.io/badge/Lifecycle-Alpha-orange)
![Lifecycle: Beta](https://img.shields.io/badge/Lifecycle-Beta-yellow)
![Lifecycle: RC](https://img.shields.io/badge/Lifecycle-RC-blue)
![Lifecycle: Stable](https://img.shields.io/badge/Lifecycle-Stable-brightgreen)
![Lifecycle: Deprecated](https://img.shields.io/badge/Lifecycle-Deprecated-red)
![Status: Deprecated](https://img.shields.io/badge/Status-Deprecated-orange)
![Status: Archived](https://img.shields.io/badge/Status-Archived-lightgrey)
![Lifecycle: EOL](https://img.shields.io/badge/Lifecycle-EOL-lightgrey)
![Coverage](https://img.shields.io/badge/Coverage-25%25-red)
![Coverage](https://img.shields.io/badge/Coverage-50%25-orange)
![Coverage](https://img.shields.io/badge/Coverage-75%25-yellow)
![Coverage](https://img.shields.io/badge/Coverage-90%25-brightgreen)
![Status: Passing](https://img.shields.io/badge/Status-Passing-brightgreen)
![Status: Failing](https://img.shields.io/badge/Status-Failing-red)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/jim-collier?logo=GitHub%20Sponsors&style=social)](https://github.com/sponsors/jim-collier)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-jimcollier-ff5e5b?logo=kofi&style=social)](https://ko-fi.com/jimcollier)
-->

<!-- TOC ignore:true -->
# ZUID

Short, sortable, privacy-preserving unique identifiers - from a command line, a Go module, or a C module.

<div align="center">

![zuid in a terminal](assets/demo.gif)

<!-- Video walkthrough: https://www.youtube.com/watch?v=REPLACE_ME -->

</div>

> **Beta.** Releases cover Linux x86_64 and arm64, macOS, Windows x86_64 and arm64, and FreeBSD x86_64. The identifier format is settled; the command's flags may still change before 1.0.0.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Why](#why)
- [Features](#features)
- [Using the modules](#using-the-modules)
- [How it is built](#how-it-is-built)
- [Who it isn't for](#who-it-isnt-for)
- [Installation](#installation)
- [Support](#support)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Why

A random UUID is 36 characters, sorts meaninglessly, and is awkward to read over a phone. Most of the time that buys uniqueness nobody needed.

UUIDv7 and ULID sort by time too. They're 36 and 26 characters. A zuid for the same job is often 6 to 12, because you pick the parts it needs.

An identifier built from a timestamp and rendered in a compact base is far shorter, sorts in creation order as plain text, and is still unique enough for the job. When it is not, more components can be mixed in - more time precision, host, user, hardware address, a UUID, or random data - and the same identifier gets as unique as required.

Host and user components are hashed by default, so an identifier does not leak where it came from. A hardware address (`%m`) is not hashed, so leave it out where that matters.

~~~console
$ zuid                          # the default: a timestamp, base 62, to the second
1wqd1q
$ zuid -f='%d%r'                # plus six random symbols, for same-second uniqueness
1wqd1wDppAd6
$ zuid -f='%d-%h-%u' -p='1'     # millisecond precision, with a hashed host and user
0VRArWn2-rw79Mr05-6UI3mO4y
$ zuid -f='%d%r' -n='3'         # three at once, one per line
1wqd2AKtvRnz
1wqd2AQ1mc6f
1wqd2A9xJbEY
~~~

Every component except an unhashed name is a fixed width, so identifiers line up in a column, sort as text, and can be split back into their parts by offset.

## Features

- Identifiers are as short as necessary, but no shorter.

- Sorts by creation time, as text, with no special comparison function.

- Uniqueness and length are yours to trade off.

- Batches in one run. `--count` prints as many as asked for, and says on stderr when the format made repeats.

- A counter, `%c`, for identifiers made in the same tick. They sort in the order they were made, in a batch or from one module context.

- Private by default. Host and user are hashed unless asked otherwise, and `--salt` or `--salt-file` puts a secret of your own in front of the hash so candidate names cannot be tried against the output.

- Base 62 by default. The help lists 16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, and 2048tz, which all sort. `--base` takes any of the library's seventy-odd.

- The same identifier from the command, the Go module, and the C module. A shared table of test vectors holds all 3 to the same output.

- No config file, on purpose. Base and precision set an identifier's width and sort order, so 2 machines can't drift apart through a setting.

- Every input can be pinned in the modules: clock, random source, host, user, domain, and hardware address. Tests get the same identifier every time.

- Runs on baseline x86-64 and arm64 CPUs. Linux needs glibc 2.28 or newer, such as Debian 10, RHEL 8, or Ubuntu 20.04. macOS needs 13 or newer, and FreeBSD 14 or newer.

- Embeddable, three ways:

	- A standalone command.

	- A permissively licensed Go module.

	- A C module, for nearly anything else. Also permissively licensed.

## Using the modules

Go:

~~~go
g, err := zuid.New()
if err != nil {
	return err
}
id, err := g.Generate(zuid.Request{Format: "%d%r"})
~~~

C, linked with `-lzuid` against the shared library:

~~~c
zuid *z = zuid_new();
if (!z) return 1;
char out[256];
zuid_request req = {0};
req.format = "%d%r";
if (zuid_generate(z, &req, out, sizeof out) == ZUID_OK) puts(out);
else fprintf(stderr, "%s\n", zuid_last_error(z));
zuid_free(z);
~~~

A C context starts in about half a second, so make one and keep it. The static library's link line is at the top of `zuid.h`.

## How it is built

Base conversion is not reimplemented here. It comes from [convert-base-v2](https://github.com/jim-collier/convert-base-v2), so there is one definition of what a base means rather than two that can drift apart.

There are two implementations of the identifier spec, one in Go and one in Zig, and a shared table of test vectors that both have to reproduce. That is more work than one implementation with bindings around it, and it is deliberate: the two check each other, and neither is forced into the other's constraints.

The Go module stays free of cgo and cross-compiles statically. The Zig side produces the command and the C module. Full reasoning is in [project/design.md](project/design.md).

## Who it isn't for

- If a database or API already expects UUIDs, use UUIDv7. zuid's format is its own.

- The command is about 19 MB, since it embeds a WebAssembly runtime and the conversion module. Its first run compiles that module, and later runs read it from a cache.

- There are no releases for musl, 32-bit, or other CPUs.

## Installation

See [install.md](install.md) for the packages, the install scripts, and building from source. To work on zuid itself, see [development.md](development.md).

## Support

zuid is free. If it saves you time and you'd like to help, there's [GitHub Sponsors](https://github.com/sponsors/jim-collier) and [Ko-fi](https://ko-fi.com/jimcollier). A star, a clear bug report, or a mention to someone who needs it helps too. `zuid --donate` prints the same links.

## Copyright and license

The command is GPL-2.0-or-later. The Go and C modules are Apache-2.0, so embedding one brings no obligation beyond attribution. [license.md](license.md) says which license covers which directory, and links the full text of each.

> Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]<br />
> Licensed under the [GNU General Public License v2.0 or later](https://spdx.org/licenses/GPL-2.0-or-later.html)<br />
> SPDX-License-Identifier: `GPL-2.0-or-later` <br />
> No warranty.<br />
> ZUID™ is a [trademark](trademark.md) of Jim Collier.
<!--
> Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]<br />

> Licensed under the [MIT License](https://mit-license.org/)<br />
> SPDX-License-Identifier: `MIT`.<br />
	- Most permissive and least protective

> Licensed under the [GNU General Public License v2.0](https://www.gnu.org/licenses/gpl-2.0.html).

> Licensed under the [GNU General Public License v2.0 or later](https://spdx.org/licenses/GPL-2.0-or-later.html).
> SPDX-License-Identifier: `GPL-2.0-or-later`<br />

> Licensed under the [GNU General Public License v3](https://www.gnu.org/licenses/gpl-3.0.en.html) license.

> Licensed under the [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/).

> Licensed under the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html)
> SPDX-License-Identifier: `Apache-2.0`<br />
	- Permissive
	- Patent protection clause
	- Requires attribution
	- No contribute back
	- SaaS loophole
-->
