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
##		- 20261003 JC: Publishing to GitHub releases.
##		- 20261004 JC: Runs in a linked worktree, minus the backup.
##		- 20261010 JC: --container.
##		- 20261014 JC: --gate and the pre-push hook. git and gh through gitsby when it's installed.
##		- 20261018 JC: --gate is --ci now. Every run cross-compiles.
##		- 20261019 JC: goleak, go vet on the dependencies, staticcheck and govulncheck from the image.
##		- 20261019 JC: govulncheck fails on called stdlib advisories and scans the reactor. The reactor builds with the image's Go.
##		- 20261019 JC: The C tests under ASan, LSan and UBSan, and gcc's and clang's analyzers, from the image.
##		- 20261019 JC: --leakcheck: the Go and C soak tests and clang's cross-file analyzer.
##		- 20261019 JC: --leakcheck: CodeQL on Go and C, from an image of its own.
##		- 20261019 JC: --leakcheck is on by default, off for --quick and --gate. --no-leakcheck.
##		- 20261019 JC: --ci is --gate again.
##		- 20261023 JC: --no-fuzz, --no-profile, --no-demo.
##		- 20261025 JC: The container by default where docker answers. --no-container.
##		- 20261025 JC: Zig caches emptied over 2 GB or after a Zig change. The image's has its own volume.
##		- 20261025 JC: Docker cleanup by label at the end of a run. --keep-temp.

declare -i doQuietly=0; [[ "${ZUID_CICD_QUIET:-}" == "1" ]] && doQuietly=1
## Global, since the exit trap reads it after fMain has gone.
declare -i keepTemp=0
## Set by --container for the run it starts inside.
declare -i inContainer=0; [[ "${ZUID_IN_CONTAINER:-}" == "1" ]] && inContainer=1
declare    thisVersion="0.1.0"
declare    copyrightYear="2026"
declare    author="Jim Collier"

## gitsby picks the git host account from the repo's path. A plain clone
## without it gets plain git and gh.
if command -v gitsby >/dev/null 2>&1; then
	git(){ gitsby -q raw git "$@" ;}
fi
fGh(){
	if   [[ -n "${ZUID_GH:-}" ]];                then "${ZUID_GH}" "$@"
	elif command -v gitsby >/dev/null 2>&1; then gitsby -q raw gh "$@"
	else gh "$@"
	fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fConfig(){ :;

	## Toolchain floors. Only the machine that produces the wasm artifact needs Go
	## 1.24+, but one floor is easier to reason about than two.
	default_minVer_Go="1.24"
	default_minVer_Zig="0.17.0"

	## Cross targets, as GOOS/GOARCH. Go builds these with cgo off, as compile
	## checks, on every run. The Zig side does not use this list; its cross builds
	## come with --package. Its macOS arm64 build is half of the universal
	## release, which package.bash makes on a Mac.
	default_crossTargets=("linux/arm64" "windows/amd64" "darwin/arm64")

	## Merge targets, never places to commit.
	default_protectedBranches=("main" "dev")

	## --publish tags and releases from this branch only.
	default_releaseBranch="main"

	## One asset per release target, by the name the installers ask for, after
	## "zuid-<version>-". --publish refuses a set with any of these missing, unless
	## --allow-partial.
	default_releaseAssets=("linux-x86_64.tgz" "linux-arm64.tgz" "freebsd-x86_64.tgz" "darwin-universal.tgz" "windows-x86_64.zip" "windows-arm64.zip")

	## Vendored Wasmtime C API, pinned. Fetched into zig/vendor/ when absent.
	## One checksum per platform, as <arch>-<os>=<sha256>, in Wasmtime's own names.
	## A Mac vendors both macOS ones, since its release is universal. Linux
	## vendors both Linux ones under --package, which releases both, and both
	## Windows ones. x86_64 is the mingw one, which a Zig Windows build links.
	## arm64 has only an MSVC one, so that build links its wasmtime.dll.
	default_wasmtimeVer="v47.0.3"
	default_wasmtimeSha256s=(
		"x86_64-linux=aaa3621f2a3d8393696702897f8f78a1cc504437d500701496d560125aefd732"
		"aarch64-linux=c1ef99bb4ef0151282f339e22a67f8229d9ab336f9a17387e65f140b79c45be1"
		"x86_64-macos=627622087b77b92c163e826ec6ebf834a70d78735828043edf7ace263f8a9e62"
		"aarch64-macos=1854c8f03a764c89afe77fa88d9092ab89a368e527cd27a12959b1d91152324e"
		"x86_64-mingw=355a0c7b49b92bb011e74a4047cc1186271aeb8c8cfcc4360248caaf3c4d5f38"
		"aarch64-windows=57107b14b28ac2152e903501fe1722007b90fc11ccd63ad6d62ed574c5dd90db"
	)

	## Wasmtime releases nothing for FreeBSD, so its C API comes from FreeBSD's
	## own package, plus the zstd package that build calls. The FreeBSD 14 repo,
	## so the release runs on 14 and later. A repo drops a package's file when it
	## moves on to a new build, and the fetch then 404s: repin from the repo's
	## packagesite. A rebuild of the same version is a new file too, with a new
	## hash. The packagesite's sum is pkg's own checksum, not the file's sha256,
	## so take the hash from the download. Linux vendors these under --package,
	## which releases FreeBSD.
	default_freebsdRepo="https://pkg.freebsd.org/FreeBSD:14:amd64/quarterly"
	default_freebsdPkgs=(
		"libwasmtime-49.0.1=95ee2302088ccbb697428bf03e90e79d2636e3da2869be1ceebafa2534f40d74"
		"zstd-1.5.7_2=ff165cf61fcbe6a225636f51b083898a06ce2ca8bb9fcb2e956acced617c4c26"
	)

	## The reactor wasm module is built from this package, which go.mod pins to
	## a release, so the Go side and the Zig side cannot end up on two versions
	## of the conversion library.
	default_reactorPackage="github.com/jim-collier/convert-base-v2/lib/reactor"

	## Dogfood. Each release file this run built goes to its own platform's synced
	## bin dir, if that dir exists: "file in dist/ after zuid-<version>-|name
	## there|dir". The name there never has the version, so there's only ever one.
	## Every box reads those, so only release builds go there, never a host build.
	## No arm64 or FreeBSD dir exists.
	default_dogfoodSynced=(
		"linux-x86_64|zuid|${HOME}/synced/0-0/common/exec/util/linux/bin"
		"windows-x86_64.exe|zuid.exe|${HOME}/synced/0-0/common/exec/util/mswin/cli/by-self/win64"
		"darwin-universal|zuid|${HOME}/synced/0-0/common/exec/util/macos/bin"
	)
	## With no release files built, the command from zig-out goes to the first of
	## these that exists. On Linux x86_64 that's built for the release target, so
	## it can go in the synced dir too; on a Mac it's a host build.
	default_dogfoodDirs=("${HOME}/.local/bin" "${HOME}/bin")
	if [[ "$(uname -s)-$(uname -m)" == "Linux-x86_64" ]]; then
		default_dogfoodDirs=("${HOME}/synced/0-0/common/exec/util/linux/bin" "${default_dogfoodDirs[@]}")
	fi

	## Extra rar excludes for the backup, one per line, on top of the helper's generic
	## list (.zig-cache, zig/vendor, links back in etc). Old build copies under
	## private/ are left out. Trailing '/' or rar matches files only.
	default_rarExcludes="*/working/audit-*/"

	## Artifact retention, grandfather-father-son. Keep this many of each.
	default_keepDaily=7
	default_keepWeekly=5
	default_keepMonthly=6

	## --container. The image is tagged with cicd/container/Dockerfile's git hash.
	## Caches live in a named volume, out of the tree and its backups.
	## Every container, image and volume a run makes is labeled with this and
	## the run's name. Nothing without this label is ever removed.
	default_projectName="zuid"
	default_containerImage="zuid-cicd"
	default_containerVolume="zuid-cicd-cache"
	## Zig's global cache in the image gets a volume of its own, at the image's
	## ZIG_GLOBAL_CACHE_DIR.
	default_containerZigVolume="zuid-zig-cache"
	default_containerZigCache="/zig-cache"
	## Zig never trims a cache, so each of ours is emptied at the end of a run
	## when it's over this, or when the Zig named in the stamp inside isn't
	## this run's.
	default_zigCacheCapMB=2048
	default_zigCacheStamp=".cicd-zig-version"
	## --leakcheck's CodeQL, built on that image from cicd/container/codeql/.
	default_codeqlImage="zuid-codeql"

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
		Builds and tests both zuid implementations, packages the release files on a
		full run, then archives the project and publishes it.

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
		    --cross           Kept for old command lines. Every run cross-compiles the
		                      Go module now, for ${crossTargets[*]}
		    --quick           Skip the slow stages: fuzzing, profiling, the demo and
		                      packaging, plus the dogfood install. Lint, the tests,
		                      the Go cross builds and the backup still run.
		    --no-fuzz         Leave the Go and Zig fuzzing out of a full run.
		    --no-profile      Leave the profile out of a full run.
		    --no-demo         Leave the demo out, so assets/demo.gif stays as it is.
		    --no-sync         Skip the remote refresh at the start.
		    --gate              The pre-push check: --quick, with no sync, dogfood,
		                      backup, commit or push. See below.
		    -m, --message     Commit message. Implies --commit.
		    --commit          Commit if everything passed. Refuses on a protected
		                      branch: ${protectedBranches[*]}
		    --push            Push the current branch. Implies a remote exists.
		    --package         Build release artifacts into dist/, even on a quick
		                      run. A full run does anyway, where it can.
		    --no-package      Do not build them, however the run went.
		    --backup          Archive and publish. On by default, so this only undoes
		                      an earlier --no-backup.
		    --no-backup       Do not archive or publish, however the run went.
		    --dogfood         Install for daily use even on a quick run. A full run
		                      installs anyway.
		    --no-dogfood      Do not install, however the run went.
		    --publish         Publish a GitHub release of the version in
		                      zig/lib/src/core.zig. Implies --package. See below.
		    --allow-partial   Let --publish go ahead with some platforms missing.
		    --container       Run the build and test stages in the container, or fail.
		                      A run uses it anyway where docker answers. See below.
		    --no-container    Run them on this machine, docker or not.
		    --leakcheck       Add the slow leak checks. On by default, so this is for
		                      a --quick or --gate run. See below.
		    --no-leakcheck    Leave the slow leak checks out.
		    --keep-temp       Keep this run's containers, rather than removing them
		                      at the end. See below.
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

		A full run that builds the Zig side also puts the command where daily use
		finds it, so that's always the build that just passed. Each release file it
		packaged goes to its own platform's dir, if that dir exists:
		$(printf '  zuid-<version>-%s\n' "${dogfoodSynced[@]}" | sed 's/|/ -> /; s/|/ in /')
		With nothing packaged, the command from zig-out goes to the first of these
		that exists: ${dogfoodDirs[*]}
		It says so and moves on when none of them do.

		A full run packages only on Linux x86_64 and macOS, and skips it with a
		note when llvm-objcopy is missing on Linux. --package asks anyway.

		--package also runs the Linux x86_64 release under Intel's SDE, emulating a
		Core 2 Duo and a Pentium 4, when it finds one: ZUID_SDE if set, else sde64
		on PATH, else ~/.local/opt/intel-sde/sde64. Without it those 2 checks skip.

		Every run - quick or full, any branch - then archives the whole project:
		repo/, private/, the lot, into ../versions/, and publishes it, committing
		and pushing through the helper in cicd/utility/. Build caches and other
		regenerable trees are left out, so the archive is a fraction of what is on
		disk. --no-backup turns it off; so does --commit or --push, which take over
		the git half. A linked worktree skips it, since it is not the project tree.

		--publish runs only on ${releaseBranch}, with a clean tree, HEAD pushed, and no tag
		yet for the version. It uploads dist/ plus whatever is in dist-incoming/.
		That is where the Mac files go, copied from the dist/ of a --package run
		of the same commit on a Mac. Only the top level counts, and
		checksums.txt and dot files there are ignored.
		It checks that every platform has an asset, writes one checksums.txt over
		all of them, shows the plan and asks. Then it tags HEAD v<version> and
		go/v<version>, pushes both, creates the release with gh, a prerelease when
		the version has a '-', and waits for the download to answer. The notes are
		changelog.md's section for that version, if it has one, then a table of the
		downloads by OS and CPU. What was uploaded stays in dist/release/ until the
		next --package.

		staticcheck, govulncheck, and the C sanitizers and analyzers are pinned in
		the --container image below, and every run calls them from it, building it
		first when it's missing. Without docker on x86_64 Linux they skip with a
		note. govulncheck also skips when offline.

		On x86_64 Linux where docker answers, a run does preflight through package
		in a Debian image with every tool pinned, built from cicd/container/Dockerfile
		the first time it is needed. Without docker, or when the image won't build,
		it says so in one line and runs them here. --publish runs them here too.
		The sync, demo, dogfood and backup stay on this machine, since they need its
		git keys, fonts and paths. --container insists on the image and fails
		without it; --no-container stays here. ZUID_DOCKER can name another program
		that takes docker's arguments. --container doesn't go with --publish.

		Zig never trims its caches. At the end of a run that built with Zig, each
		.zig-cache in the tree, and in the image the ${containerZigVolume} volume,
		is emptied when it's over ${zigCacheCapMB} MB or was filled by another Zig.
		A stamp file in each one records which. ~/.cache/zig is shared, so it's
		left alone.

		Every container, image and volume a run makes is labeled dev.project=${projectName}
		and dev.run=<run>, and each container is named ${projectName}-<run>-<step>. At the
		end of a run, failed or interrupted too, its containers are stopped and
		removed, unless --keep-temp. A run that passed then removes the project's
		dangling images, and every tag of ${containerImage} and ${codeqlImage} but the current
		one and the one before it. Then a docker builder prune keeps the last week
		of build cache, and the ${containerVolume} volume is emptied when it's over
		${zigCacheCapMB} MB. One line says what went and about what it freed. Nothing
		without the project's label is touched.

		--leakcheck is a soak test of each side, clang's cross-file analyzer, and
		CodeQL. The soaks repeat what a caller does and fail when the heap after
		round 2N is bigger than after round N by more than a margin: the Go one on
		this machine's Go, with 2 heap profiles kept, and the C one under heaptrack
		from the image, with heaptrack's report kept. CodeQL runs on the Go module
		with the third-party Go it builds, and on the C tests, from an image of its
		own built on the main one. It's about 480 MB more, so only --leakcheck
		builds it. Its reports and the soaks' go in cicd/artifacts/leakcheck/.
		About 10 minutes. A --quick or --gate run leaves it out unless --leakcheck
		is given, and --no-leakcheck leaves it out of any run.

		With no options a run does every stage but --publish.

		--gate is what cicd/utility/git-hooks/pre-push runs before a push to main,
		on the commit being pushed, in a scratch worktree. Turn the hook on once
		per clone with: git config core.hooksPath cicd/utility/git-hooks
		SKIP_GATE=1 skips it. A run's own backup and push skip it, since that run
		just passed.

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
	local    default_releaseBranch=""
	local -a default_releaseAssets=()
	local    default_wasmtimeVer=""
	local -a default_wasmtimeSha256s=()
	local    default_freebsdRepo=""
	local -a default_freebsdPkgs=()
	local    default_reactorPackage=""
	local -a default_dogfoodSynced=()
	local -a default_dogfoodDirs=()
	local    default_rarExcludes=""
	local -i default_keepDaily=0
	local -i default_keepWeekly=0
	local -i default_keepMonthly=0
	local    default_projectName=""
	local    default_containerImage=""
	local    default_containerVolume=""
	local    default_containerZigVolume=""
	local    default_containerZigCache=""
	local -i default_zigCacheCapMB=0
	local    default_zigCacheStamp=""
	local    default_codeqlImage=""
	fConfig
	local -r minVer_Go="${default_minVer_Go}"
	local -r minVer_Zig="${default_minVer_Zig}"
	local -ra crossTargets=("${default_crossTargets[@]}")
	local -ra protectedBranches=("${default_protectedBranches[@]}")
	local -r  releaseBranch="${default_releaseBranch}"
	local -ra releaseAssets=("${default_releaseAssets[@]}")
	local -r wasmtimeVer="${default_wasmtimeVer}"
	local -ra wasmtimeSha256s=("${default_wasmtimeSha256s[@]}")
	local -r  freebsdRepo="${default_freebsdRepo}"
	local -ra freebsdPkgs=("${default_freebsdPkgs[@]}")
	local -r reactorPackage="${default_reactorPackage}"
	local -ra dogfoodSynced=("${default_dogfoodSynced[@]}")
	local -ra dogfoodDirs=("${default_dogfoodDirs[@]}")
	local -r  rarExcludes="${default_rarExcludes}"
	local -ri keepDaily="${default_keepDaily}"
	local -ri keepWeekly="${default_keepWeekly}"
	local -ri keepMonthly="${default_keepMonthly}"
	local -r  projectName="${default_projectName}"
	local -r  containerImage="${default_containerImage}"
	local -r  containerVolume="${default_containerVolume}"
	local -r  containerZigVolume="${default_containerZigVolume}"
	local -r  containerZigCache="${default_containerZigCache}"
	local -ri zigCacheCapMB="${default_zigCacheCapMB}"
	local -r  zigCacheStamp="${default_zigCacheStamp}"
	local -r  codeqlImage="${default_codeqlImage}"
	local -r  containerEngine="${ZUID_DOCKER:-docker}"
	## Set by fContainer_Image and fCodeql_Image.
	local containerTag="" codeqlTag=""

	## Layout. This script lives in the repo's cicd/, so the repo root is one up.
	## Physical, since find does not descend a symlink it is handed as a start.
	## Run through a symlinked path, the PowerShell check found nothing.
	local -r repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
	[[ -n "${repoRoot}" ]] || fThrowError "Could not resolve the repo root."  "${FUNCNAME[0]}"
	local -r goDir="${repoRoot}/go"
	local -r zigDir="${repoRoot}/zig"
	## Release files are named zuid-<version>-<platform>.
	local distPrefix=""
	distPrefix="zuid-$(fCoreVersion || true)-"
	readonly distPrefix
	local -r artifactDir="${repoRoot}/cicd/artifacts"
	local -r utilityDir="${repoRoot}/cicd/utility"
	local -r incomingDir="${repoRoot}/dist-incoming"
	local -r runStamp="$(fRunStamp)"
	## Becomes the run folder's name with 2026102416233107.
	local -r runName="${runStamp}"
	fSection_Init

	## No single stage gets the whole machine. fJobs works the counts out, here
	## and again from fSection before each step, since the load moves.
	local -i cpuCount=1 buildJobs=1 hardJobs=1 machineBusy=0
	local    loadNow=""
	fJobs
	fLowPriority

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
	local -i noPackage=0
	local    packageSkipWhy=""
	local -i doBackup=1
	local -i backupAsked=0
	local -i backupInWorktree=0
	local -i doDogfood=1
	local -i dogfoodAsked=0
	local -i doPublish=0
	local -i allowPartial=0
	local -i doContainer=0
	local    containerMode="auto"
	local    imageSkipWhy=""
	local -i doGate=0
	local -i doLeakcheck=1
	local -i leakAsked=0
	local -i doFuzz=1
	local -i doProfile=1
	local -i doDemo=1
	fInit "${@}"
	readonly onlyToolchain
	readonly doCross
	readonly doQuick
	readonly doSync
	readonly doPush
	readonly doPublish
	readonly allowPartial
	readonly containerMode
	readonly doGate
	readonly doLeakcheck
	readonly doFuzz
	readonly doProfile
	readonly doDemo

	## Set by the publish preflight, read by the publish stage.
	local publishVersion="" publishRemote="" publishHead="" publishRepoUrl=""

	## Dogfooding rides along with every full run, so that daily use is the
	## build that just passed. A quick run is mid-iteration, so it stays
	## off the path unless asked for by name.
	if ((doQuick)) && ((! dogfoodAsked)); then doDogfood=0; fi
	readonly doDogfood

	## Backing up survives a quick run - the archive is cheap next to the stages
	## quick exists to skip, and an archive nobody remembered to ask for
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

	## Inside a container the outer run already logs everything this prints.
	if ((! inContainer)); then fStartRunLog; fi

	## Plain 'if', not '&&' - a trailing false in a function trips the ERR trap.
	if ((doSync));                 then fStage_Sync;      fi
	## After the sync, which can bring a new Dockerfile.
	fContainer_Pick
	readonly doContainer doPackage packageSkipWhy imageSkipWhy
	if ((doContainer)); then
		fStage_Container
		fStage_Shell_Bash32
	else
		fPreflight
		fStage_Shell
		if ((doGo));                   then fStage_Go;        fi
		if ((doZig));                  then fStage_Zig;       fi
		if ((doCross)) && ((doGo));    then fStage_Go_Cross;  fi
		if ((doLeakcheck));            then fStage_Leakcheck; fi
		if ((doProfile));              then fStage_Profile;   fi
	fi
	## The demo draws with this machine's fonts, so a container never renders it.
	if ((doDemo)) && ((! inContainer)); then fStage_Demo; fi
	if ((doPackage)) && ((! doContainer)); then fStage_Package; fi
	if [[ -n "${packageSkipWhy}" ]]; then fEcho_Clean; fEcho_Clean "Package ....: skipped, ${packageSkipWhy}"; fi
	## After the last stage that runs Zig. With the image, the run inside does it.
	if ((doZig)) && ((! doContainer)); then fZigCache_Tidy; fi
	## Only once the run's image has passed, since older tags go then.
	fContainer_Tidy
	if ((doPublish));              then fStage_Publish;   fi
	if ((doZig)) && ((doDogfood)); then fStage_Dogfood;   fi
	if ((doBackup));               then fStage_Backup;    fi
	if ((backupInWorktree));       then fEcho_Clean; fEcho_Clean "Backup .....: skipped in a linked worktree"; fi
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
			--package)    doPackage=1; noPackage=0 ;;
			--no-package) doPackage=0; noPackage=1 ;;
			--backup)     doBackup=1; backupAsked=1 ;;
			--no-backup)  doBackup=0; backupAsked=0 ;;
			--dogfood)    doDogfood=1; dogfoodAsked=1 ;;
			--no-dogfood) doDogfood=0; dogfoodAsked=0 ;;
			--publish)    doPublish=1; doPackage=1 ;;
			--allow-partial) allowPartial=1 ;;
			--container)  doContainer=1; containerMode="on"  ;;
			--no-container) doContainer=0; containerMode="off" ;;
			--gate)         doGate=1 ;;
			--leakcheck)  doLeakcheck=1; leakAsked=1 ;;
			--no-leakcheck) doLeakcheck=0; leakAsked=1 ;;
			--no-fuzz)    doFuzz=0    ;;
			--no-profile) doProfile=0 ;;
			--no-demo)    doDemo=0    ;;
			--keep-temp)  keepTemp=1  ;;
			-q|--quiet)   doQuietly=1 ;;

			## ¯\_(:/)_/¯
			*)  fThrowError "Argument invalid or not expected in this context: '$1'."  "${FUNCNAME[0]}" ;;

		esac
		shift || true
	done

	## The pre-push hook's run. Anything that writes outside the tree, or to git,
	## would be a push inside a push.
	if ((doGate)); then
		if ((doCommit)) || ((doPush)) || ((backupAsked)) || ((doPackage)) || ((dogfoodAsked)); then
			fThrowError "--gate only builds and tests. Drop the other stage flags."  "${FUNCNAME[0]}"
		fi
		doQuick=1; doSync=0; doBackup=0; doDogfood=0; doQuietly=1
	fi

	## Leak checks are 10 minutes more, so a quick run only has them if asked.
	if ((doQuick)) && ((! leakAsked)); then doLeakcheck=0; fi
	if ((doQuick)); then doFuzz=0; doProfile=0; doDemo=0; fi

	## The Go cross builds take a few seconds each from cold, so quick runs get
	## them too. The Zig ones take about 20 s a target and come with --package.
	doCross=1

	## The backup helper does its own commit and push, so pairing it with either of
	## ours would commit the same work twice. Asked for together that is a mistake and
	## says so; with the backup merely riding along by default, the narrower git path
	## is plainly what was meant, so it wins quietly.
	if ((commitAsked)) || ((doPush)); then
		if ((backupAsked)); then
			fThrowError "--backup already commits and pushes; drop --commit and --push."  "${FUNCNAME[0]}"
		fi
		doBackup=0
	fi

	## The helper archives the folder above the checkout, which for a linked
	## worktree is not the project, and it wants a real .git directory there.
	if ((doBackup)); then
		local -r gitDir="$(git -C "${repoRoot}" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
		local -r gitCommonDir="$(git -C "${repoRoot}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
		if [[ "${gitDir}" != "${gitCommonDir}" ]]; then
			if ((backupAsked)); then
				fThrowError "--backup archives the project tree, so it runs from the main checkout, not a linked worktree."  "${FUNCNAME[0]}"
			fi
			doBackup=0
			backupInWorktree=1
		fi
	fi

	## A bare -m is not that clash - the message is what the helper commits with.
	if ((doBackup)); then doCommit=0; fi

	if ((allowPartial)) && ((! doPublish)); then
		fThrowError "--allow-partial only means something with --publish."  "${FUNCNAME[0]}"
	fi
	## Publishing needs gh and its login, which stay out of the container.
	if ((doPublish)) && ((doContainer)); then
		fThrowError "--publish runs on this machine, so it does not go with --container."  "${FUNCNAME[0]}"
	fi
	if ((doContainer)) && ((inContainer)); then
		fThrowError "Already in the container; --container would start another."  "${FUNCNAME[0]}"
	fi
	## Every release asset comes out of the Zig build.
	if ((doPublish)) && [[ "${onlyToolchain}" == "go" ]]; then
		fThrowError "--publish needs the Zig side, which builds every release asset. Drop --only go."  "${FUNCNAME[0]}"
	fi
	if ((doPublish)) && ((noPackage)); then
		fThrowError "--publish builds the release files, so it does not go with --no-package."  "${FUNCNAME[0]}"
	fi

	## A full run builds the release files too. Where it can't, it says why and
	## moves on, so a fresh clone without LLVM still passes. The container has
	## every tool.
	if ((! doQuick)) && ((! doPackage)) && ((! noPackage)) && [[ "${onlyToolchain}" != "go" ]]; then
		if ((doContainer)); then packageSkipWhy=""; else packageSkipWhy="$(fPackageBlocker)"; fi
		if [[ -z "${packageSkipWhy}" ]]; then doPackage=1; fi
	fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Why a full run can't package here, or nothing. Only the hosts --package has
