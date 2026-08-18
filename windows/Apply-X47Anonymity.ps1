#requires -RunAsAdministrator
# Security + max-offline anonymity without re-running BitLocker or themes.
[CmdletBinding()]
param([switch]$Revert)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-EnsureLog

if ($Revert) {
    & (Join-Path $KitRoot 'modules\08-anonymity.ps1') -KitRoot $KitRoot -Revert
    exit 0
}

Write-Host ''
Write-Host 'X47 anonymity + security pass' -ForegroundColor Cyan
Write-Host 'This blocks Microsoft account / Store / OneDrive / Xbox / telemetry hosts.'
Write-Host 'Windows Update and Defender stay on. Your IP is still visible without Mullvad.'
Write-Host ''
$go = Read-Host 'Type YES to continue'
if ($go -ne 'YES') { exit 1 }

& (Join-Path $KitRoot 'modules\07-security.ps1') -KitRoot $KitRoot
& (Join-Path $KitRoot 'modules\08-anonymity.ps1') -KitRoot $KitRoot
Write-Host 'Done. Sign out recommended. Revert hosts: Apply-X47Anonymity.ps1 -Revert' -ForegroundColor Green
