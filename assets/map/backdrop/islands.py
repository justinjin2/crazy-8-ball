"""The near islands on the ocean side, 900 to 2,500 studs out (Stage 5; Spec section 7), as in
the art's ocean panel: a couple of steep jungle peaks and smaller rocky islets in two clusters,
each island with mauve crags at its shore, a sand beach toward the tower, a few palms, and a
painted turquoise ring of shallows round it.

    cluster 0  azimuth 55 to 85: the ocean-side view
    cluster 1  azimuth 20 to 45: right of the pergola from the entrance, the high and day views
(azimuth from straight ahead, -Z, toward the ocean, +X: x = d sin a, z = -d cos a).

build() returns [(chunk name, Mesh)]: a cluster's islands in Islands_<n> (this module's sheet,
islands_textures.py), its shallows in IslandShallows_<n> (near_color.png's n_shallows strip,
alpha: v 1 is the foam at the sand, 0 clear). Pure Python, deterministic (random.Random with
fixed seeds), so every run builds the same islands.

An island is a heightfield on a polar grid round its summit: rings of vertices from the summit
out to the land's edge, each vertex jittered, raised along a few ridges (with shoulders on
them) and lowered in the gullies between, then the shore (a beach apron toward the tower,
low cliffs elsewhere) down to the waterline and on under the sea. Every face picks its strip
(jungle, dark gully, light canopy, rock, sand) from where it lies; V is the height over the
sea on one scale for every island, so the foot is shaded and the tops are lit alike.
"""

import math
import os
import random
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
SMOOTH = {'Islands'}  # gen_backdrop merges these chunks' vertices and shades them smooth: soft slopes
SEA = cp.WORLD['sea_y']
SEED = 7307

ISLANDS = [
    # (cluster, kind, azimuth in degrees, distance, radius, height over the sea): the summit's
    # place; radius is the land's mean reach from it (the beach and shallows lie beyond).
    (0, 'ridge', 63.0, 2130.0, 250.0, 300.0),  # the ocean-side view's big massif: spires on a ridge
    (0, 'hill', 77.0, 1680.0, 165.0, 150.0),  # the near jungle island, crags at its shore
    (0, 'islet', 84.0, 1160.0, 70.0, 62.0),  # a rocky islet, a jungle cap
    (0, 'islet', 57.0, 1720.0, 55.0, 48.0),  # a small one between the two
    (1, 'peak', 33.0, 2150.0, 270.0, 320.0),  # the big peak right of the pergola
    (1, 'hill', 42.0, 1600.0, 87.0, 78.0),  # 0.6 of its first size: it loomed beside the roof (high view)
    (1, 'islet', 24.5, 1790.0, 62.0, 56.0),
    (1, 'islet', 44.0, 2330.0, 60.0, 52.0),
]

