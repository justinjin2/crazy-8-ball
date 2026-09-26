"""The city's skyline from the near world's edge to city_plan's reach (Stage 5): every lot of
city_plan.city_blocks() beyond the near radius, at the plan's own spots and sizes, as low-poly
towers on a painted sheet (skyline_textures.py, which draws for distance).

Every block is one raised slab top at STREET + 1 (its 80-stud square): paved, or a park (lawn
and a few round tree blobs; its podium roofs are roof gardens). Every lot is a podium, a shaft
and, when the plan gives it one, a crown: boxes with no bottom faces, one quad per wall, V by
height over the street (the sheet's facade strips are one tall gradient each, windows as
vertical bands along U), so parapets and window lines are painted, not modelled. The five
city_plan.landmarks() lots are replaced by their landmark (stepped, spire, twin, slant, needle).

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
SKY_SEED = 5102  # the skyline's own choices per block (styles, crowns, parks, trees)
STYLES = ('s_glass', 's_white', 's_stone', 's_terracotta')

P = {
    'park_share': 0.26,  # this share of the blocks are parks (lawn, roof gardens, trees)
    # A lot's style by its height: weights for (glass, white, stone, terracotta). Glass towers
    # are the tall slim ones; the mid-rises are masonry, as in the art.
    'style_tall': (0.56, 0.3, 0.14, 0.0),  # over the roof (300 over the street)
    'style_mid': (0.3, 0.3, 0.2, 0.2),  # 180 to 300
    'style_low': (0.1, 0.2, 0.3, 0.4),  # under 180
    'glass_podium': ('s_white', 's_stone'),  # a glass tower stands on a light masonry podium
    'crown_accent': 0.45,  # a crowned tower's crown is an accent cap this often, else a setback box
    'crown_setback': 0.7,  # a setback crown's footprint, of the shaft's
    'crown_cap': 0.55,  # an accent cap's footprint, of the shaft's (the gray-box's crown)
    'setback': 0.35,  # a tower over 250 steps back this often...
    'setback_at': (0.55, 0.78),  # ...this far up its shaft...
    'setback_scale': (0.72, 0.86),  # ...to this much of the shaft's footprint
    'penthouse': 0.6,  # a flat-topped tower over 120 carries a small rooftop box this often
    'penthouse_size': (0.3, 0.5),  # its footprint, of the shaft's
    'penthouse_height': (5.0, 10.0),
    'antenna': 0.2,  # a crowned tower over the roof carries a mast this often (short: the
    'antenna_height': (12.0, 30.0),  # landmarks' spires are the tall ones)
    'tree_cap': 5000,  # triangles of tree blobs in the whole skyline
    'tree_radius': (8.0, 12.0),  # a tree blob at the street
    'tree_height': (0.7, 0.95),  # its dome's height over its rim, of its radius
    'tree_lift': 0.3,  # its rim this far over the ground, of its radius (the canopy's widest line)
    # Street trees on a park's rim by the block's distance (the near blocks are the ones seen
    # from above), and on a paved block (a chance, and how many).
    'park_trees': ((1000.0, (6, 8)), (1600.0, (4, 5)), (9999.0, (2, 3))),
    'garden_tree_radius': (4.0, 7.0),  # a tree on a roof garden (it may lean on the shaft)
    'street_trees': (1100.0, 0.5, (1, 3)),  # a paved block nearer than this, this often, this many
}
TREE_SEGS = 6  # a tree blob is a six-sided mound: 6 triangles


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


def accent_box(mesh, x, z, w, d, y0, y1, top_frac=0.9):
    """A crown cap in s_accent: V over the piece (blue glass at its foot, bright metal at its
    top), and a light roof."""
    outline = mc.outward_rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2)
    u = 0.0
    for i in range(4):
        u = mesh.wall(outline[i], outline[(i + 1) % 4], y0, y1, 's_accent', u0=u)
    mesh.flat(outline, y1, 's_roof', up=True, frac=top_frac)


def prism(mesh, poly, y0, y1, strip, zone=None, top_strip='s_roof', top_frac=0.8):
    """Walls round a convex outline (outward order): V by height for a facade strip, each wall
    centred in `zone`; or V over the piece for s_accent. And a top."""
    taper(mesh, poly, poly, y0, y1, strip, zone)
    if top_strip:
        mesh.flat(poly, y1, top_strip, up=True, frac=top_frac)


def taper(mesh, lo, hi, y0, y1, strip, zone=None):
    """Walls between two outlines of the same corners (outward order), lo at y0 and hi at y1:
    a straight or tapering prism with no top or bottom. V as prism()."""
    n = len(lo)
    if strip == 's_accent':
        va, vb = mc.trim_v(strip, 0.0), mc.trim_v(strip, 1.0)
    else:
        va, vb = (mc.trim_v(strip, (y - STREET) / tex.FACADE_TOP) for y in (y0, y1))
    for i in range(n):
        j = (i + 1) % n
        length = math.hypot(lo[j][0] - lo[i][0], lo[j][1] - lo[i][1])
        top_len = math.hypot(hi[j][0] - hi[i][0], hi[j][1] - hi[i][1])
        c = (zone + 0.5) * tex.ZONE if zone is not None else length / 2
        ua, ub = mc.trim_u(strip, c - length / 2), mc.trim_u(strip, c + length / 2)
        ta, tb = mc.trim_u(strip, c - top_len / 2), mc.trim_u(strip, c + top_len / 2)
        mesh.face([(lo[i][0], y0, lo[i][1]), (lo[j][0], y0, lo[j][1]), (hi[j][0], y1, hi[j][1]), (hi[i][0], y1, hi[i][1])],
                  [(ua, va), (ub, va), (tb, vb), (ta, vb)])


def ring(x, z, r, segs, phase=0.5):
    """Points round a circle in outward order (map_common._circle's winding)."""
    return [(x + r * math.cos(2 * math.pi * (i + phase) / segs), z - r * math.sin(2 * math.pi * (i + phase) / segs))
            for i in range(segs)]


def spike(mesh, x, z, r, y0, y1, segs=4):
    """A mast or spire: a thin pyramid in s_accent's bright metal, no bottom."""
    mesh.frustum(x, z, r, 0.0, y0, y1, segs, 's_accent', top=False, v_range=(0.6, 1.0))


def plant(trees, rng, x, z, y, r, h):
    """Note a tree blob (its shape's random numbers drawn now, so thinning keeps the rest)."""
    trees.append((x, z, y, r, h, rng.random(), rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15)))


