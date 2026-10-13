#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		- Builds the release artifacts for whatever platform this machine can
##		  actually produce, into the output directory:
##		    - a tarball of the CLI, its C libraries, and the header, or a zip
##		      for Windows
##		    - the bare CLI binary (grab-and-run)
##		    - .deb and .rpm, via nfpm
##		    - checksums.txt over everything
##		- Every binary built here is stripped. Its debug info goes to debug/
##		  in the output directory, which is not a release file, so a panic
##		  address can still be looked up later.
##		- Only what the host system can make: Linux or macOS. The Go module
##		  cross-compiles fine, but it is a module - there is no binary to
##		  release.
##		- On Linux, one release each for x86_64 and arm64, whichever the host
##		  is, one for x86_64 FreeBSD, and one each for x86_64 and arm64
##		  Windows. cicd.bash --package vendors the Wasmtime archives the host's
##		  own is not.
##		- On a Mac everything is universal, x86_64 and arm64 merged by lipo.
##		  cicd.bash vendors the second Wasmtime archive that needs.
##		- Builds with the zig on PATH. cicd.bash --package puts the Zig it
##		  found first there, so run it that way, or put Zig 0.17.0 first.
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

## Zig 0.17 hands SOURCE_DATE_EPOCH to clang when it builds its own libunwind
## and libc, and clang refuses anything but a number, empty included. Each
## target is a cold cache the first time. build.zig takes the commit date
## without it.
if [[ -n "${SOURCE_DATE_EPOCH+set}" ]] && [[ ! "${SOURCE_DATE_EPOCH}" =~ ^[0-9]+$ ]]; then
	if [[ -n "${SOURCE_DATE_EPOCH//[[:space:]]/}" ]]; then
		fWarn "SOURCE_DATE_EPOCH '${SOURCE_DATE_EPOCH}' is not a number; ignored, so the build number comes from the commit date"
	fi
	unset SOURCE_DATE_EPOCH
fi

## Every file in a tarball, zip or package gets this one time, so two machines
## building one commit make the same bytes. Same order as build.zig's build
## number, and never the clock. A zip can't hold a time before 1980.
stamp="${SOURCE_DATE_EPOCH:-}"
if [[ -z "${stamp}" ]]; then stamp="$(git -C "${root}" log -1 --format=%ct 2>/dev/null || true)"; fi
if [[ ! "${stamp}" =~ ^[0-9]+$ ]]; then
	fWarn "no SOURCE_DATE_EPOCH and no commit date; archive times are 1980-01-01"
	stamp=0
