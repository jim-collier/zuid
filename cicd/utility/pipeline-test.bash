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
##		report made-up SARIF. The FreeBSD vendor step reads a stand-in repo
##		with its own signed catalog.
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
	passed=$((passed + 1)); printf '  PASS %s %s\n' "${curId}" "${curName}"
	curId=""
}
fFail(){  ## detail
	failed=$((failed + 1)); printf '  FAIL %s %s: %s\n' "${curId:-?????}" "${curName}" "$*"
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

## The guard is for the lifted functions that remove a folder too. The run
## folder is physical, since the guard refuses a path through a link, and
## macOS's temp folder sits behind /var.
# shellcheck source=cicd/utility/include/safe-rm.bash
source "${repoRoot}/cicd/utility/include/safe-rm.bash"
trap '[[ -z "${safeRmRunDir}" ]] || fSafeRm "${safeRmRunDir}"' EXIT
fRunDir_Sub zuid pipeline-test || fDie "no run folder"
work="${safeRmRunDir}"
## The guard refuses a path that isn't there.
fRmIfThere(){ if [[ -e "$1" || -L "$1" ]]; then fSafeRm "$1"; fi ;}
## The exported values, space-separated. One name per printenv, since BSD's
## takes only one.
fPrintEnv(){ local n; for n in "$@"; do printenv "${n}"; done | tr '\n' ' ' ;}


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
fWantRefusal ddb0k "-h inside a message"  "after --only" -m 'fix the -h case' --only nope

## --commit used to take an optional message, and swallowed whatever flag came
## next as one.
fWantRefusal ddb0m "--commit leaves the next flag alone"    "after --only" --commit --only nope
fWantRefusal ddb0n "-m won't take a flag"               "Expecting a value after -m" -m --quick
fWantRefusal ddb0p "--backup with --commit"     "--backup already commits" --backup --commit
## Retired 20261003: --publish is implemented now, so this refusal is gone on
## purpose. The publish cases below cover it instead.
# fWantRefusal ddb0q "--publish says it is not there yet"             "Not implemented yet" --publish
fWantRefusal ddb0r "unknown argument named"                   "'--bogus'" --bogus
fWantRefusal ddfb7 "--allow-partial needs --publish"   "only means something with --publish" --allow-partial
fWantRefusal ddfb8 "--publish with --only go"            "--publish needs the Zig side" --publish --only go
fWantRefusal ddrj4 "--publish with --container"          "does not go with --container" --publish --container
fWantRefusal ddyby "--gate won't commit"                  "--gate only builds and tests" --gate --commit
fWantRefusal ddybz "--gate won't package"                 "--gate only builds and tests" --gate --package
## --ci was renamed back to --gate with no alias on 20261019, and came back as
## another name for --merge-gate on 20261025. The bad --only after it keeps a
## run from starting, and shows --ci was taken.
fWantRefusal de4bt "--ci is taken"                    "after --only" --ci --only nope
fWantRefusal ddyee "--publish with --no-package"         "does not go with --no-package" --publish --no-package

fId ddrj5 "--container from inside one"
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

## Headers come from fStep now, but a lifted helper may still print one.
# shellcheck disable=2329  ## Called by the lifted functions.
fSection(){ :; }

## A prerelease of the floor version passed the floor, because only the
## release part was compared.
fId ddb0s "prerelease is below its floor"
if ! fLoad fVersion_AtLeast; then
	fFail "no fVersion_AtLeast in cicd.bash"
elif fVersion_AtLeast "0.16.0-dev.1+abc" "0.16.0"; then
	fFail "0.16.0-dev.1 passed a 0.16.0 floor"
else
	fPass
fi

fId ddb0t "version floor compare"
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

fId ddb0v "no commit on main"
out="$(fCommitIn "${scratchRepo}" || true)"
if [[ "${out}" == *"Refusing to commit to 'main'"* && -z "$(git -C "${scratchRepo}" log --format=%h -1 --skip 1 2>/dev/null || true)" ]]
	then fPass
	else fFail "said '${out}'"
fi

fId ddb0w "no commit on a detached HEAD"
git -C "${scratchRepo}" checkout -q --detach
out="$(fCommitIn "${scratchRepo}" || true)"
if [[ "${out}" == *"HEAD is detached"* ]]
	then fPass
	else fFail "said '${out}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Machine use. The counts are worked out in one place, here with the CPU
## count and the load stubbed.

fJobsWith(){  ## cpus, load, [cap]
	(
		stubCpus="$1" stubLoad="$2"
		# shellcheck disable=2329  ## Called by the lifted fJobs.
		fCpuCount(){ printf '%s\n' "${stubCpus}"; }
		# shellcheck disable=2329
		fLoadAvg(){ printf '%s\n' "${stubLoad}"; }
		fLoad fJobs || { echo "no fJobs in cicd.bash"; exit 2; }
		local -i cpuCount=0 buildJobs=0 hardJobs=0 machineBusy=0
		local loadNow=""
		if [[ -n "${3:-}" ]]; then export ZUID_JOBS_CAP="$3"; else unset ZUID_JOBS_CAP; fi
		fJobs
		printf '%s %s %s %s\n' "${buildJobs}" "${hardJobs}" "${machineBusy}" "${loadNow}"
	) 2>&1
}

fId dedp4 "job counts: half, a quarter when busy, a quarter for hard steps"
jobsBad=""
while IFS='|' read -r jobsCpus jobsLoad jobsCap jobsWant; do
	jobsGot="$(fJobsWith "${jobsCpus}" "${jobsLoad}" "${jobsCap}" || true)"
	[[ "${jobsGot}" == "${jobsWant}" ]] || jobsBad+=" ${jobsCpus} CPUs, load ${jobsLoad}, cap '${jobsCap}': got '${jobsGot}', wanted '${jobsWant}';"
done <<- 'EOF'
	32|15.99||16 8 0 15.99
	32|16.00||16 8 0 16.00
	32|16.01||8 8 1 16.01
	32|20.39|4|4 4 1 20.39
	32|1.00|x|16 8 0 1.00
	6|2||3 1 0 2
	3|9.5||1 1 1 9.5
	1|0.00||1 1 0 0.00
	EOF
if [[ -z "${jobsBad}" ]]
	then fPass
	else fFail "${jobsBad}"
fi

## Compared as a number, so what the load reader hands back must never reach
## arithmetic unchecked.
fId dedp5 "a bad load reading counts as no load"
jobsBad=""
for jobsLoad in "" "high" "1.5.2" "x[\$(touch ${work}/jobs-pwned)]"; do
	jobsGot="$(fJobsWith 32 "${jobsLoad}" || true)"
	[[ "${jobsGot}" == "16 8 0 unknown" ]] || jobsBad+=" load '${jobsLoad}' gave '${jobsGot}';"
done
[[ ! -e "${work}/jobs-pwned" ]] || jobsBad+=" a load reading ran a command;"
if [[ -z "${jobsBad}" ]]
	then fPass
	else fFail "${jobsBad}"
fi

fId dedp6 "counts are checked again before each step"
out="$(
	stubLoad="1.00"
	# shellcheck disable=2329  ## Called by the lifted functions.
	fCpuCount(){ printf '32\n'; }
	# shellcheck disable=2329
	fLoadAvg(){ printf '%s\n' "${stubLoad}"; }
	# shellcheck disable=2329
	fEcho_Clean(){ printf '%s\n' "$*"; }
	for fn in fJobs fJobs_Line fJobs_Recheck; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2034  ## Read by the lifted functions.
	{ cpuCount=0; buildJobs=0; hardJobs=0; machineBusy=0; loadNow="" ;}
	unset ZUID_JOBS_CAP
	fJobs_Recheck; echo "before: ${buildJobs}"
	fJobs; fJobs_Recheck; echo "same: ${buildJobs}"
	stubLoad="30.00"; fJobs_Recheck; echo "busy: ${buildJobs}"
)" && rc=0 || rc=$?
want=$'before: 0\nsame: 16\nJobs .......: 8, 8 for the hard steps (32 CPUs, load 30.00, busy)\nbusy: 8'
if ((rc == 0)) && [[ "${out}" == "${want}" ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## On the script's own process, so everything it starts inherits it. Read
## through fNiceOf, since the image has no ps. Where there is /proc, its branch
## is checked too, with ps hidden by a function.
fId dedpa "the run lowers its own priority"
out="$(bash -c "$(sed -n '/^fLowPriority(){/,/^}/p;/^fNiceOf(){/,/^}/p' "${cicd}")"'
	fLowPriority
	printf "%s|" "$(fNiceOf "$$")"
	if [[ -r "/proc/$$/stat" ]]; then
		printf "%s|" "$(command(){ [[ "$*" != "-v ps" ]] && builtin command "$@"; }; fNiceOf "$$")"
	else
		printf "19|"
	fi
	if command -v ionice >/dev/null; then ionice -p "$$"; fi
' 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "19|19|"* ]] && { ! command -v ionice >/dev/null || [[ "${out}" == "19|19|idle"* ]]; }
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## CodeQL ran on half the box, whatever cicd.bash was handing everything else.
fId dedp9 "codeql.bash takes its thread count from cicd.bash"
codeqlThreads="$(sed -n '/^fThreads(){/,/^}/p' "${cicd%/*}/utility/codeql.bash")"
jobsBad=""
[[ -n "${codeqlThreads}" ]] || jobsBad+=" no fThreads in codeql.bash;"
for jobsCase in "5|5" "|1" "x|1" "0|1"; do
	jobsGot="$(ZUID_JOBS="${jobsCase%|*}" bash -c "${codeqlThreads}"$'\nfThreads' 2>&1 || true)"
	[[ "${jobsGot}" == "${jobsCase#*|}" ]] || jobsBad+=" ZUID_JOBS='${jobsCase%|*}' gave '${jobsGot}';"
done
if [[ -z "${jobsBad}" ]]
	then fPass
	else fFail "${jobsBad}"
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
		{ repoRoot="$1"; runStamp="pipeline-test"; buildJobs=1; hardJobs=1; cpuCount=2; machineBusy=0; loadNow="0.00"; doGo=0; doZig=0; doPublish=0 ;}
		shift
		local fn=""
		for fn in "$@" fJobs_Line; do
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

fId ddgkv "sync in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fStage_Sync)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Remote .....: none"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddgkw "preflight in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fPreflight)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Branch .....: side"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddgkx "sync and preflight want the checkout's top"
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
fId ddhnc "repo root through a symlink"
mkdir -p "${work}/linked/real/cicd/utility/include"
cp "${cicd}" "${work}/linked/real/cicd/"
cp "${cicd%/cicd.bash}/utility/include/safe-rm.bash" "${work}/linked/real/cicd/utility/include/"
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
			doContainer=0; containerMode="auto"; inContainer=0; doGate=0; doLeakcheck=1; leakAsked=0
			doFuzz=1; doProfile=1; doDemo=1
			doFullGate=0; gateFlag=""; aliasNote=""; doLong=0; doRemote=1; runAreas=(); doList=0
		}
		shift
		local fn=""
		for fn in fMustBeAValue fPackageBlocker fInit fInit_Area fConfig; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fConfig
		# shellcheck disable=2034,2154  ## Read by the lifted fInit_Area, set by the lifted fConfig.
		areas=("${default_areas[@]}")
		# shellcheck disable=2030  ## Only this subshell's PATH, on purpose.
		if [[ -n "${fakePath:-}" ]]; then PATH="${fakePath}"; fi
		fInit "$@"
		if [[ "${showCross:-0}" == "1" ]]; then
			printf 'doCross=%s\n' "${doCross}"
		elif [[ "${showLeak:-0}" == "1" ]]; then
			printf 'doLeakcheck=%s\n' "${doLeakcheck}"
		elif [[ "${showSlow:-0}" == "1" ]]; then
			printf 'doFuzz=%s doProfile=%s doDemo=%s\n' "${doFuzz}" "${doProfile}" "${doDemo}"
		elif [[ "${showFullGate:-0}" == "1" ]]; then
			printf 'quick=%s sync=%s backup=%s dogfood=%s demo=%s quiet=%s leak=%s fuzz=%s profile=%s remote=%s note=%s\n' \
				"${doQuick}" "${doSync}" "${doBackup}" "${doDogfood}" "${doDemo}" "${doQuietly}" "${doLeakcheck}" "${doFuzz}" "${doProfile}" "${doRemote}" "${aliasNote:-none}"
		elif [[ "${showAreas:-0}" == "1" ]]; then
			printf 'areas=%s quick=%s list=%s only=%s\n' "${runAreas[*]:-none}" "${doQuick}" "${doList}" "${onlyToolchain:-none}"
		elif [[ "${showGate:-0}" == "1" ]]; then
			printf 'doQuick=%s doSync=%s doBackup=%s doDogfood=%s doPackage=%s\n' "${doQuick}" "${doSync}" "${doBackup}" "${doDogfood}" "${doPackage}"
		elif [[ "${showPackage:-0}" == "1" ]]; then
			printf 'doPackage=%s skip=%s\n' "${doPackage}" "${packageSkipWhy}"
		elif [[ "${showContainer:-0}" == "1" ]]; then
			printf 'doContainer=%s mode=%s\n' "${doContainer}" "${containerMode}"
		else
			printf 'doBackup=%s backupInWorktree=%s\n' "${doBackup}" "${backupInWorktree}"
		fi
	) 2>&1
}

fId ddgky "default backup skips linked worktrees"
outWorktree="$(fInitIn "${worktreeDir}")" && rc=0 || rc=$?
outMain="$(fInitIn "${worktreeMain}")" || rc=$?
if ((rc == 0)) && [[ "${outWorktree}" == "doBackup=0 backupInWorktree=1" ]] && [[ "${outMain}" == "doBackup=1 backupInWorktree=0" ]]
	then fPass
	else fFail "exited ${rc}, worktree said '${outWorktree}', main checkout said '${outMain}'"
fi

fId ddgkz "--backup refused in a linked worktree"
out="$(fInitIn "${worktreeDir}" --backup)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"linked worktree"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The pre-push hook runs --gate inside a push, so it must not sync, install,
## or push again.
fId ddyc0 "what --gate leaves out"
out="$(showGate=1 fInitIn "${worktreeMain}" --gate)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doQuick=1 doSync=0 doBackup=0 doDogfood=0 doPackage=0" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The Go cross builds are seconds, so a quick run and the pre-push one get
## them as well as a full run.
fId de4bv "every run mode cross-compiles"
out="$(showCross=1 fInitIn "${worktreeMain}"; showCross=1 fInitIn "${worktreeMain}" --quick; showCross=1 fInitIn "${worktreeMain}" --gate)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doCross=1\ndoCross=1\ndoCross=1' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## The leak checks take about 10 minutes, so a full run has them and a quick or
## pre-push one only if asked. --no-leakcheck drops them from any run.
fId de5cn "--leakcheck is default, off for quick and gate"
out="$(for leakArgs in "" --quick --gate; do
	# shellcheck disable=2086  ## Empty means no argument at all.
	showLeak=1 fInitIn "${worktreeMain}" ${leakArgs}
	# shellcheck disable=2086
	showLeak=1 fInitIn "${worktreeMain}" ${leakArgs} --leakcheck
	# shellcheck disable=2086
	showLeak=1 fInitIn "${worktreeMain}" ${leakArgs} --no-leakcheck
done)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doLeakcheck=1\ndoLeakcheck=1\ndoLeakcheck=0\ndoLeakcheck=0\ndoLeakcheck=1\ndoLeakcheck=0\ndoLeakcheck=0\ndoLeakcheck=1\ndoLeakcheck=0' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## Each slow stage can be left out of a full run alone, so a failure in one
## doesn't stop a run that's testing something else. Quick drops profile and
## demo, but fuzzes. The gate drops all three.
fId debne "--no-fuzz, --no-profile, --no-demo"
out="$(for slowArgs in "" --no-fuzz --no-profile --no-demo "--no-fuzz --no-profile --no-demo" --quick --gate "--quick --no-demo"; do
	# shellcheck disable=2086  ## Empty means no argument at all.
	showSlow=1 fInitIn "${worktreeMain}" ${slowArgs}
done)" && rc=0 || rc=$?
wantSlow="doFuzz=1 doProfile=1 doDemo=1"$'\n'"doFuzz=0 doProfile=1 doDemo=1"$'\n'"doFuzz=1 doProfile=0 doDemo=1"$'\n'"doFuzz=1 doProfile=1 doDemo=0"
wantSlow+=$'\n'"doFuzz=0 doProfile=0 doDemo=0"$'\n'"doFuzz=1 doProfile=0 doDemo=0"$'\n'"doFuzz=0 doProfile=0 doDemo=0"$'\n'"doFuzz=1 doProfile=0 doDemo=0"
if ((rc == 0)) && [[ "${out}" == "${wantSlow}" ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## The gate flags never commit, push, install, publish or prompt. Through the
## lifted fInit, since a refusal that broke would start a real run, and these
## flags don't prompt.
fId dedpp "gate flags refuse the stages that write"
gateBad=""
for gateArgs in "--merge-gate --commit" "--merge-gate --push" "--merge-gate --dogfood" "--merge-gate --backup" "--merge-gate --publish" \
	"--ci --commit" "--backlog-run-full --dogfood" "--backlog-run-quick --package" "--backlog-run-quick --push" "--gate -m msg"; do
	# shellcheck disable=2086  ## Split on purpose.
	out="$(fInitIn "${worktreeMain}" ${gateArgs})" && rc=0 || rc=$?
	if ((rc == 0)) || [[ "${out}" != *"${gateArgs%% *} only builds and tests"* ]]; then gateBad+=" '${gateArgs}' exited ${rc}: ${out:0:80};"; fi
done
for gateArgs in "--merge-gate --quick" "--quick --ci" "--backlog-run-full --gate" "--long --quick" "--slow --backlog-run-quick"; do
	# shellcheck disable=2086
	out="$(fInitIn "${worktreeMain}" ${gateArgs})" && rc=0 || rc=$?
	if ((rc == 0)) || [[ "${out}" != *"n't go "* ]]; then gateBad+=" '${gateArgs}' exited ${rc}: ${out:0:80};"; fi
done
if [[ -z "${gateBad}" ]]
	then fPass
	else fFail "${gateBad}"
fi

## What each gate flag runs. The full ones run the default run's checks, fuzz,
## profile and leak checks included, minus what writes or prompts. --gate and
## --ci say they're other names.
fId dedpq "what the gate flags run"
out="$(for gateArgs in --backlog-run-quick --gate --backlog-run-full --merge-gate --ci "--merge-gate --no-remote"; do
	# shellcheck disable=2086
	showFullGate=1 fInitIn "${worktreeMain}" ${gateArgs}
done)" && rc=0 || rc=$?
wantGate="quick=1 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=0 fuzz=0 profile=0 remote=1 note=none"
wantGate+=$'\n'"quick=1 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=0 fuzz=0 profile=0 remote=1 note=--gate is another name for --backlog-run-quick."
wantGate+=$'\n'"quick=0 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=1 fuzz=1 profile=1 remote=1 note=none"
wantGate+=$'\n'"quick=0 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=1 fuzz=1 profile=1 remote=1 note=none"
wantGate+=$'\n'"quick=0 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=1 fuzz=1 profile=1 remote=1 note=--ci is another name for --merge-gate."
wantGate+=$'\n'"quick=0 sync=0 backup=0 dogfood=0 demo=0 quiet=1 leak=1 fuzz=1 profile=1 remote=0 note=none"
if ((rc == 0)) && [[ "${out}" == "${wantGate}" ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## --long and --slow are the default run for now. The note for --gate and --ci
## goes out once the run log has started.
fId dedpr "--long, --slow, and the alias line"
out="$(showFullGate=1 fInitIn "${worktreeMain}" --long; showFullGate=1 fInitIn "${worktreeMain}" --slow)" && rc=0 || rc=$?
wantLong="quick=0 sync=1 backup=1 dogfood=1 demo=1 quiet=0 leak=1 fuzz=1 profile=1 remote=1 note=none"
# shellcheck disable=2016  ## Script text, looked for as written.
if ((rc == 0)) && [[ "${out}" == "${wantLong}"$'\n'"${wantLong}" ]] \
	&& grep -A1 -F 'then fStartRunLog; fi' <<< "$(sed -n '/^fMain(){/,/^}/p' "${cicd}")" | grep -qF 'if [[ -n "${aliasNote}" ]]; then fEcho_Clean; fEcho_Clean "${aliasNote}"; fi'
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }', or fMain doesn't print the alias line after the log starts"
fi

## Words after --backlog-run-quick, up to the next option, are areas. Only
## known ones, and not with --only, since the areas pick the toolchains.
fId dedtw "areas after --backlog-run-quick"
out="$(for areaArgs in "--backlog-run-quick go zig" "--gate SHELL --no-container" "--backlog-run-quick" "--list --backlog-run-quick docs installers -q"; do
	# shellcheck disable=2086
	showAreas=1 fInitIn "${worktreeMain}" ${areaArgs}
done)" && rc=0 || rc=$?
wantAreas="areas=go zig quick=1 list=0 only=none"$'\n'"areas=shell quick=1 list=0 only=none"$'\n'"areas=none quick=1 list=0 only=none"$'\n'"areas=docs installers quick=1 list=1 only=none"
areaBad=""
((rc == 0)) && [[ "${out}" == "${wantAreas}" ]] || areaBad+=" exited ${rc} and said '${out//$'\n'/ | }';"
for areaArgs in "--backlog-run-quick nope|for --backlog-run-quick. The areas are: go zig shell installers docs." \
	"--gate go --only zig|already pick the toolchains" "--only go --backlog-run-quick go|already pick the toolchains" "--backlog-run-full go|not expected in this context"; do
	# shellcheck disable=2086
	out="$(showAreas=1 fInitIn "${worktreeMain}" ${areaArgs%%|*})" && rc=0 || rc=$?
	if ((rc == 0)) || [[ "${out}" != *"${areaArgs#*|}"* ]]; then areaBad+=" '${areaArgs%%|*}' exited ${rc}: ${out:0:100};"; fi
done
if [[ -z "${areaBad}" ]]
	then fPass
	else fFail "${areaBad}"
fi

fId debnf "the stage calls follow the flags"
## Read from the step list and the Zig fuzz stage, so a stage that goes back
## to keying on doQuick fails here. The list moved out of fMain into fSteps
## on 2026102416233104.
mainBody="$(sed -n '/^fMain(){/,/^}/p' "${cicd}")"
stepsBody="$(sed -n '/^fSteps(){/,/^}/p; /^fSteps_Checks(){/,/^}/p' "${cicd}")"
zigFuzzBody="$(sed -n '/^fStage_Zig_Fuzz(){/,/^}/p' "${cicd}")"
if grep -q 'if ((doProfile)); then fStep "Profile" fStage_Profile$' <<< "${stepsBody}" \
	&& grep -A1 -F 'if ((! inContainer)); then' <<< "${stepsBody}" | grep -q 'if ((doDemo)); then fStep "Demo" fStage_Demo$' \
	&& grep -q 'if ((doFuzz)); then fStep "Go: fuzz" fStage_Go_Fuzz;' <<< "${stepsBody}" \
	&& grep -q 'if ((doFuzz)); then fStep "Zig: fuzz" fStage_Zig_Fuzz;' <<< "${stepsBody}" && grep -q 'if ((! doFuzz)); then' <<< "${zigFuzzBody}"
	then fPass
	else fFail "a slow stage isn't keyed on its own flag in cicd.bash"
fi

## The run in the container can't start bash:3.2, so it skips those cases and
## the run outside does them.
fId dedm5 "bash 3.2 cases run outside the container"
bash32Body="$(sed -n '/^fStage_Shell_Bash32(){/,/^}/p' "${cicd}")"
installerBody="$(cat "${cicd%/cicd.bash}/utility/installer-test.bash")"
## In the image branch of fSteps, after the run in the image, since 2026102416233104.
imageBranch="$(sed -n '/^	if ((inImage)); then$/,/^	else$/p' <<< "${stepsBody}")"
# shellcheck disable=2016  ## Script text, looked for as written.
if grep -qF 'then fStage_Container; fi' <<< "${imageBranch}" && grep -qE '^[[:space:]]+fStep "Installers: bash 3.2" fStage_Shell_Bash32$' <<< "${imageBranch}" \
	&& (($(grep -n 'fStage_Container' <<< "${imageBranch}" | cut -d: -f1) < $(grep -n 'fStage_Shell_Bash32' <<< "${imageBranch}" | cut -d: -f1))) \
	&& grep -qF 'bash "${runner}" --only bash32' <<< "${bash32Body}" \
	&& grep -qF 'if [[ "${ZUID_IN_CONTAINER:-}" == "1" ]]; then' <<< "${installerBody}" \
	&& grep -A2 -F 'if [[ "${only}" == "bash32" ]]; then' <<< "${installerBody}" | grep -qE '^[[:space:]]+fCase_Bash32$'
	then fPass
	else fFail "the container run doesn't hand the bash 3.2 cases back to this machine"
fi

fId de5cq "--help on --leakcheck"
out="$(bash "${cicd}" --help 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"--leakcheck       Add the slow leak checks"* ]] && [[ "${out}" == *"every stage but --publish."* ]] && [[ "${out}" == *"--no-leakcheck    Leave"* ]]
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

fId ddye8 "full Linux x86_64 run packages"
out="$(fPackageIn Linux x86_64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddye9 "no llvm-objcopy, no package"
out="$(fPackageIn Linux x86_64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip=no llvm-objcopy"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddyea "full Mac run packages"
out="$(fPackageIn Darwin arm64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddyeb "other hosts skip packaging"
out="$(fPackageIn FreeBSD amd64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip="*"--package"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddyec "what turns packaging off"
out="$(fPackageIn Linux x86_64 with --quick; fPackageIn Linux x86_64 with --no-package; fPackageIn Linux x86_64 with --only go)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doPackage=0 skip=\ndoPackage=0 skip=\ndoPackage=0 skip=' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId ddyed "--package forces it"
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

fId ddyef "dogfood copies release files"
out="$(fDogfoodIn "${dogRoot}" 1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "$(cat "${dogRoot}/linux/zuid" 2>/dev/null)" == "linux-release" && "$(cat "${dogRoot}/mswin/zuid.exe" 2>/dev/null)" == "windows-release" ]] \
	&& [[ ! -e "${dogRoot}/macos" && ! -e "${dogRoot}/fallback/zuid" && "$(ls "${dogRoot}/linux")" == "zuid" ]]
	then fPass
	else fFail "exited ${rc}, said '${out//$'\n'/ | }'"
fi

fId ddyeg "dogfood falls back to zig-out"
out="$(fDogfoodIn "${dogRoot}" 0)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "$(cat "${dogRoot}/fallback/zuid" 2>/dev/null)" == "zig-out" && "$(cat "${dogRoot}/linux/zuid")" == "linux-release" ]]
	then fPass
	else fFail "exited ${rc}, said '${out//$'\n'/ | }'"
fi

## The container stage, with a stand-in for docker that logs what it was asked.
## Its image list has the current tag, the one before and an older one, out
## of order. ENGINE_VOLUMES names the volumes that are there already, and
## ENGINE_DF a file of sizes, one line per 'system df'.
cat > "${work}/engine" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ENGINE_LOG}"
case "$1 ${2:-}" in
	"image inspect") [[ -f "${ENGINE_LOG}.built-${3//[:\/]/_}" ]] ;;
	"build "*)       [[ "${ENGINE_BUILD_RC:-0}" == "0" ]] || exit "${ENGINE_BUILD_RC}"
	                 while (($#)) && [[ "$1" != "-t" ]]; do shift; done; : > "${ENGINE_LOG}.built-${2//[:\/]/_}" ;;
	"image ls")      if [[ "$3" == "zuid-codeql" ]]
		then printf '2026-10-01 01:00:00 -0700 PDT\tzuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld\n2026-10-24 01:00:00 -0700 PDT\t%s\n2026-10-12 01:00:00 -0700 PDT\tzuid-codeql:prevprevprev-prevprevprev\n' "${ENGINE_NEW_CODEQL:-}"
		else printf '2026-10-01 01:00:00 -0700 PDT\tzuid-cicd:0ld0ld0ld0ld\n2026-10-24 01:00:00 -0700 PDT\t%s\n2026-10-12 01:00:00 -0700 PDT\tzuid-cicd:prevprevprev\n2026-10-11 01:00:00 -0700 PDT\t<none>:<none>\n' "${ENGINE_NEW}"
		fi ;;
	"volume inspect") [[ " ${ENGINE_VOLUMES:-zuid-cicd-cache zuid-zig-cache} " == *" ${*: -1} "* ]] || exit 1
	                  if [[ "$3" == "--format" ]]; then printf '%s\n' "${ENGINE_VOLUME_LABEL:-}"; fi ;;
	"ps "*)          printf '%s' "${ENGINE_PS:-}" ;;
	"images "*)      printf '%s' "${ENGINE_DANGLING:-}" ;;
	"system df")     n="$(grep -c . "${ENGINE_LOG}.df" 2>/dev/null || true)"; echo x >> "${ENGINE_LOG}.df"
	                 sed -n "$(( ${n:-0} + 1 ))p" "${ENGINE_DF:-/dev/null}" | tr ' ' '\n' ;;
	"run "*)         if [[ "$*" == *"-cache-cap "* ]]; then printf '%s\n' "${ENGINE_CAP_OUT:-}"; fi
	                 exit "${ENGINE_RUN_RC:-0}" ;;
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
		# shellcheck disable=2329
		fFindSde(){ printf '%s' "${rigSde:-}"; }
		# shellcheck disable=2034  ## Read by the lifted fStage_Container.
		{
			repoRoot="$(cd "$1" && pwd -P)"; containerImage="zuid-cicd"; containerVolume="zuid-cicd-cache"; codeqlImage="zuid-codeql"
			containerZigVolume="zuid-zig-cache"; containerZigCache="/zig-cache"
			onlyToolchain="go"; doQuick="${quick:-1}"; doPackage=1; doLeakcheck="${leakcheck:-0}"; runStamp="20261019-101112"; _stepAt=2; _stepTotal=30
			doFuzz="${fuzz:-1}"; doProfile="${profile:-0}"
			projectName="zuid"; runName="20261019-101112"; keepTemp="${keep:-0}"; _dockerRun=""; buildJobs=3
			read -r -a runAreas <<< "${areasIn:-}"
		}
		local fn=""
		for fn in _fMustBeInPath fStage_Container fStep_UtcOffset fContainer_InnerArgs fContainer_Image fCodeql_Image fCodeql_Tag fContainer_Volumes fContainer_RunArgs; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		mkdir -p "${repoRoot}/cicd/container/codeql"
		echo "FROM scratch" > "${repoRoot}/cicd/container/Dockerfile"
		echo "FROM codeql" > "${repoRoot}/cicd/container/codeql/Dockerfile"
		# shellcheck disable=2030  ## Each case sets its own.
		export ZUID_DOCKER="${work}/engine" ENGINE_LOG="$2" ENGINE_RUN_RC="$3" TZ="ABC7"
		## The pre-push hook sets it, and the run lines below want it only when asked.
		unset ZIG_LOCAL_CACHE_DIR
		if [[ -n "${zigCache:-}" ]]; then export ZIG_LOCAL_CACHE_DIR="${zigCache}"; fi
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

fId ddrj0 "image built by recipe hash"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-main" 2>/dev/null || true)"
## Older tags wait for the end of a run that passed, since 2026102416233101.
if ((rc == 0)) && grep -qxF "build --label dev.project=zuid --label dev.run=20261019-101112 -t ${newTag} ${mainReal}/cicd/container" <<< "${log}" \
	&& ! grep -q "^rmi " <<< "${log}"
	then fPass
	else fFail "exited ${rc}, asked: ${log//$'\n'/ | }; said '${out}'"
fi

fId ddrj1 "container run arguments"
: > "${work}/engine-main"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-main")"
wantRun="run --rm --init --user $(id -u):$(id -g) -v ${mainReal}:${mainReal} -v zuid-cicd-cache:/cache -v zuid-zig-cache:/zig-cache"
wantRun+=" --name zuid-20261019-101112-container --label dev.project=zuid --label dev.run=20261019-101112 --cpus 3 --cpu-shares 256 -e ZUID_JOBS=3 -e ZUID_JOBS_CAP=3"
wantRun+=" -e ZUID_IN_CONTAINER=1 -e USER=${USER:-builder} -e ZUID_RUN_STAMP=20261019-101112 -e ZUID_STEP_FIRST=2 -e ZUID_STEP_TOTAL=30 -e ZUID_STEP_UTC_OFFSET=-25200"
wantRun+=" -w ${mainReal} ${newTag} ionice -c 3 nice -n 19 bash ${mainReal}/cicd/cicd.bash -q --no-sync --no-backup --no-dogfood --only go --quick --package --no-leakcheck"
if ((rc == 0)) && grep -qxF -- "${wantRun}" <<< "${log}" && ! grep -q '^build ' <<< "${log}"
	then fPass
	else fFail "exited ${rc}, asked: ${log//$'\n'/ | }"
fi

fId ddrj2 "worktree's git dir in the container"
out="$(fContainerIn "${worktreeDir}" "${work}/engine-wt" 0)" && rc=0 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* -v ${mainReal}/.git:${mainReal}/.git " "${work}/engine-wt"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-wt" || true)"
fi

fId ddrj3 "container failure fails the stage"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 3)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"The run in the container failed"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The run inside is a new cicd.bash, which only knows what it's handed.
fId de5cp "--container passes --leakcheck in"
: > "${work}/engine-main"
out="$(leakcheck=1 fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
: > "${work}/engine-noleak"
fContainerIn "${worktreeMain}" "${work}/engine-noleak" 0 >/dev/null 2>&1 || true
if ((rc == 0)) && grep -q -- "^run .* --only go --quick --package --leakcheck$" "${work}/engine-main" \
	&& grep -q -- "^run .* --only go --quick --package --no-leakcheck$" "${work}/engine-noleak"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-main" || true)"
fi

## A full run's --no-fuzz and --no-profile go in too. A quick one's --quick
## already covers them.
fId debng "--container passes --no-fuzz, --no-profile in"
: > "${work}/engine-slow"
out="$(quick=0 fuzz=0 profile=1 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0; quick=0 fuzz=1 profile=0 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0; quick=0 fuzz=1 profile=1 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0)" && rc=0 || rc=$?
runs="$(grep '^run ' "${work}/engine-slow" | sed 's/.* --only go //' || true)"
if ((rc == 0)) && [[ "${runs}" == $'--package --no-leakcheck --no-fuzz\n--package --no-leakcheck --no-profile\n--package --no-leakcheck' ]]
	then fPass
	else fFail "exited ${rc}, asked: ${runs//$'\n'/ | }"
fi

## A quick run fuzzes now, so --quick no longer says --no-fuzz for it.
fId dedv8 "--container passes --no-fuzz in on a quick run"
fuzzInner="$(
	fLoad fContainer_InnerArgs || exit 2
	# shellcheck disable=2034  ## Read by the lifted function.
	{ onlyToolchain=""; doQuick=1; doPackage=0; doLeakcheck=0; doProfile=0; keepTemp=0; runAreas=(); }
	for doFuzz in 1 0; do args=(); fContainer_InnerArgs args; printf '%s\n' "${args[*]}"; done
)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${fuzzInner}" == $'-q --no-sync --no-backup --no-dogfood --quick --no-leakcheck\n-q --no-sync --no-backup --no-dogfood --quick --no-leakcheck --no-fuzz' ]]
	then fPass
	else fFail "exited ${rc}, asked: ${fuzzInner//$'\n'/ | }"
fi

## The image has no time zone, so the run inside stamped its files in UTC and
## they sorted hours away from the host's.
fId de5gg "container run keeps the outer stamp"
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

## A section is a blank line, a rule of 79 dots, then the title, the way
## silkterm prints one. A terminal, a pipe and the image all get 79, since
## 2026102416233104. Before that the rule took the terminal's width.
fId de5h3 "stage header layout"
sectionScript="${work}/section.bash"
sectionBad=""
if (
	for fn in fEcho_Clean fSection; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2016  ## Expanded by the script, not here.
	{
		printf '%s\n' 'set -Eeuo pipefail' 'declare -i _wasLastEchoBlank=0' 'inContainer="${1:-0}"'
		grep -m1 '^declare -r _sectionRule=' "${cicd}"
		grep -E '^function fEcho\(\) ' "${cicd}"
		declare -f fEcho_Clean fSection
		printf '%s\n' 'fEcho_Clean "before"' 'fSection "A stage"'
	} > "${sectionScript}"
) > "${work}/section.out" 2>&1; then
	printf -v rule79 '%*s' 79 ''; rule79="${rule79// /•}"
	want="before"$'\n'$'\n'"${rule79}"$'\n'"[ A stage ]"
	got="$(bash "${sectionScript}" 0 | cat)"
	[[ "${got}" == "${want}" ]] || sectionBad+=" in a pipe it said '${got}';"
	got="$(ZUID_COLUMNS=101 bash "${sectionScript}" 1 | cat)"
	[[ "${got}" == "${want}" ]] || sectionBad+=" in the container it said '${got}';"
	## A terminal, from util-linux's script, sized by hand.
	if script --version 2>/dev/null | grep -q util-linux; then
		got="$(script -qec "stty cols 123 rows 40; bash '${sectionScript}' 0" /dev/null < /dev/null | tr -d '\r')"
		[[ "${got}" == *"${want}"* ]] || sectionBad+=" in a 123-wide terminal it said '${got}';"
	fi
else
	sectionBad+=" $(cat "${work}/section.out");"
fi
: > "${work}/engine-main"
fContainerIn "${worktreeMain}" "${work}/engine-main" 0 >/dev/null 2>&1 || true
if grep -q -- "^run .*ZUID_COLUMNS" "${work}/engine-main"; then sectionBad+=" the container was still handed a width;"; fi
if [[ -z "${sectionBad}" ]]
	then fPass
	else fFail "${sectionBad}"
fi

## Each step opens with a stamped "Step N of M; Starting" line and closes
## with PASS or FAIL. A step turned off isn't in M, and the first section
## lists it with its reason.
fId dedq5 "step lines"
stepBad=""
stepScript="${work}/steps.bash"
if (
	for fn in fEcho_Clean fSection fStep fStep_Off fStep_Fail fStep_Stamp fSteps_Plan fSteps_Print; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2016  ## Expanded by the script, not here.
	{
		printf '%s\n' 'set -Eeuo pipefail' 'declare -i _wasLastEchoBlank=0'
		grep -m1 '^declare -r _sectionRule=' "${cicd}"
		printf '%s\n' 'declare -a _stepTitles=() _stepOffs=()' 'declare -i _stepPlanning=0 _stepElsewhere=0 _stepAt=0 _stepTotal=0' 'declare _stepOpen=""'
		grep -E '^function (fEcho|fEcho_Force|fEcho_ResetBlankCounter)\(\) ' "${cicd}"
		declare -f fEcho_Clean fSection fStep fStep_Off fStep_Fail fStep_Stamp fSteps_Plan fSteps_Print
		printf '%s\n' 'fJobs_Recheck(){ :; }' 'fOne(){ echo one; }' 'fTwo(){ echo two; [[ "${1}" != fail ]] || exit 1; }'
		printf '%s\n' 'fSteps(){ fStep "One" fOne; fStep_Off "Off one" "--no-off"; _stepElsewhere=1; fStep "Inside" fOne; _stepElsewhere=0; fStep "Two" fTwo "${mode}"; }'
		printf '%s\n' 'mode="${1:-}"; trap fStep_Fail EXIT' 'fSteps_Plan; fSteps_Print; fSteps'
	} > "${stepScript}"
) > "${work}/steps.out" 2>&1; then
	printf -v rule79 '%*s' 79 ''; rule79="${rule79// /•}"
	ts='[0-9]{8}-[0-9]{6}\.[0-9]{2}'
	wantRe="^"$'\n'"${rule79}"$'\n'"\[ ${ts}: 3 steps, 1 turned off \]"$'\n'"Off \.+: Off one \(--no-off\)"$'\n'$'\n'"${rule79}"$'\n'"\[ ${ts}: Step 1 of 3; Starting One \]"$'\n'"one"$'\n'"\[ ${ts}: Step 1 of 3; PASS One \]"$'\n'$'\n'"${rule79}"$'\n'"\[ ${ts}: Step 3 of 3; Starting Two \]"$'\n'"two"$'\n'
	wantPass="${wantRe}\[ ${ts}: Step 3 of 3; PASS Two \]$"
	wantFail="${wantRe}\[ ${ts}: Step 3 of 3; FAIL Two \]"$'\n'$'\n'"end$"
	got="$(bash "${stepScript}" | cat)"
	[[ "${got}" =~ ${wantPass} ]] || stepBad+=" passing run said '${got}';"
	got="$(bash "${stepScript}" fail | cat; echo "end")"
	[[ "${got}" =~ ${wantFail} ]] || stepBad+=" failing run said '${got}';"
	## The image is on UTC, and takes the outside's offset.
	stampBad="$(
		for fn in fStep_Stamp fStep_UtcOffset; do fLoad "${fn}" || { echo "no ${fn}"; exit 0; }; done
		## Run in the image, the harness has the outside's.
		unset ZUID_STEP_UTC_OFFSET
		for zone in "ABC7" "XYZ-5:30" "UTC0"; do
			offset="$(TZ="${zone}" fStep_UtcOffset)"
			outside="$(TZ="${zone}" fStep_Stamp)"; inside="$(TZ=UTC0 ZUID_STEP_UTC_OFFSET="${offset}" fStep_Stamp)"
			[[ "${outside:0:13}" == "${inside:0:13}" ]] || echo "${zone} gave offset ${offset}, ${outside} outside and ${inside} inside;"
		done
	)"
	[[ -z "${stampBad}" ]] || stepBad+=" ${stampBad}"
else
	stepBad+=" $(cat "${work}/steps.out");"
fi
if [[ -z "${stepBad}" ]]
	then fPass
	else fFail "${stepBad}"
fi

## The run in the image numbers its steps on from the outside's, so the
## steps the outside counts for it have to be the ones it runs.
fId dedq6 "image's steps match the outside's count"
planBad=""
fPlanIn(){  ## inContainer, planContainer, then name=value settings
	(
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			inContainer="$1"; planContainer="$2"; doContainer=0; repoRoot="${work}/plan/repo"
			doSync=1; doGate=0; doFullGate=0; gateFlag=""; doQuick=0; doDemo=1; doPackage=0; noPackage=0; packageSkipWhy=""
			onlyToolchain=""; doGo=1; doZig=1; doFuzz=1; doCross=1; doLeakcheck=1; leakAsked=0; doProfile=1
			doPublish=0; doDogfood=1; doBackup=1; backupInWorktree=0; commitAsked=0; doCommit=0; doPush=0; doRemote=1
			freebsdBox="bsdtest@vmFreeBSD"; linuxArm64Box="tester@vmDebARM64"; macBox="collierjr@b26 collierjr@vmKt6m"; windowsBox="collierjr@b29w"
			_stepTitles=(); _stepOffs=(); _stepPlanning=0; _stepElsewhere=0; _stepAt=0; _stepTotal=0
			read -r -a runAreas <<< "${planAreas:-}"; areaWhy="not in --backlog-run-quick ${planAreas:-}"
		}
		shift 2
		local kv=""; for kv in "$@"; do printf -v "${kv%%=*}" '%s' "${kv#*=}"; done
		local fn=""
		for fn in fSteps fSteps_Checks fSteps_Scrub fSteps_FuzzWhy fSteps_Packages fSteps_Box fSteps_Plan fStep_Off fArea; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		## planUname stands in for the host's kernel name. Linux unless a case
		## names another, so the plan is the same on a Mac as here.
		# shellcheck disable=2329  ## Called by the lifted fSteps.
		uname(){ if [[ "${1:-}" == -s ]]; then printf '%s\n' "${planUname:-Linux}"; else command uname "$@"; fi; }
		## Marks the ones the image runs.
		# shellcheck disable=2329  ## Called by the lifted fSteps.
		fStep(){ if ((_stepPlanning)); then _stepTitles+=("$( ((_stepElsewhere)) && echo '*')$1"); fi; }
		fSteps_Plan
		printf '%s\n' "${_stepTitles[@]}"
		if [[ -n "${planOffs:-}" ]]; then printf 'off:%s\n' "${_stepOffs[@]}"; fi
	)
}
## A scrub beside the repo, which only this machine can see.
mkdir -p "${work}/plan/repo" "${work}/plan/private/hooks"
printf '#!/usr/bin/env bash\n' > "${work}/plan/private/hooks/scrub.bash"; chmod +x "${work}/plan/private/hooks/scrub.bash"
for planCase in "" "doQuick=1 doFuzz=0 doProfile=0 doLeakcheck=0 doDemo=0" "onlyToolchain=go doZig=0" "doPackage=1 doFuzz=0" "packageSkipWhy=no-llvm"; do
	# shellcheck disable=2086  ## Each case is a list of settings.
	outside="$(fPlanIn 0 1 ${planCase})" || { planBad+=" '${planCase}' outside: ${outside};"; continue; }
	insideWant="$(sed -n 's/^\*//p' <<< "${outside}")"
	## What the image's cicd.bash is handed, per fContainer_InnerArgs.
	innerCase="${planCase//packageSkipWhy=no-llvm/doPackage=1}"
	# shellcheck disable=2086
	inside="$(fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0 ${innerCase})" || { planBad+=" '${planCase}' inside: ${inside};"; continue; }
	[[ -n "${insideWant}" && "${inside}" == "${insideWant}" ]] || planBad+=" '${planCase}': outside counts '${insideWant//$'\n'/, }', inside runs '${inside//$'\n'/, }';"
	grep -qx "Content scrub" <<< "${inside}" && planBad+=" '${planCase}': the image can't see the scrub;"
	grep -qx "Content scrub" <<< "${outside}" || planBad+=" '${planCase}': this machine doesn't run the scrub;"
done
if [[ -z "${planBad}" ]]
	then fPass
	else fFail "${planBad}"
fi

## Areas narrow --backlog-run-quick to their steps, here and in the image
## alike, and the image's run is handed the same areas.
fId dedtx "areas pick the steps"
areaBad=""
## fMain sets doGo and doZig from the areas, which --list's case below covers.
for areaCase in "shell|doGo=0 doZig=0|Pipeline|Installers" "go docs|doZig=0|Content scrub|Bash: lint" "installers zig|doGo=0|Installers: bash 3.2|Docs: claims that can be counted"; do
	planAreas="${areaCase%%|*}"; rest="${areaCase#*|}"; toolchains="${rest%%|*}"; rest="${rest#*|}"; wantIn="${rest%%|*}"; wantOut="${rest#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planAreas="${planAreas}" fPlanIn 0 1 doGate=1 doQuick=1 doFuzz=0 doProfile=0 doLeakcheck=0 doDemo=0 ${toolchains})" || { areaBad+=" '${planAreas}': ${outside};"; continue; }
	# shellcheck disable=2086
	inside="$(planAreas="${planAreas}" fPlanIn 1 0 doGate=1 doQuick=1 doFuzz=0 doProfile=0 doLeakcheck=0 doDemo=0 doSync=0 doDogfood=0 doBackup=0 ${toolchains})" || { areaBad+=" '${planAreas}' inside: ${inside};"; continue; }
	plain="${outside//\*/}"
	grep -qxF "${wantIn}" <<< "${plain}" || areaBad+=" '${planAreas}' has no ${wantIn};"
	grep -q "^${wantOut}" <<< "${plain}" && areaBad+=" '${planAreas}' has ${wantOut};"
	[[ "${inside}" == "$(sed -n 's/^\*//p' <<< "${outside}")" ]] || areaBad+=" '${planAreas}': outside counts what inside doesn't run;"
done
## Preflight and the test IDs, whatever the areas.
outside="$(planAreas="docs" fPlanIn 0 1 doGate=1 doQuick=1)" || true
grep -qx '\*Preflight' <<< "${outside}" && grep -qx '\*Test IDs' <<< "${outside}" || areaBad+=" docs alone drops Preflight or Test IDs;"
inner="$(
	fLoad fContainer_InnerArgs || exit 2
	# shellcheck disable=2034  ## Read by the lifted function.
	{ onlyToolchain=""; doQuick=1; doPackage=0; doLeakcheck=0; doFuzz=0; doProfile=0; keepTemp=0; runAreas=(go docs); }
	args=(); fContainer_InnerArgs args; printf '%s\n' "${args[*]}"
)" || true
[[ "${inner}" == *" --backlog-run-quick go docs" ]] || areaBad+=" the image is handed '${inner}';"
if [[ -z "${areaBad}" ]]
	then fPass
	else fFail "${areaBad}"
fi

## --list prints the plan and each step's tests, and runs nothing, the run
## log included. Every test with an ID is in some step.
fId dedty "--list runs nothing, and names every test"
listBad=""
logsBefore="$(find "${cicd%/cicd.bash}/artifacts" -maxdepth 1 -newer "${cicd}" 2>/dev/null | sort || true)"
out="$(bash "${cicd}" --list --backlog-run-quick go --no-container < /dev/null 2>&1)" && rc=0 || rc=$?
((rc == 0)) || listBad+=" exited ${rc}: ${out:0:200};"
grep -qE '^[0-9]+\. Go: build, vet, format, test$' <<< "${out}" || listBad+=" no Go step;"
grep -qx '      daq6x TestVectors' <<< "${out}" || listBad+=" no TestVectors under it;"
grep -qE '^[0-9]+\. Zig' <<< "${out}" && listBad+=" a Zig step with only go named;"
grep -qE ' steps, [0-9]+ tests\. Nothing was run\.$' <<< "${out}" || listBad+=" no closing line;"
## As the outside plans it, since the run in the image never plans the steps
## only the outside runs, such as the macOS workflow's. And as Linux x86_64
## plans it, since a Mac leaves out the Mac box step and its tests.
listHost="${work}/list-host"
mkdir -p "${listHost}"
# shellcheck disable=2016  ## The stand-in's own text.
printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exec %q "$@" ;; esac\n' "$(command -v uname)" > "${listHost}/uname"
chmod +x "${listHost}/uname"
# shellcheck disable=2031  ## Only this run sees it.
out="$(PATH="${listHost}:${PATH}" env -u ZUID_IN_CONTAINER bash "${cicd}" --list --no-container --package --leakcheck < /dev/null 2>&1)" && rc=0 || rc=$?
((rc == 0)) || listBad+=" the full list exited ${rc};"
listed="$(sed -n 's/^      \([0-9a-hjkmnp-tv-z]\{5\}\) .*/\1/p' <<< "${out}" | sort -u)"
known="$(python3 -I -B -c 'import importlib.util as u, sys; s = u.spec_from_file_location("t", sys.argv[1]); t = u.module_from_spec(s); s.loader.exec_module(t); print("\n".join(sorted({i for i, *_ in t.fScan() if i})))' "${cicd%/cicd.bash}/utility/test-ids.py")"
missing="$(comm -13 <(printf '%s\n' "${listed}") <(printf '%s\n' "${known}") | tr '\n' ' ')"
[[ -n "${known}" && -z "${missing// /}" ]] || listBad+=" not in any step: ${missing:0:200};"
logsAfter="$(find "${cicd%/cicd.bash}/artifacts" -maxdepth 1 -newer "${cicd}" 2>/dev/null | sort || true)"
[[ "${logsAfter}" == "${logsBefore}" ]] || listBad+=" it wrote to cicd/artifacts;"
if [[ -z "${listBad}" ]]
	then fPass
	else fFail "${listBad}"
fi

## Only a run about as long as the Mac one on GitHub starts it, outside the
## image, and collects it after the image's steps.
fId dedwk "which runs start the macOS workflow"
hostedBad=""
for hostedCase in "|yes" "doGate=1 doQuick=1 gateFlag=--backlog-run-quick|--backlog-run-quick" "doQuick=1|--quick" "doRemote=0|--no-remote" "onlyToolchain=go doZig=0|--only go" "doFullGate=1 gateFlag=--merge-gate doSync=0|yes"; do
	hostedWant="${hostedCase#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planOffs=1 fPlanIn 0 1 ${hostedCase%%|*})" || { hostedBad+=" '${hostedCase}': ${outside};"; continue; }
	if [[ "${hostedWant}" == "yes" ]]; then
		## First after the sync, and last before publish.
		[[ "$(grep -v '^off:' <<< "${outside}" | grep -m1 -v '^Remote sync$')" == "macOS on GitHub: start" ]] || hostedBad+=" '${hostedCase}': start isn't first;"
		[[ "$(grep -v '^off:' <<< "${outside}" | sed -n '/^macOS on GitHub: result$/,$p' | grep -cvxE 'macOS on GitHub: result|Publish|Dogfood|Backup and publish|Commit|Push')" == "0" ]] \
			&& grep -qx 'macOS on GitHub: result' <<< "${outside}" || hostedBad+=" '${hostedCase}': result isn't after the checks;"
	else
		grep -q '^macOS on GitHub' <<< "${outside}" && hostedBad+=" '${hostedCase}' starts it;"
		grep -qxF "off:macOS on GitHub (${hostedWant})" <<< "${outside}" || hostedBad+=" '${hostedCase}' doesn't say it's off for ${hostedWant};"
	fi
done
inside="$(fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0)" || true
grep -q 'macOS on GitHub' <<< "${inside}" && hostedBad+=" the image starts it;"
if [[ -z "${hostedBad}" ]]
	then fPass
	else fFail "${hostedBad}"
fi

## The steps against a scratch repo pushed to a local bare remote, with gh
## stood in for. It's asked for only when the remote's branch is at HEAD, and
## only a finished run that failed fails the step.
fId dedwm "macOS workflow start and result"
hostedBad=""
hostedDir="${work}/hosted"
mkdir -p "${hostedDir}/bin"
cat > "${hostedDir}/bin/gh" <<'EOF_hgh'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${HOSTED_GH_LOG:?}"
case "${1:-} ${2:-}" in
	"workflow run") exit "${HOSTED_GH_DISPATCH:-0}" ;;
	"run list")     printf '%s\n' "${HOSTED_GH_RUN:-}"; exit 0 ;;
	"run view")     printf 'completed|%s|https://example.invalid/run/7\n' "${HOSTED_GH_CONCLUSION:?}"; exit 0 ;;
