"""Lights and feature props (Stage 3): the floor lanterns, the pergola's hanging globe lights,
the umbrella set with its two loungers, and the grand piano with its bench.

Each build() returns gen_props' dict ('Opaque', optional 'Glow', 'seats', 'lights'), in the
prop-local frame: Roblox studs, the footprint centred on the origin, the floor at Y 0 (the
GlobeLight's origin is the globe's centre), the front toward +Z. Opaque parts use only the
props trim sheet's p_ strips; the Glow meshes (lantern glass, the globe) draw in one flat
colour, so their UVs only need to be valid.

Art: reference/03-detail-assets.jpg (LIGHT, UMBRELLA SEATING, the PERGOLA's globes) first,
02-day-view.jpg for the grand piano. Sizes match the gray-box collision (gen_graybox.prop).
"""

import math

import map_common as mc

# ---------------------------------------------------------------------------------------------
# Small vector helpers and mesh pieces the shared builder lacks
# ---------------------------------------------------------------------------------------------


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    n = math.sqrt(_dot(a, a)) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def _dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(len(a))))


def _newell(pts):
    """A polygon's normal (right-handed, counterclockwise = toward the viewer)."""
    n = [0.0, 0.0, 0.0]
    for i, (x1, y1, z1) in enumerate(pts):
        x2, y2, z2 = pts[(i + 1) % len(pts)]
        n[0] += (y1 - y2) * (z1 + z2)
        n[1] += (z1 - z2) * (x1 + x2)
        n[2] += (x1 - x2) * (y1 + y2)
    return tuple(n)


def oface(m, pts, uvs, out):
    """A face that looks along `out`: the corners are reversed when their winding faces away."""
    if _dot(_newell(pts), out) < 0:
        pts, uvs = list(reversed(pts)), list(reversed(uvs))
    m.face(pts, uvs)


def ring(cx, cz, rx, rz, segs, phase=0.0):
    """Points round an ellipse in outward order (walls built along it face out, like
    map_common's circles): phase 0.5 on a square or octagon puts flats toward +-X and +-Z."""
    out = []
    for i in range(segs):
        t = 2 * math.pi * (i + phase) / segs
        out.append((cx + rx * math.cos(t), cz - rz * math.sin(t)))
    return out


def lift(poly, y):
    return [(x, y, z) for x, z in poly]


def loft(m, rings, strip, vs=None, flip=False):
    """Side faces between consecutive rings of 3D points, each ring in outward order and the
    rings going up (or out and up) so the faces look outward; flip turns them inward. U runs
    round the first ring in studs, V is vs[k] (a strip fraction) at ring k. A ring that is a
    single repeated point closes to an apex."""
    n = len(rings[0])
    vs = vs if vs is not None else [k / (len(rings) - 1) for k in range(len(rings))]
    us = [0.0]
    for i in range(n):
        us.append(us[-1] + _dist(rings[0][i], rings[0][(i + 1) % n]))
    for k in range(len(rings) - 1):
        lo, hi = rings[k], rings[k + 1]
        va, vb = mc.trim_v(strip, vs[k]), mc.trim_v(strip, vs[k + 1])
        apex_hi = all(_dist(p, hi[0]) < 1e-9 for p in hi)
        apex_lo = all(_dist(p, lo[0]) < 1e-9 for p in lo)
        for i in range(n):
            j = (i + 1) % n
            ua, ub = mc.trim_u(strip, us[i]), mc.trim_u(strip, us[i + 1])
            if apex_hi:
                pts, uvs = [lo[i], lo[j], hi[0]], [(ua, va), (ub, va), ((ua + ub) / 2, vb)]
            elif apex_lo:
                pts, uvs = [lo[0], hi[j], hi[i]], [((ua + ub) / 2, va), (ub, vb), (ua, vb)]
            else:
                pts, uvs = [lo[i], lo[j], hi[j], hi[i]], [(ua, va), (ub, va), (ub, vb), (ua, vb)]
            if flip:
                pts, uvs = list(reversed(pts)), list(reversed(uvs))
            m.face(pts, uvs)


def cap(m, pts, strip, up=True, frac=0.5, vfun=None):
    """A face over a ring of 3D points in outward order (facing up, or down), U planar along X,
    V a constant strip fraction (or vfun(x, y, z) -> fraction)."""
    uvs = [(mc.trim_u(strip, p[0]), mc.trim_v(strip, vfun(*p) if vfun else frac)) for p in pts]
    if not up:
        pts, uvs = list(reversed(pts)), list(reversed(uvs))
    m.face(list(pts), uvs)


