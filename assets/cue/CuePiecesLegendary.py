"""The Legendary set pieces (scripted modelling; see CuePieces.py for the kit and export).

Set pieces that were camera-facing flipbooks look like flat cut-outs from most angles
(designer, 2026-09-30), so they are real 3D parts that move: the Phoenix's wings of flame.

Every piece is modelled in the cue's Blender frame: X is the side, Y runs from the tip (0) to
the butt (-7), Z is the top.
"""
import math

from CuePieces import piece


def _blade(bm, root, direction, plane_n, length, width, thick, mats, steps=12, curl=0.0, wave=0.0,
           phase=0.0):
    """One flame feather: a flat blade with a lens-shaped section along a curved centreline.

    root, direction (unit, along the feather) and plane_n (unit, the wing plane's normal) are
    Vectors. The blade is widest at a third of its length and ends in a point; curl lifts the tip
    out of the plane (a flame flick), wave bends it sideways in an S. mats = [(s_end, index), ...]
    gives the material index of each stretch along the feather (root crimson to gold tip)."""
    side = direction.cross(plane_n).normalized()
    rings = []
    for i in range(steps + 1):
        s = i / steps
        c = (root + direction * (length * s) + plane_n * (curl * length * s * s)
             + side * (wave * length * math.sin(math.pi * s + phase) * s))
        w = width * (math.sin(math.pi * min(s / 0.34, 1.0) * 0.5) if s < 0.34 else (1 - (s - 0.34) / 0.66) ** 0.8)
        w = max(w, 0.004) if i < steps else 0.002
        t = thick * (1 - 0.7 * s) if i < steps else 0.001
        ring = [c + side * w, c + side * (0.5 * w) + plane_n * t, c - side * (0.5 * w) + plane_n * t,
                c - side * w, c - side * (0.5 * w) - plane_n * t, c + side * (0.5 * w) - plane_n * t]
        rings.append([bm.verts.new(p) for p in ring])

    def index(s):
        for s_end, idx in mats:
            if s <= s_end:
                return idx
        return mats[-1][1]

    for i in range(steps):
        idx = index((i + 0.5) / steps)
        a, b = rings[i], rings[i + 1]
        for k in range(6):
            f = bm.faces.new((a[k], a[(k + 1) % 6], b[(k + 1) % 6], b[k]))
            f.material_index = idx
    cap = bm.faces.new(list(reversed(rings[0])))
    cap.material_index = mats[0][1]


