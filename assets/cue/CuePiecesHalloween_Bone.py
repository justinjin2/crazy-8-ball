"""The Bone Cue (Halloween 2026, lane hw-map, 2026-10-28; concept mocks/v2/C7_bone.png, approved by
the coordinator 18:50): a Halloween track cue in the Black Cat's place. Its own body (a `body`
piece that replaces the shared cue mesh) and its pocket finisher. See CuePieces.py for the kit and
CuePiecesHalloween_A.py for the body rules (`check_body`) this body passes before it exports.
Modelled in the cue's Blender frame: X the side, Y from the tip (0) toward the butt (-7), Z up;
the finisher in the pocket frame (origin at the pocket's mouth, Z up, the front toward -Y).

    bone          the body: a pale tip and a bronze ferrule, a polished bone shaft, four knobby
                  cartoon bones between the hands (wide double-lobed knuckles, a waist, bronze
                  rings between a few), the grip as two long smooth bones with a flush ring, a
                  bronze collar, and a big grinning cartoon skull on the butt (modelled here
                  from a distance function, see the skull section) whose eyes glow; it nods
    bone_pocket   the finisher: the same skull, 1.6 studs tall, popping up out of the pocket
                  in a ring of flame, its jaw chattering, its eyes blazing, with six real 3D
                  bones and two mini skulls whirling round it

The motif is bones, skulls, flame and sparks, never ghosts (the Phantom's; coordinator
2026-10-28 18:50). The flame's colour is one switch, PALETTE (coordinator 19:2x): 'green' (C7)
or 'red' (hellfire). It colours the eyes here and, through apply_palette, every flame, spark,
light, ring, trail and outline colour in skins/bone.json; the model is the same either way.

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_Bone.py -- bone bone_pocket
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

PALETTE = 'green'            # the flame colour, one switch: 'green' (C7) or 'red' (hellfire)
PALETTES = {
    'green': {
        'Eye': '#5CFF4A',                     # the look's Accent and the light
        'EyeNeon': '#30D82A',                 # the Neon eye orbs (Neon brightens: #5CFF4A drew white)
        'Outline': '#36C24A',
        'Flame': [[0, '#B6FF5A'], [0.35, '#2EE02A'], [1, '#0E6A22']],
        'Spark': [[0, '#FFFFFF'], [0.4, '#B8FF7A'], [1, '#3CD24A']],
        'Smoke': [[0, '#3CD24A'], [1, '#10301A']],
        'Rings': ['#10301A', '#5CFF4A', '#B8FF7A'],   # the finisher's dark ring, bright ring, pale ring
        'Trail': [[214, 255, 140], [40, 190, 60]],
        'TrailCore': [240, 255, 220],
        'Pocket': [[92, 255, 74], [200, 255, 140]],
        'Flash': [92, 255, 74],
    },
    'red': {                                  # hellfire (concept mocks/v3/R3.png, Inferno Bone: its swatches)
        'Eye': '#FF5A1E',
        'EyeNeon': '#E8300E',
        'Outline': '#E0221B',
        'Flame': [[0, '#FFD27A'], [0.3, '#FF8A1F'], [0.65, '#E0221B'], [1, '#7A1010']],
        'Spark': [[0, '#FFFFFF'], [0.4, '#FFC05A'], [1, '#E0221B']],
        'Smoke': [[0, '#7A1010'], [1, '#120808']],
        'Rings': ['#120808', '#E0221B', '#FF8A1F'],
        'Trail': [[255, 200, 110], [224, 34, 27]],
        'TrailCore': [255, 240, 210],
        'Pocket': [[255, 90, 30], [255, 170, 80]],
        'Flash': [255, 90, 30],
    },
}
BONE_IVORY = '#D9B57A'       # the little bones' solid colour (tan: the violet Night reads it as bone)
SEGMENTS = (2.2, 4.32, 4)    # the knobby bones between the hands: from, to, count
RING_JOINTS = (2,)           # the joints between them that wear a bronze ring (1 = after the first)
GRIP_JOINT = 5.55            # the grip's two long bones meet here (a flush bronze ring)
# bronze, studs from the tip: the ferrule, the stack's ends, its middle ring, the grip's flush
# ring, the band at the grip's end and the collar under the skull
RINGS = ((0.30, 0.36), (2.10, 2.20), (3.235, 3.285), (4.32, 4.40), (5.535, 5.565), (6.70, 6.78), (6.83, 6.90))
SKULL_SIZE = 1.0             # the skull across, studs (the butt is 0.36 across: C7's chunky cap)
# The face looks out of a back (+Z: away from the body, so the players behind see it, and up
# from the hands), turned toward the side the lobby stand shows (-X) and a little up the cue
# (+Y: a back's camera is above and behind, toward the tip). Measured in the lab 2026-10-28: on
# a back both -X and "past the butt" point at the floor, so a face tipped out past the butt
# (C7's pose) looked down and read as a blank ball. The crown sits on the cue, as in R3's
# front view: the cue enters the top of the head and the jaw hangs past the butt.
SKULL_FACE = (-0.6, 0.25, 0.76)
SKULL_SHIFT = 0.1            # the head sits this far toward its face off the axis (studs)


def _little_bone(bm, M, length):
    """A cartoon bone `length` studs long along X: a shaft and a pair of knobs at each end."""
    from mathutils import Matrix
    r = length * 0.1
    bmesh_ops = __import__('bmesh').ops
    bmesh_ops.create_cone(bm, cap_ends=True, segments=10, radius1=r, radius2=r, depth=length * 0.8,
                          matrix=M @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    for sx in (-1, 1):
        for sz in (-1, 1):
            bmesh_ops.create_uvsphere(bm, u_segments=10, v_segments=7, radius=r * 1.5,
                                      matrix=M @ Matrix.Translation((sx * length * 0.42, 0, sz * r * 1.1)))


def _body_rows():
    """The body's lathe profile: (d, r, lobe) rows from the tip to the closed end inside the
    skull, lobe the depth of the knuckles' two-lobed groove (0: round)."""
    R = envelope()
    rows = [(0.0, 0.0, 0), (0.012, 0.03, 0), (0.03, R(0.03), 0)]
    rows += [(d, r, 0) for d, r in _rows(0.03, 0.30, R, 0.09)[1:]]
    rows += [(0.30, R(0.30), 0), (0.305, R(0.30) + 0.012, 0), (0.355, R(0.355) + 0.012, 0), (0.36, R(0.36), 0)]
    rows += [(d, r, 0) for d, r in _rows(0.36, 2.10, R, 0.2)[1:]]
    rows += [(2.10, R(2.10), 0), (2.105, R(2.10) + 0.035, 0), (2.195, R(2.195) + 0.035, 0)]
    # the knobby bones: a knuckle at each end (two lobes across, +0.075 at most: the side rule's
    # +0.08), a waist between, a dip or a bronze ring where two meet
    lo, hi, n = SEGMENTS
    L = (hi - lo) / n
    prof = ((0.0, -0.012), (0.035, 0.035), (0.09, 0.075), (0.15, 0.06), (0.24, 0.02), (0.5, -0.004),
            (0.76, 0.02), (0.85, 0.06), (0.91, 0.075), (0.965, 0.035), (1.0, -0.012))
    for i in range(n):
        a = lo + i * L
        for t, extra in prof:
            if t == 0.0 and i > 0:
                continue
            ring_after = i + 1 in RING_JOINTS and t >= 0.965
            ring_before = i in RING_JOINTS and t <= 0.035
            if ring_after or ring_before:
                continue
            d = a + L * t
            rows.append((d, R(d) + extra, 0.16 * min(1.0, max(0.0, (extra - 0.03) / 0.045))))
        if i + 1 in RING_JOINTS:
            j = a + L
            rows += [(j - 0.028, R(j) + 0.045, 0), (j - 0.022, R(j) + 0.052, 0),
                     (j + 0.022, R(j) + 0.052, 0), (j + 0.028, R(j) + 0.045, 0)]
    rows += [(4.325, R(4.325) + 0.035, 0), (4.395, R(4.395) + 0.035, 0)]
    # the grip: two long smooth bones (the hand rule: the envelope +-0.02), a flush ring between
    for a, b in ((4.40, GRIP_JOINT - 0.015), (GRIP_JOINT + 0.015, 6.75)):
        for t, extra in ((0.0, 0.0), (0.04, 0.016), (0.12, 0.012), (0.5, -0.004), (0.88, 0.012), (0.96, 0.016), (1.0, 0.004)):
            d = a + (b - a) * t
            rows.append((d, R(d) + extra, 0))
        if a == 4.40:
            rows += [(GRIP_JOINT - 0.01, R(GRIP_JOINT) - 0.01, 0), (GRIP_JOINT + 0.01, R(GRIP_JOINT) - 0.01, 0)]
    # the collar under the skull (the butt zone from 6.8: the hand rule's last bin ends there),
    # closing inside the skull
    for d, extra in ((6.80, 0.03), (6.83, 0.075), (6.835, 0.085), (6.895, 0.085), (6.9, 0.075), (6.95, 0.06), (7.0, 0.04)):
        rows.append((d, R(min(d, 7.0)) + extra, 0))
    rows.append((7.04, 0.0, 0))
    return rows


