"""Build our own lucky block models in headless Blender (designer, 2026-10-07).

One master block, built by script so it is exact and can be rebuilt: a cube core with raised
faces (a pixel "?", an 8-ball disc or a clock), inside a frame of thick bevelled edge bars. Frame
"B" has a chunky cube bulging out at each of the 8 corners (every block but Mystery); frame "C"
has thinner bars meeting flush (Mystery). A kind may add a ribbon, a topper (bow, crown, halo), a
cloud base and wings. The approved concept icons are in ~/Desktop/8ball-refs/lucky-blocks/.

Every piece is its own mesh with its own painted map (tools/luckyblock_textures.py), so it comes
into Roblox as its own MeshPart with its own SurfaceAppearance (tools/luckyblock_template.luau).

The rig: joint1 at the bottom centre, joint2 above it (the pack's names and heights, scaled to
our block); the block and its toppers are weighted to joint2, which the idle bobs and tilts.
Wings hang on their own bones, wingL and wingR (children of joint2), which the idle flaps
(tools/luckyblock_anims.luau).

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/luckyblock_build.py -- \
        --kind standard [--preview out.png] [--glb out.glb] [--view x,y,z]

1 Blender metre = 1 stud (docs/STUDIO_NOTES.md, "Models from Blender").
"""

import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------- shape

L = 4.66  # the block's edge in studs, as the pack's Standard block
H = L / 2

# Frame and face proportions, in block edges (L). Measured off the approved concept icons.
FRAME = {
    "B": {"Inset": 0.05, "Bar": 0.14, "Corner": 0.25, "Bevel": 0.016},  # corner cubes bulge out
    "C": {"Inset": 0.0, "Bar": 0.115, "Corner": None, "Bevel": 0.012},  # flush, thinner (designer)
}
CORE_INSET = 0.085  # the face panel sits this far inside the block's outer edge
GLYPH_CELL = 0.064  # one pixel of the "?"
GLYPH_RISE = 0.045  # how far the "?" stands off the face panel
RIBBON = {"Width": 0.15, "Thick": 0.03}  # the gift ribbon's band, over the frame
DISC = {"Radius": 0.25, "Rise": 0.05}  # an 8-ball disc or a clock on a face
BEVEL = {"Core": 0.02, "Glyph": 0.012}

# The chunky pixel question mark, top row first.
QUESTION = [
    ".####.",
    "##..##",
    "##..##",
    "...###",
    "..###.",
    "..##..",
    "......",
    "..##..",
]

# The joints, as the pack's Standard block: joint1 at the bottom, joint2 2.96 studs above it.
JOINT2_HEIGHT = 2.9647

SIDES = ["front", "right", "back", "left"]

# Each kind's recipe. Frame: "B" or "C". Faces: what stands on each face ("Question", "Disc"),
# Ribbon: a gift ribbon over the frame, Topper: "Bow", "Crown" or "Halo", Base: "Cloud",
# Wings: "Large" or "Small", GlyphRise: the "?" stands further out (over a ribbon).
KINDS = {
    "standard": {"Name": "StandardBlock", "Frame": "B"},
    "uncommon": {"Name": "UncommonBlock", "Frame": "B"},
    "rare": {"Name": "RareBlock", "Frame": "B"},
    "epic": {"Name": "EpicBlock", "Frame": "B"},
    "legendary": {"Name": "LegendaryBlock", "Frame": "B", "Wings": "Large"},
    "grandopening": {"Name": "GrandOpeningBlock", "Frame": "B", "Topper": "Crown"},
    "eightball": {
        "Name": "EightBallBlock",
        "Frame": "B",
        "Faces": {"front": "Disc", "right": "Disc", "back": "Disc", "left": "Disc", "top": "Question"},
    },
    "starter": {"Name": "StarterBlock", "Frame": "B", "Ribbon": True, "Topper": "Bow", "GlyphRise": 0.085},
    "gift": {
        "Name": "GiftBlock",
        "Frame": "B",
        "Ribbon": True,
        "Topper": "Bow",
        "GlyphRise": 0.085,
        "DiscRise": 0.1,
        "Faces": {"front": "Disc", "right": "Question", "back": "Question", "left": "Question"},
    },
    "mythic": {"Name": "MythicBlock", "Frame": "B", "Topper": "Halo", "Wings": "Large"},
    "sky": {"Name": "SkyBlock", "Frame": "B", "Base": "Cloud", "Wings": "Small"},
    "mystery": {"Name": "MysteryBlock", "Frame": "C"},
}
TEXTURES = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "luckyblocks", "build"
)

