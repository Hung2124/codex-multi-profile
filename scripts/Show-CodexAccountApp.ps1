#Requires -Version 5.1
<#
.SYNOPSIS
  Codex Accounts — Windows desktop picker for multiple authorized ChatGPT logins.

.DESCRIPTION
  Standalone WPF app (PowerShell 5.1, no extra SDK). Lists AuthSwap profiles as
  selectable cards: name, masked email, last-used, depleted badge, sticky paths.
  Click / Enter launches via Launch-CodexProfile.ps1. If a Codex window is already
  open, shows the one-window message and does not start a second UI.

  Device-code / chatgpt.com login is NOT implemented here. First-run still uses
  the existing AuthSwap bootstrap inside Codex.

.PARAMETER Headless
  Load pool/state only. No window, no ChatGPT.exe. For tests and agents.

.PARAMETER ParallelRoot
  Override install root (tests). Defaults to %LOCALAPPDATA%\CodexParallelDesktop.

.EXAMPLE
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\Show-CodexAccountApp.ps1

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Show-CodexAccountApp.ps1 -Headless
#>
[CmdletBinding()]
param(
    [switch]$Headless,
    [string]$ParallelRoot
)

$ErrorActionPreference = 'Stop'

function Get-AppScriptRoot {
    if ($PSScriptRoot) { return $PSScriptRoot }
    return (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

$script:AppScriptRoot = Get-AppScriptRoot
$core = Join-Path $script:AppScriptRoot 'CodexMultiProfile.psm1'
if (-not (Test-Path -LiteralPath $core)) {
    throw "Missing $core. Re-run Install-CodexMultiProfile.ps1."
}
Import-Module $core -Force
$routerMod = Join-Path $script:AppScriptRoot 'CodexRouter.psm1'
if (Test-Path -LiteralPath $routerMod) {
    Import-Module $routerMod -Force
}

if ([string]::IsNullOrWhiteSpace($ParallelRoot)) {
    $script:Root = Get-CodexParallelRoot
}
else {
    $script:Root = $ParallelRoot
}

function Format-AccountLastUsed {
    param($Value)
    if ($null -eq $Value) { return 'Never used' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Never used' }
    try {
        $dt = [datetime]$text
        $local = $dt.ToLocalTime()
        $age = (Get-Date) - $local
        if ($age.TotalMinutes -lt 1) { return 'Just now' }
        if ($age.TotalHours -lt 1) { return ('{0}m ago' -f [int]$age.TotalMinutes) }
        if ($age.TotalDays -lt 1) { return ('{0}h ago' -f [int]$age.TotalHours) }
        if ($age.TotalDays -lt 7) { return ('{0}d ago' -f [int]$age.TotalDays) }
        return $local.ToString('yyyy-MM-dd HH:mm')
    }
    catch {
        return $text
    }
}

function Format-StickyPaths {
    param($Paths)
    if ($null -eq $Paths) { return '' }
    $arr = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($arr.Count -eq 0) { return '' }
    $short = foreach ($p in $arr) {
        $s = [string]$p
        try {
            $leaf = Split-Path -Leaf $s
            $parent = Split-Path -Leaf (Split-Path -Parent $s)
            if ($parent) { '{0}\{1}' -f $parent, $leaf }
            else { $leaf }
        }
        catch { $s }
    }
    return ($short -join '  ·  ')
}

function Get-CodexAccountAppRows {
    param([string]$ParallelRoot = $script:Root)
    $rows = @()
    if (Get-Command Get-CodexProfilePool -ErrorAction SilentlyContinue) {
        $rows = @(Get-CodexProfilePool -ParallelRoot $ParallelRoot)
    }
    else {
        $names = @()
        if (Get-Command Get-CodexKnownProfileNames -ErrorAction SilentlyContinue) {
            $names = @(Get-CodexKnownProfileNames -ParallelRoot $ParallelRoot)
        }
        $rows = foreach ($name in $names) {
            $email = Get-AuthEmailFromFile -Path (Join-Path $ParallelRoot "profiles\$name\auth.json")
            [pscustomobject]@{
                Name     = $name
                Account  = Hide-AuthEmail -Email $email
                LastUsed = $null
                Depleted = $false
                Stickies = @()
            }
        }
    }

    $view = foreach ($row in $rows) {
        $email = [string]$row.Account
        $email = Hide-AuthEmail -Email $email
        $authPath = Join-Path $ParallelRoot ("profiles\{0}\auth.json" -f $row.Name)
        $hasAuth = Test-Path -LiteralPath $authPath
        $needsLogin = (-not $hasAuth) -or ($email -eq 'MISSING')
        $depleted = $false
        if ($row.PSObject.Properties['Depleted']) { $depleted = [bool]$row.Depleted }
        $sticky = ''
        if ($row.PSObject.Properties['Stickies']) { $sticky = Format-StickyPaths -Paths $row.Stickies }
        $lastRaw = $null
        if ($row.PSObject.Properties['LastUsed']) { $lastRaw = $row.LastUsed }
        $subBits = @()
        if ($needsLogin) { $subBits += 'Sign-in on first open (inside Codex)' }
        else { $subBits += $email }
        $subBits += (Format-AccountLastUsed -Value $lastRaw)
        if ($sticky) { $subBits += ('Sticky  ' + $sticky) }
        $depletedVis = 'Collapsed'
        if ($depleted) { $depletedVis = 'Visible' }
        [pscustomobject]@{
            Name               = [string]$row.Name
            Title              = ([string]$row.Name).ToUpperInvariant()
            Account            = $email
            LastUsed           = $lastRaw
            LastUsedText       = (Format-AccountLastUsed -Value $lastRaw)
            Depleted           = $depleted
            DepletedVisibility = $depletedVis
            StickyText         = $sticky
            Subtitle           = ($subBits -join '   ·   ')
            HasAuth            = $hasAuth
            NeedsLogin         = $needsLogin
        }
    }
    return @($view)
}

function Test-CodexAccountWindowOpen {
    param([string]$ParallelRoot = $script:Root)
    if (-not (Get-Command Get-CodexRunningProcesses -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        $running = @(Get-CodexRunningProcesses -ParallelRoot $ParallelRoot | Where-Object {
                $_.Kind -eq 'clone' -or $_.Kind -eq 'store'
            })
        return ($running.Count -gt 0)
    }
    catch {
        return $false
    }
}

function Get-LauncherPath {
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [string]$ParallelRoot = $script:Root
    )
    $candidates = @(
        (Join-Path $ParallelRoot $FileName),
        (Join-Path $script:AppScriptRoot $FileName)
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Start-CodexAccountProfile {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$ParallelRoot = $script:Root
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    $launch = Get-LauncherPath -FileName 'Launch-CodexProfile.ps1' -ParallelRoot $ParallelRoot
    if (-not $launch) {
        return [pscustomobject]@{
            Ok      = $false
            Blocked = $false
            Message = 'Missing Launch-CodexProfile.ps1. Re-run the installer.'
        }
    }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launch, '-Name', $key, '-FastSwitch'
    ) | Out-Null
    return [pscustomobject]@{
        Ok      = $true
        Blocked = $false
        Message = ("Switching to {0}…" -f $key)
    }
}

function Start-CodexAccountMain {
    param([string]$ParallelRoot = $script:Root)
    $launch = Get-LauncherPath -FileName 'Launch-CodexMain.ps1' -ParallelRoot $ParallelRoot
    if (-not $launch) {
        return [pscustomobject]@{
            Ok      = $false
            Blocked = $false
            Message = 'Missing Launch-CodexMain.ps1. Re-run the installer.'
        }
    }
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launch
    ) | Out-Null
    return [pscustomobject]@{
        Ok      = $true
        Blocked = $false
        Message = 'Opening Main…'
    }
}

function New-CodexAccountProfile {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [string]$ParallelRoot = $script:Root
    )
    $key = ConvertTo-ProfileKey -ProfileName $Name
    $manager = Get-LauncherPath -FileName 'CodexProfile.ps1' -ParallelRoot $ParallelRoot
    if (-not $manager) {
        throw 'Missing CodexProfile.ps1. Re-run the installer.'
    }
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $manager -Action new -Name $key 2>&1
    $code = $LASTEXITCODE
    if ($code -and $code -ne 0) {
        throw ("Create profile failed (exit {0}): {1}" -f $code, ($out | Out-String))
    }
    return $key
}

if ($Headless) {
    $rows = @(Get-CodexAccountAppRows -ParallelRoot $script:Root)
    $payload = [pscustomobject]@{
        ok       = $true
        ui       = $false
        count    = $rows.Count
        accounts = $rows
    }
    $json = $payload | ConvertTo-Json -Depth 6
    if ($json -match '@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -and $json -notmatch '\*\*\*@') {
        if ($json -match '[A-Za-z0-9._%+-]{3,}@[A-Za-z0-9.-]+\.[A-Za-z]{2,}') {
            throw 'Headless pool leaked a full email.'
        }
    }
    Write-Output $json
    return
}

# --- GUI (STA WPF) ----------------------------------------------------------
$apt = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apt -ne 'STA') {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = Join-Path $script:AppScriptRoot 'Show-CodexAccountApp.ps1' }
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
        '-File', $self
    )
    if ($ParallelRoot) { $argList += @('-ParallelRoot', $ParallelRoot) }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList | Out-Null
    return
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex Accounts"
        Width="480" Height="620"
        MinWidth="420" MinHeight="520"
        WindowStartupLocation="CenterScreen"
        Background="#0B0D10"
        Foreground="#F4F1EA"
        FontFamily="Segoe UI"
        FontSize="13"
        SnapsToDevicePixels="True"
        UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="GhostButton" TargetType="Button">
      <Setter Property="Background" Value="#161A20"/>
      <Setter Property="Foreground" Value="#F4F1EA"/>
      <Setter Property="BorderBrush" Value="#2A3038"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1E242C"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#3A424C"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#10141A"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource GhostButton}">
      <Setter Property="Background" Value="#10A37F"/>
      <Setter Property="Foreground" Value="#04140F"/>
      <Setter Property="BorderBrush" Value="#10A37F"/>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="card" Background="#14181E" BorderBrush="#222830"
                    BorderThickness="1" CornerRadius="10" Padding="14,12">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="card" Property="Background" Value="#1A1F26"/>
                <Setter TargetName="card" Property="BorderBrush" Value="#2E3540"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="card" Property="Background" Value="#12231D"/>
                <Setter TargetName="card" Property="BorderBrush" Value="#10A37F"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="20,18,20,16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" LastChildFill="True" Margin="0,0,0,16">
      <Button x:Name="RefreshBtn" DockPanel.Dock="Right" Style="{StaticResource GhostButton}"
              Content="Refresh" Margin="10,0,0,0" MinWidth="84"/>
      <StackPanel>
        <TextBlock Text="Codex Accounts" FontSize="22" FontWeight="SemiBold" Foreground="#F7F4EE"/>
        <TextBlock Text="Click a row to switch. One window." Margin="0,4,0,0"
                   Foreground="#8B93A0" FontSize="12"/>
      </StackPanel>
    </DockPanel>

    <Grid Grid.Row="1">
      <ListBox x:Name="AccountList" Background="Transparent" BorderThickness="0"
               ScrollViewer.HorizontalScrollBarVisibility="Disabled"
               ScrollViewer.VerticalScrollBarVisibility="Auto">
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Text="{Binding Title}" FontSize="14" FontWeight="SemiBold"
                           Foreground="#F4F1EA"/>
                <TextBlock Text="{Binding Subtitle}" Margin="0,4,0,0" TextWrapping="Wrap"
                           Foreground="#8B93A0" FontSize="12"/>
              </StackPanel>
              <Border Grid.Column="1" Margin="10,0,0,0" Padding="8,3" CornerRadius="8"
                      Background="#3A1F1F" VerticalAlignment="Top"
                      Visibility="{Binding DepletedVisibility}">
                <TextBlock Text="DEPLETED" Foreground="#F5A3A3" FontSize="10"
                           FontWeight="Bold"/>
              </Border>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>
      <TextBlock x:Name="EmptyHint" Text="No profiles yet. Add one — first open signs in inside Codex."
                 Foreground="#6B7380" FontSize="13" TextWrapping="Wrap"
                 HorizontalAlignment="Center" VerticalAlignment="Center"
                 Visibility="Collapsed" Margin="24"/>
    </Grid>

    <WrapPanel Grid.Row="2" Margin="0,14,0,10">
      <Button x:Name="OpenBtn" Style="{StaticResource AccentButton}" Content="Open" MinWidth="88" Margin="0,0,8,8"/>
      <Button x:Name="AddBtn" Style="{StaticResource GhostButton}" Content="Add profile" MinWidth="104" Margin="0,0,8,8"/>
      <Button x:Name="MainBtn" Style="{StaticResource GhostButton}" Content="Open Main" MinWidth="104" Margin="0,0,8,8"/>
      <Button x:Name="DepletedBtn" Style="{StaticResource GhostButton}" Content="Mark depleted" MinWidth="124" Margin="0,0,8,8"/>
    </WrapPanel>

    <TextBlock x:Name="StatusText" Grid.Row="3" Foreground="#6B7380" FontSize="11"
               TextWrapping="Wrap"
               Text="Authorized accounts you own. First-run login still happens inside Codex."/>
  </Grid>
