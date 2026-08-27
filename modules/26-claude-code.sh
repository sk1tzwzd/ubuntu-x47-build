#!/usr/bin/env bash
# Claude Code in VS Code only — no standalone CLI (for now).
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

_remove_claude_cli() {
  rm -f "$HOME/.local/bin/claude"
  rm -rf "$HOME/.local/share/claude/versions"
  rm -f "$HOME/.local/share/applications/launcher-claude.desktop"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
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
if "launcher-claude.desktop" not in apps:
    sys.exit(0)
apps = [a for a in apps if a != "launcher-claude.desktop"]
formatted = "[" + ", ".join(f"'{a}'" for a in apps) + "]"
subprocess.check_call(["gsettings", "set", key, "apps", formatted])
print("removed-launcher")
PY
  ok "standalone Claude Code CLI removed"
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
  log "Claude Code: VS Code extension only (no standalone CLI)"
  _remove_claude_cli
  _harden_code_desktop
  _install_vscode_claude
}

module_claude_code