esac
exit 1
EOF_hgh
chmod +x "${hostedDir}/bin/gh"
git init -q --bare "${hostedDir}/remote.git"
git init -q -b round "${hostedDir}/repo"
git -C "${hostedDir}/repo" config user.name t
git -C "${hostedDir}/repo" config user.email t@t
mkdir -p "${hostedDir}/repo/.github/workflows"
printf 'name: macos\n' > "${hostedDir}/repo/.github/workflows/macos.yml"
git -C "${hostedDir}/repo" add -A
git -C "${hostedDir}/repo" commit -q -m first
git -C "${hostedDir}/repo" remote add origin "${hostedDir}/remote.git"
git -C "${hostedDir}/repo" push -q -u origin round 2>/dev/null
fHostedIn(){  ## then the result's lines follow the start's
	(
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ repoRoot="${hostedDir}/repo"; hostedSha=""; hostedBranch=""; hostedSince=""; hostedSkipWhy=""; hostedWorkflow="macos.yml"; hostedCapSecs=60; }
		local fn=""
		for fn in fGh fHosted_Gh fStage_Hosted_Start fStage_Hosted_Result fId fTestPass fTestSkip fTestFail; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2329  ## Called by the lifted functions.
		{ fEcho_Clean(){ printf '%s\n' "$*"; }; fThrowError(){ printf 'error: %s\n' "$1"; exit 1; }; sleep(){ :; }; }
		: > "${HOSTED_GH_LOG}"
		fStage_Hosted_Start
		fStage_Hosted_Result
	) 2>&1
}
export HOSTED_GH_LOG="${hostedDir}/gh.log"
## Pushed, and GitHub says it passed.
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_RUN=7 HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS dedwh macOS workflow started on GitHub' <<< "${out}" && grep -qx '  PASS dedwj macOS workflow passed on GitHub' <<< "${out}"; } || hostedBad+=" passed: exited ${rc}, said '${out//$'\n'/ | }';"
grep -qx 'workflow run macos.yml --ref round' "${HOSTED_GH_LOG}" || hostedBad+=" passed: not asked for on the branch;"
grep -q "^run list .*--branch round --event workflow_dispatch --commit $(git -C "${hostedDir}/repo" rev-parse HEAD) " "${HOSTED_GH_LOG}" || hostedBad+=" passed: the run looked for isn't HEAD's dispatch;"
## It failed there, which fails the step.
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_RUN=7 HOSTED_GH_CONCLUSION=failure GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -qx '  FAIL dedwj macOS workflow passed on GitHub' <<< "${out}"; } || hostedBad+=" failed: exited ${rc}, said '${out//$'\n'/ | }';"
## Cancelled for a newer run, or never listed, is a skip.
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_RUN=7 HOSTED_GH_CONCLUSION=cancelled GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dedwj .*(cancelled on GitHub' <<< "${out}"; } || hostedBad+=" cancelled: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_RUN="" HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dedwj .*(GitHub listed no run' <<< "${out}"; } || hostedBad+=" unlisted: exited ${rc}, said '${out//$'\n'/ | }';"
## gh refused, which is a skip in both steps.
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_DISPATCH=1 HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "$(grep -c '^  SKIP dedw[hj] .*(gh could not start it' <<< "${out}")" == "2" ]]; } || hostedBad+=" refused: exited ${rc}, said '${out//$'\n'/ | }';"
## On a runner already, it never asks.
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS=true fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dedwh .*(already on a GitHub runner)$' <<< "${out}" && ! grep -q '^workflow run' "${HOSTED_GH_LOG}"; } || hostedBad+=" runner: exited ${rc}, said '${out//$'\n'/ | }';"
## A commit the remote doesn't have yet.
git -C "${hostedDir}/repo" commit -q --allow-empty -m second
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q "^  SKIP dedwh .*(origin/round isn't at HEAD .*, so push first)$" <<< "${out}" && grep -q '^  SKIP dedwj ' <<< "${out}" && ! grep -q '^workflow run' "${HOSTED_GH_LOG}"; } || hostedBad+=" unpushed: exited ${rc}, said '${out//$'\n'/ | }';"
## Detached, so no branch to name.
git -C "${hostedDir}/repo" checkout -q --detach
out="$(ZUID_GH="${hostedDir}/bin/gh" HOSTED_GH_CONCLUSION=success GITHUB_ACTIONS="" fHostedIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dedwh .*(HEAD is detached' <<< "${out}"; } || hostedBad+=" detached: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${hostedBad}" ]]
	then fPass
	else fFail "${hostedBad}"