def beam(m, a, b, w, strip, h=None, ends=True, v_range=(0.3, 0.9), up=(0.0, 1.0, 0.0)):
    """A square (w x h) bar from point a to point b, any direction; U along it in studs."""
    h = w if h is None else h
    d = _unit(_sub(b, a))
    ref = up if abs(_dot(d, _unit(up))) < 0.95 else (1.0, 0.0, 0.0)
    u = _unit(_cross(d, ref))
    v = _cross(u, d)
    offs = [_add(_mul(u, sx * w / 2), _mul(v, sy * h / 2)) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
    length = _dist(a, b)
    ua, ub = 0.0, mc.trim_u(strip, length)
    va, vb = mc.trim_v(strip, v_range[0]), mc.trim_v(strip, v_range[1])
    for k in range(4):
        o0, o1 = offs[k], offs[(k + 1) % 4]
        pts = [_add(a, o0), _add(a, o1), _add(b, o1), _add(b, o0)]
        oface(m, pts, [(ua, va), (ua, vb), (ub, vb), (ub, va)], _add(o0, o1))
    if ends:
        vm = mc.trim_v(strip, (v_range[0] + v_range[1]) / 2)
        for p, out in ((a, _mul(d, -1)), (b, d)):
            oface(m, [_add(p, o) for o in offs], [(0.0, vm)] * 4, out)


def pillow(m, x0, y0, z0, x1, y1, z1, strip, bevel, chamfer=0.0, v_range=(0.0, 1.0)):
    """A box whose top edges are bevelled (a cushion or a soft slab): straight sides to
    y1 - bevel, a sloped band, then the top inset by bevel."""
    cx, cz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2

    def rect(inset):
        c = min(chamfer, hx - inset, hz - inset) if chamfer > 0 else 0.0
        if c > 1e-6:
            return mc.chamfer_rect(cx, cz, hx - inset, hz - inset, c)
        return mc.outward_rect(cx - hx + inset, cz - hz + inset, cx + hx - inset, cz + hz - inset)

    lo, top = rect(0.0), rect(bevel)
    y_mid = y1 - bevel
    t = (y_mid - y0) / (y1 - y0)
    vm = v_range[0] + (v_range[1] - v_range[0]) * t
    loft(m, [lift(lo, y0), lift(lo, y_mid), lift(top, y1)], strip, [v_range[0], vm, v_range[1]])
    cap(m, lift(top, y1), strip, frac=v_range[1])


def tapered_leg(m, cx, cz, y0, y1, r0, r1, strip, chamfer=0.0):
    """A square leg narrowing from half-width r1 at the top (y1) to r0 at the foot (y0)."""
    if chamfer > 0:
        lo = mc.chamfer_rect(cx, cz, r0, r0, chamfer * r0 / r1)
        hi = mc.chamfer_rect(cx, cz, r1, r1, chamfer)
    else:
        lo = mc.outward_rect(cx - r0, cz - r0, cx + r0, cz + r0)
        hi = mc.outward_rect(cx - r1, cz - r1, cx + r1, cz + r1)
    loft(m, [lift(lo, y0), lift(hi, y1)], strip, [0.05, 0.95])


def offset_outline(poly, d):
    """An outline (x, z) in outward order moved inward by d (mitred corners)."""
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = poly[i - 1], poly[i], poly[(i + 1) % n]
        normals = []
        for a, b in ((p0, p1), (p1, p2)):
            dx, dz = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dz) or 1.0
            normals.append((dz / length, -dx / length))  # inward: the wall's normal flipped
        nx, nz = normals[0][0] + normals[1][0], normals[0][1] + normals[1][1]
        length = math.hypot(nx, nz) or 1.0
        nx, nz = nx / length, nz / length
        cos_half = max(0.35, nx * normals[1][0] + nz * normals[1][1])
        out.append((p1[0] + nx * d / cos_half, p1[1] + nz * d / cos_half))
    return out


def _bezier(p0, p1, p2, p3, n):
    out = []
    for k in range(n + 1):
        t = k / n
        a, b, c, e = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        out.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
    return out


