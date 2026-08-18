# Reset advertising / telemetry IDs. Does NOT touch MachineGuid, SMBIOS UUID, or the TPM.
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' })
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 04 identifiers ==='

X47-Log 'leaving HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid alone (activation / BitLocker / Update)' 'WARN'

# Advertising ID: disable + rotate the stored value so old ad graphs stop matching.
$adPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
X47-SetReg -Path $adPath -Name Enabled -Value 0
$newAd = [guid]::NewGuid().ToString()
X47-SetReg -Path $adPath -Name Id -Value $newAd -Type String
X47-Log "Advertising ID disabled and rotated"

# SQM / CEIP machine id (telemetry correlation — not the OS MachineGuid).
$sqm = 'HKLM:\SOFTWARE\Microsoft\SQMClient'
if (-not (Test-Path $sqm)) { New-Item -Path $sqm -Force | Out-Null }
X47-SetReg -Path $sqm -Name MachineId -Value ('{' + [guid]::NewGuid().ToString().ToUpper() + '}') -Type String
X47-Log 'SQM MachineId rotated'

# Device metadata cache (OEM "phone home" catalog).
$meta = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata'
X47-SetReg -Path $meta -Name PreventDeviceMetadataFromNetwork -Value 1

# Windows Error Reporting user id leftovers.
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Windows Error Reporting' -Name MachineID -Force -ErrorAction SilentlyContinue

# Inventory of what we will NOT change (for the log / guide).
$machineGuid = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
$board = $null
try {
    $board = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
} catch { $board = 'unavailable' }

@"
# X47 identifier report — $(Get-Date -Format o)
AdvertisingIdEnabled=0
AdvertisingId=$newAd
SQM_MachineId=rotated
OS_MachineGuid=$machineGuid   # UNCHANGED on purpose
SMBIOS_UUID=$board            # firmware; cannot remove from Windows
TPM=untouched
"@ | Set-Content -Path (Join-Path $KitRoot 'logs\identifiers.txt') -Encoding UTF8

X47-Log 'identifier reset done (MachineGuid / SMBIOS / TPM left intact)' 'OK'
