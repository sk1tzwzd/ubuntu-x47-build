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
    "pink": {  # workspace 2 — bright pink duster on off-white circuit
        "sharp": (255, 25, 140),
        "bold": True,  # thicken the glyphs so the art fills out on the light bg
        "out": "x47-circuit-pink.png",
        "recolor": ((248, 246, 242), (168, 160, 172)),
    },
    "blue": {  # workspace 3 — crisp white duster on graded dark blue circuit
        "sharp": (255, 255, 255),
        "out": "x47-circuit-blue.png",
        "recolor": ((12, 40, 90), (58, 108, 185)),
        "grade": ((28, 80, 158), (105, 165, 235)),
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
    # --- amnesia (anon) session: black circuit + "anon@x47" ASCII text ---
    # Text is rendered with pyfiglet at build time (pip install pyfiglet);
    # the PNG is committed, so installs never need pyfiglet.
    "anon": {
        "sharp": (228, 234, 240),
        "out": "x47-anon.png",
        "carbon": True,
        "text": "anon@x47",
        "font": "ansi_shadow",
        "frac": 0.55,
    },
}


def load_art(path: Path):
    lines = path.read_text().rstrip("\n").split("\n")
    cols = max(len(ln) for ln in lines)
    return lines, cols, len(lines)


def art_for(spec):
    if "text" in spec:
        import pyfiglet  # build-time only; the rendered PNG is committed

        art = pyfiglet.figlet_format(spec["text"], font=spec.get("font", "chunky"))
        lines = art.rstrip("\n").split("\n")
        return lines, max(len(ln) for ln in lines)
    lines, cols, _rows = load_art(ASCII_FILE)
    return lines, cols


def fit_font(cols: int, frac: float = ART_WIDTH_FRAC):
    target = W * frac
    best = 8
    for size in range(8, 200):
        f = ImageFont.truetype(FONT_PATH, size)
        if f.getlength("M") * cols <= target:
            best = size
        else:
            break
    return ImageFont.truetype(FONT_PATH, best)


def carbon_background():
    """Dark carbon-fibre twill: 2x2 weave of alternating strand directions."""
    import math

    s = 26  # strand cell size at 4K
    shadow, base, sheen = (6, 6, 8), (13, 14, 16), (40, 43, 49)

    def strand(horizontal):
        cell = Image.new("RGB", (s, s))
        d = ImageDraw.Draw(cell)
        for i in range(s):
            t = math.sin(math.pi * (i + 0.5) / s)
            c = tuple(round(sh + (hi - sh) * t) for sh, hi in zip(shadow, sheen))
            if horizontal:
                d.line([(0, i), (s, i)], fill=c)
            else:
                d.line([(i, 0), (i, s)], fill=c)
        return cell

    h, v = strand(True), strand(False)
    tile = Image.new("RGB", (2 * s, 2 * s), base)
    tile.paste(h, (0, 0)); tile.paste(v, (s, 0))
    tile.paste(v, (0, s)); tile.paste(h, (s, s))

    img = Image.new("RGB", (W, H))
    for x in range(0, W, 2 * s):
        for y in range(0, H, 2 * s):
            img.paste(tile, (x, y))
    img = img.filter(ImageFilter.GaussianBlur(0.6))

    # Soft vignette so the centre (behind the text) reads slightly lifted.
    mask = Image.radial_gradient("L").resize((W, H))
    return Image.composite(Image.new("RGB", (W, H), (2, 2, 3)), img,
                           mask.point(lambda p: min(255, int(p * 0.55))))


def background(spec):
    if spec.get("carbon"):
        return carbon_background()
    img = Image.open(BG).convert("RGB").resize((W, H), Image.LANCZOS)
    if "recolor" not in spec:
        return img
    shadow, trace = spec["recolor"]
    gray = ImageOps.autocontrast(img.convert("L"))
    base = ImageOps.colorize(gray, black=shadow, white=trace)
    grade = spec.get("grade")
    if grade is None:
        return base
    # "grade" = second (shadow, trace) ramp blended in from top to bottom,
    # giving a smooth vertical colour gradient that keeps the circuit pattern.
    lower = ImageOps.colorize(gray, black=grade[0], white=grade[1])
    mask = Image.linear_gradient("L").resize((W, H))
    return Image.composite(lower, base, mask)


def draw_art(base, lines, font, sharp_rgb, glow_rgb=None, bold=False):
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
    # A 1px same-colour stroke fattens the glyphs without any blur.
    bold_kw = {"stroke_width": 1, "stroke_fill": (*sharp_rgb, 255)} if bold else {}
    for i, ln in enumerate(lines):
        sd.text((x0, y0 + i * lh), ln, font=font, fill=(*sharp_rgb, 255), **bold_kw)
    out = Image.alpha_composite(out, sharp)
    return out.convert("RGB")


def render(name: str):
    spec = COLOURS[name]
    lines, cols = art_for(spec)
    font = fit_font(cols, spec.get("frac", ART_WIDTH_FRAC))
    img = draw_art(
        background(spec),
        lines,
        font,
        spec["sharp"],
        spec.get("glow"),
        spec.get("bold", False),
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

    names = list(COLOURS) if args.all else [args.color]
    for name in names:
        render(name)


if __name__ == "__main__":
    main()
