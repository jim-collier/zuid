#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Checks cicd.bash's own argument handling and the two helpers that
##		stand between it and a bad commit. The arguments are driven through the
##		real script, with values it refuses before any stage runs, so nothing is
##		built or logged. The helpers are lifted out of the script by name and run
##		against a scratch repo. So are the publish preflight and stage, against
##		scratch repos pushing to a local bare remote, with gh stubbed out.
##		test-ids.py runs against a scratch tree, and the Zig fuzz stage's
##		report against a stand-in zig. So does package.bash, to see what
##		SOURCE_DATE_EPOCH it hands on. The profile report reads a made-up
##		flamegraph, the vuln report made-up govulncheck output, and the CodeQL
##		report made-up SARIF.
##	Syntax:
##		pipeline-test.bash
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

fEcho(){ printf '[ %s ]\n' "$*" ;}
fLine(){ printf '%s\n' "$*" ;}
fDie(){  printf '\n%s: %s\n\n' "pipeline-test" "$*" >&2; exit 1 ;}

## Every case names its test ID first, then what it checks. New IDs come from
## test-ids.py. A check written out by hand starts with fId instead.
passed=0
failed=0
curId=""
curName=""
fId(){ curId="$1"; curName="$2" ;}
fPass(){
	if [[ -z "${curId}" ]]; then fFail "no test ID"; return 0; fi
	passed=$((passed + 1)); printf '  ok ....: %s %s\n' "${curId}" "${curName}"
	curId=""
}
fFail(){  ## detail
	failed=$((failed + 1)); printf '  FAIL ..: %s %s: %s\n' "${curId:-???????}" "${curName}" "$*"
	curId=""
}

case "${1:-}" in
	-h|--help) sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	"") ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cicd="${repoRoot}/cicd/cicd.bash"
flameReport="${repoRoot}/cicd/utility/flame-report.py"
[[ -f "${cicd}" ]] || fDie "could not find cicd.bash from ${repoRoot}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Arguments. Each run is refused inside argument parsing, which is before the
## run log, the sync, or any stage.

fWantRefusal(){  ## id, label, text the refusal must contain, args...
	fId "$1" "$2"
	local -r needle="$3"; shift 3
	local out="" rc=0
	## A refusal that broke would start a real run. With no input and no quiet
	## mode, that stops at the commit message prompt instead.
	out="$(env -u ZUID_CICD_QUIET bash "${cicd}" "$@" 2>&1 < /dev/null)" || rc=$?
	if ((rc != 0)) && [[ "${out}" == *"${needle}"* ]]
		then fPass
		else fFail "exited ${rc} and said '${out:0:120}'"
	fi
}

fEcho "cicd.bash: ${cicd}"
fLine ""

## -h anywhere inside the joined arguments used to print help, so a commit
## message mentioning it got the help screen. The refusal of the bad --only
## after it is how this shows the message was taken as a message.
fWantRefusal ErOjF6y "-h inside a message is not a request for help"  "after --only" -m 'fix the -h case' --only nope

## --commit used to take an optional message, and swallowed whatever flag came
## next as one.
fWantRefusal ErOjF6z "--commit does not swallow the flag after it"    "after --only" --commit --only nope
fWantRefusal ErOjF70 "-m refuses a flag as its message"               "Expecting a value after -m" -m --quick
fWantRefusal ErOjF71 "--backup and --commit together are refused"     "--backup already commits" --backup --commit
## Retired 20261003: --publish is implemented now, so this refusal is gone on
## purpose. The publish cases below cover it instead.
# fWantRefusal ErOjF72 "--publish says it is not there yet"             "Not implemented yet" --publish
fWantRefusal ErOjF73 "an unknown argument is named"                   "'--bogus'" --bogus
fWantRefusal ErgqYt2 "--allow-partial without --publish is refused"   "only means something with --publish" --allow-partial
fWantRefusal ErgqYt3 "--publish with --only go is refused"            "--publish needs the Zig side" --publish --only go
fWantRefusal EsJ9SjI "--publish with --container is refused"          "does not go with --container" --publish --container
fWantRefusal EshGwj4 "--ci with --commit is refused"                  "--ci only builds and tests" --ci --commit
fWantRefusal EshGwj5 "--ci with --package is refused"                 "--ci only builds and tests" --ci --package
## --gate was renamed --ci with no alias. The bad --only after it keeps a
## build that still took --gate from starting a real run.
fWantRefusal Et6FB1m "--gate is gone, with no alias"                   "'--gate'" --gate --only nope
fWantRefusal Eshc39l "--publish with --no-package is refused"         "does not go with --no-package" --publish --no-package

fId EsJ9cHS "--container inside the container is refused"
out="$(env -u ZUID_CICD_QUIET ZUID_IN_CONTAINER=1 bash "${cicd}" --container 2>&1 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Already in the container"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out:0:120}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Helpers, lifted out of the script by name. One that has moved or been
## renamed fails here rather than being skipped.

fLoad(){  ## function name
	local -r body="$(sed -n "/^\(function \)\{0,1\}$1(){/,/^}/p" "${cicd}")"
	[[ -n "${body}" ]] || return 1
	eval "${body}"
}

## A prerelease of the floor version passed the floor, because only the
## release part was compared.
fId ErOjF74 "a prerelease of the floor version is below it"
if ! fLoad fVersion_AtLeast; then
	fFail "no fVersion_AtLeast in cicd.bash"
elif fVersion_AtLeast "0.16.0-dev.1+abc" "0.16.0"; then
	fFail "0.16.0-dev.1 passed a 0.16.0 floor"
else
	fPass
fi

fId ErOjF75 "a release at or past the floor passes, and nothing below it does"
versionBad=""
if declare -F fVersion_AtLeast >/dev/null; then
	for pair in "0.16.0 0.16.0 yes" "0.17.0-dev.3 0.16.0 yes" "1.26.2 1.24 yes" "1.24 1.24 yes" \
		"0.15.2 0.16.0 no" "1.23.9 1.24 no" " 0.16.0 no" "go1.26 1.24 no"; do
		read -r haveVer floorVer want <<< "${pair}"
		[[ -n "${want}" ]] || { want="${floorVer}"; floorVer="${haveVer}"; haveVer="" ;}
		got="no"
		if fVersion_AtLeast "${haveVer}" "${floorVer}"; then got="yes"; fi
		[[ "${got}" == "${want}" ]] || versionBad+=" '${haveVer}' against ${floorVer} gave ${got};"
	done
else
	versionBad=" no fVersion_AtLeast in cicd.bash"
fi
if [[ -z "${versionBad}" ]]
	then fPass
	else fFail "${versionBad}"
fi

## The commit stage refuses main and dev, and a detached HEAD. It runs against
## a scratch repo, with the output helpers stubbed and fThrowError ending the
## subshell the way it ends the script.
fCommitIn(){  ## repo dir
	(
		# shellcheck disable=2329  ## Called by the lifted fStage_Commit, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ :; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted fStage_Commit.
		{ repoRoot="$1"; protectedBranches=("main" "dev"); commitMsg="pipeline-test" ;}
		fLoad fStage_Commit || { printf 'no fStage_Commit in cicd.bash\n'; exit 2; }
		fStage_Commit
	) 2>&1
}

scratchRepo="${work}/repo"
git init -q -b main "${scratchRepo}"
git -C "${scratchRepo}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m first
echo change > "${scratchRepo}/file"

fId ErOjF76 "a commit on main is refused"
out="$(fCommitIn "${scratchRepo}" || true)"
if [[ "${out}" == *"Refusing to commit to 'main'"* && -z "$(git -C "${scratchRepo}" log --format=%h -1 --skip 1 2>/dev/null || true)" ]]
	then fPass
	else fFail "said '${out}'"
fi

fId ErOjF77 "a commit on a detached HEAD is refused"
git -C "${scratchRepo}" checkout -q --detach
out="$(fCommitIn "${scratchRepo}" || true)"
if [[ "${out}" == *"HEAD is detached"* ]]
	then fPass
	else fFail "said '${out}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A linked worktree, whose .git is a file. Sync and preflight used to test for
## a .git directory and refused one.

fGitCheckIn(){  ## repo dir, function names...
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ repoRoot="$1"; runStamp="pipeline-test"; buildJobs=1; doGo=0; doZig=0; doPublish=0 ;}
		shift
		local fn=""
		for fn in "$@"; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		for fn in "$@"; do "${fn}"; done
	) 2>&1
}

worktreeMain="${work}/wtmain"
worktreeDir="${work}/wt"
git init -q -b main "${worktreeMain}"
mkdir -p "${worktreeMain}/testdata"
: > "${worktreeMain}/testdata/vectors.tsv"
git -C "${worktreeMain}" add -A
git -C "${worktreeMain}" -c user.name=t -c user.email=t@t commit -q -m first
git -C "${worktreeMain}" worktree add -q -b side "${worktreeDir}" 2>/dev/null

fId Erm7vCh "the sync stage runs in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fStage_Sync)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Remote .....: none"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Erm7vCi "preflight runs in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fPreflight)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Branch .....: side"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Erm7vCj "sync and preflight still refuse a folder that is not a checkout's top"
notTopBad=""
for notTop in "${worktreeMain}/testdata" "${work}"; do
	for fn in fStage_Sync fPreflight; do
		out="$(fGitCheckIn "${notTop}" "${fn}")" && rc=0 || rc=$?
		if ((rc == 0)) || [[ "${out}" != *"Not a git repo"* ]]; then notTopBad+=" ${fn} in ${notTop##*/} exited ${rc}: '${out}';"; fi
	done
done
if [[ -z "${notTopBad}" ]]
	then fPass
	else fFail "${notTopBad}"
