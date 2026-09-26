"""Writes the Stage 1 gray-box of the rooftop map as one Luau snippet for Studio.

    python3 assets/map/gen_graybox.py

Reads Layout.json (map_layout.py) and Palette.json, and writes the gray-box as data to
src/server/MapData/GrayBox.json (git-ignored; Rojo syncs it into Studio as a ModuleScript in
ServerScriptService, which players never receive). MapBuilder.buildGrayBox turns it into
Workspace.Map.GrayBox in Edit mode (the snippet is in assets/map/Readme.md), out of plain Parts:
the terrace, stairs, lounge, parapet and railing, invisible safety walls, the pergola, every
prop as coloured blocks at its Spec size, the tower, a block city, island cones and Terrain
water. It is safe to run twice: it clears GrayBox and refills the same water regions. It
removes Workspace.Baseplate and moves the SpawnLocation to Config's spawn. Nothing here is a
script; the gray-box is replaced stage by stage by the Blender meshes.
"""

import json
import math
import os
import random
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_layout as ml  # noqa: E402

SEED = 26092026  # the block city and the islands
OUT = os.path.join(HERE, '..', '..', 'src', 'server', 'MapData', 'GrayBox.json')

# The world round the rooftop (Spec section 7).
STREET_Y = -300.0
SEA_Y = -302.0
COAST_X = 110.0  # water to the right of this...
COAST_Z = -150.0  # ...and behind this, between CITY_BACK_X and COAST_X
CITY_BACK_X = -350.0  # the city carries on behind the tower on the left...
CITY_CREEP = 0.12  # ...its shore bending in toward the middle of the view with distance...
CITY_EDGE_MAX = -200.0  # ...but never past this, so the sea stays behind the pergola
MAX_PART = 2000.0  # Roblox clamps a Part at 2048 studs; big slabs are tiled
WATER_REACH = 6500.0  # Terrain water out to this far (the islands stand in it)...
FAR_REACH = 8000.0  # ...then flat sea and ground slabs to here, so no edge shows before the haze

with open(os.path.join(HERE, 'Palette.json')) as handle:
    PALETTE = json.load(handle)


def hexc(name):
    return PALETTE[name]['hex']


C = {
    'floor': hexc('floor_panel_day'),
    'stone': hexc('step'),
    'cream': hexc('column'),
    'slat': hexc('pergola_slat'),
    'frame': hexc('railing_frame'),
    'glass': hexc('railing_glass'),
    'glow': hexc('under_table_glow'),
    'led': hexc('led_strip'),
    'couch': hexc('couch_day'),
    'cushion_blue': hexc('cushion_blue'),
    'cushion_orange': hexc('cushion_orange'),
    'wood_dark': PALETTE['coffee_table']['shade'],
    'wood_top': hexc('coffee_table'),
    'stone_dark': hexc('firepit_stone'),
    'fire': hexc('fire'),
    'lantern_frame': hexc('lantern_frame'),
    'lantern_glass': hexc('lantern_glass'),
    'globe': hexc('globe_light'),
    'canvas': hexc('umbrella_canvas_day'),
    'pole': hexc('umbrella_pole'),
    'lounger': hexc('lounger'),
    'piano': hexc('piano_black'),
    'leaf': hexc('leaf_mid'),
    'palm': hexc('palm_mid'),
    'trunk': hexc('palm_trunk'),
    'facade': hexc('city_facade_day'),
    'glass_city': hexc('city_glass_day'),
    'city_far': hexc('city_far_day'),
    'island': hexc('island_green'),
    'rock': hexc('island_rock'),
    'sand': hexc('sand'),
    'street': '#8C8A92',
}


class Lua:
    """Collects part rows: (folder, name, shape, size, cframe expression, colour, flags)."""

    def __init__(self):
        self.rows = []

    def part(self, folder, name, size, pos, colour, yaw=0.0, shape='Block', material='SmoothPlastic',
             transparency=0.0, collide=False, local=None, rot=None, shadow=True):
        """pos is world (x, y, z) of the part's centre, or with `local` the prop's (X, Y, Z, yaw)
        and pos in the prop's own frame. rot is an extra (rx, ry, rz) in degrees."""
        self.rows.append({
            'f': folder, 'n': name, 's': shape, 'size': [round(v, 4) for v in size],
            'p': [round(v, 4) for v in pos], 'c': colour, 'yaw': yaw, 'm': material,
            't': transparency, 'k': collide, 'local': local, 'rot': rot, 'shadow': shadow,
        })


