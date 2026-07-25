#!/usr/bin/env bash
# Shared helpers for ubuntu-x47-build install / snapshot scripts.
# shellcheck disable=SC2034

set -euo pipefail

# Resolve repo root (directory containing install.sh / snapshot.sh)
X47_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export X47_ROOT

# Logging
log()  { printf '\033[1;34m[x47]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ok]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; }
die()  { fail "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Prefer sudo when available and needed; no-op if already root.
# Routed through `env` so leading VAR=value assignments (e.g.
# DEBIAN_FRONTEND=noninteractive) work whether we are root or using sudo.
run_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    env "$@"
  elif have sudo; then
    sudo env "$@"
  else
    die "sudo required for: $*"
  fi
}

need_sudo() {
  [[ "$(id -u)" -eq 0 ]] || have sudo
}

# Architecture helpers
arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) uname -m ;;
  esac
}

# Bootstrap user PATH (mirrors .bashrc tail used on the reference machine)
bootstrap_path() {
  export GOPATH="${GOPATH:-$HOME/go}"
  mkdir -p "$HOME/.local/bin" "$GOPATH/bin" "$HOME/tools" "$HOME/.cache"
  export PATH="$HOME/.local/bin:$GOPATH/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"
  if [[ -r "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  if have ruby; then
    local gem_bin
    gem_bin="$(ruby -e 'print Gem.user_dir' 2>/dev/null)/bin" || true
    [[ -n "${gem_bin:-}" ]] && export PATH="$PATH:$gem_bin"
    export GEM_HOME="${GEM_HOME:-$(ruby -e 'print Gem.user_dir' 2>/dev/null)}"
  fi
}

# Ensure PATH exports persist in ~/.bashrc (idempotent)
ensure_bashrc_path() {
  local marker="# --- x47-build PATH ---"
  if grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null; then
    return 0
  fi
  cat >> "$HOME/.bashrc" <<'EOF'

# --- x47-build PATH ---
export PATH="$PATH:$HOME/.local/bin"
export GOPATH="${GOPATH:-$HOME/go}"
export PATH="$PATH:$GOPATH/bin"
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export PATH="$PATH:/usr/local/go/bin"
if command -v ruby >/dev/null 2>&1; then
  _gem_bin="$(ruby -e 'print Gem.user_dir' 2>/dev/null)/bin"
  [ -n "$_gem_bin" ] && export PATH="$PATH:$_gem_bin"
  unset _gem_bin
fi
# --- end x47-build PATH ---
EOF
  ok "appended PATH block to ~/.bashrc"
}

# Download helper
download() {
  local url="$1" dest="$2"
  if have curl; then
    curl -fsSL "$url" -o "$dest"
  elif have wget; then
    wget -qO "$dest" "$url"
  else
    die "curl or wget required to download $url"
  fi
}

# GitHub latest release asset URL matching a regex
gh_asset_url() {
  local repo="$1" rx="$2"
  curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+"' \
    | sed 's/.*"browser_download_url": *"//;s/"$//' \
    | grep -iE "$rx" | head -n1
}

# Install a binary from a GitHub release archive into ~/.local/bin
# Usage: install_release_bin <name> <repo> <asset_regex> <binary_name>
install_release_bin() {
  local name="$1" repo="$2" rx="$3" bin="$4"
  if have "$bin"; then
    log "skip $name (already on PATH)"
    return 0
  fi
  log "installing $name from GitHub release ($repo)"
  local url tmp dir f found
  url="$(gh_asset_url "$repo" "$rx")"
  [[ -n "$url" ]] || { fail "$name: no matching release asset"; return 1; }
  tmp="$(mktemp -d)"
  dir="$tmp/$name"
  mkdir -p "$dir"
  f="$dir/${url##*/}"
  download "$url" "$f" || { rm -rf "$tmp"; fail "$name: download failed"; return 1; }
  case "$f" in
    *.tar.gz|*.tgz) tar -xzf "$f" -C "$dir" ;;
    *.tar.xz)       tar -xJf "$f" -C "$dir" ;;
    *.zip)
      # Some releases are double-zipped (e.g. rustscan .tar.gz.zip)
      unzip -qo "$f" -d "$dir"
      local inner
      inner="$(find "$dir" -maxdepth 2 \( -name '*.tar.gz' -o -name '*.tgz' \) | head -n1)"
      if [[ -n "$inner" ]]; then
        tar -xzf "$inner" -C "$dir"
      fi
      ;;
    *.deb)
      # extract binary from .deb
      (cd "$dir" && ar x "$f" && tar -xf data.tar.* 2>/dev/null || true)
      ;;
    *)
      cp "$f" "$dir/$bin"
      chmod +x "$dir/$bin"
      ;;
  esac
  found="$(find "$dir" -type f -name "$bin" ! -name '*.tar*' ! -name '*.zip' | head -n1)"
  [[ -z "$found" ]] && found="$(find "$dir" -type f -perm -u+x -name "${bin}*" | head -n1)"
  if [[ -n "$found" ]]; then
    install -m 0755 "$found" "$HOME/.local/bin/$bin"
    ok "$name -> ~/.local/bin/$bin"
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  fail "$name: binary '$bin' not found in archive"
  return 1
}

# Rewrite absolute /home/<user>/ paths to $HOME placeholder (for snapshot)
path_template() {
  local src="$1" dest="$2" user_home="${3:-$HOME}"
  sed "s|${user_home}|\$HOME|g" "$src" > "$dest"
}

# Expand $HOME placeholders in a file into the live home
path_expand() {
  local src="$1" dest="$2"
  sed "s|\$HOME|${HOME}|g" "$src" > "$dest"
}
