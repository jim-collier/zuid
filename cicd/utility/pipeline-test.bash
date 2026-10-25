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
fWantRefusal ErOjF6y "-h inside a message"  "after --only" -m 'fix the -h case' --only nope

## --commit used to take an optional message, and swallowed whatever flag came
## next as one.
fWantRefusal ErOjF6z "--commit leaves the next flag alone"    "after --only" --commit --only nope
fWantRefusal ErOjF70 "-m won't take a flag"               "Expecting a value after -m" -m --quick
fWantRefusal ErOjF71 "--backup with --commit"     "--backup already commits" --backup --commit
## Retired 20261003: --publish is implemented now, so this refusal is gone on
## purpose. The publish cases below cover it instead.
# fWantRefusal ErOjF72 "--publish says it is not there yet"             "Not implemented yet" --publish
fWantRefusal ErOjF73 "unknown argument named"                   "'--bogus'" --bogus
fWantRefusal ErgqYt2 "--allow-partial needs --publish"   "only means something with --publish" --allow-partial
fWantRefusal ErgqYt3 "--publish with --only go"            "--publish needs the Zig side" --publish --only go
fWantRefusal EsJ9SjI "--publish with --container"          "does not go with --container" --publish --container
fWantRefusal EshGwj4 "--gate won't commit"                  "--gate only builds and tests" --gate --commit
fWantRefusal EshGwj5 "--gate won't package"                 "--gate only builds and tests" --gate --package
## --ci was renamed back to --gate with no alias on 20261019, and came back as
## another name for --merge-gate on 20261025. The bad --only after it keeps a
## run from starting, and shows --ci was taken.
fWantRefusal Et6FB1m "--ci is taken"                    "after --only" --ci --only nope
fWantRefusal Eshc39l "--publish with --no-package"         "does not go with --no-package" --publish --no-package

fId EsJ9cHS "--container from inside one"
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
fId ErOjF74 "prerelease is below its floor"
if ! fLoad fVersion_AtLeast; then
	fFail "no fVersion_AtLeast in cicd.bash"
elif fVersion_AtLeast "0.16.0-dev.1+abc" "0.16.0"; then
	fFail "0.16.0-dev.1 passed a 0.16.0 floor"
else
	fPass
fi

fId ErOjF75 "version floor compare"
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

fId ErOjF76 "no commit on main"
out="$(fCommitIn "${scratchRepo}" || true)"
if [[ "${out}" == *"Refusing to commit to 'main'"* && -z "$(git -C "${scratchRepo}" log --format=%h -1 --skip 1 2>/dev/null || true)" ]]
	then fPass
	else fFail "said '${out}'"
fi

fId ErOjF77 "no commit on a detached HEAD"
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

fId Etj0Hby "job counts: half, a quarter when busy, a quarter for hard steps"
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
fId Etj0Hbz "a bad load reading counts as no load"
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

fId Etj0Hc0 "counts are checked again before each step"
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
fId Etj0NB7 "the run lowers its own priority"
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
fId Etj0Hc3 "codeql.bash takes its thread count from cicd.bash"
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

fId Erm7vCh "sync in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fStage_Sync)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Remote .....: none"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Erm7vCi "preflight in a linked worktree"
out="$(fGitCheckIn "${worktreeDir}" fPreflight)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Branch .....: side"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Erm7vCj "sync and preflight want the checkout's top"
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
fId ErqU8vW "repo root through a symlink"
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

fId Erm7vCk "default backup skips linked worktrees"
outWorktree="$(fInitIn "${worktreeDir}")" && rc=0 || rc=$?
outMain="$(fInitIn "${worktreeMain}")" || rc=$?
if ((rc == 0)) && [[ "${outWorktree}" == "doBackup=0 backupInWorktree=1" ]] && [[ "${outMain}" == "doBackup=1 backupInWorktree=0" ]]
	then fPass
	else fFail "exited ${rc}, worktree said '${outWorktree}', main checkout said '${outMain}'"
fi

fId Erm7vCl "--backup refused in a linked worktree"
out="$(fInitIn "${worktreeDir}" --backup)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"linked worktree"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The pre-push hook runs --gate inside a push, so it must not sync, install,
## or push again.
fId EshGwj6 "what --gate leaves out"
out="$(showGate=1 fInitIn "${worktreeMain}" --gate)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doQuick=1 doSync=0 doBackup=0 doDogfood=0 doPackage=0" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The Go cross builds are seconds, so a quick run and the pre-push one get
## them as well as a full run.
fId Et6FB1n "every run mode cross-compiles"
out="$(showCross=1 fInitIn "${worktreeMain}"; showCross=1 fInitIn "${worktreeMain}" --quick; showCross=1 fInitIn "${worktreeMain}" --gate)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doCross=1\ndoCross=1\ndoCross=1' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

