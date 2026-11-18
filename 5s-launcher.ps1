# 5s-launcher.ps1 - 5S Launcher: control panel for the proxy stack.
# SSH tunnel is its own button. Gost and the system proxy are one button.
# Routing checkbox: sites from tools\bypass.txt go direct, or everything external
# goes through the proxy. Localhost and the internal network always stay direct.
# Live status refresh every 3 seconds.
#
# Run:  wscript 5s-launcher.vbs        (silent)

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

if (-not ("Native.Caption" -as [type])) {
    Add-Type -Name Caption -Namespace Native -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
public static void Paint(IntPtr hwnd) {
    int dark = 1;
    DwmSetWindowAttribute(hwnd, 20, ref dark, 4);
    int caption = 0x0034180B; // #0B1834
    int text = 0x00FAF5F2;    // #F2F5FA
    DwmSetWindowAttribute(hwnd, 35, ref caption, 4);
    DwmSetWindowAttribute(hwnd, 36, ref text, 4);
    DwmSetWindowAttribute(hwnd, 34, ref caption, 4);
}
'@
}
function Set-DarkCaption($target) {
    $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($target)).EnsureHandle()
    [Native.Caption]::Paint($hwnd) | Out-Null
}

# Settings, probes and start/stop logic live in tools\5s-common.ps1.
# The bypass list is tools\bypass.txt. Servers are tools\connections.json.
. "$PSScriptRoot\tools\5s-common.ps1"

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="5S Launcher" Height="560" Width="560"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        Background="#0B1834" FontFamily="Segoe UI">
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
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="MoreBtn" TargetType="Button">
      <Setter Property="Width" Value="32"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="Background" Value="#081226"/>
      <Setter Property="Foreground" Value="#7FA6DA"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="10">
              <TextBlock Text="···" Foreground="#7FA6DA" FontSize="16"
                         HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-6,0,0"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0F2145"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1C3868"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkMenu" TargetType="ContextMenu">
      <Setter Property="Background" Value="#081226"/>
      <Setter Property="Foreground" Value="#7FA6DA"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ContextMenu">
            <Border Background="#081226" CornerRadius="10" Padding="4">
              <StackPanel IsItemsHost="True"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DarkMenuItem" TargetType="MenuItem">
      <Setter Property="Foreground" Value="#7FA6DA"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="bd" Background="Transparent" Padding="10,6" CornerRadius="6" Margin="2,1">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0F2145"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="ServerCombo" TargetType="ComboBox">
      <Setter Property="Foreground" Value="#7FA6DA"/>
      <Setter Property="Background" Value="#081226"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="ItemContainerStyle">
        <Setter.Value>
          <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#7FA6DA"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ComboBoxItem">
                  <Border x:Name="row" Background="{TemplateBinding Background}"
                          Padding="{TemplateBinding Padding}" CornerRadius="6" Margin="2,1">
                    <ContentPresenter/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsHighlighted" Value="True">
                      <Setter TargetName="row" Property="Background" Value="#0F2145"/>
                    </Trigger>
                    <Trigger Property="IsSelected" Value="True">
                      <Setter TargetName="row" Property="Background" Value="#1C3868"/>
                      <Setter Property="Foreground" Value="#F2F5FA"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </Setter.Value>
      </Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid x:Name="root">
              <ToggleButton Focusable="False" ClickMode="Press" Background="Transparent"
                            IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="#081226" CornerRadius="10">
                      <Path Data="M 0 0 L 3.5 3.5 L 7 0" Stroke="#7E93B5" StrokeThickness="1.3"
                            HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"
                            StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <TextBlock Foreground="#7FA6DA" FontFamily="Consolas" FontSize="12"
                         Margin="12,0,28,0" VerticalAlignment="Center"
                         TextTrimming="CharacterEllipsis" IsHitTestVisible="False"
                         Text="{Binding SelectedItem.Label, RelativeSource={RelativeSource TemplatedParent}}"/>
              <Popup Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade"
                     IsOpen="{TemplateBinding IsDropDownOpen}" PlacementTarget="{Binding ElementName=root}">
                <Border Background="#081226" CornerRadius="10" Padding="4" Margin="0,4,0,0"
                        MinWidth="{Binding ActualWidth, ElementName=root}"
                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer Background="#081226" BorderThickness="0"
                                HorizontalScrollBarVisibility="Disabled"
                                VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
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
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="2,0,0,14">
      <Image x:Name="LogoImg" Width="38" Height="38" Margin="0,0,12,0"
             VerticalAlignment="Center" RenderOptions.BitmapScalingMode="HighQuality"/>
      <TextBlock Text="5S Launcher" Foreground="#F2F5FA" FontSize="27" FontWeight="SemiBold"
                 VerticalAlignment="Center"/>
    </StackPanel>

    <StackPanel Grid.Row="1" Margin="0,0,0,14">
      <TextBlock Text="СЕРВЕР" Foreground="#7E93B5" FontSize="11" Margin="2,0,0,6"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <ComboBox x:Name="SrvCombo" Style="{StaticResource ServerCombo}"
                  DisplayMemberPath="Label" SelectedValuePath="Id" VerticalAlignment="Center"/>
        <Button x:Name="BtnMore" Grid.Column="1" Margin="8,0,0,0" Style="{StaticResource MoreBtn}" ToolTip="Действия с сервером">
          <Button.ContextMenu>
            <ContextMenu x:Name="ServerMenu" Style="{StaticResource DarkMenu}">
              <MenuItem x:Name="MiAdd" Header="Добавить" Style="{StaticResource DarkMenuItem}"/>
              <MenuItem x:Name="MiEdit" Header="Изменить" Style="{StaticResource DarkMenuItem}"/>
              <MenuItem x:Name="MiDel" Header="Удалить" Style="{StaticResource DarkMenuItem}"/>
            </ContextMenu>
          </Button.ContextMenu>
        </Button>
      </Grid>
    </StackPanel>

    <Border Grid.Row="2" Background="#0F2145" BorderBrush="#1C3868" BorderThickness="1"
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
        <TextBlock x:Name="StTunnel" Grid.Row="0" Grid.Column="1" Text="Туннель: ..."
                   Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center" TextWrapping="Wrap"/>
        <Button x:Name="BtnTunnel" Grid.Row="0" Grid.Column="2" Content="..." Style="{StaticResource ActionBtn}"/>

        <TextBlock x:Name="DotProxy" Grid.Row="2" Grid.Column="0" Text="●" FontSize="16"
                   Foreground="#D97757" VerticalAlignment="Center"/>
        <TextBlock x:Name="StProxy" Grid.Row="2" Grid.Column="1" Text="Прокси: ..."
                   Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center" TextWrapping="Wrap"/>
        <Button x:Name="BtnProxy" Grid.Row="2" Grid.Column="2" Content="..." Style="{StaticResource ActionBtn}"/>

        <StackPanel Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="2">
          <CheckBox x:Name="ChkRoute" Content="Маршрутизация: сайты из списка напрямую"
                    Foreground="#C9D6EA" FontSize="13" VerticalAlignment="Center"
                    ToolTip="Локальная сеть и localhost всегда идут напрямую."/>
          <TextBlock Margin="18,5,0,0" FontSize="12">
            <Hyperlink x:Name="LinkBypass" Foreground="#2D7FE0">Открыть список</Hyperlink>
          </TextBlock>
        </StackPanel>
      </Grid>
    </Border>

    <TextBlock Grid.Row="3" Text="ЖУРНАЛ" Foreground="#7E93B5" FontSize="11" Margin="2,0,0,6"/>
    <Border Grid.Row="4" Background="#081226" CornerRadius="10" Padding="6">
      <TextBox x:Name="LogBox" Background="Transparent" Foreground="#7FA6DA"
               FontFamily="Consolas" FontSize="12" IsReadOnly="True" BorderThickness="0"
               VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" Padding="8,6"/>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.Add_SourceInitialized({ Set-DarkCaption $window })

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
$StProxy   = $window.FindName("StProxy");   $BtnProxy  = $window.FindName("BtnProxy")
$DotTunnel = $window.FindName("DotTunnel"); $DotProxy  = $window.FindName("DotProxy")
$LogBox    = $window.FindName("LogBox");    $SrvCombo  = $window.FindName("SrvCombo")
$BtnMore   = $window.FindName("BtnMore");   $ChkRoute  = $window.FindName("ChkRoute")
$MiAdd     = $window.FindName("MiAdd");     $MiEdit    = $window.FindName("MiEdit")
$MiDel     = $window.FindName("MiDel")

