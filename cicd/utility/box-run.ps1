#!/usr/bin/env pwsh
<#
.SYNOPSIS
	The Windows half of box-run.bash, sent along with the job.

.DESCRIPTION
	-Run sweeps the project's stale run folders beside the given one, then runs
	its job.ps1 there at below normal priority, with TEMP and TMP pointed at it.
	-Remove takes the run folder off the box through the guard. Both take only a
	folder named <YYYYmmDD-HHMMSS>_<NNN>, directly under <temp root>\zuid, where
	the temp root is HOST_TEMP if set, else TEMP. A link is unlinked, never
	followed.

.PARAMETER Run
	The run folder whose job.ps1 to run.

.PARAMETER Remove
	The run folder to remove.

.NOTES
	Copyright (C) 2026 Jim Collier. MIT licensed: https://mit-license.org/
	SPDX-License-Identifier: MIT
#>

## Called by box-run.bash, which reads the job's output as the step's log.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
[CmdletBinding()]
param(
	[string] $Run,
	[string] $Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$onWindows = $PSVersionTable.PSVersion.Major -lt 6 -or $IsWindows

function Test-IsLink { param([IO.FileSystemInfo] $Item) return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) }

function Remove-Tree {
	param([IO.FileSystemInfo] $Item)
	if ($Item -is [IO.DirectoryInfo] -and -not (Test-IsLink $Item)) {
		foreach ($child in @($Item.GetFileSystemInfos())) { Remove-Tree $child }
	}
	if ($onWindows -and ($Item.Attributes -band [IO.FileAttributes]::ReadOnly)) {
		$Item.Attributes = $Item.Attributes -band -bnot [IO.FileAttributes]::ReadOnly
	}
	$Item.Delete()
}

## <temp root>\zuid, which has to be a real folder.
function Get-ProjectRoot {
	$root = if ($env:HOST_TEMP) { $env:HOST_TEMP } else { $env:TEMP }
	if (-not $root) { throw 'box-run: no HOST_TEMP or TEMP here' }
	$base = Get-Item -LiteralPath (Join-Path $root 'zuid') -Force
	if (Test-IsLink $base) { throw "box-run: refused, $($base.FullName) is a link" }
	return $base
}

## The run folder, if it's one of ours, else a throw.
function Get-RunDirectory {
	param([string] $Path)
	$base = Get-ProjectRoot
	$item = Get-Item -LiteralPath $Path -Force
	$case = if ($onWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
	if (-not ($item -is [IO.DirectoryInfo]) -or (Test-IsLink $item)) { throw "box-run: refused, not a plain folder: $Path" }
	if ($item.Name -notmatch '^[0-9]{8}-[0-9]{6}_[0-9]{3}$') { throw "box-run: refused, not a run folder's name: $Path" }
	if (-not [string]::Equals($item.Parent.FullName.TrimEnd('\', '/'), $base.FullName.TrimEnd('\', '/'), $case)) {
		throw "box-run: refused, not directly under $($base.FullName): $Path"
	}
	return $item
}

if ($Remove) {
	Remove-Tree (Get-RunDirectory $Remove)
	Write-Host "removed $Remove"
	exit 0
}

if (-not $Run) { throw 'box-run: -Run <folder> or -Remove <folder>' }
$dir = Get-RunDirectory $Run
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch { Write-Verbose 'priority not settable' }
Set-Content -LiteralPath (Join-Path $dir.FullName 'run.pid') -Value $PID

## Over 2 days old, with nothing left running from it.
$cutoff = (Get-Date).AddDays(-2)
foreach ($old in @($dir.Parent.GetDirectories())) {
	if ($old.FullName -eq $dir.FullName -or $old.Name -notmatch '^[0-9]{8}-[0-9]{6}_[0-9]{3}$' -or $old.LastWriteTime -gt $cutoff) { continue }
	$pidFile = Join-Path $old.FullName 'run.pid'
	if (Test-Path -LiteralPath $pidFile) {
		$oldPid = 0
		if ([int]::TryParse(([string](Get-Content -LiteralPath $pidFile -TotalCount 1)).Trim(), [ref] $oldPid) -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) { continue }
	}
	try { Remove-Tree (Get-RunDirectory $old.FullName); Write-Host "Swept ......: $($old.FullName)" }
	catch { Write-Host "Not swept ..: $($old.FullName) ($($_.Exception.Message))" }
}

$env:ZUID_RUN_DIR = $dir.FullName; $env:TEMP = $dir.FullName; $env:TMP = $dir.FullName
Set-Location -LiteralPath $dir.FullName
$global:LASTEXITCODE = 0
& (Join-Path $dir.FullName 'job.ps1')
exit $LASTEXITCODE
