"""The Mythic and Secret pieces (scripted modelling; see CuePieces.py for the kit and export).

Every piece is modelled in the cue's Blender frame: X is the side, Y runs from the tip (0) to
the butt (-7), Z is the top. Heads and masks sit on or past the butt end.
"""
import math

import CuePieces as P
from CuePieces import piece, sweep, metaball_mesh, assign_by_region, apply_modifier


def _butt(at):
    return -at


# =============================================================================================
# Celestial Dragon (M1)
# =============================================================================================

@piece
def celestial_dragon(k):
    """A pearl-white dragon head with gold horns resting past the butt end, glowing blue eyes, an
    open jaw that snaps wider now and then (a roar), gold-edged lips and white fangs, a mane of
    blue energy flames sweeping back; its see-through energy body (two ForceField ribbons with
    a Neon core) coils round the cue from the butt to the shaft."""
    import bmesh
    from mathutils import Vector, Quaternion
    bpy = k.bpy
    k.material('Pearl', 'SmoothPlastic', '#F2EFE8', Reflectance=0.15)
    k.material('Gold', 'Foil', '#D4AF37')
    k.material('Fang', 'SmoothPlastic', '#FFFDF6')
    k.material('Eye', 'Neon', '#7FC8FF')
    k.material('Energy', 'ForceField', '#6FB8FF', Transparency=0.35)
    k.material('Core', 'Neon', '#A8D8FF', Transparency=0.55)
    k.material('Mane', 'Neon', '#9ED0FF', Transparency=0.3)

    # head frame: u forward past the butt (-Y), s to the side (+X), w up (+Z)
    U0, W0 = 7.02, 0.05   # the back of the skull, and how high the head's axis sits

    def H(u, s, w):
        return (s, -(U0 + u), W0 + w)

    k.joint('Head', pivot=H(0.0, 0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 3.2},             # breathing nod
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 4.0, 'Period': 5.1, 'Phase': 40}])  # a slow look round
    k.joint('Jaw', pivot=H(0.1, 0, -0.03), parent='Head', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 8.0, 'Amp': 18.0, 'Period': 4.0, 'Shape': 'pulse'}])
    k.joint('Body', pivot=(0, 0, 0))

    def E(u, s, w, along, side, up, rot=None, neg=False):
        # an ellipsoid in head terms: half-extents along the head, to the side, up
        return (H(u, s, w), (side, along, up), rot, neg)
    q_down = Quaternion((1, 0, 0), math.radians(8))
    skull = metaball_mesh(bpy, 'DragonSkull', [
        E(0.10, 0, 0.07, 0.15, 0.11, 0.11),                 # cranium
        E(0.33, 0, 0.03, 0.20, 0.07, 0.06, q_down),         # snout
        E(0.51, 0, 0.035, 0.06, 0.055, 0.05),               # nose
        E(0.26, 0.065, 0.10, 0.09, 0.04, 0.035),            # brows
        E(0.26, -0.065, 0.10, 0.09, 0.04, 0.035),
        E(0.15, 0.085, -0.005, 0.09, 0.05, 0.06),           # cheeks
        E(0.15, -0.085, -0.005, 0.09, 0.05, 0.06),
        E(-0.10, 0, 0.0, 0.16, 0.09, 0.09),                 # neck into the cue
        E(0.345, 0.075, 0.075, 0.03, 0.028, 0.025, None, True),   # eye sockets
        E(0.345, -0.075, 0.075, 0.03, 0.028, 0.025, None, True),
    ], resolution=0.008)
    skull.data.materials.append(k.blender_mat('Pearl'))
    skull.data.materials.append(k.blender_mat('Gold'))

    apply_modifier(bpy, skull, 'DECIMATE', ratio=0.16)
    k.add('Head', skull)

    jaw = metaball_mesh(bpy, 'DragonJaw', [
        E(0.30, 0, -0.065, 0.19, 0.055, 0.03, Quaternion((1, 0, 0), math.radians(-8))),
        E(0.13, 0.055, -0.035, 0.07, 0.035, 0.04),
        E(0.13, -0.055, -0.035, 0.07, 0.035, 0.04),
    ], resolution=0.008)
    jaw.data.materials.append(k.blender_mat('Pearl'))
    jaw.data.materials.append(k.blender_mat('Gold'))
    apply_modifier(bpy, jaw, 'DECIMATE', ratio=0.2)
    k.add('Jaw', jaw)
    # gold lip rims: the upper along the snout's lower edge, the lower along the jaw's top
    bm = bmesh.new()
    for side in (-1, 1):
        sweep(bm, [H(0.12 + 0.4 * t, side * (0.07 - 0.035 * t), -0.018 + 0.012 * t) for t in [i / 11 for i in range(12)]],
              [0.009] * 12, segs=8)
    k.add('Head', k.mesh_object('DragonLipUp', bm, ['Gold']))
    bm = bmesh.new()
    for side in (-1, 1):
        sweep(bm, [H(0.12 + 0.36 * t, side * (0.058 - 0.03 * t), -0.047 - 0.01 * t) for t in [i / 11 for i in range(12)]],
              [0.008] * 12, segs=8)
    k.add('Jaw', k.mesh_object('DragonLipLow', bm, ['Gold']))

    # fangs: cones down from the upper jaw, up from the lower
    bm = bmesh.new()
    for side in (-1, 1):
        for i, (u, ln) in enumerate(((0.47, 0.07), (0.41, 0.045), (0.35, 0.04), (0.29, 0.035))):
            s = side * (0.045 - 0.004 * i)
            top = Vector(H(u, s, -0.025))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.013 - 0.002 * i, radius2=0.0,
                                  depth=ln, matrix=_cone_matrix(top, Vector((0, -0.25, -1)).normalized(), ln))
    fangs = k.mesh_object('DragonFangs', bm, ['Fang'])
    k.add('Head', fangs)
    bm = bmesh.new()
    for side in (-1, 1):
        for i, u in enumerate((0.42, 0.34, 0.26)):
            base = Vector(H(u, side * 0.04, -0.07))
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.01, radius2=0.0, depth=0.04,
                                  matrix=_cone_matrix(base, Vector((0, -0.2, 1)).normalized(), 0.04))
    k.add('Jaw', k.mesh_object('DragonFangsLow', bm, ['Fang']))

    # eyes
    bm = bmesh.new()
    for side in (-1, 1):
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.024,
                                  matrix=_scale_at(Vector(H(0.345, side * 0.078, 0.075)), (1.0, 1.25, 0.8)))
    k.add('Head', k.mesh_object('DragonEyes', bm, ['Eye']))

    # horns: two long gold horns sweeping back and up, two short ones below
    bm = bmesh.new()
    for side in (-1, 1):
        for (u0, s0, w0, length, rad, rise, spread) in ((0.2, 0.06, 0.13, 0.55, 0.026, 0.22, 0.10), (0.1, 0.1, 0.06, 0.3, 0.018, 0.08, 0.14)):
            path, radii = [], []
            for i in range(14):
                t = i / 13
                path.append(H(u0 - length * t, side * (s0 + spread * t), w0 + rise * math.sin(t * 1.6) + 0.02 * t))
                radii.append(rad * (1 - t) ** 0.8 + 0.002)
            sweep(bm, path, radii, segs=10, profile=lambda a: 1.0 + 0.12 * math.cos(3 * a))
    horns = k.mesh_object('DragonHorns', bm, ['Gold'])
    k.add('Head', horns)

    # the mane: flame spikes of energy sweeping back from the brow, cheeks and chin
    bm = bmesh.new()
    spikes = [(0.22, 0.0, 0.16, 0.45, 0.2), (0.12, 0.05, 0.15, 0.5, 0.25), (0.12, -0.05, 0.15, 0.5, 0.25),
              (0.05, 0.09, 0.1, 0.55, 0.12), (0.05, -0.09, 0.1, 0.55, 0.12), (0.12, 0.12, 0.0, 0.4, -0.02),
              (0.12, -0.12, 0.0, 0.4, -0.02), (0.02, 0.1, -0.06, 0.45, -0.1), (0.02, -0.1, -0.06, 0.45, -0.1),
              (0.3, 0.05, -0.09, 0.25, -0.12), (0.3, -0.05, -0.09, 0.25, -0.12)]
    for (u0, s0, w0, length, lift) in spikes:
        path, radii = [], []
        length *= 0.7
        for i in range(14):
            t = i / 13
            path.append(H(u0 - length * t, s0 * (1 + 0.7 * t), w0 + lift * 0.8 * t + 0.035 * math.sin(t * math.pi * 1.5)))
            radii.append((0.024 * (1 - t) ** 0.8 + 0.0015, 0.009 * (1 - t) + 0.0015))
        sweep(bm, path, radii, segs=8)
    k.add('Head', k.mesh_object('DragonMane', bm, ['Mane']))
    # whiskers from the snout
    bm = bmesh.new()
    for side in (-1, 1):
        path = [H(0.5 - 0.3 * t, side * (0.05 + 0.2 * t), 0.0 - 0.1 * t + 0.08 * t * t) for t in [i / 15 for i in range(16)]]
        sweep(bm, path, [0.006 * (1 - i / 15) + 0.0015 for i in range(16)], segs=6)
    k.add('Head', k.mesh_object('DragonWhiskers', bm, ['Mane']))

    # the energy body: two flat ribbons coiling round the cue from the neck to the shaft, and a
    # thin glowing core in each (the cue's radius from its profile)
    import cue_common as cc
    env = cc.Envelope(cc.load_shape()[0])
    bm_e, bm_c = bmesh.new(), bmesh.new()
    for ph in (0.0, math.pi):
        path, radii, core = [], [], []
        n = 160
        for i in range(n):
            t = i / (n - 1)
            at = 6.95 - 6.35 * t
            rr = float(env(at)) + 0.045 + 0.02 * math.sin(t * 9)
            ang = ph + 2 * math.pi * 3.2 * t
            path.append((rr * math.sin(ang), -at, rr * math.cos(ang)))
            w = 0.034 * (1 - t) ** 0.6 + 0.006
            radii.append((w, w * 0.3))
            core.append(0.006 * (1 - t) + 0.0015)
        sweep(bm_e, path, radii, segs=10)
        sweep(bm_c, path, core, segs=6)
    k.add('Body', k.mesh_object('DragonBody', bm_e, ['Energy']))
    k.add('Body', k.mesh_object('DragonCore', bm_c, ['Core']))


