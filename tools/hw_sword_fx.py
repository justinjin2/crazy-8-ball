#!/usr/bin/env python3
"""The Halloween Sword's v3 effect sprites (lane cuesB, 2026-10-29: the top of the event's
ladder gets the richest effects).

    python3 tools/hw_sword_fx.py [face] [flame] [--frames <dir>]     (no names: both)

Procedural numpy + Pillow painting, deterministic (a seeded numpy generator, no random module),
drawn at twice the cell size and shrunk. Every sheet is a 4x4 flipbook (Grid4x4) with 8 px of
padding per 1024 (4 px per 512), laid out as CuePieces.sheet_sprite does, and LOOPS: frame 15
runs into frame 0 (the laugh, the head's bob and tilt, the tongues' sway and growth and the
noise that wobbles them are all periodic over the 16 frames), so the rows play it with
FlipbookMode Loop.

    halloween_sword/fire_face_4x4   1024: the finisher's laughing jack-o'-lantern face made of
                                    purple fire, as on the sword's hilt (angry slanted eyes, a
                                    triangle nose, a jagged grin with teeth): two cackles a loop
                                    (the jaw drops, the eyes squint, the head bobs and tilts),
                                    white-hot carved holes with fire inside the mouth, an inner
                                    glow on the ribbed rind, a crown of flame tongues licking up
                                    off it and licks breaking away, all inside a dark-violet ink
                                    line and a violet halo so it reads on the bright lobby floor
                                    as well as at night
    halloween_sword/toon_flame_4x4  512: one bold cartoon flame tongue licking (the same banded
                                    palette and ink line), for the blade's edge flames, the trail
                                    and the finisher's flame bed

The flames are drawn tongues (a swaying S-shaped centreline, a tapering width, heat falling
across and along), banded into the palette; low-frequency tileable noise only wobbles them
(high-frequency noise thresholded into bands read as speckle and dirt on the first try).

--frames <dir> also writes a contact sheet of each sheet on dark and on cream there and four
face frames at full size (review only, never committed).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'cue', 'vfx', 'halloween_sword')
FRAMES = 16
TAU = 2 * math.pi

# The banded fire palette (sRGB), dark to white-hot: the ink outline, then the flame's bands.
INK = (24, 6, 44)
DEEP = (62, 18, 120)
BODY = (112, 38, 214)
VIVID = (157, 88, 255)
LIGHT = (205, 166, 255)
HOT = (242, 232, 255)
WHITE = (255, 252, 255)
HALO = (123, 47, 247)
RIND_DARK = (40, 12, 82)
STEM = (46, 15, 74)
FLAME_STOPS = [(0.0, DEEP), (0.27, BODY), (0.50, VIVID), (0.70, LIGHT), (0.87, HOT)]


def rgb(c):
    return np.array(c, np.float32) / 255.0


# --------------------------------------------------------------------------- noise and helpers

def periodic_noise(n, seed, slope=1.7, lo=2.0, hi=None):
    """Band-limited noise tileable in both axes (white noise filtered in the frequency domain),
    zero mean, unit deviation."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    fx = np.fft.fftfreq(n)[None, :] * n
    fy = np.fft.fftfreq(n)[:, None] * n
    f = np.sqrt(fx * fx + fy * fy)
    amp = np.where(f < lo, 0.0, 1.0 / np.maximum(f, 1.0) ** slope)
    if hi:
        amp = amp * np.exp(-(f / hi) ** 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(w) * amp))
    return (out - out.mean()) / out.std()


# Low-frequency tileable noise only: it wobbles the drawn tongues.
WOBBLE = periodic_noise(128, 31, slope=2.6, lo=1.0, hi=10)
WOBBLE2 = periodic_noise(128, 47, slope=2.6, lo=1.0, hi=10)


