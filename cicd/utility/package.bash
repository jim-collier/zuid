#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		- Builds the release artifacts for whatever platform this machine can
##		  actually produce, into the output directory:
##		    - a tarball of the CLI, its C libraries, and the header
##		    - the bare CLI binary (grab-and-run)
##		    - .deb and .rpm, via nfpm
##		    - checksums.txt over everything
##		- Only the host platform, for now. The Zig side embeds a Wasmtime static
##		  archive, and one is vendored per platform; until the other platforms'
##		  archives are vendored there is nothing to link against. The Go module
##		  cross-compiles fine, but it is a module - there is no binary to ship.
##	Syntax:
##		package.bash [--out DIR] [--version V]
##	History: At bottom.

##	Copyright © 2026 Jim Collier
##	Licensed under GNU GPL v2 or later <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
##	SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

## Locations. This script lives in cicd/utility; the repo root is two up.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/../.." && pwd)"

## Identity and package metadata.
PKG="zuid"
EXE="zuid"
MAINTAINER="Jim Collier <32471972+jim-collier@users.noreply.github.com>"
HOMEPAGE="https://github.com/jim-collier/zuid"
SUMMARY="Short, sortable, privacy-preserving unique identifiers"
DESC_LONG="Generates identifiers built from a timestamp and optional host, user, hardware address, UUID, and random components, rendered in a compact base. Fixed width, so they sort chronologically as plain text. Ships as a command, a Go module, and a C module."

VERSION="$(cd "${root}" && git describe --tags --always --dirty 2>/dev/null || echo dev)"
OUT="${root}/dist"

fEcho(){ printf '[ %s ]\n' "$*"; }
fWarn(){ printf '[ WARNING: %s ]\n' "$*" >&2; }
fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }

while (($#)); do case "$1" in
	--out)     OUT="${2:?}";     shift 2 ;;
	--version) VERSION="${2:?}"; shift 2 ;;
	-h|--help) fUsage; exit 0 ;;
	*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac; done

## A relative --out is resolved against the caller's directory.
[[ "${OUT}" = /* ]] || OUT="${PWD}/${OUT}"

## nfpm turns 1.1.0-beta7 into 1.1.0~beta7 itself, which is what Debian and RPM
## read as "sorts before the final release".
plainver="${VERSION#v}"

## The label users see. amd64 is spelled x86_64 because "AMD64" reads as a
## processor brand to anyone who has not met the convention.
hostArch="$(uname -m)"
case "${hostArch}" in
	x86_64)          goArch="amd64"; label="x86_64" ;;
	aarch64|arm64)   goArch="arm64"; label="arm64"  ;;
	*) echo "unsupported architecture: ${hostArch}" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

rm -rf "${OUT}"; mkdir -p "${OUT}"
fEcho "packaging ${PKG} ${VERSION} -> ${OUT}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The shipped tree: the command, both C libraries, the header, and the licenses.

( cd "${root}/zig" && zig build -Doptimize=ReleaseSafe )

stage="${work}/${PKG}-${VERSION}"
mkdir -p "${stage}/bin" "${stage}/lib" "${stage}/include" "${stage}/share"
cp "${root}/zig/zig-out/bin/${EXE}"        "${stage}/bin/"
cp "${root}/zig/zig-out/lib/libzuid."*     "${stage}/lib/"
cp "${root}/zig/zig-out/include/zuid.h"    "${stage}/include/"
cp "${root}/LICENSE.txt"                   "${stage}/share/"
cp "${root}/zig/lib/LICENSE.txt"           "${stage}/share/LICENSE-module.txt"
cp "${root}/zig/lib/NOTICE.txt"            "${stage}/share/"
cp "${root}/README.md"                     "${stage}/share/"

tar -C "${work}" -czf "${OUT}/${PKG}-linux-${label}.tgz" "$(basename "${stage}")"
cp "${stage}/bin/${EXE}" "${OUT}/${PKG}-linux-${label}"
fEcho "built linux/${label}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Linux packages. nfpm writes deb and rpm directly, so neither dpkg nor rpmbuild
## has to be installed, and it maps the one arch value to each format's spelling.

if command -v nfpm >/dev/null 2>&1; then
	cfg="${work}/nfpm.yaml"
	cat >"${cfg}" <<-EOF
		name: ${PKG}
		arch: ${goArch}
		version: ${plainver}
		maintainer: ${MAINTAINER}
		description: |
		  ${SUMMARY}.
		  ${DESC_LONG}
		homepage: ${HOMEPAGE}
		license: GPL-2.0-or-later
		section: utils
		priority: optional
		contents:
		  - src: ${stage}/bin/${EXE}
		    dst: /usr/bin/${EXE}
		    file_info:
		      mode: 0755
		  - src: ${stage}/include/zuid.h
		    dst: /usr/include/zuid.h
		  - src: ${root}/LICENSE.txt
		    dst: /usr/share/doc/${PKG}/copyright
		    packager: deb
		  - src: ${root}/LICENSE.txt
		    dst: /usr/share/licenses/${PKG}/LICENSE.txt
		    packager: rpm
	EOF
	for fmt in deb rpm; do
		if nfpm package --config "${cfg}" --packager "${fmt}" --target "${OUT}/" >/dev/null 2>&1; then
			fEcho "built .${fmt} (${label})"
		else
			fWarn "nfpm ${fmt} failed (${label})"
		fi
	done
else
	fWarn "nfpm missing; skipping .deb/.rpm - go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## What is deliberately not built here yet, so a missing artifact reads as a
## known gap rather than a silent one.

fWarn "windows, macOS, BSD, and cross-architecture builds need a Wasmtime archive vendored per target; not built"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Checksums over everything produced.

## Built aside and moved into place, so the file being written is never also one
## of the files being hashed.
( cd "${OUT}" && find . -maxdepth 1 -type f -printf '%P\n' | sort \
	| xargs -r sha256sum > "${work}/checksums.txt" )
mv "${work}/checksums.txt" "${OUT}/checksums.txt"

fEcho "done: $(find "${OUT}" -maxdepth 1 -type f ! -name checksums.txt | wc -l) artifacts in ${OUT}"


##	History:
##		- 20260804 JC: Created. Host-platform tarball, bare binary, deb, rpm, checksums.
