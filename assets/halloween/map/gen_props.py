"""The Haunted Rooftop's meshes (Halloween 2026, hw-map lane; docs/prompts/HW_MAP_PROMPT.md 2.5
and 2.6): one .glb holding every prop, coloured from one small palette texture (one new image for
the whole event), uploaded once as a Model and loaded on the server with InsertService
(src/server/HalloweenMap/Assets.luau). Objects are named "<Prop>.<Piece>"; the code groups them
by the prop's name and keeps each piece where it sits relative to the others.

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/halloween/map/gen_props.py

Writes assets/halloween/map/HalloweenMap_props.glb, textures/palette.png and renders/*.png.

Pieces whose name ends in "Glow" are drawn Neon by the game (their palette colour is only for
the preview). Scale: 1 Blender metre = 1 stud. The front of a carved pumpkin faces Blender -Y
(Roblox -Z after the importer's half turn). Every prop sits on its own spot along X so the file
opens readable; the game re-centres each one.
"""

import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "blender", "abilities"))
import common  # noqa: E402

os.makedirs(os.path.join(HERE, "textures"), exist_ok=True)
os.makedirs(os.path.join(HERE, "renders"), exist_ok=True)

# The palette: 8 x 8 swatches of 8 px; a face takes its swatch's centre as its UV.
SWATCH = 8
GRID = 8
PALETTE = {
    "orange": "#FF7A1A",
    "groove": "#D45A12",
    "glow": "#FFC23A",
    "stem": "#4F6B24",
    "gold": "#FFC43C",
    "golddark": "#C8901E",
    "bark": "#2C2333",
    "barklight": "#44384C",
    "stone": "#8C899A",
    "stonedark": "#5E5B6C",
    "moss": "#4F6B4A",
    "candyorange": "#FF8A1E",
    "candypurple": "#9A46F0",
    "candywhite": "#FFF5EB",
    "black": "#17141D",
    "web": "#E8E4F2",
    "wire": "#26222C",
    "lantern": "#2A2430",
    "bush": "#3B2E2C",
    "soil": "#2E2228",
}
NAMES = list(PALETTE)


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def palette_image():
    size = SWATCH * GRID
    rgba = np.ones((size, size, 4), dtype=np.float32)
    for i, name in enumerate(NAMES):
        r, g, b = hexrgb(PALETTE[name])
        row, col = divmod(i, GRID)
        rgba[row * SWATCH:(row + 1) * SWATCH, col * SWATCH:(col + 1) * SWATCH, :3] = (r, g, b)
    return common.image_from_array("HalloweenPalette", rgba, os.path.join(HERE, "textures", "palette.png"))


def swatch_uv(name):
    i = NAMES.index(name)
    row, col = divmod(i, GRID)
    size = SWATCH * GRID
    u = (col * SWATCH + SWATCH / 2) / size
    v = 1 - (row * SWATCH + SWATCH / 2) / size  # Blender UV v runs up; image row 0 is the top
    return u, v


def paint(bm, faces, name):
    """Every loop of `faces` takes the swatch's centre."""
    uv = bm.loops.layers.uv.verify()
    u, v = swatch_uv(name)
    for f in faces:
        for loop in f.loops:
            loop[uv].uv = (u, v)


def new_object(name, bm, smooth=True, recalc=True):
    me = bpy.data.meshes.new(name)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    me.materials.append(MATERIAL)
    return obj


def tube(bm, points, radii, sides, name):
    """A tapered tube through `points` (Vectors) with `radii`, capped, painted `name`."""
    rings = []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        a = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
        n1 = d.cross(a).normalized()
        n2 = d.cross(n1).normalized()
        ring = []
        for k in range(sides):
            t = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + (n1 * math.cos(t) + n2 * math.sin(t)) * radii[i]))
        rings.append(ring)
    faces = []
    for a_ring, b_ring in zip(rings, rings[1:]):
        for k in range(sides):
            faces.append(bm.faces.new((a_ring[k], a_ring[(k + 1) % sides], b_ring[(k + 1) % sides], b_ring[k])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[-1]))
    paint(bm, faces, name)
    return faces


