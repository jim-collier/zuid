<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- hard tabs -->
<!-- markdownlint-disable MD033 -- inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Command-line style guide

How the `zuid` command talks: what it prints, where it prints it, and what it exits with. [style_guide.md](style_guide.md) covers code and prose; this one covers the surface a user actually meets.

Everything here describes what the command already does. It is written down so the next flag matches the last one, rather than each being argued from scratch.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Streams and exit codes](#streams-and-exit-codes)
- [Flags](#flags)
- [Errors](#errors)
- [Help](#help)
- [Version, about, donate](#version-about-donate)

<!-- /TOC -->

## Streams and exit codes

Identifiers go to stdout, one per line. So do the screens a person asked for by name: `--help`, `--version`, `--about`, `--donate`. Asking for the help and being unable to pipe it into a pager is the older convention, and it is the wrong one.

Errors and warnings go to stderr. Nothing a caller did not ask for is ever mixed into stdout, so a run that generates identifiers hands the next program in the pipe identifiers and only identifiers.

| Exit | Meaning
| :--: | :--
| 0    | An identifier was printed, or an informational screen was
| 1    | Anything went wrong

There is no third code. The command does one thing, and a caller that needs to know what went wrong reads the message rather than a number. The C module is the opposite - it has numbered codes, because a caller there has no message to read.

## Flags

- Every flag has a long spelling. A short one is a convenience and only exists where the flag is typed often.

- A value attaches with `=` or follows as the next argument. `--base=32c` and `--base 32c` are the same thing, and so are `-b=32c` and `-b 32c`. Only an argument starting with a dash is split at its `=`, so a format string carrying one survives.

- A flag that takes no value refuses one rather than ignoring it. `--no-hash=1` is an error.

- An off switch is spelled `--no-<thing>`, and the thing it turns off is the default. There is no matching `--hash`, because the only reason to write one would be to undo a `--no-hash` on the same line.

- Nothing is abbreviated to save characters. `--rand-chars`, not `--rc`.

- A flag never asks a question or waits for input. The command is meant to be called from scripts, and a prompt in the middle of a pipeline is a hang.

## Errors

One line, on stderr, in this shape:

~~~text
zuid: Precision '9' is out of range. Want -1 (minute), 0 (second), or 1 (millisecond).
~~~

- It starts with `zuid: `, so a message coming out of a long script says who produced it.

- Then a sentence, capitalized, ending in a period. Not a fragment.

- A value the user typed is quoted with `'single quotes'`, so an empty or space-padded one is visible.

- Where there is a right answer, a second sentence says what it is, starting with "Want". That is the part people actually use.

- It says what was wrong with what was given, in the words the user used. Not the name of the internal error, and not a stack of context.

- Nothing is printed to stdout on the way out. A failed run produces no partial identifier.

One exception, and it is not something a user typed: a failure inside the embedded wasm runtime is passed through as it arrived. Those are internal, and the runtime's own words say more than a summary would. A message about a value the user gave is always rewritten in this style first, keeping whatever the library worked out - an unknown base name still gets its near match suggested.

## Help

`--help` is the whole surface on one screen, in this order:

1. A blank line, then the version banner.
2. One sentence saying what the command does.
3. `Syntax:` and one line.
4. Anything a reader needs before the option list makes sense. Right now that is the sentence about how values attach.
5. `Options:`, indented four spaces, with the descriptions in one column. Short and long spellings in one cell, and a flag with no short spelling is indented past where a short one would sit, so the long names line up.
6. `Format components:`, the same way.
7. A closing paragraph on the thing a first-time user gets wrong - that widths differ between bases, so two of them do not sort against each other.
8. A blank line.

The option list is built from the same constants the command runs on, so it cannot describe a base that is no longer curated.

No colour, no bold, no box drawing. The help has to read the same in a terminal, a pipe, and a bug report pasted into an issue.

## Version, about, donate

`--version` prints one bare line and nothing else, with no leading or trailing blank:

~~~text
1.0.0-alpha.1 (build dcrb0)
~~~

That is so a script can take `head -n1` of it, which both installers do.

`--about` is the longer form: version, copyright, project URL, both licenses, the no-warranty line, and a two-line description. The copyright lives here and nowhere else - not in `--help`, and not in the banner.

`--donate` says how to support the project and stops. Nothing else ever mentions donating.