## passed on: Linux x86_64 and a Mac. Asking for --package skips this.
fPackageBlocker(){
	case "$(uname -s)-$(uname -m)" in
		Linux-x86_64) ;;
		Darwin-*)     return 0 ;;
		*)            printf 'a full run packages only on Linux x86_64 and macOS (pass --package to try)'; return 0 ;;
	esac
	local tool=""
	for tool in llvm-objcopy llvm-objcopy-21 llvm-objcopy-20 llvm-objcopy-19 llvm-objcopy-18 llvm-objcopy-17 llvm-objcopy-16; do
		if command -v "${tool}" >/dev/null 2>&1; then return 0; fi
	done
	printf 'no llvm-objcopy to strip the release with'
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
## True when HEAD sits on a branch this script must not commit to. A detached
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

	fSection "Commit message"
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

	fSection "Remote sync"

	## Asks git, since a linked worktree has a .git file, not a directory.
	[[ "$(git -C "${repoRoot}" rev-parse --show-cdup 2>/dev/null || echo no)" == "" ]] || fThrowError "Not a git repo: '${repoRoot}'."  "${FUNCNAME[0]}"

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
## The pinned image where docker answers, else this machine with a note. A
## missing docker never fails a run. --container and --no-container decide
## alone, and --publish needs this machine's gh login.
fContainer_Pick(){

	if ((inContainer)); then return 0; fi
	fSection "Container"
	if [[ "${containerMode}" == "off" ]]; then fEcho_Clean "Container ..: off (--no-container), so this runs here"; return 0; fi
	if [[ "${containerMode}" == "on" ]];  then return 0; fi

	local why=""
	if   ((doPublish));                                                 then why="--publish runs on this machine"
	elif [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]];             then why="the image is Linux x86_64 only"
	elif [[ -z "$(command -v "${containerEngine}" 2>/dev/null || true)" ]]; then why="no ${containerEngine}"
	elif ! "${containerEngine}" info >/dev/null 2>&1;                   then why="${containerEngine} isn't answering"
	## The checkers would only try the same build again.
	elif ! fContainer_Image soft;                                       then why="the image didn't build"; imageSkipWhy="${why}"
	fi
	if [[ -n "${why}" ]]; then fEcho_Clean "Container ..: not used, ${why}, so this runs here"; return 0; fi

	doContainer=1
	## The image has every tool packaging needs.
	if [[ -n "${packageSkipWhy}" ]]; then packageSkipWhy=""; doPackage=1; fi

}


