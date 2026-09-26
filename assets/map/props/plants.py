"""Plant props (Stage 3): FernPlanter, PalmPlanter, Palm, PlanterBed.

Each build returns {'Opaque': Mesh on the props trim sheet, 'Foliage': Mesh on the plants
atlas}; see gen_props.py for the frame. The planters are light cream boxes with a slight top
lip and soil a little below the rim (03's square planter). The leaves are two-sided alpha
cards: a frond is a strip bent in segments along its length (an arch that droops toward the
tip) and folded down a little either side of its stem, so it keeps some width seen edge on.
The soil in each box is hidden under the atlas's leafy clump, raised into a low pyramid (a
mound). Nothing here is random at run time: each kind seeds its own random.Random.
"""

import math
import random

import map_common as mc

# The plants atlas layout (props/plants_textures.py draws it; these repeat its constants).
MARGIN = 0.006  # a frond's base and tip sit this far in from its region's left and right edges
FROND_BAND = 0.96  # the palm frond spans this much of its region's height
FERN_BAND = 0.44  # the fern frond spans this much of its region's height

P = {
    # Planter boxes (03: square, a slight lip, soil a little below the rim)
    'lip_height': 0.28,  # the top lip band
    'lip_out': 0.07,  # the lip stands this far proud of the body
    'rim': 0.24,  # the wall's thickness seen at the top
    'soil_drop': 0.22,  # the soil this far below the rim
    'chamfer': 0.08,  # the box's vertical edges
    'fold': 24.0,  # a frond card's halves droop this many degrees either side of its stem
    # Palm
    'trunk_base_r': 0.55,  # 1.1 thick at the foot
    'trunk_top_r': 0.37,  # 0.74 under the crown
    'trunk_sides': 8,
    'trunk_foot': -0.45,  # below the Palm's origin (the box top), into the soil
    'trunk_lean': 1.3,  # the crown this far off the base's axis, along +X (a gentle curve)
    'trunk_lean_z': 0.35,  # and this far along +Z, so the curve is not in a flat plane
    'coconut_r': 0.3,  # three coconuts (p_wood_dark) under the crown
    'palm_fold': 30.0,  # a palm frond's leaflets hang this far either side of its rachis
    'palm_wide': 1.1,  # palm fronds this much wider than the atlas's proportions (lush crowns)
    'fern_wide': 0.8,  # fern fronds this much narrower than the atlas's (the art's slender fronds)
}


# ---------------------------------------------------------------------------------------------
# Small vector helpers (Roblox axes)
# ---------------------------------------------------------------------------------------------

def _add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k)


def _norm(a):
    n = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


# ---------------------------------------------------------------------------------------------
# Planter box
# ---------------------------------------------------------------------------------------------

def planter(mesh, w, d, h):
    """A cream box w x d, h high, centred on the origin: a body, a lip a little proud of it
    round the top, a rim, inner walls and the soil (p_soil). Returns the soil height."""
    lip, out, rim, c = P['lip_height'], P['lip_out'], P['rim'], P['chamfer']
    y_lip = h - lip
    frac = y_lip / h
    # The body, inset under the lip (its top is hidden); AO at its foot from the strip.
    body = mc.chamfer_rect(0.0, 0.0, w / 2 - out, d / 2 - out, c)
    u = 0.0
    for i in range(len(body)):
        u = mesh.wall(body[i], body[(i + 1) % len(body)], 0.0, y_lip, 'p_planter', u, (0.0, frac))
    outer = mc.chamfer_rect(0.0, 0.0, w / 2, d / 2, c + out * 0.4)
    inner = mc.chamfer_rect(0.0, 0.0, w / 2 - rim, d / 2 - rim, max(c - rim * 0.4, 0.04))
    # The lip's outer walls, the light top of the strip.
    u = 0.0
    for i in range(len(outer)):
        u = mesh.wall(outer[i], outer[(i + 1) % len(outer)], y_lip, h, 'p_planter', u, (frac, 1.0))
    # Its underside (seen from low eye heights as a thin shadow line).
    for i in range(len(outer)):
        j = (i + 1) % len(outer)
        a, b, bb, ba = outer[i], outer[j], body[j], body[i]
        v = mc.trim_v('p_planter', 0.35)
        mesh.face([(a[0], y_lip, a[1]), (ba[0], y_lip, ba[1]), (bb[0], y_lip, bb[1]), (b[0], y_lip, b[1])],
                  [(mc.trim_u('p_planter', p[0]), v) for p in (a, ba, bb, b)])
    # The rim: a ring from the outer outline in to the inner one, facing up.
    v = mc.trim_v('p_planter', 0.97)
    for i in range(len(outer)):
        j = (i + 1) % len(outer)
        a, b, ib, ia = outer[i], outer[j], inner[j], inner[i]
        mesh.face([(a[0], h, a[1]), (b[0], h, b[1]), (ib[0], h, ib[1]), (ia[0], h, ia[1])],
                  [(mc.trim_u('p_planter', p[0] + p[1]), v) for p in (a, b, ib, ia)])
    # The inner walls, facing in (the outline walked the other way), shaded toward the soil.
    y_soil = h - P['soil_drop']
    rev = inner[::-1]
    u = 0.0
    for i in range(len(rev)):
        u = mesh.wall(rev[i], rev[(i + 1) % len(rev)], y_soil, h, 'p_planter', u, (0.1, 0.6))
    mesh.flat(inner, y_soil, 'p_soil', up=True)
    return y_soil