def ball(bm, centre, size, name, segments=8, rings=6):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=0.5)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(centre), verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    paint(bm, faces, name)
    return faces


def box(bm, centre, size, name):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(centre), verts=verts)
    faces = list({f for v in verts for f in v.link_faces})
    paint(bm, faces, name)
    return faces


def at(obj, x):
    obj.location.x += x
    return obj


# ---------------------------------------------------------------------------------------------
# The carved pumpkin (the King's head, the throne's back, the small pumpkins, the tables'
# corners): a ribbed shell with an angry grin cut through its front, and the cut's walls and
# floor as a separate Glow piece the game draws Neon. 2 studs wide, 1.64 tall, centred.
# ---------------------------------------------------------------------------------------------

def pumpkin(x):
    bm = bmesh.new()
    geom = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in geom["verts"]:
        phi = math.atan2(v.co.y, v.co.x)
        lobe = 0.93 + 0.07 * abs(math.cos(4 * phi)) ** 0.6
        v.co.x *= lobe
        v.co.y *= lobe
        v.co.z *= 0.82
        # flatten the top and bottom a little round the stem
        if abs(v.co.z) > 0.7:
            v.co.z *= 0.94
    paint(bm, bm.faces, "orange")
    shell = new_object("Pumpkin.Shell", bm)
    shell.data.materials.append(INNER)
    # The cutters: two angry eyes, a nose and a toothy grin, deep into the front (-Y).
    cut = bmesh.new()

    def prism(points2d):
        front = [cut.verts.new((px, -1.3, pz)) for px, pz in points2d]
        back = [cut.verts.new((px, -0.25, pz)) for px, pz in points2d]
        n = len(points2d)
        cut.faces.new(front)
        cut.faces.new(list(reversed(back)))
        for k in range(n):
            cut.faces.new((front[k], back[k], back[(k + 1) % n], front[(k + 1) % n]))

    for side in (-1, 1):
        # an angry eye: a triangle slanting down toward the nose
        prism([(side * 0.18, 0.12), (side * 0.62, 0.42), (side * 0.56, 0.08)])
    prism([(-0.08, -0.02), (0.08, -0.02), (0.0, 0.12)])
    grin = []
    teeth = 6
    for k in range(teeth * 2 + 1):  # the top edge: teeth hanging down
        t = k / (teeth * 2)
        gx = -0.62 + 1.24 * t
        gz = -0.2 - 0.12 * math.sin(math.pi * t) - (0.1 if k % 2 == 1 and 0 < k < teeth * 2 else 0)
        grin.append((gx, gz))
    for k in range(teeth * 2, -1, -1):  # the bottom edge: a deeper curve
        t = k / (teeth * 2)
        gx = -0.62 + 1.24 * t
        gz = -0.26 - 0.36 * math.sin(math.pi * t)
        grin.append((gx, gz))
    prism(grin)
    me = bpy.data.meshes.new("Cutter")
    bmesh.ops.recalc_face_normals(cut, faces=cut.faces)
    cut.to_mesh(me)
    cut.free()
    cutter = bpy.data.objects.new("Cutter", me)
    bpy.context.scene.collection.objects.link(cutter)
    me.materials.append(INNER)
    mod = shell.modifiers.new("Carve", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    try:
        mod.material_mode = "TRANSFER"
    except Exception:
        pass
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.modifier_apply(modifier="Carve")
    bpy.data.objects.remove(cutter, do_unlink=True)
    # The cut's faces (material 1) become the Glow piece, painted glow.
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    inner = [f for f in bm.faces if f.material_index == 1]
    paint(bm, inner, "glow")
    glow_bm = bmesh.new()
    vmap = {}
    for f in inner:
        vs = []
        for v in f.verts:
            if v not in vmap:
                vmap[v] = glow_bm.verts.new(v.co)
            vs.append(vmap[v])
        nf = glow_bm.faces.new(vs)
        uvl = glow_bm.loops.layers.uv.verify()
        u, vv = swatch_uv("glow")
        for loop in nf.loops:
            loop[uvl].uv = (u, vv)
    bmesh.ops.delete(bm, geom=inner, context="FACES_ONLY")
    # the stem
    stem_pts = [Vector((0, 0, 0.72)), Vector((0.02, 0, 0.92)), Vector((0.1, 0, 1.05))]
    tube(bm, stem_pts, [0.12, 0.09, 0.07], 6, "stem")
    for f in bm.faces:
        f.material_index = 0
    bm.to_mesh(shell.data)
    bm.free()
    shell.data.materials.pop(index=1)
    glow = new_object("Pumpkin.Glow", glow_bm, smooth=False)
    at(shell, x)
    at(glow, x)
    return [shell, glow]


def pumpkin_small(x):
    """A low-poly jack-o'-lantern in one piece (the tables' corners, four to a table): 12 ribs,
    its face laid on the shell's front (-Y) in the glow swatch instead of carved, so it is one
    MeshPart. Pumpkin's size (2 studs wide, 1.64 tall, centred). About 190 triangles."""
    from mathutils.bvhtree import BVHTree

    bm = bmesh.new()
    geom = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=1.0)
    for v in geom["verts"]:
        phi = math.atan2(v.co.y, v.co.x)
        lobe = 0.92 + 0.08 * abs(math.sin(3 * phi))
        v.co.x *= lobe
        v.co.y *= lobe
        v.co.z *= 0.82
    shell = list(bm.faces)
    paint(bm, shell, "orange")
    bmesh.ops.recalc_face_normals(bm, faces=shell)
    bm.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    stem = tube(bm, [Vector((0, 0, 0.74)), Vector((0.03, 0, 0.95)), Vector((0.1, 0, 1.06))], [0.13, 0.1, 0.07], 5, "stem")
    bmesh.ops.recalc_face_normals(bm, faces=stem)

    made = {}

    def on_front(px, pz):
        key = (round(px, 4), round(pz, 4))
        if key not in made:
            hit = tree.ray_cast(Vector((px, -2.0, pz)), Vector((0, 1, 0)))[0]
            y = hit.y if hit is not None else -0.9
            made[key] = bm.verts.new((px, y - 0.05, pz))
        return made[key]

    face = []

    def poly(points2d):
        f = bm.faces.new([on_front(px, pz) for px, pz in points2d])
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
        face.append(f)

    def mid(a, b):
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)

    def tri(a, b, c):
        """A face triangle cut in four, so its middle never sinks behind the shell's facets."""
        ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
        for t in ((a, ab, ca), (ab, b, bc), (ca, bc, c), (ab, bc, ca)):
            poly(list(t))

    for side in (-1, 1):
        tri((side * 0.18, 0.12), (side * 0.62, 0.42), (side * 0.56, 0.08))
    tri((-0.08, -0.02), (0.08, -0.02), (0.0, 0.12))
    cols = 6
    for k in range(cols):  # the grin in narrow columns and two rows, so each stays on the curve
        t0, t1 = k / cols, (k + 1) / cols
        x0, x1 = -0.6 + 1.2 * t0, -0.6 + 1.2 * t1
        top0, top1 = -0.18 - 0.1 * math.sin(math.pi * t0), -0.18 - 0.1 * math.sin(math.pi * t1)
        bot0, bot1 = -0.26 - 0.24 * math.sin(math.pi * t0), -0.26 - 0.24 * math.sin(math.pi * t1)
        mid0, mid1 = (top0 + bot0) / 2, (top1 + bot1) / 2
        poly([(x0, top0), (x0, mid0), (x1, mid1), (x1, top1)])
        poly([(x0, mid0), (x0, bot0), (x1, bot1), (x1, mid1)])
    paint(bm, face, "glow")
    obj = new_object("PumpkinSmall.Body", bm, recalc=False)
    return [at(obj, x)]


