# Color scheme: dark/light mode + custom accent color.
# config.colors: { enabled, mode: dark|light, systemMode: dark|light|null,
#                  accent: "#4CC2FF" (optional), colorPrevalence: true|false }

function Invoke-BoiColors {
    param([Parameter(Mandatory)]$Cfg)

    $c = $Cfg.colors
    if (-not $c -or -not $c.enabled) { Add-BoiResult 'colors' 'SKIP'; return }

    $pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    if ($c.mode) {
        # apps mode: 0 = dark, 1 = light (Settings > Personalization > Colors > App mode)
        $v = if ($c.mode.ToLower() -eq 'dark') { 0 } else { 1 }
        Set-RegValue $pers 'AppsUseLightTheme' $v
        Write-Boi "app mode: $($c.mode)" 'OK'
    }
    if ($c.systemMode) {
        # windows mode: controls taskbar/start color (0 = dark)
        $v = if ($c.systemMode.ToLower() -eq 'dark') { 0 } else { 1 }
        Set-RegValue $pers 'SystemUsesLightTheme' $v
        Write-Boi "system mode: $($c.systemMode)" 'OK'
    }

    if ($c.accent) {
        try {
            $bgr = ConvertTo-BoiBgrInt $c.accent
            # stop Windows picking its own accent from the wallpaper
            Set-RegValue $pers 'EnableAutoColorization' 0
            Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 1
            Set-RegValue 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor' $bgr
            # apply accent to start/taskbar/title bars (Settings toggle)
            $prev = if ($null -ne $c.colorPrevalence) { [int][bool]$c.colorPrevalence } else { 1 }
            Set-RegValue $pers 'ColorPrevalence' $prev
            Write-Boi "accent color: $($c.accent)" 'OK'
        } catch {
            Write-Boi "bad accent hex '$($c.accent)' : $($_.Exception.Message)" 'ERR'
            Add-BoiResult 'colors' 'WARN' 'bad accent hex'
            return
        }
    }

    Add-BoiResult 'colors' 'OK'
    Restart-BoiShell
}
