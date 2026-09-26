"""The islands' sheet (textures/islands_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/islands_textures.py

Seen from 900 to 2,500 studs away: tall strips, 8 pixels clear at each edge, calm colours from
the art's ocean panel (Palette.json: island_green, island_rock, sand). STUB: flat colours.
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
    'i_jungle': (0, 256, 64.0),  # the green slopes
    'i_ridge': (256, 384, 64.0),  # darker ridges and gullies
    'i_rock': (384, 576, 32.0),  # mauve rock outcrops
    'i_sand': (576, 704, 64.0),  # the beaches
    'i_palm': (704, 832, 16.0),  # palm crowns
    'i_trunk': (832, 896, 8.0),  # palm trunks
    'i_spare': (896, 1024, 16.0),
}

STUB = {'i_jungle': mc.hexc('island_green'), 'i_ridge': mc.hexc('island_green', 'shade'),
        'i_rock': mc.hexc('island_rock'), 'i_sand': mc.hexc('sand'), 'i_palm': mc.hexc('palm_mid'),
        'i_trunk': mc.hexc('palm_trunk'), 'i_spare': '#808080'}


def draw(rng, size):
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    for name, (top, bottom, _) in STRIPS.items():
        img[int(top * s):int(bottom * s)] = np.array(mc.rgb(STUB[name]), dtype=np.float64)
    return img


if __name__ == '__main__':
    import gen_textures
    gen_textures.write_backdrop_sheet('islands')