def build(g, plan):
    zones = plan['zones']
    P = ml.P
    tx0, tz0, tx1, tz1 = zones['terrace']
    front = tz1
    sx = P['steps_width'] / 2
    stair_end = zones['steps'][3]
    lower_end = zones['lower_landing'][3]
    lower_y = plan['heights']['lower_landing']
    platform_y = plan['heights']['lounge']
    pt = P['parapet_thickness']
    ph = P['parapet_height']
    top = P['railing_top']
    wall_top = P['safety_wall_top']

    # ---- Rooftop -------------------------------------------------------------------------
    R = 'Rooftop'
    g.part(R, 'Floor', (tx1 - tx0, 1, tz1 - tz0), ((tx0 + tx1) / 2, -0.5, (tz0 + tz1) / 2), C['floor'], collide=True)
    # Entrance stair, down toward +Z, and the lower landing.
    n, rise, run = P['step_count'], P['step_rise'], P['step_run']
    for k in range(n):
        top_y = -rise * (k + 1)
        g.part(R, 'Step%02d' % (k + 1), (2 * sx, top_y + 6, run),
               (0, (top_y - 6) / 2, front + run * (k + 0.5)), C['stone'], collide=True)
    g.part(R, 'LowerLanding', (2 * sx, 1, lower_end - stair_end), (0, lower_y - 0.5, (stair_end + lower_end) / 2),
           C['floor'], collide=True)
    # Lounge platform and its central flight (going back, up).
    lx0, lz0, lx1, lz1 = zones['lounge']
    g.part(R, 'LoungePlatform', (lx1 - lx0, platform_y, lz1 - lz0), (0, platform_y / 2, (lz0 + lz1) / 2),
           C['floor'], collide=True)
    fx0, fz0, fx1, fz1 = zones['lounge_steps']
    m, lrise, lrun = P['lounge_step_count'], P['lounge_step_rise'], P['lounge_step_run']
    for k in range(m):
        h = lrise * (k + 1)
        g.part(R, 'LoungeStep%d' % (k + 1), (fx1 - fx0, h, lrun), (0, h / 2, fz1 - lrun * (k + 0.5)),
               C['stone'], collide=True)

    # Parapet, glass railing, top rail, posts and the invisible wall, along a run of edge.
    def edge(name, a, b, floor_y, outward):
        """A straight edge from a to b (x, z) with the terrace on the side opposite `outward`
        (a unit (dx, dz)); floor_y is the walking level beside it."""
        (ax, az), (bx, bz) = a, b
        length = math.hypot(bx - ax, bz - az)
        mx, mz = (ax + bx) / 2 + outward[0] * pt / 2, (az + bz) / 2 + outward[1] * pt / 2
        along_x = abs(bx - ax) > abs(bz - az)
        def sz(w, h, t):
            return (w, h, t) if along_x else (t, h, w)
        base = floor_y - 6 if floor_y < 0 else -1
        g.part(R, name + 'Parapet', sz(length + pt, floor_y + ph - base, pt), (mx, (floor_y + ph + base) / 2, mz),
               C['stone'], collide=True)
        g.part(R, name + 'Glass', sz(length, top - ph, 0.2), (mx, floor_y + (top + ph) / 2, mz), C['glass'],
               material='Glass', transparency=0.6, collide=True)
        g.part(R, name + 'TopRail', sz(length + pt, 0.3, 0.35), (mx, floor_y + top, mz), C['frame'], collide=True)
        posts = max(1, round(length / 4.0))
        for k in range(posts + 1):
            t = k / posts
            g.part(R, name + 'Post', (0.25, top - ph, 0.25), (ax + (bx - ax) * t + outward[0] * pt / 2,
                                                             floor_y + (top + ph) / 2,
                                                             az + (bz - az) * t + outward[1] * pt / 2), C['frame'])
        g.part(R, name + 'SafetyWall', sz(length + pt, wall_top - (floor_y + top), pt),
               (mx, (wall_top + floor_y + top) / 2, mz), '#FFFFFF', transparency=1, collide=True)

    lw = P['lounge_half_width']
    edge('Back', (tx0, tz0), (-lw, tz0), 0.0, (0, -1))
    edge('BackLounge', (-lw, tz0), (lw, tz0), platform_y, (0, -1))
    edge('Back', (lw, tz0), (tx1, tz0), 0.0, (0, -1))
    edge('City', (tx0, tz0), (tx0, tz1), 0.0, (-1, 0))
    edge('Ocean', (tx1, tz0), (tx1, tz1), 0.0, (1, 0))
    edge('Front', (tx0, tz1), (-sx, tz1), 0.0, (0, 1))
    edge('Front', (sx, tz1), (tx1, tz1), 0.0, (0, 1))
    # The stair runs down between two walls to the lower landing's railing.
    for side, name in ((-1, 'StairWallCity'), (1, 'StairWallOcean')):
        x = side * (sx + pt / 2)
        g.part(R, name, (pt, ph + 6 + 1, lower_end - front), (x, (ph + 1 - 6 + lower_y) / 2 + 0.0, (front + lower_end) / 2),
               C['stone'], collide=True)
        g.part(R, name + 'SafetyWall', (pt, wall_top - ph, lower_end - front), (x, (wall_top + ph) / 2, (front + lower_end) / 2),
               '#FFFFFF', transparency=1, collide=True)
    edge('LowerLanding', (-sx, lower_end), (sx, lower_end), lower_y, (0, 1))

    # Pergola: columns come with the props; beams and slats here.
    px0, pz0, px1, pz1 = zones['pergola']
    beam_y = platform_y + P['pergola_height']
    for name, z in (('FrontBeam', pz1 - P['pergola_column'] / 2), ('BackBeam', pz0 + P['pergola_column'] / 2),
                    ('MidBeam', (pz0 + pz1) / 2)):
        g.part(R, 'Pergola' + name, (px1 - px0 + 3, 1.6, 1.4), (0, beam_y + 0.8, z), C['cream'], collide=True)
    x = px0 + 1.5
    while x < px1 - 0.5:
        g.part(R, 'PergolaSlat', (1.2, 0.6, pz1 - pz0 + 2), (x, beam_y + 1.9, (pz0 + pz1) / 2), C['slat'],
               shadow=False)  # no zebra stripes until the lighting stage
        x += 3.0
    # Vines along the front beam: a few green clumps, a pink one at the ocean end (02).
    for k, vx in enumerate((px0 + 2, -30, 0.0, 30, px1 - 2)):
        colour = hexc('flower_vivid') if k == 4 else C['leaf']
        g.part(R, 'Vine', (4.0, 2.0, 1.4), (vx, beam_y + 0.4, pz1 + 0.6), colour, shadow=False)

    # ---- Props ---------------------------------------------------------------------------
    for i, p in enumerate(plan['props']):
        prop(g, p, i)

    # ---- The tower and the near world -------------------------------------------------------
    N = 'Near'
    depth = -1 - STREET_Y
    g.part(N, 'Tower', (tx1 - tx0 + 2 * pt, depth, tz1 - tz0 + 2 * pt), ((tx0 + tx1) / 2, (-1 + STREET_Y) / 2, (tz0 + tz1) / 2),
           C['facade'])
    g.part(N, 'TowerStairBay', (2 * (sx + pt), lower_y - 1 - STREET_Y, lower_end - front + pt),
           (0, (lower_y - 1 + STREET_Y) / 2, (front + lower_end + pt) / 2), C['facade'])
    # Land: the city's ground front-left of the coast and, behind the tower, left of
    # CITY_BACK_X; sand strips along the water's edge. Big slabs are tiled under the Part limit.
    R_ = WATER_REACH
    slab(g, N, 'Land', (-R_, COAST_Z, COAST_X, R_), STREET_Y - 4, STREET_Y, C['street'])
    slab(g, N, 'Beach', (COAST_X, COAST_Z - 60, COAST_X + 60, R_), SEA_Y - 1, SEA_Y + 2, C['sand'])
    slab(g, N, 'Beach', (CITY_BACK_X, COAST_Z - 60, COAST_X, COAST_Z), SEA_Y - 1, SEA_Y + 2, C['sand'])
    # Behind the tower the shore bends in with distance: land and beach in 150-deep steps.
    z = COAST_Z
    while z > -R_:
        z0 = max(z - 150.0, -R_)
        edge = city_edge_x((z + z0) / 2)
        slab(g, N, 'Land', (-R_, z0, edge, z), STREET_Y - 4, STREET_Y, C['street'])
        slab(g, N, 'Beach', (edge, z0, edge + 50, z), SEA_Y - 1, SEA_Y + 2, C['sand'])
        z = z0
    # Beyond the Terrain water and the land, flat slabs to the horizon (a hair under the water
    # line so they never fight the Terrain's surface).
    F_ = FAR_REACH
    # Darker than water_far: the slab takes the sun directly where the Terrain water does not, so
    # this is the albedo that renders like the far water (sampled from a Stage 1 capture).
    far_sea = '#5A82A8'
    for rect in ((R_, -F_, F_, F_), (COAST_X, R_, R_, F_), (CITY_EDGE_MAX, -F_, R_, -R_)):
        slab(g, 'Backdrop', 'SeaFar', rect, SEA_Y - 3, SEA_Y - 0.6, far_sea)
    for rect in ((-F_, -F_, -R_, F_), (-R_, R_, COAST_X, F_), (-R_, -F_, CITY_EDGE_MAX, -R_)):
        slab(g, 'Backdrop', 'LandFar', rect, STREET_Y - 4, STREET_Y, C['street'])

    # ---- Backdrop: the city on a street grid, and the islands (seeded) ------------------------
    rng = random.Random(SEED)
    B = 'Backdrop'
    city(g, rng, B)
    # Islands: steep green cones over the sea, toward the ocean and behind; one beside the sunset
    # sun (azimuth 36, Spec section 6).
    # Far out (3500 to 6000) like the art's: two big peaks, one straight behind the pergola and
    # one beside the sunset sun (azimuth 36, Spec section 6), and smaller islands in two
    # clusters with radii varying about 3:1.
    islands = [(3.0, 4800, 520, 950), (36.4 + 7, 5200, 480, 850)]
    for centre, count in ((70.0, 4), (115.0, 4)):
        for k in range(count):
            az = centre + rng.uniform(-12, 12)
            dist = rng.uniform(3500, 6000)
            radius = rng.uniform(90, 270)
            height = rng.uniform(150, 350)
            islands.append((az, dist, radius, height))
    for k, (az, dist, radius, height) in enumerate(islands):
        a = math.radians(az)
        cx, cz = dist * math.sin(a), -dist * math.cos(a)
        steps = 12
        for s in range(steps):
            r = radius * (1 - s / steps) ** 1.15
            h = height / steps
            y = SEA_Y + h * (s + 0.5)
            g.part(B, 'Island%02d' % k, (h, 2 * r, 2 * r), (cx, y, cz), C['island'] if s else C['sand'],
                   shape='Cylinder', rot=(0, 0, 90))


