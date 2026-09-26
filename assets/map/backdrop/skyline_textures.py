"""The skyline's sheet (textures/skyline_color.png): STRIPS below, drawn by draw(). Pure Python
(numpy), no bpy: gen_textures.py calls draw(), and running this file writes the sheet alone:

    python3 assets/map/backdrop/skyline_textures.py

Seen from 450 to 2,300 studs away, so it is drawn for distance: tall strips, 8 pixels clear at
each edge, big calm features, no fine window grids (they shimmer), soft shade at the foot.
Facade strips map V to height over the street (0 at the street, 1 at FACADE_TOP studs up), so a
whole wall is one quad and every building shares one gradient: the stub draws flat colours.
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
STRIPS = {
    # name: (first row, last row + 1 of a 1024 sheet, studs per image width along U)
    's_glass': (0, 176, 40.0),  # blue glass curtain wall
    's_white': (176, 352, 40.0),  # white tower, window bands
    's_terracotta': (352, 528, 40.0),  # terracotta mid-rise
    's_stone': (528, 704, 40.0),  # cream stone
    's_accent': (704, 768, 20.0),  # landmark crowns: bright glass and metal
    's_roof': (768, 832, 64.0),  # flat roofs, lit
    's_paving': (832, 896, 64.0),  # block tops: paving
    's_park': (896, 960, 128.0),  # block tops: lawn
    's_tree': (960, 1024, 32.0),  # tree canopies
}

STUB = {
    's_glass': mc.hexc('city_glass_day'), 's_white': '#E6E4E8', 's_terracotta': mc.hexc('facade_terracotta_day'),
    's_stone': mc.hexc('city_facade_day'), 's_accent': '#BFD8F0', 's_roof': '#C8C6CC', 's_paving': '#C9C3C3',
    's_park': '#4E9A48', 's_tree': '#2E7A3E',
}


def draw(rng, size):
    """The sheet at size x size (RGB, 0..255)."""
    img = np.zeros((size, size, 3))
    s = size / mc.TRIM_PX
    for name, (top, bottom, _) in STRIPS.items():
        img[int(top * s):int(bottom * s)] = np.array(mc.rgb(STUB[name]), dtype=np.float64)
    return img


if __name__ == '__main__':
    sys.path.insert(0, os.path.dirname(HERE))
    import gen_textures
    gen_textures.write_backdrop_sheet('skyline')
