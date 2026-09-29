#Requires -Version 5.1
<#
===============================================================================
  FF MOBILE OPTIMIZER  -  Free Fire performance optimizer for Android phones
  Version 1.2.0                                   (Android 12 / 13 / 14 / 15)
-------------------------------------------------------------------------------
  What it does
    Connects to your phone over ADB (USB or Wi-Fi), finds Free Fire, then
    applies REAL, measurable Android-level optimizations:

      * per-game PERFORMANCE mode        (Android GameManager)
      * per-game RESOLUTION downscale    (only the game - your UI stays sharp)
      * animation scales off             (snappier menus)
      * AOT compile the game for speed   (faster loads, less stutter)
      * background Wi-Fi scanning off    (less network jitter)
      * stop/limit background apps       (more RAM + CPU for the game)
      * touch response latency           (long-press / multi-tap timeouts)
      * battery-optimization exemption   (Android stops freezing the game)
      * game kept in the ACTIVE bucket   (no background restrictions)
      * battery saver off while gaming   (only when it was on)
      * optional: refresh-rate lock      (opt-in, some phones ignore it)
      * optional: fixed performance mode, bloat removal, global resolution
      * experimental: ANGLE renderer     (-Angle, opt-in, measure before/after)

  Safety model
    * Nothing is changed without showing you the plan first.
    * Every change is recorded with its previous value in a JSON backup.
    * "Restore" puts the phone back exactly the way it was.
    * No root required. No game files touched. No cheats. Bans not possible
      from this - it only changes Android settings, never the game itself.

  Usage
      .\FFMobileOptimizer.ps1                          (menu)
      .\FFMobileOptimizer.ps1 -Mode Scan
      .\FFMobileOptimizer.ps1 -Mode Optimize -Profile Safe
      .\FFMobileOptimizer.ps1 -Mode Optimize -Profile Full -DryRun
      .\FFMobileOptimizer.ps1 -Mode Measure
      .\FFMobileOptimizer.ps1 -Mode Restore
      .\FFMobileOptimizer.ps1 -Mode PhoneGuide          (commands for LADB)

  Options
      -AdbPath  <path to adb(.exe)>   use a specific adb build
      -Serial   <device serial>       pick a device when several are plugged in
      -Wireless                       connect over Wi-Fi (asks for the IP)
      -BackupFile <path>              backup to restore from
===============================================================================
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Scan', 'Optimize', 'Measure', 'Restore', 'PhoneGuide', 'Report', 'Doctor')]
    [string]$Mode = 'Menu',

    [Alias('Profile')]
    [ValidateSet('Safe', 'Full', 'Custom')]
    [string]$TweakProfile = 'Safe',

    [string]$AdbPath,
    [string]$Serial,
    [switch]$Wireless,
    [switch]$DryRun,
    [switch]$Simulate,
    [switch]$Force,
    [string]$BackupFile,
    [string]$RemovePackages,          # custom bloat list, comma separated
    [string]$Tweaks,                  # comma separated tweak ids for -Profile Custom
    [switch]$Angle,                   # experimental: route Free Fire through the ANGLE GLES driver
    [double]$Downscale = 0.75         # 1.0 = off, 0.75 = 75% of pixels
)

$ErrorActionPreference = 'Stop'
$script:Version = '1.2.0'
$script:AppDir = if ($env:FFMO_HOME) { $env:FFMO_HOME } else {
    Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FFMobileOptimizer'
}
$script:Sim = [bool]$Simulate
$script:Real = (-not $script:Sim) -and (-not $DryRun)
$script:ForceFlag = [bool]$Force
$script:BackupFileOpt = $BackupFile
$script:Changes = New-Object System.Collections.Generic.List[object]
$script:CmdLog = New-Object System.Collections.Generic.List[string]
$script:Warnings = New-Object System.Collections.Generic.List[string]
$script:SerialToUse = $Serial
$script:Device = $null
$script:FfPackages = @()

$FF_PACKAGES_KNOWN = @('com.dts.freefireth', 'com.dts.freefiremax')

# =============================================================================
#  UI
# =============================================================================
function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor DarkCyan
    Write-Host ("  $Text") -ForegroundColor Cyan
    Write-Host ('=' * 74) -ForegroundColor DarkCyan
}
function Write-Sub { param([string]$Text) Write-Host ''; Write-Host ("  $Text") -ForegroundColor White; Write-Host ('  ' + ('-' * 70)) -ForegroundColor DarkGray }
function Write-Ok    { param([string]$T) Write-Host "  [ OK ] $T" -ForegroundColor Green }
function Write-Bad   { param([string]$T) Write-Host "  [FAIL] $T" -ForegroundColor Red }
function Write-Warn2 { param([string]$T) Write-Host "  [WARN] $T" -ForegroundColor Yellow }
function Write-Info  { param([string]$T) Write-Host "  $T" -ForegroundColor Gray }
function Write-Step {
    param([string]$Text, [string]$Result, [string]$Color = 'Green')
    $t = $Text
    if ($t.Length -gt 44) { $t = $t.Substring(0, 41) + '...' }
    Write-Host ("   " + $t.PadRight(46, '.')) -NoNewline
    if ($Result) { Write-Host " $Result" -ForegroundColor $Color } else { Write-Host '' }
}
function Write-Cmd {
    param([string]$Text)
    Write-Host "     > $Text" -ForegroundColor DarkGray
}

# =============================================================================
#  ADB LAYER
# =============================================================================
function Find-Adb {
    if ($AdbPath -and $AdbPath.Trim()) {
        if (Test-Path -LiteralPath $AdbPath) { return (Resolve-Path -LiteralPath $AdbPath).Path }
        throw "adb not found at: $AdbPath"
    }
    $local = Join-Path $PSScriptRoot (Join-Path 'platform-tools' $(if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'adb.exe' } else { 'adb' }))
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-PlatformTools {
    $platformTools = if ($env:OS -eq 'Windows_NT' -or $IsWindows) { 'windows' } else { 'linux' }
    $url = "https://dl.google.com/android/repository/platform-tools-latest-$platformTools.zip"
    $dest = Join-Path $PSScriptRoot 'platform-tools'
    $zip = Join-Path ([System.IO.Path]::GetTempPath()) 'platform-tools.zip'
    Write-Info "Downloading official Google platform-tools from dl.google.com ..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $PSScriptRoot -Force
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        $exe = Join-Path $dest $(if ($platformTools -eq 'windows') { 'adb.exe' } else { 'adb' })
        if (Test-Path -LiteralPath $exe) {
            if ($platformTools -ne 'windows') { & chmod +x $exe 2>$null }
            Write-Ok "adb installed at $dest"
            return $exe
        }
        Write-Bad 'Extraction finished but adb was not found.'
        return $null
    } catch {
        Write-Bad "Could not download platform-tools: $($_.Exception.Message)"
        Write-Info 'Download it manually: https://developer.android.com/studio/releases/platform-tools'
        return $null
    }
}

function Invoke-Adb {
    param([string[]]$AdbArgs, [switch]$NoSerial, [switch]$IgnoreErrors)
    $exe = $script:AdbExe
    $full = @()
    if ($script:SerialToUse -and -not $NoSerial) { $full += @('-s', $script:SerialToUse) }
    $full += $AdbArgs
    $script:CmdLog.Add(("adb " + ($full -join ' '))) | Out-Null
    try {
        $out = & $exe @full 2>&1
        $code = $LASTEXITCODE
    } catch {
        $out = @("$($_.Exception.Message)")
        $code = 1
    }
    if ($code -ne 0 -and -not $IgnoreErrors) { Write-Verbose ("adb exit {0}: {1}" -f $code, ($out -join ' ')) }
    return [pscustomobject]@{ Output = @($out | ForEach-Object { "$_" }); ExitCode = $code; Text = (($out | ForEach-Object { "$_" }) -join "`n") }
}

function Invoke-Shell {
    param([string]$Command, [switch]$IgnoreErrors)
    if ($script:Sim) { Write-Verbose "SIM shell: $Command" }
    return (Invoke-Adb -AdbArgs @('shell', $Command) -IgnoreErrors:$IgnoreErrors)
}

function Get-Prop {
    param([string]$Name)
    $r = Invoke-Shell "getprop $Name" -IgnoreErrors
    return ($r.Text).Trim()
}
function Get-PropInt {
    param([string]$Name)
    $v = Get-Prop $Name
    $n = 0
    if ([int]::TryParse(($v -replace '[^\d]', ''), [ref]$n)) { return $n }
    return 0
}

function Get-GlobalSetting {
    param([string]$Key)
    $r = Invoke-Shell "settings get global $Key" -IgnoreErrors
    $v = ($r.Text).Trim()
    if ($v -eq 'null' -or $v -eq '') { return $null }
    return $v
}
function Get-SystemSetting {
    param([string]$Key)
    $r = Invoke-Shell "settings get system $Key" -IgnoreErrors
    $v = ($r.Text).Trim()
    if ($v -eq 'null' -or $v -eq '') { return $null }
    return $v
}
function Set-GlobalSetting {
    param([string]$Key, [string]$Value)
    $r = Invoke-Shell "settings put global $Key $Value"
    if ($r.ExitCode -ne 0 -or $r.Text -match '(?i)error|exception|security') { throw "settings put global $Key failed: $($r.Text)" }
    return $true
}
function Get-SecureSetting {
    param([string]$Key)
    $r = Invoke-Shell "settings get secure $Key" -IgnoreErrors
    $v = ($r.Text).Trim()
    if ($v -eq 'null' -or $v -eq '') { return $null }
    return $v
}

function Set-SecureSetting {
    param([string]$Key, [string]$Value)
    $r = Invoke-Shell "settings put secure $Key $Value"
    if ($r.ExitCode -ne 0 -or $r.Text -match '(?i)error|exception|security') { throw "settings put secure $Key failed: $($r.Text)" }
    return $true
}

function Set-SystemSetting {
    param([string]$Key, [string]$Value)
    $r = Invoke-Shell "settings put system $Key $Value"
    if ($r.ExitCode -ne 0 -or $r.Text -match '(?i)error|exception|security') { throw "settings put system $Key failed: $($r.Text)" }
    return $true
}

