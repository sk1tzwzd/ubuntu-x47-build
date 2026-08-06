#!/usr/bin/env bash
# Restore a stock Cursor install after X47 titlebar experiments.
# Fixes the "installation appears to be corrupt" integrity warning.
set -euo pipefail

WB_DIR=/usr/share/cursor/resources/app/out/vs/code/electron-sandbox/workbench

run() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

echo "Reinstalling Cursor package (restores stock workbench files)…"
run apt-get update -qq
run apt-get install --reinstall -y cursor

echo "Removing leftover X47 patches…"
run rm -f "$WB_DIR/workbench.html.x47-bak" \
  "$WB_DIR/x47-autohide-titlebar.css"

# Verify product checksums
python3 - <<'PY'
import hashlib, base64, json
from pathlib import Path
root = Path("/usr/share/cursor/resources/app")
prod = json.loads((root / "product.json").read_text())
bad = 0
for rel, expected in prod.get("checksums", {}).items():
    path = root / "out" / rel
    if not path.exists():
        print("MISSING", rel)
        bad += 1
        continue
    got = base64.b64encode(hashlib.sha256(path.read_bytes()).digest()).decode().rstrip("=")
    exp = expected.rstrip("=")
    if got != exp:
        print("MISMATCH", rel)
        bad += 1
print("checksums_ok" if bad == 0 else f"checksums_bad={bad}")
raise SystemExit(bad)
PY

echo
echo "Done. Fully quit Cursor (all windows), then reopen it."
echo "The corrupt-install banner should be gone."