# ---------------------------------------------------------------------------------------------
# Lanterns (03 art, LIGHT): a stepped plinth, a dark bronze frame with corner posts round four
# glowing glass panels set a little inside it, a stepped cap and a loop handle on top.
# ---------------------------------------------------------------------------------------------

LANTERN = {
    # Sizes are for the 1.5-stud lantern (4.0 tall) and scale with the width; the glass takes
    # whatever height is left.
    'plinth': (0.17, 0.1),  # the two plinth steps' heights
    'body_half': 0.58,  # half the body's width (the plinth is the full footprint)
    'post': 0.13,  # corner post thickness
    'rail': 0.15,  # the top and bottom rails' heights
    'inset': 0.06,  # how far the glass sits inside the frame's outer faces
    'cap': (0.07, 0.12, 0.07),  # the cap slab's overhang and height, the raised step's height
    'loop': (0.5, 0.66, 0.065),  # the loop handle's width, height and bar thickness
}


def lantern(width, height, light=None):
    s = width / 1.5
    L = LANTERN
    m, glow = mc.Mesh('Opaque'), mc.Mesh('Glow')
    hw = width / 2
    b = L['body_half'] * s
    t = L['post'] * s
    rail = L['rail'] * s
    over, cap_h, step_h = (v * s for v in L['cap'])
    loop_w, loop_h, bar = (v * s for v in L['loop'])
    neck_h = 0.07 * s
    # The plinth: a low chamfered slab and a second, smaller step.
    p0, p1 = L['plinth'][0] * s, L['plinth'][1] * s
    m.box(-hw, 0.0, -hw, hw, p0, hw, 'p_frame', chamfer=0.07 * s, v_range=(0.0, 0.6))
    step = hw - 0.08 * s
    m.box(-step, p0, -step, step, p0 + p1, step, 'p_frame', chamfer=0.05 * s, v_range=(0.3, 0.8))
    glass0 = p0 + p1 + rail
    glass1 = height - (loop_h + neck_h + step_h + cap_h + rail)
    # The rails: a solid band at the foot and at the head of the glass.
    m.box(-b, p0 + p1, -b, b, glass0, b, 'p_frame', v_range=(0.3, 0.7))
    m.box(-b, glass1, -b, b, glass1 + rail, b, 'p_frame', v_range=(0.5, 0.9))
    # The corner posts stand proud of the glass, so the frame reads as a dark outline.
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = sx * (b - t / 2), sz * (b - t / 2)
            m.box(cx - t / 2, glass0, cz - t / 2, cx + t / 2, glass1, cz + t / 2, 'p_frame',
                  v_range=(0.4, 0.9))
    # The glass: four panels just inside the frame (a closed band; the rails cover its ends).
    g = b - L['inset'] * s
    square = mc.outward_rect(-g, -g, g, g)
    loft(glow, [lift(square, glass0), lift(square, glass1)], 'p_white')
    # The cap: a wide chamfered slab overhanging the body, a smaller raised step with bevelled
    # edges, a short neck.
    y = glass1 + rail
    c = b + over
    m.box(-c, y, -c, c, y + cap_h, c, 'p_frame', chamfer=0.04 * s, v_range=(0.5, 1.0))
    y += cap_h
    r = b - 0.1 * s
    pillow(m, -r, y, -r, r, y + step_h, r, 'p_frame', 0.035 * s, v_range=(0.6, 1.0))
    y += step_h
    n = 0.08 * s
    m.box(-n, y, -n, n, y + neck_h, n, 'p_frame', v_range=(0.4, 1.0))
    y += neck_h
    # The loop handle: a flat rectangular ring facing the front, up to the full height.
    lw = loop_w / 2
    top = height
    for x0, x1, y0, y1 in ((-lw, -lw + bar, y, top), (lw - bar, lw, y, top),
                           (-lw + bar, lw - bar, top - bar, top), (-lw + bar, lw - bar, y, y + bar)):
        m.box(x0, y0, -bar / 2, x1, y1, bar / 2, 'p_frame', v_range=(0.5, 1.0))
    out = {'Opaque': m, 'Glow': glow, 'seats': [], 'lights': []}
    if light is not None:
        out['lights'] = [(0.0, light, 0.0)]
    return out


def build_lantern():
    return lantern(1.5, 4.0)


def build_lantern_tall():
    return lantern(2.2, 6.5, light=4.0)


