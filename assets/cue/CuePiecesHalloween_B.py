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
# The Aim joints, also passed as k.joint(aim='fade') so the plain kit CLI writes the same key;
# patch_aim is now a check that both agree (10:40).
AIM = {
    'witch_broom': ['Bristles', 'Charm'],
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
    'Grip': (4.4, 6.2),        # the grip hand zone (rest 5.95, a wind-up slides 1.5 back); the collar past it (remake, 13:10)
    'HandAxis': 0.02,          # centreline within this of the axis in a hand zone
    'HandRadius': 0.04,        # radius within this of the envelope in a hand zone (+0.025 of bark; remake)
    'SideDown': 0.08,          # envelope + this downward (the rails, a back's torso) up to the collar
    'Side': 0.22,              # envelope + this sideways between the hands (remake: the knots and the stub)
    'UpMid': 0.4,              # +Z between 2.1 and 4.4 (the crook, the knots, the branch stub; remake)
    'UpMidZone': (2.1, 4.4),
    'ButtZone': (6.2, 7.0),    # the collar, binding and buckle: envelope + this all round
    'ButtExtra': 0.25,
    'Length': 7.0,
    'PastButt': 0.3,           # a part that does not fade in the aim view (Bodies.PastButtStuds)
    'PastButtRadius': 0.45,    # ... and how far off the axis it may sit there (own number: the Broom's hat charm brim)
    'AimPastButt': 1.5,        # an Aim joint's cap (Bodies.MaxOverhangStuds)
    'AimRadius': 1.1,          # ... and its radial room (the Broom's splayed straw; own number)
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
    'crystal': '#A86BFF', 'core': '#D9B8FF', 'violet': '#9B4DFF', 'emerald': '#2EE6A0',
}

HANDLE = (0.3, 6.75)      # the bark handle's run (d from the tip)
BINDING = (6.75, 7.0)     # the purple wraps
KNOTS = ((2.6, math.pi * 0.86, 0.5), (3.95, math.pi * 1.14, 0.42))  # (d, angle: pi = up, bump) the knot holes between the hand zones
TWIGS = ((2.35, 0.14, 0.55), (3.0, 0.18, -0.35), (4.05, 0.17, 0.2))   # (d, length, lean (rad, +X))


def _broom_atlas(k):
    """Paint and register the Broom's atlas: BARK (the handle's circumference across, its
    length along, with the silver spiral bands at the tip end and the knot hole), BIND (the
    purple wraps), STRAW (strands with alpha for the cards), ROOT (dense straw, opaque), SILVER,
    GOLD, HAT (purple with a gold band) and BUCKLE (silver with the gold crescent, emissive);
    no end-face region: the bristle bundle closes in a dome of strands."""
    import numpy as np
    A = Atlas('witch_broom')
    A.region('BARK', 0.0, 0.0, 0.5, 1.0)
    A.region('STRAW', 0.5, 0.0, 1.0, 0.5)
    A.region('ROOT', 0.75, 0.5, 1.0, 0.75)
    A.region('BIND', 0.5, 0.5, 0.75, 0.75)
    A.region('SILVER', 0.5, 0.75, 0.625, 0.875)
    A.region('GOLD', 0.625, 0.75, 0.75, 0.875)
    A.region('BUCKLE', 0.5, 0.875, 0.625, 1.0)
    A.region('HAT', 0.625, 0.875, 1.0, 1.0)
    A.region('CHAIN', 0.75, 0.75, 1.0, 0.875)
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
    # the knot holes (KNOTS): dark concentric rings sinking into a hole, a raised rim
    for kd, ka, _ in KNOTS:
        ku = ka / (2 * math.pi)
        kv = (kd - HANDLE[0]) / (HANDLE[1] - HANDLE[0])
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
    rng = [(_hash(i, 1), _hash(i, 2), _hash(i, 3), _hash(i, 4)) for i in range(130)]
    for i, (x0, drift, w, tone_) in enumerate(rng):
        x = x0 + (drift - 0.5) * 0.22 * V * V + 0.012 * np.sin(V * 14 + i)
        end = 0.5 + 0.5 * _hash(i, 5)              # where this strand ends (frayed tips)
        width = 0.007 + 0.009 * w
        m = (np.abs(U - x) < width) & (V < end)
        core = np.clip(1 - np.abs(U - x) / width, 0, 1)
        strand = np.maximum(strand, m * core)
        tint = np.where(m & (core > tint), tone_, tint)
        hgt = np.maximum(hgt, m * core)
    alpha = np.clip(strand * 1.6, 0, 1)
    alpha = np.maximum(alpha, _smooth(V, 0.3, 0.0))                        # solid for the first third
    scol = _lerp(_lerp(straw_dark, straw, tint), straw_light, _smooth(hgt, 0.6, 1.0) * 0.5)
    scol = _lerp(scol, straw_dark, _smooth(V, 0.0, 0.12) * 0.5)
    A.paint('STRAW', scol, alpha=alpha, height=hgt * 0.6, bump=1.2)

    # --- ROOT: dense straw, opaque, strands along v (the bulb of the remade head wears it once
    # round, so 64 strands across, darker where they leave the binding) --------------------------
    U, V = A.grid('ROOT')
    g = _fbm(U * 6, V * 0.5, 9.0, octaves=3, seed=31)
    tone = _fbm(U * 8, V, 5.0, octaves=2, seed=57)
    lines = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 64 + 0.25 * g))
    rcol = _lerp(_lerp(straw_dark, straw, lines), straw_light, (lines * g) * 0.5)
    rcol = _lerp(rcol, straw_dark, (1 - tone) * 0.35)
    rcol = _lerp(rcol, straw_dark, _smooth(V, 0.1, 0.0) * 0.5)
    A.paint('ROOT', rcol, height=lines * 0.5 + tone * 0.3, bump=1.0)

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
    """The handle's centreline offset (x, z) at d: straight in both hand zones; between them
    a pulled branch's wave (coordinator, 09:20): a hump of up to 0.185 upward (the +Z room is
    0.25), a shallow dip (-0.02, the down room is 0.08) and ±0.065 sideways, eased in and out."""
    w = float(_smooth(d, 2.1, 2.4)) * float(_smooth(d, 4.4, 4.1))
    t = min(1.0, max(0.0, (d - 2.1) / (4.4 - 2.1)))
    x = 0.1 * w * math.sin(2 * math.pi * t * 1.5 + 0.4)
    z = w * (0.15 * math.sin(math.pi * t) + 0.07 * math.sin(2 * math.pi * t * 2 + 0.3))
    return (x, z)


