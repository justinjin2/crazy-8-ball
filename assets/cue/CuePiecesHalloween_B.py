"""The Halloween 2026 event cues of lane Cues B (docs/prompts/HW_CUES_B_PROMPT.md, PLAN §3):
the Witch's Broom (Secret), the Black Cat Cue (Mythic) and the Spider Cue (Mythic). Bodies,
aura pieces, pocket pieces and silhouette rigs, modelled with the CuePieces kit in the cue's
Blender frame: X the side, Y from 0 at the tip to -7 at the butt, Z up (up in the hands, away
from the body on a back); pocket pieces in the pocket frame (origin at the mouth, Z up).

A **body** replaces the hidden shared cue mesh (Cues A's path: the skin's `body` names it),
so it must fit the CueShape envelope where the hands, the rails and the balls meet it. The
rules of brief 2.2 are enforced here by `check_envelope` (the Blender run fails naming the
part and the distance) and the budgets by `check_budget`.

Always build through this file, never through the plain CuePieces.py entry point: only this
one writes the `Aim` joint keys (brief 2.3) into piece.json after the export:

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_B.py -- witch_broom
    $B -b --factory-startup --python-exit-code 1 --python assets/cue/CuePiecesHalloween_B.py -- --silhouette cat_run
    python3 assets/cue/CuePiecesHalloween_B.py --sheet witch_broom        # join the preview tiles

This module is also imported by CuePieces.py (Cues A's guarded import), so it registers its
builders on import and does nothing else: the Aim keys live in the static AIM table below.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from CuePieces import piece, apply_modifier, sweep, ramp  # noqa: E402
import CuePieces  # noqa: E402

PIECES_DIR = os.path.join(HERE, 'pieces')

# The joints that may reach past the butt: on the stick owner's own screen they ease to clear
# while the stick is drawn for a shot (`"Aim": "fade"`, Cues A's drop 3), so a long overhang
# never blocks the aim. Static, never recorded at build time (the file is loaded twice).
AIM = {
    'witch_broom': ['Bristles'],
    'black_cat': ['Tail'],
    'spider': ['Crown'],
}

# Which rules a piece follows: a body fits the envelope, an aura piece only keeps off the tip
# and inside the overhang cap, a pocket piece is free (its own frame).
KIND = {
    'witch_broom': 'body', 'witch_broom_aura': 'aura', 'witch_broom_pocket': 'pocket',
    'black_cat': 'body', 'black_cat_aura': 'aura', 'black_cat_pocket': 'pocket',
    'spider': 'body', 'spider_aura': 'aura', 'spider_pocket': 'pocket',
}

# Hard budgets (brief 2.2; Cues A's data tool stops over them too): parts, triangles.
BUDGET = {'body': (8, 10000), 'aura': (None, 10000), 'pocket': (None, 20000)}

# The body rules (brief 2.2), studs. d is the distance from the tip (= -Y in the Blender frame).
RULES = {
    'TipSlack': 0.01,          # nothing at Y > this (Config.CueSkins.Bodies.TipSlackStuds)
    'TipAcross': 0.12,         # the first 0.3 studs stay inside this width (the ball is 0.36 across)
    'TipLength': 0.3,
    'Bridge': (0.3, 2.1),      # the bridge hand zone
    'Grip': (4.4, 6.75),       # the grip hand zone (rest 5.95, a wind-up slides 1.5 back)
    'HandAxis': 0.02,          # centreline within this of the axis in a hand zone
    'HandRadius': 0.02,        # radius within this of the envelope in a hand zone
    'SideDown': 0.08,          # envelope + this sideways and downward up to 6.75
    'UpMid': 0.25,             # +Z between 2.1 and 4.4 (twig stubs, rings, the claw)
    'UpMidZone': (2.1, 4.4),
    'ButtZone': (6.75, 7.0),   # binding, collar, cap: envelope + this all round
    'ButtExtra': 0.2,
    'Length': 7.0,
    'PastButt': 0.3,           # a part that does not fade in the aim view (Bodies.PastButtStuds)
    'PastButtRadius': 0.45,    # ... and how far off the axis it may sit there (own number: the Broom's hat charm brim)
    'AimPastButt': 1.5,        # an Aim joint's cap (Bodies.MaxOverhangStuds)
    'AimRadius': 1.0,          # ... and its radial room (the Cat's long tail curls 0.9 up; own number)
}


def _radius():
    """The cue's radius at distance d from the tip (Shape.json's envelope)."""
    import cue_common as cc
    return cc.Envelope(cc.load_shape()[0])


# =============================================================================================
# Mesh helpers (the Unique builder's lathe family, local so this file imports with no side
# effects beyond registering its own builders)
# =============================================================================================

def _ring_verts(bm, d, r, segs, twist=0.0, centre=(0.0, 0.0)):
    from mathutils import Vector
    cx, cz = centre
    out = []
    for k in range(segs):
        a = 2 * math.pi * k / segs + twist
        out.append(bm.verts.new(Vector((cx + r * math.sin(a), -d, cz - r * math.cos(a)))))
    return out


def _lathe(bm, ds, rs, segs, twist_per_ring=0.0, close=False, centres=None, shape=None):
    """A tube of rings along the cue (d from the tip, positive). centres: an (x, z) offset per
    ring (a crooked handle); shape(angle, i) -> radius scale (facets, bark lumps)."""
    from mathutils import Vector
    rings = []
    for i, (d, r) in enumerate(zip(ds, rs)):
        c = centres[i] if centres else (0.0, 0.0)
        if shape is None:
            rings.append(_ring_verts(bm, d, r, segs, twist_per_ring * i, c))
        else:
            ring = []
            for k in range(segs):
                a = 2 * math.pi * k / segs + twist_per_ring * i
                rr = r * shape(a, i)
                ring.append(bm.verts.new(Vector((c[0] + rr * math.sin(a), -d, c[1] - rr * math.cos(a)))))
            rings.append(ring)
    for a, b in zip(rings[:-1], rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    if close:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            c = sum((v.co for v in ring), Vector()) / len(ring)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[(k + 1) % segs], cv)
                bm.faces.new(q[::-1] if rev else q)
    return rings


def _torus(bm, centre, axis, R, r, segs=32, minor=10):
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
            ring.append(bm.verts.new(Vector(centre) + radial * (R + r * math.cos(b)) + axis * (r * math.sin(b))))
        grid.append(ring)
    for i in range(segs):
        a, b = grid[i], grid[(i + 1) % segs]
        for j in range(minor):
            bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor]))


def _box(bm, centre, size, basis=None):
    from mathutils import Vector
    cx, cy, cz = size[0] / 2, size[1] / 2, size[2] / 2
    bx, by, bz = basis or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    c = Vector(centre)
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corners.append(bm.verts.new(c + bx * (sx * cx) + by * (sy * cy) + bz * (sz * cz)))

    def V(sx, sy, sz):
        return corners[(sx * 4) + (sy * 2) + sz]
    faces = [((0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)), ((1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0)),
             ((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)), ((0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)),
             ((0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)), ((0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1))]
    for f in faces:
        bm.faces.new(tuple(V(*q) for q in f))


# =============================================================================================
# The atlas: one 512 px colour (+alpha), normal and emissive-mask set per body, painted by
# region with numpy inside the Blender run (its Python has no PIL; cue_common.write_png)
# =============================================================================================

# Which overhang variant a body is built with (brief 2.2: compact ≤0.3 past the butt until the
# Aim fade is seen working in the aim camera at P18, then the long one).
LONG = {'witch_broom': False, 'black_cat': False, 'spider': False}


class Atlas:
    """A square atlas painted by named regions (u0, v0, u1, v1 in 0..1, v up). `paint` takes
    region-local (U, V) grids (0..1) and returns the colour / alpha / height / emissive layers
    to fill; the normal map comes from the height. Saved as pieces/<pid>/<stem>_{color,normal,
    emissive}.png (row 0 at the top, so the arrays are flipped on the way out)."""

    def __init__(self, pid, stem='atlas', size=512):
        import numpy as np
        self.pid, self.stem, self.size = pid, stem, size
        self.col = np.zeros((size, size, 3), np.float32)
        self.alpha = np.ones((size, size), np.float32)
        self.height = np.zeros((size, size), np.float32)
        self.bump = np.ones((size, size), np.float32)    # normal strength per pixel
        self.emi = np.zeros((size, size), np.float32)
        self.regions = {}

    def region(self, name, u0, v0, u1, v1):
        self.regions[name] = (u0, v0, u1, v1)
        return name

    def uv(self, name, u, v):
        """Region-local (u, v) in 0..1 -> atlas (u, v)."""
        u0, v0, u1, v1 = self.regions[name]
        return (u0 + (u1 - u0) * u, v0 + (v1 - v0) * v)

    def rect(self, name):
        u0, v0, u1, v1 = self.regions[name]
        s = self.size
        return (int(round(u0 * s)), int(round(v0 * s)), int(round(u1 * s)), int(round(v1 * s)))

    def grid(self, name):
        import numpy as np
        x0, y0, x1, y1 = self.rect(name)
        V, U = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        return (U - x0 + 0.5) / (x1 - x0), (V - y0 + 0.5) / (y1 - y0)

    def paint(self, name, col, alpha=None, height=None, emissive=None, bump=1.0):
        import numpy as np
        x0, y0, x1, y1 = self.rect(name)
        sl = (slice(y0, y1), slice(x0, x1))
        self.col[sl] = np.clip(col, 0, 1)
        if alpha is not None:
            self.alpha[sl] = np.clip(alpha, 0, 1)
        if height is not None:
            self.height[sl] = height
        if emissive is not None:
            self.emi[sl] = np.clip(emissive, 0, 1)
        self.bump[sl] = bump

    def save(self):
        import numpy as np
        import cue_common as cc
        out = os.path.join(PIECES_DIR, self.pid)
        os.makedirs(out, exist_ok=True)
        rgba = np.concatenate([self.col, self.alpha[..., None]], -1)
        # normal (OpenGL: +Y up in the map = +v) from the height field, strength per pixel
        h = self.height
        dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * self.bump
        dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * self.bump
        n = np.stack([-dx, -dy, np.ones_like(h)], -1)
        n = n / np.linalg.norm(n, axis=-1, keepdims=True)
        nrm = n * 0.5 + 0.5
        emi = np.repeat(self.emi[..., None], 3, -1)
        paths = {}
        for key, arr in (('color', rgba), ('normal', nrm), ('emissive', emi)):
            rel = 'pieces/%s/%s_%s.png' % (self.pid, self.stem, key)
            cc.write_png(os.path.join(HERE, rel), np.flipud(arr) * 255.0)
            paths[key] = rel
        return paths

    def materials(self, kit, opaque='Atlas', alpha=None, emissive_tint='#FFFFFF', emissive_strength=1.5,
                  Material='SmoothPlastic', Reflectance=0.0):
        """Register the atlas on the kit: `opaque` (AlphaMode Overlay) and, given a name, an
        `alpha` twin (AlphaMode Transparency) for the parts that need the alpha channel."""
        paths = self.save()
        sa = {'ColorMap': paths['color'], 'NormalMap': paths['normal'], 'EmissiveMask': paths['emissive'],
              'EmissiveTint': emissive_tint, 'EmissiveStrength': emissive_strength}
        kit.material(opaque, Material, '#FFFFFF', Reflectance=Reflectance, SurfaceAppearance=dict(sa))
        if alpha:
            sa2 = dict(sa)
            sa2['AlphaMode'] = 'Transparency'
            kit.material(alpha, Material, '#FFFFFF', Reflectance=Reflectance, SurfaceAppearance=sa2)
        return paths


def _fbm(u, v, scale, octaves=4, seed=0):
    import cue_common as cc
    import numpy as np
    return cc.fbm(u * scale, v * scale, np.zeros_like(u), octaves=octaves, seed=seed)


def _rgb(h):
    import numpy as np
    return np.array(CuePieces.hexrgb(h), np.float32)


def _lerp(a, b, t):
    import numpy as np
    t = np.asarray(t, np.float32)[..., None]
    return a * (1 - t) + b * t


# ---- UV-aware mesh helpers ----------------------------------------------------------------------

def _lathe_uv(bm, uvl, ds, rs, segs, uv_fn, centres=None, shape=None, close=False, cap_uv=None):
    """A tube of rings along the cue (d from the tip) with a real seam (segs + 1 vertices a ring,
    the first and last at the same place, at the bottom, -Z), so its UVs never wrap: loop UV =
    uv_fn(u across 0..1, v along 0..1). centres: (x, z) per ring; shape(angle, i) scales the
    radius. close: caps at both ends, their loops at cap_uv or the ring's own UVs."""
    from mathutils import Vector
    rings = []
    n = len(ds)
    for i, (d, r) in enumerate(zip(ds, rs)):
        cx, cz = centres[i] if centres else (0.0, 0.0)
        ring = []
        for k in range(segs + 1):
            a = 2 * math.pi * k / segs
            rr = r * (shape(a, i) if shape else 1.0)
            ring.append(bm.verts.new(Vector((cx + rr * math.sin(a), -d, cz - rr * math.cos(a)))))
        rings.append(ring)
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        va, vb = i / (n - 1), (i + 1) / (n - 1)
        for k in range(segs):
            f = bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
            for lp, (u, v) in zip(f.loops, ((k / segs, va), ((k + 1) / segs, va), ((k + 1) / segs, vb), (k / segs, vb))):
                lp[uvl].uv = uv_fn(u, v)
    if close:
        for ring, rev, v in ((rings[0], True, 0.0), (rings[-1], False, 1.0)):
            c = sum((x.co for x in ring[:-1]), Vector()) / (len(ring) - 1)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[k + 1], cv)
                f = bm.faces.new(q[::-1] if rev else q)
                for lp in f.loops:
                    lp[uvl].uv = cap_uv or uv_fn(0.5, v)
    return rings


