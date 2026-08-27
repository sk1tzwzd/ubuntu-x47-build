# X47 desktop helpers — Performance-only build.
# The Visual/Performance switcher was removed: the desktop is always the lean
# Performance stack. This file keeps the shared extension UUID lists and the
# window-FX purge used by modules/51-desktop-fx.sh.
# shellcheck shell=bash

# Visual-stack extensions from the old Visual mode. Never installed now;
# uninstalled on sight so an old install cannot keep them loaded.
X47_HEAVY_FX_UUIDS=(
  "CoverflowAltTab@palatis.blogspot.com"
  "desktop-cube@schneegans.github.com"
  "blur-my-shell@aunetx"
  "x47-ws-walls@x47"
)

# Never enabled — no wobbly windows, no open/close window FX.
# Left on disk they come back after a login or an extension update.
X47_WINDOW_FX_UUIDS=(
  "burn-my-windows@schneegans.github.com"
  "compiz-windows-effect@hermes83.github.com"
)

# Retired top-bar mode toggle — uninstalled on sight too.
X47_RETIRED_UUIDS=(
  "x47-desktop-mode@x47"
)

# Disable + uninstall so GNOME cannot load them on the next session.
x47_purge_window_fx() {
  local uuid dir
  for uuid in "${X47_WINDOW_FX_UUIDS[@]}"; do
    gnome-extensions disable "$uuid" 2>/dev/null || true
    gnome-extensions uninstall "$uuid" 2>/dev/null || true
    dir="$HOME/.local/share/gnome-shell/extensions/$uuid"
    [[ -e "$dir" ]] && rm -rf "$dir"
    dir="$HOME/.local/share/gnome-shell/extension-updates/$uuid"
    [[ -e "$dir" ]] && rm -rf "$dir"
  done
}

# Remove an extension from enabled-extensions and uninstall it completely.
x47_uninstall_extension() {
  local uuid="$1" cur cleaned
  gnome-extensions disable "$uuid" 2>/dev/null || true
  gnome-extensions uninstall "$uuid" 2>/dev/null || true
  if have gsettings; then
    cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
    if [[ "$cur" == *"'$uuid'"* ]]; then
      cleaned="$(printf '%s' "$cur" | sed -E "s/'$uuid',? ?//g; s/, ]/]/g; s/\[,/[/g; s/\[ ,/[/g")"
      gsettings set org.gnome.shell enabled-extensions "$cleaned" 2>/dev/null || true
    fi
  fi
  local dir
  for dir in "$HOME/.local/share/gnome-shell/extensions/$uuid" \
             "$HOME/.local/share/gnome-shell/extension-updates/$uuid"; do
    [[ -e "$dir" ]] && rm -rf "$dir"
  done
}

# Always-on lean extensions (top-bar chips, tiling, notification focus).
X47_LEAN_FX_UUIDS=(
  "tilingshell@ferrarodomenico.com"
  "x47-notif-activate@x47"
  "x47-show-apps@x47"
  "x47-display@x47"
  "x47-syncthing@x47"
)
