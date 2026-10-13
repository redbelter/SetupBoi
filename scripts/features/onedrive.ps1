# Full OneDrive removal: stop the process, run the built-in uninstaller,
# delete leftovers (folder, scheduled tasks, services, run key, startup).
# config.onedrive: { enabled: bool }
# (Runs before installs so OneDrive can't re-provision mid-run.)

function Invoke-BoiOneDrive {
    param([Parameter(Mandatory)]$Cfg)

    $o = $Cfg.onedrive
    if (-not $o -or -not $o.enabled) { Add-BoiResult 'onedrive removal' 'SKIP'; return }

    Write-Boi 'removing OneDrive' 'STEP'

    Invoke-BoiAction -Description 'stop OneDrive processes' -Action {
        taskkill /f /im OneDrive.exe 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }

    # The official uninstaller (keeps user files in %USERPROFILE%\OneDrive)
    $unins = @(
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",   # 64-bit OS
        "$env:SystemRoot\System32\OneDriveSetup.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($unins) {
        Invoke-BoiAction -Description "run official uninstaller: $unins /uninstall" -Action {
            Start-Process -FilePath $unins -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    } else {
        Write-Boi 'OneDriveSetup.exe not found (already uninstalled?)' 'INFO'
    }

    # Kill any per-user install under %LOCALAPPDATA%
    $userUninst = Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe'
    if (Test-Path $userUninst) {
        Invoke-BoiAction -Description 'uninstall per-user OneDrive' -Action {
            Start-Process -FilePath $userUninst -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    }

    Write-Boi 'cleaning OneDrive leftovers' 'STEP'
    Remove-BoiTree -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive')            -Label 'OneDrive app data'
    Remove-BoiTree -Path "$env:ProgramData\Microsoft OneDrive"                          -Label 'OneDrive ProgramData'
    Remove-BoiTree -Path "$env:SystemDrive\OneDriveTemp"                                -Label 'OneDriveTemp'

    Invoke-BoiAction -Description 'remove OneDrive scheduled tasks' -Action {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskPath -like '*OneDrive*' -or $_.TaskName -like '*OneDrive*' } |
            ForEach-Object {
                Write-Boi "deleting scheduled task: $($_.TaskPath)$($_.TaskName)" 'INFO'
                Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            }
    }

    Invoke-BoiAction -Description 'remove OneDrive shell icon overlay + run key' -Action {
        $pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers'
        Get-ChildItem $pol -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -like '*OneDrive*' } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -Force -ErrorAction SilentlyContinue
    }

    # stop windows re-provisioning it via its scheduled autopilot task
    Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1

    Write-Boi 'OneDrive removal complete (reboot to clear the ghost recycle-bin entry)' 'OK'
    Add-BoiResult 'onedrive removal' 'OK'
}
