# Sets the desktop wallpaper from a local file or URL.
# config.wallpaper: { enabled, source (path or http url), style (fill|fit|stretch|center|tile|span) }

function Invoke-BoiWallpaper {
    param([Parameter(Mandatory)]$Cfg)

    $w = $Cfg.wallpaper
    if (-not $w -or -not $w.enabled) { Add-BoiResult 'wallpaper' 'SKIP'; return }

    $source = [string]$w.source
    if (-not $source) {
        Write-Boi 'wallpaper.source not set' 'WARN'
        Add-BoiResult 'wallpaper' 'WARN' 'no source'
        return
    }

    $style = if ($w.style) { $w.style } else { 'fill' }
    $local = $null

    if ($source -match '^https?://') {
        $cacheDir = Join-Path $env:LOCALAPPDATA 'SetupBoi'
        if (-not (Get-BoiDryRun)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        $ext = [System.IO.Path]::GetExtension([uri]$source.AbsolutePath)
        if (-not $ext) { $ext = '.jpg' }
        $local = Join-Path $cacheDir ('wallpaper' + $ext)
        $local = Save-BoiUrl -Url $source -OutFile $local
        if (-not $local) { Add-BoiResult 'wallpaper' 'FAIL' 'download failed'; return }
    } else {
        $local = Expand-BoiPath ([System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($source)))
        if (-not (Get-BoiDryRun) -and -not (Test-Path $local)) {
            Write-Boi "wallpaper file missing: $local" 'ERR'
            Add-BoiResult 'wallpaper' 'FAIL' "missing $local"
            return
        }
    }

    Write-Boi "applying wallpaper: $local (style=$style)" 'STEP'
    Set-BoiWallpaper -ImagePath $local -Style $style
    Add-BoiResult 'wallpaper' 'OK' $local
}