## The leak checks take about 10 minutes, so a full run has them and a quick or
## pre-push one only if asked. --no-leakcheck drops them from any run.
fId EtAUMRF "--leakcheck is default, off for quick and gate"
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
fId Etab8wo "--no-fuzz, --no-profile, --no-demo"
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
fId Etj4p9f "gate flags refuse the stages that write"
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
fId Etj4p9g "what the gate flags run"
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
fId Etj4p9h "--long, --slow, and the alias line"
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
fId Etjcehs "areas after --backlog-run-quick"
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

fId Etab8wp "the stage calls follow the flags"
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
fId Etika82 "bash 3.2 cases run outside the container"
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

fId EtAUMRH "--help on --leakcheck"
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

fId EshbzZU "full Linux x86_64 run packages"
out="$(fPackageIn Linux x86_64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZV "no llvm-objcopy, no package"
out="$(fPackageIn Linux x86_64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip=no llvm-objcopy"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZW "full Mac run packages"
out="$(fPackageIn Darwin arm64 without)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=1 skip=" ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZX "other hosts skip packaging"
out="$(fPackageIn FreeBSD amd64 with)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "doPackage=0 skip="*"--package"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId EshbzZY "what turns packaging off"
out="$(fPackageIn Linux x86_64 with --quick; fPackageIn Linux x86_64 with --no-package; fPackageIn Linux x86_64 with --only go)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == $'doPackage=0 skip=\ndoPackage=0 skip=\ndoPackage=0 skip=' ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId Eshc39k "--package forces it"
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

fId EshcCTw "dogfood copies release files"
out="$(fDogfoodIn "${dogRoot}" 1)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "$(cat "${dogRoot}/linux/zuid" 2>/dev/null)" == "linux-release" && "$(cat "${dogRoot}/mswin/zuid.exe" 2>/dev/null)" == "windows-release" ]] \
	&& [[ ! -e "${dogRoot}/macos" && ! -e "${dogRoot}/fallback/zuid" && "$(ls "${dogRoot}/linux")" == "zuid" ]]
	then fPass
	else fFail "exited ${rc}, said '${out//$'\n'/ | }'"
fi

fId EshcCTx "dogfood falls back to zig-out"
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

fId EsJ9SjE "image built by recipe hash"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 0)" && rc=0 || rc=$?
log="$(cat "${work}/engine-main" 2>/dev/null || true)"
## Older tags wait for the end of a run that passed, since 2026102416233101.
if ((rc == 0)) && grep -qxF "build --label dev.project=zuid --label dev.run=20261019-101112 -t ${newTag} ${mainReal}/cicd/container" <<< "${log}" \
	&& ! grep -q "^rmi " <<< "${log}"
	then fPass
	else fFail "exited ${rc}, asked: ${log//$'\n'/ | }; said '${out}'"
fi

fId EsJ9SjF "container run arguments"
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

fId EsJ9SjG "worktree's git dir in the container"
out="$(fContainerIn "${worktreeDir}" "${work}/engine-wt" 0)" && rc=0 || rc=$?
if ((rc == 0)) && grep -q -- "^run .* -v ${mainReal}/.git:${mainReal}/.git " "${work}/engine-wt"
	then fPass
	else fFail "exited ${rc}, asked: $(grep '^run ' "${work}/engine-wt" || true)"
fi

fId EsJ9SjH "container failure fails the stage"
out="$(fContainerIn "${worktreeMain}" "${work}/engine-main" 3)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"The run in the container failed"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The run inside is a new cicd.bash, which only knows what it's handed.
fId EtAUMRG "--container passes --leakcheck in"
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
fId Etab8wq "--container passes --no-fuzz, --no-profile in"
: > "${work}/engine-slow"
out="$(quick=0 fuzz=0 profile=1 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0; quick=0 fuzz=1 profile=0 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0; quick=0 fuzz=1 profile=1 fContainerIn "${worktreeMain}" "${work}/engine-slow" 0)" && rc=0 || rc=$?
runs="$(grep '^run ' "${work}/engine-slow" | sed 's/.* --only go //' || true)"
if ((rc == 0)) && [[ "${runs}" == $'--package --no-leakcheck --no-fuzz\n--package --no-leakcheck --no-profile\n--package --no-leakcheck' ]]
	then fPass
	else fFail "exited ${rc}, asked: ${runs//$'\n'/ | }"
fi