@piece
def witch_broom(k):
    """The Witch's Broom body, remade 2026-10-28 (Justin, 12:55: a real broom, not a dressed
    cue; concept C3b_broom.png). Tip (0-0.3): a six-sided violet Neon crystal over a brighter
    core (Glow), a silver coil wound round its base. Handle (0.3-6.75, joint Body): one bark
    lathe that keeps the envelope (+0.025 of bark) only where the hands hold it; between the
    hands it is a gnarled branch (three ridges spiralling along it, a crook, two knot holes,
    bark lumps, a thick broken branch stub and two twigs) and before the binding it swells into
    a twisted collar. Binding (6.55-7.05): thick purple cord wraps closed at both ends, a big
    silver buckle on the +X side carrying the gold crescent (emissive). Bristles (joint
    Bristles, Aim fade, 3.3x the first head): an opaque straw bulb from the binding to d 8.47
    (1.2 across at its widest, fuller on top, flatter underneath), a purple cord round its
    waist, three layers of opaque tapered straws (70, double-sided) splaying past it to pointed
    tips up to 1.9 across, the lower ones drooping, and 130 thinner straws poking out of the
    bulb, most near its end (opaque, never alpha cards: the outline inks each straw).
    The hat charm (two chain links and a 0.3-tall hat, one skinned mesh on a 3-bone Sway
    chain) hangs from the buckle below the head, clear of the straw; an Aim joint too."""
    import bmesh
    from mathutils import Vector, Matrix
    R = _radius()
    A = _broom_atlas(k)
    k.material('Crystal', 'Neon', BROOM['crystal'], Transparency=0.3)
    k.material('CrystalCore', 'Neon', BROOM['core'])

    def double_side(bm):
        """Duplicate every face flipped: the cards and strands show from both sides without a
        Solidify rim (Roblox culls back faces; the two layers never show together)."""
        ret = bmesh.ops.duplicate(bm, geom=bm.faces[:])
        bmesh.ops.reverse_faces(bm, faces=[g for g in ret['geom'] if isinstance(g, bmesh.types.BMFace)])

    def tube(bm, uvl, pts, radii, minor, uv_fn):
        """A tube along a polyline (the silver coil)."""
        rings = []
        n = len(pts)
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            u = Vector((0, 0, 1))
            if abs(t.dot(u)) > 0.9:
                u = Vector((1, 0, 0))
            nrm = (u - t * t.dot(u)).normalized()
            bi = t.cross(nrm)
            ring = []
            for j in range(minor + 1):
                a = 2 * math.pi * j / minor
                ring.append(bm.verts.new(p + (nrm * math.cos(a) + bi * math.sin(a)) * radii[i]))
            rings.append(ring)
        for i in range(n - 1):
            for j in range(minor):
                f = bm.faces.new((rings[i][j], rings[i + 1][j], rings[i + 1][j + 1], rings[i][j + 1]))
                for lp, (uu, vv) in zip(f.loops, ((j / minor, i / (n - 1)), (j / minor, (i + 1) / (n - 1)),
                                                 ((j + 1) / minor, (i + 1) / (n - 1)), ((j + 1) / minor, i / (n - 1)))):
                    lp[uvl].uv = uv_fn(uu, vv)

    # --- the crystal tip ---------------------------------------------------------------------
    k.joint('Tip', pivot=(0, 0, 0), visual=[{'Kind': 'Glow', 'Min': 0.25, 'Max': 1.0, 'Period': 2.4}])
    bm = bmesh.new()
    _lathe(bm, [0.0, 0.05, 0.13, 0.22, 0.3], [0.006, 0.038, 0.058, 0.052, R(0.3)], 6, close=True, twist_per_ring=0.0)
    k.add('Tip', k.mesh_object('TipCrystal', bm, ['Crystal'], smooth=False))
    bm = bmesh.new()
    _lathe(bm, [0.03, 0.1, 0.2, 0.29], [0.012, 0.03, 0.032, 0.03], 6, close=True)
    k.add('Tip', k.mesh_object('TipCore', bm, ['CrystalCore'], smooth=False))

    # --- the handle: a gnarled branch ----------------------------------------------------------
    k.joint('Body', pivot=(0, -3.5, 0))

    def mid_w(d):      # 1 between the hands
        return float(_smooth(d, 2.1, 2.45)) * float(_smooth(d, 4.4, 4.05))

    def collar_w(d):   # 1 at the binding
        return float(_smooth(d, 6.15, 6.6))

    def handle_r(d):
        return R(d) + 0.025 + 0.055 * mid_w(d) + 0.1 * collar_w(d)

    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    n = int(round((HANDLE[1] - HANDLE[0]) / 0.08)) + 1
    ds = [HANDLE[0] + (HANDLE[1] - HANDLE[0]) * i / (n - 1) for i in range(n)]
    centres = [_crook(d) for d in ds]

    def bark_shape(a, i):
        d = ds[i]
        w = max(mid_w(d), collar_w(d))
        s = 1.0
        # three ridges winding along the branch (the twist), strongest between the hands and at the collar
        ridge = (0.5 + 0.5 * math.cos(3 * a + d * 2.6)) ** 2
        s += (0.02 + 0.14 * w) * ridge
        for kd, ka, kb in KNOTS:
            da = (a - ka + math.pi) % (2 * math.pi) - math.pi
            s += kb * math.exp(-(da / 0.75) ** 2) * math.exp(-((d - kd) / 0.24) ** 2)
        if 2.1 < d < 4.4:  # bark lumps on top only (+Z is up: angle pi)
            s += 0.08 * mid_w(d) * max(0.0, math.cos(a - math.pi)) * (0.5 + 0.5 * math.sin(d * 7.0))
        # the collar's knob: a twisted swelling on the upper side just before the binding
        s += 0.2 * collar_w(d) * (1 - float(_smooth(d, 6.62, 6.75))) * max(0.0, math.cos(a - math.pi * 0.8)) ** 2
        s *= 1 - 0.1 * w * max(0.0, math.cos(a))   # flatter underneath (the rails, a back)
        return s
    _lathe_uv(bm, uvl, ds, [handle_r(d) for d in ds], 24, lambda u, v: A.uv('BARK', u, v), centres=centres,
              shape=bark_shape, close=True, cap_uv=A.uv('BARK', 0.5, 0.98))
    k.add('Body', k.mesh_object('Handle', bm, ['Bark']))

    # the branch stub (broken off, a jagged end) and two twigs, growing up from the handle
    stubs = [(3.45, 0.27, (0.68, 0.25, 0.55), (0.075, 0.064, 0.052, 0.046), 10),
             (2.35, 0.14, (0.5, -0.25, 0.85), (0.045, 0.034, 0.024, 0.008), 8),
             (4.05, 0.17, (-0.35, -0.1, 0.9), (0.045, 0.034, 0.024, 0.008), 8)]
    for i, (d, length, direction, radii, segs) in enumerate(stubs):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new('UVMap')
        cx, cz = _crook(d)
        base = Vector((cx + 0.3 * handle_r(d) * direction[0], -d, cz + handle_r(d) * 0.55))
        ls = [0.0, 0.35, 0.7, 1.0]
        _lathe_uv(bm, uvl, [l * length for l in ls], list(radii), segs,
                  lambda u, v: A.uv('BARK', 0.15 + 0.3 * u, 0.55 + 0.1 * v), close=True,
                  shape=(lambda a, j: 1 + 0.12 * math.sin(a * 5 + j) * (j == 3)) if i == 0 else None)
        _transform(bm, bm.verts[:], _basis(base, Vector(direction).normalized()))
        k.add('Body', k.mesh_object('Twig%d' % (i + 1), bm, ['Bark']))

    # the silver coil round the crystal's base (the concept's metal bands), 2.5 turns
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    pts = []
    nc = 44
    for i in range(nc + 1):
        t = i / nc
        d = 0.32 + 0.3 * t
        th = 2 * math.pi * 2.5 * t
        rho = R(d) + 0.009
        pts.append(Vector((rho * math.sin(th), -d, -rho * math.cos(th))))
    tube(bm, uvl, pts, [0.011] * (nc + 1), 6, lambda u, v: A.uv('SILVER', u, v))
    k.add('Body', k.mesh_object('Coil', bm, ['Bark']))

    # --- the binding and the buckle ---------------------------------------------------------------
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    b0, b1 = 6.55, 7.05
    nb = 18
    dsb = [b0 + (b1 - b0) * i / (nb - 1) for i in range(nb)]
    rsb = [handle_r(min(d, 6.75)) + 0.03 + 0.03 * (0.5 + 0.5 * math.sin((d - b0) / (b1 - b0) * 2 * math.pi * 7)) for d in dsb]
    rsb[0] = handle_r(b0) + 0.004
    rsb[-1] = rsb[-2] * 0.92
    _lathe_uv(bm, uvl, dsb, rsb, 22, lambda u, v: A.uv('BIND', u, v), close=True, cap_uv=A.uv('BIND', 0.5, 0.5))
    bd = 6.82
    bx = Vector((1, 0, 0))
    bo = Vector((max(rsb) + 0.02, -bd, 0.0))
    _box_uv(bm, uvl, bo, (0.04, 0.22, 0.22), (bx, Vector((0, 1, 0)), Vector((0, 0, 1))),
            lambda axis, sign: (lambda u, v: A.uv('BUCKLE', u, v)) if (axis == 0 and sign == 1)
            else (lambda u, v: A.uv('SILVER', u, v)))
    k.add('Body', k.mesh_object('Binding', bm, ['Bark']))

    # --- the bristle head (joint Bristles: Aim fade) ----------------------------------------------
    k.joint('Bristles', pivot=(0, -7.0, 0), parent='Body',
            motion=[{'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 1.0, 'Period': 2.6},
                    {'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 0.7, 'Period': 4.0, 'Phase': 90}],
            aim='fade')
    bulb_ds = [7.0, 7.12, 7.3, 7.55, 7.85, 8.1, 8.3, 8.42, 8.47]
    bulb_rs = [0.3, 0.42, 0.5, 0.56, 0.58, 0.52, 0.38, 0.22, 0.1]

    def bulb_r(d):
        for (d0, r0), (d1, r1) in zip(zip(bulb_ds, bulb_rs), zip(bulb_ds[1:], bulb_rs[1:])):
            if d0 <= d <= d1:
                t = (d - d0) / (d1 - d0)
                return r0 + (r1 - r0) * t
        return bulb_rs[-1]

    def bulb_shape(a, i):   # fuller on top, flatter underneath, a little ragged
        return (0.88 + 0.17 * (0.5 - 0.5 * math.cos(a))) * (1 + 0.06 * math.sin(a * 7 + i * 1.7))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    _lathe_uv(bm, uvl, bulb_ds, bulb_rs, 24, lambda u, v: A.uv('ROOT', u, v), shape=bulb_shape, close=True,
              cap_uv=A.uv('ROOT', 0.5, 0.95))
    # the purple cord round the bulb's waist
    cds = [7.28, 7.31, 7.36, 7.41, 7.44]
    crs = [bulb_r(d) * 1.0 + (0.0, 0.03, 0.035, 0.03, 0.0)[i] for i, d in enumerate(cds)]
    _lathe_uv(bm, uvl, cds, crs, 24, lambda u, v: A.uv('BIND', u, 0.3 + 0.4 * v), shape=bulb_shape, close=False)
    k.add('Bristles', k.mesh_object('BristleRoot', bm, ['Bark']))

    # The straws: opaque tapered strips, never alpha cards (the cue's inked outline Highlight
    # draws every part's silhouette, so an alpha-cut card outlined as a rectangle and 220 hair-
    # thin strands outlined one by one read as a violet fuzz in the lobby, 13:20). Three layers
    # of wide straws all round, splaying past the bulb to pointed uneven tips, the lower ones
    # drooping; then thinner straws poking out of the bulb, most near its end. Each straw's
    # outline then inks it like a drawn straw, the game's cartoon line.
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    layers = ((0.92, 0.78, 26), (0.72, 1.0, 24), (0.5, 1.18, 20))   # (start share of the binding's radius, tip scale, count)
    tip_r0 = 0.68
    seg = 5
    for li, (share, tscale, cards) in enumerate(layers):
        d0 = 7.02 + 0.05 * li
        for c in range(cards):
            frac = (c + 0.5 + 0.37 * li) / cards
            ang = 2 * math.pi * frac
            rad = Vector((math.sin(ang), 0, -math.cos(ang)))
            tang = Vector((math.cos(ang), 0, math.sin(ang)))
            hc = c + 31 * li
            width = 0.16 * (0.75 + 0.5 * _hash(hc, 7))
            r0 = 0.34 * share * (0.85 + 0.15 * (0.5 - 0.5 * math.cos(ang)))
            end = d0 + (8.48 - d0) * (0.78 + 0.22 * _hash(hc, 5))
            tr = min(0.98, tip_r0 * tscale * (0.85 + 0.3 * _hash(hc, 8)))
            under = max(0.0, math.cos(ang))
            left, right = [], []
            for s in range(seg + 1):
                t = s / seg
                d = d0 + (end - d0) * t
                r = r0 + (tr - r0) * (t ** 0.85)
                twist = 0.1 * math.sin(t * 3 + c)
                p = Vector((0, -d, -0.1 * t * t * under)) + rad * r + tang * (twist * r)
                w = width * (1.0 - 0.85 * t * t)   # to a point
                left.append(p - tang * (w / 2))
                right.append(p + tang * (w / 2))
            u0 = 0.05 + 0.85 * _hash(hc, 9)
            _strip_uv(bm, uvl, left, right, lambda u, v, u0=u0: A.uv('ROOT', u0 + u * 0.06, 0.15 + 0.8 * v))
    for i in range(130):
        h = lambda j: _hash(i + 400, j)
        d = 7.2 + 1.2 * (h(1) ** 0.7)   # more of them toward the end, where the bundle frays
        ang = 2 * math.pi * h(2)
        rad = Vector((math.sin(ang), 0, -math.cos(ang)))
        tang = Vector((math.cos(ang), 0, math.sin(ang)))
        rb = bulb_r(d) * (0.88 + 0.17 * (0.5 - 0.5 * math.cos(ang))) * 0.97
        base = Vector((0, -d, 0)) + rad * rb
        tilt = math.radians(25 + 45 * h(3))
        yaw = math.radians(-25 + 50 * h(4))
        dirv = (rad * math.cos(tilt) + Vector((0, -1, 0)) * math.sin(tilt) + tang * math.sin(yaw) * 0.5).normalized()
        L = 0.22 + 0.25 * h(5)
        if d - dirv.y * L > 8.46:
            L = (8.46 - d) / max(1e-3, -dirv.y)
        if L < 0.1:
            continue
        side = dirv.cross(rad).normalized() if abs(dirv.dot(rad)) < 0.98 else tang
        left, right = [], []
        for s, t in enumerate((0.0, 0.55, 1.0)):
            p = base + dirv * (L * t) + Vector((0, 0, -0.05 * t * t))
            w = 0.055 - 0.04 * t
            left.append(p - side * (w / 2))
            right.append(p + side * (w / 2))
        u0 = 0.05 + 0.85 * h(6)
        _strip_uv(bm, uvl, left, right, lambda u, v, u0=u0: A.uv('ROOT', u0 + u * 0.05, 0.2 + 0.7 * v))
    double_side(bm)
    k.add('Bristles', k.mesh_object('BristleStraws', bm, ['Bark'], smooth=False))

    # --- the hat charm: two chain links and the hat on a 3-bone Sway chain ----------------------
    # Hung from the buckle's lower edge, outward and down, so the hat swings below the head's
    # root, clear of the straw; an Aim joint like the bristles, so it fades for the aiming owner.
    P0 = Vector((bo.x - 0.035, -bd - 0.07, -0.11))
    hang = Vector((0.3, -0.45, -0.85)).normalized()
    link = 0.08
    P1 = P0 + hang * link
    P2 = P1 + hang * link
    period = 1.8
    k.joint('Charm', pivot=tuple(P0), parent='Body', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 7.0, 'Period': period},
        {'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': period * 1.45, 'Phase': 40}], aim='fade')
    k.joint('Chain2', pivot=tuple(P1), parent='Charm', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 6.0, 'Period': period, 'Phase': 55}])
    k.joint('Hat', pivot=tuple(P2), parent='Chain2', motion=[
        {'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 5.0, 'Period': period, 'Phase': 110},
        {'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 3.0, 'Period': period * 1.45, 'Phase': 150}])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    side = hang.cross(Vector((0, 1, 0))).normalized()
    for i, c in enumerate((P0 + hang * (link * 0.5), P1 + hang * (link * 0.5))):
        _torus_uv(bm, uvl, c, side if i % 2 == 0 else side.cross(hang), link * 0.5 - 0.006, 0.009, A.uv('CHAIN', 0.5, 0.5), segs=12, minor=6)
    hat_h, brim_r, crown_r = 0.3, 0.15, 0.09
    hb = bmesh.new()
    uvh = hb.loops.layers.uv.new('UVMap')
    hs = [0.0, 0.05, 0.12, 0.2, 0.26, 0.3]
    hr = [0.01, 0.03, 0.055, 0.075, crown_r, crown_r]
    bend = [(0.075, 0.0), (0.055, 0.0), (0.03, 0.0), (0.01, 0.0), (0.0, 0.0), (0.0, 0.0)]
    _lathe_uv(hb, uvh, hs, hr, 12, lambda u, v: A.uv('HAT', u, 0.34 + 0.66 * (1 - v)), centres=bend, close=False)
    _lathe_uv(hb, uvh, [hat_h, hat_h + 0.014, hat_h + 0.028, hat_h + 0.042], [crown_r, brim_r, brim_r, crown_r * 0.6], 14,
              lambda u, v: A.uv('HAT', u, 0.12 + 0.22 * (1 - v)), close=True, cap_uv=A.uv('HAT', 0.5, 0.05))
    _transform(hb, hb.verts[:], _basis(P2, hang, up_hint=(1, 0, 0)))
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
    print('CUE broom remake: buckle at d %.2f, hat point %s, head to d %.2f' % (bd, [round(x, 3) for x in P2], bulb_ds[-1]))


# =============================================================================================
# Witch's Broom: the aura piece (ribbons) and the pocket piece (portal rings)
# =============================================================================================

@piece
def witch_broom_aura(k):
    """Aura-only decoration (hides with the aura, brief 2.4), the third build (Justin, 12:55: no
    ribbons on any cue, each cue its own hand-made effect): the Broom's are the things a witch
    keeps round her broom. Three gold crescent moons, five four-point stars and two bats as
    meshes orbiting the handle (Spin and Bob, the bats flapping on Sway hinges), the stars
    twinkling (Fade); three spell stars (a five-point Neon star outline with a small solid star
    at its heart, violet, emerald and gold; no rings, nothing occult: Justin 18:45) hovering
    beside the handle facing out, each on a `life` cycle of its own length, turning slowly. The smoke, bats
    bursting from the bristles, the crystal's sparks and the potion bubbles are the skin's
    emitters. Lower effects keeps the moons, two spell stars and one bat; the small stars,
    the third spell star and the second bat hide."""
    import bmesh
    from mathutils import Vector
    R = _radius()
    k.material('Violet', 'Neon', '#8B30FF', Transparency=0.05)
    k.material('Emerald', 'Neon', '#19E088', Transparency=0.05)
    k.material('Gold', 'Neon', BROOM['gold'], Transparency=0.0)
    k.material('Bat', 'SmoothPlastic', '#160A28')
    k.material('BatEye', 'Neon', '#FFD36A')

    def flat(bm, ob_name, mat, thickness):
        ob = k.mesh_object(ob_name, bm, [mat])
        apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=thickness, offset=0.0)
        return ob

    # Three crescent moons standing beside the handle, each turning round it and bobbing.
    for i, (d, rate, period, radius) in enumerate(((1.4, 30.0, 2.4, 0.8), (3.3, -24.0, 3.1, 0.85), (5.2, 36.0, 2.8, 0.8))):
        name = 'Moon%d' % (i + 1)
        k.joint(name, pivot=(0, -d, 0), aura=True,
                motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate},
                        {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.15, 'Period': period, 'Phase': 60 * i}],
                visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.4, 'Period': 1.9 + 0.3 * i, 'Phase': 40 * i,
                         'Color': '#FFE9A8'}])
        bm = bmesh.new()
        c = Vector((radius, -d, 0))
        u, v = Vector((0, 0, 1)), Vector((0, 1, 0))   # the moon's plane is tangent to the handle
        r_out, r_in, off = 0.27, 0.235, 0.13
        n = 14
        outer, inner = [], []
        for j in range(n):
            t = math.radians(62 + (298 - 62) * j / (n - 1))
            s = math.radians(92 + (268 - 92) * j / (n - 1))
            outer.append(bm.verts.new(c + u * (r_out * math.cos(t)) + v * (r_out * math.sin(t))))
            inner.append(bm.verts.new(c + u * (off + r_in * math.cos(s)) + v * (r_in * math.sin(s))))
        for j in range(n - 1):
            bm.faces.new((outer[j], inner[j], inner[j + 1], outer[j + 1]))
        k.add(name, flat(bm, name + 'Crescent', 'Gold', 0.03))

    # Five four-point stars twinkling round the handle (hidden under Lower effects).
    for i, (d, rate, period, phase) in enumerate(((0.9, 22.0, 1.3, 0), (2.0, -28.0, 1.7, 70), (3.0, 20.0, 1.1, 140),
                                                   (4.2, -34.0, 1.9, 210), (5.8, 26.0, 1.5, 280))):
        name = 'Star%d' % (i + 1)
        k.joint(name, pivot=(0, -d, 0), aura=True, low='hide',
                motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate}],
                visual=[{'Kind': 'Fade', 'Min': 0.0, 'Max': 1.0, 'Period': period, 'Phase': phase}])
        bm = bmesh.new()
        c = Vector((0.7, -d, 0))
        u, v = Vector((0, 0, 1)), Vector((0, 1, 0))
        centre = bm.verts.new(c)
        pts = []
        for j in range(8):
            a = math.radians(45 * j + 22.5 * (i % 2))
            r = 0.15 if j % 2 == 0 else 0.05
            pts.append(bm.verts.new(c + u * (r * math.cos(a)) + v * (r * math.sin(a))))
        for j in range(8):
            bm.faces.new((centre, pts[j], pts[(j + 1) % 8]))
        k.add(name, flat(bm, name + 'Star', 'Gold', 0.02))

    # Two bats flying round the handle, bobbing, wings flapping on hinges; gold eyes.
    for i, (d, rate, low) in enumerate(((2.2, 40.0, None), (4.6, -32.0, 'hide'))):
        name = 'Bat%d' % (i + 1)
        k.joint(name, pivot=(0, -d, 0), aura=True, low=low,
                motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate},
                        {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.22, 'Period': 1.1, 'Phase': 90 * i}])
        c = Vector((0.95, -d, 0))
        u, v = Vector((0, 1, 0)), Vector((0, 0, 1))   # wings along the handle, body across the flight
        S = 1.2   # a fifth bigger than the first build: they read from the stand camera
        bm = bmesh.new()
        centre = bm.verts.new(c)
        body = []
        for j in range(12):
            a = 2 * math.pi * j / 12
            body.append(bm.verts.new(c + u * (0.05 * S * math.cos(a)) + v * (0.09 * S * math.sin(a))))
        for j in range(12):
            bm.faces.new((centre, body[j], body[(j + 1) % 12]))
        for sgn in (1, -1):   # ears
            bm.faces.new((bm.verts.new(c + u * (sgn * 0.015 * S) + v * (0.08 * S)), bm.verts.new(c + u * (sgn * 0.045 * S) + v * (0.08 * S)),
                          bm.verts.new(c + u * (sgn * 0.03 * S) + v * (0.14 * S))))
        k.add(name, flat(bm, name + 'Body', 'Bat', 0.02))
        bm = bmesh.new()
        for sgn in (1, -1):
            e = c + u * (sgn * 0.02 * S) + v * (0.045 * S) + Vector((0.012, 0, 0))
            bm.faces.new((bm.verts.new(e + u * (sgn * 0.0) + v * 0.0), bm.verts.new(e + u * (sgn * 0.016 * S)),
                          bm.verts.new(e + u * (sgn * 0.016 * S) + v * (0.014 * S)), bm.verts.new(e + v * (0.014 * S))))
        k.add(name, flat(bm, name + 'Eyes', 'BatEye', 0.01))
        for side, sgn in (('L', 1), ('R', -1)):
            wname = name + 'Wing' + side
            k.joint(wname, pivot=tuple(c), parent=name, aura=True,
                    motion=[{'Kind': 'Sway', 'Axis': (0, 0, 1), 'Amp': 35.0 * sgn, 'Period': 0.5, 'Phase': 30 * i}])
            bm = bmesh.new()
            root = bm.verts.new(c + u * (sgn * 0.04 * S))
            pts = [(0.04, 0.06), (0.16, 0.14), (0.30, 0.10), (0.26, 0.0), (0.30, -0.1), (0.16, -0.12), (0.04, -0.06)]
            vs = [bm.verts.new(c + u * (sgn * y * S) + v * (z * S)) for (y, z) in pts]
            for j in range(len(vs) - 1):
                bm.faces.new((root, vs[j], vs[j + 1]))
            k.add(wname, flat(bm, wname, 'Bat', 0.02))

    # Three spell stars hovering beside the handle, facing out (Justin 18:45: no circled
    # pentagrams, nothing occult; plain stars): a five-point star outline of thin Neon quads
    # (0.028 wide, like the web lines that read in the lab) with a small solid four-point star
    # at its heart, each on a life cycle of its own length, turning slowly round the handle.
    for i, (d, mat, tint, rate, period, phase, low) in enumerate((
            (1.1, 'Violet', '#C9A0FF', 14.0, 6.0, 0, None), (3.0, 'Emerald', '#9CFFD8', -11.0, 7.5, 120, None),
            (4.9, 'Gold', '#FFF0C0', 16.0, 6.8, 240, 'hide'))):
        name = 'Spell%d' % (i + 1)
        k.joint(name, pivot=(0, -d, 0), aura=True, low=low,
                motion=[{'Kind': 'Spin', 'Axis': (0, 1, 0), 'Rate': rate},
                        {'Kind': 'Bob', 'Dir': (0, 1, 0), 'Amp': 0.12, 'Period': 2.9 + 0.4 * i, 'Phase': 50 * i}],
                visual=[{'Kind': 'Fade', 'Min': 0.0, 'Max': 1.0, 'Period': period, 'Shape': 'life', 'Phase': phase},
                        {'Kind': 'Glow', 'Min': 0.0, 'Max': 0.35, 'Period': 1.7, 'Phase': 30 * i, 'Color': tint}])
        bm = bmesh.new()
        c = Vector((0.62, -d, 0))
        u, v = Vector((0, 1, 0)), Vector((0, 0, 1))   # the star's plane faces out from the handle
        w = 0.028

        def line(p, q):
            along = (q - p).normalized()
            across = Vector((0, along.z, -along.y)) * (w / 2)
            bm.faces.new((bm.verts.new(p - across), bm.verts.new(q - across), bm.verts.new(q + across), bm.verts.new(p + across)))
        pts = []
        for j in range(10):
            r = 0.32 if j % 2 == 0 else 0.14
            a = math.pi / 2 + 2 * math.pi * j / 10
            pts.append(c + u * (r * math.cos(a)) + v * (r * math.sin(a)))
        for j in range(10):
            line(pts[j], pts[(j + 1) % 10])
        centre = bm.verts.new(c)
        inner = []
        for j in range(8):
            r = 0.09 if j % 2 == 0 else 0.035
            a = math.pi / 4 + 2 * math.pi * j / 8
            inner.append(bm.verts.new(c + u * (r * math.cos(a)) + v * (r * math.sin(a))))
        for j in range(8):
            bm.faces.new((centre, inner[j], inner[(j + 1) % 8]))
        k.add(name, flat(bm, name + 'Star', mat, 0.02))

