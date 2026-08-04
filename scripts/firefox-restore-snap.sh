#!/usr/bin/env bash
# Undo the Firefox snap -> Mozilla .deb swap: remove the Mozilla apt repo,
# reinstall the Firefox snap, and restore the migrated profile into the snap.
# The hardening policy at /etc/firefox/policies/policies.json applies to the
# snap too, so Firefox comes back hardened. Needs sudo; run once.
#
# Close Firefox before running this.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

need_sudo || die "firefox-restore-snap.sh needs sudo"

log "removing the Mozilla apt repo, pin, and key"
run_sudo rm -f \
  /etc/apt/sources.list.d/mozilla.list \
  /etc/apt/preferences.d/mozilla \
  /etc/apt/keyrings/packages.mozilla.org.asc

# Drop the Mozilla .deb if it got installed (keep Ubuntu's transitional shim).
if dpkg-query -W -f='${Version}' firefox 2>/dev/null | grep -qv 'snap'; then
  log "purging the Mozilla firefox .deb"
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq firefox >/dev/null 2>&1 || true
fi

run_sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true

log "reinstalling the Firefox snap"
if ! snap list firefox >/dev/null 2>&1; then
  run_sudo snap install firefox >/dev/null 2>&1 || die "snap install firefox failed"
fi
# Ensure Ubuntu's integration shim is present so 'firefox' resolves normally.
run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq firefox >/dev/null 2>&1 || true

# Restore the profile migrated to ~/.mozilla back into the snap sandbox.
SNAP_MOZ="$HOME/snap/firefox/common/.mozilla"
if [[ -d "$HOME/.mozilla/firefox" ]]; then
  log "restoring the Firefox profile into the snap"
  mkdir -p "$SNAP_MOZ"
  cp -a "$HOME/.mozilla/firefox" "$SNAP_MOZ/" 2>/dev/null || warn "profile copy failed"
  # profiles.ini lives one level up from the firefox/ dir
  [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]] \
    && cp -a "$HOME/.mozilla/firefox/profiles.ini" "$SNAP_MOZ/firefox/" 2>/dev/null || true
else
  warn "no ~/.mozilla/firefox profile found — snap will start with a fresh profile"
fi

ok "hardened Firefox snap restored (launch Firefox to confirm your bookmarks/settings)"
