"""The Ghost Lantern Cue (GhostLanternCue; the catalog already had a Rare PhantomCue, Halloween 2026 track step 150; lane Cues A, 2026-10-28, to the
concept card ~/Desktop/8ball-refs/halloween/mocks/v2/C6_phantom.png): drawn by its own body
`ghost_lantern` (a translucent cyan glass shaft lit by a Neon core, a dark iron chain spiralling
between the hands, a ghost lantern past the butt with a little ghost glowing inside), the
decor `ghost_lantern_aura` (three cute ghosts drifting round the shaft) and the finisher
`ghost_lantern_pocket` (ghosts swirling up out of the pocket). The ghost is a Meshy model
(assets/cue/models/ghost, from an OpenAI front view) worn through Kit.model. Modelled in the
cue's Blender frame (X the side, Y from the tip (0) toward the butt (-7), Z up); the finisher
in the pocket frame (origin at the mouth, Z up, the front toward -Y).

    ghost_lantern          the body: leather tip, glass tube to the butt, the Neon core, two iron
                     bands with the chain between the hands, the ghost lantern (Aim fade)
    ghost_lantern_aura     three ghosts on a racetrack round the shaft (Lower effects keeps one)
    ghost_lantern_pocket   four ghosts spiralling up out of the pocket

Build (headless Blender): CuePieces.py -- ghost_lantern ghost_lantern_aura ghost_lantern_pocket --no-preview.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from CuePieces import piece, assign_by_region, sweep  # noqa: E402
from CuePiecesHalloween_A import envelope, check_body, _revolve, _rows, _finish  # noqa: E402

PHANTOM = {'Tip': '#D8D1C2', 'Glass': '#2FC8F0', 'Core': '#1FD8FF', 'Iron': '#22232B', 'Lantern': '#B5F4FF'}   # a deep, saturated cyan, nothing like the live Rare Phantom's pale teal tube (coordinator 19:12)
GHOST_TINT = '#8FE8FF'          # the ghosts' emissive tint: a soft cyan glow so white ghosts never vanish on the white floor
LANTERN_AT = 7.5                # the lantern cage's centre along the cue (the butt is at 7.0; the cage is past it, an Aim-fade joint)


def _ghost_glow(px):
    """Emissive mask from the ghost's colour map: the white sheet glows, the eyes and mouth do not."""
    import numpy as np
    lum = px.mean(axis=2)
    return np.clip((lum - 0.6) / 0.3, 0.0, 1.0)


# =============================================================================================
# Geometry helpers (bmesh, Blender cue frame)
# =============================================================================================

def _torus(bm, centre, u, v, R, r, nmaj=8, nmin=4):
    """A ring at `centre` in the plane of unit axes u and v: major radius R, tube radius r."""
    from mathutils import Vector
    c, u, v = Vector(centre), Vector(u).normalized(), Vector(v).normalized()
    n = u.cross(v).normalized()
    rings = []
    for i in range(nmaj):
        a = 2 * math.pi * i / nmaj
        radial = u * math.cos(a) + v * math.sin(a)
        ring = []
        for j in range(nmin):
            b = 2 * math.pi * j / nmin
            ring.append(bm.verts.new(c + radial * (R + r * math.cos(b)) + n * (r * math.sin(b))))
        rings.append(ring)
    for i in range(nmaj):
        A, B = rings[i], rings[(i + 1) % nmaj]
        for j in range(nmin):
            bm.faces.new((A[j], B[j], B[(j + 1) % nmin], A[(j + 1) % nmin]))