</Window>
'@

function Show-AccountNotice {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$Title = 'Codex Accounts',
        [string]$Kind = 'Information'
    )
    try {
        [System.Windows.MessageBox]::Show($Message, $Title, 'OK', $Kind) | Out-Null
    }
    catch {
        Write-Output $Message
    }
}

function Show-AddAccountDialog {
    param($Owner)
    $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add profile" Width="360" Height="210"
        WindowStartupLocation="CenterOwner"
        Background="#0B0D10" Foreground="#F4F1EA"
        FontFamily="Segoe UI" FontSize="13"
        ResizeMode="NoResize" ShowInTaskbar="False">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="New profile name" FontWeight="SemiBold" Foreground="#F7F4EE"/>
    <TextBlock Grid.Row="1" Margin="0,6,0,10" Foreground="#8B93A0" FontSize="11"
               Text="Letters, numbers, hyphen. Sign-in still happens inside Codex on first open."
               TextWrapping="Wrap"/>
    <TextBox x:Name="NameBox" Grid.Row="2" Height="32" Padding="8,6"
             Background="#161A20" Foreground="#F4F1EA" BorderBrush="#2A3038"
             CaretBrush="#F4F1EA" Text="codex2"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
      <Button x:Name="CancelBtn" Width="88" Height="30" Margin="0,0,8,0" Content="Cancel"/>
      <Button x:Name="OkBtn" Width="88" Height="30" Content="Create" IsDefault="True"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse($dlgXaml)
    if ($Owner) { $dlg.Owner = $Owner }
    $box = $dlg.FindName('NameBox')
    $ok = $dlg.FindName('OkBtn')
    $cancel = $dlg.FindName('CancelBtn')
    $script:AddName = $null
    $ok.Add_Click({
            $script:AddName = $box.Text
            $dlg.DialogResult = $true
            $dlg.Close()
        })
    $cancel.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })
    $box.Add_GotFocus({
            if ($box.Text -eq 'codex2') { $box.SelectAll() }
        })
    $null = $dlg.ShowDialog()
    return $script:AddName
}

