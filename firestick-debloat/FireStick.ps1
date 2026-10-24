# Fire Stick cleanup for Windows. Double-click Start-Here.bat to run this.
# Apps are disabled, never deleted. Everything removed is listed in
# disabled.txt so the "Undo" option can bring it all back.

$ErrorActionPreference = 'Continue'
$Log = Join-Path $PSScriptRoot 'disabled.txt'

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
    'org.xbmc.kodi'                     = 'Kodi'
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
    Restart-Prompt
}

function Start-Undo {
    if (-not (Test-Path $Log)) { Write-Host 'Nothing to undo: no apps have been removed from this folder.'; return }
    Write-Host ''
    Write-Host 'Bringing everything back...' -ForegroundColor Cyan
    foreach ($p in (Get-Content $Log | Where-Object { $_.Trim() } | Sort-Object -Unique)) {
        Invoke-Shell "cmd package install-existing --user 0 $p" | Out-Null
        Invoke-Shell "pm enable --user 0 $p" | Out-Null
        Write-Host "  restored  $(Get-Name $p)" -ForegroundColor Green
    }
    Remove-Item $Log
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
        Write-Host 'Projectivy already controls the Home button.' -ForegroundColor Green
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

# --- Pegasus themes ---
$PegasusPkg = 'org.pegasus_frontend.android'

# Remote buttons Pegasus ignores out of the box. Each entry is the key's default
# binding plus the Fire TV remote button added to it: Menu opens Pegasus's main
# menu, Back goes back, Play/Pause shows details, Rewind/Fast-forward change page.
$PegasusKeys = [ordered]@{
    'keys.menu'      = @('F1,GamepadStart', 'Menu')
    'keys.cancel'    = @('Esc,Backspace,GamepadB', 'Back')
    'keys.details'   = @('I,GamepadX', 'Toggle Media Play/Pause')
    'keys.prev-page' = @('Q,A,GamepadL1', 'Media Rewind')
    'keys.next-page' = @('E,D,GamepadR1', 'Media Fast Forward')
}

# Pegasus creates its settings folder the first time it opens; depending on the
# build it is in one of these two places.
function Get-PegasusDir {
    if ((Get-Installed) -notcontains $PegasusPkg) {
        Write-Host 'Pegasus is not installed yet. Install it with option 5 first.' -ForegroundColor Yellow
        return $null
    }
    $candidates = @("/sdcard/Android/data/$PegasusPkg/files/pegasus-frontend", '/sdcard/pegasus-frontend')
    $existing = @($candidates | Where-Object { (Invoke-Shell "[ -d $_ ] && echo yes") -match 'yes' })
    foreach ($d in $existing) {
        if ((Invoke-Shell "[ -f $d/settings.txt ] && echo yes") -match 'yes') { return $d }
    }
    if ($existing.Count -gt 0) { return $existing[0] }
    Write-Host 'Open Pegasus once on the TV so it can set itself up, then try again.' -ForegroundColor Yellow
    return $null
}

function Set-SettingLine($Lines, [string]$Key, [string]$Value) {
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^$([regex]::Escape($Key))\s*:") { $Lines[$i] = "${Key}: $Value"; return }
    }
    $Lines.Add("${Key}: $Value")
}