# ---------------------------------------------------------------------------------------------
# Globe light (03 art, PERGOLA): a glowing orb, a small dark cap, a thin cord up to the beam.
# ---------------------------------------------------------------------------------------------

GLOBE_R = 0.75  # the globe is 1.5 across
CORD = 3.0  # the cord's length above the globe's top


def build_globe_light():
    m, glow = mc.Mesh('Opaque'), mc.Mesh('Glow')
    glow.sphere(0.0, 0.0, 0.0, GLOBE_R, 12, 6, 'p_white')
    # The socket cap: a short cone sunk into the globe's shoulder.
    y0, y1 = 0.58, 0.9
    rings = [lift(ring(0.0, 0.0, 0.33, 0.33, 8), y0), lift(ring(0.0, 0.0, 0.2, 0.2, 8), y1)]
    loft(m, rings, 'p_frame', [0.3, 0.9])
    # The cord: four-sided, straight up to the beam. (No tops: the cord covers the cap's, the
    # beam the cord's; the globe gets the triangles.)
    c = 0.045
    top = GLOBE_R + CORD
    loft(m, [lift(mc.outward_rect(-c, -c, c, c), y1), lift(mc.outward_rect(-c, -c, c, c), top)], 'p_frame',
         [0.5, 0.9])
    return {'Opaque': m, 'Glow': glow, 'seats': [], 'lights': []}


# ---------------------------------------------------------------------------------------------
# Umbrella set (03 art, UMBRELLA SEATING): a cream octagonal market umbrella on a wooden pole
# with a round dark base (eight flat panels, rib tips at the corners, a short valance, a vent
# and a finial); two dark loungers side by side under it, backs raised at -Z, feet toward +Z.
# ---------------------------------------------------------------------------------------------

UMBRELLA = {
    'flat': 6.0,  # half the canopy across its flats (12 across, the gray-box)
    'rim_y': 9.0,  # the rim's height at the ribs
    'top_y': 10.95,  # the canopy's top ring, round the vent
    'top_r': 0.6,
    'valance': 0.3,  # the flap round the rim
    'vent_r': 1.1,  # the vent cap over the top
    'vent_y': (11.05, 11.4),  # the vent cap's rim and peak
    'finial': 11.8,  # the finial's top
    'pole_r': 0.19,  # 0.38 thick
    'base_r': 0.7,  # the round base, between the loungers
}
LOUNGER_X = 1.8  # the loungers' centres (the gray-box)
LOUNGER_CUSHION = 'p_lounger'  # the art's loungers are dark grey cushions on dark wood frames
LOUNGER_FRAME = 'p_wood_dark'
BACK_TILT = 32.0  # the backrest's lean back from upright, degrees


def _octagon(r, y):
    """The canopy's octagon at radius r (to its corners), corners at the ribs, flats toward
    +-X and +-Z."""
    return lift(ring(0.0, 0.0, r, r, 8, 0.5), y)


def _canopy(m):
    U = UMBRELLA
    R = U['flat'] / math.cos(math.pi / 8)  # the rib tips (corner radius)
    rim_y, top_y, top_r = U['rim_y'], U['top_y'], U['top_r']
    rim, top = _octagon(R, rim_y), _octagon(top_r, top_y)
    # Eight flat panels, each UV'd on its own across one fold period of the canvas strip, so
    # the soft fold shading darkens toward its ribs; the underside the same, in the shade.
    period = 1.0 / 6.0
    for k in range(8):
        j = (k + 1) % 8
        for up, (va, vb) in ((True, (0.5, 0.97)), (False, (0.1, 0.24))):
            pts = [rim[k], rim[j], top[j], top[k]]
            u_top = period * (0.5 - 0.5 * top_r / R)
            uvs = [(0.0, mc.trim_v('p_canvas', va)), (period, mc.trim_v('p_canvas', va)),
                   (period - u_top, mc.trim_v('p_canvas', vb)), (u_top, mc.trim_v('p_canvas', vb))]
            if not up:
                pts, uvs = list(reversed(pts)), list(reversed(uvs))
            m.face(pts, uvs)
    # The valance: a short flap hanging from the rim, both sides.
    drop = U['valance']
    low = [(p[0], p[1] - drop, p[2]) for p in rim]
    loft(m, [low, rim], 'p_canvas', [0.3, 0.55])
    loft(m, [low, rim], 'p_canvas', [0.08, 0.2], flip=True)
    # The vent: a small octagonal cap over the top ring with a short skirt, both sides.
    vr = U['vent_r']
    vy0, vy1 = U['vent_y']
    vent, vent_low = _octagon(vr, vy0), _octagon(vr, vy0 - 0.12)
    loft(m, [vent, [(0.0, vy1, 0.0)] * 8], 'p_canvas', [0.6, 1.0])
    loft(m, [vent, [(0.0, vy1, 0.0)] * 8], 'p_canvas', [0.12, 0.25], flip=True)
    loft(m, [vent_low, vent], 'p_canvas', [0.35, 0.6])
    loft(m, [vent_low, vent], 'p_canvas', [0.08, 0.2], flip=True)
    # The finial: a small wooden knob and point on the peak.
    m.sphere(0.0, vy1 + 0.13, 0.0, 0.13, 6, 4, 'p_pole')
    loft(m, [lift(ring(0.0, 0.0, 0.06, 0.06, 4, 0.5), vy1 + 0.22), [(0.0, U['finial'], 0.0)] * 4], 'p_pole',
         [0.5, 1.0])
    return R


