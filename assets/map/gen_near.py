"""The near world round the tower (Stage 4; Spec section 7), built in headless Blender:

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_near.py            # the FBX
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_near.py -- render  # and renders

Writes fbx/Near.fbx (with the anchor cubes; MapBuilder.prepareNear places it), Near.blend and
Near.json (triangles per mesh). Everything below the roof within about 450 studs, plus the
coast out to near_coast:
    Tower          the tower's walls from its top floors (TowerTop, Rooftop.fbx) down to the
                   lobby: one facade band a floor (the arch sheet)
    Ground         the lobby round the tower's foot and its canopy, the plaza, the streets
                   (roads, crossings, zebra stripes) and the near blocks' raised sidewalks
    Buildings_*    the near city's lots (city_plan): a lobby floor, facades a floor at a
                   time, roofs with a parapet and a little clutter; split in two chunks
    Coast          along the coast: the promenade on the sea wall, the wall, the beach sloping
                   into the water
    Shallows       the painted turquoise band over the water along the beach (alpha)
    Palms          light palms along the beach (alpha frond cards, the plants atlas)
    Trees          street and plaza trees: leafy clumps seen from above (the plants atlas)
    Boat           one sailboat at the origin, the template MapBuilder clones for the drifting
                   boats (MapAmbience)
The geometry is in Roblox studs and axes (map_common.Mesh); nothing collides (nobody can get
down there). The city's lots and the coast come from city_plan, so the gray-box's rows for
the same places (group 'near') are what these meshes replace.
"""

import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import city_plan as cp  # noqa: E402
import map_common as mc  # noqa: E402
import map_layout as ml  # noqa: E402

SEED = 4027
W = cp.WORLD
STREET = W['street_y']
SEA = W['sea_y']

P = {
    'kerb': 1.0,  # sidewalks and the near blocks stand this far over the street (city_plan's lot 'top')
    'lobby': 19.0,  # the tower's double-height lobby, under its first facade floor
    'canopy_out': 6.0,  # the lobby canopy's depth...
    'canopy_y': 12.0,  # ...and its height over the street
    'crossing': 5.0,  # zebra crossings at each end of a road segment, this long
    'ground_radius': 520.0,  # plaza and streets for grid cells with their centre this close
    'wall_drop': 1.4,  # the sea wall: the beach's top sits this far under the promenade
    'under': 12.0,  # the sand runs on under the water this far past the waterline...
    'under_drop': 1.2,  # ...down this far
    'shallows_in': 3.0,  # the painted shallows start this far up the sand (the foam line)...
    'shallows_out': 70.0,  # ...and fade out this far past the waterline
    'shallows_lift': 0.5,  # over the water's surface (at 0.15 it flickered with the water from the roof)
    'plaza_margin': 15.0,  # grid cells this close to the tower are its paved plaza; the rest a park
    'palm_every': 24.0,  # palms along the beach, this far apart...
    'palm_offset': 9.0,  # ...this far out from the sea wall...
    'palm_reach': 650.0,  # ...up to this far along the coast
    'palm_height': (22.0, 30.0),
    'tree_every': 16.0,  # street trees round each near block's edge
    'tree_inset': 2.0,
    'tree_size': (10.0, 7.0),  # the two leafy clumps of a tree, across
    'tree_height': 9.0,
}

CAPS = {  # triangles per mesh (the brief: the near world 50,000 in all)
    'Tower': 1500, 'Ground': 6000, 'Buildings_Left': 12000, 'Buildings_Front': 8000, 'Coast': 1500,
    'Shallows': 300, 'Palms': 3500, 'Trees': 4000, 'Boat': 400,
}
CAP_TOTAL = 50000

