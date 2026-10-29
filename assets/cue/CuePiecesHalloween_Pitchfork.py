"""The Pitchfork Cue (Halloween 2026, lane hw-map, 2026-10-28; concept mocks/v3/R2.png, the
designer's pick for the 500-Candy track slot, coordinator 19:40). Its own body (a `body` piece
that replaces the shared cue mesh). Only ever "Pitchfork Cue" (the designer: not "devil").
See CuePieces.py for the kit and CuePiecesHalloween_A.py for the body rules (`check_body`) this
body passes before it exports. Modelled in the cue's Blender frame: X the side, Y from the tip
(0) toward the butt (-7), Z up.

    pitchfork    a compact pitchfork AT THE TIP (the designer 2026-10-29: about half as wide,
                 flat, the middle prong is the tip): the middle prong, red and square-ish with a
                 flat barbed arrowhead whose point IS the cue's tip (d 0, nothing past it), is
                 part of the body and never fades; a bevelled gold yoke and the two outer prongs
                 (their points set back 0.32, 0.445 off the axis across the barbs) ride the Tines
                 joint and fade on the owner's own screen while aiming. Laid flat (face up), so
                 nothing reaches the cloth on a max-draw stroke. Behind the yoke the glossy
                 candy-apple red shaft starts with a gold ferrule, slim (0.82 of the shared cue's
                 width: the designer found the first two "too wide"); a low collar (gold, black,
                 gold) with two small slim black horns on top; a red tail coiling from under the
                 collar down the shaft (riding high on top), lifting off it in a small arrowhead
                 tip that sways; a black band with gold rims; the red grip with a painted black
                 band; a black butt cap with a gold ring

One painted atlas (vfx/pitchfork/pitchfork_atlas.png) for every part: the lathe's bands and
its lacquer along most of it (a sheen, a crisp near-white streak with a thinner one either
side, a rim light underneath; the gold and black bands bevelled at their edges; the tail's
shadow on the shaft round the coil), and three swatches (red, black, gold, each shaded round a
tube with rim lights, red on the black horns) in a band at the top that the horns, the tail,
the prongs, the yoke and the shaft's front ferrule are mapped onto. So the body is three parts:
Body, TailTip and Tines (renamed from the butt build's Fork, so an old template with new data
is a missing part and falls back to the plain cue instead of drawing a wrong fork). The atlas's
cream tip and front ferrule rows are unused since the fork moved (kept, so the atlas and its
id stay). A small roughness map (vfx/pitchfork/pitchfork_rough.png, the same zones) gives the
sun a crisp highlight on the lacquer; no Reflectance mirror (`UseRoughness`: build_cue_templates
applies it only when asked).

The flame flipbook (vfx/pitchfork/flame_4x4.png) is painted here too: an opaque cartoon flame,
red with a darker rim, going orange only at its tongues' tips (coordinator 19:40: red, not
orange; opaque, no additive mush on the bright floor).

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_Pitchfork.py -- pitchfork
    python3 assets/cue/CuePiecesHalloween_Pitchfork.py --flame      (the flipbook only, no Blender)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from CuePieces import piece, PIECES_DIR  # noqa: E402
from CuePiecesHalloween_A import envelope, check_body, _revolve, _finish, _rows  # noqa: E402
import CuePiecesHalloween_A as A  # noqa: E402

# The palette (R2's swatches): #111111 #5A0B0B #D81E1E #F2B632 #FFF1DC
RED = (216, 30, 30)
DARK_RED = (90, 11, 11)
BLACK = (22, 22, 24)
GOLD = (242, 182, 50)
CREAM = (255, 241, 220)
ORANGE = (255, 138, 31)      # the flames' tongue tips only
BASE = {'Red': RED, 'Black': BLACK, 'Gold': GOLD, 'Cream': CREAM}
# candy-apple lacquer (coordinator 20:4x: R2 is glossy, the lab read flat red plastic): a soft
# sheen, crisp near-white streaks and a rim light, painted per colour
SHEEN = {'Red': (255, 120, 110), 'Black': (95, 95, 105), 'Gold': (255, 226, 140), 'Cream': (255, 255, 250)}
STREAK = {'Red': (255, 236, 230), 'Black': (232, 232, 242), 'Gold': (255, 252, 226), 'Cream': (255, 255, 255)}
RIM = {'Red': (255, 104, 92), 'Black': (214, 48, 34), 'Gold': (255, 232, 160), 'Cream': (255, 255, 255)}

ATLAS = 'vfx/pitchfork/pitchfork_atlas.png'
ATLAS_W, ATLAS_H = 256, 1024    # a 512 x 512 atlas's pixels, laid long along the cue
LATHE_V = 0.9                   # the lathe takes v 0 (the tip) to this (V_STUDS from the tip)
V_STUDS = 7.05
SWATCH_V = (0.925, 0.995)       # the swatches' band (UV v)
SWATCH_U = {'Red': (0.02, 0.31), 'Black': (0.355, 0.645), 'Gold': (0.69, 0.98)}
ROUGH = 'vfx/pitchfork/pitchfork_rough.png'   # the same UVs, 64 x 256: glossy lacquer, a little less on the gold
ROUGHNESS = {'Red': 0.22, 'Black': 0.26, 'Gold': 0.34, 'Cream': 0.5}

# Slim (the designer 2026-10-28, after the refinement: "make pitchfork skinnier all around
# including the horns and the width of the cue, it's too wide"): the whole lathe is this share
# of the shared cue's envelope, under a named 'Slim' exception to the hand rule (the hands rest
# at most 0.03 off the grip).
SLIM = 0.82
# The fork at the tip (2026-10-29) adds three, for this body only: up to WideX studs from the tip
# the sideways width is free (the barbs, the outer prongs), and in the bridge hand zone only the
# Body's up/down thickness and centreline are held to the hand rule (the fading Tines may
# overlap the hand on other players' screens, as the Sword's blade does); and the first 0.3 studs
# may be TipAcross wide (the middle arrowhead, flat; the ball curves away from it, so it never
# meets the ball, while 0.12 would cut the arrowhead to a stub).
A.BODY_EXCEPTIONS['pitchfork'] = {'Slim': SLIM, 'WideX': 1.5, 'BridgeCore': ('Body',), 'TipAcross': 0.25}

# The lathe's raised bands: (d, extra over the slim envelope) polylines between flush rows,
# raised BAND_RISE of these (the bevel shapes kept). Outside the hand zones (2.1 to 4.4 and
# past 6.8) the side rule allows +0.08.
BAND_RISE = 0.6
COLLAR = ((2.10, 0.0), (2.105, 0.022), (2.112, 0.03), (2.176, 0.03), (2.181, 0.026), (2.187, 0.046),
          (2.195, 0.05), (2.405, 0.05), (2.413, 0.046), (2.419, 0.026), (2.424, 0.03), (2.488, 0.03),
          (2.495, 0.022), (2.50, 0.0))
LOW_BAND = ((4.20, 0.0), (4.205, 0.016), (4.21, 0.022), (4.241, 0.022), (4.245, 0.018), (4.251, 0.032),
            (4.257, 0.035), (4.343, 0.035), (4.349, 0.032), (4.355, 0.018), (4.359, 0.022), (4.388, 0.022),
            (4.394, 0.012), (4.398, 0.0))
BUTT_CAP = ((6.80, 0.0), (6.805, 0.03), (6.812, 0.05), (6.846, 0.05), (6.85, 0.058), (6.856, 0.068),
            (6.894, 0.068), (6.90, 0.058), (6.904, 0.05), (6.96, 0.05), (6.985, 0.035), (6.998, 0.012))
# The painted colours along the lathe (d from, d to, swatch); red elsewhere. The grip's black
# band is paint only (the hand rule keeps the grip flush).
PAINT = ((0.0, 0.30, 'Cream'), (0.30, 0.36, 'Gold'),
         (2.10, 2.18, 'Gold'), (2.18, 2.42, 'Black'), (2.42, 2.50, 'Gold'),
         (4.20, 4.248, 'Gold'), (4.248, 4.352, 'Black'), (4.352, 4.40, 'Gold'),
         (6.42, 6.45, 'Gold'), (6.45, 6.66, 'Black'), (6.66, 6.69, 'Gold'),
         (6.80, 6.848, 'Black'), (6.848, 6.902, 'Gold'), (6.902, 7.05, 'Black'))

# The horns: on the collar's black band, either side of the top
HORN_AT = 2.30               # studs from the tip
HORN_ANGLE = 30.0            # degrees off the top: the up rule's room is within 45, and a horn's
                             # flank reaches about 13 more
HORN_REACH = 0.15            # how far out from the collar (studs)
HORN_CURL = 0.09             # how far the tip curls toward the cue's tip (studs)
HORN_RADII = (0.037, 0.035, 0.031, 0.026, 0.02, 0.013, 0.007, 0.0)   # a slim crescent, base to tip

# The tail: a loose coil between the hands' zones, then a lifting tip on its own swaying joint
TAIL_FROM, TAIL_TO = 2.44, 3.62     # the coil, studs from the tip (it ends on top)
TAIL_TURNS = 1.75
# readable but slim (coordinator 20:4x: R2's tail is prominent; the designer 2026-10-28: thinner):
# the tube sinks into the shaft at its sides and bottom and rides out over the top
TAIL_R = 0.04                       # the tube's radius (it rides R + 0.014 on the sides)
TAIL_RIDE = (0.014, 0.035)          # the centre's offset over the slim envelope: everywhere, extra on top
TAIL_TIP = (0.26, 0.055, 0.3, 0.75)  # the lifting tip: its run along the cue, its rise, the arrowhead's length and scale

# The fork, at the tip (the designer 2026-10-29: "a compact fork at the TIP", about half the
# approved 2.08 span, flat, the middle prong is the tip; it was past the butt, 1.5 studs long).
# Its prongs spread along S = (cos t, 0, sin t), t = FORK_TILT from +X toward +Z: 180 lays it
# flat, face up (at 150 the lower outer tine sat 0.4 under the axis, into the cloth on a max-draw
# stroke, whose axis is only 0.097 over it). d is studs from the tip, as everywhere here.
FORK_TILT = 180.0
FORK_SPREAD = 0.31                  # the outer prongs' centres off the axis (studs); 0.445 across the barbs
PRONG_R = (0.05, 0.058)             # a prong's section: across its face (up), in its plane (sideways)
PRONG_SQUARE = 2.8                  # its superellipse power: a rounded, bevelled square that catches light
FORK_FROM = 1.22                    # the outer prongs leave the yoke here
FORK_BEND = 0.86                    # and turn parallel to the cue here
MIDDLE_TIP, OUTER_TIP = 0.0, 0.32   # the arrowheads' points: the middle one IS the cue's tip; the outer
                                    # ones set back, out of the tip zone, so the middle one strikes first
HEAD_LEN = (0.40, 0.34)             # the arrowheads' lengths: middle, outer
HEAD_SCALE = (0.8, 0.72)            # the arrowheads' width and thickness (HEAD and BARB are at 1): middle, outer
HEAD_THICK = 0.7                    # and their thickness again on top: flat, elegant blades
LATHE_FROM = 1.36                   # the shaft starts here, behind the yoke, with a gold ferrule
FERRULE = 0.07                      # the ferrule's length
HALF_SPAN_CAP = 0.46                # check_fork: nothing in the fork zone further off the axis sideways
CLOTH_DEPTH = 0.085                 # check_fork: nor deeper under the axis (a max-draw axis is 0.097 over the cloth)
FORK_ZONE = 1.6                     # the fork zone for those two checks (studs from the tip)
# an arrowhead's section along it (t from its neck, 0, to its point, 1): full width, full
# thickness (studs at scale 1); the point rounds off over its last 0.09
HEAD = ((0.0, 0.18, 0.152), (0.025, 0.25, 0.14), (0.06, 0.31, 0.128), (0.10, 0.335, 0.12),
        (0.25, 0.285, 0.108), (0.45, 0.215, 0.094), (0.68, 0.14, 0.078), (0.911, 0.075, 0.064),
        (0.9555, 0.065, 0.0554), (0.984, 0.043, 0.0367), (0.997, 0.0194, 0.0166), (1.0, 0.0, 0.0))
# its two barbs, swept back past the neck with rounded ends: (t along, studs across from the
# axis, half thickness, half width) at scale 1
BARB = ((0.16, 0.09, 0.045, 0.06), (0.07, 0.14, 0.04, 0.05), (-0.02, 0.17, 0.033, 0.036),
        (-0.09, 0.185, 0.026, 0.024), (-0.115, 0.188, 0.012, 0.011))
# the gold yoke where the prongs leave the shaft: from the shaft's side, two bevelled rims with a
# groove between, then a dome toward the tip the prongs leave from (d, radius at scale 1; the
# butt build's profile turned round). Flattened: its section is YOKE_SCALE of these sideways and
# YOKE_UP of that up and down (the cloth rule), an oval boss the outer prongs grow out of.
YOKE_SCALE = 0.62
YOKE_UP = 0.55
YOKE = ((1.375, 0.0), (1.37, 0.19), (1.364, 0.226), (1.356, 0.238), (1.332, 0.238), (1.326, 0.222),
        (1.316, 0.214), (1.306, 0.222), (1.30, 0.238), (1.276, 0.238), (1.266, 0.222), (1.24, 0.19),
        (1.21, 0.14), (1.188, 0.07), (1.18, 0.0))


def slim_envelope():
    """The lathe's radius at d: SLIM of the shared cue's envelope."""
    R = envelope()
    return lambda d: SLIM * R(d)


def _band_rows(R, band):
    return [(d, R(d) + extra * BAND_RISE) for d, extra in band]


def ferrule_rows():
    """The shaft's front: a gold ferrule closed toward the tip (the middle prong enters it),
    LATHE_FROM to LATHE_FROM + FERRULE, a little proud of the shaft; its own UVs (the gold
    swatch), so it is a separate run of rows from lathe_rows."""
    R = slim_envelope()
    d0, d1 = LATHE_FROM, LATHE_FROM + FERRULE
    return [(d0, 0.0), (d0 + 0.004, R(d0) * 0.75), (d0 + 0.012, R(d0) + 0.01), (d1 - 0.006, R(d1) + 0.01),
            (d1, R(d1))]


def lathe_rows():
    """The lathe's (d, r) rows from the ferrule's back to the butt's closed end."""
    R = slim_envelope()
    rows = _rows(LATHE_FROM + FERRULE, 2.10, R, 0.2)[:-1]
    rows += _band_rows(R, COLLAR)
    rows += _rows(2.50, 4.20, R, 0.2)[1:-1]
    rows += _band_rows(R, LOW_BAND)
    rows += _rows(4.40, 6.80, R, 0.2)[:-1]
    rows += _band_rows(R, BUTT_CAP)
    rows += [(7.004, 0.11), (7.008, 0.0)]
    return rows


