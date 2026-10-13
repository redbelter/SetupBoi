<#
.SYNOPSIS
  Roll back what SetupBoi did. Replays %LOCALAPPDATA%\SetupBoi\journal.json
  newest-first: restores every registry value it changed, re-copies deleted
  files/folders from the per-run backup, deletes files it created, and lists
  anything it cannot safely reverse (removed AppX packages, winget installs).
.DESCRIPTION
  undo.ps1                    # roll back the LAST run
  undo.ps1 -All               # roll back every journaled run
  undo.ps1 -Run 20261013-...  # roll back a specific run id
  undo.ps1 -List              # show run history, change nothing
  undo.ps1 -DryRun            # print what would be undone
.NOTES
  AppX removals are journaled but NOT auto-reverted (store reinstall is the
  fix); winget installs are never touched by undo - list only.
#>
[CmdletBinding()]
param(
    [string]$Run,
    [switch]$All,
    [switch]$List,
    [switch]$DryRun
)

$RepoRoot = $PSScriptRoot
Import-Module "$RepoRoot\scripts\SetupBoi.psm1" -Force
Set-BoiDryRun ([bool]$DryRun)
$script:JournalRun = 'undo'
# undo's own registry writes must not pollute the journal
$SetupBoiJournal = Get-Module SetupBoi
& $SetupBoiJournal { $script:JournalQuiet = $true } | Out-Null

$journal = Get-BoiJournal
if (-not $journal -or $journal.Count -eq 0) {
    Write-Host 'no journal found - setupboi has not run yet' -ForegroundColor Yellow
    exit 0
}

# ---- run history ----------------------------------------------------------
$runs = $journal | Where-Object { $_.run -and $_.kind -eq 'run' -and $_.action -eq 'begin' }
if ($List) {
    Write-Host 'journalled runs:' -ForegroundColor Cyan
    $runs | ForEach-Object {
        Write-Host ("  {0}  config={1}" -f $_.run, $_.config)
    }
    $ops = $journal | Where-Object { $_.kind -ne 'run' }
    Write-Host ("  ({0} recorded operations total)" -f @($ops).Count) -ForegroundColor DarkGray
    exit 0
}

# ---- select what to undo ---------------------------------------------------
if ($All)      { $targetRuns = @($runs | ForEach-Object { $_.run }) }
elseif ($Run)  { $targetRuns = @($Run) }
else           { $targetRuns = @((Get-BoiLastRunId)) }

if (-not $targetRuns -or -not $targetRuns[0]) {
    Write-Host 'nothing to undo (no runs in journal)' -ForegroundColor Yellow
    exit 0
}

$ops = @($journal | Where-Object { $_.kind -ne 'run' -and $targetRuns -contains $_.run })
# oldest-first order of runs, but within replay: newest operation first
$ops = $ops | Sort-Object at -Descending

Write-Host ("undoing {0} operations from runs: {1}" -f $ops.Count, ($targetRuns -join ', ')) -ForegroundColor Cyan

$undone = 0; $failed = 0; $skipped = 0
foreach ($e in $ops) {
    try {
        switch ($e.kind) {
            'reg' {
                if ($e.action -eq 'set') {
                    if ($e.oldExists) {
                        Set-RegValue $e.path $e.name $e.oldValue -Type $e.type
                        Write-Boi "restored $($e.path)\$($e.name) = $($e.oldValue)" 'OK'
                    } else {
                        Remove-RegValue $e.path $e.name
                        Write-Boi "removed value it created: $($e.path)\$($e.name)" 'OK'
                    }
                } elseif ($e.action -eq 'remove') {
                    Set-RegValue $e.path $e.name $e.oldValue -Type $e.type
                    Write-Boi "re-added $($e.path)\$($e.name) = $($e.oldValue)" 'OK'
                }
                $undone++
            }
            'tree' {
                if ($e.action -eq 'delete') {
                    if ($e.backup -and (Test-Path $e.backup)) {
                        & robocopy $e.backup $e.path /E /NFL /NDL /NJH /NJS /NP | Out-Null
                        Write-Boi "restored $e.path from backup" 'OK'
                        $undone++
                    } elseif ($e.backup) {
                        Write-Boi "backup missing for $($e.path) - cannot restore" 'ERR'
                        $failed++
                    } else {
                        Write-Boi "$($e.path) was deleted without backup (too large) - cannot restore" 'WARN'
                        $skipped++
                    }
                } elseif ($e.action -eq 'create') {
                    Invoke-BoiAction -Description "delete dir setupboi created: $($e.path)" -Action {
                        Remove-Item -LiteralPath $e.path -Recurse -Force -EA SilentlyContinue
                    }
                    $undone++
                }
            }
            'file' {
                if ($e.action -in @('delete','backup')) {
                    if ($e.backup -and (Test-Path $e.backup)) {
                        New-Item -ItemType Directory -Force -Path (Split-Path $e.path) | Out-Null
                        Copy-Item -LiteralPath $e.backup -Destination $e.path -Force
                        Write-Boi "restored file $($e.path)" 'OK'
                        $undone++
                    } else {
                        Write-Boi "no backup for $($e.path) - cannot restore" 'WARN'
                        $skipped++
                    }
                } elseif ($e.action -eq 'create') {
                    Invoke-BoiAction -Description "delete file setupboi created: $($e.path)" -Action {
                        Remove-Item -LiteralPath $e.path -Force -EA SilentlyContinue
                    }
                    $undone++
                }
            }
            'appx' {
                Write-Boi "removed appx: $($e.detail) v$($e.version) - reinstall via  winget install / Microsoft Store" 'WARN'
                $skipped++
            }
            default { $skipped++ }
        }
    } catch {
        Write-Boi "undo failed for $($e.kind) $($e.path)\$($e.name): $($_.Exception.Message)" 'ERR'
        $failed++
    }
}

Write-Host ''
Write-Host ("undo complete: {0} reverted, {1} skipped (manual), {2} failed" -f $undone, $skipped, $failed) -ForegroundColor Cyan

# winget installs were never journaled as mutations; remind the human
Write-Host 'note: winget-installed apps are NOT uninstalled by undo (list was in your config). Remove with: winget uninstall <id>' -ForegroundColor DarkGray

if (-not $DryRun) { Restart-BoiShell }
