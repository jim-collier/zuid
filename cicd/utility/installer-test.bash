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
##		installer-test.bash [--keep] [--only bash|ps1]
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
## in one fPass or fFail. A case run once per installer carries an ID for each,
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
	skipped=$((skipped + 1)); printf '  skip ..: %s %s (%s)\n' "${curId:-???????}" "${curName}" "${skipWhy}"
	curId=""
}
fPass(){
	if fSkipped; then return 0; fi
	if [[ -z "${curId}" ]]; then fFail "no test ID"; return 0; fi
	passed=$((passed + 1)); printf '  ok ....: %s %s\n' "${curId}" "${curName}"
	curId=""
}
fFail(){  ## detail
	if fSkipped; then return 0; fi
	failed=$((failed + 1)); printf '  FAIL ..: %s %s: %s\n' "${curId:-???????}" "${curName}" "$*"
	curId=""
}

while (($#)); do case "$1" in
	--keep)    doKeep=1; shift ;;
	--only)    only="${2:-}"; shift 2 ;;
	-h|--help) sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

case "${only}" in ""|bash|ps1) ;; *) fDie "--only wants bash or ps1, got '${only}'" ;; esac

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "${repoRoot}/install.bash" ]] || fDie "could not find install.bash from ${repoRoot}"

for tool in python3 curl tar sha256sum; do
	command -v "${tool}" >/dev/null 2>&1 || fDie "not found in PATH: ${tool}"
done

hasPwsh=0
command -v pwsh >/dev/null 2>&1 && hasPwsh=1

## What the installers fetch on this machine, and where a user install keeps it.
case "$(uname -m)" in
	aarch64|arm64) hostAsset="arm64.tgz" ;;
	*)             hostAsset="x86_64.tgz" ;;
esac
case "$(uname -s)" in
	Darwin) hostAsset="${PROG}-darwin-universal.tgz"; userShare="Library/Application Support/${PROG}" ;;
	*)      hostAsset="${PROG}-linux-${hostAsset}";   userShare=".local/share/${PROG}" ;;
esac


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A tree the stock python server can serve, laid out at the paths the rewritten
## URLs ask for.

work="$(mktemp -d)"
serverPid=""
fCleanup(){
	[[ -n "${serverPid}" ]] && kill "${serverPid}" 2>/dev/null
	((doKeep)) && { fLine ""; fEcho "Kept: ${work}"; return 0 ;}
	rm -rf "${work}"
	return 0
}
trap fCleanup EXIT

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
## re-run check to have something to read.
fMakeRelease(){
	local -r tag="$1"
	local -r stageDir="${work}/stage-${tag}"
	local -r outDir="${dlRoot}/${tag}"
	mkdir -p "${stageDir}/${PROG}-${tag}/bin" "${outDir}"
	{
		printf '#!/usr/bin/env bash\n'
		# shellcheck disable=2016  ## The single quotes are the point: this is the text of the stand-in, not something to expand here.
		printf 'case "${1:-}" in --version) printf "%%s (build test)\\n" "%s" ;; *) printf "stand-in %s\\n" "%s" ;; esac\n' \
			"${tag#v}" "${PROG}" "${tag}"
	} > "${stageDir}/${PROG}-${tag}/bin/${PROG}"
	chmod +x "${stageDir}/${PROG}-${tag}/bin/${PROG}"

	tar -czf "${outDir}/${hostAsset}" -C "${stageDir}" "${PROG}-${tag}"
	( cd "${outDir}" && sha256sum "${hostAsset}" > checksums.txt )
	## A zip for the Windows path, so a run there has something to fetch too.
	if command -v zip >/dev/null 2>&1; then
		( cd "${stageDir}" && zip -qr "${outDir}/${PROG}-windows-x86_64.zip" "${PROG}-${tag}" )
		( cd "${outDir}" && sha256sum "${PROG}-windows-x86_64.zip" >> checksums.txt )
	fi
}
fMakeRelease "v2.1.0-beta.1"
fMakeRelease "v2.0.0"

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
## above so the default-target case still sees the real /usr/local/bin, which is
## the whole point of that case.
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
	rm -rf "${home}"
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
	"${link}" --version 2>/dev/null | head -n1 | cut -d' ' -f1
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
	fId "${label}" bash=Eq9ejdI ps1=Eq9ejdJ "${label}: the default takes the newest full release"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "should take v2.0.0, got ${got}. Output: ${out}"
	fi

	home="$(fNewHome "${label}-dev")"
	out="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=Eq9ejdK ps1=Eq9ejdL "${label}: dev takes the newest prerelease"
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

	fId "${label}" bash=ErOioHp ps1=ErOioHq "${label}: with only a prerelease published, the default takes it"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass
		else fFail "should take v2.1.0-beta.1, got ${got}. Output: ${out}"
	fi
	fId "${label}" bash=ErOioHr ps1=ErOioHs "${label}: and says there is no stable release yet"
	if [[ "${out}" == *"No stable release yet"* ]]
		then fPass
		else fFail "said nothing about it. Output: ${out}"
	fi
}