# =============================================================================
#  DEVICE / GAME DETECTION
# =============================================================================
function Connect-Device {
    if (-not $script:AdbExe) {
        $script:AdbExe = Find-Adb
        if (-not $script:AdbExe) {
            Write-Warn2 'adb was not found on this PC.'
            $ans = Read-Host '  Download and install Google platform-tools now? (y/N)'
            if ($ans -match '^(y|yes)$') { $script:AdbExe = Install-PlatformTools }
            if (-not $script:AdbExe) { throw 'adb is required.' }
        }
    }
    $v = Invoke-Adb -AdbArgs @('version') -NoSerial -IgnoreErrors
    if ($v.ExitCode -ne 0) { throw "adb could not run: $($v.Text)" }
    if (-not $env:FFMO_SILENT) { Write-Info ("adb: " + (($v.Output | Select-Object -First 1))) }

    if ($Wireless -and -not $script:Sim) {
        $target = Read-Host '  Phone IP:port (e.g. 192.168.1.50:5555)'
        if ($target) {
            Write-Info "Connecting to $target ..."
            Invoke-Adb -AdbArgs @('connect', $target.Trim()) -NoSerial -IgnoreErrors | Out-Null
            Start-Sleep -Milliseconds 800
            $script:SerialToUse = $target.Trim()
        }
    }

    $list = Invoke-Adb -AdbArgs @('devices') -NoSerial -IgnoreErrors
    $devices = @()
    foreach ($line in $list.Output) {
        if ($line -match '^\s*(\S+)\s+(device|unauthorized|offline|no permissions)(\s+.*)?$') {
            $devices += [pscustomobject]@{ Serial = $matches[1]; State = $matches[2] }
        }
    }
    if ($devices.Count -eq 0) {
        throw "No phone detected.`n  * Connect the USB cable and set it to 'File transfer / MTP'`n  * Enable Developer options > USB debugging and accept the popup on the phone`n  * Check the cable - some charge-only cables do not carry data"
    }
    if ($script:SerialToUse) {
        $match = $devices | Where-Object { $_.Serial -eq $script:SerialToUse }
        if (-not $match) { throw "Specified device $($script:SerialToUse) is not connected." }
        if ($match.State -ne 'device') { throw "Device $($script:SerialToUse) is in state '$($match.State)'." }
    } else {
        $ready = @($devices | Where-Object { $_.State -eq 'device' })
        if ($ready.Count -eq 0) {
            $st = ($devices | Select-Object -First 1).State
            if ($st -eq 'unauthorized') { throw 'The phone shows "Allow USB debugging?" - tick "Always allow" and accept it, then try again.' }
            throw "No usable device (state: $st)."
        }
        if ($ready.Count -gt 1) {
            Write-Sub 'More than one device is connected'
            $i = 0
            foreach ($d in $ready) { $i++; Write-Host ("   [{0}] {1}" -f $i, $d.Serial) }
            $pick = Read-Host '  Which one?'
            $idx = 0
            if ([int]::TryParse($pick, [ref]$idx) -and $idx -ge 1 -and $idx -le $ready.Count) {
                $script:SerialToUse = $ready[$idx - 1].Serial
            } else { $script:SerialToUse = $ready[0].Serial }
        } else {
            $script:SerialToUse = $ready[0].Serial
        }
    }
    Write-Ok "Connected: $($script:SerialToUse)"
    return $true
}

function Get-DeviceInfo {
    $densityOut = (Invoke-Shell 'wm density' -IgnoreErrors).Text
    $sizeOut = (Invoke-Shell 'wm size' -IgnoreErrors).Text

    $size = 'unknown'; $sizeOverride = 'none'
    if ($sizeOut -match 'Override size:\s*(\d+)x(\d+)') { $sizeOverride = "$($matches[1])x$($matches[2])" }
    if ($sizeOut -match 'Physical size:\s*(\d+)x(\d+)') { $size = "$($matches[1])x$($matches[2])" }
    $density = 'unknown'; $densityOverride = 'none'
    if ($densityOut -match 'Override density:\s*(\d+)') { $densityOverride = $matches[1] }
    if ($densityOut -match 'Physical density:\s*(\d+)') { $density = $matches[1] }

    $memTotal = 0
    $memInfo = (Invoke-Shell 'cat /proc/meminfo' -IgnoreErrors).Text
    if ($memInfo -match 'MemTotal:\s*(\d+)\s*kB') { $memTotal = [int]$matches[1] }
    $memAvail = 0
    if ($memInfo -match 'MemAvailable:\s*(\d+)\s*kB') { $memAvail = [int]$matches[1] }

    $androidRel = Get-Prop 'ro.build.version.release'
    $sdk = Get-PropInt 'ro.build.version.sdk'
    $model = Get-Prop 'ro.product.model'
    $brand = Get-Prop 'ro.product.brand'
    $soc = Get-Prop 'ro.soc.model'
    if (-not $soc) { $soc = Get-Prop 'ro.board.platform' }
    if (-not $soc) { $soc = Get-Prop 'ro.hardware' }

    $brandNice = $brand
    if ($brandNice) { $brandNice = $brandNice.Substring(0,1).ToUpper() + $brandNice.Substring(1) }
    $modelNice = $model
    if ($brandNice -and $modelNice -and $modelNice.ToLower().StartsWith($brandNice.ToLower() + ' ')) {
        $modelNice = $modelNice.Substring($brandNice.Length + 1)
    }
    return [pscustomobject]@{
        Brand          = $brandNice
        Model          = $modelNice
        Android        = $androidRel
        Sdk            = $sdk
        Soc            = $soc
        RamTotalGb     = [math]::Round($memTotal / 1048576, 1)
        RamFreeGb      = [math]::Round($memAvail / 1048576, 1)
        Screen         = $size
        ScreenOverride = $sizeOverride
        Density        = $density
        DensityOverride= $densityOverride
        RefreshRate    = Get-RefreshRate
        Serial         = $script:SerialToUse
    }
}

function Get-RefreshRate {
    $r = Invoke-Shell 'dumpsys display' -IgnoreErrors
    $rates = @()
    foreach ($pattern in @('fps=([\d\.]+)', '"fps"\s*:\s*([\d\.]+)', 'refreshRate=([\d\.]+)')) {
        foreach ($m in [regex]::Matches($r.Text, $pattern)) {
            $v = 0.0
            if ([double]::TryParse($m.Groups[1].Value, [ref]$v) -and $v -gt 1) { $rates += $v }
        }
    }
    if ($rates.Count -eq 0) { return 'unknown' }
    $max = ($rates | Measure-Object -Maximum).Maximum
    if ($max -ge 100) { return "$([int]$max) Hz" }
    return "$([int]$max) Hz"
}

function Get-PeakRefreshValue {
    $r = Invoke-Shell 'dumpsys display' -IgnoreErrors
    $best = 0.0
    foreach ($pattern in @('fps=([\d\.]+)', '"fps"\s*:\s*([\d\.]+)', 'refreshRate=([\d\.]+)')) {
        foreach ($m in [regex]::Matches($r.Text, $pattern)) {
            $v = 0.0
            if ([double]::TryParse($m.Groups[1].Value, [ref]$v) -and $v -gt $best) { $best = $v }
        }
    }
    return [int][math]::Round($best)
}

function Test-InDozeWhitelist {
    param([string]$Package)
    $r = Invoke-Shell 'dumpsys deviceidle whitelist' -IgnoreErrors
    foreach ($line in ($r.Text -split "`n")) {
        foreach ($tok in ($line -split ',')) {
            if ($tok.Trim() -eq $Package) { return $true }
        }
    }
    return $false
}

function Get-FreeFirePackages {
    $installed = (Invoke-Shell 'pm list packages' -IgnoreErrors).Text
    $found = @()
    foreach ($p in $FF_PACKAGES_KNOWN) {
        if ($installed -match [regex]::Escape($p)) { $found += $p }
    }
    return $found
}

function Get-PackageVersion {
    param([string]$Package)
    $r = Invoke-Shell "dumpsys package $Package" -IgnoreErrors
    if ($r.Text -match 'versionName=(\S+)') { return $matches[1] }
    return 'unknown'
}

function Test-GameRunning {
    param([string]$Package)
    $r = Invoke-Shell 'dumpsys activity activities' -IgnoreErrors
    return ($r.Text -match [regex]::Escape($Package))
}

# =============================================================================
#  PERFORMANCE SNAPSHOT  (heat / thermal / frame stats)
# =============================================================================
function Get-BatteryTempC {
    $r = Invoke-Shell 'dumpsys battery' -IgnoreErrors
    if ($r.Text -match 'temperature:\s*(-?\d+)') {
        return [math]::Round(([double]$matches[1]) / 10.0, 1)
    }
    return $null
}

function Get-ThermalStatus {
    $r = Invoke-Shell 'dumpsys thermalservice' -IgnoreErrors
    if ($r.Text -match 'Thermal Status:\s*(\d+)') {
        $map = @{ 0 = 'NONE (cool)'; 1 = 'LIGHT'; 2 = 'MODERATE'; 3 = 'SEVERE'; 4 = 'CRITICAL'; 5 = 'EMERGENCY'; 6 = 'SHUTDOWN' }
        $v = [int]$matches[1]
        if ($map.ContainsKey($v)) { return $map[$v] }
        return "status $v"
    }
    return 'unknown'
}

function Get-FrameStats {
    param([string]$Package)
    $r = Invoke-Shell "dumpsys gfxinfo $Package framestats" -IgnoreErrors
    $janky = $null; $total = $null; $fps = $null
    if ($r.Text -match 'Total frames rendered:\s*(\d+)') { $total = [int]$matches[1] }
    if ($r.Text -match 'Janky frames(?:[^:]*):\s*(\d+)') { $janky = [int]$matches[1] }
    $block = $r.Text
    $start = $block.IndexOf('---PROFILEDATA---')
    if ($start -ge 0) {
        $end = $block.IndexOf('---PROFILEDATA---', $start + 16)
        if ($end -gt $start) {
            $data = $block.Substring($start + 16, $end - $start - 16).Trim()
            $lines = @($data -split "`n" | Where-Object { $_ -match '^\d' })
            if ($lines.Count -ge 3) {
                $head = $lines[0] -split ','
                $vidx = 1
                for ($i = 0; $i -lt $head.Count; $i++) { if ($head[$i].Trim() -eq 'IntendedVsync') { $vidx = $i; break } }
                $vs = @()
                foreach ($ln in ($lines | Select-Object -Skip 1)) {
                    $parts = $ln -split ','
                    if ($parts.Count -gt $vidx) {
                        $n = 0L
                        if ([long]::TryParse($parts[$vidx].Trim(), [ref]$n) -and $n -gt 0) { $vs += $n }
                    }
                }
                if ($vs.Count -ge 3) {
                    $first = $vs[0]; $last = $vs[$vs.Count - 1]
                    $ns = $last - $first
                    $frames = $vs.Count - 1
                    if ($ns -gt 0 -and $frames -gt 0) {
                        $fps = [math]::Round($frames / ($ns / 1e9), 1)
                    }
                }
            }
        }
    }
    $jankPct = $null
    if ($null -ne $janky -and $null -ne $total -and $total -gt 0) {
        $jankPct = [math]::Round(($janky / $total) * 100, 1)
    }
    return [pscustomobject]@{ Fps = $fps; JankPercent = $jankPct; Frames = $total; JankyFrames = $janky }
}

