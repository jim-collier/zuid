#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Covers the install and release path, which nothing else can reach without
##		a real download. Runs install.bash and install.ps1 against a local release
##		listing: which release is chosen, what a re-run does, and what happens to
##		a file already sitting at the link path. Also package.bash's --out, since
##		that is the other script handed a caller's path.
##
##		The installers are copied and their two base URLs rewritten to point here.
##		A second pair of copies has /opt and /usr/local moved under the scratch
##		tree, which is how --target system gets run without root. Every rewrite is
##		checked, so a script that moves its URLs or its paths fails this rather
##		than quietly testing nothing.
##	Syntax:
##		installer-test.bash [--keep] [--only bash|ps1|bash32]
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

PROG="zuid"
REPO="jim-collier/zuid"

doKeep=0
only=""

fEcho(){    printf '[ %s ]\n' "$*" ;}
fLine(){    printf '%s\n' "$*" ;}
fDie(){     printf '\n%s: %s\n\n' "installer-test" "$*" >&2; exit 1 ;}

## Every check starts with fId, naming its test ID and what it checks, then ends
## in one fPass or fFail. A case run once per installer has an ID for each,
## picked by the label: fId "${label}" bash=<id> ps1=<id> "what it checks".
## New IDs come from test-ids.py. While skipWhy is set every check reports as
## skipped, and the runners do nothing.
passed=0
failed=0
skipped=0
curId=""
curName=""
skipWhy=""

fId(){  ## [key key=id...] | id, name
	curId=""
	curName="${*: -1}"
	if (($# == 2)); then curId="$1"; return 0; fi
	local -r key="$1"
	local pair=""
	for pair in "${@:2:$#-2}"; do
		if [[ "${pair%%=*}" == "${key}" ]]; then curId="${pair#*=}"; fi
	done
	return 0
}
fSkipped(){
	[[ -n "${skipWhy}" ]] || return 1
	skipped=$((skipped + 1)); printf '  SKIP %s %s (%s)\n' "${curId:-?????}" "${curName}" "${skipWhy}"
	curId=""
}
fPass(){
	if fSkipped; then return 0; fi
	if [[ -z "${curId}" ]]; then fFail "no test ID"; return 0; fi
	passed=$((passed + 1)); printf '  PASS %s %s\n' "${curId}" "${curName}"
	curId=""
}
fFail(){  ## detail
	if fSkipped; then return 0; fi
	failed=$((failed + 1)); printf '  FAIL %s %s: %s\n' "${curId:-?????}" "${curName}" "$*"
	curId=""
}

while (($#)); do case "$1" in
	--keep)    doKeep=1; shift ;;
	--only)    only="${2:-}"; shift 2 ;;
	-h|--help) sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

case "${only}" in ""|bash|ps1|bash32) ;; *) fDie "--only wants bash, ps1 or bash32, got '${only}'" ;; esac

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "${repoRoot}/install.bash" ]] || fDie "could not find install.bash from ${repoRoot}"

for tool in python3 curl tar sha256sum; do
	command -v "${tool}" >/dev/null 2>&1 || fDie "not found in PATH: ${tool}"
done

hasPwsh=0
command -v pwsh >/dev/null 2>&1 && hasPwsh=1

## What the installers fetch on this machine, past the name and version, and
## where a user install keeps it.
case "$(uname -m)" in
	aarch64|arm64) hostAsset="arm64.tgz" ;;
	*)             hostAsset="x86_64.tgz" ;;
esac
case "$(uname -s)" in
	Darwin) hostAsset="darwin-universal.tgz"; userShare="Library/Application Support/${PROG}"; userCache="Library/Caches/${PROG}" ;;
	*)      hostAsset="linux-${hostAsset}";   userShare=".local/share/${PROG}";                userCache=".cache/${PROG}" ;;
esac
## A user uninstall removes the command's cache, and outside Darwin that follows
## XDG_CACHE_HOME. Left set, it's the real one, whatever HOME a case gives.
unset XDG_CACHE_HOME
## What an arm64 Linux host fetches, which a stand-in uname can ask for anywhere.
armAsset="linux-arm64.tgz"
## Likewise a FreeBSD one.
bsdAsset="freebsd-x86_64.tgz"

