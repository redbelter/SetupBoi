<#
.SYNOPSIS
  SetupBoi bootstrapper - one file that downloads the repo and runs setup.
.DESCRIPTION
  On a FRESH machine you only need this file (or just curl it). It fetches the
  repo as a zip, unpacks it, and launches setup.ps1 with your config.

  Usage on a bare PC (paste in an elevated PowerShell):

    Set-ExecutionPolicy Bypass -Scope Process -Force
    Invoke-WebRequest https://raw.githubusercontent.com/redbelter/SetupBoi/main/setupboi.ps1 -OutFile setupboi.ps1
    .\setupboi.ps1

  Flags:
    -Branch main          branch/subdir of the repo to pull
    -Repo redbelter/SetupBoi
    -Config <path>        a config.json already on disk (or http url) to use
    -DryRun, -Only a,b, -Skip a,b, -Reboot    passed straight to setup.ps1
#>
param(
    [string]$Repo   = 'redbelter/SetupBoi',
    [string]$Branch = 'main',
    [string]$Config,
    [switch]$DryRun,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$Reboot
)

$ErrorActionPreference = 'Stop'
$stage  = Join-Path $env:TEMP 'SetupBoi'
$zip    = Join-Path $env:TEMP 'SetupBoi.zip'
$url    = "https://github.com/$Repo/archive/refs/heads/$Branch.zip"

Write-Host "[setupboi] downloading $url" -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

Write-Host '[setupboi] unpacking...' -ForegroundColor Cyan
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Expand-Archive -Path $zip -DestinationPath $stage -Force

# zip unpacks to SetupBoi-<branch>/...
$root = Get-ChildItem $stage -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'setup.ps1') } | Select-Object -First 1
if (-not $root) { throw 'setup.ps1 not found in the downloaded archive' }

# if a remote config was given, download it into the repo root as config.json
if ($Config -and $Config -match '^https?://') {
    Invoke-WebRequest -Uri $Config -OutFile (Join-Path $root.FullName 'config.json') -UseBasicParsing
    $Config = Join-Path $root.FullName 'config.json'
}

$setupArgs = @('-ExecutionPolicy','Bypass','-NoProfile','-File', (Join-Path $root.FullName 'setup.ps1'))
if ($Config) { $setupArgs += @('-Config', $Config) }
if ($DryRun) { $setupArgs += '-DryRun' }
if ($Only)   { $setupArgs += @('-Only', ($Only -join ',')) }
if ($Skip)   { $setupArgs += @('-Skip', ($Skip -join ',')) }
if ($Reboot) { $setupArgs += '-Reboot' }

Write-Host "[setupboi] launching setup.ps1" -ForegroundColor Cyan
& powershell.exe @setupArgs
exit $LASTEXITCODE
