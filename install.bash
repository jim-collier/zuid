#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Downloads a zuid release, checks it against the published checksums, and
##		installs it. Idempotent: it says what it is about to do and asks before
##		touching anything, and reinstalling the same version is a no-op.
##	Syntax:
##		install.bash [--release stable|dev] [--target user|system] [--yes] [--uninstall]
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

REPO="jim-collier/zuid"
PROG="zuid"
installerVersion="1.3.1"

release="stable"
target="user"
assumeYes=0
doUninstall=0

fEcho(){ printf '[ %s ]\n' "$*"; }
fLine(){ printf '%s\n' "$*"; }
fDie(){ printf '\n%s: %s\n\n' "${PROG}-install" "$*" >&2; exit 1; }

## A heredoc, not sed over this file: under bash <(curl ...) the file is a pipe
## that's already been read.
fHelp(){
	cat <<EOF

${PROG} installer ${installerVersion}

Downloads the newest ${PROG} release from GitHub, checks it against the
published checksums, and installs it. It says what it's about to do and asks
first. Running it again on the same version changes nothing.

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.bash) [options]

Options:
  --release stable|dev   stable (default): newest full release
                         dev: newest release, prereleases included
  --target user|system   user (default): under \$HOME, no root needed
                         system: /opt or /usr/local, uses sudo
  --yes, -y              don't ask before installing
  --uninstall            remove what this installer put in place
  --version              print the installer's version
  --help, -h             this text

The OS, CPU architecture, and release file are detected.

EOF
}

## A flag with its value left off used to reach 'shift 2' with one argument
## left. That fails, and under set -e it ended the script with nothing printed.
fNeedValue(){ (($# >= 2)) || fDie "$1 needs a value (try --help)" ;}

while (($#)); do case "$1" in
	--release)   fNeedValue "$@"; release="$2"; shift 2 ;;
	--target)    fNeedValue "$@"; target="$2";  shift 2 ;;
	--release=*) release="${1#*=}"; shift ;;
	--target=*)  target="${1#*=}";  shift ;;
	-y|--yes)    assumeYes=1;      shift ;;
	--uninstall) doUninstall=1;    shift ;;
	--version)   printf '%s\n' "${installerVersion}"; exit 0 ;;
	-h|--help)   fHelp; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

printf '\n'

case "${release}" in stable|dev) ;; *) fDie "--release wants stable or dev, got '${release}'" ;; esac


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Where things go. A user install needs no privileges, so it's the default
## even for root. System only when asked for.

## Linux, macOS and FreeBSD. FreeBSD keeps third-party software under /usr/local.
case "$(uname -s)" in
	Linux)   osLabel="linux";   systemDir="/opt/${PROG}";       systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/.local/share/${PROG}" ;;
	Darwin)  osLabel="darwin";  systemDir="/opt/${PROG}";       systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/Library/Application Support/${PROG}" ;;
	FreeBSD) osLabel="freebsd"; systemDir="/usr/local/${PROG}"; systemLink="/usr/local/bin/${PROG}"; userDir="${HOME}/.local/share/${PROG}" ;;
	*) fDie "no ${PROG} build exists for $(uname -s). On Windows use install.ps1; elsewhere, build from source - see the README." ;;
esac
userLink="${HOME}/.local/bin/${PROG}"

case "${target}" in
	user)   installDir="${userDir}";   linkPath="${userLink}";   needsRoot=0 ;;
	system) installDir="${systemDir}"; linkPath="${systemLink}"; needsRoot=1 ;;
	*) fDie "--target wants user or system, got '${target}'" ;;
esac

## Not an array: an empty one is "unbound" under set -u before bash 4.4, which
## is what a Mac's /bin/bash is.
useSudo=0
if ((needsRoot)) && [[ "$(id -u)" != "0" ]]; then
	command -v sudo >/dev/null 2>&1 || fDie "a system install needs root, and sudo was not found"
	useSudo=1
fi
fRun(){ if ((useSudo)); then sudo "$@"; else "$@"; fi ;}