fi
stamp=$((10#${stamp}))
((stamp >= 315532800)) || stamp=315532800
## touch and nfpm both read this form.
if date --version >/dev/null 2>&1; then
	stampIso="$(date -u -d "@${stamp}" +%Y-%m-%dT%H:%M:%SZ)"
else
	stampIso="$(date -u -r "${stamp}" +%Y-%m-%dT%H:%M:%SZ)"
fi

## A relative --out is resolved against the caller's directory.
[[ "${OUT}" = /* ]] || OUT="${PWD}/${OUT}"

## nfpm turns 1.1.0-beta7 into 1.1.0~beta7 itself, which is what Debian and RPM
## read as "sorts before the final release".
plainver="${VERSION#v}"

## Only to tell which Wasmtime archive is the build machine's own.
hostArch="$(uname -m)"
case "${hostArch}" in
	x86_64)          zigArch="x86_64"  ;;
	aarch64|arm64)   zigArch="aarch64" ;;
	*) echo "unsupported architecture: ${hostArch}" >&2; exit 2 ;;
esac

## With no target named, Zig builds for this machine: its CPU's newest
## instructions, its glibc, its macOS version. A release has to run on older
## ones. Naming a target also gives that target's baseline CPU: plain armv8-a
## for arm64 Linux, and the M1 for arm64 macOS, the oldest there is. 2.28 and
## 13.0 are what cicd.bash checks the result against; 13.0 is as far back as Zig
## goes. FreeBSD 14.0 matches the package repo its Wasmtime comes from.
## Windows has no version in the target; Zig's floor there is Windows 10.
## Linux makes one release per architecture. A Mac builds one slice per
## architecture and merges them into one release, whichever it is.
mergeSlices=0
case "$(uname -s)" in
	Linux)  hostOs="linux"; zigTargets=("x86_64-linux-gnu.2.28" "aarch64-linux-gnu.2.28" "x86_64-freebsd.14.0" "x86_64-windows-gnu" "aarch64-windows-gnu") ;;
	Darwin) hostOs="macos"; zigTargets=("x86_64-macos.13.0" "aarch64-macos.13.0"); mergeSlices=1 ;;
	*) echo "unsupported system: $(uname -s)" >&2; exit 2 ;;
esac

## The label users see, and nfpm's name for the architecture. amd64 is spelled
## x86_64 because "AMD64" reads as a processor brand to anyone who has not met
## the convention. nfpm turns arm64 into aarch64 for the rpm itself.
fArchLabel(){ case "$1" in aarch64*) echo "arm64" ;; *) echo "x86_64" ;; esac ;}
## The name in the asset, which the installers ask for. Zig says macos.
fOsLabel(){   case "$1" in *-macos*) echo "darwin" ;; *-freebsd*) echo "freebsd" ;; *-windows*) echo "windows" ;; *) echo "linux" ;; esac ;}
fGoArch(){    case "$1" in arm64) echo "arm64" ;; *) echo "amd64" ;; esac ;}

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
## "no entry" for the same name - so this needs llvm-ar. A box without it gets a
## warning here, and the package stage's path check then fails.
## Zig's Mach-O archives use basenames already.
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
	## members mode 000, so they come out unreadable. Windows members are .obj.
	( cd "${extractDir}" && "${llvmAr}" x "${archive}" && chmod u+r ./* && "${llvmAr}" rcsD "${archive}.new" ./* )
	mv "${archive}.new" "${archive}"
}

## Same rule as build.zig: the build machine's own Wasmtime is vendor/wasmtime,
## and any other target's is beside it under Wasmtime's platform name.
fWasmtimeDir(){  ## zig target
	local -r arch="${1%%-*}" rest="${1#*-}"
	local -r os="${rest%%[-.]*}"
	if [[ "${arch}" == "${zigArch}" && "${os}" == "${hostOs}" ]]; then
		echo "${root}/zig/vendor/wasmtime"
	else
		echo "${root}/zig/vendor/wasmtime-${arch}-${os}"
	fi
}

## Also build.zig's rule. arm64 Windows links Wasmtime's DLL through its import
## library, since Wasmtime has no mingw build for it.
fWasmtimeArchive(){  ## zig target
	case "$1" in
		aarch64-windows*) echo "$(fWasmtimeDir "$1")/lib/wasmtime.dll.lib" ;;
		*)                echo "$(fWasmtimeDir "$1")/lib/libwasmtime.a" ;;
	esac
}

## Each slice is a whole tree. zuid.h tells a static consumer to link -lzuid
## -lwasmtime, so the archive it names goes in too. libzuid.a holds its own
## objects only, and the release used to carry no wasmtime at all, which left
## that link line with nothing to satisfy it.
lipo=""
if ((mergeSlices)); then
	lipo="$(command -v lipo || true)"
	[[ -n "${lipo}" ]] || fDie "lipo not found. It comes with Xcode's command line tools."
fi
## Windows releases are zips, which is what Windows opens by itself and what
## install.ps1 expects. Like nfpm, a box without zip skips them with a warning.
haveZip=0
if command -v zip >/dev/null 2>&1; then haveZip=1; fi
if [[ "${hostOs}" == "linux" ]] && ((! haveZip)); then
	fWarn "zip missing; skipping the Windows releases"
	zigTargets=("${zigTargets[@]/*-windows-*/}")
fi

## Debug info has the paths of this machine's Zig, its caches and the checkout,
## and differs between two machines building one commit. llvm-objcopy reads
## ELF and Windows files alike. A Mac has Apple's own tools for Mach-O.
objcopy=""
if ((mergeSlices)); then
	for tool in strip dsymutil codesign; do
		command -v "${tool}" >/dev/null 2>&1 || fDie "${tool} not found. It comes with Xcode's command line tools."
	done
else
	for candidate in llvm-objcopy llvm-objcopy-21 llvm-objcopy-20 llvm-objcopy-19 llvm-objcopy-18 llvm-objcopy-17 llvm-objcopy-16; do
		if command -v "${candidate}" >/dev/null 2>&1; then objcopy="${candidate}"; break; fi
	done
	[[ -n "${objcopy}" ]] || fDie "llvm-objcopy not found. Release binaries are stripped with it; it comes with LLVM."
fi

## Strips a slice in place, keeping what it took out under the debug dir, laid
## out like the release. A program or shared library keeps its symbols and
## DWARF in <name>.debug, or <name>.dSYM on a Mac. A static library keeps its
## symbols, since linking needs them, and its unstripped copy goes to debug/.
## Windows PDBs move there whole: the command's from bin/, and the DLL's from
## lib/, where build.zig puts it, since both are zuid.pdb.
## Wasmtime's and zstd's files are left as their projects ship them.
fStripSlice(){  ## slice, debug dir, zig target
	local -r slice="$1" debugDir="$2" zigTarget="$3"
	local file="" name="" sub=""
	mkdir -p "${debugDir}/bin" "${debugDir}/lib"
	for file in "${slice}"/bin/* "${slice}"/lib/*; do
		[[ -f "${file}" && ! -L "${file}" ]] || continue
		name="${file##*/}"
		sub="$(basename "$(dirname "${file}")")"
		case "${name}" in
			*wasmtime* | libzstd.a | zuid.lib) continue ;;
			*.pdb) mv "${file}" "${debugDir}/${sub}/"; continue ;;
		esac
		if ((mergeSlices)); then
			case "${name}" in
				*.a) cp "${file}" "${debugDir}/${sub}/"; strip -S "${file}" ;;
				*)
					dsymutil "${file}" -o "${debugDir}/${sub}/${name}.dSYM"
					strip -S -x "${file}"
					## Stripping voids the ad-hoc signature an arm64 Mac needs to
					## load anything at all.
					if [[ "${zigTarget}" == aarch64-* ]]; then codesign --force --sign - "${file}"; fi
					;;
			esac
		else
			case "${name}" in
				*.a) cp "${file}" "${debugDir}/${sub}/"; "${objcopy}" --strip-debug "${file}" ;;
				*)
					"${objcopy}" --only-keep-debug "${file}" "${debugDir}/${sub}/${name}.debug"
					"${objcopy}" --strip-all "${file}"
					;;
			esac
		fi
	done
}

