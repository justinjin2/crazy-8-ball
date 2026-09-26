"""The rooftop plan: every position on the hub map, in one place.

Pure Python (no bpy, no Pillow at import), so Blender generators, the plan drawing and the
checks all read the same numbers. Studs, Roblox world axes: X to the right as seen from the
entrance (the city is -X, the ocean +X), Y up (the rooftop floor is Y = 0), Z toward the
entrance (the lounge is -Z). Yaw is degrees about +Y, as CFrame.Angles(0, yaw, 0).

The table grid, the modes and the spawn are gameplay: they are written into
src/shared/Config.luau (Config.Hub.Tables, Config.TableModel.LookByTable,
Config.Multiplayer.Spawn) and tests/map_layout_test.luau checks that the two agree. The queue
pad's size comes from Config too (GAME below); when the pad changes, change GAME, re-run, and
everything re-spaces. Everything else here is the map's own. The brief is
docs/prompts/ROOFTOP_MAP_PROMPT.md; the spec is assets/map/Spec.md.

Run it to write Layout.json and check the plan (exit 1 on any problem):
    python3 assets/map/map_layout.py
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_plan  # noqa: E402  (the world round the rooftop, copied into Layout.json)

# ---------------------------------------------------------------------------------------------
# Gameplay footprint, mirrored from Config (tests/map_layout_test.luau keeps them equal)
# ---------------------------------------------------------------------------------------------
GAME = {
    'table_length': (100 + 2 * 7) * 0.16,  # Table.LengthInches + 2 rails, times StudsPerInch
    'table_width': (50 + 2 * 7) * 0.16,
    'barrier_half': (9.48, 5.48),  # Placement.barrierHalfExtents (rails + Barrier.MarginStuds)
    'fence_half': (13.0, 8.5),  # Multiplayer.Fence.HalfLengthStuds, HalfWidthStuds
    'fence_wall': 1.0,  # Fence.ThicknessStuds, outside the inner face
    # The queue pad (Multiplayer.Queue): a rectangle centred on the table's long side toward
    # the entrance (designer, 2026-09-26), just beyond the walkway.
    'pad_size': {1: (10.0, 5.0), 2: (14.0, 5.0), 3: (18.0, 5.0)},  # PadSizeStuds: along, out
    'pad_gap': 1.0,  # PadGapStuds: from the walkway's edge to the pad
    'fence_margin': 0.5,  # FenceMarginStuds: the match fence stands this far beyond the pad
    'pad_side': -1,  # Queue.PadSide: the sign of physics y the pad sits on (world +Z at yaw 0)
    'player_height': 5.0,
}

# Every table plays one mode (team size a side) and wears that mode's regular-lobby look
# (wood frames; designer, 2026-09-26). Rows front to back, columns city to ocean: the 1v1
# tables at the front, the four 2v2 together in the back city corner (2 x 2), the 3v3 pair in
# the back ocean corner (designer, Checkpoint B).
MODES = [
    [1, 1, 1, 1],
    [1, 1, 1, 1],
    [2, 2, 1, 1],
    [2, 2, 3, 3],
]
LOOK_BY_MODE = {1: 'Green', 2: 'RedWood', 3: 'CharcoalWood'}

# ---------------------------------------------------------------------------------------------
# The plan's choices (studs). Spacing is on the table's scale (the art's layout); anything a
# player sits on or climbs is at player scale; big decor about 1.4x player scale (designer,
# 2026-09-26). A re-run is the tweak.
# ---------------------------------------------------------------------------------------------
P = {
    # Tables: 4 across (X) and 4 deep (Z), long sides to the entrance (yaw 0), pads in front.
    # Aisles are measured between match fences; the row pitch leaves room for the biggest
    # pad anywhere in the grid, so every row is evenly spaced like the art.
    'table_yaw': 0,
    'aisle_x': 10.0,  # between columns (the aisles running toward the lounge)
    'aisle_z': 8.0,  # between rows, at the narrowest (behind the biggest pad)
    # Walkways round the field (between the outer fences and the next thing).
    'front_walk': 10.0,  # field front to the entrance landing
    'back_walk': 8.0,  # field back to the lounge steps
    'side_walk': 10.0,  # field side to the side zones
    'side_zone': 16.0,  # side zone depth, walkway edge to the railing's inner face
    # The edge: a low parapet with a dark-framed glass railing on top (player scale).
    'parapet_height': 1.2,
    'parapet_thickness': 1.2,
    'railing_top': 5.0,  # above the floor: head height of a Roblox character (designer, 2026-09-26)
    'safety_wall_top': 40.0,  # the invisible wall above the railing reaches this high
    # Entrance, at the front centre: the landing (spawn), a grand stair down to a small dead
    # end (the art's central flight is 1.7 table lengths wide).
    'landing_depth': 10.0,
    'steps_width': 26.0,
    'step_count': 10,
    'step_rise': 0.5,
    'step_run': 1.6,
    'lower_landing_depth': 8.0,
    'entrance_column': 2.8,  # square, cream, framing the view from the stair head
    'entrance_column_height': 16.0,
    # Lounge across the back, raised four steps, under a pergola about 75% of the field wide.
    'lounge_step_count': 4,
    'lounge_step_rise': 0.5,
    'lounge_step_run': 2.0,
    'lounge_flight_half_width': 14.0,  # the central flight (the rest of the edge is a low riser)
    'lounge_depth': 30.0,  # platform, top step to the back railing
    'lounge_half_width': 62.0,
    'pergola_half_width': 57.5,  # about 115 wide, as the art's (about 40% of the entrance view)
    'pergola_front_inset': 3.0,  # pergola front columns this far behind the platform edge
    'pergola_depth': 24.0,
    'pergola_height': 22.0,  # clear height under its deep fascia (the fascia's top at 28.5 above the platform)
    'pergola_column': 4.5,  # thick, plain cream columns (the art; Stage 1 and 2 critics)
    'pergola_bays': 3,  # 4 columns per row, 38.3 apart: a pavilion, none behind the piano (Stage 2 critics)
    'palm_inset': 7.0,  # a palm planter's centre this far in from the railing, so its crown stays over the roof
    # Spawn on the landing, facing the tables. The SpawnLocation is the art's entrance mat.
    'spawn_from_landing_front': 4.5,
    'globe_scale': 1.5,  # the GlobeLight template (globe 1.5, cord to 3.75 over its centre) scaled so
    'globe_hang': 5.6,  # ...its centre hangs this far under the fascia's underside
    'crossing_planter_scale': 1.3,  # the aisle-crossing fern planters, chunkier as in the art (Stage 3 critic 2)
    # What a player sits on is sized for a Roblox character, not a real person: the sofas, the
    # umbrella sets' loungers, the piano and its bench and the coffee table, all scaled up
    # (designer, Checkpoint B). The fire pit less, so it still fits inside its U.
    'seating_scale': 1.6,
    'fire_pit_scale': 1.3,
    'mat_size': (16.0, 0.2, 6.0),  # the entrance mat (the SpawnLocation), between the tall lanterns
}

# Prop footprints (studs): width along the prop's own X, depth along its own Z, height.
# Stage 3 builds to these (Spec section 4).
PROP_SIZE = {
    'fern_planter': (3.2, 3.2, 7.0),  # box 3.0 high, ferns above
    'palm_planter': (4.8, 4.8, 26.0),  # box 3.2 high, palm crown about 18 across
    'lantern': (1.5, 1.5, 4.0),
    'lantern_tall': (2.2, 2.2, 6.5),
    'umbrella_set': (12.0, 12.0, 12.0),  # canopy 12 across, two loungers under it
    'side_couch': (12.0, 6.0, 2.6),  # a sofa with its back to the railing and an ottoman
    'lounge_couch': (20.0, 9.0, 2.6),  # U sectional, seat 1.3, round a coffee table or fire pit
    'coffee_table': (2.8, 2.8, 1.3),
    'fire_pit': (4.5, 4.5, 1.4),
    'piano': (4.4, 5.8, 3.0),
    'piano_bench': (2.4, 1.0, 1.4),
    'globe_light': (2.25, 2.25, 2.25),  # the template scaled 1.5 (Stage 3 critic: they did not show)
    'planter_bed': (16.0, 3.0, 6.5),  # a long trough of ferns along a parapet: 3.2 high, ferns above
    'table_glow': (26.0, 18.0, 0.02),  # the table (18.24 x 10.24) and a soft warm pool about 3.5 round it
}

# Where a prop's solid part is smaller than its size: an umbrella set's canopy is overhead, so
# only its loungers and pole block walking (width, depth at scale 1, round the prop's centre).
SOLID_SIZE = {'umbrella_set': (6.0, 7.0)}

# Things that block walking (their footprint is solid). Glow planes and lights do not.
SOLID = {'fern_planter', 'palm_planter', 'planter_bed', 'lantern', 'lantern_tall', 'umbrella_set', 'side_couch',
         'lounge_couch', 'coffee_table', 'fire_pit', 'piano', 'piano_bench',
         'column'}

MIN_WALKWAY = 8.0  # section 4 of the brief: main walkways at least this wide


# ---------------------------------------------------------------------------------------------
# Derived gameplay shapes (the same sums as src/shared/Placement.luau)
# ---------------------------------------------------------------------------------------------

def queue_pad_local(team):
    """The pad: centre (cx, cy) and half extents (hx, hy) in table studs (x along the length,
    y physics), as Placement.queuePad."""
    fy = GAME['fence_half'][1]
    length, depth = GAME['pad_size'][team]
    hx, hy = length / 2, depth / 2
    return 0.0, GAME['pad_side'] * (fy + GAME['pad_gap'] + hy), hx, hy


def match_fence_local(team):
    """The walkway grown to take in the pad: half extents (hx, hy), centre (cx, cy)."""
    fx, fy = GAME['fence_half']
    pcx, pcy, phx, phy = queue_pad_local(team)
    m = GAME['fence_margin']
    x0, x1 = min(-fx, pcx - phx - m), max(fx, pcx + phx + m)
    y0, y1 = min(-fy, pcy - phy - m), max(fy, pcy + phy + m)
    return (x1 - x0) / 2, (y1 - y0) / 2, (x0 + x1) / 2, (y0 + y1) / 2


def local_rect_to_world(t, cx, cy, hx, hy):
    """A table-local box (x along the length, y = physics y) as a world rectangle
    (x0, z0, x1, z1). Physics y maps to world -Z at yaw 0 (Placement.toWorld)."""
    yaw = math.radians(t['yaw'])
    c, s = math.cos(yaw), math.sin(yaw)
    xs, zs = [], []
    for lx in (cx - hx, cx + hx):
        for ly in (cy - hy, cy + hy):
            xs.append(t['X'] + lx * c - ly * s)
            zs.append(t['Z'] - (lx * s + ly * c))
    return (min(xs), min(zs), max(xs), max(zs))


def local_point_to_world(t, lx, ly):
    yaw = math.radians(t['yaw'])
    c, s = math.cos(yaw), math.sin(yaw)
    return t['X'] + lx * c - ly * s, t['Z'] - (lx * s + ly * c)


# ---------------------------------------------------------------------------------------------
# The plan
# ---------------------------------------------------------------------------------------------

def build():
    teams = sorted({m for row in MODES for m in row})
    widest = max(2 * match_fence_local(n)[0] for n in teams)
    deepest = max(2 * match_fence_local(n)[1] for n in teams)
    pitch_x = widest + P['aisle_x']
    pitch_z = deepest + P['aisle_z']

    # Table centres, centred on X = 0 and Z = 0. Row 1 is the front (nearest the spawn); ids
    # run left to right, front to back, like the baseplate grid.
    xs = [(i - 1.5) * pitch_x for i in range(4)]
    zs = [(1.5 - r) * pitch_z for r in range(4)]
    tables = []
    for r, z in enumerate(zs):
        for i, x in enumerate(xs):
            team = MODES[r][i]
            tables.append({'id': r * 4 + i + 1, 'X': x, 'Y': 0.0, 'Z': z, 'yaw': P['table_yaw'],
                           'teamSize': team, 'look': LOOK_BY_MODE[team]})

    fences, pads, barriers = [], [], []
    bx, bz = GAME['barrier_half']
    for t in tables:
        hx, hy, cx, cy = match_fence_local(t['teamSize'])
        fences.append(local_rect_to_world(t, cx, cy, hx, hy))
        pcx, pcy, phx, phy = queue_pad_local(t['teamSize'])
        px, pz = local_point_to_world(t, pcx, pcy)
        pads.append({'X': px, 'Z': pz, 'rect': local_rect_to_world(t, pcx, pcy, phx, phy)})
        barriers.append(local_rect_to_world(t, 0, 0, bx, bz))

    field = (min(f[0] for f in fences), min(f[1] for f in fences),
             max(f[2] for f in fences), max(f[3] for f in fences))
    fx0, fz0, fx1, fz1 = field

    # Terrace edges (the railing's inner face).
    rail_x = fx1 + P['side_walk'] + P['side_zone']
    landing_front = fz1 + P['front_walk']  # the landing starts here...
    front_edge = landing_front + P['landing_depth']  # ...and the stair starts here
    lounge_front = fz0 - P['back_walk']  # the lounge steps start here (going back)
    lounge_steps_depth = P['lounge_step_count'] * P['lounge_step_run']
    platform_front = lounge_front - lounge_steps_depth
    back_edge = platform_front - P['lounge_depth']
    platform_y = P['lounge_step_count'] * P['lounge_step_rise']

    steps_depth = P['step_count'] * P['step_run']
    lower_y = -P['step_count'] * P['step_rise']
    lower_front = front_edge + steps_depth + P['lower_landing_depth']

    spawn = {'X': 0.0, 'Y': P['mat_size'][1] / 2, 'Z': landing_front + P['spawn_from_landing_front'], 'yaw': 0.0,
             'size': list(P['mat_size'])}

    lw, lf = P['lounge_half_width'], P['lounge_flight_half_width']
    pw = P['pergola_half_width']
    zones = {
        'field': field,
        'terrace': (-rail_x, back_edge, rail_x, front_edge),
        'landing': (-rail_x, landing_front, rail_x, front_edge),
        'steps': (-P['steps_width'] / 2, front_edge, P['steps_width'] / 2, front_edge + steps_depth),
        'lower_landing': (-P['steps_width'] / 2, front_edge + steps_depth, P['steps_width'] / 2, lower_front),
        'lounge_steps': (-lf, platform_front, lf, lounge_front),
        'lounge_riser': (-lw, platform_front, lw, platform_front + 0.01),
        'lounge': (-lw, back_edge, lw, platform_front),
        'pergola': (-pw, platform_front - P['pergola_front_inset'] - P['pergola_depth'],
                    pw, platform_front - P['pergola_front_inset']),
        'side_city': (-rail_x, back_edge, -(fx1 + P['side_walk']), landing_front),
        'side_ocean': (fx1 + P['side_walk'], back_edge, rail_x, landing_front),
    }
    heights = {'lounge': platform_y, 'lower_landing': lower_y}

    # Walkways that must stay clear (at least MIN_WALKWAY wide, nothing solid inside except
    # the crossing planters, whose clearance is checked separately).
    walkways = {
        'front': (fx0 - P['side_walk'], fz1, fx1 + P['side_walk'], landing_front),
        'back': (fx0 - P['side_walk'], lounge_front, fx1 + P['side_walk'], fz0),
        'side_city': (fx0 - P['side_walk'], fz0, fx0, fz1),
        'side_ocean': (fx1, fz0, fx1 + P['side_walk'], fz1),
    }
    # Aisles between columns and between rows: the narrowest gap between neighbouring fences.
    aisle_x_spans = []
    for i in range(3):
        a = max(fences[r * 4 + i][2] for r in range(4))
        b = min(fences[r * 4 + i + 1][0] for r in range(4))
        aisle_x_spans.append((a, b))
    aisle_z_spans = []  # front to back
    for r in range(3):
        a = max(fences[(r + 1) * 4 + i][3] for i in range(4))  # the row behind, its front edge
        b = min(fences[r * 4 + i][1] for i in range(4))  # this row, its back edge
        aisle_z_spans.append((a, b))
    for k, (a, b) in enumerate(aisle_x_spans):
        walkways['aisle_col_%d' % (k + 1)] = (a, fz0, b, fz1)
    for k, (a, b) in enumerate(aisle_z_spans):
        walkways['aisle_row_%d' % (k + 1)] = (fx0, a, fx1, b)
    crossings = [((a + b) / 2, (c + d) / 2) for (c, d) in aisle_z_spans for (a, b) in aisle_x_spans]

    props = []

    def prop(kind, x, z, yaw=0.0, y=0.0, **extra):
        w, d, h = PROP_SIZE[kind]
        h = extra.pop('height', h)  # a palm's own height, so a cluster steps up and down
        k = extra.get('scale', 1.0)  # the whole template scaled (MapBuilder.prepareProps)
        w, d, h = w * k, d * k, h * k
        item = {'kind': kind, 'X': round(x, 4), 'Y': round(y, 4), 'Z': round(z, 4), 'yaw': yaw,
                'size': [w, h, d]}
        item.update(extra)
        props.append(item)

    def sized(kind, k):
        """A kind's footprint (width, depth, height) at scale k."""
        return tuple(v * k for v in PROP_SIZE[kind])

    S = P['seating_scale']

    def column(x, z, y, height, size, part_of):
        props.append({'kind': 'column', 'X': round(x, 4), 'Y': y, 'Z': round(z, 4), 'yaw': 0.0,
                      'size': [size, height, size], 'part_of': part_of})

    # Under-table glow: one flat plane under each table.
    for t in tables:
        prop('table_glow', t['X'], t['Z'], t['yaw'], 0.01)

    # Fern planters at the aisle crossings, as in the top-down art: the side aisles' crossings
    # between rows 1 and 2 and between rows 3 and 4. None between rows 2 and 3, and none in the
    # centre aisle, the clear walk from the spawn to the lounge (designer, Checkpoint B).
    for k, (x, z) in enumerate(crossings):
        row, col = divmod(k, 3)
        if row != 1 and col != 1:
            prop('fern_planter', x, z, scale=P['crossing_planter_scale'])

    # Side zones: a regular rhythm along each railing. Big items line up with the table rows,
    # lanterns with the row gaps and the front and back walkways.
    row_z = zs
    gap_z = [(fz1 + landing_front) / 2] + [(a + b) / 2 for (a, b) in aisle_z_spans] + [(fz0 + lounge_front) / 2]
    # Lanterns stand in front of the planted edge, not alone on open floor (Stage 3 critic); on
    # the ocean side they step aside from the palms in the row gaps.
    palm_gaps = [(row_z[0] + row_z[1]) / 2, (row_z[2] + row_z[3]) / 2]
    for z in gap_z:
        prop('lantern', -(rail_x - 5.0), z)
        zo = z + 3.4 if any(abs(z - g) < 1e-6 for g in palm_gaps) else z
        prop('lantern', rail_x - 5.0, zo)
    # City side (02): big fern planters against the railing at every row (the palms stand in
    # clusters at the corners and ends instead, not in an even ring).
    for k, z in enumerate(row_z):
        size = PROP_SIZE['fern_planter'][0]
        prop('fern_planter', -(rail_x - size / 2 - 0.8), z, 90.0)
    # ...and troughs of ferns between them, so the city railing reads as one green line (the
    # top-down art's planted edge).
    bed_d = PROP_SIZE['planter_bed'][1]
    bed_z = [(row_z[k] + row_z[k + 1]) / 2 for k in range(3)] + [row_z[0] + 16.0, row_z[3] - 16.0]
    for z in bed_z:
        prop('planter_bed', -(rail_x - bed_d / 2 - 0.8), z, 90.0)
    # Ocean side (02, designer's choice): umbrella sets with loungers at the first and third
    # rows, sofa groups along the railing at the second and fourth, palms in the gaps between.
    for k, z in enumerate(row_z):
        if k in (0, 2):
            # Loungers face the sea (the set's front, +Z, turned to +X).
            # The loungers' feet 3 in from the railing; the canopy overhangs the walkway.
            prop('umbrella_set', rail_x - SOLID_SIZE['umbrella_set'][1] * S / 2 - 3.0, z, 90.0, scale=S)
        else:
            prop('side_couch', rail_x - sized('side_couch', S)[1] / 2 - 0.4, z, -90.0, scale=S)
    inset = P['palm_inset']
    for (a, b), height in zip(((row_z[0], row_z[1]), (row_z[2], row_z[3])), (26.0, 22.0)):
        prop('palm_planter', rail_x - inset, (a + b) / 2, -90.0, height=height)

    # Entrance: tall lanterns flank the stair head, big palm planters both sides of the stair,
    # cream columns frame the view (the entrance panel), palms in the front corners.
    sx = P['steps_width'] / 2
    prop('lantern_tall', -(sx + 1.8), front_edge - 1.8)
    prop('lantern_tall', sx + 1.8, front_edge - 1.8)
    prop('palm_planter', -(sx + 6.6), front_edge - 3.0, height=30.0)
    prop('palm_planter', sx + 6.6, front_edge - 3.0, height=30.0)
    col = P['entrance_column']
    for side in (-1, 1):
        column(side * (sx + 13.0), front_edge - col / 2 - 0.3, 0.0, P['entrance_column_height'], col, 'entrance')
    for side in (-1, 1):
        # A pair of palms in each front corner, a tall one and a short one.
        prop('palm_planter', side * (rail_x - inset), front_edge - inset, height=26.0)
        prop('palm_planter', side * (rail_x - inset - 6.5), front_edge - inset + 2.0, height=20.0)
        # Troughs of ferns along the front parapet, between the stair and the corners.
        for x in (40.0, 64.0):
            prop('planter_bed', side * x, front_edge - bed_d / 2 - 0.8)

    # Lounge (02, top-down, lounge-back): the raised platform across the back centre, under
    # the pergola. The grand piano is the centrepiece at the back, its bench behind it so the
    # player at the keys faces the tables (designer, 2026-09-26; the snack counter is out for
    # now). A U couch round a coffee table on the city side and a U couch round the fire pit
    # on the ocean side, either side of it. Lanterns flank the central flight; fern planters
    # line the platform edge; palms at the pergola's ends.
    y = platform_y
    pz0, pz1 = zones['pergola'][1], zones['pergola'][3]
    piano_d = sized('piano', S)[1]
    bench_d = sized('piano_bench', S)[1]
    bench_z = pz0 + P['pergola_column'] + 1.0 + bench_d / 2
    piano_z = bench_z + bench_d / 2 + 0.6 * S + piano_d / 2
    prop('piano_bench', 0.0, bench_z, 0.0, y, scale=S)
    prop('piano', 0.0, piano_z, 180.0, y, scale=S)  # the keyboard (the prop's +Z side) faces the bench
    group_z = (pz0 + pz1) / 2 + 1.0
    bay_w = 2 * P['pergola_half_width'] / P['pergola_bays']
    prop('lounge_couch', -bay_w, group_z, 0.0, y, scale=S)  # in the bays either side of the piano's
    prop('coffee_table', -bay_w, group_z + 1.0 * S, 0.0, y, scale=S)
    prop('lounge_couch', bay_w, group_z, 0.0, y, scale=S)
    prop('fire_pit', bay_w, group_z + 1.0 * S, 0.0, y, scale=P['fire_pit_scale'])
    for side in (-1, 1):
        # A fern trough on the back railing behind each U couch: the lounge-back art's planted
        # edge behind the sofa (Stage 3 critic 2).
        prop('planter_bed', side * bay_w, back_edge + PROP_SIZE['planter_bed'][1] / 2 + 0.8, 0.0, y)
        prop('lantern', side * (lf + 1.5), lounge_front - 1.5)
        # Ferns on the platform's edge: flanking the flight, and toward its ends (clear of the
        # views down the bays either side of the piano).
        for x in (lf + 11.0, lf + 39.0):  # beside the columns, clear of them and of the flight
            prop('fern_planter', side * x, platform_front - 2.2, 0.0, y)
        # A pair of palms at each end of the pergola, just off the platform, stepping down.
        prop('palm_planter', side * (lw + 3.0), platform_front - 2.6, 0.0, 0.0, height=32.0)
        prop('palm_planter', side * (lw + 3.0), platform_front - 9.0, 0.0, 0.0, height=24.0)
    # The back corners at floor level: a sofa group (city) and an umbrella set (ocean), as in
    # the top-down art, with palms in the far corners.
    corner_x = (lw + rail_x) / 2
    corner_z = (back_edge + lounge_front) / 2
    # In front of the corner palms, clear of them and of the pergola-end palms.
    prop('side_couch', -corner_x, corner_z + 2.3, 0.0, scale=S)
    prop('umbrella_set', corner_x - 2.0, corner_z + 2.25, 180.0, scale=S)
    for side in (-1, 1):
        # Three palms in each back corner at three heights.
        prop('palm_planter', side * (rail_x - inset), back_edge + inset, height=32.0)
        prop('palm_planter', side * (rail_x - inset - 6.5), back_edge + inset - 1.5, height=26.0)
        prop('palm_planter', side * (rail_x - inset + 1.0), back_edge + inset + 6.5, height=20.0)
    # Globe lights hang from the pergola's front and middle beams, one per bay.
    bay = 2 * pw / P['pergola_bays']
    for k in range(P['pergola_bays']):
        x = -pw + bay * (k + 0.5)
        for z in (pz1 - 1.3, (pz0 + pz1) / 2):
            prop('globe_light', x, z, 0.0, y + P['pergola_height'] - P['globe_hang'])
    # Pergola columns: a front and a back row.
    pcol = P['pergola_column']
    for k in range(P['pergola_bays'] + 1):
        x = -pw + bay * k
        for z in (pz1 - pcol / 2, pz0 + pcol / 2):
            column(x, z, y, P['pergola_height'], pcol, 'pergola')

    return {
        'units': 'studs; Roblox world axes: X right from the entrance (city -X, ocean +X), Y up, Z toward the entrance',
        'tables': tables,
        'spawn': spawn,
        'pads': pads,
        'fences': fences,
        'barriers': barriers,
        'zones': zones,
        'heights': heights,
        'walkways': walkways,
        'crossings': crossings,
        'props': props,
        'pitch': [pitch_x, pitch_z],
        'cameras': cameras(spawn, zones),
        # The world round the rooftop (city_plan.py), for the Lune tests and the generators.
        'world': dict(city_plan.WORLD, land_x=city_plan.land_x(), land_z=city_plan.land_z(),
                      water_fills=[list(r) for r in city_plan.water_fills()]),
    }