fi

## The FreeBSD box tests what Package made, outside the image, unless
## --no-remote or its destination is empty.
fId dee34 "which runs test on the FreeBSD box"
boxBad=""
for boxCase in "doPackage=1|yes" "doPackage=1 doFullGate=1 gateFlag=--merge-gate doSync=0|yes" "doPackage=1 doRemote=0|--no-remote" "doPackage=1 freebsdBox=|ZUID_BOX_FREEBSD is empty" "doQuick=1|nothing packaged" "onlyToolchain=go doZig=0|nothing packaged"; do
	boxWant="${boxCase#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planAreas="" planOffs=1 fPlanIn 0 1 ${boxCase%%|*})" || { boxBad+=" '${boxCase}': ${outside};"; continue; }
	if [[ "${boxWant}" == "yes" ]]; then
		grep -v '^off:' <<< "${outside}" | sed -n '/^\*\{0,1\}Package$/,$p' | grep -qx 'FreeBSD box: vmFreeBSD' || boxBad+=" '${boxCase}': it isn't after Package, in '${outside//$'\n'/, }';"
	else
		grep -q '^FreeBSD box' <<< "${outside}" && boxBad+=" '${boxCase}' runs it;"
		grep -qxF "off:FreeBSD box (${boxWant})" <<< "${outside}" || boxBad+=" '${boxCase}' doesn't say it's off for ${boxWant};"
	fi
done
inside="$(planAreas="" fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0 doPackage=1)" || true
grep -q 'FreeBSD box' <<< "${inside}" && boxBad+=" the image runs it;"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The same for the Linux arm64 box, which comes after the FreeBSD one.
fId dee7n "which runs test on the Linux arm64 box"
boxBad=""
for boxCase in "doPackage=1|yes" "doPackage=1 doFullGate=1 gateFlag=--merge-gate doSync=0|yes" "doPackage=1 doRemote=0|--no-remote" "doPackage=1 linuxArm64Box=|ZUID_BOX_LINUX_ARM64 is empty" "doQuick=1|nothing packaged" "onlyToolchain=go doZig=0|nothing packaged"; do
	boxWant="${boxCase#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planAreas="" planOffs=1 fPlanIn 0 1 ${boxCase%%|*})" || { boxBad+=" '${boxCase}': ${outside};"; continue; }
	if [[ "${boxWant}" == "yes" ]]; then
		grep -v '^off:' <<< "${outside}" | sed -n '/^FreeBSD box: vmFreeBSD$/,$p' | grep -qx 'Linux arm64 box: vmDebARM64' || boxBad+=" '${boxCase}': it isn't after the FreeBSD box, in '${outside//$'\n'/, }';"
	else
		grep -q '^Linux arm64 box' <<< "${outside}" && boxBad+=" '${boxCase}' runs it;"
		grep -qxF "off:Linux arm64 box (${boxWant})" <<< "${outside}" || boxBad+=" '${boxCase}' doesn't say it's off for ${boxWant};"
	fi
done
## Emptying one box's destination leaves the other running.
outside="$(planAreas="" planOffs=1 fPlanIn 0 1 doPackage=1 freebsdBox=)" || true
grep -qx 'Linux arm64 box: vmDebARM64' <<< "${outside}" || boxBad+=" no FreeBSD box took the arm64 one too;"
inside="$(planAreas="" fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0 doPackage=1)" || true
grep -q 'Linux arm64 box' <<< "${inside}" && boxBad+=" the image runs it;"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The Mac box comes after the arm64 one, outside the image, and never on a Mac.
fId dee8m "which runs build on the Mac box"
boxBad=""
for boxCase in "doPackage=1|yes" "doPackage=1 doFullGate=1 gateFlag=--merge-gate doSync=0|yes" "doPackage=1 doRemote=0|--no-remote" "doPackage=1 macBox=|ZUID_BOX_MAC is empty" "doQuick=1|nothing packaged" "onlyToolchain=go doZig=0|nothing packaged" "doPackage=1 planUname=Darwin|this Mac makes its own universal release"; do
	boxWant="${boxCase#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planAreas="" planOffs=1 fPlanIn 0 1 ${boxCase%%|*})" || { boxBad+=" '${boxCase}': ${outside};"; continue; }
	if [[ "${boxWant}" == "yes" ]]; then
		grep -v '^off:' <<< "${outside}" | sed -n '/^Linux arm64 box: vmDebARM64$/,$p' | grep -qx 'Mac box: b26 or vmKt6m' || boxBad+=" '${boxCase}': it isn't after the arm64 box, in '${outside//$'\n'/, }';"
	else
		grep -q '^Mac box' <<< "${outside}" && boxBad+=" '${boxCase}' runs it;"
		grep -qxF "off:Mac box (${boxWant})" <<< "${outside}" || boxBad+=" '${boxCase}' doesn't say it's off for ${boxWant};"
	fi
done
outside="$(planAreas="" planOffs=1 fPlanIn 0 1 doPackage=1 freebsdBox= linuxArm64Box=)" || true
grep -qx 'Mac box: b26 or vmKt6m' <<< "${outside}" || boxBad+=" no other boxes took the Mac one too;"
inside="$(planAreas="" fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0 doPackage=1)" || true
grep -q 'Mac box' <<< "${inside}" && boxBad+=" the image runs it;"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The Windows box comes after the Mac one, outside the image.
fId deea6 "which runs test on the Windows box"
boxBad=""
for boxCase in "doPackage=1|yes" "doPackage=1 doFullGate=1 gateFlag=--merge-gate doSync=0|yes" "doPackage=1 doRemote=0|--no-remote" "doPackage=1 windowsBox=|ZUID_BOX_WINDOWS is empty" "doQuick=1|nothing packaged" "onlyToolchain=go doZig=0|nothing packaged"; do
	boxWant="${boxCase#*|}"
	# shellcheck disable=2086  ## Settings, split on purpose.
	outside="$(planAreas="" planOffs=1 fPlanIn 0 1 ${boxCase%%|*})" || { boxBad+=" '${boxCase}': ${outside};"; continue; }
	if [[ "${boxWant}" == "yes" ]]; then
		grep -v '^off:' <<< "${outside}" | sed -n '/^Mac box: b26 or vmKt6m$/,$p' | grep -qx 'Windows box: b29w' || boxBad+=" '${boxCase}': it isn't after the Mac box, in '${outside//$'\n'/, }';"
	else
		grep -q '^Windows box' <<< "${outside}" && boxBad+=" '${boxCase}' runs it;"
		grep -qxF "off:Windows box (${boxWant})" <<< "${outside}" || boxBad+=" '${boxCase}' doesn't say it's off for ${boxWant};"
	fi
done
outside="$(planAreas="" planOffs=1 fPlanIn 0 1 doPackage=1 freebsdBox= linuxArm64Box= macBox=)" || true
grep -qx 'Windows box: b29w' <<< "${outside}" || boxBad+=" no other boxes took the Windows one too;"
inside="$(planAreas="" fPlanIn 1 0 doSync=0 doDogfood=0 doBackup=0 doPackage=1)" || true
grep -q 'Windows box' <<< "${inside}" && boxBad+=" the image runs it;"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The box step end to end, with ssh and the host lock stood in for. ssh runs
## its command here, so the box's temp root is a folder of the test's own.
fId dee35 "a box step passes, fails, or skips when the box is down or taken"
boxBad=""
boxDir="${work}/box"
mkdir -p "${boxDir}/bin" "${boxDir}/root" "${boxDir}/dist" "${boxDir}/run"
cat > "${boxDir}/bin/ssh" <<'EOF_bssh'
#!/usr/bin/env bash
while [[ "${1:-}" == -o ]]; do shift 2; done
## BOX_DOWN_AT lists the destinations that don't answer.
[[ " ${BOX_DOWN_AT:-} " != *" ${1} "* ]] || exit 255
shift
[[ "${BOX_DOWN:-0}" != 1 ]] || exit 255
## The powershell beside it, for the Windows box.
PATH="$(dirname "$0"):${PATH}" HOST_TEMP="${BOX_ROOT:?}" exec bash -c "$*"
EOF_bssh
printf '#!/usr/bin/env bash\nexec pwsh "$@"\n' > "${boxDir}/bin/powershell"
cat > "${boxDir}/bin/lock" <<'EOF_block'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${BOX_LOCK_LOG:?}"
[[ "${BOX_TAKEN:-0}" != 1 ]] || exit 3
[[ " ${BOX_TAKEN_AT:-} " != *" ${2:-} "* ]] || exit 3
while [[ "${1:-}" != -- ]]; do shift; done
shift
exec "$@"
EOF_block
chmod +x "${boxDir}/bin/ssh" "${boxDir}/bin/lock" "${boxDir}/bin/powershell"
export BOX_ROOT="${boxDir}/root" BOX_LOCK_LOG="${boxDir}/lock.log"
## Always called in $(...), so a brace group is subshell enough.
fBoxIn(){  ## job.bash's text, in BOX_JOB
	{
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ repoRoot="${boxDir}"; utilityDir="$(cd "$(dirname "${cicd}")" && pwd -P)/utility"
		  zigDir="${boxDir}/zig"; distPrefix="zuid-1.0.0-"; freebsdBox="bsdtest@vmFreeBSD"; linuxArm64Box="tester@vmDebARM64"; boxWaitSecs=60; keepTemp=0
		  macBox="${BOX_MAC:-collierjr@b26}"; windowsBox="collierjr@b29w"; incomingDir="${boxDir}/dist-incoming"
		  projectName="zuid"; runName="test"; _stepSkipWhy=""; }
		_runDir="${boxDir}/run"
		local fn=""
		for fn in fBox_Lock fBox_Skip fBox_Run fBox_Release fBox_Pkg fBox_PkgHome fPkg_IntoDist fPkg_Here fBox_MacHome fStage_Box_FreeBSD fStage_Box_LinuxArm64 fStage_Box_Mac fStage_Box_Windows fStep_Skip fId fTestPass fTestSkip fTestFail; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2329  ## Called by the lifted functions.
		{ fEcho_Clean(){ printf '%s\n' "$*"; }; fThrowError(){ printf 'error: %s\n' "$1"; exit 1; }; }
		## The image, in BOX_HERE: unset is no image, else what its pkg writes,
		## or "fail". The last argument is pkg create's -o.
		# shellcheck disable=2329
		{ fGoCheckers_Ready(){ checkerSkipWhy=""; [[ -n "${BOX_HERE:-}" ]] || checkerSkipWhy="no image"; }
		  fInImage(){ printf '%s\n' "$*" > "${boxDir}/inimage.args"; [[ "${BOX_HERE}" != fail ]] || return 1; printf '%b' "${BOX_HERE}" > "${*: -1}/zuid-1.0.0.pkg"; }; }
		## The job is a stand-in, not the real one.
		# shellcheck disable=2329
		cp(){ if [[ "${1##*/}" == box-release-test.bash || "${1##*/}" == box-mac-build.bash || "${1##*/}" == box-windows-test.ps1 ]]; then printf '%s\n' "${BOX_JOB:?}" > "$2"
		      elif [[ "${1##*/}" == box-freebsd-pkg.bash ]]; then printf '%s\n' "${BOX_PKG_JOB:-mkdir back && printf pkg > back/zuid-1.0.0-freebsd-x86_64.pkg}" > "$2"
		      else command cp "$@"; fi; }
		local jobName="box-freebsd-x86_64"; [[ "${BOX_STAGE:-}" != fStage_Box_LinuxArm64 ]] || jobName="box-linux-arm64"
		[[ "${BOX_STAGE:-}" != fStage_Box_Windows ]] || jobName="box-windows-x86_64"
		## The Mac bundles a repo of its own.
		if [[ "${BOX_STAGE:-}" == fStage_Box_Mac ]]; then jobName="box-darwin-universal"; repoRoot="${boxDir}/src"; fi
		if [[ -d "${_runDir}/${jobName}" ]]; then fSafeRm "${_runDir}/${jobName}"; fi
		if [[ -d "${_runDir}/${jobName}.back" ]]; then fSafeRm "${_runDir}/${jobName}.back"; fi
		if [[ -d "${_runDir}/${jobName}-pkg" ]]; then fSafeRm "${_runDir}/${jobName}-pkg"; fi
		if [[ -d "${_runDir}/${jobName}-pkg.back" ]]; then fSafeRm "${_runDir}/${jobName}-pkg.back"; fi
		: > "${BOX_LOCK_LOG}"
		"${BOX_STAGE:-fStage_Box_FreeBSD}"
		printf 'skipwhy:%s\n' "${_stepSkipWhy}"
	} 2>&1
}
mkdir -p "${boxDir}/zig/lib/test" "${boxDir}/testdata"
: > "${boxDir}/zig/lib/test/capi_smoke.c"; : > "${boxDir}/testdata/errors.tsv"
## No release yet.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee33 .*(no zuid-1.0.0-freebsd-x86_64.tgz in dist/)$' <<< "${out}" && grep -q '^skipwhy:no ' <<< "${out}"; } || boxBad+=" no release: exited ${rc}, said '${out//$'\n'/ | }';"
printf 'x\n' > "${boxDir}/dist/zuid-1.0.0-freebsd-x86_64.tgz"
mkdir -p "${boxDir}/dist/pkg/zuid-1.0.0-freebsd-x86_64/root"
## Passes, under the lock, and the box's folder is gone after.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='[[ -f zuid-1.0.0-freebsd-x86_64.tgz && -f cicd/utility/cli-test.bash ]]' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS dee33 FreeBSD release on its box: command surface and C module' <<< "${out}" && grep -qx 'skipwhy:' <<< "${out}"; } || boxBad+=" pass: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap vmFreeBSD --wait 60 --why zuid: cicd test -- bash .*/box-run.bash bsdtest@vmFreeBSD ' "${BOX_LOCK_LOG}" || boxBad+=" pass: not held through the lock;"
grep -q "^Box \.*: bsdtest@vmFreeBSD:${boxDir}/root/zuid/[0-9]\{8\}-[0-9]\{6\}_[0-9]\{3\}$" <<< "${out}" || boxBad+=" pass: no work folder of its own;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" pass: the box's folder is still there;"
## The job fails, which fails the step.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 3' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -qx '  FAIL dee33 FreeBSD release on its box: command surface and C module' <<< "${out}" && grep -q 'exited 3' <<< "${out}"; } || boxBad+=" fail: exited ${rc}, said '${out//$'\n'/ | }';"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" fail: the box's folder is still there;"
## Down, or taken past the wait, is a skip that the step ends on.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee33 .*(no answer from bsdtest@vmFreeBSD)$' <<< "${out}" && grep -qx 'skipwhy:no answer from bsdtest@vmFreeBSD' <<< "${out}"; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_TAKEN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee33 .*(vmFreeBSD stayed taken for 1 minutes)$' <<< "${out}"; } || boxBad+=" taken: exited ${rc}, said '${out//$'\n'/ | }';"
## No lock here, which says so and runs anyway.
out="$(ZUID_BOX_LOCK="" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q "isn't held" <<< "${out}" && grep -q '^  PASS dee33 ' <<< "${out}" && [[ ! -s "${BOX_LOCK_LOG}" ]]; } || boxBad+=" no lock: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## FreeBSD's .pkg: package.bash's layout goes to the same box as root, and the
## .pkg comes home into dist/ and its checksums.txt. A box that skipped the
## release test skips this too.
fId defn2 "the FreeBSD box step makes the .pkg as root and brings it into dist/"
boxBad=""
pkgKit="${boxDir}/dist/pkg/zuid-1.0.0-freebsd-x86_64"
pkgHome="${boxDir}/dist/zuid-1.0.0-freebsd-x86_64.pkg"
printf 'pin\n' > "${pkgKit}/manifest.ucl"
## pkg puts each file's mtime in the package, so the layout's settled times
## have to get to the box as they are.
find "${pkgKit}" -exec touch -h -t 202001010000 {} +
rm -f "${pkgHome}"; printf 'aaa  zuid-1.0.0-freebsd-x86_64.tgz\n' > "${boxDir}/dist/checksums.txt"
# shellcheck disable=2016  ## Run by the box stand-in.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' \
	BOX_PKG_JOB='[[ "$(cat zuid-1.0.0-freebsd-x86_64/manifest.ucl)" == pin && -d zuid-1.0.0-freebsd-x86_64/root && ! -e zuid-1.0.0-freebsd-x86_64.tgz && -z "$(find zuid-1.0.0-freebsd-x86_64 -newermt 2020-01-02)" ]] && mkdir back && printf made > back/zuid-1.0.0-freebsd-x86_64.pkg' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS defmv FreeBSD .pkg made and installed on its box, back in dist/' <<< "${out}" && grep -qx 'skipwhy:' <<< "${out}"; } || boxBad+=" pass: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap vmFreeBSD --wait 60 --why zuid: cicd test -- bash .*/box-run.bash root@vmFreeBSD .*/box-freebsd-x86_64-pkg ' "${BOX_LOCK_LOG}" || boxBad+=" pass: not run as root under the lock;"