LAYOUT = ml.build()


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def facing(mesh, pts, uvs, want):
    """A face turned to face `want` (a direction): Mesh.face's normal is (p1 - p0) x (p2 - p0)."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    if n[0] * want[0] + n[1] * want[1] + n[2] * want[2] < 0:
        pts, uvs = list(reversed(pts)), list(reversed(uvs))
    mesh.face(pts, uvs)


UP = (0.0, 1.0, 0.0)


def flat_band(mesh, a, b, width, y, strip, v_lo=0.0, v_hi=1.0, u0=0.0):
    """A horizontal band from a to b (x, z) at height y, `width` across: U along it (studs from
    u0), V across it from v_lo on the left to v_hi on the right (seen walking from a to b)."""
    (ax, az), (bx, bz) = a, b
    length = math.hypot(bx - ax, bz - az)
    dx, dz = (bx - ax) / length, (bz - az) / length
    px, pz = -dz * width / 2, dx * width / 2  # toward the left
    pts = [(ax + px, y, az + pz), (ax - px, y, az - pz), (bx - px, y, bz - pz), (bx + px, y, bz + pz)]
    va, vb = mc.trim_v(strip, v_hi), mc.trim_v(strip, v_lo)
    ua, ub = mc.trim_u(strip, u0), mc.trim_u(strip, u0 + length)
    facing(mesh, pts, [(ua, va), (ua, vb), (ub, vb), (ub, va)], UP)


def flat_rect(mesh, x0, z0, x1, z1, y, strip, frac=0.5):
    if x1 - x0 > 1e-6 and z1 - z0 > 1e-6:
        mesh.flat(mc.outward_rect(x0, z0, x1, z1), y, strip, up=True, frac=frac)


def floors(mesh, a, b, y0, y1, strip, lobby=None, u0=0.0):
    """A wall from a to b (x, z) between y0 and y1, one facade band a floor (FACADE_FLOOR_STUDS),
    the last cut short; optionally a lobby floor (strip, height) at the foot."""
    fh = mc.FACADE_FLOOR_STUDS
    y = y0
    if lobby:
        top = min(y1, y0 + lobby[1])
        mesh.wall(a, b, y, top, lobby[0], u0=u0)
        y = top
    while y < y1 - 1e-6:
        top = min(y1, y + fh)
        mesh.wall(a, b, y, top, strip, u0=u0, v_range=(0.0, (top - y) / fh))
        y = top


def image_material(name, image_file, alpha=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(os.path.join(HERE, 'textures', image_file), check_existing=True)
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.8
    if alpha:
        links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'BLENDED'
    return mat


# ---------------------------------------------------------------------------------------------
# The tower
# ---------------------------------------------------------------------------------------------

def tower_outline():
    """TowerTop's outline (gen_rooftop.py): the walls in outward order, the stair bay cut into
    the front."""
    zones, P_ = LAYOUT['zones'], ml.P
    tx0, tz0, tx1, tz1 = zones['terrace']
    pt, fo = P_['parapet_thickness'], 0.12
    sx = P_['steps_width'] / 2
    lower_end = zones['lower_landing'][3]
    X0, X1, Zb, Zf = tx0 - pt - fo, tx1 + pt + fo, tz0 - pt - fo, tz1 + pt + fo
    bx, bz = sx + pt + fo, lower_end + pt + fo
    return [(X0, Zb), (X0, Zf), (-bx, Zf), (-bx, bz), (bx, bz), (bx, Zf), (X1, Zf), (X1, Zb)]


def tower(tower_mesh, ground):
    """The tower's walls from the street to TowerTop's foot (Y -41): a lobby (the near sheet),
    then a facade band a floor (the arch sheet), U restarting on every wall as TowerTop's does
    so the windows run on up. A canopy round the lobby."""
    outline = tower_outline()
    top = -41.0  # gen_rooftop: y_top - tower_floors * floor_height
    lobby_top = STREET + P['lobby']
    n = len(outline)
    for i in range(n):
        a, b = outline[i], outline[(i + 1) % n]
        ground.wall(a, b, STREET, lobby_top, 'n_lobby', v_range=(0.0, 1.0))
        floors(tower_mesh, a, b, lobby_top, top, 'facade')
    # The canopy: a thin slab round the lobby.
    x0 = min(p[0] for p in outline) - P['canopy_out']
    x1 = max(p[0] for p in outline) + P['canopy_out']
    z0 = min(p[1] for p in outline) - P['canopy_out']
    z1 = max(p[1] for p in outline) + P['canopy_out']
    y = STREET + P['canopy_y']
    ground.box(x0, y, z0, x1, y + 0.8, z1, 'n_cap')


# ---------------------------------------------------------------------------------------------
# The ground: plaza, streets, near blocks' sidewalks
# ---------------------------------------------------------------------------------------------

def classify():
    """Every grid cell (i, j) in reach: 'near' (a near city block), 'city' (a gray-box block,
    left as it is), 'plaza' (open, round the tower's foot) or 'park' (open, further out: lawns
    and trees). Returns (cells, near_blocks)."""
    pitch = W['city_pitch']
    blocks = cp.city_blocks()
    by_cell = {(b['i'], b['j']): b for b in blocks}
    cells = {}
    n = int(P['ground_radius'] // pitch) + 2
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            cx, cz = (i + 0.5) * pitch, (j + 0.5) * pitch
            if math.hypot(cx, cz) > P['ground_radius']:
                continue
            b = by_cell.get((i, j))
            if b is not None:
                cells[(i, j)] = 'near' if b['near'] else 'city'
            elif land_rect(*cell_rect(i, j)) is not None:
                cells[(i, j)] = 'plaza' if near_tower(cell_rect(i, j)) else 'park'
    return cells, [b for b in blocks if b['near']]


def near_tower(rect):
    """Whether a rectangle comes within plaza_margin of the tower."""
    outline = tower_outline()
    m = P['plaza_margin']
    x0, x1 = min(p[0] for p in outline) - m, max(p[0] for p in outline) + m
    z0, z1 = min(p[1] for p in outline) - m, max(p[1] for p in outline) + m
    return rect[0] < x1 and rect[2] > x0 and rect[1] < z1 and rect[3] > z0


def cell_rect(i, j):
    pitch, half = W['city_pitch'], W['city_block'] / 2
    cx, cz = (i + 0.5) * pitch, (j + 0.5) * pitch
    return cx - half, cz - half, cx + half, cz + half


def land_rect(x0, z0, x1, z1):
    """A rectangle clipped to the land inside the promenade (None if nothing is left)."""
    x1 = min(x1, cp.land_x() - W['promenade'])
    z0 = max(z0, cp.land_z() + W['promenade'])
    if x1 - x0 < 0.5 or z1 - z0 < 0.5:
        return None
    return x0, z0, x1, z1


def ground(mesh, cells):
    pitch, street = W['city_pitch'], W['city_pitch'] - W['city_block']
    hs = street / 2
    kerb_y = STREET + P['kerb']
    road_y = STREET
    # Cells: the near blocks' raised sidewalks (a slab with kerb sides), the plaza's paving.
    for (i, j), kind in cells.items():
        r = cell_rect(i, j)
        if kind == 'near':
            x0, z0, x1, z1 = r
            mesh.prism(mc.outward_rect(x0, z0, x1, z1), road_y - 0.2, kerb_y, 'n_cap', top=False)
            flat_rect(mesh, x0, z0, x1, z1, kerb_y, 'n_sidewalk', 0.5)
        elif kind in ('plaza', 'park'):
            lr = land_rect(*r)
            if lr:
                flat_rect(mesh, *lr, road_y, 'n_plaza' if kind == 'plaza' else 'n_grass', 0.5)

    def kind(i, j):
        return cells.get((i, j))

    # Streets between cells: a road (with zebra crossings at its ends) where a near block
    # borders it, plaza paving between two plaza cells, nothing where only gray-box or no
    # cells border it.
    n = max(max(abs(i), abs(j)) for i, j in cells) + 2
    for k in range(-n, n + 1):
        for m in range(-n, n + 1):
            for along_z in (True, False):
                if along_z:  # a street along Z at x = k * pitch, between crossings m and m + 1
                    sides = (kind(k - 1, m), kind(k, m))
                    x0, x1 = k * pitch - hs, k * pitch + hs
                    z0, z1 = m * pitch + hs, (m + 1) * pitch - hs
                else:  # along X at z = m * pitch, between crossings k and k + 1
                    sides = (kind(k, m - 1), kind(k, m))
                    x0, x1 = k * pitch + hs, (k + 1) * pitch - hs
                    z0, z1 = m * pitch - hs, m * pitch + hs
                if not any(s in ('near', 'plaza', 'park') for s in sides):
                    continue
                lr = land_rect(x0, z0, x1, z1)
                if lr is None:
                    continue
                x0, z0, x1, z1 = lr
                if all(s in ('plaza', 'park', None) for s in sides):
                    flat_rect(mesh, x0, z0, x1, z1, road_y, 'n_plaza', 0.5)
                    continue
                c = P['crossing']
                if along_z:
                    xm = (x0 + x1) / 2
                    flat_band(mesh, (xm, z0 + c), (xm, z1 - c), x1 - x0, road_y, 'n_road')
                    for za, zb in ((z0, z0 + c), (z1 - c, z1)):
                        flat_band(mesh, (x0, (za + zb) / 2), (x1, (za + zb) / 2), zb - za, road_y, 'n_crosswalk')
                else:
                    zm = (z0 + z1) / 2
                    flat_band(mesh, (x0 + c, zm), (x1 - c, zm), z1 - z0, road_y, 'n_road')
                    for xa, xb in ((x0, x0 + c), (x1 - c, x1)):
                        flat_band(mesh, ((xa + xb) / 2, z0), ((xa + xb) / 2, z1), xb - xa, road_y, 'n_crosswalk')
    # Crossings (the squares where streets meet): asphalt, or paving when only plaza is round.
    for k in range(-n, n + 1):
        for m in range(-n, n + 1):
            round_ = [kind(k - 1, m - 1), kind(k, m - 1), kind(k - 1, m), kind(k, m)]
            if not any(s in ('near', 'plaza', 'park') for s in round_):
                continue
            lr = land_rect(k * pitch - hs, m * pitch - hs, k * pitch + hs, m * pitch + hs)
            if lr is None:
                continue
            plaza = all(s in ('plaza', 'park', None) for s in round_)
            flat_rect(mesh, *lr, road_y, 'n_plaza' if plaza else 'n_road', 0.5 if plaza else 0.3)


# ---------------------------------------------------------------------------------------------
# The near city's buildings
# ---------------------------------------------------------------------------------------------

def building(mesh, lot, rng):
    """A podium (a lobby floor, then facade floors), a shaft and maybe a crown, each with a
    roof inside a low parapet and a little clutter on top."""
    base = STREET + lot['top']
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    if lot['glass']:
        podium_style, shaft_style = rng.choice(('n_stone', 'n_white')), 'n_glass'
    else:
        podium_style = shaft_style = rng.choice(('n_stone', 'n_terracotta', 'n_white', 'n_terracotta'))
    podium_top = base + lot['podium']
    block(mesh, x, z, w, d, base, podium_top, podium_style, rng, lobby=('n_lobby', min(10.0, lot['podium'])),
          clutter=lot['shaft'] is None)
    if lot['shaft'] is None:
        return
    sw, sd = lot['shaft']
    crown = lot['crown']
    shaft_top = STREET + lot['top'] + lot['height'] - crown
    block(mesh, x, z, sw, sd, podium_top, shaft_top, shaft_style, rng, clutter=not crown)
    if crown:
        block(mesh, x, z, sw * 0.55, sd * 0.55, shaft_top, shaft_top + crown, 'n_glass' if not lot['glass'] else 'n_stone',
              rng, clutter=True)


def block(mesh, x, z, w, d, y0, y1, style, rng, lobby=None, clutter=False):
    x0, x1, z0, z1 = x - w / 2, x + w / 2, z - d / 2, z + d / 2
    outline = mc.outward_rect(x0, z0, x1, z1)
    for i in range(4):
        floors(mesh, outline[i], outline[(i + 1) % 4], y0, y1, style, lobby=lobby)
    # Roof inside a parapet: the roof 0.8 under the wall tops, the parapet's inner faces and cap.
    p, t = 0.8, 0.6
    roof_y = y1 - p
    flat_rect(mesh, x0 + t, z0 + t, x1 - t, z1 - t, roof_y, 'n_roof', 0.5)
    inner = mc.outward_rect(x0 + t, z0 + t, x1 - t, z1 - t)
    for i in range(4):
        a, b = inner[(i + 1) % 4], inner[i]  # reversed: the inner faces look in
        mesh.wall(a, b, roof_y, y1, 'n_cap')
    for rx0, rz0, rx1, rz1 in ((x0, z0, x1, z0 + t), (x0, z1 - t, x1, z1), (x0, z0 + t, x0 + t, z1 - t),
                               (x1 - t, z0 + t, x1, z1 - t)):
        flat_rect(mesh, rx0, rz0, rx1, rz1, y1, 'n_cap', 0.9)
    if not clutter:
        return
    for _ in range(rng.randint(1, 3)):
        bw, bd, bh = rng.uniform(3, 7), rng.uniform(3, 6), rng.uniform(2, 4)
        bx = rng.uniform(x0 + t + bw / 2 + 1, x1 - t - bw / 2 - 1) if x1 - x0 > bw + 4 else x
        bz = rng.uniform(z0 + t + bd / 2 + 1, z1 - t - bd / 2 - 1) if z1 - z0 > bd + 4 else z
        mesh.box(bx - bw / 2, roof_y, bz - bd / 2, bx + bw / 2, roof_y + bh, bz + bd / 2, 'n_cap', top_strip='n_roof')


# ---------------------------------------------------------------------------------------------
# The coast: promenade, sea wall, beach, shallows
# ---------------------------------------------------------------------------------------------

def coast_path():
    """The land's edge along the coast, walked with the sea on the left: along the back
    beach from the city's side to the corner, then along the ocean side toward the front."""
    lx, lz = cp.land_x(), cp.land_z()
    return [(W['city_back_x'], lz), (lx, lz), (lx, W['near_coast'])]