def _cone_matrix(base, direction, depth):
    """create_cone builds along +Z centred on the origin: move its base to `base` pointing along
    `direction`."""
    from mathutils import Vector, Matrix
    z = Vector((0, 0, 1))
    q = z.rotation_difference(direction)
    return Matrix.Translation(base + direction * depth / 2) @ q.to_matrix().to_4x4()


def _scale_at(centre, scale):
    from mathutils import Matrix
    return Matrix.Translation(centre) @ Matrix.Diagonal(tuple(scale) + (1.0,))


def _dragon_roar(i, n):
    """The pocket finisher's spectral dragon head: it lunges up and forward as its jaw drops
    open in a roar (frames 0-9), holds, and pulls back (10-15)."""
    import numpy as np
    k = i / (n - 1)
    lunge = math.sin(math.pi * min(k / 0.7, 1.0))
    jaw = math.radians(8 + 40 * math.sin(math.pi * min(k / 0.75, 1.0)) ** 0.7)
    pivot_head = np.array([0, -7.02, 0.05])
    pivot_jaw = np.array([0, -7.12, 0.02])

    def about(p, R):
        T = np.eye(4); T[:3, 3] = p
        Ti = np.eye(4); Ti[:3, 3] = -p
        return T @ R @ Ti
    head = about(pivot_head, P._rot((1, 0, 0), math.radians(-38 - 14 * lunge)))
    S = np.eye(4) * (0.85 + 0.2 * lunge); S[3, 3] = 1
    head = about(pivot_head, S) @ head
    jaw_m = head @ about(pivot_jaw, P._rot((1, 0, 0), jaw))
    return {'Head': head.tolist(), 'Jaw': jaw_m.tolist()}


