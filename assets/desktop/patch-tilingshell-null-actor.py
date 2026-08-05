#!/usr/bin/env python3
"""Guard Tiling Shell against null compositor actors mid-snap.

On GNOME 50, drag-end can fire after the window actor is already gone
(`window.get_compositor_private()` returns null), which throws in
`_easeWindowRect` and leaves snap/suggestion overlays stuck.

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-null-window-actor"

OLD = """  _easeWindowRect(window, destRect, user_op = false, force = false) {
    const windowActor = window.get_compositor_private();
    const beforeRect = window.get_frame_rect();
    if (destRect.x === beforeRect.x && destRect.y === beforeRect.y && destRect.width === beforeRect.width && destRect.height === beforeRect.height)
      return;
    windowActor.remove_all_transitions();
    Main.wm._prepareAnimationInfo(
      global.windowManager,
      windowActor,
      beforeRect.copy(),
      Meta.SizeChange.UNMAXIMIZE
    );
    window.move_to_monitor(this._monitor.index);
    if (force) window.move_frame(user_op, destRect.x, destRect.y);
    window.move_resize_frame(
      user_op,
      destRect.x,
      destRect.y,
      destRect.width,
      destRect.height
    );
  }"""

NEW = f"""  _easeWindowRect(window, destRect, user_op = false, force = false) {{
    // {MARKER}: compositor private can be null mid-destroy / mid-workspace move
    if (!window)
      return;
    const windowActor = window.get_compositor_private();
    const beforeRect = window.get_frame_rect();
    if (destRect.x === beforeRect.x && destRect.y === beforeRect.y && destRect.width === beforeRect.width && destRect.height === beforeRect.height)
      return;
    if (windowActor) {{
      try {{
        windowActor.remove_all_transitions();
        Main.wm._prepareAnimationInfo(
          global.windowManager,
          windowActor,
          beforeRect.copy(),
          Meta.SizeChange.UNMAXIMIZE
        );
      }} catch (_) {{ /* animation prep is best-effort */ }}
    }}
    try {{
      window.move_to_monitor(this._monitor.index);
    }} catch (_) {{ /* ignore */ }}
    if (force) {{
      try {{ window.move_frame(user_op, destRect.x, destRect.y); }} catch (_) {{}}
    }}
    try {{
      window.move_resize_frame(
        user_op,
        destRect.x,
        destRect.y,
        destRect.width,
        destRect.height
      );
    }} catch (_) {{ /* window may already be gone */ }}
  }}"""


def main() -> int:
    root = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home()
        / ".local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com"
    )
    path = root / "components/tilingsystem/tilingManager.js"
    if not path.is_file():
        print(f"tilingManager.js not found at {path}", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print("  skip null-actor (already patched)")
        return 0
    if OLD not in text:
        print("  WARN: _easeWindowRect pattern not found", file=sys.stderr)
        return 1
    path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"  patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
