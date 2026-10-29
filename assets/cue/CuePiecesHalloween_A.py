"""The Halloween 2026 cues of lane Cues A (2026-10-28; docs/prompts/HW_CUES_A_PROMPT.md): the
Candy Corn Cue and the Jack-o'-Lantern Cue, each drawn by its own model (a `body` piece that
replaces the shared cue mesh), plus Jack's pocket piece. See CuePieces.py for the kit and the
export; CuePiecesHalloween_B.py holds the Black Cat, Spider and Witch's Broom. Modelled in the
cue's Blender frame: X the side, Y from the tip (0) toward the butt (-7), Z up; the pocket
finisher in the pocket frame (origin at the mouth, Z up).

    candy_corn              the body: kernel tip cap, cream shaft, barber-pole wrap, orange
                            forearm, yellow handle, candy-corn bulb (brief 2.7)
    jack_o_lantern          the body: stem tip, ribbed orange shaft, spiralling vine with
                            leaves, wood collars with glowing slits, carved pumpkin butt (2.8)
    jack_o_lantern_pocket   the laughing jack-o'-lantern that rises out of the pocket (2.8)

Every body passes `check_body` before it exports (brief 2.6): the tip ends at the pivot and
stays thin, the hand zones keep the envelope, the rest stays inside the clearances, and
nothing but an Aim-fade joint reaches further than 0.3 studs past the butt.
"""
import math

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from CuePieces import piece, apply_modifier, assign_by_region, sweep, PIECES_DIR

# The modelling rules (brief 2.6; the same numbers as Cues B's brief 2.2 and Config.CueSkins.Bodies).
LENGTH = 7.0                 # Config.Cue.CueLengthStuds
TIP_SLACK = 0.01             # a body must reach this close to the pivot (Bodies.TipSlackStuds)
TIP_ACROSS = 0.12            # at most this across for the first TIP_LEN studs (the ball's radius is 0.18)
TIP_LEN = 0.3
HAND_ZONES = ((0.3, 2.1), (4.4, 6.75))   # bridge hand, grip hand: envelope +-HAND_TOL, centred
HAND_TOL = 0.02
SIDE_EXTRA = 0.08            # up to 6.75: at most envelope + this sideways and downward
UP_EXTRA = 0.25              # +Z between the hand zones (2.1 to 4.4): leaves, rings, kernels
BUTT_FROM, BUTT_EXTRA = 6.75, 0.2   # from 6.75 to the butt: the bulb, the pumpkin
PAST_BUTT = 0.3              # past the butt (Bodies.PastButtStuds)
AIM_OVERHANG = 1.5           # an Aim-fade joint's reach past the butt (Bodies.MaxOverhangStuds)
MAX_PARTS, MAX_TRIS = 8, 10000
# Named relaxations of the rules above, one body at a time (coordinator 19:2x 2026-10-28: the
# Halloween Sword's wide blade; a named exception per body, never a looser global rule):
#   'WideX': up to this many studs the sideways width may pass envelope + SIDE_EXTRA (the
#            downward reach and the +Z allowance still hold);
#   'BridgeCore': in the bridge hand zone the hand rule applies in Z (up/down) and on the
#            centreline to these joints only (the solid core); other joints (an Aim-fade flame
#            edge) may overlap the hand.
#   'GuardInGripZone': (d0, d1) at the front of the grip hand zone where a sword's guard may
#            sit: the hand rules are off there and the +Z allowance runs to d1 (coordinator
#            20:4x: the hilt reads as a stick when the guard stops at 4.4; the grip hand's
#            full wind-up was measured in Studio to reach 4.92 from the tip, so 4.9 was the
#            back edge clear of the fingers; designer 20:5x: the handle is way too big, the
#            guard goes to 5.0-5.55 just in front of the hand at rest, and the hand passing
#            through it for an instant at a full-power wind-up is accepted).
#   'Slim': a factor under 1 for a body slimmer than the shared cue (the designer 2026-10-28:
#            the Pitchfork "too wide"): the hand rule holds against this share of the
#            envelope (+-HAND_TOL), so the hands rest at most (1 - Slim) x 0.18 off the grip.
#   'SlimGrip': r, a handle slimmer still: in the grip hand zone the radius may come down to r
#            (designer 20:5x: a sword handle, thinner than the cue is fine). Both may be set;
#            the upper bound is Slim's, the lower the smaller of the two.
BODY_EXCEPTIONS = {}   # the hard budget (the data tool stops over it); aim at 6 and 6,000


def envelope():
    """The cue's radius at distance d from the tip (Shape.json's envelope, CueShape.radiusAt)."""
    import cue_common as cc
    return cc.Envelope(cc.load_shape()[0])


def _bins(kit, step=0.1):
    """Every vertex of the kit (world, Blender cue frame) by 0.1-stud bin of its distance from
    the tip: bin -> [(d, x, z, joint, aim)]."""
    out = {}
    for jname, j in kit.joints.items():
        aim = bool(j.get('Aim'))
        for ob in j['objects']:
            M = ob.matrix_world
            for v in ob.data.vertices:
                p = M @ v.co
                d = -p.y
                out.setdefault(int(math.floor(d / step)), []).append((d, p.x, p.z, jname, aim))
    return out


def check_body(kit, step=0.1):
    """Assert the body obeys brief 2.6, sampling every `step` studs; raise with the first few
    problems so a bad body never exports. Checks: a vertex at the pivot (the tip reaches), the
    tip thin, the hand zones at the envelope and centred, side and down clearance up to 6.75,
    the +Z allowance between the hands, the butt allowance, the past-butt limits (Aim joints
    excepted up to AIM_OVERHANG), and nothing before the tip."""
    R = envelope()
    bins = _bins(kit, step)
    problems = []
    wide_cx = []   # a WideX body's sideways centre, bin by bin through the bridge hand
    all_d = [v[0] for vs in bins.values() for v in vs]
    if not all_d:
        raise AssertionError('%s: no vertices' % kit.pid)
    if min(all_d) > TIP_SLACK:
        problems.append('the tip stops %.3f studs short of the pivot (at most %.2f)' % (min(all_d), TIP_SLACK))
    if min(all_d) < -TIP_SLACK:
        problems.append('a part reaches %.3f studs before the tip' % -min(all_d))
    for b in sorted(bins):
        vs = bins[b]
        d0 = max(0.0, b * step)
        r_env = R(min(d0 + step / 2, LENGTH))
        rs = [math.hypot(x, z) for _, x, z, _, _ in vs]
        r_max = max(rs)
        # the widest vertex of the bin, by direction
        r_side = max((math.hypot(x, z) for _, x, z, _, _ in vs if z <= 0 or abs(x) > abs(z)), default=0.0)
        r_up = max((math.hypot(x, z) for _, x, z, _, _ in vs if z > 0 and abs(z) >= abs(x)), default=0.0)
        if d0 < TIP_LEN:
            if 2 * r_max > TIP_ACROSS + 1e-6:
                problems.append('%.1f: %.3f across at the tip (at most %.2f)' % (d0, 2 * r_max, TIP_ACROSS))
            continue
        past = d0 - LENGTH
        if past >= 0:
            far = [(d, j, a) for d, _, _, j, a in vs if d > LENGTH + PAST_BUTT and not a]
            if far:
                d, j, _ = max(far)
                problems.append('%s reaches %.2f studs past the butt (at most %.2f without "Aim": "fade")' % (j, d - LENGTH, PAST_BUTT))
            far_aim = [(d, j) for d, _, _, j, a in vs if d > LENGTH + AIM_OVERHANG and a]
            if far_aim:
                d, j = max(far_aim)
                problems.append('%s (Aim) reaches %.2f studs past the butt (at most %.2f)' % (j, d - LENGTH, AIM_OVERHANG))
            continue
        in_hand = any(a <= d0 < b_ for a, b_ in HAND_ZONES)
        ex = BODY_EXCEPTIONS.get(kit.pid, {})
        wide = d0 < ex.get('WideX', 0.0)
        gz = ex.get('GuardInGripZone')
        if in_hand and gz and gz[0] <= d0 < gz[1]:
            in_hand = False   # the guard, ahead of the hand's full wind-up
        if in_hand and wide and ex.get('BridgeCore'):
            core = [(x, z) for _, x, z, j, _ in vs if j in ex['BridgeCore']]
            if core:
                z_max = max(abs(z) for _, z in core)
                if z_max > r_env + HAND_TOL + 1e-6:
                    problems.append('%.1f (hand zone, %s): %.3f thick up or down, envelope %.3f (+%.2f at most)' % (d0, '/'.join(ex['BridgeCore']), z_max, r_env, HAND_TOL))
                # centred: the core up and down in every bin; sideways the whole blade over the
                # zone (its flame serrations are not mirror pairs bin by bin, and which faces
                # count as core is a texture split, not a shape), checked after the loop
                xs = [x for _, x, _, _, _ in vs]
                zs = [z for _, z in core]
                cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
                wide_cx.append(cx)
                if abs(cz) > HAND_TOL + 1e-6:
                    problems.append('%.1f (hand zone): the core off the centreline by %.3f up or down' % (d0, cz))
            continue
        if in_hand:
            r_hand = r_env * ex.get('Slim', 1.0)
            if r_max > r_hand + HAND_TOL + 1e-6:
                problems.append('%.1f (hand zone): radius %.3f, envelope %.3f (+%.2f at most)' % (d0, r_max, r_hand, HAND_TOL))
            r_low = min(r_hand, ex.get('SlimGrip', r_hand))
            if r_max < r_low - HAND_TOL - 1e-6:
                problems.append('%.1f (hand zone): radius %.3f, envelope %.3f (the hand would sink in)' % (d0, r_max, r_low))
            # centred: the bin's outline (its box) is centred on the axis
            xs = [x for _, x, _, _, _ in vs]
            zs = [z for _, _, z, _, _ in vs]
            cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
            if math.hypot(cx, cz) > HAND_TOL + 1e-6:
                problems.append('%.1f (hand zone): centreline off by %.3f' % (d0, math.hypot(cx, cz)))
            continue
        if d0 >= BUTT_FROM:
            if r_max > r_env + BUTT_EXTRA + 1e-6:
                problems.append('%.1f (butt): radius %.3f, envelope %.3f (+%.2f at most)' % (d0, r_max, r_env, BUTT_EXTRA))
            continue
        if wide:
            down, low_joint = max(((-z, j) for _, _, z, j, _ in vs), default=(0.0, '-'))
            if down > r_env + SIDE_EXTRA + 1e-6:
                problems.append('%.1f: %s reaches %.3f down, envelope %.3f (+%.2f at most)' % (d0, low_joint, down, r_env, SIDE_EXTRA))
        elif r_side > r_env + SIDE_EXTRA + 1e-6:
            problems.append('%.1f: radius %.3f sideways or down, envelope %.3f (+%.2f at most)' % (d0, r_side, r_env, SIDE_EXTRA))
        up_allow = UP_EXTRA if 2.1 <= d0 < (gz[1] if gz else 4.4) else SIDE_EXTRA
        if r_up > r_env + up_allow + 1e-6:
            problems.append('%.1f: radius %.3f on +Z, envelope %.3f (+%.2f at most)' % (d0, r_up, r_env, up_allow))
    if wide_cx and abs(sum(wide_cx) / len(wide_cx)) > HAND_TOL + 1e-6:
        problems.append('the blade sits %.3f off the centreline sideways through the bridge hand' % (sum(wide_cx) / len(wide_cx)))
    n_parts = sum(len({m.material for m in ob.material_slots}) for j in kit.joints.values() for ob in j['objects'])
    if n_parts > MAX_PARTS:
        problems.append('about %d parts (joint x material), at most %d' % (n_parts, MAX_PARTS))
    if problems:
        raise AssertionError('%s fails the body rules:\n  ' % kit.pid + '\n  '.join(problems[:12]))
    print('CUE pieces %s: body rules pass' % kit.pid)


