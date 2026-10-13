# Escape hatch: arbitrary steps from the config.
# config.custom: {
#   registry: [ {path:"HKCU:\\...", name:"X", value:1, type:"DWord"} ],
#   commands: [ "cleanmgr /verylowdisk", {cmd:"reg add ...", cwd:"C:\\x"} ],
#   files:    [ {url:"https://...", dest:"%LOCALAPPDATA%\\x.bin", run:true, args:"/S"} ],
#   after:    [ "cmdkey /list" ]   # shell lines printed for the human at the end
# }

function Invoke-BoiCustom {
    param([Parameter(Mandatory)]$Cfg)

    $x = $Cfg.custom
    if (-not $x) { Add-BoiResult 'custom' 'SKIP'; return }

    if ($x.registry) {
        Write-Boi "custom registry: $(@($x.registry).Count) values" 'STEP'
        foreach ($r in $x.registry) {
            $t = if ($r.type) { $r.type } else { 'DWord' }
            Set-RegValue $r.path $r.name $r.value -Type $t
        }
        Add-BoiResult 'custom registry' 'OK'
    }

    if ($x.commands) {
        Write-Boi "custom commands: $(@($x.commands).Count)" 'STEP'
        foreach ($c in $x.commands) {
            $line = if ($c -is [string]) { $c } else { $c.cmd }
            $cwd  = if ($c -is [string]) { $null } else { $c.cwd }
            Invoke-BoiAction -Description "run: $line" -Action {
                if ($cwd) { Push-Location $cwd }
                try { cmd /c $line } finally { if ($cwd) { Pop-Location } }
            }
        }
        Add-BoiResult 'custom commands' 'OK'
    }

    if ($x.files) {
        Write-Boi "custom files: $(@($x.files).Count)" 'STEP'
        foreach ($f in $x.files) {
            $dest = [Environment]::ExpandEnvironmentVariables($f.dest)
            if (-not [System.IO.Path]::IsPathRooted($dest)) {
                $dest = Join-Path $env:LOCALAPPDATA $dest
            }
            # journal: record prior state before we overwrite/create
            if (-not (Get-BoiDryRun)) {
                if (Test-Path -LiteralPath $dest) {
                    $bak = BackUp-BoiFile -FilePath $dest
                    Add-BoiJournalEntry -Kind 'file' -Action 'backup' -Path $dest `
                        -Detail 'overwritten by custom.files' -Extra @{ backup = $bak } | Out-Null
                } else {
                    Add-BoiJournalEntry -Kind 'file' -Action 'create' -Path $dest `
                        -Detail 'written by custom.files' | Out-Null
                }
            }
            if ($f.url) {
                $got = Save-BoiUrl -Url $f.url -OutFile $dest
                if (-not $got) { Add-BoiResult "custom file $($f.url)" 'FAIL'; continue }
            } elseif ($f.content) {
                Invoke-BoiAction -Description "write file $dest" -Action {
                    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                    Set-Content -LiteralPath $dest -Value $f.content -Encoding UTF8
                }
            }
            if ($f.run) {
                $fa = if ($f.args) { $f.args } else { @() }
                Invoke-BoiAction -Description "execute $dest $($f.args)" -Action {
                    Start-Process -FilePath $dest -ArgumentList $fa -Wait -ErrorAction Stop
                }
            }
        }
        Add-BoiResult 'custom files' 'OK'
    }
}
