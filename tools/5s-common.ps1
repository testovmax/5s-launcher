# 5s-common.ps1 - shared settings and logic for 5S Launcher.
# Dot-source it:  . "$PSScriptRoot\tools\5s-common.ps1"
#
# Servers live in tools\connections.json (gitignored). The first launch
# imports tools\tunnel.local.cmd once, if the json file is not there yet.
# tools\tunnel.active.cmd is generated from the selected server for start-tunnel.bat.

$BaseDir     = Split-Path -Parent $PSScriptRoot
$ToolsDir    = $PSScriptRoot
$TunnelBat   = "$ToolsDir\start-tunnel.bat"
$TunnelCfg   = "$ToolsDir\tunnel.local.cmd"
$ActiveCmd   = "$ToolsDir\tunnel.active.cmd"
$ConfigFile  = "$ToolsDir\connections.json"
$TunnelLog   = "$ToolsDir\tunnel.log"
$TunnelPid   = "$ToolsDir\tunnel.pid"
$TunnelUserStop = "$ToolsDir\tunnel.userstop"
$VlessFile   = "$ToolsDir\vless.link"
$VlessScript = "$ToolsDir\start-vless.ps1"
$GostExe     = "$ToolsDir\gost.exe"
$XrayExe     = "$ToolsDir\xray.exe"
$VlessJson   = "$ToolsDir\vless.json"
$GostLog     = "$ToolsDir\gost.log"
$IconFile    = "$ToolsDir\icon-1a.ico"
$LogoFile    = "$ToolsDir\logo.png"
$TunnelPort  = 5555
$BridgePort  = 8118
$Socks5      = "socks5://127.0.0.1:$TunnelPort"

# Site list for smart routing. Re-read every time the proxy is switched on.
$BypassFile = "$ToolsDir\bypass.txt"
$DefaultBypass = @(
    "*.ru"; "*.su"; "*.by"; "*.xn--p1ai"
    "vk.com"; "*.vk.com"; "*.userapi.com"
    "*.yandex.net"; "*.yastatic.net"; "*.yandex.com"
)

# Local network and the machine itself always skip the proxy, so the
# bridge cannot loop back into itself.
$InternalBypass = @("172.20.*"; "localhost"; "127.0.0.1"; "<local>")

function Get-DirectSourceIp {
    # Skip the Clash/VPN tunnel so SSH and VLESS dial the server directly.
    $skip = 'clash|meta|tun|wsl|radmin|vpn|tap|loopback|vethernet|bluetooth|teredo'
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object {
            $_.NextHop -and $_.NextHop -ne '0.0.0.0' -and $_.InterfaceAlias -notmatch $skip
        } |
        Sort-Object RouteMetric, InterfaceMetric |
        Select-Object -First 1
    if (-not $route) { return $null }
    $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notlike '198.18.*' -and $_.IPAddress -notlike '198.19.*' } |
        Select-Object -First 1
    if ($ip) { return [string]$ip.IPAddress }
    $null
}

function Read-LogTail([string]$Path, [int]$Lines) {
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return "" }
    $text = $null
    $utf8 = New-Object System.Text.UTF8Encoding $false, $true
    try { $text = $utf8.GetString($bytes) } catch { $text = $null }
    if (-not $text) {
        $text = [System.Text.Encoding]::GetEncoding(866).GetString($bytes)
    }
    $rows = @($text -split "`r?`n" | Where-Object { $_.Trim() })
    if ($rows.Count -eq 0) { return "" }
    $take = $rows | Select-Object -Last $Lines
    ($take -join " | ").Trim()
}

function Test-Listen([int]$Port) {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    foreach ($ep in $listeners) {
        if ($ep.Port -eq $Port) { return $true }
    }
    $false
}

function Get-Bypass {
    if (Test-Path -LiteralPath $BypassFile) {
        $masks = Get-Content -LiteralPath $BypassFile -Encoding UTF8 |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ -and -not $_.StartsWith("#") }
        if ($masks) { return @($masks) }
    }
    $DefaultBypass
}

function New-ConnObject([string]$Id, [string]$Name, [string]$Target, [string]$Identity, [string]$Protocol = "ssh", [string]$Link = "") {
    $proto = if ($Protocol -eq "vless") { "vless" } else { "ssh" }
    [pscustomobject]@{
        id       = $Id
        name     = $Name
        protocol = $proto
        target   = $Target
        identity = $(if ($Identity) { $Identity } else { "" })
        link     = $(if ($Link) { $Link } else { "" })
    }
}

