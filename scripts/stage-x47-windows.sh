#!/usr/bin/env bash
# Copy the X47 Windows kit onto a mounted Windows NTFS volume (C:\X47).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$ROOT/windows"
DEST="${1:-}"

if [[ -z "$DEST" ]]; then
  for cand in /run/media/"$USER"/*/Windows /media/"$USER"/*/Windows; do
    [[ -d "$cand" ]] || continue
    DEST="$(dirname "$cand")/X47"
    break
  done
fi

[[ -n "$DEST" ]] || { echo "usage: $0 /path/to/WindowsDrive/X47" >&2; exit 2; }
[[ -d "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

WP_SRC="$ROOT/assets/desktop/wallpapers"
WP_DST="$SRC/assets/wallpapers"
mkdir -p "$WP_DST"
shopt -s nullglob
for f in "$WP_SRC"/x47-circuit.png "$WP_SRC"/x47-circuit-*.png; do
  [[ -f "$f" ]] || continue
  install -m 0644 "$f" "$WP_DST/$(basename "$f")"
done

mkdir -p "$DEST"
# Avoid copying a previous BitLocker key back over the kit.
rsync -a --delete \
  --exclude 'logs/' \
  --exclude 'BitLocker-Recovery.txt' \
  "$SRC/" "$DEST/"

# Desktop shortcuts (often read-only from Linux; C:\X47 is the real entry point).
win_root="$(dirname "$DEST")"
desk="$win_root/Users/sk1tz/Desktop"
if [[ -d "$desk" ]] && [[ -w "$desk" ]]; then
  cp -f "$SRC/START-HERE.txt" "$desk/START-HERE-X47.txt" || true
  printf '%s\n' '@echo off' 'C:\X47\Install-X47Windows.bat' >"$desk/X47 Windows Privacy.bat" || true
fi

echo "staged → $DEST"
echo "boot Windows and run: C:\\X47\\Install-X47Windows.bat (as Administrator)"
