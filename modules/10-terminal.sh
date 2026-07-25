#!/usr/bin/env bash
# Install WezTerm AppImage, X47 watermark, and set as default terminal.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

WEZTERM_VERSION="${WEZTERM_VERSION:-20240203-110809-5046fc22}"
WEZTERM_URL="${WEZTERM_URL:-https://github.com/wez/wezterm/releases/download/${WEZTERM_VERSION}/WezTerm-${WEZTERM_VERSION}-Ubuntu20.04.AppImage}"

module_terminal() {
  bootstrap_path
  local tools="$HOME/tools/wezterm"
  mkdir -p "$tools" "$HOME/.local/bin" "$HOME/.config/wezterm" "$HOME/.config/wzd" \
    "$HOME/.local/share/applications" "$HOME/.config"

  # Download AppImage if missing
  if [[ ! -x "$tools/wezterm.AppImage" ]]; then
    log "downloading WezTerm AppImage"
    download "$WEZTERM_URL" "$tools/wezterm.AppImage"
    chmod +x "$tools/wezterm.AppImage"
  else
    log "WezTerm AppImage already present"
  fi

  # Extract for FUSE-less environments
  if [[ ! -x "$tools/squashfs-root/AppRun" ]]; then
    log "extracting WezTerm AppImage"
    (cd "$tools" && ./wezterm.AppImage --appimage-extract >/dev/null)
  fi

  # Wrapper
  cat > "$HOME/.local/bin/wezterm" <<EOF
#!/usr/bin/env bash
exec "$tools/squashfs-root/AppRun" "\$@"
EOF
  chmod +x "$HOME/.local/bin/wezterm"
  ok "wezterm wrapper -> ~/.local/bin/wezterm"

  # Config + watermark (Lua resolves HOME via os.getenv)
  if [[ -f "$X47_ROOT/assets/wezterm/wezterm.lua" ]]; then
    cp -a "$X47_ROOT/assets/wezterm/wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
  fi
  for f in banner.txt watermark.png ascii-art.txt; do
    [[ -f "$X47_ROOT/assets/wzd/$f" ]] && cp -a "$X47_ROOT/assets/wzd/$f" "$HOME/.config/wzd/"
  done

  # Desktop entry
  if [[ -f "$X47_ROOT/assets/wezterm/org.wezfurlong.wezterm.desktop" ]]; then
    path_expand \
      "$X47_ROOT/assets/wezterm/org.wezfurlong.wezterm.desktop" \
      "$HOME/.local/share/applications/org.wezfurlong.wezterm.desktop"
  else
    cat > "$HOME/.local/share/applications/org.wezfurlong.wezterm.desktop" <<EOF
[Desktop Entry]
Name=WezTerm
Comment=Wez's Terminal Emulator
Keywords=shell;prompt;command;commandline;cmd;terminal;
Icon=org.wezfurlong.wezterm
StartupWMClass=org.wezfurlong.wezterm
TryExec=$HOME/.local/bin/wezterm
Exec=$HOME/.local/bin/wezterm start --cwd .
Type=Application
Categories=System;TerminalEmulator;Utility;
Terminal=false
EOF
  fi

  # WezTerm icon
  if [[ -f "$tools/squashfs-root/org.wezfurlong.wezterm.png" ]]; then
    local idir="$HOME/.local/share/icons/hicolor/128x128/apps"
    mkdir -p "$idir"
    cp -a "$tools/squashfs-root/org.wezfurlong.wezterm.png" "$idir/"
  fi

  # Default terminal (XDG + gsettings)
  echo "org.wezfurlong.wezterm.desktop" > "$HOME/.config/xdg-terminals.list"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  if have xdg-mime; then
    xdg-mime default org.wezfurlong.wezterm.desktop x-scheme-handler/terminal 2>/dev/null || true
  fi
  if have gsettings; then
    gsettings set org.gnome.desktop.default-applications.terminal exec "$HOME/.local/bin/wezterm" 2>/dev/null || true
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg 'start' 2>/dev/null || true
  fi

  ok "WezTerm installed and set as default terminal"
}

module_terminal "$@"