def bone_map(w=512, h=1024):
    """vfx/bone/bone_512.png: the painted body. u runs round the cue (0 on top, +Z), v from the
    tip (0) to 7.3 studs (1); PNG row 0 is UV v = 1, so d = (1 - V) * 7.3. A pale chalky tip,
    bronze rings, warm ivory bone with long faint grain and pores, the lathe's own hollows
    shaded (painted occlusion: the dips between knuckles, the knuckles' lobe grooves, the waists)
    and a scatter of fine hairline cracks."""
    import numpy as np
    import cue_common as cc
    rel = 'vfx/bone/bone_512.png'
    path = os.path.join(os.path.dirname(PIECES_DIR), rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    rng = np.random.default_rng(11)
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, V = np.meshgrid(u, v)
    d = (1.0 - V) * 7.3
    noise = rng.random((h, w)).astype(np.float32)

    def lerp(a, b, t):
        return np.array(a, np.float32)[None, None, :] * (1 - t[..., None]) + np.array(b, np.float32)[None, None, :] * t[..., None]
    grain = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 5 + 0.2 * np.sin(2 * np.pi * V * 4)))
    img = lerp((242, 220, 172), (222, 194, 142), grain * 0.55)
    img = img * (0.97 + 0.03 * noise[..., None]) - ((noise > 0.965) * 12)[..., None]
    # painted occlusion from the lathe: how far a row sits below its neighbours' crest
    R = envelope()
    rows = _body_rows()
    dd = np.array([r[0] for r in rows])
    extra = np.array([r[1] - R(min(r[0], 7.0)) for r in rows])
    lobe = np.array([r[2] for r in rows])
    fine = np.linspace(0, 7.3, 2921)
    ex = np.interp(fine, dd, extra)
    win = 24                                              # +-0.06 studs
    pad = np.pad(ex, win, mode='edge')
    crest = np.max(np.stack([pad[i:i + len(fine)] for i in range(2 * win + 1)]), 0)
    occ = np.clip((crest - ex) / 0.06, 0, 1)
    occ_d = np.interp(d, fine, occ)
    lobe_d = np.interp(d, dd, lobe)
    groove = lobe_d / 0.16 * (0.5 + 0.5 * np.cos(4 * np.pi * U)) ** 2   # the lobes' grooves, top and bottom
    shade = 1 - 0.42 * np.clip(occ_d, 0, 1) - 0.22 * groove
    img = img * shade[..., None]
    # hairline cracks: short wandering dark lines on the bones (not the tip or the rings)
    crack = np.zeros((h, w), np.float32)
    for _ in range(34):
        d0 = rng.uniform(0.5, 6.7)
        u0 = rng.uniform(0, 1)
        n_steps = int(rng.integers(10, 24))
        heading = rng.uniform(-0.5, 0.5)
        for s in range(n_steps):
            heading += rng.normal(0, 0.35)
            d0 += 0.012 * math.cos(heading)
            u0 = (u0 + 0.006 * math.sin(heading)) % 1.0
            row = int((1 - d0 / 7.3) * h)
            col = int(u0 * w)
            if 0 <= row < h:
                for dc in (-1, 0, 1):
                    crack[row, (col + dc) % w] = max(crack[row, (col + dc) % w], 0.55 if dc else 0.8)
    img = img * (1 - 0.45 * crack[..., None]) + np.array((120, 84, 44), np.float32) * 0.45 * crack[..., None]
    # bronze
    sheen = 0.5 + 0.5 * np.cos(2 * np.pi * U)
    bronze = lerp((112, 74, 34), (200, 150, 80), sheen)
    for lo, hi in RINGS:
        band = (d >= lo) & (d < hi)
        rim = ((d - lo) < 0.01) | ((hi - d) < 0.01)
        img = np.where(band[..., None], np.where(rim[..., None], bronze * 0.62, bronze), img)
    # the tip: pale chalky white
    img = np.where((d < 0.30)[..., None], lerp((250, 250, 246), (232, 230, 224), noise * 0.5), img)
    cc.write_png(path, np.clip(img, 0, 255).astype(np.uint8))
    return rel


