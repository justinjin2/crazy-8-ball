"""The pocket finishers' creatures (designer, 2026-09-30: set pieces are real 3D, not flat
flipbooks): a 3D piece that rises out of the pocket, turned to face the camera, grows, and fades.
The skin's vfx.Pocket.Piece gives its timing (see CuePreview.PocketPiece).

Each is modelled in the 'pocket' frame (CuePieces.Kit.frame): the origin at the pocket's mouth,
Z up, the creature's front toward -Y. The generated ones (Meshy, assets/cue/models/pocket_*)
glow from within like a spirit: an emissive mask from the colour map's own brightness, tinted
per creature, over their own colour, normal, roughness and metal maps.
"""
import math

from CuePieces import piece, sweep


def _spirit_glow(px):
    """The whole creature glows, its bright parts most (a spirit made of light)."""
    import numpy as np
    luma = px[..., 0] * 0.3 + px[..., 1] * 0.59 + px[..., 2] * 0.11
    return 0.08 + 0.5 * np.clip(luma, 0, 1) ** 2.2


def _stand(height):
    """place(ob): scaled to `height` studs tall, centred over the origin, its lowest point at it."""
    def place(ob):
        import numpy as np
        from mathutils import Matrix
        V = np.array([v.co[:] for v in ob.data.vertices])
        lo, hi = V.min(0), V.max(0)
        s = height / (hi[2] - lo[2])
        return Matrix.Scale(s, 4) @ Matrix.Translation((-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    return place


@piece
def celestial_dragon_pocket(k):
    """The Celestial Dragon rears up out of the pocket, roaring: a generated model (a pearl-white
    serpentine dragon, gold horns and ridge, a white-and-blue mane, clawed forelegs), 3.2 studs
    tall, glowing icy blue from within. It sways slowly as it rises."""
    k.frame = 'pocket'
    k.joint('Body', pivot=(0, 0, 0), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 4.0, 'Period': 2.4},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 1.9, 'Phase': 60}])
    k.model('Body', 'PocketDragon', 'pocket_dragon', _stand(3.2), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#8CC8FF', emissive_strength=2.0)


@piece
def kitsune_pocket(k):
    """The Kitsune's spirit fox leaps up out of the pocket: a generated model (a white fox mid-leap
    wearing the porcelain mask, nine tails tipped pink and violet), 3.0 studs tall, glowing violet
    from within. It sways as it rises."""
    k.frame = 'pocket'
    k.joint('Body', pivot=(0, 0, 0.6), motion=[
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 5.0, 'Period': 2.0},
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': 1.6, 'Phase': 90}])
    k.model('Body', 'PocketFox', 'pocket_fox', _stand(3.0), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#D08CFF', emissive_strength=2.0)


@piece
def phoenix_pocket(k):
    """The Phoenix's firebird rises out of the pocket, wings spread: a generated model (flame-shaped
    feathers crimson to orange to gold), 3.2 studs tall, burning gold from within."""
    k.frame = 'pocket'
    k.joint('Body', pivot=(0, 0, 0.8), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 1.4}])
    k.model('Body', 'PocketFirebird', 'pocket_firebird', _stand(3.2), target_tris=19500, emissive=_spirit_glow,
            emissive_tint='#FFB040', emissive_strength=2.4)


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
    """The Infernal's horned skull rises out of the hellfire eruption and glares: the same generated
    model as the butt's skull (assets/cue/models/infernal_skull, its bust cut away), 2.6 studs
    tall, its eyes and magma cracks blazing. Its jaw end dips as it rises (a
    slow nod)."""
    k.frame = 'pocket'
    k.joint('Skull', pivot=(0, 0, 0.4), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': 1.6},
        {'Kind': 'Hinge', 'Axis': (0, 1, 0), 'Amp': 3.0, 'Period': 2.2, 'Phase': 40}])
    k.model('Skull', 'PocketSkull', 'infernal_skull', _stand(2.6), target_tris=19500, emissive=_magma_glow,
            emissive_tint='#FF7A3A', emissive_strength=3.0, cut_below=0.3)
