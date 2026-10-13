# Installs apps with winget (auto-bootstraps winget if missing).
# config.install: { enabled, winget: [ "Mozilla.Firefox", ... ],
#                   scoop: [ "git", ... ],  local: [ {path,args} ] }

function Install-BoiWingetPackage {
    param([Parameter(Mandatory)][string]$Id)

    # already installed?
    $list = & winget list --id $Id --exact 2>&1
    if ($LASTEXITCODE -eq 0 -and ($list | Out-String) -match [regex]::Escape($Id)) {
        Write-Boi "$Id already installed" 'INFO'
        return $true
    }
    Invoke-BoiWinget @('install', '--id', $Id, '--exact', '-s', 'winget', '-e', '--silent')
}

function Assert-BoiWinget {
    if (Test-BoiWinget) { return $true }
    Write-Boi 'winget missing - bootstrapping App Installer from GitHub' 'WARN'
    if (Get-BoiDryRun) { return $false }

    $releases = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        $json = Invoke-RestMethod -Uri $releases -UseBasicParsing
        $url = ($json.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1).browser_download_url
        $depUrl = ($json.assets | Where-Object { $_.name -like 'DesktopAppInstaller.DeploymentKit*' -or $_.name -like '*Dep*zip*' } | Select-Object -First 1).browser_download_url
        if (-not $url) { throw 'no msixbundle asset found' }
        $tmp = Join-Path $env:TEMP 'winget-bootstrap'
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        $msix = Join-Path $tmp 'AppInstaller.msixbundle'
        Write-Boi "downloading $url" 'INFO'
        Invoke-WebRequest -Uri $url -OutFile $msix -UseBasicParsing

        # VCLibs + UI.Xaml dependencies
        $vc = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        $vcPath = Join-Path $tmp 'VCLibs.appx'
        Invoke-WebRequest -Uri $vc -OutFile $vcPath -UseBasicParsing -ErrorAction SilentlyContinue
        $xaml = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'
        $xamlPath = Join-Path $tmp 'MicrosoftUIXaml.appx'
        Invoke-WebRequest -Uri $xaml -OutFile $xamlPath -UseBasicParsing -ErrorAction SilentlyContinue

        $deps = @()
        if (Test-Path $vcPath)   { $deps += $vcPath }
        if (Test-Path $xamlPath) { $deps += $xamlPath }
        Add-AppxPackage -DependencyPath $deps -ForceUpdateFromAnyVersion -ErrorAction SilentlyContinue
        Add-AppxPackage $msix -ForceUpdateFromAnyVersion -ErrorAction Stop
        Start-Process 'shell:AppsFolder\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe!App' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        return (Test-BoiWinget)
    } catch {
        Write-Boi "winget bootstrap failed: $($_.Exception.Message)" 'ERR'
        Write-Boi 'install "App Installer" from the Microsoft Store, then re-run setup.ps1' 'WARN'
        return $false
    }
}

function Invoke-BoiInstall {
    param([Parameter(Mandatory)]$Cfg)

    $i = $Cfg.install
    if (-not $i -or -not $i.enabled) { Add-BoiResult 'installs' 'SKIP'; return }

    $wingetIds = @(@($i.winget) + @($i.apps) | Where-Object { $_ })   # 'apps' is an alias for winget ids

    if ($wingetIds.Count -gt 0) {
        if (-not (Assert-BoiWinget)) {
            Add-BoiResult 'installs (winget)' 'FAIL' 'winget unavailable'
        } else {
            Write-Boi "installing $($wingetIds.Count) winget packages" 'STEP'
            $ok = 0; $fail = 0
            foreach ($id in $wingetIds) {
                if (Install-BoiWingetPackage $id) {
                    Write-Boi "$id installed" 'OK'
                    $ok++
                } else {
                    Write-Boi "FAILED: $id" 'ERR'
                    $fail++
                }
            }
            Add-BoiResult 'installs (winget)' $(if ($fail -eq 0) {'OK'} else {'WARN'}) "$ok ok, $fail failed"
        }
    }

    if ($i.scoop -and @($i.scoop).Count -gt 0) {
        $haveScoop = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
        if (-not $haveScoop) {
            Invoke-BoiAction -Description 'install scoop' -Action {
                iwr -useb get.scoop.sh | iex
            }
        }
        foreach ($app in $i.scoop) {
            Invoke-BoiAction -Description "scoop install $app" -Action { scoop install $app }
        }
        Add-BoiResult 'installs (scoop)' 'OK'
    }

    foreach ($loc in @($i.local)) {
        if (-not $loc) { continue }
        $p = Expand-BoiPath $loc.path
        $installerArgs = if ($loc.args) { $loc.args } else { @() }
        Invoke-BoiAction -Description "run local installer: $p $installerArgs" -Action {
            Start-Process -FilePath $p -ArgumentList $installerArgs -Wait -ErrorAction Stop
        }
    }
    if ($i.local -and @($i.local).Count -gt 0) { Add-BoiResult 'installs (local)' 'OK' }
}
