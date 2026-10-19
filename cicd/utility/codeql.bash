#!/usr/bin/env bash

##	Purpose:
##		CodeQL for cicd.bash --leakcheck, in the CodeQL image. Each mode builds
##		a database from a clean build, fails if a file the build compiled isn't
##		in it, then runs the security and quality queries and hands the
##		results to codeql-report.py.
##		- go: copies the Go module to a scratch folder and vendors what it
##		  uses, since CodeQL only reports on files under the database's root.
##		  The command runs the reactor package, so it's vendored too and
##		  built for wasm, as the release builds it.
##		- c: compiles each .c file given, with the compiler args given.
##		Zig isn't a language CodeQL reads, so the C module's own code isn't in
##		the C database. Only its header is, through the C tests.
##	Syntax:
##		codeql.bash go <go dir> <work dir> <sarif out> <reactor package>
##		codeql.bash c <source root> <work dir> <sarif out> <compiler args...> -- <file.c...>
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly here

fThreads(){
	local -i half=$(( $(nproc) / 2 ))
	echo $(( half > 0 ? half : 1 ))
}

## Its own output is long and mostly progress, so it's shown only on a failure.
fQuietly(){  ## log, command...
	local -r log="$1"; shift
	"$@" > "${log}" 2>&1 && return 0
	cat "${log}"
	return 1
}

fAnalyze(){  ## go|c, database, sarif
	local -r lang="$1" db="$2" sarif="$3"
	local suite="codeql/go-queries:codeql-suites/go-security-and-quality.qls"
	if [[ "${lang}" == "c" ]]; then suite="codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls"; fi
	echo "Queries ....: ${suite#*:codeql-suites/}"
	fQuietly "${db}.analyze.log" codeql database analyze "${db}" "${suite}" --format=sarif-latest \
		--output="${sarif}" --threads="$(fThreads)" || { echo "codeql database analyze failed." >&2; return 1; }
	echo "Report .....: ${sarif}"
	python3 "${here}/codeql-report.py" report "${sarif}" "${lang}" "${here}/codeql-suppressions.txt"
}

fGo(){  ## go dir, work dir, sarif, reactor package
	local -r goDir="$1" work="$2" sarif="$3" reactor="$4"
	local -r src="${work}/src"
	mkdir -p "${src}/codeqlreactor"
	cp -a "${goDir}/." "${src}/"
	## go mod vendor takes only what something imports. The tag keeps this
	## file out of every build, so the folder is just a way in.
	printf '//go:build codeqlreactor\n\npackage codeqlreactor\n\nimport _ "%s"\n' "${reactor}" > "${src}/codeqlreactor/reactor.go"
	(cd "${src}" && go mod vendor) || { echo "go mod vendor failed. Offline, with the modules not cached yet?" >&2; return 1; }
	## A warm build cache compiles nothing, and the extractor only sees compiles.
	local -x GOCACHE="${work}/gocache" GOFLAGS="-mod=vendor"
	local -x CODEQL_EXTRACTOR_GO_OPTION_EXTRACT_VENDOR_DIRS=true
	fQuietly "${work}/create.log" codeql database create "${work}/db" --language=go --source-root="${src}" --threads="$(fThreads)" \
		--command="go build ./..." \
		--command="env GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o ${work}/reactor.wasm ${reactor}" \
		|| { echo "codeql database create failed." >&2; return 1; }
	## What the two builds compiled, ours and vendored.
	local -r listFmt='{{if not .Standard}}{{range .GoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CgoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{end}}'
	local -a files=()
	mapfile -t files < <(cd "${src}" && { go list -deps -f "${listFmt}" ./...; GOOS=wasip1 GOARCH=wasm go list -deps -f "${listFmt}" "${reactor}"; } | sort -u)
	python3 "${here}/codeql-report.py" coverage "${work}/db" "${files[@]}"
	fAnalyze go "${work}/db" "${sarif}"
}

fC(){  ## source root, work dir, sarif, compiler args..., --, files...
	local -r root="$1" work="$2" sarif="$3"; shift 3
	local -a args=()
	while (($#)) && [[ "$1" != "--" ]]; do args+=("$1"); shift; done
	if (($#)); then shift; fi
	if (($# == 0)); then echo "No .c files given, so there's nothing to build." >&2; return 2; fi
	## A new folder, so every file compiles. CodeQL splits each command at spaces.
	mkdir -p "${work}/build"
	local -a commands=()
	local -i n=0
	local file=""
	for file in "$@"; do
		n+=1
		commands+=("--command=gcc ${args[*]} -c ${file} -o ${work}/build/${n}.o")
	done
	fQuietly "${work}/create.log" codeql database create "${work}/db" --language=c-cpp --source-root="${root}" \
		--threads="$(fThreads)" "${commands[@]}" || { echo "codeql database create failed." >&2; return 1; }
	python3 "${here}/codeql-report.py" coverage "${work}/db" "$@"
	fAnalyze c "${work}/db" "${sarif}"
}

command -v codeql >/dev/null || { echo "No codeql here. It's in the CodeQL image, cicd/container/codeql/Dockerfile." >&2; exit 2; }
case "${1:-}" in
	go) shift; fGo "$@" ;;
	c)  shift; fC "$@" ;;
	*) echo "Syntax: codeql.bash go <go dir> <work dir> <sarif out> <reactor package> | c <source root> <work dir> <sarif out> <compiler args...> -- <file.c...>" >&2; exit 2 ;;
esac


##	Script history:
##		- 20261019 JC: Created.
