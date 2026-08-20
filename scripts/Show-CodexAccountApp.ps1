#Requires -Version 5.1
<#
.SYNOPSIS
  Codex Accounts - Windows desktop picker for multiple authorized ChatGPT logins.

.DESCRIPTION
  Standalone WPF app (PowerShell 5.1, no extra SDK). Lists AuthSwap profiles as
  selectable cards: name, masked email, last-used, depleted badge, sticky paths.
  Click / Enter closes any open Codex window, then AuthSwap-launches that
  saved profile (-FastSwitch). No second UI is left running.

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
    if ($null -eq $Value) { return 'Chua dung' }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return 'Chua dung' }
    try {
        $dt = [datetime]$text
        $local = $dt.ToLocalTime()
        $age = (Get-Date) - $local
        if ($age.TotalMinutes -lt 1) { return 'Vua xong' }
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
    return ($short -join ' - ')
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
        if ($needsLogin) { $subBits += 'Lan dau: dang nhap trong Codex' }
        else { $subBits += $email }
        $subBits += (Format-AccountLastUsed -Value $lastRaw)
        if ($sticky) { $subBits += ('Sticky  ' + $sticky) }
        $depletedVis = 'Collapsed'
        if ($depleted) { $depletedVis = 'Visible' }
        $nm = [string]$row.Name
        $initial = '?'
        if ($nm.Length -gt 0) { $initial = $nm.Substring(0, 1).ToUpperInvariant() }
        $hint = 'Bam de mo'
        if ($needsLogin) { $hint = 'Lan dau' }
        [pscustomobject]@{
            Name               = $nm
            Title              = $nm.ToUpperInvariant()
            Initial            = $initial
            ActionHint         = $hint
            Account            = $email
            LastUsed           = $lastRaw
            LastUsedText       = (Format-AccountLastUsed -Value $lastRaw)
            Depleted           = $depleted
            DepletedVisibility = $depletedVis
            StickyText         = $sticky
            Subtitle           = ($subBits -join '  -  ')
            HasAuth            = $hasAuth
            NeedsLogin         = $needsLogin
        }
    }
    return @($view)
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
        Message = ("Dang chuyen sang {0}..." -f $key)
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
        Message = 'Dang mo tai khoan chinh...'
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
        Width="560" Height="720"
        MinWidth="500" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        Background="#F6F1E8"
        Foreground="#2A241C"
        FontFamily="Segoe UI"
        FontSize="13"
        SnapsToDevicePixels="True"
        UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="GhostButton" TargetType="Button">
      <Setter Property="Background" Value="#FFF9F1"/>
      <Setter Property="Foreground" Value="#2A241C"/>
      <Setter Property="BorderBrush" Value="#D8CCB8"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="999" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#EFE4D2"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E4D6C0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource GhostButton}">
      <Setter Property="Background" Value="#3F6A4E"/>
      <Setter Property="Foreground" Value="#F7F2EA"/>
      <Setter Property="BorderBrush" Value="#3F6A4E"/>
    </Style>
    <Style TargetType="ListBoxItem">
      <Setter Property="Padding" Value="0"/>
      <Setter Property="Margin" Value="0,0,0,14"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="shell" Background="#E7DDD0" CornerRadius="22" Padding="3" Margin="0">
              <Border x:Name="card" Background="#FFF9F1" BorderBrush="#E6DCCE"
                      BorderThickness="1" CornerRadius="19" Padding="16,15">
                <ContentPresenter/>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="card" Property="Background" Value="#FFFDF8"/>
                <Setter TargetName="card" Property="BorderBrush" Value="#C9B89A"/>
                <Setter TargetName="shell" Property="Background" Value="#D9CDBB"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="card" Property="Background" Value="#F3F6F0"/>
                <Setter TargetName="card" Property="BorderBrush" Value="#3F6A4E"/>
                <Setter TargetName="shell" Property="Background" Value="#C9D6CB"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid Margin="28,26,28,8">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <DockPanel Grid.Row="0" LastChildFill="True" Margin="0,0,0,22">
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
          <Button x:Name="RefreshBtn" Style="{StaticResource GhostButton}" Content="Lam moi" MinWidth="96"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal">
          <Border Width="42" Height="42" CornerRadius="14" Background="#3F6A4E" Margin="0,2,14,0"
                  VerticalAlignment="Top">
            <TextBlock Text="C" FontFamily="Georgia" FontSize="22" FontWeight="Bold"
                       Foreground="#F6F1E8" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel>
            <TextBlock Text="CODEX" FontFamily="Georgia" FontSize="11" Foreground="#8A7D6C"/>
            <TextBlock Text="Tai khoan" FontFamily="Georgia" FontSize="28" FontWeight="Normal"
                       Foreground="#2A241C"/>
            <TextBlock Text="Bam mot the. Cua so nay o lai."
                       Margin="0,4,0,0" Foreground="#7A7164" FontSize="13"/>
          </StackPanel>
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
                  <ColumnDefinition Width="Auto"/>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border Width="48" Height="48" CornerRadius="24" Background="#E4EDE4"
                        Margin="0,0,14,0" VerticalAlignment="Center">
                  <TextBlock Text="{Binding Initial}" FontFamily="Georgia" FontSize="20"
                             Foreground="#3F6A4E" HorizontalAlignment="Center"
                             VerticalAlignment="Center"/>
                </Border>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <TextBlock Text="{Binding Title}" FontFamily="Georgia" FontSize="18"
                             Foreground="#2A241C"/>
                  <TextBlock Text="{Binding Subtitle}" Margin="0,5,0,0" TextWrapping="Wrap"
                             Foreground="#7A7164" FontSize="12"/>
                </StackPanel>
                <StackPanel Grid.Column="2" VerticalAlignment="Center" HorizontalAlignment="Right">
                  <Border Padding="10,3" CornerRadius="999" Background="#F3E1D6" Margin="0,0,0,8"
                          Visibility="{Binding DepletedVisibility}" HorizontalAlignment="Right">
                    <TextBlock Text="HET HAN" Foreground="#8A4B32" FontSize="10" FontWeight="Bold"/>
                  </Border>
                  <TextBlock Text="{Binding ActionHint}" Foreground="#3F6A4E" FontSize="11"
                             FontWeight="SemiBold" HorizontalAlignment="Right"/>
                </StackPanel>
              </Grid>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>
        <Border x:Name="EmptyHint" Visibility="Collapsed" HorizontalAlignment="Center"
                VerticalAlignment="Center" Background="#FFF9F1" BorderBrush="#E6DCCE"
                BorderThickness="1" CornerRadius="20" Padding="28,26" MaxWidth="360">
          <StackPanel>
            <TextBlock Text="Chua co nick" FontFamily="Georgia" FontSize="20"
                       Foreground="#2A241C" HorizontalAlignment="Center"/>
            <TextBlock Text="Bam Them nick. Lan dau dang nhap ngay trong Codex, khong can go so."
                       Margin="0,8,0,0" TextWrapping="Wrap" TextAlignment="Center"
                       Foreground="#7A7164" FontSize="13"/>
          </StackPanel>
        </Border>
      </Grid>

      <WrapPanel Grid.Row="2" Margin="0,18,0,4">
        <Button x:Name="OpenBtn" Style="{StaticResource AccentButton}" Content="Mo nick" MinWidth="108" Margin="0,0,8,8"/>
        <Button x:Name="AddBtn" Style="{StaticResource GhostButton}" Content="Them nick" MinWidth="108" Margin="0,0,8,8"/>
        <Button x:Name="MainBtn" Style="{StaticResource GhostButton}" Content="Tai khoan chinh" MinWidth="132" Margin="0,0,8,8"/>
        <Button x:Name="DepletedBtn" Style="{StaticResource GhostButton}" Content="Het han" MinWidth="96" Margin="0,0,8,8"/>
      </WrapPanel>
    </Grid>
    <Border Grid.Row="1" Background="#EFE6D7" Padding="28,14">
      <TextBlock x:Name="StatusText" Foreground="#5C5348" FontSize="12" TextWrapping="Wrap"
                 Text="Bam mot the. Nick da luu khong hoi password."/>
    </Border>
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
        Title="Them nick" Width="380" Height="230"
        WindowStartupLocation="CenterOwner"
        Background="#F3EEE4" Foreground="#2C261E"
        FontFamily="Segoe UI" FontSize="13"
        ResizeMode="NoResize" ShowInTaskbar="False">
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="Ten nick moi" FontWeight="SemiBold" Foreground="#2C261E" FontSize="16"/>
    <TextBlock Grid.Row="1" Margin="0,8,0,12" Foreground="#7A7166" FontSize="12"
               Text="Chu, so, gach ngang. Lan dau van dang nhap trong Codex."
               TextWrapping="Wrap"/>
    <TextBox x:Name="NameBox" Grid.Row="2" Height="36" Padding="10,8"
             Background="#FFFBF5" Foreground="#2C261E" BorderBrush="#D9CFC0"
             CaretBrush="#2C261E" Text="codex2"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="CancelBtn" Width="96" Height="34" Margin="0,0,8,0" Content="Huy"/>
      <Button x:Name="OkBtn" Width="96" Height="34" Content="Tao" IsDefault="True"/>
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
        $depBtn.Content = 'Het han'
        $depBtn.IsEnabled = $false
        $openBtn.IsEnabled = $false
        return
    }
    $openBtn.IsEnabled = $true
    $depBtn.IsEnabled = $true
    if ($sel.Depleted) { $depBtn.Content = 'Bo het han' }
    else { $depBtn.Content = 'Het han' }
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
    Set-Status ("{0} nick. Bam mot lan tren the. Cua so nay khong tat." -f $n)
}

$script:LastSwitchUtc = [datetime]::MinValue
function Invoke-OpenSelected {
    $now = [datetime]::UtcNow
    if (($now - $script:LastSwitchUtc).TotalSeconds -lt 1.5) {
        return
    }
    $sel = Get-SelectedAccount
    if ($null -eq $sel) {
        Set-Status 'Chon mot the truoc.'
        return
    }
    $script:LastSwitchUtc = $now
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
            Set-Status 'Dang tao nick...'
            $key = New-CodexAccountProfile -Name $name -ParallelRoot $script:Root
            Refresh-AccountList -KeepName $key
            Set-Status ("Da tao {0}. Bam the de dang nhap trong Codex (lan dau)." -f $key)
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
            Show-AccountNotice -Message 'Thieu router. Chay lai installer.' -Kind 'Error'
            return
        }
        try {
            if ($sel.Depleted) {
                $null = Set-CodexProfileDepleted -Name $sel.Name -ParallelRoot $script:Root -Clear
                Set-Status ("Da bo het han {0}." -f $sel.Name)
            }
            else {
                $null = Set-CodexProfileDepleted -Name $sel.Name -ParallelRoot $script:Root
                Set-Status ("Da danh het han {0}." -f $sel.Name)
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