## Both scripts check the download against the published checksums. A tarball
## that does not match has to stop the install, not just be reported.
fCase_Checksum(){  ## label, runner
	local -r label="$1" runner="$2"
	local -r sums="${dlRoot}/v2.0.0/checksums.txt"
	local home="" out="" got=""

	cp "${sums}" "${work}/checksums.good"
	sed "s/^[0-9a-f]\{64\}  ${hostAsset}$/$(printf '0%.0s' $(seq 1 64))  ${hostAsset}/" "${work}/checksums.good" > "${sums}"
	if cmp -s "${sums}" "${work}/checksums.good"; then fDie "could not corrupt ${sums}; the release layout moved"; fi
	home="$(fNewHome "${label}-checksum")"
	out="$("${runner}" "${home}" user yes)" || true
	got="$(fInstalledVersion "${home}")"
	cp "${work}/checksums.good" "${sums}"

	fId "${label}" bash=ErOkWfU ps1=ErOkWfV "${label}: a checksum mismatch installs nothing"
	if [[ "${got}" == "none" && ! -e "${home}/${userShare}" ]]
		then fPass
		else fFail "installed ${got}. Output: ${out}"
	fi
	fId "${label}" bash=ErOkWfW ps1=ErOkWfX "${label}: and says why"
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

	fId "${label}" bash=ErOkWfY ps1=ErOkWfZ "${label}: with no answer, nothing is downloaded"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it fetched anyway. Output: ${out}"
	fi
	fId "${label}" bash=ErOkWfa ps1=ErOkWfb "${label}: or installed"
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
	fId Eq9filc "package: an --out it did not make is left alone"
	if [[ -f "${victim}/canary.txt" && -f "${victim}/subdir/other.txt" ]]
		then fPass
		else fFail "--out was emptied. Output: ${out}"
	fi
	fId Eq9fild "package: and says why it refused"
	if [[ "${out}" == *"carries no"* ]]
		then fPass
		else fFail "refused without saying why. Output: ${out}"
	fi

	## An empty directory is nobody's work, so it gets adopted rather than refused.
	local -r fresh="${area}/fresh"
	mkdir -p "${fresh}"
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${fresh}" --version v0 2>&1)" || true
	fId Eq9file "package: an empty --out is accepted"
	if [[ "${out}" != *"carries no"* ]]
		then fPass
		else fFail "an empty --out was refused. Output: ${out}"
	fi

	## And a path that does not exist yet, which is what dist/ is on a clean tree.
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${area}/brand-new" --version v0 2>&1)" || true
	fId Eq9filf "package: a new --out is accepted"
	if [[ "${out}" != *"carries no"* ]]
		then fPass
		else fFail "a new --out was refused. Output: ${out}"
	fi
}