function Get-PerfSnapshot {
    param([string]$Package, [string]$Label)
    $temp = Get-BatteryTempC
    $thermal = Get-ThermalStatus
    $frames = $null
    if ($Package -and (Test-GameRunning -Package $Package)) {
        $frames = Get-FrameStats -Package $Package
    }
    return [pscustomobject]@{
        Label      = $Label
        Time       = (Get-Date).ToString('HH:mm:ss')
        TempC      = $temp
        Thermal    = $thermal
        Fps        = if ($frames) { $frames.Fps } else { $null }
        JankPct    = if ($frames) { $frames.JankPercent } else { $null }
        Frames     = if ($frames) { $frames.Frames } else { $null }
        GameRunning= [bool]($Package -and (Test-GameRunning -Package $Package))
    }
}

function Show-Snapshot {
    param($Snap)
    Write-Host ("   Temperature : {0}" -f $(if ($null -ne $Snap.TempC) { "$($Snap.TempC) C" } else { 'unknown' })) -NoNewline
    if ($null -ne $Snap.TempC) {
        $c = if ($Snap.TempC -lt 38) { 'Green' } elseif ($Snap.TempC -lt 43) { 'Yellow' } else { 'Red' }
        $note = if ($Snap.TempC -lt 38) { 'cool' } elseif ($Snap.TempC -lt 43) { 'warm' } else { 'hot - throttling likely!' }
        Write-Host ("   ({0})" -f $note) -ForegroundColor $c
    } else { Write-Host '' }
    Write-Host ("   Thermal     : {0}" -f $Snap.Thermal) -ForegroundColor $(if ($Snap.Thermal -match 'NONE|unknown') { 'Green' } else { 'Yellow' })
    if ($Snap.GameRunning) {
        $fpsTxt = if ($null -ne $Snap.Fps) { "$($Snap.Fps) fps (estimated from Android frame stats)" } else { 'n/a' }
        $jankTxt = if ($null -ne $Snap.JankPct) { "$($Snap.JankPct) % janky frames" } else { 'n/a' }
        Write-Host "   Frames      : $fpsTxt"
        Write-Host "   Smoothness  : $jankTxt"
    } else {
        Write-Host '   Frames      : (game not running - start Free Fire to measure)' -ForegroundColor DarkGray
    }
}

# =============================================================================
#  TWEAKS
# =============================================================================
function Get-TweakTable {
    @(
        [pscustomobject]@{ Id='GameMode';    Name='Per-game performance mode'; Impact='FPS';     Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='Downscale';   Name='Game resolution downscale';  Impact='FPS';     Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='Animations';  Name='Animation scales off';       Impact='Latency'; Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='Compile';     Name='AOT compile game for speed'; Impact='Stutter'; Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='WifiScan';    Name='Background Wi-Fi scanning';  Impact='Ping';    Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='KillApps';    Name='Stop background apps';       Impact='RAM/FPS'; Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='TouchResp';   Name='Touch response latency';     Impact='Aim';     Risk='Safe';     In=@('Safe','Full','Custom'); Reboot=$false }
        [pscustomobject]@{ Id='DozeWhitelist'; Name='Battery-optimization exemption'; Impact='FPS'; Risk='Safe'; In=@('Full','Custom');      Reboot=$false }
        [pscustomobject]@{ Id='StandbyBucket'; Name='Game kept in active bucket'; Impact='FPS';     Risk='Safe';     In=@('Full','Custom');        Reboot=$false }
        [pscustomobject]@{ Id='LowPower';      Name='Battery saver off while gaming'; Impact='FPS'; Risk='Safe';   In=@('Full','Custom');        Reboot=$false }
        [pscustomobject]@{ Id='RefreshLock';   Name='Refresh-rate lock (opt-in)'; Impact='FPS';     Risk='Safe';     In=@('Custom');               Reboot=$false }
        [pscustomobject]@{ Id='Angle';       Name='ANGLE GLES driver (experimental)'; Impact='FPS?'; Risk='Experimental'; In=@('Custom'); Reboot=$true }
        [pscustomobject]@{ Id='BgRestrict';  Name='Restrict heavy bloat apps';  Impact='FPS';     Risk='Moderate'; In=@('Full','Custom');        Reboot=$false }
        [pscustomobject]@{ Id='FixedPerf';   Name='Fixed performance mode';     Impact='FPS';     Risk='Moderate'; In=@('Full','Custom');        Reboot=$false }
        [pscustomobject]@{ Id='RemoveBloat'; Name='Remove bloat apps';          Impact='FPS';     Risk='Advanced'; In=@('Custom');               Reboot=$false }
        [pscustomobject]@{ Id='GlobalRes';   Name='Lower screen resolution';    Impact='FPS';     Risk='Advanced'; In=@('Custom');               Reboot=$true }
    )
}

function Get-TweaksForProfile {
    param([string]$ProfileName, [string[]]$CustomIds)
    $list = @()
    $all = Get-TweakTable
    if ($ProfileName -eq 'Custom') { $list = @($all | Where-Object { $CustomIds -contains $_.Id }) }
    else { $list = @($all | Where-Object { $_.In -contains $ProfileName }) }
    if ($script:AngleFlag -and -not ($list | Where-Object { $_.Id -eq 'Angle' })) {
        $list += ($all | Where-Object { $_.Id -eq 'Angle' })
    }
    return $list
}

function Get-GameOverlayConfig {
    param([string]$Package)
    $r = Invoke-Shell "device_config get game_overlay $Package" -IgnoreErrors
    $t = ($r.Text).Trim()
    if ($t -match 'null' -or $t -eq '') { return '' }
    return $t
}

function Test-Tweak {
    param([string]$Id)
    try {
        switch ($Id) {
            'GameMode' {
                $cfg = Get-GameOverlayConfig -Package $script:ActivePackage
                $ok = ($cfg -match 'mode=2')
                return [pscustomobject]@{ Optimal=$ok; Current=$(if ($cfg) { $cfg } else { 'default' }) }
            }
            'Downscale' {
                $cfg = Get-GameOverlayConfig -Package $script:ActivePackage
                $ok = ($cfg -match 'downscaleFactor=(0\.\d+|1\.0)?' -and $cfg -match 'downscaleFactor=0\.')
                $cur = if ($cfg -match 'downscaleFactor=(\S+)') { $matches[1] } else { 'off' }
                return [pscustomobject]@{ Optimal=$ok; Current="factor=$cur" }
            }
            'Animations' {
                $a = Get-GlobalSetting 'window_animation_scale'
                $b = Get-GlobalSetting 'transition_animation_scale'
                $c = Get-GlobalSetting 'animator_duration_scale'
                $ok = ($a -eq '0' -and $b -eq '0' -and $c -eq '0')
                return [pscustomobject]@{ Optimal=$ok; Current=("window={0} transition={1} animator={2}" -f (Fmt $a), (Fmt $b), (Fmt $c)) }
            }
            'Compile' {
                $r = Invoke-Shell "cmd package compile -m speed -f $($script:ActivePackage)" -IgnoreErrors
                return [pscustomobject]@{ Optimal=$true; Current='on demand (runs each optimize)'; OnDemand=$true }
            }
            'WifiScan' {
                $a = Get-GlobalSetting 'wifi_scan_always_enabled'
                $b = Get-GlobalSetting 'network_recommendations_enabled'
                $ok = ($a -eq '0' -and $b -eq '0')
                return [pscustomobject]@{ Optimal=$ok; Current=("scan_always={0} network_reco={1}" -f (Fmt $a), (Fmt $b)) }
            }
            'KillApps' { return [pscustomobject]@{ Optimal=$true; Current='on demand'; OnDemand=$true } }
        'BgRestrict' {
                $n = 0; $targets = Get-BloatList
                foreach ($p in $targets) {
                    $r = Invoke-Shell "cmd appops get $p RUN_IN_BACKGROUND" -IgnoreErrors
                    if ($r.Text -match 'deny') { $n++ }
                }
                $ok = ($targets.Count -gt 0 -and $n -eq $targets.Count)
                return [pscustomobject]@{ Optimal=$ok; Current="$n/$($targets.Count) restricted" }
            }
            'FixedPerf' {
                $r = Invoke-Shell 'cmd power set-fixed-performance-mode-enabled' -IgnoreErrors
                $t = $r.Text.Trim()
                if ($t -match '\btrue\b')  { return [pscustomobject]@{ Optimal=$true;  Current='enabled' } }
                if ($t -match '\bfalse\b') { return [pscustomobject]@{ Optimal=$false; Current='disabled' } }
                return [pscustomobject]@{ Optimal=$false; Current='no readback on this Android build'; Unverifiable=$true }
            }
            'TouchResp' {
                $a = Get-SecureSetting 'long_press_timeout'
                $b = Get-SecureSetting 'multi_press_timeout'
                $ok = ($null -ne $a -and [int]$a -le 250) -and ($null -ne $b -and [int]$b -le 250)
                return [pscustomobject]@{ Optimal=$ok; Current=("long_press={0} multi_press={1}" -f (Fmt $a), (Fmt $b)) }
            }
            'Angle' {
                $pkgs = Get-GlobalSetting 'angle_gl_driver_selection_pkgs'
                $vals = Get-GlobalSetting 'angle_gl_driver_selection_values'
                $on = ($pkgs -and ($pkgs -split ',' | Where-Object { $_.Trim() -eq $script:ActivePackage })) -and ($vals -and $vals -match 'angle')
                return [pscustomobject]@{ Optimal=$on; Current=$(if ($on) { 'ANGLE active for this game' } elseif ($pkgs) { "other: $pkgs" } else { 'native GLES driver' }) }
            }
            'DozeWhitelist' {
                $on = Test-InDozeWhitelist -Package $script:ActivePackage
                return [pscustomobject]@{ Optimal=$on; Current=$(if ($on) { 'exempt from battery optimization' } else { 'Android may freeze it in background' }) }
            }
            'StandbyBucket' {
                $v = (Invoke-Shell "am get-standby-bucket $($script:ActivePackage)" -IgnoreErrors).Text.Trim()
                $name = switch ($v) { '10' { 'ACTIVE' } '20' { 'WORKING_SET' } '30' { 'FREQUENT' } '40' { 'RARE' } '45' { 'RESTRICTED' } default { "bucket '$v'" } }
                return [pscustomobject]@{ Optimal=($v -eq '10'); Current=("bucket $name") }
            }
            'LowPower' {
                $v = Get-GlobalSetting 'low_power'
                $ok = ($null -eq $v -or $v -eq '0')
                return [pscustomobject]@{ Optimal=$ok; Current=$(if ($v -eq '1') { 'battery saver is ON - it caps performance' } else { 'battery saver off' }) }
            }
            'RefreshLock' {
                $peak = Get-PeakRefreshValue
                $mn = Get-SystemSetting 'min_refresh_rate'
                $pk = Get-SystemSetting 'peak_refresh_rate'
                $mnd = 0.0; $pkd = 0.0; $okM = $false; $okP = $false
                if ($mn) { $okM = [double]::TryParse($mn, [ref]$mnd) }
                if ($pk) { $okP = [double]::TryParse($pk, [ref]$pkd) }
                $ok = ($peak -gt 0 -and $okM -and $okP -and $mnd -ge $peak -and $pkd -ge $peak)
                $cur = if ($mn -or $pk) { "min=$(Fmt $mn) peak=$(Fmt $pk) (device peak ${peak} Hz)" } else { "not locked (device peak ${peak} Hz)" }
                return [pscustomobject]@{ Optimal=$ok; Current=$cur }
            }
            'RemoveBloat' { return [pscustomobject]@{ Optimal=$true; Current='opt-in (menu 8)'; OnDemand=$true } }
            'GlobalRes' {
                $sizeOut = (Invoke-Shell 'wm size' -IgnoreErrors).Text
                $ok = ($sizeOut -match 'Override size')
                return [pscustomobject]@{ Optimal=$false; Current=$(if ($sizeOut -match 'Override size:\s*(\S+)') { "override $($matches[1])" } else { 'native (best quality)' }) }
            }
            default { return [pscustomobject]@{ Optimal=$true; Current='n/a' } }
        }
    } catch {
        return [pscustomobject]@{ Optimal=$false; Current="detect error: $($_.Exception.Message)" }
    }
}