def offset_path(path, d):
    """The path moved d toward the sea (the left of travel), with mitred corners."""
    out = []
    n = len(path)
    normals = []
    for i in range(n - 1):
        (ax, az), (bx, bz) = path[i], path[i + 1]
        length = math.hypot(bx - ax, bz - az)
        dx, dz = (bx - ax) / length, (bz - az) / length
        normals.append((dz, -dx))  # the sea side: -Z along the back, +X along the ocean side
    for i in range(n):
        if i == 0:
            nx, nz = normals[0]
            scale = 1.0
        elif i == n - 1:
            nx, nz = normals[-1]
            scale = 1.0
        else:
            (ax, az), (bx, bz) = normals[i - 1], normals[i]
            nx, nz = ax + bx, az + bz
            scale = 1.0 / (1.0 + ax * bx + az * bz)
        out.append((path[i][0] + nx * d * scale, path[i][1] + nz * d * scale))
    return out


def sweep(mesh, path, profile, strip, want, u_scale=1.0):
    """Quads between consecutive profile points (offset, y, v) along the path; U along the path
    in studs, V from each point's v; each face turned toward `want` (a function of the
    segment's sea-side normal)."""
    rings = [(offset_path(path, off), y, v) for off, y, v in profile]
    for k in range(len(rings) - 1):
        (pa, ya, va), (pb, yb, vb) = rings[k], rings[k + 1]
        u = 0.0
        for i in range(len(path) - 1):
            (ax, az), (bx, bz) = path[i], path[i + 1]
            seg = math.hypot(bx - ax, bz - az)
            dx, dz = (bx - ax) / seg, (bz - az) / seg
            normal = (dz, 0.0, -dx)
            pts = [(pa[i][0], ya, pa[i][1]), (pa[i + 1][0], ya, pa[i + 1][1]),
                   (pb[i + 1][0], yb, pb[i + 1][1]), (pb[i][0], yb, pb[i][1])]
            u0, u1 = mc.trim_u(strip, u * u_scale), mc.trim_u(strip, (u + seg) * u_scale)
            uvs = [(u0, mc.trim_v(strip, va)), (u1, mc.trim_v(strip, va)), (u1, mc.trim_v(strip, vb)),
                   (u0, mc.trim_v(strip, vb))]
            facing(mesh, pts, uvs, want(normal))
            u += seg