fi

## Run through a symlinked folder, the root kept the link's name, and a find
## started there listed only the link. The sync refusal names the root.
fId ErqU8vW "the repo root is the real folder when cicd.bash is run through a symlink"
mkdir -p "${work}/linked/real/cicd"
cp "${cicd}" "${work}/linked/real/cicd/"
ln -s real "${work}/linked/link"
out="$(cd "${work}/linked" && env -u ZUID_CICD_QUIET bash link/cicd/cicd.bash -q --no-backup --no-dogfood 2>&1 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Not a git repo: '$(cd "${work}/linked/real" && pwd -P)'"* ]]
	then fPass
	else fFail "exited ${rc} and said '$(grep -m1 'Not a git repo' <<< "${out}" || true)'"
fi

## The backup helper archives the folder above the checkout, which for a
## worktree is not the project, so the default backup steps aside there.
fInitIn(){  ## repo dir, args...
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted fInit.
		{
			repoRoot="$1"; onlyToolchain=""; commitMsg=""; doQuietly=0
			doCross=0; doQuick=0; doSync=1; doCommit=0; commitAsked=0; doPush=0; doPackage=0; noPackage=0; packageSkipWhy=""
			doBackup=1; backupAsked=0; backupInWorktree=0; doDogfood=1; dogfoodAsked=0; doPublish=0; allowPartial=0
			doContainer=0; inContainer=0; doCi=0; doLeakcheck=0
		}
		shift
		local fn=""
		for fn in fMustBeAValue fPackageBlocker fInit; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2030  ## Only this subshell's PATH, on purpose.
		if [[ -n "${fakePath:-}" ]]; then PATH="${fakePath}"; fi
		fInit "$@"
		if [[ "${showCross:-0}" == "1" ]]; then
			printf 'doCross=%s\n' "${doCross}"
		elif [[ "${showLeak:-0}" == "1" ]]; then
			printf 'doLeakcheck=%s\n' "${doLeakcheck}"
		elif [[ "${showGate:-0}" == "1" ]]; then
			printf 'doQuick=%s doSync=%s doBackup=%s doDogfood=%s doPackage=%s\n' "${doQuick}" "${doSync}" "${doBackup}" "${doDogfood}" "${doPackage}"
		elif [[ "${showPackage:-0}" == "1" ]]; then
			printf 'doPackage=%s skip=%s\n' "${doPackage}" "${packageSkipWhy}"
		else
			printf 'doBackup=%s backupInWorktree=%s\n' "${doBackup}" "${backupInWorktree}"
		fi
	) 2>&1
}

fId Erm7vCk "the default backup steps aside in a linked worktree, and not in the main checkout"
outWorktree="$(fInitIn "${worktreeDir}")" && rc=0 || rc=$?
outMain="$(fInitIn "${worktreeMain}")" || rc=$?
if ((rc == 0)) && [[ "${outWorktree}" == "doBackup=0 backupInWorktree=1" ]] && [[ "${outMain}" == "doBackup=1 backupInWorktree=0" ]]
	then fPass
	else fFail "exited ${rc}, worktree said '${outWorktree}', main checkout said '${outMain}'"
fi

fId Erm7vCl "--backup by name is refused in a linked worktree"
out="$(fInitIn "${worktreeDir}" --backup)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"linked worktree"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The pre-push hook runs --ci inside a push, so it must not sync, install,
## or push again.
fId EshGwj6 "--ci is a quick run with no sync, dogfood, or backup"
out="$(showGate=1 fInitIn "${worktreeMain}" --ci)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doQuick=1 doSync=0 doBackup=0 doDogfood=0 doPackage=0" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The Go cross builds are seconds, so a quick run and the pre-push one get
## them as well as a full run.
fId Et6FB1n "a plain run, --quick and --ci all cross-compile"
out="$(showCross=1 fInitIn "${worktreeMain}"; showCross=1 fInitIn "${worktreeMain}" --quick; showCross=1 fInitIn "${worktreeMain}" --ci)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doCross=1\ndoCross=1\ndoCross=1' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## The leak checks take a minute and a half, so only asking for them runs
## them. Asked for, they ride along with any run, the pre-push one included.
fId EtAUMRF "--leakcheck is off for a plain run, --quick and --ci, and on with each"
out="$(for leakArgs in "" --quick --ci; do
	# shellcheck disable=2086  ## Empty means no argument at all.
	showLeak=1 fInitIn "${worktreeMain}" ${leakArgs}
	# shellcheck disable=2086
	showLeak=1 fInitIn "${worktreeMain}" ${leakArgs} --leakcheck
done)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doLeakcheck=0\ndoLeakcheck=1\ndoLeakcheck=0\ndoLeakcheck=1\ndoLeakcheck=0\ndoLeakcheck=1' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId EtAUMRH "--help names --leakcheck, and says a plain run leaves it out"
out="$(bash "${cicd}" --help 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"--leakcheck       Add the slow leak checks"* ]] && [[ "${out}" == *"every stage but --publish and --leakcheck"* ]]
	then fPass
	else fFail "exited ${rc}, and the help has no --leakcheck line or plain-run note"
fi

## A full run packages where --package is known to work: Linux x86_64 or a Mac,
## with llvm-objcopy for the Linux strip. Elsewhere it says why and goes on.
## The host is a stand-in uname, on a PATH that has only it, git, and maybe a
## stand-in llvm-objcopy.
fakeHost="${work}/fake-host"
mkdir -p "${fakeHost}/with" "${fakeHost}/without"
for fakeDir in "${fakeHost}/with" "${fakeHost}/without"; do
	ln -s "$(command -v git)" "${fakeDir}/git"
	# shellcheck disable=2016  ## The stand-in's own text.
	printf '#!/bin/sh\ncase "$1" in -s) echo "${FAKE_OS}" ;; -m) echo "${FAKE_ARCH}" ;; esac\n' > "${fakeDir}/uname"
	chmod +x "${fakeDir}/uname"
done
printf '#!/bin/sh\n' > "${fakeHost}/with/llvm-objcopy"
chmod +x "${fakeHost}/with/llvm-objcopy"
fPackageIn(){  ## os, arch, with|without, args...
	local -r os="$1" arch="$2" kit="$3"; shift 3
	FAKE_OS="${os}" FAKE_ARCH="${arch}" fakePath="${fakeHost}/${kit}" showPackage=1 fInitIn "${worktreeMain}" "$@"
}

fId EshbzZU "a full run on Linux x86_64 with llvm-objcopy packages"
out="$(fPackageIn Linux x86_64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZV "without llvm-objcopy it doesn't, and says why"
out="$(fPackageIn Linux x86_64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip=no llvm-objcopy"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZW "a full run on a Mac packages"
out="$(fPackageIn Darwin arm64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZX "a full run anywhere else doesn't, and says --package asks anyway"
out="$(fPackageIn FreeBSD amd64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip="*"--package"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZY "--quick, --no-package and --only go each turn the default off"
out="$(fPackageIn Linux x86_64 with --quick; fPackageIn Linux x86_64 with --no-package; fPackageIn Linux x86_64 with --only go)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doPackage=0 skip=\ndoPackage=0 skip=\ndoPackage=0 skip=' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId Eshc39k "--package still asks on a quick run, and where the default wouldn't"
out="$(fPackageIn Linux x86_64 with --quick --package; fPackageIn FreeBSD amd64 without --package)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doPackage=1 skip=\ndoPackage=1 skip=' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## Dogfood. Packaged release files go each to their own platform's dir, over
## what's there, and a missing dir is passed over. Unpackaged, zig-out's command
## goes to the first fallback that exists.
fDogfoodIn(){  ## root, doPackage
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2034  ## Read by the lifted fStage_Dogfood.
		{
			repoRoot="$1/repo"; zigDir="$1/repo/zig"; doPackage="$2"
			distPrefix="zuid-1.2.3-"
			dogfoodSynced=("linux-x86_64|zuid|$1/linux" "windows-x86_64.exe|zuid.exe|$1/mswin" "darwin-universal|zuid|$1/macos")
			dogfoodDirs=("$1/nope" "$1/fallback")
		}
		local fn=""
		for fn in fDogfoodCopy fStage_Dogfood; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fStage_Dogfood
	) 2>&1
}
dogRoot="${work}/dogfood"
mkdir -p "${dogRoot}/repo/dist" "${dogRoot}/repo/zig/zig-out/bin" "${dogRoot}/linux" "${dogRoot}/mswin" "${dogRoot}/fallback"
echo linux-release > "${dogRoot}/repo/dist/zuid-1.2.3-linux-x86_64"
echo windows-release > "${dogRoot}/repo/dist/zuid-1.2.3-windows-x86_64.exe"
## Another version's file left in dist/ is not this run's.
echo old-release > "${dogRoot}/repo/dist/zuid-1.2.2-linux-x86_64"
echo zig-out > "${dogRoot}/repo/zig/zig-out/bin/zuid"
chmod +x "${dogRoot}/repo/zig/zig-out/bin/zuid"
echo stale > "${dogRoot}/linux/zuid"

fId EshcCTw "packaged release files go to their platform's synced dir, over what's there"
out="$(fDogfoodIn "${dogRoot}" 1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "$(cat "${dogRoot}/linux/zuid" 2>/dev/null)" == "linux-release" && "$(cat "${dogRoot}/mswin/zuid.exe" 2>/dev/null)" == "windows-release" ]] \
	&& [[ ! -e "${dogRoot}/macos" && ! -e "${dogRoot}/fallback/zuid" && "$(ls "${dogRoot}/linux")" == "zuid" ]]
	then fPass
	else fFail "exited ${rc}, said '${out//$'\n'/ | }'"
