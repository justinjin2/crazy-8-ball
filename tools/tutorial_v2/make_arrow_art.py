#!/usr/bin/env python3
"""Tutorial v2's arrow art (docs/prompts/TUTORIAL_V2_PROMPT.md 4.3): a chevron pointing up (a
Beam runs its texture's vertical axis along its length, tested in Studio 2026-10-09), white
with a thick black outline on a transparent background, and a bigger arrowhead for the end
over the pad. Drawn 4x and scaled down for clean edges.

    python3 tools/tutorial_v2/make_arrow_art.py   # writes assets/ui/tutorial/arrow_*.png
"""
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "ui", "tutorial")
S = 4  # supersampling


def outlined(w, h, pts, outline):
    """White polygon `pts` (supersampled pixels) with an even black outline `outline` px wide
    (the shape grown by a round brush), on a transparent tile."""
    W, H = w * S, h * S
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    grown = mask
    r = outline * S
    step = 9  # MaxFilter sizes must be odd; grow in passes
    while r > 0:
        k = min(step, 2 * r + 1)
        k = k if k % 2 == 1 else k - 1
        grown = grown.filter(ImageFilter.MaxFilter(k))
        r -= (k - 1) // 2
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img.paste((0, 0, 0, 255), (0, 0), grown)
    img.paste((255, 255, 255, 255), (0, 0), mask)
    return img.resize((w, h), Image.LANCZOS)


def chevron(w, h, thick, outline, tip):
    """A '>' chevron: arms `thick` wide across, its tip at `tip` (share of the width)."""
    W, H = w * S, h * S
    t = thick * S
    x0, x1 = W * 0.16, W * tip
    y0, y1 = H * 0.14, H * 0.86
    pts = [(x0, y0), (x0 + t, y0), (x1 + t, H * 0.5), (x0 + t, y1), (x0, y1), (x1, H * 0.5)]
    return outlined(w, h, pts, outline)


def head(w, h, outline):
    """A solid arrowhead pointing right."""
    W, H = w * S, h * S
    pts = [(W * 0.16, H * 0.14), (W * 0.84, H * 0.5), (W * 0.16, H * 0.86)]
    return outlined(w, h, pts, outline)


def main():
    os.makedirs(OUT, exist_ok=True)
    up = Image.Transpose.ROTATE_90  # drawn pointing right, turned to point up
    chevron(256, 256, 54, 14, 0.62).transpose(up).save(os.path.join(OUT, "arrow_chevron_up.png"))
    head(256, 256, 14).transpose(up).save(os.path.join(OUT, "arrow_head_up.png"))
    print("wrote arrow_chevron_up.png, arrow_head_up.png in", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