def coast(coast_mesh, shallows):
    path = coast_path()
    beach, prom = W['beach'], W['promenade']
    wall_bottom = STREET - P['wall_drop']
    up = lambda n: UP  # noqa: E731
    seaward = lambda n: n  # noqa: E731
    sweep(coast_mesh, path, [(-prom, STREET, 0.0), (0.0, STREET, 1.0)], 'n_promenade', up)
    sweep(coast_mesh, path, [(0.0, STREET, 1.0), (0.0, wall_bottom, 0.0)], 'n_seawall', seaward)
    sweep(coast_mesh, path, [(0.0, wall_bottom, 1.0), (beach, SEA, 0.08),
                             (beach + P['under'], SEA - P['under_drop'], 0.0)], 'n_sand', up)
    lift = SEA + P['shallows_lift']
    sweep(shallows, path, [(beach - P['shallows_in'], lift, 1.0), (beach + P['shallows_out'], lift, 0.0)],
          'n_shallows', up)
    # The ends: the sea wall's face closed where the coast stops (behind, on the city side).
    (ax, az) = path[0]
    coast_mesh.wall((ax, az), (ax, az - beach), wall_bottom, STREET, 'n_seawall')


# ---------------------------------------------------------------------------------------------
# Palms and trees (alpha cards from the plants atlas)
# ---------------------------------------------------------------------------------------------