def _transform(bm, verts, M):
    import bmesh
    bmesh.ops.transform(bm, matrix=M, verts=verts)


def _basis(origin, axis_dir, up_hint=(0, 0, 1)):
    """A 4x4 taking the lathe's local frame (built along -Y from the origin) to `axis_dir`."""
    from mathutils import Vector, Matrix
    t = Vector(axis_dir).normalized()
    u = Vector(up_hint)
    if abs(t.dot(u)) > 0.95:
        u = Vector((1, 0, 0))
    n = (u - t * t.dot(u)).normalized()
    b = t.cross(n)
    # local -Y -> t, local Z -> n, local X -> b
    M = Matrix(((b.x, -t.x, n.x, origin[0]), (b.y, -t.y, n.y, origin[1]), (b.z, -t.z, n.z, origin[2]), (0, 0, 0, 1)))
    return M


def _strip_uv(bm, uvl, pts_left, pts_right, uv_fn, flip=False):
    """A quad strip between two polylines (the card's two edges), UV u 0 (left) .. 1 (right),
    v 0 (first point) .. 1 (last). flip turns the faces over."""
    L = [bm.verts.new(p) for p in pts_left]
    R = [bm.verts.new(p) for p in pts_right]
    n = len(L)
    faces = []
    for i in range(n - 1):
        q = (L[i], R[i], R[i + 1], L[i + 1])
        f = bm.faces.new(q[::-1] if flip else q)
        uvs = ((0, i / (n - 1)), (1, i / (n - 1)), (1, (i + 1) / (n - 1)), (0, (i + 1) / (n - 1)))
        if flip:
            uvs = uvs[::-1]
        for lp, (u, v) in zip(f.loops, uvs):
            lp[uvl].uv = uv_fn(u, v)
        faces.append(f)
    return faces


