"""The skyline's sheet (textures/skyline_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/skyline_textures.py

Seen from 450 to 2,300 studs away (and on a phone), so it is drawn for distance: big calm
features, no vertical stripes or fine window grids (they read as corrugated sheet and shimmer),
no noise, and PAD pixels clear at each strip edge.

Facade strips (s_glass, s_white, s_stone, s_terracotta) map V to height over the street (0 at
the street, 1 at FACADE_TOP studs up), so a whole wall is one quad and every building shares one
gradient: a soft cool shade at the foot, lighter toward the top. Glass is a desaturated steel
grey-blue, darker at the foot and lighter up the tower, with only a very faint mullion (it must
not match the gameplay's blue arrows and rings). White, stone and terracotta have faint
HORIZONTAL window bands, one per floor (a variant's floor height, 10 to 13 studs; the same
heights on every building of that variant), about BAND darker than the wall. The masonry strips
are the tallest, so a floor spans about five texels. Along U each facade strip is ZONES zones of
ZONE studs: the first LIGHT are the style's variants (tone and floor height), the next LIGHT the
same variants a little lighter, for crowns, caps and rooftop boxes (skyline.py centres every
wall of a building in one zone, so a building keeps one variant all round).

The rest: s_roof (flat roofs: V picks a tone), s_accent (masts and spires: light steel),
s_paving and s_park (block tops, lawns), s_tree (canopies, the #3E6B3A family: V from the dark
rim to the lit top, U in TREE_TONES zones of TREE_ZONE studs, one green each). The order keeps
neighbours alike (distant mip levels blend a strip with the next, and the sheet wraps).
"""

import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import map_common as mc  # noqa: E402

IMAGE = 'skyline_color.png'
SEED = 5101
PAD = 8
FACADE_TOP = 560.0  # studs over the street at the top of a facade strip
ZONE = 72.0  # studs: one facade variant along U (no wall in the plan is wider)
LIGHT = 4  # variants per facade style; zone k + LIGHT is variant k, lighter (crowns and caps)
ZONES = 2 * LIGHT  # zones per facade strip; its U period is ZONE * ZONES
TREE_ZONE = 128.0  # studs: one canopy green along U (a canopy's rim is never longer)
TREE_TONES = 4
STRIPS = {
    # name: (first row, last row + 1 of a 1024 sheet, studs per image width along U)
    's_roof': (0, 48, 256.0),  # flat roofs, lit: V picks the tone
    's_accent': (48, 80, 32.0),  # masts and spires: light steel
    's_glass': (80, 176, ZONE * ZONES),  # steel grey-blue glass: a gradient only, so short
    's_white': (176, 400, ZONE * ZONES),  # warm white: faint floor bands
    's_stone': (400, 624, ZONE * ZONES),  # cream stone: faint floor bands
    's_terracotta': (624, 848, ZONE * ZONES),  # muted terracotta: faint floor bands
    's_paving': (848, 880, 256.0),  # block tops: light warm paving
    's_park': (880, 928, 256.0),  # block tops, roof gardens and tree lots: lawn, V picks the tone
    's_tree': (928, 1024, TREE_ZONE * TREE_TONES),  # canopies: dark rim to lit top, a green per zone
}

# ---------------------------------------------------------------------------------------------
# Colours: the art's (Palette.json, panels/city-side.jpg) and the art director's review, kept
# clear because Roblox renders a little paler and greyer than painted
# ---------------------------------------------------------------------------------------------

SKY = mc.hexc('sky_horizon_day')  # #86C4FB
SHADE = mc.ALBEDO['shadow']  # the painter's cool shade (#5D719E): every foot darkens toward it
FOOT_STUDS = 34.0  # the soft shade at a facade's foot fades out this high over the street
FOOT_SHADE = 0.28  # ...from this much toward SHADE at the street
LIFT = 0.1  # masonry walls this much toward white at FACADE_TOP (the lit upper floors)
BAND = 0.08  # a floor's window band is this much darker than its wall (the review: about 8%)
BAND_TINT = 0.3  # ...and this far toward its style's window hue, at the same lightness
BAND_SILL, BAND_HEAD = 0.34, 0.86  # the band's foot and top, as fractions of a floor
BAND_SOFT = 0.12  # its edges soften over this much of a floor (no hard lines to shimmer)
LIGHTER = 0.13  # the lighter zones: this far toward white (masonry) or pale steel (glass)
PALE_STEEL = '#C8D4E0'

