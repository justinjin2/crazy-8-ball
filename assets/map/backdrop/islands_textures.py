"""The islands' sheet (textures/islands_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy, PIL), no bpy: gen_textures.py calls draw(), and running this file writes the sheet
alone:

    python3 assets/map/backdrop/islands_textures.py

Seen from 900 to 2,500 studs away, so it is calm: no noise, nothing fine enough to shimmer.
    i_sand, i_rock, i_trunk, i_palm  strips even along U, V a ramp (islands.py sets V per
            vertex: i_rock by height over the sea, land_v with V_ROCK)
    i_land  the islands' ground: one tile per island (islands.make_islands packs them with
            pack_tiles), the island seen from above at STUDS_PER_PX, painted from its own
            shape (islands.Island.fields): rock and the greens blended where they lie (dark
            gullies, the slopes, lit canopy on ridges and crowns), shaded gently by height
            (land_v, V_TOP), and a lumpy tree canopy (canopy: packed round crowns lit in the
            middle, darker gaps, soft broad patches) so the slopes read as jungle, not grass.
            The islands are shaded smooth, and the tiles are continuous, so nothing shows a
            face's edge.
Colours from the art's ocean panel and Palette.json: the art's deep jungle greens (#3A6B42 to
#5A8A4E, the canopy tops a little lighter), the measured mauve rock turned greyer and browner
(half island_rock, half #7A6E62: the pure mauve read lilac in the game), warm sand.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import map_common as mc  # noqa: E402

IMAGE = 'islands_color.png'
SEED = 5201
PAD = 8
STRIPS = {
    # name: (first row, last row + 1 of a 1024 sheet, studs per image width along U). Ordered
    # so neighbours are alike (distant mip levels blend a strip with its neighbours).
    'i_sand': (0, 64, 2048.0),  # beaches: wet at the waterline (V 0), dry at the jungle (V 1)
    'i_rock': (64, 160, 2048.0),  # rock: crags and the shore's cliffs (V: land_v, V_ROCK)
    'i_trunk': (160, 192, 256.0),  # palm trunks: shaded foot (V 0), lit under the crown (V 1)
    'i_palm': (192, 256, 256.0),  # palm fronds: darker at the stem (V 0), lit at the tips (V 1)
    'i_land': (256, 1024, 1.0),  # the islands' tiles (pack_tiles; not sampled as a strip)
}
STUDS_PER_PX = 1.5  # the land tiles' scale, studs per pixel of the 1024 sheet
GUTTER = 8  # pixels round each tile, painted with its edge's colours (mip levels blend neighbours)
V_TOP = 330.0  # studs over the sea where the ground's height shade tops out (the tallest summit is 320)
V_ROCK = 140.0  # and i_rock's V 1, so low crags still span its ramp
CANOPY = {
    # Tree crowns: round and packed (one per jittered cell of a grid), lit in the middle, the
    # gaps between them darker, each crown a little lighter or darker than the next...
    'spacing': 22.0,  # studs between crowns: big enough to read at 1,500 studs
    'crown': (0.15, 0.62),  # a crown's lit middle and its edge, as a fraction of the spacing
    'contrast': 0.16,  # the lightness from a gap to a lit crown (low: about 10% either way)
    'vary': 0.5,  # how much crowns differ from one another
    # ...and a few broad, soft patches of lighter and darker jungle over them.
    'patch_spacing': 70.0,  # studs between patches
    'patch_radius': (30.0, 60.0),
    'patch_contrast': 0.04,  # a fraction either way per standard deviation
}
SAMPLE_PX = 2  # the painter samples each island's shape every this many sheet pixels


def land_v(height, top=V_TOP):
    """A ramp's V fraction for a height over the sea (the ground: top V_TOP; i_rock: V_ROCK)."""
    return 0.04 + 0.92 * max(0.0, min(1.0, height / top))


def hexmix(a, b, t):
    return '#%02X%02X%02X' % tuple(int(round(c)) for c in mc.mix(mc.rgb(a), mc.rgb(b), t))


ROCK = hexmix(mc.hexc('island_rock'), '#7A6E62', 0.5)  # the coordinator's grey mauve-brown

