#!/usr/bin/env python3
"""Render the X47 knuckle-duster ASCII art onto the circuit wallpaper.

By default writes the teal (workspace 1) wallpaper. Pass --all to also write
the pink / blue / lime variants for workspaces 2–4 (used by the desktop-cube
workspace wallpaper switcher). Those three use loud solid backgrounds so each
workspace is unmistakable at a glance.

Usage:
  scripts/make-wallpaper.py               # teal only
  scripts/make-wallpaper.py --all         # all four
  scripts/make-wallpaper.py --color pink  # one colour
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = ROOT / "assets/desktop/x47-ascii.txt"
OUT_DIR = ROOT / "assets/desktop/wallpapers"
BG = ROOT / "assets/desktop/x47-circuit-bg.png"

W, H = 3840, 2160
ART_WIDTH_FRAC = 0.315
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# glow RGB (soft halo behind the art), sharp RGB (the art itself).
# "bg" = solid background colour; without it the circuit image is used.
COLOURS = {
    "teal": {
        "glow": (64, 224, 208),
        "sharp": (214, 246, 242),
        "out": "x47-circuit.png",
    },
    "pink": {  # workspace 2 — hot pink duster on white
        "glow": (255, 100, 170),
        "sharp": (235, 0, 110),
        "out": "x47-circuit-pink.png",
        "bg": (252, 250, 252),
        "stroke": (170, 0, 80),
    },
    "blue": {  # workspace 3 — white duster on light blue
        "glow": (255, 255, 255),
        "sharp": (255, 255, 255),
        "out": "x47-circuit-blue.png",
        "bg": (95, 190, 255),
    },
    "lime": {  # workspace 4 — white duster on lime green
        "glow": (255, 255, 255),
        "sharp": (255, 255, 255),
        "out": "x47-circuit-lime.png",
        "bg": (105, 220, 40),
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


def background(spec):
    if "bg" in spec:
        return Image.new("RGB", (W, H), spec["bg"])
    return Image.open(BG).convert("RGB").resize((W, H), Image.LANCZOS)


def draw_art(base, lines, font, glow_rgb, sharp_rgb, stroke_rgb=None):
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
        gd.text((x0, y0 + i * lh), ln, font=font, fill=(*glow_rgb, 255),
                stroke_width=3, stroke_fill=(*glow_rgb, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(6))

    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)
    stroke_kw = {}
    if stroke_rgb is not None:
        stroke_kw = {"stroke_width": 2, "stroke_fill": (*stroke_rgb, 255)}
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(*sharp_rgb, 255), **stroke_kw)

    out = base.convert("RGBA")
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def render(name: str, lines, font):
    spec = COLOURS[name]
    img = draw_art(
        background(spec),
        lines,
        font,
        spec["glow"],
        spec["sharp"],
        spec.get("stroke"),
    )
    out = OUT_DIR / spec["out"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"wrote {out} ({W}x{H}, {name})")
    return out


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--all", action="store_true", help="render all four variants")
    p.add_argument("--color", choices=list(COLOURS), default="teal")
    args = p.parse_args(argv)

    lines, cols, _rows = load_art(ASCII_FILE)
    font = fit_font(cols)
    names = list(COLOURS) if args.all else [args.color]
    for name in names:
        render(name, lines, font)


if __name__ == "__main__":
    main()
