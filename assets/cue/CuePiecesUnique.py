"""The Unique cues' pieces (the Beta Cue and the Firework Cue, 2026-10-04; see CuePieces.py
for the kit and export). Modelled in the cue's Blender frame: X the side, Y from the tip (0)
toward the butt (-7), Z up; the pocket finisher in the pocket frame (origin at the mouth, Z up).

    beta            a Neon wireframe lattice shell round the body (turning), magenta rings at
                    the joint and collar, a scan plane sliding tip to butt, and eight blueprint
                    panels floating well beyond the cue (aura joints: textured panes with Neon
                    frames and a leader line each, orbiting slowly at three radii)
    beta_pocket     a wireframe funnel with glowing rings, rising out of the pocket, turning
    grand_opening   two flat Neon gold ribbons spiralling round the whole cue in opposite senses,
                    turning like a screw so the sparkle streams along the cue
"""
import math

from CuePieces import piece, apply_modifier

PANEL_TEXTURES = 8  # tools/unique_panels.py draws vfx/beta/panel_<n>.png (+ _emissive)


def _radius():
    """The cue's radius at distance d from the tip (Shape.json's envelope)."""
    import cue_common as cc
    return cc.Envelope(cc.load_shape()[0])


def _ring_verts(bm, d, r, segs, twist=0.0):
    from mathutils import Vector
    out = []
    for k in range(segs):
        a = 2 * math.pi * k / segs + twist
        out.append(bm.verts.new(Vector((r * math.sin(a), -d, -r * math.cos(a)))))
    return out


def _lathe(bm, ds, rs, segs, twist_per_ring=0.0, close=False):
    """A tube of rings (quads between them) along the cue; twist turns each ring on from the
    last so the quads' edges run diagonally (a diamond lattice once wireframed)."""
    rings = []
    for i, (d, r) in enumerate(zip(ds, rs)):
        rings.append(_ring_verts(bm, d, r, segs, twist_per_ring * i))
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if close:
        from mathutils import Vector
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            c = sum((v.co for v in ring), Vector()) / len(ring)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[(k + 1) % segs], cv)
                bm.faces.new(q[::-1] if rev else q)
    return rings


def _torus(bm, centre, axis, R, r, segs=32, minor=10):
    """A torus of major radius R and tube radius r round `axis` (unit Vector) through centre."""
    from mathutils import Vector
    axis = Vector(axis).normalized()
    u = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 0, 1))
    u = (u - axis * axis.dot(u)).normalized()
    v = axis.cross(u)
    grid = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        radial = u * math.cos(a) + v * math.sin(a)
        ring = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            p = Vector(centre) + radial * (R + r * math.cos(b)) + axis * (r * math.sin(b))
            ring.append(bm.verts.new(p))
        grid.append(ring)
    for i in range(segs):
        a, b = grid[i], grid[(i + 1) % segs]
        for j in range(minor):
            bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor]))


def _box(bm, centre, size, basis=None):
    """An axis-aligned box (or one in the orthonormal `basis` (x, y, z) Vectors) at centre."""
    from mathutils import Vector
    cx, cy, cz = size[0] / 2, size[1] / 2, size[2] / 2
    bx, by, bz = basis or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    c = Vector(centre)
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corners.append(bm.verts.new(c + bx * (sx * cx) + by * (sy * cy) + bz * (sz * cz)))
    # corners index: sx*4 + sy*2 + sz with (-1 -> 0, 1 -> 1)
    def V(sx, sy, sz):
        return corners[(sx * 4) + (sy * 2) + sz]
    faces = [((0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)), ((1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0)),
             ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)), ((0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)),
             ((0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)), ((0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1))]
    for f in faces:
        bm.faces.new(tuple(V(*q) for q in f))


# =============================================================================================
# Beta Cue
# =============================================================================================

