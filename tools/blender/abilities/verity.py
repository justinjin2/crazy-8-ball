"""Verity: the smiley cue-ball skin and the rigged Verity monster (headless Blender 5.2).

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        --python tools/blender/abilities/verity.py [-- ball|monster|renders ...]

With no step every step runs. Outputs go to assets/abilities/Verity/ (see its Readme.md).

ball     verity_ball_plush.png (the plush smiley, 2026-10-08; verity_ball.png was the first, flat
         smiley): a 1024 x 512 equirectangular map for assets/balls/ball_sphere.obj
         (tools/gen_ball_mesh.py: u = 0.5 at mesh +X, u grows towards +Z, v = 1 at +Y). The face
         is drawn twice, centred on mesh -Z (u = 0.25) and +Z (u = 0.75), where tex_<n>.png has
         its number discs, so a ball at rest (identity rotation) shows it like a number. It is
         painted in the face's own orthographic view, so it reads round, not stretched. The face
         is left-right symmetric, which matters: this UV wrap reads mirrored from outside (a "2"
         on tex_2 shows backwards in Blender), and a symmetric face does not care.
monster  verity_monster.glb + verity_anims.json from the Meshy rig and clips in
         assets/cue/models/verity_monster/ (tools/meshy_generate.py, tools/meshy_rig.py). One
         mesh, one material (base colour at 1024 px), decimated to TARGET_TRIS, facing Blender
         -Y, feet at Z = 0, centred, exactly 1.0 unit tall, at most 4 bone influences.
renders  the ball, the monster from three sides and one contact sheet per action.

verity_anims.json, all matrices 12 numbers: the 3x3 rotation row-major, then the translation.
    armature: {name, world}            the armature object's world matrix (identity here)
    bones: [{name, parent, rest}]      parent first; rest = bone.matrix_local (armature space)
    actions: [{name, source, fps, frames, loop, tracks: {bone: [matrix per frame]}}]
             tracks hold pose_bone.matrix (posed, armature space), sampled at FPS.
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402

OUT = common.asset_dir("Verity")
RENDERS = os.path.join(OUT, "renders")
MESHY = os.path.join(common.ROOT, "assets", "cue", "models", "verity_monster")
BALL_OBJ = os.path.join(common.ROOT, "assets", "balls", "ball_sphere.obj")

# ----------------------------------------------------------------------------- the ball

# The armed Verity ball (the designer's second round, 2026-10-08, "needs to look exactly like
# this": a plush smiley toy ball): a bright warm yellow plush (fine fibre noise, a little lighter
# on top), two small black upright oval eyes and a wide embroidered grin, a thick black outline
# (a crescent, widest in the middle, a short black tick across each corner) round two rows of
# white teeth (the upper row taller), each tooth parted by a thin black line. Drawn in the face's
# own orthographic view (unit = the ball's radius; a across, b up), measured off the reference.
BALL_W, BALL_H, SS = 1024, 512, 3
PLUSH = (250, 211, 30)  # the plush's yellow
PLUSH_TOP = (255, 224, 70)  # toward the top
PLUSH_LOW = (238, 190, 16)  # toward the bottom
INK = (17, 14, 12)
TOOTH = (250, 250, 246)
TOOTH_SHADE = (196, 194, 186)  # a tooth's edges (the embroidery's puff)
EYE = {"x": 0.345, "y": 0.247, "rx": 0.08, "ry": 0.153}  # two upright ovals
# The mouth: the outline's outer edge is a circle along the top (TOP_C, TOP_R) and a rounded
# ellipse below (a superellipse, LOW_*), ending at each corner in a short upright stem (STEM)
# under a bar (TICK); OUTLINE thick; the bite line between the rows a third circle. The rows'
# parting lines cross the middle of their row at these places (the upper row parted down the
# middle between two big front teeth, the lower with a tooth there). In the middle they lean
# as rays from a point far below (FAN_C); toward the corners they turn square across the row.
TOP_C, TOP_R = 0.669, 0.953  # the top edge: lowest (-0.284) in the middle...
TOP_LIFT = (0.05, 0.5, 0.68)  # ...turning up this much more between these a, into the stem
LOW_C, LOW_A, LOW_B, LOW_N = -0.07, 0.7075, 0.606, 2.1  # the bottom edge: lowest -0.676
BITE_C, BITE_R = 0.313, 0.805  # the bite line: lowest -0.492, the upper row the taller
OUTLINE = 0.056  # the outline's thickness in the middle...
OUTLINE_CORNER = (0.034, 0.25, 0.65)  # ...thinning to this toward the corners (between these a)
BITE_HALF = 0.0125  # half the bite line's thickness
UPPER_EDGES = (0.0, 0.205, 0.308, 0.407, 0.489, 0.555, 0.62)  # the upper row's parting lines (a)
LOWER_EDGES = (0.0675, 0.19, 0.287, 0.375, 0.447, 0.519, 0.578)  # the lower row's
UPPER_GAP_HALF, LOWER_GAP_HALF = 0.0065, 0.008  # half a line between two teeth
UPPER_ROUND, LOWER_ROUND = 0.022, 0.028  # the teeth's corner radii (the lower ones rounder)...
CORNER_ROUND = 0.6  # ...this share of it on the small teeth at the mouth's corners
FAN_C = (-1.8, -1.85)  # the upper and the lower row's parting lines' common point (b)
TURN = (0.35, 0.6)  # where along the mouth (a) the parting lines turn square across the row
STEM = (0.645, 0.712, -0.12, 0.07)  # each corner's stem: a from, a to, b from, b to
TICK = ((0.632, 0.093), (0.758, 0.056))  # each corner's bar, across the stem's top
TICK_HALF_W = 0.03


def _smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _blur(img, rx, ry):
    """Box blur of a 2-D array by (2rx+1) x (2ry+1), edges clamped (cumulative sums)."""
    out = img
    if rx > 0:
        p = np.pad(out, ((0, 0), (rx + 1, rx)), mode="edge")
        c = np.cumsum(p, axis=1)
        out = (c[:, 2 * rx + 1:] - c[:, :-2 * rx - 1]) / (2 * rx + 1)
    if ry > 0:
        p = np.pad(out, ((ry + 1, ry), (0, 0)), mode="edge")
        c = np.cumsum(p, axis=0)
        out = (c[2 * ry + 1:, :] - c[:-2 * ry - 1, :]) / (2 * ry + 1)
    return out


def _seg_dist(a, b, p0, p1):
    """Distance from (a, b) to the segment p0-p1."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    t = np.clip(((a - p0[0]) * dx + (b - p0[1]) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(a - (p0[0] + t * dx), b - (p0[1] + t * dy))