def _coil_angle(d):
    """The coil's angle round the cue at d (0 on top, toward +X positive, as the lathe's share x
    2 pi): 1.75 loose turns ending on top; the turning eases off over the last fifth, so the tail
    lies along the top where its tip lifts off (no kink)."""
    u = min(1.0, max(0.0, (d - TAIL_FROM) / (TAIL_TO - TAIL_FROM)))
    left = (1 - u) ** 2 / 0.4 if u >= 0.8 else 0.9 - u
    return -2 * math.pi * TAIL_TURNS * left / 0.9


def _coil_ride(a):
    """How far the coil's centre rides over the envelope at angle a: TAIL_RIDE[0] where the side
    rule holds (more than 45 degrees off the top), up to the sum on top."""
    return TAIL_RIDE[0] + TAIL_RIDE[1] * max(0.0, (math.cos(a) - math.sqrt(0.5)) / (1 - math.sqrt(0.5)))


def _swatch_uv(name, share, along):
    u0, u1 = SWATCH_U[name]
    m = 0.06 * (u1 - u0)
    return (u0 + m + (u1 - u0 - 2 * m) * share, SWATCH_V[0] + (SWATCH_V[1] - SWATCH_V[0]) * (0.08 + 0.84 * along))


def _tube(bm, uvl, pts, radii, up, swatch, along=None, segs=10, caps=(True, True), square=2.0):
    """A tube through `pts` (Vectors) with a radius per point (r, or (r across up, r beside)),
    its section turned so share 0 (the swatch's painted highlight) faces up(i) (a Vector made
    perpendicular to the tangent), mapped onto `swatch` (u round it, v by along(i) 0..1).
    `square` above 2 makes the section a superellipse: flat faces and rounded bevels."""
    def sq(c):
        return math.copysign(abs(c) ** (2.0 / square), c)
    from mathutils import Vector
    n = len(pts)
    along = along or (lambda i: i / max(1, n - 1))
    rings = []
    for i in range(n):
        t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        u = Vector(up(i))
        u = (u - t * t.dot(u)).normalized()
        s = t.cross(u)
        r = radii[i]
        ru, rs = (r, r) if not isinstance(r, (tuple, list)) else r
        if ru <= 1e-6 and rs <= 1e-6:
            rings.append([bm.verts.new(pts[i])])
            continue
        rings.append([bm.verts.new(pts[i] + u * (sq(math.cos(2 * math.pi * k / segs)) * ru)
                                   + s * (sq(math.sin(2 * math.pi * k / segs)) * rs)) for k in range(segs)])

    def put(f, coords):
        for lp, (share, al) in zip(f.loops, coords):
            lp[uvl].uv = _swatch_uv(swatch, share, al)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        va, vb = along(i), along(i + 1)
        if len(a) == 1 and len(b) == 1:
            continue
        for k in range(segs):
            k1 = (k + 1) % segs
            s0, s1 = k / segs, (k + 1) / segs
            if len(a) == 1:
                put(bm.faces.new((a[0], b[k1], b[k])), ((s0 + 0.5 / segs, va), (s1, vb), (s0, vb)))
            elif len(b) == 1:
                put(bm.faces.new((a[k], a[k1], b[0])), ((s0, va), (s1, va), (s0 + 0.5 / segs, vb)))
            else:
                put(bm.faces.new((a[k], a[k1], b[k1], b[k])), ((s0, va), (s1, va), (s1, vb), (s0, vb)))
    for ring, end, rev in ((rings[0], caps[0], True), (rings[-1], caps[1], False)):
        if not end or len(ring) == 1:
            continue
        c = bm.verts.new(sum((v.co for v in ring), Vector()) / len(ring))
        al = along(0) if rev else along(n - 1)
        for k in range(segs):
            q = (ring[k], ring[(k + 1) % segs], c)
            put(bm.faces.new(q[::-1] if rev else q), [(0.5, al)] * 3)
    return rings


