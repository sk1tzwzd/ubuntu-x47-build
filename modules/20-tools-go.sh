#!/usr/bin/env bash
# Install Go-based pentest / QoL tools from assets/manifests/go-modules.txt
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_tools_go() {
  bootstrap_path

  if ! have go; then
    warn "go not on PATH — install golang-go via apt first (00-apt.sh)"
    return 1
  fi

  export GOPATH="${GOPATH:-$HOME/go}"
  mkdir -p "$GOPATH/bin"

  local manifest="$X47_ROOT/assets/manifests/go-modules.txt"
  [[ -f "$manifest" ]] || die "missing $manifest"

  local line name mod
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    IFS='|' read -r name mod <<< "$line"
    if have "$name"; then
      log "skip $name"
      continue
    fi
    log "go install $name ($mod)"
    if go install "$mod"; then
      ok "$name"
    else
      fail "$name (go install failed)"
    fi
  done < "$manifest"

  # ligolo-ng: proxy + agent with renamed binaries
  if have ligolo-proxy; then
    log "skip ligolo-ng"
  else
    log "installing ligolo-ng (proxy + agent)"
    if go install github.com/nicocha30/ligolo-ng/cmd/proxy@latest \
       && go install github.com/nicocha30/ligolo-ng/cmd/agent@latest; then
      [[ -f "$GOPATH/bin/proxy" ]] && mv -f "$GOPATH/bin/proxy" "$GOPATH/bin/ligolo-proxy"
      [[ -f "$GOPATH/bin/agent" ]] && mv -f "$GOPATH/bin/agent" "$GOPATH/bin/ligolo-agent"
      have ligolo-proxy && ok "ligolo-ng" || fail "ligolo-ng"
    else
      fail "ligolo-ng"
    fi
  fi

  ok "go tools module done"
}

module_tools_go "$@"
