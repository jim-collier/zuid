#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Downloads a zuid release, checks it against the published checksums, and
##		installs it. Idempotent: it says what it is about to do and asks before
##		touching anything, and reinstalling the same version is a no-op.
##	Syntax:
##		install.bash [--release stable|dev] [--target user|system] [--arch x86_64|arm64] [--yes] [--uninstall]
##	History: At bottom.

##	Copyright © 2026 Jim Collier
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

REPO="jim-collier/zuid"
PROG="zuid"

release="stable"
target=""
arch=""
assumeYes=0
doUninstall=0

fEcho(){ printf '[ %s ]\n' "$*"; }
fLine(){ printf '%s\n' "$*"; }
fDie(){ printf '\n%s: %s\n\n' "${PROG}-install" "$*" >&2; exit 1; }
fUsage(){ sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; }

while (($#)); do case "$1" in
	--release)   release="${2:-}"; shift 2 ;;
	--target)    target="${2:-}";  shift 2 ;;
	--arch)      arch="${2:-}";    shift 2 ;;
	-y|--yes)    assumeYes=1;      shift ;;
	--uninstall) doUninstall=1;    shift ;;
	-h|--help)   fUsage; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

printf '\n'

case "${release}" in stable|dev) ;; *) fDie "--release wants stable or dev, got '${release}'" ;; esac


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Where things go. A user install needs no privileges and is the default when
## the system directories are not writable.

case "$(uname -s)" in
	Linux)   systemDir="/opt/${PROG}";        systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/.local/share/${PROG}" ;;
	FreeBSD|OpenBSD|NetBSD)
	         systemDir="/usr/local/${PROG}";  systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/.local/share/${PROG}" ;;
	Darwin)  systemDir="/opt/${PROG}";        systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/Library/Application Support/${PROG}" ;;
	*) fDie "unsupported system: $(uname -s). On Windows use install.ps1." ;;
esac
userLink="${HOME}/.local/bin/${PROG}"

if [[ -z "${target}" ]]; then
	if [[ -w "$(dirname "${systemLink}")" ]] 2>/dev/null; then target="system"; else target="user"; fi
fi
case "${target}" in
	user)   installDir="${userDir}";   linkPath="${userLink}";   needsRoot=0 ;;
	system) installDir="${systemDir}"; linkPath="${systemLink}"; needsRoot=1 ;;
	*) fDie "--target wants user or system, got '${target}'" ;;
esac

runAs=()
if ((needsRoot)) && [[ "$(id -u)" != "0" ]]; then
	command -v sudo >/dev/null 2>&1 || fDie "a system install needs root, and sudo was not found"
	runAs=(sudo)
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Uninstall is the same plan in reverse, so it lives here rather than in a
## second script.

if ((doUninstall)); then
	fEcho "Uninstall"
	fLine "  Remove: ${installDir}"
	fLine "  Remove: ${linkPath}"
	fLine ""
	if ((! assumeYes)); then
		read -r -p "  Proceed? [y/N] " answer
		[[ "${answer}" =~ ^[Yy] ]] || { fLine ""; fEcho "Nothing was changed."; printf '\n'; exit 0; }
		fLine ""
	fi
	"${runAs[@]}" rm -rf "${installDir}"
	"${runAs[@]}" rm -f "${linkPath}"
	fEcho "Removed."
	printf '\n'
	exit 0
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Work out what to fetch.

for tool in curl tar sha256sum; do
	command -v "${tool}" >/dev/null 2>&1 || fDie "not found in PATH: ${tool}"
done

if [[ -z "${arch}" ]]; then
	case "$(uname -m)" in
		x86_64|amd64)  arch="x86_64" ;;
		aarch64|arm64) arch="arm64"  ;;
		*) fDie "unsupported architecture: $(uname -m). Pass --arch to override." ;;
	esac
fi

case "$(uname -s)" in
	Linux)  osLabel="linux"   ;;
	Darwin) osLabel="darwin"  ;;
	*)      osLabel="freebsd" ;;
esac

## GitHub's 'latest' endpoint only ever answers with a full release, so it 404s
## on a repository whose releases are all prereleases. Listing them instead
## covers both, and leaves the choice here rather than on the far end.
## The API prints one field per line, and tag_name/draft/prerelease appear in
## that order per release and under no other key, so a line scan reads it
## without needing jq installed.
fReleaseTags(){  ## tag<TAB>stable|prerelease, newest first
	local line tag="" draft="" isPre="" kind
	while IFS= read -r line; do case "${line}" in
		*'"tag_name":'*)
			tag="${line#*: \"}"; tag="${tag%%\"*}"; draft=""; isPre="" ;;
		*'"draft":'*)
			draft="${line##*: }"; draft="${draft%,}" ;;
		*'"prerelease":'*)
			isPre="${line##*: }"; isPre="${isPre%,}"
			kind="stable"; [[ "${isPre}" == "true" ]] && kind="prerelease"
			[[ -n "${tag}" && "${draft}" == "false" ]] && printf '%s\t%s\n' "${tag}" "${kind}"
			tag="" ;;
	esac; done
}