# --- the skull: a clean cartoon skull from a signed distance function --------------------------
# (coordinator 19:05: the generated skull read as a lumpy pale blob; C7's is a clean cartoon face,
# big round sockets, a small nose hole, a wide grin with chunky teeth, a smooth round cranium.)
# Its own frame: X across (1 unit = the skull's width), the face toward -Y, Z up. Meshed by
# OpenVDB (Blender's bundled openvdb), unwrapped, and painted by a bake: the zone colours (ivory,
# teeth, the dark sockets, nose and mouth) times baked ambient occlusion, into one colour map
# that the body's skull, the finisher's skull and its jaw, and the mini skulls all wear.

SKULL_MAPS = {'whole': 'vfx/bone/skull_512.png', 'split': 'vfx/bone/skull_jaw_512.png'}
SKULL_TRIS = 4000            # the meshed skull, reduced to this; each use reduces its own copy
SKULL_VOXEL = 0.009          # the meshing grid (skull widths): fine enough for the teeth's gaps
GRIN = 0.55                  # the mouth line's rise toward its corners: z + GRIN x^2
MOUTH_Z = -0.355             # the mouth's centre line (the finisher's jaw splits here)
SOCKETS = ((-0.2, -0.42, 0.03), (0.2, -0.42, 0.03))
SKULL_EYES = (((-0.2, -0.335, 0.03), 0.112), ((0.2, -0.335, 0.03), 0.112))   # the Neon orbs
ZONE_RGB = {'Ivory': (236, 212, 162), 'Teeth': (250, 238, 204), 'Dark': (54, 34, 22)}
_SKULL = {}


def _ell(P, c, r):
    """The (approximate) signed distance to an ellipsoid at c with radii r."""
    import numpy as np
    r = np.asarray(r, np.float32)
    q = (P - np.asarray(c, np.float32)) / r
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def _smin(a, b, k):
    import numpy as np
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def _smax(a, b, k):
    return -_smin(-a, -b, k)


