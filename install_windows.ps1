param(
    [string]$InstallDir = "C:\kev_monitor",
    [switch]$Uninstall
)

$ServiceName = "kev_monitor"
$DisplayName  = "CISA KEV Catalog Monitor"
$Description  = "Monitors the CISA KEV catalog for changes and sends desktop notifications."
$BinaryUrl    = "https://github.com/quantumcore/kev_monitor/releases/download/V.1/kev_monitor-windows-x86_64.exe"

# ── Helpers ─────────────────────────────────────────────────────────────

function Write-Step { param($m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[✓] $m" -ForegroundColor Green }
function Write-Fail { param($m) { Write-Host "[✗] $m" -ForegroundColor Red; exit 1 } }

function Ensure-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail "Run PowerShell as Administrator"
    }
}

function Download {
    param($Url, $Out)
    Write-Step "Downloading $(Split-Path $Out -Leaf)"
    Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
}

function Remove-Service {
    sc.exe stop $ServiceName >$null 2>&1
    sc.exe delete $ServiceName >$null 2>&1
}

# ── Uninstall ───────────────────────────────────────────────────────────

if ($Uninstall) {
    Ensure-Admin

    Write-Step "Removing service..."
    Remove-Service

    $choice = Read-Host "Remove $InstallDir ? [y/N]"
    if ($choice -match '^[Yy]$') {
        Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
        Write-Ok "Removed install directory"
    }

    Write-Ok "Uninstalled"
    exit 0
}

# ── Install ─────────────────────────────────────────────────────────────

Ensure-Admin

Write-Ok "Installing kev_monitor (Windows)"

# Create directories
Write-Step "Creating directory: $InstallDir"
New-Item -ItemType Directory -Force -Path "$InstallDir\reports" | Out-Null

# Download binary
$binaryPath = "$InstallDir\kev_monitor.exe"
Download $BinaryUrl $binaryPath
Write-Ok "Binary installed"

# Default config (always overwrite for simplicity)
$configPath = "$InstallDir\settings.ini"

Write-Step "Writing settings.ini"
@"
[CONFIG]
CHECK = 1
DB_PATH = kev_monitor.db
REPORT_DIR = reports
KEV_URL = https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
"@ | Set-Content -Encoding UTF8 $configPath

# Remove existing service if any
Remove-Service

# Create service
Write-Step "Creating Windows service..."

sc.exe create $ServiceName `
    binPath= "`"$binaryPath`"" `
    start= auto `
    DisplayName= "$DisplayName" | Out-Null

sc.exe description $ServiceName "$Description" | Out-Null

# Ensure correct working directory (critical for relative paths)
$reg = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
Set-ItemProperty -Path $reg -Name "ImagePath" `
    -Value "`"%SystemRoot%\System32\cmd.exe`" /c cd /d `"$InstallDir`" && `"$binaryPath`""

# Restart policy
sc.exe failure $ServiceName reset= 86400 actions= restart/30000/restart/30000/restart/30000 | Out-Null

# Start service
Write-Step "Starting service..."
Start-Service -Name $ServiceName

Start-Sleep 2

$status = Get-Service $ServiceName
if ($status.Status -ne "Running") {
    Write-Fail "Service failed to start"
}

Write-Ok "kev_monitor installed and running"

Write-Host ""
Write-Host "Install Dir : $InstallDir"
Write-Host "Config      : $configPath"
Write-Host "Reports     : $InstallDir\reports"
Write-Host "Logs        : Event Viewer / Windows Logs"
Write-Host ""
Write-Host "Uninstall   : .\install.ps1 -Uninstall"