# =============================================================================================
# Geometry helpers (bmesh, Blender cue frame)
# =============================================================================================

def _revolve(bm, rows, segs, rib=None, uv=None, mat_of=None):
    """A solid of revolution about the cue's axis: rows are (d, r) from the tip toward the butt
    (r 0 at an end makes a pole). rib(d) -> (count, depth) carves `count` shallow lengthwise
    grooves inward (the crests stay at r). uv(d, share) -> (u, v) writes a UV layer. Faces wind
    outward. Returns the ring vertex lists."""
    from mathutils import Vector
    uvl = bm.loops.layers.uv.new('UVMap') if uv else None
    rings = []
    for d, r in rows:
        n, depth = rib(d) if rib else (0, 0.0)
        if r <= 1e-6:
            rings.append([bm.verts.new(Vector((0.0, -d, 0.0)))])
            continue
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            sc = 1.0 - depth * (0.5 + 0.5 * math.cos(n * a)) if n else 1.0
            ring.append(bm.verts.new(Vector((r * sc * math.sin(a), -d, r * sc * math.cos(a)))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for k in range(segs):
                f = bm.faces.new((a[0], b[(k + 1) % segs], b[k]))
                if uvl:
                    for lp, (dd, kk) in zip(f.loops, ((rows[i][0], k + 0.5), (rows[i + 1][0], k + 1), (rows[i + 1][0], k))):
                        lp[uvl].uv = uv(dd, kk / segs)
        elif len(b) == 1:
            for k in range(segs):
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
                if uvl:
                    for lp, (dd, kk) in zip(f.loops, ((rows[i][0], k), (rows[i][0], k + 1), (rows[i + 1][0], k + 0.5))):
                        lp[uvl].uv = uv(dd, kk / segs)
        else:
            for k in range(segs):
                f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
                if uvl:
                    for lp, (dd, kk) in zip(f.loops, ((rows[i][0], k), (rows[i][0], k + 1), (rows[i + 1][0], k + 1), (rows[i + 1][0], k))):
                        lp[uvl].uv = uv(dd, kk / segs)
    return rings


def _finish(bm):
    import bmesh
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def _rows(d0, d1, radius, step=0.08, first=None, last=None):
    """(d, r) rows from d0 to d1 every `step`, r = radius(d); `first`/`last` override the end radii."""
    n = max(1, int(math.ceil((d1 - d0) / step)))
    out = []
    for i in range(n + 1):
        d = d0 + (d1 - d0) * i / n
        r = radius(d)
        if i == 0 and first is not None:
            r = first
        if i == n and last is not None:
            r = last
        out.append((d, r))
    return out


def _ribbon(bm, points, across_fn, half_width):
    """A flat strip through `points` (Vectors), its width along across_fn(i) (unit Vector)."""
    left, right = [], []
    for i, p in enumerate(points):
        a = across_fn(i)
        left.append(bm.verts.new(p - a * half_width))
        right.append(bm.verts.new(p + a * half_width))
    for i in range(len(points) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))


def _leaf(bm, base, along, up, length, width, tilt_deg):
    """A pointed leaf (two-sided, 8 triangles) rooted at `base`, pointing along `along` tilted
    `tilt_deg` up from it toward `up`, with a midrib crease."""
    from mathutils import Vector, Matrix
    along = Vector(along).normalized()
    up = Vector(up).normalized()
    side = along.cross(up).normalized()
    axis = (Matrix.Rotation(math.radians(tilt_deg), 3, side) @ along).normalized()
    nrm = side.cross(axis).normalized()
    b = Vector(base)
    tip = b + axis * length
    mid = b + axis * (length * 0.42)
    l = mid - side * (width / 2) + nrm * 0.01
    r = mid + side * (width / 2) + nrm * 0.01
    l2 = b + axis * (length * 0.12) - side * (width * 0.22)
    r2 = b + axis * (length * 0.12) + side * (width * 0.22)
    # two sides as two thin sheets (Roblox draws one side of a face; bmesh refuses a mirrored
    # duplicate, so the back gets its own vertices a hair below)
    for sign in (1, -1):
        off = nrm * (-0.004 if sign < 0 else 0.0)
        vb, vt, vm = bm.verts.new(b + off), bm.verts.new(tip + off), bm.verts.new(mid + nrm * 0.018 + off)
        vl, vr, vl2, vr2 = bm.verts.new(l + off), bm.verts.new(r + off), bm.verts.new(l2 + off), bm.verts.new(r2 + off)
        tris = [(vb, vl2, vm), (vb, vm, vr2), (vl2, vl, vm), (vr2, vm, vr), (vl, vt, vm), (vm, vt, vr)]
        for t in tris:
            bm.faces.new(t if sign > 0 else t[::-1])


def _curl(bm, points, radii, segs=8):
    """A tapering tube along `points` (a curly stem)."""
    sweep(bm, points, radii, segs=segs, cap=True)


# =============================================================================================
# Candy Corn Cue (CandyCornCue, Epic, track 150): the body `candy_corn`
# =============================================================================================

CANDY = {'White': '#FFFFFF', 'Orange': '#FF7A12', 'Yellow': '#FFD21E', 'Cream': '#FFF4E2', 'Glow': '#FFF6D8'}


def kernel_palette():
    """vfx/candy_corn/kernel_palette.png: a 64x64 palette (white top, orange, yellow bottom) the
    orbiting kernels wear through their UVs, so three tri-colour kernels are one MeshPart."""
    import numpy as np
    import cue_common as cc
    path = os.path.join(os.path.dirname(PIECES_DIR), 'vfx', 'candy_corn', 'kernel_palette.png')
    if os.path.isfile(path):
        return 'vfx/candy_corn/kernel_palette.png'
    img = np.zeros((64, 64, 3), np.uint8)
    for y in range(64):
        img[y, :] = (255, 255, 255) if y < 21 else ((255, 122, 18) if y < 43 else (255, 210, 30))
    cc.write_png(path, img)
    return 'vfx/candy_corn/kernel_palette.png'


def candy_bands_map(size=512):
    """vfx/candy_corn/bands_512.png: the painted body (coordinator 2026-10-28 12:05): crisp
    white, orange and yellow candy bands along the cue with a sugar speckle and a pearly sheen,
    a hairline dark edge at every band so the stripes read as candy, not paint. u round the
    cue, v from the tip (0) to 7.3 studs (1); the regions follow candy_corn's lathe."""
    import numpy as np
    import cue_common as cc
    rel = 'vfx/candy_corn/bands_512.png'
    path = os.path.join(os.path.dirname(PIECES_DIR), rel)
    rng = np.random.default_rng(11)
    u = (np.arange(size) + 0.5) / size
    v = (np.arange(size) + 0.5) / size
    U, V = np.meshgrid(u, v)
    d = (1.0 - V) * 7.3  # PNG row 0 is UV v = 1: the butt is the top row, the tip the bottom
    cream, orange, yellow, white = (250, 228, 190), (255, 112, 10), (255, 200, 20), (255, 255, 255)
    bands = [(0.0, 0.19, orange), (0.19, 0.30, yellow), (0.30, 0.36, orange), (0.36, 3.42, cream), (3.42, 3.52, orange),
             (3.52, 3.96, white), (3.96, 4.06, orange), (4.06, 5.0, orange), (5.0, 6.79, yellow), (6.79, 6.925, white),
             (6.925, 7.105, orange), (7.105, 7.31, yellow)]
    img = np.zeros((size, size, 3), np.float32)
    edge = np.zeros((size, size), bool)
    for lo, hi, col in bands:
        m = (d >= lo) & (d < hi)
        img[m] = col
        edge |= m & (((d - lo) < 0.012) | ((hi - d) < 0.012))
    # the pearly sheen: a soft highlight band round the cue and a faint ripple along it
    sheen = 0.5 + 0.5 * np.cos(2 * np.pi * (U - 0.25))
    img = img * (0.84 + 0.18 * sheen[..., None]) + 0.08 * 255 * (0.5 + 0.5 * np.sin(2 * np.pi * V * 60))[..., None] * (sheen[..., None] ** 3)
    # sugar glitter: bright specks on the orange and yellow zones, soft pearls on the cream
    noise = rng.random((size, size)).astype(np.float32)
    specks = (noise > 0.965).astype(np.float32)
    glitter = ((d >= 4.06) & (d < 6.79)) | (d < 0.36) | ((d >= 6.925) & (d < 7.31))
    img = img + specks[..., None] * 70 * glitter[..., None] + (noise > 0.985).astype(np.float32)[..., None] * 22
    img[edge] = img[edge] * 0.62
    cc.write_png(path, np.clip(img, 0, 255).astype(np.uint8))
    return rel


def _kernel_at(bm, uvl, centre, up, scale):
    """One candy-corn kernel (the carousel's profile, scale x) standing on `centre` along the
    unit Vector `up`, its tri-colour palette through the UV v (0 base, 1 point)."""
    from mathutils import Vector
    up = Vector(up).normalized()
    a0 = Vector((0, 0, 1)) if abs(up.z) < 0.9 else Vector((1, 0, 0))
    sx = up.cross(a0).normalized()
    sy = up.cross(sx).normalized()
    c = Vector(centre)
    prof = [(0.0, 0.04), (0.035, 0.038), (0.07, 0.03), (0.10, 0.018), (0.125, 0.008), (0.13, 0.0)]
    rings = []
    for t, r in prof:
        if r <= 1e-6:
            rings.append(([bm.verts.new(c + up * (t * scale))], t))
            continue
        ring = []
        for s_ in range(10):
            b = 2 * math.pi * s_ / 10
            ring.append(bm.verts.new(c + up * (t * scale) + (sx * math.cos(b) + sy * math.sin(b)) * (r * scale)))
        rings.append((ring, t))
    c0 = bm.verts.new(c)
    r0 = rings[0][0]
    for s_ in range(10):
        f = bm.faces.new((c0, r0[(s_ + 1) % 10], r0[s_]))
        for lp in f.loops:
            lp[uvl].uv = (0.5, 0.02)
    for i in range(len(rings) - 1):
        (ra, ta), (rb, tb) = rings[i], rings[i + 1]
        for s_ in range(10):
            if len(rb) == 1:
                f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[0]))
                ts = (ta, ta, tb)
            else:
                f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[(s_ + 1) % 10], rb[s_]))
                ts = (ta, ta, tb, tb)
            for lp, tt in zip(f.loops, ts):
                lp[uvl].uv = (0.5, 0.04 + 0.92 * tt / 0.13)