@piece
def phoenix(k):
    """Two great wings of flame on the cue at the forearm's end (4.4 studs from the tip), spread
    wide and swept back toward the butt: each wing a fan of flame feathers (long primaries off
    the wrist, secondaries along the arm, a layer of short coverts), crimson at the root through
    orange to a glowing gold tip, the tips flicking up like flames. The wings beat slowly; the
    primaries follow a beat behind (a whip)."""
    import bmesh
    from mathutils import Vector
    k.material('Crimson', 'Neon', '#B8141A', Transparency=0.05)
    k.material('Ember', 'Neon', '#E8361A', Transparency=0.08)
    k.material('Flame', 'Neon', '#FF6A14', Transparency=0.1)
    k.material('Amber', 'Neon', '#FF9A28', Transparency=0.12)
    k.material('Gold', 'Neon', '#FFD04A', Transparency=0.18)
    CRIMSON, EMBER, FLAME, AMBER, GOLD = range(5)
    names = ['Crimson', 'Ember', 'Flame', 'Amber', 'Gold']

    AT = 4.4                                     # the wings' root on the cue
    # the root sits just on the surface (0.002 out): it follows the cue's width (Shape.json;
    # (0.07, 0.06) on the 0.2 cue)
    import cue_common as cc
    env = cc.Envelope(cc.load_shape()[0])
    lift = (float(env(AT)) + 0.002) / math.hypot(0.07, 0.06)
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        root = Vector((0.07 * side * lift, -AT, 0.06 * lift))
        # the wing's arm: out, up and swept back toward the butt (-Y)
        arm = Vector((side * 1.0, -0.4, 0.38)).normalized()
        L_arm = 1.25
        wrist = root + arm * L_arm
        # the wing plane: holds the arm and the backward direction
        back = Vector((0, -1, -0.15)).normalized()
        plane_n = arm.cross(back).normalized()
        if plane_n.z < 0:
            plane_n = -plane_n

        wing = 'Wing' + sname
        tipj = 'Primaries' + sname
        flap_axis = (0, 1 * side, 0)             # about the cue: both wings rise together
        k.joint(wing, pivot=tuple(root), motion=[
            {'Kind': 'Hinge', 'Axis': flap_axis, 'Base': 0.0, 'Amp': 16.0, 'Period': 1.8}])
        k.joint(tipj, pivot=tuple(wrist), parent=wing, motion=[
            {'Kind': 'Hinge', 'Axis': tuple(back * side), 'Base': 0.0, 'Amp': 10.0, 'Period': 1.8, 'Phase': 50}])

        bm_arm, bm_tip = bmesh.new(), bmesh.new()
        grad = [(0.18, CRIMSON), (0.4, EMBER), (0.62, FLAME), (0.82, AMBER), (1.0, GOLD)]
        # secondaries: along the arm, pointing back, longer toward the wrist
        n_sec = 9
        for i in range(n_sec):
            f = (i + 0.5) / n_sec
            base = root + arm * (L_arm * (0.08 + 0.9 * f))
            d = (back * (1 - 0.35 * f) + arm * (0.35 * f)).normalized()
            _blade(bm_arm, base, d, plane_n, 0.55 + 0.35 * f, 0.075, 0.012, grad,
                   curl=0.16, wave=0.09, phase=i * 0.9)
        # coverts: a short layer over the base of the secondaries (crimson to flame)
        for i in range(7):
            f = (i + 0.5) / 7
            base = root + arm * (L_arm * (0.05 + 0.85 * f)) + plane_n * 0.02
            d = (back * (1 - 0.3 * f) + arm * (0.3 * f)).normalized()
            _blade(bm_arm, base, d, plane_n, 0.3 + 0.12 * f, 0.07, 0.012, [(0.45, CRIMSON), (0.8, EMBER), (1.0, FLAME)],
                   curl=0.05, wave=0.03, phase=i * 1.3)
        # the leading edge: a gold-tipped flame ridge along the arm
        _blade(bm_arm, root, arm, plane_n, L_arm * 1.04, 0.05, 0.02, [(0.4, CRIMSON), (0.7, EMBER), (0.9, AMBER), (1.0, GOLD)],
               steps=14)
        # primaries: a fan off the wrist, from pointing back to pointing out along the arm
        n_pri = 8
        for i in range(n_pri):
            f = i / (n_pri - 1)
            d = (back * (1 - f) + arm * (0.35 + 1.1 * f)).normalized()
            length = 0.95 + 0.4 * math.sin(math.pi * (0.25 + 0.6 * f))
            _blade(bm_tip, wrist - arm * 0.05, d, plane_n, length, 0.085, 0.012, grad,
                   curl=0.22, wave=0.11, phase=i * 1.1)

        # the left wing is modelled with the same code, so its faces face the other way: flip
        for bm in (bm_arm, bm_tip):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        k.add(wing, k.mesh_object('Phoenix' + wing, bm_arm, names))
        k.add(tipj, k.mesh_object('Phoenix' + tipj, bm_tip, names))


