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


def worley(c, freq, seed=0, jitter=0.9):
    """Cellular noise on the cue's 3D point: (F1, F2, cell id 0..1), distances in cell widths.
    F2 - F1 is 0 on the border between two cells (a crease), F1 is 0 at a cell's centre."""
    X, Y, Z = c.x * freq, c.d * freq, c.z * freq
    ix, iy, iz = np.floor(X).astype(np.int64), np.floor(Y).astype(np.int64), np.floor(Z).astype(np.int64)
    f1 = np.full(X.shape, 9.0)
    f2 = np.full(X.shape, 9.0)
    cid = np.zeros(X.shape)
    for dz in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                jx, jy, jz = ix + dx, iy + dy, iz + dz
                px = jx + 0.5 + jitter * (cc._hash3(jx, jy, jz, seed) - 0.5)
                py = jy + 0.5 + jitter * (cc._hash3(jx, jy, jz, seed + 1) - 0.5)
                pz = jz + 0.5 + jitter * (cc._hash3(jx, jy, jz, seed + 2) - 0.5)
                dist = np.sqrt((X - px) ** 2 + (Y - py) ** 2 + (Z - pz) ** 2)
                closer = dist < f1
                f2 = np.where(closer, f1, np.minimum(f2, dist))
                cid = np.where(closer, cc._hash3(jx, jy, jz, seed + 3), cid)
                f1 = np.where(closer, dist, f1)
    return f1, f2, cid


def leather(c, m, color, rough=0.62, depth=0.00016, scale=1.0, seed=29, sheen=0.0, contrast=1.0):
    """Pebbled leather: rounded pebbles of uneven size (cellular noise at two scales) parted by
    fine creases, a little tone change from pebble to pebble."""
    f = 170 / scale
    f1, f2, cid = worley(c, f, seed)
    g1, g2, _ = worley(c, f * 2.3, seed + 5)
    crease = np.clip(1 - (f2 - f1) / 0.16, 0, 1) ** 1.5
    fine = np.clip(1 - (g2 - g1) / 0.12, 0, 1) ** 2 * 0.45
    dome = np.clip(1 - f1 * 1.1, 0, 1) ** 0.5
    grain = cc.noise3(c.x * f * 6, c.d * f * 6, c.z * f * 6, seed + 9)
    creases = np.maximum(crease, fine)
    h = depth * (0.7 * dome - 0.9 * creases + 0.1 * grain)
    base = rgb(color)
    tone = 0.95 + contrast * (0.06 * (cid - 0.5) + 0.05 * dome - 0.16 * creases + 0.03 * (grain - 0.5))
    col = base * tone[..., None] + sheen * 30 * dome[..., None]
    c.put(m, col, rough=rough + 0.08 * creases - 0.06 * dome, metal=0.0)
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


def fleck_wrap(c, m, color, fleck, rough=0.7, seed=33, amount=0.22, size=1.0):
    """An off-white wrap with a soft grey mottle and irregular coloured flecks (Heritage's
    green-flecked wrap): fine pebble relief, flecks of uneven size scattered all over."""
    mott = fbm(c, 60, 60, octaves=3, seed=seed)
    f1, f2, _ = worley(c, 120, seed + 1)
    crease = np.clip(1 - (f2 - f1) / 0.14, 0, 1)
    base = rgb(color) * (0.86 + 0.2 * mott - 0.12 * crease)[..., None]
    g1, _, gid = worley(c, 55 / size, seed + 2, jitter=1.0)
    wob = fbm(c, 400 / size, 400 / size, octaves=2, seed=seed + 3)
    r = (0.12 + 0.2 * np.mod(gid * 7.3, 1)) * (0.7 + 0.6 * wob)
    fl = np.clip((r - g1) / 0.03, 0, 1) * (gid < amount)
    fcol = rgb(fleck) * (0.8 + 0.35 * np.mod(gid * 13.1, 1))[..., None]
    col = mix(base, fcol, fl)
    c.put(m, col, rough=rough - 0.1 * fl, metal=0.0)
    c.add_height(m, 0.0002 * (1 - crease) + 0.00008 * fl)


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


def carbon_weave(c, m, dark='#1E1E1E', light='#3A3A3A', rough=0.12, tow=0.018, seed=41, tint=None):
    """2x2 twill carbon weave under a clear coat: tows run along and round the cue, each over two
    and under two, stepping one per row, so the weave reads as diagonal stair-step stripes. The
    tows running along the cue catch the light (silver), the others stay black: carbon's
    anisotropic sheen."""
    n_round = max(4, int(round(float(np.mean(2 * math.pi * c.r)) / tow / 4)) * 4)
    a = c.d / tow
    b = c.theta / (2 * math.pi) * n_round  # a whole number of tows round the cue: no seam
    i, j = np.floor(a), np.floor(b)
    warp = np.mod(i + j, 4) < 2  # the along-the-cue tow is on top
    fa, fb = np.mod(a, 1), np.mod(b, 1)
    across = np.where(warp, fb, fa)
    along = np.where(warp, fa, fb)
    bundle = np.sin(math.pi * across) ** 0.6
    ends = np.clip(np.minimum(along, 1 - along) / 0.08, 0, 1)  # a tow dives under at its ends
    fibres = cc.noise3(c.x * 2500, c.d * 2500, c.z * 2500, seed)
    t = np.where(warp, 0.45 + 0.55 * bundle, 0.04 + 0.2 * bundle) * (0.55 + 0.45 * ends) * (0.9 + 0.2 * fibres)
    lo, hi = rgb(dark), rgb(light)
    col = mix(np.broadcast_to(lo, c.col.shape), np.broadcast_to(hi, c.col.shape), np.clip(t, 0, 1))
    if tint is not None:
        col = col * rgb(tint) / 255.0 * 1.8
    c.put(m, col, rough=np.where(warp, rough, rough + 0.08), metal=0.15)
    c.add_height(m, 0.00005 * (bundle * ends - 0.5))


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
            # curl: bands across the grain whose spacing, width and strength wander (the figure
            # of real curly maple is patchy and rippled, never a regular wave)
            ph = (c.d * 30 + 3.0 * fbm(c, 6, 3, octaves=2, seed=seed + 2)
                  + 0.7 * fbm(c, 40, 10, octaves=2, seed=seed + 9))
            stripe = (0.5 + 0.5 * np.sin(2 * math.pi * ph)) ** 2.2
            patch = np.clip(0.3 + 1.2 * (fbm(c, 5, 5, octaves=2, seed=seed + 10) - 0.35), 0.15, 1)
            broken = np.clip(0.6 + 0.8 * (fbm(c, 70, 4, octaves=2, seed=seed + 11) - 0.5), 0, 1)
            col = mix(col, col * 0.6, stripe * figure * patch * broken)
            col = col * (1 + 0.1 * (1 - stripe) * patch)[..., None]  # the chatoyant shimmer
        if kind == 'birdseye':
            # little round "eyes" (dark centres with a pale ring), scattered unevenly in drifts,
            # plus a soft flame across the grain: the look of honey birdseye maple
            wob = fbm(c, 500, 500, octaves=2, seed=seed + 6)
            f1, _, cid = worley(c, 95, seed + 3, jitter=1.0)
            f1 = f1 * (0.75 + 0.5 * wob)
            drift = fbm(c, 18, 9, octaves=2, seed=seed + 4)
            keep = (cid < 0.35 + 0.6 * drift) * figure
            radius = 0.18 + 0.2 * np.mod(cid * 5.7, 1)
            eye = np.clip(1 - f1 / radius, 0, 1) ** 0.7 * keep
            ring_ = np.clip(1 - np.abs(f1 - radius * 1.5) / (radius * 0.5), 0, 1) * keep
            flame = (0.5 + 0.5 * np.sin(2 * math.pi * (c.d * 16 + 2.5 * fbm(c, 10, 4, octaves=2, seed=seed + 5)))) ** 2
            col = col * (1 - 0.04 * flame * figure)[..., None]
            col = mix(col, mix(col, np.broadcast_to(Dk, col.shape), 0.75), eye * 0.8)
            col = col * (1 + 0.07 * ring_)[..., None]
            # the bigger mottle you see from arm's length: soft irregular darker patches
            b1, _, bid = worley(c, 30, seed + 7, jitter=1.0)
            bw = fbm(c, 160, 160, octaves=3, seed=seed + 8)
            blotch = np.clip((0.36 + 0.12 * bid - b1 * (0.7 + 0.6 * bw)) / 0.16, 0, 1) * (bid < 0.7) * figure
            col = col * (1 - 0.16 * blotch)[..., None]
            height = -0.00002 * lines - 0.00003 * eye
        col = mix(col, np.broadcast_to(Dk, col.shape), lines * 0.25)
        if kind != 'birdseye':
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


def points(c, n, d_base, d_tip, width_base, phase=0.0, curve=1.0, soft_px=1.2, sweep=0.0, wave=None):
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
    # sweep bends each point sideways toward its tip (radians at the tip); wave = (amplitude
    # radians, cycles per stud) ripples it like a flame
    theta = c.theta - sweep * (1 - t) ** 2
    if wave is not None:
        theta = theta - wave[0] * np.sin(2 * math.pi * wave[1] * c.d) * (1 - t)
    best = np.full(c.d.shape, 1e9)
    for a in centres:
        best = np.minimum(best, angle_diff(theta, a))
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


def inlay_points(c, m, n, d_base, d_tip, width, fill, veneers=(), phase=math.pi, curve=1.0, sweep=0.0, wave=None):
    """n inlaid points (see points()) painted inside mask m: fill(c, mask) paints the point's body,
    then each veneer (colour, thickness in studs, [roughness, metal]) lines its edge from the
    outside in, like the layered veneers of a real cue's points. Returns the point coverage."""
    cov, edge = points(c, n, d_base, d_tip, width, phase=phase, curve=curve, sweep=sweep, wave=wave)
    e = np.where(edge > -1, edge * c.r, -1)  # studs inside the edge
    inside = cov * m
    if inside.any():
        fill(c, inside > 0.5)
        acc = 0.0
        px = 2 * math.pi * float(np.mean(c.r)) / c.h
        for v in veneers:
            colour, t = v[0], v[1]
            rough = v[2] if len(v) > 2 else 0.25
            mt = v[3] if len(v) > 3 else 0.0
            lo = smooth(acc - px * 0.6, acc + px * 0.6, e)
            hi = 1 - smooth(acc + t - px * 0.6, acc + t + px * 0.6, e)
            band_ = np.clip(lo * hi, 0, 1) * inside
            if mt > 0:
                metal(c, band_ > 0.5, colour, rough=rough, brushed=False)
            else:
                c.put(band_, rgb(colour), rough=rough, metal=0.0)
            c.add_height(band_, -0.00006)
            acc += t
        # a hairline groove round the whole inlay
        rim = np.exp(-(e / (px * 0.8)) ** 2) * (edge > -1) * m
        c.add_height(rim, -0.00012)
    return cov


def inlay_diamond(c, m, d_centre, theta_centre, half_len, half_wid, colour, kind='pearl', border=None,
                  border_w=0.004, glow=0.0):
    """A diamond inlay (pearl, stone or metal), optionally with a metal border."""
    outer = diamond(c, d_centre, theta_centre, half_len + (border_w if border else 0), half_wid + (border_w if border else 0)) * m
    inner = diamond(c, d_centre, theta_centre, half_len, half_wid) * m
    if border:
        metal(c, (outer - inner) > 0.5, border, rough=0.14, brushed=False)
    if kind == 'pearl':
        pearl(c, inner > 0.5, colour, rough=0.15)
        c.put(inner, None)
    elif kind == 'gem':
        # a faceted stone: brighter toward one facet, glossy
        along = c.d - d_centre
        around = np.mod(c.theta - theta_centre + math.pi, 2 * math.pi) - math.pi
        facet = np.where(along * around > 0, 1.25, 0.8) * np.where(along > 0, 1.0, 0.85)
        col = rgb(colour) * facet[..., None]
        sparkle = np.clip((noise(c, 900, 900, seed=7) - 0.8) * 5, 0, 1)
        col = col + (255 - col) * (sparkle * 0.6)[..., None]
        c.put(inner, col, rough=0.05, metal=0.1, glow=inner * glow)
    else:
        metal(c, inner > 0.5, colour, rough=0.12, brushed=False)
    c.add_height(inner, 0.00008)
    return outer


def inlay_lozenge(c, m, d0, d1, theta, half_w, fill, veneers=(), curve=1.0):
    """A long double-ended point (widest in the middle, sharp at d0 and d1), centred at angle
    theta, half_w studs wide at the middle; fill(c, mask) paints the body and veneers line the
    edge from the outside in, as inlay_points."""
    mid, half_len = (d0 + d1) / 2, (d1 - d0) / 2
    t = np.clip(1 - np.abs(c.d - mid) / half_len, 0, 1) ** curve
    around = angle_diff(c.theta, theta) * c.r
    e = half_w * t - around
    px = 2 * math.pi * float(np.mean(c.r)) / c.h
    inside = np.clip(e / px + 0.5, 0, 1) * (t > 0) * m
    if not inside.any():
        return inside
    fill(c, inside > 0.5)
    acc = 0.0
    for v in veneers:
        colour, th = v[0], v[1]
        band_ = np.clip(smooth(acc - px * 0.6, acc + px * 0.6, e) * (1 - smooth(acc + th - px * 0.6, acc + th + px * 0.6, e)), 0, 1) * inside
        if len(v) > 3 and v[3] > 0:
            metal(c, band_ > 0.5, colour, rough=v[2], brushed=False)
        else:
            c.put(band_, rgb(colour), rough=v[2] if len(v) > 2 else 0.2, metal=0.0)
        acc += th
    c.add_height(np.exp(-(e / (px * 0.8)) ** 2) * (t > 0) * m, -0.00012)
    return inside


def ivory(c, m, color='#F1EAD8', rough=0.16, seed=65):
    """Ivory-coloured inlay (a resin ivory): warm, faintly grained, glossy."""
    g = fbm(c, 40, 400, octaves=3, seed=seed)
    c.put(m, rgb(color) * (0.95 + 0.07 * g)[..., None], rough=rough, metal=0.0)


def teardrop(c, d_round, d_tip, theta_centre, radius):
    """A teardrop inlay: round end at d_round, point at d_tip (studs)."""
    along = c.d - d_round
    around = angle_diff(c.theta, theta_centre) * c.r
    circle = np.hypot(along, around) < radius
    span = d_tip - d_round
    t = np.clip(along / span, 0, 1)
    tri = (along * np.sign(span) > 0) & (np.abs(along) <= abs(span)) & (around < radius * (1 - t) ** 1.2)
    return (circle | tri).astype(np.float64)


def ring_lines(c, m, lines):
    """Thin rings round the cue: [(d0, d1, colour, kind)] with kind 'metal', 'pearl' or 'paint'."""
    for d0, d1, colour, kind in lines:
        b_ = band(c, d0, d1, soft=0.0008) * m
        if not b_.any():
            continue
        if kind == 'metal':
            metal(c, b_ > 0.5, colour, rough=0.14, brushed=True)
        elif kind == 'pearl':
            pearl(c, b_ > 0.5, colour, rough=0.18)
        else:
            c.put(b_, rgb(colour), rough=0.2, metal=0.0)
        c.add_height(b_, -0.00005)


def butt_cap_band(k, colour, d0=6.9, rough=0.1):
    """A polished metal butt-cap band at the end of the sleeve, before the bumper."""
    for c, m in k.zone('cap'):
        metal(c, band(c, d0, 7.2) * m > 0.5, colour, rough=rough, brushed=True)
    seam_edges(k, [d0])


def glow_ring(k, colour, base=None, d0=5.378, d1=5.418, base_kind='metal'):
    """The Uncommon glowing ring: a bright emissive band in the ring zone (the glow mask carries
    it), on a metal or gloss base."""
    for c, m in k.zone('ring'):
        if base:
            if base_kind == 'metal':
                metal(c, m, base, rough=0.1, brushed=True)
            else:
                gloss(c, m, base, rough=0.1)
        c.put(m, None, glow=0.0)
        line = band(c, d0, d1, soft=0.0012) * m
        c.put(line, rgb(colour), rough=0.25, metal=0.0, glow=line)
        c.add_height(line, 0.00005)


