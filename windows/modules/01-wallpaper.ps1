# Apply the X47 circuit wallpaper (desktop + lock screen).
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' })
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 01 wallpaper ==='

$srcDir = Join-Path $KitRoot 'assets\wallpapers'
$primary = Join-Path $srcDir 'x47-circuit.png'
if (-not (Test-Path $primary)) {
    throw "missing $primary — restage the kit from Ubuntu"
}

$userPictures = Join-Path $env:USERPROFILE 'Pictures\X47'
New-Item -ItemType Directory -Path $userPictures -Force | Out-Null
Get-ChildItem -Path $srcDir -Filter 'x47-circuit*.png' | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $userPictures $_.Name) -Force
}
$dest = Join-Path $userPictures 'x47-circuit.png'
X47-Log "wallpapers copied to $userPictures"

# Desktop for the current user (and default user so new accounts match).
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class X47Wallpaper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02
[void][X47Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $dest, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE))

X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $dest -Type String
X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' -Type String  # fill
X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0' -Type String

# Lock screen (machine policy — applies at the login screen).
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name LockScreenImage -Value $dest -Type String
X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name NoChangingLockScreen -Value 0

X47-Log 'desktop + lock screen set to x47-circuit.png' 'OK'