@piece
def candy_corn(k):
    """The Candy Corn Cue's body (brief 2.7): a kernel tip (a white glowing point, orange,
    yellow) with a thin orange collar; a glossy cream shaft; at the joint an orange ring, a
    white sleeve under a turning orange barber-pole ribbon, an orange ring; an orange forearm;
    a yellow handle; past the grip a candy-corn bulb (white, orange, a yellow dome) wider than
    the cue. Three small candy corns turn above the joint like a carousel; the tip glow pulses."""
    import bmesh
    from mathutils import Vector
    R = envelope()
    for name, hexc in CANDY.items():
        k.material(name, 'Neon' if name == 'Glow' else 'SmoothPlastic', hexc, Reflectance=0.0 if name == 'Glow' else 0.14)
    k.material('Kernel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.1,
               SurfaceAppearance={'ColorMap': kernel_palette()})
    # the painted body (coordinator 12:05): crisp candy bands with a sugar sheen, one colour map
    k.material('Sugar', 'SmoothPlastic', '#FFFFFF', Reflectance=0.08, SurfaceAppearance={'ColorMap': candy_bands_map()})

    # --- the body: one lathe, materials by distance ------------------------------------------
    k.joint('Body', pivot=(0, -3.5, 0))
    rows = []
    rows += [(0.07, R(0.07))]                                   # the point is the Glow part
    rows += _rows(0.07, 0.30, R, 0.05)[1:]                      # kernel bands (orange, yellow)
    rows += [(0.30, R(0.30)), (0.305, R(0.30) + 0.012), (0.355, R(0.355) + 0.012), (0.36, R(0.36))]  # collar
    rows += _rows(0.36, 3.42, R, 0.12)[1:]                      # cream shaft
    rows += [(3.42, R(3.42)), (3.425, R(3.42) + 0.03), (3.515, R(3.515) + 0.03), (3.52, R(3.52))]    # ring
    rows += _rows(3.52, 3.96, R, 0.11)[1:]                      # white sleeve
    rows += [(3.96, R(3.96)), (3.965, R(3.96) + 0.03), (4.055, R(4.055) + 0.03), (4.06, R(4.06))]    # ring
    rows += _rows(4.06, 6.78, R, 0.12)[1:]                      # forearm, handle
    # the bulb: a white band swelling, an orange band, a yellow dome ending at 7.30
    for d in (6.82, 6.86, 6.90, 6.92):
        rows.append((d, 0.18 + (0.26 - 0.18) * (d - 6.78) / (6.92 - 6.78)))
    for d in (6.96, 7.02, 7.08, 7.10):
        rows.append((d, 0.26 + (0.33 - 0.26) * (d - 6.92) / (7.10 - 6.92)))
    for i in range(1, 8):
        d = 7.10 + 0.19 * i / 8
        rows.append((d, 0.33 * math.sqrt(max(0.0, 1 - ((d - 7.10) / 0.19) ** 2))))
    rows.append((7.29, 0.0))
    bm = bmesh.new()
    _revolve(bm, rows, 24, uv=lambda d, share: (share, d / 7.3))
    _finish(bm)
    ob = k.mesh_object('CandyBody', bm, ['Sugar'])
    k.add('Body', ob)

    # --- the glowing white point of the kernel tip (pulses) -----------------------------------
    k.joint('Tip', pivot=(0, 0, 0), visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.5, 'Period': 1.6}])
    bm = bmesh.new()
    _revolve(bm, [(0.0, 0.0), (0.012, 0.03), (0.03, 0.042), (0.07, R(0.07) + 0.002), (0.075, 0.0)], 16)
    _finish(bm)
    k.add('Tip', k.mesh_object('TipGlow', bm, ['Glow']))

    # --- the barber-pole ribbon over the white sleeve (turns slowly) --------------------------
    k.joint('Wrap', pivot=(0, -3.74, 0), motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 90.0}])
    bm = bmesh.new()
    pts, acr = [], []
    n = 90
    for i in range(n):
        d = 3.545 + (3.935 - 3.545) * i / (n - 1)
        a = 2 * math.pi * (d - 3.545) / 0.195            # two turns over the sleeve
        radial = Vector((math.sin(a), 0, math.cos(a)))
        p = Vector((0, -d, 0)) + radial * (R(d) + 0.012)
        d2 = d + 0.004
        a2 = 2 * math.pi * (d2 - 3.545) / 0.195
        p2 = Vector((0, -d2, 0)) + Vector((math.sin(a2), 0, math.cos(a2))) * (R(d2) + 0.012)
        tang = (p2 - p).normalized()
        pts.append(p)
        acr.append(tang.cross(radial).normalized())
    _ribbon(bm, pts, lambda i: acr[i], 0.03)
    ob = k.mesh_object('WrapRibbon', bm, ['Orange'])
    apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=0.014, offset=0.0)
    k.add('Wrap', ob)

    # --- three little candy corns turning above the joint ------------------------------------
    top = R(3.74) + 0.13
    k.joint('Kernels', pivot=(0, -3.74, top), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 138.0}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    for j in range(3):
        a = 2 * math.pi * j / 3
        cx, cy = 0.085 * math.sin(a), -3.74 + 0.085 * math.cos(a)
        base = top - 0.065
        prof = [(0.0, 0.04), (0.035, 0.038), (0.07, 0.03), (0.10, 0.018), (0.125, 0.008), (0.13, 0.0)]
        rings = []
        for t, r in prof:
            if r <= 1e-6:
                rings.append(([bm.verts.new(Vector((cx, cy, base + t)))], t))
                continue
            ring = []
            for s_ in range(10):
                b = 2 * math.pi * s_ / 10
                ring.append(bm.verts.new(Vector((cx + r * math.cos(b), cy + r * math.sin(b), base + t))))
            rings.append((ring, t))
        # the base cap
        c0 = bm.verts.new(Vector((cx, cy, base)))
        r0 = rings[0][0]
        for s_ in range(10):
            f = bm.faces.new((c0, r0[(s_ + 1) % 10], r0[s_]))
            for lp in f.loops:
                lp[uvl].uv = (0.5, 0.02)
        for i in range(len(rings) - 1):
            (ra, ta), (rb, tb) = rings[i], rings[i + 1]
            for s_ in range(10):
                if len(rb) == 1:
                    f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[0]))
                    ts = (ta, ta, tb)
                else:
                    f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[(s_ + 1) % 10], rb[s_]))
                    ts = (ta, ta, tb, tb)
                for lp, tt in zip(f.loops, ts):
                    lp[uvl].uv = (0.5, 0.04 + 0.92 * tt / 0.13)
    _finish(bm)
    k.add('Kernels', k.mesh_object('Kernels', bm, ['Kernel']))
    check_body(k)


# =============================================================================================
# Candy Corn aura decor: `candy_corn_aura` (designer 2026-10-28 11:55: the Beta/Firework level)
# =============================================================================================


def _wing(bm, root, along, side, normal, length, width, pleats=5):
    """A crinkled wrapper wing (a cellophane fan): rooted at `root`, reaching `length` along
    `along`, widening to `width` across `side`, zigzag pleats in `normal`; two-sided."""
    from mathutils import Vector
    root, along, side, normal = Vector(root), Vector(along).normalized(), Vector(side).normalized(), Vector(normal).normalized()
    for sign in (1, -1):
        off = normal * (-0.004 if sign < 0 else 0.0)
        cols = []
        for i in range(pleats + 1):
            u = i / pleats
            zig = normal * (0.014 * (1 if i % 2 == 0 else -1))
            a = root + side * ((u - 0.5) * width * 0.18) + off
            b = root + along * length + side * ((u - 0.5) * width) + zig + off
            cols.append((bm.verts.new(a), bm.verts.new(b)))
        for i in range(pleats):
            (a0, b0), (a1, b1) = cols[i], cols[i + 1]
            quad = (a0, b0, b1, a1)
            bm.faces.new(quad if sign > 0 else quad[::-1])


