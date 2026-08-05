#!/usr/bin/env bash
# Purge-only stub — Linux CMD Helper / X47 Widgets are REMOVED and must never
# be reinstalled by this build. This module only strips leftover UUIDs and
# config if somehow re-enabled.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

DEAD_UUIDS=(
  "x47-cmd@x47"
  "x47-cmdfix@x47"
  "x47-deskcmd@x47"
  "x47-cmd-helper@x47"
  "x47-widgets@x47"
)

drop_enabled() {
  local uuid="$1"
  gnome-extensions disable "$uuid" 2>/dev/null || true
  python3 - "$uuid" <<'PY'
import ast, subprocess, sys
uuid = sys.argv[1]
cur = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "enabled-extensions"], text=True
).strip()
try:
    arr = ast.literal_eval(cur.replace("@as ", ""))
except Exception:
    arr = []
arr = [u for u in arr if u != uuid]
fmt = "[" + ", ".join(f"'{u}'" for u in arr) + "]"
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "enabled-extensions", fmt])
PY
}

module_widgets() {
  if ! have gsettings; then
    return 0
  fi
  log "purging retired desktop widgets / CMD Helper (never reinstall)"
  local uuid
  for uuid in "${DEAD_UUIDS[@]}"; do
    drop_enabled "$uuid"
    rm -rf "$HOME/.local/share/gnome-shell/extensions/$uuid"
  done
  rm -f "$HOME/.config/autostart/x47-ensure-cmd-helper.desktop"
  rm -rf "$HOME/.config/x47-widgets"
  # Keep them disabled so they are harder to casually re-enable
  python3 - <<'PY'
import ast, subprocess
dead = [
    "x47-cmd@x47", "x47-cmdfix@x47", "x47-deskcmd@x47",
    "x47-cmd-helper@x47", "x47-widgets@x47",
]
cur = subprocess.check_output(
    ["gsettings", "get", "org.gnome.shell", "disabled-extensions"], text=True
).strip()
try:
    arr = list(ast.literal_eval(cur.replace("@as ", "")))
except Exception:
    arr = []
for u in dead:
    if u not in arr:
        arr.append(u)
fmt = "[" + ", ".join(f"'{u}'" for u in arr) + "]"
subprocess.check_call(["gsettings", "set", "org.gnome.shell", "disabled-extensions", fmt])
PY
  ok "CMD Helper / legacy widgets purged — will not return"
}

module_widgets "$@"
