"""Cue skin painters: write a skin's five paint-kit panels (and their companion maps).

    python3 assets/cue/CuePaint.py <id> [<id> ...]      run the skin's painter (skins/<id>.json "paint")
    python3 assets/cue/CuePaint.py --list                list the procedural recipes

Runs on the Mac's own Python 3 (numpy + Pillow), not in Blender. Writes into assets/cue/skins/<id>/:
    <panel>.png            the colour (shaft_tile, shaft_top, forearm, butt, cap_end)
    <panel>_height.png     16-bit relief: (value / 65535 - 0.5) * HEIGHT_RANGE_STUDS
    <panel>_rough.png      roughness 0..1
    <panel>_metal.png      metalness 0..1
    <panel>_glow.png       emissive mask 0..1 (SurfaceAppearance's emissive mask)
CueTextures.py maps every one of them onto the atlas, so a skin is its panels plus a skin file.

Every panel is painted in real cue coordinates: each panel pixel knows its distance from the tip
(d, studs), its angle round the cue (theta, 0 at the seam underneath, pi on top), its radius and
its 3D point, exactly as CueTextures.panel_lookup reads it back. Procedural skins use the shaft
tile once along the whole shaft ("repeats": 1), so the shaft is painted in one piece with no
visible repeat.

Painters:
  "procedural"  a recipe function below (RECIPES), numpy only
  "openai"      panels painted by tools/openai_image.py from the template and the concept crops
                (skins/<id>.json "ai"), then checked and fixed (size, seams, palette); a recipe
                may still paint the rest ("mix")
"""

import json
import math
import os
import subprocess
import sys

sys.dont_write_bytecode = True

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

SKINS = os.path.join(HERE, 'skins')
CONCEPTS = os.path.join(HERE, 'concepts')
TEMPLATE = os.path.join(HERE, 'template')
PANELS = ['shaft_tile', 'shaft_top', 'forearm', 'butt', 'cap_end']
HEIGHT_RANGE_STUDS = 0.002  # a 16-bit height map spans +-0.001 studs (half a percent of the butt)

# Zone boundaries along the cue (studs from the tip), from Shape.json.
ZONES = {'tip': (0.0, 0.105), 'ferrule': (0.105, 0.245), 'shaft': (0.245, 3.605),
         'joint': (3.605, 3.78), 'forearm': (3.78, 5.32), 'ring': (5.32, 5.425),
         'wrap': (5.425, 6.615), 'cap': (6.615, 7.0)}


# ---------------------------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------------------------

def rgb(value):
    if isinstance(value, str):
        return np.array(cc.hex_rgb(value), np.float64)
    return np.array(value, np.float64)


