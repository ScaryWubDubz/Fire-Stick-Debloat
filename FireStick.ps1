# Fire Stick cleanup for Windows. Double-click Start-Here.bat to run this.
# Apps are disabled, never deleted. Everything removed is listed in
# disabled.txt so the "Undo" option can bring it all back.

$ErrorActionPreference = 'Continue'
# What the tool removed is tracked per Fire Stick (by serial number), in this
# folder and as a backup on the stick itself, so Undo and Re-apply keep working
# after this folder is moved or the tool is run from another computer.
# $Log is set once a stick is connected.
$Log = $null
$DeviceDir = '/sdcard/fire-stick-debloat'
$DeviceLog = "$DeviceDir/removed.txt"
# Before v1.2 a single list was shared by every stick the tool connected to.
$LegacyLog = Join-Path $PSScriptRoot 'disabled.txt'
$LegacyDeviceLog = "$DeviceDir/disabled.txt"

# Ads, tracking and background junk. Removed without asking.
$AdsTelemetry = @(
    'com.amazon.kso',                 # "Special offers": sponsored ads on the home screen
    'com.amazon.device.crashmanager', # crash reports sent to Amazon
    'com.amazon.dp.logger',           # usage logging
    'com.amazon.alexashopping',       # Alexa shopping prompts
    'com.amazon.ags.app',             # GameCircle
    'com.amazon.wifilocker',          # uploads your Wi-Fi passwords to Amazon
    'com.amazon.tv.csapp',            # customer service promo app
    'com.amazon.tv.legal.notices'     # legal notices viewer
)

# Amazon apps. You're asked about each one.
$AmazonApps = @(
    'com.amazon.amazonvideo.livingroom',
    'com.amazon.avod.thirdpartyclient',
    'com.amazon.imdb.tv.android.app',
    'com.amazon.bueller.music',
    'com.amazon.bueller.photos',
    'com.amazon.cloud9'
)

# Never touched: removing these can break the stick (home screen, Appstore,
# settings, remote/Alexa, casting) or the tools you need for the clean look.
$Protected = @(
    'com.amazon.tv.launcher', 'com.amazon.venezia', 'com.amazon.tv.settings',
    'com.amazon.tv.settings.v2', 'com.amazon.vizzini', 'com.amazon.tcomm',
    'com.amazon.whisperplay', 'com.amazon.device.sync', 'com.android.systemui',
    'com.spocky.projengmenu', 'com.esaba.downloader'
)

$Names = @{
    'com.amazon.amazonvideo.livingroom' = 'Prime Video'
    'com.amazon.avod.thirdpartyclient'  = 'Prime Video (extra copy)'
    'com.amazon.imdb.tv.android.app'    = 'Freevee'
    'com.amazon.bueller.music'          = 'Amazon Music'
    'com.amazon.bueller.photos'         = 'Amazon Photos (also the photo screensaver)'
    'com.amazon.cloud9'                 = 'Silk Browser'
    'com.netflix.ninja'                 = 'Netflix'
    'com.amazon.firetv.youtube'         = 'YouTube'
    'com.disney.disneyplus'             = 'Disney+'
    'com.hulu.plus'                     = 'Hulu'
    'com.wbd.stream'                    = 'Max'
    'com.cbs.ott'                       = 'Paramount+'
    'com.peacocktv.peacockandroid'      = 'Peacock'
    'com.apple.atve.amazon.appletv'     = 'Apple TV'
    'com.spotify.tv.android'            = 'Spotify'
    'com.plexapp.android'               = 'Plex'
    'tv.pluto.android'                  = 'Pluto TV'
    'com.tubitv'                        = 'Tubi'
    'com.tubitv.ott'                    = 'Tubi'
    'org.xbmc.kodi'                     = 'Kodi'
    'com.spocky.projengmenu'            = 'Projectivy Launcher'
    'org.pegasus_frontend.android'      = 'Pegasus'
}

function Get-Name([string]$Pkg) {
    if ($Names.ContainsKey($Pkg)) { return "$($Names[$Pkg])  ($Pkg)" }
    return $Pkg
}

