#requires -RunAsAdministrator
<#
.SYNOPSIS
  X47 Windows 11 privacy twin — wallpaper, debloat, privacy, IDs, BitLocker+PIN.

.EXAMPLE
  Set-ExecutionPolicy Bypass -Scope Process
  C:\X47\Install-X47Windows.ps1

.EXAMPLE
  C:\X47\Install-X47Windows.ps1 -SkipBitLocker
#>
[CmdletBinding()]
param(
    [switch]$SkipWallpaper,
    [switch]$SkipDebloat,
    [switch]$SkipPrivacy,
    [switch]$SkipIdentifiers,
    [switch]$SkipBitLocker,
    [switch]$SkipSecurity,
    [switch]$SkipAnonymity,
    [switch]$SkipTheme,
    [ValidateSet('x47','xp','xp-remastered','vista','win10','win11')]
    [string]$Theme
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot

X47-RequireAdmin
X47-EnsureLog
X47-Log "kit root = $KitRoot"
X47-Log ("user={0} host={1} edition={2}" -f $env:USERNAME, $env:COMPUTERNAME, (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName)

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' X47 Windows 11 — privacy twin' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'This will:'
Write-Host '  1. Set wallpaper (X47, or XP / Vista / Win10 / Win11 look)'
Write-Host '  2. Remove Xbox / widgets / Copilot / consumer junk'
Write-Host '  3. Harden privacy (telemetry Required, ads/location off)'
Write-Host '  4. Rotate advertising + SQM IDs (MachineGuid left alone)'
if (-not $SkipSecurity) {
    Write-Host '  5. Harden security (inbound firewall, RDP off, Defender stays)'
}
if (-not $SkipAnonymity) {
    Write-Host '  6. Max-offline anonymity (block MSA / Store / OneDrive / telemetry hosts)'
}
if (-not $SkipTheme) {
    Write-Host '  7. Apply a look (XP, remastered XP, Vista, Win10, Win11, or X47)'
}
if (-not $SkipBitLocker) {
    Write-Host '  8. Turn on BitLocker with a pre-boot PIN (full volume)'
}
Write-Host ''
Write-Host 'Stay on AC power. Have a USB stick ready for the recovery key.'
Write-Host 'Ubuntu dual-boot stays on GRUB. The PIN only unlocks Windows.'
Write-Host 'Store / OneDrive / Xbox / Microsoft sign-in will likely break. Update stays.'
Write-Host ''
$go = Read-Host 'Type YES to continue'
if ($go -ne 'YES') {
    X47-Log 'aborted by user'
    exit 1
}

$steps = @(
    @{ Flag = $SkipWallpaper;    Name = '01-wallpaper.ps1' }
    @{ Flag = $SkipDebloat;      Name = '02-debloat.ps1' }
    @{ Flag = $SkipPrivacy;      Name = '03-privacy.ps1' }
    @{ Flag = $SkipIdentifiers;  Name = '04-identifiers.ps1' }
    @{ Flag = $SkipSecurity;     Name = '07-security.ps1' }
    @{ Flag = $SkipAnonymity;    Name = '08-anonymity.ps1' }
    @{ Flag = $SkipTheme;        Name = '06-themes.ps1' }
    @{ Flag = $SkipBitLocker;    Name = '05-bitlocker.ps1' }
)

$failed = @()
foreach ($step in $steps) {
    if ($step.Flag) {
        X47-Log "skip $($step.Name)"
        continue
    }
    $path = Join-Path $KitRoot "modules\$($step.Name)"
    X47-Log "running $path"
    try {
        if ($step.Name -eq '06-themes.ps1' -and $Theme) {
            & $path -KitRoot $KitRoot -Theme $Theme
        } else {
            & $path -KitRoot $KitRoot
        }
    } catch {
        X47-Log "$($step.Name) failed: $($_.Exception.Message)" 'ERROR'
        $failed += $step.Name
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    X47-Log ("finished with failures: {0}" -f ($failed -join ', ')) 'WARN'
    Write-Host "See $script:X47LogFile"
    exit 1
}

X47-Log 'X47 Windows kit finished' 'OK'
Write-Host ''
Write-Host 'Next:' -ForegroundColor Green
Write-Host '  • If BitLocker is encrypting, wait for manage-bde -status C: = 100%'
Write-Host '  • Keep the USB recovery key. Photograph it.'
Write-Host '  • Shut down (not restart-from-Fast-Startup). Boot Ubuntu from GRUB.'
Write-Host '  • On Ubuntu: x47-windows-import-key /path/to/X47-BitLocker-Recovery-*.txt'
Write-Host "  • Guide: $KitRoot\docs\x47-windows-guide.html"
Write-Host '  • Change the look later: C:\X47\Apply-X47Theme.bat'
Write-Host '  • Anonymity only / revert: C:\X47\Apply-X47Anonymity.bat'
Write-Host ''
