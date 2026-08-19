# 5s-common.ps1 - shared settings and logic for 5S Launcher and 5S Widget.
# Dot-source it:  . "$PSScriptRoot\tools\5s-common.ps1"
# Everything that both UIs need lives here, so the bypass list and the
# start/stop logic exist in exactly one place.

# Repo root = parent of tools\ , so the project can live in any folder.
$BaseDir    = Split-Path -Parent $PSScriptRoot
$ToolsDir   = $PSScriptRoot
$TunnelBat  = "$ToolsDir\start-tunnel.bat"
$TunnelCfg  = "$ToolsDir\tunnel.local.cmd"   # SSH login, gitignored
$GostExe    = "$ToolsDir\gost.exe"
$GostLog    = "$ToolsDir\gost.log"
$IconFile   = "$ToolsDir\icon-1a.ico"
$LogoFile   = "$ToolsDir\logo.png"
$TunnelPort = 5555
$BridgePort = 8118
$Socks5     = "socks5://127.0.0.1:5555"

# Smart routing: these masks bypass the proxy (RU sites go DIRECT).
$RuBypass = @(
    "*.ru"; "*.su"; "*.by"; "*.xn--p1ai"                  # .rf in punycode
    "vk.com"; "*.vk.com"; "*.userapi.com"                 # VK + its CDN
    "*.vkuservideo.net"; "*.vkuseraudio.net"
    "*.mycdn.me"                                          # OK / Mail.ru CDN
    "*.yandex.net"; "*.yastatic.net"; "*.yandex.com"      # Yandex CDN
    "sberbank.com"; "*.sberbank.com"
    "*.ozonusercontent.com"                               # Ozon CDN
    "*.wbstatic.net"                                      # Wildberries CDN
    "*.2gis.com"
)
# Internal network + localhost always bypass the proxy:
$InternalBypass = @("172.20.*"; "localhost"; "127.0.0.1"; "<local>")

# ---- state probes ----
function Tunnel-Up { [bool](Get-NetTCPConnection -LocalPort $TunnelPort -State Listen -ErrorAction SilentlyContinue) }
function Gost-Up   { [bool](Get-Process gost -ErrorAction SilentlyContinue) }
function Proxy-On  { (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings").ProxyEnable -eq 1 }

function Set-SystemProxy([bool]$On) {
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($On) {
        Set-ItemProperty $reg ProxyEnable 1
        Set-ItemProperty $reg ProxyServer "127.0.0.1:$BridgePort"
        # Smart routing: everything in $RuBypass + $InternalBypass goes DIRECT.
        Set-ItemProperty $reg ProxyOverride (($RuBypass + $InternalBypass) -join ";")
    } else { Set-ItemProperty $reg ProxyEnable 0 }
    if (-not ("PInvoke.WinINet" -as [type])) {
        $sig = '[DllImport("wininet.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
        Add-Type -MemberDefinition $sig -Name WinINet -Namespace PInvoke | Out-Null
    }
    [PInvoke.WinINet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [PInvoke.WinINet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

# ---- actions: each returns a human-readable message for the caller's log ----
function Start-Tunnel {
    if (-not (Test-Path $TunnelBat)) { return "Не найден $TunnelBat." }
    if (-not (Test-Path $TunnelCfg)) {
        return "Нет tools\tunnel.local.cmd - скопируй tunnel.example.cmd и впиши свой SSH-логин."
    }
    Start-Process $TunnelBat -WindowStyle Hidden
    Start-Sleep 3
    if (Tunnel-Up) { "Туннель поднялся." } else { "Туннель не поднялся (пароль? логин в bat?)." }
}

function Stop-Tunnel {
    Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
        Where-Object { $_.CommandLine -like "*start-tunnel*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
        Where-Object { $_.CommandLine -like "*-D $TunnelPort*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep 1
    if (Tunnel-Up) { "Туннель ещё жив - проверь окна вручную." } else { "Туннель остановлен." }
}

function Start-Gost {
    if (-not (Test-Path $GostExe)) { return "Не найден $GostExe." }
    Remove-Item $GostLog -ErrorAction SilentlyContinue
    try {
        Start-Process $GostExe -ArgumentList "-L","http://:$BridgePort","-F",$Socks5 `
            -WindowStyle Hidden -RedirectStandardError $GostLog
    } catch {
        return "Ошибка запуска gost: $($_.Exception.Message)"
    }
    Start-Sleep 1
    if (Gost-Up) { return "Мост gost запущен в фоне (порт $BridgePort)." }
    $tail = if (Test-Path $GostLog) { (Get-Content $GostLog -Tail 3 -ErrorAction SilentlyContinue) -join " | " }
    if (-not $tail) { $tail = "лог пуст" }
    "gost НЕ запустился. Причина (tools\gost.log): $tail"
}

function Stop-Gost {
    Get-Process gost -ErrorAction SilentlyContinue | Stop-Process -Force
    "Мост gost остановлен."
}
