#!/usr/bin/env bash
# Desktop looks: Performance-only (lean). The old Visual mode (cube, Coverflow,
# blur, per-workspace walls) and the top-bar mode switcher are retired — window
# animations were already pulled from Visual, so the switch bought nothing.
# Dock stays hidden in favour of Super / the top-bar Show Apps button.
# CTRL-only tiling, X47 wallpapers, notification click-to-focus. User-level only.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck disable=SC1091
. "$X47_ROOT/lib/desktop-mode.sh"

AM_DESKTOP="$X47_ROOT/assets/desktop"

# Always ego-install tiling.
X47_FX_UUIDS=(
  "tilingshell@ferrarodomenico.com"
)

hide_dock() {
  log "hiding Ubuntu Dock — session keeps the extension; UI via manualhide"
  # Do not gnome-extensions disable ubuntu-dock: Ubuntu session mode lists it in
  # enabledExtensions and fighting that leaves ERROR + the dock often reappears.
  enable_uuid ubuntu-dock@ubuntu.com
  gsettings set org.gnome.shell.extensions.dash-to-dock manualhide true 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock autohide true 2>/dev/null || true
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false 2>/dev/null || true
  gnome-extensions disable dash-to-dock@micxgx.gmail.com 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']" 2>/dev/null || true
  ok "dock hidden — Super opens Activities; Super+1…9 launches favorites"
}

# Enable a uuid both via the CLI and by appending to the enabled-extensions
# array (belt and suspenders; the array survives until the next login).
enable_uuid() {
  local uuid="$1" cur cleaned
  # Clear disabled-extensions or Ubuntu Dock stays suppressed after Visual apply.
  cur="$(gsettings get org.gnome.shell disabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" == *"'$uuid'"* ]]; then
    cleaned="$(printf '%s' "$cur" | sed -E "s/'$uuid',? ?//g; s/, ]/]/g; s/\[,/[/g; s/\[ ,/[/g")"
    gsettings set org.gnome.shell disabled-extensions "$cleaned" 2>/dev/null || true
  fi
  gnome-extensions enable "$uuid" 2>/dev/null || true
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

