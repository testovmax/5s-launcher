# proxy-smart.ps1 - turn the smart system proxy on/off from the command line,
# without opening the launcher or the widget.
# Russian sites go DIRECT, everything else goes via the corporate proxy.
#
# Turn ON :  powershell -ExecutionPolicy Bypass -File tools\proxy-smart.ps1
# Turn OFF:  powershell -ExecutionPolicy Bypass -File tools\proxy-smart.ps1 -Off

param([switch]$Off)

# Settings, the RU bypass list and start/stop helpers.
. "$PSScriptRoot\5s-common.ps1"

$ErrorActionPreference = "Stop"

if ($Off) {
    Set-SystemProxy $false
    Write-Host "[OK] System proxy OFF." -ForegroundColor Green
    exit 0
}

# 1. SSH tunnel
if (-not (Tunnel-Up)) {
    Write-Host "[i] SSH tunnel not running - starting it hidden..." -ForegroundColor Cyan
    Write-Host ("    " + (Start-Tunnel))
    if (-not (Tunnel-Up)) {
        Write-Host "[X] SSH tunnel (127.0.0.1:$TunnelPort) is not running." -ForegroundColor Red
        exit 1
    }
}

# 2. gost bridge
if (-not (Gost-Up)) {
    Write-Host "[i] Starting gost bridge on port $BridgePort..." -ForegroundColor Cyan
    Write-Host ("    " + (Start-Gost))
    if (-not (Gost-Up)) { exit 1 }
}

# 3. System proxy ON with the smart bypass list
Set-SystemProxy $true
Write-Host "[OK] Smart proxy ON: RU sites direct, the rest via 127.0.0.1:$BridgePort." -ForegroundColor Green
