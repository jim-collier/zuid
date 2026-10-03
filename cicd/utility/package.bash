#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		- Builds the release artifacts for whatever platform this machine can
##		  actually produce, into the output directory:
##		    - a tarball of the CLI, its C libraries, and the header
##		    - the bare CLI binary (grab-and-run)
##		    - .deb and .rpm, via nfpm
##		    - checksums.txt over everything
##		- Only the host platform, for now: Linux or macOS. The Zig side embeds a
##		  Wasmtime static archive, and one is vendored per platform; until the
##		  other platforms' archives are vendored there is nothing to link
##		  against. The Go module cross-compiles fine, but it is a module - there
##		  is no binary to release.
##		- On a Mac everything is universal, x86_64 and arm64 merged by lipo.
##		  cicd.bash vendors the second Wasmtime archive that needs.
##	Syntax:
##		package.bash [--out DIR] [--version V]
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
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
DESC_LONG="Generates identifiers built from a timestamp and optional host, user, hardware address, UUID, and random components, rendered in a compact base. Fixed width, so they sort chronologically as plain text. Available as a command, a Go module, and a C module."

VERSION="$(cd "${root}" && git describe --tags --always --dirty 2>/dev/null || echo dev)"
OUT="${root}/dist"
## dist/ is this script's own directory, so it counts as ours whatever is in it.
## A path that came from --out does not, and has to prove itself below.
outIsDefault=1

fEcho(){ printf '[ %s ]\n' "$*"; }
fWarn(){ printf '[ WARNING: %s ]\n' "$*" >&2; }
fDie(){  printf '\n%s: %s\n\n' "package" "$*" >&2; exit 2; }
fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }

while (($#)); do case "$1" in
	--out)     OUT="${2:?}"; outIsDefault=0; shift 2 ;;
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
	x86_64)          goArch="amd64"; label="x86_64"; zigArch="x86_64"  ;;
	aarch64|arm64)   goArch="arm64"; label="arm64";  zigArch="aarch64" ;;
	*) echo "unsupported architecture: ${hostArch}" >&2; exit 2 ;;
esac

## With no target named, Zig builds for this machine: its CPU's newest
## instructions, its glibc, its macOS version. A release has to run on older
## ones. Naming a target also gives that target's baseline CPU, which for arm64
## macOS is the M1, the oldest there is. 2.28 and 13.0 are what cicd.bash checks
## the result against; 13.0 is as far back as Zig goes.
## A Mac builds one slice per architecture and merges them, whichever it is.
case "$(uname -s)" in
	Linux)  osLabel="linux";  hostOs="linux"; zigTargets=("${zigArch}-linux-gnu.2.28") ;;
	Darwin) osLabel="darwin"; hostOs="macos"; zigTargets=("x86_64-macos.13.0" "aarch64-macos.13.0"); label="universal" ;;
	*) echo "unsupported system: $(uname -s)" >&2; exit 2 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## --out comes from whoever ran this, and it used to be handed straight to
## 'rm -rf'. So the directory has to be one of ours before anything in it is
## touched: either it does not exist, or it is empty, or it carries the marker a
## previous run left. Anything else is somebody's work and gets refused.
##
## The check runs now and the clearing runs after the build, so a mistyped --out
## fails in a second rather than after a ReleaseSafe build, and a build that
## fails leaves the last good run's artifacts alone.

outMarker=".${PKG}-package-dir"

## Empty prints nothing. Cheaper than counting, and it stops at the first entry.
fDirHasContent(){ [[ -n "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit)" ]] ;}

## Ours if this script picked the path, if a previous run left its marker, or if
## there is nothing there to lose. The marker is what carries a --out directory
## from one run to the next.
fOutDirIsOurs(){
	((outIsDefault))                  && return 0
	[[ -e "${OUT}/${outMarker}" ]]    && return 0
	fDirHasContent "${OUT}"           || return 0
	return 1
}

fCheckOutDir(){
	[[ -e "${OUT}" ]] || return 0
	[[ -d "${OUT}" ]] || fDie "--out names something that is not a directory: ${OUT}"
	fOutDirIsOurs && return 0
	fDie "refusing to empty ${OUT}: it holds files and carries no ${outMarker} marker, so it is not a previous run's output. Pass --out somewhere this script made, or an empty or new directory."
}