# Firefox: strip X47 autohide/hover chrome — normal tabs/toolbar everywhere.
firefox_restore_normal_chrome() {
  local begin_old="/* --- x47 hover window buttons (Firefox) --- */"
  local end_old="/* --- end x47 hover window buttons --- */"
  local begin="/* --- x47 autohide chrome (unmaximized) --- */"
  local end="/* --- end x47 autohide chrome --- */"
  local pref_begin="// --- x47 userChrome ---"
  local pref_end="// --- end x47 userChrome ---"
  local prof found=0 css userjs tmp

  for prof in "$HOME"/snap/firefox/common/.mozilla/firefox/*.default* \
              "$HOME"/snap/firefox/common/.mozilla/firefox/*.x47 \
              "$HOME"/snap/firefox/common/.mozilla/firefox/amnesia.default \
              "$HOME"/snap/firefox/common/.mozilla/firefox/nerovia.x47 \
              "$HOME"/.mozilla/firefox/*.default* \
              "$HOME"/.mozilla/firefox/*.x47 \
              "$HOME"/.mozilla/firefox/amnesia.default \
              "$HOME"/.mozilla/firefox/nerovia.x47; do
    [[ -d "$prof" ]] || continue
    found=1
    css="$prof/chrome/userChrome.css"
    if [[ -f "$css" ]]; then
      strip_css_block "$css" "$begin_old" "$end_old"
      strip_css_block "$css" "$begin" "$end"
      if [[ ! -s "$css" ]] || ! grep -qE '[^[:space:]]' "$css" 2>/dev/null; then
        rm -f "$css"
        rmdir "$prof/chrome" 2>/dev/null || true
      fi
    fi

    userjs="$prof/user.js"
    [[ -f "$userjs" ]] || continue
    tmp="$(mktemp)"
    awk -v b="$pref_begin" -v e="$pref_end" '
      index($0, b) { skip = 1; next }
      index($0, e) { skip = 0; next }
      skip { next }
      /toolkit\.legacyUserProfileCustomizations\.stylesheets/ { next }
      /Allow chrome\/userChrome\.css/ { next }
      { print }
    ' "$userjs" > "$tmp"
    mv "$tmp" "$userjs"
  done

  if [[ "$found" == "1" ]]; then
    ok "Firefox: normal chrome restored (restart Firefox if it is open)"
  else
    log "no Firefox profile yet — stock chrome on first launch"
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

show_apps_top_bar() {
  install_local_extension "x47-show-apps@x47" "top-bar Show Apps (green Ubuntu circle)"
}

retire_visual_stack() {
  # Visual mode is gone: uninstall its extensions (cube, Coverflow, blur,
  # per-workspace walls) and the old top-bar mode toggle, then strip the
  # adaptive-display autostart (a Visual-stack feature).
  local uuid
  for uuid in "${X47_HEAVY_FX_UUIDS[@]}" "${X47_RETIRED_UUIDS[@]}"; do
    x47_uninstall_extension "$uuid"
  done
  rm -f "$HOME/.config/autostart/x47-display-adaptive.desktop"
  rm -f "$HOME/.config/autostart/x47-power-desktop-sync.desktop"
  if [[ -x "$HOME/.local/bin/x47-display" ]]; then
    "$HOME/.local/bin/x47-display" adaptive off >/dev/null 2>&1 || true
  fi
  # Retired mode-switcher binaries.
  rm -f "$HOME/.local/bin/x47-desktop-mode" "$HOME/.local/bin/x47-power-desktop-sync"
  rm -f "$HOME/.local/share/ubuntu-x47-build/bin/x47-desktop-mode" \
        "$HOME/.local/share/ubuntu-x47-build/bin/x47-power-desktop-sync"
}

display_comfort_panel() {
  # Brightness / blue-light / glare sliders (right status area).
  if [[ -x "$HOME/.local/bin/x47-display" ]]; then
    "$HOME/.local/bin/x47-display" apply >/dev/null 2>&1 || true
  elif [[ -x "$X47_ROOT/scripts/x47-display" ]]; then
    "$X47_ROOT/scripts/x47-display" apply >/dev/null 2>&1 || true
  fi
  install_local_extension "x47-display@x47" "top-bar display comfort (brightness / blue-light / glare)"
}

install_nerovia_widgets() {
  # Retired — never seed profile/autostart; strip leftovers instead.
  remove_nerovia_widgets
  log "Nerovia Firefox widgets retired (not installed)"
}

remove_nerovia_widgets() {
  rm -f "$HOME/.config/autostart/x47-nerovia-widgets.desktop"
  rm -f "$HOME/.local/share/applications/x47-nerovia-chart.desktop"
  rm -f "$HOME/.local/share/applications/x47-nerovia-positions.desktop"
  # Leave a disabled stub so an old session generator can't revive the launcher.
  mkdir -p "$HOME/.config/autostart"
  cat >"$HOME/.config/autostart/x47-nerovia-widgets.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=X47 Nerovia Widgets (disabled)
Exec=/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
  pkill -f 'firefox.*-P nerovia' >/dev/null 2>&1 || true
  if [[ -x "$HOME/.local/bin/x47-nerovia-widgets" ]]; then
    "$HOME/.local/bin/x47-nerovia-widgets" stop >/dev/null 2>&1 || true
  fi
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

  log "desktop-fx: Performance-only (Visual mode and the switcher are retired)"
  x47_settings_ensure
  x47_settings_set_str desktop_mode performance
  x47_settings_set_str desktop_modes_installed performance
  x47_purge_window_fx

  set_wallpaper
  show_apps_duster_icon
  screenshot_keybindings
  hover_window_controls
  firefox_restore_normal_chrome
  gsettings set org.gnome.desktop.wm.keybindings toggle-fullscreen "['F11']" 2>/dev/null || true
  gsettings set org.gnome.mutter dynamic-workspaces false 2>/dev/null || true
  gsettings set org.gnome.desktop.wm.preferences num-workspaces 4 2>/dev/null || true
  gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true

  if ! have gnome-extensions; then
    warn "gnome-extensions CLI missing — wallpaper only"
    hide_dock
    return 0
  fi

  local uuid ok_any=0
  for uuid in "${X47_FX_UUIDS[@]}"; do
    ego_install "$uuid" && ok_any=1 || true
  done

  # Visual stack + mode toggle: uninstalled, not just disabled.
  retire_visual_stack
  # Nerovia Firefox widgets retired — always strip autostart/app entries.
  remove_nerovia_widgets

  tiling_shell_tune
  notification_click_activate
  show_apps_top_bar
  display_comfort_panel
  hide_dock

  ok "desktop-fx module done (Performance-only)"
  if [[ "$ok_any" == "1" ]]; then
    log "Log out and back in so GNOME picks up extensions (Wayland)."
  fi
}

module_desktop_fx "$@"