[[ "$(cat "${pkgHome}" 2>/dev/null)" == made && "$(ls -l "${pkgHome}")" == -rw-r--r--* ]] || boxBad+=" pass: no .pkg in dist/, or not 644;"
grep -qx "$(shasum -a 256 "${pkgHome}" | awk '{print $1}')  zuid-1.0.0-freebsd-x86_64.pkg" "${boxDir}/dist/checksums.txt" || boxBad+=" pass: not in checksums.txt;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" pass: the box's folder is still there;"
## The job fails, or sends nothing home.
rm -f "${pkgHome}"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' BOX_PKG_JOB='exit 4' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -qx '  FAIL defmv FreeBSD .pkg made and installed on its box, back in dist/' <<< "${out}" && grep -q 'exited 4' <<< "${out}" && [[ ! -e "${pkgHome}" ]]; } || boxBad+=" fail: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' BOX_PKG_JOB='mkdir back' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -q 'sent no zuid-1.0.0-freebsd-x86_64.pkg home' <<< "${out}"; } || boxBad+=" nothing home: exited ${rc}, said '${out//$'\n'/ | }';"
## The release test skipped, so this does too, and asks no box.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP defmv .*(no answer from bsdtest@vmFreeBSD)$' <<< "${out}" && [[ "$(grep -c '^wrap ' "${BOX_LOCK_LOG}")" == 1 ]]; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
## No layout from package.bash is its fault, not the box's.
mv "${pkgKit}" "${pkgKit}.away"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
mv "${pkgKit}.away" "${pkgKit}"
{ ((rc != 0)) && grep -qx '  FAIL defmv FreeBSD .pkg made and installed on its box, back in dist/' <<< "${out}" && grep -q 'laid out no pkg/' <<< "${out}"; } || boxBad+=" no layout: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The image's pkg makes the same .pkg: it has to be the box's, byte for byte,
## and goes in dist/ when the box made none, if it's zstd.
fId defp4 "the FreeBSD box step makes the .pkg here too, and uses it without the box's"
boxBad=""
printf 'abi: "FreeBSD:*:amd64"\n' > "${pkgKit}/manifest.ucl"; printf '1700000000\n' > "${pkgKit}/stamp"
zst='\x28\xb5\x2f\xfdzst'
## The box is down, so the one made here goes in dist/ and checksums.txt.
rm -f "${pkgHome}" "${boxDir}/inimage.args"; printf 'aaa  zuid-1.0.0-freebsd-x86_64.tgz\n' > "${boxDir}/dist/checksums.txt"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' BOX_HERE="${zst}" fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP defmv ' <<< "${out}" && grep -qx '  PASS defp3 FreeBSD .pkg made here, the box'"'"'s bytes, or in dist/ without one' <<< "${out}"; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
[[ "$(head -c 4 "${pkgHome}" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == 28b52ffd && "$(ls -l "${pkgHome}")" == -rw-r--r--* ]] || boxBad+=" down: no .pkg in dist/, or not 644;"
grep -qx "$(shasum -a 256 "${pkgHome}" | awk '{print $1}')  zuid-1.0.0-freebsd-x86_64.pkg" "${boxDir}/dist/checksums.txt" || boxBad+=" down: not in checksums.txt;"
grep -qF "/here-freebsd-x86_64-pkg env ABI=FreeBSD:14:amd64 OSVERSION=1400000 /opt/fbsdpkg/pkg create -t 1700000000 -M ${pkgKit}/manifest.ucl -p ${pkgKit}/plist -r ${pkgKit}/root -o " "${boxDir}/inimage.args" || boxBad+=" down: pkg create called as '$(cat "${boxDir}/inimage.args" 2>/dev/null || true)';"
## Made here as xz, or not made, with no box's to go by.
rm -f "${pkgHome}"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' BOX_HERE='\xfd7zXZ' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -q "isn't zstd, it starts fd377a58" <<< "${out}" && [[ ! -e "${pkgHome}" ]]; } || boxBad+=" xz: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' BOX_HERE=fail fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -qx '  FAIL defp3 FreeBSD .pkg made here, the box'"'"'s bytes, or in dist/ without one' <<< "${out}" && grep -q 'pkg create failed here' <<< "${out}"; } || boxBad+=" failed: exited ${rc}, said '${out//$'\n'/ | }';"
## The box made one: the same bytes pass and leave the box's, others fail.
printf 'aaa  zuid-1.0.0-freebsd-x86_64.tgz\n' > "${boxDir}/dist/checksums.txt"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' BOX_PKG_JOB='mkdir back && printf made > back/zuid-1.0.0-freebsd-x86_64.pkg' BOX_HERE=made fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  PASS defmv ' <<< "${out}" && grep -q '^  PASS defp3 ' <<< "${out}" && [[ "$(cat "${pkgHome}")" == made && "$(grep -c 'zuid-1.0.0-freebsd-x86_64.pkg$' "${boxDir}/dist/checksums.txt")" == 1 ]]; } || boxBad+=" same: exited ${rc}, said '${out//$'\n'/ | }';"
rm -f "${pkgHome}"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' BOX_PKG_JOB='mkdir back && printf made > back/zuid-1.0.0-freebsd-x86_64.pkg' BOX_HERE="${zst}" fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -q "isn't the box's, byte for byte" <<< "${out}" && [[ "$(cat "${pkgHome}")" == made ]]; } || boxBad+=" differs: exited ${rc}, said '${out//$'\n'/ | }';"
## No image here is a skip.
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  SKIP defp3 FreeBSD .pkg made here, the box'"'"'s bytes, or in dist/ without one (no image)' <<< "${out}"; } || boxBad+=" no image: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The Linux arm64 box step sends its own release to its own box, under the
## lock by that box's name, and skips without one.
fId dee7p "the Linux arm64 box step sends its release to vmDebARM64"
boxBad=""
out="$(BOX_STAGE=fStage_Box_LinuxArm64 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee7m .*(no zuid-1.0.0-linux-arm64.tgz in dist/)$' <<< "${out}"; } || boxBad+=" no release: exited ${rc}, said '${out//$'\n'/ | }';"
printf 'x\n' > "${boxDir}/dist/zuid-1.0.0-linux-arm64.tgz"
out="$(BOX_STAGE=fStage_Box_LinuxArm64 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='[[ -f zuid-1.0.0-linux-arm64.tgz && ! -e zuid-1.0.0-freebsd-x86_64.tgz && -f cicd/utility/cli-test.bash && -f capi_smoke.c ]]' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS dee7m Linux arm64 release on its box: command surface and C module' <<< "${out}"; } || boxBad+=" pass: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap vmDebARM64 --wait 60 --why zuid: cicd test -- bash .*/box-run.bash tester@vmDebARM64 ' "${BOX_LOCK_LOG}" || boxBad+=" pass: not held through the lock by its own name;"
grep -q "^Box \.*: tester@vmDebARM64:${boxDir}/root/zuid/[0-9]\{8\}-[0-9]\{6\}_[0-9]\{3\}$" <<< "${out}" || boxBad+=" pass: no work folder of its own;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" pass: the box's folder is still there;"
out="$(BOX_STAGE=fStage_Box_LinuxArm64 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee7m .*(no answer from tester@vmDebARM64)$' <<< "${out}"; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The emulated arm64 box gets cli-test.bash's short run, and FreeBSD the whole.
## The job hands what the step asked for to cli-test.bash.
fId dee9h "the Linux arm64 box runs cli-test.bash --short, FreeBSD all of it"
boxBad=""
# shellcheck disable=2016  ## Run by the box stand-in.
out="$(BOX_STAGE=fStage_Box_LinuxArm64 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='[[ "$(cat cli-test.args)" == --short ]]' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  PASS dee7m ' <<< "${out}"; } || boxBad+=" arm64: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='[[ ! -e cli-test.args ]]' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  PASS dee33 ' <<< "${out}"; } || boxBad+=" FreeBSD: exited ${rc}, said '${out//$'\n'/ | }';"
## The real job, with a stand-in release and cli-test.bash, stopped at the C
## compiler.
fBoxJobArgs(){  ## cli-test.args text, or - for none
	local -r jobDir="${work}/box-job"
	if [[ -d "${jobDir}" ]]; then fSafeRm "${jobDir}"; fi
	mkdir -p "${jobDir}/pack/zuid-v1/bin" "${jobDir}/cicd/utility"
	printf '#!/usr/bin/env bash\necho zuid v1\n' > "${jobDir}/pack/zuid-v1/bin/zuid"
	chmod +x "${jobDir}/pack/zuid-v1/bin/zuid"
	tar -czf "${jobDir}/zuid-1-test.tgz" -C "${jobDir}/pack" zuid-v1
	printf 'printf "%%s|" "$@" > cli.args\n' > "${jobDir}/cicd/utility/cli-test.bash"
	cp "${cicd%/*}/utility/box-release-test.bash" "${jobDir}/job.bash"
	[[ "$1" == - ]] || printf '%s\n' "$1" > "${jobDir}/cli-test.args"
	(cd "${jobDir}" && CC="${jobDir}/no-cc" bash ./job.bash > /dev/null 2>&1) || true
	cat "${jobDir}/cli.args" 2>/dev/null || printf 'none'
}
out="$(fBoxJobArgs --short)"; [[ "${out}" == "--bin|${work}/box-job/zuid-v1/bin/zuid|--short|" ]] || boxBad+=" job with --short ran '${out}';"
out="$(fBoxJobArgs -)";       [[ "${out}" == "--bin|${work}/box-job/zuid-v1/bin/zuid|" ]]         || boxBad+=" job with no args ran '${out}';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The Mac builds from a bundle of HEAD, and what it sends home goes in
## dist-incoming/, replacing an earlier run's.
fId dee8n "the Mac box step builds from HEAD and brings its release home"
boxBad=""
mkdir -p "${boxDir}/src"
git -C "${boxDir}/src" init -q
printf 'mac\n' > "${boxDir}/src/f"
git -C "${boxDir}/src" add f
git -C "${boxDir}/src" -c user.name=t -c user.email=t@t.invalid commit -q -m t
macRel="zuid-1.0.0-darwin-universal"
## The stand-in job, which writes <n> into what it sends home.
fMacJob(){ printf 'git clone -q src.bundle r && [[ -f r/f ]] && mkdir -p back/debug/%s && echo %s > back/%s.tgz && echo b > back/%s && echo %s > back/debug/%s/zuid.dSYM\n' \
	"${macRel}" "$1" "${macRel}" "${macRel}" "$1" "${macRel}" ;}
out="$(BOX_STAGE=fStage_Box_Mac ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB="$(fMacJob 1)" fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS dee8k macOS universal release built on its box, back in dist-incoming/' <<< "${out}"; } || boxBad+=" pass: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap b26 --wait 60 --why zuid: cicd test -- bash .*/box-run.bash collierjr@b26 ' "${BOX_LOCK_LOG}" || boxBad+=" pass: not held through the lock as b26;"
[[ -f "${boxDir}/dist-incoming/${macRel}.tgz" && -f "${boxDir}/dist-incoming/${macRel}" && -f "${boxDir}/dist-incoming/debug/${macRel}/zuid.dSYM" ]] || boxBad+=" pass: not all of it reached dist-incoming/;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" pass: the box's folder is still there;"
## A second run replaces the first one's files.
out="$(BOX_STAGE=fStage_Box_Mac ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB="$(fMacJob 2)" fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "$(cat "${boxDir}/dist-incoming/${macRel}.tgz" "${boxDir}/dist-incoming/debug/${macRel}/zuid.dSYM" 2>&1)" == $'2\n2' ]]; } || boxBad+=" again: exited ${rc}, said '${out//$'\n'/ | }';"
## A job that passes but sends no tarball home fails, and so does one that fails.
out="$(BOX_STAGE=fStage_Box_Mac ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='mkdir -p back && printf x > back/zuid-0.9.0-darwin-universal.tgz' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -qx '  FAIL dee8k macOS universal release built on its box, back in dist-incoming/' <<< "${out}" && grep -q "no ${macRel}.tgz home, only: zuid-0.9.0-darwin-universal.tgz" <<< "${out}"; } || boxBad+=" nothing home: exited ${rc}, said '${out//$'\n'/ | }';"
[[ ! -e "${boxDir}/dist-incoming/zuid-0.9.0-darwin-universal.tgz" ]] || boxBad+=" nothing home: another version reached dist-incoming/;"
out="$(BOX_STAGE=fStage_Box_Mac ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='mkdir -p back && printf x > back/zuid-1.0.0-darwin-universal.tgz && exit 4' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -q 'exited 4' <<< "${out}"; } || boxBad+=" fail: exited ${rc}, said '${out//$'\n'/ | }';"
[[ "$(cat "${boxDir}/dist-incoming/${macRel}.tgz")" == 2 ]] || boxBad+=" fail: a failed job's tarball reached dist-incoming/;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" fail: the box's folder is still there;"
out="$(BOX_STAGE=fStage_Box_Mac ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  SKIP dee8k .*(no answer from collierjr@b26)$' <<< "${out}"; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## b26, else vmKt6m. A Mac that's down or taken hands the job to the next one,
## and one whose job failed doesn't.
fId defkr "the Mac box step falls back to vmKt6m when b26 doesn't answer"
boxBad=""
macTwo="collierjr@b26 collierjr@vmKt6m"
out="$(BOX_STAGE=fStage_Box_Mac BOX_MAC="${macTwo}" BOX_DOWN_AT=collierjr@b26 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB="$(fMacJob 3)" fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -qx '  PASS dee8k macOS universal release built on its box, back in dist-incoming/' <<< "${out}" && grep -qx 'Note .......: no answer from collierjr@b26, so trying collierjr@vmKt6m' <<< "${out}"; } || boxBad+=" b26 down: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap b26 --wait 60 ' "${BOX_LOCK_LOG}" && grep -q '^wrap vmKt6m --wait 60 --why zuid: cicd test -- bash .*/box-run.bash collierjr@vmKt6m ' "${BOX_LOCK_LOG}" || boxBad+=" b26 down: not held as b26 then vmKt6m;"
[[ "$(cat "${boxDir}/dist-incoming/${macRel}.tgz" 2>&1)" == 3 ]] || boxBad+=" b26 down: vmKt6m's release isn't in dist-incoming/;"
[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" b26 down: the box's folder is still there;"
out="$(BOX_STAGE=fStage_Box_Mac BOX_MAC="${macTwo}" BOX_TAKEN_AT=b26 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB="$(fMacJob 4)" fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && grep -q '^  PASS dee8k ' <<< "${out}" && [[ "$(cat "${boxDir}/dist-incoming/${macRel}.tgz" 2>&1)" == 4 ]]; } || boxBad+=" b26 taken: exited ${rc}, said '${out//$'\n'/ | }';"
## A failed job stays a fail, on b26 alone.
out="$(BOX_STAGE=fStage_Box_Mac BOX_MAC="${macTwo}" ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 4' fBoxIn)" && rc=0 || rc=$?
{ ((rc != 0)) && grep -q '^  FAIL dee8k ' <<< "${out}" && grep -q 'exited 4' <<< "${out}"; } || boxBad+=" fail: exited ${rc}, said '${out//$'\n'/ | }';"
grep -q '^wrap vmKt6m ' "${BOX_LOCK_LOG}" && boxBad+=" fail: went on to vmKt6m;"
## Both down is one skip, with both reasons.
out="$(BOX_STAGE=fStage_Box_Mac BOX_MAC="${macTwo}" BOX_DOWN=1 ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "$(grep -c '^  SKIP dee8k ' <<< "${out}")" == 1 ]] && grep -qx '  SKIP dee8k .*(no answer from collierjr@b26; no answer from collierjr@vmKt6m)' <<< "${out}" && grep -qx 'skipwhy:no answer from collierjr@b26; no answer from collierjr@vmKt6m' <<< "${out}"; } || boxBad+=" both down: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${boxBad}" ]]
	then fPass
	else fFail "${boxBad}"
fi

## The Windows box has no bash, so box-run.bash makes, runs and removes its
## folder through PowerShell. The stand-in ssh runs it here under pwsh.
fId deea7 "the Windows box step runs a PowerShell job on b29w"
boxBad=""
if ! command -v pwsh > /dev/null; then fFail "pwsh not installed, which the Windows box half needs here"
else
	out="$(BOX_STAGE=fStage_Box_Windows ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
	{ ((rc == 0)) && grep -q '^  SKIP deea5 .*(no zuid-1.0.0-windows-x86_64.zip in dist/)$' <<< "${out}"; } || boxBad+=" no release: exited ${rc}, said '${out//$'\n'/ | }';"
	printf 'x\n' > "${boxDir}/dist/zuid-1.0.0-windows-x86_64.zip"; printf 'y\n' > "${boxDir}/dist/checksums.txt"; printf 'z\n' > "${boxDir}/install.ps1"
	## The job sees what was sent and runs in its own folder, with TEMP there too.
	# shellcheck disable=2016  ## PowerShell, for the box.
	winJob='foreach ($f in @("zuid-1.0.0-windows-x86_64.zip", "checksums.txt", "install.ps1", "box-run.ps1")) { if (-not (Test-Path -LiteralPath $f)) { Write-Host "missing $f"; exit 5 } }
if ($env:TEMP -ne (Get-Location).Path) { Write-Host "TEMP is $env:TEMP"; exit 6 }'
	out="$(BOX_STAGE=fStage_Box_Windows ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB="${winJob}" fBoxIn)" && rc=0 || rc=$?
	{ ((rc == 0)) && grep -qx '  PASS deea5 Windows release on its box: command, and install.ps1 under 5.1 and 7' <<< "${out}"; } || boxBad+=" pass: exited ${rc}, said '${out//$'\n'/ | }';"
	grep -q '^wrap b29w --wait 60 --why zuid: cicd test -- bash .*/box-run.bash collierjr@b29w ' "${BOX_LOCK_LOG}" || boxBad+=" pass: not held through the lock as b29w;"
	grep -q "^Box \.*: collierjr@b29w:${boxDir}/root/zuid/[0-9]\{8\}-[0-9]\{6\}_[0-9]\{3\}$" <<< "${out}" || boxBad+=" pass: no work folder of its own;"
	[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" pass: the box's folder is still there;"
	out="$(BOX_STAGE=fStage_Box_Windows ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_JOB='exit 3' fBoxIn)" && rc=0 || rc=$?
	{ ((rc != 0)) && grep -qx '  FAIL deea5 Windows release on its box: command, and install.ps1 under 5.1 and 7' <<< "${out}" && grep -q 'exited 3' <<< "${out}"; } || boxBad+=" fail: exited ${rc}, said '${out//$'\n'/ | }';"
	[[ -z "$(find "${boxDir}/root/zuid" -mindepth 1 -maxdepth 1 -type d)" ]] || boxBad+=" fail: the box's folder is still there;"
	## box-run.ps1 removes only a run folder under the project's temp root.
	mkdir -p "${boxDir}/root/zuid/not-a-run" "${boxDir}/root/zuid/20260101-000000_001" "${boxDir}/elsewhere/20260101-000000_001"
	for winBad in "${boxDir}/root/zuid/not-a-run" "${boxDir}/elsewhere/20260101-000000_001" "${boxDir}/root/zuid"; do
		HOST_TEMP="${boxDir}/root" pwsh -NoProfile -NonInteractive -File "${cicd%/*}/utility/box-run.ps1" -Remove "${winBad}" > /dev/null 2>&1 && boxBad+=" removed ${winBad};"
		[[ -d "${winBad}" ]] || boxBad+=" ${winBad} is gone;"
	done
	HOST_TEMP="${boxDir}/root" pwsh -NoProfile -NonInteractive -File "${cicd%/*}/utility/box-run.ps1" -Remove "${boxDir}/root/zuid/20260101-000000_001" > /dev/null 2>&1 || boxBad+=" wouldn't remove a run folder;"
	[[ ! -e "${boxDir}/root/zuid/20260101-000000_001" ]] || boxBad+=" a run folder is still there;"
	## Whatever a broken guard left.
	for winBad in "${boxDir}/root/zuid/not-a-run" "${boxDir}/elsewhere/20260101-000000_001" "${boxDir}/elsewhere"; do [[ ! -d "${winBad}" ]] || rmdir "${winBad}"; done
	out="$(BOX_STAGE=fStage_Box_Windows ZUID_BOX_LOCK="${boxDir}/bin/lock" ZUID_SSH="${boxDir}/bin/ssh" BOX_DOWN=1 BOX_JOB='exit 0' fBoxIn)" && rc=0 || rc=$?
	{ ((rc == 0)) && grep -q '^  SKIP deea5 .*(no answer from collierjr@b29w)$' <<< "${out}"; } || boxBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
	if [[ -z "${boxBad}" ]]
		then fPass
		else fFail "${boxBad}"
	fi
fi

## A step that skipped ends on SKIP, not PASS, and is kept for the end.
fId dee36 "a skipped step says SKIP"
stepOut="$(
	fLoad fStep || exit 2
	fLoad fStep_Skip || exit 2
	# shellcheck disable=2329,2034  ## Called and read by the lifted functions.
	{ declare -i _stepPlanning=0 _stepElsewhere=0 _stepAt=0 _stepTotal=2; _stepOpen=""; _stepSkipWhy=""; _stepSkipped=()
	  fEcho(){ printf '%s\n' "$*"; }; fStep_Stamp(){ printf 'now\n'; }; fJobs_Recheck(){ :; }
	  fBoxDown(){ fStep_Skip "no answer"; }; fFine(){ :; }; }
	fStep "Box" fBoxDown
	fStep "Other" fFine
	printf 'kept:%s\n' "${_stepSkipped[@]}"
)" || true
if grep -qx 'now: Step 1 of 2; SKIP Box (no answer)' <<< "${stepOut}" && grep -qx 'now: Step 2 of 2; PASS Other' <<< "${stepOut}" && grep -qx 'kept:Box (no answer)' <<< "${stepOut}"
	then fPass
	else fFail "said '${stepOut//$'\n'/ | }'"
fi

## --quick fuzzes and dogfoods, per the 2026-10-24 CICD reset. The gate flags
## do neither.
fId dedv6 "--quick fuzzes and dogfoods, the gates don't"
quickBad=""
## As planned on the host. The run in the image has no dogfood step.
fQuickList(){ env -u ZUID_IN_CONTAINER -u ZUID_STEP_FIRST -u ZUID_STEP_TOTAL bash "${cicd}" --list "$@" --no-container < /dev/null 2>&1; }
out="$(fQuickList --quick)" || quickBad+=" --quick exited $?;"
for step in "Go: fuzz" "Zig: fuzz" "Dogfood"; do
	grep -qE "^[0-9]+\. ${step}\$" <<< "${out}" || quickBad+=" --quick has no ${step} step;"
done
out="$(fQuickList --quick --no-fuzz --no-dogfood)" || quickBad+=" --quick --no-fuzz exited $?;"
for step in "Go: fuzz (--no-fuzz)" "Zig: fuzz (--no-fuzz)" "Dogfood (--no-dogfood)"; do
	grep -qxF "Off ........: ${step}" <<< "${out}" || quickBad+=" --quick --no-fuzz --no-dogfood doesn't say ${step};"
done
for gate in --backlog-run-quick --merge-gate; do
	out="$(fQuickList "${gate}")" || quickBad+=" ${gate} exited $?;"
	grep -qxF "Off ........: Dogfood (${gate})" <<< "${out}" || quickBad+=" ${gate} dogfoods;"
	if [[ "${gate}" == "--backlog-run-quick" ]]; then
		grep -qxF "Off ........: Go: fuzz (${gate})" <<< "${out}" || quickBad+=" ${gate} fuzzes;"
	fi
done
if [[ -z "${quickBad}" ]]
	then fPass
	else fFail "${quickBad}"
fi

## CodeQL is about 480 MB, so a run that doesn't want it never builds it.
fId de5ea "CodeQL image only with --leakcheck"
codeqlTag="zuid-codeql:$(echo "FROM codeql" | git hash-object --stdin | cut -c1-12)-${newTag#*:}"
out="$(leakcheck=1 fContainerIn "${worktreeMain}" "${work}/engine-codeql" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-codeql" 2>/dev/null || true)"
plainOut="$(fContainerIn "${worktreeMain}" "${work}/engine-plain" 0)" && plainRc=0 || plainRc=$?
if ((rc == 0)) && grep -qxF "build --build-arg BASE=${newTag} --label dev.project=zuid --label dev.run=20261019-101112 -t ${codeqlTag} ${mainReal}/cicd/container/codeql" <<< "${log}" \
	&& grep -q -- "^run .* ${codeqlTag} ionice -c 3 nice -n 19 bash .* --leakcheck$" <<< "${log}" && ! grep -q "^rmi " <<< "${log}" \
	&& ((plainRc == 0)) && ! grep -qE '^(build|run) .*codeql' "${work}/engine-plain"
	then fPass
	else fFail "exited ${rc} and ${plainRc}, asked: ${log//$'\n'/ | }; said '${out}' and '${plainOut}'"
fi

## A rebuilt main image left the CodeQL one built on the old one, and what it
## held of the old layers, until the next --leakcheck run.
fId debk4 "plain run drops a CodeQL image on an old main one"
staleBad=""
for pass in built found; do
	: > "${work}/engine-stale"
	out="$(fContainerIn "${worktreeMain}" "${work}/engine-stale" 0)" && rc=0 || rc=$?
	log="$(cat "${work}/engine-stale")"
	rmis="$(grep '^rmi ' <<< "${log}" || true)"
	((rc == 0)) || staleBad+=" ${pass}: exited ${rc}, said '${out}';"
	! grep -qE '^(build|run) .*codeql' <<< "${log}" || staleBad+=" ${pass}: built or ran CodeQL;"
	## Since 2026102416233101 nothing goes during the stage. dednb has the
	## old CodeQL tag going at the end, ahead of the old main one.
	if [[ "${pass}" == "built" ]]; then
		grep -q '^build .*-t zuid-cicd' <<< "${log}" || staleBad+=" built: no build;"
		[[ -z "${rmis}" ]] || staleBad+=" built: removed '${rmis//$'\n'/ | }';"
	else
		! grep -q '^build ' <<< "${log}" || staleBad+=" found: built again;"
		[[ -z "${rmis}" ]] || staleBad+=" found: removed '${rmis//$'\n'/ | }';"
	fi
done
if [[ -z "${staleBad}" ]]
	then fPass
	else fFail "${staleBad}"
fi

## A public clone without docker still passes, so the checkers in the image
## skip rather than fail when there's nothing to run them in.
fId de54z "Go checkers with and without docker"
out="$(
	# shellcheck disable=2329  ## Called by the lifted functions, not here.
	fEcho_Clean(){ :; }
	# shellcheck disable=2329
	fThrowError(){ printf '%s\n' "$1"; exit 1; }
	# shellcheck disable=2329
	uname(){ case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; esac; }
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerImage="zuid-cicd"; codeqlImage="zuid-codeql"; inContainer=0; containerTag=""; checkerSkipWhy=""
		containerVolume="zuid-cicd-cache"; containerZigVolume="zuid-zig-cache"; projectName="zuid"; runName="20261019-101112"; _dockerRun=""
	}
	for fn in _fMustBeInPath fGoCheckers_Ready fContainer_Image fContainer_Volumes; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2030,2031  ## The stub reads it; the earlier subshell's copy is gone.
	export ENGINE_LOG="${work}/engine-checkers"
	# shellcheck disable=2034  ## Read by the lifted functions.
	containerEngine="${work}/no-such-engine"
	fGoCheckers_Ready; printf 'missing=%s\n' "${checkerSkipWhy}"
	# shellcheck disable=2034
	containerEngine="${work}/engine"
	# shellcheck disable=2030  ## Only this subshell's.
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

fId dedkz "--container, --no-container"
out="$(for containerArgs in "" --no-container --container "--container --no-container" "--gate --no-container" "--gate --container"; do
	# shellcheck disable=2086  ## Empty means no argument at all.
	showContainer=1 fInitIn "${worktreeMain}" ${containerArgs}
done)" && rc=0 || rc=$?
wantContainer="doContainer=0 mode=auto"$'\n'"doContainer=0 mode=off"$'\n'"doContainer=1 mode=on"$'\n'"doContainer=0 mode=off"$'\n'"doContainer=0 mode=off"$'\n'"doContainer=1 mode=on"
if ((rc == 0)) && [[ "${out}" == "${wantContainer}" ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## A run's own pick of the container, with the stand-in engine above.
fPickIn(){  ## engine log; the case's settings come in as pick* variables
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329
		uname(){ case "$1" in -s) echo "${pickOs:-Linux}" ;; -m) echo x86_64 ;; esac; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerImage="zuid-cicd"; codeqlImage="zuid-codeql"; containerTag=""
			inContainer="${pickInside:-0}"; containerMode="${pickMode:-auto}"; doContainer="${pickAsked:-0}"
			doPublish="${pickPublish:-0}"; doPackage=0; packageSkipWhy="${pickSkip:-}"; imageSkipWhy=""
			containerEngine="${pickEngine:-${work}/engine}"
			containerVolume="zuid-cicd-cache"; containerZigVolume="zuid-zig-cache"; projectName="zuid"; runName="20261019-101112"; _dockerRun=""
		}
		local fn=""
		for fn in _fMustBeInPath fContainer_Pick fContainer_Where fContainer_Image fContainer_Volumes; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2030,2031  ## The stub reads them; each case has its own.
		export ENGINE_LOG="$1" ENGINE_INFO_RC="${pickInfoRc:-0}" ENGINE_BUILD_RC="${pickBuildRc:-0}"
		: > "${ENGINE_LOG}"
		fContainer_Pick
		printf 'doContainer=%s doPackage=%s skip=%s image=%s tag=%s\n' "${doContainer}" "${doPackage}" "${packageSkipWhy}" "${imageSkipWhy}" "${containerTag}"
	) 2>&1
}
pickSkipWhy="no llvm-objcopy to strip the release with"

