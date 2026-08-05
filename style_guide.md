<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- hard tabs -->
<!-- markdownlint-disable MD033 -- inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# Style guide

How code and prose are written here, and why. [contributing.md](contributing.md) covers the process side; this is the canonical answer for anything about form.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [The short version](#the-short-version)
- [Formatting](#formatting)
- [Naming](#naming)
- [Comments](#comments)
- [Errors](#errors)
- [Prose and documentation](#prose-and-documentation)

<!-- /TOC -->

## The short version

Each language's own formatter wins. Run it, take its output, and do not hand-format against it. Where a language has no enforced formatter, match the surrounding file.

## Formatting

| Language | Formatter | Indentation |
| :-- | :-- | :-- |
| Go | `gofmt` | tabs |
| Zig | `zig fmt` | four spaces, and it cannot be configured |
| C | matches the Zig side | four spaces |
| Bash | none enforced, but `shellcheck` must pass | tabs |
| Markdown | none | tabs |

Spaces are for alignment, never for indentation, wherever the formatter allows a choice.

Zig is the odd one out. `zig fmt` is deliberately not configurable, and fighting it is not worth the churn, so Zig source is spaces while everything else is tabs.

Protect a hand-laid data table from being reflowed with the formatter's own escape hatch, rather than by avoiding the formatter.

Markdown is never hard-wrapped. One paragraph or one bullet is one physical line, however long, and the reader's editor wraps it. Newlines are for real structure: paragraph breaks, bullets, nesting, code blocks.

## Naming

Names should be findable. Someone reading the code has to be able to search for a name and get the places that actually mean it.

- Prefer a descriptive word to an abbreviation: `upperBound`, not `ub`.
- Single letters are fine for loop indices, and only there.
- Do not overcorrect. Longer is not automatically better, and a short conventional name in a small scope is clear.
- Follow each language's own conventions for case and ordering.

## Comments

Comments say *why*. The code already says what.

- No comment that restates the line below it.
- No banner dividers inside a file. The one exception is the full-width `#•••` rule between major sections of a Bash script, which is an established convention here.
- ASCII only. Write `->` rather than an arrow character, and `-` rather than a dash character. `©` is the exception, and is preferred over `(C)`.
- Terse. A comment that has grown into a paragraph usually wants to be in `project/design.md` instead.
- Describe what the code does and why, never how it was written, tested, or arrived at.

Every source file opens with a copyright and SPDX header. Helper scripts under `cicd/utility/` are MIT regardless of the rest of the project, since they are useful on their own.

## Errors

- Errors are values, returned and then handled or propagated immediately. Nothing is discarded silently.
- No panic, `unreachable`, or equivalent for ordinary failure. Where one is genuinely impossible, a comment carries the proof.
- Return early. The success path sits at the lowest indentation, and there is no `else` after a return.
- An error message says what was wrong with what was given, in the terms the caller used.

## Prose and documentation

Public documents are read by people deciding whether to use this, so they are written for someone who has not seen the code.

- Short sentences. Break a complicated idea into nested bullets rather than joining clauses with dashes, semicolons, and parentheses.
- Plain words. Minimal bold and italic, no capitals for emphasis, and no dramatic adjectives.
- No characters that are not on a keyboard, unless the subject genuinely requires them.
- US spellings.
- Filenames are lower case, except `README.md`.
- Technical detail that only a maintainer needs belongs in `project/design.md` or in the code, not in `README.md`.
