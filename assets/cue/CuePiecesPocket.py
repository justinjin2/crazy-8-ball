"""The pocket finishers' creatures (designer, 2026-09-30: set pieces are real 3D, not flat
flipbooks): a 3D piece that rises out of the pocket, turned to face the camera, grows, and fades.
The skin's vfx.Pocket.Piece gives its timing (see CuePreview.PocketPiece).

Each is modelled in the 'pocket' frame (CuePieces.Kit.frame): the origin at the pocket's mouth,
Z up, the creature's front toward -Y. The generated ones (Meshy, assets/cue/models/pocket_*)
glow from within like a spirit: an emissive mask from the colour map's own brightness, tinted
per creature, over their own colour, normal, roughness and metal maps.
"""
import math

from CuePieces import piece, sweep, ramp


def _spirit_glow(px):
    """The whole creature glows, its bright parts most (a spirit made of light)."""
    import numpy as np
    luma = px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11
    return 0.08 + 0.5 * np.clip(luma, 0, 1) ** 2.2


def _stand(height, yaw=0.0):
    """place(ob): scaled to `height` studs tall, centred over the origin, its lowest point at it,
    then turned `yaw` degrees about the vertical (a model facing -Y turned 90 faces +X, its side
    to the camera)."""
    def place(ob):
        import math
        import numpy as np
        from mathutils import Matrix
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s = height / (hi[2] - lo[2])
        return (Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Scale(s, 4)
                @ Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2])))
    return place


def _yaw90(p):
    """A point or axis in a -Y-facing model's own frame, after _stand(..., yaw=90)."""
    return (-p[1], p[0], p[2])


def _unyaw90(fn):
    """A bone weight written in the model's own frame, read in the turned frame."""
    import numpy as np
    return lambda V: fn(np.stack([V[:, 1], -V[:, 0], V[:, 2]], 1))


