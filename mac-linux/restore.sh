#!/usr/bin/env bash
# Re-enables everything debloat.sh disabled (reads disabled.txt).
# Usage: ./restore.sh <fire-stick-ip> [package ...]   (no packages = restore all)
set -u
IP="${1:-}"; [ -z "$IP" ] && { echo "Usage: $0 <fire-stick-ip> [package ...]"; exit 1; }
LOG="$(dirname "$0")/disabled.txt"
adb connect "$IP:5555" >/dev/null

if [ $# -gt 1 ]; then PKGS=("${@:2}"); else PKGS=(); while IFS= read -r l; do [ -n "$l" ] && PKGS+=("$l"); done < <(sort -u "$LOG" 2>/dev/null); fi
[ ${#PKGS[@]} -eq 0 ] && { echo "Nothing to restore."; exit 0; }

for pkg in "${PKGS[@]}"; do
  adb -s "$IP:5555" shell cmd package install-existing --user 0 "$pkg" >/dev/null 2>&1
  adb -s "$IP:5555" shell pm enable --user 0 "$pkg" >/dev/null 2>&1
  echo "  restored  $pkg"
  [ -f "$LOG" ] && sed -i.bak "/^${pkg//./\\.}\$/d" "$LOG"
done
rm -f "$LOG.bak"
echo "Done. Reboot: adb -s $IP:5555 reboot"
