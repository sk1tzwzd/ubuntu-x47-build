#!/usr/bin/env bash
# Install free PDF editing stack + one X47 PDF front door + guide.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# Prefer a graphical password prompt when the session has a display.
_priv() {
  if [[ "$(id -u)" -eq 0 ]]; then
    env "$@"
    return
  fi
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && have pkexec; then
    pkexec env "$@"
    return
  fi
  run_sudo "$@"
}

_install_pdf_helper() {
  local src="$X47_ROOT/scripts/x47-pdf"
  local dest_dir="$HOME/.local/share/ubuntu-x47-build/bin"
  local link="$HOME/.local/bin/x47-pdf"
  [[ -f "$src" ]] || die "missing $src"
  mkdir -p "$dest_dir" "$HOME/.local/bin"
  install -m 0755 "$src" "$dest_dir/x47-pdf"
  ln -sfn "$dest_dir/x47-pdf" "$link"
  ok "x47-pdf → $link"
}

_install_pdf_guide() {
  local src="$X47_ROOT/assets/docs/x47-pdf-guide.html"
  local dest="$HOME/.local/share/ubuntu-x47-build/docs/x47-pdf-guide.html"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  ok "PDF guide → $dest"
}

_install_pdf_icon() {
  local dest_base="$HOME/.local/share/icons/hicolor"
  local svg="$X47_ROOT/assets/icons/hicolor/scalable/apps/x47-pdf.svg"
  [[ -f "$svg" ]] || { warn "missing $svg"; return 0; }
  mkdir -p "$dest_base/scalable/apps"
  install -m 0644 "$svg" "$dest_base/scalable/apps/x47-pdf.svg"
  local sz
  for sz in 128 256; do
    local png="$X47_ROOT/assets/icons/hicolor/${sz}x${sz}/apps/x47-pdf.png"
    if [[ -f "$png" ]]; then
      mkdir -p "$dest_base/${sz}x${sz}/apps"
      install -m 0644 "$png" "$dest_base/${sz}x${sz}/apps/x47-pdf.png"
    fi
  done
  if have gtk-update-icon-cache; then
    gtk-update-icon-cache -f -t "$dest_base" >/dev/null 2>&1 || true
  fi
  ok "X47 PDF icon installed"
}

_install_pdf_desktop() {
  local src="$X47_ROOT/assets/desktop/x47-pdf.desktop"
  local dest="$HOME/.local/share/applications/x47-pdf.desktop"
  [[ -f "$src" ]] || { warn "missing $src"; return 0; }
  mkdir -p "$(dirname "$dest")"
  install -m 0644 "$src" "$dest"
  sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/x47-pdf gui %F|" "$dest"
  if have update-desktop-database; then
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
  fi
  ok "desktop entry → $dest"
}

_add_pdf_to_utilities() {
  have gsettings || return 0
  python3 - <<'PY'
import ast, subprocess, sys
schema = "org.gnome.desktop.app-folders.folder"
path = "/org/gnome/desktop/app-folders/folders/Utilities/"
key = f"{schema}:{path}"
try:
    raw = subprocess.check_output(["gsettings", "get", key, "apps"], text=True).strip()
except subprocess.CalledProcessError:
    sys.exit(0)
apps = ast.literal_eval(raw.replace("@as ", "") or "[]")
wanted = [
    "x47-pdf.desktop",
    "onlyoffice-desktopeditors.desktop",
    "com.github.jeromerobert.pdfarranger.desktop",
    "com.github.xournalpp.xournalpp.desktop",
]
changed = False
# Keep Papers first when present; insert X47 PDF right after it.
anchor = "org.gnome.Papers.desktop"
for item in wanted:
    if item in apps:
        continue
    if item == "x47-pdf.desktop" and anchor in apps:
        apps.insert(apps.index(anchor) + 1, item)
    else:
        apps.append(item)
    changed = True
if not changed:
    sys.exit(0)
formatted = "[" + ", ".join(f"'{a}'" for a in apps) + "]"
subprocess.check_call(["gsettings", "set", key, "apps", formatted])
print("added")
PY
  ok "X47 PDF added to Utilities"
}