def _box_uv(bm, uvl, centre, size, basis, uv_faces):
    """A box with UVs: uv_faces(axis, sign) -> uv_fn(u, v) for each of the six faces
    (axis 0..2 of the basis, sign ±1)."""
    from mathutils import Vector
    bx, by, bz = basis
    cx, cy, cz = size[0] / 2, size[1] / 2, size[2] / 2
    c = Vector(centre)
    corner = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                corner[(sx, sy, sz)] = bm.verts.new(c + bx * (sx * cx) + by * (sy * cy) + bz * (sz * cz))
    # each face: (axis, sign, the four corners in order, their (u, v))
    faces = [
        (0, 1, ((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1))), (0, -1, ((-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1))),
        (1, 1, ((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1))), (1, -1, ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1))),
        (2, 1, ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))), (2, -1, ((-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1))),
    ]
    for axis, sign, quad in faces:
        f = bm.faces.new(tuple(corner[q] for q in quad))
        fn = uv_faces(axis, sign)
        for lp, (u, v) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[uvl].uv = fn(u, v)


def _const_uv(bm, uvl, faces, uv):
    for f in faces:
        for lp in f.loops:
            lp[uvl].uv = uv


def _torus_uv(bm, uvl, centre, axis, R, r, uv, segs=16, minor=8):
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
            ring.append(bm.verts.new(Vector(centre) + radial * (R + r * math.cos(b)) + axis * (r * math.sin(b))))
        grid.append(ring)
    faces = []
    for i in range(segs):
        a, b = grid[i], grid[(i + 1) % segs]
        for j in range(minor):
            faces.append(bm.faces.new((a[j], b[j], b[(j + 1) % minor], a[(j + 1) % minor])))
    _const_uv(bm, uvl, faces, uv)
    return faces


