# Runs the instant ssh exits, from start-tunnel.bat.
if (Test-Path -LiteralPath "$PSScriptRoot\tunnel.userstop") { exit 0 }
. "$PSScriptRoot\5s-common.ps1"
Stop-ClaudeApp | Out-Null