## The alpha went out before release names had the version.
fAssetName(){  ## tag, platform part
	if [[ "$1" == "v1.0.0-alpha.1" ]]; then printf '%s\n' "${PROG}-$2"; else printf '%s\n' "${PROG}-${1#v}-$2"; fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A tree the stock python server can serve, laid out at the paths the rewritten
## URLs ask for.

# shellcheck source=cicd/utility/include/safe-rm.bash
source "${repoRoot}/cicd/utility/include/safe-rm.bash"
serverPid=""
fCleanup(){
	[[ -n "${serverPid}" ]] && kill "${serverPid}" 2>/dev/null
	[[ -n "${safeRmRunDir}" ]] || return 0
	((doKeep)) && { fLine ""; fEcho "Kept: ${safeRmRunDir}"; return 0 ;}
	fSafeRm "${safeRmRunDir}"
	return 0
}
trap fCleanup EXIT
fRunDir_Sub "${PROG}" installer-test || fDie "no run folder"
work="${safeRmRunDir}"
## The guard refuses a path that isn't there.
fRmIfThere(){ if [[ -e "$1" || -L "$1" ]]; then fSafeRm "$1"; fi ;}

srvRoot="${work}/srv"
apiDir="${srvRoot}/api/repos/${REPO}"
dlRoot="${srvRoot}/dl/${REPO}/releases/download"
mkdir -p "${apiDir}" "${dlRoot}"

## Newest first, the order the real API answers in. The draft has to be dropped,
## the newest prerelease is what --release dev takes, and the newest full release
## is what the default takes. One release alone would not tell those apart.
cat > "${apiDir}/releases" <<'JSON'
[
	{
		"tag_name": "v2.1.0-beta.1",
		"draft": false,
		"prerelease": true
	},
	{
		"tag_name": "v2.0.0",
		"draft": false,
		"prerelease": false
	},
	{
		"tag_name": "v9.9.9-draft",
		"draft": true,
		"prerelease": false
	},
	{
		"tag_name": "v1.0.0",
		"draft": false,
		"prerelease": false
	}
]
JSON

## A stand-in for the real command: enough of --version for the installers'
## re-run check to have something to read. Run bare, it names the asset it came
## in, so a case can tell which one was installed. "old" gives the line beta.1
## and earlier print, which is still what's out there.
fWriteStandIn(){  ## tag, asset, path, [old]
	local -r tag="$1" asset="$2" path="$3" form="${4:-}"
	local versionLine="${PROG} v${tag#v} build test\\nCopyright (C) 2026 Jim Collier"
	if [[ "${form}" == "old" ]]; then versionLine="${tag#v} (build test)"; fi
	{
		printf '#!/usr/bin/env bash\n'
		# shellcheck disable=2016  ## The single quotes are the point: this is the text of the stand-in, not something to expand here.
		printf 'case "${1:-}" in --version) printf "%s\\n" ;; *) printf "stand-in %%s\\n" "%s" ;; esac\n' \
			"${versionLine}" "${asset}"
	} > "${path}"
	chmod +x "${path}"
}

## The version a --version line names, in either form.
fVersionOf(){  ## command
	local line=""
	line="$("$1" --version 2>/dev/null | head -n1 || true)"
	line="${line#"${PROG}" v}"
	printf '%s' "${line%% *}"
}

fMakeRelease(){
	local -r tag="$1"
	local -r stageDir="${work}/stage-${tag}"
	local -r outDir="${dlRoot}/${tag}"
	local -r standIn="${stageDir}/${PROG}-${tag}/bin/${PROG}"
	mkdir -p "${stageDir}/${PROG}-${tag}/bin" "${outDir}"
	local name="" part=""

	: > "${outDir}/checksums.txt"
	for part in "${hostAsset}" "${armAsset}" "${bsdAsset}"; do
		name="$(fAssetName "${tag}" "${part}")"
		[[ ! -e "${outDir}/${name}" ]] || continue
		fWriteStandIn "${tag}" "${name}" "${standIn}"
		tar -czf "${outDir}/${name}" -C "${stageDir}" "${PROG}-${tag}"
		( cd "${outDir}" && sha256sum "${name}" >> checksums.txt )
	done
	## A zip for the Windows path, so a run there has something to fetch too.
	if command -v zip >/dev/null 2>&1; then
		name="$(fAssetName "${tag}" windows-x86_64.zip)"
		( cd "${stageDir}" && zip -qr "${outDir}/${name}" "${PROG}-${tag}" )
		( cd "${outDir}" && sha256sum "${name}" >> checksums.txt )
	fi
}
fMakeRelease "v2.1.0-beta.1"
fMakeRelease "v2.0.0"
fMakeRelease "v1.0.0-alpha.1"

## Port 0 lets the kernel pick, so parallel runs and a busy box cannot collide.
## Every path asked for is logged, which is how the re-run case tells a no-op
## from a script that merely says it did nothing.
python3 - "${srvRoot}" "${work}/port" "${work}/requests.log" <<'PY' &
import http.server, socketserver, sys, os
root, portFile, logFile = sys.argv[1], sys.argv[2], sys.argv[3]
os.chdir(root)
class Logged(http.server.SimpleHTTPRequestHandler):
	def log_message(self, *a): pass
	def do_GET(self):
		with open(logFile, "a") as f:
			f.write(self.path + "\n")
		super().do_GET()
with socketserver.TCPServer(("127.0.0.1", 0), Logged) as httpd:
	with open(portFile, "w") as f:
		f.write(str(httpd.server_address[1]))
	httpd.serve_forever()
PY
serverPid=$!

## Downloads only. The release listing is read on every run by design, so
## counting that would say nothing about whether anything was fetched.
fRequestCount(){ grep -c '/dl/' "${work}/requests.log" 2>/dev/null || printf '0' ;}

for _ in $(seq 1 50); do
	[[ -s "${work}/port" ]] && break
	sleep 0.1
done
[[ -s "${work}/port" ]] || fDie "the local server did not come up"
port="$(cat "${work}/port")"
baseUrl="http://127.0.0.1:${port}"

curl -fsS "${baseUrl}/api/repos/${REPO}/releases" >/dev/null \
	|| fDie "the local server is not answering on ${port}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Patched copies. Each rewrite is asserted, so this cannot pass by testing a
## substitution that no longer matches anything.

fRewrite(){  ## file, description, sed expression...
	local -r file="$1" what="$2"; shift 2
	local before="" after=""
	before="$(md5sum "${file}" | cut -d' ' -f1)"
	## Not sed -i, which BSD sed reads differently. cat keeps the file's mode.
	sed "$@" "${file}" > "${file}.new"
	cat "${file}.new" > "${file}"
	rm -f "${file}.new"
	after="$(md5sum "${file}" | cut -d' ' -f1)"
	[[ "${before}" != "${after}" ]] || fDie "nothing to rewrite in $(basename "${file}"): ${what}. The script moved; fix this harness."
}

bashCopy="${work}/install-copy.bash"
cp "${repoRoot}/install.bash" "${bashCopy}"
fRewrite "${bashCopy}" "the releases API URL" -e "s|https://api\.github\.com/repos/|${baseUrl}/api/repos/|"
fRewrite "${bashCopy}" "the download URL"     -e "s|https://github\.com/|${baseUrl}/dl/|"
## curl pins https, which a local server cannot answer.
fRewrite "${bashCopy}" "curl's https pinning" -e "s|--proto '=https' --tlsv1\.2 ||g"

if ((hasPwsh)) && [[ -f "${repoRoot}/install.ps1" ]]; then
	ps1Copy="${work}/install-copy.ps1"
	cp "${repoRoot}/install.ps1" "${ps1Copy}"
	fRewrite "${ps1Copy}" "the releases API URL" -e "s|https://api\.github\.com/repos/|${baseUrl}/api/repos/|"
	fRewrite "${ps1Copy}" "the download URL"     -e "s|https://github\.com/|${baseUrl}/dl/|"
fi

## A second pair, with /opt and /usr/local moved under a scratch root. That is
## the only way to reach --target system here: the real locations need root, and
## a test that asks for root is a test nobody runs. Kept separate from the copies
## above so the default-target case still sees the real /usr/local/bin, which
## is what that case checks.
sysRoot="${work}/sysroot"

bashSysCopy="${work}/install-sys.bash"
cp "${bashCopy}" "${bashSysCopy}"
fRewrite "${bashSysCopy}" "the system install directory" -e "s|systemDir=\"/|systemDir=\"${sysRoot}/|g"
fRewrite "${bashSysCopy}" "the system link path"         -e "s|systemLink=\"/|systemLink=\"${sysRoot}/|g"

ps1SysCopy=""
if [[ -n "${ps1Copy:-}" ]]; then
	ps1SysCopy="${work}/install-sys.ps1"
	cp "${ps1Copy}" "${ps1SysCopy}"
	fRewrite "${ps1SysCopy}" "the system install directory" -e "s|\"/opt/\$program\"|\"${sysRoot}/opt/\$program\"|g"
	fRewrite "${ps1SysCopy}" "the system link directory"    -e "s|'/usr/local/bin'|'${sysRoot}/usr/local/bin'|g"
fi

## install.bash prefixes every write of a system install with sudo. A shim runs
## the command as-is and records that it was asked, which is also how the user
## target proves it never reaches for root.
shimDir="${work}/shim"
sudoLog="${work}/sudo.log"
mkdir -p "${shimDir}"
{
	printf '#!/usr/bin/env bash\n'
	printf 'printf "%%s\\n" "$*" >> "%s"\n' "${sudoLog}"
	printf 'exec "$@"\n'
} > "${shimDir}/sudo"
chmod +x "${shimDir}/sudo"

fSudoCount(){
	[[ -f "${sudoLog}" ]] || { printf '0'; return 0 ;}
	wc -l < "${sudoLog}" | tr -d ' '
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Each case gets its own HOME, so nothing leaks between them and nothing
## outside the scratch tree is ever a target.

## Named rather than counted. A counter here would be incremented inside the
## command substitution that reads it, so the subshell would keep the new value
## and every case would quietly share one directory.
fNewHome(){  ## label
	local -r home="${work}/home-$1"
	fRmIfThere "${home}"
	mkdir -p "${home}/.local/bin"
	printf '%s' "${home}"
}

## The two installers spell the same switches differently, so cases name them
## once, in the neutral words below, and each runner translates. The pathPrefix
## is where the sudo shim goes; it is empty for everything but a system case.
fRunBashAs(){  ## script, pathPrefix, home, verb...
	[[ -z "${skipWhy}" ]] || return 0
	local -r script="$1" pathPrefix="$2" home="$3"; shift 3
	local -a args=()
	local verb
	for verb in "$@"; do case "${verb}" in
		dev)       args+=(--release dev) ;;
		user)      args+=(--target user) ;;
		system)    args+=(--target system) ;;
		yes)       args+=(--yes) ;;
		uninstall) args+=(--uninstall) ;;
		*) fDie "unknown verb: ${verb}" ;;
	esac; done
	HOME="${home}" PATH="${pathPrefix}${PATH}" bash "${script}" "${args[@]}" 2>&1
}

