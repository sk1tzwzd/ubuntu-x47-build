# Remove consumer junk. Keep Defender, Settings, Store, Photos, Calculator, Notepad, Terminal.
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' })
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 02 debloat ==='

$remove = @(
    'Microsoft.XboxApp'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.GamingApp'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MixedReality.Portal'
    'Microsoft.People'
    'Microsoft.SkypeApp'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.YourPhone'
    'Microsoft.BingNews'
    'Microsoft.BingWeather'
    'Microsoft.BingSearch'
    'Microsoft.Todos'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.Clipchamp'
    'Microsoft.OutlookForWindows'
    'Microsoft.Windows.DevHome'
    'Microsoft.Copilot'
    'Microsoft.549981C3F5F10'   # Cortana
    'MSTeams'
    'MicrosoftTeams'
    'Microsoft.XboxGameCallableUI'
    'Microsoft.GamingServices'
    'Microsoft.Paint3D'
    'Microsoft.Whiteboard'
    'Microsoft.Windows.DevHome'
    'MicrosoftWindows.CrossDevice'
    'Microsoft.Windows.CrossDevice'
    'Microsoft.MicrosoftFamily'
    'Microsoft.Family'
    'MicrosoftCorporationII.QuickAssist'
    'Microsoft.QuickAssist'
    'Microsoft.Windows.Ai.Copilot.Provider'
    'Microsoft.Copilot_8wekyb3d8bbwe'
    'Microsoft.StartExperiencesApp'
    'MicrosoftWindows.Client.WebExperience'
    'Microsoft.Windows.Photos.Automation'
)

$removed = @()
$skipped = @()
foreach ($name in $remove) {
    $pkgs = @()
    $pkgs += Get-AppxPackage -Name $name -AllUsers -ErrorAction SilentlyContinue
    $pkgs += Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $name }
    if (-not $pkgs) {
        $skipped += $name
        continue
    }
    foreach ($pkg in $pkgs) {
        try {
            if ($pkg.PSObject.Properties.Name -contains 'PackageFullName') {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            } elseif ($pkg.PSObject.Properties.Name -contains 'PackageName') {
                Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop
            }
            X47-Log "removed $name" 'OK'
            $removed += $name
        } catch {
            X47-Log "could not remove ${name}: $($_.Exception.Message)" 'WARN'
        }
    }
}

# Widgets / Copilot taskbar (does not uninstall Store).
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name AllowNewsAndInterests -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarDa -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name ShowTaskViewButton -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarMn -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Copilot' -Name TurnOffWindowsCopilot -Value 1
X47-SetReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\Windows Copilot' -Name TurnOffWindowsCopilot -Value 1

# Consumer Microsoft-account / suggested-app nags.
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsConsumerFeatures -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableSoftLanding -Value 1
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name SystemPaneSuggestionsEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name SilentInstalledAppsEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name SubscribedContent-338388Enabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name SubscribedContent-338389Enabled -Value 0

# Fast Startup off — required for dual-boot and for Linux to mount NTFS safely.
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0
try {
    powercfg /hibernate off | Out-Null
    X47-Log 'Fast Startup / hibernate off' 'OK'
} catch {
    X47-Log "hibernate off failed: $($_.Exception.Message)" 'WARN'
}

# Uninstall OneDrive. Does not delete already-synced files on disk.
$odRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if (Get-ItemProperty -Path $odRun -Name OneDrive -ErrorAction SilentlyContinue) {
    Remove-ItemProperty -Path $odRun -Name OneDrive -Force -ErrorAction SilentlyContinue
}
$odSetup = @(
    "$env:SystemRoot\System32\OneDriveSetup.exe"
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($odSetup) {
    try {
        Start-Process -FilePath $odSetup -ArgumentList '/uninstall' -Wait -ErrorAction Stop
        X47-Log 'OneDrive uninstalled (local files left in place)' 'OK'
    } catch {
        X47-Log "OneDrive uninstall failed: $($_.Exception.Message)" 'WARN'
    }
}

# Second pass: provisioned packages by wildcard so they do not return after a feature update.
$provWild = @(
    '*Xbox*', '*GamingApp*', '*Clipchamp*', '*BingNews*', '*BingWeather*',
    '*YourPhone*', '*Teams*', '*Copilot*', '*QuickAssist*', '*OneDrive*',
    '*MicrosoftOfficeHub*', '*WindowsMaps*', '*Zune*', '*Solitaire*'
)
$prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($pat in $provWild) {
    foreach ($pkg in ($prov | Where-Object { $_.DisplayName -like $pat })) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
            X47-Log "deprovisioned $($pkg.DisplayName)" 'OK'
        } catch {
            X47-Log "deprovision $($pkg.DisplayName) failed" 'WARN'
        }
    }
}

$note = Join-Path $KitRoot 'logs\debloat-removed.txt'
X47-EnsureLog
@("removed=$($removed -join ',')", "already_absent=$($skipped -join ',')") | Set-Content -Path $note -Encoding UTF8
X47-Log "debloat finished ($($removed.Count) removed). Reinstall via Microsoft Store if needed." 'OK'