try {
    $window = [Windows.Markup.XamlReader]::Parse($xaml)
}
catch {
    Show-AccountNotice -Message $_.Exception.Message -Kind 'Error'
    throw
}

$list = $window.FindName('AccountList')
$empty = $window.FindName('EmptyHint')
$status = $window.FindName('StatusText')
$openBtn = $window.FindName('OpenBtn')
$addBtn = $window.FindName('AddBtn')
$mainBtn = $window.FindName('MainBtn')
$depBtn = $window.FindName('DepletedBtn')
$refreshBtn = $window.FindName('RefreshBtn')

function Set-Status([string]$Text) {
    $status.Text = $Text
}

function Get-SelectedAccount {
    return $list.SelectedItem
}

function Update-DepletedButton {
    $sel = Get-SelectedAccount
    if ($null -eq $sel) {
        $depBtn.Content = 'Mark depleted'
        $depBtn.IsEnabled = $false
        $openBtn.IsEnabled = $false
        return
    }
    $openBtn.IsEnabled = $true
    $depBtn.IsEnabled = $true
    if ($sel.Depleted) { $depBtn.Content = 'Clear depleted' }
    else { $depBtn.Content = 'Mark depleted' }
}

function Refresh-AccountList {
    param([string]$KeepName)
    $items = @(Get-CodexAccountAppRows -ParallelRoot $script:Root)
    $list.ItemsSource = $items
    if ($items.Count -eq 0) {
        $empty.Visibility = 'Visible'
        $list.SelectedIndex = -1
    }
    else {
        $empty.Visibility = 'Collapsed'
        $idx = 0
        if ($KeepName) {
            for ($i = 0; $i -lt $items.Count; $i++) {
                if ($items[$i].Name -eq $KeepName) { $idx = $i; break }
            }
        }
        $list.SelectedIndex = $idx
    }
    Update-DepletedButton
    $n = $items.Count
    $noun = 'account'
    if ($n -ne 1) { $noun = 'accounts' }
    Set-Status ("{0} {1}. Click a row to switch now. Saved logins do not ask for a password." -f $n, $noun)
}