@piece
def witch_broom_pocket(k):
    """The Broom's pocket finisher piece (brief 2.4; pocket frame, origin at the mouth, Z up):
    two Neon portal rings, violet and emerald, lying flat and turning in opposite senses (the
    finisher's Rise/Scale/Spin curves lift and widen them), each a fat torus with a thin pale
    rim; a ForceField violet disc inside the lower ring that the swirl layer sits on; six
    small Neon crescents and four-point stars riding the rings, bobbing."""
    import bmesh
    from mathutils import Vector
    k.frame = 'pocket'
    k.material('Violet', 'Neon', BROOM['violet'])
    k.material('Emerald', 'Neon', BROOM['emerald'])
    k.material('Pale', 'Neon', '#F0E4FF')
    k.material('Gold', 'Neon', BROOM['gold'])
    k.material('Disc', 'ForceField', BROOM['violet'], Transparency=0.45)
    k.joint('Portal', pivot=(0, 0, 0), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 90.0}],
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.4, 'Period': 0.7}])
    k.joint('Counter', pivot=(0, 0, 0.55), parent='Portal', motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': -200.0}],
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.5, 'Period': 0.5, 'Phase': 90}])
    for joint, z, Rr, mat in (('Portal', 0.0, 0.9, 'Violet'), ('Counter', 0.55, 0.7, 'Emerald')):
        bm = bmesh.new()
        _torus(bm, (0, 0, z), (0, 0, 1), Rr, 0.06, segs=40, minor=10)
        k.add(joint, k.mesh_object(joint + 'Ring', bm, [mat]))
        bm = bmesh.new()
        _torus(bm, (0, 0, z + 0.07), (0, 0, 1), Rr + 0.02, 0.014, segs=40, minor=6)
        _torus(bm, (0, 0, z - 0.07), (0, 0, 1), Rr - 0.02, 0.014, segs=40, minor=6)
        k.add(joint, k.mesh_object(joint + 'Rim', bm, ['Pale']))
    bm = bmesh.new()
    _lathe(bm, [0.004, -0.004], [0.86, 0.86], 40, close=True)
    bmesh.ops.transform(bm, matrix=__import__('mathutils').Matrix.Rotation(math.radians(-90), 4, 'X'), verts=bm.verts[:])
    k.add('Portal', k.mesh_object('PortalDisc', bm, ['Disc']))
    # charms riding the rings: crescents (gold) and stars (pale), bobbing
    for i in range(8):
        a = 2 * math.pi * i / 8
        joint = 'Portal' if i % 2 == 0 else 'Counter'
        z = 0.0 if i % 2 == 0 else 0.55
        Rr = 0.9 if i % 2 == 0 else 0.7
        name = 'Charm%d' % (i + 1)
        k.joint(name, pivot=(Rr * math.cos(a), Rr * math.sin(a), z + 0.12), parent=joint,
                motion=[{'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.06, 'Period': 0.9, 'Phase': 45 * i}])
        bm = bmesh.new()
        c = Vector((Rr * math.cos(a), Rr * math.sin(a), z + 0.12))
        if i % 2 == 0:
            # a crescent: a ring with a bite (a thin torus arc)
            _torus(bm, c, (math.cos(a), math.sin(a), 0), 0.09, 0.02, segs=24, minor=6)
            k.add(name, k.mesh_object(name + 'Crescent', bm, ['Gold']))
        else:
            # a four-point star: two thin crossed boxes
            _box(bm, c, (0.2, 0.03, 0.03))
            _box(bm, c, (0.03, 0.03, 0.2))
            k.add(name, k.mesh_object(name + 'Star', bm, ['Pale'], smooth=False))


# =============================================================================================
# Black Cat Cue (Mythic): the body
# =============================================================================================

CAT = {
    'black': '#0B0B0D', 'black_soft': '#17171B', 'gold': '#E2B04A', 'claw': '#FFC85A',
    'rim': '#E8B04A', 'fur': '#0A0A0C', 'fur_tip': '#1C1C22',
}
CAT_RINGS = ((3.26, 0.02), (3.36, 0.02), (4.24, 0.02), (4.34, 0.02),     # the pairs (mid zone)
             (6.6, 0.012), (6.67, 0.012), (6.74, 0.012),                   # the triple collar (grip zone: flush)
             (6.92, 0.02))                                                 # the cap ring (butt zone)
CAT_WRAP = (4.4, 6.6)         # the knurled wrap (normal map)
CAT_FOREARM = (3.6, 4.4)      # the three claw slashes


def _sweep_uv(bm, uvl, path, radii, segs, uv_fn, profile=None, cap=True):
    """A tube along `path` (Vectors) with a radius per point and parallel-transported frames,
    segs + 1 vertices a ring (a real seam, at the ring's -normal side) so the UVs never wrap:
    u across 0..1, v along 0..1 (uv_fn maps them). profile(angle) scales the radius."""
    from mathutils import Vector
    pts = [Vector(p) for p in path]
    n = len(pts)
    tangents = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    t0 = tangents[0]
    up = Vector((0, 0, 1))
    if abs(t0.dot(up)) > 0.95:
        up = Vector((1, 0, 0))
    nrm = (up - t0 * t0.dot(up)).normalized()
    rings = []
    for i in range(n):
        t = tangents[i]
        nrm = (nrm - t * t.dot(nrm)).normalized()
        bin_ = t.cross(nrm)
        r = radii[i]
        ring = []
        for k in range(segs + 1):
            ang = 2 * math.pi * k / segs + math.pi
            sc = profile(ang) if profile else 1.0
            ring.append(bm.verts.new(pts[i] + (nrm * math.cos(ang) + bin_ * math.sin(ang)) * (r * sc)))
        rings.append(ring)
    faces = []
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        va, vb = i / (n - 1), (i + 1) / (n - 1)
        for k in range(segs):
            f = bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))
            for lp, (u, v) in zip(f.loops, ((k / segs, va), ((k + 1) / segs, va), ((k + 1) / segs, vb), (k / segs, vb))):
                lp[uvl].uv = uv_fn(u, v)
            faces.append(f)
    if cap:
        for ring, rev, v in ((rings[0], True, 0.0), (rings[-1], False, 1.0)):
            c = sum((x.co for x in ring[:-1]), Vector()) / (len(ring) - 1)
            cv = bm.verts.new(c)
            for k in range(segs):
                q = (ring[k], ring[k + 1], cv)
                f = bm.faces.new(q[::-1] if rev else q)
                for lp in f.loops:
                    lp[uvl].uv = uv_fn(0.5, v)
                faces.append(f)
    return rings, faces


def _curve(points, n):
    """A smooth polyline through `points` (Catmull-Rom), n samples."""
    from mathutils import Vector
    P = [Vector(p) for p in points]
    P = [P[0]] + P + [P[-1]]
    out = []
    m = len(points) - 1
    for i in range(n):
        t = i / (n - 1) * m
        j = min(int(math.floor(t)), m - 1)
        f = t - j
        p0, p1, p2, p3 = P[j], P[j + 1], P[j + 2], P[j + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f))
    return out