fi

fId EshcCTx "with nothing packaged, zig-out's command goes to the first fallback that exists"
out="$(fDogfoodIn "${dogRoot}" 0)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "$(cat "${dogRoot}/fallback/zuid" 2>/dev/null)" == "zig-out" && "$(cat "${dogRoot}/linux/zuid")" == "linux-release" ]]
	then fPass
	else fFail "exited ${rc}, said '${out//$'\n'/ | }'"
fi

## The container stage, with a stand-in for docker that logs what it was asked.
## Its image list always has an older tag beside the current one.
cat > "${work}/engine" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ENGINE_LOG}"
case "$1 ${2:-}" in
	"image inspect") [[ -f "${ENGINE_LOG}.built-${3//[:\/]/_}" ]] ;;
	"build "*)       while (($#)) && [[ "$1" != "-t" ]]; do shift; done; : > "${ENGINE_LOG}.built-${2//[:\/]/_}" ;;
	"image ls")      if [[ "$3" == "zuid-codeql" ]]
		then printf 'zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld\n%s\n' "${ENGINE_NEW_CODEQL:-}"
		else printf 'zuid-cicd:0ld0ld0ld0ld\n%s\n' "${ENGINE_NEW}"
		fi ;;
	"run "*)         exit "${ENGINE_RUN_RC:-0}" ;;
	"info "*)        exit "${ENGINE_INFO_RC:-0}" ;;
esac
STUB
chmod +x "${work}/engine"

fContainerIn(){  ## repo dir, engine log, run exit code
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted fStage_Container.
		{
			repoRoot="$(cd "$1" && pwd -P)"; containerImage="zuid-cicd"; containerVolume="zuid-cicd-cache"; codeqlImage="zuid-codeql"
			onlyToolchain="go"; doQuick=1; doPackage=1; doLeakcheck="${leakcheck:-0}"; runStamp="20261019-101112"
		}
		local fn=""
		for fn in _fMustBeInPath fStage_Container fContainer_Image fCodeql_Image fContainer_DropOthers fContainer_RunArgs; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		mkdir -p "${repoRoot}/cicd/container/codeql"
		echo "FROM scratch" > "${repoRoot}/cicd/container/Dockerfile"
		echo "FROM codeql" > "${repoRoot}/cicd/container/codeql/Dockerfile"
		# shellcheck disable=2030  ## Each case sets its own.
		export ZUID_DOCKER="${work}/engine" ENGINE_LOG="$2" ENGINE_RUN_RC="$3"
		ENGINE_NEW="zuid-cicd:$(git hash-object "${repoRoot}/cicd/container/Dockerfile" | cut -c1-12)"
		ENGINE_NEW_CODEQL="zuid-codeql:$(git hash-object "${repoRoot}/cicd/container/codeql/Dockerfile" | cut -c1-12)-${ENGINE_NEW#*:}"
		export ENGINE_NEW ENGINE_NEW_CODEQL
		# shellcheck disable=2034  ## Read by the lifted fContainer_Image.
		containerEngine="${ZUID_DOCKER}" containerTag="" codeqlTag=""
		fStage_Container
	) 2>&1
}
mainReal="$(cd "${worktreeMain}" && pwd -P)"
newTag="zuid-cicd:$(echo "FROM scratch" | git hash-object --stdin | cut -c1-12)"

fId EsJ9SjE "--container builds a missing image under the recipe's hash, and drops the one it replaces"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-main" 2>/dev/null || true)"
if ((rc == 0)) && grep -qxF "build -t ${newTag} ${mainReal}/cicd/container" <<< "${log}" \
	&& grep -qxF "rmi zuid-cicd:0ld0ld0ld0ld" <<< "${log}" && ! grep -qxF "rmi ${newTag}" <<< "${log}"
	then fPass
	else fFail "exited ${rc}, asked: ${log//$'\n'/ | }; said '${out}'"
fi

fId EsJ9SjF "the container gets the repo at its own path, the cache volume and the inner flags, and no rebuild"
: > "${work}/engine-main"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-main")"
wantRun="run --rm --init --user $(id -u):$(id -g) -v ${mainReal}:${mainReal} -v zuid-cicd-cache:/cache -e ZUID_IN_CONTAINER=1 -e USER=${USER:-builder} -e ZUID_RUN_STAMP=20261019-101112"
wantRun+=" -w ${mainReal} ${newTag} bash ${mainReal}/cicd/cicd.bash -q --no-sync --no-backup --no-dogfood --only go --quick --package"
if ((rc == 0)) && grep -qxF -- "${wantRun}" <<< "${log}" && ! grep -q '^build ' <<< "${log}"
	then fPass
	else fFail "exited ${rc}, asked: ${log//$'\n'/ | }"
fi

fId EsJ9SjG "a linked worktree's container gets the main checkout's git dir too"
out="$(fContainerIn "${worktreeDir}" "${work}/engine-wt" 0)" && rc=0 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* -v ${mainReal}/.git:${mainReal}/.git " "${work}/engine-wt"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-wt" || true)"
fi

fId EsJ9SjH "a failed run in the container fails the stage"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 3)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"The run in the container failed"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The run inside is a new cicd.bash, which only knows what it's handed.
fId EtAUMRG "--container hands --leakcheck to the run inside"
: > "${work}/engine-main"
out="$(leakcheck=1 fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* --only go --quick --package --leakcheck$" "${work}/engine-main"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-main" || true)"
fi

## The image has no time zone, so the run inside stamped its files in UTC and
## they sorted hours away from the host's.
fId EtB0hIu "the run in the container names its files with the stamp of the run outside"
: > "${work}/engine-main"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
stampBad=""
grep -q -- "^run .* -e ZUID_RUN_STAMP=20261019-101112 .* bash " "${work}/engine-main" || stampBad+=" the stamp wasn't handed in;"
stampOut="$(
	if ! fLoad fRunStamp; then echo "no fRunStamp in cicd.bash"; exit 0; fi
	# shellcheck disable=2034  ## Read by the lifted fRunStamp.
	inContainer=1
	printf 'in=%s\n' "$(ZUID_RUN_STAMP=20261019-101112 fRunStamp)"
	printf 'junk=%s\n' "$(ZUID_RUN_STAMP='20261019-101112;x' fRunStamp)"
	# shellcheck disable=2034
	inContainer=0
	printf 'host=%s\n' "$(ZUID_RUN_STAMP=20261019-101112 fRunStamp)"
)"
grep -qxF "in=20261019-101112" <<< "${stampOut}" || stampBad+=" inside, it didn't take the stamp;"
if ! grep -qE '^junk=[0-9]{8}-[0-9]{6}$' <<< "${stampOut}" || grep -q '^junk=20261019-101112' <<< "${stampOut}"; then
	stampBad+=" inside, it took a malformed stamp;"
fi
if ! grep -qE '^host=[0-9]{8}-[0-9]{6}$' <<< "${stampOut}" || grep -q '^host=20261019-101112' <<< "${stampOut}"; then
	stampBad+=" on the host, it took one from the environment;"
fi
if ((rc == 0)) && [[ -z "${stampBad}" ]]
	then fPass
	else fFail "exited ${rc},${stampBad} asked: $(grep '^run ' "${work}/engine-main" || true); said: ${stampOut//$'\n'/ | }"
fi

## CodeQL is about 480 MB, so a run that doesn't want it never builds it.
fId EtAj5P2 "--container --leakcheck builds CodeQL's image on the main one and runs in it, and a plain --container run never touches it"
codeqlTag="zuid-codeql:$(echo "FROM codeql" | git hash-object --stdin | cut -c1-12)-${newTag#*:}"
out="$(leakcheck=1 fContainerIn "${worktreeMain}" "${work}/engine-codeql" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-codeql" 2>/dev/null || true)"
plainOut="$(fContainerIn "${worktreeMain}" "${work}/engine-plain" 0)" && plainRc=0 || plainRc=$?
if ((rc == 0)) && grep -qxF "build --build-arg BASE=${newTag} -t ${codeqlTag} ${mainReal}/cicd/container/codeql" <<< "${log}" \
	&& grep -q -- "^run .* ${codeqlTag} bash .* --leakcheck$" <<< "${log}" && grep -qxF "rmi zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld" <<< "${log}" \
	&& ! grep -qxF "rmi ${codeqlTag}" <<< "${log}" && ((plainRc == 0)) && ! grep -q 'codeql' "${work}/engine-plain"
	then fPass
	else fFail "exited ${rc} and ${plainRc}, asked: ${log//$'\n'/ | }; said '${out}' and '${plainOut}'"
fi

## A public clone without docker still passes, so the checkers in the image
## skip rather than fail when there's nothing to run them in.
fId Et9VtIq "the Go checkers skip with a reason when docker is missing or not answering, and use the image when it answers"
out="$(
	# shellcheck disable=2329  ## Called by the lifted functions, not here.
	fEcho_Clean(){ :; }
	# shellcheck disable=2329
	fThrowError(){ printf '%s\n' "$1"; exit 1; }
	# shellcheck disable=2329
	uname(){ case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerImage="zuid-cicd"; inContainer=0; containerTag=""; checkerSkipWhy=""
	}
	for fn in _fMustBeInPath fGoCheckers_Ready fContainer_Image fContainer_DropOthers; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2031  ## The stub reads it; the earlier subshell's copy is gone.
	export ENGINE_LOG="${work}/engine-checkers"
	# shellcheck disable=2034  ## Read by the lifted functions.
	containerEngine="${work}/no-such-engine"
	fGoCheckers_Ready; printf 'missing=%s\n' "${checkerSkipWhy}"
	# shellcheck disable=2034
	containerEngine="${work}/engine"
	export ENGINE_INFO_RC=1
	fGoCheckers_Ready; printf 'silent=%s\n' "${checkerSkipWhy}"
	export ENGINE_INFO_RC=0
	fGoCheckers_Ready; printf 'ready=%s tag=%s\n' "${checkerSkipWhy}" "${containerTag}"
)" && rc=0 || rc=$?
if ((rc == 0)) && grep -qxF "missing=no ${work}/no-such-engine to run the pinned checkers in" <<< "${out}" \
	&& grep -qxF "silent=${work}/engine isn't answering" <<< "${out}" && grep -qxF "ready= tag=${newTag}" <<< "${out}"
	then fPass
	else fFail "exited ${rc} and said: ${out//$'\n'/ | }"
