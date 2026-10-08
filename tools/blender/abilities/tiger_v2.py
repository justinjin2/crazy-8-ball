"""Guangdong Tiger v2: a skinned Bengal tiger from a Meshy image-to-3D mesh, a hand-built
quadruped armature, five procedural actions, exported as a skinned glb plus a JSON of every
bone's posed matrix per frame (the game drives the Bones itself; no Animation assets).

Source: source/tiger_v2_meshy.blend, made from assets/cue/models/tiger_v2/model.glb (Meshy
image-to-3D task 01a11bda-d3a4-744f-9911-a526af30e268 from ref/tiger_ref.png, polycount 30000,
2k textures; the download itself is gitignored).

Output (assets/abilities/GuangdongTiger/):
  tiger_v2.glb            one skinned mesh (TigerMesh) + armature (TigerRig), one material
                          with the 1024 base colour embedded, no animations
  tiger_v2_anims.json     per action: fps, frames, loop, per frame per bone the posed
                          armature-space matrix; per bone the rest matrix and parent
  tiger_v2.blend          the built scene (for a look; the script is the source of truth)
  textures/tiger_v2_basecolor.png
  renders/                stills and one contact sheet per action

Axes: the tiger faces Blender -Y, up +Z, feet at Z=0, centred on X, nose to tail base exactly
1.0 Blender unit (the runtime scales it).

Run headless (never through the live Blender MCP):
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/tiger_v2.py
Env: TIGER_STAGE=mesh stops after the mesh (prints cross-sections for placing bones);
     TIGER_NO_RENDER=1 skips the renders.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

OUT = common.asset_dir("GuangdongTiger")
# Meshy's full download stays local (gitignored, 14 MB with 2k PBR maps); the committed source is
# source/tiger_v2_meshy.blend: Meshy's mesh untouched (same vertex order) with only its base
# colour, at 1024. It is made from the download the first time, if missing.
MESHY_GLB = os.path.join(common.ROOT, "assets", "cue", "models", "tiger_v2", "model.glb")
SRC = os.path.join(OUT, "source", "tiger_v2_meshy.blend")
TEX_SIZE = 1024
TARGET_TRIS = 10000
STAGE = os.environ.get("TIGER_STAGE", "all")
NO_RENDER = os.environ.get("TIGER_NO_RENDER") == "1"
TAIL_BASE_MEASURED = 0.46
K_TAIL = 0.96  # nose to tail base in the measuring frame; set exactly in build_mesh


# ---------------------------------------------------------------- mesh

def leg_centres(co):
    """The four legs' XY centres from a horizontal slice just above the paws (tail excluded)."""
    zmin = co[:, 2].min()
    band = co[(co[:, 2] > zmin + 0.12) & (co[:, 2] < zmin + 0.2)]
    # The tail tip hangs low at the far +Y end; keep the slice to the body's span.
    ymin, ymax = co[:, 1].min(), co[:, 1].max()
    band = band[band[:, 1] < ymin + 0.82 * (ymax - ymin)]
    pts = band[:, :2]
    # 2-means on Y (front / hind), then 2-means on X within each.
    order = np.argsort(pts[:, 1])
    front, hind = pts[order[: len(pts) // 2]], pts[order[len(pts) // 2:]]
    for _ in range(20):
        c = np.array([front[:, 1].mean(), hind[:, 1].mean()])
        lab = np.abs(pts[:, 1, None] - c[None]).argmin(1)
        front, hind = pts[lab == 0], pts[lab == 1]
    out = []
    for grp in (front, hind):
        a, b = grp[grp[:, 0] < np.median(grp[:, 0])], grp[grp[:, 0] >= np.median(grp[:, 0])]
        for _ in range(20):
            c = np.array([a[:, 0].mean(), b[:, 0].mean()])
            lab = np.abs(grp[:, 0, None] - c[None]).argmin(1)
            a, b = grp[lab == 0], grp[lab == 1]
        out.append((a.mean(0), b.mean(0)))
    return out  # ((frontA, frontB), (hindA, hindB))


def ensure_source():
    if os.path.exists(SRC):
        return
    common.clear_scene()
    bpy.ops.import_scene.gltf(filepath=MESHY_GLB)
    obj = next(o for o in bpy.data.objects if o.type == "MESH")
    mat = obj.data.materials[0]
    tex = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"
               and any(lk.to_socket.name == "Base Color" for lk in n.outputs["Color"].links))
    img = tex.image
    img.scale(TEX_SIZE, TEX_SIZE)
    img.name = "MeshyBaseColor"
    img.pack()
    src_mat = common.image_material("MeshySource", img)
    obj.data.materials.clear()
    obj.data.materials.append(src_mat)
    obj.name = "TigerMeshSource"
    os.makedirs(os.path.dirname(SRC), exist_ok=True)
    bpy.data.libraries.write(SRC, {obj}, fake_user=True, compress=True)
    print("SOURCE written", SRC)


def build_mesh():
    ensure_source()
    common.clear_scene()
    with bpy.data.libraries.load(SRC, link=False) as (_src, dst):
        dst.objects = ["TigerMeshSource"]
    obj = dst.objects[0]
    bpy.context.scene.collection.objects.link(obj)
    obj.name = "TigerMesh"
    obj.data.name = "TigerMesh"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Weld the UV-seam splits so the skin deforms as one surface (UVs live on loops, so kept).
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(obj.data)
    bm.free()

    # Turn the body square: the line from the hind legs' middle to the front legs' middle
    # becomes -Y.
    co = np.array([v.co[:] for v in obj.data.vertices])
    (fa, fb), (ha, hb) = leg_centres(co)
    fmid, hmid = (fa + fb) / 2, (ha + hb) / 2
    d = fmid - hmid
    ang = -math.atan2(d[0], -d[1])  # turns d onto -Y
    obj.data.transform(Matrix.Rotation(ang, 4, "Z"))
    co = np.array([v.co[:] for v in obj.data.vertices])
    (fa, fb), (ha, hb) = leg_centres(co)
    xmid = (fa[0] + fb[0] + ha[0] + hb[0]) / 4
    obj.data.transform(Matrix.Translation((-xmid, 0, -co[:, 2].min())))
    co = np.array([v.co[:] for v in obj.data.vertices])

    # Scale: nose (min Y) to tail base = 1.0. The tail base is where the rump's cross-section
    # collapses to the tail's (measured on this mesh: see tail_base_y).
    nose_y = co[:, 1].min()
    tb = tail_base_y(co)
    s = 1.0 / (tb - nose_y)
    obj.data.transform(Matrix.Translation((0, -nose_y * s, 0)) @ Matrix.Scale(s, 4))
    co = np.array([v.co[:] for v in obj.data.vertices])
    # Nose at Y = -0.5 so the body's middle sits near the origin.
    obj.data.transform(Matrix.Translation((0, -0.5 - co[:, 1].min(), 0)))

    remove_whiskers(obj)
    straighten_head(obj)

    # tail_base_y lands just behind the rump; the tail visibly leaves the body at Y = 0.46 in
    # this frame (read off ortho renders). Scale so the nose (moved a little by the
    # straightening) to that point is exactly 1.0, nose at Y = -0.5. Every landmark below (J,
    # TAIL_LINE) was measured in the frame before this scale; P() converts.
    global K_TAIL
    co = np.array([v.co[:] for v in obj.data.vertices])
    K_TAIL = TAIL_BASE_MEASURED - co[:, 1].min()
    obj.data.transform(Matrix.Translation((0, 0.5, 0)) @ Matrix.Scale(1 / K_TAIL, 4)
                       @ Matrix.Translation((0, -TAIL_BASE_MEASURED, 0)))

    # Decimate to the triangle budget (the source is already triangles).
    tris = len(obj.data.polygons)
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = TARGET_TRIS / tris
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    for p in obj.data.polygons:
        p.use_smooth = True

    # One material: the base colour only, at 1024.
    mat_src = obj.data.materials[0]
    tex_node = next(n for n in mat_src.node_tree.nodes if n.type == "TEX_IMAGE"
                    and any(lk.to_socket.name == "Base Color" for lk in n.outputs["Color"].links))
    img = tex_node.image
    img.scale(TEX_SIZE, TEX_SIZE)
    path = os.path.join(OUT, "textures", "tiger_v2_basecolor.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    img.pack()
    img.name = "tiger_v2_basecolor"
    mat = common.image_material("TigerFur", img, roughness=0.8)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    # Drop Meshy's material and its 2k maps (metallic, roughness, normal): the game uses the
    # base colour only.
    for m in list(bpy.data.materials):
        if m is not mat:
            bpy.data.materials.remove(m)
    for im in list(bpy.data.images):
        if im is not img:
            bpy.data.images.remove(im)
    return obj


def straighten_head(obj, y_start=-0.16, y_full=-0.34, pivot_y=-0.2):
    """The reference's head looks toward the tiger's left; bend the neck (a turn about Z that
    ramps in from the shoulders to the head) so the nose sits on X = 0."""
    co = np.array([v.co[:] for v in obj.data.vertices])
    tip = co[co[:, 1] < co[:, 1].min() + 0.02]
    nose = tip.mean(0)
    full = -math.atan2(nose[0], pivot_y - nose[1])
    print("STRAIGHTEN nose x %.3f, turn %.1f deg" % (nose[0], math.degrees(full)))
    for v in obj.data.vertices:
        t = (y_start - v.co.y) / (y_start - y_full)
        if t <= 0:
            continue
        t = min(t, 1.0)
        w = t * t * (3 - 2 * t)
        rel = Vector((v.co.x, v.co.y - pivot_y, v.co.z))
        rel.rotate(Matrix.Rotation(full * w, 3, "Z"))
        v.co = Vector((rel.x, rel.y + pivot_y, rel.z))


def remove_whiskers(obj):
    """Meshy models the whiskers as paper-thin strips. They are below a pixel in the game and
    stretch into white spikes when the jaw opens, so every vertex thinner than 4 mm (a ray
    through the surface finds the far side that close) on the muzzle, below the eyes, goes."""
    from mathutils.bvhtree import BVHTree

    bvh = BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())
    y_max, z_max = P(0, -0.38, 0).y, P(0, 0, 0.47).z
    doomed = []
    for v in obj.data.vertices:
        if v.co.y < y_max and v.co.z < z_max:
            n = v.normal
            hit = bvh.ray_cast(v.co - n * 1e-4, -n, 0.2)
            if hit[0] is not None and hit[3] < 0.004:
                doomed.append(v.index)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed], context="VERTS")
    # Drop any crumbs the cut left floating.
    seen, parts = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        stack, comp = [v], []
        seen.add(v)
        while stack:
            a = stack.pop()
            comp.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b not in seen:
                    seen.add(b)
                    stack.append(b)
        parts.append(comp)
    parts.sort(key=len, reverse=True)
    crumbs = [v for comp in parts[1:] for v in comp]
    bmesh.ops.delete(bm, geom=crumbs, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    print("WHISKERS removed %d verts, %d crumb verts" % (len(doomed), len(crumbs)))


def tail_base_y(co):
    """The Y where the body ends and the tail begins: walking back from the hind legs, the
    first slice whose height span falls under 40% of the hips' span."""
    ys = np.linspace(co[:, 1].min(), co[:, 1].max(), 200)
    spans = []
    for y in ys:
        s = co[np.abs(co[:, 1] - y) < 0.01]
        spans.append((s[:, 2].max() - s[:, 2].min()) if len(s) else 0)
    spans = np.array(spans)
    (_, _), (ha, hb) = leg_centres(co)
    hip_y = (ha[1] + hb[1]) / 2
    i0 = int(np.searchsorted(ys, hip_y))
    # The hips' span: the top of the rump down to the hind paws, high everywhere near the legs.
    top = np.array([co[np.abs(co[:, 1] - y) < 0.01][:, 2].max() if spans[i] > 0 else 0
                    for i, y in enumerate(ys)])
    # Tail base: past the hind legs, where the slice no longer reaches the ground and its
    # top has dropped from the rump's.
    for i in range(i0, len(ys)):
        s = co[np.abs(co[:, 1] - ys[i]) < 0.01]
        if len(s) and s[:, 2].min() > 0.25 * top[i0] and spans[i] < 0.4 * spans[i0]:
            return ys[i]
    return ys[-1]


def print_sections(obj):
    co = np.array([v.co[:] for v in obj.data.vertices])
    print("BOUNDS", np.round(co.min(0), 3), np.round(co.max(0), 3), "TRIS", len(obj.data.polygons))
    print("LEGS", [np.round(p, 3) for pair in leg_centres(co) for p in pair])
    for y in np.arange(-0.5, co[:, 1].max() + 0.001, 0.04):
        s = co[np.abs(co[:, 1] - y) < 0.015]
        if len(s):
            print("SEC y %.2f n %4d x[%.3f %.3f] z[%.3f %.3f]" % (
                y, len(s), s[:, 0].min(), s[:, 0].max(), s[:, 2].min(), s[:, 2].max()))




# ---------------------------------------------------------------- renders

def setup_render(size=480):
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.35, 0.38, 0.42, 1)
    bg.inputs["Strength"].default_value = 0.8
    if "PreviewSun" not in bpy.data.objects:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
        sun.data.energy = 3.5
        sun.rotation_euler = Euler((math.radians(40), 0, math.radians(30)))
        scene.collection.objects.link(sun)
    if "PreviewCam" not in bpy.data.objects:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        scene.collection.objects.link(cam)
        scene.camera = cam
    return bpy.data.objects["PreviewCam"]


