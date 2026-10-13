# Quality-of-life / debloat registry tweaks (the RedsCleanWindows classics).
# config.experience: { enabled,
#   noMsAccountNag, noStartRecs, noWebSearch, noLockScreenAds, noWidgets,
#   noTips, noCopilot, noAADJoin, showFileExtensions, showHiddenFiles,
#   noGameBarAds, noFeedback, classicContextMenu }
# Every key is optional; defaults listed below are what ships in config.example.json.

function Invoke-BoiExperience {
    param([Parameter(Mandatory)]$Cfg)

    $e = $Cfg.experience
    if (-not $e -or -not $e.enabled) { Add-BoiResult 'experience tweaks' 'SKIP'; return }

    Write-Boi 'experience / debloat tweaks' 'STEP'

    function On-Off($v, $default) {
        if ($null -eq $v) { return $default }
        return [bool]$v
    }

    # stop windows nagging you to convert the local account to an MSA
    if (On-Off $e.noMsAccountNag $true) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_AccountNotifications' 0
    }

    # no "interests"/recommended tiles on the start menu
    if (On-Off $e.noStartRecs $true) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    }

    # searches stay local (no Bing results in start search)
    if (On-Off $e.noWebSearch $true) {
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    }

    # no ads on the lock screen ("fun facts")
    if (On-Off $e.noLockScreenAds $true) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
    }

    # kill widgets/news & interests
    if (On-Off $e.noWidgets $true) {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
    }

    # no "take a tour of windows" / tips popups
    if (On-Off $e.noTips $true) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338381Enabled' 0
    }

    # hide copilot button (harmless on machines that never had it)
    if (On-Off $e.noCopilot $false) {
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\Copilot' 'TurnOffCopilot' 1
    }

    # stop windows pestering you to join a work/school account
    if (On-Off $e.noAADJoin $true) {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin' 'BlockAADWorkplaceJoin' 1
    }

    # explorer: extensions + hidden files always visible
    if (On-Off $e.showFileExtensions $true) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
    }
    if (On-Off $e.showHiddenFiles $false) {
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1
    }

    # game bar / captures nag
    if (On-Off $e.noGameBarAds $true) {
        New-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Force | Out-Null
        Set-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
        Set-RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    }

    # feedback hub prompts
    if (On-Off $e.noFeedback $true) {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\DataCollection' 'AllowTelemetry' 1
        Set-RegValue 'HKCU:\Software\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    }

    # win10-style classic context menu ("hide expanded context menus")
    if (On-Off $e.classicContextMenu $false) {
        Set-RegValue 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' -Type String
    }

    Add-BoiResult 'experience tweaks' 'OK'
}