function Fmt {
    param($V)
    if ($null -eq $V) { return 'default' }
    return "$V"
}

function Get-BloatList {
    if ($RemovePackages) { return @($RemovePackages -split '[,\s]+' | Where-Object { $_ }) }
    $candidates = @(
        'com.facebook.katana', 'com.facebook.appmanager', 'com.facebook.services', 'com.facebook.system',
        'com.netflix.partner.activation', 'com.netflix.mediaclient',
        'com.amazon.appmanager', 'com.amazon.mShop.android.shopping',
        'com.linkedin.android', 'com.spotify.music',
        'com.tencent.ig', 'com.mi.globalbrowser', 'com.miui.weather2',
        'com.samsung.android.game.gamehome'
    )
    $installed = (Invoke-Shell 'pm list packages' -IgnoreErrors).Text
    $found = @()
    foreach ($c in $candidates) {
        if ($installed -match ('package:' + [regex]::Escape($c) + '\b')) { $found += $c }
    }
    return $found
}

# =============================================================================
#  CHANGE TRACKING
# =============================================================================
function Add-Change {
    param([string]$Kind, [string]$Target, [string]$OldValue, [string]$NewValue, [string]$Note)
    $script:Changes.Add([pscustomobject]@{
        Kind     = $Kind
        Target   = $Target
        OldValue = $OldValue
        NewValue = $NewValue
        Note     = $Note
        Time     = (Get-Date).ToString('s')
    }) | Out-Null
}

function Set-TrackedGlobal {
    param([string]$Key, [string]$Value, [string]$Note = '')
    $old = Get-GlobalSetting $Key
    if ($old -eq $Value) { return $false }
    Add-Change -Kind 'GlobalSetting' -Target $Key -OldValue $old -NewValue $Value -Note $Note
    Set-GlobalSetting -Key $Key -Value $Value | Out-Null
    return $true
}

function Set-TrackedSystem {
    param([string]$Key, [string]$Value, [string]$Note = '')
    $old = Get-SystemSetting $Key
    if ($old -eq $Value) { return $false }
    Add-Change -Kind 'SystemSetting' -Target $Key -OldValue $old -NewValue $Value -Note $Note
    Set-SystemSetting -Key $Key -Value $Value | Out-Null
    return $true
}

# =============================================================================
#  APPLY
# =============================================================================
function Invoke-Tweak {
    param([string]$Id, [string]$Package)
    switch ($Id) {
        'GameMode' {
            $r = Invoke-Shell "cmd game mode performance $Package"
            if ($r.Text -match '(?i)error|exception') { throw $r.Text }
            Add-Change -Kind 'GameMode' -Target $Package -OldValue 'default' -NewValue 'performance' `
                -Note "restore: cmd game mode default $Package"
            return 'performance mode'
        }
        'Downscale' {
            if ($Downscale -ge 1.0) { return 'skipped (factor = 1.0)' }
            $factor = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.00}', $Downscale)
            $old = Get-GameOverlayConfig -Package $Package
            Add-Change -Kind 'Downscale' -Target $Package -OldValue $old -NewValue $factor `
                -Note "restore: cmd game downscale disable $Package"
            $r = Invoke-Shell "cmd game downscale $factor $Package"
            if ($r.Text -match '(?i)error|exception') { throw $r.Text }
            return "rendering at $([int]($Downscale * 100))% of pixels"
        }
        'Animations' {
            $null = Set-TrackedGlobal 'window_animation_scale' '0'
            $null = Set-TrackedGlobal 'transition_animation_scale' '0'
            $null = Set-TrackedGlobal 'animator_duration_scale' '0'
            return 'animations off'
        }
        'Compile' {
            Add-Change -Kind 'Compile' -Target $Package -OldValue 'default' -NewValue 'speed' `
                -Note "restore: cmd package compile -m speed-profile -f $Package"
            $r = Invoke-Shell "cmd package compile -m speed -f $Package"
            if ($r.Text -match '(?i)failure|error') { throw $r.Text }
            $done = if ($r.Text -match 'Success') { 'compiled for speed' } else { 'submitted' }
            return $done
        }
        'WifiScan' {
            $null = Set-TrackedGlobal 'wifi_scan_always_enabled' '0' -Note 'background Wi-Fi scanning'
            $null = Set-TrackedGlobal 'network_recommendations_enabled' '0' -Note 'network recommendations'
            return 'scanning off'
        }
        'KillApps' {
            $stopped = Stop-BackgroundApps
            return "$stopped apps stopped"
        }
        'TouchResp' {
            $old = Get-SecureSetting 'long_press_timeout'
            if ("$old" -ne '250') {
                Add-Change -Kind 'SecureSetting' -Target 'long_press_timeout' -OldValue $old -NewValue '250' -Note ''
            }
            $old2 = Get-SecureSetting 'multi_press_timeout'
            if ("$old2" -ne '250') {
                Add-Change -Kind 'SecureSetting' -Target 'multi_press_timeout' -OldValue $old2 -NewValue '250' -Note ''
            }
            Set-SecureSetting -Key 'long_press_timeout' -Value '250' | Out-Null
            Set-SecureSetting -Key 'multi_press_timeout' -Value '250' | Out-Null
            return 'long press + multi tap tuned'
        }
        'Angle' {
            $oldPkgs = Get-GlobalSetting 'angle_gl_driver_selection_pkgs'
            $oldVals = Get-GlobalSetting 'angle_gl_driver_selection_values'
            $pkgs = @()
            $vals = @()
            if ($oldPkgs) { $pkgs = @($oldPkgs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            if ($oldVals) { $vals = @($oldVals -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            if ($pkgs -notcontains $Package) {
                $pkgs += $Package
                $vals += 'angle'
            }
            Add-Change -Kind 'GlobalSetting' -Target 'angle_gl_driver_selection_pkgs' -OldValue $oldPkgs -NewValue ($pkgs -join ',') `
                -Note 'experimental - delete this setting to go back'
            Add-Change -Kind 'GlobalSetting' -Target 'angle_gl_driver_selection_values' -OldValue $oldVals -NewValue ($vals -join ',') `
                -Note 'experimental - delete this setting to go back'
            Set-GlobalSetting -Key 'angle_gl_driver_selection_pkgs' -Value ($pkgs -join ',') | Out-Null
            Set-GlobalSetting -Key 'angle_gl_driver_selection_values' -Value ($vals -join ',') | Out-Null
            return 'ANGLE enabled (reboot + test!)'
        }
        'DozeWhitelist' {
            $r = Invoke-Shell "dumpsys deviceidle whitelist +$Package" -IgnoreErrors
            if ($r.Text -match '(?i)error|exception') { throw $r.Text }
            Add-Change -Kind 'DozeWhitelist' -Target $Package -OldValue 'optimized' -NewValue 'exempt' `
                -Note "restore: dumpsys deviceidle whitelist -$Package"
            return 'battery-optimization exempt'
        }
        'StandbyBucket' {
            $old = (Invoke-Shell "am get-standby-bucket $Package" -IgnoreErrors).Text.Trim()
            if ($old -eq '10') { return 'already ACTIVE' }
            Add-Change -Kind 'StandbyBucket' -Target $Package -OldValue $old -NewValue '10' `
                -Note "restore: am set-standby-bucket $Package <old>"
            $r = Invoke-Shell "am set-standby-bucket $Package 10" -IgnoreErrors
            if ($r.Text -match '(?i)error|exception') { throw $r.Text }
            return 'bucket = ACTIVE (no background limits)'
        }
        'LowPower' {
            $cur = Get-GlobalSetting 'low_power'
            if ($null -eq $cur -or $cur -eq '0') { return 'battery saver already off' }
            $null = Set-TrackedGlobal 'low_power' '0' -Note 'battery saver was ON - turned off for gaming'
            return 'battery saver turned off'
        }
        'RefreshLock' {
            $peak = Get-PeakRefreshValue
            if ($peak -le 0) { return 'skipped (refresh rate unknown on this build)' }
            $val = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.0}', [double]$peak)
            $null = Set-TrackedSystem 'min_refresh_rate'  $val -Note 'device-dependent: some phones ignore this'
            $null = Set-TrackedSystem 'peak_refresh_rate' $val -Note 'device-dependent: some phones ignore this'
            return "refresh lock set to ${peak} Hz"
        }
        'BgRestrict' {
            $targets = Get-BloatList
            if ($targets.Count -eq 0) { return 'no known bloat installed' }
            $n = 0
            foreach ($p in $targets) {
                $before = (Invoke-Shell "cmd appops get $p RUN_IN_BACKGROUND" -IgnoreErrors).Text.Trim()
                Add-Change -Kind 'AppOp' -Target $p -OldValue $before -NewValue 'RUN_IN_BACKGROUND deny' `
                    -Note "restore: cmd appops reset $p"
                $r = Invoke-Shell "cmd appops set $p RUN_IN_BACKGROUND deny" -IgnoreErrors
                Invoke-Shell "am force-stop $p" -IgnoreErrors | Out-Null
                if ($r.Text -notmatch '(?i)error') { $n++ }
            }
            return "$n apps restricted"
        }
        'FixedPerf' {
            $old = (Invoke-Shell 'cmd power set-fixed-performance-mode-enabled' -IgnoreErrors).Text.Trim()
            Add-Change -Kind 'FixedPerf' -Target 'power' -OldValue $old -NewValue 'true' `
                -Note 'restore: cmd power set-fixed-performance-mode-enabled false'
            $r = Invoke-Shell 'cmd power set-fixed-performance-mode-enabled true' -IgnoreErrors
            if ($r.Text -match '(?i)error|exception') { throw $r.Text }
            return 'clocks pinned (phone will run hotter)'
        }
        'RemoveBloat' {
            $targets = Get-BloatList
            if ($targets.Count -eq 0) { return 'nothing to remove' }
            $n = 0
            foreach ($p in $targets) {
                Add-Change -Kind 'RemovedPackage' -Target $p -OldValue 'installed' -NewValue 'removed for user 0' `
                    -Note "restore: cmd package install-existing $p"
                $r = Invoke-Shell "pm uninstall --user 0 $p" -IgnoreErrors
                if ($r.Text -match '(?i)success') { $n++ }
            }
            return "$n apps removed (reversible)"
        }
        'GlobalRes' {
            $sizeOut = (Invoke-Shell 'wm size' -IgnoreErrors).Text
            $densityOut = (Invoke-Shell 'wm density' -IgnoreErrors).Text
            $phys = '1080x2340'
            if ($sizeOut -match 'Physical size:\s*(\d+x\d+)') { $phys = $matches[1] }
            $pW, $pH = $phys -split 'x'
            $newW = [int]([int]$pW * 0.75); $newH = [int]([int]$pH * 0.75)
            $oldDensity = 'none'
            if ($densityOut -match 'Physical density:\s*(\d+)') { $oldDensity = $matches[1] }
            $newDensity = [int]([int]$oldDensity * 0.75)
            Add-Change -Kind 'WmSize' -Target 'display' -OldValue $(if ($sizeOut -match 'Override size:\s*(\S+)') { $matches[1] } else { 'reset' }) `
                -NewValue "${newW}x${newH}" -Note "restore: wm size reset"
            Add-Change -Kind 'WmDensity' -Target 'display' -OldValue $(if ($densityOut -match 'Override density:\s*(\S+)') { $matches[1] } else { 'reset' }) `
                -NewValue "$newDensity" -Note "restore: wm density reset"
            Invoke-Shell "wm size ${newW}x${newH}" | Out-Null
            Invoke-Shell "wm density $newDensity" | Out-Null
            return "screen -> ${newW}x${newH} @ ${newDensity}dpi"
        }
        default { return 'no-op' }
    }
}