def _bite_b(a):
    return BITE_C - math.sqrt(BITE_R * BITE_R - a * a)


def _top(a):
    """The mouth's top edge at `a` (scalar or array): its height and its slope."""
    root = np.sqrt(np.maximum(TOP_R * TOP_R - a * a, 1e-6))
    lift, l0, l1 = TOP_LIFT
    t = np.clip((a - l0) / (l1 - l0), 0.0, 1.0)
    return TOP_C - root + lift * t * t * (3 - 2 * t), a / root + lift * 6 * t * (1 - t) / (l1 - l0)


def _outline(a):
    """The outline's thickness at `a`."""
    thin, a0, a1 = OUTLINE_CORNER
    return OUTLINE + (thin - OUTLINE) * _smoothstep(a0, a1, np.abs(a))


def _row_mid(a, upper):
    """The height of the middle of a row at `a` (between the outline's inner edge and the bite)."""
    if upper:
        top, slope = _top(a)
        edge = float(top - _outline(a) * math.sqrt(1 + slope * slope))
    else:
        t = max(1 - (abs(a) / LOW_A) ** LOW_N, 0.0)
        edge = LOW_C - LOW_B * t ** (1 / LOW_N) + float(_outline(a))
    return (edge + _bite_b(a)) / 2


def _row_side(a, b, upper, edges, gap_half):
    """Distance (face units, less the gap) from (a, b) to the nearest of a row's parting lines,
    each through the row's middle at one of `edges`, leaning as a ray from (0, FAN_C) below in
    the middle and turning square across the row (a ray from the bite circle's centre) toward
    the corners."""
    cy = FAN_C[0] if upper else FAN_C[1]
    near = np.full(a.shape, 9.0)
    for e in edges:
        m = _row_mid(e, upper)
        fan = math.atan2(e, m - cy)  # the line's lean from upright (+: out at the top)
        square = math.atan2(-e, BITE_C - m)
        w = float(_smoothstep(TURN[0], TURN[1], e))
        lean = fan * (1 - w) + square * w
        near = np.minimum(near, np.abs((a - e) * math.cos(lean) - (b - m) * math.sin(lean)))
    return near - gap_half


