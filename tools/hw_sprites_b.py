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
                                  broom crosses it with two bats, it fades out (shipped until v3)
    witch_broom/witch_fly_8x8     64 frames, OneShot (v3, designer 2026-10-29: no moon, the witch
                                  much smoother and faster): the witch alone sweeps across in an
                                  arc, her cloak, hair, hat tip and bristles fluttering, a gold and
                                  violet sparkle trail streaming off the bristles; 128 px cells
    witch_broom/star5             a five-point star with a soft glow, 256 px (v3: the finisher's
                                  star fountain and bursts)
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


def sheet8(frames, pad=3):
    """Pack 64 RGBA cell images 8x8 at 1024 (128 px cells, `pad` px clear round each)."""
    cell = SHEET // 8
    out = Image.new('RGBA', (SHEET, SHEET), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        im = im.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS)
        r, c = divmod(i, 8)
        out.paste(im, (c * cell + pad, r * cell + pad))
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


def witch_fly_pose(cv, c, s, lean, ph):
    """A fuller witch on her broom facing +x for the 128 px cells (v3): a thick stick and a solid
    bristle fan, a big cloak, a hooked nose, a wide brim and a crooked hat; the flight's flutter
    at phase `ph` (radians): the cloak's hem and the hair wave, the hat tip flops, the boot
    kicks, the bristles splay and close."""
    def T(p):
        return rot((c[0] + p[0] * s, c[1] + p[1] * s), c, lean)
    w1, w2, w3 = math.sin(ph), math.sin(ph + 1.3), math.sin(ph + 2.6)
    # the broom: the stick, then a solid fan of bristles with ragged tips
    cv.capsule(T((-0.34, -0.1)), T((0.42, -0.02)), 0.03 * s)
    spread = 0.11 + 0.025 * w2
    fan = [T((-0.3, -0.07))]
    for k in range(7):
        t = k / 6
        tip_y = -0.1 + spread * (1 - 2 * t) - 0.03 * t
        tip_x = -0.6 - 0.05 * (0.5 + 0.5 * math.sin(k * 2.3 + ph * 1.5))
        fan.append(T((tip_x, tip_y)))
        if k < 6:
            fan.append(T((tip_x + 0.07, tip_y - spread / 6)))
    fan.append(T((-0.3, -0.13)))
    cv.polygon(fan)
    cv.capsule(T((-0.33, -0.065)), T((-0.33, -0.135)), 0.02 * s)
    # the cloak: from the shoulders back past the broom, its hem waving
    cv.polygon([T((0.11, 0.2)), T((0.03, 0.21)), T((-0.12, 0.15 + 0.03 * w1)), T((-0.3 - 0.04 * w2, 0.1 + 0.05 * w3)),
                T((-0.2, 0.05 + 0.04 * w2)), T((-0.24 - 0.03 * w1, 0.0 + 0.03 * w3)), T((-0.05, -0.05)), T((0.05, -0.05))])
    # the body leaning forward, the arm to the broom
    cv.polygon([T((-0.05, -0.07)), T((0.07, -0.07)), T((0.17, 0.12)), T((0.12, 0.21)), T((0.0, 0.17))])
    cv.capsule(T((0.11, 0.15)), T((0.3, -0.03)), 0.036 * s)
    cv.ellipse(T((0.31, -0.03)), 0.03 * s, 0.03 * s)

    # the leg tucked back with a pointed boot that kicks a little
    knee = (-0.04 + 0.01 * w3, -0.15 + 0.015 * w3)
    cv.capsule(T((0.02, -0.06)), T(knee), 0.042 * s)
    boot = (knee[0] - 0.13, knee[1] - 0.01 + 0.02 * w1)
    cv.capsule(T(knee), T(boot), 0.032 * s)
    cv.polygon([T((0.04, -0.06)), T(knee), T(boot), T((boot[0], -0.1)), T((-0.05, -0.085))])
    cv.polygon([T((boot[0] + 0.02, boot[1] + 0.03)), T((boot[0] - 0.07, boot[1] + 0.03)), T((boot[0] + 0.02, boot[1] - 0.03))])
    # the head with a hooked nose
    cv.ellipse(T((0.15, 0.255)), 0.062 * s, 0.062 * s)
    cv.polygon([T((0.19, 0.27)), T((0.27, 0.235)), T((0.2, 0.235))])
    # the hat: a wide tilted brim and a crooked cone whose tip flops back with the wind
    cv.ellipse(T((0.14, 0.3)), 0.15 * s, 0.026 * s, angle=lean * 0 - 0.12)
    flop = 0.5 + 0.5 * w1
    cv.polygon([T((0.06, 0.305)), T((0.23, 0.3)), T((0.2, 0.39)), T((0.12 - 0.08 * flop, 0.52 - 0.02 * flop)),
                T((0.13, 0.42)), T((0.08, 0.36))])
    # hair streaming back in waves
    cv.stroke([T((0.11, 0.24)), T((0.02, 0.25 + 0.02 * w2)), T((-0.08, 0.235 + 0.035 * w3)), T((-0.16, 0.24 + 0.03 * w1))], 0.024 * s)
    cv.stroke([T((0.1, 0.2)), T((0.0, 0.19 + 0.025 * w3)), T((-0.1, 0.18 + 0.03 * w1))], 0.02 * s)