## The one way this removes anything recursively. Only strictly under <parent>,
## which has to be physical. '..', '//', a newline and a link are refused, and
## it stays on one filesystem. Its own copy of the repo's guard, since this
## runs alone from a download.
fSafeRm_Under(){  ## parent, path
	local parent="${1%/}" path="${2%/}" oneFs="-x"
	case "${parent}${path}" in
		*..*|*//*|*$'\n'*) printf '  Refused to remove %s: a bad path\n' "${path}" >&2; return 1 ;;
	esac
	if [[ "${parent}" != /?* || "${path}" != "${parent}"/?* ]]; then printf '  Refused to remove %s: not under %s\n' "${path}" "${parent}" >&2; return 1; fi
	if [[ -L "${path}" ]]; then printf '  Refused to remove %s: a link\n' "${path}" >&2; return 1; fi
	[[ -e "${path}" ]] || return 0
	if [[ "$(cd -P -- "${parent}" 2>/dev/null && pwd -P)" != "${parent}" ]]; then printf '  Refused to remove %s: %s goes through a link\n' "${path}" "${parent}" >&2; return 1; fi
	## GNU rm says --one-file-system, BSD's -x.
	if rm --version >/dev/null 2>&1; then oneFs="--one-file-system"; fi
	fRun rm -rf "${oneFs}" -- "${path}"
}

## Empties the install dir one entry at a time, so it's the one parent the
## guard names, and a wrong installDir can't take its parent with it. It has to
## be named ${PROG}, and not be a link. A link inside is only unlinked.
fEmptyInstallDir(){
	local dir="" entry=""
	[[ -e "${installDir}" || -L "${installDir}" ]] || return 0
	if [[ -L "${installDir}" ]]; then printf '  Refused to empty %s: a link\n' "${installDir}" >&2; return 1; fi
	dir="$(cd -P -- "${installDir}" && pwd -P)" || return 1
	if [[ "${dir##*/}" != "${PROG}" ]]; then printf '  Refused to empty %s: not a %s install dir\n' "${installDir}" "${PROG}" >&2; return 1; fi
	for entry in "${dir}"/* "${dir}"/.[!.]* "${dir}"/..?*; do
		if [[ -L "${entry}" ]]; then fRun rm -f -- "${entry}" || return 1
		elif [[ -e "${entry}" ]]; then fSafeRm_Under "${dir}" "${entry}" || return 1
		fi
	done
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Uninstall is the same plan in reverse, so it lives here rather than in a
## second script.

## Only this installer's own link. A zuid at that path the installer did not put
## there is somebody's own build - the README tells a source build that a full
## cicd run copies one to ~/.local/bin - and uninstall is the plan in reverse,
## which only covers what the install made.
fLinkIsOurs(){
	[[ -L "${linkPath}" ]] || return 1
	local target="" owned=""
	target="$(readlink -f "${linkPath}" 2>/dev/null || true)"
	owned="$(readlink -f "${installDir}" 2>/dev/null || true)"
	[[ -n "${target}" && -n "${owned}" && "${target}" == "${owned}"/* ]]
}

if ((doUninstall)); then
	## Worked out before anything is removed: once installDir is gone the link
	## dangles and there is no target left to recognize.
	ownsLink=0
	if fLinkIsOurs; then ownsLink=1; fi

	fEcho "Uninstall"
	fLine "  Remove: ${installDir}"
	if ((ownsLink)); then
		fLine "  Remove: ${linkPath}"
	elif [[ -e "${linkPath}" || -L "${linkPath}" ]]; then
		fLine "  Keep ..: ${linkPath} (not this installer's link, so it stays)"
	fi
	fLine ""
	if ((! assumeYes)); then
		answer=""
	read -r -p "  Proceed? [y/N] " answer || true
		[[ "${answer}" =~ ^[Yy] ]] || { fLine ""; fEcho "Nothing was changed."; printf '\n'; exit 0; }
		fLine ""
	fi
	fEmptyInstallDir || fDie "couldn't remove ${installDir}"
	if [[ -d "${installDir}" ]]; then fRun rmdir "${installDir}" || fDie "couldn't remove ${installDir}"; fi
	if ((ownsLink)); then fRun rm -f "${linkPath}"; fi
	fEcho "Removed."
	printf '\n'
	exit 0
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Work out what to fetch.

for tool in curl tar; do
	command -v "${tool}" >/dev/null 2>&1 || fDie "not found in PATH: ${tool}"
done
## A stock Mac or FreeBSD may have only one of these.
shaTool=""
for tool in sha256sum shasum openssl; do
	if command -v "${tool}" >/dev/null 2>&1; then shaTool="${tool}"; break; fi
done
[[ -n "${shaTool}" ]] || fDie "nothing to check a sha256 with: install sha256sum, shasum, or openssl"
fSha256(){ case "${shaTool}" in
	sha256sum) sha256sum "$1" | awk '{print $1}' ;;
	shasum)    shasum -a 256 "$1" | awk '{print $1}' ;;
	openssl)   openssl dgst -sha256 "$1" | awk '{print $NF}' ;;
esac ;}

case "$(uname -m)" in
	x86_64|amd64)  arch="x86_64" ;;
	aarch64|arm64) arch="arm64"  ;;
	*) fDie "no ${PROG} build exists for $(uname -m). Build from source - see the README." ;;
esac

## The macOS release is one universal build, for either architecture.
if [[ "${osLabel}" == "darwin" ]]; then arch="universal"; fi
if [[ "${osLabel}" == "freebsd" && "${arch}" != "x86_64" ]]; then
	fDie "no ${PROG} build exists for FreeBSD ${arch}, only x86_64. Build from source - see the README."
fi

## GitHub's 'latest' endpoint only ever answers with a full release, so it 404s
## on a repository whose releases are all prereleases. Listing them covers both.
## Without jq: the body goes onto one line, then each "tag_name" starts a new
## one. A release's draft and prerelease flags sit between its tag and the next.
fReleaseRows(){  ## tag draft|- pre|full, one per line
	tr -d '\r\n' | sed 's/"tag_name"/\
"tag_name"/g' | awk '/^"tag_name"/ {
		tag = $0
		sub(/^"tag_name"[ \t]*:[ \t]*"/, "", tag); sub(/".*/, "", tag)
		draft = ($0 ~ /"draft"[ \t]*:[ \t]*true/) ? "draft" : "-"
		pre = ($0 ~ /"prerelease"[ \t]*:[ \t]*true/) ? "pre" : "full"
		if (tag != "") print tag, draft, pre
	}'
}

