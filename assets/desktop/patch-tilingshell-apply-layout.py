#!/usr/bin/env python3
"""Keep layout-menu clicks as selection-only (no retile on click).

Earlier X47 builds retilled every open window when a layout was chosen.
That fought the desired model: windows open floating; the grid only
applies while a window is being moved. This script strips that retile
hook if present, and is a no-op on a clean upstream install.

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "x47-apply-layout-on-click"

# Upstream / desired behaviour
SELECT_ONLY = """  selectLayoutOnClick(monitorIndex, layoutToSelectId) {
    GlobalState.get().setSelectedLayoutOfMonitor(
      layoutToSelectId,
      monitorIndex
    );
    this.menu.toggle();
  }"""


def main() -> int:
    root = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home()
        / ".local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com"
    )
    path = root / "indicator/indicator.js"
    if not path.is_file():
        print(f"indicator.js not found at {path}", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    if MARKER not in text:
        print("  skip apply-layout (no retile hook present)")
        return 0
    # Remove the whole selectLayoutOnClick that contains our marker
    new_text, n = re.subn(
        r"  selectLayoutOnClick\(monitorIndex, layoutToSelectId\) \{.*?"
        r"this\.menu\.toggle\(\);\n  \}",
        SELECT_ONLY,
        text,
        count=1,
        flags=re.DOTALL,
    )
    if n != 1 or MARKER in new_text:
        print("  WARN: could not strip apply-layout retile hook", file=sys.stderr)
        return 1
    path.write_text(new_text, encoding="utf-8")
    print(f"  stripped retile-on-click from {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