@piece
def celestial_dragon_pocket(k):
    """The Celestial Dragon rears up out of the pocket, roaring: a generated model (a serpentine
    dragon, horns and ridge, a flowing mane, clawed forelegs), 3.2 studs tall, turned side-on so
    its S-curve and roaring head face the table, rigged (designer, 2026-09-30) and drawn as a spirit of icy blue light (see-through, glowing, in a shimmering
    shell). It sways as it rises; its head nods, its jaw opens in a roar, its mane streams and its
    forelegs claw at the air."""
    import numpy as np
    k.frame = 'pocket'
    k.joint('Body', pivot=_yaw90((0, 0, 0)), motion=[
        {'Kind': 'Hinge', 'Axis': _yaw90((0, 1, 0)), 'Amp': 4.0, 'Period': 2.4},
        {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Amp': 3.0, 'Period': 1.9, 'Phase': 60}])
    k.joint('Neck', pivot=_yaw90((0, 0.0, 1.9)), parent='Body', motion=[
        {'Kind': 'Hinge', 'Axis': _yaw90((0, 1, 0)), 'Amp': 5.0, 'Period': 2.2, 'Phase': 30},
        {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Amp': 4.0, 'Period': 1.7}])
    k.joint('Head', pivot=_yaw90((0, -0.2, 2.35)), parent='Neck', motion=[
        {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Amp': 6.0, 'Period': 1.6, 'Phase': 90}])
    k.joint('Jaw', pivot=_yaw90((0, -0.36, 2.45)), parent='Head', motion=[
        {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Base': 9.0, 'Amp': 9.0, 'Period': 1.2}])
    k.joint('Mane', pivot=_yaw90((0, 0.2, 2.3)), parent='Head', motion=[
        {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Amp': 6.0, 'Period': 1.1, 'Phase': 45}])
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        k.joint('Arm' + sname, pivot=_yaw90((0.2 * side, -0.3, 1.75)), parent='Neck', motion=[
            {'Kind': 'Hinge', 'Axis': _yaw90((1, 0, 0)), 'Amp': 12.0, 'Period': 1.4, 'Phase': 0 if side > 0 else 120}])

    def arm(side):
        return lambda V: (ramp(V[:, 0] * side, 0.16, 0.3) * ramp(V[:, 2], 1.95, 1.75) * ramp(V[:, 2], 1.1, 1.25)
                          * ramp(V[:, 1], -0.15, -0.32))

    bones = {'Neck': lambda V: ramp(V[:, 2], 1.8, 2.1),
             'Head': lambda V: ramp(V[:, 2], 2.2, 2.4) * ramp(V[:, 1], 0.12, -0.08),
             'Jaw': lambda V: ramp(V[:, 1], -0.38, -0.5) * ramp(V[:, 2], 2.47, 2.39) * ramp(V[:, 2], 2.15, 2.25),
             'Mane': lambda V: ramp(V[:, 1], 0.08, 0.35) * ramp(V[:, 2], 2.0, 2.3),
             'ArmRight': arm(1), 'ArmLeft': arm(-1)}
    bones = {b: _unyaw90(f) for b, f in bones.items()}   # written facing -Y, the model is turned 90
    k.model('Body', 'PocketDragon', 'pocket_dragon', _stand(3.2, yaw=90), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#8CC8FF', emissive_strength=2.0, bones=bones,
            hologram={'Tint': '#7AC0FF', 'Shell': '#CFEAFF', 'Strength': 1.8})


@piece
def kitsune_pocket(k):
    """The Kitsune's spirit fox leaps up out of the pocket: a generated model (a fox mid-leap wearing
    the porcelain mask, nine tails fanned behind it), 3.0 studs tall, rigged (designer, 2026-09-30)
    and drawn as a spirit of violet light (see-through, glowing, in a shimmering shell). Its head
    tilts; its nine tails sway as a fan, their tips whipping a beat behind."""
    import numpy as np
    k.frame = 'pocket'
    k.joint('Body', pivot=(0.4, 0, 1.6), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 5.0, 'Period': 2.0},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': 1.6, 'Phase': 90}])
    k.joint('Head', pivot=(0.62, -0.1, 2.45), parent='Body', motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': 1.8, 'Phase': 20},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 5.0, 'Period': 2.3}])
    ROOT = (0.15, 1.45)                             # where the tails fan from (x, z)
    k.joint('Tails', pivot=(ROOT[0], 0, ROOT[1]), parent='Body', motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 6.0, 'Period': 2.0, 'Phase': 50}])
    k.joint('TailTips', pivot=(ROOT[0], 0, ROOT[1]), parent='Tails', motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 9.0, 'Period': 1.6, 'Phase': 70},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 7.0, 'Period': 2.0, 'Phase': 120}])

    def body(V):
        return ramp(V[:, 0], 0.22, 0.36) * ramp(V[:, 2], 1.65, 1.85)

    def dist(V):
        return np.hypot(V[:, 0] - ROOT[0], V[:, 2] - ROOT[1])

    bones = {'Head': lambda V: ramp(V[:, 2], 2.36, 2.52) * ramp(V[:, 0], 0.44, 0.56),
             'Tails': lambda V: (1 - body(V)) * ramp(dist(V), 0.25, 0.6),
             'TailTips': lambda V: ramp(dist(V), 0.8, 1.3)}
    k.model('Body', 'PocketFox', 'pocket_fox', _stand(3.0), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#D08CFF', emissive_strength=2.0, bones=bones,
            hologram={'Tint': '#C88CFF', 'Shell': '#F0D0FF', 'Strength': 1.8})

@piece
def phoenix_pocket(k):
    """The Phoenix's firebird rises out of the pocket, wings beating: a generated model (flame-shaped
    feathers crimson to orange to gold), 3.2 studs tall, rigged (designer, 2026-09-30) and drawn as
    a spirit of golden fire (see-through, glowing, in a shimmering shell). Its wings beat, the tips
    whipping a beat behind; its head sways; its long tail swishes in two parts."""
    import numpy as np
    k.frame = 'pocket'
    k.joint('Body', pivot=(0, 0, 0.8), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 1.4}])
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        axis = (0, -side, 0)                       # up for both wings at once
        k.joint('Wing' + sname, pivot=(0.27 * side, 0, 2.15), parent='Body', motion=[
            {'Kind': 'Hinge', 'Axis': axis, 'Base': 4.0, 'Amp': 28.0, 'Period': 0.9}])
        k.joint('WingTip' + sname, pivot=(0.8 * side, 0, 2.35), parent='Wing' + sname, motion=[
            {'Kind': 'Hinge', 'Axis': axis, 'Amp': 16.0, 'Period': 0.9, 'Phase': 60}])
    k.joint('Head', pivot=(0.02, -0.05, 2.5), parent='Body', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 6.0, 'Period': 1.8},
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 8.0, 'Period': 2.6, 'Phase': 40}])
    k.joint('Tail', pivot=(0.05, 0, 1.35), parent='Body', motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 5.0, 'Period': 2.1, 'Phase': 30}])
    k.joint('TailTip', pivot=(0.1, 0, 0.6), parent='Tail', motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 10.0, 'Period': 1.6, 'Phase': 60}])

    def wing(side, tip=False):
        def w(V):
            x = V[:, 0] * side
            if tip:
                return ramp(x, 0.65, 0.95)
            return ramp(x, 0.2, 0.42) * ramp(V[:, 2], 1.2, 1.5)
        return w

    bones = {'WingRight': wing(1), 'WingTipRight': wing(1, True), 'WingLeft': wing(-1), 'WingTipLeft': wing(-1, True),
             'Head': lambda V: ramp(V[:, 2], 2.4, 2.62) * (1 - ramp(np.abs(V[:, 0]), 0.22, 0.32)),
             'Tail': lambda V: ramp(V[:, 2], 1.3, 0.95),
             'TailTip': lambda V: ramp(V[:, 2], 0.7, 0.35)}
    k.model('Body', 'PocketFirebird', 'pocket_firebird', _stand(3.2), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#FFB040', emissive_strength=2.4, bones=bones,
            hologram={'Tint': '#FFA030', 'Shell': '#FFC060', 'Strength': 1.6})


@piece
def kraken_pocket(k):
    """The Kraken's pocket finisher: one great spectral tentacle bursts up out of the pocket and
    curls over at the top, see-through violet energy over a dim violet core with a row of glowing
    cyan suckers; a chain of six segments so a quick wave runs up it as it rises."""
    import bmesh
    from mathutils import Vector
    k.frame = 'pocket'
    k.material('Ink', 'ForceField', '#8A4CFF')
    k.material('Core', 'Neon', '#3C1C96', Transparency=0.45)
    k.material('Sucker', 'Neon', '#2EF2FF')
    H = 3.2
    CUTS = [0.0, 0.2, 0.38, 0.54, 0.68, 0.82, 1.0]

    def P(s):
        # up, leaning a little, then curling over and back down at the top
        z = H * (s if s < 0.7 else 0.7 + 0.3 * math.sin((s - 0.7) / 0.3 * math.pi / 2))
        curl = max(0.0, s - 0.6) / 0.4
        x = 0.25 * math.sin(s * 2.4) + 0.9 * curl ** 1.6
        z -= 0.7 * curl ** 2.5
        return Vector((x, -0.1 * math.sin(s * 3.1), z))

    def width(s):
        return 0.34 * (1 - s) ** 0.8 + 0.03

    parent = None
    for si in range(len(CUTS) - 1):
        s0, s1 = CUTS[si], CUTS[si + 1]
        name = 'Seg%d' % (si + 1)
        piv = P(s0)
        k.joint(name, pivot=tuple(piv), parent=parent, motion=[
            {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0 + 2.0 * si, 'Period': 1.5, 'Phase': si * 45},
            {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 2.0 + 1.0 * si, 'Period': 1.9, 'Phase': si * 30}])
        parent = name
        n = 16
        lo = max(0.0, s0 - 0.025)
        ss = [lo + (s1 - lo) * i / (n - 1) for i in range(n)]
        pts = [P(s) for s in ss]
        bm_i, bm_c, bm_s = bmesh.new(), bmesh.new(), bmesh.new()
        sweep(bm_i, pts, [width(s) for s in ss], segs=16, cap=True)
        sweep(bm_c, pts, [width(s) * 0.55 for s in ss], segs=10, cap=True)
        m = 5
        for j in range(m):
            s = s0 + (s1 - s0) * (j + 0.5) / m
            if s > 0.95:
                continue
            c = P(s)
            t_ = (P(min(s + 0.01, 1.0)) - c).normalized()
            side = t_.cross(Vector((0, 1, 0))).normalized()   # the underside of the curl
            if side.length < 0.5:
                continue
            w = width(s)
            r = w * 0.42
            mat = (-side).to_track_quat('Z', 'Y').to_matrix().to_4x4()
            mat.translation = c - side * (w * 0.9)
            bmesh.ops.create_cone(bm_s, cap_ends=True, segments=12, radius1=r, radius2=r * 0.8, depth=w * 0.22,
                                  matrix=mat)
        k.add(name, k.mesh_object(name + 'Ink', bm_i, ['Ink']))
        k.add(name, k.mesh_object(name + 'Core', bm_c, ['Core']))
        k.add(name, k.mesh_object(name + 'Suckers', bm_s, ['Sucker'], smooth=False))


def _magma_glow(px):
    """Only the skull's eyes and magma cracks blaze (a glow over the whole skull washed its
    silver and obsidian to copper)."""
    from CuePiecesLegendary import _magma
    return _magma(px)


@piece
def infernal_pocket(k):
    """The Infernal's horned skull rises out of the hellfire eruption: the same generated model as
    the butt's skull (assets/cue/models/infernal_skull, its bust cut away), 2.6 studs tall, rigged
    (designer, 2026-09-30) and drawn as a spirit of hellfire (see-through, glowing orange-red, in a
    shimmering shell), its eyes and magma cracks blazing. It nods as it rises and its jaw gnashes."""
    k.frame = 'pocket'
    k.joint('Skull', pivot=(0, 0, 0.4), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0, 'Period': 2.2, 'Phase': 40}])
    k.joint('Jaw', pivot=(0, 0.0, 0.58), parent='Skull', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 13.0, 'Amp': 13.0, 'Period': 0.9, 'Shape': 'snap'}])
    bones = {'Jaw': lambda V: ramp(V[:, 2], 0.62, 0.46) * ramp(V[:, 1], -0.1, -0.35)}
    k.model('Skull', 'PocketSkull', 'infernal_skull', _stand(2.6), target_tris=19500, emissive=_magma_glow,
            emissive_tint='#FF7A3A', emissive_strength=3.0, cut_below=0.3, bones=bones,
            hologram={'Tint': '#FF6A2A', 'Shell': '#FFB060', 'Strength': 1.8})