def mix(a, b, t):
    t = np.asarray(t, np.float64)
    if t.ndim and np.asarray(a).ndim > t.ndim:
        t = t[..., None]
    return a * (1 - t) + b * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def to_lin(c):
    c = np.asarray(c, np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


# ---------------------------------------------------------------------------------------------
# Panel geometry: every panel pixel's place on the cue
# ---------------------------------------------------------------------------------------------

class Params:
    def __init__(self):
        self.p = cc.read_parameters()
        self.panels = {q['name']: q for q in self.p['panels']}
        prof = self.p['profile']
        self.ps = np.array([q['s'] for q in prof])
        self.pd = np.array([q['d'] for q in prof])
        self.pr = np.array([q['r'] for q in prof])

    def d_of_s(self, s):
        return np.interp(s, self.ps, self.pd)

    def r_of_s(self, s):
        return np.interp(s, self.ps, self.pr)


class Canvas:
    """One panel: colour (0..255), height (studs), roughness, metalness and glow per pixel, plus
    each pixel's cue coordinates."""

    def __init__(self, P, name, shaft_repeats=1):
        q = P.panels[name]
        self.name = name
        w, h = q['size_px']
        self.w, self.h = w, h
        u = (np.arange(w) + 0.5) / w
        v = (np.arange(h) + 0.5) / h
        self.U, self.V = np.meshgrid(u, v)
        if name == 'cap_end':
            k = q['disc_radius_px'] / q['face_radius_studs']
            px = (self.U * w - w / 2) / k  # studs, +x right
            pz = (h / 2 - self.V * h) / k  # studs, +z up (the top of the cue)
            self.x, self.z = px, pz
            self.r = np.hypot(px, pz)
            self.theta = np.mod(np.arctan2(px, -pz), 2 * math.pi)
            self.d = np.full_like(px, 7.0)
            self.s = np.full_like(px, q['s_from'])
            self.inside = self.r <= q['face_radius_studs'] + 2 / k
            self.face_radius = q['face_radius_studs']
        else:
            if name == 'shaft_tile':
                grid = np.linspace(q['s_from'], q['s_to'], 4001)
                rate = 1.0 / ((w / h) * 2 * math.pi * P.r_of_s(grid))
                F = np.concatenate([[0.0], np.cumsum((rate[1:] + rate[:-1]) / 2 * np.diff(grid))])
                F = F / F[-1] * shaft_repeats
                # one repeat of the tile covers F in [0, 1]; paint the first repeat
                s_of_u = np.interp(u, F, grid)
            else:
                s_of_u = q['s_from'] + u * (q['s_to'] - q['s_from'])
            S = np.broadcast_to(s_of_u[None, :], (h, w))
            self.s = S.copy()
            self.d = P.d_of_s(self.s)
            self.r = P.r_of_s(self.s)
            self.theta = 2 * math.pi * self.V
            self.x = self.r * np.sin(self.theta)
            self.z = -self.r * np.cos(self.theta)
            self.inside = np.ones((h, w), bool)
        # arc length round the cue from the seam (studs), and the top-facing angle (0 on top)
        self.around = self.theta * self.r
        self.top = self.theta - math.pi
        self.col = np.zeros((h, w, 3))
        self.height = np.zeros((h, w))
        self.rough = np.full((h, w), 0.35)
        self.metal = np.zeros((h, w))
        self.glow = np.zeros((h, w))
        self.used = {'height': False, 'rough': False, 'metal': False, 'glow': False}

    def zone(self, *names):
        m = np.zeros((self.h, self.w), bool)
        if self.name == 'cap_end':
            return np.ones_like(m) if 'end' in names or 'cap' in names else m
        for n in names:
            a, b = ZONES[n]
            m |= (self.d >= a - 1e-9) & (self.d < b + (1e-6 if n == 'cap' else 0))
        return m

    def span(self, a, b):
        return (self.d >= a) & (self.d < b)

    # --- writing -----------------------------------------------------------------------------
    def put(self, mask, col=None, rough=None, metal=None, height=None, glow=None):
        m = mask.astype(np.float64) if mask.dtype == bool else np.clip(mask, 0, 1)
        if col is not None:
            c = np.asarray(col, np.float64)
            if c.ndim == 1:
                c = np.broadcast_to(c, (self.h, self.w, 3))
            self.col = mix(self.col, c, m)
        for key, value in (('rough', rough), ('metal', metal), ('height', height), ('glow', glow)):
            if value is None:
                continue
            arr = getattr(self, key)
            val = np.broadcast_to(np.asarray(value, np.float64), (self.h, self.w))
            setattr(self, key, arr * (1 - m) + val * m)
            self.used[key] = True

    def add_height(self, mask, h):
        m = mask.astype(np.float64) if mask.dtype == bool else mask
        self.height = self.height + h * m
        self.used['height'] = True


# ---------------------------------------------------------------------------------------------
# Noise in cue space (seamless round the cue because it is sampled on the 3D point)
# ---------------------------------------------------------------------------------------------

def fbm(c, fx, fd, fz=None, octaves=4, seed=0, warp=None):
    """fbm on the cue's 3D point, scaled per axis (cycles per stud): fx across (x and z), fd along."""
    fz = fx if fz is None else fz
    X, D, Z = c.x * fx, c.d * fd, c.z * fz
    if warp is not None:
        X, D, Z = X + warp[0], D + warp[1], Z + warp[2]
    return cc.fbm(X, D, Z, octaves, seed)


def noise(c, fx, fd, seed=0):
    return cc.noise3(c.x * fx, c.d * fd, c.z * fx, seed)


# ---------------------------------------------------------------------------------------------
# Materials (each paints colour, roughness, metalness and relief inside a mask)
# ---------------------------------------------------------------------------------------------

def metal(c, m, color, rough=0.16, brushed=True, seed=11):
    """Polished or brushed metal (the joint collar, rings, butt caps)."""
    base = rgb(color)
    if brushed:
        b = fbm(c, 20, 3000, octaves=2, seed=seed)
    else:
        b = fbm(c, 60, 60, octaves=2, seed=seed)
    c.put(m, base * (0.95 + 0.08 * b)[..., None], rough=rough + 0.05 * b, metal=1.0)


def gloss(c, m, color, rough=0.1, flake=0.0, flake_color=None, seed=19, clear=0.03):
    """Glossy paint or lacquer; flake > 0 adds a fine metallic sparkle."""
    base = rgb(color)
    v = fbm(c, 80, 80, octaves=2, seed=seed)
    col = base * (1 - clear + 2 * clear * v)[..., None]
    rough_v = np.full(m.shape, rough, np.float64)
    if flake > 0:
        f = np.clip((cc.noise3(c.x * 2600, c.d * 2600, c.z * 2600, seed + 1) - 0.62) * 4, 0, 1)
        fc = rgb(flake_color) if flake_color is not None else base * 1.6 + 30
        col = mix(col, np.broadcast_to(fc, col.shape), f * flake)
        rough_v = rough_v - 0.04 * f
    c.put(m, col, rough=rough_v, metal=0.0)


def matte(c, m, color, rough=0.55, grain=0.05, seed=23):
    base = rgb(color)
    v = fbm(c, 400, 400, octaves=2, seed=seed)
    c.put(m, base * (1 - grain + 2 * grain * v)[..., None], rough=rough + 0.05 * v, metal=0.0)
    c.add_height(m, 0.00001 * v)


def leather(c, m, color, rough=0.62, depth=0.00016, scale=1.0, seed=29, sheen=0.0):
    """Pebbled leather: cells of soft bumps with fine creases between them."""
    f = 170 / scale
    a = cc.noise3(c.x * f, c.d * f, c.z * f, seed)
    b = cc.noise3(c.x * f * 2.1, c.d * f * 2.1, c.z * f * 2.1, seed + 1)
    cell = np.abs(a - 0.5) * 2
    crease = np.clip(1 - np.abs(a - 0.5) / 0.08, 0, 1) * 0.6 + np.clip(1 - np.abs(b - 0.5) / 0.06, 0, 1) * 0.4
    h = depth * (0.6 * cell + 0.4 * b - 0.8 * crease)
    base = rgb(color)
    tone = 0.92 + 0.12 * cell - 0.14 * crease
    col = base * tone[..., None] + sheen * 30 * cell[..., None]
    c.put(m, col, rough=rough + 0.1 * crease - 0.06 * cell, metal=0.0)
    c.add_height(m, h - h[m].mean() if m.any() else h)


def linen(c, m, color, rough=0.78, fleck=None, fleck_amount=0.0, seed=31):
    """Irish linen: threads wound round the cue (the Classic wrap), optionally flecked."""
    pitch = 0.011
    phase = c.d / pitch + c.theta / (2 * math.pi)
    ridge = (0.5 - 0.5 * np.cos(2 * math.pi * phase)) ** 0.6
    slub = cc.fbm(c.x * 90, c.d * 25, c.z * 90, 3, seed)
    fibre = cc.fbm(c.x * 1200, c.d * 300, c.z * 1200, 2, seed + 1)
    base = rgb(color)
    col = base * (0.75 + 0.35 * ridge + 0.15 * fibre)[..., None]
    if fleck is not None and fleck_amount > 0:
        f = np.clip((cc.noise3(c.x * 700, c.d * 180, c.z * 700, seed + 2) - (1 - fleck_amount)) * 6, 0, 1)
        col = mix(col, np.broadcast_to(rgb(fleck) * (0.85 + 0.3 * ridge)[..., None], col.shape), f)
    c.put(m, col, rough=rough, metal=0.0)
    c.add_height(m, 0.0004 * ridge * (0.7 + 0.6 * slub))


def sport_grip(c, m, color, rough=0.7, seed=37, pitch=0.035):
    """A rubbery sport grip: a fine diamond knurl pressed into the surface."""
    around = c.theta / (2 * math.pi) * 18
    along = c.d / pitch
    k = np.abs(np.mod(around + along, 1) - 0.5) + np.abs(np.mod(around - along, 1) - 0.5)
    h = np.clip(1 - k, 0, 1)
    base = rgb(color)
    v = fbm(c, 300, 300, octaves=2, seed=seed)
    c.put(m, base * (0.85 + 0.2 * h + 0.06 * v)[..., None], rough=rough - 0.08 * h, metal=0.0)
    c.add_height(m, 0.00035 * (h - 0.5))


def carbon(c, m, dark='#1E1E1E', light='#3A3A3A', rough=0.12, tow=0.018, seed=41, tint=None):
    """2x2 twill carbon weave under a clear coat: tows at +-45 degrees on the surface."""
    a = c.d / tow
    b = c.around_top / tow if hasattr(c, 'around_top') else c.theta * c.r / tow
    # a twill in (along, around): tows alternate over two, under two
    p = np.floor(a + b)
    q = np.floor(a - b)
    fa = np.mod(a + b, 1)
    fb = np.mod(a - b, 1)
    over = np.mod(p + np.floor(q / 2), 2) < 1  # which direction is on top here
    f = np.where(over, fa, fb)
    sheen = np.sin(math.pi * f) ** 0.8  # each tow is a rounded bundle
    fibres = cc.noise3(c.x * 3000, c.d * 3000, c.z * 3000, seed)
    lo, hi = rgb(dark), rgb(light)
    t = np.where(over, 0.25 + 0.75 * sheen, 0.1 + 0.55 * sheen) * (0.9 + 0.2 * fibres)
    col = mix(np.broadcast_to(lo, c.col.shape), np.broadcast_to(hi, c.col.shape), np.clip(t, 0, 1))
    if tint is not None:
        col = col * rgb(tint) / 255.0 * 1.8
    c.put(m, col, rough=rough, metal=0.15)
    c.add_height(m, 0.00006 * (sheen - 0.5))


def wood(c, m, kind, light, dark, rough=0.3, seed=51, stain=None, figure=1.0):
    """Wood: 'maple' (fine straight grain), 'rosewood' (dark wavy), 'ebony' (black, tight),
    'curly' (tiger-stripe figure), 'birdseye' (maple with tiny eyes)."""
    L, Dk = rgb(light), rgb(dark)
    warp = fbm(c, 4, 2.0, octaves=2, seed=seed)
    if kind in ('maple', 'curly', 'birdseye'):
        g = fbm(c, 140, 2.2, octaves=4, seed=seed + 1, warp=(warp * 3, 0, warp * 3))
        lines = np.clip(1 - np.abs(np.mod(g * 14, 1.0) - 0.5) * 2 / 0.18, 0, 1)
        shade = 0.93 + 0.1 * g - 0.09 * lines
        col = L * shade[..., None]
        if kind == 'curly':
            # tiger stripes: bands across the grain that ripple round the cue
            ph = c.d * 38 + 0.8 * np.sin(c.theta * 3 + c.d * 5) + 2.0 * fbm(c, 8, 3, octaves=2, seed=seed + 2)
            stripe = (0.5 + 0.5 * np.sin(2 * math.pi * ph)) ** 3
            col = mix(col, col * 0.62, stripe * 0.9 * figure)
        if kind == 'birdseye':
            e = cc.noise3(c.x * 520, c.d * 520, c.z * 520, seed + 3)
            eyes = np.clip((e - 0.8) * 9, 0, 1)
            col = mix(col, col * 0.55, eyes * figure)
        col = mix(col, np.broadcast_to(Dk, col.shape), lines * 0.25)
        height = -0.00002 * lines
    else:
        freq = 55 if kind == 'rosewood' else 90
        g = fbm(c, freq, 1.6, octaves=4, seed=seed + 1, warp=(warp * 5, 0, warp * 5))
        lines = np.clip(1 - np.abs(np.mod(g * 11, 1.0) - 0.5) * 2 / 0.28, 0, 1)
        pores = np.clip((cc.noise3(c.x * 1500, c.d * 220, c.z * 1500, seed + 2) - 0.62) * 3, 0, 1)
        k = np.clip(0.55 + 0.9 * (g - 0.5), 0, 1)
        col = mix(np.broadcast_to(Dk, c.col.shape), np.broadcast_to(L, c.col.shape), k)
        col = mix(col, np.broadcast_to(Dk * 0.6, col.shape), lines * 0.55)
        col = col * (1 - 0.25 * pores)[..., None]
        height = -0.000025 * lines - 0.00002 * pores
    if stain is not None:
        # a dye soaked into the wood: the figure stays, the colour becomes the stain
        lum = col.mean(axis=-1, keepdims=True) / max(L.mean(), 1)
        col = rgb(stain) * np.clip(lum, 0.2, 1.6)
    c.put(m, col, rough=rough, metal=0.0)
    c.add_height(m, height)


def pearl(c, m, color='#EDE8E0', rough=0.2, seed=61, fire=0.35):
    """Mother-of-pearl: soft iridescent patches."""
    base = rgb(color)
    a = fbm(c, 90, 90, octaves=3, seed=seed)
    b = fbm(c, 200, 200, octaves=2, seed=seed + 1)
    tints = np.stack([np.sin(a * 9) * 0.5 + 0.5, np.sin(a * 9 + 2.1) * 0.5 + 0.5, np.sin(a * 9 + 4.2) * 0.5 + 0.5], -1)
    col = base * (0.88 + 0.16 * b)[..., None] * (1 - fire * 0.25) + tints * 255 * fire * 0.25
    c.put(m, col, rough=rough, metal=0.0)


# ---------------------------------------------------------------------------------------------
# Shapes on the cue
# ---------------------------------------------------------------------------------------------

def angle_diff(a, b):
    return np.abs(np.mod(a - b + math.pi, 2 * math.pi) - math.pi)


def points(c, n, d_base, d_tip, width_base, phase=0.0, curve=1.0, soft_px=1.2):
    """n pointed inlays round the cue (a classic cue's points): each is widest (width_base, as a
    fraction of 360/n degrees) at d_base and comes to a sharp point at d_tip. Returns a 0..1
    coverage map and, per pixel, the distance inside the edge in radians (for veneers)."""
    span = 2 * math.pi / n
    if d_tip < d_base:
        t = np.clip((c.d - d_tip) / (d_base - d_tip), 0, 1)
        inside_d = (c.d >= d_tip) & (c.d <= d_base)
    else:
        t = np.clip((d_tip - c.d) / (d_tip - d_base), 0, 1)
        inside_d = (c.d >= d_base) & (c.d <= d_tip)
    half = width_base * span / 2 * t ** curve
    centres = phase + span * np.arange(n)
    best = np.full(c.d.shape, 1e9)
    for a in centres:
        best = np.minimum(best, angle_diff(c.theta, a))
    edge = half - best  # >0 inside, radians
    px = 2 * math.pi / c.h  # one panel pixel in radians
    cov = np.clip(edge / (soft_px * px) + 0.5, 0, 1) * inside_d
    return cov, np.where(inside_d, edge, -1)


def band(c, d0, d1, soft=0.0015):
    """A ring round the cue from d0 to d1 (studs)."""
    return smooth(d0 - soft, d0 + soft, c.d) * (1 - smooth(d1 - soft, d1 + soft, c.d))


def stripe_along(c, centre, half_width, soft=None):
    """A stripe along the cue, centred at an angle (radians, pi = the top), half_width in studs."""
    dist = angle_diff(c.theta, centre) * c.r
    soft = soft if soft is not None else 1.5 * (2 * math.pi * c.r / c.h)
    return 1 - smooth(half_width - soft, half_width + soft, dist)


def spiral(c, turns_per_stud, n=2, duty=0.5, phase=0.0, soft=0.02):
    """n helical stripes (candy cane). Returns 0..1 coverage."""
    ph = n * (c.theta / (2 * math.pi) + c.d * turns_per_stud) + phase
    f = np.mod(ph, 1.0)
    return smooth(0.0, soft, f) * (1 - smooth(duty - soft, duty, f))


def diamond(c, d_centre, theta_centre, half_len, half_wid, soft_px=1.0):
    """A diamond inlay: |along|/half_len + |around|/half_wid <= 1 (studs)."""
    along = np.abs(c.d - d_centre)
    around = angle_diff(c.theta, theta_centre) * c.r
    k = along / half_len + around / half_wid
    px = 2 * math.pi * c.r / c.h
    return np.clip((1 - k) * min(half_len, half_wid) / (soft_px * px) + 0.5, 0, 1)


def hex_cells(c, n_around, stretch=1.0, phase=0.0):
    """A regular hexagon grid wrapped round the cue, n_around cells across the circumference (so
    it joins at the seam). Returns (edge, cid, cx, cy): the distance to the cell's edge in cell
    widths (0 on a wall, 0.5 at the centre), a per-cell hash 0..1, and the offset from the cell
    centre (cell widths, x round, y along)."""
    x = c.theta / (2 * math.pi) * n_around + phase
    rmean = float(np.mean(c.r))
    y = c.d / (2 * math.pi * rmean / n_around) / stretch
    s3 = math.sqrt(3.0)
    best = None
    for ox, oy in ((0.0, 0.0), (0.5, s3 / 2)):
        gx = np.round(x - ox)
        gy = np.round((y - oy) / s3)
        cx0, cy0 = gx + ox, gy * s3 + oy
        dx, dy = x - cx0, y - cy0
        dist = dx * dx + dy * dy
        if best is None:
            best = [dist, dx, dy, gx, gy, ox]
        else:
            take = dist < best[0]
            for i, v in enumerate([dist, dx, dy, gx, gy, ox]):
                best[i] = np.where(take, v, best[i])
    _, dx, dy, gx, gy, ox = best
    far = np.zeros_like(dx)
    for a in (0.0, math.pi / 3, 2 * math.pi / 3):
        far = np.maximum(far, np.abs(dx * math.cos(a) + dy * math.sin(a)))
    edge = 0.5 - far
    gxm = np.mod(gx, n_around)
    cid = cc._hash3(gxm.astype(np.int64), gy.astype(np.int64), (ox * 2).astype(np.int64), 97)
    return edge, cid, dx, dy


def drips(c, top_width, count, max_len, seed=5, width=0.012, centre=math.pi):
    """Honey (or goo) running down both sides from a band along the top of the cue: a coverage
    map. top_width: the band's half width round the cue (studs); count drips per stud each side;
    max_len: the longest drip (studs round the cue)."""
    along = c.d
    around = angle_diff(c.theta, centre) * c.r  # studs from the top line
    band_edge = top_width * (1 + 0.25 * (fbm(c, 0.01, 9, octaves=2, seed=seed) - 0.5))
    cov = 1 - smooth(band_edge - 0.002, band_edge + 0.002, around)
    rs = np.random.RandomState(seed)
    d0, d1 = float(along.min()), float(along.max())
    n = max(1, int((d1 - d0) * count))
    for side in (-1, 1):
        for _ in range(n):
            at = rs.uniform(d0, d1)
            ln = rs.uniform(0.25, 1.0) * max_len
            w = width * rs.uniform(0.7, 1.3)
            # which side of the top line this pixel is on
            sgn = np.sign(np.mod(c.theta - centre + math.pi, 2 * math.pi) - math.pi)
            on_side = (sgn == side) | (sgn == 0)
            u = (around - band_edge) / ln  # 0 at the band, 1 at the drip's end
            taper = np.where(u < 0.75, 1 - 0.35 * u, 0.74 + 0.9 * (u - 0.75))  # thins, then a bulb
            dist = np.abs(along - at)
            body = (dist < w * taper) & (u >= -0.2) & (u <= 1.0) & on_side
            bulb = ((along - at) ** 2 + (around - (band_edge + ln)) ** 2) < (w * 1.35) ** 2
            cov = np.maximum(cov, (body | (bulb & on_side)).astype(np.float64))
    return cov


# ---------------------------------------------------------------------------------------------
# The kit: all five canvases and the plain-colour parts
# ---------------------------------------------------------------------------------------------

class Kit:
    def __init__(self, skin):
        self.P = Params()
        self.skin = skin
        reps = (skin.get('shaft_tile') or {}).get('repeats') or 1
        self.c = {name: Canvas(self.P, name, reps) for name in PANELS}

    def each(self):
        return list(self.c.values())

    def zone(self, *names):
        """[(canvas, mask)] for every canvas that has any of these zones."""
        out = []
        for c in self.each():
            m = c.zone(*names)
            if m.any():
                out.append((c, m))
        return out

    def paint(self, zones, fn, *args, **kw):
        for c, m in self.zone(*zones):
            fn(c, m, *args, **kw)

    def write(self, skin_id):
        out = os.path.join(SKINS, skin_id)
        os.makedirs(out, exist_ok=True)
        from PIL import Image
        for name, c in self.c.items():
            col = np.clip(np.round(c.col), 0, 255).astype(np.uint8)
            Image.fromarray(col).save(os.path.join(out, name + '.png'), optimize=True)
            companions = {'height': c.height, 'rough': c.rough, 'metal': c.metal, 'glow': c.glow}
            for key, arr in companions.items():
                path = os.path.join(out, '%s_%s.png' % (name, key))
                if key == 'height':
                    v = np.clip(arr / HEIGHT_RANGE_STUDS + 0.5, 0, 1) * 65535
                    Image.fromarray(np.round(v).astype(np.uint16)).save(path, optimize=True)
                else:
                    if key == 'glow' and not c.glow.any():
                        if os.path.isfile(path):
                            os.remove(path)
                        continue
                    v = np.clip(arr, 0, 1) * 255
                    Image.fromarray(np.round(v).astype(np.uint8)).save(path, optimize=True)
        print('CUE paint wrote', os.path.relpath(out, ROOT))


# ---------------------------------------------------------------------------------------------
# Shared parts every real cue has
# ---------------------------------------------------------------------------------------------

def standard_hardware(k, joint='#C8CCD0', ring='#C8CCD0', joint_rough=0.16, ring_rough=0.16,
                      end='#141414', seams=True):
    """The joint collar and the ring in metal, and the end face as rubber; a hairline seam at
    the joint's middle (where the shaft screws on)."""
    k.paint(['joint'], metal, joint, rough=joint_rough)
    k.paint(['ring'], metal, ring, rough=ring_rough)
    c = k.c['cap_end']
    rubber(c, c.inside | True, end)
    if seams:
        f = k.c['forearm']
        mid = (ZONES['joint'][0] + ZONES['joint'][1]) / 2
        line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
        f.put(line > 0.01, f.col * 0.35, rough=0.4)
        f.add_height(line, -0.0003)


def rubber(c, m, color, seed=21):
    grain = fbm(c, 1500, 1500, octaves=2, seed=seed)
    col = rgb(color) * (0.92 + 0.16 * grain)[..., None]
    c.put(m, col, rough=0.86, metal=0.0)
    if c.name == 'cap_end':
        rr = c.r / c.face_radius
        ring = sum(np.exp(-((rr - q) / 0.018) ** 2) for q in (0.55, 0.62))
        c.add_height(m, 0.00002 * grain - 0.00012 * ring)


def cap_face_metal(c, color, rough=0.2, rim_color=None):
    """A metal disc on the end face (a butt cap you can see from behind)."""
    rr = c.r / c.face_radius
    disc = rr < 0.72
    metal(c, disc, color, rough=rough, brushed=False)
    rings = np.exp(-((rr - 0.72) / 0.02) ** 2)
    c.add_height(rings > 0.05, -0.0002 * rings)


def seam_edges(k, at_d, depth=0.00025, width=0.0018):
    """Hairline grooves where two materials meet (a cue's inlays are separate pieces)."""
    for c in k.each():
        for d in at_d:
            g = band(c, d - width, d + width, soft=width * 0.6)
            if g.any():
                c.add_height(g, -depth * g)


# ---------------------------------------------------------------------------------------------
# Procedural recipes (one per procedural skin)
# ---------------------------------------------------------------------------------------------

RECIPES = {}


def recipe(fn):
    RECIPES[fn.__name__] = fn
    return fn


J0, J1 = ZONES['joint']
F0, F1 = ZONES['forearm']
W0, W1 = ZONES['wrap']
C0, C1 = ZONES['cap']


@recipe
def midnight(k):
    """Metallic gloss black; one silver-grey stripe along the top of the forearm, tapering to a
    point toward the joint, with chrome pinstripe edges (the concept's close-up); chrome collar,
    ring and butt-cap band; pebbled black leather wrap; the shaft the same gloss black."""
    s = k.skin['colours']
    black, grey, chrome = s['body'], s['stripe'], s['metal']
    k.paint(['shaft'], gloss, black, rough=0.1, flake=0.35, flake_color='#3A3D44')
    k.paint(['forearm', 'cap'], gloss, black, rough=0.07, flake=0.5, flake_color='#4A4E57')
    for c, m in k.zone('forearm'):
        # the stripe is widest at the ring and comes to a point 0.35 studs after the collar
        t = np.clip((c.d - (F0 + 0.35)) / (F1 - F0 - 0.35), 0, 1)
        width = 0.034 * t ** 0.7
        st = stripe_along(c, math.pi, width) * m * (c.d > F0 + 0.35)
        brushed = fbm(c, 20, 1500, octaves=2, seed=71)
        c.put(st, rgb(grey) * (0.96 + 0.08 * brushed)[..., None], rough=0.38, metal=0.0)
        edge = np.clip(stripe_along(c, math.pi, width + 0.004) - st, 0, 1) * m * (c.d > F0 + 0.3)
        metal(c, edge > 0.5, chrome, rough=0.1, brushed=False)
        c.add_height(edge, -0.00015)
    k.paint(['wrap'], leather, s['wrap'], rough=0.66, depth=0.0009, scale=2.6)
    standard_hardware(k, joint=chrome, ring=chrome, joint_rough=0.08, ring_rough=0.08)
    # the butt cap: a chrome band at the very end of the sleeve, before the bumper
    for c, m in k.zone('cap'):
        cap = band(c, 6.9, 7.1) * m
        metal(c, cap > 0.5, chrome, rough=0.08, brushed=True)
    seam_edges(k, [F1, 6.9])
    cap_face_metal(k.c['cap_end'], chrome, rough=0.14)


@recipe
def honeycomb(k):
    """Warm amber: a glossy honeycomb of dark amber-brown cells outlined in glowing gold on the
    forearm and the sleeve, thick orange honey pooling along the top of the forearm and running
    down between the cells, a chocolate-brown grip wound with amber bee stripes, gold rings,
    silver collar, and a deep amber shaft with glowing honey veins toward the joint."""
    s = k.skin['colours']
    amber, wall, honey, dark, gold = rgb(s['amber']), rgb(s['wall']), rgb(s['honey']), rgb(s['dark']), s['gold']
    # shaft: deep amber over a curly figure, glossy; honey veins glow near the joint
    for c, m in k.zone('shaft'):
        wood(c, m, 'curly', '#E0902A', '#7A3A08', rough=0.14, seed=81, figure=0.5)
        deep = smooth(0.3, 3.6, c.d)
        c.put(m * (0.45 + 0.45 * deep), np.broadcast_to(np.array([214.0, 118, 18]), c.col.shape))
        warp = fbm(c, 6, 1.2, octaves=3, seed=88)
        vein = np.abs(np.mod(warp * 5 + c.theta / math.pi, 1.0) - 0.5)
        vein = (1 - smooth(0.0, 0.05, vein)) * smooth(0.9, 3.0, c.d) * m
        vcol = np.broadcast_to(np.array([255.0, 190, 60]), c.col.shape)
        c.put(vein * 0.95, vcol, glow=vein)
    # the honeycomb (forearm and sleeve): dark glossy cells, glowing gold walls
    for c, m in k.zone('forearm', 'cap'):
        edge, cid, dx, dy = hex_cells(c, 7)
        wall_w = 0.07
        inside = smooth(wall_w - 0.018, wall_w + 0.018, edge)
        centre = np.clip(edge / 0.5, 0, 1)
        cellc = mix(np.broadcast_to(np.array([96.0, 44, 10]), c.col.shape), np.broadcast_to(np.array([190.0, 98, 26]), c.col.shape), (centre ** 0.9) * (0.55 + 0.45 * cid))
        wallc = np.broadcast_to(np.array([246.0, 158, 30]), c.col.shape)
        c.put(m, mix(wallc, cellc, inside), rough=0.1 + 0.08 * (1 - inside), metal=0.0)
        # glowing walls stand proud; each cell a shallow glossy dome
        c.add_height(m, 0.00045 * (1 - inside) + 0.0002 * inside * (centre ** 2))
        rim = smooth(wall_w + 0.1, wall_w, edge) * inside  # a warm rim of light inside each wall
        c.put(m, None, glow=np.clip((1 - inside) * 0.65 + rim * 0.25, 0, 1))
        c.col = c.col + (rim * m)[..., None] * (amber - c.col) * 0.5
    # honey running down from the top of the forearm, starting just after the collar
    for c, m in k.zone('forearm'):
        runs = drips(c, 0.016, 2.6, 0.2, seed=85, width=0.022) * m * smooth(F0 + 0.02, F0 + 0.08, c.d)
        runs = runs * (1 - smooth(F1 - 0.08, F1 - 0.02, c.d))
        shade = fbm(c, 60, 40, octaves=2, seed=86)
        hcol = mix(np.broadcast_to(np.array([250.0, 170, 40]), c.col.shape), np.broadcast_to(np.array([214.0, 104, 12]), c.col.shape), 0.35 + 0.4 * shade)
        # a glossy highlight line down the middle of each run
        c.put(runs, hcol, rough=0.04, metal=0.0, glow=0.45 * runs)
        c.add_height(runs, 0.0006 * runs)
    # the grip: chocolate brown pebbled, wound with three amber bee stripes
    for c, m in k.zone('wrap'):
        leather(c, m, s['dark'], rough=0.8, depth=0.0005, scale=2.2, seed=87)
        st = spiral(c, 0.85, n=3, duty=0.42, phase=0.1, soft=0.025) * m
        tex = fbm(c, 400, 400, octaves=2, seed=89)
        c.put(st, amber * (0.62 + 0.25 * tex)[..., None], rough=0.62)
    # hardware: silver collar; gold rings with dark lines; gold bands where the sleeve starts
    k.paint(['joint'], metal, s['metal'], rough=0.14)
    for c, m in k.zone('ring'):
        metal(c, m, gold, rough=0.16)
        for a0, a1 in ((5.345, 5.36), (5.385, 5.4)):
            line = band(c, a0, a1) * m
            c.put(line, dark * 0.5, rough=0.35, metal=0.0)
    for c, m in k.zone('cap'):
        for a0, a1 in ((6.615, 6.635), (6.645, 6.655)):
            b_ = band(c, a0, a1) * m
            metal(c, b_ > 0.5, gold, rough=0.16)
            c.put(b_ > 0.5, None, glow=0.0)
        endb = band(c, 6.975, 7.1) * m
        c.put(endb, dark * 0.4, rough=0.3, glow=0.0)
    c = k.c['cap_end']
    rubber(c, c.inside | True, s['bumper'])
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)
    seam_edges(k, [F1, 6.615, 6.655])


