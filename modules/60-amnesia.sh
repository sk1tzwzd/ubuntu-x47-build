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

install_wezterm_shared() {
  # Anon cannot read the main user's home — ship a world-usable wezterm wrapper.
  # Prefer the installing user's tools dir (works on fresh ISO installs too).
  local src_home="$HOME"
  if [[ -n "${SUDO_USER:-}" ]]; then
    src_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    [[ -n "$src_home" ]] || src_home="$HOME"
  fi
  local src_appimage="$src_home/tools/wezterm/wezterm.AppImage"
  local src_apprun="$src_home/tools/wezterm/squashfs-root/AppRun"
  local dest=/opt/x47-amnesia/wezterm
  run_sudo mkdir -p "$dest"
  if [[ -x "$src_apprun" ]]; then
    if [[ ! -x "$dest/squashfs-root/AppRun" ]]; then
      log "copying WezTerm into /opt/x47-amnesia for shared use"
      run_sudo rm -rf "$dest/squashfs-root"
      run_sudo cp -a "$src_home/tools/wezterm/squashfs-root" "$dest/"
      [[ -f "$src_appimage" ]] && run_sudo cp -a "$src_appimage" "$dest/wezterm.AppImage" || true
    fi
  elif [[ -x "$src_appimage" ]]; then
    run_sudo cp -a "$src_appimage" "$dest/wezterm.AppImage"
    (cd "$dest" && run_sudo ./wezterm.AppImage --appimage-extract >/dev/null) || true
  else
    warn "WezTerm not found under $src_home/tools/wezterm — run 10-terminal first"
    return 1
  fi
  run_sudo tee /usr/local/bin/wezterm >/dev/null <<EOF
#!/usr/bin/env bash
exec /opt/x47-amnesia/wezterm/squashfs-root/AppRun "\$@"
EOF
  run_sudo chmod 0755 /usr/local/bin/wezterm
  ok "shared wezterm -> /usr/local/bin/wezterm"
}

install_vulnscape() {
  local dest=/opt/x47-amnesia/vulnscape
  run_sudo mkdir -p /opt/x47-amnesia
  if [[ -d "$dest/.git" ]]; then
    log "updating VulnScape in $dest"
    run_sudo git -C "$dest" fetch --tags origin 2>/dev/null || true
    run_sudo git -C "$dest" pull --ff-only origin main 2>/dev/null \
      || run_sudo git -C "$dest" pull --ff-only origin master 2>/dev/null \
      || warn "VulnScape git pull failed — keeping existing checkout"
  else
    log "cloning VulnScape into $dest"
    run_sudo rm -rf "$dest"
    if ! run_sudo git clone --depth 1 https://github.com/sk1tzwzd/vulnscape.git "$dest"; then
      # Fallback: copy from this machine's checkout if clone fails
      if [[ -f /home/wzd/Projects/GW/vulnscape.sh ]]; then
        warn "clone failed — copying local /home/wzd/Projects/GW"
        run_sudo mkdir -p "$dest"
        run_sudo cp -a /home/wzd/Projects/GW/vulnscape.sh /home/wzd/Projects/GW/README.md \
          /home/wzd/Projects/GW/LICENSE /home/wzd/Projects/GW/CHANGELOG.md "$dest/" 2>/dev/null || true
        run_sudo cp -a /home/wzd/Projects/GW/vulnscape.sh "$dest/vulnscape.sh"
      else
        warn "VulnScape not installed"
        return 1
      fi
    fi
  fi
  # Prefer freshest local tree if it's ahead of the clone (same machine maintainers)
  if [[ -f /home/wzd/Projects/GW/vulnscape.sh ]]; then
    local local_mtime remote_mtime
    local_mtime="$(stat -c %Y /home/wzd/Projects/GW/vulnscape.sh 2>/dev/null || echo 0)"
    remote_mtime="$(stat -c %Y "$dest/vulnscape.sh" 2>/dev/null || echo 0)"
    if [[ "$local_mtime" -gt "$remote_mtime" ]]; then
      log "syncing newer local VulnScape into $dest"
      run_sudo cp -a /home/wzd/Projects/GW/vulnscape.sh "$dest/vulnscape.sh"
      [[ -f /home/wzd/Projects/GW/CHANGELOG.md ]] && run_sudo cp -a /home/wzd/Projects/GW/CHANGELOG.md "$dest/" || true
      [[ -f /home/wzd/Projects/GW/README.md ]] && run_sudo cp -a /home/wzd/Projects/GW/README.md "$dest/" || true
    fi
  fi
  run_sudo chmod 0755 "$dest/vulnscape.sh"
  run_sudo tee /usr/local/bin/vulnscape >/dev/null <<EOF
#!/usr/bin/env bash
exec /opt/x47-amnesia/vulnscape/vulnscape.sh "\$@"
EOF
  run_sudo chmod 0755 /usr/local/bin/vulnscape
  # Icon for all users
  if [[ -f "$X47_ROOT/assets/icons/hicolor/scalable/apps/kali-cool-vulnscape.svg" ]]; then
    run_sudo mkdir -p /usr/share/icons/hicolor/scalable/apps
    run_sudo cp -a "$X47_ROOT/assets/icons/hicolor/scalable/apps/kali-cool-vulnscape.svg" \
      /usr/share/icons/hicolor/scalable/apps/
    run_sudo gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
  fi
  local ver
  ver="$(grep -m1 -E '^\s*VERSION=|VulnScape v|1\.[0-9]+\.[0-9]+' "$dest/vulnscape.sh" 2>/dev/null | head -1 || true)"
  ok "VulnScape -> /usr/local/bin/vulnscape (${ver:-installed})"
}

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

