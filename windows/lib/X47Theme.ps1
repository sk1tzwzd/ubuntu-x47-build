# Theme helpers — Open-Shell + ExplorerPatcher + original wallpapers.
# Skins shipped with Open-Shell (GPL). No Microsoft Luna/Aero files.

function X47-SetWallpaperFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "wallpaper missing: $Path" }
    $userPictures = Join-Path $env:USERPROFILE 'Pictures\X47'
    New-Item -ItemType Directory -Path $userPictures -Force | Out-Null
    $dest = Join-Path $userPictures (Split-Path $Path -Leaf)
    Copy-Item $Path $dest -Force
    if (-not ([System.Management.Automation.PSTypeName]'X47Wallpaper').Type) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public class X47Wallpaper {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
    }
    [void][X47Wallpaper]::SystemParametersInfo(0x0014, 0, $dest, 0x03)
    X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value $dest -Type String
    X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10' -Type String
    X47-SetReg -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0' -Type String
    X47-SetReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name LockScreenImage -Value $dest -Type String
    X47-Log "wallpaper → $dest" 'OK'
}

function X47-RgbToAccent {
    param([int]$R, [int]$G, [int]$B)
    # DWM AccentColor is 0xAABBGGRR
    return [int](0xFF000000 -bor ($B -shl 16) -bor ($G -shl 8) -bor $R)
}

function X47-SetAccent {
    param([int]$R, [int]$G, [int]$B, [switch]$ColoredTitlebars)
    $accent = X47-RgbToAccent $R $G $B
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name AccentColor -Value $accent
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name AccentColorInactive -Value $accent
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name ColorizationColor -Value $accent
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name ColorPrevalence -Value $(if ($ColoredTitlebars) { 1 } else { 0 })
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\DWM' -Name EnableWindowColorization -Value $(if ($ColoredTitlebars) { 1 } else { 0 })
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name ColorPrevalence -Value $(if ($ColoredTitlebars) { 1 } else { 0 })
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Value 1
    X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -Name AccentColorMenu -Value $accent
    X47-Log ("accent RGB({0},{1},{2})" -f $R, $G, $B) 'OK'
}

