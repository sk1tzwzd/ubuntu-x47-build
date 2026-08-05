#!/usr/bin/env python3
"""Fix Tiling Shell's layout editor on GNOME 50 (Mutter 18).

Mutter 18 removed both the `Meta.Cursor` enum and `Meta.Display.set_cursor()`.
Tiling Shell's editor slider still uses them, so opening / closing the layout
editor throws and strands its blue overlay on screen. Rewrite the cursor code
to fall back to `Clutter.CursorType` + `global.stage.set_cursor_type()`.

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-gnome50-cursor"

PREFERRED_OLD = """  get preferredCursor() {
    const horizCursor = Meta.Cursor.WEST_RESIZE ?? Meta.Cursor.W_RESIZE;
    const vertCursor = Meta.Cursor.NORTH_RESIZE ?? Meta.Cursor.N_RESIZE;
    return this.hover || this._dragging ? this._horizontalDir ? horizCursor : vertCursor : Meta.Cursor.DEFAULT;
  }"""

PREFERRED_NEW = f"""  get preferredCursor() {{
    // {MARKER}: Meta.Cursor was removed in Mutter 18 — use Clutter.CursorType
    const _mc = Meta.Cursor ?? Clutter.CursorType;
    const horizCursor = _mc.WEST_RESIZE ?? _mc.W_RESIZE;
    const vertCursor = _mc.NORTH_RESIZE ?? _mc.N_RESIZE;
    return this.hover || this._dragging ? this._horizontalDir ? horizCursor : vertCursor : _mc.DEFAULT;
  }}"""

SET_OLD = "global.display.set_cursor(this.preferredCursor)"
SET_NEW = ("(global.display.set_cursor"
           " ? global.display.set_cursor(this.preferredCursor)"
           " : global.stage.set_cursor_type(this.preferredCursor))")


def main() -> int:
    root = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home()
        / ".local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com"
    )
    slider = root / "components/editor/slider.js"
    if not slider.is_file():
        print(f"Tiling Shell slider not found at {slider}", file=sys.stderr)
        return 1

    text = slider.read_text(encoding="utf-8")
    if MARKER in text:
        print("  skip (already patched)")
        return 0
    if PREFERRED_OLD not in text or SET_OLD not in text:
        print("  WARN: expected cursor code not found — Tiling Shell changed?",
              file=sys.stderr)
        return 1
    text = text.replace(PREFERRED_OLD, PREFERRED_NEW, 1)
    text = text.replace(SET_OLD, SET_NEW)
    slider.write_text(text, encoding="utf-8")
    print(f"  patched {slider}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