def _crystal(bm, centre, up, size):
    """A sugar crystal: an octahedron standing on `centre`, its long axis along `up`."""
    from mathutils import Vector
    c, up = Vector(centre), Vector(up).normalized()
    a0 = Vector((0, 0, 1)) if abs(up.z) < 0.9 else Vector((1, 0, 0))
    sx = up.cross(a0).normalized()
    sy = up.cross(sx).normalized()
    top = bm.verts.new(c + up * (size * 1.6))
    bot = bm.verts.new(c)
    ring = [bm.verts.new(c + up * (size * 0.6) + (sx * math.cos(b) + sy * math.sin(b)) * (size * 0.55)) for b in (0, math.pi / 2, math.pi, 3 * math.pi / 2)]
    for i in range(4):
        bm.faces.new((top, ring[(i + 1) % 4], ring[i]))
        bm.faces.new((bot, ring[i], ring[(i + 1) % 4]))


@piece
def candy_corn_aura(k):
    """The Candy Corn's own candy-shop motion, nothing wrapping a stick (designer 2026-10-28
    12:55: no ribbons, a hand-made signature): four candy-corn kernels hop on the shaft just
    behind the tip where the fountain pours (aura joints: Bob snap, a quick drop and a slow
    rise, and a tumble), five sugar crystals stand on the orange and yellow bands and twinkle
    (Glow flicker), and the butt's cellophane wrapper, four crinkled wings tied behind the
    dome, pops open (Hinge, quick open, slow close) in two pairs. The aura rows pour the
    kernel fountain off the tip and sparkle sugar on the bands. Lower effects keeps two
    kernels, two wings and the crystals."""
    import bmesh
    from mathutils import Vector
    R = envelope()
    k.material('Kernel', 'SmoothPlastic', '#FFFFFF', Reflectance=0.1, SurfaceAppearance={'ColorMap': kernel_palette()})
    k.material('Crystal', 'Neon', '#FFF8E0', Transparency=0.05)
    k.material('Wrapper', 'SmoothPlastic', '#FF9A3C', Transparency=0.12, Reflectance=0.25)  # an orange cellophane, it must read on the floor
    k.material('Tie', 'SmoothPlastic', '#FF7A12')

    # --- the kernels hopping behind the tip -------------------------------------------------
    for i, (d, ang, period, low) in enumerate(((0.55, 0.3, 0.8, None), (0.85, 2.3, 0.95, 'hide'), (1.2, 4.2, 0.7, None), (1.55, 1.2, 1.05, 'hide'))):
        name = 'Kernel%d' % (i + 1)
        radial = Vector((math.sin(ang), 0, math.cos(ang)))
        tangent = Vector((math.cos(ang), 0, -math.sin(ang)))
        base = Vector((0, -d, 0)) + radial * (R(d) + 0.01)
        k.joint(name, pivot=tuple(base), aura=True, low=low,
                motion=[{'Kind': 'Bob', 'Dir': tuple(radial), 'Amp': 0.07, 'Period': period, 'Phase': 90 * i, 'Shape': 'snap'},
                        {'Kind': 'Hinge', 'Axis': tuple(tangent), 'Amp': 25.0, 'Period': period * 2, 'Phase': 45 * i},
                        {'Kind': 'Spin', 'Axis': tuple(radial), 'Rate': 120.0 * (1 if i % 2 == 0 else -1)}])
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new('UVMap')
        _kernel_at(bm, uvl, base + radial * 0.09, tuple(radial * 0.6 + tangent * 0.4), 2.2)
        _finish(bm)
        k.add(name, k.mesh_object(name + 'Kernel', bm, ['Kernel']))

    # --- the sugar crystals on the bands, twinkling ------------------------------------------
    for i, (d, ang, period) in enumerate(((4.3, 0.5, 1.1), (4.75, 2.6, 1.6), (5.3, 4.4, 1.3), (5.9, 1.6, 1.9), (6.4, 3.6, 1.4))):
        name = 'Crystal%d' % (i + 1)
        radial = Vector((math.sin(ang), 0, math.cos(ang)))
        base = Vector((0, -d, 0)) + radial * (R(d) - 0.005)
        k.joint(name, pivot=tuple(base), visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 1.0, 'Period': period, 'Shape': 'flicker', 'Color': '#FFFFFF'}])
        bm = bmesh.new()
        _crystal(bm, base, radial, 0.075)
        _finish(bm)
        k.add(name, k.mesh_object(name, bm, ['Crystal']))

    # --- the wrapper at the butt: four crinkled wings tied behind the dome, popping open -----
    for i, (sx, sz, period, phase, low) in enumerate(((1, 0, 2.8, 0, None), (-1, 0, 2.8, 0, None), (0, 1, 3.4, 50, 'hide'), (0, -1, 3.4, 50, 'hide'))):
        name = 'Wing%d' % (i + 1)
        side = Vector((sx, 0, sz))
        root = Vector((0, -7.14, 0)) + side * 0.24
        axis = Vector((0, 0, 1)) * sx + Vector((-1, 0, 0)) * sz   # opening swings the wing out toward `side`
        k.joint(name, pivot=tuple(root), low=low,
                motion=[{'Kind': 'Hinge', 'Axis': tuple(axis), 'Base': 26.0, 'Amp': -26.0, 'Period': period, 'Phase': phase, 'Shape': 'snap'}])
        bm = bmesh.new()
        _wing(bm, root, (0, -1, 0), tuple(side.cross(Vector((0, -1, 0)))), tuple(side), 0.46, 0.42)
        _finish(bm)
        k.add(name, k.mesh_object(name, bm, ['Wrapper']))
    # the twist tie round the wings' roots
    k.joint('Tie', pivot=(0, -7.14, 0))
    bm = bmesh.new()
    pts = [Vector((0.27 * math.cos(b), -7.15, 0.27 * math.sin(b))) for b in [2 * math.pi * j / 24 for j in range(25)]]
    sweep(bm, pts, [0.022] * 25, segs=6, cap=False)
    _finish(bm)
    k.add('Tie', k.mesh_object('Tie', bm, ['Tie']))

# =============================================================================================
# Jack-o'-Lantern Cue (JackOLanternCue, Legendary, track 500): the body `jack_o_lantern`
# =============================================================================================

JACK = {'Orange': '#FF7A1C', 'Green': '#2F5A2A', 'Brown': '#5A3A22', 'Vine': '#3E8E3A', 'Leaf': '#4EA63C',
        'Slit': '#FF9A2E', 'Face': '#FFC34D'}
PUMPKIN_C, PUMPKIN_HALF, PUMPKIN_R = 6.96, 0.20, 0.36   # the butt pumpkin: centre, half-length, radius


def _pumpkin_r(d):
    u = (d - PUMPKIN_C) / PUMPKIN_HALF
    return PUMPKIN_R * math.sqrt(max(0.0, 1 - u * u))


def _vine_offset(d):
    """How far the vine strand's centre sits off the envelope: flush in the hand zones, standing
    out between them, over the collars at the joint."""
    def blend(a, b, lo, hi):
        if d <= lo:
            return a
        if d >= hi:
            return b
        t = (d - lo) / (hi - lo)
        return a + (b - a) * (t * t * (3 - 2 * t))
    if d < 2.12:
        return -0.003
    if d < 2.32:
        return blend(-0.003, 0.02, 2.12, 2.32)
    if d < 3.3:
        return 0.02
    if d < 3.42:
        return blend(0.02, 0.045, 3.3, 3.42)
    if d < 4.06:
        return 0.045
    if d < 4.16:
        return blend(0.045, 0.02, 4.06, 4.16)
    if d < 4.2:
        return 0.02
    if d < 4.37:
        return blend(0.02, -0.003, 4.2, 4.37)
    return -0.003


def jack_rind_map(size=512):
    """vfx/jack_o_lantern/rind_512.png: the painted body (coordinator 2026-10-28 12:05: a flat
    orange cylinder reads cheap next to Firework's painted navy and gold). u runs round the cue
    (the eight rib grooves of _revolve's rib carve fall where cos(8 * 2 pi u) = 1), v runs from the
    tip (0) to 7.3 studs (1): a dark green stem, dark wood collars with grain, pumpkin orange
    shaded deep in the grooves and bright on the crests with a sugar of speckle, the butt pumpkin
    deeper and burnt toward its end, a near-black band at the pumpkin's base."""
    import numpy as np
    import cue_common as cc
    rel = 'vfx/jack_o_lantern/rind_512.png'
    path = os.path.join(os.path.dirname(PIECES_DIR), rel)
    rng = np.random.default_rng(7)
    u = (np.arange(size) + 0.5) / size
    v = (np.arange(size) + 0.5) / size
    U, V = np.meshgrid(u, v)                     # rows = v (along), cols = u (round)
    d = (1.0 - V) * 7.3  # PNG row 0 is UV v = 1: the butt is the top row, the tip the bottom
    groove = 0.5 + 0.5 * np.cos(8 * 2 * np.pi * U)   # 1 in a groove, 0 on a crest
    crest = 1.0 - groove
    noise = rng.random((size, size)).astype(np.float32)
    fine = (noise > 0.93).astype(np.float32)
    def lerp(a, b, t):
        return np.array(a)[None, None, :] * (1 - t[..., None]) + np.array(b)[None, None, :] * t[..., None]
    orange_c, orange_g = (255, 142, 40), (168, 62, 10)
    img = lerp(orange_c, orange_g, groove ** 0.8)
    img = img * (0.94 + 0.06 * noise[..., None]) + fine[..., None] * 26
    # the pumpkin: deeper, burnt toward the end, the ribs stronger
    pump = (d >= 6.76)
    deep = lerp((240, 112, 24), (150, 44, 6), np.clip(groove * 1.1, 0, 1) ** 0.7)
    burnt = np.clip((d - 6.76) / 0.42, 0, 1)
    deep = deep * (1 - 0.25 * burnt[..., None])
    img = np.where(pump[..., None], deep, img)
    # dark wood collars with grain and the band at the pumpkin's base
    grain = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 9 + 0.6 * np.sin(2 * np.pi * V * 40)))
    wood = lerp((58, 36, 20), (30, 18, 10), grain)
    for lo, hi in ((0.30, 0.36), (3.38, 3.58), (3.88, 4.08), (6.70, 6.80)):
        band = (d >= lo) & (d < hi)
        edge = ((d - lo) < 0.02) | ((hi - d) < 0.02)
        img = np.where(band[..., None], np.where(edge[..., None], wood * 0.55, wood), img)
    # the stem tip: dark green with lighter streaks
    stem = d < 0.30
    streak = 0.5 + 0.5 * np.sin(2 * np.pi * U * 6)
    green = lerp((40, 86, 36), (24, 54, 22), streak)
    img = np.where(stem[..., None], green, img)
    cc.write_png(path, np.clip(img, 0, 255).astype(np.uint8))
    return rel