def _head(P):
    """The uncarved head: a round cranium, the face, the brow, cheekbones, temples, the muzzle
    and the jaw, blended smoothly."""
    d = _smin(_ell(P, (0, 0.08, 0.1), (0.5, 0.47, 0.46)),            # the cranium
              _ell(P, (0, -0.12, -0.1), (0.42, 0.38, 0.3)), 0.14)  # the face
    d = _smin(d, _ell(P, (0, -0.33, 0.16), (0.4, 0.12, 0.08)), 0.06)   # the brow
    for sx in (-1, 1):
        d = _smin(d, _ell(P, (sx * 0.28, -0.28, -0.07), (0.16, 0.14, 0.11)), 0.07)   # cheekbones
        d = _smax(d, -_ell(P, (sx * 0.5, -0.14, -0.14), (0.13, 0.2, 0.16)), 0.08)    # temples
    d = _smin(d, _ell(P, (0, -0.3, -0.28), (0.29, 0.19, 0.11)), 0.06)    # the muzzle
    return _smin(d, _ell(P, (0, -0.22, -0.44), (0.28, 0.27, 0.12)), 0.07)   # the jaw


def _skull_fields(P):
    """The skull's distance fields at points P (... x 3): 'skull' (the final surface) and the
    zones' own fields ('socket', 'nose', 'mouth', 'teeth') that colour it."""
    import numpy as np
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    d = _head(P)
    socket = np.minimum(*(_ell(P, c, (0.155, 0.22, 0.17)) for c in SOCKETS))
    d = _smax(d, -socket, 0.03)
    nose = _smin(_smin(_ell(P, (-0.03, -0.46, -0.155), (0.038, 0.14, 0.05)),
                       _ell(P, (0.03, -0.46, -0.155), (0.038, 0.14, 0.05)), 0.02),
                 _ell(P, (0, -0.46, -0.195), (0.02, 0.14, 0.04)), 0.02)
    d = _smax(d, -nose, 0.012)
    Pw = np.stack([x, y, z - GRIN * x * x], -1)                  # the grin: the corners rise
    mouth = _ell(Pw, (0, -0.4, MOUTH_Z), (0.3, 0.26, 0.078))
    d = _smax(d, -mouth, 0.015)
    teeth = np.full(x.shape, 9.0, np.float32)
    for xs, dz, half in ((np.linspace(-0.25, 0.25, 7), 0.047, (0.035, 0.04, 0.043)),
                         (np.linspace(-0.21, 0.21, 6), -0.046, (0.033, 0.04, 0.039))):
        for tx in xs:
            tz = MOUTH_Z + dz + GRIN * tx * tx
            fy, nx, ny = _front(tx, tz)
            c = np.array((tx, fy + half[1] - 0.012, tz), np.float32)
            th = math.atan2(nx, -ny)
            Q = P - c
            qx = Q[..., 0] * math.cos(th) + Q[..., 1] * math.sin(th)
            qy = -Q[..., 0] * math.sin(th) + Q[..., 1] * math.cos(th)
            q = np.abs(np.stack([qx, qy, Q[..., 2]], -1)) - (np.array(half, np.float32) - 0.014)
            box = np.linalg.norm(np.maximum(q, 0), axis=-1) + np.minimum(q.max(-1), 0) - 0.014
            teeth = np.minimum(teeth, box)
    d = np.minimum(d, teeth)
    return {'skull': d, 'socket': socket, 'nose': nose, 'mouth': mouth, 'teeth': teeth}


_FRONT = {}


def _front(x, z):
    """Where the uncarved head's front surface is at (x, z): its y and outward normal (nx, ny)
    across the face (memoised: the teeth ask once per tooth)."""
    import numpy as np
    key = (round(float(x), 5), round(float(z), 5))
    if key not in _FRONT:
        ys = np.linspace(-0.8, 0.0, 1601, dtype=np.float32)

        def field(px, py):
            return _head(np.stack([np.full_like(py, px), py, np.full_like(py, z)], -1))
        d = field(x, ys)
        i = int(np.argmax(d < 0))
        fy = float(ys[i])
        e = 0.004
        gx = float(field(x + e, np.array([fy], np.float32))[0] - field(x - e, np.array([fy], np.float32))[0])
        gy = float(field(x, np.array([fy + e], np.float32))[0] - field(x, np.array([fy - e], np.float32))[0])
        n = math.hypot(gx, gy) or 1.0
        _FRONT[key] = (fy, gx / n, gy / n)
    return _FRONT[key]


