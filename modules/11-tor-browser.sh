#!/usr/bin/env bash
# Download latest Tor Browser, extract to ~/tools/tor-browser, register app launcher.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

TOR_DOWNLOADS_JSON="${TOR_DOWNLOADS_JSON:-https://aus1.torproject.org/torbrowser/update_3/release/downloads.json}"

module_tor_browser() {
  bootstrap_path
  mkdir -p "$HOME/tools" "$HOME/.local/share/applications" "$HOME/.cache"

  local platform
  case "$(uname -m)" in
    x86_64|amd64) platform="linux-x86_64" ;;
    i686|i386)    platform="linux-i686" ;;
    *)
      warn "Tor Browser: unsupported arch $(uname -m) — skipping"
      return 0
      ;;
  esac

  local install_root="$HOME/tools/tor-browser"
  local starter="$install_root/Browser/start-tor-browser"

  # Idempotent: already installed and runnable
  if [[ -x "$starter" ]]; then
    log "Tor Browser already present at $install_root"
    # Ensure launcher is registered
    if [[ -x "$install_root/start-tor-browser.desktop" ]]; then
      (cd "$install_root" && ./start-tor-browser.desktop --register-app >/dev/null 2>&1) || true
    fi
    ok "Tor Browser (skipped download)"
    return 0
  fi

  log "resolving latest Tor Browser for $platform"
  local json url
  json="$(mktemp)"
  if ! download "$TOR_DOWNLOADS_JSON" "$json"; then
    fail "could not fetch Tor downloads.json"
    rm -f "$json"
    return 1
  fi

  # Prefer python for reliable JSON; fall back to grep/sed
  if have python3; then
    url="$(python3 - "$json" "$platform" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
plat = sys.argv[2]
print(data["downloads"][plat]["ALL"]["binary"])
PY
)"
  else
    url="$(grep -A2 "\"$platform\"" "$json" | grep -oE 'https://[^"]+tor-browser[^"]+\.tar\.xz' | head -n1)"
  fi
  rm -f "$json"

  [[ -n "${url:-}" ]] || { fail "could not resolve Tor Browser URL for $platform"; return 1; }
  log "downloading $url"

  local archive="$HOME/.cache/$(basename "$url")"
  download "$url" "$archive" || { fail "Tor Browser download failed"; return 1; }

  local tmp
  tmp="$(mktemp -d)"
  log "extracting Tor Browser"
  tar -xJf "$archive" -C "$tmp"

  # Archive contains a top-level "tor-browser/" directory
  local extracted
  extracted="$(find "$tmp" -maxdepth 2 -type d -name tor-browser | head -n1)"
  [[ -n "$extracted" ]] || extracted="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n1)"
  [[ -d "$extracted" ]] || { rm -rf "$tmp"; fail "unexpected Tor Browser archive layout"; return 1; }

  rm -rf "$install_root"
  mkdir -p "$(dirname "$install_root")"
  mv "$extracted" "$install_root"
  rm -rf "$tmp"

  # Register into the user application menu (writes ~/.local/share/applications/)
  if [[ -x "$install_root/start-tor-browser.desktop" ]]; then
    (cd "$install_root" && ./start-tor-browser.desktop --register-app) || \
      warn "Tor Browser --register-app failed (non-fatal)"
  fi

  # Convenience symlink for CLI
  ln -sfn "$install_root/Browser/start-tor-browser" "$HOME/.local/bin/tor-browser" 2>/dev/null || true

  if [[ -x "$starter" ]]; then
    ok "Tor Browser -> $install_root"
  else
    fail "Tor Browser extract succeeded but starter missing"
    return 1
  fi
}

module_tor_browser "$@"