def trim_ring(x):
    """The tables' glowing trim (TableBuilder.addDecor): a thin band round the apron just under
    the rail line, at the table's own size (outside 18.24 x 10.24 studs, the body's footprint;
    0.04 thick, 0.08 tall), so it is one Neon MeshPart a table. The game colours it by kit."""
    bm = bmesh.new()
    ox, oy, t, h = 9.12, 5.12, 0.04, 0.08

    def rect(hx, hy, z):
        return [bm.verts.new(v) for v in ((-hx, -hy, z), (hx, -hy, z), (hx, hy, z), (-hx, hy, z))]

    ob, ot = rect(ox, oy, -h / 2), rect(ox, oy, h / 2)
    ib, it = rect(ox - t, oy - t, -h / 2), rect(ox - t, oy - t, h / 2)
    faces = []
    for k in range(4):
        j = (k + 1) % 4
        faces.append(bm.faces.new((ob[k], ob[j], ot[j], ot[k])))
        faces.append(bm.faces.new((ib[j], ib[k], it[k], it[j])))
        faces.append(bm.faces.new((ot[k], ot[j], it[j], it[k])))
        faces.append(bm.faces.new((ob[j], ob[k], ib[k], ib[j])))
    paint(bm, faces, "glow")
    obj = new_object("Trim.Glow", bm, smooth=False)
    return [at(obj, x)]