fi

## The C sanitizer builds go to a scratch dir outside the repo, which the
## image only sees if it's mounted.
fId EtAHpAi "a checker run in a folder outside the repo gets that folder mounted at its own path, and one inside gets no extra mount"
out="$(
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerVolume="zuid-cicd-cache"; inContainer=0
		containerTag="zuid-cicd:t3st"; containerEngine="${work}/engine"
	}
	for fn in fInImage fContainer_RunArgs; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	mkdir -p "${work}/outside"
	ENGINE_LOG="${work}/engine-inimage" fInImage "${work}/outside" true
	ENGINE_LOG="${work}/engine-inimage" fInImage "${repoRoot}/go" true
)" && rc=0 || rc=$?
log="$(cat "${work}/engine-inimage" 2>/dev/null || true)"
if ((rc == 0)) && [[ "$(grep -c '^run ' <<< "${log}")" == "2" ]] \
	&& grep -qF -- "-v ${work}/outside:${work}/outside -w ${work}/outside zuid-cicd:t3st true" <<< "${log}" \
	&& grep -- "-w ${mainReal}/go " <<< "${log}" | grep -qvF -- "-v ${mainReal}/go:"
	then fPass
	else fFail "exited ${rc}, said '${out}', asked: ${log//$'\n'/ | }"
fi

git -C "${worktreeMain}" worktree remove --force "${worktreeDir}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Publishing, against scratch repos that push to a local bare remote, with gh
## replaced by a stub that logs what it was asked. Nothing reaches GitHub. The
## preflight and the stage are lifted out by name, with fConfig for the branch
## and the list of release assets.

stubBin="${work}/bin"
mkdir -p "${stubBin}"
cat > "${stubBin}/gh" <<'EOF_gh'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
	"auth status")    exit 0 ;;
	"repo view")      [[ -z "${GH_STUB_NO_REPO:-}" ]] || exit 1; printf 'https://github.com/example/zuid\n'; exit 0 ;;
	"release create") shift 2; printf '%s\0' "$@" > "${GH_STUB_LOG:?}"; exit 0 ;;
	"release view")   printf 'file://%s\n' "${GH_STUB_SERVED:?}"; exit 0 ;;
esac
printf 'gh stub: not expected: %s\n' "$*" >&2
exit 1
EOF_gh
chmod +x "${stubBin}/gh"
export ZUID_GH="${stubBin}/gh"
# shellcheck disable=2031  ## The fake PATH above was only in a subshell.
export PATH="${stubBin}:${PATH}"

## A tarball whose top directory has the version in its name, the way package.bash
## names it.
fTarball(){  ## path, version
	local -r tree="${work}/tgz-$$-${RANDOM}"
	mkdir -p "${tree}/zuid-v$2/bin"
	printf 'zuid %s\n' "$2" > "${tree}/zuid-v$2/bin/zuid"
	tar -C "${tree}" -czf "$1" "zuid-v$2"
	rm -rf "${tree}"
}

## A repo on main, pushed, with this machine's dist/ and the other machines'
## files in dist-incoming/: every release target, plus a package with '~' in
## its name.
fPublishRepo(){  ## name, version
	local -r dir="${work}/$1" version="$2"
	git init -q --bare "${dir}/remote.git"
	git init -q -b main "${dir}/repo"
	git -C "${dir}/repo" config user.name t
	git -C "${dir}/repo" config user.email t@t
	mkdir -p "${dir}/repo/zig/lib/src" "${dir}/repo/dist" "${dir}/repo/dist-incoming"
	printf 'pub const version = "%s";\n' "${version}" > "${dir}/repo/zig/lib/src/core.zig"
	printf '/dist/\n/dist-incoming/\n' > "${dir}/repo/.gitignore"
	printf '# Changelog\n\n## v%s - 2026-10-03\n\n- Notes for this one.\n\n## v0.9.0 - 2026-01-01\n\n- Notes for an older one.\n' "${version}" > "${dir}/repo/changelog.md"
	git -C "${dir}/repo" add -A
	git -C "${dir}/repo" commit -q -m first
	git -C "${dir}/repo" remote add origin "${dir}/remote.git"
	git -C "${dir}/repo" push -q -u origin main 2>/dev/null
	fTarball "${dir}/repo/dist/zuid-${version}-linux-x86_64.tgz" "${version}"
	fTarball "${dir}/repo/dist/zuid-${version}-linux-arm64.tgz" "${version}"
	fTarball "${dir}/repo/dist/zuid-${version}-freebsd-x86_64.tgz" "${version}"
	## Answers --version the way the real one does, for the notes' build line.
	printf '#!/bin/sh\necho "%s (build abc12)"\n' "${version}" > "${dir}/repo/dist/zuid-${version}-linux-x86_64"
	chmod +x "${dir}/repo/dist/zuid-${version}-linux-x86_64"
	printf 'arm64\n'  > "${dir}/repo/dist/zuid-${version}-linux-arm64"
	printf 'freebsd\n' > "${dir}/repo/dist/zuid-${version}-freebsd-x86_64"
	printf 'stale\n'  > "${dir}/repo/dist/checksums.txt"
	: > "${dir}/repo/dist/.zuid-package-dir"
	## What package.bash stripped out, which stays here.
	mkdir -p "${dir}/repo/dist/debug/zuid-${version}-linux-x86_64/bin"
	printf 'debug\n' > "${dir}/repo/dist/debug/zuid-${version}-linux-x86_64/bin/zuid.debug"
	printf 'pdb\n'   > "${dir}/repo/dist/debug/zuid.pdb"
	fTarball "${dir}/repo/dist-incoming/zuid-${version}-darwin-universal.tgz" "${version}"
	printf 'universal\n' > "${dir}/repo/dist-incoming/zuid-${version}-darwin-universal"
	printf 'zip x86_64\n' > "${dir}/repo/dist-incoming/zuid-${version}-windows-x86_64.zip"
	printf 'zip arm64\n'  > "${dir}/repo/dist-incoming/zuid-${version}-windows-arm64.zip"
	printf 'deb\n' > "${dir}/repo/dist-incoming/zuid_${version//-/\~}_amd64.deb"
	printf 'mac sums\n' > "${dir}/repo/dist-incoming/checksums.txt"
}

## Runs the preflight and the stage in a subshell, the way a --publish run
## reaches them. Standard input is the answer to the prompt.
fPublishIn(){  ## name, quiet, allow partial
	local -r dir="${work}/$1"
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		local fn=""
		for fn in fConfig _fMustBeInPath fGh fCoreVersion fPublish_Preflight fPublish_Downloads fStage_Publish; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fConfig
		# shellcheck disable=2034,2154  ## Read by the lifted functions. The defaults come from the lifted fConfig.
		{
			repoRoot="${dir}/repo"; zigDir="${dir}/repo/zig"; incomingDir="${dir}/repo/dist-incoming"
			releaseBranch="${default_releaseBranch}"; releaseAssets=("${default_releaseAssets[@]}")
			distPrefix="zuid-$(fCoreVersion)-"
			doQuietly="$2"; allowPartial="$3"
			publishVersion=""; publishRemote=""; publishHead=""; publishRepoUrl=""
		}
		export GH_STUB_LOG="${dir}/gh-create" GH_STUB_SERVED="${dir}/repo/dist/release/checksums.txt"
		fPublish_Preflight
		fStage_Publish
	) 2>&1
}

## Tags on the remote, as name -> commit, one per line.
fRemoteTags(){ git -C "$1" ls-remote --tags "$1/../remote.git" | awk '$2 ~ /\^\{\}$/ { sub(/\^\{\}$/, "", $2); sub(/^refs\/tags\//, "", $2); print $2, $1 }' | sort ;}

## Every case that is refused has to leave no tag anywhere and no release.
fNothingPublished(){  ## name
	local -r dir="${work}/$1"
	[[ -z "$(git -C "${dir}/repo" tag -l)" ]] && [[ -z "$(git -C "${dir}/repo" ls-remote --tags origin)" ]] && [[ ! -e "${dir}/gh-create" ]]
}

fWantPublishRefusal(){  ## id, label, scratch name, text the refusal must contain, quiet, allow partial
	fId "$1" "$2"
	local out="" rc=0
	out="$(fPublishIn "$3" "$5" "$6" < /dev/null)" || rc=$?
	if ((rc == 0)) || [[ "${out}" != *"$4"* ]]; then
		fFail "exited ${rc} and said '${out: -160}'"
	elif ! fNothingPublished "$3"; then
		fFail "refused, but something was tagged or released"
	else
		fPass
	fi
}

fPublishRepo offmain 1.0.0-beta.1
git -C "${work}/offmain/repo" checkout -q -b feature
fWantPublishRefusal ErgqYt4 "--publish is refused off main" offmain "come from 'main' only" 1 0

fPublishRepo dirty 1.0.0-beta.1
printf 'edit\n' > "${work}/dirty/repo/stray.txt"
fWantPublishRefusal ErgqYt5 "--publish is refused on a dirty tree" dirty "uncommitted changes" 1 0

