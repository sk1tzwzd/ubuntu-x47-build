#!/usr/bin/env bash
# Install Rust toolchain (if needed) + cargo crates from cargo-crates.txt
# Heavy crates (eza/fd/delta/zoxide/rustscan) are handled by 23-tools-release.sh.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_tools_cargo() {
  bootstrap_path

  if ! have rustup && ! have cargo; then
    log "installing rustup (user install)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable >/dev/null
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  bootstrap_path
  have cargo || die "cargo not available after rustup install"

  local manifest="$X47_ROOT/assets/manifests/cargo-crates.txt"
  [[ -f "$manifest" ]] || die "missing $manifest"

  local line crate
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    crate="$line"
    # Prefer binary name = crate name (feroxbuster, bat)
    if have "$crate"; then
      log "skip $crate"
      continue
    fi
    log "cargo install $crate"
    if cargo install --locked "$crate" >/dev/null; then
      ok "$crate"
    else
      fail "$crate"
    fi
  done < "$manifest"

  ok "cargo tools module done"
}

module_tools_cargo "$@"
