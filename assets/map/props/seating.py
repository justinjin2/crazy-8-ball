"""The seating family (Stage 3 props): the lounge's U sectional (LoungeCouch), the ocean-side
sofa group (SideCouch), the round coffee table (CoffeeTable) and the fire pit (FirePit).

Built after 03-detail-assets (the lounge couch and fire pit panels) in the brief's low-poly,
clean style: chunky bevelled blocks, smooth colour from the props trim sheet's p_ strips, the
soft AO at each strip's foot put at the foot of every face. Prop-local frame (gen_props.py):
Roblox studs and axes, the footprint centred on the origin, the floor at Y 0, the front +Z.
Every seat top and outline sits on the gray-box's collision boxes (gen_graybox.prop), which
stay the game's collision.
"""

import math

import map_common as mc

# ---------------------------------------------------------------------------------------------
# Geometry helpers: faces with trim UVs projected from their normal
# ---------------------------------------------------------------------------------------------


def _mean(pts):
    n = float(len(pts))
    return (sum(p[0] for p in pts) / n, sum(p[1] for p in pts) / n, sum(p[2] for p in pts) / n)


def _normal(pts):
    """Newell's normal: counterclockwise seen from outside gives the outward normal."""
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        x0, y0, z0 = pts[i]
        x1, y1, z1 = pts[(i + 1) % len(pts)]
        nx += (y0 - y1) * (z0 + z1)
        ny += (z0 - z1) * (x0 + x1)
        nz += (x0 - x1) * (y0 + y1)
    length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / length, ny / length, nz / length)


def _uvs(pts, n, strip, vfun, top, under):
    """Tops (normal up): one lit line of the strip (`top`, else vfun of the highest corner);
    undersides: the dark foot (`under`); everything else: U along the face in studs, V from
    the height (vfun maps Y to a strip fraction, 0 the dark foot)."""
    if n[1] > 0.75:
        v = mc.trim_v(strip, top if top is not None else vfun(max(p[1] for p in pts)))
        return [(mc.trim_u(strip, p[0]), v) for p in pts]
    if n[1] < -0.75:
        v = mc.trim_v(strip, under)
        return [(mc.trim_u(strip, p[0]), v) for p in pts]
    tx, tz = n[2], -n[0]
    length = math.hypot(tx, tz) or 1.0
    tx, tz = tx / length, tz / length
    return [(mc.trim_u(strip, p[0] * tx + p[2] * tz), mc.trim_v(strip, vfun(p[1]))) for p in pts]


def _poly(mesh, pts, strip, vfun=None, away=None, toward=None, top=None, under=0.03, uvs=None):
    """One polygon, turned to face away from the point `away` (inside a convex solid) or along
    the direction `toward`; UVs projected unless given."""
    pts = list(pts)
    n = _normal(pts)
    flip = False
    if away is not None:
        c = _mean(pts)
        flip = n[0] * (c[0] - away[0]) + n[1] * (c[1] - away[1]) + n[2] * (c[2] - away[2]) < 0
    elif toward is not None:
        flip = n[0] * toward[0] + n[1] * toward[1] + n[2] * toward[2] < 0
    if flip:
        pts.reverse()
        n = (-n[0], -n[1], -n[2])
        if uvs is not None:
            uvs = list(reversed(uvs))
    if uvs is None:
        uvs = _uvs(pts, n, strip, vfun or (lambda y: 0.5), top, under)
    mesh.face(pts, uvs)


def _solid(mesh, rings, strip, vfun, top=None, cap_lo=True, cap_hi=True, apex_lo=None, apex_hi=None):
    """A convex solid lofted through closed rings (lists of (x, y, z), all the same length):
    bands between neighbouring rings, each end capped flat or fanned to an apex."""
    extra = [p for p in (apex_lo, apex_hi) if p is not None]
    centre = _mean([p for r in rings for p in r] + extra)
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            _poly(mesh, [a[i], a[j], b[j], b[i]], strip, vfun, away=centre, top=top)
    for ring, apex, cap in ((rings[0], apex_lo, cap_lo), (rings[-1], apex_hi, cap_hi)):
        if apex is not None:
            for i in range(n):
                _poly(mesh, [ring[i], ring[(i + 1) % n], apex], strip, vfun, away=centre, top=top)
        elif cap:
            _poly(mesh, ring, strip, vfun, away=centre, top=top)