def luma(img):
    return (img[..., 0] * 0.2126 + img[..., 1] * 0.7152 + img[..., 2] * 0.0722) / 255.0


def glow_from(img, lo=0.15, hi=0.6, gamma=1.0):
    """An emissive mask from a painted panel: bright (lit) paint glows, dark paint does not."""
    mx = img.max(-1) / 255.0
    return smooth(lo, hi, mx) ** gamma


def height_from(img, amount, blur=1):
    """Relief from a painted panel's brightness (light = raised), softened by a small box blur."""
    L = luma(img)
    if blur:
        k = int(blur)
        acc = np.zeros_like(L)
        n = 0
        for dy in range(-k, k + 1):
            for dx in range(-k, k + 1):
                acc += np.roll(np.roll(L, dy, 0), dx, 1)
                n += 1
        L = acc / n
    return (L - L.mean()) * amount


@recipe
def void(k):
    """Matte black that swallows light. Shaft: black with faint violet star-dust wisps that thicken
    toward the joint. Forearm (OpenAI): the violet black-hole swirl. Butt (OpenAI): black
    snakeskin grip cracked with glowing violet; the sleeve a black hole ringed in violet. A
    glowing violet ring, a silver collar, a violet event-horizon ring on the end face."""
    s = k.skin['colours']
    black, violet, lilac = rgb(s['black']), rgb(s['violet']), rgb(s['lilac'])
    for c, m in k.zone('shaft'):
        gloss(c, m, s['black'], rough=0.3, flake=0.25, flake_color='#2A2238')
        warp = fbm(c, 5, 0.9, octaves=3, seed=91)
        wisp = np.abs(np.mod(warp * 4 + c.theta / (2 * math.pi) * 2, 1.0) - 0.5)
        wisp = (1 - smooth(0.0, 0.06, wisp)) * smooth(0.6, 3.4, c.d) * (0.35 + 0.65 * fbm(c, 30, 4, octaves=2, seed=92))
        stars = np.clip((cc.noise3(c.x * 1400, c.d * 1400, c.z * 1400, 93) - 0.86) * 12, 0, 1)
        wcol = mix(np.broadcast_to(violet, c.col.shape), np.broadcast_to(lilac, c.col.shape), wisp)
        c.put(m * np.clip(wisp * 1.2, 0, 1), wcol, glow=np.clip(wisp, 0, 1) * 0.8)
        c.put(m * stars, np.broadcast_to([235.0, 225, 255], c.col.shape), glow=stars * 0.7)
    # forearm: the painted swirl
    f = k.c['forearm']
    img = ai_panel(k, 'forearm')
    f.col = f.col * 0.8
    f.put(np.ones((f.h, f.w), bool), None, rough=0.3 - 0.15 * glow_from(img, 0.2, 0.7), metal=0.0,
          glow=glow_from(img, 0.16, 0.75, 1.3))
    f.add_height(np.ones((f.h, f.w)), height_from(img, 0.0002))
    metal(f, f.zone('joint'), s['metal'], rough=0.2)
    f.put(f.zone('joint'), None, glow=0.0)
    # butt: the painted grip and black-hole sleeve
    b = k.c['butt']
    img = ai_panel(k, 'butt')
    wrap = b.zone('wrap')
    b.put(np.ones((b.h, b.w), bool), None, rough=0.45, metal=0.0, glow=glow_from(img, 0.25, 0.8, 1.2))
    b.add_height(wrap, height_from(img, 0.0009, blur=1))
    b.put(wrap, None, rough=0.42 - 0.2 * glow_from(img, 0.3, 0.8))
    b.put(b.zone('cap'), None, rough=0.3)
    ring = b.zone('ring')
    metal(b, ring, '#9A9EA6', rough=0.2)
    b.put(ring, None, glow=0.0)
    for a0, a1 in ((5.345, 5.36), (5.385, 5.4)):
        line = band(b, a0, a1) * ring
        b.put(line, np.broadcast_to(lilac, b.col.shape), rough=0.3, metal=0.0, glow=line)
    for a0, a1 in ((6.615, 6.63),):
        line = band(b, a0, a1) * b.zone('cap')
        b.put(line, np.broadcast_to(lilac, b.col.shape), glow=line)
    endb = band(b, 6.985, 7.1) * b.zone('cap')
    b.put(endb, black, rough=0.5, glow=0.0)
    seam_edges(k, [F1, W0, W1])
    # the end face: black with a violet event-horizon ring
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#08080C')
    rr = c.r / c.face_radius
    ringm = np.exp(-((rr - 0.62) / 0.06) ** 2)
    c.put(ringm, np.broadcast_to(lilac, c.col.shape), glow=ringm)
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)