def ai_base(k, panel, rough=0.2, height=0.0003, blur=1):
    """An OpenAI panel as the colour, with flat roughness, no metal, no glow and a relief from its
    brightness; recipes then set roughness, metal and glow per part."""
    img = ai_panel(k, panel)
    c = k.c[panel]
    ones = np.ones((c.h, c.w), bool)
    c.put(ones, None, rough=rough, metal=0.0, glow=0.0)
    if height:
        c.add_height(ones, height_from(img, height, blur=blur))
    return img


def hue_mask(img, target, tol=40.0, min_sat=0.25):
    """Where an image is close to a colour (in RGB distance, softly), and saturated enough."""
    t = rgb(target)
    dist = np.sqrt(((img - t) ** 2).sum(-1))
    mx, mn = img.max(-1), img.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    return np.clip(1 - (dist - tol) / tol, 0, 1) * (sat > min_sat)


def gummy_blobs(c, m, colours, freq=10.0, cover=0.5, seed=0):
    """Soft jelly-candy blobs in several colours: rounded drops round jittered points (cellular
    noise), their outlines warped so neighbours melt into each other, deeper and more saturated
    at the rim with a light inner rim and a clear middle, glossy and domed. freq is drops per
    stud; cover 0..1 how many cells carry a drop. Returns the total blob coverage."""
    warp = (fbm(c, freq * 1.3, freq * 1.3, octaves=2, seed=seed + 1) - 0.5) * 0.9 / freq
    view = type('V', (), {})()
    view.x, view.d, view.z = c.x + warp, c.d + warp * 0.7, c.z - warp
    f1, _, cid = worley(view, freq, seed + 2, jitter=0.85)
    radius = 0.5 + 0.24 * np.mod(cid * 9.1, 1)
    inside = radius - f1  # cell widths inside the drop's edge
    px = 1.0 / (freq * 2 * math.pi * float(np.mean(c.r)) / c.h)
    cov = np.clip(inside * freq / (1.4 / px) + 0.5, 0, 1) * m * (cid < cover)
    total = np.zeros(c.d.shape)
    pick = np.minimum((np.mod(cid * 37.7, 1) * len(colours)).astype(int), len(colours) - 1)
    depth = np.clip(inside / 0.22, 0, 1)
    for i, col in enumerate(colours):
        cm = cov * (pick == i)
        if not cm.any():
            continue
        base = rgb(col)
        rim = base * 0.8
        core = base + (255 - base) * 0.3
        shade = mix(np.broadcast_to(rim, c.col.shape), np.broadcast_to(core, c.col.shape), depth ** 0.7)
        hi = np.exp(-((inside - 0.05) / 0.02) ** 2)  # the light inner rim of a jelly drop
        shade = shade + (255 - shade) * (0.35 * hi)[..., None]
        c.put(cm, shade, rough=0.05, metal=0.0)
        total = total + cm
    c.add_height(cov, 0.0008 * depth ** 0.5)
    return np.clip(total, 0, 1)


def pixel_blocks(c, m, colours, size=0.022, density=0.5, seed=0, clump=6.0, glow=0.0, aspect=1.0):
    """8-bit pixel blocks on a grid that wraps the cue (a whole number of cells round it): each
    cell picks a colour or stays empty by a hash, clumped by a smooth field so the pixels form
    blobs and steps like an old game screen. Blocks are slightly raised with a dark bevel."""
    n_round = max(8, int(round(float(np.mean(2 * math.pi * c.r)) / size)))
    a = c.d / (size * aspect)  # aspect > 1: dashes along the cue
    b = c.theta / (2 * math.pi) * n_round
    i, j = np.floor(a), np.floor(b)
    h1 = cc._hash3(i.astype(np.int64), j.astype(np.int64), np.zeros_like(i, np.int64), seed)
    h2 = cc._hash3(i.astype(np.int64), j.astype(np.int64), np.ones_like(i, np.int64), seed + 1)
    # the clump field sampled at the cell centre (so a whole cell shares it)
    ang = (j + 0.5) / n_round * 2 * math.pi
    rr = float(np.mean(c.r))
    field = cc.fbm(rr * np.sin(ang) * clump, (i + 0.5) * size * aspect * clump, -rr * np.cos(ang) * clump, 3, seed + 2)
    on = (h1 < density * np.clip((field - 0.3) * 2.2, 0, 1.4)) * m
    idx = np.minimum((h2 * len(colours)).astype(int), len(colours) - 1)
    pal = np.array([rgb(x) for x in colours])
    col = pal[idx]
    fa, fb = np.mod(a, 1), np.mod(b, 1)
    edge = np.minimum(np.minimum(fa, 1 - fa) * aspect, np.minimum(fb, 1 - fb))
    bevel = np.clip(edge / 0.12, 0, 1)
    col = col * (0.72 + 0.28 * bevel)[..., None]
    c.put(on, col, rough=0.12, metal=0.0, glow=on * glow if glow else None)
    c.add_height(on, 0.00012 * bevel)
    return on


# ---------------------------------------------------------------------------------------------
# The kit: all five canvases and the plain-colour parts
# ---------------------------------------------------------------------------------------------

class Kit:
    def __init__(self, skin):
        self.P = Params()
        self.skin = skin
        self.frame = 0  # the moving-material frame being painted (skin "frames")
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
        # a faint warm glow through the whole amber shaft, so the tip end glows too
        c.put(m, None, glow=np.maximum(c.glow, 0.12 * m))
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


@recipe
def arctic(k):
    """Gloss pearl white with one frosted ice-blue stripe along the top of the forearm (tapering to
    a point toward the joint, a thin chrome edge), a pearl-white sleeve, chrome collar, ring and
    butt-cap band, white pebbled leather wrap; a silver-white shaft."""
    s = k.skin['colours']
    chrome, ice = s['metal'], rgb(s['ice'])
    k.paint(['shaft'], wood, 'maple', '#E2E5E8', '#A9AEB4', rough=0.16, seed=102, stain=s['shaft'])
    for c, m in k.zone('forearm', 'cap'):
        pearl(c, m, s['body'], rough=0.08, fire=0.25)
    for c, m in k.zone('forearm'):
        # a wide ice-blue wedge: full width at the ring, a sharp point 0.12 studs after the
        # collar, lined with a silver edge and a pinstripe on each side (the concept's close-up)
        t = np.clip((c.d - (F0 + 0.12)) / (F1 - F0 - 0.12), 0, 1)
        width = 0.07 * (0.62 + 0.38 * t) * np.clip(t / 0.2, 0, 1) ** 0.75
        on = m & (c.d > F0 + 0.1)
        st = stripe_along(c, math.pi, width) * on
        frost = fbm(c, 300, 60, octaves=3, seed=101)
        across = angle_diff(c.theta, math.pi) * c.r / np.maximum(width, 1e-4)
        shade = 1.08 - 0.22 * across ** 2 + 0.08 * (frost - 0.5)
        c.put(st, ice * shade[..., None], rough=0.18, metal=0.0, glow=st * 0.1)
        for off, w_ in ((0.0, 0.003), (0.009, 0.0014)):
            line = np.clip(stripe_along(c, math.pi, width + off + w_) - stripe_along(c, math.pi, width + off), 0, 1) * on
            metal(c, line > 0.35, chrome, rough=0.08, brushed=False)
            c.add_height(line, -0.0001)
    k.paint(['wrap'], leather, s['wrap'], rough=0.55, depth=0.0009, scale=2.8, contrast=1.4)
    standard_hardware(k, joint=chrome, ring=chrome, joint_rough=0.08, ring_rough=0.08, end='#141414')
    butt_cap_band(k, chrome)
    seam_edges(k, [F1])
    cap_face_metal(k.c['cap_end'], chrome, rough=0.14)


@recipe
def cherry(k):
    """Satin ruby-red maple (a bloodwood-like grain) on the forearm and sleeve, a black pebbled wrap
    (the concept's), stainless collar, ring and butt-cap band, and a black carbon shaft."""
    s = k.skin['colours']
    steel = s['metal']
    k.paint(['shaft'], carbon_weave, '#08080A', '#3E4046', rough=0.12, tow=0.01)
    for c, m in k.zone('forearm', 'cap'):
        wood(c, m, 'rosewood', '#B01624', '#4A060C', rough=0.22, seed=111)
        c.put(m, None)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    standard_hardware(k, joint=steel, ring=steel, joint_rough=0.12, ring_rough=0.12, end='#141414')
    butt_cap_band(k, steel)
    seam_edges(k, [F1, C0])
    cap_face_metal(k.c['cap_end'], steel, rough=0.2)


@recipe
def carbon(k):
    """Carbon fibre from tip to butt: the twill weave under a glossy clear coat, a black pebbled
    leather wrap, stainless collar, ring and butt-cap band."""
    s = k.skin['colours']
    steel = s['metal']
    k.paint(['shaft'], carbon_weave, s['dark'], s['light'], rough=0.1, tow=0.012)
    k.paint(['forearm', 'cap'], carbon_weave, s['dark'], s['light'], rough=0.07, tow=0.02)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    standard_hardware(k, joint=steel, ring=steel, joint_rough=0.1, ring_rough=0.1, end='#141414')
    butt_cap_band(k, steel)
    seam_edges(k, [F1, C0])
    cap_face_metal(k.c['cap_end'], steel, rough=0.2)


@recipe
def heritage(k):
    """The classic four-point: honey birdseye maple; four black points, wide at the collar and
    tapering toward the wrap, each lined with maple, orange and green veneers, a pearl diamond
    in the black of each; an off-white wrap flecked with green; black rings with green, ivory
    and orange lines; the sleeve repeats the points; a birdseye shaft; steel collar."""
    s = k.skin['colours']
    black, maple, green, orange, ivory = s['black'], s['maple'], s['green'], s['orange'], s['ivory']
    honey = ('#E6B26C', '#8E5A22')
    k.paint(['shaft'], wood, 'birdseye', '#EBC68A', '#9A6A30', rough=0.2, seed=121, figure=0.9)
    ebony = lambda cc_, mm: wood(cc_, mm, 'ebony', '#1E1812', '#0A0806', rough=0.14, seed=123)
    # the points are centred 45 degrees off the top, so one faces a camera above and to the side
    ph = math.pi / 4
    veneers = [(maple, 0.005), (orange, 0.012), (black, 0.002), (green, 0.009), (black, 0.002)]
    for c, m in k.zone('forearm'):
        wood(c, m, 'birdseye', honey[0], honey[1], rough=0.16, seed=122, figure=1.0)
        inlay_points(c, m, 4, F0, F0 + 0.88 * (F1 - F0), 1.65, ebony, veneers, phase=ph, curve=1.0)
        for i in range(4):
            inlay_diamond(c, m, F0 + 0.24, ph + i * math.pi / 2, 0.1, 0.03, ivory, 'pearl')
    for c, m in k.zone('cap'):
        wood(c, m, 'birdseye', honey[0], honey[1], rough=0.16, seed=124, figure=1.0)
        inlay_points(c, m, 4, C0 + 0.03, 6.93, 1.5, ebony,
                     [(maple, 0.004), (orange, 0.009), (black, 0.0015), (green, 0.007)], phase=ph, curve=1.1)
        for i in range(4):
            inlay_diamond(c, m, C0 + 0.13, ph + i * math.pi / 2, 0.06, 0.022, ivory, 'pearl')
        ring_lines(c, m, [(C0, C0 + 0.03, black, 'paint'), (C0 + 0.006, C0 + 0.011, orange, 'paint'),
                          (C0 + 0.017, C0 + 0.022, orange, 'paint'), (6.935, 7.1, black, 'paint')])
    for c, m in k.zone('wrap'):
        fleck_wrap(c, m, s['wrap'], green, amount=0.85, size=2.2)
    k.paint(['joint'], metal, s['metal'], rough=0.12)
    for c, m in k.zone('ring'):
        ring_lines(c, m, [(5.32, 5.43, black, 'paint'), (5.334, 5.346, green, 'paint'), (5.356, 5.362, ivory, 'pearl'),
                          (5.372, 5.384, green, 'paint'), (5.396, 5.404, orange, 'paint')])
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)
    seam_edges(k, [F1, C0, W0, W1])


@recipe
def monarch(k):
    """Black ebony: on each quarter a long double-ended curly-maple lozenge edged in ivory, with
    a small ivory diamond before it, and long ivory points running in from both ends between
    them; short ivory-edged maple points on the shaft before the steel collar; thick ivory rings
    with a black and a silver line; a black pebbled leather wrap; a black sleeve with maple
    lozenges, ivory diamonds and steel teardrops; a chrome butt cap; an ebony shaft."""
    s = k.skin['colours']
    ebony_c, iv, maple, silver = s['ebony'], s['ivory'], s['maple'], s['metal']
    ph = math.pi / 4  # the lozenges face a camera above and to the side, like Heritage's points
    ebony = lambda cc_, mm, sd=132: wood(cc_, mm, 'ebony', '#221B15', '#0A0806', rough=0.12, seed=sd)
    curly = lambda cc_, mm: wood(cc_, mm, 'curly', '#DDB887', '#8A6236', rough=0.14, seed=133, figure=0.9)
    ivo = lambda cc_, mm: ivory(cc_, mm, iv)
    k.paint(['shaft'], wood, 'ebony', '#2A221C', '#0E0B09', rough=0.16, seed=131)
    for c, m in k.zone('shaft'):
        # short ivory-edged maple points on the shaft, pointing to the tip from the collar
        inlay_points(c, m, 4, J0, J0 - 0.32, 0.5, curly, [(iv, 0.005)], phase=ph)
        inlay_points(c, m, 4, J0, J0 - 0.2, 0.34, ivo, [], phase=ph + math.pi / 4)
    for c, m in k.zone('forearm'):
        ebony(c, m)
        for i in range(4):
            a = ph + i * math.pi / 2
            inlay_lozenge(c, m, F0 + 0.36, F1 - 0.06, a, 0.055, curly, [(iv, 0.011)], curve=1.0)
            inlay_diamond(c, m, F0 + 0.2, a, 0.075, 0.022, iv, 'pearl')
        inlay_points(c, m, 4, F0, F0 + 0.75, 0.42, ivo, [], phase=ph + math.pi / 4, curve=1.0)
        inlay_points(c, m, 4, F1, F1 - 0.75, 0.42, ivo, [], phase=ph + math.pi / 4, curve=1.0)
    for c, m in k.zone('cap'):
        ebony(c, m, 134)
        for i in range(4):
            a = ph + i * math.pi / 2
            b = a + math.pi / 4
            td = teardrop(c, 6.89, 6.74, a, 0.042) * m
            metal(c, td > 0.5, silver, rough=0.08, brushed=False)
            rim = (teardrop(c, 6.89, 6.735, a, 0.047) * m - td) > 0.5
            ivory(c, rim, iv)
            c.add_height(td, 0.00008)
            inlay_diamond(c, m, 6.68, a, 0.035, 0.016, iv, 'pearl')
            inlay_lozenge(c, m, 6.645, 6.95, b, 0.04, curly, [(iv, 0.006)])
        ring_lines(c, m, [(C0, C0 + 0.012, iv, 'paint'), (C0 + 0.012, C0 + 0.016, ebony_c, 'paint'),
                          (C0 + 0.016, C0 + 0.022, iv, 'paint')])
    butt_cap_band(k, silver, d0=6.965, rough=0.07)
    k.paint(['wrap'], leather, s['wrap'], rough=0.42, depth=0.001, scale=4.2, contrast=3.0, sheen=0.7)
    k.paint(['joint'], metal, silver, rough=0.1)
    for c, m in k.zone('ring'):
        ring_lines(c, m, [(5.32, 5.43, ebony_c, 'paint'), (5.332, 5.36, iv, 'paint'), (5.366, 5.374, silver, 'metal'),
                          (5.38, 5.408, iv, 'paint')])
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)
    seam_edges(k, [F1, C0, W0, W1, J0])