@piece
def jack_o_lantern(k):
    """The Jack-o'-Lantern Cue's body (brief 2.8): a dark green stem tip with a brown ring; a
    glossy pumpkin-orange shaft with eight shallow lengthwise ribs; a green vine spiralling
    along the whole cue (flush in the hands, standing out between them) with five leaves on
    top that sway; dark wood collars at the joint with glowing orange slits that pulse; at the
    butt a ribbed carved pumpkin whose triangle eyes and jagged grin glow and flicker like a
    candle, with a curly green stem out of its end."""
    import bmesh
    from mathutils import Vector
    R = envelope()
    for name, hexc in JACK.items():
        neon = name in ('Slit', 'Face')
        k.material(name, 'Neon' if neon else 'SmoothPlastic', hexc, Reflectance=0.0 if neon else (0.1 if name == 'Orange' else 0.03))
    # the painted body (coordinator 12:05): one colour map over the whole lathe
    k.material('Rind', 'SmoothPlastic', '#FFFFFF', Reflectance=0.06, SurfaceAppearance={'ColorMap': jack_rind_map()})

    # --- the body lathe: tip stem, ring, ribbed shaft, collars, pumpkin ----------------------
    k.joint('Body', pivot=(0, -3.5, 0))
    rows = [(0.0, 0.0), (0.012, 0.03), (0.03, R(0.03))]
    rows += _rows(0.03, 0.30, R, 0.06)[1:]
    rows += [(0.30, R(0.30)), (0.305, R(0.30) + 0.012), (0.355, R(0.355) + 0.012), (0.36, R(0.36))]
    rows += _rows(0.36, 3.38, R, 0.1)[1:]
    rows += [(3.38, R(3.38)), (3.385, R(3.38) + 0.03), (3.575, R(3.575) + 0.03), (3.58, R(3.58))]
    rows += _rows(3.58, 3.88, R, 0.1)[1:]
    rows += [(3.88, R(3.88)), (3.885, R(3.88) + 0.03), (4.075, R(4.075) + 0.03), (4.08, R(4.08))]
    rows += _rows(4.08, 6.76, R, 0.1)[1:]
    # the pumpkin grows out of the handle: the larger of the handle and the pumpkin's surface
    for i in range(1, 21):
        d = 6.76 + (7.16 - 6.76) * i / 20
        rows.append((d, max(0.18 if d < 6.96 else 0.0, _pumpkin_r(d))))
    rows.append((7.165, 0.0))

    def rib(d):
        if 0.36 <= d < 3.38 or 3.58 <= d < 3.88 or 4.08 <= d < 6.76:
            return (8, 0.1)
        if d > 6.78:
            return (8, 0.12)
        return (0, 0.0)
    bm = bmesh.new()
    _revolve(bm, rows, 24, rib=rib, uv=lambda d, share: (share, d / 7.3))
    _finish(bm)
    ob = k.mesh_object('JackBody', bm, ['Rind'])
    k.add('Body', ob)

    # --- the curly stem out of the pumpkin's end ---------------------------------------------
    bm = bmesh.new()
    _curl(bm, [(0, -7.12, 0.0), (0, -7.19, 0.02), (0, -7.25, 0.06), (0, -7.27, 0.11), (0, -7.235, 0.155), (0, -7.17, 0.165), (0, -7.12, 0.14)],
          [0.04, 0.036, 0.032, 0.028, 0.024, 0.02, 0.016], segs=8)
    _finish(bm)
    k.add('Body', k.mesh_object('Stem', bm, ['Green']))

    # --- the vine: a helix along the whole cue -----------------------------------------------
    bm = bmesh.new()
    pts, rads = [], []
    n = 190
    for i in range(n):
        d = 0.42 + (6.70 - 0.42) * i / (n - 1)
        a = 2 * math.pi * d / 0.8
        radial = Vector((math.sin(a), 0, math.cos(a)))
        pts.append(Vector((0, -d, 0)) + radial * (R(d) + _vine_offset(d)))
        rads.append(0.02)
    sweep(bm, pts, rads, segs=5, cap=True)
    _finish(bm)
    k.add('Body', k.mesh_object('Vine', bm, ['Vine']))

    # --- the leaves, on top, swaying ----------------------------------------------------------
    k.joint('Leaves', pivot=(0, -3.5, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': 2.6},
        {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.012, 'Period': 1.7, 'Phase': 50}])
    bm = bmesh.new()
    for d, side in ((2.42, -1), (2.5, 1), (3.2, 1), (4.0, -1), (6.9, 1)):
        if d < 6.7:
            z0 = R(d) + _vine_offset(d) + 0.01
            along = (side * 0.75, -0.55, 0.0)        # toward the butt, out to one side
            length, tilt = 0.15, 38
        else:
            z0 = _pumpkin_r(d) - 0.03
            along = (side * 0.8, -0.3, 0.0)         # lying on the pumpkin, toward its end
            length, tilt = 0.13, 22
        _leaf(bm, (0.0, -d, z0), along, (0, 0, 1), length, 0.09, tilt)
    _finish(bm)
    k.add('Leaves', k.mesh_object('Leaves', bm, ['Leaf']))

    # --- the collars' glowing slits (pulse slowly) ---------------------------------------------
    k.joint('Slits', pivot=(0, -3.73, 0), visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.45, 'Period': 4.0}])
    bm = bmesh.new()
    for d0, d1 in ((3.41, 3.55), (3.91, 4.05)):
        for s_ in range(6):
            a = 2 * math.pi * (s_ + 0.5) / 6
            radial = Vector((math.sin(a), 0, math.cos(a)))
            tang = Vector((math.cos(a), 0, -math.sin(a)))
            rr = R((d0 + d1) / 2) + 0.03
            inner, outer = rr - 0.012, rr + 0.006
            corners = []
            for dd in (d0, d1):
                for t in (-0.016, 0.016):
                    for rad in (inner, outer):
                        corners.append(bm.verts.new(Vector((0, -dd, 0)) + radial * rad + tang * t))
            # corners index: dd*4 + t*2 + rad
            def V(i, j, l):
                return corners[i * 4 + j * 2 + l]
            quads = [((0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)), ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)),
                     ((0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)), ((0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)),
                     ((0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)), ((1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0))]
            for q in quads:
                bm.faces.new(tuple(V(*c) for c in q))
    _finish(bm)
    k.add('Slits', k.mesh_object('Slits', bm, ['Slit']))

    # --- the carved face on top of the pumpkin (flickers like a candle) ----------------------
    k.joint('Face', pivot=(0, -PUMPKIN_C, 0), visual=[
        {'Kind': 'Glow', 'Min': 0.25, 'Max': 0.8, 'Period': 0.55, 'Shape': 'flicker', 'Color': '#FFC040'},  # a candle, not a pulse (12:55); Color, else white
        {'Kind': 'Blink', 'Period': 2.7, 'Seconds': 0.37, 'Count': 3, 'Phase': 1.1}])
    bm = bmesh.new()

    def surf(x, d, lift):
        r = _pumpkin_r(d) + lift
        return Vector((x, -d, math.sqrt(max(1e-4, r * r - x * x))))

    def prism(poly, scale=1.0):
        # lifted, the eyes 1.25x, so the face reads from the table (12:05); the mouth keeps its
        # size: its wide corners sit where the pumpkin narrows toward the grip zone
        poly = [(x * scale, PUMPKIN_C + (d - PUMPKIN_C) * scale) for x, d in poly]
        top = [bm.verts.new(surf(x, d, 0.02)) for x, d in poly]
        bot = [bm.verts.new(surf(x, d, -0.06)) for x, d in poly]
        bm.faces.new(top)
        bm.faces.new(bot[::-1])
        m = len(poly)
        for i in range(m):
            bm.faces.new((top[i], bot[i], bot[(i + 1) % m], top[(i + 1) % m]))
    # eyes: triangles pointing toward the stem, mouth: a jagged grin toward the handle
    for sx in (-1, 1):
        prism([(sx * 0.07, 7.06), (sx * 0.20, 7.06), (sx * 0.135, 6.94)], 1.25)
    mouth = [(-0.22, 6.90), (-0.16, 6.95), (-0.10, 6.90), (-0.04, 6.95), (0.03, 6.90), (0.10, 6.95), (0.17, 6.90), (0.22, 6.90),
             (0.20, 6.82), (0.12, 6.78), (0.05, 6.82), (-0.03, 6.78), (-0.11, 6.82), (-0.18, 6.78), (-0.22, 6.84)]
    prism(mouth)
    _finish(bm)
    k.add('Face', k.mesh_object('Face', bm, ['Face']))
    check_body(k)