# Glass variants, a desaturated steel grey-blue (the review: #6F8FB2 at the foot to #A9BED2 at
# the top): (foot, top). No bands.
GLASS = [
    ('#6F8FB2', '#A9BED2'),
    ('#6887A8', '#A0B6CB'),  # a little deeper
    ('#7896B8', '#B2C5D6'),  # a little lighter
    ('#6D8AA6', '#A6B9CA'),  # greyer
]
GLASS_TOP_POWER = 0.85  # the gradient's curve up the tower (under 1: it lightens early)
MULLION = (8.0, 0.9, 0.02)  # a very faint lighter line: every, studs wide, how much lighter
# Masonry variants: (wall, window hue, floor height in studs). Faint horizontal window bands.
WHITE = [
    ('#F5E8DA', '#8E9AB6', 12.0),  # warm white
    ('#F2EAE1', '#8498BC', 10.5),  # white
    ('#F7EADB', '#96A0B8', 13.0),  # cream white
    ('#EDE3D9', '#8A98B4', 11.5),  # light warm grey-white
]
STONE = [
    ('#E8D2B0', '#948E9C', 12.5),  # cream stone
    ('#DEC6A4', '#8A8698', 11.0),  # sand stone
    ('#EDDEC6', '#9C9CAC', 13.0),  # pale limestone
    ('#D9C8B2', '#9092A4', 10.5),  # warm grey stone
]
TERRACOTTA = [
    ('#B08A70', '#6E5A56', 11.5),  # muted terracotta (the review: toward #B08A70)
    ('#A67E66', '#665250', 12.5),  # deeper
    ('#BA947A', '#76625C', 10.5),  # pinker tan
    ('#B28868', '#6C5854', 13.0),  # warmer brick
]
ACCENT = ('#98A6B8', '#E2E8EF')  # masts and spires: steel at the foot, light at the top
ROOF = ('#CBC6C4', '#DAD8DE')  # the roof tones from frac 0 (warm) to frac 1 (light, cool)
PAVING = '#D8CEC4'  # lighter and warmer than the grey streets round it
PARK = ('#4A8240', '#5A9A4A')  # the lawn tones from frac 0 to 1
TREES = [
    # (rim, middle, lit top): a canopy's green, one per tree zone along U (the #3E6B3A family)
    ('#2A4A2A', '#3E6B3A', '#6E955A'),
    ('#26442A', '#3A6438', '#648C50'),  # deeper
    ('#30502C', '#46733C', '#7A9E5C'),  # a little yellower
    ('#284A34', '#3C6A44', '#6A9660'),  # a little bluer
]


def _c(hex_colour):
    return np.array(mc.rgb(hex_colour), dtype=np.float64)


def _luma(c):
    return 0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2]


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _lerp(a, b, t):
    """Colour arrays a, b (..., 3) blended by t (...)."""
    return a + (b - a) * np.asarray(t)[..., None]


def _band(p, period, width, soft):
    """1 inside bands `width` studs wide centred on every multiple of `period` along p (studs),
    with soft edges `soft` studs wide."""
    d = np.abs(p - np.round(p / period) * period)
    return 1.0 - _smooth(width / 2 - soft / 2, width / 2 + soft / 2, d)


def _foot(h):
    """How far toward SHADE at height h (studs over the street): the soft street-level shade."""
    return (1.0 - _smooth(0.0, FOOT_STUDS, h)) * FOOT_SHADE


def _zone_pos(u, zone, zones):
    """(zone index, studs from the zone's centre) for U positions u (studs)."""
    k = np.floor(u / zone).astype(int) % zones
    return k, u - (np.floor(u / zone) + 0.5) * zone


def band_colour(wall, hue):
    """A window band's colour: BAND darker than the wall, BAND_TINT of the way to the window's
    hue at that same lightness (so the difference is lightness, not a loud colour)."""
    w, h = _c(wall), _c(hue)
    target = _luma(w) * (1 - BAND)
    dark = w * (1 - BAND)
    tinted = h * target / max(_luma(h), 1.0)
    return dark + (tinted - dark) * BAND_TINT


def lighter(colour, toward='#FFFFFF'):
    return colour + (_c(toward) - colour) * LIGHTER