## Each release's debug dir. A Mac strips each slice before lipo merges them, so
## its debug info is kept per CPU.
fDebugDir(){  ## zig target
	if ((mergeSlices)); then
		echo "${work}/debug/${PKG}-darwin-universal/$(fArchLabel "$1")"
	else
		echo "${work}/debug/${PKG}-$(fOsLabel "$1")-$(fArchLabel "$1")"
	fi
}

## Every slice is built before anything is staged, so a build that fails leaves
## the last good run's artifacts alone.
slices=()
for zigTarget in "${zigTargets[@]}"; do
	[[ -n "${zigTarget}" ]] || continue
	slice="${work}/slice-${zigTarget}"
	wasmtimeArchive="$(fWasmtimeArchive "${zigTarget}")"
	[[ -f "${wasmtimeArchive}" ]] || fDie "missing ${wasmtimeArchive}. Run cicd.bash --package first; it vendors Wasmtime."
	( cd "${root}/zig" && zig build -Doptimize=ReleaseSafe -Dtarget="${zigTarget}" --prefix "${slice}" )
	case "${zigTarget}" in
		## The command and both libraries load wasmtime.dll, so it goes beside
		## them. Its import library is renamed to what -lwasmtime finds, for a
		## static link of libzuid.a, the way zuid.lib goes with zuid.dll.
		aarch64-windows*)
			cp "$(dirname "${wasmtimeArchive}")/wasmtime.dll" "${slice}/bin/"
			cp "${wasmtimeArchive}" "${slice}/lib/wasmtime.lib"
			;;
		*)
			cp "${wasmtimeArchive}" "${slice}/lib/"
			;;
	esac
	## FreeBSD's Wasmtime calls zstd, so a static consumer needs it too.
	if [[ "$(fOsLabel "${zigTarget}")" == "freebsd" ]]; then
		cp "$(dirname "${wasmtimeArchive}")/libzstd.a" "${slice}/lib/"
	fi
	fNormalizeArchive "${slice}/lib/libzuid.a"
	fStripSlice "${slice}" "$(fDebugDir "${zigTarget}")" "${zigTarget}"
	slices+=("${slice}")
done

## The build worked, so there is something to publish. Safe to clear now.
fClaimOutDir
mv "${work}/debug" "${OUT}/debug"

