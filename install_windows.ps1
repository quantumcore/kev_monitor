

param(
    [string]$InstallDir = "C:\kev_monitor",
    [switch]$Uninstall
)

$ServiceName  = "kev_monitor"
$DisplayName  = "CISA KEV Catalog Monitor"
$Description  = "Monitors the CISA KEV catalog for changes and sends desktop notifications."
$Version      = "V.1"
$BinaryUrl    = "https://github.com/quantumcore/kev_monitor/releases/download/V.1/kev_monitor-windows-x86_64.exe"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step { param($msg) Write-Host "[*] $msg" -ForegroundColor Cyan  }
function Write-Ok   { param($msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[✗] $msg" -ForegroundColor Red; exit 1 }

function Ensure-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Fail "Please run this script as Administrator."
    }
}

function Download-File {
    param([string]$Url, [string]$Dest)
    Write-Step "Downloading $(Split-Path $Dest -Leaf)..."
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing `
            -Headers @{ "User-Agent" = "kev_monitor-installer" }
    } catch {
        Write-Fail "Download failed: $_"
    }
}

function Remove-Service-If-Exists {
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) { return }

    Write-Step "Stopping existing service..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Step "Deleting existing service..."
    sc.exe delete $ServiceName | Out-Null
    # Wait for SCM to release the handle
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

if ($Uninstall) {
    Ensure-Admin

    Write-Step "Stopping service '$ServiceName'..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Step "Deleting service '$ServiceName'..."
    sc.exe delete $ServiceName
    Write-Ok "Service removed."

    $choice = Read-Host "Remove install directory '$InstallDir'? [y/N]"
    if ($choice -match '^[Yy]$') {
        Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
        Write-Ok "Install directory removed."
    }
    exit 0
}

# ── Install ───────────────────────────────────────────────────────────────────

Ensure-Admin

# 1. Release info
$version   = $Version
$binaryUrl = $BinaryUrl
$configUrl = $null
Write-Ok "Release: $version"

# 3. Create install directory
Write-Step "Creating install directory: $InstallDir"
New-Item -ItemType Directory -Force -Path "$InstallDir\reports" | Out-Null

# 4. Download binary
$binaryDest = "$InstallDir\kev_monitor.exe"
Download-File $binaryUrl $binaryDest
Write-Ok "Binary saved to $binaryDest"

# 5. Config — download from release, keep existing, or write built-in default
$configDest = "$InstallDir\settings.ini"
if (Test-Path $configDest) {
    Write-Step "Existing settings.ini retained (not overwritten)."
} elseif ($configUrl) {
    Download-File $configUrl $configDest
    Write-Ok "Default settings.ini downloaded."
} else {
    Write-Step "No settings.ini in release — writing built-in default..."
    @"
[CONFIG]
; Days between KEV catalog checks
CHECK = 1

; SQLite database path (relative to install dir)
DB_PATH = kev_monitor.db

; Directory where Markdown reports are written
REPORT_DIR = reports

; CISA KEV feed URL
KEV_URL = https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json
"@ | Set-Content -Encoding UTF8 $configDest
    Write-Ok "Default settings.ini written."
}

# 6. Remove any pre-existing service
Remove-Service-If-Exists

# 7. Register as a native Windows service via sc.exe
#    The binary runs its own sleep loop, so it is TYPE=own / START=auto.
Write-Step "Registering Windows service '$ServiceName' (version $version)..."

$binPath = "`"$binaryDest`""   # quoted in case InstallDir has spaces

sc.exe create $ServiceName `
    binPath= $binPath `
    DisplayName= $DisplayName `
    start= auto | Out-Null

if ($LASTEXITCODE -ne 0) { Write-Fail "sc.exe create failed (exit $LASTEXITCODE)." }

sc.exe description $ServiceName "$Description Version: $version" | Out-Null

# Set working directory via registry so the binary resolves settings.ini correctly
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
Set-ItemProperty -Path $regPath -Name "AppDirectory" -Value $InstallDir -ErrorAction SilentlyContinue

# Configure failure recovery: restart after 30 s, up to 3 times; reset counter after 1 day
sc.exe failure $ServiceName reset= 86400 actions= restart/30000/restart/30000/restart/30000 | Out-Null

# 8. Wrap the binary in a scheduled-task trampoline so it inherits a proper
#    working directory (sc.exe doesn't support AppDirectory natively).
#    We set the ImagePath to cmd /c "cd <dir> && kev_monitor.exe" instead.
$cmdPath = "%SystemRoot%\System32\cmd.exe"
$args    = "/c `"cd /d `"$InstallDir`" && `"$binaryDest`"`""
Set-ItemProperty -Path $regPath -Name "ImagePath" `
    -Value "$cmdPath $args" -Type ExpandString

Write-Ok "Service registered."

# 9. Start the service
Write-Step "Starting service..."
try {
    Start-Service -Name $ServiceName -ErrorAction Stop
} catch {
    Write-Fail "Service failed to start: $_"
}

# Verify
$svc = Get-Service -Name $ServiceName
if ($svc.Status -ne "Running") {
    Write-Fail "Service registered but is not running (status: $($svc.Status)). Check Windows Event Log."
}

Write-Host ""
Write-Ok "kev_monitor $version installed and running."
Write-Host "    Config:    $configDest"
Write-Host "    Reports:   $InstallDir\reports\"
Write-Host "    Event log: Get-EventLog -LogName Application -Source kev_monitor"
Write-Host ""
Write-Host "    To uninstall:  .\install_windows.ps1 -Uninstall"
