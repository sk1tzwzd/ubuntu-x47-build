#!/usr/bin/env bash
# X47 first-boot setup: runs once per user on the first desktop login of a
# system installed from the X47 ISO. Opens a terminal running the installer
# (it needs an interactive sudo prompt), then stamps completion.
set -u

STAMP="$HOME/.config/x47-firstboot-done"
REPO="/opt/ubuntu-x47-build"

[ -e "$STAMP" ] && exit 0
[ -d "$REPO" ] || exit 0
mkdir -p "$HOME/.config"

run_install='
set -u
echo "==============================================";
echo "  X47 Ubuntu build — first boot setup";
echo "  This installs the terminal, tools, hardening,";
echo "  debloat and desktop. Sudo required.";
echo "==============================================";
cd /opt/ubuntu-x47-build || exit 1;

# Desktop mode chooser (Visual / High Performance / Both).
MODE=both
if command -v zenity >/dev/null 2>&1; then
  pick="$(zenity --list --radiolist \
    --title="X47 Desktop Mode" \
    --text="Choose the desktop experience to install:" \
    --column="Pick" --column="Mode" --column="Description" \
    --hide-column=2 --print-column=2 \
    --width=560 --height=280 \
    TRUE both "Both — Visual FX + High Performance (switch via Power settings)" \
    FALSE visual "Visual only — cube, dock, animations, full FX" \
    FALSE performance "High Performance only — lean desktop, no heavy FX" \
    2>/dev/null)" || pick=""
  [ -n "$pick" ] && MODE="$pick"
else
  echo "Desktop mode:";
  echo "  1) Both — Visual + High Performance (recommended)";
  echo "  2) Visual only";
  echo "  3) High Performance only";
  read -rp "Choice [1]: " ans || ans=1;
  case "${ans:-1}" in
    2) MODE=visual ;;
    3) MODE=performance ;;
    *) MODE=both ;;
  esac
fi
echo "Selected desktop mode: $MODE";

if ./install.sh --desktop-mode "$MODE"; then
  touch "$HOME/.config/x47-firstboot-done";
  echo;
  echo "Done. Log out and back in to load the desktop.";
  if [ "$MODE" = both ]; then
    echo "Tip: Settings → Power → Performance enables the High Performance desktop.";
  fi
else
  echo; echo "Install failed — run /opt/ubuntu-x47-build/install.sh again manually.";
fi;
read -rp "Press Enter to close...";
'

# Prefer WezTerm (build default); fall back to x-terminal-emulator.
if command -v wezterm >/dev/null 2>&1; then
  exec wezterm start -- bash -c "$run_install"
elif [[ -x "$HOME/.local/bin/wezterm" ]]; then
  exec "$HOME/.local/bin/wezterm" start -- bash -c "$run_install"
elif command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e bash -c "$run_install"
fi
exit 0
