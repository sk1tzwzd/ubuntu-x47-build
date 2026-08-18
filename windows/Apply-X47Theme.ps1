#requires -RunAsAdministrator
<#
.SYNOPSIS
  Switch the X47 Windows look: XP, remastered XP, Vista, Windows 10, Windows 11, or X47.

.EXAMPLE
  C:\X47\Apply-X47Theme.ps1
  C:\X47\Apply-X47Theme.ps1 -Theme xp-remastered
#>
[CmdletBinding()]
param(
    [ValidateSet('x47','xp','xp-remastered','vista','win10','win11')]
    [string]$Theme
)

$ErrorActionPreference = 'Stop'
$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KitRoot 'lib\X47Common.ps1')
. (Join-Path $KitRoot 'lib\X47Theme.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-EnsureLog

if (-not $Theme) {
    Write-Host ''
    Write-Host 'X47 Windows look' -ForegroundColor Cyan
    Write-Host '  1) X47 circuit (current default)'
    Write-Host '  2) Windows XP'
    Write-Host '  3) Remastered XP  (XP feel, modern DPI / search)'
    Write-Host '  4) Windows Vista'
    Write-Host '  5) Windows 10'
    Write-Host '  6) Windows 11 stock'
    Write-Host ''
    $pick = Read-Host 'Choose 1-6'
    $Theme = @{
        '1' = 'x47'
        '2' = 'xp'
        '3' = 'xp-remastered'
        '4' = 'vista'
        '5' = 'win10'
        '6' = 'win11'
    }[$pick]
    if (-not $Theme) { throw 'invalid choice' }
}

X47-Log "applying theme $Theme"
X47-ApplyThemePreset -Name $Theme -KitRoot $KitRoot
Write-Host ''
Write-Host "Theme '$Theme' applied. Sign out / back in if the Start menu did not refresh." -ForegroundColor Green
Write-Host 'This is Start + taskbar + wallpaper + accent — not a full Luna/Aero title-bar patch.'
Write-Host 'Switch again anytime: C:\X47\Apply-X47Theme.bat'
