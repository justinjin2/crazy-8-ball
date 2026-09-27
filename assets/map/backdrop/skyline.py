"""The city's skyline from the near world's edge to city_plan's reach (Stage 5): every lot of
city_plan.city_blocks() beyond the near radius, at the plan's own spots and sizes, as low-poly
towers on a painted sheet (skyline_textures.py, which draws for distance).

Every block is one raised slab top at STREET + 1 (its 80-stud square), paved, with streets
round it (streets(): a road along each side with lane lines, zebra crossings at the corners). Every lot is a podium, a shaft and, when the plan
gives it one, a crown: boxes with no bottom faces, one quad per wall, V by height over the
street (the sheet's facade strips are one tall gradient each, masonry with faint horizontal
floor bands), so parapets and windows are painted, not modelled. The plan's height is each
lot's maximum: lots flattened by the plan's height cap are lowered at random and neighbours in
a block are staggered by at least P['stagger'], so the skyline is not a comb of flat tops;
shafts rising over P['slim_over'] are slimmed. Crowns, setback caps and rooftop boxes are the
tower's own facade a little lighter (the strip's lighter zones). The five city_plan.landmarks()
lots are replaced by their landmark (stepped, spire, twin, slant, needle). The canopy trees and
lawn blocks are gone (the designer read them as black rocks at sunset and the lawns as odd
patches, 2026-09-26).

build() returns [(chunk name, Mesh)]: all of a block goes to the chunk of its centre
(map_common.chunk_cell), so no building is split across MeshParts. Every choice is seeded per
block (SKY_SEED), so the skyline is the same on every run.
"""

import math
import os
import random
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
GROUND = STREET + 1.0  # every block's slab top, and every building's foot
SKY_SEED = 5102  # the skyline's own choices per block (styles, crowns)
STYLES = ('s_glass', 's_white', 's_stone', 's_terracotta')

W = cp.WORLD
P = {
    # A lot's style by its plan height: weights for (glass, white, stone, terracotta). Glass is
    # about 30% of the lots (the review: the rest white, cream stone and terracotta), most of
    # it on the tall slim towers.
    'style_tall': (0.55, 0.25, 0.2, 0.0),  # over the roof (300 over the street)
    'style_mid': (0.32, 0.26, 0.21, 0.21),  # 180 to 300
    'style_low': (0.22, 0.22, 0.26, 0.3),  # under 180
    'glass_podium': ('s_white', 's_stone'),  # a glass tower stands on a light masonry podium
    # Massing (the review): the plan's height is a lot's maximum.
    'capped': (0.62, 1.0),  # a lot the plan's height cap flattened is lowered by this factor
    'stagger': 0.2,  # neighbours in a block differ in height by at least this share
    'slim_over': 250.0,  # a shaft rising over this many studs...
    'slim': (0.6, 0.7),  # ...is slimmed to this much of the plan's footprint...
    'slim_min': 8.0,  # ...but no thinner than this
    'crown_over': 280.0,  # a lot the plan crowns keeps its crown while it stays this tall
    'crown_scale': ((0.55, 0.3), (0.7, 0.7)),  # a crown's footprint of the shaft's, and how often
    'setback': 0.35,  # a tower over 250 steps back this often...
    'setback_at': (0.55, 0.78),  # ...this far up its shaft...
    'setback_scale': (0.72, 0.86),  # ...to this much of the shaft's footprint
    'penthouse': 0.6,  # a flat-topped tower over 120 carries a small rooftop box this often
    'penthouse_size': (0.3, 0.5),  # its footprint, of the shaft's
    'penthouse_height': (5.0, 10.0),
    'antenna': 0.2,  # a crowned tower over the roof carries a mast this often (short: the
    'antenna_height': (12.0, 30.0),  # landmarks' spires are the tall ones)
    'edge_room': 20.0,  # a cell at the land's edge (city_plan.edge_cells) this wide carries a building...
    'edge_height': (25.0, 70.0),  # ...this tall (low: the waterfront)
}
ROAD_Y = STREET  # the streets' surface: over the gray-box land (land_drop under), as the near world's


