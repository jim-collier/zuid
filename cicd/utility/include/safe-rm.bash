#!/bin/bash

# shellcheck disable=2034  ## safeRmOwn is set by whoever sources this.

##	Purpose:
##		The one way the pipeline and its harnesses remove a folder, and make the
##		run folder that sets what they may remove. Source it and call:
##			fSafeRm <path>                  Under a folder named tmp, or under ${safeRmOwn}.
##			fSafeRm_Under <parent> <path>   Strictly under <parent>, for a folder outside any temp root.
##			fRunDir_Make <project> <stamp>  A run folder in the temp root, for cicd.bash.
##			fRunDir_Sweep                   Then the project's stale run folders.
##			fRunDir_Sub <project> <name>    Inside cicd.bash's run folder, or a run folder of its own when run alone.
##			fMkTempDir                      A tmp.* folder in TMPDIR, physical. Prints it.
##		Both take one absolute path, refuse '..', '//', a newline, a link, a path
##		through a link and one that isn't there, and stay on one filesystem.
##		safeRmOwn is the project's own folder in the temp root, realpath'd once, since
##		the macOS and Windows temp folders aren't named tmp.
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

declare safeRmOwn="${safeRmOwn:-}"
## The folder fRunDir_Make or fRunDir_Sub made.
declare safeRmRunDir=""
## What fRunDir_Sweep removed, for the caller to say.
declare -i safeRmSweptN=0 safeRmSweptKb=0
## GNU rm says --one-file-system, BSD's -x.
declare _safeRmOneFs=""