def _smooth(t, a, b):
    """0 at a, 1 at b (either way), smoothstep."""
    import numpy as np
    t = np.clip((np.asarray(t, np.float32) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# =============================================================================================
# Witch's Broom (Secret): the body
# =============================================================================================

BROOM = {
    'bark': '#6B4A2E', 'bark_dark': '#3A2414', 'bark_light': '#9C7146', 'moss': '#5E8A3A',
    'silver': '#C9CED8', 'silver_dark': '#7C8390', 'gold': '#FFD36A', 'purple': '#5B2A86',
    'purple_dark': '#3A1757', 'hat': '#4B2270', 'hat_dark': '#2E1245', 'straw': '#D9A441',
    'straw_dark': '#A8742A', 'straw_light': '#F0C76A',
    'crystal': '#A86BFF', 'core': '#D9B8FF',
}

HANDLE = (0.3, 6.75)      # the bark handle's run (d from the tip)
BINDING = (6.75, 7.0)     # the purple wraps
KNOT_D, KNOT_ANGLE = 2.6, math.pi * 0.86  # the knot hole: 0.86π from the bottom = up, a little to +X
TWIGS = ((2.35, 0.14, 0.55), (3.25, 0.22, -0.35), (4.05, 0.17, 0.2))   # (d, length, lean (rad, +X))


def _broom_atlas(k):
    """Paint and register the Broom's atlas: BARK (the handle's circumference across, its
    length along, with the silver spiral bands at the tip end and the knot hole), BIND (the
    purple wraps), STRAW (strands with alpha for the cards), ROOT (dense straw, opaque), SILVER,
    GOLD, HAT (purple with a gold band) and BUCKLE (silver with the gold crescent, emissive)."""
    import numpy as np
    A = Atlas('witch_broom')
    A.region('BARK', 0.0, 0.0, 0.5, 1.0)
    A.region('STRAW', 0.5, 0.0, 1.0, 0.5)
    A.region('ROOT', 0.75, 0.5, 0.875, 0.75)
    A.region('BIND', 0.5, 0.5, 0.75, 0.75)
    A.region('SILVER', 0.5, 0.75, 0.625, 0.875)
    A.region('GOLD', 0.625, 0.75, 0.75, 0.875)
    A.region('BUCKLE', 0.5, 0.875, 0.625, 1.0)
    A.region('HAT', 0.625, 0.875, 1.0, 1.0)
    A.region('CHAIN', 0.75, 0.75, 1.0, 0.875)
    A.region('ENDS', 0.875, 0.5, 1.0, 0.625)
    bark, dark, light, moss = (_rgb(BROOM[x]) for x in ('bark', 'bark_dark', 'bark_light', 'moss'))

    # --- BARK: ridges along the length (v), broken by noise; cracks; moss flecks ---------------
    U, V = A.grid('BARK')
    warp = _fbm(U * 2, V * 1.0, 6.0, octaves=3, seed=3)
    ridge = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 11 + 0.35 * warp + 0.08 * np.sin(2 * np.pi * V * 9)))
    grain = _fbm(U, V, 40.0, octaves=4, seed=5)
    crack = _smooth(_fbm(U * 1.5, V, 18.0, octaves=3, seed=9), 0.62, 0.7)
    h = 0.55 * ridge + 0.3 * grain - 0.45 * crack
    tone = np.clip(0.25 + 0.6 * ridge + 0.3 * (grain - 0.5), 0, 1)
    col = _lerp(dark, bark, tone)
    col = _lerp(col, light, np.clip(0.25 * ridge * grain * 2, 0, 1) * 0.6)
    col = _lerp(col, dark, crack * 0.8)
    mossy = _smooth(_fbm(U * 3, V, 16.0, octaves=3, seed=21), 0.66, 0.76) * (1 - crack) * (1 - ridge)
    col = _lerp(col, moss, mossy * 0.35)
    # the knot hole at KNOT_D: dark concentric rings sinking into a hole, a raised rim
    ku = (KNOT_ANGLE / (2 * math.pi))
    kv = (KNOT_D - HANDLE[0]) / (HANDLE[1] - HANDLE[0])
    du = (U - ku) * 2.4            # the circumference is ~0.7 studs here, the length 6.45: squash u
    dv = (V - kv) * 14.0
    rr = np.sqrt(du * du + dv * dv)
    rim = _smooth(rr, 0.42, 0.3) * (1 - _smooth(rr, 0.2, 0.08))
    hole = _smooth(rr, 0.2, 0.06)
    rings = 0.5 + 0.5 * np.sin(rr * 28 + 2 * grain)
    knot_col = _lerp(_lerp(bark, dark, 0.3 + 0.5 * rings), _rgb('#1A0E08'), hole)
    inknot = _smooth(rr, 0.5, 0.3)
    col = _lerp(col, knot_col, inknot)
    h = h * (1 - inknot) + inknot * (0.5 * rings * (1 - hole) + 0.8 * rim - 1.2 * hole)
    # the silver spiral bands: two stripes winding round the first 0.3 studs (v 0..0.0465)
    band_v = (0.6 - HANDLE[0]) / (HANDLE[1] - HANDLE[0])
    inband = (V < band_v).astype(np.float32)
    spiral = ((U * 1.0 + V / band_v * 1.5) % 1.0)
    stripes = (_smooth(spiral, 0.0, 0.05) * _smooth(spiral, 0.32, 0.27) + _smooth(spiral, 0.5, 0.55) * _smooth(spiral, 0.82, 0.77))
    silver, silver_dark = _rgb(BROOM['silver']), _rgb(BROOM['silver_dark'])
    sheen = _lerp(silver_dark, silver, 0.4 + 0.6 * ridge)
    col = _lerp(col, sheen, inband * stripes)
    h = h + inband * stripes * 0.9
    A.paint('BARK', col, height=h, bump=2.2)

    # --- STRAW: strands with alpha, dense at the root (v 0), frayed at the tip (v 1) ---------
    U, V = A.grid('STRAW')
    straw, straw_dark, straw_light = (_rgb(BROOM[x]) for x in ('straw', 'straw_dark', 'straw_light'))
    strand = np.zeros_like(U)
    tint = np.zeros_like(U)
    hgt = np.zeros_like(U)
    rng = [(_hash(i, 1), _hash(i, 2), _hash(i, 3), _hash(i, 4)) for i in range(70)]
    for i, (x0, drift, w, tone_) in enumerate(rng):
        x = x0 + (drift - 0.5) * 0.22 * V * V + 0.012 * np.sin(V * 14 + i)
        end = 0.55 + 0.45 * _hash(i, 5)            # where this strand ends (frayed tips)
        width = 0.006 + 0.008 * w
        m = (np.abs(U - x) < width) & (V < end)
        core = np.clip(1 - np.abs(U - x) / width, 0, 1)
        strand = np.maximum(strand, m * core)
        tint = np.where(m & (core > tint), tone_, tint)
        hgt = np.maximum(hgt, m * core)
    alpha = np.clip(strand * 1.6, 0, 1)
    alpha = np.maximum(alpha, _smooth(V, 0.08, 0.0))                       # solid at the root
    scol = _lerp(_lerp(straw_dark, straw, tint), straw_light, _smooth(hgt, 0.6, 1.0) * 0.5)
    scol = _lerp(scol, straw_dark, _smooth(V, 0.0, 0.12) * 0.5)
    A.paint('STRAW', scol, alpha=alpha, height=hgt * 0.6, bump=1.2)

    # --- ROOT: dense straw, opaque, strands along v ---------------------------------------------
    U, V = A.grid('ROOT')
    g = _fbm(U * 6, V * 0.5, 9.0, octaves=3, seed=31)
    lines = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 26 + 0.3 * g))
    A.paint('ROOT', _lerp(_lerp(straw_dark, straw, lines), straw_light, (lines * g) * 0.5), height=lines * 0.5, bump=1.0)
    # ENDS: the cut ends of the straw bundle: pale dots on a dark ground
    U, V = A.grid('ENDS')
    cell = 9.0
    fx, fy = (U * cell) % 1.0 - 0.5, (V * cell) % 1.0 - 0.5
    jitter = _fbm(U, V, 30.0, octaves=2, seed=52) - 0.5
    dot = _smooth(np.sqrt(fx * fx + fy * fy) + 0.1 * jitter, 0.34, 0.24)
    A.paint('ENDS', _lerp(_rgb('#5A3A14'), _lerp(straw, straw_light, 0.3), dot), height=dot * 0.8, bump=1.5)

    # --- BIND: purple fabric wraps with ridges across (v), a weave ------------------------------
    U, V = A.grid('BIND')
    purple, purple_dark = _rgb(BROOM['purple']), _rgb(BROOM['purple_dark'])
    weave = 0.5 + 0.5 * np.sin(2 * np.pi * V * 6) * np.cos(2 * np.pi * U * 40)
    wraps = 0.5 + 0.5 * np.sin(2 * np.pi * V * 6)
    A.paint('BIND', _lerp(purple_dark, purple, 0.35 + 0.65 * wraps * (0.7 + 0.3 * weave)), height=wraps * 0.7 + weave * 0.1, bump=1.5)

    # --- flat colours: SILVER, GOLD (emissive), CHAIN, HAT (purple with a gold band + buckle) ----
    U, V = A.grid('SILVER')
    A.paint('SILVER', _lerp(silver_dark, silver, 0.6 + 0.4 * np.sin(V * 9)), height=np.zeros_like(U))
    U, V = A.grid('GOLD')
    gold = _rgb(BROOM['gold'])
    A.paint('GOLD', _lerp(gold * 0.8, gold, 0.5 + 0.5 * np.sin(U * 7)), height=np.zeros_like(U), emissive=np.ones_like(U) * 0.6)
    U, V = A.grid('CHAIN')
    A.paint('CHAIN', _lerp(silver_dark, silver, 0.5 + 0.5 * np.sin(U * 25 + V * 3)), height=np.zeros_like(U))
    U, V = A.grid('HAT')
    hat, hat_dark = _rgb(BROOM['hat']), _rgb(BROOM['hat_dark'])
    felt = _fbm(U * 2, V, 12.0, octaves=3, seed=44)
    band = _smooth(V, 0.12, 0.16) * _smooth(V, 0.34, 0.3)
    buckle = band * _smooth(np.abs(U - 0.5), 0.09, 0.07) * (1 - _smooth(np.abs(U - 0.5), 0.05, 0.035) * _smooth(np.abs(V - 0.23), 0.07, 0.05))
    hcol = _lerp(hat_dark, hat, 0.5 + 0.5 * felt)
    hcol = _lerp(hcol, _rgb('#1E0A33'), band * 0.9)
    hcol = _lerp(hcol, gold, buckle)
    A.paint('HAT', hcol, height=band * 0.3 + buckle * 0.6, emissive=buckle * 0.5)

    # --- BUCKLE: a silver square with a gold crescent (emissive) ---------------------------------
    U, V = A.grid('BUCKLE')
    frame = 1 - _smooth(np.abs(U - 0.5), 0.5, 0.4) * _smooth(np.abs(V - 0.5), 0.5, 0.4)
    cx, cy = U - 0.5, V - 0.5
    disc = _smooth(np.sqrt(cx * cx + cy * cy), 0.3, 0.26)
    bite = _smooth(np.sqrt((cx - 0.12) ** 2 + (cy - 0.06) ** 2), 0.26, 0.22)
    crescent = np.clip(disc - bite, 0, 1)
    bcol = _lerp(_lerp(silver_dark, silver, 0.3 + 0.7 * frame), _rgb('#2B1C45'), (1 - frame) * 0.9)
    bcol = _lerp(bcol, gold, crescent)
    A.paint('BUCKLE', bcol, height=frame * 0.6 + crescent * 0.5, emissive=crescent)

    A.materials(k, opaque='Bark', alpha='Straw', emissive_tint=BROOM['gold'], emissive_strength=1.6)
    return A


