#!/usr/bin/env bash
# Fire TV debloater. Disables (never deletes) Amazon ads, telemetry and apps you
# don't use. Everything it touches is logged to disabled.txt; run restore.sh to undo.
#
# Usage: ./debloat.sh <fire-stick-ip> [--dry-run] [--block-updates]
set -u

IP="${1:-}"
DRY_RUN=0
BLOCK_UPDATES=0
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --block-updates) BLOCK_UPDATES=1 ;;
  esac
done
[ -z "$IP" ] && { echo "Usage: $0 <fire-stick-ip> [--dry-run] [--block-updates]"; exit 1; }
command -v adb >/dev/null || { echo "adb not found. Install Android platform-tools first (see README)."; exit 1; }

LOG="$(dirname "$0")/disabled.txt"

# Ads, tracking and background junk. Safe to disable on every Fire OS version.
ADS_TELEMETRY=(
  com.amazon.kso                      # "Special offers": sponsored ads on the home screen
  com.amazon.device.crashmanager      # crash reports sent to Amazon
  com.amazon.dp.logger                # usage logging
  com.amazon.alexashopping            # Alexa shopping prompts
  com.amazon.ags.app                  # GameCircle
  com.amazon.wifilocker               # uploads your Wi-Fi passwords to Amazon
  com.amazon.tv.csapp                 # customer service promo app
  com.amazon.tv.legal.notices         # legal notices viewer
)

# Amazon apps. You'll be asked about each one.
AMAZON_APPS=(
  "com.amazon.amazonvideo.livingroom|Prime Video"
  "com.amazon.avod.thirdpartyclient|Prime Video (alt)"
  "com.amazon.imdb.tv.android.app|Freevee"
  "com.amazon.bueller.music|Amazon Music"
  "com.amazon.bueller.photos|Amazon Photos (also the photo screensaver)"
  "com.amazon.cloud9|Silk Browser"
)

# Updates. Only with --block-updates. Stops Amazon from undoing your setup,
# but also stops security patches.
UPDATES=(
  com.amazon.tv.forcedotaupdater.v2
  com.amazon.device.software.ota
  com.amazon.device.software.ota.override
)

# Never touched, whatever you answer: removing these can soft-brick the stick.
PROTECTED="com.amazon.tv.launcher com.amazon.venezia com.amazon.tv.settings com.amazon.tv.settings.v2 \
com.amazon.vizzini com.amazon.tcomm com.amazon.whisperplay com.amazon.device.sync com.android.systemui"

adb_sh() { adb -s "$IP:5555" shell "$@" 2>&1 | tr -d '\r'; }

echo "Connecting to $IP ... (approve the prompt on your TV if one appears)"
adb connect "$IP:5555" >/dev/null
adb -s "$IP:5555" get-state >/dev/null 2>&1 || { echo "Could not connect. Check the IP and that ADB debugging is on."; exit 1; }

INSTALLED="$(adb_sh pm list packages | sed 's/^package://')"
is_installed() { grep -qx "$1" <<<"$INSTALLED"; }
is_protected() { [[ " $PROTECTED " == *" $1 "* ]]; }

disable_pkg() {
  local pkg="$1"
  is_installed "$pkg" || return 0
  is_protected "$pkg" && { echo "  skip  $pkg (system-critical)"; return 0; }
  if [ "$DRY_RUN" = 1 ]; then echo "  would disable  $pkg"; return 0; fi
  # disable-user is the gentlest option; newer Fire OS blocks it for some
  # system apps, so fall back to a per-user uninstall (still restorable).
  if adb_sh pm disable-user --user 0 "$pkg" | grep -q "disabled"; then
    echo "  disabled  $pkg"; echo "$pkg" >> "$LOG"
  elif adb_sh pm uninstall -k --user 0 "$pkg" | grep -q "Success"; then
    echo "  removed for user  $pkg"; echo "$pkg" >> "$LOG"
  else
    echo "  failed  $pkg (Fire OS wouldn't allow it; harmless)"
  fi
}

ask() { local a; read -r -p "$1 [y/N] " a </dev/tty; [[ "$a" =~ ^[Yy] ]]; }

echo; echo "== Ads & telemetry =="
for p in "${ADS_TELEMETRY[@]}"; do disable_pkg "$p"; done

echo; echo "== Amazon apps: answer y to REMOVE =="
for entry in "${AMAZON_APPS[@]}"; do
  pkg="${entry%%|*}"; name="${entry#*|}"
  is_installed "$pkg" || continue
  ask "Remove $name?" && disable_pkg "$pkg"
done

echo; echo "== Apps you installed: answer y to REMOVE =="
for pkg in $(adb_sh pm list packages -3 | sed 's/^package://' | sort); do
  is_protected "$pkg" && continue
  ask "Remove $pkg?" && disable_pkg "$pkg"
done

if [ "$BLOCK_UPDATES" = 1 ]; then
  echo; echo "== Blocking Fire OS updates =="
  for p in "${UPDATES[@]}"; do disable_pkg "$p"; done
fi

echo; echo "Done. Restart the stick: adb -s $IP:5555 reboot"
[ "$DRY_RUN" = 0 ] && echo "Changes logged to $LOG; run ./restore.sh $IP to undo."
