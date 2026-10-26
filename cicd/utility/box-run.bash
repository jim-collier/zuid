#!/usr/bin/env bash

# shellcheck disable=2016  ## The remote lines are single-quoted on purpose, to expand there.

##	Purpose:
##		Runs a job on a test box over ssh. Sends <job dir> to a work folder of
##		its own under the box's temp root, runs its job.bash there, and removes
##		the folder through the guard. cicd.bash runs this under the host lock.
##		A job dir with a job.ps1 is for a Windows box, which has no bash, so
##		there box-run.ps1 does the box's half, run with -File.
##		The verdict file gets one line, "pass", "fail <why>" or "skip <why>",
##		so the caller can tell a box that never answered from a job that failed.
##	Syntax:
##		box-run.bash <ssh destination> <job dir> <verdict file>
##	Notes:
##		- ZUID_SSH names another ssh, for the tests.
##		- ZUID_BOX_KEEP=1 keeps the work folder on the box, and says where.
##		- ZUID_BOX_BACK=<dir> brings the box folder's back/ home into <dir>,
##		  after a job that passed.
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
back="${ZUID_BOX_BACK:-}"
sshOpts=(-o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30 -o ServerAliveCountMax=4)

fVerdict(){ printf '%s\n' "$*" > "${verdict}" ;}
fSsh(){ "${sshCmd}" "${sshOpts[@]}" "${dest}" "$@" ;}

: > "${verdict}"
onWindows=0; [[ -f "${jobDir}/job.ps1" ]] && onWindows=1
[[ -f "${jobDir}/job.bash" ]] || ((onWindows)) || { fVerdict "fail no job.bash in ${jobDir}"; exit 0; }
[[ -f "${guard}" ]]           || { fVerdict "fail no ${guard}"; exit 0; }

## 'exit 0' is the one probe both cmd and a POSIX shell take.
if ! fSsh exit 0 < /dev/null > /dev/null 2>&1; then fVerdict "skip no answer from ${dest}"; exit 0; fi

## The verdict from the job's exit code and what went wrong after it. 255 is
## ssh's own, so the box went away mid-job.
fVerdict_Job(){  ## job's exit code, why
	if   (($1 == 255)); then fVerdict "skip lost ${dest} partway through"
	elif (($1 != 0));   then fVerdict "fail the job on ${dest} exited $1"
	elif [[ -n "$2" ]]; then fVerdict "fail $2"
	else                     fVerdict "pass"; fi
}

if ((onWindows)); then
	fWinPs(){ fSsh powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass "$@" ;}
	psHalf="${here}/box-run.ps1"
	[[ -f "${psHalf}" ]] || { fVerdict "fail no ${psHalf}"; exit 0; }
	## Made here rather than by box-run.ps1, which has nowhere to go yet. With
	## forward slashes, which Windows takes and cmd's quoting leaves alone.
	makeDir='$ErrorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"
$root = if ($env:HOST_TEMP) { $env:HOST_TEMP } else { $env:TEMP }
$base = Join-Path $root "zuid"
New-Item -ItemType Directory -Force -Path $base | Out-Null
foreach ($n in 1..999) {
	$d = Join-Path $base ("STAMP_{0:000}" -f $n)
	try { $made = New-Item -ItemType Directory -Path $d } catch { continue }
	$made.FullName -replace "\\", "/"
	exit 0
}
exit 1'
	makeDir="${makeDir//STAMP/$(date +%Y%m%d-%H%M%S)}"
	## Its stderr only on a failure, since the first PowerShell of a session can
	## send a progress record there as CLIXML.
	makeErr="${verdict}.err"
	boxDir="$(fWinPs -EncodedCommand "$(printf '%s' "${makeDir}" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')" < /dev/null 2> "${makeErr}" | tr -d '\r')" || boxDir=""
	if [[ ! "${boxDir}" =~ ^([A-Za-z]:)?/[^\"\']+/[0-9]{8}-[0-9]{6}_[0-9]{3}$ ]]; then
		cat "${makeErr}" >&2; rm -f "${makeErr}"
		fVerdict "fail could not make a work folder on ${dest}: '${boxDir}'"; exit 0
	fi
	rm -f "${makeErr}"
	echo "Box ........: ${dest}:${boxDir}"
	rc=0; why=""; sent=1
	if ! tar -cf - -C "${jobDir}" . -C "${here}" box-run.ps1 | fSsh tar -xf - -C "\"${boxDir}\""; then sent=0
	else
		fWinPs -File "\"${boxDir}/box-run.ps1\"" -Run "\"${boxDir}\"" < /dev/null || rc=$?
	fi
	if [[ "${ZUID_BOX_KEEP:-0}" == 1 ]]; then echo "Kept .......: ${dest}:${boxDir}"
	elif ! fWinPs -File "\"${boxDir}/box-run.ps1\"" -Remove "\"${boxDir}\"" < /dev/null; then why="could not remove ${dest}:${boxDir}"
	fi
	if ((sent)); then fVerdict_Job "${rc}" "${why}"; else fVerdict "fail could not send the job to ${dest}"; fi
	exit 0
fi

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
		'export ZUID_RUN_DIR="$1" TMPDIR="$1" TEMP="$1" TMP="$1"' \
		'cd "$1" && bash ./job.bash < /dev/null'; } \
		| fSsh bash -s -- "${boxDir}" || rc=$?
	why=""
	if ((rc == 0)) && [[ -n "${back}" ]]; then
		mkdir -p "${back}"
		fSsh tar -cf - -C "${boxDir}/back" . < /dev/null | tar -xf - -C "${back}" || why="could not bring back/ home from ${dest}"
	fi
	if [[ "${ZUID_BOX_KEEP:-0}" == 1 ]]; then echo "Kept .......: ${dest}:${boxDir}"
	elif ! { cat "${guard}"; printf '%s\n' 'safeRmOwn="${1%/*}"; fSafeRm "$1"'; } | fSsh bash -s -- "${boxDir}"; then
		if ((rc == 0)) && [[ -z "${why}" ]]; then why="could not remove ${dest}:${boxDir}"; fi
	fi
	fVerdict_Job "${rc}" "${why}"
	exit 0
fi

## The send failed, so nothing ran. Take the folder back off.
{ cat "${guard}"; printf '%s\n' 'safeRmOwn="${1%/*}"; fSafeRm "$1"'; } | fSsh bash -s -- "${boxDir}" || true
exit 0

##	History:
##		- 20261025 JC: Created, for the test boxes.
##		- 20261025 JC: ZUID_BOX_BACK, for the Mac's release.
##		- 20261025 JC: Windows, through box-run.ps1.
