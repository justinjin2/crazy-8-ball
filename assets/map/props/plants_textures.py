"""The plants atlas (textures/plants.png): a palm frond, a fern frond and a round leafy clump,
drawn as flat two-tone vector leaves (a lit half and a narrower shade half on every leaflet)
from the measured greens only.

gen_textures.plants() calls draw(rng, 2048) and exports the result at 1024 (premultiplied, a
green bleed under clear pixels). The regions are map_common.PLANTS in Blender UVs (v up; image
row 0 is the top):

    frond  the top half: a palm frond, its rachis on the region's horizontal centre line, the
           base at the left edge and the tip at the right; its leaflets reach FROND_BAND / 2 of
           the region's height either side of the rachis.
    fern   the bottom-left quarter: a fern frond the same way round, inside FERN_BAND of the
           quarter's height (centred), so a card needs only that band.
    clump  the bottom-right quarter: a leafy mound seen from above, filling a rounded square
           (a square card covers square soil), lit from the top left, darker toward its rim.

Every frond runs from MARGIN to 1 - MARGIN of its region's width. props/plants.py repeats
MARGIN, FROND_BAND and FERN_BAND to map its cards onto exactly these extents.
"""

import numpy as np
from PIL import Image, ImageDraw

import map_common as mc

MARGIN = 0.006  # each frond's base and tip this far in from its region's left and right edges
FROND_BAND = 0.96  # the palm frond's leaflets span this much of the top half's height
FERN_BAND = 0.44  # the fern frond spans this much of its quarter's height


def _c(name):
    return np.array(mc.rgb(mc.hexc(name)), dtype=np.float64)


# The measured stops (Palette.json). Mixes of these only; the lit halves favour the brightest.
LEAF_LIT, LEAF_MID, LEAF_DARK = _c('leaf_lit'), _c('leaf_mid'), _c('leaf_dark')
PALM_LIT, PALM_MID = _c('palm_lit'), _c('palm_mid')
TRUNK = _c('palm_trunk')


def _mix(a, b, t):
    return a + (b - a) * float(np.clip(t, 0.0, 1.0))


def _fill(colour):
    return tuple(int(round(v)) for v in np.clip(colour, 0, 255)) + (255,)


def _leaf(p0, heading, length, width, bend, steps=12, base=0.18, power=0.8):
    """A curved, pointed leaf from p0 (image px, y down), heading `heading` radians at its
    foot and turned by `bend` radians at its tip. Returns (centre, plus, minus): its centre
    line and the two edges, `plus` being the side of the normal (-sin, cos) of the heading."""
    x, y = p0
    ds = length / steps
    centre, plus, minus = [], [], []
    for k in range(steps + 1):
        s = k / steps
        a = heading + bend * s
        half = width / 2 * max(np.sin(np.pi * (base + (1 - base) * s)), 0.0) ** power
        nx, ny = -np.sin(a), np.cos(a)
        centre.append((x, y))
        plus.append((x + nx * half, y + ny * half))
        minus.append((x - nx * half, y - ny * half))
        x += ds * np.cos(a + bend / steps / 2)
        y += ds * np.sin(a + bend / steps / 2)
    return centre, plus, minus


def _two_tone(draw, centre, lit_edge, shade_edge, lit, shade, shade_width=0.7):
    """Draw a leaf's shade half (narrowed to shade_width of its width) then its lit half."""
    narrow = [(cx + (ex - cx) * shade_width, cy + (ey - cy) * shade_width)
              for (cx, cy), (ex, ey) in zip(centre, shade_edge)]
    draw.polygon(centre + narrow[::-1], fill=_fill(shade))
    draw.polygon(centre + lit_edge[::-1], fill=_fill(lit))