# =============================================================================================
# Jack-o'-Lantern aura decor: `jack_o_lantern_aura` (designer 2026-10-28 11:55: bring the cue up to
# the Beta/Firework level: a real 3D piece round the whole cue, glowing and moving)
# =============================================================================================

FLAME = {'FlameA': '#FF6A10', 'FlameB': '#FFB030', 'MiniPumpkin': '#FF7A1C', 'MiniFace': '#FFD24D', 'MiniStem': '#3E8E3A'}


def _mini_pumpkin(bm, centre, radius, segs=14):
    """A ribbed little pumpkin (a sphere squashed a hair along the cue) centred at `centre`
    (cue frame), its stem along +Z. Returns nothing; faces go into bm."""
    from mathutils import Vector
    import bmesh
    c = Vector(centre)
    rows = []
    n = 10
    for i in range(n + 1):
        u = -1 + 2 * i / n
        r = radius * math.sqrt(max(0.0, 1 - u * u)) * 1.0
        rows.append((u * radius * 0.86, r))
    rings = []
    for off, r in rows:
        if r <= 1e-6:
            rings.append([bm.verts.new(c + Vector((0, 0, off)))])
            continue
        ring = []
        for k_ in range(segs):
            a = 2 * math.pi * k_ / segs
            sc = 1.0 - 0.12 * (0.5 + 0.5 * math.cos(8 * a))
            ring.append(bm.verts.new(c + Vector((r * sc * math.cos(a), r * sc * math.sin(a), off))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1:
            for k_ in range(segs):
                bm.faces.new((a[0], b[k_], b[(k_ + 1) % segs]))
        elif len(b) == 1:
            for k_ in range(segs):
                bm.faces.new((a[k_], b[0], a[(k_ + 1) % segs]))
        else:
            for k_ in range(segs):
                bm.faces.new((a[k_], b[k_], b[(k_ + 1) % segs], a[(k_ + 1) % segs]))


def _mini_face(bm, centre, radius, out):
    """Glowing triangle eyes and a jagged grin as thin plates on the pumpkin's side facing `out`
    (a unit Vector in the XY plane, away from the cue's axis)."""
    from mathutils import Vector
    out = Vector(out).normalized()
    up = Vector((0, 0, 1))
    side = up.cross(out).normalized()
    base = Vector(centre) + out * (radius * 0.97)
    lift = out * 0.02

    def plate(poly):
        top = [bm.verts.new(base + side * x + up * z + lift) for x, z in poly]
        bot = [bm.verts.new(base + side * x + up * z - out * 0.03) for x, z in poly]
        bm.faces.new(top)
        bm.faces.new(bot[::-1])
        m = len(poly)
        for i in range(m):
            bm.faces.new((top[i], bot[i], bot[(i + 1) % m], top[(i + 1) % m]))
    s = radius / 0.36
    for sx in (-1, 1):
        plate([(sx * 0.07 * s, 0.02 * s), (sx * 0.20 * s, 0.02 * s), (sx * 0.135 * s, 0.14 * s)])
    plate([(-0.20 * s, -0.04 * s), (-0.12 * s, 0.01 * s), (-0.04 * s, -0.04 * s), (0.04 * s, 0.01 * s), (0.12 * s, -0.04 * s), (0.20 * s, -0.04 * s),
           (0.16 * s, -0.12 * s), (0.06 * s, -0.08 * s), (-0.06 * s, -0.13 * s), (-0.16 * s, -0.09 * s)])


@piece
def jack_o_lantern_aura(k):
    """The Jack-o'-Lantern's own life, nothing that wraps a stick (designer 2026-10-28 12:55: no
    ribbons, a hand-made signature): the vine LIVES, with four corkscrew tendrils that turn and
    wave where they sprout from it and four leaves that sway; three small pumpkins sprout on the
    vine and glow from inside (aura joints: they clear on the shooter's own turn); the butt
    pumpkin's JAW, the grin's lower teeth as its own plate, snaps open and shut (Hinge, quick
    close, slow open) so the glowing mouth breathes (the aura rows put a little flame and the
    embers at the mouth). Lower effects keeps the jaw, two tendrils, two leaves and one
    pumpkin."""
    import bmesh
    from mathutils import Vector
    R = envelope()
    k.material('Vine', 'SmoothPlastic', '#3E8E3A')
    k.material('Leaf', 'SmoothPlastic', '#5BB04A')
    k.material('MiniPumpkin', 'SmoothPlastic', FLAME['MiniPumpkin'])
    k.material('MiniFace', 'Neon', FLAME['MiniFace'])
    k.material('MiniStem', 'SmoothPlastic', FLAME['MiniStem'])
    k.material('Jaw', 'SmoothPlastic', '#C8501A')

    def on_vine(d):
        a = 2 * math.pi * d / 0.8
        radial = Vector((math.sin(a), 0, math.cos(a)))
        tangent = Vector((math.cos(a), 0, -math.sin(a)))
        p0 = Vector((0, -d, 0)) + radial * (R(d) + _vine_offset(d))
        return p0, radial, tangent

    # --- the tendrils: corkscrews off the vine, turning on their own axis and waving ----------
    for i, (d, period, rate, low) in enumerate(((1.6, 2.8, 26.0, None), (2.9, 3.4, -22.0, 'hide'),
                                                (4.3, 2.4, 30.0, None), (5.5, 3.1, -24.0, 'hide'))):
        name = 'Tendril%d' % (i + 1)
        p0, radial, tangent = on_vine(d)
        binorm = radial.cross(tangent).normalized()
        k.joint(name, pivot=tuple(p0), low=low,
                motion=[{'Kind': 'Spin', 'Axis': tuple(radial), 'Rate': rate},
                        {'Kind': 'Hinge', 'Axis': tuple(tangent), 'Amp': 13.0, 'Period': period, 'Phase': 35 * i}])
        bm = bmesh.new()
        pts, rads = [], []
        n = 44
        for j in range(n):
            s_ = j / (n - 1)
            th = 2 * math.pi * 2.1 * s_
            coil = 0.052 * (1.0 - 0.55 * s_) * min(1.0, s_ * 4)
            pts.append(p0 + radial * (0.015 + 0.2 * s_) + (tangent * math.cos(th) + binorm * math.sin(th)) * coil)
            rads.append(0.013 * (1.0 - 0.7 * s_) + 0.003)
        sweep(bm, pts, rads, segs=6, cap=True)
        _finish(bm)
        k.add(name, k.mesh_object(name, bm, ['Vine']))

    # --- the leaves on the vine, swaying ----------------------------------------------------
    for i, (d, side, period, low) in enumerate(((2.0, 1, 2.2, None), (3.6, -1, 2.9, 'hide'), (4.9, 1, 2.5, None), (6.1, -1, 3.2, 'hide'))):
        name = 'Leaf%d' % (i + 1)
        p0, radial, tangent = on_vine(d)
        k.joint(name, pivot=tuple(p0), low=low,
                motion=[{'Kind': 'Hinge', 'Axis': tuple(tangent), 'Amp': 9.0, 'Period': period, 'Phase': 60 * i},
                        {'Kind': 'Bob', 'Dir': tuple(radial), 'Amp': 0.01, 'Period': 1.7, 'Phase': 40 * i}])
        bm = bmesh.new()
        along = (tangent * (0.75 * side) + Vector((0, -0.55, 0))).normalized()
        _leaf(bm, tuple(p0 + radial * 0.012), tuple(along), tuple(radial), 0.17, 0.1, 36)
        _finish(bm)
        k.add(name, k.mesh_object(name, bm, ['Leaf']))

    # --- the little pumpkins sprouting on the vine, glowing from inside ---------------------
    for i, (d, period, low) in enumerate(((2.45, 2.0, None), (3.95, 2.7, 'hide'), (5.65, 3.3, 'hide'))):
        name = 'Pumpkin%d' % (i + 1)
        p0, radial, tangent = on_vine(d)
        radius = 0.13
        centre = p0 + radial * (radius + 0.005)
        k.joint(name, pivot=tuple(centre), aura=True, low=low,
                motion=[{'Kind': 'Bob', 'Dir': tuple(radial), 'Amp': 0.02, 'Period': period, 'Phase': 70 * i},
                        {'Kind': 'Hinge', 'Axis': tuple(tangent), 'Amp': 5.0, 'Period': period * 1.3, 'Phase': 20 * i}],
                visual=[{'Kind': 'Glow', 'Min': 0.1, 'Max': 0.85, 'Period': period, 'Shape': 'beat', 'Color': '#FFA030'}])
        bm = bmesh.new()
        _mini_pumpkin(bm, centre, radius)
        _finish(bm)
        k.add(name, k.mesh_object(name + 'Body', bm, ['MiniPumpkin']))
        bm = bmesh.new()
        _mini_face(bm, centre, radius, radial)
        _finish(bm)
        k.add(name, k.mesh_object(name + 'Face', bm, ['MiniFace']))
        bm = bmesh.new()
        top = centre + radial * radius
        _curl(bm, [tuple(top), tuple(top + radial * 0.03), tuple(top + radial * 0.055 + tangent * 0.015),
                   tuple(top + radial * 0.065 + tangent * 0.04)], [0.016, 0.014, 0.011, 0.007], segs=6)
        _finish(bm)
        k.add(name, k.mesh_object(name + 'Stem', bm, ['MiniStem']))

    # --- the jaw: the grin's lower teeth as a plate hinged at the chin, snapping open --------
    def surf(x, d, lift):
        r = _pumpkin_r(d) + lift
        return Vector((x, -d, math.sqrt(max(1e-4, r * r - x * x))))
    k.joint('Jaw', pivot=tuple(surf(0, 6.80, 0.0)),
            motion=[{'Kind': 'Hinge', 'Axis': (-1, 0, 0), 'Base': 13.0, 'Amp': 13.0, 'Period': 2.4, 'Shape': 'snap'}])
    bm = bmesh.new()
    poly = [(-0.22, 6.84), (-0.18, 6.78), (-0.11, 6.82), (-0.03, 6.78), (0.05, 6.82), (0.12, 6.78), (0.20, 6.82),
            (0.22, 6.875), (-0.22, 6.875)]
    top = [bm.verts.new(surf(x, d, 0.04)) for x, d in poly]
    bot = [bm.verts.new(surf(x, d, -0.02)) for x, d in poly]
    bm.faces.new(top)
    bm.faces.new(bot[::-1])
    m_ = len(poly)
    for i in range(m_):
        bm.faces.new((top[i], bot[i], bot[(i + 1) % m_], top[(i + 1) % m_]))
    _finish(bm)
    k.add('Jaw', k.mesh_object('Jaw', bm, ['Jaw']))

# =============================================================================================
# Jack-o'-Lantern pocket finisher: `jack_o_lantern_pocket` (the laughing jack)
# =============================================================================================

def _grin(x):
    """The mouth's lower and upper edges (z) at lateral x, with teeth."""
    u = min(1.0, abs(x) / 0.62)
    tooth = abs(((x / 0.17) % 1.0) - 0.5) * 2      # 0..1 triangle wave
    lower = 0.60 + 0.22 * u * u + 0.09 * tooth
    upper = 0.96 + 0.14 * u * u - 0.07 * (1 - tooth)
    return lower, upper


def _in_eye(x, z):
    for sx in (-1, 1):
        ax, bx, cx = sx * 0.52, sx * 0.16, sx * 0.34
        az, bz, cz = 1.30, 1.30, 1.64
        # barycentric inside test
        def sgn(px, pz, qx, qz, rx, rz):
            return (px - rx) * (qz - rz) - (qx - rx) * (pz - rz)
        d1, d2, d3 = sgn(x, z, ax, az, bx, bz), sgn(x, z, bx, bz, cx, cz), sgn(x, z, cx, cz, ax, az)
        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
            return True
    return False


@piece
def jack_o_lantern_pocket(k):
    """The pocket finisher's jack-o'-lantern: a ribbed orange pumpkin shell 1.9 studs tall with
    its triangle eyes and jagged grin cut out and a Neon core glowing through them, the lower
    grin a jaw on a snapping hinge (the laugh), the head wobbling slowly, a curly stem on top."""
    import bmesh
    from mathutils import Vector
    k.frame = 'pocket'
    k.upright = True   # face and jaw stay where they were built (CuePiece's half turn skipped)
    k.material('Shell', 'SmoothPlastic', '#FF7A1C', Reflectance=0.08)
    k.material('Core', 'Neon', '#FFC34D')
    k.material('Stem', 'SmoothPlastic', '#2F5A2A')
    k.joint('Skull', pivot=(0, 0, 0.5), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 3.0, 'Period': 2.2, 'Phase': 40}])
    k.joint('Jaw', pivot=(0, 0.0, 0.74), parent='Skull', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 9.0, 'Amp': 9.0, 'Period': 0.28, 'Shape': 'snap'}])
    k.joint('Core', pivot=(0, 0, 1.0), parent='Skull', visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.5, 'Period': 0.45}])
    zc, hz, rr = 1.0, 0.92, 1.02
    segs, nrows = 64, 40

    def shell_rows(scale):
        out = []
        for i in range(nrows + 1):
            z = zc - hz * scale + 2 * hz * scale * i / nrows
            u = (z - zc) / (hz * scale)
            out.append((z, rr * scale * math.sqrt(max(0.0, 1 - u * u))))
        return out

    def build_sphere(bm, rows_, ribs, uv=None):
        # a revolve about Z: reuse _revolve by building along -Y then turning Y to Z
        from mathutils import Matrix
        rows_y = [(-z, r) for z, r in rows_]       # d = -z so that -d = z ... turned below
        rings = _revolve(bm, [(zr, r) for zr, r in [(-z, r) for z, r in rows_]], segs, rib=(lambda d: (8, ribs)) if ribs else None)
        # the revolve put the axis along -Y with d = -z, i.e. y = z: turn y -> z
        M = Matrix.Rotation(math.radians(90), 4, 'X')  # (x, y, z) -> (x, -z, y): y becomes z
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
        return rings
    # the shell
    bm = bmesh.new()
    build_sphere(bm, shell_rows(1.0), 0.06)
    # cut the face out of the front (-Y) and split the jaw off
    kill, jaw = [], []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y < 0:
            x, z = c.x, c.z
            lower, upper = _grin(x)
            if _in_eye(x, z) or (abs(x) < 0.62 and lower < z < upper):
                kill.append(f)
            elif (abs(x) < 0.62 and z < lower) or (abs(x) >= 0.62 and z < 0.60 + 0.22 and abs(x) < 0.9):
                jaw.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    jaw_set = set(jaw) - set(kill)
    bm_j = bmesh.new()
    jv = {}
    for f in list(bm.faces):
        if f in jaw_set:
            vs = []
            for v in f.verts:
                key = tuple(round(c, 5) for c in v.co)
                if key not in jv:
                    jv[key] = bm_j.verts.new(v.co)
                vs.append(jv[key])
            bm_j.faces.new(vs)
    bmesh.ops.delete(bm, geom=list(jaw_set), context='FACES')
    _finish(bm)
    _finish(bm_j)
    k.add('Skull', k.mesh_object('Shell', bm, ['Shell']))
    k.add('Jaw', k.mesh_object('JawShell', bm_j, ['Shell']))
    # the glowing core
    bm = bmesh.new()
    rows_c = [(zc + (z - zc) * 0.94, r * 0.94) for z, r in shell_rows(1.0)]
    segs_save = segs
    segs = 32
    build_sphere(bm, rows_c[::2] + [rows_c[-1]] if len(rows_c) % 2 == 0 else rows_c[::2], 0.0)
    segs = segs_save
    _finish(bm)
    k.add('Core', k.mesh_object('Core', bm, ['Core']))
    # the stem
    bm = bmesh.new()
    _curl(bm, [(0, 0, zc + hz - 0.06), (0, -0.02, zc + hz + 0.08), (0, -0.09, zc + hz + 0.2), (0, -0.2, zc + hz + 0.27), (0, -0.3, zc + hz + 0.25), (0, -0.34, zc + hz + 0.16)],
          [0.1, 0.09, 0.08, 0.065, 0.05, 0.035], segs=10)
    _finish(bm)
    k.add('Skull', k.mesh_object('Stem', bm, ['Stem']))


