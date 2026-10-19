#!/usr/bin/env bash

##	Purpose:
##		The C checks cicd.bash runs in its pinned image, with the gcc and clang
##		there. Each mode exits non-zero on any finding.
##		- sanitize: builds one program with gcc under ASan, LSan and UBSan, then
##		  runs it from the current folder. A report, or a failed build, fails.
##		- gcc-analyzer, clang-analyzer: that analyzer over each .c file given.
##		- clang-ctu: clang's analyzer again, following calls from one .c file
##		  into another. The files are analyzed as one program.
##		- ctu-canary: clang-ctu over 2 files it writes, with a null dereference
##		  only a cross-file analysis can see. Fails if that goes unseen.
##		- soak-calls: builds capi_soak.c plainly and runs its call soak under
##		  heaptrack, writing heaptrack's report. The data file is kept only on
##		  a failure, since it runs to tens of MB.
##		- soak-contexts: the same build, running its context soak plainly.
##	Syntax:
##		c-checks.bash sanitize <program> <gcc args...>
##		c-checks.bash gcc-analyzer|clang-analyzer|clang-ctu <compiler args...> -- <file.c...>
##		c-checks.bash ctu-canary
##		c-checks.bash soak-calls <program> <report> <data file> <gcc args...>
##		c-checks.bash soak-contexts <program> <gcc args...>
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