## Two or more slices are merged file by file. Symlinks come from the first, and
## everything else is one file holding every slice. -P, because the shared
## library carries an soname: lib/ holds libzuid.so and libzuid.so.1 as symlinks
## onto libzuid.so.1.0.0, and a plain cp would follow them and put three 28 MB
## copies in the tarball.
fMergeSlices(){  ## stage, subdir, slice...
	local -r stage="$1" sub="$2"; shift 2
	local -ra parts=("$@")
	local item="" name="" part=""
	local -a files=()
	for item in "${parts[0]}/${sub}/"*; do
		name="$(basename "${item}")"
		if [[ -L "${item}" ]] || ((${#parts[@]} == 1)); then
			cp -P "${item}" "${stage}/${sub}/"
			continue
		fi
		files=()
		for part in "${parts[@]}"; do files+=("${part}/${sub}/${name}"); done
		"${lipo}" -create "${files[@]}" -output "${stage}/${sub}/${name}"
	done
}

## An archive keeps each file's time, owner, mode and place in the list, which
## would otherwise come from the clock, the user, the umask and the directory
## order. Modes keep only whether a file runs.
fSettleTree(){  ## dir
	local -r dir="$1"
	find "${dir}" -type d -exec chmod 0755 {} +
	find "${dir}" -type f -perm -u+x -exec chmod 0755 {} +
	find "${dir}" -type f ! -perm -u+x -exec chmod 0644 {} +
	find "${dir}" -exec touch -h -d "${stampIso}" {} +
}

## Byte order, the same under any locale or filesystem.
fTreeList(){  ## parent dir, tree name
	( cd "$1" && find "$2" | LC_ALL=C sort )
}

## GNU tar on Linux, bsdtar on a Mac. Owner 0 by number, with no names.
tarFlags=(--uid 0 --gid 0 --numeric-owner --no-mac-metadata --no-xattrs)
if [[ "$(tar --version 2>/dev/null || true)" == *"GNU tar"* ]]; then
	tarFlags=(--owner=0 --group=0 --numeric-owner)
fi

fTarball(){  ## tree, output
	local -r parent="$(dirname "$1")" tree="$(basename "$1")"
	fTreeList "${parent}" "${tree}" | tar -C "${parent}" -cf - --no-recursion "${tarFlags[@]}" -T - | gzip -n > "$2"
}

## Zip keeps local time, so the zone is pinned too. -X drops the owner and the
## extra time fields.
fZip(){  ## tree, output
	local -r parent="$(dirname "$1")" tree="$(basename "$1")"
	fTreeList "${parent}" "${tree}" | ( cd "${parent}" && TZ=UTC0 zip -q -X -@ "$2" )
}

## One release: the tarball, the bare binary and, on Linux, the packages.
## Windows gets a zip, and its bare binary only where it runs alone.
fRelease(){  ## os label, arch label, slice...
	local -r osLabel="$1" label="$2"; shift 2
	local exe="${EXE}"
	if [[ "${osLabel}" == "windows" ]]; then exe="${EXE}.exe"; fi
	## Per OS as well, or a release takes in the files of the one before it on
	## the same CPU.
	local -r stage="${work}/release-${osLabel}-${label}/${PKG}-${VERSION}"
	mkdir -p "${stage}/bin" "${stage}/lib" "${stage}/include" "${stage}/share"
	fMergeSlices "${stage}" bin "$@"
	fMergeSlices "${stage}" lib "$@"

	cp "$1/include/zuid.h"                     "${stage}/include/"
	cp "${root}/license.md"                    "${stage}/share/"
	cp "${root}/zig/cmd/LICENSE.txt"           "${stage}/share/"
	cp "${root}/zig/lib/LICENSE.txt"           "${stage}/share/LICENSE-module.txt"
	cp "${root}/zig/lib/NOTICE.txt"            "${stage}/share/"
	cp "${root}/README.md"                     "${stage}/share/"
	## Every release has Wasmtime in it, if only inside the command, so every
	## one has its license. Each slice of a universal release has the same pin.
	cp "$(fWasmtimeDir "${1##*/slice-}")/LICENSE" "${stage}/share/LICENSE-wasmtime.txt"
	if [[ -f "${stage}/lib/libzstd.a" ]]; then
		cp "${root}/zig/vendor/wasmtime-x86_64-freebsd/LICENSE-zstd" "${stage}/share/LICENSE-zstd.txt"
	fi
	fSettleTree "${stage}"

	if [[ "${osLabel}" == "windows" ]]; then
		fZip "${stage}" "${OUT}/${PKG}-${osLabel}-${label}.zip"
		## arm64 needs wasmtime.dll beside it, so it is not one file there.
		if [[ ! -f "${stage}/bin/wasmtime.dll" ]]; then
			cp "${stage}/bin/${exe}" "${OUT}/${PKG}-${osLabel}-${label}.exe"
		fi
	else
		fTarball "${stage}" "${OUT}/${PKG}-${osLabel}-${label}.tgz"
		cp "${stage}/bin/${exe}" "${OUT}/${PKG}-${osLabel}-${label}"
	fi
	fEcho "built ${osLabel}/${label}"
	if [[ "${osLabel}" == "linux" ]]; then fLinuxPackages "${stage}" "${label}"; fi
}


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

haveNfpm=0
if command -v nfpm >/dev/null 2>&1; then haveNfpm=1; fi
if [[ "${hostOs}" == "linux" ]] && ((! haveNfpm)); then
	fWarn "nfpm missing; skipping .deb/.rpm - go install github.com/goreleaser/nfpm/v2/cmd/nfpm@latest"
fi

fLinuxPackages(){  ## stage, label
	local -r stage="$1" label="$2"
	((haveNfpm)) || return 0
	local -r cfg="${work}/nfpm-${label}.yaml"
	cat >"${cfg}" <<-EOF
		name: ${PKG}
		arch: $(fGoArch "${label}")
		version: ${plainver}
		maintainer: ${MAINTAINER}
		description: |
		  ${SUMMARY}.
		  ${DESC_LONG}
		homepage: ${HOMEPAGE}
		license: GPL-2.0-or-later AND Apache-2.0
		section: utils
		priority: optional
		mtime: "${stampIso}"
		rpm:
		  buildhost: reproducible
		contents:
		  - src: ${stage}/bin/${EXE}
		    dst: /usr/bin/${EXE}
		    file_info:
		      mode: 0755
		  - src: ${root}/zig/cmd/LICENSE.txt
		    dst: /usr/share/doc/${PKG}/copyright
		    packager: deb
		    file_info:
		      mode: 0644
		  - src: ${root}/zig/cmd/LICENSE.txt
		    dst: /usr/share/licenses/${PKG}/LICENSE.txt
		    packager: rpm
		    file_info:
		      mode: 0644
	EOF
	## The command links the module and Wasmtime in, so their licenses go too.
	local file=""
	for file in LICENSE-module.txt NOTICE.txt LICENSE-wasmtime.txt; do
		cat >>"${cfg}" <<-EOF
			  - src: ${stage}/share/${file}
			    dst: /usr/share/doc/${PKG}/${file}
			    packager: deb
			    file_info:
			      mode: 0644
			  - src: ${stage}/share/${file}
			    dst: /usr/share/licenses/${PKG}/${file}
			    packager: rpm
			    file_info:
			      mode: 0644
		EOF
	done
	local fmt=""
	for fmt in deb rpm; do
		if nfpm package --config "${cfg}" --packager "${fmt}" --target "${OUT}/" >/dev/null 2>&1; then
			fEcho "built .${fmt} (${label})"
		else
			fWarn "nfpm ${fmt} failed (${label})"
		fi
	done
}

if ((mergeSlices)); then
	fRelease "darwin" "universal" "${slices[@]}"
else
	for slice in "${slices[@]}"; do
		fRelease "$(fOsLabel "${slice##*/slice-}")" "$(fArchLabel "${slice##*/slice-}")" "${slice}"
	done
fi


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

fEcho "done: $(find "${OUT}" -maxdepth 1 -type f ! -name checksums.txt ! -name "${outMarker}" | wc -l | tr -d ' ') artifacts in ${OUT}, debug info in ${OUT}/debug"


##	History:
##		- 20261013 JC: Archives and packages get one time, owner 0, set modes and a sorted list.
##		- 20261013 JC: Strip release binaries; their debug info and PDBs go to debug/.
##		- 20261004 JC: Wasmtime's license in every release, and the module's and Wasmtime's in the deb and rpm.
##		- 20261004 JC: Windows x86_64 and arm64 zips, cross-built on Linux.
##		- 20261004 JC: FreeBSD x86_64, cross-built on Linux from FreeBSD's own Wasmtime package.
##		- 20261003 JC: Linux arm64, cross-built beside x86_64 on any Linux host.
##		- 20261003 JC: Zig 0.17.0.
##		- 20261003 JC: Universal on a Mac: an x86_64 and an arm64 slice, merged by lipo.
##		- 20261002 JC: Build for a named target: baseline CPU, glibc 2.28, macOS 13.0. macOS host.
##		- 20260917 JC: Drop the header from the deb and rpm; keep the library symlinks.
##		- 20260805 JC: Name packages the way GitHub will serve them.
##		- 20260804 JC: Created. Host-platform tarball, bare binary, deb, rpm, checksums.
