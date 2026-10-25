#!/bin/bash

# shellcheck disable=2034  ## safeRmOwn is set by whoever sources this.

##	Purpose:
##		The one way the pipeline and its harnesses remove a folder. Source it and call:
##			fSafeRm <path>                  Under a folder named tmp, or under ${safeRmOwn}.
##			fSafeRm_Under <parent> <path>   Strictly under <parent>, for a folder outside any temp root.
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

##	History:
##		- 20261025 JC: Created, from the shared safe removal guard.