@piece
def kraken(k):
    """Four spectral tentacles wrap the forearm and butt and peel off into curls: see-through
    violet energy (ForceField) over a dim violet core, a row of glowing cyan suckers down each.
    Each tentacle is a chain of four segments hinged one after another, so a slow wave runs down
    it from the root to the curling tip."""
    import bmesh
    from mathutils import Vector
    import cue_common as cc
    from CuePieces import sweep
    k.material('Ink', 'ForceField', '#8A4CFF', Transparency=0.0)
    k.material('Core', 'Neon', '#3C1C96', Transparency=0.45)
    k.material('Sucker', 'Neon', '#2EF2FF', Transparency=0.0)
    env = cc.Envelope(cc.load_shape()[0])
    CUTS = [0.0, 0.3, 0.55, 0.78, 1.0]

    def path_fn(a0, th0, span, turns, reach):
        def P(s):
            at = a0 - span * s
            ang = th0 + 2 * math.pi * turns * s + 2.2 * max(0.0, s - 0.72) ** 1.5
            rr = float(env(at)) + 0.012 + reach * s ** 2.2
            return Vector((rr * math.sin(ang), -at, rr * math.cos(ang)))
        return P

    def width(s):
        return 0.066 * (1 - s) ** 0.75 + 0.008

    tentacles = [(4.3, 20, 1.9, 1.05, 0.34, 0), (5.1, 110, 2.1, -0.95, 0.4, 70),
                 (5.9, 200, 1.7, 1.2, 0.3, 140), (6.6, 290, 1.5, -1.1, 0.36, 210)]
    for ti, (a0, th0, span, turns, reach, ph0) in enumerate(tentacles, 1):
        P = path_fn(a0, math.radians(th0), span, turns, reach)
        parent = None
        for si in range(4):
            s0, s1 = CUTS[si], CUTS[si + 1]
            name = 'Tentacle%d_%d' % (ti, si + 1)
            piv = P(s0)
            tang = (P(s0 + 0.01) - piv).normalized()
            out = Vector((piv.x, 0, piv.z)).normalized()
            bend = tang.cross(out).normalized()          # bends the tentacle toward / away from the cue
            k.joint(name, pivot=tuple(piv), parent=parent, motion=[
                {'Kind': 'Hinge', 'Axis': tuple(bend), 'Amp': 3.0 if si == 0 else 8.0 + 2 * si,
                 'Period': 3.4, 'Phase': ph0 + si * 50}])
            parent = name
            # the segment's tube, starting a little inside the last one so no gap opens as it bends
            n = 14
            lo = max(0.0, s0 - 0.03)
            ss = [lo + (s1 - lo) * i / (n - 1) for i in range(n)]
            pts = [P(s) for s in ss]
            bm_i, bm_c, bm_s = bmesh.new(), bmesh.new(), bmesh.new()
            sweep(bm_i, pts, [width(s) for s in ss], segs=12, cap=True)
            sweep(bm_c, pts, [width(s) * 0.5 for s in ss], segs=8, cap=True)
            # suckers on the side away from the cue's axis line of sight: a glowing disc each
            m = 4 if si < 3 else 2
            for j in range(m):
                s = s0 + (s1 - s0) * (j + 0.5) / m
                if s > 0.92:
                    continue
                c = P(s)
                t_ = (P(min(s + 0.01, 1.0)) - c).normalized()
                o_ = Vector((c.x, 0, c.z)).normalized()
                side = t_.cross(o_).normalized()
                w = width(s)
                centre = c + side * (w * 0.92)
                r = w * 0.52
                mat = side.to_track_quat('Z', 'Y').to_matrix().to_4x4()
                mat.translation = centre
                bmesh.ops.create_cone(bm_s, cap_ends=True, segments=10, radius1=r, radius2=r * 0.8, depth=w * 0.25,
                                      matrix=mat)
            k.add(name, k.mesh_object(name + 'Ink', bm_i, ['Ink']))
            k.add(name, k.mesh_object(name + 'Core', bm_c, ['Core']))
            k.add(name, k.mesh_object(name + 'Suckers', bm_s, ['Sucker'], smooth=False))


def _magma(px):
    """The glowing orange-red of the skull's eyes and magma cracks (the silver and the black
    obsidian stay unlit)."""
    import numpy as np
    from CuePiecesMythic import _hsv
    h, s_, v = _hsv(px)
    return (np.clip((s_ - 0.45) / 0.2, 0, 1) * np.clip((v - 0.35) / 0.25, 0, 1)
            * ((h < 0.13) | (h > 0.95)))