## The image has the tools, so a full run that couldn't package here does there.
fId dedm0 "the container where docker answers"
out="$(pickSkip="${pickSkipWhy}" fPickIn "${work}/engine-pick")" && rc=0 || rc=$?
if ((rc == 0)) && grep -qxF "build --label dev.project=zuid --label dev.run=20261019-101112 -t ${newTag} ${mainReal}/cicd/container" "${work}/engine-pick" \
	&& [[ "${out}" == *$'\n'"doContainer=1 doPackage=1 skip= image= tag=${newTag}" ]]
	then fPass
	else fFail "exited ${rc} and said: ${out//$'\n'/ | }"
fi

fId dedm1 "this machine with a note, without docker"
pickBad=""
fWantPick(){  ## why, then the case's pick* settings as name=value
	local -r why="$1"; shift
	local got="" imageWant=""
	if [[ "${why}" == "the image didn't build" ]]; then imageWant="${why}"; fi
	# shellcheck disable=2163  ## Exports the name=value pairs it was handed.
	got="$(export "$@" pickSkip="${pickSkipWhy}"; fPickIn "${work}/engine-pick-fb")" || { pickBad+=" '${why}' exited $?: ${got//$'\n'/ | };"; return 0; }
	if [[ "${got}" != *"Container ..: not used, ${why}, so this runs here"$'\n'"doContainer=0 doPackage=0 skip=${pickSkipWhy} image=${imageWant} tag=" ]]; then pickBad+=" '${why}' said: ${got//$'\n'/ | };"; fi
}
fWantPick "no ${work}/no-such-engine"            pickEngine="${work}/no-such-engine"
fWantPick "${work}/engine isn't answering"       pickInfoRc=1
fWantPick "the image didn't build"               pickBuildRc=1
fWantPick "--publish runs on this machine"       pickPublish=1
fWantPick "the image is Linux x86_64 only"       pickOs=Darwin
if [[ -z "${pickBad}" ]]
	then fPass
	else fFail "${pickBad}"
fi

## Asked for by name, or already inside, nothing is asked of docker.
fId dedm2 "--container, --no-container and the run inside decide alone"
pickBad=""
out="$(pickMode=off fPickIn "${work}/engine-pick-off")" || pickBad+=" off exited $?;"
[[ "${out}" == "Container ..: off (--no-container), so this runs here"$'\n'"doContainer=0 doPackage=0 skip= image= tag=" ]] || pickBad+=" off said: ${out//$'\n'/ | };"
out="$(pickMode=on pickAsked=1 fPickIn "${work}/engine-pick-on")" || pickBad+=" on exited $?;"
[[ "${out}" == "doContainer=1 doPackage=0 skip= image= tag=" ]] || pickBad+=" on said: ${out//$'\n'/ | };"
out="$(pickInside=1 fPickIn "${work}/engine-pick-in")" || pickBad+=" inside exited $?;"
[[ "${out}" == "doContainer=0 doPackage=0 skip= image= tag=" ]] || pickBad+=" inside said: ${out//$'\n'/ | };"
for pickLog in off on in; do
	if [[ -s "${work}/engine-pick-${pickLog}" ]]; then pickBad+=" ${pickLog} asked the engine: $(tr '\n' '|' < "${work}/engine-pick-${pickLog}");"; fi
done
if [[ -z "${pickBad}" ]]
	then fPass
	else fFail "${pickBad}"
fi

## The checkers would only try the same failed build again.
fId dedm3 "checkers skip on an image that didn't build"
: > "${work}/engine-noimage"
out="$(
	# shellcheck disable=2329  ## Called by the lifted functions, not here.
	fEcho_Clean(){ :; }
	# shellcheck disable=2034  ## Read by the lifted functions.
	{ inContainer=0; checkerSkipWhy=""; imageSkipWhy="the image didn't build"; containerEngine="${work}/engine"; }
	fLoad fGoCheckers_Ready || { echo "no fGoCheckers_Ready in cicd.bash"; exit 2; }
	# shellcheck disable=2030,2031  ## The stub reads it.
	export ENGINE_LOG="${work}/engine-noimage"
	fGoCheckers_Ready; printf 'why=%s\n' "${checkerSkipWhy}"
)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "why=the image didn't build" ]] && [[ ! -s "${work}/engine-noimage" ]]
	then fPass
	else fFail "exited ${rc}, said '${out}', asked: $(tr '\n' '|' < "${work}/engine-noimage")"
fi

## The pre-push hook points the worktree's Zig at the checkout's cache.
fId dedm4 "the hook's Zig cache goes in"
mkdir -p "${work}/hook-zig-cache" "${mainReal}/zig/.zig-cache"
: > "${work}/engine-zc"
out="$(zigCache="${work}/hook-zig-cache" fContainerIn "${worktreeMain}" "${work}/engine-zc" 0)" && rc=0 || rc=$?
: > "${work}/engine-zc-in"
zigCache="${mainReal}/zig/.zig-cache" fContainerIn "${worktreeMain}" "${work}/engine-zc-in" 0 >/dev/null 2>&1 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* -v ${work}/hook-zig-cache:${work}/hook-zig-cache .* -e ZIG_LOCAL_CACHE_DIR=${work}/hook-zig-cache " "${work}/engine-zc" \
	&& grep -q -- "^run .* -e ZIG_LOCAL_CACHE_DIR=${mainReal}/zig/.zig-cache " "${work}/engine-zc-in" && ! grep -q -- "-v ${mainReal}/zig/.zig-cache:" "${work}/engine-zc-in"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-zc" "${work}/engine-zc-in" || true)"
fi

## This checkout's cache is a link off the snapshotted dataset, and Zig
## stopped on NotDir in the container.
fId dedmc "a Zig cache linked out of the tree goes in"
workReal="$(cd "${work}" && pwd -P)"
mkdir -p "${work}/zc-target" "${mainReal}/zig"
zcLinkBad=""
if [[ -e "${mainReal}/zig/.zig-cache" && ! -L "${mainReal}/zig/.zig-cache" ]]; then
	mv "${mainReal}/zig/.zig-cache" "${mainReal}/zig/.zig-cache.real"
fi
ln -sfn "${work}/zc-target" "${mainReal}/zig/.zig-cache"
: > "${work}/engine-zclink"
fContainerIn "${worktreeMain}" "${work}/engine-zclink" 0 >/dev/null 2>&1 || zcLinkBad+=" the stage exited $?;"
rm -f -- "${mainReal}/zig/.zig-cache"
if [[ -d "${mainReal}/zig/.zig-cache.real" ]]; then mv "${mainReal}/zig/.zig-cache.real" "${mainReal}/zig/.zig-cache"; fi
grep -q -- "^run .* -v ${workReal}/zc-target:${workReal}/zc-target " "${work}/engine-zclink" || zcLinkBad+=" no mount for it;"
if [[ -z "${zcLinkBad}" ]]
	then fPass
	else fFail "${zcLinkBad} asked: $(grep '^run ' "${work}/engine-zclink" || true)"
fi

## SDE is a kit on this machine, so the packaging inside can only find it
## when it's handed in.
fId dedmd "SDE goes in for packaging"
mkdir -p "${work}/sde-kit"
: > "${work}/sde-kit/sde64"; chmod +x "${work}/sde-kit/sde64"
: > "${work}/engine-sde"
out="$(rigSde="${work}/sde-kit/sde64" fContainerIn "${worktreeMain}" "${work}/engine-sde" 0)" && rc=0 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* -v ${workReal}/sde-kit:${workReal}/sde-kit:ro .* -e ZUID_SDE=${workReal}/sde-kit/sde64 " "${work}/engine-sde"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-sde" || true)"
fi

## The C sanitizer builds go to a scratch dir outside the repo, which the
## image only sees if it's mounted.
fId de5b3 "mounts for a folder outside the repo"
out="$(
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerVolume="zuid-cicd-cache"; inContainer=0
		containerZigVolume="zuid-zig-cache"; containerZigCache="/zig-cache"
		containerTag="zuid-cicd:t3st"; containerEngine="${work}/engine"
		projectName="zuid"; runName="20261019-101112"; keepTemp=0; _dockerSteps=0; _dockerPid="${BASHPID}"; buildJobs=3
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
	&& grep -qF -- "-v ${work}/outside:${work}/outside -w ${work}/outside zuid-cicd:t3st ionice -c 3 nice -n 19 true" <<< "${log}" \
	&& grep -- "-w ${mainReal}/go " <<< "${log}" | grep -qvF -- "-v ${mainReal}/go:"
	then fPass
	else fFail "exited ${rc}, said '${out}', asked: ${log//$'\n'/ | }"
fi

## Each step in the image is held to its own count, a hard step to the
## quarter, and nice inside, since the image's processes aren't ours.
fId dedp8 "steps in the image get the step's job count"
out="$(
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerVolume="zuid-cicd-cache"; inContainer=0
		containerZigVolume="zuid-zig-cache"; containerZigCache="/zig-cache"
		containerTag="zuid-cicd:t3st"; containerEngine="${work}/engine"
		projectName="zuid"; runName="20261019-101112"; keepTemp=0; _dockerSteps=0; _dockerPid="${BASHPID}"; buildJobs=3; hardJobs=2
	}
	for fn in fInImage fContainer_RunArgs; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2030,2031  ## The stub reads it; each case has its own.
	export ENGINE_LOG="${work}/engine-jobs"
	fInImage "${repoRoot}" true
	# shellcheck disable=2034  ## Read by the lifted fInImage.
	fHard(){ local -ri imageJobs="${hardJobs}"; fInImage "${repoRoot}" "$@"; }
	fHard true
	inContainer=1
	fHard printenv ZUID_JOBS
)" && rc=0 || rc=$?
log="$(cat "${work}/engine-jobs" 2>/dev/null || true)"
jobsBad=""
grep -q -- "^run .*-hard-2 .* --cpus 2 --cpu-shares 256 -e ZUID_JOBS=2 -e ZUID_JOBS_CAP=2 .* zuid-cicd:t3st ionice -c 3 nice -n 19 true$" <<< "${log}" || jobsBad+=" the hard step;"
grep -v -- "-hard-" <<< "${log}" | grep -q -- "^run .* --cpus 3 --cpu-shares 256 -e ZUID_JOBS=3 -e ZUID_JOBS_CAP=3 .* zuid-cicd:t3st ionice -c 3 nice -n 19 true$" || jobsBad+=" the plain step;"
[[ "${out}" == "2" ]] || jobsBad+=" inside the image it said '${out}';"
if ((rc == 0)) && [[ -z "${jobsBad}" ]]
	then fPass
	else fFail "exited ${rc},${jobsBad} asked: ${log//$'\n'/ | }"
fi

## Cleanup finds a run's leftovers by label, so everything gets them. docker
## makes a missing volume on first use with none.
fId dedn9 "containers, images and volumes are labeled and named"
labelBad=""
: > "${work}/engine-label"
out="$(ENGINE_VOLUMES="zuid-cicd-cache" leakcheck=1 fContainerIn "${worktreeMain}" "${work}/engine-label" 0)" || labelBad+=" the stage exited $?: ${out};"
log="$(cat "${work}/engine-label")"
labels="--label dev.project=zuid --label dev.run=20261019-101112"
grep -qxF "volume create ${labels} zuid-zig-cache" <<< "${log}" || labelBad+=" no labeled zuid-zig-cache;"
! grep -q "^volume create .*zuid-cicd-cache" <<< "${log}" || labelBad+=" made a volume that was there;"
grep -q -- "^build ${labels} -t zuid-cicd:" <<< "${log}" || labelBad+=" main image unlabeled;"
grep -q -- "^build --build-arg BASE=.* ${labels} -t zuid-codeql:" <<< "${log}" || labelBad+=" CodeQL image unlabeled;"
grep -q -- "^run --rm .* --name zuid-20261019-101112-container ${labels} " <<< "${log}" || labelBad+=" stage container unnamed or unlabeled;"
## Steps in the image, two of them in a $(...), named apart, and --keep-temp
## drops --rm.
out="$(
	# shellcheck disable=2034  ## Read by the lifted functions.
	{
		repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerVolume="zuid-cicd-cache"; inContainer=0
		containerZigVolume="zuid-zig-cache"; containerZigCache="/zig-cache"
		containerTag="zuid-cicd:t3st"; containerEngine="${work}/engine"
		projectName="zuid"; runName="20261019-101112"; keepTemp=0; _dockerSteps=0; _dockerPid="${BASHPID}"; buildJobs=3
	}
	for fn in fInImage fContainer_RunArgs; do
		fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
	done
	# shellcheck disable=2030,2031  ## The stub reads them; each case has its own.
	export ENGINE_LOG="${work}/engine-steps"
	fStage_Go_Checkers(){ fInImage "${repoRoot}" true; a="$(fInImage "${repoRoot}" true)"; b="$(fInImage "${repoRoot}" true)"; : "${a}${b}"; }
	fStage_Go_Checkers
	keepTemp=1
	fInImage "${repoRoot}" true
)" || labelBad+=" fInImage exited $?: ${out};"
mapfile -t names < <(grep -o -- '--name [^ ]*' "${work}/engine-steps" | cut -d' ' -f2 || true)
if ((${#names[@]} != 4)) || [[ "$(printf '%s\n' "${names[@]}" | sort -u | wc -l | tr -d ' ')" != "4" ]]; then labelBad+=" names not 4 apart: ${names[*]};"; fi
[[ "${names[0]:-}" == "zuid-20261019-101112-go-checkers-1" ]] || labelBad+=" first step named '${names[0]:-}';"
[[ "${names[1]:-}" == zuid-20261019-101112-go-checkers-2-* ]] || labelBad+=" second step named '${names[1]:-}';"
[[ "$(grep -c -- "^run --rm --init .* ${labels} " "${work}/engine-steps" || true)" == "3" ]] || labelBad+=" not 3 labeled --rm runs;"
grep -q -- "^run --init .* ${labels} " "${work}/engine-steps" || labelBad+=" --keep-temp still has --rm;"
if [[ -z "${labelBad}" ]]
	then fPass
	else fFail "${labelBad}"
fi

## The end of a run, failed or not, stops and removes its own containers.
fStopIn(){  ## engine log; keep, run come in as variables
	(
		# shellcheck disable=2329  ## Called by the lifted function.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		fLoad fContainer_StopRun || { echo "no fContainer_StopRun in cicd.bash"; exit 2; }
		# shellcheck disable=2034  ## Read by the lifted function.
		{ _dockerEngine="${work}/engine"; _dockerProject="zuid"; _dockerRun="${run-20261019-101112}"; _dockerPid="${BASHPID}"; keepTemp="${keep:-0}"; _dockerGone=(); }
		# shellcheck disable=2030,2031  ## The stub reads them; each case has its own.
		export ENGINE_LOG="$1" ENGINE_PS=$'c0ffee1\nc0ffee2\n'
		: > "${ENGINE_LOG}"
		fContainer_StopRun
		printf 'gone=%s\n' "${_dockerGone[*]}"
	) 2>&1
}
fId dedna "a run's containers go at its end, unless --keep-temp"
stopBad=""
out="$(fStopIn "${work}/engine-stop")" || stopBad+=" exited $?;"
log="$(cat "${work}/engine-stop")"
[[ "${log}" == "ps -aq --filter label=dev.project=zuid --filter label=dev.run=20261019-101112"$'\n'"stop -t 10 c0ffee1 c0ffee2"$'\n'"rm c0ffee1 c0ffee2" ]] || stopBad+=" asked: ${log//$'\n'/ | };"
[[ "${out}" == "gone=2 container(s)" ]] || stopBad+=" said '${out}';"
out="$(keep=1 fStopIn "${work}/engine-stop-keep")" || stopBad+=" keep exited $?;"
! grep -qE '^(stop|rm) ' "${work}/engine-stop-keep" || stopBad+=" --keep-temp removed them;"
[[ "${out}" == *"kept 2 container(s)"* ]] || stopBad+=" keep said '${out}';"
out="$(run="" fStopIn "${work}/engine-stop-none")" || stopBad+=" none exited $?;"
[[ ! -s "${work}/engine-stop-none" ]] || stopBad+=" a run without docker asked: $(tr '\n' '|' < "${work}/engine-stop-none");"
## Both traps call it, and fMain tidies once the stages have passed.
trapBody="$(sed -n '/^function _fTrap_Exit(){/,/^}/p; /^function _fTrap_Error(){/,/^}/p' "${cicd}")"
[[ "$(grep -c 'fContainer_StopRun' <<< "${trapBody}")" == "2" ]] || stopBad+=" not called from both traps;"
## In fSteps since 2026102416233104.
mainBody="$(sed -n '/^fSteps(){/,/^}/p' "${cicd}")"
tidyAt="$(grep -n '^		fContainer_Tidy$' <<< "${mainBody}" | cut -d: -f1 || true)"
zigAt="$(grep -n 'then fZigCache_Tidy; fi' <<< "${mainBody}" | cut -d: -f1 || true)"
publishAt="$(grep -n 'then fStep "Publish" fStage_Publish;' <<< "${mainBody}" | cut -d: -f1 || true)"
if ! [[ "${tidyAt}" =~ ^[0-9]+$ && "${zigAt}" =~ ^[0-9]+$ && "${publishAt}" =~ ^[0-9]+$ ]] || ((tidyAt < zigAt || tidyAt > publishAt)); then
	stopBad+=" fMain doesn't call fContainer_Tidy after the stages;"
fi
if [[ -z "${stopBad}" ]]
	then fPass
	else fFail "${stopBad}"
fi

## Only the project's, older tags keeping the one before the current, a week
## of build cache, Go's module prune and the volume's cap, and one line at the
## end of the run.
fTidyIn(){  ## engine log; label, cap come in as variables
	(
		# shellcheck disable=2329  ## Called by the lifted functions.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		for fn in fContainer_Tidy fContainer_StopRun fContainer_DropOlder fContainer_VolumeCap fDocker_Bytes fCodeql_Tag fCleanup_Say fCleanup_Mb; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerEngine="${work}/engine"; projectName="zuid"; runName="20261019-101112"
			containerImage="zuid-cicd"; codeqlImage="zuid-codeql"; containerVolume="zuid-cicd-cache"; zigCacheCapMB=2048; keepTemp=0
			containerTag="${newTag}"; _dockerEngine="${containerEngine}"; _dockerProject="zuid"; _dockerRun="${runName}"; _dockerGone=(); _dockerPid="${BASHPID}"
			_cleanGone=(); _cleanKb=0; _cleanSay=1; _cleanDockerFreed=""; _runPid="${BASHPID}"; safeRmSweptN=0; inContainer=0
		}
		mkdir -p "${repoRoot}/cicd/container/codeql"; echo "FROM codeql" > "${repoRoot}/cicd/container/codeql/Dockerfile"
		ENGINE_NEW="${newTag}" ENGINE_NEW_CODEQL="zuid-codeql:$(echo "FROM codeql" | git hash-object --stdin | cut -c1-12)-${newTag#*:}"
		# shellcheck disable=2030,2031  ## The stub reads them; each case has its own.
		export ENGINE_LOG="$1" ENGINE_NEW ENGINE_NEW_CODEQL ENGINE_DANGLING=$'d4ng1e\n' ENGINE_VOLUME_LABEL="${label-zuid}" ENGINE_CAP_OUT="${cap:-}" ENGINE_DF="${work}/df-sizes"
		printf '%s\n' "142.5GB 7.052GB 14.91GB 137.3GB" "${dfAfter-139.6GB 7.052GB 14.61GB 136.8GB}" > "${ENGINE_DF}"
		: > "${ENGINE_LOG}"; rm -f "${ENGINE_LOG}.df"
		fContainer_Tidy
		printf 'run=%s\n' "${_dockerRun}"
		fCleanup_Say
	) 2>&1
}
fId dednb "a passing run tidies docker by label"
tidyBad=""
out="$(cap=$'pruned 10240\nemptied 3145728' fTidyIn "${work}/engine-tidy")" || tidyBad+=" exited $?: ${out};"
log="$(cat "${work}/engine-tidy")"
rmis="$(grep '^rmi ' <<< "${log}" || true)"
[[ "${rmis}" == "rmi zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld"$'\n'"rmi zuid-cicd:0ld0ld0ld0ld"$'\n'"rmi d4ng1e" ]] || tidyBad+=" removed '${rmis//$'\n'/ | }';"
grep -qxF "image ls zuid-cicd --filter label=dev.project=zuid --format {{.CreatedAt}}"$'\t'"{{.Repository}}:{{.Tag}}" <<< "${log}" || tidyBad+=" tags not listed by label;"
grep -qxF "images -q --filter dangling=true --filter label=dev.project=zuid" <<< "${log}" || tidyBad+=" dangling not by label;"
grep -qxF "builder prune -f --filter until=168h" <<< "${log}" || tidyBad+=" no builder prune;"
tidyRoot="$(cd "${worktreeMain}" && pwd -P)"
grep -q -- "^run --rm --init .* -v ${tidyRoot}:${tidyRoot}:ro -v zuid-cicd-cache:/cache --name zuid-20261019-101112-cache-cap --label dev.project=zuid --label dev.run=20261019-101112 --cpus 1 --cpu-shares 256 ${newTag} ionice -c 3 nice -n 19 sh -c" <<< "${log}" \
	&& grep -q -- " sh 2097152 ${tidyRoot}$" <<< "${log}" || tidyBad+=" no capped volume check;"
# shellcheck disable=2016  ## The script's own text.
grep -qF 'bash "$2/cicd/utility/gomod-prune.bash" "$(go env GOMODCACHE)" "$2/go/go.sum"' <<< "${log}" || tidyBad+=" no Go module prune;"
! grep -qE '^(rmi|.*-f ).*(prevprevprev|'"${newTag#*:}"')' <<< "${rmis}" || tidyBad+=" removed a kept tag;"
! grep -qE '^(system prune|rmi -f|image prune)' <<< "${log}" || tidyBad+=" pruned wide;"
want="Cleanup ....: removed zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld, zuid-cicd:0ld0ld0ld0ld, 1 dangling image(s), Go modules go.sum doesn't name, 10 MB, zuid-cicd-cache's contents, 3072 MB, build cache over a week old; about 3.7 GB freed"
[[ "${out}" == *"run="$'\n'"${want}" ]] || tidyBad+=" said '${out//$'\n'/ | }';"
out="$(label="" dfAfter="" fTidyIn "${work}/engine-tidy-nolabel")" || tidyBad+=" unlabeled exited $?;"
! grep -q -- "-cache-cap" "${work}/engine-tidy-nolabel" || tidyBad+=" checked an unlabeled volume;"
## A df that didn't answer is no reason to claim the whole lot was freed.
[[ "${out}" == *"; under 1 MB freed, plus an unknown amount from docker, since docker system df didn't answer" ]] || tidyBad+=" a silent df said '${out//$'\n'/ | }';"
if [[ -z "${tidyBad}" ]]
	then fPass
	else fFail "${tidyBad}"
fi

git -C "${worktreeMain}" worktree remove --force "${worktreeDir}"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Zig never trims a cache, so the end of a run empties each of ours that's
## over the cap or was filled by another Zig. A stand-in zig names the version.
fZigTidyIn(){  ## repo dir, cap in MB, inContainer
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		zig(){ printf '0.17.0\n'; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			repoRoot="$(cd "$1" && pwd -P)"; zigCacheCapMB="$2"; inContainer="$3"
			zigCacheStamp=".cicd-zig-version"; containerZigCache="${zigGlobal:-/zig-cache}"
			_cleanGone=(); _cleanKb=0
		}
		local fn=""
		for fn in fZigCache_Tidy fZigCache_Empty fCleanup_Mb; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fZigCache_Tidy
		printf 'gone=%s kb=%s\n' "${_cleanGone[*]}" "${_cleanKb}"
	) 2>&1
}
## A cache with a file in it, and a stamp if one is given.
fZigCacheMake(){  ## dir, [stamp]
	mkdir -p "$1/o/0123abcd"; printf 'x%.0s' {1..2000} > "$1/o/0123abcd/obj"
	if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" > "$1/.cicd-zig-version"; fi
}
## Only the stamp left, naming this Zig.
fZigCacheEmptied(){  ## dir
	[[ -d "$1" && "$(ls -A "$1")" == ".cicd-zig-version" && "$(cat "$1/.cicd-zig-version")" == "0.17.0" ]]
}

fId dedmt "a Zig cache over the cap is emptied whole"
zt="${work}/zt-cap"; ztReal=""
mkdir -p "${zt}/.git" "${work}/zt-cap-target"
fZigCacheMake "${zt}/zig/.zig-cache" "0.17.0"
fZigCacheMake "${zt}/zig/vendor/dep/.zig-cache"
fZigCacheMake "${zt}/.git/.zig-cache"
fZigCacheMake "${work}/zt-cap-target/.zig-cache"
mkdir -p "${zt}/linked"; ln -s "${work}/zt-cap-target/.zig-cache" "${zt}/linked/.zig-cache"
out="$(fZigTidyIn "${zt}" 0 0)" && rc=0 || rc=$?
ztReal="$(cd "${zt}" && pwd -P)"
capBad=""
((rc == 0)) || capBad+=" exited ${rc};"
fZigCacheEmptied "${zt}/zig/.zig-cache"            || capBad+=" zig/.zig-cache not emptied;"
fZigCacheEmptied "${zt}/zig/vendor/dep/.zig-cache" || capBad+=" a dependency's not emptied;"
fZigCacheEmptied "${work}/zt-cap-target/.zig-cache" || capBad+=" the linked one not emptied;"
[[ -L "${zt}/linked/.zig-cache" ]]                 || capBad+=" the link is gone;"
[[ -f "${zt}/.git/.zig-cache/o/0123abcd/obj" ]]    || capBad+=" went into .git;"
[[ "${out}" == *"Zig cache ..: emptied ${ztReal}/zig/.zig-cache, "*" MB, over 0 MB"* ]] || capBad+=" no line for it;"
## And for the run's last line.
[[ "${out}" =~ gone=.*zig/.zig-cache,\ (under\ 1|[0-9]+)\ MB.*\ kb=[1-9][0-9]*$ ]] || capBad+=" not kept for the end line;"
if [[ -z "${capBad}" ]]
	then fPass
	else fFail "${capBad} said '${out//$'\n'/ | }'"
fi

fId dedmv "a Zig cache from another Zig is emptied, this one's kept"
zt="${work}/zt-ver"
mkdir -p "${zt}"
fZigCacheMake "${zt}/old/.zig-cache" "0.16.0"
fZigCacheMake "${zt}/same/.zig-cache" "0.17.0"
fZigCacheMake "${zt}/unstamped/.zig-cache"
out="$(fZigTidyIn "${zt}" 99999 0)" && rc=0 || rc=$?
verBad=""
((rc == 0)) || verBad+=" exited ${rc};"
fZigCacheEmptied "${zt}/old/.zig-cache" || verBad+=" 0.16.0's not emptied;"
[[ -f "${zt}/same/.zig-cache/o/0123abcd/obj" ]] || verBad+=" this Zig's emptied;"
[[ -f "${zt}/unstamped/.zig-cache/o/0123abcd/obj" ]] || verBad+=" an unstamped one emptied;"
[[ "$(cat "${zt}/unstamped/.zig-cache/.cicd-zig-version" 2>/dev/null || true)" == "0.17.0" ]] || verBad+=" an unstamped one not stamped;"
[[ "${out}" == *"emptied "*"/old/.zig-cache, filled by Zig 0.16.0"* && "${out}" != *"/same/"* ]] || verBad+=" wrong lines;"
if [[ -z "${verBad}" ]]
	then fPass
	else fFail "${verBad} said '${out//$'\n'/ | }'"
fi

fId dedmw "the image's Zig cache volume, only inside"
zt="${work}/zt-global"
mkdir -p "${zt}"
fZigCacheMake "${work}/zt-global-cache" "0.17.0"
zgReal="$(cd "${work}/zt-global-cache" && pwd -P)"
out="$(ZIG_GLOBAL_CACHE_DIR="${zgReal}" zigGlobal="${zgReal}" fZigTidyIn "${zt}" 0 0)" || true
globalBad=""
[[ -f "${zgReal}/o/0123abcd/obj" ]] || globalBad+=" emptied outside the image;"
out="$(ZIG_GLOBAL_CACHE_DIR="${zgReal}" zigGlobal="${zgReal}" fZigTidyIn "${zt}" 0 1)" && rc=0 || rc=$?
((rc == 0)) || globalBad+=" exited ${rc};"
fZigCacheEmptied "${zgReal}" || globalBad+=" not emptied inside;"
if [[ -z "${globalBad}" ]]
	then fPass
	else fFail "${globalBad} said '${out//$'\n'/ | }'"
fi

fId dedmx "a Zig cache is emptied only where it's ours"
zt="${work}/zt-guard"
mkdir -p "${zt}" "${work}/zt-guard-notcache"
fZigCacheMake "${work}/zt-guard-notcache"
fZigCacheMake "${work}/zt-guard-outside/.zig-cache"
mkdir -p "${zt}/bad"; ln -s "${work}/zt-guard-notcache" "${zt}/bad/.zig-cache"
out="$(fZigTidyIn "${zt}" 0 0)" && rc=0 || rc=$?
guardBad=""
[[ -f "${work}/zt-guard-notcache/o/0123abcd/obj" ]] || guardBad+=" followed a link to something else;"
[[ "${out}" == *"couldn't empty "*"/zt-guard/bad/.zig-cache, "* ]] || guardBad+=" didn't say so;"
## Straight at the guard, the way a broken caller would be.
guardOut="$(
	# shellcheck disable=2034  ## Read by the lifted function.
	{ repoRoot="$(cd "${zt}" && pwd -P)"; inContainer=0; containerZigCache="${work}/zt-guard-outside/.zig-cache" ;}
	fLoad fZigCache_Empty || exit 2
	for p in "${work}/zt-guard-outside/.zig-cache" "${repoRoot}/../zt-guard-outside/.zig-cache" "${repoRoot}" "${repoRoot}/bad/.zig-cache" "${containerZigCache}"; do
		if fZigCache_Empty "${p}"; then printf 'took %s\n' "${p}"; fi
	done
	inContainer=1
	if fZigCache_Empty "${repoRoot}/../zt-guard-outside/.zig-cache"; then printf 'took it through ..\n'; fi
)" || guardBad+=" the guard's subshell failed;"
[[ -z "${guardOut}" ]] || guardBad+=" ${guardOut//$'\n'/;}"
[[ -f "${work}/zt-guard-outside/.zig-cache/o/0123abcd/obj" ]] || guardBad+=" emptied one outside the repo;"
if [[ -z "${guardBad}" ]]
	then fPass
	else fFail "${guardBad} said '${out//$'\n'/ | }'"
