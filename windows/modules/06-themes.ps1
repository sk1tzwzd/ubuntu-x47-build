# Prompt for (or apply) an X47 Windows look.
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' }),
    [string]$Theme
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
. (Join-Path $KitRoot 'lib\X47Theme.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 06 themes ==='

if (-not $Theme) {
    Write-Host ''
    Write-Host 'How should Windows look?' -ForegroundColor Cyan
    Write-Host '  1) X47 circuit (default)'
    Write-Host '  2) Windows XP'
    Write-Host '  3) Remastered XP'
    Write-Host '  4) Windows Vista'
    Write-Host '  5) Windows 10'
    Write-Host '  6) Windows 11 stock'
    Write-Host ''
    $pick = Read-Host 'Choose 1-6 [1]'
    if (-not $pick) { $pick = '1' }
    $Theme = @{
        '1' = 'x47'
        '2' = 'xp'
        '3' = 'xp-remastered'
        '4' = 'vista'
        '5' = 'win10'
        '6' = 'win11'
    }[$pick]
    if (-not $Theme) { $Theme = 'x47' }
}

X47-ApplyThemePreset -Name $Theme -KitRoot $KitRoot
