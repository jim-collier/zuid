#!/usr/bin/env pwsh
<#
.SYNOPSIS
	Runs on the Windows box as job.ps1, in the folder box-run.bash sent.

.DESCRIPTION
	Runs the command from the one zuid-*-windows-x86_64.zip there, then has
	install.ps1 install that zip under Windows PowerShell 5.1 and PowerShell 7,
	user and system, and uninstall it, with both PATHs checked back byte for
	byte. install.ps1 runs as the one-liner does, from a scriptblock, with its
	GitHub calls answered from this folder: a listing with the one release, the
	zip, and checksums.txt from the run. It also has to refuse an install dir
	that is a junction, in one plain line.

	The user install and the command's module cache go under this folder, by
	way of LOCALAPPDATA. The system install needs an admin session and no
	Program Files\zuid already there. Whatever happens, both PATHs end as they
	started.

.NOTES
	Copyright (C) 2026 Jim Collier. MIT licensed: https://mit-license.org/
	SPDX-License-Identifier: MIT
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$here = (Get-Location).Path
$script:fails = 0

function Write-Ok { param([string] $Name) Write-Host "  ok ......: $Name" }
function Write-Fail { param([string] $Name, [string] $Detail) $script:fails++; Write-Host "  FAIL ....: $Name ($Detail)" }
function Test-That { param([bool] $Cond, [string] $Name, [string] $Detail) if ($Cond) { Write-Ok $Name } else { Write-Fail $Name $Detail } }
function Show-Output { param([string] $Text) foreach ($line in ($Text -split "`r?`n")) { if ($line.Trim()) { Write-Host "      | $line" } } }

function Open-PathKey {
	param([string] $Scope, [bool] $Writable)
	if ($Scope -eq 'Machine') { return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $Writable) }
	return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $Writable)
}
function Get-PathValue {
	param([string] $Scope)
	$key = Open-PathKey $Scope $false
	try {
		$raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
		$kind = if ($raw) { [string]$key.GetValueKind('Path') } else { 'none' }
	}
	finally { $key.Close() }
	return [pscustomobject]@{ Raw = $raw; Kind = $kind }
}
function Set-PathValue {
	param([string] $Scope, [object] $Saved)
	$key = Open-PathKey $Scope $true
	try { $key.SetValue('Path', $Saved.Raw, [Microsoft.Win32.RegistryValueKind]$Saved.Kind) } finally { $key.Close() }
}

## Unlinks, never follows, for what a failed step left.
function Remove-Mine {
	param([IO.FileSystemInfo] $Item)
	if ($Item -is [IO.DirectoryInfo] -and -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
		foreach ($child in @($Item.GetFileSystemInfos())) { Remove-Mine $child }
	}
	$Item.Attributes = $Item.Attributes -band -bnot [IO.FileAttributes]::ReadOnly
	$Item.Delete()
}