def cameras(spawn, zones):
    """Camera poses for the verification captures (section 8 of the brief): position, a point to
    look at and the vertical field of view in degrees; the capture is cropped to the reference
    image's aspect. Tuned against the art in Stage 1, relative to the terrace's edges."""
    front = zones['terrace'][3]
    back = zones['terrace'][1]
    table_row = zones['field'][3] - 15.0  # the front row of tables, about
    bay_x = 2 * P['pergola_half_width'] / P['pergola_bays']  # the fire-pit sofa's bay
    lounge = zones['lounge'][3]
    mid = (front + back) / 2
    return {
        # Just behind the front row, eye height: a table either side, the centre planter, the
        # pergola beyond (panels/entrance.jpg).
        'entrance': {'ref': 'panels/entrance.jpg', 'pos': (0, 7.0, table_row + 21.25), 'look': (0, 4.0, -60.0), 'fov': 70},
        # Over the front walkway, right of centre, looking back and left (02).
        'day-view': {'ref': '02-day-view.jpg', 'pos': (24, 20.0, front - 12.0), 'look': (-8, 0, -45.0), 'fov': 55},
        # The high three-quarter view from beyond the entrance, pitched 18 degrees down so the
        # horizon sits near the top as in the day and sunset panels.
        'high-day': {'ref': 'panels/day.jpg', 'pos': (0, 46.0, front + 48.25), 'look': (0, 0, -8.0), 'fov': 50},
        'high-sunset': {'ref': 'panels/sunset.jpg', 'pos': (0, 46.0, front + 48.25), 'look': (0, 0, -8.0), 'fov': 50},
        'top-down': {'ref': 'panels/top-down.jpg', 'pos': (0, 400.0, mid), 'look': (0, 0, mid - 0.01), 'fov': 30},
        # At the front of the lounge, facing the fire-pit sofa with the sea and the big island
        # beyond it (panels/lounge-back.jpg).
        'lounge-back': {'ref': 'panels/lounge-back.jpg', 'pos': (bay_x, 7.5, lounge - 0.25), 'look': (bay_x, 3.0, back - 40.0), 'fov': 70},
        'city-side': {'ref': 'panels/city-side.jpg', 'pos': (zones['terrace'][0] + 3, 30.0, 0), 'look': (-600, -20, 0), 'fov': 25},
        'ocean-side': {'ref': 'panels/ocean-side.jpg', 'pos': (zones['terrace'][2] - 3, 30.0, -20), 'look': (700, -80, -250), 'fov': 25},
        'phone-eye': {'ref': None, 'pos': (0, 5.6, spawn['Z']), 'look': (0, 4.0, 0), 'fov': 70, 'aspect': 750 / 361},
    }