@recipe
def cobalt(k):
    """Curly maple stained deep Prussian blue under a gloss finish (shaft and forearm); on each
    quarter a double-ended lozenge outlined silver / navy / silver round a navy field and a large
    faceted blue gem, slim silver-outlined lozenges between them; a smooth smoke-grey leather
    handle (no wrap); a black sleeve with silver and blue V points meeting at a blue gem; thin
    silver rings; steel collar."""
    s = k.skin['colours']
    blue, grey, silver, gem, navy = s['blue'], s['grey'], s['metal'], s['gem'], s['navy']
    ph = math.pi / 4
    stained = lambda sd: (lambda cc_, mm: wood(cc_, mm, 'curly', '#D8B98B', '#8A6A3A', rough=0.1, seed=sd, stain=blue, figure=1.0))
    k.paint(['shaft'], wood, 'curly', '#D8B98B', '#8A6A3A', rough=0.12, seed=141, stain=blue, figure=0.9)
    trim = [(silver, 0.006, 0.1, 1.0), (navy, 0.011), (silver, 0.004, 0.1, 1.0)]
    for c, m in k.zone('forearm'):
        stained(142)(c, m)
        for i in range(4):
            a = ph + i * math.pi / 2
            inlay_lozenge(c, m, F0 + 0.2, F1 - 0.04, a, 0.06, stained(143), trim)
            field = diamond(c, F0 + 0.62, a, 0.2, 0.045) * m
            c.put(field, rgb(navy) * (0.9 + 0.2 * fbm(c, 200, 200, octaves=2, seed=144))[..., None], rough=0.1, metal=0.0)
            inlay_diamond(c, m, F0 + 0.62, a, 0.12, 0.03, gem, 'gem', border=silver, glow=0.2)
            inlay_lozenge(c, m, F0 + 0.55, F1 - 0.02, a + math.pi / 4, 0.022, stained(145), [(silver, 0.003, 0.1, 1.0)])
    for c, m in k.zone('cap'):
        gloss(c, m, '#0C0D10', rough=0.07, flake=0.15)
        inlay_points(c, m, 4, 6.985, C0 + 0.05, 1.5, lambda cc_, mm: gloss(cc_, mm, '#0C0D10', rough=0.07),
                     [(silver, 0.003, 0.1, 1.0), (blue, 0.008, 0.12), (silver, 0.002, 0.1, 1.0)], phase=ph)
        for i in range(4):
            inlay_diamond(c, m, 6.86, ph + i * math.pi / 2, 0.06, 0.028, gem, 'gem', border=silver, glow=0.2)
        ring_lines(c, m, [(C0, C0 + 0.008, silver, 'metal')])
    for c, m in k.zone('wrap'):
        leather(c, m, grey, rough=0.5, depth=0.00025, scale=5.0, contrast=0.6, sheen=0.2)
    k.paint(['joint'], metal, silver, rough=0.1)
    for c, m in k.zone('ring'):
        gloss(c, m, '#0C0D10', rough=0.08)
        ring_lines(c, m, [(5.40, 5.412, silver, 'metal')])
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)
    seam_edges(k, [F1, W0, W1])

# --- Uncommons ------------------------------------------------------------------------------

def end_band(k, colour='#0C0C0E', d0=6.93, rough=0.14):
    """A black butt cap at the end of the sleeve (the concepts' big black end)."""
    for c, m in k.zone('cap'):
        gloss(c, band(c, d0, 7.2) * m > 0.5, colour, rough=rough)
    seam_edges(k, [d0])


def joint_seam(k):
    f = k.c['forearm']
    mid = (J0 + J1) / 2
    line = band(f, mid - 0.0025, mid + 0.0025, soft=0.001)
    f.put(line > 0.01, f.col * 0.35, rough=0.4)
    f.add_height(line, -0.0003)


@recipe
def gummy(k):
    """Pastel jelly-candy blobs of pink and light blue over see-through silver carbon from the
    shaft to the butt (no wrap), a chrome collar with a pink line, a glowing pink ring, a black
    sleeve with pink and blue blobs behind a pink line."""
    s = k.skin['colours']
    pink, blue, silver = s['pink'], s['blue'], s['silver']
    k.paint(['shaft'], carbon_weave, '#80858C', silver, rough=0.08, tow=0.008)
    k.paint(['forearm', 'wrap'], carbon_weave, '#80858C', silver, rough=0.08, tow=0.012)
    for c, m in k.zone('shaft'):
        gummy_blobs(c, m * smooth(0.4, 1.6, c.d), [pink, blue], freq=9.0, cover=0.7, seed=151)
    for c, m in k.zone('forearm', 'wrap'):
        gummy_blobs(c, m, [pink, blue], freq=5.2, cover=0.9, seed=152)
    for c, m in k.zone('cap'):
        gloss(c, m, '#0E0E12', rough=0.08)
        gummy_blobs(c, m, [pink, blue], freq=6.0, cover=0.85, seed=153)
        ring_lines(c, m, [(C0, C0 + 0.02, pink, 'paint')])
    end_band(k, d0=6.95)
    k.paint(['joint'], metal, s['metal'], rough=0.1)
    for c, m in k.zone('forearm'):
        ring_lines(c, m, [(J1 - 0.02, J1, pink, 'paint')])
    glow_ring(k, s['glow'], base='#0E0E12', base_kind='gloss', d0=5.34, d1=5.405)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W1, C0])


def racing_shaft(k, body, stripe, seed=0, sweep=1.1, n=3, length=2.4, width=0.2, outline=None):
    """A gloss shaft with a few long thin racing slashes spiralling from the joint to sharp
    points toward the tip (optionally outlined in the body colour's bright tone)."""
    for c, m in k.zone('shaft'):
        gloss(c, m, body, rough=0.1, flake=0.2)
        for w_, ln, ph, sw in ((width, length, 0.0, sweep), (width * 0.55, length * 0.62, math.pi / n, sweep * 0.8)):
            cov, edge = points(c, n, J0, J0 - ln, w_, phase=ph + 0.4 * seed, curve=1.7, sweep=sw)
            c.put(cov * m, rgb(stripe), rough=0.1, metal=0.0)
            if outline:
                e = np.where(edge > -1, edge * c.r, -1)
                line = np.clip(1 - np.abs(e - 0.0035) / 0.0015, 0, 1) * m * (e > 0)
                c.put(line, rgb(outline), rough=0.1)


def finish_ai_racing(k, s, main, snake_dark=True):
    """Flare and Hornet: OpenAI shaft end, forearm and butt; the paint glossy, the snakeskin grip
    matte with relief, the joint strips carbon; the glowing ring in the ring zone."""
    img = ai_base(k, 'shaft_top', rough=0.1, height=0.0001)
    t = k.c['shaft_top']
    t.put(np.ones((t.h, t.w), bool), None, rough=0.1)
    img = ai_base(k, 'forearm', rough=0.12, height=0.0005)
    f = k.c['forearm']
    paint_m = hue_mask(img, main, tol=90, min_sat=0.35)
    f.put(np.ones((f.h, f.w), bool), None, rough=0.36 - 0.24 * paint_m)
    f.col = f.col * (0.55 + 0.45 * paint_m)[..., None]  # the black and the scales: deep black
    joint = f.zone('joint')
    carbon_weave(f, joint, '#141414', '#3A3A3A', rough=0.1, tow=0.012)
    for c, m in k.zone('joint'):
        ring_lines(c, m, [(J1 - 0.018, J1 - 0.004, main, 'paint')])
    img = ai_base(k, 'butt', rough=0.45, height=0.0009)
    b = k.c['butt']
    paint_m = hue_mask(img, main, tol=90, min_sat=0.35)
    lum = luma(img)
    b.put(np.ones((b.h, b.w), bool), None, rough=0.5 - 0.2 * np.clip(lum * 3, 0, 1) - 0.25 * paint_m)
    b.col = b.col * (0.55 + 0.45 * paint_m)[..., None]
    b.put(b.zone('cap'), None, rough=0.14 + 0.3 * (1 - paint_m))
    glow_ring(k, s['glow'], base='#121212', base_kind='gloss', d0=5.35, d1=5.4)
    for c, m in k.zone('cap'):
        ring_lines(c, m, [(C0 + 0.004, C0 + 0.016, main, 'paint')])
    end_band(k, d0=6.97)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def flare(k):
    """Electric orange gloss with black racing slashes (OpenAI forearm), a black carbon collar
    with an orange line, a glowing orange ring, a black snakeskin sport grip, a black sleeve
    with an orange chevron; an orange shaft with black slashes reaching from the joint."""
    s = k.skin['colours']
    racing_shaft(k, s['orange'], s['black'], seed=1)
    finish_ai_racing(k, s, s['orange'])


@recipe
def hornet(k):
    """Black and yellow racing-jersey graphics over black hex carbon (OpenAI forearm), a black
    carbon collar with a yellow line, a glowing yellow ring, a black snakeskin sport grip, a black
    sleeve with a yellow chevron; a black shaft with yellow slashes reaching from the joint."""
    s = k.skin['colours']
    racing_shaft(k, s['black'], s['yellow'], seed=2, width=0.24)
    finish_ai_racing(k, s, s['yellow'])


@recipe
def venom(k):
    """Deep black with six long neon-green carbon-fibre points rippling up the forearm like
    flames (running over the joint onto the shaft), a chrome band and a glowing green ring at
    the wrap, black pebbled leather, a chrome ring, a carbon sleeve with green streaks, a black
    end cap."""
    s = k.skin['colours']
    green, black = s['green'], s['black']
    green_carbon = lambda cc_, mm: carbon_weave(cc_, mm, '#2FD012', green, rough=0.08, tow=0.006)
    dark_green = lambda cc_, mm: carbon_weave(cc_, mm, '#135E08', '#27A011', rough=0.08, tow=0.006)
    for c, m in k.zone('shaft', 'joint', 'forearm'):
        gloss(c, m, black, rough=0.08, flake=0.25, flake_color='#1C2A1C')
        inlay_points(c, m, 6, F1, 2.7, 0.26, dark_green, [], phase=math.pi / 6, curve=2.2, sweep=0.7, wave=(0.12, 1.6))
        inlay_points(c, m, 6, F1, 3.2, 0.3, green_carbon, [], phase=0.0, curve=2.0, sweep=0.6, wave=(0.1, 1.3))
        inlay_points(c, m, 6, F1, 4.3, 0.16, green_carbon, [], phase=math.pi / 12, curve=1.6, sweep=0.5, wave=(0.08, 2.0))
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.08)
    glow_ring(k, s['glow'], d0=5.382, d1=5.418)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    for c, m in k.zone('cap'):
        carbon_weave(c, m, '#0A0A0A', '#3A3A3E', rough=0.08, tow=0.016)
        inlay_points(c, m, 6, C0 + 0.03, 6.93, 0.3, lambda cc_, mm: gloss(cc_, mm, green, rough=0.1), [], phase=0.3,
                     curve=1.3, sweep=0.9)
        ring_lines(c, m, [(C0, C0 + 0.025, s['metal'], 'metal')])
    end_band(k, d0=6.93)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def lagoon(k):
    """Gloss black with six bold turquoise points edged in white sweeping up the forearm (over
    the joint onto the shaft), white chevrons at their base, a chrome band and a glowing
    turquoise ring at the wrap, black pebbled leather, two turquoise rings, a black sleeve with
    turquoise and white swept points meeting in the middle, a black end cap."""
    s = k.skin['colours']
    teal, white, black = s['teal'], s['white'], s['black']
    tealfill = lambda cc_, mm: gloss(cc_, mm, teal, rough=0.08)
    blackfill = lambda cc_, mm: gloss(cc_, mm, black, rough=0.06)
    ph = math.pi / 4
    for c, m in k.zone('shaft', 'joint', 'forearm'):
        gloss(c, m, black, rough=0.06, flake=0.15)
        # long turquoise points edged white, sweeping from the ring toward the tip
        inlay_points(c, m, 4, F1, 3.0, 0.5, tealfill, [(white, 0.007)], phase=ph + math.pi / 4, curve=1.8, sweep=0.35)
        # the layered arrowheads at the ring: white arms, turquoise arms, a black centre
        inlay_points(c, m, 4, F1, F1 - 0.6, 0.72, blackfill, [(white, 0.017), (teal, 0.011)], phase=ph, curve=1.1)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.08)
    glow_ring(k, s['glow'], d0=5.382, d1=5.418)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    for c, m in k.zone('cap'):
        gloss(c, m, black, rough=0.06)
        # swept wings from the wrap end toward the butt, and a turquoise arrow back from the end
        inlay_points(c, m, 4, C0 + 0.045, 6.92, 0.95, blackfill, [(white, 0.004), (teal, 0.012)], phase=ph + math.pi / 4,
                     curve=1.5, sweep=0.35)
        inlay_points(c, m, 4, 6.92, C0 + 0.12, 0.55, tealfill, [(white, 0.004)], phase=ph, curve=1.4)
        ring_lines(c, m, [(C0 + 0.004, C0 + 0.014, teal, 'paint'), (C0 + 0.022, C0 + 0.032, teal, 'paint'),
                          (6.922, 6.932, teal, 'paint')])
    end_band(k, d0=6.94)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def splice(k):
    """Black wood with eight long spliced points on the forearm (over the joint onto the shaft),
    each layered ivory, bright blue, sky blue and ivory round a black core; a chrome band and a
    glowing blue ring; black pebbled leather; an ivory ring; a black-wood sleeve with nested
    ivory and blue lozenges (the other eight points, meeting from both ends); a black end cap."""
    s = k.skin['colours']
    blue, sky, iv = s['blue'], s['sky'], s['ivory']
    blackwood = lambda sd: (lambda cc_, mm: wood(cc_, mm, 'rosewood', '#3A2A20', '#0E0907', rough=0.14, seed=sd))
    ph = math.pi / 4
    for c, m in k.zone('shaft', 'joint', 'forearm'):
        blackwood(161)(c, m)
        # eight points: four long ones joined at the ring into nested ivory and blue V's, and four
        # shorter ones between them
        inlay_points(c, m, 4, F1, 3.9, 0.7, blackwood(163), [(blue, 0.008), (iv, 0.005)], phase=ph + math.pi / 4, curve=1.2)
        for tip, w_, ven in ((2.6, 0.95, [(blue, 0.01), (sky, 0.004), (iv, 0.004)]),
                             (4.05, 0.8, [(iv, 0.013), (blue, 0.011), (sky, 0.004)]),
                             (4.5, 0.55, [(iv, 0.006), (blue, 0.009)])):
            inlay_points(c, m, 4, F1 + 0.01, tip, w_, blackwood(162), ven, phase=ph, curve=1.0)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.08)
    glow_ring(k, s['glow'], d0=5.382, d1=5.418)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    for c, m in k.zone('cap'):
        blackwood(164)(c, m)
        for i in range(4):
            a = ph + i * math.pi / 2
            inlay_lozenge(c, m, C0 + 0.03, 6.92, a, 0.1, lambda cc_, mm: gloss(cc_, mm, blue, rough=0.08),
                          [(iv, 0.006), (blue, 0.012), (sky, 0.006), (iv, 0.005), ('#0E0907', 0.008), (iv, 0.004)])
            inlay_lozenge(c, m, C0 + 0.1, 6.85, a + math.pi / 4, 0.035, blackwood(165), [(iv, 0.004), (blue, 0.007)])
        ring_lines(c, m, [(C0, C0 + 0.02, '#CDB892', 'paint')])
    end_band(k, d0=6.94)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def cosmo(k):
    """Gloss metallic black space: a shimmering galaxy stripe of blue, violet and magenta and a
    glassy planet on the forearm, a spiral galaxy on the sleeve (both OpenAI); a star-dusted
    navy shaft with a faint nebula stream; a stepped chrome collar; a glowing violet ring; black
    pebbled leather."""
    s = k.skin['colours']
    blue, violet, magenta = rgb(s['blue']), rgb(s['violet']), rgb(s['magenta'])
    for c, m in k.zone('shaft'):
        gloss(c, m, s['space'], rough=0.08, flake=0.35, flake_color='#3A3A6A')
        warp = fbm(c, 4, 0.8, octaves=3, seed=171)
        stream = np.exp(-((angle_diff(c.theta, math.pi - 0.7 + 0.6 * np.sin(c.d * 2.2 + warp * 3)) * c.r) / 0.02) ** 2)
        stream = stream * smooth(0.5, 2.8, c.d) * (0.5 + 0.8 * fbm(c, 40, 6, octaves=3, seed=172))
        hue = fbm(c, 3, 1.2, octaves=2, seed=173)
        scol = mix(np.broadcast_to(blue, c.col.shape), np.broadcast_to(violet, c.col.shape), np.clip(hue * 1.6 - 0.3, 0, 1))
        scol = mix(scol, np.broadcast_to(magenta, c.col.shape), np.clip(hue * 2 - 1.1, 0, 1))
        c.put(np.clip(stream * 1.3, 0, 1) * m, scol, rough=0.08)
        stars = np.clip((cc.noise3(c.x * 1400, c.d * 1400, c.z * 1400, 174) - 0.86) * 12, 0, 1)
        c.put(m * stars, np.broadcast_to([235.0, 235, 255], c.col.shape))
    img = ai_base(k, 'forearm', rough=0.08, height=0.00015)
    f = k.c['forearm']
    metal(f, f.zone('joint'), s['metal'], rough=0.1)
    f.put(f.zone('joint'), None, glow=0.0)
    band2 = band(f, J0 + 0.06, J0 + 0.064, soft=0.001) * f.zone('joint')
    f.add_height(band2, -0.0003)
    img = ai_base(k, 'butt', rough=0.08, height=0.00015)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    glow_ring(k, s['glow'], base='#0A0A12', base_kind='gloss', d0=5.345, d1=5.4)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def gilded(k):
    """Black piano lacquer inlaid with swirling gold art-deco vines and mother-of-pearl
    marquises and diamonds (OpenAI forearm and sleeve; the gold is real metal in the maps, the
    pearl glossy); a natural maple shaft with slim gold-edged black points and pearl diamonds
    before the collar; a stepped chrome collar; a glowing gold ring; black pebbled leather."""
    s = k.skin['colours']
    gold, pearl_c = s['gold'], s['pearl']
    k.paint(['shaft'], wood, 'maple', '#E8C890', '#9A6E3A', rough=0.16, seed=181)
    for c, m in k.zone('shaft'):
        inlay_points(c, m, 4, J0, J0 - 1.2, 0.5, lambda cc_, mm: gloss(cc_, mm, '#0D0D0D', rough=0.06),
                     [(gold, 0.004, 0.2, 1.0)], phase=math.pi / 4, curve=1.4)
        for i in range(4):
            inlay_diamond(c, m, J0 - 0.2, math.pi / 4 + i * math.pi / 2, 0.07, 0.016, pearl_c, 'pearl', border=gold, border_w=0.002)
    for panel in ('forearm', 'butt'):
        img = ai_base(k, panel, rough=0.07, height=0.0002)
        c = k.c[panel]
        g = hue_mask(img, gold, tol=70, min_sat=0.3)
        lum = luma(img)
        pearl_m = np.clip((lum - 0.72) / 0.1, 0, 1) * (1 - g)
        c.put(g, None, rough=0.22, metal=1.0)
        c.put(pearl_m, None, rough=0.1, metal=0.0)
        c.add_height(g, 0.0002)
    f = k.c['forearm']
    metal(f, f.zone('joint'), s['metal'], rough=0.1)
    k.paint(['wrap'], leather, s['wrap'], rough=0.46, depth=0.001, scale=2.4, contrast=2.2, sheen=0.55)
    glow_ring(k, s['glow'], base='#0D0D0D', base_kind='gloss', d0=5.345, d1=5.4)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def pixel(k):
    """A retro arcade 8-bit pattern: magenta, cyan and yellow pixel blocks clumped over a deep
    purple-black gloss (dense on the forearm and sleeve, thinning out down the shaft), a black
    pixel-grid wrap with a few coloured pixels, a stepped chrome collar, a glowing cyan ring."""
    s = k.skin['colours']
    cols = [s['magenta'], s['cyan'], s['yellow']]
    deep = s['deep']
    for c, m in k.zone('shaft'):
        gloss(c, m, deep, rough=0.08, flake=0.2, flake_color='#3A2A6A')
        pixel_blocks(c, m * smooth(0.3, 3.3, c.d), cols, size=0.018, density=0.5, seed=191, clump=5, aspect=3.5)
    for c, m in k.zone('forearm', 'cap'):
        gloss(c, m, deep, rough=0.08)
        pixel_blocks(c, m, ['#2A1A55', '#3A2470'], size=0.036, density=0.9, seed=192, clump=9)
        pixel_blocks(c, m, cols, size=0.036, density=0.9, seed=193, clump=6)
    for c, m in k.zone('wrap'):
        # a black pixel-grid grip: little raised square studs
        n_round = max(8, int(round(float(np.mean(2 * math.pi * c.r)) / 0.026)))
        a, b = c.d / 0.026, c.theta / (2 * math.pi) * n_round
        fa, fb = np.mod(a, 1), np.mod(b, 1)
        stud = np.clip(np.minimum(np.minimum(fa, 1 - fa), np.minimum(fb, 1 - fb)) / 0.15, 0, 1)
        c.put(m, rgb('#101012') * (0.5 + 0.5 * stud)[..., None], rough=0.5, metal=0.0)
        c.add_height(m, 0.0003 * stud)
        pixel_blocks(c, m, cols, size=0.026, density=0.14, seed=194, clump=4)
    k.paint(['joint'], metal, s['metal'], rough=0.1)
    glow_ring(k, s['glow'], base='#120A26', base_kind='gloss', d0=5.345, d1=5.4)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


