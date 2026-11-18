# Local SOCKS on 127.0.0.1:5555 through Xray and a VLESS link.
$ErrorActionPreference = "Continue"
. "$PSScriptRoot\5s-common.ps1"

$linkFile = Join-Path $PSScriptRoot "vless.link"
$stopFile = Join-Path $PSScriptRoot "tunnel.userstop"
$log = Join-Path $PSScriptRoot "tunnel.log"
$xray = Join-Path $PSScriptRoot "xray.exe"
$json = Join-Path $PSScriptRoot "vless.json"

function ConvertTo-JsonString([string]$Value) {
    if ($null -eq $Value) { return '""' }
    $Value | ConvertTo-Json -Compress
}

function Write-XrayConfig([string]$Link) {
    $u = $Link.Trim()
    $hash = $u.IndexOf("#")
    if ($hash -ge 0) { $u = $u.Substring(0, $hash) }
    if ($u -notmatch '^vless://([^@]+)@([^:/?#]+):(\d+)(\?.*)?$') { throw "bad vless link" }
    $id = [Uri]::UnescapeDataString($Matches[1])
    $address = $Matches[2]
    $port = $Matches[3]
    $query = @{}
    if ($Matches[4]) {
        foreach ($part in ($Matches[4].TrimStart("?") -split "&")) {
            if ($part -match '^([^=]*)=(.*)$') {
                $query[[Uri]::UnescapeDataString($Matches[1])] = [Uri]::UnescapeDataString($Matches[2])
            }
        }
    }
    $network = if ($query["type"]) { $query["type"] } else { "tcp" }
    $security = if ($query["security"]) { $query["security"] } else { "none" }
    $encryption = if ($query["encryption"]) { $query["encryption"] } else { "none" }
    $flow = $query["flow"]
    $user = '"id": ' + (ConvertTo-JsonString $id) + ', "encryption": ' + (ConvertTo-JsonString $encryption)
    if ($flow) { $user += ', "flow": ' + (ConvertTo-JsonString $flow) }

    $extra = ""
    if ($security -eq "reality") {
        $sni = if ($query["sni"]) { $query["sni"] } else { $address }
        $fp = if ($query["fp"]) { $query["fp"] } else { "chrome" }
        $spx = if ($query["spx"]) { $query["spx"] } else { "/" }
        $extra = '"realitySettings": {"serverName": ' + (ConvertTo-JsonString $sni) +
            ', "fingerprint": ' + (ConvertTo-JsonString $fp) +
            ', "publicKey": ' + (ConvertTo-JsonString $query["pbk"]) +
            ', "shortId": ' + (ConvertTo-JsonString $query["sid"]) +
            ', "spiderX": ' + (ConvertTo-JsonString $spx) + '}'
    } elseif ($security -eq "tls") {
        $sni = if ($query["sni"]) { $query["sni"] } else { $address }
        $fp = if ($query["fp"]) { $query["fp"] } else { "chrome" }
        $extra = '"tlsSettings": {"serverName": ' + (ConvertTo-JsonString $sni) +
            ', "fingerprint": ' + (ConvertTo-JsonString $fp) + '}'
    }
    if ($network -eq "ws") {
        if ($extra) { $extra += ', ' }
        $extra += '"wsSettings": {"path": ' + (ConvertTo-JsonString $query["path"]) +
            ', "headers": {"Host": ' + (ConvertTo-JsonString $query["host"]) + '}}'
    } elseif ($network -eq "grpc") {
        if ($extra) { $extra += ', ' }
        $extra += '"grpcSettings": {"serviceName": ' + (ConvertTo-JsonString $query["serviceName"]) + '}'
    }
    $stream = '"network": ' + (ConvertTo-JsonString $network) + ', "security": ' + (ConvertTo-JsonString $security)
    if ($extra) { $stream += ', ' + $extra }

    $bind = Get-DirectSourceIp
    $bindPart = ''
    if ($bind) { $bindPart = '"sendThrough": ' + (ConvertTo-JsonString $bind) + ', ' }
    $text = '{' +
        '"log": {"loglevel": "warning"},' +
        '"inbounds": [{"listen": "127.0.0.1", "port": ' + $TunnelPort + ', "protocol": "socks", "settings": {"udp": true}}],' +
        '"outbounds": [{' + $bindPart + '"protocol": "vless", "settings": {"vnext": [{"address": ' + (ConvertTo-JsonString $address) +
        ', "port": ' + $port + ', "users": [{' + $user + '}]}]}, "streamSettings": {' + $stream + '}}]' +
        '}'
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($json, $text, $utf8)
}

while ($true) {
    if (Test-Path -LiteralPath $stopFile) { exit 0 }
    if (-not (Test-Path -LiteralPath $xray)) {
        Set-Content -LiteralPath $log -Value "xray.exe not found" -Encoding ascii
        exit 1
    }
    if (-not (Test-Path -LiteralPath $linkFile)) { exit 1 }
    $dial = (Get-Content -LiteralPath $linkFile -Raw -Encoding UTF8).Trim()
    if (-not $dial) { exit 1 }
    try { Write-XrayConfig $dial } catch {
        Set-Content -LiteralPath $log -Value $_.Exception.Message -Encoding utf8
        exit 1
    }
    $proc = Start-Process -FilePath $xray -ArgumentList @("run", "-c", $json) `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardError $log -PassThru
    $proc.WaitForExit()
    if (Test-Path -LiteralPath $stopFile) { exit 0 }
    Stop-ClaudeApp | Out-Null
    Start-Sleep -Seconds 5
}