# ---------------------------------------------------------------------------------------------
# The King's crown: a gold band with five points, tilted by the game. 1.1 wide.
# ---------------------------------------------------------------------------------------------

def crown(x):
    bm = bmesh.new()
    n = 20
    r_out, r_in, h = 0.55, 0.47, 0.3
    outer_bot = [bm.verts.new((r_out * math.cos(2 * math.pi * k / n), r_out * math.sin(2 * math.pi * k / n), 0)) for k in range(n)]
    tops = []
    for k in range(n):
        a = 2 * math.pi * k / n
        spike = 0.32 if k % 4 == 0 else 0.0
        tops.append(h + spike)
    outer_top = [bm.verts.new((r_out * math.cos(2 * math.pi * k / n), r_out * math.sin(2 * math.pi * k / n), tops[k])) for k in range(n)]
    inner_top = [bm.verts.new((r_in * math.cos(2 * math.pi * k / n), r_in * math.sin(2 * math.pi * k / n), tops[k])) for k in range(n)]
    inner_bot = [bm.verts.new((r_in * math.cos(2 * math.pi * k / n), r_in * math.sin(2 * math.pi * k / n), 0)) for k in range(n)]
    faces = []
    for k in range(n):
        j = (k + 1) % n
        faces.append(bm.faces.new((outer_bot[k], outer_bot[j], outer_top[j], outer_top[k])))
        faces.append(bm.faces.new((inner_bot[j], inner_bot[k], inner_top[k], inner_top[j])))
        faces.append(bm.faces.new((outer_top[k], outer_top[j], inner_top[j], inner_top[k])))
        faces.append(bm.faces.new((inner_bot[k], inner_bot[j], outer_bot[j], outer_bot[k])))
    paint(bm, faces, "gold")
    # a darker rim round the base
    rim = tube(bm, [Vector((r_out + 0.02, 0, 0.05)), Vector((r_out + 0.02, 0, 0.06))], [0.0, 0.0], 3, "golddark")
    for f in rim:
        bm.faces.remove(f)
    obj = new_object("Crown.Band", bm, smooth=False)
    return [at(obj, x)]


# ---------------------------------------------------------------------------------------------
# The dead tree (replaces each palm, in its pot): a crooked trunk splitting into bare branches,
# three lanterns hanging from the branches (frames on the tree, glass as the Lanterns glow
# piece). About 14 studs tall at scale 1; <= 1,500 triangles.
# ---------------------------------------------------------------------------------------------