def _head(bm, uvl, base, axis, across, face, length, scale=1.0, thick=1.0, segs=14, swatch='Red'):
    """An arrowhead from `base` along `axis`, `length` long: HEAD's lens-shaped sections (width
    along `across`, thickness along `face`, the painted highlight's side) to a rounded point, and
    BARB's two barbs swept back past the neck (R2's pitchfork tips), all scaled by `scale`, their
    thickness by `thick` again."""
    from mathutils import Vector
    axis, across, face = Vector(axis).normalized(), Vector(across).normalized(), Vector(face).normalized()
    # the section's second axis is axis x face, which is `across` (or its reverse: the same ellipse)
    assert abs(abs(axis.cross(face).dot(across)) - 1.0) < 1e-3, 'an arrowhead\'s across is not axis x face'
    base = Vector(base)
    pts = [base + axis * (t * length) for t, _, _ in HEAD]
    radii = [(th * scale * thick / 2, w * scale / 2) for _, w, th in HEAD]
    _tube(bm, uvl, pts, radii, lambda i: face, swatch, along=lambda i: HEAD[i][0], segs=segs, caps=(True, False))
    for sgn in (-1, 1):
        bpts = [base + axis * (t * length) + across * (sgn * w * scale) for t, w, _, _ in BARB]
        _tube(bm, uvl, bpts, [(ru * scale * thick, rs * scale) for _, _, ru, rs in BARB], lambda i: face, swatch,
              along=lambda i: 0.2, segs=8)