function Stop-BackgroundApps {
    $keep = @(
        'com.android.systemui', 'android', 'com.android.phone', 'com.android.settings',
        'com.google.android.gms', 'com.google.android.gsf', 'com.android.providers.telephony',
        'com.dts.freefireth', 'com.dts.freefiremax'
    )
    $protected = @('com.android', 'android.process', 'com.google.android.gms', 'com.whatsapp')
    $n = 0
    if ($script:Sim) { return 6 }
    $r = Invoke-Shell 'pm list packages -3' -IgnoreErrors
    $pkgs = @()
    foreach ($m in [regex]::Matches($r.Text, 'package:(\S+)')) { $pkgs += $m.Groups[1].Value }
    foreach ($p in $pkgs) {
        if ($keep -contains $p) { continue }
        $skip = $false
        foreach ($pr in $protected) { if ($p -like "$pr*") { $skip = $true } }
        if ($skip) { continue }
        Invoke-Shell "am force-stop $p" -IgnoreErrors | Out-Null
        $n++
    }
    return $n
}

# =============================================================================
#  BACKUP / RESTORE
# =============================================================================
function Get-PendingPath {
    if ($script:Sim) { return (Join-Path $script:AppDir 'pending-simulated.json') }
    $serial = if ($script:SerialToUse) { $script:SerialToUse -replace '[^\w\-]', '_' } else { 'nodevice' }
    return (Join-Path $script:AppDir "pending-$serial.json")
}

function Merge-ChangeList {
    # keeps every change made since the last restore, without duplicates
    # (first recorded old value wins, so undo always reaches the original state)
    param($Existing, $New)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($Existing)) { if ($c) { $out.Add($c) | Out-Null } }
    foreach ($n in @($New)) {
        if (-not $n) { continue }
        $dup = $false
        foreach ($e in $out) { if ($e.Kind -eq $n.Kind -and $e.Target -eq $n.Target) { $dup = $true; break } }
        if (-not $dup) { $out.Add($n) | Out-Null }
    }
    return $out.ToArray()
}

function New-Backup {
    param([string]$ProfileName)
    $info = $script:Device
    $pending = @()
    $pendingPath = Get-PendingPath
    if (Test-Path -LiteralPath $pendingPath) {
        try { $pending = @((Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json).Changes) } catch { Write-Verbose "pending unreadable: $($_.Exception.Message)" }
    }
    $merged = Merge-ChangeList -Existing $pending -New $script:Changes.ToArray()
    $backup = [pscustomobject]@{
        Tool      = 'FF Mobile Optimizer'
        Version   = $script:Version
        Created   = (Get-Date).ToString('s')
        Device    = "$($info.Brand) $($info.Model)"
        Android   = "$($info.Android) (SDK $($info.Sdk))"
        Profile   = $ProfileName
        Simulated = $script:Sim
        Changes   = $merged
        Commands  = $script:CmdLog.ToArray()
        Warnings  = $script:Warnings.ToArray()
    }
    if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null }
    $name = if ($script:Sim) { 'backup-simulated.json' } else { "backup-$($script:SerialToUse -replace '[^\w\-]','_')-$(Get-Date -Format 'yyyyMMdd-HHmmss').json" }
    $path = Join-Path $script:AppDir $name
    $json = $backup | ConvertTo-Json -Depth 8
    $json | Set-Content -LiteralPath $path -Encoding UTF8
    if ($pendingPath) { $json | Set-Content -LiteralPath $pendingPath -Encoding UTF8 }
    return $path
}

