#!/usr/bin/env bash
# Amnesia mode: create an unprivileged "anon" user whose home is RAM-only
# (tmpfs, wiped on reboot) and whose traffic is force-routed through Tor with a
# leak-blocking kill-switch. Opt-in (X47_WITH_AMNESIA=1) and requires sudo.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

ANON_USER="${ANON_USER:-anon}"
ANON_DEFAULT_PASS="${ANON_DEFAULT_PASS:-anon}"
AM_ASSETS="$X47_ROOT/assets/amnesia"

module_amnesia() {
  if [[ "${X47_WITH_AMNESIA:-0}" != "1" ]]; then
    log "amnesia mode not requested (use --with-amnesia) — skipping"
    return 0
  fi
  if [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "amnesia mode needs sudo and cannot run under --user-only — skipping"
    return 0
  fi
  need_sudo || die "60-amnesia.sh needs sudo"
  [[ -d "$AM_ASSETS" ]] || die "missing $AM_ASSETS — incomplete checkout"

  # --- packages ---
  log "installing tor, nftables, rsync"
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    tor nftables rsync >/dev/null || die "failed to install amnesia packages"

  # --- unprivileged anon user ---
  if id "$ANON_USER" >/dev/null 2>&1; then
    log "user $ANON_USER already exists"
  else
    log "creating unprivileged user $ANON_USER"
    # Create WITHOUT -m first: the home is a tmpfs mount populated at boot.
    run_sudo useradd --create-home --shell /bin/bash \
      --comment "Anonymous (Amnesia)" "$ANON_USER"
    echo "${ANON_USER}:${ANON_DEFAULT_PASS}" | run_sudo chpasswd
    run_sudo passwd --expire "$ANON_USER" >/dev/null 2>&1 || true
    warn "default password for '$ANON_USER' is '${ANON_DEFAULT_PASS}' — it MUST be changed at first login"
  fi
  # Ensure anon is NOT in privileged groups (kill-switch relies on this).
  local grp
  for grp in sudo adm wheel admin; do
    if id -nG "$ANON_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
      run_sudo deluser "$ANON_USER" "$grp" >/dev/null 2>&1 || true
    fi
  done

  local anon_uid tor_uid
  anon_uid="$(id -u "$ANON_USER")"
  tor_uid="$(id -u debian-tor 2>/dev/null || id -u tor 2>/dev/null || echo "")"
  [[ -n "$tor_uid" ]] || die "cannot resolve Tor user (debian-tor/tor) — is tor installed?"

  # --- pristine skeleton -> /var/lib/anon-skel ---
  log "staging pristine skeleton to /var/lib/anon-skel"
  run_sudo rm -rf /var/lib/anon-skel
  run_sudo mkdir -p /var/lib/anon-skel
  run_sudo cp -aT "$AM_ASSETS/skel" /var/lib/anon-skel
  run_sudo chown -R "$ANON_USER:$ANON_USER" /var/lib/anon-skel
  run_sudo chmod 0700 /var/lib/anon-skel

  # --- tmpfs home + repopulate service ---
  log "installing RAM-home units"
  # If /home/anon already has real contents from useradd, clear them; the tmpfs
  # mount will shadow them anyway, but keep the mountpoint clean.
  run_sudo install -m 0644 "$AM_ASSETS/home-anon.mount" /etc/systemd/system/home-anon.mount
  run_sudo install -m 0644 "$AM_ASSETS/anon-home-populate.service" /etc/systemd/system/anon-home-populate.service
  run_sudo systemctl daemon-reload
  run_sudo systemctl enable home-anon.mount anon-home-populate.service >/dev/null 2>&1 || true
  # Start now so it works this session too.
  run_sudo systemctl start home-anon.mount || warn "could not mount tmpfs home now (will apply on reboot)"
  run_sudo systemctl start anon-home-populate.service || warn "skeleton populate deferred to reboot"

  # --- Tor transparent proxy config ---
  # NOTE: the default `system_tor` AppArmor profile denies reading anything
  # under /etc/tor/torrc.d/, which makes a %include drop-in fail with
  # "Permission denied". Tor IS allowed to read /etc/tor/torrc itself, so we
  # append our directives there directly, between markers, for portability.
  log "configuring Tor transparent proxy (inline in /etc/tor/torrc)"
  local torrc=/etc/tor/torrc
  # Drop any include we may have added before, and any stale marked block.
  run_sudo sed -i '\#^%include /etc/tor/torrc.d/#d' "$torrc"
  run_sudo sed -i '/### X47 AMNESIA TOR BEGIN ###/,/### X47 AMNESIA TOR END ###/d' "$torrc"
  # Append a fresh block sourced from the asset (strip comments/blank lines).
  {
    echo ''
    echo '### X47 AMNESIA TOR BEGIN ###'
    grep -vE '^[[:space:]]*(#|$)' "$AM_ASSETS/torrc-anon.conf"
    echo '### X47 AMNESIA TOR END ###'
  } | run_sudo tee -a "$torrc" >/dev/null
  run_sudo systemctl enable tor >/dev/null 2>&1 || true
  run_sudo systemctl reset-failed tor@default.service >/dev/null 2>&1 || true
  run_sudo systemctl restart tor@default.service 2>/dev/null \
    || run_sudo systemctl restart tor \
    || warn "tor restart failed — check 'journalctl -u tor@default'"

  # --- nftables kill-switch (UID-substituted) ---
  log "installing nftables transparent-Tor kill-switch (anon uid=$anon_uid, tor uid=$tor_uid)"
  local rendered=/etc/nftables.d/anon-tor.nft
  run_sudo mkdir -p /etc/nftables.d
  sed -e "s/__ANON_UID__/$anon_uid/g" -e "s/__TOR_UID__/$tor_uid/g" \
    "$AM_ASSETS/anon-tor.nft" | run_sudo tee "$rendered" >/dev/null
  run_sudo chmod 0644 "$rendered"

  # Ensure /etc/nftables.conf includes our drop-in so it survives reboot.
  if [[ -f /etc/nftables.conf ]]; then
    if ! run_sudo grep -qF 'include "/etc/nftables.d/*.nft"' /etc/nftables.conf; then
      echo 'include "/etc/nftables.d/*.nft"' | run_sudo tee -a /etc/nftables.conf >/dev/null
    fi
  else
    {
      echo '#!/usr/sbin/nft -f'
      echo 'include "/etc/nftables.d/*.nft"'
    } | run_sudo tee /etc/nftables.conf >/dev/null
  fi

  # Load now and enable persistence.
  if run_sudo nft -f "$rendered"; then
    ok "nftables ruleset loaded"
  else
    warn "nft load failed — review $rendered"
  fi
  run_sudo systemctl enable nftables >/dev/null 2>&1 || true

  # --- swap leak warning ---
  if [[ -n "$(run_sudo swapon --show=NAME --noheadings 2>/dev/null)" ]]; then
    warn "ACTIVE SWAP DETECTED: RAM (incl. anon's tmpfs home) can be paged to disk."
    warn "For true amnesia, disable swap (sudo swapoff -a + remove from /etc/fstab) or use encrypted zram."
  fi

  ok "amnesia mode installed"
  log "Log in as '$ANON_USER' from the login screen. Home is RAM-only; all traffic is Tor-forced."
  log "Verify Tor at https://check.torproject.org — use Firefox, NOT Tor Browser (avoids Tor-over-Tor)."
}

module_amnesia "$@"