def _umbrella_frame(m, R):
    """The pole, the hub, the ribs under the canopy (their tips poking out at the corners), the
    runner and its stretchers, the base."""
    U = UMBRELLA
    pr = U['pole_r']
    base_top = 0.3
    br = U['base_r']
    # The base: a low dark dome.
    b0 = lift(ring(0.0, 0.0, br, br, 12), 0.0)
    b1 = lift(ring(0.0, 0.0, br * 0.9, br * 0.9, 12), 0.12)
    b2 = lift(ring(0.0, 0.0, 0.3, 0.3, 12), base_top)
    loft(m, [b0, b1, b2], 'p_frame', [0.0, 0.5, 0.9])
    cap(m, b2, 'p_frame', frac=0.9)
    # The pole, up into the vent.
    top = U['vent_y'][1] - 0.1
    loft(m, [lift(ring(0.0, 0.0, pr, pr, 8), base_top), lift(ring(0.0, 0.0, pr * 0.85, pr * 0.85, 8), top)],
         'p_pole', [0.45, 1.0])
    # The hub under the top ring and the runner lower down, both collars on the pole.
    rim_y, top_y, top_r = U['rim_y'], U['top_y'], U['top_r']
    hub_y = top_y - 0.15
    m.cylinder(0.0, 0.0, 0.3, hub_y - 0.2, hub_y + 0.1, 8, 'p_pole', v_range=(0.3, 0.9))
    runner_y = 7.9
    m.cylinder(0.0, 0.0, 0.27, runner_y - 0.22, runner_y + 0.22, 8, 'p_pole', v_range=(0.3, 0.9))

    def under(r):
        # Just under the canvas along a rib line, r from the pole.
        return top_y + (top_r - r) / (R - top_r) * (top_y - rim_y) - 0.08

    for k in range(8):
        ang = 2 * math.pi * (k / 8.0 + 0.5 / 8)
        cx, cz = math.cos(ang), -math.sin(ang)
        a = (cx * 0.3, under(0.3), cz * 0.3)
        b = (cx * (R + 0.14), under(R + 0.14), cz * (R + 0.14))
        beam(m, a, b, 0.1, 'p_pole', ends=True)
        mid = _add(a, _mul(_sub(b, a), 0.5))
        beam(m, (cx * 0.22, runner_y, cz * 0.22), (mid[0], mid[1] - 0.05, mid[2]), 0.07, 'p_pole', ends=False)