P.SPRITES['dragon_roar'] = {'piece': 'celestial_dragon', 'skin': 'celestial_dragon', 'joints': ['Head', 'Jaw'],
                            'colour': '#8CCBFF', 'rim': 0.3, 'fill': 0.4, 'ortho': 1.4,
                            'cam': ((1.7, -7.4, 0.55), (0, -7.02, 0.33)), 'pose': _dragon_roar}


# =============================================================================================
# Kitsune (M2)
# =============================================================================================

def _surface_ribbon(bm, bvh, centre_fn, path_ua, widths, lift=0.003):
    """A ribbon lying on a sculpt: path_ua is [(u, a_deg)] (along the head and round it from the
    top), each point found by casting a ray at the head's axis; widths per point. Returns
    nothing (adds faces to bm)."""
    from mathutils import Vector
    pts, nrms = [], []
    for u, a in path_ua:
        c = Vector(centre_fn(u))
        d = Vector((math.sin(math.radians(a)), 0.0, math.cos(math.radians(a))))
        hit = bvh.ray_cast(c + d * 0.6, -d)
        if hit[0] is None:
            continue
        pts.append(hit[0])
        nrms.append(hit[1].normalized())
    if len(pts) < 2:
        return
    left, right = [], []
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = nrms[i]
        b = t.cross(n).normalized()
        w = widths[min(i, len(widths) - 1)] / 2
        left.append(bm.verts.new(p + n * lift + b * w))
        right.append(bm.verts.new(p + n * lift - b * w))
    for i in range(len(pts) - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))


def _basis_matrix(origin, z_dir, y_hint, scale=(1, 1, 1)):
    """A matrix whose local Z points along z_dir and local Y as near y_hint as it can, scaled."""
    from mathutils import Matrix, Vector
    z = Vector(z_dir).normalized()
    y = Vector(y_hint)
    y = (y - z * z.dot(y)).normalized()
    x = y.cross(z)
    R = Matrix((x, y, z)).transposed().to_4x4()
    return Matrix.Translation(Vector(origin)) @ R @ Matrix.Diagonal(tuple(scale) + (1.0,))


