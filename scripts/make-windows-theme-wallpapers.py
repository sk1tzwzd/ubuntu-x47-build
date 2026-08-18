#!/usr/bin/env python3
"""Original (non-Microsoft) 4K wallpapers for the X47 Windows theme kit."""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

W, H = 3840, 2160
OUT = Path(__file__).resolve().parents[1] / "windows" / "assets" / "wallpapers"


def _lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))  # type: ignore[return-value]


def _vgrad(top: tuple[int, int, int], bot: tuple[int, int, int]) -> Image.Image:
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        c = _lerp(top, bot, y / (H - 1))
        for x in range(W):
            px[x, y] = c
    return im


def _hill(draw: ImageDraw.ImageDraw, y0: int, amp: int, freq: float, phase: float, color, width: int = 6) -> None:
    pts = []
    for x in range(0, W + 8, 8):
        y = int(y0 + amp * math.sin(x / freq + phase) + amp * 0.35 * math.sin(x / (freq * 1.7) + phase * 1.3))
        pts.append((x, y))
    pts += [(W, H), (0, H)]
    draw.polygon(pts, fill=color)


def bliss(path: Path, *, dusk: bool = False) -> None:
    if dusk:
        sky = _vgrad((42, 72, 128), (232, 176, 118))
    else:
        sky = _vgrad((74, 148, 214), (196, 224, 246))
    d = ImageDraw.Draw(sky, "RGBA")
    # Soft original clouds — not the Bliss photo.
    for cx, cy, rx, ry in (
        (620, 420, 340, 90),
        (900, 390, 280, 70),
        (2200, 360, 420, 100),
        (2600, 410, 260, 70),
        (3100, 520, 300, 80),
    ):
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(255, 255, 255, 70 if dusk else 110))
    hills = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hills)
    if dusk:
        layers = (
            (1180, 90, 520, 0.4, (46, 78, 52)),
            (1320, 70, 380, 1.1, (58, 102, 54)),
            (1480, 55, 300, 2.2, (78, 128, 58)),
            (1680, 40, 240, 0.7, (112, 154, 64)),
        )
    else:
        layers = (
            (1200, 85, 540, 0.5, (52, 110, 48)),
            (1360, 68, 400, 1.3, (70, 138, 52)),
            (1520, 50, 310, 2.0, (96, 162, 58)),
            (1700, 38, 230, 0.8, (132, 186, 70)),
        )
    for y0, amp, freq, phase, col in layers:
        _hill(hd, y0, amp, freq, phase, col)
    sky = Image.alpha_composite(sky.convert("RGBA"), hills).convert("RGB")
    sky = sky.filter(ImageFilter.GaussianBlur(0.6))
    sky.save(path, "PNG", optimize=True)


def aurora(path: Path) -> None:
    im = _vgrad((4, 10, 8), (10, 28, 18))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for i, (y, col, a) in enumerate((
        (380, (80, 220, 170), 36),
        (520, (40, 180, 140), 28),
        (700, (20, 90, 70), 22),
        (900, (120, 200, 90), 18),
    )):
        pts = []
        for x in range(0, W + 12, 12):
            yy = int(y + 70 * math.sin(x / 280.0 + i) + 40 * math.sin(x / 140.0 + i * 0.7))
            pts.append((x, yy))
        pts += [(W, y + 220), (0, y + 220)]
        d.polygon(pts, fill=col + (a,))
    im = Image.alpha_composite(im.convert("RGBA"), overlay)
    im = im.filter(ImageFilter.GaussianBlur(8)).convert("RGB")
    im.save(path, "PNG", optimize=True)


def bloom(path: Path) -> None:
    im = _vgrad((228, 232, 240), (176, 196, 220))
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    blobs = (
        (900, 700, 820, (90, 140, 210, 50)),
        (2500, 900, 980, (160, 130, 210, 40)),
        (1900, 400, 640, (70, 170, 200, 35)),
        (3000, 1600, 700, (100, 150, 190, 30)),
    )
    for x, y, r, col in blobs:
        d.ellipse((x - r, y - r, x + r, y + r), fill=col)
    im = Image.alpha_composite(im.convert("RGBA"), overlay)
    im = im.filter(ImageFilter.GaussianBlur(48)).convert("RGB")
    im.save(path, "PNG", optimize=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bliss(OUT / "theme-xp.png", dusk=False)
    bliss(OUT / "theme-xp-remastered.png", dusk=True)
    aurora(OUT / "theme-vista.png")
    bloom(OUT / "theme-win11.png")
    print(f"wrote wallpapers in {OUT}")


if __name__ == "__main__":
    main()