def render_view(path, azimuth, elevation, target=(0, 0.1, 0.3), distance=2.4, ortho=0.0):
    """azimuth 0 = from the tiger's front (-Y), 90 = from its left (+X)."""
    cam = setup_render()
    el, az = math.radians(elevation), math.radians(azimuth)
    tgt = Vector(target)
    cam.location = tgt + Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az),
                                 math.sin(el))) * distance
    common.look_at(cam, tgt)
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = 50
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def sheet(paths, out, cols):
    """Stitch same-size PNGs into a grid (Blender images, no PIL needed)."""
    ims = [bpy.data.images.load(p) for p in paths]
    w, h = ims[0].size
    rows = (len(ims) + cols - 1) // cols
    canvas = np.zeros((rows * h, cols * w, 4), np.float32)
    for i, im in enumerate(ims):
        px = np.array(im.pixels[:], np.float32).reshape(h, w, 4)[::-1]
        r, c = divmod(i, cols)
        canvas[r * h:(r + 1) * h, c * w:(c + 1) * w] = px
        bpy.data.images.remove(im)
    common.image_from_array("sheet_tmp", canvas, out)
    bpy.data.images.remove(bpy.data.images["sheet_tmp"])
    for p in paths:
        os.remove(p)


# ---------------------------------------------------------------- armature