@piece
def kitsune(k):
    """A white porcelain spirit-fox mask on the butt end, looking out past it: tall pointed ears
    with crimson insides that twitch now and then, violet foxfire eyes, crimson flame markings
    on the brow and cheeks, a gold-framed crimson gem on the forehead, a black nose, a small jaw
    with fangs, gold rims where it meets the cue. (Its nine foxfire tails are Beams in the skin's
    VFX, flowing off the back of the mask.)"""
    import bmesh
    from mathutils import Vector, Quaternion
    from mathutils.bvhtree import BVHTree
    bpy = k.bpy
    k.material('Porcelain', 'SmoothPlastic', '#FAF7F2', Reflectance=0.2)
    k.material('Crimson', 'SmoothPlastic', '#C8102E', Reflectance=0.1)
    k.material('Gold', 'Foil', '#D4AF37')
    k.material('Eye', 'Neon', '#A63CFF')
    k.material('Nose', 'SmoothPlastic', '#141216')
    k.material('Mouth', 'SmoothPlastic', '#3A0A12')
    k.material('Fang', 'SmoothPlastic', '#FFFDF6')

    U0, W0 = 7.0, 0.02

    def H(u, s, w):
        return (s, -(U0 + u), W0 + w)

    def E(u, s, w, along, side, up, rot=None, neg=False):
        return (H(u, s, w), (side, along, up), rot, neg)

    k.joint('Mask', pivot=H(-0.05, 0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0, 'Period': 4.4},             # a slow head tilt
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.0, 'Period': 3.1, 'Phase': 70}])
    for side, nm, ph in ((1, 'EarR', 0), (-1, 'EarL', 140)):
        k.joint(nm, pivot=H(0.06, side * 0.085, 0.13), parent='Mask', motion=[
            {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': side * 12.0, 'Period': 3.3, 'Phase': ph, 'Shape': 'pulse'}])
    k.joint('Jaw', pivot=H(0.14, 0, -0.05), parent='Mask', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 4.0, 'Amp': 6.0, 'Period': 5.0, 'Shape': 'pulse', 'Phase': 200}])

    q_dn = Quaternion((1, 0, 0), math.radians(6))
    skull = metaball_mesh(bpy, 'FoxMask', [
        E(0.10, 0, 0.05, 0.13, 0.145, 0.13),            # forehead dome
        E(0.15, 0.075, -0.03, 0.11, 0.07, 0.075),       # cheeks
        E(0.15, -0.075, -0.03, 0.11, 0.07, 0.075),
        E(0.33, 0, -0.01, 0.2, 0.06, 0.055, q_dn),      # snout
        E(0.30, 0, 0.035, 0.14, 0.035, 0.03, q_dn),     # nose bridge
        E(-0.06, 0, 0.0, 0.1, 0.12, 0.12),              # back, into the cue
        E(0.28, 0.068, 0.045, 0.035, 0.022, 0.018, None, True),   # eye sockets
        E(0.28, -0.068, 0.045, 0.035, 0.022, 0.018, None, True),
    ], resolution=0.008)
    apply_modifier(bpy, skull, 'DECIMATE', ratio=0.2)
    skull.data.materials.append(k.blender_mat('Porcelain'))
    k.add('Mask', skull)
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(skull, dg)

    def centre(u):
        return H(u, 0, 0.0)

    # crimson flame markings on the brow and cheeks, and round the eyes
    bm = bmesh.new()
    for side in (-1, 1):
        for path, w0 in (([(0.32 - 0.26 * t, side * (22 + 55 * t)) for t in [i / 11 for i in range(12)]], 0.03),
                         ([(0.25 - 0.22 * t, side * (10 + 35 * t)) for t in [i / 11 for i in range(12)]], 0.022),
                         ([(0.3 - 0.18 * t, side * (100 + 28 * t)) for t in [i / 9 for i in range(10)]], 0.024),
                         ([(0.24 + 0.08 * math.cos(2 * math.pi * t), side * (68 + 20 * math.sin(2 * math.pi * t))) for t in [i / 20 for i in range(21)]], 0.008)):
            n = len(path)
            widths = [w0 * math.sin(math.pi * (0.15 + 0.85 * i / (n - 1))) ** 0.6 + 0.003 for i in range(n)] if w0 > 0.01 else [w0] * n
            _surface_ribbon(bm, bvh, centre, path, widths)
    red = k.mesh_object('FoxMarks', bm, ['Crimson'], smooth=True)
    apply_modifier(bpy, red, 'SOLIDIFY', thickness=0.003, offset=-1.0)
    k.add('Mask', red)

    # the forehead gem: a gold diamond frame round a crimson gem
    hit = bvh.ray_cast(Vector(centre(0.17)) + Vector((0, 0, 0.6)), Vector((0, 0, -1)))
    top = hit[0] + hit[1] * 0.004
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0,
                               matrix=_basis_matrix(top, hit[1], (0, -1, 0), (0.028, 0.05, 0.012)))
    k.add('Mask', k.mesh_object('FoxGemFrame', bm, ['Gold'], smooth=False))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0,
                               matrix=_basis_matrix(top + hit[1] * 0.006, hit[1], (0, -1, 0), (0.016, 0.032, 0.01)))
    k.add('Mask', k.mesh_object('FoxGem', bm, ['Crimson'], smooth=False))

    # eyes: slanted almonds of violet foxfire
    bm = bmesh.new()
    for side in (-1, 1):
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0,
                                  matrix=_basis_matrix(Vector(H(0.285, side * 0.07, 0.047)), (side * 0.9, -0.2, 0.4), (0, -1, 0.35 * side),
                                                       (0.014, 0.036, 0.012)))
    k.add('Mask', k.mesh_object('FoxEyes', bm, ['Eye']))
    # nose
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0, matrix=_scale_at(Vector(H(0.525, 0, 0.005)), (0.024, 0.018, 0.016)))
    k.add('Mask', k.mesh_object('FoxNose', bm, ['Nose']))

    # ears: flattened cones, crimson inside
    for side, nm in ((1, 'EarR'), (-1, 'EarL')):
        base = Vector(H(0.06, side * 0.085, 0.1))
        d = Vector((side * 0.32, 0.22, 1.0)).normalized()   # up, out and a little back
        fwd = (0, -1, 0)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=0.0, depth=1.0,
                              matrix=_basis_matrix(base + d * 0.11, d, fwd, (0.065, 0.028, 0.22)))
        ear = k.mesh_object('Fox' + nm, bm, ['Porcelain'])
        k.add(nm, ear)
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=1.0, radius2=0.0, depth=1.0,
                              matrix=_basis_matrix(base + d * 0.1 + Vector((0, -0.016, 0)), d, fwd, (0.042, 0.016, 0.17)))
        k.add(nm, k.mesh_object('Fox' + nm + 'In', bm, ['Crimson']))
        bm = bmesh.new()
        sweep(bm, [base + d * (0.005 + 0.2 * t) + Vector((side * 0.052 * (1 - t), -0.004, 0)) for t in [i / 8 for i in range(9)]],
              [0.004] * 9, segs=6)
        sweep(bm, [base + d * (0.005 + 0.2 * t) + Vector((-side * 0.052 * (1 - t), -0.004, 0)) for t in [i / 8 for i in range(9)]],
              [0.004] * 9, segs=6)
        k.add(nm, k.mesh_object('Fox' + nm + 'Rim', bm, ['Gold']))

    # the jaw: a dark mouth with a gold edge and small fangs
    jaw = metaball_mesh(bpy, 'FoxJaw', [E(0.3, 0, -0.065, 0.15, 0.045, 0.025, Quaternion((1, 0, 0), math.radians(-6))),
                                         E(0.18, 0, -0.06, 0.08, 0.06, 0.03)], resolution=0.008)
    apply_modifier(bpy, jaw, 'DECIMATE', ratio=0.25)
    jaw.data.materials.append(k.blender_mat('Mouth'))
    k.add('Jaw', jaw)
    bm = bmesh.new()
    for side in (-1, 1):
        for i, u in enumerate((0.42, 0.35)):
            bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.008, radius2=0.0, depth=0.03,
                                  matrix=_cone_matrix(Vector(H(u, side * 0.032, -0.04)), Vector((0, -0.2, -1)).normalized(), 0.03))
    k.add('Mask', k.mesh_object('FoxFangs', bm, ['Fang']))

    # gold rims: a double collar where the mask meets the cue
    bm = bmesh.new()
    for u, rad, tube in ((-0.13, 0.104, 0.012), (-0.155, 0.104, 0.007)):
        path = [H(u, rad * math.sin(2 * math.pi * i / 48), rad * math.cos(2 * math.pi * i / 48) - W0) for i in range(49)]
        sweep(bm, path, [tube] * 49, segs=8, cap=False)
    k.add('Mask', k.mesh_object('FoxRims', bm, ['Gold']))