function Invoke-OpenSelected {
    $sel = Get-SelectedAccount
    if ($null -eq $sel) {
        Set-Status 'Select an account first.'
        return
    }
    $result = Start-CodexAccountProfile -Name $sel.Name -ParallelRoot $script:Root
    Set-Status $result.Message
    if (-not $result.Ok) {
        Show-AccountNotice -Message $result.Message -Kind 'Error'
    }
}

$openBtn.Add_Click({ Invoke-OpenSelected })
$refreshBtn.Add_Click({ Refresh-AccountList -KeepName ((Get-SelectedAccount).Name) })
$mainBtn.Add_Click({
        $result = Start-CodexAccountMain -ParallelRoot $script:Root
        Set-Status $result.Message
        if (-not $result.Ok) { Show-AccountNotice -Message $result.Message -Kind 'Error' }
    })
$addBtn.Add_Click({
        $name = Show-AddAccountDialog -Owner $window
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        try {
            Set-Status 'Creating profile…'
            $key = New-CodexAccountProfile -Name $name -ParallelRoot $script:Root
            Refresh-AccountList -KeepName $key
            Set-Status ("Created {0}. Open it to sign in inside Codex (AuthSwap bootstrap)." -f $key)
        }
        catch {
            Show-AccountNotice -Message $_.Exception.Message -Kind 'Error'
            Set-Status $_.Exception.Message
        }
    })
