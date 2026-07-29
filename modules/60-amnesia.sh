#!/usr/bin/env bash
# Amnesia mode: unprivileged "anon" user (RAM home + forced Tor), dark green
# desktop, Electrum/Feather/Kleopatra/KeePassXC, optional LUKS persistent vault.
# Opt-in (X47_WITH_AMNESIA=1). Requires sudo.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

ANON_USER="${ANON_USER:-anon}"
ANON_DEFAULT_PASS="${ANON_DEFAULT_PASS:-anon}"
AM_ASSETS="$X47_ROOT/assets/amnesia"

install_electrum() {
  local dest=/opt/x47-amnesia
  run_sudo mkdir -p "$dest"
  if [[ -x "$dest/electrum" ]] && [[ -f "$dest/electrum.AppImage" ]]; then
    log "Electrum already installed"
    return 0
  fi
  log "downloading Electrum AppImage"
  local ver url
  ver="$(curl -fsSL https://download.electrum.org/ \
    | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' \
    | sed 's/href="//;s/\/"//' \
    | sort -V | tail -n1)"
  [[ -n "$ver" ]] || { warn "could not resolve Electrum version"; return 1; }
  url="https://download.electrum.org/${ver}/electrum-${ver}-x86_64.AppImage"
  local tmp
  tmp="$(mktemp)"
  if download "$url" "$tmp"; then
    run_sudo install -m 0755 "$tmp" "$dest/electrum.AppImage"
    rm -f "$tmp"
    run_sudo tee "$dest/electrum" >/dev/null <<EOF
#!/usr/bin/env bash
exec "$dest/electrum.AppImage" "\$@"
EOF
    run_sudo chmod 0755 "$dest/electrum"
    ok "Electrum $ver -> $dest/electrum"
  else
    rm -f "$tmp"
    warn "Electrum download failed"
    return 1
  fi
}

install_persistent_helper() {
  log "installing persistent storage helper"
  run_sudo install -m 0755 "$AM_ASSETS/anon-persistent" /usr/local/sbin/anon-persistent
  run_sudo install -m 0755 "$AM_ASSETS/anon-persistent-gui" /usr/local/bin/anon-persistent-gui
  run_sudo install -m 0440 "$AM_ASSETS/sudoers-anon-persistent" /etc/sudoers.d/anon-persistent
  # Validate sudoers fragment
  if run_sudo visudo -cf /etc/sudoers.d/anon-persistent >/dev/null 2>&1; then
    ok "sudoers drop-in OK"
  else
    run_sudo rm -f /etc/sudoers.d/anon-persistent
    die "invalid sudoers drop-in for anon-persistent"
  fi
  run_sudo mkdir -p /var/lib/x47-amnesia /mnt/x47-persistent
  run_sudo chmod 750 /var/lib/x47-amnesia
  run_sudo chmod 755 /mnt/x47-persistent
}

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
  log "installing amnesia packages (tor, wallets, pgp, keepass, cryptsetup)"
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    tor nftables rsync cryptsetup zenity \
    feather-wallet keepassxc-full kleopatra \
    >/dev/null || die "failed to install amnesia packages"

  install_electrum || warn "Electrum install skipped (manual install later)"
  install_persistent_helper

  # --- unprivileged anon user ---
  if id "$ANON_USER" >/dev/null 2>&1; then
    log "user $ANON_USER already exists"
  else
    log "creating unprivileged user $ANON_USER"
    run_sudo useradd --create-home --shell /bin/bash \
      --comment "Anonymous (Amnesia)" "$ANON_USER"
    echo "${ANON_USER}:${ANON_DEFAULT_PASS}" | run_sudo chpasswd
    run_sudo passwd --expire "$ANON_USER" >/dev/null 2>&1 || true
    warn "default password for '$ANON_USER' is '${ANON_DEFAULT_PASS}' — it MUST be changed at first login"
  fi
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
  run_sudo chmod 0755 /var/lib/anon-skel/.local/bin/anon-desktop-setup 2>/dev/null || true
  run_sudo chown -R "$ANON_USER:$ANON_USER" /var/lib/anon-skel
  run_sudo chmod 0700 /var/lib/anon-skel

  # --- tmpfs home + repopulate service ---
  log "installing RAM-home units"
  run_sudo install -m 0644 "$AM_ASSETS/home-anon.mount" /etc/systemd/system/home-anon.mount
  run_sudo install -m 0644 "$AM_ASSETS/anon-home-populate.service" /etc/systemd/system/anon-home-populate.service
  run_sudo systemctl daemon-reload
  run_sudo systemctl enable home-anon.mount anon-home-populate.service >/dev/null 2>&1 || true
  run_sudo systemctl start home-anon.mount || warn "could not mount tmpfs home now (will apply on reboot)"
  run_sudo systemctl start anon-home-populate.service || warn "skeleton populate deferred to reboot"

  # --- Tor transparent proxy config ---
  log "configuring Tor transparent proxy (inline in /etc/tor/torrc)"
  local torrc=/etc/tor/torrc
  run_sudo sed -i '\#^%include /etc/tor/torrc.d/#d' "$torrc"
  run_sudo sed -i '/### X47 AMNESIA TOR BEGIN ###/,/### X47 AMNESIA TOR END ###/d' "$torrc"
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

  # --- nftables kill-switch ---
  log "installing nftables transparent-Tor kill-switch (anon uid=$anon_uid, tor uid=$tor_uid)"
  local rendered=/etc/nftables.d/anon-tor.nft
  run_sudo mkdir -p /etc/nftables.d
  sed -e "s/__ANON_UID__/$anon_uid/g" -e "s/__TOR_UID__/$tor_uid/g" \
    "$AM_ASSETS/anon-tor.nft" | run_sudo tee "$rendered" >/dev/null
  run_sudo chmod 0644 "$rendered"
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
  if run_sudo nft -f "$rendered"; then
    ok "nftables ruleset loaded"
  else
    warn "nft load failed — review $rendered"
  fi
  run_sudo systemctl enable nftables >/dev/null 2>&1 || true

  if [[ -n "$(run_sudo swapon --show=NAME --noheadings 2>/dev/null)" ]]; then
    warn "ACTIVE SWAP DETECTED: RAM (incl. anon's tmpfs home) can be paged to disk."
    warn "For true amnesia, disable swap or use encrypted zram."
  fi

  ok "amnesia mode installed"
  log "Log in as '$ANON_USER'. Dark green theme + Safest Firefox auto-apply."
  log "Apps: Electrum, Feather, Kleopatra, KeePassXC."
  log "Persistent vault: Create once, Unlock each session you need secrets. See ~/README-anon.txt"
}

module_amnesia "$@"