def facade(mesh, x0, z0, x1, z1, y0, y1, strip, zone, top_strip='s_roof', top_frac=0.5):
    """A box's four walls (one quad each, V by height over the street, every wall centred in
    the strip's `zone` so the building keeps one variant all round) and its lit top; no bottom."""
    outline = mc.outward_rect(x0, z0, x1, z1)
    v0, v1 = (y0 - STREET) / tex.FACADE_TOP, (y1 - STREET) / tex.FACADE_TOP
    for i in range(4):
        a, b = outline[i], outline[(i + 1) % 4]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        mesh.wall(a, b, y0, y1, strip, u0=(zone + 0.5) * tex.ZONE - length / 2, v_range=(v0, v1))
    if top_strip:
        mesh.flat(outline, y1, top_strip, up=True, frac=top_frac)


def centred(mesh, x, z, w, d, y0, y1, strip, zone, **kw):
    facade(mesh, x - w / 2, z - d / 2, x + w / 2, z + d / 2, y0, y1, strip, zone, **kw)


def prism(mesh, poly, y0, y1, strip, zone, top_strip='s_roof', top_frac=0.8):
    """Walls round a convex outline (outward order), V by height, each wall centred in `zone`;
    and a top."""
    taper(mesh, poly, poly, y0, y1, strip, zone)
    if top_strip:
        mesh.flat(poly, y1, top_strip, up=True, frac=top_frac)


def taper(mesh, lo, hi, y0, y1, strip, zone):
    """Walls between two outlines of the same corners (outward order), lo at y0 and hi at y1:
    a straight or tapering prism with no top or bottom; V by height, each wall centred in
    `zone`."""
    n = len(lo)
    va, vb = (mc.trim_v(strip, (y - STREET) / tex.FACADE_TOP) for y in (y0, y1))
    c = (zone + 0.5) * tex.ZONE
    for i in range(n):
        j = (i + 1) % n
        length = math.hypot(lo[j][0] - lo[i][0], lo[j][1] - lo[i][1])
        top_len = math.hypot(hi[j][0] - hi[i][0], hi[j][1] - hi[i][1])
        ua, ub = mc.trim_u(strip, c - length / 2), mc.trim_u(strip, c + length / 2)
        ta, tb = mc.trim_u(strip, c - top_len / 2), mc.trim_u(strip, c + top_len / 2)
        mesh.face([(lo[i][0], y0, lo[i][1]), (lo[j][0], y0, lo[j][1]), (hi[j][0], y1, hi[j][1]), (hi[i][0], y1, hi[i][1])],
                  [(ua, va), (ub, va), (tb, vb), (ta, vb)])


def ring(x, z, r, segs, phase=0.5):
    """Points round a circle in outward order (map_common._circle's winding)."""
    return [(x + r * math.cos(2 * math.pi * (i + phase) / segs), z - r * math.sin(2 * math.pi * (i + phase) / segs))
            for i in range(segs)]


def spike(mesh, x, z, r, y0, y1, segs=4):
    """A mast or spire: a thin pyramid in s_accent's light steel, no bottom."""
    mesh.frustum(x, z, r, 0.0, y0, y1, segs, 's_accent', top=False)


# ---------------------------------------------------------------------------------------------
# Lots: styles and ordinary buildings
# ---------------------------------------------------------------------------------------------

def pick_style(rng, lot, avoid):
    h = lot['height']
    weights = P['style_tall'] if h > 300 else P['style_mid'] if h > 180 else P['style_low']
    for _ in range(3):
        style = rng.choices(STYLES, weights)[0]
        if style not in avoid:
            break
    return style


