# SetupBoi shared module - helper functions used by all feature scripts.
# Targets Windows PowerShell 5.1+ (no pwsh required). ASCII only.

$script:DRYRUN = $false
$script:Results = @()
$script:BoiRepoRoot = Split-Path $PSScriptRoot -Parent

# ---------------------------------------------------------------- journal
# Every mutation appends an entry to %LOCALAPPDATA%\SetupBoi\journal.json so
# undo.ps1 can roll the last run back. Entries are replayed newest-first.
$script:JournalPath   = Join-Path $env:LOCALAPPDATA 'SetupBoi\journal.json'
$script:JournalRun    = $null   # timestamp id of the current run
$script:Journal       = @()     # in-memory copy while running

function Start-BoiJournal {
    param([string]$ConfigPath = '')
    $script:JournalRun = (Get-Date).ToString('yyyyMMdd-HHmmss')
    if (Test-Path $script:JournalPath) {
        try { $script:Journal = @(Get-Content $script:JournalPath -Raw | ConvertFrom-Json) }
        catch { $script:Journal = @(); Write-Boi 'journal unreadable, starting fresh' 'WARN' }
    }
    Add-BoiJournalEntry -Kind 'run' -Action 'begin' -Detail "run $script:JournalRun" `
        -Extra @{ config = $ConfigPath } | Out-Null
}

function Stop-BoiJournal {
    Add-BoiJournalEntry -Kind 'run' -Action 'end' | Out-Null
    Save-BoiJournal
}

function Save-BoiJournal {
    if ($script:DRYRUN) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path $script:JournalPath) | Out-Null
    $json = if (@($script:Journal).Count -eq 0) { '[]' } else { ConvertTo-Json @($script:Journal) -Depth 6 -Compress }
    [System.IO.File]::WriteAllText($script:JournalPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Add-BoiJournalEntry {
    <# Appends one undo-record. Kind: reg|file|tree|lnk|run. Returns the entry. #>
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Action,   # set|remove|delete|backup
        [string]$Path = '',
        [string]$Name = '',
        $OldValue = $null,
        [bool]$OldExists = $false,
        [string]$Type = '',
        [string]$Detail = '',
        [hashtable]$Extra = @{}
    )
    if ($script:DRYRUN) { return $null }
    if ($script:JournalQuiet) { return $null }
    $e = [ordered]@{
        at = (Get-Date).ToString('o'); run = $script:JournalRun
        kind = $Kind; action = $Action; path = $Path; name = $Name
        oldValue = $OldValue; oldExists = $OldExists; type = $Type; detail = $Detail
    }
    foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }
    $script:Journal += [pscustomobject]$e
    # append-only on disk right away: survives a crash mid-run
    Save-BoiJournal
    return [pscustomobject]$e
}

function Get-BoiJournal {
    if (Test-Path $script:JournalPath) {
        try { return @(Get-Content $script:JournalPath -Raw | ConvertFrom-Json) } catch { return @() }
    }
    return @()
}

function Get-BoiBackupDir {
    $d = Join-Path (Split-Path $script:JournalPath) ('backup\' + $script:JournalRun)
    if (-not $script:DRYRUN) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    return $d
}

function Get-BoiLastRunId {
    $seen = New-Object System.Collections.Generic.List[string]
    foreach ($e in (Get-BoiJournal)) {
        $r = [string]$e.run
        if ($r -and -not $seen.Contains($r)) { $seen.Add($r) }
    }
    if ($seen.Count -eq 0) { return $null }
    return $seen[$seen.Count - 1]
}

$script:BackupMaxMB = 300   # don't journal-backup trees bigger than this

function BackUp-BoiTree {
    <# Copies a tree into the per-run backup dir. Returns backup path or $null. #>
    param([Parameter(Mandatory)][string]$Path, [string]$Label = '')
    if ($script:DRYRUN) { return $null }
    try {
        $bytes = (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
        if ($bytes -gt ($script:BackupMaxMB * 1MB)) {
            Write-Boi "$Label too big ($([int]($bytes/1MB)) MB) to back up - deleting without backup" 'WARN'
            return $null
        }
    } catch { return $null }
    $safe = ($Path -replace '[\\/:*?\"<>|]', '_').Trim('_')
    $dst  = Join-Path (Get-BoiBackupDir) $safe
    & robocopy $Path $dst /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Write-Boi "backup failed for $Path (robocopy $LASTEXITCODE) - deleting without backup" 'WARN'
        return $null
    }
    return $dst
}

function BackUp-BoiFile {
    param([Parameter(Mandatory)][string]$FilePath)
    if ($script:DRYRUN) { return $null }
    try {
        if ((Get-Item -LiteralPath $FilePath).Length -gt ($script:BackupMaxMB * 1MB)) { return $null }
        $safe = ($FilePath -replace '[\\/:*?\"<>|]', '_')
        $dst  = Join-Path (Get-BoiBackupDir) $safe
        Copy-Item -LiteralPath $FilePath -Destination $dst -Force
        return $dst
    } catch { return $null }
}

function Set-BoiDryRun {
    param([bool]$Value)
    $script:DRYRUN = $Value
}

function Get-BoiDryRun { return [bool]$script:DRYRUN }

function Write-Boi {
    param(
        [string]$Message,
        [ValidateSet('INFO','STEP','OK','WARN','ERR','PLAN')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        'INFO'  { 'DarkGray' }
        'STEP'  { 'Cyan' }
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERR'   { 'Red' }
        'PLAN'  { 'Magenta' }
    }
    $prefix = switch ($Level) {
        'INFO'  { '   ' }
        'STEP'  { '=> ' }
        'OK'    { ' + ' }
        'WARN'  { ' ! ' }
        'ERR'   { ' X ' }
        'PLAN'  { '[dry] ' }
    }
    Write-Host ("[{0}] {1}{2}" -f $ts, $prefix, $Message) -ForegroundColor $color
}

function Add-BoiResult {
    param(
        [string]$Name,
        [ValidateSet('OK','WARN','FAIL','SKIP')][string]$Status,
        [string]$Detail = ''
    )
    $script:Results += [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }
}

function Get-BoiResults { return $script:Results }

# ---------------------------------------------------------------- registry

function Set-RegValue {
    <#
      Creates the parent key if needed and sets a value. Dry-run aware.
      Type examples: DWord, String, QWord, Binary, ExpandString
    #>
    param(
        [Parameter(Mandatory)][string]$Path,     # e.g. HKCU:\Software\Microsoft\Windows\CurrentVersion
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord'
    )
    if ($script:DRYRUN) {
        Write-Boi "Set-RegValue $Path\$Name = $Value ($Type)" 'PLAN'
        return
    }
    try {
        # journal: remember what was there before
        $old = $null; $exists = $false
        if (Test-Path $Path) {
            $pi = Get-Item $Path
            if ($pi.Property -and $pi.Property -contains $Name) {
                $old = (Get-ItemProperty -Path $Path -Name $Name).PSObject.Properties[$Name].Value
                $exists = $true
            }
        }
        Add-BoiJournalEntry -Kind 'reg' -Action 'set' -Path $Path -Name $Name `
            -OldValue $old -OldExists $exists -Type $Type | Out-Null

        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        Write-Boi "$Path\$Name = $Value" 'OK'
    } catch {
        Write-Boi "FAILED $Path\$Name : $($_.Exception.Message)" 'ERR'
    }
}

