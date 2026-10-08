#!/usr/bin/env python3
"""The cue cards' moving 8-balls (docs/prompts/CUES_LIVELY_PROMPT.md, concept 1): a seamless tile
of real-looking 8-balls, each with its white number disc and a clear 8, a shaded body and a
shine, big enough on a card that the 8 reads (designer, 2026-10-08: "they need to actually show
the 8 ball detail"). Two looks:

- tint: grey and white, so the game tints it to each card's colour (ImageColor3 multiplies: the
  body takes the card's colour, the disc stays lighter, the 8 stays dark);
- classic: black balls with a white disc and a black 8, never tinted.

Writes each look as a TILE px tile and as a 1024 sheet (the tile 2 x 2, so a scroll window that
wraps at one period always stays inside the picture) into assets/ui/cards/, plus a 3 x 3 seam
check into OUT (default: the scratch folder). Pure Pillow and numpy, a fixed layout (no
randomness), drawn 4x and shrunk.

    python3 tools/gui/card_balls.py [--out DIR]
"""

import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw

TILE = 512  # the period in texels; the sheet is this repeated 2 x 2
SS = 4  # drawn this much bigger, then shrunk

# x, y, radius, the disc's turn in degrees, and which way the disc faces (its offset from the
# centre as a share of the radius). Spaced so no two balls touch, across the wrap too.
BALLS = [
    (88, 92, 52, -18, (-0.22, -0.24)),
    (300, 70, 38, 20, (0.12, -0.28)),
    (438, 210, 46, -8, (-0.26, -0.12)),
    (205, 255, 40, 24, (-0.18, -0.26)),
    (72, 372, 44, 10, (-0.08, -0.3)),
    (330, 392, 54, -24, (-0.24, -0.2)),
    (480, 470, 30, 16, (-0.2, -0.24)),
]

LOOKS = {
    "tint": {
        "body": [(0.0, (226, 230, 238)), (0.55, (166, 174, 190)), (1.0, (118, 127, 146))],
        "disc": (255, 255, 255),
        "disc_edge": (205, 211, 222),
        "eight": (36, 40, 52),
        "shine": 0.85,
    },
    "classic": {
        "body": [(0.0, (92, 98, 114)), (0.5, (34, 37, 46)), (1.0, (10, 11, 15))],
        "disc": (255, 255, 255),
        "disc_edge": (200, 204, 214),
        "eight": (18, 20, 26),
        "shine": 0.7,
    },
}


def radial(size, cx, cy, r, stops):
    """An RGB radial gradient (stops: share of r -> colour) from (cx, cy) over a size x size box."""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
    d = np.clip(d, 0, 1)
    out = np.zeros((size, size, 3), np.float32)
    for i in range(3):
        xs = [s for s, _ in stops]
        ys = [c[i] for _, c in stops]
        out[..., i] = np.interp(d, xs, ys)
    return out


