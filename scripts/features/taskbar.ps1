# Taskbar: center/left alignment, autohide, and pinned apps.
# config.taskbar: { enabled, align: center|left, autohide: bool,
#                   pins: ["Firefox", "Everything", ...]  (friendly names or .lnk paths) }
#
# Pins are applied via the Taskbar/EnableFixStartLayout policy with a generated
# LayoutModificationTemplate XML - the supported unattended mechanism on Win11.

function Invoke-BoiTaskbar {
    param([Parameter(Mandatory)]$Cfg)

    $t = $Cfg.taskbar
    if (-not $t -or -not $t.enabled) { Add-BoiResult 'taskbar' 'SKIP'; return }

    # alignment / autohide (HKCU, no reboot needed - explorer restart picks it up)
    if ($t.align) {
        $v = if ($t.align.ToLower() -eq 'left') { 0 } else { 1 }
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' $v
        Write-Boi "taskbar alignment: $($t.align)" 'OK'
    }
    if ($null -ne $t.autohide) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarSc' ([int][bool]$t.autohide)
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAutohideSuspend' ([int][bool](-not $t.autohide))
        Write-Boi "taskbar autohide: $($t.autohide)" 'OK'
    }

    # hide system tray extras if requested
    if ($t.hideTaskview)     { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0 }
    if ($t.hideWidgets)      { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarSd' 0 }
    if ($t.hideChat)         { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0 }
    if ($t.combineTaskbar)   { Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarGlomLevel' ([int]$t.combineTaskbar) }

    if (-not $t.pins -or @($t.pins).Count -eq 0) {
        Add-BoiResult 'taskbar' 'OK' 'no pins configured'
        Restart-BoiShell
        return
    }

    Write-Boi "taskbar pins: $(($t.pins) -join ', ')" 'STEP'

    $pinXml = New-Object System.Collections.Generic.List[string]
    $resolved = 0
    foreach ($pin in $t.pins) {
        $node = $null
        if ($pin -match '\.lnk$') {
            $candidate = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($pin))
            if ((Get-BoiDryRun) -or (Test-Path $candidate)) {
                $node = "      <taskbar:DesktopApp DesktopApplicationLinkPath=""$([System.Security.SecurityElement]::Escape($candidate))"" />"
            }
        } else {
            # 1) win32 .lnk in the Start Menu
            $lnk = Resolve-BoiLnk $pin
            if ($lnk) {
                $node = "      <taskbar:DesktopApp DesktopApplicationLinkPath=""$([System.Security.SecurityElement]::Escape($lnk))"" />"
            } else {
                # 2) UWP/store app -> AUMID pin (taskbar:UApp)
                $id = Resolve-BoiStartApp $pin
                if ($id -and $id -match '!') {
                    $node = "      <taskbar:UApp DesktopApplicationID=""$([System.Security.SecurityElement]::Escape($id))"" />"
                }
            }
        }
        if (-not $node) {
            Write-Boi "taskbar pin '$pin' not resolvable (no .lnk or AUMID) - skipped" 'WARN'
            continue
        }
        $pinXml.Add($node)
        $resolved++
    }

    if ($resolved -eq 0) {
        Write-Boi 'no taskbar pins resolved - leaving policy untouched' 'WARN'
        Add-BoiResult 'taskbar pins' 'WARN' 'none resolved'
        Restart-BoiShell
        return
    }

    $xml = @"
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2016/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2016/Taskbar" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
$($pinXml -join "`n")
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@

    # The policy engine requires the file on disk; store it in %LOCALAPPDATA%.
    $xmlPath = Join-Path $env:LOCALAPPDATA 'SetupBoi\TaskbarLayout.xml'
    Invoke-BoiAction -Description "write taskbar layout xml -> $xmlPath ($resolved pins)" -Action {
        New-Item -ItemType Directory -Force -Path (Split-Path $xmlPath) | Out-Null
        [System.IO.File]::WriteAllText($xmlPath, $xml, (New-Object System.Text.UTF8Encoding($false)))
        Write-Boi "wrote $xmlPath" 'OK'
    }

    $pol = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
    Set-RegValue $pol 'StartLayout' $xmlPath -Type String

    Add-BoiResult 'taskbar pins' 'OK' ("$resolved pinned (apply on next sign-in)")
    Restart-BoiShell
}
