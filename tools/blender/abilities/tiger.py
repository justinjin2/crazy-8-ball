"""Guangdong Tiger (ABILITIES_PROMPT 7.13, references 09 and 10): the tiger, the claw slash, the
cut ball's halves and the fur frame.

The tiger is built by hand (no generator or library here): metaball shapes for an organic,
stylised body in reference 09's look (bold orange, black stripes, white face, belly and paws, a
roaring open mouth, fangs, claws), one object per rigid part so the look can animate it in code
(a rig of joints; Roblox MeshParts):

  TigerTorso, TigerHead, TigerJaw, TigerLegFL, TigerLegFR, TigerLegHL, TigerLegHR, TigerTail
               facing Blender +X (Roblox +X), up +Z, about 2.6 long nose to rump and 1.2 to the
               shoulder. Each part is coloured per vertex on a dense metaball mesh (stripes,
               white markings, eyes, fangs, the mouth's inside), then baked onto a decimated
               copy with its own texture.
  J_Head, J_Jaw, J_LegFL, J_LegFR, J_LegHL, J_LegHR, J_Tail
               tiny cubes at the joints (the head at the neck, the jaw's hinge, the shoulders
               and hips, the tail's root): the look reads their positions and drops them.
  TigerSlash   one claw slash: a flat curved blade, 1 long in X, in the XY plane, two-sided,
               for slash.png (the look lays three side by side, in the air and on the cloth).
  HalfA, HalfB the two halves of a ball shell of unit radius cut by the XZ plane (Roblox XY:
               the look turns the cut across the swipe), with the ball mesh's own UVs so they
               wear the cut ball's texture; the cut face is drawn from the texture's middle.

Rendered images (textures/, RGBA, numpy):
  slash.png      a blade of light: white-hot core, orange then red edges, tapering to points.
  fur_frame.png  reference 10's full-screen frame: gold-orange fur with black stripes in a
                 mirrored chevron, three claw slashes across it.

Run headless: Blender -b --python tools/blender/abilities/tiger.py
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("GuangdongTiger")

# Linear colours. Yellow-gold rather than orange: the game's colour grade pushes it toward red
# (the art director, 2026-09-29, second pass: base about #F8C650, cream about #FFF6E6).
ORANGE = np.array([0.965, 0.63, 0.117])
ORANGE_DARK = np.array([0.94, 0.565, 0.08])
WHITE = np.array([1.0, 0.92, 0.79])
BLACK = np.array([0.03, 0.02, 0.02])
MOUTH = np.array([0.6, 0.03, 0.04])
TONGUE = np.array([0.85, 0.25, 0.3])
NOSE = np.array([0.02, 0.015, 0.015])
EYE = np.array([0.98, 0.78, 0.12])

# Joints (Blender coordinates).
J = {
    "Head": (0.95, 0.0, 1.28),
    "Jaw": (1.36, 0.0, 1.2),
    "LegFL": (0.62, 0.26, 1.0),
    "LegFR": (0.62, -0.26, 1.0),
    "LegHL": (-0.68, 0.26, 1.02),
    "LegHR": (-0.68, -0.26, 1.02),
    "Tail": (-1.02, 0.0, 1.12),
}


# ---------------------------------------------------------------- shapes

def select_only(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def metaball(name, balls, res=0.028, threshold=0.6):
    """balls: (centre, radius, (sx, sy, sz)) ellipsoids of one family, converted to a mesh."""
    mb = bpy.data.metaballs.new(name + "_mb")
    mb.resolution = res
    mb.render_resolution = res
    mb.threshold = threshold
    for co, r, scale in balls:
        e = mb.elements.new()
        e.type = "ELLIPSOID"
        e.co = co
        e.radius = r
        e.size_x, e.size_y, e.size_z = scale  # factors on the radius
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    select_only(obj)
    bpy.ops.object.convert(target="MESH")
    out = bpy.context.active_object
    out.name = name
    out.data.name = name
    return out


def chain(points, radii, step=0.05, scale=(1, 1, 1)):
    """Balls along a polyline with radii interpolated, for legs and the tail."""
    out = []
    for (a, ra), (b, rb) in zip(zip(points[:-1], radii[:-1]), zip(points[1:], radii[1:])):
        a, b = Vector(a), Vector(b)
        n = max(1, int((b - a).length / step))
        for k in range(n):
            t = k / n
            out.append((tuple(a.lerp(b, t)), ra + (rb - ra) * t, scale))
    out.append((tuple(points[-1]), radii[-1], scale))
    return out


def cone(name, base, tip, radius, segs=8):
    bm = bmesh.new()
    base, tip = Vector(base), Vector(tip)
    axis = (tip - base).normalized()
    side = axis.orthogonal().normalized()
    other = axis.cross(side)
    ring = []
    for i in range(segs):
        a = i / segs * 2 * math.pi
        ring.append(bm.verts.new((side * math.cos(a) + other * math.sin(a)) * radius))
    apex = bm.verts.new(tip - base)
    for i in range(segs):
        bm.faces.new((ring[i], ring[(i + 1) % segs], apex))
    bm.faces.new(list(reversed(ring)))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = base  # scaled about its base
    bpy.context.scene.collection.objects.link(obj)
    return obj


def sphere(name, centre, radius, segs=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=radius)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = centre  # scaled about its centre
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------- colour

def nz(p, s=1.0):
    return noise.noise(Vector(p) * s)


def paint(obj, fn):
    """Colour every face corner by fn(position, normal) -> rgb (a 'Col' corner attribute),
    in world space (the object's transform is applied first)."""
    if obj.type == "MESH" and (obj.location.length > 0 or obj.scale != Vector((1, 1, 1))):
        select_only(obj)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR",
                                                                        "CORNER")
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            c = fn(v.co, v.normal)
            attr.data[li].color = (float(c[0]), float(c[1]), float(c[2]), 1.0)


