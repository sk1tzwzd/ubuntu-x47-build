#!/usr/bin/env bash
# Performance pass: trim boot time and idle resource use on the installed
# system. Everything here is reversible (each step prints how to undo it).
# Requires sudo. Opt out with --skip-perf.
#
# Steps:
#   1. Stop chkrootkit + bettercap running at boot (kept; run on demand)
#   2. Cut the GRUB menu timeout to 1s and hide it
#   3. Mask ModemManager (no cellular modem -> no serial-port probe stalls)
#   4. Switch ClamAV from a resident daemon to on-demand scans (frees ~1 GB RAM)
#   5. Disable kdump-tools (frees reserved crash-kernel RAM)
#   6. Disable cloud-init on the installed system (it is only needed at install)
#   7. Disable the printing/discovery stack (cups, cups-browsed, avahi)
#   8. Replace the Firefox snap with the Mozilla .deb (faster launch, less RAM)
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# --- 1. heavy pentest tools off the boot path -------------------------------
disable_boot_services() {
  log "stopping chkrootkit + bettercap from running at every boot"
  local svc
  for svc in chkrootkit.service bettercap.service; do
    run_sudo systemctl disable --now "$svc" >/dev/null 2>&1 || true
  done
  ok "chkrootkit/bettercap off at boot (re-enable: sudo systemctl enable --now <svc>)"
}

# --- 2. GRUB timeout --------------------------------------------------------
grub_timeout() {
  local f=/etc/default/grub
  [[ -f "$f" ]] || { warn "no $f — skipping GRUB timeout"; return 0; }
  log "cutting GRUB timeout to 1s and hiding the menu"
  set_grub_key() {
    local key="$1" val="$2"
    if grep -qE "^\s*${key}=" "$f"; then
      run_sudo sed -i "s|^\s*${key}=.*|${key}=${val}|" "$f"
    else
      printf '%s=%s\n' "$key" "$val" | run_sudo tee -a "$f" >/dev/null
    fi
  }
  set_grub_key GRUB_TIMEOUT 1
  set_grub_key GRUB_TIMEOUT_STYLE hidden
  run_sudo update-grub >/dev/null 2>&1 || run_sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || warn "update-grub failed"
  ok "GRUB timeout set (undo: edit $f, restore GRUB_TIMEOUT, run sudo update-grub)"
}

# --- 3. ModemManager --------------------------------------------------------
mask_modemmanager() {
  log "masking ModemManager (no cellular modem present)"
  run_sudo systemctl disable --now ModemManager.service >/dev/null 2>&1 || true
  run_sudo systemctl mask ModemManager.service >/dev/null 2>&1 || true
  ok "ModemManager masked (undo: sudo systemctl unmask --now ModemManager)"
}

# --- 4. ClamAV on-demand ----------------------------------------------------
clamav_ondemand() {
  if ! systemctl list-unit-files 2>/dev/null | grep -q '^clamav-daemon'; then
    log "clamav-daemon not present — skipping"
    return 0
  fi
  log "switching ClamAV to on-demand (stopping the resident daemon)"
  # Keep freshclam so signatures stay current for manual clamscan runs.
  run_sudo systemctl disable --now clamav-daemon.service >/dev/null 2>&1 || true
  ok "clamav-daemon off, freshclam kept (scan on demand: clamscan -r <dir>; undo: sudo systemctl enable --now clamav-daemon)"
}

# --- 5. kdump ---------------------------------------------------------------
disable_kdump() {
  log "disabling kdump-tools (frees reserved crash-kernel RAM)"
  run_sudo systemctl disable --now kdump-tools.service >/dev/null 2>&1 || true
  ok "kdump-tools disabled (undo: sudo systemctl enable --now kdump-tools)"
}

# --- 6. cloud-init ----------------------------------------------------------
disable_cloudinit() {
  if ! have cloud-init && [[ ! -d /etc/cloud ]]; then
    log "cloud-init not present — skipping"
    return 0
  fi
  log "disabling cloud-init on the installed system"
  run_sudo mkdir -p /etc/cloud
  run_sudo touch /etc/cloud/cloud-init.disabled
  ok "cloud-init disabled (undo: sudo rm /etc/cloud/cloud-init.disabled)"
}

# --- 7. printing / discovery ------------------------------------------------
disable_printing() {
  log "disabling the printing/discovery stack (cups, cups-browsed, avahi)"
  local svc
  for svc in cups.service cups-browsed.service cups.socket avahi-daemon.service avahi-daemon.socket; do
    run_sudo systemctl disable --now "$svc" >/dev/null 2>&1 || true
  done
  ok "printing/discovery off (undo: sudo systemctl enable --now cups cups-browsed avahi-daemon)"
}

# --- 8. Firefox snap -> Mozilla .deb ---------------------------------------
firefox_snap_to_deb() {
  if ! have snap || ! snap list firefox >/dev/null 2>&1; then
    log "no Firefox snap present — skipping snap->deb swap"
    return 0
  fi
  log "replacing the Firefox snap with the Mozilla .deb"

  # Migrate the snap profile into the standard location BEFORE removing snap,
  # so bookmarks/history/userChrome survive.
  local snap_moz="$HOME/snap/firefox/common/.mozilla"
  if [[ -d "$snap_moz" && ! -d "$HOME/.mozilla" ]]; then
    log "migrating Firefox profile from the snap into ~/.mozilla"
    cp -a "$snap_moz" "$HOME/.mozilla" || warn "profile copy failed (continuing)"
  elif [[ -d "$snap_moz" ]]; then
    warn "~/.mozilla already exists — leaving it; snap profile at $snap_moz"
  fi

  # Mozilla APT repo (keyring + source + pin so apt wins over the snap shim).
  local key=/etc/apt/keyrings/packages.mozilla.org.asc
  run_sudo install -d -m 0755 /etc/apt/keyrings
  if curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg | run_sudo tee "$key" >/dev/null; then
    echo "deb [signed-by=$key] https://packages.mozilla.org/apt mozilla main" \
      | run_sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
      | run_sudo tee /etc/apt/preferences.d/mozilla >/dev/null
  else
    warn "could not fetch Mozilla signing key — keeping the snap"
    return 0
  fi

  run_sudo snap remove --purge firefox >/dev/null 2>&1 || warn "snap remove firefox failed"
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
  if run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq firefox >/dev/null 2>&1; then
    ok "Firefox .deb installed (profile migrated; undo: sudo apt purge firefox && sudo snap install firefox)"
  else
    warn "apt install firefox failed — reinstall the snap with: sudo snap install firefox"
  fi
}

module_perf() {
  if [[ "${X47_SKIP_PERF:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]] \
     || [[ "${X47_SKIP_APT:-0}" == "1" ]]; then
    warn "skipping perf module"
    return 0
  fi
  need_sudo || die "06-perf.sh needs sudo"

  disable_boot_services
  grub_timeout
  mask_modemmanager
  clamav_ondemand
  disable_kdump
  disable_cloudinit
  disable_printing
  firefox_snap_to_deb

  ok "perf module done"
}

module_perf "$@"
