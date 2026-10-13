# Desktop icons: This PC / Network / Recycle Bin / Control Panel / User files,
# plus a "clean" mode that nukes every icon (including shortcuts in Desktop folder).
# config.desktopIcons: { enabled, showThisPC, showNetwork, showRecycleBin, showControlPanel,
#                        showUserFiles, hideTabletMode, clean (bool), desktopIni (bool) }

function Invoke-BoiDesktopIcons {
    param([Parameter(Mandatory)]$Cfg)

    $d = $Cfg.desktopIcons
    if (-not $d -or -not $d.enabled) { Add-BoiResult 'desktop icons' 'SKIP'; return }

    # Hide icons wholesale if 'clean'
    if ($d.clean) {
        Write-Boi 'clean desktop: hiding all desktop icons' 'STEP'
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDesktop' 1
        Add-BoiResult 'desktop icons' 'OK' 'clean'
        Restart-BoiShell
        return
    }

    # Desktop CLSID show/hide (HKCU Desktop NameSpace)
    $clsids = @{
        'ThisPC'        = '{20D04FE0-3AEA-1069-A2D8-08002B30309D}'
        'Network'       = '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}'
        'RecycleBin'    = '{645FF040-5081-101B-9F08-00AA002F954E}'
        'ControlPanel'  = '{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}'
        'UserFiles'     = '{59031A47-3FCC-4C7B-81E6-10329585EBDE}'
    }

    $flags = @{
        'ThisPC'       = $d.showThisPC
        'Network'      = $d.showNetwork
        'RecycleBin'   = $d.showRecycleBin
        'ControlPanel' = $d.showControlPanel
        'UserFiles'    = $d.showUserFiles
    }

    foreach ($k in $clsids.Keys) {
        if ($null -eq $flags[$k]) { continue }   # not specified in config -> leave alone
        $cls = $clsids[$k]
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
        # 1 = hidden, 0 = shown
        $val = if ([bool]$flags[$k]) { 0 } else { 1 }
        Set-RegValue $path $cls $val
        Write-Boi "$k : $(if ($flags[$k]) {'shown'} else {'hidden'})" 'OK'
    }

    if ($d.hideTabletMode) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\HideDesktopIcons\NewStartPanel' '{3ADD1653-1C32-4cb0-B295-D650C2B023D1}' 1
    }

    # Remove .lnk shortcuts from the user's Desktop folder
    if ($d.cleanShortcuts) {
        Write-Boi 'removing desktop shortcuts (.lnk)' 'STEP'
        Invoke-BoiAction -Description 'delete *.lnk on Desktop' -Action {
            Get-ChildItem ([Environment]::GetFolderPath('Desktop')) -Filter '*.lnk' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Boi 'removed .lnk files from Desktop' 'OK'
        }
    }

    Add-BoiResult 'desktop icons' 'OK'
    Restart-BoiShell
}
