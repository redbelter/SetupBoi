# Start menu pins via the ConfigureStartPins policy (works unattended on Win11;
# official from 24H2, honored on 22H2/23H2 too). Takes effect on next sign-in.
# config.start: { enabled, pins: ["Firefox","Settings","File Explorer", ...] }

function Invoke-BoiStart {
    param([Parameter(Mandatory)]$Cfg)

    $s = $Cfg.start
    if (-not $s -or -not $s.enabled) { Add-BoiResult 'start pins' 'SKIP'; return }
    if (-not $s.pins -or @($s.pins).Count -eq 0) { Add-BoiResult 'start pins' 'SKIP' 'no pins'; return }

    Write-Boi "start pins: $(($s.pins) -join ', ')" 'STEP'

    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($pin in $s.pins) {
        $id = Resolve-BoiStartApp $pin
        if ($id) {
            Write-Boi "resolved '$pin' -> $id" 'INFO'
            $ids.Add($id)
        } else {
            Write-Boi "start pin '$pin' unresolved - skipped" 'WARN'
        }
    }

    if ($ids.Count -eq 0) {
        Write-Boi 'no start pins resolved - not touching the pin policy' 'WARN'
        Add-BoiResult 'start pins' 'WARN' 'none resolved'
        return
    }

    Set-BoiStartPins -AppIds $ids.ToArray()
    Write-Boi 'ConfigureStartPins written - pins appear on next sign-in' 'OK'
    Add-BoiResult 'start pins' 'OK' ("$($ids.Count) pins, apply next sign-in")
}