# ---------------------------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------------------------

def footprint(p):
    w, _, d = p['size']
    if p['kind'] in SOLID_SIZE:
        k = p.get('scale', 1.0)
        w, d = (v * k for v in SOLID_SIZE[p['kind']])
    yaw = math.radians(p['yaw'])
    c, s = abs(math.cos(yaw)), abs(math.sin(yaw))
    hx = (w * c + d * s) / 2
    hz = (w * s + d * c) / 2
    return (p['X'] - hx, p['Z'] - hz, p['X'] + hx, p['Z'] + hz)


def overlaps(a, b, grow=0.0):
    return a[0] - grow < b[2] and b[0] - grow < a[2] and a[1] - grow < b[3] and b[1] - grow < a[3]


def rect_gap(a, b):
    dx = max(b[0] - a[2], a[0] - b[2], 0.0)
    dz = max(b[1] - a[3], a[1] - b[3], 0.0)
    return math.hypot(dx, dz)


def check(plan):
    problems = []
    solids = [(p['kind'], footprint(p)) for p in plan['props'] if p['kind'] in SOLID]
    # Nothing solid inside a match fence (walls included); the pads are inside the fences.
    w = GAME['fence_wall']
    for i, f in enumerate(plan['fences']):
        grown = (f[0] - w, f[1] - w, f[2] + w, f[3] + w)
        for kind, r in solids:
            if overlaps(grown, r):
                problems.append('%s at %s is inside table %d match fence' % (kind, r, i + 1))
    # No two fences (with walls) overlap.
    fences = plan['fences']
    for i in range(len(fences)):
        for j in range(i + 1, len(fences)):
            a, b = fences[i], fences[j]
            if overlaps((a[0] - w, a[1] - w, a[2] + w, a[3] + w), (b[0] - w, b[1] - w, b[2] + w, b[3] + w)):
                problems.append('fences %d and %d overlap' % (i + 1, j + 1))
    # Walkways: wide enough, and nothing solid in them except crossing planters.
    crossing_set = {(round(x, 4), round(z, 4)) for x, z in plan['crossings']}
    for name, r in plan['walkways'].items():
        width = min(r[2] - r[0], r[3] - r[1])
        if width < MIN_WALKWAY - 1e-9:
            problems.append('walkway %s is %.2f wide' % (name, width))
        for p in plan['props']:
            if p['kind'] not in SOLID:
                continue
            if (round(p['X'], 4), round(p['Z'], 4)) in crossing_set:
                continue
            if overlaps(r, footprint(p)):
                problems.append('%s at (%.1f, %.1f) blocks walkway %s' % (p['kind'], p['X'], p['Z'], name))
    # A crossing planter keeps MIN_WALKWAY of floor to anything solid (table barriers and props).
    blockers = list(plan['barriers']) + [r for _, r in solids]
    for p in plan['props']:
        if (round(p['X'], 4), round(p['Z'], 4)) in crossing_set and p['kind'] in SOLID:
            me = footprint(p)
            near = min(rect_gap(me, b) for b in blockers if b != me)
            if near < MIN_WALKWAY - 1e-9:
                problems.append('crossing planter at (%.1f, %.1f) is only %.2f from something solid'
                                % (p['X'], p['Z'], near))
    # Solid props do not overlap one another, except what a U couch holds in its middle.
    held = {('lounge_couch', 'coffee_table'), ('lounge_couch', 'fire_pit')}
    for i in range(len(solids)):
        for j in range(i + 1, len(solids)):
            pair = (solids[i][0], solids[j][0])
            if pair in held or pair[::-1] in held:
                continue
            if overlaps(solids[i][1], solids[j][1], -0.01):
                problems.append('%s %s and %s %s overlap' % (solids[i][0], solids[i][1], solids[j][0], solids[j][1]))
    # Nothing solid on the lounge steps' central flight or the entrance stair.
    for zone in ('lounge_steps', 'steps'):
        for kind, r in solids:
            if overlaps(plan['zones'][zone], r):
                problems.append('%s blocks the %s' % (kind, zone))
    # Everything stands on the terrace.
    tx0, tz0, tx1, tz1 = plan['zones']['terrace']
    for kind, r in solids:
        if r[0] < tx0 or r[2] > tx1 or r[1] < tz0 or r[3] > tz1:
            problems.append('%s at %s hangs over the edge' % (kind, r))
    return problems