def _chain(bm, R, d0, d1, turns, link_R=0.1, link_r=0.03, pitch=0.17, lift=0.0, tilt=15.0, phase=0.0):
    """Iron links along a helix round the shaft from d0 to d1 (`turns` round): each link lies on
    the glass tilted `tilt` degrees about the helix tangent, alternately in and out, so the run
    reads as a chain (thick links, coordinator 18:31) while staying inside the side clearance
    (the link's outward reach is (link_R + link_r) * sin(tilt) + link_r * cos(tilt) + lift: 0.063)."""
    import bisect
    from mathutils import Vector

    def at(s):
        d = d0 + (d1 - d0) * s
        a = phase + 2 * math.pi * turns * s
        radial = Vector((math.sin(a), 0.0, math.cos(a)))
        return Vector((0.0, -d, 0.0)) + radial * (R(d) + lift), radial

    N = 600
    pts = [at(i / N)[0] for i in range(N + 1)]
    seg = [(pts[i + 1] - pts[i]).length for i in range(N)]
    cum = [0.0]
    for s_ in seg:
        cum.append(cum[-1] + s_)
    L = cum[-1]
    n_links = int(L / pitch)
    for i in range(n_links):
        s_len = (i + 0.5) * pitch
        k_ = min(max(bisect.bisect_right(cum, s_len) - 1, 0), N - 1)
        f = (s_len - cum[k_]) / max(seg[k_], 1e-9)
        s = (k_ + f) / N
        p, radial = at(s)
        p2, _ = at(min(s + 0.002, 1.0))
        p1, _ = at(max(s - 0.002, 0.0))
        tang = (p2 - p1).normalized()
        side = tang.cross(radial).normalized()
        ang = math.radians(tilt if i % 2 == 0 else -tilt)
        v = (side * math.cos(ang) + radial * math.sin(ang)).normalized()
        _torus(bm, p, tang, v, link_R, link_r)


def _ghost_track(R, d0, d1, lift, step=0.1):
    """The ghosts' racetrack round the shaft: along the top from the butt toward the tip, half a
    turn round at the tip end, back along the belly, half a turn round at the butt end, `lift`
    off the surface. Frames (columns side, tangent, normal away from the cue, point) every
    `step` studs; returns (frames, step, length)."""
    import numpy as np

    def at(d, a):
        return np.array([math.sin(a) * (R(d) + lift), -d, math.cos(a) * (R(d) + lift)])

    samples = []
    N = 300
    for i in range(N):                       # the top leg: d1 -> d0 at a = 0 (+Z)
        d = d1 - (d1 - d0) * i / (N - 1)
        samples.append((at(d, 0.0), 0.0))
    for i in range(1, 30):                   # round the tip end to the belly
        a = math.pi * i / 30
        samples.append((at(d0, a), a))
    for i in range(N):                       # the belly leg: d0 -> d1 at a = pi
        d = d0 + (d1 - d0) * i / (N - 1)
        samples.append((at(d, math.pi), math.pi))
    for i in range(1, 30):                   # round the butt end back to the top
        a = math.pi + math.pi * i / 30
        samples.append((at(d1, a), a))
    P = np.array([s[0] for s in samples])
    A = np.array([s[1] for s in samples])
    Pc = np.vstack([P, P[:1]])
    Ac = np.concatenate([A, [2 * math.pi]])
    seg = np.linalg.norm(np.diff(Pc, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    L = float(cum[-1])
    nF = max(int(round(L / step)), 8)
    frames = []
    for j in range(nF):
        sj = j * L / nF
        p = np.array([np.interp(sj, cum, Pc[:, c]) for c in range(3)])
        a = float(np.interp(sj, cum, Ac))
        p2 = np.array([np.interp((sj + 0.05) % L, cum, Pc[:, c]) for c in range(3)])
        p1 = np.array([np.interp((sj - 0.05) % L, cum, Pc[:, c]) for c in range(3)])
        tang = p2 - p1
        tang /= np.linalg.norm(tang)
        nrm = np.array([math.sin(a), 0.0, math.cos(a)])
        nrm -= tang * float(nrm @ tang)
        nrm /= np.linalg.norm(nrm)
        side = np.cross(tang, nrm)
        M = np.eye(4)
        M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = side, tang, nrm, p
        frames.append(M)
    return frames, L / nF, L


def _ghost_place(height, basis):
    """place() for Kit.model: the Meshy ghost (imported Z up, its front toward -Y) scaled to
    `height` studs tall, centred, turned so its front is +Y of `basis` and its up +Z, then put
    where `basis` (a 4x4) says."""
    import numpy as np
    from mathutils import Matrix

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s = height / float(hi[2] - lo[2])
        centre = Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -(lo[2] + hi[2]) / 2))
        return basis @ Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(s, 4) @ centre
    return place


# =============================================================================================
# The body: `phantom`
# =============================================================================================