def P(x, y, z):
    """A landmark measured before the final 1/K_TAIL scale, in the finished frame."""
    return Vector((x / K_TAIL, 0.5 - (TAIL_BASE_MEASURED - y) / K_TAIL, z / K_TAIL))


# name: (head, tail, parent). L = the tiger's own left = +X (it faces -Y).
J = {
    "Root": ((0, 0.34, 0), (0, 0.19, 0), None),
    "Hips": ((0, 0.36, 0.38), (0, 0.20, 0.40), "Root"),
    "Spine1": ((0, 0.20, 0.40), (0, 0.04, 0.42), "Hips"),
    "Spine2": ((0, 0.04, 0.42), (0, -0.10, 0.44), "Spine1"),
    "Chest": ((0, -0.10, 0.44), (0, -0.20, 0.46), "Spine2"),
    "Neck": ((0, -0.20, 0.46), (0, -0.32, 0.47), "Chest"),
    "Head": ((0, -0.32, 0.47), (0, -0.47, 0.46), "Neck"),
    "Jaw": ((0, -0.37, 0.418), (0, -0.475, 0.385), "Head"),
    "ShoulderL": ((0.08, -0.15, 0.40), (0.09, -0.10, 0.24), "Chest"),
    "ForearmL": ((0.09, -0.10, 0.24), (0.095, -0.14, 0.085), "ShoulderL"),
    "FrontPawL": ((0.095, -0.14, 0.085), (0.12, -0.245, 0.02), "ForearmL"),
    "ShoulderR": ((-0.08, -0.15, 0.40), (-0.09, -0.11, 0.24), "Chest"),
    "ForearmR": ((-0.09, -0.11, 0.24), (-0.098, -0.168, 0.085), "ShoulderR"),
    "FrontPawR": ((-0.098, -0.168, 0.085), (-0.105, -0.255, 0.02), "ForearmR"),
    "ThighL": ((0.075, 0.33, 0.38), (0.08, 0.31, 0.24), "Hips"),
    "ShinL": ((0.08, 0.31, 0.24), (0.08, 0.455, 0.14), "ThighL"),
    "HindPawL": ((0.08, 0.455, 0.14), (0.105, 0.39, 0.02), "ShinL"),
    "ThighR": ((-0.075, 0.33, 0.38), (-0.085, 0.28, 0.24), "Hips"),
    "ShinR": ((-0.085, 0.28, 0.24), (-0.088, 0.39, 0.14), "ThighR"),
    "HindPawR": ((-0.088, 0.39, 0.14), (-0.11, 0.29, 0.02), "ShinR"),
}
# The tail's centre line (sampled from cross-sections), cut into four equal lengths.
TAIL_LINE = [(0.0, 0.45, 0.40), (0.015, 0.53, 0.315), (0.041, 0.59, 0.24), (0.065, 0.65, 0.169),
             (0.093, 0.71, 0.125), (0.106, 0.77, 0.118), (0.107, 0.80, 0.118)]
LEGS = {
    # leg: upper, lower, paw, parent, knee bend (+1 forward, -1 back)
    "FL": ("ShoulderL", "ForearmL", "FrontPawL", "Chest", -1),
    "FR": ("ShoulderR", "ForearmR", "FrontPawR", "Chest", -1),
    "HL": ("ThighL", "ShinL", "HindPawL", "Hips", 1),
    "HR": ("ThighR", "ShinR", "HindPawR", "Hips", 1),
}
BONE_ORDER = ["Root", "Hips", "Spine1", "Spine2", "Chest", "Neck", "Head", "Jaw",
              "Tail1", "Tail2", "Tail3", "Tail4",
              "ShoulderL", "ForearmL", "FrontPawL", "ShoulderR", "ForearmR", "FrontPawR",
              "ThighL", "ShinL", "HindPawL", "ThighR", "ShinR", "HindPawR"]


