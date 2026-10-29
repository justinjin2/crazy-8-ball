#!/usr/bin/env python3
"""Make a cue card thumbnail pop on the event track's dark tiles (coordinator 20:5x 2026-10-28:
the purple Halloween Sword read faint next to the other cards). A post pass over
assets/cue/thumbs/<skin>.png, after `python3 tools/cue_skin.py <skin> --thumb`: a soft light
halo behind the cue, the glow pixels brightened, the dark body lifted a little, and the cue a
touch larger in the square. Deterministic: re-run after every re-render.

    python3 tools/thumb_pop.py halloween_sword --halo D9C2FF --halo-alpha 0.55 --halo-radius 0.46 \
        --glow 1.25 --lift 0.85 --zoom 1.04
"""
import argparse
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
THUMBS = os.path.join(HERE, '..', 'assets', 'cue', 'thumbs')


def hexrgb(s):
    s = s.lstrip('#')
    return np.array([int(s[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('skin')
    ap.add_argument('--halo', default='D9C2FF', help='halo colour (hex)')
    ap.add_argument('--halo-alpha', type=float, default=0.55, help='the halo at its centre')
    ap.add_argument('--halo-radius', type=float, default=0.46, help='of the square, to the fade-out')
    ap.add_argument('--glow', type=float, default=1.25, help='brightness multiplier on glow (semi-transparent) pixels')
    ap.add_argument('--lift', type=float, default=0.85, help='gamma on the opaque pixels (below 1 lifts the dark body)')
    ap.add_argument('--zoom', type=float, default=1.04, help='the cue this much larger in the square')
    ap.add_argument('--out', default=None, help='write here instead of over the thumb')
    a = ap.parse_args()

    path = os.path.join(THUMBS, a.skin + '.png')
    im = Image.open(path).convert('RGBA')
    n = im.width
    px = np.asarray(im, np.float32) / 255
    rgb, al = px[..., :3], px[..., 3]

    # Brighten the glow (the semi-transparent aura and bloom) and lift the dark opaque body.
    glow = np.clip((0.9 - al) / 0.9, 0, 1)[..., None]           # 1 where faint, 0 where solid
    rgb = np.clip(rgb * (1 + (a.glow - 1) * glow), 0, 1)
    solid = np.clip((al - 0.5) / 0.5, 0, 1)[..., None]
    rgb = rgb * (1 - solid) + np.power(rgb, a.lift) * solid

    # A touch larger: crop the middle and scale back (premultiplied so the edges stay clean).
    if a.zoom != 1.0:
        pm = np.concatenate([rgb * al[..., None], al[..., None]], -1)
        crop = int(round(n / a.zoom))
        o = (n - crop) // 2
        pm = pm[o:o + crop, o:o + crop]
        big = Image.fromarray((np.clip(pm, 0, 1) * 255).astype(np.uint8), 'RGBA').resize((n, n), Image.LANCZOS)
        pm = np.asarray(big, np.float32) / 255
        al = pm[..., 3]
        rgb = np.where(al[..., None] > 1e-4, pm[..., :3] / np.maximum(al[..., None], 1e-4), 0)

    # The halo behind: a soft radial light, under the cue (over where the cue is clear).
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.hypot(xx - (n - 1) / 2, yy - (n - 1) / 2) / (a.halo_radius * n)
    halo_a = a.halo_alpha * np.clip(1 - r, 0, 1) ** 2 * (3 - 2 * np.clip(1 - r, 0, 1))
    hc = hexrgb(a.halo)
    out_a = al + halo_a * (1 - al)
    out_rgb = np.where(out_a[..., None] > 1e-4,
                       (rgb * al[..., None] + hc * (halo_a * (1 - al))[..., None]) / np.maximum(out_a[..., None], 1e-4), 0)

    out = np.concatenate([np.clip(out_rgb, 0, 1), out_a[..., None]], -1)
    dest = a.out or path
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA').save(dest)
    print('thumb pop', a.skin, '->', dest)


if __name__ == '__main__':
    main()
