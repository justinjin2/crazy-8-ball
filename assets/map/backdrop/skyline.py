"""The city's skyline from the near world's edge to city_plan's reach (Stage 5): every lot of
city_plan.city_blocks() beyond the near radius, at the plan's own spots and sizes, as low-poly
towers on a painted sheet (skyline_textures.py, which draws for distance).

Every block is one raised slab top at STREET + 1 (its 80-stud square): paved, or a park (lawn,
its podium roofs lawn gardens with canopies). Every lot is a podium, a shaft and, when the plan
gives it one, a crown: boxes with no bottom faces, one quad per wall, V by height over the
street (the sheet's facade strips are one tall gradient each, masonry with faint horizontal
floor bands), so parapets and windows are painted, not modelled. The plan's height is each
lot's maximum: lots flattened by the plan's height cap are lowered at random and neighbours in
a block are staggered by at least P['stagger'], so the skyline is not a comb of flat tops;
shafts rising over P['slim_over'] are slimmed. Crowns, setback caps and rooftop boxes are the
tower's own facade a little lighter (the strip's lighter zones). The five city_plan.landmarks()
lots are replaced by their landmark (stepped, spire, twin, slant, needle). About P['tree_lots']
of the other lots between 450 and 1,200 studs are tree lots instead: a lawn and dense canopies.
Canopies, round low-poly mounds 18 to 44 studs across, line the block edges that face the roof
and fill the parks, so the city reads green between its blocks.

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

W = cp.WORLD
P = {
    'park_share': 0.26,  # this share of the blocks are parks (lawn, roof gardens, canopies)
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
    # Tree lots: this share of the (non-landmark) lots in this distance range is a lawn and
    # dense canopies instead of a building.
    'tree_lots': 0.15,
    'tree_lot_reach': (450.0, 1200.0),
    'tree_lot_radius': (9.0, 13.0),  # its canopies, on a grid about 1.5 radii apart
    'tree_lot_height': (0.75, 1.0),  # their height over the rim, of the radius
    'lawn_lift': 1.2,  # a tree lot's lawn over the block's slab (clear of it in the depth buffer)
    # Canopies: clumps of round mounds (a big one and one or two smaller beside it).
    'tree_cap': 18000,  # triangles of canopies in the whole skyline (and every chunk under CHUNK_LIMIT)
    'tree_radius': (15.0, 22.0),  # a kerb clump's big mound (30 to 44 studs across)
    'tree_side': (0.6, 0.85),  # a clump's smaller mounds, of the big one's radius
    'tree_min_radius': 7.0,  # no mound smaller (small ones in the gaps read as litter)
    'tree_height': (0.6, 0.8),  # a mound's height over its rim, of its radius (squat: round)
    'tree_lift': 0.22,  # its rim this far over the ground, of its radius (the canopy's widest line)
    'garden_radius': (7.0, 12.0),  # a canopy on a park's podium roof
    # Clumps along a block's edges by the block's distance: (reach, park, paved). Clumps sit
    # mostly on the two edges facing the roof (the others hide behind the block's podiums).
    'clumps': ((1000.0, 5, 4), (1500.0, 5, 3.5), (1900.0, 2, 1), (9999.0, 1, 0.3)),
    'facing_edges': 0.75,  # this share of the clumps on the two edges facing the roof
    'gardens': ((1000.0, 2), (1500.0, 1), (1900.0, 1), (9999.0, 0)),  # a park podium's canopies per side, at most
}
CHUNK_LIMIT = 14800  # triangles per chunk, under gen_backdrop's CHUNK_CAP (15,000)
TREE_SEGS = 6  # a canopy mound is six-sided: 6 triangles (more canopies in the budget)


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


def plant(trees, rng, x, z, y, r, height=None):
    """Note a canopy mound (its shape's random numbers drawn now, so thinning keeps the rest):
    its height over its rim a `height` range of its radius, its green one of the tree strip's
    zones at a random spot inside it."""
    h = r * rng.uniform(*(height or P['tree_height']))
    rim = 2 * math.pi * r
    u0 = rng.randrange(tex.TREE_TONES) * tex.TREE_ZONE + rng.uniform(0.0, max(tex.TREE_ZONE - rim, 0.0))
    trees.append((x, z, y, r, h, rng.random(), rng.uniform(-0.12, 0.12), rng.uniform(-0.12, 0.12), u0))


def clump(trees, rng, x, z, y, r, along):
    """A clump of canopies: a big mound at (x, z), radius r, and one or two smaller ones beside
    it along the unit vector `along` (the block edge), a little in or out."""
    plant(trees, rng, x, z, y, r)
    across = (-along[1], along[0])
    for side in rng.sample((-1, 1), rng.randint(1, 2)):
        k = max(rng.uniform(*P['tree_side']), P['tree_min_radius'] / r)
        off = r * rng.uniform(0.8, 1.1) * side
        j = r * rng.uniform(-0.3, 0.3)
        plant(trees, rng, x + along[0] * off + across[0] * j, z + along[1] * off + across[1] * j, y, r * k)


def tree(mesh, spec):
    """A round low-poly canopy: a six-sided mound, its rim (the canopy's widest line) a little
    over the ground, V from the dark rim to the lit top."""
    x, z, y, r, h, phase, dx, dz, u0 = spec
    y += r * P['tree_lift']
    rim = ring(x, z, r, TREE_SEGS, phase)
    top = (x + dx * r, y + h, z + dz * r)
    va, vb = mc.trim_v('s_tree', 0.0), mc.trim_v('s_tree', 1.0)
    step = 2 * math.pi * r / TREE_SEGS
    for i in range(TREE_SEGS):
        j = (i + 1) % TREE_SEGS
        ua, ub = mc.trim_u('s_tree', u0 + i * step), mc.trim_u('s_tree', u0 + (i + 1) * step)
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


def building(mesh, trees, rng, lot, style, park, dist, height):
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
            top_strip='s_park' if park else 's_roof', top_frac=rng.uniform(0.15, 0.85))
    if lot['shaft'] is None or height <= lot['podium'] + 4:
        return
    sw, sd = lot['shaft']
    if height > P['slim_over']:
        k = rng.uniform(*P['slim'])
        sw, sd = max(sw * k, P['slim_min']), max(sd * k, P['slim_min'])
    base = (sw, sd)
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
    if park and by_distance(P['gardens'], dist):
        garden(trees, rng, lot, base, podium_top, by_distance(P['gardens'], dist))


def by_distance(table, dist):
    """The row of a (reach, ...) table for a distance: the first whose reach is beyond it."""
    row = next(r for r in table if dist < r[0])
    return row[1] if len(row) == 2 else row[1:]


def garden(trees, rng, lot, shaft, y, per_side):
    """A park lot's podium roof filled with canopies round its shaft (its footprint `shaft`): up
    to `per_side` along each side of the ring, big enough to lean on the shaft and hang over the
    podium's edge; none on a ring too narrow for a canopy of P['tree_min_radius']."""
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    sw, sd = shaft
    lo, hi = P['garden_radius']
    for side in range(4):
        along_x = side < 2  # the ring's sides at -Z and +Z run along X
        margin = ((d - sd) if along_x else (w - sw)) / 2
        r = min(hi, margin * 0.9 + 3.0)
        if r < max(lo, P['tree_min_radius']):
            continue
        length = w if along_x else d
        count = max(1, min(per_side, int(length / (1.7 * r))))
        sign = 1 if side % 2 else -1
        for n in range(count):
            t = (n + 0.5) / count * length - length / 2 + rng.uniform(-0.15, 0.15) * r
            off = (sd if along_x else sw) / 2 + margin / 2
            cx, cz = (x + t, z + sign * off) if along_x else (x + sign * off, z + t)
            plant(trees, rng, cx, cz, y, max(r * rng.uniform(0.85, 1.0), P['tree_min_radius']))


def tree_lot(mesh, trees, rng, lot):
    """A lot of trees instead of a building: a lawn over its footprint and dense big canopies
    on a jittered grid, with one more in the middle."""
    x, z, w, d = lot['x'], lot['z'], lot['w'], lot['d']
    outline = mc.outward_rect(x - w / 2, z - d / 2, x + w / 2, z + d / 2)
    mesh.flat(outline, GROUND + P['lawn_lift'], 's_park', up=True, frac=rng.uniform(0.2, 0.6))
    y = GROUND + P['lawn_lift']
    r = rng.uniform(*P['tree_lot_radius'])
    nx, nz = max(1, round(w / (1.5 * r))), max(1, round(d / (1.5 * r)))
    for i in range(nx):
        for j in range(nz):
            cx = x - w / 2 + (i + 0.5) * w / nx + rng.uniform(-0.2, 0.2) * r
            cz = z - d / 2 + (j + 0.5) * d / nz + rng.uniform(-0.2, 0.2) * r
            plant(trees, rng, cx, cz, y, r * rng.uniform(0.85, 1.15), P['tree_lot_height'])
    if nx * nz > 1:
        plant(trees, rng, x, z, y, r * 1.1, P['tree_lot_height'])


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

def block_top(mesh, b, park):
    half = cp.WORLD['city_block'] / 2
    outline = mc.outward_rect(b['cx'] - half, b['cz'] - half, b['cx'] + half, b['cz'] + half)
    mesh.flat(outline, GROUND, 's_park' if park else 's_paving', up=True, frac=0.5)


def edge_clumps(trees, rng, b, count):
    """`count` clumps of canopies along a block's kerbs (centred on its edge: half over the
    street, half over the slab's rim and the podiums' feet), mostly on the two edges facing the
    roof, spread along each edge."""
    half = cp.WORLD['city_block'] / 2
    inset = half
    # Edges as (unit normal out of the block); the two facing the roof (the origin) first.
    edges = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    edges.sort(key=lambda e: e[0] * b['cx'] + e[1] * b['cz'])
    slots = {}
    for _ in range(count):
        e = edges[rng.randrange(2)] if rng.random() < P['facing_edges'] else edges[2 + rng.randrange(2)]
        slots[e] = slots.get(e, 0) + 1
    for (nx, nz), n in slots.items():
        along = (abs(nz), abs(nx))
        for k in range(n):
            t = ((k + rng.uniform(0.25, 0.75)) / n - 0.5) * (2 * half - 16)
            cx = b['cx'] + nx * inset + along[0] * t
            cz = b['cz'] + nz * inset + along[1] * t
            clump(trees, rng, cx, cz, GROUND, rng.uniform(*P['tree_radius']), along)


def build():
    marks = {(m['block'], m['lot']): m for m in cp.landmarks()}
    blocks = [b for b in cp.city_blocks() if not b['near']]
    pieces = []
    lo, hi = P['tree_lot_reach']
    for b in blocks:
        rng = random.Random(cp.block_seed(SKY_SEED, b['i'], b['j']))
        park = rng.random() < P['park_share']
        mesh = mc.Mesh('block')
        trees = []
        block_top(mesh, b, park)
        block_marks = {k: marks[((b['i'], b['j']), k)] for k in range(len(b['lots'])) if ((b['i'], b['j']), k) in marks}
        kinds = []
        for k in range(len(b['lots'])):
            if k in block_marks:
                kinds.append('landmark')
            elif lo <= b['dist'] < hi and rng.random() < P['tree_lots']:
                kinds.append('trees')
            else:
                kinds.append('building')
        heights = staggered_heights(rng, b, kinds, block_marks)
        avoid = set()
        for k, lot in enumerate(b['lots']):
            if kinds[k] == 'landmark':
                landmark(mesh, lot, block_marks[k])
            elif kinds[k] == 'trees':
                tree_lot(mesh, trees, rng, lot)
            else:
                style = pick_style(rng, lot, avoid)
                avoid = {style}
                building(mesh, trees, rng, lot, style, park, b['dist'], heights[k])
        # Canopy clumps along the kerbs: more on parks and near the tower, fewer behind it.
        per_park, per_paved = by_distance(P['clumps'], b['dist'])
        count = per_park if park else per_paved
        count = int(count) + (1 if rng.random() < count - int(count) else 0)
        if b['behind']:
            count //= 2
        edge_clumps(trees, rng, b, count)
        pieces.append((mc.cell_name('Skyline', mc.chunk_cell(b['cx'], b['cz'])), mesh, trees))
    # Over the canopy cap (or a chunk's limit), thin the mounds, the far ones first (a seeded
    # choice: each mound's chance to stay falls with its block's distance).
    thin = random.Random(SKY_SEED)
    specs = sorted((thin.random() * blocks[n]['dist'], n, t) for n, (_, _, trees) in enumerate(pieces) for t in trees)
    room = {}
    for name, mesh, _ in pieces:
        room[name] = room.get(name, CHUNK_LIMIT) - mesh.triangles()
    left = P['tree_cap'] // TREE_SEGS
    for _, n, spec in specs:
        name = pieces[n][0]
        if left and room[name] >= TREE_SEGS:
            tree(pieces[n][1], spec)
            room[name] -= TREE_SEGS
            left -= 1
    return [(name, mesh) for name, mesh, _ in pieces]
