#!/usr/bin/env bash
# Harden the system Firefox (snap or deb) via an enterprise policies.json.
# Balanced profile: telemetry/ads off, tracking protection, HTTPS-only, DoH.
# JavaScript stays ON (this is the everyday browser, not the anon/Tor one).
# Also force hardened Firefox as the default browser (over Chrome etc.).
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

firefox_desktop_id() {
  if [[ -f /var/lib/snapd/desktop/applications/firefox_firefox.desktop ]]; then
    echo firefox_firefox.desktop
  elif [[ -f /usr/share/applications/firefox.desktop ]]; then
    echo firefox.desktop
  elif [[ -f /usr/share/applications/firefox_firefox.desktop ]]; then
    echo firefox_firefox.desktop
  else
    echo ""
  fi
}

set_default_firefox() {
  local desk
  desk="$(firefox_desktop_id)"
  [[ -n "$desk" ]] || { warn "no Firefox .desktop found — skip default-browser"; return 0; }

  log "setting hardened Firefox as default browser ($desk)"
  if [[ "$(id -u)" -ne 0 ]]; then
    xdg-settings set default-web-browser "$desk" 2>/dev/null \
      || warn "xdg-settings set default-web-browser failed"
  elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    local home
    home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    sudo -u "$SUDO_USER" env HOME="$home" DISPLAY="${DISPLAY:-}" \
      xdg-settings set default-web-browser "$desk" 2>/dev/null \
      || warn "xdg-settings (as $SUDO_USER) failed"
  fi

  # mimeapps.list for the interactive user
  local conf_home mime
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    conf_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.config"
  else
    conf_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  fi
  mkdir -p "$conf_home"
  mime="$conf_home/mimeapps.list"
  if [[ ! -f "$mime" ]]; then
    cat > "$mime" <<EOF
[Default Applications]
x-scheme-handler/http=$desk
x-scheme-handler/https=$desk
text/html=$desk
application/xhtml+xml=$desk
EOF
  else
    # Ensure Default Applications section + keys
    if ! grep -q '^\[Default Applications\]' "$mime"; then
      printf '\n[Default Applications]\n' >> "$mime"
    fi
    local key
    for key in x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml; do
      if grep -q "^${key}=" "$mime"; then
        sed -i "s|^${key}=.*|${key}=${desk}|" "$mime"
      else
        # Insert after [Default Applications]
        sed -i "/^\[Default Applications\]/a ${key}=${desk}" "$mime"
      fi
    done
  fi
  # If we wrote as root into SUDO_USER home, fix ownership
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]]; then
    chown "$SUDO_USER:" "$mime" 2>/dev/null || true
  fi
  ok "default browser -> $desk"
}

module_firefox_hardening() {
  if [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "skipping Firefox hardening (user-only)"
    return 0
  fi
  need_sudo || die "12-firefox-hardening.sh needs sudo"

  local src="$X47_ROOT/assets/firefox/policies.json"
  [[ -f "$src" ]] || die "missing $src"

  # Ubuntu's Firefox snap and the Mozilla deb both read managed policies
  # from /etc/firefox/policies/policies.json.
  log "installing Firefox enterprise policy (/etc/firefox/policies)"
  run_sudo install -d -m 0755 /etc/firefox/policies
  run_sudo install -m 0644 "$src" /etc/firefox/policies/policies.json

  set_default_firefox

  ok "Firefox hardening done (see about:policies in Firefox)"
}

module_firefox_hardening "$@"