# ---------------------------------------------------------------------------------------------
# Leaf cards
# ---------------------------------------------------------------------------------------------

def frond(mesh, region, band, root, yaw, pitches, length, half_width, widths, fold=None):
    """A two-sided frond card from `root` heading `yaw` degrees (0 = +Z, 90 = +X), one segment
    per entry of `pitches` (each segment's elevation in degrees, up positive), `length` studs
    along its stem. The texture's frond (its base at the region's u0, tip at u1, spanning `band`
    of the region's height) maps onto the card at `half_width` studs either side of the stem;
    `widths` (one per station, len(pitches) + 1) narrows the card to that fraction of it, which
    crops the image (no stretch) to trim the clear corners. Both halves droop by `fold` degrees
    below the stem."""
    fold = math.radians(P['fold'] if fold is None else fold)
    n = len(pitches)
    step = length / n
    ya = math.radians(yaw)
    heading = (math.sin(ya), 0.0, math.cos(ya))
    side = (math.cos(ya), 0.0, -math.sin(ya))
    dirs = []
    for p in pitches:
        pr = math.radians(p)
        dirs.append((heading[0] * math.cos(pr), math.sin(pr), heading[2] * math.cos(pr)))
    stem = [root]
    for d in dirs:
        stem.append(_add(stem[-1], d, step))
    u0, v0, u1, v1 = region
    ua, ub = u0 + MARGIN * (u1 - u0), u1 - MARGIN * (u1 - u0)
    vc, vh = (v0 + v1) / 2, band / 2 * (v1 - v0)
    edges = {1: [], -1: []}
    uvs = {1: [], -1: []}
    for k in range(n + 1):
        d = _norm(_add(dirs[max(k - 1, 0)], dirs[min(k, n - 1)]))
        up = _cross(d, side)
        w = half_width * widths[k]
        for s in (1, -1):
            off = _add((side[0] * s * math.cos(fold), 0.0, side[2] * s * math.cos(fold)), up, -math.sin(fold))
            edges[s].append(_add(stem[k], off, w))
            uvs[s].append(vc + s * widths[k] * vh)
    us = [ua + (ub - ua) * k / n for k in range(n + 1)]
    for k in range(n):
        # +side: stem k, stem k+1, edge k+1, edge k is counterclockwise seen from above.
        mesh.face([stem[k], stem[k + 1], edges[1][k + 1], edges[1][k]],
                  [(us[k], vc), (us[k + 1], vc), (us[k + 1], uvs[1][k + 1]), (us[k], uvs[1][k])],
                  double=True)
        mesh.face([stem[k], edges[-1][k], edges[-1][k + 1], stem[k + 1]],
                  [(us[k], vc), (us[k], uvs[-1][k]), (us[k + 1], uvs[-1][k + 1]), (us[k + 1], vc)],
                  double=True)


def fern(mesh, root, yaw, pitches, length, widths=None, fold=None, wide=1.0):
    """A fern frond card (the atlas's fern region); `wide` stretches it across its stem."""
    widths = widths or FERN_WIDTHS[len(pitches)]
    half = length * (FERN_BAND / 2) / (1 - 2 * MARGIN) * wide
    frond(mesh, mc.PLANTS['fern'], FERN_BAND, root, yaw, pitches, length, half, widths, fold)


def palm_frond(mesh, root, yaw, pitches, length, widths=None, fold=None, wide=1.0):
    """A palm frond card (the atlas's frond region); `wide` stretches it across its stem."""
    widths = widths or PALM_WIDTHS[len(pitches)]
    half = length * (FROND_BAND / 4) / (1 - 2 * MARGIN) * wide
    frond(mesh, mc.PLANTS['frond'], FROND_BAND, root, yaw, pitches, length, half, widths, fold)