FROND = mc.PLANTS['frond']
CLUMP = mc.PLANTS['clump']


def palm(mesh, cards, x, z, y, height, rng):
    """A trunk (six sides) and eight frond cards, springing up then drooping, seen from above."""
    lean = (rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5))
    top = (x + lean[0], y + height, z + lean[1])
    mesh.frustum(x, z, 0.9, 0.55, y, y + height, 6, 'n_wood', top=False)
    u0, v0, u1, v1 = FROND
    ua, ub = u0 + 0.006, u1 - 0.006
    vc, vh = (v0 + v1) / 2, (v1 - v0) * 0.48
    length, width = 9.5, 3.4
    for k in range(8):
        a = math.radians(k * 45 + rng.uniform(-12, 12))
        dx, dz = math.cos(a), math.sin(a)
        px, pz = -dz * width / 2, dx * width / 2
        # base, a knee a little up and out, the tip down
        pts = [(top[0], top[1], top[2]),
               (top[0] + dx * length * 0.45, top[1] + 0.8, top[2] + dz * length * 0.45),
               (top[0] + dx * length, top[1] - 3.0, top[2] + dz * length)]
        us = [ua, ua + (ub - ua) * 0.45, ub]
        for s in range(2):
            (x0_, y0_, z0_), (x1_, y1_, z1_) = pts[s], pts[s + 1]
            quad = [(x0_ + px, y0_, z0_ + pz), (x0_ - px, y0_, z0_ - pz), (x1_ - px, y1_, z1_ - pz),
                    (x1_ + px, y1_, z1_ + pz)]
            uvs = [(us[s], vc + vh), (us[s], vc - vh), (us[s + 1], vc - vh), (us[s + 1], vc + vh)]
            facing(cards, quad, uvs, UP)


