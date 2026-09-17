#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Downloads a zuid release, checks it against the published checksums, and installs it.

.DESCRIPTION
	Idempotent: it states what it is about to do and asks before touching
	anything, and reinstalling the same version is a no-op. Runs on Windows,
	Linux, and macOS under PowerShell 7 or newer.

.PARAMETER Release
	stable (default) or dev.

.PARAMETER Target
	user (default when the system location is not writable) or system.

.PARAMETER Arch
	x86_64 or arm64. Detected when not given.

.PARAMETER Yes
	Skip the confirmation prompt.

.PARAMETER Uninstall
	Remove an existing install instead of adding one.

.EXAMPLE
	& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/jim-collier/zuid/main/install.ps1')))

.EXAMPLE
	.\install.ps1 -Release dev -Target user

.NOTES
	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]. MIT licensed: https://mit-license.org/
	SPDX-License-Identifier: MIT
#>

[CmdletBinding()]
param(
	[ValidateSet('stable', 'dev')] [string] $Release = 'stable',
	[ValidateSet('user', 'system')] [string] $Target,
	[ValidateSet('x86_64', 'arm64')] [string] $Arch,
	[switch] $Yes,
	[switch] $Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = 'jim-collier/zuid'
$program = 'zuid'

function Write-Status { param([string] $Message) Write-Host "[ $Message ]" }
function Write-Detail { param([string] $Message) Write-Host $Message }
function Stop-WithMessage { param([string] $Message) throw "$program-install: $Message" }

Write-Host ''


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Where things go, per platform.

if ($IsWindows) {
	$systemDir = Join-Path $env:ProgramFiles $program
	$userDir = Join-Path $env:LOCALAPPDATA "Programs\$program"
	$osLabel = 'windows'
	$binaryName = "$program.exe"
	$archiveExtension = 'zip'
}
elseif ($IsMacOS) {
	$systemDir = "/opt/$program"
	$userDir = Join-Path $HOME "Library/Application Support/$program"
	$osLabel = 'darwin'
	$binaryName = $program
	$archiveExtension = 'tgz'
}
else {
	$systemDir = "/opt/$program"
	$userDir = Join-Path $HOME ".local/share/$program"
	$osLabel = 'linux'
	$binaryName = $program
	$archiveExtension = 'tgz'
}

## Whether the system location can be written, not whether it is there. Testing
## existence meant a normal user on any box with /usr/local/bin got a system
## install, which then failed at New-Item after the whole download - and there
## is no elevation path here the way install.bash has sudo. install.bash tests
## -w for the same reason.
function Test-DirectoryWritable {
	param([string] $Path)
	## The install creates the leaf, so what matters is the nearest thing that
	## already exists.
	$probeDir = $Path
	while ($probeDir -and -not (Test-Path $probeDir -PathType Container)) {
		$parent = Split-Path -Parent $probeDir
		if ($parent -eq $probeDir) { return $false }
		$probeDir = $parent
	}
	if (-not $probeDir) { return $false }
	## Actually write, rather than read a mode or an ACL. Those disagree with
	## the filesystem often enough, and this is one file in a directory the
	## script is about to use anyway.
	$probe = Join-Path $probeDir ".$program-write-probe-$PID"
	try {
		[System.IO.File]::WriteAllText($probe, '')
		Remove-Item -Force -ErrorAction SilentlyContinue $probe
		return $true
	}
	catch { return $false }
}

if (-not $Target) {
	## On Windows the install directory is the whole story. Elsewhere it is the
	## link directory that decides, which is what install.bash tests.
	$systemProbe = if ($IsWindows) { $systemDir } else { '/usr/local/bin' }
	$Target = if (Test-DirectoryWritable $systemProbe) { 'system' } else { 'user' }
}

$installDirectory = if ($Target -eq 'system') { $systemDir } else { $userDir }
$linkDirectory = if ($IsWindows) {
	$null
}
elseif ($Target -eq 'system') {
	'/usr/local/bin'
}
else {
	Join-Path $HOME '.local/bin'
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Uninstall is the same plan in reverse.

## Only this installer's own link. A zuid at that path the installer did not put
## there is somebody's own build - the README tells a source build that a full
## cicd run copies one to ~/.local/bin - and uninstall is the plan in reverse,
## which only covers what the install made.
function Test-OurLink {
	param([string] $Link, [string] $InstallDirectory)
	$item = Get-Item -LiteralPath $Link -Force -ErrorAction SilentlyContinue
	if (-not $item) { return $false }
	## A plain file is never ours, however it got there.
	if (-not $item.LinkTarget) { return $false }
	$target = $item.LinkTarget
	if (-not [System.IO.Path]::IsPathRooted($target)) {
		$target = Join-Path (Split-Path -Parent $Link) $target
	}
	$expected = Join-Path $InstallDirectory 'bin'
	return $target.StartsWith($expected, [System.StringComparison]::Ordinal)
}

if ($Uninstall) {
	## Decided before anything is removed: once the install directory is gone
	## the link dangles and there is no target left to recognize.
	$link = if ($linkDirectory) { Join-Path $linkDirectory $program } else { $null }
	$ownsLink = if ($link) { Test-OurLink $link $installDirectory } else { $false }

	Write-Status 'Uninstall'
	Write-Detail "  Remove: $installDirectory"
	if ($ownsLink) {
		Write-Detail "  Remove: $link"
	}
	elseif ($link -and (Test-Path -LiteralPath $link)) {
		Write-Detail "  Keep ..: $link (not this installer's link, so it stays)"
	}
	Write-Detail ''
	if (-not $Yes) {
		$answer = Read-Host '  Proceed? [y/N]'
		if ($answer -notmatch '^[Yy]') {
			Write-Detail ''
			Write-Status 'Nothing was changed.'
			Write-Host ''
			return
		}
		Write-Detail ''
	}
	if (Test-Path $installDirectory) { Remove-Item -Recurse -Force $installDirectory }
	if ($ownsLink) { Remove-Item -Force -LiteralPath $link }
	Write-Status 'Removed.'
	Write-Host ''
	return
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Work out what to fetch.

if (-not $Arch) {
	$Arch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
		'X64' { 'x86_64' }
		'Arm64' { 'arm64' }
		default { Stop-WithMessage "unsupported architecture: $_. Pass -Arch to override." }
	}
}

## GitHub's 'latest' endpoint only ever answers with a full release, so it 404s
## on a repository whose releases are all prereleases. List them and choose here.

Write-Status "Looking up the $Release release"
## The response has to land in a variable before it is wrapped. Invoke-RestMethod
## hands a JSON array to the pipeline as one object, so @(irm ...) inline gives a
## single element holding the whole list, and every later per-release test then
## runs against an array of flags instead of one flag.
try {
	$response = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases" -Headers @{ 'User-Agent' = "$program-install" }
	$found = @($response)
}
catch {
	$found = @()
}
$published = @($found | Where-Object { -not $_.draft })
if (-not $published) {
	Stop-WithMessage "no published release found for $repository. If the repository has none yet, build from source instead - see its README."
}

if ($Release -eq 'dev') {
	## Newest of anything, prerelease included.
	$chosen = $published[0]
}
else {
	$chosen = $published | Where-Object { -not $_.prerelease } | Select-Object -First 1
	if (-not $chosen) {
		## Nothing final published yet, so the newest prerelease is the only
		## thing there is to install. Say so rather than failing.
		$chosen = $published[0]
		Write-Detail '  No stable release yet, so this is the newest prerelease.'
	}
}
$tag = $chosen.tag_name
$kind = if ($chosen.prerelease) { 'prerelease' } else { 'stable' }

$asset = "$program-$osLabel-$Arch.$archiveExtension"
$baseUrl = "https://github.com/$repository/releases/download/$tag"


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## State the plan, then ask.

$existing = Join-Path $installDirectory (Join-Path 'bin' $binaryName)
$installedVersion = if (Test-Path $existing) { (& $existing --version 2>$null | Select-Object -First 1) } else { $null }

## --version is "1.0.0-alpha.1 (build dcrb0)", and the tag carries a leading v.
## Nothing used to compare the two, so a second run downloaded the same release,
## deleted the install directory and copied it back - while the help, the README
## and the backlog all said re-running changes nothing.
if ($installedVersion) {
	$installedTag = ($installedVersion -split ' ')[0]
	if ($installedTag -eq ($tag -replace '^v', '')) {
		Write-Detail ''
		Write-Status 'Already installed'
		Write-Detail "  Version ....: $tag ($kind)"
		Write-Detail "  Location ...: $installDirectory"
		Write-Detail ''
		Write-Detail '  Nothing to do. To reinstall, run -Uninstall first.'
		Write-Host ''
		return
	}
}

Write-Detail ''
Write-Status 'Plan'
Write-Detail "  Version ....: $tag ($kind)"
Write-Detail "  Platform ...: $osLabel/$Arch"
Write-Detail "  Download ...: $baseUrl/$asset"
Write-Detail '  Verify .....: sha256 against checksums.txt'
Write-Detail "  Install to .: $installDirectory"
if ($linkDirectory) { Write-Detail "  Link .......: $(Join-Path $linkDirectory $program)" }
## Naming it, because the thing being overwritten may not be ours - a build
## copied there by hand or by a cicd run, rather than a previous install.
if ($linkDirectory) {
	$plannedLink = Join-Path $linkDirectory $program
	if ((Test-Path -LiteralPath $plannedLink) -and -not (Test-OurLink $plannedLink $installDirectory)) {
		Write-Detail "  Overwriting : $plannedLink is not this installer's link"
	}
}
else { Write-Detail "  PATH .......: add $(Join-Path $installDirectory 'bin') yourself" }
if ($installedVersion) { Write-Detail "  Replacing ..: $installedVersion" }
Write-Detail ''

if (-not $Yes) {
	$answer = Read-Host '  Proceed? [y/N]'
	if ($answer -notmatch '^[Yy]') {
		Write-Detail ''
		Write-Status 'Nothing was changed.'
		Write-Host ''
		return
	}
	Write-Detail ''
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Fetch, verify, install.

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
	$archive = Join-Path $work $asset
	$checksums = Join-Path $work 'checksums.txt'

	Write-Status 'Downloading'
	Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archive
	Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile $checksums

	Write-Status 'Verifying'
	$expected = (Get-Content $checksums |
		Where-Object { ($_ -split '\s+')[-1].TrimStart('*') -eq $asset } |
		Select-Object -First 1)
	if (-not $expected) { Stop-WithMessage "$asset is not listed in checksums.txt" }
	$wanted = ($expected -split '\s+')[0]
	$actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
	if ($actual -ne $wanted.ToLowerInvariant()) {
		Stop-WithMessage "checksum mismatch: expected $wanted, got $actual"
	}

	Write-Status 'Installing'
	$unpacked = Join-Path $work 'unpacked'
	New-Item -ItemType Directory -Path $unpacked | Out-Null
	if ($archiveExtension -eq 'zip') {
		Expand-Archive -Path $archive -DestinationPath $unpacked -Force
	}
	else {
		tar --no-same-owner --no-same-permissions -xzf $archive -C $unpacked
	}
	$payload = Get-ChildItem -Path $unpacked -Directory | Select-Object -First 1
	if (-not $payload) { Stop-WithMessage 'the archive did not contain the expected directory' }

	if (Test-Path $installDirectory) { Remove-Item -Recurse -Force $installDirectory }
	New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
	Copy-Item -Path (Join-Path $payload.FullName '*') -Destination $installDirectory -Recurse -Force

	if ($linkDirectory) {
		New-Item -ItemType Directory -Path $linkDirectory -Force | Out-Null
		$link = Join-Path $linkDirectory $program
		if (Test-Path $link) { Remove-Item -Force $link }
		New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $installDirectory "bin/$binaryName") | Out-Null
	}

	Write-Detail ''
	Write-Status "Installed $tag to $installDirectory"
	$binDirectory = if ($linkDirectory) { $linkDirectory } else { Join-Path $installDirectory 'bin' }
	if (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $binDirectory) {
		Write-Detail "  Note: $binDirectory is not on your PATH."
	}
	Write-Detail "  Try: $program --help"
	Write-Host ''
}
finally {
	Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