fi

fId dedmy "the Zig caches are tidied where Zig ran"
## The run inside the image does its own, and the run outside built nothing.
## In fSteps since 2026102416233104, after the last place Package can run.
mainBody="$(sed -n '/^fSteps(){/,/^}/p' "${cicd}")"
tidyAt="$(grep -n 'if ((doZig)) && ((! doContainer)); then fZigCache_Tidy; fi' <<< "${mainBody}" | cut -d: -f1 || true)"
packageAt="$(grep -n 'then fStep "Package" fStage_Package; fi' <<< "${mainBody}" | tail -n1 | cut -d: -f1 || true)"
if [[ "${tidyAt}" =~ ^[0-9]+$ && "${packageAt}" =~ ^[0-9]+$ ]] && ((tidyAt > packageAt))
	then fPass
	else fFail "fMain doesn't call fZigCache_Tidy after the package stage, outside the image's run"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The shell stage, with a stand-in shellcheck that reports a version and
## passes everything, and the stages it calls stubbed out.

cat > "${work}/shellcheck" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
	printf 'ShellCheck - shell script analysis tool\nversion: %s\nlicense: GNU General Public License, version 3\n' "${FAKE_SC_VER}"
fi
STUB
chmod +x "${work}/shellcheck"
shellTree="${work}/shell-tree"
mkdir -p "${shellTree}/cicd/container" "${work}/shell-bin"
cp "${work}/shellcheck" "${work}/shell-bin/"
printf 'FROM scratch\nARG SC_VER=0.11.0\n' > "${shellTree}/cicd/container/Dockerfile"

fShellIn(){  ## version the stand-in shellcheck reports
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329,2154  ## testId and testName come from the lifted fId.
		fTestPass(){ printf '  PASS %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  SKIP %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL %s %s\n' "${testId}" "${testName}"; fThrowError "$*"; }
		# shellcheck disable=2329
		fStage_TestIds(){ :; }
		# shellcheck disable=2329
		fStage_Shell_PowerShell(){ :; }
		# shellcheck disable=2329
		fStage_Shell_Pipeline(){ :; }
		# shellcheck disable=2329
		fStage_Shell_Installers(){ :; }
		# shellcheck disable=2329
		fStage_Docs(){ :; }
		# shellcheck disable=2329
		fContentScrub(){ :; }
		# shellcheck disable=2034,2030  ## Read by the lifted functions, in this subshell only.
		{ repoRoot="${shellTree}"; utilityDir="${shellTree}/cicd/utility" ;}
		local fn=""
		for fn in fId fStage_Shell; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2030,2031  ## Only the subshell is meant to see it.
		export PATH="${work}/shell-bin:${PATH}" FAKE_SC_VER="$1"
		fStage_Shell
	) 2>&1
}

## shellcheck's warnings change between versions, so a host on another one
## can pass what the container fails.
fId de5gz "shellcheck pin note"
scOld="$(fShellIn 0.10.0)" && rc=0 || rc=$?
scSame="$(fShellIn 0.11.0)" && rcSame=0 || rcSame=$?
scWant="SKIP de5h0 host shellcheck matches the pin (shellcheck 0.10.0 here, and the container pins 0.11.0, so its warnings can differ)"
if ((rc == 0 && rcSame == 0)) && grep -qxF "  ${scWant}" <<< "${scOld}" \
	&& grep -qxF "  PASS de5h0 host shellcheck matches the pin" <<< "${scSame}"
	then fPass
	else fFail "exited ${rc} and ${rcSame}, said: ${scOld//$'\n'/ | } and: ${scSame//$'\n'/ | }"
fi

## The pinned Go, through a stand-in go. The first run that fetches it says
## so on stderr, and that went into the version de572 compares
## (2026102517583389).
goTree="${work}/go-tree"
mkdir -p "${goTree}/cicd/container" "${goTree}/bin" "${goTree}/run"
printf 'FROM scratch\nARG GO_VER=1.26.9\n' > "${goTree}/cicd/container/Dockerfile"
cat > "${goTree}/bin/go" <<- 'EOF_go'
	#!/usr/bin/env bash
	if [[ "${FAKE_GO:-}" == down ]]; then printf 'go: downloading %s (linux/amd64)\ngo: download failed: no network\n' "${GOTOOLCHAIN}" >&2; exit 1; fi
	[[ "${FAKE_GO:-}" != fetch ]] || printf 'go: downloading %s (linux/amd64)\n' "${GOTOOLCHAIN}" >&2
	printf '%s\n' "${GOTOOLCHAIN}"
EOF_go
chmod +x "${goTree}/bin/go"
## Always called in $(...), so a brace group is subshell enough.
fGoPinIn(){  ## FAKE_GO mode, doPackage
	{
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ repoRoot="${goTree}"; _runDir="${goTree}/run"; doPackage="$2"; goToolchain="" ;}
		local fn=""
		for fn in fId fTestPass fTestSkip fTestFail fReactor_Toolchain; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2031  ## The run is in $(...), so only it sees this.
		export PATH="${goTree}/bin:${PATH}" FAKE_GO="$1"
		unset GOTOOLCHAIN
		fReactor_Toolchain
	} 2>&1
}
fId dee9f "de572 passes on the run that fetches the pinned Go"
goBad=""
out="$(fGoPinIn fetch 1)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "${out}" == "  PASS de572 reactor wasm built with the pinned Go" ]]; } || goBad+=" fetching: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(fGoPinIn "" 1)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "${out}" == "  PASS de572 reactor wasm built with the pinned Go" ]]; } || goBad+=" fetched: exited ${rc}, said '${out//$'\n'/ | }';"
## A fetch that fails still says why.
out="$(fGoPinIn down 0)" && rc=0 || rc=$?
{ ((rc == 0)) && [[ "${out}" == "  SKIP de572 reactor wasm built with the pinned Go (could not get go1.26.9: go: download failed: no network)" ]]; } || goBad+=" down: exited ${rc}, said '${out//$'\n'/ | }';"
out="$(fGoPinIn down 1)" && rc=0 || rc=$?
{ ((rc != 0)) && [[ "${out}" == *"FAIL de572 "*"Could not get go1.26.9 for a release: go: downloading go1.26.9 (linux/amd64)"$'\n'"go: download failed: no network" ]]; } || goBad+=" down, packaging: exited ${rc}, said '${out//$'\n'/ | }';"
if [[ -z "${goBad}" ]]
	then fPass
	else fFail "${goBad}"
fi

## The PowerShell lint, against this repo's own file list, with the stand-in
## docker. Each run is "<checkerSkipWhy>|<exit code of the run in the image>".
fPsLintIn(){  ## skip reason, exit code for the run in the image
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho(){ :; }
		# shellcheck disable=2329
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329,2154  ## testId and testName come from the lifted fId.
		fTestPass(){ printf '  PASS %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  SKIP %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL %s %s\n' "${testId}" "${testName}"; fThrowError "$*"; }
		# shellcheck disable=2329,2034  ## Called by the lifted stage, and checkerSkipWhy is its local.
		fGoCheckers_Ready(){ checkerSkipWhy="${PS_SKIP}"; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ containerVolume="zuid-cicd-cache"; containerZigVolume="zuid-zig-cache"; containerZigCache="/zig-cache"; inContainer=0; containerTag="zuid-cicd:t3st"; containerEngine="${work}/engine"
		  projectName="zuid"; runName="20261019-101112"; keepTemp=0; _dockerSteps=0; _dockerPid="${BASHPID}"; buildJobs=3 ;}
		local fn=""
		for fn in fId fInImage fContainer_RunArgs fStage_Shell_PowerShell; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2030,2031  ## Only the subshell is meant to see them.
		export PS_SKIP="$1" ENGINE_RUN_RC="$2" ENGINE_LOG="${work}/engine-pslint"
		fStage_Shell_PowerShell
	) 2>&1
}