def _fork_frame():
    from mathutils import Vector
    a = math.radians(FORK_TILT)
    S = Vector((math.cos(a), 0.0, math.sin(a)))       # the prongs' spread
    N = Vector((math.sin(a), 0.0, -math.cos(a)))      # the fork's face (toward the card and a back's camera)
    return S, N


def _fork_point(s, d):
    from mathutils import Vector
    S, _ = _fork_frame()
    return S * s + Vector((0.0, -d, 0.0))


@piece
def pitchfork(k):
    """The Pitchfork Cue's body (concept R2): see the module docstring."""
    import bmesh
    from mathutils import Vector
    R = slim_envelope()
    # no Reflectance: it mirrors the violet Night sky (the Bone read lavender, lab 2026-10-28)
    k.material('Pitchfork', 'SmoothPlastic', '#FFFFFF', Reflectance=0.0,
               SurfaceAppearance={'ColorMap': pitchfork_atlas(), 'RoughnessMap': pitchfork_roughness(),
                                     'UseRoughness': True})

    # --- the body: the middle prong (the tip), the lathe, the horns and the tail's coil -----------
    k.joint('Body', pivot=(0, -3.5, 0))
    bm = bmesh.new()
    _revolve(bm, lathe_rows(), 24, uv=lambda d, share: (share, d / V_STUDS * LATHE_V))
    uvl = bm.loops.layers.uv['UVMap']
    # the shaft's gold ferrule, closed toward the tip, where the middle prong enters it
    fr = ferrule_rows()
    _tube(bm, uvl, [Vector((0.0, -d, 0.0)) for d, _ in fr], [r for _, r in fr], lambda i: (0.0, 0.0, 1.0), 'Gold',
          along=lambda i: (fr[i][0] - fr[0][0]) / FERRULE, segs=24, caps=(False, False))
    # the middle prong, straight from inside the ferrule to its arrowhead, whose point is the
    # cue's tip (d 0 exactly: the head's last section is a point at base + its length)
    S, N = _fork_frame()
    A = Vector((0.0, 1.0, 0.0))     # the arrowheads point toward the tip
    neck = MIDDLE_TIP + HEAD_LEN[0]
    straight = [_fork_point(0.0, LATHE_FROM + 0.03 + (neck - 0.02 - LATHE_FROM - 0.03) * i / 6) for i in range(7)]
    _tube(bm, uvl, straight, [PRONG_R] * 7, lambda i: N, 'Red', segs=16, caps=(True, False), square=PRONG_SQUARE)
    _head(bm, uvl, _fork_point(0.0, neck), A, S, N, HEAD_LEN[0], scale=HEAD_SCALE[0], thick=HEAD_THICK)
    # two small curved black horns on the collar, either side of the top, curling toward the tip
    for side in (-1, 1):
        b = math.radians(HORN_ANGLE) * side
        o = Vector((math.sin(b), 0.0, math.cos(b)))
        root = R(HORN_AT) + 0.012         # sunk into the collar (R + 0.03)
        ts = [i / 7 for i in range(8)]
        pts = [o * (root + HORN_REACH * t ** 0.9) + Vector((0.0, -HORN_AT + HORN_CURL * t * t, 0.0)) for t in ts]
        _tube(bm, uvl, pts, HORN_RADII, lambda i: (0.0, 0.35, 1.0), 'Black', along=lambda i: ts[i], segs=10)
    # the coil: from under the collar's lower ring, 1.75 loose turns, ending on top (_coil_angle),
    # thick, riding out over the top (_coil_ride)
    steps = 56
    coil = []
    for i in range(steps + 1):
        d = TAIL_FROM + (TAIL_TO - TAIL_FROM) * i / steps
        a = _coil_angle(d)
        rho = R(d) + _coil_ride(a)
        coil.append((d, a, Vector((rho * math.sin(a), -d, rho * math.cos(a)))))
    radii = [min(TAIL_R, 0.026 + (TAIL_R - 0.026) * min(1.0, (d - TAIL_FROM) / 0.12)) for d, _, _ in coil]
    _tube(bm, uvl, [p for _, _, p in coil], radii, lambda i: (math.sin(coil[i][1]), 0.0, math.cos(coil[i][1])),
          'Red', segs=12)
    _finish(bm)
    k.add('Body', k.mesh_object('PitchforkBody', bm, ['Pitchfork']))

    # --- the tail's tip: it lifts off the top and ends in an arrowhead, swaying --------------------
    d0 = TAIL_TO
    run, rise, head_len, head_scale = TAIL_TIP
    ride = _coil_ride(0.0)
    pivot = Vector((0.0, -d0, R(d0) + ride))
    k.joint('TailTip', pivot=tuple(pivot), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 14.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 5.0, 'Period': 2.3, 'Phase': 60}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    lift = []
    for i in range(9):
        t = i / 8
        d = d0 + run * t
        # it leaves the coil flat (no kink at the joint) and rises to about 27 degrees, so the
        # arrowhead points back along the cue and up (the up rule's +0.25 ends at 4.4)
        lift.append(Vector((-0.03 * t * t, -d, R(d) + ride + rise * t * t * (2 - t))))
    _tube(bm, uvl, lift, [TAIL_R - 0.006 * i / 8 for i in range(9)], lambda i: (-0.1, 0.0, 0.995), 'Red',
          segs=12, caps=(True, False))
    tip_dir = (lift[-1] - lift[-3]).normalized()
    face = Vector((-0.1, 0.0, 0.995))  # nearly flat: tipped toward the stand side, the barbs stay in the up cone
    face = (face - tip_dir * tip_dir.dot(face)).normalized()
    _head(bm, uvl, lift[-1] - tip_dir * 0.01, tip_dir, tip_dir.cross(face), face, head_len, scale=head_scale, segs=12)
    _finish(bm)
    k.add('TailTip', k.mesh_object('TailTip', bm, ['Pitchfork']))

    # --- the yoke and the outer prongs at the tip: they fade on the owner's screen while aiming ----
    # (the middle prong is the body's: the owner aims a cue that still ends on its point)
    k.joint('Tines', pivot=(0.0, -FORK_FROM, 0.0), aim='fade')
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    # the gold yoke, an oval boss round the middle prong in front of the ferrule
    yk = [Vector((0.0, -d, 0.0)) for d, _ in YOKE]
    _tube(bm, uvl, yk, [(r * YOKE_SCALE * YOKE_UP, r * YOKE_SCALE) for _, r in YOKE], lambda i: N, 'Gold', segs=24,
          caps=(False, False))
    # the outer prongs: a round U out of the yoke (a quadratic curve leaving sideways, arriving
    # parallel to the cue), then straight on to their arrowheads, which point toward the tip
    for side in (-1, 1):
        p0, p1, p2 = (0.0, FORK_FROM), (side * FORK_SPREAD, FORK_FROM), (side * FORK_SPREAD, FORK_BEND)
        pts = []
        for i in range(15):
            t = i / 14
            s = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            d = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
            pts.append(_fork_point(s, d))
        neck = OUTER_TIP + HEAD_LEN[1]
        pts += [_fork_point(side * FORK_SPREAD, FORK_BEND + (neck - 0.02 - FORK_BEND) * i / 4) for i in range(1, 5)]
        _tube(bm, uvl, pts, [PRONG_R] * len(pts), lambda i: N, 'Red', segs=16, caps=(True, False), square=PRONG_SQUARE)
        _head(bm, uvl, _fork_point(side * FORK_SPREAD, neck), A, S, N, HEAD_LEN[1], scale=HEAD_SCALE[1],
              thick=HEAD_THICK)
    _finish(bm)
    k.add('Tines', k.mesh_object('Tines', bm, ['Pitchfork']))
    check_body(k)
    check_fork(k)