function Get-VlessEndpoint([string]$Link) {
    $u = $Link.Trim()
    if ($u -match '^vless://[^@\s]+@([^:?/#\s]+):(\d+)') { return "$($Matches[1]):$($Matches[2])" }
    $null
}

function Get-VlessDialLink([string]$Link) {
    $u = $Link.Trim()
    $hash = $u.IndexOf("#")
    if ($hash -ge 0) { $u = $u.Substring(0, $hash) }
    if ($u -notmatch '^vless://') { return $null }
    $u
}

# Always a new List. Write-Output -NoEnumerate keeps a 1-item list from
# unrolling into a single object — PowerShell += on those objects merges fields.
function ConvertTo-ConnList($Connections) {
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Connections) {
        foreach ($c in $Connections) {
            if (-not $c -or -not $c.id) { continue }
            if ([string]$c.id -match '\s') { continue }
            $items.Add((New-ConnObject ([string]$c.id) ([string]$c.name) ([string]$c.target) ([string]$c.identity) ([string]$c.protocol) ([string]$c.link)))
        }
    }
    Write-Output -NoEnumerate $items
}

function Find-Connection($Connections, [string]$Id) {
    if (-not $Id) { return $null }
    foreach ($c in (ConvertTo-ConnList $Connections)) {
        if ($c.id -eq $Id) { return $c }
    }
    $null
}

function Test-HasConnection($Connections, [string]$Id) {
    $null -ne (Find-Connection $Connections $Id)
}

function ConvertTo-JsonArray($Items) {
    $list = ConvertTo-ConnList $Items
    if ($list.Count -eq 0) { return "[]" }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $list) { $parts.Add(($item | ConvertTo-Json -Depth 4 -Compress)) }
    "[" + ($parts -join ",") + "]"
}

function Parse-SshTargetValue([string]$Value) {
    $v = $Value.Trim().Trim('"')
    if (-not $v) { return $null }
    $identity = ""
    if ($v -match '-i\s+"([^"]+)"') {
        $identity = $Matches[1]
        $v = ($v -replace '-i\s+"[^"]+"', "").Trim()
    } elseif ($v -match '-i\s+(\S+)') {
        $identity = $Matches[1]
        $v = ($v -replace '-i\s+\S+', "").Trim()
    }
    $target = @($v -split '\s+' | Where-Object { $_ -and $_ -notlike '-*' } | Select-Object -Last 1)
    if (-not $target -or $target[0] -notmatch '@') { return $null }
    [pscustomobject]@{ target = [string]$target[0]; identity = $identity }
}

function Import-LegacyConnections {
    if (-not (Test-Path -LiteralPath $TunnelCfg)) {
        return [pscustomobject]@{ activeId = $null; connections = @() }
    }
    $lines = @(Get-Content -LiteralPath $TunnelCfg -Encoding UTF8)
    $list = New-Object System.Collections.Generic.List[object]
    $pendingName = $null
    $activeId = $null
    foreach ($line in $lines) {
        $t = $line.Trim()
        if ($t -match '^rem\s+New server:\s*([^,(]+)') {
            $pendingName = $Matches[1].Trim()
            continue
        }
        if ($t -match '^rem\s+Old server\b') {
            $pendingName = "Старый сервер"
            continue
        }
        $commented = $t -match '^rem\s+'
        $body = if ($commented) { ($t -replace '^rem\s+', '').Trim() } else { $t }
        if ($body -notmatch '^set\s+SSH_TARGET\s*=\s*(.*)$') { continue }
        $parsed = Parse-SshTargetValue $Matches[1]
        if (-not $parsed) { $pendingName = $null; continue }
        $id = [guid]::NewGuid().ToString("n").Substring(0, 8)
        $name = $pendingName
        if (-not $name) { $name = ($parsed.target -split '@', 2)[1] }
        $list.Add((New-ConnObject $id $name $parsed.target $parsed.identity))
        if (-not $commented) { $activeId = $id }
        $pendingName = $null
    }
    [pscustomobject]@{ activeId = $activeId; connections = $list }
}

