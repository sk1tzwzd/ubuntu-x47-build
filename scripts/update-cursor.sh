#!/usr/bin/env bash
# Update Cursor via the official apt repo (source of truth for .deb installs).
# The in-app "update available" popup often fires before apt has the package —
# that is a known Cursor lag, not a broken system / not caused by X47 debloat.
#
# Usage:
#   update-cursor           # apt update + only-upgrade cursor
#   update-cursor --quiet-gui  # also set Cursor update.mode=none to silence the nag
set -euo pipefail

QUIET_GUI=0
for arg in "$@"; do
  case "$arg" in
    --quiet-gui) QUIET_GUI=1 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
done

need_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  elif command -v sudo >/dev/null 2>&1; then
    sudo -v
  else
    echo "sudo required" >&2
    exit 1
  fi
}

run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

need_sudo

echo "[x47] refreshing apt and upgrading cursor…"
run apt-get update -qq
BEFORE="$(dpkg-query -W -f='${Version}' cursor 2>/dev/null || echo none)"
set +e
run apt-get install --only-upgrade -y cursor
RC=$?
set -e
AFTER="$(dpkg-query -W -f='${Version}' cursor 2>/dev/null || echo none)"

if [[ "$RC" -ne 0 ]]; then
  echo "[fail] apt upgrade cursor failed (exit $RC)" >&2
  exit "$RC"
fi

if [[ "$BEFORE" == "$AFTER" ]]; then
  cat <<EOF
[ok] cursor is already the newest apt package: $AFTER

The GUI update popup uses a separate feed that often announces a build
before it lands in https://downloads.cursor.com/aptrepo. Deb installs
cannot self-update (only AppImage can). This is a known Cursor lag —
not caused by X47 debloat. Wait and re-run later, or silence the nag:
  update-cursor --quiet-gui
EOF
else
  echo "[ok] cursor upgraded: $BEFORE -> $AFTER"
fi

if [[ "$QUIET_GUI" == "1" ]]; then
  SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json"
  mkdir -p "$(dirname "$SETTINGS")"
  if [[ ! -f "$SETTINGS" ]]; then
    printf '{\n  "update.mode": "none"\n}\n' > "$SETTINGS"
  else
    python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
data["update.mode"] = "none"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"[ok] set update.mode=none in {path}")
PY
  fi
  echo "[ok] Cursor update nags silenced (update.mode=none). Undo: remove that key from settings.json"
fi
