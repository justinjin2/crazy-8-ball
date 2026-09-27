"""The fire pit's effect images (Config.Map.FirePit; the client's FirePit module plays them at
sunset). Pure Python (numpy, PIL), no bpy:

    python3 assets/map/gen_fire.py

Writes textures/fire_flames.png (an 8 x 8 flipbook, 128 pixels a frame: one flame lick over its
life, played once per particle), fire_ember.png (a hot spark), fire_glow.png (a soft round glow)
and fire_smoke.png (a soft puff). The flames are cel-shaded like the art (hard bands: a yellow
core, orange, a red-orange rim) rather than Roblox's stock fire.
"""

import math
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'textures')

FRAMES = 8  # the flipbook is FRAMES x FRAMES
CELL = 128  # pixels a frame
# The flame's bands, from the rim in: red-orange, orange, yellow, a pale core (the art's fire:
# Palette 'fire' #F6AA3F, its shade #A65015, lit toward white).
BANDS = [(0.0, '#F0562A'), (0.22, '#FF8A2C'), (0.5, '#FFC54A'), (0.78, '#FFF1A8')]
EDGE = 0.035  # the silhouette's soft edge, of the frame (antialiasing only)


def rgb(hex_colour):
    return np.array([int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float64)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def tongue(x, y, t, cx, height, width, phase):
    """One flame tongue: its inside 0..1 (1 at the spine, 0 at the rim, negative outside) at
    points (x across -1..1, y up 0..1) for its life t 0..1."""
    yy = y / height
    sway = 0.13 * np.sin(2 * math.pi * (yy * 0.9 - t * 1.7 + phase)) * yy ** 1.3
    half = width * np.clip(1 - yy, 0, 1) ** 0.75 * (1 + 0.22 * np.sin(7 * yy + t * 11 + phase * 5))
    half = np.maximum(half, 1e-4)
    inside = 1 - np.abs(x - cx - sway) / half
    return np.where((yy >= 0) & (yy <= 1), inside, -1.0)


def flame_frame(t):
    """One frame (CELL x CELL RGBA, 0..255) of a lick at life t: it rises, sways and thins, its
    side tongues lagging, its tip breaking off late in life."""
    n = CELL
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    x = (xs + 0.5) / n * 2 - 1
    y = 1 - (ys + 0.5) / n  # 0 at the bottom
    grow = smooth(0.0, 0.3, np.array(t))
    height = 0.45 + 0.47 * grow
    width = 0.5 * (1 - 0.4 * t)
    inside = tongue(x, y, t, 0.0, height, width, 0.0)
    for side, lag in ((-1, 0.15), (1, 0.3)):
        tt = max(t - lag, 0.0)
        h2 = height * (0.5 + 0.2 * math.sin(t * 6 + side))
        inside = np.maximum(inside, tongue(x, y, tt, side * 0.2, h2, width * 0.55, 0.25 * side) * 0.9)
    # Late in life the tip pinches off: a soft waist climbs the flame and the tip floats free.
    if t > 0.55:
        k = (t - 0.55) / 0.45
        cut = height * (0.4 + 0.45 * k)
        inside = inside - 1.3 * k * np.exp(-((y - cut) / 0.07) ** 2)
    # Hard cel bands by depth inside, pushed up the flame a little (the core sits low).
    depth = inside * (1 - 0.35 * np.clip(y / height, 0, 1))
    col = np.zeros((n, n, 3))
    for start, hex_colour in BANDS:
        col = np.where((depth >= start)[..., None], rgb(hex_colour)[None, None, :], col)
    alpha = smooth(0.0, EDGE / width, inside)
    return np.dstack([col, alpha * 255.0])


def flames():
    sheet = np.zeros((FRAMES * CELL, FRAMES * CELL, 4))
    for k in range(FRAMES * FRAMES):
        row, colm = divmod(k, FRAMES)
        sheet[row * CELL:(row + 1) * CELL, colm * CELL:(colm + 1) * CELL] = flame_frame(k / (FRAMES * FRAMES - 1))
    return sheet


def radial(size, core, falloff, colour='#FFFFFF', core_colour=None):
    """A round sprite: alpha 1 inside `core` (of the radius) falling to 0 at the edge by `falloff`'s
    power; the colour toward `core_colour` at the centre."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    r = np.hypot((xs + 0.5) / size * 2 - 1, (ys + 0.5) / size * 2 - 1)
    alpha = np.clip(1 - smooth(core, 1.0, r), 0, 1) ** falloff
    col = np.broadcast_to(rgb(colour), (size, size, 3)).copy()
    if core_colour:
        k = (1 - smooth(0.0, 0.5, r))[..., None]
        col = col + (rgb(core_colour) - col) * k
    return np.dstack([col, alpha * 255.0])


def smoke(size=256):
    """A soft puff: a few overlapping round lobes, soft-edged (tinted by the emitter)."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    x, y = (xs + 0.5) / size * 2 - 1, (ys + 0.5) / size * 2 - 1
    alpha = np.zeros((size, size))
    for cx, cy, r in ((0.0, 0.1, 0.55), (-0.3, -0.15, 0.4), (0.3, -0.2, 0.42), (0.05, -0.4, 0.35)):
        d = np.hypot(x - cx, y - cy) / r
        alpha = np.maximum(alpha, 1 - smooth(0.55, 1.0, d))
    return np.dstack([np.full((size, size, 3), 255.0), alpha * 200.0])


def save(arr, name):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name), optimize=True)
    print('wrote', name)


if __name__ == '__main__':
    save(flames(), 'fire_flames.png')
    save(radial(64, 0.15, 1.6, '#FF8A2C', '#FFF6C8'), 'fire_ember.png')
    save(radial(256, 0.0, 2.2), 'fire_glow.png')
    save(smoke(), 'fire_smoke.png')