# ---------------------------------------------------------------------------------------------
# OpenAI panels
# ---------------------------------------------------------------------------------------------

PANEL_WORDS = {
    'shaft_tile': 'the shaft (the long thin front part), repeated along it',
    'shaft_top': 'the upper end of the shaft; its right edge meets the joint collar',
    'forearm': 'the forearm: the two thin strips at the far left are the metal joint collar, the rest is the forearm (between the joint collar and the ring)',
    'butt': 'the butt: the thin strip at the far left is the ring, then the wrap (the handle grip), then the butt sleeve, then a thin rounded end at the far right',
    'cap_end': 'the flat round end of the butt, seen from behind',
}


def ai_prompt(skin, panel, spec):
    w, h = Params().panels[panel]['size_px']
    palette = ' '.join(skin.get('palette', []))
    parts = []
    if panel == 'cap_end':
        parts.append('Image 1 is a layout template. Paint it as a round badge: the flat end of a pool cue butt, seen from behind, in the style of the cue in the other images. Paint only inside the circle; outside the circle stays plain %s.' % spec.get('outside', '#141414'))
    else:
        parts.append('Image 1 is a layout template. Paint it as a flat unrolled texture for a cylinder: %s of a pool cue, in the style of the cue in the other images.' % PANEL_WORDS[panel])
        parts.append('Keep the exact layout and zone lines of image 1 and the exact size, %d x %d pixels. The left edge is the tip end and the right edge is the butt end. The top and bottom edges join seamlessly (they meet underneath the cue); the middle row is the top of the cue.' % (w, h))
    if panel == 'shaft_tile':
        parts.append('It tiles seamlessly on all four edges.')
    parts.append(spec['prompt'])
    parts.append(spec.get('style', 'A flat texture map: no lighting, no shading, no highlights, no reflections, no shadows, no gloss streaks, no depth. Crisp clean shapes.'))
    if palette:
        parts.append('Use only these colours and their darker and lighter tones: %s.' % palette)
    parts.append('No text, no letters, no numbers, no logos, no symbols with words.')
    return '\n'.join(parts)


