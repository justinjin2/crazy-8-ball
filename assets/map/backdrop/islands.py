"""The near islands on the ocean side, 900 to 2,500 studs out (Stage 5). STUB: a few plain
cones; builder B replaces this.

build() returns [(chunk name, Mesh)]: one chunk per cluster (Islands_<n>), and one painted
shallows ring per cluster (IslandShallows_<n>, near_color.png's n_shallows strip, alpha).
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
import city_plan as cp  # noqa: E402
import islands_textures as tex  # noqa: E402
import map_common as mc  # noqa: E402

mc.register_trim(tex.STRIPS, tex.PAD)

CAP = 30000
MATERIALS = {'Islands': (tex.IMAGE, False), 'IslandShallows': ('near_color.png', True)}
SEA = cp.WORLD['sea_y']

# (cluster, azimuth from straight ahead toward the ocean (+X) in degrees, distance, radius, height)
STUB_ISLANDS = [(0, 70.0, 1400.0, 160.0, 180.0), (0, 80.0, 1900.0, 220.0, 260.0),
                (1, 30.0, 1600.0, 180.0, 220.0), (1, 40.0, 2300.0, 140.0, 150.0)]


def build():
    out = []
    for cluster, az, dist, r, h in STUB_ISLANDS:
        a = math.radians(az)
        cx, cz = dist * math.sin(a), -dist * math.cos(a)
        m = mc.Mesh('isle')
        m.frustum(cx, cz, r, 0.0, SEA - 2.0, SEA + h, 10, 'i_jungle')
        out.append(('Islands_%d' % cluster, m))
    return out