def dead_tree(x, seed=7):
    rng = random.Random(seed)
    bm = bmesh.new()
    hooks = []

    def branch(start, direction, length, radius, depth):
        pts, radii = [start], [radius]
        d = direction.normalized()
        p = start
        steps = 4
        for i in range(steps):
            d = (d + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(-0.1, 0.25)))).normalized()
            p = p + d * (length / steps)
            pts.append(p)
            radii.append(radius * (1 - (i + 1) / (steps + 1.2)))
        tube(bm, pts, radii, 6 if depth == 0 else 5 if depth == 1 else 4, "bark")
        if depth < 3:
            kids = 3 if depth == 0 else 2
            for k in range(kids):
                at_i = rng.randint(2, steps)
                base = pts[at_i]
                spread = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized()
                nd = (d * 0.55 + spread * 0.75 + Vector((0, 0, 0.35))).normalized()
                branch(base, nd, length * 0.62, radii[at_i] * 0.75, depth + 1)
        if depth >= 1:
            # a point part way along a branch (thick enough to hang from) is a lantern hook
            hooks.append(pts[2].copy())

    # the trunk: leaning a little, with a twist
    branch(Vector((0, 0, 0)), Vector((0.12, 0.05, 1)), 7.5, 0.6, 0)
    # three hanging lanterns, on branch points 6 to 11 studs up, as far apart as they come
    usable = [h for h in hooks if 6 <= h.z <= 11] or hooks
    chosen = [max(usable, key=lambda h: Vector((h.x, h.y)).length)]
    while len(chosen) < 3 and len(chosen) < len(usable):
        chosen.append(max(usable, key=lambda h: min((h - c).length for c in chosen)))
    glow_bm = bmesh.new()
    for h in chosen:
        wire_top, lantern_top = h, h - Vector((0, 0, 1.0))
        tube(bm, [wire_top, lantern_top], [0.03, 0.03], 3, "wire")
        box(bm, lantern_top - Vector((0, 0, 0.08)), (0.5, 0.5, 0.12), "lantern")  # cap
        box(bm, lantern_top - Vector((0, 0, 0.8)), (0.54, 0.54, 0.1), "lantern")  # base
        box(glow_bm, lantern_top - Vector((0, 0, 0.44)), (0.4, 0.4, 0.62), "glow")
    tree = new_object("DeadTree.Trunk", bm, smooth=True)
    glow = new_object("DeadTree.Glow", glow_bm, smooth=False)
    return [at(tree, x), at(glow, x)]


def tombstone(x):
    bm = bmesh.new()
    w, h, d = 1.6, 1.6, 0.35
    # the slab with a round top
    n = 10
    outline = [(-w / 2, 0), (w / 2, 0)]
    for k in range(n + 1):
        t = k / n
        a = math.pi * t
        outline.append((math.cos(a) * w / 2, h - w / 2 + math.sin(a) * w / 2))
    front = [bm.verts.new((px, -d / 2, pz)) for px, pz in outline]
    back = [bm.verts.new((px, d / 2, pz)) for px, pz in outline]
    faces = [bm.faces.new(front), bm.faces.new(list(reversed(back)))]
    m = len(outline)
    for k in range(m):
        j = (k + 1) % m
        faces.append(bm.faces.new((front[k], back[k], back[j], front[j])))
    paint(bm, faces, "stone")
    # a carved cross, a little proud of the face
    box(bm, (0, -d / 2 - 0.02, h * 0.6), (0.14, 0.06, 0.62), "stonedark")
    box(bm, (0, -d / 2 - 0.02, h * 0.72), (0.44, 0.06, 0.14), "stonedark")
    # a mound of soil at its foot
    ball(bm, (0, 0, 0.02), (w * 1.15, d * 3.2, 0.3), "soil", 10, 4)
    obj = new_object("Tombstone.Stone", bm, smooth=False)
    obj.rotation_euler = (math.radians(-4), 0, math.radians(5))
    return [at(obj, x)]