def solid_colour(rgb):
    return lambda p, n: rgb


def smoothstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fur(p, top=1.35, bottom=0.6):
    """The orange, darker along the back."""
    k = smoothstep(bottom, top, p.z)
    return ORANGE * (1 - k) + ORANGE_DARK * k


def torso_colour(p, n):
    # White belly and chest underside.
    belly = 0.8 + 0.05 * nz(p, 3) - 0.1 * smoothstep(0.3, 0.8, p.x)
    if p.z < belly:
        return WHITE
    # Strokes down the flanks, thick on the back, tapering to points toward the belly, some
    # forked low down, some broken over the spine (not rings).
    s = math.sin(p.x * 13.0 + 2.2 * nz(p, 1.6) + 0.8 * abs(p.y) * 4)
    thr = 0.35 + 0.55 * smoothstep(1.25, belly + 0.02, p.z) + 0.12 * nz(p, 4.0)
    if s > thr and p.x > -1.0 and p.x < 0.95:
        core = 1 - (1 - thr) * 0.35
        if p.z < 1.12 and s > core and nz(p + Vector((3, 0, 0)), 3.0) > -0.1:
            return fur(p)  # the fork: an orange split down the stroke's middle
        if abs(p.y) < 0.13 and p.z > 1.3 and nz(p + Vector((0, 0, 7)), 2.5) > 0.15:
            return fur(p)  # broken over the spine
        return BLACK
    return fur(p)


def leg_colour(side):
    def fn(p, n):
        if p.z < 0.17:
            return WHITE  # the paw
        inner = (p.y * side) < 0.24  # toward the body's middle
        if inner and p.z < 0.75:
            return WHITE
        s = math.sin(p.z * 17.0 + 2.0 * nz(p, 2.2))
        if s > 0.55 and p.z > 0.22 and not inner:
            return BLACK
        return fur(p)
    return fn


def tail_colour(root, tip):
    root, tip = Vector(root), Vector(tip)
    length = (tip - root).length

    def fn(p, n):
        t = (Vector(p) - root).length / length
        if t > 0.85:
            return BLACK
        s = math.sin(t * 34.0 + 1.5 * nz(p, 3))
        if s > 0.35:
            return BLACK
        return fur(p)
    return fn


EYE_AT = (1.62, 0.15, 1.44)  # the left eye (y mirrored for the right)
EYE_SLANT = math.radians(20)  # slanted down toward the nose