def _pinnate(draw, rng, x0, x1, yc, reach, spec):
    """A pinnate frond from x0 (base) to x1 (tip) along the row yc: leaflets both sides, each
    lit on its tip-ward half, then the rachis over them."""
    length = x1 - x0
    n = spec['count']
    if spec.get('underlay'):
        # A solid blade under the leaflets (a fern's merged pinnae), in the shade tone.
        ts = np.linspace(0.0, 1.0, 48)
        taper = np.minimum(1.0, ts / 0.12) ** 0.7 * np.minimum(1.0, (1.0 - ts) / 0.2) ** 0.8
        top = [(x0 + t * length, yc - reach * spec['underlay'] * np.interp(t, spec['env_t'], spec['env']) * k)
               for t, k in zip(ts, taper)]
        bottom = [(x, 2 * yc - y) for x, y in top]
        draw.polygon(top + bottom[::-1], fill=_fill(spec['shade'](0.6)))
    for i in range(n):
        for side in (-1, 1):  # -1: the upper row (image up), +1: the lower row
            t = spec['t0'] + (spec['t1'] - spec['t0']) * (i + (0.5 if side > 0 else 0.0)) / n
            env = np.interp(t, spec['env_t'], spec['env'])
            alpha = np.radians(np.interp(t, (0.0, 1.0), spec['angle']) + rng.uniform(-3, 3))
            bend = np.radians(spec['bend'])
            thick = np.interp(t, (0.0, 1.0), spec['rachis']) / 2
            ax, ay = x0 + t * length, yc + side * thick * 0.6
            heading = side * alpha
            turn = -side * bend  # toward +x, the frond's tip
            mean = alpha - bend / 2
            size = (reach - thick) * env / max(np.sin(mean), 0.2)
            # Keep the leaflet's tip inside the region.
            size = min(size, (x1 - ax) / max(np.cos(mean), 0.3))
            if size < 8:
                continue
            width = spec['width'] * (0.7 + 0.3 * env)
            centre, plus, minus = _leaf((ax, ay), heading, size, width, turn)
            # The tip-ward (+x facing) side is lit.
            plus_faces_tip = -np.sin(heading) > 0
            lit_edge, shade_edge = (plus, minus) if plus_faces_tip else (minus, plus)
            glint = rng.uniform(-0.08, 0.08)
            _two_tone(draw, centre, lit_edge, shade_edge, spec['lit'](t, glint), spec['shade'](t),
                      spec['shade_width'])
    # The rachis: a tapered stem in short pieces, its colour running base to tip.
    pieces = 24
    for k in range(pieces):
        ta, tb = k / pieces, (k + 1) / pieces
        ha = np.interp(ta, (0.0, 1.0), spec['rachis']) / 2
        hb = np.interp(tb, (0.0, 1.0), spec['rachis']) / 2
        xa, xb = x0 + ta * length, x0 + tb * length + (1 if k < pieces - 1 else 0)
        draw.polygon([(xa, yc - ha), (xb, yc - hb), (xb, yc + hb), (xa, yc + ha)],
                     fill=_fill(spec['stem']((ta + tb) / 2)))


def _palm_frond(draw, rng, s):
    rw, rh = s, s // 2
    x0, x1 = MARGIN * rw, (1 - MARGIN) * rw
    yc = rh / 2
    spec = {
        'count': 30, 't0': 0.07, 't1': 0.95,
        'env_t': (0.07, 0.16, 0.3, 0.5, 0.72, 0.9, 0.98),
        'env': (0.42, 0.78, 0.97, 1.0, 0.82, 0.45, 0.18),
        'angle': (62.0, 32.0),  # the leaflets' angle from the rachis, base to tip
        'bend': 16.0,  # each leaflet sweeps this much further toward the tip
        'width': 0.03 * s,
        'rachis': (0.024 * s, 0.004 * s),
        'shade_width': 0.72,
        # Lit: palm_mid at the base (inside the crown), palm_lit, then toward leaf_lit at the tip.
        'lit': lambda t, g: (_mix(PALM_MID, PALM_LIT, t / 0.22 + g) if t < 0.22
                             else _mix(PALM_LIT, LEAF_LIT, (t - 0.22) / 0.78 * 0.7 + g)),
        'shade': lambda t: _mix(_mix(PALM_MID, LEAF_DARK, 0.45), PALM_MID, t / 0.35),
        'stem': lambda t: (_mix(_mix(PALM_MID, TRUNK, 0.45), PALM_MID, t / 0.12) if t < 0.12
                           else _mix(PALM_MID, LEAF_LIT, (t - 0.12) / 0.4)),
    }
    reach = FROND_BAND / 2 * rh
    _pinnate(draw, rng, x0, x1, yc, reach, spec)