function Remove-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if ($script:DRYRUN) {
        Write-Boi "Remove-RegValue $Path\$Name" 'PLAN'
        return
    }
    try {
        if (Test-Path $Path) {
            $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($null -ne $p) {
                $old = $p.PSObject.Properties[$Name].Value
                Add-BoiJournalEntry -Kind 'reg' -Action 'remove' -Path $Path -Name $Name `
                    -OldValue $old -OldExists $true -Type 'String' | Out-Null
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
                Write-Boi "removed $Path\$Name" 'OK'
            }
        }
    } catch {
        Write-Boi "FAILED removing $Path\$Name : $($_.Exception.Message)" 'ERR'
    }
}

# ---------------------------------------------------------------- actions

function Invoke-BoiAction {
    <# Wraps any native command / filesystem mutation so it respects dry-run. #>
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($script:DRYRUN) {
        Write-Boi $Description 'PLAN'
        return $null
    }
    Write-Boi $Description 'INFO'
    & $Action
}

function Remove-BoiTree {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Label = ''
    )
    $what = if ($Label) { $Label } else { $Path }
    $body = {
        if (Test-Path -LiteralPath $Path) {
            $bak = BackUp-BoiTree -Path $Path -Label $what
            try {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
                Add-BoiJournalEntry -Kind 'tree' -Action 'delete' -Path $Path `
                    -Detail $what -Extra @{ backup = $bak } | Out-Null
                Write-Boi "removed: $Path" 'OK'
            } catch {
                Write-Boi "could not remove $Path : $($_.Exception.Message)" 'WARN'
            }
        } else {
            Write-Boi "not present: $Path" 'INFO'
        }
    }
    Invoke-BoiAction -Description "remove $what" -Action $body
}