def _fox_rise(i, n):
    """The pocket finisher's fox spirit: the mask rises tilted up toward the camera, ears flicking,
    jaw parting, then settles (a loop-free 16 frames)."""
    import numpy as np
    k = i / (n - 1)
    up = math.sin(math.pi * min(k / 0.6, 1.0))
    piv = np.array([0, -7.0, 0.02])

    def about(p, R):
        T = np.eye(4); T[:3, 3] = p
        Ti = np.eye(4); Ti[:3, 3] = -p
        return T @ R @ Ti
    mask = about(piv, P._rot((1, 0, 0), math.radians(-30 - 12 * up)) @ P._rot((0, 1, 0), math.radians(8 * math.sin(k * 6))))
    ears = {}
    for side, nm in ((1, 'EarR'), (-1, 'EarL')):
        ep = np.array([side * 0.085, -7.06, 0.15])
        ears[nm] = (mask @ about(ep, P._rot((0, 1, 0), math.radians(side * 14 * math.sin(k * 12))))).tolist()
    jaw = mask @ about(np.array([0, -7.14, -0.03]), P._rot((1, 0, 0), math.radians(6 + 14 * up)))
    out = {'Mask': mask.tolist(), 'Jaw': jaw.tolist()}
    out.update(ears)
    return out


P.SPRITES['fox_spirit'] = {'piece': 'kitsune', 'skin': 'kitsune', 'joints': ['Mask', 'EarL', 'EarR', 'Jaw'],
                           'colour': '#D08CFF', 'rim': 0.25, 'fill': 0.22, 'ortho': 0.88,
                           'cam': ((1.0, -8.1, 0.45), (0, -7.22, 0.2)), 'pose': _fox_rise, 'drop': ('Mask_Gold',)}


# =============================================================================================
# Apex (M3)
# =============================================================================================

def _frustum(bm, centre, z_dir, y_hint, w, th, length, taper=1.0):
    """A bevel-ready box along z_dir (w across, th thick along y_hint, `length` long), its far
    end scaled by `taper`."""
    from mathutils import Matrix
    import bmesh
    M = _basis_matrix(centre, z_dir, y_hint, (w, th, length)) @ Matrix.Rotation(math.radians(45), 4, 'Z')
    bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=math.sqrt(0.5), radius2=math.sqrt(0.5) * taper,
                          depth=1.0, matrix=M)


def _bevel(bpy, ob, width=0.004, segments=2):
    apply_modifier(bpy, ob, 'BEVEL', width=width, segments=segments, limit_method='ANGLE')
    return ob