def _fern_frond(draw, rng, s):
    q = s // 2
    x0, x1 = MARGIN * q, (1 - MARGIN) * q
    yc = q + q / 2
    spec = {
        # Short, wide pinnae over a solid blade: the art's broad fern frond with a sawtooth
        # edge (not a palm's long leaflets).
        'count': 22, 't0': 0.04, 't1': 0.97,
        'env_t': (0.04, 0.14, 0.32, 0.55, 0.78, 0.92, 0.99),
        'env': (0.4, 0.8, 1.0, 0.95, 0.66, 0.36, 0.1),
        'angle': (72.0, 44.0),
        'bend': 12.0,
        'width': 0.034 * s,
        'rachis': (0.011 * s, 0.003 * s),
        'shade_width': 0.5,
        'underlay': 0.62,
        # Lit: toward leaf_lit quickly (the art's bright yellow-green fern), leaf_mid at the foot.
        'lit': lambda t, g: _mix(_mix(LEAF_MID, LEAF_LIT, 0.55), LEAF_LIT, t / 0.35 + g),
        'shade': lambda t: _mix(_mix(LEAF_MID, LEAF_DARK, 0.2), _mix(LEAF_MID, LEAF_LIT, 0.5), t / 0.7),
        'stem': lambda t: _mix(LEAF_MID, _mix(LEAF_LIT, LEAF_MID, 0.2), t / 0.5),
    }
    reach = FERN_BAND / 2 * q
    _pinnate(draw, rng, x0, x1, yc, reach, spec)


def _clump(draw, rng, s):
    """A bushy mound seen from above, filling a rounded square (so a square card covers square
    soil to its corners): a dark heart, then rings of short leaves, the outer ones darker and
    drawn first so the lighter middle sits on top like a dome lit from the top left."""
    q = s // 2
    cx, cy = q + q / 2, q + q / 2
    half = 0.485 * q
    power = 3.5  # the outline: |x|^p + |y|^p = half^p

    def reach(a):
        return half / (abs(np.cos(a)) ** power + abs(np.sin(a)) ** power) ** (1 / power)

    heart = [(cx + 0.55 * reach(a) * np.cos(a), cy + 0.55 * reach(a) * np.sin(a))
             for a in np.linspace(0, 2 * np.pi, 64, endpoint=False)]
    draw.polygon(heart, fill=_fill(_mix(LEAF_MID, LEAF_DARK, 0.45)))
    leaves = []
    # Rings of short leaves, evenly spaced with a little jitter: (count, foot, length) as
    # fractions of the outline's reach in each direction.
    for count, foot, length in ((32, 0.5, 0.5), (26, 0.33, 0.48), (18, 0.17, 0.44), (11, 0.04, 0.36),
                                (6, 0.0, 0.24)):
        phase = rng.uniform(0, 1)
        for k in range(count):
            a = 2 * np.pi * (k + phase) / count + rng.uniform(-0.1, 0.1)
            heading = a + rng.uniform(-0.35, 0.35)
            edge = reach(a)
            r = edge * foot * rng.uniform(0.9, 1.1)
            ln = edge * length * rng.uniform(0.9, 1.05)
            ln = min(ln, (edge - r) / max(np.cos(heading - a), 0.5))
            leaves.append((r / edge, r, a, heading, ln, rng.uniform(0.36, 0.44), rng.uniform(-0.3, 0.3),
                           rng.uniform(-0.06, 0.06)))
    for depth, r, a, heading, ln, wf, bend, g in sorted(leaves, key=lambda leaf: -leaf[0]):
        depth = min(depth / 0.55, 1.0)  # 0 at the middle, 1 at the rim
        lit = _mix(LEAF_LIT, _mix(LEAF_MID, LEAF_LIT, 0.3), depth * 0.9 + g)
        shade = _mix(_mix(LEAF_MID, LEAF_LIT, 0.25), _mix(LEAF_MID, LEAF_DARK, 0.4), depth)
        px, py = cx + r * np.cos(a), cy + r * np.sin(a)
        centre, plus, minus = _leaf((px, py), heading, ln, ln * wf, bend)
        nx, ny = -np.sin(heading), np.cos(heading)
        plus_lit = (-nx - ny) > 0  # the half facing the top left (the light) is lit
        lit_edge, shade_edge = (plus, minus) if plus_lit else (minus, plus)
        _two_tone(draw, centre, lit_edge, shade_edge, lit, shade, 0.85)


def draw(rng, size):
    """The plants atlas: (size, size, 4) floats, RGB 0..255 and alpha 0..1."""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    pen = ImageDraw.Draw(canvas)
    _palm_frond(pen, rng, size)
    _fern_frond(pen, rng, size)
    _clump(pen, rng, size)
    arr = np.asarray(canvas).astype(np.float64)
    out = arr.copy()
    out[..., 3] = arr[..., 3] / 255.0
    return out