# The eight panels: (distance along the cue, angle round it in degrees from the top, radius from
# the axis, width, height, tilt degrees about the radial, orbit degrees a second, texture)
# Each Beta panel's life (seconds) and the share of it already run at t = 0, so five or six of
# the eight are up at any moment and no two are born together.
PANEL_LIFE = [(7.5, 0.0), (8.5, 0.37), (6.5, 0.62), (9.0, 0.18), (7.0, 0.8), (8.0, 0.5), (6.0, 0.28), (9.5, 0.7)]

BETA_PANELS = [
    (1.1, 40, 1.05, 0.95, 0.58, 18, 5.0, 1),
    (2.0, 200, 1.55, 0.7, 0.45, -24, -4.0, 2),
    (2.9, 110, 0.95, 1.25, 0.72, 10, 6.5, 3),
    (3.8, 300, 1.85, 0.8, 0.5, -14, -5.5, 4),
    (4.6, 20, 1.25, 1.0, 0.6, 22, 4.5, 5),
    (5.4, 160, 1.9, 1.3, 0.75, -8, -3.5, 6),
    (6.2, 250, 1.1, 0.75, 0.48, 16, 7.0, 7),
    (7.3, 80, 1.5, 1.05, 0.62, -20, -6.0, 8),
]


@piece
def beta(k):
    """The hologram's depth: a Neon wireframe lattice round the body (rings every 0.32 studs,
    ten longitudinal lines, the wrap's stretch twisted into a diamond lattice), turning 9
    degrees a second; four magenta rings (tori) at the joint collar and two on the butt sleeve;
    a scan plane (a ForceField disc with a white-blue Neon rim) sweeping tip to butt every
    2.6 s, fading at both ends; a glitch every 4 s (sideways jolts, a blink) on the lattice and
    the rings; the rings pulsing; eight blueprint panels as aura joints: a textured pane (vfx/beta/panel_n.png,
    AlphaMode Transparency, glowing) in a Neon frame with a leader line down to the cue's
    surface, each orbiting the cue slowly and bobbing."""
    import bmesh
    from mathutils import Vector, Matrix
    R = _radius()
    k.material('Lattice', 'Neon', '#3B8CFF', Transparency=0.3)
    k.material('Ring', 'Neon', '#FF3FD6')
    k.material('RingEdge', 'Neon', '#FFD9F8')
    k.material('ScanRim', 'Neon', '#DFF6FF')
    k.material('ScanDisc', 'ForceField', '#7FD4FF', Transparency=0.4)
    k.material('Frame', 'Neon', '#3FA9FF')
    k.material('Leader', 'Neon', '#3FA9FF', Transparency=0.35)

    # --- the lattice shell -----------------------------------------------------------------
    # Turning slowly; every 4 s a glitch: three sideways jolts over 0.2 s while the shell blinks,
    # and a slow glow pulse (the light flowing through the lattice).
    k.joint('Lattice', pivot=(0, -3.5, 0), motion=[
        {'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': 9.0},
        {'Kind': 'Glitch', 'Dir': (1, 0, 0), 'Amp': 0.07, 'Period': 4.0, 'Seconds': 0.2, 'Steps': 3, 'Phase': 3.0}],
        visual=[
        {'Kind': 'Blink', 'Period': 4.0, 'Seconds': 0.2, 'Count': 4, 'Phase': 3.0},
        {'Kind': 'Glow', 'Min': 0.0, 'Max': 0.3, 'Period': 3.0}])
    bm = bmesh.new()
    ds = [0.3 + 0.32 * i for i in range(int((5.3 - 0.3) / 0.32) + 1)]
    _lathe(bm, ds, [R(d) + 0.045 for d in ds], 10)
    ds2 = [5.4 + 0.25 * i for i in range(7)]
    _lathe(bm, ds2, [R(d) + 0.05 for d in ds2], 10, twist_per_ring=math.pi / 10)
    ob = k.mesh_object('LatticeShell', bm, ['Lattice'], smooth=False)
    apply_modifier(k.bpy, ob, 'WIREFRAME', thickness=0.014, use_replace=True, use_even_offset=False)
    k.add('Lattice', ob)

    # --- the magenta rings ----------------------------------------------------------------
    # The rings pulse: the magenta tori glow toward white every 1.6 s, their thin pale edges
    # fading in and out half a beat behind; the whole collar glitches with the lattice.
    k.joint('Rings', pivot=(0, -3.5, 0), motion=[
        {'Kind': 'Glitch', 'Dir': (1, 0, 0), 'Amp': 0.05, 'Period': 4.0, 'Seconds': 0.2, 'Steps': 3, 'Phase': 3.0}],
        visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.6, 'Period': 1.6}])
    k.joint('RingEdges', pivot=(0, -3.5, 0), parent='Rings',
            visual=[{'Kind': 'Fade', 'Min': 0.1, 'Max': 1.0, 'Period': 1.6, 'Phase': 0.3}])
    bm_r, bm_e = bmesh.new(), bmesh.new()
    for d in (3.62, 3.78, 6.76, 6.9):
        _torus(bm_r, (0, -d, 0), (0, 1, 0), R(d) + 0.035, 0.022)
        for dd in (d - 0.03, d + 0.03):
            _torus(bm_e, (0, -dd, 0), (0, 1, 0), R(d) + 0.04, 0.007, segs=28, minor=6)
    k.add('Rings', k.mesh_object('RingTori', bm_r, ['Ring']))
    k.add('RingEdges', k.mesh_object('RingEdges', bm_e, ['RingEdge']))

    # --- the scan plane --------------------------------------------------------------------
    # The scan line sweeps one way, tip to butt, every 2.6 s (a saw wave along -Y, toward the
    # butt), fading in at the tip and out at the butt so the jump back is never seen.
    k.joint('Scan', pivot=(0, -3.6, 0),
            motion=[{'Kind': 'Bob', 'Dir': (0, -1, 0), 'Amp': 3.3, 'Period': 2.6, 'Shape': 'saw'}],
            visual=[{'Kind': 'Fade', 'Min': 0.0, 'Max': 1.0, 'Period': 2.6}])
    bm_s = bmesh.new()
    _torus(bm_s, (0, -3.6, 0), (0, 1, 0), 0.27, 0.01, segs=40, minor=6)
    k.add('Scan', k.mesh_object('ScanRing', bm_s, ['ScanRim']))
    bm_d = bmesh.new()
    _lathe(bm_d, [3.6 - 0.004, 3.6 + 0.004], [0.265, 0.265], 40, close=True)
    # (_lathe takes d from the tip, positive; a disc is two rings 0.008 apart, both closed)
    k.add('Scan', k.mesh_object('ScanDisc', bm_d, ['ScanDisc']))

    # --- the panels ------------------------------------------------------------------------
    for i, (d, ang, rad, w, h, tilt, orbit, tex) in enumerate(BETA_PANELS):
        name = 'Panel%d' % (i + 1)
        a = math.radians(ang)
        radial = Vector((math.sin(a), 0, math.cos(a)))      # out from the axis (angle from the top)
        along = Vector((0, -1, 0))                          # toward the butt
        tangent = along.cross(radial).normalized()
        centre = Vector((0, -d, 0)) + radial * rad
        # the pane faces outward, turned `tilt` about the radial so it is never flat to the cue
        rot = Matrix.Rotation(math.radians(tilt), 3, radial)
        bx = rot @ along        # the pane's width runs along the cue
        bz = rot @ tangent      # its height runs round
        by = radial             # its normal
        # The four farthest panels (radius 1.5 and more) go under Lower effects (low='hide').
        # Each panel lives PANEL_LIFE[i] seconds: pops in with a blink, types its gibberish
        # (the Type visual: a SurfaceGui riding the joint, on the pane's lower two thirds under
        # the painted title bar), holds, dissolves out, and is reborn with new text.
        life, phase = PANEL_LIFE[i]
        glyph_origin = centre + by * 0.012      # a hair in front of the pane
        k.joint(name, pivot=(0, -d, 0), aura=True, low=('hide' if rad >= 1.5 else None), motion=[
            {'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': orbit, 'Phase': 0},
            {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.03, 'Period': 2.2 + 0.3 * i, 'Phase': 40 * i}],
            visual=[
            {'Kind': 'Fade', 'Min': 0.0, 'Max': 1.0, 'Period': life, 'Phase': phase, 'Shape': 'life'},
            {'Kind': 'Type', 'Frame': {'Origin': [round(v, 4) for v in glyph_origin],
                                       'Right': [round(v, 5) for v in bx], 'Up': [round(v, 5) for v in bz]},
             'Size': [w, h], 'Rows': 3 + (i % 3), 'Cols': int(w * 22), 'Rate': 26 + 4 * (i % 4),
             'Delay': 0.4, 'Period': life, 'Phase': phase, 'Color': '#BFE9FF' if i % 2 else '#7FD4FF',
             'Area': [0.06, 0.3, 0.94, 0.92]}])
        tex_name = 'Pane%d' % (((tex - 1) % PANEL_TEXTURES) + 1)
        n = ((tex - 1) % PANEL_TEXTURES) + 1
        k.material(tex_name, 'SmoothPlastic', '#FFFFFF', SurfaceAppearance={
            'ColorMap': 'vfx/beta/panel_%d.png' % n, 'AlphaMode': 'Transparency',
            'EmissiveMask': 'vfx/beta/panel_%d_emissive.png' % n, 'EmissiveTint': '#9FD0FF',
            'EmissiveStrength': 2.2})
        bm_p = bmesh.new()
        uv = bm_p.loops.layers.uv.new('UVMap')
        corners = [centre + bx * (sx * w / 2) + bz * (sz * h / 2) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        vs = [bm_p.verts.new(p) for p in corners]
        f = bm_p.faces.new(vs)
        for lp, (u_, v_) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[uv].uv = (u_, v_)
        f.normal_update()
        if f.normal.dot(by) < 0:
            bmesh.ops.reverse_faces(bm_p, faces=[f])
        k.add(name, k.mesh_object('%sPane' % name, bm_p, [tex_name], smooth=False))
        # the Neon frame: four thin bars round the pane's edges
        bm_f = bmesh.new()
        t = 0.012
        for sx in (-1, 1):
            _box(bm_f, centre + bx * (sx * w / 2), (t, t, h + t), basis=(bx, by, bz))
        for sz in (-1, 1):
            _box(bm_f, centre + bz * (sz * h / 2), (w + t, t, t), basis=(bx, by, bz))
        k.add(name, k.mesh_object('%sFrame' % name, bm_f, ['Frame'], smooth=False))
        # the leader line: from the pane's inner edge down to the cue's surface
        bm_l = bmesh.new()
        inner = centre - bz * (h / 2) if tilt >= 0 else centre + bz * (h / 2)
        foot = Vector((0, -min(d, 7.0), 0)) + radial * (R(min(d, 7.0)) + 0.01)
        mid = (inner + foot) / 2
        axis = (foot - inner)
        L = axis.length
        bl = axis.normalized()
        bo = bl.cross(radial).normalized() if abs(bl.dot(radial)) < 0.98 else bl.cross(along).normalized()
        bn = bo.cross(bl)
        _box(bm_l, mid, (L, 0.008, 0.008), basis=(bl, bo, bn))
        _box(bm_l, foot, (0.03, 0.03, 0.03), basis=(bl, bo, bn))
        k.add(name, k.mesh_object('%sLeader' % name, bm_l, ['Leader'], smooth=False))


@piece
def beta_pocket(k):
    """The Beta Cue's pocket finisher: a wireframe funnel (Neon blue, 3.6 studs tall, 0.3 to
    1.8 studs wide) rising out of the pocket, turning, with a see-through ForceField skin and
    four glowing rings (magenta and white-blue) up its height."""
    import bmesh
    k.frame = 'pocket'
    # Thick enough to read from across the table (the first build's 0.028 wire vanished at
    # ten studs, 2026-10-04): 0.09-stud Neon wire, fat rings, a denser skin.
    k.material('Wire', 'Neon', '#3B8CFF')
    k.material('Skin', 'ForceField', '#5AB0FF', Transparency=0.35)
    k.material('Ring', 'Neon', '#FF3FD6')
    k.material('Rim', 'Neon', '#DFF6FF')
    k.joint('Funnel', pivot=(0, 0, 0), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 110.0}],
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.5, 'Period': 0.5}])
    H = 3.6
    zs = [H * i / 13 for i in range(14)]
    rs = [0.3 + 1.5 * (z / H) ** 1.8 for z in zs]
    # the pocket frame is Z up: build along Y as _lathe does, then turn Y to Z
    from mathutils import Matrix
    turn = Matrix.Rotation(math.radians(-90), 4, 'X')  # -Y -> ... a lathe along -Y turned up
    for mat, wire in (('Wire', True), ('Skin', False)):
        bm = bmesh.new()
        _lathe(bm, [-z for z in zs], rs, 16, twist_per_ring=(math.pi / 16 if wire else 0.0))
        bmesh.ops.transform(bm, matrix=turn, verts=bm.verts[:])
        ob = k.mesh_object('Funnel' + mat, bm, [mat], smooth=not wire)
        if wire:
            apply_modifier(k.bpy, ob, 'WIREFRAME', thickness=0.09, use_replace=True, use_even_offset=False)
        k.add('Funnel', ob)
    bm_r, bm_m = bmesh.new(), bmesh.new()
    for i, z in enumerate((0.8, 1.7, 2.6, 3.45)):
        r = 0.3 + 1.5 * (z / H) ** 1.8 + 0.03
        _torus(bm_m if i % 2 else bm_r, (0, 0, z), (0, 0, 1), r, 0.07, segs=40, minor=8)
    k.add('Funnel', k.mesh_object('FunnelRings', bm_r, ['Ring']))
    k.add('Funnel', k.mesh_object('FunnelRims', bm_m, ['Rim']))