## A quick run fuzzes now, so --quick no longer says --no-fuzz for it.
fId EtjfGH2 "--container passes --no-fuzz in on a quick run"
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
fId EtB0hIu "container run keeps the outer stamp"
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
fId EtB5PUX "stage header layout"
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
fId Etj8iKE "step lines"
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
fId Etj8iKF "image's steps match the outside's count"
planBad=""
fPlanIn(){  ## inContainer, planContainer, then name=value settings
	(
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			inContainer="$1"; planContainer="$2"; doContainer=0; repoRoot="${work}/plan/repo"
			doSync=1; doGate=0; doFullGate=0; gateFlag=""; doQuick=0; doDemo=1; doPackage=0; noPackage=0; packageSkipWhy=""
			onlyToolchain=""; doGo=1; doZig=1; doFuzz=1; doCross=1; doLeakcheck=1; leakAsked=0; doProfile=1
			doPublish=0; doDogfood=1; doBackup=1; backupInWorktree=0; commitAsked=0; doCommit=0; doPush=0
			_stepTitles=(); _stepOffs=(); _stepPlanning=0; _stepElsewhere=0; _stepAt=0; _stepTotal=0
			read -r -a runAreas <<< "${planAreas:-}"; areaWhy="not in --backlog-run-quick ${planAreas:-}"
		}
		shift 2
		local kv=""; for kv in "$@"; do printf -v "${kv%%=*}" '%s' "${kv#*=}"; done
		local fn=""
		for fn in fSteps fSteps_Checks fSteps_Scrub fSteps_FuzzWhy fSteps_Packages fSteps_Plan fStep_Off fArea; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		## Marks the ones the image runs.
		# shellcheck disable=2329  ## Called by the lifted fSteps.
		fStep(){ if ((_stepPlanning)); then _stepTitles+=("$( ((_stepElsewhere)) && echo '*')$1"); fi; }
		fSteps_Plan
		printf '%s\n' "${_stepTitles[@]}"
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
fId Etjceht "areas pick the steps"
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
fId Etjcehu "--list runs nothing, and names every test"
listBad=""
logsBefore="$(find "${cicd%/cicd.bash}/artifacts" -maxdepth 1 -newer "${cicd}" 2>/dev/null | sort || true)"
out="$(bash "${cicd}" --list --backlog-run-quick go --no-container < /dev/null 2>&1)" && rc=0 || rc=$?
((rc == 0)) || listBad+=" exited ${rc}: ${out:0:200};"
grep -qE '^[0-9]+\. Go: build, vet, format, test$' <<< "${out}" || listBad+=" no Go step;"
grep -qx '      ElmNxqS TestVectors' <<< "${out}" || listBad+=" no TestVectors under it;"
grep -qE '^[0-9]+\. Zig' <<< "${out}" && listBad+=" a Zig step with only go named;"
grep -qE ' steps, [0-9]+ tests\. Nothing was run\.$' <<< "${out}" || listBad+=" no closing line;"
out="$(bash "${cicd}" --list --no-container --package --leakcheck < /dev/null 2>&1)" && rc=0 || rc=$?
((rc == 0)) || listBad+=" the full list exited ${rc};"
listed="$(sed -n 's/^      \([0-9A-Za-z]\{7\}\) .*/\1/p' <<< "${out}" | sort -u)"
known="$(python3 -I -B -c 'import importlib.util as u, sys; s = u.spec_from_file_location("t", sys.argv[1]); t = u.module_from_spec(s); s.loader.exec_module(t); print("\n".join(sorted({i for i, *_ in t.fScan() if i})))' "${cicd%/cicd.bash}/utility/test-ids.py")"
missing="$(comm -13 <(printf '%s\n' "${listed}") <(printf '%s\n' "${known}") | tr '\n' ' ')"
[[ -n "${known}" && -z "${missing// /}" ]] || listBad+=" not in any step: ${missing:0:200};"
logsAfter="$(find "${cicd%/cicd.bash}/artifacts" -maxdepth 1 -newer "${cicd}" 2>/dev/null | sort || true)"
[[ "${logsAfter}" == "${logsBefore}" ]] || listBad+=" it wrote to cicd/artifacts;"
if [[ -z "${listBad}" ]]
	then fPass
	else fFail "${listBad}"
fi

## --quick fuzzes and dogfoods, per the 2026-10-24 CICD reset. The gate flags
## do neither.
fId EtjfGH0 "--quick fuzzes and dogfoods, the gates don't"
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
fId EtAj5P2 "CodeQL image only with --leakcheck"
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
fId EtaIbeg "plain run drops a CodeQL image on an old main one"
staleBad=""
for pass in built found; do
	: > "${work}/engine-stale"
	out="$(fContainerIn "${worktreeMain}" "${work}/engine-stale" 0)" && rc=0 || rc=$?
	log="$(cat "${work}/engine-stale")"
	rmis="$(grep '^rmi ' <<< "${log}" || true)"
	((rc == 0)) || staleBad+=" ${pass}: exited ${rc}, said '${out}';"
	! grep -qE '^(build|run) .*codeql' <<< "${log}" || staleBad+=" ${pass}: built or ran CodeQL;"
	## Since 2026102416233101 nothing goes during the stage. EtitVm9 has the
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
fId Et9VtIq "Go checkers with and without docker"
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

fId Etij2SB "--container, --no-container"
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
fId Etij2SC "the container where docker answers"
out="$(pickSkip="${pickSkipWhy}" fPickIn "${work}/engine-pick")" && rc=0 || rc=$?
if ((rc == 0)) && grep -qxF "build --label dev.project=zuid --label dev.run=20261019-101112 -t ${newTag} ${mainReal}/cicd/container" "${work}/engine-pick" \
	&& [[ "${out}" == *$'\n'"doContainer=1 doPackage=1 skip= image= tag=${newTag}" ]]
	then fPass
	else fFail "exited ${rc} and said: ${out//$'\n'/ | }"
fi

fId Etij2SD "this machine with a note, without docker"
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
fId Etij2SE "--container, --no-container and the run inside decide alone"
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
fId Etij2SF "checkers skip on an image that didn't build"
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
fId EtijCAL "the hook's Zig cache goes in"
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
fId EtimFcG "a Zig cache linked out of the tree goes in"
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
fId EtimFcH "SDE goes in for packaging"
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
fId EtAHpAi "mounts for a folder outside the repo"
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
fId Etj0Hc2 "steps in the image get the step's job count"
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
fId EtitVm7 "containers, images and volumes are labeled and named"
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
fId EtitVm8 "a run's containers go at its end, unless --keep-temp"
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
## of build cache, the volume's cap, and one line.
fTidyIn(){  ## engine log; label, cap come in as variables
	(
		# shellcheck disable=2329  ## Called by the lifted functions.
		fEcho_Clean(){ printf '%s\n' "$*"; }
		for fn in fContainer_Tidy fContainer_StopRun fContainer_DropOlder fContainer_VolumeCap fDocker_Bytes fCodeql_Tag; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			repoRoot="$(cd "${worktreeMain}" && pwd -P)"; containerEngine="${work}/engine"; projectName="zuid"; runName="20261019-101112"
			containerImage="zuid-cicd"; codeqlImage="zuid-codeql"; containerVolume="zuid-cicd-cache"; zigCacheCapMB=2048; keepTemp=0
			containerTag="${newTag}"; _dockerEngine="${containerEngine}"; _dockerProject="zuid"; _dockerRun="${runName}"; _dockerGone=(); _dockerPid="${BASHPID}"
		}
		mkdir -p "${repoRoot}/cicd/container/codeql"; echo "FROM codeql" > "${repoRoot}/cicd/container/codeql/Dockerfile"
		ENGINE_NEW="${newTag}" ENGINE_NEW_CODEQL="zuid-codeql:$(echo "FROM codeql" | git hash-object --stdin | cut -c1-12)-${newTag#*:}"
		# shellcheck disable=2030,2031  ## The stub reads them; each case has its own.
		export ENGINE_LOG="$1" ENGINE_NEW ENGINE_NEW_CODEQL ENGINE_DANGLING=$'d4ng1e\n' ENGINE_VOLUME_LABEL="${label-zuid}" ENGINE_CAP_OUT="${cap:-}" ENGINE_DF="${work}/df-sizes"
		printf '%s\n' "142.5GB 7.052GB 14.91GB 137.3GB" "${dfAfter-139.6GB 7.052GB 14.61GB 136.8GB}" > "${ENGINE_DF}"
		: > "${ENGINE_LOG}"; rm -f "${ENGINE_LOG}.df"
		fContainer_Tidy
		printf 'run=%s\n' "${_dockerRun}"
	) 2>&1
}
fId EtitVm9 "a passing run tidies docker by label"
tidyBad=""
out="$(cap="emptied 3145728" fTidyIn "${work}/engine-tidy")" || tidyBad+=" exited $?: ${out};"
log="$(cat "${work}/engine-tidy")"
rmis="$(grep '^rmi ' <<< "${log}" || true)"
[[ "${rmis}" == "rmi zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld"$'\n'"rmi zuid-cicd:0ld0ld0ld0ld"$'\n'"rmi d4ng1e" ]] || tidyBad+=" removed '${rmis//$'\n'/ | }';"
grep -qxF "image ls zuid-cicd --filter label=dev.project=zuid --format {{.CreatedAt}}"$'\t'"{{.Repository}}:{{.Tag}}" <<< "${log}" || tidyBad+=" tags not listed by label;"
grep -qxF "images -q --filter dangling=true --filter label=dev.project=zuid" <<< "${log}" || tidyBad+=" dangling not by label;"
grep -qxF "builder prune -f --filter until=168h" <<< "${log}" || tidyBad+=" no builder prune;"
grep -q -- "^run --rm --init .* -v zuid-cicd-cache:/cache --name zuid-20261019-101112-cache-cap --label dev.project=zuid --label dev.run=20261019-101112 --cpus 1 --cpu-shares 256 ${newTag} ionice -c 3 nice -n 19 sh -c" <<< "${log}" \
	&& grep -q -- " sh 2097152$" <<< "${log}" || tidyBad+=" no capped volume check;"