def strand(x):
    """String lights: 14 bulbs on a sagging wire, 20 studs long along X (the game stretches it)."""
    bm, glow_bm = bmesh.new(), bmesh.new()
    length, sag, bulbs = 20.0, 1.2, 14
    pts = []
    for k in range(25):
        t = k / 24
        pts.append(Vector((-length / 2 + length * t, 0, -sag * 4 * t * (1 - t))))
    tube(bm, pts, [0.04] * len(pts), 4, "wire")
    for k in range(bulbs):
        t = (k + 0.5) / bulbs
        p = Vector((-length / 2 + length * t, 0, -sag * 4 * t * (1 - t) - 0.22))
        ball(glow_bm, p, (0.28, 0.28, 0.38), "glow", 6, 4)
    wire = new_object("Strand.Wire", bm, smooth=False)
    glow = new_object("Strand.Glow", glow_bm, smooth=True)
    return [at(wire, x), at(glow, x)]


def bat(x):
    """A flat bat emblem (the tables' aprons): wings out, scalloped, facing -Y. 2.4 x 1.0."""
    bm = bmesh.new()
    pts = [(0, 0.28), (0.12, 0.42), (0.18, 0.3), (0.42, 0.36), (0.8, 0.5), (1.2, 0.3),
           (1.0, 0.1), (0.85, -0.05), (0.62, 0.05), (0.45, -0.12), (0.26, 0.0), (0.1, -0.3),
           (0, -0.4)]
    outline = pts + [(-px, pz) for px, pz in reversed(pts[1:-1])]
    d = 0.06
    front = [bm.verts.new((px, -d / 2, pz)) for px, pz in outline]
    back = [bm.verts.new((px, d / 2, pz)) for px, pz in outline]
    faces = []
    faces.extend(bmesh.ops.triangle_fill(bm, edges=[bm.edges.new((front[k], front[(k + 1) % len(front)])) for k in range(len(front))], use_beauty=True)["geom"])
    faces.extend(bmesh.ops.triangle_fill(bm, edges=[bm.edges.new((back[k], back[(k + 1) % len(back)])) for k in range(len(back))], use_beauty=True)["geom"])
    faces = [f for f in faces if isinstance(f, bmesh.types.BMFace)]
    m = len(outline)
    for k in range(m):
        j = (k + 1) % m
        faces.append(bm.faces.new((front[k], back[k], back[j], front[j])))
    paint(bm, faces, "black")
    obj = new_object("Bat.Body", bm, smooth=False)
    return [at(obj, x)]


def cobweb(x):
    """A corner cobweb: threads fanning from the corner (the origin) down and out across a
    quarter, sagging rings between them; thin flat strips, both faces. About 3 studs."""
    bm = bmesh.new()
    threads, rings, reach, wdt = 6, 5, 3.0, 0.035

    def strip(a, b):
        side = Vector((0, 1, 0)).cross((b - a).normalized()) * wdt
        v = [bm.verts.new(a - side), bm.verts.new(b - side), bm.verts.new(b + side), bm.verts.new(a + side)]
        f1 = bm.faces.new(v)
        f2 = bm.faces.new(list(reversed([bm.verts.new(p.co + Vector((0, 0.005, 0))) for p in v])))
        return [f1, f2]

    faces = []
    dirs = []
    for k in range(threads):
        a = math.radians(-90 + 90 * k / (threads - 1))
        dirs.append(Vector((math.cos(a), 0, math.sin(a))))
    for d in dirs:
        faces += strip(Vector((0, 0, 0)), d * reach)
    for r in range(1, rings + 1):
        rr = reach * r / (rings + 0.6)
        for k in range(threads - 1):
            a, b = dirs[k] * rr, dirs[k + 1] * rr
            mid = (a + b) / 2 * 0.86  # the sag toward the corner
            faces += strip(a, mid)
            faces += strip(mid, b)
    paint(bm, faces, "web")
    obj = new_object("Cobweb.Web", bm, smooth=False)
    return [at(obj, x)]


