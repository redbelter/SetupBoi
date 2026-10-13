<#
.SYNOPSIS
  SetupBoi - configure a fresh Windows machine from a single JSON config.
.DESCRIPTION
  Run on a brand-new PC (after installing git, or from a USB copy of this repo):

    powershell -ExecutionPolicy Bypass -File .\setup.ps1

  Options:
    -Config <path>   JSON config (default: .\config.json, else .\config.example.json)
    -DryRun          print every action without touching anything
    -Only a,b        run only these steps
    -Skip a,b        skip these steps
    -NoElevate       do not self-elevate to admin
    -Reboot          reboot when finished (applies start/taskbar pins)
.NOTES
  Steps (in order): experience, bloatware, onedrive, wallpaper, colors,
                    icons, taskbar, startmenu, install, custom
#>
[CmdletBinding()]
param(
    [string]$Config,
    [switch]$DryRun,
    [string[]]$Only,
    [string[]]$Skip,
    [switch]$NoElevate,
    [switch]$Reboot
)

$ErrorActionPreference = 'Continue'
$RepoRoot = $PSScriptRoot

# ---- console banner -------------------------------------------------------
$logo = @"
  ____             _      ____    _  ___
 / ___|  ___  ___ | |__  | __ )  (_)/ _ \
 \___ \ / _ \/ __|| '_ \ |  _ \  | | (_) |
  ___) |  __/\__ \| | | || |_) | | |\__, |
 |____/ \___||___/|_| |_||____/  |_|   /_/
"@
Write-Host $logo -ForegroundColor Magenta
Write-Host '  fresh-windows setup from one config file' -ForegroundColor DarkGray
Write-Host ''

# ---- config discovery -----------------------------------------------------
if (-not $Config) {
    $candidates = @(
        "$RepoRoot\config.json",
        "$RepoRoot\config.example.json",
        "$RepoRoot\config.example.jsonc"
    )
    $Config = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Config -or -not (Test-Path $Config)) {
    Write-Host "config not found: $Config" -ForegroundColor Red
    Write-Host 'copy config.example.json to config.json and edit it.' -ForegroundColor Yellow
    exit 1
}
Write-Host "config: $Config" -ForegroundColor DarkGray

