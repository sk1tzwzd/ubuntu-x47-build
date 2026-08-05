#!/usr/bin/env bash
# Desktop looks: bottom dock, 3D window/desktop effects (Coverflow Alt-Tab,
# Desktop Cube, Burn My Windows "Matrix"), Blur My Shell, wobbly windows, and a
# custom X47 wallpaper. User-level only (no sudo). On Wayland the extensions
# load after a log out / log back in.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

AM_DESKTOP="$X47_ROOT/assets/desktop"

# Extensions to install (version-matched from extensions.gnome.org)
X47_FX_UUIDS=(
  "CoverflowAltTab@palatis.blogspot.com"
  "desktop-cube@schneegans.github.com"
  "burn-my-windows@schneegans.github.com"
  "blur-my-shell@aunetx"
  "compiz-windows-effect@hermes83.github.com"
  "tilingshell@ferrarodomenico.com"
)

dock_to_bottom() {
  log "moving Ubuntu Dock to the bottom (always visible; hides in fullscreen)"
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' 2>/dev/null || warn "dock-position failed"
  gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false 2>/dev/null || true
  # Floating dock: windows maximize to the FULL screen (no reserved strip).
  # The dock stays visible whenever nothing overlaps it, dodges out of the way
  # of overlapping windows, and slides back over them when the mouse hits the
  # bottom edge. (An always-on-top overlay dock is not a dash-to-dock mode.)
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode 'ALL_WINDOWS' 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock autohide true 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock require-pressure-to-show false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock animation-time 0.15 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock autohide-in-fullscreen true 2>/dev/null || true
  # Click a pinned app: cycle through its windows, jumping workspaces to reach them.
  gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'cycle-windows' 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces false 2>/dev/null || true
  # F11 toggles window fullscreen system-wide (apps that handle F11 themselves still work).
  gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']" 2>/dev/null || true
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
  # Check the install dir too: on Wayland `gnome-extensions info` can't see
  # extensions installed since the last login.
  if gnome-extensions info "$uuid" >/dev/null 2>&1 \
     || [[ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ]]; then
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

bmw_fx_profile() {
  # Burn My Windows v48 reads per-profile keyfiles. Ship two: TV Glitch for
  # window open, Broken Glass for window close. Drop stale x47 profiles and
  # empty auto-created ones.
  local src_open="$AM_DESKTOP/burn-my-windows-x47-open.conf"
  local src_close="$AM_DESKTOP/burn-my-windows-x47-close.conf"
  local dir="$HOME/.config/burn-my-windows/profiles"
  [[ -f "$src_open" && -f "$src_close" ]] || { warn "missing BMW profile assets — skipping"; return 0; }
  log "installing Burn My Windows profiles (open: TV Glitch, close: Broken Glass)"
  mkdir -p "$dir"
  rm -f "$dir/x47.conf"
  local f
  for f in "$dir"/*.conf; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == x47-*.conf ]] && continue
    # Only remove profiles that don't enable any effect (the empty default).
    if ! grep -qE '^[a-z0-9-]+-enable-effect=true' "$f" 2>/dev/null; then
      rm -f "$f"
    fi
  done
  install -m 0644 "$src_open" "$dir/x47-open.conf"
  install -m 0644 "$src_close" "$dir/x47-close.conf"
  ok "BMW profiles -> $dir/x47-{open,close}.conf"
}

coverflow_tune() {
  # The extension ships its own compiled schema, so gsettings needs
  # --schemadir to find org.gnome.shell.extensions.coverflowalttab.
  local sdir="$HOME/.local/share/gnome-shell/extensions/CoverflowAltTab@palatis.blogspot.com/schemas"
  local edir="$HOME/.local/share/gnome-shell/extensions/CoverflowAltTab@palatis.blogspot.com"
  [[ -f "$sdir/gschemas.compiled" ]] || { warn "Coverflow schema not found — skipping tuning"; return 0; }
  log "tuning Coverflow Alt-Tab (3D switcher bound to window/app switching)"
  gsettings --schemadir "$sdir" set org.gnome.shell.extensions.coverflowalttab switcher-style 'Coverflow' 2>/dev/null || true
  gsettings --schemadir "$sdir" set org.gnome.shell.extensions.coverflowalttab bind-to-switch-windows true 2>/dev/null || true
  gsettings --schemadir "$sdir" set org.gnome.shell.extensions.coverflowalttab bind-to-switch-applications true 2>/dev/null || true
  gsettings --schemadir "$sdir" set org.gnome.shell.extensions.coverflowalttab hide-panel true 2>/dev/null || true
  # Windows-like: Alt+Tab one step past the last window → Desktop.
  if [[ -d "$edir" && -f "$AM_DESKTOP/patch-coverflow-alttab-desktop.py" ]]; then
    log "patching Coverflow Alt-Tab so you can Alt+Tab to the desktop"
    python3 "$AM_DESKTOP/patch-coverflow-alttab-desktop.py" "$edir" \
      && ok "Alt+Tab past last window selects Desktop (log out/in once on Wayland)" \
      || warn "Coverflow desktop patch failed (extension API may have changed)"
  fi
}

# Append the hover-only window-controls CSS to a gtk.css (idempotent via
# marker block; replaces the block if the asset changed).
install_hover_css_into() {
  local css_dir="$1" src="$2"
  local css="$css_dir/gtk.css"
  local begin="/* --- x47 hover window controls --- */"
  local end="/* --- end x47 hover window controls --- */"
  mkdir -p "$css_dir"
  if [[ -f "$css" ]] && grep -qF "$begin" "$css"; then
    # Drop the old managed block before re-adding it.
    local tmp
    tmp="$(mktemp)"
    awk -v b="$begin" -v e="$end" '
      index($0, b) { skip = 1 }
      !skip { print }
      index($0, e) { skip = 0 }
    ' "$css" > "$tmp"
    mv "$tmp" "$css"
  fi
  {
    printf '%s\n' "$begin"
    cat "$src"
    printf '%s\n' "$end"
  } >> "$css"
}

hover_window_controls() {
  local src="$AM_DESKTOP/gtk-hover-controls.css"
  [[ -f "$src" ]] || { warn "missing $src — skipping hover window controls"; return 0; }
  log "hiding window controls until hover (GTK3 + GTK4 css)"
  install_hover_css_into "$HOME/.config/gtk-3.0" "$src"
  install_hover_css_into "$HOME/.config/gtk-4.0" "$src"
  # Snap apps (e.g. Firefox) read gtk.css from their own sandboxed config dir.
  # Prefer the `current` symlink; also refresh any revision dirs that already
  # have our managed block (older installs wrote there directly).
  local snap_conf
  for snap_conf in "$HOME"/snap/*/current/.config "$HOME"/snap/*/*/.config; do
    [[ -d "$snap_conf" ]] || continue
    [[ "$snap_conf" == */common/.config ]] && continue
    install_hover_css_into "$snap_conf/gtk-3.0" "$src"
    install_hover_css_into "$snap_conf/gtk-4.0" "$src"
  done
  ok "hover-only window controls installed (restart apps to pick it up)"
}

# Replace a marked block in a text file (or append if missing).
replace_marked_block() {
  local dest="$1" begin="$2" end="$3" src="$4"
  mkdir -p "$(dirname "$dest")"
  local tmp
  tmp="$(mktemp)"
  if [[ -f "$dest" ]] && grep -qF "$begin" "$dest"; then
    awk -v b="$begin" -v e="$end" '
      index($0, b) { skip = 1 }
      !skip { print }
      index($0, e) { skip = 0 }
    ' "$dest" > "$tmp"
  elif [[ -f "$dest" ]]; then
    cat "$dest" > "$tmp"
  else
    : > "$tmp"
  fi
  {
    cat "$tmp"
    # Ensure a trailing newline before the block when appending to non-empty.
    [[ -s "$tmp" ]] && [[ "$(tail -c1 "$tmp" | wc -l)" -eq 0 ]] && printf '\n'
    cat "$src"
  } > "$dest"
  rm -f "$tmp"
}

# Firefox renders its own min/max/close buttons, so it needs a userChrome.css
# (plus the legacy-stylesheets pref) instead of GTK css.
firefox_hover_buttons() {
  local src="$AM_DESKTOP/firefox-userChrome.css"
  [[ -f "$src" ]] || { warn "missing $src — skipping Firefox hover buttons"; return 0; }
  local begin="/* --- x47 hover window buttons (Firefox) --- */"
  local end="/* --- end x47 hover window buttons --- */"
  local prof found=0
  for prof in "$HOME"/snap/firefox/common/.mozilla/firefox/*.default* \
              "$HOME"/.mozilla/firefox/*.default*; do
    [[ -d "$prof" ]] || continue
    found=1
    mkdir -p "$prof/chrome"
    local dest="$prof/chrome/userChrome.css"
    replace_marked_block "$dest" "$begin" "$end" "$src"
    if ! grep -qF "toolkit.legacyUserProfileCustomizations.stylesheets" "$prof/user.js" 2>/dev/null; then
      echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$prof/user.js"
    fi
  done
  if [[ "$found" == "1" ]]; then
    ok "Firefox hover-only window buttons installed (restart Firefox)"
  else
    warn "no Firefox profile found — hover buttons will apply after Firefox first run + rerun"
  fi
}

# Super+Shift+S screenshot — gated by ~/.config/x47/settings.conf (x47-settings).
screenshot_keybindings() {
  # shellcheck disable=SC1091
  . "$X47_ROOT/lib/settings.sh"
  x47_settings_ensure
  if [[ "$(x47_settings_get win_screenshot 1)" != "1" ]]; then
    log "win_screenshot disabled in X47 Settings — Print only"
    gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print']" 2>/dev/null || true
    return 0
  fi
  log "binding Super+Shift+S to the screenshot UI (Print kept; toggle via x47-settings)"
  gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print', '<Super><Shift>s']" 2>/dev/null \
    || warn "could not set show-screenshot-ui keybinding"
  ok "screenshot: Print or Super+Shift+S"
}

set_wallpaper() {
  # Teal (ws1) + green (ws2) + red (ws3) + purple (ws4) ASCII duster walls.
  local dest_dir="$HOME/.local/share/backgrounds"
  local src_dir="$AM_DESKTOP/wallpapers"
  local f dest
  mkdir -p "$dest_dir"
  log "installing X47 workspace wallpapers (teal/green/red/purple)"
  for f in x47-circuit.png x47-circuit-pink.png x47-circuit-blue.png x47-circuit-green.png \
           x47-circuit-orange.png x47-circuit-purple.png x47-circuit-yellow.png x47-circuit-red.png; do
    [[ -f "$src_dir/$f" ]] || { warn "missing $src_dir/$f"; continue; }
    install -m 0644 "$src_dir/$f" "$dest_dir/$f"
  done
  dest="$dest_dir/x47-circuit.png"
  if [[ -f "$dest" ]]; then
    gsettings set org.gnome.desktop.background picture-uri "file://$dest" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$dest" 2>/dev/null || true
    gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
    ok "wallpapers -> $dest_dir (active: teal / workspace 1)"
  fi
  install_ws_walls_extension
}

# Install a bundled extension from assets/extensions/<uuid> and enable it.
install_local_extension() {
  local uuid="$1" label="${2:-$1}"
  local src="$X47_ROOT/assets/extensions/$uuid"
  local dest="$HOME/.local/share/gnome-shell/extensions/$uuid"
  [[ -d "$src" ]] || { warn "missing $src — $label skipped"; return 1; }
  log "installing $label ($uuid)"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -a "$src" "$dest"
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
  ok "$label enabled (log out/in on Wayland)"
}

install_ws_walls_extension() {
  install_local_extension "x47-ws-walls@x47" "workspace wallpaper switcher"
}

# One click on a top banner focuses/opens the notifying app.
# Windows 11-style snap layouts: drag a window to see zones (no modifier),
# edges/corners tile halves and quarters, suggestions fill the rest.
tiling_shell_tune() {
  local sdir="$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com/schemas"
  [[ -d "$sdir" ]] || { warn "tiling shell not installed; skipping tune"; return 0; }
  # Ubuntu's built-in tiler fights Tiling Shell.
  gnome-extensions disable tiling-assistant@ubuntu.com 2>/dev/null || true
  local s="org.gnome.shell.extensions.tilingshell"
  gsettings --schemadir "$sdir" set $s tiling-system-activation-key "['-1']" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-snap-assist true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-tiling-system true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-tiling-system-windows-suggestions true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-snap-assistant-windows-suggestions true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-screen-edges-windows-suggestions true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s active-screen-edges true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s top-edge-maximize true 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s quarter-tiling-threshold 40 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s inner-gaps 6 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s outer-gaps 4 2>/dev/null || true
  # Custom layouts: main+terminal strip (default), code+side stack, halves, 2x2 grid.
  local layouts='[{"id":"x47-term","tiles":[{"x":0,"y":0,"width":1,"height":0.72,"groups":[1]},{"x":0,"y":0.72,"width":1,"height":0.28,"groups":[1]}]},{"id":"x47-code","tiles":[{"x":0,"y":0,"width":0.62,"height":1,"groups":[1]},{"x":0.62,"y":0,"width":0.38,"height":0.55,"groups":[1,2]},{"x":0.62,"y":0.55,"width":0.38,"height":0.45,"groups":[1,2]}]},{"id":"x47-halves","tiles":[{"x":0,"y":0,"width":0.5,"height":1,"groups":[1]},{"x":0.5,"y":0,"width":0.5,"height":1,"groups":[1]}]},{"id":"x47-grid","tiles":[{"x":0,"y":0,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0.5,"y":0,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0,"y":0.5,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0.5,"y":0.5,"width":0.5,"height":0.5,"groups":[1,2]}]}]'
  gsettings --schemadir "$sdir" set $s layouts-json "$layouts" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s selected-layouts "[['x47-term','x47-term','x47-term','x47-term']]" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s snap-assist-sync-layout true 2>/dev/null || true
  # Hold CTRL while dragging to bypass tiling (free placement / overlap).
  gsettings --schemadir "$sdir" set $s tiling-system-deactivation-key "['0']" 2>/dev/null || true
}

notification_click_activate() {
  gsettings set org.gnome.desktop.notifications show-banners true 2>/dev/null || true
  install_local_extension "x47-notif-activate@x47" "notification click → open app"
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
    warn "gnome-extensions CLI missing — dock + wallpaper only, skipping 3D effects"
    dock_to_bottom
    set_wallpaper
    return 0
  fi

  dock_to_bottom

  local uuid ok_any=0
  for uuid in "${X47_FX_UUIDS[@]}"; do
    ego_install "$uuid" && ok_any=1 || true
  done

  cube_workspaces
  bmw_fx_profile
  coverflow_tune
  tiling_shell_tune
  hover_window_controls
  firefox_hover_buttons
  screenshot_keybindings
  notification_click_activate
  set_wallpaper

  ok "desktop-fx module done"
  if [[ "$ok_any" == "1" ]]; then
    log "Log out and back in to load the 3D effects (Wayland can't hot-reload extensions)."
  fi
}

module_desktop_fx "$@"