def _lounger(m, lx):
    """One lounger at x = lx: a dark wood tray on four legs, a thick seat cushion to z 3.3, a
    raised backrest at -Z (its top at about 2.6) and two chunky armrests."""
    F, C = LOUNGER_FRAME, LOUNGER_CUSHION
    x0, x1 = lx - 1.0, lx + 1.0
    z0, z1 = -2.05, 3.4
    seat = 0.68  # the tray's top, under the cushion
    # The tray (the frame's sides) and its legs.
    m.box(x0, 0.3, z0, x1, seat, z1, F, chamfer=0.08, v_range=(0.2, 0.8))
    for x in (x0 + 0.12, x1 - 0.12):
        for z in (z0 + 0.14, z1 - 0.14):
            tapered_leg(m, x, z, 0.0, 0.3, 0.09, 0.11, F)
    # The seat cushion: top at the seat height, 1.0.
    ci = 0.12  # the cushion sits inside the frame's rim
    pillow(m, x0 + ci, seat, -0.95, x1 - ci, 1.0, z1 - 0.08, C, 0.09, chamfer=0.12, v_range=(0.3, 1.0))
    # The backrest: a thick cushion on a board, hinged at the seat's back edge, leaning back.
    tilt = BACK_TILT
    length = 1.95
    th = 0.3
    back = mc.Mesh('back')
    pillow(back, x0 + ci - lx, 0.0, 0.0, x1 - ci - lx, th, length, C, 0.09, chamfer=0.12, v_range=(0.3, 1.0))
    board = mc.Mesh('board')
    board.box(x0 + 0.05 - lx, -0.12, 0.0, x1 - 0.05 - lx, 0.0, length + 0.06, F, v_range=(0.3, 0.8))
    # Built lying flat (length along +Z, the cushion's face up); stand it up and lean it back.
    rot = (90.0 - tilt, 180.0, 0.0)
    hinge = (lx, 0.72, -0.8)
    m.add(back, rot=rot, offset=hinge)
    m.add(board, rot=rot, offset=hinge)
    # Armrests beside the backrest: a rail on a front post, a little proud of the cushions.
    for x in (x0, x1 - ci):
        m.box(x, 1.36, -1.5, x + ci, 1.5, 0.1, F, chamfer=0.03, v_range=(0.5, 1.0))
        m.box(x + 0.01, seat, -0.1, x + ci - 0.01, 1.36, 0.06, F, v_range=(0.3, 0.9))


def build_umbrella_set():
    m = mc.Mesh('Opaque')
    R = _canopy(m)
    _umbrella_frame(m, R)
    for lx in (-LOUNGER_X, LOUNGER_X):
        _lounger(m, lx)
    # Against the backrest's foot (its hinge at z -0.8), between the armrests: the sit pose is
    # upright, so a spot further forward left a gap behind the player (Checkpoint B).
    seats = [(-LOUNGER_X, 1.0, -0.35, 0.0), (LOUNGER_X, 1.0, -0.35, 0.0)]
    return {'Opaque': m, 'seats': seats, 'lights': []}


# ---------------------------------------------------------------------------------------------
# Grand piano (02 art): the classic plan (a long straight side at -X, the bentside curving in
# toward a round tail), a rim on three legs, the lid hinged on the straight side and propped
# open on a stick, the keyboard across the front (+Z) between cheek blocks, a music desk, a
# pedal lyre. Black lacquer (p_piano: its sheen sits near the top of the strip).
# ---------------------------------------------------------------------------------------------

PIANO = {
    'half_w': 2.2,  # 4.4 across (the gray-box)
    'front': 1.9,  # the case's front wall; the keyboard is in front of it, to z 2.9
    'tail': -2.9,
    'rim': (1.8, 3.0),  # the rim's foot and top
    'wall': 0.14,  # the rim's thickness
    'board_y': 2.55,  # the soundboard inside the rim
    'lid_open': 35.0,  # degrees
    'lid_front': 1.3,  # the main lid covers the case behind this line
    'key_y': 2.2,  # the keys' top
}


def piano_outline():
    """The case's plan outline (x, z) in outward order: up the straight side (-X) to the front,
    across it, down the treble cheek, the bentside curving in, the round tail."""
    P = PIANO
    hw, front, tail = P['half_w'], P['front'], P['tail']
    tail_x, tail_z = 0.15, -1.55  # where the bentside meets the tail's round
    pts = [(-hw, tail_z), (-hw, front), (hw, front)]
    pts += _bezier((hw, 1.45), (hw, 0.85), (tail_x, 0.55), (tail_x, tail_z), 14)
    cx, rx, rz = (tail_x - hw) / 2, (tail_x + hw) / 2, tail_z - tail
    for k in range(1, 14):
        th = math.pi * k / 14
        pts.append((cx + rx * math.cos(th), tail_z - rz * math.sin(th)))
    return pts


def _clip_front(poly, z_cut):
    """The outline with everything in front of z_cut cut off (for the main lid)."""
    out = []
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        if a[1] <= z_cut:
            out.append(a)
        if (a[1] - z_cut) * (b[1] - z_cut) < 0:
            t = (z_cut - a[1]) / (b[1] - a[1])
            out.append((a[0] + (b[0] - a[0]) * t, z_cut))
    return out