# Copy lean desktop-fx extensions into a shared cache and the anon skel
# (tiling + notif only — never cube/blur/wobbly/Coverflow/BMW/widgets).
stage_anon_desktop_fx_into_skel() {
  local skel="${1:?skel dest}"
  local cache=/opt/x47-amnesia/gnome-shell-extensions
  local src_root="$HOME"
  if [[ ! -d "$src_root/.local/share/gnome-shell/extensions" ]] && [[ -n "${SUDO_USER:-}" ]]; then
    src_root="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  fi
  local src_ext="$src_root/.local/share/gnome-shell/extensions"
  local uuids=(
    "tilingshell@ferrarodomenico.com"
    "x47-notif-activate@x47"
    "x47-show-apps@x47"
  )
  local heavy=(
    "CoverflowAltTab@palatis.blogspot.com"
    "desktop-cube@schneegans.github.com"
    "burn-my-windows@schneegans.github.com"
    "blur-my-shell@aunetx"
    "compiz-windows-effect@hermes83.github.com"
    "x47-ws-walls@x47"
  )
  local uuid found=0
  run_sudo mkdir -p "$cache" "$skel/.local/share/gnome-shell/extensions"
  # Purge heavy FX leftovers from older installs.
  for uuid in "${heavy[@]}"; do
    run_sudo rm -rf "$cache/$uuid" "$skel/.local/share/gnome-shell/extensions/$uuid"
  done
  run_sudo rm -rf "$skel/.config/burn-my-windows"
  for uuid in "${uuids[@]}"; do
    if [[ -d "$src_ext/$uuid" ]]; then
      log "staging extension for anon: $uuid"
      run_sudo rm -rf "$cache/$uuid" "$skel/.local/share/gnome-shell/extensions/$uuid"
      run_sudo cp -a "$src_ext/$uuid" "$cache/"
      run_sudo cp -a "$src_ext/$uuid" "$skel/.local/share/gnome-shell/extensions/"
      found=1
    elif [[ -d "$cache/$uuid" ]]; then
      log "reusing cached extension for anon: $uuid"
      run_sudo rm -rf "$skel/.local/share/gnome-shell/extensions/$uuid"
      run_sudo cp -a "$cache/$uuid" "$skel/.local/share/gnome-shell/extensions/"
      found=1
    else
      warn "desktop-fx extension missing for anon skel: $uuid (run 51-desktop-fx first)"
    fi
  done
  # Refresh wallpaper from build assets (skel may already have them).
  local desk="$X47_ROOT/assets/desktop"
  run_sudo mkdir -p "$skel/.local/share/backgrounds"
  local wf
  # Same teal circuit as main; keep shroud as optional fallback.
  for wf in x47-circuit.png x47-anon.png; do
    [[ -f "$desk/wallpapers/$wf" ]] || continue
    run_sudo install -m 0644 "$desk/wallpapers/$wf" "$skel/.local/share/backgrounds/$wf"
  done
  # Lime Show Apps icon theme (matches main account).
  local icon_src="$X47_ROOT/assets/icons/show-apps-duster"
  local icon_dst="$skel/.local/share/icons/X47"
  if [[ -d "$icon_src" ]]; then
    run_sudo rm -rf "$icon_dst"
    if [[ -d "$HOME/.local/share/icons/X47" ]]; then
      run_sudo mkdir -p "$skel/.local/share/icons"
      run_sudo cp -a "$HOME/.local/share/icons/X47" "$icon_dst"
    else
      # Minimal theme from assets (PNGs may be generated on main by 51-desktop-fx).
      run_sudo mkdir -p "$icon_dst/scalable/actions"
      run_sudo tee "$icon_dst/index.theme" >/dev/null <<'EOF'
[Icon Theme]
Name=X47
Comment=Yaru-blue-dark with X47 Show Apps duster
Inherits=Yaru-blue-dark,Yaru,hicolor
Directories=scalable/actions
[scalable/actions]
Context=Actions
Size=16
MinSize=8
MaxSize=512
Type=Scalable
EOF
      for f in view-app-grid-ubuntu-symbolic.svg view-app-grid-symbolic.svg view-app-grid-ubiquity-symbolic.svg; do
        [[ -f "$icon_src/$f" ]] && run_sudo install -m 0644 "$icon_src/$f" "$icon_dst/scalable/actions/$f"
      done
    fi
  fi
  # Bundled X47 extensions (also copied from main user if present).
  local bund
  for bund in x47-anon-status@x47 x47-notif-activate@x47 x47-show-apps@x47; do
    if [[ -d "$X47_ROOT/assets/extensions/$bund" ]]; then
      run_sudo mkdir -p "$skel/.local/share/gnome-shell/extensions"
      run_sudo rm -rf "$skel/.local/share/gnome-shell/extensions/$bund"
      run_sudo cp -a "$X47_ROOT/assets/extensions/$bund" \
        "$skel/.local/share/gnome-shell/extensions/"
    fi
  done
  # Hover-only min/max/close was removed — leave anon GTK css alone / empty.
  for d in gtk-3.0 gtk-4.0; do
    if [[ -f "$skel/.config/$d/gtk.css" ]] && grep -qF 'x47 hover window controls' "$skel/.config/$d/gtk.css" 2>/dev/null; then
      run_sudo rm -f "$skel/.config/$d/gtk.css"
    fi
  done
  if [[ -f "$X47_ROOT/assets/wezterm/wezterm.lua" ]]; then
    run_sudo mkdir -p "$skel/.config/wezterm" "$skel/.config/wzd"
    run_sudo install -m 0644 "$X47_ROOT/assets/wezterm/wezterm.lua" "$skel/.config/wezterm/wezterm.lua"
    [[ -f "$X47_ROOT/assets/wzd/watermark.png" ]] \
      && run_sudo install -m 0644 "$X47_ROOT/assets/wzd/watermark.png" "$skel/.config/wzd/watermark.png"
  fi
  if [[ "$found" == "1" ]]; then
    ok "anon lean desktop-fx extensions staged (no heavy FX / widgets)"
  else
    warn "no desktop-fx extensions staged — anon still gets wallpaper/dock/WezTerm"
  fi
}

