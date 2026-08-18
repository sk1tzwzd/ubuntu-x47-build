# Cut Windows 11 telemetry, ads, location, and activity history.
# Pro can only force diagnostic data to Required (0/Security needs Enterprise).
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' })
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 03 privacy ==='

# Diagnostic data: 1 = Required on Pro/Home. (0 is Enterprise-only and is ignored here.)
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name AllowTelemetry -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name DoNotShowFeedbackNotifications -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name DisableTelemetryOptInSettingsUx -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name AllowTelemetry -Value 1
X47-SetReg -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name NumberOfSIUFInPeriod -Value 0

# Advertising / tailored experiences
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name DisabledByGroupPolicy -Value 1
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name Enabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name TailoredExperiencesWithDiagnosticDataEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name Start_TrackProgs -Value 0

# Location + Find My Device
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name DisableLocation -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name DisableLocationScripting -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' -Name AllowFindMyDevice -Value 0
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' -Name Status -Value 0

# Activity history / Timeline
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name PublishUserActivities -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name UploadUserActivities -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableActivityFeed -Value 0

# Search: no cloud, no web, no history upload
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name IsMSACloudSearchEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name IsAADCloudSearchEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name IsDeviceSearchHistoryEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name BingSearchEnabled -Value 0
X47-SetReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name DisableSearchBoxSuggestions -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name AllowCortana -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name DisableWebSearch -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name ConnectedSearchUseWeb -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name AllowSearchToUseLocation -Value 0

# Input / inking personalization
X47-SetReg -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name RestrictImplicitInkCollection -Value 1
X47-SetReg -Path 'HKCU:\Software\Microsoft\InputPersonalization' -Name RestrictImplicitTextCollection -Value 1
X47-SetReg -Path 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' -Name HarvestContacts -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Personalization\Settings' -Name AcceptedPrivacyPolicy -Value 0

# Delivery Optimization: no internet P2P
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name DODownloadMode -Value 0

# Edge telemetry / shopping / follow
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name DiagnosticData -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name PersonalizationReportingEnabled -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name SearchSuggestEnabled -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name HubsSidebarEnabled -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name EdgeShoppingAssistantEnabled -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name ShowRecommendationsEnabled -Value 0

# Wi-Fi Sense / hotspot auto-connect leftovers
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' -Name AutoConnectAllowedOEM -Value 0

# Clipboard cloud sync
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name AllowClipboardHistory -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name AllowCrossDeviceClipboard -Value 0

X47-DisableService 'DiagTrack'
X47-DisableService 'dmwappushservice'
X47-DisableService 'WerSvc'
X47-DisableService 'PcaSvc'
X47-DisableService 'RetailDemo'
X47-DisableService 'RemoteRegistry'

# Scheduled telemetry tasks (best-effort; names vary by build)
$tasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
    '\Microsoft\Windows\Autochk\Proxy'
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
    '\Microsoft\Windows\Feedback\Siuf\DmClient'
    '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    '\Microsoft\Windows\Maps\MapsToastTask'
    '\Microsoft\Windows\Maps\MapsUpdateTask'
)
foreach ($t in $tasks) {
    try {
        Disable-ScheduledTask -TaskName (Split-Path $t -Leaf) -TaskPath ((Split-Path $t -Parent) + '\') -ErrorAction Stop | Out-Null
        X47-Log "disabled task $t" 'OK'
    } catch {
        X47-Log "task not disabled $t" 'WARN'
    }
}

X47-Log 'privacy policies applied (telemetry = Required)' 'OK'
