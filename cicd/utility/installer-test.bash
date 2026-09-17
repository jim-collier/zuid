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
##		Every rewrite is checked, so a script that moves its URLs fails this
##		rather than quietly testing nothing.
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

passed=0
failed=0
fPass(){ passed=$((passed + 1)); printf '  ok ....: %s\n' "$*" ;}
fFail(){ failed=$((failed + 1)); printf '  FAIL ..: %s\n' "$*" ;}

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

	local -r asset="${PROG}-linux-x86_64.tgz"
	tar -czf "${outDir}/${asset}" -C "${stageDir}" "${PROG}-${tag}"
	( cd "${outDir}" && sha256sum "${asset}" > checksums.txt )
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
	sed -i "$@" "${file}"
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
## once, in the neutral words below, and each runner translates.
fRunBash(){  ## home, verb...
	local -r home="$1"; shift
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
	HOME="${home}" bash "${bashCopy}" "${args[@]}" 2>&1
}

fRunPs1(){  ## home, verb...
	local -r home="$1"; shift
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
	HOME="${home}" pwsh -NoProfile -File "${ps1Copy}" "${args[@]}" 2>&1
}

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
	if [[ "${got}" == "2.0.0" ]]
		then fPass "${label}: the default takes the newest full release"
		else fFail "${label}: the default should take v2.0.0, got ${got}. Output: ${out}"
	fi

	home="$(fNewHome "${label}-dev")"
	out="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass "${label}: dev takes the newest prerelease"
		else fFail "${label}: dev should take v2.1.0-beta.1, got ${got}. Output: ${out}"
	fi
}

#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## package.bash's --out. It used to be handed straight to 'rm -rf', so a stray
## --out emptied whatever it named, before the build had produced anything to
## put there. A stub zig that fails is enough: the removal came first.

fCase_PackageOutDir(){
	local -r packager="${repoRoot}/cicd/utility/package.bash"
	if [[ ! -f "${packager}" ]]; then
		fLine "  skipped: package.bash is not present."
		return 0
	fi

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
	if [[ -f "${victim}/canary.txt" && -f "${victim}/subdir/other.txt" ]]
		then fPass "package: an --out it did not make is left alone"
		else fFail "package: --out was emptied. Output: ${out}"
	fi
	if [[ "${out}" == *"carries no"* ]]
		then fPass "package: and says why it refused"
		else fFail "package: refused without saying why. Output: ${out}"
	fi

	## An empty directory is nobody's work, so it gets adopted rather than refused.
	local -r fresh="${area}/fresh"
	mkdir -p "${fresh}"
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${fresh}" --version v0 2>&1)" || true
	if [[ "${out}" != *"carries no"* ]]
		then fPass "package: an empty --out is accepted"
		else fFail "package: an empty --out was refused. Output: ${out}"
	fi

	## And a path that does not exist yet, which is what dist/ is on a clean tree.
	out="$(PATH="${area}/bin:${PATH}" bash "${packager}" --out "${area}/brand-new" --version v0 2>&1)" || true
	if [[ "${out}" != *"carries no"* ]]
		then fPass "package: a new --out is accepted"
		else fFail "package: a new --out was refused. Output: ${out}"
	fi
}

## The .deb and .rpm shipped zuid.h with no library behind it, so anything that
## included it failed at the link step. Building a real package here would need
## nfpm and a full release build, so this reads the nfpm contents list instead:
## a header may only be in there if a library is too.

fCase_PackageHeader(){
	local -r packager="${repoRoot}/cicd/utility/package.bash"
	if [[ ! -f "${packager}" ]]; then
		fLine "  skipped: package.bash is not present."
		return 0
	fi

	## The heredoc that becomes nfpm.yaml, from its 'contents:' line to the EOF
	## that closes it.
	local -r contents="$(awk '/^\t\tcontents:/ { on = 1 } on { print } /^\tEOF$/ { on = 0 }' "${packager}")"
	if [[ -z "${contents}" ]]; then
		fLine "  skipped: no nfpm contents list found in package.bash."
		return 0
	fi

	if [[ "${contents}" != *"/usr/include"* || "${contents}" == *"libzuid.so"* ]]
		then fPass "package: the packages do not install a header with no library"
		else fFail "package: the nfpm contents list has /usr/include and no libzuid.so."
	fi
}