function Write-ConfigFile($Cfg) {
    $conns = ConvertTo-ConnList $Cfg.connections
    $active = [string]$Cfg.activeId
    if ($active -and -not (Test-HasConnection $conns $active)) { $active = "" }
    if (-not $active -and $conns.Count -gt 0) { $active = [string]$conns[0].id }
    $routing = [bool]$Cfg.routing
    $idJson = if ($active) { $active | ConvertTo-Json -Compress } else { "null" }
    $json = @"
{
  "routing": $($routing.ToString().ToLower()),
  "activeId": $idJson,
  "connections": $(ConvertTo-JsonArray $conns)
}
"@
    $utf8 = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($ConfigFile, $json.Replace("`n", "`r`n"), $utf8)
    [pscustomobject]@{ routing = $routing; activeId = $(if ($active) { $active } else { $null }); connections = (ConvertTo-ConnList $conns) }
}

function Write-ActiveTunnelCmd($Cfg) {
    $active = $null
    if ($Cfg.activeId) {
        $active = Find-Connection $Cfg.connections ([string]$Cfg.activeId)
    }
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if (-not $active) {
        $text = "@echo off`r`nset SSH_TARGET=`r`nset SSH_IDENTITY=`r`nset SOCKS_PORT=$TunnelPort`r`n"
        [System.IO.File]::WriteAllText($ActiveCmd, $text, $utf8)
        return
    }
    $text = @"
@echo off
set SSH_TARGET=$($active.target)
set SSH_IDENTITY=$($active.identity)
set SSH_BIND=$(Get-DirectSourceIp)
set SOCKS_PORT=$TunnelPort
"@
    [System.IO.File]::WriteAllText($ActiveCmd, $text.Replace("`n", "`r`n") + "`r`n", $utf8)
}

function Read-LauncherConfig {
    if (-not (Test-Path -LiteralPath $ConfigFile)) { return $null }
    $raw = [System.IO.File]::ReadAllText($ConfigFile)
    if (-not $raw.Trim()) { return $null }
    $cfg = $raw | ConvertFrom-Json
    $conns = ConvertTo-ConnList $cfg.connections
    $active = [string]$cfg.activeId
    if ($active -and -not (Test-HasConnection $conns $active)) { $active = "" }
    if (-not $active -and $conns.Count -gt 0) { $active = [string]$conns[0].id }
    [pscustomobject]@{
        routing     = [bool]$cfg.routing
        activeId    = $(if ($active) { $active } else { $null })
        connections = $conns
    }
}

function Get-LauncherConfig {
    $cfg = $null
    try { $cfg = Read-LauncherConfig } catch {
        $bak = "$ConfigFile.bak"
        if (Test-Path -LiteralPath $ConfigFile) {
            Move-Item -LiteralPath $ConfigFile -Destination $bak -Force
        }
        $cfg = $null
    }
    if ($cfg) { return $cfg }
    $legacy = Import-LegacyConnections
    $fresh = [pscustomobject]@{
        routing     = $true
        activeId    = $legacy.activeId
        connections = $legacy.connections
    }
    $saved = Write-ConfigFile $fresh
    Write-ActiveTunnelCmd $saved
    $saved
}

function Save-LauncherConfig($Cfg) {
    $saved = Write-ConfigFile $Cfg
    Write-ActiveTunnelCmd $saved
    $saved
}

function Get-ActiveConnection {
    $cfg = Get-LauncherConfig
    if (-not $cfg.activeId) { return $null }
    Find-Connection $cfg.connections ([string]$cfg.activeId)
}

function Set-ActiveConnection([string]$Id) {
    $cfg = Get-LauncherConfig
    $found = Find-Connection $cfg.connections $Id
    if (-not $found) { return "Подключение не найдено." }
    Save-LauncherConfig ([pscustomobject]@{
        routing     = [bool]$cfg.routing
        activeId    = $Id
        connections = $cfg.connections
    }) | Out-Null
    "Активный сервер: $($found.name)"
}

function Set-RoutingEnabled([bool]$On) {
    $cfg = Get-LauncherConfig
    Save-LauncherConfig ([pscustomobject]@{
        routing     = $On
        activeId    = $cfg.activeId
        connections = $cfg.connections
    }) | Out-Null
}

function Test-ConnectionFields([string]$Name, [string]$Target, [string]$Identity, [string]$Protocol = "ssh", [string]$Link = "") {
    if ([string]::IsNullOrWhiteSpace($Name)) { return "Введите имя подключения." }
    if ($Name -match '[&|<>^%"]') { return "В имени есть недопустимый символ." }
    if ($Protocol -eq "vless") {
        if ($Link.Trim() -notmatch '^vless://') { return "Вставьте ссылку, которая начинается с vless://" }
        if (-not (Get-VlessEndpoint $Link)) { return "В ссылке не найден адрес вида host:port." }
        return $null
    }
    if ($Target -notmatch '^[^@\s]+@[^@\s]+$') { return "Сервер нужен в виде login@host." }
    if ($Target -match '[&|<>^%"]') { return "В адресе есть недопустимый символ." }
    if ($Identity) {
        if ($Identity -match '[&|<>^%"]') { return "В пути к ключу есть недопустимый символ." }
        if (-not (Test-Path -LiteralPath $Identity)) { return "Файл ключа не найден." }
    }
    $null
}