## The .deb and .rpm shipped zuid.h with no library behind it, so anything that
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

	fId EqA3RdA "package: the packages do not install a header with no library"
	if [[ "${contents}" != *"/usr/include"* || "${contents}" == *"libzuid.so"* ]]
		then fPass
		else fFail "the nfpm contents list has /usr/include and no libzuid.so."
	fi
}

## With no target named, the choice has to come from whether the system location
## can be written, not whether it exists. install.ps1 tested existence, so a
## normal user on a box with /usr/local/bin - which is to say any box - got a
## system install that failed after the download, with no elevation path.
##
## Skipped where the system location happens to be writable, such as a run as
## root, since then system is the right answer and there is nothing to catch.
## Both halves count: Homebrew leaves /usr/local/bin writable on an Intel Mac,
## while /opt is not.
fCase_DefaultTarget(){  ## label, runner
	local -r label="$1" runner="$2"
	local skipWhy="${skipWhy}"
	if [[ -w /usr/local/bin && -w /opt ]]; then skipWhy="/usr/local/bin and /opt are writable here, so system is the right default"; fi

	local home="" out="" got=""
	home="$(fNewHome "${label}-default-target")"
	out="$("${runner}" "${home}" yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=Eq9l4yO ps1=Eq9l4yP "${label}: an unwritable system location falls back to a user install"
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
## just writes and hopes, which is what install.ps1 does.
fCase_SystemTarget(){  ## label, runner, elevates
	local -r label="$1" runner="$2" elevates="$3"
	local home="" out="" got=""
	local -r installed="${sysRoot}/opt/${PROG}"
	local -r link="${sysRoot}/usr/local/bin/${PROG}"

	rm -rf "${sysRoot}"
	mkdir -p "${sysRoot}/usr/local/bin"
	: > "${sudoLog}"

	## The user target through the same copy, so "no sudo here" is a comparison
	## against a run that could have used it and did not.
	home="$(fNewHome "${label}-system-user")"
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=EqANb6u ps1=EqANb6v "${label}: a user install never reaches for root"
	if [[ "$(fSudoCount)" == "0" ]]
		then fPass
		else fFail "called sudo $(fSudoCount) time(s). Output: ${out}"
	fi

	home="$(fNewHome "${label}-system")"
	out="$("${runner}" "${home}" system yes)" || true

	fId "${label}" bash=EqANb6w ps1=EqANb6x "${label}: a system install lands under /opt/${PROG}"
	if [[ -x "${installed}/bin/${PROG}" ]]
		then fPass
		else fFail "nothing at ${installed}/bin/${PROG}. Output: ${out}"
	fi

	got="none"
	[[ -x "${link}" ]] && got="$("${link}" --version 2>/dev/null | head -n1 | cut -d' ' -f1)"
	fId "${label}" bash=EqANb6y ps1=EqANb6z "${label}: and /usr/local/bin runs the installed version"
	if [[ "${got}" == "2.0.0" ]]
		then fPass
		else fFail "${link} gave ${got}. Output: ${out}"
	fi
	fId "${label}" bash=EqANb70 ps1=EqANb71 "${label}: and the link is a symlink, not a copy"
	if [[ -L "${link}" ]]
		then fPass
		else fFail "${link} is not a symlink. Output: ${out}"
	fi

	## The two targets are meant to be separate installs, not one with a second
	## name. A system run writing into HOME would make uninstall miss half of it.
	fId "${label}" bash=EqANb72 ps1=EqANb73 "${label}: and leaves HOME alone"
	if [[ -e "${home}/${userShare}" || -e "${home}/.local/bin/${PROG}" ]]
		then fFail "a system install also wrote under HOME. Output: ${out}"
		else fPass
	fi

	if [[ "${elevates}" == "yes" ]]; then
		fId "${label}" bash=EqANb74 "${label}: and does its writing through sudo"
		if (($(fSudoCount) > 0))
			then fPass
			else fFail "never called sudo. Output: ${out}"
		fi
		fId "${label}" bash=EqANb75 "${label}: and the plan says so beforehand"
		if [[ "${out}" == *"this needs root"* ]]
			then fPass
			else fFail "the plan did not mention root. Output: ${out}"
		fi
	fi

	## The re-run check reads --version off the link path, which for a system
	## install is somewhere the user target never looks.
	local -r before="$(fRequestCount)"
	out="$("${runner}" "${home}" system yes)" || true
	fId "${label}" bash=EqANb76 ps1=EqANb77 "${label}: a system re-run downloads nothing"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "the re-run fetched again. Output: ${out}"
	fi

	out="$("${runner}" "${home}" system uninstall yes)" || true
	fId "${label}" bash=EqANb78 ps1=EqANb79 "${label}: uninstall removes the system directory"
	if [[ ! -e "${installed}" ]]
		then fPass
		else fFail "${installed} is still there. Output: ${out}"
	fi
	fId "${label}" bash=EqANb7A ps1=EqANb7B "${label}: and the link with it"
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

	rm -rf "${sysRoot}"
	mkdir -p "${sysRoot}"
	chmod a-w "${sysRoot}"

	local -r before="$(fRequestCount)"
	local -r home="$(fNewHome "ps1-system-unwritable")"
	local out="" rc=0
	out="$(fRunPs1Sys "${home}" system yes)" || rc=$?

	chmod u+w "${sysRoot}"

	fId EqANb7C "ps1: an unwritable system target fails"
	if ((rc != 0))
		then fPass
		else fFail "it succeeded. Output: ${out}"
	fi
	fId EqANb7D "ps1: and refuses before downloading anything"
	if [[ "$(fRequestCount)" == "${before}" ]]
		then fPass
		else fFail "it downloaded first. Output: ${out}"
	fi
	fId EqANb7E "ps1: and names the alternative"
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

	fId "${label}" bash=Eq9lTwm ps1=Eq9lTwn "${label}: a re-run on the same version downloads nothing"
	if [[ "${firstGot}" != "2.0.0" ]]
		then fFail "the first run did not install. Output: ${first}"
	elif [[ "${after}" == "${before}" ]]
		then fPass
		else fFail "the re-run made $((after - before)) request(s). Output: ${second}"
	fi
	fId "${label}" bash=Eq9lTwo ps1=Eq9lTwp "${label}: and says it is already installed"
	if [[ "${second}" == *"Already installed"* ]]
		then fPass
		else fFail "said nothing about being already installed. Output: ${second}"
	fi

	## A different version still replaces it, so the check cannot be a blanket
	## refusal to do anything.
	second="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	fId "${label}" bash=Eq9lTwq ps1=Eq9lTwr "${label}: a different version still installs over it"
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
	for flag in --release --target --arch; do
		rc=0
		out="$(HOME="$(fNewHome "missing-value")" bash "${bashCopy}" "${flag}" 2>&1)" || rc=$?
		fId "${flag}" --release=Eq9oNBg --target=Eq9oNBh --arch=Eq9oNBi "bash: ${flag} with no value names the flag"
		if ((rc != 0)) && [[ "${out}" == *"${flag}"* && "${out}" == *"needs a value"* ]]
			then fPass
			else fFail "rc=${rc} and '${out}'"
		fi
	done
}

## There is no BSD build, since Wasmtime publishes none. install.bash used to
## take any system it did not know for FreeBSD and go looking for that tarball.
fCase_NoBuild(){
	local out="" rc=0 home=""
	local -r fakeDir="${work}/fake-uname"
	mkdir -p "${fakeDir}"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'realUname=%q\n' "$(command -v uname)"
		cat <<'SH'
case "${1:-}" in -s) echo FreeBSD ;; *) exec "${realUname}" "$@" ;; esac
SH
	} > "${fakeDir}/uname"
	chmod +x "${fakeDir}/uname"
	home="$(fNewHome "no-build")"
	local -r before="$(fRequestCount)"
	out="$(HOME="${home}" PATH="${fakeDir}:${PATH}" bash "${bashCopy}" --target user --yes 2>&1)" || rc=$?

	fId Ergbz3Z "bash: a system with no build says so by name"
	if ((rc != 0)) && [[ "${out}" == *"FreeBSD"* && "${out}" == *"no ${PROG} build"* ]]
		then fPass
		else fFail "rc=${rc} and '${out}'"
	fi
	fId Ergbz3a "bash: and downloads nothing"
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
	fId "${label}" bash=Eq9oNBj ps1=Eq9oNBk "${label}: uninstall leaves a file it did not create"
	if [[ -f "${planted}" ]]
		then fPass
		else fFail "uninstall deleted a file it did not create. Output: ${out}"
	fi
	fId "${label}" bash=Eq9oNBl ps1=Eq9oNBm "${label}: and says it is keeping it"
	if [[ "${out}" == *"not this installer's link"* ]]
		then fPass
		else fFail "said nothing about keeping it. Output: ${out}"
	fi

	## Installing over it does replace it - that is what an installer does - but
	## the plan has to name it rather than do it quietly.
	out="$("${runner}" "${home}" user yes)" || true
	fId "${label}" bash=Eq9oNBn ps1=Eq9oNBo "${label}: install names what it is overwriting"
	if [[ "${out}" == *"is not this installer's link"* ]]
		then fPass
		else fFail "overwrote it without saying so. Output: ${out}"
	fi

	## And once it is the installer's own link, uninstall does remove it.
	out="$("${runner}" "${home}" user uninstall yes)" || true
	fId "${label}" bash=Eq9oNBp ps1=Eq9oNBq "${label}: uninstall removes its own link"
	if [[ ! -e "${planted}" ]]
		then fPass
		else fFail "left its own link behind. Output: ${out}"
	fi
}

