# Removes preinstalled bloatware (provisioned AppX packages + optional store
# leftovers) and disables auto-install of suggested apps / sponsored tiles.
# config.bloatware: { enabled, remove: ["MicrosoftEdge...", "MicrosoftTeams..."],
#                     removeOnUpgrade: bool, disableAutoInstall: bool }
#
# Names support wildcards: "Microsoft.Bing*" removes every Bing package.
# Wildcards that match "Windows" core packages are refused for safety.

function Invoke-BoiBloatware {
    param([Parameter(Mandatory)]$Cfg)

    $b = $Cfg.bloatware
    if (-not $b -or -not $b.enabled) { Add-BoiResult 'bloatware' 'SKIP'; return }

    if ($b.disableAutoInstall -ne $false) {
        # stop the store silently installing 'recommended' apps + sponsored start tiles
        $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Set-RegValue $cdm 'SilentInstalledAppsEnabled' 0
        Set-RegValue $cdm 'OemPreInstalledAppsEnabled' 0
        Set-RegValue $cdm 'PreInstalledAppsEnabled' 0
        Set-RegValue $cdm 'PreInstalledAppsEverEnabled' 0
        Set-RegValue $cdm 'ContentDeliveryAllowed' 0
        Set-RegValue $cdm 'SubscribedContent-338388Enabled' 0   # suggested apps in start
        Set-RegValue $cdm 'SubscribedContent-314559Enabled' 0   # tips & tricks
        Set-RegValue $cdm 'SubscribedContent-338389Enabled' 0   # surface hub ads
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
        Write-Boi 'disabled auto-app-install + sponsored content' 'OK'
    }

    if (-not $b.remove -or @($b.remove).Count -eq 0) {
        Add-BoiResult 'bloatware' 'OK' 'nothing to remove'
        return
    }

    # Packages whose removal bricks Windows - wildcards must never catch these.
    $protected = @(
        'Microsoft.Windows.Explorer','Microsoft.Windows.StartMenuExperienceHost',
        'Microsoft.Windows.Search','Microsoft.Windows.ShellExperienceHost',
        'Microsoft.Windows.ImmersiveControlPanel','Microsoft.Windows.SecureAssessmentBrowser',
        'Microsoft.Windows.CloudExperienceHost','Microsoft.AAD.BrokerPlugin',
        'Microsoft.Windows.SecHealthUI','Microsoft.Windows.XGpuEjectDialog',
        'Microsoft.Windows.Apprep.ChxApp','Microsoft.Windows.Pinning',
        'Microsoft.Windows.Cortana','InputApp','Microsoft.Windows.ContentDeliveryManager',
        'Microsoft.NET','Microsoft.VCLibs','Microsoft.UI','Microsoft.Windows.Shell'
    )

    $pkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    if (-not $pkgs) { $pkgs = Get-AppxPackage -ErrorAction SilentlyContinue }

    foreach ($pattern in $b.remove) {
        $rx = ('(?i)^' + [regex]::Escape($pattern).Replace('\*','.*') + '$')
        $targets = $pkgs | Where-Object { $_.Name -match $rx }
        if (-not $targets) {
            Write-Boi "no installed package matches '$pattern'" 'INFO'
            continue
        }
        foreach ($p in $targets) {
            foreach ($prot in $protected) {
                if ($p.Name -like "*$prot*") {
                    Write-Boi "REFUSING to remove protected system package: $($p.Name)" 'WARN'
                    $p = $null
                    break
                }
            }
            if (-not $p) { continue }

            $pkgFull = $p.PackageFullName
            Add-BoiJournalEntry -Kind 'appx' -Action 'remove' -Path $pkgFull `
                -Detail $p.Name -Extra @{ version = [string]$p.Version } | Out-Null
            Invoke-BoiAction -Description "remove AppX: $($p.Name) ($($p.Version))" -Action ([scriptblock]::Create(
                "Remove-AppxPackage -Package '$pkgFull' -AllUsers -ErrorAction Continue; Remove-AppxProvisionedPackage -Online -PackageName '$pkgFull' -ErrorAction SilentlyContinue"
            ))
            Add-BoiResult "remove $($p.Name)" 'OK'
        }
    }

    Write-Boi 'bloatware removal done (reboot fully clears provisioned tiles)' 'OK'
}
