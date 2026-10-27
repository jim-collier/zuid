#!/usr/bin/env bash

##	Purpose:
##		Runs on a FreeBSD box as job.bash, in the folder box-run.bash sent.
##		Makes the .pkg with pkg create from the one zuid-*-freebsd-* folder
##		package.bash laid out, checks what pkg reads back from it, installs it
##		under a scratch root and runs the command from there, then leaves it in
##		back/ as <that folder's name>.pkg for box-run.bash to bring home.
##		Runs as root, since pkg add sets owners. Nothing goes outside the
##		folder box-run.bash made.
##	Syntax:
##		bash ./job.bash
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

fSay(){ printf '%-11s: %s\n' "$1" "$2" ;}
fDie(){ printf 'box job: %s\n' "$*" >&2; exit 1 ;}

here="$(pwd -P)"
[[ "$(uname -s)" == "FreeBSD" ]] || fDie "not FreeBSD: $(uname -s)"
command -v pkg > /dev/null || fDie "no pkg here"
shopt -s nullglob
kits=(zuid-*-freebsd-*/)
shopt -u nullglob
((${#kits[@]} == 1)) || fDie "wants one zuid-*-freebsd-* folder here, found ${#kits[@]}"
kit="${here}/${kits[0]%/}"
release="${kit##*/}"
for file in manifest.ucl plist stamp root; do [[ -e "${kit}/${file}" ]] || fDie "no ${file} in ${release}"; done
fSay "Box" "$(uname -srm), pkg $(pkg -v)"

## The stamp is the commit's, as for the tarballs, so one commit makes one .pkg.
## -t, not SOURCE_DATE_EPOCH, which leaves each file's own mtime in +MANIFEST.
mkdir out
pkg create -t "$(< "${kit}/stamp")" -M "${kit}/manifest.ucl" -p "${kit}/plist" -r "${kit}/root" -o out \
	|| fDie "pkg create failed"
shopt -s nullglob
outs=(out/*.pkg)
shopt -u nullglob
((${#outs[@]} == 1)) || fDie "pkg create made ${#outs[@]} files, not one"
made="${here}/${outs[0]}"

## What pkg reads back is what the manifest asked for, not this box's own ABI.
fUcl(){ sed -n "s/^$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "${kit}/manifest.ucl" ;}
want="$(fUcl name)|$(fUcl version)|$(fUcl abi)"
got="$(pkg query -F "${made}" '%n|%v|%q')"
[[ "${got}" == "${want}" ]] || fDie "the .pkg says '${got}', the manifest '${want}'"
fSay "Package" "${made##*/}, ${got//|/ }"

## Every file in the plist, and nothing else.
wantFiles="$(sed 's/^@([^)]*) //; s|^|/usr/local/|' "${kit}/plist" | LC_ALL=C sort)"
gotFiles="$(pkg query -F "${made}" '%Fp' | LC_ALL=C sort)"
[[ "${gotFiles}" == "${wantFiles}" ]] || fDie "the .pkg holds: ${gotFiles//$'\n'/, }"

## pkg add under a root of its own does what it does on /, the ABI and library
## checks included. It sets each file's owner, so this runs as root. That root
## has no base system, so it gets copies of this box's libraries the package
## needs, from where they are here. The command has to run from where it went.
[[ "$(id -u)" == 0 ]] || fDie "pkg add sets owners, so this runs as root, not $(id -un)"
mkdir inst
shlibs=()
while IFS= read -r lib; do
	[[ -n "${lib}" ]] || continue
	for dir in /lib /usr/lib ""; do [[ -z "${dir}" || -f "${dir}/${lib}" ]] && break; done
	[[ -n "${dir}" ]] || fDie "it needs ${lib}, which FreeBSD's base system doesn't have"
	mkdir -p "inst${dir}"
	cp "${dir}/${lib}" "inst${dir}/"
	shlibs+=("${lib}")
done < <(pkg query -F "${made}" '%B')
fSay "Needs" "${shlibs[*]:-nothing}"
pkg -r "${here}/inst" add "${made}" || fDie "pkg add refused it"
installed="${here}/inst/usr/local/bin/zuid"
## Its module cache goes here, not in root's home.
export HOME="${here}/home" XDG_CACHE_HOME="${here}/home/.cache"
mkdir -p "${XDG_CACHE_HOME}"
[[ -x "${installed}" ]] || fDie "pkg add put no ${installed#"${here}"/}"
[[ "$("${installed}" --version | head -n 1)" == "$("${kit}/root/usr/local/bin/zuid" --version | head -n 1)" ]] \
	|| fDie "the installed command says '$("${installed}" --version | head -n 1)'"
"${installed}" > /dev/null || fDie "the installed command failed"
fSay "Installed" "$("${installed}" --version | head -n 1)"

mkdir -p back
cp "${made}" "back/${release}.pkg"
fSay "Back" "${release}.pkg"

##	History:
##		- 20261026 JC: Created, for the FreeBSD .pkg.
##		- 20261027 JC: pkg create -t, so the .pkg doesn't depend on how the files got here.