def star_alpha(cv, c, r, points=4, inner=0.32, ang=0.0):
    """A pointed star (4 or 5 points) of outer radius r at c (unit coordinates)."""
    pts = []
    for i in range(points * 2):
        a = ang + math.pi / 2 + math.pi * i / points
        rr = r if i % 2 == 0 else r * inner
        pts.append((c[0] + rr * math.cos(a), c[1] + rr * math.sin(a)))
    cv.polygon(pts)


def witch_fly():
    """64 frames: the witch alone (no moon) sweeping across the cell in a rising arc, about 1.1 s
    in game (the finisher's Lifetime; 58 frames a second), so she reads as a smooth, fast fly-by.
    A sparkle trail (gold stars to violet, shrinking) streams off her bristles."""
    frames = []
    n = 64
    s = 0.52
    gold = np.array((255, 214, 110), np.float32) / 255.0
    violet = np.array((190, 130, 255), np.float32) / 255.0

    def path(u):
        x = 0.32 + 0.46 * u
        y = 0.4 + 0.14 * math.sin(math.pi * u) + 0.012 * math.sin(2 * math.pi * 3 * u)
        lean = 0.14 * math.cos(math.pi * u)
        return x, y, lean
    for i in range(n):
        u = i / (n - 1)
        x, y, lean = path(u)
        ph = 2 * math.pi * 5 * u
        cv = Canvas(CELL // 2)
        witch_fly_pose(cv, (x, y), s, lean, ph)
        fade = float(smooth(u, 0.0, 0.08) * (1 - smooth(u, 0.9, 1.0)))
        witch = np.asarray(rimmed(cv.alpha() * fade, (14, 7, 28), VIOLET, rim_px=1.0, glow_px=1, glow=0.3), np.float32) / 255.0
        # the sparkle trail: stars where the bristles were a moment ago, older ones smaller and violet
        sp = Canvas(CELL // 2)
        sp_col = np.zeros((CELL // 2, CELL // 2, 3), np.float32)
        sp_a = np.zeros((CELL // 2, CELL // 2), np.float32)
        for kk in range(1, 9):
            ub = u - 0.065 * kk
            if ub < 0:
                break
            bx, by, bl = path(ub)
            p = rot((bx - 0.6 * s, by - 0.1 * s + 0.025 * math.sin(kk * 2.1 + i * 0.4)), (bx, by), bl)
            age = kk / 8
            one = Canvas(CELL // 2)
            star_alpha(one, p, (0.042 - 0.024 * age) * (0.85 + 0.3 * hash01(i, kk)), 4, 0.32, 0.4 * kk)
            a1 = one.alpha() * (1 - 0.75 * age) * fade
            col = gold * (1 - age) + violet * age
            sp_col = sp_col * (1 - a1[..., None]) + col[None, None] * a1[..., None]
            sp_a = sp_a + a1 * (1 - sp_a)
        glow = np.asarray(Image.fromarray((np.clip(sp_a, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6)), np.float32) / 255.0 * 0.6
        sp_rgb = np.where(sp_a[..., None] > 1e-3, sp_col / np.maximum(sp_a[..., None], 1e-3), gold[None, None])
        under_a = np.clip(sp_a + glow * (1 - sp_a), 0, 1)
        wa = witch[..., 3]
        out_a = wa + under_a * (1 - wa)
        out_rgb = (witch[..., :3] * wa[..., None] + sp_rgb * (under_a * (1 - wa))[..., None]) / np.maximum(out_a[..., None], 1e-3)
        frames.append(Image.fromarray((np.dstack([np.clip(out_rgb, 0, 1), np.clip(out_a, 0, 1)]) * 255 + 0.5).astype(np.uint8)))
    return sheet8(frames)


# --------------------------------------------------------------------------- flat sprites

def crescent():
    x, y, r, a = grid(SIZE)
    disc = smooth(r, 0.72, 0.68)
    bite = smooth(np.hypot(x - 0.3, y - 0.12), 0.62, 0.58)
    alpha = np.clip(disc - bite, 0, 1)
    glow = smooth(r, 0.95, 0.6) * 0.25 * (1 - bite)
    return flat(np.clip(alpha + glow * (1 - alpha), 0, 1))


def star5():
    """A white five-point star (straight edges, crisp points) with a soft glow round it, 256 px."""
    n = 256
    cv = Canvas(n)
    star_alpha(cv, (0.5, 0.49), 0.36, 5, 0.42)
    body = cv.alpha()
    soft = np.asarray(Image.fromarray((body * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(14)), np.float32) / 255.0
    alpha = np.clip(body + 0.7 * soft * (1 - body), 0, 1)
    return flat(alpha)


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
    'witch_broom/witch_fly_8x8': witch_fly, 'witch_broom/star5': star5,
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