def plush_face(a, b):
    """The face at orthographic coords (a, b): (ink, tooth, shade) arrays, ink and tooth 0..1
    coverage (anti-aliased by the supersampling), shade 0..1 how near a tooth's edge."""
    a = np.abs(a)  # left-right symmetric (the UV wrap reads mirrored from outside)
    eye = ((a - EYE["x"]) / EYE["rx"]) ** 2 + ((b - EYE["y"]) / EYE["ry"]) ** 2 <= 1.0
    # Signed distance to the mouth's outer edge (negative inside): inside the rounded ellipse
    # (its level less one over the level's slope), below the top circle.
    qa, qb = np.abs(a / LOW_A), np.abs((b - LOW_C) / LOW_B)
    level = (qa ** LOW_N + qb ** LOW_N) ** (1 / LOW_N)
    slope = np.hypot(qa ** (LOW_N - 1) / LOW_A, qb ** (LOW_N - 1) / LOW_B) * np.maximum(level, 1e-6) ** (1 - LOW_N)
    sd_low = (level - 1) / np.maximum(slope, 1e-6)
    top, top_slope = _top(a)
    sd_top = (b - top) / np.sqrt(1 + top_slope * top_slope)
    mouth = np.maximum(sd_low, sd_top) <= 0.0
    to_edge = np.minimum(-sd_low, -sd_top) - _outline(a)  # inside the outline: > 0
    inner = to_edge >= 0.0
    d_bite = np.hypot(a, b - BITE_C)
    upper = d_bite < BITE_R  # inside the bite circle: the upper row
    bite = np.abs(d_bite - BITE_R) <= BITE_HALF
    side = np.where(upper, _row_side(a, b, True, UPPER_EDGES, UPPER_GAP_HALF),
                    _row_side(a, b, False, LOWER_EDGES, LOWER_GAP_HALF))
    gaps = side <= 0.0
    # The teeth are puffy: rounded at the corners, the lower ones most.
    to_bite = np.abs(d_bite - BITE_R) - BITE_HALF
    rr = np.where(upper, UPPER_ROUND, LOWER_ROUND) * (1 - (1 - CORNER_ROUND) * _smoothstep(0.35, 0.6, a))
    corner = np.zeros(a.shape, bool)
    for t in (to_bite, to_edge):
        near_corner = (side < rr) & (t < rr) & (side > 0) & (t > 0)
        corner |= near_corner & (np.hypot(rr - side, rr - t) > rr)
    # A tooth's edge distance: to its sides, the bite line and the outline.
    edge = np.minimum(np.minimum(side, to_bite), to_edge)
    tooth = inner & ~bite & ~gaps & ~corner
    shade = 1.0 - _smoothstep(0.0, 0.045, edge)
    tick = _seg_dist(a, b, TICK[0], TICK[1]) <= TICK_HALF_W
    tick |= (a >= STEM[0]) & (a <= STEM[1]) & (b >= STEM[2]) & (b <= STEM[3])
    ink = eye | (mouth & ~tooth) | tick
    return ink, tooth & ~tick, shade