fEcho "Looking up the ${release} release"
listing="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases" 2>/dev/null || true)"
tags="$(printf '%s\n' "${listing}" | fReleaseTags)"
[[ -n "${tags}" ]] || fDie "no published release found for ${REPO}. If the repository has none yet, build from source instead - see its README."

if [[ "${release}" == "dev" ]]; then
	## Newest of anything, prerelease included.
	kind="$(printf '%s\n' "${tags}" | head -n1 | cut -f2)"
	tag="$(printf '%s\n' "${tags}" | head -n1 | cut -f1)"
else
	kind="stable"
	tag="$(printf '%s\n' "${tags}" | awk -F'\t' '$2 == "stable" {print $1; exit}')"
	if [[ -z "${tag}" ]]; then
		## Nothing final published yet, so the newest prerelease is the only
		## thing there is to install. Say so rather than failing.
		kind="prerelease"
		tag="$(printf '%s\n' "${tags}" | head -n1 | cut -f1)"
		fLine "  No stable release yet, so this is the newest prerelease."
	fi
fi

asset="${PROG}-${osLabel}-${arch}.tgz"
base="https://github.com/${REPO}/releases/download/${tag}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## State the plan, then ask.

installed=""
[[ -x "${linkPath}" ]] && installed="$("${linkPath}" --version 2>/dev/null | head -n1 || true)"

fLine ""
fEcho "Plan"
fLine "  Version ....: ${tag} (${kind})"
fLine "  Platform ...: ${osLabel}/${arch}"
fLine "  Download ...: ${base}/${asset}"
fLine "  Verify .....: sha256 against checksums.txt"
fLine "  Install to .: ${installDir}"
fLine "  Link .......: ${linkPath}"
[[ -n "${installed}" ]] && fLine "  Replacing ..: ${installed}"
((needsRoot)) && fLine "  Privileges .: system install, so this needs root"
fLine ""

if ((! assumeYes)); then
	read -r -p "  Proceed? [y/N] " answer
	[[ "${answer}" =~ ^[Yy] ]] || { fLine ""; fEcho "Nothing was changed."; printf '\n'; exit 0; }
	fLine ""
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fetch, verify, install.

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fEcho "Downloading"
curl -fsSL --proto '=https' --tlsv1.2 -o "${work}/${asset}" "${base}/${asset}" \
	|| fDie "could not download ${base}/${asset}"
curl -fsSL --proto '=https' --tlsv1.2 -o "${work}/checksums.txt" "${base}/checksums.txt" \
	|| fDie "could not download the checksums for ${tag}"

fEcho "Verifying"
want="$(awk -v want="${asset}" '$2 == want || $2 == "*"want {print $1}' "${work}/checksums.txt" | head -n1)"
[[ -n "${want}" ]] || fDie "${asset} is not listed in checksums.txt"
got="$(sha256sum "${work}/${asset}" | awk '{print $1}')"
[[ "${got}" == "${want}" ]] || fDie "checksum mismatch: expected ${want}, got ${got}"

fEcho "Installing"
tar --no-same-owner --no-same-permissions -xzf "${work}/${asset}" -C "${work}"
payload="$(find "${work}" -maxdepth 1 -type d -name "${PROG}-*" | head -n1)"
[[ -n "${payload}" ]] || fDie "the archive did not contain the expected directory"

"${runAs[@]}" rm -rf "${installDir}"
"${runAs[@]}" mkdir -p "${installDir}" "$(dirname "${linkPath}")"
"${runAs[@]}" cp -R "${payload}/." "${installDir}/"
"${runAs[@]}" ln -sfn "${installDir}/bin/${PROG}" "${linkPath}"

fLine ""
fEcho "Installed ${tag} to ${installDir}"
case ":${PATH}:" in
	*":$(dirname "${linkPath}"):"*) : ;;
	*) fLine "  Note: $(dirname "${linkPath}") is not on your PATH." ;;
esac
fLine "  Try: ${PROG} --help"
printf '\n'


##	History:
##		- 20260805 JC: Pick the release from the full list; fall back to a prerelease.
##		- 20260804 JC: Created.