# --- Rares ----------------------------------------------------------------------------------

def crosshatch(c, m, color, pitch=0.02, rough=0.55, depth=0.0005):
    """A knurled crosshatch grip: grooves winding both ways round the cue, leaving little raised
    diamonds (Plasma's and Blaze's black grips)."""
    n_round = max(8, int(round(float(np.mean(2 * math.pi * c.r)) / pitch)))
    a = c.d / pitch
    b = c.theta / (2 * math.pi) * n_round
    g1 = np.abs(np.mod(a + b, 1) - 0.5) * 2
    g2 = np.abs(np.mod(a - b, 1) - 0.5) * 2
    bump = np.clip(np.minimum(g1, g2) / 0.35, 0, 1) ** 0.7
    fine = fbm(c, 900, 900, octaves=2, seed=77)
    col = rgb(color) * (0.55 + 0.45 * bump + 0.08 * (fine - 0.5))[..., None]
    c.put(m, col, rough=rough - 0.15 * bump, metal=0.0)
    c.add_height(m, depth * (bump - 0.5))


def crack_plates(c, m, freq, plate, crack_lo, crack_hi, seed=0, width=0.07, live=0.75, metal_=0.0,
                 rough=0.4, grain=None, halo=0.35):
    """Plates split by glowing cracks (cellular noise): each plate a slightly different tone
    (with a wood grain if grain), raised; the cracks between them glow crack_hi at the core to
    crack_lo at the edge, with a warm halo bleeding onto the plates; some cracks stay dark."""
    wob = (fbm(c, freq * 2, freq * 2, octaves=2, seed=seed + 1) - 0.5) * 0.5 / freq
    view = type('V', (), {})()
    view.x, view.d, view.z = c.x + wob, c.d + wob, c.z - wob
    f1, f2, cid = worley(view, freq, seed, jitter=0.95)
    edge = f2 - f1
    alive = np.clip((fbm(c, freq * 0.8, freq * 0.8, octaves=2, seed=seed + 2) - (1 - live)) * 4, 0, 1)
    w = width * (0.6 + 0.8 * fbm(c, freq * 3, freq * 3, octaves=2, seed=seed + 3))
    core = np.clip(1 - edge / w, 0, 1)
    glow = core ** 1.5 * alive
    hal = np.exp(-(edge / (w * 3.5)) ** 2) * alive * halo
    base = rgb(plate) * (0.8 + 0.4 * cid)[..., None]
    if grain is not None:
        g = fbm(c, 30, 300, octaves=3, seed=seed + 4)
        base = base * (0.85 + 0.3 * g)[..., None]
    lo, hi = rgb(crack_lo), rgb(crack_hi)
    ccol = mix(np.broadcast_to(lo, c.col.shape), np.broadcast_to(hi, c.col.shape), core ** 2)
    col = mix(base, np.broadcast_to(lo, c.col.shape), hal * 0.6)
    col = mix(col, ccol, np.clip(glow * 1.3, 0, 1))
    dark_crack = np.clip(1 - edge / (w * 0.8), 0, 1) * (1 - alive)
    col = col * (1 - 0.7 * dark_crack)[..., None]
    c.put(m, col, rough=rough + 0.3 * glow, metal=metal_ * (1 - glow), glow=np.clip(glow + hal * 0.35, 0, 1))
    c.add_height(m, 0.0006 * np.clip(edge / 0.25, 0, 1) - 0.0003)


def caustics(c, m, deep, light, freq=18, seed=0, glow=0.25):
    """Sea water: deep colour with bright wavy caustic lines (the edges of warped cells)."""
    wob = (fbm(c, freq * 0.7, freq * 0.7, octaves=3, seed=seed + 1) - 0.5) * 1.2 / freq
    view = type('V', (), {})()
    view.x, view.d, view.z = c.x + wob, c.d + wob * 0.6, c.z - wob
    f1, f2, _ = worley(view, freq, seed)
    line = np.clip(1 - (f2 - f1) / 0.12, 0, 1) ** 2
    depth = fbm(c, 4, 3, octaves=3, seed=seed + 2)
    col = mix(np.broadcast_to(rgb(deep), c.col.shape), np.broadcast_to(rgb(light), c.col.shape), np.clip(depth * 0.6 - 0.1, 0, 1))
    col = col + (255 - col) * (line * 0.55)[..., None]
    c.put(m, col, rough=0.06, metal=0.0, glow=line * glow)


def shagreen(c, m, color, freq=150, seed=0):
    """Stingray shagreen: tightly packed small round glassy beads (Tidal's sea-foam wrap)."""
    f1, f2, cid = worley(c, freq, seed, jitter=0.6)
    bead = np.clip(1 - f1 / 0.46, 0, 1) ** 0.6
    col = rgb(color) * (0.7 + 0.35 * bead + 0.06 * (cid - 0.5))[..., None]
    c.put(m, col, rough=0.5 - 0.3 * bead, metal=0.0)
    c.add_height(m, 0.00045 * bead - 0.0002)


@recipe
def candy(k):
    """A red-and-white candy-cane spiral with a sugar-glitter shine from the tip to the ring, a
    steel collar, green / white / red rings, a white sugar-grain wrap, a red sleeve with a
    peppermint pinwheel (red, white and mint) facing each side, a black end."""
    s = k.skin['colours']
    red, white, mint = s['red'], s['white'], s['mint']

    def cane(c, m):
        st = spiral(c, 1.15, n=3, duty=0.5, soft=0.015)
        sparkle = np.clip((noise(c, 1600, 1600, seed=141) - 0.78) * 7, 0, 1)
        col = mix(np.broadcast_to(rgb(white), c.col.shape), np.broadcast_to(rgb(red), c.col.shape), st)
        col = col + (255 - col) * (sparkle * 0.7)[..., None]
        c.put(m, col, rough=0.08 + 0.05 * st, metal=0.0, glow=sparkle * 0.25 * m)
        c.add_height(m, 0.00006 * st)
    for c, m in k.zone('shaft', 'forearm'):
        cane(c, m)
    k.paint(['joint'], metal, s['metal'], rough=0.1)
    for c, m in k.zone('ring'):
        gloss(c, m, white, rough=0.1)
        ring_lines(c, m, [(5.325, 5.35, mint, 'paint'), (5.36, 5.375, red, 'paint'), (5.385, 5.41, mint, 'paint')])
    k.paint(['wrap'], leather, s['wrap'], rough=0.62, depth=0.0006, scale=1.5, contrast=1.3)
    for c, m in k.zone('cap'):
        gloss(c, m, red, rough=0.08, flake=0.4, flake_color='#FFFFFF')
        for i, a in enumerate((math.pi * 3 / 4, math.pi * 7 / 4)):
            along = c.d - 6.8
            around = (np.mod(c.theta - a + math.pi, 2 * math.pi) - math.pi) * c.r
            rr = np.hypot(along, around)
            R = 0.13
            ang = np.arctan2(around, along) + rr / R * 2.2
            sector = np.mod(np.floor(ang / (2 * math.pi / 10)), 2)
            edge = np.abs(np.mod(ang / (2 * math.pi / 10), 1) - 0.5)
            inside = np.clip((R - rr) / 0.004, 0, 1) * m
            col = np.where(sector[..., None] > 0.5, rgb(red), rgb(white))
            col = mix(col, np.broadcast_to(rgb(mint), col.shape), np.clip((edge - 0.44) / 0.06, 0, 1) * 0.8)
            col = col * (1 - 0.18 * (rr / R) ** 2)[..., None]
            c.put(inside, col, rough=0.06)
            c.add_height(inside, 0.00025 * np.clip(1 - rr / R, 0, 1))
        ring_lines(c, m, [(C0, C0 + 0.012, mint, 'paint'), (C0 + 0.016, C0 + 0.024, white, 'paint')])
    end_band(k, d0=6.95)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def plasma(k):
    """Dark gunmetal plates split by glowing violet plasma cracks on the forearm and sleeve, thin
    violet veins through a dark blue-grey shaft, a steel collar, a glowing violet ring, a black
    crosshatch grip, a black end."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        metal(c, m, '#3A3C48', rough=0.32, brushed=False)
        c.col = c.col * 0.7
        f1, f2, _ = worley(c, 9, 151)
        vein = np.clip(1 - (f2 - f1) / 0.035, 0, 1) ** 2 * smooth(0.6, 2.8, c.d) * np.clip((fbm(c, 6, 6, seed=152) - 0.35) * 3, 0, 1) * m
        c.put(vein, rgb(s['violet']) * 1.1, rough=0.4, metal=0.0, glow=vein)
    for c, m in k.zone('forearm', 'cap'):
        crack_plates(c, m, 7, s['gunmetal'], s['violet'], s['pale'], seed=153, metal_=0.55, rough=0.35, live=0.72, width=0.045)
        # finer branching veins inside the plates, like lightning frozen in the metal
        f1, f2, _ = worley(c, 19, 154)
        br = np.clip(1 - (f2 - f1) / 0.05, 0, 1) ** 2 * np.clip((fbm(c, 9, 9, seed=155) - 0.5) * 4, 0, 1) * m
        c.put(br, rgb(s['violet']), glow=br * 0.8)
    k.paint(['joint'], metal, s['metal'], rough=0.12)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.12)
    glow_ring(k, s['glow'], d0=5.35, d1=5.39)
    k.paint(['wrap'], crosshatch, '#16161A', pitch=0.022)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def blaze(k):
    """Charcoal wood like a log in a campfire: charred plates split by glowing orange ember cracks
    on the forearm and sleeve, dark brown wood with a few faint ember cracks warming toward the
    joint on the shaft, a steel collar, a glowing orange ring, a black crosshatch grip."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        wood(c, m, 'rosewood', '#5A3A28', '#1E120C', rough=0.4, seed=161)
        f1, f2, _ = worley(c, 11, 162)
        vein = np.clip(1 - (f2 - f1) / 0.04, 0, 1) ** 2 * smooth(1.4, 3.5, c.d) * np.clip((fbm(c, 6, 6, seed=163) - 0.4) * 3, 0, 1) * m
        c.put(vein, rgb(s['ember']), rough=0.5, glow=vein)
    for c, m in k.zone('forearm', 'cap'):
        crack_plates(c, m, 6.5, s['charcoal'], s['ember'], s['hot'], seed=164, rough=0.72, grain=True, live=0.85, halo=0.32, width=0.075)
    k.paint(['joint'], metal, s['metal'], rough=0.14)
    for c, m in k.zone('ring'):
        metal(c, m, '#3A3A3E', rough=0.2)
    glow_ring(k, s['glow'], d0=5.345, d1=5.4)
    k.paint(['wrap'], crosshatch, '#141212', pitch=0.022)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