KINDS = {
    # spokes and land rings (radial fractions s from the summit, 0, to the land's edge, 1);
    # the profile's (s, height fraction) points; ridges, how far they stand out and from
    # which s (hills keep round crowns); a tail (the land reaches this much further to one
    # side, across the view: a long slope one way, a steep side the other); wide (and this
    # much further across the view than along it); shoulders on the ridges across the view
    # (s, lift range as a fraction of the height); lumps anywhere (count, s range, lift range:
    # a hill's canopy clumps, a peak's foothills); spires on the ridge line across the view;
    # rock streaks down the slopes; beach (widest, studs), cliff heights where there is none,
    # shallows (studs past the waterline: close round the coast, not a halo), crags at the
    # shore (count, heights), sea stacks off it, boulders, palms; the outline's bays and
    # points; ref_r, the radius the dressing is sized for (smaller islands get less of it).
    'peak': {
        'spokes': 48,
        'rings': (0.0, 0.05, 0.1, 0.16, 0.23, 0.3, 0.38, 0.46, 0.55, 0.64, 0.73, 0.81, 0.88, 0.94, 1.0),
        'profile': ((0.0, 1.0), (0.05, 0.9), (0.12, 0.75), (0.22, 0.57), (0.35, 0.39), (0.5, 0.25),
                    (0.68, 0.13), (0.85, 0.05), (1.0, 0.0)),
        'ridges': (5, 7), 'ridge_lift': 0.4, 'ridge_from': 0.12, 'tail': 0.22, 'wide': 0.12,
        'shoulders': ((0.14, 0.04, 0.08), (0.32, 0.12, 0.2), (0.55, 0.12, 0.2)), 'lumps': (5, 0.45, 0.85, 0.04, 0.1),
        'spires': (), 'streaks': 3, 'beach': 38.0, 'cliff': (7.0, 14.0), 'shallows': 60.0, 'crags': (9, 12),
        'crag_h': (18.0, 60.0), 'stacks': (2, 3), 'boulders': 7, 'palms': (9, 12), 'outline': 0.09, 'ref_r': 250.0,
    },
    'ridge': {  # a peak whose summit is a jagged ridge line across the view: spires and saddles
        'spokes': 48,
        'rings': (0.0, 0.05, 0.1, 0.16, 0.23, 0.3, 0.38, 0.46, 0.55, 0.64, 0.73, 0.81, 0.88, 0.94, 1.0),
        'profile': ((0.0, 1.0), (0.05, 0.9), (0.12, 0.75), (0.22, 0.57), (0.35, 0.39), (0.5, 0.25),
                    (0.68, 0.13), (0.85, 0.05), (1.0, 0.0)),
        'ridges': (4, 6), 'ridge_lift': 0.3, 'ridge_from': 0.12, 'tail': 0.12, 'wide': 0.26,
        'shoulders': (), 'lumps': (5, 0.45, 0.85, 0.04, 0.1),
        # spires along the ridge: (side of the summit, s, height and radius as fractions),
        # each a straight-sided cone (spire_profile), broad enough that the saddles between
        # stay high: a jagged ridge line, not separate horns
        'spires': ((1, 0.38, 0.76, 0.56), (-1, 0.46, 0.66, 0.52), (1, 0.73, 0.36, 0.36)),
        'spire_profile': ((0.0, 1.0), (0.12, 0.85), (0.35, 0.58), (0.65, 0.27), (1.0, 0.0)),
        'streaks': 2, 'beach': 38.0, 'cliff': (7.0, 14.0), 'shallows': 60.0, 'crags': (9, 12),
        'crag_h': (18.0, 60.0), 'stacks': (2, 3), 'boulders': 7, 'palms': (9, 12), 'outline': 0.08, 'ref_r': 250.0,
    },
    'hill': {
        'spokes': 36, 'rings': (0.0, 0.09, 0.19, 0.3, 0.41, 0.52, 0.63, 0.73, 0.82, 0.9, 0.96, 1.0),
        'profile': ((0.0, 1.0), (0.12, 0.93), (0.3, 0.76), (0.5, 0.52), (0.7, 0.28), (0.86, 0.1),
                    (1.0, 0.0)),
        'ridges': (4, 6), 'ridge_lift': 0.2, 'ridge_from': 0.3, 'tail': 0.12, 'wide': 0.12,
        'shoulders': ((0.28, 0.06, 0.12), (0.55, 0.08, 0.14), (0.45, 0.06, 0.12)), 'lumps': (7, 0.1, 0.8, 0.06, 0.13),
        'spires': (), 'streaks': 1, 'beach': 34.0, 'cliff': (6.0, 11.0), 'shallows': 50.0, 'crags': (7, 9),
        'crag_h': (22.0, 58.0), 'stacks': (2, 3), 'boulders': 5, 'palms': (10, 13), 'outline': 0.1, 'ref_r': 160.0,
    },
    'islet': {
        'spokes': 24, 'rings': (0.0, 0.16, 0.33, 0.5, 0.66, 0.8, 0.91, 1.0),
        'profile': ((0.0, 1.0), (0.2, 0.93), (0.4, 0.78), (0.6, 0.55), (0.78, 0.3), (0.9, 0.12),
                    (1.0, 0.0)),
        'ridges': (3, 4), 'ridge_lift': 0.2, 'ridge_from': 0.35, 'tail': 0.1, 'wide': 0.12,
        'shoulders': ((0.45, 0.08, 0.16),), 'lumps': (3, 0.1, 0.6, 0.06, 0.12),
        'spires': (), 'streaks': 0, 'beach': 20.0, 'cliff': (5.0, 9.0), 'shallows': 40.0, 'crags': (4, 5),
        'crag_h': (16.0, 40.0), 'stacks': (1, 2), 'boulders': 3, 'palms': (4, 6), 'outline': 0.12, 'ref_r': 65.0,
    },
}

P = {
    'base_drop': 3.0,  # the island's foot this far under the sea, so no gap shows at the waterline
    'beach_top': 3.5,  # the sand's top, where the jungle meets it
    'beach_spread': 70.0,  # degrees either side of the beach's middle that still have sand
    'beach_turn': 30.0,  # the beach's middle this far either side of straight toward the tower
    'cliff_toe': 3.0,  # a cliff meets the sea this far out from the land's edge
    'under': 8.0,  # the sea floor ring, this far past the waterline
    'jitter_r': 0.05,  # each land vertex's reach, up to this fraction either way...
    'jitter_a': 0.22,  # ...its angle, this fraction of a spoke either way...
    'jitter_h': 0.045,  # ...and its height, this fraction of the island's
    'egg': 0.18,  # the land reaches this much further toward the tower (the summit sits back)
    'ridge_sharp': 14.0,  # the ridges' cos power: higher, narrower crests
    'ridge_out': 0.08,  # ridges reach out (gullies cut in) this fraction of the land's reach
    'green_gain': 1.0,  # a vertex's green: gully (0) to canopy (1), 0.5 + this x its ridge value
    'streak_width': 0.18,  # radians either side of a rock streak's line
    'shore_rock': 0.85,  # past this s, the land off the beach is the shore's cliffs (islets: islet_rock)
    'islet_rock': 0.74,
    'shallows_in': 3.0,  # the painted shallows start this far up the beach from the waterline...
    'foam_out': 8.0,  # ...the foam ends this far out (v 0.86: just past the strip's foam)...
    'shallows_mid': 0.45,  # ...v at half the band's width (the turquoise thinning)...
    'shallows_edge': 0.2,  # ...and at its full width (the strip is clear from v 0.2 down)...
    'shallows_lift': 0.5,  # ...lifted this far over the sea (gen_near's)
    'palm_h': (30.0, 46.0),  # palm heights, studs (the near world's are 24 to 36; these are seen
                             # from 1,000 studs and more)
    'palm_frond': (13.0, 18.0),  # frond lengths
    'water_margin': 20.0,  # every footprint this far inside the Terrain water
    'boat_clear': 80.0,  # and this far clear of the boats' loops (shallows included)
    'island_gap': 60.0,  # open water at least this wide between two islands' waterlines
    'span_max': 2000.0,  # a chunk's span (gen_backdrop fails at 2,040)
}