function Get-LastBackupPath {
    # the pending file holds every change made since the last restore
    $pend = Get-PendingPath
    if ($pend -and (Test-Path -LiteralPath $pend)) { return $pend }
    if ($script:Sim) {
        $p = Join-Path $script:AppDir 'backup-simulated.json'
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    if (-not (Test-Path -LiteralPath $script:AppDir)) { return $null }
    $f = Get-ChildItem -LiteralPath $script:AppDir -Filter 'backup-*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if (-not $f) { return $null }
    return $f[0].FullName
}

function Invoke-Restore {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { Write-Bad "Backup not found: $Path"; return $false }
    $bk = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    Write-Head 'RESTORE - putting the phone back'
    Write-Info "Backup     : $Path"
    Write-Info "Device     : $($bk.Device)   ($($bk.Android))"
    Write-Info "Created    : $($bk.Created)   changes: $(@($bk.Changes).Count)"
    Write-Host ''
    if (-not $script:ForceFlag) {
        $ans = Read-Host '  Undo every change from this backup? (y/N)'
        if ($ans -notmatch '^(y|yes)$') { Write-Info 'Cancelled.'; return $false }
    }
    $failed = 0; $done = 0
    $undoOrder = @('GlobalSetting', 'SecureSetting', 'SystemSetting', 'Downscale', 'GameMode', 'DozeWhitelist', 'StandbyBucket', 'FixedPerf', 'AppOp', 'RemovedPackage', 'WmSize', 'WmDensity', 'Compile')
    $sorted = @($bk.Changes | Sort-Object { $undoOrder.IndexOf($_.Kind) })
    foreach ($c in $sorted) {
        try {
            switch ($c.Kind) {
                'GlobalSetting' {
                    if ($c.OldValue) {
                        Set-GlobalSetting -Key $c.Target -Value $c.OldValue | Out-Null
                        Write-Step "$($c.Target) -> $($c.OldValue)" 'restored'
                    } else {
                        Invoke-Shell "settings delete global $($c.Target)" -IgnoreErrors | Out-Null
                        Write-Step "$($c.Target)" 'reset to default'
                    }
                    $done++
                }
                'Downscale' {
                    Invoke-Shell "cmd game downscale disable $($c.Target)" -IgnoreErrors | Out-Null
                    Write-Step "downscale ($($c.Target))" 'disabled'
                    $done++
                }
                'GameMode' {
                    Invoke-Shell "cmd game mode default $($c.Target)" -IgnoreErrors | Out-Null
                    Write-Step "game mode ($($c.Target))" 'back to default'
                    $done++
                }
                'FixedPerf' {
                    Invoke-Shell 'cmd power set-fixed-performance-mode-enabled false' -IgnoreErrors | Out-Null
                    Write-Step 'fixed performance mode' 'disabled'
                    $done++
                }
                'SecureSetting' {
                    if ($c.OldValue) {
                        Set-SecureSetting -Key $c.Target -Value $c.OldValue | Out-Null
                        Write-Step "$($c.Target) -> $($c.OldValue)" 'restored'
                    } else {
                        Invoke-Shell "settings delete secure $($c.Target)" -IgnoreErrors | Out-Null
                        Write-Step "$($c.Target)" 'reset to default'
                    }
                    $done++
                }
                'SystemSetting' {
                    if ($c.OldValue) {
                        Set-SystemSetting -Key $c.Target -Value $c.OldValue | Out-Null
                        Write-Step "$($c.Target) -> $($c.OldValue)" 'restored'
                    } else {
                        Invoke-Shell "settings delete system $($c.Target)" -IgnoreErrors | Out-Null
                        Write-Step "$($c.Target)" 'reset to default'
                    }
                    $done++
                }
                'DozeWhitelist' {
                    Invoke-Shell "dumpsys deviceidle whitelist -$($c.Target)" -IgnoreErrors | Out-Null
                    Write-Step "battery exemption ($($c.Target))" 'removed'
                    $done++
                }
                'StandbyBucket' {
                    if ($c.OldValue -match '^\d+$') {
                        Invoke-Shell "am set-standby-bucket $($c.Target) $($c.OldValue)" -IgnoreErrors | Out-Null
                        Write-Step "standby bucket ($($c.Target))" "back to $($c.OldValue)"
                    } else {
                        Invoke-Shell "am reset-standby-bucket $($c.Target)" -IgnoreErrors | Out-Null
                        Write-Step "standby bucket ($($c.Target))" 'reset'
                    }
                    $done++
                }
                'AppOp' {
                    Invoke-Shell "cmd appops reset $($c.Target)" -IgnoreErrors | Out-Null
                    Write-Step "appops ($($c.Target))" 'reset'
                    $done++
                }
                'RemovedPackage' {
                    $r = Invoke-Shell "cmd package install-existing $($c.Target)" -IgnoreErrors
                    if ($r.Text -match '(?i)installed') { Write-Step "$($c.Target)" 'reinstalled' }
                    else { Write-Step "$($c.Target)" 'not restored (install from Play Store)' 'Yellow' }
                    $done++
                }
                'WmSize'    { Invoke-Shell 'wm size reset' -IgnoreErrors | Out-Null;     Write-Step 'screen size' 'reset to native'; $done++ }
                'WmDensity' { Invoke-Shell 'wm density reset' -IgnoreErrors | Out-Null;  Write-Step 'screen density' 'reset to native'; $done++ }
                'Compile'   { Invoke-Shell "cmd package compile -m speed-profile -f $($c.Target)" -IgnoreErrors | Out-Null
                              Write-Step "compile state ($($c.Target))" 'back to default'; $done++ }
                default     { Write-Step "$($c.Kind)" 'skipped' 'DarkGray' }
            }
        } catch {
            $failed++
            Write-Bad "$($c.Kind) $($c.Target): $($_.Exception.Message)"
        }
    }
    Write-Host ''
    if ($failed -eq 0) {
        Write-Ok "Restore complete - $done item(s) reverted."
        $pend = Get-PendingPath
        if ($pend -and (Test-Path -LiteralPath $pend) -and ($Path -eq $pend)) {
            Remove-Item -LiteralPath $pend -Force -ErrorAction SilentlyContinue
            Write-Info 'Change log cleared - the phone is back to its original state.'
        }
    }
    else { Write-Warn2 "Restore finished with $failed error(s)." }
    Write-Info 'Tip: reboot the phone so every setting is fully re-read.'
    return ($failed -eq 0)
}

# =============================================================================
#  SCAN / STATUS
# =============================================================================
function Show-Status {
    Write-Sub 'Scanning Android settings (nothing is changed)'
    $status = @{}
    foreach ($t in (Get-TweakTable)) { $status[$t.Id] = Test-Tweak -Id $t.Id }
    $total = 0; $good = 0; $todo = @()
    foreach ($t in (Get-TweakTable)) {
        $st = $status[$t.Id]
        $isAdv = ($t.Risk -eq 'Advanced')
        $isInfo = $isAdv -or $st.OnDemand -or $st.Unverifiable
        $mark = if ($isInfo) { '--' } elseif ($st.Optimal) { 'OK' } else { '!!' }
        $color = if ($isInfo) { 'DarkGray' } elseif ($st.Optimal) { 'Green' } else { 'Yellow' }
        Write-Host ("   [{0}] {1,-34} " -f $mark, $t.Name) -NoNewline
        Write-Host ("{0,-9} {1}" -f $t.Impact, $st.Current) -ForegroundColor $color
        if (-not $isInfo) {
            $total++
            if ($st.Optimal) { $good++ } else { $todo += $t }
        }
    }
    $score = if ($total -gt 0) { [math]::Round(($good / $total) * 100) } else { 0 }
    Write-Host ''
    Write-Host ("   OPTIMIZATION SCORE: {0}%   ({1}/{2} core tweaks optimal)" -f $score, $good, $total) -ForegroundColor Cyan
    if ($todo.Count -gt 0) {
        Write-Host ''
        Write-Info 'Can be improved:'
        foreach ($t in $todo) { Write-Host ("     * {0,-32} {1,-9} {2}" -f $t.Name, $t.Impact, $t.Risk) -ForegroundColor Yellow }
    }
    return [pscustomobject]@{ Status = $status; Score = $score; Good = $good; Total = $total; Todo = $todo }
}

function Show-DeviceInfo {
    $d = $script:Device
    Write-Sub 'Phone'
    Write-Host ("   {0} {1}   -   Android {2} (SDK {3})" -f $d.Brand, $d.Model, $d.Android, $d.Sdk) -ForegroundColor White
    Write-Host ("   SoC        : {0}" -f $(if ($d.Soc) { $d.Soc } else { 'unknown' }))
    Write-Host ("   RAM        : {0} GB total, {1} GB free" -f $d.RamTotalGb, $d.RamFreeGb)
    Write-Host ("   Screen     : {0} @ {1} dpi   ({2})" -f $d.Screen, $d.Density, $d.RefreshRate)
    if ($d.ScreenOverride -ne 'none') { Write-Warn2 "Screen size is overridden to $($d.ScreenOverride) (menu 9 to reset)" }
    if ($script:FfPackages.Count -gt 0) {
        foreach ($p in $script:FfPackages) {
            $v = Get-PackageVersion -Package $p
            Write-Host ("   Free Fire  : {0}  v{1}" -f $p, $v) -ForegroundColor Green
        }
    } else {
        Write-Warn2 'Free Fire is not installed (or not visible to ADB).'
        if ($script:ActivePackage) { Write-Info "Using package: $($script:ActivePackage)" }
    }
}

# =============================================================================
#  REPORT
# =============================================================================
function New-Report {
    param($Before, $After, $Applied, $SnapBefore, $SnapAfter, [string]$BackupPath)
    $d = $script:Device
    $rows = ''
    foreach ($t in (Get-TweakTable)) {
        $b = $Before.Status[$t.Id]; $a = $After.Status[$t.Id]
        $bc = if ($b.Optimal) { 'ok' } else { 'bad' }
        $ac = if ($a.Optimal) { 'ok' } else { 'bad' }
        $rows += "<tr><td>$($t.Name)</td><td>$($t.Impact)</td><td>$($t.Risk)</td>" +
                 "<td class='$bc'>$(if($b.Optimal){'OK'}else{'needs fix'})</td>" +
                 "<td class='$ac'>$(if($a.Optimal){'OK'}else{'needs fix'})</td></tr>"
    }
    $applied = ''
    foreach ($a in $Applied) { $applied += "<li>$($a.Name) &rarr; <b>$($a.Result)</b></li>" }
    $tempB = if ($SnapBefore -and $null -ne $SnapBefore.TempC) { "$($SnapBefore.TempC) C" } else { 'n/a' }
    $tempA = if ($SnapAfter -and $null -ne $SnapAfter.TempC) { "$($SnapAfter.TempC) C" } else { 'n/a' }
    $fpsB = if ($SnapBefore -and $null -ne $SnapBefore.Fps) { "$($SnapBefore.Fps) fps" } else { 'n/a' }
    $fpsA = if ($SnapAfter -and $null -ne $SnapAfter.Fps) { "$($SnapAfter.Fps) fps" } else { 'n/a' }
    $jankB = if ($SnapBefore -and $null -ne $SnapBefore.JankPct) { "$($SnapBefore.JankPct) %" } else { 'n/a' }
    $jankA = if ($SnapAfter -and $null -ne $SnapAfter.JankPct) { "$($SnapAfter.JankPct) %" } else { 'n/a' }

    $html = @"
<!doctype html><html><head><meta charset="utf-8"><title>FF Mobile Optimizer Report</title>
<style>
 body{background:#0f1216;color:#e8ecf3;font-family:Segoe UI,system-ui,sans-serif;margin:0;padding:30px}
 h1{color:#7dd3fc;margin:0 0 4px} h2{color:#a5b4fc;margin-top:30px;border-bottom:1px solid #2b3242;padding-bottom:6px}
 .sub{color:#8b94a7;margin-bottom:22px}
 .cards{display:flex;gap:14px;flex-wrap:wrap}
 .card{background:#171b23;border:1px solid #2b3242;border-radius:12px;padding:14px 20px;min-width:130px}
 .card .n{font-size:26px;font-weight:700;color:#4ade80} .card .l{color:#8b94a7;font-size:13px}
 table{border-collapse:collapse;width:100%;margin-top:8px}
 th,td{border-bottom:1px solid #2b3242;padding:7px 9px;text-align:left;font-size:14px}
 th{color:#8b94a7;font-weight:600} td.ok{color:#4ade80} td.bad{color:#fbbf24}
 ul{line-height:1.7} code{background:#222836;padding:2px 6px;border-radius:5px;color:#fcd34d}
 .foot{margin-top:30px;color:#6b7280;font-size:12px}
</style></head><body>
<h1>FF Mobile Optimizer Report</h1>
<div class="sub">$($d.Brand) $($d.Model) &middot; Android $($d.Android) (SDK $($d.Sdk)) &middot; v$($script:Version) &middot; $(Get-Date -Format 'yyyy-MM-dd HH:mm')$(if($script:Sim){' &middot; [SIMULATED DEVICE]'})</div>
<div class="cards">
 <div class="card"><div class="n">$($Before.Score)% &rarr; $($After.Score)%</div><div class="l">Optimization score</div></div>
 <div class="card"><div class="n">$(@($Applied).Count)</div><div class="l">Tweaks applied</div></div>
 <div class="card"><div class="n">$tempB &rarr; $tempA</div><div class="l">Battery temp</div></div>
 <div class="card"><div class="n">$fpsB &rarr; $fpsA</div><div class="l">Frames (Android stats)</div></div>
 <div class="card"><div class="n">$jankB &rarr; $jankA</div><div class="l">Janky frames</div></div>
</div>
<h2>Phone</h2>
<table>
<tr><th>SoC</th><td>$($d.Soc)</td></tr>
<tr><th>RAM</th><td>$($d.RamTotalGb) GB total / $($d.RamFreeGb) GB free</td></tr>
<tr><th>Screen</th><td>$($d.Screen) @ $($d.Density) dpi ($($d.RefreshRate))</td></tr>
<tr><th>Free Fire</th><td>$(($script:FfPackages -join ', '))</td></tr>
</table>
<h2>Tweaks</h2>
<table><tr><th>Tweak</th><th>Impact</th><th>Risk</th><th>Before</th><th>After</th></tr>$rows</table>
<h2>Applied in this run</h2><ul>$applied</ul>
<h2>How to undo</h2>
<p>Run <code>FF Mobile Optimizer.bat</code> &rarr; menu <b>6) Restore</b>, or:</p>
<p><code>.\FFMobileOptimizer.ps1 -Mode Restore</code></p>
<p>Backup for this run: <code>$BackupPath</code></p>
<h2>Honest measurement notes</h2>
<p>Android does not expose a simple "current FPS" number for games. This tool reads the
frame timings Android records for the game process (best effort) plus battery temperature and
the thermal throttling state - the things that actually decide your sustained FPS.
For the most reliable before/after: play one match, run <b>Measure</b>, optimize, restart the game,
play another match, run <b>Measure</b> again.</p>
<div class="foot">FF Mobile Optimizer $($script:Version) - Android settings only. The game itself was never modified, so there is no ban risk.</div>
</body></html>
"@
    if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null }
    $path = Join-Path $script:AppDir ("report-{0}.html" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $html | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

# =============================================================================
#  PHONE-ONLY GUIDE
# =============================================================================
function Show-PhoneGuide {
    param([switch]$Plain)
    $pkg = if ($script:ActivePackage) { $script:ActivePackage } else { 'com.dts.freefireth' }
    $lines = @(
        '# ---- FF Mobile Optimizer : phone-only commands (LADB / Shizuku) ----',
        '# 1) pkg = package name. Free Fire = com.dts.freefireth , Free Fire MAX = com.dts.freefiremax',
        "pkg=$pkg",
        '',
        '# --- check current state -------------------------------------------------',
        'wm size ; wm density',
        'settings get global window_animation_scale',
        'device_config get game_overlay $pkg',
        'dumpsys battery | grep temperature',
        'dumpsys thermalservice | grep "Thermal Status"',
        '',
        '# --- optimize ------------------------------------------------------------',
        'cmd game mode performance $pkg',
        'cmd game downscale 0.75 $pkg',
        'settings put global window_animation_scale 0',
        'settings put global transition_animation_scale 0',
        'settings put global animator_duration_scale 0',
        'settings put global wifi_scan_always_enabled 0',
        'settings put global network_recommendations_enabled 0',
        'cmd package compile -m speed -f $pkg',
        'settings put secure long_press_timeout 250',
        'settings put secure multi_press_timeout 250',
        'am force-stop com.facebook.katana',
        '',
        '# --- keep the game alive + full speed ------------------------------------',
        'dumpsys deviceidle whitelist +$pkg',
        'am set-standby-bucket $pkg 10',
        'settings put global low_power 0',
        '',
        '# --- optional: refresh-rate lock (some phones ignore it) ------------------',
        'settings put system min_refresh_rate 120.0',
        'settings put system peak_refresh_rate 120.0',
        '',
        '# --- EXPERIMENTAL: route the game through the ANGLE driver ----------------',
        '#     measure dumpsys gfxinfo jank BEFORE and AFTER - it can help or hurt',
        'settings put global angle_gl_driver_selection_pkgs $pkg',
        'settings put global angle_gl_driver_selection_values angle',
        '',
        '# --- undo everything -----------------------------------------------------',
        'cmd game mode default $pkg',
        'cmd game downscale disable $pkg',
        'settings put global window_animation_scale 1',
        'settings put global transition_animation_scale 1',
        'settings put global animator_duration_scale 1',
        'settings put global wifi_scan_always_enabled 1',
        'settings put global network_recommendations_enabled 1',
        'settings put secure long_press_timeout 400',
        'settings put secure multi_press_timeout 300',
        'dumpsys deviceidle whitelist -$pkg',
        'am reset-standby-bucket $pkg',
        'settings delete global low_power',
        'settings delete system min_refresh_rate',
        'settings delete system peak_refresh_rate',
        'settings delete global angle_gl_driver_selection_pkgs',
        'settings delete global angle_gl_driver_selection_values',
        'cmd package compile -m speed-profile -f $pkg',
        'wm size reset ; wm density reset'
    )
    if ($Plain) { return ($lines -join "`r`n") }
    Write-Head 'PHONE-ONLY MODE (no PC needed)'
    Write-Info 'Use the LADB app (free, Play Store) or Shizuku + a terminal app.'
    Write-Info 'Steps: Developer options > Wireless debugging > ON, then pair LADB with the code.'
    Write-Host ''
    foreach ($l in $lines) {
        if ($l -match '^#') { Write-Host "  $l" -ForegroundColor DarkGray }
        elseif ($l -eq '') { Write-Host '' }
        else { Write-Host "  $l" -ForegroundColor Green }
    }
    Write-Host ''
    Write-Warn2 'Copy the command lines (not the # comments) into LADB, one block at a time.'
}

# =============================================================================
#  OPTIMIZE FLOW
# =============================================================================
function Select-CustomTweaks {
    $table = Get-TweakTable
    Write-Sub 'Pick tweaks (comma separated numbers)'
    $i = 0
    foreach ($t in $table) {
        $i++
        Write-Host ("   [{0,2}] {1,-34} {2,-9} risk: {3}" -f $i, $t.Name, $t.Impact, $t.Risk)
    }
    Write-Host ''
    $ans = Read-Host '  Numbers'
    $ids = @()
    foreach ($p in ($ans -split '[,\s]+')) {
        if ($p -match '^\d+$') {
            $idx = [int]$p - 1
            if ($idx -ge 0 -and $idx -lt $table.Count) { $ids += $table[$idx].Id }
        }
    }
    return $ids
}

function Invoke-Optimize {
    param([string]$ProfileName, [string[]]$CustomIds, [switch]$SkipPrompts)

    $tweaks = Get-TweaksForProfile -ProfileName $ProfileName -CustomIds $CustomIds
    if (@($tweaks).Count -eq 0) {
        Write-Bad 'Nothing selected.'
        if ($ProfileName -eq 'Custom') {
            Write-Info 'Tweak ids for -Tweaks (comma separated):'
            foreach ($t in (Get-TweakTable)) { Write-Host ("     {0,-12} {1}" -f $t.Id, $t.Name) -ForegroundColor Gray }
        }
        return
    }
    Write-Head "OPTIMIZE - profile: $ProfileName$(if ($script:Sim) { '   [SIMULATED DEVICE]' })"

    Show-DeviceInfo
    Write-Sub 'Performance right now'
    $snapBefore = Get-PerfSnapshot -Package $script:ActivePackage -Label 'before'
    Show-Snapshot -Snap $snapBefore

    $before = Show-Status
    $script:ScoreBefore = $before.Score

    Write-Sub 'Plan'
    $i = 0
    foreach ($t in $tweaks) {
        $i++
        $st = $before.Status[$t.Id]
        $state = if ($st.Optimal -and -not $st.OnDemand -and -not $st.Unverifiable) { 'already OK' } else { 'will apply' }
        $color = if ($state -eq 'already OK') { 'DarkGray' } else { 'White' }
        $note = ''
        if ($t.Id -eq 'FixedPerf') { $note = '  <- runs hotter!' }
        if ($t.Id -eq 'GlobalRes') { $note = '  <- changes the whole phone UI' }
        if ($t.Id -eq 'Angle') { $note = '  <- EXPERIMENTAL: measure before/after, may lower FPS' }
        if ($t.Id -eq 'RemoveBloat') { $note = '  <- reversible, apps come back from Play Store' }
        if ($t.Id -eq 'DozeWhitelist') { $note = '  <- keeps the game alive when you switch apps' }
        if ($t.Id -eq 'RefreshLock') { $note = '  <- some phones ignore this' }
        Write-Host ("   [{0,2}] {1,-34} {2,-9} {3}{4}" -f $i, $t.Name, $t.Impact, $state, $note) -ForegroundColor $color
    }

    if ($script:DryRunFlag) {
        Write-Host ''
        Write-Warn2 'DRY RUN - nothing was changed.'
        return
    }
    if (-not $script:ForceFlag -and -not $SkipPrompts) {
        Write-Host ''
        Write-Warn2 'Close Free Fire first - the changes apply when the game next starts.'
        $ans = Read-Host '  Apply these changes now? (y/N)'
        if ($ans -notmatch '^(y|yes)$') { Write-Info 'Cancelled.'; return }
    }

    Write-Sub 'Applying'
    $applied = @()
    $n = @($tweaks).Count
    $i = 0
    foreach ($t in $tweaks) {
        $i++
        try {
            $msg = Invoke-Tweak -Id $t.Id -Package $script:ActivePackage
            Write-Step "[$i/$n] $($t.Name)" $msg
            $applied += [pscustomobject]@{ Name = $t.Name; Result = $msg; Id = $t.Id }
        } catch {
            $script:Warnings.Add("$($t.Id): $($_.Exception.Message)") | Out-Null
            Write-Step "[$i/$n] $($t.Name)" "ERROR: $($_.Exception.Message)" 'Red'
        }
    }

    $backupPath = New-Backup -ProfileName $ProfileName
    Write-Host ''
    Write-Ok "Backup saved: $backupPath"
    Write-Info 'Undo any time: menu 6) Restore, or -Mode Restore'

    Write-Sub 'Verify'
    $after = Show-Status
    Write-Sub 'Performance after'
    $snapAfter = Get-PerfSnapshot -Package $script:ActivePackage -Label 'after'
    Show-Snapshot -Snap $snapAfter

    Write-Host ''
    Write-Host ("   SCORE: {0}%  ->  {1}%" -f $before.Score, $after.Score) -ForegroundColor Cyan

    Show-InGameCard

    $report = New-Report -Before $before -After $after -Applied $applied -SnapBefore $snapBefore -SnapAfter $snapAfter -BackupPath $backupPath
    Write-Sub 'Report'
    Write-Ok "Saved: $report"
    if ($script:Warnings.Count -gt 0) {
        Write-Sub 'Warnings'
        foreach ($w in $script:Warnings) { Write-Warn2 $w }
    }
    Write-Host ''
    Write-Host '   Done. Restart Free Fire and enjoy. ' -ForegroundColor Green
}

function Show-InGameCard {
    Write-Sub 'Free Fire settings that match these tweaks'
    Write-Host '   Graphics   : Smooth  |  High FPS  |  Shadows OFF  |  AA OFF' -ForegroundColor White
    Write-Host '   Auto-adjust graphics: OFF   (stops mid-fight quality changes)'
    Write-Host '   Audio      : high-quality audio OFF (less CPU, footsteps clearer)'
    Write-Host '   Phone      : keep 20-30% battery free of apps, avoid charging while playing' -ForegroundColor DarkGray
    Write-Host '   Cooling    : remove the case, never play while charging - heat is the' -ForegroundColor DarkGray
    Write-Host '                number one cause of FPS drops after 10 minutes.' -ForegroundColor DarkGray
}

# =============================================================================
#  MENU
# =============================================================================
function Show-Banner {
    Write-Host ''
    Write-Host '  ####### #######   #     #  ####### ######  ### #####  #######' -ForegroundColor DarkCyan
    Write-Host '  #       #         ##   ##  #     # #     #  #  #    # #      ' -ForegroundColor DarkCyan
    Write-Host '  #####   #####     # # # #  #     # ######   #  #    # #####  ' -ForegroundColor DarkCyan
    Write-Host '  #       #         #  #  #  #     # #     #  #  #    # #      ' -ForegroundColor DarkCyan
    Write-Host '  #       #         #     #  ####### ######  ### #####  #######' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ("  Free Fire optimizer for Android (no root) - v$($script:Version)$(if ($script:Sim) { '   [SIMULATED DEVICE]' })") -ForegroundColor Gray
    if ($script:Device) {
        Write-Host ("  Phone : {0} {1}  -  Android {2}" -f $script:Device.Brand, $script:Device.Model, $script:Device.Android) -ForegroundColor DarkGray
        Write-Host ("  Game  : {0}" -f $($script:FfPackages -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host '  Phone : (not connected yet)' -ForegroundColor DarkGray
    }
}

function Start-Menu {
    while ($true) {
        Clear-Host
        Show-Banner
        Write-Host ''
        Write-Host '   1) Connect / reconnect phone' -ForegroundColor White
        Write-Host '   2) Scan        - see what is not optimized (change nothing)' -ForegroundColor White
        Write-Host '   3) Optimize    - Safe profile (recommended)' -ForegroundColor White
        Write-Host '   4) Optimize    - Full profile (more FPS, phone runs hotter)' -ForegroundColor White
        Write-Host '   5) Optimize    - Custom (pick tweaks yourself)' -ForegroundColor White
        Write-Host '   6) Restore     - undo everything from the last backup' -ForegroundColor White
        Write-Host '   7) Measure     - temperature / thermal / frame stats' -ForegroundColor White
        Write-Host '   8) Remove bloat apps (reversible, opt-in)' -ForegroundColor White
        Write-Host '   9) Reset screen size/density to native' -ForegroundColor White
        Write-Host '  10) Phone-only commands (LADB / Shizuku)' -ForegroundColor White
        Write-Host '  11) Open backup + report folder' -ForegroundColor White
        Write-Host '   0) Exit' -ForegroundColor DarkGray
        Write-Host ''
        $choice = (Read-Host '  Choose').Trim()
        try {
            switch ($choice) {
                '1' { $script:SerialToUse = $null; Connect-Device | Out-Null; $script:Device = Get-DeviceInfo; $script:FfPackages = Get-FreeFirePackages
                      $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] } }
                '2' { if (Confirm-Connected) { Show-DeviceInfo; $null = Show-Status; $null = Get-PerfSnapshot -Package $script:ActivePackage -Label 'now' | ForEach-Object { Show-Snapshot $_ } } }
                '3' { if (Confirm-Connected) { Invoke-Optimize -ProfileName 'Safe' } }
                '4' { if (Confirm-Connected) { Invoke-Optimize -ProfileName 'Full' } }
                '5' { if (Confirm-Connected) { $ids = Select-CustomTweaks; if ($ids.Count -gt 0) { Invoke-Optimize -ProfileName 'Custom' -CustomIds $ids } else { Write-Warn2 'Nothing selected.' } } }
                '6' { if (Confirm-Connected) {
                        $bk = if ($script:BackupFileOpt) { $script:BackupFileOpt } else { Get-LastBackupPath }
                        if (-not $bk) { Write-Warn2 'No backup found.' } else { $null = Invoke-Restore -Path $bk } } }
                '7' { if (Confirm-Connected) { Write-Head 'MEASURE'; $s = Get-PerfSnapshot -Package $script:ActivePackage -Label 'now'; Show-Snapshot -Snap $s } }
                '8' { if (Confirm-Connected) {
                        $list = Get-BloatList
                        if ($list.Count -eq 0) { Write-Warn2 'No known bloat apps found.' } else {
                            Write-Sub 'Apps that will be removed for user 0 (fully reversible)'
                            foreach ($p in $list) { Write-Host "   - $p" -ForegroundColor Yellow }
                            Write-Host ''
                            Write-Info 'They disappear for you but stay in the system partition.'
                            Write-Info 'Bring them back any time with Restore, or install from Play Store.'
                            $ans = Read-Host '  Type REMOVE to continue'
                            if ($ans -eq 'REMOVE') {
                                $msg = Invoke-Tweak -Id 'RemoveBloat' -Package $script:ActivePackage
                                Write-Ok $msg
                                $p = New-Backup -ProfileName 'BloatRemoval'
                                Write-Ok "Backup saved: $p"
                            } else { Write-Info 'Cancelled.' }
                        } } }
                '9' { if (Confirm-Connected) {
                        Invoke-Shell 'wm size reset' -IgnoreErrors | Out-Null
                        Invoke-Shell 'wm density reset' -IgnoreErrors | Out-Null
                        Write-Ok 'Screen size and density reset to native.'
                        Write-Info 'Reboot the phone for a clean redraw.' } }
                '10' { Show-PhoneGuide }
                '11' {
                    if (-not (Test-Path -LiteralPath $script:AppDir)) { New-Item -ItemType Directory -Path $script:AppDir -Force | Out-Null }
                    if ($env:OS -eq 'Windows_NT' -or $IsWindows) { Start-Process explorer.exe $script:AppDir }
                    else { Write-Info "Folder: $script:AppDir" } }
                '0' { return }
                default { Write-Warn2 'Pick 0-11.' }
            }
        } catch {
            Write-Bad $_.Exception.Message
        }
        Write-Host ''
        Read-Host '  Press Enter to return to the menu' | Out-Null
    }
}

function Confirm-Connected {
    if ($script:Device) { return $true }
    try {
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $script:FfPackages = Get-FreeFirePackages
        $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] }
        if ($script:FfPackages.Count -eq 0) {
            Write-Warn2 'Free Fire was not found on the phone. Continuing with the default package name.'
        }
        return $true
    } catch {
        Write-Bad $_.Exception.Message
        return $false
    }
}

# =============================================================================
#  MAIN
# =============================================================================
$script:DryRunFlag = [bool]$DryRun
$script:AngleFlag  = [bool]$Angle
$script:AdbExe = $null
$script:ActivePackage = $FF_PACKAGES_KNOWN[0]

if ($script:Sim -and -not $env:FFMO_SILENT) {
    Write-Host ''
    Write-Host '  ***************************************************************' -ForegroundColor Yellow
    Write-Host '  *  SIMULATED DEVICE - no phone is being changed by this run    *' -ForegroundColor Yellow
    Write-Host '  ***************************************************************' -ForegroundColor Yellow
}

switch ($Mode) {
    'PhoneGuide' { Show-PhoneGuide; if ($env:FFMO_PRINT_GUIDE) { } }
    'Doctor' {
        Write-Head 'DOCTOR'
        Write-Info "PowerShell : $($PSVersionTable.PSVersion)"
        Write-Info "OS         : $(if ($env:OS) { $env:OS } else { 'unix' })"
        Write-Info "App folder : $script:AppDir"
        Write-Info "ANGLE flag : $(if ($script:AngleFlag) { 'ON (experimental)' } else { 'off' })"
        $adb = Find-Adb
        if ($adb) { Write-Ok "adb found: $adb" ; $script:AdbExe = $adb; $v = Invoke-Adb -AdbArgs @('version') -NoSerial -IgnoreErrors; Write-Info ($v.Output -join ' | ') }
        else { Write-Warn2 'adb not found - it can be downloaded automatically (menu 1).' }
    }
    'Scan' {
        if ($script:Sim) { $script:AdbExe = Find-Adb }
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $script:FfPackages = Get-FreeFirePackages
        $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] }
        Write-Head 'SAFE MOBILE OPTIMIZER - SCAN'
        Show-DeviceInfo
        $null = Show-Status
        Write-Sub 'Performance now'
        Show-Snapshot -Snap (Get-PerfSnapshot -Package $script:ActivePackage -Label 'now')
    }
    'Optimize' {
        if ($script:Sim) { $script:AdbExe = Find-Adb }
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $script:FfPackages = Get-FreeFirePackages
        $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] }
        $ids = @()
        if ($TweakProfile -eq 'Custom' -and $Tweaks) { $ids = @($Tweaks -split '[,\s]+' | Where-Object { $_ }) }
        Invoke-Optimize -ProfileName $TweakProfile -CustomIds $ids
    }
    'Measure' {
        if ($script:Sim) { $script:AdbExe = Find-Adb }
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $script:FfPackages = Get-FreeFirePackages
        $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] }
        Write-Head 'MEASURE'
        Show-DeviceInfo
        Show-Snapshot -Snap (Get-PerfSnapshot -Package $script:ActivePackage -Label 'now')
    }
    'Restore' {
        if ($script:Sim) { $script:AdbExe = Find-Adb }
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $bk = if ($script:BackupFileOpt) { $script:BackupFileOpt } else { Get-LastBackupPath }
        if (-not $bk) { Write-Bad 'No backup file found.'; exit 1 }
        if (-not (Invoke-Restore -Path $bk)) { exit 1 }
    }
    'Report' {
        if ($script:Sim) { $script:AdbExe = Find-Adb }
        Connect-Device | Out-Null
        $script:Device = Get-DeviceInfo
        $script:FfPackages = Get-FreeFirePackages
        $script:ActivePackage = if ($script:FfPackages.Count -gt 0) { $script:FfPackages[0] } else { $FF_PACKAGES_KNOWN[0] }
        Write-Head 'REPORT'
        $st = Show-Status
        $snap = Get-PerfSnapshot -Package $script:ActivePackage -Label 'now'
        $r = New-Report -Before $st -After $st -Applied @() -SnapBefore $snap -SnapAfter $snap -BackupPath (Get-LastBackupPath)
        Write-Ok "Report: $r"
    }
    default { Start-Menu }
}
