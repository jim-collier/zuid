<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<div align="center">

[![License: GPL v2+](https://img.shields.io/badge/License-GPLv2%2B-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
![Lifecycle: Pre-alpha](https://img.shields.io/badge/Lifecycle-Pre--alpha-red)
![Support](https://img.shields.io/badge/Support-Maintained-brightgreen)

</div>
<!--
[![!#/bin/bash](https://img.shields.io/badge/-%23!%2Fbin%2Fbash-1f425f.svg?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![made-with-python](https://img.shields.io/badge/Made%20with-Python-1f425f.svg)](https://www.python.org/)
[![made-with-rust](https://img.shields.io/badge/Made%20with-Rust-1f425f.svg)](https://www.rust-lang.org/)
![Go](https://img.shields.io/badge/Go-00ADD8?logo=go&logoColor=white)
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
-->

<!-- TOC ignore:true -->
# ZUID

Short, sortable, privacy-preserving unique identifiers - from a command line, a Go module, or a C module.

> **Pre-alpha.** Both implementations build and reproduce the shared test vectors, and every component works from the CLI, the Go module, and the C module. Configuration files, emitting more than one identifier per run, and packaging are still to come. See [project/backlog.md](project/backlog.md) for where it actually stands.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Why](#why)
- [Features](#features)
- [How it is built](#how-it-is-built)
- [Installing](#installing)
- [Building from source](#building-from-source)
- [Copyright and license](#copyright-and-license)

<!-- /TOC -->

## Why

A UUID is 36 characters, sorts meaninglessly, and is awkward to read over a phone. Most of the time that buys uniqueness nobody needed.

An identifier built from a timestamp and rendered in a compact base is far shorter, sorts in creation order as plain text, and is still unique enough for the job. When it is not, more components can be mixed in - more time precision, host, user, MAC, a UUID, or random data - and the same identifier gets as unique as required.

Host and user components are hashed by default, so an identifier does not leak where it came from.

```
$ zuid                          # the default: a timestamp, base 62, to the second
1wqd1q
$ zuid -f '%d%r'                # plus six random symbols, for same-second uniqueness
1wqd1wDppAd6
$ zuid -f '%d-%h-%u' -p 1       # millisecond precision, with a hashed host and user
0VRArWn2-rw79Mr05-6UI3mO4y
```

Every component is a fixed width, so identifiers line up in a column, sort as text, and can be split back into their parts by offset.

## Features

- UIDs are as short as necessary - but no shorter.

- By default, sorts by creation time, as text, with no special comparison function.

- Tunable uniqueness vs length.

- Private by default. Host and user are hashed unless you ask otherwise.

- A curated set of bases suited to identifiers, with the full set of sixty-odd bases available.

- Embeddable. Ships with:

	- A standalone CLI.

	- A permissively licensed Go module to embed in your own Go project.

	- A C module to embed in nearly anything else. Also permissively licensed.

## How it is built

Base conversion is not reimplemented here. It comes from [convert-base-v2](https://github.com/jim-collier/convert-base-v2), so there is one definition of what a base means rather than two that can drift apart.

There are two implementations of the identifier spec, one in Go and one in Zig, and a shared table of test vectors that both have to reproduce. That is more work than one implementation with bindings around it, and it is deliberate: the two check each other, and neither is forced into the other's constraints.

The Go module stays free of cgo and cross-compiles statically.

The Zig side produces the CLI executable, and the C module.

## Installing

## Building from source

`cicd/cicd.bash` drives everything: it builds and tests both sides, and vendors the Wasmtime C API and the upstream WebAssembly module into `zig/vendor/` on first run. Requirements: Go 1.24+, Zig 0.16+.

Or directly: `cd go && go build ./...` for the Go module, and `cd zig && zig build` for the CLI and the C libraries (artifacts land in `zig/zig-out/`).

## Copyright and license

The CLI executable is GPL-2.0-or-later. Full text in [LICENSE.txt](LICENSE.txt) and [zig/cmd/LICENSE.txt](zig/cmd/LICENSE.txt).

The Go and C modules are Apache-2.0, so that embedding one carries no obligation beyond attribution. Full text and attribution sit next to each module: [go/LICENSE.txt](go/LICENSE.txt) + [go/NOTICE.txt](go/NOTICE.txt), and [zig/lib/LICENSE.txt](zig/lib/LICENSE.txt) + [zig/lib/NOTICE.txt](zig/lib/NOTICE.txt).

> Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)<br />
> Licensed under the [GNU General Public License v2.0 or later](https://spdx.org/licenses/GPL-2.0-or-later.html)<br />
> SPDX-License-Identifier: `GPL-2.0-or-later` <br />
> No warranty.<br />
> ZUID™ is a [trademark](trademark.md) of Jim Collier.
<!--
> Copyright © 2026 Jim Collier (CryptogID: ѳ6ᴚ℈𐀘𐇦ɛ𐊁¥Mﾏb϶Δ𐌞)<br />
> Copyright © 2026 t00mietum (CryptogID: กᛦϾ2𐃭ขᚭɘƌფｸᛏﾅh𐌞)<br />
> Copyright © 2026 Bubbles (CryptogID: 7६⋏𐇤𐃋𐀍หԏ๙ኦ𐇔𐀣ษʭ𐌞)<br />

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