@piece
def infernal(k):
    """The horned skull on the butt: a generated model (Meshy, from a clean render of the concept's
    handle close-up; assets/cue/models/infernal_skull) with its own colour, normal, roughness and
    metal maps: glossy black obsidian edged in polished silver, two silver horns curving up and
    back, silver blade spikes at the temples and jaw, and molten orange eyes and magma cracks that
    glow (an emissive mask picked from the colour map). It sits on top of the butt near its end,
    its neck sunk into the cue, the face tipped back to glare up past the butt (at a player
    aiming from behind), the horns sweeping toward the tip. It breathes: a slow small nod."""
    import numpy as np
    from mathutils import Matrix
    import cue_common as cc
    env = cc.Envelope(cc.load_shape()[0])
    AT = 6.45                                  # the skull's footing on the butt
    WIDE = 0.6                                 # across the horns, in studs (0.42 on the 0.2 cue)
    SINK = 0.093                               # the neck's footing this far below the surface
    TILT = math.radians(-28)                   # face tipped up from looking out past the butt

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s = WIDE / (hi[0] - lo[0])
        foot = Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
        r = float(env(AT))
        return (Matrix.Translation((0, -AT, r - SINK)) @ Matrix.Rotation(TILT, 4, 'X') @ Matrix.Scale(s, 4)
                @ foot)

    k.joint('Skull', pivot=(0, -AT, float(env(AT))), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.5, 'Period': 3.6}])
    k.model('Skull', 'HornedSkull', 'infernal_skull', place, target_tris=19500, emissive=_magma,
            emissive_tint='#FF6A2A', emissive_strength=3.0, cut_below=0.3)


def _gear(bm, r, teeth, thick, spokes=5, tooth_scale=1.0):
    """One gear in its own frame (the XY plane, the axle along Z): a toothed rim (trapezoid teeth
    `tooth` deep round radius r; tooth_scale grows the depth cap for big gears), spokes to a
    hub. Returns (rim_faces, hub_faces)."""
    import bmesh
    from mathutils import Matrix
    tooth = min(0.045 * tooth_scale, r * 0.2)
    r_root, r_in = r - tooth, (r - tooth) * 0.74
    # the outline: per tooth, root, rise, tip, tip, fall (so teeth have flat tops)
    pts = []
    for i in range(teeth):
        a0 = 2 * math.pi * i / teeth
        step = 2 * math.pi / teeth
        for f, rr in ((0.0, r_root), (0.22, r_root), (0.34, r), (0.62, r), (0.74, r_root)):
            pts.append((a0 + f * step, rr))
    h = thick / 2
    top_o = [bm.verts.new((rr * math.cos(a), rr * math.sin(a), h)) for a, rr in pts]
    bot_o = [bm.verts.new((rr * math.cos(a), rr * math.sin(a), -h)) for a, rr in pts]
    top_i = [bm.verts.new((r_in * math.cos(a), r_in * math.sin(a), h)) for a, _ in pts]
    bot_i = [bm.verts.new((r_in * math.cos(a), r_in * math.sin(a), -h)) for a, _ in pts]
    rim = []
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        rim.append(bm.faces.new((top_o[i], top_o[j], top_i[j], top_i[i])))
        rim.append(bm.faces.new((bot_o[j], bot_o[i], bot_i[i], bot_i[j])))
        rim.append(bm.faces.new((bot_o[i], bot_o[j], top_o[j], top_o[i])))
        rim.append(bm.faces.new((top_i[i], top_i[j], bot_i[j], bot_i[i])))
    # spokes: flat bars from the hub to the rim
    w = max(r * 0.12, 0.012)
    for s in range(spokes):
        a = 2 * math.pi * (s + 0.5) / spokes
        mid = (r_in + r * 0.2) / 2
        length = r_in - r * 0.2 + 0.01
        M = (Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((mid, 0, 0))
             @ Matrix.Diagonal((length, w, thick * 0.7, 1)))
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=M)
        rim += list({f for v in res['verts'] for f in v.link_faces})
    before = set(bm.faces)
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=r * 0.22, radius2=r * 0.22,
                          depth=thick * 1.5)
    hub = [f for f in bm.faces if f not in before]
    return rim, hub


