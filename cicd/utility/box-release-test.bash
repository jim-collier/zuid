#!/usr/bin/env bash

##	Purpose:
##		Runs on a test box as job.bash, in the folder box-run.bash sent. Unpacks
##		the one release tarball there, runs cli-test.bash on its command, then
##		builds capi_smoke.c against its libraries, shared and static, with the
##		link line zuid.h gives for the platform, and runs both.
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
shopt -s nullglob
tarballs=(zuid-*.tgz)
shopt -u nullglob
((${#tarballs[@]} == 1)) || fDie "wants one zuid-*.tgz here, found ${#tarballs[@]}"
tar -xzf "${tarballs[0]}"
shopt -s nullglob
trees=("${here}"/zuid-v*/)
shopt -u nullglob
((${#trees[@]} == 1)) || fDie "the tarball didn't unpack to one zuid-v* folder"
tree="${trees[0]%/}"
fSay "Box" "$(uname -srm)"
fSay "Release" "${tarballs[0]}, $("${tree}/bin/zuid" --version | head -n 1)"

bash ./cicd/utility/cli-test.bash --bin "${tree}/bin/zuid"

## zuid.h's link lines, per platform.
cc="${CC:-cc}"
command -v "${cc}" > /dev/null || fDie "no ${cc} here"
case "$(uname -s)" in
	FreeBSD) staticLibs=(-lzuid -lwasmtime -lzstd); sysLibs=(-lpthread -lm) ;;
	Linux)   staticLibs=(-lzuid -lwasmtime);        sysLibs=(-lpthread -ldl -lm) ;;
	*)       fDie "no link line here for $(uname -s)" ;;
esac
"${cc}" -I "${tree}/include" capi_smoke.c -L "${tree}/lib" -lzuid -Wl,-rpath,"${tree}/lib" -o smoke-shared \
	|| fDie "capi_smoke.c didn't link against the shared library"
./smoke-shared || fDie "capi_smoke.c failed against the shared library"
fSay "Smoke" "shared library passed"
"${cc}" -I "${tree}/include" capi_smoke.c -L "${tree}/lib" -Wl,-Bstatic "${staticLibs[@]}" -Wl,-Bdynamic "${sysLibs[@]}" -o smoke-static \
	|| fDie "capi_smoke.c didn't link against the static library"
./smoke-static || fDie "capi_smoke.c failed against the static library"
fSay "Smoke" "static library passed"

##	History:
##		- 20261025 JC: Created, for the FreeBSD box.
