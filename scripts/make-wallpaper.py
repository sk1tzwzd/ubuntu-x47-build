#!/usr/bin/env python3
"""Render the X47 knuckle-duster ASCII art onto the circuit wallpaper.

By default writes the teal (workspace 1) wallpaper. Pass --all to also write
the pink / blue / green variants for workspaces 2–4 (used by the desktop-cube
workspace wallpaper switcher). All four share the exact same circuit pattern
and crisp ASCII duster; only the colours differ.

Usage:
  scripts/make-wallpaper.py               # teal only
  scripts/make-wallpaper.py --all         # all four
  scripts/make-wallpaper.py --color pink  # one colour
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = ROOT / "assets/desktop/x47-ascii.txt"
OUT_DIR = ROOT / "assets/desktop/wallpapers"
BG = ROOT / "assets/desktop/x47-circuit-bg.png"

W, H = 3840, 2160
ART_WIDTH_FRAC = 0.315
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# sharp RGB = the ASCII art itself; "glow" (optional) adds the soft halo the
# original teal wallpaper has — omitted on the light variants so the duster
# stays razor sharp.
# "recolor" = (shadow RGB, trace RGB): the circuit background is converted to
# grayscale and remapped onto that ramp, keeping the exact same pattern.
# Without "recolor" the original dark circuit image is used untouched.
COLOURS = {
    # --- preset workspaces 1-4 ---
    "teal": {  # workspace 1 — teal duster on the original dark circuit
        "glow": (64, 224, 208),
        "sharp": (214, 246, 242),
        "out": "x47-circuit.png",
    },
    "pink": {  # workspace 2 — pink duster on white circuit
        "sharp": (230, 20, 120),
        "out": "x47-circuit-pink.png",
        "recolor": ((250, 248, 250), (150, 145, 158)),
    },
    "blue": {  # workspace 3 — dark red duster on bright baby blue circuit
        "sharp": (140, 10, 25),
        "out": "x47-circuit-blue.png",
        "recolor": ((110, 195, 255), (225, 245, 255)),
    },
    "green": {  # workspace 4 — white duster on medium-dark green circuit
        "sharp": (255, 255, 255),
        "out": "x47-circuit-green.png",
        "recolor": ((20, 95, 45), (115, 205, 135)),
    },
    # --- extra colourways, assigned randomly to workspaces beyond 4 ---
    "orange": {
        "sharp": (255, 255, 255),
        "out": "x47-circuit-orange.png",
        "recolor": ((205, 105, 15), (255, 190, 110)),
    },
    "purple": {
        "sharp": (255, 255, 255),
        "out": "x47-circuit-purple.png",
        "recolor": ((70, 30, 110), (165, 115, 225)),
    },
    "yellow": {
        "sharp": (45, 45, 55),
        "out": "x47-circuit-yellow.png",
        "recolor": ((235, 200, 30), (255, 240, 150)),
    },
    "red": {
        "sharp": (255, 255, 255),
        "out": "x47-circuit-red.png",
        "recolor": ((125, 18, 25), (225, 95, 95)),
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
    img = Image.open(BG).convert("RGB").resize((W, H), Image.LANCZOS)
    if "recolor" not in spec:
        return img
    shadow, trace = spec["recolor"]
    gray = ImageOps.autocontrast(img.convert("L"))
    return ImageOps.colorize(gray, black=shadow, white=trace)


def draw_art(base, lines, font, sharp_rgb, glow_rgb=None):
    cw = font.getlength("M")
    ascent, descent = font.getmetrics()
    lh = ascent + descent
    block_w = cw * max(len(ln) for ln in lines)
    block_h = lh * len(lines)
    x0 = (W - block_w) / 2
    y0 = (H - block_h) / 2

    out = base.convert("RGBA")

    if glow_rgb is not None:
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        for i, ln in enumerate(lines):
            gd.text((x0, y0 + i * lh), ln, font=font, fill=(*glow_rgb, 255))
        glow = glow.filter(ImageFilter.GaussianBlur(6))
        out = Image.alpha_composite(out, glow)

    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(*sharp_rgb, 255))
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def render(name: str, lines, font):
    spec = COLOURS[name]
    img = draw_art(
        background(spec),
        lines,
        font,
        spec["sharp"],
        spec.get("glow"),
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
