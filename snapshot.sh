#!/usr/bin/env bash
# Capture the live X47 Ubuntu build into this repo's assets/ + config/ + manifests/.
# Run ONCE on the reference machine. Needs sudo to read /etc hardening files.
#
# Usage: ./snapshot.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

REF_HOME="${REF_HOME:-$HOME}"
WORKSPACE_ASSETS="${WORKSPACE_ASSETS:-$SCRIPT_DIR/..}"  # parent: Ubuntu 26 Custom Build/

log "snapshotting from REF_HOME=$REF_HOME into $X47_ROOT"

# ---------- icons ----------
snap_icons() {
  log "capturing icons"
  local src="$REF_HOME/.local/share/icons/hicolor"
  local dest="$X47_ROOT/assets/icons/hicolor"
  mkdir -p "$dest"
  # Copy index.theme + icon sizes we care about
  [[ -f "$src/index.theme" ]] && cp -a "$src/index.theme" "$dest/"
  local size
  for size in scalable 48x48 64x64 128x128 256x256 512x512; do
    if [[ -d "$src/$size/apps" ]]; then
      mkdir -p "$dest/$size/apps"
      # kali-*, kali-cool-*, x47duster, plus a few non-kali helpers
      find "$src/$size/apps" -maxdepth 1 -type f \( \
        -name 'kali-*.svg' -o -name 'kali-*.png' -o \
        -name 'x47duster.png' -o \
        -name 'exploit-database.svg' -o -name 'offsec.svg' -o \
        -name 'vulnhub.svg' -o -name 'utilities-root-terminal.svg' -o \
        -name 'org.wezfurlong.wezterm.png' \
      \) -exec cp -a {} "$dest/$size/apps/" \;
    fi
  done
  # Ensure index.theme lists all sizes we ship
  cat > "$dest/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=scalable/apps,48x48/apps,64x64/apps,128x128/apps,256x256/apps,512x512/apps
Hidden=true
Example=folder

[scalable/apps]
Size=48
Type=Scalable
MinSize=1
MaxSize=256
Context=Applications

[48x48/apps]
Size=48
Type=Fixed
Context=Applications

[64x64/apps]
Size=64
Type=Fixed
Context=Applications

[128x128/apps]
Size=128
Type=Fixed
Context=Applications

[256x256/apps]
Size=256
Type=Fixed
Context=Applications

[512x512/apps]
Size=512
Type=Fixed
Context=Applications
EOF
  ok "icons: $(find "$dest" -type f | wc -l) files"
}

# ---------- terminal / watermark ----------
snap_terminal() {
  log "capturing WezTerm + watermark assets"
  mkdir -p "$X47_ROOT/assets/wezterm" "$X47_ROOT/assets/wzd"
  if [[ -f "$REF_HOME/.config/wezterm/wezterm.lua" ]]; then
    # Prefer a portable Lua HOME lookup so any user can use the config
    if grep -q "os.getenv('HOME')" "$X47_ROOT/assets/wezterm/wezterm.lua" 2>/dev/null; then
      log "keeping portable wezterm.lua already in assets/"
    else
      sed "s|${REF_HOME}|' .. (os.getenv('HOME') or '') .. '|g" \
        "$REF_HOME/.config/wezterm/wezterm.lua" \
        > "$X47_ROOT/assets/wezterm/wezterm.lua" || \
        cp -a "$REF_HOME/.config/wezterm/wezterm.lua" "$X47_ROOT/assets/wezterm/wezterm.lua"
    fi
  fi
  [[ -f "$REF_HOME/.config/wzd/banner.txt" ]] && \
    cp -a "$REF_HOME/.config/wzd/banner.txt" "$X47_ROOT/assets/wzd/"
  [[ -f "$REF_HOME/.config/wzd/watermark.png" ]] && \
    cp -a "$REF_HOME/.config/wzd/watermark.png" "$X47_ROOT/assets/wzd/"
  # Source assets from workspace if present
  [[ -f "$WORKSPACE_ASSETS/ascii-art.txt" ]] && \
    cp -a "$WORKSPACE_ASSETS/ascii-art.txt" "$X47_ROOT/assets/wzd/"
  [[ -f "$WORKSPACE_ASSETS/x47duster.png" ]] && \
    cp -a "$WORKSPACE_ASSETS/x47duster.png" "$X47_ROOT/assets/wzd/"
  # WezTerm desktop entry (templated)
  if [[ -f "$REF_HOME/.local/share/applications/org.wezfurlong.wezterm.desktop" ]]; then
    path_template \
      "$REF_HOME/.local/share/applications/org.wezfurlong.wezterm.desktop" \
      "$X47_ROOT/assets/wezterm/org.wezfurlong.wezterm.desktop" \
      "$REF_HOME"
  fi
  # Icon for WezTerm if present in squashfs
  if [[ -f "$REF_HOME/tools/wezterm/squashfs-root/org.wezfurlong.wezterm.png" ]]; then
    mkdir -p "$X47_ROOT/assets/icons/hicolor/128x128/apps"
    cp -a "$REF_HOME/tools/wezterm/squashfs-root/org.wezfurlong.wezterm.png" \
      "$X47_ROOT/assets/icons/hicolor/128x128/apps/"
  fi
  ok "terminal assets captured"
}

