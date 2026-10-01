#!/usr/bin/env python3
"""The cue VFX v2 sprite library (designer, 2026-10-01: auras must read in the bright lobby).

    python3 tools/vfx_sprites.py [name ...]      (no names: all) -> assets/cue/vfx/v2/<name>.png

Procedural, crisp, high-contrast sprites at 512 px (flipbooks 1024 px, 8x8 cells of 128 px),
white with the shape in the alpha so a ParticleEmitter's Color tints them: the same sheet makes
an additive HDR glow (LightEmission 1, Brightness 3-8) or a saturated body layer
(LightEmission 0-0.4) that reads on a white floor. Deterministic (fixed seeds).

    flare        8-point star: long thin cross rays, short diagonals, hot core, soft halo
    glint        anamorphic glint: one long thin ray pair and a small cross
    orb          dense glowing orb: solid core, steep falloff, faint halo
    ring         crisp ring with an inner and outer glow (shockwaves, halos)
    dust         a cluster of tiny sparkles in one sprite (dense look at low counts)
    shard        a faceted crystal shard with a bright edge
    streak       a long soft streak (velocity-aligned speed lines, rising embers)
    smoke_8x8    64 frames: a soft wispy puff that swirls, grows and thins out
    wisp_8x8     64 frames: energy tendrils curling up (aura flames, spirit energy)
    flame_8x8    64 frames: a flame tongue licking upward
    swirl_8x8    64 frames: a spiral of energy turning (orbs, portals, magic)
    eclipse_orb  (coloured) a black moon disc inside a blazing gold ring with fiery corona rays
"""
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'cue', 'vfx', 'v2')
SIZE = 512
SHEET = 1024
CELL = SHEET // 8


# --------------------------------------------------------------------------- helpers

def grid(n):
    """Coordinates in -1..1 (y up), radius and angle, for an n x n image."""
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, -c)
    return x, y, np.hypot(x, y), np.arctan2(y, x)


def save(name, alpha, rgb=None):
    """White (or `rgb` 0..1) with `alpha` 0..1 as an RGBA PNG."""
    alpha = np.clip(alpha, 0, 1)
    h, w = alpha.shape
    if rgb is None:
        rgb = np.ones((h, w, 3))
    img = np.dstack([np.clip(rgb, 0, 1), alpha])
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.png')
    Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGBA').save(path, optimize=True)
    print('wrote', os.path.relpath(path, ROOT), '%dx%d' % (w, h))


def edge_fade(a, r, start=0.82):
    """Fade alpha to zero toward the sprite's edge so no square ever shows."""
    return a * np.clip((1 - r) / (1 - start), 0, 1)


class Noise:
    """Smooth 3D value noise (x, y, t) with fbm and domain warping, seeded."""

    def __init__(self, seed, res=64):
        rng = np.random.default_rng(seed)
        self.res = res
        self.lat = rng.random((res, res, res))

    def value(self, x, y, z):
        r = self.res
        x, y, z = x % r, y % r, z % r
        x0, y0, z0 = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
        fx, fy, fz = x - x0, y - y0, z - z0
        fx, fy, fz = [f * f * (3 - 2 * f) for f in (fx, fy, fz)]
        x1, y1, z1 = (x0 + 1) % r, (y0 + 1) % r, (z0 + 1) % r
        L = self.lat

        def lerp(a, b, t):
            return a + (b - a) * t
        c00 = lerp(L[x0, y0, z0], L[x1, y0, z0], fx)
        c10 = lerp(L[x0, y1, z0], L[x1, y1, z0], fx)
        c01 = lerp(L[x0, y0, z1], L[x1, y0, z1], fx)
        c11 = lerp(L[x0, y1, z1], L[x1, y1, z1], fx)
        return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)

    def fbm(self, x, y, z, octaves=5, gain=0.5):
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for _ in range(octaves):
            total = total + amp * self.value(x * freq, y * freq, z * freq + 17 * freq)
            norm += amp
            amp *= gain
            freq *= 2.0
        return total / norm