def _hash(i, j):
    """A deterministic 0..1 for strand i, channel j (no random module)."""
    h = (i * 374761393 + j * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def _crook(d):
    """The handle's centreline offset (x, z) at d: straight in both hand zones, a wave of up
    to ±0.06 between them (brief 2.4), eased in and out."""
    w = float(_smooth(d, 2.1, 2.45)) * float(_smooth(d, 4.4, 4.05))
    t = (d - 2.1) / (4.4 - 2.1)
    return (0.06 * w * math.sin(2 * math.pi * t * 1.0 + 0.4), 0.045 * w * math.sin(2 * math.pi * t * 1.5 + 2.2))


@piece
def witch_broom(k):
    """The Witch's Broom body (brief 2.4, concept C3b_broom.png). Tip (0-0.3): a six-sided
    violet Glass crystal over a Neon core (Glow 0.2-0.7 over 2.4 s). Handle (0.3-6.75): one
    bark lathe exactly on the envelope in both hand zones, crooked between them (±0.06), the
    knot hole bulging at 2.6, three twig stubs pointing up between 2.3 and 4.2, the silver
    spiral bands painted flush at 0.3-0.6. Binding (6.75-7.0): purple ridged wraps with a
    silver square buckle on the +X side carrying a gold crescent (emissive). Bristles (joint
    Bristles, Aim fade): a dense straw root flaring past the butt and straw cards with alpha
    (compact to 7.3, 0.5 across; long to 8.2, 0.75 across). The hat charm: two chain links and
    a purple hat with a gold band, one skinned mesh on a 3-bone Sway chain hung from the buckle
    (15-20 degrees over 1.8 s), hanging down and back beside the bristle root."""
    import bmesh
    from mathutils import Vector, Matrix
    R = _radius()
    A = _broom_atlas(k)
    k.material('Crystal', 'Glass', BROOM['crystal'], Transparency=0.2)
    k.material('CrystalCore', 'Neon', BROOM['core'])
    long = LONG['witch_broom']

    # --- the crystal tip --------------------------------------------------------------------
    k.joint('Tip', pivot=(0, 0, 0), visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 0.7, 'Period': 2.4}])
    bm = bmesh.new()
    _lathe(bm, [0.0, 0.05, 0.13, 0.22, 0.3], [0.006, 0.038, 0.058, 0.052, R(0.3)], 6, close=True, twist_per_ring=0.0)
    k.add('Tip', k.mesh_object('TipCrystal', bm, ['Crystal'], smooth=False))
    bm = bmesh.new()
    _lathe(bm, [0.03, 0.1, 0.2, 0.29], [0.012, 0.03, 0.032, 0.03], 6, close=True)
    k.add('Tip', k.mesh_object('TipCore', bm, ['CrystalCore'], smooth=False))

    # --- the handle --------------------------------------------------------------------------
    k.joint('Body', pivot=(0, -3.5, 0))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    n = int(round((HANDLE[1] - HANDLE[0]) / 0.08)) + 1
    ds = [HANDLE[0] + (HANDLE[1] - HANDLE[0]) * i / (n - 1) for i in range(n)]
    centres = [_crook(d) for d in ds]

    def knot_shape(a, i):
        d = ds[i]
        da = (a - KNOT_ANGLE + math.pi) % (2 * math.pi) - math.pi
        bump = math.exp(-(da / 0.7) ** 2) * math.exp(-((d - KNOT_D) / 0.22) ** 2)
        lump = 0.0
        if 2.1 < d < 4.4:  # gentle bark lumps on top only (+Z is up: angle pi), never below
            lump = 0.12 * max(0.0, math.cos(a - math.pi)) * (0.5 + 0.5 * math.sin(d * 7.0))
        return 1.0 + 0.42 * bump + lump
    _lathe_uv(bm, uvl, ds, [R(d) for d in ds], 24, lambda u, v: A.uv('BARK', u, v), centres=centres,
              shape=knot_shape, close=True, cap_uv=A.uv('BARK', 0.5, 0.98))
    k.add('Body', k.mesh_object('Handle', bm, ['Bark']))

    # the twig stubs: short tapering cones growing up (+Z) from the handle, leaning a little
    for i, (d, length, lean) in enumerate(TWIGS):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new('UVMap')
        cx, cz = _crook(d)
        base = Vector((cx, -d, cz + R(d) * 0.6))
        direction = Vector((math.sin(lean) * 0.5, -0.25 + 0.15 * i, math.cos(lean) * 0.5 + 0.5)).normalized()
        ls = [0.0, 0.35, 0.7, 1.0]
        rings = _lathe_uv(bm, uvl, [l * length for l in ls], [0.045, 0.034, 0.024, 0.008], 8,
                          lambda u, v: A.uv('BARK', 0.15 + 0.3 * u, 0.55 + 0.1 * v), close=True)
        _transform(bm, bm.verts[:], _basis(base, direction))
        k.add('Body', k.mesh_object('Twig%d' % (i + 1), bm, ['Bark']))

    # --- the binding and the buckle --------------------------------------------------------------
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    nb = 26
    dsb = [BINDING[0] + (BINDING[1] - BINDING[0]) * i / (nb - 1) for i in range(nb)]
    rsb = [R(d) + 0.025 + 0.02 * (0.5 + 0.5 * math.sin((d - BINDING[0]) / (BINDING[1] - BINDING[0]) * 2 * math.pi * 6)) for d in dsb]
    rsb[0] = R(dsb[0]) + 0.004
    rsb[-1] = R(dsb[-1]) + 0.01
    _lathe_uv(bm, uvl, dsb, rsb, 24, lambda u, v: A.uv('BIND', u, v), close=False)
    # the buckle: a flat silver square on the +X side of the binding, its outer face the crescent
    bd = 0.5 * (BINDING[0] + BINDING[1])
    bx = Vector((1, 0, 0))
    bo = Vector((R(bd) + 0.045 + 0.015, -bd, 0.0))
    _box_uv(bm, uvl, bo, (0.03, 0.17, 0.17), (bx, Vector((0, 1, 0)), Vector((0, 0, 1))),
            lambda axis, sign: (lambda u, v: A.uv('BUCKLE', u, v)) if (axis == 0 and sign == 1)
            else (lambda u, v: A.uv('SILVER', u, v)))
    k.add('Body', k.mesh_object('Binding', bm, ['Bark']))

    # --- the bristles (joint Bristles: Aim fade) ----------------------------------------------
    k.joint('Bristles', pivot=(0, -7.0, 0), parent='Body',
            motion=[{'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 1.2, 'Period': 2.6},
                    {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 0.8, 'Period': 4.0, 'Phase': 90}])
    tip_d = 8.2 if long else 7.3
    tip_r = 0.37 if long else 0.28
    # the dense root: an opaque straw flare from the binding's end
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    root_end = 7.45 if long else 7.24
    nr = 8
    dsr = [7.0 + (root_end - 7.0) * i / (nr - 1) for i in range(nr)]
    root_r = 0.30 if long else 0.24
    rsr = [R(7.0) * 0.98 + (root_r - R(7.0) * 0.98) * ((i / (nr - 1)) ** 0.8) for i in range(nr)]

    def root_shape(a, i):   # fuller on top and the sides, flatter underneath
        return 0.85 + 0.15 * (0.5 - 0.5 * math.cos(a))  # a = pi at the top
    rings_r = _lathe_uv(bm, uvl, dsr, rsr, 18, lambda u, v: A.uv('ROOT', u, v), shape=root_shape, close=False)
    # the cap: the cut ends, a disc whose UVs spread over the ENDS region
    end_ring = rings_r[-1]
    cv = bm.verts.new(sum((x.co for x in end_ring[:-1]), Vector()) / (len(end_ring) - 1))
    for kk in range(len(end_ring) - 1):
        f = bm.faces.new((end_ring[kk], end_ring[kk + 1], cv))
        for lp in f.loops:
            q = lp.vert.co - cv.co
            lp[uvl].uv = A.uv('ENDS', 0.5 + q.x / (2 * rsr[-1]) * 0.9, 0.5 + q.z / (2 * rsr[-1]) * 0.9)
    f0 = bm.faces.new(tuple(rings_r[0][:-1][::-1]))
    _const_uv(bm, uvl, [f0], A.uv('ROOT', 0.5, 0.5))
    k.add('Bristles', k.mesh_object('BristleRoot', bm, ['Bark']))
    # the straw cards: strips from the root ring to the tip, flaring out, over the top and sides
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    cards = 14 if long else 10
    seg = 5 if long else 3
    d0 = 7.12 if long else 7.0
    for c in range(cards):
        frac = (c + 0.5) / cards
        ang = math.pi + (frac - 0.5) * (math.pi * 1.45)     # from the bottom-left round the top to the bottom-right
        rad = Vector((math.sin(ang), 0, -math.cos(ang)))
        tang = Vector((math.cos(ang), 0, math.sin(ang)))
        width = (0.2 if long else 0.17) * (0.8 + 0.4 * _hash(c, 7))
        r0 = rsr[1] * 0.9
        left, right = [], []
        for s in range(seg + 1):
            t = s / seg
            d = d0 + (tip_d - d0) * t
            r = r0 + (tip_r - r0) * (t ** 0.75) * (0.85 + 0.3 * _hash(c, 8))
            r = min(r, 0.39)
            twist = (0.15 * math.sin(t * 3 + c)) * (1 if long else 0.3)
            p = Vector((0, -d, 0)) + rad * r + tang * (twist * r)
            w = width * (0.6 + 0.4 * t)
            left.append(p - tang * (w / 2))
            right.append(p + tang * (w / 2))
        _strip_uv(bm, uvl, left, right, lambda u, v: A.uv('STRAW', (c % 3) / 3 + u / 3, v))
    ob = k.mesh_object('BristleCards', bm, ['Straw'], smooth=False)
    apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=0.006, offset=0.0)
    k.add('Bristles', ob)

    # --- the hat charm: two chain links and the hat on a 3-bone Sway chain ----------------------
    # Hung from the buckle's lower edge, down and back toward the butt, so the hat sits beside
    # the bristle root (past the butt, within 0.42 of the axis).
    P0 = Vector((bo.x - 0.005, -bd - 0.06, -0.085))
    hang = Vector((0.2, -0.75, -0.63)).normalized()
    link = 0.045
    P1 = P0 + hang * link
    P2 = P1 + hang * link
    period = 1.8
    k.joint('Charm', pivot=tuple(P0), parent='Body', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': period},
        {'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': period * 1.45, 'Phase': 40}])
    k.joint('Chain2', pivot=tuple(P1), parent='Charm', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 6.0, 'Period': period, 'Phase': 55}])
    k.joint('Hat', pivot=tuple(P2), parent='Chain2', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 5.0, 'Period': period, 'Phase': 110},
        {'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': period * 1.45, 'Phase': 150}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    side = hang.cross(Vector((0, 1, 0))).normalized()
    for i, c in enumerate((P0 + hang * (link * 0.5), P1 + hang * (link * 0.5))):
        _torus_uv(bm, uvl, c, side if i % 2 == 0 else side.cross(hang), link * 0.5 - 0.004, 0.006, A.uv('CHAIN', 0.5, 0.5), segs=12, minor=6)
    # the hat: a bent cone hanging point-up from P2, its brim below; built along -Y then turned
    hat_h, brim_r, crown_r = 0.12, 0.06, 0.036
    hb = bmesh.new()
    uvh = hb.loops.layers.uv.new('UVMap')
    hs = [0.0, 0.02, 0.05, 0.08, 0.105, 0.12]
    hr = [0.004, 0.012, 0.022, 0.03, crown_r, crown_r]
    bend = [(0.03, 0.0), (0.022, 0.0), (0.012, 0.0), (0.004, 0.0), (0.0, 0.0), (0.0, 0.0)]
    _lathe_uv(hb, uvh, hs, hr, 12, lambda u, v: A.uv('HAT', u, 0.34 + 0.66 * (1 - v)), centres=bend, close=False)
    _lathe_uv(hb, uvh, [hat_h, hat_h + 0.006, hat_h + 0.012, hat_h + 0.018], [crown_r, brim_r, brim_r, crown_r * 0.6], 14,
              lambda u, v: A.uv('HAT', u, 0.12 + 0.22 * (1 - v)), close=True, cap_uv=A.uv('HAT', 0.5, 0.05))
    # the hat's local -Y runs from the point (0) down to the brim: hang it along `hang`
    _transform(hb, hb.verts[:], _basis(P2 + hang * 0.0, hang, up_hint=(1, 0, 0)))
    # merge the hat into the charm mesh
    hat_me = k.bpy.data.meshes.new('HatTmp')
    hb.to_mesh(hat_me)
    hb.free()
    bm.from_mesh(hat_me)
    k.bpy.data.meshes.remove(hat_me)
    ob = k.mesh_object('HatCharm', bm, ['Bark'])
    k.add('Charm', ob)

    def along(V):
        import numpy as np
        return (np.asarray(V) - np.array(P0)) @ np.array(hang)
    k.skins['HatCharm'] = {'root': 'Charm', 'meshes': [ob], 'bones': {
        'Chain2': lambda V: ramp(along(V), link * 0.9, link * 1.1),
        'Hat': lambda V: ramp(along(V), link * 1.9, link * 2.1)}}
    print('CUE broom charm: buckle at d %.2f, hat point %s, long=%s' % (bd, [round(x, 3) for x in P2], long))