def ball(r, tilt, facing, look):
    """One 8-ball, r texels round, on a clear square (drawn SS times bigger)."""
    R = r * SS
    size = int(R * 2 + 8 * SS)
    c = size / 2
    # The body: lit from the upper left.
    rgb = radial(size, c - 0.38 * R, c - 0.36 * R, 1.75 * R, look["body"])
    body = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((c - R, c - R, c + R, c + R), fill=255)
    body.putalpha(mask)

    # The disc and its 8, drawn flat, turned by tilt, then placed toward `facing`.
    dsize = int(R * 1.3)
    disc = Image.new("RGBA", (dsize, dsize), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    dc = dsize / 2
    rx, ry = 0.53 * R, 0.49 * R
    edge = max(1, int(0.035 * R))
    dd.ellipse((dc - rx, dc - ry, dc + rx, dc + ry), fill=look["disc"] + (255,), outline=look["disc_edge"] + (255,), width=edge)
    stroke = max(2, int(0.1 * R))
    top_r, bot_r = 0.12 * R, 0.148 * R
    top_c, bot_c = dc - 0.135 * R, dc + 0.128 * R
    eight = look["eight"] + (255,)
    dd.ellipse((dc - top_r, top_c - top_r, dc + top_r, top_c + top_r), outline=eight, width=stroke)
    dd.ellipse((dc - bot_r, bot_c - bot_r, dc + bot_r, bot_c + bot_r), outline=eight, width=stroke)
    disc = disc.rotate(-tilt, resample=Image.BICUBIC)
    # Foreshorten the disc a little the further it sits from the middle, as on a sphere.
    off = math.hypot(*facing)
    squash = max(0.78, 1 - off * 0.45)
    w = int(dsize * (squash if abs(facing[0]) > abs(facing[1]) else 1))
    h = int(dsize * (squash if abs(facing[1]) >= abs(facing[0]) else 1))
    disc = disc.resize((w, h), Image.BICUBIC)
    px = int(c + facing[0] * R - w / 2)
    py = int(c + facing[1] * R - h / 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.alpha_composite(disc, (px, py))
    # Keep the disc inside the ball.
    la = np.array(layer)
    la[..., 3] = (la[..., 3].astype(np.float32) * (np.array(mask, np.float32) / 255)).astype(np.uint8)
    body.alpha_composite(Image.fromarray(la))

    # The shine: a soft highlight up and left, a faint rim light down and right.
    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    a = int(255 * look["shine"])
    hx, hy = c - 0.5 * R, c - 0.56 * R
    sd.ellipse((hx - 0.2 * R, hy - 0.1 * R, hx + 0.2 * R, hy + 0.1 * R), fill=(255, 255, 255, a))
    rx2, ry2 = c + 0.45 * R, c + 0.52 * R
    sd.ellipse((rx2 - 0.28 * R, ry2 - 0.09 * R, rx2 + 0.28 * R, ry2 + 0.09 * R), fill=(255, 255, 255, int(a * 0.35)))
    shine = shine.rotate(35, center=(c, c), resample=Image.BICUBIC)
    sa = np.array(shine)
    sa[..., 3] = (sa[..., 3].astype(np.float32) * (np.array(mask, np.float32) / 255)).astype(np.uint8)
    body.alpha_composite(Image.fromarray(sa))
    return body, size


def tile(look):
    """The seamless TILE px tile: every ball drawn at each wrap-around place it reaches."""
    big = Image.new("RGBA", (TILE * SS, TILE * SS), (0, 0, 0, 0))
    for x, y, r, tilt, facing in BALLS:
        img, size = ball(r, tilt, facing, look)
        for dx in (-TILE, 0, TILE):
            for dy in (-TILE, 0, TILE):
                cx, cy = (x + dx) * SS, (y + dy) * SS
                big.alpha_composite(img, (int(cx - size / 2), int(cy - size / 2))) if (
                    -size < cx - size / 2 < TILE * SS and -size < cy - size / 2 < TILE * SS
                ) else None
    small = big.convert("RGBa").resize((TILE, TILE), Image.LANCZOS).convert("RGBA")
    return small


def check_spacing():
    for i, (x1, y1, r1, *_rest) in enumerate(BALLS):
        for j, (x2, y2, r2, *_rest2) in enumerate(BALLS):
            if j <= i:
                continue
            best = min(
                math.hypot(x1 - (x2 + dx), y1 - (y2 + dy)) for dx in (-TILE, 0, TILE) for dy in (-TILE, 0, TILE)
            )
            assert best > r1 + r2 + 12, f"balls {i} and {j} too close ({best:.0f} px)"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(os.path.dirname(here))
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(here, "out", "card_balls"))
    args = parser.parse_args()
    check_spacing()
    dest = os.path.join(root, "assets", "ui", "cards")
    os.makedirs(dest, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    for name, look in LOOKS.items():
        t = tile(look)
        t.save(os.path.join(dest, f"balls_{name}_tile.png"), optimize=True)
        sheet = Image.new("RGBA", (TILE * 2, TILE * 2), (0, 0, 0, 0))
        for ox in (0, TILE):
            for oy in (0, TILE):
                sheet.alpha_composite(t, (ox, oy))
        sheet.save(os.path.join(dest, f"balls_{name}_sheet.png"), optimize=True)
        # 3 x 3 seam check on a mid background.
        check = Image.new("RGBA", (TILE * 3, TILE * 3), (120, 140, 180, 255))
        for ox in range(3):
            for oy in range(3):
                check.alpha_composite(t, (ox * TILE, oy * TILE))
        check.convert("RGB").resize((TILE * 3 // 2, TILE * 3 // 2), Image.LANCZOS).save(os.path.join(args.out, f"seam_{name}.png"))
    print(f"period {TILE} texels; sheet {TILE * 2} px; balls r {min(b[2] for b in BALLS)}-{max(b[2] for b in BALLS)}")
    print(f"wrote {dest}/balls_tint_*.png, balls_classic_*.png; seam checks in {args.out}")


if __name__ == "__main__":
    main()
