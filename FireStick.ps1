# Fire Stick cleanup for Windows. Double-click Start-Here.bat to run this.
# Apps are disabled, never deleted. Everything removed is listed in
# disabled.txt so the "Undo" option can bring it all back.

$ErrorActionPreference = 'Continue'
# The release workflow (.github/workflows/release.yml) stamps the release tag
# here when it builds the zip. 'dev' means running from the source code, which
# skips the update check.
$ToolVersion = 'dev'
$LatestReleaseApi = 'https://api.github.com/repos/cmeraspro-dev/Fire-Stick-Debloat/releases/latest'
$LogDir = Join-Path $PSScriptRoot 'logs'
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
    'com.spocky.projengmenu', 'com.esaba.downloader', 'io.github.toolicious.homeonfire'
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
    'io.github.toolicious.homeonfire'   = 'Home on Fire'
    'com.seeker.tv'                     = 'Seeker TV'
    'ar.tvplayer.tv'                    = 'TiviMate'
    'com.hbo.hbonow'                    = 'HBO Max'
    'com.sling'                         = 'Sling TV'
    'com.stremio.one'                   = 'Stremio'
    'com.tiktok.tv'                     = 'TikTok'
    'com.koushikdutta.cast.receiver'    = 'AllCast Receiver'
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

# Looks on this computer's network for devices that accept ADB connections
# (port 5555), so nobody has to look up the stick's IP address. Only the local
# network is searched, and nothing is saved.
function Find-Sticks {
    $mine = @()
    $targets = @()
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        # One adapter that can't be read shouldn't stop the search on the others.
        try {
            if ("$($nic.OperationalStatus)" -ne 'Up') { continue }
            $props = $nic.GetIPProperties()
            # Only networks with a router (home Wi-Fi or Ethernet), which skips virtual adapters.
            $gateways = @($props.GatewayAddresses | Where-Object { "$($_.Address.AddressFamily)" -eq 'InterNetwork' -and "$($_.Address)" -ne '0.0.0.0' })
            if ($gateways.Count -eq 0) { continue }
            foreach ($a in $props.UnicastAddresses) {
                $addr = "$($a.Address)"
                if ($addr -notmatch '^(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+$') { continue }
                $mine += $addr
                $b = $a.Address.GetAddressBytes(); [array]::Reverse($b)
                $ipNum = [int64][BitConverter]::ToUInt32($b, 0)
                $m = $a.IPv4Mask.GetAddressBytes(); [array]::Reverse($m)
                $maskNum = [int64][BitConverter]::ToUInt32($m, 0)
                # Search the whole network, which can be bigger than 254 addresses (mesh
                # routers such as eero use 192.168.4.0 to 192.168.7.255), up to 1024.
                if ($maskNum -gt 4294966272) { $size = 4294967296 - $maskNum } else { $size = 1024; $maskNum = 4294966272 }
                $net = $ipNum -band $maskNum
                for ($h = 1; $h -lt $size - 1; $h++) {
                    $nb = [BitConverter]::GetBytes([uint32]($net + $h)); [array]::Reverse($nb)
                    $targets += ([System.Net.IPAddress]::new($nb)).ToString()
                }
            }
        } catch {
            Write-Verbose "Skipped a network adapter: $_"
        }
    }
    $targets = @($targets | Where-Object { $mine -notcontains $_ } | Select-Object -Unique)
    if ($targets.Count -eq 0) { return @() }
    Write-Host "  (searching $($targets[0]) to $($targets[-1]))" -ForegroundColor DarkGray
    $found = @()
    # 256 at a time, so the network isn't flooded. Devices on the same Wi-Fi
    # answer well within the wait.
    for ($start = 0; $start -lt $targets.Count; $start += 256) {
        $probes = @()
        foreach ($addr in $targets[$start..([Math]::Min($start + 255, $targets.Count - 1))]) {
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $probes += [pscustomobject]@{ Ip = $addr; Client = $client; Task = $client.ConnectAsync($addr, 5555) }
            } catch {
                Write-Verbose "Couldn't check ${addr}: $_"
            }
        }
        Start-Sleep -Milliseconds 1500
        $found += @($probes | Where-Object { "$($_.Task.Status)" -eq 'RanToCompletion' } | ForEach-Object { $_.Ip })
        foreach ($p in $probes) { $p.Client.Close() }
    }
    return $found
}