# Each ramp: (V, colour) stops, V 0 at the foot.
RAMPS = {
    'i_sand': [(0.0, '#D6BFA1'), (0.3, '#E8CFAE'), (1.0, '#F0D7B6')],
    'i_rock': [(0.0, hexmix(ROCK, '#000000', 0.14)), (0.45, ROCK), (1.0, hexmix(ROCK, '#FFFFFF', 0.1))],
    'i_trunk': [(0.0, '#6A5044'), (1.0, '#8C6E5C')],
    'i_palm': [(0.0, '#3E6A2E'), (1.0, '#5E8A3E')],
    # The ground's greens (V by land_v): deep jungle, the gullies a step darker, the canopy a
    # step lighter at the tops. Not lime.
    'gully': [(0.0, '#3B673F'), (1.0, '#437447')],
    'jungle': [(0.0, '#426F46'), (1.0, '#528650')],
    'canopy': [(0.0, '#548650'), (1.0, '#65965A')],
}


def ramp(stops, v):
    """Colours (..., 3) along a ramp's (V, hex) stops."""
    xs = [s for s, _ in stops]
    cols = np.array([mc.rgb(c) for _, c in stops], dtype=np.float64)
    return np.stack([np.interp(v, xs, cols[:, k]) for k in range(3)], axis=-1)


def pack_tiles(sizes):
    """Shelf-pack tiles (w, h: pixels of the 1024 sheet, gutters included) into i_land,
    tallest first; [(x, y, w, h)] in the order given."""
    top = STRIPS['i_land'][0]
    order = sorted(range(len(sizes)), key=lambda i: (-sizes[i][1], i))
    out = [None] * len(sizes)
    x, y, shelf = 0, top, 0
    for i in order:
        w, h = sizes[i]
        if x + w > mc.TRIM_PX:
            x, y, shelf = 0, y + shelf, 0
        assert y + h <= mc.TRIM_PX and w <= mc.TRIM_PX, ('the island tiles overflow the sheet', sizes)
        out[i] = (x, y, w, h)
        x, shelf = x + w, max(shelf, h)
    return out


def upsample(coarse, ys, xs, rows, cols):
    """Bilinear: values on a coarse grid (ys x xs positions) at finer positions."""
    along = np.stack([np.interp(cols, xs, line) for line in coarse])
    return np.stack([np.interp(rows, ys, along[:, c]) for c in range(len(cols))], axis=1)


def canopy(rng, wx, wz):
    """The jungle's lightness over a tile (world studs wx along columns, wz along rows), about
    1: packed round tree crowns (the nearest of a jittered grid of crown centres), each lit in
    its middle, with darker gaps, and a few broad soft patches over them."""
    sp = CANOPY['spacing']
    gx0, gz0 = int(math.floor(wx[0] / sp)) - 1, int(math.floor(wz[0] / sp)) - 1
    nx, nz = int(math.ceil((wx[-1] - wx[0]) / sp)) + 4, int(math.ceil((wz[-1] - wz[0]) / sp)) + 4
    jitter = rng.uniform(0.15, 0.85, (nz, nx, 2))
    tone = rng.uniform(1 - CANOPY['vary'], 1 + CANOPY['vary'], (nz, nx))
    ix = np.floor(wx / sp).astype(int) - gx0
    iz = np.floor(wz / sp).astype(int) - gz0
    best = np.full((len(wz), len(wx)), np.inf)
    shade = np.ones_like(best)
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            ci, cj = np.clip(ix + di, 0, nx - 1), np.clip(iz + dj, 0, nz - 1)
            px = (gx0 + ci[None, :] + jitter[cj[:, None], ci[None, :], 0]) * sp
            pz = (gz0 + cj[:, None] + jitter[cj[:, None], ci[None, :], 1]) * sp
            d2 = (wx[None, :] - px) ** 2 + (wz[:, None] - pz) ** 2
            nearer = d2 < best
            best = np.where(nearer, d2, best)
            shade = np.where(nearer, tone[cj[:, None], ci[None, :]], shade)
    f1 = np.sqrt(best) / sp
    lo, hi = CANOPY['crown']
    t = np.clip((f1 - lo) / (hi - lo), 0.0, 1.0)
    crown = 1 - t * t * (3 - 2 * t)  # 1 in a crown's middle, 0 in the gaps
    crowns = crown * shade
    light = 1 + CANOPY['contrast'] * (crowns - crowns.mean())
    patches = np.zeros_like(best)
    area = (wx[-1] - wx[0]) * (wz[-1] - wz[0])
    for _ in range(max(1, int(area / CANOPY['patch_spacing'] ** 2))):
        bx, bz = rng.uniform(wx[0], wx[-1]), rng.uniform(wz[0], wz[-1])
        r = rng.uniform(*CANOPY['patch_radius'])
        i0, i1 = np.searchsorted(wx, bx - 3 * r), np.searchsorted(wx, bx + 3 * r)
        j0, j1 = np.searchsorted(wz, bz - 3 * r), np.searchsorted(wz, bz + 3 * r)
        dx, dz = wx[i0:i1] - bx, wz[j0:j1] - bz
        patches[j0:j1, i0:i1] += rng.choice((-1.0, 1.0)) * np.exp(-(dz[:, None] ** 2 + dx[None, :] ** 2) / r ** 2)
    patches = (patches - patches.mean()) / (patches.std() + 1e-9)
    return light * (1 + CANOPY['patch_contrast'] * np.clip(patches, -2.0, 2.0))