fPublishRepo unpushed 1.0.0-beta.1
git -C "${work}/unpushed/repo" commit -q --allow-empty -m second
fWantPublishRefusal ErgqYt6 "--publish is refused with HEAD not pushed" unpushed "HEAD is not what origin/main has" 1 0

## On the remote only, so the remote is what is asked.
fPublishRepo tagged 1.0.0-beta.1
git -C "${work}/tagged/repo" tag v1.0.0-beta.1
git -C "${work}/tagged/repo" push -q origin v1.0.0-beta.1 2>/dev/null
git -C "${work}/tagged/repo" tag -d v1.0.0-beta.1 >/dev/null
fId ErgqYt7 "--publish is refused when the version's tag is on the remote"
out="$(fPublishIn tagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/tagged/gh-create" ]] && [[ -z "$(git -C "${work}/tagged/repo" tag -l)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo gotagged 1.0.0-beta.1
git -C "${work}/gotagged/repo" tag go/v1.0.0-beta.1
fId ErgqYt8 "--publish is refused when the go/ tag exists here"
out="$(fPublishIn gotagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag go/v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/gotagged/gh-create" ]] && [[ -z "$(git -C "${work}/gotagged/repo" ls-remote --tags origin)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo partial 1.0.0-beta.1
rm -f "${work}/partial/repo/dist-incoming/"zuid-1.0.0-beta.1-windows-*.zip
fWantPublishRefusal ErgqYt9 "a set missing a platform is refused without --allow-partial" partial "No asset for: zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-arm64.zip" 1 0

fId ErgqYtA "--allow-partial publishes the rest and names what is missing"
rm -rf "${work}/partial/repo/dist/release"
out="$(fPublishIn partial 1 1 < /dev/null)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Missing ....: zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-arm64.zip"* ]] && [[ -e "${work}/partial/gh-create" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

## The installers once took no answer as a yes. Here no answer, an empty one
## and a plain 'n' all have to stop it.
fPublishRepo unanswered 1.0.0-beta.1
fId ErgqYtB "no answer to the prompt means no"
unansweredBad=""
for answer in "" $'\n' $'n\n'; do
	rm -rf "${work}/unanswered/repo/dist/release"
	out="$(printf '%s' "${answer}" | fPublishIn unanswered 0 0)" && rc=0 || rc=$?
	if ((rc == 0)) || [[ "${out}" != *"Not published"* ]] || ! fNothingPublished unanswered; then
		unansweredBad+=" answer '${answer//$'\n'/\\n}' exited ${rc};"
	fi
done
if [[ -z "${unansweredBad}" ]]
	then fPass
	else fFail "${unansweredBad}"
fi

fStaleTarball(){
	fPublishRepo stale 1.0.0-beta.1
	fTarball "${work}/stale/repo/dist-incoming/zuid-1.0.0-beta.1-darwin-universal.tgz" 1.0.0-alpha.1
}
fStaleTarball
fWantPublishRefusal ErgqYtH "a copied-in tarball from another version is refused" stale "built from another version" 1 0

## A remote gh cannot match to a GitHub repo, so the notes would have no
## links. The tags must not go out first.
fPublishRepo norepo 1.0.0-beta.1
export GH_STUB_NO_REPO=1
fWantPublishRefusal ErmAuec "--publish is refused when gh cannot name the repo" norepo "gh cannot tell which GitHub repo this is" 1 0
unset GH_STUB_NO_REPO

## One full run, answered yes, for the cases after it to read.
fPublishRepo beta 1.0.0-beta.1
betaOut="$(printf 'y\n' | fPublishIn beta 0 0)" && betaRc=0 || betaRc=$?
betaArgs=()
if [[ -e "${work}/beta/gh-create" ]]; then mapfile -d '' -t betaArgs < "${work}/beta/gh-create"; fi
## The uploads are the arguments that are files.
betaUploads=()
for arg in "${betaArgs[@]}"; do
	if [[ -f "${arg}" ]]; then betaUploads+=("${arg}"); fi
done

fId ErgqYtC "a version with a '-' is released as a prerelease"
if ((betaRc == 0)) && [[ " ${betaArgs[*]} " == *" --prerelease "* ]] && [[ "${betaArgs[0]:-}" == "v1.0.0-beta.1" ]]
	then fPass
	else fFail "exited ${betaRc}, gh got '${betaArgs[*]:0:6}', said '${betaOut: -160}'"
fi

fId ErgqYtE "both tags are pushed, on HEAD"
betaHead="$(git -C "${work}/beta/repo" rev-parse HEAD)"
if [[ "$(fRemoteTags "${work}/beta/repo")" == "go/v1.0.0-beta.1 ${betaHead}"$'\n'"v1.0.0-beta.1 ${betaHead}" ]]
	then fPass
	else fFail "the remote has: $(fRemoteTags "${work}/beta/repo" | tr '\n' ';')"
fi

## GitHub lists a bare tag beside the releases, so its message says what it is.
fId EsjRmx6 "the go/ tag's message names the release it goes with"
betaGoMsg="$(git -C "${work}/beta/repo" tag -l --format='%(contents:subject)' go/v1.0.0-beta.1)"
if [[ "${betaGoMsg}" == "Go module tag for v1.0.0-beta.1" ]]
	then fPass
	else fFail "its message is '${betaGoMsg}'"
fi

## Exactly one checksums.txt, listing every other upload once with the right
## hash, and nothing else.
fId ErgqYtF "one checksums.txt covers every asset"
sumsFile="" sumsBad=""
for arg in "${betaUploads[@]}"; do
	if [[ "$(basename "${arg}")" == checksums.txt ]]; then
		[[ -z "${sumsFile}" ]] || sumsBad+=" more than one checksums.txt;"
		sumsFile="${arg}"
	fi
done
if [[ -z "${sumsFile}" ]]; then
	sumsBad+=" no checksums.txt uploaded;"
else
	for arg in "${betaUploads[@]}"; do
		[[ "${arg}" != "${sumsFile}" ]] || continue
		[[ "$(awk -v n="$(basename "${arg}")" '$2 == n' "${sumsFile}" | wc -l)" -eq 1 ]] || sumsBad+=" $(basename "${arg}") not listed once;"
	done
	[[ "$(wc -l < "${sumsFile}")" -eq $((${#betaUploads[@]} - 1)) ]] || sumsBad+=" $(wc -l < "${sumsFile}") lines for $((${#betaUploads[@]} - 1)) assets;"
	(cd "$(dirname "${sumsFile}")" && sha256sum --quiet -c checksums.txt >/dev/null 2>&1) || sumsBad+=" a hash does not match;"
fi
## Six targets, four bare binaries, the package and checksums.txt.
((${#betaUploads[@]} == 12)) || sumsBad+=" ${#betaUploads[@]} uploads, expected 12;"
if [[ -z "${sumsBad}" ]]
	then fPass
	else fFail "${sumsBad}"
fi

fId ErgqYtG "'~' in an asset name is uploaded and listed as '.'"
tildeBad=""
for arg in "${betaUploads[@]}"; do
	[[ "$(basename "${arg}")" != *'~'* ]] || tildeBad+=" uploaded $(basename "${arg}");"
done
[[ -n "${sumsFile}" ]] && grep -q ' zuid_1.0.0.beta.1_amd64.deb$' "${sumsFile}" || tildeBad+=" checksums.txt does not list zuid_1.0.0.beta.1_amd64.deb;"
! grep -q '~' "${sumsFile:-/dev/null}" || tildeBad+=" checksums.txt has a '~';"
if [[ -z "${tildeBad}" ]]
	then fPass
	else fFail "${tildeBad}"
fi

fId EsZni4k "nothing under dist/debug/ is uploaded or listed in checksums.txt"
debugBad=""
for arg in "${betaUploads[@]}"; do
	case "${arg}" in */debug/*|*.debug|*.pdb) debugBad+=" uploaded $(basename "${arg}");" ;; esac
done
if [[ -z "${sumsFile}" ]] || grep -qE '(debug/|\.debug$|\.pdb$)' "${sumsFile}"; then debugBad+=" checksums.txt is missing or lists debug info;"; fi
if [[ -z "${debugBad}" ]]
	then fPass
	else fFail "${debugBad}"
fi

fId ErgqjsR "the release notes are the changelog's section for the version"
betaNotes=""
for ((argIndex = 0; argIndex < ${#betaArgs[@]}; argIndex++)); do
	if [[ "${betaArgs[argIndex]}" == "--notes" ]]; then betaNotes="${betaArgs[argIndex + 1]:-}"; fi
done
if [[ "${betaNotes}" == *"Notes for this one."* ]] && [[ "${betaNotes}" != *"older one"* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fId EshGwj3 "the release notes start with the build number"
if [[ "${betaNotes}" == "zuid v1.0.0-beta.1 build abc12"$'\n'* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fPublishRepo stable 1.0.0
fId ErgqYtD "a version with no '-' is not a prerelease"
out="$(fPublishIn stable 1 0 < /dev/null)" && rc=0 || rc=$?
stableArgs=()
if [[ -e "${work}/stable/gh-create" ]]; then mapfile -d '' -t stableArgs < "${work}/stable/gh-create"; fi
if ((rc == 0)) && ((${#stableArgs[@]})) && [[ " ${stableArgs[*]} " != *" --prerelease "* ]]
	then fPass
	else fFail "exited ${rc}, gh got '${stableArgs[*]:0:6}', said '${out: -160}'"
fi

## The download table in the notes. This set has both Linux packages for both
## CPUs, and one file named for no OS.
fNotesOf(){  ## gh-create log
	local -a args=()
	local -i i=0
	[[ -e "$1" ]] && mapfile -d '' -t args < "$1"
	for ((i = 0; i < ${#args[@]}; i++)); do
		if [[ "${args[i]}" == "--notes" ]]; then printf '%s' "${args[i + 1]:-}"; fi
	done
}
tableDl="https://github.com/example/zuid/releases/download/v1.0.0-beta.1"
fLinks(){  ## asset...
	local links="" name=""
	for name in "$@"; do links+="${links:+<br>}<a href=\"${tableDl}/${name}\">${name}</a>"; done
	printf '%s' "${links}"
}
fPublishRepo table 1.0.0-beta.1
for name in 'zuid_1.0.0~beta.1_arm64.deb' 'zuid-1.0.0~beta.1-1.x86_64.rpm' 'zuid-1.0.0~beta.1-1.aarch64.rpm' 'zuid-1.0.0-beta.1-src.tar.gz' 'zuid-1.0.0-beta.1-windows-x86_64.exe'; do
	printf '%s\n' "${name}" > "${work}/table/repo/dist/${name}"
done
tableOut="$(fPublishIn table 1 0 < /dev/null)" || true
tableNotes="$(fNotesOf "${work}/table/gh-create")"
tableRows=()
mapfile -t tableRows < <(grep '^<tr>' <<< "${tableNotes}" || true)

fId Erm9fTp "the download table has a row per OS and a column per CPU"
tableBad=""
tableWant=(
	"<tr><th></th><th>x86_64</th><th>arm64</th></tr>"
	"<tr><th>Linux</th><td>$(fLinks zuid-1.0.0-beta.1-linux-x86_64.tgz zuid-1.0.0-beta.1-linux-x86_64 zuid_1.0.0.beta.1_amd64.deb zuid-1.0.0.beta.1-1.x86_64.rpm)</td><td>$(fLinks zuid-1.0.0-beta.1-linux-arm64.tgz zuid-1.0.0-beta.1-linux-arm64 zuid_1.0.0.beta.1_arm64.deb zuid-1.0.0.beta.1-1.aarch64.rpm)</td></tr>"
	"<tr><th>macOS</th>"
	"<tr><th>Windows</th><td>$(fLinks zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-x86_64.exe)</td><td>$(fLinks zuid-1.0.0-beta.1-windows-arm64.zip)</td></tr>"
	"<tr><th>FreeBSD</th><td>$(fLinks zuid-1.0.0-beta.1-freebsd-x86_64.tgz zuid-1.0.0-beta.1-freebsd-x86_64)</td><td>-</td></tr>"
)
((${#tableRows[@]} == ${#tableWant[@]})) || tableBad+=" ${#tableRows[@]} rows, wanted ${#tableWant[@]};"
for ((rowIndex = 0; rowIndex < ${#tableWant[@]}; rowIndex++)); do
	if [[ "${tableWant[rowIndex]}" == *"</tr>" ]]; then
		[[ "${tableRows[rowIndex]:-}" == "${tableWant[rowIndex]}" ]] || tableBad+=" row ${rowIndex} was '${tableRows[rowIndex]:-}';"
	else
		[[ "${tableRows[rowIndex]:-}" == "${tableWant[rowIndex]}"* ]] || tableBad+=" row ${rowIndex} was '${tableRows[rowIndex]:-}';"
	fi
done
if [[ -z "${tableBad}" ]]
	then fPass
	else fFail "${tableBad} said '${tableOut: -160}'"
fi

fId Erm9fTq "the macOS universal files span both CPU columns"
macWant="<tr><th>macOS</th><td colspan=\"2\" align=\"center\">$(fLinks zuid-1.0.0-beta.1-darwin-universal.tgz zuid-1.0.0-beta.1-darwin-universal)</td></tr>"
if [[ "${tableRows[2]:-}" == "${macWant}" ]]
	then fPass
	else fFail "macOS row was '${tableRows[2]:-}'"
fi

## The partial run above left out both Windows files.
fId Erm9fTr "a target with no file gets a dash in its cell"
partialNotes="$(fNotesOf "${work}/partial/gh-create")"
partialRows=()
mapfile -t partialRows < <(grep '^<tr>' <<< "${partialNotes}" || true)
if [[ "${partialRows[3]:-}" == "<tr><th>Windows</th><td>-</td><td>-</td></tr>" ]] && [[ "${partialRows[1]:-}" == "<tr><th>Linux</th><td><a href="* ]] && [[ "${partialNotes}" != *zuid-1.0.0-beta.1-windows* ]]
	then fPass
	else fFail "rows were '${partialRows[*]:-}'"
fi

fPublishRepo nomac 1.0.0-beta.1
rm -f "${work}/nomac/repo/dist-incoming/"zuid-1.0.0-beta.1-darwin-universal*
fId ErmpEWr "a missing macOS file gets one dash across both columns"
out="$(fPublishIn nomac 1 1 < /dev/null)" && rc=0 || rc=$?
nomacRows=()
mapfile -t nomacRows < <(grep '^<tr>' <<< "$(fNotesOf "${work}/nomac/gh-create")" || true)
if ((rc == 0)) && [[ "${nomacRows[2]:-}" == "<tr><th>macOS</th><td colspan=\"2\" align=\"center\">-</td></tr>" ]]
	then fPass
	else fFail "exited ${rc}, rows were '${nomacRows[*]:-}'"
fi

fId Erm9fTs "the changelog comes first, then the table, then the other files and checksums.txt"
notesBad=""
inTable="${tableNotes#*<table>}"; inTable="${inTable%%</table>*}"
afterTable="${tableNotes#*</table>}"
[[ "${tableNotes}" == *"Notes for this one."*"### Downloads"*"<table>"*"</table>"* ]] || notesBad+=" not in changelog, heading, table order;"
[[ "${inTable}" != *checksums.txt* ]] || notesBad+=" checksums.txt is in the table;"
[[ "${inTable}" != *-src.tar.gz* ]] || notesBad+=" the source tarball is in the table;"
[[ "${afterTable}" == *"[zuid-1.0.0-beta.1-src.tar.gz](${tableDl}/zuid-1.0.0-beta.1-src.tar.gz)"*"[checksums.txt](${tableDl}/checksums.txt)"* ]] || notesBad+=" other files and checksums.txt are not linked after the table;"
if [[ -z "${notesBad}" ]]
	then fPass
	else fFail "${notesBad} notes were '${tableNotes:0:400}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## test-ids.py, against a scratch tree laid out like this one. The fixture IDs
## are made at run time, since any written into this file would be read as
## real ones.

## Through cicd's path, since the publish cases set a repoRoot of their own.
utilityDir="${cicd%/*}/utility"
idsTree="${work}/ids"
mkdir -p "${idsTree}/cicd/utility" "${idsTree}/zig/lib/src"
cp "${utilityDir}/test-ids.py" "${idsTree}/cicd/utility/"
## A fixed time, not now. The stray scan skips a word with no digit or capital
## past its first letter, and an ID made now is sometimes all lower case there,
## which let ErkRrml pass the check it is meant to fail. Written with +00:00,
## which every python takes, so the Z case below fails alone.
fIdsNew(){ PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" new "$@" 2>&1 ;}
mapfile -t fixtureIds <<< "$(fIdsNew -n 4 --at 2026-09-01T12:00:00+00:00 || true)"

## Python before 3.11 reads no trailing Z by itself, and stock macOS has 3.9.
fId ErmeArM "test-ids.py new --at takes a UTC time ending in Z"
out="$(fIdsNew -n 4 --at 2026-09-01T12:00:00Z)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "$(printf '%s\n' "${fixtureIds[@]}")" ]] && ((${#fixtureIds[@]} == 4))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErmeArN "test-ids.py new --at refuses a bad time in one line"
out="$(fIdsNew --at 2026-13-01T12:00:00Z)" && rc=0 || rc=$?
if ((rc == 2)) && [[ "${out}" == *"--at wants an ISO 8601 time"* ]] && [[ "${out}" != *Traceback* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fIdsTree(){  ## cicd.bash body, extra Zig text
	printf '%s\n' "$1" > "${idsTree}/cicd/cicd.bash"
	{
		printf '// test-id: %s\ntest "a fuzz test" {\n    try std.testing.fuzz({}, f, .{});\n}\n\n' "${fixtureIds[0]}"
		printf '// test-id: %s\ntest "a plain test" {\n    try std.testing.expect(true);\n}\n' "${fixtureIds[1]}"
		printf '%s\n' "${2:-}"
	} > "${idsTree}/zig/lib/src/x.zig"
}
fIdsCheck(){ PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" check 2>&1 ;}

fId ErkRrmk "test-ids.py check passes a tree where every ID belongs to a test"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"3 tests, all unique"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The two arm64 link checks kept their IDs in an array, so the check never saw
## them and would have let a duplicate through.
fId ErkRrml "test-ids.py check refuses an ID that no test line names"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"links=(\"${fixtureIds[3]}:static\")"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' looks like a test ID"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmm "test-ids.py check refuses a test-id mark that is above no test"
fIdsTree "fId ${fixtureIds[2]} \"a check\"" "// test-id: ${fixtureIds[3]}"$'\n'"fn helper() void {}"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' is not directly above a test"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmn "test-ids.py check lets a retired test stay in a comment"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"# fWantRefusal ${fixtureIds[3]} \"retired\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmo "test-ids.py fuzzers lists only the Zig tests that fuzz"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" fuzzers 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "${fixtureIds[0]}"$'\t'"a fuzz test" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## An empty or non-numeric SOURCE_DATE_EPOCH, which clang refuses when Zig
## builds its own libunwind and libc into a cold global cache. A real cold build
## takes minutes, so these check the value never reaches zig.

## Each value as "<value>|<what zig should see>|<1 if a note is wanted>".
epochCases=("|unset|0" "  |unset|0" "soon|unset|1" "1700000000|1700000000|0")

fId ErmER3z "cicd.bash drops an empty or non-numeric SOURCE_DATE_EPOCH before running zig"
epochBad=""
if ! fLoad fDropBadEpoch; then
	epochBad=" no fDropBadEpoch in cicd.bash;"
else
	[[ "$(sed -n '/^fPreflight(){/,/^}/p' "${cicd}")" == *fFindZig*fDropBadEpoch* ]] || epochBad+=" fPreflight does not call it after fFindZig;"
	for epochCase in "${epochCases[@]}"; do
		IFS='|' read -r epochIn epochWant epochNote <<< "${epochCase}"
		out="$(
			# shellcheck disable=2329  ## Called by the lifted fDropBadEpoch.
			fEcho_Clean(){ printf '%s\n' "$*"; }
			export SOURCE_DATE_EPOCH="${epochIn}"
			fDropBadEpoch
			printf 'seen=%s\n' "$(bash -c 'printf %s "${SOURCE_DATE_EPOCH-unset}"')"
		)"
		[[ "${out}" == *"seen=${epochWant}" ]] || epochBad+=" '${epochIn}' reached zig as '${out##*seen=}';"
		if [[ "${epochNote}" == "1" && "${out}" != *"not a number"* ]]; then epochBad+=" '${epochIn}' gave no note;"; fi
		if [[ "${epochNote}" == "0" && "${out}" == *"not a number"* ]]; then epochBad+=" '${epochIn}' got a note;"; fi
	done
fi
if [[ -z "${epochBad}" ]]
	then fPass
	else fFail "${epochBad}"
fi

## package.bash in a scratch tree, with a stand-in zig that records what it was
## handed and fails, so nothing is built.
pkgTree="${work}/pkg"
mkdir -p "${pkgTree}/cicd/utility" "${work}/pkgbin"
cp "${utilityDir}/package.bash" "${pkgTree}/cicd/utility/"
for wasmtimeSub in wasmtime wasmtime-{x86_64,aarch64}-{linux,macos,freebsd}; do
	mkdir -p "${pkgTree}/zig/vendor/${wasmtimeSub}/lib"
	: > "${pkgTree}/zig/vendor/${wasmtimeSub}/lib/libwasmtime.a"
done
cat > "${work}/pkgbin/zig" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${SOURCE_DATE_EPOCH-unset}" > "${PKG_ZIG_SEEN}"
exit 1
EOF
chmod +x "${work}/pkgbin/zig"

fId ErmER40 "package.bash drops an empty or non-numeric SOURCE_DATE_EPOCH before running zig"
epochBad=""
for epochCase in "${epochCases[@]}"; do
	IFS='|' read -r epochIn epochWant epochNote <<< "${epochCase}"
	seenFile="${work}/pkg-seen"
	rm -f "${seenFile}"
	out="$(PATH="${work}/pkgbin:${PATH}" PKG_ZIG_SEEN="${seenFile}" SOURCE_DATE_EPOCH="${epochIn}" \
		bash "${pkgTree}/cicd/utility/package.bash" --out "${work}/pkg-out" 2>&1 < /dev/null)" || true
	if [[ ! -f "${seenFile}" ]]; then
		epochBad+=" '${epochIn}' never reached zig: '${out:0:200}';"
		continue
	fi
	[[ "$(< "${seenFile}")" == "${epochWant}" ]] || epochBad+=" '${epochIn}' reached zig as '$(< "${seenFile}")';"
	if [[ "${epochNote}" == "1" && "${out}" != *"not a number"* ]]; then epochBad+=" '${epochIn}' gave no note;"; fi
	if [[ "${epochNote}" == "0" && "${out}" == *"not a number"* ]]; then epochBad+=" '${epochIn}' got a note;"; fi
done
if [[ -z "${epochBad}" ]]
	then fPass
	else fFail "${epochBad}"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The Zig fuzz stage's report, with a stand-in zig. The fuzz tests are this
## repo's own, so a renamed one is followed rather than hard-coded here.

mapfile -t fuzzList < <(PYTHONDONTWRITEBYTECODE=1 python3 "${utilityDir}/test-ids.py" fuzzers)
fuzzBin="${work}/fuzzbin"
mkdir -p "${fuzzBin}"
## A find names the test, as Zig 0.17.0 words it, and leaves the input in the cache.
cat > "${fuzzBin}/zig" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_FUZZ}" in
	clean) echo "======= FUZZING REPORT ======="; exit 0 ;;
	broken) echo "error: the build broke"; exit 1 ;;
	find)
		mkdir -p .zig-cache/f; printf 'Q\001' > .zig-cache/f/crash
		echo "error: test 'tests.test.${FAKE_FUZZ_TEST}' terminated with signal ABRT; input saved to '.zig-cache/f/crash'"
		exit 1 ;;
esac
EOF
chmod +x "${fuzzBin}/zig"
fuzzTmp="${work}/fuzz-tmp"
mkdir -p "${fuzzTmp}"

fFuzzIn(){  ## mode, name of the test that finds
	local -r dir="${work}/fuzz-$1"
	mkdir -p "${dir}/zig" "${dir}/artifacts"
	(
		# shellcheck disable=2329  ## Called by the lifted fStage_Zig_Fuzz, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329,2154  ## testId and testName come from the lifted fId.
		fTestPass(){ printf '  ok ....: %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  skip ..: %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL ..: %s %s\n%s\n' "${testId}" "${testName}" "$*"; exit 1; }
		local fn=""
		for fn in fId fStage_Zig_Fuzz _fRemoveScratchDirs; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			doQuick=0; zigDir="${dir}/zig"; buildJobs=1
			_scratchDirs=(); artifactDir="${dir}/artifacts"; runStamp="pipeline-test"
		}
		## The script's own exit cleanup. A failed case leaves through exit 1,
		## and its log folder went with it into the real temp dir.
		trap _fRemoveScratchDirs EXIT
		# shellcheck disable=2030  ## Only the subshell is meant to see it.
		export FAKE_FUZZ="$1" FAKE_FUZZ_TEST="${2:-}" PATH="${fuzzBin}:${PATH}" TMPDIR="${fuzzTmp}"
		fStage_Zig_Fuzz
	) 2>&1
}

## Each fuzz test as "<id> <name>", the way a status line names it.
fuzzLines=()
for fuzzLine in "${fuzzList[@]}"; do fuzzLines+=("${fuzzLine%%$'\t'*} ${fuzzLine#*$'\t'}"); done

fId ErkRrmp "a clean fuzz run prints an ok line for each fuzz test, under its own ID"
out="$(fFuzzIn clean)" && rc=0 || rc=$?
fuzzBad=""
((${#fuzzLines[@]} >= 2)) || fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
for fuzzLine in "${fuzzLines[@]}"; do
	[[ "${out}" == *"  ok ....: ${fuzzLine}, fuzzed for "* ]] || fuzzBad+=" no ok line for '${fuzzLine}';"
done
if ((rc == 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

## Before 20261004 the two shared one line, so a find could not say whose it was.
fId ErkRrmq "a fuzz find fails the test that found it and keeps the input"
out="" rc=0 fuzzBad=""
if ((${#fuzzLines[@]} < 2)); then
	fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
else
	out="$(fFuzzIn find "${fuzzList[1]#*$'\t'}")" || rc=$?
	[[ "${out}" == *"  FAIL ..: ${fuzzLines[1]}, fuzzed for "* ]] || fuzzBad+=" no FAIL line for the finder;"
	[[ "${out}" == *"  skip ..: ${fuzzLines[0]}, fuzzed for "* ]] || fuzzBad+=" no skip line for the other;"
	[[ -s "${work}/fuzz-find/artifacts/fuzz/zig-crash_pipeline-test" ]] || fuzzBad+=" the input was not kept;"
fi
if ((rc != 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

fId ErkRrmr "a fuzz run that breaks without a find fails every fuzz test"
out="$(fFuzzIn broken)" && rc=0 || rc=$?
fuzzBad=""
((${#fuzzLines[@]} >= 2)) || fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
for fuzzLine in "${fuzzLines[@]}"; do
	[[ "${out}" == *"  FAIL ..: ${fuzzLine}, fuzzed for "* ]] || fuzzBad+=" no FAIL line for '${fuzzLine}';"
done
if ((rc != 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

## Each case above left its fuzz.log folder in the temp dir, 2 a run, since
## nothing cleaned up after the subshell.
fId EscPGS5 "the fuzz stage leaves nothing in TMPDIR, passed or failed"
fuzzLeft="$(find "${fuzzTmp}" -mindepth 1 -maxdepth 1 2>&1 | tr '\n' ' ' || true)"
if [[ -z "${fuzzLeft}" ]]
	then fPass
	else fFail "left ${fuzzLeft}"
fi

## Cleanup used to remove only what sat under /tmp, so with TMPDIR elsewhere
## every scratch folder stayed. It still takes nothing mktemp -d did not make.
fId EscPGS6 "scratch cleanup removes tmp.* folders in TMPDIR and nothing else"
cleanTmp="${work}/clean-tmp"
mkdir -p "${cleanTmp}/tmp.mine" "${cleanTmp}/keep" "${work}/clean-other/tmp.elsewhere" "${work}/clean-target"
ln -s "${work}/clean-target" "${cleanTmp}/tmp.link"
cleanBad=""
if ! out="$(
	fLoad _fRemoveScratchDirs || { echo "no _fRemoveScratchDirs in cicd.bash"; exit 2; }
	# shellcheck disable=2031  ## Its own TMPDIR, with the trailing slash macOS gives.
	export TMPDIR="${cleanTmp}/"
	_scratchDirs=("${cleanTmp}/tmp.mine" "${cleanTmp}/keep" "${work}/clean-other/tmp.elsewhere" "${cleanTmp}/tmp.link" "")
	_fRemoveScratchDirs
	printf 'left=%s\n' "${#_scratchDirs[@]}"
)"; then
	cleanBad=" ${out};"
else
	[[ ! -e "${cleanTmp}/tmp.mine" ]]                || cleanBad+=" kept tmp.mine;"
	[[ -d "${cleanTmp}/keep" ]]                      || cleanBad+=" removed keep;"
	[[ -d "${work}/clean-other/tmp.elsewhere" ]]     || cleanBad+=" removed a tmp.* outside TMPDIR;"
	[[ -L "${cleanTmp}/tmp.link" && -d "${work}/clean-target" ]] || cleanBad+=" followed or removed a link;"
	[[ "${out}" == "left=0" ]]                       || cleanBad+=" the list was not emptied: ${out};"
fi
if [[ -z "${cleanBad}" ]]
	then fPass
	else fFail "${cleanBad}"
fi

## The profile report sorted self time by the leaf's own name, and registry
## construction spends its time in strings and the allocator, so a third of a
## profile read as 0% registry. Here 40 of 100 samples sit under NewRegistry.
mkdir -p "${work}/flame"
cat > "${work}/flame/flame_20260101-000000_go.svg" <<'SVG'
<svg total_samples="100">
<g><title>all (100 samples, 100%)</title><rect x="0%" y="100" width="100%" height="15" fg:x="0" fg:w="100"/></g>
<g><title>github.com/jim-collier/convert-base-v2/lib/convertbase.NewRegistry (40 samples, 40%)</title><rect x="0%" y="84" width="40%" height="15" fg:x="0" fg:w="40"/></g>
<g><title>strings.Index (40 samples, 40%)</title><rect x="0%" y="68" width="40%" height="15" fg:x="0" fg:w="40"/></g>
<g><title>github.com/jim-collier/zuid/go/zuid.(*Generator).Generate (60 samples, 60%)</title><rect x="40%" y="84" width="60%" height="15" fg:x="40" fg:w="60"/></g>
</svg>
SVG
fId ErsspWK "the profile report counts what runs under NewRegistry as registry time"
out="$(python3 "${flameReport}" --dir "${work}/flame" 2>&1)" || true
if grep -q 'registry construction.*40\.0%' <<< "${out}"
	then fPass
	else fFail "said: $(grep 'registry' <<< "${out}" || echo nothing)"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## vuln-report.py, on made-up govulncheck streams: indented objects back to
## back, as govulncheck writes them.

fVulnFinding(){  ## osv, module, package, function or empty
	printf '{\n  "osv": {"id": "%s", "summary": "made up"}\n}\n' "$1"
	printf '{\n  "finding": {\n    "osv": "%s",\n    "trace": [{"module": "%s", "version": "v1.0.0", "package": "%s"%s}]\n  }\n}\n' \
		"$1" "$2" "$3" "${4:+, \"function\": \"$4\"}"
}
fVulnReport(){ python3 "${utilityDir}/vuln-report.py" 2>&1 ;}
vulnConfig='{"config": {"go_version": "go1.0.1"}}'

fId Et9luGK "the vuln report fails on a stdlib advisory in code that's called"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0001 stdlib net LookupCNAME; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"GO-0000-0001 in go1.0.1, called from net.LookupCNAME"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Et9luGL "the vuln report only counts a stdlib advisory in code that isn't called"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0002 stdlib net ""; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"1 advisories for go1.0.1 in code we don't call"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Et9luGM "the vuln report fails on a third-party advisory, even one that isn't called"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0003 example.com/x example.com/x ""; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"GO-0000-0003 in example.com/x@v1.0.0"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## codeql-report.py, on made-up SARIF with one rule tagged as a bug and one as
## style. CodeQL puts a query pack's rules under extensions, not the driver.

fSarif(){  ## file:rule...
	local sep="" pair=""
	printf '{"runs": [{"tool": {"driver": {"name": "CodeQL", "rules": []}, "extensions": [{"name": "made-up", "rules": ['
	printf '{"id": "x/bug", "properties": {"tags": ["security"]}}, {"id": "x/style", "properties": {"tags": ["maintainability"]}}]}]}, "results": ['
	for pair in "$@"; do
		printf '%s{"ruleId": "%s", "message": {"text": "made up"}, "locations": [{"physicalLocation": {"artifactLocation": {"uri": "%s"}, "region": {"startLine": 3}}}]}' \
			"${sep}" "${pair#*:}" "${pair%%:*}"
		sep=", "
	done
	printf ']}]}\n'
}
fCodeqlReport(){  ## suppressions file, file:rule...
	local -r suppressions="$1"; shift
	fSarif "$@" > "${work}/made-up.sarif"
	python3 "${utilityDir}/codeql-report.py" report "${work}/made-up.sarif" go "${suppressions}" 2>&1
}
: > "${work}/no-suppressions"

fId EtAj5P3 "the CodeQL report fails on any finding in our own code, style ones too"
out="$(fCodeqlReport "${work}/no-suppressions" zuid/a.go:x/style)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"x/style at zuid/a.go:3: made up"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId EtAj5P4 "the CodeQL report counts only security and correctness findings in third-party code"
out="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/style)" && rc=0 || rc=$?
out2="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/bug)" && rc2=0 || rc2=$?
if ((rc == 0 && rc2 == 1)) && [[ "${out}" == *"1 style findings in third-party code"* && "${out2}" == *"x/bug at vendor/m/a.go:3"* ]]
	then fPass
	else fFail "exited ${rc} and ${rc2}, and said '${out//$'\n'/ | }' and '${out2//$'\n'/ | }'"
fi

fId EtAj5P5 "a CodeQL suppression hides its rule in its file only, one that matches nothing fails, and one without a backlog ID is refused"
printf '## made up\ngo 2026101911183280 x/bug vendor/m/a.go\nc 2026101911183281 x/bug test/a.c\n' > "${work}/suppressions"
printf 'go x/bug vendor/m/a.go\n' > "${work}/suppressions-bad"
out="$(fCodeqlReport "${work}/suppressions" vendor/m/a.go:x/bug)" && rc=0 || rc=$?
out2="$(fCodeqlReport "${work}/suppressions" vendor/m/b.go:x/bug)" && rc2=0 || rc2=$?
out3="$(fCodeqlReport "${work}/suppressions-bad" vendor/m/a.go:x/bug)" && rc3=0 || rc3=$?
out4="$(fCodeqlReport "${work}/suppressions")" && rc4=0 || rc4=$?
if ((rc == 0 && rc2 == 1 && rc3 != 0 && rc4 == 1)) && [[ "${out}" == *"Suppressed .: 1 of x/bug in vendor/m/a.go, until 2026101911183280"* ]] \
	&& [[ "${out2}" == *"x/bug at vendor/m/b.go:3"* && "${out2}" == *"2026101911183280 in suppressions matched nothing"* ]] \
	&& [[ "${out2}" != *2026101911183281* && "${out3}" == *"suppressions-bad:1: wants"* && "${out4}" == *"2026101911183280 in suppressions matched nothing"* ]]
	then fPass
	else fFail "exited ${rc}, ${rc2}, ${rc3} and ${rc4}, and said '${out//$'\n'/ | }', '${out2//$'\n'/ | }', '${out3}' and '${out4//$'\n'/ | }'"
fi

fId EtAj5P6 "the CodeQL coverage check fails when a file the build compiled isn't in the database"
mkdir -p "${work}/cov/db"
: > "${work}/cov/in.c"; : > "${work}/cov/out.c"
python3 -c 'import os, sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").writestr(os.path.realpath(sys.argv[2]).lstrip("/"), "")' \
	"${work}/cov/db/src.zip" "${work}/cov/in.c"
fCoverage(){ python3 "${utilityDir}/codeql-report.py" coverage "$@" 2>&1 ;}
out="$(fCoverage "${work}/cov/db" "${work}/cov/in.c")" && rc=0 || rc=$?
out2="$(fCoverage "${work}/cov/db" "${work}/cov/in.c" "${work}/cov/out.c")" && rc2=0 || rc2=$?
out3="$(fCoverage "${work}/cov" "${work}/cov/in.c")" && rc3=0 || rc3=$?
if ((rc == 0 && rc2 == 1 && rc3 == 1)) && [[ "${out2}" == *"Not in the database: ${work}/cov/out.c"* && "${out2}" != *"database: ${work}/cov/in.c"* ]] \
	&& [[ "${out3}" == *"has no source in it"* ]]
	then fPass
	else fFail "exited ${rc}, ${rc2} and ${rc3}, and said '${out}', '${out2//$'\n'/ | }' and '${out3}'"
fi

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261019 JC: The CodeQL report, and CodeQL's image under --container.
##		- 20261019 JC: --leakcheck.
##		- 20261019 JC: The vuln report.
##		- 20261018 JC: --gate is --ci. Every run cross-compiles.
##		- 20261013 JC: Fuzz cases clean up their temp folders.
##		- 20261010 JC: --container.
##		- 20261005 JC: The profile report's registry bucket.
##		- 20261004 JC: SOURCE_DATE_EPOCH kept from zig.
##		- 20261014 JC: --gate refusals, and the build number in the release notes.
##		- 20261004 JC: The download table in the release notes.
##		- 20261004 JC: test-ids.py and the Zig fuzz report.
##		- 20261003 JC: Publishing.
##		- 20260930 JC: Created.