def city_edge_x(z):
    """The city's shore on the right (its largest X) at a Z behind the tower: it bends in
    toward the middle of the view from the spawn with distance, so the city fills more of the
    way the player faces (designer, 2026-09-26)."""
    if z >= COAST_Z:
        return COAST_X
    return min(CITY_EDGE_MAX, CITY_BACK_X + (COAST_Z - z) * CITY_CREEP)


def slab(g, folder, name, rect, y0, y1, colour):
    """A flat slab over rect (x0, z0, x1, z1) from y0 to y1, tiled under the Part size limit."""
    x0, z0, x1, z1 = rect
    nx = max(1, math.ceil((x1 - x0) / MAX_PART))
    nz = max(1, math.ceil((z1 - z0) / MAX_PART))
    for i in range(nx):
        for j in range(nz):
            a, b = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
            c, d = z0 + (z1 - z0) * j / nz, z0 + (z1 - z0) * (j + 1) / nz
            g.part(folder, name, (b - a, y1 - y0, d - c), ((a + b) / 2, (y0 + y1) / 2, (c + d) / 2), colour)


CITY_PITCH = 110.0  # a city block and its street
CITY_BLOCK = 80.0  # the block itself (the street is the rest)
CITY_REACH = 2300.0  # blocks out to this far; the horizon beyond is Stage 6's cards