def eye_local(p):
    """p relative to its side's eye, turned so the almond's long axis is local y."""
    y = abs(p.y)
    dy, dz = y - EYE_AT[1], p.z - EYE_AT[2]
    c, s_ = math.cos(EYE_SLANT), math.sin(EYE_SLANT)
    return p.x - EYE_AT[0], dy * c + dz * s_, -dy * s_ + dz * c


def head_colour(p, n):
    y = abs(p.y)
    # Black almond liner round the eyes, and a tear line down the muzzle's side.
    _, ey, ez = eye_local(p)
    if p.x > 1.45 and (ey / 0.13) ** 2 + (ez / 0.065) ** 2 < 1:
        return BLACK
    if 1.55 < p.x < 1.72 and 0.07 < y < 0.12 and 1.28 < p.z < 1.4:
        return BLACK
    # A black V brow: low at the nose, rising outward (a scowl).
    if p.x > 1.4 and 0.04 < y < 0.24 and abs(p.z - (1.49 + 0.35 * (y - 0.04))) < 0.028:
        return BLACK
    # The mouth: the roof under the muzzle is dark red.
    if p.x > 1.36 and p.z < 1.2 and n.z < 0.2:
        return MOUTH
    # The nose.
    if p.x > 1.84 and p.z > 1.27 and y < 0.08:
        return NOSE
    # White: muzzle, the cheek ruff, the chin, spots over the eyes.
    if p.x > 1.62 and p.z < 1.3:
        return WHITE
    if y > 0.2 and p.z < 1.24 and p.x > 1.05:
        # Cheek stripes over the white ruff.
        if math.sin(p.z * 26 + p.x * 8 + 2 * nz(p, 4)) > 0.7 and y > 0.28:
            return BLACK
        return WHITE
    if p.x > 1.55 and p.z > 1.46 and 0.07 < y < 0.19:
        return WHITE
    # The forehead's stripes and the back of the head.
    if p.z > 1.46:
        s = math.sin(y * 30 + 2.0 * nz(p, 3) + p.x * 6)
        if s > 0.45:
            return BLACK
    if p.x < 1.25 and math.sin(p.z * 20 + 2 * nz(p, 3)) > 0.6:
        return BLACK
    return fur(p, top=1.6, bottom=1.0)


def jaw_colour(p, n):
    if n.z > 0.35:
        return TONGUE if abs(p.y) < 0.09 else MOUTH
    return WHITE


# ---------------------------------------------------------------- the parts

def build_torso():
    balls = [
        ((0.62, 0, 1.0), 0.54, (1.1, 1.1, 1.0)),    # chest
        ((0.3, 0, 0.98), 0.5, (1.1, 1.05, 0.92)),
        ((-0.1, 0, 0.96), 0.48, (1.1, 1.0, 0.86)),  # waist
        ((-0.5, 0, 1.0), 0.52, (1.1, 1.08, 0.95)),   # hips
        ((-0.82, 0, 1.03), 0.42, (1.0, 1.0, 0.9)),
        ((0.92, 0, 1.2), 0.38, (1.0, 1.05, 1.0)),  # neck
        ((0.75, 0, 0.74), 0.34, (1.2, 0.95, 0.8)),   # brisket
    ]
    obj = metaball("TigerTorso", balls)
    paint(obj, torso_colour)
    return obj