## Every tracked .ps1, in the image, and a finding fails it. With no docker it
## skips, the same as the other checkers in the image.
fId de5h7 "PowerShell lint stage"
psBad=""
: > "${work}/engine-pslint"
out="$(fPsLintIn "" 0)" && rc=0 || rc=$?
psLog="$(cat "${work}/engine-pslint")"
if ((rc != 0)) || ! grep -qxF "  PASS de5h6 PSScriptAnalyzer on our PowerShell" <<< "${out}"; then psBad+=" a clean run said '${out}';"; fi
## The real repo. The scratch roots above were set in subshells.
# shellcheck disable=2031
{
	mapfile -t psFiles < <(git -C "${repoRoot}" ls-files --full-name '*.ps1' '*.psm1' '*.psd1')
	((${#psFiles[@]})) || psBad+=" this repo has no PowerShell files to check against;"
	for psFile in "${psFiles[@]}"; do
		grep -qF "${repoRoot}/${psFile}" <<< "${psLog}" || psBad+=" ${psFile} wasn't linted;"
	done
}
grep -q -- "^run .* zuid-cicd:t3st ionice -c 3 nice -n 19 env ZUID_PS_FILES=" <<< "${psLog}" || psBad+=" it didn't run in the image: '${psLog}';"
out="$(fPsLintIn "" 1)" && rc=0 || rc=$?
if ((rc == 0)) || [[ "${out}" != *"PSScriptAnalyzer found something"* ]]; then psBad+=" a finding didn't fail it: '${out}';"; fi
: > "${work}/engine-pslint"
out="$(fPsLintIn "no docker here" 0)" && rc=0 || rc=$?
if ((rc != 0)) || ! grep -qxF "  SKIP de5h6 PSScriptAnalyzer on our PowerShell (no docker here)" <<< "${out}" \
	|| [[ -s "${work}/engine-pslint" ]]; then psBad+=" without docker it said '${out}';"; fi
if [[ -z "${psBad}" ]]
	then fPass
	else fFail "${psBad}"
fi


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
	fSafeRm "${tree}"
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
	printf '#!/bin/sh\necho "zuid v%s build abc12"\necho "Copyright (C) 2026 Jim Collier"\n' "${version}" > "${dir}/repo/dist/zuid-${version}-linux-x86_64"
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
		# shellcheck disable=2030,2034,2154  ## Read by the lifted functions, in this subshell. The defaults come from the lifted fConfig.
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
fWantPublishRefusal ddfb9 "--publish off main" offmain "come from 'main' only" 1 0

fPublishRepo dirty 1.0.0-beta.1
printf 'edit\n' > "${work}/dirty/repo/stray.txt"
fWantPublishRefusal ddfba "--publish on a dirty tree" dirty "uncommitted changes" 1 0

fPublishRepo unpushed 1.0.0-beta.1
git -C "${work}/unpushed/repo" commit -q --allow-empty -m second
fWantPublishRefusal ddfbb "--publish with HEAD unpushed" unpushed "HEAD is not what origin/main has" 1 0

## On the remote only, so the remote is what is asked.
fPublishRepo tagged 1.0.0-beta.1
git -C "${work}/tagged/repo" tag v1.0.0-beta.1
git -C "${work}/tagged/repo" push -q origin v1.0.0-beta.1 2>/dev/null
git -C "${work}/tagged/repo" tag -d v1.0.0-beta.1 >/dev/null
fId ddfbc "tag already on the remote"
out="$(fPublishIn tagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/tagged/gh-create" ]] && [[ -z "$(git -C "${work}/tagged/repo" tag -l)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo gotagged 1.0.0-beta.1
git -C "${work}/gotagged/repo" tag go/v1.0.0-beta.1
fId ddfbd "go/ tag already here"
out="$(fPublishIn gotagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag go/v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/gotagged/gh-create" ]] && [[ -z "$(git -C "${work}/gotagged/repo" ls-remote --tags origin)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo partial 1.0.0-beta.1
rm -f "${work}/partial/repo/dist-incoming/"zuid-1.0.0-beta.1-windows-*.zip
fWantPublishRefusal ddfbe "missing platform, no --allow-partial" partial "No asset for: zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-arm64.zip" 1 0

fId ddfbf "--allow-partial publishes the rest"
fRmIfThere "${work}/partial/repo/dist/release"
out="$(fPublishIn partial 1 1 < /dev/null)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Missing ....: zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-arm64.zip"* ]] && [[ -e "${work}/partial/gh-create" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

## The installers once took no answer as a yes. Here no answer, an empty one
## and a plain 'n' all have to stop it.
fPublishRepo unanswered 1.0.0-beta.1
fId ddfbg "no answer to the prompt means no"
unansweredBad=""
for answer in "" $'\n' $'n\n'; do
	fRmIfThere "${work}/unanswered/repo/dist/release"
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
fWantPublishRefusal ddfbp "stale tarball refused" stale "built from another version" 1 0

## A remote gh cannot match to a GitHub repo, so the notes would have no
## links. The tags must not go out first.
fPublishRepo norepo 1.0.0-beta.1
export GH_STUB_NO_REPO=1
fWantPublishRefusal ddgm7 "gh can't name the repo" norepo "gh cannot tell which GitHub repo this is" 1 0
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

fId ddfbh "'-' in the version means prerelease"
if ((betaRc == 0)) && [[ " ${betaArgs[*]} " == *" --prerelease "* ]] && [[ "${betaArgs[0]:-}" == "v1.0.0-beta.1" ]]
	then fPass
	else fFail "exited ${betaRc}, gh got '${betaArgs[*]:0:6}', said '${betaOut: -160}'"
fi

fId ddfbk "both tags pushed on HEAD"
betaHead="$(git -C "${work}/beta/repo" rev-parse HEAD)"
if [[ "$(fRemoteTags "${work}/beta/repo")" == "go/v1.0.0-beta.1 ${betaHead}"$'\n'"v1.0.0-beta.1 ${betaHead}" ]]
	then fPass
	else fFail "the remote has: $(fRemoteTags "${work}/beta/repo" | tr '\n' ';')"
fi

## GitHub lists a bare tag beside the releases, so its message says what it is.
fId ddywc "go/ tag message"
betaGoMsg="$(git -C "${work}/beta/repo" tag -l --format='%(contents:subject)' go/v1.0.0-beta.1)"
if [[ "${betaGoMsg}" == "Go module tag for v1.0.0-beta.1" ]]
	then fPass
	else fFail "its message is '${betaGoMsg}'"
fi

## Exactly one checksums.txt, listing every other upload once with the right
## hash, and nothing else.
fId ddfbm "one checksums.txt covers every asset"
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

fId ddfbn "'~' becomes '.' in asset names"
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

fId ddwj6 "dist/debug/ stays local"
debugBad=""
for arg in "${betaUploads[@]}"; do
	case "${arg}" in */debug/*|*.debug|*.pdb) debugBad+=" uploaded $(basename "${arg}");" ;; esac
done
if [[ -z "${sumsFile}" ]] || grep -qE '(debug/|\.debug$|\.pdb$)' "${sumsFile}"; then debugBad+=" checksums.txt is missing or lists debug info;"; fi
if [[ -z "${debugBad}" ]]
	then fPass
	else fFail "${debugBad}"
fi

fId ddfbq "release notes from the changelog"
betaNotes=""
for ((argIndex = 0; argIndex < ${#betaArgs[@]}; argIndex++)); do
	if [[ "${betaArgs[argIndex]}" == "--notes" ]]; then betaNotes="${betaArgs[argIndex + 1]:-}"; fi
done
if [[ "${betaNotes}" == *"Notes for this one."* ]] && [[ "${betaNotes}" != *"older one"* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fId ddybx "build number tops the notes"
if [[ "${betaNotes}" == "zuid v1.0.0-beta.1 build abc12"$'\n\n'* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fPublishRepo stable 1.0.0
fId ddfbj "plain version is a full release"
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

fId ddgm2 "download table, OS by CPU"
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

fId ddgm3 "macOS universal spans both columns"
macWant="<tr><th>macOS</th><td colspan=\"2\" align=\"center\">$(fLinks zuid-1.0.0-beta.1-darwin-universal.tgz zuid-1.0.0-beta.1-darwin-universal)</td></tr>"
if [[ "${tableRows[2]:-}" == "${macWant}" ]]
	then fPass
	else fFail "macOS row was '${tableRows[2]:-}'"
fi

## The partial run above left out both Windows files.
fId ddgm4 "dash for a missing file"
partialNotes="$(fNotesOf "${work}/partial/gh-create")"
partialRows=()
mapfile -t partialRows < <(grep '^<tr>' <<< "${partialNotes}" || true)
if [[ "${partialRows[3]:-}" == "<tr><th>Windows</th><td>-</td><td>-</td></tr>" ]] && [[ "${partialRows[1]:-}" == "<tr><th>Linux</th><td><a href="* ]] && [[ "${partialNotes}" != *zuid-1.0.0-beta.1-windows* ]]
	then fPass
	else fFail "rows were '${partialRows[*]:-}'"
fi

fPublishRepo nomac 1.0.0-beta.1
rm -f "${work}/nomac/repo/dist-incoming/"zuid-1.0.0-beta.1-darwin-universal*
fId ddgs7 "one dash for missing macOS"
out="$(fPublishIn nomac 1 1 < /dev/null)" && rc=0 || rc=$?
nomacRows=()
mapfile -t nomacRows < <(grep '^<tr>' <<< "$(fNotesOf "${work}/nomac/gh-create")" || true)
if ((rc == 0)) && [[ "${nomacRows[2]:-}" == "<tr><th>macOS</th><td colspan=\"2\" align=\"center\">-</td></tr>" ]]
	then fPass
	else fFail "exited ${rc}, rows were '${nomacRows[*]:-}'"
fi

fId ddgm5 "release notes order"
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
## A fixed time, not now, so the fixture is the same every run. Written with
## +00:00, which every python takes, so the Z case below fails alone.
fIdsNew(){ PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" new "$@" 2>&1 ;}
mapfile -t fixtureIds <<< "$(fIdsNew -n 4 --at 2026-09-01T12:00:00+00:00 || true)"

## Python before 3.11 reads no trailing Z by itself, and stock macOS has 3.9.
fId ddgqv "test-ids.py --at takes a Z time"
out="$(fIdsNew -n 4 --at 2026-09-01T12:00:00Z)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "$(printf '%s\n' "${fixtureIds[@]}")" ]] && ((${#fixtureIds[@]} == 4))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddgqw "bad --at time, one-line error"
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

fId ddg6y "test-ids.py check on a clean tree"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"3 tests, all unique"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The two arm64 link checks kept their IDs in an array, so the check never saw
## them and would have let a duplicate through.
fId ddg6z "orphan ID caught"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"links=(\"${fixtureIds[3]}:static\")"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' looks like a test ID"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddg70 "stray test-id mark caught"
fIdsTree "fId ${fixtureIds[2]} \"a check\"" "// test-id: ${fixtureIds[3]}"$'\n'"fn helper() void {}"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' is not directly above a test"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddg71 "retired test can stay commented"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"# fWantRefusal ${fixtureIds[3]} \"retired\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ddg72 "test-ids.py fuzzers lists fuzz tests only"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" fuzzers 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "${fixtureIds[0]}"$'\t'"a fuzz test" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## Both ways. The shared rules' decp8, for 2026-10-24 22:00, would be read as a
## stray ID here, so this is the minute before the first commit.
fId dedw3 "IDs are minutes in Crockford base 32"
out="$(fIdsNew --at 2026-07-31T23:59:30+00:00)$(PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" decode dan8z 2>&1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "dan8zdan8z  2026-07-31T23:59Z" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId dedw4 "test-ids.py new skips minutes already taken"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
fixtureNext="$(fIdsNew --at 2026-09-01T12:04:00+00:00)"
out="$(fIdsNew -n 3 --at 2026-09-01T12:00:00+00:00 | tr '\n' ' ')"
if [[ "${out}" == "${fixtureIds[3]} ${fixtureNext} "?????" " ]] && [[ "${out}" != *"${fixtureIds[0]}"* ]]
	then fPass
	else fFail "with ${fixtureIds[*]:0:3} taken, said '${out}'"
fi

## Zig's defer is due to decode to a date in range from 2026-10-26.
fId dedw5 "plain words are not stray IDs"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"dated=1; echo \"dated defer\" \${dated}"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId dedw6 "test lines read PASS, FAIL and SKIP"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(printf '%s\n' "1/3 x.test.a plain test...OK" "2/3 x.test.a fuzz test...SKIP" "3/3 x.test.a plain test...FAIL (TestUnexpectedResult)" \
	| PYTHONDONTWRITEBYTECODE=1 python3 "${idsTree}/cicd/utility/test-ids.py" zig 2>&1)" && rc=0 || rc=$?
lineBad=""
grep -qxF "  PASS ${fixtureIds[1]} a plain test" <<< "${out}" || lineBad+=" no PASS line;"
grep -qxF "  SKIP ${fixtureIds[0]} a fuzz test" <<< "${out}" || lineBad+=" no SKIP line;"
grep -qxF "  FAIL ${fixtureIds[1]} a plain test" <<< "${out}" || lineBad+=" no FAIL line;"
if ((rc == 1)) && [[ -z "${lineBad}" ]]
	then fPass
	else fFail "exited ${rc}:${lineBad} said '${out}'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## An empty or non-numeric SOURCE_DATE_EPOCH, which clang refuses when Zig
## builds its own libunwind and libc into a cold global cache. A real cold build
## takes minutes, so these check the value never reaches zig.

## Each value as "<value>|<what zig should see>|<1 if a note is wanted>".
epochCases=("|unset|0" "  |unset|0" "soon|unset|1" "1700000000|1700000000|0")

fId ddgmn "cicd.bash drops a bad SOURCE_DATE_EPOCH"
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
mkdir -p "${pkgTree}/cicd/utility/include" "${work}/pkgbin"
cp "${utilityDir}/package.bash" "${pkgTree}/cicd/utility/"
cp "${utilityDir}/include/safe-rm.bash" "${pkgTree}/cicd/utility/include/"
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

fId ddgmp "package.bash drops it too"
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
printf '%s\n' "$*" >> "${FAKE_ZIG_ARGS:-/dev/null}"
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
		fTestPass(){ printf '  PASS %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  SKIP %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL %s %s\n%s\n' "${testId}" "${testName}" "$*"; exit 1; }
		local fn=""
		for fn in fId fStage_Zig_Fuzz _fRemoveScratchDirs; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			doQuick="${rigQuick:-0}"; doFuzz=1; zigDir="${dir}/zig"; buildJobs=5; hardJobs=2
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

fId ddg73 "clean fuzz run, one ok line each"
out="$(fFuzzIn clean)" && rc=0 || rc=$?
fuzzBad=""
((${#fuzzLines[@]} >= 2)) || fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
for fuzzLine in "${fuzzLines[@]}"; do
	[[ "${out}" == *"  PASS ${fuzzLine}, fuzzed for "* ]] || fuzzBad+=" no ok line for '${fuzzLine}';"
done
if ((rc == 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

## Before 20261004 the two shared one line, so a find could not say whose it was.
fId ddg74 "a fuzz find fails its own test"
out="" rc=0 fuzzBad=""
if ((${#fuzzLines[@]} < 2)); then
	fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
else
	out="$(fFuzzIn find "${fuzzList[1]#*$'\t'}")" || rc=$?
	[[ "${out}" == *"  FAIL ${fuzzLines[1]}, fuzzed for "* ]] || fuzzBad+=" no FAIL line for the finder;"
	[[ "${out}" == *"  SKIP ${fuzzLines[0]}, fuzzed for "* ]] || fuzzBad+=" no skip line for the other;"
	[[ -s "${work}/fuzz-find/artifacts/fuzz/zig-crash_pipeline-test" ]] || fuzzBad+=" the input was not kept;"
fi
if ((rc != 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

fId ddg75 "broken fuzz run fails them all"
out="$(fFuzzIn broken)" && rc=0 || rc=$?
fuzzBad=""
((${#fuzzLines[@]} >= 2)) || fuzzBad=" found ${#fuzzLines[@]} fuzz tests, wanted at least 2;"
for fuzzLine in "${fuzzLines[@]}"; do
	[[ "${out}" == *"  FAIL ${fuzzLine}, fuzzed for "* ]] || fuzzBad+=" no FAIL line for '${fuzzLine}';"
done
if ((rc != 0)) && [[ -z "${fuzzBad}" ]]
	then fPass
	else fFail "exited ${rc},${fuzzBad} said '${out}'"
fi

## Fuzzing is a hard step, so it gets a quarter of the box, not the build's half.
fId dedp7 "fuzzing takes the hard-step job count"
: > "${work}/fuzz-args"
out="$(FAKE_ZIG_ARGS="${work}/fuzz-args" fFuzzIn clean)" && rc=0 || rc=$?
if ((rc == 0)) && grep -qxF -- "build -j2 test --fuzz=50K" "${work}/fuzz-args"
	then fPass
	else fFail "exited ${rc}, zig was asked: '$(tr '\n' ' ' < "${work}/fuzz-args")'"
fi

## A quick run fuzzes on a short budget, both sides.
fId dedv7 "quick fuzz budget"
budgetBad=""
: > "${work}/fuzz-args"
rigQuick=1 FAKE_ZIG_ARGS="${work}/fuzz-args" fFuzzIn clean > /dev/null || budgetBad+=" the Zig stage exited $?;"
grep -qxF -- "build -j2 test --fuzz=5K" "${work}/fuzz-args" || budgetBad+=" zig was asked '$(tr '\n' ' ' < "${work}/fuzz-args")';"
# shellcheck disable=2016  ## The stand-in's own text.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${FAKE_GO_ARGS:-/dev/null}"\n' > "${fuzzBin}/go"
chmod +x "${fuzzBin}/go"
mkdir -p "${work}/gofuzz/go"
for goQuick in 1 0; do
	: > "${work}/go-args"
	(
		# shellcheck disable=2329  ## Called by the lifted fStage_Go_Fuzz, not here.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329
		fTestPass(){ :; }
		# shellcheck disable=2329
		fTestFail(){ printf '%s\n' "$*"; exit 1; }
		# shellcheck disable=2329
		fId(){ :; }
		fLoad fStage_Go_Fuzz || exit 2
		# shellcheck disable=2034  ## Read by the lifted function.
		{ doQuick="${goQuick}"; goDir="${work}/gofuzz/go"; hardJobs=2; }
		# shellcheck disable=2030,2031  ## Only the subshell's PATH.
		export FAKE_GO_ARGS="${work}/go-args" PATH="${fuzzBin}:${PATH}" PYTHONDONTWRITEBYTECODE=1
		fStage_Go_Fuzz
	) > /dev/null 2>&1 || budgetBad+=" the Go stage exited $? with doQuick=${goQuick};"
	goWant="-fuzztime=20s"; if ((goQuick)); then goWant="-fuzztime=5s"; fi
	grep -qF -- " ${goWant} " "${work}/go-args" || budgetBad+=" go was asked '$(tr '\n' ' ' < "${work}/go-args")' with doQuick=${goQuick};"
done
if [[ -z "${budgetBad}" ]]
	then fPass
	else fFail "${budgetBad}"
fi

## Each case above left its fuzz.log folder in the temp dir, 2 a run, since
## nothing cleaned up after the subshell.
fId ddx66 "fuzz stage cleans TMPDIR"
fuzzLeft="$(find "${fuzzTmp}" -mindepth 1 -maxdepth 1 2>&1 | tr '\n' ' ' || true)"
if [[ -z "${fuzzLeft}" ]]
	then fPass
	else fFail "left ${fuzzLeft}"
fi

## Cleanup used to remove only what sat under /tmp, so with TMPDIR elsewhere
## every scratch folder stayed. It still takes nothing mktemp -d did not make.
fId ddx67 "scratch cleanup takes only tmp.*"
cleanTmp="${work}/clean-tmp"
mkdir -p "${cleanTmp}/tmp.mine" "${cleanTmp}/keep" "${work}/clean-other/tmp.elsewhere" "${work}/clean-target"
ln -s "${work}/clean-target" "${cleanTmp}/tmp.link"
cleanBad=""
if ! out="$(
	fLoad _fRemoveScratchDirs || { echo "no _fRemoveScratchDirs in cicd.bash"; exit 2; }
	# shellcheck disable=2030,2031  ## Its own TMPDIR, with the trailing slash macOS gives.
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

## A stage's scratch folder is made inside TMPDIR, by its physical path, so
## the guard takes it back. Once with TMPDIR through a link, and once with a
## mktemp that ignores TMPDIR for a temp folder behind a link, as macOS's
## does. A bare mktemp -d failed both, on the guard's link refusal.
fId dee5h "scratch folders made physical, inside TMPDIR"
mkRoot="${work}/mkt"
mkdir -p "${mkRoot}/real/run" "${mkRoot}/real/sysT" "${mkRoot}/bin"
ln -s "${mkRoot}/real" "${mkRoot}/var"
realMktemp="$(command -v mktemp)"
printf '#!/usr/bin/env bash\nif [[ "$*" == "-d" ]]; then exec "%s" -d "%s/tmp.XXXXXXXXXX"; fi\nexec "%s" "$@"\n' \
	"${realMktemp}" "${mkRoot}/var/sysT" "${realMktemp}" > "${mkRoot}/bin/mktemp"
## Enough of go for the consumer stage: its build writes a program that runs.
# shellcheck disable=2016  ## Expanded by the stand-in.
printf '#!/usr/bin/env bash\nif [[ "$1" == build ]]; then printf "#!/bin/sh\\nexit 0\\n" > "$3"; chmod +x "$3"; fi\nexit 0\n' > "${mkRoot}/bin/go"
chmod +x "${mkRoot}/bin/mktemp" "${mkRoot}/bin/go"
mkdir "${mkRoot}/gobin"; ln -s "${mkRoot}/bin/go" "${mkRoot}/gobin/go"
fMkCase(){  ## TMPDIR, PATH prefix
	(
		fLoad fStage_Go_Consumer || { echo "no fStage_Go_Consumer in cicd.bash"; exit 2; }
		# shellcheck disable=2329  ## Called by the lifted stage.
		{ fId(){ :; }; fTestPass(){ :; }; fTestFail(){ printf 'fail: %s\n' "$*"; exit 1; }; fThrowError(){ printf '%s\n' "$1"; exit 1; }; }
		# shellcheck disable=2030,2031,2034  ## Read by the lifted stage, in this subshell.
		{ goDir="${repoRoot}/go"; _scratchDirs=(); safeRmOwn="${mkRoot}/real"; }
		# shellcheck disable=2030,2031  ## Only this subshell's.
		export TMPDIR="$1" PATH="$2:${PATH}"
		fStage_Go_Consumer 2>&1 || echo "rc=$?"
	)
}
mkBad=""
out="$(fMkCase "${mkRoot}/var/run" "${mkRoot}/gobin")"
[[ -z "${out}" ]] || mkBad+=" TMPDIR through a link: ${out};"
out="$(fMkCase "${mkRoot}/real/run" "${mkRoot}/bin")"
[[ -z "${out}" ]] || mkBad+=" a mktemp that ignores TMPDIR: ${out};"
mkLeft="$(find "${mkRoot}/real" -mindepth 2 | tr '\n' ' ')"
[[ -z "${mkLeft}" ]] || mkBad+=" left ${mkLeft};"
if [[ -z "${mkBad}" ]]
	then fPass
	else fFail "${mkBad}"
fi

## Every mktemp names its template, or goes through fMkTempDir. A bare one is
## what dee5h caught in the consumer stage, on macOS.
fId dee5j "no bare mktemp in the scripts"
mkBad=""
# shellcheck disable=2031  ## repoRoot is the harness's own.
for mkFile in cicd/cicd.bash install.bash cicd/utility/include/safe-rm.bash cicd/utility/git-hooks/pre-push \
	cicd/utility/{installer-test,cli-test,pipeline-test,package,c-checks,box-run,box-release-test,gomod-prune}.bash; do
	[[ -f "${repoRoot}/${mkFile}" ]] || { mkBad+=" no ${mkFile};"; continue; }
	while IFS= read -r mkLine; do
		mkBad+=" ${mkFile}:${mkLine%%:*};"
	done < <(grep -nE '(\$\(|^[[:space:]]*|[;|&][[:space:]]*)mktemp( |\)|$)' "${repoRoot}/${mkFile}" | grep -vE '^[0-9]+:[[:space:]]*#' \
		| grep -v 'XXX' | grep -v -e '-v mktemp' -e '_fMustBeInPath mktemp' || true)
done
if [[ -z "${mkBad}" ]]
	then fPass
	else fFail "bare mktemp at${mkBad}"
fi

## The guard every recursive removal goes through. The refusals run against a
## stand-in for rm, so a broken guard removes nothing, /usr/bin included.
fId dee1p "safe-rm refuses all but its own"
rmRoot="${work}/saferm"
mkdir -p "${rmRoot}/own/a" "${rmRoot}/own/gone" "${rmRoot}/own/target" "${rmRoot}/vendor/pkg" "${rmRoot}/other/pkg"
ln -s "${rmRoot}/own/target" "${rmRoot}/own/link"
ln -s "${rmRoot}/own" "${rmRoot}/via"
rmBad="$(
	safeRmOwn="${rmRoot}/own"
	(
		# shellcheck disable=2329  ## Called by the guard.
		_fSafeRm_Do(){ printf 'took %s;' "$1"; }
		for bad in "" "own/a" "${rmRoot}/own/../own/a" "${rmRoot}//own/a" "${rmRoot}/own/link" "${rmRoot}/via/a" "${rmRoot}/own/nope" "/usr/bin"; do
			fSafeRm "${bad}" 2>/dev/null || true
		done
		fSafeRm "${rmRoot}/own/a" "${rmRoot}/own/gone" 2>/dev/null || true
		fSafeRm_Under "${rmRoot}/vendor" "${rmRoot}/other/pkg" 2>/dev/null || true
		fSafeRm_Under "${rmRoot}/vendor" "${rmRoot}/vendor"    2>/dev/null || true
		fSafeRm_Under "${rmRoot}/via"    "${rmRoot}/via/a"     2>/dev/null || true
	)
	fSafeRm "${rmRoot}/own/gone/"                              || printf 'refused its own;'
	fSafeRm_Under "${rmRoot}/vendor" "${rmRoot}/vendor/pkg"    || printf 'refused one under its parent;'
	true
)"
[[ ! -e "${rmRoot}/own/gone" ]]   || rmBad+=" kept own/gone;"
[[ ! -e "${rmRoot}/vendor/pkg" ]] || rmBad+=" kept vendor/pkg;"
[[ -d "${rmRoot}/own/target" && -d "${rmRoot}/own/a" ]] || rmBad+=" removed a refused one;"
if [[ -z "${rmBad}" ]]
	then fPass
	else fFail "${rmBad}"
fi

## Each run's folder in HOST_TEMP, numbered past a taken one, and the project's
## stale ones gone: over 2 days old with no live run.pid. A live, a young and a
## foreign-named one stay.
fId dee1q "run folder made, stale ones removed"
htRoot="${work}/ht"
mkdir -p "${htRoot}/zuid/20260101-000000_001" "${htRoot}/zuid/20260101-000000_002" "${htRoot}/zuid/20260101-000000_003" \
	"${htRoot}/zuid/keep-me" "${htRoot}/zuid/20261019-101112_001"
printf '999999999\n' > "${htRoot}/zuid/20260101-000000_001/run.pid"
printf '%s\n' "$$"   > "${htRoot}/zuid/20260101-000000_002/run.pid"
touch -t 202601010000 "${htRoot}/zuid/20260101-000000_001" "${htRoot}/zuid/20260101-000000_002" "${htRoot}/zuid/keep-me"
runBad=""
if ! out="$(
	fLoad fRunDir || { echo "no fRunDir in cicd.bash"; exit 2; }
	# shellcheck disable=2329  ## Called by the lifted fRunDir.
	fThrowError(){ printf '%s\n' "$1"; exit 1; }
	# shellcheck disable=2030,2034  ## Read by the lifted function, in this subshell.
	{ projectName="zuid"; HOST_TEMP="${htRoot}"; safeRmOwn=""; }
	fRunDir 20261019-101112
	## printenv, since it's the exported ones the stages see.
	# shellcheck disable=2154  ## Set by the lifted fRunDir.
	printf 'dir=%s\nvars=%s\nown=%s\npid=%s\n' "${_runDir}" "$(fPrintEnv TMPDIR TEMP TMP)" "${safeRmOwn}" "$(cat "${_runDir}/run.pid")"
)"; then
	runBad=" ${out};"
else
	want="${htRoot}/zuid/20261019-101112_002"
	[[ "${out}" == *"dir=${want}"$'\n'* ]]                 || runBad+=" not ${want}: ${out};"
	[[ "${out}" == *"vars=${want} ${want} ${want} "$'\n'* ]] || runBad+=" TMPDIR, TEMP or TMP not set: ${out};"
	[[ "${out}" == *"own=${htRoot}/zuid"$'\n'* ]]          || runBad+=" the guard's own folder wasn't set;"
	[[ "${out}" == *"pid=$$" ]]                            || runBad+=" run.pid isn't the run's;"
	[[ ! -e "${htRoot}/zuid/20260101-000000_001" ]]         || runBad+=" kept a stale one;"
	[[ -d "${htRoot}/zuid/20260101-000000_002" ]]           || runBad+=" removed a live one;"
	[[ -d "${htRoot}/zuid/20260101-000000_003" ]]           || runBad+=" removed a young one;"
	[[ -d "${htRoot}/zuid/keep-me" ]]                       || runBad+=" removed one not named like a run;"
fi
if [[ -z "${runBad}" ]]
	then fPass
	else fFail "${runBad}"
fi

## A whole run: the folder goes at the end, failed or interrupted too, and
## --keep-temp keeps it and says where.
fId dee1r "run folder gone after a run, kept with --keep-temp"
e2eRoot="${work}/e2e"
mkdir -p "${e2eRoot}"
e2eBad=""
env -u ZUID_CICD_QUIET HOST_TEMP="${e2eRoot}" bash "${cicd}" --list --only go > /dev/null 2>&1 < /dev/null || e2eBad+=" --list failed;"
env -u ZUID_CICD_QUIET HOST_TEMP="${e2eRoot}" bash "${cicd}" --gate --commit > /dev/null 2>&1 < /dev/null && e2eBad+=" the refusal ran;"
left="$(find "${e2eRoot}/zuid" -mindepth 1 2>&1 | tr '\n' ' ' || true)"
[[ -z "${left}" ]] || e2eBad+=" left ${left};"
out="$(env -u ZUID_CICD_QUIET HOST_TEMP="${e2eRoot}" bash "${cicd}" --keep-temp --gate --commit 2>&1 < /dev/null)" || true
kept="$(find "${e2eRoot}/zuid" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)"
if [[ -z "${kept}" || "${kept}" == *$'\n'* ]]; then e2eBad+=" --keep-temp kept '${kept}';"
elif [[ "${out}" != *"kept ${kept} (--keep-temp)"* ]]; then e2eBad+=" --keep-temp didn't say where: ${out:0:200};"
else fSafeRm "${kept}"
fi
if [[ -z "${e2eBad}" ]]
	then fPass
	else fFail "${e2eBad}"
fi

## Ctrl+C, and SIGTERM, which let the run go on after its cleanup until
## 20261025. A stand-in find holds the run just after its folder is made, and
## the signal goes to its whole group, as a terminal's does.
fId dee1s "run folder gone after Ctrl+C or SIGTERM"
intRoot="${work}/int"
mkdir -p "${intRoot}/bin" "${intRoot}/temp"
# shellcheck disable=2016  ## The stand-in's own text.
printf '#!/usr/bin/env bash\n: > "%s/held"\nsleep 30\n' "${intRoot}" > "${intRoot}/bin/find"
chmod +x "${intRoot}/bin/find"
intBad="$(python3 -I -B - "${cicd}" "${intRoot}" <<'PY'
import os, signal, subprocess, sys, time
cicd, root = sys.argv[1], sys.argv[2]
env = dict(os.environ, HOST_TEMP=root + "/temp", PATH=root + "/bin:" + os.environ["PATH"])
env.pop("ZUID_CICD_QUIET", None)
for sig in (signal.SIGINT, signal.SIGTERM):
	if os.path.exists(root + "/held"): os.remove(root + "/held")
	p = subprocess.Popen(["bash", cicd, "--list", "--only", "go"], env=env, stdin=subprocess.DEVNULL,
		stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
		preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
	for _ in range(200):
		if os.path.exists(root + "/held"): break
		time.sleep(0.05)
	else:
		os.killpg(p.pid, signal.SIGKILL); p.wait(); print("never reached the stand-in;"); sys.exit()
	runs = os.listdir(root + "/temp/zuid")
	os.killpg(p.pid, sig)
	rc = p.wait(timeout=20)
	name = signal.Signals(sig).name
	if len(runs) != 1: print("%s: had %s during the run;" % (name, runs))
	if rc == 0: print("%s: exited 0;" % name)
	left = os.listdir(root + "/temp/zuid")
	if left: print("%s: left %s;" % (name, left))
PY
)" || intBad+=" the rig failed;"
if [[ -z "${intBad}" ]]
	then fPass
	else fFail "${intBad}"
fi

## Two runs in a scratch tree, the first stopped partway through a stage by
## SIGTERM, the second left to fail at Docs. Each ends on its Cleanup line,
## the first sweeps a stale run folder, and nothing else is left behind.
fId dee46 "two runs, one killed partway, leave nothing behind"
pileRoot="${work}/pile"
mkdir -p "${pileRoot}/tree/cicd/utility/include" "${pileRoot}/tree/testdata" "${pileRoot}/bin" "${pileRoot}/tmp" "${pileRoot}/temp/zuid/20260101-000000_001"
cp "${cicd}" "${pileRoot}/tree/cicd/"
cp "${cicd%/cicd.bash}/utility/include/safe-rm.bash" "${pileRoot}/tree/cicd/utility/include/"
cp "${cicd%/cicd.bash}/utility/test-ids.py" "${pileRoot}/tree/cicd/utility/"
: > "${pileRoot}/tree/testdata/vectors.tsv"
git init -q -b main "${pileRoot}/tree"
git -C "${pileRoot}/tree" add cicd testdata
git -C "${pileRoot}/tree" -c user.name=t -c user.email=t@t commit -q -m first
printf '999999999\n' > "${pileRoot}/temp/zuid/20260101-000000_001/run.pid"
touch -t 202601010000 "${pileRoot}/temp/zuid/20260101-000000_001"
## Holds the Test IDs step, and passes anything else through.
# shellcheck disable=2016  ## The stand-in's own text.
printf '#!/usr/bin/env bash\nif [[ "$*" == *test-ids.py\\ check* && -n "${PILE_HOLD:-}" ]]; then : > "${PILE_HOLD}"; sleep 30; fi\nexec %s "$@"\n' \
	"$(command -v python3)" > "${pileRoot}/bin/python3"
chmod +x "${pileRoot}/bin/python3"
pileBad="$(python3 -I -B - "${pileRoot}" <<'PY'
import os, signal, subprocess, sys, time
root = sys.argv[1]
env = dict(os.environ, HOST_TEMP=root + "/temp", TMPDIR=root + "/tmp", PATH=root + "/bin:" + os.environ["PATH"])
## Not ZUID_IN_CONTAINER either, when this harness runs in the image.
for k in ("ZUID_CICD_QUIET", "ZUID_RUN_DIR", "ZUID_IN_CONTAINER"): env.pop(k, None)
def snap():
	out = set()
	for top in ("temp", "tmp"):
		for d, dirs, files in os.walk(os.path.join(root, top)):
			out.update(os.path.relpath(os.path.join(d, n), root) for n in dirs + files)
	return out
def last(text):
	lines = [l for l in text.splitlines() if l.strip()]
	return lines[-1] if lines else ""
before = snap() - {"temp/zuid/20260101-000000_001", "temp/zuid/20260101-000000_001/run.pid"}
cmd = ["bash", "cicd/cicd.bash", "--backlog-run-quick", "docs", "--no-container"]
held = root + "/held"
p = subprocess.Popen(cmd, cwd=root + "/tree", env=dict(env, PILE_HOLD=held), stdin=subprocess.DEVNULL,
	stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True, text=True)
for _ in range(600):
	if os.path.exists(held): break
	time.sleep(0.05)
else:
	os.killpg(p.pid, signal.SIGKILL); p.wait(); print("never reached Test IDs;"); sys.exit()
os.killpg(p.pid, signal.SIGTERM)
out1, _ = p.communicate(timeout=30)
if p.returncode == 0: print("the killed run exited 0;")
said = last(out1)
if not said.startswith("Cleanup ....: removed the run folder, "): print("the killed run ended '%s';" % said)
if "1 stale run folder(s)" not in said: print("the stale folder wasn't said;")
p = subprocess.run(cmd, cwd=root + "/tree", env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
	stderr=subprocess.STDOUT, text=True, timeout=120)
said = last(p.stdout)
if not said.startswith("Cleanup ....: removed the run folder, "): print("the second run ended '%s';" % said)
left = sorted(snap() - before)
if left: print("left %s;" % left)
if os.path.exists(root + "/temp/zuid/20260101-000000_001"): print("kept the stale folder;")
PY
)" || pileBad+=" the rig failed;"
if [[ -z "${pileBad}" ]]
	then fPass
	else fFail "${pileBad}"
fi

## Go's module cache in the volume keeps what go.sum names, by the cache's
## own spelling of capitals, and the checksum db. Read-only folders too.
fId dee45 "Go module cache pruned to what go.sum names"
gmRoot="${work}/gomod"; gm="${gmRoot}/mod"
mkdir -p "${gm}/go.uber.org/goleak@v1.3.0" "${gm}/go.uber.org/goleak@v1.2.0/sub" "${gm}/github.com/!burnt!sushi/toml@v1.0.0" \
	"${gm}/github.com/!burnt!sushi/toml@v0.9.0" "${gm}/cache/download/go.uber.org/goleak/@v" "${gm}/cache/download/old.org/x/@v" \
	"${gm}/cache/download/sumdb/sum.golang.org/lookup" "${gm}/example.com/gone@v0.0.1"
for gmFile in v1.3.0.zip v1.3.0.mod v1.2.0.zip v1.2.0.mod list; do echo x > "${gm}/cache/download/go.uber.org/goleak/@v/${gmFile}"; done
echo x > "${gm}/cache/download/old.org/x/@v/v0.1.0.zip"; echo x > "${gm}/cache/download/old.org/x/@v/list"
echo x > "${gm}/cache/download/sumdb/sum.golang.org/lookup/a"
head -c 100000 /dev/zero > "${gm}/go.uber.org/goleak@v1.2.0/sub/big"
chmod -R a-w "${gm}/go.uber.org/goleak@v1.2.0"
printf '%s\n' "go.uber.org/goleak v1.3.0 h1:x" "go.uber.org/goleak v1.3.0/go.mod h1:y" "github.com/BurntSushi/toml v1.0.0/go.mod h1:z" > "${gmRoot}/go.sum"
gmBad=""
out="$(bash "${cicd%/cicd.bash}/utility/gomod-prune.bash" "${gm}" "${gmRoot}/go.sum" 2>&1)" || gmBad+=" exited $?: ${out};"
[[ "${out}" =~ ^pruned\ [1-9][0-9]*$ ]] || gmBad+=" said '${out}';"
gmLeft="$(cd "${gm}" && find . -mindepth 1 | LC_ALL=C sort | tr '\n' ' ')"
gmWant="./cache ./cache/download ./cache/download/go.uber.org ./cache/download/go.uber.org/goleak ./cache/download/go.uber.org/goleak/@v"
gmWant+=" ./cache/download/go.uber.org/goleak/@v/list ./cache/download/go.uber.org/goleak/@v/v1.3.0.mod ./cache/download/go.uber.org/goleak/@v/v1.3.0.zip"
gmWant+=" ./cache/download/sumdb ./cache/download/sumdb/sum.golang.org ./cache/download/sumdb/sum.golang.org/lookup ./cache/download/sumdb/sum.golang.org/lookup/a"
gmWant+=" ./github.com ./github.com/!burnt!sushi ./github.com/!burnt!sushi/toml@v1.0.0 ./go.uber.org ./go.uber.org/goleak@v1.3.0 "
[[ "${gmLeft}" == "${gmWant}" ]] || gmBad+=" left '${gmLeft}';"
## A go.sum that names nothing would take the lot.
: > "${gmRoot}/empty.sum"
bash "${cicd%/cicd.bash}/utility/gomod-prune.bash" "${gm}" "${gmRoot}/empty.sum" > /dev/null 2>&1 && gmBad+=" an empty go.sum ran;"
[[ -d "${gm}/go.uber.org/goleak@v1.3.0" ]] || gmBad+=" an empty go.sum removed what's named;"
if [[ -z "${gmBad}" ]]
	then fPass
	else fFail "${gmBad}"
fi

## A harness, the hook or the packager: inside the cicd.bash run's folder when
## ZUID_RUN_DIR names one, and only that is its own. Alone, or with a
## ZUID_RUN_DIR that's a link or not there, a run folder like cicd.bash's.
fId dee2b "harness folder inside the run's, or its own run folder"
subRoot="${work}/sub"
mkdir -p "${subRoot}/ht" "${subRoot}/zuid/20261019-101112_001" "${subRoot}/elsewhere"
ln -s "${subRoot}/zuid/20261019-101112_001" "${subRoot}/via"
subBad=""
fSubCase(){  ## ZUID_RUN_DIR
	(
		# shellcheck disable=2030,2031  ## Only this subshell's.
		export ZUID_RUN_DIR="$1" HOST_TEMP="${subRoot}/ht"
		fRunDir_Sub zuid cli-test || { echo "fRunDir_Sub failed"; exit 0; }
		# shellcheck disable=2031  ## Set by fRunDir_Sub, in this subshell.
		printf 'dir=%s own=%s tmp=%s run=%s pid=%s\n' "${safeRmRunDir}" "${safeRmOwn}" "$(fPrintEnv TMPDIR TEMP TMP)" \
			"${ZUID_RUN_DIR}" "$(cat "${safeRmRunDir}/run.pid" 2>/dev/null || echo none)"
	)
}
nested="${subRoot}/zuid/20261019-101112_001"
out="$(fSubCase "${nested}")"
want="dir=${nested}/cli-test_001 own=${nested} tmp=${nested}/cli-test_001 ${nested}/cli-test_001 ${nested}/cli-test_001  run=${nested} pid=none"
[[ "${out}" == "${want}" ]] || subBad+=" nested said '${out}';"
out="$(fSubCase "${nested}")"
[[ "${out}" == "dir=${nested}/cli-test_002 "* ]] || subBad+=" a second one said '${out}';"
for subParent in "" "${subRoot}/via" "${subRoot}/gone" "relative/dir"; do
	out="$(fSubCase "${subParent}")"
	if ! [[ "${out}" =~ ^dir=(${subRoot}/ht/zuid/[0-9]{8}-[0-9]{6}_[0-9]{3})\ own=${subRoot}/ht/zuid\ tmp=([^ ]+)\ .*\ run=([^ ]+)\ pid=([0-9]+)$ \
		&& "${BASH_REMATCH[2]}" == "${BASH_REMATCH[1]}" && "${BASH_REMATCH[3]}" == "${BASH_REMATCH[1]}" ]]; then
		subBad+=" ZUID_RUN_DIR '${subParent}' said '${out}';"
	fi
done
[[ -z "$(find "${subRoot}/elsewhere" -mindepth 1)" ]] || subBad+=" wrote outside;"
if [[ -z "${subBad}" ]]
	then fPass
	else fFail "${subBad}"
fi

## The harnesses, the hook, the packager and the installers remove a folder
## only through a guard. Every recursive rm, and every Remove-Item -Recurse,
## has to sit in one of the guard's own functions.
fId dee2c "recursive removals only inside the guards"
guardBad=""
# shellcheck disable=2031  ## Only a subshell much earlier changes it.
for guardFile in cicd/utility/cli-test.bash cicd/utility/pipeline-test.bash cicd/utility/installer-test.bash \
	cicd/utility/git-hooks/pre-push cicd/utility/package.bash cicd/utility/include/safe-rm.bash cicd/cicd.bash install.bash install.ps1 \
	cicd/utility/box-run.bash cicd/utility/box-release-test.bash cicd/utility/box-mac-build.bash cicd/utility/gomod-prune.bash \
	cicd/utility/box-run.ps1 cicd/utility/box-windows-test.ps1; do
	# shellcheck disable=2031  ## Likewise.
	[[ -f "${repoRoot}/${guardFile}" ]] || { guardBad+=" no ${guardFile};"; continue; }
	# shellcheck disable=2031  ## Likewise.
	guardBad+="$(awk -v f="${guardFile}" '
		/^[[:space:]]*#/ { next }
		/^(function )?[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*\(\)[[:space:]]*\{/ { fn = $0; sub(/^function /, "", fn); sub(/[[:space:]]*\(.*/, "", fn); one = /\}[[:space:]]*$/ }
		/^function [A-Za-z-]+ *\{?$/ { fn = $2 }
		/^}/ { fn = "" }
		## Bracketed, so the pattern does not match itself.
		/(^|[^A-Za-z-])rm -[A-Za-z]*[rR]|-exec[ ]rm|Remove-Item.*-Recurs[e]/ {
			if (fn != "_fSafeRm_Do" && fn != "fSafeRm_Under") printf " %s:%d in %s;", f, NR, (fn == "" ? "top level" : fn)
		}
		## A function on one line ends with it.
		one { fn = ""; one = 0 }' "${repoRoot}/${guardFile}")"