def tree(mesh, spec):
    """A round low-poly tree blob: a six-sided dome, its rim (the canopy's widest line) a little
    over the ground, V from the dark rim to the lit top. Seen from the roof, far above, the
    gap under the rim does not show."""
    x, z, y, r, h, phase, dx, dz = spec
    y += r * P['tree_lift']
    rim = ring(x, z, r, TREE_SEGS, phase)
    top = (x + dx * r, y + h, z + dz * r)
    va, vb = mc.trim_v('s_tree', 0.0), mc.trim_v('s_tree', 1.0)
    step = 2 * math.pi * r / TREE_SEGS
    for i in range(TREE_SEGS):
        j = (i + 1) % TREE_SEGS
        ua, ub = mc.trim_u('s_tree', i * step), mc.trim_u('s_tree', (i + 1) * step)
        mesh.face([(rim[i][0], y, rim[i][1]), (rim[j][0], y, rim[j][1]), top],
                  [(ua, va), (ub, va), ((ua + ub) / 2, vb)])


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


def building(mesh, trees, rng, lot, style, park):
    """A podium, a shaft and, when the plan gives it one, a crown; a mast or a rooftop box on
    some. Every piece stands on GROUND; the plan's height is over the street's slab."""
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    zone = rng.randrange(tex.ZONES)
    podium_top = GROUND + lot['podium']
    podium_style = rng.choice(P['glass_podium']) if style == 's_glass' else style
    garden = park and lot['shaft'] is not None
    centred(mesh, x, z, w, d, GROUND, podium_top, podium_style, rng.randrange(tex.ZONES) if style == 's_glass' else zone,
            top_strip='s_park' if garden else 's_roof', top_frac=rng.uniform(0.15, 0.85))
    if lot['shaft'] is None:
        return
    sw, sd = lot['shaft']
    top = GROUND + lot['height']
    crown = lot['crown']
    shaft_top = top - crown
    roof_frac = rng.uniform(0.25, 0.95)
    if lot['height'] > 250 and rng.random() < P['setback']:
        # A setback part way up: the shaft's upper floors on a smaller footprint.
        cut = podium_top + (shaft_top - podium_top) * rng.uniform(*P['setback_at'])
        centred(mesh, x, z, sw, sd, podium_top, cut, style, zone, top_frac=roof_frac)
        k = rng.uniform(*P['setback_scale'])
        sw, sd = sw * k, sd * k
        centred(mesh, x, z, sw, sd, cut, shaft_top, style, zone, top_frac=roof_frac)
    else:
        centred(mesh, x, z, sw, sd, podium_top, shaft_top, style, zone, top_frac=roof_frac)
    if crown:
        if rng.random() < P['crown_accent']:
            k = P['crown_cap']
            accent_box(mesh, x, z, sw * k, sd * k, shaft_top, top)
        else:
            k = P['crown_setback']
            centred(mesh, x, z, sw * k, sd * k, shaft_top, top, style, zone, top_frac=roof_frac)
            k *= 0.7
        if lot['height'] > 300 and rng.random() < P['antenna']:
            spike(mesh, x, z, min(sw, sd) * k * 0.12, top, top + rng.uniform(*P['antenna_height']), segs=3)
    elif lot['height'] > 120 and rng.random() < P['penthouse']:
        k = rng.uniform(*P['penthouse_size'])
        ox, oz = rng.uniform(-0.2, 0.2) * sw, rng.uniform(-0.2, 0.2) * sd
        centred(mesh, x + ox, z + oz, sw * k, sd * k, top, top + rng.uniform(*P['penthouse_height']),
                rng.choice(('s_white', 's_stone')), rng.randrange(tex.ZONES), top_frac=0.3)
    if garden:
        garden_trees(trees, rng, x, z, w, d, *lot['shaft'], podium_top)