$script:SuspendUi = $false
$script:ActionBusy = $false
$global:FiveSPingText = ""
$global:FiveSPingHost = ""

function Log($msg) {
    foreach ($line in @(([string]$msg) -split "`r?`n")) {
        if ($line -eq "") { continue }
        $LogBox.AppendText("[" + (Get-Date -Format "HH:mm:ss") + "] $line`r`n")
    }
    $LogBox.ScrollToEnd()
}

function Test-ProxyStop {
    if (ProxyPair-On) { return $true }
    # Tunnel is down, so the pair cannot be completed. Offer to clear the half-state.
    if (-not (Tunnel-Up) -and ((Gost-Up) -or (Proxy-On))) { return $true }
    $false
}

function Get-ActiveHost {
    $conn = Get-ActiveConnection
    if (-not $conn -or -not $conn.target) { return $null }
    if ($conn.protocol -eq "vless") {
        if ($conn.target -match '^(.+):\d+$') { return $Matches[1] }
        return [string]$conn.target
    }
    if ($conn.target -match '@([^@]+)$') { return $Matches[1] }
    [string]$conn.target
}

function Read-ServerPing {
    if (-not $script:PingProc) { return }
    if (-not $script:PingProc.HasExited) { return }
    $text = "нет ответа"
    if ($script:PingOut -and (Test-Path -LiteralPath $script:PingOut)) {
        $raw = [System.IO.File]::ReadAllText($script:PingOut, [System.Text.Encoding]::GetEncoding(866))
        if ($raw -match '(?:time|время)\s*[=<]\s*(\d+)') { $text = "$($Matches[1]) мс" }
    }
    $global:FiveSPingText = $text
    $script:PingProc = $null
}

