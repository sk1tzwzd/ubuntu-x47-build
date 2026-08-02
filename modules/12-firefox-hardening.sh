#!/usr/bin/env bash
# Harden the system Firefox (snap or deb) via an enterprise policies.json.
# Balanced profile: telemetry/ads off, tracking protection, HTTPS-only, DoH.
# JavaScript stays ON (this is the everyday browser, not the anon/Tor one).
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

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

  ok "Firefox hardening done (see about:policies in Firefox)"
}

module_firefox_hardening "$@"