def paint_tile(img, s, isle, rng):
    """One island's tile at scale s (pixels per 1024-sheet pixel): its shape sampled every
    SAMPLE_PX, blended to colours, the canopy laid over the greens, written into img."""
    x, y, w, h = isle.tile
    X0, Y0, W, H = int(round(x * s)), int(round(y * s)), int(round(w * s)), int(round(h * s))
    # World studs at each image pixel's centre, and on the coarse sampling grid.
    to_world_x = lambda px: isle.box[0] + (px - x - GUTTER) * STUDS_PER_PX  # noqa: E731
    to_world_z = lambda px: isle.box[1] + (px - y - GUTTER) * STUDS_PER_PX  # noqa: E731
    wx = to_world_x(X0 / s + (np.arange(W) + 0.5) / s)
    wz = to_world_z(Y0 / s + (np.arange(H) + 0.5) / s)
    cx = to_world_x(np.arange(x, x + w + SAMPLE_PX, SAMPLE_PX, dtype=np.float64))
    cz = to_world_z(np.arange(y, y + h + SAMPLE_PX, SAMPLE_PX, dtype=np.float64))
    coarse = np.array([[isle.fields(px, pz) for px in cx] for pz in cz])  # rows x cols x 3
    height, green, rock = (upsample(coarse[..., i], cz, cx, wz, wx) for i in range(3))
    hv = 0.04 + 0.92 * np.clip(height / V_TOP, 0.0, 1.0)
    rv = 0.04 + 0.92 * np.clip(height / V_ROCK, 0.0, 1.0)
    shades = [ramp(RAMPS[m], hv) for m in ('gully', 'jungle', 'canopy')]
    g2 = np.clip(green, 0.0, 1.0)[..., None] * 2.0
    greens = np.where(g2 < 1.0, shades[0] + (shades[1] - shades[0]) * g2,
                      shades[1] + (shades[2] - shades[1]) * (g2 - 1))
    greens = greens * canopy(rng, wx, wz)[..., None]
    r = np.clip(rock, 0.0, 1.0)[..., None]
    img[Y0:Y0 + H, X0:X0 + W] = greens * (1 - r) + ramp(RAMPS['i_rock'], rv) * r


def draw(rng, size):
    """The sheet at size x size (RGB, 0..255): each strip's ramp, clamped over its padding
    (islands.py never samples inside the pads: map_common.trim_v keeps PAD clear), and every
    island's tile."""
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    for name, (top, bottom, _) in STRIPS.items():
        rows = np.arange(int(top * s), int(bottom * s))
        if name == 'i_land':  # between the tiles: the jungle's middle green
            img[rows] = ramp(RAMPS['jungle'], np.full(1, 0.3))[0]
            continue
        centre = (rows + 0.5) / s  # in 1024-sheet rows
        lo, hi = bottom - PAD, top + PAD  # trim_v's V 0 and V 1
        v = np.clip((lo - centre) / (lo - hi), 0.0, 1.0)
        img[rows] = ramp(RAMPS[name], v)[:, None, :]
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import islands  # the shapes (islands imports this module first, so no cycle at load)
    for isle in islands.make_islands():
        paint_tile(img, s, isle, rng)
    return img


if __name__ == '__main__':
    import gen_textures
    gen_textures.write_backdrop_sheet('islands')