def _glow_ring(bm, r, thick, segs=40):
    """A thin glowing ring inlaid in both faces of a gear of radius r (just proud of the rim, on
    its inner half), so the gear reads as lit brass even in dim light."""
    tooth_root = r - min(0.045 * max(1.0, r / 0.3), r * 0.2)
    r0, r1 = tooth_root * 0.78, tooth_root * 0.88
    for z in (thick / 2 + 0.002, -thick / 2 - 0.002):
        a_ = [bm.verts.new((r0 * math.cos(2 * math.pi * i / segs), r0 * math.sin(2 * math.pi * i / segs), z))
              for i in range(segs)]
        b_ = [bm.verts.new((r1 * math.cos(2 * math.pi * i / segs), r1 * math.sin(2 * math.pi * i / segs), z))
              for i in range(segs)]
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((a_[i], a_[j], b_[j], b_[i]) if z > 0 else (b_[i], b_[j], a_[j], a_[i]))
            f.smooth = False


@piece
def clockwork(k):
    """Brass and copper gears on the cue, turning (the concept's clockwork, which the flat cog
    sprites could only hint at): a meshing pair on top of the forearm and another on its side, a
    cluster of three round the butt, small single gears along the shaft. Each gear stands just off
    the cue on a dark axle pin, its face to the outside; meshing gears turn opposite ways at
    speeds set by their sizes, so their teeth roll together. Hubs and a ring inlaid in each
    face glow amber."""
    import bmesh
    from mathutils import Matrix, Vector
    import cue_common as cc
    from CuePieces import apply_modifier
    env = cc.Envelope(cc.load_shape()[0])
    k.material('Brass', 'Foil', '#EDBE58')
    k.material('Copper', 'Foil', '#DE8A4E')
    k.material('Pin', 'Metal', '#3A2A1C')
    k.material('Glow', 'Neon', '#FFB040')
    MODULE = 0.024            # studs of radius per tooth: meshing gears share it
    BASE_RATE = 70.0          # degrees a second for a gear of radius 0.2

    def frame(at, theta):
        n = Vector((math.sin(theta), 0, math.cos(theta)))          # out from the cue: the axle
        t = Vector((math.cos(theta), 0, -math.sin(theta)))          # round the cue
        return n, t

    count = [0]

    def gear(at, theta, r, rate_sign, mat, phase=0.0, standoff=0.035, spokes=5):
        count[0] += 1
        name = 'Gear%d' % count[0]
        n, t = frame(at, theta)
        rc = float(env(at))
        centre = n * (rc + standoff) + Vector((0, -at, 0))
        teeth = max(8, round(r / MODULE))
        rate = rate_sign * BASE_RATE * 0.2 / r
        k.joint(name, pivot=tuple(centre), motion=[
            {'Kind': 'Spin', 'Axis': tuple(n), 'Rate': rate, 'Phase': phase}])
        bm_g, bm_h = bmesh.new(), bmesh.new()
        rim, _ = _gear(bm_g, r, teeth, 0.028, spokes=spokes)
        bmesh.ops.create_cone(bm_h, cap_ends=True, segments=16, radius1=r * 0.13, radius2=r * 0.13, depth=0.05)
        _glow_ring(bm_h, r, 0.028)
        # the gear's frame: X round the cue, Y along it (toward the tip), Z the axle
        R = Matrix((t, Vector((0, 1, 0)), n)).transposed().to_4x4()
        M = Matrix.Translation(centre) @ R
        bmesh.ops.transform(bm_g, matrix=M, verts=bm_g.verts)
        bmesh.ops.transform(bm_h, matrix=M, verts=bm_h.verts)
        ob = k.add(name, k.mesh_object(name + mat, bm_g, [mat], smooth=False))
        # machined edges: a small bevel so the brass catches highlights on every tooth
        apply_modifier(k.bpy, ob, 'BEVEL', width=0.0035, segments=1, limit_method='ANGLE',
                       harden_normals=False)
        k.add(name, k.mesh_object(name + 'Hub', bm_h, ['Glow'], smooth=False))
        # the axle pin from the cue's surface to the gear (does not turn)
        bm_p = bmesh.new()
        bmesh.ops.create_cone(bm_p, cap_ends=True, segments=10, radius1=0.018, radius2=0.018,
                              depth=standoff + 0.02)
        Mp = Matrix.Translation(n * (rc + standoff / 2 - 0.01) + Vector((0, -at, 0))) @ R
        bmesh.ops.transform(bm_p, matrix=Mp, verts=bm_p.verts)
        if 'Pins' not in k.joints:
            k.joint('Pins')
        k.add('Pins', k.mesh_object('Pin%d' % count[0], bm_p, ['Pin']))
        return teeth

    def pair(at, theta, r1, r2, toward_tip, m1, m2, sign=1, spokes=(5, 4)):
        """Two meshing gears side by side along the cue: the second rolls against the first."""
        t1 = gear(at, theta, r1, sign, m1, spokes=spokes[0])
        pitch = (r1 - min(0.045, r1 * 0.2) / 2) + (r2 - min(0.045, r2 * 0.2) / 2)
        at2 = at - pitch if toward_tip else at + pitch
        t2 = max(8, round(r2 / MODULE))
        gear(at2, theta, r2, -sign, m2, phase=180.0 / t2, spokes=spokes[1])

    # the forearm (the glass section): a pair on top, another on the far side
    pair(4.55, math.radians(-15), 0.27, 0.16, True, 'Brass', 'Copper')
    pair(4.9, math.radians(115), 0.2, 0.13, False, 'Copper', 'Brass', sign=-1)
    # the butt: a big gear with a small one rolling on it toward the tip, one more underneath
    pair(6.5, math.radians(25), 0.25, 0.14, True, 'Brass', 'Copper')
    gear(6.55, math.radians(200), 0.22, 1, 'Brass', spokes=6)
    # small gears along the shaft
    gear(1.7, math.radians(50), 0.11, 1, 'Brass', standoff=0.03, spokes=4)
    gear(2.9, math.radians(-70), 0.13, -1, 'Copper', standoff=0.03, spokes=4)