function Remove-BoiFile {
    <# Deletes one file with backup + journal entry. #>
    param([Parameter(Mandatory)][string]$FilePath, [string]$Label = '')
    if ($script:DRYRUN) { return }
    if (-not (Test-Path -LiteralPath $FilePath)) { return }
    $bak = BackUp-BoiFile -FilePath $FilePath
    try {
        Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop
        Add-BoiJournalEntry -Kind 'file' -Action 'delete' -Path $FilePath `
            -Detail $Label -Extra @{ backup = $bak } | Out-Null
    } catch {
        Write-Boi "could not remove $FilePath : $($_.Exception.Message)" 'WARN'
    }
}

# ---------------------------------------------------------------- misc

function Test-BoiAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-BoiAdmin {
    <# Re-launches the given script as admin, preserving args. #>
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )
    Write-Boi 'Not running as admin - requesting elevation...' 'WARN'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" " + ($Arguments -join ' ')
    $psi.Verb = 'runas'
    $psi.UseShellExecute = $true
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

function Get-BoiOSInfo {
    $ci = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name  = (Get-ItemProperty $ci -ErrorAction SilentlyContinue).ProductName
    $build = [int](Get-ItemProperty $ci -ErrorAction SilentlyContinue).CurrentBuildNumber
    if (-not $build) { $build = [System.Environment]::OSVersion.Version.Build }
    [pscustomobject]@{
        ProductName = $name
        Build       = $build
        IsWin11     = ($build -ge 22000)
    }
}

function Expand-BoiPath {
    <# Resolves a path that may be relative to the repo root. #>
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $script:BoiRepoRoot $Path))
}

function Save-BoiUrl {
    <# Downloads a URL to a local file (returns path, or $null on failure). #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )
    if ($script:DRYRUN) {
        Write-Boi "download $Url -> $OutFile" 'PLAN'
        return $OutFile
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 # TLS1.2
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return $OutFile
    } catch {
        Write-Boi "download failed for $Url : $($_.Exception.Message)" 'ERR'
        return $null
    }
}

function Get-BoiMd5Hex {
    param([Parameter(Mandatory)][string]$String)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String)) | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Restart-BoiShell {
    # Restart explorer.exe so shell-level tweaks become visible.
    Invoke-BoiAction -Description 'restart explorer.exe (shell refresh)' -Action {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------------- wallpaper

function Set-BoiWallpaper {
    param(
        [Parameter(Mandatory)][string]$ImagePath,   # local jpg/png
        [string]$Style = 'fill'
    )
    # WallpaperStyle / TileWallpaper pairs per display mode
    $styleMap = @{
        'fill'    = @('10','0')
        'fit'     = @('6','0')
        'stretch' = @('2','0')
        'center'  = @('0','0')
        'tile'    = @('0','1')
        'span'    = @('22','0')
    }
    $pair = $styleMap[$Style.ToLower()]
    if (-not $pair) { $pair = @('10','0') }

    Set-RegValue 'HKCU:\Control Panel\Desktop' 'Wallpaper' $ImagePath -Type String
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' $pair[0] -Type String
    Set-RegValue 'HKCU:\Control Panel\Desktop' 'TileWallpaper' $pair[1] -Type String

    if ($script:DRYRUN) {
        Write-Boi "apply wallpaper $ImagePath (style=$Style) + Win11 SystemProtectedPath trick" 'PLAN'
        return
    }

    # Windows 11 caches wallpapers under a protected slideshow path; writing there
    # keeps the wallpaper from reverting when the theme/lock image changes.
    if ((Get-BoiOSInfo).IsWin11) {
        try {
            $src = Get-Item -LiteralPath $ImagePath
            $dirName = 'SystemProtectedPath-' + (Get-BoiMd5Hex $src.FullName.ToLower())
            $destDir = Join-Path $env:LOCALAPPDATA ('Microsoft\Windows\ThemeFiles\' + $dirName)
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            $dest = Join-Path $destDir 'wallpaper.jpg'
            # Re-encode as JPEG so it satisfies the protected-path JPEG check.
            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
            $img = [System.Drawing.Image]::FromFile($src.FullName)
            $img.Save($dest, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $img.Dispose()
            Set-RegValue 'HKCU:\Control Panel\Desktop\Slideshow' 'Location0' $dest -Type String
            Set-RegValue 'HKCU:\Control Panel\Desktop\Slideshow' 'Location0Attributes' '4294967295:127' -Type String
            Set-RegValue 'HKCU:\Control Panel\Desktop\Slideshow' 'Location0Interval' '0' -Type String
            Set-RegValue 'HKCU:\Control Panel\Desktop\Slideshow' 'CurrentUnit' '0' -Type String
            Add-BoiJournalEntry -Kind 'tree' -Action 'create' -Path $destDir `
                -Detail 'win11 protected-path wallpaper dir' | Out-Null
            $ImagePath = $dest
            Set-RegValue 'HKCU:\Control Panel\Desktop' 'Wallpaper' $ImagePath -Type String
        } catch {
            Write-Boi "Win11 protected-path wallpaper skipped ($($_.Exception.Message)); using direct apply" 'WARN'
        }
    }

    $sig = @'