def ball_texture():
    """verity_ball_plush.png: the plush smiley on the ball map (see the module docstring)."""
    w, h = BALL_W * SS, BALL_H * SS
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    lon, lat = np.meshgrid((u - 0.5) * 2 * math.pi, (0.5 - v) * math.pi)
    x, y, z = np.cos(lat) * np.cos(lon), np.sin(lat), np.cos(lat) * np.sin(lon)
    # The plush: yellow, lighter toward the top, darker toward the bottom.
    up = np.clip(y, 0, 1)[..., None]
    down = np.clip(-y, 0, 1)[..., None]
    rgb = (np.array(PLUSH, np.float32) * (1 - up - down) + np.array(PLUSH_TOP, np.float32) * up
           + np.array(PLUSH_LOW, np.float32) * down)
    ink = np.zeros(z.shape, np.float32)
    tooth = np.zeros(z.shape, np.float32)
    shade = np.zeros(z.shape, np.float32)
    for sign in (1.0, -1.0):  # +Z (u = 0.75) and -Z (u = 0.25)
        front = z * sign > 0.05
        i, t, s = plush_face(x, y)  # orthographic view along the face axis: (x, y)
        ink = np.where(front & i, 1.0, ink)
        tooth = np.where(front & t, 1.0, tooth)
        shade = np.where(front & t, s, shade)
    # Embroidery and fibres: fine noise, a little streaked along the fibres, and a soft mottle.
    rng = np.random.default_rng(7)
    fine = rng.standard_normal((h, w)).astype(np.float32)
    fibre = _blur(fine, 2 * SS, 0) * 0.6 + _blur(fine, 0, SS) * 0.4
    mottle = _blur(_blur(rng.standard_normal((h, w)).astype(np.float32), 12 * SS, 12 * SS), 0, 0)
    mottle /= max(float(np.abs(mottle).max()), 1e-6)
    lum = 1.0 + 0.06 * fibre / max(float(np.abs(fibre).std()) * 3, 1e-6) + 0.035 * mottle
    rgb = rgb * lum[..., None]
    teeth_rgb = (np.array(TOOTH, np.float32) * (1 - shade[..., None])
                 + np.array(TOOTH_SHADE, np.float32) * shade[..., None]) * (1 + 0.025 * fibre[..., None])
    ink_rgb = np.array(INK, np.float32) * (1 + 0.5 * np.clip(fibre[..., None], -1, 1))
    rgb = rgb * (1 - tooth[..., None]) + teeth_rgb * tooth[..., None]
    rgb = rgb * (1 - ink[..., None]) + ink_rgb * ink[..., None]
    rgb = np.clip(rgb, 0, 255)
    rgb = rgb.reshape(BALL_H, SS, BALL_W, SS, 3).mean(axis=(1, 3)) / 255.0
    rgba = np.concatenate([rgb, np.ones((BALL_H, BALL_W, 1), np.float32)], axis=2)
    return common.image_from_array("verity_ball_plush", rgba, os.path.join(OUT, "verity_ball_plush.png"))


def light_rig(energy=3.0):
    bpy.context.scene.view_settings.view_transform = "Standard"  # true colours, not AgX
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = energy
    sun.rotation_euler = (math.radians(40), math.radians(10), math.radians(25))
    bpy.context.scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = energy * 0.35
    fill.rotation_euler = (math.radians(70), 0, math.radians(200))
    bpy.context.scene.collection.objects.link(fill)


def step_ball():
    common.clear_scene()
    img = ball_texture()
    bpy.ops.wm.obj_import(filepath=BALL_OBJ)
    ball = bpy.context.selected_objects[0]
    ball.data.materials.clear()
    ball.data.materials.append(common.image_material("VerityBall", img, roughness=0.75))
    for p in ball.data.polygons:
        p.use_smooth = True
    light_rig()
    # Mesh +Z (u = 0.75) is Blender -Y after the OBJ import: azimuth 0 looks at it.
    for name, el, az, size, bg in (("ball_front", 0, 0, 512, (1, 1, 1, 1)),
                                   ("ball_shot", 35, 0, 512, (0.05, 0.25, 0.12, 1)),
                                   ("ball_side", 20, 70, 512, (0.05, 0.25, 0.12, 1)),
                                   ("ball_phone", 35, 0, 48, (0.05, 0.25, 0.12, 1))):
        common.render_preview(os.path.join(RENDERS, name + ".png"), size=size, distance=4.2,
                              elevation=el, azimuth=az, background=bg)
    print("VERITY ball texture and previews written")


# ----------------------------------------------------------------------------- the monster