# =============================================================================================
# Firework Cue
# =============================================================================================

@piece
def grand_opening(k):
    """Two flat Neon gold ribbons (0.05 wide, 0.012 thick) spiralling round the whole cue 0.16
    studs off its surface, a turn every 1.6 studs, in opposite senses; each turns about the
    cue's axis (50 and -50 degrees a second) so, as a screw, its sparkle streams along the cue."""
    import bmesh
    from mathutils import Vector
    R = _radius()
    k.material('RibbonA', 'Neon', '#FFB83A', Transparency=0.1)
    k.material('RibbonB', 'Neon', '#FFD070', Transparency=0.15)
    for name, sense, phase, rate in (('RibbonA', 1, 0.0, 50.0), ('RibbonB', -1, math.pi, -50.0)):
        k.joint(name, pivot=(0, -3.5, 0), motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate}])
        bm = bmesh.new()
        n = 260
        left, right = [], []
        for i in range(n):
            d = 0.3 + (6.95 - 0.3) * i / (n - 1)
            a = sense * 2 * math.pi * d / 1.6 + phase
            radial = Vector((math.sin(a), 0, math.cos(a)))
            p = Vector((0, -d, 0)) + radial * (R(d) + 0.16)
            # the ribbon lies on the cylinder round the cue: its width across the helix, in the
            # surface (tangent to the cylinder), its thin side out
            d2 = min(d + 0.01, 6.95)
            a2 = sense * 2 * math.pi * d2 / 1.6 + phase
            p2 = Vector((0, -d2, 0)) + Vector((math.sin(a2), 0, math.cos(a2))) * (R(d2) + 0.16)
            tang = (p2 - p).normalized()
            across = tang.cross(radial).normalized()
            left.append(bm.verts.new(p - across * 0.025))
            right.append(bm.verts.new(p + across * 0.025))
        for i in range(n - 1):
            bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
        ob = k.mesh_object(name + 'Strip', bm, [name])
        apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=0.012, offset=0.0)
        k.add(name, ob)
