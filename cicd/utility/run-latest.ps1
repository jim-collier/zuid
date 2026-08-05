<#
.SYNOPSIS
	Runs the newest release build from a scratch copy, keeping the dogfood
	install out of it.

.DESCRIPTION
	Copies zig-out/bin/zuid to a date-stamped name in a scratch directory, drops
	older copies that nothing is holding open, and runs the new one with every
	argument forwarded. Nothing here touches the installed binary, so a build
	can be tried out while the daily one stays where it is.

	Everything after -- goes to zuid.

.PARAMETER KeepDays
	Age at which an unused copy is dropped. Default 7.

.PARAMETER ScratchDir
	Where the stamped copies live. Defaults to a zuid-builds directory under the
	system temporary directory.

.EXAMPLE
	./run-latest.ps1 -- -f '%d%r'

.NOTES
	Copyright (c) 2026 Jim Collier. MIT licensed: https://mit-license.org/
	SPDX-License-Identifier: MIT
#>

[CmdletBinding()]
param(
	[int] $KeepDays = 7,
	[string] $ScratchDir,
	[Parameter(ValueFromRemainingArguments = $true)] [string[]] $Forwarded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$program = 'zuid'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$built = Join-Path $repoRoot (Join-Path 'zig/zig-out/bin' $(if ($IsWindows) { "$program.exe" } else { $program }))

if (-not (Test-Path $built)) {
	throw "run-latest: no release build at $built. Run cicd.bash first."
}

if (-not $ScratchDir) {
	$ScratchDir = Join-Path ([System.IO.Path]::GetTempPath()) "$program-builds"
}
New-Item -ItemType Directory -Path $ScratchDir -Force | Out-Null


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Drop aged-out copies. A file still open is skipped rather than fought over.

$cutoff = (Get-Date).AddDays(-$KeepDays)
Get-ChildItem -Path $ScratchDir -File -Filter "$program-*" |
	Where-Object { $_.LastWriteTime -lt $cutoff } |
	ForEach-Object {
		try { Remove-Item -Force $_.FullName }
		catch { Write-Verbose "still in use, keeping: $($_.Name)" }
	}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Stamp a fresh copy and run it. The stamp comes from the build, not the clock,
## so running the same build twice reuses one copy.

$stamp = (Get-Item $built).LastWriteTime.ToString('yyyyMMdd-HHmmss')
$suffix = if ($IsWindows) { '.exe' } else { '' }
$copy = Join-Path $ScratchDir "$program-$stamp$suffix"

if (-not (Test-Path $copy)) {
	Copy-Item -Path $built -Destination $copy -Force
	if (-not $IsWindows) { chmod +x $copy }
}

& $copy @Forwarded
exit $LASTEXITCODE