@piece
def apex(k):
    """A robotic claw arm on the butt end: a gunmetal housing with orange armour plates and cyan
    light slots, three thruster vents at its back, a cyan lens core in a spinning bezel at its
    front, and three two-jointed claws (orange armoured, steel talons with cyan edges) that flex
    open and snap shut."""
    import bmesh
    from mathutils import Vector
    bpy = k.bpy
    k.material('Gunmetal', 'Metal', '#3A3F47')
    k.material('Dark', 'SmoothPlastic', '#16181C', Reflectance=0.1)
    k.material('Armour', 'SmoothPlastic', '#FF7A1A', Reflectance=0.12)
    k.material('Steel', 'Metal', '#C4CCD6')
    k.material('Cyan', 'Neon', '#19E6FF')
    k.material('Lens', 'Neon', '#8FF6FF')
    k.material('Amber', 'Neon', '#FF8A2A')

    U0 = 7.0
    F = Vector((0, -1, 0))                         # forward, past the butt

    def rad(a):
        return Vector((math.sin(math.radians(a)), 0, math.cos(math.radians(a))))

    def tan(a):                                    # round the cue (the claws' hinge axis)
        return Vector((math.cos(math.radians(a)), 0, -math.sin(math.radians(a))))

    def at(u, r, a):
        return Vector((0, -(U0 + u), 0)) + rad(a) * r

    # the housing: a turned gunmetal body over the end of the cue
    prof = [(-0.15, 0.104), (-0.1, 0.108), (-0.095, 0.121), (-0.02, 0.126), (0.0, 0.13), (0.2, 0.134),
            (0.23, 0.131), (0.255, 0.118), (0.27, 0.1), (0.285, 0.097)]
    k.joint('Housing', pivot=(0, -U0, 0))
    bm = bmesh.new()
    sweep(bm, [(0, -(U0 + u), 0) for u, _ in prof], [r for _, r in prof], segs=40)
    k.add('Housing', k.mesh_object('ApexBody', bm, ['Gunmetal']))

    def r_at(u):
        for (u0, r0), (u1, r1) in zip(prof, prof[1:]):
            if u0 <= u <= u1:
                return r0 + (r1 - r0) * (u - u0) / (u1 - u0)
        return prof[-1][1]

    # armour plates between the claws: hexagonal shells, thick and bevelled
    CLAWS = (0, 120, 240)
    bm = bmesh.new()
    for a in (60, 180, 300):
        rows, cols = 7, 9
        grid = []
        for i in range(rows):
            u = 0.015 + 0.2 * i / (rows - 1)
            half = 40 - 14 * abs(2 * i / (rows - 1) - 1) ** 1.5
            grid.append([bm.verts.new(at(u, r_at(u) + 0.002, a + half * (2 * j / (cols - 1) - 1))) for j in range(cols)])
        for i in range(rows - 1):
            for j in range(cols - 1):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        # a smaller plate behind it, over the vent
        grid = []
        for i in range(3):
            u = -0.085 + 0.065 * i / 2
            grid.append([bm.verts.new(at(u, 0.123 + 0.002, a + 22 * (2 * j / 4 - 1))) for j in range(5)])
        for i in range(2):
            for j in range(4):
                bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    plates = k.mesh_object('ApexPlates', bm, ['Armour'])
    apply_modifier(bpy, plates, 'SOLIDIFY', thickness=0.014, offset=1.0)
    _bevel(bpy, plates, 0.004, 1)
    k.add('Housing', plates)

    # dark recessed seams and cyan light slots under each claw, amber lights on the plates
    bm = bmesh.new()
    for a in CLAWS:
        _frustum(bm, at(0.1, 0.13, a), F, rad(a), 0.05, 0.012, 0.19)
    seams = _bevel(bpy, k.mesh_object('ApexSeams', bm, ['Dark'], smooth=False), 0.003, 1)
    k.add('Housing', seams)
    bm = bmesh.new()
    for a in CLAWS:
        _frustum(bm, at(0.1, 0.137, a), F, rad(a), 0.022, 0.006, 0.16)
    k.add('Housing', k.mesh_object('ApexSlots', bm, ['Cyan'], smooth=False))
    bm = bmesh.new()
    for a in (60, 180, 300):
        for da in (-24, 24):
            bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=1.0,
                                      matrix=_scale_at(at(0.19, 0.15, a + da), (0.012, 0.012, 0.012)))
    k.add('Housing', k.mesh_object('ApexLights', bm, ['Amber']))
    # a cyan ring where the housing meets the cue
    bm = bmesh.new()
    sweep(bm, [at(-0.097, 0.117, 360 * i / 48) for i in range(49)], [0.008] * 49, segs=8, cap=False)
    k.add('Housing', k.mesh_object('ApexRing', bm, ['Cyan']))

    # thruster vents at the back, angled out and back along the cue; amber glow inside
    bm_n, bm_g = bmesh.new(), bmesh.new()
    for a in (60, 180, 300):
        d = (rad(a) * 0.55 - F * 0.85).normalized()
        base = at(-0.05, 0.1, a)
        bmesh.ops.create_cone(bm_n, cap_ends=True, segments=14, radius1=0.036, radius2=0.03, depth=0.07,
                              matrix=_cone_matrix(base, d, 0.07))
        bmesh.ops.create_cone(bm_g, cap_ends=True, segments=14, radius1=0.022, radius2=0.022, depth=0.004,
                              matrix=_cone_matrix(base + d * 0.069, d, 0.004))
    k.add('Housing', _bevel(bpy, k.mesh_object('ApexVents', bm_n, ['Gunmetal'], smooth=False), 0.004, 1))
    k.add('Housing', k.mesh_object('ApexVentGlow', bm_g, ['Amber'], smooth=False))

    # the front: a gunmetal bezel, a notched ring that turns, the cyan lens
    bm = bmesh.new()
    sweep(bm, [at(0.285, 0.088, 360 * i / 48) for i in range(49)], [0.016] * 49, segs=10, cap=False)
    k.add('Housing', k.mesh_object('ApexBezel', bm, ['Gunmetal']))
    k.joint('Rotor', pivot=(0, -U0, 0), parent='Housing', motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 50.0}])
    bm = bmesh.new()
    for i in range(10):
        a = 36 * i
        _frustum(bm, at(0.3, 0.08, a), F, rad(a), 0.03, 0.022, 0.02, 0.8)
    k.add('Rotor', _bevel(bpy, k.mesh_object('ApexNotches', bm, ['Dark'], smooth=False), 0.003, 1))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0, matrix=_scale_at(at(0.29, 0, 0), (0.07, 0.026, 0.07)))
    k.add('Housing', k.mesh_object('ApexLens', bm, ['Lens']))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=1.0, matrix=_scale_at(at(0.31, 0, 0), (0.034, 0.02, 0.034)))
    k.add('Housing', k.mesh_object('ApexCore', bm, ['Cyan']))

    # the three claws: a knuckle, an armoured arm, a second knuckle, a curved steel talon
    for n, a in enumerate(CLAWS, 1):
        r_, t_ = rad(a), tan(a)
        K = at(0.235, 0.145, a)
        J2 = K + F * 0.2 + r_ * 0.13
        fname, tname = 'Claw%d' % n, 'Talon%d' % n
        k.joint(fname, pivot=tuple(K), parent='Housing', motion=[
            {'Kind': 'Hinge', 'Axis': tuple(t_), 'Base': 4.0, 'Amp': 12.0, 'Period': 3.0, 'Shape': 'snap'}])
        k.joint(tname, pivot=tuple(J2), parent=fname, motion=[
            {'Kind': 'Hinge', 'Axis': tuple(t_), 'Base': 0.0, 'Amp': 9.0, 'Period': 3.0, 'Phase': 25, 'Shape': 'snap'}])
        d1 = (J2 - K).normalized()
        nrm = t_.cross(d1)
        if nrm.dot(r_) < 0:
            nrm = -nrm
        # knuckles: gunmetal barrels with amber caps
        bm, bm_c = bmesh.new(), bmesh.new()
        for P_, rr in ((K, 0.036), (J2, 0.03)):
            bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=rr, radius2=rr, depth=0.085,
                                  matrix=_cone_matrix(P_ - t_ * 0.0425, t_, 0.085))
            bmesh.ops.create_cone(bm_c, cap_ends=True, segments=12, radius1=rr * 0.5, radius2=rr * 0.5, depth=0.093,
                                  matrix=_cone_matrix(P_ - t_ * 0.0465, t_, 0.093))
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Knuckles', bm, ['Gunmetal'], smooth=False), 0.004, 1))
        k.add(fname, k.mesh_object(fname + 'Caps', bm_c, ['Amber'], smooth=False))
        # the arm: a gunmetal strut under an orange armour plate with a cyan slot
        L = (J2 - K).length
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2, d1, nrm, 0.05, 0.036, L, 0.85)
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Strut', bm, ['Gunmetal'], smooth=False)))
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2 + nrm * 0.026 - d1 * 0.005, d1, nrm, 0.078, 0.022, L * 0.82, 0.72)
        k.add(fname, _bevel(bpy, k.mesh_object(fname + 'Armour', bm, ['Armour'], smooth=False), 0.005))
        bm = bmesh.new()
        _frustum(bm, (K + J2) / 2 + nrm * 0.0375 - d1 * 0.01, d1, nrm, 0.014, 0.004, L * 0.5, 0.7)
        k.add(fname, k.mesh_object(fname + 'Slot', bm, ['Cyan'], smooth=False))

        # the talon: a faceted blade (a diamond section) curving in toward the axis
        steps = 14
        pts, secs = [], []
        for i in range(steps + 1):
            s = i / steps
            pts.append(J2 + F * (0.19 * s) + r_ * (0.04 * s - 0.26 * s ** 1.6))
        blade = bmesh.new()
        armour = bmesh.new()
        edge_pts = []
        rings = []
        for i, p in enumerate(pts):
            s = i / steps
            tg = (pts[min(i + 1, steps)] - pts[max(i - 1, 0)]).normalized()
            m = tg.cross(t_).normalized()          # the talon's back (away from the axis)
            w = 0.05 * (1 - s) ** 0.55 + 0.002
            h = 0.044 * (1 - s) ** 0.7 + 0.002
            rings.append([blade.verts.new(p + t_ * w), blade.verts.new(p + m * h),
                          blade.verts.new(p - t_ * w), blade.verts.new(p - m * h * 1.25)])
            if 0.3 <= s <= 0.93:
                edge_pts.append(p - m * h * 1.25)
            secs.append((p, m, w, h))
        for i in range(steps):
            a_, b_ = rings[i], rings[i + 1]
            for j in range(4):
                blade.faces.new((a_[j], a_[(j + 1) % 4], b_[(j + 1) % 4], b_[j]))
        blade.faces.new(rings[0][::-1])
        blade.faces.new(rings[-1])
        k.add(tname, k.mesh_object(tname + 'Blade', blade, ['Steel'], smooth=False))
        # an orange armour sleeve over the talon's root (a hexagonal section, slightly larger)
        rings = []
        cut = [(p, m, w, h) for (p, m, w, h), i in zip(secs, range(steps + 1)) if i / steps <= 0.58]
        for p, m, w, h in cut:
            rings.append([armour.verts.new(p + t_ * w * 1.25 + m * h * 0.3), armour.verts.new(p + m * h * 1.35),
                          armour.verts.new(p - t_ * w * 1.25 + m * h * 0.3), armour.verts.new(p - t_ * w * 1.1 - m * h * 0.6),
                          armour.verts.new(p + t_ * w * 1.1 - m * h * 0.6)])
        for i in range(len(rings) - 1):
            a_, b_ = rings[i], rings[i + 1]
            for j in range(5):
                armour.faces.new((a_[j], a_[(j + 1) % 5], b_[(j + 1) % 5], b_[j]))
        armour.faces.new(rings[0][::-1])
        armour.faces.new(rings[-1])
        k.add(tname, _bevel(bpy, k.mesh_object(tname + 'Armour', armour, ['Armour'], smooth=False), 0.003, 1))
        bm = bmesh.new()
        sweep(bm, edge_pts, [0.0045 * (1 - 0.6 * i / (len(edge_pts) - 1)) for i in range(len(edge_pts))], segs=6)
        k.add(tname, k.mesh_object(tname + 'Edge', bm, ['Cyan']))