def candy(x, colour, name):
    """A wrapped candy: an oval sweet with a white stripe and a twist of wrapper each side."""
    bm = bmesh.new()
    ball(bm, (0, 0, 0), (1.0, 0.8, 0.8), colour, 12, 8)
    for side in (-1, 1):
        base = Vector((side * 0.45, 0, 0))
        tip = Vector((side * 0.95, 0, 0))
        verts_tip = [bm.verts.new(tip + Vector((0, math.cos(a) * 0.32, math.sin(a) * 0.32))) for a in [2 * math.pi * k / 6 for k in range(6)]]
        verts_base = [bm.verts.new(base + Vector((0, math.cos(a) * 0.08, math.sin(a) * 0.08))) for a in [2 * math.pi * k / 6 for k in range(6)]]
        fs = []
        for k in range(6):
            j = (k + 1) % 6
            fs.append(bm.faces.new((verts_base[k], verts_base[j], verts_tip[j], verts_tip[k])))
        fs.append(bm.faces.new(verts_tip if side > 0 else list(reversed(verts_tip))))
        paint(bm, fs, colour)
    ring = tube(bm, [Vector((-0.06, 0, 0)), Vector((0.06, 0, 0))], [0.415, 0.415], 12, "candywhite")
    obj = new_object(name, bm, smooth=True)
    return [at(obj, x)]


def bush(x, seed=3):
    """A dead bush for the spooky planters: a tuft of bare twigs. About 2 studs."""
    rng = random.Random(seed)
    bm = bmesh.new()
    for _ in range(9):
        d = Vector((rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), 1)).normalized()
        p0 = Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 0))
        p1 = p0 + d * rng.uniform(0.9, 1.4)
        p2 = p1 + (d + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.2))).normalized() * 0.6
        tube(bm, [p0, p1, p2], [0.07, 0.04, 0.015], 4, "bush")
    obj = new_object("Bush.Twigs", bm, smooth=False)
    return [at(obj, x)]


# ---------------------------------------------------------------------------------------------
# Merged dressings (HW_MAP_PROMPT 2.5's budget: one MeshPart each): a spooky planter's top and a
# pumpkin cluster, built from the props above and joined into one piece.
# ---------------------------------------------------------------------------------------------

def place(at, scale=1.0, yaw=0.0, tilt=(0.0, 0.0)):
    """The matrix that puts a prop's origin at `at`, turned `yaw` degrees about Z, tipped
    `tilt` degrees about X and Y, scaled."""
    return (Matrix.Translation(Vector(at)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
            @ Matrix.Rotation(math.radians(tilt[0]), 4, "X") @ Matrix.Rotation(math.radians(tilt[1]), 4, "Y")
            @ Matrix.Scale(scale, 4))


def merged(name, pieces):
    """One object from several props: `pieces` = [(make, matrix)], each make() returning its
    objects (made at the origin, then removed from the file)."""
    bm = bmesh.new()
    for make, matrix in pieces:
        objs = make()
        for obj in objs:
            n0 = len(bm.verts)
            bm.from_mesh(obj.data)
            bm.verts.ensure_lookup_table()
            bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts[n0:])
        for obj in objs:
            me = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            bpy.data.meshes.remove(me)
    return new_object(name, bm, smooth=False, recalc=False)


def lift(scale):
    """A small pumpkin's centre height when it sits on z = 0."""
    return 0.8 * scale


def pot_dressing(x):
    """A fern planter's top turned spooky (origin: the pot's top centre; a 4-stud pot, the game
    scales it to smaller ones): a dead bush behind, a jack-o'-lantern in front (-Y)."""
    obj = merged("PotDressing.Body", [
        (lambda: bush(0, seed=5), place((0.35, 0.45, -0.05))),
        (lambda: pumpkin_small(0), place((-0.55, -0.75, lift(0.55)), 0.55, yaw=-18)),
    ])
    return [at(obj, x)]