# =============================================================================================
# Headless previews of a body beside nothing but itself (the shared cue hidden)
# =============================================================================================

def body_preview(pid, out_dir=None):
    """pieces/<pid>/preview.png: the body alone (the plain cue hidden), from the side, three
    quarter from above-behind, the butt close and the joint close. Blender side."""
    import bpy
    import cue_common as cc
    from mathutils import Vector
    from CuePieces import attach, stitch
    cc.clear_scene('BodyPreview')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.06, 0.03, 0.10, 1)
    bg.inputs[1].default_value = 1.0
    scene.world = world
    cue = cc.load_cue_object()
    cue.hide_render = True
    for loc, e in (((3, -4, 6), 2.5), ((-4, -9, 3), 2.0), ((2, -10, -3), 1.0), ((-3, 1, 3), 1.2)):
        ld = bpy.data.lights.new('L', 'AREA')
        ld.energy = 300 * e
        ld.size = 4
        lo = bpy.data.objects.new('L', ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, -5.0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    animate = attach(bpy, pid, cue)
    animate(0.0)
    cam_d = bpy.data.cameras.new('C')
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 900, 560
    out = os.path.join(PIECES_DIR, pid)
    import json
    frame = json.load(open(os.path.join(out, 'piece.json'))).get('Frame', 'cue')
    if frame == 'pocket':
        # the pocket piece stands at the origin, Z up, its front toward -Y
        views = (((0, -5.2, 1.3), (0, 0, 1.0), 45), ((3.4, -4.2, 2.2), (0, 0, 1.0), 45),
                 ((0, -2.6, 1.1), (0, 0, 1.05), 50), ((-3.6, 3.0, 2.0), (0, 0, 1.0), 45))
    else:
        views = (((8.3, -3.55, 0.9), (0, -3.55, 0.0), 42),      # the whole cue from the side
                 ((3.0, -10.2, 2.3), (0, -4.6, 0.0), 42),        # three quarter from above-behind
                 ((1.5, -7.75, 0.7), (0, -6.75, 0.05), 50),      # the butt
                 ((1.25, -4.5, 0.55), (0, -3.75, 0.02), 50),     # the joint
                 ((1.1, -0.85, 0.5), (0, -0.55, 0.0), 50),       # the tip
                 ((-3.0, -8.6, 1.6), (0, -5.6, 0.0), 42))        # three quarter from the other side
    for vi, (loc, tgt, lens) in enumerate(views):
        cam.location = loc
        cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        cam_d.lens = lens
        scene.render.filepath = os.path.join(out, '_v%d_0.png' % vi)
        bpy.ops.render.render(write_still=True)
    try:
        stitch(pid)  # Blender's Python has no Pillow: then `python3 assets/cue/CuePieces.py --sheet <pid>` joins the tiles
    except ImportError:
        print('CUE pieces body preview: tiles rendered; stitch with python3 assets/cue/CuePieces.py --sheet', pid)
        return
    if out_dir:
        import shutil
        os.makedirs(out_dir, exist_ok=True)
        shutil.copy(os.path.join(out, 'preview.png'), os.path.join(out_dir, pid + '_preview.png'))
    print('CUE pieces body preview', os.path.join(out, 'preview.png'))


# ---------------------------------------------------------------------------------------------
# Candy Corn sprites: the tumbling kernel flipbook (Blender, real materials) and the sprinkle
# rods sheet (Pillow). `-- --sprites` under Blender renders the kernel frames; `--sheets` under
# the system python joins them (CuePieces.sheet_sprite) and draws the rods.
# ---------------------------------------------------------------------------------------------

VFX_DIR = os.path.join(os.path.dirname(PIECES_DIR), 'vfx', 'candy_corn')
KERNEL_PROFILE = [(0.0, 0.04), (0.035, 0.038), (0.07, 0.03), (0.10, 0.018), (0.125, 0.008), (0.13, 0.0)]


def kernel_sprite(frames=16, px=240):
    """vfx/candy_corn/_frames_kernel/NN.png: one candy-corn kernel (the body's profile and
    palette) tumbling end over end on a transparent film, lit like the lobby, for the aura's
    floating kernels, the trail and the finisher. Blender side."""
    import bpy
    import bmesh
    import cue_common as cc
    from mathutils import Euler, Vector
    cc.clear_scene('KernelSprite')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_x = scene.render.resolution_y = px
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (1, 1, 1, 1)
    bg.inputs[1].default_value = 0.6
    scene.world = world
    # the kernel, standing on +Z at the origin, UV v along its length (the palette's bands)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    rings = []
    for t, r in KERNEL_PROFILE:
        if r <= 1e-6:
            rings.append(([bm.verts.new(Vector((0, 0, t - 0.065)))], t))
            continue
        ring = [bm.verts.new(Vector((r * math.cos(2 * math.pi * s_ / 10), r * math.sin(2 * math.pi * s_ / 10), t - 0.065)))
                for s_ in range(10)]
        rings.append((ring, t))
    c0 = bm.verts.new(Vector((0, 0, -0.065)))
    r0 = rings[0][0]
    for s_ in range(10):
        f = bm.faces.new((c0, r0[(s_ + 1) % 10], r0[s_]))
        for lp in f.loops:
            lp[uvl].uv = (0.5, 0.02)
    for i in range(len(rings) - 1):
        (ra, ta), (rb, tb) = rings[i], rings[i + 1]
        for s_ in range(10):
            if len(rb) == 1:
                f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[0]))
                ts = (ta, ta, tb)
            else:
                f = bm.faces.new((ra[s_], ra[(s_ + 1) % 10], rb[(s_ + 1) % 10], rb[s_]))
                ts = (ta, ta, tb, tb)
            for lp, tt in zip(f.loops, ts):
                lp[uvl].uv = (0.5, 0.04 + 0.92 * tt / 0.13)
    _finish(bm)
    me = bpy.data.meshes.new('Kernel')
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    mat = bpy.data.materials.new('KernelSprite')
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new('ShaderNodeTexImage')
    kernel_palette()
    tex.image = bpy.data.images.load(os.path.join(VFX_DIR, 'kernel_palette.png'))
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.35
    me.materials.append(mat)
    pivot = bpy.data.objects.new('Pivot', None)
    scene.collection.objects.link(pivot)
    pivot.rotation_euler = Euler((math.radians(62), 0, math.radians(20)))   # the tumble axis, tilted to the camera
    ob = bpy.data.objects.new('Kernel', me)
    scene.collection.objects.link(ob)
    ob.parent = pivot
    for loc, e in (((1.5, -2.5, 3.0), 2.0), ((-2.5, -2.0, 1.0), 0.9), ((1.0, 2.5, -1.0), 0.5)):
        ld = bpy.data.lights.new('L', 'AREA')
        ld.energy = 60 * e
        ld.size = 2.5
        lo = bpy.data.objects.new('L', ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam_d = bpy.data.cameras.new('C')
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 0.17
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (0, -3, 0.35)
    cam.rotation_euler = (Vector((0, 0, 0)) - Vector(cam.location)).to_track_quat('-Z', 'Z').to_euler()
    out = os.path.join(VFX_DIR, '_frames_kernel')
    os.makedirs(out, exist_ok=True)
    for i in range(frames):
        ob.rotation_euler = Euler((2 * math.pi * i / frames, 0, 0))   # end over end about the pivot's X
        scene.render.filepath = os.path.join(out, '%02d.png' % i)
        bpy.ops.render.render(write_still=True)
    print('CUE kernel sprite frames', out)


def rods_sheet(size=1024, grid=4, pad=8):
    """vfx/candy_corn/rods_4x4.png: sixteen sprinkle rods, white, orange and yellow in turn,
    each at its own angle (held still per particle: FlipbookFramerate 0, a random start).
    System python (Pillow)."""
    from PIL import Image, ImageDraw, ImageFilter
    import random
    rnd = random.Random(8)
    colours = [((255, 255, 255), (228, 222, 210)), ((255, 122, 18), (200, 84, 6)), ((255, 210, 30), (208, 160, 10))]
    cell = size // grid
    inner = cell - 2 * pad
    sheet = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    big = inner * 2
    for i in range(grid * grid):
        light, dark = colours[i % 3]
        im = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        dr = ImageDraw.Draw(im)
        length, width = int(big * 0.66), int(big * 0.17)
        x0, y0 = (big - length) // 2, (big - width) // 2
        dr.rounded_rectangle((x0, y0, x0 + length, y0 + width), radius=width // 2, fill=dark + (255,))
        dr.rounded_rectangle((x0 + 3, y0 + 2, x0 + length - 3, y0 + width - width // 3), radius=width // 2, fill=light + (255,))
        hl = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        ImageDraw.Draw(hl).rounded_rectangle((x0 + width // 2, y0 + width // 5, x0 + length - width // 2, y0 + width // 2), radius=width // 4, fill=(255, 255, 255, 110))
        hl = hl.filter(ImageFilter.GaussianBlur(3))
        im.alpha_composite(hl)
        im = im.rotate(rnd.uniform(0, 180), resample=Image.BICUBIC, expand=False)
        im = im.resize((inner, inner), Image.LANCZOS)
        r, c = divmod(i, grid)
        sheet.paste(im, (c * cell + pad, r * cell + pad))
    os.makedirs(VFX_DIR, exist_ok=True)
    path = os.path.join(VFX_DIR, 'rods_4x4.png')
    sheet.save(path, optimize=True)
    print('CUE rods sheet', path)
    return path


JACK_VFX_DIR = os.path.join(os.path.dirname(PIECES_DIR), 'vfx', 'jack_o_lantern')


def _set_emission(mat, strength):
    """Every emission input of a material's nodes (looked up by type, never by name)."""
    if not mat.use_nodes:
        return
    for node in mat.node_tree.nodes:
        if node.type == 'EMISSION':
            node.inputs['Strength'].default_value = strength
        elif node.type == 'BSDF_PRINCIPLED' and 'Emission Strength' in node.inputs:
            node.inputs['Emission Strength'].default_value = strength


def jack_sprite(frames=16, px=240):
    """vfx/jack_o_lantern/_frames_jack/NN.png: the pocket piece's jack-o'-lantern seen from the
    front with its Neon face flickering like a candle and the head swaying a little: the aura's
    floating mini jacks, the trail flecks and the finisher's popping jacks. Blender side."""
    import bpy
    import cue_common as cc
    from mathutils import Euler, Vector
    from CuePieces import attach
    cc.clear_scene('JackSprite')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.resolution_x = scene.render.resolution_y = px
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (1, 0.85, 0.7, 1)
    bg.inputs[1].default_value = 0.35
    scene.world = world
    root = bpy.data.objects.new('Root', None)
    scene.collection.objects.link(root)
    animate = attach(bpy, 'jack_o_lantern_pocket', root)
    assert animate is not None, 'build jack_o_lantern_pocket first'
    animate(0.0)
    cores = [m for m in bpy.data.materials if 'jack_o_lantern_pocket' in m.name and m.name.endswith('_Core')]
    for loc, e in (((2.5, -4.0, 3.0), 1.6), ((-3.0, -3.0, 1.2), 0.7)):
        ld = bpy.data.lights.new('L', 'AREA')
        ld.energy = 220 * e
        ld.size = 3
        lo = bpy.data.objects.new('L', ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam_d = bpy.data.cameras.new('C')
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = 2.7
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = (0, -9, 1.15)
    cam.rotation_euler = (Vector((0, 0, 1.0)) - Vector(cam.location)).to_track_quat('-Z', 'Z').to_euler()
    # a candle: an irregular flicker that never repeats inside the sheet
    flicker = [0.55, 0.9, 1.0, 0.7, 0.35, 0.8, 1.0, 0.95, 0.6, 0.25, 0.7, 1.0, 0.85, 0.5, 0.9, 0.65]
    out = os.path.join(JACK_VFX_DIR, '_frames_jack')
    os.makedirs(out, exist_ok=True)
    for i in range(frames):
        for m in cores:
            _set_emission(m, 2.0 + 6.0 * flicker[i])
        a = 2 * math.pi * i / frames
        root.rotation_euler = Euler((math.radians(3.0 * math.sin(a * 2)), math.radians(2.0 * math.cos(a)), math.radians(7.0 * math.sin(a))))
        scene.render.filepath = os.path.join(out, '%02d.png' % i)
        bpy.ops.render.render(write_still=True)
    print('CUE jack sprite frames', out)


def sheets():
    """System python: join the rendered frames into their 4x4 sheets and draw the rods sheet."""
    from CuePieces import sheet_sprite
    if os.path.isdir(os.path.join(VFX_DIR, '_frames_kernel')):
        sheet_sprite('kernel', 'candy_corn')
    if os.path.isdir(os.path.join(JACK_VFX_DIR, '_frames_jack')):
        sheet_sprite('jack', 'jack_o_lantern')
    rods_sheet()


def main():
    import sys
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if '--sprites' in argv:   # --sprites [kernel] [jack]: both when no name follows
        names = [a for a in argv[argv.index('--sprites') + 1:] if not a.startswith('--')] or ['kernel', 'jack']
        if 'kernel' in names:
            kernel_sprite()
        if 'jack' in names:
            jack_sprite()
        return
    if '--sheets' in argv:
        sheets()
        return
    if '--preview' in argv:
        i = argv.index('--preview')
        out_dir = argv[argv.index('--out') + 1] if '--out' in argv else None
        body_preview(argv[i + 1], out_dir)
        return
    from CuePieces import build
    for pid in (a for a in argv if not a.startswith('--')):
        build(pid, render_preview=False)


if __name__ == '__main__':
    main()