def tree(cards, trunks, x, z, y, rng):
    """A thin trunk and two leafy clumps (flat cards seen from above), the smaller one lower and
    off to a side."""
    h = P['tree_height'] * rng.uniform(0.85, 1.15)
    trunks.frustum(x, z, 0.35, 0.25, y, y + h - 1.0, 4, 'n_wood', top=False)
    u0, v0, u1, v1 = CLUMP
    m = 0.01
    for size, lift, off in ((P['tree_size'][0], 0.0, 0.0), (P['tree_size'][1], -1.6, 2.2)):
        a = rng.uniform(0, 2 * math.pi)
        cx, cz = x + math.cos(a) * off, z + math.sin(a) * off
        r = size / 2 * rng.uniform(0.9, 1.1)
        yy = y + h + lift
        quad = [(cx - r, yy, cz - r), (cx - r, yy, cz + r), (cx + r, yy, cz + r), (cx + r, yy, cz - r)]
        uvs = [(u0 + m, v0 + m), (u0 + m, v1 - m), (u1 - m, v1 - m), (u1 - m, v0 + m)]
        facing(cards, quad, uvs, UP)


# ---------------------------------------------------------------------------------------------
# The sailboat (a template at the origin: the bow toward +Z, the waterline at Y 0)
# ---------------------------------------------------------------------------------------------

BOAT = {'length': 40.0, 'beam': 12.0, 'freeboard': 3.2, 'draft': 1.2, 'mast': 46.0}


def boat(mesh):
    L, B, fb, dr = BOAT['length'], BOAT['beam'], BOAT['freeboard'], BOAT['draft']
    # The hull: a deck outline pointed at the bow, walls down to a narrower keel line.
    deck = [(-B / 2, -L / 2), (-B / 2 * 0.95, L * 0.15), (0.0, L / 2), (B / 2 * 0.95, L * 0.15), (B / 2, -L / 2)]
    keel = [(x * 0.55, z * 0.9) for x, z in deck]
    n = len(deck)
    u = 0.0
    for i in range(n):
        a, b = deck[i], deck[(i + 1) % n]
        ka, kb = keel[i], keel[(i + 1) % n]
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        pts = [(ka[0], -dr, ka[1]), (kb[0], -dr, kb[1]), (b[0], fb, b[1]), (a[0], fb, a[1])]
        uvs = [(mc.trim_u('n_hull', u), mc.trim_v('n_hull', 0.0)), (mc.trim_u('n_hull', u + seg), mc.trim_v('n_hull', 0.0)),
               (mc.trim_u('n_hull', u + seg), mc.trim_v('n_hull', 1.0)), (mc.trim_u('n_hull', u), mc.trim_v('n_hull', 1.0))]
        mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        facing(mesh, pts, uvs, (mx, 0.0, mz))  # out from the middle
        u += seg
    mesh.flat(deck, fb, 'n_wood', up=True)
    # The cabin, the mast, the mainsail (behind the mast) and the jib (before it).
    mesh.box(-B * 0.28, fb, -L * 0.3, B * 0.28, fb + 3.0, L * 0.05, 'n_hull', top_strip='n_sail')
    mast_z = L * 0.1
    mesh.cylinder(0.0, mast_z, 0.45, fb, fb + BOAT['mast'], 5, 'n_wood', top=False)
    sail = [('main', [(0.0, fb + 4.0, mast_z - 0.5), (0.0, fb + 4.0, -L * 0.42), (0.0, fb + BOAT['mast'] - 2.0, mast_z - 0.5)]),
            ('jib', [(0.0, fb + 2.0, mast_z + 0.8), (0.0, fb + BOAT['mast'] * 0.8, mast_z + 0.8), (0.0, fb + 2.0, L * 0.47)])]
    v0, v1 = mc.trim_v('n_sail', 0.0), mc.trim_v('n_sail', 1.0)
    for _, tri in sail:
        mesh.face(tri, [(0.0, v0), (0.5, v0), (0.25, v1)], double=True)


