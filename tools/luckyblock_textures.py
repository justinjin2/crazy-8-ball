#!/usr/bin/env python3
"""Paint the colour maps for our own lucky blocks (designer, 2026-10-07).

Each block is three pieces (tools/luckyblock_build.py): Frame (the edge bars and corner cubes),
Core (the face panels) and Glyph (the raised "?"), plus a topper or wings on some kinds. Every
piece is box-mapped, so each face of a piece shows the whole square texture: u runs left to
right and v bottom to top as you look at that face. The approved concept icons set the colours
(~/Desktop/8ball-refs/lucky-blocks/).

    python3 tools/luckyblock_textures.py [kind ...]     # every kind when none is named

Writes assets/luckyblocks/build/<kind>/<piece>.png (512 x 512).
"""
import colorsys

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "luckyblocks", "build")
SIZE = 512

# A piece's paint: "Top" and "Bottom" colours of a vertical gradient (RGB 0-255), or "Rainbow".
# Sheen adds the concept icons' soft glossy light from the upper left.
KINDS = {
    "standard": {
        # Bright yellow rims, beige-brown faces (designer, 2026-10-07: "more yellow than gold").
        "Frame": {"Top": (255, 230, 50), "Bottom": (250, 196, 18), "Sheen": 0.35},
        "Core": {"Top": (222, 184, 128), "Bottom": (176, 128, 76), "Sheen": 0.3},
        "Glyph": {"Top": (255, 252, 240), "Bottom": (244, 232, 206), "Sheen": 0.2},
    },
    "mystery": {
        "Frame": {"Rainbow": True, "Sheen": 0.3},
        "Core": {"Top": (22, 24, 44), "Bottom": (8, 8, 18), "Sheen": 0.18},
        "Glyph": {"Rainbow": True, "Vertical": True, "Sheen": 0.25},
    },
}


def gradient(top, bottom):
    v = np.linspace(0.0, 1.0, SIZE)[:, None, None]  # row 0 is the top of the image
    top, bottom = np.array(top, float), np.array(bottom, float)
    return np.broadcast_to(top * (1 - v) + bottom * v, (SIZE, SIZE, 3)).copy()


def rainbow(vertical):
    y, x = np.mgrid[0:SIZE, 0:SIZE] / (SIZE - 1)
    t = y if vertical else (x + (1 - y)) / 2  # a diagonal sweep across each face
    # Red through violet (hue 0 to 0.85), never wrapping back to red.
    ramp = np.array([colorsys.hsv_to_rgb(h, 0.85, 1.0) for h in np.linspace(0, 0.85, 256)])
    return ramp[(t * 255).astype(int).clip(0, 255)] * 255


def sheen(img, strength):
    """A soft highlight from the upper left, like the icons' glossy light."""
    if not strength:
        return img
    y, x = np.mgrid[0:SIZE, 0:SIZE] / (SIZE - 1)
    d = np.hypot(x - 0.3, y - 0.25)
    glow = np.clip(1 - d / 0.75, 0, 1) ** 2 * strength
    return img + (255 - img) * glow[..., None]


def paint(spec):
    if spec.get("Rainbow"):
        img = rainbow(spec.get("Vertical", False))
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
        for piece, spec in KINDS[kind].items():
            paint(spec).save(os.path.join(folder, piece.lower() + ".png"))
        print("luckyblock_textures:", kind, ", ".join(KINDS[kind]))


if __name__ == "__main__":
    main()