## Semver order, since GitHub lists by date: a 1.0.1 fix published after
## 1.1.0-beta.1 would otherwise win for dev. sort -V puts 1.0.0-alpha above
## 1.0.0, which is backwards.
fFieldCmp(){  ## a b -> -1|0|1. Numbers sort below words; beta10 is above beta3.
	local a="$1" b="$2" num='^[0-9]+$' word='^([^0-9]*)([0-9]+)$'
	if [[ ${a} =~ ${num} ]] && [[ ${b} =~ ${num} ]]; then
		if ((10#${a} > 10#${b})); then echo 1; elif ((10#${a} < 10#${b})); then echo -1; else echo 0; fi
		return 0
	fi
	if [[ ${a} =~ ${num} ]]; then echo -1; return 0; fi
	if [[ ${b} =~ ${num} ]]; then echo 1; return 0; fi
	local aStem="" aNum="" bStem="" bNum=""
	if [[ ${a} =~ ${word} ]]; then aStem="${BASH_REMATCH[1]}"; aNum="${BASH_REMATCH[2]}"; fi
	if [[ ${b} =~ ${word} ]]; then bStem="${BASH_REMATCH[1]}"; bNum="${BASH_REMATCH[2]}"; fi
	if [[ -n "${aNum}" && -n "${bNum}" && "${aStem}" == "${bStem}" ]]; then
		fFieldCmp "${aNum}" "${bNum}"
		return 0
	fi
	if [[ ${a} < ${b} ]]; then echo -1; elif [[ ${a} > ${b} ]]; then echo 1; else echo 0; fi
}
fListCmp(){  ## a b missing. missing is what a shorter list counts as: -1 for a prerelease, 0 for the core.
	local a="$1" b="$2" missing="$3" c=""
	while [[ -n "${a}" || -n "${b}" ]]; do
		if [[ -z "${a}" ]]; then if [[ "${missing}" == "0" ]]; then a="0"; else echo -1; return 0; fi; fi
		if [[ -z "${b}" ]]; then if [[ "${missing}" == "0" ]]; then b="0"; else echo 1; return 0; fi; fi
		c="$(fFieldCmp "${a%%.*}" "${b%%.*}")"
		[[ "${c}" == "0" ]] || { echo "${c}"; return 0; }
		case "${a}" in *.*) a="${a#*.}" ;; *) a="" ;; esac
		case "${b}" in *.*) b="${b#*.}" ;; *) b="" ;; esac
	done
	echo 0
}
fNewer(){  ## a b. True when tag a is the higher version.
	local a="${1#v}" b="${2#v}" aPre="" bPre="" c=""
	a="${a%%+*}"; b="${b%%+*}"
	case "${a}" in *-*) aPre="${a#*-}"; a="${a%%-*}" ;; esac
	case "${b}" in *-*) bPre="${b#*-}"; b="${b%%-*}" ;; esac
	c="$(fListCmp "${a}" "${b}" 0)"
	[[ "${c}" == "0" ]] || { [[ "${c}" == "1" ]]; return; }
	## Same core: a release is above any of its prereleases.
	[[ -n "${aPre}" ]] || { [[ -n "${bPre}" ]]; return; }
	[[ -n "${bPre}" ]] || return 1
	[[ "$(fListCmp "${aPre}" "${bPre}" -1)" == "1" ]]
}
fPickTag(){  ## stable|dev, rows on stdin. Prints the highest, or nothing.
	local want="$1" tag draft pre best=""
	while read -r tag draft pre; do
		[[ "${draft}" == "-" ]] || continue
		[[ "${want}" == "dev" || "${pre}" == "full" ]] || continue
		if [[ -z "${best}" ]] || fNewer "${tag}" "${best}"; then best="${tag}"; fi
	done
	if [[ -n "${best}" ]]; then printf '%s\n' "${best}"; fi
}

