#!/usr/bin/env bash

##	Purpose:
##		The C checks cicd.bash runs in its pinned image, with the gcc and clang
##		there. Each mode exits non-zero on any finding.
##		- sanitize: builds one program with gcc under ASan, LSan and UBSan, then
##		  runs it from the current folder. A report, or a failed build, fails.
##		- gcc-analyzer, clang-analyzer: that analyzer over each .c file given.
##	Syntax:
##		c-checks.bash sanitize <program> <gcc args...>
##		c-checks.bash gcc-analyzer|clang-analyzer <compiler args...> -- <file.c...>
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

fSanitize(){  ## program, gcc args...
	local -r program="$1"; shift
	## No recover, or UBSan prints a report and the run still passes.
	gcc "$@" -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g -O1 -o "${program}"
	## Leak checking is the default on x86_64 Linux only, so it's asked for.
	## Options set by hand go after, such as fast_unwind_on_malloc=0.
	local -i rc=0
	ASAN_OPTIONS="detect_leaks=1${ASAN_OPTIONS:+:${ASAN_OPTIONS}}" UBSAN_OPTIONS="print_stacktrace=1" "./${program}" || rc=$?
	((rc == 0)) && return 0
	## The fast unwinder stops at Wasmtime's frames, which have no frame
	## pointers. The slow one ran past 2 minutes on the static build, so it's not
	## the default.
	echo "For the full stacks, run this again in the image with ASAN_OPTIONS=fast_unwind_on_malloc=0. It's slow."
	return "${rc}"
}

fAnalyze(){  ## gcc|clang, compiler args..., --, files...
	local -r analyzer="$1"; shift
	local -a args=()
	while (($#)) && [[ "$1" != "--" ]]; do args+=("$1"); shift; done
	if (($#)); then shift; fi
	if (($# == 0)); then echo "No .c files given, so there's nothing to analyze." >&2; return 2; fi
	local file=""
	local -i bad=0
	for file in "$@"; do
		case "${analyzer}" in
			## -fanalyzer does nothing under -fsyntax-only, and its findings are
			## only warnings without -Werror. too-complex says when it gave up.
			gcc)   gcc "${args[@]}" -Werror -fanalyzer -Wanalyzer-too-complex -c "${file}" -o /dev/null || bad=1 ;;
			## By default clang drops every path through a loop after 4 turns, so
			## nothing past capi_smoke.c's 200-turn loop was looked at. Widening
			## carries on past it.
			clang) clang-19 --analyze "${args[@]}" -Xclang -analyzer-output=text -Xclang -analyzer-werror \
				-Xclang -analyzer-config -Xclang widen-loops=true "${file}" -o /dev/null || bad=1 ;;
		esac
	done
	return "${bad}"
}

case "${1:-}" in
	sanitize)       shift; fSanitize "$@" ;;
	gcc-analyzer)   shift; fAnalyze gcc "$@" ;;
	clang-analyzer) shift; fAnalyze clang "$@" ;;
	*) echo "Syntax: c-checks.bash sanitize <program> <gcc args...> | gcc-analyzer|clang-analyzer <args...> -- <file.c...>" >&2; exit 2 ;;
esac


##	Script history:
##		- 20261019 JC: Created.