function Add-Connection([string]$Name, [string]$Target, [string]$Identity, [string]$Protocol = "ssh", [string]$Link = "") {
    $err = Test-ConnectionFields $Name $Target $Identity $Protocol $Link
    if ($err) { return $err }
    $cfg = Get-LauncherConfig
    $list = ConvertTo-ConnList $cfg.connections
    $shown = if ($Protocol -eq "vless") { Get-VlessEndpoint $Link } else { $Target.Trim() }
    $item = New-ConnObject ([guid]::NewGuid().ToString("n").Substring(0, 8)) $Name.Trim() $shown $(if ($Identity) { $Identity.Trim() } else { "" }) $Protocol $Link.Trim()
    $list.Add($item)
    $active = if ($cfg.activeId) { [string]$cfg.activeId } else { $item.id }
    Save-LauncherConfig ([pscustomobject]@{
        routing     = [bool]$cfg.routing
        activeId    = $active
        connections = $list
    }) | Out-Null
    $item
}

function Update-Connection([string]$Id, [string]$Name, [string]$Target, [string]$Identity, [string]$Protocol = "ssh", [string]$Link = "") {
    $err = Test-ConnectionFields $Name $Target $Identity $Protocol $Link
    if ($err) { return $err }
    $cfg = Get-LauncherConfig
    $list = New-Object System.Collections.Generic.List[object]
    $found = $false
    $shown = if ($Protocol -eq "vless") { Get-VlessEndpoint $Link } else { $Target.Trim() }
    foreach ($c in (ConvertTo-ConnList $cfg.connections)) {
        if ($c.id -eq $Id) {
            $found = $true
            $list.Add((New-ConnObject $c.id $Name.Trim() $shown $(if ($Identity) { $Identity.Trim() } else { "" }) $Protocol $Link.Trim()))
        } else { $list.Add($c) }
    }
    if (-not $found) { return "Подключение не найдено." }
    Save-LauncherConfig ([pscustomobject]@{
        routing     = [bool]$cfg.routing
        activeId    = $cfg.activeId
        connections = $list
    }) | Out-Null
    "Подключение сохранено."
}

function Remove-Connection([string]$Id) {
    $cfg = Get-LauncherConfig
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($c in (ConvertTo-ConnList $cfg.connections)) {
        if ($c.id -ne $Id) { $list.Add($c) }
    }
    $active = [string]$cfg.activeId
    if ($active -eq $Id) {
        $active = if ($list.Count -gt 0) { [string]$list[0].id } else { "" }
    }
    Save-LauncherConfig ([pscustomobject]@{
        routing     = [bool]$cfg.routing
        activeId    = $(if ($active) { $active } else { $null })
        connections = $list
    }) | Out-Null
    "Подключение удалено."
}

function Tunnel-Up {
    if (-not (Test-Listen $TunnelPort)) { return $false }
    [bool](@(Get-Process -Name ssh,gost,xray -ErrorAction SilentlyContinue))
}
function Gost-Up {
    (Test-Listen $BridgePort) -and [bool](Get-Process -Name gost -ErrorAction SilentlyContinue)
}
function Proxy-On {
    $reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    ($reg.ProxyEnable -eq 1) -and ($reg.ProxyServer -eq "127.0.0.1:$BridgePort")
}
function ProxyPair-On { (Gost-Up) -and (Proxy-On) }

function Get-ListenerProcessId([int]$Port) {
    $needle = ':' + $Port + ' '
    foreach ($line in @(netstat.exe -ano -p tcp)) {
        if ($line -notlike "*$needle*") { continue }
        if ($line -notmatch 'LISTENING\s+(\d+)\s*$') { continue }
        return [int]$Matches[1]
    }
    $null
}