fEcho "Looking up the ${release} release"
## TMPDIR ends in a slash on a Mac.
tmpRoot="${TMPDIR:-/tmp}"; tmpRoot="${tmpRoot%/}"
tmpRoot="$(cd -P -- "${tmpRoot}" && pwd -P)" || fDie "no temp dir at ${TMPDIR:-/tmp}"
work="$(mktemp -d "${tmpRoot}/${PROG}-install.XXXXXX")" || fDie "couldn't make a temp dir in ${tmpRoot}"
trap 'useSudo=0 fSafeRm_Under "${tmpRoot}" "${work}"' EXIT
listing="${work}/releases.json"
## A rate limit or a dead network used to read as "no release found".
httpCode="$(curl -sSL --proto '=https' --tlsv1.2 -o "${listing}" -w '%{http_code}' "https://api.github.com/repos/${REPO}/releases?per_page=100" 2>/dev/null || true)"
case "${httpCode}" in
	2??) : ;;
	403|429) fDie "GitHub refused the release lookup (HTTP ${httpCode}), most likely a rate limit. Wait an hour and try again." ;;
	000|"")  fDie "couldn't reach api.github.com. Check the network or proxy, then try again." ;;
	*)       fDie "the release lookup failed with HTTP ${httpCode}." ;;
esac
rows="$(fReleaseRows < "${listing}")"
[[ -n "${rows}" ]] || fDie "no published release found for ${REPO}. Build from source instead - see its README."

kind="stable"
if [[ "${release}" == "dev" ]]; then
	tag="$(printf '%s\n' "${rows}" | fPickTag dev)"
	case "$(printf '%s\n' "${rows}" | awk -v t="${tag}" '$1 == t {print $3; exit}')" in pre) kind="prerelease" ;; esac
else
	tag="$(printf '%s\n' "${rows}" | fPickTag stable)"
	if [[ -z "${tag}" ]]; then
		## Nothing final yet, so the newest prerelease is all there is.
		kind="prerelease"
		tag="$(printf '%s\n' "${rows}" | fPickTag dev)"
		fLine "  No stable release yet, so this is the newest prerelease."
	fi
fi
[[ -n "${tag}" ]] || fDie "no published release found for ${REPO}. Build from source instead - see its README."

asset="${PROG}-${tag#v}-${osLabel}-${arch}.tgz"
## The alpha went out before release names had the version.
if [[ "${tag}" == "v1.0.0-alpha.1" ]]; then asset="${PROG}-${osLabel}-${arch}.tgz"; fi
base="https://github.com/${REPO}/releases/download/${tag}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## State the plan, then ask.

## The copy in installDir, not whatever is on the link path: a build copied to
## ~/.local/bin by hand would otherwise read as "already installed".
installed=""
if [[ -x "${installDir}/bin/${PROG}" ]]; then
	installed="$("${installDir}/bin/${PROG}" --version 2>/dev/null | head -n1 || true)"
fi

## --version starts "zuid v1.0.0 build dee3e", and the tag has a leading v.
## Up to beta.1 it was "1.0.0-alpha.1 (build dcrb0)", so take either.
## Nothing used to compare the two, so a second run downloaded the same release,
## deleted the install directory and copied it back - while the help, the README
## and the backlog all said re-running changes nothing.
installedVer="${installed#"${PROG}" v}"
installedVer="${installedVer%% *}"
if [[ -n "${installedVer}" && "${installedVer}" == "${tag#v}" ]]; then
	fLine ""
	fEcho "Already installed"
	fLine "  Version ....: ${tag} (${kind})"
	fLine "  Location ...: ${installDir}"
	fLine ""
	fLine "  Nothing to do. To reinstall, run --uninstall first."
	printf '\n'
	exit 0
