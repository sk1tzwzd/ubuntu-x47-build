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
  # Disable the socket too (the service Requires= it, so socket activation
  # restarts the daemon) and mask both so package updates cannot re-enable
  # them — an update did exactly that and the daemon crept back to ~1 GB RSS.
  run_sudo systemctl disable --now clamav-daemon.service clamav-daemon.socket >/dev/null 2>&1 || true
  run_sudo systemctl mask clamav-daemon.service clamav-daemon.socket >/dev/null 2>&1 || true
  ok "clamav-daemon+socket off and masked, freshclam kept (scan: clamscan -r <dir>; undo: sudo systemctl unmask --now clamav-daemon.service clamav-daemon.socket && sudo systemctl enable --now clamav-daemon)"
}

# --- 5. kdump ---------------------------------------------------------------
disable_kdump() {
  log "disabling kdump-tools (frees reserved crash-kernel RAM)"
  run_sudo systemctl disable --now kdump-tools.service >/dev/null 2>&1 || true
  # Disabling the service is not enough: /etc/default/grub.d/kdump-tools.cfg
  # keeps injecting crashkernel= into the kernel cmdline, permanently
  # reserving RAM (512 MB on a 16 GB machine). Ship a later-sorting drop-in
  # that strips it — this survives kdump-tools package updates too.
  local dropin=/etc/default/grub.d/zz-x47-no-crashkernel.cfg
  if [[ -d /etc/default/grub.d ]] && [[ ! -f "$dropin" ]]; then
    run_sudo tee "$dropin" >/dev/null <<'EOF'
# X47: kdump-tools is disabled — do not reserve crash-kernel RAM.
# Remove this file and run update-grub to get kdump reservations back.
GRUB_CMDLINE_LINUX_DEFAULT="$(echo "$GRUB_CMDLINE_LINUX_DEFAULT" | sed -E 's/\bcrashkernel=[^ ]*//g;s/  +/ /g')"
EOF
    run_sudo update-grub >/dev/null 2>&1 || run_sudo grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || warn "update-grub failed"
  fi
  ok "kdump-tools disabled, crashkernel reservation dropped from GRUB (takes effect next reboot; undo: sudo rm $dropin && sudo systemctl enable --now kdump-tools && sudo update-grub)"
}

# --- 5b. journald size cap ---------------------------------------------------
journald_cap() {
  # A one-shot vacuum does not hold — without SystemMaxUse the journal grows
  # back (observed at 800 MB). Persist the cap.
  local dropin=/etc/systemd/journald.conf.d/x47-journal.conf
  log "capping systemd journal at 200M ($dropin)"
  run_sudo mkdir -p /etc/systemd/journald.conf.d
  run_sudo tee "$dropin" >/dev/null <<'EOF'
# X47: keep the persistent journal bounded.
[Journal]
SystemMaxUse=200M
EOF
  run_sudo systemctl try-restart systemd-journald >/dev/null 2>&1 || true
  ok "journal capped at 200M (undo: sudo rm $dropin && sudo systemctl restart systemd-journald)"
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
  journald_cap
  disable_cloudinit
  disable_printing

  ok "perf module done"
}

module_perf "$@"