def city(g, rng, folder):
    """The city on a street grid. The blocks ahead of the spawn and to its left (the way the
    player faces) are all built, with towers rising over the railing; behind the spawn (+Z,
    the stair side) the city thins out and stays low. Each lot is a podium, a shaft and, on
    the tall ones, a crown."""
    half = CITY_BLOCK / 2
    n = int(CITY_REACH // CITY_PITCH) + 1
    for i in range(-n, 2):
        for j in range(-n, n + 1):
            cx, cz = (i + 0.5) * CITY_PITCH, (j + 0.5) * CITY_PITCH
            x0, x1, z0, z1 = cx - half, cx + half, cz - half, cz + half
            d = math.hypot(cx, cz)
            if d > CITY_REACH:
                continue
            # On the land: front-left of the coast, or left of the bending shore behind.
            if z1 > COAST_Z - 20 and x1 > COAST_X - 30:
                continue
            if z0 < COAST_Z and x1 > city_edge_x(z0) - 30:
                continue
            # The tower's own lot and plaza, and the beach promenade front-right, stay clear.
            if x1 > -160 and x0 < 160 and z1 > -180 and z0 < 170:
                continue
            if x1 > 20 and z1 > -130:
                continue
            behind = cz > 250  # behind the spawn: the stair side, seldom looked at
            if behind and rng.random() < 0.55:
                continue
            # A sidewalk slab for the near blocks.
            if d < 1200:
                g.part(folder, 'Block', (CITY_BLOCK, 1.0, CITY_BLOCK), (cx, STREET_Y + 0.5, cz), '#B9B3B7')
            lots = rng.choice((1, 2, 2, 4))
            for k in range(lots):
                if lots == 1:
                    lx, lz, lw, ld = cx, cz, CITY_BLOCK - 8, CITY_BLOCK - 8
                elif lots == 2:
                    lx, lz, lw, ld = cx + (k - 0.5) * half, cz, half - 6, CITY_BLOCK - 8
                else:
                    lx, lz, lw, ld = cx + ((k % 2) - 0.5) * half, cz + ((k // 2) - 0.5) * half, half - 6, half - 6
                building(g, rng, folder, lx, lz, lw, ld, d, behind)


def building(g, rng, folder, x, z, w, d_, dist, behind):
    """One lot: a podium, a shaft and maybe a crown. Heights from the street (Y -300); the
    roof is 300 up. Within 700 of the tower everything stays below the roof; further out some
    slim towers rise over it, more of them the further out, so the skyline shows over the city
    railing."""
    top = 1.0 if dist < 1200 else 0.0  # stand on the sidewalk slab where there is one
    # Towers that rise over the roof are slimmer than the blocks round them.
    podium = rng.uniform(12, 30)
    if behind:
        height = rng.uniform(40, 120)
    elif dist < 700:
        height = rng.uniform(50, 230)  # close by, everything stays below the roof
    elif dist < 1500:
        height = 300 + rng.uniform(30, 150) if rng.random() < 0.16 else rng.uniform(80, 260)
    else:
        height = 300 + rng.uniform(60, 240) if rng.random() < 0.3 else rng.uniform(140, 300)
    far = dist > 1600
    glass = rng.random() < 0.4
    shaft_colour = C['city_far'] if far else (C['glass_city'] if glass else C['facade'])
    base_y = STREET_Y + top
    g.part(folder, 'Podium', (w, podium, d_), (x, base_y + podium / 2, z), C['facade'])
    if height <= podium + 4:
        return
    slim = (0.45, 0.65) if height > 300 else (0.6, 0.85)
    sw, sd = w * rng.uniform(*slim), d_ * rng.uniform(*slim)
    shaft = height - podium
    tall = height > 280
    crown = rng.uniform(12, 30) if tall else 0.0
    g.part(folder, 'Shaft', (sw, shaft - crown, sd), (x, base_y + podium + (shaft - crown) / 2, z), shaft_colour)
    if crown:
        g.part(folder, 'Crown', (sw * 0.55, crown, sd * 0.55), (x, base_y + height - crown / 2, z),
               C['glass_city'] if not glass else C['facade'])


def prop(g, p, i):
    kind = p['kind']
    L = (p['X'], p['Y'], p['Z'], p['yaw'])
    w, h, d = p['size']
    F = 'Props'
    name = '%s_%02d' % (kind, i)

    def part(size, pos, colour, **kw):
        g.part(F, name, size, pos, colour, local=L, **kw)

    if kind == 'table_glow':
        part((w, 0.05, d), (0, 0.03, 0), C['glow'], material='Neon', transparency=0.88)
    elif kind == 'fern_planter':
        part((w, 3.0, d), (0, 1.5, 0), C['stone'], collide=True)
        part((4.4, 4.4, 4.4), (0, 5.0, 0), C['leaf'], shape='Ball')
    elif kind == 'palm_planter':
        part((w, 3.2, d), (0, 1.6, 0), C['stone'], collide=True)
        part((1.1, h - 7, 1.1), (0, 3.2 + (h - 7) / 2, 0), C['trunk'])
        # A Ball part is as big as its smallest side, so the flat crown is a disc.
        part((3.0, 18, 18), (0, h - 4, 0), C['palm'], shape='Cylinder', rot=(0, 0, 90), shadow=False)
    elif kind == 'planter_bed':
        part((w, 2.5, d), (0, 1.25, 0), C['stone'], collide=True)
        part((w - 0.4, 2.2, d + 0.8), (0, 3.4, 0), C['leaf'])
    elif kind in ('lantern', 'lantern_tall'):
        part((w, h, d), (0, h / 2, 0), C['lantern_frame'], collide=True)
        part((w - 0.3, h * 0.7, d + 0.02), (0, h * 0.5, 0), C['lantern_glass'], material='Neon')
        part((w + 0.02, h * 0.7, d - 0.3), (0, h * 0.5, 0), C['lantern_glass'], material='Neon')
    elif kind == 'umbrella_set':
        part((0.4, 10, 0.4), (0, 5, 0), C['pole'], collide=True)
        # A square pyramid-ish canopy (a hipped gable of two wedges), rim at 9, peak at 11.
        part((12, 2, 6), (0, 10, 3), C['canvas'], shape='Wedge', shadow=False)
        part((12, 2, 6), (0, 10, -3), C['canvas'], shape='Wedge', rot=(0, 180, 0), shadow=False)
        for lx in (-1.8, 1.8):
            part((2.0, 1.0, 5.6), (lx, 0.5, 0.6), C['lounger'], collide=True)
            part((2.0, 1.4, 0.4), (lx, 1.6, -2.0), C['lounger'], rot=(-30, 0, 0))
    elif kind == 'side_couch':
        part((11, 1.3, 3), (0, 0.65, -1.4), C['couch'], collide=True)
        part((11, 1.3, 0.8), (0, 1.95, -2.5), C['couch'], collide=True)
        for k, lx in enumerate((-3.5, -1.2, 1.2, 3.5)):
            part((1.6, 1.3, 0.5), (lx, 1.95, -1.9), C['cushion_blue'] if k % 2 == 0 else C['cushion_orange'])
        part((2.9, 1.1, 2.4), (0, 0.55, 1.6), C['wood_dark'], collide=True)
    elif kind == 'lounge_couch':
        part((w, 1.3, 3.0), (0, 0.65, -d / 2 + 1.5), C['couch'], collide=True)
        part((w, 1.3, 0.8), (0, 1.95, -d / 2 + 0.4), C['couch'], collide=True)
        for side in (-1, 1):
            part((3.0, 1.3, d - 3.0), (side * (w / 2 - 1.5), 0.65, 1.5), C['couch'], collide=True)
            part((0.8, 1.3, d - 3.0), (side * (w / 2 - 0.4), 1.95, 1.5), C['couch'], collide=True)
        for k, lx in enumerate((-6, -2, 2, 6)):
            part((2.2, 1.3, 0.5), (lx, 1.95, -d / 2 + 1.1), C['cushion_blue'] if k % 2 == 0 else C['cushion_orange'])
    elif kind == 'coffee_table':
        part((h, w, d), (0, h / 2, 0), C['wood_top'], shape='Cylinder', rot=(0, 0, 90), collide=True)
    elif kind == 'fire_pit':
        part((h, w, d), (0, h / 2, 0), C['stone_dark'], shape='Cylinder', rot=(0, 0, 90), collide=True)
        part((1.2, 2.0, 2.0), (0, h + 0.4, 0), C['fire'], shape='Cylinder', rot=(0, 0, 90), material='Neon')
    elif kind == 'piano':
        part((w, 2.2, d), (0, 1.9, 0), C['piano'], collide=True)
        part((w, 0.2, d * 0.8), (0, 3.4, -0.3), C['piano'], rot=(-25, 0, 0))
    elif kind == 'piano_bench':
        part((w, h, d), (0, h / 2, 0), C['piano'], collide=True)
    elif kind == 'snack_counter':
        part((w, 3.2, 2.4), (0, 1.6, d / 2 - 1.2), C['cream'], collide=True)
        part((w, 0.25, 2.6), (0, 3.3, d / 2 - 1.2), C['wood_top'])
        part((w, 0.3, 0.1), (0, 3.0, d / 2 + 0.02), C['led'], material='Neon')
        # Lit shelves in two units at the ends, so the sea shows over the middle of the bar.
        for side in (-1, 1):
            part((7.0, 6.0, 1.0), (side * (w / 2 - 3.5), 3.0, -d / 2 + 0.5), C['wood_dark'], collide=True)
            for k in range(2):
                part((6.4, 0.2, 0.9), (side * (w / 2 - 3.5), 3.6 + 1.6 * k, -d / 2 + 1.1), C['led'])
    elif kind == 'globe_light':
        part((w, w, w), (0, 0, 0), C['globe'], shape='Ball', material='Neon')
        part((0.08, 3.0, 0.08), (0, 1.5, 0), C['frame'])
    elif kind == 'column':
        part((w, h, d), (0, h / 2, 0), C['cream'], collide=True)
    else:
        raise SystemExit('no gray-box for ' + kind)


def main():
    plan = ml.build()
    problems = ml.check(plan)
    if problems:
        raise SystemExit('layout problems: ' + '; '.join(problems))
    g = Lua()
    build(g, plan)
    rows = []
    for r in g.rows:
        row = {'f': r['f'], 'n': r['n'], 's': r['s'], 'size': r['size'], 'p': r['p'], 'c': r['c'],
               'yaw': r['yaw'], 'm': r['m'], 't': r['t'], 'k': r['k']}
        if r['local'] is not None:
            row['local'] = [round(v, 4) for v in r['local']]
        if r['rot'] is not None:
            row['rot'] = list(r['rot'])
        if not r['shadow']:
            row['ns'] = True
        rows.append(row)
    s = plan['spawn']
    data = {
        'rows': rows,
        'water': {'seaY': SEA_Y, 'reach': WATER_REACH, 'coastX': COAST_X, 'coastZ': COAST_Z,
                  'cityBackX': CITY_BACK_X},
        'spawn': [s['X'], s['Y'], s['Z']],
        'spawnSize': s['size'],
        'spawnColour': hexc('lounger'),
    }
    text = json.dumps(data, separators=(',', ':'), sort_keys=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as handle:
        handle.write(text + '\n')
    lua = text
    kinds = {}
    for r in g.rows:
        kinds[r['f']] = kinds.get(r['f'], 0) + 1
    print('%d parts (%s), %d bytes -> %s' % (len(g.rows), ', '.join('%s %d' % kv for kv in sorted(kinds.items())),
                                            len(lua), os.path.relpath(OUT)))


if __name__ == '__main__':
    main()