TARGET_TRIS = 8000
TEX_SIZE = 1024
FPS = 24  # the export rate; Meshy's clips are 30 fps and are resampled
HEIGHT = 1.0  # Blender units, head to toe at rest
GLB = os.path.join(OUT, "verity_monster.glb")
ANIMS_JSON = os.path.join(OUT, "verity_anims.json")
# Meshy library clips (tools/meshy_rig.py animate, files in MESHY/anims).
# (name, file, loop, in place: the run's forward root motion is removed, the game moves it)
ACTIONS = [
    ("Idle", "anim_0_idle.glb", True, False),
    ("Run", "anim_16_run_fast.glb", True, True),
    ("Sprint", "anim_509_lean_forward_sprint.glb", True, True),
    ("PickUp", "anim_276_male_bend_over_pick_up.glb", False, False),
    ("Grab", "anim_284_collect_object.glb", False, False),
    ("PickThrow", "anim_280_female_crouch_pick_throw_forward.glb", False, False),
    ("Throw", "anim_421_over_shoulder_throw.glb", False, False),
    ("ThrowDown", "anim_389_grip_and_throw_down.glb", False, False),
    ("Taunt", "anim_88_chest_pound_taunt.glb", False, False),
    ("Cheer", "anim_59_victory_cheer.glb", False, False),
]


def import_glb(path):
    """Import a glb; returns (armature, meshes) of the new objects only."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    return arm, [o for o in new if o.type == "MESH"]


def remove_objects(objs):
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


def m12(m):
    """A 4x4 as 12 numbers: the 3x3 row-major, then the translation, to 4 decimals."""
    return [round(m[i][j], 4) + 0.0 for i in range(3) for j in range(3)] + \
        [round(m[i][3], 4) + 0.0 for i in range(3)]


def from12(v):
    return Matrix(((v[0], v[1], v[2], v[9]), (v[3], v[4], v[5], v[10]),
                   (v[6], v[7], v[8], v[11]), (0, 0, 0, 1)))


def bone_order(arm):
    def depth(b):
        return 0 if b.parent is None else 1 + depth(b.parent)
    return sorted(arm.data.bones, key=depth)


def select_only(objs, active):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def normalise_rig(arm, mesh):
    """Move the rest rig so it is HEIGHT tall, feet at Z = 0, centred on X and Y, with every
    transform applied (armature world = identity). Returns T, the world map applied."""
    from mathutils import Vector as V
    corners = [mesh.matrix_world @ V(c) for c in mesh.bound_box]
    lo = V([min(c[i] for c in corners) for i in range(3)])
    hi = V([max(c[i] for c in corners) for i in range(3)])
    T = Matrix.Scale(HEIGHT / (hi.z - lo.z), 4) @ Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    arm.animation_data_clear()
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    mw = mesh.matrix_world.copy()
    mesh.parent = None
    mesh.matrix_world = T @ mw
    arm.matrix_world = T @ arm.matrix_world
    for obj in (mesh, arm):
        select_only([obj], obj)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh.parent = arm
    mesh.matrix_parent_inverse = Matrix.Identity(4)
    for mod in mesh.modifiers:
        if mod.type == "ARMATURE":
            mod.object = arm
    return T


def weld(me):
    """Merge the vertices the glTF import split at UV seams (UVs live on the face corners, so
    nothing is lost). Split, every UV chart is its own island, and recalc_face_normals orients
    each island on its own: small ones came out flipped (holes in Roblox, which culls back
    faces)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    print("VERITY welded %d -> %d vertices" % (before, len(bm.verts)))
    bm.free()


def decimate(mesh):
    me = mesh.data
    weld(me)
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    mod = mesh.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, TARGET_TRIS / tris)
    mod.use_collapse_triangulate = True
    select_only([mesh], mesh)
    bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    me.calc_loop_triangles()
    print("VERITY decimated %d -> %d triangles" % (tris, len(me.loop_triangles)))


def one_material(mesh):
    src = None
    for mat in mesh.data.materials:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        for link in bsdf.inputs["Base Color"].links:
            if link.from_node.type == "TEX_IMAGE":
                src = link.from_node.image
    rgba = np.empty(src.size[0] * src.size[1] * 4, np.float32)
    src.pixels.foreach_get(rgba)
    rgba = rgba.reshape(src.size[1], src.size[0], 4)[::-1]  # top row first
    f = src.size[0] // TEX_SIZE
    rgba = rgba.reshape(TEX_SIZE, f, TEX_SIZE, f, 4).mean(axis=(1, 3))
    rgba[..., 3] = 1.0
    img = common.image_from_array("verity_monster_basecolor", rgba,
                                  os.path.join(OUT, "textures", "verity_monster_basecolor.png"))
    mesh.data.materials.clear()
    mesh.data.materials.append(common.image_material("VerityMonster", img, roughness=0.55))