function Show-AdbSteps {
    Write-Host 'Turn on ADB Debugging on the TV, using the remote:'
    Write-Host '  1. Press Home. Go to the gear icon (Settings) at the right end of the menu and press the center button.'
    Write-Host '  2. Open My Fire TV (called Device & Software on some models), then About.'
    Write-Host '  3. The first line, with your Fire Stick name, is highlighted. Press the center button 7 times,'
    Write-Host '     until it says "You are now a developer" or "No need, you are already a developer".'
    Write-Host '  4. Press Back once, open Developer Options, and turn ADB Debugging ON.'
    Write-Host 'Also check that the TV is on and the stick is on the same Wi-Fi as this computer.'
}

# Finds the Fire Stick on the network, or asks for its IP address, and
# connects. $Skip leaves out the stick that's connected now (for Switch).
function Connect-Stick([string]$Skip) {
    $ip = $null
    while (-not $ip) {
        Write-Host ''
        Write-Host 'Looking for your Fire Stick on this Wi-Fi... (a few seconds)'
        $found = @(Find-Sticks | Where-Object { $_ -ne $Skip })
        $answer = ''
        if ($found.Count -eq 1) {
            Write-Host "Found a Fire Stick at $($found[0])." -ForegroundColor Green
            $answer = '1'
        } elseif ($found.Count -gt 1) {
            Write-Host 'Found more than one:'
            for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1)  $($found[$i])" }
            Write-Host "(Each stick's address is on its TV under Settings > My Fire TV > About > Network.)"
            $answer = (Read-Host 'Type its number or IP address (Q to stop)').Trim()
        } else {
            Write-Host "Couldn't find a Fire Stick on this Wi-Fi." -ForegroundColor Yellow
            Show-AdbSteps
            Write-Host "If it still isn't found, type its IP address instead. It's on the TV under"
            Write-Host '  Settings > My Fire TV > About > Network   (it looks like 192.168.1.23)'
            $answer = (Read-Host 'Press Enter to search again, or type the IP address (Q to stop)').Trim()
        }
        if ($answer -match '^[Qq]$') { return $false }
        if ($answer -match '^\d{1,2}$' -and [int]$answer -ge 1 -and [int]$answer -le $found.Count) {
            $ip = $found[[int]$answer - 1]
        } elseif ($answer -match '^\d{1,3}(\.\d{1,3}){3}$') {
            $ip = $answer
        } elseif ($answer) {
            Write-Host "That doesn't look like an IP address. Example: 192.168.1.23" -ForegroundColor Yellow
        }
    }
    $script:Target = "${ip}:5555"

    Write-Host 'Connecting... (can take up to 30 seconds)'
    $r = Invoke-Adb @('connect', $script:Target)
    # Success is "connected to" or "already connected to"; "failed to authenticate
    # to" is normal the first time (the TV is showing its permission popup).
    # Match adb's wording at the start of a line: Windows' own timeout message
    # ("...the connected party did not properly respond...") contains the word too.
    if ($r -notmatch '(^|\n)\s*(already connected to|connected to|failed to authenticate to)') {
        Write-Host "Couldn't reach the Fire Stick at $ip." -ForegroundColor Red
        Show-AdbSteps
        Write-Host 'If you typed the IP address, check it on the TV: Settings > My Fire TV > About > Network.'
        return $false
    }

    # The first time, the TV asks for permission before anything works.
    for ($i = 0; $i -lt 45; $i++) {
        $state = Invoke-Adb @('-s', $script:Target, 'get-state')
        if ($state -match '(^|\n)device') {
            # The name shown in Settings > My Fire TV > About, to tell sticks apart.
            $name = (Invoke-Shell 'settings get global device_name').Trim()
            if (-not $name -or $name -eq 'null') { $name = 'the Fire Stick' }
            $script:StickName = $name
            Write-Host "Connected to $name!" -ForegroundColor Green
            return $true
        }
        if ($i -eq 0) {
            Write-Host ''
            Write-Host 'LOOK AT YOUR TV: a box asks "Allow USB debugging?". With the remote:' -ForegroundColor Cyan
            Write-Host '  1. Use the arrows to highlight "Always allow from this computer" and press the center button to tick it.' -ForegroundColor Cyan
            Write-Host '  2. Highlight OK and press the center button.' -ForegroundColor Cyan
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

# Installed apps that aren't switched off yet: the ones a cleanup can still act
# on. (Apps that are switched off still count as installed.)
function Get-ActiveApps {
    $off = @(Get-DisabledPackages)
    @(Get-Installed | Where-Object { $off -notcontains $_ })
}

function Show-Preview {
    $active = Get-ActiveApps
    $auto = @($AdsTelemetry | Where-Object { $active -contains $_ })
    $asked = @(@($AmazonApps) + @(Get-YourApps) | Where-Object { $active -contains $_ })
    Write-Host ''
    Write-Host 'Removed automatically (ads and tracking):' -ForegroundColor Cyan
    foreach ($p in $auto) { Write-Host "  $p" }
    if ($auto.Count -eq 0) { Write-Host '  (nothing left: these are already off)' }
    Write-Host ''
    Write-Host "You'll be asked about these (answer y only for ones you want gone):" -ForegroundColor Cyan
    foreach ($p in $asked) { Write-Host "  $(Get-Name $p)" }
    if ($asked.Count -eq 0) { Write-Host '  (none)' }
    Write-Host ''
    Write-Host 'Apps that are already off are left out. Nothing was changed.'
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

function Start-Cleanup([switch]$NoRestart) {
    # Apps that are already off (from an earlier cleanup) are skipped.
    $active = Get-ActiveApps
    Write-Host ''
    Write-Host 'Removing ads and tracking...' -ForegroundColor Cyan
    foreach ($p in $AdsTelemetry) { if ($active -contains $p) { Disable-Pkg $p } }

    Write-Host ''
    Write-Host 'Now each app. Type y and Enter to REMOVE it, or just press Enter to KEEP it.' -ForegroundColor Cyan
    foreach ($p in $AmazonApps) {
        if (($active -contains $p) -and (Ask "Remove $(Get-Name $p)?")) { Disable-Pkg $p }
    }
    foreach ($p in Get-YourApps) {
        if (($active -contains $p) -and (Ask "Remove $(Get-Name $p)?")) { Disable-Pkg $p }
    }
    Sync-RemovedList | Out-Null
    if (-not $NoRestart) { Restart-Prompt }
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
# Fire OS ignores the normal "default home app" setting, so the Home button is
# taken over by an accessibility service that opens a launcher whenever
# Amazon's home screen appears. Projectivy has its own; for any other launcher
# the free, open-source Home on Fire app does it.
$ProjectivyPkg = 'com.spocky.projengmenu'
$HomeOnFirePkg = 'io.github.toolicious.homeonfire'
$HomeOnFireApk = 'https://github.com/toolicious/home-on-fire/releases/latest/download/home-on-fire.apk'
$HomeChoiceFile = "$DeviceDir/home.txt"

function Get-AccessibilityService([string]$Pkg) {
    $dump = Invoke-Shell "dumpsys package $Pkg"
    $esc = [regex]::Escape($Pkg)
    if ($dump -match "android\.accessibilityservice\.AccessibilityService:\s*\n\s*\S+\s+($esc/\S+)") { return $Matches[1] }
    if ($dump -match "($esc/\S*[Aa]ccessib\S*)") { return $Matches[1] }
    return $null
}

# Switches on one app's Home-button service and switches off the other's, so
# the two never fight over Home. Other accessibility services are kept.
# Remembers the choice on the stick so Re-apply can restore it.
function Set-HomeService([string]$Pkg) {
    $svc = Get-AccessibilityService $Pkg
    if (-not $svc) { return $false }
    $current = (Invoke-Shell 'settings get secure enabled_accessibility_services').Trim()
    $keep = @()
    if ($current -and $current -ne 'null') {
        $keep = @($current -split ':' | Where-Object { $_ -and $_ -notlike "$ProjectivyPkg/*" -and $_ -notlike "$HomeOnFirePkg/*" })
    }
    $new = (@($keep) + $svc) -join ':'
    Invoke-Shell "settings put secure enabled_accessibility_services '$new'" | Out-Null
    Invoke-Shell 'settings put secure accessibility_enabled 1' | Out-Null
    Invoke-Shell "mkdir -p $DeviceDir && echo $Pkg > $HomeChoiceFile" | Out-Null
    return ((Invoke-Shell 'settings get secure enabled_accessibility_services') -like "*$svc*")
}

function Enable-Projectivy {
    if ((Get-Installed) -notcontains $ProjectivyPkg) {
        Write-Host 'Projectivy Launcher is not installed yet. Install it with option 7, open it once, then try again.' -ForegroundColor Yellow
        return
    }
    if (Set-HomeService $ProjectivyPkg) {
        Write-Host 'Done! Press Home on your remote: you should land on Projectivy.' -ForegroundColor Green
        Write-Host '(If a Fire OS update ever brings back the Amazon home screen, run option 8.)'
    } else {
        Write-Host "Fire OS didn't accept the change. Use 'Override current launcher' in Projectivy's own settings instead." -ForegroundColor Yellow
    }
}

function Enable-HomeOnFire {
    if ((Get-Installed) -notcontains $HomeOnFirePkg) {
        Write-Host ''
        Write-Host 'Any launcher can take over the Home button with Home on Fire, a free, open-source helper app'
        Write-Host '(no internet access): https://github.com/toolicious/home-on-fire'
        if (-not (Ask 'Download Home on Fire from GitHub and install it?')) { return }
        $apk = Join-Path $env:TEMP 'home-on-fire.apk'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Write-Host 'Downloading...'
            Invoke-WebRequest -Uri $HomeOnFireApk -OutFile $apk -UseBasicParsing
        } catch {
            Write-Host "Download failed: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
        $r = Invoke-Adb @('-s', $script:Target, 'install', '-r', $apk)
        Remove-Item $apk -ErrorAction SilentlyContinue
        if ($r -notmatch 'Success') {
            Write-Host "Installing Home on Fire didn't work. Here's what the Fire Stick said:" -ForegroundColor Red
            Write-Host $r
            return
        }
    }
    # Home on Fire's own setup needs this on Fire OS builds that hide the Accessibility page.
    Invoke-Shell "pm grant $HomeOnFirePkg android.permission.WRITE_SECURE_SETTINGS" | Out-Null
    if (Set-HomeService $HomeOnFirePkg) {
        Write-Host 'Home on Fire now controls the Home button.' -ForegroundColor Green
    } else {
        Write-Host "Couldn't switch on Home on Fire's Home button service; finish its setup on the TV." -ForegroundColor Yellow
    }
    Invoke-Shell "am start -n $HomeOnFirePkg/.MainActivity" | Out-Null
    Write-Host 'Home on Fire is now open on the TV: pick the launcher the Home button should open.' -ForegroundColor Cyan
    Write-Host '(If your launcher is not installed yet, install it first with option 5.)'
    Write-Host "Tip: if Amazon's home screen keeps coming back, hold the remote's Menu button to open"
    Write-Host "Home on Fire's settings and turn off its double-press escape to Amazon's home screen."
}

function Select-HomeLauncher {
    Write-Host ''
    Write-Host 'Which launcher should the Home button open?'
    Write-Host '  1  Projectivy (recommended: the most reliable on Fire TV)'
    Write-Host '  2  Another launcher I installed (uses Home on Fire)'
    switch ((Read-Host 'Type 1 or 2').Trim()) {
        '1' { Enable-Projectivy }
        '2' { Enable-HomeOnFire }
        default { Write-Host 'Nothing changed.' }
    }
}

# Gives the Home button back to whichever app was chosen in option 4
# (Projectivy if nothing was recorded, as before this choice existed).
function Restore-HomeChoice {
    $choice = (Invoke-Shell "cat $HomeChoiceFile 2>/dev/null").Trim()
    if ($choice -ne $HomeOnFirePkg) { $choice = $ProjectivyPkg }
    if ((Get-Installed) -notcontains $choice) { return }
    if ($choice -eq $HomeOnFirePkg) {
        Invoke-Shell "pm grant $HomeOnFirePkg android.permission.WRITE_SECURE_SETTINGS" | Out-Null
    }
    if (Set-HomeService $choice) {
        Write-Host "$($Names[$choice]) controls the Home button." -ForegroundColor Green
    } else {
        Write-Host "Couldn't give $($Names[$choice]) the Home button back. Try option 4." -ForegroundColor Yellow
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
    $null = Read-Host 'Press Enter here once the download has finished'
    Install-FromComputer
    return ((Get-Installed) -contains $ProjectivyPkg)
}

# Walks someone through the whole setup in order, for a first run.
function Start-FirstTime {
    Write-Host ''
    Write-Host "Step 1 of 4: turn off ads in the Fire Stick's own settings" -ForegroundColor Cyan
    Write-Host "The tool can't change these for you. On the TV, open Settings (the gear icon), then Preferences:"
    Write-Host '  - Featured Content: turn off video autoplay, audio autoplay and sponsored content.'
    Write-Host '  - Privacy Settings: turn off Device Usage Data, Collect App Usage Data and Interest-based Ads.'
    $null = Read-Host 'Press Enter when you are done (or to skip this step)'

    Write-Host ''
    Write-Host "Step 2 of 4: remove ads, tracking and apps you don't use" -ForegroundColor Cyan
    Show-Preview
    if (Ask 'Start the cleanup now?') { Start-Cleanup -NoRestart }

    Write-Host ''
    Write-Host 'Step 3 of 4: install Projectivy, the clean home screen' -ForegroundColor Cyan
    $hasProjectivy = (Get-Installed) -contains $ProjectivyPkg
    if ($hasProjectivy) {
        Write-Host 'Projectivy is already installed.'
    } elseif (Ask 'Install Projectivy Launcher now? (recommended)') {
        $hasProjectivy = Get-Projectivy
    }

    Write-Host ''
    Write-Host 'Step 4 of 4: make the Home button open Projectivy' -ForegroundColor Cyan
    if ($hasProjectivy) {
        # Projectivy finishes setting itself up the first time it's opened.
        $r = Invoke-Shell "monkey -p $ProjectivyPkg -c android.intent.category.LEANBACK_LAUNCHER 1"
        if ($r -match 'No activities') { Invoke-Shell "monkey -p $ProjectivyPkg -c android.intent.category.LAUNCHER 1" | Out-Null }
        Write-Host "Projectivy should now be open on the TV. If it isn't, open it from Your Apps & Channels."
        $null = Read-Host 'Go through its welcome screens, then press Enter here'
        Enable-Projectivy
        Write-Host ''
        Write-Host 'To finish the look: in Projectivy, press Up to the top bar and open the gear icon. Hide the rows'
        Write-Host "you don't need and pick a calm wallpaper. Step 5 of README.md has the details."
    } else {
        Write-Host "Skipped, because Projectivy isn't installed. You can do it later with options 7 and 4,"
        Write-Host 'or make another launcher your home screen with option 4.'
    }
    Restart-Prompt
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
    Restore-HomeChoice
    if ($back.Count -gt 0) { Restart-Prompt }
}

# Connects to a stick and loads its own list of removed apps.
function Open-Stick([string]$Skip) {
    if (-not (Connect-Stick $Skip)) { return $false }
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
    Write-Host "Apps the tool has removed on this Fire Stick: $(@(Get-LocalList).Count)" -ForegroundColor DarkGray
    return $true
}

# Moves to another Fire Stick without restarting the tool. If the new one
# can't be reached, stays with the current one.
function Switch-Stick {
    $prevTarget = $script:Target
    $prevLog = $script:Log
    $prevName = $script:StickName
    if (Open-Stick ($prevTarget -replace ':5555$', '')) {
        if ($prevTarget -ne $script:Target) { Invoke-Adb @('disconnect', $prevTarget) | Out-Null }
    } else {
        $script:Target = $prevTarget
        $script:Log = $prevLog
        $script:StickName = $prevName
        Write-Host "Staying connected to the Fire Stick at $($prevTarget -replace ':5555$', '')." -ForegroundColor Yellow
    }
}

# Tells people when a newer release is out and offers to update the tool's
# files in place. The lists of removed apps and platform-tools are kept.
function Test-ForUpdate {
    if ($ToolVersion -eq 'dev') { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $latest = Invoke-RestMethod -Uri $LatestReleaseApi -TimeoutSec 5 -Headers @{ 'User-Agent' = 'Fire-Stick-Debloat' }
        $newer = [version]($latest.tag_name.TrimStart('v')) -gt [version]($ToolVersion.TrimStart('v'))
    } catch {
        return  # offline, or GitHub didn't answer: carry on with this version
    }
    if (-not $newer) { return }
    Write-Host ''
    Write-Host "A newer version ($($latest.tag_name)) is available. You have $ToolVersion." -ForegroundColor Cyan
    $asset = $latest.assets | Where-Object { $_.name -like 'Fire-Stick-Debloat-*.zip' } | Select-Object -First 1
    if (-not $asset) {
        Write-Host 'Download it from https://github.com/cmeraspro-dev/Fire-Stick-Debloat/releases/latest'
        return
    }
    if (-not (Ask 'Update now? (your lists of removed apps are kept)')) { return }
    $zip = Join-Path $env:TEMP 'fire-stick-debloat-update.zip'
    $dir = Join-Path $env:TEMP ('fire-stick-debloat-update-' + [guid]::NewGuid())
    try {
        $ProgressPreference = 'SilentlyContinue'
        Write-Host 'Downloading...'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        $new = Join-Path $dir 'Fire-Stick-Debloat'
        foreach ($f in 'FireStick.ps1', 'README.md', 'LICENSE') {
            $src = Join-Path $new $f
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $PSScriptRoot $f) -Force }
        }
        Write-Host "Updated to $($latest.tag_name). Close this window and double-click Start-Here.bat again." -ForegroundColor Green
        # Start-Here.bat is the file running right now, so it can't be replaced safely.
        $bat = Join-Path $new 'Start-Here.bat'
        if ((Test-Path -LiteralPath $bat) -and
            (Get-FileHash -LiteralPath $bat).Hash -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'Start-Here.bat')).Hash) {
            Write-Host 'This update also changed Start-Here.bat. Copy it from the zip on the releases page.' -ForegroundColor Yellow
        }
        $script:Updated = $true
    } catch {
        Write-Host "The update didn't work: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'You can download it from https://github.com/cmeraspro-dev/Fire-Stick-Debloat/releases/latest'
    } finally {
        Remove-Item -LiteralPath $zip, $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Each run is logged to logs\run-<date>.txt (the newest 10 are kept) so it can
# be attached to a bug report. Windows puts the user and computer name at the
# top of these logs; they're stripped out so the files are safe to share.
function Clear-LogHeaders {
    foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter 'run-*.txt' -ErrorAction SilentlyContinue)) {
        $lines = @(Get-Content -LiteralPath $f.FullName)
        $clean = @($lines | Where-Object { $_ -notmatch '^(Username|RunAs User|Machine|Host Application|Configuration Name|Process ID):' })
        if ($clean.Count -ne $lines.Count) { Set-Content -LiteralPath $f.FullName -Value $clean }
    }
}

function Start-RunLog {
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Clear-LogHeaders
        Get-ChildItem -LiteralPath $LogDir -Filter 'run-*.txt' | Sort-Object Name -Descending |
            Select-Object -Skip 9 | Remove-Item -Force -ErrorAction SilentlyContinue
        Start-Transcript -LiteralPath (Join-Path $LogDir ('run-{0:yyyy-MM-dd_HH-mm-ss}.txt' -f (Get-Date))) | Out-Null
    } catch {
        # A log is nice to have; never let it stop the tool.
        Write-Verbose "Couldn't start the log: $_"
    }
}

