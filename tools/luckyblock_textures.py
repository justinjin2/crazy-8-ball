#!/usr/bin/env python3
"""Paint the colour maps for our own lucky blocks (designer, 2026-10-07).

Each block is a set of pieces (tools/luckyblock_build.py): Frame (the edge bars), Corners (the
corner cubes), Core (the face panels), Glyph (the raised "?"), and on some kinds Disc (an 8-ball
circle or a clock), Ribbon, Topper (bow, crown, halo), Base (cloud) and Wings. Every piece is
box-mapped, so each face shows the whole square texture: u runs left to right and v bottom to top
as you look at that face. The approved concept icons set the colours
(~/Desktop/8ball-refs/lucky-blocks/).

    python3 tools/luckyblock_textures.py [kind ...]     # every kind when none is named

Writes assets/luckyblocks/build/<kind>/<piece>.png (512 x 512) and
assets/luckyblocks/textures/rainbow_scroll.png.
"""
import colorsys
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "luckyblocks", "build")
SIZE = 512


def g(top, bottom, sheen=0.3):
    return {"Top": top, "Bottom": bottom, "Sheen": sheen}


GOLD = g((255, 222, 96), (232, 162, 30), 0.35)
WHITE_GLYPH = g((255, 255, 255), (236, 236, 244), 0.15)

# A piece's paint: a vertical gradient ("Top", "Bottom", RGB 0-255), "Rainbow", "Pastel"
# (iridescent bands), "Cracks" (glowing veins over a gradient), "Image" ("Disc8", "Clock") or
# "Tips" (wings: the middle colour out to the tip colour). Sheen adds the concept icons' soft
# glossy light from the upper left. Corners default to the Frame's paint.
KINDS = {
    "standard": {
        # Close to the pack's original (designer, 2026-10-07): beige rims ("more beige than
        # gold"), brown faces that darken toward the bottom, white "?".
        "Frame": g((240, 224, 188), (206, 184, 140)),
        "Core": g((156, 100, 48), (72, 40, 16), 0.22),
        "Glyph": WHITE_GLYPH,
    },
    "uncommon": {
        "Frame": g((60, 190, 90), (22, 120, 52)),
        "Core": g((140, 230, 80), (66, 176, 40), 0.4),
        "Glyph": g((236, 255, 236), (196, 240, 204), 0.15),
    },
    "rare": {
        "Frame": g((48, 84, 190), (26, 46, 128)),
        "Corners": g((160, 220, 255), (84, 166, 244)),
        "Core": g((52, 136, 250), (22, 84, 206), 0.4),
        "Glyph": WHITE_GLYPH,
    },
    "epic": {
        "Frame": g((52, 50, 86), (20, 20, 42)),
        "Corners": g((200, 136, 255), (140, 72, 232)),
        "Core": {"Cracks": (196, 132, 255), "Top": (66, 24, 120), "Bottom": (30, 8, 62), "Sheen": 0.12},
        "Glyph": g((246, 228, 255), (208, 172, 255), 0.15),
    },
    "legendary": {
        "Frame": GOLD,
        "Corners": g((255, 160, 50), (222, 100, 12)),
        "Core": g((255, 180, 60), (236, 112, 12), 0.4),
        "Glyph": g((255, 244, 150), (255, 210, 80), 0.15),
        "Wings": {"Tips": ((255, 236, 150), (232, 158, 36))},
    },
    "grandopening": {
        "Frame": g((255, 208, 64), (226, 150, 20)),
        "Core": g((255, 220, 76), (242, 172, 30), 0.4),
        "Glyph": g((255, 248, 200), (250, 226, 150), 0.15),
        "Topper": g((255, 230, 100), (226, 160, 30), 0.45),
    },
    "eightball": {
        "Frame": g((240, 242, 248), (150, 156, 172), 0.45),
        "Core": g((40, 40, 46), (10, 10, 12), 0.2),
        "Glyph": g((244, 244, 248), (186, 190, 202), 0.2),
        "Disc": {"Image": "Disc8"},
    },
    "starter": {
        "Frame": g((236, 48, 48), (172, 16, 22)),
        "Core": g((228, 40, 40), (162, 16, 22), 0.35),
        "Glyph": WHITE_GLYPH,
        "Ribbon": GOLD,
        "Topper": GOLD,
    },
    "gift": {
        "Frame": GOLD,
        "Core": g((255, 255, 255), (222, 226, 240), 0.2),
        "Glyph": g((255, 220, 80), (236, 166, 30), 0.2),
        "Ribbon": GOLD,
        "Topper": GOLD,
        "Disc": {"Image": "Clock"},
    },
    "mythic": {
        "Frame": g((255, 238, 176), (236, 202, 120)),
        "Core": {"Pastel": True, "Sheen": 0.35},
        "Glyph": g((255, 255, 255), (238, 232, 252), 0.15),
        "Topper": g((255, 240, 140), (255, 204, 70), 0.4),
        "Wings": {"Tips": ((255, 255, 255), "Pastel")},
    },
    "sky": {
        "Frame": g((255, 255, 255), (222, 234, 250), 0.2),
        "Corners": g((196, 234, 255), (140, 202, 250)),
        "Core": g((116, 204, 255), (60, 150, 240), 0.4),
        "Glyph": WHITE_GLYPH,
        "Base": g((255, 255, 255), (212, 226, 246), 0.2),
        "Wings": {"Tips": ((255, 255, 255), (214, 232, 252))},
    },
    "mystery": {
        "Frame": {"Rainbow": True, "Sheen": 0.3},
        "Core": g((22, 24, 44), (8, 8, 18), 0.18),
        "Glyph": {"Rainbow": True, "Vertical": True, "Sheen": 0.25},
    },
}