def _arc_lengths(pts):
    s = [0.0]
    for a, b in zip(pts[:-1], pts[1:]):
        s.append(s[-1] + (b - a).length)
    return s


def _cat_atlas(k):
    """The Cat's atlas: SHAFT (glossy black, faint scratches, the knurl's diamonds as a normal
    map over the wrap, gold bands under the rings), TIP (black with the gold claw curve,
    emissive) and FUR (near-black strands along the tail, their tips a shade lighter)."""
    import numpy as np
    A = Atlas('black_cat')
    A.region('SHAFT', 0.0, 0.0, 0.5, 1.0)
    A.region('TIP', 0.5, 0.0, 1.0, 0.25)
    A.region('FUR', 0.5, 0.5, 1.0, 1.0)
    A.region('GOLD', 0.5, 0.25, 0.75, 0.5)
    black, soft, gold, claw = (_rgb(CAT[x]) for x in ('black', 'black_soft', 'gold', 'claw'))

    U, V = A.grid('SHAFT')
    d = V * 7.0
    scratch = _smooth(_fbm(U * 2, V * 0.3, 60.0, octaves=2, seed=11), 0.72, 0.8) * 0.5
    sheen = _fbm(U, V, 5.0, octaves=2, seed=12)
    col = _lerp(black, soft, 0.35 * sheen + scratch)
    h = scratch * 0.3
    # the knurl over the wrap: a diamond lattice (two crossed sets of grooves)
    inwrap = _smooth(d, CAT_WRAP[0], CAT_WRAP[0] + 0.03) * _smooth(d, CAT_WRAP[1], CAT_WRAP[1] - 0.03)
    g1 = np.abs(np.sin(2 * np.pi * (U * 18 + V * 7.0 * 9)))
    g2 = np.abs(np.sin(2 * np.pi * (U * 18 - V * 7.0 * 9)))
    knurl = (1 - _smooth(g1, 0.0, 0.25)) + (1 - _smooth(g2, 0.0, 0.25))
    h = h + inwrap * (-0.9 * np.clip(knurl, 0, 1))
    col = _lerp(col, _rgb('#050506'), inwrap * np.clip(knurl, 0, 1) * 0.6)
    col = _lerp(col, soft, inwrap * (1 - np.clip(knurl, 0, 1)) * 0.25)
    # the forearm a hair lighter so its claw slashes sit on a panel
    infore = _smooth(d, CAT_FOREARM[0], CAT_FOREARM[0] + 0.02) * _smooth(d, CAT_FOREARM[1], CAT_FOREARM[1] - 0.02)
    col = _lerp(col, soft, infore * 0.3)
    # gold bands under every ring
    band = np.zeros_like(U)
    for rd, rr in CAT_RINGS:
        band = np.maximum(band, _smooth(np.abs(d - rd), rr + 0.006, rr - 0.002))
    col = _lerp(col, gold, band)
    A.paint('SHAFT', col, height=h, bump=1.8)

    # TIP: the first 0.3 studs: black, a gold claw curve hooking round the ferrule (emissive)
    U, V = A.grid('TIP')
    cx = (U - 0.5) * 2.0          # -1..1 round the tip
    cy = V                        # 0 at the very tip, 1 at 0.3 studs
    # a hooked claw: a crescent-like stroke from the ferrule's base curving to a point near the tip
    ang = np.arctan2(cy - 0.75, cx)
    rad = np.sqrt(cx * cx + (cy - 0.75) ** 2)
    stroke = _smooth(np.abs(rad - 0.55), 0.1, 0.03) * _smooth(ang, -2.9, -2.6) * _smooth(ang, -0.3, -0.6)
    taper = _smooth(ang, -0.6, -2.4)
    clawm = np.clip(stroke * (0.35 + 0.65 * taper), 0, 1)
    tcol = _lerp(black, soft, 0.3 * _fbm(U, V, 6.0, octaves=2, seed=13))
    tcol = _lerp(tcol, claw, clawm)
    A.paint('TIP', tcol, height=clawm * 0.5, emissive=clawm)

    # FUR: strands along v, tips lighter
    U, V = A.grid('FUR')
    fur, fur_tip = _rgb(CAT['fur']), _rgb(CAT['fur_tip'])
    strands = 0.5 + 0.5 * np.sin(2 * np.pi * (U * 34 + 0.5 * _fbm(U, V, 9.0, octaves=3, seed=14) + V * 2))
    strands = strands ** 2
    fine = _fbm(U * 3, V, 50.0, octaves=2, seed=15)
    A.paint('FUR', _lerp(fur, fur_tip, strands * 0.6 + fine * 0.2), height=strands * 0.8 + fine * 0.2, bump=1.6)
    U, V = A.grid('GOLD')
    A.paint('GOLD', _lerp(gold * 0.85, gold, 0.5 + 0.5 * np.sin(U * 9)), height=np.zeros_like(U))
    A.materials(k, opaque='Body', emissive_tint=CAT['claw'], emissive_strength=1.8, Reflectance=0.12)
    return A


def _cat_tail_path(long):
    """The tail's centreline (Vectors) from the cap's end: compact curls up within 0.3 past the
    butt; long sweeps 0.8 back and 0.9 up, the concept's C-curve."""
    if long:
        pts = [(0, -7.0, 0.0), (0, -7.3, 0.02), (0, -7.6, 0.14), (0.02, -7.8, 0.42), (0.03, -7.76, 0.7), (0.02, -7.55, 0.88), (0, -7.3, 0.9)]
    else:
        pts = [(0, -7.0, 0.0), (0, -7.12, 0.01), (0, -7.22, 0.07), (0.01, -7.28, 0.17), (0.01, -7.25, 0.28), (0, -7.15, 0.35)]
    return _curve(pts, 16 if long else 12)


