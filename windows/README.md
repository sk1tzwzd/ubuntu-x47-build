# X47 Windows 11 kit

Privacy twin for the [Ubuntu X47](https://sk1tzwzd.github.io/ubuntu-x47-build/) build.

**Site:** [Windows overview](https://sk1tzwzd.github.io/ubuntu-x47-build/windows.html) · [Install](https://sk1tzwzd.github.io/ubuntu-x47-build/windows-install.html)

Run **from Windows 11 Pro, as Administrator**. Staging from Linux only copies files.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
C:\X47\Install-X47Windows.ps1
```

Or right-click `Install-X47Windows.bat` → Run as administrator.

## Security and privacy (short)

**Keeps:** Defender, SmartScreen, Windows Update, BitLocker, local files.

**Locks:** inbound firewall; RDP/WinRM/SMBv1/LLMNR off; UAC max; Recall off; Fast Startup off.

**Cuts:** telemetry to Required; ads/location/activity history off; Advertising ID + SQM ID rotated; Microsoft accounts blocked; Store/OneDrive/Xbox/telemetry hosts blocked; OneDrive uninstalled; Wi-Fi MAC random; NTP → pool.ntp.org.

**Does not hide:** board UUID, TPM, `MachineGuid`, or your ISP IP (run Mullvad on Windows for that).

**Breaks:** Store, OneDrive, Xbox Live, “Sign in with Microsoft.”

Revert hosts: `Apply-X47Anonymity.ps1 -Revert`

## Looks

`Apply-X47Theme.bat` — `x47` | `xp` | `xp-remastered` | `vista` | `win10` | `win11`

Open-Shell skins are GPL. No Microsoft theme files.

See `START-HERE.txt` and `docs/x47-windows-guide.html`.
