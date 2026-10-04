#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Checks cicd.bash's own argument handling and the two helpers that
##		stand between it and a bad commit. The arguments are driven through the
##		real script, with values it refuses before any stage runs, so nothing is
##		built or logged. The helpers are lifted out of the script by name and run
##		against a scratch repo. So are the publish preflight and stage, against
##		scratch repos pushing to a local bare remote, with gh stubbed out.
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
	printf 'x86_64\n' > "${dir}/repo/dist/zuid-linux-x86_64"
	printf 'arm64\n'  > "${dir}/repo/dist/zuid-linux-arm64"
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
		for fn in fConfig _fMustBeInPath fCoreVersion fPublish_Preflight fStage_Publish; do
			fLoad "${fn}" || { printf 'no %s in cicd.bash\n' "${fn}"; exit 2; }
		done
		fConfig
		# shellcheck disable=2034,2154  ## Read by the lifted functions. The defaults come from the lifted fConfig.
		{
			repoRoot="${dir}/repo"; zigDir="${dir}/repo/zig"; incomingDir="${dir}/repo/dist-incoming"
			releaseBranch="${default_releaseBranch}"; releaseAssets=("${default_releaseAssets[@]}")
			doQuietly="$2"; allowPartial="$3"
			publishVersion=""; publishRemote=""; publishHead=""
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
## Five targets, three bare binaries, the package and checksums.txt.
((${#betaUploads[@]} == 10)) || sumsBad+=" ${#betaUploads[@]} uploads, expected 10;"
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

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20261003 JC: Publishing.
##		- 20260930 JC: Created.