@piece
def black_cat(k):
    """The Black Cat body (brief 2.5, concept C2c_black_cat.png rev 3). One glossy black lathe on
    the envelope from the tip to the butt (Reflectance 0.12), its atlas giving a gold claw curve
    at the ferrule (emissive), faint scratches, a diamond knurl over the wrap 4.4-6.6 (normal
    map) and gold bands under the rings; Foil gold rings: pairs at 3.3 and 4.3, the triple
    collar at 6.6-6.75 (flush), the cap ring; three Neon gold claw slashes raked across the top
    of the forearm (Glow breath 0.1-0.5 over 3 s); the butt cap 6.75-7.0 a touch wider. The
    tail (joint Tail, Aim fade): one skinned fur tube on five bones out of the cap, a Sway
    travelling down it over 2.4 s (8-14 degrees a joint) over a slower sideways Hinge, a sharp flick every 4.2 s (a pulse
    travelling down the bones: it curls up, then drops straight), with a
    slightly larger gold ForceField shell for the thin rim light. Compact: curls up within 0.3
    past the butt; long: 0.8 back and 0.9 up. No head, no face, no eyes anywhere."""
    import bmesh
    import numpy as np
    from mathutils import Vector
    R = _radius()
    A = _cat_atlas(k)
    k.material('Ring', 'Foil', CAT['gold'])
    k.material('TailShell', 'ForceField', CAT['rim'], Transparency=0.3)
    long = LONG['black_cat']

    # --- the shaft: tip (own UV region) + body + cap, one lathe -----------------------------------
    k.joint('Body', pivot=(0, -3.5, 0))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    nt = 7
    dst = [0.3 * i / (nt - 1) for i in range(nt)]
    _lathe_uv(bm, uvl, dst, [max(R(d), 0.03) if i else 0.03 for i, d in enumerate(dst)], 20,
              lambda u, v: A.uv('TIP', u, v), close=True, cap_uv=A.uv('TIP', 0.5, 0.02))
    n = int(round((7.0 - 0.3) / 0.08)) + 1
    ds = [0.3 + (7.0 - 0.3) * i / (n - 1) for i in range(n)]

    def cap_r(d):
        return R(d) + 0.02 * float(_smooth(d, 6.76, 6.82))
    _lathe_uv(bm, uvl, ds, [cap_r(d) for d in ds], 24, lambda u, v: A.uv('SHAFT', u, (0.3 + 6.7 * v) / 7.0),
              close=True, cap_uv=A.uv('SHAFT', 0.5, 0.975))
    k.add('Body', k.mesh_object('Shaft', bm, ['Body']))

    # --- the gold rings ----------------------------------------------------------------------------
    bm = bmesh.new()
    for rd, rr in CAT_RINGS:
        _torus(bm, (0, -rd, 0), (0, 1, 0), cap_r(rd) + rr * 0.45, rr, segs=22, minor=7)
    k.add('Body', k.mesh_object('Rings', bm, ['Ring']))

    # The claw slashes (three Neon strips raked across the forearm) are gone (2026-10-28): the
    # cue's Highlight outline merges round a part that thin into one solid gold slab, even
    # with the part transparent; the atlas scratches carry the claw marks. The uploaded body
    # model still holds the ClawSlashes part; the Parts list below no longer dresses it.

    # --- the tail: a skinned fur tube on five bones, a gold ForceField shell ----------------------
    path = _cat_tail_path(long)
    s = _arc_lengths(path)
    L = s[-1]
    radii = [0.075 * (1 - 0.72 * (si / L) ** 1.2) + 0.012 * math.sin(math.pi * (si / L) ** 2) for si in s]
    bones = ['Tail', 'Tail2', 'Tail3', 'Tail4', 'Tail5']
    at = [0.0, 0.2, 0.42, 0.64, 0.84]
    pivots = []
    for frac in at:
        target = frac * L
        j = min(range(len(s)), key=lambda q: abs(s[q] - target))
        pivots.append(path[j])
    period = 2.4
    for i, (name, piv) in enumerate(zip(bones, pivots)):
        motion = [{'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 8.0 + 1.5 * i, 'Period': period, 'Phase': 55 * i},
                  # the flick (2026-10-28 signature): every 4.2 s the tail curls up sharply from the
                  # base to the tip (a pulse travelling down the bones) and drops straight again
                  {'Kind': 'Hinge', 'Axis': (1, 0, 0), 'Amp': 12.0 + 3.0 * i, 'Period': 4.2, 'Phase': -14 * i, 'Shape': 'pulse'}]
        if i == 0:
            motion.append({'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 6.0, 'Period': 4.0, 'Phase': 20})
        if i == 2:
            motion.append({'Kind': 'Hinge', 'Axis': (0, 0, 1), 'Amp': 4.0, 'Period': 4.0, 'Phase': 120})
        k.joint(name, pivot=tuple(piv), parent=('Body' if i == 0 else bones[i - 1]), motion=motion,
                aim=('fade' if name == 'Tail' else None))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    _sweep_uv(bm, uvl, path, radii, 14, lambda u, v: A.uv('FUR', u, v * 0.98),
              profile=lambda a: 1.0 + 0.08 * math.cos(2 * a))
    tail = k.mesh_object('Tail', bm, ['Body'])
    shell = tail.copy()
    shell.data = tail.data.copy()
    shell.name = shell.data.name = 'TailShell'
    k.bpy.context.scene.collection.objects.link(shell)
    apply_modifier(k.bpy, shell, 'DISPLACE', strength=0.011, mid_level=0.0)
    shell.data.materials.clear()
    shell.data.materials.append(k.blender_mat('TailShell'))
    for poly in shell.data.polygons:
        poly.material_index = 0
    k.add('Tail', tail)
    k.add('Tail', shell)
    P = np.array([list(p) for p in path])
    S = np.array(s)

    def arc(V):
        V = np.asarray(V, float)
        d2 = ((V[:, None, :] - P[None, :, :]) ** 2).sum(-1)
        return S[d2.argmin(1)]
    k.skins['Tail'] = {'root': 'Tail', 'meshes': [tail, shell], 'bones': {
        name: (lambda frac: (lambda V: ramp(arc(V), (frac - 0.07) * L, (frac + 0.07) * L)))(frac)
        for name, frac in zip(bones[1:], at[1:])}}
    print('CUE cat tail: %d samples, %.2f studs long, long=%s, pivots %s' % (len(path), L, long, [[round(x, 2) for x in p] for p in pivots]))


# =============================================================================================
# Black Cat (Mythic): the aura piece (the Cat moved to lane Cues A on 2026-10-28 13:08; the
# body builder above and this block are Cues A's; the Broom and the Spider stay Cues B's)
# =============================================================================================

def _cat_flat(k, bm, ob_name, mat, thickness):
    ob = k.mesh_object(ob_name, bm, [mat])
    apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=thickness, offset=0.0)
    return ob


def _cat_polygon(bm, origin, u, v, pts, scale=1.0, about=(0.0, 0.0)):
    """One n-gon (concave allowed, ear-clipped) from 2D points in the plane (origin, u, v)."""
    import bmesh
    verts = []
    for (x, y) in pts:
        x = about[0] + (x - about[0]) * scale
        y = about[1] + (y - about[1]) * scale
        verts.append(bm.verts.new(origin + u * x + v * y))
    bm.faces.new(verts)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], ngon_method='EAR_CLIP')
    return bm


def _cat_band(bm, origin, u, v, pts, s_out, s_in, about):
    """A band following a polygon's outline in the plane (origin, u, v): quads between the
    polygon scaled `s_out` and `s_in` about `about` (the thin gold rim round a shadow cat)."""
    def at(x, y, sc):
        return origin + u * (about[0] + (x - about[0]) * sc) + v * (about[1] + (y - about[1]) * sc)
    outer = [bm.verts.new(at(x, y, s_out)) for (x, y) in pts]
    inner = [bm.verts.new(at(x, y, s_in)) for (x, y) in pts]
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((outer[i], outer[j], inner[j], inner[i]))
    return bm


# A running cat seen from the side, nose toward +x, standing on y = 0 (the concept's shadow
# cats: no face, no eyes; a silhouette).
CAT_SIL = [
    (0.50, 0.30), (0.44, 0.40), (0.47, 0.50), (0.40, 0.42), (0.34, 0.50), (0.30, 0.40),
    (0.20, 0.36), (0.00, 0.34), (-0.20, 0.32), (-0.36, 0.30),
    (-0.40, 0.33), (-0.50, 0.42), (-0.60, 0.54), (-0.70, 0.58), (-0.68, 0.50), (-0.58, 0.44),
    (-0.49, 0.34), (-0.44, 0.24),
    (-0.48, 0.16), (-0.64, 0.06), (-0.60, 0.00), (-0.44, 0.08), (-0.34, 0.14),
    (-0.16, 0.16), (0.04, 0.16),
    (0.12, 0.08), (0.30, -0.02), (0.36, 0.04), (0.24, 0.12), (0.34, 0.18), (0.44, 0.22),
]


