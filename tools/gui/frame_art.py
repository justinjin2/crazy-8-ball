"""The Shop frame's tiles. For now: the white sheet's dot tile.

dots_512.png is the original tiny pool-ball pattern (art_pattern() in tools/gen_ui_art.py at git
commit 106a294: solid and striped balls on an even staggered grid in a 256 px tile, white marks
with the number spots knocked out) redrawn at 512 px, twice the size with the same layout, so it
stays crisp. White on transparent; Roblox tints it (ImageColor3 74,123,192) and fades it
(ImageTransparency 0.92), tiled at ~88 px per period (the designer's option A, 2026-10-06).

Drawn with Pillow at 4x and shrunk (no Chrome). Every ball is drawn at its wrap-around copies
too, so the tile is seamless. Writes:
  assets/ui/frame/dots_512.png                       the tile
  OUT/dots_tiled_3x3.png                             3 x 3 tiles on navy: seams would show here
  OUT/dots_preview_vs_A.png                          tinted 8% over white at 88 px per period,
                                                     beside option A from 15-sheet-pattern-options
Usage: tools/gui/.venv/bin/python tools/gui/frame_art.py [--out DIR]
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
REFS = Path.home() / "Desktop/8ball-refs/gui-lively"
TILE = 512  # px; the 106a294 tile was 256
SS = 4  # supersampling
TINT = (74, 123, 192)  # the sheet pattern's ImageColor3
STRENGTH = 0.08  # 1 - ImageTransparency (0.92)
PERIOD_PX = 88  # on-screen px per tile period in option A

# (x, y, kind) in the 256 px layout of 106a294; everything scales by TILE / 256
SPOTS = [
    (40, 40, "solid"), (168, 40, "stripe"), (104, 104, "stripe"), (232, 104, "solid"),
    (40, 168, "stripe"), (168, 168, "solid"), (104, 232, "solid"), (232, 232, "stripe"),
]
R = 13  # ball radius at 256


def draw_tile():
    k = TILE / 256 * SS  # 256-layout units -> supersampled px
    n = TILE * SS
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)

    def circle(cx, cy, r, fill):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

    for x, y, kind in SPOTS:
        for dx in (-256, 0, 256):  # wrap-around copies: seamless
            for dy in (-256, 0, 256):
                cx, cy = (x + dx) * k, (y + dy) * k
                if not (-R * k <= cx <= n + R * k and -R * k <= cy <= n + R * k):
                    continue
                if kind == "solid":  # white ball, number spot knocked out
                    circle(cx, cy, R * k, 255)
                    circle(cx, cy, R * 0.42 * k, 0)
                else:  # ring (stroke 3 centred on r - 1.5) plus the band across it
                    circle(cx, cy, R * k, 255)
                    circle(cx, cy, (R - 3) * k, 0)
                    d.rectangle([cx - R * 0.89 * k, cy - R * 0.45 * k,
                                 cx + R * 0.89 * k, cy + R * 0.45 * k], fill=255)
    a = m.resize((TILE, TILE), Image.BOX)
    white = Image.new("L", (TILE, TILE), 255)
    return Image.merge("RGBA", (white, white, white, a))


def tiled(tile, nx, ny, period):
    """The tile repeated nx x ny times at `period` px per tile (alpha only, 0..1)."""
    t = tile.getchannel("A").resize((period, period), Image.LANCZOS) if period != tile.width else tile.getchannel("A")
    a = np.asarray(t).astype(float) / 255
    return np.tile(a, (ny, nx))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REFS / "work/frame"))
    args = ap.parse_args()
    out = Path(args.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    dest = ROOT / "assets/ui/frame"
    dest.mkdir(parents=True, exist_ok=True)

    tile = draw_tile()
    tile.save(dest / "dots_512.png")

    # 3 x 3 seam check on navy at full size
    a = tiled(tile, 3, 3, TILE)[..., None]
    navy = np.array([16, 24, 60], float)
    img = navy * (1 - a) + 255 * a
    Image.fromarray(img.astype(np.uint8)).save(out / "dots_tiled_3x3.png")

    # option A, top panel of the options picture: its sheet interior
    ref = Image.open(REFS / "15-sheet-pattern-options-dots-vs-8balls.png").convert("RGB")
    ref_crop = ref.crop((10, 95, 890, 510))
    w, h = ref_crop.size
    # ours: tint at STRENGTH over the same sheet colour (sampled from a dot-free spot of A) and
    # over plain white, at PERIOD_PX per period, phase matched by eye to A's first dot row
    a = tiled(tile, w // PERIOD_PX + 2, h // PERIOD_PX + 2, PERIOD_PX)
    a = np.roll(a, (-int(PERIOD_PX * 40 / 256) + 12, -int(PERIOD_PX * 40 / 256) + 31), (0, 1))[:h, :w, None]
    ra = np.asarray(ref_crop).astype(float)
    sheet = np.median(ra.reshape(-1, 3), axis=0)
    tint = np.array(TINT, float)
    on_sheet = sheet * (1 - STRENGTH * a) + tint * STRENGTH * a
    on_white = 255 * (1 - STRENGTH * a) + tint * STRENGTH * a
    gap = np.full((h, 12, 3), 40.0)
    row = np.concatenate([ra, gap, on_sheet, gap, on_white], 1)
    Image.fromarray(row.round().astype(np.uint8)).save(out / "dots_preview_vs_A.png")

    # strength match: how far the darkest dot pixels sit from the sheet colour, A vs ours
    def depth(x):  # dot pixels against their local surroundings (ignores A's gradient)
        from scipy.ndimage import uniform_filter

        local = np.stack([uniform_filter(x[..., c], 25) for c in range(3)], -1)
        return np.percentile((local - x).sum(-1), 99.5)

    print(f"sheet colour in A: {sheet.round()}  dot depth (99.5th pct, local mean - pixel, RGB sum): "
          f"A {depth(ra):.1f}  ours {depth(on_sheet):.1f}")


if __name__ == "__main__":
    main()