# =============================================================================================
# Checks: the budget and the body envelope
# =============================================================================================

def check_budget(pid, spec):
    kind = KIND.get(pid, 'body')
    parts, tris = BUDGET[kind]
    n = len(spec['Parts'])
    if parts is not None and n > parts:
        raise RuntimeError('CUE check_budget FAIL %s: %d parts, the %s budget is %d' % (pid, n, kind, parts))
    if spec['Triangles'] > tris:
        raise RuntimeError('CUE check_budget FAIL %s: %d triangles, the %s budget is %d' % (pid, spec['Triangles'], kind, tris))
    print('CUE check_budget %s: %d parts, %d triangles (%s budget %s parts, %d triangles)' % (pid, n, spec['Triangles'], kind, parts, tris))


def _is_aim(kit, pid, jname):
    aim = set(AIM.get(pid, ()))
    while jname:
        if jname in aim:
            return True
        jname = kit.joints[jname]['Parent']
    return False


def check_envelope(pid, kit):
    """Sample every part's vertices (world space, the Blender cue frame) in 0.1-stud slices
    along the cue against the envelope and the body rules (RULES); raise naming the part, the
    slice and the distance on the first failure. Aura pieces keep only the tip and overhang
    rules; pocket pieces are free."""
    import numpy as np
    kind = KIND.get(pid, 'body')
    if kind == 'pocket' or kit.frame != 'cue':
        print('CUE check_envelope %s: a %s piece, no envelope rules' % (pid, kind))
        return
    R = _radius()
    r = RULES
    worst = 0.0
    seen = set()
    for jname, j in kit.joints.items():
        aim = _is_aim(kit, pid, jname)
        for ob in j['objects']:
            if ob.name in seen:
                continue
            seen.add(ob.name)
            M = np.array(ob.matrix_world)
            co = np.array([v.co[:] for v in ob.data.vertices])
            if not len(co):
                continue
            V = co @ M[:3, :3].T + M[:3, 3]
            x, d, z = V[:, 0], -V[:, 1], V[:, 2]

            def fail(msg, by):
                raise RuntimeError('CUE check_envelope FAIL %s part %s (joint %s): %s by %.3f studs' % (pid, ob.name, jname, msg, by))
            # the tip: nothing in front of the pivot
            over = (-d).max()
            if over > r['TipSlack']:
                fail('reaches past the tip (Y > 0)', over - r['TipSlack'])
            # past the butt
            cap = r['AimPastButt'] if aim else r['PastButt']
            if d.max() > r['Length'] + cap + 1e-4:
                fail('reaches past the butt (%s cap %.1f)' % ('Aim' if aim else 'compact', cap), d.max() - r['Length'] - cap)
            if kind == 'aura':
                continue
            # slices of 0.1 stud
            lo, hi = int(math.floor(d.min() / 0.1)), int(math.floor(d.max() / 0.1))
            for s in range(lo, hi + 1):
                m = (d >= s * 0.1) & (d < (s + 1) * 0.1)
                if not m.any():
                    continue
                sx, sz, sd = x[m], z[m], d[m]
                dm = float(sd.mean())
                rad = np.sqrt(sx * sx + sz * sz)
                env = R(dm)
                if dm < r['TipLength']:
                    if rad.max() > r['TipAcross'] / 2 + 1e-4:
                        fail('too wide at the tip (d %.2f)' % dm, rad.max() - r['TipAcross'] / 2)
                    continue
                if dm > r['Length']:
                    lim = r['AimRadius'] if aim else r['PastButtRadius']
                    if rad.max() > lim + 1e-4:
                        fail('too far off the axis past the butt (d %.2f)' % dm, rad.max() - lim)
                    continue
                in_hand = (r['Bridge'][0] <= dm <= r['Bridge'][1]) or (r['Grip'][0] <= dm <= r['Grip'][1])
                if in_hand and ob.name in BODY_SHAFT.get(pid, (ob.name,)):
                    cx = (sx.min() + sx.max()) / 2
                    cz = (sz.min() + sz.max()) / 2
                    off = math.hypot(cx, cz)
                    if off > r['HandAxis'] + 1e-4:
                        fail('centreline off the axis in a hand zone (d %.2f)' % dm, off - r['HandAxis'])
                    if rad.max() > env + r['HandRadius'] + 1e-4:
                        fail('wider than the envelope in a hand zone (d %.2f)' % dm, rad.max() - env - r['HandRadius'])
                    if rad.max() < env - r['HandRadius'] - 1e-4:
                        fail('thinner than the envelope in a hand zone (d %.2f)' % dm, env - r['HandRadius'] - rad.max())
                    worst = max(worst, abs(rad.max() - env), off)
                    continue
                if in_hand:
                    # decor on the shaft in a hand zone: flush, never standing out
                    if rad.max() > env + r['HandRadius'] + 1e-4:
                        fail('decor stands out in a hand zone (d %.2f)' % dm, rad.max() - env - r['HandRadius'])
                    continue
                if dm >= r['ButtZone'][0]:
                    if rad.max() > env + r['ButtExtra'] + 1e-4:
                        fail('too wide at the butt (d %.2f)' % dm, rad.max() - env - r['ButtExtra'])
                    continue
                side = np.abs(sx).max()
                down = (-sz).max()
                up = sz.max()
                if side > env + r['SideDown'] + 1e-4:
                    fail('too wide sideways (d %.2f)' % dm, side - env - r['SideDown'])
                if down > env + r['SideDown'] + 1e-4:
                    fail('too deep downward (-Z, into the torso on a back) (d %.2f)' % dm, down - env - r['SideDown'])
                up_lim = r['UpMid'] if r['UpMidZone'][0] <= dm <= r['UpMidZone'][1] else r['SideDown']
                if up > env + up_lim + 1e-4:
                    fail('too tall upward (d %.2f)' % dm, up - env - up_lim)
    print('CUE check_envelope %s: OK (hand zones within %.3f of the envelope)' % (pid, worst))