def sample_clip(path, T, names, loop, in_place):
    """Pose matrices of every bone of the clip in `path`, in the normalised armature's space."""
    arm, meshes = import_glb(path)
    remove_objects(meshes)
    act = arm.animation_data.action
    start, end = act.frame_range
    if loop:  # the last key repeats the first: sample one period evenly
        period = end - start
        count = max(2, round(period * FPS / 24.0))
        times = [start + i * period / count for i in range(count)]
    else:
        count = int(math.floor(end - start + 1e-6)) + 1
        times = [start + i for i in range(count)]
    scene = bpy.context.scene
    W = T @ arm.matrix_world
    frames = []
    for t in times:
        scene.frame_set(int(math.floor(t)), subframe=t - math.floor(t))
        pose = {}
        for name in names:
            loc, rot, _ = (W @ arm.pose.bones[name].matrix).decompose()
            pose[name] = Matrix.LocRotScale(loc, rot, None)
        frames.append(pose)
    if in_place:  # loops only: take out the hips' X/Y drift over one period (read off the end key)
        first = frames[0]["Hips"].translation.copy()
        scene.frame_set(int(math.floor(end)), subframe=end - math.floor(end))
        drift = (W @ arm.pose.bones["Hips"].matrix).translation - first
        for i, f in enumerate(frames):
            off = Vector((drift.x, drift.y, 0.0)) * (i / count) + Vector((first.x, first.y, 0.0))
            for name in names:
                f[name].translation -= off  # the hips now start at X = Y = 0
    remove_objects([arm])
    bpy.data.actions.remove(act)
    return frames, round(times[-1] - times[0], 3)


def step_monster():
    common.clear_scene()
    arm, meshes = import_glb(os.path.join(MESHY, "rig", "rigged.glb"))
    mesh = meshes[0]
    for extra in meshes[1:]:
        remove_objects([extra])
    arm.name, arm.data.name, mesh.name, mesh.data.name = "Verity", "VerityRig", "VerityBody", "VerityBody"
    T = normalise_rig(arm, mesh)
    decimate(mesh)
    one_material(mesh)
    order = bone_order(arm)
    names = [b.name for b in order]
    rest_hips = arm.data.bones["Hips"].head_local.copy()

    data = {
        "source": "Meshy image-to-3D + auto-rig + animation library; tools/blender/abilities/verity.py",
        "units": "Blender units, model 1.0 tall, feet at Z=0, faces -Y; Z up",
        "armature": {"name": arm.name, "world": m12(arm.matrix_world)},
        "bones": [{"name": b.name, "parent": b.parent.name if b.parent else None, "rest": m12(b.matrix_local)}
                  for b in order],
        "actions": [],
    }
    for name, fname, loop, in_place in ACTIONS:
        frames, span = sample_clip(os.path.join(MESHY, "anims", fname), T, names, loop, in_place)
        if in_place:  # put the hips back over the rest hips (X, Y)
            for f in frames:
                for bn in names:
                    f[bn].translation += Vector((rest_hips.x, rest_hips.y, 0.0))
        tracks = {bn: [m12(f[bn]) for f in frames] for bn in names}
        data["actions"].append({"name": name, "source": fname, "fps": FPS, "frames": len(frames),
                                "loop": loop, "in_place": in_place, "tracks": tracks})
        h = [f["Hips"].translation for f in frames]
        print("VERITY action %-10s %4d frames loop=%s hips x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f" % (
            name, len(frames), loop, min(p.x for p in h), max(p.x for p in h), min(p.y for p in h),
            max(p.y for p in h), min(p.z for p in h), max(p.z for p in h)))
    with open(ANIMS_JSON, "w") as fh:
        json.dump(data, fh, separators=(",", ":"))

    select_only([arm, mesh], arm)
    kwargs = dict(filepath=GLB, export_format="GLB", use_selection=True, export_yup=True,
                  export_skins=True, export_animations=False, export_apply=False,
                  export_materials="EXPORT", export_image_format="AUTO")
    try:
        bpy.ops.export_scene.gltf(export_influence_nb=4, **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)
    print("VERITY wrote", GLB, ANIMS_JSON, "json bytes", os.path.getsize(ANIMS_JSON))


