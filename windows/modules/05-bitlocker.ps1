# Enable BitLocker on C: with TPM+PIN and export the 48-digit recovery key.
# Dual-boot safe: PIN is required at Windows pre-boot; Ubuntu LUKS is separate.
param(
    [string]$KitRoot = $(if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { 'C:\X47' }),
    [switch]$SkipEncrypt
)

. (Join-Path $KitRoot 'lib\X47Common.ps1')
$script:X47Root = $KitRoot
X47-RequireAdmin
X47-Log '=== 05 BitLocker ==='

function Get-X47RecoveryPassword {
    $vol = Get-BitLockerVolume -MountPoint 'C:'
    $prot = $vol.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' } | Select-Object -First 1
    if ($prot) { return $prot }
    return $null
}

function Save-X47RecoveryKey {
    param([string]$Password)
    if (-not $Password) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $local = Join-Path $KitRoot 'BitLocker-Recovery.txt'
    $body = @"
X47 BitLocker recovery key
Volume: C:
Saved: $stamp
Host: $env:COMPUTERNAME

$Password

Keep this file on a USB that is NOT the Windows disk.
After you boot Ubuntu, import it with:
  x47-windows-import-key /path/to/BitLocker-Recovery.txt
"@
    $body | Set-Content -Path $local -Encoding UTF8
    X47-Log "recovery key written to $local" 'OK'

    $usb = Get-Volume | Where-Object {
        $_.DriveType -eq 'Removable' -and $_.DriveLetter
    } | Select-Object -First 1
    if ($usb) {
        $usbPath = '{0}:\X47-BitLocker-Recovery-{1}.txt' -f $usb.DriveLetter, $stamp
        Copy-Item $local $usbPath -Force
        X47-Log "recovery key copied to $usbPath" 'OK'
    } else {
        X47-Log 'no USB volume found — plug one in and re-run:  .\\modules\\05-bitlocker.ps1 -SkipEncrypt' 'WARN'
        Write-Host ''
        Write-Host 'COPY THIS KEY NOW (photo + paper). After encryption Linux cannot read C:\X47 without it.' -ForegroundColor Yellow
        Write-Host $Password -ForegroundColor Cyan
        Write-Host ''
    }
    return $local
}

# Allow a startup PIN (otherwise manage-bde / Enable-BitLocker refuses TPM+PIN).
$fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
X47-SetReg -Path $fve -Name UseAdvancedStartup -Value 1
X47-SetReg -Path $fve -Name EnableBDEWithNoTPM -Value 0
X47-SetReg -Path $fve -Name UseTPM -Value 2          # allow
X47-SetReg -Path $fve -Name UseTPMPIN -Value 1       # require PIN
X47-SetReg -Path $fve -Name UseTPMKey -Value 2
X47-SetReg -Path $fve -Name UseTPMKeyPIN -Value 2
X47-SetReg -Path $fve -Name MinimumPIN -Value 6
X47-SetReg -Path $fve -Name EncryptionMethodWithXtsOs -Value 7  # XTS-AES 256
X47-Log 'FVE policy set (TPM+PIN required, XTS-AES 256)'

$vol = Get-BitLockerVolume -MountPoint 'C:'
X47-Log ("BitLocker status={0} percent={1}" -f $vol.ProtectionStatus, $vol.EncryptionPercentage)

if ($SkipEncrypt) {
    $existing = Get-X47RecoveryPassword
    if ($existing) {
        Save-X47RecoveryKey $existing.RecoveryPassword | Out-Null
    } else {
        X47-Log 'SkipEncrypt set and no recovery protector yet' 'WARN'
    }
    return
}

if ($vol.VolumeStatus -ne 'FullyDecrypted' -and $vol.ProtectionStatus -eq 'On') {
    X47-Log 'BitLocker already on — exporting recovery key only'
    $existing = Get-X47RecoveryPassword
    if (-not $existing) {
        Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector | Out-Null
        $existing = Get-X47RecoveryPassword
    }
    if ($existing) { Save-X47RecoveryKey $existing.RecoveryPassword | Out-Null }
    return
}

Write-Host ''
Write-Host 'BitLocker will encrypt the whole C: volume (XTS-AES 256).' -ForegroundColor Yellow
Write-Host 'Stay on AC power. Do not force-reboot until encryption finishes.' -ForegroundColor Yellow
Write-Host 'Ubuntu LUKS is separate — this PIN only unlocks Windows.' -ForegroundColor Yellow
Write-Host ''

$pin1 = Read-Host -AsSecureString 'Choose a BitLocker pre-boot PIN (6+ digits)'
$pin2 = Read-Host -AsSecureString 'Re-enter the PIN'
$bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pin1)
$bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pin2)
try {
    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
    if ($p1 -ne $p2) { throw 'PINs did not match' }
    if ($p1.Length -lt 6 -or $p1 -notmatch '^\d+$') { throw 'PIN must be at least 6 digits' }
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
}

# Recovery protector first so we can save the key before the long encrypt.
if (-not (Get-X47RecoveryPassword)) {
    Add-BitLockerKeyProtector -MountPoint 'C:' -RecoveryPasswordProtector | Out-Null
}
$rec = Get-X47RecoveryPassword
if (-not $rec) { throw 'failed to create a BitLocker recovery password protector' }
Save-X47RecoveryKey $rec.RecoveryPassword | Out-Null

Write-Host 'Plug in a USB if you have not already, then press Enter to start encryption.'
[void](Read-Host)

# Re-copy to USB now that the user had a chance to plug one in.
Save-X47RecoveryKey $rec.RecoveryPassword | Out-Null

try {
    Enable-BitLocker -MountPoint 'C:' `
        -EncryptionMethod XtsAes256 `
        -UsedSpaceOnly:$false `
        -TpmAndPinProtector `
        -Pin $pin1 `
        -SkipHardwareTest
    X47-Log 'Enable-BitLocker started (TPM+PIN, XTS-AES 256, full volume)' 'OK'
} catch {
    X47-Log "Enable-BitLocker failed: $($_.Exception.Message)" 'ERROR'
    X47-Log 'You can finish in Settings → Privacy & security → Device encryption / BitLocker, then re-run this module with -SkipEncrypt' 'WARN'
    throw
}

Write-Host ''
Write-Host 'Encryption is running in the background. Check progress with:' -ForegroundColor Green
Write-Host '  manage-bde -status C:'
Write-Host 'After it reaches 100% and Protection is On, reboot to Ubuntu and run:'
Write-Host '  x47-windows-import-key /media/$USER/<USB>/X47-BitLocker-Recovery-*.txt'
Write-Host ''
