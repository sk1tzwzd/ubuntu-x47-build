#!/usr/bin/env bash
# Add third-party apt repos and install the filtered apt-manual package set.
# Requires sudo. Idempotent.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_apt() {
  if [[ "${X47_SKIP_APT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "skipping apt module"
    return 0
  fi
  need_sudo || die "00-apt.sh needs sudo"

  log "updating apt indexes"
  run_sudo apt-get update -qq

  # Base tooling needed for the rest of the installer
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    apt-transport-https unzip jq git build-essential pkg-config \
    python3 python3-pip python3-venv python3-dev pipx \
    golang-go ruby-dev \
    >/dev/null

  local codename
  codename="$(. /etc/os-release; echo "${VERSION_CODENAME:-noble}")"
  local arch_name
  arch_name="$(dpkg --print-architecture)"

  # --- Docker ---
  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    log "adding Docker apt repo"
    run_sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | run_sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    run_sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=${arch_name} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
      | run_sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  fi

  # --- GitHub CLI ---
  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]] && [[ ! -f /usr/share/keyrings/githubcli-archive-keyring.gpg ]]; then
    log "adding GitHub CLI apt repo"
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | run_sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
    run_sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=${arch_name} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | run_sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  fi

  # --- Google Chrome ---
  if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]] && [[ ! -f /etc/apt/sources.list.d/google-chrome.sources ]]; then
    log "adding Google Chrome apt repo"
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | run_sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      | run_sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  fi

  # --- VS Code ---
  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    log "adding VS Code apt repo"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | run_sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
    echo "deb [arch=${arch_name} signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      | run_sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  fi

  # --- Mullvad VPN (optional; ignore failures) ---
  if [[ ! -f /etc/apt/sources.list.d/mullvad.list ]]; then
    log "adding Mullvad apt repo (optional)"
    local mullvad_suite="$codename"
    # New Ubuntu series often land before Mullvad publishes a matching suite.
    if ! curl -fsSIL "https://repository.mullvad.net/deb/stable/dists/${mullvad_suite}/Release" >/dev/null 2>&1; then
      mullvad_suite="noble"
      warn "Mullvad has no ${codename} suite — using ${mullvad_suite}"
    fi
    if curl -fsSL https://repository.mullvad.net/deb/mullvad-keyring.asc \
      | run_sudo tee /usr/share/keyrings/mullvad-keyring.asc >/dev/null 2>&1; then
      echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=${arch_name}] https://repository.mullvad.net/deb/stable ${mullvad_suite} main" \
        | run_sudo tee /etc/apt/sources.list.d/mullvad.list >/dev/null || true
    else
      warn "Mullvad key download failed — skipping repo"
    fi
  fi

  run_sudo apt-get update -qq

  # Packages to install from the snapshot manifest (skip unavailable ones)
  local manifest="$X47_ROOT/assets/manifests/apt-manual.txt"
  [[ -f "$manifest" ]] || die "missing $manifest — run snapshot.sh first"

  # Skip packages that are third-party / may not resolve on a fresh box
  # (cursor, metasploit may need their own repos; we try them and ignore failures)
  local -a pkgs=()
  local p
  while IFS= read -r p; do
    [[ -z "$p" || "$p" =~ ^# ]] && continue
    # Skip Cursor (proprietary installer, not in apt by default)
    [[ "$p" == "cursor" ]] && continue
    pkgs+=("$p")
  done < "$manifest"

  log "installing ${#pkgs[@]} apt packages (best-effort)"
  # Install in chunks so one missing package doesn't abort the whole set
  local -a chunk=()
  local i=0
  for p in "${pkgs[@]}"; do
    chunk+=("$p")
    i=$((i + 1))
    if (( i % 25 == 0 )); then
      run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${chunk[@]}" \
        || warn "some packages in chunk failed: ${chunk[*]}"
      chunk=()
    fi
  done
  if ((${#chunk[@]} > 0)); then
    run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${chunk[@]}" \
      || warn "some packages in final chunk failed: ${chunk[*]}"
  fi

  # Hardening packages (ensure present even if filtered from manifest)
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ufw fail2ban apparmor auditd unattended-upgrades \
    rkhunter chkrootkit lynis \
    >/dev/null || warn "some hardening packages failed"

  # Ensure pipx path for the invoking user
  if [[ "$(id -u)" -ne 0 ]]; then
    pipx ensurepath >/dev/null 2>&1 || true
  fi

  ok "apt module done"
}

module_apt "$@"
