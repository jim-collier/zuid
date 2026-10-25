#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Downloads a zuid release, checks it against the published checksums, and installs it.

.DESCRIPTION
	Idempotent: it states what it is about to do and asks before touching
	anything, and reinstalling the same version is a no-op. Runs under Windows
	PowerShell 5.1, and under PowerShell 7 on Windows, Linux, and macOS.

.PARAMETER Release
	stable (default) or dev.

.PARAMETER Target
	user (default) or system.

.PARAMETER Yes
	Skip the confirmation prompt.

.PARAMETER Uninstall
	Remove an existing install instead of adding one.

.PARAMETER Help
	Print this help.

.PARAMETER Version
	Print the installer's version.

.EXAMPLE
	& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/jim-collier/zuid/main/install.ps1')))

.EXAMPLE
	.\install.ps1 -Release dev -Target user

.NOTES
	Copyright (C) 2026 Jim Collier. MIT licensed: https://mit-license.org/
	SPDX-License-Identifier: MIT
#>

## Console output is the point of an installer.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
## Stop-WithMessage only throws; it changes nothing.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
[CmdletBinding()]
param(
	[ValidateSet('stable', 'dev')] [string] $Release = 'stable',
	[ValidateSet('user', 'system')] [string] $Target,
	[switch] $Yes,
	[switch] $Uninstall,
	[switch] $Help,
	[switch] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repository = 'jim-collier/zuid'
$program = 'zuid'
$installerVersion = '1.3.0'

## Here and not through Get-Help, which needs the script as a file. Under irm |
## scriptblock there isn't one.
if ($Help) {
	Write-Host @"

$program installer $installerVersion

Downloads the newest $program release from GitHub, checks it against the
published checksums, and installs it. It says what it's about to do and asks
first. Running it again on the same version changes nothing.

Usage:
  & ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/$repository/main/install.ps1'))) [options]

Options:
  -Release stable|dev   stable (default): newest full release
                        dev: newest release, prereleases included
  -Target user|system   user (default): your own account, no admin needed
                        system: Program Files, /opt, /usr/local
  -Yes                  don't ask before installing
  -Uninstall            remove what this installer put in place
  -Version              print the installer's version
  -Help                 this text

The OS, CPU architecture, and release file are detected.

"@
	return
}
if ($Version) {
	Write-Output $installerVersion
	return
}

function Write-Status { param([string] $Message) Write-Host "[ $Message ]" }
function Write-Detail { param([string] $Message) Write-Host $Message }
function Stop-WithMessage { param([string] $Message) throw "$program-install: $Message" }

$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -lt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -lt 1)) {
	Stop-WithMessage "this needs Windows PowerShell 5.1 or PowerShell 7, and this is PowerShell $psVer. Install PowerShell 7 from https://aka.ms/powershell, then run this again from pwsh."
}

## 5.1 is Windows only and has no $IsWindows at all, which strict mode won't read.
$onWindows = $true; $onMac = $false; $onLinux = $false
if ($psVer.Major -ge 6) { $onWindows = $IsWindows; $onMac = $IsMacOS; $onLinux = $IsLinux }

## 5.1 can still default to TLS 1.0 on an older box, which GitHub refuses with
## "the underlying connection was closed". -UseBasicParsing keeps it off the IE
## engine, which throws when IE was never started.
$webArgs = @{}
if ($psVer.Major -lt 6) {
	try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch { Write-Verbose 'TLS 1.2 not settable' }
	$webArgs['UseBasicParsing'] = $true
	## Its progress bar slows a download down by a lot.
	$ProgressPreference = 'SilentlyContinue'
}

Write-Host ''


#-------------------------------------------------------------------------------
## Where things go, per platform.