def _mesh_field(bpy, name, field, lo, vs):
    """A closed mesh object of field < 0 (OpenVDB's mesher), its normals outward."""
    import numpy as np
    import bmesh
    import openvdb
    grid = openvdb.FloatGrid(1.0)
    grid.copyFromArray(np.ascontiguousarray(field, np.float32), ijk=tuple(int(round(v / vs)) for v in lo))
    grid.transform = openvdb.createLinearTransform(voxelSize=vs)
    pts, tris, quads = grid.convertToPolygons(0.0, 0.0)
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in pts.astype(float)]
    for f in list(tris) + list(quads):
        try:
            bm.faces.new([verts[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def _skull_geometry(bpy, kind):
    """The skull as numpy arrays (verts, tris, per-corner uvs) and its painted map: kind 'whole'
    (the body's: one closed head) or 'split' (the finisher's: 'upper', the head, and 'jaw',
    below the mouth line in front, sharing one unwrap and map). Meshed fine, reduced to
    SKULL_TRIS, unwrapped, and baked from the fine mesh: its zone colours (a colour attribute
    from the zone fields, so the sockets' edges are smooth) and ambient occlusion. Built once
    per kind per Blender run."""
    if kind in _SKULL:
        return _SKULL[kind]
    import numpy as np
    import bmesh
    import cue_common as cc
    from CuePieces import apply_modifier
    vs = SKULL_VOXEL
    lo = np.array((-0.62, -0.7, -0.66))
    hi = np.array((0.62, 0.66, 0.62))
    n = np.ceil((hi - lo) / vs).astype(int) + 1
    gx, gy, gz = (lo[i] + vs * np.arange(n[i], dtype=np.float32) for i in range(3))
    P = np.stack(np.meshgrid(gx, gy, gz, indexing='ij'), -1).astype(np.float32)
    d = _skull_fields(P)['skull']
    if kind == 'whole':
        fields = {'whole': d}
    else:
        # the jaw: below the mouth line and in front; the head is the rest
        jaw = np.maximum(P[..., 2] - GRIN * P[..., 0] ** 2 - MOUTH_Z, P[..., 1] - 0.02)
        fields = {'upper': np.maximum(d, -jaw), 'jaw': np.maximum(d, jaw)}
    del P
    fine, coarse = [], []
    for i, (name, field) in enumerate(fields.items()):
        f = _mesh_field(bpy, 'SkullFine_' + name, field, lo, vs)
        c = f.copy()
        c.data = f.data.copy()
        c.name = 'SkullCoarse_' + name
        bpy.context.scene.collection.objects.link(c)
        have = sum(len(p.vertices) - 2 for p in c.data.polygons)
        share = 1.0 if kind == 'whole' else (0.82 if name == 'upper' else 0.18)
        apply_modifier(bpy, c, 'DECIMATE', decimate_type='COLLAPSE', ratio=min(1.0, SKULL_TRIS * share / have),
                       use_collapse_triangulate=True)
        layer = c.data.attributes.new('part', 'INT', 'FACE')
        for j in range(len(c.data.polygons)):
            layer.data[j].value = i
        fine.append(f)
        coarse.append((name, c))
    # the fine meshes' zone colours: (ivory, teeth, dark) weights per vertex, smooth
    def ramp_(v, a, b):
        return np.clip((v - a) / (b - a), 0, 1)
    for f in fine:
        V = np.array([v.co[:] for v in f.data.vertices], np.float32)
        Z = _skull_fields(V)
        teeth = ramp_(Z['teeth'], 0.012, 0.0)
        dark = np.maximum.reduce([ramp_(Z['socket'], 0.028, 0.004), ramp_(Z['nose'], 0.02, 0.0),
                                  ramp_(Z['mouth'], 0.018, 0.0) * (1 - teeth)])
        if kind == 'split':
            dark = np.maximum(dark, ramp_(np.abs(V[:, 2] - GRIN * V[:, 0] ** 2 - MOUTH_Z), 0.014, 0.004) * (V[:, 1] < 0.03))
        ivory = np.clip(1 - teeth - dark, 0, 1)
        col = f.data.color_attributes.new('zone', 'FLOAT_COLOR', 'POINT')
        for j, rgb in enumerate(np.stack([ivory, teeth, dark], 1)):
            col.data[j].color = (float(rgb[0]), float(rgb[1]), float(rgb[2]), 1.0)
    zone_mat = bpy.data.materials.new('SkullZones')
    zone_mat.use_nodes = True
    bsdf = next(n_ for n_ in zone_mat.node_tree.nodes if n_.type == 'BSDF_PRINCIPLED')
    attr = zone_mat.node_tree.nodes.new('ShaderNodeAttribute')
    attr.attribute_name = 'zone'
    zone_mat.node_tree.links.new(attr.outputs['Color'], bsdf.inputs['Base Color'])
    for f in fine:
        f.data.materials.append(zone_mat)
    # one unwrap for the coarse meshes (joined; split again by the part attribute below)
    bpy.ops.object.select_all(action='DESELECT')
    for _, c in coarse:
        c.select_set(True)
    whole = coarse[0][1]
    bpy.context.view_layer.objects.active = whole
    if len(coarse) > 1:
        bpy.ops.object.join()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.012)
    bpy.ops.object.mode_set(mode='OBJECT')
    me = whole.data
    for p in me.polygons:
        p.use_smooth = True
    size = 512
    imgs = {k_: bpy.data.images.new('SkullBake_' + k_, size, size, float_buffer=True) for k_ in ('ID', 'AO')}
    for img in imgs.values():
        img.colorspace_settings.name = 'Non-Color'
    me.materials.clear()
    bake_mat = bpy.data.materials.new('SkullBake')
    bake_mat.use_nodes = True
    tex = bake_mat.node_tree.nodes.new('ShaderNodeTexImage')
    bake_mat.node_tree.nodes.active = tex
    me.materials.append(bake_mat)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 128
    if scene.world is None:
        scene.world = bpy.data.worlds.new('BakeWorld')
    scene.world.light_settings.distance = 0.22
    bpy.ops.object.select_all(action='DESELECT')
    for f in fine:
        f.select_set(True)
    whole.select_set(True)
    bpy.context.view_layer.objects.active = whole
    out = {}
    for key, kind_ in (('ID', 'DIFFUSE'), ('AO', 'AO')):
        tex.image = imgs[key]
        extra = {'pass_filter': {'COLOR'}} if kind_ == 'DIFFUSE' else {}
        bpy.ops.object.bake(type=kind_, margin=8, use_clear=True, use_selected_to_active=True,
                            cage_extrusion=0.02, max_ray_distance=0.06, **extra)
        out[key] = np.array(imgs[key].pixels[:], np.float32).reshape(size, size, 4)
    ids = np.clip(out['ID'][..., :3], 0, None)
    w = ids / np.maximum(ids.sum(-1, keepdims=True), 1e-6)
    base = sum(w[..., i:i + 1] * np.array(ZONE_RGB[k_], np.float32) for i, k_ in enumerate(('Ivory', 'Teeth', 'Dark')))
    ao = np.clip(out['AO'][..., :1], 0, 1)
    rgb = base * (0.42 + 0.58 * ao ** 0.9)
    rel = SKULL_MAPS[kind]
    path = os.path.join(os.path.dirname(PIECES_DIR), rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cc.write_png(path, np.clip(rgb[::-1], 0, 255).astype(np.uint8))   # Blender rows run bottom-up
    # back to arrays, split by part
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    uvl = bm.loops.layers.uv.active
    part = bm.faces.layers.int.get('part')
    bm.verts.ensure_lookup_table()
    geo = {'map': rel}
    for i, name in enumerate(fields):
        faces = [f for f in bm.faces if f[part] == i]
        used = sorted({v.index for f in faces for v in f.verts})
        remap = {j: k_ for k_, j in enumerate(used)}
        V = np.array([bm.verts[j].co[:] for j in used], np.float32)
        T = np.array([[remap[v.index] for v in f.verts] for f in faces], np.int64)
        UV = np.array([[lp[uvl].uv[:] for lp in f.loops] for f in faces], np.float32)
        geo[name] = (V, T, UV)
    bm.free()
    for img in imgs.values():
        bpy.data.images.remove(img)
    for ob in fine + [whole]:
        bpy.data.objects.remove(ob)
    scene.render.engine = 'BLENDER_EEVEE'
    print('CUE skull %s: %s, map %s' % (kind, ', '.join('%s %d tris' % (k_, len(geo[k_][1])) for k_ in fields), rel))
    _SKULL[kind] = geo
    return geo


def _skull_object(k, name, parts, M, mat, tris=None):
    """A copy of the skull's `parts` ('upper', 'jaw') as one object wearing kit material `mat`,
    placed by M (skull frame -> cue or pocket frame), reduced to `tris` if given (the collapse
    keeps the UVs, so the shared map still fits)."""
    import bmesh
    from CuePieces import apply_modifier
    geo = _skull_geometry(k.bpy, 'whole' if parts == ('whole',) else 'split')
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    for part in parts:
        V, T, UV = geo[part]
        verts = [bm.verts.new(M @ __import__('mathutils').Vector(v)) for v in V]
        for tri, uv in zip(T, UV):
            try:
                f = bm.faces.new([verts[i] for i in tri])
            except ValueError:
                continue
            for lp, t in zip(f.loops, uv):
                lp[uvl].uv = t
    _finish(bm)
    ob = k.mesh_object(name, bm, [mat])
    if tris:
        have = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        if have > tris:
            apply_modifier(k.bpy, ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=tris / have,
                           use_collapse_triangulate=True)
            for p in ob.data.polygons:
                p.use_smooth = True
    return ob


def _skull_frame(face, crown_toward):
    """The rotation taking the skull's frame (the face toward -Y, the crown +Z) so the face
    looks along `face` and the crown leans toward `crown_toward` (both cue-frame vectors)."""
    from mathutils import Matrix, Vector
    F = Vector(face).normalized()
    U = Vector(crown_toward)
    U = (U - U.dot(F) * F).normalized()
    X = (-F).cross(U)
    return Matrix((X, -F, U)).transposed().to_4x4()


@piece
def bone(k):
    """The Bone Cue's body (concept C7): see the module docstring."""
    import bmesh
    import numpy as np
    from mathutils import Matrix, Vector
    R = envelope()
    pal = PALETTES[PALETTE]
    # no reflectance: it mirrored the deep violet Night sky and turned the bone lavender (lab)
    k.material('Bone', 'SmoothPlastic', '#FFFFFF', Reflectance=0.0, SurfaceAppearance={'ColorMap': bone_map()})
    k.material('SkullBone', 'SmoothPlastic', '#FFFFFF', Reflectance=0.0,
               SurfaceAppearance={'ColorMap': SKULL_MAPS['whole']})
    k.material('Glow', 'Neon', pal['EyeNeon'])

    # --- the lathe: tip, ferrule, shaft, ring, the knobby bones, ring, the grip bones, collar ----
    k.joint('Body', pivot=(0, -3.5, 0))
    rows = _body_rows()
    lobes = {r[0]: r[2] for r in rows}
    bm = bmesh.new()
    _revolve(bm, [(d, r) for d, r, _ in rows], 20, rib=lambda d: (2, lobes.get(d, 0.0)),
             uv=lambda d, share: (share, d / 7.3))
    _finish(bm)
    k.add('Body', k.mesh_object('BoneBody', bm, ['Bone']))

    # --- the skull on the butt: past the butt, so it fades on the owner's screen while he aims ---
    rot = _skull_frame(SKULL_FACE, (0, 1, 0)) @ Matrix.Scale(SKULL_SIZE, 4)
    geo = _skull_geometry(k.bpy, 'whole')
    V = np.array([(rot @ Vector(p))[:] for p in geo['whole'][0]])
    side = Vector((SKULL_FACE[0], 0, SKULL_FACE[2])).normalized() * SKULL_SHIFT
    V += np.array(side[:])
    r = np.hypot(V[:, 0], V[:, 2])
    # slide it out along the axis until its part before the butt fits the butt rule (each
    # 0.1-stud bin within the envelope + 0.2 there; nothing before the hand zone's end)
    lim = lambda d: np.array([R(min(math.floor(x / 0.1) * 0.1 + 0.05, 7.0)) + 0.19 for x in d])  # noqa: E731
    at = 6.8
    while True:
        dv = at - V[:, 1]
        inside = dv < 7.0
        if dv.min() >= 6.8 and np.all(r[inside] <= lim(dv[inside])):
            break
        at += 0.005
    centre = Vector((side.x, -at, side.z))
    M = Matrix.Translation(centre) @ rot
    k.joint('Skull', pivot=tuple(centre), aim='fade', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': 3.4}])
    k.add('Skull', _skull_object(k, 'Skull', ('whole',), M, 'SkullBone'))
    print('CUE bone: skull centre at %.3f studs, reaches %.3f past the butt' % (at, float((at - V[:, 1]).max()) - 7.0))
    # the eyes: Neon orbs in the sockets, pulsing (they read in the bright lobby, a mask alone washes out)
    k.joint('Eyes', pivot=tuple(centre), parent='Skull', aim='fade',
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.3, 'Period': 1.8}])
    bm = bmesh.new()
    for c, rad in SKULL_EYES:
        bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=rad * SKULL_SIZE,
                                  matrix=Matrix.Translation(M @ Vector(c)))
    _finish(bm)
    k.add('Eyes', k.mesh_object('Eyes', bm, ['Glow']))
    check_body(k)


@piece
def bone_pocket(k):
    """The finisher: the body's skull 1.6 studs tall (the split skull: its jaw is its own part
    on a chattering hinge), its face to the camera, its eyes blazing, the head wobbling, six
    real 3D bones and two mini skulls whirling and tumbling round it (coordinator 19:08: the
    motifs are meshes, never flat cards). The ring of flame, the sparks and the dissolve are the
    skin's Pocket rows."""
    k.frame = 'pocket'
    k.upright = True
    import bmesh
    import numpy as np
    from mathutils import Matrix, Vector
    pal = PALETTES[PALETTE]
    k.material('PocketBone', 'SmoothPlastic', '#FFFFFF', Reflectance=0.0,
               SurfaceAppearance={'ColorMap': SKULL_MAPS['split']})
    k.material('PocketIvory', 'SmoothPlastic', BONE_IVORY, Reflectance=0.0)
    k.material('Glow', 'Neon', pal['EyeNeon'])
    geo = _skull_geometry(k.bpy, 'split')
    allv = np.concatenate([geo['upper'][0], geo['jaw'][0]])
    zlo, zhi = float(allv[:, 2].min()), float(allv[:, 2].max())
    s = 1.6 / (zhi - zlo)
    M = Matrix.Translation((0, 0, -zlo * s)) @ Matrix.Scale(s, 4)
    centre = M @ Vector((0, 0, 0))
    k.joint('Skull', pivot=tuple(centre), motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 5.0, 'Period': 1.4},
        {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 6.0, 'Period': 2.0, 'Phase': 40}])
    k.add('Skull', _skull_object(k, 'PocketSkull', ('upper',), M, 'PocketBone'))
    # the jaw hinges at the back of its cut, chattering
    k.joint('Jaw', pivot=tuple(M @ Vector((0, 0.02, MOUTH_Z))), parent='Skull', motion=[
        {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Base': 8.0, 'Amp': 8.0, 'Period': 0.32, 'Shape': 'snap'}])
    k.add('Jaw', _skull_object(k, 'PocketJaw', ('jaw',), M, 'PocketBone'))
    k.joint('Eyes', pivot=tuple(centre), parent='Skull', visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 0.8, 'Period': 0.6}])
    bm = bmesh.new()
    for c, rad in SKULL_EYES:
        bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=9, radius=rad * s, matrix=Matrix.Translation(M @ Vector(c)))
    _finish(bm)
    k.add('Eyes', k.mesh_object('PocketEyes', bm, ['Glow']))
    # the whirl: six 3D bones and two mini skulls, each tumbling (Lower effects keeps three bones)
    k.joint('Orbit', pivot=(0, 0, 0.9), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 150.0}])
    for i in range(6):
        a = 2 * math.pi * i / 6
        c = Vector((1.05 * math.cos(a), 1.05 * math.sin(a), 0.55 + 0.75 * ((i * 0.37) % 1.0)))
        axis = Vector((math.sin(a * 1.7), math.cos(a * 2.3), 0.6)).normalized()
        name = 'Bone%d' % (i + 1)
        k.joint(name, pivot=tuple(c), parent='Orbit', low='hide' if i % 2 else None,
                motion=[{'Kind': 'Spin', 'Axis': tuple(axis), 'Rate': 300.0 + 60.0 * i}])
        bm = bmesh.new()
        _little_bone(bm, Matrix.Translation(c) @ Matrix.Rotation(a + 0.6 * i, 4, 'Z') @ Matrix.Rotation(0.5 * i, 4, 'Y'), 0.5)
        _finish(bm)
        k.add(name, k.mesh_object(name, bm, ['PocketIvory']))
    for i, a in enumerate((math.radians(90), math.radians(270))):
        c = Vector((1.25 * math.cos(a), 1.25 * math.sin(a), 1.25 - 0.3 * i))
        name = 'Mini%d' % (i + 1)
        k.joint(name, pivot=tuple(c), parent='Orbit', low='hide',
                motion=[{'Kind': 'Spin', 'Axis': (0.3, 0.2, 1.0), 'Rate': 220.0 + 80 * i}])
        Mm = Matrix.Translation(c) @ Matrix.Rotation(a + math.pi / 2, 4, 'Z') @ Matrix.Scale(0.4 / (zhi - zlo), 4)
        k.add(name, _skull_object(k, 'MiniSkull%d' % (i + 1), ('upper', 'jaw'), Mm, 'PocketBone', tris=700))
        bm = bmesh.new()
        for e, rad in SKULL_EYES:
            bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=rad * 0.4 / (zhi - zlo),
                                      matrix=Matrix.Translation(Mm @ Vector(e)))
        _finish(bm)
        k.add(name, k.mesh_object('MiniEyes%d' % (i + 1), bm, ['Glow']))