# Writes the theme (and the remote buttons) into Pegasus's settings.txt,
# keeping every other setting as it was.
function Set-PegasusTheme([string]$Dir, [string]$ThemeValue) {
    # Pegasus rewrites settings.txt when it closes, so stop it first.
    Invoke-Shell "am force-stop $PegasusPkg" | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in ((Invoke-Shell "cat $Dir/settings.txt 2>/dev/null") -split "`n")) {
        if ($l.Trim()) { $lines.Add($l.TrimEnd()) }
    }
    Set-SettingLine $lines 'general.theme' $ThemeValue
    foreach ($key in $PegasusKeys.Keys) {
        $current = $PegasusKeys[$key][0]
        foreach ($l in $lines) {
            if ($l -match "^$([regex]::Escape($key))\s*:\s*(.*)$") { $current = $Matches[1].Trim() }
        }
        $tokens = @($current -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($tokens -notcontains $PegasusKeys[$key][1]) { $tokens += $PegasusKeys[$key][1] }
        Set-SettingLine $lines $key ($tokens -join ',')
    }
    $tmp = Join-Path $env:TEMP 'pegasus-settings.txt'
    # No byte-order mark: Pegasus would read it as part of the first setting's name.
    [IO.File]::WriteAllText($tmp, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    $r = Invoke-Adb @('-s', $script:Target, 'push', $tmp, "$Dir/settings.txt")
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return ($r -match 'pushed')
}

# Copies a theme you downloaded (the .zip, or the folder you extracted) to the
# Fire Stick and switches Pegasus to it.
function Install-PegasusTheme {
    $dir = Get-PegasusDir
    if (-not $dir) { return }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $roots = @($PSScriptRoot, (Join-Path $env:USERPROFILE 'Downloads')) | Where-Object { Test-Path $_ }
    $found = @()
    foreach ($z in (Get-ChildItem -Path $roots -Filter *.zip -File -ErrorAction SilentlyContinue)) {
        try {
            $zip = [IO.Compression.ZipFile]::OpenRead($z.FullName)
            $isTheme = @($zip.Entries | Where-Object { $_.Name -eq 'theme.cfg' }).Count -gt 0
            $zip.Dispose()
            if ($isTheme) { $found += $z }
        } catch { }
    }
    foreach ($cfg in (Get-ChildItem -Path $roots -Filter theme.cfg -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)) {
        $found += $cfg.Directory
    }
    $found = @($found | Sort-Object FullName -Unique | Sort-Object LastWriteTime -Descending | Select-Object -First 9)
    if ($found.Count -eq 0) {
        Write-Host 'No Pegasus themes found in your Downloads folder. Download a theme .zip first.' -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host 'Themes found (newest first):'
    for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1)  $($found[$i].Name)" }
    $pick = (Read-Host 'Type the number to install (or just press Enter for 1)').Trim()
    if (-not $pick) { $pick = '1' }
    if ($pick -notmatch '^[1-9]$' -or [int]$pick -gt $found.Count) { Write-Host 'Not a valid number.' -ForegroundColor Yellow; return }
    $item = $found[[int]$pick - 1]

    $tmp = $null
    if ($item -is [IO.FileInfo]) {
        $tmp = Join-Path $env:TEMP ('pegasus-theme-' + [guid]::NewGuid())
        try { [IO.Compression.ZipFile]::ExtractToDirectory($item.FullName, $tmp) }
        catch {
            Write-Host "Couldn't open that zip file. Try downloading it again." -ForegroundColor Yellow
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        $searchRoot = $tmp
        $fallbackName = $item.BaseName
    } else {
        $searchRoot = $item.FullName
        $fallbackName = $item.Name
    }
    # The theme is the folder holding theme.cfg; take the shallowest one.
    $cfgFile = Get-ChildItem -Path $searchRoot -Filter theme.cfg -File -Recurse |
        Sort-Object { $_.FullName.Length } | Select-Object -First 1
    $themeDir = $cfgFile.Directory.FullName
    if ($themeDir -eq $tmp) { $name = $fallbackName } else { $name = $cfgFile.Directory.Name }
    # GitHub zips are named like gameOS-master; keep it short and shell-safe.
    $name = ($name -replace '-(master|main)$', '') -replace '[^A-Za-z0-9._-]', '_'
    if (-not $name) { $name = 'theme' }

    Write-Host "Copying '$name' to the Fire Stick... (can take a minute)"
    Invoke-Shell "mkdir -p $dir/themes" | Out-Null
    Invoke-Shell "rm -rf $dir/themes/$name" | Out-Null
    $r = Invoke-Adb @('-s', $script:Target, 'push', $themeDir, "$dir/themes/$name")
    if ($tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    if ($r -notmatch 'pushed') {
        Write-Host "Copying didn't work. Here's what the Fire Stick said:" -ForegroundColor Red
        Write-Host $r
        return
    }
    if (Set-PegasusTheme $dir "themes/$name/") {
        Write-Host "Installed and switched to '$name'. Open Pegasus to see it." -ForegroundColor Green
        Write-Host 'Remote: Menu button = Pegasus menu, Back = back, Play/Pause = details, Rewind/Fast-forward = change page.'
    } else {
        Write-Host "The theme was copied, but switching to it didn't work. Pick it in Pegasus: Menu button > Settings > Theme." -ForegroundColor Yellow
    }
}

function Switch-PegasusTheme {
    $dir = Get-PegasusDir
    if (-not $dir) { return }
    $themes = @((Invoke-Shell "ls -1 $dir/themes 2>/dev/null") -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    Write-Host ''
    Write-Host 'Pegasus themes on your Fire Stick:'
    Write-Host '  0  Pegasus default (grid)'
    for ($i = 0; $i -lt $themes.Count; $i++) { Write-Host "  $($i + 1)  $($themes[$i])" }
    $pick = (Read-Host 'Type the number of the theme to use').Trim()
    if ($pick -eq '0') {
        $value = ':/themes/pegasus-theme-grid/'; $label = 'the default theme'
    } elseif ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $themes.Count) {
        $label = $themes[[int]$pick - 1]; $value = "themes/$label/"
    } else {
        Write-Host 'Not a valid number.' -ForegroundColor Yellow
        return
    }
    if (Set-PegasusTheme $dir $value) { Write-Host "Switched to $label. Open Pegasus to see it." -ForegroundColor Green }
    else { Write-Host "Couldn't save the setting on the Fire Stick." -ForegroundColor Red }
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
if (-not $Adb) {
    Write-Host "Couldn't find adb.exe. Put this file and Start-Here.bat inside the" -ForegroundColor Red
    Write-Host "'platform-tools' folder you downloaded (the one with adb.exe in it), then try again." -ForegroundColor Red
    Write-Host "If platform-tools is still a .zip file, right-click it and choose 'Extract All' first." -ForegroundColor Red
    return
}
if (-not (Connect-Stick)) { return }

while ($true) {
    Write-Host ''
    Write-Host 'What do you want to do?'
    Write-Host '  1  Preview (shows what would happen, changes nothing)'
    Write-Host '  2  Clean up my Fire Stick'
    Write-Host '  3  Undo everything'
    Write-Host '  4  Make Projectivy my home screen (install Projectivy first)'
    Write-Host '  5  Install an app file from this computer (.apk)'
    Write-Host '  6  Install a Pegasus theme from this computer'
    Write-Host '  7  Switch Pegasus theme'
    Write-Host '  Q  Quit'
    switch ((Read-Host 'Type a number, or Q to quit').Trim().ToUpper()) {
        '1' { Show-Preview }
        '2' { Start-Cleanup }
        '3' { Start-Undo }
        '4' { Enable-Projectivy }
        '5' { Install-FromComputer }
        '6' { Install-PegasusTheme }
        '7' { Switch-PegasusTheme }
        'Q' { return }
        default { Write-Host 'Please type a number from the list, or Q.' -ForegroundColor Yellow }
    }
}
