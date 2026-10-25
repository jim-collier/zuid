#!/usr/bin/env bash

##	Purpose:
##		Prunes a Go module cache down to what the given go.sum files name.
##		Unpacked module folders and their download files both go, for every
##		module version none of them lists. The checksum db and the version
##		lists stay. cicd.bash runs it on the cache volume, never on a host's
##		own cache, which other projects share.
##		Prints "pruned <KB>" when it removed anything.
##	Syntax:
##		gomod-prune.bash <module cache> <go.sum>...
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

cache="${1:?module cache}"; shift
(($#)) || { echo "gomod-prune: no go.sum given" >&2; exit 2; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=cicd/utility/include/safe-rm.bash
source "${here}/include/safe-rm.bash"

[[ -d "${cache}" && ! -L "${cache}" ]] || exit 0
cache="$(realpath -- "${cache}")"

## The cache's own spelling: each capital is ! and the lower case letter.
fEscape(){  ## module path; sets escaped
	local s="$1" c=""
	local -i i=0
	escaped=""
	for ((i = 0; i < ${#s}; i++)); do
		c="${s:i:1}"
		if [[ "${c}" == [A-Z] ]]; then escaped+="!${c,,}"; else escaped+="${c}"; fi
	done
}

declare -A named=()
declare escaped="" mod="" ver="" sum=""
for sum in "$@"; do
	[[ -f "${sum}" ]] || { echo "gomod-prune: no ${sum}" >&2; exit 2; }
	while read -r mod ver _; do
		[[ -n "${mod}" && -n "${ver}" ]] || continue
		fEscape "${mod}"
		named["${escaped}@${ver%/go.mod}"]=1
	done < "${sum}"
done
## An empty list would take the whole cache.
((${#named[@]})) || { echo "gomod-prune: nothing named in $*" >&2; exit 2; }

declare -i before=0 after=0
before="$(du -sk "${cache}" | cut -f1)"

declare dir="" file="" rel="" base=""
while IFS= read -r -d '' dir; do
	rel="${dir#"${cache}"/}"
	[[ -n "${named["${rel}"]:-}" ]] && continue
	## Go leaves them read-only.
	chmod -R u+w "${dir}"
	fSafeRm_Under "${cache}" "${dir}"
done < <(find "${cache}" -mindepth 1 -path "${cache}/cache" -prune -o -type d -name '*@*' -prune -print0)
## And the module path folders that held only those.
while IFS= read -r -d '' dir; do
	find "${dir}" -type d -empty ! -name '*@*' -delete
done < <(find "${cache}" -mindepth 1 -maxdepth 1 -type d ! -name cache -print0)

if [[ -d "${cache}/cache/download" ]]; then
	while IFS= read -r -d '' file; do
		rel="${file#"${cache}/cache/download/"}"
		mod="${rel%%/@v/*}"; base="${rel##*/}"
		[[ "${base}" == list || "${base}" == list.lock ]] && continue
		ver="${base%.*}"
		[[ -n "${named["${mod}@${ver}"]:-}" ]] && continue
		rm -f -- "${file}"
	done < <(find "${cache}/cache/download" -path "${cache}/cache/download/sumdb" -prune -o -type f -path '*/@v/*' -print0)
	## Then what that left empty, a module's list file and all.
	while IFS= read -r -d '' dir; do
		[[ -z "$(find "${dir}" -type f ! -name 'list' ! -name 'list.lock' -print -quit)" ]] || continue
		fSafeRm_Under "${cache}/cache/download" "${dir}"
	done < <(find "${cache}/cache/download" -mindepth 1 -path "${cache}/cache/download/sumdb" -prune -o -type d -name '@v' -print0)
	find "${cache}/cache/download" -mindepth 1 -type d -empty -delete
fi

after="$(du -sk "${cache}" | cut -f1)"
if ((before > after)); then printf 'pruned %s\n' "$((before - after))"; fi

##	History:
##		- 20261025 JC: Created.
