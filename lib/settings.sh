# X47 feature settings — ~/.config/x47/settings.conf
# shellcheck shell=bash

X47_SETTINGS_DIR="${X47_SETTINGS_DIR:-$HOME/.config/x47}"
X47_SETTINGS_FILE="${X47_SETTINGS_FILE:-$X47_SETTINGS_DIR/settings.conf}"

# Defaults (1 = on). Keep in sync with scripts/x47-settings and wezterm.lua.
X47_FEATURE_DEFAULTS=(
  "putty_clipboard=1"
  "win_screenshot=1"
  "tiling=1"
)

x47_settings_ensure() {
  mkdir -p "$X47_SETTINGS_DIR"
  if [[ ! -f "$X47_SETTINGS_FILE" ]]; then
    {
      echo "# X47 feature toggles — edit with: x47-settings"
      echo "# 1/on/true = enabled, 0/off/false = disabled"
      local line
      for line in "${X47_FEATURE_DEFAULTS[@]}"; do
        echo "$line"
      done
    } > "$X47_SETTINGS_FILE"
  else
    # Seed any newly-added keys without clobbering user choices.
    local line key
    for line in "${X47_FEATURE_DEFAULTS[@]}"; do
      key="${line%%=*}"
      if ! grep -qE "^${key}=" "$X47_SETTINGS_FILE" 2>/dev/null; then
        echo "$line" >> "$X47_SETTINGS_FILE"
      fi
    done
  fi
}

x47_settings_get() {
  local key="$1" default="${2:-0}" val
  x47_settings_ensure
  val="$(grep -E "^${key}=" "$X47_SETTINGS_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '[:space:]')"
  [[ -n "$val" ]] || val="$default"
  case "${val,,}" in
    1|true|on|yes) echo 1 ;;
    *) echo 0 ;;
  esac
}

x47_settings_set() {
  local key="$1" raw="$2" val
  case "${raw,,}" in
    1|true|on|yes|enable|enabled) val=1 ;;
    0|false|off|no|disable|disabled) val=0 ;;
    *) return 1 ;;
  esac
  x47_settings_ensure
  if grep -qE "^${key}=" "$X47_SETTINGS_FILE" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$val" -F= '
      $1 == k { print k "=" v; next }
      { print }
    ' "$X47_SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$X47_SETTINGS_FILE"
  else
    echo "${key}=${val}" >> "$X47_SETTINGS_FILE"
  fi
}

# Apply settings that need an immediate system action (gsettings, etc.).
x47_settings_apply() {
  local putty shot tiling
  putty="$(x47_settings_get putty_clipboard 1)"
  shot="$(x47_settings_get win_screenshot 1)"
  tiling="$(x47_settings_get tiling 1)"

  if have gsettings; then
    if [[ "$shot" == "1" ]]; then
      gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print', '<Super><Shift>s']" 2>/dev/null || true
    else
      gsettings set org.gnome.shell.keybindings show-screenshot-ui "['Print']" 2>/dev/null || true
    fi

    # Window tiling (Tiling Shell): off = windows drag/overlap freely,
    # no snap zones, no edge tiling. Applies live.
    local tdir="$HOME/.local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com/schemas"
    if [[ -d "$tdir" ]]; then
      local ts="org.gnome.shell.extensions.tilingshell" onoff=false
      [[ "$tiling" == "1" ]] && onoff=true
      gsettings --schemadir "$tdir" set $ts enable-tiling-system $onoff 2>/dev/null || true
      gsettings --schemadir "$tdir" set $ts enable-snap-assist $onoff 2>/dev/null || true
      gsettings --schemadir "$tdir" set $ts active-screen-edges $onoff 2>/dev/null || true
    fi
  fi

  # WezTerm reads settings.conf on startup — remind the caller.
  printf '%s\n' "$putty" >/dev/null
}