@piece
def seraph(k):
    """The Seraph's halo: a ring of golden light floating just beyond the butt, round the cue's
    axis and tipped a little toward the top, a glowing gold core in a soft shimmering sheath. It
    bobs gently along the cue and sways (the two orbiter trails that drew it were a thin, broken
    ring from most angles)."""
    import bmesh
    from mathutils import Matrix, Vector
    from CuePieces import sweep
    k.material('HaloCore', 'Neon', '#FFE08A')
    k.material('HaloGlow', 'ForceField', '#FFD76A')
    AT, R = 7.34, 0.27
    k.joint('Halo', pivot=(0, -AT, 0), motion=[
        {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.04, 'Period': 2.6},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 6.0, 'Period': 3.4, 'Phase': 30},
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 4.0, 'Period': 4.1, 'Phase': 110}])
    n = 48
    ring = [Vector((R * math.sin(2 * math.pi * i / n), 0, R * math.cos(2 * math.pi * i / n))) for i in range(n + 1)]
    M = Matrix.Translation((0, -AT, 0)) @ Matrix.Rotation(math.radians(-14), 4, 'X')
    for name, mat, r, segs in (('Core', 'HaloCore', 0.022, 12), ('Glow', 'HaloGlow', 0.05, 14)):
        bm = bmesh.new()
        sweep(bm, ring, [r] * len(ring), segs=segs, cap=False)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
        k.add('Halo', k.mesh_object('Halo' + name, bm, [mat]))


