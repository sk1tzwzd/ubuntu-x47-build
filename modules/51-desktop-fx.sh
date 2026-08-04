#!/usr/bin/env bash
# Desktop looks: move the Ubuntu Dock to the bottom and add 3D window/desktop
# effects (Coverflow Alt-Tab, Desktop Cube, Burn My Windows). User-level only
# (no sudo). On Wayland the extensions load after a log out / log back in.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Extensions to install (version-matched from extensions.gnome.org)
X47_FX_UUIDS=(
  "CoverflowAltTab@palatis.blogspot.com"
  "desktop-cube@schneegans.github.com"
  "burn-my-windows@schneegans.github.com"
)

dock_to_bottom() {
  log "moving Ubuntu Dock to the bottom"
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' 2>/dev/null || warn "dock-position failed"
  gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
}

# Enable a uuid both via the CLI and by appending to the enabled-extensions
# array (belt and suspenders; the array survives until the next login).
enable_uuid() {
  local uuid="$1"
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
}

# Download + install a version-matched extension from extensions.gnome.org.
ego_install() {
  local uuid="$1" shellver info url tmp
  if gnome-extensions info "$uuid" >/dev/null 2>&1; then
    log "extension already installed: $uuid"
    enable_uuid "$uuid"
    return 0
  fi

  local v
  for shellver in "$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+')" 50.1 50 50.0; do
    [[ -n "$shellver" ]] || continue
    info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shellver}" 2>/dev/null || true)"
    [[ -n "$info" ]] || continue
    url="$(printf '%s' "$info" | jq -r '.download_url // empty' 2>/dev/null || true)"
    [[ -n "$url" ]] && break
  done

  if [[ -z "${url:-}" ]]; then
    warn "no compatible build on extensions.gnome.org for $uuid (skipping; re-run later)"
    return 1
  fi

  tmp="$(mktemp --suffix=.zip)"
  if curl -fsSL "https://extensions.gnome.org${url}" -o "$tmp" 2>/dev/null; then
    if gnome-extensions install --force "$tmp" 2>/dev/null; then
      ok "installed $uuid"
      enable_uuid "$uuid"
      rm -f "$tmp"
      return 0
    fi
  fi
  rm -f "$tmp"
  warn "failed to install $uuid"
  return 1
}

cube_workspaces() {
  # Desktop Cube needs fixed, horizontally-arranged workspaces.
  log "configuring fixed workspaces for the desktop cube"
  gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 2>/dev/null || true
}

module_desktop_fx() {
  if [[ "${X47_SKIP_DESKTOP_FX:-0}" == "1" ]]; then
    warn "skipping desktop-fx module (--skip-desktop-fx)"
    return 0
  fi
  if ! have gsettings; then
    warn "gsettings not available — skipping desktop-fx"
    return 0
  fi
  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && [[ "${XDG_SESSION_TYPE:-}" != "wayland" && "${XDG_SESSION_TYPE:-}" != "x11" ]]; then
    warn "no graphical session detected — skipping desktop-fx"
    return 0
  fi
  if ! have gnome-extensions; then
    warn "gnome-extensions CLI missing — dock only, skipping 3D effects"
    dock_to_bottom
    return 0
  fi

  dock_to_bottom

  local uuid ok_any=0
  for uuid in "${X47_FX_UUIDS[@]}"; do
    ego_install "$uuid" && ok_any=1 || true
  done

  cube_workspaces

  ok "desktop-fx module done"
  if [[ "$ok_any" == "1" ]]; then
    log "Log out and back in to load the 3D effects (Wayland can't hot-reload extensions)."
  fi
}

module_desktop_fx "$@"
