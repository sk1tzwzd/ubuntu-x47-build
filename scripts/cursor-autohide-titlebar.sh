#!/usr/bin/env bash
# Inject soft-hide titlebar CSS into Cursor's workbench (needs sudo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CSS_SRC="${1:-$ROOT/assets/cursor/x47-autohide-titlebar.css}"
WB_DIR=/usr/share/cursor/resources/app/out/vs/code/electron-sandbox/workbench
WB_HTML="$WB_DIR/workbench.html"
[[ -f "$CSS_SRC" ]] || { echo "missing $CSS_SRC" >&2; exit 1; }
[[ -f "$WB_HTML" ]] || { echo "Cursor workbench.html not found" >&2; exit 1; }
[[ -f "$WB_HTML.x47-bak" ]] || cp -a "$WB_HTML" "$WB_HTML.x47-bak"
install -m 0644 "$CSS_SRC" "$WB_DIR/x47-autohide-titlebar.css"
python3 - "$WB_HTML" <<'PY'
from pathlib import Path
import re, sys
html_path = Path(sys.argv[1])
begin = "<!-- X47 autohide titlebar start -->"
end = "<!-- X47 autohide titlebar end -->"
snippet = f"""{begin}
		<link rel=\"stylesheet\" href=\"./x47-autohide-titlebar.css\">
		{end}
"""
text = html_path.read_text()
if begin in text:
    text = re.sub(re.escape(begin) + r".*?" + re.escape(end), snippet.strip(), text, count=1, flags=re.S)
else:
    text = text.replace("</head>", snippet + "\t</head>", 1)
html_path.write_text(text)
print("Cursor titlebar autohide applied — reload the window (Ctrl+Shift+P → Developer: Reload Window)")
PY
