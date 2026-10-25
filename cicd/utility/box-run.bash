#!/usr/bin/env bash

# shellcheck disable=2016  ## The remote lines are single-quoted on purpose, to expand there.

##	Purpose:
##		Runs a job on a test box over ssh. Sends <job dir> to a work folder of
##		its own under the box's temp root, runs its job.bash there, and removes
##		the folder through the guard. cicd.bash runs this under the host lock.
##		The verdict file gets one line, "pass", "fail <why>" or "skip <why>",
##		so the caller can tell a box that never answered from a job that failed.
##	Syntax:
##		box-run.bash <ssh destination> <job dir> <verdict file>
##	Notes:
##		- ZUID_SSH names another ssh, for the tests.
##		- ZUID_BOX_KEEP=1 keeps the work folder on the box, and says where.
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

dest="${1:?ssh destination}"; jobDir="${2:?job dir}"; verdict="${3:?verdict file}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
guard="${here}/include/safe-rm.bash"
sshCmd="${ZUID_SSH:-ssh}"
sshOpts=(-o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30 -o ServerAliveCountMax=4)

fVerdict(){ printf '%s\n' "$*" > "${verdict}" ;}
fSsh(){ "${sshCmd}" "${sshOpts[@]}" "${dest}" "$@" ;}

: > "${verdict}"
[[ -f "${jobDir}/job.bash" ]] || { fVerdict "fail no job.bash in ${jobDir}"; exit 0; }
[[ -f "${guard}" ]]           || { fVerdict "fail no ${guard}"; exit 0; }

if ! fSsh true < /dev/null > /dev/null 2>&1; then fVerdict "skip no answer from ${dest}"; exit 0; fi

## The box's own run folder, made and swept the same way as here. Its temp
## root is HOST_TEMP if the box sets it for ssh, else TMPDIR, else /tmp.
boxDir="$({ cat "${guard}"; printf '%s\n' 'fRunDir_Make zuid "$1" && fRunDir_Sweep && printf "%s\n" "${safeRmRunDir}"'; } \
	| fSsh bash -s -- "$(date +%Y%m%d-%H%M%S)")" || boxDir=""
if [[ ! "${boxDir}" =~ ^/[A-Za-z0-9._/-]+_[0-9]{3}$ ]]; then
	fVerdict "fail could not make a work folder on ${dest}: '${boxDir}'"; exit 0
fi
echo "Box ........: ${dest}:${boxDir}"

if ! tar -C "${jobDir}" -cf - . | fSsh tar -xf - -C "${boxDir}"; then
	fVerdict "fail could not send the job to ${dest}"
else
	## job.bash gets no stdin, since bash -s is reading this from it.
	rc=0
	{ cat "${guard}"; printf '%s\n' \
		'safeRmOwn="${1%/*}"; export ZUID_RUN_DIR="$1" TMPDIR="$1" TEMP="$1" TMP="$1"' \
		'cd "$1" && bash ./job.bash < /dev/null; rc=$?' \
		'cd / && if [[ "$2" == 1 ]]; then echo "Kept .......: $1"; else fSafeRm "$1" || rc=1; fi' \
		'exit "${rc}"'; } \
		| fSsh bash -s -- "${boxDir}" "${ZUID_BOX_KEEP:-0}" || rc=$?
	## 255 is ssh's own, so the box went away mid-job.
	if   ((rc == 0));   then fVerdict "pass"
	elif ((rc == 255)); then fVerdict "skip lost ${dest} partway through"
	else                     fVerdict "fail the job on ${dest} exited ${rc}"; fi
	exit 0
fi

## The send failed, so nothing ran. Take the folder back off.
{ cat "${guard}"; printf '%s\n' 'safeRmOwn="${1%/*}"; fSafeRm "$1"'; } | fSsh bash -s -- "${boxDir}" || true
exit 0

##	History:
##		- 20261025 JC: Created, for the test boxes.
