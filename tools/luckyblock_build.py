"""Build our own lucky block models in headless Blender (designer, 2026-10-07).

One master block, built by script so it is exact and can be rebuilt: a cube core with a raised
pixel "?" on its faces, inside a frame of thick bevelled edge bars. Frame "B" has a chunky cube
bulging out at each of the 8 corners (every block but Mystery); frame "C" has the same bars
meeting flush (Mystery). The approved concept icons are in ~/Desktop/8ball-refs/lucky-blocks/.

The rig: joint1 at the bottom centre, joint2 above it (the pack's names and heights, scaled to
our block); the whole block is weighted to joint2, which the idle animation bobs and tilts.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/luckyblock_build.py -- \
        --kind standard [--preview out.png] [--glb out.glb]

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

# Each kind's frame; its painted maps come from tools/luckyblock_textures.py.
LOOKS = {
    "standard": {"Frame_style": "B"},
    "mystery": {"Frame_style": "C"},
}
TEXTURES = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "luckyblocks", "build")


def clear():
    bpy.ops.wm.read_homefile(use_empty=True)


def box(name, center, size):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


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
    merge_coplanar(base)
    mod = base.modifiers.new("Round", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    mod.harden_normals = True
    apply_all(base)
    return base


def apply_all(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def merge_coplanar(obj):
    """Weld the boolean's seams. Its flat cuts are left alone (the bevel's angle limit skips
    them): dissolving them turned each face's ring of bars into one face with a hole, which the
    glb export filled with a triangle across the panel."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.to_mesh(obj.data)
    bm.free()


def frame(style):
    f = FRAME[style]
    inset, bar, corner = f["Inset"] * L, f["Bar"] * L, f["Corner"]
    outer = H - inset  # the bars' outer faces
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
    if corner:
        cs = corner * L
        k = H - cs / 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    parts.append(box("corner", (sx * k, sy * k, sz * k), (cs, cs, cs)))
    return union("Frame", parts, f["Bevel"] * L)


def core():
    s = 2 * (H - CORE_INSET * L)
    return union("Core", [box("core", (0, 0, 0), (s, s, s))], BEVEL["Core"] * L)


def glyph(rows):
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
    bmesh.ops.translate(bm, verts=moved, vec=(0, -(GLYPH_RISE * L + sink), 0))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new("Glyph")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Glyph", mesh)
    bpy.context.scene.collection.objects.link(obj)
    mod = obj.modifiers.new("Round", "BEVEL")
    mod.width = BEVEL["Glyph"] * L
    mod.segments = 2
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(40)
    mod.harden_normals = True
    apply_all(obj)
    return obj


def on_faces(src, faces):
    """Copies of a front-face piece turned onto the named faces; the source is removed."""
    turns = {
        "front": Matrix.Identity(4),
        "right": Matrix.Rotation(math.radians(90), 4, "Z"),
        "back": Matrix.Rotation(math.radians(180), 4, "Z"),
        "left": Matrix.Rotation(math.radians(-90), 4, "Z"),
        "top": Matrix.Rotation(math.radians(90), 4, "X"),
        "bottom": Matrix.Rotation(math.radians(-90), 4, "X"),
    }
    out = []
    for f in faces:
        obj = src.copy()
        obj.data = src.data.copy()
        obj.data.transform(turns[f])
        bpy.context.scene.collection.objects.link(obj)
        out.append(obj)
    bpy.data.objects.remove(src)
    return join("Glyph", out)


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


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


def box_uv(obj, half=H):
    """Each face shows the whole texture, upright as you look at it from outside. `half` is the
    half-width the texture spans (the block's for most pieces, the glyph's own for the "?")."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for loop in face.loops:
            x, y, z = loop.vert.co
            if axis == 0:
                u, v = (y if n.x > 0 else -y), z
            elif axis == 1:
                u, v = (-x if n.y > 0 else x), z
            else:
                u, v = x, (y if n.z > 0 else -y)
            loop[uv].uv = ((u + half) / (2 * half), (v + half) / (2 * half))
    bm.to_mesh(obj.data)
    bm.free()


def rig(objs):
    """joint1 at the bottom centre, joint2 above it; every piece weighted to joint2."""
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
    bpy.ops.object.mode_set(mode="OBJECT")
    for o in objs:
        group = o.vertex_groups.new(name="joint2")
        group.add(range(len(o.data.vertices)), 1.0, "REPLACE")
        o.parent = root
        mod = o.modifiers.new("Rig", "ARMATURE")
        mod.object = root
    return root


def build(kind):
    look = LOOKS[kind]
    clear()
    pieces = {
        "Frame": frame(look["Frame_style"]),
        "Core": core(),
        "Glyph": on_faces(glyph(QUESTION), ["front", "right", "back", "left"]),
    }
    for key, obj in pieces.items():
        obj.name = obj.data.name = key
        box_uv(obj, len(QUESTION) * GLYPH_CELL * L / 2 if key == "Glyph" else H)
        # The boolean leaves its operands' (empty) slots behind: one material per piece.
        obj.data.materials.clear()
        obj.data.materials.append(material(f"{kind}_{key}", os.path.join(TEXTURES, kind, key.lower() + ".png")))
        for p in obj.data.polygons:
            p.material_index = 0
    for obj in pieces.values():
        for p in obj.data.polygons:
            p.use_smooth = True
    rig(list(pieces.values()))
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
    cam.location = direction * 21
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