# Card widths per station (fraction of the texture's band): the narrowest that never crop the
# drawn frond (measured from plants.png's alpha; rerun checkpoints/props/_b_widths.py if the
# drawing changes), so the clear corners near a frond's base and tip cost no overdraw.
FERN_WIDTHS = {3: (0.27, 1.0, 1.0, 0.59), 4: (0.23, 0.98, 1.0, 1.0, 0.55)}
PALM_WIDTHS = {4: (0.11, 0.75, 1.0, 1.0, 0.84), 5: (0.13, 0.64, 0.95, 1.0, 1.0, 0.84)}


def mound(mesh, cx, y, cz, size, height, turn=0.0):
    """The clump card raised into a low four-sided pyramid (a leafy mound, 4 triangles, seen
    from above and the side), its apex `height` over the card's centre."""
    r = size / 2
    u0, v0, u1, v1 = mc.PLANTS['clump']
    a = math.radians(turn)
    corners = []
    for dx, dz, uv in ((-1, 1, (u0, v0)), (1, 1, (u1, v0)), (1, -1, (u1, v1)), (-1, -1, (u0, v1))):
        x = dx * math.cos(a) + dz * math.sin(a)
        z = -dx * math.sin(a) + dz * math.cos(a)
        corners.append(((cx + x * r, y, cz + z * r), uv))
    apex = ((cx, y + height, cz), ((u0 + u1) / 2, (v0 + v1) / 2))
    for i in range(4):
        tri = [corners[i], corners[(i + 1) % 4], apex]
        (p0, _), (p1, _), (p2, _) = tri
        e1 = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
        e2 = (p2[0] - p1[0], p2[1] - p1[1], p2[2] - p1[2])
        if _cross(e1, e2)[1] < 0:
            tri.reverse()
        mesh.face([p for p, _ in tri], [uv for _, uv in tri])


# ---------------------------------------------------------------------------------------------
# Kinds
# ---------------------------------------------------------------------------------------------

def fern_bush(mesh, rng, cx, y, cz, tiers, reach=1.0, yaw0=0.0, wide=None):
    """A fern: tiers of fronds round (cx, cz) from height y. Each tier is (count, length,
    pitches, root radius); fronds in a tier are spaced evenly round with a little jitter."""
    for t, (count, length, pitches, root_r) in enumerate(tiers):
        phase = yaw0 + t * 360.0 / count / 2 + rng.uniform(0, 360.0 / count)
        for k in range(count):
            yaw = phase + 360.0 * k / count + rng.uniform(-9, 9)
            ya = math.radians(yaw)
            root = (cx + math.sin(ya) * root_r, y, cz + math.cos(ya) * root_r)
            ln = length * rng.uniform(0.9, 1.08) * reach
            pitch = [p + rng.uniform(-5, 5) for p in pitches]
            fern(mesh, root, yaw, pitch, ln, wide=wide or P['fern_wide'])


def build_fern_planter():
    rng = random.Random(3201)
    opaque, foliage = mc.Mesh('Opaque'), mc.Mesh('Foliage')
    y_soil = planter(opaque, 3.2, 3.2, 3.0)
    mound(foliage, 0.0, y_soil + 0.02, 0.0, 2.8, 1.2)
    fern_bush(foliage, rng, 0.0, y_soil, 0.0, [
        (10, 2.3, (46, 18, -12, -40), 0.55),  # outer: arch over the rim and droop
        (9, 3.2, (70, 52, 32, 10), 0.3),  # middle
        (6, 4.7, (80, 70, 56, 38), 0.15),  # inner: leaning out like a vase, to about 7
    ])
    return {'Opaque': opaque, 'Foliage': foliage}


def build_palm_planter():
    rng = random.Random(4801)
    opaque, foliage = mc.Mesh('Opaque'), mc.Mesh('Foliage')
    y_soil = planter(opaque, 4.8, 4.8, mc.PLANTER_BOX_HEIGHT)
    mound(foliage, 0.0, y_soil + 0.02, 0.0, 4.4, 0.7)
    # Small fern fronds round the trunk, tumbling over the rim.
    for k in range(7):
        yaw = 20 + 360.0 / 7 * k + rng.uniform(-10, 10)
        ya = math.radians(yaw)
        root = (math.sin(ya) * 1.0, y_soil, math.cos(ya) * 1.0)
        fern(foliage, root, yaw, (52, 18, -26), 2.3 * rng.uniform(0.9, 1.1), wide=1.0)
    return {'Opaque': opaque, 'Foliage': foliage}


def _trunk_centre(y, height):
    t = max(y, 0.0) / height
    return (P['trunk_lean'] * t * t, P['trunk_lean_z'] * t * t)