def _cat_track(R, d0=0.8, d1=6.5, lift=0.2, step=0.1):
    """The shadow cats' racetrack: along the TOP of the shaft from the butt toward the tip
    (the way a strike goes), half a turn round the cue at the tip end, back along the belly,
    half a turn round at the butt end. Frames (columns side, tangent, normal away from the
    cue, point) every `step` studs; returns (frames, step, length)."""
    import numpy as np

    def at(d, a):
        return np.array([math.sin(a) * (R(d) + lift), -d, math.cos(a) * (R(d) + lift)])

    samples = []
    N = 400
    for i in range(N):                       # the top leg: d1 -> d0 at a = 0 (+Z, up)
        d = d1 - (d1 - d0) * i / (N - 1)
        samples.append((at(d, 0.0), 0.0))
    for i in range(1, 40):                   # round the tip end to the belly
        a = math.pi * i / 40
        samples.append((at(d0, a), a))
    for i in range(N):                       # the belly leg: d0 -> d1 at a = pi
        d = d0 + (d1 - d0) * i / (N - 1)
        samples.append((at(d, math.pi), math.pi))
    for i in range(1, 40):                   # round the butt end back to the top
        a = math.pi + math.pi * i / 40
        samples.append((at(d1, a), a))
    P = np.array([s[0] for s in samples])
    A = np.array([s[1] for s in samples])
    seg = np.linalg.norm(np.diff(np.vstack([P, P[:1]]), axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    L = float(cum[-1])
    nF = max(int(round(L / step)), 8)
    frames = []
    Pc = np.vstack([P, P[:1]])
    Ac = np.concatenate([A, A[:1]])
    for j in range(nF):
        sj = j * L / nF
        p = np.array([np.interp(sj, cum, Pc[:, c]) for c in range(3)])
        a = float(np.interp(sj, cum, Ac))
        s2 = (sj + 0.05) % L
        s1 = (sj - 0.05) % L
        p2 = np.array([np.interp(s2, cum, Pc[:, c]) for c in range(3)])
        p1 = np.array([np.interp(s1, cum, Pc[:, c]) for c in range(3)])
        t = p2 - p1
        t /= max(np.linalg.norm(t), 1e-6)
        n = np.array([math.sin(a), 0.0, math.cos(a)])
        n = n - t * float(np.dot(t, n))
        n /= max(np.linalg.norm(n), 1e-6)
        side = np.cross(t, n)
        M = np.eye(4)
        M[:3, 0], M[:3, 1], M[:3, 2], M[:3, 3] = side, t, n, p
        frames.append(M)
    return frames, L / nF, L


def _claw_blade(bm, origin, along, up, length, width, bend, n=14):
    """One claw slash in the plane (origin, along, up): a crescent `length` long bowing `bend`
    toward `up`, `width` at its middle, tapering to points at both ends (a hooked claw's
    tear through the air)."""
    from mathutils import Vector
    left, right = [], []
    for i in range(n):
        u = i / (n - 1)
        c = origin + along * ((u - 0.5) * length) + up * (bend * math.sin(math.pi * u))
        # the in-plane normal of the arc (perpendicular to its tangent)
        du = along * length + up * (bend * math.pi * math.cos(math.pi * u))
        nrm = (up * du.dot(along) - along * du.dot(up)).normalized()
        w = width * math.sin(math.pi * u) ** 0.7
        left.append(bm.verts.new(c - nrm * (w / 2)))
        right.append(bm.verts.new(c + nrm * (w / 2)))
    for i in range(n - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    return bm


@piece
def black_cat_aura(k):
    """Aura-only decoration of the Black Cat (hides with the aura): the cue's own hand-made
    signature (designer, 2026-10-28 12:55: no ribbons; the coordinator's 13:08 rule: no head,
    no face, no eyes, no paw prints). Three shadow cats (black silhouettes with a thin gold
    Neon rim, two crossed planes each so they read from every side) race along the top of the
    shaft toward the tip and back under its belly, a lap in 7 s, a third of a lap apart,
    galloping (a quick Bob); three gold claw swipes (three crescent Neon blades each, a claw's
    rake) hang beside the shaft at 1.9, 3.7 and 5.4 studs and every 3.6 s one of them tears
    through the air (a Hinge pulse of 55 degrees) flashing in with a Fade beat and fading out,
    its embers (the skin's ClawEmbers rows ride these joints) left behind. The tail flick lives
    in the body. Lower effects keeps two cats and two swipes."""
    import bmesh
    from mathutils import Vector
    R = _radius()
    k.material('Shadow', 'SmoothPlastic', CAT['black'])
    k.material('Rim', 'Neon', '#E8A830', Transparency=0.0)     # deeper golds: Neon blooms, and a
    k.material('Claw', 'Neon', '#E09A20', Transparency=0.0)    # bright one turned three blades into a plate

    frames, step, length = _cat_track(R)
    k.path('Race', frames, step)
    speed = length / 7.0
    for i in range(3):
        name = 'Cat%d' % (i + 1)
        rest = length * i / 3.0
        idx = int(round(rest / step)) % len(frames)
        F = frames[idx]
        side, tang, nrm, pt = Vector(F[:3, 0]), Vector(F[:3, 1]), Vector(F[:3, 2]), Vector(F[:3, 3])
        k.joint(name, pivot=tuple(pt), aura=True, low=('hide' if i == 2 else None),
                motion=[{'Kind': 'Path', 'Path': 'Race', 'Rest': rest, 'Speed': speed},
                        {'Kind': 'Bob', 'Dir': (0, 0, 1), 'Amp': 0.035, 'Period': 0.42, 'Phase': 90 * i, 'Shape': 'snap'}],
                visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.2, 'Period': 2.2 + 0.4 * i, 'Phase': 70 * i, 'Color': '#FFE2A0'}])
        # One silhouette a cat, standing on the cue but leaning 40 degrees outward (crossed
        # planes were tried: the pair read as a black lump from most angles), so it reads from
        # the side and from above alike; a black plane with a gold Neon band round its outline
        # (a full gold plate under the black one showed through as a yellow cat in the lab).
        lean = nrm * math.cos(math.radians(40)) + side * (math.sin(math.radians(40)) * (1 if i % 2 == 0 else -1))
        bm = bmesh.new()
        _cat_polygon(bm, pt, tang, lean, CAT_SIL, scale=0.9)
        k.add(name, _cat_flat(k, bm, name + 'Shadow', 'Shadow', 0.04))
        bm = bmesh.new()
        _cat_band(bm, pt, tang, lean, CAT_SIL, 0.96, 0.9, (-0.1 * 0.9, 0.3 * 0.9))
        k.add(name, _cat_flat(k, bm, name + 'Rim', 'Rim', 0.02))

    # The claw swipes: three crescent blades in the plane of the cue axis and the radial, hung
    # 0.42 off the surface; the Hinge about the side axis rakes them within that plane.
    for i, (d, ang, phase) in enumerate(((1.9, math.radians(35), 0), (3.7, math.radians(-110), 120), (5.4, math.radians(150), 240))):
        name = 'Swipe%d' % (i + 1)
        radial = Vector((math.sin(ang), 0, math.cos(ang)))
        along = Vector((0, -1, 0))
        side = along.cross(radial).normalized()
        base = Vector((0, -d, 0)) + radial * (R(d) + 0.42)
        k.joint(name, pivot=tuple(base), aura=True, low=('hide' if i == 2 else None),
                motion=[{'Kind': 'Hinge', 'Axis': tuple(side), 'Amp': 55.0, 'Period': 3.6, 'Phase': phase + 18, 'Shape': 'pulse'}],
                visual=[{'Kind': 'Fade', 'Min': 0.0, 'Max': 1.0, 'Period': 3.6, 'Phase': phase / 360.0, 'Shape': 'beat'}])
        # Three distinct slashes well apart (0.27; closer, their Neon bloom merged them into one
        # plate in the lab), staggered 0.1 along the cue like a raking paw.
        bm = bmesh.new()
        for j in range(3):
            o = base + radial * (0.27 * (j - 1)) + along * (0.1 * (j - 1))
            _claw_blade(bm, o, along, radial, 0.8, 0.06, 0.16)
        k.add(name, _cat_flat(k, bm, name + 'Claws', 'Claw', 0.03))


# =============================================================================================
# Spider Cue (Mythic): the body
# =============================================================================================

SPIDER = {
    'black': '#0A0A0E', 'black_light': '#1E1E26', 'silver': '#C9CED8', 'silver_bright': '#F2F5FA',
    'silk': '#DDE3F0', 'crimson': '#C0142C', 'red': '#E8102E', 'red_glow': '#FF3A50', 'eye': '#FF2038',
}
SPIDER_BLADES = 8
SPIDER_COLLAR = (6.28, 6.62)          # the joint: a six-flat collar in the butt zone, the gem on its top flat
SPIDER_BANDS = (0.75, 1.35, 1.95, 2.55, 3.15, 3.75, 4.35, 4.95, 5.55, 6.05)   # the red chevron bands (d)
# the collar and the neck, (d, r): the shaft flares into a six-flat prism, steps down to a neck the
# crown roots on; None = the envelope. The eye dome (SPIDER_DOME) is a crown part past the neck, the
# exposed end of the cue (coordinator 19:08: C1's dome is the first thing seen from behind).
SPIDER_CAP = ((6.28, None), (6.32, 0.26), (6.38, 0.36), (6.44, 0.40), (6.56, 0.40), (6.62, 0.34), (6.72, 0.30),
              (6.90, 0.30), (6.96, 0.28))
# the crown's neck and the eye dome, (d, r), one lathe on the Crown joint: the neck carries on from
# the body's (which stops at 6.96, the compact room) out to the dome at 7.55-8.21, the exposed end
# of the cue (Aim room 8.5); the blades root at the dome's base and sweep 1.3 studs forward
SPIDER_DOME = ((6.98, 0.30), (7.3, 0.30), (7.5, 0.32), (7.58, 0.38), (7.68, 0.42), (7.8, 0.43), (7.95, 0.40),
               (8.06, 0.32), (8.14, 0.2), (8.19, 0.08), (8.21, 0.0))


def _spider_atlas(k):
    """The Spider's atlas: SHAFT (glossy black with twelve long facets and a thin silver seam
    beside each band; the bands themselves are Neon geometry), TIP (the red crystal spear: six
    facets, pale edges, emissive) and CAP (the collar's silver facet edges, the dome's black)."""
    import numpy as np
    A = Atlas('spider')
    A.region('SHAFT', 0.0, 0.0, 0.5, 1.0)
    A.region('TIP', 0.5, 0.0, 1.0, 0.25)
    A.region('CAP', 0.5, 0.25, 1.0, 1.0)
    black, black_light, silver, red = (_rgb(SPIDER[x]) for x in ('black', 'black_light', 'silver', 'red'))

    U, V = A.grid('SHAFT')
    d = V * 7.0
    sheen = _fbm(U, V, 3.0, octaves=2, seed=61)
    col = _lerp(black, black_light, 0.35 * sheen)
    facet = (U * 12) % 1.0
    col = _lerp(col, black_light, 0.25 * facet)
    seam = np.zeros_like(U)
    for b in SPIDER_BANDS:
        seam = np.maximum(seam, _smooth(np.abs(d - (b + 0.075)), 0.02, 0.008))
    col = _lerp(col, silver, seam * 0.8)
    A.paint('SHAFT', col, height=facet * 0.15 - seam * 0.3, emissive=np.zeros_like(U), bump=1.2)

    U, V = A.grid('TIP')
    facet = np.abs(((U * 6) % 1.0) - 0.5) * 2.0
    edge = _smooth(facet, 0.8, 0.95)
    tcol = _lerp(_lerp(red * 0.6, red, 0.6 * facet), _rgb('#FFB0B8'), edge)
    A.paint('TIP', tcol, height=edge * 0.5, emissive=np.clip(0.55 + 0.45 * edge, 0, 1))

    U, V = A.grid('CAP')
    fac = np.abs(((U * 6) % 1.0) - 0.5) * 2.0
    edge = _smooth(fac, 0.9, 0.97) * _smooth(V, 0.4, 0.3)       # the collar is the low third of the region
    ccol = _lerp(_lerp(black, black_light, 0.3 * fac), silver, edge)
    ccol = _lerp(ccol, black_light, 0.25 * _fbm(U, V, 4.0, octaves=2, seed=64) * _smooth(V, 0.35, 0.5))
    A.paint('CAP', ccol, height=edge * 0.5, emissive=np.zeros_like(U))

    A.materials(k, opaque='Body', emissive_tint=SPIDER['red_glow'], emissive_strength=1.6,
                Material='Foil', Reflectance=0.12)
    return A


def _spider_blade_curve(theta, long=True):
    """A leg-blade's centreline (Vectors) and its radial direction: rooted at the dome's base
    (d 7.55), sweeping FORWARD along the butt and flaring out like a splayed spider leg (a cubic
    in the (d, out) plane, out to 0.93 of the Aim room 1.1), the tip turning in and pointing up
    the shaft at d 6.24: just behind the grip hand's rest at 5.95 (the grip zone 4.4-6.2 stays
    flush), the way C1's hand holds the shaft ahead of the crown (coordinator 19:08). Four broad
    blades on the diagonals and four short ones between (tip at d 6.8, out 0.6) so the crown's
    silhouette is jagged, not a cage (v9 lab); the centreline keeps room for the blade's width
    (a crescent 0.32 wide at its bulge, the inner edge taking most of it)."""
    from mathutils import Vector
    rad = Vector((math.sin(theta), 0, -math.cos(theta)))      # out from the axis at this angle
    topness = 0.5 + 0.5 * math.cos(theta - math.pi)           # 1 at the top (+Z), 0 at the bottom
    if long:
        P = ((7.55, 0.34), (7.3, 0.8 + 0.03 * topness), (6.72, 0.86 + 0.03 * topness), (6.24, 0.74))
    else:
        P = ((7.55, 0.34), (7.4, 0.62), (7.05, 0.7), (6.8, 0.6))
    pts = []
    n = 13
    for s in range(n):
        t = s / (n - 1)
        b = ((1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3)
        d = sum(w * p[0] for w, p in zip(b, P))
        out = sum(w * p[1] for w, p in zip(b, P))
        pts.append(Vector((0, -d, 0)) + rad * out)
    return pts, rad


@piece
def spider(k):
    """The Spider body, the fourth build (Justin 18:45: redone to C1_spider.jpg / C1b_spider.png,
    real 3D geometry): a glossy black shaft (Foil, one atlas) with a red crystal spear in the tip
    limits; ten Neon red angular chevron bands standing 0.012 proud, each turned a little
    further round so they spiral up the shaft;
    at the joint a six-flat collar (d 6.28-6.62, the butt zone) with a red Neon hourglass gem on
    three of its flats (Glow); and the crown (joint Crown, Aim fade, the fifth build after the
    coordinator's 19:08 review): the glossy black eye dome as the exposed END of the cue (d
    7.55-8.21, past the butt on the Aim room, on a neck from 6.98) studded with twelve glowing red eyes (Neon
    hemispheres: one at the pole, seven filling the end face, eight smaller round the rim; Glow
    kept red), and EIGHT curved black blades rooted at the dome's base sweeping FORWARD along
    the butt like splayed legs, their tips toward the shaft at d 6.24 just behind the grip
    hand's rest: four broad bevelled crescents on the diagonals (0.32 wide at the bulge, 0.06
    thick) and four short ones between, each with a Neon red rim along its OUTER edge only, each
    a skinned fin on its own bone breathing on a Hinge; Neon red rim rings where the crown meets
    the dome and the neck (the sixth build, coordinator 19:3x: no silk lines on the crown, the
    dome plain glossy black, big eyes, broad solid blades, red under-glow). Seven parts: Shaft,
    Bands, Gem and the crown's Dome, Eyes, Blades, BladeEdges. Everything that must read on the
    bright floor is Neon geometry; the silk is the skin's live beams."""
    import bmesh
    import numpy as np
    from mathutils import Vector, Matrix
    R = _radius()
    A = _spider_atlas(k)
    k.material('Red', 'Neon', SPIDER['red'])
    k.material('Eye', 'Neon', SPIDER['eye'])
    k.material('Blade', 'SmoothPlastic', '#0B0B10')   # no Reflectance: 0.15 mirrored the skybox as a purple checker (v11 lab)

    # --- the shaft: crystal spear, the shaft on the envelope, the collar and the eye cap ----------
    k.joint('Body', pivot=(0, -3.5, 0))
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new('UVMap')
    _lathe_uv(bm, uvl, [0.0, 0.05, 0.14, 0.24, 0.3], [0.004, 0.028, 0.048, 0.057, R(0.3)], 6,
              lambda u, v: A.uv('TIP', u, v), close=True, cap_uv=A.uv('TIP', 0.5, 0.02))
    c0 = SPIDER_COLLAR[0]
    n = int(round((c0 - 0.3) / 0.1)) + 1
    ds = [0.3 + (c0 - 0.3) * i / (n - 1) for i in range(n)]
    _lathe_uv(bm, uvl, ds, [R(d) for d in ds], 20, lambda u, v: A.uv('SHAFT', u, (0.3 + (c0 - 0.3) * v) / 7.0),
              close=True, cap_uv=A.uv('SHAFT', 0.5, 0.5))
    cap_ds = [p[0] for p in SPIDER_CAP]
    cap_rs = [p[1] if p[1] is not None else R(p[0]) for p in SPIDER_CAP]

    def hexshape(a, i):
        if 0 < i and cap_ds[i] < SPIDER_COLLAR[1] - 1e-6:
            # a six-flat prism inscribed in the ring, a flat centred on +Z (the gem sits on it)
            delta = ((a - math.pi + math.pi / 6) % (math.pi / 3)) - math.pi / 6
            return math.cos(math.pi / 6) / math.cos(delta)
        return 1.0
    _lathe_uv(bm, uvl, cap_ds, cap_rs, 24, lambda u, v: A.uv('CAP', u, v), shape=hexshape, close=True,
              cap_uv=A.uv('CAP', 0.5, 0.98))
    k.add('Body', k.mesh_object('Shaft', bm, ['Body']))

    # --- the bands: Neon red zigzag rings, six teeth each, turned 0.24 of a tooth further each band
    bm = bmesh.new()
    N = 24
    for bi, d in enumerate(SPIDER_BANDS):
        phase = 0.24 * bi
        rr = R(d) + 0.012
        L, Rt = [], []
        for j in range(N):
            a = 2 * math.pi * j / N
            tri = abs(((a * 6 / (2 * math.pi) + phase) % 1.0) - 0.5) * 2.0
            off = 0.064 * (tri - 0.5)
            for lst, half in ((L, -0.017), (Rt, 0.017)):
                dd = d + off + half
                lst.append(bm.verts.new(Vector((rr * math.sin(a), -dd, -rr * math.cos(a)))))
        for j in range(N):
            bm.faces.new((L[j], Rt[j], Rt[(j + 1) % N], L[(j + 1) % N]))
    k.add('Body', _flat(k, bm, 'Bands', 'Red', 0.012))

    # --- the gem: a red hourglass (two triangles point to point, 0.05 thick, 0.32 tall) on three of
    # the collar's flats (the top and the two lower sides, so one faces every view), pulsing
    k.joint('Gem', pivot=(0, -6.47, 0), parent='Body',
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.6, 'Period': 1.7, 'Color': '#FF9AA0'}])
    bm = bmesh.new()
    for phi in (math.pi, math.pi / 3, 5 * math.pi / 3):      # the top flat and the two lower side flats
        nrm = Vector((math.sin(phi), 0, -math.cos(phi)))      # out through the flat's centre
        tg = Vector((math.cos(phi), 0, math.sin(phi)))        # round the collar
        c = nrm * 0.372 + Vector((0, -6.47, 0))
        for sgn in (1, -1):
            a = bm.verts.new(c + Vector((0, sgn * 0.006, 0)))
            b = bm.verts.new(c + Vector((0, sgn * 0.16, 0)) - tg * 0.1)
            d = bm.verts.new(c + Vector((0, sgn * 0.16, 0)) + tg * 0.1)
            bm.faces.new((a, b, d) if sgn > 0 else (a, d, b))
    ob = k.mesh_object('Gem', bm, ['Red'], smooth=False)
    apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=0.05, offset=0.0)
    k.add('Gem', ob)

    # --- the crown: the eye dome at the end, the eyes, four broad and four short skinned
    # crescent blades with a red rim on the outer edge, red rim rings (coordinator 19:3x) ----------
    k.joint('Crown', pivot=(0, -7.55, 0), parent='Body', aim='fade')
    bm = bmesh.new()
    _lathe(bm, [q[0] for q in SPIDER_DOME], [q[1] for q in SPIDER_DOME], 24, close=True)
    k.add('Crown', k.mesh_object('Dome', bm, ['Blade']))
    # the eyes: Neon red hemispheres (icospheres half sunk into the dome): one at the pole, seven
    # round it filling the end face, eight smaller round the rim; the Glow stays red
    k.joint('Eyes', pivot=(0, -8.0, 0), parent='Crown',
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.35, 'Period': 1.3, 'Color': '#FF3344'}])
    bm = bmesh.new()
    dome_ds = [q[0] for q in SPIDER_DOME]
    dome_rs = [q[1] for q in SPIDER_DOME]

    def dome_r(d):
        return float(np.interp(d, dome_ds, dome_rs))
    eyes = [(8.17, 0.11, 0.0, 0.0)]
    eyes += [(8.1, 0.09, 2 * math.pi * j / 7, 0.21) for j in range(7)]
    eyes += [(7.8, 0.06, math.pi / 8 + j * math.pi / 4, dome_r(7.8) - 0.03) for j in range(8)]
    for d, r, a, rho in eyes:
        c = Vector((rho * math.sin(a), -d, -rho * math.cos(a)))
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r, matrix=Matrix.Translation(c))   # 80 tris each (two subdivisions passed the budget)
    k.add('Eyes', k.mesh_object('Eyes', bm, ['Eye']))
    thetas = [i * math.pi / 4 for i in range(SPIDER_BLADES)]       # the broad ones on the diagonals
    curves = []
    bm_b = bmesh.new()
    uvl_b = bm_b.loops.layers.uv.new('UVMap')
    bm_e = bmesh.new()
    uvl_e = bm_e.loops.layers.uv.new('UVMap')
    flat_uv = lambda u, v: (u, v)  # noqa: E731
    for i, theta in enumerate(thetas):
        big = i % 2 == 1
        pts, rad = _spider_blade_curve(theta, long=big)
        curves.append((pts, rad))
        k.joint('Blade%d' % (i + 1), pivot=tuple(pts[0]), parent='Crown', motion=[
            {'Kind': 'Hinge', 'Axis': tuple(Vector((0, 1, 0)).cross(rad)), 'Amp': 1.5 + 1.0 * (i % 3) / 2,
             'Period': 3.1 + 0.17 * i, 'Phase': 45 * i}])
        # a crescent: the outer rim follows the centreline's convex sweep, the inner edge takes
        # most of the width so it bows back toward the shaft; broad at the bulge, a point at the tip
        wmax = 0.32 if big else 0.22
        inner, outer = [], []
        for s, p in enumerate(pts):
            t = s / (len(pts) - 1)
            w = 0.1 * (1 - t) + wmax * (math.sin(math.pi * t) ** 1.2) + 0.012
            inner.append(p - rad * (w * 0.7))
            outer.append(p + rad * (w * 0.3))
        _strip_uv(bm_b, uvl_b, inner, outer, flat_uv)
        eo = [o + rad * 0.004 for o in outer]
        _strip_uv(bm_e, uvl_e, [o - rad * 0.012 for o in eo], [o + rad * 0.02 for o in eo], flat_uv)
    blades = k.mesh_object('Blades', bm_b, ['Blade'])
    apply_modifier(k.bpy, blades, 'SOLIDIFY', thickness=0.06, offset=0.0)
    try:
        apply_modifier(k.bpy, blades, 'BEVEL', width=0.012, segments=1, limit_method='ANGLE')
    except Exception as e:  # noqa: BLE001
        print('CUE spider: no bevel on the blades (%s)' % e)
    k.add('Crown', blades)
    # red rim rings where the crown meets the dome and the neck: the under-glow against the floor
    _torus(bm_e, (0, -7.56, 0), (0, 1, 0), 0.37, 0.028, segs=24, minor=8)
    _torus(bm_e, (0, -7.0, 0), (0, 1, 0), 0.33, 0.025, segs=24, minor=8)
    edges = k.mesh_object('BladeEdges', bm_e, ['Red'], smooth=False)
    apply_modifier(k.bpy, edges, 'SOLIDIFY', thickness=0.08, offset=0.0)
    k.add('Crown', edges)

    # bone weights: tents round each blade's angle (wrapping), each bone taking its absolute share
    # of what the bones before it left (skin_weights hands each bone a share of its parent's remainder)
    th = np.array(thetas)
    step = math.pi / 4

    def hats(V):
        V = np.asarray(V, float)
        a = np.arctan2(V[:, 0], -V[:, 2])
        a = np.where(a < 0, a + 2 * math.pi, a)
        diff = np.abs(((a[:, None] - th[None, :] + math.pi) % (2 * math.pi)) - math.pi)
        return np.clip(1 - diff / step, 0, 1)

    def bone_fn(i):
        def fn(V):
            H = hats(V)
            left = 1 - H[:, :i].sum(1)
            return np.where(left > 1e-6, H[:, i] / np.maximum(left, 1e-6), 0.0)
        return fn
    k.skins['Crown'] = {'root': 'Crown', 'meshes': [blades, edges],
                        'bones': {'Blade%d' % (i + 1): bone_fn(i) for i in range(SPIDER_BLADES)}}
    tipd = min(-pts[-1].y for pts, _ in curves)
    wide = max(math.hypot(p.x, p.z) for pts, _ in curves for p in pts)
    print('CUE spider crown: %d blades forward to d %.2f, out %.2f, dome to %.2f' % (SPIDER_BLADES, tipd, wide, SPIDER_DOME[-1][0]))


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
                    # an Aim joint's decor (the Broom's hat charm hanging under the binding) has the
                    # Aim room here too: it fades for the aiming owner like the overhang (remake, 13:10)
                    lim = r['AimRadius'] if aim and ob.name not in BODY_SHAFT.get(pid, ()) else env + r['ButtExtra']
                    if rad.max() > lim + 1e-4:
                        fail('too wide at the butt (d %.2f)' % dm, rad.max() - lim)
                    continue
                side = np.abs(sx).max()
                down = (-sz).max()
                up = sz.max()
                if side > env + r.get('Side', r['SideDown']) + 1e-4:
                    fail('too wide sideways (d %.2f)' % dm, side - env - r.get('Side', r['SideDown']))
                if down > env + r['SideDown'] + 1e-4:
                    fail('too deep downward (-Z, into the torso on a back) (d %.2f)' % dm, down - env - r['SideDown'])
                up_lim = r['UpMid'] if r['UpMidZone'][0] <= dm <= r['UpMidZone'][1] else r['SideDown']
                if up > env + up_lim + 1e-4:
                    fail('too tall upward (d %.2f)' % dm, up - env - up_lim)
    print('CUE check_envelope %s: OK (hand zones within %.3f of the envelope)' % (pid, worst))