[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
    if ('SetupBoi.SetupBoiUser32' -as [type]) {
        $type = [SetupBoi.SetupBoiUser32]
    } else {
        $type = Add-Type -MemberDefinition $sig -Name 'SetupBoiUser32' -Namespace 'SetupBoi' -PassThru
    }
    # SPI_SETDESKWALLPAPER = 20, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    [void]$type::SystemParametersInfo(20, 0, $ImagePath, 3)
}

# ---------------------------------------------------------------- start pins

function Resolve-BoiStartApp {
    <#
      Turns a friendly name or AUMID into a desktopAppId usable in the
      ConfigureStartPins policy JSON. Returns $null if not found.
    #>
    param([Parameter(Mandatory)][string]$Name)

    # Already an AUMID/appid? (contains '!' or looks like a package family)
    if ($Name -match '!' -or $Name -match '^[A-Za-z0-9._]+\.[A-Za-z0-9]+$' -and $Name -notmatch ' ') {
        # explicit ids pass through: MSEdge, Microsoft.Windows.Explorer, AppX...!App, Chrome
    }

    $aliases = @{
        'settings'        = 'windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel'
        'file explorer'   = 'Microsoft.Windows.Explorer'
        'explorer'        = 'Microsoft.Windows.Explorer'
        'control panel'   = 'Microsoft.Windows.ControlPanel'
        'admin tools'     = 'Microsoft.Windows.AdministrativeTools'
        'task manager'    = 'Microsoft.Windows.TaskManager'
        'regedit'         = 'Microsoft.Windows.Regedit'
        'run'             = 'Microsoft.Windows.Run'
        'windows security' = 'Microsoft.Windows.SecHealthUI_cw5n1h2txyewy!SecHealthUI'
    }
    $key = $Name.ToLower().Trim()
    if ($aliases.ContainsKey($key)) { return $aliases[$key] }

    # explicit known win32 AUMIDs commonly used
    $known = @{
        'msedge'    = 'MSEdge'
        'edge'      = 'MSEdge'
        'notepad'   = 'Microsoft.Windows.Notepad'
        'calc'      = 'Microsoft.Windows.Calculator'
    }
    if ($known.ContainsKey($key)) { return $known[$key] }

    # resolve via the Start menu app list (works once the app is installed)
    try {
        $apps = Get-StartApps -ErrorAction Stop
        $hit = $apps | Where-Object { $_.Name -and $_.Name -match ('(?i)^' + [regex]::Escape($Name) + '$') } | Select-Object -First 1
        if (-not $hit) {
            $hit = $apps | Where-Object { $_.Name -and $_.Name -match ('(?i)' + [regex]::Escape($Name)) } | Select-Object -First 1
        }
        if ($hit) { return $hit.AppID }
    } catch {
        Write-Boi "Get-StartApps unavailable: $($_.Exception.Message)" 'WARN'
    }

    # last resort: pass through as-is (might be a raw AUMID the user knows)
    if ($Name -match '[.!]') { return $Name }
    Write-Boi "cannot resolve start pin '$Name' - skipping" 'WARN'
    return $null
}

