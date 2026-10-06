"""Rebuild check for the cut layers: stack the plate and every layer at its place, compare with 13b.

Reads OUT/layers.json (written by cut_pieces.py) and writes into OUT:
  rebuild.png        the stacked layers over the plate (holes filled by the OpenCV stand-in)
  rebuild_check.png  13b | rebuild | difference heat map (x4 gain, black = equal), stacked
  layers_sheet.png   every layer on black, white and a checkerboard
Each layer is stacked as 13b shows it (alpha x (1 - its fill mask)), so parts hidden in 13b (a
ball behind a button) stay hidden. Prints the mean and 99th-percentile difference (0-255 scale,
max over RGB) inside the pieces' visible areas (alpha > 0), and inside the solid cores
(alpha >= 0.98), where the plate's stand-in fill cannot matter.

Usage: tools/gui/.venv/bin/python tools/gui/rebuild_check.py [--out DIR] [--plate FILE]
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REFS = Path.home() / "Desktop/8ball-refs/gui-lively"


def over(dst, rgba, x, y):
    """Straight-alpha 'over' of rgba (float 0..1) onto dst (float RGB) at x, y."""
    h, w = rgba.shape[:2]
    a = rgba[..., 3:4]
    dst[y:y + h, x:x + w] = rgba[..., :3] * a + dst[y:y + h, x:x + w] * (1 - a)


def heat(d):
    """Black -> red -> yellow -> white for a 0..1 difference."""
    d = np.clip(d, 0, 1)[..., None]
    return np.clip(np.concatenate([d * 3, d * 3 - 1, d * 3 - 2], -1), 0, 1)


def checker(h, w, s=8):
    yy, xx = np.mgrid[0:h, 0:w]
    c = ((xx // s + yy // s) % 2).astype(float)
    return np.dstack([0.55 + 0.25 * c] * 3)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REFS / "work/pieces"))
    ap.add_argument("--plate", default="plate_preview_fill.png", help="plate image under the layers")
    args = ap.parse_args()
    out = Path(args.out).expanduser()
    meta = json.loads((out / "layers.json").read_text())
    src = np.asarray(Image.open(meta["source"]).convert("RGB")).astype(float) / 255
    H, W = src.shape[:2]

    rb = np.asarray(Image.open(out / args.plate).convert("RGB")).astype(float) / 255
    rb = rb.copy()
    cover = np.zeros((H, W))
    tiles = []
    for l in sorted(meta["layers"], key=lambda l: l["z"]):
        rgba = np.asarray(Image.open(out / l["file"])).astype(float) / 255
        tiles.append((l["id"], rgba))
        if l.get("fill_mask"):  # as seen in 13b: what hides a layer stays in front of it
            rgba = rgba.copy()
            rgba[..., 3] *= 1 - np.asarray(Image.open(out / l["fill_mask"])) / 255.0
        over(rb, rgba, l["x"], l["y"])
        a = rgba[..., 3]
        sl = (slice(l["y"], l["y"] + l["h"]), slice(l["x"], l["x"] + l["w"]))
        cover[sl] = np.maximum(cover[sl], a)
    Image.fromarray((rb * 255).round().astype(np.uint8)).save(out / "rebuild.png")

    diff = np.abs(rb - src).max(-1) * 255
    inside, core = cover > 0, cover >= 0.98
    print(f"pieces' area : {inside.sum():7d} px  mean {diff[inside].mean():5.2f}  p99 {np.percentile(diff[inside], 99):6.2f}")
    print(f"solid cores  : {core.sum():7d} px  mean {diff[core].mean():5.2f}  p99 {np.percentile(diff[core], 99):6.2f}")
    for l in sorted(meta["layers"], key=lambda l: l["z"]):
        sl = (slice(l["y"], l["y"] + l["h"]), slice(l["x"], l["x"] + l["w"]))
        m = cover[sl] > 0
        print(f"  {l['id']:18s} mean {diff[sl][m].mean():5.2f}  p99 {np.percentile(diff[sl][m], 99):6.2f}")

    sheet = np.concatenate([src, rb, heat(diff / 255 * 4)], 0)
    Image.fromarray((sheet * 255).round().astype(np.uint8)).save(out / "rebuild_check.png")

    # every layer on black, white and checker, one row each, scaled to <= 220 px tall
    rows, maxw = [], 0
    for name, rgba in tiles:
        s = min(1.0, 220 / rgba.shape[0], 420 / rgba.shape[1])
        im = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBA")
        im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
        a = np.asarray(im).astype(float) / 255
        h, w = a.shape[:2]
        bgs = [np.zeros((h, w, 3)), np.ones((h, w, 3)), checker(h, w)]
        cells = []
        for b in bgs:
            c = b.copy()
            over(c, a, 0, 0)
            cells.append(c)
        gap = np.full((h, 10, 3), 0.3)
        row = np.concatenate([cells[0], gap, cells[1], gap, cells[2]], 1)
        label = Image.new("RGB", (row.shape[1], 18), (40, 40, 40))
        ImageDraw.Draw(label).text((4, 3), name, fill=(255, 255, 255))
        row = np.concatenate([np.asarray(label).astype(float) / 255, row], 0)
        rows.append(row)
        maxw = max(maxw, row.shape[1])
    # two columns of rows
    half = (len(rows) + 1) // 2
    cols = []
    for part in (rows[:half], rows[half:]):
        part = [np.pad(r, ((0, 6), (0, maxw - r.shape[1]), (0, 0)), constant_values=0.3) for r in part]
        cols.append(np.concatenate(part, 0) if part else np.zeros((1, maxw, 3)))
    hmax = max(c.shape[0] for c in cols)
    cols = [np.pad(c, ((0, hmax - c.shape[0]), (0, 0), (0, 0)), constant_values=0.3) for c in cols]
    sheet = np.concatenate([cols[0], np.full((hmax, 16, 3), 0.3), cols[1]], 1)
    Image.fromarray((sheet * 255).round().astype(np.uint8)).save(out / "layers_sheet.png")


if __name__ == "__main__":
    main()