def run_ai(skin_id, skin, only=None, force=False):
    """Paint every panel listed under skin["ai"] with OpenAI; keep each raw result as
    skins/<id>/ai/<panel>_<n>.png and the chosen one (after fixes) as <panel>.png."""
    ai = skin.get('ai') or {}
    out = os.path.join(SKINS, skin_id)
    raw_dir = os.path.join(out, 'ai')
    os.makedirs(raw_dir, exist_ok=True)
    for panel, spec in ai.items():
        if panel.startswith('_') or (only and panel not in only):
            continue
        n = 1
        while os.path.isfile(os.path.join(raw_dir, '%s_%d.png' % (panel, n))):
            n += 1
        if n > 1 and not force:
            print('CUE paint ai', panel, 'kept (%d takes; --force for another)' % (n - 1))
            continue
        prompt = ai_prompt(skin, panel, spec)
        images = [os.path.join(TEMPLATE, panel + '_input.png')]
        for ref in spec.get('refs', []):
            images.append(os.path.join(CONCEPTS, 'cues', skin_id, ref + '.png') if '/' not in ref else os.path.join(HERE, ref))
        w, h = Params().panels[panel]['size_px']
        size = spec.get('size') or ('%dx%d' % (w, h) if panel != 'butt' else '1376x512')
        raw = os.path.join(raw_dir, '%s_%d.png' % (panel, n))
        pf = os.path.join(raw_dir, '%s_%d.txt' % (panel, n))
        with open(pf, 'w') as handle:
            handle.write(prompt)
        cmd = [sys.executable, os.path.join(ROOT, 'tools', 'openai_image.py'), '--prompt-file', pf,
               '--size', size, '--quality', spec.get('quality', 'high'), '--out', raw, '--tag', skin_id + ':' + panel]
        for im in images:
            cmd += ['--image', im]
        subprocess.run(cmd, check=True)