# =============================================================================================
# Spider: the pocket piece (an orb web and a silk funnel; no spider)
# =============================================================================================

@piece
def spider_pocket(k):
    """The Spider's pocket finisher piece (brief 2.6; pocket frame, origin at the mouth, Z up):
    a silver Neon orb web lying flat (eight spokes, four rings) turning slowly, a funnel of six
    red threads rising from its rim to an apex 1.3 up (a red/white web, the fourth build), turning the other way so the threads
    twist, and a crimson Neon hourglass bead glowing at the apex. No spider. Threads and bead
    are Neon and thicker than a first cut (lab 10:25: ForceField threads 0.014 wide vanished
    from 8 studs, the bead read as a dot)."""
    import bmesh
    from mathutils import Vector, Matrix
    k.frame = 'pocket'
    k.material('Silk', 'Neon', '#E6EAF2', Transparency=0.08)
    k.material('Thread', 'Neon', '#FF2A44', Transparency=0.12)   # red threads on the white web (Justin 18:45: a red/white web)
    k.material('Crimson', 'Neon', '#C8102E')
    k.joint('Web', pivot=(0, 0, 0), motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': 24.0}],
            visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.35, 'Period': 0.8}])
    bm = bmesh.new()
    for i in range(8):
        a = 2 * math.pi * i / 8
        d = Vector((math.cos(a), math.sin(a), 0))
        _box(bm, d * 0.55, (0.022, 1.1, 0.022), (Vector((-math.sin(a), math.cos(a), 0)), d, Vector((0, 0, 1))))
    for Rr in (0.3, 0.55, 0.8, 1.05):
        _torus(bm, (0, 0, 0), (0, 0, 1), Rr, 0.015, segs=40, minor=6)
    k.add('Web', k.mesh_object('WebDisc', bm, ['Silk']))
    k.joint('Funnel', pivot=(0, 0, 0), parent='Web', motion=[{'Kind': 'Spin', 'Axis': (0, 0, 1), 'Rate': -48.0}])
    bm = bmesh.new()
    apex = Vector((0, 0, 1.3))
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        P = Vector((math.cos(a), math.sin(a), 0))
        d = apex - P
        ey = d.normalized()
        ex = ey.cross(Vector((0, 0, 1))).normalized()
        ez = ex.cross(ey)
        _box(bm, P + d / 2, (0.03, d.length, 0.03), (ex, ey, ez))
    k.add('Funnel', k.mesh_object('Threads', bm, ['Thread']))
    k.joint('Bead', pivot=(0, 0, 1.3), parent='Funnel', visual=[{'Kind': 'Glow', 'Min': 0.2, 'Max': 0.8, 'Period': 0.5}])
    bm = bmesh.new()
    _lathe(bm, [0.0, 0.05, 0.1, 0.15, 0.2], [0.001, 0.09, 0.035, 0.09, 0.001], 12, close=True)
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((0, 0, 1.2))) @ Matrix.Rotation(math.radians(-90), 4, 'X'), verts=bm.verts[:])
    k.add('Bead', k.mesh_object('BeadHourglass', bm, ['Crimson'], smooth=False))


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