def trunk(mesh, height):
    """A gently curving palm trunk, 8 sides, from below the origin up to `height`; the rings of
    p_trunk run along it (three per segment, a darker foot)."""
    sides = P['trunk_sides']
    ys = [P['trunk_foot'], 1.0] + [1.0 + (height - 1.0) * k / 6 for k in range(1, 7)]
    rings = []
    for y in ys:
        t = max(y, 0.0) / height
        r = P['trunk_top_r'] + (P['trunk_base_r'] - P['trunk_top_r']) * (1 - t) ** 1.4
        if y < 0.5:
            r *= 1.06  # a slight flare at the foot
        cx, cz = _trunk_centre(y, height)
        rings.append([(x, y, z) for x, z in mc._circle(cx, cz, r, sides)])
    step = 2 * math.pi * P['trunk_base_r'] / sides
    for k in range(len(ys) - 1):
        lo, hi = rings[k], rings[k + 1]
        va, vb = (0.0, 1 / 3) if k == 0 else (1 / 3, 5 / 6)
        va, vb = mc.trim_v('p_trunk', va), mc.trim_v('p_trunk', vb)
        for i in range(sides):
            j = (i + 1) % sides
            ua, ub = mc.trim_u('p_trunk', i * step), mc.trim_u('p_trunk', (i + 1) * step)
            mesh.face([lo[i], lo[j], hi[j], hi[i]], [(ua, va), (ub, va), (ub, vb), (ua, vb)])
    return _trunk_centre(height, height)


# The crown: (count, length, pitches per segment, yaw offset, root lift). Outer fronds arch up
# and out and droop to about -50 degrees at the tip; a middle ring arches higher (the art's
# fountain); three young fronds stand up in the middle.
CROWN = [
    (9, 10.0, (40, 20, -4, -28, -50), 0.0, 0.0),
    (5, 8.6, (64, 48, 28, 4, -22), 20.0, 0.18),
    (3, 5.4, (80, 70, 58, 44), 60.0, 0.35),
]


def _crown(rng):
    """The fronds, round the crown point at the origin."""
    mesh = mc.Mesh('crown')
    for count, length, pitches, offset, lift in CROWN:
        for k in range(count):
            yaw = offset + 360.0 * k / count + rng.uniform(-10, 10)
            ya = math.radians(yaw)
            root = (math.sin(ya) * 0.25, lift, math.cos(ya) * 0.25)
            pitch = [p + rng.uniform(-6, 6) for p in pitches]
            palm_frond(mesh, root, yaw, pitch, length * rng.uniform(0.94, 1.06), fold=P['palm_fold'],
                       wide=P['palm_wide'])
    return mesh


def build_palm():
    rng = random.Random(2280)
    opaque, foliage = mc.Mesh('Opaque'), mc.Mesh('Foliage')
    crown = _crown(rng)
    rise = crown.bounds()[1][1]
    height = mc.PALM_HEIGHT - rise - 0.35  # the trunk top, so the crown's top lands at PALM_HEIGHT
    cx, cz = trunk(opaque, height)
    # The crown shaft: a short swelling where the fronds spring from.
    opaque.frustum(cx, cz, P['trunk_top_r'] * 1.15, 0.18, height - 0.5, height + 0.5, P['trunk_sides'],
                   'p_trunk', top=False, v_range=(0.4, 0.95))
    for k in range(3):
        a = math.radians(40 + 120 * k)
        opaque.sphere(cx + math.sin(a) * 0.42, height - 0.35, cz + math.cos(a) * 0.42, P['coconut_r'],
                      6, 4, 'p_wood_dark')
    foliage.add(crown, offset=(cx, height + 0.35, cz))
    return {'Opaque': opaque, 'Foliage': foliage}


def build_planter_bed():
    rng = random.Random(1603)
    opaque, foliage = mc.Mesh('Opaque'), mc.Mesh('Foliage')
    y_soil = planter(opaque, 16.0, 3.0, 2.5)
    for k in range(7):
        x = -6.5 + 2.1667 * k + rng.uniform(-0.12, 0.12)
        mound(foliage, x, y_soil + 0.02, 0.0, 2.6, 0.8, 180 * (k % 2))
        # The end clusters a little smaller, so the ferns spill under a stud past the ends.
        fern_bush(foliage, rng, x, y_soil, rng.uniform(-0.15, 0.15), [
            (4, 2.4, (50, 18, -24), 0.4),  # arching over the trough's sides and ends
            (2, 3.2, (74, 56, 32), 0.15),  # upright, arching
        ], reach=0.8 if k in (0, 6) else 1.0, wide=0.95)
    return {'Opaque': opaque, 'Foliage': foliage}


KINDS = {
    'FernPlanter': build_fern_planter,
    'PalmPlanter': build_palm_planter,
    'Palm': build_palm,
    'PlanterBed': build_planter_bed,
}
