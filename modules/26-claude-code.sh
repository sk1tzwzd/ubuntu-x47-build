#!/usr/bin/env bash
# Install official Claude Code CLI + Dev Tools launcher.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

_install_claude_icon() {
  local dest_base="$HOME/.local/share/icons/hicolor"
  local svg="$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-claude.svg"
  [[ -f "$svg" ]] || { warn "missing $svg"; return 0; }
  mkdir -p "$dest_base/scalable/apps"
  install -m 0644 "$svg" "$dest_base/scalable/apps/x47-claude.svg"
  local sz
  for sz in 128 256; do
    local png="$X47_ROOT/assets/icons/hicolor/${sz}x${sz}/apps/x47-claude.png"
    if [[ -f "$png" ]]; then
      mkdir -p "$dest_base/${sz}x${sz}/apps"
      install -m 0644 "$png" "$dest_base/${sz}x${sz}/apps/x47-claude.png"
    fi
  done
  if have gtk-update-icon-cache; then
    gtk-update-icon-cache -f -t "$dest_base" >/dev/null 2>&1 || true
  fi
  ok "Claude Code icon installed"
}

_install_claude_desktop() {
  local src="$X47_ROOT/assets/applications/launcher-claude.desktop"
  local dest="$HOME/.local/share/applications/launcher-claude.desktop"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  path_expand "$src" "$dest"
  chmod 0644 "$dest"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "Claude Code launcher → $dest"
}

_add_claude_to_devtools() {
  have gsettings || return 0
  python3 - <<'PY'
import ast, subprocess, sys
schema = "org.gnome.desktop.app-folders.folder"
path = "/org/gnome/desktop/app-folders/folders/DevTools/"
key = f"{schema}:{path}"
try:
    raw = subprocess.check_output(["gsettings", "get", key, "apps"], text=True).strip()
except subprocess.CalledProcessError:
    sys.exit(0)
apps = ast.literal_eval(raw.replace("@as ", "") or "[]")
if "launcher-claude.desktop" in apps:
    sys.exit(0)
if "antigravity-ide.desktop" in apps:
    idx = apps.index("antigravity-ide.desktop") + 1
elif "cursor.desktop" in apps:
    idx = apps.index("cursor.desktop") + 1
else:
    idx = len(apps)
apps.insert(idx, "launcher-claude.desktop")
formatted = "[" + ", ".join(f"'{a}'" for a in apps) + "]"
subprocess.check_call(["gsettings", "set", key, "apps", formatted])
print("added")
PY
  ok "Claude Code added to Dev Tools"
}

_install_claude_bin() {
  bootstrap_path
  if have claude; then
    log "updating Claude Code CLI"
    claude update >/dev/null 2>&1 || true
    ok "Claude Code CLI: $(claude --version 2>/dev/null || echo claude)"
    return 0
  fi
  log "installing official Claude Code CLI"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL https://claude.ai/install.sh -o "$tmp"; then
    rm -f "$tmp"
    warn "Claude Code installer download failed"
    return 1
  fi
  if ! bash "$tmp"; then
    rm -f "$tmp"
    warn "Claude Code installer failed — retry: curl -fsSL https://claude.ai/install.sh | bash"
    return 1
  fi
  rm -f "$tmp"
  hash -r 2>/dev/null || true
  if have claude; then
    ok "Claude Code → $(command -v claude)"
  else
    warn "installer finished but claude is not on PATH yet (open a new terminal)"
  fi
}

_install_vscode_claude() {
  have code || { warn "VS Code (code) not on PATH — skip Claude Code extension"; return 0; }
  log "installing Claude Code extension in VS Code"
  if code --install-extension anthropic.claude-code --force >/dev/null 2>&1; then
    ok "VS Code extension anthropic.claude-code"
  else
    warn "could not install anthropic.claude-code — in VS Code: Extensions → Claude Code"
  fi
}

_harden_code_desktop() {
  # Wayland + AMD: Electron GPU flakes. Same ozone hint as Mullvad.
  # Keep ~/.local/bin on PATH so the Claude Code extension finds `claude`.
  local sys dest prefix
  prefix="env PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin ELECTRON_OZONE_PLATFORM_HINT=x11 "
  mkdir -p "$HOME/.local/share/applications"
  local name
  for name in code.desktop code-url-handler.desktop; do
    sys="/usr/share/applications/${name}"
    dest="$HOME/.local/share/applications/${name}"
    [[ -f "$sys" ]] || continue
    install -m 0644 "$sys" "$dest"
    sed -i "s|^Exec=|Exec=${prefix}|" "$dest"
  done
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  if have xdg-mime && [[ -f "$HOME/.local/share/applications/code-url-handler.desktop" ]]; then
    xdg-mime default code-url-handler.desktop x-scheme-handler/vscode 2>/dev/null || true
  fi
  ok "VS Code launcher uses PATH + ELECTRON_OZONE_PLATFORM_HINT=x11"
}

module_claude_code() {
  if [[ "${X47_SKIP_CLAUDE:-0}" == "1" ]]; then
    warn "skipping Claude Code (X47_SKIP_CLAUDE=1)"
    return 0
  fi
  log "installing Claude Code"
  _install_claude_bin || true
  _install_claude_icon
  _install_claude_desktop
  _add_claude_to_devtools
  _harden_code_desktop
  _install_vscode_claude
}

module_claude_code