## Only reached once the build has produced something to put here. Clears the
## contents rather than the directory itself, so a mount point or a directory
## somebody granted permissions on survives being reused.
fClaimOutDir(){
	mkdir -p "${OUT}"
	if fDirHasContent "${OUT}"; then
		fOutDirIsOurs || fDie "${OUT} gained files while the build ran, and carries no ${outMarker} marker. Refusing to empty it."
		find "${OUT}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
	fi
	: > "${OUT}/${outMarker}"
}

fCheckOutDir
fEcho "packaging ${PKG} ${VERSION} -> ${OUT}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The release tree: the command, both C libraries, the header, and the licenses.

## Member names come out holding this machine's cache paths, which is both a
## build path in a published file and a difference between two builds of the
## same commit. Re-archive on basenames, deterministically, so neither shows.
##
## GNU ar cannot address the members Zig writes - it lists them and then reports
## "no entry" for the same name - so this needs llvm-ar. Cosmetic either way, so
## a box without it gets a warning rather than a failure.
llvmAr=""
for candidate in llvm-ar llvm-ar-19 llvm-ar-18 llvm-ar-17 llvm-ar-16; do
	if command -v "${candidate}" >/dev/null 2>&1; then llvmAr="${candidate}"; break; fi
done

fNormalizeArchive(){  ## path
	local -r archive="$1"
	if [[ -z "${llvmAr}" ]]; then
		fWarn "no llvm-ar; $(basename "${archive}") keeps this machine's paths in its member names"
		return 0
	fi
	local extractDir; extractDir="$(mktemp -d "${work}/ar.XXXXXX")"
	## llvm-ar extracts on basenames into the working directory, which is the
	## whole point: the paths go away here. Zig's Mach-O archives give their
	## members mode 000, so they come out unreadable.
	( cd "${extractDir}" && "${llvmAr}" x "${archive}" && chmod u+r ./*.o && "${llvmAr}" rcsD "${archive}.new" ./*.o )
	mv "${archive}.new" "${archive}"
}

## Same rule as build.zig: the build machine's own Wasmtime is vendor/wasmtime,
## and any other target's is beside it under Wasmtime's platform name.
fWasmtimeArchive(){  ## zig target
	local -r arch="${1%%-*}" rest="${1#*-}"
	local -r os="${rest%%[-.]*}"
	if [[ "${arch}" == "${zigArch}" && "${os}" == "${hostOs}" ]]; then
		echo "${root}/zig/vendor/wasmtime/lib/libwasmtime.a"
	else
		echo "${root}/zig/vendor/wasmtime-${arch}-${os}/lib/libwasmtime.a"
	fi
}

## Each slice is a whole tree. zuid.h tells a static consumer to link -lzuid
## -lwasmtime, so the archive it names goes in too. libzuid.a holds its own
## objects only, and the release used to carry no wasmtime at all, which left
## that link line with nothing to satisfy it.
lipo=""
if ((${#zigTargets[@]} > 1)); then
	lipo="$(command -v lipo || true)"
	[[ -n "${lipo}" ]] || fDie "lipo not found. It comes with Xcode's command line tools."
fi
slices=()
for zigTarget in "${zigTargets[@]}"; do
	slice="${work}/slice-${zigTarget%%-*}"
	wasmtimeArchive="$(fWasmtimeArchive "${zigTarget}")"
	[[ -f "${wasmtimeArchive}" ]] || fDie "missing ${wasmtimeArchive}. Run cicd.bash first; it vendors Wasmtime."
	( cd "${root}/zig" && zig build -Doptimize=ReleaseSafe -Dtarget="${zigTarget}" --prefix "${slice}" )
	cp "${wasmtimeArchive}" "${slice}/lib/"
	fNormalizeArchive "${slice}/lib/libzuid.a"
	slices+=("${slice}")
done

## The build worked, so there is something to publish. Safe to clear now.
fClaimOutDir

stage="${work}/${PKG}-${VERSION}"
mkdir -p "${stage}/bin" "${stage}/lib" "${stage}/include" "${stage}/share"

## Two or more slices are merged file by file. Symlinks come from the first, and
## everything else is one file holding every slice. -P, because the shared
## library carries an soname: lib/ holds libzuid.so and libzuid.so.1 as symlinks
## onto libzuid.so.1.0.0, and a plain cp would follow them and put three 28 MB
## copies in the tarball.
fMergeSlices(){  ## subdir
	local -r sub="$1"
	local item="" name="" slice=""
	local -a parts=()
	for item in "${slices[0]}/${sub}/"*; do
		name="$(basename "${item}")"
		if [[ -L "${item}" ]] || ((${#slices[@]} == 1)); then
			cp -P "${item}" "${stage}/${sub}/"
			continue
		fi
		parts=()
		for slice in "${slices[@]}"; do parts+=("${slice}/${sub}/${name}"); done
		"${lipo}" -create "${parts[@]}" -output "${stage}/${sub}/${name}"
	done
}
fMergeSlices bin
fMergeSlices lib

cp "${slices[0]}/include/zuid.h"           "${stage}/include/"
cp "${root}/license.md"                    "${stage}/share/"
cp "${root}/zig/cmd/LICENSE.txt"           "${stage}/share/"
cp "${root}/zig/lib/LICENSE.txt"           "${stage}/share/LICENSE-module.txt"
cp "${root}/zig/lib/NOTICE.txt"            "${stage}/share/"
cp "${root}/README.md"                     "${stage}/share/"

tar -C "${work}" -czf "${OUT}/${PKG}-${osLabel}-${label}.tgz" "$(basename "${stage}")"
cp "${stage}/bin/${EXE}" "${OUT}/${PKG}-${osLabel}-${label}"
fEcho "built ${osLabel}/${label}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Linux packages. nfpm writes deb and rpm directly, so neither dpkg nor rpmbuild
## has to be installed, and it maps the one arch value to each format's spelling.
##
## The command only. These used to install zuid.h with no library behind it, so
## the one thing a header is for - compiling against it - failed at the link
## step. The C module ships in the tarball instead, where the static archive can
## sit next to the Wasmtime archive it needs. A real -dev package, with the
## shared library in the right per-distro lib directory and ldconfig run after
## it, is a separate job.

if [[ "${osLabel}" == "linux" ]] && command -v nfpm >/dev/null 2>&1; then
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
		license: GPL-2.0-or-later AND Apache-2.0
		section: utils
		priority: optional
		contents:
		  - src: ${stage}/bin/${EXE}
		    dst: /usr/bin/${EXE}
		    file_info:
		      mode: 0755
		  - src: ${root}/zig/cmd/LICENSE.txt
		    dst: /usr/share/doc/${PKG}/copyright
		    packager: deb
		  - src: ${root}/zig/cmd/LICENSE.txt
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
elif [[ "${osLabel}" == "linux" ]]; then
	fWarn "nfpm missing; skipping .deb/.rpm - go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## What is deliberately not built here yet, so a missing artifact reads as a
## known gap rather than a silent one.

fWarn "windows, BSD, and Linux cross-architecture builds need a Wasmtime archive vendored per target; not built"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## GitHub rewrites '~' to '.' in an uploaded asset filename, so a Debian-style
## name would reach a downloader spelled differently from the way checksums.txt
## lists it. Rename before hashing and the two agree. Only the filename changes -
## the version recorded inside the package keeps the '~' that sorts it ahead of
## the final release.

for artifact in "${OUT}"/*'~'*; do
	[[ -e "${artifact}" ]] || continue
	mv "${artifact}" "${artifact//\~/.}"
done


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Checksums over everything produced.

## Built aside and moved into place, so the file being written is never also one
## of the files being hashed.
## The marker is bookkeeping, not an artifact, so it is hashed by nothing and
## counted in nothing.
## Not every macOS has sha256sum. shasum prints the same thing.
sha256=(sha256sum)
command -v sha256sum >/dev/null 2>&1 || sha256=(shasum -a 256)
( cd "${OUT}" && find . -maxdepth 1 -type f ! -name "${outMarker}" | sed 's|^\./||' | sort \
	| xargs "${sha256[@]}" > "${work}/checksums.txt" )
mv "${work}/checksums.txt" "${OUT}/checksums.txt"

fEcho "done: $(find "${OUT}" -maxdepth 1 -type f ! -name checksums.txt ! -name "${outMarker}" | wc -l | tr -d ' ') artifacts in ${OUT}"


##	History:
##		- 20261003 JC: Universal on a Mac: an x86_64 and an arm64 slice, merged by lipo.
##		- 20261002 JC: Build for a named target: baseline CPU, glibc 2.28, macOS 13.0. macOS host.
##		- 20260917 JC: Drop the header from the deb and rpm; keep the library symlinks.
##		- 20260805 JC: Name packages the way GitHub will serve them.
##		- 20260804 JC: Created. Host-platform tarball, bare binary, deb, rpm, checksums.
