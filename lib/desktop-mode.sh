# X47 desktop mode helpers (visual / performance / both).
# shellcheck shell=bash

# Heavy FX disabled in Performance mode.
X47_HEAVY_FX_UUIDS=(
  "CoverflowAltTab@palatis.blogspot.com"
  "desktop-cube@schneegans.github.com"
  "burn-my-windows@schneegans.github.com"
  "blur-my-shell@aunetx"
  "compiz-windows-effect@hermes83.github.com"
  "x47-ws-walls@x47"
)

# Always kept enabled in both modes (includes the top-bar mode toggle).
X47_LEAN_FX_UUIDS=(
  "tilingshell@ferrarodomenico.com"
  "x47-notif-activate@x47"
  "x47-show-apps@x47"
  "x47-desktop-mode@x47"
  "x47-display@x47"
)

X47_DOCK_UUIDS=(
  "ubuntu-dock@ubuntu.com"
  "dash-to-dock@micxgx.gmail.com"
)

# Normalize / validate a desktop-mode install choice.
x47_normalize_desktop_mode() {
  local m="${1:-both}"
  case "${m,,}" in
    visual|v|full|fx) echo visual ;;
    performance|perf|hp|high-performance|high_performance) echo performance ;;
    both|all) echo both ;;
    *) return 1 ;;
  esac
}

# Interactive chooser when X47_DESKTOP_MODE is unset. Defaults to both.
x47_choose_desktop_mode() {
  local cur="${X47_DESKTOP_MODE:-}"
  if [[ -n "$cur" ]]; then
    x47_normalize_desktop_mode "$cur" || {
      warn "invalid X47_DESKTOP_MODE='$cur' — using both"
      echo both
    }
    return 0
  fi

  local pick=""
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && have zenity; then
    pick="$(zenity --list --radiolist \
      --title='X47 Desktop Mode' \
      --text='Choose what to install. With Both you can switch from the top-bar chip anytime.' \
      --column='Pick' --column='Mode' --column='Description' \
      --hide-column=2 --print-column=2 \
      --width=620 --height=300 \
      TRUE both 'Both (recommended) — Visual + Performance; start lean; toggle in top bar' \
      FALSE visual 'Visual only — cube, animations, multi-colour desktops' \
      FALSE performance 'Performance only — lean desktop, no heavy FX' \
      2>/dev/null)" || pick=""
  elif [[ -t 0 ]] && have whiptail; then
    pick="$(whiptail --title 'X47 Desktop Mode' --radiolist \
      'Choose the desktop experience to install:' 16 74 3 \
      both 'Both Visual + Performance (toggle in top bar)' ON \
      visual 'Visual only' OFF \
      performance 'Performance only' OFF \
      3>&1 1>&2 2>&3)" || pick=""
  elif [[ -t 0 ]]; then
    echo "X47 Desktop Mode:" >&2
    echo "  1) Both — Visual + Performance; start Performance; toggle in top bar (recommended)" >&2
    echo "  2) Visual only — cube, animations, multi-colour desktops" >&2
    echo "  3) Performance only — lean desktop" >&2
    local ans
    read -rp "Choice [1]: " ans || ans=1
    case "${ans:-1}" in
      2) pick=visual ;;
      3) pick=performance ;;
      *) pick=both ;;
    esac
  fi

  if [[ -z "$pick" ]]; then
    pick=both
  fi
  x47_normalize_desktop_mode "$pick" || echo both
}

x47_seed_desktop_mode_settings() {
  # shellcheck disable=SC1091
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings.sh"
  local installed="${1:-both}" active="${2:-}"
  installed="$(x47_normalize_desktop_mode "$installed" || echo both)"
  case "$installed" in
    performance) active="${active:-performance}" ;;
    visual) active="${active:-visual}" ;;
    # Both: prefer Performance unless caller overrides.
    both) active="${active:-performance}" ;;
  esac
  active="$(x47_normalize_desktop_mode "$active" || echo performance)"
  if [[ "$installed" == "performance" ]]; then
    active=performance
  elif [[ "$installed" == "visual" ]]; then
    active=visual
  fi
  x47_settings_ensure
  x47_settings_set_str desktop_modes_installed "$installed"
  x47_settings_set_str desktop_mode "$active"
}