def pose_from_json(arm, bones, frame_mats):
    """Pose `arm` (a re-import of the glb, whose bone axes may differ) to one frame of the
    JSON: posed' = posed @ rest^-1 @ rest' (the skinning transform), parent first."""
    rest = {b["name"]: from12(b["rest"]) for b in bones}
    posed = {}
    for b in bones:
        bone = arm.data.bones[b["name"]]
        m = frame_mats[b["name"]] @ rest[b["name"]].inverted() @ bone.matrix_local
        posed[b["name"]] = m
        if bone.parent is None:
            basis = bone.matrix_local.inverted() @ m
        else:
            p = bone.parent
            basis = (p.matrix_local.inverted() @ bone.matrix_local).inverted() @ posed[p.name].inverted() @ m
        arm.pose.bones[b["name"]].matrix_basis = basis
    bpy.context.view_layer.update()


def tile(paths, cols, out):
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p)
        a = np.empty(im.size[0] * im.size[1] * 4, np.float32)
        im.pixels.foreach_get(a)
        imgs.append(a.reshape(im.size[1], im.size[0], 4)[::-1])
        bpy.data.images.remove(im)
    h, w = imgs[0].shape[:2]
    rows = (len(imgs) + cols - 1) // cols
    sheet = np.zeros((rows * h, cols * w, 4), np.float32)
    sheet[..., 3] = 1
    for i, a in enumerate(imgs):
        r, c = divmod(i, cols)
        sheet[r * h:(r + 1) * h, c * w:(c + 1) * w] = a
    common.image_from_array(os.path.basename(out), sheet, out)
    for p in paths:
        os.remove(p)


def step_renders():
    """Renders from the exported glb posed by the exported JSON, so they show what ships."""
    common.clear_scene()
    bpy.context.scene.view_settings.view_transform = "Standard"
    arm, meshes = import_glb(GLB)
    light_rig(5.0)
    for m in meshes:
        m.data.calc_loop_triangles()
        print("VERITY glb mesh", m.name, "tris", len(m.data.loop_triangles), "mats", len(m.data.materials),
              "dims", tuple(round(x, 4) for x in m.dimensions))
    bg = (0.06, 0.07, 0.09, 1)
    for name, az in (("monster_front", 0), ("monster_threequarter", 40), ("monster_side", 90)):
        common.render_preview(os.path.join(RENDERS, name + ".png"), size=768, target=(0, 0, 0.5),
                              distance=1.65, elevation=8, azimuth=az, background=bg)
    with open(ANIMS_JSON) as fh:
        data = json.load(fh)
    tmp = os.path.join(RENDERS, "_tmp")
    os.makedirs(tmp, exist_ok=True)
    for act in data["actions"]:
        n = act["frames"]
        picks = sorted(set(round(i * (n - 1) / 7) for i in range(8))) if n > 8 else list(range(n))
        paths = []
        for k, fi in enumerate(picks):
            mats = {bn: from12(tr[fi]) for bn, tr in act["tracks"].items()}
            pose_from_json(arm, data["bones"], mats)
            p = os.path.join(tmp, "%s_%02d.png" % (act["name"], k))
            common.render_preview(p, size=320, target=(0, 0, 0.48), distance=2.0, elevation=10, azimuth=35,
                                  background=bg)
            paths.append(p)
        tile(paths, 4 if len(paths) > 4 else len(paths), os.path.join(RENDERS, "anim_%s.png" % act["name"]))
        print("VERITY sheet", act["name"], "frames", picks)
    os.rmdir(tmp)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    steps = argv or ["ball", "monster", "renders"]
    for step in steps:
        {"ball": step_ball, "monster": step_monster, "renders": step_renders}[step]()


main()
