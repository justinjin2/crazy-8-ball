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