! grep -qE '^(rmi|.*-f ).*(prevprevprev|'"${newTag#*:}"')' <<< "${rmis}" || tidyBad+=" removed a kept tag;"
! grep -qE '^(system prune|rmi -f|image prune)' <<< "${log}" || tidyBad+=" pruned wide;"
want="Docker .....: removed zuid-codeql:0ld0ld0ld0ld-0ld0ld0ld0ld, zuid-cicd:0ld0ld0ld0ld, 1 dangling image(s), zuid-cicd-cache's contents, 3072 MB, build cache over a week old; about 3.7 GB freed"
[[ "${out}" == *"${want}"$'\n'"run=" ]] || tidyBad+=" said '${out//$'\n'/ | }';"
out="$(label="" dfAfter="" fTidyIn "${work}/engine-tidy-nolabel")" || tidyBad+=" unlabeled exited $?;"
! grep -q -- "-cache-cap" "${work}/engine-tidy-nolabel" || tidyBad+=" checked an unlabeled volume;"
## A df that didn't answer is no reason to claim the whole lot was freed.
[[ "${out}" == *"; an unknown amount freed, since docker system df didn't answer"$'\n'* ]] || tidyBad+=" a silent df said '${out//$'\n'/ | }';"
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
		}
		local fn=""
		for fn in fZigCache_Tidy fZigCache_Empty; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fZigCache_Tidy
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