## Preflight through package, run inside the pinned image, then back here for
## whatever needs this machine. The repo is mounted at the same path inside,
## so paths in logs and caches, and a worktree's .git file, still point at
## something.
fStage_Container(){

	## fContainer_Pick has the tag already, unless --container asked.
	if [[ -z "${containerTag}" ]]; then fContainer_Image; fi
	## The run inside can't start another container, so CodeQL's image is the
	## one it runs in. It's the main image with CodeQL added.
	local runTag="${containerTag}"
	if ((doLeakcheck)); then fCodeql_Image; runTag="${codeqlTag}"; fi

	local -a runArgs=()
	fContainer_RunArgs runArgs container "${buildJobs}"

	local -a innerEnv=(-e ZUID_IN_CONTAINER=1 -e "USER=${USER:-builder}" -e "ZUID_RUN_STAMP=${runStamp}" -e "ZUID_COLUMNS=${_sectionWidth}")
	if [[ -n "${SOURCE_DATE_EPOCH+set}" ]]; then innerEnv+=(-e "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"); fi
	## SDE is a kit on this machine, not in the image, so it goes in where it is.
	local sde=""
	if ((doPackage)); then sde="$(fFindSde)"; fi
	if [[ -n "${sde}" ]]; then sde="$(readlink -f "${sde}" || true)"; fi
	if [[ -x "${sde}" ]]; then
		innerEnv+=(-e "ZUID_SDE=${sde}")
		if [[ "${sde}" != "${repoRoot}/"* ]]; then runArgs+=(-v "${sde%/*}:${sde%/*}:ro"); fi
	fi
	## The pre-push hook's worktree shares the checkout's Zig cache.
	if [[ "${ZIG_LOCAL_CACHE_DIR:-}" == /* ]] && [[ -d "${ZIG_LOCAL_CACHE_DIR}" ]]; then
		innerEnv+=(-e "ZIG_LOCAL_CACHE_DIR=${ZIG_LOCAL_CACHE_DIR}")
		if [[ "${ZIG_LOCAL_CACHE_DIR}" != "${repoRoot}/"* ]]; then runArgs+=(-v "${ZIG_LOCAL_CACHE_DIR}:${ZIG_LOCAL_CACHE_DIR}"); fi
	fi

	local -a innerArgs=(-q --no-sync --no-backup --no-dogfood)
	if [[ -n "${onlyToolchain}" ]]; then innerArgs+=(--only "${onlyToolchain}"); fi
	if ((doQuick));   then innerArgs+=(--quick);   fi
	if ((doPackage)); then innerArgs+=(--package); fi
	if ((doLeakcheck)); then innerArgs+=(--leakcheck); else innerArgs+=(--no-leakcheck); fi
	## --quick already says these. The demo stays out here anyway.
	if ((! doQuick)) && ((! doFuzz));    then innerArgs+=(--no-fuzz);    fi
	if ((! doQuick)) && ((! doProfile)); then innerArgs+=(--no-profile); fi
	if ((keepTemp)); then innerArgs+=(--keep-temp); fi
	fEcho_Clean "Runs .......: cicd.bash ${innerArgs[*]}"

	"${containerEngine}" run "${runArgs[@]}" "${innerEnv[@]}" -w "${repoRoot}" \
		"${runTag}" nice -n 19 bash "${repoRoot}/cicd/cicd.bash" "${innerArgs[@]}" \
		|| fThrowError "The run in the container failed; its output is above."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Sets containerTag, building the image first if it isn't there yet. With
## "soft", a failed build returns 1 rather than stopping the run.
fContainer_Image(){  ## [soft]

	_fMustBeInPath "${containerEngine}"
	local -r recipe="${repoRoot}/cicd/container/Dockerfile"
	[[ -f "${recipe}" ]] || fThrowError "Missing the container recipe: '${recipe}'."  "${FUNCNAME[0]}"

	## Tagged by the recipe's hash, so an edited recipe can't run on the old image.
	containerTag="${containerImage}:$(git hash-object "${recipe}" | cut -c1-12)"
	if "${containerEngine}" image inspect "${containerTag}" &>/dev/null; then
		fEcho_Clean "Image ......: ${containerTag}"
	else
		fEcho_Clean "Image ......: building ${containerTag}"
		if ! "${containerEngine}" build --label "dev.project=${projectName}" --label "dev.run=${runName}" -t "${containerTag}" "$(dirname "${recipe}")"; then
			if [[ "${1:-}" == "soft" ]]; then fEcho_Clean "Image ......: ${containerTag} didn't build"; containerTag=""; return 1; fi
			fThrowError "Could not build '${containerTag}'."  "${FUNCNAME[0]}"
		fi
	fi
	## Older tags wait for fContainer_Tidy, once this one has passed.
	if [[ -z "${_dockerRun}" ]]; then
		fContainer_Volumes
		_dockerEngine="${containerEngine}" _dockerProject="${projectName}" _dockerRun="${runName}" _dockerPid="${BASHPID}"
	fi

}


## Sets codeqlTag, building CodeQL's image on the main one if it isn't there
## yet. Only --leakcheck wants it, so a plain run never pulls the bundle.
## Needs containerTag set.
fCodeql_Image(){

	local -r recipe="${repoRoot}/cicd/container/codeql/Dockerfile"
	[[ -f "${recipe}" ]] || fThrowError "Missing CodeQL's container recipe: '${recipe}'."  "${FUNCNAME[0]}"

	codeqlTag="$(fCodeql_Tag)"
	if "${containerEngine}" image inspect "${codeqlTag}" &>/dev/null; then
		fEcho_Clean "CodeQL .....: ${codeqlTag}"
		return 0
	fi
	fEcho_Clean "CodeQL .....: building ${codeqlTag}"
	"${containerEngine}" build --build-arg "BASE=${containerTag}" --label "dev.project=${projectName}" --label "dev.run=${runName}" \
		-t "${codeqlTag}" "$(dirname "${recipe}")" \
		|| fThrowError "Could not build '${codeqlTag}'."  "${FUNCNAME[0]}"

}

## A new main image means a new CodeQL one, so both hashes are in the tag.
fCodeql_Tag(){ printf '%s:%s-%s\n' "${codeqlImage}" "$(git hash-object "${repoRoot}/cicd/container/codeql/Dockerfile" | cut -c1-12)" "${containerTag##*:}" ;}


## docker makes a missing volume on first use, with no labels, so ours are
## made first.
fContainer_Volumes(){
	local vol=""
	for vol in "${containerVolume}" "${containerZigVolume}"; do
		if "${containerEngine}" volume inspect "${vol}" &>/dev/null; then continue; fi
		"${containerEngine}" volume create --label "dev.project=${projectName}" --label "dev.run=${runName}" "${vol}" >/dev/null \
			|| fEcho_Clean "Volume .....: couldn't make ${vol}, so docker makes it unlabeled"
	done
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The repo at its own path as the caller's uid, the cache volumes, and a
## linked worktree's main .git. Named and labeled for the run, so its end
## finds what's left. Held to the step's job count, which goes in too, as the
## count to use and as a cap for a run of this script inside.
fContainer_RunArgs(){  ## array to fill, step, jobs
	local -n runArgs_k4w="$1"
	local -r jobs_k4w="${3:?}"
	runArgs_k4w=()
	if ((! keepTemp)); then runArgs_k4w+=(--rm); fi
	runArgs_k4w+=(--init --user "$(id -u):$(id -g)" -v "${repoRoot}:${repoRoot}" -v "${containerVolume}:/cache" -v "${containerZigVolume}:${containerZigCache}")
	runArgs_k4w+=(--name "${projectName}-${runName}-${2:?}" --label "dev.project=${projectName}" --label "dev.run=${runName}")
	runArgs_k4w+=(--cpus "${jobs_k4w}" --cpu-shares 256 -e "ZUID_JOBS=${jobs_k4w}" -e "ZUID_JOBS_CAP=${jobs_k4w}")
	local -r gitCommon="$(git -C "${repoRoot}" rev-parse --path-format=absolute --git-common-dir)"
	if [[ "${gitCommon}" != "${repoRoot}/"* ]]; then runArgs_k4w+=(-v "${gitCommon}:${gitCommon}"); fi
	## A Zig cache linked off the snapshotted dataset points at nothing inside,
	## and Zig stops on NotDir.
	local -r zigCacheLink="${repoRoot}/zig/.zig-cache"
	local zigCacheReal=""
	if [[ -L "${zigCacheLink}" ]]; then zigCacheReal="$(readlink -f "${zigCacheLink}" || true)"; fi
	if [[ -d "${zigCacheReal}" && "${zigCacheReal}" != "${repoRoot}/"* ]]; then runArgs_k4w+=(-v "${zigCacheReal}:${zigCacheReal}"); fi
}


## The run's own containers, by label. --rm takes them on a clean exit, so
## this is for a failed or interrupted one, or --keep-temp's. Called from the
## exit trap too, after fMain's locals are gone, so it reads only globals.
fContainer_StopRun(){
	## Not from a $(...)'s ERR trap, while the run goes on.
	if [[ -z "${_dockerRun}" || "${BASHPID}" != "${_dockerPid}" ]]; then return 0; fi
	local -a ids=()
	mapfile -t ids < <("${_dockerEngine}" ps -aq --filter "label=dev.project=${_dockerProject}" --filter "label=dev.run=${_dockerRun}" 2>/dev/null || true)
	if ((${#ids[@]} == 0)) || [[ -z "${ids[0]}" ]]; then return 0; fi
	if ((keepTemp)); then
		fEcho_Clean "Docker .....: kept ${#ids[@]} container(s), labeled dev.run=${_dockerRun} (--keep-temp)"
		return 0
	fi
	"${_dockerEngine}" stop -t 10 "${ids[@]}" >/dev/null 2>&1 || true
	## One run with --rm is already gone once it stops.
	"${_dockerEngine}" rm "${ids[@]}" >/dev/null 2>&1 || true
	_dockerGone+=("${#ids[@]} container(s)")
}


## The end of a run that passed: its containers, the project's dangling images,
## older tags, a week of build cache kept, and the cache volume's cap. Only
## what has the project's label, and a plain rmi, so one in use stays.
fContainer_Tidy(){
	if [[ -z "${_dockerRun}" ]]; then return 0; fi
	local -r before="$(fDocker_Bytes)"
	_dockerGone=()
	fContainer_StopRun
	## CodeQL's first, since each holds the layers of the main one under it.
	fContainer_DropOlder "${codeqlImage}" "$(fCodeql_Tag)"
	fContainer_DropOlder "${containerImage}" "${containerTag}"
	local -a ids=()
	mapfile -t ids < <("${containerEngine}" images -q --filter dangling=true --filter "label=dev.project=${projectName}" 2>/dev/null || true)
	if ((${#ids[@]})) && [[ -n "${ids[0]}" ]] && "${containerEngine}" rmi "${ids[@]}" >/dev/null 2>&1; then _dockerGone+=("${#ids[@]} dangling image(s)"); fi
	"${containerEngine}" builder prune -f --filter until=168h >/dev/null 2>&1 || true
	fContainer_VolumeCap
	local -r after="$(fDocker_Bytes)"
	local freed="an unknown amount freed, since docker system df didn't answer" gone=""
	if ((${#_dockerGone[@]})); then printf -v gone '%s, ' "${_dockerGone[@]}"; fi
	if [[ -n "${before}" && -n "${after}" ]]; then
		freed="about $(awk -v b="${before}" -v a="${after}" 'BEGIN { d = b - a; if (d < 0) d = 0; printf "%.1f GB", d / 1e9 }') freed"
	fi
	fEcho_Clean
	fEcho_Clean "Docker .....: removed ${gone}build cache over a week old; ${freed}"
	## Done, so the exit trap has nothing to ask.
	_dockerRun="" _dockerGone=()
}


## Keeps the current tag and the newest other one, which is the last to pass
## before it.
fContainer_DropOlder(){  ## image, current tag
	local -r image="$1" current="$2"
	local ref="" line=""
	local -i kept=0
	while IFS= read -r line; do
		ref="${line##*$'\t'}"
		if [[ -z "${ref}" || "${ref}" == "${current}" || "${ref}" == *"<none>"* ]]; then continue; fi
		if ((kept == 0)); then kept=1; continue; fi
		if "${containerEngine}" rmi "${ref}" >/dev/null 2>&1; then _dockerGone+=("${ref}"); fi
	done < <("${containerEngine}" image ls "${image}" --filter "label=dev.project=${projectName}" --format '{{.CreatedAt}}'$'\t''{{.Repository}}:{{.Tag}}' 2>/dev/null | sort -r || true)
}


## The cache volume is emptied when it's over the cap, the same rule as the
## Zig caches. From inside, since only there can its size be read. Everything
## the runs wrote goes; the image's own root-owned folders stay. Go's module
## cache is read-only, hence the chmod.
fContainer_VolumeCap(){
	local label="" out=""
	label="$("${containerEngine}" volume inspect --format '{{index .Labels "dev.project"}}' "${containerVolume}" 2>/dev/null || true)"
	if [[ "${label}" != "${projectName}" || -z "${containerTag}" ]]; then return 0; fi
	local -a runArgs=(--init --user "$(id -u):$(id -g)" -v "${containerVolume}:/cache" --name "${projectName}-${runName}-cache-cap" --label "dev.project=${projectName}" --label "dev.run=${runName}")
	if ((! keepTemp)); then runArgs=(--rm "${runArgs[@]}"); fi
	runArgs+=(--cpus 1 --cpu-shares 256)
	# shellcheck disable=2016  ## Expanded inside.
	out="$("${containerEngine}" run "${runArgs[@]}" "${containerTag}" nice -n 19 sh -c '
		kb="$(du -sk /cache | cut -f1)"
		if [ "${kb}" -gt "$1" ]; then chmod -R u+w /cache 2>/dev/null; find /cache -xdev -mindepth 1 -user "$(id -u)" -delete; echo "emptied ${kb}"; fi
	' sh "$((zigCacheCapMB * 1024))" 2>/dev/null || true)"
	if [[ "${out}" == "emptied "* ]]; then _dockerGone+=("${containerVolume}'s contents, $((${out#emptied } / 1024)) MB"); fi
}


## Total bytes docker reports, or nothing when it doesn't answer. Shared
## layers count once, which is why the freed figure comes from this and not
## from what was removed. One call has come back empty, cause not found
## (2026102416233101).
fDocker_Bytes(){
	local sizes=""
	sizes="$("${containerEngine}" system df --format '{{.Size}}' 2>/dev/null)" || return 0
	if [[ -z "${sizes}" ]]; then return 0; fi
	awk '
		{ n = $1 + 0; u = $1; sub(/^[0-9.]+/, "", u); u = toupper(u)
		  m = (u == "KB") ? 1e3 : (u == "MB") ? 1e6 : (u == "GB") ? 1e9 : (u == "TB") ? 1e12 : 1
		  t += n * m }
		END { printf "%.0f\n", t }' <<< "${sizes}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fPreflight(){

	fSection "Preflight"

	## Asks git, since a linked worktree has a .git file, not a directory.
	[[ "$(git -C "${repoRoot}" rev-parse --show-cdup 2>/dev/null || echo no)" == "" ]] || fThrowError "Not a git repo: '${repoRoot}'."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	fEcho_Clean "Branch .....: ${branch}"
	if [[ -n "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		fEcho_Clean "Tree .......: uncommitted changes present"
	fi
	fJobs_Line
	local niceNow="" ioNow=""
	niceNow="$(ps -o nice= -p "$$" 2>/dev/null || true)"
	if command -v ionice &>/dev/null; then ioNow="$(ionice -p "$$" 2>/dev/null || true)"; fi
	fEcho_Clean "Priority ...: nice ${niceNow// /}${ioNow:+, IO ${ioNow%%:*}}"

	if ((doGo)); then
		_fMustBeInPath go
		local -r haveVer_Go="$(go version | awk '{print $3}' | sed 's/^go//')"
		fVersion_AtLeast "${haveVer_Go}" "${minVer_Go}" || fThrowError "Go ${minVer_Go} or newer required, found '${haveVer_Go}'."  "${FUNCNAME[0]}"
		fEcho_Clean "Go .........: ${haveVer_Go}"
	fi

	if ((doZig)); then
		fFindZig "${minVer_Zig}"
		fEcho_Clean "Zig ........: $(zig version) ($(readlink -f "$(command -v zig)"))"
		fDropBadEpoch
	fi

	[[ -f "${repoRoot}/testdata/vectors.tsv" ]] || fThrowError "Missing the shared test vectors: 'testdata/vectors.tsv'."  "${FUNCNAME[0]}"

	if ((doPublish)); then fPublish_Preflight; fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every test prints one line with its ID, the way the harnesses do. A check
## here starts with fId and ends in one of the three below. A check run once
## per item has an ID for each, picked by a key:
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

	fSection "Bash: lint"

	## shellcheck's warnings change between versions, so a host on another one
	## can pass what the container fails. Before the lint, which stops the run
	## on a warning. Not fatal, the same as nfpm's.
	fId EtB4gns "host shellcheck matches the pin"
	local pinned="" have=""
	pinned="$(sed -n 's/^ARG SC_VER=//p' "${repoRoot}/cicd/container/Dockerfile" || true)"
	if [[ -z "$(command -v shellcheck 2>/dev/null || true)" ]]; then
		fTestSkip "no shellcheck"
	else
		have="$(shellcheck --version 2>/dev/null | awk '$1 == "version:" { print $2; exit }' || true)"
		if [[ -z "${pinned}" ]]; then fTestFail "no ARG SC_VER in cicd/container/Dockerfile"; fi
		if [[ "${have}" != "${pinned}" ]]
			then fTestSkip "shellcheck ${have:-of unknown version} here, and the container pins ${pinned}, so its warnings can differ"
			else fTestPass
		fi
	fi

	## Not a toolchain, so a missing shellcheck is a gap in coverage, not a failure.
	## It used to return here and take the stages below down with it.
	if [[ -z "$(command -v shellcheck 2>/dev/null || true)" ]]; then
		fEcho_Clean "shellcheck not installed - skipping."
	else
		## Only what this project wrote. x9muid1 under utility/ is 2023 reference
		## code, and the copied helpers keep their own upstream's lint state.
		shellcheck "${repoRoot}/cicd/cicd.bash" "${repoRoot}/install.bash" \
			"${utilityDir}/installer-test.bash" "${utilityDir}/cli-test.bash" \
			"${utilityDir}/pipeline-test.bash" "${utilityDir}/package.bash" \
			"${utilityDir}/c-checks.bash" "${utilityDir}/git-hooks/pre-push"
		fEcho_Clean "Clean."
	fi

	fStage_Shell_PowerShell
	fStage_TestIds
	fStage_Shell_Pipeline
	fStage_Shell_Installers
	fStage_Docs
	fContentScrub

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## PSScriptAnalyzer's default rules on every tracked PowerShell file. It's
## pinned in the image, like the Go checkers, so with no docker it skips.
## installer-test.bash checks install.ps1 against Windows PowerShell 5.1 too.
fStage_Shell_PowerShell(){

	fSection "PowerShell: lint"

	local checkerSkipWhy=""
	fGoCheckers_Ready

	local -a psFiles=()
	mapfile -t psFiles < <(git -C "${repoRoot}" ls-files --full-name '*.ps1' '*.psm1' '*.psd1' | sed "s|^|${repoRoot}/|")

	fId EtB6KVF "PSScriptAnalyzer on our PowerShell"
	if [[ -n "${checkerSkipWhy}" ]]; then fTestSkip "${checkerSkipWhy}"; return 0; fi
	if ((${#psFiles[@]} == 0)); then fTestFail "git ls-files found no PowerShell files, so this would lint nothing."; fi
	local fileList=""
	printf -v fileList '%s\n' "${psFiles[@]}"
	## A missing file throws, which fails it too.
	# shellcheck disable=2016  ## PowerShell's own variables.
	fInImage "${repoRoot}" env "ZUID_PS_FILES=${fileList%$'\n'}" pwsh -NoProfile -NonInteractive -Command '
		$ErrorActionPreference = "Stop"
		if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) { "PSScriptAnalyzer is not installed."; exit 2 }
		$found = @(foreach ($file in ($env:ZUID_PS_FILES -split "`n")) { Invoke-ScriptAnalyzer -Path $file })
		foreach ($finding in $found) { "{0}:{1}: {2}: {3}" -f $finding.ScriptPath, $finding.Line, $finding.RuleName, $finding.Message }
		if ($found.Count) { exit 1 }' \
		|| fTestFail "PSScriptAnalyzer found something, or couldn't run. What it said is above."
	fTestPass

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The scrub lives with the private project files. A clone without them, or a
## worktree, skips it.
fContentScrub(){
	local -r scrub="${repoRoot}/../private/hooks/scrub.bash"
	[[ -x "${scrub}" ]] || return 0
	fSection "Content scrub"
	"${scrub}" "${repoRoot}" || fThrowError "The content scrub found something."  "${FUNCNAME[0]}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every test has an ID, and no two share one. A test added without one fails
## here rather than printing a line nobody can refer to.
fStage_TestIds(){

	fSection "Test IDs"

	if [[ -z "$(command -v python3 2>/dev/null || true)" ]]; then
		fEcho_Clean "Skipped ....: python3 not installed."
		return 0
	fi
	python3 "${utilityDir}/test-ids.py" check || fThrowError "Some tests have no ID, share one, or have one nothing checks. 'cicd/utility/test-ids.py new' makes one."  "${FUNCNAME[0]}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## A number written in front of a list drifts the moment the list grows, and no
## linter counts. design.md said "four things" above five bullets.
fStage_Docs(){

	fSection "Docs: claims that can be counted"

	## Both style guides were written and then pointed at from two places. A
	## guide nothing links to is one nobody reads, which is how the CLI one came
	## to be missing in the first place.
	fId EqA4qmO "style guides linked from both docs"
	local guide="" from=""
	for from in development.md contributing.md; do
		for guide in style_guide.md style-guide_cli.md; do
			grep -q "(${guide})" "${repoRoot}/${from}" \
				|| fTestFail "${from} does not link ${guide}."
		done
	done
	fTestPass

	## And every relative link in the root documents goes somewhere.
	fId EqA4qmP "root doc links resolve"
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
	fId ErOj0WT "licenses match license.md"
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
	fId ErOj0WU "one contact address everywhere"
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

	## Windows PowerShell reads a file with no byte-order mark in the local code
	## page, where some UTF-8 bytes turn into quote marks, and irm keeps a mark
	## that then breaks the README's one-line install. Plain ASCII avoids both.
	fId ErmS0zI "PowerShell is plain ASCII"
	local psFile="" psBad=""
	local -i psCount=0
	while IFS= read -r psFile; do
		psCount=$((psCount + 1))
		if [[ -n "$(LC_ALL=C tr -d '\000-\177' < "${psFile}")" ]]; then psBad+=" ${psFile#"${repoRoot}/"}"; fi
	done < <(find "${repoRoot}" -name '*.ps1' -not -path '*/.git/*' -not -path '*/.zig-cache/*' -not -path '*/vendor/*' | sort)
	((psCount > 0)) || fTestFail "found no .ps1 files, so this checked nothing."
	[[ -z "${psBad}" ]] || fTestFail "not ASCII:${psBad}."
	fTestPass

	fId Eq9ofeq "design.md rejection count"
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

	fSection "Pipeline"

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

	fSection "Installers"

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


## bash:3.2 is an image on this machine, which the run in the container can't
## start, so it skips these and they run here after it.
fStage_Shell_Bash32(){

	fSection "Installers: bash 3.2"

	local -r runner="${utilityDir}/installer-test.bash"
	if [[ ! -f "${runner}" ]] || [[ -z "$(command -v python3 2>/dev/null || true)" ]]; then
		fEcho_Clean "Skipped ....: needs installer-test.bash and python3 here."
		return 0
	fi

	bash "${runner}" --only bash32

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Go(){

	fSection "Go: build, vet, format, test"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	## convertbase comes from its published release, never a local checkout. The
	## reactor wasm is built from that same pin, which is what keeps the two
	## sides on one library version, and a replace directive would split them.
	fId ErOj0WV "convertbase pinned to a release"
	if grep -qE '^[[:space:]]*replace' go.mod; then
		fTestFail "go.mod has a replace directive."
	fi
	if ! grep -qE '^[[:space:]]*(require[[:space:]]+)?github\.com/jim-collier/convert-base-v2/lib v[0-9]+\.[0-9]+\.[0-9]+$' go.mod; then
		fTestFail "go.mod does not require convert-base-v2/lib at a tagged version: $(grep convert-base go.mod || true)"
	fi
	fTestPass

	go build -p "${buildJobs}" ./...

	## gofmt is silent on success and lists offenders on failure, so it needs the
	## test. Its own exit code is checked too - a missing gofmt would otherwise
	## report an empty list and pass.
	local unformatted=""
	unformatted="$(gofmt -l . 2>&1)" || fThrowError "gofmt failed: ${unformatted}"  "${FUNCNAME[0]}"
	if [[ -n "${unformatted}" ]]; then
		fThrowError "gofmt would rewrite: ${unformatted//$'\n'/, }"  "${FUNCNAME[0]}"
	fi

	## Each package's TestMain fails the run on a goroutine left behind. A
	## package without one would let that through unseen.
	fId Et9R2xV "goleak in every Go package"
	local pkgDir="" noLeakCheck=""
	local -i pkgCount=0
	while IFS= read -r pkgDir; do
		if [[ -z "${pkgDir}" ]]; then continue; fi
		pkgCount=$((pkgCount + 1))
		grep -qF 'goleak.VerifyTestMain(' "${pkgDir}"/*_test.go || noLeakCheck+=" ${pkgDir#"${goDir}/"}"
	done < <(go list -f '{{if or .TestGoFiles .XTestGoFiles}}{{.Dir}}{{end}}' ./...)
	if ((pkgCount == 0)); then fTestFail "go list found no Go package with tests."; fi
	if [[ -n "${noLeakCheck}" ]]; then fTestFail "no goleak.VerifyTestMain in the tests of:${noLeakCheck}"; fi
	fTestPass

	## The race detector is the only thing defending the documented promise that
	## Generate is safe to call concurrently. It costs about 6 s, so quick runs
	## keep it. It needs cgo, which the module itself doesn't. -count=1 since a
	## cached pass would skip goleak and the race detector both. The JSON stream
	## is what gives one line per test, with its ID.
	## The race detector's memory makes it a hard step.
	local -a testFlags=(-count=1)
	local raceSkipWhy=""
	if [[ "$(go env CGO_ENABLED)" == "1" ]]
		then testFlags+=(-race -p "${hardJobs}")
		else testFlags+=(-p "${buildJobs}"); raceSkipWhy="cgo is off here, and -race needs it"
	fi
	if [[ -n "$(command -v python3 2>/dev/null || true)" ]]; then
		go test "${testFlags[@]}" -json ./... | python3 "${utilityDir}/test-ids.py" go
	else
		fEcho_Clean "IDs ........: skipped, no python3"
		go test "${testFlags[@]}" ./...
	fi
	fId Et9R2xW "Go tests ran with -race"
	if [[ -n "${raceSkipWhy}" ]]; then fTestSkip "${raceSkipWhy}"; else fTestPass; fi

	## The module promises it needs no cgo, which is what keeps a static cross
	## build possible. fStage_Go_Cross checks the other targets.
	fId ErOgfbn "builds with cgo off"
	CGO_ENABLED=0 go build -p "${buildJobs}" ./... || fTestFail "the Go module needs cgo."
	fTestPass

	fStage_Go_Checks
	fStage_Go_Consumer
	if ((doFuzz)); then fStage_Go_Fuzz; fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Correctness checks on the module and on the third-party code it brings
## along. Third-party packages get vet and staticcheck's own bug checks, not its
## style ones, since their style isn't ours to fix. staticcheck and govulncheck
## are pinned in the container image and run from there, never from the host.
## Each takes a second or two warm, so quick runs keep them.
fStage_Go_Checks(){

	fSection "Go: vet, staticcheck, govulncheck"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	## What a user of the module builds, so not goleak, which only the tests use.
	local -a thirdParty=()
	mapfile -t thirdParty < <(go list -deps -f '{{with .Module}}{{if not .Main}}{{$.ImportPath}}{{end}}{{end}}' ./... | sort -u)

	fId Et9R2xX "go vet passes"
	go vet ./... || fTestFail "go vet found something in the module."
	fTestPass

	fId Et9R2xY "go vet on dependencies"
	if ((${#thirdParty[@]} == 0)); then fTestFail "go list found no third-party packages, so this would vet nothing."; fi
	go vet "${thirdParty[@]}" || fTestFail "go vet found something in: ${thirdParty[*]}"
	fTestPass

	local checkerSkipWhy=""
	fGoCheckers_Ready

	fId Et9R2xZ "staticcheck passes"
	if [[ -n "${checkerSkipWhy}" ]]; then
		fTestSkip "${checkerSkipWhy}"
	else
		fInImage "${goDir}" staticcheck ./... || fTestFail "staticcheck found something in the module."
		fTestPass
	fi

	fId Et9R2xa "staticcheck bug checks on dependencies"
	if [[ -n "${checkerSkipWhy}" ]]; then
		fTestSkip "${checkerSkipWhy}"
	else
		fInImage "${goDir}" staticcheck -tests=false -checks 'SA*' "${thirdParty[@]}" || fTestFail "staticcheck found something in: ${thirdParty[*]}"
		fTestPass
	fi

	## The reactor is scanned as the wasm it ships as, since its files are
	## wasip1 only.
	fId Et9R2xb "govulncheck finds no advisory"
	if [[ -n "${checkerSkipWhy}" ]]; then fTestSkip "${checkerSkipWhy}"; return 0; fi
	if [[ -z "$(command -v python3 2>/dev/null || true)" ]]; then fTestSkip "no python3 to read its report"; return 0; fi
	local report="" reactorReport="" rc=0
	report="$(fInImage "${goDir}" govulncheck -format json ./...)" && rc=0 || rc=$?
	if ((rc == 0)); then
		reactorReport="$(fInImage "${goDir}" env GOOS=wasip1 GOARCH=wasm govulncheck -format json "${reactorPackage}")" && rc=0 || rc=$?
	fi
	if ((rc != 0)); then
		## Same network as govulncheck had, so a failed probe means offline.
		if ! fInImage "${goDir}" curl -fsS -m 10 -o /dev/null https://vuln.go.dev/index/db.json 2>/dev/null; then
			fTestSkip "offline, no answer from vuln.go.dev"
			return 0
		fi
		fTestFail "govulncheck exited ${rc}. What it said is above."
	fi
	python3 "${utilityDir}/vuln-report.py" <<< "${report}${reactorReport}" || fTestFail "govulncheck knows of an advisory, listed above. One in Go's library wants GO_VER in cicd/container/Dockerfile bumped."
	fTestPass

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Sets checkerSkipWhy when the image's tools can't run here. Builds the image
## when it's missing, so the first run after a Dockerfile edit takes minutes.
## The C checks use it too.
fGoCheckers_Ready(){
	checkerSkipWhy=""
	if ((inContainer)); then return 0; fi
	if [[ -n "${imageSkipWhy:-}" ]]; then checkerSkipWhy="${imageSkipWhy}"; return 0; fi
	if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then checkerSkipWhy="the checkers' image is Linux x86_64 only"; return 0; fi
	if [[ -z "$(command -v "${containerEngine}" 2>/dev/null || true)" ]]; then checkerSkipWhy="no ${containerEngine} to run the pinned checkers in"; return 0; fi
	if ! "${containerEngine}" info >/dev/null 2>&1; then checkerSkipWhy="${containerEngine} isn't answering"; return 0; fi
	fContainer_Image
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## One of the image's pinned tools, run in a folder. Inside the container
## that's a plain call. A folder outside the repo, such as a scratch dir, is
## mounted at its own path too.
## A hard step sets imageJobs to hardJobs first.
fInImage(){  ## folder, command...
	local -r dir="$1"; shift
	local -ri jobs="${imageJobs:-${buildJobs:?}}"
	if ((inContainer)); then
		(cd "${dir}" && export ZUID_JOBS="${jobs}" && "$@")
		return
	fi
	## Named for the stage that asked, and numbered, since --keep-temp keeps
	## each one. A count bumped in a $(...) is lost, so there the pid helps.
	local step="${FUNCNAME[1]:-image}"
	if [[ "${step}" == "fCCheck" ]]; then step="${FUNCNAME[2]:-image}"; fi
	step="${step#fStage_}"; step="${step#f}"; step="${step,,}"; step="${step//_/-}"
	_dockerSteps=$((_dockerSteps + 1)); step+="-${_dockerSteps}"
	if [[ "${BASHPID}" != "${_dockerPid}" ]]; then step+="-${BASHPID}"; fi
	local -a runArgs=()
	fContainer_RunArgs runArgs "${step}" "${jobs}"
	if [[ "${dir}" != "${repoRoot}" && "${dir}" != "${repoRoot}/"* ]]; then runArgs+=(-v "${dir}:${dir}"); fi
	## The image has no ionice.
	"${containerEngine}" run "${runArgs[@]}" -w "${dir}" "${containerTag}" nice -n 19 "$@"
}


## A program that imports the module, built the way somebody following README
## would. Its own tests import by relative package path and so prove nothing
## about that.
fStage_Go_Consumer(){

	fSection "Go: a consumer of the module"

	## The docs' command has to name the package, not the module root. On the root
	## go get adds the module without what its package needs, and the build stops
	## on a missing go.sum entry for convertbase.
	fId Eq9m0j2 "go get path in the docs"
	local readme=""
	for readme in "${repoRoot}"/*.md; do
		if grep -q 'go get github.com/jim-collier/zuid/go$' "${readme}"; then
			fTestFail "$(basename "${readme}") tells people 'go get <module root>', which leaves the build unable to resolve convertbase. It should name the package."
		fi
	done
	grep -qF 'go get github.com/jim-collier/zuid/go/zuid' "${repoRoot}/install.md" 2>/dev/null \
		|| fTestFail "install.md has no go get line for the package."
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
	fId Eq9m0j3 "importing the module works"
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
## fuzz tests, which fStage_Zig_Fuzz runs in fuzz mode.
fStage_Go_Fuzz(){

	fSection "Go: fuzz"

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
		if output="$(go test -p "${hardJobs}" -run=xxx -fuzz=FuzzGenerate -fuzztime="${fuzzTime}" -parallel="${hardJobs}" ./zuid 2>&1)"; then
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

	fSection "Go: cross-compile"

	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"

	## Module only, so there is no binary to emit - this is a compile check per target.
	local target="" goos="" goarch=""
	for target in "${crossTargets[@]}"; do
		goos="${target%%/*}"
		goarch="${target##*/}"
		fId "${target}" linux/arm64=EloMht2 windows/amd64=EloMht3 darwin/arm64=EloMht4 "${target} build, cgo off"
		CGO_ENABLED=0 GOOS="${goos}" GOARCH="${goarch}" go build -p "${buildJobs}" ./... || fTestFail "${target} does not build."
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Sets goToolchain. The reactor ships inside the command, Go's library and
## all, so it's built with the Go the image pins, which is the one govulncheck
## scanned. GOTOOLCHAIN fetches it when the host's is another version. One set
## by hand wins, but not for a release. auto is Go's default, so not by hand.
fReactor_Toolchain(){
	local -r pin="$(sed -n 's/^ARG GO_VER=//p' "${repoRoot}/cicd/container/Dockerfile")"
	[[ -n "${pin}" ]] || fThrowError "No GO_VER in cicd/container/Dockerfile."  "${FUNCNAME[0]}"
	local handSet="${GOTOOLCHAIN:-}"
	[[ "${handSet}" != "auto" ]] || handSet=""
	goToolchain="${handSet:-go${pin}}"
	fId Et9luGN "reactor wasm built with the pinned Go"
	local used=""
	if ! used="$(GOTOOLCHAIN="${goToolchain}" go env GOVERSION 2>&1)"; then
		((! doPackage)) || fTestFail "Could not get ${goToolchain} for a release: ${used}"
		fTestSkip "could not get ${goToolchain}: ${used##*$'\n'}"
	elif [[ "${used}" == "go${pin}" ]]; then
		fTestPass
	elif [[ -n "${handSet}" ]] && ((! doPackage)); then
		fTestSkip "GOTOOLCHAIN=${handSet} picks ${used}, not go${pin}"
	else
		fTestFail "GOTOOLCHAIN=${goToolchain} gives ${used}, not go${pin}."
	fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Zig_Vendor(){

	fSection "Zig: vendor"

	local -r vendorDir="${zigDir}/vendor"
	mkdir -p "${vendorDir}"

	## Wasmtime C API, pinned and checksummed per platform. The host's goes in
	## vendor/wasmtime. A Mac also gets the other macOS one beside it, as
	## vendor/wasmtime-<platform>, for the second slice of its universal release.
	## Linux gets the other Linux one there under --package, since it releases
	## both architectures, and FreeBSD's and Windows' too. build.zig and
	## package.bash look for it there, under Zig's name for the platform.
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
	local -a releasePlatforms=()
	if   [[ "${hostOs}" == "macos" ]];                  then releasePlatforms=(x86_64-macos aarch64-macos)
	elif [[ "${hostOs}" == "linux" ]] && ((doPackage)); then releasePlatforms=(x86_64-linux aarch64-linux)
	fi
	local platform=""
	for platform in "${releasePlatforms[@]}"; do
		if [[ "${platform}" != "${hostPlatform}" ]]; then fVendor_Wasmtime "${platform}" "${vendorDir}/wasmtime-${platform}"; fi
	done
	if [[ "${hostOs}" == "linux" ]] && ((doPackage)); then fVendor_FreeBSD "${vendorDir}/wasmtime-x86_64-freebsd"; fi
	if [[ "${hostOs}" == "linux" ]] && ((doPackage)); then
		fVendor_Wasmtime "x86_64-mingw"    "${vendorDir}/wasmtime-x86_64-windows"
		fVendor_Wasmtime "aarch64-windows" "${vendorDir}/wasmtime-aarch64-windows"
	fi

	## The reactor wasm module, built from the same convertbase release go.mod
	## pins. Building it here rather than copying a prebuilt artifact is what
	## keeps the two implementations on one version of the library: the Go
	## module and the wasm module cannot drift apart when they come from the
	## same verified module. Needs a Go 1.24+ toolchain for //go:wasmexport.
	local -r wasmVendored="${vendorDir}/convert-base-reactor.wasm"
	if command -v go &>/dev/null; then
		local -r wasmTmp="${wasmVendored}.new"
		local buildLog="" goToolchain=""
		fReactor_Toolchain
		if buildLog="$(GOTOOLCHAIN="${goToolchain}" GOOS=wasip1 GOARCH=wasm go build -C "${goDir}" -trimpath -buildmode=c-shared \
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
			## It's built here so the two sides can't reach different library
			## versions. A failure that falls back to
			## an older vendored copy has to say what went wrong.
			rm -f "${wasmTmp}"
			((! doPackage)) || fThrowError "Could not build the reactor wasm module for a release, and won't ship an older copy: ${buildLog}"  "${FUNCNAME[0]}"
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

	## Version-stamped, so re-pinning in fConfig re-fetches instead of
	## quietly keeping whatever was vendored first.
	local -r wtStamp="${dest}/.version"
	if [[ -f "${dest}/include/wasmtime.h" ]] && [[ "$(cat "${wtStamp}" 2>/dev/null || true)" == "${wasmtimeVer}" ]]; then
		fEcho_Clean "Wasmtime ...: ${wasmtimeVer} ${platform} present"
		return 0
	fi

	## Wasmtime zips its Windows archives, and GNU tar cannot read a zip.
	local wtExt="tar.xz"
	if [[ "${platform}" == *-mingw || "${platform}" == *-windows ]]; then wtExt="zip"; fi
	_fMustBeInPath curl
	_fMustBeInPath shasum
	if [[ "${wtExt}" == "zip" ]]; then _fMustBeInPath unzip; else _fMustBeInPath tar; fi
	local -r wtName="wasmtime-${wasmtimeVer}-${platform}-c-api"
	local -r wtUrl="https://github.com/bytecodealliance/wasmtime/releases/download/${wasmtimeVer}/${wtName}.${wtExt}"
	local -r wtTar="${parentDir}/${wtName}.${wtExt}"
	fEcho_Clean "Wasmtime ...: fetching ${wasmtimeVer} ${platform}"
	curl -sSL --fail -o "${wtTar}" "${wtUrl}" || fThrowError "Could not download '${wtUrl}'."  "${FUNCNAME[0]}"
	## shasum, not sha256sum: it is on both Linux and macOS.
	local -r wtSum="$(shasum -a 256 "${wtTar}" | awk '{print $1}')"
	if [[ "${wtSum}" != "${wasmtimeSha256}" ]]; then
		rm -f "${wtTar}"
		fThrowError "Wasmtime ${platform} checksum mismatch: got ${wtSum}."  "${FUNCNAME[0]}"
	fi
	if [[ "${wtExt}" == "zip" ]]; then
		unzip -q -o "${wtTar}" -d "${parentDir}"
	else
		tar --no-same-owner --no-same-permissions -xf "${wtTar}" -C "${parentDir}"
	fi
	rm -f "${wtTar}"
	rm -rf "${dest:?}"
	mv "${parentDir}/${wtName}" "${dest}"
	printf '%s\n' "${wasmtimeVer}" > "${wtStamp}"
	fEcho_Clean "Wasmtime ...: vendored ${platform}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## FreeBSD's Wasmtime, from its packages into the same layout as Wasmtime's own
## release: include/, lib/libwasmtime.a and LICENSE, with libzstd.a beside it,
## and zstd's license for the release to include.
fVendor_FreeBSD(){  ## destination

	local -r dest="$1"
	local -r parentDir="$(dirname "${dest}")"
	local -r stamp="${dest}/.version"
	local -r want="${freebsdPkgs[*]%%=*}"
	## A tree vendored before the license was copied has none, so it is fetched again.
	if [[ -f "${dest}/include/wasmtime.h" && -f "${dest}/LICENSE" ]] && [[ "$(cat "${stamp}" 2>/dev/null || true)" == "${want}" ]]; then
		fEcho_Clean "Wasmtime ...: ${want} x86_64-freebsd present"
		return 0
	fi

	_fMustBeInPath curl
	_fMustBeInPath shasum
	_fMustBeInPath tar
	local -r unpackDir="${parentDir}/.freebsd-unpack"
	rm -rf "${unpackDir:?}"
	mkdir -p "${unpackDir}"
	local pin="" pkgName="" pkgSum="" pkgFile="" gotSum=""
	for pin in "${freebsdPkgs[@]}"; do
		pkgName="${pin%%=*}"; pkgSum="${pin#*=}"
		pkgFile="${unpackDir}/${pkgName}.pkg"
		fEcho_Clean "Wasmtime ...: fetching FreeBSD ${pkgName}"
		curl -sSL --fail -o "${pkgFile}" "${freebsdRepo}/All/${pkgName}.pkg" \
			|| fThrowError "Could not download ${pkgName} from ${freebsdRepo}. The repo may have moved on to a newer build; repin default_freebsdPkgs from its packagesite."  "${FUNCNAME[0]}"
		gotSum="$(shasum -a 256 "${pkgFile}" | awk '{print $1}')"
		[[ "${gotSum}" == "${pkgSum}" ]] || fThrowError "FreeBSD ${pkgName} checksum mismatch: got ${gotSum}."  "${FUNCNAME[0]}"
		## A package is a tarball of absolute paths under /usr/local.
		tar --no-same-owner --no-same-permissions -xf "${pkgFile}" -C "${unpackDir}" 2>/dev/null \
			|| fThrowError "Could not unpack ${pkgName}."  "${FUNCNAME[0]}"
	done

	local -r usrLocal="${unpackDir}/usr/local"
	rm -rf "${dest:?}"
	mkdir -p "${dest}/lib"
	cp -R "${usrLocal}/include" "${dest}/"
	cp "${usrLocal}/lib/libwasmtime.a" "${usrLocal}/lib/libzstd.a" "${dest}/lib/"
	## zstd is dual BSD and GPLv2; the release takes it under BSD, whose text
	## has the copyright line a binary distribution has to reproduce.
	cp "$(find "${usrLocal}/share/licenses" -path '*/zstd-*/BSD3CLAUSE' -print -quit)" "${dest}/LICENSE-zstd" \
		|| fThrowError "The zstd package has no BSD3CLAUSE license file."  "${FUNCNAME[0]}"
	## The port installs Wasmtime's own LICENSE under the name of its license,
	## so this is upstream's text, LLVM exception and all.
	cp "$(find "${usrLocal}/share/licenses" -path '*/libwasmtime-*/APACHE20' -print -quit)" "${dest}/LICENSE" \
		|| fThrowError "The libwasmtime package has no APACHE20 license file."  "${FUNCNAME[0]}"
	rm -rf "${unpackDir:?}"
	printf '%s\n' "${want}" > "${stamp}"
	fEcho_Clean "Wasmtime ...: vendored ${want} x86_64-freebsd"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Zig(){

	fStage_Zig_Vendor

	fSection "Zig: build and test"

	cd "${zigDir}" || fThrowError "Missing the Zig tree: '${zigDir}'."  "${FUNCNAME[0]}"

	## ReleaseSafe is what a release uses; the vectors replay through it too.
	## zig wants the count attached to the flag, not as a separate word.
	## On Linux the command is built for package.bash's target, not this CPU,
	## since dogfood copies it into a dir other machines run from. One built
	## for the build machine's CPU died on the first hash on a CPU without SHA-NI.
	local -a releaseTarget=()
	if [[ "$(uname -s)" == "Linux" ]]; then releaseTarget=("-Dtarget=$(uname -m)-linux-gnu.2.28"); fi
	zig build "-j${buildJobs}" -Doptimize=ReleaseSafe "${releaseTarget[@]}"
	fId EsXcjyV "dogfood build is plain x86-64"
	if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
		fTestSkip "only a Linux x86_64 build goes to the synced dir"
	elif ! command -v objdump >/dev/null 2>&1; then
		fTestSkip "no objdump"
	else
		local dogfoodScan=""
		dogfoodScan="$(fX86FloorScan "${zigDir}/zig-out/bin/zuid")"
		if [[ "${dogfoodScan%% *}" != "0" ]]; then
			fTestFail "${dogfoodScan%% *} functions use instructions past x86-64-v1, such as ${dogfoodScan#* }. The Zig stage has to name a target."
		fi
		fTestPass
	fi
	## Zig numbers a value interned off the main thread with the thread's number
	## in the top bits, and a worker thread is whichever was free. Below 2^20 is
	## the main thread on any machine with up to 4096 threads.
	fId EscFGGR "stable __anon names in libzuid.a"
	if ! command -v nm >/dev/null 2>&1; then
		fTestSkip "no nm"
	else
		local anonScan="" anonCount="" anonBad="" anonExample=""
		anonScan="$(nm "${zigDir}/zig-out/lib/libzuid.a" 2>/dev/null | awk '
			match($NF, /__anon_[0-9]+$/) { n++; v = substr($NF, RSTART + 7) + 0; if (v >= 1048576) { bad++; ex = $NF } }
			END { printf "%d %d %s", n, bad, ex }' || true)"
		read -r anonCount anonBad anonExample <<< "${anonScan}"
		if [[ "${anonCount}" == "0" ]]; then
			fTestSkip "no __anon_N names in libzuid.a, so Zig names them some other way now"
		elif [[ "${anonBad}" != "0" ]]; then
			fTestFail "${anonBad} of ${anonCount} names were made off the main thread, such as ${anonExample}, so 2 cold builds can differ. See compilerRt in build.zig."
		else
			fTestPass
		fi
	fi
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
	local -r unformattedZig="$(zig fmt --check build.zig tools lib/src cmd/src 2>&1 || true)"
	if [[ -n "${unformattedZig}" ]]; then
		fThrowError "zig fmt would rewrite: ${unformattedZig//$'\n'/, }"  "${FUNCNAME[0]}"
	fi

	fStage_Zig_Cli
	fStage_Zig_CApi
	fStage_Zig_CChecks
	fStage_Zig_Fuzz

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The two fuzz tests in tests.zig, this time in fuzz mode. In Debug, because
## the leaked-context test counts contexts only there and fails in a release
## build. A find still exits 0, so the output is read for it.
fStage_Zig_Fuzz(){

	fSection "Zig: fuzz"

	local -r fuzzLimit="50K"

	## One line per fuzz test under its own ID, as the Go side does. The limit
	## is per test, not shared.
	local -a fuzzIds=() fuzzNames=()
	local fuzzId="" fuzzName=""
	while IFS=$'\t' read -r fuzzId fuzzName; do
		fuzzIds+=("${fuzzId}")
		fuzzNames+=("${fuzzName}")
	done < <(python3 "${utilityDir}/test-ids.py" fuzzers || true)
	((${#fuzzIds[@]} > 0)) || fThrowError "No Zig test calls std.testing.fuzz, so there is nothing to fuzz."  "${FUNCNAME[0]}"

	local -i i=0
	if ((! doFuzz)); then
		local skipWhy="--no-fuzz"; if ((doQuick)); then skipWhy="a quick run"; fi
		for i in "${!fuzzIds[@]}"; do
			fId "${fuzzIds[i]}" "${fuzzNames[i]}, fuzzed for ${fuzzLimit} iterations"
			fTestSkip "${skipWhy}"
		done
		return 0
	fi

	cd "${zigDir}" || fThrowError "Missing the Zig tree: '${zigDir}'."  "${FUNCNAME[0]}"

	local logDir=""
	logDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${logDir}")
	local -r fuzzLog="${logDir}/fuzz.log"

	## The limit has to stay attached with '='. A bare --fuzz never ends and
	## starts a web server, and that is how a separate word would be read.
	local -i exitCode=0
	env -u DISPLAY -u WAYLAND_DISPLAY zig build "-j${hardJobs}" test "--fuzz=${fuzzLimit}" > "${fuzzLog}" 2>&1 || exitCode=$?

	local -r findLine="$(grep -m1 -F "input saved to '" "${fuzzLog}" || true)"
	if [[ -z "${findLine}" ]] && ((exitCode == 0)); then
		for i in "${!fuzzIds[@]}"; do
			fId "${fuzzIds[i]}" "${fuzzNames[i]}, fuzzed for ${fuzzLimit} iterations"
			fTestPass
		done
		rm -rf "${logDir}"
		return 0
	fi

	cat "${fuzzLog}"
	if [[ -z "${findLine}" ]]; then
		## A build error or a broken runner, not a find, so no one test is to blame.
		for i in "${!fuzzIds[@]}"; do
			fEcho_Clean "  FAIL ..: ${fuzzIds[i]} ${fuzzNames[i]}, fuzzed for ${fuzzLimit} iterations"
		done
		fThrowError "zig build test --fuzz=${fuzzLimit} exited ${exitCode}."  "${FUNCNAME[0]}"
	fi

	## "test 'tests.test.<name>' terminated ...; input saved to '...'". The
	## others stopped with it, so they were not fuzzed to the limit.
	local failName="${findLine#*test \'}"
	failName="${failName%%\' *}"
	failName="${failName#*.test.}"
	local failId="???????"
	for i in "${!fuzzIds[@]}"; do
		if [[ "${fuzzNames[i]}" == "${failName}" ]]; then failId="${fuzzIds[i]}"; fi
	done
	for i in "${!fuzzIds[@]}"; do
		[[ "${fuzzIds[i]}" == "${failId}" ]] && continue
		fId "${fuzzIds[i]}" "${fuzzNames[i]}, fuzzed for ${fuzzLimit} iterations"
		fTestSkip "fuzzing stopped at the find in ${failId}"
	done
	fId "${failId}" "${failName}, fuzzed for ${fuzzLimit} iterations"

	## The cache copy is overwritten by the next find, and artifacts/fuzz is
	## not rotated, so the input stays until somebody adds it to the corpus.
	local crashFile="${findLine##*input saved to \'}"
	crashFile="${crashFile%\'*}"
	[[ "${crashFile}" == /* ]] || crashFile="${zigDir}/${crashFile}"
	local -r keepDir="${artifactDir}/fuzz"
	local -r keptFile="${keepDir}/zig-crash_${runStamp}"
	mkdir -p "${keepDir}"
	if ! cp "${crashFile}" "${keptFile}"; then
		fTestFail "Fuzzing found a failing input, and '${crashFile}' could not be kept."
	fi
	## The saved bytes replay as they are when added to the test's corpus.
	## printf, since fEcho_Clean's echo -e would undo the escapes.
	if [[ -n "$(command -v python3 2>/dev/null || true)" ]]; then
		printf 'As a corpus entry: %s\n' "$(python3 -c 'import sys; print("\"" + "".join(chr(c) if 32 <= c < 127 and c not in (34, 92) else "\\x%02x" % c for c in open(sys.argv[1], "rb").read()) + "\"")' "${keptFile}")"
	fi
	fTestFail "Fuzzing found a failing input, kept as ${keptFile}."

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The vectors cover the two modules. What the command itself prints, and what
## it exits with, is only checked here.
fStage_Zig_Cli(){

	fSection "Zig: command surface"

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

	## Zig 0.17.0 on macOS spins forever copying its output into a pipe, and a
	## captured stdout is a pipe. tools/to_file.zig gives it a file instead. A
	## Linux build never hangs, so look for the call.
	fId Erm4m6a "no build step pipes stdout"
	local -r buildCode="$(grep -v '^[[:space:]]*//' "${zigDir}/build.zig" || true)"
	if [[ "${buildCode}" == *captureStdOut* ]]; then
		fTestFail "build.zig captures a command's stdout. zig translate-c hangs on macOS when that is a pipe; run it through tools/to_file.zig."
	fi
	fTestPass

	fId Eq9nb3o "build with an empty SOURCE_DATE_EPOCH"
	## Its own cache, since translate-c chokes on the empty value, and a cached
	## translation never runs it. The global cache has to be warm: clang refuses
	## the value too, in Zig's own libunwind and libc builds, which no build.zig
	## cna reach. fDropBadEpoch keeps it from them. A new Zig or a cleared cache
	## failed here, so a plain build goes first, in a throwaway cache.
	(
		cd "${zigDir}" || exit 1
		zig build "-j${buildJobs}" --cache-dir "${stampDir}/warm" --prefix "${stampDir}/warm-out" >/dev/null || exit 1
		SOURCE_DATE_EPOCH="" zig build "-j${buildJobs}" --cache-dir "${stampDir}/cache" --prefix "${stampDir}" || exit 1
	) || fTestFail "the build failed with SOURCE_DATE_EPOCH empty."

	local -r stamped="$("${stampDir}/bin/zuid" --version 2>&1 || true)"
	if [[ "${stamped}" != *"(build "* ]]; then
		fTestFail "an empty SOURCE_DATE_EPOCH dropped the build number: --version said '${stamped}'. It should fall through to the commit date."
	fi
	fTestPass

	## The translate-c steps hash to_file's bytes, and where they put the headers
	## is in every file's debug info. Both caches above are new, so each built
	## its own to_file. __anon_ names include the compiler's thread numbers, and a
	## builder with 1 CPU gets other ones, so a match here alone isn't enough.
	fId EscLn6s "tools/to_file is reproducible"
	local -a toFiles=()
	mapfile -t toFiles < <(find "${stampDir}/warm/o" "${stampDir}/cache/o" -type f \( -name to_file -o -name to_file.exe \) 2>/dev/null || true)
	if ((${#toFiles[@]} != 2)); then
		fTestFail "found ${#toFiles[@]} to_file builds in 2 new caches, not 2."
	elif ! cmp -s "${toFiles[0]}" "${toFiles[1]}"; then
		fTestFail "to_file differs between 2 new caches, so the translated headers and every debug path move. build.zig should build it with LLVM, stripped."
	elif LC_ALL=C grep -aqF __anon_ "${toFiles[0]}"; then
		fTestFail "to_file keeps __anon_ names, which change with the compiler's thread count. build.zig should strip it."
	fi
	fTestPass

	## Zig 0.17 reuses build.zig's answers from the last run unless told not to,
	## and it doesn't watch the environment or git. So the same cache again, with
	## only the epoch changed. bz4zn is 1700000000 in minutes since 2000.
	fId EsaCjhS "build number follows SOURCE_DATE_EPOCH in a warm cache"
	(
		cd "${zigDir}" || exit 1
		SOURCE_DATE_EPOCH=1700000000 zig build "-j${buildJobs}" --cache-dir "${stampDir}/cache" --prefix "${stampDir}/again" || exit 1
	) || fTestFail "the build failed with SOURCE_DATE_EPOCH=1700000000."
	local -r restamped="$("${stampDir}/again/bin/zuid" --version 2>&1 || true)"
	if [[ "${restamped}" != *"(build bz4zn)"* ]]; then
		fTestFail "--version said '${restamped}', so the build kept an old epoch."
	fi
	fTestPass

	## bz4zn is 2023-11-14 22:13 UTC, already the 15th at UTC+14. A date fixed
	## at build time would be the same in both.
	fId EtaWcMt "build date is the viewer's local date"
	local dated=""
	dated="$(TZ=UTC0 "${stampDir}/again/bin/zuid" --version 2>&1 || true)"
	[[ "${dated}" == *"(build bz4zn) (2023-11-14)" ]] || fTestFail "with TZ=UTC0, --version said '${dated}', not the 2023-11-14 build date."
	dated="$(TZ=XXX-14 "${stampDir}/again/bin/zuid" --version 2>&1 || true)"
	[[ "${dated}" == *"(build bz4zn) (2023-11-15)" ]] || fTestFail "at UTC+14, --version said '${dated}', not the 2023-11-15 build date."
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

	fSection "Zig: C module from a system compiler"

	local systemCc=""
	if   command -v gcc   &>/dev/null; then systemCc="gcc"
	elif command -v clang &>/dev/null; then systemCc="clang"
	fi
	if [[ -z "${systemCc}" ]]; then
		fEcho_Clean "Skipped ....: no system gcc or clang."
		return 0
	fi
	fEcho_Clean "Compiler ...: ${systemCc}"
	## The header is for C99 callers, and has to stay quiet for them.
	local -ra cWarn=(-std=c99 -Wall -Wextra -Wpedantic -Werror)

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

	## Shared: self-contained, so the header and -lzuid are all it needs.
	## An rpath rather than LD_LIBRARY_PATH, which macOS does not read.
	fId ElpGOHZ "capi_smoke.c against the shared library"
	"${systemCc}" "${cWarn[@]}" -I "${zigDir}/zig-out/include" "${smokeSrc}" \
		-L "${libDir}" -lzuid -Wl,-rpath,"${libDir}" -o "${buildDir}/smoke-shared" || fTestFail "did not compile."
	"${buildDir}/smoke-shared" || fTestFail "the smoke test failed."
	fTestPass

	## Only the entry points are visible. The library used to export all of
	## Wasmtime, which let any program holding one of those names displace the
	## calls it makes internally.
	fId Eq9gPQm "shared library exports match zuid.map"
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
	fId EqA3RdC "soname is ${majorName}"
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
	fId Eq9gPQn "caller's own Wasmtime name doesn't clash"
	if [[ -f "${interposeSrc}" ]]; then
		"${systemCc}" "${cWarn[@]}" -I "${zigDir}/zig-out/include" "${interposeSrc}" \
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
	"${systemCc}" "${cWarn[@]}" -I "${zigDir}/zig-out/include" "${smokeSrc}" \
		"${zigDir}/zig-out/lib/libzuid.a" "${zigDir}/vendor/wasmtime/lib/libwasmtime.a" \
		-lpthread -ldl -lm -o "${buildDir}/smoke-static" || fTestFail "did not link."
	"${buildDir}/smoke-static" || fTestFail "the smoke test failed."
	fTestPass

	## Now the same thing the way somebody who downloaded the release does it:
	## against a tree holding only what's in the release, with the link line the
	## header prints. libzuid.a used to nest the whole wasmtime archive inside
	## itself, where no linker looks, and the release had no separate copy,
	## so this is the check that would have caught it. Deliberately not pointed
	## at vendor/.
	fId Eq9hexE "capi_smoke.c with the header's link line"
	local -r relTree="${buildDir}/release"
	mkdir -p "${relTree}/lib" "${relTree}/include"
	cp "${zigDir}/zig-out/include/zuid.h"                  "${relTree}/include/"
	cp "${zigDir}/zig-out/lib/libzuid.a"                   "${relTree}/lib/"
	cp "${zigDir}/vendor/wasmtime/lib/libwasmtime.a"       "${relTree}/lib/"
	## Apple's ld has no -Bstatic. It needs none here, with only archives in lib/.
	local -a staticOn=('-Wl,-Bstatic') staticOff=('-Wl,-Bdynamic')
	if ((isMac)); then staticOn=(); staticOff=(); fi
	"${systemCc}" "${cWarn[@]}" -I "${relTree}/include" "${smokeSrc}" \
		-L "${relTree}/lib" "${staticOn[@]}" -lzuid -lwasmtime "${staticOff[@]}" \
		-lpthread -ldl -lm -o "${buildDir}/smoke-release" || fTestFail "did not link."
	"${buildDir}/smoke-release" || fTestFail "the smoke test failed."
	fTestPass

	## And nothing nested, since that is what made the archive unusable.
	fId Eq9hexF "no nested archive in libzuid.a"
	if ar t "${zigDir}/zig-out/lib/libzuid.a" | grep -q '\.a$'; then
		fTestFail "libzuid.a has another archive inside it. Only its own objects belong there."
	fi
	fTestPass

	rm -rf "${buildDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The C tests again under ASan, LSan and UBSan, and gcc's and clang's
## analyzers over every first-party .c file. Only our C is instrumented, since
## Wasmtime comes prebuilt. Its mallocs still go through ASan, so LSan sees a
## Wasmtime object that zuid_free leaves behind. The compilers are the image's,
## like the Go checkers. About 15 s on a busy box, most of it starting the
## image 5 times, so quick runs keep it.
fStage_Zig_CChecks(){

	fSection "Zig: C sanitizers and analyzers"

	local checkerSkipWhy=""
	local -ri imageJobs="${hardJobs}"
	fGoCheckers_Ready

	local -r cChecks="${utilityDir}/c-checks.bash"
	local -r testDir="${zigDir}/lib/test" incDir="${zigDir}/zig-out/include" libDir="${zigDir}/zig-out/lib"
	local -ra cWarn=(-std=c99 -Wall -Wextra -Wpedantic -Werror)
	local buildDir=""
	buildDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${buildDir}")

	fId EtAHpAd "capi_smoke.c shared, sanitized"
	fCCheck "${buildDir}" "it did not build, or a sanitizer reported something. What it said is above." \
		bash "${cChecks}" sanitize smoke-shared "${cWarn[@]}" -I "${incDir}" "${testDir}/capi_smoke.c" \
		-L "${libDir}" -lzuid -Wl,-rpath,"${libDir}"

	fId EtAHpAe "capi_smoke.c static, sanitized"
	fCCheck "${buildDir}" "it did not build, or a sanitizer reported something. What it said is above." \
		bash "${cChecks}" sanitize smoke-static "${cWarn[@]}" -I "${incDir}" "${testDir}/capi_smoke.c" \
		"${libDir}/libzuid.a" "${zigDir}/vendor/wasmtime/lib/libwasmtime.a" -lpthread -ldl -lm

	fId EtAHpAf "capi_interpose.c sanitized"
	if [[ -f "${testDir}/capi_interpose.c" ]]; then
		fCCheck "${buildDir}" "it did not build, or a sanitizer reported something. What it said is above." \
			bash "${cChecks}" sanitize interpose "${cWarn[@]}" -I "${incDir}" "${testDir}/capi_interpose.c" \
			-L "${libDir}" -lzuid -Wl,-rpath,"${libDir}"
	else
		fTestSkip "capi_interpose.c is not present"
	fi

	## Every tracked .c file is ours. Nothing vendored is tracked.
	local -a cFiles=()
	mapfile -t cFiles < <(git -C "${repoRoot}" ls-files --full-name '*.c' | sed "s|^|${repoRoot}/|")

	fId EtAHpAg "gcc -fanalyzer finds nothing"
	if ((${#cFiles[@]} == 0)); then fTestFail "git ls-files found no .c files, so this would analyze nothing."; fi
	fCCheck "${buildDir}" "the analyzer found something. What it said is above." \
		bash "${cChecks}" gcc-analyzer "${cWarn[@]}" -I "${zigDir}/lib/include" -- "${cFiles[@]}"

	fId EtAHpAh "clang analyzer is clean"
	fCCheck "${buildDir}" "the analyzer found something. What it said is above." \
		bash "${cChecks}" clang-analyzer "${cWarn[@]}" -I "${zigDir}/lib/include" -- "${cFiles[@]}"

	rm -rf "${buildDir}"

}


## One check run in the image, or skipped with the reason.
fCCheck(){  ## folder, why it failed, command...
	if [[ -n "${checkerSkipWhy}" ]]; then fTestSkip "${checkerSkipWhy}"; return 0; fi
	local -r dir="$1" failWhy="$2"; shift 2
	fInImage "${dir}" "$@" || fTestFail "${failWhy}"
	fTestPass
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The slow checks, --leakcheck only. The soaks repeat what a caller does,
## round after round, and fail when the heap after round 2N is bigger than
## after round N by more than a margin. The first rounds fill caches, so it's
## never 0 against N. What they find goes in cicd/artifacts/leakcheck/.
fStage_Leakcheck(){

	fSection "Leak check: soak tests, cross-file analysis and CodeQL"

	local -r leakDir="${artifactDir}/leakcheck"
	mkdir -p "${leakDir}"
	local prefix=""
	for prefix in go-soak-n_ go-soak-2n_ c-soak-report_ c-soak-data_ codeql-go_ codeql-c_; do
		fRotate_Artifacts "${leakDir}" "${prefix}"
	done

	if ((doGo));  then fLeakcheck_Go "${leakDir}"; fi
	if ((doZig)); then fLeakcheck_C  "${leakDir}"; fi
	fLeakcheck_CodeQL "${leakDir}"

}


## On this machine's Go, since the soak reads Go's own runtime stats. About
## 20 s. Not under -race, which would be measuring the race detector's heap.
fLeakcheck_Go(){  ## artifact dir

	local -r leakDir="$1"
	cd "${goDir}" || fThrowError "Missing the Go tree: '${goDir}'."  "${FUNCNAME[0]}"
	local -rx GOMAXPROCS="${hardJobs}"
	local soakDir=""
	soakDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${soakDir}")

	## TestSoak skips without ZUID_SOAK_DIR. Its exit is held until the profiles
	## are moved, since a failed run is when they're wanted.
	local -i rc=0
	if [[ -n "$(command -v python3 2>/dev/null || true)" ]]; then
		ZUID_SOAK_DIR="${soakDir}" go test -p "${hardJobs}" -count=1 -run '^TestSoak$' -json ./zuid | python3 "${utilityDir}/test-ids.py" go || rc=$?
	else
		fEcho_Clean "IDs ........: skipped, no python3"
		ZUID_SOAK_DIR="${soakDir}" go test -p "${hardJobs}" -count=1 -run '^TestSoak$' -v ./zuid || rc=$?
	fi

	local -r profileN="${leakDir}/go-soak-n_${runStamp}.pprof" profile2N="${leakDir}/go-soak-2n_${runStamp}.pprof"
	if [[ -f "${soakDir}/summary.txt" ]]; then
		local line=""
		while IFS= read -r line; do fEcho_Clean "  ${line}"; done < "${soakDir}/summary.txt"
	fi
	if [[ -f "${soakDir}/heap-n.pprof" ]] && [[ -f "${soakDir}/heap-2n.pprof" ]]; then
		mv "${soakDir}/heap-n.pprof" "${profileN}"
		mv "${soakDir}/heap-2n.pprof" "${profile2N}"
		fEcho_Clean "Profiles ...: go tool pprof -top -base ${profileN} ${profile2N}"
	fi
	rm -rf "${soakDir}"
	((rc == 0)) || fThrowError "The Go soak test failed. What it said is above."  "${FUNCNAME[0]}"

}


## The image's gcc, heaptrack and clang, like the other C checks, so with no
## docker these skip with a note. About 40 s.
fLeakcheck_C(){  ## artifact dir

	local -r leakDir="$1"
	local checkerSkipWhy=""
	local -ri imageJobs="${hardJobs}"
	fGoCheckers_Ready

	local -r cChecks="${utilityDir}/c-checks.bash"
	local -r soakSrc="${zigDir}/lib/test/capi_soak.c" incDir="${zigDir}/zig-out/include" libDir="${zigDir}/zig-out/lib"
	local -ra cWarn=(-std=c99 -Wall -Wextra -Wpedantic -Werror)
	local buildDir=""
	buildDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${buildDir}")

	## heaptrack's data file is kept only on a failure. It runs to about 25 MB.
	fId EtAUMRB "C call soak under heaptrack"
	fCCheck "${buildDir}" "the heap grew, or a call failed. What it said is above, and heaptrack's report is in ${leakDir}." \
		bash "${cChecks}" soak-calls soak "${leakDir}/c-soak-report_${runStamp}.txt" "${leakDir}/c-soak-data_${runStamp}.zst" \
		"${cWarn[@]}" -I "${incDir}" "${soakSrc}" -L "${libDir}" -lzuid -Wl,-rpath,"${libDir}"

	## A missing zuid_free shows here, at about 13 MB a round.
	fId EtAUMRE "C context churn doesn't leak"
	fCCheck "${buildDir}" "the heap grew, or a call failed. What it said is above." \
		bash "${cChecks}" soak-contexts soak "${cWarn[@]}" -I "${incDir}" "${soakSrc}" -L "${libDir}" -lzuid -Wl,-rpath,"${libDir}"

	## No first-party .c file calls into another yet, so on its own the next
	## check can't show it follows calls across files. This one does.
	fId EtAUMRC "cross-file analyzer catches a planted bug"
	fCCheck "${buildDir}" "the cross-file analysis isn't following calls between files. What it said is above." \
		bash "${cChecks}" ctu-canary

	local -a cFiles=()
	mapfile -t cFiles < <(git -C "${repoRoot}" ls-files --full-name '*.c' | sed "s|^|${repoRoot}/|")
	fId EtAUMRD "cross-file analysis of our C"
	if ((${#cFiles[@]} == 0)); then fTestFail "git ls-files found no .c files, so this would analyze nothing."; fi
	fCCheck "${buildDir}" "the analyzer found something. What it said is above." \
		bash "${cChecks}" clang-ctu "${cWarn[@]}" -I "${zigDir}/lib/include" -- "${cFiles[@]}"

	rm -rf "${buildDir}"

}


## From CodeQL's own image, so with no docker these skip like the C checks.
## Each builds its database from scratch and fails if a file that compiled
## isn't in it. About 25 s each.
fLeakcheck_CodeQL(){  ## artifact dir

	local -r leakDir="$1"
	local checkerSkipWhy=""
	local -ri imageJobs="${hardJobs}"
	fGoCheckers_Ready
	if [[ -z "${checkerSkipWhy}" ]] && ((! inContainer)); then fCodeql_Image; fi
	## fInImage starts whatever containerTag names.
	local containerTag="${codeqlTag:-${containerTag}}"

	local -r runner="${utilityDir}/codeql.bash"
	local workDir=""
	workDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${workDir}")

	if ((doGo)); then
		fId EtAUMRI "CodeQL on Go"
		fCCheck "${workDir}" "CodeQL found something, or didn't see every file compile. What it said is above." \
			bash "${runner}" go "${goDir}" "${workDir}/go" "${leakDir}/codeql-go_${runStamp}.sarif" "${reactorPackage}"
	fi

	if ((doZig)); then
		local -a cFiles=()
		mapfile -t cFiles < <(git -C "${repoRoot}" ls-files --full-name '*.c' | sed "s|^|${repoRoot}/|")
		fId EtAUMRJ "CodeQL on C"
		if ((${#cFiles[@]} == 0)); then fTestFail "git ls-files found no .c files, so this would analyze nothing."; fi
		fCCheck "${workDir}" "CodeQL found something, or didn't see every file compile. What it said is above." \
			bash "${runner}" c "${repoRoot}" "${workDir}/c" "${leakDir}/codeql-c_${runStamp}.sarif" \
			-std=c99 -Wall -Wextra -Wpedantic -Werror -I "${zigDir}/lib/include" -- "${cFiles[@]}"
	fi

	rm -rf "${workDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Two profiles, because the two implementations have different hot paths: the
## Go module through its own benchmarks, and the command itself through perf.
fStage_Profile(){

	fSection "Profile"

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
	## work worth looking at. The others build one generator each, outside
	## the loop, so the bench time has to dwarf that: at 3000 runs it was a third
	## of a 51-sample profile.
	go test -p "${buildJobs}" -run '^$' -bench 'BenchmarkGenerate' -benchtime 1s \
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

	fSection "Demo"

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

	## Renders are kept with the private project files, beside the repo, when
	## they're here. A plain clone keeps them under cicd/artifacts/.
	local demoDir="${artifactDir}/demo"
	if [[ -d "${repoRoot}/../private" ]]; then demoDir="${repoRoot}/../private/demo/gif"; fi
	readonly demoDir
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

	fSection "Package"

	local -r packager="${utilityDir}/package.bash"
	[[ -x "${packager}" ]] || fThrowError "Missing the packager: '${packager}'."  "${FUNCNAME[0]}"

	## Named for the version the binary reports, not for git describe. The Mac
	## files are built on a Mac before the tag exists, and have to match what the
	## Linux box then publishes.
	local packageVersion=""
	packageVersion="$(fCoreVersion)" || fThrowError "Could not read the version from zig/lib/src/core.zig."  "${FUNCNAME[0]}"
	ZUID_JOBS="${buildJobs}" "${packager}" --out "${repoRoot}/dist" --version "v${packageVersion}"

	## The release has to run on machines older than this one. These check that
	## it did not pick up this one's CPU, glibc or macOS version. Linux makes an
	## x86_64 and an arm64 release on any host; the x86_64 one is checked here
	## first, and the arm64 one by its own IDs below.
	local osLabel="linux" archLabel="x86_64"
	if [[ "$(uname -s)" == "Darwin" ]]; then osLabel="darwin"; archLabel="universal"; fi
	local -r release="${repoRoot}/dist/${distPrefix}${osLabel}-${archLabel}"
	local -i haveObjdump=0
	if command -v objdump >/dev/null 2>&1; then haveObjdump=1; fi

	## Only a build for a release leaves the date off. The publish stage reads
	## the build number from --version, and the Windows resource is held to it.
	fId EtaWcMu "release --version has no build date"
	local releaseSaid=""
	if ! releaseSaid="$("${release}" --version 2>/dev/null)"; then
		fTestSkip "this host can't run ${release##*/}"
	elif [[ "${releaseSaid}" =~ ^[^\ ]+\ \(build\ [0-9a-z]+\)$ ]]; then
		fTestPass
	else
		fTestFail "--version said '${releaseSaid}'. package.bash has to build with -Drelease."
	fi

	## The macOS checks read one slice at a time. The x86_64 scan means nothing on
	## arm64, and the minimum macOS has to be right for both.
	local thinDir=""
	thinDir="$(mktemp -d)" || fThrowError "Could not make a temporary directory."  "${FUNCNAME[0]}"
	_scratchDirs+=("${thinDir}")
	local -r macSlices=("x86_64" "arm64")

	fId Erfhegq "macOS release is universal"
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

	local floorName="x86-64-v1" floorKind=""
	if [[ "${osLabel}" == "darwin" ]]; then floorName="Penryn"; floorKind="penryn"; fi
	fId ErbFB7B "CPU floor is ${floorName}"
	if ((! haveObjdump)); then
		fTestSkip "no objdump"
	elif [[ "${osLabel}" == "linux" && "$(uname -m)" != "x86_64" && "$(objdump --help 2>/dev/null || true)" != *elf64-x86-64* ]]; then
		fTestSkip "no objdump that reads x86_64"
	else
		## The release is stripped, so the names come from its debug info.
		local scanTarget="${release}" scanSymbols="${repoRoot}/dist/debug/${distPrefix}${osLabel}-${archLabel}/bin/zuid.debug"
		if [[ "${osLabel}" == "darwin" ]]; then
			scanTarget="${thinDir}/zuid-x86_64"
			scanSymbols="${repoRoot}/dist/debug/${distPrefix}darwin-universal/x86_64/bin/zuid.dSYM/Contents/Resources/DWARF/zuid"
			lipo -thin x86_64 "${release}" -output "${scanTarget}" || fTestFail "could not take the x86_64 slice out of ${release}."
		fi
		[[ -f "${scanSymbols}" ]] || fTestFail "there is no ${scanSymbols}, which names the functions built here."
		local floorScan=""
		floorScan="$(fX86FloorScan "${scanTarget}" "${scanSymbols}" "${floorKind}")"
		if [[ "${floorScan%% *}" != "0" ]]; then
			fTestFail "${floorScan%% *} functions use instructions past ${floorName}, such as ${floorScan#* }. package.bash has to name a target."
		fi
		fTestPass
	fi

	## Matches package.bash.
	local -r glibcFloor="2.28"
	fId ErbFB7C "glibc ${glibcFloor} at most"
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

	fStage_Package_OldCpu "${release}" "${thinDir}"
	fStage_Package_Arm64 "${thinDir}" "${glibcFloor}"
	fStage_Package_FreeBSD "${thinDir}"
	fStage_Package_Windows "${thinDir}"
	fStage_Package_Licenses "${thinDir}"
	fStage_Package_Stripped "${thinDir}"
	fStage_Package_Again "${thinDir}" "${packageVersion}"

	local -r macFloor="13.0"
	fId ErbFB7D "asks for macOS ${macFloor}"
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
	fId ErfrKRQ "dylib slices: exports, install name, floor, signature"
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

	fStage_Package_MacRun "${thinDir}" "${release}" "${packageVersion}"

	rm -rf "${thinDir}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Runs each slice of the macOS release this Mac can run: its own, plus x86_64
## under Rosetta on Apple Silicon. Then capi_smoke.c against the tarball's
## libraries, per slice. No box here is Apple Silicon, so the arm64 slice runs
## only on the hosted macOS runner.
fStage_Package_MacRun(){  ## scratch dir, release, version
	local -r scratchDir="$1" release="$2" version="$3"
	local -i isMac=0
	if [[ "$(uname -s)" == "Darwin" ]]; then isMac=1; fi
	local macLib=""
	if ((isMac)); then macLib="$(find "${scratchDir}/tgz" -type f -name 'libzuid.a' -print -quit)"; macLib="${macLib%/*}"; fi
	local -r smokeSrc="${zigDir}/lib/test/capi_smoke.c"
	local -ra cWarn=(-std=c99 -Wall -Wextra -Wpedantic -Werror)
	## Its own cache, so the real one is never read or written.
	local -r runHome="${scratchDir}/run-home"
	mkdir -p "${runHome}"
	local slice="" said="" linkKind="" smokeExe=""
	local -i canRun=0
	local -a linkFlags=()
	for slice in x86_64 arm64; do
		canRun=0
		if ((isMac)) && arch -"${slice}" /usr/bin/true 2>/dev/null; then canRun=1; fi

		fId "${slice}" x86_64=EtaL127 arm64=EtaL128 "macOS release, ${slice} slice runs"
		if ((! isMac)); then
			fTestSkip "macOS only"
		elif ((! canRun)); then
			fTestSkip "this Mac can't run ${slice}"
		else
			said="$(HOME="${runHome}" XDG_CACHE_HOME="${runHome}/cache" arch -"${slice}" "${release}" --version 2>&1)" || fTestFail "--version failed: ${said}"
			[[ "${said}" == "${version} (build "*")" ]] || fTestFail "--version said '${said}', not ${version}."
			said="$(HOME="${runHome}" XDG_CACHE_HOME="${runHome}/cache" arch -"${slice}" "${release}" 2>&1)" || fTestFail "a default identifier failed: ${said}"
			[[ -n "${said}" && "${said}" != *$'\n'* ]] || fTestFail "a default identifier came out as '${said}'."
			fTestPass
		fi

		for linkKind in static shared; do
			fId "${slice}-${linkKind}" x86_64-static=EtaL129 x86_64-shared=EtaL12A arm64-static=EtaL12B arm64-shared=EtaL12C "capi_smoke.c, macOS ${slice} ${linkKind}"
			if ((! isMac)); then fTestSkip "macOS only"; continue; fi
			[[ -n "${macLib}" ]] || fTestFail "the tarball has no libzuid.a."
			## Named as files, since -lzuid takes the dylib beside the archive.
			if [[ "${linkKind}" == "static" ]]
				then linkFlags=("${macLib}/libzuid.a" "${macLib}/libwasmtime.a" -lpthread -ldl -lm)
				else linkFlags=(-L "${macLib}" -lzuid "-Wl,-rpath,${macLib}")
			fi
			smokeExe="${scratchDir}/smoke-mac-${slice}-${linkKind}"
			MACOSX_DEPLOYMENT_TARGET="13.0" clang -arch "${slice}" "${cWarn[@]}" -I "${macLib}/../include" "${smokeSrc}" "${linkFlags[@]}" \
				-o "${smokeExe}" || fTestFail "did not link."
			if ((! canRun)); then fTestSkip "linked, but this Mac can't run ${slice}"; continue; fi
			arch -"${slice}" "${smokeExe}" || fTestFail "the smoke test failed."
			fTestPass
		done
	done
}


## Never the bare 'sde', which is an unrelated tool on some boxes.
fFindSde(){
	local sde="${ZUID_SDE:-}"
	if [[ -z "${sde}" ]]; then sde="$(command -v sde64 2>/dev/null || true)"; fi
	if [[ -z "${sde}" && -x "${HOME}/.local/opt/intel-sde/sde64" ]]; then sde="${HOME}/.local/opt/intel-sde/sde64"; fi
	printf '%s' "${sde}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Runs the Linux x86_64 release under Intel's SDE as the oldest CPUs it has to
## run on. SDE stops at the first instruction the chip lacks, in the code
## Wasmtime compiles too, and the CPU it reports is the chip's. Penryn is the
## last Core 2 Duo, with no POPCNT. SDE has no AMD chip, so Prescott stands in
## for Phenom II: no SSSE3 or SSE4.1. Each run starts from a module cache made
## on this CPU, which Wasmtime has to turn down and compile again.
fStage_Package_OldCpu(){  ## x86_64 release, scratch dir

	local -r release="$1" scratchDir="$2"
	local -r sde="$(fFindSde)"
	local -r seedHome="${scratchDir}/oldcpu-seed" runFormat="%d-%h-%u-%f-%g-%r"

	local chip="" chipName="" chipHome="" sdeErrors=""
	local -i seeded=0 lineCount=0
	for chip in pnr p4p; do
		case "${chip}" in
			pnr) chipName="Core 2 Duo (Penryn)" ;;
			p4p) chipName="Pentium 4 (Prescott)" ;;
		esac
		fId "${chip}" pnr=EsZyWyD p4p=EsZyWyE "runs on an emulated ${chipName}"
		if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
			fTestSkip "Linux x86_64 only"
			continue
		fi
		if [[ -z "${sde}" || ! -x "${sde}" ]]; then
			fTestSkip "no sde64 in ZUID_SDE, on PATH or in ~/.local/opt/intel-sde"
			continue
		fi
		[[ -f "${release}" ]] || fTestFail "there is no ${release}."
		if ((! seeded)); then
			mkdir -p "${seedHome}"
			HOME="${seedHome}" XDG_CACHE_HOME="${seedHome}/cache" "${release}" -f "${runFormat}" >/dev/null \
				|| fTestFail "the release failed on this CPU, before any emulation."
			seeded=1
		fi
		chipHome="${scratchDir}/oldcpu-${chip}"
		mkdir -p "${chipHome}"
		cp -R "${seedHome}/cache" "${chipHome}/"
		if ! HOME="${chipHome}" XDG_CACHE_HOME="${chipHome}/cache" "${sde}" "-${chip}" -- "${release}" -f "${runFormat}" -n 2 \
			>"${chipHome}/out" 2>"${chipHome}/err"; then
			fTestFail "it exited non-zero under ${sde} -${chip}: $(head -c 400 "${chipHome}/err")"
		fi
		sdeErrors="$(grep -c 'SDE-ERROR' "${chipHome}/err" || true)"
		[[ "${sdeErrors}" == "0" ]] || fTestFail "SDE reported: $(head -c 400 "${chipHome}/err")"
		lineCount="$(grep -c . "${chipHome}/out" || true)"
		((lineCount == 2)) || fTestFail "it printed ${lineCount} identifiers, expected 2."
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Prints how many functions use an instruction past plain x86-64, then up to
## three of their names, each with one such instruction. Wasmtime's Rust asks
## the CPU before it uses anything newer, so it is left out. Its names start
## with _ZN, or _R for the newer mangling. zstd, which comes with Wasmtime or
## FreeBSD's package, asks too (ZSTD_cpuid) and has a BMI2 twin of a few hot
## functions, so those twins are left out as well.
fX86FloorScan(){  ## x86_64 binary, [file its symbols went to, if it was stripped], [floor, as for fPastX86Floor]
	fDisassemble objdump "$1" "${2:-}" | fPastX86Floor "${3:-}" | awk '
		/^[0-9a-f]+ <.*>:$/ {
			fn = $2; gsub(/^<|>:$/, "", fn)
			asks = (fn ~ /^_?_(ZN|R[0-9]*[BCIMNXY])/ || fn ~ /_bmi2(\.[a-z]+\.[0-9]+)*$/ || fn ~ /^_?HUF_decompress4X[12]_usingDTable_internal_fast/)
			next
		}
		asks || (fn in seen) { next }
		{ seen[fn] = 1; if (++count <= 3) names = names " " fn " (" $2 ")" }
		END { print count + 0 names }
	'
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Filters objdump -d output down to its function headers and each instruction
## that plain x86-64 (x86-64-v1: SSE2, CMOV, CX8) lacks, as "address: mnemonic".
## The floor is the last Core 2 Duo and AMD's Phenom II. Penryn has SSE4.1 but
## no POPCNT, Phenom II the reverse, so neither is allowed. LZCNT runs as BSR
## on a CPU without it, a wrong answer with no fault, which an emulator misses
## too. TZCNT is let through: LLVM writes BSF that way on purpose, where BSF
## gives the same answer. A Mac's floor is Penryn instead, which is what
## Rust builds Wasmtime's macOS archive for, zstd included. Zig's baseline
## there is Core 2, and no Mac that runs macOS 13 is older than Penryn, so
## SSE3, SSSE3, SSE4.1, CX16 and LAHF are allowed.
fPastX86Floor(){  ## [penryn]
	awk -v floor="${1:-}" '
		BEGIN {
			core2 = "^(" \
				"fisttp[a-z]*|lddqu|movddup|movs[hl]dup|(addsub|hadd|hsub)p[sd]|monitor[a-z]*|mwait[a-z]*|" \
				"pabs[bwd]|palignr|ph(add|sub)(w|d|sw)|pmaddubsw|pmulhrsw|pshufb|psign[bwd]|cmpxchg16b|lahf|sahf)$"
			sse41 = "^(" \
				"blendv?p[sd]|pblend(vb|w)|dpp[sd]|extractps|insertps|movntdqa|mpsadbw|packusdw|pcmpeqq|" \
				"pextr[bdq]|pinsr[bdq]|phminposuw|pm(ax|in)(sb|sd|ud|uw)|pmov[sz]x(bw|bd|bq|wd|wq|dq)|pmuldq|pmulld|ptest|round[ps][sd])$"
			past = "^(" \
				"pcmp[ei]str[im]|pcmpgtq|crc32[bwlq]?|extrq|insertq|movnts[sd]|" \
				"popcnt[wlq]?|lzcnt[wlq]?|andn[lq]?|bextr[lq]?|blsi[lq]?|blsmsk[lq]?|blsr[lq]?|" \
				"bzhi[lq]?|mulx[lq]?|pdep[lq]?|pext[lq]?|rorx[lq]?|sarx[lq]?|shlx[lq]?|shrx[lq]?|adcx[lq]?|adox[lq]?|movbe[wlq]?|" \
				"aes[a-z0-9]*|pclmul[a-z]*|sha(1|256|512)[a-z0-9]*|gf2p8[a-z0-9]*|rdrand[wlq]?|rdseed[wlq]?|rdtscp|rdpid|" \
				"prefetchw(t1)?|prefetch|clflushopt|clwb|xgetbv|xsave[a-z0-9]*|xrstor[a-z0-9]*|" \
				"[rw]r[fg]sbase[lq]?|k(add|and|andn|mov|not|or|ortest|shiftl|shiftr|test|unpck|xnor|xor)[bwdq]?|" \
				"v[a-z0-9]*)$"
			virt = "^(verr|verw|vm(call|clear|func|launch|load|mcall|ptrld|ptrst|read|resume|run|save|write|xoff|xon)[lq]?)$"
			penryn = (floor == "penryn")
		}
		/^[0-9a-f]+ <.*>:$/ { print; next }
		/^[[:space:]]*[0-9a-f]+:[[:space:]]/ {
			text = $0; sub(/^[[:space:]]*[0-9a-f]+:[[:space:]]*/, "", text); sub(/[[:space:]]*#.*$/, "", text)
			n = split(text, word, /[[:space:]]+/)
			i = 1
			while (i < n && word[i] ~ /^(lock|rep[a-z]*|notrack|bnd|data16|addr32|cs|ds|es|fs|gs|ss|rex[.A-Za-z]*|xacquire|xrelease|\{[a-z]+\})$/) i++
			op = word[i]
			if ((op ~ past && op !~ virt) || (!penryn && (op ~ core2 || op ~ sse41 || (op ~ /^pextrw/ && text ~ /\(/))) || text ~ /%[xyz]mm(1[6-9]|2[0-9]|3[01])|%[yz]mm|%k[0-7]/) print $1, op
		}
	'
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## objdump -d, with function names. A stripped release gets them from the file
## its symbols went to, through nm, in the same form objdump gives them, so a
## scan reads either the same way. Addresses are padded to sort as text.
## A Mach-O dSYM keeps assembler labels such as zstd's .L_4X1_loop_body, which
## are inside a function, so they stay with it.
fDisassemble(){  ## objdump, program, [file its symbols went to]
	local -r objdump="$1" program="$2" symbols="${3:-}"
	if [[ -z "${symbols}" ]]; then
		"${objdump}" -d --no-show-raw-insn "${program}"
		return 0
	fi
	{
		nm -n "${symbols}" | awk 'NF >= 3 && $2 ~ /^[tTwW]$/ && $3 !~ /^\.L/ { a = $1; name = $0; sub(/^[^ ]+ [^ ]+ /, "", name); while (length(a) < 16) a = "0" a; print a, 0, a " <" name ">:" }'
		"${objdump}" -d --no-show-raw-insn "${program}" | awk '/^[[:space:]]*[0-9a-f]+:/ { a = $1; sub(/:$/, "", a); while (length(a) < 16) a = "0" a; print a, 1, $0 }'
	} | LC_ALL=C sort -t ' ' -k1,1 -k2,2 | cut -d ' ' -f 3-
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Prints a PE file's machine field, then IMAGE_FILE_DLL as 1 or 0, or nothing
## for a file that is not PE. x86_64 is 8664, arm64 aa64.
fPeHeader(){  ## file
	[[ "$(head -c 2 "$1")" == "MZ" ]] || return 0
	local peOffset=""
	peOffset="$(od -An -tu4 -j 60 -N 4 "$1" | tr -d ' ')"
	[[ "$(od -An -c -j "${peOffset}" -N 4 "$1" | tr -d ' ')" == 'PE\0\0' ]] || return 0
	local -r machine="$(od -An -tx2 -j $((peOffset + 4)) -N 2 "$1" | tr -d ' ')"
	local -r traits="$(od -An -tu2 -j $((peOffset + 22)) -N 2 "$1" | tr -d ' ')"
	echo "${machine} $(( (traits & 0x2000) != 0 ))"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## fX86FloorScan for a Windows program, whose function names are only in its
## PDB. Code built here is what the PDB lists; Wasmtime's Rust and mingw's C
## have no CodeView, so they are left out the same way.
fX86FloorScan_Pe(){  ## readobj, pdbutil, x86_64 program, its .pdb
	local -r readobj="$1" pdbutil="$2" program="$3" pdb="$4"
	local imageBase="" firstSection=""
	imageBase="$("${readobj}" --file-headers "${program}" | awk '$1 == "ImageBase:" { print $2; exit }')"
	firstSection="$("${readobj}" --sections "${program}" | awk '$1 == "VirtualAddress:" { print $2; exit }')"
	{
		"${pdbutil}" dump --symbols "${pdb}" | awk -v base="${imageBase}" -v section="${firstSection}" '
			function hex(text,   i, n) { text = tolower(text); sub(/^0x/, "", text); n = 0; for (i = 1; i <= length(text); i++) n = n * 16 + index("0123456789abcdef", substr(text, i, 1)) - 1; return n }
			/ S_[GL]PROC32 / { name = $0; sub(/^[^`]*`/, "", name); sub(/`[^`]*$/, "", name); next }
			name != "" && / addr = 0001:/ { split($0, parts, / addr = 0001:/); printf "F %.0f %d %s\n", hex(base) + hex(section) + (parts[2] + 0), $NF, name; name = "" }
		'
		objdump -d --no-show-raw-insn "${program}" | fPastX86Floor | awk '
			function hex(text,   i, n) { text = tolower(text); n = 0; for (i = 1; i <= length(text); i++) n = n * 16 + index("0123456789abcdef", substr(text, i, 1)) - 1; return n }
			/^[[:space:]]*[0-9a-f]+: / { address = $1; sub(/:$/, "", address); printf "A %.0f %s\n", hex(address), $2 }
		'
	} | LC_ALL=C sort -k2,2n -k1,1r | awk '
		$1 == "F" { end = $2 + $3; fn = $4; next }
		$2 < end && !(fn in seen) { seen[fn] = 1; if (++count <= 3) names = names " " fn " (" $3 ")" }
		END { print count + 0 names }
	'
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The Windows releases, cross-built on Linux. x86_64 links Wasmtime's mingw
## archive. arm64 links wasmtime.dll, since Wasmtime has only an MSVC build
## there, and puts it in bin/. Nothing here can run either, so this checks
## what each file is, what it needs and exports, and that capi_smoke.c links
## against both libraries. A Windows machine runs the x86_64 one by hand, and nothing runs
## the arm64 one yet.
fStage_Package_Windows(){  ## scratch dir

	local -r scratchDir="$1"
	local -i isLinux=0 haveZip=0 haveObjdump=0
	if [[ "$(uname -s)" == "Linux" ]];      then isLinux=1;     fi
	if command -v zip >/dev/null 2>&1;      then haveZip=1;     fi
	if command -v objdump >/dev/null 2>&1;  then haveObjdump=1; fi

	local winReadobj="" winPdbutil="" candidate="" version=""
	for version in "" -21 -20 -19 -18 -17 -16; do
		candidate="llvm-readobj${version}"
		if [[ -z "${winReadobj}" ]] && command -v "${candidate}" >/dev/null 2>&1; then winReadobj="${candidate}"; fi
		candidate="llvm-pdbutil${version}"
		if [[ -z "${winPdbutil}" ]] && command -v "${candidate}" >/dev/null 2>&1; then winPdbutil="${candidate}"; fi
	done

	## Everything a release file may load that is not in its zip. All of these
	## come with Windows 10. A mingw runtime DLL, or MSVC's, would not.
	local -r windowsDlls='^(kernel32|ntdll|advapi32|ws2_32|iphlpapi|bcrypt|bcryptprimitives|userenv|ole32|shell32|api-ms-win-(crt|core)-[a-z0-9-]+)\.dll$'
	local -r smokeSrc="${zigDir}/lib/test/capi_smoke.c"
	local -r winSystemLibs="-lws2_32 -liphlpapi -lbcrypt -ladvapi32 -luserenv -lole32 -lntdll"

	## What the version resource in zuid.exe and zuid.dll has to repeat, from
	## the host's own release. package.bash built every target from one commit
	## date, so the build number is the same in all of them.
	local hostRelease="${repoRoot}/dist/${distPrefix}linux-x86_64" versionWant="" yearWant="" aboutText=""
	if [[ "$(uname -m)" == "aarch64" ]]; then hostRelease="${repoRoot}/dist/${distPrefix}linux-arm64"; fi
	if ((isLinux)) && versionWant="$("${hostRelease}" --version 2>/dev/null)" && aboutText="$("${hostRelease}" --about 2>/dev/null)"; then
		yearWant="$(sed -n 's/^Copyright © \([0-9-]*\) Jim Collier .*/\1/p' <<< "${aboutText}")"
	else
		versionWant=""
	fi
	## FILEVERSION is 4 numbers, so a prerelease gets the flag in place of its tag.
	local -r versionPlain="${versionWant%% *}"
	local -r versionNumbers="${versionPlain%%-*}.0"
	local flagsWant="0x0"
	if [[ "${versionPlain}" == *-* ]]; then flagsWant="0x2"; fi
	local peFile="" peFacts="" peWant="" peLine=""

	local winArch="" winTarget="" machine="" winZip="" winBare="" winTree="" winRoot="" winFile=""
	local winExports="" exportProblem="" importSample="" inZip="" pe="" dll="" symbol=""
	local -A exported=()
	local link="" linkKind="" smokeExe="" smokeImports=""
	local -a winFiles=() links=() linkFlags=() importProblems=()
	for winArch in x86_64 arm64; do
		winZip="${repoRoot}/dist/${distPrefix}windows-${winArch}.zip"
		winBare="${repoRoot}/dist/${distPrefix}windows-${winArch}.exe"
		winTree="${scratchDir}/windows-${winArch}"
		case "${winArch}" in
			x86_64) winTarget="x86_64-windows-gnu";  machine="8664" ;;
			arm64)  winTarget="aarch64-windows-gnu"; machine="aa64" ;;
		esac
		winRoot=""
		if ((isLinux && haveZip)) && [[ -f "${winZip}" ]]; then
			mkdir -p "${winTree}"
			unzip -q "${winZip}" -d "${winTree}"
			winRoot="$(find "${winTree}" -mindepth 1 -maxdepth 1 -type d -print -quit)"
		fi

		## x86_64 is one file and gets a bare copy. arm64 needs wasmtime.dll
		## beside it, so a bare copy would not run.
		fId "${winArch}" x86_64=ErmM9mS arm64=ErmS0zE "Windows ${winArch} zip contents"
		if ((! isLinux)); then
			fTestSkip "Linux only"
		elif ((! haveZip)); then
			fTestSkip "no zip, so package.bash made no Windows release"
		else
			[[ -n "${winRoot}" ]] || fTestFail "there is no ${winZip}, or nothing in it."
			winFiles=(bin/zuid.exe bin/zuid.dll lib/zuid.lib lib/libzuid.a include/zuid.h share/LICENSE-wasmtime.txt)
			if [[ "${winArch}" == "arm64" ]]; then winFiles+=(bin/wasmtime.dll lib/wasmtime.lib); else winFiles+=(lib/libwasmtime.a); fi
			for winFile in "${winFiles[@]}"; do
				[[ -f "${winRoot}/${winFile}" ]] || fTestFail "${winFile} is missing."
			done
			[[ "$(fPeHeader "${winRoot}/bin/zuid.exe")" == "${machine} 0" ]] || fTestFail "zuid.exe is not a ${winArch} Windows program."
			[[ "$(fPeHeader "${winRoot}/bin/zuid.dll")" == "${machine} 1" ]] || fTestFail "zuid.dll is not a ${winArch} Windows DLL."
			if [[ "${winArch}" == "arm64" ]]; then
				[[ "$(fPeHeader "${winRoot}/bin/wasmtime.dll")" == "${machine} 1" ]] || fTestFail "wasmtime.dll is not a ${winArch} Windows DLL."
				[[ ! -e "${winBare}" ]] || fTestFail "$(basename "${winBare}") is in dist/, and cannot run without wasmtime.dll."
			else
				cmp -s "${winBare}" "${winRoot}/bin/zuid.exe" || fTestFail "$(basename "${winBare}") is missing, or is not the zip's zuid.exe."
			fi
			grep -q "Combined Software" "${winRoot}/share/LICENSE-wasmtime.txt" || fTestFail "LICENSE-wasmtime.txt is not Wasmtime's license."
			fTestPass
		fi

		## What Explorer's Properties tab shows. It has to say what --version and
		## --about say, in ASCII, with no time stamp and no ID in the copyright.
		fId "${winArch}" x86_64=EtBCCRm arm64=EtBCCRn "Windows ${winArch} version resource"
		if ((! isLinux)); then
			fTestSkip "Linux only"
		elif ((! haveZip)); then
			fTestSkip "no zip, so package.bash made no Windows release"
		elif [[ -z "${versionWant}" || -z "${yearWant}" ]]; then
			fTestSkip "the host's own release doesn't run here, so there's no --version to hold it to"
		else
			[[ -n "${winRoot}" ]] || fTestFail "there is no ${winZip}, or nothing in it."
			for peFile in zuid.exe zuid.dll; do
				peFacts="$(python3 "${utilityDir}/pe-version.py" "${winRoot}/bin/${peFile}" 2>&1)" || fTestFail "${peFile}: ${peFacts}"
				if LC_ALL=C grep -q '[^ -~]' <<< "${peFacts}"; then fTestFail "${peFile}'s version resource isn't all ASCII: ${peFacts}"; fi
				peWant="resources 1
STAMP 0x0
FILEVERSION ${versionNumbers}
PRODUCTVERSION ${versionNumbers}
FILEFLAGSMASK 0x3f
FILEFLAGS ${flagsWant}
FILEOS 0x40004
FILETYPE $([[ "${peFile}" == *.exe ]] && echo 0x1 || echo 0x2)
FILEDATE 0x0
StringTable 040904b0
CompanyName=Jim Collier
FileDescription=$([[ "${peFile}" == *.exe ]] && echo "zuid" || echo "zuid C library")
FileVersion=${versionWant}
InternalName=zuid
LegalCopyright=Copyright (C) ${yearWant} Jim Collier
OriginalFilename=${peFile}
ProductName=zuid
ProductVersion=${versionWant}
Translation 0409 04b0"
				if [[ "${peFacts}" != "${peWant}" ]]; then
					peLine="$(diff <(printf '%s\n' "${peWant}") <(printf '%s\n' "${peFacts}") | grep '^[<>]' | paste -sd' ' - || true)"
					fTestFail "${peFile}'s version resource isn't what build.zig should write (< want, > have): ${peLine}"
				fi
			done
			fTestPass
		fi

		## A DLL exports only what is marked for export, so there is no map to
		## apply. Wasmtime's own objects mark four debugger hooks, which come
		## along on x86_64. Nothing can displace them, since Windows binds a
		## DLL's calls inside it.
		fId "${winArch}" x86_64=ErmM9mT arm64=ErmS0zF "Windows ${winArch} zuid.dll exports"
		if ((! isLinux)); then
			fTestSkip "Linux only"
		elif ((! haveZip)); then
			fTestSkip "no zip, so package.bash made no Windows release"
		elif [[ -z "${winReadobj}" ]]; then
			fTestSkip "no llvm-readobj"
		else
			[[ -n "${winRoot}" ]] || fTestFail "there is no ${winZip}, or nothing in it."
			winExports="$("${winReadobj}" --coff-exports "${winRoot}/bin/zuid.dll" | awk '$1 == "Name:" { print $2 }' \
				| grep -Ev '^(__jit_debug_(descriptor|register_code)|wasmtime_(set_vmctx_memory|resolve_vmctx_memory_ptr)_[0-9_]+)$' || true)"
			exportProblem="$(fExportProblems "${winExports}")"
			if [[ -n "${exportProblem}" ]]; then fTestFail "${exportProblem}"; fi
			fTestPass
		fi

		## Every DLL a program or library loads has to be one Windows has or one
		## in the zip, and one in the zip has to export what is asked of it.
		fId "${winArch}" x86_64=ErmS0zC arm64=ErmS0zD "Windows ${winArch} imports resolve"
		if ((! isLinux)); then
			fTestSkip "Linux only"
		elif ((! haveZip)); then
			fTestSkip "no zip, so package.bash made no Windows release"
		elif [[ -z "${winReadobj}" ]]; then
			fTestSkip "no llvm-readobj"
		else
			[[ -n "${winRoot}" ]] || fTestFail "there is no ${winZip}, or nothing in it."
			importProblems=()
			## The DLLs in the zip, lowercased, and what each exports.
			inZip=" "
			exported=()
			for pe in "${winRoot}"/bin/*.dll; do
				[[ -f "${pe}" ]] || continue
				dll="$(basename "${pe}" | tr '[:upper:]' '[:lower:]')"
				inZip+="${dll} "
				while read -r symbol; do exported["${dll}/${symbol}"]=1; done \
					< <("${winReadobj}" --coff-exports "${pe}" | awk '$1 == "Name:" { print $2 }')
			done
			for pe in "${winRoot}"/bin/*.exe "${winRoot}"/bin/*.dll; do
				[[ -f "${pe}" ]] || continue
				## A "dll -" line per DLL, then a "dll symbol" line per import.
				while read -r dll symbol; do
					if [[ "${symbol}" == "-" ]]; then
						if [[ ! "${dll}" =~ ${windowsDlls} ]] && [[ "${inZip}" != *" ${dll} "* ]]; then
							importProblems+=("$(basename "${pe}") loads ${dll}, which neither Windows nor the zip has")
						fi
					elif [[ "${inZip}" == *" ${dll} "* ]] && [[ -z "${exported["${dll}/${symbol}"]:-}" ]]; then
						importProblems+=("$(basename "${pe}") asks ${dll} for ${symbol}, which it does not export")
					fi
				done < <("${winReadobj}" --coff-imports "${pe}" | awk '
					$1 == "Name:" { dll = tolower($2); print dll " -"; next }
					$1 == "Symbol:" && dll != "" { print dll " " $2 }
					$1 == "}" { dll = "" }
				')
			done
			if ((${#importProblems[@]})); then
				importSample="$(printf '%s; ' "${importProblems[@]:0:3}")"
				fTestFail "${#importProblems[@]} imports cannot be met, such as: ${importSample%; }."
			fi
			fTestPass
		fi

		## Link only, with zig cc standing in for mingw gcc, against what the zip
		## has. The static line is the one zuid.h gives. x86_64 adds -lunwind,
		## which gcc would get from libgcc; arm64 has no unwinder to link, since
		## Wasmtime is in its DLL there. libzuid.a is named by path, since zig
		## cc's -lzuid finds the import library first, where mingw's ld finds
		## libzuid.a.
		if [[ "${winArch}" == "arm64" ]]; then
			links=("static:${winRoot}/lib/libzuid.a -L ${winRoot}/lib -lwasmtime ${winSystemLibs}")
		else
			links=("static:${winRoot}/lib/libzuid.a -L ${winRoot}/lib -lwasmtime ${winSystemLibs} -lunwind")
		fi
		links+=("shared:${winRoot}/lib/zuid.lib")
		for link in "${links[@]}"; do
			linkKind="${link%%:*}"
			read -r -a linkFlags <<< "${link#*:}"
			fId "${winArch}-${linkKind}" x86_64-static=ErmM9mU x86_64-shared=ErmM9mV arm64-static=ErmS0zG arm64-shared=ErmS0zH "capi_smoke.c, Windows ${winArch} ${linkKind}"
			if ((! isLinux)); then
				fTestSkip "Linux only"
				continue
			elif ((! haveZip)); then
				fTestSkip "no zip, so package.bash made no Windows release"
				continue
			fi
			[[ -n "${winRoot}" ]] || fTestFail "there is no ${winZip}, or nothing in it."
			smokeExe="${scratchDir}/smoke-windows-${winArch}-${linkKind}.exe"
			zig cc -target "${winTarget}" -I "${winRoot}/include" "${smokeSrc}" "${linkFlags[@]}" -o "${smokeExe}" \
				|| fTestFail "did not link."
			[[ "$(fPeHeader "${smokeExe}")" == "${machine} 0" ]] || fTestFail "it did not link as a ${winArch} Windows program."
			## The import table names each DLL as plain text.
			smokeImports="$(grep -aoiE 'zuid\.dll|wasmtime\.dll' "${smokeExe}" | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ' || true)"
			if [[ "${linkKind}" == "static" && "${smokeImports}" == *zuid.dll* ]]; then fTestFail "it loads zuid.dll rather than holding the library."; fi
			if [[ "${linkKind}" == "shared" && "${smokeImports}" != *zuid.dll* ]]; then fTestFail "it does not load zuid.dll."; fi
			if [[ "${winArch}-${linkKind}" == "arm64-static" && "${smokeImports}" != *wasmtime.dll* ]]; then fTestFail "it does not load wasmtime.dll."; fi
			fTestPass
		done
	done

	fId ErmS0zB "Windows x86_64 is plain x86-64"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveZip)); then
		fTestSkip "no zip, so package.bash made no Windows release"
	elif ((! haveObjdump)) || [[ "$(objdump --help 2>/dev/null || true)" != *pei-x86-64* ]]; then
		fTestSkip "no objdump that reads x86_64 Windows programs"
	elif [[ -z "${winReadobj}" || -z "${winPdbutil}" ]]; then
		fTestSkip "no llvm-readobj and llvm-pdbutil"
	else
		winRoot="$(find "${scratchDir}/windows-x86_64" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null || true)"
		local -r winPdb="${repoRoot}/dist/debug/${distPrefix}windows-x86_64/bin/zuid.pdb"
		[[ -n "${winRoot}" ]] || fTestFail "there is no x86_64 zip, or nothing in it."
		[[ -f "${winPdb}" ]] || fTestFail "there is no ${winPdb}, which names the functions built here."
		local winScan=""
		winScan="$(fX86FloorScan_Pe "${winReadobj}" "${winPdbutil}" "${winRoot}/bin/zuid.exe" "${winPdb}")"
		if [[ "${winScan%% *}" != "0" ]]; then
			fTestFail "${winScan%% *} functions use instructions past x86-64-v1, such as ${winScan#* }. package.bash has to name a target."
		fi
		## A PDB that names nothing would pass the scan above.
		[[ "$("${winPdbutil}" dump --symbols "${winPdb}" | grep -c ' S_[GL]PROC32 ' || true)" -gt 100 ]] \
			|| fTestFail "zuid.pdb names next to no functions, so the scan saw nothing."
		fTestPass
	fi

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The FreeBSD x86_64 release, cross-built on Linux from FreeBSD's own Wasmtime
## package. As with arm64, nothing here can run it; a FreeBSD machine does that by hand.
fStage_Package_FreeBSD(){  ## scratch dir

	local -r scratchDir="$1"
	local -r bsdRelease="${repoRoot}/dist/${distPrefix}freebsd-x86_64"
	local -r bsdTree="${scratchDir}/freebsd"
	local -i isLinux=0 haveReadelf=0 haveObjdump=0
	if [[ "$(uname -s)" == "Linux" ]];          then isLinux=1;     fi
	if command -v readelf >/dev/null 2>&1;      then haveReadelf=1; fi
	if command -v objdump >/dev/null 2>&1;      then haveObjdump=1; fi

	local bsdLib=""
	if ((isLinux)) && [[ -f "${bsdRelease}.tgz" ]]; then
		mkdir -p "${bsdTree}"
		tar -xzf "${bsdRelease}.tgz" -C "${bsdTree}"
		bsdLib="$(find "${bsdTree}" -mindepth 2 -maxdepth 2 -type d -name lib -print -quit)"
	fi

	## Zig leaves the ELF header's OS/ABI at System V, so that says nothing.
	## FreeBSD knows its programs by their ABI note and loader, and a shared
	## library by the libc it needs: libc.so.7, where Linux has libc.so.6.
	fId ErlUUiQ "FreeBSD build and tarball"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveReadelf)); then
		fTestSkip "no readelf"
	else
		[[ -n "${bsdLib}" ]] || fTestFail "there is no lib/ in ${bsdRelease}.tgz."
		local -ra bsdPrograms=("${bsdRelease}" "${bsdLib}/../bin/zuid")
		local -r bsdShared="$(find "${bsdLib}" -maxdepth 1 -type f -name 'libzuid.so.*' -print -quit)"
		local -a bsdFiles=("${bsdPrograms[@]}" "${bsdShared}" "${bsdLib}/libzuid.a" "${bsdLib}/libwasmtime.a" "${bsdLib}/libzstd.a" "${bsdLib}/../share/LICENSE-zstd.txt")
		local bsdFile="" machines=""
		for bsdFile in "${bsdFiles[@]}"; do
			[[ -f "${bsdFile}" ]] || fTestFail "${bsdFile:-the shared library} is missing."
		done
		machines="$(readelf -h "${bsdFiles[@]:0:6}" | awk '$1 == "Machine:" { $1 = ""; print substr($0, 2) }' | sort -u)"
		if [[ "${machines}" != "Advanced Micro Devices X86-64" ]]; then
			fTestFail "the binaries and libraries are for '${machines//$'\n'/, }'."
		fi
		for bsdFile in "${bsdPrograms[@]}"; do
			[[ "$(readelf -n "${bsdFile}")" == *"FreeBSD"*"NT_VERSION"* ]] || fTestFail "$(basename "${bsdFile}") has no FreeBSD ABI note."
			[[ "$(readelf -l "${bsdFile}")" == *"/libexec/ld-elf.so.1"* ]] || fTestFail "$(basename "${bsdFile}") does not ask for FreeBSD's loader."
		done
		[[ "$(readelf -d "${bsdShared}")" == *"[libc.so.7]"* ]] || fTestFail "$(basename "${bsdShared}") does not need FreeBSD's libc.so.7."
		grep -q "Meta Platforms" "${bsdLib}/../share/LICENSE-zstd.txt" || fTestFail "LICENSE-zstd.txt is not zstd's BSD license."
		fTestPass
	fi

	fId ErlUUiR "FreeBSD is plain x86-64"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveObjdump)); then
		fTestSkip "no objdump"
	else
		local -r bsdSymbols="${repoRoot}/dist/debug/${distPrefix}freebsd-x86_64/bin/zuid.debug"
		[[ -f "${bsdRelease}" ]] || fTestFail "there is no ${bsdRelease}."
		[[ -f "${bsdSymbols}" ]] || fTestFail "there is no ${bsdSymbols}, which names the functions built here."
		local bsdScan=""
		bsdScan="$(fX86FloorScan "${bsdRelease}" "${bsdSymbols}")"
		if [[ "${bsdScan%% *}" != "0" ]]; then
			fTestFail "${bsdScan%% *} functions use instructions past x86-64-v1, such as ${bsdScan#* }. package.bash has to name a target."
		fi
		fTestPass
	fi

	## FreeBSD versions libc's symbols by release: FBSD_1.7 is 14, FBSD_1.8 is
	## 15. A symbol from a newer one would keep the release off 14.
	local -r fbsdFloor="1.7"
	fId ErlUUiS "FreeBSD libc floor FBSD_${fbsdFloor}"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveReadelf)); then
		fTestSkip "no readelf"
	else
		[[ -f "${bsdRelease}" ]] || fTestFail "there is no ${bsdRelease}."
		local fbsdNewest=""
		fbsdNewest="$(readelf -W --dyn-syms "${bsdRelease}" | grep -o 'FBSD_[0-9.]*' | sort -u -V | tail -n 1 || true)"
		fbsdNewest="${fbsdNewest#FBSD_}"
		if [[ -z "${fbsdNewest}" ]]; then
			fTestFail "found no FreeBSD symbol versions in ${bsdRelease}."
		fi
		if [[ "$(printf '%s\n' "${fbsdNewest}" "${fbsdFloor}" | sort -V | tail -n 1)" != "${fbsdFloor}" ]]; then
			fTestFail "it needs FBSD_${fbsdNewest}."
		fi
		fTestPass
	fi

	## Link only, as for arm64. zuid.h gives the static line.
	local -r smokeSrc="${zigDir}/lib/test/capi_smoke.c"
	local -ra bsdCc=(zig cc -target "x86_64-freebsd.14.0")
	local -a links=(
		"static:-Wl,-Bstatic -lzuid -lwasmtime -lzstd -Wl,-Bdynamic -lunwind -lpthread -lm"
		"shared:-lzuid"
	)
	local link="" linkKind=""
	local -a linkFlags=()
	for link in "${links[@]}"; do
		linkKind="${link%%:*}"
		read -r -a linkFlags <<< "${link#*:}"
		fId "${linkKind}" static=ErlUUiT shared=ErlUUiU "capi_smoke.c, FreeBSD ${linkKind}"
		if ((! isLinux)); then
			fTestSkip "Linux only"
			continue
		fi
		[[ -n "${bsdLib}" ]] || fTestFail "there is no lib/ in ${bsdRelease}.tgz."
		"${bsdCc[@]}" -I "${bsdLib}/../include" "${smokeSrc}" -L "${bsdLib}" "${linkFlags[@]}" \
			-o "${scratchDir}/smoke-freebsd-${linkKind}" || fTestFail "did not link."
		if ((haveReadelf)) && [[ "$(readelf -l "${scratchDir}/smoke-freebsd-${linkKind}")" != *"/libexec/ld-elf.so.1"* ]]; then
			fTestFail "it did not link as a FreeBSD program."
		fi
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Debug info names the Zig install, its caches, the checkout and the home
## directory of whoever built it, and made every release file differ between
## two machines building one commit. So release binaries go out stripped, and
## their debug info goes to dist/debug/, which is never uploaded. Wasmtime's
## and zstd's archives go out as their projects publish them, so only the
## path rule applies to those.
fStage_Package_Stripped(){  ## scratch dir

	local -r scratchDir="$1"
	local -r distDir="${repoRoot}/dist"
	local -r unpackDir="${scratchDir}/stripped"

	local lister="" candidate=""
	for candidate in llvm-objdump llvm-objdump-21 llvm-objdump-20 llvm-objdump-19 llvm-objdump-18 llvm-objdump-17 llvm-objdump-16 objdump; do
		if command -v "${candidate}" >/dev/null 2>&1; then lister="${candidate}"; break; fi
	done

	local zigEnv="" zigLib="" zigCache=""
	zigEnv="$(zig env 2>/dev/null || true)"
	zigLib="$(sed -n 's/^ *\.lib_dir = "\(.*\)",$/\1/p' <<< "${zigEnv}")"
	zigCache="$(sed -n 's/^ *\.global_cache_dir = "\(.*\)",$/\1/p' <<< "${zigEnv}")"
	local -a grepArgs=(-e "${repoRoot}" -e ".zig-cache/")
	if [[ -n "${zigLib}" ]];                    then grepArgs+=(-e "$(dirname "${zigLib}")"); fi
	if [[ -n "${zigCache}" ]];                  then grepArgs+=(-e "${zigCache}");            fi
	## Wasmtime is built on GitHub's runners, and its build paths stay in
	## every binary that links it. A runner's home is a prefix of those, so
	## there it can't tell our paths from theirs. The checkout still can.
	local homeIsTheirs=""
	for candidate in "${zigDir}"/vendor/wasmtime*/lib/libwasmtime.a; do
		if [[ -n "${HOME:-}" && -f "${candidate}" ]] && LC_ALL=C grep -qaF "${HOME}/" "${candidate}"; then homeIsTheirs="${candidate}"; break; fi
	done
	if [[ -n "${homeIsTheirs}" ]]; then
		fEcho_Clean "Home .......: ${HOME} is in ${homeIsTheirs#"${zigDir}"/}, so only the checkout and Zig paths are looked for"
	elif [[ -n "${HOME:-}" && "${HOME}" != "/" ]]; then
		grepArgs+=(-e "${HOME}")
	fi

	fId EsZni4i "no local paths or debug info in the release"
	if [[ -z "${lister}" ]]; then
		fTestSkip "no objdump"
		return 0
	fi
	mkdir -p "${unpackDir}"
	local -a problems=()
	local asset="" assetName="" unpacked="" file="" name="" found="" sections=""
	local -i ours=0 assets=0
	while IFS= read -r asset; do
		assetName="$(basename "${asset}")"
		unpacked="${unpackDir}/${assetName}"
		mkdir -p "${unpacked}"
		case "${assetName}" in
			*.tgz) tar -xzf "${asset}" -C "${unpacked}" ;;
			*.zip) unzip -q "${asset}" -d "${unpacked}" ;;
			*.deb)
				if ! command -v dpkg-deb >/dev/null 2>&1; then continue; fi
				dpkg-deb -x "${asset}" "${unpacked}"
				;;
			*.rpm)
				if ! command -v rpm2cpio >/dev/null 2>&1 || ! command -v cpio >/dev/null 2>&1; then continue; fi
				( cd "${unpacked}" && rpm2cpio "${asset}" | cpio -idm --quiet )
				;;
			*) cp "${asset}" "${unpacked}/" ;;
		esac
		assets=$((assets + 1))
		ours=0
		while IFS= read -r file; do
			name="${file#"${unpacked}"/}"
			if [[ "${name}" == *.pdb ]]; then problems+=("${assetName}: ${name} is debug info"); fi
			found="$(LC_ALL=C grep -aoF -m 1 "${grepArgs[@]}" "${file}" || true)"
			if [[ -n "${found}" ]]; then problems+=("${assetName}: ${name} has ${found%%$'\n'*}"); fi
			fIsBinary "${file}" || continue
			case "${file##*/}" in libwasmtime.a|libzstd.a|wasmtime.dll|wasmtime.lib) continue ;; esac
			ours=$((ours + 1))
			if ! sections="$("${lister}" -h "${file}" 2>/dev/null)"; then
				problems+=("${assetName}: ${lister} cannot read ${name}")
				continue
			fi
			sections="$(awk '$1 ~ /^[0-9]+$/ && $2 ~ /^(\.z?debug|__debug|__DWARF)/ { print $2 }' <<< "${sections}" | sort -u | tr '\n' ' ')"
			if [[ -n "${sections}" ]]; then problems+=("${assetName}: ${name} has ${sections% }"); fi
		done < <(find "${unpacked}" -type f | sort)
		if ((ours == 0)); then problems+=("${assetName} has no binary built here to check"); fi
	done < <(find "${distDir}" -maxdepth 1 -type f ! -name '.*' ! -name checksums.txt | sort)
	if ((assets == 0)); then problems+=("there is nothing in dist/"); fi
	if ((${#problems[@]})); then
		fTestFail "${#problems[@]} problems, such as: $(printf '%s; ' "${problems[@]:0:4}")"
	fi
	fTestPass

	## Each one's debug info has to be in dist/debug/, and has to be that
	## build's, or an address from a crash cannot be looked up. A Mac keeps it
	## per CPU, since each slice is stripped before they are merged.
	local readobj="" pdbutil="" version=""
	for version in "" -21 -20 -19 -18 -17 -16; do
		if [[ -z "${readobj}" ]] && command -v "llvm-readobj${version}" >/dev/null 2>&1; then readobj="llvm-readobj${version}"; fi
		if [[ -z "${pdbutil}" ]] && command -v "llvm-pdbutil${version}" >/dev/null 2>&1; then pdbutil="llvm-pdbutil${version}"; fi
	done
	fId EsZni4j "debug info in dist/debug/"
	problems=()
	local release="" debugRoot="" debugFile="" sub="" arch="" want="" got=""
	local -a debugRoots=()
	local -i checked=0
	while IFS= read -r asset; do
		assetName="$(basename "${asset}")"
		release="${assetName%.*}"
		debugRoot="${distDir}/debug/${release}"
		[[ -d "${debugRoot}" ]] || { problems+=("there is no dist/debug/${release}/"); continue; }
		debugRoots=("${debugRoot}")
		if [[ "${release}" == *-darwin-universal ]]; then debugRoots=("${debugRoot}/x86_64" "${debugRoot}/arm64"); fi
		while IFS= read -r file; do
			name="${file##*/}"
			sub="$(basename "$(dirname "${file}")")"
			fIsBinary "${file}" || continue
			case "${name}" in libwasmtime.a|libzstd.a|wasmtime.dll|wasmtime.lib|zuid.lib) continue ;; esac
			for debugRoot in "${debugRoots[@]}"; do
				checked=$((checked + 1))
				arch="${debugRoot##*/}"
				case "${name}" in
					*.a)
						debugFile="${debugRoot}/${sub}/${name}.debug"
						if [[ "${release}" == *-darwin-universal ]]; then debugFile="${debugRoot}/${sub}/${name}"; fi
						if [[ ! -f "${debugFile}" ]] || [[ "$("${lister}" -h "${debugFile}" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^(\.z?debug|__debug|__DWARF)/' | wc -l)" -eq 0 ]]; then
							problems+=("${release}: no ${sub}/${name} with debug info beside it")
						fi
						;;
					*.exe|*.dll)
						## build.zig puts the DLL's PDB in lib/, since the command's is
						## zuid.pdb too.
						debugFile="${debugRoot}/bin/${name%.*}.pdb"
						if [[ "${name}" == *.dll ]]; then debugFile="${debugRoot}/lib/${name%.*}.pdb"; fi
						if [[ ! -f "${debugFile}" ]]; then
							problems+=("${release}: no PDB for ${sub}/${name}")
						elif [[ -n "${readobj}" && -n "${pdbutil}" ]]; then
							want="$("${readobj}" --coff-debug-directory "${file}" | awk '$1 == "PDBGUID:" { print $2; exit }')"
							got="$("${pdbutil}" dump --summary "${debugFile}" | awk '$1 == "GUID:" { print $2; exit }')"
							if [[ -z "${want}" || "${want}" != "${got}" ]]; then problems+=("${release}: ${sub}/${name} wants PDB ${want:-none}, and ${debugFile##*/} is ${got:-unreadable}"); fi
						fi
						;;
					*)
						if [[ "${release}" == *-darwin-universal ]]; then
							debugFile="${debugRoot}/${sub}/${name}.dSYM"
							want="$(dwarfdump --uuid --arch="${arch}" "${file}" 2>/dev/null | awk '$1 == "UUID:" { print $2; exit }' || true)"
							got="$(dwarfdump --uuid "${debugFile}" 2>/dev/null | awk '$1 == "UUID:" { print $2; exit }' || true)"
						else
							## The stripped file keeps its section table, so the
							## code's address and size have to agree.
							debugFile="${debugRoot}/${sub}/${name}.debug"
							want="$("${lister}" -h "${file}" 2>/dev/null | awk '$2 == ".text" { print $3, $4; exit }' || true)"
							got="$("${lister}" -h "${debugFile}" 2>/dev/null | awk '$2 == ".text" { print $3, $4; exit }' || true)"
							if [[ "$("${lister}" -h "${debugFile}" 2>/dev/null | awk '$2 == ".debug_info"' | wc -l)" -eq 0 ]]; then got="no debug info"; fi
							if [[ "$(nm "${debugFile}" 2>/dev/null | awk '$2 ~ /^[tT]$/' | wc -l)" -lt 100 ]]; then got="next to no function names"; fi
						fi
						if [[ ! -e "${debugFile}" ]]; then
							problems+=("${release}: no ${debugFile#"${distDir}/"}")
						elif [[ -z "${want}" || "${want}" != "${got}" ]]; then
							problems+=("${release}: ${debugFile#"${distDir}/"} is not for ${sub}/${name}: ${want:-nothing} against ${got:-nothing}")
						fi
						;;
				esac
			done
		done < <(find "${unpackDir}/${assetName}" -mindepth 3 -maxdepth 3 -type f \( -path '*/bin/*' -o -path '*/lib/*' \) | sort)
	done < <(find "${distDir}" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.zip' \) | sort)
	if ((checked == 0)); then problems+=("found no binary built here in a tarball or zip"); fi
	if ((${#problems[@]})); then
		fTestFail "${#problems[@]} problems, such as: $(printf '%s; ' "${problems[@]:0:4}")"
	fi
	fTestPass

	## The backup archives dist/ on every run, so an ELF .debug file keeps only
	## DWARF, packed. A whole unstripped libzuid.a went there until 20261013.
	fId EsbEsag "debug files are packed DWARF only"
	problems=()
	checked=0
	local readelf=""
	for version in "" -21 -20 -19 -18 -17 -16; do
		if [[ -z "${readelf}" ]] && command -v "llvm-readelf${version}" >/dev/null 2>&1; then readelf="llvm-readelf${version}"; fi
	done
	if [[ -z "${readelf}" ]]; then fTestSkip "no llvm-readelf"; return 0; fi
	local sections=""
	while IFS= read -r file; do
		## Windows .debug files are COFF, which llvm-objcopy won't pack.
		"${readelf}" -h "${file}" 2>/dev/null | grep -q 'ELF Header' || continue
		checked=$((checked + 1))
		## Name, type, then flags in the 7th column once the [ N] is gone.
		sections="$("${readelf}" -S -W "${file}" 2>/dev/null | sed -n 's/^ *\[ *[0-9]*\] *//p' || true)"
		if awk '$1 ~ /^\.text/ && $2 == "PROGBITS" { hit = 1 } END { exit !hit }' <<< "${sections}"; then
			problems+=("${file#"${distDir}/"} has code in it")
		fi
		if ! awk '$1 == ".debug_info" { n++; if ($7 !~ /C/) bad = 1 } END { exit !(n && !bad) }' <<< "${sections}"; then
			problems+=("${file#"${distDir}/"} has an unpacked or no .debug_info")
		fi
	done < <(find "${distDir}/debug" -type f \( -name '*.debug' -o -name '*.a' \) ! -path '*.dSYM/*' | sort)
	if ((checked == 0)); then fTestSkip "no ELF debug files, as on a Mac"; return 0; fi
	if ((${#problems[@]})); then
		fTestFail "${#problems[@]} problems, such as: $(printf '%s; ' "${problems[@]:0:4}")"
	fi
	fTestPass

}


## Two machines building one commit have to make the same release. A second
## run stands in for the second machine: later, under another umask, and where
## a user namespace is allowed, as root on another host name. The Zig cache is
## warm by now, so this mostly times the stripping and archiving. Paths and
## Zig's own output aren't covered, since this box has only one of each.
fStage_Package_Again(){  ## scratch dir, version

	local -r scratchDir="$1" version="$2"
	local -r distDir="${repoRoot}/dist" againDir="${scratchDir}/again"
	local -r packager="${utilityDir}/package.bash"

	fId Esa8LVS "repackaging gives the same bytes"
	local how="umask 077"
	local -a runner=(bash -c 'umask 077 && exec "$@"' again)
	if unshare -r -u true 2>/dev/null; then
		how="umask 077, as root on host zuid-again"
		runner=(unshare -r -u bash -c 'hostname zuid-again && umask 077 && exec "$@"' again)
	fi
	if ! ZUID_JOBS="${buildJobs}" "${runner[@]}" "${packager}" --out "${againDir}" --version "v${version}" >"${scratchDir}/again.log" 2>&1; then
		fTestFail "the second run failed (${how}): $(tail -c 400 "${scratchDir}/again.log")"
	fi
	local -a problems=()
	local name=""
	local -i compared=0
	while IFS= read -r name; do
		compared=$((compared + 1))
		if [[ ! -f "${againDir}/${name}" ]]; then
			problems+=("${name} is missing")
		elif ! cmp -s "${distDir}/${name}" "${againDir}/${name}"; then
			problems+=("${name} differs")
		fi
	done < <(cd "${distDir}" && find . -type f ! -name '.zuid-package-dir' | sed 's|^\./||' | LC_ALL=C sort)
	if ((compared == 0)); then problems+=("there is nothing in dist/"); fi
	if [[ "$(cd "${againDir}" && find . -type f | wc -l)" != "$(cd "${distDir}" && find . -type f | wc -l)" ]]; then
		problems+=("the two runs made a different number of files")
	fi
	if ((${#problems[@]})); then
		fTestFail "${#problems[@]} of ${compared} files differ (${how}): $(printf '%s; ' "${problems[@]}")"
	fi
	fTestPass

	## nfpm's version is in every .deb and .rpm it writes, so a host on another
	## one makes packages that differ from the container's. Not fatal: a clone
	## elsewhere may have any nfpm at all.
	fId EsbF9Jy "host nfpm matches the pin"
	local pinned="" have=""
	pinned="$(sed -n 's/^ARG NFPM_VER=//p' "${repoRoot}/cicd/container/Dockerfile" || true)"
	if ! command -v nfpm >/dev/null 2>&1; then fTestSkip "no nfpm"; return 0; fi
	have="$(nfpm --version 2>/dev/null | awk '$1 == "GitVersion:" { sub(/^v/, "", $2); print $2; exit }' || true)"
	if [[ -z "${pinned}" ]]; then fTestFail "no ARG NFPM_VER in cicd/container/Dockerfile"; fi
	if [[ "${have}" != "${pinned}" ]]; then fTestSkip "nfpm ${have:-of unknown version} here, and the container pins ${pinned}, so its .deb and .rpm differ"; return 0; fi
	fTestPass

}


## ELF, PE, Mach-O, universal Mach-O, or an ar archive.
fIsBinary(){  ## file
	local magic=""
	magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n' || true)"
	case "${magic}" in
		7f454c46|4d5a*|cffaedfe|cefaedfe|cafebabe|213c6172) return 0 ;;
	esac
	return 1
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every tarball has libwasmtime.a, and every command has Wasmtime linked in,
## so each one goes with Wasmtime's license. The Windows zips are checked with
## their other files. The GPLv2 clause is in Wasmtime's text and not in the
## plain Apache license the module has.
fStage_Package_Licenses(){  ## scratch dir

	local -r scratchDir="$1"
	local -r wasmtimeMark="Combined Software"
	local -i isLinux=0 isMac=0 haveNfpm=0
	if [[ "$(uname -s)" == "Linux" ]];  then isLinux=1; fi
	if [[ "$(uname -s)" == "Darwin" ]]; then isMac=1;   fi
	if command -v nfpm >/dev/null 2>&1; then haveNfpm=1; fi

	local archive="" kind="" arch="" file="" found="" text="" tree="" packageList=""
	for archive in linux-x86_64 linux-arm64 freebsd-x86_64 darwin-universal deb-x86_64 deb-arm64 rpm-x86_64 rpm-arm64; do
		kind="${archive%%-*}"; arch="${archive#*-}"
		fId "${archive}" linux-x86_64=ErmYT8O linux-arm64=ErmYT8P freebsd-x86_64=ErmYT8Q darwin-universal=ErmYT8R deb-x86_64=ErmYT8S deb-arm64=ErmYT8T rpm-x86_64=ErmYT8U rpm-arm64=ErmYT8V "Wasmtime license in ${archive}"
		case "${kind}" in
			darwin) if ((! isMac));   then fTestSkip "macOS only"; continue; fi ;;
			*)      if ((! isLinux)); then fTestSkip "Linux only"; continue; fi ;;
		esac
		case "${kind}" in
			linux|freebsd|darwin)
				found="${repoRoot}/dist/${distPrefix}${archive}.tgz"
				[[ -f "${found}" ]] || fTestFail "there is no $(basename "${found}")."
				tree="${scratchDir}/license-${archive}"
				mkdir -p "${tree}"
				tar -xzf "${found}" -C "${tree}"
				file="$(find "${tree}" -path '*/share/LICENSE-wasmtime.txt' -print -quit)"
				[[ -n "${file}" ]] || fTestFail "$(basename "${found}") has no share/LICENSE-wasmtime.txt."
				grep -q "${wasmtimeMark}" "${file}" || fTestFail "share/LICENSE-wasmtime.txt is not Wasmtime's license."
				;;
			deb|rpm)
				if ((! haveNfpm)); then fTestSkip "no nfpm, so package.bash made no packages"; continue; fi
				## Each format's own word for the architecture.
				case "${archive}" in
					deb-x86_64) found="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid_*_amd64.deb' -print -quit)" ;;
					deb-arm64)  found="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid_*_arm64.deb' -print -quit)" ;;
					rpm-x86_64) found="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid-*.x86_64.rpm' -print -quit)" ;;
					rpm-arm64)  found="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid-*.aarch64.rpm' -print -quit)" ;;
				esac
				[[ -n "${found}" ]] || fTestFail "the ${arch} .${kind} is missing from dist/."
				if [[ "${kind}" == "deb" ]]; then
					if ! command -v dpkg-deb >/dev/null 2>&1; then fTestSkip "no dpkg-deb"; continue; fi
					packageList="$(dpkg-deb --fsys-tarfile "${found}" | tar -t)"
					text="$(dpkg-deb --fsys-tarfile "${found}" | tar -xO ./usr/share/doc/zuid/LICENSE-wasmtime.txt 2>/dev/null || true)"
				else
					if ! command -v rpm2cpio >/dev/null 2>&1 || ! command -v cpio >/dev/null 2>&1; then fTestSkip "no rpm2cpio or cpio"; continue; fi
					packageList="$(rpm2cpio "${found}" | cpio -it --quiet)"
					text="$(rpm2cpio "${found}" | cpio -i --quiet --to-stdout ./usr/share/licenses/zuid/LICENSE-wasmtime.txt 2>/dev/null || true)"
				fi
				[[ "${text}" == *"${wasmtimeMark}"* ]] || fTestFail "$(basename "${found}") has no Wasmtime license."
				## The module is linked in too, under Apache with its NOTICE.
				for file in LICENSE-module.txt NOTICE.txt; do
					[[ "${packageList}" == *"/zuid/${file}"* ]] || fTestFail "$(basename "${found}") has no ${file}."
				done
				;;
		esac
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The Linux arm64 release, cross-built beside the x86_64 one. Nothing here can
## run it, so these check what it is, what it asks of the machine, and that the
## C module in its tarball links. Running it is left to an arm64 machine.
fStage_Package_Arm64(){  ## scratch dir, glibc floor

	local -r scratchDir="$1" glibcFloor="$2"
	local -r armRelease="${repoRoot}/dist/${distPrefix}linux-arm64"
	local -r armTree="${scratchDir}/arm64"
	local -i isLinux=0 haveReadelf=0 haveObjdump=0
	if [[ "$(uname -s)" == "Linux" ]];          then isLinux=1;     fi
	if command -v readelf >/dev/null 2>&1;      then haveReadelf=1; fi
	if command -v objdump >/dev/null 2>&1;      then haveObjdump=1; fi

	## The tarball's own top directory has the version in its name, so find it rather
	## than rebuild its name.
	local armLib=""
	if ((isLinux)) && [[ -f "${armRelease}.tgz" ]]; then
		mkdir -p "${armTree}"
		tar -xzf "${armRelease}.tgz" -C "${armTree}"
		armLib="$(find "${armTree}" -mindepth 2 -maxdepth 2 -type d -name lib -print -quit)"
	fi

	fId ErgjCkT "Linux arm64 build and packages"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveReadelf)); then
		fTestSkip "no readelf"
	else
		[[ -n "${armLib}" ]] || fTestFail "there is no lib/ in ${armRelease}.tgz."
		local -a armFiles=("${armRelease}" "${armLib}/../bin/zuid" "${armLib}/libzuid.a" "${armLib}/libwasmtime.a")
		armFiles+=("$(find "${armLib}" -maxdepth 1 -type f -name 'libzuid.so.*' -print -quit)")
		local armFile="" machines=""
		for armFile in "${armFiles[@]}"; do
			[[ -f "${armFile}" ]] || fTestFail "${armFile:-the shared library} is missing."
		done
		machines="$(readelf -h "${armFiles[@]}" | awk '$1 == "Machine:" { $1 = ""; print substr($0, 2) }' | sort -u)"
		if [[ "${machines}" != "AArch64" ]]; then
			fTestFail "the binaries and libraries are for '${machines//$'\n'/, }'."
		fi
		## nfpm names each package with that format's word for the architecture.
		if command -v nfpm >/dev/null 2>&1; then
			local deb="" rpm=""
			deb="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid_*_arm64.deb' -print -quit)"
			rpm="$(find "${repoRoot}/dist" -maxdepth 1 -name 'zuid-*.aarch64.rpm' -print -quit)"
			[[ -n "${deb}" && -n "${rpm}" ]] || fTestFail "the arm64 .deb or .rpm is missing from dist/."
			if command -v dpkg-deb >/dev/null 2>&1 && [[ "$(dpkg-deb -f "${deb}" Architecture)" != "arm64" ]]; then
				fTestFail "$(basename "${deb}") says its architecture is '$(dpkg-deb -f "${deb}" Architecture)'."
			fi
			if command -v rpm >/dev/null 2>&1 && [[ "$(rpm -qp --qf '%{ARCH}' "${rpm}" 2>/dev/null)" != "aarch64" ]]; then
				fTestFail "$(basename "${rpm}") says its architecture is '$(rpm -qp --qf '%{ARCH}' "${rpm}" 2>/dev/null)'."
			fi
		fi
		fTestPass
	fi

	## The arm64 twin of the x86_64 check. Zig's baseline for arm64 Linux is plain
	## armv8-a, so code built here must use nothing a later extension added. The
	## pointer-authentication instructions that sit in the hint space are allowed,
	## since an older CPU runs them as no-ops. Rust and C++ are left out for the
	## same reason as before, and so are the __aarch64_ atomics helpers, which ask
	## the CPU before they use LSE.
	local armObjdump="" candidate=""
	for candidate in llvm-objdump llvm-objdump-21 llvm-objdump-20 llvm-objdump-19 llvm-objdump-18 llvm-objdump-17 llvm-objdump-16; do
		if command -v "${candidate}" >/dev/null 2>&1; then armObjdump="${candidate}"; break; fi
	done
	if [[ -z "${armObjdump}" ]] && ((haveObjdump)) && [[ "$(objdump --help 2>/dev/null || true)" == *elf64-littleaarch64* ]]; then
		armObjdump="objdump"
	fi
	fId ErgjCkU "Linux arm64 is plain armv8-a"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif [[ -z "${armObjdump}" ]]; then
		fTestSkip "no objdump that reads arm64"
	else
		local -r armSymbols="${repoRoot}/dist/debug/${distPrefix}linux-arm64/bin/zuid.debug"
		[[ -f "${armRelease}" ]] || fTestFail "there is no ${armRelease}."
		[[ -f "${armSymbols}" ]] || fTestFail "there is no ${armSymbols}, which names the functions built here."
		local armScan=""
		armScan="$(fDisassemble "${armObjdump}" "${armRelease}" "${armSymbols}" | awk '
			/^[0-9a-f]+ <.*>:$/ { fn = $2; gsub(/^<|>:$/, "", fn); skip = (fn ~ /^_?_(ZN|R[0-9]*[BCIMNXY])/ || fn ~ /^__aarch64_/); next }
			skip || (fn in seen) || NF < 2 { next }
			$2 ~ /^(cas|ld(add|clr|eor|set|[su]max|[su]min)|st(add|clr|eor|set|[su]max|[su]min)|swp|crc32|[su]dot|usdot|sudot|sqrdml|ldap|stlur|aes|sha1|sha256|sha512|sm3|sm4|eor3|bcax|rax1|xar|fjcvtzs|fcmla|fcadd|frint(32|64)|reta[ab]|bra[ab]|blra[ab]|ldra[ab]|eret[ab]|pac[id][ab]$|aut[id][ab]$|pacga|xpac[id]$|irg|stg|st2g|stzg|ldg|cfinv|rmif|setf|axflag|xaflag|ld64b|st64b|wfet|wfit|bf(cvt|dot|mmla|mlal)|[su]mmla|usmmla)/ || $0 ~ /[[:space:]][zp][0-9]+(\.[bhsdq])?[,[:space:]]/ {
				seen[fn] = 1; if (++count <= 3) names = names " " fn " (" $2 ")"
			}
			END { print count + 0 names }
		')"
		if [[ "${armScan%% *}" != "0" ]]; then
			fTestFail "${armScan%% *} functions use instructions past armv8-a, such as ${armScan#* }. package.bash has to name a target."
		fi
		fTestPass
	fi

	## readelf, not objdump: GNU objdump on another architecture may not read it.
	fId ErgjCkV "Linux arm64 needs glibc ${glibcFloor} at most"
	if ((! isLinux)); then
		fTestSkip "Linux only"
	elif ((! haveReadelf)); then
		fTestSkip "no readelf"
	else
		[[ -f "${armRelease}" ]] || fTestFail "there is no ${armRelease}."
		local glibcNewest=""
		glibcNewest="$(readelf -W --dyn-syms "${armRelease}" | grep -o 'GLIBC_[0-9.]*' | sort -u -V | tail -n 1 || true)"
		glibcNewest="${glibcNewest#GLIBC_}"
		if [[ -z "${glibcNewest}" ]]; then
			fTestFail "found no glibc symbol versions in ${armRelease}."
		fi
		if [[ "$(printf '%s\n' "${glibcNewest}" "${glibcFloor}" | sort -V | tail -n 1)" != "${glibcFloor}" ]]; then
			fTestFail "it needs glibc ${glibcNewest}."
		fi
		fTestPass
	fi

	## Link only, against what's in the tarball: there is no arm64 machine here
	## to run the result. zig cc stands in for an arm64 compiler, so it needs
	## -lunwind where gcc would bring libgcc.
	local -r smokeSrc="${zigDir}/lib/test/capi_smoke.c"
	local -ra armCc=(zig cc -target "aarch64-linux-gnu.${glibcFloor}")
	local -a links=(
		"static:-Wl,-Bstatic -lzuid -lwasmtime -Wl,-Bdynamic -lunwind -lpthread -ldl -lm"
		"shared:-lzuid"
	)
	local link="" linkKind="" linkMachine=""
	local -a linkFlags=()
	for link in "${links[@]}"; do
		linkKind="${link%%:*}"
		read -r -a linkFlags <<< "${link#*:}"
		fId "${linkKind}" static=ErgjCkW shared=ErgjCkX "capi_smoke.c, Linux arm64 ${linkKind}"
		if ((! isLinux)); then
			fTestSkip "Linux only"
			continue
		fi
		[[ -n "${armLib}" ]] || fTestFail "there is no lib/ in ${armRelease}.tgz."
		"${armCc[@]}" -I "${armLib}/../include" "${smokeSrc}" -L "${armLib}" "${linkFlags[@]}" \
			-o "${scratchDir}/smoke-arm64-${linkKind}" || fTestFail "did not link."
		if ((haveReadelf)); then
			linkMachine="$(readelf -h "${scratchDir}/smoke-arm64-${linkKind}" | awk '$1 == "Machine:" { print $2 }')"
			[[ "${linkMachine}" == "AArch64" ]] || fTestFail "it linked for '${linkMachine}'."
		fi
		fTestPass
	done

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The one place the version lives. Empty output is an error.
fCoreVersion(){
	local version=""
	version="$(sed -n 's/^pub const version = "\([^"]*\)".*/\1/p' "${zigDir}/lib/src/core.zig" 2>/dev/null || true)"
	[[ -n "${version}" ]] || return 1
	printf '%s\n' "${version}"
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Everything --publish needs that can be known before the build, so a refusal
## comes in seconds rather than after it. ZUID_GH names another gh, which is
## how the tests run this without reaching GitHub.
fPublish_Preflight(){

	local -r ghCmd="${ZUID_GH:-gh}"
	_fMustBeInPath curl
	command -v "${ghCmd}" >/dev/null 2>&1 || fThrowError "--publish creates the release with gh, which is not installed."  "${FUNCNAME[0]}"
	fGh auth status >/dev/null 2>&1 || fThrowError "gh is not logged in. Run 'gh auth login' first."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" != "${releaseBranch}" ]]; then
		fThrowError "Releases come from '${releaseBranch}' only, and this is '${branch}'."  "${FUNCNAME[0]}"
	fi
	if [[ -n "$(git -C "${repoRoot}" status --porcelain)" ]]; then
		fThrowError "The tree has uncommitted changes. A release is built from a commit, so commit or stash them first."  "${FUNCNAME[0]}"
	fi

	## The tag goes on what the remote already has, or the release would point
	## at a commit nobody else can fetch.
	publishRemote="$(git -C "${repoRoot}" config "branch.${branch}.remote" || true)"
	local -r upstream="$(git -C "${repoRoot}" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
	if [[ -z "${publishRemote}" ]] || [[ -z "${upstream}" ]]; then
		fThrowError "'${branch}' tracks no remote branch, so there is nowhere to push the tags."  "${FUNCNAME[0]}"
	fi
	publishHead="$(git -C "${repoRoot}" rev-parse HEAD)"
	if [[ "${publishHead}" != "$(git -C "${repoRoot}" rev-parse "${upstream}")" ]]; then
		fThrowError "HEAD is not what ${upstream} has. Push or pull first."  "${FUNCNAME[0]}"
	fi

	publishVersion="$(fCoreVersion || true)"
	if [[ ! "${publishVersion}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
		fThrowError "zig/lib/src/core.zig's version '${publishVersion}' is not a release version."  "${FUNCNAME[0]}"
	fi

	local remoteTags=""
	remoteTags="$(git -C "${repoRoot}" ls-remote --tags "${publishRemote}")" || fThrowError "Could not list the tags on ${publishRemote}."  "${FUNCNAME[0]}"
	local tag=""
	for tag in "v${publishVersion}" "go/v${publishVersion}"; do
		if git -C "${repoRoot}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null \
			|| [[ $'\n'"${remoteTags}"$'\n' == *$'\t'"refs/tags/${tag}"$'\n'* ]]; then
			fThrowError "Tag ${tag} already exists. Bump the version in zig/lib/src/core.zig first."  "${FUNCNAME[0]}"
		fi
	done

	## The notes link each download by its full address. gh is asked, so it is
	## the same repo the release goes to.
	publishRepoUrl="$(cd "${repoRoot}" && fGh repo view --json url --jq .url 2>/dev/null || true)"
	if [[ ! "${publishRepoUrl}" =~ ^https://[A-Za-z0-9./_-]+$ ]]; then
		fThrowError "gh cannot tell which GitHub repo this is, so the notes would have no download links. Run 'gh repo set-default' first."  "${FUNCNAME[0]}"
	fi

	fEcho_Clean "Publish ....: v${publishVersion} from ${branch} at ${publishHead:0:12}, to ${publishRepoUrl}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## One release from this machine's dist/ and the files copied in from the
## others, with one checksums.txt over all of it. Nothing is tagged or pushed
## until the plan has been shown and agreed to.
fStage_Publish(){

	fSection "Publish"

	local -r tag="v${publishVersion}"
	local -r goTag="go/v${publishVersion}"
	local -r distDir="${repoRoot}/dist"
	local -r stageDir="${distDir}/release"

	## The build ran since the preflight. The demo render is the one tracked
	## file a run rewrites, and no asset includes it.
	if [[ "$(git -C "${repoRoot}" rev-parse HEAD)" != "${publishHead}" ]]; then
		fThrowError "HEAD moved during the run. Nothing was published."  "${FUNCNAME[0]}"
	fi
	if [[ -n "$(git -C "${repoRoot}" status --porcelain -- . ':!assets/demo.gif')" ]]; then
		fThrowError "Files changed during the run. Nothing was published."  "${FUNCNAME[0]}"
	fi

	## dist/ was emptied by this run's packaging, so the stage directory is new
	## unless something else made it. Hard links where they work.
	mkdir "${stageDir}" || fThrowError "'${stageDir}' already exists, so it is not this run's."  "${FUNCNAME[0]}"
	## GitHub turns anything outside [A-Za-z0-9._-] in an asset name into '.',
	## so the name is changed here, before hashing, to match what it will serve.
	local source="" name=""
	local -i fromIncoming=0
	while IFS= read -r source; do
		name="$(basename "${source}")"
		name="${name//[^A-Za-z0-9._-]/.}"
		if [[ -e "${stageDir}/${name}" ]]; then
			fThrowError "Two assets would be named '${name}'. Remove one from dist-incoming/."  "${FUNCNAME[0]}"
		fi
		ln "${source}" "${stageDir}/${name}" 2>/dev/null || cp "${source}" "${stageDir}/${name}"
		if [[ "${source}" == "${incomingDir}"/* ]]; then fromIncoming=$((fromIncoming + 1)); fi
	done < <(
		find "${distDir}" -maxdepth 1 -type f ! -name '.*' ! -name checksums.txt | sort
		if [[ -d "${incomingDir}" ]]; then find "${incomingDir}" -maxdepth 1 -type f ! -name '.*' ! -name checksums.txt | sort; fi
	)

	local -a assets=()
	local file=""
	for file in "${stageDir}"/*; do
		if [[ -f "${file}" ]]; then assets+=("${file##*/}"); fi
	done
	((${#assets[@]})) || fThrowError "Nothing to publish in dist/ or dist-incoming/."  "${FUNCNAME[0]}"

	## A tarball built from another version unpacks to another directory name,
	## which is how a stale copy from the Mac shows.
	local asset="" topDir=""
	for asset in "${assets[@]}"; do
		[[ "${asset}" == *.tgz ]] || continue
		topDir="$(tar -tzf "${stageDir}/${asset}" 2>/dev/null | awk -F/ 'NR == 1 { print $1 }' || true)"
		if [[ "${topDir}" != "zuid-${tag}" ]]; then
			fThrowError "${asset} unpacks to '${topDir}/', not 'zuid-${tag}/', so it was built from another version."  "${FUNCNAME[0]}"
		fi
	done

	local -a missing=()
	for asset in "${releaseAssets[@]}"; do
		asset="${distPrefix}${asset}"
		[[ -e "${stageDir}/${asset}" ]] || missing+=("${asset}")
	done
	if ((${#missing[@]})) && ((! allowPartial)); then
		fThrowError "No asset for: ${missing[*]}. Copy them into dist-incoming/, or pass --allow-partial to publish without them."  "${FUNCNAME[0]}"
	fi

	local -a sha256=(sha256sum)
	command -v sha256sum >/dev/null 2>&1 || sha256=(shasum -a 256)
	local sums=""
	sums="$(cd "${stageDir}" && "${sha256[@]}" "${assets[@]}")" || fThrowError "Could not hash the assets."  "${FUNCNAME[0]}"
	printf '%s\n' "${sums}" > "${stageDir}/checksums.txt"

	## The changelog's own section for this version, up to the next one.
	local notes=""
	if [[ -f "${repoRoot}/changelog.md" ]]; then
		notes="$(TAG="${tag}" awk '
			/^## / { if (inside) exit; split($0, words, " "); inside = (words[2] == ENVIRON["TAG"]); next }
			inside { print }
		' "${repoRoot}/changelog.md")"
	fi

	local downloads="" notesFrom="changelog.md, section ${tag}, then the download table"
	downloads="$(fPublish_Downloads "${publishRepoUrl}/releases/download/${tag}" "${assets[@]}")"
	if [[ -n "${notes//[[:space:]]/}" ]]; then
		notes+=$'\n\n'"${downloads}"
	else
		notes="${downloads}"
		notesFrom="the download table only - changelog.md has no section for ${tag}"
	fi

	## The build number, read from the release binary, so it's the one users see.
	local buildLine=""
	if [[ -x "${repoRoot}/dist/${distPrefix}linux-x86_64" ]]; then
		buildLine="$("${repoRoot}/dist/${distPrefix}linux-x86_64" --version 2>/dev/null | sed -n '1s/^\([^ ]*\) (build \([^)]*\))$/zuid v\1 build \2/p' || true)"
	fi
	if [[ -n "${buildLine}" ]]; then notes="${buildLine}"$'\n\n'"${notes}"; fi

	local prerelease=""
	if [[ "${publishVersion}" == *-* ]]; then prerelease=" (prerelease)"; fi
	fEcho_Clean "Release ....: ${tag}${prerelease}"
	fEcho_Clean "Tags .......: ${tag} and ${goTag} on ${publishHead:0:12}, pushed to ${publishRemote}"
	fEcho_Clean "Assets .....: ${#assets[@]}, ${fromIncoming} of them from dist-incoming/, plus checksums.txt"
	for asset in "${assets[@]}"; do fEcho_Clean "               ${asset}"; done
	if ((${#missing[@]})); then fEcho_Clean "Missing ....: ${missing[*]}"; fi
	fEcho_Clean "Notes ......: ${notesFrom}"

	## Anything but a yes is a no, an empty or missing answer included.
	if ((! doQuietly)); then
		local answer=""
		fEcho_Clean
		read -r -p "  Publish it? [y/N] " answer || true
		if [[ "${answer,,}" != "y" ]] && [[ "${answer,,}" != "yes" ]]; then
			fThrowError "Not published. Nothing was tagged or pushed."  "${FUNCNAME[0]}"
		fi
	fi

	git -C "${repoRoot}" tag -a "${tag}"   -m "${tag}"   "${publishHead}"
	## GitHub lists this beside the releases, so say what it is.
	git -C "${repoRoot}" tag -a "${goTag}" -m "Go module tag for ${tag}" "${publishHead}"
	if ! git -C "${repoRoot}" push --atomic "${publishRemote}" "refs/tags/${tag}" "refs/tags/${goTag}"; then
		git -C "${repoRoot}" tag -d "${tag}" "${goTag}" >/dev/null
		fThrowError "Could not push the tags, so nothing was published. The local ones were removed again."  "${FUNCNAME[0]}"
	fi

	local -a ghArgs=(release create "${tag}" --verify-tag --title "${tag}" --notes "${notes}")
	if [[ -n "${prerelease}" ]]; then ghArgs+=(--prerelease); fi
	for asset in "${assets[@]}" checksums.txt; do ghArgs+=("${stageDir}/${asset}"); done
	if ! (cd "${repoRoot}" && fGh "${ghArgs[@]}"); then
		fThrowError "Both tags are pushed, but the release was not created. Run 'gh release create ${tag} --verify-tag' with the files in dist/release/, or delete both tags from ${publishRemote} and publish again."  "${FUNCNAME[0]}"
	fi

	## The tag shows before the assets do, for a minute or so.
	local url=""
	url="$(cd "${repoRoot}" && fGh release view "${tag}" --json assets --jq '.assets[] | select(.name == "checksums.txt") | .url' 2>/dev/null || true)"
	[[ -n "${url}" ]] || fThrowError "${tag} is released, but gh lists no checksums.txt on it."  "${FUNCNAME[0]}"
	local -i tries=1
	until curl -fsSL -o /dev/null "${url}" 2>/dev/null; do
		if ((tries >= 30)); then
			fThrowError "${tag} is released, but ${url} still does not answer after five minutes. Check it by hand."  "${FUNCNAME[0]}"
		fi
		tries=$((tries + 1))
		sleep 10
	done
	fEcho_Clean "Download ...: ${url}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The downloads for the release notes: one row per OS, one column per CPU. HTML,
## since the macOS file is for both CPUs and a markdown table cannot span cells.
## A file this cannot place is listed under the table rather than guessed at.
fPublish_Downloads(){  ## download URL, asset...

	local -r baseUrl="$1"; shift
	local -ra osOrder=("linux" "darwin" "windows" "freebsd")
	local -rA osTitles=([linux]="Linux" [darwin]="macOS" [windows]="Windows" [freebsd]="FreeBSD")
	local -ra cpuOrder=("x86_64" "arm64")
	## macOS has one universal file, so its row is one cell even when it is missing.
	local -rA universalOnly=([darwin]=1)
	local -A cells=()
	local -a ranked=() others=()
	local asset="" rank="" words="" os="" cpu="" cell="" row=""

	## Archives first in a cell, then the bare binary, then the packages. The
	## version has dots too, so a bare binary is one with none after its last '-'.
	for asset in "$@"; do
		case "${asset}" in
			*.tgz|*.tar.*|*.zip) rank=1 ;;
			*.exe)               rank=2 ;;
			*.deb)               rank=3 ;;
			*.rpm)               rank=4 ;;
			*)                   rank=2; [[ "${asset##*-}" != *.* ]] || rank=5 ;;
		esac
		ranked+=("${rank} ${asset}")
	done
	mapfile -t ranked < <(printf '%s\n' "${ranked[@]}" | LC_ALL=C sort)

	for asset in "${ranked[@]}"; do
		asset="${asset#* }"
		[[ -n "${asset}" ]] || continue
		## Whole words only, split where the names split: x86_64 is "x86 64".
		words=" ${asset//[-_.]/ } "
		case "${words}" in
			*" darwin "*|*" macos "*)            os="darwin" ;;
			*" windows "*|*" exe "|*" msi ")    os="windows" ;;
			*" freebsd "*)                       os="freebsd" ;;
			*" linux "*|*" deb "|*" rpm ")      os="linux" ;;
			*)                                   os="" ;;
		esac
		case "${words}" in
			*" universal "*)                     cpu="any" ;;
			*" x86 64 "*|*" amd64 "*|*" x64 "*)  cpu="x86_64" ;;
			*" arm64 "*|*" aarch64 "*)           cpu="arm64" ;;
			*)                                   cpu="" ;;
		esac
		if [[ -z "${os}" ]] || [[ -z "${cpu}" ]]; then
			others+=("[${asset}](${baseUrl}/${asset})")
			continue
		fi
		cells["${os}/${cpu}"]+="${cells["${os}/${cpu}"]:+<br>}<a href=\"${baseUrl}/${asset}\">${asset}</a>"
	done

	printf '### Downloads\n\n<table>\n<tr><th></th>'
	for cpu in "${cpuOrder[@]}"; do printf '<th>%s</th>' "${cpu}"; done
	printf '</tr>\n'
	for os in "${osOrder[@]}"; do
		row="<tr><th>${osTitles[${os}]}</th>"
		if [[ -z "${cells["${os}/x86_64"]:-}${cells["${os}/arm64"]:-}" ]] && [[ -n "${cells["${os}/any"]:-}${universalOnly[${os}]:-}" ]]; then
			row+="<td colspan=\"${#cpuOrder[@]}\" align=\"center\">${cells["${os}/any"]:--}</td>"
		else
			for cpu in "${cpuOrder[@]}"; do
				cell="${cells["${os}/${cpu}"]:-}"
				if [[ -n "${cells["${os}/any"]:-}" ]]; then cell+="${cell:+<br>}${cells["${os}/any"]}"; fi
				row+="<td>${cell:--}</td>"
			done
		fi
		printf '%s</tr>\n' "${row}"
	done
	printf '</table>\n'

	if ((${#others[@]})); then
		local -r joined="$(printf '%s, ' "${others[@]}")"
		printf '\nOther files: %s.\n' "${joined%, }"
	fi
	printf '\n[checksums.txt](%s/checksums.txt) has the SHA-256 of every file.\n' "${baseUrl}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Puts the build that just passed where daily use finds it. Release files,
## when this run made them, each go to their platform's synced dir, overwriting
## what's there. Otherwise the command from zig-out goes to the first dir that
## exists. Part of every full run, so nothing here is fatal - a machine with
## none of those dirs still built and tested fine.
fStage_Dogfood(){

	fSection "Dogfood"

	local -i placed=0
	local entry="" file="" name="" dir=""
	## A container run packages into the same dist/.
	if ((doPackage)); then
		for entry in "${dogfoodSynced[@]}"; do
			IFS='|' read -r file name dir <<< "${entry}"
			file="${distPrefix}${file}"
			[[ -f "${repoRoot}/dist/${file}" ]] || continue
			if [[ ! -d "${dir}" ]]; then
				fEcho_Clean "Skipped ....: ${file}, no ${dir} here"
				continue
			fi
			fDogfoodCopy "${repoRoot}/dist/${file}" "${dir}/${name}"
			placed=$((placed + 1))
		done
	fi
	if ((placed)); then return 0; fi

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
	fDogfoodCopy "${exe}" "${target}/zuid"

}

fDogfoodCopy(){  ## from, to
	if cmp -s "$1" "$2" 2>/dev/null; then
		fEcho_Clean "Installed ..: $2 already current"
	elif install -m 0755 "$1" "$2"; then
		fEcho_Clean "Installed ..: $2"
	else
		fEcho_Clean "Installed ..: could not write '$2'"
	fi
	return 0
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Archives the whole project - repo/, private/, the lot - to ../versions/, then
## commits and pushes, all through the vendored helper. Its git half is why
## --commit and --push are refused alongside it.
fStage_Backup(){

	fSection "Backup and publish"

	local -r helper="${utilityDir}/n8git_backup-and-publish"
	[[ -x "${helper}" ]] || fThrowError "Missing the backup helper: '${helper}'."  "${FUNCNAME[0]}"
	_fMustBeInPath rar

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fThrowError "HEAD is detached. Check out a branch before publishing."  "${FUNCNAME[0]}"
	fi

	fEcho_Clean "Archive to .: $(dirname "${repoRoot}")/versions/"
	fEcho_Clean "Excluding ..: $(tr '\n' ' ' <<< "${rarExcludes:-(generic list in the helper only)}")"

	## Quiet always: the message was asked for up front, and this run just made every
	## check the helper would prompt about. Without a message it falls to git's editor.
	local -a helperArgs=(-q)
	if [[ -n "${commitMsg}" ]]; then helperArgs+=(-m "${commitMsg}"); fi

	## The helper works from the git directory itself - it archives '../.' and looks
	## for './.git' - so it gets run from there rather than wherever cicd was called.
	(
		cd "${repoRoot}" || fThrowError "Could not enter '${repoRoot}'."  "${FUNCNAME[0]}"
		SKIP_GATE=1 GIT_BACKUP_AND_PUBLISH_RAR_EXCLUDES="${rarExcludes}" "${helper}" "${helperArgs[@]}"
	)

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
fStage_Commit(){

	fSection "Commit"

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

	fSection "Push"

	local -r remote="$(git -C "${repoRoot}" remote | head -n1)"
	[[ -n "${remote}" ]] || fThrowError "No remote to push to."  "${FUNCNAME[0]}"

	local -r branch="$(git -C "${repoRoot}" rev-parse --abbrev-ref HEAD)"
	if [[ "${branch}" == "HEAD" ]]; then
		fThrowError "HEAD is detached, so there is no branch to push."  "${FUNCNAME[0]}"
	fi
	SKIP_GATE=1 git -C "${repoRoot}" push -u "${remote}" "${branch}"

}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Artifacts. Everything under cicd/artifacts/ is gitignored; this keeps it
##	from growing without bound.
##

## The image has no time zone, so a stamp made inside was UTC and sorted
## hours away from the host's. The run inside takes the one from outside.
fRunStamp(){
	if ((inContainer)) && [[ "${ZUID_RUN_STAMP:-}" =~ ^[0-9]{8}-[0-9]{6}$ ]]
		then printf '%s\n' "${ZUID_RUN_STAMP}"
		else date +%Y%m%d-%H%M%S
	fi
}

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
## Machine use, per the shared CICD rules. buildJobs is half the CPUs, or a
## quarter when the 1-minute load is over half of them. hardJobs is a quarter
## either way, for fuzzing, the sanitizers, the soaks and CodeQL. Never less
## than one. Inside the image, never more than the --cpus the run outside gave
## it, since nproc there still counts the whole box.
fJobs(){
	local -i cores=1 half=1 quarter=1 load100=0 busy=0
	cores="$(fCpuCount)"
	local load="" frac=""
	load="$(fLoadAvg)"
	if [[ "${load}" =~ ^([0-9]{1,6})(\.([0-9]+))?$ ]]; then
		frac="${BASH_REMATCH[3]}00"
		load100=$((10#${BASH_REMATCH[1]} * 100 + 10#${frac:0:2}))
	else
		load=""
	fi
	half=$((cores / 2));    ((half > 0))    || half=1
	quarter=$((cores / 4)); ((quarter > 0)) || quarter=1
	if ((load100 * 2 > cores * 100)); then busy=1; fi
	buildJobs="${half}"; if ((busy)); then buildJobs="${quarter}"; fi
	hardJobs="${quarter}"
	if [[ "${ZUID_JOBS_CAP:-}" =~ ^[1-9][0-9]{0,5}$ ]]; then
		if ((buildJobs > ZUID_JOBS_CAP)); then buildJobs="${ZUID_JOBS_CAP}"; fi
		if ((hardJobs > ZUID_JOBS_CAP));  then hardJobs="${ZUID_JOBS_CAP}";  fi
	fi
	cpuCount="${cores}"; machineBusy="${busy}"; loadNow="${load:-unknown}"
}

fJobs_Line(){
	local busyNote=""; if ((machineBusy)); then busyNote=", busy"; fi
	fEcho_Clean "Jobs .......: ${buildJobs}, ${hardJobs} for the hard steps (${cpuCount} CPUs, load ${loadNow}${busyNote})"
}

## Before each step. Says so only when a count moved.
fJobs_Recheck(){
	## fSection runs outside fMain too, in the test rigs.
	[[ -n "${loadNow:-}" ]] || return 0
	local -ri wasBuild="${buildJobs}" wasHard="${hardJobs}"
	fJobs
	if ((buildJobs != wasBuild || hardJobs != wasHard)); then fJobs_Line; fi
}

fCpuCount(){
	local n=""
	if command -v nproc &>/dev/null; then n="$(nproc 2>/dev/null || true)"; fi
	if [[ ! "${n}" =~ ^[1-9][0-9]*$ ]]; then n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"; fi
	if [[ ! "${n}" =~ ^[1-9][0-9]*$ ]]; then n="$(sysctl -n hw.ncpu 2>/dev/null || true)"; fi
	if [[ ! "${n}" =~ ^[1-9][0-9]*$ ]]; then n=1; fi
	printf '%s\n' "${n}"
}

## The 1-minute load as the system gives it, or nothing.
fLoadAvg(){
	local l1="" rest=""
	if [[ -r /proc/loadavg ]]; then
		read -r l1 rest < /proc/loadavg || true
	else
		## macOS and BSD: "{ 1.23 1.45 1.67 }".
		read -r rest l1 rest <<< "$(sysctl -n vm.loadavg 2>/dev/null || true)" || true
	fi
	printf '%s\n' "${l1}"
}

## Children inherit it, so every tool this starts runs low. The image's
## processes are docker's children, not ours, so fInImage and fStage_Container
## add nice inside as well, and --cpu-shares.
fLowPriority(){
	renice 19 -p "$$" >/dev/null 2>&1 || true
	if command -v ionice &>/dev/null; then ionice -c 3 -p "$$" >/dev/null 2>&1 || true; fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## sort -V puts 1.2.3 before 1.2.3-dev, so a pre-release reads as newer than the
## release it precedes. Comparing the release part first is what stops a dev
## snapshot passing a floor it is below.
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
## Zig 0.17 hands SOURCE_DATE_EPOCH to clang when it builds its own libunwind
## and libc into a cold global cache, and clang refuses anything but a number,
## empty included. build.zig cannot clear it for that process, so it goes here.
## build.zig then takes the commit date, as it would for an empty one.
## package.bash does the same.
fDropBadEpoch(){
	if [[ -z "${SOURCE_DATE_EPOCH+set}" ]] || [[ "${SOURCE_DATE_EPOCH}" =~ ^[0-9]+$ ]]; then return 0; fi
	if [[ -n "${SOURCE_DATE_EPOCH//[[:space:]]/}" ]]; then
		fEcho_Clean "Epoch ......: SOURCE_DATE_EPOCH '${SOURCE_DATE_EPOCH}' is not a number; ignored, so the build number comes from the commit date"
	fi
	unset SOURCE_DATE_EPOCH
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Every .zig-cache in the tree, and inside the image its global cache volume.
## Whole or not at all, since the manifests point into the rest. A cache with
## no stamp was just filled by this run's Zig, so it only gets one.
## ~/.cache/zig is every project's and every Zig's, so it's left alone.
fZigCache_Tidy(){
	local -r zigVer="$(zig version 2>/dev/null || true)"
	local -a caches=()
	local dir="" was="" why=""
	local -i kb=0
	while IFS= read -r -d '' dir; do caches+=("${dir}"); done < <(find "${repoRoot}" -path "${repoRoot}/.git" -prune -o -name .zig-cache \( -type d -o -type l \) -prune -print0 2>/dev/null || true)
	if ((inContainer)) && [[ "${ZIG_GLOBAL_CACHE_DIR:-}" == "${containerZigCache}" ]]; then caches+=("${containerZigCache}"); fi
	for dir in "${caches[@]}"; do
		[[ -d "${dir}" ]] || continue
		kb="$(du -sk "${dir}/" 2>/dev/null | awk '{print $1}' || true)"
		was="$(cat "${dir}/${zigCacheStamp}" 2>/dev/null || true)"
		why=""
		if ((kb > zigCacheCapMB * 1024)); then why="$((kb / 1024)) MB, over ${zigCacheCapMB} MB"
		elif [[ -n "${was}" && -n "${zigVer}" && "${was}" != "${zigVer}" ]]; then why="filled by Zig ${was}"; fi
		if [[ -n "${why}" ]]; then
			if ! fZigCache_Empty "${dir}"; then fEcho_Clean "Zig cache ..: couldn't empty ${dir}, ${why}"; continue; fi
			fEcho_Clean "Zig cache ..: emptied ${dir}, ${why}"
		fi
		if [[ -n "${zigVer}" ]]; then printf '%s\n' "${zigVer}" > "${dir}/${zigCacheStamp}" || true; fi
	done
}


## The only place a Zig cache is emptied. A .zig-cache under the repo, wherever
## its link goes as long as that's a .zig-cache too, or inside the image its
## global cache. The folder stays, since it may be a link's target or a mount.
fZigCache_Empty(){  ## cache dir
	local -r dir="${1%/}"
	local real=""
	[[ -n "${dir}" && "${dir}" != *..* && "${dir}" != *$'\n'* ]] || return 1
	real="$(cd "${dir}" 2>/dev/null && pwd -P)" || return 1
	if [[ "${dir}" == "${repoRoot}/"*.zig-cache && "${dir##*/}" == ".zig-cache" && "${real##*/}" == ".zig-cache" ]]; then :
	elif ((inContainer)) && [[ "${dir}" == "${containerZigCache}" && "${real}" == "${containerZigCache}" ]]; then :
	else return 1; fi
	find "${real}" -xdev -mindepth 1 -delete
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

## A stage header is a blank line, a rule as wide as the terminal, then the
## title, the way silkterm's fSection prints one. A log or a pipe has no width,
## so it gets silkterm's 74. Set before the run log's tee, since after it
## nothing is a terminal. The run in the container is handed the width.
declare _sectionRule="" _sectionWidth=""
function fSection_Init(){
	local width=""
	if [[ -t 1 ]]; then width="$(stty size 2>/dev/null < /dev/tty || true)"; width="${width#* }"; fi
	if ((inContainer)) && [[ -z "${width}" ]]; then width="${ZUID_COLUMNS:-}"; fi
	[[ "${width}" =~ ^[1-9][0-9]{0,3}$ ]] || width=74
	_sectionWidth="${width}"
	printf -v _sectionRule '%*s' "${width}" ''
	_sectionRule="${_sectionRule// /•}"
}
function fSection(){
	[[ -n "${_sectionRule}" ]] || fSection_Init
	fEcho_Clean
	fEcho_Clean "${_sectionRule}"
	fEcho "$*"
	fJobs_Recheck
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
##
##	Generic error-handling stuff.
##

declare -i _wasCleanupRun=0
declare -a _scratchDirs=()
## Set by fContainer_Image, for the exit trap.
declare _dockerEngine="" _dockerProject="" _dockerRun="" _dockerPid=""
declare -i _dockerSteps=0
declare -a _dockerGone=()

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
	## Only a bare mktemp -d's own tmp.* folder, in TMPDIR or /tmp. Checking for
	## /tmp alone kept every one when TMPDIR was elsewhere, as it is on macOS.
	local tmpRoot="${TMPDIR:-/tmp}"; tmpRoot="${tmpRoot%/}"
	local dir="" parent=""
	for dir in "${_scratchDirs[@]}"; do
		[[ -n "${dir}" && -d "${dir}" && ! -L "${dir}" && "${dir##*/}" == tmp.* ]] || continue
		parent="${dir%/*}"; parent="${parent%/}"
		if [[ "${parent}" == "${tmpRoot}" || "${parent}" == "/tmp" ]]; then rm -rf "${dir}"; fi
	done
	_scratchDirs=()
}
function _fTrap_Exit(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		_fRemoveScratchDirs
		fContainer_StopRun
		if ((${#_dockerGone[@]})); then fEcho_Clean "Docker .....: removed ${_dockerGone[*]} of this run"; fi
		_fSingleExitPoint "${@}"
	fi
}
function _fTrap_Error(){
	if [[ "${_wasCleanupRun}" == "0" ]]; then  ## String compare is less to fail than integer
		_wasCleanupRun=1
		_fRemoveScratchDirs
		fContainer_StopRun
		if ((${#_dockerGone[@]})); then fEcho_Clean "Docker .....: removed ${_dockerGone[*]} of this run"; fi
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