# Parts the cue's inked outline Highlight must skip (Cues A's runtime key `Outline = false`,
# agreed 13:28): the Broom's straw, whose 200 strips would each get an ink stroke (a violet fuzz
# in the lobby, gate2/broom_remake_stand_v1_alphacards_lab.jpg).
NO_OUTLINE = {'witch_broom': ['Bristles_Bark']}


def patch_outline(pid):
    """Write `Outline: false` on the parts NO_OUTLINE names into the built piece.json."""
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


# =============================================================================================
# Previews: the body on its own (the plain cue hidden), from the views a gate wants
# =============================================================================================

VIEWS = {
    # (camera, target, lens mm): a three-quarter of the whole cue, the hand zones close, the butt end
    'witch_broom': [((4.4, -3.3, 2.4), (0, -3.7, 0.0), 24), ((1.3, -0.8, 0.75), (0, -1.4, 0.0), 50),
                    ((1.7, -8.4, 0.45), (0.1, -7.05, -0.05), 45), ((-1.4, -8.2, 0.9), (0, -7.0, 0.0), 45)],
    'black_cat': [((4.4, -3.3, 2.4), (0, -3.7, 0.0), 24), ((1.1, -3.3, 0.9), (0, -3.9, 0.0), 50),
                  ((1.6, -8.2, 0.5), (0, -7.1, 0.15), 45), ((-1.2, -8.0, 1.1), (0, -7.1, 0.15), 45)],
    'spider': [((4.4, -3.3, 2.4), (0, -3.7, 0.0), 24), ((1.0, -0.2, 0.6), (0, -0.9, 0.0), 50),
               ((1.7, -8.3, 0.8), (0, -7.05, 0.12), 45), ((-1.3, -8.4, 1.0), (0, -7.05, 0.12), 45)],
    # pocket pieces sit at the origin of the preview (the pocket frame), Z up
    'witch_broom_pocket': [((2.6, -3.0, 2.2), (0, 0, 0.5), 35), ((0.0, -3.6, 0.9), (0, 0, 0.5), 40)],
    'black_cat_pocket': [((2.6, -3.0, 2.2), (0, 0, 0.8), 35), ((0.0, -3.6, 0.9), (0, 0, 0.8), 40)],
    'spider_pocket': [((2.6, -3.0, 2.2), (0, 0, 0.8), 35), ((0.0, -3.6, 0.9), (0, 0, 0.8), 40)],
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
# The aura decor piece of the Spider (designer, 2026-10-28 11:55: the five cues
# brought up to their concept cards and the Firework's level): ribbons and orbiters wrapping
# the cue, the Firework's way (narrow saturated Neon strips; see witch_broom_aura).
# =============================================================================================


def _flat(k, bm, ob_name, mat, thickness):
    ob = k.mesh_object(ob_name, bm, [mat])
    apply_modifier(k.bpy, ob, 'SOLIDIFY', thickness=thickness, offset=0.0)
    return ob


def _plane_polygon(bm, origin, u, v, pts, scale=1.0, about=(0.0, 0.0)):
    """One n-gon (concave allowed, ear-clipped) from 2D points in the plane (origin, u, v)."""
    import bmesh
    verts = []
    for (x, y) in pts:
        x = about[0] + (x - about[0]) * scale
        y = about[1] + (y - about[1]) * scale
        verts.append(bm.verts.new(origin + u * x + v * y))
    bm.faces.new(verts)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], ngon_method='EAR_CLIP')
    return bm



def _web_wheel(bm, c, u, v, r=0.32, spokes=8, rings=(0.11, 0.21, 0.31), w=0.011):
    """A spider web in the plane (c, u, v): spokes from the centre and polygon rings, thin quads."""
    from mathutils import Vector
    for j in range(spokes):
        a = 2 * math.pi * j / spokes
        dirn = u * math.cos(a) + v * math.sin(a)
        across = u * -math.sin(a) + v * math.cos(a)
        bm.faces.new((bm.verts.new(c + across * w), bm.verts.new(c - across * w),
                      bm.verts.new(c + dirn * r - across * w), bm.verts.new(c + dirn * r + across * w)))
    for rr in rings:
        pts = []
        for j in range(spokes):
            a = 2 * math.pi * j / spokes
            # a strand sags a little between the spokes: the rings are polygons, not circles
            pts.append(c + (u * math.cos(a) + v * math.sin(a)) * rr)
        for j in range(spokes):
            p, q = pts[j], pts[(j + 1) % spokes]
            d = (q - p).normalized()
            n = (u * d.dot(v) - v * d.dot(u)).normalized() if abs(d.dot(u)) + abs(d.dot(v)) > 0 else u
            n = Vector((0, 0, 0)) + (u * (-(q - p).dot(v)) + v * ((q - p).dot(u))).normalized()
            bm.faces.new((bm.verts.new(p + n * w), bm.verts.new(p - n * w), bm.verts.new(q - n * w), bm.verts.new(q + n * w)))
    return bm


@piece
def spider_aura(k):
    """Aura-only decoration of the Spider (hides with the aura), the third build (Justin,
    12:55: no ribbons on any cue, each cue its own hand-made effect; the concept C1b_spider.png
    rule, since overruled by Justin's 18:45 verdict: the body is the crown of legs). The fifth
    build (coordinator 19:08: no flat web discs, they read as stickers on the bright floor) keeps
    only the strands: four silk droplines hanging under the cue,
    each a thread crossed so it reads from every side with a dew bead at its end, swinging on
    two Sways, the beads breathing toward white. The hourglass charms of the third build are gone
    (the fourth build's gem is on the body). The live-spun strands between the cue's points are
    the skin's Silk beams. Lower effects keeps two droplines; the other two hide."""
    import bmesh
    from mathutils import Vector
    R = _radius()
    # Readability on the bright floor (coordinator 13:35): opaque Neon silk, wider web lines.
    k.material('Silk', 'Neon', SPIDER['silk'], Transparency=0.0)
    k.material('SilkSoft', 'Neon', SPIDER['silver_bright'], Transparency=0.05)
    k.material('Crimson', 'Neon', SPIDER['crimson'], Transparency=0.0)

    # Four silk droplines hanging under the cue: a thread (two crossed quads) with a dew bead
    # (a small diamond) at its end, swinging round the cue's axis and along it.
    # Robustness pass (17:55): the droplines sit from the forearm back and are short, so a cue
    # low over the cloth at a rail (tip at ball height, elevation 4-8 deg) keeps them out of the
    # table; a 0.62 line at d 1.2 went 0.4 into the cloth (gate2/spider_robust_rail_v4_lab.jpg).
    for i, (d, length, period, low) in enumerate(((2.9, 0.34, 1.7, None), (4.1, 0.42, 2.1, None), (5.2, 0.4, 1.9, 'hide'), (6.3, 0.46, 2.3, 'hide'))):
        name = 'Drop%d' % (i + 1)
        top = Vector((0, -d, -R(d) + 0.01))
        k.joint(name, pivot=tuple(top), aura=True, low=low,
                motion=[{'Kind': 'Sway', 'Axis': (0, 1, 0), 'Amp': 9.0, 'Period': period, 'Phase': 70 * i},
                        {'Kind': 'Sway', 'Axis': (1, 0, 0), 'Amp': 4.0, 'Period': period * 1.37, 'Phase': 40 * i}],
                visual=[{'Kind': 'Glow', 'Min': 0.0, 'Max': 0.5, 'Period': 1.3 + 0.2 * i, 'Phase': 90 * i}])
        bm = bmesh.new()
        q = top + Vector((0, 0, -length))
        for across in (Vector((0.018, 0, 0)), Vector((0, 0.018, 0))):
            bm.faces.new((bm.verts.new(top - across), bm.verts.new(q - across), bm.verts.new(q + across), bm.verts.new(top + across)))
        k.add(name, _flat(k, bm, name + 'Thread', 'SilkSoft', 0.014))
        bm = bmesh.new()
        c = q + Vector((0, 0, -0.06))
        r = 0.055
        tip_up, tip_dn = bm.verts.new(c + Vector((0, 0, r * 1.4))), bm.verts.new(c - Vector((0, 0, r * 1.4)))
        ring = [bm.verts.new(c + Vector((r * math.cos(2 * math.pi * j / 6), r * math.sin(2 * math.pi * j / 6), 0))) for j in range(6)]
        for j in range(6):
            bm.faces.new((tip_up, ring[j], ring[(j + 1) % 6]))
            bm.faces.new((tip_dn, ring[(j + 1) % 6], ring[j]))
        k.add(name, k.mesh_object(name + 'Bead', bm, ['Silk'], smooth=False))



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
    patch_outline(pid)
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
