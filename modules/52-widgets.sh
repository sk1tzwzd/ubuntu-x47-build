#!/usr/bin/env bash
# Desktop widgets: installs the bundled "X47 Widgets" GNOME extension
# (London + New York digital clocks, live BTC ticker, system vitals) drawn
# on the wallpaper beneath windows. User-level only (no sudo). On Wayland
# the widgets appear after a log out / log back in.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

UUID="x47-widgets@x47"
SRC="$X47_ROOT/assets/widgets/$UUID"
DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

module_widgets() {
  if [[ "${X47_SKIP_DESKTOP_FX:-0}" == "1" ]]; then
    warn "skipping widgets module (--skip-desktop-fx)"
    return 0
  fi
  if ! have gsettings; then
    warn "gsettings not available — skipping widgets"
    return 0
  fi
  [[ -d "$SRC" ]] || { warn "missing $SRC — skipping widgets"; return 0; }

  log "installing X47 Widgets extension (clocks, BTC, vitals)"
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -r "$SRC" "$DEST"

  # Enable: CLI first, then make sure the uuid is in enabled-extensions.
  gnome-extensions enable "$UUID" 2>/dev/null || true
  local cur
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" != *"'$UUID'"* ]]; then
    if [[ "$cur" == "@as []" || "$cur" == "[]" ]]; then
      gsettings set org.gnome.shell enabled-extensions "['$UUID']" 2>/dev/null || true
    else
      gsettings set org.gnome.shell enabled-extensions "${cur%]}, '$UUID']" 2>/dev/null || true
    fi
  fi

  ok "X47 Widgets installed — log out and back in to see them on the desktop"
}

module_widgets "$@"
