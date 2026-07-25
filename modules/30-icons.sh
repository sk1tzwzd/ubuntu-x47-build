#!/usr/bin/env bash
# Install bundled hicolor icon pack (kali-*, kali-cool-*, x47duster) and rebuild cache.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_icons() {
  local src="$X47_ROOT/assets/icons/hicolor"
  local dest="$HOME/.local/share/icons/hicolor"
  [[ -d "$src" ]] || die "missing $src — run snapshot.sh first"

  log "installing icon pack into $dest"
  mkdir -p "$dest"
  # rsync-like copy preserving structure
  cp -a "$src/." "$dest/"

  # Also place source x47duster.png if present (for regeneration later)
  if [[ -f "$X47_ROOT/assets/wzd/x47duster.png" ]]; then
    mkdir -p "$dest/512x512/apps"
    # Only copy if sized variants missing — snapshot should have already sized them
    [[ -f "$dest/256x256/apps/x47duster.png" ]] || \
      cp -a "$X47_ROOT/assets/wzd/x47duster.png" "$dest/512x512/apps/"
  fi

  if have gtk-update-icon-cache; then
    gtk-update-icon-cache -f -t "$dest" >/dev/null 2>&1 || true
  fi
  # Also try xdg icon cache
  if have update-icon-caches; then
    update-icon-caches "$dest" >/dev/null 2>&1 || true
  fi

  ok "icons installed ($(find "$dest" -type f | wc -l) files)"
}

module_icons "$@"
