#!/usr/bin/env python3
"""Make Tiling Shell layout templates actually retile windows when clicked.

By default, clicking a layout in the top-bar menu only *selects* it for the
next drag — existing windows stay put, so it feels broken. Patch
`selectLayoutOnClick` to also place the current workspace's windows into
that layout's tiles (left-to-right, top-to-bottom).

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-apply-layout-on-click"

OLD = """  selectLayoutOnClick(monitorIndex, layoutToSelectId) {
    GlobalState.get().setSelectedLayoutOfMonitor(
      layoutToSelectId,
      monitorIndex
    );
    this.menu.toggle();
  }"""

NEW = f"""  selectLayoutOnClick(monitorIndex, layoutToSelectId) {{
    GlobalState.get().setSelectedLayoutOfMonitor(
      layoutToSelectId,
      monitorIndex
    );
    // {MARKER}: also place existing windows into the chosen layout tiles
    try {{
      const layout = GlobalState.get().getSelectedLayoutOfMonitor(
        monitorIndex,
        global.workspaceManager.get_active_workspace_index()
      );
      if (layout && layout.tiles && layout.tiles.length) {{
        const workArea = Main.layoutManager.getWorkAreaForMonitor(monitorIndex);
        const ws = global.workspaceManager.get_active_workspace();
        const wins = global.display.get_tab_list(0 /* Meta.TabList.NORMAL */, ws).filter(
          (w) => w && w.get_monitor() === monitorIndex && !w.minimized
            && !w.is_override_redirect()
        );
        const tiles = layout.tiles.slice().sort(
          (a, b) => (a.y - b.y) || (a.x - b.x)
        );
        for (let i = 0; i < wins.length && i < tiles.length; i++) {{
          const win = wins[i];
          const t = tiles[i];
          const x = Math.round(workArea.x + t.x * workArea.width);
          const y = Math.round(workArea.y + t.y * workArea.height);
          const w = Math.round(t.width * workArea.width);
          const h = Math.round(t.height * workArea.height);
          if (w <= 0 || h <= 0) continue;
          try {{
            if (win.maximizedHorizontally || win.maximizedVertically)
              win.unmaximize(3 /* Meta.MaximizeFlags.BOTH */);
          }} catch (_) {{ /* ignore */ }}
          win.move_resize_frame(true, x, y, w, h);
          win.assignedTile = t;
        }}
      }}
    }} catch (e) {{
      console.warn(`tilingshell apply-layout: ${{e}}`);
    }}
    this.menu.toggle();
  }}"""


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
    if MARKER in text:
        print("  skip apply-layout (already patched)")
        return 0
    if OLD not in text:
        print("  WARN: selectLayoutOnClick pattern not found", file=sys.stderr)
        return 1
    path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"  patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