# --------------------------------------------------------------------------- mesh helpers


def clear():
    bpy.ops.wm.read_homefile(use_empty=True)


def link(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def box(name, center, size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    return link(name, bm)


def ellipsoid(name, radii, matrix=Matrix.Identity(4)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in bm.verts:
        v.co = matrix @ Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
    return link(name, bm)


def torus(name, major, minor, matrix=Matrix.Identity(4), segments=40, rings=12):
    """A ring in the XY plane around the origin, placed by `matrix`."""
    bm = bmesh.new()
    grid = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        row = []
        for j in range(rings):
            b = 2 * math.pi * j / rings
            r = major + minor * math.cos(b)
            co = Vector((r * math.cos(a), r * math.sin(a), minor * math.sin(b)))
            row.append(bm.verts.new(matrix @ co))
        grid.append(row)
    for i in range(segments):
        for j in range(rings):
            a, b = grid[i][j], grid[(i + 1) % segments][j]
            c, d = grid[(i + 1) % segments][(j + 1) % rings], grid[i][(j + 1) % rings]
            bm.faces.new([a, b, c, d])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return link(name, bm)


def cone(name, r1, r2, depth, matrix=Matrix.Identity(4), segments=40):
    """A cylinder (r1 == r2) or cone along Z, centred on the origin, placed by `matrix`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, segments=segments, radius1=r1, radius2=r2, depth=depth, matrix=matrix
    )
    return link(name, bm)


def apply_all(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def round_edges(obj, width, segments=3):
    mod = obj.modifiers.new("Round", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    mod.harden_normals = True
    apply_all(obj)
    return obj


def weld(obj):
    """Weld the boolean's seams. Its flat cuts are left alone (the bevel's angle limit skips
    them): dissolving them turned each face's ring of bars into one face with a hole, which the
    glb export filled with a triangle across the panel."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()


def union(name, parts, bevel):
    """Join boxes into one solid with the exact boolean, then round every hard edge."""
    base = parts[0]
    base.name = name
    if len(parts) > 1:
        col = bpy.data.collections.new(name + "_ops")
        bpy.context.scene.collection.children.link(col)
        for p in parts[1:]:
            bpy.context.scene.collection.objects.unlink(p)
            col.objects.link(p)
        mod = base.modifiers.new("Union", "BOOLEAN")
        mod.operation = "UNION"
        mod.operand_type = "COLLECTION"
        mod.collection = col
        mod.solver = "EXACT"
        apply_all(base)
        for p in list(col.objects):
            bpy.data.objects.remove(p)
        bpy.data.collections.remove(col)
    weld(base)
    return round_edges(base, bevel)


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


TURNS = {
    "front": Matrix.Identity(4),
    "right": Matrix.Rotation(math.radians(90), 4, "Z"),
    "back": Matrix.Rotation(math.radians(180), 4, "Z"),
    "left": Matrix.Rotation(math.radians(-90), 4, "Z"),
    "top": Matrix.Rotation(math.radians(90), 4, "X"),
    "bottom": Matrix.Rotation(math.radians(-90), 4, "X"),
}


def on_faces(name, make, faces):
    """Copies of a front-face piece (made by `make`) turned onto the named faces, joined."""
    out = []
    for f in faces:
        obj = make()
        obj.data.transform(TURNS[f])
        out.append(obj)
    return join(name, out)


# --------------------------------------------------------------------------- the block


def outer_of(style):
    return H - FRAME[style]["Inset"] * L


def frame(style):
    """The edge bars (and, for "B", the corner cubes as their own piece)."""
    f = FRAME[style]
    bar = f["Bar"] * L
    outer = outer_of(style)
    c = outer - bar / 2  # a bar's centre line, off each axis
    parts = []
    for axis in range(3):
        a, b = (axis + 1) % 3, (axis + 2) % 3
        for sa in (-1, 1):
            for sb in (-1, 1):
                center = [0.0, 0.0, 0.0]
                center[a], center[b] = sa * c, sb * c
                size = [bar, bar, bar]
                size[axis] = 2 * outer
                parts.append(box("bar", center, size))
    pieces = {"Frame": union("Frame", parts, f["Bevel"] * L)}
    if f["Corner"]:
        cs = f["Corner"] * L
        k = H - cs / 2
        cubes = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    cube = box("corner", (sx * k, sy * k, sz * k), (cs, cs, cs))
                    cubes.append(round_edges(cube, f["Bevel"] * L))
        pieces["Corners"] = join("Corners", cubes)
    return pieces


def core():
    s = 2 * (H - CORE_INSET * L)
    return union("Core", [box("core", (0, 0, 0), (s, s, s))], BEVEL["Core"] * L)


def glyph(rows, rise):
    """The pixel glyph on the front face (Blender -Y): its pixels as one flat outline, extruded."""
    cell = GLYPH_CELL * L
    face = H - CORE_INSET * L
    sink = 0.02 * L  # starts a little inside the panel so no gap shows
    w, h = len(rows[0]) * cell, len(rows) * cell
    bm = bmesh.new()
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch != "#":
                continue
            x0, z1 = -w / 2 + c * cell, h / 2 - r * cell
            corners = [(x0, z1 - cell), (x0 + cell, z1 - cell), (x0 + cell, z1), (x0, z1)]
            bm.faces.new([bm.verts.new((x, -face + sink, z)) for x, z in corners])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts, edges=bm.edges)
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=moved, vec=(0, -(rise * L + sink), 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return round_edges(link("Glyph", bm), BEVEL["Glyph"] * L, 2)


def disc(rise=DISC["Rise"]):
    """A raised disc on the front face (an 8-ball circle or a clock); its map paints the face."""
    r = DISC["Radius"] * L
    face = H - CORE_INSET * L
    depth = rise * L + 0.02 * L
    y = -(face + rise * L) + depth / 2
    m = Matrix.Translation((0, y, 0)) @ Matrix.Rotation(math.radians(90), 4, "X")
    return round_edges(cone("Disc", r, r, depth, m, 48), 0.012 * L, 2)


def ribbon(style):
    """A gift ribbon: a band down the middle of each side and a cross over the top."""
    w, t = RIBBON["Width"] * L, RIBBON["Thick"] * L
    o = outer_of(style) + t / 2
    parts = []
    for f in SIDES:
        band = box("band", (0, -o, 0), (w, t, 2 * o))
        band.data.transform(TURNS[f])
        parts.append(band)
    parts.append(box("top_x", (0, 0, o), (2 * o + t, w, t)))
    parts.append(box("top_y", (0, 0, o), (w, 2 * o + t, t)))
    return round_edges(join("Ribbon", parts), 0.008 * L, 2)


def bow():
    """Two loops, a round knot and two tails on the top."""
    top = outer_of("B") + RIBBON["Thick"] * L
    parts = []
    for side in (-1, 1):
        m = (
            Matrix.Translation((side * 0.19 * L, 0, top + 0.13 * L))
            @ Matrix.Rotation(math.radians(side * -25), 4, "Y")
            @ Matrix.Rotation(math.radians(90), 4, "X")
            @ Matrix.Diagonal((1.0, 0.72, 1.0, 1.0))
        )
        parts.append(torus("loop", 0.15 * L, 0.07 * L, m))
        tail = (
            Matrix.Translation((side * 0.12 * L, -0.16 * L, top + 0.03 * L))
            @ Matrix.Rotation(math.radians(side * 35), 4, "Z")
            @ Matrix.Rotation(math.radians(18), 4, "X")
        )
        parts.append(ellipsoid("tail", (0.08 * L, 0.22 * L, 0.022 * L), tail))
    parts.append(ellipsoid("knot", (0.095 * L, 0.095 * L, 0.085 * L), Matrix.Translation((0, 0, top + 0.09 * L))))
    return join("Topper", parts)


def crown():
    """A ring band with five ball-tipped points, on the top."""
    top = outer_of("B")
    parts = [cone("band", 0.31 * L, 0.31 * L, 0.15 * L, Matrix.Translation((0, 0, top + 0.08 * L)), 48)]
    hollow = cone("hole", 0.26 * L, 0.26 * L, 0.3 * L, Matrix.Translation((0, 0, top + 0.08 * L)), 48)
    mod = parts[0].modifiers.new("Hollow", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = hollow
    mod.solver = "EXACT"
    apply_all(parts[0])
    bpy.data.objects.remove(hollow)
    for i in range(5):
        a = 2 * math.pi * i / 5 + math.pi / 2
        x, y = 0.285 * L * math.cos(a), 0.285 * L * math.sin(a)
        m = Matrix.Translation((x, y, top + 0.26 * L))
        parts.append(cone("point", 0.11 * L, 0.02 * L, 0.22 * L, m, 16))
        parts.append(ellipsoid("ball", (0.06 * L,) * 3, Matrix.Translation((x, y, top + 0.39 * L))))
    return join("Topper", parts)


def halo():
    top = outer_of("B")
    m = Matrix.Translation((0, 0.04 * L, top + 0.4 * L)) @ Matrix.Rotation(math.radians(-12), 4, "X")
    return torus("Topper", 0.3 * L, 0.035 * L, m)


def cloud():
    """Soft puffs around the bottom of the block."""
    parts = []
    for i in range(12):
        a = 2 * math.pi * i / 12
        r = 0.58 * L + (0.04 * L if i % 2 else 0)
        size = 0.24 * L if i % 2 else 0.2 * L
        z = -H + (0.05 * L if i % 3 else 0.12 * L)
        parts.append(ellipsoid("puff", (size, size, size * 0.8), Matrix.Translation((r * math.cos(a), r * math.sin(a), z))))
    parts.append(ellipsoid("under", (0.62 * L, 0.62 * L, 0.14 * L), Matrix.Translation((0, 0, -H + 0.02 * L))))
    return join("Base", parts)


def wing(side, scale):
    """A fan of feathers from a hinge at the block's upper back edge; `side` -1 left, 1 right."""
    hinge = Vector((side * (H - 0.05 * L), 0.12 * L, 0.18 * L))
    rows = [  # (feathers, longest, shortest, lowest angle, highest angle, width)
        (9, 1.0, 0.5, -12, 72, 0.22),
        (7, 0.7, 0.42, -4, 76, 0.22),
        (5, 0.42, 0.3, 8, 80, 0.22),
    ]
    parts = []
    for row, (n, longest, shortest, lo, hi, width) in enumerate(rows):
        for i in range(n):
            t = i / max(1, n - 1)
            length = (shortest + (longest - shortest) * (1 - abs(t - 0.35) * 1.2)) * L * scale
            angle = math.radians(lo + (hi - lo) * t)
            turn = -angle if side > 0 else angle - math.pi
            m = (
                Matrix.Translation(hinge + Vector((0, -0.03 * L * row, 0)))
                @ Matrix.Rotation(math.radians(side * -14), 4, "Z")  # swept back a little
                @ Matrix.Rotation(turn, 4, "Y")
                @ Matrix.Translation((length / 2, 0, 0))
            )
            parts.append(ellipsoid("feather", (length / 2, 0.03 * L * scale, width * L * scale / 2), m))
    return join("WingL" if side < 0 else "WingR", parts), hinge


# --------------------------------------------------------------------------- materials, UVs, rig


def material(name, image_path, roughness=0.22, metallic=0.0):
    """One Principled material whose Base Colour is the piece's painted map (packed in the glb)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.image.pack()
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def box_uv(obj, half=H, center=(0.0, 0.0, 0.0)):
    """Each face shows the whole texture, upright as you look at it from outside. `half` is the
    half-width the texture spans around `center` (the block's for most pieces, the glyph's or
    the disc's own for those)."""
    cx, cy, cz = center
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            x, y, z = loop.vert.co
            x, y, z = x - cx, y - cy, z - cz
            if axis == 0:
                u, v = (y if n.x > 0 else -y), z
            elif axis == 1:
                u, v = (-x if n.y > 0 else x), z
            else:
                u, v = x, (y if n.z > 0 else -y)
            loop[uv].uv = ((u + half) / (2 * half), (v + half) / (2 * half))
    bm.to_mesh(obj.data)
    bm.free()


def face_uv(obj, half):
    """A piece repeated on several faces (a glyph or disc): each copy maps around its own face
    centre, so every copy shows the whole texture."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        c = face.calc_center_median()
        # Which block face this copy sits on: the axis it stands furthest out along. Every face
        # of the copy, its side walls too, is projected onto that block face.
        far = max(range(3), key=lambda i: abs(c[i]))
        sign = 1 if c[far] > 0 else -1
        for loop in face.loops:
            x, y, z = loop.vert.co
            if far == 0:
                u, v = (y if sign > 0 else -y), z
            elif far == 1:
                u, v = (-x if sign > 0 else x), z
            else:
                u, v = x, (y if sign > 0 else -y)
            loop[uv].uv = ((u + half) / (2 * half), (v + half) / (2 * half))
    bm.to_mesh(obj.data)
    bm.free()


def bounds_uv(obj):
    """Box map around the piece's own bounds (toppers, wings, the cloud)."""
    co = [v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    centre = (lo + hi) / 2
    half = max(hi - lo) / 2
    box_uv(obj, half, tuple(centre))


def rig(pieces, wings):
    """joint1 at the bottom centre, joint2 above it; every piece on joint2 but the wings, which
    hang on wingL and wingR at their hinges."""
    arm = bpy.data.armatures.new("Rig")
    root = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(root)
    bpy.context.view_layer.objects.active = root
    bpy.ops.object.mode_set(mode="EDIT")
    j1 = arm.edit_bones.new("joint1")
    j1.head, j1.tail = (0, 0, -H), (0, 0, -H + JOINT2_HEIGHT)
    j2 = arm.edit_bones.new("joint2")
    j2.head, j2.tail = (0, 0, -H + JOINT2_HEIGHT), (0, 0, H)
    j2.parent = j1
    for name, hinge in wings.items():
        bone = arm.edit_bones.new(name.replace("Wing", "wing"))
        side = -1 if name.endswith("L") else 1
        bone.head = hinge
        bone.tail = hinge + Vector((side * 0.3 * L, 0, 0))
        bone.parent = j2
    bpy.ops.object.mode_set(mode="OBJECT")
    for name, o in pieces.items():
        bone = name.replace("Wing", "wing") if name in wings else "joint2"
        group = o.vertex_groups.new(name=bone)
        group.add(range(len(o.data.vertices)), 1.0, "REPLACE")
        o.parent = root
        mod = o.modifiers.new("Rig", "ARMATURE")
        mod.object = root
    return root


def build(kind):
    recipe = KINDS[kind]
    style = recipe["Frame"]
    clear()
    pieces = frame(style)
    pieces["Core"] = core()
    faces = recipe.get("Faces") or {f: "Question" for f in SIDES}
    rise = recipe.get("GlyphRise", GLYPH_RISE)
    marks = [f for f, what in faces.items() if what == "Question"]
    discs = [f for f, what in faces.items() if what == "Disc"]
    if marks:
        pieces["Glyph"] = on_faces("Glyph", lambda: glyph(QUESTION, rise), marks)
    if discs:
        disc_rise = recipe.get("DiscRise", DISC["Rise"])
        pieces["Disc"] = on_faces("Disc", lambda: disc(disc_rise), discs)
    if recipe.get("Ribbon"):
        pieces["Ribbon"] = ribbon(style)
    topper = recipe.get("Topper")
    if topper:
        pieces["Topper"] = {"Bow": bow, "Crown": crown, "Halo": halo}[topper]()
    if recipe.get("Base") == "Cloud":
        pieces["Base"] = cloud()
    wings = {}
    if recipe.get("Wings"):
        scale = 1.0 if recipe["Wings"] == "Large" else 0.6
        for side in (-1, 1):
            obj, hinge = wing(side, scale)
            pieces[obj.name] = obj
            wings[obj.name] = hinge
    for key, obj in pieces.items():
        obj.name = obj.data.name = key
        if key == "Glyph":
            face_uv(obj, len(QUESTION) * GLYPH_CELL * L / 2)
        elif key == "Disc":
            face_uv(obj, DISC["Radius"] * L)
        elif key in ("Frame", "Corners", "Core", "Ribbon"):
            box_uv(obj)
        else:
            bounds_uv(obj)
        # The boolean leaves its operands' (empty) slots behind: one material per piece.
        obj.data.materials.clear()
        texture = "wings" if key.startswith("Wing") else key.lower()
        obj.data.materials.append(material(f"{kind}_{key}", os.path.join(TEXTURES, kind, texture + ".png")))
        for p in obj.data.polygons:
            p.material_index = 0
            p.use_smooth = True
    rig(pieces, wings)
    return pieces


# --------------------------------------------------------------------------- preview


def preview(path, view=(1.0, -1.0, 1.15)):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"  # keep the candy colours saturated
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.9, 0.93, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.55
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 85
    scene.collection.objects.link(cam)
    # The icons' three-quarter view: from the front-right, a little above.
    direction = Vector(view).normalized()
    cam.location = direction * 26
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", default="standard")
    parser.add_argument("--preview")
    parser.add_argument("--glb")
    parser.add_argument("--view", help="camera direction x,y,z (default the icons' three-quarter view)")
    args = parser.parse_args(argv)
    build(args.kind)
    if args.glb:
        os.makedirs(os.path.dirname(os.path.abspath(args.glb)), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=args.glb, export_format="GLB", export_skins=True, export_animations=False)
    if args.preview:
        view = tuple(float(v) for v in args.view.split(",")) if args.view else (1.0, -1.0, 1.15)
        preview(os.path.abspath(args.preview), view)
    print("luckyblock_build: built", args.kind)


main()
