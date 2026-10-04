#!/usr/bin/env python3
"""The Beta Cue's blueprint panels (2026-10-04): eight textures for the panes the piece carries
(assets/cue/CuePiecesUnique.py), each a floating blueprint window: a thin tinted glass body
(alpha 0.28), a title bar of glyph blocks, lines of made-up glyphs (never readable words), and
a diagram (cue cross-sections, side elevations with dimension lines, grids with a trace, data
bars), the linework white-blue and glowing (its own emissive mask).

    python3 tools/unique_panels.py        -> assets/cue/vfx/beta/panel_<n>.png, panel_<n>_emissive.png

Deterministic (fixed seeds). The panel's colour map is RGBA: the glass is a dark blue at low
alpha, the lines pale blue at alpha 1 (AlphaMode Transparency on the SurfaceAppearance).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'cue', 'vfx', 'beta')
W, H = 640, 384
GLASS = (10, 26, 70)
LINE = (170, 220, 255)
DIM = (90, 160, 255)
HOT = (255, 255, 255)


def glyph_row(d, x, y, n, rs, size=9, colour=LINE):
    """A row of n made-up glyphs (small stroke clusters) starting at (x, y)."""
    for _ in range(n):
        kind = rs.randint(0, 7)
        s = size
        if kind == 0:
            d.rectangle([x, y, x + s, y + s], outline=colour)
        elif kind == 1:
            d.rectangle([x, y, x + s, y + s * 0.45], fill=colour)
            d.rectangle([x, y + s * 0.6, x + s, y + s], fill=colour)
        elif kind == 2:
            d.line([x, y + s, x + s, y], fill=colour, width=2)
            d.line([x, y + s, x + s, y + s], fill=colour, width=2)
        elif kind == 3:
            d.line([x, y, x, y + s], fill=colour, width=2)
            d.line([x, y, x + s, y], fill=colour, width=2)
            d.line([x, y + s, x + s, y + s], fill=colour, width=2)
        elif kind == 4:
            d.line([x + s / 2, y, x + s / 2, y + s], fill=colour, width=2)
            d.line([x, y + s / 2, x + s, y + s / 2], fill=colour, width=2)
        elif kind == 5:
            d.ellipse([x, y, x + s, y + s], outline=colour)
            d.rectangle([x + s * 0.35, y + s * 0.35, x + s * 0.65, y + s * 0.65], fill=colour)
        else:
            d.rectangle([x + s * 0.3, y, x + s * 0.7, y + s * 0.3], fill=colour)
            d.line([x, y + s, x + s, y + s], fill=colour, width=2)
        x += s + 5 + rs.randint(0, 4)
        if rs.random_sample() < 0.12:
            x += 8  # a word gap
    return x


def dimension(d, x0, y0, x1, y1, colour=DIM):
    """A dimension line with ticks at both ends and a short glyph label."""
    d.line([x0, y0, x1, y1], fill=colour, width=1)
    dx, dy = x1 - x0, y1 - y0
    L = max(math.hypot(dx, dy), 1)
    nx, ny = -dy / L * 6, dx / L * 6
    for px, py in ((x0, y0), (x1, y1)):
        d.line([px - nx, py - ny, px + nx, py + ny], fill=colour, width=1)
    d.polygon([(x0, y0), (x0 + dx / L * 8 + nx * 0.5, y0 + dy / L * 8 + ny * 0.5), (x0 + dx / L * 8 - nx * 0.5, y0 + dy / L * 8 - ny * 0.5)], fill=colour)
    d.polygon([(x1, y1), (x1 - dx / L * 8 + nx * 0.5, y1 - dy / L * 8 + ny * 0.5), (x1 - dx / L * 8 - nx * 0.5, y1 - dy / L * 8 - ny * 0.5)], fill=colour)


def diagram(d, kind, box, rs):
    x0, y0, x1, y1 = box
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    w, h = x1 - x0, y1 - y0
    if kind == 'section':
        R = min(w, h) * 0.42
        for f, col in ((1.0, LINE), (0.78, DIM), (0.5, LINE), (0.18, DIM)):
            d.ellipse([cx - R * f, cy - R * f, cx + R * f, cy + R * f], outline=col, width=2 if f == 1.0 else 1)
        for i in range(12):
            t = i * math.pi / 6
            d.line([cx + R * 0.9 * math.cos(t), cy + R * 0.9 * math.sin(t), cx + R * 1.08 * math.cos(t), cy + R * 1.08 * math.sin(t)], fill=LINE, width=2 if i % 3 == 0 else 1)
        d.line([cx - R * 1.2, cy, cx + R * 1.2, cy], fill=DIM, width=1)
        d.line([cx, cy - R * 1.2, cx, cy + R * 1.2], fill=DIM, width=1)
        dimension(d, cx - R, cy + R * 1.25, cx + R, cy + R * 1.25)
        glyph_row(d, cx - 20, cy + R * 1.32, 3, rs, size=7, colour=DIM)
    elif kind == 'elevation':
        # the cue's side view: a tapered outline, zone lines and dimension lines
        tip, butt = h * 0.08, h * 0.3
        d.polygon([(x0, cy - tip), (x1, cy - butt), (x1, cy + butt), (x0, cy + tip)], outline=LINE)
        for f in (0.1, 0.52, 0.55, 0.77, 0.96):
            xx = x0 + w * f
            yy = tip + (butt - tip) * f
            d.line([xx, cy - yy, xx, cy + yy], fill=DIM, width=1)
        for f in (0.25, 0.65):
            xx = x0 + w * f
            yy = tip + (butt - tip) * f
            d.ellipse([xx - yy * 0.35, cy - yy, xx + yy * 0.35, cy + yy], outline=LINE)
        dimension(d, x0, y0 + h * 0.92, x1, y0 + h * 0.92)
        dimension(d, x1 + 12, cy - butt, x1 + 12, cy + butt)
        glyph_row(d, x0 + w * 0.4, y0 + h * 0.95, 2, rs, size=6, colour=DIM)
    elif kind == 'grid':
        for i in range(0, int(w) + 1, 24):
            d.line([x0 + i, y0, x0 + i, y1], fill=(40, 80, 160), width=1)
        for j in range(0, int(h) + 1, 24):
            d.line([x0, y0 + j, x1, y0 + j], fill=(40, 80, 160), width=1)
        pts = []
        for i in range(0, int(w) + 1, 6):
            t = i / w
            v = 0.5 + 0.35 * math.sin(t * 9 + rs.random_sample() * 0.2) * math.exp(-((t - 0.5) * 2.2) ** 2)
            pts.append((x0 + i, y0 + h * (1 - v)))
        d.line(pts, fill=LINE, width=2)
        for px, py in pts[::18]:
            d.ellipse([px - 3, py - 3, px + 3, py + 3], fill=HOT)
    elif kind == 'bars':
        n = 7
        for i in range(n):
            bh = h * (0.25 + 0.7 * rs.random_sample())
            bx = x0 + i * (w / n) + 6
            d.rectangle([bx, y1 - bh, bx + w / n - 12, y1], outline=LINE)
            d.rectangle([bx + 3, y1 - bh * 0.6, bx + w / n - 15, y1 - 3], fill=(60, 110, 210))
        d.line([x0, y1, x1, y1], fill=LINE, width=2)
    elif kind == 'joint':
        R = min(w, h) * 0.3
        for ox in (-R * 1.3, R * 1.3):
            d.ellipse([cx + ox - R, cy - R, cx + ox + R, cy + R], outline=LINE, width=2)
            d.ellipse([cx + ox - R * 0.4, cy - R * 0.4, cx + ox + R * 0.4, cy + R * 0.4], outline=DIM)
        d.line([cx - R * 0.3, cy, cx + R * 0.3, cy], fill=HOT, width=2)
        for i in range(6):
            yy = cy - R + i * (2 * R / 5)
            d.line([cx - R * 2.3, yy, cx - R * 1.9, yy], fill=DIM)
            d.line([cx + R * 1.9, yy, cx + R * 2.3, yy], fill=DIM)
        dimension(d, cx - R * 2.3, cy + R * 1.3, cx + R * 2.3, cy + R * 1.3)


SPECS = [  # (diagram, glyph rows, a title)
    ('section', 2, True), ('elevation', 2, True), ('grid', 3, True), ('bars', 2, False),
    ('joint', 2, True), ('section', 3, False), ('elevation', 1, True), ('grid', 2, True),
]


def panel(n, spec, rs):
    kind, rows, title = spec
    img = Image.new('RGBA', (W, H), GLASS + (72,))
    d = ImageDraw.Draw(img)
    # the border and the title bar
    d.rectangle([2, 2, W - 3, H - 3], outline=LINE + (255,), width=3)
    d.rectangle([2, 2, W - 3, 34], fill=(40, 90, 200, 150))
    glyph_row(d, 14, 11, 4 + rs.randint(0, 4), rs, size=11, colour=HOT + (255,))
    for i in range(3):
        d.rectangle([W - 24 - i * 18, 11, W - 14 - i * 18, 23], fill=LINE + (255,))
    # the diagram on the left two thirds, the glyph lines on the right (or below)
    if rows >= 3:
        diagram(d, kind, (24, 52, W * 0.6, H - 70), rs)
        y = 58
        for _ in range(rows + 2):
            glyph_row(d, W * 0.64, y, 4 + rs.randint(0, 4), rs, size=8, colour=LINE + (255,))
            y += 22
    else:
        diagram(d, kind, (24, 52, W - 24, H * 0.62), rs)
        y = H * 0.68
        for _ in range(rows):
            glyph_row(d, 24, y, 8 + rs.randint(0, 8), rs, size=8, colour=LINE + (255,))
            y += 22
    # a status strip at the bottom with small bars
    d.line([12, H - 30, W - 12, H - 30], fill=DIM + (255,), width=1)
    for i in range(6):
        if rs.random_sample() < 0.7:
            d.rectangle([20 + i * 36, H - 22, 44 + i * 36, H - 12], fill=(DIM if i % 2 else LINE) + (255,))
    arr = np.asarray(img, np.float64)
    # the emissive mask: the linework (anything brighter than the glass)
    bright = np.clip((arr[..., :3].max(-1) - 60) / 120, 0, 1) * (arr[..., 3] > 100)
    em = Image.fromarray((bright * 255).astype(np.uint8))
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, 'panel_%d.png' % n), optimize=True)
    em.save(os.path.join(OUT, 'panel_%d_emissive.png' % n), optimize=True)
    print('wrote', os.path.relpath(os.path.join(OUT, 'panel_%d.png' % n), ROOT))


def main():
    for i, spec in enumerate(SPECS):
        panel(i + 1, spec, np.random.RandomState(100 + i))


if __name__ == '__main__':
    main()
