#!/usr/bin/env bash
# Install Python tools via pipx from assets/manifests/pipx-packages.txt
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_tools_pipx() {
  bootstrap_path

  if ! have pipx; then
    if have python3; then
      log "bootstrapping pipx via python3 -m pip"
      python3 -m pip install --user pipx >/dev/null 2>&1 || true
      python3 -m pipx ensurepath >/dev/null 2>&1 || true
      bootstrap_path
    fi
  fi
  have pipx || die "pipx not available"

  pipx ensurepath >/dev/null 2>&1 || true

  local manifest="$X47_ROOT/assets/manifests/pipx-packages.txt"
  [[ -f "$manifest" ]] || die "missing $manifest"

  # Map package -> probe binary
  probe_for() {
    case "$1" in
      httpie) echo http ;;
      bloodhound) echo bloodhound-python ;;
      impacket) echo smbserver.py ;;
      netexec) echo nxc ;;
      *) echo "$1" ;;
    esac
  }

  local line name pkg probe
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    if [[ "$line" == *"|"* ]]; then
      IFS='|' read -r name pkg <<< "$line"
    else
      name="$line"
      pkg="$line"
    fi
    probe="$(probe_for "$name")"
    if have "$probe"; then
      log "skip $name"
      continue
    fi
    log "pipx install $name"
    if pipx install "$pkg" >/dev/null; then
      have "$probe" && ok "$name" || warn "$name installed but probe '$probe' not on PATH"
    else
      # retry enum4linux from git if pip name failed
      if [[ "$name" == "enum4linux-ng" ]]; then
        pipx install "git+https://github.com/cddmp/enum4linux-ng.git" >/dev/null \
          && ok "$name" || fail "$name"
      else
        fail "$name"
      fi
    fi
  done < "$manifest"

  ok "pipx tools module done"
}

module_tools_pipx "$@"
