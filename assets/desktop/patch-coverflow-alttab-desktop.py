#!/usr/bin/env python3
"""Patch Coverflow Alt-Tab so Alt+Tab past the last window selects Desktop.

Idempotent. Re-run after Coverflow updates / reinstalls.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "x47-alt-tab-desktop"

SWITCHER_INIT = "        this._qPressed = false;"
SWITCHER_INIT_X47 = (
    "        this._qPressed = false;\n"
    f"        this._x47Desktop = false; // {MARKER}"
)

ACTIVATE_OLD = """    _activateSelected(reset_current_window_title) {
        this._swipeTracker.enabled = false;
        let preview = this._previews[this._currentIndex];"""

ACTIVATE_NEW = f"""    _activateSelected(reset_current_window_title) {{
        // {MARKER}: selecting past the last window shows the desktop
        if (this._x47Desktop) {{
            this._showDesktop();
            return;
        }}
        this._swipeTracker.enabled = false;
        let preview = this._previews[this._currentIndex];"""

PREVIEW_NEXT_OLD = """    _previewNext() {
        if (this._currentIndex === this._windows.length - 1) {
            this._setCurrentIndex(0);
            if (this._usingCarousel()) {
                this._updatePreviews(false)
            } else {
                this._flipStack(Direction.TO_LEFT);
            }
        } else {
            this._setCurrentIndex(this._currentIndex + 1);
            this._updatePreviews(false);
        }
    }"""

PREVIEW_NEXT_NEW = f"""    _previewNext() {{
        // {MARKER}: one step past the last window = Desktop
        if (this._x47Desktop) {{
            this._x47Desktop = false;
            for (let p of this._allPreviews)
                p.ease({{opacity: 255, duration: 150}});
            if (this._windowTitles[this._currentIndex] && this._windows[this._currentIndex])
                this._windowTitles[this._currentIndex].text = this._windows[this._currentIndex].get_title();
            this._setCurrentIndex(0);
            if (this._usingCarousel()) {{
                this._updatePreviews(false)
            }} else {{
                this._flipStack(Direction.TO_LEFT);
            }}
            return;
        }}
        if (this._currentIndex === this._windows.length - 1) {{
            this._x47Desktop = true;
            for (let p of this._allPreviews)
                p.ease({{opacity: 0, duration: 150}});
            if (this._windowTitles[this._currentIndex])
                this._windowTitles[this._currentIndex].text = 'Desktop';
            return;
        }}
        this._setCurrentIndex(this._currentIndex + 1);
        this._updatePreviews(false);
    }}"""

PREVIEW_PREV_OLD = """    _previewPrevious() {
        if (this._currentIndex === 0) {
            this._setCurrentIndex(this._windows.length-1);
            if (this._usingCarousel()) {
                this._updatePreviews(false)
            } else {
                this._flipStack(Direction.TO_RIGHT);
            }
        } else {
            this._setCurrentIndex(this._currentIndex - 1);
            this._updatePreviews(false);
        }
    }"""

PREVIEW_PREV_NEW = f"""    _previewPrevious() {{
        // {MARKER}
        if (this._x47Desktop) {{
            this._x47Desktop = false;
            for (let p of this._allPreviews)
                p.ease({{opacity: 255, duration: 150}});
            if (this._windowTitles[this._currentIndex] && this._windows[this._currentIndex])
                this._windowTitles[this._currentIndex].text = this._windows[this._currentIndex].get_title();
            return;
        }}
        if (this._currentIndex === 0) {{
            this._setCurrentIndex(this._windows.length-1);
            if (this._usingCarousel()) {{
                this._updatePreviews(false)
            }} else {{
                this._flipStack(Direction.TO_RIGHT);
            }}
        }} else {{
            this._setCurrentIndex(this._currentIndex - 1);
            this._updatePreviews(false);
        }}
    }}"""


def patch_file(path: Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")
    # Unique marker line from the replacement, if any
    marker_line = next((ln for ln in new.splitlines() if MARKER in ln), None)
    if marker_line and marker_line in text:
        print(f"  skip {label} (already patched)")
        return True
    if old not in text:
        print(f"  WARN: pattern not found for {label} in {path}", file=sys.stderr)
        return False
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  patched {label}")
    return True


def main() -> int:
    root = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else Path.home()
        / ".local/share/gnome-shell/extensions/CoverflowAltTab@palatis.blogspot.com"
    )
    if not root.is_dir():
        print(f"Coverflow not installed at {root}", file=sys.stderr)
        return 1

    switcher = root / "switcher.js"
    coverflow = root / "coverflowSwitcher.js"
    ok = True
    print(f"patching {root}")
    ok &= patch_file(switcher, SWITCHER_INIT, SWITCHER_INIT_X47, "switcher init")
    ok &= patch_file(switcher, ACTIVATE_OLD, ACTIVATE_NEW, "activateSelected")
    ok &= patch_file(coverflow, PREVIEW_NEXT_OLD, PREVIEW_NEXT_NEW, "previewNext")
    ok &= patch_file(coverflow, PREVIEW_PREV_OLD, PREVIEW_PREV_NEW, "previewPrevious")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