def tail_joints():
    pts = [P(*p) for p in TAIL_LINE]
    seg = [(pts[i + 1] - pts[i]).length for i in range(len(pts) - 1)]
    total = sum(seg)
    out = [pts[0]]
    for k in range(1, 5):
        want, acc = total * k / 4, 0.0
        for i, s in enumerate(seg):
            if acc + s >= want - 1e-9:
                out.append(pts[i].lerp(pts[i + 1], (want - acc) / s))
                break
            acc += s
    return out


def build_armature(mesh):
    arm_data = bpy.data.armatures.new("TigerRig")
    arm = bpy.data.objects.new("TigerRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    spec = {k: (P(*h), P(*t), par) for k, (h, t, par) in J.items()}
    tj = tail_joints()
    for i in range(4):
        spec["Tail%d" % (i + 1)] = (tj[i], tj[i + 1], "Hips" if i == 0 else "Tail%d" % i)
    for name in BONE_ORDER:
        h, t, _ = spec[name]
        b = eb.new(name)
        b.head, b.tail = h, t
        d = (t - h).normalized()
        b.align_roll(Vector((1, 0, 0)).cross(d))  # every bone's X axis = the tiger's +X side
    for name in BONE_ORDER:
        par = spec[name][2]
        if par:
            eb[name].parent = eb[par]
            eb[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_data.bones["Root"].use_deform = False
    arm_data.display_type = "STICK"
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def smooth01(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def skin(mesh, arm):
    """Bone-heat weights, then region fixes, max 4 influences."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    names = [n for n in BONE_ORDER if n != "Root"]
    idx = {n: i for i, n in enumerate(names)}
    vgi = {mesh.vertex_groups[n].index: idx[n] for n in names if n in mesh.vertex_groups}
    nv = len(mesh.data.vertices)
    W = np.zeros((nv, len(names)))
    for v in mesh.data.vertices:
        for g in v.groups:
            if g.group in vgi:
                W[v.index, vgi[g.group]] = g.weight
    co = np.array([v.co[:] for v in mesh.data.vertices])
    # Back to the measured frame for the region rules (same numbers as J).
    x, y, z = co[:, 0] * K_TAIL, TAIL_BASE_MEASURED - (0.5 - co[:, 1]) * K_TAIL, co[:, 2] * K_TAIL
    print("SKIN unweighted before fixes:", int((W.sum(1) < 1e-6).sum()))

    def col(n):
        return W[:, idx[n]]

    for side, sgn in (("L", 1), ("R", -1)):
        front = ["Shoulder" + side, "Forearm" + side, "FrontPaw" + side]
        hind = ["Thigh" + side, "Shin" + side, "HindPaw" + side]
        other = 1 - smooth01(-0.005, 0.02, sgn * x)  # 1 on the wrong side of the midline
        body = smooth01(0.16, 0.2, z)  # above the paws and lower legs
        for n in front + hind:
            # No leg weight on the other side of the midline, nor along the midline's chest
            # and belly.
            W[:, idx[n]] *= 1 - np.maximum(other, body * (1 - smooth01(0.015, 0.05, sgn * x)))
        for n in front:
            # Front legs keep off the belly (behind the elbows) and the tail end.
            W[:, idx[n]] *= 1 - body * smooth01(-0.07, 0.02, y)
            W[:, idx[n]] *= 1 - smooth01(0.1, 0.2, y)
        for n in hind:
            W[:, idx[n]] *= 1 - body * (1 - smooth01(0.15, 0.25, y))
            W[:, idx[n]] *= 1 - smooth01(0.49, 0.53, y) * smooth01(0.16, 0.2, z)
        # Lower bones stay below the body.
        for n in ("Forearm" + side, "FrontPaw" + side, "Shin" + side, "HindPaw" + side):
            W[:, idx[n]] *= 1 - smooth01(0.26, 0.32, z)
        # The paws own the paws: below the wrist / hock every leg vertex is that leg's.
        for paw, lower, ylo, yhi in (("FrontPaw" + side, "Forearm" + side, -0.3, -0.05),
                                     ("HindPaw" + side, "Shin" + side, 0.25, 0.52)):
            sel = (sgn * x > 0.0) & (y > ylo) & (y < yhi) & (z < 0.07)
            W[sel] = 0
            W[sel, idx[paw]] = 1
    # Tail: only the tail and hips behind the rump; no tail weight on the body.
    tail = ["Tail1", "Tail2", "Tail3", "Tail4"]
    behind = smooth01(0.5, 0.56, y) * smooth01(0.06, 0.1, z)
    for n in names:
        if n not in tail and n != "Hips":
            W[:, idx[n]] *= 1 - behind
    for n in tail:
        W[:, idx[n]] *= smooth01(0.38, 0.46, y)
    # Jaw: everything under the mouth line in front of the hinge, nothing else.
    # The split runs just under the upper fangs' tips, along the lower lip.
    z_split = 0.399 + 0.08 * (y + 0.47)
    jaw = (smooth01(-0.35, -0.38, y) * (1 - smooth01(-0.003, 0.002, z - z_split))
           * (1 - smooth01(0.06, 0.085, np.abs(x))))
    W[:, idx["Jaw"]] = 0
    W = limit_and_normalise(W, 4) * (1 - jaw)[:, None]
    W[:, idx["Jaw"]] = jaw

    # Anything left empty takes its nearest bone.
    empty = W.sum(1) < 1e-4
    if empty.any():
        heads = {n: Vector(arm.data.bones[n].head_local) for n in names}
        tails = {n: Vector(arm.data.bones[n].tail_local) for n in names}
        for i in np.nonzero(empty)[0]:
            p = Vector(co[i])
            best = min(names, key=lambda n: (geometry_closest(p, heads[n], tails[n]) - p).length)
            W[i, idx[best]] = 1
    print("SKIN filled empty:", int(empty.sum()))

    # Keep the four largest, normalise, a little smoothing across edges, again.
    edges = np.array([e.vertices[:] for e in mesh.data.edges])
    for _ in range(4):
        acc = np.zeros_like(W)
        cnt = np.zeros(nv)
        np.add.at(acc, edges[:, 0], W[edges[:, 1]])
        np.add.at(acc, edges[:, 1], W[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1)
        np.add.at(cnt, edges[:, 1], 1)
        nb = acc / np.maximum(cnt, 1)[:, None]
        keep = (y < -0.34) | ((z < 0.07) & (y > -0.3))  # the jaw line and the paws stay crisp
        W = np.where(keep[:, None], W, 0.6 * W + 0.4 * nb)
    W = limit_and_normalise(W, 4)

    for vg in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(vg)
    groups = {n: mesh.vertex_groups.new(name=n) for n in names}
    for i in range(nv):
        for j in np.nonzero(W[i])[0]:
            groups[names[j]].add([int(i)], float(W[i, j]), "REPLACE")
    return W, names


def geometry_closest(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return a + ab * t


def limit_and_normalise(W, k):
    W = W.copy()
    if W.shape[1] > k:
        np.put_along_axis(W, np.argsort(W, 1)[:, :-k], 0, 1)
    W[W < 0.01] = 0
    s = W.sum(1, keepdims=True)
    return W / np.maximum(s, 1e-9)


# ---------------------------------------------------------------- posing

def update():
    bpy.context.view_layer.update()


class Poser:
    """Poses the rig in armature space. rot() turns a bone by an armature-space Euler (degrees;
    +X pitches a forward-pointing bone nose-down and swings a hanging leg back, +Z turns toward
    the tiger's left... see the Readme) on top of what its parents do; legs are placed by a
    two-bone IK solved here, so planted paws stay put."""

    def __init__(self, arm):
        self.arm = arm
        self.pb = arm.pose.bones
        self.rest = {b.name: b.matrix_local.copy() for b in arm.data.bones}

    def reset(self):
        for pb in self.pb:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.scale = (1, 1, 1)

    def rot(self, name, x=0.0, y=0.0, z=0.0, local_twist=0.0):
        mq = self.rest[name].to_quaternion()
        r = Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ").to_quaternion()
        q = mq.inverted() @ r @ mq
        if local_twist:
            q = q @ Quaternion((0, 1, 0), math.radians(local_twist))
        self.pb[name].rotation_quaternion = q

    def move(self, name, v):
        self.pb[name].location = self.rest[name].to_3x3().inverted() @ Vector(v)

    def set_abs(self, name, rot3, head=None):
        """Give a bone an armature-space orientation (3x3) at its current posed head."""
        pb = self.pb[name]
        m = rot3.to_4x4()
        m.translation = pb.head if head is None else head
        pb.matrix = m
        update()

    def rest_rot(self, name, pitch=0.0, yaw=0.0):
        r = Euler((math.radians(pitch), 0, math.radians(yaw)), "XYZ").to_matrix()
        return r @ self.rest[name].to_3x3()

    def aim(self, name, head, direction, side):
        y = direction.normalized()
        x = (side - side.dot(y) * y).normalized()
        z = x.cross(y)
        self.set_abs(name, Matrix((x, y, z)).transposed(), head)

    def leg(self, leg, target, paw_ground_pitch=0.0, paw_curl=0.0, paw_air=0.0):
        """Two-bone IK: the paw bone's head goes to `target` (armature space). The paw is flat
        to the ground (its rest orientation turned by paw_ground_pitch) blended by paw_air
        (0..1) toward the lower bone's frame curled by paw_curl."""
        up, lo, paw, parent, bend = LEGS[leg]
        par = self.pb[parent].matrix.to_3x3()
        fwd = par @ Vector((0, 1, 0))  # the parent bone points headward
        side = par @ Vector((1, 0, 0))
        root = self.pb[up].head.copy()
        l1, l2 = self.arm.data.bones[up].length, self.arm.data.bones[lo].length
        d = Vector(target) - root
        dist = min(max(d.length, abs(l1 - l2) + 1e-4), (l1 + l2) * 0.999)
        dn = d.normalized()
        a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        hint = fwd * bend
        b = (hint - hint.dot(dn) * dn)
        b = b.normalized() if b.length > 1e-6 else Vector((0, 0, 1))
        mid = root + dn * a + b * h
        end = root + dn * dist
        self.aim(up, root, mid - root, side)
        self.aim(lo, mid, end - mid, side)
        ground = self.rest_rot(paw, paw_ground_pitch)
        lo3 = self.pb[lo].matrix.to_3x3()
        rel = (lo3 @ self.rest[lo].to_3x3().inverted() @ self.rest[paw].to_3x3()
               @ Matrix.Rotation(math.radians(paw_curl), 3, "X"))
        q = ground.to_quaternion().slerp(rel.to_quaternion(), max(0.0, min(1.0, paw_air)))
        self.set_abs(paw, q.to_matrix(), end)

    def rest_target(self, leg):
        return self.rest[LEGS[leg][2]].translation.copy()

    def joint(self, name):
        return self.pb[name].head.copy()


# ---------------------------------------------------------------- animation

def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def track(keys, f, loop_len=None):
    """Catmull-Rom through (frame, value) keys; values may be numbers or tuples. With
    loop_len the keys wrap (the last key should not repeat the first)."""
    ks = sorted(keys)
    if loop_len:
        f = f % loop_len
        ext = [(k[0] - loop_len, k[1]) for k in ks[-2:]] + ks + [(k[0] + loop_len, k[1]) for k in ks[:2]]
    else:
        ext = [ks[0]] + ks + [ks[-1]]
        if f <= ks[0][0]:
            return ks[0][1]
        if f >= ks[-1][0]:
            return ks[-1][1]
    for i in range(1, len(ext) - 2):
        f1, f2 = ext[i][0], ext[i + 1][0]
        if f1 <= f <= f2:
            t = (f - f1) / (f2 - f1) if f2 > f1 else 0.0
            p0, p1, p2, p3 = ext[i - 1][1], ext[i][1], ext[i + 1][1], ext[i + 2][1]

            def cr(a, b, c, d):
                return 0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                              + (-a + 3 * b - 3 * c + d) * t * t * t)

            if isinstance(p1, (tuple, list)):
                return tuple(cr(a, b, c, d) for a, b, c, d in zip(p0, p1, p2, p3))
            return cr(p0, p1, p2, p3)
    return ext[-1][1]


def wave(f, n, phase=0.0, cycles=1.0):
    return math.sin(2 * math.pi * (cycles * f / n) + phase)


def tail_pose(po, pitch, yaw, curl=0.0):
    """pitch / yaw: per-bone lists (degrees), curl added on the last two."""
    for i in range(4):
        po.rot("Tail%d" % (i + 1), x=pitch[i] + (curl if i >= 2 else 0), z=yaw[i])


def head_level(po, pitch=0.0, yaw=0.0, roll=0.0):
    """Hold the head at an armature-space orientation (rest turned), whatever the spine does."""
    r = Euler((math.radians(pitch), math.radians(roll), math.radians(yaw)), "XYZ").to_matrix()
    po.set_abs("Head", r @ po.rest["Head"].to_3x3())


# Run: a rotary gallop. Stride per 16-frame cycle in Blender units (nose to tail base = 1):
# the game should move the tiger STRIDE * scale every cycle (24 fps) for planted paws.
RUN_FRAMES = 16
STRIDE = 1.2
# leg: (touchdown phase, stance share, swing lift)
GALLOP = {"HL": (0.00, 0.30, 0.09), "HR": (0.09, 0.30, 0.09),
          "FR": (0.44, 0.28, 0.11), "FL": (0.53, 0.28, 0.11)}


def pose_run(po, f):
    n = RUN_FRAMES
    ph = f / n
    flex = math.cos(2 * math.pi * (ph - 0.88))  # +1 gathered, -1 stretched out
    pitch = 6 * math.cos(2 * math.pi * (ph - 0.62))  # nose down while the fronts carry
    po.move("Hips", (0, 0, -0.05 + 0.022 * math.cos(4 * math.pi * (ph - 0.36))))
    po.rot("Hips", x=pitch - 7 * flex)
    po.rot("Spine1", x=5 * flex)
    po.rot("Spine2", x=5 * flex)
    po.rot("Chest", x=3 * flex)
    po.rot("Neck", x=-0.6 * pitch + 6)
    po.rot("Jaw", x=10 + 3 * wave(f, n, 1.0))
    tp = [22 + 10 * wave(f, n, -0.6 * i - 1.4) for i in range(4)]
    tail_pose(po, [tp[0], tp[1] - 8, tp[2] - 12, tp[3] - 14], [3 * wave(f, n, -0.7 * i) for i in range(4)])
    update()
    head_level(po, pitch=6 + 2.5 * math.cos(4 * math.pi * (ph - 0.1)))
    for leg, (t0, duty, lift) in GALLOP.items():
        rest = po.rest_target(leg)
        u = (ph - t0) % 1.0
        front = leg[0] == "F"
        reach = STRIDE * duty / 2
        y_mid = rest.y - 0.02
        if u < duty:
            s = u / duty
            y = y_mid - reach + 2 * reach * s
            z = rest.z
            air, ground_pitch = 0.0, (25 * ease((s - 0.6) / 0.4) if front else -20 * ease((s - 0.6) / 0.4))
        else:
            s = (u - duty) / (1 - duty)
            # Swing: the paw trails back and up first, then reaches far forward and drops.
            y = y_mid + reach - (2 * reach) * ease(s) + (0.05 if front else 0.04) * math.sin(math.pi * s)
            y -= 0.06 * math.sin(math.pi * ease(s)) * (1 if front else 0.5)
            z = rest.z + lift * math.sin(math.pi * s) ** 0.8
            air = math.sin(math.pi * min(1.0, s * 1.15)) ** 0.7
            ground_pitch = 0.0
        curl = 75 if front else -45
        po.leg(leg, Vector((rest.x, y, z)), paw_ground_pitch=ground_pitch, paw_curl=curl * air,
               paw_air=air)


POUNCE_FRAMES = 20


def pose_pounce(po, f):
    hz = track([(0, 0), (5, -0.08), (7, -0.07), (10, 0.10), (13, 0.15), (16, 0.10), (19, 0.02)], f)
    pitch = track([(0, 0), (5, 5), (7, 2), (9, -24), (12, -14), (15, 6), (17, 14), (19, 6)], f)
    flex = track([(0, 0), (5, 5), (8, -6), (12, -8), (16, 3), (19, 0)], f)
    po.move("Hips", (0, 0, hz))
    po.rot("Hips", x=pitch)
    for b in ("Spine1", "Spine2", "Chest"):
        po.rot(b, x=flex)
    po.rot("Neck", x=track([(0, 0), (5, 10), (9, 6), (13, 0), (17, 4), (19, 0)], f))
    po.rot("Jaw", x=track([(0, 2), (6, 6), (10, 26), (16, 32), (19, 18)], f))
    tail_lift = track([(0, 5), (5, -5), (9, 30), (14, 25), (19, 15)], f)
    lash = track([(0, 0), (4, 15), (7, -10), (19, 0)], f)
    tail_pose(po, [tail_lift, tail_lift * 0.6 - 5, tail_lift * 0.3 - 8, -10],
              [lash * 0.5, lash, lash * 1.2, lash * 1.4])
    update()
    head_level(po, pitch=track([(0, 0), (5, 6), (9, -8), (13, 2), (17, 14), (19, 8)], f))
    # Front paws: planted through the crouch, then reach out ahead (claws spread), then strike
    # down to the ground in front.
    for leg in ("FL", "FR"):
        rest = po.rest_target(leg)
        sh = po.joint(LEGS[leg][0])
        air = track([(0, 0), (6.5, 0), (9, 1), (16, 1), (17.5, 0), (19, 0)], f)
        # Beyond the leg's reach on purpose: the IK straightens the leg along the offset.
        off = track([(7, (0, -0.12, -0.30)), (9, (0, -0.36, -0.12)), (12, (0, -0.42, -0.02)),
                     (14, (0, -0.42, -0.14)), (16, (0, -0.36, -0.30)), (17.5, (0, -0.30, -0.36))],
                    f)
        land = rest + Vector((0, -0.12, 0))
        ground = rest.lerp(land, ease((f - 14) / 3))
        tgt = ground.lerp(sh + Vector(off) + Vector((rest.x - sh.x, 0, 0)), air)
        tgt.z = max(tgt.z, rest.z)
        curl = track([(7, 35), (9, 18), (13, 12), (15.5, 35), (17.5, 10)], f)
        po.leg(leg, tgt, paw_curl=curl * air, paw_air=air)
    # Hind paws: push off, trail out behind in the air, swing back under for the landing.
    for leg in ("HL", "HR"):
        rest = po.rest_target(leg)
        hip = po.joint(LEGS[leg][0])
        air = track([(0, 0), (8, 0), (10, 1), (16.5, 1), (19, 0)], f)
        off = track([(8, (0, 0.10, -0.26)), (11, (0, 0.24, -0.15)), (14, (0, 0.16, -0.22)),
                     (18, (0, -0.02, -0.26))], f)
        tgt = rest.lerp(hip + Vector(off) + Vector((rest.x - hip.x, 0, 0)), air)
        po.leg(leg, tgt, paw_curl=track([(8, 0), (11, 40), (16, -20)], f) * air, paw_air=air)


SWIPE_FRAMES = 20


def pose_swipe(po, f):
    pitch = track([(0, 0), (3, -26), (5, -38), (8, -33), (11, -38), (14, -33), (16, -22),
                   (18, -5), (19, 0)], f)
    po.move("Hips", (0, 0, track([(0, 0), (3, -0.04), (16, -0.04), (19, 0)], f)))
    po.rot("Hips", x=pitch)
    po.rot("Spine1", x=track([(0, 0), (5, -4), (16, -4), (19, 0)], f))
    # Twist about the spine: + drives the right shoulder forward and down (the right strike).
    twist = track([(0, 0), (5, -8), (7, 6), (9, 16), (11, -4), (13, -14), (15, -8), (19, 0)], f)
    po.rot("Spine2", local_twist=twist * 0.5)
    po.rot("Chest", local_twist=twist * 0.5)
    po.rot("Jaw", x=track([(0, 2), (4, 22), (9, 26), (14, 26), (19, 6)], f))
    lash = track([(0, 0), (5, -18), (9, 18), (13, -14), (17, 10), (19, 0)], f)
    tail_pose(po, [track([(0, 0), (5, 28), (16, 28), (19, 5)], f), 0, -6, -12],
              [lash * 0.4, lash * 0.8, lash, lash * 1.2])
    update()
    head_level(po, pitch=track([(0, 0), (5, 16), (8, 24), (11, 18), (14, 24), (19, 4)], f),
               yaw=twist * 0.3)
    # Paw targets as offsets from each shoulder (armature space): up = +Z, forward = -Y, the
    # tiger's left = +X. Targets past the leg's reach straighten it along the offset. The right
    # paw winds up out to its side, then rakes down and across to the left, near the cloth;
    # then the left paw does the mirror.
    keys = {
        "FR": [(2, (-0.02, -0.12, -0.22)), (4, (-0.06, -0.16, -0.06)), (6, (-0.08, -0.18, 0.06)),
               (7.5, (-0.04, -0.30, -0.14)), (9, (0.10, -0.22, -0.42)), (11, (0.02, -0.12, -0.26)),
               (13, (-0.02, -0.14, -0.24)), (16, (-0.02, -0.16, -0.30))],
        "FL": [(2, (0.02, -0.12, -0.22)), (6, (0.03, -0.14, -0.22)), (9, (0.06, -0.16, -0.06)),
               (11, (0.08, -0.18, 0.06)), (12.5, (0.04, -0.30, -0.14)), (14, (-0.10, -0.22, -0.42)),
               (16, (-0.02, -0.14, -0.28))],
    }
    curls = {"FR": [(0, 0), (5, -40), (7, -10), (9, 45), (12, 10), (19, 0)],
             "FL": [(0, 0), (9, 0), (11, -40), (12.5, -10), (14, 45), (16, 10), (19, 0)]}
    for leg in ("FR", "FL"):
        rest = po.rest_target(leg)
        sh = po.joint(LEGS[leg][0])
        air = track([(0, 0), (2, 1), (16, 1), (19, 0)], f)
        tgt = rest.lerp(sh + Vector(track(keys[leg], f)), air)
        po.leg(leg, tgt, paw_curl=track(curls[leg], f) * air, paw_air=air)
    for leg in ("HL", "HR"):
        po.leg(leg, po.rest_target(leg))


ROAR_FRAMES = 24


def pose_roar(po, f):
    po.move("Hips", (0, 0, track([(0, 0), (5, 0.012), (9, -0.02), (18, -0.02), (23, 0)], f)))
    po.rot("Hips", x=track([(0, 0), (5, -5), (9, 4), (18, 4), (23, 0)], f))
    po.rot("Spine2", x=track([(0, 0), (5, -3), (9, 2), (23, 0)], f))
    po.rot("Chest", x=track([(0, 0), (5, -4), (9, 3), (23, 0)], f))
    po.rot("Neck", x=track([(0, 0), (5, -16), (9, -6), (18, -8), (23, 0)], f))
    shake = 2.5 * math.sin(f * 2.4) * ease((f - 9) / 2) * (1 - ease((f - 17) / 3))
    po.rot("Head", x=track([(0, 0), (5, -14), (9, -24), (18, -20), (23, 0)], f), z=shake)
    po.rot("Jaw", x=track([(0, 1), (4, 8), (9, 40), (17, 37), (21, 8), (23, 1)], f))
    lash = track([(0, 0), (6, 16), (11, -14), (16, 12), (23, 0)], f)
    tl = track([(0, 0), (8, 22), (18, 22), (23, 0)], f)
    tail_pose(po, [tl, tl * 0.4, 0, -4], [lash * 0.4, lash * 0.8, lash, lash * 1.3])
    update()
    for leg in LEGS:
        po.leg(leg, po.rest_target(leg))


IDLE_FRAMES = 48


def pose_idle(po, f):
    n = IDLE_FRAMES
    b = wave(f, n)  # one slow breath per loop
    po.move("Hips", (0, 0, 0.003 * b))
    po.rot("Spine2", x=-0.8 * b)
    po.rot("Chest", x=-1.2 * b)
    po.rot("Neck", x=1.5 * wave(f, n, 0.8))
    po.rot("Head", x=2 * wave(f, n, 2.0, 2), z=7 * wave(f, n, -0.5))
    po.rot("Jaw", x=1.5 + 1.5 * wave(f, n, 0.3))
    tail_pose(po, [2 * wave(f, n, -0.4 * i) for i in range(4)],
              [8 * wave(f, n, -0.8 * i) * (1 + 0.2 * i) for i in range(4)],
              curl=-6 + 4 * wave(f, n, 1.5))
    update()
    for leg in LEGS:
        po.leg(leg, po.rest_target(leg))


ACTIONS = [
    ("Run", RUN_FRAMES, True, pose_run),
    ("Pounce", POUNCE_FRAMES, False, pose_pounce),
    ("Swipe", SWIPE_FRAMES, False, pose_swipe),
    ("Roar", ROAR_FRAMES, False, pose_roar),
    ("Idle", IDLE_FRAMES, True, pose_idle),
]


# ---------------------------------------------------------------- bake, export, renders

def mat12(m):
    return [round(m[r][c], 4) for r in range(3) for c in range(4)]


SHEET_FRAMES = {"Run": list(range(16)), "Pounce": list(range(20)), "Swipe": list(range(20)),
                "Roar": list(range(0, 24, 2)), "Idle": list(range(0, 48, 6))}
SHEET_VIEW = {"Run": (-75, 10), "Pounce": (-75, 10), "Swipe": (-35, 12), "Roar": (-40, 8),
              "Idle": (-50, 12)}
SHEET_COLS = {"Run": 8, "Pounce": 5, "Swipe": 5, "Roar": 6, "Idle": 4}


def ground_plane():
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.001))
    plane = bpy.context.object
    plane.name = "PreviewGround"
    mat = bpy.data.materials.new("PreviewGround")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.05, 0.22, 0.12, 1)  # pool cloth green
    plane.data.materials.append(mat)
    return plane