@piece
def clockwork_pocket(k):
    """The Clockwork's pocket finisher: three big meshing gears (brass, copper, brass) rise out of
    the pocket standing face-on to the camera, turning together, their hubs and inlaid rings glowing amber."""
    import bmesh
    from mathutils import Matrix
    from CuePieces import apply_modifier
    from CuePiecesLegendary import _gear, _glow_ring
    k.frame = 'pocket'
    k.material('Brass', 'Foil', '#EDBE58')
    k.material('Copper', 'Foil', '#DE8A4E')
    k.material('Glow', 'Neon', '#FFB040')
    MODULE = 0.075            # studs of radius per tooth, shared so the teeth mesh
    gears = [('Big', 0.95, 'Brass', 1, 6), ('Mid', 0.58, 'Copper', -1, 5), ('Small', 0.42, 'Brass', -1, 5)]
    big_r = 0.95

    def pitch(r):
        return r - min(0.045 * 3.2, r * 0.2) / 2

    # the big gear 1.35 studs up; the mid one meshes on its upper left, the small on its right
    centres = {'Big': (0.0, 1.35)}
    for name, r, ang in (('Mid', 0.58, math.radians(140)), ('Small', 0.42, math.radians(20))):
        d = pitch(big_r) + pitch(r)
        centres[name] = (d * math.cos(ang), 1.35 + d * math.sin(ang))
    for name, r, mat, sign, spokes in gears:
        cx, cz = centres[name]
        teeth = max(8, round(r / MODULE))
        rate = sign * 110.0 * 0.5 / r
        phase = 0.0 if name == 'Big' else 180.0 / teeth
        k.joint(name, pivot=(cx, 0, cz), motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate, 'Phase': phase}])
        bm_g, bm_h = bmesh.new(), bmesh.new()
        _gear(bm_g, r, teeth, 0.09, spokes=spokes, tooth_scale=3.2)
        bmesh.ops.create_cone(bm_h, cap_ends=True, segments=20, radius1=r * 0.13, radius2=r * 0.13, depth=0.16)
        _glow_ring(bm_h, r, 0.09)
        # the gear's face to the camera (-Y): its axle along Y
        M = Matrix.Translation((cx, 0, cz)) @ Matrix.Rotation(math.pi / 2, 4, 'X')
        bmesh.ops.transform(bm_g, matrix=M, verts=bm_g.verts)
        bmesh.ops.transform(bm_h, matrix=M, verts=bm_h.verts)
        ob = k.add(name, k.mesh_object(name + mat, bm_g, [mat], smooth=False))
        apply_modifier(k.bpy, ob, 'BEVEL', width=0.012, segments=1, limit_method='ANGLE')
        k.add(name, k.mesh_object(name + 'Hub', bm_h, ['Glow'], smooth=False))