def build_head():
    balls = [
        ((1.33, 0, 1.38), 0.48, (1.05, 1.08, 0.9)),   # skull
        ((1.28, 0.26, 1.24), 0.28, (1.0, 1.0, 1.0)),  # cheek ruff
        ((1.28, -0.26, 1.24), 0.28, (1.0, 1.0, 1.0)),
        ((1.64, 0, 1.28), 0.26, (1.2, 1.1, 0.8)),   # muzzle
        ((1.5, 0.13, 1.47), 0.17, (1.0, 1.0, 0.75)),  # brows
        ((1.5, -0.13, 1.47), 0.17, (1.0, 1.0, 0.75)),
        ((1.1, 0, 1.3), 0.3, (1.0, 0.9, 1.0)),       # the back of the head
    ]
    head = metaball("TigerHead", balls)
    paint(head, head_colour)
    extra = []
    for side in (1, -1):
        ear = cone("Ear", (1.22, 0.19 * side, 1.52), (1.16, 0.3 * side, 1.74), 0.11, 12)
        ear.scale = (0.6, 1.0, 1.0)
        bpy.context.view_layer.update()
        # White inside (facing forward), a black back, orange round the rim.
        paint(ear, lambda p, n: WHITE if n.x > 0.35 else (BLACK if n.x < -0.35 else ORANGE))
        eye = sphere("Eye", (1.62, 0.15 * side, 1.44), 0.075)
        eye.scale = (0.5, 1.25, 0.42)  # a narrow almond
        eye.rotation_euler = (EYE_SLANT * side, 0, 0)  # its inner end down toward the nose
        bpy.context.view_layer.update()
        paint(eye, lambda p, n: BLACK if n.x > 0.8 else EYE)
        fang = cone("Fang", (1.74, 0.1 * side, 1.18), (1.75, 0.1 * side, 1.08), 0.035)
        paint(fang, solid_colour(WHITE))
        extra += [ear, eye, fang]
    nose = sphere("Nose", (1.83, 0, 1.33), 0.06, 10, 6)
    nose.scale = (0.8, 1.6, 0.75)
    bpy.context.view_layer.update()
    paint(nose, solid_colour(NOSE))
    extra.append(nose)
    return join(head, extra)


def build_jaw():
    balls = [
        ((1.55, 0, 1.1), 0.2, (1.6, 0.95, 0.45)),
        ((1.4, 0, 1.12), 0.18, (1.2, 1.0, 0.5)),
    ]
    jaw = metaball("TigerJaw", balls)
    paint(jaw, jaw_colour)
    extra = []
    for side in (1, -1):
        fang = cone("LowFang", (1.72, 0.09 * side, 1.13), (1.73, 0.09 * side, 1.28), 0.03)
        paint(fang, solid_colour(WHITE))
        extra.append(fang)
    return join(jaw, extra)


def build_leg(name, front, side):
    y = 0.26 * side
    if front:
        pts = [(0.64, y, 1.02), (0.66, y, 0.6), (0.68, y * 1.05, 0.28), (0.74, y * 1.05, 0.1)]
        radii = [0.25, 0.19, 0.15, 0.18]
    else:
        pts = [(-0.66, y, 1.04), (-0.78, y, 0.62), (-0.7, y, 0.3), (-0.62, y * 1.05, 0.1)]
        radii = [0.3, 0.21, 0.14, 0.18]
    leg = metaball(name, chain(pts, radii, 0.04, (1.0, 0.9, 1.0)))
    paint(leg, leg_colour(side))
    extra = []
    paw = Vector(pts[-1])
    for k in (-1, 0, 1):
        claw = cone("Claw", paw + Vector((0.1, 0.05 * k, -0.02)), paw + Vector((0.2, 0.05 * k, -0.08)),
                    0.02, 6)
        paint(claw, solid_colour(WHITE))
        extra.append(claw)
    return join(leg, extra)


def build_tail():
    pts = [(-1.02, 0, 1.12), (-1.3, 0, 1.0), (-1.6, 0.05, 0.95), (-1.85, 0.1, 1.1),
           (-2.0, 0.08, 1.35)]
    radii = [0.13, 0.11, 0.1, 0.095, 0.09]
    tail = metaball("TigerTail", chain(pts, radii, 0.035))
    paint(tail, tail_colour(pts[0], pts[-1]))
    return tail


def join(main, extra):
    bpy.ops.object.select_all(action="DESELECT")
    for o in extra:
        select_only(o)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [main] + extra:
        o.select_set(True)
    bpy.context.view_layer.objects.active = main
    bpy.ops.object.join()
    return main


# ---------------------------------------------------------------- bake