$depBtn.Add_Click({
        $sel = Get-SelectedAccount
        if ($null -eq $sel) { return }
        if (-not (Get-Command Set-CodexProfileDepleted -ErrorAction SilentlyContinue)) {
            Show-AccountNotice -Message 'Router module missing. Re-run the installer.' -Kind 'Error'
            return
        }
        try {
            if ($sel.Depleted) {
                $null = Set-CodexProfileDepleted -Name $sel.Name -ParallelRoot $script:Root -Clear
                Set-Status ("Cleared depleted on {0}." -f $sel.Name)
            }
            else {
                $null = Set-CodexProfileDepleted -Name $sel.Name -ParallelRoot $script:Root
                Set-Status ("Marked {0} depleted. Next pick will skip it." -f $sel.Name)
            }
            Refresh-AccountList -KeepName $sel.Name
        }
        catch {
            Show-AccountNotice -Message $_.Exception.Message -Kind 'Error'
        }
    })
$list.Add_PreviewMouseLeftButtonUp({
        if ($null -ne $list.SelectedItem) { Invoke-OpenSelected }
    })
$list.Add_MouseDoubleClick({ Invoke-OpenSelected })
$list.Add_KeyDown({
        if ($_.Key -eq 'Return') {
            $_.Handled = $true
            Invoke-OpenSelected
        }
        elseif ($_.Key -eq 'F5') {
            $_.Handled = $true
            Refresh-AccountList -KeepName ((Get-SelectedAccount).Name)
        }
    })
$list.Add_SelectionChanged({ Update-DepletedButton })
$window.Add_KeyDown({
        if ($_.Key -eq 'F5') {
            $_.Handled = $true
            $keep = $null
            $sel = Get-SelectedAccount
            if ($sel) { $keep = $sel.Name }
            Refresh-AccountList -KeepName $keep
        }
        elseif ($_.Key -eq 'N' -and $_.KeyboardDevice.Modifiers -eq 'Control') {
            $_.Handled = $true
            $addBtn.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
        }
    })
$window.Add_Loaded({
        Refresh-AccountList
        $null = $list.Focus()
    })

[void]$window.ShowDialog()