def sample(field, u, v):
    """Bilinear sample of a tileable field at (u, v) in periods (wraps)."""
    n = field.shape[0]
    x = np.mod(u, 1.0) * n
    y = np.mod(v, 1.0) * n
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    fx = x - x0
    fy = y - y0
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    a = field[y0, x0] * (1 - fx) + field[y0, x1] * fx
    b = field[y1, x0] * (1 - fx) + field[y1, x1] * fx
    return a * (1 - fy) + b * fy


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _l(a):
    return Image.fromarray(np.clip(np.nan_to_num(a) * 255.0, 0, 255).astype(np.uint8))


def blur(a, px):
    return np.asarray(_l(a).filter(ImageFilter.GaussianBlur(px)), np.float32) / 255.0


def dilate(a, px):
    return np.asarray(_l(a).filter(ImageFilter.MaxFilter(int(px) * 2 + 1)), np.float32) / 255.0


def erode(a, px):
    return np.asarray(_l(a).filter(ImageFilter.MinFilter(int(px) * 2 + 1)), np.float32) / 255.0


def over(dst_rgb, dst_a, src_rgb, src_a):
    """Porter-Duff over, straight alpha; src_rgb HxWx3 or a colour."""
    sa = src_a[..., None]
    da = dst_a[..., None]
    out_a = sa + da * (1 - sa)
    out_rgb = (src_rgb * sa + dst_rgb * da * (1 - sa)) / np.maximum(out_a, 1e-6)
    return out_rgb, out_a[..., 0]


def under(col, a, c, ha):
    """`c` at alpha `ha` drawn behind (col, a)."""
    out_a = a + ha * (1 - a)
    out = (col * a[..., None] + c * (ha * (1 - a))[..., None]) / np.maximum(out_a, 1e-6)[..., None]
    return out, out_a


def bands(heat, stops):
    """The banded flame colour of `heat`: stops [(threshold, colour), ...] ascending; each band
    edge anti-aliased over a hair of heat."""
    h, w = heat.shape
    out = np.zeros((h, w, 3), np.float32)
    out[...] = rgb(stops[0][1])
    for th, col in stops[1:]:
        k = smooth(th - 0.012, th + 0.012, heat)[..., None]
        out = out * (1 - k) + rgb(col) * k
    return out