function Find-Adb {
    $places = @(
        (Join-Path $PSScriptRoot 'adb.exe'),
        (Join-Path $PSScriptRoot 'platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\platform-tools\adb.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\platform-tools-latest-windows\platform-tools\adb.exe')
    )
    foreach ($p in $places) { if (Test-Path $p) { return $p } }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # Last resort: look through Downloads and Desktop (including OneDrive's Desktop).
    $roots = @((Join-Path $env:USERPROFILE 'Downloads'), [Environment]::GetFolderPath('Desktop')) |
        Where-Object { $_ -and (Test-Path $_) }
    if ($roots) {
        $hit = Get-ChildItem -Path $roots -Filter adb.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# Google's license doesn't allow shipping adb with this tool, so fetch the
# official copy into this folder the first time it's needed.
function Get-PlatformTools {
    Write-Host ''
    Write-Host "This tool needs Google's free Android platform-tools (adb), and it isn't on this computer yet."
    Write-Host 'It downloads from Google (a few MB). By downloading it you accept the Android SDK terms:'
    Write-Host '  https://developer.android.com/studio/terms'
    if (-not (Ask 'Download it now?')) { return $null }
    $zip = Join-Path $env:TEMP 'platform-tools-latest-windows.zip'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Windows PowerShell's progress bar makes downloads crawl.
        $ProgressPreference = 'SilentlyContinue'
        Write-Host 'Downloading...'
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $PSScriptRoot -Force
    } catch {
        Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    } finally {
        Remove-Item $zip -ErrorAction SilentlyContinue
    }
    $adb = Join-Path $PSScriptRoot 'platform-tools\adb.exe'
    if (Test-Path $adb) { Write-Host 'Done.' -ForegroundColor Green; return $adb }
    return $null
}

function Invoke-Adb([string[]]$AdbArgs) {
    (& $script:Adb $AdbArgs 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Invoke-Shell([string]$Cmd) {
    Invoke-Adb @('-s', $script:Target, 'shell', $Cmd)
}

function Ask([string]$Question) {
    (Read-Host "$Question [y/N]").Trim() -match '^[Yy]'
}

function Connect-Stick {
    Write-Host ''
    Write-Host "Find your Fire Stick's IP address on the TV:"
    Write-Host '  Settings > My Fire TV > About > Network   (it looks like 192.168.1.23)'
    while ($true) {
        $ip = (Read-Host 'Type the IP address and press Enter').Trim()
        if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$') { break }
        Write-Host "That doesn't look like an IP address. Example: 192.168.1.23" -ForegroundColor Yellow
    }
    $script:Target = "${ip}:5555"

    Write-Host 'Connecting... (can take up to 30 seconds)'
    $r = Invoke-Adb @('connect', $script:Target)
    # "failed to authenticate" is normal the first time: the TV is showing its permission popup.
    if ($r -notmatch 'connected|authenticate') {
        Write-Host "Couldn't reach the Fire Stick. Check that:" -ForegroundColor Red
        Write-Host '  - the TV is on and the stick is on the same Wi-Fi as this computer'
        Write-Host '  - Settings > My Fire TV > Developer Options > ADB Debugging is ON'
        Write-Host '  - the IP address is typed correctly'
        return $false
    }

    # The first time, the TV asks for permission before anything works.
    for ($i = 0; $i -lt 45; $i++) {
        $state = Invoke-Adb @('-s', $script:Target, 'get-state')
        if ($state -match '(^|\n)device') { Write-Host 'Connected!' -ForegroundColor Green; return $true }
        if ($i -eq 0) {
            Write-Host ''
            Write-Host 'LOOK AT YOUR TV: tick "Always allow from this computer", then select OK.' -ForegroundColor Cyan
        }
        if ($i -eq 15) {
            Invoke-Adb @('disconnect', $script:Target) | Out-Null
            Invoke-Adb @('connect', $script:Target) | Out-Null
        }
        Start-Sleep -Seconds 2
    }
    Write-Host "The TV didn't give permission in time. Run this again and watch the TV for the popup." -ForegroundColor Red
    return $false
}

function Get-Installed {
    (Invoke-Shell 'pm list packages') -split "`n" |
        ForEach-Object { $_.Trim() -replace '^package:', '' } | Where-Object { $_ }
}

# Apps you installed. Amazon's own background services are left out so you're
# only asked about apps you'd recognise.
function Get-YourApps {
    (Invoke-Shell 'pm list packages -3') -split "`n" |
        ForEach-Object { $_.Trim() -replace '^package:', '' } |
        Where-Object { $_ -and ($Protected -notcontains $_) -and ($AmazonApps -notcontains $_) -and ($AdsTelemetry -notcontains $_) } |
        Where-Object { ($_ -notlike 'com.amazon.*') -or $Names.ContainsKey($_) } |
        Sort-Object
}

function Disable-Pkg([string]$Pkg) {
    if ($Protected -contains $Pkg) { Write-Host "  skipped   $(Get-Name $Pkg) (the system needs it)"; return }
    # disable-user is the gentlest option; newer Fire OS blocks it for some
    # system apps, so fall back to removing it for this user (still undoable).
    $r = Invoke-Shell "pm disable-user --user 0 $Pkg"
    if ($r -notmatch 'disabled') { $r = Invoke-Shell "pm uninstall -k --user 0 $Pkg" }
    if ($r -match 'disabled|Success') {
        Write-Host "  removed   $(Get-Name $Pkg)" -ForegroundColor Green
        Add-Content -Path $Log -Value $Pkg
    } else {
        Write-Host "  couldn't remove $(Get-Name $Pkg) (Fire OS protects it; that's fine)" -ForegroundColor DarkGray
    }
}

function Show-Preview {
    $installed = Get-Installed
    Write-Host ''
    Write-Host 'Removed automatically (ads and tracking):' -ForegroundColor Cyan
    foreach ($p in $AdsTelemetry) { if ($installed -contains $p) { Write-Host "  $p" } }
    Write-Host ''
    Write-Host "You'll be asked about these (answer y only for ones you want gone):" -ForegroundColor Cyan
    foreach ($p in $AmazonApps) { if ($installed -contains $p) { Write-Host "  $(Get-Name $p)" } }
    foreach ($p in Get-YourApps) { Write-Host "  $(Get-Name $p)" }
    Write-Host ''
    Write-Host 'Nothing was changed.'
}

function Get-DisabledPackages {
    (Invoke-Shell 'pm list packages -d') -split "`n" |
        ForEach-Object { $_.Trim() -replace '^package:', '' } | Where-Object { $_ }
}

# Points $Log at this stick's own list. The first time a stick is seen, any
# shared list from before v1.2 is carried over, keeping only the apps that are
# actually off on this stick, so another stick's choices don't leak in.
function Initialize-RemovedList {
    $id = (Invoke-Shell 'getprop ro.serialno').Trim() -replace '[^A-Za-z0-9]', ''
    if (-not $id) { $id = (Invoke-Shell 'settings get secure android_id').Trim() -replace '[^A-Za-z0-9]', '' }
    if (-not $id) { $id = 'unknown' }
    $script:Log = Join-Path $PSScriptRoot "removed-$id.txt"

    if ((Test-Path -LiteralPath $Log) -or ((Invoke-Shell "[ -f $DeviceLog ] && echo yes") -match 'yes')) { return }
    $old = @()
    if (Test-Path -LiteralPath $LegacyLog) {
        $old += @(Get-Content -LiteralPath $LegacyLog | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $old += @((Invoke-Shell "cat $LegacyDeviceLog 2>/dev/null") -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.]+$' })
    if ($old.Count -eq 0) { return }
    $installed = Get-Installed
    $off = @(Get-DisabledPackages)
    $mine = @($old | Sort-Object -Unique | Where-Object { -not (($installed -contains $_) -and ($off -notcontains $_)) })
    if ($mine.Count -gt 0) { Set-Content -LiteralPath $Log -Value $mine }
    Invoke-Shell "rm -f $LegacyDeviceLog" | Out-Null
    if (Test-Path -LiteralPath $LegacyLog) { Move-Item -LiteralPath $LegacyLog -Destination "$LegacyLog.old" -Force }
    Write-Host "Now keeping a separate list of removed apps for each Fire Stick ($($mine.Count) on this one)." -ForegroundColor Green
}

function Get-LocalList {
    if (-not (Test-Path $Log)) { return @() }
    @(Get-Content $Log | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# Merges the list on this computer with the copy on the Fire Stick, saves the
# result to both, and returns it.
function Sync-RemovedList {
    $device = @((Invoke-Shell "cat $DeviceLog 2>/dev/null") -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z0-9_.]+$' })
    $all = @(@(Get-LocalList) + $device | Sort-Object -Unique)
    if ($all.Count -eq 0) { return @() }
    Set-Content -Path $Log -Value $all
    Invoke-Shell "mkdir -p $DeviceDir" | Out-Null
    Invoke-Adb @('-s', $script:Target, 'push', $Log, $DeviceLog) | Out-Null
    return $all
}

function Start-Cleanup {
    $installed = Get-Installed
    Write-Host ''
    Write-Host 'Removing ads and tracking...' -ForegroundColor Cyan
    foreach ($p in $AdsTelemetry) { if ($installed -contains $p) { Disable-Pkg $p } }

    Write-Host ''
    Write-Host 'Now each app. Type y and Enter to REMOVE it, or just press Enter to KEEP it.' -ForegroundColor Cyan
    foreach ($p in $AmazonApps) {
        if (($installed -contains $p) -and (Ask "Remove $(Get-Name $p)?")) { Disable-Pkg $p }
    }
    foreach ($p in Get-YourApps) {
        if (Ask "Remove $(Get-Name $p)?") { Disable-Pkg $p }
    }
    Sync-RemovedList | Out-Null
    Restart-Prompt
}

function Start-Undo {
    if (-not (Test-Path $Log)) { Write-Host 'Nothing to undo: the tool has no record of removing any apps.'; return }
    Write-Host ''
    Write-Host 'Bringing everything back...' -ForegroundColor Cyan
    foreach ($p in (Get-Content $Log | Where-Object { $_.Trim() } | Sort-Object -Unique)) {
        Invoke-Shell "cmd package install-existing --user 0 $p" | Out-Null
        Invoke-Shell "pm enable --user 0 $p" | Out-Null
        Write-Host "  restored  $(Get-Name $p)" -ForegroundColor Green
    }
    Remove-Item $Log
    Invoke-Shell "rm -f $DeviceLog" | Out-Null
    Restart-Prompt
}

# Projectivy takes over the Home button through an accessibility service.
# Fire OS often has no on-screen switch for it, so turn it on over ADB.
function Enable-Projectivy {
    $pkg = 'com.spocky.projengmenu'
    if ((Get-Installed) -notcontains $pkg) {
        Write-Host 'Projectivy Launcher is not installed yet. Install it on the Fire Stick, open it once, then try again.' -ForegroundColor Yellow
        return
    }
    $dump = Invoke-Shell "dumpsys package $pkg"
    $svc = $null
    if ($dump -match 'android\.accessibilityservice\.AccessibilityService:\s*\n\s*\S+\s+(com\.spocky\.projengmenu/\S+)') { $svc = $Matches[1] }
    elseif ($dump -match '(com\.spocky\.projengmenu/\S*[Aa]ccessib\S*)') { $svc = $Matches[1] }
    if (-not $svc) {
        Write-Host "Couldn't find Projectivy's Home button service. Use 'Override current launcher' in Projectivy's own settings instead." -ForegroundColor Yellow
        return
    }
    $current = (Invoke-Shell 'settings get secure enabled_accessibility_services').Trim()
    if ($current -like "*$svc*") {
        # Updates can switch accessibility off as a whole while leaving the list alone.
        Invoke-Shell 'settings put secure accessibility_enabled 1' | Out-Null
        Write-Host 'Projectivy controls the Home button.' -ForegroundColor Green
        return
    }
    # Keep any accessibility services that were already on.
    if ($current -and $current -ne 'null') { $new = "${current}:$svc" } else { $new = $svc }
    Invoke-Shell "settings put secure enabled_accessibility_services $new" | Out-Null
    Invoke-Shell 'settings put secure accessibility_enabled 1' | Out-Null
    if ((Invoke-Shell 'settings get secure enabled_accessibility_services') -like "*$svc*") {
        Write-Host 'Done! Press Home on your remote: you should land on Projectivy.' -ForegroundColor Green
        Write-Host '(If a Fire OS update ever brings back the Amazon home screen, just run option 4 again.)'
    } else {
        Write-Host "Fire OS didn't accept the change. Use 'Override current launcher' in Projectivy's own settings instead." -ForegroundColor Yellow
    }
}

# Installs an app file you downloaded on this computer (.apk, or a bundle such
# as .apkm/.apks/.xapk) straight onto the Fire Stick. No Downloader app needed.
function Install-FromComputer {
    $folders = @($PSScriptRoot, (Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { Test-Path $_ }
    $files = @(Get-ChildItem -Path $folders -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.apk', '.apkm', '.apks', '.xapk' } |
        Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending | Select-Object -First 9)
    if ($files.Count -eq 0) {
        Write-Host 'No app files (.apk or .apkm) found in your Downloads folder. Download one first.' -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host 'App files found (newest first):'
    for ($i = 0; $i -lt $files.Count; $i++) { Write-Host "  $($i + 1)  $($files[$i].Name)" }
    $pick = (Read-Host 'Type the number to install (or just press Enter for 1)').Trim()
    if (-not $pick) { $pick = '1' }
    if ($pick -notmatch '^[1-9]$' -or [int]$pick -gt $files.Count) { Write-Host 'Not a valid number.' -ForegroundColor Yellow; return }
    $file = $files[[int]$pick - 1]

    Write-Host "Sending $($file.Name) to the Fire Stick... (can take a minute)"
    if ($file.Extension -eq '.apk') {
        $r = Invoke-Adb @('-s', $script:Target, 'install', '-r', $file.FullName)
    } else {
        # A bundle is a zip of several .apk parts. Send the main part plus only
        # the processor-specific parts this Fire Stick can actually run.
        $tmp = Join-Path $env:TEMP ('firestick-' + [guid]::NewGuid())
        try {
            New-Item -ItemType Directory -Path $tmp | Out-Null
            $zip = Join-Path $tmp 'bundle.zip'
            Copy-Item $file.FullName $zip
            Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x') -ErrorAction Stop
        } catch {
            Write-Host "Couldn't open that file. Download the plain APK version instead." -ForegroundColor Yellow
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        $abis = (Invoke-Shell 'getprop ro.product.cpu.abilist').Trim().Replace('-', '_') -split ','
        $parts = @(Get-ChildItem (Join-Path $tmp 'x') -Filter *.apk -Recurse | Where-Object {
            if ($_.Name -match 'config\.(arm64_v8a|armeabi_v7a|armeabi|x86_64|x86)\.apk$') { $abis -contains $Matches[1] } else { $true }
        } | ForEach-Object { $_.FullName })
        if ($parts.Count -eq 0) {
            Write-Host "That file doesn't contain an app. Download the plain APK version instead." -ForegroundColor Yellow
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        $r = Invoke-Adb (@('-s', $script:Target, 'install-multiple', '-r') + $parts)
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($r -match 'Success') {
        Write-Host 'Installed! It is now in Your Apps & Channels on the Fire Stick.' -ForegroundColor Green
    } elseif ($r -match 'INSTALL_FAILED_OLDER_SDK') {
        $sdk = (Invoke-Shell 'getprop ro.build.version.sdk').Trim()
        Write-Host "That version needs a newer Android than your Fire Stick has (SDK $sdk)." -ForegroundColor Yellow
        Write-Host "On APKMirror, download a variant whose 'Minimum version' is Android 6.0 or similar, not 12L+." -ForegroundColor Yellow
    } else {
        Write-Host "The install didn't work. Here's what the Fire Stick said:" -ForegroundColor Red
        Write-Host $r
    }
}

# Folders some apps leave behind in shared storage after they're uninstalled.
$Leftovers = @{
    'org.pegasus_frontend.android' = '/sdcard/pegasus-frontend'
}

# Fully uninstalls an app you installed yourself (not Amazon's built-in ones;
# those are handled by "Clean up" and "Undo").
function Uninstall-App {
    $apps = @(Get-YourApps)
    if ($apps.Count -eq 0) { Write-Host 'No apps you installed were found.' -ForegroundColor Yellow; return }
    Write-Host ''
    Write-Host 'Apps you installed:'
    for ($i = 0; $i -lt $apps.Count; $i++) { Write-Host "  $($i + 1)  $(Get-Name $apps[$i])" }
    $pick = (Read-Host 'Type the number of the app to uninstall (or just Enter to cancel)').Trim()
    if (-not $pick) { return }
    if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $apps.Count) { Write-Host 'Not a valid number.' -ForegroundColor Yellow; return }
    $pkg = $apps[[int]$pick - 1]
    if (-not (Ask "Uninstall $(Get-Name $pkg) completely?")) { return }
    if ((Invoke-Shell "pm uninstall $pkg") -match 'Success') {
        Write-Host "  uninstalled  $(Get-Name $pkg)" -ForegroundColor Green
        if ($Leftovers.ContainsKey($pkg)) {
            Invoke-Shell "rm -rf $($Leftovers[$pkg])" | Out-Null
            Write-Host "  removed its leftover files" -ForegroundColor Green
        }
    } else {
        Write-Host "Couldn't uninstall $(Get-Name $pkg)." -ForegroundColor Red
    }
}

# Projectivy can't be shipped with this tool, so open its download page and
# then install whatever the person downloads.
function Get-Projectivy {
    $ver = (Invoke-Shell 'getprop ro.build.version.release').Trim()
    Write-Host ''
    Write-Host "Your Fire Stick runs Android $ver. Opening Projectivy's download page in your browser..." -ForegroundColor Cyan
    Start-Process 'https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/'
    Write-Host '  1. Click the newest version.'
    Write-Host "  2. In the Download table, pick a row whose minimum version is Android $ver or LOWER."
    Write-Host '     Skip rows that need a newer Android (for example "Android 12L+").'
    Write-Host '  3. Click "Download APK" under the app name (ignore the big ad buttons) and save it to Downloads.'
    Read-Host 'Press Enter here once the download has finished'
    Install-FromComputer
    if ((Get-Installed) -contains 'com.spocky.projengmenu') {
        Write-Host 'Next: open Projectivy once on the TV, then choose option 4 to make it your home screen.' -ForegroundColor Cyan
    }
}

# After a Fire OS update: turns off again anything from the last cleanup that
# the update switched back on, and gives Projectivy back the Home button.
function Start-Reapply {
    $list = @(Sync-RemovedList)
    if ($list.Count -eq 0) {
        Write-Host 'Nothing to re-apply yet. Run option 2 (Clean up) first.' -ForegroundColor Yellow
        return
    }
    $installed = Get-Installed
    $off = @(Get-DisabledPackages)
    # Removed-for-this-user apps don't show as installed, so only installed
    # apps that aren't disabled have come back.
    $back = @($list | Where-Object { ($installed -contains $_) -and ($off -notcontains $_) })
    Write-Host ''
    if ($back.Count -eq 0) {
        Write-Host "All $($list.Count) apps from your cleanup are still off." -ForegroundColor Green
    } else {
        Write-Host "$($back.Count) of $($list.Count) apps came back after the update. Turning them off again..." -ForegroundColor Cyan
        foreach ($p in $back) { Disable-Pkg $p }
        Sync-RemovedList | Out-Null
    }
    if ($installed -contains 'com.spocky.projengmenu') { Enable-Projectivy }
    if ($back.Count -gt 0) { Restart-Prompt }
}

function Restart-Prompt {
    Write-Host ''
    if (Ask 'Done. Restart the Fire Stick now to finish?') {
        Invoke-Adb @('-s', $script:Target, 'reboot') | Out-Null
        Write-Host 'Restarting. Give it about a minute.'
    }
}

# --- main ---
Write-Host '=============================='
Write-Host '     Fire Stick Cleanup'
Write-Host '=============================='

$Adb = Find-Adb
if (-not $Adb) { $Adb = Get-PlatformTools }
if (-not $Adb) {
    Write-Host "Couldn't find adb.exe. Put this file and Start-Here.bat inside the" -ForegroundColor Red
    Write-Host "'platform-tools' folder you downloaded (the one with adb.exe in it), then try again." -ForegroundColor Red
    Write-Host "If platform-tools is still a .zip file, right-click it and choose 'Extract All' first." -ForegroundColor Red
    return
}
if (-not (Connect-Stick)) { return }
Initialize-RemovedList

$hadDeviceCopy = (Invoke-Shell "[ -f $DeviceLog ] && echo yes") -match 'yes'
$localCount = @(Get-LocalList).Count
$synced = @(Sync-RemovedList)
if ($synced.Count -gt $localCount) {
    Write-Host "Restored your list of removed apps from the Fire Stick's backup." -ForegroundColor Green
} elseif ($synced.Count -gt 0 -and -not $hadDeviceCopy -and
          ((Invoke-Shell "[ -f $DeviceLog ] && echo yes") -match 'yes')) {
    Write-Host 'Backed up your list of removed apps to the Fire Stick.' -ForegroundColor Green
}

while ($true) {
    Write-Host ''
    Write-Host 'What do you want to do?'
    Write-Host '  1  Preview (shows what would happen, changes nothing)'
    Write-Host '  2  Clean up my Fire Stick'
    Write-Host '  3  Undo everything'
    Write-Host '  4  Make Projectivy my home screen (install Projectivy first)'
    Write-Host '  5  Install an app file from this computer (.apk)'
    Write-Host '  6  Uninstall an app I installed'
    Write-Host '  7  Get Projectivy Launcher (opens its download page, then installs it)'
    Write-Host '  8  Re-apply my cleanup (after a Fire OS update)'
    Write-Host '  Q  Quit'
    switch ((Read-Host 'Type a number, or Q to quit').Trim().ToUpper()) {
        '1' { Show-Preview }
        '2' { Start-Cleanup }
        '3' { Start-Undo }
        '4' { Enable-Projectivy }
        '5' { Install-FromComputer }
        '6' { Uninstall-App }
        '7' { Get-Projectivy }
        '8' { Start-Reapply }
        'Q' { return }
        default { Write-Host 'Please type a number from the list, or Q.' -ForegroundColor Yellow }
    }
}
