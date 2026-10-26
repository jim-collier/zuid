#!/usr/bin/env bash

##	Purpose:
##		Runs on a Mac as job.bash, in the folder box-run.bash sent. Clones the
##		commit from src.bundle, runs a quick cicd.bash with --package there, and
##		leaves the universal tarball, the bare command and their debug info in
##		back/ for box-run.bash to bring home.
##	Syntax:
##		bash ./job.bash
##	Notes:
##		- Wasmtime's macOS archives are kept between runs in the user's cache
##		  dir, so each run doesn't fetch them again. cicd.bash still checks
##		  their version stamp.
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

fSay(){ printf '%-11s: %s\n' "$1" "$2" ;}
fDie(){ printf 'box job: %s\n' "$*" >&2; exit 1 ;}

## A non-interactive ssh may have only Apple's bash 3.2 on PATH.
PATH="/usr/local/bin:/opt/homebrew/bin:${PATH}"

[[ -f src.bundle ]] || fDie "no src.bundle here"
git -c advice.detachedHead=false clone -q src.bundle repo
fSay "Box" "$(uname -srm), macOS $(sw_vers -productVersion 2>/dev/null || echo '?')"
fSay "Commit" "$(git -C repo log -1 --format='%h %cI')"

## By its physical path, since the guard refuses one through a link.
mkdir -p "${HOME}/Library/Caches/zuid-cicd/vendor" repo/zig/vendor
vendorCache="$(cd -P "${HOME}/Library/Caches/zuid-cicd/vendor" && pwd -P)"
shopt -s nullglob
cached=("${vendorCache}"/wasmtime*)
shopt -u nullglob
if ((${#cached[@]})); then cp -R "${cached[@]}" repo/zig/vendor/; fi

rc=0
## From the repo root, where the shellcheck source hints resolve.
(cd repo && bash cicd/cicd.bash -q --quick --package --no-fuzz --no-sync --no-backup --no-dogfood --no-remote) || rc=$?

## Kept even from a run that failed, since the fetch is what's slow. Only a
## pin that moved replaces one.
# shellcheck source=cicd/utility/include/safe-rm.bash
source repo/cicd/utility/include/safe-rm.bash
shopt -s nullglob
fresh=(repo/zig/vendor/wasmtime*)
shopt -u nullglob
for dir in "${fresh[@]}"; do
	kept="${vendorCache}/${dir##*/}"
	[[ -f "${dir}/.version" ]] || continue
	if cmp -s "${dir}/.version" "${kept}/.version"; then continue; fi
	if [[ -e "${kept}" ]]; then fSafeRm_Under "${vendorCache}" "${kept}" > /dev/null || continue; fi
	cp -R "${dir}" "${kept}"
done
((rc == 0)) || fDie "cicd.bash exited ${rc}"

## The tarball and the bare command, the two files --publish takes from a Mac.
shopt -s nullglob
tarballs=(repo/dist/zuid-*-darwin-universal.tgz)
shopt -u nullglob
((${#tarballs[@]} == 1)) || fDie "wants one zuid-*-darwin-universal.tgz in dist/, found ${#tarballs[@]}"
release="${tarballs[0]##*/}"; release="${release%.tgz}"
mkdir -p back
cp "${tarballs[0]}" back/
if [[ -f "repo/dist/${release}" ]]; then cp "repo/dist/${release}" back/; fi
if [[ -d "repo/dist/debug/${release}" ]]; then
	mkdir -p back/debug
	cp -R "repo/dist/debug/${release}" back/debug/
fi
fSay "Back" "$(cd back && printf '%s ' *)"

##	History:
##		- 20261025 JC: Created, for the Mac box.
