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
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        root = Vector((0.07 * side, -AT, 0.06))
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
    WIDE = 0.42                                # across the horns, in studs
    TILT = math.radians(-28)                   # face tipped up from looking out past the butt

    def place(ob):
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s = WIDE / (hi[0] - lo[0])
        foot = Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
        r = float(env(AT))
        return (Matrix.Translation((0, -AT, r * 0.35)) @ Matrix.Rotation(TILT, 4, 'X') @ Matrix.Scale(s, 4)
                @ foot)

    k.joint('Skull', pivot=(0, -AT, 0.1), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.5, 'Period': 3.6}])
    k.model('Skull', 'HornedSkull', 'infernal_skull', place, target_tris=19500, emissive=_magma,
            emissive_tint='#FF6A2A', emissive_strength=3.0, cut_below=0.3)