fId Etipgwi "a Zig cache over the cap is emptied whole"
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
if [[ -z "${capBad}" ]]
	then fPass
	else fFail "${capBad} said '${out//$'\n'/ | }'"
fi

fId Etipgwj "a Zig cache from another Zig is emptied, this one's kept"
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

fId Etipgwk "the image's Zig cache volume, only inside"
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

fId Etipgwl "a Zig cache is emptied only where it's ours"
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

fId Etipgwm "the Zig caches are tidied where Zig ran"
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
		fTestPass(){ printf '  ok ....: %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  skip ..: %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL ..: %s %s\n' "${testId}" "${testName}"; fThrowError "$*"; }
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
fId EtB4VLJ "shellcheck pin note"
scOld="$(fShellIn 0.10.0)" && rc=0 || rc=$?
scSame="$(fShellIn 0.11.0)" && rcSame=0 || rcSame=$?
scWant="skip ..: EtB4gns host shellcheck matches the pin (shellcheck 0.10.0 here, and the container pins 0.11.0, so its warnings can differ)"
if ((rc == 0 && rcSame == 0)) && grep -qxF "  ${scWant}" <<< "${scOld}" \
	&& grep -qxF "  ok ....: EtB4gns host shellcheck matches the pin" <<< "${scSame}"
	then fPass
	else fFail "exited ${rc} and ${rcSame}, said: ${scOld//$'\n'/ | } and: ${scSame//$'\n'/ | }"
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
		fTestPass(){ printf '  ok ....: %s %s\n' "${testId}" "${testName}"; }
		# shellcheck disable=2329
		fTestSkip(){ printf '  skip ..: %s %s (%s)\n' "${testId}" "${testName}" "$*"; }
		# shellcheck disable=2329
		fTestFail(){ printf '  FAIL ..: %s %s\n' "${testId}" "${testName}"; fThrowError "$*"; }
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
fId EtB6KVG "PowerShell lint stage"
psBad=""
: > "${work}/engine-pslint"
out="$(fPsLintIn "" 0)" && rc=0 || rc=$?
psLog="$(cat "${work}/engine-pslint")"
if ((rc != 0)) || ! grep -qxF "  ok ....: EtB6KVF PSScriptAnalyzer on our PowerShell" <<< "${out}"; then psBad+=" a clean run said '${out}';"; fi
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
if ((rc != 0)) || ! grep -qxF "  skip ..: EtB6KVF PSScriptAnalyzer on our PowerShell (no docker here)" <<< "${out}" \
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
fWantPublishRefusal ErgqYt4 "--publish off main" offmain "come from 'main' only" 1 0