def building(mesh, rng, lot, style, height):
    """A podium, a shaft and maybe a crown, `height` over the street's slab (the plan's, or
    lower: the stagger); a mast or a rooftop box on some. Every piece stands on GROUND. A shaft
    rising over P['slim_over'] is slimmed. Crowns and rooftop boxes are the tower's own facade,
    lighter (its zone + tex.LIGHT)."""
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    zone = rng.randrange(tex.LIGHT)
    light = zone + tex.LIGHT
    podium_top = GROUND + lot['podium']
    podium_style = rng.choice(P['glass_podium']) if style == 's_glass' else style
    centred(mesh, x, z, w, d, GROUND, podium_top, podium_style, rng.randrange(tex.LIGHT) if style == 's_glass' else zone,
            top_strip='s_roof', top_frac=rng.uniform(0.15, 0.85))
    if lot['shaft'] is None or height <= lot['podium'] + 4:
        return
    sw, sd = lot['shaft']
    if height > P['slim_over']:
        k = rng.uniform(*P['slim'])
        sw, sd = max(sw * k, P['slim_min']), max(sd * k, P['slim_min'])
    top = GROUND + height
    crown = lot['crown'] if height > P['crown_over'] else 0.0
    shaft_top = top - crown
    roof_frac = rng.uniform(0.25, 0.95)
    if height > 250 and rng.random() < P['setback']:
        # A setback part way up: the shaft's upper floors on a smaller footprint.
        cut = podium_top + (shaft_top - podium_top) * rng.uniform(*P['setback_at'])
        centred(mesh, x, z, sw, sd, podium_top, cut, style, zone, top_frac=roof_frac)
        k = rng.uniform(*P['setback_scale'])
        sw, sd = sw * k, sd * k
        centred(mesh, x, z, sw, sd, cut, shaft_top, style, zone, top_frac=roof_frac)
    else:
        centred(mesh, x, z, sw, sd, podium_top, shaft_top, style, zone, top_frac=roof_frac)
    if crown:
        (k_small, share), (k_big, _) = P['crown_scale']
        k = k_small if rng.random() < share else k_big
        centred(mesh, x, z, sw * k, sd * k, shaft_top, top, style, light, top_frac=min(roof_frac + 0.1, 1.0))
        if height > 300 and rng.random() < P['antenna']:
            spike(mesh, x, z, min(sw, sd) * k * 0.1, top, top + rng.uniform(*P['antenna_height']), segs=3)
    elif height > 120 and rng.random() < P['penthouse']:
        k = rng.uniform(*P['penthouse_size'])
        ox, oz = rng.uniform(-0.2, 0.2) * sw, rng.uniform(-0.2, 0.2) * sd
        centred(mesh, x + ox, z + oz, sw * k, sd * k, top, top + rng.uniform(*P['penthouse_height']),
                style, light, top_frac=min(roof_frac + 0.1, 1.0))


def staggered_heights(rng, b, kinds, marks):
    """The height of each building lot in block b: the plan's, lowered at random where the
    plan's height cap flattened it, then, tallest first, each lowered until it is at least
    P['stagger'] under every taller neighbour in the block (landmarks count at their own
    height). Never over the plan's, never so low the shaft disappears."""
    cap = W['height_cap_base'] + (b['dist'] - W['near_radius']) * W['height_cap_slope']
    heights = {}
    for k, lot in enumerate(b['lots']):
        if kinds[k] == 'building':
            h = lot['height']
            heights[k] = h * rng.uniform(*P['capped']) if h >= cap - 0.5 else h
    done = [marks[k]['height'] for k in range(len(kinds)) if kinds[k] == 'landmark']
    for k in sorted(heights, key=lambda n: -heights[n]):
        h = heights[k]
        for other in done:
            if h > (1 - P['stagger']) * other:
                h = (1 - P['stagger']) * other * rng.uniform(0.88, 1.0)
        heights[k] = max(h, b['lots'][k]['podium'] + 10.0)
        done.append(heights[k])
    return heights


# ---------------------------------------------------------------------------------------------
# Landmarks (city_plan.landmarks()): each within its lot, on the lot's own podium; crowns in
# their own facade, lighter; masts and spires in steel
# ---------------------------------------------------------------------------------------------

