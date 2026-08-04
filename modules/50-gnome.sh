#!/usr/bin/env bash
# Apply GNOME theme, wallpaper, and default-terminal settings from the snapshot.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_gnome() {
  if ! have gsettings; then
    warn "gsettings not available — skipping GNOME module"
    return 0
  fi

  local settings="$X47_ROOT/assets/manifests/gnome-settings.txt"
  local icon_theme='Yaru-blue-dark'
  local gtk_theme='Yaru-blue-dark'
  local color_scheme='prefer-dark'
  local picture_uri_dark="'file:///usr/share/backgrounds/mendhak-Red_Acer.jpg'"
  local picture_uri="'file:///usr/share/backgrounds/mendhak-Red_Acer.jpg'"
  local terminal_exec="'$HOME/.local/bin/wezterm'"

  if [[ -f "$settings" ]]; then
    # shellcheck disable=SC1090
    while IFS='=' read -r k v; do
      case "$k" in
        icon-theme) icon_theme="${v//\'/}" ;;
        gtk-theme) gtk_theme="${v//\'/}" ;;
        color-scheme) color_scheme="${v//\'/}" ;;
        picture-uri-dark) picture_uri_dark="$v" ;;
        picture-uri) picture_uri="$v" ;;
        terminal-exec) terminal_exec="$v" ;;
      esac
    done < "$settings"
  fi

  log "applying GNOME look: theme=$gtk_theme scheme=$color_scheme"
  gsettings set org.gnome.desktop.interface icon-theme "$icon_theme" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme "$color_scheme" 2>/dev/null || true

  # Wallpaper — only if file exists
  local wall_path
  wall_path="$(echo "$picture_uri_dark" | sed "s/^'//;s/'$//;s|^file://||")"
  if [[ -f "$wall_path" ]]; then
    gsettings set org.gnome.desktop.background picture-uri-dark "$picture_uri_dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri "$picture_uri" 2>/dev/null || true
  else
    warn "wallpaper not found at $wall_path — leaving background unchanged"
  fi

  # Default terminal
  local term_bin="$HOME/.local/bin/wezterm"
  if [[ -x "$term_bin" ]]; then
    gsettings set org.gnome.desktop.default-applications.terminal exec "$term_bin" 2>/dev/null || true
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg 'start' 2>/dev/null || true
  elif [[ -n "$terminal_exec" ]]; then
    gsettings set org.gnome.desktop.default-applications.terminal exec "${terminal_exec//\'/}" 2>/dev/null || true
  fi

  mullvad_tray_start

  ok "GNOME module done"
}

# Mullvad autostarts + autoconnects; make the GUI open minimized in the tray
# instead of popping a window at login. Skipped while the GUI is running so
# the app doesn't overwrite the file on exit.
mullvad_tray_start() {
  local gui_settings="$HOME/.config/Mullvad VPN/gui_settings.json"
  [[ -f "$gui_settings" ]] || return 0
  if pgrep -f "mullvad-gu[i]" >/dev/null 2>&1; then
    warn "Mullvad GUI running — skipping startMinimized tweak (set it in the app or re-run later)"
    return 0
  fi
  if python3 - "$gui_settings" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
if data.get("startMinimized") is True:
    sys.exit(1)
data["startMinimized"] = True
json.dump(data, open(path, "w"))
PY
  then
    ok "Mullvad set to start minimized in the tray"
  fi
}

module_gnome "$@"
