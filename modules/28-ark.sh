#!/usr/bin/env bash
# Install X47 Ark — Windows user-file backup + Ubuntu disk reclaim.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

_priv() {
  if [[ "$(id -u)" -eq 0 ]]; then
    env "$@"
    return
  fi
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && have pkexec; then
    pkexec env "$@"
    return
  fi
  run_sudo "$@"
}

_install_ark_helper() {
  local dest_dir="$HOME/.local/share/ubuntu-x47-build/bin"
  mkdir -p "$dest_dir" "$HOME/.local/bin"
  local name src
  for name in x47-ark x47-ark-gui; do
    src="$X47_ROOT/scripts/$name"
    [[ -f "$src" ]] || die "missing $src"
    install -m 0755 "$src" "$dest_dir/$name"
    ln -sfn "$dest_dir/$name" "$HOME/.local/bin/$name"
    ok "$name → $HOME/.local/bin/$name"
  done
}

_install_ark_guide() {
  local src="$X47_ROOT/assets/docs/x47-ark-guide.html"
  local dest="$HOME/.local/share/ubuntu-x47-build/docs/x47-ark-guide.html"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  ok "Ark guide → $dest"
}

_install_ark_icon() {
  local dest_base="$HOME/.local/share/icons/hicolor"
  local svg="$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-ark.svg"
  [[ -f "$svg" ]] || { warn "missing $svg"; return 0; }
  mkdir -p "$dest_base/scalable/apps"
  install -m 0644 "$svg" "$dest_base/scalable/apps/x47-ark.svg"
  local sz
  for sz in 128 256; do
    local png="$X47_ROOT/assets/icons/hicolor/${sz}x${sz}/apps/x47-ark.png"
    if [[ -f "$png" ]]; then
      mkdir -p "$dest_base/${sz}x${sz}/apps"
      install -m 0644 "$png" "$dest_base/${sz}x${sz}/apps/x47-ark.png"
    fi
  done
  if have gtk-update-icon-cache; then
    gtk-update-icon-cache -f -t "$dest_base" >/dev/null 2>&1 || true
  fi
  ok "X47 Ark icon installed"
}

_install_ark_desktop() {
  local src="$X47_ROOT/assets/desktop/x47-ark.desktop"
  local dest="$HOME/.local/share/applications/x47-ark.desktop"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/x47-ark gui|" "$dest"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "desktop entry → $dest"
}

_add_ark_to_utilities() {
  have gsettings || return 0
  python3 - <<'PY'
import ast, subprocess, sys
schema = "org.gnome.desktop.app-folders.folder"
path = "/org/gnome/desktop/app-folders/folders/Utilities/"
key = f"{schema}:{path}"
try:
    raw = subprocess.check_output(["gsettings", "get", key, "apps"], text=True).strip()
except subprocess.CalledProcessError:
    sys.exit(0)
apps = ast.literal_eval(raw.replace("@as ", "") or "[]")
item = "x47-ark.desktop"
if item in apps:
    sys.exit(0)
# Sit with the other X47 utilities; keep Papers first when present.
anchor = "x47-pdf.desktop"
if anchor in apps:
    apps.insert(apps.index(anchor) + 1, item)
else:
    apps.append(item)
formatted = "[" + ", ".join(f"'{a}'" for a in apps) + "]"
subprocess.check_call(["gsettings", "set", key, "apps", formatted])
print("added")
PY
  ok "X47 Ark added to Utilities"
}

_pin_ark_desktop() {
  local desk="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  mkdir -p "$desk"
  local dest="$desk/X47 Ark.desktop"
  [[ -f "$HOME/.local/share/applications/x47-ark.desktop" ]] || return 0
  install -m 0755 "$HOME/.local/share/applications/x47-ark.desktop" "$dest"
  if have gio; then
    gio set "$dest" metadata::trusted true 2>/dev/null || true
  fi
  ok "desktop shortcut → $dest"
}

_install_ark_packages() {
  if [[ "${X47_SKIP_APT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "skipping Ark package install (no apt)"
    return 0
  fi
  if ! need_sudo; then
    warn "Ark packages need sudo — helper/guide still installed"
    return 0
  fi
  log "installing ntfs-3g rsync parted e2fsprogs zenity + GTK"
  _priv DEBIAN_FRONTEND=noninteractive apt-get install -y \
    --no-install-recommends \
    ntfs-3g rsync parted e2fsprogs zenity gdisk dislocker fuse3 \
    python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 gir1.2-vte-3.91 \
    || warn "Ark package install had errors"
}

module_ark() {
  if [[ "${X47_SKIP_ARK:-0}" == "1" ]]; then
    warn "skipping X47 Ark (X47_SKIP_ARK=1)"
    return 0
  fi
  log "installing X47 Ark"
  _install_ark_packages
  _install_ark_helper
  _install_ark_guide
  _install_ark_icon
  _install_ark_desktop
  _add_ark_to_utilities
  _pin_ark_desktop
}

module_ark