def grid():
    y, x = np.mgrid[0:SIZE, 0:SIZE] / (SIZE - 1)
    return x, y  # y = 0 is the top of the image


def gradient(top, bottom):
    v = np.linspace(0.0, 1.0, SIZE)[:, None, None]
    top, bottom = np.array(top, float), np.array(bottom, float)
    return np.broadcast_to(top * (1 - v) + bottom * v, (SIZE, SIZE, 3)).copy()


def ramp(t, saturation=0.85, value=1.0, span=0.85):
    """Hue from red to violet (span < 1 never wraps back to red)."""
    table = np.array([colorsys.hsv_to_rgb(h, saturation, value) for h in np.linspace(0, span, 256)])
    return table[(np.clip(t, 0, 1) * 255).astype(int)] * 255


def rainbow(vertical):
    x, y = grid()
    return ramp(y if vertical else (x + (1 - y)) / 2)


def pastel():
    """Soft iridescent bands, pink to lavender to mint to sky blue and back."""
    x, y = grid()
    t = (x * 0.8 + y * 0.6 + 0.12 * np.sin(x * 9) * np.cos(y * 7)) % 1.0
    table = np.array([colorsys.hsv_to_rgb(h, 0.28, 1.0) for h in np.linspace(0, 1, 256, endpoint=False)])
    return table[(t * 255).astype(int)] * 255


def cracks(spec):
    """Glowing veins over a dark gradient: random walks that branch, the same every run."""
    img = gradient(spec["Top"], spec["Bottom"])
    layer = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(layer)
    rng = np.random.default_rng(7)
    for _ in range(7):
        x, y = rng.uniform(0, SIZE, 2)
        angle = rng.uniform(0, 2 * np.pi)
        for _step in range(9):
            angle += rng.uniform(-0.8, 0.8)
            nx, ny = x + np.cos(angle) * 46, y + np.sin(angle) * 46
            draw.line([(x, y), (nx, ny)], fill=255, width=5)
            if rng.random() < 0.3:
                b = angle + rng.choice([-1.1, 1.1])
                draw.line([(nx, ny), (nx + np.cos(b) * 34, ny + np.sin(b) * 34)], fill=200, width=3)
            x, y = nx, ny
    core = np.asarray(layer, float) / 255
    glow = np.asarray(layer.filter(ImageFilter.GaussianBlur(9)), float) / 255
    colour = np.array(spec["Cracks"], float)
    img = img * (1 - glow[..., None] * 0.7) + colour * glow[..., None] * 0.7
    return img * (1 - core[..., None]) + np.array((246, 226, 255)) * core[..., None]


