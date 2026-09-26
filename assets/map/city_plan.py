"""The world round the rooftop, as numbers and a plan (Spec section 7): the street and sea
levels, the coast, and the city's street grid with every lot on it. Pure Python (no bpy), shared
by gen_graybox.py (the gray-box), gen_near.py (the near world, Stage 4) and the skyline
generator (Stage 5), so they all build the same city. map_layout.py copies WORLD into
Layout.json for the Lune tests.
"""

import math
import random

CITY_SEED = 26092026  # the city's random numbers (each block's own: block_seed)

# ---------------------------------------------------------------------------------------------
# The world (studs; Roblox axes: the ocean is +X and behind the tower, -Z)
# ---------------------------------------------------------------------------------------------

WORLD = {
    'street_y': -300.0,  # the street round the tower (the roof is at 0: about 30 floors up)
    'sea_y': -304.0,  # the sea's surface: on the Terrain's 4-stud voxel grid, so the water is crisp
                      # (at -302 it half-filled two voxels), and 4 under the street so the beach slopes
    # The coast (Stage 4 moved the waterline out from X 110 and Z -150, so a promenade and a
    # beach fit between the tower and the sea). From the tower out: the street, the promenade
    # (paved, at street level, on top of the sea wall), the beach (sand, down to the water),
    # then the sea.
    'shore_x': 205.0,  # the waterline on the ocean side...
    'shore_z': -215.0,  # ...and behind the tower, between city_back_x and shore_x
    'beach': 50.0,  # sand from the sea wall down to the waterline
    'promenade': 30.0,  # the paved walk along the top of the sea wall
    'city_back_x': -350.0,  # the city carries on behind the tower on the left...
    'city_bend_z': -150.0,  # ...its shore bending in from here (pinned: the coast moved, the bend did not)...
    'city_creep': 0.12,  # ...toward the middle of the view with distance...
    'city_edge_max': -200.0,  # ...but never past this, so the sea stays behind the pergola
    'water_depth': 4.0,  # Terrain water, this deep under the surface
    'land_drop': 0.6,  # the gray-box land's top sits this far under the street, under the near ground
    'near_radius': 450.0,  # city blocks with their centre this close belong to the near world (Stage 4)
    # Beyond the near world a building is at most height_cap_base tall at the near radius, the cap
    # rising height_cap_slope a stud outward, so the city steps up from low blocks near the tower
    # to towers in the middle distance, as in the art (Stage 5 critic: the near ring was a wall).
    'height_cap_base': 150.0,  # (Stage 5 critic 2: only landmarks over the roof close in)
    'height_cap_slope': 0.2,
    'near_coast': 1000.0,  # the near world's beach runs this far along the coast; the gray-box's beyond
    'max_part': 2000.0,  # Roblox clamps a Part at 2048 studs: big slabs are tiled
    'water_reach': 2600.0,  # the 3D Terrain water and land out to this far (a square); beyond, the
                            # skybox holds everything, painted from the roof by gen_sky.py (Stage 6):
                            # anything 3D further out would hide the painting behind it
    'far_reach': 7000.0,  # the far city, painted into the skybox, from city_reach out to this far
    'city_pitch': 110.0,  # a city block and its street
    'city_block': 80.0,  # the block itself (the street is the rest)
    'city_reach': 2300.0,  # the 3D city out to this far (Stage 5); beyond, it is painted (Stage 6)
}

# The city's shape beyond the near world (the near world keeps its own line, Z 250, so Near.fbx
# is unchanged). Stage 6 critic 2: a straight line showed as a hard vertical edge in the
# city-side view, and the 3D city's tallest towers stood right at its edge, a wall before the
# painting.
CITY = {
    # Behind the spawn (the stair side) the city thins out and stays low, easing in by bearing
    # from the tower (0 straight ahead, 90 the city side, 180 behind): none at behind_from...
    'behind_from': 90.0,
    'behind_to': 135.0,  # ...all of it here
    'behind_drop': 0.55,  # a fully behind block is left out this often
    'outer_taper': 400.0,  # the 3D city's outer ring this deep steps down toward the painting...
    'outer_drop': 0.4,  # ...its heights down this much at the very edge
    # The far city (painted): towers gather in the downtowns and the city between them is a
    # low carpet, so the horizon has a skyline's hierarchy instead of an even barcode.
    'far_tower_base': 0.02,  # a far lot is a tower this often away from any downtown...
    'far_tower_core': 0.75,  # ...and this much more often at a downtown's heart, where they rise
    'far_tower_rise': 280.0,  # this much taller (away from the downtowns a tower barely clears the roof)
    'far_lot_counts': (1, 1, 2),  # lots per far block: fewer, wider towers than the mid city's
}

