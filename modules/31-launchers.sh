#!/usr/bin/env bash
# Install .desktop launchers (\$HOME expanded) and wire GNOME app-grid folders.
set -euo pipefail
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

module_launchers() {
  bootstrap_path
  local src="$X47_ROOT/assets/applications"
  local dest="$HOME/.local/share/applications"
  [[ -d "$src" ]] || die "missing $src — run snapshot.sh first"

  mkdir -p "$dest"
  log "installing launchers from $src"
  local f
  for f in "$src"/*.desktop; do
    [[ -f "$f" ]] || continue
    # Standalone Claude CLI launcher is retired — VS Code extension only.
    [[ "$(basename "$f")" == "launcher-claude.desktop" ]] && continue
    path_expand "$f" "$dest/$(basename "$f")"
  done

  if have update-desktop-database; then
    update-desktop-database "$dest" >/dev/null 2>&1 || true
  fi
  ok "launchers installed ($(ls "$dest"/launcher-*.desktop 2>/dev/null | wc -l))"

  # Hide grid cruft via user-level NoDisplay overrides (shadows the system
  # entry without touching the package): leftover NymVPN (anon uses Mullvad),
  # TeX doc viewers, lstopo, and the duplicate firmware-updater snap entry.
  local hide
  for hide in NymVPN.desktop texdoctk.desktop info.desktop lstopo.desktop \
              firmware-updater_firmware-updater.desktop; do
    local sys=""
    for sys in "/usr/share/applications/$hide" \
               "/var/lib/snapd/desktop/applications/$hide"; do
      [[ -f "$sys" ]] && break
    done
    [[ -f "$sys" ]] || continue
    if [[ ! -f "$dest/$hide" ]] || ! grep -q '^NoDisplay=true' "$dest/$hide" 2>/dev/null; then
      cp "$sys" "$dest/$hide"
      sed -i '/^NoDisplay=/d' "$dest/$hide"
      sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "$dest/$hide"
      log "hidden from grid: $hide"
    fi
  done

  # Restore app-folder membership from dconf dump if available
  local dconf_dump="$X47_ROOT/assets/manifests/app-folders.dconf"
  if [[ -f "$dconf_dump" ]] && have dconf; then
    log "restoring GNOME app-folders via dconf"
    # Ensure DevTools / PentestTools folders exist even if dump is partial
    dconf load /org/gnome/desktop/app-folders/ < "$dconf_dump" 2>/dev/null \
      && ok "app-folders restored" \
      || warn "dconf load of app-folders failed (non-fatal)"
  elif have gsettings; then
    log "setting DevTools / PentestTools folders via gsettings"
    # Minimal fallback: create folders and add any launcher-*.desktop we just installed
    gsettings set org.gnome.desktop.app-folders folder-children \
      "['System', 'Utilities', 'DevTools', 'PentestTools']" 2>/dev/null || true

    local schema="org.gnome.desktop.app-folders.folder"
    local path_pt="/org/gnome/desktop/app-folders/folders/PentestTools/"
    local path_dt="/org/gnome/desktop/app-folders/folders/DevTools/"

    gsettings set "${schema}:${path_pt}" name 'Pentesting' 2>/dev/null || true
    gsettings set "${schema}:${path_dt}" name 'Dev Tools' 2>/dev/null || true

    # Build apps lists
    local -a pentest=() dev=()
    local base
    for f in "$dest"/launcher-*.desktop; do
      base="$(basename "$f")"
      case "$base" in
        launcher-bat.desktop|launcher-eza.desktop|launcher-fd.desktop| \
        launcher-zoxide.desktop|launcher-lazygit.desktop|launcher-delta.desktop| \
        launcher-uv.desktop|launcher-yq.desktop|launcher-http.desktop)
          dev+=("'$base'")
          ;;
        *)
          pentest+=("'$base'")
          ;;
      esac
    done
    if ((${#pentest[@]} > 0)); then
      local joined
      joined=$(IFS=,; echo "${pentest[*]}")
      gsettings set "${schema}:${path_pt}" apps "[$joined]" 2>/dev/null || true
    fi
    if ((${#dev[@]} > 0)); then
      local joined
      joined=$(IFS=,; echo "${dev[*]}")
      # Prefer keeping code/cursor if present
      gsettings set "${schema}:${path_dt}" apps "[$joined]" 2>/dev/null || true
    fi
  fi
}

module_launchers "$@"
