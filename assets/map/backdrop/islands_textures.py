"""The islands' sheet (textures/islands_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/islands_textures.py

Seen from 900 to 2,500 studs away, so every strip is a calm vertical ramp and even along U (no
noise, no detail to shimmer): islands.py picks a strip per face and sets V per vertex, so a
strip works like a colour ramp. The land strips (jungle, gully, canopy, rock) run V by height
over the sea on one scale for every island (islands.P['v_top']): shaded at the foot, lit
toward the tops. Colours from the art's ocean panel and Palette.json: the art's near islands
are a fresher, lighter green than the measured sage (island_green), and Roblox renders a
little paler and greyer than painted, so the greens are kept clear.
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
    # so neighbours are alike (distant mip levels blend a strip with its neighbours): sand by
    # rock, the trunk between rock and the greens, the palm fronds last.
    'i_sand': (0, 112, 2048.0),  # beaches: wet at the waterline (V 0), dry at the jungle (V 1)
    'i_rock': (112, 288, 2048.0),  # mauve rock: crags, cliffs, bare steep faces (V by height)
    'i_trunk': (288, 352, 256.0),  # palm trunks: shaded foot (V 0), lit under the crown (V 1)
    'i_ridge': (352, 544, 2048.0),  # the dark jungle in the gullies (V by height)
    'i_jungle': (544, 768, 2048.0),  # the jungle slopes (V by height)
    'i_canopy': (768, 912, 2048.0),  # light, sunlit canopy on ridges and crowns (V by height)
    'i_palm': (912, 1024, 256.0),  # palm fronds: dark at the stem (V 0), lit at the tips (V 1)
}

# Each strip's ramp: (V, colour) stops, V 0 at the strip's foot.
RAMPS = {
    'i_sand': [(0.0, '#CDB597'), (0.3, '#E6CCAA'), (1.0, '#F0D7B6')],
    # The measured mauve (island_rock) went blue-violet under the sky's light, so the ramp
    # leans warmer, toward the art's pinkish lit faces.
    'i_rock': [(0.0, '#5E5470'), (0.15, '#74667F'), (0.45, '#907D8C'), (1.0, '#B69A9A')],
    'i_trunk': [(0.0, '#5A4238'), (1.0, '#8C6E5C')],
    # The greens lean a little yellow (the art's warm jungle): the sky's blue light turned the
    # first, cooler set minty on the lit faces.
    'i_ridge': [(0.0, '#1C4838'), (0.15, '#24543E'), (0.6, '#2F6841'), (1.0, '#3D7644')],
    'i_jungle': [(0.0, '#2B5E42'), (0.12, '#346F44'), (0.5, '#478847'), (1.0, '#64A24B')],
    'i_canopy': [(0.0, '#4F8A40'), (0.3, '#68A247'), (1.0, '#97C255')],
    'i_palm': [(0.0, '#355F25'), (0.5, '#5B8A2F'), (1.0, '#8FAE3E')],
}


def ramp(stops, v):
    """Colours (len(v), 3) along a strip's (V, hex) stops."""
    xs = [s for s, _ in stops]
    cols = np.array([mc.rgb(c) for _, c in stops], dtype=np.float64)
    return np.stack([np.interp(v, xs, cols[:, k]) for k in range(3)], axis=-1)


def draw(rng, size):
    """The sheet at size x size (RGB, 0..255): each strip a vertical ramp, clamped over its
    padding (islands.py never samples inside the pads: map_common.trim_v keeps PAD clear)."""
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    for name, (top, bottom, _) in STRIPS.items():
        rows = np.arange(int(top * s), int(bottom * s))
        centre = (rows + 0.5) / s  # in 1024-sheet rows
        lo, hi = bottom - PAD, top + PAD  # trim_v's V 0 and V 1
        v = np.clip((lo - centre) / (lo - hi), 0.0, 1.0)
        img[rows] = ramp(RAMPS[name], v)[:, None, :]
    return img


if __name__ == '__main__':
    import gen_textures
    gen_textures.write_backdrop_sheet('islands')