_add_pdf_office_folder() {
  have gsettings || return 0
  python3 - <<'PY'
import ast, subprocess
children_raw = subprocess.check_output(
    ["gsettings", "get", "org.gnome.desktop.app-folders", "folder-children"], text=True
).strip()
children = ast.literal_eval(children_raw.replace("@as ", "") or "[]")
if "Office" not in children:
    children.append("Office")
    formatted = "[" + ", ".join(f"'{c}'" for c in children) + "]"
    subprocess.check_call(["gsettings", "set", "org.gnome.desktop.app-folders", "folder-children", formatted])
schema = "org.gnome.desktop.app-folders.folder"
path = "/org/gnome/desktop/app-folders/folders/Office/"
key = f"{schema}:{path}"
subprocess.check_call(["gsettings", "set", key, "name", "Office"])
apps = [
    "x47-pdf.desktop",
    "onlyoffice-desktopeditors.desktop",
    "com.github.jeromerobert.pdfarranger.desktop",
    "com.github.xournalpp.xournalpp.desktop",
]
formatted = "[" + ", ".join(f"'{a}'" for a in apps) + "]"
subprocess.check_call(["gsettings", "set", key, "apps", formatted])
print("office-folder")
PY
  ok "Office app folder (X47 PDF Editor)"
}

_pin_pdf_desktop() {
  local desk="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
  mkdir -p "$desk"
  local dest="$desk/X47 PDF Editor.desktop"
  install -m 0755 "$HOME/.local/share/applications/x47-pdf.desktop" "$dest"
  if have gio; then
    gio set "$dest" metadata::trusted true 2>/dev/null || true
  fi
  ok "desktop shortcut → $dest"
}

_onlyoffice_present() {
  have onlyoffice-desktopeditors || have desktopeditors \
    || [[ -x /snap/bin/onlyoffice-desktopeditors ]] \
    || [[ -x /opt/onlyoffice/desktopeditors/DesktopEditors ]]
}

_install_pdf_packages() {
  if [[ "${X47_SKIP_APT:-0}" == "1" ]] || [[ "${X47_USER_ONLY:-0}" == "1" ]]; then
    warn "skipping PDF package install (no apt)"
    return 0
  fi
  if ! need_sudo && ! have pkexec; then
    warn "PDF packages need sudo — helper/guide still installed"
    return 0
  fi

  local work keyfile listfile
  work="$(mktemp -d)"
  keyfile="$work/onlyoffice.asc"
  listfile="$work/onlyoffice.list"
  if ! _onlyoffice_present; then
    log "downloading ONLYOFFICE apt key"
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE -o "$keyfile" || true
    printf 'deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main\n' \
      >"$listfile"
  fi

  local helper="$work/install-pdf.sh"
  cat >"$helper" <<EOF
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections || true
apt-get install -y pdfarranger xournalpp zenity
if ! command -v onlyoffice-desktopeditors >/dev/null && ! command -v desktopeditors >/dev/null \\
   && [[ ! -x /snap/bin/onlyoffice-desktopeditors ]] \\
   && [[ ! -x /opt/onlyoffice/desktopeditors/DesktopEditors ]]; then
  if [[ -s "$keyfile" ]]; then
    install -m 0755 -d /usr/share/keyrings /etc/apt/sources.list.d
    gpg --dearmor <"$keyfile" >/usr/share/keyrings/onlyoffice.gpg || cp "$keyfile" /usr/share/keyrings/onlyoffice.gpg
    chmod 0644 /usr/share/keyrings/onlyoffice.gpg
    install -m 0644 "$listfile" /etc/apt/sources.list.d/onlyoffice.list
    apt-get update -qq || true
  fi
  if ! apt-get install -y --no-install-recommends onlyoffice-desktopeditors; then
    if command -v snap >/dev/null; then
      snap install onlyoffice-desktopeditors || true
    fi
  fi
fi
EOF
  chmod 0755 "$helper"
  log "installing PDF tools (password prompt)"
  if _priv bash "$helper"; then
    ok "PDF packages installed"
  else
    warn "PDF package install failed or was cancelled"
  fi
  rm -rf "$work"
}

module_pdf() {
  if [[ "${X47_SKIP_PDF:-0}" == "1" ]]; then
    warn "skipping X47 PDF (X47_SKIP_PDF=1)"
    return 0
  fi
  log "installing X47 PDF"
  _install_pdf_packages
  _install_pdf_helper
  _install_pdf_guide
  _install_pdf_icon
  _install_pdf_desktop
  _add_pdf_to_utilities
  _add_pdf_office_folder
  _pin_pdf_desktop
}

module_pdf