def fix_panel(img, panel, spec):
    """Size, seams and palette: the drift fixes. img: H x W x 3 float."""
    from PIL import Image
    w, h = Params().panels[panel]['size_px']
    if img.shape[1] != w or img.shape[0] != h:
        img = np.asarray(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((w, h), Image.LANCZOS), np.float64)
    lines = [q['x'] for q in Params().panels[panel].get('lines', [])]
    if lines and spec.get('snap_zones', True):
        img = snap_zones(img, [x * w for x in lines], spec.get('zone_window_px', 110))
    seam = spec.get('seam_blend_px', 0 if panel == 'cap_end' else 10)
    if seam and panel != 'cap_end':
        # pull the top and bottom rows to their average so the seam underneath joins
        target = (img[0] + img[-1]) / 2
        for i in range(seam):
            t = (1 - i / seam) ** 2
            img[i] = img[i] * (1 - t) + target * t
            img[h - 1 - i] = img[h - 1 - i] * (1 - t) + target * t
    if panel == 'shaft_tile':
        sx = spec.get('seam_blend_x', 12)
        target = (img[:, 0] + img[:, -1]) / 2
        for i in range(sx):
            t = (1 - i / sx) ** 2
            img[:, i] = img[:, i] * (1 - t) + target * t
            img[:, w - 1 - i] = img[:, w - 1 - i] * (1 - t) + target * t
    snap = spec.get('palette_snap', 0)
    if snap and spec.get('palette'):
        pal = np.array([cc.hex_rgb(p) for p in spec['palette']], np.float64)
        flat = img.reshape(-1, 3)
        dist = ((flat[:, None, :] - pal[None]) ** 2).sum(-1)
        near = pal[np.argmin(dist, axis=1)].reshape(img.shape)
        img = img * (1 - snap) + near * snap
    return img


