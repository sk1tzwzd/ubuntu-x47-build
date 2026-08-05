#!/usr/bin/env python3
"""Fix stuck blue tile overlays when dragging a window to another desktop.

Root cause: during a cube / workspace switch mid-drag, Tiling Shell closes
only the *new* workspace's layout and leaves the previous workspace's blue
tile previews visible. The moving-window timer can also bail with
`!tilingLayout` without tearing overlays down.

Also harden SelectionTilePreview / TilingLayout `.close()` so a desynced
`_showing=false` still force-hides the actor.

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-tiling-ws-drag"


def patch_force_close(root: Path) -> bool:
    path = root / "components/tilingsystem/tilingManager.js"
    text = path.read_text(encoding="utf-8")
    changed = False

    old_fc = """  _forceCloseOverlays() {
    // x47-tiling-stability-grab — visuals only; leave snap/edge state for grab-end logic
    try { this._selectedTilesPreview?.close?.(false); } catch (_) {}
    try { this._snapAssist?.close?.(false); } catch (_) {}
    try { this._tilingSuggestionsLayout?.close?.(); } catch (_) {}
  }"""
    new_fc = f"""  _forceCloseOverlays() {{
    // x47-tiling-stability-grab — visuals only; leave snap/edge state for grab-end logic
    // {MARKER}: also close EVERY workspace layout (cube drag leaves the old one up)
    try {{ this._selectedTilesPreview?.close?.(false); }} catch (_) {{}}
    try {{ this._snapAssist?.close?.(false); }} catch (_) {{}}
    try {{ this._tilingSuggestionsLayout?.close?.(); }} catch (_) {{}}
    try {{
      this._workspaceTilingLayout?.forEach?.((tl) => {{
        try {{ tl.close?.(false); }} catch (_) {{}}
      }});
    }} catch (_) {{}}
  }}"""
    if MARKER in text and "_workspaceTilingLayout?.forEach" in text:
        print("  skip forceClose (already ws-drag patched)")
    elif old_fc in text:
        text = text.replace(old_fc, new_fc, 1)
        changed = True
    else:
        # Minimal helper without stability marker
        old_fc2 = """  _forceCloseOverlays() {
    // x47-tiling-stability-grab — visuals only; leave snap/edge state for grab-end logic
    try { this._selectedTilesPreview?.close?.(false); } catch (_) {}
    try { this._snapAssist?.close?.(false); } catch (_) {}
    try { this._tilingSuggestionsLayout?.close?.(); } catch (_) {}
  }"""
        if old_fc2 in text:
            text = text.replace(old_fc2, new_fc, 1)
            changed = True
        else:
            print("  WARN: _forceCloseOverlays not found", file=sys.stderr)

    # When layout missing mid-drag (workspace hop), don't abandon overlays
    old_miss = """    const tilingLayout = this._workspaceTilingLayout.get(currentWs);
    if (!tilingLayout) return GLib.SOURCE_REMOVE;
    this._edgeTilingManager.workspaceIndex = currentWs.index();"""
    new_miss = f"""    const tilingLayout = this._workspaceTilingLayout.get(currentWs);
    if (!tilingLayout) {{
      // {MARKER}: workspace hop mid-drag — tear down old overlays, keep timer
      this._forceCloseOverlays();
      return GLib.SOURCE_CONTINUE;
    }}
    this._edgeTilingManager.workspaceIndex = currentWs.index();"""
    if MARKER in text and "workspace hop mid-drag" in text:
        print("  skip !tilingLayout (already patched)")
    elif old_miss in text:
        text = text.replace(old_miss, new_miss, 1)
        changed = True
    else:
        print("  WARN: !tilingLayout bail not found", file=sys.stderr)

    # On workspace change while grabbing, kill overlays immediately
    old_ws = """    this._signals.connect(
      global.workspaceManager,
      "active-workspace-changed",
      () => {
        const ws = global.workspaceManager.get_active_workspace();
        if (this._workspaceTilingLayout.has(ws)) return;"""
    new_ws = f"""    this._signals.connect(
      global.workspaceManager,
      "active-workspace-changed",
      () => {{
        // {MARKER}: cube / edge workspace switch mid-drag leaves blue previews
        if (this._isGrabbingWindow) {{
          try {{ this._forceCloseOverlays(); }} catch (_) {{}}
          try {{ this._snapAssistingInfo?.update?.(void 0); }} catch (_) {{}}
          try {{ this._edgeTilingManager?.abortEdgeTiling?.(); }} catch (_) {{}}
        }}
        const ws = global.workspaceManager.get_active_workspace();
        if (this._workspaceTilingLayout.has(ws)) return;"""
    if "cube / edge workspace switch mid-drag" in text:
        print("  skip workspace-changed (already patched)")
    elif old_ws in text:
        text = text.replace(old_ws, new_ws, 1)
        changed = True
    else:
        print("  WARN: active-workspace-changed hook not found", file=sys.stderr)

    # Skip tiling apply if the window changed workspace during the drag
    if "x47-tiling-ws-drag-skip-retile" not in text:
        old_grab_begin_flag = """    this._isGrabbingWindow = true;
    this._movingWindowTimerId = GLib.timeout_add("""
        new_grab_begin_flag = f"""    this._isGrabbingWindow = true;
    try {{ this._grabStartWsIndex = window.get_workspace()?.index?.() ?? -1; }} catch (_) {{ this._grabStartWsIndex = -1; }}
    // {MARKER}-skip-retile
    this._movingWindowTimerId = GLib.timeout_add("""
        if old_grab_begin_flag in text:
            text = text.replace(old_grab_begin_flag, new_grab_begin_flag, 1)
            changed = True

        # After force close in grab-end, bail if workspace changed
        needle = """    this._forceCloseOverlays();
    this._lastCursorPos = null;
    if (!window || !desiredWindowRect || !selectedTilesRect)
      return;"""
        insert = f"""    this._forceCloseOverlays();
    this._lastCursorPos = null;
    if (!window || !desiredWindowRect || !selectedTilesRect)
      return;
    // {MARKER}-skip-retile: dropped onto another desktop — leave floating
    try {{
      const endWs = window.get_workspace()?.index?.() ?? -1;
      if (this._grabStartWsIndex !== -1 && endWs !== -1 && endWs !== this._grabStartWsIndex) {{
        try {{ this._snapAssistingInfo?.update?.(void 0); }} catch (_) {{}}
        try {{ this._edgeTilingManager?.abortEdgeTiling?.(); }} catch (_) {{}}
        this._grabStartWsIndex = -1;
        return;
      }}
    }} catch (_) {{}}
    this._grabStartWsIndex = -1;"""
        if needle in text and "dropped onto another desktop" not in text:
            text = text.replace(needle, insert, 1)
            changed = True

    if changed:
        path.write_text(text, encoding="utf-8")
        print(f"  patched {path}")
    else:
        print(f"  no tilingManager changes ({path})")
    return True


def patch_selection_preview(root: Path) -> bool:
    path = root / "components/tilepreview/selectionTilePreview.js"
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print("  skip selectionTilePreview (already patched)")
        return True
    old = """  close(ease = false) {
    if (!this._showing) return;
    this._rect.width = this.gaps.left + this.gaps.right;
    this._rect.height = this.gaps.top + this.gaps.bottom;
    super.close(ease);
  }"""
    new = f"""  close(ease = false) {{
    // {MARKER}: never early-return while the blue actor is still painted
    try {{
      this._rect.width = this.gaps.left + this.gaps.right;
      this._rect.height = this.gaps.top + this.gaps.bottom;
    }} catch (_) {{}}
    super.close(ease);
  }}"""
    if old not in text:
        print("  WARN: SelectionTilePreview.close not found", file=sys.stderr)
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  patched {path}")
    return True


def patch_tiling_layout(root: Path) -> bool:
    path = root / "components/tilingsystem/tilingLayout.js"
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print("  skip tilingLayout (already patched)")
        return True
    old = """  close(ease = false) {
    if (!this._showing) return;
    this._showing = false;
    this.ease({
      opacity: 0,
      duration: ease ? GlobalState.get().tilePreviewAnimationTime : 0,
      mode: Clutter.AnimationMode.EASE_OUT_QUAD,
      onComplete: () => {
        this.unhoverAllTiles();
        this.hide();
      }
    });
  }"""
    new = f"""  close(ease = false) {{
    // {MARKER}: force-hide even if _showing desynced during workspace switch
    if (!this._showing) {{
      try {{ this.remove_all_transitions(); this.unhoverAllTiles(); this.hide(); this.opacity = 0; }} catch (_) {{}}
      return;
    }}
    this._showing = false;
    const finish = () => {{
      try {{ this.unhoverAllTiles(); this.hide(); this.opacity = 0; }} catch (_) {{}}
    }};
    try {{
      this.remove_all_transitions();
      const dur = ease ? GlobalState.get().tilePreviewAnimationTime : 0;
      if (!dur) {{
        finish();
        return;
      }}
      this.ease({{
        opacity: 0,
        duration: dur,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        onComplete: finish
      }});
    }} catch (_) {{
      finish();
    }}
  }}"""
    if old not in text:
        print("  WARN: TilingLayout.close not found", file=sys.stderr)
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  patched {path}")
    return True


def main() -> int:
    root = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home()
        / ".local/share/gnome-shell/extensions/tilingshell@ferrarodomenico.com"
    )
    if not root.is_dir():
        print(f"tilingshell not found at {root}", file=sys.stderr)
        return 1
    ok = True
    ok = patch_force_close(root) and ok
    ok = patch_selection_preview(root) and ok
    ok = patch_tiling_layout(root) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