if ($onWindows) {
	$systemDir = Join-Path $env:ProgramFiles $program
	$userDir = Join-Path $env:LOCALAPPDATA "Programs\$program"
	$osLabel = 'windows'
	$binaryName = "$program.exe"
	$archiveExtension = 'zip'
}
elseif ($onMac) {
	$systemDir = "/opt/$program"
	$userDir = Join-Path $HOME "Library/Application Support/$program"
	$osLabel = 'darwin'
	$binaryName = $program
	$archiveExtension = 'tgz'
}
elseif ($onLinux) {
	$systemDir = "/opt/$program"
	$userDir = Join-Path $HOME ".local/share/$program"
	$osLabel = 'linux'
	$binaryName = $program
	$archiveExtension = 'tgz'
}
else {
	## PowerShell does not support FreeBSD, so install.bash covers it.
	Stop-WithMessage "no $program build exists for $([Environment]::OSVersion.VersionString). Build from source instead - see the README."
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
	## Write a file, rather than read a mode or an ACL. Those disagree with
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

## Both locations get written, so both have to be writable. On Windows the
## install directory is all there is, since there is no link.
function Test-SystemTargetUsable {
	if (-not (Test-DirectoryWritable $systemDir)) { return $false }
	if ($onWindows) { return $true }
	return Test-DirectoryWritable '/usr/local/bin'
}

## User unless asked, admin or not.
if (-not $Target) { $Target = 'user' }
if ($Target -eq 'system' -and -not (Test-SystemTargetUsable)) {
	## Asked for by name, with nowhere to write. There is no elevation here the
	## way install.bash has sudo, and the write is the last thing this script
	## does - so without this the whole release downloaded and verified before
	## New-Item threw a raw permissions error.
	Stop-WithMessage "the system target needs write access to $systemDir and its link directory. Re-run elevated, or use -Target user."
}

$installDirectory = if ($Target -eq 'system') { $systemDir } else { $userDir }
$linkDirectory = if ($onWindows) {
	$null
}
elseif ($Target -eq 'system') {
	'/usr/local/bin'
}
else {
	Join-Path $HOME '.local/bin'
}


#-------------------------------------------------------------------------------
## Windows has no link, so the bin folder goes on PATH: the user's for a user
## install, the machine's for a system one. Through the registry, since
## [Environment]::SetEnvironmentVariable rewrites a REG_EXPAND_SZ PATH as REG_SZ
## and every %VAR% in it stops expanding.

$windowsBin = Join-Path $installDirectory 'bin'
$pathScope = if ($Target -eq 'system') { 'Machine' } else { 'User' }

function Open-PathKey {
	param([string] $Scope, [bool] $Writable)
	if ($Scope -eq 'Machine') {
		return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $Writable)
	}
	return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $Writable)
}