## With no target named, the choice has to come from whether the system location
## can be written, not whether it exists. install.ps1 tested existence, so a
## normal user on a box with /usr/local/bin - which is to say any box - got a
## system install that failed after the download, with no elevation path.
##
## Skipped where the system location happens to be writable, such as a run as
## root, since then system is the right answer and there is nothing to catch.
fCase_DefaultTarget(){  ## label, runner
	local -r label="$1" runner="$2"
	if [[ -w /usr/local/bin ]]; then
		fLine "  skipped: /usr/local/bin is writable here, so system is the right default."
		return 0
	fi

	local home="" out="" got=""
	home="$(fNewHome "${label}-default-target")"
	out="$("${runner}" "${home}" yes)" || true
	got="$(fInstalledVersion "${home}")"
	if [[ "${got}" == "2.0.0" ]]
		then fPass "${label}: an unwritable system location falls back to a user install"
		else fFail "${label}: should have installed under HOME, got ${got}. Output: ${out}"
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
	got="$(fInstalledVersion "${home}")"
	if [[ "${got}" != "2.0.0" ]]; then
		fFail "${label}: the first run did not install. Output: ${first}"
		return 0
	fi

	local -r before="$(fRequestCount)"
	second="$("${runner}" "${home}" user yes)" || true
	local -r after="$(fRequestCount)"

	if [[ "${after}" == "${before}" ]]
		then fPass "${label}: a re-run on the same version downloads nothing"
		else fFail "${label}: the re-run made $((after - before)) request(s). Output: ${second}"
	fi
	if [[ "${second}" == *"Already installed"* ]]
		then fPass "${label}: and says it is already installed"
		else fFail "${label}: said nothing about being already installed. Output: ${second}"
	fi

	## A different version still replaces it, so the check cannot be a blanket
	## refusal to do anything.
	second="$("${runner}" "${home}" user dev yes)" || true
	got="$(fInstalledVersion "${home}")"
	if [[ "${got}" == "2.1.0-beta.1" ]]
		then fPass "${label}: a different version still installs over it"
		else fFail "${label}: expected the beta to replace it, got ${got}. Output: ${second}"
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
		if ((rc != 0)) && [[ "${out}" == *"${flag}"* && "${out}" == *"needs a value"* ]]
			then fPass "bash: ${flag} with no value names the flag"
			else fFail "bash: ${flag} with no value gave rc=${rc} and '${out}'"
		fi
	done
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
	if [[ -f "${planted}" ]]
		then fPass "${label}: uninstall leaves a file it did not create"
		else fFail "${label}: uninstall deleted a file it did not create. Output: ${out}"
	fi
	if [[ "${out}" == *"not this installer's link"* ]]
		then fPass "${label}: and says it is keeping it"
		else fFail "${label}: said nothing about keeping it. Output: ${out}"
	fi

	## Installing over it does replace it - that is what an installer does - but
	## the plan has to name it rather than do it quietly.
	out="$("${runner}" "${home}" user yes)" || true
	if [[ "${out}" == *"is not this installer's link"* ]]
		then fPass "${label}: install names what it is overwriting"
		else fFail "${label}: overwrote it without saying so. Output: ${out}"
	fi

	## And once it is the installer's own link, uninstall does remove it.
	out="$("${runner}" "${home}" user uninstall yes)" || true
	if [[ ! -e "${planted}" ]]
		then fPass "${label}: uninstall removes its own link"
		else fFail "${label}: left its own link behind. Output: ${out}"
	fi
}

fEcho "Installers: against a local release listing on port ${port}"
fLine ""

if [[ "${only}" != "ps1" ]]; then
	fLine "install.bash"
	fCase_ReleaseChoice "bash" "fRunBash"
	fCase_DefaultTarget "bash" "fRunBash"
	fCase_Rerun "bash" "fRunBash"
	fCase_MissingValue
	fCase_ForeignLink "bash" "fRunBash"
fi

if [[ "${only}" != "bash" ]]; then
	fLine ""
	fLine "install.ps1"
	if ((! hasPwsh)); then
		fLine "  skipped: pwsh not installed."
	else
		fCase_ReleaseChoice "ps1" "fRunPs1"
		fCase_DefaultTarget "ps1" "fRunPs1"
		fCase_Rerun "ps1" "fRunPs1"
		fCase_ForeignLink "ps1" "fRunPs1"
	fi
fi

fLine ""
fLine "package.bash"
fCase_PackageOutDir
fCase_PackageHeader

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20260917 JC: Check what the deb and rpm contents list installs.
##		- 20260917 JC: Created, for the release-choice, re-run and link-path cases.
