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
##		SOURCE_DATE_EPOCH it hands on.
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


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Helpers, lifted out of the script by name. One that has moved or been
## renamed fails here rather than being skipped.

fLoad(){  ## function name
	local -r body="$(sed -n "/^$1(){/,/^}/p" "${cicd}")"
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

## The backup helper archives the folder above the checkout, which for a
## worktree is not the project, so the default backup steps aside there.
fInitIn(){  ## repo dir, args...
	(
		# shellcheck disable=2329  ## Called by the lifted functions, not here.
		fThrowError(){ printf '%s\n' "$1"; exit 1; }
		# shellcheck disable=2034  ## Read by the lifted fInit.
		{
			repoRoot="$1"; onlyToolchain=""; commitMsg=""; doQuietly=0
			doCross=0; doQuick=0; doSync=1; doCommit=0; commitAsked=0; doPush=0; doPackage=0
			doBackup=1; backupAsked=0; backupInWorktree=0; doDogfood=1; dogfoodAsked=0; doPublish=0; allowPartial=0
		}
		shift
		local fn=""
		for fn in fMustBeAValue fInit; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fInit "$@"
		printf 'doBackup=%s backupInWorktree=%s\n' "${doBackup}" "${backupInWorktree}"
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
export PATH="${stubBin}:${PATH}"

## A tarball whose top directory carries the version, the way package.bash
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
	fTarball "${dir}/repo/dist/zuid-linux-x86_64.tgz" "${version}"
	fTarball "${dir}/repo/dist/zuid-linux-arm64.tgz" "${version}"
	fTarball "${dir}/repo/dist/zuid-freebsd-x86_64.tgz" "${version}"
	printf 'x86_64\n' > "${dir}/repo/dist/zuid-linux-x86_64"
	printf 'arm64\n'  > "${dir}/repo/dist/zuid-linux-arm64"
	printf 'freebsd\n' > "${dir}/repo/dist/zuid-freebsd-x86_64"
	printf 'stale\n'  > "${dir}/repo/dist/checksums.txt"
	: > "${dir}/repo/dist/.zuid-package-dir"
	fTarball "${dir}/repo/dist-incoming/zuid-darwin-universal.tgz" "${version}"
	printf 'universal\n' > "${dir}/repo/dist-incoming/zuid-darwin-universal"
	printf 'zip x86_64\n' > "${dir}/repo/dist-incoming/zuid-windows-x86_64.zip"
	printf 'zip arm64\n'  > "${dir}/repo/dist-incoming/zuid-windows-arm64.zip"
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
		for fn in fConfig _fMustBeInPath fCoreVersion fPublish_Preflight fPublish_Downloads fStage_Publish; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fConfig
		# shellcheck disable=2034,2154  ## Read by the lifted functions. The defaults come from the lifted fConfig.
		{
			repoRoot="${dir}/repo"; zigDir="${dir}/repo/zig"; incomingDir="${dir}/repo/dist-incoming"
			releaseBranch="${default_releaseBranch}"; releaseAssets=("${default_releaseAssets[@]}")
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
rm -f "${work}/partial/repo/dist-incoming/"zuid-windows-*.zip
fWantPublishRefusal ErgqYt9 "a set missing a platform is refused without --allow-partial" partial "No asset for: zuid-windows-x86_64.zip zuid-windows-arm64.zip" 1 0

fId ErgqYtA "--allow-partial publishes the rest and names what is missing"
rm -rf "${work}/partial/repo/dist/release"
out="$(fPublishIn partial 1 1 < /dev/null)" && rc=0 || rc=$?
if ((rc == 0)) && [[ "${out}" == *"Missing ....: zuid-windows-x86_64.zip zuid-windows-arm64.zip"* ]] && [[ -e "${work}/partial/gh-create" ]]
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
	fTarball "${work}/stale/repo/dist-incoming/zuid-darwin-universal.tgz" 1.0.0-alpha.1
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

fId ErgqjsR "the release notes are the changelog's section for the version"
betaNotes=""
for ((argIndex = 0; argIndex < ${#betaArgs[@]}; argIndex++)); do
	if [[ "${betaArgs[argIndex]}" == "--notes" ]]; then betaNotes="${betaArgs[argIndex + 1]:-}"; fi
done
if [[ "${betaNotes}" == *"Notes for this one."* ]] && [[ "${betaNotes}" != *"older one"* ]]
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
for name in 'zuid_1.0.0~beta.1_arm64.deb' 'zuid-1.0.0~beta.1-1.x86_64.rpm' 'zuid-1.0.0~beta.1-1.aarch64.rpm' 'zuid-1.0.0-beta.1-src.tar.gz' 'zuid-windows-x86_64.exe'; do
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
	"<tr><th>Linux</th><td>$(fLinks zuid-linux-x86_64.tgz zuid-linux-x86_64 zuid_1.0.0.beta.1_amd64.deb zuid-1.0.0.beta.1-1.x86_64.rpm)</td><td>$(fLinks zuid-linux-arm64.tgz zuid-linux-arm64 zuid_1.0.0.beta.1_arm64.deb zuid-1.0.0.beta.1-1.aarch64.rpm)</td></tr>"
	"<tr><th>macOS</th>"
	"<tr><th>Windows</th><td>$(fLinks zuid-windows-x86_64.zip zuid-windows-x86_64.exe)</td><td>$(fLinks zuid-windows-arm64.zip)</td></tr>"
	"<tr><th>FreeBSD</th><td>$(fLinks zuid-freebsd-x86_64.tgz zuid-freebsd-x86_64)</td><td>-</td></tr>"
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
macWant="<tr><th>macOS</th><td colspan=\"2\" align=\"center\">$(fLinks zuid-darwin-universal.tgz zuid-darwin-universal)</td></tr>"
if [[ "${tableRows[2]:-}" == "${macWant}" ]]
	then fPass
	else fFail "macOS row was '${tableRows[2]:-}'"
fi

## The partial run above left out both Windows files.
fId Erm9fTr "a target with no file gets a dash in its cell"
partialNotes="$(fNotesOf "${work}/partial/gh-create")"
partialRows=()
mapfile -t partialRows < <(grep '^<tr>' <<< "${partialNotes}" || true)
if [[ "${partialRows[3]:-}" == "<tr><th>Windows</th><td>-</td><td>-</td></tr>" ]] && [[ "${partialRows[1]:-}" == "<tr><th>Linux</th><td><a href="* ]] && [[ "${partialNotes}" != *zuid-windows* ]]
	then fPass
	else fFail "rows were '${partialRows[*]:-}'"
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
## which let ErkRrml pass the check it is meant to fail.
mapfile -t fixtureIds < <(python3 "${idsTree}/cicd/utility/test-ids.py" new -n 4 --at 2026-09-01T12:00:00Z)

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
		for fn in fId fStage_Zig_Fuzz; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		# shellcheck disable=2034  ## Read by the lifted functions.
		{
			doQuick=0; zigDir="${dir}/zig"; buildJobs=1
			_scratchDirs=(); artifactDir="${dir}/artifacts"; runStamp="pipeline-test"
		}
		export FAKE_FUZZ="$1" FAKE_FUZZ_TEST="${2:-}" PATH="${fuzzBin}:${PATH}"
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

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261004 JC: SOURCE_DATE_EPOCH kept from zig.
##		- 20261004 JC: The download table in the release notes.
##		- 20261004 JC: test-ids.py and the Zig fuzz report.
##		- 20261003 JC: Publishing.
##		- 20260930 JC: Created.