function Test-SameDirectory {
	param([string] $A, [string] $B)
	return $A.TrimEnd('\') -eq $B.TrimEnd('\')
}

function Test-OnWindowsPath {
	$key = Open-PathKey $pathScope $false
	if (-not $key) { return $false }
	try { $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
	finally { $key.Close() }
	foreach ($entry in ($raw -split ';')) { if (Test-SameDirectory $entry $windowsBin) { return $true } }
	return $false
}

## Explorer, and whatever it starts, rereads the environment only when told.
function Send-EnvironmentChange {
	try {
		if (-not ('ZuidInstall.Env' -as [type])) {
			Add-Type -Namespace ZuidInstall -Name Env -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
		}
		$ignored = [UIntPtr]::Zero
		## HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG, 5 s.
		[void]([type]'ZuidInstall.Env')::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$ignored)
	}
	catch { Write-Detail '  A window opened from the Start menu may not see the new PATH until you sign in again.' }
}

## Adds or removes the one entry and leaves the rest of PATH as it was. Says
## what it did, and never throws: the install itself already worked.
function Set-WindowsPath {
	param([bool] $Present)
	try {
		$key = Open-PathKey $pathScope $true
		if (-not $key) { throw "can't open the $pathScope environment key" }
		try {
			$raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
			$kind = if ($raw) { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
			$entries = @($raw -split ';')
			$kept = @($entries | Where-Object { -not (Test-SameDirectory $_ $windowsBin) })
			if ($Present) {
				if ($kept.Count -ne $entries.Count) { return }
				## A trailing ';' stays trailing, so removing the entry later gives
				## back the same value.
				$new = if (-not $raw) { $windowsBin } elseif ($raw.EndsWith(';')) { "$raw$windowsBin;" } else { "$raw;$windowsBin" }
				## Past these, parts of Windows cut PATH short, and a lost PATH
				## is worse than a missing entry.
				$limit = if ($pathScope -eq 'User') { 2047 } else { 4095 }
				if ([Environment]::ExpandEnvironmentVariables($new).Length -gt $limit) {
					Write-Detail "  Note: the $($pathScope.ToLower()) PATH is close to Windows' length limit, so $windowsBin wasn't added."
					Write-Detail "  Run it as: $(Join-Path $windowsBin $binaryName)"
					return
				}
			}
			else {
				if ($kept.Count -eq $entries.Count) { return }
				$new = $kept -join ';'
			}
			$key.SetValue('Path', $new, $kind)
		}
		finally { $key.Close() }
		if ($Present) {
			$env:PATH = "$env:PATH;$windowsBin"
			Write-Detail "  Added $windowsBin to the $($pathScope.ToLower()) PATH. Shells already open need a restart to see it."
		}
		else { Write-Detail "  Removed $windowsBin from the $($pathScope.ToLower()) PATH." }
		Send-EnvironmentChange
	}
	catch {
		Write-Detail "  Note: couldn't update the $($pathScope.ToLower()) PATH ($($_.Exception.Message))."
		if ($Present) { Write-Detail "  Run it as: $(Join-Path $windowsBin $binaryName)" }
	}
}


#-------------------------------------------------------------------------------
## The one way this removes anything recursively, its own copy of the repo's
## guard, since it runs alone from a download. Only strictly under a parent
## that isn't a link. A link is only unlinked, never followed, which Windows
## PowerShell 5.1's Remove-Item -Recurse can't promise.

function Test-IsLink {
	param([System.IO.FileSystemInfo] $Item)
	return [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
}

function Remove-Tree {
	param([System.IO.FileSystemInfo] $Item)
	if ($Item -is [System.IO.DirectoryInfo] -and -not (Test-IsLink $Item)) {
		foreach ($child in @($Item.GetFileSystemInfos())) { Remove-Tree $child }
	}
	## Remove-Item -Force did this for a read-only file.
	if ($onWindows -and ($Item.Attributes -band [System.IO.FileAttributes]::ReadOnly)) {
		$Item.Attributes = $Item.Attributes -band -bnot [System.IO.FileAttributes]::ReadOnly
	}
	$Item.Delete()
}

function Remove-Under {
	param([string] $Parent, [string] $Path)
	$parentItem = Get-Item -LiteralPath $Parent -Force
	if (Test-IsLink $parentItem) { Stop-WithMessage "refused to remove ${Path}: $Parent is a link" }
	$under = $parentItem.FullName.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
	if ($Path -match '(^|[\\/])\.\.([\\/]|$)') { Stop-WithMessage "refused to remove ${Path}: a bad path" }
	$item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
	if (-not $item) { return }
	$case = if ($onWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
	if (-not $item.FullName.StartsWith($under, $case)) { Stop-WithMessage "refused to remove ${Path}: not under $Parent" }
	Remove-Tree $item
}

## Empties the install directory one entry at a time, so it's the one parent
## named, and a wrong path can't take its parent with it. It has to be named for
## the program, and not be a link.
function Clear-InstallDirectory {
	$dir = Get-Item -LiteralPath $installDirectory -Force -ErrorAction SilentlyContinue
	if (-not $dir) { return }
	if (Test-IsLink $dir) { Stop-WithMessage "refused to empty ${installDirectory}: it's a link" }
	if (-not ($dir -is [System.IO.DirectoryInfo]) -or $dir.Name -ne $program) {
		Stop-WithMessage "refused to empty ${installDirectory}: not a $program install directory"
	}
	foreach ($entry in @($dir.GetFileSystemInfos())) { Remove-Under $dir.FullName $entry.FullName }
}


#-------------------------------------------------------------------------------
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
	## Worked out before anything is removed: once the install directory is gone
	## the link dangles and there is no target left to recognize.
	$link = if ($linkDirectory) { Join-Path $linkDirectory $program } else { $null }
	$ownsLink = if ($link) { Test-OurLink $link $installDirectory } else { $false }
	$ownsPath = if ($onWindows) { Test-OnWindowsPath } else { $false }

	Write-Status 'Uninstall'
	Write-Detail "  Remove: $installDirectory"
	if ($ownsPath) { Write-Detail "  Remove: $windowsBin from the $($pathScope.ToLower()) PATH" }
	if ($ownsLink) {
		Write-Detail "  Remove: $link"
	}
	elseif ($link -and (Test-Path -LiteralPath $link)) {
		Write-Detail "  Keep ..: $link (not this installer's link, so it stays)"
	}
	Write-Detail ''
	if (-not $Yes) {
		$answer = try { Read-Host '  Proceed? [y/N]' } catch { '' }
		## With stdin at its end Read-Host gives back nothing, and nothing
		## -notmatch anything is not true, so no answer used to mean yes.
		if ([string]$answer -notmatch '^[Yy]') {
			Write-Detail ''
			Write-Status 'Nothing was changed.'
			Write-Host ''
			return
		}
		Write-Detail ''
	}
	Clear-InstallDirectory
	if (Test-Path -LiteralPath $installDirectory) { (Get-Item -LiteralPath $installDirectory -Force).Delete() }
	if ($ownsLink) { Remove-Item -Force -LiteralPath $link }
	if ($ownsPath) { Set-WindowsPath $false }
	Write-Status 'Removed.'
	Write-Host ''
	return
}


#-------------------------------------------------------------------------------
## Work out what to fetch.

## .NET Framework under 5.1 doesn't have OSArchitecture. Named by string so the
## 5.1 lint doesn't flag the branch that never runs there.
$osArch = if ($psVer.Major -ge 6) {
	[string]([type]'System.Runtime.InteropServices.RuntimeInformation')::OSArchitecture
}
elseif ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 }
else { $env:PROCESSOR_ARCHITECTURE }
$Arch = switch ($osArch) {
	{ $_ -in 'X64', 'AMD64' } { 'x86_64' }
	'Arm64' { 'arm64' }
	default { Stop-WithMessage "no $program build exists for $_. Build from source instead - see the README." }
}

## GitHub's 'latest' endpoint only ever answers with a full release, so it 404s
## on a repository whose releases are all prereleases. List them and choose here.

## Semver order, since GitHub lists by date: a 1.0.1 fix published after
## 1.1.0-beta.1 would otherwise win for dev. Same rules as install.bash.
function Compare-VersionField {
	param([string] $A, [string] $B)
	$aNum = $A -match '^[0-9]+$'
	$bNum = $B -match '^[0-9]+$'
	if ($aNum -and $bNum) { return [math]::Sign([decimal]$A - [decimal]$B) }
	if ($aNum) { return -1 }
	if ($bNum) { return 1 }
	## beta10 is above beta3.
	if ($A -match '^([^0-9]*)([0-9]+)$') {
		$aStem = $Matches[1]; $aTail = $Matches[2]
		if ($B -match '^([^0-9]*)([0-9]+)$' -and $Matches[1] -ceq $aStem) {
			return [math]::Sign([decimal]$aTail - [decimal]$Matches[2])
		}
	}
	return [math]::Sign([string]::CompareOrdinal($A, $B))
}

function Compare-VersionList {
	## Missing is what a shorter list counts as: -1 for a prerelease, 0 for the core.
	param([string] $A, [string] $B, [int] $Missing)
	$aParts = if ($A) { @($A -split '\.') } else { @() }
	$bParts = if ($B) { @($B -split '\.') } else { @() }
	$count = [math]::Max($aParts.Count, $bParts.Count)
	for ($i = 0; $i -lt $count; $i++) {
		if ($i -ge $aParts.Count) { if ($Missing -eq 0) { $aField = '0' } else { return -1 } } else { $aField = $aParts[$i] }
		if ($i -ge $bParts.Count) { if ($Missing -eq 0) { $bField = '0' } else { return 1 } } else { $bField = $bParts[$i] }
		$c = Compare-VersionField -A $aField -B $bField
		if ($c -ne 0) { return $c }
	}
	return 0
}

function Test-NewerTag {
	param([string] $A, [string] $B)
	## PowerShell names ignore case, so $A and $a would be one variable.
	$aVer = ($A -replace '^v', '') -replace '\+.*$', ''
	$bVer = ($B -replace '^v', '') -replace '\+.*$', ''
	$aCore, $aPre = $aVer -split '-', 2
	$bCore, $bPre = $bVer -split '-', 2
	$c = Compare-VersionList -A $aCore -B $bCore -Missing 0
	if ($c -ne 0) { return $c -gt 0 }
	## Same core: a release is above any of its prereleases.
	if (-not $aPre) { return [bool]$bPre }
	if (-not $bPre) { return $false }
	return (Compare-VersionList -A $aPre -B $bPre -Missing -1) -gt 0
}

function Select-Newest {
	param([object[]] $Releases)
	$best = $null
	foreach ($r in $Releases) {
		if (-not $best -or (Test-NewerTag $r.tag_name $best.tag_name)) { $best = $r }
	}
	return $best
}

Write-Status "Looking up the $Release release"
## The response has to go in a variable before it is wrapped. Invoke-RestMethod
## hands a JSON array to the pipeline as one object, so @(irm ...) inline gives a
## single element holding the whole list, and every later per-release test then
## runs against an array of flags instead of one flag.
## A rate limit or a dead network used to read as "no release found".
try {
	$response = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases?per_page=100" -Headers @{ 'User-Agent' = "$program-install" } @webArgs
	$found = @($response)
}
catch {
	$status = $null
	if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
	if ($status -eq 403 -or $status -eq 429) {
		Stop-WithMessage "GitHub refused the release lookup (HTTP $status), most likely a rate limit. Wait an hour and try again."
	}
	elseif ($status) {
		Stop-WithMessage "the release lookup failed with HTTP $status."
	}
	Stop-WithMessage "couldn't reach api.github.com ($($_.Exception.Message)). Check the network or proxy, then try again."
}
$published = @($found | Where-Object { -not $_.draft })
if (-not $published) {
	Stop-WithMessage "no published release found for $repository. Build from source instead - see its README."
}

if ($Release -eq 'dev') {
	$chosen = Select-Newest $published
}
else {
	$chosen = Select-Newest @($published | Where-Object { -not $_.prerelease })
	if (-not $chosen) {
		## Nothing final yet, so the newest prerelease is all there is.
		$chosen = Select-Newest $published
		Write-Detail '  No stable release yet, so this is the newest prerelease.'
	}
}
$tag = $chosen.tag_name
$kind = if ($chosen.prerelease) { 'prerelease' } else { 'stable' }

## The macOS release is one universal build, for either architecture.
$assetArch = if ($onMac) { 'universal' } else { $Arch }
$asset = "$program-$($tag -replace '^v', '')-$osLabel-$assetArch.$archiveExtension"
## The alpha went out before release names had the version.
if ($tag -eq 'v1.0.0-alpha.1') { $asset = "$program-$osLabel-$assetArch.$archiveExtension" }
$baseUrl = "https://github.com/$repository/releases/download/$tag"


#-------------------------------------------------------------------------------
## State the plan, then ask.

$existing = Join-Path $installDirectory (Join-Path 'bin' $binaryName)
## 5.1 turns any stderr from a native command into an error, and Stop makes that fatal.
$installedVersion = $null
if (Test-Path $existing) {
	try { $installedVersion = & $existing --version 2>$null | Select-Object -First 1 } catch { $installedVersion = $null }
}

## --version is "1.0.0-alpha.1 (build dcrb0)", and the tag has a leading v.
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
Write-Detail "  Platform ...: $osLabel/$assetArch"
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
elseif (Test-OnWindowsPath) { Write-Detail "  PATH .......: already has $windowsBin" }
else { Write-Detail "  PATH .......: add $windowsBin to the $($pathScope.ToLower()) PATH" }
if ($installedVersion) { Write-Detail "  Replacing ..: $installedVersion" }
Write-Detail ''

if (-not $Yes) {
	$answer = try { Read-Host '  Proceed? [y/N]' } catch { '' }
	if ([string]$answer -notmatch '^[Yy]') {
		Write-Detail ''
		Write-Status 'Nothing was changed.'
		Write-Host ''
		return
	}
	Write-Detail ''
}


#-------------------------------------------------------------------------------
## Fetch, verify, install.

$tempRoot = [System.IO.Path]::GetTempPath()
$work = Join-Path $tempRoot ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
	$archive = Join-Path $work $asset
	$checksums = Join-Path $work 'checksums.txt'

	Write-Status 'Downloading'
	try { Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $archive @webArgs }
	catch { Stop-WithMessage "couldn't download $baseUrl/$asset ($($_.Exception.Message))" }
	try { Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile $checksums @webArgs }
	catch { Stop-WithMessage "couldn't download the checksums for $tag ($($_.Exception.Message))" }

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

	$otherTarget = if ($Target -eq 'system') { 'user' } else { 'system' }
	try {
		Clear-InstallDirectory
		New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
		Copy-Item -Path (Join-Path $payload.FullName '*') -Destination $installDirectory -Recurse -Force
	}
	catch {
		## A running zuid.exe can't be deleted on Windows.
		Stop-WithMessage "couldn't write ${installDirectory}: $($_.Exception.Message) Close any running $program, check the permissions, or try -Target $otherTarget."
	}

	if ($linkDirectory) {
		$link = Join-Path $linkDirectory $program
		try {
			New-Item -ItemType Directory -Path $linkDirectory -Force | Out-Null
			if (Test-Path $link) { Remove-Item -Force $link }
			New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $installDirectory "bin/$binaryName") | Out-Null
		}
		catch { Stop-WithMessage "couldn't write ${link}: $($_.Exception.Message) Check its permissions, or try -Target $otherTarget." }
	}

	Write-Detail ''
	Write-Status "Installed $tag to $installDirectory"
	if ($onWindows) { Set-WindowsPath $true }
	elseif (($env:PATH -split [System.IO.Path]::PathSeparator) -notcontains $linkDirectory) {
		Write-Detail "  Note: $linkDirectory is not on your PATH."
	}
	Write-Detail "  Try: $program --help"
	Write-Host ''
}
finally {
	try { Remove-Under $tempRoot $work } catch { Write-Detail "  Left behind: $work" }
}
