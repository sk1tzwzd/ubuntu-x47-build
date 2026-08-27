#!/usr/bin/env bash
# Install X47 Updates helper + desktop entry, and harden Mullvad GUI on Wayland.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

_install_updates_bin() {
  local src="$X47_ROOT/scripts/x47-updates"
  local dest_dir="$HOME/.local/share/ubuntu-x47-build/bin"
  local link="$HOME/.local/bin/x47-updates"
  [[ -f "$src" ]] || die "missing $src"
  mkdir -p "$dest_dir" "$HOME/.local/bin"
  install -m 0755 "$src" "$dest_dir/x47-updates"
  ln -sfn "$dest_dir/x47-updates" "$link"
  ln -sfn "$dest_dir/x47-updates" "$HOME/.local/bin/x47-clean"
  ok "x47-updates → $link (alias: x47-clean)"
}

_install_updates_desktop() {
  local src="$X47_ROOT/assets/desktop/x47-updates.desktop"
  local dest="$HOME/.local/share/applications/x47-updates.desktop"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/x47-updates gui|" "$dest"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "desktop entry → $dest"
}

# Weekly system-side tidy: journal vacuum, crash dumps, disabled snap
# revisions, apt caches. Self-contained root script + system timer — it must
# not depend on (or execute) anything user-writable. Never touches user files;
# the fuller interactive clean stays in `x47-clean`.
_install_tidy_timer() {
  if [[ "${X47_SKIP_APT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    return 0
  fi
  if ! need_sudo; then
    warn "x47-tidy timer needs sudo — skipped"
    return 0
  fi
  log "installing weekly x47-tidy timer (journals, crash dumps, old snaps, apt cache)"
  run_sudo tee /usr/local/sbin/x47-tidy >/dev/null <<'EOF'
#!/usr/bin/env bash
# X47 weekly tidy — system-side junk only. User files are never touched.
set -u
journalctl --vacuum-size=200M 2>/dev/null || true
rm -f /var/crash/*.crash /var/crash/*.upload* 2>/dev/null || true
if command -v snap >/dev/null 2>&1; then
  snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | \
  while read -r name rev; do
    snap remove "$name" --revision="$rev" 2>/dev/null || true
  done
fi
apt-get -y autoremove --purge >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
EOF
  run_sudo chmod 0755 /usr/local/sbin/x47-tidy
  run_sudo tee /etc/systemd/system/x47-tidy.service >/dev/null <<'EOF'
[Unit]
Description=X47 weekly tidy (journals, crash dumps, old snaps, apt cache)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/x47-tidy
Nice=19
IOSchedulingClass=idle
EOF
  run_sudo tee /etc/systemd/system/x47-tidy.timer >/dev/null <<'EOF'
[Unit]
Description=Run X47 tidy weekly

[Timer]
OnCalendar=weekly
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
  run_sudo systemctl daemon-reload
  run_sudo systemctl enable --now x47-tidy.timer >/dev/null 2>&1 || true
  ok "x47-tidy.timer weekly (undo: sudo systemctl disable --now x47-tidy.timer)"
}

# Restore Mullvad apt source when the package is present but the list was dropped.
_repair_mullvad_apt_source() {
  if [[ "${X47_SKIP_APT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    return 0
  fi
  if ! dpkg -s mullvad-vpn >/dev/null 2>&1; then
    return 0
  fi
  local need_repair=0
  if [[ ! -f /etc/apt/sources.list.d/mullvad.list ]]; then
    need_repair=1
  else
    local suite
    suite="$(awk '/^deb / {
      for (i=1;i<=NF;i++) if ($i ~ /^https?:/) { print $(i+1); exit }
    }' /etc/apt/sources.list.d/mullvad.list 2>/dev/null || true)"
    if [[ -z "$suite" ]] || ! curl -fsSIL "https://repository.mullvad.net/deb/stable/dists/${suite}/Release" >/dev/null 2>&1; then
      need_repair=1
    fi
  fi
  [[ "$need_repair" -eq 1 ]] || return 0
  if ! need_sudo; then
    warn "Mullvad apt source needs repair — re-run with sudo or: x47-updates repair-sources"
    return 0
  fi
  log "restoring Mullvad apt repository"
  local host_codename codename arch_name key_tmp list_tmp
  host_codename="$(. /etc/os-release; echo "${VERSION_CODENAME:-noble}")"
  # Mullvad lags new Ubuntu series (e.g. resolute); fall back to noble.
  codename="$host_codename"
  if ! curl -fsSIL "https://repository.mullvad.net/deb/stable/dists/${codename}/Release" >/dev/null 2>&1; then
    codename="noble"
    warn "Mullvad has no ${host_codename} suite — using ${codename}"
  fi
  arch_name="$(dpkg --print-architecture)"
  key_tmp="$(mktemp)"
  list_tmp="$(mktemp)"
  if ! curl -fsSL https://repository.mullvad.net/deb/mullvad-keyring.asc -o "$key_tmp"; then
    rm -f "$key_tmp" "$list_tmp"
    warn "Mullvad key download failed — skip source restore"
    return 0
  fi
  printf 'deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=%s] https://repository.mullvad.net/deb/stable %s main\n' \
    "$arch_name" "$codename" >"$list_tmp"
  if run_sudo install -m 0644 "$key_tmp" /usr/share/keyrings/mullvad-keyring.asc \
    && run_sudo install -m 0644 "$list_tmp" /etc/apt/sources.list.d/mullvad.list; then
    run_sudo apt-get update -qq || true
    ok "Mullvad apt source restored"
  else
    warn "Mullvad apt source restore needs a password — run: x47-updates repair-sources"
  fi
  rm -f "$key_tmp" "$list_tmp"
}

# Wayland + AMD: Electron GPU process dies (SIGTRAP). Force X11 ozone for the GUI only.
_harden_mullvad_desktop() {
  local sys_desk="/usr/share/applications/mullvad-vpn.desktop"
  local user_desk="$HOME/.local/share/applications/mullvad-vpn.desktop"
  local auto_desk="$HOME/.config/autostart/mullvad-vpn.desktop"
  if [[ ! -f "$sys_desk" ]] && ! dpkg -s mullvad-vpn >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$HOME/.local/share/applications" "$HOME/.config/autostart"

  local base=""
  if [[ -f "$sys_desk" ]]; then
    base="$sys_desk"
  elif [[ -f "$user_desk" ]]; then
    base="$user_desk"
  else
    # Minimal override if package desktop is missing
    cat >"$user_desk" <<'EOF'
[Desktop Entry]
Name=Mullvad VPN
Exec=env ELECTRON_OZONE_PLATFORM_HINT=x11 mullvad-gui
Type=Application
Categories=Network;
Icon=mullvad-vpn
EOF
    ok "Mullvad desktop override created (Wayland GPU hint)"
    return 0
  fi

  install -m 0644 "$base" "$user_desk"
  # Rewrite Exec= lines to prefix the ozone hint (idempotent).
  if grep -qE '^Exec=' "$user_desk"; then
    if ! grep -q 'ELECTRON_OZONE_PLATFORM_HINT=x11' "$user_desk"; then
      sed -i 's|^Exec=\(.*\)|Exec=env ELECTRON_OZONE_PLATFORM_HINT=x11 \1|' "$user_desk"
    fi
  fi
  # Prefer minimized start when the stock entry uses it; leave other args intact.
  if [[ -f "$auto_desk" ]] || grep -qiE 'X-GNOME-Autostart|Autostart' "$sys_desk" 2>/dev/null; then
    install -m 0644 "$user_desk" "$auto_desk"
    # Ensure autostart still launches the GUI (some packs use Hidden=true).
    sed -i '/^Hidden=/d' "$auto_desk" 2>/dev/null || true
  fi
  # Also write autostart override so session start gets the same env.
  if [[ ! -f "$auto_desk" ]] && [[ -f "$user_desk" ]]; then
    install -m 0644 "$user_desk" "$auto_desk"
  fi
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "Mullvad GUI launcher uses ELECTRON_OZONE_PLATFORM_HINT=x11"
}

module_updates() {
  log "installing X47 Updates"
  _install_updates_bin
  _install_updates_desktop
  _install_tidy_timer
  _repair_mullvad_apt_source
  _harden_mullvad_desktop
}

module_updates