# The drifting boats' loops (Config.Map.Near.Boat.Paths): centre X, Z; radius along X, Z.
BOAT_LOOPS = [((450.0, -1000.0), (250.0, 150.0)), ((900.0, -600.0), (300.0, 140.0)),
              ((250.0, -1500.0), (200.0, 150.0))]

UP = (0.0, 1.0, 0.0)


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def normal(pts):
    return cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))


def facing(mesh, pts, uvs, want):
    """A face turned toward `want` (Mesh.face's normal is (p1 - p0) x (p2 - p0))."""
    n = normal(pts)
    if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0:
        pts, uvs = list(reversed(pts)), list(reversed(uvs))
    mesh.face(pts, uvs)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def interp(points, s):
    """Piecewise-linear through (x, y) points."""
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        if s <= x1:
            return y0 + (y1 - y0) * (s - x0) / (x1 - x0)
    return points[-1][1]


def angle_diff(a, b):
    return (a - b + math.pi) % (2 * math.pi) - math.pi


def uv(strip, p, frac):
    """A vertex's UV in a strip: U planar (these strips are even along U), V a fraction."""
    return (mc.trim_u(strip, p[0] + p[2]), mc.trim_v(strip, frac))


def rock_v(y):
    """i_rock's V fraction at a world height (the sheet's scale for rock)."""
    return tex.land_v(y - SEA, tex.V_ROCK)


# ---------------------------------------------------------------------------------------------
# One island
# ---------------------------------------------------------------------------------------------

