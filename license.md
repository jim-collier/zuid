<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->

# License

Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]

This repo holds two licenses. Which one applies depends on the directory.

| Part                        | Where      | License           | Full text
|:----------------------------|:-----------|:------------------|:---------
| The `zuid` command          | `zig/cmd/` | GPL-2.0-or-later  | [zig/cmd/LICENSE.txt](zig/cmd/LICENSE.txt)
| The C module and `zuid.h`   | `zig/lib/` | Apache-2.0        | [zig/lib/LICENSE.txt](zig/lib/LICENSE.txt), with [NOTICE.txt](zig/lib/NOTICE.txt)
| The Go module               | `go/`      | Apache-2.0        | [go/LICENSE.txt](go/LICENSE.txt), with [NOTICE.txt](go/NOTICE.txt)
| Everything else             | the rest   | GPL-2.0-or-later  | [zig/cmd/LICENSE.txt](zig/cmd/LICENSE.txt)

- Embedding either module in another program only asks for attribution, as Apache-2.0 describes. The GPL on the command does not reach code that uses a module.

- A file whose header names a different license is under that one. The installers, for example, are MIT.

- Neither license grants use of the name. See [trademark.md](trademark.md).

- There is no warranty, to the extent permitted by law.