def bake(arm, po):
    renders = os.path.join(OUT, "renders")
    baked, tracks_all = {}, {}
    for name, n, loop, fn in ACTIONS:
        frames, tracks = [], {b: [] for b in BONE_ORDER}
        shots = []
        for f in range(n):
            po.reset()
            update()
            fn(po, f)
            update()
            pose = {}
            for b in BONE_ORDER:
                pb = arm.pose.bones[b]
                tracks[b].append(mat12(pb.matrix))
                pose[b] = (tuple(pb.location), tuple(pb.rotation_quaternion))
            frames.append(pose)
            if not NO_RENDER and f in SHEET_FRAMES[name]:
                p = os.path.join(renders, "_%s_%02d.png" % (name, f))
                az, el = SHEET_VIEW[name]
                render_view(p, az, el, target=(0, 0.05, 0.38), distance=3.0, ortho=1.75)
                shots.append(p)
        if shots:
            sheet(shots, os.path.join(renders, "anim_%s.png" % name), SHEET_COLS[name])
        baked[name] = frames
        tracks_all[name] = {"fps": 24, "frames": n, "loop": loop, "poses": tracks}
        print("BAKED", name, n)
    po.reset()
    update()
    return baked, tracks_all


def write_actions(arm, baked):
    bpy.context.scene.render.fps = 24
    arm.animation_data_create()
    for name, frames in baked.items():
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        arm.animation_data.action = act
        for f, pose in enumerate(frames):
            for b, (loc, q) in pose.items():
                pb = arm.pose.bones[b]
                pb.location = loc
                pb.rotation_quaternion = q
                pb.keyframe_insert("location", frame=f, group=b)
                pb.keyframe_insert("rotation_quaternion", frame=f, group=b)
    arm.animation_data.action = None