# Part keys patched into piece.json after the export: `Outline = false` keeps a part outside the
# body's ink outline (CuePiece: a skull's folds, the teeth and sockets, ink as speckles at a
# cue's size, lab 2026-10-28) and `Smooth = true` has tools/cue_pieces_glb.py share its vertex
# normals (the packer writes flat faces otherwise: the skull read faceted, lab 2026-10-28).
PART_KEYS = {
    'bone': {'Skull_SkullBone': {'Outline': False, 'Smooth': True}, 'Eyes_Glow': {'Outline': False, 'Smooth': True},
             'Body_Bone': {'Smooth': True}},
    'bone_pocket': {name: {'Smooth': True} for name in (
        'Skull_PocketBone', 'Jaw_PocketBone', 'Eyes_Glow', 'Mini1_PocketBone', 'Mini2_PocketBone', 'Mini1_Glow',
        'Mini2_Glow', 'Bone1_PocketIvory', 'Bone2_PocketIvory', 'Bone3_PocketIvory', 'Bone4_PocketIvory',
        'Bone5_PocketIvory', 'Bone6_PocketIvory')},
}


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


# skins/bone.json's colour slots by emitter name (apply_palette writes them)
_FLAME_EMITTERS = ('BoneFlames', 'SkullFlames', 'FlamePuffs', 'FlameRing', 'FlameWrap')
_SPARK_EMITTERS = ('BoneSparks', 'Sparks')