fRunPs1As(){  ## script, pathPrefix, home, verb...
	[[ -z "${skipWhy}" ]] || return 0
	local -r script="$1" pathPrefix="$2" home="$3"; shift 3
	local -a args=()
	local verb
	for verb in "$@"; do case "${verb}" in
		dev)       args+=(-Release dev) ;;
		user)      args+=(-Target user) ;;
		system)    args+=(-Target system) ;;
		yes)       args+=(-Yes) ;;
		uninstall) args+=(-Uninstall) ;;
		*) fDie "unknown verb: ${verb}" ;;
	esac; done
	HOME="${home}" PATH="${pathPrefix}${PATH}" pwsh -NoProfile -File "${script}" "${args[@]}" 2>&1
}

fRunBash(){     local -r home="$1"; shift; fRunBashAs "${bashCopy}"    ""              "${home}" "$@" ;}
fRunPs1(){      local -r home="$1"; shift; fRunPs1As  "${ps1Copy:-}"  ""              "${home}" "$@" ;}
fRunBashSys(){  local -r home="$1"; shift; fRunBashAs "${bashSysCopy}" "${shimDir}:"   "${home}" "$@" ;}
fRunPs1Sys(){   local -r home="$1"; shift; fRunPs1As  "${ps1SysCopy}"  "${shimDir}:"   "${home}" "$@" ;}