def bed_dressing(x):
    """A planter bed's top turned spooky (origin: the bed's top centre; the bed 16 long along X,
    3 deep): two leaning tombstones, two dead bushes, three jack-o'-lanterns facing -Y."""
    obj = merged("BedDressing.Body", [
        (lambda: tombstone(0), place((-4.4, 0.25, -0.05), 1.0, yaw=8, tilt=(-5, 4))),
        (lambda: tombstone(0), place((3.2, 0.3, -0.05), 0.9, yaw=-10, tilt=(-3, -5))),
        (lambda: bush(0, seed=3), place((-6.8, 0.35, -0.05))),
        (lambda: bush(0, seed=9), place((6.7, 0.3, -0.05), 1.1)),
        (lambda: pumpkin_small(0), place((-2.1, -0.65, lift(0.55)), 0.55, yaw=12)),
        (lambda: pumpkin_small(0), place((0.9, -0.75, lift(0.4)), 0.4, yaw=-20)),
        (lambda: pumpkin_small(0), place((5.1, -0.6, lift(0.48)), 0.48, yaw=6)),
    ])
    return [at(obj, x)]


def pumpkin_cluster(x):
    """Three jack-o'-lanterns of three sizes on the floor (origin: the cluster's foot)."""
    obj = merged("PumpkinCluster.Body", [
        (lambda: pumpkin_small(0), place((0, 0, lift(0.6)), 0.6)),
        (lambda: pumpkin_small(0), place((0.95, -0.4, lift(0.42)), 0.42, yaw=25)),
        (lambda: pumpkin_small(0), place((-0.8, -0.5, lift(0.3)), 0.3, yaw=-30)),
    ])
    return [at(obj, x)]


def main():
    common.clear_scene()
    global MATERIAL, INNER
    img = palette_image()
    MATERIAL = common.image_material("HalloweenPalette", img, roughness=0.7)
    INNER = bpy.data.materials.new("Inner")
    objects = []
    objects += pumpkin(0)
    objects += crown(4)
    objects += dead_tree(10)
    objects += tombstone(18)
    objects += strand(32)
    objects += bat(46)
    objects += cobweb(50)
    objects += candy(55, "candyorange", "CandyOrange.Sweet")
    objects += candy(58, "candypurple", "CandyPurple.Sweet")
    objects += bush(62)
    objects += pumpkin_small(66)
    objects += trim_ring(80)
    objects += pot_dressing(96)
    objects += bed_dressing(110)
    objects += pumpkin_cluster(122)
    for obj in objects:
        obj.data.materials.clear()
        obj.data.materials.append(MATERIAL)
    total = common.triangles(objects)
    for obj in objects:
        print("%-22s %5d tris" % (obj.name, common.triangles([obj])))
    print("total", total)
    path = os.path.join(HERE, "HalloweenMap_props.glb")
    common.export_glb(path, objects)
    print("wrote", os.path.relpath(path, ROOT))
    # previews
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.0
    sun_obj = bpy.data.objects.new("Sun", sun)
    sun_obj.rotation_euler = (math.radians(50), 0, math.radians(30))
    bpy.context.scene.collection.objects.link(sun_obj)
    for name, target, dist in (("pumpkin", (0, 0, 0), 4.5), ("tree", (10, 0, 6), 22), ("small", (50, 0, 0), 22),
                               ("pumpkin_small", (66, 0, 0), 4.5), ("pot_dressing", (96, 0, 1), 6),
                               ("bed_dressing", (110, 0, 1), 15), ("pumpkin_cluster", (122, 0, 0.6), 4)):
        common.render_preview(os.path.join(HERE, "renders", name + ".png"), size=512, target=target,
                              distance=dist, elevation=15, azimuth=20 if name != "pumpkin" else 15)


MATERIAL = None
INNER = None
main()
