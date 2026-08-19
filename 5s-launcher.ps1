# 5s-launcher.ps1 - 5S Launcher: control panel for the proxy stack.
# Buttons: SSH tunnel start/stop, gost bridge start/stop, system proxy on/off.
# System proxy uses smart routing: RU sites go direct, the rest via proxy.
# Live status refresh every 3 seconds.
#
# Run:  wscript 5s-launcher.vbs        (silent)
# Compact desktop version: 5s-widget.ps1

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Hide this script's own console window. For zero flash on startup,
# launch via 5s-launcher.vbs (and point the desktop shortcut at it).
if (-not ("Native.ConsoleUtil" -as [type])) {
    Add-Type -Name ConsoleUtil -Namespace Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
}
[Native.ConsoleUtil]::ShowWindow([Native.ConsoleUtil]::GetConsoleWindow(), 0) | Out-Null

# Settings, probes and start/stop logic live in tools\5s-common.ps1,
# shared with the desktop widget - edit the bypass list there.
. "$PSScriptRoot\tools\5s-common.ps1"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="5S Launcher" Height="450" Width="500"
        WindowStartupLocation="CenterScreen" Background="#0B1834"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="ActionBtn" TargetType="Button">
      <Setter Property="Background" Value="#1B4F9C"/>
      <Setter Property="Foreground" Value="#F2F5FA"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="8">
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
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,0,14">
      <Image x:Name="LogoImg" Width="38" Height="38" Margin="0,0,12,0"
             VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Text="5S Launcher" Foreground="#F2F5FA" FontSize="27" FontWeight="SemiBold"
                 VerticalAlignment="Center"/>
    </StackPanel>

    <Border Grid.Row="1" Background="#0F2145" BorderBrush="#1C3868" BorderThickness="1"
            CornerRadius="10" Padding="16,14" Margin="0,0,0,14">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/><RowDefinition Height="12"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="12"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="26"/><ColumnDefinition Width="*"/><ColumnDefinition Width="120"/>
        </Grid.ColumnDefinitions>

        <TextBlock x:Name="DotTunnel" Grid.Row="0" Grid.Column="0" Text="●" FontSize="16"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StTunnel" Grid.Row="0" Grid.Column="1" Text="SSH-туннель: ..."
                   Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center"/>
        <Button x:Name="BtnTunnel" Grid.Row="0" Grid.Column="2" Content="..." Style="{StaticResource ActionBtn}"/>

        <TextBlock x:Name="DotGost" Grid.Row="2" Grid.Column="0" Text="●" FontSize="16"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StGost" Grid.Row="2" Grid.Column="1" Text="Мост gost: ..."
                   Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center"/>
        <Button x:Name="BtnGost" Grid.Row="2" Grid.Column="2" Content="..." Style="{StaticResource ActionBtn}"/>

        <TextBlock x:Name="DotProxy" Grid.Row="4" Grid.Column="0" Text="●" FontSize="16"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StProxy" Grid.Row="4" Grid.Column="1" Text="Системный прокси: ..."
                   Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center"/>
        <Button x:Name="BtnProxy" Grid.Row="4" Grid.Column="2" Content="..." Style="{StaticResource ActionBtn}"/>
      </Grid>
    </Border>

    <TextBlock Grid.Row="2" Text="ЖУРНАЛ" Foreground="#7E93B5" FontSize="11" Margin="2,0,0,6"/>
    <Border Grid.Row="3" Background="#081226" CornerRadius="10" Padding="6">
      <TextBox x:Name="LogBox" Background="Transparent" Foreground="#7FA6DA"
               FontFamily="Consolas" FontSize="12" IsReadOnly="True" BorderThickness="0"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Padding="8,6"/>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Window icon = taskbar icon (otherwise Windows shows the PowerShell icon).
if (Test-Path $IconFile) {
    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create(
        [Uri]$IconFile, "None", "OnLoad")
}

# Logo in the header (loaded from file if present, so a missing png never breaks startup).
$LogoImg = $window.FindName("LogoImg")
if ($LogoImg -and (Test-Path $LogoFile)) {
    $LogoImg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create(
        [Uri]$LogoFile, "None", "OnLoad")
}

# Own taskbar identity, so the button is not grouped under PowerShell.
if (-not ("Native.AppId" -as [type])) {
    Add-Type -Name AppId -Namespace Native -MemberDefinition @'
[DllImport("shell32.dll", SetLastError=true)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);
'@
}
[Native.AppId]::SetCurrentProcessExplicitAppUserModelID("5S.Launcher") | Out-Null