function Start-ServerPing {
    Read-ServerPing
    $h = Get-ActiveHost
    if (-not $h) { $global:FiveSPingText = ""; $global:FiveSPingHost = ""; return }
    if ($global:FiveSPingHost -ne $h) { $global:FiveSPingText = ""; $global:FiveSPingHost = $h }
    if ($script:PingProc -and -not $script:PingProc.HasExited) { return }
    $out = Join-Path $env:TEMP "5s-ping.txt"
    $script:PingOut = $out
    $script:PingProc = Start-Process -FilePath "$env:SystemRoot\System32\ping.exe" -ArgumentList @("-n","1","-w","1000",$h) `
        -WindowStyle Hidden -RedirectStandardOutput $out -PassThru
}

function Refresh-Status {
    $conn = Get-ActiveConnection
    $who = if ($conn) { $conn.name } else { "сервер не выбран" }
    $kind = if ($conn -and $conn.protocol -eq "vless") { "VLESS" } else { "SSH" }
    $ping = if ($global:FiveSPingText) { " · $($global:FiveSPingText)" } else { "" }
    if (Tunnel-Up) { $StTunnel.Text = "${kind}: работает · $who$ping"; $DotTunnel.Foreground = "#2D7FE0"; $BtnTunnel.Content = "Остановить" }
    else           { $StTunnel.Text = "${kind}: остановлен · $who$ping"; $DotTunnel.Foreground = "#D97757"; $BtnTunnel.Content = "Запустить" }
    if (ProxyPair-On) {
        $StProxy.Text = "Прокси: включён (127.0.0.1:$BridgePort)"
        $DotProxy.Foreground = "#2D7FE0"
    } elseif ((Gost-Up) -and -not (Proxy-On)) {
        $StProxy.Text = "Прокси: мост есть, системный выключен"
        $DotProxy.Foreground = "#D97757"
    } elseif ((Proxy-On) -and -not (Gost-Up)) {
        $StProxy.Text = "Прокси: системный включён, мост не работает"
        $DotProxy.Foreground = "#D97757"
    } else {
        $StProxy.Text = "Прокси: выключен"
        $DotProxy.Foreground = "#D97757"
    }
    if (Test-ProxyStop) { $BtnProxy.Content = "Выключить" } else { $BtnProxy.Content = "Включить" }
}

function Update-ConnectionList {
    $script:SuspendUi = $true
    $cfg = Get-LauncherConfig
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($c in (ConvertTo-ConnList $cfg.connections)) {
        $items.Add([pscustomobject]@{ Id = $c.id; Label = "$($c.name)  —  $($c.target)" })
    }
    $SrvCombo.ItemsSource = $items
    if ($cfg.activeId) { $SrvCombo.SelectedValue = [string]$cfg.activeId }
    $ChkRoute.IsChecked = [bool]$cfg.routing
    $script:SuspendUi = $false
}

function Set-ActionsEnabled([bool]$On) {
    $BtnTunnel.IsEnabled = $On
    $BtnProxy.IsEnabled = $On
    $BtnMore.IsEnabled = $On
    $SrvCombo.IsEnabled = $On
    $ChkRoute.IsEnabled = $On
}

function Invoke-LauncherAction([string]$Name) {
    if ($script:ActionBusy) { return }
    $script:ActionBusy = $true
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $result = switch ($Name) {
            "start-tunnel"  { Start-Tunnel }
            "stop-tunnel"   { Stop-Tunnel }
            "start-proxy"   { $cfg = Get-LauncherConfig; Start-ProxyPair -Routing ([bool]$cfg.routing) }
            "stop-proxy"    { Stop-ProxyPair }
            "switch-tunnel" { Switch-Tunnel }
            "apply-routing" { Apply-Routing }
            default         { "Неизвестное действие: $name" }
        }
        if ($result) { Log ($result -join " ") }
    } catch {
        Log ("Ошибка: " + $_.Exception.Message)
    } finally {
        $script:ActionBusy = $false
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        Refresh-Status
    }
}

function Show-ConnectionDialog($Existing) {
    [xml]$dxaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Подключение" Height="520" Width="500"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#0B1834" FontFamily="Segoe UI" ShowInTaskbar="False">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Имя" Foreground="#C9D6EA" Margin="0,0,0,4"/>
    <TextBox x:Name="ConnName" Grid.Row="1" Height="28" Margin="0,0,0,12" Padding="6,2"/>
    <TextBlock Grid.Row="2" Text="Протокол" Foreground="#C9D6EA" Margin="0,0,0,4"/>
    <ComboBox x:Name="ConnProto" Grid.Row="3" Height="32" Margin="0,0,0,12"
              DisplayMemberPath="Label" SelectedValuePath="Id"/>
    <StackPanel x:Name="SshFields" Grid.Row="4">
      <TextBlock Text="Сервер (login@host)" Foreground="#C9D6EA" Margin="0,0,0,4"/>
      <TextBox x:Name="ConnTarget" Height="28" Margin="0,0,0,12" Padding="6,2"/>
      <TextBlock Text="Ключ SSH, можно оставить пустым" Foreground="#C9D6EA" Margin="0,0,0,4"/>
      <Grid Margin="0,0,0,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="96"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="ConnKey" Height="28" Padding="6,2"/>
        <Button x:Name="BtnBrowse" Grid.Column="1" Content="Обзор" Margin="8,0,0,0" Height="28"/>
      </Grid>
    </StackPanel>
    <StackPanel x:Name="VlessFields" Grid.Row="4" Visibility="Collapsed">
      <TextBlock Text="Ссылка vless://" Foreground="#C9D6EA" Margin="0,0,0,4"/>
      <TextBox x:Name="ConnLink" Height="120" Padding="6,4" TextWrapping="Wrap"
               AcceptsReturn="True" VerticalScrollBarVisibility="Auto"/>
      <TextBlock Margin="0,8,0,0" Foreground="#7E93B5" FontSize="12" TextWrapping="Wrap"
                 Text="Локальный SOCKS остаётся на порту 5555, мост HTTP не меняется."/>
    </StackPanel>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnCancel" Content="Отмена" Width="96" Height="32" Margin="0,0,8,0"/>
      <Button x:Name="BtnSave" Content="Сохранить" Width="110" Height="32"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $dxaml))
    $dlg.Owner = $window
    $dlg.Add_SourceInitialized({ Set-DarkCaption $dlg }.GetNewClosure())
    $dlg.Title = if ($Existing) { "Изменить подключение" } else { "Новое подключение" }
    $nameBox = $dlg.FindName("ConnName")
    $targetBox = $dlg.FindName("ConnTarget")
    $keyBox = $dlg.FindName("ConnKey")
    $linkBox = $dlg.FindName("ConnLink")
    $sshFields = $dlg.FindName("SshFields")
    $vlessFields = $dlg.FindName("VlessFields")
    $proto = $dlg.FindName("ConnProto")
    $proto.Style = $window.FindResource("ServerCombo")
    $proto.ItemsSource = @(
        [pscustomobject]@{ Id = "ssh"; Label = "SSH" },
        [pscustomobject]@{ Id = "vless"; Label = "VLESS" }
    )
    $proto.Add_SelectionChanged({
        $vless = [string]$proto.SelectedValue -eq "vless"
        $sshFields.Visibility = if ($vless) { "Collapsed" } else { "Visible" }
        $vlessFields.Visibility = if ($vless) { "Visible" } else { "Collapsed" }
    }.GetNewClosure())
    if ($Existing) {
        $nameBox.Text = [string]$Existing.name
        $targetBox.Text = [string]$Existing.target
        $keyBox.Text = [string]$Existing.identity
        $linkBox.Text = [string]$Existing.link
        $proto.SelectedValue = if ([string]$Existing.protocol -eq "vless") { "vless" } else { "ssh" }
    } else {
        $proto.SelectedValue = "ssh"
    }
    # A hashtable, not $script:, because the click handler runs in its own
    # module and would not be able to hand the values back otherwise.
    $result = @{ Value = $null }
    $dlg.FindName("BtnBrowse").Add_Click({
        $pick = New-Object Microsoft.Win32.OpenFileDialog
        $pick.Title = "Ключ SSH"
        $pick.Filter = "Все файлы|*.*"
        if ($keyBox.Text -and (Test-Path -LiteralPath $keyBox.Text)) {
            $pick.InitialDirectory = Split-Path -Parent $keyBox.Text
            $pick.FileName = Split-Path -Leaf $keyBox.Text
        }
        if ($pick.ShowDialog($dlg)) { $keyBox.Text = $pick.FileName }
    }.GetNewClosure())
    $cancel = $dlg.FindName("BtnCancel")
    $cancel.IsCancel = $true
    $cancel.Add_Click({ $dlg.DialogResult = $false }.GetNewClosure())
    $save = $dlg.FindName("BtnSave")
    $save.IsDefault = $true
    $save.Add_Click({
        $chosen = [string]$proto.SelectedValue
        $err = Test-ConnectionFields $nameBox.Text $targetBox.Text $keyBox.Text $chosen $linkBox.Text
        if ($err) {
            [System.Windows.MessageBox]::Show($dlg, $err, "Подключение", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $result.Value = [pscustomobject]@{
            Name     = $nameBox.Text.Trim()
            Target   = $targetBox.Text.Trim()
            Identity = $keyBox.Text.Trim()
            Protocol = $chosen
            Link     = $linkBox.Text.Trim()
        }
        $dlg.DialogResult = $true
    }.GetNewClosure())
    if ($dlg.ShowDialog()) { return $result.Value }
    $null
}

function Get-SelectedConnection {
    $cfg = Get-LauncherConfig
    $id = [string]$SrvCombo.SelectedValue
    if (-not $id) { $id = [string]$cfg.activeId }
    Find-Connection $cfg.connections $id
}

# ---- actions ----
$BtnTunnel.Add_Click({
    if (Tunnel-Up) { Log "Останавливаю туннель..."; Invoke-LauncherAction "stop-tunnel" }
    else { Log "Запускаю туннель..."; Invoke-LauncherAction "start-tunnel" }
})

$BtnProxy.Add_Click({
    if (Test-ProxyStop) { Invoke-LauncherAction "stop-proxy" }
    else { Log "Включаю мост и системный прокси..."; Invoke-LauncherAction "start-proxy" }
})

$ChkRoute.Add_Click({
    if ($script:SuspendUi) { return }
    $on = [bool]$ChkRoute.IsChecked
    Set-RoutingEnabled $on
    if (Proxy-On) { Invoke-LauncherAction "apply-routing" }
    elseif ($on) { Log "Маршрутизация включена. Заработает вместе с прокси." }
    else { Log "Маршрутизация выключена. Внешний трафик пойдёт через прокси." }
})

$window.FindName("LinkBypass").Add_Click({
    if (-not (Test-Path -LiteralPath $BypassFile)) {
        Log "Нет файла tools\bypass.txt."
        return
    }
    Start-Process -FilePath $BypassFile
    Log "Открыт список. После правок переключите галку, чтобы применить."
})

$SrvCombo.Add_SelectionChanged({
    if ($script:SuspendUi) { return }
    $newId = [string]$SrvCombo.SelectedValue
    if (-not $newId) { return }
    $cfg = Get-LauncherConfig
    if ($newId -eq [string]$cfg.activeId) { return }
    if (Tunnel-Up) {
        $answer = [System.Windows.MessageBox]::Show(
            $window,
            "Переключить туннель на выбранный сервер?",
            "5S Launcher",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
            $script:SuspendUi = $true
            $SrvCombo.SelectedValue = [string]$cfg.activeId
            $script:SuspendUi = $false
            return
        }
        Set-ActiveConnection $newId | Out-Null
        Log "Переключаю туннель..."
        Invoke-LauncherAction "switch-tunnel"
        return
    }
    $msg = Set-ActiveConnection $newId
    Log $msg
    Refresh-Status
})

$BtnMore.Add_Click({
    $menu = $BtnMore.ContextMenu
    $menu.PlacementTarget = $BtnMore
    $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.IsOpen = $true
})

$MiAdd.Add_Click({
    $made = Show-ConnectionDialog $null
    if (-not $made) { return }
    $item = Add-Connection $made.Name $made.Target $made.Identity $made.Protocol $made.Link
    if ($item -is [string]) { Log $item; return }
    if (-not (Get-LauncherConfig).activeId) { Set-ActiveConnection $item.id | Out-Null }
    Update-ConnectionList
    Log "Добавлен сервер: $($made.Name)"
    Refresh-Status
})

$MiEdit.Add_Click({
    $cur = Get-SelectedConnection
    if (-not $cur) { Log "Сначала добавьте подключение."; return }
    $edited = Show-ConnectionDialog $cur
    if (-not $edited) { return }
    $msg = Update-Connection $cur.id $edited.Name $edited.Target $edited.Identity $edited.Protocol $edited.Link
    if ($msg -ne "Подключение сохранено.") { Log $msg; return }
    Update-ConnectionList
    Log $msg
    if (Tunnel-Up -and $cur.id -eq [string](Get-LauncherConfig).activeId) {
        $answer = [System.Windows.MessageBox]::Show(
            $window,
            "Перезапустить туннель с новыми данными?",
            "5S Launcher",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question)
        if ($answer -eq [System.Windows.MessageBoxResult]::Yes) {
            Log "Перезапускаю туннель..."
            Invoke-LauncherAction "switch-tunnel"
        }
    }
    Refresh-Status
})

$MiDel.Add_Click({
    $cur = Get-SelectedConnection
    if (-not $cur) { return }
    if ((Tunnel-Up) -and $cur.id -eq [string](Get-LauncherConfig).activeId) {
        [System.Windows.MessageBox]::Show($window, "Сначала остановите туннель — это активный сервер.", "5S Launcher", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    $answer = [System.Windows.MessageBox]::Show($window, "Удалить «$($cur.name)»?", "5S Launcher", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Log (Remove-Connection $cur.id)
    Update-ConnectionList
    Refresh-Status
})

# ---- live refresh every 3s ----
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ try { if (-not $script:ActionBusy) { Refresh-Status } } catch {} })
$timer.Start()

$pingTimer = New-Object System.Windows.Threading.DispatcherTimer
$pingTimer.Interval = [TimeSpan]::FromSeconds(5)
$pingTimer.Add_Tick({ try { Start-ServerPing } catch { $global:FiveSPingBusy = $false } })
$pingTimer.Start()
Start-ServerPing

# Tunnel drop: close the Claude desktop app. A manual Stop sets the flag first.
$script:TunnelWasUp = [bool](Tunnel-Up)
$tunnelWatch = New-Object System.Windows.Threading.DispatcherTimer
$tunnelWatch.Interval = [TimeSpan]::FromMilliseconds(250)
$tunnelWatch.Add_Tick({
    try {
        $up = [bool](Tunnel-Up)
        if ($up) {
            $global:FiveSUserStoppedTunnel = $false
        } elseif ($script:TunnelWasUp) {
            if ($global:FiveSUserStoppedTunnel) {
                $global:FiveSUserStoppedTunnel = $false
            } else {
                $msg = Stop-ClaudeApp
                if ($msg) { Log $msg } else { Log "Туннель упал." }
            }
        }
        $script:TunnelWasUp = $up
    } catch {}
})
$tunnelWatch.Start()

Update-ConnectionList
Log "Пульт запущен."
$boot = Get-ActiveConnection
if ($boot) { Log "Сервер: $($boot.name)" } else { Log "Добавьте SSH-подключение." }
if ([bool]$ChkRoute.IsChecked) { Log "Маршрутизация включена." } else { Log "Маршрутизация выключена." }
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
            "-NoProfile -STA -ExecutionPolicy Bypass -File \"$($BaseDir -replace '\\','\\')\\5s-launcher.ps1\"");
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