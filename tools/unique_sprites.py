#!/usr/bin/env python3
"""The Unique cues' own sprites (2026-10-04), in the v2 standard (tools/vfx_sprites.py: white
with the shape in the alpha, crisp, so an emitter's Color tints them; deterministic).

    python3 tools/unique_sprites.py [name ...]      (no names: all)

assets/cue/vfx/beta/
    wire_strip      1024x256, tiles in x: a wireframe strip (longitudinal lines, cross-section
                    ellipses, a faint grid) for the trail and the overlay beam
    holo_strip      1024x256, tiles in x: hologram energy, soft pulses with fine scan lines
    glyphs_4x4      1024, 16 cells: short strings of made-up glyphs (code typing in and out)
    section_ring    512: a cross-section ring with tick marks and an inner ring (a blueprint's
                    section view)
    wire_frag       256: a small wireframe fragment
    column          512: a soft column of light standing on the pocket (both cues)
assets/cue/vfx/grand_opening/
    burst_8x8       1024, 64 frames: a firework burst (rays from a hot core, spark tips
                    drooping late, fading)
    sparkle_strip   1024x128, tiles in x: a sparkler's streak with star sparkles along it
"""
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VFX = os.path.join(ROOT, 'assets', 'cue', 'vfx')


def save(skin, name, alpha):
    alpha = np.clip(alpha, 0, 1)
    h, w = alpha.shape
    img = np.dstack([np.ones((h, w, 3)), alpha])
    out = os.path.join(VFX, skin)
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, name + '.png')
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)
    print('wrote', os.path.relpath(path, ROOT), '%dx%d' % (w, h))


def coords(w, h):
    """x in 0..1 across, y in -1..1 (up) down the height."""
    x = (np.arange(w) + 0.5) / w
    y = 1 - 2 * (np.arange(h) + 0.5) / h
    return np.meshgrid(x, y)


def line(dist, width, glow=0.0, glow_width=0.0):
    """A soft line from a distance field: crisp core plus an optional glow."""
    a = np.clip(1 - np.abs(dist) / width, 0, 1) ** 0.6
    if glow:
        a = np.maximum(a, glow * np.exp(-(dist / glow_width) ** 2))
    return a


def wrap_dist(x, period):
    """Distance to the nearest multiple of period."""
    f = np.mod(x, period)
    return np.minimum(f, period - f)


# --------------------------------------------------------------------------- Beta

def wire_strip():
    w, h = 1024, 256
    x, y = coords(w, h)
    a = np.zeros((h, w))
    # three longitudinal lines (the middle brighter) and two faint ones
    for yy, s in ((0.0, 1.0), (0.55, 0.7), (-0.55, 0.7), (0.85, 0.35), (-0.85, 0.35)):
        a = np.maximum(a, s * line(y - yy, 0.012, 0.35, 0.05))
    # cross-section ellipses every 1/4 of the strip (seen at an angle: narrow ellipses)
    for cx in (0.125, 0.375, 0.625, 0.875):
        dx = (x - cx) / 0.035
        r = np.hypot(dx, y / 0.92)
        a = np.maximum(a, 0.9 * line(r - 1.0, 0.05, 0.3, 0.12))
    # a faint grid
    a = np.maximum(a, 0.18 * line(wrap_dist(x, 1 / 16.0), 0.0025))
    a = np.maximum(a, 0.18 * line(wrap_dist(y, 0.5), 0.006))
    # small ticks on the middle line
    tick = (wrap_dist(x, 1 / 32.0) < 0.0015) & (np.abs(y) < 0.1)
    a = np.maximum(a, 0.6 * tick)
    # fade at the top and bottom edges so the strip never shows a square edge
    a = a * np.clip((1 - np.abs(y)) / 0.1, 0, 1)
    return a


def holo_strip():
    w, h = 1024, 256
    x, y = coords(w, h)
    rs = np.random.RandomState(5)
    a = np.zeros((h, w))
    # soft pulses of energy, stretched along x, wrapping
    for _ in range(9):
        cx, cy = rs.random_sample(), (rs.random_sample() * 2 - 1) * 0.6
        lx, ly = 0.05 + 0.1 * rs.random_sample(), 0.25 + 0.3 * rs.random_sample()
        dx = np.minimum(np.abs(x - cx), 1 - np.abs(x - cx)) / lx
        a = np.maximum(a, (0.5 + 0.5 * rs.random_sample()) * np.exp(-(dx ** 2 + (y - cy) ** 2 / ly ** 2)))
    body = 0.35 * np.exp(-(y / 0.75) ** 2)
    a = np.maximum(a, body)
    # fine scan lines (dark stripes through the glow)
    scan = 0.55 + 0.45 * (0.5 + 0.5 * np.cos(y * math.pi * 40))
    a = a * scan
    # a few bright flow streaks
    for _ in range(6):
        cy = (rs.random_sample() * 2 - 1) * 0.7
        cx, L = rs.random_sample(), 0.08 + 0.2 * rs.random_sample()
        dx = np.mod(x - cx, 1.0)
        streak = np.clip(1 - dx / L, 0, 1) ** 2 * (dx < L) * line(y - cy, 0.012, 0.3, 0.04)
        a = np.maximum(a, 0.9 * streak)
    a = a * np.clip((1 - np.abs(y)) / 0.12, 0, 1)
    return a


