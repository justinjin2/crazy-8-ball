#!/usr/bin/env python3
"""The Halloween Cues B sprites and silhouette flipbooks (docs/prompts/HW_CUES_B_PROMPT.md 2.7).

    python3 tools/hw_sprites_b.py [name ...]      (no names: all)

Procedural Pillow drawing, deterministic (no random module): every silhouette is a small
jointed rig of capsules and polygons posed by a function of the frame, drawn at 4x and
downsampled, then given its rim from the alpha edge (the alpha minus its erosion, 1-2 px at a
256 px cell, with a soft outer glow) and packed 4x4 at 1024 px with 8 px padding, as
CuePieces.sheet_sprite lays them. Flat sprites are 512 px, white with the shape in the alpha,
so a row's Color tints them.

    witch_broom/crescent          a crescent moon
    witch_broom/straw             a straw leaf with a midrib
    witch_broom/bat_flap_4x4      16 frames, Loop: a bat flapping, front view (symmetric, so it
                                  reads right from every side), black with a violet rim
    witch_broom/witch_moon_4x4    16 frames, OneShot: a pale full moon fades in, a witch on her
                                  broom crosses it with two bats, it fades out
    spider/web                    a radial web (spokes and a spiral)
    spider/silk                   a silk strand, tileable left to right (Beam texture)
    spider/web_ring               a ring decal of web strands
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VFX = os.path.join(ROOT, 'assets', 'cue', 'vfx')
SS = 4                 # supersampling
CELL = 256             # a flipbook cell
SHEET = 1024
PAD = 8
SIZE = 512             # a flat sprite

GOLD = (232, 176, 74)
VIOLET = (163, 92, 255)
MOON = (244, 235, 208)


# --------------------------------------------------------------------------- drawing helpers

class Canvas:
    """An alpha-only canvas in unit coordinates (x right, y up, 0..1), drawn at SS x `px`."""

    def __init__(self, px):
        self.px = px
        self.n = px * SS
        self.im = Image.new('L', (self.n, self.n), 0)
        self.d = ImageDraw.Draw(self.im)

    def P(self, p):
        return (p[0] * self.n, (1 - p[1]) * self.n)

    def capsule(self, a, b, r):
        ax, ay = self.P(a)
        bx, by = self.P(b)
        rr = r * self.n
        self.d.line([(ax, ay), (bx, by)], fill=255, width=int(round(2 * rr)))
        for x, y in ((ax, ay), (bx, by)):
            self.d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)

    def ellipse(self, c, rx, ry, angle=0.0):
        """An ellipse turned by `angle` (radians) about its centre."""
        n = 48
        pts = []
        for i in range(n):
            t = 2 * math.pi * i / n
            x, y = rx * math.cos(t), ry * math.sin(t)
            pts.append((c[0] + x * math.cos(angle) - y * math.sin(angle), c[1] + x * math.sin(angle) + y * math.cos(angle)))
        self.polygon(pts)

    def polygon(self, pts):
        self.d.polygon([self.P(p) for p in pts], fill=255)

    def stroke(self, pts, r):
        for a, b in zip(pts[:-1], pts[1:]):
            self.capsule(a, b, r)

    def alpha(self):
        return np.asarray(self.im.resize((self.px, self.px), Image.LANCZOS), np.float32) / 255.0


def rot(p, c, ang):
    """Turn point p about c by ang (radians)."""
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(ang) - y * math.sin(ang), c[1] + x * math.sin(ang) + y * math.cos(ang))


def limb(c, start, angles, lengths):
    """A chain of segments from `start`: angles (radians, from straight down, positive = forward
    (+x)), lengths; appends the joints to the canvas as capsules of shrinking radius."""
    pts = [start]
    p = start
    a = 0.0
    for ang, ln in zip(angles, lengths):
        a += ang
        p = (p[0] + ln * math.sin(a), p[1] - ln * math.cos(a))
        pts.append(p)
    return pts


def bezier(p0, p1, p2, p3, n=12):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def rimmed(alpha, fill, rim, rim_px=1.5, glow_px=5, glow=0.5):
    """An RGBA image: `fill` inside the alpha, `rim` along its edge (alpha minus its erosion),
    a soft `rim`-coloured glow outside."""
    h, w = alpha.shape
    a8 = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8))
    k = int(round(rim_px * 2)) | 1
    eroded = np.asarray(a8.filter(ImageFilter.MinFilter(k)), np.float32) / 255.0
    edge = np.clip(alpha - eroded, 0, 1)
    dil = np.asarray(a8.filter(ImageFilter.MaxFilter(int(glow_px) * 2 + 1)).filter(ImageFilter.GaussianBlur(glow_px * 0.8)), np.float32) / 255.0
    halo = np.clip(dil - alpha, 0, 1) * glow
    rgb = np.zeros((h, w, 3), np.float32)
    fill = np.array(fill, np.float32) / 255.0
    rim = np.array(rim, np.float32) / 255.0
    rgb[...] = fill
    rgb = rgb * (1 - edge[..., None]) + rim * edge[..., None]
    out_a = np.clip(alpha + halo, 0, 1)
    outside = (alpha < 0.02)
    rgb[outside] = rim
    img = np.dstack([rgb, out_a])
    return Image.fromarray((img * 255 + 0.5).astype(np.uint8))


def sheet(frames, fade=None):
    """Pack 16 RGBA cell images 4x4 at 1024 with 8 px padding (CueVfx.flipbook's layout)."""
    cell = SHEET // 4
    out = Image.new('RGBA', (SHEET, SHEET), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        im = im.resize((cell - 2 * PAD, cell - 2 * PAD), Image.LANCZOS)
        if fade:
            a = im.getchannel('A').point(lambda v, f=fade(i, len(frames)): int(v * f))
            im.putalpha(a)
        r, c = divmod(i, 4)
        out.paste(im, (c * cell + PAD, r * cell + PAD))
    return out


def save(skin, name, img):
    os.makedirs(os.path.join(VFX, skin), exist_ok=True)
    path = os.path.join(VFX, skin, name + '.png')
    img.save(path, optimize=True)
    print('wrote', os.path.relpath(path, ROOT), '%dx%d' % img.size)


def flat(alpha, rgb=None):
    """White (or rgb 0..1 HxWx3) with alpha 0..1 as an RGBA image."""
    h, w = alpha.shape
    if rgb is None:
        rgb = np.ones((h, w, 3), np.float32)
    return Image.fromarray((np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)]) * 255 + 0.5).astype(np.uint8))