def glass_strip(frac, u):
    h = frac * FACADE_TOP
    k, p = _zone_pos(u, ZONE, ZONES)
    rows = h.shape[0]
    out = np.zeros((rows, u.shape[1], 3))
    t = np.clip(h / (FACADE_TOP * 0.96), 0.0, 1.0) ** GLASS_TOP_POWER  # (rows, 1)
    every, width, amount = MULLION
    for z in range(ZONES):
        sel = (k[0] == z)
        n = int(sel.sum())
        foot, top = (_c(c) for c in GLASS[z % LIGHT])
        if z >= LIGHT:
            foot, top = lighter(foot, PALE_STEEL), lighter(top, PALE_STEEL)
        col = _lerp(np.broadcast_to(foot, (rows, n, 3)), top, np.broadcast_to(t, (rows, n)))
        mull = np.broadcast_to(_band(p[:, sel] + every / 2, every, width, 0.6) * amount, (rows, n))
        col = _lerp(col, _c('#FFFFFF'), mull)
        col = _lerp(col, _c(SHADE), np.broadcast_to(_foot(h) * 1.2, (rows, n)))
        out[:, sel] = col
    return out


def masonry_strip(variants, frac, u):
    h = frac * FACADE_TOP
    k, _ = _zone_pos(u, ZONE, ZONES)
    rows = h.shape[0]
    out = np.zeros((rows, u.shape[1], 3))
    white, shade = _c('#FFFFFF'), _c(SHADE)
    lift = _smooth(30.0, FACADE_TOP, h) * LIFT  # (rows, 1)
    for z in range(ZONES):
        wall_hex, hue, floor = variants[z % LIGHT]
        sel = (k[0] == z)
        n = int(sel.sum())
        wall, win = _c(wall_hex), band_colour(wall_hex, hue)
        if z >= LIGHT:
            wall, win = lighter(wall), lighter(win)
        # One soft window band per floor, between its sill and its head; none in the base
        # course under the first floor.
        f = (h / floor) % 1.0
        band = _smooth(BAND_SILL - BAND_SOFT, BAND_SILL, f) * (1 - _smooth(BAND_HEAD, BAND_HEAD + BAND_SOFT, f))
        band = band * _smooth(floor * 0.6, floor, h)
        col = _lerp(np.broadcast_to(wall, (rows, n, 3)), win, np.broadcast_to(band, (rows, n)))
        col = _lerp(col, white, np.broadcast_to(lift, (rows, n)))
        col = _lerp(col, shade, np.broadcast_to(_foot(h), (rows, n)))
        out[:, sel] = col
    return out


def ramp_strip(lo, hi, frac, u):
    t = np.broadcast_to(frac, (frac.shape[0], u.shape[1]))
    return _lerp(np.broadcast_to(_c(lo), t.shape + (3,)), _c(hi), t)


def tree_strip(frac, u):
    k, _ = _zone_pos(u, TREE_ZONE, TREE_TONES)
    rows = frac.shape[0]
    out = np.zeros((rows, u.shape[1], 3))
    for z, (rim, mid, lit) in enumerate(TREES):
        sel = (k[0] == z)
        t = np.broadcast_to(frac, (rows, int(sel.sum())))
        col = _lerp(np.broadcast_to(_c(rim), t.shape + (3,)), _c(mid), _smooth(0.0, 0.45, t))
        out[:, sel] = _lerp(col, _c(lit), _smooth(0.45, 1.0, t))
    return out


PAINTERS = {
    's_roof': lambda f, u: ramp_strip(ROOF[0], ROOF[1], f, u),
    's_accent': lambda f, u: ramp_strip(ACCENT[0], ACCENT[1], f, u),
    's_glass': glass_strip,
    's_white': lambda f, u: masonry_strip(WHITE, f, u),
    's_stone': lambda f, u: masonry_strip(STONE, f, u),
    's_terracotta': lambda f, u: masonry_strip(TERRACOTTA, f, u),
    's_paving': lambda f, u: ramp_strip(PAVING, PAVING, f, u),
    's_park': lambda f, u: ramp_strip(PARK[0], PARK[1], f, u),
    's_tree': tree_strip,
}


def draw(rng, size):
    """The sheet at size x size (RGB, 0..255). Each strip is painted as a function of its
    height fraction (trim_v's mapping: 0 at the strip's foot, 1 at its top, held flat across
    the PAD rows at either edge) and of U in studs."""
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    rows_done = 0
    for name, (top, bottom, studs) in STRIPS.items():
        r0, r1 = int(round(top * s)), int(round(bottom * s))
        rows = (np.arange(r0, r1) + 0.5) / s  # sheet rows in 1024 units
        frac = np.clip(((bottom - PAD) - rows) / (bottom - top - 2 * PAD), 0.0, 1.0)[:, None]
        u = ((np.arange(size) + 0.5) / size * studs)[None, :]
        img[r0:r1] = PAINTERS[name](frac, u)
        rows_done += r1 - r0
    assert rows_done == size, 'the strips must fill the sheet'
    return np.clip(img, 0.0, 255.0)


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(HERE))
    import gen_textures
    gen_textures.write_backdrop_sheet('skyline')