def check_fork(k):
    """The fork's own rules, on top of the body check: the middle prong's point is exactly the
    cue's tip and nothing passes it; in the fork zone (the first FORK_ZONE studs) nothing sits
    further than HALF_SPAN_CAP off the axis sideways or deeper than CLOTH_DEPTH under it (flat,
    so no tine reaches the cloth on a max-draw stroke). Prints the fork's span and depth."""
    front, span, depth, at_tip = math.inf, 0.0, 0.0, False
    for jname, j in k.joints.items():
        for ob in j['objects']:
            M = ob.matrix_world
            for v in ob.data.vertices:
                p = M @ v.co
                d = -p.y
                front = min(front, d)
                if jname == 'Body' and abs(d - MIDDLE_TIP) < 1e-5 and math.hypot(p.x, p.z) < 1e-5:
                    at_tip = True
                if d < FORK_ZONE:
                    span = max(span, abs(p.x))
                    depth = max(depth, -p.z)
    assert front >= -1e-5, 'a part passes the tip by %.4f' % -front
    assert at_tip, "the middle prong's point is not at the cue's tip"
    assert span <= HALF_SPAN_CAP + 1e-6, 'the fork reaches %.3f off the axis (at most %.2f)' % (span, HALF_SPAN_CAP)
    assert depth <= CLOTH_DEPTH + 1e-6, 'the fork reaches %.3f under the axis (at most %.3f)' % (depth, CLOTH_DEPTH)
    print('CUE pitchfork: the fork at the tip, %.3f off the axis (%.2f across), %.3f under it; nothing past the tip'
          % (span, 2 * span, depth))


