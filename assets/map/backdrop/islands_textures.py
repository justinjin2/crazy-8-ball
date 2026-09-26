"""The islands' sheet (textures/islands_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/islands_textures.py

Seen from 900 to 2,500 studs away, so every strip is a calm ramp (no noise, no detail to
shimmer), and islands.py sets UVs per vertex, so the sheet works like vertex colours:
    i_sand, i_rock, i_trunk, i_palm  even along U, V a ramp (islands.py sets V per vertex)
    i_land  the islands' ground, two-dimensional: V is the height over the sea (land_v, one
            scale for every island: shaded at the foot, lit toward the tops, but gently), U
            the material, blended between the LAND_U columns (rock, gully, jungle, canopy).
            Every land vertex has its own U, so rock streaks and the greens shade softly into
            each other across faces (the islands are shaded smooth; a strip chosen per face
            showed every face's edge). The columns sit close together in U so no face spans
            more than a small part of the sheet (a wide U spread would pick a blurry mip level).
Colours from the art's ocean panel and Palette.json: the art's near islands are a fresher,
lighter green than the measured sage (island_green), and Roblox renders a little paler and
greyer than painted, so the greens are kept clear; each ramp is shallow, so an island's
light-to-dark range stays within about a quarter (Stage 5 critic: muddy, high contrast).
"""

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
    'i_sand': (0, 96, 2048.0),  # beaches: wet at the waterline (V 0), dry at the jungle (V 1)
    'i_rock': (96, 224, 2048.0),  # mauve rock: crags and the shore's cliffs (V: land_v, V_ROCK)
    'i_trunk': (224, 288, 256.0),  # palm trunks: shaded foot (V 0), lit under the crown (V 1)
    'i_land': (288, 928, 1.0),  # the ground: U the material (LAND_U), V the height (land_v, V_TOP)
    'i_palm': (928, 1024, 256.0),  # palm fronds: darker at the stem (V 0), lit at the tips (V 1)
}
LAND_U = {'rock': 0.40, 'gully': 0.45, 'jungle': 0.50, 'canopy': 0.55}  # i_land's columns
V_TOP = 330.0  # studs over the sea at V 1 of i_land (the tallest summit is 320)
V_ROCK = 140.0  # and of i_rock, so low crags still span its ramp


def land_v(height, top=V_TOP):
    """A strip's V fraction for a height over the sea (i_land: top V_TOP; i_rock: V_ROCK)."""
    return 0.04 + 0.92 * max(0.0, min(1.0, height / top))


# Each ramp: (V, colour) stops, V 0 at the strip's foot.
RAMPS = {
    'i_sand': [(0.0, '#D6BFA1'), (0.3, '#E8CFAE'), (1.0, '#F0D7B6')],
    # The measured mauve (island_rock) went blue-violet under the sky's light, so the ramp
    # leans warmer, toward the art's pinkish lit faces; light and flat so the crags do not
    # read as dark holes.
    'i_rock': [(0.0, '#877A8C'), (0.4, '#9A8894'), (1.0, '#AE979C')],
    'i_trunk': [(0.0, '#6A5044'), (1.0, '#8C6E5C')],
    'i_palm': [(0.0, '#5B8C35'), (1.0, '#7CA73F')],
    # i_land's greens (V by land_v): fresh and light, the gullies a step darker than the
    # slopes, the canopy a step lighter and yellower.
    'gully': [(0.0, '#46874A'), (1.0, '#4E944E')],
    'jungle': [(0.0, '#4C914C'), (1.0, '#58A054')],
    'canopy': [(0.0, '#5EA052'), (1.0, '#6CAC58')],
}


def ramp(stops, v):
    """Colours (..., 3) along a ramp's (V, hex) stops."""
    xs = [s for s, _ in stops]
    cols = np.array([mc.rgb(c) for _, c in stops], dtype=np.float64)
    return np.stack([np.interp(v, xs, cols[:, k]) for k in range(3)], axis=-1)


def land(v, u):
    """i_land's colour at V fractions v (rows) and U u (columns): each material's ramp at the
    height v stands for, blended linearly between the LAND_U columns (clamped outside)."""
    height = (v - 0.04) / 0.92 * V_TOP
    rock_v = np.array([land_v(h, V_ROCK) for h in height])
    columns = [('rock', ramp(RAMPS['i_rock'], rock_v))]
    columns += [(m, ramp(RAMPS[m], v)) for m in ('gully', 'jungle', 'canopy')]
    keys = [LAND_U[m] for m, _ in columns]
    out = np.zeros((len(v), len(u), 3))
    for c in range(3):
        stack = np.stack([col[:, c] for _, col in columns], axis=1)  # rows x materials
        for i in range(len(v)):
            out[i, :, c] = np.interp(u, keys, stack[i])
    return out


def draw(rng, size):
    """The sheet at size x size (RGB, 0..255): each strip's ramp, clamped over its padding
    (islands.py never samples inside the pads: map_common.trim_v keeps PAD clear)."""
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    u = (np.arange(size) + 0.5) / size
    for name, (top, bottom, _) in STRIPS.items():
        rows = np.arange(int(top * s), int(bottom * s))
        centre = (rows + 0.5) / s  # in 1024-sheet rows
        lo, hi = bottom - PAD, top + PAD  # trim_v's V 0 and V 1
        v = np.clip((lo - centre) / (lo - hi), 0.0, 1.0)
        img[rows] = land(v, u) if name == 'i_land' else ramp(RAMPS[name], v)[:, None, :]
    return img


if __name__ == '__main__':
    import gen_textures
    gen_textures.write_backdrop_sheet('islands')
