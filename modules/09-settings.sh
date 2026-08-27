#!/usr/bin/env bash
# Install X47 Settings (CLI/GUI) and seed ~/.config/x47/settings.conf from
# install-time flags (clipboard / screenshot / desktop mode).
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck disable=SC1091
. "$X47_ROOT/lib/settings.sh"
# shellcheck disable=SC1091
. "$X47_ROOT/lib/desktop-mode.sh"

module_settings() {
  bootstrap_path
  local share="$HOME/.local/share/ubuntu-x47-build"
  mkdir -p "$share/lib" "$share/bin" "$HOME/.local/bin" \
    "$HOME/.local/share/applications" "$X47_SETTINGS_DIR"

  install -m 0644 "$X47_ROOT/lib/common.sh" "$share/lib/common.sh"
  install -m 0644 "$X47_ROOT/lib/settings.sh" "$share/lib/settings.sh"
  install -m 0644 "$X47_ROOT/lib/desktop-mode.sh" "$share/lib/desktop-mode.sh"
  install -m 0755 "$X47_ROOT/scripts/x47-settings" "$share/bin/x47-settings"
  install -m 0755 "$X47_ROOT/scripts/x47-display" "$share/bin/x47-display"
  install -m 0755 "$X47_ROOT/scripts/x47-nerovia-widgets" "$share/bin/x47-nerovia-widgets"
  if [[ -f "$X47_ROOT/scripts/x47-clean-launchers" ]]; then
    install -m 0755 "$X47_ROOT/scripts/x47-clean-launchers" "$share/bin/x47-clean-launchers"
    ln -sfn "$share/bin/x47-clean-launchers" "$HOME/.local/bin/x47-clean-launchers"
  fi
  ln -sfn "$share/bin/x47-settings" "$HOME/.local/bin/x47-settings"
  ln -sfn "$share/bin/x47-display" "$HOME/.local/bin/x47-display"
  ln -sfn "$share/bin/x47-nerovia-widgets" "$HOME/.local/bin/x47-nerovia-widgets"
  # Retired mode switcher — remove any older install.
  rm -f "$HOME/.local/bin/x47-desktop-mode" "$HOME/.local/bin/x47-power-desktop-sync" \
        "$share/bin/x47-desktop-mode" "$share/bin/x47-power-desktop-sync" \
        "$share/bin/x47-display-adaptive" "$HOME/.local/bin/x47-display-adaptive"

  # Stage Nerovia Firefox widget assets for the helper (Visual stack).
  if [[ -d "$X47_ROOT/assets/firefox/nerovia" ]]; then
    mkdir -p "$share/assets/firefox/nerovia"
    cp -a "$X47_ROOT/assets/firefox/nerovia/." "$share/assets/firefox/nerovia/"
  fi

  if [[ -f "$X47_ROOT/assets/desktop/x47-settings.desktop" ]]; then
    install -m 0644 "$X47_ROOT/assets/desktop/x47-settings.desktop" \
      "$HOME/.local/share/applications/x47-settings.desktop"
    if have update-desktop-database; then
      update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    fi
  fi

  # Seed / update feature keys from install flags (defaults on).
  x47_settings_ensure
  x47_settings_set putty_clipboard "${X47_PUTTY_CLIPBOARD:-1}"
  x47_settings_set win_screenshot "${X47_WIN_SCREENSHOT:-1}"

  # Performance-only desktop — the Visual mode switcher is retired.
  x47_settings_set_str desktop_mode performance
  x47_settings_set_str desktop_modes_installed performance

  # Do not autostart Power↔desktop sync (retired with the mode switcher).
  rm -f "$HOME/.config/autostart/x47-power-desktop-sync.desktop"

  x47_settings_apply

  ok "X47 Settings -> x47-settings (putty=$(x47_settings_get putty_clipboard) shot=$(x47_settings_get win_screenshot))"
}

module_settings "$@"