# =============================================================================================
# The painted maps (numpy; the atlas runs inside Blender, the flipbook anywhere)
# =============================================================================================

def _lerp(a, b, t):
    import numpy as np
    return np.array(a, np.float32) * (1 - t[..., None]) + np.array(b, np.float32) * t[..., None]


def _shade(name, share, flanks=False):
    """A colour round a tube or the lathe (share 0 and 1 face the painted light): lit from that
    side, a soft sheen, a crisp near-white streak with a thinner one either side (lacquer), a
    faint rim light underneath, and with `flanks` (the swatches' tubes) a rim light down both
    sides, red on the black horns."""
    import numpy as np
    base = np.array(BASE[name], np.float32)
    c = np.cos(2 * np.pi * share)
    k = (0.66 + 0.34 * c) if name == 'Gold' else (0.8 + 0.2 * c)
    col = base[None, None] * k[..., None]
    dist = np.minimum(share % 1.0, 1.0 - share % 1.0)          # 0 at the light, 0.5 opposite
    col = _lerp(col, SHEEN[name], np.exp(-(dist / 0.1) ** 2) * 0.22)
    # wide enough to read at 7 studs (a hairline streak vanished on the floor)
    streak = np.exp(-(dist / 0.035) ** 2) * 0.8 + np.exp(-((dist - 0.12) / 0.022) ** 2) * 0.45
    col = _lerp(col, STREAK[name], np.clip(streak, 0, 1))
    rim = np.exp(-((0.5 - dist) / 0.05) ** 2) * 0.25
    if flanks:
        rim = rim + np.exp(-((dist - 0.25) / 0.035) ** 2) * (0.55 if name == 'Black' else 0.3)
    return _lerp(col, RIM[name], np.clip(rim, 0, 1))


