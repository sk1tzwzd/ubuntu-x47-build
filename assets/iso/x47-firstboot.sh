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
echo "==============================================";
echo "  X47 Ubuntu build — first boot setup";
echo "  Terminal, tools, hardening, debloat, and";
echo "  desktop (Performance and/or Visual).";
echo "  You will be asked which desktop to install.";
echo "  Sudo required.";
echo "==============================================";
cd /opt/ubuntu-x47-build || exit 1;
if ./install.sh; then
  touch "$HOME/.config/x47-firstboot-done";
  echo; echo "Done. Log out and back in to load the desktop.";
  echo "Toggle Visual ↔ Performance from the top-bar chip (right).";
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