function Stop-RunLog {
    try { Stop-Transcript | Out-Null } catch { Write-Verbose "Couldn't stop the log: $_" }
    try { Clear-LogHeaders } catch { Write-Verbose "Couldn't tidy the logs: $_" }
}

function Restart-Prompt {
    Write-Host ''
    if (Ask 'Done. Restart the Fire Stick now to finish?') {
        Invoke-Adb @('-s', $script:Target, 'reboot') | Out-Null
        Write-Host 'Restarting. Give it about a minute.'
    }
}

# --- main ---
Start-RunLog
try {
    Write-Host '=============================='
    Write-Host '     Fire Stick Cleanup'
    Write-Host '=============================='
    if ($ToolVersion -ne 'dev') { Write-Host "Version $ToolVersion" -ForegroundColor DarkGray }

    Test-ForUpdate
    if ($script:Updated) { return }

    $Adb = Find-Adb
    if (-not $Adb) { $Adb = Get-PlatformTools }
    if (-not $Adb) {
        Write-Host "Couldn't find adb.exe. Put this file and Start-Here.bat inside the" -ForegroundColor Red
        Write-Host "'platform-tools' folder you downloaded (the one with adb.exe in it), then try again." -ForegroundColor Red
        Write-Host "If platform-tools is still a .zip file, right-click it and choose 'Extract All' first." -ForegroundColor Red
        return
    }
    if (-not (Open-Stick)) { return }

    while ($true) {
        Write-Host ''
        Write-Host "Connected to $($script:StickName) at $($script:Target -replace ':5555$', '')" -ForegroundColor DarkGray
        Write-Host 'What do you want to do?'
        Write-Host '  F  First time? Set everything up step by step'
        Write-Host '  1  Preview (shows what would happen, changes nothing)'
        Write-Host '  2  Clean up my Fire Stick'
        Write-Host '  3  Undo everything'
        Write-Host '  4  Choose my home screen launcher (Projectivy or any other)'
        Write-Host '  5  Install an app file from this computer (.apk)'
        Write-Host '  6  Uninstall an app I installed'
        Write-Host '  7  Get Projectivy Launcher (opens its download page, then installs it)'
        Write-Host '  8  Re-apply my cleanup (after a Fire OS update)'
        Write-Host '  S  Switch to another Fire Stick'
        Write-Host '  Q  Quit'
        switch ((Read-Host 'Type a number or letter').Trim().ToUpper()) {
            'F' { Start-FirstTime }
            '1' { Show-Preview }
            '2' { Start-Cleanup }
            '3' { Start-Undo }
            '4' { Select-HomeLauncher }
            '5' { Install-FromComputer }
            '6' { Uninstall-App }
            '7' {
                if (Get-Projectivy) {
                    Write-Host 'Next: open Projectivy once on the TV, then choose option 4 to make it your home screen.' -ForegroundColor Cyan
                }
            }
            '8' { Start-Reapply }
            'S' { Switch-Stick }
            'Q' { return }
            default { Write-Host 'Please type a number or letter from the list.' -ForegroundColor Yellow }
        }
    }
} finally {
    Stop-RunLog
}