def grid(n):
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, -c)
    return x, y, np.hypot(x, y), np.arctan2(y, x)


def smooth(t, a, b):
    t = np.clip((np.asarray(t, np.float32) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def hash01(i, j):
    h = (i * 374761393 + j * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0xFFFFFF)


# --------------------------------------------------------------------------- the bat and the witch

def bat_pose(cv, c, s, flap):
    """A bat, front view, wings up at flap = 1, down at -1: symmetric."""
    cv.ellipse(c, 0.07 * s, 0.11 * s)
    head = (c[0], c[1] + 0.11 * s)
    cv.ellipse(head, 0.06 * s, 0.055 * s)
    for side in (-1, 1):
        cv.polygon([(head[0] + 0.02 * s * side, head[1] + 0.03 * s), (head[0] + 0.05 * s * side, head[1] + 0.11 * s), (head[0] + 0.065 * s * side, head[1] + 0.02 * s)])
        sh = (c[0] + 0.05 * s * side, c[1] + 0.05 * s)
        wrist = (sh[0] + 0.26 * s * side, sh[1] + 0.22 * s * flap)
        tip = (wrist[0] + 0.2 * s * side, wrist[1] + 0.08 * s * flap - 0.04 * s)
        f1 = (wrist[0] + 0.1 * s * side, c[1] - 0.14 * s + 0.1 * s * flap)
        f2 = (sh[0] + 0.1 * s * side, c[1] - 0.12 * s + 0.02 * s * flap)
        cv.polygon([sh, wrist, tip, f1, f2, (c[0], c[1] - 0.09 * s)])
        cv.capsule(sh, wrist, 0.014 * s)
        cv.capsule(wrist, tip, 0.01 * s)


def bat_flap():
    frames = []
    for i in range(16):
        cv = Canvas(CELL)
        ph = 2 * math.pi * i / 16
        flap = math.sin(ph)
        bat_pose(cv, (0.5, 0.5 - 0.03 * math.cos(ph)), 0.95, flap)
        frames.append(rimmed(cv.alpha(), (0, 0, 0), VIOLET, rim_px=1.5, glow_px=4, glow=0.35))
    return sheet(frames)


def witch_pose(cv, c, s, lean):
    """A witch on a broom facing +x: hat, head, cloak, arm, legs, the broom with bristles."""
    def T(p):
        return rot((c[0] + p[0] * s, c[1] + p[1] * s), c, lean)
    # the broom: a long stick, bristles at the back
    cv.capsule(T((-0.32, -0.12)), T((0.32, -0.04)), 0.018 * s)
    for k in range(7):
        a = -0.35 + 0.1 * k
        cv.capsule(T((-0.32, -0.12)), T((-0.48 - 0.02 * abs(3 - k), -0.14 + 0.055 * math.sin(a * 3))), 0.016 * s)
    # the body: a cloak flaring back, the torso leaning forward
    cv.polygon([T((-0.02, 0.0)), T((0.1, 0.16)), T((0.16, 0.14)), T((0.12, -0.02)), T((-0.16, -0.06))])
    cv.capsule(T((0.06, 0.0)), T((0.13, 0.17)), 0.045 * s)
    # the head and the hat: a tall crooked point, a wide brim
    head = T((0.15, 0.22))
    cv.ellipse(head, 0.05 * s, 0.05 * s)
    cv.polygon([T((0.06, 0.25)), T((0.24, 0.25)), T((0.2, 0.28)), T((0.1, 0.28))])
    cv.polygon([T((0.1, 0.27)), T((0.2, 0.27)), T((0.2, 0.36)), T((0.3, 0.5)), T((0.12, 0.42))])
    # arms to the broom, legs trailing back
    cv.capsule(T((0.12, 0.12)), T((0.26, 0.0)), 0.028 * s)
    cv.capsule(T((0.0, -0.02)), T((-0.1, -0.16)), 0.032 * s)
    cv.capsule(T((-0.1, -0.16)), T((-0.2, -0.14)), 0.024 * s)
    # hair streaming back
    cv.capsule(T((0.12, 0.2)), T((-0.05, 0.22)), 0.02 * s)
    cv.capsule(T((0.1, 0.17)), T((-0.08, 0.17)), 0.015 * s)


def moon_disc(n, c, r):
    x, y, _, _ = grid(n)
    cx, cy = c[0] * 2 - 1, c[1] * 2 - 1
    d = np.hypot(x - cx, y - cy)
    disc = smooth(d, r, r - 0.02)
    shade = np.ones_like(d)
    for i in range(14):
        px, py = (hash01(i, 1) * 2 - 1) * r * 0.85 + cx, (hash01(i, 2) * 2 - 1) * r * 0.85 + cy
        pr = r * (0.06 + 0.12 * hash01(i, 3))
        shade = shade * (1 - 0.08 * smooth(np.hypot(x - px, y - py), pr, pr * 0.5))
    rim_dark = 1 - 0.1 * smooth(d, r - 0.08, r)
    rgb = np.dstack([np.full_like(d, MOON[0] / 255.0), np.full_like(d, MOON[1] / 255.0), np.full_like(d, MOON[2] / 255.0)]) * (shade * rim_dark)[..., None]
    halo = smooth(d, r + 0.18, r) * 0.35
    return disc, np.clip(halo, 0, 1), rgb


def witch_moon():
    frames = []
    disc, halo, moon_rgb = moon_disc(CELL, (0.5, 0.5), 0.44)
    for i in range(16):
        t = i / 15
        moon_a = smooth(i, 0, 3) * (1 - smooth(i, 12, 15))
        cv = Canvas(CELL)
        wfade = 0.0
        if 1 <= i <= 14:
            u = (i - 1) / 13
            x = 0.1 + 0.8 * u
            y = 0.52 + 0.1 * math.sin(math.pi * u)
            witch_pose(cv, (x, y), 0.48, 0.12 * math.cos(math.pi * u))
            # two small bats trailing behind
            for b, (dx, dy, ph) in enumerate(((-0.2, 0.13, 0.0), (-0.24, -0.1, 2.0))):
                bat_pose(cv, (x + dx, y + dy), 0.13, math.sin(u * 14 + ph))
            wfade = float(smooth(u, 0.0, 0.18) * (1 - smooth(u, 0.82, 1.0)))
        sil = cv.alpha() * wfade
        witch = rimmed(sil, (12, 6, 24), VIOLET, rim_px=1.2, glow_px=3, glow=0.3)
        wa = np.asarray(witch, np.float32) / 255.0
        # compose: the moon (with its halo) under the witch
        moon_layer_a = np.clip(disc + halo, 0, 1) * moon_a
        moon_layer_rgb = moon_rgb * disc[..., None] + np.array(MOON, np.float32)[None, None, :] / 255.0 * (halo * (1 - disc))[..., None]
        base_a = moon_layer_a
        base_rgb = np.where(base_a[..., None] > 0, moon_layer_rgb / np.maximum(np.clip(disc + halo, 0, 1), 1e-3)[..., None], 0)
        out_a = wa[..., 3] + base_a * (1 - wa[..., 3])
        out_rgb = (wa[..., :3] * wa[..., 3:4] + base_rgb * (base_a * (1 - wa[..., 3]))[..., None]) / np.maximum(out_a[..., None], 1e-3)
        frames.append(Image.fromarray((np.dstack([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)]) * 255 + 0.5).astype(np.uint8)))
    return sheet(frames)


# --------------------------------------------------------------------------- flat sprites

def crescent():
    x, y, r, a = grid(SIZE)
    disc = smooth(r, 0.72, 0.68)
    bite = smooth(np.hypot(x - 0.3, y - 0.12), 0.62, 0.58)
    alpha = np.clip(disc - bite, 0, 1)
    glow = smooth(r, 0.95, 0.6) * 0.25 * (1 - bite)
    return flat(np.clip(alpha + glow * (1 - alpha), 0, 1))


def straw():
    x, y, r, a = grid(SIZE)
    # a long tapered leaf along x with a soft curve and a midrib
    yc = 0.12 * np.sin(x * 2.2)
    width = 0.13 * np.clip(1 - np.abs(x / 0.85) ** 2.2, 0, 1) * (0.5 + 0.5 * (1 - (x + 0.85) / 1.7))
    body = smooth(np.abs(y - yc) - width, 0.01, -0.01) * (np.abs(x) < 0.86)
    rib = smooth(np.abs(y - yc), 0.012, 0.004) * (np.abs(x) < 0.8)
    rgb = np.dstack([np.ones_like(x), np.ones_like(x), np.ones_like(x)]) * (1 - 0.35 * rib)[..., None]
    return flat(body, rgb)


def web():
    x, y, r, a = grid(SIZE)
    spokes = np.zeros_like(r)
    for k in range(10):
        ang = 2 * math.pi * k / 10
        dist = np.abs(x * math.sin(ang) - y * math.cos(ang))
        along = x * math.cos(ang) + y * math.sin(ang)
        spokes = np.maximum(spokes, smooth(dist, 0.012, 0.004) * (along > 0))
    spiral = np.zeros_like(r)
    for k in range(7):
        rk = 0.12 + 0.12 * k
        sag = 0.01 * np.cos(a * 10)
        spiral = np.maximum(spiral, smooth(np.abs(r - rk - sag), 0.01, 0.003))
    alpha = np.clip(spokes + spiral, 0, 1) * smooth(r, 0.95, 0.85)
    glow = (np.clip(spokes + spiral, 0, 1)) * 0.3
    a8 = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
    soft = np.asarray(a8, np.float32) / 255.0 * 0.5
    return flat(np.clip(alpha + soft * (1 - alpha) + glow * 0, 0, 1))


def silk():
    x, y, r, a = grid(SIZE)
    u = (x + 1) / 2
    strand = np.zeros_like(x)
    for k in range(3):
        yc = 0.12 * np.sin(2 * math.pi * (u * (1 + k) + k * 0.3)) * (0.5 + 0.5 * k) - 0.2 + 0.2 * k
        strand = np.maximum(strand, smooth(np.abs(y - yc), 0.014 - 0.003 * k, 0.003))
    beads = np.zeros_like(x)
    for k in range(12):
        bx, by = hash01(k, 1) * 2 - 1, (hash01(k, 2) * 2 - 1) * 0.6
        beads = np.maximum(beads, smooth(np.hypot(x - bx, y - by), 0.05, 0.015) * (0.4 + 0.6 * hash01(k, 3)))
    alpha = np.clip(strand + beads, 0, 1)
    return flat(alpha)


def web_ring():
    x, y, r, a = grid(SIZE)
    ring = smooth(np.abs(r - 0.78), 0.05, 0.02)
    inner = smooth(np.abs(r - 0.66), 0.03, 0.01) * 0.7
    spokes = np.zeros_like(r)
    for k in range(24):
        ang = 2 * math.pi * k / 24
        dist = np.abs(x * math.sin(ang) - y * math.cos(ang))
        along = x * math.cos(ang) + y * math.sin(ang)
        spokes = np.maximum(spokes, smooth(dist, 0.012, 0.004) * (along > 0.6) * (along < 0.86))
    sag = smooth(np.abs(r - (0.72 + 0.02 * np.cos(a * 24))), 0.012, 0.004) * 0.8
    alpha = np.clip(ring + inner + spokes + sag, 0, 1) * smooth(r, 0.95, 0.88)
    return flat(alpha)


SPRITES = {
    'witch_broom/crescent': crescent, 'witch_broom/straw': straw,
    'witch_broom/bat_flap_4x4': bat_flap, 'witch_broom/witch_moon_4x4': witch_moon,
    'spider/web': web, 'spider/silk': silk, 'spider/web_ring': web_ring,
}


def main():
    names = sys.argv[1:] or list(SPRITES)
    for name in names:
        key = name if name in SPRITES else next((k for k in SPRITES if k.endswith('/' + name)), None)
        if key is None:
            sys.exit('unknown sprite %s (have %s)' % (name, ', '.join(SPRITES)))
        skin, base = key.split('/')
        save(skin, base, SPRITES[key]())


if __name__ == '__main__':
    main()