# The part(s) that are the shaft itself in the hand zones (checked for the centreline and the
# exact radius); any other part there is decor and only has to stay flush.
BODY_SHAFT = {
    'witch_broom': ('Handle',),
    'black_cat': ('Shaft',),
    'spider': ('Shaft',),
}


def patch_aim(pid):
    """Write the AIM joint keys into the built piece.json (the exporter writes only its own keys)."""
    path = os.path.join(PIECES_DIR, pid, 'piece.json')
    spec = json.load(open(path))
    for jname in AIM.get(pid, ()):
        if jname not in spec['Joints']:
            raise RuntimeError('CUE patch_aim FAIL %s: AIM names joint %s, which the piece has not got' % (pid, jname))
        spec['Joints'][jname]['Aim'] = 'fade'
    with open(path, 'w') as fh:
        json.dump(spec, fh, indent=2)
        fh.write('\n')
    print('CUE patch_aim %s: %s' % (pid, ', '.join(AIM.get(pid, ())) or 'no Aim joints'))


# =============================================================================================
# Previews: the body on its own (the plain cue hidden), from the views a gate wants
# =============================================================================================

VIEWS = {
    # (camera, target, lens mm): a three-quarter of the whole cue, the hand zones close, the butt end
    'witch_broom': [((4.4, -3.3, 2.4), (0, -3.7, 0.0), 24), ((1.3, -0.8, 0.75), (0, -1.4, 0.0), 50),
                    ((1.7, -8.4, 0.45), (0.1, -7.05, -0.05), 45), ((-1.4, -8.2, 0.9), (0, -7.0, 0.0), 45)],
    'black_cat': [((3.2, -2.2, 1.6), (0, -3.6, 0.05), 32), ((1.4, -4.2, 0.7), (0, -4.0, 0.0), 50),
                  ((1.9, -8.9, 1.1), (0, -7.0, 0.05), 45), ((-1.6, -8.4, 0.9), (0, -7.0, 0.05), 45)],
    'spider': [((3.2, -2.2, 1.6), (0, -3.6, 0.05), 32), ((1.4, -0.9, 0.7), (0, -0.8, 0.0), 50),
               ((1.9, -8.9, 1.1), (0, -7.0, 0.05), 45), ((-1.6, -8.4, 0.9), (0, -7.0, 0.05), 45)],
}