# ---------------------------------------------------------------------------------------------
# Build, check, export
# ---------------------------------------------------------------------------------------------

def build():
    rng = random.Random(SEED)
    meshes = {name: mc.Mesh(name) for name in CAPS}
    tower(meshes['Tower'], meshes['Ground'])
    cells, near_blocks = classify()
    ground(meshes['Ground'], cells)
    tx = tower_outline()
    tx0, tx1 = min(p[0] for p in tx) - 8, max(p[0] for p in tx) + 8
    tz0, tz1 = min(p[1] for p in tx) - 8, max(p[1] for p in tx) + 8
    for b in near_blocks:
        chunk = 'Buildings_Front' if b['cz'] > 220 else 'Buildings_Left'
        brng = random.Random(cp.block_seed(SEED, b['i'], b['j']))
        for lot in b['lots']:
            building(meshes[chunk], lot, brng)
        # Street trees round the block's edge.
        x0, z0, x1, z1 = cell_rect(b['i'], b['j'])
        inset, every = P['tree_inset'], P['tree_every']
        for (ax, az), (bx, bz) in zip(mc.outward_rect(x0 + inset, z0 + inset, x1 - inset, z1 - inset),
                                      mc.outward_rect(x0 + inset, z0 + inset, x1 - inset, z1 - inset)[1:] +
                                      [(x0 + inset, z0 + inset)]):
            seg = math.hypot(bx - ax, bz - az)
            for k in range(int(seg // every)):
                t = (k + 0.5) * every / seg
                tree(meshes['Trees'], meshes['Ground'], ax + (bx - ax) * t, az + (bz - az) * t, STREET + P['kerb'], brng)
    # Trees in the open cells, clear of the tower and the promenade: a loose grid of four in
    # the plaza's, a denser, jittered grid of nine on the park's lawns.
    for (i, j), kind in sorted(cells.items()):
        if kind not in ('plaza', 'park'):
            continue
        lr = land_rect(*cell_rect(i, j))
        if lr is None:
            continue
        grid = (0.25, 0.75) if kind == 'plaza' else (0.18, 0.5, 0.82)
        for fx in grid:
            for fz in grid:
                jx, jz = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06)) if kind == 'park' else (0.0, 0.0)
                x = lr[0] + (lr[2] - lr[0]) * (fx + jx)
                z = lr[1] + (lr[3] - lr[1]) * (fz + jz)
                if tx0 < x < tx1 and tz0 < z < tz1:
                    continue
                if (lr[2] - lr[0]) < 30 or (lr[3] - lr[1]) < 30:
                    continue
                tree(meshes['Trees'], meshes['Ground'], x, z, STREET, rng)
    coast(meshes['Coast'], meshes['Shallows'])
    # Palms along the beach, behind the sea wall's foot.
    path = coast_path()
    line = offset_path(path, P['palm_offset'])
    walked = 0.0
    for i in range(len(line) - 1):
        (ax, az), (bx, bz) = line[i], line[i + 1]
        seg = math.hypot(bx - ax, bz - az)
        t = (P['palm_every'] - walked % P['palm_every']) % P['palm_every'] + P['palm_every'] / 2
        while t < seg and walked + t < P['palm_reach'] + 400:
            x, z = ax + (bx - ax) * t / seg, az + (bz - az) * t / seg
            if walked + t <= P['palm_reach'] or z < 0:
                palm(meshes['Ground'], meshes['Palms'], x, z, STREET - P['wall_drop'] - 0.2,
                     rng.uniform(*P['palm_height']), rng)
            t += P['palm_every']
        walked += seg
    boat(meshes['Boat'])
    return meshes