## What ended up on the link path, per the stand-in's own --version.
fInstalledVersion(){  ## home
	local -r link="$1/.local/bin/${PROG}"
	[[ -x "${link}" ]] || { printf 'none'; return 0 ;}
	fVersionOf "${link}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The release choice. Both installers pick from the full listing, so a draft is
## skipped, the default takes the newest full release, and dev takes the newest
## of either. install.ps1 used to find nothing at all here: Invoke-RestMethod
## hands a JSON array to the pipeline as one object, so every release's draft
## flag was tested as one array and none survived.

## The target is named rather than left to the default, so a wrong default
## cannot be what fails here. That choice has its own case.
fCase_ReleaseChoice(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out="" got=""

	home="$(fNewHome "${label}-stable")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=dcrem ps1=dcren "${label}: default is the newest full release"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "should take v2.0.0, got ${got}. Output: ${out}"
	fi

	home="$(fNewHome "${label}-dev")"
	out="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=dcrep ps1=dcreq "${label}: dev takes the newest prerelease"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "should take v2.1.0-beta.1, got ${got}. Output: ${out}"
	fi
}

## Before the first stable release, the only thing published was a prerelease,
## and both installers asked for 'latest', which never answers with one. So a
## default install found nothing. It has to fall back, and say it did.
fCase_PrereleaseOnly(){  ## label, runner
	local -r label="$1" runner="$2"
	local -r listing="${apiDir}/releases"
	local home="" out="" got=""

	cp "${listing}" "${work}/releases.full"
	cat > "${listing}" <<'JSON'
[
	{
		"tag_name": "v2.1.0-beta.1",
		"draft": false,
		"prerelease": true
	}
]
JSON
	home="$(fNewHome "${label}-prerelease-only")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	cp "${work}/releases.full" "${listing}"

	fId "${label}" bash=ddb0c ps1=ddb0d "${label}: only a prerelease, default takes it"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "should take v2.1.0-beta.1, got ${got}. Output: ${out}"
	fi
	fId "${label}" bash=ddb0e ps1=ddb0f "${label}: and says there's no stable yet"
	if [[ "${out}" == *"No stable release yet"* ]]
		then fPass
		else fFail "said nothing about it. Output: ${out}"
	fi
}

## Release names have the version, except the alpha's, which went out first.
fCase_AssetNames(){  ## label, runner
	local -r label="$1" runner="$2"
	local -r listing="${apiDir}/releases"
	local home="" out="" got=""

	: > "${work}/requests.log"
	home="$(fNewHome "${label}-asset-name")"
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=ddynb ps1=ddync "${label}: versioned asset name"
	if grep -q -F -- "/v2.0.0/${PROG}-2.0.0-${hostAsset}" "${work}/requests.log"
		then fPass
		else fFail "asked for: $(grep -E '\.(tgz|zip)$' "${work}/requests.log" | tr '\n' ' '). Output: ${out}"
	fi

	cp "${listing}" "${work}/releases.full"
	cat > "${listing}" <<'JSON'
[
	{
		"tag_name": "v1.0.0-alpha.1",
		"draft": false,
		"prerelease": true
	}
]
JSON
	: > "${work}/requests.log"
	home="$(fNewHome "${label}-asset-alpha")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	cp "${work}/releases.full" "${listing}"
	fId "${label}" bash=ddynd ps1=ddyne "${label}: and the alpha by its old name"
	if [[ "${got}" == "1.0.0-alpha.1" ]] && grep -q -F -- "/v1.0.0-alpha.1/${PROG}-${hostAsset}" "${work}/requests.log"
		then fPass
		else fFail "got ${got}, asked for: $(grep -E '\.(tgz|zip)$' "${work}/requests.log" | tr '\n' ' '). Output: ${out}"
	fi
}

## Both scripts check the download against the published checksums. A tarball
## that does not match has to stop the install, not only be reported.
fCase_Checksum(){  ## label, runner
	local -r label="$1" runner="$2"
	local -r sums="${dlRoot}/v2.0.0/checksums.txt"
	local home="" out="" got=""

	cp "${sums}" "${work}/checksums.good"
	sed "s/^[0-9a-f]\{64\}  \(.*-${hostAsset}\)$/$(printf '0%.0s' $(seq 1 64))  \1/" "${work}/checksums.good" > "${sums}"
	if cmp -s "${sums}" "${work}/checksums.good"; then fDie "could not corrupt ${sums}; the release layout moved"; fi
	home="$(fNewHome "${label}-checksum")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	cp "${work}/checksums.good" "${sums}"

	fId "${label}" bash=ddb0x ps1=ddb0y "${label}: a checksum mismatch installs nothing"
	if [[ "${got}" == "none" && ! -e "${home}/${userShare}" ]]
		then fPass
		else fFail "installed ${got}. Output: ${out}"
	fi
	fId "${label}" bash=ddb0z ps1=ddb10 "${label}: and says why"
	if [[ "${out}" == *"checksum mismatch"* ]]
		then fPass
		else fFail "said nothing about the checksum. Output: ${out}"
	fi
}

## Without --yes the plan is shown and the answer waited for. With nothing to
## answer it, the default is no: nothing downloaded, nothing installed.
fCase_NoAnswer(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out=""
	home="$(fNewHome "${label}-no-answer")"
	local -r before="$(fRequestCount)"
	out="$("${runner}" "${home}" user < /dev/null)" || true

	fId "${label}" bash=ddb11 ps1=ddb12 "${label}: no answer, no download"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it fetched anyway. Output: ${out}"
	fi
	fId "${label}" bash=ddb13 ps1=ddb14 "${label}: or installed"
	if [[ "$(fInstalledVersion "${home}")" == "none" && ! -e "${home}/${userShare}" ]]
		then fPass
		else fFail "it installed anyway. Output: ${out}"
	fi
}

#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## package.bash's --out. It used to be handed straight to 'rm -rf', so a stray
## --out emptied whatever it named, before the build had produced anything to
## put there. A stub zig that fails is enough: the removal came first.

fCase_PackageOutDir(){
	local -r packager="${repoRoot}/cicd/utility/package.bash"
	local skipWhy=""
	[[ -f "${packager}" ]] || skipWhy="package.bash is not present"

	local -r area="${work}/pkg"
	mkdir -p "${area}/bin"
	printf '#!/bin/sh\nexit 3\n' > "${area}/bin/zig"
	chmod +x "${area}/bin/zig"

	## A directory holding somebody else's work, which is the case that hurt.
	local -r victim="${area}/victim"
	mkdir -p "${victim}/subdir"
	echo "keep me" > "${victim}/canary.txt"
	echo "me too"  > "${victim}/subdir/other.txt"

	local out=""
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${victim}" --version v0 2>&1)" || true
	fId dcrer "package: leaves a foreign --out alone"
	if [[ -f "${victim}/canary.txt" && -f "${victim}/subdir/other.txt" ]]
		then fPass
		else fFail "--out was emptied. Output: ${out}"
	fi
	fId dcres "package: and says why"
	if [[ "${out}" == *"and has no"* ]]
		then fPass
		else fFail "refused without saying why. Output: ${out}"
	fi

	## An empty directory is nobody's work, so it gets adopted rather than refused.
	local -r fresh="${area}/fresh"
	mkdir -p "${fresh}"
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${fresh}" --version v0 2>&1)" || true
	fId dcret "package: empty --out is fine"
	if [[ "${out}" != *"and has no"* ]]
		then fPass
		else fFail "an empty --out was refused. Output: ${out}"
	fi

	## And a path that does not exist yet, which is what dist/ is on a clean tree.
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${area}/brand-new" --version v0 2>&1)" || true
	fId dcrev "package: new --out is fine"
	if [[ "${out}" != *"and has no"* ]]
		then fPass
		else fFail "a new --out was refused. Output: ${out}"
	fi
}

## The install dir is the one parent the installers' guards name. One that's a
## link is refused, rather than emptied or replaced, and a link inside it is
## only unlinked, never followed.
fCase_GuardedRemoval(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out="" rc=0

	home="$(fNewHome "${label}-guard-link")"
	mkdir -p "${home}/elsewhere/sub" "$(dirname "${home}/${userShare}")"
	printf 'keep me\n' > "${home}/elsewhere/sub/canary.txt"
	ln -s "${home}/elsewhere" "${home}/${userShare}"
	out="$("${runner}" "${home}" user yes)" && rc=0 || rc=$?
	"${runner}" "${home}" user uninstall yes > /dev/null 2>&1 || true
	fId "${label}" bash=dee2f ps1=dee2g "${label}: refuses an install dir that's a link"
	if [[ ! -f "${home}/elsewhere/sub/canary.txt" ]]; then fFail "emptied the link's target. Output: ${out}"
	elif [[ ! -L "${home}/${userShare}" ]]; then fFail "replaced the link. Output: ${out}"
	elif ((rc == 0)) || [[ "${out}" != *"efused to empty"* ]]; then fFail "exited ${rc} without saying why. Output: ${out}"
	else fPass
	fi
	## It used to come wrapped in the write error, prefix twice, with advice
	## about permissions and running copies.
	local -r flat="${out//[$'\n\r|']/ }" prefix="${PROG}-install:"
	local -r afterFirst="${flat#*"${prefix}"}"
	fId "${label}" bash=deea3 ps1=deea4 "${label}: the link refusal is said once, without the write advice"
	if   [[ "${afterFirst}" == *"${prefix}"* ]]; then fFail "the prefix shows twice. Output: ${out}"
	elif [[ "${flat}" == *"couldn't write"* || "${flat}" == *"ermissions"* ]]; then fFail "has the write error's advice. Output: ${out}"
	elif [[ "${flat}" != *"it's a link, so it was left alone"* ]]; then fFail "no plain refusal. Output: ${out}"
	else fPass
	fi

	home="$(fNewHome "${label}-guard-inside")"
	mkdir -p "${home}/elsewhere/sub"
	printf 'keep me\n' > "${home}/elsewhere/sub/canary.txt"
	## Each run's temp dir has to go too.
	local -r tempsBefore="$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 | sort | tr '\n' ' ')"
	out="$("${runner}" "${home}" user yes)" || true
	[[ ! -d "${home}/${userShare}" ]] || ln -s "${home}/elsewhere" "${home}/${userShare}/planted"
	out+="$("${runner}" "${home}" user dev yes)" || true
	local -r afterReinstall="$(fInstalledVersion "${home}")"
	out+="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=dee2h ps1=dee2j "${label}: a link inside is unlinked, not followed"
	if [[ "${afterReinstall}" != "2.1.0-beta.1" ]]; then fFail "the reinstall got ${afterReinstall}. Output: ${out}"
	elif [[ ! -f "${home}/elsewhere/sub/canary.txt" ]]; then fFail "followed the link. Output: ${out}"
	elif [[ -e "${home}/${userShare}" || -L "${home}/${userShare}" ]]; then fFail "uninstall left ${userShare}. Output: ${out}"
	elif [[ "$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 | sort | tr '\n' ' ')" != "${tempsBefore}" ]]; then fFail "left a temp dir in ${TMPDIR}"
	else fPass
	fi
}

## A user uninstall takes the command's module cache too, from wherever the
## command would have put it, and doesn't follow a link there. A stand-in
## module, since the stand-in command never writes one.
fCase_Cache(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out=""

	home="$(fNewHome "${label}-cache")"
	out="$("${runner}" "${home}" user yes)" || true
	mkdir -p "${home}/${userCache}"
	printf 'x' > "${home}/${userCache}/module-0123456789abcdef.cwasm"
	printf 'x' > "${home}/${userCache}/half-written"
	out+="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=defpm ps1=defpn "${label}: user uninstall removes the module cache"
	if [[ -e "${home}/${userCache}" ]]; then fFail "${userCache} is still there. Output: ${out}"
	elif [[ "${out}" != *"Remove: ${home}/${userCache} "* ]]; then fFail "the plan didn't name it. Output: ${out}"
	else fPass
	fi

	## The command reads XDG_CACHE_HOME everywhere but Darwin.
	home="$(fNewHome "${label}-cache-xdg")"
	mkdir -p "${home}/xdg/${PROG}" "${home}/${userCache}"
	printf 'x' > "${home}/xdg/${PROG}/module-0123456789abcdef.cwasm"
	printf 'x' > "${home}/${userCache}/module-0123456789abcdef.cwasm"
	local gone="${home}/xdg/${PROG}" kept="${home}/${userCache}"
	if [[ "$(uname -s)" == "Darwin" ]]; then gone="${home}/${userCache}"; kept="${home}/xdg/${PROG}"; fi
	out="$(XDG_CACHE_HOME="${home}/xdg" "${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=defpp ps1=defpq "${label}: and finds it where the command would"
	if [[ -e "${gone}" ]]; then fFail "${gone} is still there. Output: ${out}"
	elif [[ ! -f "${kept}/module-0123456789abcdef.cwasm" ]]; then fFail "removed ${kept}, which the command doesn't use here. Output: ${out}"
	else fPass
	fi

	home="$(fNewHome "${label}-cache-link")"
	mkdir -p "${home}/elsewhere" "$(dirname "${home}/${userCache}")"
	printf 'keep me\n' > "${home}/elsewhere/canary.txt"
	ln -s "${home}/elsewhere" "${home}/${userCache}"
	out="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=defpr ps1=defps "${label}: and keeps a cache dir that's a link"
	if [[ ! -f "${home}/elsewhere/canary.txt" ]]; then fFail "followed the link. Output: ${out}"
	elif [[ ! -L "${home}/${userCache}" ]]; then fFail "removed the link. Output: ${out}"
	elif [[ "${out}" != *"Keep ..: ${home}/${userCache} "* ]]; then fFail "the plan didn't say it stays. Output: ${out}"
	else fPass
	fi
}

## package.bash empties dist/ or --out through the guard, with that folder as
## the one parent, and only unlinks a link. Lifted out of the script, since the
## build ahead of it can't run here.
fCase_PackageClaim(){
	local -r packager="${repoRoot}/cicd/utility/package.bash"
	local missing="" body="" out=""
	body="$(sed -n -e '/^fDirHasContent(){/p' -e '/^fOutDirIsOurs(){/,/^}/p' -e '/^fClaimOutDir(){/,/^}/p' "${packager}" 2>/dev/null)"
	[[ "${body}" == *"fClaimOutDir"* ]] || missing="no fClaimOutDir in package.bash"

	local -r area="${work}/pkg-claim"
	mkdir -p "${area}/out/sub/deeper" "${area}/outside"
	printf 'old\n' > "${area}/out/zuid-old.tgz"; printf 'old\n' > "${area}/out/.hidden"; printf 'old\n' > "${area}/out/sub/deeper/x"
	printf 'keep me\n' > "${area}/outside/canary.txt"
	ln -s "${area}/outside" "${area}/out/link"
	: > "${area}/out/.zuid-package-dir"
	if [[ -z "${missing}" ]]; then
		out="$(
			# shellcheck disable=2034  ## Read by the lifted functions.
			OUT="${area}/out" outIsDefault=0 outMarker=".zuid-package-dir"
			# shellcheck disable=2329  ## Called by the lifted functions.
			fDie(){ printf 'died: %s\n' "$*"; exit 1; }
			eval "${body}"
			## Counted, to show each entry went through it.
			# shellcheck disable=2329  ## Called by the lifted functions.
			fSafeRm_Under(){ printf 'guard %s %s\n' "$1" "${2##*/}"; ( unset -f fSafeRm_Under; source "${repoRoot}/cicd/utility/include/safe-rm.bash"; fSafeRm_Under "$@" ) ;}
			fClaimOutDir 2>&1
		)" || true
	fi
	fId dee2e "package: empties --out through the guard"
	local -r left="$(cd "${area}/out" 2>/dev/null && find . -mindepth 1 | sort | tr '\n' ' ')"
	if [[ -n "${missing}" ]]; then fFail "${missing}"
	elif [[ ! -f "${area}/outside/canary.txt" ]]; then fFail "followed the link. Output: ${out}"
	elif [[ "${left}" != "./.zuid-package-dir " ]]; then fFail "left '${left}'. Output: ${out}"
	## Three, and the marker, which is put back.
	elif [[ "$(grep -c "^guard ${area}/out " <<< "${out}")" != "4" ]]; then fFail "not 4 entries through the guard: ${out}"
	else fPass
	fi
}

## The .deb and .rpm included zuid.h with no library behind it, so anything that
## included it failed at the link step. Building a real package here would need
## nfpm and a full release build, so this reads the nfpm contents list instead:
## a header may only be in there if a library is too.

fCase_PackageHeader(){
	local -r packager="${repoRoot}/cicd/utility/package.bash"
	local skipWhy="" contents=""
	if [[ -f "${packager}" ]]; then
		## The heredoc that becomes nfpm.yaml, from its 'contents:' line to the
		## EOF that closes it.
		contents="$(awk '/^\t\tcontents:/ { on = 1 } on { print } /^\tEOF$/ { on = 0 }' "${packager}")"
		[[ -n "${contents}" ]] || skipWhy="no nfpm contents list found in package.bash"
	else
		skipWhy="package.bash is not present"
	fi

	fId dcrhp "package: no header without its library"
	if [[ "${contents}" != *"/usr/include"* || "${contents}" == *"libzuid.so"* ]]
		then fPass
		else fFail "the nfpm contents list has /usr/include and no libzuid.so."
	fi
}

## With no target named, it's a user install. install.ps1 once tested whether
## the system location existed, so a normal user on any box got a system
## install that failed after the download. The writable case is in
## fCase_SystemTarget, against the moved system paths.
fCase_DefaultTarget(){  ## label, runner
	local -r label="$1" runner="$2"

	local home="" out="" got=""
	home="$(fNewHome "${label}-default-target")"
	out="$("${runner}" "${home}" yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=dcrfv ps1=dcrfw "${label}: unwritable system dir falls back to user"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "should have installed under HOME, got ${got}. Output: ${out}"
	fi
}

## A system install, which until now nothing had ever run. Everything it touches
## is outside HOME, so the paths, the elevation prefix and an uninstall that has
## to reach a link in /usr/local/bin were all untested. The copies used here have
## those two locations moved under the scratch tree.
##
## elevates is "yes" for a script that shells out to sudo and "no" for one that
## writes and hopes, which is what install.ps1 does.
fCase_SystemTarget(){  ## label, runner, elevates
	local -r label="$1" runner="$2" elevates="$3"
	local home="" out="" got=""
	local -r installed="${sysRoot}/opt/${PROG}"
	local -r link="${sysRoot}/usr/local/bin/${PROG}"

	fRmIfThere "${sysRoot}"
	mkdir -p "${sysRoot}/usr/local/bin"
	: > "${sudoLog}"

	## The user target through the same copy, so "no sudo here" is a comparison
	## against a run that could have used it and did not.
	home="$(fNewHome "${label}-system-user")"
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=dcrm6 ps1=dcrm7 "${label}: user install needs no root"
	if [[ "$(fSudoCount)" == "0" ]]
		then fPass
		else fFail "called sudo $(fSudoCount) time(s). Output: ${out}"
	fi

	## Writable or not, system is only when asked for. Both used to pick it
	## whenever they could write there, root and admins included.
	home="$(fNewHome "${label}-system-default")"
	out="$("${runner}" "${home}" yes)" || true
	fId "${label}" bash=ddye2 ps1=ddye3 "${label}: writable system dir, still a user install"
	if [[ "$(fInstalledVersion "${home}")" == "2.0.0" && ! -e "${installed}" && "$(fSudoCount)" == "0" ]]
		then fPass
		else fFail "got $(fInstalledVersion "${home}") under HOME, ${installed} $([[ -e "${installed}" ]] && echo exists || echo absent). Output: ${out}"
	fi

	home="$(fNewHome "${label}-system")"
	out="$("${runner}" "${home}" system yes)" || true

	fId "${label}" bash=dcrm8 ps1=dcrm9 "${label}: system install under /opt/${PROG}"
	if [[ -x "${installed}/bin/${PROG}" ]]
		then fPass
		else fFail "nothing at ${installed}/bin/${PROG}. Output: ${out}"
	fi

	got="none"
	[[ -x "${link}" ]] && got="$(fVersionOf "${link}")"
	fId "${label}" bash=dcrma ps1=dcrmb "${label}: and /usr/local/bin runs it"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "${link} gave ${got}. Output: ${out}"
	fi
	fId "${label}" bash=dcrmc ps1=dcrmd "${label}: and it's a symlink"
	if [[ -L "${link}" ]]
		then fPass
		else fFail "${link} is not a symlink. Output: ${out}"
	fi

	## The two targets are meant to be separate installs, not one with a second
	## name. A system run writing into HOME would make uninstall miss half of it.
	fId "${label}" bash=dcrme ps1=dcrmf "${label}: and leaves HOME alone"
	if [[ -e "${home}/${userShare}" || -e "${home}/.local/bin/${PROG}" ]]
		then fFail "a system install also wrote under HOME. Output: ${out}"
		else fPass
	fi

	if [[ "${elevates}" == "yes" ]]; then
		fId "${label}" bash=dcrmg "${label}: and writes through sudo"
		if (($(fSudoCount) > 0))
			then fPass
			else fFail "never called sudo. Output: ${out}"
		fi
		fId "${label}" bash=dcrmh "${label}: and the plan says so"
		if [[ "${out}" == *"this needs root"* ]]
			then fPass
			else fFail "the plan did not mention root. Output: ${out}"
		fi
	fi

	## The re-run check reads --version off the link path, which for a system
	## install is somewhere the user target never looks.
	local -r before="$(fRequestCount)"
	out="$("${runner}" "${home}" system yes)" || true
	fId "${label}" bash=dcrmj ps1=dcrmk "${label}: a system re-run downloads nothing"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "the re-run fetched again. Output: ${out}"
	fi

	mkdir -p "${home}/${userCache}"
	printf 'x' > "${home}/${userCache}/module-0123456789abcdef.cwasm"
	out="$("${runner}" "${home}" system uninstall yes)" || true
	fId "${label}" bash=defpt ps1=defpv "${label}: system uninstall leaves the caches, and says where"
	if [[ ! -f "${home}/${userCache}/module-0123456789abcdef.cwasm" ]]; then fFail "removed ${userCache}. Output: ${out}"
	elif [[ "${out}" != *"module cache in each user's ~/${userCache}"* ]]; then fFail "didn't say where they are. Output: ${out}"
	else fPass
	fi
	fId "${label}" bash=dcrmm ps1=dcrmn "${label}: system uninstall"
	if [[ ! -e "${installed}" ]]
		then fPass
		else fFail "${installed} is still there. Output: ${out}"
	fi
	fId "${label}" bash=dcrmp ps1=dcrmq "${label}: and the link with it"
	if [[ ! -e "${link}" && ! -L "${link}" ]]
		then fPass
		else fFail "${link} is still there. Output: ${out}"
	fi
}

## install.ps1 asked for a system target it cannot write. It has no sudo, and
## the write is the last thing it does, so it used to download and verify the
## whole release and then throw a raw permissions error from New-Item. Counted
## by what the server was asked for: the point is that nothing is fetched.
##
## install.bash needs no equivalent - a system install there goes through sudo.
fCase_SystemUnwritable(){
	local skipWhy="${skipWhy}"
	[[ "$(id -u)" != "0" ]] || skipWhy="running as root, so there is no unwritable location to test"

	fRmIfThere "${sysRoot}"
	mkdir -p "${sysRoot}"
	chmod a-w "${sysRoot}"

	local -r before="$(fRequestCount)"
	local -r home="$(fNewHome "ps1-system-unwritable")"
	local out="" rc=0
	out="$(fRunPs1Sys "${home}" system yes)" || rc=$?

	chmod u+w "${sysRoot}"

	fId dcrmr "ps1: unwritable system target fails"
	if ((rc != 0))
		then fPass
		else fFail "it succeeded. Output: ${out}"
	fi
	fId dcrms "ps1: before any download"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it downloaded first. Output: ${out}"
	fi
	fId dcrmt "ps1: and names the alternative"
	if [[ "${out}" == *"-Target user"* ]]
		then fPass
		else fFail "gave no way forward. Output: ${out}"
	fi
}

## Re-running on the version already installed. Both scripts' help, the README
## and the closed backlog item all said that changes nothing, and nothing
## compared the installed version with the chosen tag, so a second run
## downloaded the release again, deleted the install directory and copied it
## back. Counted by what the server was asked for, not by what the script says.
fCase_Rerun(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" first="" second="" got=""
	home="$(fNewHome "${label}-rerun")"

	first="$("${runner}" "${home}" user yes)" || true
	local -r firstGot="$(fInstalledVersion "${home}")"

	local -r before="$(fRequestCount)"
	second="$("${runner}" "${home}" user yes)" || true
	local -r after="$(fRequestCount)"

	fId "${label}" bash=dcrfx ps1=dcrfy "${label}: same-version re-run downloads nothing"
	if [[ "${firstGot}" != "2.0.0" ]]
		then fFail "the first run did not install. Output: ${first}"
	elif [[ "${after}" == "${before}" ]]
		then fPass
		else fFail "the re-run made $((after - before)) request(s). Output: ${second}"
	fi
	fId "${label}" bash=dcrfz ps1=dcrg0 "${label}: and says it's installed"
	if [[ "${second}" == *"Already installed"* ]]
		then fPass
		else fFail "said nothing about being already installed. Output: ${second}"
	fi

	## An install from beta.1 or before has the old --version line.
	fWriteStandIn "v2.0.0" "old-line" "${home}/${userShare}/bin/${PROG}" old
	local -r beforeOld="$(fRequestCount)"
	second="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=dee3k ps1=dee3m "${label}: the old --version line still reads as installed"
	if [[ "$(fRequestCount)" == "${beforeOld}" && "${second}" == *"Already installed"* ]]
		then fPass
		else fFail "the re-run fetched again or didn't say so. Output: ${second}"
	fi

	## A different version still replaces it, so the check cannot be a blanket
	## refusal to do anything.
	second="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=dcrg1 ps1=dcrg2 "${label}: another version installs over it"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "expected the beta to replace it, got ${got}. Output: ${second}"
	fi
}

## A flag with its value left off reached 'shift 2' with one argument left.
## That fails, and under set -e the script ended with nothing printed at all.
## install.ps1 needs no equivalent: PowerShell's own parameter binding reports
## a missing argument by name.
fCase_MissingValue(){
	local flag="" out="" rc=0
	for flag in --release --target; do
		rc=0
		out="$(HOME="$(fNewHome "missing-value")" bash "${bashCopy}" "${flag}" 2>&1)" || rc=$?
		fId "${flag}" --release=dcrgb --target=dcrgc "bash: bare ${flag} named"
		if ((rc != 0)) && [[ "${out}" == *"${flag}"* && "${out}" == *"needs a value"* ]]
			then fPass
			else fFail "rc=${rc} and '${out}'"
		fi
	done
}

## install.bash used to take any system it did not know for FreeBSD and go
## looking for that tarball. OpenBSD has no build.
fCase_NoBuild(){
	local out="" rc=0 home=""
	local -r fakeDir="${work}/fake-uname"
	mkdir -p "${fakeDir}"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'realUname=%q\n' "$(command -v uname)"
		cat <<'SH'
case "${1:-}" in -s) echo OpenBSD ;; *) exec "${realUname}" "$@" ;; esac
SH
	} > "${fakeDir}/uname"
	chmod +x "${fakeDir}/uname"
	home="$(fNewHome "no-build")"
	local -r before="$(fRequestCount)"
	out="$(HOME="${home}" PATH="${fakeDir}:${PATH}" bash "${bashCopy}" --target user --yes 2>&1)" || rc=$?

	fId ddf9d "bash: unsupported system named"
	if ((rc != 0)) && [[ "${out}" == *"OpenBSD"* && "${out}" == *"no ${PROG} build"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	fId ddf9e "bash: and downloads nothing"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it fetched anyway. Output: ${out}"
	fi
}

## An arm64 Linux machine says aarch64, not arm64, and the release is named
## arm64. A stand-in uname reports one, so this runs on any host.
fCase_Arm64Linux(){
	local out="" home="" got=""
	local -r fakeDir="${work}/fake-uname-arm64"
	mkdir -p "${fakeDir}"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'realUname=%q\n' "$(command -v uname)"
		cat <<'SH'
case "${1:-}" in -s) echo Linux ;; -m) echo aarch64 ;; *) exec "${realUname}" "$@" ;; esac
SH
	} > "${fakeDir}/uname"
	chmod +x "${fakeDir}/uname"
	home="$(fNewHome "arm64-linux")"
	: > "${work}/requests.log"
	out="$(HOME="${home}" PATH="${fakeDir}:${PATH}" bash "${bashCopy}" --target user --yes 2>&1)" || true
	got="$(fInstalledVersion "${home}")"

	fId ddfae "bash: aarch64 Linux gets the arm64 tarball"
	if grep -q -- "-${armAsset}\$" "${work}/requests.log" && ! grep -q '\.tgz$' <(grep -v -- "-${armAsset}\$" "${work}/requests.log")
		then fPass
		else fFail "asked for: $(grep '\.tgz$' "${work}/requests.log" | tr '\n' ' '). Output: ${out}"
	fi
	fId ddfaf "bash: and installs it"
	if [[ "${got}" == "2.0.0" && "$("${home}/.local/bin/${PROG}" 2>&1 || true)" == *"${armAsset}"* ]]
		then fPass
		else fFail "should install v2.0.0 from ${armAsset}, got ${got}: $("${home}/.local/bin/${PROG}" 2>&1 || true). Output: ${out}"
	fi
}