def sheet(frames):
    """64 frames (CELL x CELL alpha arrays) into one 8x8 sheet, row-major from the top left."""
    a = np.zeros((SHEET, SHEET))
    for i, f in enumerate(frames):
        r, c = divmod(i, 8)
        a[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = f
    return a


# --------------------------------------------------------------------------- single sprites

def flare():
    x, y, r, th = grid(SIZE)
    core = np.exp(-(r / 0.05) ** 2) + 0.55 * np.exp(-(r / 0.16) ** 2)
    halo = 0.22 * np.exp(-(r / 0.42) ** 2)

    def ray(along, across, length, width):
        return np.exp(-(across / width) ** 2) * np.clip(1 - np.abs(along) / length, 0, 1) ** 2.2
    rays = ray(x, y, 1.0, 0.012) + ray(y, x, 1.0, 0.012)
    d1, d2 = (x + y) / math.sqrt(2), (x - y) / math.sqrt(2)
    rays += 0.55 * (ray(d1, d2, 0.55, 0.01) + ray(d2, d1, 0.55, 0.01))
    a = np.clip(core + halo + rays, 0, 1)
    save('flare', edge_fade(a, r, 0.9))


def glint():
    x, y, r, th = grid(SIZE)
    core = np.exp(-(r / 0.04) ** 2) + 0.4 * np.exp(-(r / 0.12) ** 2)
    long = np.exp(-(y / 0.01) ** 2) * np.clip(1 - np.abs(x), 0, 1) ** 1.6
    short = 0.6 * np.exp(-(x / 0.01) ** 2) * np.clip(1 - np.abs(y) / 0.35, 0, 1) ** 2
    halo = 0.12 * np.exp(-((x / 0.5) ** 2 + (y / 0.12) ** 2))
    save('glint', edge_fade(np.clip(core + long + short + halo, 0, 1), r, 0.9))


def orb():
    x, y, r, th = grid(SIZE)
    a = np.clip(1.15 - (r / 0.34) ** 3, 0, 1) * 0.9 + 0.35 * np.exp(-(r / 0.55) ** 2)
    rgb = np.ones((SIZE, SIZE, 3))
    save('orb', edge_fade(np.clip(a, 0, 1), r))


def ring():
    x, y, r, th = grid(SIZE)
    band = np.exp(-((r - 0.72) / 0.022) ** 2)
    glow = 0.45 * np.exp(-((r - 0.72) / 0.09) ** 2)
    inner = 0.12 * np.clip(r / 0.72, 0, 1) ** 4 * (r < 0.72)
    save('ring', edge_fade(np.clip(band + glow + inner, 0, 1), r, 0.92))


def dust():
    x, y, r, th = grid(SIZE)
    rng = np.random.default_rng(7)
    a = np.zeros_like(x)
    for _ in range(26):
        cx, cy = rng.normal(0, 0.32, 2)
        s = rng.uniform(0.012, 0.03)
        d = np.hypot(x - cx, y - cy)
        k = rng.uniform(0.5, 1)
        a += k * (np.exp(-(d / s) ** 2) + 0.25 * np.exp(-(d / (s * 3.5)) ** 2))
        # a few with tiny cross rays
        if rng.random() < 0.35:
            a += 0.6 * k * (np.exp(-((y - cy) / 0.006) ** 2) * np.clip(1 - np.abs(x - cx) / (s * 6), 0, 1)
                            + np.exp(-((x - cx) / 0.006) ** 2) * np.clip(1 - np.abs(y - cy) / (s * 6), 0, 1))
    save('dust', edge_fade(np.clip(a, 0, 1), r))


def shard():
    x, y, r, th = grid(SIZE)
    # a long diamond: |x|/w + |y|/h < 1, with facets lit differently
    w, h = 0.26, 0.9
    d = np.abs(x) / w + np.abs(y) / h
    body = np.clip((1 - d) / 0.04, 0, 1)
    facet = np.where(x > 0, 0.75, 0.45) + 0.25 * (y > 0)
    edge = np.exp(-((1 - d) / 0.035) ** 2) * (d < 1.02)
    ridge = np.exp(-(x / 0.012) ** 2) * (d < 1)
    a = np.clip(body * facet * 0.85 + edge * 0.9 + ridge * 0.6, 0, 1)
    glow = 0.25 * np.exp(-((x / 0.4) ** 2 + (y / 1.0) ** 2))
    save('shard', edge_fade(np.clip(a + glow * (1 - body), 0, 1), r, 0.95))


def streak():
    x, y, r, th = grid(SIZE)
    a = np.exp(-(x / 0.07) ** 2) * np.clip(1 - np.abs(y), 0, 1) ** 1.3
    a += 0.8 * np.exp(-(x / 0.02) ** 2) * np.clip(1 - np.abs(y) / 0.8, 0, 1) ** 2
    save('streak', edge_fade(np.clip(a, 0, 1), r, 0.95))


# --------------------------------------------------------------------------- flipbooks

def smoke():
    n = Noise(11)
    x, y, r, th = grid(CELL)
    frames = []
    for i in range(64):
        t = i / 63
        grow = 0.45 + 0.5 * t
        swirl = th + 1.2 * t * (1 - r)
        wx = x + 0.25 * np.cos(swirl * 2 + t * 3)
        wy = y + 0.25 * np.sin(swirl * 2 + t * 3)
        f = n.fbm(wx * 2.4 + 5, wy * 2.4 + 5 - t * 1.5, t * 2.5, 5)
        mask = np.clip(1 - (r / grow) ** 2, 0, 1) ** 0.7
        density = np.clip((f - 0.22 - 0.2 * t) * 2.6, 0, 1) * mask
        fade = min(1.0, t / 0.08) * (1 - t) ** 0.6
        frames.append(edge_fade(density * fade, r, 0.86))
    save('smoke_8x8', sheet(frames))


def wisp():
    n = Noise(23)
    x, y, r, th = grid(CELL)
    frames = []
    for i in range(64):
        t = i / 63
        # tendrils: stripes along y bent by warped noise, rising with t
        warp = n.fbm(x * 2.2, y * 2.2 - t * 2.0, t * 3.0, 4) - 0.5
        u = x * 3.2 + warp * 3.0
        lines = np.exp(-((np.sin(u * math.pi) * 1.0) / 0.5) ** 2)
        body = np.clip(1 - np.abs(x) / 0.75, 0, 1) * np.clip((y + 0.95) / 0.4, 0, 1) * np.clip((0.95 - y) / 0.9, 0, 1)
        breakup = np.clip((n.fbm(x * 3, y * 3 - t * 4, t * 5 + 3, 4) - 0.25) * 2.4, 0, 1)
        fade = min(1.0, t / 0.12) * (1 - t) ** 0.8
        a = lines * body * breakup * fade
        frames.append(edge_fade(np.clip(a * 1.6, 0, 1), r, 0.88))
    save('wisp_8x8', sheet(frames))


def flame():
    n = Noise(31)
    x, y, r, th = grid(CELL)
    frames = []
    for i in range(64):
        t = i / 63
        rise = t * 3.0
        f = n.fbm(x * 2.6, y * 2.0 - rise, t * 2.0, 5)
        # teardrop: wide at the bottom, narrowing upward
        width = 0.55 * np.clip((0.9 - y) / 1.6, 0.05, 1) ** 0.8
        shape = np.clip(1 - np.abs(x + (f - 0.5) * 0.5) / width, 0, 1)
        vert = np.clip((y + 0.85) / 0.25, 0, 1) * np.clip((0.95 - y) / 1.2, 0, 1)
        lick = np.clip((f - 0.3 + 0.35 * (1 - (y + 1) / 2)) * 2.4, 0, 1)
        fade = min(1.0, t / 0.06) * (1 - t ** 1.5)
        a = shape ** 0.8 * vert * lick * fade
        frames.append(edge_fade(np.clip(a * 1.5, 0, 1), r, 0.9))
    save('flame_8x8', sheet(frames))


def swirl():
    n = Noise(41)
    x, y, r, th = grid(CELL)
    frames = []
    for i in range(64):
        t = i / 63
        ang = th - 3.2 * r + t * math.tau
        arms = np.clip(np.cos(ang * 3) * 0.5 + 0.5, 0, 1) ** 3
        brk = np.clip((n.fbm(r * 4, ang * 0.6, t * 2.0 + 1, 4) - 0.3) * 2.2, 0, 1)
        mask = np.clip(1 - (r / 0.9) ** 2, 0, 1) * np.clip(r / 0.08, 0, 1)
        core = 0.6 * np.exp(-(r / 0.12) ** 2)
        a = (arms * brk * mask + core)
        frames.append(edge_fade(np.clip(a * 1.4, 0, 1), r, 0.9))
    save('swirl_8x8', sheet(frames))


def eclipse_orb():
    """Coloured, not tinted: the Eclipse cue's glowing eclipse (Color white on the emitter)."""
    n = Noise(53)
    x, y, r, th = grid(SIZE)
    R = 0.42
    disc = np.clip((R - r) / 0.006, 0, 1)
    ring = np.exp(-((r - R) / 0.018) ** 2)
    rays = n.fbm(np.cos(th) * 3 + 10, np.sin(th) * 3 + 10, r * 2.0, 5)
    corona = np.clip(1 - (r - R) / (0.12 + 0.38 * rays ** 2), 0, 1) ** 2.2 * (r > R)
    glow = np.exp(-((r - R) / 0.2) ** 2) * (r > R) * 0.6
    light = np.clip(ring + corona * 0.85 + glow * 0.5, 0, 1)
    # colour: white-hot at the ring, gold to deep orange outward; the disc is near-black
    t = np.clip((r - R) / 0.45, 0, 1)
    gold = np.dstack([np.ones_like(t), 0.92 - 0.45 * t, 0.55 - 0.5 * t])
    hot = np.dstack([np.ones_like(t)] * 3)
    k = ring[..., None]
    rgb = hot * k + gold * (1 - k)
    rgb = rgb * (1 - disc[..., None]) + np.dstack([np.full_like(t, 0.02)] * 3) * disc[..., None]
    alpha = np.clip(disc + light, 0, 1)
    save('eclipse_orb', edge_fade(alpha, r, 0.92), rgb)


ALL = {
    'flare': flare, 'glint': glint, 'orb': orb, 'ring': ring, 'dust': dust, 'shard': shard,
    'streak': streak, 'smoke_8x8': smoke, 'wisp_8x8': wisp, 'flame_8x8': flame,
    'swirl_8x8': swirl, 'eclipse_orb': eclipse_orb,
}

if __name__ == '__main__':
    names = sys.argv[1:] or list(ALL)
    for name in names:
        ALL[name]()