def poly_mask(n, pts):
    """A 0..1 mask of the polygon `pts` (unit coords, x right, y up, -1..1) on an n x n grid,
    drawn at 2x and shrunk (anti-aliased)."""
    m = n * 2
    im = Image.new('L', (m, m), 0)
    d = ImageDraw.Draw(im)
    d.polygon([((p[0] + 1) * 0.5 * m, (1 - p[1]) * 0.5 * m) for p in pts], fill=255)
    im = im.resize((n, n), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def quad_bezier(a, c, b, k=16):
    return [((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t * t * b[0],
             (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t * t * b[1]) for t in np.linspace(0, 1, k)]


def to_image(col, a):
    img = np.nan_to_num(np.dstack([np.clip(col, 0, 1), np.clip(a, 0, 1)]))
    return Image.fromarray((img * 255.0 + 0.5).astype(np.uint8), 'RGBA')


def pack(frames, size):
    """16 RGBA cells packed 4x4 at `size` with padding (8 px per 1024), row by row from the top
    left (the Grid4x4 order)."""
    cell = size // 4
    pad = max(2, size // 128)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    for i, im in enumerate(frames):
        im = im.resize((cell - 2 * pad, cell - 2 * pad), Image.LANCZOS)
        r, c = divmod(i, 4)
        out.paste(im, (c * cell + pad, r * cell + pad))
    return out


def grid(n):
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    x = (xs + 0.5) / n * 2 - 1
    y = 1 - (ys + 0.5) / n * 2
    return x, y


# --------------------------------------------------------------------------- flame tongues

def tongue(x, y, base, angle, length, width, sway, wave):
    """The heat (0..1) of one cartoon flame tongue: from `base` along `angle` (radians from
    straight up, + to the right) for `length`, `width` across its root, its centreline swaying
    `sway` (a share of the length) in an S whose phase is `wave` (radians). The heat is 1 on the
    centreline at the root, falling across to 0 at the edge and along to the tip, so banding it
    gives nested tongues whose bright cores are shorter than the dark outer flame."""
    dxv, dyv = math.sin(angle), math.cos(angle)
    px, py = x - base[0], y - base[1]
    v = (px * dxv + py * dyv) / length
    u = (px * dyv - py * dxv) / length
    vc = np.clip(v, 0, 1)
    c = sway * np.sin(math.pi * 1.25 * vc + wave) * vc ** 1.15
    w = (width / length) * (1 - vc) ** 0.85 * (0.75 + 0.25 * np.cos(math.pi * vc * 0.5)) + 1e-4
    across = np.clip(1 - np.abs(u - c) / w, 0, 1)
    root = smooth(-0.35, 0.05, v)  # the root melts into what it grows from
    return across ** 0.8 * root * (1 - 0.62 * vc ** 1.3) * (v < 1)


def lick(x, y, centre, r, angle=0.0):
    """A detached lick of flame: a teardrop with its point up (radius r), heat 1 at the core."""
    dxv, dyv = math.sin(angle), math.cos(angle)
    px, py = x - centre[0], y - centre[1]
    v = (px * dxv + py * dyv) / r
    u = (px * dyv - py * dxv) / r
    up = np.clip(v, 0, 2.2) / 2.2
    w = np.where(v < 0, np.sqrt(np.clip(1 - v * v, 0, 1)), (1 - up) ** 1.1)
    across = np.clip(1 - np.abs(u) / np.maximum(w, 1e-3), 0, 1)
    return across * ((v > -1) & (v < 2.2)) * (1 - 0.5 * up)


def finish(col, a, ink_px, halo_px=0, halo=0.0):
    """The dark-violet ink line round the whole silhouette, then an optional violet halo."""
    shape = np.clip(a, 0, 1)
    ink = np.clip(dilate(shape, ink_px) - shape, 0, 1)
    ink = blur(ink, 0.8)
    col, a = over(col, a, np.broadcast_to(rgb(INK), col.shape), ink * (1 - shape))
    if halo > 0:
        h = blur(dilate(shape, halo_px), halo_px * 1.3) * halo
        col, a = under(col, a, rgb(HALO), np.clip(h - a, 0, 1))
    return col, a


# --------------------------------------------------------------------------- the laughing face

N = 512  # a face frame is painted at 512 and shrunk to its 240 px cell

# The crown's tongues: (spot on the head's top outline in degrees from straight up, + right;
# length; root width; sway; cycles a loop; phase), and the licks breaking off some of them.
CROWN = [(-62, 0.30, 0.17, 0.30, 1, 0.1), (-40, 0.44, 0.19, 0.26, 2, 0.6), (-18, 0.56, 0.20, 0.22, 1, 0.35),
         (4, 0.62, 0.21, 0.24, 2, 0.85), (24, 0.52, 0.20, 0.25, 1, 0.55), (44, 0.42, 0.18, 0.28, 2, 0.2),
         (64, 0.28, 0.16, 0.30, 1, 0.75), (-80, 0.18, 0.13, 0.3, 2, 0.4), (82, 0.17, 0.13, 0.3, 1, 0.9)]
LICKS = [(-18, 1, 0.0), (4, 1, 0.5), (24, 1, 0.25), (-40, 1, 0.75)]
SIDES = [(-104, 0.36, 0.16, 0.34, 2, 0.15), (106, 0.34, 0.16, 0.34, 2, 0.65),
         (-128, 0.26, 0.13, 0.34, 1, 0.45), (130, 0.25, 0.13, 0.34, 1, 0.95)]


def laugh(f):
    """The cackle at frame f (0..1 open), the head's tilt (radians) and bob (units)."""
    phase = f / FRAMES
    o = (0.5 - 0.5 * math.cos(TAU * 2 * phase)) ** 0.85
    tilt = math.radians(5.5) * math.sin(TAU * phase)
    bob = 0.04 * o
    return o, tilt, bob


def face_frame(f):
    x, y = grid(N)
    o, tilt, bob = laugh(f)
    phase = f / FRAMES

    # the head: centre, half-width; local coords in units of the half-width, turned by the tilt
    cx, cy, R = 0.0, -0.22 + bob, 0.62
    sx, sy = R * (1 - 0.018 * o), R * (1 + 0.035 * o)
    ct, st = math.cos(tilt), math.sin(tilt)
    dx, dy = x - cx, y - cy
    lx = (dx * ct + dy * st) / sx
    ly = (-dx * st + dy * ct) / sy

    def world(p):
        px, py = p[0] * sx, p[1] * sy
        return (cx + px * ct - py * st, cy + px * st + py * ct)

    # ---- the pumpkin: lobes (front-most first), union silhouette, seams, lobe shading
    lobes = [(0.0, 0.40, 0.84), (-0.36, 0.40, 0.81), (0.36, 0.40, 0.81), (-0.68, 0.36, 0.72), (0.68, 0.36, 0.72)]
    rr = [np.sqrt(((lx - x0) / ax) ** 2 + (ly / ay) ** 2) for x0, ax, ay in lobes]
    head_d = np.min(np.stack(rr), axis=0)  # < 1 inside some lobe
    edge_px = 2.0 / N / (R * 0.4)
    head_a = smooth(1 + edge_px, 1 - edge_px, head_d)
    owner = np.full(x.shape, -1, np.int64)
    for k in range(len(lobes) - 1, -1, -1):
        owner = np.where(rr[k] < 1, k, owner)
    s = np.zeros_like(x)
    for k in range(len(lobes)):
        s = np.where(owner == k, 1 - np.clip(rr[k], 0, 1) ** 2, s)
    seam = np.zeros_like(x)
    for k in range(3):
        near = np.abs(rr[k] - 1) < 0.05
        behind = owner > k
        vis = np.ones_like(x, bool)
        for j in range(k):
            vis &= rr[j] >= 1
        seam = np.maximum(seam, (near & behind & vis).astype(np.float32) * (1 - np.abs(rr[k] - 1) / 0.05))
    seam *= smooth(0.84, 0.5, np.abs(ly))

    # ---- the carved features (local coords; mirrored eyes)
    sq = o

    def eye(side):
        O = (side * 0.66, 0.44 + 0.03 * sq)
        I = (side * 0.13, 0.22 + 0.02 * sq)
        mid = (side * 0.42, 0.02 + 0.15 * sq)  # the lower lid rises as it laughs
        ctrl = (2 * mid[0] - 0.5 * (O[0] + I[0]), 2 * mid[1] - 0.5 * (O[1] + I[1]))
        top = quad_bezier(O, (side * 0.40, 0.37 + 0.03 * sq), I, 10)
        bottom = quad_bezier(I, ctrl, O, 14)
        return [world(p) for p in top + bottom[1:]]

    nose = [world(p) for p in ((0.0, 0.12 + 0.015 * o), (-0.12, -0.09), (0.0, -0.05), (0.12, -0.09))]
    W = 0.88
    xs = np.linspace(-W, W, 81)

    def upper(xv):
        u = xv / W
        base = -0.19 - 0.15 * (1 - u * u) + (0.12 + 0.03 * o) * np.abs(u) ** 5
        jag = 0.03 * np.abs(((xv * 4.2 + 0.25) % 1.0) - 0.5) * 2  # knife notches
        return base - jag

    def lower(xv):
        u = xv / W
        g = (0.13 + 0.22 * o) * np.clip(1 - u * u, 0, 1) ** 0.7
        jag = 0.026 * np.abs(((xv * 3.8 + 0.6) % 1.0) - 0.5) * 2
        return upper(xv) - g - 0.03 * (1 - u * u) + jag

    mouth = [world((xv, upper(xv))) for xv in xs] + [world((xv, lower(xv))) for xv in xs[::-1]]
    teeth = []
    for x0, w0, ln in ((-0.34, 0.16, 0.11), (0.30, 0.16, 0.11)):  # two hanging from the lip
        yt = upper(x0) + 0.03
        teeth.append([world(p) for p in ((x0 - w0 / 2, yt), (x0 + w0 / 2, yt), (x0 + w0 * 0.36, yt - ln), (x0 - w0 * 0.36, yt - ln))])
    for x0, w0, ln in ((-0.03, 0.17, 0.11), (0.58, 0.11, 0.07), (-0.62, 0.10, 0.06)):  # rising from the jaw
        yb = lower(x0) - 0.03
        teeth.append([world(p) for p in ((x0 - w0 / 2, yb), (x0 + w0 / 2, yb), (x0 + w0 * 0.34, yb + ln), (x0 - w0 * 0.34, yb + ln))])

    eyes_m = np.maximum(poly_mask(N, eye(-1)), poly_mask(N, eye(1)))
    nose_m = poly_mask(N, nose)
    mouth_m = poly_mask(N, mouth)
    teeth_m = np.zeros_like(x)
    for t in teeth:
        teeth_m = np.maximum(teeth_m, poly_mask(N, t))
    mouth_m = mouth_m * (1 - teeth_m)
    holes = np.clip(np.maximum(np.maximum(eyes_m, nose_m), mouth_m), 0, 1) * head_a

    # ---- the crown of flame: drawn tongues and licks, wobbled by low-frequency noise
    wob = 0.035 * sample(WOBBLE, x * 0.6, y * 0.5 - phase * 2)
    wob2 = 0.025 * sample(WOBBLE2, x * 0.6 + 0.4, y * 0.5 - phase)
    xw = x + wob * (0.4 + np.clip(y - cy, 0, 2))
    yw = y + wob2
    heat = np.zeros_like(x)
    flare = 1 + 0.14 * o  # the fire flares with each cackle

    def crown_base(deg):
        a = math.radians(deg)
        return world((0.84 * 0.62 * math.sin(a) * 1.55, 0.84 * math.cos(a) * 0.93)), tilt * 0.4 + a * 0.32

    for deg, ln, wd, sw, m, ph in CROWN:
        base, lean = crown_base(deg)
        grow = 1 + 0.16 * math.sin(TAU * (phase * m + ph))
        heat = np.maximum(heat, tongue(xw, yw, base, lean, ln * grow * flare * R / 0.62, wd * R / 0.62,
                                       sw, TAU * (phase * m + ph)))
    def outline(deg):
        """The head's outline (local) on the ray `deg` from straight up."""
        a = math.radians(deg)
        r = 0.2
        while r < 1.6:
            px, py = r * math.sin(a), r * math.cos(a)
            if min(math.hypot((px - x0) / ax, py / ay) for x0, ax, ay in lobes) >= 1:
                break
            r += 0.005
        return r * math.sin(a), r * math.cos(a)

    for deg, ln, wd, sw, m, ph in SIDES:  # flames licking up the cheeks, leaning out
        bx, by = outline(deg)
        base = world((bx * 0.93, by * 0.93))
        lean = tilt * 0.4 + math.copysign(math.radians(9), deg)
        grow = 1 + 0.2 * math.sin(TAU * (phase * m + ph))
        heat = np.maximum(heat, tongue(xw, yw, base, lean, ln * grow * flare * R / 0.62, wd * R / 0.62,
                                       sw, TAU * (phase * m + ph)) * 0.92)
    for deg, m, ph in LICKS:
        k = next(c for c in CROWN if c[0] == deg)
        base, lean = crown_base(deg)
        sfrac = (phase * m + ph) % 1.0
        dist = k[1] * (0.70 + 0.55 * sfrac) * R / 0.62
        cxl = base[0] + math.sin(lean) * dist + 0.03 * math.sin(TAU * sfrac)
        cyl = base[1] + math.cos(lean) * dist
        r = 0.085 * (1 - sfrac) ** 1.1 + 0.01
        heat = np.maximum(heat, lick(xw, yw, (cxl, cyl), r * R / 0.62, lean) * (1 - sfrac) ** 0.6 * 0.85)
    # a burning band hugging the crown, so the tongues grow out of fire, not out of the rind
    band = np.clip(1 - np.maximum(head_d - 1, 0) / 0.20, 0, 1) * smooth(0.05, 0.55, ly) * (head_d > 0.92)
    heat = np.maximum(heat, band * 0.62)
    heat *= smooth(0.985, 0.90, y)  # never past the cell's top
    flame_a = smooth(0.015, 0.05, heat)
    flame_col = bands(heat, FLAME_STOPS)

    # ---- the rind: deep violet by lobe, lit from the carved holes, seams inked
    glow_near = blur(holes, 7)
    glow_far = blur(holes, 22)
    rind = rgb(RIND_DARK)[None, None, :] * (1 - s[..., None] ** 0.8) + rgb(BODY)[None, None, :] * 0.92 * s[..., None] ** 0.8
    hi = smooth(0.62, 0.96, s) * smooth(-0.3, 0.6, ly)
    rind = rind * (1 - 0.30 * hi[..., None]) + rgb(VIVID) * 0.30 * hi[..., None]
    flick = 0.85 + 0.15 * math.sin(TAU * phase * 3)
    lit = np.clip(1.05 * glow_near * flick + 0.42 * glow_far, 0, 1)
    rind = rind * (1 - lit[..., None]) + rgb(LIGHT) * lit[..., None]
    edge_dark = smooth(0.78, 1.0, head_d)
    rind = rind * (1 - 0.6 * edge_dark[..., None]) + rgb(INK) * 0.6 * edge_dark[..., None]
    rind = rind * (1 - seam[..., None] * 0.9) + rgb(INK) * seam[..., None] * 0.9
    top = smooth(0.35, 0.84, ly) * head_a  # the fire's light on the crown
    rind = rind * (1 - 0.35 * top[..., None]) + rgb(VIVID) * 0.35 * top[..., None]

    # ---- the holes: a lit cut wall round the edge, a white-hot core, fire inside the mouth
    inner = erode(holes, 4)
    deep_in = erode(holes, 10)
    hole_col = np.zeros(x.shape + (3,), np.float32)
    hole_col[...] = rgb(LIGHT)
    k1 = smooth(0.2, 0.9, inner)[..., None]
    hole_col = hole_col * (1 - k1) + rgb(HOT) * k1
    k2 = smooth(0.2, 0.9, deep_in)[..., None]
    hole_col = hole_col * (1 - k2) + rgb(WHITE) * k2
    inside = np.zeros_like(x)  # three tongues rising off the jaw, seen through the grin
    for x0, ln, ph in ((-0.45, 0.26, 0.0), (0.05, 0.32, 0.4), (0.50, 0.24, 0.7)):
        b = world((x0, lower(x0) - 0.02))
        inside = np.maximum(inside, tongue(xw, yw, b, tilt, ln * R * (1 + 0.6 * o), 0.13 * R, 0.25, TAU * (phase * 2 + ph)))
    # the mouth glows from the jaw up: lilac low in it, white-hot at the top, the jaw's fire
    # flickering through as soft lilac tongues (vivid ones read as fangs)
    jaw = smooth(-0.05, 0.25, (ly - np.interp(lx, xs, lower(xs))) / 0.25)
    low = ((1 - jaw) * mouth_m * 0.55)[..., None]
    hole_col = hole_col * (1 - low) + rgb(LIGHT) * low
    mouth_fire = smooth(0.30, 0.40, inside) * mouth_m * 0.55
    hole_col = hole_col * (1 - mouth_fire[..., None]) + rgb(LIGHT) * mouth_fire[..., None]
    cut = np.clip(dilate(holes, 3) - holes, 0, 1) * head_a  # the carved edge, inked

    # ---- the stem: short, thick, curling right out of the crown
    spine = quad_bezier((0.0, 0.66), (0.02, 0.96), (0.24, 1.07), 14)
    left, right = [], []
    for i, (px, py) in enumerate(spine):
        j = min(i + 1, len(spine) - 1)
        k = max(i - 1, 0)
        tx, ty = spine[j][0] - spine[k][0], spine[j][1] - spine[k][1]
        tl = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / tl, tx / tl
        hw = 0.115 - 0.055 * (i / (len(spine) - 1))  # flared root, thinner cut tip
        left.append((px + nx * hw, py + ny * hw))
        right.append((px - nx * hw, py - ny * hw))
    stem_m = poly_mask(N, [world(p) for p in left + right[::-1]])
    # a lilac sheen down the stem's left side (lit by the fire behind it)
    sheen_pts = [world((px - 0.05 + 0.02 * (i / 13), py)) for i, (px, py) in enumerate(spine[:11])]
    sheen = np.zeros_like(x)
    for (ax_, ay_), (bx_, by_) in zip(sheen_pts[:-1], sheen_pts[1:]):
        vx, vy = bx_ - ax_, by_ - ay_
        t = np.clip(((x - ax_) * vx + (y - ay_) * vy) / (vx * vx + vy * vy + 1e-9), 0, 1)
        d = np.hypot(x - ax_ - t * vx, y - ay_ - t * vy)
        sheen = np.maximum(sheen, smooth(0.016, 0.006, d))
    sheen *= stem_m

    # ---- composite: flames behind, stem, rind, holes, cut ink, tongues in front, ink, halo
    col = np.zeros(x.shape + (3,), np.float32)
    a = np.zeros_like(x)
    col, a = over(col, a, flame_col, flame_a)
    stem_col = np.zeros_like(col)
    stem_col[...] = rgb(STEM)
    stem_col = stem_col * (1 - sheen[..., None]) + rgb(VIVID) * sheen[..., None]
    col, a = over(col, a, stem_col, stem_m)
    stem_ink = np.clip(dilate(stem_m, 3) - stem_m, 0, 1) * (1 - head_a)
    col, a = over(col, a, np.broadcast_to(rgb(INK), col.shape), stem_ink)
    rind_col = rind * (1 - holes[..., None]) + hole_col * holes[..., None]
    rind_col = rind_col * (1 - cut[..., None]) + rgb(INK) * cut[..., None]
    # the crown backlit by the fire: a lilac rim inside the ink round the top of the head
    rim = np.clip(erode(head_a, 3) - erode(head_a, 9), 0, 1) * smooth(0.25, 0.65, ly)
    rind_col = rind_col * (1 - 0.8 * rim[..., None]) + rgb(LIGHT) * 0.8 * rim[..., None]
    head_ink = np.clip(head_a - erode(head_a, 3), 0, 1)
    rind_col = rind_col * (1 - head_ink[..., None]) + rgb(INK) * head_ink[..., None]
    col, a = over(col, a, rind_col, head_a)
    col, a = finish(col, a, 4, 9, 0.5)
    return to_image(col, a)


# --------------------------------------------------------------------------- the toon flame

M = 256  # a flame frame is painted at 256 and shrunk to its 120 px cell


def flame_frame(f):
    x, y = grid(M)
    phase = f / FRAMES
    wob = 0.05 * sample(WOBBLE, x * 0.5, y * 0.5 - phase * 2)
    xw = x + wob * np.clip(y + 0.6, 0, 2)
    yw = y
    grow = 1 + 0.10 * math.sin(TAU * phase * 2)
    heat = tongue(xw, yw, (0.0, -0.66), 0.04 * math.sin(TAU * phase), 1.45 * grow, 0.62, 0.20, TAU * phase * 2)
    heat = np.maximum(heat, tongue(xw, yw, (-0.22, -0.55), -0.35, 0.78 * (1 + 0.15 * math.sin(TAU * (phase * 2 + 0.3))),
                                   0.30, 0.25, TAU * (phase * 2 + 0.5)))
    heat = np.maximum(heat, tongue(xw, yw, (0.24, -0.52), 0.38, 0.70 * (1 + 0.15 * math.sin(TAU * (phase * 2 + 0.7))),
                                   0.28, 0.25, TAU * (phase * 2 + 0.2)))
    root = np.clip(1 - np.sqrt((x / 0.44) ** 2 + ((y + 0.56) / 0.30) ** 2), 0, 1)  # a round root
    heat = np.maximum(heat, root ** 0.6 * 0.95)
    sfrac = (phase * 2) % 1.0
    heat = np.maximum(heat, lick(xw, yw, (0.05 * math.sin(TAU * sfrac), 0.55 + 0.30 * sfrac),
                                 0.10 * (1 - sfrac) + 0.01) * (1 - sfrac) * 0.8)
    heat *= smooth(0.98, 0.90, y)
    # a rounded bottom inside the cell (the tongues' roots melt down past their base)
    bottom = np.where(y < -0.56, 1 - np.sqrt((x / 0.50) ** 2 + ((y + 0.56) / 0.30) ** 2), 1.0)
    heat *= smooth(0.0, 0.12, bottom)
    a = smooth(0.015, 0.05, heat)
    col = bands(heat, FLAME_STOPS)
    col, a = finish(col, a, 3)
    return to_image(col, a)


# --------------------------------------------------------------------------- main

def contact(frames, path, bgs=((22, 16, 34), (226, 216, 196))):
    w, h = frames[0].size
    sheet = Image.new('RGB', (w * 4 * len(bgs), h * 4))
    for b, bg in enumerate(bgs):
        for i, im in enumerate(frames):
            tile = Image.alpha_composite(Image.new('RGBA', (w, h), bg + (255,)), im)
            r, c = divmod(i, 4)
            sheet.paste(tile.convert('RGB'), (b * w * 4 + c * w, r * h))
    sheet.save(path)


def main():
    args = list(sys.argv[1:])
    frames_dir = None
    if '--frames' in args:
        i = args.index('--frames')
        frames_dir = os.path.expanduser(args[i + 1])
        del args[i:i + 2]
        os.makedirs(frames_dir, exist_ok=True)
    names = args or ['face', 'flame']
    os.makedirs(OUT, exist_ok=True)
    if 'face' in names:
        frames = [face_frame(f) for f in range(FRAMES)]
        sheet = pack(frames, 1024)
        path = os.path.join(OUT, 'fire_face_4x4.png')
        sheet.save(path, optimize=True)
        print('wrote', os.path.relpath(path, ROOT), '%dx%d' % sheet.size)
        if frames_dir:
            contact([im.resize((256, 256), Image.LANCZOS) for im in frames], os.path.join(frames_dir, 'face_contact.png'))
            for f in (0, 4, 8, 12):
                for name, bg in (('dark', (22, 16, 34)), ('cream', (226, 216, 196))):
                    tile = Image.alpha_composite(Image.new('RGBA', frames[f].size, bg + (255,)), frames[f])
                    tile.convert('RGB').save(os.path.join(frames_dir, 'face_%02d_%s.png' % (f, name)))
    if 'flame' in names:
        frames = [flame_frame(f) for f in range(FRAMES)]
        sheet = pack(frames, 512)
        path = os.path.join(OUT, 'toon_flame_4x4.png')
        sheet.save(path, optimize=True)
        print('wrote', os.path.relpath(path, ROOT), '%dx%d' % sheet.size)
        if frames_dir:
            contact([im.resize((128, 128), Image.LANCZOS) for im in frames], os.path.join(frames_dir, 'flame_contact.png'))


if __name__ == '__main__':
    main()