# Taskbar pinning support: a Start Menu shortcut carrying our AppUserModelID.
# The taskbar takes the button icon from this shortcut, and "Pin to taskbar"
# pins it like a normal application.
if (-not ("Native.ShortcutMaker" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace Native {
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  public struct PropertyKey {
    public Guid fmtid; public uint pid;
    public PropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
  }
  [StructLayout(LayoutKind.Explicit)]
  public struct PropVariant {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pointerValue;
  }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
   InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IPropertyStore {
    int GetCount(out uint cProps);
    int GetAt(uint iProp, out PropertyKey pkey);
    int GetValue(ref PropertyKey key, out PropVariant pv);
    int SetValue(ref PropertyKey key, ref PropVariant pv);
    int Commit();
  }
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
  public class CShellLink { }
  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"),
   InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IShellLinkW {
    void GetPath(StringBuilder pszFile, int cch, IntPtr pfd, uint fFlags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription(StringBuilder pszName, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory(StringBuilder pszDir, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments(StringBuilder pszArgs, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out short pwHotkey);
    void SetHotkey(short wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation(StringBuilder pszIconPath, int cch, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
    void Resolve(IntPtr hwnd, uint fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
  }
  public static class ShortcutMaker {
    [DllImport("ole32.dll")]
    static extern int PropVariantClear(ref PropVariant pvar);

    public static void Create(string lnkPath, string target, string args,
                              string workDir, string icon, string appId, string descr) {
      IShellLinkW link = (IShellLinkW)new CShellLink();
      link.SetPath(target);
      link.SetArguments(args);
      link.SetWorkingDirectory(workDir);
      link.SetIconLocation(icon, 0);
      link.SetDescription(descr);
      IPropertyStore store = (IPropertyStore)link;
      PropertyKey key = new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
      PropVariant pv = new PropVariant();
      pv.vt = 31; // VT_LPWSTR
      pv.pointerValue = Marshal.StringToCoTaskMemUni(appId);
      store.SetValue(ref key, ref pv);
      store.Commit();
      PropVariantClear(ref pv);
      ((IPersistFile)link).Save(lnkPath, true);
      Marshal.ReleaseComObject(link);
    }
  }
  public static class TaskbarProps {
    [DllImport("shell32.dll")]
    static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore store);
    [DllImport("ole32.dll")]
    static extern int PropVariantClear(ref PropVariant pvar);

    static readonly Guid AppModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

    static void SetString(IPropertyStore store, uint pid, string value) {
      PropertyKey key = new PropertyKey(AppModel, pid);
      PropVariant pv = new PropVariant();
      pv.vt = 31; // VT_LPWSTR
      pv.pointerValue = Marshal.StringToCoTaskMemUni(value);
      store.SetValue(ref key, ref pv);
      PropVariantClear(ref pv);
    }
    // Tells the taskbar how to relaunch this window when its button is pinned.
    // iconRes must point at an EXE/DLL resource ("app.exe,0") - a bare .ico
    // does not resolve and the pinned button ends up blank.
    public static void Apply(IntPtr hwnd, string appId, string relaunchCmd,
                             string displayName, string iconRes) {
      Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
      IPropertyStore store;
      if (SHGetPropertyStoreForWindow(hwnd, ref iid, out store) != 0 || store == null) return;
      SetString(store, 5, appId);        // System.AppUserModel.ID
      SetString(store, 2, relaunchCmd);  // RelaunchCommand
      SetString(store, 4, displayName);  // RelaunchDisplayNameResource
      SetString(store, 3, iconRes);      // RelaunchIconResource
      store.Commit();
      Marshal.ReleaseComObject(store);
    }
  }
}
'@
}

$StTunnel  = $window.FindName("StTunnel");  $BtnTunnel = $window.FindName("BtnTunnel")
$StGost    = $window.FindName("StGost");    $BtnGost   = $window.FindName("BtnGost")
$StProxy   = $window.FindName("StProxy");   $BtnProxy  = $window.FindName("BtnProxy")
$DotTunnel = $window.FindName("DotTunnel"); $DotGost   = $window.FindName("DotGost")
$DotProxy  = $window.FindName("DotProxy");  $LogBox    = $window.FindName("LogBox")

function Log($msg) {
    $LogBox.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "] $msg`r`n")
    $LogBox.ScrollToEnd()
}

function Refresh-Status {
    # Палитра иконки: работает - ярко-синяя точка (#2D7FE0), остановлен - терракотовая (#D97757).
    # Текст статуса всегда спокойный светлый, состояние показывает точка-индикатор.
    if (Tunnel-Up) { $StTunnel.Text = "SSH-туннель: работает (порт $TunnelPort)"; $DotTunnel.Foreground = "#2D7FE0"; $BtnTunnel.Content = "Остановить" }
    else           { $StTunnel.Text = "SSH-туннель: остановлен";                  $DotTunnel.Foreground = "#D97757"; $BtnTunnel.Content = "Запустить" }
    if (Gost-Up)   { $StGost.Text = "Мост gost: работает (порт $BridgePort)";     $DotGost.Foreground = "#2D7FE0";   $BtnGost.Content = "Остановить" }
    else           { $StGost.Text = "Мост gost: остановлен";                      $DotGost.Foreground = "#D97757";   $BtnGost.Content = "Запустить" }
    if (Proxy-On)  { $StProxy.Text = "Системный прокси: включён (:$BridgePort)";  $DotProxy.Foreground = "#2D7FE0";  $BtnProxy.Content = "Выключить" }
    else           { $StProxy.Text = "Системный прокси: выключен";                $DotProxy.Foreground = "#D97757";  $BtnProxy.Content = "Включить" }
}

# ---- actions ----
$BtnTunnel.Add_Click({
    if (Tunnel-Up) {
        Log "Останавливаю туннель (окно bat + ssh)..."
        Log (Stop-Tunnel)
    } else {
        Log "Запускаю туннель (в фоне, без окна)..."
        Log (Start-Tunnel)
    }
    Refresh-Status
})

$BtnGost.Add_Click({
    if (Gost-Up) {
        Log (Stop-Gost)
    } else {
        if (-not (Tunnel-Up)) { Log "Сначала подними SSH-туннель - мосту некуда пересылать." }
        Log (Start-Gost)
    }
    Refresh-Status
})

$BtnProxy.Add_Click({
    if (Proxy-On) { Set-SystemProxy $false; Log "Системный прокси выключен." }
    else {
        Set-SystemProxy $true
        Log "Системный прокси включён -> 127.0.0.1:$BridgePort."
        if (-not (Gost-Up)) { Log "Внимание: мост gost не запущен - без него интернет через прокси не пойдёт." }
    }
    Refresh-Status
})

# ---- live refresh every 3s ----
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Refresh-Status })
$timer.Start()

Log "Пульт запущен."
Refresh-Status

# ---- Taskbar identity: tiny launcher EXE + Start Menu shortcut ----
# Windows takes a pinned button's icon from an EXE/DLL resource, never from a
# bare .ico, and pinning a powershell window would pin the PowerShell icon.
# So we build a small 5s-launcher.exe with our icon embedded; it just starts
# this script hidden. Built once, rebuilt automatically if missing.
$ExeFile = "$BaseDir\tools\5s-launcher.exe"
if (-not (Test-Path $ExeFile)) {
    try {
        $src = @"
using System.Diagnostics;
class Program {
    static void Main() {
        ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -File \"$($BaseDir -replace '\\','\\')\\5s-launcher.ps1\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        Process.Start(psi);
    }
}
"@
        # csc.exe directly: Add-Type dropped -OutputAssembly/-CompilerOptions
        # in PowerShell 7, csc works the same in both 5.1 and 7.
        $csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
                 "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
               Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $csc) { throw "csc.exe не найден (нужен .NET Framework 4)" }
        $srcFile = Join-Path $env:TEMP "5s-launcher-src.cs"
        Set-Content -Path $srcFile -Value $src -Encoding UTF8
        $out = & $csc /nologo /target:winexe "/win32icon:$IconFile" "/out:$ExeFile" $srcFile 2>&1
        if (-not (Test-Path $ExeFile)) { throw (($out | Out-String).Trim()) }
        Remove-Item $srcFile -ErrorAction SilentlyContinue
        Log "Собран tools\5s-launcher.exe (иконка для панели задач)."
    } catch {
        Log "Не удалось собрать 5s-launcher.exe: $($_.Exception.Message)"
    }
}

# Start Menu shortcut carrying the same AppUserModelID, so the running window
# docks into the pinned button instead of creating a second one.
if (Test-Path $ExeFile) {
    try {
        $LnkPath = Join-Path ([Environment]::GetFolderPath("Programs")) "5S Launcher.lnk"
        [Native.ShortcutMaker]::Create($LnkPath, $ExeFile, "", $BaseDir, $ExeFile,
            "5S.Launcher", "5S Launcher")
    } catch { Log "Не удалось создать ярлык в меню Пуск: $($_.Exception.Message)" }

    # Same info on the window itself: right-click -> "Закрепить" works too.
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        $hwnd = $helper.EnsureHandle()
        [Native.TaskbarProps]::Apply($hwnd, "5S.Launcher", "`"$ExeFile`"",
            "5S Launcher", "$ExeFile,0")
    } catch { Log "Не удалось задать свойства панели задач: $($_.Exception.Message)" }
}

$window.ShowDialog() | Out-Null