## FreeBSD says amd64 and the release says x86_64. It has no arm64 build, so an
## arm64 FreeBSD machine is refused rather than handed the Linux one.
fCase_FreeBSD(){
	local out="" home="" got="" rc=0 before=""
	local -r fakeDir="${work}/fake-uname-freebsd"
	mkdir -p "${fakeDir}"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'realUname=%q\n' "$(command -v uname)"
		cat <<'SH'
case "${1:-}" in -s) echo FreeBSD ;; -m) echo "${FAKE_MACHINE:-amd64}" ;; *) exec "${realUname}" "$@" ;; esac
SH
	} > "${fakeDir}/uname"
	chmod +x "${fakeDir}/uname"
	home="$(fNewHome "freebsd")"
	: > "${work}/requests.log"
	out="$(HOME="${home}" PATH="${fakeDir}:${PATH}" bash "${bashCopy}" --target user --yes 2>&1)" || true
	got="$(fInstalledVersion "${home}")"

	fId ddgf3 "bash: amd64 FreeBSD gets its tarball"
	if grep -q -- "-${bsdAsset}\$" "${work}/requests.log" && ! grep -q '\.tgz$' <(grep -v -- "-${bsdAsset}\$" "${work}/requests.log")
		then fPass
		else fFail "asked for: $(grep '\.tgz$' "${work}/requests.log" | tr '\n' ' '). Output: ${out}"
	fi
	fId ddgf4 "bash: and installs it"
	if [[ "${got}" == "2.0.0" && "$("${home}/.local/bin/${PROG}" 2>&1 || true)" == *"${bsdAsset}"* ]]
		then fPass
		else fFail "should install v2.0.0 from ${bsdAsset}, got ${got}: $("${home}/.local/bin/${PROG}" 2>&1 || true). Output: ${out}"
	fi

	home="$(fNewHome "freebsd-arm64")"
	before="$(fRequestCount)"
	out="$(HOME="${home}" FAKE_MACHINE=arm64 PATH="${fakeDir}:${PATH}" bash "${bashCopy}" --target user --yes 2>&1)" || rc=$?
	fId ddgf5 "bash: no build for arm64 FreeBSD"
	if ((rc != 0)) && [[ "${out}" == *"FreeBSD"* && "${out}" == *"arm64"* && "${out}" == *"no ${PROG} build"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	fId ddgf8 "bash: and downloads nothing"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it fetched anyway. Output: ${out}"
	fi
}

## A zuid at the link path that the installer did not put there. The README
## tells a source build that a full cicd run copies one to ~/.local/bin, so this
## is a real collision, and uninstall used to delete it.
fCase_ForeignLink(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out=""

	home="$(fNewHome "${label}-foreign-link")"
	local -r planted="${home}/.local/bin/${PROG}"
	printf '#!/bin/sh\necho somebody else\n' > "${planted}"
	chmod +x "${planted}"

	out="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=dcrge ps1=dcrgf "${label}: uninstall keeps a file it didn't make"
	if [[ -f "${planted}" ]]
		then fPass
		else fFail "uninstall deleted a file it did not create. Output: ${out}"
	fi
	fId "${label}" bash=dcrgg ps1=dcrgh "${label}: and says so"
	if [[ "${out}" == *"not this installer's link"* ]]
		then fPass
		else fFail "said nothing about keeping it. Output: ${out}"
	fi

	## Installing over it does replace it - that is what an installer does - but
	## the plan has to name it rather than do it quietly.
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=dcrgj ps1=dcrgk "${label}: install names what it overwrites"
	if [[ "${out}" == *"is not this installer's link"* ]]
		then fPass
		else fFail "overwrote it without saying so. Output: ${out}"
	fi

	## And once it is the installer's own link, uninstall does remove it.
	out="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=dcrgm ps1=dcrgn "${label}: uninstall removes its own link"
	if [[ ! -e "${planted}" ]]
		then fPass
		else fFail "left its own link behind. Output: ${out}"
	fi
}

## The README runs both from a pipe, where there's no file for --help to read
## its own text from. install.bash printed nothing there.
fCase_HelpPiped(){
	local out="" rc=0
	out="$(bash <(cat "${bashCopy}") --help 2>&1)" || rc=$?
	fId ddybe "bash: --help works from a pipe"
	if ((rc == 0)) && [[ "${out}" == *"Usage:"* && "${out}" == *"--release"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	rc=0
	out="$(bash "${bashCopy}" --version 2>&1)" || rc=$?
	fId ddybf "bash: --version"
	if ((rc == 0)) && [[ "${out}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
}

## Windows PowerShell 5.1 runs on .NET Framework, which lacks some of what
## pwsh has. PSScriptAnalyzer's own 5.1 profile names what's missing. It can't
## see a read of $IsWindows, which 5.1 doesn't have, so that one takes a real
## 5.1 run.
fCase_Ps1Compat(){
	local skipWhy="${skipWhy}" out="" rc=0
	if [[ -z "${skipWhy}" ]] && ! pwsh -NoProfile -Command 'if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { exit 1 }' >/dev/null 2>&1; then
		skipWhy="PSScriptAnalyzer not installed"
	fi
	if [[ -z "${skipWhy}" ]]; then
		# shellcheck disable=2016  ## PowerShell's own variables.
		out="$(ZUID_PS1="${repoRoot}/install.ps1" pwsh -NoProfile -Command '
			$p = "win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework"
			$rules = @{
				PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @("5.1", "7.0") }
				PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @($p) }
				PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @($p) }
			}
			if (-not (Test-Path $env:ZUID_PS1)) { "no file at $env:ZUID_PS1"; exit 1 }
			$found = @(Invoke-ScriptAnalyzer -Path $env:ZUID_PS1 -Settings @{ Rules = $rules })
			$found | ForEach-Object { "{0}: {1}" -f $_.Line, $_.Message }
			if ($found.Count) { exit 1 }' 2>&1)" || rc=$?
	fi
	fId ddye4 "ps1: fits Windows PowerShell 5.1"
	if ((rc == 0))
		then fPass
		else fFail "${out}"
	fi
}

fCase_HelpPs1(){
	local out="" rc=0
	if [[ -z "${skipWhy}" ]]; then
		out="$(pwsh -NoProfile -Command "& ([scriptblock]::Create((Get-Content -Raw '${ps1Copy}'))) -Help" 2>&1)" || rc=$?
	fi
	fId ddybg "ps1: -Help works from a scriptblock"
	if ((rc == 0)) && [[ "${out}" == *"Usage:"* && "${out}" == *"-Release"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	rc=0
	if [[ -z "${skipWhy}" ]]; then
		out="$(pwsh -NoProfile -File "${ps1Copy}" -Version 2>&1)" || rc=$?
	fi
	fId ddybh "ps1: -Version"
	if ((rc == 0)) && [[ "${out}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
}

fCase_EqualsForm(){
	local home="" out="" got=""
	home="$(fNewHome "equals-form")"
	out="$(HOME="${home}" bash "${bashCopy}" --release=dev --target=user --yes 2>&1)" || true
	got="$(fInstalledVersion "${home}")"
	fId ddybj "bash: --release=dev attached"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "expected the beta, got ${got}. Output: ${out}"
	fi
}

## GitHub lists by date. A v1.0.0 fix published after v2.0.0 used to win.
fCase_SemverOrder(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out="" got=""
	cp "${apiDir}/releases" "${work}/releases.byDate"
	cat > "${apiDir}/releases" <<'JSON'
[
	{ "tag_name": "v1.0.0", "draft": false, "prerelease": false },
	{ "tag_name": "v2.1.0-beta.1", "draft": false, "prerelease": true },
	{ "tag_name": "v2.0.0", "draft": false, "prerelease": false }
]
JSON
	home="$(fNewHome "${label}-semver-dev")"
	out="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=ddybk ps1=ddybm "${label}: dev goes by version, not list order"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "expected 2.1.0-beta.1, got ${got}. Output: ${out}"
	fi
	home="$(fNewHome "${label}-semver-stable")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=ddybn ps1=ddybp "${label}: and so does stable"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "expected 2.0.0, got ${got}. Output: ${out}"
	fi
	cp "${work}/releases.byDate" "${apiDir}/releases"
}

## A rate limit or a dead network used to read as "no published release found".
fCase_LookupFails(){  ## label, copy
	local -r label="$1" copy="$2"
	local out="" rc=0 broken="${work}/lookup-fails-${label}"
	if [[ -z "${skipWhy}" ]]; then
		cp "${copy}" "${broken}"
		fRewrite "${broken}" "the releases API URL" -e "s|${baseUrl}/api/repos/|${baseUrl}/api/nowhere/|"
		if [[ "${label}" == "bash" ]]
			then out="$(HOME="$(fNewHome "${label}-lookup")" bash "${broken}" --target user --yes 2>&1)" || rc=$?
			else out="$(HOME="$(fNewHome "${label}-lookup")" pwsh -NoProfile -File "${broken}" -Target user -Yes 2>&1)" || rc=$?
		fi
	fi
	fId "${label}" bash=ddybq ps1=ddybr "${label}: a failed lookup gives the HTTP status"
	if ((rc != 0)) && [[ "${out}" == *"HTTP 404"* && "${out}" != *"no published release"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
}

## A build copied to ~/.local/bin by hand, at the same version, used to make
## install.bash say "Already installed" with nothing in the install directory.
fCase_ForeignSameVersion(){  ## label, runner
	local -r label="$1" runner="$2"
	local home="" out=""
	home="$(fNewHome "${label}-foreign-same")"
	fWriteStandIn "v2.0.0" "hand-copied" "${home}/.local/bin/${PROG}"
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=ddybs ps1=ddybt "${label}: a hand-copied build isn't an install"
	if [[ -x "${home}/${userShare}/bin/${PROG}" && "${out}" != *"Already installed"* ]]
		then fPass
		else fFail "nothing went into ${userShare}. Output: ${out}"
	fi
}

## A Mac's /bin/bash is 3.2, where an empty array under set -u is unbound. The
## host bash is newer, so this runs in a container when one is on hand. cicd.bash's
## container can't start one, so the run outside does these two after it.
fCase_Bash32(){
	local skipWhy="${skipWhy}" out="" rc=0 home=""
	if [[ "${ZUID_IN_CONTAINER:-}" == "1" ]]; then
		skipWhy="runs outside the container, after it"
	elif ! command -v docker >/dev/null 2>&1 || ! docker image inspect bash:3.2 >/dev/null 2>&1; then
		skipWhy="no docker image bash:3.2"
	fi
	home="$(fNewHome "bash32")"
	if [[ -z "${skipWhy}" ]]; then
		out="$(docker run --rm --network none --cpus 1 --cpu-shares 256 -e HOME=/home -v "${home}:/home" -v "${bashCopy}:/install.bash:ro" \
			bash:3.2 nice -n 19 bash /install.bash --uninstall --target user --yes 2>&1)" || rc=$?
	fi
	fId ddybv "bash 3.2: uninstall runs"
	if ((rc == 0)) && [[ "${out}" == *"Removed."* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	rc=0
	if [[ -z "${skipWhy}" ]]; then
		out="$(docker run --rm --network none --cpus 1 --cpu-shares 256 -v "${bashCopy}:/install.bash:ro" \
			bash:3.2 nice -n 19 bash -c 'bash <(cat /install.bash) --help' 2>&1)" || rc=$?
	fi
	fId ddybw "bash 3.2: --help works from a pipe"
	if ((rc == 0)) && [[ "${out}" == *"Usage:"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
}

fEcho "Installers: against a local release listing on port ${port}"
fLine ""

if [[ "${only}" == "bash32" ]]; then
	fLine "install.bash"
	fCase_Bash32
fi

if [[ "${only}" == "" || "${only}" == "bash" ]]; then
	fLine "install.bash"
	fCase_ReleaseChoice "bash" "fRunBash"
	fCase_PrereleaseOnly "bash" "fRunBash"
	fCase_AssetNames "bash" "fRunBash"
	fCase_Checksum "bash" "fRunBash"
	fCase_NoAnswer "bash" "fRunBash"
	fCase_DefaultTarget "bash" "fRunBash"
	fCase_SystemTarget "bash" "fRunBashSys" "yes"
	fCase_Rerun "bash" "fRunBash"
	fCase_MissingValue
	fCase_HelpPiped
	fCase_EqualsForm
	fCase_SemverOrder "bash" "fRunBash"
	fCase_LookupFails "bash" "${bashCopy}"
	fCase_ForeignSameVersion "bash" "fRunBash"
	fCase_Bash32
	fCase_NoBuild
	fCase_Arm64Linux
	fCase_FreeBSD
	fCase_ForeignLink "bash" "fRunBash"
	fCase_GuardedRemoval "bash" "fRunBash"
	fCase_Cache "bash" "fRunBash"
fi

## Without pwsh the ps1 cases still run, so each one reports as skipped by ID,
## but the runner does nothing.
if [[ "${only}" == "" || "${only}" == "ps1" ]]; then
	fLine ""
	fLine "install.ps1"
	if ((! hasPwsh)); then skipWhy="pwsh not installed"; fi
	fCase_ReleaseChoice "ps1" "fRunPs1"
	fCase_PrereleaseOnly "ps1" "fRunPs1"
	fCase_AssetNames "ps1" "fRunPs1"
	fCase_Checksum "ps1" "fRunPs1"
	fCase_NoAnswer "ps1" "fRunPs1"
	fCase_DefaultTarget "ps1" "fRunPs1"
	fCase_SystemTarget "ps1" "fRunPs1Sys" "no"
	fCase_SystemUnwritable
	fCase_Rerun "ps1" "fRunPs1"
	fCase_ForeignLink "ps1" "fRunPs1"
	fCase_HelpPs1
	fCase_Ps1Compat
	fCase_SemverOrder "ps1" "fRunPs1"
	fCase_LookupFails "ps1" "${ps1Copy:-}"
	fCase_ForeignSameVersion "ps1" "fRunPs1"
	fCase_GuardedRemoval "ps1" "fRunPs1"
	fCase_Cache "ps1" "fRunPs1"
	skipWhy=""
fi

if [[ "${only}" != "bash32" ]]; then
	fLine ""
	fLine "package.bash"
	fCase_PackageOutDir
	fCase_PackageClaim
	fCase_PackageHeader
fi

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}, skipped: ${skipped}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261026 JC: Uninstall and the module cache. XDG_CACHE_HOME is unset, so it's never the real one.
##		- 20261025 JC: The new --version line, and the old one still read as installed.
##		- 20261025 JC: Its folder is a run folder, removed through the guard. The installers' and the packager's guards.
##		- 20261025 JC: Test IDs in minutes. PASS, FAIL and SKIP lines.
##		- 20261025 JC: --only bash32, for the run outside cicd.bash's container.
##		- 20261014 JC: User target by default. install.ps1 against the 5.1 profile.
##		- 20261014 JC: --help from a pipe, --version, --opt=value, semver order, lookup errors, bash 3.2.
##		- 20261003 JC: An aarch64 Linux machine fetches the arm64 tarball.
##		- 20261003 JC: A system with no build is refused by name.
##		- 20260930 JC: Test IDs. A listing with only a prerelease in it, a bad checksum, no answer.
##		- 20260917 JC: Cover --target system, against a scratch /opt and /usr/local.
##		- 20260917 JC: Check what the deb and rpm contents list installs.
##		- 20260917 JC: Created, for the release-choice, re-run and link-path cases.