class Island:
    """An island's shape as functions of the angle round its summit (radians, x = cos, z = sin)
    and the radial fraction s (0 at the summit, 1 at the land's edge)."""

    def __init__(self, index, cluster, kind, az, dist, radius, height):
        self.index, self.cluster, self.kind = index, cluster, kind
        self.k = KINDS[kind]
        self.rng = random.Random(SEED * 100 + index)
        a = math.radians(az)
        self.cx, self.cz = dist * math.sin(a), -dist * math.cos(a)
        self.R, self.H = radius, height
        rng = self.rng
        self.toward = math.atan2(-self.cz, -self.cx)  # the tower's direction from the summit
        n = self.k['spokes']
        self.step = 2 * math.pi / n
        # A ridge line across the view (the spires stand on it), along two opposite spokes so
        # each spire's tip is a vertex.
        if self.k['spires']:
            j = int(round(n / 4 - 0.5)) + rng.choice((-1, 0, 1))
            self.j_plus = j if rng.random() < 0.5 else n - 1 - j
            self.j_minus = (self.j_plus + n // 2) % n
            self.axis = self.spoke(self.j_plus)
            self.tail = self.axis + rng.uniform(-0.2, 0.2)  # the long side under the spires
        else:
            self.axis = None
            self.tail = self.toward + rng.choice((-1.0, 1.0)) * math.pi / 2 + rng.uniform(-0.3, 0.3)
        self.size = min(1.0, self.R / self.k['ref_r'])  # the dressing's scale
        # The outline: an egg reaching toward the tower, wider across the view, a tail to one
        # side, a few bays.
        self.harm = [(n, rng.uniform(0.5, 1.0) * self.k['outline'] * 2.2 / n, rng.uniform(0, 2 * math.pi))
                     for n in (3, 4, 5, 7)]
        # Ridges from the summit, the first a spur straight toward the tower, so the face the
        # roof sees is lit down its middle (a gully there read as a dark crater groove).
        count = rng.randint(*self.k['ridges'])
        base = self.toward + rng.uniform(-0.2, 0.2)
        self.ridges = []
        for i in range(count):
            jitter = rng.uniform(-0.25, 0.25)
            ang = base + 2 * math.pi * (i + (jitter if i else 0.0)) / count
            self.ridges.append((ang, 1.0 if i == 0 else rng.uniform(0.6, 1.0)))
        if self.axis is not None:
            self.ridges += [(self.axis, 1.0), (self.axis + math.pi, 1.0)]
        # Shoulders on ridges turned across the view, alternately left and right of the
        # summit, so the silhouette steps down to each side as the art's peaks do.
        side = rng.choice((-1.0, 1.0))
        self.shoulders = []
        for s0, lo, hi in self.k['shoulders']:
            ang = self.toward + side * (math.pi / 2 + rng.uniform(-0.5, 0.3))
            side = -side
            self.shoulders.append((ang, s0 + rng.uniform(-0.04, 0.04), rng.uniform(lo, hi)))
            self.ridges.append((ang, 1.0))
        # Lumps: round swellings anywhere on the slopes (local x, z from the summit, width).
        count, s_lo, s_hi, a_lo, a_hi = self.k['lumps']
        self.lumps = []
        for _ in range(count):
            t, f = rng.uniform(0, 2 * math.pi), rng.uniform(s_lo, s_hi)
            self.lumps.append((f * self.R * math.cos(t), f * self.R * math.sin(t), self.R * rng.uniform(0.14, 0.26),
                               rng.uniform(a_lo, a_hi)))
        # Rock streaks: bare cliffs down the steep slopes, each along a line from the summit.
        self.streaks = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.12, 0.3), rng.uniform(0.6, 0.95))
                        for _ in range(self.k['streaks'])]
        # The ridge function's mean, taken off so gullies come out negative.
        self.ridge_mean = sum(self._ridge_raw(2 * math.pi * i / 360) for i in range(360)) / 360
        # The spires: each a sharp cone on the ridge line, its tip a vertex of the grid.
        rings = self.k['rings']
        self.spires = []
        for side, s_want, hf, rf in self.k['spires']:
            j = self.j_plus if side > 0 else self.j_minus
            k = min(range(len(rings)), key=lambda i: abs(rings[i] - s_want))
            t = self.spoke(j)
            r = self.radius(t, rings[k])
            self.spires.append({'j': j, 'k': k, 'x': r * math.cos(t), 'z': r * math.sin(t),
                                'h': self.H * hf * rng.uniform(0.93, 1.05), 'rad': self.R * rf})
        # The beach: toward the tower, turned a little.
        self.beach_mid = self.toward + math.radians(rng.uniform(-P['beach_turn'], P['beach_turn']))
        self.beach_w = self.k['beach'] * rng.uniform(0.85, 1.1) * (0.6 + 0.4 * self.size)
        self.cliff = [(rng.uniform(0, 2 * math.pi), rng.uniform(*self.k['cliff'])) for _ in range(3)]

    # -- shape -----------------------------------------------------------------------------

    def reach(self, t):
        """The land's edge (studs from the summit) at angle t."""
        d = angle_diff(t, self.toward)
        f = 1.0 + P['egg'] * math.cos(d) - self.k['wide'] * math.cos(2 * d)
        f += self.k['tail'] * math.cos(angle_diff(t, self.tail))
        for n, amp, ph in self.harm:
            f += amp * math.cos(n * t + ph)
        return self.R * f

    def spoke(self, j):
        """The angle of spoke j (the first half a spoke past straight toward the tower)."""
        return self.toward + self.step * (j + 0.5)

    def radius(self, t, s):
        """A land vertex's reach from the summit before its jitter: ridges reach out, gullies
        cut in."""
        return s * self.reach(t) * (1 + P['ridge_out'] * self.ridge(t) * self.relief(s))

    def _ridge_raw(self, t):
        return sum(w * max(0.0, math.cos(angle_diff(t, a))) ** P['ridge_sharp'] for a, w in self.ridges)

    def ridge(self, t):
        return self._ridge_raw(t) - self.ridge_mean

    def beach(self, t):
        """Beach width (studs) at angle t: widest toward the tower, none past beach_spread."""
        d = abs(angle_diff(t, self.beach_mid))
        spread = math.radians(P['beach_spread'])
        if d >= spread:
            return 0.0
        return self.beach_w * math.cos(d / spread * math.pi / 2) ** 1.5

    def sandy(self, t):
        return smoothstep(4.0, 14.0, self.beach(t))

    def edge_height(self, t):
        """The land's edge over the sea: the beach's top where there is sand, a low cliff
        elsewhere."""
        cliff = sum(h * (0.5 + 0.5 * math.cos(angle_diff(t, a))) for a, h in self.cliff) / 1.5
        return cliff + (P['beach_top'] - cliff) * self.sandy(t)

    def waterline(self, t):
        return self.reach(t) + self.beach(t) + P['cliff_toe'] * (1 - self.sandy(t))

    def relief(self, s):
        """How much the ridges and gullies stand out at fraction s: none at the land's edge,
        nor near a hill's round crown."""
        start = self.k['ridge_from']
        w = math.sin(math.pi * s) ** 0.8
        return w * smoothstep(start * 0.5, start * 1.5, s) if start > 0 else w

    def height(self, t, s, r=None):
        """The land's height over the sea at angle t, fraction s (no jitter); r, the point's
        actual reach from the summit (default s of the land's), places it for the spires and
        lumps."""
        he = self.edge_height(t)
        base = he + (self.H - he) * interp(self.k['profile'], s)
        h = base * (1 + self.k['ridge_lift'] * self.ridge(t) * self.relief(s))
        for a, s0, lift in self.shoulders:
            h += self.H * lift * math.exp(-((s - s0) / 0.11) ** 2) * max(0.0, math.cos(angle_diff(t, a))) ** 30
        if s < 1:
            r = s * self.reach(t) if r is None else r
            x, z = r * math.cos(t), r * math.sin(t)
            keep = 1 - smoothstep(0.8, 1.0, s)
            for sp in self.spires:  # the ridge line: the higher of the slope and each spire's cone
                d = math.hypot(x - sp['x'], z - sp['z'])
                if d < sp['rad']:
                    cone = he + (sp['h'] - he) * interp(self.k['spire_profile'], d / sp['rad'])
                    h += max(0.0, cone - h) * keep
            for lx, lz, width, lift in self.lumps:
                h += self.H * lift * keep * math.exp(-((x - lx) ** 2 + (z - lz) ** 2) / width ** 2)
        return max(h, he * (1 - s) if s < 1 else he)

    def ground(self, x, z):
        """The ground's height over the sea at (x, z) (for palms): the land or the beach."""
        t = math.atan2(z - self.cz, x - self.cx)
        r = math.hypot(x - self.cx, z - self.cz)
        edge = self.reach(t)
        if r <= edge:
            return self.height(t, r / edge, r)
        b = self.beach(t)
        if b > 1e-6 and r < edge + b:
            return self.edge_height(t) * (1 - (r - edge) / b)
        return 0.0

    def point(self, t, r, y):
        return (self.cx + r * math.cos(t), SEA + y, self.cz + r * math.sin(t))

    # -- the land and the shore ------------------------------------------------------------

    def build_land(self, mesh):
        rng = self.rng
        n = self.k['spokes']
        rings = self.k['rings']
        step = self.step
        spokes = [self.spoke(j) for j in range(n)]
        tips = {(sp['j'], sp['k']) for sp in self.spires}  # spire tips: exactly on their spoke
        grid = []  # grid[k][j] = (point, angle, s)
        for k, s in enumerate(rings):
            row = []
            for j, t0 in enumerate(spokes):
                if k == 0:
                    row.append((self.point(0.0, 0.0, self.H), t0, 0.0))
                    continue
                w = math.sin(math.pi * s) ** 0.8
                ja = rng.uniform(-1, 1) * P['jitter_a'] * step if s < 1 else 0.0
                jr = rng.uniform(-1, 1) * P['jitter_r'] * w
                jh = rng.uniform(-1, 1) * P['jitter_h'] * self.H * w if s < 1 else 0.0
                if (j, k) in tips:
                    ja = jr = jh = 0.0
                t = t0 + ja
                r = self.radius(t, s) + s * self.reach(t) * jr
                y = self.height(t, s, r) + jh
                row.append((self.point(t, r, y), t, s))
            grid.append(row)
        # The summit stands a little over its first ring (lumps and jitter can lift that ring
        # past the height, which left a crater on the round hills).
        first = max(p[0][1] for p in grid[1]) - SEA
        top = self.point(0.0, 0.0, max(self.H, first + 0.03 * self.H))
        grid[0] = [(top, t, 0.0) for _, t, _ in grid[0]]
        # The shore: the land's edge (the last ring), the waterline, the sea floor under it.
        water = [self.point(t, self.waterline(t), 0.0) for t in spokes]
        floor = [self.point(t, self.waterline(t) + P['under'] * (0.4 + 0.6 * self.sandy(t)), -P['base_drop'])
                 for t in spokes]
        self.spokes, self.water = spokes, water
        # Canopy patches: a few spots on the slopes where the jungle is lit lighter.
        self.patches = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.25, 0.7)) for _ in range(3)]
        # Every vertex's UV in i_land: U its material, V its height (the same for every face
        # that shares it, so colours shade across faces).
        grid = [[(p, (self.land_u(t, s), mc.trim_v('i_land', tex.land_v(p[1] - SEA)))) for p, t, s in row]
                for row in grid]
        for k in range(len(rings) - 1):
            for j in range(n):
                jn = (j + 1) % n
                a0, a1 = grid[k][j], grid[k][jn]
                b0, b1 = grid[k + 1][j], grid[k + 1][jn]
                if k == 0:
                    tris = [(a0, b0, b1)]
                # Split along the shorter diagonal: crisper ridges.
                elif sum((p - q) ** 2 for p, q in zip(a0[0], b1[0])) <= sum((p - q) ** 2 for p, q in zip(a1[0], b0[0])):
                    tris = [(a0, b0, b1), (a0, b1, a1)]
                else:
                    tris = [(a0, b0, a1), (a1, b0, b1)]
                for tri in tris:
                    facing(mesh, [v[0] for v in tri], [v[1] for v in tri], UP)
        edge = [grid[-1][j][0] for j in range(n)]
        for j in range(n):
            jn = (j + 1) % n
            sand = (self.sandy(spokes[j]) + self.sandy(spokes[jn])) / 2 > 0.5
            for ring_a, ring_b, lo in ((edge, water, False), (water, floor, True)):
                quad = [ring_a[j], ring_b[j], ring_b[jn], ring_a[jn]]
                if sand:
                    fr = [0.2 if lo else 1.0, 0.0 if lo else 0.2, 0.0 if lo else 0.2, 0.2 if lo else 1.0]
                    uvs = [uv('i_sand', p, f) for p, f in zip(quad, fr)]
                    facing(mesh, quad, uvs, UP)
                else:
                    facing(mesh, quad, [uv('i_rock', p, rock_v(p[1])) for p in quad], UP)

    def land_u(self, t, s):
        """A land vertex's U in i_land: its green (gully, slope or canopy, from the ridges, a
        hill's round crown and the canopy patches), blended toward rock on the shore's cliffs
        off the beach and down the rock streaks."""
        green = 0.5 + P['green_gain'] * self.ridge(t) * self.relief(s)
        if self.kind in ('hill', 'islet'):
            green = max(green, 1 - smoothstep(0.18, 0.34, s))
        for a, s0 in self.patches:
            green = max(green, (1 - smoothstep(0.2, 0.35, abs(angle_diff(t, a)))) *
                        (1 - smoothstep(0.06, 0.13, abs(s - s0))))
        green = max(0.0, min(1.0, green))
        edge = P['islet_rock'] if self.kind == 'islet' else P['shore_rock']
        rock = smoothstep(edge - 0.08, edge + 0.04, s) * (1 - smoothstep(0.25, 0.55, self.sandy(t)))
        for a, s0, s1 in self.streaks:
            band = 1 - smoothstep(0.5 * P['streak_width'], P['streak_width'], abs(angle_diff(t, a)))
            band *= smoothstep(s0 - 0.04, s0 + 0.04, s) * (1 - smoothstep(s1 - 0.04, s1 + 0.04, s))
            rock = max(rock, band)
        u = tex.LAND_U
        g = u['gully'] + (u['canopy'] - u['gully']) * green
        return g + (u['rock'] - g) * rock

    # -- crags, boulders, palms ------------------------------------------------------------

    def crag(self, mesh, x, z, h, r, sides=6, rings=((0.0, 1.0), (0.5, 0.74), (0.84, 0.44))):
        """A jagged rock pillar from under the sea to a point, leaning a little."""
        rng = self.rng
        lean = (rng.uniform(-0.12, 0.12) * h, rng.uniform(-0.12, 0.12) * h)
        phase = rng.uniform(0, 2 * math.pi)
        levels = []
        for f, rf in rings:
            y = -P['base_drop'] if f == 0 else f * h
            row = []
            for i in range(sides):
                t = phase + 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / sides
                rr = r * rf * rng.uniform(0.75, 1.2)
                row.append((x + lean[0] * f + rr * math.cos(t), SEA + y, z + lean[1] * f + rr * math.sin(t)))
            levels.append(row)
        apex = (x + lean[0], SEA + h, z + lean[1])
        centre = lambda p: (p[0] - x, 0.0, p[2] - z)  # noqa: E731
        for k in range(len(levels) - 1):
            lo, hi = levels[k], levels[k + 1]
            for i in range(sides):
                i2 = (i + 1) % sides
                for tri in ([lo[i], lo[i2], hi[i2]], [lo[i], hi[i2], hi[i]]):
                    c = [sum(p[a] for p in tri) / 3 for a in range(3)]
                    facing(mesh, tri, [uv('i_rock', p, rock_v(p[1])) for p in tri], centre(c))
        top = levels[-1]
        for i in range(sides):
            tri = [top[i], top[(i + 1) % sides], apex]
            c = [sum(p[a] for p in tri) / 3 for a in range(3)]
            want = (c[0] - x - lean[0], 0.3 * r, c[2] - z - lean[1])
            facing(mesh, tri, [uv('i_rock', p, rock_v(p[1])) for p in tri], want)

    def palm(self, mesh, x, z, y, height):
        """A thin four-sided trunk, gently leaning, and a star of six opaque fronds that arch
        up and droop: 8 + 18 triangles."""
        rng = self.rng
        lean = rng.uniform(0, 2 * math.pi)
        amount = rng.uniform(0.05, 0.16) * height
        top = (x + amount * math.cos(lean), SEA + y + height, z + amount * math.sin(lean))
        base_r, top_r = 1.3, 0.8
        ph = rng.uniform(0, math.pi)
        lo = [(x + base_r * math.cos(ph + i * math.pi / 2), SEA + y - 2.0, z + base_r * math.sin(ph + i * math.pi / 2))
              for i in range(4)]
        hi = [(top[0] + top_r * math.cos(ph + i * math.pi / 2), top[1], top[2] + top_r * math.sin(ph + i * math.pi / 2))
              for i in range(4)]
        for i in range(4):
            i2 = (i + 1) % 4
            quad = [lo[i], lo[i2], hi[i2], hi[i]]
            out = ((lo[i][0] + lo[i2][0]) / 2 - x, 0.0, (lo[i][2] + lo[i2][2]) / 2 - z)
            fr = [0.1, 0.1, 0.9, 0.9]
            facing(mesh, quad, [uv('i_trunk', p, f) for p, f in zip(quad, fr)], out)
        length = rng.uniform(*P['palm_frond'])
        spin = rng.uniform(0, 2 * math.pi)
        for i in range(6):
            a = spin + 2 * math.pi * (i + rng.uniform(-0.15, 0.15)) / 6
            dx, dz = math.cos(a), math.sin(a)
            px, pz = -dz, dx
            L = length * rng.uniform(0.85, 1.1)
            w = L * 0.17
            knee = (top[0] + dx * L * 0.42, top[1] + L * 0.12, top[2] + dz * L * 0.42)
            tip = (top[0] + dx * L, top[1] - L * 0.38, top[2] + dz * L)
            kl = (knee[0] + px * w, knee[1], knee[2] + pz * w)
            kr = (knee[0] - px * w, knee[1], knee[2] - pz * w)
            tl = (tip[0] + px * w * 0.35, tip[1], tip[2] + pz * w * 0.35)
            tr = (tip[0] - px * w * 0.35, tip[1], tip[2] - pz * w * 0.35)
            facing(mesh, [top, kr, kl], [uv('i_palm', top, 0.15), uv('i_palm', kr, 0.6), uv('i_palm', kl, 0.6)], UP)
            facing(mesh, [kl, kr, tr, tl], [uv('i_palm', kl, 0.6), uv('i_palm', kr, 0.6), uv('i_palm', tr, 0.95),
                                            uv('i_palm', tl, 0.95)], UP)

    def build_dressing(self, mesh):
        rng = self.rng
        kd = self.k
        # Crags round the shore, in twos and threes, off the beach (and at its ends).
        crags = []
        count = rng.randint(*kd['crags'])
        groups = max(2, count // 3)
        centres = []
        for g in range(groups):
            for _ in range(30):
                t = rng.uniform(0, 2 * math.pi)
                if self.sandy(t) < 0.3 and all(abs(angle_diff(t, c)) > 0.6 for c in centres):
                    break
            centres.append(t)
        scale = 0.45 + 0.55 * self.size  # smaller islands, smaller crags
        for i in range(count):
            t = centres[i % groups] + rng.uniform(-0.22, 0.22)
            h = rng.uniform(*kd['crag_h']) * scale
            r = h * rng.uniform(0.38, 0.52)
            dist = self.reach(t) + rng.uniform(-0.2, 0.5) * r + P['cliff_toe']
            x, z = self.cx + dist * math.cos(t), self.cz + dist * math.sin(t)
            self.crag(mesh, x, z, h, r)
            crags.append((x, z, r))
        # Sea stacks: a crag or two standing off the shore, inside the shallows.
        for _ in range(rng.randint(*kd['stacks'])):
            t = rng.uniform(0, 2 * math.pi)
            h = rng.uniform(*kd['crag_h']) * 0.7 * scale
            r = h * rng.uniform(0.3, 0.42)
            dist = self.waterline(t) + rng.uniform(10.0, 0.5 * kd['shallows'])
            x, z = self.cx + dist * math.cos(t), self.cz + dist * math.sin(t)
            self.crag(mesh, x, z, h, r)
            self.crag(mesh, x + r * 1.2 * math.cos(t + 1.3), z + r * 1.2 * math.sin(t + 1.3), h * 0.45, r * 0.7,
                      sides=5, rings=((0.0, 1.0), (0.55, 0.6)))
            crags.append((x, z, r * 2.2))
        # Boulders at the waterline, low and wide.
        for _ in range(kd['boulders']):
            t = rng.uniform(0, 2 * math.pi)
            h = rng.uniform(5.0, 11.0)
            r = h * rng.uniform(1.0, 1.4)
            dist = self.waterline(t) + rng.uniform(-0.3, 0.3) * r
            x, z = self.cx + dist * math.cos(t), self.cz + dist * math.sin(t)
            self.crag(mesh, x, z, h, r, sides=5, rings=((0.0, 1.0), (0.55, 0.7)))
            crags.append((x, z, r))
        self.crag_spots = crags
        # Palms: in a clump or two where the jungle meets the beach, and a few on the slope.
        count = max(3, int(round(rng.randint(*kd['palms']) * (0.4 + 0.6 * self.size))))
        for i in range(count):
            t = self.beach_mid + math.radians(rng.uniform(-50, 50))
            edge = self.reach(t)
            b = self.beach(t)
            r = edge + rng.uniform(-0.1 * edge if i % 3 == 2 else -6.0, 0.45 * b)
            x, z = self.cx + r * math.cos(t), self.cz + r * math.sin(t)
            self.palm(mesh, x, z, self.ground(x, z), rng.uniform(*P['palm_h']))

    # -- the painted shallows --------------------------------------------------------------

    def build_shallows(self, mesh):
        """A band close round the coast (offset along the waterline's normals, not out from
        the summit: the first, radial rings read as round halos), feathered into the sea."""
        lift = P['shallows_lift']
        width = self.k['shallows']
        wl = [self.point(t, self.waterline(t), 0.0) for t in self.spokes]
        n = len(wl)
        normals = []
        for i in range(n):
            # the waterline's outward normal, from the neighbours two spokes either side (smooth)
            ax, az = wl[(i - 2) % n][0], wl[(i - 2) % n][2]
            bx, bz = wl[(i + 2) % n][0], wl[(i + 2) % n][2]
            nx, nz = bz - az, -(bx - ax)
            if nx * (wl[i][0] - self.cx) + nz * (wl[i][2] - self.cz) < 0:
                nx, nz = -nx, -nz
            length = math.hypot(nx, nz) or 1.0
            normals.append((nx / length, nz / length))
        rings = []
        for off, v in ((-P['shallows_in'], 1.0), (P['foam_out'], 0.86), (width / 2, P['shallows_mid']),
                       (width, P['shallows_edge'])):
            pts = [(p[0] + nx * off, SEA + lift, p[2] + nz * off) for p, (nx, nz) in zip(wl, normals)]
            rings.append((pts + [pts[0]], v))
        self.shallows_ring = rings[-1][0][:-1]
        # U along the waterline's length for every ring: each ring's own length ran the outer
        # ring's U far ahead of the inner's, and the skew pushed the band to a blurry mip
        # level that pulled its neighbours' opaque alpha in (a pale sector on every ring).
        wl = wl + [wl[0]]
        ua = [0.0]
        for i in range(len(wl) - 1):
            ua.append(ua[-1] + math.hypot(wl[i + 1][0] - wl[i][0], wl[i + 1][2] - wl[i][2]))
        ub = ua
        for k in range(len(rings) - 1):
            (pa, va), (pb, vb) = rings[k], rings[k + 1]
            for i in range(len(pa) - 1):
                quad = [pa[i], pa[i + 1], pb[i + 1], pb[i]]
                uvs = [(mc.trim_u('n_shallows', ua[i]), mc.trim_v('n_shallows', va)),
                       (mc.trim_u('n_shallows', ua[i + 1]), mc.trim_v('n_shallows', va)),
                       (mc.trim_u('n_shallows', ub[i + 1]), mc.trim_v('n_shallows', vb)),
                       (mc.trim_u('n_shallows', ub[i]), mc.trim_v('n_shallows', vb))]
                facing(mesh, quad, uvs, UP)

    def footprint(self):
        """(x, z) points round everything this island puts on the water: the shallows' edge
        and the crags."""
        pts = [(p[0], p[2]) for p in self.shallows_ring]
        for x, z, r in self.crag_spots:
            pts += [(x + r * math.cos(a), z + r * math.sin(a)) for a in (0, 1.57, 3.14, 4.71)]
        return pts


# ---------------------------------------------------------------------------------------------
# Checks: at sea, clear of the boats
# ---------------------------------------------------------------------------------------------

def in_water(x, z, margin):
    """Inside the Terrain water with a margin (city_plan.water_fills), and on the brief's side
    of the coast: past the ocean-side waterline, or behind the tower right of the city's
    shore."""
    W = cp.WORLD
    inside = any(x0 + margin < x < x1 - margin and z0 + margin < z < z1 - margin for x0, z0, x1, z1 in cp.water_fills())
    beyond = x > W['shore_x'] + margin or (z < W['shore_z'] - margin and x > W['city_edge_max'] + margin)
    return inside and beyond


def loop_clearance(pts, loop):
    """The least distance from a closed polygon (its edges) to a boat's loop (an ellipse,
    sampled); negative if the island's middle lies inside the loop."""
    (ex, ez), (rx, rz) = loop
    samples = [(ex + rx * math.cos(math.radians(i)), ez + rz * math.sin(math.radians(i))) for i in range(360)]
    best = float('inf')
    n = len(pts)
    for qx, qz in samples:
        for i in range(n):
            (ax, az), (bx, bz) = pts[i], pts[(i + 1) % n]
            dx, dz = bx - ax, bz - az
            L2 = dx * dx + dz * dz or 1e-9
            t = max(0.0, min(1.0, ((qx - ax) * dx + (qz - az) * dz) / L2))
            best = min(best, math.hypot(ax + dx * t - qx, az + dz * t - qz))
    mx, mz = sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n
    if ((mx - ex) / rx) ** 2 + ((mz - ez) / rz) ** 2 < 1:
        return -best
    return best


def build():
    chunks = {}
    islands = []
    for index, row in enumerate(ISLANDS):
        isle = Island(index, *row)
        land = chunks.setdefault('Islands_%d' % isle.cluster, mc.Mesh('Islands_%d' % isle.cluster))
        water = chunks.setdefault('IslandShallows_%d' % isle.cluster, mc.Mesh('IslandShallows_%d' % isle.cluster))
        isle.build_land(land)
        isle.build_dressing(land)
        isle.build_shallows(water)
        islands.append(isle)
        foot = isle.footprint()
        for x, z in foot:
            assert in_water(x, z, P['water_margin']), ('island %d leaves the water' % index, round(x), round(z))
        for loop in BOAT_LOOPS:
            clear = loop_clearance(foot, loop)
            assert clear >= P['boat_clear'], ('island %d too near a boat loop' % index, loop, round(clear))
    for a in islands:  # open water between any two islands' waterlines
        for b in islands:
            if a.index < b.index:
                gap = min(math.hypot(p[0] - q[0], p[2] - q[2]) for p in a.water for q in b.water)
                assert gap > P['island_gap'], ('islands too close', a.index, b.index, round(gap))
    for name, m in chunks.items():
        lo, hi = m.bounds()
        span = max(hi[i] - lo[i] for i in range(3))
        assert span < P['span_max'], (name, round(span), 'too wide for one MeshPart')
    return sorted(chunks.items())