def chamfer(x, z, w, d, k=0.22):
    """An octagon inside a w x d rectangle, its corners cut by k of the shorter side."""
    return mc.chamfer_rect(x, z, w / 2, d / 2, min(w, d) * k)


def landmark(mesh, lot, mark):
    kind = mark['kind']
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    sw, sd = lot['shaft']
    top = GROUND + mark['height']
    podium_top = GROUND + lot['podium']
    rise = top - podium_top
    L = tex.LIGHT

    def at(f):
        return podium_top + rise * f
    if kind == 'stepped':
        # Cream stone setbacks up to a stepped crown of lighter stone, and a mast.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_stone', 0, top_frac=0.4)
        y = podium_top
        for f, k, zone in ((0.46, 1.0, 0), (0.62, 0.84, 0), (0.74, 0.7, 0), (0.83, 0.57, 0),
                           (0.875, 0.44, L), (0.91, 0.32, L)):
            centred(mesh, x, z, sw * k, sd * k, y, at(f), 's_stone', zone, top_frac=0.85)
            y = at(f)
        spike(mesh, x, z, sw * 0.07, y, top)
    elif kind == 'spire':
        # The tallest: a slim chamfered glass tower, a setback, a lighter glass crown and a
        # long spire.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_white', 1, top_frac=0.5)
        prism(mesh, chamfer(x, z, sw, sd), podium_top, at(0.68), 's_glass', 2)
        prism(mesh, chamfer(x, z, sw * 0.8, sd * 0.8), at(0.68), at(0.77), 's_glass', 2)
        prism(mesh, chamfer(x, z, sw * 0.56, sd * 0.56), at(0.77), at(0.81), 's_glass', 2 + L, top_frac=0.95)
        spike(mesh, x, z, min(sw, sd) * 0.14, at(0.81), top, segs=6)
    elif kind == 'twin':
        # Two matching glass towers side by side along Z (side by side as seen from the roof),
        # lighter glass crowns and masts, a sky bridge between them.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_white', 3, top_frac=0.5)
        tw, td = min(sw, w * 0.46), min(sd * 0.75, d * 0.38)
        gap = min(d - 2 * td - 4.0, 12.0)
        for n, sign in enumerate((-1, 1)):
            cz = z + sign * (gap + td) / 2
            t = top if n == 0 else at(0.96)
            r = t - podium_top
            y1, y2, y3 = (podium_top + r * f for f in (0.74, 0.84, 0.89))
            prism(mesh, chamfer(x, cz, tw, td), podium_top, y1, 's_glass', 0)
            prism(mesh, chamfer(x, cz, tw * 0.76, td * 0.76), y1, y2, 's_glass', 0)
            prism(mesh, chamfer(x, cz, tw * 0.52, td * 0.52), y2, y3, 's_glass', L, top_frac=0.95)
            spike(mesh, x, cz, tw * 0.1, y3, t, segs=4)
        centred(mesh, x, z, tw * 0.34, gap + 2.0, at(0.46), at(0.46) + 12.0, 's_white', 3 + L, top_frac=0.9)
    elif kind == 'slant':
        # A glass tower whose top slopes steeply from -X down toward the roof (+X), so the
        # lighter glass slope faces the rooftop and catches the sun.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_stone', 3, top_frac=0.5)
        low = at(0.5)
        centred(mesh, x, z, sw, sd, podium_top, low, 's_glass', 3, top_frac=0.8)
        ww, dd = sw * 0.86, sd * 0.86
        slant_tower(mesh, x - ww / 2, z - dd / 2, x + ww / 2, z + dd / 2, low, top - ww * 2.6, top, 3)
    elif kind == 'needle':
        # A slim glass needle tapering to a pod of lighter glass, and a spire.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_white', 0, top_frac=0.5)
        r0 = min(sw, sd) / 2
        taper(mesh, ring(x, z, r0, 8), ring(x, z, r0 * 0.55, 8), podium_top, at(0.74), 's_glass', 2)
        taper(mesh, ring(x, z, r0 * 0.55, 8), ring(x, z, r0 * 0.85, 8), at(0.74), at(0.78), 's_glass', 2 + L)
        prism(mesh, ring(x, z, r0 * 0.85, 8), at(0.78), at(0.83), 's_glass', 2 + L, top_frac=0.95)
        spike(mesh, x, z, r0 * 0.22, at(0.83), top, segs=6)
    else:
        raise ValueError(kind)


