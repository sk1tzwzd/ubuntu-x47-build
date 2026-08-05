#!/usr/bin/env python3
"""Harden Tiling Shell against stuck overlays / dispose races on GNOME 50.

Problems this addresses:
  - SnapAssist.workArea runs after the actor was destroyed (workareas-changed
    during disable / dock hide) → "already disposed" spam + half-dead state
  - grab-end / moving-window timer can throw if the Meta.Window vanishes mid
    drag → tile preview / snap assist left visible and stealing clicks
  - TilePreview.close relies on ease onComplete to hide(); if the actor is
    disposed mid-animation the blue overlay stays forever
  - _prepareAnimationInfo fights Compiz wobbly → "Error in size change
    accounting" and flaky tile landings

Idempotent. Re-run after Tiling Shell updates.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-tiling-stability"


def _once(text: str, old: str, new: str, label: str) -> tuple[str, bool]:
    if MARKER in new and new.strip()[:80] in text:
        return text, False
    if old not in text:
        print(f"  WARN: {label} pattern not found", file=sys.stderr)
        return text, False
    return text.replace(old, new, 1), True


def patch_snap_assist(root: Path) -> bool:
    path = root / "components/snapassist/snapAssist.js"
    text = path.read_text(encoding="utf-8")
    if "x47-tiling-stability-snap" in text:
        print("  skip snapAssist (already patched)")
        return True

    old_wa = """  set workArea(newWorkArea) {
    this.set_position(newWorkArea.x, newWorkArea.y);
    this.set_width(newWorkArea.width);
    this.set_clip(0, 0, newWorkArea.width, newWorkArea.height);
  }"""
    new_wa = """  set workArea(newWorkArea) {
    // x47-tiling-stability-snap: actor may already be disposed during disable
    try {
      if (this.is_destroyed?.() || this._content?.is_destroyed?.())
        return;
      this.set_position(newWorkArea.x, newWorkArea.y);
      this.set_width(newWorkArea.width);
      this.set_clip(0, 0, newWorkArea.width, newWorkArea.height);
    } catch (_) { /* disposed */ }
  }"""

    old_close = """  close(ease = false) {
    this._content.close(ease);
  }"""
    new_close = """  close(ease = false) {
    // x47-tiling-stability-snap
    try {
      if (!this._content || this._content.is_destroyed?.())
        return;
      this._content.close(ease);
    } catch (_) { /* disposed */ }
  }"""

    changed = False
    text, c = _once(text, old_wa, new_wa, "SnapAssist.workArea")
    changed = changed or c
    text, c = _once(text, old_close, new_close, "SnapAssist.close")
    changed = changed or c

    # Content close: force-hide even if ease fails
    old_cclose = """  close(ease = false) {
    if (!this._showing) return;
    this._showing = false;
    this._isEnlarged = false;
    this.set_x(this._container.width / 2 - this.width / 2);
    this.ease({
      y: this._desiredY,
      opacity: 0,
      duration: ease ? this._snapAssistantAnimationTime : 0,
      mode: Clutter.AnimationMode.EASE_OUT_QUAD,
      onComplete: () => {
        this.hide();
      }
    });
  }"""
    new_cclose = """  close(ease = false) {
    // x47-tiling-stability-snap
    if (!this._showing) {
      try { this.hide(); this.opacity = 0; } catch (_) {}
      return;
    }
    this._showing = false;
    this._isEnlarged = false;
    const finish = () => {
      try { this.hide(); this.opacity = 0; } catch (_) {}
    };
    try {
      this.remove_all_transitions();
      this.set_x(this._container.width / 2 - this.width / 2);
      if (!ease || !this._snapAssistantAnimationTime) {
        finish();
        return;
      }
      this.ease({
        y: this._desiredY,
        opacity: 0,
        duration: this._snapAssistantAnimationTime,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        onComplete: finish
      });
    } catch (_) {
      finish();
    }
  }"""
    text, c = _once(text, old_cclose, new_cclose, "SnapAssistContent.close")
    changed = changed or c

    if not changed:
        return False
    path.write_text(text, encoding="utf-8")
    print(f"  patched {path}")
    return True


def patch_tile_preview(root: Path) -> bool:
    path = root / "components/tilepreview/tilePreview.js"
    text = path.read_text(encoding="utf-8")
    if "x47-tiling-stability-preview" in text:
        print("  skip tilePreview (already patched)")
        return True

    old = """  close(ease = false) {
    if (!this._showing) return;
    this._showing = false;
    this.ease({
      opacity: 0,
      duration: ease ? GlobalState.get().tilePreviewAnimationTime : 0,
      mode: Clutter.AnimationMode.EASE_OUT_QUAD,
      onComplete: () => this.hide()
    });
  }"""
    new = """  close(ease = false) {
    // x47-tiling-stability-preview: never leave a visible overlay behind
    if (!this._showing) {
      try { this.hide(); this.opacity = 0; } catch (_) {}
      return;
    }
    this._showing = false;
    const finish = () => {
      try { this.hide(); this.opacity = 0; } catch (_) {}
    };
    try {
      this.remove_all_transitions();
      const dur = ease ? GlobalState.get().tilePreviewAnimationTime : 0;
      if (!dur) {
        finish();
        return;
      }
      this.ease({
        opacity: 0,
        duration: dur,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        onComplete: finish
      });
    } catch (_) {
      finish();
    }
  }"""
    if old not in text:
        print("  WARN: TilePreview.close pattern not found", file=sys.stderr)
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  patched {path}")
    return True


def _ensure_force_close_helper(text: str) -> str:
    if "  _forceCloseOverlays() {" in text:
        return text
    helper = """  _forceCloseOverlays() {
    // x47-tiling-stability-grab — visuals only; leave snap/edge state for grab-end logic
    // x47-tiling-ws-drag: also close EVERY workspace layout (cube drag leaves the old one up)
    try { this._selectedTilesPreview?.close?.(false); } catch (_) {}
    try { this._snapAssist?.close?.(false); } catch (_) {}
    try { this._tilingSuggestionsLayout?.close?.(); } catch (_) {}
    try {
      this._workspaceTilingLayout?.forEach?.((tl) => {
        try { tl.close?.(false); } catch (_) {}
      });
    } catch (_) {}
  }

  """
    for a in (
        "  _easeWindowRect(window, destRect, user_op = false, force = false) {\n    // x47-null-window-actor",
        "  _easeWindowRect(window, destRect, user_op = false, force = false) {",
    ):
        if a in text:
            return text.replace(a, helper + a, 1)
    print("  WARN: could not insert _forceCloseOverlays", file=sys.stderr)
    return text


def patch_tiling_manager(root: Path) -> bool:
    path = root / "components/tilingsystem/tilingManager.js"
    text = path.read_text(encoding="utf-8")
    if "x47-tiling-stability-grab" in text:
        print("  skip tilingManager grab (already patched)")
        text = _ensure_force_close_helper(text)
        # still try anim skip below
    else:
        old_end = """  _onWindowGrabEnd(window) {
    this._isGrabbingWindow = false;
    this._grabStartPosition = null;
    this._signals.disconnect(window);
    TouchPointer.get().reset();
    const currentWs = window.get_workspace();
    const tilingLayout = this._workspaceTilingLayout.get(currentWs);
    if (tilingLayout) tilingLayout.close();
    const desiredWindowRect = buildRectangle({
      x: this._selectedTilesPreview.innerX,
      y: this._selectedTilesPreview.innerY,
      width: this._selectedTilesPreview.innerWidth,
      height: this._selectedTilesPreview.innerHeight
    });
    const selectedTilesRect = this._selectedTilesPreview.rect.copy();
    this._selectedTilesPreview.close(true);
    this._snapAssist.close(true);
    this._lastCursorPos = null;"""
        new_end = """  _onWindowGrabEnd(window) {
    // x47-tiling-stability-grab: snapshot tile rects, then always tear down overlays
    this._isGrabbingWindow = false;
    this._grabStartPosition = null;
    try { this._signals.disconnect(window); } catch (_) {}
    try { TouchPointer.get().reset(); } catch (_) {}
    let desiredWindowRect = null;
    let selectedTilesRect = null;
    try {
      desiredWindowRect = buildRectangle({
        x: this._selectedTilesPreview.innerX,
        y: this._selectedTilesPreview.innerY,
        width: this._selectedTilesPreview.innerWidth,
        height: this._selectedTilesPreview.innerHeight
      });
      selectedTilesRect = this._selectedTilesPreview.rect.copy();
    } catch (_) {}
    let currentWs = null;
    let tilingLayout = null;
    try {
      if (window)
        currentWs = window.get_workspace();
      if (currentWs)
        tilingLayout = this._workspaceTilingLayout.get(currentWs);
      if (tilingLayout)
        tilingLayout.close();
    } catch (_) {}
    this._forceCloseOverlays();
    this._lastCursorPos = null;
    if (!window || !desiredWindowRect || !selectedTilesRect)
      return;"""
        if old_end not in text:
            print("  WARN: _onWindowGrabEnd head not found", file=sys.stderr)
        else:
            text = text.replace(old_end, new_end, 1)

        text = _ensure_force_close_helper(text)

        # Guard moving-window timer when window is gone
        old_move = """  _onMovingWindow(window, grabOp) {
    if (!this._isGrabbingWindow) {
      this._movingWindowTimerId = null;
      return GLib.SOURCE_REMOVE;
    }
    const currentWs = window.get_workspace();"""
        new_move = """  _onMovingWindow(window, grabOp) {
    // x47-tiling-stability-grab
    if (!this._isGrabbingWindow) {
      this._movingWindowTimerId = null;
      return GLib.SOURCE_REMOVE;
    }
    if (!window) {
      this._forceCloseOverlays();
      this._movingWindowTimerId = null;
      this._isGrabbingWindow = false;
      return GLib.SOURCE_REMOVE;
    }
    let currentWs;
    try { currentWs = window.get_workspace(); } catch (_) {
      this._forceCloseOverlays();
      this._movingWindowTimerId = null;
      this._isGrabbingWindow = false;
      return GLib.SOURCE_REMOVE;
    }"""
        if old_move in text:
            text = text.replace(old_move, new_move, 1)
        else:
            print("  WARN: _onMovingWindow head not found", file=sys.stderr)

        # Soft workArea setter
        old_wa = """  set workArea(newWorkArea) {
    if (newWorkArea.equal(this._workArea)) return;
    this._workArea = newWorkArea;
    this._debug(
      `new work area for monitor ${this._monitor.index}: ${newWorkArea.x} ${newWorkArea.y} ${newWorkArea.width}x${newWorkArea.height}`
    );
    this._workspaceTilingLayout.forEach(
      (tl) => tl.relayout({ containerRect: this._workArea })
    );
    this._snapAssist.workArea = this._workArea;
    this._edgeTilingManager.workarea = this._workArea;
  }"""
        new_wa = """  set workArea(newWorkArea) {
    // x47-tiling-stability-grab
    if (newWorkArea.equal(this._workArea)) return;
    this._workArea = newWorkArea;
    this._debug(
      `new work area for monitor ${this._monitor.index}: ${newWorkArea.x} ${newWorkArea.y} ${newWorkArea.width}x${newWorkArea.height}`
    );
    try {
      this._workspaceTilingLayout.forEach(
        (tl) => tl.relayout({ containerRect: this._workArea })
      );
    } catch (_) {}
    try { this._snapAssist.workArea = this._workArea; } catch (_) {}
    try { this._edgeTilingManager.workarea = this._workArea; } catch (_) {}
  }"""
        if old_wa in text:
            text = text.replace(old_wa, new_wa, 1)

    # Skip _prepareAnimationInfo — conflicts with wobbly / size-change accounting
    if "x47-tiling-stability-no-anim-prep" not in text:
        old_prep = """    if (windowActor) {
      try {
        windowActor.remove_all_transitions();
        Main.wm._prepareAnimationInfo(
          global.windowManager,
          windowActor,
          beforeRect.copy(),
          Meta.SizeChange.UNMAXIMIZE
        );
      } catch (_) { /* animation prep is best-effort */ }
    }"""
        new_prep = """    // x47-tiling-stability-no-anim-prep: _prepareAnimationInfo races Compiz
    // wobbly and leaves "Error in size change accounting" + flaky landings
    if (windowActor) {
      try { windowActor.remove_all_transitions(); } catch (_) {}
    }"""
        if old_prep in text:
            text = text.replace(old_prep, new_prep, 1)
        else:
            # unpatched original
            old_prep2 = """    windowActor.remove_all_transitions();
    Main.wm._prepareAnimationInfo(
      global.windowManager,
      windowActor,
      beforeRect.copy(),
      Meta.SizeChange.UNMAXIMIZE
    );"""
            new_prep2 = """    // x47-tiling-stability-no-anim-prep
    if (windowActor) {
      try { windowActor.remove_all_transitions(); } catch (_) {}
    }"""
            if old_prep2 in text:
                text = text.replace(old_prep2, new_prep2, 1)
            else:
                print("  WARN: animation prep block not found", file=sys.stderr)

    path.write_text(text, encoding="utf-8")
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
    ok = patch_snap_assist(root) and ok
    ok = patch_tile_preview(root) and ok
    ok = patch_tiling_manager(root) and ok
    if MARKER:
        pass
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
