#!/usr/bin/env python3
"""Render the X47 knuckle-duster ASCII art onto the circuit wallpaper.

By default writes the teal (workspace 1) wallpaper. Pass --all to also write
green / red / purple variants for workspaces 2–4 (used by the desktop-cube
workspace wallpaper switcher).

Usage:
  scripts/make-wallpaper.py              # teal only
  scripts/make-wallpaper.py --all        # teal + green + red + purple
  scripts/make-wallpaper.py --color red  # one colour
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = ROOT / "assets/desktop/x47-ascii.txt"
OUT_DIR = ROOT / "assets/desktop/wallpapers"
BG = ROOT / "assets/desktop/x47-circuit-bg.png"

W, H = 3840, 2160
ART_WIDTH_FRAC = 0.315
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# glow RGB, sharp RGB, optional background colourize (hue factor 0–1, None=skip)
COLOURS = {
    "teal": {
        "glow": (64, 224, 208),
        "sharp": (214, 246, 242),
        "out": "x47-circuit.png",
        "tint": None,  # keep original circuit
    },
    "green": {
        "glow": (48, 220, 96),
        "sharp": (200, 255, 210),
        "out": "x47-circuit-green.png",
        "tint": (0.33, 1.15),  # hue toward green, slight sat boost
    },
    "red": {
        "glow": (255, 64, 72),
        "sharp": (255, 210, 210),
        "out": "x47-circuit-red.png",
        "tint": (0.0, 1.2),
    },
    "purple": {
        "glow": (180, 96, 255),
        "sharp": (230, 210, 255),
        "out": "x47-circuit-purple.png",
        "tint": (0.78, 1.15),
    },
}


def load_art(path: Path):
    lines = path.read_text().rstrip("\n").split("\n")
    cols = max(len(ln) for ln in lines)
    return lines, cols, len(lines)


def fit_font(cols: int):
    target = W * ART_WIDTH_FRAC
    best = 8
    for size in range(8, 120):
        f = ImageFont.truetype(FONT_PATH, size)
        if f.getlength("M") * cols <= target:
            best = size
        else:
            break
    return ImageFont.truetype(FONT_PATH, best)


def background(tint):
    img = Image.open(BG).convert("RGB").resize((W, H), Image.LANCZOS)
    if tint is None:
        return img
    # Cheap colour wash: blend a translucent colour overlay matching the theme.
    hue_hint, sat = tint
    # Map hue hint to an RGB wash colour.
    if hue_hint < 0.1:  # red
        wash = (90, 18, 22)
    elif hue_hint < 0.4:  # green
        wash = (12, 70, 28)
    else:  # purple
        wash = (48, 16, 80)
    overlay = Image.new("RGB", (W, H), wash)
    img = Image.blend(img, overlay, 0.28)
    img = ImageEnhance.Color(img).enhance(sat)
    return img


def draw_art(base, lines, font, glow_rgb, sharp_rgb):
    cw = font.getlength("M")
    ascent, descent = font.getmetrics()
    lh = ascent + descent
    block_w = cw * max(len(ln) for ln in lines)
    block_h = lh * len(lines)
    x0 = (W - block_w) / 2
    y0 = (H - block_h) / 2

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i, ln in enumerate(lines):
        gd.text((x0, y0 + i * lh), ln, font=font, fill=(*glow_rgb, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(6))

    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(*sharp_rgb, 255))

    out = base.convert("RGBA")
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def render(name: str, lines, font):
    spec = COLOURS[name]
    img = draw_art(
        background(spec["tint"]),
        lines,
        font,
        spec["glow"],
        spec["sharp"],
    )
    out = OUT_DIR / spec["out"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"wrote {out} ({W}x{H}, {name})")
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--all", action="store_true", help="render teal+green+red+purple")
    p.add_argument("--color", choices=list(COLOURS), default="teal")
    args = p.parse_args(argv)

    lines, cols, _rows = load_art(ASCII_FILE)
    font = fit_font(cols)
    names = list(COLOURS) if args.all else [args.color]
    for name in names:
        render(name, lines, font)


if __name__ == "__main__":
    main()