try {
    $raw = Get-Content -LiteralPath $Config -Raw -Encoding UTF8
    # strip comments so people can annotate their config:
    #   full-line "// ..." and trailing " ... // ..." (space before // protects URLs)
    $raw = ($raw -split "`n" | ForEach-Object {
        $_ -replace '^\s*//.*$','' -replace '\s+//.*$',''
    }) -join "`n"
    $Cfg = $raw | ConvertFrom-Json
} catch {
    Write-Host "config is not valid JSON: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# -Only/-Skip may arrive as one comma-joined string after elevation re-launch
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

# ---- module + features ----------------------------------------------------
Import-Module "$RepoRoot\scripts\SetupBoi.psm1" -Force
Set-BoiDryRun ([bool]$DryRun)
if (-not $DryRun) { Start-BoiJournal -ConfigPath $Config }

Get-ChildItem "$RepoRoot\scripts\features\*.ps1" | ForEach-Object {
    . $_.FullName
}

# ordered pipeline: key -> script function
$pipeline = [ordered]@{
    'experience' = { Invoke-BoiExperience $Cfg }
    'bloatware'  = { Invoke-BoiBloatware  $Cfg }
    'onedrive'   = { Invoke-BoiOneDrive   $Cfg }
    'install'    = { Invoke-BoiInstall    $Cfg }   # before pins so new apps resolve
    'wallpaper'  = { Invoke-BoiWallpaper  $Cfg }
    'colors'     = { Invoke-BoiColors     $Cfg }
    'icons'      = { Invoke-BoiDesktopIcons $Cfg }
    'taskbar'    = { Invoke-BoiTaskbar    $Cfg }
    'startmenu'  = { Invoke-BoiStart      $Cfg }
    'custom'     = { Invoke-BoiCustom     $Cfg }
}

# ---- elevation ------------------------------------------------------------
$needsAdmin = (-not $DryRun) -and (
    ($Cfg.bloatware -and $Cfg.bloatware.enabled) -or
    ($Cfg.onedrive -and $Cfg.onedrive.enabled) -or
    ($Cfg.install -and $Cfg.install.enabled) -or
    ($null -ne $Cfg.requireAdmin -and $Cfg.requireAdmin)
)
if ($Only) {
    $needsAdmin = $needsAdmin -or (@($Only | Where-Object { 'bloatware','onedrive','install' -contains $_ }).Count -gt 0)
}
if ($needsAdmin -and -not (Test-BoiAdmin) -and -not $NoElevate) {
    $childArgs = @()
    if ($Config) {
        $full = try { (Resolve-Path $Config).Path } catch { $Config }
        $childArgs += "-Config `"$full`""
    }
    if ($Only)    { $childArgs += "-Only `"$($Only -join ',')`"" }
    if ($Skip)    { $childArgs += "-Skip `"$($Skip -join ',')`"" }
    if ($Reboot)  { $childArgs += '-Reboot' }
    $childArgs += '-NoElevate'
    Request-BoiAdmin -ScriptPath $PSCommandPath -Arguments $childArgs
    exit 0
}
if ($DryRun) {
    Write-Host 'DRY RUN - nothing will be touched' -ForegroundColor Magenta
} elseif ((Test-BoiAdmin)) {
    Write-Host 'running as administrator' -ForegroundColor DarkGray
} else {
    Write-Host 'not admin - HKLM/AppX/winget steps may partially fail (use -NoElevate only deliberately)' -ForegroundColor Yellow
}
Write-Host ''

# ---- run pipeline ---------------------------------------------------------
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($step in $pipeline.Keys) {
    if ($Only -and $Only -notcontains $step) { continue }
    if ($Skip -and $Skip -contains $step) {
        Write-Boi "step '$step' skipped via -Skip" 'INFO'
        continue
    }
    Write-Host ("--- {0} {1}" -f $step, ('-' * (56 - $step.Length))) -ForegroundColor DarkCyan
    try {
        & $pipeline[$step]
    } catch {
        Write-Boi "step '$step' threw: $($_.Exception.Message)" 'ERR'
        Add-BoiResult $step 'FAIL' $_.Exception.Message
    }
    Write-Host ''
}
$sw.Stop()

if (-not $DryRun) { Stop-BoiJournal }

# ---- summary --------------------------------------------------------------
Write-Host '=== SUMMARY ==========================================' -ForegroundColor Cyan
$results = Get-BoiResults
if ($results.Count -eq 0) {
    Write-Host '  (no results - was every section disabled?)' -ForegroundColor Yellow
}
foreach ($r in $results) {
    $color = switch ($r.Status) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        'SKIP' { 'DarkGray' }
    }
    Write-Host ("  [{0,-4}] {1,-28} {2}" -f $r.Status, $r.Name, $r.Detail) -ForegroundColor $color
}
Write-Host ("  total: {0:N1}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor DarkGray

# ---- after actions ---------------------------------------------------------
$after = $null
if ($Cfg.custom -and $Cfg.custom.after) { $after = $Cfg.custom.after }
if ($after) {
    Write-Host ''
    Write-Host 'manual follow-ups from your config:' -ForegroundColor Yellow
    foreach ($a in $after) { Write-Host "  - $a" -ForegroundColor Yellow }
}

if ($Reboot -and -not $DryRun) {
    Write-Host 'rebooting in 10s to apply pins (Ctrl+C to cancel)...' -ForegroundColor Yellow
    shutdown /r /t 10 /c "SetupBoi finishing"
} else {
    Write-Host ''
    Write-Host 'sign out & back in (or -Reboot) to apply start/taskbar pins.' -ForegroundColor DarkGray
}
