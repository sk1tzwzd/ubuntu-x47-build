#!/usr/bin/env bash
# Install X47 Settings (CLI/GUI) and seed ~/.config/x47/settings.conf from
# install-time flags (X47_PUTTY_CLIPBOARD / X47_WIN_SCREENSHOT).
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
# shellcheck disable=SC1091
. "$X47_ROOT/lib/settings.sh"

module_settings() {
  bootstrap_path
  local share="$HOME/.local/share/ubuntu-x47-build"
  mkdir -p "$share/lib" "$share/bin" "$HOME/.local/bin" \
    "$HOME/.local/share/applications" "$X47_SETTINGS_DIR"

  install -m 0644 "$X47_ROOT/lib/common.sh" "$share/lib/common.sh"
  install -m 0644 "$X47_ROOT/lib/settings.sh" "$share/lib/settings.sh"
  install -m 0755 "$X47_ROOT/scripts/x47-settings" "$share/bin/x47-settings"
  ln -sfn "$share/bin/x47-settings" "$HOME/.local/bin/x47-settings"

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
  x47_settings_apply

  ok "X47 Settings -> x47-settings (putty_clipboard=$(x47_settings_get putty_clipboard) win_screenshot=$(x47_settings_get win_screenshot))"
}

module_settings "$@"
