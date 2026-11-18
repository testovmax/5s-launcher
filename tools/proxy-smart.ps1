# proxy-smart.ps1 - turn the proxy pair on or off from the command line.
# ON  starts the SSH tunnel if needed, then gost and the system proxy.
# OFF turns the system proxy off and stops gost. The tunnel stays up.
# Routing follows tools\connections.json (the checkbox in the launcher).
#
#   powershell -ExecutionPolicy Bypass -File tools\proxy-smart.ps1
#   powershell -ExecutionPolicy Bypass -File tools\proxy-smart.ps1 -Off

param([switch]$Off)

. "$PSScriptRoot\5s-common.ps1"

$ErrorActionPreference = "Stop"

if ($Off) {
    Write-Host (Stop-ProxyPair)
    exit 0
}

if (-not (Tunnel-Up)) {
    Write-Host (Start-Tunnel)
    if (-not (Tunnel-Up)) { exit 1 }
}

$cfg = Get-LauncherConfig
Write-Host (Start-ProxyPair -Routing ([bool]$cfg.routing))
if (-not (ProxyPair-On)) { exit 1 }