# ---------- launchers ----------
snap_launchers() {
  log "capturing .desktop launchers (path-templated)"
  local src="$REF_HOME/.local/share/applications"
  local dest="$X47_ROOT/assets/applications"
  mkdir -p "$dest"
  # Only ship our custom launchers + wezterm (not IDE vendor entries with secrets)
  local f
  for f in "$src"/launcher-*.desktop "$src"/org.wezfurlong.wezterm.desktop; do
    [[ -f "$f" ]] || continue
    path_template "$f" "$dest/$(basename "$f")" "$REF_HOME"
  done
  ok "launchers: $(ls "$dest"/*.desktop 2>/dev/null | wc -l)"
}

# ---------- manifests ----------
snap_manifests() {
  log "capturing package manifests"
  local m="$X47_ROOT/assets/manifests"
  mkdir -p "$m"

  # apt: filter out Ubuntu meta/base packages that shouldn't be reinstalled
  apt-mark showmanual 2>/dev/null | sort | grep -vE '^(ubuntu-|linux-|grub-|shim-|dash$|diffutils$|findutils$|grep$|gzip$|hostname$|init$|ncurses-|wbritish$|wpasupplicant$|language-pack-|libchewing|libm17n|libmarisa|libopencc|libotf|libpinyin|m17n-db|ibus-table-)' \
    > "$m/apt-manual.txt" || true

  # go bins present
  if [[ -d "$REF_HOME/go/bin" ]]; then
    ls -1 "$REF_HOME/go/bin" > "$m/go.txt"
  else
    : > "$m/go.txt"
  fi

  # Explicit go install map (name -> module) for reproducible installs
  cat > "$m/go-modules.txt" <<'EOF'
amass|github.com/owasp-amass/amass/v4/...@master
assetfinder|github.com/tomnomnom/assetfinder@latest
chisel|github.com/jpillora/chisel@latest
dalfox|github.com/hahwul/dalfox/v2@latest
dnsx|github.com/projectdiscovery/dnsx/cmd/dnsx@latest
gau|github.com/lc/gau/v2/cmd/gau@latest
gowitness|github.com/sensepost/gowitness@latest
httpx|github.com/projectdiscovery/httpx/cmd/httpx@latest
interactsh-client|github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest
katana|github.com/projectdiscovery/katana/cmd/katana@latest
kerbrute|github.com/ropnop/kerbrute@latest
lazygit|github.com/jesseduffield/lazygit@latest
naabu|github.com/projectdiscovery/naabu/v2/cmd/naabu@latest
nuclei|github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
subfinder|github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
tlsx|github.com/projectdiscovery/tlsx/cmd/tlsx@latest
waybackurls|github.com/tomnomnom/waybackurls@latest
yq|github.com/mikefarah/yq/v4@latest
# ligolo handled specially (proxy+agent rename)
# ligolo-proxy|github.com/nicocha30/ligolo-ng/cmd/proxy@latest
# ligolo-agent|github.com/nicocha30/ligolo-ng/cmd/agent@latest
EOF

  # pipx
  if have pipx; then
    pipx list --short 2>/dev/null | awk '{print $1}' > "$m/pipx.txt" || true
  else
    : > "$m/pipx.txt"
  fi
  cat > "$m/pipx-packages.txt" <<'EOF'
arjun
wafw00f
httpie
uv
impacket
smbmap
bloodhound
# specials
enum4linux-ng|git+https://github.com/cddmp/enum4linux-ng.git
netexec|git+https://github.com/Pennyw0rth/NetExec
EOF

  # cargo user bins (excluding rustup toolchain itself)
  if [[ -d "$REF_HOME/.cargo/bin" ]]; then
    ls -1 "$REF_HOME/.cargo/bin" | grep -vE '^(cargo|rustc|rustup|rust-|clippy|rls|cargo-)' \
      > "$m/cargo.txt" || true
  else
    : > "$m/cargo.txt"
  fi
  cat > "$m/cargo-crates.txt" <<'EOF'
bat
feroxbuster
# eza/fd/zoxide/delta/rustscan prefer release binaries (see release-bins.txt)
EOF

  # Release binaries (name|repo|asset_regex|bin)
  cat > "$m/release-bins.txt" <<'EOF'
gitleaks|gitleaks/gitleaks|linux_x64\.tar\.gz|gitleaks
trufflehog|trufflesecurity/trufflehog|linux_amd64\.tar\.gz|trufflehog
eza|eza-community/eza|x86_64-unknown-linux-gnu\.tar\.gz|eza
zoxide|ajeetdsouza/zoxide|x86_64-unknown-linux-musl\.tar\.gz|zoxide
delta|dandavison/delta|x86_64-unknown-linux-gnu\.tar\.gz|delta
fd|sharkdp/fd|x86_64-unknown-linux-gnu\.tar\.gz|fd
rustscan|bee-san/RustScan|x86_64-linux|rustscan
EOF

  # Gems
  cat > "$m/gems.txt" <<'EOF'
evil-winrm
wpscan
EOF

  # Git clone tools
  cat > "$m/git-clones.txt" <<'EOF'
WhatWeb|https://github.com/urbanadventurer/WhatWeb
Responder|https://github.com/lgandx/Responder
EOF

  # Snap (informational)
  if have snap; then
    snap list 2>/dev/null | awk 'NR>1 {print $1}' > "$m/snap.txt" || true
  else
    : > "$m/snap.txt"
  fi

  # App-folder membership (dconf dump)
  if have dconf; then
    dconf dump /org/gnome/desktop/app-folders/ > "$m/app-folders.dconf" 2>/dev/null || true
  fi

  # GNOME settings of interest
  if have gsettings; then
    {
      echo "icon-theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
      echo "gtk-theme=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
      echo "color-scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"
      echo "picture-uri-dark=$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || true)"
      echo "picture-uri=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || true)"
      echo "terminal-exec=$(gsettings get org.gnome.desktop.default-applications.terminal exec 2>/dev/null || true)"
    } > "$m/gnome-settings.txt"
  fi

  ok "manifests written to assets/manifests/"
}