def _ramp(y0, y1, f0, f1):
    """vfun: strip fraction f0 at height y0 to f1 at y1."""
    return lambda y: f0 + (f1 - f0) * (y - y0) / ((y1 - y0) or 1.0)


def _rect(cx, cz, hx, hz, c, y):
    """A chamfered rectangle ring at height y (outward order)."""
    c = max(0.01, min(c, hx * 0.9, hz * 0.9))
    return [(x, y, z) for x, z in mc.chamfer_rect(cx, cz, hx, hz, c)]


def _circle(r, y, segs, phase=0.0, cx=0.0, cz=0.0):
    out = []
    for i in range(segs):
        t = 2 * math.pi * (i + phase) / segs
        out.append((cx + r * math.cos(t), y, cz - r * math.sin(t)))
    return out


def _band(mesh, lo, hi, strip, v_lo, v_hi, facing, axis=(0.0, 0.0)):
    """Quads between two rings of a round part, U round the ring in studs, V from v_lo (ring
    lo) to v_hi; facing 'out'/'in' (from/toward the axis) or 'up'/'down'."""
    n = len(lo)
    u = 0.0
    for i in range(n):
        j = (i + 1) % n
        a, b, c, d = lo[i], lo[j], hi[j], hi[i]
        step = max(math.hypot(b[0] - a[0], b[2] - a[2]), math.hypot(c[0] - d[0], c[2] - d[2]))
        ua, ub = mc.trim_u(strip, u), mc.trim_u(strip, u + step)
        va, vb = mc.trim_v(strip, v_lo), mc.trim_v(strip, v_hi)
        mid = _mean([a, b, c, d])
        radial = (mid[0] - axis[0], 0.0, mid[2] - axis[1])
        hint = {'out': radial, 'in': (-radial[0], 0.0, -radial[2]), 'up': (0, 1, 0), 'down': (0, -1, 0)}[facing]
        _poly(mesh, [a, b, c, d], strip, toward=hint, uvs=[(ua, va), (ub, va), (ub, vb), (ua, vb)])
        u += step


def _disc(mesh, ring, strip, frac, up=True):
    _poly(mesh, ring, strip, toward=(0, 1 if up else -1, 0), top=frac, under=frac)


def _turned(mesh, rot):
    """A copy of a mesh turned by CFrame.Angles(*rot) about its origin."""
    return mc.Mesh(mesh.name).add(mesh, rot=rot)


# ---------------------------------------------------------------------------------------------
# Couch parts
# ---------------------------------------------------------------------------------------------

SEAT_Y = 1.3  # the gray-box seat top
BACK_Y = 2.6  # the gray-box back top
DECK_Y = 0.8  # the couch body's top: the seat cushions sit on it (0.5 thick)
PLINTH_Y = 0.2  # the dark inset base line under the body
PLINTH_INSET = 0.22
GAP = 0.08  # between neighbouring cushions


def _fabric_v(y):
    """The couch fabric's strip fraction by height: the dark foot at the floor, lit near the
    top of the back (one gradient over the whole couch, so its pieces read as one)."""
    if y <= DECK_Y:
        return 0.1 + 0.35 * y / DECK_Y
    return 0.45 + 0.5 * (y - DECK_Y) / (BACK_Y - DECK_Y)