## The same flags as the clang analyzer above, plus the definitions in the
## other files. analyze-build makes the AST dumps and the map of which file
## defines what, then clang reads them. analyze-build's own analysis only
## writes HTML, and exits 0 on findings without --status-bugs.
fCtu(){  ## compiler args..., --, files...
	local -a args=()
	while (($#)) && [[ "$1" != "--" ]]; do args+=("$1"); shift; done
	if (($#)); then shift; fi
	if (($# == 0)); then echo "No .c files given, so there's nothing to analyze." >&2; return 2; fi
	local -r work="${PWD}/ctu"
	mkdir -p "${work}"
	python3 - "${PWD}" "${work}/compile_commands.json" "$@" -- "${args[@]}" <<- 'EOF'
		import json, shlex, sys
		cwd, out, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
		split = rest.index("--")
		files, args = rest[:split], rest[split + 1:]
		## The old 'command' form. analyze-build 19 fails on 'arguments'.
		entries = [{"directory": cwd, "file": f, "command": shlex.join(["clang-19", *args, "-c", f])} for f in files]
		json.dump(entries, open(out, "w"), indent=1)
	EOF
	analyze-build-19 --cdb "${work}/compile_commands.json" --ctu-collect-only --ctu-dir "${work}/dir" \
		--use-analyzer "$(command -v clang-19)" --use-extdef-map-cmd "$(command -v clang-extdef-mapping-19)" \
		-o "${work}/reports" >/dev/null || { echo "analyze-build couldn't build the cross-file index." >&2; return 1; }
	local -a maps=()
	mapfile -t maps < <(find "${work}/dir" -name externalDefMap.txt)
	if ((${#maps[@]} != 1)); then echo "Expected one definition map from analyze-build, found ${#maps[@]}." >&2; return 1; fi
	## A function defined in more than one file, such as main, is left out.
	echo "Cross-file .: $(wc -l < "${maps[0]}") function(s) another file could call"
	local file=""
	local -i bad=0
	for file in "$@"; do
		clang-19 --analyze "${args[@]}" -Xclang -analyzer-output=text -Xclang -analyzer-werror \
			-Xclang -analyzer-config -Xclang widen-loops=true \
			-Xclang -analyzer-config -Xclang experimental-enable-naive-ctu-analysis=true \
			-Xclang -analyzer-config -Xclang "ctu-dir=$(dirname "${maps[0]}")" \
			"${file}" -o /dev/null || bad=1
	done
	return "${bad}"
}

## A NULL returned from another file is a pattern the analyzer drops on
## purpose (suppress-null-return-paths), so the canary passes one in instead.
fCtuCanary(){
	local -r dir="${PWD}/canary"
	local -i rc=0
	mkdir -p "${dir}"
	printf '#include <stddef.h>\nint canary_first(const int *values);\nint main(void) { return canary_first(NULL); }\n' > "${dir}/caller.c"
	printf 'int canary_first(const int *values);\nint canary_first(const int *values) { return values[0]; }\n' > "${dir}/callee.c"
	## Its report is only news when it's missing.
	(cd "${dir}" && fCtu -std=c99 -- "${dir}/caller.c" "${dir}/callee.c") > "${dir}/out.txt" 2>&1 && rc=0 || rc=$?
	if ((rc == 0)); then
		cat "${dir}/out.txt"
		echo "The cross-file analyzer missed a null dereference planted across 2 files, so it isn't following calls between them."
		return 1
	fi
	grep -F 'core.NullDereference' "${dir}/out.txt" | sed 's|^.*/canary/|Planted ....: |'
	echo "Found the planted null dereference, as it should."
}

## The per-thread cache counts freed blocks as in use, which made the heap
## reading wander by about 100 KB between rounds. Without it the reading held
## to the byte. Plain builds, since heaptrack and ASan can't share one.
fSoakBuild(){  ## program, gcc args...
	local -r program="$1"; shift
	gcc "$@" -O2 -g -o "${program}"
}

## The call soak under heaptrack, which wraps malloc and lets the tunable
## through. Its report is peaks and leaks only, since the full listing ran
## past 1 MB. Its leak list isn't a verdict: it named Cranelift's compile
## buffers as leaked, while the heap after 24 contexts was the same to the
## byte as after 4.
fSoakCalls(){  ## program, report, data file, gcc args...
	local -r program="$1" report="$2" data="$3"; shift 3
	fSoakBuild "${program}" "$@"
	local -r stem="${PWD}/${program}-heaptrack"
	local -i rc=0
	GLIBC_TUNABLES="glibc.malloc.tcache_count=0" heaptrack -o "${stem}" "./${program}" calls > "${stem}.log" 2>&1 || rc=$?
	## heaptrack's own lines name the data file, which a pass deletes, and its
	## leak count, which isn't a verdict.
	grep -vE '^(heaptrack output will be written|starting application|heaptrack stats:|Heaptrack finished|  heaptrack --analyze|[[:space:]]+(leaked |temporary )?allocations:|$)' "${stem}.log" || true
	heaptrack_print -f "${stem}.zst" --print-peaks=1 --print-allocators=0 --print-temporary=0 --print-leaks=1 \
		--peak-limit=10 --sub-peak-limit=3 > "${report}" || { echo "heaptrack_print failed." >&2; rc=1; }
	echo "Report .....: ${report}"
	## The data file is what heaptrack --analyze opens, and about 25 MB.
	if ((rc == 0)); then
		rm -f "${stem}.zst"
	elif [[ -f "${stem}.zst" ]]; then
		mv "${stem}.zst" "${data}"
		echo "Data .......: ${data}"
	fi
	return "${rc}"
}

## Under heaptrack its own memory grew about 70 MB a round here, while
## heaptrack's view of the program peaked under 90 MB, so this one runs plain.
fSoakContexts(){  ## program, gcc args...
	local -r program="$1"; shift
	fSoakBuild "${program}" "$@"
	GLIBC_TUNABLES="glibc.malloc.tcache_count=0" "./${program}" contexts
}

case "${1:-}" in
	sanitize)       shift; fSanitize "$@" ;;
	gcc-analyzer)   shift; fAnalyze gcc "$@" ;;
	clang-analyzer) shift; fAnalyze clang "$@" ;;
	clang-ctu)      shift; fCtu "$@" ;;
	ctu-canary)     shift; fCtuCanary ;;
	soak-calls)     shift; fSoakCalls "$@" ;;
	soak-contexts)  shift; fSoakContexts "$@" ;;
	*) echo "Syntax: c-checks.bash sanitize <program> <gcc args...> | gcc-analyzer|clang-analyzer|clang-ctu <args...> -- <file.c...> | ctu-canary | soak-calls <program> <report> <data file> <gcc args...> | soak-contexts <program> <gcc args...>" >&2; exit 2 ;;
esac


##	Script history:
##		- 20261019 JC: Created.
##		- 20261019 JC: The cross-file analyzer and the soak test, for --leakcheck.