def tips(middle, tip):
    """Wings: the middle colour near the hinge out to the tips (both ends of u)."""
    x, y = grid()
    t = np.clip((np.abs(x - 0.5) * 2 - 0.35) / 0.65, 0, 1)[..., None]
    mid = np.array(middle, float)
    if tip == "Pastel":
        end = ramp(1 - y, saturation=0.35, span=1.0)
    else:
        end = np.broadcast_to(np.array(tip, float), (SIZE, SIZE, 3))
    return mid * (1 - t) + end * t


def font(size):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Black.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def disc8():
    """A white 8-ball circle with a bold black 8 (the disc's face fills the whole square)."""
    img = Image.new("RGB", (SIZE, SIZE), (248, 248, 250))
    d = ImageDraw.Draw(img)
    d.ellipse([18, 18, SIZE - 18, SIZE - 18], outline=(206, 208, 216), width=10)
    d.text((SIZE / 2, SIZE / 2 + 8), "8", font=font(330), fill=(16, 16, 20), anchor="mm")
    return np.asarray(img, float)


def clock():
    """A gold-rimmed clock: white dial, ticks, black hands at 12 and 2 (gold outside the rim)."""
    img = Image.new("RGB", (SIZE, SIZE), (238, 176, 34))
    d = ImageDraw.Draw(img)
    c = SIZE / 2
    d.ellipse([0, 0, SIZE, SIZE], fill=(255, 214, 72))
    d.ellipse([40, 40, SIZE - 40, SIZE - 40], fill=(232, 160, 26))
    d.ellipse([58, 58, SIZE - 58, SIZE - 58], fill=(252, 252, 255))
    for i in range(12):
        a = np.pi * 2 * i / 12
        r1, r2 = (150, 186) if i % 3 == 0 else (165, 186)
        d.line(
            [(c + np.sin(a) * r1, c - np.cos(a) * r1), (c + np.sin(a) * r2, c - np.cos(a) * r2)],
            fill=(150, 156, 170),
            width=10 if i % 3 == 0 else 6,
        )
    d.line([(c, c), (c, c - 150)], fill=(24, 24, 30), width=26)
    a = np.pi * 2 * 2 / 12
    d.line([(c, c), (c + np.sin(a) * 105, c - np.cos(a) * 105)], fill=(24, 24, 30), width=28)
    d.ellipse([c - 24, c - 24, c + 24, c + 24], fill=(24, 24, 30))
    return np.asarray(img, float)


def sheen(img, strength):
    """A soft highlight from the upper left, like the icons' glossy light."""
    if not strength:
        return img
    x, y = grid()
    d = np.hypot(x - 0.3, y - 0.25)
    glow = np.clip(1 - d / 0.75, 0, 1) ** 2 * strength
    return img + (255 - img) * glow[..., None]


def paint(spec):
    if spec.get("Rainbow"):
        img = rainbow(spec.get("Vertical", False))
    elif spec.get("Pastel"):
        img = pastel()
    elif "Cracks" in spec:
        img = cracks(spec)
    elif "Image" in spec:
        img = {"Disc8": disc8, "Clock": clock}[spec["Image"]]()
    elif "Tips" in spec:
        img = tips(*spec["Tips"])
    else:
        img = gradient(spec["Top"], spec["Bottom"])
    img = sheen(img, spec.get("Sheen", 0))
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def rainbow_strip(path):
    """A seamless rainbow (red back to red) the game scrolls along a block's frame."""
    hues = np.linspace(0, 1, 512, endpoint=False)
    row = np.array([colorsys.hsv_to_rgb(h, 0.8, 1.0) for h in hues]) * 255
    img = np.broadcast_to(row[None, :, :], (64, 512, 3))
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(path)


def main():
    kinds = sys.argv[1:] or list(KINDS)
    rainbow_strip(os.path.join(ROOT, "assets", "luckyblocks", "textures", "rainbow_scroll.png"))
    for kind in kinds:
        folder = os.path.join(OUT, kind)
        os.makedirs(folder, exist_ok=True)
        pieces = dict(KINDS[kind])
        pieces.setdefault("Corners", pieces["Frame"])
        for piece, spec in pieces.items():
            paint(spec).save(os.path.join(folder, piece.lower() + ".png"))
        print("luckyblock_textures:", kind, ", ".join(pieces))


if __name__ == "__main__":
    main()