def ai_finish(k, panels, rough=0.12, glow=None, height=0.0002, wrap=None, collar=None, ring_glow=None):
    """The common finish of an OpenAI Rare: each panel as colour with roughness, a relief and a
    glow mask from its bright parts (glow = (lo, hi, gamma) of brightness), a crisp metal
    collar, the wrap replaced by a procedural material (wrap = fn(c, m)), a glowing ring."""
    for panel in panels:
        img = ai_base(k, panel, rough=rough, height=height)
        if glow:
            c = k.c[panel]
            c.put(np.ones((c.h, c.w), bool), None, glow=glow_from(img, *glow))
    if collar:
        f = k.c['forearm']
        metal(f, f.zone('joint'), collar, rough=0.1)
        f.put(f.zone('joint'), None, glow=0.0)
    if wrap:
        for c, m in k.zone('wrap'):
            wrap(c, m)
            c.put(m, None, glow=0.0)
    if ring_glow:
        glow_ring(k, ring_glow[0], base=ring_glow[1], d0=5.35, d1=5.395)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)


@recipe
def neon(k):
    """Glossy black with neon tubes (OpenAI forearm and butt: pink circuit lines, cyan diagonals,
    a crosshatch grip crossed by neon bands, a cyan chevron sleeve); a black shaft with a hot-pink
    neon tube along it that jogs sideways before the joint; neon parts glow in the mask."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        gloss(c, m, '#0C0C10', rough=0.07)
        centre = math.pi * 3 / 4 + 0.35 * smooth(3.0, 3.12, c.d)
        tube = stripe_along(c, centre, 0.006) * smooth(0.5, 0.7, c.d) * m
        halo = stripe_along(c, centre, 0.016, soft=0.012) * smooth(0.5, 0.7, c.d) * m
        c.put(halo, rgb(s['pink']) * 0.55, glow=halo * 0.4)
        c.put(tube, mix(np.broadcast_to(rgb(s['pink']), c.col.shape), np.broadcast_to(np.array([255.0, 220, 245]), c.col.shape), 0.5),
              rough=0.1, glow=tube)
    ai_finish(k, ['forearm', 'butt'], rough=0.08, glow=(0.45, 0.8, 1.2), collar=s['metal'])
    b = k.c['butt']
    b.put(b.zone('wrap'), None, rough=0.55)
    end_band(k, d0=6.97)


@recipe
def nature(k):
    """A living-wood cue (all OpenAI): light wood wrapped in spiralling vines with leaves and white
    flowers from the shaft to the sleeve, a moss wrap, green and yellow rings, a steel collar."""
    s = k.skin['colours']
    ai_finish(k, ['shaft_tile', 'shaft_top', 'forearm', 'butt'], rough=0.45, height=0.0005, collar=s['metal'])
    b = k.c['butt']
    b.put(b.zone('wrap'), None, rough=0.8)
    end_band(k, d0=6.97)


@recipe
def frostbite(k):
    """Frosted ice-crystal glass (OpenAI forearm and sleeve: frost feathers, cracks, snowflakes,
    glacier shards; a frosted grey-white wrap); a pale icy shaft with a fine crack network that
    glows faintly; silver collar and ring; the frost glows softly in the mask."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        caustics(c, m, s['ice'], s['frost'], freq=14, seed=171, glow=0.2)
        f1, f2, _ = worley(c, 22, 172)
        crack = np.clip(1 - (f2 - f1) / 0.05, 0, 1) ** 2 * np.clip((fbm(c, 8, 8, seed=173) - 0.35) * 3, 0, 1) * m
        c.put(crack, np.array([245.0, 252, 255]), glow=crack * 0.35)
    ai_finish(k, ['forearm', 'butt'], rough=0.06, glow=(0.86, 1.0, 2.0), collar=s['metal'])
    b = k.c['butt']
    b.put(b.zone('wrap'), None, rough=0.6, glow=0.0)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.1)
        c.put(m, None, glow=0.0)
    end_band(k, d0=6.97)


@recipe
def phantom(k):
    """Ghostly see-through teal glass with spirit wisps and small cartoon ghosts (OpenAI forearm
    and sleeve), a pale pebbled wrap, a milky white-teal shaft with faint glowing wisps swirling
    in it, silver collar; the wisps and ghosts glow softly."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        warp = fbm(c, 5, 1.2, octaves=3, seed=181)
        wisp = np.abs(np.mod(warp * 5 + c.theta / (2 * math.pi) * 2 + c.d * 0.4, 1.0) - 0.5)
        wisp = (1 - smooth(0.0, 0.08, wisp)) * (0.3 + 0.7 * fbm(c, 20, 4, octaves=2, seed=182))
        base = mix(np.broadcast_to(rgb(s['deep']), c.col.shape), np.broadcast_to(rgb(s['milk']), c.col.shape),
                   np.clip(0.55 + 0.4 * fbm(c, 6, 2, octaves=2, seed=183), 0, 1))
        c.put(m, base, rough=0.06, metal=0.0)
        c.put(wisp * m, np.broadcast_to(rgb(s['wisp']), c.col.shape), glow=wisp * 0.6 * m)
    ai_finish(k, ['forearm', 'butt'], rough=0.06, glow=(0.62, 0.95, 1.3), collar=s['metal'],
              wrap=lambda c, m: leather(c, m, s['wrap'], rough=0.55, depth=0.0008, scale=2.2, contrast=1.3))
    end_band(k, d0=6.97)


@recipe
def tidal(k):
    """Deep ocean blue water with teal caustics (OpenAI forearm with a pearl and a silver wave
    line; sleeve with a breaking wave), a sea-foam stingray-bead wrap, a deep-blue-to-teal
    caustic shaft, silver collar; the caustics glow faintly."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        caustics(c, m, s['deep'], s['teal'], freq=16, seed=191, glow=0.25)
        c.col = mix(c.col, c.col * np.array([0.7, 1.05, 1.1]), smooth(0.5, 3.5, c.d)[..., None] * 0.6)
    ai_finish(k, ['forearm', 'butt'], rough=0.06, glow=(0.72, 0.95, 1.5), collar=s['metal'],
              wrap=lambda c, m: shagreen(c, m, s['foam'], seed=192))
    for panel in ('forearm', 'butt'):
        # the white pearl and wave line get a pearl's soft iridescent lustre
        c = k.c[panel]
        white = np.clip((luma(c.col) - 0.85) / 0.08, 0, 1) * ~c.zone('joint') * ~c.zone('wrap', 'ring')
        keep = c.glow.copy()
        pearl(c, white > 0.5, '#F2F7F7', rough=0.12, fire=0.45)
        c.glow = keep
    end_band(k, d0=6.97)


@recipe
def sakura(k):
    """Black lacquer painted with gold-outlined cherry branches and pink blossoms from the shaft to
    the sleeve (OpenAI), the gold real metal in the maps, a pink pebbled silk-leather wrap, gold
    collar and rings; the blossoms glow very softly."""
    s = k.skin['colours']
    for panel in ('shaft_tile', 'shaft_top', 'forearm', 'butt'):
        img = ai_base(k, panel, rough=0.07, height=0.00015)
        c = k.c[panel]
        g = hue_mask(img, s['gold'], tol=70, min_sat=0.3)
        pink = hue_mask(img, s['pink'], tol=70, min_sat=0.2)
        c.put(g, None, rough=0.22, metal=1.0)
        c.put(np.ones((c.h, c.w), bool), None, glow=pink * 0.3)
        c.add_height(g + pink, 0.00012)
    f = k.c['forearm']
    metal(f, f.zone('joint'), s['gold'], rough=0.15)
    for c, m in k.zone('wrap'):
        leather(c, m, s['wrap'], rough=0.5, depth=0.0007, scale=2.0, contrast=1.2, sheen=0.3)
        c.put(m, None, glow=0.0)
    for c, m in k.zone('ring'):
        metal(c, m, s['gold'], rough=0.15)
        c.put(m, None, glow=0.0)
    for c, m in k.zone('cap'):
        ring_lines(c, m, [(C0, C0 + 0.02, s['gold'], 'metal')])
    end_band(k, d0=6.97)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101010')
    joint_seam(k)


# ---------------------------------------------------------------------------------------------
# Epics: shared painters
# ---------------------------------------------------------------------------------------------

FACE = math.pi * 5 / 4  # the side a camera above and to the side sees (sheets, the back): inlays centre here


def around_of(c, theta0):
    """Signed arc length (studs) round the cue from the angle theta0."""
    return (np.mod(c.theta - theta0 + math.pi, 2 * math.pi) - math.pi) * c.r


def scales(c, m, color, size=0.028, rough=0.45, depth=0.0005, seed=0, sheen=0.25, edge_col=None):
    """Snakeskin: rows of overlapping rounded scales round the cue (a whole number per row), each
    row offset by half a scale and lying over the row before it (toward the tip), every scale
    domed with a darker free edge and a soft sheen on its crown; a little tone change per scale."""
    n_round = max(8, int(round(float(np.mean(2 * math.pi * c.r)) / size)))
    a = c.d / (size * 0.62)
    b = c.theta / (2 * math.pi) * n_round
    i0 = np.floor(a)
    R = 0.72
    best_row = np.full(a.shape, -1e9)
    best_dist = np.ones(a.shape)
    best_id = np.zeros(a.shape)
    for di in (0, -1, 1):
        row = i0 + di
        off = 0.5 * np.mod(row, 2)
        j = np.floor(b - off + 0.5)
        for dj in (-1, 0, 1):
            jj = j + dj
            du = (a - (row + 0.5)) / 1.0
            dv = (b - (jj + off))
            dist = np.hypot(du * 1.15, dv) / R
            cover = (dist < 1) & (row > best_row)
            best_row = np.where(cover, row, best_row)
            best_dist = np.where(cover, dist, best_dist)
            best_id = np.where(cover, cc._hash3(row.astype(np.int64), np.mod(jj, n_round).astype(np.int64),
                                                 np.zeros_like(row, np.int64), seed), best_id)
    dome = np.sqrt(np.clip(1 - best_dist ** 2, 0, 1))
    rim = np.clip((best_dist - 0.78) / 0.22, 0, 1)
    base = rgb(color)
    tone = 0.82 + 0.12 * (best_id - 0.5) + 0.22 * dome - 0.45 * rim
    col = base[None, None] * tone[..., None] + sheen * 40 * (dome ** 4)[..., None]
    if edge_col is not None:
        col = mix(col, np.broadcast_to(rgb(edge_col), col.shape), rim * 0.6)
    c.put(m, col, rough=rough + 0.15 * rim - 0.1 * dome, metal=0.0)
    h = depth * (dome - 0.6 * rim)
    c.add_height(m, h - h[m].mean() if np.any(m) else h)


def ridged(c, fx, fd, seed=0, octaves=3, warp=None):
    """Ridged noise (1 on the ridge lines): thin wandering filaments."""
    n = fbm(c, fx, fd, octaves=octaves, seed=seed, warp=warp)
    return 1 - np.abs(2 * n - 1)


def starfield(c, m, density=0.86, gold=None, seed=0, glow=0.9, freq=1400):
    """Tiny stars: white (and gold) pin points, a few bigger, glowing."""
    st = np.clip((cc.noise3(c.x * freq, c.d * freq, c.z * freq, seed) - density) * 14, 0, 1)
    big = np.clip((cc.noise3(c.x * freq * 0.45, c.d * freq * 0.45, c.z * freq * 0.45, seed + 1) - (density + 0.06)) * 10, 0, 1)
    st = np.clip(st + big, 0, 1) * m
    col = np.broadcast_to(np.array([240.0, 244, 255]), c.col.shape)
    if gold is not None:
        pick = np.clip((fbm(c, 300, 300, octaves=1, seed=seed + 2) - 0.5) * 8, 0, 1)
        col = mix(col, np.broadcast_to(rgb(gold), c.col.shape), pick)
    c.put(st, col, glow=st * glow)
    return st


def lava_rock(c, m, freq, s, seed=0, live=0.85, width=0.09, halo=0.45, dome=0.0009):
    """Black volcanic rock split into domed, pitted plates by molten cracks: the cracks glow
    yellow-white at the core, orange, then red at the edge, with a hot halo on the rock beside
    them; some cracks have cooled dark."""
    wob = (fbm(c, freq * 2, freq * 2, octaves=2, seed=seed + 1) - 0.5) * 0.55 / freq
    view = type('V', (), {})()
    view.x, view.d, view.z = c.x + wob, c.d + wob, c.z - wob
    f1, f2, cid = worley(view, freq, seed, jitter=0.95)
    edge = f2 - f1
    alive = np.clip((fbm(c, freq * 0.7, freq * 0.7, octaves=2, seed=seed + 2) - (1 - live)) * 4, 0, 1)
    w = width * (0.55 + 0.9 * fbm(c, freq * 3, freq * 3, octaves=2, seed=seed + 3))
    core = np.clip(1 - edge / w, 0, 1)
    heat = 0.35 + 0.65 * np.clip((fbm(c, freq * 1.6, freq * 1.6, octaves=3, seed=seed + 4) - 0.3) * 2.2, 0, 1)  # hotter and cooler runs
    hot = core ** 1.3 * alive * heat
    hal = np.exp(-(edge / (w * 1.4)) ** 2) * alive * halo * heat
    domed = np.clip(edge / 0.35, 0, 1) ** 0.6
    g1, _, _ = worley(c, freq * 7, seed + 7)
    pit = np.clip(1 - g1 / 0.32, 0, 1) ** 2 * (fbm(c, freq * 2, freq * 2, octaves=2, seed=seed + 8) > 0.45)
    grain = fbm(c, freq * 14, freq * 14, octaves=3, seed=seed + 9)
    ao = 0.3 + 0.7 * domed  # the lumps' own shading: dark in the seams, lit on the crowns
    rock = rgb(s['rock']) * ((0.6 + 0.3 * cid + 0.5 * (grain - 0.5) - 0.3 * pit) * ao)[..., None]
    rock = rock + np.array([14.0, 12, 12]) * (domed ** 5)[..., None]
    lo, mid, hi = rgb(s['red']), rgb(s['lava']), rgb(s['hot'])
    lava = mix(np.broadcast_to(lo, c.col.shape), np.broadcast_to(mid, c.col.shape), np.clip(core * 2.2 * heat, 0, 1))
    lava = mix(lava, np.broadcast_to(hi, c.col.shape), np.clip((core * 2.2 - 1.1) * heat ** 2, 0, 1))
    col = mix(rock, np.broadcast_to(lo * 0.9, c.col.shape), hal * 0.5)
    col = mix(col, lava, np.clip(hot * 1.8, 0, 1))
    dark = np.clip(1 - edge / (w * 0.8), 0, 1) * (1 - alive)
    col = col * (1 - 0.75 * dark)[..., None]
    c.put(m, col, rough=np.clip(0.58 - 0.18 * domed + 0.15 * pit - 0.25 * hot, 0.2, 1), metal=0.0,
          glow=np.clip(hot * 1.2 + hal * 0.5, 0, 1))
    c.add_height(m, dome * domed - 0.0002 * pit - 0.0004 * np.clip(1 - edge / 0.1, 0, 1))


