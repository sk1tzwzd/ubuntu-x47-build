#!/usr/bin/env bash
# Install prebuilt GitHub release binaries + git-cloned tools + gems.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_tools_release() {
  bootstrap_path
  mkdir -p "$HOME/.local/bin" "$HOME/tools"

  # --- release binaries ---
  local manifest="$X47_ROOT/assets/manifests/release-bins.txt"
  if [[ -f "$manifest" ]]; then
    local line name repo rx bin
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      IFS='|' read -r name repo rx bin <<< "$line"
      install_release_bin "$name" "$repo" "$rx" "$bin" || true
    done < "$manifest"
  fi

  # --- git clones (WhatWeb, Responder) ---
  local clones="$X47_ROOT/assets/manifests/git-clones.txt"
  if [[ -f "$clones" ]]; then
    local cname curl_
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      IFS='|' read -r cname curl_ <<< "$line"
      if [[ -d "$HOME/tools/$cname/.git" ]]; then
        log "skip clone $cname"
      else
        log "cloning $cname"
        git clone --depth 1 "$curl_" "$HOME/tools/$cname" >/dev/null \
          && ok "cloned $cname" || fail "clone $cname"
      fi
    done < "$clones"
  fi

  # WhatWeb wrapper
  if [[ -x "$HOME/tools/WhatWeb/whatweb" ]] && [[ ! -e "$HOME/.local/bin/whatweb" ]]; then
    ln -sfn "$HOME/tools/WhatWeb/whatweb" "$HOME/.local/bin/whatweb"
    ok "whatweb -> ~/.local/bin/whatweb"
  fi

  # Responder wrapper
  if [[ -f "$HOME/tools/Responder/Responder.py" ]] && [[ ! -e "$HOME/.local/bin/responder" ]]; then
    cat > "$HOME/.local/bin/responder" <<EOF
#!/usr/bin/env bash
exec python3 "$HOME/tools/Responder/Responder.py" "\$@"
EOF
    chmod +x "$HOME/.local/bin/responder"
    ok "responder -> ~/.local/bin/responder"
  fi

  # --- gems (evil-winrm, wpscan) ---
  local gems="$X47_ROOT/assets/manifests/gems.txt"
  if [[ -f "$gems" ]] && have gem; then
    local g
    while IFS= read -r g || [[ -n "$g" ]]; do
      [[ -z "$g" || "$g" =~ ^# ]] && continue
      if have "$g"; then
        log "skip gem $g"
        continue
      fi
      log "gem install --user-install $g"
      if gem install --user-install --no-document "$g" >/dev/null; then
        bootstrap_path
        have "$g" && ok "$g" || warn "$g installed but not on PATH (check GEM bin)"
      else
        fail "$g (need ruby-dev?)"
      fi
    done < "$gems"
  elif [[ -f "$gems" ]]; then
    warn "ruby/gem not available — skipping gems"
  fi

  ok "release/git/gem tools module done"
}

module_tools_release "$@"
