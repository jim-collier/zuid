#!/bin/bash

# shellcheck disable=2119  ## Disable confusing and inapplicable warning about function's $1 meaning script's $1.
# shellcheck disable=2120  ## OK with declaring functions that accept arguments, without calling with arguments.
# shellcheck disable=2155  ## Disable check to 'Declare and assign separately to avoid masking return values'.

##	Purpose: See fPrint_AboutAndSyntax() and fPrint_Help().
##	History:
##		- 20260802 JC: Created.
##		- 20260804 JC: Remote sync, artifacts, profiling, demo, packaging, dogfood.
##		- 20260805 JC: Backup and publish stage.
##		- 20260930 JC: Test IDs, one line per test. Pipeline self-test.
##		- 20261003 JC: Zig 0.17.0, found beside an older one on PATH.

declare -i doQuietly=0; [[ "${ZUID_CICD_QUIET:-}" == "1" ]] && doQuietly=1
declare    thisVersion="0.1.0"
declare    copyrightYear="2026"
declare    author="Jim Collier"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fConfig(){ :;

	## Toolchain floors. Only the machine that produces the wasm artifact needs Go
	## 1.24+, but one floor is easier to reason about than two.
	default_minVer_Go="1.24"
	default_minVer_Zig="0.17.0"

	## Cross targets for --cross, as GOOS/GOARCH. Go builds these with cgo off, as
	## compile checks. The Zig side does not use this list. Its macOS arm64 build is
	## half of the universal release, which package.bash makes on a Mac.
	default_crossTargets=("linux/arm64" "windows/amd64" "darwin/arm64")

	## Merge targets, never places to commit.
	default_protectedBranches=("main" "dev")

	## Vendored Wasmtime C API, pinned. Fetched into zig/vendor/ when absent.
	## One checksum per platform, as <arch>-<os>=<sha256>, in Wasmtime's own names.
	## A Mac vendors both macOS ones, since its release is universal.
	default_wasmtimeVer="v47.0.3"
	default_wasmtimeSha256s=(
		"x86_64-linux=aaa3621f2a3d8393696702897f8f78a1cc504437d500701496d560125aefd732"
		"x86_64-macos=627622087b77b92c163e826ec6ebf834a70d78735828043edf7ace263f8a9e62"
		"aarch64-macos=1854c8f03a764c89afe77fa88d9092ab89a368e527cd27a12959b1d91152324e"
	)

	## The reactor wasm module is built from this package, which go.mod pins to
	## a release, so the Go side and the Zig side cannot end up on two versions
	## of the conversion library.
	default_reactorPackage="github.com/jim-collier/convert-base-v2/lib/reactor"

	## Where dogfooding puts the binary. First existing directory wins.
	default_dogfoodDirs=("${HOME}/synced/0-0/common/exec/util/linux/bash" "${HOME}/.local/bin" "${HOME}/bin")

	## Extra rar excludes for the backup, on top of the helper's generic list, which
	## covers .zig-cache itself as of 20260917. Empty because nothing here needs a
	## project-specific one; the hook stays for when something does. Single-quote any
	## pattern inside the double quotes, so the helper's eval hands rar the glob
	## rather than a match.
	default_rarExcludes=""

	## Artifact retention, grandfather-father-son. Keep this many of each.
	default_keepDaily=7
	default_keepWeekly=5
	default_keepMonthly=6

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_Copyright(){
	((doQuietly)) && return 0
	fEcho_Clean ""
	cat <<- EOF_c8xr2
		${meName} version ${thisVersion}
		Copyright (c) ${copyrightYear} ${author}.
		License GPLv2+: GNU GPL version 2 or later, full text at:
		    https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
		There is no warranty, to the extent permitted by law.
	EOF_c8xr2
	fEcho_Force ""
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_AboutAndSyntax(){
	((doQuietly)) && return 0
	fEcho_Clean ""
	#  X-------------------------------------------------------------------------------X
	cat <<- EOF_p3vk9
		Builds and tests both zuid implementations, then archives the project and
		publishes it. Nothing is packaged unless asked for.

		Syntax: ${meName} [options]
	EOF_p3vk9
	fEcho_Clean_Force ""
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_Help(){
	#  X-------------------------------------------------------------------------------X
	cat <<- EOF_h7wq4
		Options:
		    --only <go|zig>   Drive one toolchain instead of both. Only that one has
		                      to be installed.
		    --cross           Also cross-compile for: ${crossTargets[*]}
		    --quick           Skip the slow stages: profiling and the demo, plus the
		                      dogfood install. The backup and everything that gates
		                      a merge still run.
		    --no-sync         Skip the remote refresh at the start.
		    -m, --message     Commit message. Implies --commit.
		    --commit          Commit if everything passed. Refuses on a protected
		                      branch: ${protectedBranches[*]}
		    --push            Push the current branch. Implies a remote exists.
		    --package         Build release artifacts into dist/.
		    --backup          Archive and publish. On by default, so this only undoes
		                      an earlier --no-backup.
		    --no-backup       Do not archive or publish, however the run went.
		    --dogfood         Install for daily use even on a quick run. A full run
		                      installs anyway.
		    --no-dogfood      Do not install, however the run went.
		    --publish         Publish a release. Not implemented yet.
		    -q, --quiet       No banner and no prompting. Without -m the commit
		                      message is generated.
		    -h, --help        This.
		    -v, --version     Version and copyright.

		Both toolchains have to reproduce testdata/vectors.tsv, which is what the test
		stage checks. The Zig stage vendors the Wasmtime C API into zig/vendor/ when
		absent, and builds the reactor wasm module there from the pinned convertbase
		release.

		Zig is ZIG if set, else the zig on PATH if it is ${default_minVer_Zig} or newer,
		else ~/.local/zig-<platform>-${default_minVer_Zig}/zig.

		Every run is logged to cicd/artifacts/, along with any profile and demo it
		produced. Those are rotated, not kept forever, and none of it is committed.

		A full run that builds the Zig side also copies the command into the first
		of these that exists, so daily use is always the build that just passed:
		${dogfoodDirs[*]}
		It says so and moves on when none of them do.

		Every run - quick or full, any branch - then archives the whole project:
		github/, private/, the lot, into ../versions/, and publishes it, committing
		and pushing through the helper in cicd/utility/. Build caches and other
		regenerable trees are left out, so the archive is a fraction of what is on
		disk. --no-backup turns it off; so does --commit or --push, which take over
		the git half.

		Exit code is 0 only if every stage that ran passed.
	EOF_h7wq4
	fEcho_Clean ""
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fMain(){

	## Pre-validation
	_fMustBeInPath awk
	_fMustBeInPath basename
	_fMustBeInPath dirname
	_fMustBeInPath git
	_fMustBeInPath head
	_fMustBeInPath mktemp
	_fMustBeInPath sed
	_fMustBeInPath sort

	## Make template constants immutible
	local -r meName="${meName}"

	## Config; 1] Define placeholder variables; 2] Call fConfig() to set them; 3] Freeze them as read-only.
	local    default_minVer_Go=""
	local    default_minVer_Zig=""
	local -a default_crossTargets=()
	local -a default_protectedBranches=()
	local    default_wasmtimeVer=""
	local -a default_wasmtimeSha256s=()
	local    default_reactorPackage=""
	local -a default_dogfoodDirs=()
	local    default_rarExcludes=""
	local -i default_keepDaily=0
	local -i default_keepWeekly=0
	local -i default_keepMonthly=0
	fConfig
	local -r minVer_Go="${default_minVer_Go}"
	local -r minVer_Zig="${default_minVer_Zig}"
	local -ra crossTargets=("${default_crossTargets[@]}")
	local -ra protectedBranches=("${default_protectedBranches[@]}")
	local -r wasmtimeVer="${default_wasmtimeVer}"
	local -ra wasmtimeSha256s=("${default_wasmtimeSha256s[@]}")
	local -r reactorPackage="${default_reactorPackage}"
	local -ra dogfoodDirs=("${default_dogfoodDirs[@]}")
	local -r  rarExcludes="${default_rarExcludes}"
	local -ri keepDaily="${default_keepDaily}"
	local -ri keepWeekly="${default_keepWeekly}"
	local -ri keepMonthly="${default_keepMonthly}"

	## Layout. This script lives in the repo's cicd/, so the repo root is one up.
	local -r repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	[[ -n "${repoRoot}" ]] || fThrowError "Could not resolve the repo root."  "${FUNCNAME[0]}"
	local -r goDir="${repoRoot}/go"
	local -r zigDir="${repoRoot}/zig"
	local -r artifactDir="${repoRoot}/cicd/artifacts"
	local -r utilityDir="${repoRoot}/cicd/utility"
	local -r runStamp="$(date +%Y%m%d-%H%M%S)"

	## No single stage gets the whole machine. Half the cores, at least one.
	local -ri buildJobs="$(fHalfTheCores)"

	## Args; 1] Define placeholder variables; 2] Call fInit() to set them; 3] Freeze them read-only.
	local    onlyToolchain=""
	local    commitMsg=""
	local -i doCross=0
	local -i doQuick=0
	local -i doSync=1
	local -i doCommit=0
	local -i commitAsked=0
	local -i doPush=0
	local -i doPackage=0
	local -i doBackup=1
	local -i backupAsked=0
	local -i doDogfood=1
	local -i dogfoodAsked=0
	fInit "${@}"
	readonly onlyToolchain
	readonly doCross
	readonly doQuick
	readonly doSync
	readonly doPush
	readonly doPackage

	## Dogfooding rides along with every full run - the whole point is that daily
	## use is the build that just passed. A quick run is mid-iteration, so it stays
	## off the path unless asked for by name.
	if ((doQuick)) && ((! dogfoodAsked)); then doDogfood=0; fi
	readonly doDogfood

	## Backing up survives a quick run - the archive is cheap next to the stages
	## quick actually exists to skip, and an archive nobody remembered to ask for
	## is not an archive. Any branch, too: the helper commits and pushes the same
	## way it would run by hand from the repo, main included.
	readonly doBackup

	local -i doGo=1;  [[ "${onlyToolchain}" == "zig" ]] && doGo=0
	local -i doZig=1; [[ "${onlyToolchain}" == "go"  ]] && doZig=0

	## Ask for the commit message before anything slow runs, so the build is not
	## finished and then thrown away because nobody was there to answer.
	fAskForCommitMessage
	readonly commitMsg
	readonly doCommit

	##
	## Make it so
	##

	fStartRunLog

	## Plain 'if', not '&&' - a trailing false in a function trips the ERR trap.
	if ((doSync));                 then fStage_Sync;      fi
	fPreflight
	fStage_Shell
	if ((doGo));                   then fStage_Go;        fi
	if ((doZig));                  then fStage_Zig;       fi
	if ((doCross)) && ((doGo));    then fStage_Go_Cross;  fi
	if ((! doQuick));              then fStage_Profile;   fi
	if ((! doQuick));              then fStage_Demo;      fi
	if ((doPackage));              then fStage_Package;   fi
	if ((doZig)) && ((doDogfood)); then fStage_Dogfood;   fi
	if ((doBackup));               then fStage_Backup;    fi
	if ((doCommit));               then fStage_Commit;    fi
	if ((doPush));                 then fStage_Push;      fi

	fEcho_Clean
	fEcho "Passed."
	fEcho_Clean

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fInit(){

	## Help and version are checked switch by switch, not by searching the joined
	## argument string - a commit message mentioning '-h' is not a request for help.
	local currentArg=""
	while (($#)); do
		currentArg="${1,,}"
		case "${currentArg}" in

			-h|--help)                fPrint_Copyright_About_Syntax 1; exit 0 ;;
			-v|--ver|--version)       fPrint_Copyright               ; exit 0 ;;

			## Switches taking a parameter
			--only)
				shift || true
				onlyToolchain="${1,,}"
				if [[ "${onlyToolchain}" != "go" ]] && [[ "${onlyToolchain}" != "zig" ]]; then
					fThrowError "Expecting 'go' or 'zig' after --only, instead got '${1:-nothing}'."  "${FUNCNAME[0]}"
				fi
				;;
			-m|--msg|--message)
				shift || true
				fMustBeAValue "${1:-}" "${currentArg}"
				commitMsg="$1"
				doCommit=1
				;;
			-m=*|--msg=*|--message=*)
				commitMsg="${1#*=}"
				fMustBeAValue "${commitMsg}" "${currentArg%%=*}"
				doCommit=1
				;;

			## Unitary switches
			--cross)      doCross=1   ;;
			--quick)      doQuick=1   ;;
			--no-sync)    doSync=0    ;;
			--commit)     doCommit=1; commitAsked=1 ;;
			--push)       doPush=1    ;;
			--package)    doPackage=1 ;;
			--backup)     doBackup=1; backupAsked=1 ;;
			--no-backup)  doBackup=0; backupAsked=0 ;;
			--dogfood)    doDogfood=1; dogfoodAsked=1 ;;
			--no-dogfood) doDogfood=0; dogfoodAsked=0 ;;
			-q|--quiet)   doQuietly=1 ;;

			## Opt-in stages that do not exist yet. Say so rather than pretending.
			--publish)
				fThrowError "Not implemented yet: '${currentArg}'. Publishing waits on the repo existing and on packaging covering more than this platform."  "${FUNCNAME[0]}"
				;;

			## ¯\_(:/)_/¯
			*)  fThrowError "Argument invalid or not expected in this context: '$1'."  "${FUNCNAME[0]}" ;;

		esac
		shift || true
	done

	## The backup helper does its own commit and push, so pairing it with either of
	## ours would land the same work twice. Asked for together that is a mistake and
	## says so; with the backup merely riding along by default, the narrower git path
	## is plainly what was meant, so it wins quietly.
	if ((commitAsked)) || ((doPush)); then
		if ((backupAsked)); then
			fThrowError "--backup already commits and pushes; drop --commit and --push."  "${FUNCNAME[0]}"
		fi
		doBackup=0
	fi

	## A bare -m is not that clash - the message is what the helper commits with.
	if ((doBackup)); then doCommit=0; fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A value that looks like the next switch is almost always a missing argument,