def main():
    render_views = '--' in sys.argv and 'render' in sys.argv[sys.argv.index('--') + 1:]
    scene = mc.clear_scene()
    collection = bpy.data.collections.new('Near')
    scene.collection.children.link(collection)
    # The near sheet is opaque except its shallows strip: only the Shallows mesh blends (in
    # Studio too, where the opaque meshes use AlphaMode Overlay).
    near = image_material('Near', 'near_color.png')
    shallows = image_material('NearShallows', 'near_color.png', alpha=True)
    arch = image_material('Arch', 'arch_color.png')
    plants = image_material('Plants', 'plants.png', alpha=True)
    materials = {'Tower': arch, 'Palms': plants, 'Trees': plants, 'Shallows': shallows}
    meshes = build()
    objects, report, counts, total = [], [], {}, 0
    for name, m in meshes.items():
        tris = m.triangles()
        counts[name] = tris
        total += tris
        report.append('%-16s %6d triangles (cap %d)' % (name, tris, CAPS[name]))
        assert tris <= CAPS[name], (name, tris, 'over its cap')
        (lo, hi) = m.bounds()
        span = max(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        assert span < 2040, (name, span, 'over the MeshPart size limit')
        objects.append(mc.to_object(m, collection, materials.get(name, near)))
    assert total <= CAP_TOTAL, ('the near world over its cap', total)
    for a in mc.anchor_meshes():
        objects.append(mc.to_object(a, collection, arch))
    for name, want in (('AnchorO', (0, 0, 0)), ('AnchorX', (10, 0, 0)), ('AnchorZ', (0, 0, 10))):
        obj = bpy.data.objects[name]
        centre = sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
        got = (centre.x, centre.z, -centre.y)
        assert max(abs(a - b) for a, b in zip(got, want)) < 1e-6, (name, got)
    fbx = os.path.join(HERE, 'fbx', 'Near.fbx')
    mc.export_fbx(fbx, objects)
    worst = mc.roundtrip_check(fbx, objects)
    report.append('total            %6d triangles (cap %d); FBX round trip within %.2g studs' % (total, CAP_TOTAL, worst))
    with open(os.path.join(HERE, 'Near.json'), 'w') as handle:
        json.dump({'triangles': counts, 'total_triangles': total, 'boat': BOAT}, handle, indent=1, sort_keys=True)
        handle.write('\n')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'Near.blend'), check_existing=False, compress=True)
    backup = os.path.join(HERE, 'Near.blend1')
    if os.path.exists(backup):
        os.remove(backup)
    print('\n'.join(report))
    if render_views:
        render(collection)


def render(collection):
    """Blender checkpoint renders: the high-day pose and looking down from each railing, over
    a flat sea (render only)."""
    scene = bpy.context.scene
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'CYCLES'
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.view_settings.view_transform = 'Standard'
    sea = bpy.data.meshes.new('SeaPreview')
    r = 3000
    sea.from_pydata([mc.rb((-r, SEA, -r)), mc.rb((-r, SEA, r)), mc.rb((r, SEA, r)), mc.rb((r, SEA, -r))], [], [(0, 1, 2, 3)])
    sea_obj = bpy.data.objects.new('SeaPreview', sea)
    collection.objects.link(sea_obj)
    mat = bpy.data.materials.new('SeaMat')
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = tuple(mc.srgb_to_linear(c) for c in mc.rgb('#2F92D8')) + (1.0,)
    sea.materials.append(mat)
    light = bpy.data.lights.new('Sun', 'SUN')
    light.energy = 4.0
    sun = bpy.data.objects.new('Sun', light)
    collection.objects.link(sun)
    sun.rotation_euler = Vector(mc.rb((0.465, 0.806, 0.367))).normalized().to_track_quat('Z', 'Y').to_euler()
    world = scene.world or bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = tuple(mc.srgb_to_linear(c) for c in mc.rgb(mc.hexc('sky_horizon_day'))) + (1.0,)
    bg.inputs['Strength'].default_value = 0.8
    out_dir = os.path.join(HERE, 'checkpoints', 'near')
    os.makedirs(out_dir, exist_ok=True)
    cam_high = LAYOUT['cameras']['high-day']
    views = {
        'high-day': (cam_high['pos'], cam_high['look'], cam_high['fov']),
        'ocean-down': ((92.0, 6.0, 20.0), (300.0, -302.0, -60.0), 70.0),
        'city-down': ((-92.0, 6.0, 0.0), (-330.0, -300.0, 60.0), 70.0),
        'back-down': ((0.0, 6.0, -100.0), (60.0, -302.0, -330.0), 70.0),
    }
    for view, (pos, look, fov) in views.items():
        cam_data = bpy.data.cameras.new('Cam_' + view)
        cam_data.sensor_fit = 'VERTICAL'
        cam_data.angle_y = math.radians(fov)
        cam_data.clip_end = 8000
        cam = bpy.data.objects.new('Cam_' + view, cam_data)
        collection.objects.link(cam)
        p, lk = Vector(mc.rb(pos)), Vector(mc.rb(look))
        cam.location = p
        cam.rotation_euler = (lk - p).to_track_quat('-Z', 'Y').to_euler()
        scene.camera = cam
        scene.render.filepath = os.path.join(out_dir, 'near-%s.png' % view)
        bpy.ops.render.render(write_still=True)
        print('rendered', scene.render.filepath)


main()