# The far downtowns: (bearing from straight ahead toward the city (-X) in degrees, distance,
# radius). Ahead-left, where the player faces, and clear of the pergola's opening from the
# spawn (about 20 degrees either side of straight ahead); the six painted landmarks stand in them.
FAR_DOWNTOWNS = [
    (34.0, 3300.0, 500.0),
    (62.0, 4600.0, 650.0),
    (96.0, 3100.0, 500.0),
]


def land_x():
    """Where the land (street level) ends on the ocean side and the beach begins."""
    return WORLD['shore_x'] - WORLD['beach']


def land_z():
    """Where the land ends behind the tower and the beach begins."""
    return WORLD['shore_z'] + WORLD['beach']


def city_edge_x(z):
    """The city's shore on the right (its largest X) at a Z behind the waterline: it bends in
    toward the middle of the view from the spawn with distance, so the city fills more of the
    way the player faces (designer, 2026-09-26)."""
    W = WORLD
    if z >= W['shore_z']:
        return W['shore_x']
    return min(W['city_edge_max'], W['city_back_x'] + (W['city_bend_z'] - z) * W['city_creep'])


def buildable(x0, z0, x1, z1, margin=10.0):
    """Whether a city block fits on the land with a street's margin to spare: left of the
    ocean-side promenade, and clear of the back promenade and beach (only the city beyond
    city_back_x reaches back there), and left of the bending shore behind the waterline."""
    W = WORLD
    if z0 < W['shore_z']:
        return x1 < city_edge_x(z0) - 30
    if z0 < land_z() + W['promenade'] + margin:
        return x1 < W['city_back_x'] - 30
    return x1 < land_x() - W['promenade'] - margin


def water_fills():
    """The Terrain water as (x0, z0, x1, z1) rectangles: from the sea wall's foot outward on
    the ocean side, and behind the tower between the city and the ocean side. It runs on
    under the beach (the sand lies above it), so a curved waterline always meets water."""
    W = WORLD
    r = W['water_reach']
    return [(land_x(), -r, r, r), (W['city_back_x'], -r, land_x(), land_z())]


# ---------------------------------------------------------------------------------------------
# The city: blocks on a street grid, each with one to four lots
# ---------------------------------------------------------------------------------------------

def block_seed(seed, i, j):
    """An integer seed for block (i, j) (random.Random needs an int or a string: tuples fail
    on Python 3.11 and later). Each block has its own, so changing the coast or the near
    radius re-rolls only the blocks it touches."""
    return seed * 1_000_003 + (i + 1000) * 4099 + (j + 1000)


def city_blocks():
    """The city as the gray-box and the near world build it (CITY_SEED, a source per block)."""
    return blocks(lambda i, j: random.Random(block_seed(CITY_SEED, i, j)))


def far_blocks():
    """The far city, painted into the skybox (gen_sky.py, Stage 6): the blocks from city_reach
    out to far_reach, on the same grid and land, seeded per block like the rest. Its towers
    are taller and more frequent than the mid city's (far_lot), so the thin band of skyline
    at the horizon, all a phone sees of the city, reads as a skyline."""
    W = WORLD
    return blocks(lambda i, j: random.Random(block_seed(CITY_SEED, i, j)),
                  reach=(W['city_reach'], W['far_reach']), make_lot=far_lot, counts=CITY['far_lot_counts'])


def behind_share(cx, cz, dist):
    """How far a block is into the stair side behind the spawn, 0 to 1: the near world by its
    old line (Z 250), beyond it eased in by bearing (CITY behind_from to behind_to)."""
    if dist < WORLD['near_radius']:
        return 1.0 if cz > 250 else 0.0
    bearing = math.degrees(math.atan2(-cx, -cz))
    t = (bearing - CITY['behind_from']) / (CITY['behind_to'] - CITY['behind_from'])
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


