#!/usr/bin/env bash
# Remove X47 Cursor titlebar autohide (kept only for Firefox via userChrome).
# Usage: sudo ./scripts/cursor-autohide-titlebar.sh [remove]
# Default action is remove — do not re-apply to Cursor.
set -euo pipefail

WB_DIR=/usr/share/cursor/resources/app/out/vs/code/electron-sandbox/workbench
WB_HTML="$WB_DIR/workbench.html"
CSS="$WB_DIR/x47-autohide-titlebar.css"
USER_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/x47-autohide-titlebar.css"

action="${1:-remove}"
case "$action" in
  remove|off|uninstall) ;;
  apply|on|install)
    echo "Cursor titlebar autohide is retired (Firefox-only). Refusing to apply." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [remove]" >&2
    exit 2
    ;;
esac

if [[ -f "$WB_HTML" ]]; then
  python3 - "$WB_HTML" <<'PY'
from pathlib import Path
import re, sys
html_path = Path(sys.argv[1])
begin = "<!-- X47 autohide titlebar start -->"
end = "<!-- X47 autohide titlebar end -->"
text = html_path.read_text()
new = re.sub(
    re.escape(begin) + r".*?" + re.escape(end) + r"\n?\t?",
    "",
    text,
    count=1,
    flags=re.S,
)
if new != text:
    html_path.write_text(new)
    print(f"removed autohide snippet from {html_path}")
else:
    print(f"no autohide snippet in {html_path}")
PY
else
  echo "Cursor workbench.html not found — skip system remove"
fi

rm -f "$CSS"
rm -f "$USER_CSS"

# Prefer restoring backup if present and still looks like a clean workbench.
if [[ -f "$WB_HTML.x47-bak" && -f "$WB_HTML" ]]; then
  if ! grep -q 'X47 autohide titlebar' "$WB_HTML" 2>/dev/null; then
    : # already clean
  fi
fi

echo "Cursor titlebar autohide removed — reload Cursor (Ctrl+Shift+P → Developer: Reload Window)"
echo "Firefox chrome autohide is also retired (stock UI)."