def _glyph(rs, cell, cx, cy, size):
    """One made-up glyph: a few strokes in a size x size box at (cx, cy) in cell pixels."""
    n = size
    g = np.zeros((cell, cell))
    kind = rs.randint(0, 6)
    yy, xx = np.mgrid[0:cell, 0:cell]
    def box(x0, y0, x1, y1):
        return (xx >= cx + x0 * n) & (xx < cx + x1 * n) & (yy >= cy + y0 * n) & (yy < cy + y1 * n)
    t = 0.22
    if kind == 0:   # a bracket shape
        g += box(0, 0, t, 1) + box(0, 0, 1, t) + box(0, 1 - t, 1, 1)
    elif kind == 1:  # a block with a gap
        g += box(0, 0, 1, 0.42) + box(0, 0.58, 1, 1)
    elif kind == 2:  # a diagonal
        for i in range(n):
            g[cy + i, cx + max(0, min(n - 1, i)):cx + max(0, min(n, i + 2))] = 1
        g += box(0, 1 - t, 1, 1)
    elif kind == 3:  # a dot and a bar
        g += box(0.3, 0, 0.7, 0.35) + box(0, 0.65, 1, 1)
    elif kind == 4:  # a cross
        g += box(0.4, 0, 0.6, 1) + box(0, 0.4, 1, 0.6)
    else:            # a hollow square
        g += box(0, 0, 1, 1) & ~box(t, t, 1 - t, 1 - t)
    return np.clip(g, 0, 1)


def glyphs_4x4():
    sheet, cell = 1024, 256
    rs = np.random.RandomState(11)
    out = np.zeros((sheet, sheet))
    for i in range(16):
        r, c = divmod(i, 4)
        g = np.zeros((cell, cell))
        rows = 2 + rs.randint(0, 2)
        size = 18
        for row in range(rows):
            cy = 70 + row * 44
            count = 3 + rs.randint(0, 5)
            x = 40 + rs.randint(0, 30)
            for _ in range(count):
                g = np.maximum(g, (0.55 + 0.45 * rs.random_sample()) * _glyph(rs, cell, x, cy, size))
                x += size + 8 + rs.randint(0, 10)
                if x > cell - size - 20:
                    break
        # a soft glow round the glyphs
        glow = np.zeros_like(g)
        for dy in (-3, 0, 3):
            for dx in (-3, 0, 3):
                glow = np.maximum(glow, np.roll(np.roll(g, dy, 0), dx, 1) * 0.3)
        out[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = np.maximum(g, glow)
    return out


def section_ring():
    n = 512
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, -c)
    r = np.hypot(x, y)
    ang = np.arctan2(y, x)
    a = line(r - 0.72, 0.028, 0.35, 0.08)
    a = np.maximum(a, 0.7 * line(r - 0.42, 0.016, 0.25, 0.05))
    a = np.maximum(a, 0.9 * np.exp(-(r / 0.05) ** 2))
    # tick marks at 12 points round the outer ring, longer at the four quarters
    for i in range(12):
        t = i * math.pi / 6
        along = x * math.cos(t) + y * math.sin(t)
        across = -x * math.sin(t) + y * math.cos(t)
        L = 0.14 if i % 3 == 0 else 0.07
        tick = (np.abs(across) < 0.012) & (along > 0.72 - L / 2) & (along < 0.72 + L / 2)
        a = np.maximum(a, tick * 0.95)
    # two crosshair lines
    a = np.maximum(a, 0.45 * ((np.abs(x) < 0.006) | (np.abs(y) < 0.006)) * (r < 0.72))
    # dimension arc
    arc = (np.abs(r - 0.57) < 0.008) & (ang > 0.3) & (ang < 1.3)
    a = np.maximum(a, 0.6 * arc)
    return a * np.clip((1 - r) / 0.12, 0, 1)


def wire_frag():
    n = 256
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, -c)
    pts = [(-0.7, -0.5), (0.6, -0.65), (0.75, 0.4), (-0.3, 0.7)]
    a = np.zeros((n, n))
    edges = list(zip(pts, pts[1:] + pts[:1])) + [(pts[0], pts[2])]
    for (x0, y0), (x1, y1) in edges:
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy)
        t = np.clip(((x - x0) * dx + (y - y0) * dy) / (L * L), 0, 1)
        d = np.hypot(x - (x0 + t * dx), y - (y0 + t * dy))
        a = np.maximum(a, line(d, 0.035, 0.3, 0.09))
    for px, py in pts:
        a = np.maximum(a, np.exp(-(np.hypot(x - px, y - py) / 0.06) ** 2))
    return a