def _zones(U, V):
    """The colour zone (a BASE name) of every atlas pixel: the lathe's PAINT along it, red
    elsewhere on the lathe, the swatches above."""
    import numpy as np
    d = V / LATHE_V * V_STUDS
    names = np.full(U.shape, 'Red', dtype=object)
    for lo, hi, name in PAINT:
        names[(d >= lo) & (d < hi)] = name
    top = V >= LATHE_V + 0.01
    for name, (u0, u1) in SWATCH_U.items():
        lo = u0 - (0.02 if u0 > 0.02 else u0)
        hi = u1 + 0.02 if u1 < 0.98 else 1.0
        names[(U >= lo) & (U < hi) & top] = name
    return names


def pitchfork_atlas():
    """vfx/pitchfork/pitchfork_atlas.png (ATLAS_W x ATLAS_H). The lathe: u round the cue (0 on
    top, +Z), v from the tip (0) to V_STUDS (LATHE_V); PNG row 0 is UV v = 1. Every band in its
    colour, glossed (_shade), the gold and black bands bevelled at their edges (dark, then a
    bright line just inside), dark-red hairlines where a band meets the red, and the tail's
    shadow painted on the shaft round the coil. Above it the swatches band: red, black and gold
    shaded round a tube with rim lights, the black lighter toward v's top (a horn's tip)."""
    import numpy as np
    import cue_common as cc
    path = os.path.join(os.path.dirname(PIECES_DIR), ATLAS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    W, H = ATLAS_W, ATLAS_H
    U, V = np.meshgrid((np.arange(W) + 0.5) / W, 1.0 - (np.arange(H) + 0.5) / H)
    d = V / LATHE_V * V_STUDS

    def smooth(a, b, v):
        t = np.clip((v - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    img = _shade('Red', U)
    for lo, hi, name in PAINT:
        band = (d >= lo) & (d < hi)
        col = _shade(name, U)
        if name in ('Gold', 'Black'):
            e = np.minimum(d - lo, hi - d)
            col = col * (0.62 + 0.38 * smooth(0.0, 0.006, e))[..., None]
            col = _lerp(col, STREAK[name], np.exp(-((e - 0.0095) / 0.003) ** 2) * (0.5 if name == 'Gold' else 0.3))
        img = np.where(band[..., None], col, img)
    # hairlines where a band meets the red shaft (the concept's crisp cartoon edges)
    edges = sorted({lo for lo, _, _ in PAINT} | {hi for _, hi, _ in PAINT})
    for e in edges:
        line = np.abs(d - e) < 0.007
        img = np.where(line[..., None], img * 0.55 + np.array(DARK_RED, np.float32) * 0.45, img)
    # the tail's shadow on the shaft: dark either side of the coil, so the tail reads on the red
    rows = d[:, 0]
    at = np.array([_coil_angle(x) for x in rows])
    gap = (2 * np.pi * U - at[:, None] + np.pi) % (2 * np.pi) - np.pi
    on = ((rows >= TAIL_FROM - 0.02) & (rows <= TAIL_TO)).astype(np.float32)
    after = np.clip(1 - (rows - TAIL_TO) / 0.14, 0, 1) * (rows > TAIL_TO)    # under the lifting tip
    occ = np.exp(-(gap / 0.7) ** 2) * np.maximum(on, after)[:, None]
    img = img * (1 - 0.45 * occ)[..., None] + np.array(DARK_RED, np.float32) * (0.2 * occ)[..., None]
    rng = np.random.default_rng(7)
    img *= (0.985 + 0.015 * rng.random(U.shape))[..., None]
    # the swatches' band, painted wider than the UVs reach so filtering never meets the lathe
    top = V >= LATHE_V + 0.01
    for name, (u0, u1) in SWATCH_U.items():
        lo = u0 - (0.02 if u0 > 0.02 else u0)
        hi = u1 + 0.02 if u1 < 0.98 else 1.0
        cols = (U >= lo) & (U < hi) & top
        m = 0.06 * (u1 - u0)
        share = np.clip((U - u0 - m) / (u1 - u0 - 2 * m), 0, 1)
        col = _shade(name, share, flanks=True)
        if name == 'Black':
            along = np.clip((V - SWATCH_V[0]) / (SWATCH_V[1] - SWATCH_V[0]), 0, 1)
            col = col + (np.array((42, 40, 44), np.float32) * along[..., None] ** 2)
        img = np.where(cols[..., None], col, img)
    cc.write_png(path, np.clip(img, 0, 255).astype(np.uint8))
    return ATLAS


def pitchfork_roughness(w=64, h=256):
    """vfx/pitchfork/pitchfork_rough.png: the atlas's zones at a quarter of its size, each its
    ROUGHNESS (grey = roughness x 255): a glossy lacquer the sun can draw a highlight on, no
    Reflectance mirror."""
    import numpy as np
    import cue_common as cc
    path = os.path.join(os.path.dirname(PIECES_DIR), ROUGH)
    U, V = np.meshgrid((np.arange(w) + 0.5) / w, 1.0 - (np.arange(h) + 0.5) / h)
    names = _zones(U, V)
    grey = np.vectorize(lambda n: ROUGHNESS[n] * 255.0)(names).astype(np.float32)
    cc.write_png(path, np.repeat(grey[..., None], 3, axis=2).astype(np.uint8))
    return ROUGH


FLAME = 'vfx/pitchfork/flame_4x4.png'


def flame_flipbook(px=128, grid=4):
    """vfx/pitchfork/flame_4x4.png: 16 frames of a cartoon flame over a particle's life (it grows,
    flickers, shrinks). Opaque inside a 1.5-px soft edge: red, a darker red rim, a brighter red
    core low down, and orange only at the tongues' tips."""
    import numpy as np
    import cue_common as cc
    path = os.path.join(os.path.dirname(PIECES_DIR), FLAME)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    n = grid * grid
    sheet = np.zeros((px * grid, px * grid, 4), np.float32)
    ys, xs = np.mgrid[0:px, 0:px]
    x = (xs + 0.5) / px - 0.5                    # -0.5 .. 0.5 across
    y = 1 - (ys + 0.5) / px                      # 0 at the bottom, 1 at the top
    unit = 1.0 / px                              # one pixel

    def smooth(a, b, v):
        t = np.clip((v - a) / (b - a), 0, 1)
        return t * t * (3 - 2 * t)
    for f in range(n):
        t = f / (n - 1)
        sc = (0.55 + 0.45 * float(smooth(0.0, 0.22, t))) * (1 - 0.55 * float(smooth(0.62, 1.0, t)))
        ph = 2.6 * t
        cy = 0.05 + 0.19 * sc                    # the bulb's centre
        rb = 0.2 * sc                            # its radius
        dist = np.hypot(x, (y - cy) * 1.05) - rb
        tip = np.zeros_like(x)
        tongues = ((0.0, 0.0, 0.7, rb, 0.0), (-0.09, 0.13, 0.46, 0.58 * rb, 0.31), (0.085, 0.12, 0.4, 0.55 * rb, 0.62))
        for x0, lean, length, w0, phase in tongues:
            L = length * sc
            h = (y - cy) / L                     # 0 at the bulb's centre, 1 at the tongue's tip
            sway = 0.06 * sc * np.sin(2 * np.pi * (0.9 * h - ph - phase)) * np.clip(h, 0, 1) ** 1.2
            xc = x0 * sc + lean * sc * np.clip(h, 0, 1) ** 1.3 * np.sign(x0 if x0 else 1.0) + sway
            hw = w0 * np.clip(1 - h, 0, 1) ** 1.15
            inside = (h >= 0) & (h <= 1)
            dt = np.where(inside, np.abs(x - xc) - hw, 9.0)
            tip = np.where((dt < 0) & (h > tip), np.clip(h, 0, 1), tip)
            dist = np.minimum(dist, dt)
        alpha = np.clip(0.5 - dist / (1.5 * unit), 0, 1)
        # colours: red; a warmer core low down; a dark-red rim so the shape reads on the red
        # prongs; orange over each tongue's top third, yellow-orange at the very tips (the lobby's
        # colour grade flattens a plain red flame into a blob, lab 2026-10-28)
        core = np.clip(1 - np.hypot(x / (0.5 * rb + 1e-6), (y - cy * 0.95) / (0.8 * rb + 1e-6)), 0, 1)
        col = _lerp(RED, (245, 85, 45), core ** 0.7)
        col = _lerp(col, ORANGE, smooth(0.45, 0.8, tip))
        col = _lerp(col, (255, 196, 80), smooth(0.82, 0.97, tip))
        rim = np.clip(1 + dist / (3.5 * unit), 0, 1) * (dist < 0)
        col = _lerp(col, (104, 8, 8), 0.65 * rim)
        r0, c0 = (f // grid) * px, (f % grid) * px
        sheet[r0:r0 + px, c0:c0 + px, :3] = col
        sheet[r0:r0 + px, c0:c0 + px, 3] = alpha * 255
    cc.write_png(path, np.clip(sheet, 0, 255).astype(np.uint8))
    print('CUE pitchfork flame flipbook written', FLAME)
    return FLAME


# Part keys patched into piece.json after the export (tools/cue_pieces_glb.py "Smooth": shared
# vertex normals; the packer writes flat faces otherwise and the lathe and prongs read faceted).
PART_KEYS = {'pitchfork': {name: {'Smooth': True} for name in ('Body_Pitchfork', 'TailTip_Pitchfork', 'Tines_Pitchfork')}}


def _patch_parts(pid):
    keys = PART_KEYS.get(pid, {})
    if not keys:
        return
    path = os.path.join(PIECES_DIR, pid, 'piece.json')
    spec = json.load(open(path))
    found = {part['Name'] for part in spec['Parts']}
    missing = [n for n in keys if n not in found]
    assert not missing, '%s: no parts %s' % (pid, missing)
    for part in spec['Parts']:
        part.update(keys.get(part['Name'], {}))
    with open(path, 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    print('CUE part keys %s: %s' % (pid, ', '.join(sorted(keys))))


def _cli():
    """Blender ... --python assets/cue/CuePiecesHalloween_Pitchfork.py -- pitchfork: build the body
    (no preview tiles), patch its part keys and paint the flame flipbook. `--flame` alone (plain
    python3) paints only the flipbook."""
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if '--flame' in argv:
        flame_flipbook()
        return
    from CuePieces import build
    for pid in (a for a in argv if not a.startswith('--')):
        build(pid, render_preview=False)
        _patch_parts(pid)
    flame_flipbook()


if __name__ == '__main__':
    _cli()