def blocks(rng_for, reach=None, make_lot=None, counts=(1, 2, 2, 4)):
    """Every city block, in grid order, with its lots. rng_for(i, j) gives the random source
    for block (i, j) (random.Random(block_seed(SEED, i, j)) in the generators). The blocks ahead
    of the spawn and to its left (the way the player faces) are all built, with towers rising
    over the railing; behind the spawn (+Z, the stair side) the city thins out and stays low
    (behind_share). counts: the lots a block may have, drawn evenly.

    A block: {'i', 'j', 'cx', 'cz', 'dist', 'behind', 'sidewalk', 'near', 'lots'}; a lot: see
    lot(). 'near' blocks are the near world's (gen_near.py builds them, Stage 4)."""
    W = WORLD
    pitch, size = W['city_pitch'], W['city_block']
    half = size / 2
    near_d, far_d = reach or (0.0, W['city_reach'])
    make_lot = make_lot or lot
    n = int(far_d // pitch) + 1
    out = []
    for i in range(-n, 2):
        for j in range(-n, n + 1):
            cx, cz = (i + 0.5) * pitch, (j + 0.5) * pitch
            x0, x1, z0, z1 = cx - half, cx + half, cz - half, cz + half
            d = math.hypot(cx, cz)
            if d > far_d or d <= near_d:
                continue
            if not buildable(x0, z0, x1, z1):
                continue
            # The tower's own lot and plaza, and the beach promenade front-right, stay clear.
            if x1 > -160 and x0 < 160 and z1 > -180 and z0 < 170:
                continue
            if x1 > 20 and z1 > -130:
                continue
            rng = rng_for(i, j)
            behind = behind_share(cx, cz, d)  # the stair side, seldom looked at
            if behind > 0.0 and rng.random() < CITY['behind_drop'] * behind:
                continue
            block = {'i': i, 'j': j, 'cx': cx, 'cz': cz, 'dist': d, 'behind': behind,
                     'sidewalk': d < 1200, 'near': d < W['near_radius'], 'lots': []}
            count = rng.choice(counts)
            for k in range(count):
                if count == 1:
                    lx, lz, lw, ld = cx, cz, size - 8, size - 8
                elif count == 2:
                    lx, lz, lw, ld = cx + (k - 0.5) * half, cz, half - 6, size - 8
                else:
                    lx, lz, lw, ld = cx + ((k % 2) - 0.5) * half, cz + ((k // 2) - 0.5) * half, half - 6, half - 6
                block['lots'].append(make_lot(rng, lx, lz, lw, ld, d, behind))
            out.append(block)
    return out


def downtown(x, z):
    """How near a spot is to a far downtown's heart, 0 to 1 (a Gaussian of its radius)."""
    best = 0.0
    for bearing, dist, radius in FAR_DOWNTOWNS:
        a = math.radians(bearing)
        dx, dz = x + math.sin(a) * dist, z + math.cos(a) * dist
        best = max(best, math.exp(-(dx * dx + dz * dz) / (radius * radius)))
    return best


def far_lot(rng, x, z, w, d_, dist, behind):
    """A far lot (painted): towers in the downtowns (FAR_DOWNTOWNS), rising higher at their
    hearts, and a low carpet between them; behind the spawn low, as the mid city's. Same record
    as lot(). (Stage 6 critics: a tall mix read as a wall of spires, an even one as a barcode.)"""
    podium = rng.uniform(12, 30)
    core = downtown(x, z)
    height = rng.uniform(80, 240)
    if rng.random() < CITY['far_tower_base'] + CITY['far_tower_core'] * core:
        height = 300 + rng.uniform(-30, 40) + CITY['far_tower_rise'] * core
    if behind > 0.0:
        height += (rng.uniform(40, 160) - height) * behind
    rec = {'x': x, 'z': z, 'w': w, 'd': d_, 'dist': dist, 'behind': behind, 'podium': podium,
           'height': height, 'far': True, 'glass': rng.random() < 0.4, 'top': 0.0, 'shaft': None, 'crown': 0.0,
           'core': core}
    if height <= podium + 4:
        return rec
    slim = (0.55, 0.8) if height > 300 else (0.65, 0.9)
    rec['shaft'] = (w * rng.uniform(*slim), d_ * rng.uniform(*slim))
    rec['crown'] = rng.uniform(15, 40) if height > 320 else 0.0
    return rec


def lot(rng, x, z, w, d_, dist, behind):
    """One lot: a podium, a shaft and maybe a crown. Heights from the street; the roof is 300
    up. Within 700 of the tower everything stays below the roof; further out some slim towers
    rise over it, more of them the further out, so the skyline shows over the city railing.

    {'x', 'z', 'w', 'd', 'dist', 'behind', 'podium', 'height', 'far', 'glass', 'top',
     'shaft': None or (sw, sd), 'crown'}; top is the base's height over the street (1 on a
    sidewalk slab)."""
    top = 1.0 if dist < 1200 else 0.0  # stand on the sidewalk slab where there is one
    # Towers that rise over the roof are slimmer than the blocks round them.
    podium = rng.uniform(12, 30)
    if behind >= 1.0:
        height = rng.uniform(40, 120)
    else:
        if dist < 700:
            height = rng.uniform(50, 230)  # close by, everything stays below the roof
        elif dist < 1500:
            height = 300 + rng.uniform(30, 150) if rng.random() < 0.16 else rng.uniform(80, 260)
        else:
            height = 300 + rng.uniform(60, 240) if rng.random() < 0.3 else rng.uniform(140, 300)
        if behind > 0.0:
            height += (rng.uniform(40, 120) - height) * behind
    W = WORLD
    if dist >= W['near_radius']:
        height = min(height, W['height_cap_base'] + (dist - W['near_radius']) * W['height_cap_slope'])
        # The outer ring steps down toward the painting.
        edge = (dist - (W['city_reach'] - CITY['outer_taper'])) / CITY['outer_taper']
        if edge > 0.0:
            height *= 1.0 - CITY['outer_drop'] * min(1.0, edge)
    far = dist > 1600
    glass = rng.random() < 0.4
    rec = {'x': x, 'z': z, 'w': w, 'd': d_, 'dist': dist, 'behind': behind, 'podium': podium,
           'height': height, 'far': far, 'glass': glass, 'top': top, 'shaft': None, 'crown': 0.0}
    if height <= podium + 4:
        return rec
    slim = (0.45, 0.65) if height > 300 else (0.6, 0.85)
    rec['shaft'] = (w * rng.uniform(*slim), d_ * rng.uniform(*slim))
    rec['crown'] = rng.uniform(12, 30) if height > 280 else 0.0
    return rec


# ---------------------------------------------------------------------------------------------
# Landmarks: five distinctive towers in the mid ring, ahead and to the left of the spawn (the
# way the player faces on arrival), each a lot of the city's own (Stage 5)
# ---------------------------------------------------------------------------------------------

LANDMARKS = [
    # (kind, bearing in degrees from straight ahead (-Z) toward the city (-X), distance)
    ('stepped', 22.0, 1150.0),  # a tower rising in setbacks to a stepped crown
    ('spire', 38.0, 1350.0),  # the tallest, a slim glass tower with a spire
    ('twin', 55.0, 1050.0),  # two towers side by side on one lot
    ('slant', 70.0, 1400.0),  # a tower with a slanted glass top
    ('needle', 86.0, 1100.0),  # a slim glass needle
]
LANDMARK_RISE = (150.0, 240.0)  # studs over the roof (the street is 300 under it)


def landmarks():
    """The five landmark lots: [{'kind', 'block': (i, j), 'lot': index, 'x', 'z', 'dist',
    'height'}], the nearest mid-ring lot with a shaft to each LANDMARKS spot, never the same
    lot twice. Heights rise LANDMARK_RISE over the roof, the spire the tallest."""
    W = WORLD
    lots = []
    for b in city_blocks():
        if b['near']:
            continue
        for k, lot in enumerate(b['lots']):
            if lot['shaft'] is not None and 1000.0 <= lot['dist'] <= 1500.0:
                lots.append(((b['i'], b['j']), k, lot))
    out, taken = [], set()
    lo, hi = LANDMARK_RISE
    for n, (kind, bearing, dist) in enumerate(LANDMARKS):
        a = math.radians(bearing)
        tx, tz = -math.sin(a) * dist, -math.cos(a) * dist
        best = min((l for l in lots if (l[0], l[1]) not in taken),
                   key=lambda l: math.hypot(l[2]['x'] - tx, l[2]['z'] - tz))
        taken.add((best[0], best[1]))
        rise = hi if kind == 'spire' else lo + (hi - lo) * (n % 3) / 3.0
        out.append({'kind': kind, 'block': best[0], 'lot': best[1], 'x': best[2]['x'], 'z': best[2]['z'],
                    'dist': best[2]['dist'], 'height': -W['street_y'] + rise})
    assert len({(m['block'], m['lot']) for m in out}) == len(LANDMARKS), 'landmarks share a lot'
    for m in out:
        assert 1000.0 <= m['dist'] <= 1550.0 and m['x'] < 0, ('a landmark out of the mid ring', m)
    return out


# ---------------------------------------------------------------------------------------------
# The far islands, painted into the skybox (Stage 6): (kind, azimuth from straight ahead toward
# the ocean in degrees, distance, radius, height). The approved gray-box islands (Stage 1),
# with the one behind the pergola moved from azimuth 3 to 7 so it clears the city's shore, and
# the coast point on the ocean side (Spec section 9). Kinds are backdrop/islands.py's.
# ---------------------------------------------------------------------------------------------

FAR_ISLANDS = [
    ('ridge', 7.0, 4800.0, 520.0, 950.0),  # the big peak straight behind the pergola
    ('ridge', 43.4, 5200.0, 480.0, 850.0),  # the big peak beside the sunset sun
    ('peak', 65.25, 5620.9, 242.4, 316.7),
    ('hill', 60.95, 4121.8, 135.4, 304.3),
    ('hill', 62.97, 4698.1, 230.0, 192.4),
    ('hill', 61.69, 4227.7, 183.5, 219.7),
    ('peak', 106.66, 5256.5, 111.8, 295.9),
    ('peak', 111.33, 4671.6, 197.5, 314.9),
    ('hill', 126.67, 4588.0, 133.4, 184.1),
    ('hill', 120.89, 4824.8, 221.0, 267.3),
    ('hill', 100.0, 3400.0, 420.0, 120.0),  # the coast point: a long low headland with beaches
    # Small low islands along the right horizon (Stage 6 critic: the art's is full of them).
    ('islet', 78.0, 6200.0, 90.0, 70.0),
    ('islet', 86.0, 5900.0, 70.0, 55.0),
    ('hill', 93.0, 6500.0, 150.0, 110.0),
    ('islet', 118.0, 6100.0, 80.0, 60.0),
    ('hill', 133.0, 6300.0, 160.0, 130.0),
    ('islet', 140.0, 5800.0, 75.0, 50.0),
    ('islet', 52.0, 6400.0, 85.0, 65.0),
    # Nearer far islands on the ocean side (Stage 6 critic 2: phones, which draw none of the 3D
    # islands, saw an empty sea there). Each on its own bearing and further out than the 3D ones,
    # so none reads as a painted twin of a near island.
    ('ridge', 28.0, 3900.0, 480.0, 620.0),  # a far range behind the near peak right of the pergola
    ('hill', 50.0, 3900.0, 200.0, 230.0),
    ('peak', 70.0, 3300.0, 220.0, 330.0),
    ('hill', 88.0, 3100.0, 180.0, 170.0),
    ('islet', 57.0, 3450.0, 100.0, 90.0),
]


def far_island_at_sea(az, dist, radius):
    """Whether a far island's whole disc lies at sea: right of the city's bending shore, and
    beyond the 3D world's reach (so no 3D water or land stands in front of it)."""
    W = WORLD
    a = math.radians(az)
    cx, cz = dist * math.sin(a), -dist * math.cos(a)
    for k in range(32):
        t = 2 * math.pi * k / 32
        x, z = cx + radius * math.cos(t), cz + radius * math.sin(t)
        if max(abs(x), abs(z)) < W['water_reach'] + 60:  # the 3D water and land are a square
            return False
        if z < W['shore_z'] and x < city_edge_x(z) + 40:
            return False
        if z >= W['shore_z'] and x < W['shore_x'] + 40:
            return False
    return True
