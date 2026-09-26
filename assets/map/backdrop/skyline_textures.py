"""The skyline's sheet (textures/skyline_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/skyline_textures.py

Seen from 450 to 2,300 studs away, so it is drawn for distance: big calm features, strong
vertical window bands along U, no horizontal floor lines or fine window grids (they shimmer),
no noise, and PAD pixels clear at each strip edge.

Facade strips (s_glass, s_white, s_stone, s_terracotta) map V to height over the street (0 at
the street, 1 at FACADE_TOP studs up), so a whole wall is one quad and every building shares one
gradient: a soft cool shade at the foot, lighter toward the top, the glass reflecting the pale
sky higher up. Along U each facade strip is ZONES zones of ZONE studs, each a variant of the
style (its tone and window rhythm, the pattern centred on the zone's middle); skyline.py
centres every wall of a building in one zone, so a building keeps one variant all round and
neighbours can differ.

The other strips: s_accent (landmark crowns and caps: V over the piece, blue glass at its foot
to bright metal at its top), s_roof (flat roofs: V picks a tone, lighter and cooler toward the
top), s_paving and s_park (block tops), s_tree (tree blobs: V from the dark rim to the lit top).
The order keeps neighbours alike (distant mip levels blend a strip with the next).
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
ZONES = 4  # variants per facade strip; its U period is ZONE * ZONES
STRIPS = {
    # name: (first row, last row + 1 of a 1024 sheet, studs per image width along U)
    's_accent': (0, 64, 32.0),  # landmark crowns and caps: blue glass up to bright metal
    's_glass': (64, 256, ZONE * ZONES),  # blue glass curtain wall: fins and panel bands
    's_white': (256, 432, ZONE * ZONES),  # white tower: blue-grey window columns
    's_stone': (432, 608, ZONE * ZONES),  # cream stone: punched window columns
    's_terracotta': (608, 784, ZONE * ZONES),  # terracotta and brick: dark window columns
    's_roof': (784, 832, 256.0),  # flat roofs, lit: V picks the tone
    's_paving': (832, 880, 256.0),  # block tops: light warm paving
    's_park': (880, 944, 256.0),  # block tops and roof gardens: lawn, V picks the tone
    's_tree': (944, 1024, 16.0),  # tree blobs: dark at the rim, lit at the top
}

# ---------------------------------------------------------------------------------------------
# Colours: the art's (Palette.json and panels/city-side.jpg), kept clear and saturated because
# Roblox renders a little paler and greyer than painted
# ---------------------------------------------------------------------------------------------

SKY = mc.hexc('sky_horizon_day')  # #86C4FB: what the glass reflects near the top
SHADE = mc.ALBEDO['shadow']  # the painter's cool shade (#5D719E): every foot darkens toward it
FOOT_STUDS = 34.0  # the soft shade at a facade's foot fades out this high over the street
FOOT_SHADE = 0.3  # ...from this much toward SHADE at the street
LIFT = 0.14  # masonry walls this much toward white at FACADE_TOP (the lit upper floors)

# Glass variants: (glass, deeper panel, fin, bay studs, fin studs, sky reflection at the top).
GLASS = [
    ('#1C58B8', '#174A9E', '#5582C6', 4.0, 0.5, 0.32),  # the art's tower blue
    ('#1A4A96', '#143C7E', '#4A6EA8', 3.0, 0.45, 0.26),  # deep navy glass
    ('#2466C8', '#1D56AE', '#6A98D8', 5.0, 0.6, 0.4),  # bright sky-blue glass
    ('#1E5AB0', '#16448E', '#5A82C0', 6.0, 1.0, 0.3),  # wide ribbons of two blues
]
# Masonry variants: (wall, window, bay studs, window studs, paired). The windows are about a
# third of the bay and lighter than the art's grid, which at a distance reads as a light tone.
WHITE = [
    ('#F2EAE4', '#8E9AB6', 4.0, 1.2, False),  # warm white, narrow windows
    ('#EEEDEE', '#8498BC', 6.0, 2.0, False),  # white, wide glass columns
    ('#F4ECE2', '#96A0B8', 8.0, 1.5, True),  # cream white, paired windows
    ('#E8E4E4', '#8A98B4', 5.0, 1.5, False),  # light grey-white
]
STONE = [
    ('#E8D2B0', '#948E9C', 5.0, 1.6, False),  # cream stone
    ('#DEC6A4', '#8A8698', 4.0, 1.3, False),  # sand stone
    ('#EDDEC6', '#9C9CAC', 8.0, 1.5, True),  # pale limestone, paired windows
    ('#D9C8B2', '#9092A4', 6.0, 2.0, False),  # warm grey stone, wide windows
]
TERRACOTTA = [
    ('#DC8E72', '#685870', 4.0, 1.4, False),  # the art's salmon terracotta
    ('#C8745A', '#5C5068', 5.0, 1.7, False),  # deeper brick
    ('#E2A088', '#6C6278', 8.0, 1.6, True),  # pink terracotta, paired windows
    ('#D4906A', '#64586C', 6.0, 2.0, False),  # orange-tan brick
]
ACCENT = ('#3C82DC', '#B4CAE6', '#F4F7FB', 2.0, 0.35)  # glass, steel, bright top edge, fin every, fin width
ROOF = ('#CBC6C4', '#DAD8DE')  # the roof tones from frac 0 (warm) to frac 1 (light, cool)
PAVING = '#D8CEC4'  # lighter and warmer than the grey streets round it
PARK = ('#468E42', '#58A64C')  # the lawn tones from frac 0 to 1 (the near world's #4E9A48 between)
TREE = ('#2A5A30', '#3F8A38', '#86BC48')  # rim, middle, lit top


def _c(hex_colour):
    return np.array(mc.rgb(hex_colour), dtype=np.float64)


def _smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _lerp(a, b, t):
    """Colour arrays a, b (..., 3) blended by t (...)."""
    return a + (b - a) * np.asarray(t)[..., None]


def _band(p, period, width, soft=0.12):
    """1 inside bands `width` studs wide centred on every multiple of `period` along p (studs),
    with soft edges `soft` studs wide."""
    d = np.abs(p - np.round(p / period) * period)
    return 1.0 - _smooth(width / 2 - soft / 2, width / 2 + soft / 2, d)


def _foot(h):
    """How far toward SHADE at height h (studs over the street): the soft street-level shade."""
    return (1.0 - _smooth(0.0, FOOT_STUDS, h)) * FOOT_SHADE


def _zone_pos(u):
    """(zone index, studs from the zone's centre) for U positions u (studs)."""
    k = np.floor(u / ZONE).astype(int) % ZONES
    return k, u - (np.floor(u / ZONE) + 0.5) * ZONE


def _windows(p, bay, width, paired):
    """The window mask along a zone: columns every `bay` studs centred on the zone's centre, or
    pairs of them either side of a narrow pier."""
    if not paired:
        return _band(p, bay, width)
    gap = 0.9
    return np.maximum(_band(p - (gap + width) / 2, bay, width), _band(p + (gap + width) / 2, bay, width))


def glass_strip(frac, u):
    h = frac * FACADE_TOP
    k, p = _zone_pos(u)
    rows, cols = h.shape[0], u.shape[1]
    out = np.zeros((rows, cols, 3))
    sky = _c(SKY)
    t_up = _smooth(30.0, FACADE_TOP, h) ** 1.2  # (rows, 1)
    for z, (glass, deep, fin, bay, fin_w, reflect) in enumerate(GLASS):
        sel = (k[0] == z)
        pz = p[:, sel]
        g, d, f = _c(glass), _c(deep), _c(fin)
        # Panel columns a bay wide, centred on the zone's middle, fins at the joints between.
        cos = np.cos(np.pi * pz / bay)
        if z == 3:  # wide ribbons: alternate columns of two blues, crisp
            ribbon = _smooth(-0.2, 0.2, cos)
            panel = _lerp(np.broadcast_to(d, pz.shape + (3,)), g, ribbon)
        else:  # alternate columns of glass and deeper glass, softly: vertical bands
            panel = _lerp(np.broadcast_to(g, pz.shape + (3,)), d, (0.5 - 0.5 * cos) * 0.7)
        # A soft vertical reflection streak, off the zone's centre, the same on every wall.
        streak = np.exp(-((pz - ZONE * 0.18) / 7.0) ** 2) * 0.16
        panel = _lerp(panel, np.broadcast_to(sky, panel.shape), streak)
        fins = _band(pz + bay / 2, bay, fin_w, 0.15 if z != 3 else 0.3)
        col = _lerp(np.broadcast_to(panel, (rows,) + panel.shape[1:]), f, np.broadcast_to(fins * 0.85, (rows, pz.shape[1])))
        # Up the tower the glass reflects more of the pale sky; the foot sits in soft shade.
        col = _lerp(col, sky, np.broadcast_to(t_up * reflect, col.shape[:2]))
        col = _lerp(col, _c(SHADE), np.broadcast_to(_foot(h) * 1.2, col.shape[:2]))
        out[:, sel] = col
    return out


def masonry_strip(variants, frac, u):
    h = frac * FACADE_TOP
    k, p = _zone_pos(u)
    rows = h.shape[0]
    out = np.zeros((rows, u.shape[1], 3))
    sky, white, shade = _c(SKY), _c('#FFFFFF'), _c(SHADE)
    lift = _smooth(30.0, FACADE_TOP, h) * LIFT  # (rows, 1)
    reflect = _smooth(30.0, FACADE_TOP, h) * 0.35
    for z, (wall, win, bay, width, paired) in enumerate(variants):
        sel = (k[0] == z)
        pz = p[:, sel]
        n = pz.shape[1]
        wall_c = _lerp(np.broadcast_to(_c(wall), (rows, n, 3)), white, np.broadcast_to(lift, (rows, n)))
        win_c = _lerp(np.broadcast_to(_c(win), (rows, n, 3)), sky, np.broadcast_to(reflect, (rows, n)))
        mask = np.broadcast_to(_windows(pz, bay, width, paired), (rows, n))
        # The window columns stop short of the street: a solid base course under 5 studs.
        mask = mask * _smooth(3.0, 6.0, np.broadcast_to(h, (rows, n)))
        col = _lerp(wall_c, win_c, mask)
        col = _lerp(col, shade, np.broadcast_to(_foot(h), (rows, n)))
        out[:, sel] = col
    return out


def accent_strip(frac, u):
    glass, steel, top, every, fin_w = ACCENT
    rows = frac.shape[0]
    t = np.broadcast_to(frac, (rows, u.shape[1]))
    col = _lerp(np.broadcast_to(_c(glass), t.shape + (3,)), _c(SKY), _smooth(0.0, 0.6, t) * 0.55)
    col = _lerp(col, _c(steel), _smooth(0.55, 0.8, t))
    col = _lerp(col, _c(top), _smooth(0.86, 0.96, t))
    fins = np.broadcast_to(_band(u, every, fin_w, 0.1), t.shape) * (1 - _smooth(0.55, 0.8, t))
    return _lerp(col, _c(steel), fins * 0.7)


def ramp_strip(lo, hi, frac, u):
    t = np.broadcast_to(frac, (frac.shape[0], u.shape[1]))
    return _lerp(np.broadcast_to(_c(lo), t.shape + (3,)), _c(hi), t)


def tree_strip(frac, u):
    rim, mid, lit = TREE
    t = np.broadcast_to(frac, (frac.shape[0], u.shape[1]))
    col = _lerp(np.broadcast_to(_c(rim), t.shape + (3,)), _c(mid), _smooth(0.0, 0.45, t))
    return _lerp(col, _c(lit), _smooth(0.45, 1.0, t))


PAINTERS = {
    's_accent': accent_strip,
    's_glass': glass_strip,
    's_white': lambda f, u: masonry_strip(WHITE, f, u),
    's_stone': lambda f, u: masonry_strip(STONE, f, u),
    's_terracotta': lambda f, u: masonry_strip(TERRACOTTA, f, u),
    's_roof': lambda f, u: ramp_strip(ROOF[0], ROOF[1], f, u),
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