# --------------------------------------------------------------------------- Grand Opening

def burst_8x8():
    sheet, cell, frames = 1024, 128, 64
    rs = np.random.RandomState(3)
    nrays = 26
    angles = np.sort(rs.random_sample(nrays) * 2 * math.pi)
    lengths = 0.75 + 0.25 * rs.random_sample(nrays)
    out = np.zeros((sheet, sheet))
    c = (np.arange(cell) + 0.5) / cell * 2 - 1
    x, y = np.meshgrid(c, -c)
    r = np.hypot(x, y)
    for i in range(frames):
        k = i / (frames - 1)
        grow = 1 - (1 - min(k / 0.55, 1)) ** 2.4          # the rays shoot out fast, then hold
        fade = 1.0 if k < 0.45 else max(0.0, 1 - (k - 0.45) / 0.55) ** 1.3
        droop = max(0.0, k - 0.35) ** 2 * 0.6               # the tips sag late (gravity)
        a = np.zeros((cell, cell))
        for ang, L in zip(angles, lengths):
            R = L * grow
            ex, ey = math.cos(ang) * R, math.sin(ang) * R - droop * R * 0.5
            sx, sy = math.cos(ang) * R * 0.25, math.sin(ang) * R * 0.25
            dx, dy = ex - sx, ey - sy
            LL = max(math.hypot(dx, dy), 1e-4)
            t = np.clip(((x - sx) * dx + (y - sy) * dy) / (LL * LL), 0, 1)
            d = np.hypot(x - (sx + t * dx), y - (sy + t * dy))
            width = 0.012 + 0.01 * (1 - t)
            ray = np.clip(1 - d / width, 0, 1) * (0.4 + 0.6 * t)
            a = np.maximum(a, ray * fade)
            # the spark at the tip
            tip = np.exp(-(np.hypot(x - ex, y - ey) / 0.045) ** 2)
            a = np.maximum(a, tip * min(1.0, fade * 1.3))
        core = np.exp(-(r / (0.28 * (1 - 0.8 * min(k / 0.3, 1)) + 0.02)) ** 2) * max(0.0, 1 - k / 0.35)
        halo = 0.07 * np.exp(-(r / (0.45 * grow + 0.05)) ** 2) * fade
        a = np.maximum(a, np.maximum(core, halo))
        a = a * np.clip((1 - r) / 0.1, 0, 1)
        rr, cc = divmod(i, 8)
        out[rr * cell:(rr + 1) * cell, cc * cell:(cc + 1) * cell] = a
    return out


def column():
    """A soft column of light standing on the pocket (FacingCameraWorldUp): bright and narrow at
    the foot, widening and fading up, soft sides, no square edge."""
    n = 512
    x, y = coords(n, n)            # x 0..1 across, y 1 (top) .. -1 (bottom)
    u = (x - 0.5) * 2
    h = (1 - y) / 2                # 0 at the top, 1 at the bottom
    width = 0.18 + 0.5 * (1 - h) ** 1.2
    a = np.exp(-(u / width) ** 2) * (0.25 + 0.75 * h ** 0.8)
    a = a * np.clip((1 - np.abs(u)) / 0.15, 0, 1) * np.clip(h / 0.08, 0, 1) * np.clip((1 - h) / 0.06, 0, 1)
    return a


def sparkle_strip():
    w, h = 1024, 128
    x, y = coords(w, h)
    rs = np.random.RandomState(9)
    a = 0.9 * np.exp(-(y / 0.22) ** 2) + 0.3 * np.exp(-(y / 0.6) ** 2)
    for _ in range(40):
        cx, cy = rs.random_sample(), (rs.random_sample() * 2 - 1) * 0.75
        s = 0.02 + 0.05 * rs.random_sample()
        dx = np.minimum(np.abs(x - cx), 1 - np.abs(x - cx)) / (s * 0.125)
        dy = (y - cy) / s
        star = np.exp(-(dx ** 2 + dy ** 2)) + 0.6 * np.exp(-(dx ** 2) * 0.1 - (dy ** 2) * 6) + 0.6 * np.exp(-(dx ** 2) * 6 - (dy ** 2) * 0.1)
        a = np.maximum(a, np.clip(star, 0, 1) * (0.6 + 0.4 * rs.random_sample()))
    return a * np.clip((1 - np.abs(y)) / 0.1, 0, 1)


SPRITES = {
    'beta': {'wire_strip': wire_strip, 'holo_strip': holo_strip, 'glyphs_4x4': glyphs_4x4,
             'section_ring': section_ring, 'wire_frag': wire_frag, 'column': column},
    'grand_opening': {'burst_8x8': burst_8x8, 'sparkle_strip': sparkle_strip, 'column': column},
}


def main():
    want = set(sys.argv[1:])
    for skin, fns in SPRITES.items():
        for name, fn in fns.items():
            if want and name not in want:
                continue
            save(skin, name, fn())


if __name__ == '__main__':
    main()
