#!/usr/bin/env python3
"""The Grand Opening block with its crown baked on (designer, 2026-10-06: the crown is part of
the block, breathing and shining with it).

    python3 tools/gui/crowned_block.py

Reads assets/ui/grand_opening/block.png and crown.png, places the crown where the card had it
(Config.UI.GrandOpeningCard.Layout before this: block centre (182, 262) 300 wide, crown centre
(192, 122) 170 wide, turned -7 degrees; seated 10 units lower), and writes:

  block_crowned.png       the block and crown, a clear border round them (the breathe zooms
                          inside it), at most 1024 px
  block_crowned_mask.png  its white silhouette (the shine sweep)

and prints the picture's box in the card's units, for Layout.CrownedBlock.
"""
import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "assets/ui/grand_opening"
BLOCK = (182, 262, 300)  # centre x, y and width in the card's units
CROWN = (192, 132, 170)  # 10 units lower than the card had it: seated in the top face
CROWN_DEGREES = -7  # Roblox Rotation (clockwise); PIL turns anticlockwise
MAX_PX = 1024
BORDER_PX = 24


def main():
    block = Image.open(DIR / "block.png").convert("RGBA")
    crown = Image.open(DIR / "crown.png").convert("RGBA")
    # The block's picture is fitted into its square box (ScaleType Fit by default: Stretch to
    # the box); the crown's height follows its picture.
    bw, bh = BLOCK[2], BLOCK[2]
    cw = CROWN[2]
    ch = cw * crown.height / crown.width
    a = math.radians(abs(CROWN_DEGREES))
    rw = cw * math.cos(a) + ch * math.sin(a)
    rh = cw * math.sin(a) + ch * math.cos(a)
    left = min(BLOCK[0] - bw / 2, CROWN[0] - rw / 2)
    right = max(BLOCK[0] + bw / 2, CROWN[0] + rw / 2)
    top = min(BLOCK[1] - bh / 2, CROWN[1] - rh / 2)
    bottom = max(BLOCK[1] + bh / 2, CROWN[1] + rh / 2)
    inner = MAX_PX - 2 * BORDER_PX
    s = inner / max(right - left, bottom - top)  # px per unit
    W = round((right - left) * s) + 2 * BORDER_PX
    H = round((bottom - top) * s) + 2 * BORDER_PX
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def at(cx, cy, w, h):
        return (
            round(BORDER_PX + (cx - left) * s - w / 2),
            round(BORDER_PX + (cy - top) * s - h / 2),
        )

    b = block.resize((round(bw * s), round(bh * s)), Image.LANCZOS)
    out.alpha_composite(b, at(BLOCK[0], BLOCK[1], b.width, b.height))
    c = crown.resize((round(cw * s), round(ch * s)), Image.LANCZOS)
    c = c.rotate(-CROWN_DEGREES, resample=Image.BICUBIC, expand=True)
    out.alpha_composite(c, at(CROWN[0], CROWN[1], c.width, c.height))
    out.save(DIR / "block_crowned.png")
    mask = Image.new("RGBA", out.size, (255, 255, 255, 0))
    mask.putalpha(out.getchannel("A"))
    mask.save(DIR / "block_crowned_mask.png")
    # The picture's box in units (border included) and its centre from the block's centre.
    uw, uh = W / s, H / s
    ucx = left - BORDER_PX / s + uw / 2
    ucy = top - BORDER_PX / s + uh / 2
    print(f"{W} x {H} px, border {BORDER_PX} px")
    print(
        f"CrownedBlock = {{ {ucx - BLOCK[0]:.1f}, {ucy - BLOCK[1]:.1f}, {uw:.1f}, {uh:.1f} }}"
        " -- centre from the block's, width, height (units)"
    )


if __name__ == "__main__":
    main()