def summary(plan):
    z = plan['zones']
    t = z['terrace']
    f = z['field']
    lines = [
        'pitch: %.1f across, %.1f deep' % tuple(plan['pitch']),
        'field (fences): X %.1f..%.1f (%.1f), Z %.1f..%.1f (%.1f)' % (f[0], f[2], f[2] - f[0], f[1], f[3], f[3] - f[1]),
        'terrace: X %.1f..%.1f (%.1f wide), Z %.1f..%.1f (%.1f deep, the stair beyond)'
        % (t[0], t[2], t[2] - t[0], t[1], t[3], t[3] - t[1]),
        'spawn: X %.1f Z %.1f' % (plan['spawn']['X'], plan['spawn']['Z']),
        'aisles: ' + ', '.join('%s %.1f' % (k, min(v[2] - v[0], v[3] - v[1]))
                               for k, v in plan['walkways'].items() if k.startswith('aisle')),
    ]
    counts = {}
    for p in plan['props']:
        key = p['kind'] + ('/' + p['part_of'] if 'part_of' in p else '')
        counts[key] = counts.get(key, 0) + 1
    lines.append('props: ' + ', '.join('%s %d' % kv for kv in sorted(counts.items())))
    return '\n'.join(lines)


def _rounded(v):
    if isinstance(v, float):
        return round(v, 4) + 0.0
    if isinstance(v, (list, tuple)):
        return [_rounded(x) for x in v]
    if isinstance(v, dict):
        return {str(k): _rounded(x) for k, x in v.items()}
    return v


def write(plan, path=os.path.join(HERE, 'Layout.json')):
    with open(path, 'w') as handle:
        json.dump(_rounded(plan), handle, indent=1, sort_keys=True)
        handle.write('\n')


if __name__ == '__main__':
    plan = build()
    print(summary(plan))
    problems = check(plan)
    for line in problems:
        print('PROBLEM:', line)
    write(plan)
    raise SystemExit(1 if problems else 0)