fi

fLine ""
fEcho "Plan"
fLine "  Version ....: ${tag} (${kind})"
fLine "  Platform ...: ${osLabel}/${arch}"
fLine "  Download ...: ${base}/${asset}"
fLine "  Verify .....: sha256 against checksums.txt"
fLine "  Install to .: ${installDir}"
fLine "  Link .......: ${linkPath}"
## Naming it, because the thing being overwritten may not be ours - a build
## copied there by hand or by a cicd run, rather than a previous install.
if [[ -e "${linkPath}" || -L "${linkPath}" ]] && ! fLinkIsOurs; then
	fLine "  Overwriting : ${linkPath} is not this installer's link"
fi
[[ -n "${installed}" ]] && fLine "  Replacing ..: ${installed}"
((needsRoot)) && fLine "  Privileges .: system install, so this needs root"
fLine ""

if ((! assumeYes)); then
	answer=""
	read -r -p "  Proceed? [y/N] " answer || true
	[[ "${answer}" =~ ^[Yy] ]] || { fLine ""; fEcho "Nothing was changed."; printf '\n'; exit 0; }
	fLine ""
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fetch, verify, install.

fEcho "Downloading"
curl -fsSL --proto '=https' --tlsv1.2 -o "${work}/${asset}" "${base}/${asset}" \
	|| fDie "could not download ${base}/${asset}"
curl -fsSL --proto '=https' --tlsv1.2 -o "${work}/checksums.txt" "${base}/checksums.txt" \
	|| fDie "could not download the checksums for ${tag}"

fEcho "Verifying"
want="$(awk -v want="${asset}" '$2 == want || $2 == "*"want {print $1}' "${work}/checksums.txt" | head -n1)"
[[ -n "${want}" ]] || fDie "${asset} is not listed in checksums.txt"
got="$(fSha256 "${work}/${asset}")"
[[ "${got}" == "${want}" ]] || fDie "checksum mismatch: expected ${want}, got ${got}"

fEcho "Installing"
tar --no-same-owner --no-same-permissions -xzf "${work}/${asset}" -C "${work}" \
	|| fDie "couldn't unpack ${asset}"
## Not depth 0: the work dir's own name starts the same way.
payload="$(find "${work}" -mindepth 1 -maxdepth 1 -type d -name "${PROG}-*" | head -n1)"
[[ -n "${payload}" ]] || fDie "the archive did not contain the expected directory"

fCantWrite(){ fDie "couldn't write $1. Check its permissions, or try --target $2." ;}
otherTarget="system"; [[ "${target}" == "system" ]] && otherTarget="user"
fEmptyInstallDir                                      || fCantWrite "${installDir}" "${otherTarget}"
fRun mkdir -p "${installDir}" "$(dirname "${linkPath}")" || fCantWrite "${installDir}" "${otherTarget}"
fRun cp -R "${payload}/." "${installDir}/"             || fCantWrite "${installDir}" "${otherTarget}"
fRun ln -sfn "${installDir}/bin/${PROG}" "${linkPath}" || fCantWrite "${linkPath}" "${otherTarget}"

fLine ""
fEcho "Installed ${tag} to ${installDir}"
case ":${PATH}:" in
	*":$(dirname "${linkPath}"):"*) : ;;
	*) fLine "  Note: $(dirname "${linkPath}") is not on your PATH." ;;
esac
fLine "  Try: ${PROG} --help"
printf '\n'


##	History:
##		- 20261025 JC: Reads the installed version from either --version line.
##		- 20261025 JC: Recursive removals go through its own guard. The install dir is emptied, not removed by path.
##		- 20261014 JC: Release names have the version.
##		- 20261014 JC: User install by default, root included.
##		- 20261014 JC: --version, --opt=value, semver release pick, sha256 fallbacks. Works under bash 3.2. --arch dropped.
##		- 20261004 JC: FreeBSD x86_64.
##		- 20261003 JC: No BSD build, so a system other than Linux or macOS is refused by name.
##		- 20261003 JC: macOS fetches the universal build.
##		- 20260805 JC: Pick the release from the full list; fall back to a prerelease.
##		- 20260804 JC: Created.
