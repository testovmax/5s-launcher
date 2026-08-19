# 5s-widget.ps1 - 5S Launcher as a desktop widget.
# A small borderless panel that floats above the desktop: no taskbar button,
# no Alt+Tab entry, survives "Show desktop" (Win+D). Drag it anywhere - the
# position is remembered. Right-click for the menu.
#
# Run:  wscript 5s-widget.vbs      (silent, no console flash)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Hide our own console window (5s-widget.vbs avoids the flash entirely).
if (-not ("Native.ConsoleUtil" -as [type])) {
    Add-Type -Name ConsoleUtil -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
}
[Native.ConsoleUtil]::ShowWindow([Native.ConsoleUtil]::GetConsoleWindow(), 0) | Out-Null

# Settings, probes and start/stop logic (single source of truth).
. "$PSScriptRoot\tools\5s-common.ps1"

# Win32 helpers: exact placement, drag, and undoing "Show desktop".
if (-not ("Native.Win" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Native {
  public struct RECT  { public int Left, Top, Right, Bottom; }
  public struct POINT { public int X, Y; }

  public static class Win {
    [DllImport("user32.dll")] public static extern int  GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] public static extern int  SetWindowLong(IntPtr h, int index, int val);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after,
                                          int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  }
}
'@
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="5S Widget" Width="322" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="False" ResizeMode="NoResize" Topmost="False"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="MiniBtn" TargetType="Button">
      <Setter Property="Background" Value="#1B4F9C"/>
      <Setter Property="Foreground" Value="#F2F5FA"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Height" Value="29"/>
      <Setter Property="Width" Value="89"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="7">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2D7FE0"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#16407F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border Background="#F00B1834" CornerRadius="17" BorderBrush="#24406F" BorderThickness="1"
          Padding="17,14">
    <Border.Effect>
      <DropShadowEffect Color="#000000" BlurRadius="22" ShadowDepth="4" Opacity="0.55"/>
    </Border.Effect>
    <StackPanel>
      <StackPanel Orientation="Horizontal" Margin="2,0,0,12">
        <Image x:Name="LogoImg" Width="22" Height="22" Margin="0,0,10,0"
               VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
        <TextBlock Text="5S Launcher" Foreground="#F2F5FA" FontSize="16"
                   FontWeight="SemiBold" VerticalAlignment="Center"/>
      </StackPanel>

      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/><RowDefinition Height="10"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="10"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="26"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>

        <TextBlock x:Name="DotTunnel" Grid.Row="0" Grid.Column="0" Text="&#9679;" FontSize="18"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StTunnel" Grid.Row="0" Grid.Column="1" Text="Туннель"
                   Foreground="#C9D6EA" FontSize="14" VerticalAlignment="Center"/>
        <Button x:Name="BtnTunnel" Grid.Row="0" Grid.Column="2" Content="..." Style="{StaticResource MiniBtn}"/>

        <TextBlock x:Name="DotGost" Grid.Row="2" Grid.Column="0" Text="&#9679;" FontSize="18"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StGost" Grid.Row="2" Grid.Column="1" Text="Мост gost"
                   Foreground="#C9D6EA" FontSize="14" VerticalAlignment="Center"/>
        <Button x:Name="BtnGost" Grid.Row="2" Grid.Column="2" Content="..." Style="{StaticResource MiniBtn}"/>

        <TextBlock x:Name="DotProxy" Grid.Row="4" Grid.Column="0" Text="&#9679;" FontSize="18"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StProxy" Grid.Row="4" Grid.Column="1" Text="Прокси"
                   Foreground="#C9D6EA" FontSize="14" VerticalAlignment="Center"/>
        <Button x:Name="BtnProxy" Grid.Row="4" Grid.Column="2" Content="..." Style="{StaticResource MiniBtn}"/>
      </Grid>

      <TextBlock x:Name="StatusLine" Text="" Foreground="#7E93B5" FontSize="12"
                 TextWrapping="Wrap" Margin="2,12,0,0"/>
    </StackPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$LogoImg   = $window.FindName("LogoImg")
$StTunnel  = $window.FindName("StTunnel");  $BtnTunnel = $window.FindName("BtnTunnel")
$StGost    = $window.FindName("StGost");    $BtnGost   = $window.FindName("BtnGost")
$StProxy   = $window.FindName("StProxy");   $BtnProxy  = $window.FindName("BtnProxy")
$DotTunnel = $window.FindName("DotTunnel"); $DotGost   = $window.FindName("DotGost")
$DotProxy  = $window.FindName("DotProxy");  $StatusLine = $window.FindName("StatusLine")

if (Test-Path $LogoFile) {
    $LogoImg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create(
        [Uri]$LogoFile, "None", "OnLoad")
}

# ---- status line instead of a log window: last message, auto-clears ----
$script:ClearTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ClearTimer.Interval = [TimeSpan]::FromSeconds(8)
$script:ClearTimer.Add_Tick({ $StatusLine.Text = ""; $script:ClearTimer.Stop() })
function Log($msg) {
    $StatusLine.Text = $msg
    $script:ClearTimer.Stop(); $script:ClearTimer.Start()
}

function Refresh-Status {
    if (Tunnel-Up) { $StTunnel.Text = "Туннель: работает";  $DotTunnel.Foreground = "#2D7FE0"; $BtnTunnel.Content = "Выключить" }
    else           { $StTunnel.Text = "Туннель: выключен";  $DotTunnel.Foreground = "#D97757"; $BtnTunnel.Content = "Включить" }
    if (Gost-Up)   { $StGost.Text   = "Мост gost: работает"; $DotGost.Foreground = "#2D7FE0";  $BtnGost.Content   = "Выключить" }
    else           { $StGost.Text   = "Мост gost: выключен"; $DotGost.Foreground = "#D97757";  $BtnGost.Content   = "Включить" }
    if (Proxy-On)  { $StProxy.Text  = "Прокси: включён";     $DotProxy.Foreground = "#2D7FE0"; $BtnProxy.Content  = "Выключить" }
    else           { $StProxy.Text  = "Прокси: выключен";    $DotProxy.Foreground = "#D97757"; $BtnProxy.Content  = "Включить" }
}

# ---- actions ----
$BtnTunnel.Add_Click({
    Log $(if (Tunnel-Up) { Stop-Tunnel } else { Start-Tunnel })
    Refresh-Status
})
$BtnGost.Add_Click({
    if (-not (Gost-Up) -and -not (Tunnel-Up)) { Log "Сначала подними туннель."; return }
    Log $(if (Gost-Up) { Stop-Gost } else { Start-Gost })
    Refresh-Status
})
$BtnProxy.Add_Click({
    if (Proxy-On) { Set-SystemProxy $false; Log "Прокси выключен." }
    else {
        Set-SystemProxy $true
        if (Gost-Up) { Log "Прокси включён: RU напрямую, остальное через мост." }
        else { Log "Прокси включён, но мост gost не запущен." }
    }
    Refresh-Status
})

# ---- geometry: the window is moved through the API, so drag works everywhere ----
# The handle is resolved live: caching it in an event handler proved unreliable,
# and creating it early (EnsureHandle) breaks rendering of a transparent window.
function Get-Hwnd { (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle }

$PosFile  = Join-Path $env:APPDATA "5S Launcher\widget.pos"
$ModeFile = Join-Path $env:APPDATA "5S Launcher\widget.mode"

function Get-WidgetPos {
    $r = New-Object Native.RECT
    [Native.Win]::GetWindowRect((Get-Hwnd), [ref]$r) | Out-Null
    ,@($r.Left, $r.Top)
}

function Move-Widget([int]$x, [int]$y) {
    # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
    [Native.Win]::SetWindowPos((Get-Hwnd), [IntPtr]::Zero, $x, $y, 0, 0, 0x15) | Out-Null
}

function Save-Setting($file, $value) {
    try {
        $dir = Split-Path -Parent $file
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $file -Value $value
    } catch { }
}

function Save-WidgetPos {
    $pos = Get-WidgetPos
    Save-Setting $PosFile ("{0};{1}" -f $pos[0], $pos[1])
}

# Default: top-right corner; overridden by the saved position if it is on-screen.
$area = [System.Windows.SystemParameters]::WorkArea
$startX = [int]($area.Right - $window.Width - 24)
$startY = [int]($area.Top + 24)
if (Test-Path $PosFile) {
    $parts = (Get-Content $PosFile -First 1) -split ";"
    if ($parts.Count -eq 2) {
        $x = 0; $y = 0
        if ([int]::TryParse($parts[0], [ref]$x) -and [int]::TryParse($parts[1], [ref]$y)) {
            # Ignore coordinates that ended up off-screen (monitor unplugged).
            if ($x -gt ($area.Left - 100) -and $x -lt ($area.Right - 60) -and
                $y -gt ($area.Top - 20)   -and $y -lt ($area.Bottom - 40)) {
                $startX = $x; $startY = $y
            }
        }
    }
}
$window.Left = $startX
$window.Top  = $startY

# ---- display mode: behind other windows (default) or on top of them ----
$script:TopMode = $false
if (Test-Path $ModeFile) {
    $script:TopMode = ((Get-Content $ModeFile -First 1).Trim() -eq "top")
}
$window.Topmost = $script:TopMode

function Push-Back {
    # HWND_BOTTOM = 1; SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE
    if (-not $script:TopMode) {
        [Native.Win]::SetWindowPos((Get-Hwnd), [IntPtr]1, 0, 0, 0, 0, 0x13) | Out-Null
    }
}

# Clicking the widget must not lift it above the windows it should stay under.
$window.Add_Activated({ Push-Back })

# ---- drag ----
$script:DragCur = $null
$script:DragWin = $null

$window.Add_MouseLeftButtonDown({
    $p = New-Object Native.POINT
    [Native.Win]::GetCursorPos([ref]$p) | Out-Null
    $script:DragCur = @($p.X, $p.Y)
    $script:DragWin = Get-WidgetPos
    $window.CaptureMouse() | Out-Null
})

$window.Add_MouseMove({
    if ($script:DragCur) {
        $p = New-Object Native.POINT
        [Native.Win]::GetCursorPos([ref]$p) | Out-Null
        Move-Widget ($script:DragWin[0] + $p.X - $script:DragCur[0]) `
                    ($script:DragWin[1] + $p.Y - $script:DragCur[1])
    }
})

$window.Add_MouseLeftButtonUp({
    if ($script:DragCur) {
        $script:DragCur = $null
        $window.ReleaseMouseCapture()
        Save-WidgetPos
    }
})

$window.Add_Loaded({ Push-Back })
$window.Add_Closing({ Save-WidgetPos })

# ---- right-click menu ----
$menu = New-Object System.Windows.Controls.ContextMenu

$miPanel = New-Object System.Windows.Controls.MenuItem
$miPanel.Header = "Открыть полный пульт"
$miPanel.Add_Click({
    $vbs = "$PSScriptRoot\5s-launcher.vbs"
    if (Test-Path $vbs) { Start-Process "wscript.exe" -ArgumentList "`"$vbs`"" }
    else { Log "Не найден 5s-launcher.vbs" }
})

$miTop = New-Object System.Windows.Controls.MenuItem
$miTop.Header = "Поверх всех окон"
$miTop.IsCheckable = $true
$miTop.IsChecked = $script:TopMode
$miTop.Add_Click({
    $script:TopMode = -not $script:TopMode
    $window.Topmost = $script:TopMode
    $miTop.IsChecked = $script:TopMode
    Push-Back
    Save-Setting $ModeFile $(if ($script:TopMode) { "top" } else { "back" })
    Log $(if ($script:TopMode) { "Поверх всех окон." } else { "За другими окнами." })
})

$StartupLnk = Join-Path ([Environment]::GetFolderPath("Startup")) "5S Widget.lnk"
$miAuto = New-Object System.Windows.Controls.MenuItem
$miAuto.Header = "Запускать при входе в Windows"
$miAuto.IsCheckable = $true
$miAuto.IsChecked = (Test-Path $StartupLnk)
$miAuto.Add_Click({
    try {
        if (Test-Path $StartupLnk) {
            Remove-Item $StartupLnk -Force
            Log "Автозапуск выключен."
        } else {
            $sh = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($StartupLnk)
            $lnk.TargetPath = "$env:WINDIR\System32\wscript.exe"
            $lnk.Arguments = "`"$PSScriptRoot\5s-widget.vbs`""
            $lnk.WorkingDirectory = $PSScriptRoot
            $lnk.IconLocation = $IconFile
            $lnk.Description = "5S Widget"
            $lnk.Save()
            Log "Автозапуск включён."
        }
    } catch { Log "Не удалось изменить автозапуск: $($_.Exception.Message)" }
    $miAuto.IsChecked = (Test-Path $StartupLnk)
})

$miClose = New-Object System.Windows.Controls.MenuItem
$miClose.Header = "Закрыть виджет"
$miClose.Add_Click({ $window.Close() })

$menu.Items.Add($miPanel) | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
$menu.Items.Add($miTop) | Out-Null
$menu.Items.Add($miAuto) | Out-Null
$menu.Items.Add($miClose) | Out-Null
$window.ContextMenu = $menu

# ---- keep out of Alt+Tab, and come back after "Show desktop" ----
$window.Add_SourceInitialized({
    $h = Get-Hwnd
    if ($h -ne [IntPtr]::Zero) {
        # GWL_EXSTYLE = -20, WS_EX_TOOLWINDOW = 0x80
        $ex = [Native.Win]::GetWindowLong($h, -20)
        [Native.Win]::SetWindowLong($h, -20, $ex -bor 0x80) | Out-Null
    }
})

# Win+D / "Show desktop" minimises every window, including this one.
# The guard notices that and restores the widget without stealing focus.
$guard = New-Object System.Windows.Threading.DispatcherTimer
$guard.Interval = [TimeSpan]::FromMilliseconds(400)
$guard.Add_Tick({
    $h = Get-Hwnd
    if ($h -eq [IntPtr]::Zero) { return }
    if ([Native.Win]::IsIconic($h) -or -not [Native.Win]::IsWindowVisible($h)) {
        if ($window.WindowState -ne [System.Windows.WindowState]::Normal) {
            $window.WindowState = [System.Windows.WindowState]::Normal
        }
        [Native.Win]::ShowWindow($h, 8) | Out-Null   # SW_SHOWNA - no focus steal
        Push-Back
    }
})
$guard.Start()

# ---- live refresh ----
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Refresh-Status; Push-Back })
$timer.Start()

Refresh-Status
$window.ShowDialog() | Out-Null