def write_json(arm, tracks_all):
    bones = {}
    for name in BONE_ORDER:
        b = arm.data.bones[name]
        bones[name] = {"parent": b.parent.name if b.parent else None,
                       "rest": mat12(b.matrix_local), "length": round(b.length, 4)}
    out = {
        "version": 1,
        "source": "tools/blender/abilities/tiger_v2.py",
        "units": "Blender units (1 = 1 stud before the runtime scale); nose to tail base = 1.0",
        "axes": "Blender armature space: the tiger faces -Y, up is +Z, its left is +X",
        "matrixLayout": "12 numbers, row-major 3x4: r00 r01 r02 tx r10 r11 r12 ty r20 r21 r22 tz;"
                        " columns of the 3x3 are the bone's X, Y (along the bone), Z axes",
        "armatureWorld": [round(arm.matrix_world[r][c], 4) for r in range(4) for c in range(4)],
        "boneOrder": BONE_ORDER,
        "bones": bones,
        "run": {"stridePerCycle": STRIDE,
                "note": "move the tiger forward STRIDE * scale per Run cycle for planted paws"},
        "actions": tracks_all,
    }
    path = os.path.join(OUT, "tiger_v2_anims.json")
    with open(path, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print("JSON", path, os.path.getsize(path))


def export(mesh, arm):
    arm.data.pose_position = "REST"
    update()
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(OUT, "tiger_v2.glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False,
        export_yup=True, export_image_format="AUTO", export_materials="EXPORT",
        export_skins=True, export_animations=False, export_def_bones=False,
        export_morph=False)
    arm.data.pose_position = "POSE"
    print("GLB", path, os.path.getsize(path))


def stills(po):
    renders = os.path.join(OUT, "renders")
    po.reset()
    update()
    shots = []
    for i, (az, el) in enumerate([(-55, 12), (90, 4), (25, 35)]):
        p = os.path.join(renders, "_still_%d.png" % i)
        render_view(p, az, el, target=(0, 0.08, 0.36), distance=8.0, ortho=1.5)
        shots.append(p)
    sheet(shots, os.path.join(renders, "tiger_v2_stills.png"), 3)


if __name__ == "__main__":
    mesh = build_mesh()
    print_sections(mesh)
    if STAGE == "mesh":
        sys.exit(0)
    arm = build_armature(mesh)
    skin(mesh, arm)
    po = Poser(arm)
    plane = None
    if not NO_RENDER:
        plane = ground_plane()
        stills(po)
    baked, tracks_all = bake(arm, po)
    write_actions(arm, baked)
    write_json(arm, tracks_all)
    if plane is not None:
        bpy.data.objects.remove(plane, do_unlink=True)
    for o in list(bpy.data.objects):
        if o.name.startswith("Preview"):
            bpy.data.objects.remove(o, do_unlink=True)
    print("TRIS", common.triangles([mesh]), "VERTS", len(mesh.data.vertices))
    export(mesh, arm)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 next to it
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "tiger_v2.blend"))
