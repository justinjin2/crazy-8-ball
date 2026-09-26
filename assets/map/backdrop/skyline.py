"""The city's skyline from the near world's edge to city_plan's reach (Stage 5): every lot of
city_plan.city_blocks() beyond the near radius (STUB: plain boxes; builder A replaces this).

build() returns [(chunk name, Mesh)]: whole blocks go to the chunk of their centre
(map_common.chunk_cell), so no building is split across MeshParts.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import city_plan as cp  # noqa: E402
import map_common as mc  # noqa: E402
import skyline_textures as tex  # noqa: E402

mc.register_trim(tex.STRIPS, tex.PAD)

CAP = 60000
MATERIALS = {'Skyline': (tex.IMAGE, False)}
STREET = cp.WORLD['street_y']
STYLES = ('s_glass', 's_white', 's_terracotta', 's_stone')


def facade(mesh, x0, z0, x1, z1, y0, y1, strip):
    """A box's four walls (one quad each, V by height over the street) and its lit top."""
    outline = mc.outward_rect(x0, z0, x1, z1)
    v0, v1 = (y0 - STREET) / tex.FACADE_TOP, (y1 - STREET) / tex.FACADE_TOP
    for i in range(4):
        mesh.wall(outline[i], outline[(i + 1) % 4], y0, y1, strip, v_range=(v0, v1))
    mesh.flat(outline, y1, 's_roof', up=True)


def build():
    out = []
    for b in cp.city_blocks():
        if b['near']:
            continue
        mesh = mc.Mesh('block')
        for k, lot in enumerate(b['lots']):
            style = STYLES[(b['i'] * 7 + b['j'] * 3 + k) % 4]
            base = STREET + lot['top']
            x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
            facade(mesh, x - w / 2, z - d / 2, x + w / 2, z + d / 2, base, base + lot['podium'], style)
            if lot['shaft']:
                sw, sd = lot['shaft']
                top = STREET + lot['top'] + lot['height'] - lot['crown']
                facade(mesh, x - sw / 2, z - sd / 2, x + sw / 2, z + sd / 2, base + lot['podium'], top, style)
        out.append((mc.cell_name('Skyline', mc.chunk_cell(b['cx'], b['cz'])), mesh))
    return out