def slant_tower(mesh, x0, z0, x1, z1, y0, y_low, y_high, zone):
    """A glass box whose top slopes from y_high along its -X side down to y_low along +X:
    walls in s_glass (V by height, the two side walls trapezoids), the slope in the same glass
    a little lighter (V by height too)."""
    def v(y):
        return mc.trim_v('s_glass', (y - STREET) / tex.FACADE_TOP)

    def u(zn, s):
        return mc.trim_u('s_glass', (zn + 0.5) * tex.ZONE + s)
    # Corners in outward order: (x0, z0) -> (x0, z1) -> (x1, z1) -> (x1, z0). Heights by X.
    tops = {x0: y_high, x1: y_low}
    outline = mc.outward_rect(x0, z0, x1, z1)
    for i in range(4):
        (ax, az), (bx, bz) = outline[i], outline[(i + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        ua, ub = u(zone, -length / 2), u(zone, length / 2)
        ya, yb = tops[ax], tops[bx]
        mesh.face([(ax, y0, az), (bx, y0, bz), (bx, yb, bz), (ax, ya, az)],
                  [(ua, v(y0)), (ub, v(y0)), (ub, v(yb)), (ua, v(ya))])
    # The slope: its foot along +X, its top along -X.
    zl = zone + tex.LIGHT
    ua, ub = u(zl, -(z1 - z0) / 2), u(zl, (z1 - z0) / 2)
    mesh.face([(x1, y_low, z1), (x1, y_low, z0), (x0, y_high, z0), (x0, y_high, z1)],
              [(ua, v(y_low)), (ub, v(y_low)), (ub, v(y_high)), (ua, v(y_high))])


# ---------------------------------------------------------------------------------------------
# Blocks
# ---------------------------------------------------------------------------------------------

def block_top(mesh, b):
    half = cp.WORLD['city_block'] / 2
    outline = mc.outward_rect(b['cx'] - half, b['cz'] - half, b['cx'] + half, b['cz'] + half)
    mesh.flat(outline, GROUND, 's_paving', up=True, frac=0.5)


def build():
    marks = {(m['block'], m['lot']): m for m in cp.landmarks()}
    blocks = [b for b in cp.city_blocks() if not b['near']]
    pieces = []
    for b in blocks:
        rng = random.Random(cp.block_seed(SKY_SEED, b['i'], b['j']))
        mesh = mc.Mesh('block')
        block_top(mesh, b)
        block_marks = {k: marks[((b['i'], b['j']), k)] for k in range(len(b['lots'])) if ((b['i'], b['j']), k) in marks}
        kinds = ['landmark' if k in block_marks else 'building' for k in range(len(b['lots']))]
        heights = staggered_heights(rng, b, kinds, block_marks)
        avoid = set()
        for k, lot in enumerate(b['lots']):
            if kinds[k] == 'landmark':
                landmark(mesh, lot, block_marks[k])
            else:
                style = pick_style(rng, lot, avoid)
                avoid = {style}
                building(mesh, rng, lot, style, heights[k])
        pieces.append((mc.cell_name('Skyline', mc.chunk_cell(b['cx'], b['cz'])), mesh))
    edges = cp.edge_cells()
    for i, j, rect in edges:
        pieces.append((mc.cell_name('Skyline', mc.chunk_cell((rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2)),
                       edge_lot(rect, random.Random(cp.block_seed(SKY_SEED + 3, i, j)))))
    cells = {(b['i'], b['j']) for b in blocks} | {(i, j) for i, j, _ in edges}
    return pieces + streets(cells)


def edge_lot(rect, rng):
    """A cell at the land's edge (city_plan.edge_cells): its paved top, and a low building on it
    when there is room (P['edge_height']), so no bare ground is left by the promenade."""
    x0, z0, x1, z1 = rect
    mesh = mc.Mesh('edge')
    mesh.flat(mc.outward_rect(x0, z0, x1, z1), GROUND, 's_paving', up=True, frac=0.5)
    w, d = x1 - x0 - 8, z1 - z0 - 8
    if min(w, d) >= P['edge_room']:
        height = rng.uniform(*P['edge_height'])
        lot = {'x': (x0 + x1) / 2, 'z': (z0 + z1) / 2, 'w': w, 'd': d, 'podium': height, 'height': height,
               'shaft': None, 'crown': 0.0}
        building(mesh, rng, lot, pick_style(rng, lot, set()), height)
    return mesh


# ---------------------------------------------------------------------------------------------
# Streets: the grid between the blocks, so the ground reads as a city from the roof (designer,
# 2026-09-26: a grey baseplate) - a road along every block side and a crossing at every corner,
# on land clear of the promenades, and none where the near world draws its own streets.
# ---------------------------------------------------------------------------------------------

def streets(ours):
    """[(chunk name, Mesh)]: the roads and crossings round the cells `ours` (the blocks and the
    edge cells), in their chunks, cut short at the promenade (city_plan.land_limit)."""
    pitch, size = W['city_pitch'], W['city_block']
    hs = (pitch - size) / 2  # half a street

    def near_owned(i, j):
        # the near world's ground: the cells round the tower that are not our blocks
        return math.hypot((i + 0.5) * pitch, (j + 0.5) * pitch) <= W['near_ground'] and (i, j) not in ours

    roads, crossings = {}, set()
    for i, j in sorted(ours):
        roads[('z', i, j)] = roads[('z', i + 1, j)] = roads[('x', i, j)] = roads[('x', i, j + 1)] = None
        crossings.update({(i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1)})
    meshes = {}

    def add(x0, z0, x1, z1, strip, along_x, owners):
        if any(near_owned(*c) for c in owners):
            return
        x1 = min(x1, cp.land_limit(z0, z1))
        if x1 - x0 < 2.0:
            return
        name = mc.cell_name('Skyline', mc.chunk_cell((x0 + x1) / 2, (z0 + z1) / 2))
        mesh = meshes.setdefault(name, mc.Mesh(name))
        # U along the street (studs), V across it; the face up ((p1 - p0) x (p2 - p0) along +Y).
        if along_x:
            pts = [(x0, ROAD_Y, z1), (x1, ROAD_Y, z1), (x1, ROAD_Y, z0), (x0, ROAD_Y, z0)]
            span, width = x1 - x0, z1 - z0
        else:
            pts = [(x0, ROAD_Y, z0), (x0, ROAD_Y, z1), (x1, ROAD_Y, z1), (x1, ROAD_Y, z0)]
            span, width = z1 - z0, x1 - x0
        u0, u1 = mc.trim_u(strip, 0.0), mc.trim_u(strip, span)
        v0, v1 = mc.trim_v(strip, 0.0), mc.trim_v(strip, 1.0)
        mesh.face(pts, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        assert width > 0

    for axis, i, j in sorted(roads):
        if axis == 'z':  # along Z at x = i * pitch, between cells (i - 1, j) and (i, j)
            x, z0 = i * pitch, j * pitch
            add(x - hs, z0 + hs, x + hs, z0 + pitch - hs, 's_road', False, [(i - 1, j), (i, j)])
        else:  # along X at z = j * pitch, between cells (i, j - 1) and (i, j)
            x0, z = i * pitch, j * pitch
            add(x0 + hs, z - hs, x0 + pitch - hs, z + hs, 's_road', True, [(i, j - 1), (i, j)])
    for i, j in sorted(crossings):
        x, z = i * pitch, j * pitch
        add(x - hs, z - hs, x + hs, z + hs, 's_crosswalk', True, [(i - 1, j - 1), (i, j - 1), (i - 1, j), (i, j)])
    return sorted(meshes.items())