## not somebody's commit message. Saying so beats committing '--push'.
fMustBeAValue(){
	local -r value="${1:-}"
	local -r flag="${2:-}"
	if [[ -z "${value}" ]] || [[ "${value}" == -* ]]; then
		fThrowError "Expecting a value after ${flag}, instead got '${value:-nothing}'."  "${FUNCNAME[1]}"
	fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## True when HEAD sits on a branch this script must not land work on. A detached
## HEAD is not protected - that is its own error, raised where it matters.
fIsProtectedBranch(){

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
	local protected=""
	for protected in "${protectedBranches[@]}"; do
		if [[ "${branch}" == "${protected}" ]]; then return 0; fi
	done
	return 1

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Asked up front, and only when a commit was asked for without a message. The
## backup helper commits too, so it needs one just the same.
## Quiet mode generates one instead of waiting for somebody who is not there.
fAskForCommitMessage(){

	if ((! doCommit)) && ((! doBackup)); then return 0; fi
	[[ -z "${commitMsg}" ]] || return 0

	if ((doQuietly)); then
		commitMsg="Updated"
		return 0
	fi

	fEcho_Clean
	fEcho "Commit message"
	fEcho_Clean "CTRL+C to abort."
	fEcho_Clean
	read -r -p "  Message: " commitMsg || fThrowError "No commit message given."  "${FUNCNAME[0]}"
	[[ -n "${commitMsg}" ]] || fThrowError "No commit message given."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Refresh from the remote before building rather than at publish time. Pulling
## only at the end means a change merged upstream gets pushed having never been
## built here.
fStage_Sync(){

	fEcho_Clean
	fEcho "Remote sync"

	[[ -d "${repoRoot}/.git" ]] || fThrowError "Not a git repo: '${repoRoot}'."  "${FUNCNAME[0]}"

	if [[ -z "$(git -C "${repoRoot}" remote)" ]]; then
		fEcho_Clean "Remote .....: none - nothing to sync"
		return 0
	fi

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fEcho_Clean "Branch .....: detached - skipping sync"
		return 0
	fi

	if ! git -C "${repoRoot}" fetch --quiet --prune 2>/dev/null; then
		fEcho_Clean "Fetch ......: failed (offline?) - continuing with what is here"
		return 0
	fi

	local -r upstream="$(git -C "${repoRoot}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
	if [[ -z "${upstream}" ]]; then
		fEcho_Clean "Upstream ...: none for '${branch}' - continuing"
		return 0
	fi

	local -r behind="$(git -C "${repoRoot}" rev-list --count "HEAD..${upstream}")"
	local -r ahead="$(git -C "${repoRoot}" rev-list --count "${upstream}..HEAD")"
	if ((behind == 0)); then
		fEcho_Clean "Branch .....: ${branch} up to date with ${upstream}"
		return 0
	fi
	if ((ahead > 0)); then
		fThrowError "'${branch}' has diverged from ${upstream} (${ahead} ahead, ${behind} behind). Reconcile it before building."  "${FUNCNAME[0]}"
	fi

	## Behind only, so a fast-forward is safe. Local work is stashed around it
	## rather than refused, since a dirty tree is the normal state mid-change.
	local -i stashed=0
	if [[ -n "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		git -C "${repoRoot}" stash push --quiet --include-untracked --message "cicd sync ${runStamp}"
		stashed=1
	fi
	git -C "${repoRoot}" merge --ff-only --quiet "${upstream}"
	if ((stashed)); then
		git -C "${repoRoot}" stash pop --quiet || fThrowError "Fast-forwarded, but the stashed changes conflict. Resolve them by hand."  "${FUNCNAME[0]}"
	fi
	fEcho_Clean "Branch .....: ${branch} fast-forwarded ${behind} commit(s)"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPreflight(){

	fEcho_Clean
	fEcho "Preflight"

	[[ -d "${repoRoot}/.git" ]] || fThrowError "Not a git repo: '${repoRoot}'."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	fEcho_Clean "Branch .....: ${branch}"
	if [[ -n "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		fEcho_Clean "Tree .......: uncommitted changes present"
	fi
	fEcho_Clean "Jobs .......: ${buildJobs}"

	if ((doGo)); then
		_fMustBeInPath go
		local -r haveVer_Go="$(go version | awk '{print $3}' | sed 's/^go//')"
		fVersion_AtLeast "${haveVer_Go}" "${minVer_Go}" || fThrowError "Go ${minVer_Go} or newer required, found '${haveVer_Go}'."  "${FUNCNAME[0]}"
		fEcho_Clean "Go .........: ${haveVer_Go}"
	fi

	if ((doZig)); then
		fFindZig "${minVer_Zig}"
		fEcho_Clean "Zig ........: $(zig version) ($(readlink -f "$(command -v zig)"))"
	fi

	[[ -f "${repoRoot}/testdata/vectors.tsv" ]] || fThrowError "Missing the shared test vectors: 'testdata/vectors.tsv'."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every test prints one line with its ID, the way the harnesses do. A check
## here starts with fId and ends in one of the three below. A check run once
## per item carries an ID for each, picked by a key:
## fId "${target}" linux/arm64=<id> darwin/arm64=<id> "what it checks".
## New IDs come from cicd/utility/test-ids.py, and its check refuses a test
## without one.
declare testId="" testName=""
fId(){  ## [key key=id...] | id, name
	testId="???????"
	testName="${*: -1}"
	if (($# == 2)); then testId="$1"; return 0; fi
	local -r key="$1"
	local pair=""
	for pair in "${@:2:$#-2}"; do
		if [[ "${pair%%=*}" == "${key}" ]]; then testId="${pair#*=}"; fi
	done
	return 0
}
fTestPass(){ fEcho_Clean "  ok ....: ${testId} ${testName}" ;}
fTestSkip(){ fEcho_Clean "  skip ..: ${testId} ${testName} ($*)" ;}
fTestFail(){ fEcho_Clean "  FAIL ..: ${testId} ${testName}"; fThrowError "$*"  "${FUNCNAME[1]}" ;}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Shell(){

	fEcho_Clean
	fEcho "Bash: lint"

	## Not a toolchain, so a missing shellcheck is a gap in coverage, not a failure.
	## It used to return here and take the stages below down with it.
	if [[ -z "$(command -v shellcheck 2>/dev/null || true)" ]]; then
		fEcho_Clean "shellcheck not installed - skipping."
	else
		## Only what this project wrote. x9muid1 under utility/ is 2023 reference
		## code, and the copied helpers keep their own upstream's lint state.
		shellcheck "${repoRoot}/cicd/cicd.bash" "${repoRoot}/install.bash" \
			"${utilityDir}/installer-test.bash" "${utilityDir}/cli-test.bash" \
			"${utilityDir}/pipeline-test.bash"
		fEcho_Clean "Clean."
	fi

	fStage_TestIds
	fStage_Shell_Pipeline
	fStage_Shell_Installers
	fStage_Docs

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every test has an ID, and no two share one. A test added without one fails
## here rather than printing a line nobody can refer to.
fStage_TestIds(){

	fEcho_Clean
	fEcho "Test IDs"

	if [[ -z "$(command -v python3 2>/dev/null || true)" ]]; then
		fEcho_Clean "Skipped ....: python3 not installed."
		return 0
	fi
	python3 "${utilityDir}/test-ids.py" check || fThrowError "Some tests have no ID, or share one. 'cicd/utility/test-ids.py new' makes one."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A number written in front of a list drifts the moment the list grows, and no
## linter counts. design.md said "four things" above five bullets.
fStage_Docs(){

	fEcho_Clean
	fEcho "Docs: claims that can be counted"

	## Both style guides were written and then pointed at from two places. A
	## guide nothing links to is one nobody reads, which is how the CLI one came
	## to be missing in the first place.
	fId EqA4qmO "both style guides are linked from README.md and contributing.md"
	local guide="" from=""
	for from in README.md contributing.md; do
		for guide in style_guide.md style-guide_cli.md; do
			grep -q "(${guide})" "${repoRoot}/${from}" \
				|| fTestFail "${from} does not link ${guide}."
		done
	done
	fTestPass

	## And every relative link in the root documents goes somewhere.
	fId EqA4qmP "every relative link in the root documents resolves"
	local doc="" target="" missing=0
	for doc in "${repoRoot}"/*.md; do
		while read -r target; do
			[[ -n "${target}" ]] || continue
			[[ -e "${repoRoot}/${target%%#*}" ]] && continue
			fEcho_Clean "Broken .....: $(basename "${doc}") -> ${target}"
			missing=$((missing + 1))
		done < <(grep -oE '\]\([^):]+\)' "${doc}" | sed -e 's/^](//' -e 's/)$//' || true)
	done
	((missing == 0)) || fTestFail "${missing} relative link(s) in the root documents point at nothing."
	fTestPass

	## A GPL file at the root read as covering everything, modules included. The
	## root has only the map now, and each licensed directory has its own text.
	fId ErOj0WT "each directory carries the license license.md says it does"
	local licenseFile="" licenseWant="" licenseBad=""
	[[ -f "${repoRoot}/license.md" ]] || licenseBad+=" license.md is missing;"
	if compgen -G "${repoRoot}/LICENSE*" >/dev/null; then licenseBad+=" a LICENSE file is back at the root;"; fi
	for licenseFile in zig/cmd/LICENSE.txt:"GNU GENERAL PUBLIC LICENSE" go/LICENSE.txt:"Apache License" \
		zig/lib/LICENSE.txt:"Apache License" go/NOTICE.txt:"" zig/lib/NOTICE.txt:""; do
		licenseWant="${licenseFile#*:}"
		licenseFile="${licenseFile%%:*}"
		if [[ ! -f "${repoRoot}/${licenseFile}" ]]; then
			licenseBad+=" ${licenseFile} is missing;"
		elif [[ -n "${licenseWant}" ]] && ! grep -q "${licenseWant}" "${repoRoot}/${licenseFile}"; then
			licenseBad+=" ${licenseFile} is not '${licenseWant}';"
		fi
	done
	licenseBad="${licenseBad# }"; [[ -z "${licenseBad}" ]] || fTestFail "${licenseBad%;}."
	fTestPass

	## The contact address was a placeholder on a domain that was never ours,
	## and code_of_conduct.md still named the project it was copied from. In
	## text people read it is written with the circled A, not a plain @.
	fId ErOj0WU "the contact address is the project's own everywhere"
	local contactDoc="" contactBad=""
	for contactDoc in trademark.md contributing.md code_of_conduct.md; do
		[[ -f "${repoRoot}/${contactDoc}" ]] || continue
		if ! grep -qE 'zuidⒶyottacore\.com' "${repoRoot}/${contactDoc}"; then
			contactBad+=" ${contactDoc} has no contact address;"
		fi
		if grep -oE '[A-Za-z0-9._-]+(@|Ⓐ)[A-Za-z0-9.-]+\.[a-z]+' "${repoRoot}/${contactDoc}" | grep -vqE '^zuidⒶyottacore\.com$'; then
			contactBad+=" ${contactDoc} has another address;"
		fi
	done
	if grep -l 'Still to fill' "${repoRoot}"/*.md >/dev/null 2>&1; then contactBad+=" a 'Still to fill' note is left in a root document;"; fi
	contactBad="${contactBad# }"; [[ -z "${contactBad}" ]] || fTestFail "${contactBad%;}."
	fTestPass

	fId Eq9ofeq "design.md's rejection count matches its list"
	local -r design="${repoRoot}/project/design.md"
	if [[ ! -f "${design}" ]]; then
		fTestSkip "project/design.md is not present"
		return 0
	fi

	## The sentence, then the bullets directly under it up to the blank line that
	## ends the list.
	local -r claimLine="$(grep -n 'reject the same .* things before rendering' "${design}" | head -n1 || true)"
	if [[ -z "${claimLine}" ]]; then
		fTestSkip "the rejection-list sentence has moved or been reworded"
		return 0
	fi

	local -r claimNumber="$(sed -n "${claimLine%%:*}p" "${design}" | sed -E 's/.*reject the same ([a-z]+) things.*/\1/')"
	local -r bulletCount="$(awk -v start="$((${claimLine%%:*} + 1))" 'NR >= start { if ($0 ~ /^- /) n++; else if ($0 !~ /^[[:space:]]*$/ && n > 0) exit } END { print n + 0 }' "${design}")"

	local spelled=""
	case "${bulletCount}" in
		3) spelled="three" ;; 4) spelled="four" ;; 5) spelled="five" ;;
		6) spelled="six" ;;   7) spelled="seven" ;;
		*) spelled="" ;;
	esac
	if [[ -z "${spelled}" ]]; then
		fTestSkip "${bulletCount} bullets, which this check has no word for"
		return 0
	fi
	if [[ "${claimNumber}" != "${spelled}" ]]; then
		fTestFail "design.md says it rejects '${claimNumber}' things and then lists ${bulletCount}."
	fi
	fTestPass

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## This script's own argument handling and commit refusal. Nothing else would
## notice them going wrong until the wrong commit had been made.
fStage_Shell_Pipeline(){

	fEcho_Clean
	fEcho "Pipeline"

	local -r runner="${utilityDir}/pipeline-test.bash"
	if [[ ! -f "${runner}" ]]; then
		fEcho_Clean "Skipped ....: pipeline-test.bash is not present."
		return 0
	fi
	bash "${runner}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The installers only reach their interesting paths against a real listing and
## a real download, so they get a local one. Nothing here touches the network or
## anything outside its own scratch tree.
fStage_Shell_Installers(){

	fEcho_Clean
	fEcho "Installers"

	local -r runner="${utilityDir}/installer-test.bash"
	if [[ ! -f "${runner}" ]]; then
		fEcho_Clean "Skipped ....: installer-test.bash is not present."
		return 0
	fi

	## python3 serves the listing; without it there is nothing to test against.
	if [[ -z "$(command -v python3 2>/dev/null || true)" ]]; then
		fEcho_Clean "Skipped ....: python3 not installed."
		return 0
	fi

	bash "${runner}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Go(){

	fEcho_Clean
	fEcho "Go: build, vet, format, test"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	## convertbase comes from its published release, never a local checkout. The
	## reactor wasm is built from that same pin, which is what keeps the two
	## sides on one library version, and a replace directive would split them.
	fId ErOj0WV "go.mod pins a released convertbase, with no replace"
	if grep -qE '^[[:space:]]*replace' go.mod; then
		fTestFail "go.mod has a replace directive."
	fi
	if ! grep -qE '^[[:space:]]*(require[[:space:]]+)?github\.com/jim-collier/convert-base-v2/lib v[0-9]+\.[0-9]+\.[0-9]+$' go.mod; then
		fTestFail "go.mod does not require convert-base-v2/lib at a tagged version: $(grep convert-base go.mod || true)"
	fi
	fTestPass

	go build -p "${buildJobs}" ./...
	go vet ./...

	## gofmt is silent on success and lists offenders on failure, so it needs the
	## test. Its own exit code is checked too - a missing gofmt would otherwise
	## report an empty list and pass.
	local unformatted=""
	unformatted="$(gofmt -l . 2>&1)" || fThrowError "gofmt failed: ${unformatted}"  "${FUNCNAME[0]}"
	if [[ -n "${unformatted}" ]]; then
		fThrowError "gofmt would rewrite: ${unformatted//$'\n'/, }"  "${FUNCNAME[0]}"
	fi

	## The race detector is the only thing defending the documented promise that
	## Generate is safe to call concurrently. The JSON stream is what gives one
	## line per test, with its ID.
	if [[ -n "$(command -v python3 2>/dev/null || true)" ]]; then
		go test -p "${buildJobs}" -race -json ./... | python3 "${utilityDir}/test-ids.py" go
	else
		fEcho_Clean "IDs ........: skipped, no python3"
		go test -p "${buildJobs}" -race ./...
	fi

	## The module promises it needs no cgo, which is what keeps a static cross
	## build possible. --cross checks the other targets; this is every run.
	fId ErOgfbn "the Go module builds with cgo off"
	CGO_ENABLED=0 go build -p "${buildJobs}" ./... || fTestFail "the Go module needs cgo."
	fTestPass

	fStage_Go_Consumer
	if ((! doQuick)); then fStage_Go_Fuzz; fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A program that imports the module, built the way somebody following README
## would. Its own tests import by relative package path and so prove nothing
## about that.
fStage_Go_Consumer(){

	fEcho_Clean
	fEcho "Go: a consumer of the module"

	## README's command has to name the package, not the module root. On the root
	## go get adds the module without what its package needs, and the build stops
	## on a missing go.sum entry for convertbase.
	fId Eq9m0j2 "README's go get names the package path"
	local -r readme="${repoRoot}/README.md"
	if [[ -f "${readme}" ]] && grep -q 'go get github.com/jim-collier/zuid/go$' "${readme}"; then
		fTestFail "README tells people 'go get <module root>', which leaves the build unable to resolve convertbase. It should name the package."
	fi
	fTestPass

	local consumerDir=""
	consumerDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${consumerDir}")

	cat > "${consumerDir}/main.go" <<-'EOF'
		package main

		import (
			"fmt"

			"github.com/jim-collier/zuid/go/zuid"
		)

		func main() {
			g, err := zuid.New()
			if err != nil {
				panic(err)
			}
			id, err := g.Generate(zuid.Request{Format: "%d"})
			if err != nil {
				panic(err)
			}
			fmt.Println(id)
		}
	EOF

	## Pointed at this tree rather than the published module, so the check says
	## whether what is about to be merged can be imported, and needs no network
	## beyond what the module cache already holds.
	fId Eq9m0j3 "a program importing the module builds and runs"
	(
		cd "${consumerDir}" || exit 1
		go mod init zuid-consumer-check >/dev/null 2>&1 || exit 1
		go mod edit -require="github.com/jim-collier/zuid/go@v0.0.0" \
			-replace="github.com/jim-collier/zuid/go=${goDir}" || exit 1
		go mod tidy >/dev/null 2>&1 || exit 1
		go build -o "${consumerDir}/consumer" . || exit 1
		"${consumerDir}/consumer" >/dev/null || exit 1
	) || fTestFail "a program importing github.com/jim-collier/zuid/go/zuid did not build and run."
	fTestPass

	rm -rf "${consumerDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The format string is the one part of a request that arrives verbatim from
## whoever is calling. Go's fuzzer drives it here; the Zig side has matching
## fuzz tests, which 0.17.0 can run in fuzz mode but this pipeline does not yet,
## so those only replay their corpus during the Zig stage.
fStage_Go_Fuzz(){

	fEcho_Clean
	fEcho "Go: fuzz"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	local -r fuzzTime="20s"
	local -r crasherDir="${goDir}/zuid/testdata/fuzz/FuzzGenerate"
	local output=""
	local -i attempt=0

	## The same test the plain run replayed, so it keeps that test's ID.
	fId "$(python3 "${utilityDir}/test-ids.py" lookup FuzzGenerate 2>/dev/null || printf '???????')" \
		"FuzzGenerate, fuzzed for ${fuzzTime}"

	while ((attempt < 2)); do
		attempt=$((attempt + 1))
		if output="$(go test -run=xxx -fuzz=FuzzGenerate -fuzztime="${fuzzTime}" ./zuid 2>&1)"; then
			fTestPass
			return 0
		fi
		## A real find is saved as a crasher. Without one this is most likely
		## Go reporting its own -fuzztime deadline as a failure (golang/go#75804),
		## which gets one more run before it is believed.
		if [[ -d "${crasherDir}" ]]; then break; fi
		fEcho_Clean "Retrying ...: the fuzz run failed with nothing saved."
	done

	fEcho_Clean "${output}"
	fTestFail "Fuzzing failed. A saved input under ${crasherDir} means a real find."

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Go_Cross(){

	fEcho_Clean
	fEcho "Go: cross-compile"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	## Module only, so there is no binary to emit - this is a compile check per target.
	local target="" goos="" goarch=""
	for target in "${crossTargets[@]}"; do
		goos="${target%%/*}"
		goarch="${target##*/}"
		fId "${target}" linux/arm64=EloMht2 windows/amd64=EloMht3 darwin/arm64=EloMht4 "compiles for ${target} with cgo off"
		CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" go build -p "${buildJobs}" ./... || fTestFail "${target} does not build."
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Zig_Vendor(){

	fEcho_Clean
	fEcho "Zig: vendor"

	local -r vendorDir="${zigDir}/vendor"
	mkdir -p "${vendorDir}"

	## Wasmtime C API, pinned and checksummed per platform. The host's goes in
	## vendor/wasmtime. A Mac also gets the other macOS one beside it, as
	## vendor/wasmtime-<platform>, for the second slice of its universal release.
	## build.zig and package.bash look for it there.
	local hostOs="" hostArch=""
	case "$(uname -s)" in
		Linux)  hostOs="linux" ;;
		Darwin) hostOs="macos" ;;
		*)      hostOs="$(uname -s)" ;;
	esac
	## Apple Silicon says arm64. Wasmtime, like Zig, says aarch64.
	hostArch="$(uname -m)"
	if [[ "${hostArch}" == "arm64" ]]; then hostArch="aarch64"; fi
	local -r hostPlatform="${hostArch}-${hostOs}"
	fVendor_Wasmtime "${hostPlatform}" "${vendorDir}/wasmtime"
	if [[ "${hostOs}" == "macos" ]]; then
		local platform=""
		for platform in x86_64-macos aarch64-macos; do
			if [[ "${platform}" != "${hostPlatform}" ]]; then fVendor_Wasmtime "${platform}" "${vendorDir}/wasmtime-${platform}"; fi
		done
	fi

	## The reactor wasm module, built from the same convertbase release go.mod
	## pins. Building it here rather than copying a prebuilt artifact is what
	## keeps the two implementations on one version of the library: the Go
	## module and the wasm module cannot drift apart when they come from the
	## same verified module. Needs a Go 1.24+ toolchain for //go:wasmexport.
	local -r wasmVendored="${vendorDir}/convert-base-reactor.wasm"
	if command -v go &>/dev/null; then
		local -r wasmTmp="${wasmVendored}.new"
		local buildLog=""
		if buildLog="$(GOOS=wasip1 GOARCH=wasm go build -C "${goDir}" -trimpath -buildmode=c-shared \
			-ldflags '-s -w' -o "${wasmTmp}" "${reactorPackage}" 2>&1)"
		then
			if cmp -s "${wasmTmp}" "${wasmVendored}" 2>/dev/null; then
				rm -f "${wasmTmp}"
				fEcho_Clean "Reactor ....: current"
			else
				mv -f "${wasmTmp}" "${wasmVendored}"
				fEcho_Clean "Reactor ....: rebuilt from the pinned release"
			fi
		else
			## The whole point of building it here is that the two sides cannot
			## reach different library versions, so a failure that falls back to
			## an older vendored copy has to say what went wrong.
			rm -f "${wasmTmp}"
			[[ -f "${wasmVendored}" ]] || fThrowError "Could not build the reactor wasm module, and no vendored copy exists: ${buildLog}"  "${FUNCNAME[0]}"
			fEcho_Clean "Reactor ....: build failed, falling back to the vendored copy"
			fEcho_Clean "${buildLog}"
		fi
	elif [[ -f "${wasmVendored}" ]]; then
		fEcho_Clean "Reactor ....: no Go toolchain, using vendored copy"
	else
		fThrowError "No reactor wasm module: no Go toolchain to build one, and '${wasmVendored}' does not exist."  "${FUNCNAME[0]}"
	fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fVendor_Wasmtime(){  ## platform, destination

	local -r platform="$1" dest="$2"
	local -r parentDir="$(dirname "${dest}")"

	local wasmtimeSha256="" pin=""
	for pin in "${wasmtimeSha256s[@]}"; do
		if [[ "${pin%%=*}" == "${platform}" ]]; then wasmtimeSha256="${pin#*=}"; fi
	done
	if [[ -z "${wasmtimeSha256}" ]]; then
		fThrowError "No vendored Wasmtime pin for ${platform}. Add that archive's checksum to fConfig first."  "${FUNCNAME[0]}"
	fi

	## Version-stamped, so re-pinning in fConfig actually re-fetches instead of
	## quietly keeping whatever was vendored first.
	local -r wtStamp="${dest}/.version"
	if [[ -f "${dest}/include/wasmtime.h" ]] && [[ "$(cat "${wtStamp}" 2>/dev/null || true)" == "${wasmtimeVer}" ]]; then
		fEcho_Clean "Wasmtime ...: ${wasmtimeVer} ${platform} present"
		return 0
	fi

	_fMustBeInPath curl
	_fMustBeInPath shasum
	_fMustBeInPath tar
	local -r wtName="wasmtime-${wasmtimeVer}-${platform}-c-api"
	local -r wtUrl="https://github.com/bytecodealliance/wasmtime/releases/download/${wasmtimeVer}/${wtName}.tar.xz"
	local -r wtTar="${parentDir}/${wtName}.tar.xz"
	fEcho_Clean "Wasmtime ...: fetching ${wasmtimeVer} ${platform}"
	curl -sSL --fail -o "${wtTar}" "${wtUrl}" || fThrowError "Could not download '${wtUrl}'."  "${FUNCNAME[0]}"
	## shasum, not sha256sum: it is on both Linux and macOS.
	local -r wtSum="$(shasum -a 256 "${wtTar}" | awk '{print $1}')"
	if [[ "${wtSum}" != "${wasmtimeSha256}" ]]; then
		rm -f "${wtTar}"
		fThrowError "Wasmtime ${platform} checksum mismatch: got ${wtSum}."  "${FUNCNAME[0]}"
	fi
	tar --no-same-owner --no-same-permissions -xf "${wtTar}" -C "${parentDir}"
	rm -f "${wtTar}"
	rm -rf "${dest:?}"
	mv "${parentDir}/${wtName}" "${dest}"
	printf '%s\n' "${wasmtimeVer}" > "${wtStamp}"
	fEcho_Clean "Wasmtime ...: vendored ${platform}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Zig(){

	fStage_Zig_Vendor

	fEcho_Clean
	fEcho "Zig: build and test"

	cd "${zigDir}" || fThrowError "Missing the Zig tree: '${zigDir}'."  "${FUNCNAME[0]}"

	## ReleaseSafe is what would ship; the vectors replay through it too.
	## zig wants the count attached to the flag, not as a separate word.
	zig build "-j${buildJobs}" -Doptimize=ReleaseSafe
	## Run by hand rather than through 'zig build test', whose runner reports
	## only a count. Its stderr is not a terminal here, so it names every test.
	if [[ -n "$(command -v python3 2>/dev/null || true)" ]]; then
		zig build "-j${buildJobs}" test-bin
		"${zigDir}/zig-out/test/test" 2>&1 | python3 "${utilityDir}/test-ids.py" zig
	else
		fEcho_Clean "IDs ........: skipped, no python3"
		zig build "-j${buildJobs}" test
	fi

	## zig fmt is silent on success and lists offenders on failure. Plain 'if',
	## not a trailing '&&' - that exact pattern has killed this script before.
	local -r unformattedZig="$(zig fmt --check build.zig lib/src cmd/src 2>&1 || true)"
	if [[ -n "${unformattedZig}" ]]; then
		fThrowError "zig fmt would rewrite: ${unformattedZig//$'\n'/, }"  "${FUNCNAME[0]}"
	fi

	fStage_Zig_Cli
	fStage_Zig_CApi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The vectors cover the two modules. What the command itself prints, and what
## it exits with, is only checked here.
fStage_Zig_Cli(){

	fEcho_Clean
	fEcho "Zig: command surface"

	local -r runner="${utilityDir}/cli-test.bash"
	if [[ ! -f "${runner}" ]]; then
		fEcho_Clean "Skipped ....: cli-test.bash is not present."
		return 0
	fi

	bash "${runner}" --bin "${zigDir}/zig-out/bin/zuid"

	fStage_Zig_BuildStamp

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The build number comes from -Dbuild-epoch, then SOURCE_DATE_EPOCH, then the
## HEAD commit date. An empty SOURCE_DATE_EPOCH is what a tarball script exports
## when its own lookup came back empty, and taking it literally used to drop the
## build number from a build that had a commit date available.
fStage_Zig_BuildStamp(){

	local stampDir=""
	stampDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${stampDir}")

	fId Eq9nb3o "the build number survives an empty SOURCE_DATE_EPOCH"
	## Its own cache, since clang chokes on the empty value too, and a cached
	## @cImport never runs clang.
	(
		cd "${zigDir}" || exit 1
		SOURCE_DATE_EPOCH="" zig build "-j${buildJobs}" --cache-dir "${stampDir}/cache" --prefix "${stampDir}" || exit 1
	) || fTestFail "the build failed with SOURCE_DATE_EPOCH empty."

	local -r stamped="$("${stampDir}/bin/zuid" --version 2>&1 || true)"
	if [[ "${stamped}" != *"(build "* ]]; then
		fTestFail "an empty SOURCE_DATE_EPOCH dropped the build number: --version said '${stamped}'. It should fall through to the commit date."
	fi
	fTestPass

	rm -rf "${stampDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## What is wrong with a shared library's exported names, or nothing: one that
## lib/zuid.map does not allow, or a function zuid.h declares that is missing.
## Reads the map rather than repeating it, since on a Mac build.zig turns the
## same file into Apple's exported symbols list.
fExportProblems(){  ## exported names, one per line
	local -r exportList="$1"
	## The map's names are globs, so they become one anchored regex.
	local -r mapRegex="$(sed 's/#.*//' "${zigDir}/lib/zuid.map" | tr ';{}' '   ' \
		| awk '{ for (i = 1; i <= NF; i++) { if ($i == "global:") on = 1; else if ($i == "local:") on = 0; else if (on) print $i } }' \
		| sed 's/[].[\^$+(){}|]/\\&/g; s/\*/.*/g; s/?/./g' | paste -sd'|' -)"
	if [[ -z "${mapRegex}" ]]; then echo "read no global names out of lib/zuid.map."; return 0; fi
	local -r strayExports="$(grep -v '^$' <<< "${exportList}" | grep -Ev "^(${mapRegex})\$" || true)"
	if [[ -n "${strayExports}" ]]; then
		echo "$(wc -l <<< "${strayExports}" | tr -d ' ') exported symbols are not in lib/zuid.map, such as $(head -n 3 <<< "${strayExports}" | paste -sd' ' -)."
	fi

	local exportName=""
	local -i declaredCount=0
	while IFS= read -r exportName; do
		if ! grep -qx "${exportName}" <<< "${exportList}"; then
			echo "zuid.h declares ${exportName}, and the shared library does not export it."
		fi
		declaredCount=$((declaredCount + 1))
	done < <(sed -n 's/^[a-z][^(]*[ *]\(zuid_[a-z_]*\)(.*/\1/p' "${zigDir}/lib/include/zuid.h")
	if ((declaredCount == 0)); then echo "read no function declarations out of zuid.h."; fi
	return 0
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The C module is one of the released artifacts, so a foreign toolchain has to
## be able to use it. Deliberately not 'zig cc' - that would prove nothing.
fStage_Zig_CApi(){

	fEcho_Clean
	fEcho "Zig: C module from a system compiler"

	local systemCc=""
	if   command -v gcc   &>/dev/null; then systemCc="gcc"
	elif command -v clang &>/dev/null; then systemCc="clang"
	fi
	if [[ -z "${systemCc}" ]]; then
		fEcho_Clean "Skipped ....: no system gcc or clang."
		return 0
	fi
	fEcho_Clean "Compiler ...: ${systemCc}"

	local -r smokeSrc="${zigDir}/lib/test/capi_smoke.c"
	local buildDir=""
	buildDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	## An errexit abort skips a RETURN trap, so the cleanup is registered where
	## the exit handler can also see it.
	_scratchDirs+=("${buildDir}")

	local -i isMac=0
	if [[ "$(uname -s)" == "Darwin" ]]; then isMac=1; fi
	## A native zig build targets this exact macOS, and clang otherwise links for
	## its SDK's and warns about every object. Release builds want a lower floor.
	if ((isMac)); then local -x MACOSX_DEPLOYMENT_TARGET; MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion)"; fi
	local -r libDir="${zigDir}/zig-out/lib"

	## Shared: self-contained, so the header and -lzuid are the whole story.
	## An rpath rather than LD_LIBRARY_PATH, which macOS does not read.
	fId ElpGOHZ "capi_smoke.c against the shared library"
	"${systemCc}" -I "${zigDir}/zig-out/include" "${smokeSrc}" \
		-L "${libDir}" -lzuid -Wl,-rpath,"${libDir}" -o "${buildDir}/smoke-shared" || fTestFail "did not compile."
	"${buildDir}/smoke-shared" || fTestFail "the smoke test failed."
	fTestPass

	## Only the entry points are visible. The library used to export all of
	## Wasmtime, which let any program holding one of those names displace the
	## calls it makes internally.
	fId Eq9gPQm "the shared library exports only what lib/zuid.map names"
	local exportList="" exportProblem=""
	if ((isMac)); then
		exportList="$(nm -gU "${libDir}/libzuid.dylib" | awk '{ sub(/^_/, "", $NF); print $NF }')"
	else
		exportList="$(nm -D --defined-only "${libDir}/libzuid.so" | awk '{print $NF}')"
	fi
	exportProblem="$(fExportProblems "${exportList}")"
	if [[ -n "${exportProblem}" ]]; then fTestFail "${exportProblem}"; fi
	fTestPass

	## The soname, which is what a linked program records rather than the file
	## name. Its major is the ABI promise the stable error codes go with, so it
	## has to match the version constant and the symlink chain has to lead there.
	local -r libVersion="$(sed -n 's/^pub const version = "\([^"]*\)".*/\1/p' "${zigDir}/lib/src/core.zig")"
	local -r abiMajor="${libVersion%%.*}"
	if [[ -z "${abiMajor}" ]]; then
		fThrowError "Could not read the version constant out of lib/src/core.zig."  "${FUNCNAME[0]}"
	fi
	## macOS puts the major before the suffix, and calls the soname an install name.
	local libName="libzuid.so" majorName="libzuid.so.${abiMajor}"
	if ((isMac)); then libName="libzuid.dylib"; majorName="libzuid.${abiMajor}.dylib"; fi
	fId EqA3RdB "${libName} is a symlink onto ${majorName}"
	if [[ ! -L "${libDir}/${libName}" || ! -e "${libDir}/${majorName}" ]]; then
		fTestFail "build.zig's .version is what makes that chain."
	fi
	fTestPass
	fId EqA3RdC "the soname is ${majorName}"
	if ((isMac)); then
		local -r installName="$(otool -D "${libDir}/${libName}" | sed -n '2p')"
		if [[ "${installName}" != "@rpath/${majorName}" ]]; then
			fTestFail "${libName}'s install name is '${installName}'."
		fi
		fTestPass
	elif [[ -z "$(command -v readelf 2>/dev/null || true)" ]]; then
		fTestSkip "no readelf"
	else
		local -r soname="$(readelf -d "${libDir}/${libName}" | sed -n 's/.*Library soname: \[\(.*\)\].*/\1/p')"
		if [[ "${soname}" != "${majorName}" ]]; then
			fTestFail "${libName}'s soname is '${soname}'."
		fi
		fTestPass
	fi

	## And the same thing from the other side: a program defining one of those
	## names must not change what the library calls. On a Mac two-level
	## namespace already keeps them bound inside, export list or not.
	local -r interposeSrc="${zigDir}/lib/test/capi_interpose.c"
	fId Eq9gPQn "a program defining a Wasmtime name still gets a working context"
	if [[ -f "${interposeSrc}" ]]; then
		"${systemCc}" -I "${zigDir}/zig-out/include" "${interposeSrc}" \
			-L "${libDir}" -lzuid -Wl,-rpath,"${libDir}" -o "${buildDir}/interpose" || fTestFail "did not compile."
		"${buildDir}/interpose" || fTestFail "the library's calls were displaced."
		fTestPass
	else
		fTestSkip "capi_interpose.c is not present"
	fi

	## Static: the consumer supplies wasmtime and the system libraries itself.
	## No -lunwind here on purpose - libgcc already provides __register_frame,
	## and the header says so.
	fId ElpGOHa "capi_smoke.c against the static library"
	"${systemCc}" -I "${zigDir}/zig-out/include" "${smokeSrc}" \
		"${zigDir}/zig-out/lib/libzuid.a" "${zigDir}/vendor/wasmtime/lib/libwasmtime.a" \
		-lpthread -ldl -lm -o "${buildDir}/smoke-static" || fTestFail "did not link."
	"${buildDir}/smoke-static" || fTestFail "the smoke test failed."
	fTestPass

	## Now the same thing the way somebody who downloaded the release does it:
	## against a tree holding only what gets shipped, with the link line the
	## header prints. libzuid.a used to nest the whole wasmtime archive inside
	## itself, where no linker looks, and the release carried no separate copy,
	## so this is the check that would have caught it. Deliberately not pointed
	## at vendor/.
	fId Eq9hexE "capi_smoke.c links against the shipped tree, with the header's link line"
	local -r relTree="${buildDir}/release"
	mkdir -p "${relTree}/lib" "${relTree}/include"
	cp "${zigDir}/zig-out/include/zuid.h"                  "${relTree}/include/"
	cp "${zigDir}/zig-out/lib/libzuid.a"                   "${relTree}/lib/"
	cp "${zigDir}/vendor/wasmtime/lib/libwasmtime.a"       "${relTree}/lib/"
	## Apple's ld has no -Bstatic. It needs none here, with only archives in lib/.
	local -a staticOn=('-Wl,-Bstatic') staticOff=('-Wl,-Bdynamic')
	if ((isMac)); then staticOn=(); staticOff=(); fi
	"${systemCc}" -I "${relTree}/include" "${smokeSrc}" \
		-L "${relTree}/lib" "${staticOn[@]}" -lzuid -lwasmtime "${staticOff[@]}" \
		-lpthread -ldl -lm -o "${buildDir}/smoke-release" || fTestFail "did not link."
	"${buildDir}/smoke-release" || fTestFail "the smoke test failed."
	fTestPass

	## And nothing nested, since that is what made the archive unusable.
	fId Eq9hexF "libzuid.a holds objects only, no nested archive"
	if ar t "${zigDir}/zig-out/lib/libzuid.a" | grep -q '\.a$'; then
		fTestFail "libzuid.a has another archive inside it. Only its own objects belong there."
	fi
	fTestPass

	rm -rf "${buildDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Two profiles, because the two implementations have different hot shapes: the
## Go module through its own benchmarks, and the command itself through perf.
fStage_Profile(){

	fEcho_Clean
	fEcho "Profile"

	local -r profileDir="${artifactDir}/profiling"
	mkdir -p "${profileDir}"

	if ((doGo)); then fProfile_Go "${profileDir}"; fi
	if ((doZig)); then fProfile_Cli "${profileDir}"; fi

	fRotate_Artifacts "${profileDir}" "flame_"

	## Non-fatal by design: a hotspot summary is something to read, not a gate.
	if [[ -x "${utilityDir}/flame-report.py" ]]; then
		fEcho_Clean
		"${utilityDir}/flame-report.py" --dir "${profileDir}" || true
	fi

}


fProfile_Go(){

	local -r profileDir="$1"
	local -r converter="${utilityDir}/pprof2flame.py"

	if [[ ! -x "${converter}" ]]; then
		fEcho_Clean "Go .........: skipped - no pprof2flame.py"
		return 0
	fi

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"
	local -r cpuOut="${profileDir}/cpu_${runStamp}.pprof"
	## Only the per-identifier benchmarks. BenchmarkNew builds the base registry,
	## which costs more than everything else put together and would bury the
	## work actually worth looking at.
	go test -p "${buildJobs}" -run '^$' -bench 'BenchmarkGenerate' -benchtime 3000x \
		-cpuprofile "${cpuOut}" -o /dev/null ./zuid >/dev/null
	if "${converter}" --prof "${cpuOut}" --title "zuid Go module" --out "${profileDir}/flame_${runStamp}_go.svg" >/dev/null 2>&1; then
		fEcho_Clean "Go .........: flame_${runStamp}_go.svg"
	else
		fEcho_Clean "Go .........: profile captured, flamegraph conversion skipped"
	fi
	rm -f "${cpuOut}"

}


fProfile_Cli(){

	local -r profileDir="$1"
	local -r exe="${zigDir}/zig-out/bin/zuid"

	if [[ ! -x "${exe}" ]]; then
		fEcho_Clean "CLI ........: skipped - no release build"
		return 0
	fi
	if ! command -v perf &>/dev/null || ! command -v inferno-collapse-perf &>/dev/null || ! command -v inferno-flamegraph &>/dev/null; then
		fEcho_Clean "CLI ........: skipped - needs perf and the inferno tools"
		return 0
	fi

	local scratch=""
	scratch="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${scratch}")

	## perf needs kernel.perf_event_paranoid below 3 to record an unprivileged
	## process. Say which knob rather than failing the build over a profile.
	if ! perf record -q -g -o "${scratch}/perf.data" -- "${exe}" -f '%d%h%u%f%m%g%r' >/dev/null 2>"${scratch}/perf.err"; then
		fEcho_Clean "CLI ........: skipped - perf could not record (kernel.perf_event_paranoid is $(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo unknown))"
		rm -rf "${scratch}"
		return 0
	fi
	perf script -i "${scratch}/perf.data" 2>/dev/null \
		| inferno-collapse-perf 2>/dev/null \
		| inferno-flamegraph --title "zuid CLI" 2>/dev/null \
		> "${profileDir}/flame_${runStamp}_cli.svg"
	fEcho_Clean "CLI ........: flame_${runStamp}_cli.svg"
	rm -rf "${scratch}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Demo(){

	fEcho_Clean
	fEcho "Demo"

	local -r generator="${utilityDir}/gen-demo-gif.py"
	local -r scenario="${repoRoot}/cicd/demo-scenario.toml"
	local -r exe="${zigDir}/zig-out/bin/zuid"

	if [[ ! -x "${generator}" ]] || [[ ! -f "${scenario}" ]]; then
		fEcho_Clean "Skipped ....: no generator or scenario"
		return 0
	fi
	if [[ ! -x "${exe}" ]]; then
		fEcho_Clean "Skipped ....: no release build to record"
		return 0
	fi
	if ! python3 -c 'import PIL' &>/dev/null; then
		fEcho_Clean "Skipped ....: python pillow not installed"
		return 0
	fi

	local -r demoDir="${artifactDir}/demo"
	mkdir -p "${demoDir}"
	local -r rendered="${demoDir}/demo_${runStamp}.gif"

	if ! python3 "${generator}" --scenario "${scenario}" --bin "${exe}" --out "${rendered}" --quiet; then
		fEcho_Clean "Skipped ....: the generator failed"
		return 0
	fi
	fRotate_Artifacts "${demoDir}" "demo_"

	## The README points at assets/demo.gif, so the newest render becomes that.
	mkdir -p "${repoRoot}/assets"
	if ! cmp -s "${rendered}" "${repoRoot}/assets/demo.gif" 2>/dev/null; then
		cp -f "${rendered}" "${repoRoot}/assets/demo.gif"
		fEcho_Clean "Rendered ...: assets/demo.gif updated"
	else
		fEcho_Clean "Rendered ...: unchanged"
	fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Package(){

	fEcho_Clean
	fEcho "Package"

	local -r packager="${utilityDir}/package.bash"
	[[ -x "${packager}" ]] || fThrowError "Missing the packager: '${packager}'."  "${FUNCNAME[0]}"

	"${packager}" --out "${repoRoot}/dist"

	## The release has to run on machines older than this one. These check that
	## it did not pick up this one's CPU, glibc or macOS version.
	local osLabel="linux" archLabel=""
	archLabel="$(uname -m)"
	if [[ "${archLabel}" == "aarch64" ]]; then archLabel="arm64"; fi
	if [[ "$(uname -s)" == "Darwin" ]]; then osLabel="darwin"; archLabel="universal"; fi
	local -r release="${repoRoot}/dist/zuid-${osLabel}-${archLabel}"
	local -i haveObjdump=0
	if command -v objdump >/dev/null 2>&1; then haveObjdump=1; fi

	## The macOS checks read one slice at a time. The AVX scan means nothing on
	## arm64, and the minimum macOS has to hold for both.
	local thinDir=""
	thinDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${thinDir}")
	local -r macSlices=("x86_64" "arm64")

	fId Erfhegq "the macOS release is universal, x86_64 and arm64 in every binary and library"
	if [[ "${osLabel}" != "darwin" ]]; then
		fTestSkip "macOS only"
	else
		mkdir -p "${thinDir}/tgz"
		tar -xzf "${release}.tgz" -C "${thinDir}/tgz"
		local fatFile="" fatArchs="" slice=""
		local -i fatCount=0
		while IFS= read -r fatFile; do
			fatArchs="$(lipo -archs "${fatFile}" 2>/dev/null || true)"
			for slice in "${macSlices[@]}"; do
				if [[ " ${fatArchs} " != *" ${slice} "* ]]; then
					fTestFail "$(basename "${fatFile}") has no ${slice} slice. lipo -archs says '${fatArchs}'."
				fi
			done
			fatCount=$((fatCount + 1))
		done < <(printf '%s\n' "${release}"; find "${thinDir}/tgz" -type f \( -path '*/bin/*' -o -path '*/lib/*' \))
		## The bare binary and the tarball's, libzuid.a, the dylib and libwasmtime.a.
		if ((fatCount < 5)); then
			fTestFail "found ${fatCount} binaries and libraries to check, expected 5."
		fi
		fTestPass
	fi

	fId ErbFB7B "the release uses no AVX in code built here"
	if [[ "${archLabel}" == "arm64" ]]; then
		fTestSkip "x86_64 only"
	elif ((! haveObjdump)); then
		fTestSkip "no objdump"
	else
		local avxTarget="${release}"
		if [[ "${osLabel}" == "darwin" ]]; then
			avxTarget="${thinDir}/zuid-x86_64"
			lipo -thin x86_64 "${release}" -output "${avxTarget}" || fTestFail "could not take the x86_64 slice out of ${release}."
		fi
		## Wasmtime's Rust asks the CPU before it uses AVX, so it is left out.
		## Its names start with _ZN, or _R for the newer mangling.
		local avxScan=""
		avxScan="$(objdump -d --no-show-raw-insn "${avxTarget}" | awk '
			/^[0-9a-f]+ <.*>:$/ { fn = $2; gsub(/^<|>:$/, "", fn); rust = (fn ~ /^_?_(ZN|R[0-9]*[BCIMNXY])/); next }
			rust || (fn in seen) { next }
			/:[[:space:]]+v[a-z]/ || /%[yz]mm/ { seen[fn] = 1; if (++count <= 3) names = names " " fn }
			END { print count + 0 names }
		')"
		if [[ "${avxScan%% *}" != "0" ]]; then
			fTestFail "${avxScan%% *} functions use AVX, such as ${avxScan#* }. package.bash has to name a target."
		fi
		fTestPass
	fi

	## Matches package.bash.
	local -r glibcFloor="2.28"
	fId ErbFB7C "the release needs glibc ${glibcFloor} at most"
	if [[ "${osLabel}" != "linux" ]]; then
		fTestSkip "Linux only"
	elif ((! haveObjdump)); then
		fTestSkip "no objdump"
	else
		local glibcNewest=""
		glibcNewest="$(objdump -T "${release}" | grep -o 'GLIBC_[0-9.]*' | sort -u -V | tail -n 1 || true)"
		glibcNewest="${glibcNewest#GLIBC_}"
		if [[ -z "${glibcNewest}" ]]; then
			fTestFail "found no glibc symbol versions in ${release}."
		fi
		if [[ "$(printf '%s\n' "${glibcNewest}" "${glibcFloor}" | sort -V | tail -n 1)" != "${glibcFloor}" ]]; then
			fTestFail "it needs glibc ${glibcNewest}."
		fi
		fTestPass
	fi

	local -r macFloor="13.0"
	fId ErbFB7D "the release asks for macOS ${macFloor}"
	if [[ "${osLabel}" != "darwin" ]]; then
		fTestSkip "macOS only"
	else
		local minOs="" macSlice=""
		for macSlice in "${macSlices[@]}"; do
			lipo -thin "${macSlice}" "${release}" -output "${thinDir}/zuid-minos" || fTestFail "could not take the ${macSlice} slice out of ${release}."
			minOs="$(otool -l "${thinDir}/zuid-minos" | awk '$1 == "minos" && !found { print $2; found = 1 }')"
			if [[ "${minOs}" != "${macFloor}" ]]; then
				fTestFail "its ${macSlice} slice asks for macOS '${minOs}'."
			fi
		done
		fTestPass
	fi

	## build.zig links the macOS dylib a second time, for the export list. That
	## link has to keep the rest: the install name, the macOS floor, and the
	## ad-hoc signature an arm64 Mac needs to load it at all.
	fId ErfrKRQ "each slice of the release dylib exports only what lib/zuid.map names, and keeps its install name, macOS floor and signature"
	if [[ "${osLabel}" != "darwin" ]]; then
		fTestSkip "macOS only"
	else
		local -r releaseDylib="$(find "${thinDir}/tgz" -type f -name 'libzuid*.dylib' -print -quit)"
		local -r libVersion="$(sed -n 's/^pub const version = "\([^"]*\)".*/\1/p' "${zigDir}/lib/src/core.zig")"
		## otool -L lists the library's own install name first, with the versions
		## a program linked against it records. Zig gives 1.0.0 for compatibility.
		local -r libVersionPlain="${libVersion%%-*}"
		local -r installWant="@rpath/libzuid.${libVersion%%.*}.dylib (compatibility version 1.0.0, current version ${libVersionPlain})"
		[[ -n "${releaseDylib}" ]] || fTestFail "the tarball has no libzuid dylib."
		local thinDylib="" exportProblem="" installName="" dylibMinOs=""
		for macSlice in "${macSlices[@]}"; do
			thinDylib="${thinDir}/libzuid-${macSlice}.dylib"
			lipo -thin "${macSlice}" "${releaseDylib}" -output "${thinDylib}" || fTestFail "could not take the ${macSlice} slice out of $(basename "${releaseDylib}")."
			exportProblem="$(fExportProblems "$(nm -gU "${thinDylib}" | awk '{ sub(/^_/, "", $NF); print $NF }')")"
			if [[ -n "${exportProblem}" ]]; then fTestFail "${macSlice}: ${exportProblem}"; fi
			installName="$(otool -L "${thinDylib}" | sed -n '2s/^[[:space:]]*//p')"
			if [[ "${installName}" != "${installWant}" ]]; then fTestFail "${macSlice}: the install name is '${installName}'."; fi
			dylibMinOs="$(otool -l "${thinDylib}" | awk '$1 == "minos" && !found { print $2; found = 1 }')"
			if [[ "${dylibMinOs}" != "${macFloor}" ]]; then fTestFail "${macSlice}: it asks for macOS '${dylibMinOs}'."; fi
			if [[ "${macSlice}" == "arm64" ]] && ! codesign --verify "${thinDylib}" 2>/dev/null; then
				fTestFail "${macSlice}: the slice is not validly signed."
			fi
		done
		fTestPass
	fi

	rm -rf "${thinDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Installs the optimized native build for daily use, into the first of the
## preferred directories that exists. Part of every full run, so nothing here is
## fatal - a machine with none of those directories still built and tested fine.
fStage_Dogfood(){

	fEcho_Clean
	fEcho "Dogfood"

	local -r exe="${zigDir}/zig-out/bin/zuid"
	if [[ ! -x "${exe}" ]]; then
		fEcho_Clean "Installed ..: nothing built at '${exe}'"
		return 0
	fi

	local target="" candidate=""
	for candidate in "${dogfoodDirs[@]}"; do
		if [[ -d "${candidate}" ]]; then target="${candidate}"; break; fi
	done
	if [[ -z "${target}" ]]; then
		fEcho_Clean "Installed ..: no destination on this machine (${dogfoodDirs[*]})"
		return 0
	fi

	if cmp -s "${exe}" "${target}/zuid" 2>/dev/null; then
		fEcho_Clean "Installed ..: ${target}/zuid already current"
		return 0
	fi
	if ! install -m 0755 "${exe}" "${target}/zuid"; then
		fEcho_Clean "Installed ..: could not write '${target}/zuid'"
		return 0
	fi
	fEcho_Clean "Installed ..: ${target}/zuid"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Archives the whole project - github/, private/, the lot - to ../versions/, then
## commits and pushes, all through the vendored helper. Its git half is why
## --commit and --push are refused alongside it.
fStage_Backup(){

	fEcho_Clean
	fEcho "Backup and publish"

	local -r helper="${utilityDir}/n8git_backup-and-publish"
	[[ -x "${helper}" ]] || fThrowError "Missing the backup helper: '${helper}'."  "${FUNCNAME[0]}"
	_fMustBeInPath rar

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fThrowError "HEAD is detached. Check out a branch before publishing."  "${FUNCNAME[0]}"
	fi

	fEcho_Clean "Archive to .: $(dirname "${repoRoot}")/versions/"
	fEcho_Clean "Excluding ..: ${rarExcludes:-(generic list in the helper only)}"

	## Quiet always: the message was asked for up front, and this run just made every
	## check the helper would prompt about. Without a message it falls to git's editor.
	local -a helperArgs=(-q)
	if [[ -n "${commitMsg}" ]]; then helperArgs+=(-m "${commitMsg}"); fi

	## The helper works from the git directory itself - it archives '../.' and looks
	## for './.git' - so it gets run from there rather than wherever cicd was called.
	(
		cd "${repoRoot}" || fThrowError "Could not enter '${repoRoot}'."  "${FUNCNAME[0]}"
		GIT_BACKUP_AND_PUBLISH_RAR_EXCLUDES="${rarExcludes}" "${helper}" "${helperArgs[@]}"
	)

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Commit(){

	fEcho_Clean
	fEcho "Commit"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fThrowError "HEAD is detached. Check out a branch before committing."  "${FUNCNAME[0]}"
	fi

	local protected=""
	for protected in "${protectedBranches[@]}"; do
		if [[ "${branch}" == "${protected}" ]]; then
			fThrowError "Refusing to commit to '${branch}'. Work on a feature branch and merge it back."  "${FUNCNAME[0]}"
		fi
	done

	if [[ -z "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		fEcho_Clean "Nothing to commit."
		return 0
	fi

	git -C "${repoRoot}" add -A
	git -C "${repoRoot}" commit -m "${commitMsg}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Push(){

	fEcho_Clean
	fEcho "Push"

	local -r remote="$(git -C "${repoRoot}" remote | head -n1)"
	[[ -n "${remote}" ]] || fThrowError "No remote to push to."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fThrowError "HEAD is detached, so there is no branch to push."  "${FUNCNAME[0]}"
	fi
	git -C "${repoRoot}" push -u "${remote}" "${branch}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Artifacts. Everything under cicd/artifacts/ is gitignored; this keeps it
##	from growing without bound.
##

## Tees the whole run to a dated log, so lint-report.bash has something to read
## and a failure can be looked at after the fact.
fStartRunLog(){
	local -r lintDir="${artifactDir}/lint"
	mkdir -p "${lintDir}"
	fRotate_Artifacts "${lintDir}" "run_"
	exec > >(tee -a "${lintDir}/run_${runStamp}.log") 2>&1
}

## Grandfather-father-son: every file from the last few days, then one a week,
## then one a month. Files are named <prefix><YYYYmmdd-HHMMSS>[_role].<ext>.
fRotate_Artifacts(){

	local -r dir="$1"
	local -r prefix="$2"
	[[ -d "${dir}" ]] || return 0

	local -a candidates=()
	mapfile -t candidates < <(find "${dir}" -maxdepth 1 -type f -name "${prefix}*" -printf '%f\n' 2>/dev/null | sort -r)
	((${#candidates[@]})) || return 0

	## Post-increment inside (( )) returns the value from before the increment,
	## so ((n++)) on a zero is a false status and errexit kills the script.
	## Arithmetic assignment has no such trap.
	local -A keptDay=() keptWeek=() keptMonth=()
	local -i days=0 weeks=0 months=0
	local name="" stamp="" day="" week="" month=""
	for name in "${candidates[@]}"; do
		stamp="${name#"${prefix}"}"
		stamp="${stamp%%_*}"
		stamp="${stamp%%.*}"
		## Anything not stamped the way this script stamps things is left alone.
		[[ "${stamp}" =~ ^[0-9]{8}-[0-9]{6}$ ]] || continue
		day="${stamp:0:8}"
		month="${stamp:0:6}"
		week="$(date -d "${day}" +%G-%V 2>/dev/null || echo "${day}")"

		if [[ -z "${keptDay[${day}]:-}" ]] && ((days < keepDaily)); then
			keptDay[${day}]=1; days=$((days + 1)); continue
		fi
		if [[ -z "${keptWeek[${week}]:-}" ]] && ((weeks < keepWeekly)); then
			keptWeek[${week}]=1; weeks=$((weeks + 1)); continue
		fi
		if [[ -z "${keptMonth[${month}]:-}" ]] && ((months < keepMonthly)); then
			keptMonth[${month}]=1; months=$((months + 1)); continue
		fi
		rm -f "${dir:?}/${name}"
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Half the cores, rounded down, never less than one. No stage is allowed the
## whole machine.
fHalfTheCores(){
	local -i cores=1
	if command -v nproc &>/dev/null; then cores="$(nproc)"
	elif command -v sysctl &>/dev/null; then cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"; fi
	local -i half=$((cores / 2))
	((half > 0)) || half=1
	printf '%s\n' "${half}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## sort -V puts 1.2.3 before 1.2.3-dev, so a pre-release reads as newer than the
## release it precedes. Comparing the release part first is what stops a dev
## snapshot passing a floor it is actually below.
fVersion_AtLeast(){
	local -r have="$1"
	local -r want="$2"
	[[ -n "${have}" ]] || return 1
	[[ "${have}" =~ ^[0-9] ]] || return 1
	local -r haveRelease="${have%%-*}"
	if [[ "$(printf '%s\n%s\n' "${want}" "${haveRelease}" | sort -V | head -n1)" != "${want}" ]]; then
		return 1
	fi
	## Equal release parts and a pre-release suffix means it is below the floor.
	if [[ "${haveRelease}" == "${want}" ]] && [[ "${have}" != "${haveRelease}" ]]; then
		return 1
	fi
	return 0
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Other projects on the same machine may pin an older Zig through the shared
## 'zig' link, so this one finds its own: ZIG if set, else the zig on PATH if
## it is new enough, else ~/.local/zig-<platform>-<version>/zig, the way the
## release tarballs unpack. The one picked goes first on PATH as 'zig', so
## package.bash and the harnesses run it too.
fFindZig(){  ## minimum version
	local -r want="$1"
	local found="" candidate=""
	if [[ -n "${ZIG:-}" ]]; then
		[[ -x "${ZIG}" ]] || fThrowError "ZIG is set to '${ZIG}', which is not a program."  "${FUNCNAME[0]}"
		found="${ZIG}"
	elif candidate="$(command -v zig 2>/dev/null)" && fVersion_AtLeast "$("${candidate}" version 2>/dev/null || true)" "${want}"; then
		return 0
	else
		for candidate in "${HOME}"/.local/zig-*-"${want}"/zig; do
			if [[ -x "${candidate}" ]]; then found="${candidate}"; break; fi
		done
		[[ -n "${found}" ]] || fThrowError "Zig ${want} or newer required, found '$(zig version 2>/dev/null || echo none)' on PATH. Set ZIG to its binary, or unpack the release as ~/.local/zig-<platform>-${want}."  "${FUNCNAME[0]}"
	fi
	local -r have="$("${found}" version 2>/dev/null || true)"
	fVersion_AtLeast "${have}" "${want}" || fThrowError "Zig ${want} or newer required, found '${have}' at ${found}."  "${FUNCNAME[0]}"
	local linkDir=""
	linkDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${linkDir}")
	ln -s "$(readlink -f "${found}")" "${linkDir}/zig"
	export PATH="${linkDir}:${PATH}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
_fMustBeInPath(){

	local -r programToCheckForInPath="${1:-}"
	if [[ -z "${programToCheckForInPath}" ]]; then
		fThrowError "_fMustBeInPath(): No program specified."
	elif [[ -z "$(command -v "${programToCheckForInPath}" 2>/dev/null || true)" ]]; then
		fThrowError "Not found in path: ${programToCheckForInPath}"
	fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_Copyright_About_Syntax(){
	fPrint_Copyright
	fPrint_AboutAndSyntax
	if [[ "${1:-}" == "1" ]]; then fPrint_Help; fi  ## An '&&' here would return 1 and trip the ERR trap.
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Generic output stuff.
##

declare -i _wasLastEchoBlank=0

function fEcho_Clean(){
	if [[ -n "${1:-}" ]]; then
		echo -e "$*"
		_wasLastEchoBlank=0
	elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then
		_wasLastEchoBlank=1
	fi
}
function fEcho()                   { if [[ -n "${*:-}" ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
function fEcho_Force()             { fEcho_ResetBlankCounter; fEcho "${*:-}";                              }
function fEcho_Clean_Force()       { fEcho_ResetBlankCounter; fEcho_Clean "${*:-}";                        }
function fEcho_ResetBlankCounter() { _wasLastEchoBlank=0;                                                  }


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Generic error-handling stuff.
##

declare -i _wasCleanupRun=0
declare -a _scratchDirs=()

function fThrowError(){
	local    errMsg="${1:-}"
	local -r funcName="${2:-}"
	[[ -z "${errMsg}" ]] && errMsg="An error occurred."
	if [[ -z "${funcName}" ]]; then
		errMsg="${meName}: ${errMsg}"
	else
		errMsg="${meName}.${funcName}(): ${errMsg}"
	fi
	fEcho_Clean
	fEcho_Clean "${errMsg}"
	fEcho_Clean
	exit 1
}
function _fRemoveScratchDirs(){
	local dir=""
	for dir in "${_scratchDirs[@]}"; do
		[[ -n "${dir}" ]] && [[ "${dir}" == /tmp/* ]] && rm -rf "${dir}"
	done
	_scratchDirs=()
}
function _fTrap_Exit(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		_fRemoveScratchDirs
		_fSingleExitPoint "${@}"
	fi
}
function _fTrap_Error(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		_fRemoveScratchDirs
		fEcho_ResetBlankCounter
		_fSingleExitPoint "${@}"
	fi
}
function _fSingleExitPoint(){
	local -r signal="${1:-}";  shift || true
	local -r lineNum="${1:-}"; shift || true
	local -r errNum="${1:-0}"; shift || true
	local -r errMsg="${*:-}"
	if [[ "${signal}" == "INT" ]]; then
		fEcho_Force
		fEcho "User interrupted."
		exit 1
	elif [[ "${errNum}" != "0" ]]; then
		## Every failing tool here exits 1, including the trailing-'&&' bug this
		## script has hit three times, so 1 is exactly the code worth reporting.
		fEcho_Clean
		fEcho_Clean "Signal .....: '${signal}'"
		fEcho_Clean "Err# .......: '${errNum}'"
		fEcho_Clean "Error ......: '${errMsg}'"
		fEcho_Clean "At line# ...: '${lineNum}'"
		fEcho_Clean
	fi
}
function fDefineTrap_Error_Fatal(){
	true
	trap '_fTrap_Error ERR     ${LINENO} $? $_' ERR
	set -e
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
## Execution entry point (do not modify)
##

## Define error and exit handling
set -e; set -E; set -u
fDefineTrap_Error_Fatal
trap '_fTrap_Error SIGHUP  ${LINENO} $? $_' SIGHUP
trap '_fTrap_Error SIGINT  ${LINENO} $? $_' SIGINT    ## CTRL+C
trap '_fTrap_Error SIGTERM ${LINENO} $? $_' SIGTERM
trap '_fTrap_Exit  EXIT    ${LINENO} $? $_' EXIT
trap '_fTrap_Exit  INT     ${LINENO} $? $_' INT
trap '_fTrap_Exit  TERM    ${LINENO} $? $_' TERM

declare meName="$(basename "${BASH_SOURCE[0]}")"


fMain "${@}"

