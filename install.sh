#!/usr/bin/env bash
# X47 Ubuntu 26 Custom Build installer
#
# Reproduces: WezTerm (default) + X47 watermark, pentest/dev toolchain,
# custom icons + launchers, and hardened services from a snapshot of the
# reference machine.
#
# Usage:
#   ./install.sh                  # full install (needs sudo for apt + hardening)
#   ./install.sh --user-only      # skip apt + hardening (tools/icons/terminal only)
#   ./install.sh --skip-apt       # skip apt repos/packages
#   ./install.sh --skip-hardening # skip ufw/fail2ban/sysctl restore
#   ./install.sh --skip-debloat   # keep language packs + default desktop apps
#   ./install.sh --skip-perf      # skip boot/service perf tweaks + Firefox deb swap
#   ./install.sh --skip-desktop-fx # skip tiling / wallpapers / desktop FX
#   ./install.sh --desktop-mode both|visual|performance
#       both (default/recommended): install Visual + Performance; start Performance;
#       toggle anytime from the top-bar chip. visual / performance = that stack only.
#   ./install.sh --skip-putty-clipboard  # classic terminal clipboard (no PuTTY mouse/Ctrl+C/V)
#   ./install.sh --skip-win-screenshot   # no Super+Shift+S (Print still works)
#   ./install.sh --with-amnesia   # also create the amnesiac Tor-forced 'anon' user
#   ./install.sh --only 10-terminal,30-icons
#
# Optional features default ON and can be changed later with: x47-settings
# Desktop: Performance (lean) vs Visual (cube/dock/animations); switch via top bar.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

X47_SKIP_APT=0
X47_SKIP_HARDENING=0
X47_SKIP_DEBLOAT=0
X47_SKIP_PERF=0
X47_SKIP_DESKTOP_FX=0
X47_USER_ONLY=0
X47_WITH_AMNESIA=0
X47_PUTTY_CLIPBOARD=1
X47_WIN_SCREENSHOT=1
# Empty = interactive chooser (defaults to both). Or pass --desktop-mode …
X47_DESKTOP_MODE="${X47_DESKTOP_MODE:-}"
X47_ONLY=""

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-apt) X47_SKIP_APT=1; shift ;;
    --skip-hardening) X47_SKIP_HARDENING=1; shift ;;
    --skip-debloat) X47_SKIP_DEBLOAT=1; shift ;;
    --skip-perf) X47_SKIP_PERF=1; shift ;;
    --skip-desktop-fx) X47_SKIP_DESKTOP_FX=1; shift ;;
    --desktop-mode)
      X47_DESKTOP_MODE="${2:-}"
      [[ -n "$X47_DESKTOP_MODE" ]] || die "--desktop-mode needs both|visual|performance"
      shift 2
      ;;
    --skip-putty-clipboard) X47_PUTTY_CLIPBOARD=0; shift ;;
    --with-putty-clipboard) X47_PUTTY_CLIPBOARD=1; shift ;;
    --skip-win-screenshot) X47_WIN_SCREENSHOT=0; shift ;;
    --with-win-screenshot) X47_WIN_SCREENSHOT=1; shift ;;
    --user-only) X47_USER_ONLY=1; X47_SKIP_APT=1; X47_SKIP_HARDENING=1; shift ;;
    --with-amnesia) X47_WITH_AMNESIA=1; shift ;;
    --skip-amnesia) X47_WITH_AMNESIA=0; shift ;;
    --only) X47_ONLY="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
done

# Resolve desktop mode early so modules see a concrete value.
# shellcheck disable=SC1091
. "$X47_ROOT/lib/desktop-mode.sh"
if [[ "${X47_SKIP_DESKTOP_FX:-0}" != "1" ]]; then
  X47_DESKTOP_MODE="$(x47_choose_desktop_mode)"
else
  X47_DESKTOP_MODE="$(x47_normalize_desktop_mode "${X47_DESKTOP_MODE:-performance}" || echo performance)"
fi

export X47_SKIP_APT X47_SKIP_HARDENING X47_SKIP_DEBLOAT X47_SKIP_PERF X47_SKIP_DESKTOP_FX \
  X47_USER_ONLY X47_WITH_AMNESIA X47_PUTTY_CLIPBOARD X47_WIN_SCREENSHOT X47_DESKTOP_MODE

MODULES=(
  00-apt.sh
  05-debloat.sh
  06-perf.sh
  09-settings.sh
  10-terminal.sh
  11-tor-browser.sh
  12-firefox-hardening.sh
  20-tools-go.sh
  21-tools-pipx.sh
  22-tools-cargo.sh
  23-tools-release.sh
  30-icons.sh
  31-launchers.sh
  40-hardening.sh
  50-gnome.sh
  51-desktop-fx.sh
  52-widgets.sh
  60-amnesia.sh
)

should_run() {
  local mod="$1"
  if [[ -z "$X47_ONLY" ]]; then
    return 0
  fi
  # Match by module name or numeric prefix
  local item
  IFS=',' read -ra _only <<< "$X47_ONLY"
  for item in "${_only[@]}"; do
    item="${item// /}"
    [[ -z "$item" ]] && continue
    if [[ "$mod" == *"$item"* ]]; then
      return 0
    fi
  done
  return 1
}

log "X47 Ubuntu Custom Build installer"
log "repo: $X47_ROOT"
log "home: $HOME"
log "desktop mode: ${X47_DESKTOP_MODE} (toggle via top-bar chip when both installed)"
bootstrap_path
ensure_bashrc_path

# Preconditions
[[ -d "$X47_ROOT/assets" ]] || die "assets/ missing — clone a complete repo or run snapshot.sh"
[[ -d "$X47_ROOT/modules" ]] || die "modules/ missing"

FAILED=()
for mod in "${MODULES[@]}"; do
  should_run "$mod" || { log "skip $mod (--only filter)"; continue; }
  local_path="$X47_ROOT/modules/$mod"
  [[ -f "$local_path" ]] || { fail "missing module $mod"; FAILED+=("$mod"); continue; }
  log "========== $mod =========="
  # Modules source common.sh themselves; run in a subshell so one failure
  # doesn't abort the whole install (we collect failures).
  set +e
  bash "$local_path"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    fail "$mod exited $rc"
    FAILED+=("$mod")
  fi
done

echo
if ((${#FAILED[@]} > 0)); then
  warn "finished with failures: ${FAILED[*]}"
  warn "re-run with --only <module> to retry, or check logs above"
  exit 1
fi

ok "X47 build install complete"
log "Log out and back in (or reboot) so GNOME picks up new launchers/icons."
log "Open WezTerm to confirm the X47 watermark on the right."