def goo_glass(c, m, s, seed=0, big=16, small=42, glow=0.75, warp_amt=1.0):
    """Acid-green radioactive goo seen through glass: a swirling bright-to-deep green body lit
    from inside, full of round bubbles (a bright rim, a clear middle, a glint), glossy."""
    sw = fbm(c, 9, 4, octaves=3, seed=seed)
    flow = fbm(c, 22, 8, octaves=3, seed=seed + 1, warp=((sw - 0.5) * 3 * warp_amt, (sw - 0.5) * 2, (sw - 0.5) * 3))
    deep, acid, lime = rgb(s['deep']), rgb(s['acid']), rgb(s['lime'])
    body = mix(np.broadcast_to(deep, c.col.shape), np.broadcast_to(acid, c.col.shape), np.clip(flow * 1.5 - 0.15, 0, 1)[..., None] * np.ones(3))
    body = mix(body, np.broadcast_to(lime, c.col.shape), np.clip(flow * 2 - 1.2, 0, 1))
    body = body * (0.35 + 0.75 * np.clip(flow * 1.6 - 0.3, 0, 1))[..., None]  # dark glass where the goo thins
    g = np.clip(flow * 1.9 - 0.55, 0.04, 1)
    c.put(m, body, rough=0.04, metal=0.0, glow=g * glow * m)
    total = np.zeros(c.d.shape)
    for freq, cover, sd in ((big, 0.35, seed + 3), (small, 0.5, seed + 5)):
        f1, _, cid = worley(c, freq, sd, jitter=0.8)
        rad = 0.26 + 0.2 * np.mod(cid * 7.7, 1)
        dd = f1 / rad
        on = (cid < cover) * m
        inside = np.clip((1 - dd) * 12, 0, 1) * on
        rim = np.exp(-((dd - 0.88) / 0.1) ** 2) * on
        glint = np.exp(-((dd - 0.5) / 0.12) ** 2) * np.clip(-np.cos(c.theta - math.pi) * 0 + 1, 0, 1) * on * 0.0
        bub = mix(body, np.broadcast_to(acid * 0.9, c.col.shape), 0.55) * (0.75 + 0.35 * np.clip(dd, 0, 1))[..., None]
        c.put(inside, bub, glow=np.maximum(c.glow, inside * glow * 0.55))
        c.put(rim, np.broadcast_to(np.array([235.0, 255, 190]), c.col.shape), glow=np.maximum(c.glow, rim))
        total = np.clip(total + inside, 0, 1)
    return total


def hazard(c, m, yellow, black='#0C0C0C', pitch=0.075, slant=1.0):
    """Black-and-yellow hazard stripes slanting round the cue (studs pitch), glossy paint."""
    f = np.mod((c.d + around_of(c, math.pi) * slant) / pitch, 1)
    y = smooth(0.02, 0.06, f) * (1 - smooth(0.48, 0.52, f))
    col = mix(np.broadcast_to(rgb(black), c.col.shape), np.broadcast_to(rgb(yellow), c.col.shape), y)
    c.put(m, col, rough=0.1, metal=0.0, glow=0.0)
    c.add_height(m, 0.00006 * y)
    return y


def red_mist(c, m, s, seed=0, amount=1.0, fd=None):
    """Crimson smoke drifting in black lacquer: soft clouds with bright curling filaments."""
    fd = fd or 5
    w0 = fbm(c, 6, fd * 0.5, octaves=3, seed=seed)
    warp = ((w0 - 0.5) * 2.5, (w0 - 0.5) * 1.5, (w0 - 0.5) * 2.5)
    cloud = fbm(c, 8, fd, octaves=5, seed=seed + 1, warp=warp)
    fil = ridged(c, 10, fd * 1.3, seed=seed + 2, octaves=4, warp=warp) ** 6
    cl = np.clip((cloud - 0.5) * 2.6, 0, 1) ** 1.3 * amount
    fl = np.clip((fil - 0.25) * 1.6 * (0.15 + cl), 0, 1) * amount
    dark, red, bright = rgb(s['black']), rgb(s['crimson']), rgb(s['bright'])
    col = mix(np.broadcast_to(dark, c.col.shape), np.broadcast_to(red * 0.45, c.col.shape), cl)
    col = mix(col, np.broadcast_to(bright, c.col.shape), fl)
    c.put(m, col, rough=0.08, metal=0.0, glow=np.clip(fl * 0.85 + cl * 0.12, 0, 1) * m)


def moon(c, m, d0, theta0, radius, s, seed=0):
    """A red full moon: a disc with darker maria and small craters, brighter at the limb, with a
    soft red glow round it."""
    along = c.d - d0
    around = around_of(c, theta0)
    rr = np.hypot(along, around) / radius
    disc = np.clip((1 - rr) * radius / 0.002, 0, 1) * m
    view = type('V', (), {})()
    view.x, view.d, view.z = along / radius, around / radius + 3, np.zeros_like(along)
    maria = cc.fbm(view.x * 2.2, view.d * 2.2, view.z, 4, seed)
    f1, _, cid = worley(view, 5, seed + 1)
    crater = np.exp(-((f1 - 0.25) / 0.06) ** 2) * (cid < 0.5) * 0.6
    pit = np.clip(1 - f1 / 0.22, 0, 1) * (cid < 0.5)
    red, bright = rgb(s['crimson']), rgb(s['bright'])
    col = mix(np.broadcast_to(red * 0.7, c.col.shape), np.broadcast_to(bright, c.col.shape), np.clip(0.75 - maria * 0.9 + crater * 0.4, 0, 1))
    col = col * (1 - 0.55 * np.clip(maria - 0.42, 0, 1) * 2.5 - 0.3 * pit)[..., None]
    limb = np.clip((rr - 0.8) / 0.2, 0, 1) * (rr < 1)
    col = col + (255 - col) * (limb * 0.25)[..., None]
    c.put(disc, col, rough=0.3, glow=disc * (0.45 + 0.35 * limb))
    halo = np.exp(-((rr - 1.0) / 0.25) ** 2) * (rr > 1) * m
    c.put(halo * 0.6, np.broadcast_to(red, c.col.shape), glow=halo * 0.55)
    c.add_height(disc, 0.0002 - 0.0001 * crater)


def crystal_facets(c, m, s, size=0.03, seed=0, glow=0.35):
    """Cut crystal: a triangle lattice of flat facets wrapped round the cue, each facet a
    different pale brightness (what it reflects) with a faint rainbow fire, bright facet edges."""
    n_round = max(6, int(round(float(np.mean(2 * math.pi * c.r)) / size)))
    b = c.theta / (2 * math.pi) * n_round
    a = c.d / (size * 0.866)
    i = np.floor(a)
    fb = b + 0.5 * np.mod(i, 2)
    j = np.floor(fb)
    fa, fbb = a - i, fb - j
    upper = (fbb > fa * 0.5) & (fbb < 1 - fa * 0.5)
    tri = np.where(upper, 0, np.where(fbb <= fa * 0.5, 1, 2))
    fid = cc._hash3(i.astype(np.int64), np.mod(j, n_round).astype(np.int64), tri.astype(np.int64), seed)
    # distance to the facet's edges (lattice units)
    e1 = np.abs(fbb - fa * 0.5)
    e2 = np.abs(1 - fbb - fa * 0.5)
    e3 = np.minimum(fa, 1 - fa)
    edge = np.minimum(np.minimum(e1, e2), e3)
    edge_line = np.clip(1 - edge / 0.05, 0, 1)
    pale, ice, deep = rgb(s['clear']), rgb(s['ice']), rgb(s['deep'])
    col = mix(np.broadcast_to(deep, c.col.shape), np.broadcast_to(ice, c.col.shape), np.clip(fid * 2.2, 0, 1))
    col = mix(col, np.broadcast_to(pale, c.col.shape), np.clip(fid * 2.2 - 1.2, 0, 1))
    hue = np.mod(fid * 5.3, 1)
    rainbow = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (hue + k / 3)) for k in range(3)], -1) * 255
    fire = np.clip((np.mod(fid * 11.7, 1) - 0.8) * 5, 0, 1)
    col = mix(col, rainbow * 0.45 + col * 0.55, fire * 0.6)
    col = col + (255 - col) * (edge_line * 0.75)[..., None]
    col = np.clip(col, 0, 255)
    spark = np.clip((fid - 0.93) * 14, 0, 1) * np.clip(1 - edge / 0.25, 0, 1)
    c.put(m, col, rough=0.03, metal=0.15, glow=np.clip(edge_line * 0.6 + fire * 0.35 + spark, 0, 1) * glow * m)
    c.add_height(m, 0.00012 * (np.clip(edge / 0.3, 0, 1) - 0.5))


def gem_lattice(c, m, s, d0, d1, n=2, phase=FACE, seed=0, frame=None, glow=0.5, cell=0.42):
    """Silver bars crossing round the cue in two helices, leaving diamond windows between them;
    each window holds a faceted gem (facets fanning from its centre, a star glint in the middle,
    rainbow fire on some facets)."""
    L = d1 - d0
    u = (c.d - d0) / (L / max(1, round(L / cell)))  # whole diamonds along the section
    v = (c.theta - phase) / (2 * math.pi) * n  # windows round the cue
    # two helices, each turning once round per window over the section: diamonds in between
    p1 = u + v
    p2 = u - v
    e1 = np.abs(np.mod(p1 + 0.5, 1) - 0.5)
    e2 = np.abs(np.mod(p2 + 0.5, 1) - 0.5)
    bar_w = 0.06
    bar = np.clip(1 - np.minimum(e1, e2) / bar_w, 0, 1)
    barm = smooth(0.25, 0.45, bar) * m
    # the window's local coords: centre where p1 and p2 are both whole + 0.5
    cp1 = np.floor(p1) + 0.5
    cp2 = np.floor(p2) + 0.5
    lx = p1 - cp1  # -0.5..0.5
    ly = p2 - cp2
    ang = np.arctan2(ly, lx)
    rad = np.maximum(np.abs(lx), np.abs(ly)) * 2  # 0 centre, 1 at the bars
    facet = np.floor((ang + math.pi) / (2 * math.pi) * 8)
    wid = cc._hash3(cp1.astype(np.int64) * 7, cp2.astype(np.int64) * 13, facet.astype(np.int64), seed)
    ring2 = rad > 0.55
    fid = np.where(ring2, np.mod(wid * 3.1 + 0.37, 1), wid)
    pale, ice, deep = rgb(s['clear']), rgb(s['ice']), rgb(s['deep'])
    col = mix(np.broadcast_to(deep, c.col.shape), np.broadcast_to(ice, c.col.shape), np.clip(fid * 2.0, 0, 1))
    col = mix(col, np.broadcast_to(pale, c.col.shape), np.clip(fid * 2.0 - 1.0, 0, 1))
    hue = np.mod(fid * 4.1, 1)
    rainbow = np.stack([0.5 + 0.5 * np.cos(2 * math.pi * (hue + k / 3)) for k in range(3)], -1) * 255
    fire = np.clip((np.mod(fid * 9.3, 1) - 0.72) * 3.5, 0, 1)
    col = mix(col, rainbow * 0.45 + col * 0.55, fire * 0.7)
    fe = np.abs(np.mod((ang + math.pi) / (2 * math.pi) * 8, 1) - 0.5)
    edge = np.clip(1 - (0.5 - fe) * rad * 10, 0, 1) + np.exp(-((rad - 0.55) / 0.03) ** 2)
    col = col + (255 - col) * (np.clip(edge, 0, 1) * 0.6)[..., None]
    starg = np.exp(-(rad / 0.12) ** 2) + 0.7 * np.exp(-((np.abs(lx) + 0.0) / 0.012) ** 2) * np.exp(-(rad / 0.5) ** 2) \
        + 0.7 * np.exp(-((np.abs(ly)) / 0.012) ** 2) * np.exp(-(rad / 0.5) ** 2)
    col = col + (255 - col) * np.clip(starg, 0, 1)[..., None]
    win = m * (1 - barm)
    c.put(win, np.clip(col, 0, 255), rough=0.02, metal=0.1,
          glow=np.clip(fire * 0.5 + np.clip(edge, 0, 1) * 0.35 + np.clip(starg, 0, 1), 0, 1) * glow * win)
    c.add_height(win, 0.0003 * (1 - rad))
    metal(c, barm > 0.5, frame or s['metal'], rough=0.3, brushed=False)
    c.put(barm, None, glow=0.0)
    c.add_height(barm, 0.0005 * barm)


def aurora_ribbons(c, m, s, seed=0, freq=1.0, glow=0.9, density=1.0):
    """Aurora ribbons flowing along the cue in the dark: warped bands winding diagonally round
    it, green to teal to violet along their length, with fine bright curtain streaks inside, and
    faint stars behind."""
    w0 = fbm(c, 5 * freq, 1.2 * freq, octaves=3, seed=seed)
    w1 = fbm(c, 7 * freq, 2.0 * freq, octaves=3, seed=seed + 1)
    ph = c.d * 1.3 * freq + c.theta / (2 * math.pi) * 2 + (w0 - 0.5) * 1.3
    band1 = np.exp(-((np.mod(ph, 1) - 0.5) / (0.1 + 0.07 * w1)) ** 2)
    ph2 = c.d * 1.1 * freq + c.theta / (2 * math.pi) * 1 + (w1 - 0.5) * 1.1 + 0.37
    band2 = np.exp(-((np.mod(ph2, 1) - 0.5) / (0.07 + 0.05 * w0)) ** 2) * 0.8
    bands = np.clip(band1 + band2, 0, 1)
    # fine silky streaks running with the ribbons (a ridged noise stretched along their slant)
    sv = type('V', (), {})()
    sv.x, sv.z = c.x, c.z
    sv.d = c.d + (w0 - 0.5) * 0.15
    streak = ridged(sv, 70 * freq, 4 * freq, seed=seed + 2, octaves=2) ** 4
    inten = np.clip(bands * (0.55 + 0.6 * streak) * (0.4 + 0.9 * fbm(c, 4, 3, octaves=2, seed=seed + 3)), 0, 1) * density
    hue = fbm(c, 3, 1.1, octaves=2, seed=seed + 4)
    green, teal, violet, blue = rgb(s['green']), rgb(s['teal']), rgb(s['violet']), rgb(s['blue'])
    t = np.clip((hue - 0.3) * 2.5, 0, 1)
    col_a = mix(np.broadcast_to(green, c.col.shape), np.broadcast_to(blue, c.col.shape), np.clip(t * 2, 0, 1))
    col_b = mix(col_a, np.broadcast_to(violet, c.col.shape), np.clip(t * 2 - 1, 0, 1))
    base = rgb(s['night'])
    col = mix(np.broadcast_to(base, c.col.shape), col_b, np.clip(inten * 1.3, 0, 1))
    core = np.clip(inten * 1.6 - 1.0, 0, 1)
    col = col + (255 - col) * (core * 0.5)[..., None]
    c.put(m, col, rough=0.07, metal=0.0, glow=np.clip(inten * glow, 0, 1) * m)
    starfield(c, m * (inten < 0.2), density=0.88, seed=seed + 5, glow=0.6)