@piece
def ghost_lantern(k):
    """The Ghost Lantern Cue's body (v3, coordinator 19:12: everything bigger): a leather tip and
    pale ferrule (one part), the shaft a deep cyan glass tube end to end with a pure cyan Neon
    core inside it pulsing, three real iron collars (2.14, 4.18 and 6.80, the butt one widest)
    with a thick iron chain (0.2-stud links) spiralling between the first two (the hand zones 0.3-2.1 and 4.4-6.75 keep the
    envelope, brief 2.6: a hand must not sink into links), and past the butt the ghost lantern,
    an Aim-fade joint about twice the v2 size: an iron neck and cap, a six-bar cage 0.9 studs
    across with rings, a candle rod flickering, a Meshy ghost 0.62 studs tall bobbing and
    turning inside, an iron knob and a hanging ring (reaching 1.38 studs past the butt, under
    the 1.5 an Aim joint may). Seven parts."""
    import bmesh
    from mathutils import Matrix
    R = envelope()
    k.material('Tip', 'SmoothPlastic', PHANTOM['Tip'], Reflectance=0.0)
    k.material('Glass', 'SmoothPlastic', PHANTOM['Glass'], Transparency=0.25, Reflectance=0.3)
    k.material('Core', 'Neon', PHANTOM['Core'], Transparency=0.0)
    k.material('Iron', 'Metal', PHANTOM['Iron'], Reflectance=0.4)
    k.material('Lantern', 'Neon', PHANTOM['Lantern'], Transparency=0.3)

    # --- the shaft: tip + ferrule (Tip) to 0.30, the glass tube to the lantern neck ----------
    k.joint('Body', pivot=(0, -3.5, 0))
    tube = _rows(0.30, 6.72, R, 0.15)
    rows = [(0.0, 0.0)] + _rows(0.0, 0.30, R, 0.05)[1:] + tube[1:] + [(6.725, 0.0)]
    bm = bmesh.new()
    _revolve(bm, rows, 20)
    _finish(bm)
    ob = k.mesh_object('Shaft', bm, ['Tip', 'Glass'])
    assign_by_region(ob, lambda c, n: 0 if -c[1] < 0.30 else 1)
    k.add('Body', ob)

    # --- the Neon core inside the glass, pulsing ---------------------------------------------
    k.joint('Core', pivot=(0, -3.5, 0), visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.35, 'Period': 2.8}])
    # the core's rows sit on the tube's rows (check_body samples by 0.1-stud bin: a bin holding
    # only core vertices would read as the hand sinking in)
    core = [(tube[1][0], 0.0)] + [(d, 0.55 * R(d)) for d, _ in tube[2:-1]] + [(tube[-1][0] - 0.005, 0.0)]
    bm = bmesh.new()
    _revolve(bm, core, 12)
    _finish(bm)
    k.add('Core', k.mesh_object('Core', bm, ['Core']))

    # --- three iron collars and the chain ---------------------------------------------------
    bm = bmesh.new()
    for d_a, d_b, proud in ((2.14, 2.32, 0.07), (4.18, 4.36, 0.07), (6.80, 6.96, 0.10)):
        _revolve(bm, [(d_a, R(d_a) - 0.01), (d_a + 0.02, R(d_a) + proud), (d_b - 0.02, R(d_b) + proud), (d_b, R(d_b) - 0.01)], 20)
    _chain(bm, R, 2.36, 4.14, turns=1.75)                       # between the hands
    _finish(bm)
    k.add('Body', k.mesh_object('Chain', bm, ['Iron']))

    # --- the ghost lantern past the butt (Aim fade) ------------------------------------------
    k.joint('Lantern', pivot=(0, -7.0, 0), aim='fade',
            motion=[{'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 1.5, 'Period': 3.3}])
    bm = bmesh.new()
    # the neck (inside the butt zone's +0.2) and the top cap (past the butt, free)
    _revolve(bm, [(6.72, R(6.72)), (6.80, 0.22), (6.96, 0.24), (6.99, 0.34), (7.06, 0.46), (7.12, 0.46), (7.12, 0.40)], 20)
    _torus(bm, (0, -7.13, 0), (1, 0, 0), (0, 0, 1), 0.45, 0.03, 20, 6)
    _torus(bm, (0, -7.87, 0), (1, 0, 0), (0, 0, 1), 0.45, 0.03, 20, 6)
    for i in range(6):
        a = 2 * math.pi * i / 6
        x, z = 0.45 * math.sin(a), 0.45 * math.cos(a)
        sweep(bm, [(x, -7.12, z), (x * 1.06, -7.5, z * 1.06), (x, -7.88, z)], [0.03, 0.033, 0.03], segs=6, cap=False)
    _revolve(bm, [(7.87, 0.40), (7.87, 0.46), (7.94, 0.46), (8.04, 0.24), (8.10, 0.13), (8.16, 0.08), (8.18, 0.0)], 20)
    _torus(bm, (0, -8.27, 0), (0, 1, 0), (0, 0, 1), 0.09, 0.022, 12, 5)
    _finish(bm)
    k.add('Lantern', k.mesh_object('Cage', bm, ['Iron']))

    k.joint('LanternGlow', pivot=(0, -LANTERN_AT, 0), parent='Lantern', aim='fade',
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.4, 'Period': 1.9, 'Shape': 'flicker'}])
    bm = bmesh.new()
    # a thin candle rod up the middle (a full glow cylinder hid the ghost; the ghost glows itself)
    _revolve(bm, [(7.14, 0.0), (7.15, 0.09), (7.85, 0.09), (7.86, 0.0)], 10)
    _finish(bm)
    k.add('LanternGlow', k.mesh_object('LanternGlow', bm, ['Lantern']))

    k.joint('LanternGhost', pivot=(0, -LANTERN_AT, 0), parent='Lantern', aim='fade',
            motion=[{'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.04, 'Period': 1.7},
                    {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 14.0, 'Period': 3.4, 'Phase': 30}])
    # facing the side (+X): basis columns side = -Y, front = +X, up = +Z
    basis = Matrix(((0, 1, 0, 0), (-1, 0, 0, -LANTERN_AT), (0, 0, 1, 0), (0, 0, 0, 1)))
    k.model('LanternGhost', 'LanternGhost', 'ghost', _ghost_place(0.62, basis), target_tris=2500, texture_px=256,
            emissive=_ghost_glow, emissive_tint=GHOST_TINT, emissive_strength=0.25)
    check_body(k)


# =============================================================================================
# The decor: `ghost_lantern_aura`
# =============================================================================================

@piece
def ghost_lantern_aura(k):
    """Four cute ghosts (the Meshy model, a stud tall, glowing soft cyan) drifting round the
    shaft on a racetrack 0.58 studs off the glass: along the top toward the tip, under and
    back, a lap in nine seconds, each bobbing and rolling a little, opaque so the faces read. Aura joints (hidden on the owner's shot with the aura); Lower effects
    keeps two (the first and third)."""
    from mathutils import Matrix, Vector
    R = envelope()
    frames, step, L = _ghost_track(R, 1.2, 6.3, 0.58)
    k.path('Drift', frames, step)
    speed = L / 9.0
    for i, (share, low) in enumerate(((0.03, None), (0.28, 'hide'), (0.53, None), (0.78, 'hide'))):
        name = 'Ghost%d' % (i + 1)
        rest = share * L
        F = frames[int(round(rest / step)) % len(frames)]
        side, tang, nrm, pt = (Vector(F[:3, c]) for c in range(4))
        k.joint(name, pivot=tuple(pt), aura=True, low=low,
                motion=[{'Kind': 'Path', 'Path': 'Drift', 'Rest': rest, 'Speed': speed},
                        {'Kind': 'Bob', 'Dir': tuple(nrm), 'Amp': 0.06, 'Period': 1.6 + 0.3 * i, 'Phase': 110 * i},
                        {'Kind': 'Hinge', 'Axis': tuple(tang), 'Amp': 10.0, 'Period': 2.3 + 0.2 * i, 'Phase': 60 * i}])
        # opaque: a ghostly Fade washed them to white smears on the bright floor (gl_back_v3)
        basis = Matrix(((side.x, tang.x, nrm.x, pt.x), (side.y, tang.y, nrm.y, pt.y),
                        (side.z, tang.z, nrm.z, pt.z), (0, 0, 0, 1)))
        # 0.9 studs tall: half a stud read as specks from the lobby camera (gl_stand_v1, coordinator
        # 18:31: real 3D ghosts with readable faces, not specks)
        k.model(name, name, 'ghost', _ghost_place(1.0, basis), target_tris=1800, texture_px=256,
                emissive=_ghost_glow, emissive_tint=GHOST_TINT, emissive_strength=0.25)


# =============================================================================================
# The pocket finisher: `ghost_lantern_pocket`
# =============================================================================================

@piece
def ghost_lantern_pocket(k):
    """Four ghosts swirling up out of the pocket: a helix from the mouth, four turns over 3.6
    studs widening from 0.45 to 0.75 studs, a lap in three seconds, the ghosts starting at the
    first quarter of it (none reaches the top before the finisher fades), each bobbing and
    facing the way it flies."""
    import numpy as np
    from mathutils import Matrix, Vector
    k.frame = 'pocket'
    k.upright = True
    nF = 160
    frames = []
    for j in range(nF):
        s = j / nF
        z = 3.6 * s
        a = 2 * math.pi * 4 * s
        r = 0.45 + 0.30 * s
        p = np.array([r * math.sin(a), r * math.cos(a), z])
        s2 = (j + 1) / nF
        p2 = np.array([(0.45 + 0.30 * s2) * math.sin(2 * math.pi * 4 * s2), (0.45 + 0.30 * s2) * math.cos(2 * math.pi * 4 * s2), 3.6 * s2])
        tang = p2 - p
        tang /= np.linalg.norm(tang)
        nrm = np.array([0.0, 0.0, 1.0])
        nrm -= tang * float(nrm @ tang)
        nrm /= np.linalg.norm(nrm)
        side = np.cross(tang, nrm)
        M = np.eye(4)
        M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = side, tang, nrm, p
        frames.append(M)
    seg = [float(np.linalg.norm(frames[(j + 1) % nF][:3, 3] - frames[j][:3, 3])) for j in range(nF - 1)]
    step = sum(seg) / (nF - 1)
    L = step * nF
    k.path('Swirl', frames, step)
    speed = L / 3.0
    for i, share in enumerate((0.0, 0.07, 0.14, 0.21)):
        name = 'Ghost%d' % (i + 1)
        rest = share * L
        F = frames[int(round(rest / step)) % nF]
        side, tang, nrm, pt = (Vector(F[:3, c]) for c in range(4))
        k.joint(name, pivot=tuple(pt),
                motion=[{'Kind': 'Path', 'Path': 'Swirl', 'Rest': rest, 'Speed': speed},
                        {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.05, 'Period': 0.7 + 0.1 * i, 'Phase': 90 * i}])
        basis = Matrix(((side.x, tang.x, nrm.x, pt.x), (side.y, tang.y, nrm.y, pt.y),
                        (side.z, tang.z, nrm.z, pt.z), (0, 0, 0, 1)))
        k.model(name, name, 'ghost', _ghost_place(0.9, basis), target_tris=900, texture_px=256,
                emissive=_ghost_glow, emissive_tint=GHOST_TINT, emissive_strength=0.6)


# =============================================================================================
# After the build: parts the cue's inked outline Highlight must skip (the runtime's part row
# `Outline = false`, as the Broom's straws): the chain's forty links each got an ink stroke in
# the lobby (gate2/gl_stand_v1.jpg, a white crust round the chain).
# =============================================================================================

NO_OUTLINE = {'ghost_lantern': ['Body_Iron']}


def patch_outline(pid):
    """Write `Outline: false` on the parts NO_OUTLINE names into the built piece.json."""
    import json
    from CuePieces import PIECES_DIR
    names = NO_OUTLINE.get(pid, ())
    if not names:
        return
    path = os.path.join(PIECES_DIR, pid, 'piece.json')
    spec = json.load(open(path))
    found = {part['Name'] for part in spec['Parts']}
    for n in names:
        if n not in found:
            raise RuntimeError('CUE patch_outline FAIL %s: NO_OUTLINE names part %s, which the piece has not got' % (pid, n))
    for part in spec['Parts']:
        if part['Name'] in names:
            part['Outline'] = False
    with open(path, 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    print('CUE patch_outline %s: %s' % (pid, ', '.join(names)))


if __name__ == '__main__':
    # python3 assets/cue/CuePiecesGhostLantern.py --patch-outline   (plain Python, after the build)
    if '--patch-outline' in sys.argv:
        for pid in NO_OUTLINE:
            patch_outline(pid)