fPublishRepo dirty 1.0.0-beta.1
printf 'edit\n' > "${work}/dirty/repo/stray.txt"
fWantPublishRefusal ErgqYt5 "--publish on a dirty tree" dirty "uncommitted changes" 1 0

fPublishRepo unpushed 1.0.0-beta.1
git -C "${work}/unpushed/repo" commit -q --allow-empty -m second
fWantPublishRefusal ErgqYt6 "--publish with HEAD unpushed" unpushed "HEAD is not what origin/main has" 1 0

## On the remote only, so the remote is what is asked.
fPublishRepo tagged 1.0.0-beta.1
git -C "${work}/tagged/repo" tag v1.0.0-beta.1
git -C "${work}/tagged/repo" push -q origin v1.0.0-beta.1 2>/dev/null
git -C "${work}/tagged/repo" tag -d v1.0.0-beta.1 >/dev/null
fId ErgqYt7 "tag already on the remote"
out="$(fPublishIn tagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/tagged/gh-create" ]] && [[ -z "$(git -C "${work}/tagged/repo" tag -l)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo gotagged 1.0.0-beta.1
git -C "${work}/gotagged/repo" tag go/v1.0.0-beta.1
fId ErgqYt8 "go/ tag already here"
out="$(fPublishIn gotagged 1 0 < /dev/null)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"Tag go/v1.0.0-beta.1 already exists"* ]] && [[ ! -e "${work}/gotagged/gh-create" ]] && [[ -z "$(git -C "${work}/gotagged/repo" ls-remote --tags origin)" ]]
	then fPass
	else fFail "exited ${rc} and said '${out: -160}'"
fi

fPublishRepo partial 1.0.0-beta.1
rm -f "${work}/partial/repo/dist-incoming/"zuid-1.0.0-beta.1-windows-*.zip
fWantPublishRefusal ErgqYt9 "missing platform, no --allow-partial" partial "No asset for: zuid-1.0.0-beta.1-windows-x86_64.zip zuid-1.0.0-beta.1-windows-arm64.zip" 1 0

fId ErgqYtA "--allow-partial publishes the rest"
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
fWantPublishRefusal ErgqYtH "stale tarball refused" stale "built from another version" 1 0

## A remote gh cannot match to a GitHub repo, so the notes would have no
## links. The tags must not go out first.
fPublishRepo norepo 1.0.0-beta.1
export GH_STUB_NO_REPO=1
fWantPublishRefusal ErmAuec "gh can't name the repo" norepo "gh cannot tell which GitHub repo this is" 1 0
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

fId ErgqYtC "'-' in the version means prerelease"
if ((betaRc == 0)) && [[ " ${betaArgs[*]} " == *" --prerelease "* ]] && [[ "${betaArgs[0]:-}" == "v1.0.0-beta.1" ]]
	then fPass
	else fFail "exited ${betaRc}, gh got '${betaArgs[*]:0:6}', said '${betaOut: -160}'"
fi

fId ErgqYtE "both tags pushed on HEAD"
betaHead="$(git -C "${work}/beta/repo" rev-parse HEAD)"
if [[ "$(fRemoteTags "${work}/beta/repo")" == "go/v1.0.0-beta.1 ${betaHead}"$'\n'"v1.0.0-beta.1 ${betaHead}" ]]
	then fPass
	else fFail "the remote has: $(fRemoteTags "${work}/beta/repo" | tr '\n' ';')"
fi

## GitHub lists a bare tag beside the releases, so its message says what it is.
fId EsjRmx6 "go/ tag message"
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

fId ErgqYtG "'~' becomes '.' in asset names"
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

fId EsZni4k "dist/debug/ stays local"
debugBad=""
for arg in "${betaUploads[@]}"; do
	case "${arg}" in */debug/*|*.debug|*.pdb) debugBad+=" uploaded $(basename "${arg}");" ;; esac
done
if [[ -z "${sumsFile}" ]] || grep -qE '(debug/|\.debug$|\.pdb$)' "${sumsFile}"; then debugBad+=" checksums.txt is missing or lists debug info;"; fi
if [[ -z "${debugBad}" ]]
	then fPass
	else fFail "${debugBad}"
fi

fId ErgqjsR "release notes from the changelog"
betaNotes=""
for ((argIndex = 0; argIndex < ${#betaArgs[@]}; argIndex++)); do
	if [[ "${betaArgs[argIndex]}" == "--notes" ]]; then betaNotes="${betaArgs[argIndex + 1]:-}"; fi
done
if [[ "${betaNotes}" == *"Notes for this one."* ]] && [[ "${betaNotes}" != *"older one"* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fId EshGwj3 "build number tops the notes"
if [[ "${betaNotes}" == "zuid v1.0.0-beta.1 build abc12"$'\n'* ]]
	then fPass
	else fFail "notes were '${betaNotes:0:120}'"
fi

fPublishRepo stable 1.0.0
fId ErgqYtD "plain version is a full release"
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

fId Erm9fTp "download table, OS by CPU"
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

fId Erm9fTq "macOS universal spans both columns"
macWant="<tr><th>macOS</th><td colspan=\"2\" align=\"center\">$(fLinks zuid-1.0.0-beta.1-darwin-universal.tgz zuid-1.0.0-beta.1-darwin-universal)</td></tr>"
if [[ "${tableRows[2]:-}" == "${macWant}" ]]
	then fPass
	else fFail "macOS row was '${tableRows[2]:-}'"
fi

## The partial run above left out both Windows files.
fId Erm9fTr "dash for a missing file"
partialNotes="$(fNotesOf "${work}/partial/gh-create")"
partialRows=()
mapfile -t partialRows < <(grep '^<tr>' <<< "${partialNotes}" || true)
if [[ "${partialRows[3]:-}" == "<tr><th>Windows</th><td>-</td><td>-</td></tr>" ]] && [[ "${partialRows[1]:-}" == "<tr><th>Linux</th><td><a href="* ]] && [[ "${partialNotes}" != *zuid-1.0.0-beta.1-windows* ]]
	then fPass
	else fFail "rows were '${partialRows[*]:-}'"
fi

fPublishRepo nomac 1.0.0-beta.1
rm -f "${work}/nomac/repo/dist-incoming/"zuid-1.0.0-beta.1-darwin-universal*
fId ErmpEWr "one dash for missing macOS"
out="$(fPublishIn nomac 1 1 < /dev/null)" && rc=0 || rc=$?
nomacRows=()
mapfile -t nomacRows < <(grep '^<tr>' <<< "$(fNotesOf "${work}/nomac/gh-create")" || true)
if ((rc == 0)) && [[ "${nomacRows[2]:-}" == "<tr><th>macOS</th><td colspan=\"2\" align=\"center\">-</td></tr>" ]]
	then fPass
	else fFail "exited ${rc}, rows were '${nomacRows[*]:-}'"
fi

fId Erm9fTs "release notes order"
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
fId ErmeArM "test-ids.py --at takes a Z time"
out="$(fIdsNew -n 4 --at 2026-09-01T12:00:00Z)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == "$(printf '%s\n' "${fixtureIds[@]}")" ]] && ((${#fixtureIds[@]} == 4))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErmeArN "bad --at time, one-line error"
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

fId ErkRrmk "test-ids.py check on a clean tree"
fIdsTree "fId ${fixtureIds[2]} \"a check\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"3 tests, all unique"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

## The two arm64 link checks kept their IDs in an array, so the check never saw
## them and would have let a duplicate through.
fId ErkRrml "orphan ID caught"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"links=(\"${fixtureIds[3]}:static\")"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' looks like a test ID"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmm "stray test-id mark caught"
fIdsTree "fId ${fixtureIds[2]} \"a check\"" "// test-id: ${fixtureIds[3]}"$'\n'"fn helper() void {}"
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc != 0)) && [[ "${out}" == *"'${fixtureIds[3]}' is not directly above a test"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmn "retired test can stay commented"
fIdsTree "fId ${fixtureIds[2]} \"a check\""$'\n'"# fWantRefusal ${fixtureIds[3]} \"retired\""
out="$(fIdsCheck)" && rc=0 || rc=$?
if ((rc == 0))
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId ErkRrmo "test-ids.py fuzzers lists fuzz tests only"
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

fId ErmER3z "cicd.bash drops a bad SOURCE_DATE_EPOCH"
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

fId ErmER40 "package.bash drops it too"
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

fId ErkRrmp "clean fuzz run, one ok line each"
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
fId ErkRrmq "a fuzz find fails its own test"
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

fId ErkRrmr "broken fuzz run fails them all"
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

## Fuzzing is a hard step, so it gets a quarter of the box, not the build's half.
fId Etj0Hc1 "fuzzing takes the hard-step job count"
: > "${work}/fuzz-args"
out="$(FAKE_ZIG_ARGS="${work}/fuzz-args" fFuzzIn clean)" && rc=0 || rc=$?
if ((rc == 0)) && grep -qxF -- "build -j2 test --fuzz=50K" "${work}/fuzz-args"
	then fPass
	else fFail "exited ${rc}, zig was asked: '$(tr '\n' ' ' < "${work}/fuzz-args")'"
fi

## A quick run fuzzes on a short budget, both sides.
fId EtjfGH1 "quick fuzz budget"
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
		# shellcheck disable=2031  ## Only the subshell's PATH.
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
fId EscPGS5 "fuzz stage cleans TMPDIR"
fuzzLeft="$(find "${fuzzTmp}" -mindepth 1 -maxdepth 1 2>&1 | tr '\n' ' ' || true)"
if [[ -z "${fuzzLeft}" ]]
	then fPass
	else fFail "left ${fuzzLeft}"
fi

## Cleanup used to remove only what sat under /tmp, so with TMPDIR elsewhere
## every scratch folder stayed. It still takes nothing mktemp -d did not make.
fId EscPGS6 "scratch cleanup takes only tmp.*"
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
fId ErsspWK "NewRegistry counts as registry time"
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

fId Et9luGK "called stdlib advisory fails"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0001 stdlib net LookupCNAME; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"GO-0000-0001 in go1.0.1, called from net.LookupCNAME"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Et9luGL "uncalled stdlib advisory is counted"
out="$( { printf '%s\n' "${vulnConfig}"; fVulnFinding GO-0000-0002 stdlib net ""; } | fVulnReport)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"1 advisories for go1.0.1 in code we don't call"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out}'"
fi

fId Et9luGM "any third-party advisory fails"
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

fId EtAj5P3 "CodeQL: any finding in our code fails"
out="$(fCodeqlReport "${work}/no-suppressions" zuid/a.go:x/style)" && rc=0 || rc=$?
if ((rc == 1)) && [[ "${out}" == *"x/style at zuid/a.go:3: made up"* ]]
	then fPass
	else fFail "exited ${rc} and said '${out//$'\n'/ | }'"
fi

fId EtAj5P4 "CodeQL: third-party bugs only"
out="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/style)" && rc=0 || rc=$?
out2="$(fCodeqlReport "${work}/no-suppressions" vendor/m/a.go:x/bug)" && rc2=0 || rc2=$?
if ((rc == 0 && rc2 == 1)) && [[ "${out}" == *"1 style findings in third-party code"* && "${out2}" == *"x/bug at vendor/m/a.go:3"* ]]
	then fPass
	else fFail "exited ${rc} and ${rc2}, and said '${out//$'\n'/ | }' and '${out2//$'\n'/ | }'"
fi

fId EtAj5P5 "CodeQL suppressions"
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

fId EtAj5P6 "CodeQL coverage check"
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

## cli-test.bash ran a relative --bin after a cd, so Ersmdcu ran nothing and
## failed (2026102321183047). The stand-in only keeps a module the way the
## command does, so every other case there fails, and only this one is read.
fId Etab8wr "cli-test.bash takes a relative --bin"
if [[ "$(uname -s)" == Darwin ]]; then
	printf '  skip ..: %s %s (%s)\n' "${curId}" "${curName}" "cli-test.bash has no Ersmdcu on a Mac"; curId=""
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
	if grep -qxF "  ok ....: Ersmdcu a relative XDG_CACHE_HOME falls back to ~/.cache" <<< "${out}"
		then fPass
		else fFail "$(grep -m1 -e 'Ersmdcu' -e 'cli-test:' <<< "${out}" || echo 'no Ersmdcu line')"
	fi
fi


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The pre-push hook, in a scratch repo with a bare remote. The committed
## cicd.bash is a stand-in that writes down what it was asked for.

fId Etj4p9i "the hook gates main with --merge-gate"
hookRepo="${work}/hook/repo"
gateLog="${work}/hook/gate.log"
git init -q --bare "${work}/hook/remote.git"
git init -q -b main "${hookRepo}"
git -C "${hookRepo}" config user.name t
git -C "${hookRepo}" config user.email t@t
mkdir -p "${hookRepo}/cicd/utility/git-hooks" "${hookRepo}/go" "${hookRepo}/project"
cp "${cicd%/cicd.bash}/utility/git-hooks/pre-push" "${cicd%/cicd.bash}/utility/git-hooks/no-gate-paths" "${hookRepo}/cicd/utility/git-hooks/"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "${gateLog}" > "${hookRepo}/cicd/cicd.bash"
chmod +x "${hookRepo}/cicd/cicd.bash"
printf 'x\n' > "${hookRepo}/README.md"; printf 'package x\n' > "${hookRepo}/go/x.go"
git -C "${hookRepo}" add -A
git -C "${hookRepo}" commit -q -m first
git -C "${hookRepo}" config core.hooksPath cicd/utility/git-hooks
git -C "${hookRepo}" remote add origin "${work}/hook/remote.git"
fHookPush(){  ## ref
	: > "${gateLog}"
	env -u SKIP_GATE TMPDIR="${work}/hook" git -C "${hookRepo}" push -q origin "$1" > /dev/null 2>&1 || printf 'push failed\n' >> "${gateLog}"
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

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
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