def preview_body(pid, t_list=(0.0, 1.3), size=(800, 500)):
    """pieces/<pid>/preview.png: the built piece on its own cue, the plain mesh hidden for a
    body, the Roblox-like look of CuePieces.preview, from VIEWS (the first view at two moments)."""
    import bpy
    import cue_common as cc
    from mathutils import Vector
    cc.clear_scene('PiecePreview')
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('W')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.05, 0.045, 0.07, 1)
    bg.inputs[1].default_value = 1.0
    scene.world = world
    cue = cc.load_cue_object()
    m = bpy.data.materials.new('plain')
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (0.5, 0.5, 0.55, 1)
    cue.data.materials.clear()
    cue.data.materials.append(m)
    if KIND.get(pid) == 'body':
        cue.hide_render = True
    for loc, e in (((3, -4, 6), 2.5), ((-4, -9, 3), 2.0), ((2, -10, -3), 1.0), ((-3, 1, 2), 1.2)):
        ld = bpy.data.lights.new('L', 'AREA')
        ld.energy = 300 * e
        ld.size = 4
        lo = bpy.data.objects.new('L', ld)
        lo.location = loc
        scene.collection.objects.link(lo)
        lo.rotation_euler = (Vector((0, -4.5, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    animate = CuePieces.attach(bpy, pid, cue)
    cam_d = bpy.data.cameras.new('C')
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = size
    out = os.path.join(PIECES_DIR, pid)
    views = VIEWS.get(pid) or [((1.6, -6.3, 0.35), (0, -6.95, 0.05), 45), ((-0.9, -8.6, 0.9), (0, -6.9, 0.05), 45)]
    for vi, (loc, tgt, lens) in enumerate(views):
        for ti, t in enumerate(t_list if vi == 0 else t_list[:1]):
            animate(t)
            cam.location = loc
            cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam_d.lens = lens
            scene.render.filepath = os.path.join(out, '_v%d_%d.png' % (vi, ti))
            bpy.ops.render.render(write_still=True)
    try:
        CuePieces.stitch(pid)
    except ImportError:
        pass
    print('CUE pieces preview', os.path.join(out, 'preview.png'))


# =============================================================================================
# The entry point
# =============================================================================================

def build_checked(pid, render_preview=True):
    """Build, export, check the budget and the envelope, write the Aim keys, then preview."""
    import bpy
    import cue_common as cc
    cc.clear_scene('CuePieces')
    kit = CuePieces.Kit(bpy, pid)
    CuePieces.BUILDERS[pid](kit)
    spec = CuePieces.export(kit)
    check_budget(pid, spec)
    check_envelope(pid, kit)
    patch_aim(pid)
    if render_preview:
        preview_body(pid)
    return spec


def _cli():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    if '--sheet' in argv:  # system python: join a preview's tiles (Blender's own Python has no PIL)
        CuePieces.stitch(argv[argv.index('--sheet') + 1])
        return
    if '--sheet-sprite' in argv:  # system python: name skin
        i = argv.index('--sheet-sprite')
        CuePieces.sheet_sprite(argv[i + 1], argv[i + 2])
        return
    if '--silhouette' in argv:
        name = argv[argv.index('--silhouette') + 1]
        CuePieces.render_sprite(name)
        return
    for pid in (a for a in argv if not a.startswith('--')):
        build_checked(pid, render_preview='--no-preview' not in argv)


if __name__ == '__main__':
    _cli()