def snap_zones(img, expected, window):
    """OpenAI keeps the zone lines only roughly: find each painted boundary (the strongest
    column-to-column change within `window` px of where the template has it) and stretch every
    zone piecewise so its boundaries land exactly on the template's lines."""
    h, w = img.shape[:2]
    colmean = img.mean(0)
    jump = np.abs(np.diff(colmean, axis=0)).sum(1)
    found = []
    for x in expected:
        lo, hi = int(max(1, x - window)), int(min(w - 2, x + window))
        prev = int(found[-1]) + 4 if found else 1
        lo = max(lo, prev)
        i = lo + int(np.argmax(jump[lo:hi])) + 0.5
        found.append(i)
    src = np.array([0.0] + found + [float(w)])
    dst = np.array([0.0] + list(expected) + [float(w)])
    xs = np.interp(np.arange(w) + 0.5, dst, src) - 0.5
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    t = (xs - x0)[None, :, None]
    out = img[:, x0] * (1 - t) + img[:, x1] * t
    print('CUE paint zones', [round(f) for f in found], '->', [round(e) for e in expected])
    return out


def ai_panel(k, panel, mask=None, take=None):
    """Put the chosen OpenAI take of a panel (skins/<id>/ai/<panel>_<n>.png, fixed) into the kit's
    canvas, inside mask (default: everywhere). Returns the fixed image."""
    spec = dict((k.skin.get('ai') or {}).get(panel) or {})
    spec.setdefault('palette', k.skin.get('palette'))
    take = take or spec.get('take', 1)
    path = os.path.join(SKINS, k.skin['id'], 'ai', '%s_%d.png' % (panel, take))
    img = fix_panel(load_rgb(path), panel, spec)
    c = k.c[panel]
    c.put(np.ones((c.h, c.w), bool) if mask is None else mask, img)
    return img