fEcho "Installers: against a local release listing on port ${port}"
fLine ""

if [[ "${only}" != "ps1" ]]; then
	fLine "install.bash"
	fCase_ReleaseChoice "bash" "fRunBash"
	fCase_PrereleaseOnly "bash" "fRunBash"
	fCase_Checksum "bash" "fRunBash"
	fCase_NoAnswer "bash" "fRunBash"
	fCase_DefaultTarget "bash" "fRunBash"
	fCase_SystemTarget "bash" "fRunBashSys" "yes"
	fCase_Rerun "bash" "fRunBash"
	fCase_MissingValue
	fCase_NoBuild
	fCase_ForeignLink "bash" "fRunBash"
fi

## Without pwsh the ps1 cases still run, so each one reports as skipped by ID,
## but the runner does nothing.
if [[ "${only}" != "bash" ]]; then
	fLine ""
	fLine "install.ps1"
	if ((! hasPwsh)); then skipWhy="pwsh not installed"; fi
	fCase_ReleaseChoice "ps1" "fRunPs1"
	fCase_PrereleaseOnly "ps1" "fRunPs1"
	fCase_Checksum "ps1" "fRunPs1"
	fCase_NoAnswer "ps1" "fRunPs1"
	fCase_DefaultTarget "ps1" "fRunPs1"
	fCase_SystemTarget "ps1" "fRunPs1Sys" "no"
	fCase_SystemUnwritable
	fCase_Rerun "ps1" "fRunPs1"
	fCase_ForeignLink "ps1" "fRunPs1"
	skipWhy=""
fi

fLine ""
fLine "package.bash"
fCase_PackageOutDir
fCase_PackageHeader

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}, skipped: ${skipped}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261003 JC: A system with no build is refused by name.
##		- 20260930 JC: Test IDs. A listing with only a prerelease in it, a bad checksum, no answer.
##		- 20260917 JC: Cover --target system, against a scratch /opt and /usr/local.
##		- 20260917 JC: Check what the deb and rpm contents list installs.
##		- 20260917 JC: Created, for the release-choice, re-run and link-path cases.