def _crystal(bm, centre, axis, length, width, sides=6, twist=0.0):
    """A crystal shard: a long six-sided bipyramid (a point at each end, widest a third of the way
    along), about `axis` through `centre`."""
    from mathutils import Vector
    axis = axis.normalized()
    u = axis.orthogonal().normalized()
    v = axis.cross(u)
    top = bm.verts.new(centre + axis * (length * 0.62))
    bot = bm.verts.new(centre - axis * (length * 0.38))
    ring = []
    for i in range(sides):
        a = 2 * math.pi * i / sides + twist
        w = width * (1.0 if i % 2 == 0 else 0.8)          # uneven facets catch the light
        ring.append(bm.verts.new(centre + (u * math.cos(a) + v * math.sin(a)) * w))
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((ring[i], ring[j], top))
        bm.faces.new((ring[j], ring[i], bot))
    return Vector(centre)


@piece
def chroma(k):
    """Rainbow crystal shards orbiting the cue (the concept's floating crystals; the shard sprite was
    small and flat): eight faceted shards, red through violet, each a shimmering see-through crystal
    over a glowing core, circling the cue on its own orbit at its own speed, drifting a little up
    and down the cue, and tumbling as it goes."""
    import bmesh
    from mathutils import Vector
    RAINBOW = [('Red', '#FF3D5A'), ('Orange', '#FF9A3D'), ('Yellow', '#FFE03D'), ('Green', '#3DFF8A'),
               ('Cyan', '#3DD8FF'), ('Blue', '#3D7AFF'), ('Violet', '#B03DFF'), ('Pink', '#FF5AD8')]
    for name, col in RAINBOW:
        k.material(name + 'Crystal', 'ForceField', col)
        k.material(name + 'Core', 'Neon', col, Transparency=0.3)
    # (at, orbit radius, start angle, orbit deg/s, drift period, length, width)
    shards = [(1.0, 0.34, 20, 70, 3.4, 0.2, 0.06), (1.9, 0.42, 150, -55, 4.1, 0.24, 0.07),
              (2.8, 0.36, 260, 62, 3.7, 0.2, 0.06), (3.7, 0.48, 60, -48, 4.6, 0.28, 0.08),
              (4.5, 0.4, 200, 58, 3.9, 0.24, 0.07), (5.3, 0.5, 320, -52, 4.3, 0.3, 0.085),
              (6.0, 0.42, 100, 64, 3.6, 0.26, 0.075), (6.7, 0.46, 230, -60, 4.0, 0.28, 0.08)]
    for i, ((cname, _), (at, r, a0, rate, drift, L, W)) in enumerate(zip(RAINBOW, shards), 1):
        orbit, shard = 'Orbit%d' % i, 'Shard%d' % i
        k.joint(orbit, pivot=(0, -at, 0), motion=[
            {'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate, 'Phase': a0},
            {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.25, 'Period': drift, 'Phase': i * 47}])
        c = Vector((0, -at, r))
        tumble = Vector((0.6, 0.3 * (1 if i % 2 else -1), 0.2)).normalized()
        k.joint(shard, pivot=tuple(c), parent=orbit, motion=[
            {'Kind': 'Spin', 'Axis': tuple(tumble), 'Rate': 140 + 25 * (i % 3)}])
        L, W = L * 1.6, W * 1.6          # (sized at 1.6 after the first render: they read as specks)
        axis = Vector((0.4 * (1 if i % 2 else -1), 0.8, 0.45))
        bm_c, bm_k = bmesh.new(), bmesh.new()
        _crystal(bm_c, c, axis, L, W, twist=i * 0.4)
        _crystal(bm_k, c, axis, L * 0.7, W * 0.55, twist=i * 0.4)
        k.add(shard, k.mesh_object(shard + 'Crystal', bm_c, [cname + 'Crystal'], smooth=False))
        k.add(shard, k.mesh_object(shard + 'Core', bm_k, [cname + 'Core'], smooth=False))
