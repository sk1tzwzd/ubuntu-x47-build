#!/usr/bin/env bash
# Install hardened Syncthing for secure Android ↔ PC file sync (LAN-first).
# No cloud, no KDE Connect. User-level binary + systemd --user service +
# top-bar panel chip and app icon.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

_install_syncthing_icon() {
  local src="$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-syncthing.svg"
  local dest_base="$HOME/.local/share/icons/hicolor"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$dest_base/scalable/apps"
  install -m 0644 "$src" "$dest_base/scalable/apps/x47-syncthing.svg"
  # Optional PNGs if present in the tree.
  local sz
  for sz in 16 22 24 32 48 64 128 256; do
    if [[ -f "$X47_ROOT/assets/icons/hicolor/${sz}x${sz}/apps/x47-syncthing.png" ]]; then
      mkdir -p "$dest_base/${sz}x${sz}/apps"
      install -m 0644 "$X47_ROOT/assets/icons/hicolor/${sz}x${sz}/apps/x47-syncthing.png" \
        "$dest_base/${sz}x${sz}/apps/x47-syncthing.png"
    fi
  done
  if have gtk-update-icon-cache; then
    gtk-update-icon-cache -f "$dest_base" >/dev/null 2>&1 || true
  fi
  ok "X47 Sync icon installed"
}

_install_syncthing_desktop() {
  local src="$X47_ROOT/assets/desktop/x47-syncthing.desktop"
  local dest="$HOME/.local/share/applications/x47-syncthing.desktop"
  [[ -f "$src" ]] || return 0
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  # Point Exec at the installed helper (PATH may omit ~/.local/bin).
  sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/x47-syncthing open|" "$dest"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "X47 Sync app shortcut installed"
}

_install_syncthing_panel() {
  local uuid="x47-syncthing@x47"
  local src="$X47_ROOT/assets/extensions/$uuid"
  local dest="$HOME/.local/share/gnome-shell/extensions/$uuid"
  [[ -d "$src" ]] || { warn "missing $src — panel chip skipped"; return 0; }
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -a "$src" "$dest"
  # Ensure icon is inside the extension for St.Icon FileIcon.
  mkdir -p "$dest/icons"
  if [[ -f "$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-syncthing.svg" ]]; then
    install -m 0644 "$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-syncthing.svg" \
      "$dest/icons/x47-syncthing.svg"
  fi
  gnome-extensions enable "$uuid" 2>/dev/null || true
  local cur
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" != *"'$uuid'"* ]]; then
    if [[ "$cur" == "@as []" || "$cur" == "[]" ]]; then
      gsettings set org.gnome.shell enabled-extensions "['$uuid']" 2>/dev/null || true
    else
      gsettings set org.gnome.shell enabled-extensions "${cur%]}, '$uuid']" 2>/dev/null || true
    fi
  fi
  # Drop from disabled-extensions if present.
  cur="$(gsettings get org.gnome.shell disabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" == *"'$uuid'"* ]]; then
    local cleaned
    cleaned="$(printf '%s' "$cur" | sed -E "s/'$uuid',? ?//g; s/, ]/]/g; s/\[,/[/g")"
    gsettings set org.gnome.shell disabled-extensions "$cleaned" 2>/dev/null || true
  fi
  ok "X47 Sync top-bar chip enabled (log out/in on Wayland if missing)"
}

module_syncthing() {
  bootstrap_path
  local share="$HOME/.local/share/ubuntu-x47-build"
  mkdir -p "$share/bin" "$HOME/.local/bin"

  install -m 0755 "$X47_ROOT/scripts/x47-syncthing" "$share/bin/x47-syncthing"
  ln -sfn "$share/bin/x47-syncthing" "$HOME/.local/bin/x47-syncthing"

  if [[ "${X47_SKIP_SYNCTHING:-0}" == "1" ]]; then
    warn "skipping Syncthing install (X47_SKIP_SYNCTHING=1)"
    return 0
  fi

  log "installing hardened Syncthing (LAN-first, no relays/global discovery)"
  if "$HOME/.local/bin/x47-syncthing" install; then
    ok "Syncthing ready — pair Android with: x47-syncthing id"
    ok "GUI (localhost): x47-syncthing open   creds: ~/.config/x47/syncthing-gui.cred"
  else
    warn "Syncthing install failed (network?). Retry: x47-syncthing install"
  fi

  _install_syncthing_icon
  _install_syncthing_desktop
  _install_syncthing_panel
}

module_syncthing "$@"