# ---------- hardening (readable first, sudo for locked files) ----------
snap_hardening() {
  log "capturing hardening config"
  local c="$X47_ROOT/config"
  mkdir -p "$c/ufw" "$c/fail2ban/jail.d" "$c/sysctl.d" "$c/audit/rules.d" "$c/apt"

  # World-readable files — no sudo needed
  [[ -r /etc/ufw/ufw.conf ]] && cp -a /etc/ufw/ufw.conf "$c/ufw/" || true
  [[ -r /etc/default/ufw ]] && cp -a /etc/default/ufw "$c/ufw/default-ufw" || true
  if [[ -d /etc/fail2ban/jail.d ]]; then
    local jf
    for jf in /etc/fail2ban/jail.d/*; do
      [[ -r "$jf" ]] && cp -a "$jf" "$c/fail2ban/jail.d/" || true
    done
  fi
  local sf
  for sf in /etc/sysctl.d/*; do
    [[ -f "$sf" ]] || continue
    [[ "$(basename "$sf")" == README* ]] && continue
    [[ -r "$sf" ]] && cp -a "$sf" "$c/sysctl.d/" || true
  done
  for f in 50unattended-upgrades 20auto-upgrades; do
    [[ -r "/etc/apt/apt.conf.d/$f" ]] && cp -a "/etc/apt/apt.conf.d/$f" "$c/apt/" || true
  done

  # Privileged files — try non-interactive sudo, else keep packaged baselines
  if sudo -n true 2>/dev/null; then
    log "passwordless sudo available — copying locked /etc files"
    sudo -n cp -a /etc/ufw/user.rules "$c/ufw/" 2>/dev/null || warn "ufw user.rules missing"
    sudo -n cp -a /etc/ufw/user6.rules "$c/ufw/" 2>/dev/null || true
    [[ -f /etc/fail2ban/jail.local ]] && \
      sudo -n cp -a /etc/fail2ban/jail.local "$c/fail2ban/" 2>/dev/null || true
    if [[ -d /etc/audit/rules.d ]]; then
      sudo -n cp -a /etc/audit/rules.d/. "$c/audit/rules.d/" 2>/dev/null || true
    fi
    sudo -n chown -R "$(id -u):$(id -g)" "$c" 2>/dev/null || true
  else
    warn "no passwordless sudo — keeping packaged UFW/audit baselines in config/"
    warn "re-run: sudo ./snapshot.sh  (interactive) to capture exact live rules"
  fi

  chmod -R u+rwX,go+rX "$c" 2>/dev/null || true
  ok "hardening config under config/"
}

# ---------- main ----------
snap_icons
snap_terminal
snap_launchers
snap_manifests
snap_hardening

log "snapshot complete"
log "review assets/ + config/, then commit and push"
