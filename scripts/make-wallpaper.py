#!/usr/bin/env python3
"""Render the X47 knuckle-duster ASCII art onto the circuit wallpaper.

The ASCII duster is drawn as glowing teal monospace text, centered small with
plenty of negative space, over the bundled dark-minimal circuit background
(assets/desktop/x47-circuit-bg.png). Reproducible: edit
assets/desktop/x47-ascii.txt (or the background) and re-run.

Usage: scripts/make-wallpaper.py [ascii_file] [out_png] [bg_png]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASCII_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "assets/desktop/x47-ascii.txt"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "assets/desktop/wallpapers/x47-circuit.png"
BG = Path(sys.argv[3]) if len(sys.argv) > 3 else ROOT / "assets/desktop/x47-circuit-bg.png"

W, H = 3840, 2160
# Fraction of canvas width the ASCII block should span (keeps it small with
# generous negative space, like the original centered logo).
ART_WIDTH_FRAC = 0.315
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"


def load_art(path):
    lines = path.read_text().rstrip("\n").split("\n")
    cols = max(len(ln) for ln in lines)
    return lines, cols, len(lines)


def fit_font(cols):
    """Largest font whose monospace grid spans ART_WIDTH_FRAC of the canvas."""
    target = W * ART_WIDTH_FRAC
    best = 8
    for size in range(8, 120):
        f = ImageFont.truetype(FONT_PATH, size)
        if f.getlength("M") * cols <= target:
            best = size
        else:
            break
    return ImageFont.truetype(FONT_PATH, best)


def background():
    img = Image.open(BG).convert("RGB").resize((W, H), Image.LANCZOS)
    return img


def draw_art(base, lines, font):
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
        gd.text((x0, y0 + i * lh), ln, font=font, fill=(64, 224, 208, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(6))

    sharp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sharp)
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(214, 246, 242, 255))

    out = base.convert("RGBA")
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def main():
    lines, cols, rows = load_art(ASCII_FILE)
    font = fit_font(cols)
    img = draw_art(background(), lines, font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"wrote {OUT} ({W}x{H}, font {font.size}pt, art {cols}x{rows})")


if __name__ == "__main__":
    main()