def _cushion(mesh, x0, x1, z0, z1, y0, y1, strip='p_fabric', c=0.3, b=0.16, dome=0.05):
    """A plump seat cushion: a rounded underside (a shadow crease on the deck), straight
    sides, a bevelled top edge and a slightly domed top, lit (0.8)."""
    cx, cz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
    rings = [
        _rect(cx, cz, hx - b * 0.6, hz - b * 0.6, c - b * 0.25, y0),
        _rect(cx, cz, hx, hz, c, y0 + b * 0.7),
        _rect(cx, cz, hx, hz, c, y1 - b),
        _rect(cx, cz, hx - b, hz - b, c - b * 0.4, y1),
    ]
    _solid(mesh, rings, strip, _ramp(y0, y1, 0.22, 0.78), top=0.8, cap_lo=False,
           apex_hi=(cx, y1 + dome, cz))


def _arc(cz, cy, r, a0, a1, steps):
    """Points on a quarter round in the (z, y) plane, from angle a0 to a1 (degrees), ends
    included."""
    return [(cz + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]


def _back_profile(zb, zf, y0, y1, rb, rf, lean=0.0, bulge=0.0):
    """An upholstered backrest's cross-section (z, y): the back face at zb, the front face at
    zf leaning back by `lean` at the top and bowed forward by `bulge` halfway up, the top
    edges rounded (radius rb behind, a softer rf in front; three steps each)."""
    zt = zf - lean
    ym = (y0 + y1 - rf) / 2
    zm = zf - lean * (ym - y0) / (y1 - rf - y0)
    return ([(zb, y0)] + _arc(zb + rb, y1 - rb, rb, 180.0, 90.0, 3)
            + _arc(zt - rf, y1 - rf, rf, 90.0, 0.0, 3) + [(zm + bulge, ym), (zf, y0)])


def _loft_x(profile, x0, x1, strip, vfun, top=0.95):
    """A bar along X with the (z, y) cross-section `profile` (convex), capped at both ends."""
    m = mc.Mesh('loft')
    rings = [[(x0, y, z) for z, y in profile], [(x1, y, z) for z, y in profile]]
    _solid(m, rings, strip, vfun, top=top)
    return m


def _pillow_mesh(strip, w, h, t, corner=0.22, pinch=0.04):
    """A throw pillow facing +Z, centred: a soft square outline (corners cut, sides drawn in a
    little), both faces bulging to a centre point."""
    hw, hh, c = w / 2, h / 2, corner
    outline = [(-hw, -hh + c), (-hw + c, -hh), (0.0, -hh + pinch), (hw - c, -hh), (hw, -hh + c),
               (hw - pinch, 0.0), (hw, hh - c), (hw - c, hh), (0.0, hh - pinch), (-hw + c, hh),
               (-hw, hh - c), (-hw + pinch, 0.0)]
    rings = []
    for z, s in ((-t * 0.3, 0.84), (0.0, 1.0), (t * 0.3, 0.84)):
        rings.append([(x * s, y * s, z) for x, y in outline])
    m = mc.Mesh('pillow')
    _solid(m, rings, strip, _ramp(-hh, hh, 0.3, 0.9), apex_lo=(0.0, 0.0, -t / 2), apex_hi=(0.0, 0.0, t / 2))
    return m


def _place_pillow(out, colour, px, pz, yaw, seat_y=SEAT_Y, w=2.0, h=1.6, t=0.62, lean=15.0, roll=0.0):
    """A pillow sat on the seat (its foot sunk a little into the cushion) and leant back
    against a backrest whose front face passes through (px, pz); yaw 0 faces +Z, 90 faces +X."""
    tilted = _turned(_pillow_mesh('p_cushion_' + colour, w, h, t), (-lean, 0.0, roll))
    lo, _ = tilted.bounds()
    fx, fz = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    push = -lo[2] + 0.02
    out.add(tilted, rot=(0.0, yaw, 0.0), offset=(px + fx * push, seat_y - 0.1 - lo[1], pz + fz * push))


def _u_outline(xo, zb, zf, xi, zi, c):
    """The U sectional's plan (outward order): outer half width xo, back zb, front ends zf,
    the arms' inner edges at +-xi, the back run's front edge at zi; outer corners cut by c."""
    return [(-xo, zb + c), (-xo, zf - c), (-xo + c, zf), (-xi - c, zf), (-xi, zf - c), (-xi, zi),
            (xi, zi), (xi, zf - c), (xi + c, zf), (xo - c, zf), (xo, zf - c), (xo, zb + c),
            (xo - c, zb), (-xo + c, zb)]


def _u_pieces(xo, zb, zf, xi, zi, c):
    """The same plan as three convex pieces (the back run and the two arm runs), for flat
    faces: a concave face would fill the U's mouth."""
    return [[(-xo, zb + c), (-xo, zi), (xo, zi), (xo, zb + c), (xo - c, zb), (-xo + c, zb)],
            [(-xo, zi), (-xo, zf - c), (-xo + c, zf), (-xi - c, zf), (-xi, zf - c), (-xi, zi)],
            [(xi, zi), (xi, zf - c), (xi + c, zf), (xo - c, zf), (xo, zf - c), (xo, zi)]]


def _prism_walls(mesh, poly, y0, y1, strip, v_range):
    u = 0.0
    for i in range(len(poly)):
        u = mesh.wall(poly[i], poly[(i + 1) % len(poly)], y0, y1, strip, u, v_range)


def _couch_base(mesh, outline, inset_outline, pieces=None):
    """The couch body (fabric, PLINTH_Y..DECK_Y, a dark top between the cushions and a dark
    underside) on its inset plinth. A concave outline passes its deck as convex `pieces`."""
    _prism_walls(mesh, inset_outline, 0.0, PLINTH_Y, 'p_fabric', (0.0, 0.04))
    _prism_walls(mesh, outline, PLINTH_Y, DECK_Y, 'p_fabric', (0.04, 0.22))
    for piece in pieces or [outline]:
        mesh.flat(piece, DECK_Y, 'p_fabric', up=True, frac=0.06)
        mesh.flat(piece, PLINTH_Y, 'p_fabric', up=False, frac=0.02)


def _backrest(mesh, x0, x1, zb, zf, y0=DECK_Y, y1=BACK_Y, rb=0.22, rf=0.36, lean=0.12, bulge=0.1, yaw=0.0):
    """A rounded backrest along X (yaw 0), or along Z turned by yaw (+-90), the profile's back
    face at zb (a local depth: for yaw 90 the world X, for yaw -90 minus the world X)."""
    bar = _loft_x(_back_profile(zb, zf, y0, y1, rb, rf, lean, bulge), x0, x1, 'p_fabric', _fabric_v)
    mesh.add(bar, rot=(0.0, yaw, 0.0))


def _split(a, b, count, gap=GAP):
    """`count` equal spans from a to b with `gap` between them."""
    size = (b - a - gap * (count - 1)) / count
    return [(a + k * (size + gap), a + k * (size + gap) + size) for k in range(count)]


# ---------------------------------------------------------------------------------------------
# LoungeCouch: the U sectional (20 x 9, open to +Z)
# ---------------------------------------------------------------------------------------------

def build_lounge_couch():
    m = mc.Mesh('LoungeCouch')
    xo, zb, zf = 10.0, -4.5, 4.5  # the footprint
    xi, zi = 7.0, -1.5  # the arm runs' inner edges, the back run's seat front
    back_t = 0.8  # backrest thickness (gray-box)
    xa = xo - back_t  # 9.2: the arm backs' inner faces
    zc = zb + back_t  # -3.7: the back run's backrest front
    i = PLINTH_INSET
    _couch_base(m, _u_outline(xo, zb, zf, xi, zi, 0.25),
                _u_outline(xo - i, zb + i, zf - i, xi + i, zi - i, 0.25), _u_pieces(xo, zb, zf, xi, zi, 0.25))
    # Backs: the back run between the arm backs, which run the full depth.
    _backrest(m, -xa - 0.05, xa + 0.05, zb, zc)
    _backrest(m, zb, zf, -xo, -xa, yaw=90.0)  # left: local depth = world X
    _backrest(m, zb, zf, -xo, -xa, yaw=-90.0)  # right: local depth = -world X
    # Seat cushions: four on the back run, three on each arm run (the corner one included).
    front = zc + 0.04
    for x0, x1 in _split(-xi + GAP, xi - GAP, 4):
        _cushion(m, x0, x1, front, zi, DECK_Y, SEAT_Y)
    for side in (-1, 1):
        for z0, z1 in _split(front, zf, 3):
            xa0, xa1 = sorted((side * xi, side * (xa - 0.04)))
            _cushion(m, xa0, xa1, z0, z1, DECK_Y, SEAT_Y)
    # Throw pillows round the U, from the left arm's front end to the right's, as in 03.
    colours = ['blue', 'orange', 'white', 'blue', 'orange', 'teal', 'blue', 'white', 'orange', 'blue']
    spots = []
    arm_z = [(z0 + z1) / 2 for z0, z1 in _split(front, zf, 3)]
    for z in reversed(arm_z):
        spots.append((-xa, z, 90.0))
    for x0, x1 in _split(-xi + GAP, xi - GAP, 4):
        spots.append(((x0 + x1) / 2, zc - 0.06, 0.0))
    for z in arm_z:
        spots.append((xa, z, -90.0))
    for k, (px, pz, yaw) in enumerate(spots):
        _place_pillow(m, colours[k], px, pz, yaw, roll=(-3.0, 2.0, -1.0, 3.0)[k % 4])
    seats = [(x, SEAT_Y, -3.0, 0.0) for x in (-6.0, -2.0, 2.0, 6.0)]
    seats += [(-8.5, SEAT_Y, z, 90.0) for z in (0.5, 3.5)]
    seats += [(8.5, SEAT_Y, z, -90.0) for z in (0.5, 3.5)]
    return {'Opaque': m, 'seats': seats, 'lights': []}


# ---------------------------------------------------------------------------------------------
# SideCouch: a straight three-seat sofa and a low wooden table in front (12 x 6)
# ---------------------------------------------------------------------------------------------

def _low_table(mesh, cx, cz, hx, hz, y_top):
    """The sofa group's low table: a bevelled warm-wood top on dark legs, apron and shelf."""
    t0 = y_top - 0.2
    top = [_rect(cx, cz, hx - 0.05, hz - 0.05, 0.12, t0), _rect(cx, cz, hx, hz, 0.15, t0 + 0.05),
           _rect(cx, cz, hx, hz, 0.15, y_top - 0.05), _rect(cx, cz, hx - 0.06, hz - 0.06, 0.1, y_top)]
    _solid(mesh, top, 'p_wood', _ramp(t0, y_top, 0.25, 0.7), top=0.85)
    ax, az = hx - 0.22, hz - 0.22
    _solid(mesh, [_rect(cx, cz, ax, az, 0.06, t0 - 0.2), _rect(cx, cz, ax, az, 0.06, t0)],
           'p_wood_dark', _ramp(t0 - 0.2, t0, 0.4, 0.7), cap_hi=False)
    for sx in (-1, 1):
        for sz in (-1, 1):
            lx, lz = cx + sx * (hx - 0.3), cz + sz * (hz - 0.3)
            _solid(mesh, [_rect(lx, lz, 0.14, 0.14, 0.04, 0.0), _rect(lx, lz, 0.14, 0.14, 0.04, t0)],
                   'p_wood_dark', _ramp(0.0, t0, 0.05, 0.8), cap_lo=False, cap_hi=False)
    _solid(mesh, [_rect(cx, cz, hx - 0.3, hz - 0.3, 0.06, 0.2), _rect(cx, cz, hx - 0.3, hz - 0.3, 0.06, 0.3)],
           'p_wood_dark', _ramp(0.2, 0.3, 0.3, 0.6), top=0.7)


def build_side_couch():
    m = mc.Mesh('SideCouch')
    x_seat = 5.5  # the gray-box seat box: x -5.5..5.5, z -2.9..0.1
    zb, zf = -2.9, 0.1
    zc = zb + 0.8  # the backrest's front
    arm_t, arm_top = 0.5, 2.0
    xo = x_seat + arm_t
    i = PLINTH_INSET
    outline = mc.chamfer_rect(0.0, (zb + zf) / 2, x_seat, (zf - zb) / 2, 0.2)
    inset = mc.chamfer_rect(0.0, (zb + zf) / 2, xo - i, (zf - zb) / 2 - i, 0.2)
    _couch_base(m, outline, inset)
    _backrest(m, -x_seat - 0.1, x_seat + 0.1, zb, zc)
    # Low arms at the ends (a local depth along the world X, as the lounge's arm backs).
    for yaw in (90.0, -90.0):
        z0, z1 = (-zf, -zb) if yaw > 0 else (zb, zf)
        bar = _loft_x(_back_profile(-xo, -x_seat, PLINTH_Y, arm_top, 0.2, 0.26, 0.0, 0.04), z0, z1, 'p_fabric', _fabric_v)
        m.add(bar, rot=(0.0, yaw, 0.0))
    for x0, x1 in _split(-x_seat + 0.04, x_seat - 0.04, 3):
        _cushion(m, x0, x1, zc + 0.04, zf, DECK_Y, SEAT_Y)
    colours = ['blue', 'orange', 'teal', 'blue']
    for k, (x0, x1) in enumerate(_split(-x_seat + 0.3, x_seat - 0.3, 4, gap=0.9)):
        _place_pillow(m, colours[k], (x0 + x1) / 2, zc - 0.06, 0.0, roll=(-3.0, 2.0, -2.0, 3.0)[k])
    _low_table(m, 0.0, 1.6, 1.45, 1.2, 1.1)
    seats = [(x, SEAT_Y, -1.4, 0.0) for x in (-3.5, 0.0, 3.5)]
    return {'Opaque': m, 'seats': seats, 'lights': []}


# ---------------------------------------------------------------------------------------------
# CoffeeTable: round, 2.8 across, 1.3 high
# ---------------------------------------------------------------------------------------------

def build_coffee_table():
    m = mc.Mesh('CoffeeTable')
    segs = 16
    r, top_y, thick = 1.4, 1.3, 0.2
    y0 = top_y - thick
    rings = [_circle(r - 0.05, y0, segs), _circle(r, y0 + 0.04, segs), _circle(r, top_y - 0.05, segs),
             _circle(r - 0.07, top_y, segs)]
    _band(m, rings[0], rings[1], 'p_wood', 0.2, 0.3, 'out')
    _band(m, rings[1], rings[2], 'p_wood', 0.3, 0.7, 'out')
    _band(m, rings[2], rings[3], 'p_wood', 0.7, 0.85, 'out')
    _disc(m, rings[3], 'p_wood', 0.85)
    _disc(m, rings[0], 'p_wood', 0.03, up=False)
    # A thin dark apron under the top, four chunky square legs out near the rim (light shows
    # between them, as in 03) and a low round shelf tying them together.
    apron_y = y0 - 0.14
    apron = [_circle(1.14, apron_y, segs), _circle(1.14, y0, segs)]
    _band(m, apron[0], apron[1], 'p_wood_dark', 0.35, 0.7, 'out')
    _disc(m, apron[0], 'p_wood_dark', 0.03, up=False)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        lx, lz = 0.93 * math.cos(a), 0.93 * math.sin(a)
        _solid(m, [_rect(lx, lz, 0.16, 0.16, 0.05, 0.0), _rect(lx, lz, 0.16, 0.16, 0.05, apron_y)],
               'p_wood_dark', _ramp(0.0, apron_y, 0.05, 0.8), cap_lo=False, cap_hi=False)
    shelf = [_circle(0.9, 0.18, 12), _circle(0.9, 0.28, 12)]
    _band(m, shelf[0], shelf[1], 'p_wood_dark', 0.3, 0.6, 'out')
    _disc(m, shelf[1], 'p_wood_dark', 0.7)
    _disc(m, shelf[0], 'p_wood_dark', 0.03, up=False)
    return {'Opaque': m, 'seats': [], 'lights': []}


# ---------------------------------------------------------------------------------------------
# FirePit: a stone drum 4.5 across and 1.4 high, a light cap ring, a blue glass ring, dark
# stones on a glowing bed and a low-poly flame
# ---------------------------------------------------------------------------------------------

def _drum_ring(r, y, panels, groove=0.07, depth=0.05):
    """The drum's outline: `panels` flat stone panels with a small V-groove between each."""
    out = []
    for k in range(panels):
        a0, a1 = 2 * math.pi * k / panels, 2 * math.pi * (k + 1) / panels
        e = groove / r
        for a, rad in ((a0, r - depth), (a0 + e, r), (a1 - e, r)):
            out.append((rad * math.cos(a), y, -rad * math.sin(a)))
    return out


def _scaled(ring, s, y):
    return [(x * s, y, z * s) for x, _, z in ring]


def _stone(mesh, x, z, r, h, y, turn):
    """A low rounded pebble (six sides) sitting on the bed at height y."""
    def ring(rr, yy):
        return [(x + rr * math.cos(turn + 2 * math.pi * k / 6), yy, z - rr * 0.85 * math.sin(turn + 2 * math.pi * k / 6))
                for k in range(6)]
    _solid(mesh, [ring(r * 0.9, y - 0.05), ring(r, y + h * 0.3), ring(r * 0.65, y + h * 0.8)],
           'p_stone_dark', _ramp(y, y + h, 0.3, 0.9), cap_lo=False, apex_hi=(x, y + h, z))


def _flame_blade(mesh, x, z, r, h, y, lean, turn, flat=0.7):
    """A leaning teardrop flame tongue: fat low down, curling to a point; its cross-section a
    flattened pentagon turned by `turn` (radians), its tip moved by `lean` (dx, dz)."""
    def ring(t, rr):
        off = t ** 1.6
        cx, cz = x + lean[0] * off, z + lean[1] * off
        pts = []
        for k in range(5):
            a = 2 * math.pi * k / 5
            u, v = rr * math.cos(a), rr * flat * math.sin(a)
            pts.append((cx + u * math.cos(turn) - v * math.sin(turn), y + t * h,
                        cz - (u * math.sin(turn) + v * math.cos(turn))))
        return pts
    tip = (x + lean[0], y + h, z + lean[1])
    _solid(mesh, [ring(0.0, r * 0.75), ring(0.2, r), ring(0.45, r * 0.78), ring(0.72, r * 0.4)], 'p_white',
           lambda yy: 0.5, cap_lo=False, apex_hi=tip)


def build_fire_pit():
    m = mc.Mesh('FirePit')
    glow = mc.Mesh('FirePitGlow')
    R, panels = 2.12, 14
    foot_y, drum_top, cap_y0, cap_top = 0.12, 1.12, 1.12, 1.4
    r_cap, r_in, r_glass, bed_y = 2.27, 1.66, 1.3, 1.05
    # The drum: vertical stone panels on a small recessed foot.
    drum_lo, drum_hi = _drum_ring(R, foot_y, panels), _drum_ring(R, drum_top, panels)
    foot_s = (R - 0.1) / R
    _band(m, _scaled(drum_lo, foot_s, 0.0), _scaled(drum_lo, foot_s, foot_y), 'p_stone_cap', 0.0, 0.05, 'out')
    _band(m, _scaled(drum_lo, foot_s, foot_y), drum_lo, 'p_stone_cap', 0.02, 0.02, 'down')
    _band(m, drum_lo, drum_hi, 'p_stone_cap', 0.08, 0.95, 'out')
    # The cap ring: overhanging a little, a bevelled outer edge, a lit top, a soft inner edge.
    segs = 18
    cap = [_circle(R - 0.1, cap_y0, segs), _circle(r_cap, cap_y0, segs), _circle(r_cap, cap_top - 0.08, segs),
           _circle(r_cap - 0.08, cap_top, segs), _circle(r_in + 0.06, cap_top, segs),
           _circle(r_in, cap_top - 0.05, segs), _circle(r_in, 1.28, segs)]
    _band(m, cap[0], cap[1], 'p_planter', 0.02, 0.02, 'down')
    _band(m, cap[1], cap[2], 'p_planter', 0.25, 0.7, 'out')
    _band(m, cap[2], cap[3], 'p_planter', 0.7, 0.85, 'out')
    _band(m, cap[3], cap[4], 'p_planter', 0.9, 0.9, 'up')
    _band(m, cap[4], cap[5], 'p_planter', 0.8, 0.7, 'in')
    _band(m, cap[5], cap[6], 'p_planter', 0.7, 0.35, 'in')
    # The blue glass ring, sloping gently in, then the dark well down to the bed.
    glass = [cap[6], _circle(r_glass, 1.23, segs)]
    _band(m, glass[0], glass[1], 'p_glass_ring', 0.85, 0.75, 'up')
    well = [glass[1], _circle(r_glass, bed_y - 0.05, segs)]
    _band(m, well[0], well[1], 'p_stone_dark', 0.5, 0.1, 'in')
    # The glowing bed and the dark stones round the flame.
    _disc(glow, _circle(r_glass + 0.01, bed_y, segs), 'p_white', 0.5)
    stones = [(0.95, 0.0, 0.26, 0.2), (0.9, 48.0, 0.3, 0.22), (1.0, 95.0, 0.24, 0.18), (0.88, 140.0, 0.3, 0.2),
              (0.98, 190.0, 0.27, 0.22), (0.9, 238.0, 0.29, 0.19), (0.97, 285.0, 0.25, 0.21),
              (0.92, 325.0, 0.28, 0.2), (0.5, 20.0, 0.22, 0.16), (0.52, 150.0, 0.2, 0.15), (0.48, 260.0, 0.21, 0.17)]
    for k, (d, a, r, h) in enumerate(stones):
        t = math.radians(a)
        _stone(m, d * math.cos(t), -d * math.sin(t), r * 0.85, h * 0.9, bed_y, t + 0.7 * k)
    # The flame: a tall, round centre tongue and four shorter ones round it whose tips swirl
    # in toward it (the art's converging flame), each broad face turned to the outside.
    _flame_blade(glow, 0.0, 0.0, 0.52, 1.8, bed_y - 0.05, (0.06, -0.05), 0.3, flat=0.85)
    for deg, d, r, h in ((15.0, 0.46, 0.33, 1.25), (135.0, 0.5, 0.31, 1.05), (225.0, 0.5, 0.34, 1.4),
                         (300.0, 0.5, 0.29, 0.95)):
        a = math.radians(deg)
        radial, tangent = (math.cos(a), -math.sin(a)), (-math.sin(a), -math.cos(a))
        lean = (tangent[0] * 0.24 + radial[0] * 0.06, tangent[1] * 0.24 + radial[1] * 0.06)
        _flame_blade(glow, d * radial[0], d * radial[1], r, h, bed_y - 0.05, lean, a + math.pi / 2, flat=0.6)
    return {'Opaque': m, 'Glow': glow, 'seats': [], 'lights': [(0.0, 2.2, 0.0)]}


KINDS = {
    'LoungeCouch': build_lounge_couch,
    'SideCouch': build_side_couch,
    'CoffeeTable': build_coffee_table,
    'FirePit': build_fire_pit,
}