function Set-BoiStartPins {
    <#
      Writes the ConfigureStartPins policy via PolicyManager. This is the only
      scriptable pin mechanism that works unattended on Windows 11 (24H2 makes
      it official; earlier builds honor the same keys). Applies on next sign-in.
    #>
    param([Parameter(Mandatory)][string[]]$AppIds)

    $pins = @($AppIds | ForEach-Object { @{ desktopAppId = $_ } })
    $json = (@{ pinnedList = $pins } | ConvertTo-Json -Compress -Depth 5)

    $provider = 'B5292708-1619-419B-9923-E5D9F3925E71'
    $cur = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
    $prov = "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\$provider\default\Device\Start"

    Set-RegValue $cur  'ConfigureStartPins' $json -Type String
    Set-RegValue $cur  'ConfigureStartPins_ProviderSet' 1
    Set-RegValue $cur  'ConfigureStartPins_WinningProvider' $provider -Type String
    Set-RegValue $prov 'ConfigureStartPins' $json -Type String
    Set-RegValue $prov 'ConfigureStartPins_LastWrite' 1
}

# ---------------------------------------------------------------- winget

function Test-BoiWinget {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    return [bool]$cmd
}

function Invoke-BoiWinget {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$Retries = 2
    )
    if ($script:DRYRUN) {
        Write-Boi ("winget " + ($Arguments -join ' ')) 'PLAN'
        return $true
    }
    for ($i = 1; $i -le ($Retries + 1); $i++) {
        # -ne '--no-progress' avoids ANSI bar spam in logs
        $out = & winget @Arguments --accept-source-agreements --no-progress 2>&1
        $code = $LASTEXITCODE
        if ($code -eq 0) { return $true }
        Write-Boi "winget exit $code (attempt $i): " ($out | Select-Object -Last 2 | Out-String).Trim() 'WARN'
        Start-Sleep -Seconds 3
    }
    return $false
}

# ---------------------------------------------------------------- shortcuts

function Resolve-BoiLnk {
    <#
      Finds a .lnk path for a friendly app name (or substring), searching the
      per-user and all-users Start Menu. Returns the full .lnk path or $null.
      Used for taskbar pins (policy requires a DesktopApplicationLinkPath).
    #>
    param([Parameter(Mandatory)][string]$Name)
    $roots = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu')
    ) | Where-Object { Test-Path $_ }
    $exact = Get-ChildItem -Path $roots -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match ('(?i)^' + [regex]::Escape($Name) + '$') } |
        Select-Object -First 1
    if ($exact) { return $exact.FullName }
    $fuzzy = Get-ChildItem -Path $roots -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match ('(?i)' + [regex]::Escape($Name)) } |
        Select-Object -First 1
    if ($fuzzy) { return $fuzzy.FullName }
    return $null
}

function ConvertTo-BoiBgrInt {
    <# '#4CC2FF' -> 0xFF4CC2FF BGR-with-alpha int used by DWM accent values. #>
    param([Parameter(Mandatory)][string]$Hex)
    $hex = $Hex.Trim().TrimStart('#')
    if ($hex -notmatch '^[0-9a-fA-F]{6}$') { throw "Bad hex color: $Hex" }
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    # stay in int64: PS5.1 parses 0xFF000000 as a NEGATIVE Int32 literal
    $u = [int64]4278190080 -bor ([int64]$b -shl 16) -bor ([int64]$g -shl 8) -bor [int64]$r
    if ($u -gt [int64][int]::MaxValue) { $u -= [int64]4294967296 }
    return [int]$u  # signed int for DWORD
}

function ConvertTo-BoiRgbTriplet {
    <# '#RRGGBB' -> 'r g b' string used by Control Panel Colors values. #>
    param([Parameter(Mandatory)][string]$Hex)
    $hex = $Hex.Trim().TrimStart('#')
    if ($hex -notmatch '^[0-9a-fA-F]{6}$') { throw "Bad hex color: $Hex" }
    $r = [Convert]::ToInt32($hex.Substring(0,2),16)
    $g = [Convert]::ToInt32($hex.Substring(2,2),16)
    $b = [Convert]::ToInt32($hex.Substring(4,2),16)
    return "$r $g $b"
}

Export-ModuleMember -Function * -Variable BoiRepoRoot
