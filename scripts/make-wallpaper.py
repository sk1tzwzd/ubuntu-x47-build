#!/usr/bin/env python3
"""Render the X47 knuckle-duster ASCII art into a desktop wallpaper.

Teal monospace glyphs with a soft glow on a deep charcoal background with a
subtle vignette — matches the rest of the X47 desktop theme. Reproducible:
edit assets/desktop/x47-ascii.txt and re-run.

Usage: scripts/make-wallpaper.py [ascii_file] [out_png]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/desktop/x47-ascii.txt"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "assets/desktop/wallpapers/x47-circuit.png"

W, H = 3840, 2160
MARGIN = 260
BG_TOP = (10, 15, 20)
BG_BOTTOM = (6, 10, 13)
TEAL = (64, 224, 208)
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"


def load_art(path):
    lines = path.read_text().rstrip("\n").split("\n")
    cols = max(len(ln) for ln in lines)
    return lines, cols, len(lines)


def fit_font(cols, rows):
    """Largest font size whose monospace grid fits inside the margins."""
    best = 10
    for size in range(10, 200):
        f = ImageFont.truetype(FONT_PATH, size)
        cw = f.getlength("M")
        # DejaVu Sans Mono line advance ~1.17x em; keep art tight.
        ascent, descent = f.getmetrics()
        lh = ascent + descent
        if cw * cols <= (W - 2 * MARGIN) and lh * rows <= (H - 2 * MARGIN):
            best = size
        else:
            break
    return ImageFont.truetype(FONT_PATH, best)


def background():
    img = Image.new("RGB", (W, H), BG_TOP)
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
        g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
        b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    # Radial vignette to darken the corners.
    vig = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-W * 0.25, -H * 0.25, W * 1.25, H * 1.25], fill=90)
    vig = vig.filter(ImageFilter.GaussianBlur(400))
    dark = Image.new("RGB", (W, H), (0, 0, 0))
    return Image.composite(img, dark, vig)


def draw_art(base, lines, font):
    cw = font.getlength("M")
    ascent, descent = font.getmetrics()
    lh = ascent + descent
    block_w = cw * max(len(ln) for ln in lines)
    block_h = lh * len(lines)
    x0 = (W - block_w) / 2
    y0 = (H - block_h) / 2

    # Glow layer: draw text, blur, tint teal, composite.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for i, ln in enumerate(lines):
        gd.text((x0, y0 + i * lh), ln, font=font, fill=(64, 224, 208, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(9))

    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(210, 245, 240, 255))

    out = base.convert("RGBA")
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, glow)  # double for a stronger halo
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def main():
    lines, cols, rows = load_art(ASCII_FILE)
    font = fit_font(cols, rows)
    img = draw_art(background(), lines, font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({W}x{H}, font {font.size}pt, art {cols}x{rows})")


if __name__ == "__main__":
    main()