## The command, from the zip as it is.
$zips = @(Get-ChildItem -LiteralPath $here -Filter 'zuid-*-windows-x86_64.zip')
if ($zips.Count -ne 1) { throw "box job: wants one zuid-*-windows-x86_64.zip here, found $($zips.Count)" }
$zip = $zips[0]
$version = $zip.Name -replace '^zuid-(.+)-windows-x86_64\.zip$', '$1'
$env:LOCALAPPDATA = Join-Path $here 'appdata'
New-Item -ItemType Directory -Path $env:LOCALAPPDATA | Out-Null
$unpacked = Join-Path $here 'unpacked'
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $unpacked
$exe = Join-Path $unpacked "zuid-v$version\bin\zuid.exe"
Write-Host "Box ........: $([Environment]::OSVersion.VersionString), PowerShell $($PSVersionTable.PSVersion), $env:USERNAME"
Write-Host "Release ....: $($zip.Name)"
Write-Host ''
Write-Host '[ The command ]'
$ErrorActionPreference = 'Continue'
$out = @(& $exe --version 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
Test-That ($code -eq 0 -and $out.Count -gt 0 -and $out[0] -match "^zuid v$([regex]::Escape($version)) build [0-9a-z]+") "--version names $version ($(if ($out.Count) { $out[0] }))" -Detail "exit $code"
$out = @(& $exe 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
Test-That ($code -eq 0 -and $out.Count -eq 1 -and $out[0] -match '^[0-9A-Za-z]+$') "a default identifier ($(if ($out.Count) { $out[0] }))" -Detail "exit $code, $($out -join ' | ')"
## With %r, since a time-only batch repeats and warns on stderr.
$out = @(& $exe --count=3 '--format=%d%r' 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
Test-That ($code -eq 0 -and $out.Count -eq 3 -and @($out | Select-Object -Unique).Count -eq 3) '--count=3 gives 3 different lines' -Detail "exit $code, $($out -join ' | ')"
$out = @(& $exe '--format=x-%r' 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
Test-That ($code -eq 0 -and $out.Count -eq 1 -and $out[0] -match '^x-[0-9A-Za-z]+$') "a literal and %r ($(if ($out.Count) { $out[0] }))" -Detail "exit $code, $($out -join ' | ')"
$out = @(& $exe --no-such-flag 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
Test-That ($code -ne 0) 'an unknown flag fails' -Detail "exit $code"
$ErrorActionPreference = 'Stop'

## The release install.ps1 is handed, in place of GitHub.
$release = Join-Path $here 'release'
New-Item -ItemType Directory -Path $release | Out-Null
Move-Item -LiteralPath $zip.FullName -Destination $release
Move-Item -LiteralPath (Join-Path $here 'checksums.txt') -Destination $release
$shim = Join-Path $here 'install-from-here.ps1'
Set-Content -LiteralPath $shim -Encoding Ascii -Value @'
param([string] $Installer, [string] $From, [string] $Version)
## Shadow the cmdlets install.ps1 calls, the way a stub dot-sourced ahead of it
## would. Scope is dynamic, so a plain $Version in them would be install.ps1's.
$script:boxFrom = $From; $script:boxVersion = $Version
function Invoke-RestMethod {
	param([string] $Uri, [hashtable] $Headers, [switch] $UseBasicParsing)
	if ($Uri -notlike 'https://api.github.com/repos/jim-collier/zuid/releases*') { throw "unexpected lookup: $Uri" }
	return @([pscustomobject]@{ tag_name = "v$($script:boxVersion)"; draft = $false; prerelease = ($script:boxVersion -like '*-*') })
}
function Invoke-WebRequest {
	param([string] $Uri, [string] $OutFile, [switch] $UseBasicParsing)
	$want = "https://github.com/jim-collier/zuid/releases/download/v$($script:boxVersion)/"
	if (-not $Uri.StartsWith($want)) { throw "unexpected download: $Uri" }
	Copy-Item -LiteralPath (Join-Path $script:boxFrom $Uri.Substring($want.Length)) -Destination $OutFile
}
## Each shell shows an error its own way, and 5.1 repeats it, so the check
## reads the message alone.
try { & ([scriptblock]::Create((Get-Content -Raw -LiteralPath $Installer))) @args }
catch { Write-Output "error from install.ps1: $($_.Exception.Message)"; exit 1 }
'@

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$savedUser = Get-PathValue 'User'
$savedMachine = Get-PathValue 'Machine'
$dirs = @{ user = (Join-Path $env:LOCALAPPDATA 'Programs\zuid'); system = (Join-Path $env:ProgramFiles 'zuid') }
$systemThere = Test-Path -LiteralPath $dirs['system']
$shells = [ordered]@{ '5.1' = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'); '7' = (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe') }
$installer = Join-Path $here 'install.ps1'

function Invoke-Install {
	param([string] $Shell, [string[]] $Options)
	$ErrorActionPreference = 'Continue'
	$text = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $shim -Installer $installer -From $release -Version $version @Options 2>&1 | Out-String
	return [pscustomobject]@{ Out = $text; Code = $LASTEXITCODE }
}

try {
	foreach ($shellName in $shells.Keys) {
		$shell = $shells[$shellName]
		Write-Host ''
		Write-Host "[ install.ps1 under PowerShell $shellName ]"
		if (-not (Test-Path -LiteralPath $shell)) { Write-Fail "PowerShell $shellName" "no $shell"; continue }
		foreach ($target in @('user', 'system')) {
			$name = "$shellName $target"
			if ($target -eq 'system' -and -not $isAdmin) { Write-Fail "$name install" 'not an admin session'; continue }
			if ($target -eq 'system' -and $systemThere) { Write-Fail "$name install" "$($dirs['system']) was there before the run, so it's left alone"; continue }
			$dir = $dirs[$target]
			$scope = if ($target -eq 'system') { 'Machine' } else { 'User' }
			$saved = if ($target -eq 'system') { $savedMachine } else { $savedUser }
			$bin = Join-Path $dir 'bin'
			$opts = @('-Target', $target)

			## Refused, in one plain line: an install dir that is a junction.
			$elsewhere = Join-Path $here "elsewhere-$shellName-$target"
			New-Item -ItemType Directory -Path $elsewhere | Out-Null
			Set-Content -LiteralPath (Join-Path $elsewhere 'mine.txt') -Value 'x'
			New-Item -ItemType Directory -Path (Split-Path -Parent $dir) -Force | Out-Null
			New-Item -ItemType Junction -Path $dir -Value $elsewhere | Out-Null
			$r = Invoke-Install $shell ($opts + '-Yes')
			$said = @($r.Out -split "`r?`n" | Where-Object { $_ -like 'error from install.ps1: *' })
			$plain = $said.Count -eq 1 -and $said[0] -like "error from install.ps1: zuid-install: refused to empty *: it's a link, so it was left alone." -and $said[0] -notmatch "couldn't write|zuid-install:.*zuid-install:"
			Test-That ($r.Code -ne 0 -and $plain -and (Test-Path -LiteralPath (Join-Path $elsewhere 'mine.txt'))) "$name refuses an install dir that's a junction, in one plain line" -Detail "exit $($r.Code)"
			if (-not $plain) { Show-Output $r.Out }
			(Get-Item -LiteralPath $dir -Force).Delete()

			$r = Invoke-Install $shell ($opts + '-Yes')
			$exeIn = Join-Path $bin 'zuid.exe'
			$ver = ''
			if (Test-Path -LiteralPath $exeIn) { $ver = [string](@(& $exeIn --version 2>&1)[0]) }
			Test-That ($r.Code -eq 0 -and $ver -match "^zuid v$([regex]::Escape($version)) ") "$name install runs ($ver)" -Detail "exit $($r.Code)"
			if ($r.Code -ne 0) { Show-Output $r.Out }
			$now = Get-PathValue $scope
			Test-That (@($now.Raw -split ';') -contains $bin) "$name install puts $bin on the $($scope.ToLower()) PATH" -Detail 'not there'
			Test-That ($now.Kind -eq $saved.Kind -or $saved.Kind -eq 'none') "$name install keeps the PATH's value kind ($($now.Kind))" -Detail "$($saved.Kind) before"

			$r = Invoke-Install $shell ($opts + '-Yes')
			$again = Get-PathValue $scope
			Test-That ($r.Code -eq 0 -and $r.Out -match 'Already installed' -and $again.Raw -ceq $now.Raw) "$name install again changes nothing" -Detail "exit $($r.Code)"

			$r = Invoke-Install $shell ($opts + '-Uninstall', '-Yes')
			Test-That ($r.Code -eq 0 -and -not (Test-Path -LiteralPath $dir)) "$name uninstall removes $dir" -Detail "exit $($r.Code)"
			if ($r.Code -ne 0) { Show-Output $r.Out }
			$after = Get-PathValue $scope
			Test-That ($after.Raw -ceq $saved.Raw -and $after.Kind -eq $saved.Kind) "$name uninstall gives the $($scope.ToLower()) PATH back byte for byte" -Detail "$($saved.Raw.Length) chars $($saved.Kind) before, $($after.Raw.Length) $($after.Kind) after"
		}
	}
}
finally {
	foreach ($pair in @(@('User', $savedUser), @('Machine', $savedMachine))) {
		$cur = Get-PathValue $pair[0]
		if ($cur.Raw -cne $pair[1].Raw -and $pair[1].Kind -ne 'none' -and ($pair[0] -eq 'User' -or $isAdmin)) {
			Set-PathValue $pair[0] $pair[1]
			Write-Host "Restored ...: the $($pair[0].ToLower()) PATH, from the copy taken at the start"
		}
	}
	if (-not $systemThere) {
		$left = Get-Item -LiteralPath $dirs['system'] -Force -ErrorAction SilentlyContinue
		if ($left) { Remove-Mine $left; Write-Host "Removed ....: $($dirs['system']), left by a failed step" }
	}
}

Write-Host ''
Write-Host "[ Failed: $($script:fails) ]"
exit $(if ($script:fails) { 1 } else { 0 })