def garden_trees(trees, rng, x, z, w, d, sw, sd, y):
    """Trees round a shaft on a roof garden: in up to two of the podium's margins wide enough."""
    sides = [0, 1, 2, 3]
    rng.shuffle(sides)
    planted = 0
    for side in sides:
        along_x = side < 2
        margin = ((d - sd) if along_x else (w - sw)) / 2
        r = min(margin * 0.8, rng.uniform(*P['garden_tree_radius']))
        if r < 3.0:
            continue
        sign = 1 if side % 2 else -1
        span = (w if along_x else d) / 2 - r
        t = rng.uniform(-span, span)
        cx = x + (t if along_x else sign * (sw / 2 + margin / 2))
        cz = z + (sign * (sd / 2 + margin / 2) if along_x else t)
        plant(trees, rng, cx, cz, y, r, r * rng.uniform(*P['tree_height']))
        planted += 1
        if planted == 2:
            break


# ---------------------------------------------------------------------------------------------
# Landmarks (city_plan.landmarks()): each within its lot, on the lot's own podium
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

    def at(f):
        return podium_top + rise * f
    if kind == 'stepped':
        # Cream stone setbacks, a stepped bright crown and a mast.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_stone', 0, top_frac=0.4)
        y = podium_top
        for f, k in ((0.46, 1.0), (0.62, 0.84), (0.74, 0.7), (0.83, 0.57)):
            centred(mesh, x, z, sw * k, sd * k, y, at(f), 's_stone', 0, top_frac=0.85)
            y = at(f)
        for f, k in ((0.875, 0.44), (0.91, 0.32)):
            accent_box(mesh, x, z, sw * k, sd * k, y, at(f), top_frac=0.95)
            y = at(f)
        spike(mesh, x, z, sw * 0.07, y, top)
    elif kind == 'spire':
        # The tallest: a slim chamfered glass tower, a setback, a bright crown and a long spire.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_white', 1, top_frac=0.5)
        prism(mesh, chamfer(x, z, sw, sd), podium_top, at(0.68), 's_glass', 2)
        prism(mesh, chamfer(x, z, sw * 0.8, sd * 0.8), at(0.68), at(0.77), 's_glass', 2)
        prism(mesh, chamfer(x, z, sw * 0.56, sd * 0.56), at(0.77), at(0.81), 's_accent', top_frac=0.95)
        spike(mesh, x, z, min(sw, sd) * 0.14, at(0.81), top, segs=6)
    elif kind == 'twin':
        # Two matching glass towers side by side along Z (side by side as seen from the roof),
        # bright crowns and masts, a sky bridge between them.
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
            prism(mesh, chamfer(x, cz, tw * 0.52, td * 0.52), y2, y3, 's_accent', top_frac=0.95)
            spike(mesh, x, cz, tw * 0.1, y3, t, segs=4)
        accent_box(mesh, x, z, tw * 0.34, gap + 2.0, at(0.46), at(0.46) + 12.0)
    elif kind == 'slant':
        # A glass tower whose top slopes steeply from -X down toward the roof (+X), so the
        # bright glass slope faces the rooftop and catches the sun.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_stone', 3, top_frac=0.5)
        low = at(0.5)
        centred(mesh, x, z, sw, sd, podium_top, low, 's_glass', 3, top_frac=0.8)
        ww, dd = sw * 0.86, sd * 0.86
        slant_tower(mesh, x - ww / 2, z - dd / 2, x + ww / 2, z + dd / 2, low, top - ww * 2.6, top)
    elif kind == 'needle':
        # A slim glass needle tapering to a bright pod, and a spire.
        centred(mesh, x, z, w, d, GROUND, podium_top, 's_white', 0, top_frac=0.5)
        r0 = min(sw, sd) / 2
        taper(mesh, ring(x, z, r0, 8), ring(x, z, r0 * 0.55, 8), podium_top, at(0.74), 's_glass', 2)
        taper(mesh, ring(x, z, r0 * 0.55, 8), ring(x, z, r0 * 0.85, 8), at(0.74), at(0.78), 's_accent')
        prism(mesh, ring(x, z, r0 * 0.85, 8), at(0.78), at(0.83), 's_accent', top_frac=0.95)
        spike(mesh, x, z, r0 * 0.22, at(0.83), top, segs=6)
    else:
        raise ValueError(kind)