def build_piano():
    P = PIANO
    m = mc.Mesh('Opaque')
    hw = P['half_w']
    y0, y1 = P['rim']
    outline = piano_outline()
    inner = offset_outline(outline, P['wall'])
    # The rim: outer walls (the sheen line near the top), the top edge, inner walls, the
    # soundboard, the case bottom.
    loft(m, [lift(outline, y0), lift(outline, y1)], 'p_piano', [0.05, 0.93])
    loft(m, [lift(inner, P['board_y']), lift(inner, y1)], 'p_piano', [0.2, 0.6], flip=True)
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        pts = [(outline[i][0], y1, outline[i][1]), (inner[i][0], y1, inner[i][1]),
               (inner[j][0], y1, inner[j][1]), (outline[j][0], y1, outline[j][1])]
        oface(m, pts, [(0.0, mc.trim_v('p_piano', 0.8))] * 4, (0.0, 1.0, 0.0))
    cap(m, lift(inner, P['board_y']), 'p_wood', frac=0.55)
    cap(m, lift(outline, y0), 'p_piano', up=False, frac=0.1)
    # The front strip over the action (in front of the lid's line), and the music desk on it.
    lf = P['lid_front']
    strip_poly = mc.outward_rect(-hw + P['wall'], lf, hw - P['wall'], P['front'] - P['wall'])
    cap(m, lift(strip_poly, y1 - 0.02), 'p_piano', frac=0.6)
    desk = mc.Mesh('desk')
    desk.box(-1.3, 0.0, -0.05, 1.3, 0.78, 0.05, 'p_piano', v_range=(0.3, 0.85))
    desk.box(-1.3, 0.0, 0.0, 1.3, 0.08, 0.2, 'p_piano', v_range=(0.3, 0.85))  # the ledge
    m.add(desk, rot=(-14.0, 0.0, 0.0), offset=(0.0, y1 - 0.02, 1.55))
    # The main lid: hinged on the straight side, raised on the bentside.
    lid_poly = _clip_front(outline, lf)
    lid = mc.Mesh('lid')
    shifted = [(x + hw, z) for x, z in lid_poly]
    th = 0.08
    loft(lid, [lift(shifted, 0.0), lift(shifted, th)], 'p_piano', [0.3, 0.9])
    cap(lid, lift(shifted, th), 'p_piano', vfun=lambda x, y, z: 0.55 + 0.25 * x / (2 * hw))
    cap(lid, lift(shifted, 0.0), 'p_piano', up=False, frac=0.62)
    angle = P['lid_open']
    m.add(lid, rot=(0.0, 0.0, angle), offset=(-hw, y1, 0.0))
    # The lid stick: from the rim top on the bentside up to the lid's underside.
    sx, sz = 1.1, -0.05
    # The rim's x at z = sz on the bentside, a little inside.
    foot = (sx, y1, sz)
    for (ax, az), (bx, bz) in zip(outline, outline[1:]):
        if ax > 0 and (az - sz) * (bz - sz) <= 0 and az != bz:
            t = (sz - az) / (bz - az)
            foot = (ax + (bx - ax) * t - 0.12, y1, sz)
            break
    tip_x = foot[0] - 0.35
    tip_y = y1 + (tip_x + hw) * math.tan(math.radians(angle)) - 0.02
    beam(m, foot, (tip_x, tip_y, sz), 0.07, 'p_piano', v_range=(0.4, 0.8))
    # The keyboard: the key bed across the front, the keys between the cheek blocks, the
    # folded fallboard behind them.
    front, kz1 = P['front'], -P['tail']
    ky = P['key_y']
    bed_top = ky - 0.16
    m.box(-hw, 1.72, front - 0.05, hw, bed_top, kz1, 'p_piano', v_range=(0.2, 0.75))
    cheek = 0.26
    kx0, kx1 = -hw + cheek, hw - cheek
    kz0 = front + 0.42  # the keys' back edge (the fallboard covers the rest)
    kzf = kz1 - 0.06  # their front edge, just behind the key slip
    # The keys' top: p_keys along X (the black keys drawn on the far part), V over the depth.
    u0 = mc.trim_u('p_keys', 0.0)
    u1 = mc.trim_u('p_keys', kx1 - kx0)
    vf, vb = mc.trim_v('p_keys', 0.08), mc.trim_v('p_keys', 1.0)
    m.face([(kx0, ky, kzf), (kx1, ky, kzf), (kx1, ky, kz0), (kx0, ky, kz0)],
           [(u0, vf), (u1, vf), (u1, vb), (u0, vb)])
    m.face([(kx0, bed_top, kzf), (kx1, bed_top, kzf), (kx1, ky, kzf), (kx0, ky, kzf)],
           [(u0, mc.trim_v('p_keys', 0.02)), (u1, mc.trim_v('p_keys', 0.02)),
            (u1, mc.trim_v('p_keys', 0.12)), (u0, mc.trim_v('p_keys', 0.12))])
    # The fallboard, folded back: a black block with a sloped face behind the keys.
    fy0, fy1 = ky - 0.02, ky + 0.3
    pts = [(kx0, fy0, kz0), (kx1, fy0, kz0), (kx1, fy1, front - 0.02), (kx0, fy1, front - 0.02)]
    oface(m, pts, [(0.0, mc.trim_v('p_piano', 0.5)), (1.0, mc.trim_v('p_piano', 0.5)),
                   (1.0, mc.trim_v('p_piano', 0.85)), (0.0, mc.trim_v('p_piano', 0.85))], (0.0, 0.5, 1.0))
    # The cheek blocks: a chamfered block at each end, a little higher than the keys.
    for xa, xb in ((-hw, kx0), (kx1, hw)):
        pillow(m, xa, bed_top, front - 0.05, xb, ky + 0.28, kz1, 'p_piano', 0.06, v_range=(0.3, 0.76))
    # Three legs: two under the keyboard's ends, one under the tail.
    tail_leg = (-1.1, -2.05)
    for (lx, lz), top in (((-hw + 0.3, front + 0.35), 1.72), ((hw - 0.3, front + 0.35), 1.72),
                          (tail_leg, y0)):
        tapered_leg(m, lx, lz, 0.14, top - 0.16, 0.12, 0.18, 'p_piano', chamfer=0.05)
        m.box(lx - 0.22, top - 0.16, lz - 0.22, lx + 0.22, top, lz + 0.22, 'p_piano', chamfer=0.06,
              v_range=(0.4, 0.85))
        m.box(lx - 0.1, 0.0, lz - 0.1, lx + 0.1, 0.14, lz + 0.1, 'p_metal', v_range=(0.1, 0.6))
    # The pedal lyre under the middle of the key bed: two posts, a pedal box, three pedals.
    lz = front - 0.25
    for px in (-0.22, 0.22):
        m.box(px - 0.05, 0.3, lz - 0.05, px + 0.05, y0, lz + 0.05, 'p_piano', v_range=(0.3, 0.85))
    m.box(-0.4, 0.06, lz - 0.2, 0.4, 0.34, lz + 0.18, 'p_piano', chamfer=0.05, v_range=(0.2, 0.85))
    for px in (-0.2, 0.0, 0.2):
        m.box(px - 0.045, 0.12, lz + 0.18, px + 0.045, 0.17, lz + 0.42, 'p_frame', v_range=(0.6, 1.0))
    return {'Opaque': m, 'seats': [], 'lights': []}


def build_piano_bench():
    """A black bench, 2.4 x 1.0, its padded top at 1.4 (the pianist faces +Z, the keyboard)."""
    m = mc.Mesh('Opaque')
    pillow(m, -1.2, 1.2, -0.5, 1.2, 1.4, 0.5, 'p_white', 0.06, chamfer=0.08, v_range=(0.35, 1.0))
    m.box(-1.14, 0.98, -0.44, 1.14, 1.2, 0.44, 'p_piano', chamfer=0.05, v_range=(0.3, 0.88))
    for x in (-1.0, 1.0):
        for z in (-0.3, 0.3):
            tapered_leg(m, x, z, 0.0, 0.98, 0.055, 0.08, 'p_piano')
    return {'Opaque': m, 'seats': [(0.0, 1.4, 0.0, 0.0)], 'lights': []}


KINDS = {
    'Lantern': build_lantern,
    'LanternTall': build_lantern_tall,
    'GlobeLight': build_globe_light,
    'UmbrellaSet': build_umbrella_set,
    'Piano': build_piano,
    'PianoBench': build_piano_bench,
}
