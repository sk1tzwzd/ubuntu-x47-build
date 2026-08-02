#!/usr/bin/env bash
# Trim the fat: remove non-English language packs and default desktop bloat,
# clean caches, and apply light performance tweaks (zram, trim, no file indexer).
# Aggressive but reversible (apt-get install <pkg> to restore). Requires sudo.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Never remove these, even if they appear in a computed list.
X47_DEBLOAT_DENYLIST=(
  gnome-shell gdm3 nautilus network-manager network-manager-gnome
  snapd firefox mutter ubuntu-session ubuntu-desktop-minimal
  gnome-control-center gnome-terminal xserver-xorg xwayland
  gnome-settings-daemon gvfs policykit-1 sudo
)

# Aggressive default-app removals (best-effort; each ignored if absent).
X47_DEBLOAT_APPS=(
  aisleriot gnome-mahjongg gnome-mines gnome-sudoku gnome-2048
  five-or-more four-in-a-row hitori iagno lightsoff quadrapassel
  swell-foop tali gnome-nibbles gnome-robots gnome-tetravex
  gnome-klotski gnome-chess
  rhythmbox cheese thunderbird
  transmission-gtk transmission-common remmina
  shotwell gnome-maps gnome-weather gnome-contacts gnome-todo
  simple-scan totem gnome-music gnome-photos
)

is_denied() {
  local p="$1" d
  for d in "${X47_DEBLOAT_DENYLIST[@]}"; do
    [[ "$p" == "$d" ]] && return 0
  done
  return 1
}

purge_pkgs() {
  # Purge a list, filtering the denylist. Best-effort per chunk.
  local -a keep=()
  local p
  for p in "$@"; do
    is_denied "$p" && { warn "keeping protected pkg: $p"; continue; }
    keep+=("$p")
  done
  ((${#keep[@]})) || return 0
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq "${keep[@]}" \
    >/dev/null 2>&1 || warn "some packages were not installed / not purged"
}

remove_language_packs() {
  log "removing non-English language packs and localisations"
  local -a langs=()
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    # keep anything English (…-en, …-en-base, …-en-*)
    [[ "$p" =~ (^|-)en(-|$) ]] && continue
    langs+=("$p")
  done < <(dpkg-query -W -f='${Package}\n' \
             'language-pack-*' 'language-pack-gnome-*' \
             'libreoffice-l10n-*' 'libreoffice-help-*' \
             'hunspell-*' 'aspell-*' 'mythes-*' 'wbritish' 2>/dev/null \
           | grep -vE '(^|-)en(-|$)' || true)
  if ((${#langs[@]})); then
    log "purging ${#langs[@]} localisation packages"
    purge_pkgs "${langs[@]}"
  else
    log "no extra language packs found"
  fi
}

remove_desktop_apps() {
  log "removing default desktop apps (games, mail, office, media)"
  # libreoffice as a family (metapackages + parts), guarded by denylist filter
  local -a office=()
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] && office+=("$p")
  done < <(dpkg-query -W -f='${Package}\n' 'libreoffice*' 2>/dev/null || true)
  purge_pkgs "${X47_DEBLOAT_APPS[@]}" "${office[@]}"
}

cleanup_system() {
  log "autoremoving orphans and clearing caches"
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y -qq >/dev/null 2>&1 || true
  run_sudo apt-get clean >/dev/null 2>&1 || true
  run_sudo journalctl --vacuum-size=200M >/dev/null 2>&1 || true
  rm -rf "$HOME/.cache/thumbnails/"* 2>/dev/null || true
}

perf_tweaks() {
  log "applying performance tweaks (zram, trim, swappiness, indexer off)"

  # SSD periodic TRIM
  run_sudo systemctl enable --now fstrim.timer >/dev/null 2>&1 || true

  # Compressed RAM swap (better than disk swap under pressure)
  run_sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zram-config >/dev/null 2>&1 \
    || warn "zram-config not available"
  run_sudo systemctl enable --now zram-config.service >/dev/null 2>&1 || true

  # Lower swappiness so we lean on RAM first
  echo 'vm.swappiness=10' | run_sudo tee /etc/sysctl.d/99-x47-swappiness.conf >/dev/null
  run_sudo sysctl --system >/dev/null 2>&1 || true

  # Disable the desktop file indexer for the invoking user (big idle-CPU win).
  # Service names differ across releases (tracker3 vs localsearch); mask both.
  if [[ "$(id -u)" -ne 0 ]]; then
    local svc
    for svc in tracker-miner-fs-3 tracker-miner-rss-3 tracker-extract-3 \
               localsearch-3 localsearch-control-3; do
      systemctl --user mask "${svc}.service" >/dev/null 2>&1 || true
    done
    tracker3 reset --filesystem >/dev/null 2>&1 || true
  fi
}

module_debloat() {
  if [[ "${X47_SKIP_DEBLOAT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]] \
     || [[ "${X47_SKIP_APT:-0}" == "1" ]]; then
    warn "skipping debloat module"
    return 0
  fi
  need_sudo || die "05-debloat.sh needs sudo"

  remove_language_packs
  remove_desktop_apps
  cleanup_system
  perf_tweaks

  ok "debloat module done (reverse anything with: sudo apt-get install <pkg>)"
}

module_debloat "$@"