def drift_report(img, panel):
    """A few numbers to judge a raw panel: size, seam mismatch, how grey (template left over)."""
    h, w = img.shape[:2]
    seam = float(np.abs(img[0] - img[-1]).mean())
    grey = float((np.abs(img - 128).max(-1) < 6).mean())
    return {'size': [w, h], 'seam_mean_abs': round(seam, 1), 'template_grey_share': round(grey, 3)}


def load_rgb(path):
    from PIL import Image
    return np.asarray(Image.open(path).convert('RGB'), np.float64)


def load_grey(path):
    from PIL import Image
    im = Image.open(path)
    a = np.asarray(im, np.float64)
    if a.ndim == 3:
        a = a[..., :3].mean(-1)
    return a / (65535.0 if im.mode.startswith('I') else 255.0)


# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

def load_skin(skin_id):
    with open(os.path.join(SKINS, skin_id + '.json')) as handle:
        return json.load(handle)


def paint(skin_id, ai_only=None, force_ai=False):
    skin = load_skin(skin_id)
    kind = skin.get('painter', 'procedural')
    if kind in ('openai', 'mix') and skin.get('ai'):
        run_ai(skin_id, skin, ai_only, force_ai)
    k = Kit(skin)
    name = skin.get('recipe', skin_id)
    if name in RECIPES:
        RECIPES[name](k)
    elif kind == 'procedural':
        sys.exit('CUE paint: no recipe %r' % name)
    k.write(skin_id)
    return k


def main():
    args = sys.argv[1:]
    if not args or '--list' in args:
        print('recipes:', ', '.join(sorted(RECIPES)))
        return
    force = '--force-ai' in args
    only = None
    if '--ai' in args:
        only = args[args.index('--ai') + 1].split(',')
    for skin_id in [a for a in args if not a.startswith('--') and (only is None or a != ','.join(only))]:
        paint(skin_id, only, force)


if __name__ == '__main__':
    main()
