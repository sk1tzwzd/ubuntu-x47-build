#!/usr/bin/env bash
# Desktop widget: installs the bundled "Linux CMD Helper" GNOME extension —
# a single desktop card that turns plain-English questions into Ubuntu
# terminal commands (Anthropic Claude Haiku; click result to copy). Drawn
# above desktop icons but beneath app windows. User-level only (no sudo).
# On Wayland the widget appears after a log out / log back in.
#
# API key: reads X47_ANTHROPIC_KEY (env) into ~/.config/x47-widgets/anthropic.key
# (chmod 600). The key is never bundled in this public repo.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

UUID="x47-widgets@x47"
SRC="$X47_ROOT/assets/widgets/$UUID"
DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"
KEY_FILE="$HOME/.config/x47-widgets/anthropic.key"

module_widgets() {
  if [[ "${X47_SKIP_DESKTOP_FX:-0}" == "1" ]]; then
    warn "skipping widgets module (--skip-desktop-fx)"
    return 0
  fi
  if ! have gsettings; then
    warn "gsettings not available — skipping widgets"
    return 0
  fi
  [[ -d "$SRC" ]] || { warn "missing $SRC — skipping widgets"; return 0; }

  log "installing Linux CMD Helper extension"
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  cp -r "$SRC" "$DEST"

  # API key for the helper (never shipped in the repo).
  mkdir -p "$(dirname "$KEY_FILE")"
  if [[ -n "${X47_ANTHROPIC_KEY:-}" ]]; then
    printf '%s\n' "$X47_ANTHROPIC_KEY" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    ok "Anthropic API key -> $KEY_FILE"
  elif [[ ! -s "$KEY_FILE" ]]; then
    warn "no API key at $KEY_FILE — the widget will prompt for one."
    warn "add it with: echo 'sk-ant-…' > $KEY_FILE && chmod 600 $KEY_FILE"
  fi

  # Enable: CLI first, then make sure the uuid is in enabled-extensions.
  gnome-extensions enable "$UUID" 2>/dev/null || true
  local cur
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")"
  if [[ "$cur" != *"'$UUID'"* ]]; then
    if [[ "$cur" == "@as []" || "$cur" == "[]" ]]; then
      gsettings set org.gnome.shell enabled-extensions "['$UUID']" 2>/dev/null || true
    else
      gsettings set org.gnome.shell enabled-extensions "${cur%]}, '$UUID']" 2>/dev/null || true
    fi
  fi

  ok "Linux CMD Helper installed — log out and back in to see it on the desktop"
}

module_widgets "$@"