_fSafeRm_Check(){  ## path
	local p="${1:-}" real=''
	if [[ -z "${p}" || "${p}" != /* || "${p}" == *..* || "${p}" == *//* || "${p}" == *$'\n'* ]]; then
		printf 'safe-rm: refused, bad path: "%s"\n' "${p}" >&2; return 1
	fi
	p="${p%/}"
	if [[ -L "${p}" ]]; then printf 'safe-rm: refused, a link: %s\n' "${p}" >&2; return 1; fi
	[[ -e "${p}" ]] || { printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; }
	## No -e: macOS's realpath doesn't have it, and the -e test above covers it.
	real="$(realpath -- "${p}" 2> /dev/null)" || { printf 'safe-rm: refused, not there: %s\n' "${p}" >&2; return 1; }
	if [[ "${real}" != "${p}" ]]; then printf 'safe-rm: refused, goes through a link: %s\n' "${p}" >&2; return 1; fi
}

_fSafeRm_Do(){  ## path
	if [[ -z "${_safeRmOneFs}" ]]; then
		if rm --version > /dev/null 2>&1; then _safeRmOneFs="--one-file-system"; else _safeRmOneFs="-x"; fi
	fi
	rm -rf "${_safeRmOneFs}" -- "${1%/}"
}

fSafeRm(){  ## path
	local p="${1:-}" own="${safeRmOwn%/}"
	if [[ "${#}" -ne 1 ]]; then printf 'safe-rm: refused, wants one path, got %s\n' "${#}" >&2; return 1; fi
	_fSafeRm_Check "${p}" || return 1
	p="${p%/}"
	if ! [[ "${p}" =~ ^/(.+/)?tmp/[^/]+(/[^/]+)*$ || ( -n "${own}" && "${p}" == "${own}"/?* ) ]]; then
		printf 'safe-rm: refused, not under a tmp folder: %s\n' "${p}" >&2; return 1
	fi
	_fSafeRm_Do "${p}"
}

fSafeRm_Under(){  ## parent, path
	local parent="${1:-}" p="${2:-}"
	if [[ "${#}" -ne 2 ]]; then printf 'safe-rm: refused, wants a parent and a path, got %s\n' "${#}" >&2; return 1; fi
	_fSafeRm_Check "${parent}" || return 1
	_fSafeRm_Check "${p}"      || return 1
	parent="${parent%/}"; p="${p%/}"
	if [[ "${p}" != "${parent}"/?* ]]; then
		printf 'safe-rm: refused, not under %s: %s\n' "${parent}" "${p}" >&2; return 1
	fi
	_fSafeRm_Do "${p}"
}

## A scratch folder in TMPDIR, by its physical path, so the guard can take it
## back. Never a bare mktemp -d: macOS's ignores TMPDIR and uses its own temp
## folder, behind the /var link.
fMkTempDir(){
	local root="${TMPDIR:-/tmp}"
	root="$(cd -P -- "${root}" && pwd -P)" || { printf "mktemp: the temp dir '%s' isn't there.\n" "${TMPDIR:-/tmp}" >&2; return 1; }
	mktemp -d "${root%/}/tmp.XXXXXXXXXX"
}

## <parent>/<name>_<NNN>, with a plain mkdir and a counter, so two started in
## one second can't share one. Prints it.
_fRunDir_Next(){  ## parent, name
	local dir="" num="" n=1
	while ((n <= 999)); do
		printf -v num '%03d' "${n}"
		dir="${1}/${2}_${num}"
		if mkdir "${dir}" 2>/dev/null; then printf '%s\n' "${dir}"; return 0; fi
		n=$((n + 1))
	done
	printf 'run-dir: no free folder for %s under %s\n' "${2}" "${1}" >&2; return 1
}

## The run's folder, ${HOST_TEMP}/<project>/<stamp>_<NNN>, with a run.pid, and
## TMPDIR, TEMP, TMP and ZUID_RUN_DIR pointed at it. HOST_TEMP falls back to
## TMPDIR, then /tmp. Physical, since the guard refuses a path through a link
## and macOS's temp folder sits behind /var. Sets safeRmOwn to the project's
## folder and safeRmRunDir to the run's.
fRunDir_Make(){  ## project, stamp
	local root="${HOST_TEMP:-${TMPDIR:-/tmp}}" dir=""
	root="$(realpath -- "${root}" 2>/dev/null)" && [[ -d "${root}" ]] \
		|| { printf "run-dir: the temp root '%s' isn't there.\n" "${HOST_TEMP:-${TMPDIR:-/tmp}}" >&2; return 1; }
	root="${root%/}/${1:?}"
	mkdir -p "${root}" || { printf "run-dir: could not make '%s'.\n" "${root}" >&2; return 1; }
	dir="$(_fRunDir_Next "${root}" "${2:?}")" || return 1
	printf '%s\n' "$$" > "${dir}/run.pid"
	safeRmOwn="${root}"; safeRmRunDir="${dir}"
	export TMPDIR="${dir}" TEMP="${dir}" TMP="${dir}" ZUID_RUN_DIR="${dir}"
}

## The project's run folders over 2 days old, unless their run.pid names a live
## process. Apart from fRunDir_Make, so the caller's exit trap knows the new
## folder before this can be interrupted. The name pattern keeps anything else
## in there out of it.
fRunDir_Sweep(){
	local stale="" pid=""
	local -i kb=0
	[[ -n "${safeRmOwn}" ]] || return 0
	while IFS= read -r stale; do
		[[ "${stale##*/}" =~ ^[0-9]{8}-[0-9]{6}_[0-9]{3}$ ]] || continue
		pid=""; { read -r pid < "${stale}/run.pid" ;} 2>/dev/null || true
		if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then continue; fi
		kb="$(du -sk "${stale}" 2>/dev/null | cut -f1 || true)"
		if fSafeRm "${stale}"; then safeRmSweptN=$((safeRmSweptN + 1)); safeRmSweptKb=$((safeRmSweptKb + kb)); fi
	done < <(find "${safeRmOwn}" -mindepth 1 -maxdepth 1 -type d -mmin +2880 2>/dev/null || true)
}

## For a harness, the hook or the packager. Run from cicd.bash, a folder of its
## own inside the run's, <name>_<NNN>, which is all it may remove under. Run
## alone, a run folder like cicd.bash's, and the stale ones swept. Either way
## TMPDIR, TEMP and TMP point at it, and safeRmRunDir names it, so an exit trap
## set before the call can remove it.
fRunDir_Sub(){  ## project, name
	local parent="${ZUID_RUN_DIR:-}" dir=""
	if [[ "${parent}" == /?* && -d "${parent}" && ! -L "${parent}" && "$(realpath -- "${parent}" 2>/dev/null)" == "${parent}" ]]; then
		dir="$(_fRunDir_Next "${parent}" "${2:?}")" || return 1
		safeRmOwn="${parent}"; safeRmRunDir="${dir}"
		export TMPDIR="${dir}" TEMP="${dir}" TMP="${dir}"
		return 0
	fi
	fRunDir_Make "${1:?}" "$(date +%Y%m%d-%H%M%S)" || return 1
	fRunDir_Sweep
}

##	History:
##		- 20261025 JC: fMkTempDir, since macOS's bare mktemp -d ignores TMPDIR.
##		- 20261025 JC: fRunDir_Sweep counts what it removed.
##		- 20261025 JC: The run folder, for cicd.bash and the harnesses alike.
##		- 20261025 JC: Created, from the shared safe removal guard.