def apply_palette(name=None):
    """Write palette `name` (default PALETTE) into skins/bone.json: every flame, spark and smoke
    colour sequence, the light, the outline, the look's Accent, the trail, the finisher's flash,
    rings and colours. The model is untouched; run cue_skins_data.py after."""
    pal = PALETTES[name or PALETTE]
    path = os.path.join(HERE, 'skins', 'bone.json')
    spec = json.load(open(path))
    vfx = spec['vfx']
    spec['look']['Accent'] = pal['Eye']
    vfx['Aura']['Outline'] = pal['Outline']
    for light in vfx['Aura']['Lights']:
        light['Color'] = pal['Eye']
    emitters = vfx['Aura']['Emitters'] + vfx['Trail']['Emitters'] + vfx['Pocket']['Layers']
    for e in emitters:
        if e['Name'] in _FLAME_EMITTERS:
            e['Color'] = [list(c) for c in pal['Flame']]
        elif e['Name'] in _SPARK_EMITTERS:
            e['Color'] = [list(c) for c in pal['Spark']]
        elif e['Name'] == 'Dissolve':
            e['Color'] = [list(c) for c in pal['Smoke']]
        else:
            raise AssertionError('apply_palette: no colour slot for emitter %s' % e['Name'])
    trail = vfx['Style']['Trail']
    trail['Colors'] = [list(c) for c in pal['Trail']]
    trail['Core']['Color'] = list(pal['TrailCore'])
    vfx['Style']['Pocket']['Colors'] = [list(c) for c in pal['Pocket']]
    vfx['Pocket']['Flash']['Color'] = list(pal['Flash'])
    for ring, colour in zip(vfx['Pocket']['Rings'], pal['Rings']):
        ring['Color'] = colour
    with open(path, 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    print('CUE bone palette %s written to skins/bone.json' % (name or PALETTE))


def _cli():
    """Blender ... --python assets/cue/CuePiecesHalloween_Bone.py -- bone [bone_pocket]: build
    each piece (no preview tiles), patch its part keys and write the palette into the skin."""
    from CuePieces import build
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    for pid in (a for a in argv if not a.startswith('--')):
        build(pid, render_preview=False)
        _patch_parts(pid)
    apply_palette()


if __name__ == '__main__':
    _cli()
