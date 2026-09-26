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
    'water_overlap': 12.0,  # the water starts this far inside the waterline, so the sand dips under it
    'water_depth': 4.0,  # Terrain water, this deep under the surface
    'land_drop': 0.6,  # the gray-box land's top sits this far under the street, under the near ground
    'near_radius': 450.0,  # city blocks with their centre this close belong to the near world (Stage 4)
    'near_coast': 1000.0,  # the near world's beach runs this far along the coast; the gray-box's beyond
    'max_part': 2000.0,  # Roblox clamps a Part at 2048 studs: big slabs are tiled
    'water_reach': 8000.0,  # the Terrain water and the land out to this far; beyond, the sky's lower
                            # half is painted land toward the city and sea toward the ocean. (Flat
                            # sea slabs past the water showed its edge as a teal stripe; Stage 4.)
    'city_pitch': 110.0,  # a city block and its street
    'city_block': 80.0,  # the block itself (the street is the rest)
    'city_reach': 2300.0,  # blocks out to this far; the horizon beyond is Stage 6's cards
}


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
    """The Terrain water as (x0, z0, x1, z1) rectangles: right of the waterline, and behind
    the tower between the city and the ocean side (the water starts water_overlap inside the
    waterline, under the sand's dip)."""
    W = WORLD
    r, o = W['water_reach'], W['water_overlap']
    return [(W['shore_x'] - o, -r, r, r), (W['city_back_x'], -r, W['shore_x'] - o, W['shore_z'] + o)]


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


def blocks(rng_for):
    """Every city block, in grid order, with its lots. rng_for(i, j) gives the random source
    for block (i, j) (random.Random(block_seed(SEED, i, j)) in the generators). The blocks ahead of the spawn and to its left (the way the player faces)
    are all built, with towers rising over the railing; behind the spawn (+Z, the stair side)
    the city thins out and stays low.

    A block: {'i', 'j', 'cx', 'cz', 'dist', 'behind', 'sidewalk', 'near', 'lots'}; a lot: see
    lot(). 'near' blocks are the near world's (gen_near.py builds them, Stage 4)."""
    W = WORLD
    pitch, size = W['city_pitch'], W['city_block']
    half = size / 2
    n = int(W['city_reach'] // pitch) + 1
    out = []
    for i in range(-n, 2):
        for j in range(-n, n + 1):
            cx, cz = (i + 0.5) * pitch, (j + 0.5) * pitch
            x0, x1, z0, z1 = cx - half, cx + half, cz - half, cz + half
            d = math.hypot(cx, cz)
            if d > W['city_reach']:
                continue
            if not buildable(x0, z0, x1, z1):
                continue
            # The tower's own lot and plaza, and the beach promenade front-right, stay clear.
            if x1 > -160 and x0 < 160 and z1 > -180 and z0 < 170:
                continue
            if x1 > 20 and z1 > -130:
                continue
            rng = rng_for(i, j)
            behind = cz > 250  # behind the spawn: the stair side, seldom looked at
            if behind and rng.random() < 0.55:
                continue
            block = {'i': i, 'j': j, 'cx': cx, 'cz': cz, 'dist': d, 'behind': behind,
                     'sidewalk': d < 1200, 'near': d < W['near_radius'], 'lots': []}
            count = rng.choice((1, 2, 2, 4))
            for k in range(count):
                if count == 1:
                    lx, lz, lw, ld = cx, cz, size - 8, size - 8
                elif count == 2:
                    lx, lz, lw, ld = cx + (k - 0.5) * half, cz, half - 6, size - 8
                else:
                    lx, lz, lw, ld = cx + ((k % 2) - 0.5) * half, cz + ((k // 2) - 0.5) * half, half - 6, half - 6
                block['lots'].append(lot(rng, lx, lz, lw, ld, d, behind))
            out.append(block)
    return out


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
    rec = {'x': x, 'z': z, 'w': w, 'd': d_, 'dist': dist, 'behind': behind, 'podium': podium,
           'height': height, 'far': far, 'glass': glass, 'top': top, 'shaft': None, 'crown': 0.0}
    if height <= podium + 4:
        return rec
    slim = (0.45, 0.65) if height > 300 else (0.6, 0.85)
    rec['shaft'] = (w * rng.uniform(*slim), d_ * rng.uniform(*slim))
    rec['crown'] = rng.uniform(12, 30) if height > 280 else 0.0
    return rec
