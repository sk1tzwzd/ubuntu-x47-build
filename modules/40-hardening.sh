#!/usr/bin/env bash
# Restore captured ufw / fail2ban / sysctl / auditd / unattended-upgrades config.
# Requires sudo.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_hardening() {
  if [[ "${X47_SKIP_HARDENING:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "skipping hardening module"
    return 0
  fi
  need_sudo || die "40-hardening.sh needs sudo"

  local c="$X47_ROOT/config"

  # Ensure packages
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ufw fail2ban apparmor auditd unattended-upgrades \
    rkhunter chkrootkit lynis \
    >/dev/null || warn "some hardening packages failed to install"

  # UFW
  if [[ -f "$c/ufw/user.rules" ]]; then
    log "restoring UFW rules"
    run_sudo cp -a "$c/ufw/user.rules" /etc/ufw/user.rules
    [[ -f "$c/ufw/user6.rules" ]] && run_sudo cp -a "$c/ufw/user6.rules" /etc/ufw/user6.rules
    [[ -f "$c/ufw/ufw.conf" ]] && run_sudo cp -a "$c/ufw/ufw.conf" /etc/ufw/ufw.conf
    [[ -f "$c/ufw/default-ufw" ]] && run_sudo cp -a "$c/ufw/default-ufw" /etc/default/ufw
  fi
  run_sudo ufw --force enable || warn "ufw enable failed"
  run_sudo systemctl enable --now ufw || true

  # fail2ban
  if [[ -d "$c/fail2ban/jail.d" ]]; then
    log "restoring fail2ban jail.d"
    run_sudo mkdir -p /etc/fail2ban/jail.d
    run_sudo cp -a "$c/fail2ban/jail.d/." /etc/fail2ban/jail.d/
  fi
  [[ -f "$c/fail2ban/jail.local" ]] && \
    run_sudo cp -a "$c/fail2ban/jail.local" /etc/fail2ban/jail.local
  run_sudo systemctl enable --now fail2ban || true

  # sysctl
  if [[ -d "$c/sysctl.d" ]] && compgen -G "$c/sysctl.d/*" >/dev/null; then
    log "restoring sysctl.d"
    local f
    for f in "$c/sysctl.d"/*; do
      [[ -f "$f" ]] || continue
      run_sudo cp -a "$f" "/etc/sysctl.d/$(basename "$f")"
    done
    run_sudo sysctl --system >/dev/null 2>&1 || true
  fi

  # auditd
  if [[ -d "$c/audit/rules.d" ]] && compgen -G "$c/audit/rules.d/*" >/dev/null; then
    log "restoring audit rules"
    run_sudo mkdir -p /etc/audit/rules.d
    run_sudo cp -a "$c/audit/rules.d/." /etc/audit/rules.d/
    if have augenrules; then
      run_sudo augenrules --load >/dev/null 2>&1 || true
    fi
  fi
  run_sudo systemctl enable --now auditd || true

  # unattended-upgrades
  if [[ -d "$c/apt" ]]; then
    log "restoring unattended-upgrades apt config"
    [[ -f "$c/apt/50unattended-upgrades" ]] && \
      run_sudo cp -a "$c/apt/50unattended-upgrades" /etc/apt/apt.conf.d/
    [[ -f "$c/apt/20auto-upgrades" ]] && \
      run_sudo cp -a "$c/apt/20auto-upgrades" /etc/apt/apt.conf.d/
  fi
  run_sudo systemctl enable --now unattended-upgrades || true

  # AppArmor
  run_sudo systemctl enable --now apparmor || true

  ok "hardening module done"
}

module_hardening "$@"