function Set-SystemProxy([bool]$On, [bool]$Routing) {
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($On) {
        $masks = @($InternalBypass)
        if ($Routing) { $masks = @(@(Get-Bypass) + @($InternalBypass)) }
        $unique = [System.Collections.Generic.List[string]]::new()
        foreach ($m in $masks) {
            if ($m -and -not $unique.Contains($m)) { $unique.Add($m) }
        }
        Set-ItemProperty $reg ProxyEnable 1
        Set-ItemProperty $reg ProxyServer "127.0.0.1:$BridgePort"
        Set-ItemProperty $reg ProxyOverride ($unique -join ";")
    } else {
        Set-ItemProperty $reg ProxyEnable 0
    }
    if (-not ("PInvoke.WinINet" -as [type])) {
        $sig = '[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
        Add-Type -MemberDefinition $sig -Name WinINet -Namespace PInvoke | Out-Null
    }
    [PInvoke.WinINet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [PInvoke.WinINet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Start-VlessTunnel($Conn) {
    if (-not (Test-Path -LiteralPath $XrayExe)) { return "Не найден tools\xray.exe. VLESS поднимает Xray, не gost." }
    if (-not (Test-Path -LiteralPath $VlessScript)) { return "Не найден start-vless.ps1." }
    $dial = Get-VlessDialLink $Conn.link
    if (-not $dial) { return "Ссылка vless:// неполная." }
    if (Tunnel-Up) { return "Туннель уже работает ($($Conn.name))." }
    if (Test-Listen $TunnelPort) { return "Порт $TunnelPort занят другим процессом." }
    Remove-Item -LiteralPath $TunnelUserStop -Force -ErrorAction SilentlyContinue
    $global:FiveSUserStoppedTunnel = $false
    Stop-TunnelLoop
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($VlessFile, $dial, $utf8)
    Remove-Item -LiteralPath $TunnelLog -ErrorAction SilentlyContinue
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$VlessScript`""
    $psi.WorkingDirectory = $ToolsDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    Set-Content -LiteralPath $TunnelPid -Value $proc.Id -Encoding ascii
    Start-Sleep -Seconds 2
    if (Tunnel-Up) { return "Туннель VLESS к $($Conn.name) поднялся." }
    $tail = ""
    if (Test-Path -LiteralPath $TunnelLog) {
        $tail = Read-LogTail $TunnelLog 2
    }
    if ($tail) { return "Туннель VLESS не поднялся. $tail" }
    "Туннель VLESS не поднялся. Подробности в tools\tunnel.log."
}

function Start-Tunnel {
    $conn = Get-ActiveConnection
    if (-not $conn) { return "Нет сервера. Добавьте подключение в пульте." }
    if ($conn.protocol -eq "vless") { return (Start-VlessTunnel $conn) }
    if (-not (Test-Path -LiteralPath $TunnelBat)) { return "Не найден $TunnelBat." }
    if ($conn.identity -and -not (Test-Path -LiteralPath $conn.identity)) {
        return "Ключ не найден: $($conn.identity)"
    }
    Remove-Item -LiteralPath $TunnelUserStop -Force -ErrorAction SilentlyContinue
    $global:FiveSUserStoppedTunnel = $false
    Write-ActiveTunnelCmd (Get-LauncherConfig)
    if (Tunnel-Up) { return "Туннель уже работает ($($conn.name))." }
    if (Test-Listen $TunnelPort) { return "Порт $TunnelPort занят другим процессом." }
    Stop-TunnelLoop
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $TunnelBat
    $psi.WorkingDirectory = $ToolsDir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.EnvironmentVariables["NO_PAUSE"] = "1"
    $proc = [System.Diagnostics.Process]::Start($psi)
    Set-Content -LiteralPath $TunnelPid -Value $proc.Id -Encoding ascii
    Start-Sleep -Seconds 3
    if (Tunnel-Up) { return "Туннель к $($conn.name) поднялся." }
    $tail = ""
    if (Test-Path -LiteralPath $TunnelLog) {
        $tail = Read-LogTail $TunnelLog 2
    }
    if ($tail) { return "Туннель не поднялся. $tail" }
    "Туннель не поднялся. Подробности в tools\tunnel.log."
}

function Stop-ClaudeApp {
    # Desktop app from the WindowsApps package. The claude.exe CLI keeps a
    # readable path outside that package and is not closed.
    # Packaged processes often hide ExecutablePath; a blank path on Claude.exe
    # or cowork-svc.exe is still the desktop app.
    $ids = New-Object System.Collections.Generic.List[int]
    Get-CimInstance Win32_Process -Filter "Name='Claude.exe' OR Name='cowork-svc.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $path = [string]$_.ExecutablePath
            $desktop = $path -like "*\WindowsApps\Claude_*\*"
            $hidden = -not $path
            $cli = $path -and -not $desktop
            if ($cli) { return }
            if ($desktop -or $hidden) { [void]$ids.Add([int]$_.ProcessId) }
        }
    if ($ids.Count -eq 0) { return $null }
    foreach ($procId in ($ids | Select-Object -Unique)) {
        & taskkill.exe /PID $procId /T /F 2>$null | Out-Null
    }
    "Туннель упал. Приложение Claude закрыто."
}

function Stop-TunnelLoop {
    if (-not (Test-Path -LiteralPath $TunnelPid)) { return }
    $raw = (Get-Content -LiteralPath $TunnelPid -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($raw -match '^\d+$') {
        & taskkill.exe /PID $raw /T /F 2>$null | Out-Null
    }
    Remove-Item -LiteralPath $TunnelPid -ErrorAction SilentlyContinue
}

function Stop-Tunnel {
    # User asked to stop. The bat and the watcher must not treat this as a crash.
    $global:FiveSUserStoppedTunnel = $true
    Set-Content -LiteralPath $TunnelUserStop -Value "1" -Encoding ascii
    Stop-TunnelLoop
    $listenPid = Get-ListenerProcessId $TunnelPort
    if ($listenPid) {
        $owner = Get-Process -Id $listenPid -ErrorAction SilentlyContinue
        if ($owner -and ($owner.ProcessName -eq "ssh" -or $owner.ProcessName -eq "gost" -or $owner.ProcessName -eq "xray")) {
            Stop-Process -Id $listenPid -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
    if (Tunnel-Up) { "Туннель ещё жив — проверьте процессы ssh вручную." } else { "Туннель остановлен." }
}

function Switch-Tunnel {
    $stopped = Stop-Tunnel
    $started = Start-Tunnel
    "$stopped $started"
}

function Start-Gost {
    if (-not (Test-Path -LiteralPath $GostExe)) { return "Не найден $GostExe." }
    if (Gost-Up) { return "Мост gost уже запущен." }
    if (Test-Listen $BridgePort) { return "Порт $BridgePort занят другим процессом." }
    Remove-Item -LiteralPath $GostLog -ErrorAction SilentlyContinue
    try {
        Start-Process -FilePath $GostExe -ArgumentList @("-L", "http://127.0.0.1:$BridgePort", "-F", $Socks5) `
            -WorkingDirectory $ToolsDir -WindowStyle Hidden -RedirectStandardError $GostLog
    } catch {
        return "Ошибка запуска gost: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 1
    if (Gost-Up) { return "Мост gost запущен (127.0.0.1:$BridgePort)." }
    $tail = ""
    if (Test-Path -LiteralPath $GostLog) {
        $tail = Read-LogTail $GostLog 3
    }
    if (-not $tail) { $tail = "лог пуст" }
    "gost не запустился ($tail)."
}

function Stop-Gost {
    $listenPid = Get-ListenerProcessId $BridgePort
    if ($listenPid) {
        $owner = Get-Process -Id $listenPid -ErrorAction SilentlyContinue
        if ($owner -and $owner.ProcessName -eq "gost") {
            Stop-Process -Id $listenPid -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds 400
    if (Gost-Up) { "Мост gost ещё работает." } else { "Мост gost остановлен." }
}

function Start-ProxyPair {
    param([bool]$Routing = $true)
    if (-not (Tunnel-Up)) { return "Сначала запустите туннель — без него прокси некуда вести." }
    $msgs = New-Object System.Collections.Generic.List[string]
    $bridge = Start-Gost
    if ($bridge -ne "Мост gost уже запущен.") { $msgs.Add($bridge) }
    if (-not (Gost-Up)) { return ($msgs -join " ") }
    Set-SystemProxy $true $Routing
    $mode = if ($Routing) { "исключения из списка включены" } else { "весь внешний трафик через прокси" }
    $msgs.Add("Прокси включён -> 127.0.0.1:${BridgePort} ($mode).")
    $msgs -join " "
}

function Stop-ProxyPair {
    Set-SystemProxy $false $false
    $bridge = Stop-Gost
    "Системный прокси выключен. $bridge"
}

function Apply-Routing {
    $cfg = Get-LauncherConfig
    if (-not (Proxy-On)) { return "Настройка сохранена. Применится при включении прокси." }
    Set-SystemProxy $true ([bool]$cfg.routing)
    if ($cfg.routing) { "Маршрутизация включена: сайты из списка идут напрямую." }
    else { "Маршрутизация выключена: внешние сайты идут через прокси." }
}
