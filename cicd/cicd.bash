#!/bin/bash

# shellcheck disable=2119  ## Disable confusing and inapplicable warning about function's $1 meaning script's $1.
# shellcheck disable=2120  ## OK with declaring functions that accept arguments, without calling with arguments.
# shellcheck disable=2155  ## Disable check to 'Declare and assign separately to avoid masking return values'.

##	Purpose: See fPrint_AboutAndSyntax() and fPrint_Help().
##	History:
##		- 20260802 JC: Created.

declare -i doQuietly=0; [[ ${ZUID_CICD_QUIET} -eq 1 ]] && doQuietly=1
declare    thisVersion="0.1.0"
declare    copyrightYear="2026"
declare    author="Jim Collier"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fConfig(){ :;

	## Toolchain floors. Only the machine that produces the wasm artifact needs Go
	## 1.24+, but one floor is easier to reason about than two.
	default_minVer_Go="1.24"
	default_minVer_Zig="0.16.0"

	## Cross targets for --cross, as GOOS/GOARCH. Go builds these with cgo off.
	## The Zig side will not match this list - macOS there needs a Mac and an SDK.
	default_crossTargets=("linux/arm64" "windows/amd64" "darwin/arm64")

	## Merge targets, never places to commit.
	default_protectedBranches=("main" "dev")

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_Copyright(){
	((doQuietly)) && return
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
	((doQuietly)) && return
	fEcho_Clean ""
	#  X-------------------------------------------------------------------------------X
	cat <<- EOF_p3vk9
		Builds and tests both zuid implementations. Nothing is committed, pushed, or
		packaged unless asked for.

		Syntax: ${meName} [options]
	EOF_p3vk9
	fEcho_Clean_Force ""
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPrint_Help(){
	((doQuietly)) && return
	#  X-------------------------------------------------------------------------------X
	cat <<- EOF_h7wq4
		Options:
		    --only <go|zig>   Drive one toolchain instead of both. Only that one has
		                      to be installed.
		    --cross           Also cross-build for: ${crossTargets[*]}
		    --commit <msg>    Commit if everything passed. Refuses on a protected
		                      branch: ${protectedBranches[*]}
		    --push            Push the current branch. Implies a remote exists.
		    --package         Build release artifacts. Not implemented yet.
		    --publish         Publish a release. Not implemented yet.
		    --quiet           Suppress the banner.
		    -h, --help        This.
		    -v, --version     Version and copyright.

		Both toolchains have to reproduce testdata/vectors.tsv, which is what the test
		stage checks. The Zig side is skipped while it has no source.

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
	_fMustBeInPath sed
	_fMustBeInPath sort

	## Make template constants immutible
	local -r meName="${meName}"

	## Config; 1] Define placeholder variables; 2] Call fConfig() to set them; 3] Freeze them as read-only.
	local    default_minVer_Go=""
	local    default_minVer_Zig=""
	local -a default_crossTargets=()
	local -a default_protectedBranches=()
	fConfig
	local -r minVer_Go="${default_minVer_Go}"
	local -r minVer_Zig="${default_minVer_Zig}"
	local -ra crossTargets=("${default_crossTargets[@]}")
	local -ra protectedBranches=("${default_protectedBranches[@]}")

	## Layout. This script lives in the repo's cicd/, so the repo root is one up.
	local -r repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	local -r goDir="${repoRoot}/go"
	local -r zigDir="${repoRoot}/zig"
	local -r distDir="${repoRoot}/dist"

	## Args; 1] Define placeholder variables; 2] Call fInit() to set them; 3] Freeze them read-only.
	local    onlyToolchain=""
	local    commitMsg=""
	local -i doCross=0
	local -i doCommit=0
	local -i doPush=0
	fInit "${@}"
	readonly onlyToolchain
	readonly commitMsg
	readonly doCross
	readonly doCommit
	readonly doPush

	local -i doGo=1;  [[ "${onlyToolchain}" == "zig" ]] && doGo=0
	local -i doZig=1; [[ "${onlyToolchain}" == "go"  ]] && doZig=0

	##
	## Make it so
	##

	## Plain 'if', not '&&' - a trailing false in a function trips the ERR trap.
	fPreflight
	fStage_Shell
	if ((doGo));               then fStage_Go;       fi
	if ((doZig));              then fStage_Zig;      fi
	if ((doCross)) && ((doGo)); then fStage_Go_Cross; fi
	if ((doCommit));           then fStage_Commit;   fi
	if ((doPush));             then fStage_Push;     fi

	fEcho_Clean
	fEcho "Passed."
	fEcho_Clean

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fInit(){

	local -r _allArgs="$*"

	## Determine if we need to show help
	case " ${_allArgs,,} " in
		*" -h "*|*" --help "*)                 fPrint_Copyright_About_Syntax 1; exit 0 ;;
		*" -v "*|*" --ver "*|*" --version "*)  fPrint_Copyright               ; exit 0 ;;
	esac

	local currentArg=""
	while (($#)); do
		currentArg="${1,,}"
		case "${currentArg}" in

			## Switches taking a parameter
			--only)
				shift || true
				onlyToolchain="${1,,}"
				if [[ "${onlyToolchain}" != "go" ]] && [[ "${onlyToolchain}" != "zig" ]]; then
					fThrowError "Expecting 'go' or 'zig' after --only, instead got '$1'."  "${FUNCNAME[0]}"
				fi
				;;
			--commit)
				shift || true
				if [[ -z "$1" ]]; then fThrowError "Expecting a message after --commit."  "${FUNCNAME[0]}"; fi
				commitMsg="$1"
				doCommit=1
				;;

			## Unitary switches
			--cross)    doCross=1   ;;
			--push)     doPush=1    ;;
			--quiet)    doQuietly=1 ;;

			## Opt-in stages that do not exist yet. Say so rather than pretending.
			--package|--publish)
				fThrowError "Not implemented yet: '${currentArg}'. Packaging waits on the Zig side, which waits on the upstream wasm module."  "${FUNCNAME[0]}"
				;;

			## ¯\_(ツ)_/¯
			*)  fThrowError "Argument invalid or not expected in this context: '$1'."  "${FUNCNAME[0]}" ;;

		esac
		shift || true
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPreflight(){

	fEcho_Clean
	fEcho "Preflight"

	[[ -d "${repoRoot}/.git" ]] || fThrowError "Not a git repo: '${repoRoot}'."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	fEcho_Clean "Branch .....: ${branch}"

	if ((doGo)); then
		_fMustBeInPath go
		local -r haveVer_Go="$(go version | awk '{print $3}' | sed 's/^go//')"
		fVersion_AtLeast "${haveVer_Go}" "${minVer_Go}" || fThrowError "Go ${minVer_Go} or newer required, found ${haveVer_Go}."  "${FUNCNAME[0]}"
		fEcho_Clean "Go .........: ${haveVer_Go}"
	fi

	if ((doZig)); then
		_fMustBeInPath zig
		local -r haveVer_Zig="$(zig version)"
		fVersion_AtLeast "${haveVer_Zig}" "${minVer_Zig}" || fThrowError "Zig ${minVer_Zig} or newer required, found ${haveVer_Zig}."  "${FUNCNAME[0]}"
		fEcho_Clean "Zig ........: ${haveVer_Zig}"
	fi

	[[ -f "${repoRoot}/testdata/vectors.tsv" ]] || fThrowError "Missing the shared test vectors: 'testdata/vectors.tsv'."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Shell(){

	fEcho_Clean
	fEcho "Bash: lint"

	## Not a toolchain, so a missing shellcheck is a gap in coverage, not a failure.
	if [[ -z "$(command -v shellcheck 2>/dev/null || true)" ]]; then
		fEcho_Clean "shellcheck not installed - skipping."
		return
	fi

	## Only this script. x9muid1 under utility/ is 2023 reference code, not ours to keep clean.
	shellcheck "${repoRoot}/cicd/cicd.bash"
	fEcho_Clean "Clean."

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Go(){

	fEcho_Clean
	fEcho "Go: build, vet, format, test"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	go build ./...
	go vet ./...

	## gofmt is silent on success and lists offenders on failure, so it needs the test.
	local -r unformatted="$(gofmt -l .)"
	[[ -n "${unformatted}" ]] && fThrowError "gofmt would rewrite: ${unformatted//$'\n'/, }"  "${FUNCNAME[0]}"

	go test ./...

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Go_Cross(){

	fEcho_Clean
	fEcho "Go: cross-build"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"
	mkdir -p "${distDir}"

	local target="" goos="" goarch="" ext=""
	for target in "${crossTargets[@]}"; do
		goos="${target%%/*}"
		goarch="${target##*/}"
		ext=""; [[ "${goos}" == "windows" ]] && ext=".exe"
		CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" go build -o "${distDir}/zuid-go-${goos}-${goarch}${ext}" ./cmd/zuid-go
		fEcho_Clean "Built ......: ${goos}/${goarch}"
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Zig(){

	fEcho_Clean
	fEcho "Zig: build and test"

	## The Zig side is blocked on the upstream reactor wasm module, so there is
	## nothing to build yet. Skipping beats failing on work that has not started.
	if [[ ! -f "${zigDir}/build.zig" ]]; then
		fEcho_Clean "No build.zig yet - skipping."
		return
	fi

	cd "${zigDir}" || fThrowError "Missing the Zig tree: '${zigDir}'."  "${FUNCNAME[0]}"

	zig build
	zig build test

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Commit(){

	fEcho_Clean
	fEcho "Commit"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"

	local protected=""
	for protected in "${protectedBranches[@]}"; do
		[[ "${branch}" == "${protected}" ]] && fThrowError "Refusing to commit to '${branch}'. Work on a feature branch and merge it back."  "${FUNCNAME[0]}"
	done

	if [[ -z "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		fEcho_Clean "Nothing to commit."
		return
	fi

	git -C "${repoRoot}" add -A
	git -C "${repoRoot}" commit -m "${commitMsg}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Push(){

	fEcho_Clean
	fEcho "Push"

	[[ -n "$(git -C "${repoRoot}" remote)" ]] || fThrowError "No remote to push to."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	git -C "${repoRoot}" push -u origin "${branch}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fVersion_AtLeast(){
	local -r have="$1"
	local -r want="$2"
	[[ -n "${have}" ]] || return 1
	[[ "$(printf '%s\n%s\n' "${want}" "${have}" | sort -V | head -n1)" == "${want}" ]]
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
_fMustBeInPath(){

	local -r programToCheckForInPath="$1"
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
	if [[ "$1" == "1" ]]; then fPrint_Help; fi  ## An '&&' here would return 1 and trip the ERR trap.
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Generic output stuff.
##

declare -i _wasLastEchoBlank=0

function fEcho_Clean(){
	if [[ -n "$1" ]]; then
		echo -e "$*"
		_wasLastEchoBlank=0
	elif [[ $_wasLastEchoBlank -eq 0 ]] && echo; then
		_wasLastEchoBlank=1
	fi
}
function fEcho()                   { if [[ -n "$*" ]]; then fEcho_Clean "[ $* ]"; else fEcho_Clean ""; fi; }
function fEcho_Force()             { fEcho_ResetBlankCounter; fEcho "$*";                                  }
function fEcho_Clean_Force()       { fEcho_ResetBlankCounter; fEcho_Clean "$*";                            }
function fEcho_ResetBlankCounter() { _wasLastEchoBlank=0;                                                  }


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Generic error-handling stuff.
##

declare -i _wasCleanupRun=0

function fThrowError(){
	local    errMsg="$1"
	local -r funcName="$2"
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
function _fTrap_Exit(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		_fSingleExitPoint "${@}"
	fi
}
function _fTrap_Error(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		fEcho_ResetBlankCounter
		_fSingleExitPoint "${@}"
	fi
}
function _fSingleExitPoint(){
	local -r signal="$1";  shift || true
	local -r lineNum="$1"; shift || true
	local -r errNum="$1";  shift || true
	local -r errMsg="$*"
	if [[ "${signal}" == "INT" ]]; then
		fEcho_Force
		fEcho "User interrupted."
		exit 1
	elif [[ "${errNum}" != "0" ]] && [[ "${errNum}" != "1" ]]; then  ## Clunky string compare is less likely to fail than integer
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


##
## Execution entry point (do not modify)
##

## Define error and exit handling
set -e; set -E
fDefineTrap_Error_Fatal
trap '_fTrap_Error SIGHUP  ${LINENO} $? $_' SIGHUP
trap '_fTrap_Error SIGINT  ${LINENO} $? $_' SIGINT    ## CTRL+C
trap '_fTrap_Error SIGTERM ${LINENO} $? $_' SIGTERM
trap '_fTrap_Exit  EXIT    ${LINENO} $? $_' EXIT
trap '_fTrap_Exit  INT     ${LINENO} $? $_' INT
trap '_fTrap_Exit  TERM    ${LINENO} $? $_' TERM

declare meName="$(basename "${BASH_SOURCE[0]}")"


fMain "${@}"
