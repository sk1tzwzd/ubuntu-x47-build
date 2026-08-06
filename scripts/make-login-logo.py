#!/usr/bin/env python3
"""Render the X47 ASCII knuckle-duster as a transparent GDM login logo."""
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = ROOT / "assets/desktop/x47-ascii.txt"
OUT = ROOT / "assets/desktop/x47-login-duster.png"
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

# Match the teal wallpaper duster.
SHARP = (214, 246, 242)
GLOW = (64, 224, 208)
TARGET_WIDTH = 420  # GDM logo sits above the user list; keep it modest.


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--out", type=Path, default=OUT)
    p.add_argument("--width", type=int, default=TARGET_WIDTH)
    args = p.parse_args(argv)

    lines = ASCII_FILE.read_text().rstrip("\n").split("\n")
    cols = max(len(ln) for ln in lines)

    # Render large, then downscale for crisp monospace edges.
    font = ImageFont.truetype(FONT_PATH, 18)
    cw = font.getlength("M")
    ascent, descent = font.getmetrics()
    lh = ascent + descent
    pad = 24
    w = int(cw * cols + pad * 2)
    h = int(lh * len(lines) + pad * 2)

    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    sd = ImageDraw.Draw(canvas)
    for i, ln in enumerate(lines):
        xy = (pad, pad + i * lh)
        gd.text(xy, ln, font=font, fill=(*GLOW, 255))
        sd.text(xy, ln, font=font, fill=(*SHARP, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(4))
    out = Image.alpha_composite(glow, canvas)

    # Crop to ink + small margin.
    bbox = out.getbbox()
    if bbox:
        l, t, r, b = bbox
        m = 12
        out = out.crop((max(0, l - m), max(0, t - m), min(w, r + m), min(h, b + m)))

    if out.width > args.width:
        nh = max(1, round(out.height * (args.width / out.width)))
        out = out.resize((args.width, nh), Image.LANCZOS)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.save(args.out)
    print(f"wrote {args.out} ({out.width}x{out.height})")


if __name__ == "__main__":
    main()