# =============================================================================================
# Eclipse (S1)
# =============================================================================================

@piece
def eclipse(k):
    """A floating total eclipse past the butt: a black sphere in a blazing gold corona (two
    ForceField shells, bright at the rim from every side), held by a black-and-gold cage of four
    curved gold prongs; two thin gold orbit rings precess round it, a small cratered silver moon
    orbits it, obsidian shards drift round the mount."""
    import bmesh
    import random
    from mathutils import Vector, Matrix
    bpy = k.bpy
    k.material('Obsidian', 'SmoothPlastic', '#0B0B0D', Reflectance=0.35)
    k.material('Gold', 'Foil', '#E3A21A')
    k.material('Void', 'SmoothPlastic', '#050505', Reflectance=0.25)
    k.material('Corona', 'ForceField', '#FFB300', Transparency=0.05)
    k.material('Halo', 'ForceField', '#FFF1B0', Transparency=0.45)
    k.material('Flare', 'Neon', '#FFC940')
    k.material('Moon', 'SmoothPlastic', '#D4D8DE', Reflectance=0.15)

    U0 = 7.0
    RS, UC = 0.28, 0.56                         # the sphere's radius and centre past the butt

    def rad(a):
        return Vector((math.sin(math.radians(a)), 0, math.cos(math.radians(a))))

    def at(u, r, a):
        return Vector((0, -(U0 + u), 0)) + rad(a) * r

    C = at(UC, 0, 0)

    # the mount: a flared obsidian cup with gold rings, four gold prongs and a cage ring
    k.joint('Mount', pivot=(0, -U0, 0))
    prof = [(-0.1, 0.104), (-0.06, 0.108), (0.0, 0.114), (0.05, 0.126), (0.09, 0.148), (0.11, 0.155), (0.115, 0.1)]
    bm = bmesh.new()
    sweep(bm, [(0, -(U0 + u), 0) for u, _ in prof], [r for _, r in prof], segs=40)
    k.add('Mount', k.mesh_object('EclipseCup', bm, ['Obsidian']))
    bm = bmesh.new()
    for u, r, tube in ((-0.085, 0.111, 0.009), (-0.045, 0.114, 0.006), (0.01, 0.12, 0.011), (0.1, 0.156, 0.012)):
        sweep(bm, [at(u, r, 360 * i / 56) for i in range(57)], [tube] * 57, segs=10, cap=False)
    for a in (45, 135, 225, 315):
        path, radii = [], []
        for i in range(19):
            s = i / 18
            u = 0.1 + 0.62 * s
            r = 0.15 + 0.25 * math.sin(math.pi * min(s / 0.8, 1.0) * 0.62) - 0.12 * max(s - 0.7, 0) / 0.3
            path.append(at(u, r, a + 18 * s))
            radii.append(0.02 * (1 - s) + 0.005)
        sweep(bm, path, radii, segs=10)
    # a cage ring round the sphere's back and a thin one round its front
    for u, r, tube in ((UC - 0.14, RS + 0.1, 0.01), (UC + 0.1, RS + 0.07, 0.006)):
        sweep(bm, [at(u, r, 360 * i / 64) for i in range(65)], [tube] * 65, segs=8, cap=False)
    k.add('Mount', k.mesh_object('EclipseGold', bm, ['Gold']))

    # the eclipse: a black sphere inside two corona shells, floating (a slow bob)
    k.joint('Orb', pivot=tuple(C), parent='Mount', motion=[{'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.012, 'Period': 3.4}])
    for name, mat, r, segs in (('EclipseVoid', 'Void', RS, 48), ('EclipseCorona', 'Corona', RS * 1.09, 40), ('EclipseHalo', 'Halo', RS * 1.24, 32)):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2, radius=r, matrix=_scale_at(C, (1, 1, 1)))
        k.add('Orb', k.mesh_object(name, bm, [mat]))

    # two thin gold orbit rings, tilted, precessing
    for n, (tilt, rate, rr) in enumerate(((68, 22.0, RS + 0.16), (-58, -30.0, RS + 0.22)), 1):
        nm = 'Ring%d' % n
        k.joint(nm, pivot=tuple(C), parent='Orb', motion=[{'Kind': 'Spin', 'Axis': (0, 0.25, 1), 'Rate': rate}])
        R = Matrix.Rotation(math.radians(tilt), 3, 'X')
        bm = bmesh.new()
        sweep(bm, [C + R @ Vector((rr * math.cos(2 * math.pi * i / 72), rr * math.sin(2 * math.pi * i / 72), 0)) for i in range(73)],
              [0.0055] * 73, segs=6, cap=False)
        k.add(nm, k.mesh_object('Eclipse' + nm, bm, ['Flare']))

    # the moon: a small cratered silver sphere orbiting on a tilted path
    axis = Vector((0.35, 0.2, 1)).normalized()
    k.joint('Moon', pivot=tuple(C), parent='Orb', motion=[{'Kind': 'Spin', 'Axis': tuple(axis), 'Rate': 70.0}])
    side = axis.cross(Vector((0, 1, 0))).normalized()
    M = C + side * (RS + 0.2)
    craters = [(M + Vector(d).normalized() * 0.066, (0.022, 0.022, 0.022), None, True)
               for d in ((1, 0.2, 0.3), (-0.4, 1, 0.5), (0.2, -0.6, 1), (-1, -0.3, -0.2), (0.3, 0.8, -1), (0.9, -0.9, -0.1))]
    moon = metaball_mesh(bpy, 'EclipseMoon', [(M, (0.068, 0.068, 0.068), None, False)] + craters, resolution=0.006)
    moon.data.materials.append(k.blender_mat('Moon'))
    k.add('Moon', moon)

    # obsidian shards drifting round the mount
    k.joint('Debris', pivot=(0, -U0, 0), parent='Mount', motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 16.0},
                                                               {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.02, 'Period': 2.7}])
    rnd = random.Random(7)
    bm = bmesh.new()
    for i in range(9):
        a = 40 * i + rnd.uniform(-12, 12)
        p = at(rnd.uniform(-0.05, 0.4), rnd.uniform(0.3, 0.46), a)
        geom = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        s = rnd.uniform(0.018, 0.034)
        for v in geom['verts']:
            v.co = Vector((v.co.x * s * rnd.uniform(0.7, 1.3), v.co.y * s * rnd.uniform(1.0, 1.8), v.co.z * s * rnd.uniform(0.6, 1.1)))
            v.co = Matrix.Rotation(rnd.uniform(0, 6.28), 3, 'Z') @ v.co + p
    k.add('Debris', k.mesh_object('EclipseShards', bm, ['Obsidian'], smooth=False))