def slant_tower(mesh, x0, z0, x1, z1, y0, y_low, y_high):
    """A glass box whose top slopes from y_high along its -X side down to y_low along +X:
    walls in s_glass (V by height, the two side walls trapezoids), the slope in s_accent."""
    def v(y):
        return mc.trim_v('s_glass', (y - STREET) / tex.FACADE_TOP)

    def u(s):
        return mc.trim_u('s_glass', (3 + 0.5) * tex.ZONE + s)
    # Corners in outward order: (x0, z0) -> (x0, z1) -> (x1, z1) -> (x1, z0). Heights by X.
    tops = {x0: y_high, x1: y_low}
    outline = mc.outward_rect(x0, z0, x1, z1)
    for i in range(4):
        (ax, az), (bx, bz) = outline[i], outline[(i + 1) % 4]
        length = math.hypot(bx - ax, bz - az)
        ua, ub = u(-length / 2), u(length / 2)
        ya, yb = tops[ax], tops[bx]
        mesh.face([(ax, y0, az), (bx, y0, bz), (bx, yb, bz), (ax, ya, az)],
                  [(ua, v(y0)), (ub, v(y0)), (ub, v(yb)), (ua, v(ya))])
    # The slope: foot (frac 0) along +X, top along -X.
    va, vb = mc.trim_v('s_accent', 0.0), mc.trim_v('s_accent', 1.0)
    ua, ub = mc.trim_u('s_accent', 0.0), mc.trim_u('s_accent', z1 - z0)
    mesh.face([(x1, y_low, z1), (x1, y_low, z0), (x0, y_high, z0), (x0, y_high, z1)],
              [(ua, va), (ub, va), (ub, vb), (ua, vb)])


