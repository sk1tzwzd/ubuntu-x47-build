# Shared helpers for the X47 Windows kit. Dot-source from other scripts.
$script:X47Root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $script:X47Root) { $script:X47Root = 'C:\X47' }

$script:X47LogDir = Join-Path $script:X47Root 'logs'
$script:X47LogFile = Join-Path $script:X47LogDir ("x47-windows-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

function X47-EnsureLog {
    if (-not (Test-Path $script:X47LogDir)) {
        New-Item -ItemType Directory -Path $script:X47LogDir -Force | Out-Null
    }
}

function X47-Log {
    param([string]$Message, [string]$Level = 'INFO')
    X47-EnsureLog
    $line = "{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $Level, $Message
    Add-Content -Path $script:X47LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN' { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'OK' { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function X47-RequireAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prin = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'X47 Windows kit must run in an elevated (Administrator) PowerShell.'
    }
}

function X47-SetReg {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [Microsoft.Win32.RegistryValueKind]$Type = [Microsoft.Win32.RegistryValueKind]::DWord
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function X47-DisableService {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        X47-Log "service $Name not present — skip"
        return
    }
    try {
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        X47-Log "disabled service $Name" 'OK'
    } catch {
        X47-Log "could not disable ${Name}: $($_.Exception.Message)" 'WARN'
    }
}
