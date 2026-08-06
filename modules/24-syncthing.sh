#!/usr/bin/env bash
# Install hardened Syncthing for secure Android ↔ PC file sync (LAN-first).
# No cloud, no KDE Connect. User-level binary + systemd --user service.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_syncthing() {
  bootstrap_path
  local share="$HOME/.local/share/ubuntu-x47-build"
  mkdir -p "$share/bin" "$HOME/.local/bin"

  install -m 0755 "$X47_ROOT/scripts/x47-syncthing" "$share/bin/x47-syncthing"
  ln -sfn "$share/bin/x47-syncthing" "$HOME/.local/bin/x47-syncthing"

  if [[ "${X47_SKIP_SYNCTHING:-0}" == "1" ]]; then
    warn "skipping Syncthing install (X47_SKIP_SYNCTHING=1)"
    return 0
  fi

  log "installing hardened Syncthing (LAN-first, no relays/global discovery)"
  if "$HOME/.local/bin/x47-syncthing" install; then
    ok "Syncthing ready — pair Android with: x47-syncthing id"
    ok "GUI (localhost): x47-syncthing open   creds: ~/.config/x47/syncthing-gui.cred"
  else
    warn "Syncthing install failed (network?). Retry: x47-syncthing install"
  fi
}

module_syncthing "$@"