def bake_part(dense, size, ratio):
    """Bake dense's corner colours onto a decimated, unwrapped copy with its own image."""
    name = dense.name
    dense.name = name + "_dense"
    low = dense.copy()
    low.data = dense.data.copy()
    low.name = name
    low.data.name = name
    bpy.context.scene.collection.objects.link(low)
    select_only(low)
    mod = low.modifiers.new("dec", "DECIMATE")
    mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    for f in low.data.polygons:
        f.use_smooth = True
    # The dense one emits its colours.
    src = bpy.data.materials.new(name + "_src")
    src.use_nodes = True
    nt = src.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(attr.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    dense.data.materials.clear()
    dense.data.materials.append(src)
    # The low one bakes into its image.
    img = bpy.data.images.new(name + "_tex", width=size, height=size, alpha=False)
    dst = bpy.data.materials.new(name + "_dst")
    dst.use_nodes = True
    tex = dst.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    dst.node_tree.nodes.active = tex
    low.data.materials.clear()
    low.data.materials.append(dst)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = 0.03
    scene.render.bake.margin = 4
    bpy.ops.object.select_all(action="DESELECT")
    dense.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.bake(type="EMIT")
    path = os.path.join(OUT, "textures", name.lower() + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    saved = bpy.data.images.load(path)
    low.data.materials.clear()
    low.data.materials.append(common.image_material(name + "Mat", saved, roughness=0.8))
    bpy.data.objects.remove(dense)
    low.name = name  # the name is free again (the dense one held it)
    low.data.name = name
    return low


# ---------------------------------------------------------------- slash, halves, images

def slash_mesh(mat, segs=24):
    """A flat curved blade 1 long along X, bowing in +Y, both sides, UV u along it."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    top, bot = [], []
    for i in range(segs + 1):
        t = i / segs
        x = t - 0.5
        bow = 0.08 * math.sin(t * math.pi)
        w = 0.06
        top.append(bm.verts.new((x, bow + w / 2, 0)))
        bot.append(bm.verts.new((x, bow - w / 2, 0)))
    for flip in (False, True):
        for i in range(segs):
            quad = [bot[i], bot[i + 1], top[i + 1], top[i]]
            if flip:
                quad = list(reversed(quad))
            f = bm.faces.new(quad) if not flip else None
            if f is None:
                # The back face: new vertices so both sides exist.
                vs = [bm.verts.new(v.co) for v in quad]
                f = bm.faces.new(vs)
            for loop in f.loops:
                co = loop.vert.co
                t = co.x + 0.5
                bow = 0.08 * math.sin(t * math.pi)
                loop[uv].uv = (t, 0.5 + (co.y - bow) / 0.06)
    me = bpy.data.meshes.new("TigerSlash")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new("TigerSlash", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ball_uv(d):
    """The ball mesh's UV for a Blender direction (tools/gen_ball_mesh.py)."""
    rx, ry, rz = d[0], d[2], -d[1]
    lon = math.atan2(rz, rx)
    lat = math.asin(max(-1.0, min(1.0, ry)))
    return 0.5 + lon / (2 * math.pi), 0.5 + lat / math.pi


def half(name, side, mat, segs=32, rings=16, thick=0.1):
    """Half a unit ball shell: the Blender y*side >= 0 side, closed by a cut face."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()

    def d(i, j):
        lat = -math.pi / 2 + math.pi * j / rings
        lon = -math.pi / 2 + math.pi * i / segs  # half a turn: y >= 0
        v = Vector((math.cos(lat) * math.cos(lon + math.pi / 2),
                    math.cos(lat) * math.sin(lon + math.pi / 2), math.sin(lat)))
        return Vector((v.x, v.y * side, v.z))

    outer = {(i, j): bm.verts.new(d(i, j)) for i in range(segs + 1) for j in range(rings + 1)}
    for i in range(segs):
        for j in range(rings):
            q = [outer[(i, j)], outer[(i + 1, j)], outer[(i + 1, j + 1)], outer[(i, j + 1)]]
            if side < 0:
                q.reverse()
            try:
                f = bm.faces.new(q)
            except ValueError:
                continue
            for loop in f.loops:
                loop[uvl].uv = ball_uv(loop.vert.co)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    # The cut face: a disc in the XZ plane, drawn from the texture's middle (the ball's colour).
    ring = [bm.verts.new((math.cos(a), 0.0, math.sin(a)))
            for a in (k / 48 * 2 * math.pi for k in range(48))]
    centre = bm.verts.new((0, 0, 0))
    for k in range(48):
        tri = [centre, ring[k], ring[(k + 1) % 48]]
        if side > 0:
            tri.reverse()
        f = bm.faces.new(tri)
        for loop in f.loops:
            loop[uvl].uv = (0.5, 0.35)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for f in me.polygons:
        f.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def slash_image(w=512, h=64):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h * 2 - 1
    uu, vv = np.meshgrid(u, v)
    taper = np.sin(np.clip(uu, 0, 1) * math.pi) ** 0.6
    across = np.abs(vv) / np.maximum(taper, 1e-3)
    core = np.clip(1 - across / 0.35, 0, 1)
    edge = np.clip(1 - across, 0, 1)
    img = np.zeros((h, w, 4))
    col = np.stack([np.ones_like(core), 0.35 + 0.65 * core, 0.1 + 0.9 * core ** 2], -1)
    img[..., 0:3] = col
    img[..., 3] = np.clip(edge ** 0.7 * 1.2, 0, 1)
    return common.image_from_array("TigerSlashImg", img, os.path.join(OUT, "textures", "slash.png"))


def fur_frame_image(w=1024, h=576):
    """The reference's flash frame: mirrored V chevrons of thin, forked, tapering black strokes
    on gold fur, lighter in the middle, with hair grain; three claw slashes across it."""
    rng = np.random.default_rng(4)
    xs = (np.arange(w) + 0.5) / w * 2 - 1
    ys = (np.arange(h) + 0.5) / h * 2 - 1
    x, y = np.meshgrid(xs, -ys)
    ax = np.abs(x)  # mirrored like the reference

    def smooth_noise(cell, seed_scale):
        coarse = rng.uniform(-1, 1, (h // cell + 2, w // cell + 2))
        out = np.kron(coarse, np.ones((cell, cell)))[:h, :w]
        for axis in (0, 1):
            acc = np.zeros_like(out)
            half = cell // 2
            for k in range(-half, half + 1):
                acc += np.roll(out, k, axis=axis)
            out = acc / (2 * half + 1)
        out = out[:, :w // 2]
        return np.concatenate([out[:, ::-1], out], axis=1) * seed_scale

    wob = smooth_noise(48, 1.0)
    fine = smooth_noise(16, 1.0)
    # Chevrons: the phase falls toward the sides (a V pointing down the middle).
    phase = (y - 0.6 * ax ** 1.15) * 18 + wob * 0.9
    band = np.sin(phase)
    row = np.floor(phase / (2 * math.pi))
    # Thin strokes, thickest halfway out, tapering to the middle line and the outer tips.
    tip = np.clip(1 - np.abs(ax - 0.5) / 0.5, 0, 1)
    thr = 0.975 - 0.27 * tip ** 0.7 + 0.03 * fine
    stroke = np.clip((band - thr) / 0.025, 0, 1)
    # Forks: some strokes split down their middle into two prongs toward their tips.
    fork = (np.sin(row * 2.3 + 1.0) > 0.0) & (ax > 0.45) & (band > thr + (1 - thr) * 0.45)
    stroke = np.where(fork, 0.0, stroke)
    # Breaks: a few gaps along the strokes.
    gap = np.sin(ax * 7 + row * 1.9 + wob * 2.0) < -0.86
    stroke = np.where(gap, 0.0, stroke)
    # Gold fur, light in the middle, deep orange at the edges, with hair grain along the V.
    r = np.sqrt(x ** 2 + (y * 0.9) ** 2)
    light = np.array([1.0, 0.8, 0.42])
    deep = np.array([0.86, 0.46, 0.08])
    k = np.clip(r / 1.3, 0, 1)[..., None]
    fur = light * (1 - k) + deep * k
    grain = 0.5 + 0.5 * np.sin((y - 0.6 * ax) * 300 + fine * 3 + ax * 40)
    fur = fur * (0.9 + 0.1 * grain[..., None])
    col = fur * (1 - stroke[..., None]) + np.array([0.05, 0.03, 0.02]) * stroke[..., None]
    # Three claw slashes, down to the right, white-hot cores with orange-red edges.
    for off in (-0.28, 0.0, 0.28):
        # A line from upper-left to lower-right, x in -0.75..0.8.
        t = np.clip((x + 0.75) / 1.55, 0, 1)
        line = (0.45 + off - t * 0.75 + 0.05 * np.sin(t * math.pi)
                + 0.006 * np.sin(t * 90 + off * 40) + 0.004 * np.sin(t * 230))  # jagged
        inside = (x > -0.75) & (x < 0.8)
        taper = np.sin(t * math.pi) ** 0.5
        dist = np.abs(y - line) / np.maximum(taper, 1e-3)
        core = np.clip(1 - dist / 0.055, 0, 1) * inside
        glow = np.clip(1 - dist / 0.17, 0, 1) ** 1.5 * inside
        col = col * (1 - glow[..., None]) + np.array([1.0, 0.35, 0.08]) * glow[..., None]
        col = col * (1 - core[..., None]) + np.array([1.0, 0.98, 0.9]) * core[..., None]
    img = np.zeros((h, w, 4))
    img[..., 0:3] = np.clip(col, 0, 1)
    img[..., 3] = 1
    return common.image_from_array("TigerFurFrame", img,
                                   os.path.join(OUT, "textures", "fur_frame.png"))


def marker(name, at):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.02)
    for v in bm.verts:
        v.co += Vector(at)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build():
    common.clear_scene()
    dense = {
        "TigerTorso": (build_torso(), 1024, 0.12),
        "TigerHead": (build_head(), 1024, 0.15),
        "TigerJaw": (build_jaw(), 256, 0.3),
        "TigerLegFL": (build_leg("TigerLegFL", True, 1), 512, 0.15),
        "TigerLegFR": (build_leg("TigerLegFR", True, -1), 512, 0.15),
        "TigerLegHL": (build_leg("TigerLegHL", False, 1), 512, 0.15),
        "TigerLegHR": (build_leg("TigerLegHR", False, -1), 512, 0.15),
        "TigerTail": (build_tail(), 256, 0.2),
    }
    parts = []
    for name, (obj, size, ratio) in dense.items():
        print(name, "dense triangles", common.triangles([obj]))
        parts.append(bake_part(obj, size, ratio))
    markers = [marker("J_" + k, v) for k, v in J.items()]
    slash_mat = common.image_material("TigerSlashMat", slash_image(), emission=1.0, alpha=True)
    slash = slash_mesh(slash_mat)
    shell = common.image_material("HalfMat", common.image_from_array(
        "HalfGrey", np.ones((8, 8, 4)) * 0.8, os.path.join(OUT, "textures", "half_grey.png")))
    halves = [half("HalfA", 1, shell), half("HalfB", -1, shell)]
    fur_frame_image()
    objects = parts + markers + [slash] + halves
    print("GuangdongTiger triangles:", common.triangles(objects))
    for o in parts:
        print(o.name, common.triangles([o]), tuple(round(v, 3) for v in o.dimensions))
    # Preview: the mouth open (the jaw turned down round its hinge), the slash and halves aside.
    jaw = bpy.data.objects["TigerJaw"]
    hinge = Vector(J["Jaw"])
    jaw.matrix_world = (Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(28), 4, "Y")
                        @ Matrix.Translation(-hinge))
    slash.location = (0.4, 0, 2.5)
    for h in halves:
        h.location = (-1.6, 0, 2.4)
        h.scale = (0.2, 0.2, 0.2)
    grey = (0.55, 0.55, 0.55, 1)
    common.render_preview(os.path.join(OUT, "renders", "tiger.png"), size=720, distance=5.4,
                          elevation=18, azimuth=55, target=(0.0, 0, 1.0), background=grey)
    common.render_preview(os.path.join(OUT, "renders", "tiger_front.png"), size=512,
                          distance=2.8, elevation=8, azimuth=70, target=(1.4, 0, 1.3),
                          background=grey)
    jaw.matrix_world = Matrix.Identity(4)
    slash.location = (0, 0, 0)
    for h in halves:
        h.location = (0, 0, 0)
        h.scale = (1, 1, 1)
    common.export_glb(os.path.join(OUT, "GuangdongTiger.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "GuangdongTiger.blend"))


build()