def mirror_tiles(c, m, s, size=0.03, seed=0, lit=0.35, glow=0.9):
    """A mirror ball: small square mirror tiles in rows round the cue (a whole number per row),
    each a slightly different silver (each catches a different reflection), parted by dark grout;
    clumps of tiles lit by coloured spotlights glow pink, cyan, yellow or blue."""
    n_round = max(8, int(round(float(np.mean(2 * math.pi * c.r)) / size)))
    a = c.d / size
    b = c.theta / (2 * math.pi) * n_round
    i, j = np.floor(a), np.floor(b)
    ii, jj = i.astype(np.int64), np.mod(j, n_round).astype(np.int64)
    h1 = cc._hash3(ii, jj, np.zeros_like(ii), seed)
    h2 = cc._hash3(ii, jj, np.ones_like(ii), seed + 1)
    fa, fb = a - i, b - j
    edge = np.minimum(np.minimum(fa, 1 - fa), np.minimum(fb, 1 - fb))
    grout = 1 - smooth(0.03, 0.08, edge)
    # a tilt: each tile is brighter toward one corner (a flat mirror at its own angle)
    tilt = (fa - 0.5) * (h2 - 0.5) * 0.6 + (fb - 0.5) * (np.mod(h2 * 7, 1) - 0.5) * 0.6
    silver = (110 + 145 * np.clip(h1 ** 1.2 + tilt, 0, 1))
    col = np.stack([silver * 0.97, silver * 0.99, silver], -1)
    # coloured spot clumps (the clump field is sampled per tile)
    ang = (j + 0.5) / n_round * 2 * math.pi
    rr = float(np.mean(c.r))
    fld = cc.fbm(rr * np.sin(ang) * 14, (i + 0.5) * size * 14, -rr * np.cos(ang) * 14, 3, seed + 2)
    on = np.clip((fld - (0.72 - 0.5 * lit)) * 7, 0, 1) * (h1 > 0.2)
    pal = np.array([rgb(x) for x in s['spots']])
    blk = cc._hash3((ii // 5), (jj // 4), np.zeros_like(ii), seed + 3)  # a colour per clump-sized block
    pick = np.minimum((blk * len(pal)).astype(int), len(pal) - 1)
    spot = pal[pick]
    spot_col = spot + (255 - spot) * (0.05 + 0.3 * h1 ** 3)[..., None]
    col = mix(col, spot_col, on)
    col = col * (1 - 0.85 * grout)[..., None]
    catch = np.clip((np.mod(h2 * 17.3, 1) - 0.9) * 10, 0, 1) * (1 - on)  # a tile catching a light: a white reflection
    col = col + (255 - col) * (catch * 0.8)[..., None]
    c.put(m, col, rough=0.14 + 0.4 * grout, metal=0.55 * (1 - on) * (1 - grout),
          glow=np.clip(on * (0.7 + 0.3 * h1) + catch * 0.6, 0, 1) * glow * (1 - grout) * m)
    c.add_height(m, 0.00018 * (1 - grout) + 0.00006 * tilt)
    return on


GLYPHS = {  # 3 x 5 pixel glyphs, rows top to bottom
    '0': ['111', '101', '101', '101', '111'],
    '1': ['010', '110', '010', '010', '111'],
    'a': ['111', '100', '111', '001', '111'],
    'b': ['101', '111', '101', '111', '101'],
    'c': ['110', '001', '011', '100', '011'],
    'd': ['111', '010', '111', '010', '111'],
    'e': ['100', '111', '101', '111', '001'],
}


def code_glyphs(c, m, s, cell_along=0.026, cell_round=0.036, density=0.75, seed=0, glow=1.0, columns=False):
    """Glowing green 8-bit code: blocky 3x5 pixel glyphs (mostly 0 and 1, some odd symbols)
    set upright in rows along the cue (a whole number of rows round it), some cells empty in
    runs, each glyph its own brightness with a few white-hot ones, on glossy black."""
    n_round = max(4, int(round(float(np.mean(2 * math.pi * c.r)) / cell_round)))
    a = c.d / cell_along
    b = c.theta / (2 * math.pi) * n_round
    i, j = np.floor(a), np.floor(b)
    ii, jj = i.astype(np.int64), np.mod(j, n_round).astype(np.int64)
    h1 = cc._hash3(ii, jj, np.zeros_like(ii), seed)
    h2 = cc._hash3(ii, jj, np.ones_like(ii), seed + 1)
    h3 = cc._hash3(ii // 5, jj, np.zeros_like(ii), seed + 2)  # runs along a row
    on = (h1 < density) & (h3 < 0.8)
    keys = list(GLYPHS)
    weights = np.array([0.38, 0.38, 0.05, 0.05, 0.05, 0.05, 0.04])
    cum = np.cumsum(weights)
    gi = np.searchsorted(cum, h2 * cum[-1])
    # pixel inside the cell: 3 wide along (with a 1-pixel gap), 5 tall round (with a gap)
    fa, fb = a - i, b - j
    px = np.floor(fa * 4.0)
    py = np.floor(fb * 6.0 - 0.5)  # 0..4 are the glyph rows, top first (image-up is up on the facing side)
    lit = np.zeros(a.shape, bool)
    for g, key in enumerate(keys):
        rows = GLYPHS[key]
        bits = np.array([[r[k] == '1' for k in range(3)] for r in rows])
        sel = (gi == g)
        inside = sel & (px >= 0) & (px < 3) & (py >= 0) & (py < 5)
        pyc, pxc = np.clip(py, 0, 4).astype(int), np.clip(px, 0, 2).astype(int)
        lit |= inside & bits[pyc, pxc]
    lit = lit & on & (m > 0)
    # soft pixel edges (a pixel glows a little past itself)
    sa, sb = np.mod(fa * 4.0, 1), np.mod(fb * 6.0 - 0.5, 1)
    pedge = np.minimum(np.minimum(sa, 1 - sa), np.minimum(sb, 1 - sb))
    shape = lit * (0.75 + 0.25 * smooth(0.0, 0.2, pedge))
    br = 0.35 + 0.65 * np.mod(h1 * 13.3 + h2 * 3.1, 1) ** 0.7
    head = (np.mod(h2 * 29.7, 1) > 0.94)
    col = mix(np.broadcast_to(rgb(s['dim']), c.col.shape), np.broadcast_to(rgb(s['code']), c.col.shape), np.clip(br * 1.3, 0, 1))
    col = mix(col, np.broadcast_to(np.array([215.0, 255, 220]), c.col.shape), head * 0.8)
    c.put(shape, col, rough=0.12, glow=shape * np.clip(br + head, 0, 1) * glow)
    c.add_height(shape, 0.00005)
    return shape


# ---------------------------------------------------------------------------------------------
# Epic recipes
# ---------------------------------------------------------------------------------------------

@recipe
def shooting_star(k):
    """Midnight navy with a drifting starfield: a starry navy shaft with gold swooshes before the
    joint; the forearm and sleeve (OpenAI) each with a gold four-point star and gold arcs; a navy
    snakeskin wrap, gold ring lines, a silver collar. Stars and gold glow softly."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        gloss(c, m, s['navy'], rough=0.08, flake=0.18, flake_color='#3A4A9A')
        neb = np.clip((fbm(c, 5, 1.4, octaves=4, seed=201) - 0.5) * 2.2, 0, 1) * smooth(0.5, 3.4, c.d)
        c.put(neb * 0.5 * m, np.broadcast_to(rgb('#2A3C8C'), c.col.shape), glow=neb * 0.15 * m)
        starfield(c, m, density=0.87 - 0.03 * smooth(0.5, 3.5, c.d), gold=s['gold'], seed=202, glow=0.9, freq=900)
        # two gold swooshes sweeping into the joint
        for ph, amp in ((FACE, 0.9), (FACE - math.pi, 0.9)):
            t = np.clip((c.d - 2.85) / 0.75, 0, 1)
            centre = ph + amp * (1 - t) ** 1.6 - 0.2
            dist = angle_diff(c.theta, centre) * c.r
            wdt = 0.0012 + 0.0045 * t ** 1.5
            line = (1 - smooth(wdt, wdt + 0.0012, dist)) * (c.d > 2.85) * m
            c.put(line, rgb(s['gold']), rough=0.2, metal=1.0, glow=line * 0.5)
            c.add_height(line, 0.00008)
    for panel in ('forearm', 'butt'):
        img = ai_base(k, panel, rough=0.08, height=0.00012)
        c = k.c[panel]
        g = hue_mask(img, s['gold'], tol=80, min_sat=0.3)
        c.put(g, None, rough=0.18, metal=1.0)
        c.put(np.ones((c.h, c.w), bool), None, glow=np.clip(g * 0.55 + glow_from(img, 0.8, 1.0, 1.5) * 0.8, 0, 1))
        c.add_height(g, 0.00015)
    f = k.c['forearm']
    metal(f, f.zone('joint'), s['metal'], rough=0.12)
    f.put(f.zone('joint'), None, glow=0.0)
    for c, m in k.zone('wrap'):
        scales(c, m, s['wrap'], size=0.032, rough=0.35, depth=0.0009, seed=203, sheen=0.7, edge_col='#070B20')
        c.put(m, None, glow=0.0)
    for c, m in k.zone('ring'):
        gloss(c, m, s['navy'], rough=0.1)
        ring_lines(c, m, [(5.33, 5.345, s['gold'], 'metal'), (5.4, 5.415, s['gold'], 'metal')])
        c.put(m, None, glow=0.0)
    end_band(k, d0=6.97)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0A0C14')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def magma(k):
    """Black volcanic rock with molten lava in its cracks, cue-long: domed, pitted rock plates
    split by glowing yellow-orange cracks (smaller toward the tip), a rocky wrap with only a few
    live cracks, a glowing red ring between red bands, a silver collar."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        freq = 15 - 3 * smooth(0.5, 3.5, c.d)
        lava_rock(c, m * (c.d < 1.6), 16, s, seed=211, live=0.3, width=0.07, dome=0.0005)
        lava_rock(c, m * (c.d >= 1.6), 12, s, seed=212, live=0.55, width=0.09, dome=0.0007)
    for c, m in k.zone('forearm', 'cap'):
        lava_rock(c, m, 8, s, seed=213, live=0.9, width=0.12, halo=0.55, dome=0.001)
    for c, m in k.zone('wrap'):
        lava_rock(c, m, 14, s, seed=214, live=0.4, width=0.07, halo=0.35, dome=0.001)
    k.paint(['joint'], metal, s['metal'], rough=0.14)
    for c, m in k.zone('ring'):
        gloss(c, m, '#1A0A06', rough=0.2)
        c.put(m, None, glow=0.0)
    glow_ring(k, s['lava'], d0=5.35, d1=5.395)
    for c, m in k.zone('ring'):
        ring_lines(c, m, [(5.325, 5.34, s['red'], 'paint'), (5.405, 5.42, s['red'], 'paint')])
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#100C0A')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0])


@recipe
def toxic(k):
    """Acid-green radioactive goo bubbling in a glass shaft; black-and-yellow hazard stripes
    slanting over the forearm's front half before the goo shows through; a black snakeskin wrap
    crossed by two yellow hazard bands; a glowing yellow ring; the sleeve a goo-filled glass
    window between black rims; a silver collar."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        goo_glass(c, m, s, seed=221, big=14, small=40, glow=0.75)
    for c, m in k.zone('forearm'):
        goo_glass(c, m, s, seed=222, big=10, small=30, glow=0.75)
        # hazard panel from the collar, cut on a slant into the goo, with a black edge
        cut = F0 + 0.62 + 0.12 * np.sin(c.theta * 1.0)
        hz = (c.d < cut) * m
        hazard(c, hz, s['yellow'], pitch=0.09)
        edge = band(c, 0, 1) * (np.abs(c.d - cut) < 0.012) * m
        c.put(edge, rgb('#0A0A0A'), rough=0.1, glow=0.0)
    for c, m in k.zone('wrap'):
        scales(c, m, '#141614', size=0.026, rough=0.35, depth=0.0006, seed=223, sheen=0.3)
        st = spiral(c, 0.55, n=2, duty=0.16, phase=0.1, soft=0.01) * m
        c.put(st, rgb(s['yellow']), rough=0.12, glow=0.0)
        c.add_height(st, 0.0002)
        c.put(m, None, glow=0.0)
    for c, m in k.zone('cap'):
        goo_glass(c, m, s, seed=224, big=9, small=26, glow=0.8)
        for a0, a1 in ((C0, C0 + 0.03), (6.935, 7.2)):
            b_ = band(c, a0, a1) * m > 0.5
            gloss(c, b_, '#0C0C0C', rough=0.08)
            c.put(b_, None, glow=0.0)
    k.paint(['joint'], metal, s['metal'], rough=0.12)
    for c, m in k.zone('ring'):
        gloss(c, m, '#0C0C0C', rough=0.1)
        c.put(m, None, glow=0.0)
    glow_ring(k, s['yellow'], base=None, d0=5.345, d1=5.4)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0E100C')
    rr = c.r / c.face_radius
    ringm = np.exp(-((rr - 0.62) / 0.05) ** 2)
    c.put(ringm, np.broadcast_to(rgb(s['acid']), c.col.shape), glow=ringm)
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, C0 + 0.03, 6.935])


@recipe
def blood_moon(k):
    """Deep crimson and black lacquer with red mist drifting inside: crimson smoke through a
    black shaft (thickening to the joint) and the forearm; a black snakeskin wrap with thin
    glowing red lines curving through it; glowing red rings; the sleeve black with red clouds
    and a red full moon facing each side; a silver collar."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        gloss(c, m, s['black'], rough=0.08)
        amt = 0.25 + 0.75 * smooth(0.4, 3.4, c.d)
        red_mist(c, m, s, seed=231, amount=1.0, fd=2.5)
        c.col = mix(np.broadcast_to(rgb(s['black']), c.col.shape), c.col, amt)
        c.glow = c.glow * amt
    for c, m in k.zone('forearm'):
        red_mist(c, m, s, seed=232, fd=4)
    for c, m in k.zone('cap'):
        red_mist(c, m, s, seed=233, fd=5, amount=0.8)
        for th in (FACE, FACE - math.pi):
            moon(c, m, 6.79, th, 0.108, s, seed=234)
    for c, m in k.zone('wrap'):
        scales(c, m, '#120A0C', size=0.026, rough=0.35, depth=0.0006, seed=235, sheen=0.3)
        for n, (amp, ph, fr) in enumerate(((0.9, 0.0, 1.3), (0.7, 2.0, 1.0), (1.1, 4.1, 0.8))):
            centre = FACE + amp * np.sin(2 * math.pi * fr * (c.d - W0) / (W1 - W0) + ph)
            dist = angle_diff(c.theta, centre) * c.r
            line = (1 - smooth(0.0018, 0.0035, dist)) * m
            c.put(line, rgb(s['bright']), rough=0.2, glow=line * 0.85)
        c.put(m * (c.glow < 0.01), None, glow=0.0)
    k.paint(['joint'], metal, s['metal'], rough=0.12)
    for c, m in k.zone('ring'):
        gloss(c, m, s['black'], rough=0.1)
        c.put(m, None, glow=0.0)
    glow_ring(k, s['crimson'], d0=5.345, d1=5.4)
    for c, m in k.zone('cap'):
        ln = band(c, C0, C0 + 0.012) * m
        c.put(ln, rgb(s['bright']), glow=ln)
    end_band(k, d0=6.96)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0C0406')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def prism(k):
    """A clear faceted crystal cue: a shaft of cut crystal facets with rainbow fire; the forearm
    and sleeve silver lattices holding diamond-cut gems; a pearly white snakeskin wrap; silver
    collar and rings. Facet edges and fire glint in the glow mask."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        crystal_facets(c, m, s, size=0.055, seed=241, glow=0.4)
    for c, m in k.zone('forearm'):
        gem_lattice(c, m, s, F0, F1, n=2, seed=242, glow=0.55, cell=0.75)
    for c, m in k.zone('cap'):
        mm = m * (c.d < 6.95)
        gem_lattice(c, mm > 0.5, s, C0, 6.95, n=2, seed=243, glow=0.55, cell=0.33)
    for c, m in k.zone('wrap'):
        scales(c, m, '#E6EAF0', size=0.026, rough=0.3, depth=0.0005, seed=244, sheen=0.5, edge_col='#B8C4D4')
        c.put(m, None, glow=0.0)
    k.paint(['joint'], metal, s['metal'], rough=0.22)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.22)
        ring_lines(c, m, [(5.335, 5.345, '#2A2E34', 'paint'), (5.4, 5.41, '#2A2E34', 'paint')])
        c.put(m, None, glow=0.0)
    for c, m in k.zone('cap'):
        gloss(c, band(c, 6.95, 7.2) * m > 0.5, '#0C0E12', rough=0.1)
        c.put(band(c, 6.95, 7.2) * m, None, glow=0.0)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#101214')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, 6.95])


@recipe
def aurora(k):
    """A dark night-sky cue with green, teal and violet aurora ribbons flowing along it from the
    shaft through the forearm and sleeve, a black snakeskin wrap, an iridescent glowing ring, a
    silver collar. The ribbons glow."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        gloss(c, m, s['night'], rough=0.07)
        aurora_ribbons(c, m, s, seed=251, freq=0.8, glow=0.85, density=0.5 + 0.5 * smooth(0.3, 2.5, c.d))
    for c, m in k.zone('forearm', 'cap'):
        aurora_ribbons(c, m, s, seed=252, freq=1.2, glow=0.9)
    for c, m in k.zone('wrap'):
        scales(c, m, '#0E1116', size=0.026, rough=0.35, depth=0.0006, seed=253, sheen=0.3)
        c.put(m, None, glow=0.0)
    k.paint(['joint'], metal, s['metal'], rough=0.1)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.1)
        c.put(m, None, glow=0.0)
        rim = band(c, 5.34, 5.405) * m
        hue = np.mod(c.theta / (2 * math.pi) * 2, 1)
        pal = [rgb(s['green']), rgb(s['teal']), rgb(s['violet']), rgb(s['blue'])]
        idx = (hue * 4).astype(int) % 4
        fr = np.mod(hue * 4, 1)[..., None]
        col = np.array(pal)[idx] * (1 - fr) + np.array(pal)[(idx + 1) % 4] * fr
        col = col + (255 - col) * 0.3
        c.put(rim, col, rough=0.15, metal=0.0, glow=rim)
    end_band(k, d0=6.97)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0A0E14')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


@recipe
def disco(k):
    """A mirror ball on a cue: small square mirror tiles from the shaft to the sleeve (smaller on
    the shaft), clumps of them lit pink, cyan, yellow and blue; a black wrap full of multicolour
    glitter; a mirrored glowing ring; a silver collar."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        mirror_tiles(c, m, s, size=0.022, seed=261, lit=0.28)
    for c, m in k.zone('forearm'):
        mirror_tiles(c, m, s, size=0.034, seed=262, lit=0.4)
    for c, m in k.zone('cap'):
        mm = (c.d < 6.95) & m
        mirror_tiles(c, mm, s, size=0.034, seed=263, lit=0.5)
    for c, m in k.zone('wrap'):
        leather(c, m, '#0C0C12', rough=0.45, depth=0.0005, scale=1.6, contrast=1.2)
        pal = [rgb(x) for x in s['spots']] + [np.array([235.0, 235, 245])]
        for i, pc in enumerate(pal):
            gl = np.clip((cc.noise3(c.x * 1300, c.d * 1300, c.z * 1300, 264 + i) - 0.8) * 9, 0, 1) * m
            c.put(gl, pc, rough=0.1, metal=0.3, glow=gl * 0.7)
    k.paint(['joint'], metal, s['metal'], rough=0.2)
    for c, m in k.zone('ring'):
        mirror_tiles(c, m, s, size=0.02, seed=265, lit=0.8)
        ring_lines(c, m, [(5.32, 5.332, s['metal'], 'metal'), (5.413, 5.425, s['metal'], 'metal')])
    for c, m in k.zone('cap'):
        bb = band(c, 6.95, 7.2) * m > 0.5
        gloss(c, bb, '#0C0C10', rough=0.1)
        c.put(bb, None, glow=0.0)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0E0E12')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, 6.95])


@recipe
def hacked(k):
    """A hacker terminal: glossy black with glowing green 8-bit code (blocky 0s, 1s and pixel
    glyphs) sparse along the shaft and packed on the forearm and sleeve; a black snakeskin wrap;
    a glowing green ring; a silver collar."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        gloss(c, m, s['black'], rough=0.06)
        dens = 0.18 + 0.45 * smooth(0.4, 3.3, c.d)
        code_glyphs(c, m * (c.d > 0.35), s, cell_along=0.036, cell_round=0.05, density=0.4, seed=271)
        c.col = mix(np.broadcast_to(rgb(s['black']), c.col.shape), c.col, np.clip(dens * 1.6, 0, 1))
        c.glow = c.glow * np.clip(dens * 1.6, 0, 1)
    for c, m in k.zone('forearm'):
        gloss(c, m, s['black'], rough=0.06)
        code_glyphs(c, m, s, cell_along=0.05, cell_round=0.068, density=0.62, seed=272)
    for c, m in k.zone('cap'):
        mm = (c.d < 6.95) & m
        gloss(c, mm, s['black'], rough=0.06)
        code_glyphs(c, mm, s, cell_along=0.05, cell_round=0.068, density=0.68, seed=273)
    for c, m in k.zone('wrap'):
        scales(c, m, '#0E1210', size=0.026, rough=0.35, depth=0.0006, seed=274, sheen=0.3)
        c.put(m, None, glow=0.0)
    k.paint(['joint'], metal, s['metal'], rough=0.1)
    for c, m in k.zone('ring'):
        gloss(c, m, '#08120A', rough=0.1)
        c.put(m, None, glow=0.0)
    glow_ring(k, s['code'], d0=5.335, d1=5.41)
    end_band(k, d0=6.95)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#080A08')
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


# ---------------------------------------------------------------------------------------------
# Legendaries
# ---------------------------------------------------------------------------------------------

def liquid_chrome(c, m, seed=0, twist=1.1, bands=2, warp=0.9, glow=0.9, line_w=0.018, base=0.62):
    """Liquid chrome: ribbons of polished metal twisting round the cue, each fold shading from dark
    to bright with a hot white edge where it turns over (the edges glow). Neutral (white to grey),
    so a runtime Color tint turns the whole cue any colour."""
    w = fbm(c, 3.5, 1.6, octaves=3, seed=seed)
    ph = (c.theta / (2 * math.pi) + c.d * twist + (w - 0.5) * warp) * bands
    f = np.mod(ph, 1.0)
    fold = f ** 1.6
    edge = np.exp(-((f - 0.012) / line_w) ** 2) + np.exp(-((f - 0.985) / (line_w * 0.6)) ** 2) * 0.6
    under = np.exp(-((f - 0.35) / 0.05) ** 2) * 0.25  # a soft second highlight inside each fold
    lvl = base * (0.45 + 0.55 * fold) + under * 60 / 255
    col = np.stack([lvl, lvl, lvl], -1) * 255
    col = col + (255 - col) * np.clip(edge, 0, 1)[..., None]
    c.put(m, col, rough=0.06 + 0.06 * (1 - fold), metal=0.75, glow=np.clip(edge * glow + fold ** 6 * 0.25, 0, 1) * m)
    c.add_height(m, 0.00025 * (fold - 0.5) + 0.0001 * np.clip(edge, 0, 1))


@recipe
def chroma(k):
    """Mirror chrome whose whole colour cycles through the rainbow (the SurfaceAppearance Color is
    turned round the hue wheel by a script; the maps are neutral): liquid-chrome ribbons twisting
    along the forearm and sleeve with glowing edges, a smooth chrome shaft with long glowing twist
    lines, a snakeskin wrap with a bright sheen, chrome collar and rings, a black end."""
    s = k.skin['colours']
    for c, m in k.zone('shaft'):
        liquid_chrome(c, m, seed=301, twist=0.55, bands=2, warp=0.6, glow=0.85, line_w=0.014, base=0.7)
    for c, m in k.zone('forearm'):
        liquid_chrome(c, m, seed=302, twist=1.1, bands=2, warp=0.9, glow=0.95)
    for c, m in k.zone('cap'):
        mm = (c.d < 6.95) & m
        liquid_chrome(c, mm, seed=303, twist=1.4, bands=2, warp=0.8, glow=0.95)
        gloss(c, band(c, 6.95, 7.2) * m > 0.5, '#0C0C0E', rough=0.1)
        c.put(band(c, 6.95, 7.2) * m, None, glow=0.0)
    for c, m in k.zone('wrap'):
        scales(c, m, '#3A3C44', size=0.028, rough=0.2, depth=0.0007, seed=304, sheen=1.4, edge_col='#101014')
        c.put(m, None, metal=0.35, glow=np.clip((luma(c.col) - 0.3) * 1.2, 0, 0.5) * m)
    k.paint(['joint'], metal, s['metal'], rough=0.12)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.12)
        c.put(m, None, glow=0.0)
        line = band(c, 5.36, 5.385) * m
        c.put(line, np.broadcast_to(np.array([250.0, 250, 250]), c.col.shape), metal=0.0, glow=line)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0C0C0E')
    rr = c.r / c.face_radius
    ringm = np.exp(-((rr - 0.62) / 0.05) ** 2)
    c.put(ringm, np.broadcast_to(np.array([250.0, 250, 250]), c.col.shape), glow=ringm)
    joint_seam(k)
    seam_edges(k, [F1, W0, W1, 6.95])


def lightning_veins(c, m, s, seed=0, freq=5.0, width=0.022, density=1.0, flare=None, glow=1.0, along=0.7):
    """Branching lightning veins in dark steel: thin jagged lines (the zero crossings of warped
    noise at two scales: trunks and finer branches), a white-hot core in a blue glow with a
    faint blue bloom on the steel. flare (0..1 per pixel) brightens some of them (a frame of
    the random pulse). Returns the vein coverage."""
    w1 = fbm(c, freq * 1.5, freq * 1.2, octaves=3, seed=seed)
    warp = ((w1 - 0.5) * 0.6, (w1 - 0.5) * 0.4, (w1 - 0.5) * 0.6)
    n1 = fbm(c, freq, freq * along, octaves=4, seed=seed + 1, warp=warp)  # along < 1: veins run along the cue
    n2 = fbm(c, freq * 2.6, freq * 2.6 * along * 1.4, octaves=3, seed=seed + 2, warp=warp)
    live = np.clip((fbm(c, freq * 0.6, freq * 0.6, octaves=2, seed=seed + 3) - (0.62 - 0.3 * density)) * 3.5, 0, 1)
    trunk = np.exp(-((n1 - 0.5) / (width * 0.5)) ** 2) * live
    branch = np.exp(-((n2 - 0.5) / (width * 0.35)) ** 2) * live * np.clip((fbm(c, freq * 2, freq * 2, octaves=2, seed=seed + 4) - 0.45) * 4, 0, 1)
    core = np.clip(trunk + branch * 0.75, 0, 1)
    halo = np.clip(np.exp(-((n1 - 0.5) / (width * 2.2)) ** 2) * live * 0.5 + np.exp(-((n2 - 0.5) / (width * 1.4)) ** 2) * live * 0.25, 0, 1)
    bright = 0.6 if flare is None else 0.3 + 0.9 * flare
    blue, white = rgb(s['bolt']), np.array([235.0, 248, 255])
    c.put(halo * m * 0.7, np.broadcast_to(blue * 0.8, c.col.shape), glow=None)
    col = mix(np.broadcast_to(blue, c.col.shape), np.broadcast_to(white, c.col.shape), np.clip(core * 1.4 - 0.3, 0, 1))
    c.put(core * m, col, rough=0.3, metal=0.0)
    c.glow = np.maximum(c.glow, np.clip((core + halo * 0.45) * bright, 0, 1) * glow * m)
    c.used['glow'] = True
    c.add_height(core * m, -0.00012)
    return core


def chevron_plates(c, m, s, d0, d1, n_round=2, count=3, phase=FACE, slant=1.0, seed=0):
    """Angular armour plates: raised silver shards slanting across the section like claw slashes,
    each a long sharp-ended parallelogram with a bevelled edge and a brushed face; count along it,
    n_round round the cue."""
    span = 2 * math.pi / n_round
    L = d1 - d0
    out = np.zeros(c.d.shape)
    for j in range(n_round):
        th0 = phase + j * span
        for i in range(count):
            dc = d0 + L * (i + 0.5) / count
            along = c.d - dc
            around = around_of(c, th0) / (2 * math.pi * float(np.mean(c.r)) / n_round)  # -0.5..0.5 round its share
            # a slanted shard: long axis along the diagonal, pointed ends
            u = along / (L / count * 0.55) + around * slant * 1.4
            v = around * 2.4 - along / (L / count) * 0.6
            d = np.abs(u) + np.abs(v) * 1.8 - 1
            shard = np.clip(-d / 0.08, 0, 1) * m
            bevel = np.clip(-d / 0.3, 0, 1)
            out = np.maximum(out, shard * (0.55 + 0.45 * bevel))
    plate = out > 0.01
    brushed = fbm(c, 30, 900, octaves=2, seed=seed)
    col = rgb(s['silver']) * (0.7 + 0.35 * out + 0.1 * brushed)[..., None]
    c.put(out > 0.3, col, rough=0.18, metal=1.0, glow=0.0)
    c.add_height(plate * 1.0, 0.0008 * out)
    return out


@recipe
def thunderstrike(k):
    """Storm-grey steel with glowing blue lightning veins: OpenAI forearm and sleeve (lightning
    branching over dark steel between raised silver angular armour shards), a procedural steel
    shaft with long branching veins running along it, a black crosshatch grip with blue veins
    breaking through, a glowing blue ring, a silver collar. Frames 1-3 flare a different part of
    the veins (the random pulse); frame 0 is the calm one."""
    s = k.skin['colours']
    fr = getattr(k, 'frame', 0)

    def flare(c):
        # frame 0: every vein at a middle brightness; frames 1-3: one region blazes, the rest dims
        if fr == 0:
            return np.full(c.d.shape, 0.35)
        return np.clip((fbm(c, 1.6, 1.1, octaves=2, seed=400 + 17 * fr) - 0.5) * 7, 0, 1)
    for panel in ('shaft_tile', 'shaft_top', 'forearm', 'butt'):
        img = ai_base(k, panel, rough=0.3, height=0.0004)
        c = k.c[panel]
        L = luma(img)
        mx, mn = img.max(-1), img.min(-1)
        sat = (mx - mn) / np.maximum(mx, 1)
        silver = np.clip((L - 0.55) * 5, 0, 1) * np.clip((0.9 - L) * 10, 0, 1) * (sat < 0.15)
        hot = np.clip((L - 0.84) * 8, 0, 1) * (sat < 0.4) * (1 - silver)  # the white-hot lightning cores
        blue = np.clip(np.clip((sat - 0.4) * 4, 0, 1) * (img[..., 2] > img[..., 0] + 30) * np.clip((L - 0.2) * 3, 0, 1) + hot, 0, 1)
        c.put(silver > 0.3, None, rough=0.2, metal=1.0)
        c.add_height(silver, 0.0005)
        c.put(np.ones((c.h, c.w), bool), None, glow=np.clip(blue * (0.3 + 0.9 * flare(c)), 0, 1))
    f = k.c['forearm']
    metal(f, f.zone('joint'), s['metal'], rough=0.16)
    f.put(f.zone('joint'), None, glow=0.0)
    for c, m in k.zone('wrap'):
        crosshatch(c, m, '#101218', pitch=0.022)
        c.put(m, None, glow=0.0)
        lightning_veins(c, m, s, seed=405, freq=5, width=0.016, density=0.55, flare=flare(c), glow=0.9, along=0.4)
    for c, m in k.zone('ring'):
        metal(c, m, s['metal'], rough=0.16)
        c.put(m, None, glow=0.0)
    glow_ring(k, s['bolt'], d0=5.345, d1=5.395)
    end_band(k, d0=6.95)
    c = k.c['cap_end']
    rubber(c, c.inside | True, '#0C0D10')
    rr = c.r / c.face_radius
    ringm = np.exp(-((rr - 0.62) / 0.05) ** 2)
    c.put(ringm, np.broadcast_to(rgb(s['bolt']), c.col.shape), glow=ringm)
    joint_seam(k)
    seam_edges(k, [F1, W0, W1])


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
    if spec.get('roll_deg'):
        # turn the painting round the cue (rows are angles), e.g. so the middle-row centrepiece
        # faces a camera above and to the side like the inlays
        img = np.roll(img, int(round(spec['roll_deg'] / 360.0 * img.shape[0])), axis=0)
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
    # moving-material frames (Legendary and up): the recipe paints frame n when k.frame = n;
    # frame 0 is the skin itself, the others go to skins/<id>_f<n>/ (CueTextures makes their maps)
    for n in range(1, int((skin.get('frames') or {}).get('Count', 1))):
        kf = Kit(skin)
        kf.frame = n
        RECIPES[name](kf)
        kf.write('%s_f%d' % (skin_id, n))
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
