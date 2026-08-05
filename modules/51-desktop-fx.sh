#!/usr/bin/env bash
# Desktop looks (lean): Super/Activities launcher (no dock), CTRL-only tiling,
# X47 wallpapers, notification click-to-focus. No cube / blur / wobbly /
# Coverflow / Burn My Windows / per-desktop wall switcher. Animations off.
# User-level only.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

AM_DESKTOP="$X47_ROOT/assets/desktop"

# Heavy FX — never installed; disabled if leftovers remain from older builds.
X47_HEAVY_FX_UUIDS=(
  "CoverflowAltTab@palatis.blogspot.com"
  "desktop-cube@schneegans.github.com"
  "burn-my-windows@schneegans.github.com"
  "blur-my-shell@aunetx"
  "compiz-windows-effect@hermes83.github.com"
  "x47-ws-walls@x47"
)

# Lean extensions only (version-matched from extensions.gnome.org / bundled).
X47_FX_UUIDS=(
  "tilingshell@ferrarodomenico.com"
)

# Super / Activities replaces the dock (lightest launcher).
hide_dock() {
  log "disabling Ubuntu Dock — use Super for Activities / app grid"
  local uuid cur
  for uuid in ubuntu-dock@ubuntu.com dash-to-dock@micxgx.gmail.com; do
    gnome-extensions disable "$uuid" 2>/dev/null || true
  done
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  for uuid in ubuntu-dock@ubuntu.com dash-to-dock@micxgx.gmail.com; do
    cur="$(printf '%s' "$cur" | sed -E "s/'$uuid',? ?//g; s/, ]/]/g; s/\[,/[/g")"
  done
  gsettings set org.gnome.shell enabled-extensions "$cur" 2>/dev/null || true
  # F11 toggles window fullscreen system-wide.
  gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']" 2>/dev/null || true
  ok "dock off — Super opens Activities; Super+1…9 launches favorites"
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
  # Fixed floor of 4 desktops (teal/pink/carbon/green). Dynamic mode culls
  # empty faces so carbon/green vanish — keep static and let x47-ws-walls'
  # "+" button raise num-workspaces when you want more.
  log "configuring workspaces for the desktop cube / swap bar (4 + add)"
  gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 2>/dev/null || true
  local cdir="$HOME/.local/share/gnome-shell/extensions/desktop-cube@schneegans.github.com/schemas"
  if [[ -d "$cdir" ]]; then
    local c="org.gnome.shell.extensions.desktop-cube"
    # Snappier cube: lower edge pressure, tighter gap, brighter neighbour faces.
    gsettings --schemadir "$cdir" set $c edge-switch-pressure 120 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c mouse-rotation-speed 2.5 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c workpace-separation 60 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c horizontal-stretch 70 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c inactive-workpace-opacity 220 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c do-explode true 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c enable-desktop-dragging true 2>/dev/null || true
    gsettings --schemadir "$cdir" set $c enable-desktop-edge-switch true 2>/dev/null || true
  fi
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

# Strip a marked CSS block from gtk.css (used to remove the old hover-only
# window-controls hack that left invisible X/max buttons stealing clicks).
strip_css_block() {
  local css="$1" begin="$2" end="$3"
  [[ -f "$css" ]] || return 0
  grep -qF "$begin" "$css" 2>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    index($0, b) { skip = 1; next }
    index($0, e) { skip = 0; next }
    !skip { print }
  ' "$css" > "$tmp"
  mv "$tmp" "$css"
}

hover_window_controls() {
  # Removed: opacity:0 min/max/close buttons still stole clicks (GTK ignores
  # pointer-events). Always show normal window controls.
  log "removing hover-only window controls (always-visible buttons)"
  local begin="/* --- x47 hover window controls --- */"
  local end="/* --- end x47 hover window controls --- */"
  local css
  while IFS= read -r css; do
    strip_css_block "$css" "$begin" "$end"
  done < <(find "$HOME/.config" "$HOME/snap" -type f \( -path '*/gtk-3.0/gtk.css' -o -path '*/gtk-4.0/gtk.css' \) 2>/dev/null)
  ok "hover-only window controls removed (restart apps to pick it up)"
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

# Strip the old Firefox hover-only min/max/close userChrome block.
firefox_hover_buttons() {
  local begin="/* --- x47 hover window buttons (Firefox) --- */"
  local end="/* --- end x47 hover window buttons --- */"
  local prof found=0
  for prof in "$HOME"/snap/firefox/common/.mozilla/firefox/*.default* \
              "$HOME"/.mozilla/firefox/*.default*; do
    [[ -d "$prof" ]] || continue
    found=1
    strip_css_block "$prof/chrome/userChrome.css" "$begin" "$end"
  done
  if [[ "$found" == "1" ]]; then
    ok "Firefox hover-only window buttons removed (restart Firefox)"
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
  # Teal / pink / carbon / green presets + random extras for added workspaces.
  local dest_dir="$HOME/.local/share/backgrounds"
  local src_dir="$AM_DESKTOP/wallpapers"
  local f dest
  mkdir -p "$dest_dir"
  log "installing X47 workspace wallpapers (4 presets + random extras)"
  for f in x47-circuit.png x47-circuit-pink.png x47-circuit-carbon.png x47-circuit-green.png \
           x47-circuit-orange.png x47-circuit-purple.png x47-circuit-yellow.png x47-circuit-red.png \
           x47-circuit-cyan.png x47-circuit-lime.png x47-circuit-magenta.png x47-circuit-slate.png; do
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
}

install_power_desktop_sync() {
  # Autostart watcher: GNOME Power Mode Performance ↔ High Performance desktop.
  mkdir -p "$HOME/.config/autostart"
  if [[ -f "$AM_DESKTOP/x47-power-desktop-sync.desktop" ]]; then
    install -m 0644 "$AM_DESKTOP/x47-power-desktop-sync.desktop" \
      "$HOME/.config/autostart/x47-power-desktop-sync.desktop"
    # Point Exec at the installed binary (PATH may not include ~/.local/bin in autostart).
    sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/x47-power-desktop-sync|" \
      "$HOME/.config/autostart/x47-power-desktop-sync.desktop"
    ok "Power desktop sync autostart installed"
  fi
}

apply_desktop_mode_helper() {
  local mode="$1"
  if [[ -x "$HOME/.local/bin/x47-desktop-mode" ]]; then
    "$HOME/.local/bin/x47-desktop-mode" "$mode" || true
  elif [[ -x "$X47_ROOT/scripts/x47-desktop-mode" ]]; then
    "$X47_ROOT/scripts/x47-desktop-mode" "$mode" || true
  else
    warn "x47-desktop-mode not installed yet — lean/visual apply skipped"
  fi
}

show_apps_duster_icon() {
  # Original Ubuntu Show Apps mark in lime green via a thin theme that inherits
  # Yaru-blue-dark for everything else.
  local src="$X47_ROOT/assets/icons/show-apps-duster"
  local theme_dir="$HOME/.local/share/icons/X47"
  local size f
  [[ -d "$src" ]] || { warn "missing $src — show-apps duster skipped"; return 0; }
  log "installing lime Ubuntu mark as Show Apps icon"
  rm -rf "$theme_dir"
  mkdir -p "$theme_dir/scalable/actions"
  cat > "$theme_dir/index.theme" <<'EOF'
[Icon Theme]
Name=X47
Comment=Yaru-blue-dark with X47 Show Apps duster
Inherits=Yaru-blue-dark,Yaru,hicolor
Directories=scalable/actions,16x16/actions,22x22/actions,24x24/actions,32x32/actions,48x48/actions,64x64/actions,128x128/actions,256x256/actions

[scalable/actions]
Context=Actions
Size=16
MinSize=8
MaxSize=512
Type=Scalable

[16x16/actions]
Context=Actions
Size=16
Type=Fixed

[22x22/actions]
Context=Actions
Size=22
Type=Fixed

[24x24/actions]
Context=Actions
Size=24
Type=Fixed

[32x32/actions]
Context=Actions
Size=32
Type=Fixed

[48x48/actions]
Context=Actions
Size=48
Type=Fixed

[64x64/actions]
Context=Actions
Size=64
Type=Fixed

[128x128/actions]
Context=Actions
Size=128
Type=Fixed

[256x256/actions]
Context=Actions
Size=256
Type=Fixed
EOF
  for f in view-app-grid-ubuntu-symbolic.svg view-app-grid-symbolic.svg view-app-grid-ubiquity-symbolic.svg; do
    [[ -f "$src/$f" ]] && install -m 0644 "$src/$f" "$theme_dir/scalable/actions/$f"
  done
  for size in 16 22 24 32 48 64 128 256; do
    mkdir -p "$theme_dir/${size}x${size}/actions"
    f="$src/view-app-grid-${size}.png"
    [[ -f "$f" ]] || continue
    install -m 0644 "$f" "$theme_dir/${size}x${size}/actions/view-app-grid.png"
    install -m 0644 "$f" "$theme_dir/${size}x${size}/actions/view-app-grid-symbolic.png"
    install -m 0644 "$f" "$theme_dir/${size}x${size}/actions/view-app-grid-ubuntu-symbolic.png"
  done
  gtk-update-icon-cache -f "$theme_dir" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface icon-theme 'X47' 2>/dev/null || true
  ok "Show Apps icon -> lime Ubuntu mark (theme X47)"
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
# Free drag by default; hold CTRL while dragging to show tile zones.
# New windows open floating (never auto-tile on spawn).
tiling_shell_tune() {
  local sdir="$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com/schemas"
  [[ -d "$sdir" ]] || { warn "tiling shell not installed; skipping tune"; return 0; }
  # Ubuntu's built-in tiler fights Tiling Shell.
  gnome-extensions disable tiling-assistant@ubuntu.com 2>/dev/null || true
  local root="${sdir%/schemas}"
  # GNOME 50: Meta.Cursor is gone — patch the layout editor or it crashes and
  # leaves its blue overlay stuck on screen.
  if [[ -f "$AM_DESKTOP/patch-tilingshell-cursor.py" ]]; then
    python3 "$AM_DESKTOP/patch-tilingshell-cursor.py" "$root" \
      || warn "tiling shell cursor patch failed"
  fi
  # Strip any old retile-on-layout-click hook (grid is drag-only).
  if [[ -f "$AM_DESKTOP/patch-tilingshell-apply-layout.py" ]]; then
    python3 "$AM_DESKTOP/patch-tilingshell-apply-layout.py" "$root" \
      || warn "tiling shell apply-layout cleanup failed"
  fi
  # Null compositor actor mid-snap — otherwise overlays get stuck.
  if [[ -f "$AM_DESKTOP/patch-tilingshell-null-actor.py" ]]; then
    python3 "$AM_DESKTOP/patch-tilingshell-null-actor.py" "$root" \
      || warn "tiling shell null-actor patch failed"
  fi
  # Dispose races + force-hide overlays + skip anim prep that fights wobbly.
  if [[ -f "$AM_DESKTOP/patch-tilingshell-stability.py" ]]; then
    python3 "$AM_DESKTOP/patch-tilingshell-stability.py" "$root" \
      || warn "tiling shell stability patch failed"
  fi
  # Cube / workspace-switch mid-drag leaves the previous desktop's blue tile
  # preview stuck — close every workspace layout + skip retile after a hop.
  if [[ -f "$AM_DESKTOP/patch-tilingshell-workspace-drag.py" ]]; then
    python3 "$AM_DESKTOP/patch-tilingshell-workspace-drag.py" "$root" \
      || warn "tiling shell workspace-drag patch failed"
  fi
  local s="org.gnome.shell.extensions.tilingshell"
  # Hold CTRL while dragging to enter tile mode (0 = CTRL). Free drag otherwise.
  gsettings --schemadir "$sdir" set $s tiling-system-activation-key "['0']" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s tiling-system-deactivation-key "['-1']" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-tiling-system true 2>/dev/null || true
  # Snap-assist / edge snap fire without CTRL — keep off so plain drags stay free.
  gsettings --schemadir "$sdir" set $s enable-snap-assist false 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s active-screen-edges false 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s top-edge-maximize false 2>/dev/null || true
  # Window-suggestion popups leave stuck overlays on GNOME 50 — keep off.
  gsettings --schemadir "$sdir" set $s enable-tiling-system-windows-suggestions false 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-snap-assistant-windows-suggestions false 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s enable-screen-edges-windows-suggestions false 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s quarter-tiling-threshold 40 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s inner-gaps 6 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s outer-gaps 4 2>/dev/null || true
  # Never auto-place new windows into tiles (dock / launcher / Alt+F2).
  gsettings --schemadir "$sdir" set $s enable-autotiling false 2>/dev/null || true
  # Custom layouts: main+terminal strip (default), code+side stack, halves, 2x2 grid.
  # selected-layouts shape is [workspace][monitor], not the other way around.
  local layouts='[{"id":"x47-term","tiles":[{"x":0,"y":0,"width":1,"height":0.72,"groups":[1]},{"x":0,"y":0.72,"width":1,"height":0.28,"groups":[1]}]},{"id":"x47-code","tiles":[{"x":0,"y":0,"width":0.62,"height":1,"groups":[1]},{"x":0.62,"y":0,"width":0.38,"height":0.55,"groups":[1,2]},{"x":0.62,"y":0.55,"width":0.38,"height":0.45,"groups":[1,2]}]},{"id":"x47-halves","tiles":[{"x":0,"y":0,"width":0.5,"height":1,"groups":[1]},{"x":0.5,"y":0,"width":0.5,"height":1,"groups":[1]}]},{"id":"x47-grid","tiles":[{"x":0,"y":0,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0.5,"y":0,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0,"y":0.5,"width":0.5,"height":0.5,"groups":[1,2]},{"x":0.5,"y":0.5,"width":0.5,"height":0.5,"groups":[1,2]}]}]'
  gsettings --schemadir "$sdir" set $s layouts-json "$layouts" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s selected-layouts "[['x47-term'], ['x47-term'], ['x47-term'], ['x47-term']]" 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s snap-assist-sync-layout true 2>/dev/null || true
  # Instant overlay dismiss — animated close was a common stuck-overlay path.
  gsettings --schemadir "$sdir" set $s snap-assistant-animation-time 0 2>/dev/null || true
  gsettings --schemadir "$sdir" set $s tile-preview-animation-time 0 2>/dev/null || true
  # Wobbly resize fights Tiling Shell's move_resize (size-change accounting errors).
  local wdir="$HOME/.local/share/gnome-shell/extensions/compiz-windows-effect@hermes83.github.com/schemas"
  if [[ -d "$wdir" ]]; then
    gsettings --schemadir "$wdir" set \
      org.gnome.shell.extensions.com.github.hermes83.compiz-windows-effect \
      resize-effect false 2>/dev/null || true
  fi
}

notification_click_activate() {
  gsettings set org.gnome.desktop.notifications show-banners true 2>/dev/null || true
  install_local_extension "x47-notif-activate@x47" "notification click → open app"
}

disable_heavy_fx() {
  local uuid cur cleaned
  for uuid in "${X47_HEAVY_FX_UUIDS[@]}"; do
    gnome-extensions disable "$uuid" 2>/dev/null || true
  done
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  cleaned="$cur"
  for uuid in "${X47_HEAVY_FX_UUIDS[@]}"; do
    cleaned="$(printf '%s' "$cleaned" | sed -E "s/'$uuid',? ?//g; s/, ]/]/g; s/\[,/[/g")"
  done
  gsettings set org.gnome.shell enabled-extensions "$cleaned" 2>/dev/null || true
  # Drop Power↔desktop sync — Visual/HP dual mode is gone.
  rm -f "$HOME/.config/autostart/x47-power-desktop-sync.desktop"
  gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
}

module_desktop_fx() {
  # shellcheck disable=SC1091
  . "$X47_ROOT/lib/desktop-mode.sh"
  # shellcheck disable=SC1091
  . "$X47_ROOT/lib/settings.sh"

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

  # Build is lean-only (no Visual / dual-mode stack).
  x47_seed_desktop_mode_settings performance performance
  log "desktop-fx: lean (no cube / blur / wobbly / Coverflow / Burn My Windows)"

  set_wallpaper
  show_apps_duster_icon
  screenshot_keybindings
  hover_window_controls
  firefox_hover_buttons
  gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']" 2>/dev/null || true
  gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 2>/dev/null || true
  gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true

  if ! have gnome-extensions; then
    warn "gnome-extensions CLI missing — wallpaper only"
    hide_dock
    disable_heavy_fx
    return 0
  fi

  hide_dock
  disable_heavy_fx

  local uuid ok_any=0
  for uuid in "${X47_FX_UUIDS[@]}"; do
    ego_install "$uuid" && ok_any=1 || true
  done
  tiling_shell_tune
  notification_click_activate
  apply_desktop_mode_helper performance

  ok "desktop-fx module done (lean)"
  if [[ "$ok_any" == "1" ]]; then
    log "Log out and back in so GNOME picks up tiling (Wayland)."
  fi
}

module_desktop_fx "$@"