function X47-EnsureOpenShell {
    $exe = @(
        "${env:ProgramFiles}\Open-Shell\StartMenu.exe"
        "${env:ProgramFiles(x86)}\Open-Shell\StartMenu.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($exe) { return $true }

    X47-Log 'Open-Shell not installed — downloading official release'
    $api = 'https://api.github.com/repos/Open-Shell/Open-Shell-Menu/releases/latest'
    try {
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'X47-Windows-Kit' }
        $asset = $rel.assets | Where-Object { $_.name -like 'OpenShellSetup*.exe' } | Select-Object -First 1
        if (-not $asset) { throw 'no OpenShellSetup asset' }
        $tmp = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing
        Start-Process -FilePath $tmp -ArgumentList '/qn','ADDLOCAL=StartMenu' -Wait
        X47-Log 'Open-Shell installed' 'OK'
        return $true
    } catch {
        X47-Log "Open-Shell install failed: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function X47-EnsureExplorerPatcher {
    $key = 'HKLM:\SOFTWARE\ExplorerPatcher'
    if (Test-Path $key) { return $true }
    if (Get-ItemProperty 'HKCU:\Software\ExplorerPatcher' -ErrorAction SilentlyContinue) { return $true }

    X47-Log 'ExplorerPatcher not installed — downloading official release'
    $api = 'https://api.github.com/repos/valinet/ExplorerPatcher/releases/latest'
    try {
        $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'X47-Windows-Kit' }
        $asset = $rel.assets | Where-Object { $_.name -eq 'ep_setup.exe' } | Select-Object -First 1
        if (-not $asset) { throw 'no ep_setup.exe' }
        $tmp = Join-Path $env:TEMP 'ep_setup.exe'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing
        Start-Process -FilePath $tmp -Wait
        X47-Log 'ExplorerPatcher installed (Explorer will restart)' 'OK'
        return $true
    } catch {
        X47-Log "ExplorerPatcher install failed: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function X47-SetOpenShellStyle {
    param(
        [ValidateSet('Classic','Classic2','Win7')][string]$MenuStyle,
        [string]$ClassicSkin = 'Windows XP Luna',
        [string]$Win7Skin = 'Windows Aero',
        [int]$LargeIcons = 0,
        [int]$EnableSearch = 1
    )
    $p = 'HKCU:\Software\OpenShell\StartMenu\Settings'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    X47-SetReg -Path $p -Name MenuStyle -Value $MenuStyle -Type String
    X47-SetReg -Path $p -Name SkinC1 -Value $ClassicSkin -Type String
    X47-SetReg -Path $p -Name SkinC2 -Value $ClassicSkin -Type String
    X47-SetReg -Path $p -Name SkinW7 -Value $Win7Skin -Type String
    X47-SetReg -Path $p -Name SearchBox -Value $EnableSearch
    X47-SetReg -Path $p -Name LargeIcons -Value $LargeIcons
    X47-SetReg -Path $p -Name EnableStartButton -Value 1
    X47-Log "Open-Shell MenuStyle=$MenuStyle skin=$ClassicSkin/$Win7Skin" 'OK'
}

function X47-SetExplorerPatcherTaskbar {
    param(
        [ValidateSet('win10','win11')][string]$Style,
        [switch]$NeverCombine
    )
    $p = 'HKCU:\Software\ExplorerPatcher'
    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
    # 0 = Windows 11 taskbar, 1 = Windows 10 taskbar
    X47-SetReg -Path $p -Name OldTaskbar -Value $(if ($Style -eq 'win10') { 1 } else { 0 })
    if ($NeverCombine) {
        X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarGlomLevel -Value 2
    }
    X47-Log "ExplorerPatcher taskbar=$Style" 'OK'
}

function X47-DisableTransformations {
    # Restore stock Windows 11 Start / taskbar as far as we can without uninstalling.
    $os = 'HKCU:\Software\OpenShell\StartMenu\Settings'
    if (Test-Path $os) {
        X47-SetReg -Path $os -Name EnableStartButton -Value 0
        X47-Log 'Open-Shell start button disabled (stock Start)'
    }
    $ep = 'HKCU:\Software\ExplorerPatcher'
    if (Test-Path $ep) {
        X47-SetReg -Path $ep -Name OldTaskbar -Value 0
    }
}

function X47-ApplyThemePreset {
    param(
        [ValidateSet('x47','xp','xp-remastered','vista','win10','win11')][string]$Name,
        [string]$KitRoot
    )
    $wp = Join-Path $KitRoot 'assets\wallpapers'
    switch ($Name) {
        'x47' {
            X47-SetWallpaperFile (Join-Path $wp 'x47-circuit.png')
            X47-SetAccent -R 13 -G 148 -B 136 -ColoredTitlebars
            X47-DisableTransformations
            X47-Log 'theme x47 — circuit + stock Win11 chrome' 'OK'
        }
        'xp' {
            X47-SetWallpaperFile (Join-Path $wp 'theme-xp.png')
            X47-SetAccent -R 49 -G 106 -B 197 -ColoredTitlebars
            if (X47-EnsureOpenShell) {
                X47-SetOpenShellStyle -MenuStyle Classic -ClassicSkin 'Windows XP Luna' -LargeIcons 0 -EnableSearch 0
            }
            if (X47-EnsureExplorerPatcher) {
                X47-SetExplorerPatcherTaskbar -Style win10 -NeverCombine
            }
            X47-Log 'theme xp — Luna Start + Win10 taskbar + original hills wallpaper' 'OK'
        }
        'xp-remastered' {
            X47-SetWallpaperFile (Join-Path $wp 'theme-xp-remastered.png')
            X47-SetAccent -R 45 -G 98 -B 186 -ColoredTitlebars
            if (X47-EnsureOpenShell) {
                # Two-column classic, Luna skin, search on, large icons — XP feel at modern DPI.
                X47-SetOpenShellStyle -MenuStyle Classic2 -ClassicSkin 'Windows XP Luna' -LargeIcons 1 -EnableSearch 1
            }
            if (X47-EnsureExplorerPatcher) {
                X47-SetExplorerPatcherTaskbar -Style win10 -NeverCombine
            }
            # Keep text readable on 4K: do not force Tahoma.
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name TaskbarSmallIcons -Value 0
            X47-Log 'theme xp-remastered — Luna + search + large icons + dusk hills' 'OK'
        }
        'vista' {
            X47-SetWallpaperFile (Join-Path $wp 'theme-vista.png')
            X47-SetAccent -R 70 -G 160 -B 140 -ColoredTitlebars
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name EnableTransparency -Value 1
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -Value 0
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name SystemUsesLightTheme -Value 0
            if (X47-EnsureOpenShell) {
                X47-SetOpenShellStyle -MenuStyle Win7 -Win7Skin 'Windows Aero' -EnableSearch 1
            }
            if (X47-EnsureExplorerPatcher) {
                X47-SetExplorerPatcherTaskbar -Style win10
            }
            X47-Log 'theme vista — Aero Start + transparency + aurora wallpaper' 'OK'
        }
        'win10' {
            X47-SetWallpaperFile (Join-Path $wp 'theme-win11.png')
            X47-SetAccent -R 0 -G 120 -B 215 -ColoredTitlebars
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -Value 1
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name SystemUsesLightTheme -Value 1
            X47-DisableTransformations
            if (X47-EnsureExplorerPatcher) {
                X47-SetExplorerPatcherTaskbar -Style win10
            }
            if (X47-EnsureOpenShell) {
                X47-SetOpenShellStyle -MenuStyle Win7 -Win7Skin 'Midnight' -EnableSearch 1
                # Prefer stock Win10-like Start from Open-Shell Win7? Better: disable Open-Shell, EP Win10 Start is limited.
                # Keep Open-Shell off so ExplorerPatcher can restore the Windows 10 Start if available.
                X47-SetReg -Path 'HKCU:\Software\OpenShell\StartMenu\Settings' -Name EnableStartButton -Value 0
            }
            X47-Log 'theme win10 — ExplorerPatcher Windows 10 taskbar' 'OK'
        }
        'win11' {
            X47-SetWallpaperFile (Join-Path $wp 'theme-win11.png')
            X47-SetAccent -R 0 -G 103 -B 192
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -Value 1
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name SystemUsesLightTheme -Value 1
            X47-SetReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name ColorPrevalence -Value 0
            X47-DisableTransformations
            if (Test-Path 'HKCU:\Software\ExplorerPatcher') {
                X47-SetExplorerPatcherTaskbar -Style win11
            }
            X47-Log 'theme win11 — stock Start/taskbar + bloom wallpaper' 'OK'
        }
    }

    $state = Join-Path $KitRoot 'logs\theme.txt'
    X47-EnsureLog
    Set-Content -Path $state -Value $Name -Encoding UTF8
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Start-Process explorer } catch {}
}