done
if [[ -z "${guardBad}" ]]
	then fPass
	else fFail "${guardBad}"
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
fId ddj7x "NewRegistry counts as registry time"
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

fId de56z "called stdlib advisory fails"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0001 stdlib net LookupCNAME; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"GO-0000-0001 in go1.0.1, called from net.LookupCNAME"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId de570 "uncalled stdlib advisory is counted"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0002 stdlib net ""; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"1 advisories for go1.0.1 in code we don't call"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId de571 "any third-party advisory fails"
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

fId de5eb "CodeQL: any finding in our code fails"
out="$(fCodeqlReport "${work}/no-suppressions" zuid/a.go:x/style)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"x/style at zuid/a.go:3: made up"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId de5ec "CodeQL: third-party bugs only"
out="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/style)" && rc=0 || rc=$?
out2="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/bug)" && rc2=0 || rc2=$?
if ((rc == 0 && rc2 == 1)) && [[ "${out}" == *"1 style findings in third-party code"* && "${out2}" == *"x/bug at vendor/m/a.go:3"* ]]
	then fPass
	else fFail "exited ${rc} and ${rc2}, and said '${out//$'\n'/ | }' and '${out2//$'\n'/ | }'"
fi

fId de5ed "CodeQL suppressions"
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

fId de5ee "CodeQL coverage check"
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

## cli-test.bash ran a relative --bin after a cd, so ddj75 ran nothing and
## failed (2026102321183047). The stand-in only keeps a module the way the
## command does, so every other case there fails, and only this one is read.
fId debnh "cli-test.bash takes a relative --bin"
if [[ "$(uname -s)" == Darwin ]]; then
	printf '  SKIP %s %s (%s)\n' "${curId}" "${curName}" "cli-test.bash has no ddj75 on a Mac"; curId=""
else
	mkdir -p "${work}/relbin/stand-in"
	cat > "${work}/relbin/stand-in/zuid" <<- 'STUB'
		#!/usr/bin/env bash
		cacheRoot="${XDG_CACHE_HOME:-}"; [[ "${cacheRoot}" == /* ]] || cacheRoot="${HOME}/.cache"
		mkdir -p "${cacheRoot}/zuid"
		find "${cacheRoot}/zuid" -name 'module-*.cwasm' ! -name module-1111111111111111.cwasm -delete
		echo module > "${cacheRoot}/zuid/module-1111111111111111.cwasm"
		echo abcdef
	STUB
	chmod +x "${work}/relbin/stand-in/zuid"
	out="$(cd "${work}/relbin" && bash "${utilityDir}/cli-test.bash" --bin stand-in/zuid 2>&1 || true)"
	if grep -qxF "  PASS ddj75 a relative XDG_CACHE_HOME falls back to ~/.cache" <<< "${out}"
		then fPass
		else fFail "$(grep -m1 -e 'ddj75' -e 'cli-test:' <<< "${out}" || echo 'no ddj75 line')"
	fi
fi

## --short runs --version, a default identifier and each component, and
## nothing else. Which cases ran is what's read, not whether they passed.
fId dee9g "cli-test.bash --short runs only its short cases"
mkdir -p "${work}/shortbin"
printf '#!/usr/bin/env bash\necho abcdef\n' > "${work}/shortbin/zuid"
chmod +x "${work}/shortbin/zuid"
out="$(bash "${utilityDir}/cli-test.bash" --short --bin "${work}/shortbin/zuid" 2>&1 || true)"
shortRan="$(awk '$1 == "PASS" || $1 == "FAIL" { printf "%s ", $2 }' <<< "${out}")"
if [[ "${shortRan}" == "dcrfc dcrfd dcrfe dcrff dcrfg dcrfh dee9c dee9d dee9e deec4 ddb04 " ]]
	then fPass
	else fFail "ran: ${shortRan:-nothing}, said '$(tail -n 3 <<< "${out}" | tr '\n' ' ')'"
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The pre-push hook, in a scratch repo with a bare remote. The committed
## cicd.bash is a stand-in that writes down what it was asked for.

fId dedps "the hook gates main with --merge-gate"
hookRepo="${work}/hook/repo"
gateLog="${work}/hook/gate.log"
git init -q --bare "${work}/hook/remote.git"
git init -q -b main "${hookRepo}"
git -C "${hookRepo}" config user.name t
git -C "${hookRepo}" config user.email t@t
mkdir -p "${hookRepo}/cicd/utility/git-hooks" "${hookRepo}/cicd/utility/include" "${hookRepo}/go" "${hookRepo}/project" "${work}/hook/temp"
cp "${cicd%/cicd.bash}/utility/git-hooks/pre-push" "${cicd%/cicd.bash}/utility/git-hooks/no-gate-paths" "${hookRepo}/cicd/utility/git-hooks/"
cp "${cicd%/cicd.bash}/utility/include/safe-rm.bash" "${hookRepo}/cicd/utility/include/"
## Where it ran, apart from what it was asked, for dee2d.
# shellcheck disable=2016  ## The stand-in's own text.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nprintf "%%s %%s\\n" "$0" "$TMPDIR" >> "%s"\n' "${gateLog}" "${work}/hook/gate.where" > "${hookRepo}/cicd/cicd.bash"
chmod +x "${hookRepo}/cicd/cicd.bash"
printf 'x\n' > "${hookRepo}/README.md"; printf 'package x\n' > "${hookRepo}/go/x.go"
git -C "${hookRepo}" add -A
git -C "${hookRepo}" commit -q -m first
git -C "${hookRepo}" config core.hooksPath cicd/utility/git-hooks
git -C "${hookRepo}" remote add origin "${work}/hook/remote.git"
fHookPush(){  ## ref
	: > "${gateLog}"
	env -u SKIP_GATE -u ZUID_RUN_DIR HOST_TEMP="${work}/hook/temp" git -C "${hookRepo}" push -q origin "$1" > /dev/null 2>&1 || printf 'push failed\n' >> "${gateLog}"
	tr '\n' ' ' < "${gateLog}"
}
hookBad=""
out="$(fHookPush main)";                          [[ "${out}" == "--merge-gate " ]] || hookBad+=" a new main said '${out}';"
printf 'y\n' >> "${hookRepo}/README.md"; printf 'y\n' > "${hookRepo}/project/notes.txt"
git -C "${hookRepo}" add -A; git -C "${hookRepo}" commit -q -m docs
out="$(fHookPush main)";                          [[ -z "${out}" ]] || hookBad+=" docs only said '${out}';"
printf 'y\n' >> "${hookRepo}/README.md"; printf '// y\n' >> "${hookRepo}/go/x.go"
git -C "${hookRepo}" add -A; git -C "${hookRepo}" commit -q -m code
out="$(fHookPush main)";                          [[ "${out}" == "--merge-gate " ]] || hookBad+=" docs and code said '${out}';"
printf '// z\n' >> "${hookRepo}/go/x.go"
git -C "${hookRepo}" add -A; git -C "${hookRepo}" commit -q -m dev
out="$(fHookPush HEAD:refs/heads/dev)";           [[ -z "${out}" ]] || hookBad+=" a push to dev said '${out}';"
if [[ -z "${hookBad}" ]]
	then fPass
	else fFail "${hookBad}"
fi

## The gate's worktree sits in a run folder like cicd.bash's, which goes after.
fId dee2d "the hook gates in a run folder, removed after"
hookWhere="$(tail -n 1 "${work}/hook/gate.where")"
hookBad=""
[[ "${hookWhere}" =~ ^(${work}/hook/temp/zuid/[0-9]{8}-[0-9]{6}_[0-9]{3})/tree/cicd/cicd\.bash\ (.*)$ && "${BASH_REMATCH[2]}" == "${BASH_REMATCH[1]}" ]] \
	|| hookBad+=" ran as '${hookWhere//$'\n'/; }';"
left="$(find "${work}/hook/temp/zuid" -mindepth 1 2>&1 | tr '\n' ' ' || true)"
[[ -z "${left}" ]] || hookBad+=" left ${left};"
if [[ -z "${hookBad}" ]]
	then fPass
	else fFail "${hookBad}"
fi

## The FreeBSD vendor step, against a stand-in repo with its own key. The
## files are checked against the signed catalog, not pinned by hash, since the
## real repo rebuilds a package under the same version (2026102519140200).
bsdRepo="${work}/bsd-repo"
fBsdPkg(){  ## name-version, then dir:file pairs under usr/local
	local -r pin="$1" tree="${bsdRepo}/build/$1"; shift
	local pair=""
	for pair in "$@"; do mkdir -p "${tree}/usr/local/${pair%:*}"; printf '%s\n' "${pin} ${pair}" > "${tree}/usr/local/${pair%:*}/${pair#*:}"; done
	printf 'name: %s\n' "${pin%-*}" > "${tree}/+MANIFEST"
	tar -cf "${bsdRepo}/build/${pin}.pkg" -C "${tree}" +MANIFEST usr
}
## Writes and signs the catalog, with the entries given, one JSON line each.
fBsdCatalog(){  ## key, then lines
	local -r key="$1"; shift
	printf '%s\n' "$@" > "${bsdRepo}/packagesite.yaml"
	openssl pkey -in "${key}" -pubout -out "${bsdRepo}/packagesite.yaml.pub" 2>/dev/null
	printf '%s' "$(shasum -a 256 "${bsdRepo}/packagesite.yaml" | awk '{print $1}')" \
		| openssl dgst -sha256 -sign "${key}" -out "${bsdRepo}/packagesite.yaml.sig"
	tar -cf "${bsdRepo}/packagesite.pkg" -C "${bsdRepo}" packagesite.yaml packagesite.yaml.sig packagesite.yaml.pub
}
fBsdEntry(){ printf '{"name":"%s","origin":"x/%s","version":"%s","sum":"%s","repopath":"%s","pkgsize":1}' "${1%-*}" "${1%-*}" "${1##*-}" "$2" "$3" ;}
fBsdVendorIn(){  ## key fingerprint, then pins
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fEcho_Clean(){ :; }
		# shellcheck disable=2329
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2329
		_fMustBeInPath(){ command -v "$1" >/dev/null || fThrowError "no $1"; }
		# shellcheck disable=2034  ## Read by the lifted functions.
		{ vendorDir="${bsdRepo}/vendor"; freebsdRepo="file://${bsdRepo}"; freebsdKey="$1"; shift; freebsdPkgs=("$@") ;}
		local fn=""
		for fn in fVendor_FreeBSD fVendor_PkgSum; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		mkdir -p "${vendorDir}"
		fVendor_FreeBSD "${vendorDir}/wasmtime-x86_64-freebsd"
	) 2>&1
}
bsdTools=""
for tool in openssl b2sum shasum; do command -v "${tool}" >/dev/null || bsdTools+=" ${tool}"; done

fId deebc "FreeBSD vendor takes packages its signed catalog vouches for"
if [[ -n "${bsdTools}" ]]; then
	printf '  SKIP %s %s (%s)\n' "${curId}" "${curName}" "no${bsdTools}, which only a Linux release run needs"; curId=""
else
	bsdBad=""
	mkdir -p "${bsdRepo}/build" "${bsdRepo}/All/Hashed"
	## pkg's own sums, from its zbase32 of blake2b-512, which matched the real
	## catalog's entries for libwasmtime-49.0.1 and zstd-1.5.7_2.
	if ! fLoad fVendor_PkgSum; then
		bsdBad+=" no fVendor_PkgSum in cicd.bash;"
	else
		printf 'zuid\n' > "${bsdRepo}/v.txt"; : > "${bsdRepo}/e.txt"
		[[ "$(fVendor_PkgSum "${bsdRepo}/v.txt" '2$')" == "2\$utz65pc85h3f55upjrjxd6yphu8ukaioxk8f7eet13q35miirep3zj3k4ucsg14g4nb1opw4dpe3tbs6c3jby933x3u6xi5wmpgdjfn" ]] || bsdBad+=" wrong pkg sum for a short file;"
		[[ "$(fVendor_PkgSum "${bsdRepo}/e.txt" '2$')" == "2\$au4ro5mebesgyd5a7xbmnjj41mr91dbeb8sqwojtgwaxt59dwkgrpxbnt3m7qcpkuenjgnp1qnczrek8e5sebr7siki9gajd69gfq8d" ]] || bsdBad+=" wrong pkg sum for an empty file;"
		openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${bsdRepo}/key.pem" 2>/dev/null
		openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${bsdRepo}/other.pem" 2>/dev/null
		fBsdPkg libwasmtime-49.0.1 include:wasmtime.h lib:libwasmtime.a share/licenses/libwasmtime-49.0.1:APACHE20
		fBsdPkg zstd-1.5.7_2 lib:libzstd.a share/licenses/zstd-1.5.7_2:BSD3CLAUSE
		## The catalog's newer sum form and path for one, the older for the other.
		wtSum="$(fVendor_PkgSum "${bsdRepo}/build/libwasmtime-49.0.1.pkg" '2$')"
		wtPath="All/Hashed/libwasmtime-49.0.1~${wtSum:0:10}.pkg"
		cp "${bsdRepo}/build/libwasmtime-49.0.1.pkg" "${bsdRepo}/${wtPath}"
		cp "${bsdRepo}/build/zstd-1.5.7_2.pkg" "${bsdRepo}/All/zstd-1.5.7_2.pkg"
		zsSum="$(shasum -a 256 "${bsdRepo}/All/zstd-1.5.7_2.pkg" | awk '{print $1}')"
		bsdEntries=("$(fBsdEntry libwasmtime-49.0.1 "${wtSum}" "${wtPath}")" "$(fBsdEntry zstd-1.5.7_2 "${zsSum}" All/zstd-1.5.7_2.pkg)")
		fBsdCatalog "${bsdRepo}/key.pem" '{"name":"other","origin":"x/other","version":"1"}' "${bsdEntries[@]}"
		bsdKey="$(shasum -a 256 "${bsdRepo}/packagesite.yaml.pub" | awk '{print $1}')"
		out="$(fBsdVendorIn "${bsdKey}" libwasmtime-49.0.1 zstd-1.5.7_2)" && rc=0 || rc=$?
		bsdTree="${bsdRepo}/vendor/wasmtime-x86_64-freebsd"
		{ ((rc == 0)) && [[ -f "${bsdTree}/include/wasmtime.h" && -f "${bsdTree}/lib/libwasmtime.a" && -f "${bsdTree}/lib/libzstd.a" && -f "${bsdTree}/LICENSE" && -f "${bsdTree}/LICENSE-zstd" ]] \
			&& [[ "$(cat "${bsdTree}/.version")" == "libwasmtime-49.0.1 zstd-1.5.7_2" && ! -e "${bsdRepo}/vendor/.freebsd-unpack" ]]; } \
			|| bsdBad+=" first fetch: exited ${rc}, said '${out//$'\n'/ | }';"
		## A rebuild: same version, new bytes, new sum and path in a newly signed catalog.
		fRmIfThere "${bsdTree}"
		printf 'rebuilt\n' >> "${bsdRepo}/build/libwasmtime-49.0.1/usr/local/lib/libwasmtime.a"
		tar -cf "${bsdRepo}/build/libwasmtime-49.0.1.pkg" -C "${bsdRepo}/build/libwasmtime-49.0.1" +MANIFEST usr
		wtSum="$(fVendor_PkgSum "${bsdRepo}/build/libwasmtime-49.0.1.pkg" '2$')"
		wtPath="All/Hashed/libwasmtime-49.0.1~${wtSum:0:10}.pkg"
		cp "${bsdRepo}/build/libwasmtime-49.0.1.pkg" "${bsdRepo}/${wtPath}"
		bsdEntries[0]="$(fBsdEntry libwasmtime-49.0.1 "${wtSum}" "${wtPath}")"
		fBsdCatalog "${bsdRepo}/key.pem" "${bsdEntries[@]}"
		out="$(fBsdVendorIn "${bsdKey}" libwasmtime-49.0.1 zstd-1.5.7_2)" && rc=0 || rc=$?
		{ ((rc == 0)) && grep -q '^rebuilt$' "${bsdTree}/lib/libwasmtime.a"; } || bsdBad+=" rebuild: exited ${rc}, said '${out//$'\n'/ | }';"
	fi
	if [[ -z "${bsdBad}" ]]
		then fPass
		else fFail "${bsdBad}"
	fi
fi

fId deebd "FreeBSD vendor refuses what its signed catalog doesn't vouch for"
if [[ -n "${bsdTools}" ]]; then
	printf '  SKIP %s %s (%s)\n' "${curId}" "${curName}" "no${bsdTools}, which only a Linux release run needs"; curId=""
elif [[ ! -f "${bsdRepo}/packagesite.pkg" ]]; then
	fFail "deebc made no stand-in repo"
else
	bsdBad=""
	## Each case runs from an empty vendor dir and must leave no tree behind.
	fWantBsdRefusal(){  ## label, text the refusal must contain, pins...
		local -r label="$1" want="$2"; shift 2
		fRmIfThere "${bsdTree}"
		out="$(fBsdVendorIn "${bsdKey}" "$@")" && rc=0 || rc=$?
		{ ((rc != 0)) && [[ "${out}" == *"${want}"* && ! -e "${bsdTree}" ]]; } || bsdBad+=" ${label}: exited ${rc}, said '${out//$'\n'/ | }';"
	}
	fWantBsdRefusal "version moved" "FreeBSD's catalog has no libwasmtime-50.0.0, only version 49.0.1" libwasmtime-50.0.0 zstd-1.5.7_2
	fWantBsdRefusal "not in catalog" "FreeBSD's catalog has no nothere-1, only version none" nothere-1
	## A dep's version later on the line is not the package's.
	fBsdCatalog "${bsdRepo}/key.pem" "${bsdEntries[0]%\}}"',"deps":{"zstd":{"origin":"x/zstd","version":"9.9"}}}' "${bsdEntries[1]}"
	fWantBsdRefusal "dep's version" "FreeBSD's catalog has no libwasmtime-9.9, only version 49.0.1" libwasmtime-9.9 zstd-1.5.7_2
	fBsdCatalog "${bsdRepo}/key.pem" "${bsdEntries[@]}"
	cp "${bsdRepo}/${wtPath}" "${bsdRepo}/wt.keep"
	printf 'x' >> "${bsdRepo}/${wtPath}"
	fWantBsdRefusal "changed package" "FreeBSD libwasmtime-49.0.1 does not match its signed catalog" libwasmtime-49.0.1 zstd-1.5.7_2
	cp "${bsdRepo}/wt.keep" "${bsdRepo}/${wtPath}"
	printf 'x' >> "${bsdRepo}/All/zstd-1.5.7_2.pkg"
	fWantBsdRefusal "changed package, sha256 form" "FreeBSD zstd-1.5.7_2 does not match its signed catalog" libwasmtime-49.0.1 zstd-1.5.7_2
	## A catalog edited after signing.
	cp "${bsdRepo}/packagesite.yaml.sig" "${bsdRepo}/packagesite.yaml.pub" "${bsdRepo}/build/"
	printf '\n' >> "${bsdRepo}/packagesite.yaml"
	tar -cf "${bsdRepo}/packagesite.pkg" -C "${bsdRepo}" packagesite.yaml packagesite.yaml.sig packagesite.yaml.pub
	fWantBsdRefusal "edited catalog" "The FreeBSD catalog's signature does not check out" libwasmtime-49.0.1
	## Signed and good, but not with the key that was pinned.
	fBsdCatalog "${bsdRepo}/other.pem" "${bsdEntries[@]}"
	fWantBsdRefusal "other key" "The FreeBSD catalog is signed with a key that isn't FreeBSD's" libwasmtime-49.0.1
	if [[ -z "${bsdBad}" ]]
		then fPass
		else fFail "${bsdBad}"
	fi
fi

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261025 JC: The box plans and the full --list as Linux, so they hold on a Mac.
##		- 20261025 JC: The FreeBSD vendor step against a stand-in signed catalog.
##		- 20261025 JC: The pinned Go on its first fetch. cli-test.bash --short, and the arm64 box's short run.
##		- 20261025 JC: The cleanup line, the Go module prune, and 2 runs with one killed leaving nothing.
##		- 20261025 JC: The release stand-in prints the new --version lines, and only the first tops the notes.
##		- 20261025 JC: Its folder is a run folder. The harness run folder, the guard scan, and the hook's run folder.
##		- 20261025 JC: Which runs start the macos workflow, and its start and result steps.
##		- 20261025 JC: Test IDs in minutes, PASS, FAIL and SKIP lines.
##		- 20261025 JC: The gate flags, and the pre-push hook's --merge-gate and docs skip.
##		- 20261025 JC: Areas for --backlog-run-quick, and --list.
##		- 20261025 JC: The Zig cache tidy, and the Zig cache volume in the run arguments.
##		- 20261025 JC: The container by default, --no-container.
##		- 20261023 JC: --no-fuzz, --no-profile, --no-demo. cli-test.bash with a relative --bin.
##		- 20261019 JC: The CodeQL report, and CodeQL's image under --container.
##		- 20261019 JC: --leakcheck.
##		- 20261019 JC: --leakcheck is default, --no-leakcheck.
##		- 20261019 JC: --ci is --gate again.
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
