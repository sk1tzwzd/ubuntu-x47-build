# Security hardening. Defender and SmartScreen stay on. Outbound stays allow (Update).
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' })
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 07 security ==='

# Inbound lock on Private/Public. Do not set outbound Block.
try {
    Set-NetFirewallProfile -Profile Private,Public -DefaultInboundAction Block -DefaultOutboundAction Allow -ErrorAction Stop
    Set-NetFirewallProfile -Profile Domain -DefaultInboundAction Block -DefaultOutboundAction Allow -ErrorAction SilentlyContinue
    X47-Log 'firewall inbound=Block outbound=Allow' 'OK'
} catch {
    X47-Log "firewall profile: $($_.Exception.Message)" 'WARN'
}

# RDP / Remote Assistance / WinRM
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fDenyTSConnections -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -Name fAllowToGetHelp -Value 0
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -Name fAllowToGetHelp -Value 0
try { Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue } catch {}
X47-DisableService 'TermService'
X47-DisableService 'RemoteAccess'
X47-DisableService 'WinRM'
X47-DisableService 'RemoteRegistry'
try { Stop-Service WinRM -Force -ErrorAction SilentlyContinue; Set-Service WinRM -StartupType Disabled -ErrorAction SilentlyContinue } catch {}

# SMBv1
try {
    Disable-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -NoRestart -ErrorAction SilentlyContinue | Out-Null
    X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name SMB1 -Value 0
    X47-Log 'SMBv1 disabled' 'OK'
} catch {
    X47-Log "SMBv1: $($_.Exception.Message)" 'WARN'
}

# LLMNR / NetBIOS / WPAD
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name EnableMulticast -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad' -Name WpadOverride -Value 1
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name UseDomainNameDevolution -Value 0
try {
    Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=true' -ErrorAction SilentlyContinue | ForEach-Object {
        Invoke-CimMethod -InputObject $_ -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } -ErrorAction SilentlyContinue | Out-Null
    }
    X47-Log 'NetBIOS-over-TCP disabled on IP adapters' 'OK'
} catch {
    X47-Log 'NetBIOS disable best-effort failed' 'WARN'
}

# Teredo / 6to4 / ISATAP
foreach ($cmd in @(
    'netsh interface teredo set state disabled',
    'netsh interface 6to4 set state disabled',
    'netsh interface isatap set state disabled'
)) {
    cmd /c $cmd 2>$null | Out-Null
}
X47-Log 'Teredo/6to4/ISATAP disabled'

# AutoPlay / AutoRun
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -Value 255
X47-SetReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -Value 255
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoAutorun -Value 1

# UAC highest (prompt on secure desktop)
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorAdmin -Value 2
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorUser -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name PromptOnSecureDesktop -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1

# WDigest / LSA
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name UseLogonCredential -Value 0
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name RunAsPPL -Value 1
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name DisableRestrictedAdmin -Value 0
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LimitBlankPasswordUse -Value 1
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name NoLmHash -Value 1
X47-SetReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -Value 5

# Recall / screenshot history
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name DisableAIDataAnalysis -Value 1
X47-SetReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' -Name DisableAIDataAnalysis -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name AllowRecallEnablement -Value 0
X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name DisabledTips -Value 1

# Defender + SmartScreen stay ON
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' -Name DisableAntiSpyware -Value 0
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableSmartScreen -Value 1
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter' -Name EnabledV9 -Value 1
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    X47-Log 'Defender realtime left enabled' 'OK'
} catch {
    X47-Log 'Defender preference unchanged' 'WARN'
}

X47-Log 'security hardening applied' 'OK'