install_persistent_helper() {
  log "installing persistent storage + MAC spoof helpers"
  run_sudo install -m 0755 "$AM_ASSETS/anon-persistent" /usr/local/sbin/anon-persistent
  run_sudo install -m 0755 "$AM_ASSETS/anon-persistent-gui" /usr/local/bin/anon-persistent-gui
  run_sudo install -m 0755 "$AM_ASSETS/anon-mac-spoof" /usr/local/sbin/anon-mac-spoof
  run_sudo install -m 0644 "$AM_ASSETS/x47-mac-cleanup.service" /etc/systemd/system/x47-mac-cleanup.service
  run_sudo install -m 0440 "$AM_ASSETS/sudoers-anon-persistent" /etc/sudoers.d/anon-persistent
  if run_sudo visudo -cf /etc/sudoers.d/anon-persistent >/dev/null 2>&1; then
    ok "sudoers drop-in OK"
  else
    run_sudo rm -f /etc/sudoers.d/anon-persistent
    die "invalid sudoers drop-in for anon-persistent"
  fi
  run_sudo mkdir -p /var/lib/x47-amnesia /mnt/x47-persistent /run/x47-amnesia
  run_sudo chmod 750 /var/lib/x47-amnesia
  run_sudo chmod 755 /mnt/x47-persistent
  run_sudo systemctl daemon-reload
  run_sudo systemctl enable x47-mac-cleanup.service >/dev/null 2>&1 || true
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
    tor obfs4proxy nftables rsync cryptsetup zenity \
    feather-wallet keepassxc-full kleopatra \
    >/dev/null || die "failed to install amnesia packages"

  install_wezterm_shared || warn "shared WezTerm skipped"
  install_vulnscape || warn "VulnScape install skipped"
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
  stage_anon_desktop_fx_into_skel /var/lib/anon-skel
  run_sudo chmod 0755 /var/lib/anon-skel/.local/bin/* 2>/dev/null || true
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
  log "Apps: Electrum, Feather, Kleopatra, KeePassXC, VulnScape, Mullvad VPN."
  log "Privacy: random MAC on anon login (restored on logout); Mullvad VPN for VPN layer."
  log "Persistent vault: Create once, Unlock each session you need secrets. See ~/README-anon.txt"
}

module_amnesia "$@"