# ---------------------------------------------------------------------------------------------
# Blocks
# ---------------------------------------------------------------------------------------------

def block_top(mesh, b, park):
    half = cp.WORLD['city_block'] / 2
    outline = mc.outward_rect(b['cx'] - half, b['cz'] - half, b['cx'] + half, b['cz'] + half)
    mesh.flat(outline, GROUND, 's_park' if park else 's_paving', up=True, frac=0.5)


def rim_spots(b, rng, count):
    """Spots for street-level trees along a block's kerb: half over the slab's rim (the 4 studs
    round the lots), half over the street, so they show beside the podiums. (The lanes between
    lots are too narrow for a blob that would not sink into the podiums.)"""
    half = cp.WORLD['city_block'] / 2
    inset = half - 1.0
    spots = []
    for _ in range(count):
        side = rng.randrange(4)
        t = rng.uniform(-half + 6, half - 6)
        if side == 0:
            spots.append((b['cx'] - inset, b['cz'] + t))
        elif side == 1:
            spots.append((b['cx'] + inset, b['cz'] + t))
        elif side == 2:
            spots.append((b['cx'] + t, b['cz'] - inset))
        else:
            spots.append((b['cx'] + t, b['cz'] + inset))
    return spots


def build():
    marks = {(m['block'], m['lot']): m for m in cp.landmarks()}
    blocks = [b for b in cp.city_blocks() if not b['near']]
    pieces = []
    for b in blocks:
        rng = random.Random(cp.block_seed(SKY_SEED, b['i'], b['j']))
        park = rng.random() < P['park_share']
        mesh = mc.Mesh('block')
        trees = []
        block_top(mesh, b, park)
        avoid = set()
        for k, lot in enumerate(b['lots']):
            mark = marks.get(((b['i'], b['j']), k))
            if mark:
                landmark(mesh, lot, mark)
                continue
            style = pick_style(rng, lot, avoid)
            avoid = {style}
            building(mesh, trees, rng, lot, style, park)
        # Street trees: a park's rim is lined with them; a paved block near the tower has one
        # or two now and then.
        if park:
            count = rng.randint(*next(n for reach, n in P['park_trees'] if b['dist'] < reach))
        elif b['dist'] < P['street_trees'][0] and rng.random() < P['street_trees'][1]:
            count = rng.randint(*P['street_trees'][2])
        else:
            count = 0
        if b['behind']:
            count //= 2
        for sx, sz in rim_spots(b, rng, count):
            r = rng.uniform(*P['tree_radius'])
            plant(trees, rng, sx, sz, GROUND, r, r * rng.uniform(*P['tree_height']))
        pieces.append((mc.cell_name('Skyline', mc.chunk_cell(b['cx'], b['cz'])), mesh, trees))
    # Over the tree cap, thin the blobs, the far ones first (a seeded choice: each blob's
    # chance to stay falls with its block's distance).
    thin = random.Random(SKY_SEED)
    specs = [(thin.random() * blocks[n]['dist'], n, t) for n, (_, _, trees) in enumerate(pieces) for t in trees]
    specs = [(n, t) for _, n, t in sorted(specs)[:P['tree_cap'] // TREE_SEGS]]
    for n, spec in specs:
        tree(pieces[n][1], spec)
    return [(name, mesh) for name, mesh, _ in pieces]
