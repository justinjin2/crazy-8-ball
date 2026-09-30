"""The 13 ability icons (ABILITIES_PROMPT 5.1 and 6.3): 3D models rendered in Blender.

One shared rig for all 13 so they read as a set: the model is scaled to the same bounding
sphere and centred, the same camera (three-quarter view, same lens), the same studio lights
(key, fill, and a rim light in the ability's rarity colour), the same thick ink outline
(an inverted hull: a solidify shell with flipped normals in the ink colour, back faces
culled) and 512 x 512 on a transparent background. Colours are UI_STYLE's (the ink #1B2033,
the rarity colours).

    Blender -b --python tools/blender/abilities/icons.py -- [Id ...]     (no ids: all 13)

Each builder makes its objects at roughly unit size around the origin; the rig does the rest.
Renders go to assets/abilities/icons/<Id>.png.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.path.join(
    os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities")
sys.path.insert(0, HERE)
import common  # noqa: E402

OUT = os.path.join(common.ASSETS, "icons")
os.makedirs(OUT, exist_ok=True)

INK = (0x1B / 255, 0x20 / 255, 0x33 / 255)
RARITY = {
    "Common": "9CA3AF",
    "Uncommon": "3DD66B",
    "Rare": "3B9BFF",
    "Epic": "A259FF",
    "Legendary": "F2B200",
    "Mythic": "B79CFF",
}
RARITY_OF = {
    "Magnet": "Common",
    "EaglesEye": "Common",
    "SuperBounce": "Common",
    "Ghost": "Uncommon",
    "HeatSeeker": "Uncommon",
    "Rewind": "Rare",
    "TimeStop": "Epic",  # 2026-09-30: Time Stop and Portals swapped rarities
    "ChainLightning": "Epic",
    "Portals": "Rare",
    "SteelBall": "Legendary",
    "BlackFlash": "Legendary",
    "BlackHole": "Mythic",
    "GuangdongTiger": "Mythic",
}
ORDER = list(RARITY_OF.keys())

# The rig (shared by every icon).
FRAME_HALF = 0.9  # every model is scaled so its extent on screen is this either side of the middle
LENS = 50
CAM_DISTANCE = 3.3  # with the lens, the model fills about 85% of the frame
CAM_AZIMUTH = 28.0  # degrees round from the front (-Y), toward +X
CAM_ELEVATION = 18.0
OUTLINE = 0.045  # the ink shell's thickness, in the normalised size


def hexcolor(h, alpha=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (lin[0], lin[1], lin[2], alpha)


def srgb(r, g, b, alpha=1.0):
    return hexcolor("%02X%02X%02X" % (int(r * 255), int(g * 255), int(b * 255)), alpha)


# ------------------------------------------------------------------------------------------
# Materials
# ------------------------------------------------------------------------------------------

def mat(name, color, rough=0.3, metal=0.0, coat=0.6, emit=0.0, emit_color=None, alpha=1.0):
    """A glossy cartoon material: `color` is a hex string or a linear RGBA tuple."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    c = hexcolor(color) if isinstance(color, str) else color
    bsdf.inputs["Base Color"].default_value = c
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Coat Weight"].default_value = coat
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    if emit > 0:
        e = emit_color or c
        e = hexcolor(e) if isinstance(e, str) else e
        bsdf.inputs["Emission Color"].default_value = e
        bsdf.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    return m


def ink_material(color=None):
    """The outline's ink: an emission in the ink colour (or `color`, hex), back faces culled."""
    name = "IconInk" + (color or "")
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = hexcolor(color) if color else (*[c ** 2.2 for c in INK], 1)
    em.inputs["Strength"].default_value = 1.0 if color is None else 2.0
    m.node_tree.links.new(em.outputs["Emission"], out.inputs["Surface"])
    m.use_backface_culling = True
    return m


# ------------------------------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------------------------------

def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def from_bmesh(name, bm, material, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = smooth
    return link(bpy.data.objects.new(name, me))


def prim(kind, name, material, location=(0, 0, 0), rotation=(0, 0, 0), scale=(1, 1, 1),
         smooth=True, **kw):
    """A primitive mesh object (uv_sphere, cylinder, cone, torus, cube, ico_sphere)."""
    ops = {
        "uv_sphere": bpy.ops.mesh.primitive_uv_sphere_add,
        "ico_sphere": bpy.ops.mesh.primitive_ico_sphere_add,
        "cylinder": bpy.ops.mesh.primitive_cylinder_add,
        "cone": bpy.ops.mesh.primitive_cone_add,
        "torus": bpy.ops.mesh.primitive_torus_add,
        "cube": bpy.ops.mesh.primitive_cube_add,
    }
    ops[kind](location=location, rotation=rotation, **kw)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    obj.data.materials.clear()
    obj.data.materials.append(material)
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
    return obj


def extrude_outline(name, points2d, depth, material, bevel=0.0, z=0.0):
    """A flat 2-D outline (list of (x, y), counter-clockwise) extruded along Z by `depth`,
    centred on z, optionally bevelled (a curve with bevel keeps it round and glossy)."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "2D"
    spline = curve.splines.new("POLY")
    spline.points.add(len(points2d) - 1)
    for p, (x, y) in zip(spline.points, points2d):
        p.co = (x, y, 0, 1)
    spline.use_cyclic_u = True
    curve.fill_mode = "BOTH"
    curve.extrude = depth / 2
    curve.bevel_depth = bevel
    curve.bevel_resolution = 3
    obj = link(bpy.data.objects.new(name, curve))
    obj.location.z = z
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    for p in obj.data.polygons:
        p.use_smooth = False
    bpy.ops.object.select_all(action="DESELECT")
    return obj


def tube_path(name, points, radius, material, sides=12, caps=True, radii=None):
    """A round tube along 3-D points (a curve with bevel, converted to a mesh); `radii`
    scales the radius at each point."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, (p, co) in enumerate(zip(spline.points, points)):
        p.co = (co[0], co[1], co[2], 1)
        if radii:
            p.radius = radii[i]
    curve.bevel_depth = radius
    curve.bevel_resolution = max(1, sides // 4)
    curve.use_fill_caps = caps
    obj = link(bpy.data.objects.new(name, curve))
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.active_object
    bpy.ops.object.select_all(action="DESELECT")
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def subdivide(obj, levels=2):
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    return obj


_AZ, _EL = math.radians(CAM_AZIMUTH), math.radians(CAM_ELEVATION)
CAM_DIR = Vector((math.sin(_AZ) * math.cos(_EL), -math.cos(_AZ) * math.cos(_EL), math.sin(_EL)))
SCREEN_RIGHT = (-CAM_DIR).cross(Vector((0, 0, 1))).normalized()
SCREEN_UP = SCREEN_RIGHT.cross(-CAM_DIR).normalized()


def screen(right, up, toward=0.0):
    """A world vector from screen directions: right, up, and toward the camera."""
    return SCREEN_RIGHT * right + SCREEN_UP * up + CAM_DIR * toward


def face_camera(obj):
    """Turn an object built flat in XY (its front +Z) to face the camera, its +Y up."""
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = CAM_DIR.to_track_quat("Z", "Y")
    return obj


def point_along(obj, direction):
    """Turn an object built along +Z to point along `direction`."""
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector(direction).normalized().to_track_quat("Z", "Y")
    return obj


def transform(objs, matrix):
    """Move a group of unparented objects together by `matrix` (applied in world space)."""
    bpy.context.view_layer.update()
    for o in objs:
        if o.parent is None:
            o.matrix_world = matrix @ o.matrix_world
    bpy.context.view_layer.update()


def ramp_fill(ramp, stops, constant=False):
    """Colour-ramp stops [(position, hex), ...] in increasing order."""
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = stops[0][0], hexcolor(stops[0][1])
    els[1].position, els[1].color = stops[-1][0], hexcolor(stops[-1][1])
    for pos, col in stops[1:-1]:
        els.new(pos).color = hexcolor(col)
    if constant:
        ramp.color_ramp.interpolation = "CONSTANT"


def glow(name, location, radius, color, strength=3.0, power=2.0):
    """A soft glow: a camera-facing disc, emissive in the middle and fading to clear. Not
    outlined and not counted in the framing."""
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=1.0, fill_type="NGON",
                                      location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (radius, radius, radius)
    m = bpy.data.materials.new(name + "Mat")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    coord = nodes.new("ShaderNodeTexCoord")
    grad = nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    pw = nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = power
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = hexcolor(color)
    em.inputs["Strength"].default_value = strength
    tr = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(coord.outputs["Object"], grad.inputs["Vector"])
    links.new(grad.outputs["Fac"], pw.inputs[0])
    links.new(pw.outputs["Value"], mix.inputs["Fac"])
    links.new(tr.outputs["BSDF"], mix.inputs[1])
    links.new(em.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    obj.data.materials.append(m)
    obj["no_outline"] = True
    obj["no_frame"] = True
    obj["glow"] = True
    return face_camera(obj)


def swirl_material(name, r0, r1, stops, strength, alpha=1.0, swirl=0.6, scale=3.0,
                   distortion=10.0, fade=3.0):
    """An emissive disc or ring material coloured by radius (object space, r0..r1 -> the
    ramp's stops), streaked by a distorted ring wave, fading to clear at the outer edge."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    coord = nodes.new("ShaderNodeTexCoord")
    length = nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    mr = nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = r0
    mr.inputs["From Max"].default_value = r1
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp_fill(ramp, stops)
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = scale
    wave.inputs["Distortion"].default_value = distortion
    wave.inputs["Detail"].default_value = 3.0
    streak = nodes.new("ShaderNodeMath")
    streak.operation = "MULTIPLY_ADD"
    streak.inputs[1].default_value = strength * swirl
    streak.inputs[2].default_value = strength * (1 - swirl * 0.5)
    em = nodes.new("ShaderNodeEmission")
    edge = nodes.new("ShaderNodeMath")
    edge.operation = "POWER"
    edge.inputs[1].default_value = fade
    inv = nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    scale_a = nodes.new("ShaderNodeMath")
    scale_a.operation = "MULTIPLY"
    scale_a.inputs[1].default_value = alpha
    tr = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(coord.outputs["Object"], length.inputs[0])
    links.new(length.outputs["Value"], mr.inputs["Value"])
    links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], em.inputs["Color"])
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    links.new(wave.outputs["Fac"], streak.inputs[0])
    links.new(streak.outputs["Value"], em.inputs["Strength"])
    links.new(mr.outputs["Result"], edge.inputs[0])
    links.new(edge.outputs["Value"], inv.inputs[1])
    links.new(inv.outputs["Value"], scale_a.inputs[0])
    links.new(scale_a.outputs["Value"], mix.inputs["Fac"])
    links.new(tr.outputs["BSDF"], mix.inputs[1])
    links.new(em.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], out.inputs["Surface"])
    try:
        m.surface_render_method = "BLENDED"
    except Exception:
        pass
    return m


def annulus(name, r0, r1, material, segs=128, rings=8):
    """A flat ring in XY from radius r0 to r1 (r0 = 0: a disc)."""
    bm = bmesh.new()
    grid = []
    for j in range(rings + 1):
        r = max(r0 + (r1 - r0) * j / rings, 1e-4)
        grid.append([bm.verts.new((math.cos(2 * math.pi * i / segs) * r,
                                   math.sin(2 * math.pi * i / segs) * r, 0))
                     for i in range(segs)])
    for j in range(rings):
        for i in range(segs):
            i2 = (i + 1) % segs
            bm.faces.new((grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]))
    obj = from_bmesh(name, bm, material)
    obj["no_outline"] = True
    return obj


def slab(name, pts, depth, material, bevel=0.02, at=(0, 0, 0)):
    """A flat 2-D shape (x right, y up) extruded `depth` thick, standing in the XZ plane with
    its front toward -Y (the camera's side)."""
    obj = extrude_outline(name, pts, depth, material, bevel=bevel)
    obj.rotation_euler = (math.pi / 2, 0, 0)
    obj.location = at
    return obj


def bands(obj, materials, axis, lo, hi):
    """Colour an object in bands along `axis` (its local coordinates, lo..hi)."""
    axis = Vector(axis).normalized()
    base = len(obj.data.materials)
    for m in materials:
        obj.data.materials.append(m)
    n = len(materials)
    for p in obj.data.polygons:
        t = (p.center.dot(axis) - lo) / (hi - lo)
        p.material_index = base + min(n - 1, max(0, int(t * n)))


def stripe(name, target, a, b, width, material, side, segments=12, shape="taper",
           offset=0.006):
    """A painted stripe on `target`'s surface: a strip from a to b (both near the surface),
    `width` wide across `side`, shrinkwrapped onto it. shape: "taper" (full at a, a point at
    b) or "lens" (points at both ends)."""
    a, b, side = Vector(a), Vector(b), Vector(side).normalized()
    bm = bmesh.new()
    rows = []
    for i in range(segments + 1):
        t = i / segments
        c = a + (b - a) * t
        if shape == "taper":
            w = width * (1 - 0.94 * t)
        else:
            w = width * max(math.sin(math.pi * (0.04 + 0.92 * t)), 0.03)
        rows.append([bm.verts.new(c + side * (w * (k - 2) / 2)) for k in range(5)])
    for i in range(segments):
        for k in range(4):
            bm.faces.new((rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]))
    obj = from_bmesh(name, bm, material)
    sw = obj.modifiers.new("Wrap", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.offset = offset
    obj["no_outline"] = True
    obj["no_frame"] = True
    return obj


def surface_y(x, z, rx, ry, rz):
    """The front (-Y) surface of an ellipsoid at the origin, at (x, z)."""
    k = 1 - (x / rx) ** 2 - (z / rz) ** 2
    return -ry * math.sqrt(max(k, 0.0))


def clip_strip(poly, y0, y1):
    """A convex polygon cut to the band y0 <= y <= y1 (empty if nothing is left)."""
    def clip(pts, keep, y):
        out = []
        for i in range(len(pts)):
            p, q = pts[i], pts[(i + 1) % len(pts)]
            pin, qin = keep(p), keep(q)
            if pin:
                out.append(p)
            if pin != qin:
                out.append((p[0] + (q[0] - p[0]) * (y - p[1]) / (q[1] - p[1]), y))
        return out
    pts = clip(poly, lambda p: p[1] >= y0, y0)
    if len(pts) < 3:
        return []
    pts = clip(pts, lambda p: p[1] <= y1, y1)
    return pts if len(pts) >= 3 else []


# ------------------------------------------------------------------------------------------
# The rig
# ------------------------------------------------------------------------------------------

def normalise(objects):
    """Scale and move the model so its extent on screen (the camera's right and up) is
    FRAME_HALF either side of the middle: every icon fills the frame the same way, whatever
    its shape."""
    bpy.context.view_layer.update()
    root = bpy.data.objects.new("IconRoot", None)
    link(root)
    for obj in objects:
        if obj.parent is None:
            obj.parent = root
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in objects:
        if obj.type != "MESH" or obj.get("no_frame"):
            continue
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        mw = obj.matrix_world
        pts += [mw @ v.co for v in me.vertices]
        ev.to_mesh_clear()
    def span(axis):
        d = [p.dot(axis) for p in pts]
        return min(d), max(d)
    (x0, x1), (y0, y1), (z0, z1) = span(SCREEN_RIGHT), span(SCREEN_UP), span(CAM_DIR)
    centre = SCREEN_RIGHT * ((x0 + x1) / 2) + SCREEN_UP * ((y0 + y1) / 2) + CAM_DIR * ((z0 + z1) / 2)
    s = FRAME_HALF / max((x1 - x0) / 2, (y1 - y0) / 2, 1e-6)
    root.location = -centre * s
    root.scale = (s, s, s)
    bpy.context.view_layer.update()
    return root, s


def outline(objects, scale):
    """The ink shell on every mesh: an inverted hull a fixed thickness in the final frame."""
    for obj in objects:
        if obj.type != "MESH" or obj.get("no_outline"):
            continue
        ink = ink_material(obj.get("ink"))
        count = len(obj.data.materials)
        obj.data.materials.append(ink)
        mod = obj.modifiers.new("InkShell", "SOLIDIFY")
        world_scale = scale * max(obj.scale)
        mod.thickness = OUTLINE / max(world_scale, 1e-6) * obj.get("outline_scale", 1.0)
        mod.offset = 1.0
        mod.use_flip_normals = True
        mod.use_rim = False
        mod.material_offset = count
        mod.material_offset_rim = count


def rig(rarity):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.lens = LENS
    cam = link(bpy.data.objects.new("IconCam", cam_data))
    cam.location = CAM_DIR * CAM_DISTANCE
    common.look_at(cam, Vector((0, 0, 0)))
    scene.camera = cam

    def light(name, kind, energy, color, location, size=2.0):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == "AREA":
            data.size = size
        obj = link(bpy.data.objects.new(name, data))
        obj.location = location
        common.look_at(obj, Vector((0, 0, 0)))
        return obj

    light("Key", "AREA", 520, (1.0, 0.97, 0.92), (-2.6, -3.2, 3.4), 2.5)
    light("Fill", "AREA", 160, (0.85, 0.92, 1.0), (3.4, -2.2, 0.8), 3.0)
    rim = hexcolor(RARITY[rarity])
    light("Rim", "AREA", 700, rim[:3], (1.2, 3.6, 2.4), 2.0)
    light("Top", "AREA", 120, (1, 1, 1), (0, 0, 4.5), 3.0)

    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.75, 0.8, 0.9, 1)
    bg.inputs["Strength"].default_value = 0.6

    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    try:
        scene.eevee.taa_render_samples = 64
    except Exception:
        pass


# ------------------------------------------------------------------------------------------
# The icons
# ------------------------------------------------------------------------------------------

def magnet():
    """A horseshoe magnet: one thick U (a round tube), the right half red (N), the left blue
    (S), silver pole tips."""
    red = mat("MagRed", "F0453A", rough=0.22)
    blue = mat("MagBlue", "3C82E6", rough=0.22)
    steel = mat("MagSteel", "E4E8EE", rough=0.15, metal=0.85)
    R, LEG = 0.62, 0.95
    pts = [(-R, 0, -LEG)]
    for i in range(1, 40):
        pts.append((-R, 0, -LEG + LEG * i / 40))
    for i in range(0, 49):
        a = math.pi - math.pi * i / 48
        pts.append((R * math.cos(a), 0, R * math.sin(a)))
    for i in range(1, 41):
        pts.append((R, 0, -LEG * i / 40))
    u = tube_path("U", pts, 0.28, red, sides=24, caps=True)
    u.data.materials.append(blue)
    for poly in u.data.polygons:
        if poly.center.x < 0:
            poly.material_index = 1
    objs = [u]
    for side in (1, -1):
        tip = prim("cylinder", "Tip", steel, location=(R * side, 0, -LEG - 0.17),
                   radius=0.285, depth=0.34, vertices=40)
        bev = tip.modifiers.new("Bevel", "BEVEL")
        bev.width = 0.04
        bev.segments = 3
        objs.append(tip)
    return objs


def iris_material(name, radius_units):
    """The iris: radial fibres (noise stretched along the radius) over rings from an amber
    ring round the pupil through olive to a sparkling green, darkening to a limbal ring at
    the edge. Built on the disc's own coordinates (its face in local XY, radius
    `radius_units`)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], sep.inputs[0])
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(sep.outputs["X"], comb.inputs["X"])
    links.new(sep.outputs["Y"], comb.inputs["Y"])
    length = nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    links.new(comb.outputs[0], length.inputs[0])
    radius = nodes.new("ShaderNodeMath")  # 0 at the centre, 1 at the rim
    radius.operation = "DIVIDE"
    radius.inputs[1].default_value = radius_units
    links.new(length.outputs["Value"], radius.inputs[0])
    angle = nodes.new("ShaderNodeMath")
    angle.operation = "ARCTAN2"
    links.new(sep.outputs["Y"], angle.inputs[0])
    links.new(sep.outputs["X"], angle.inputs[1])
    # Fibres: noise sampled at (angle x 9, radius x 0.6): streaks running out along the radius.
    a_k = nodes.new("ShaderNodeMath")
    a_k.operation = "MULTIPLY"
    a_k.inputs[1].default_value = 9.0
    links.new(angle.outputs[0], a_k.inputs[0])
    r_k = nodes.new("ShaderNodeMath")
    r_k.operation = "MULTIPLY"
    r_k.inputs[1].default_value = 0.6
    links.new(radius.outputs[0], r_k.inputs[0])
    fib_v = nodes.new("ShaderNodeCombineXYZ")
    links.new(a_k.outputs[0], fib_v.inputs["X"])
    links.new(r_k.outputs[0], fib_v.inputs["Y"])
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.0
    noise.inputs["Detail"].default_value = 10.0
    noise.inputs["Roughness"].default_value = 0.65
    links.new(fib_v.outputs[0], noise.inputs["Vector"])
    shade = nodes.new("ShaderNodeValToRGB")
    ramp_fill(shade, [(0.3, "4A4A4A"), (0.55, "C8C8C8"), (0.75, "FFFFFF")])
    links.new(noise.outputs["Fac"], shade.inputs["Fac"])
    rings = nodes.new("ShaderNodeValToRGB")
    ramp_fill(rings, [(0.0, "3A2208"), (0.33, "D08A1A"), (0.45, "A8A62C"), (0.56, "4FC45A"),
                      (0.8, "2FB257"), (0.9, "1C7A3A"), (0.97, "0B2E18")])
    links.new(radius.outputs[0], rings.inputs["Fac"])
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    links.new(rings.outputs["Color"], mix.inputs["A"])
    links.new(shade.outputs["Color"], mix.inputs["B"])
    links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    links.new(mix.outputs["Result"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.9
    bsdf.inputs["Roughness"].default_value = 0.08
    # A soft gloss only: a sharp coat mirrors the square studio lights on the iris.
    bsdf.inputs["Coat Weight"].default_value = 0.3
    bsdf.inputs["Coat Roughness"].default_value = 0.25
    return m


def hunter_eye():
    """Hunter eyes (the designer, 2026-09-30, from a close-up reference; was an eagle's head,
    then a cat's eye): one human eye, hooded, its outer corner tilted up, a low heavy brow of
    drawn hair strokes right over it, lashes, and a detailed sparkling green iris (fibres, an
    amber ring round the pupil, a dark limbal ring, catchlights and a few sparkles)."""
    import random
    rng = random.Random(7)
    sclera_m = mat("HunterSclera", "F3EEE8", rough=0.25, coat=0.6)
    pink = mat("HunterCaruncle", "E5868A", rough=0.3, coat=0.5)
    liner = mat("HunterLiner", "1A120D", rough=0.4, coat=0.2)
    brow_fill = mat("HunterBrowFill", "150E0A", rough=0.8, coat=0.0)
    hairs = [mat("HunterHair%d" % i, c, rough=0.7, coat=0.0)
             for i, c in enumerate(("080504", "100A07", "1A110C", "2A1C14"))]
    pupil_m = mat("HunterPupil", "020202", rough=0.7, coat=0.0)  # matte: no light squares
    shine = mat("HunterShine", "FFFFFF", rough=0.1, emit=4.0)
    sparkle = mat("HunterSparkle", "EFFFF2", rough=0.1, emit=5.0, emit_color="D8FFE0")
    shadow = mat("HunterLidShadow", "2A1A14", rough=0.8, coat=0.0, alpha=0.4)
    ix, iz, ir = 0.06, 0.0, 0.45
    iris_m = iris_material("HunterIris", ir)

    TILT = 0.09  # the outer corner (left, x < 0) sits higher: a positive canthal tilt
    UP, DOWN = 0.36, 0.4  # the hooded, flatter upper lid; the lower lid

    def lid_y(x, upper):
        base = UP * (1 - x * x) ** 0.62 if upper else -DOWN * (1 - x * x) ** 0.85
        return base - TILT * x

    def almond(sx=1.0, sy=1.0, n=48):
        pts = [(-1 + 2 * k / n, lid_y(-1 + 2 * k / n, False)) for k in range(n + 1)]
        pts += [(-1 + 2 * k / n, lid_y(-1 + 2 * k / n, True)) for k in range(n - 1, 0, -1)]
        return [(x * sx, y * sy) for x, y in pts]

    def stroke(pts, width, taper=(0.0, 1.0)):
        """A flat stroke along a polyline, `width` thick, tapering in at the start over the
        first taper[0] of it and out to a point from taper[1] on."""
        n = len(pts) - 1
        top, bottom = [], []
        for k, p in enumerate(pts):
            q0, q1 = pts[max(k - 1, 0)], pts[min(k + 1, n)]
            dx, dy = q1[0] - q0[0], q1[1] - q0[1]
            ln = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / ln, dx / ln
            t = k / n
            w = width
            if taper[0] > 0 and t < taper[0]:
                w *= (t / taper[0]) ** 0.6
            if t > taper[1]:
                w *= ((1 - t) / (1 - taper[1])) ** 0.8
            w = w / 2 + 0.004
            top.append((p[0] + nx * w, p[1] + ny * w))
            bottom.append((p[0] - nx * w, p[1] - ny * w))
        return top + list(reversed(bottom))

    def boolean_intersect(obj, mask):
        mod = obj.modifiers.new("Clip", "BOOLEAN")
        mod.operation = "INTERSECT"
        mod.solver = "EXACT"
        mod.object = mask
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)

    objs = []
    # The white of the eye (outlined: the eye's silhouette) and the pink inner corner.
    objs.append(slab("Sclera", almond(), 0.16, sclera_m, bevel=0.03, at=(0, 0, 0)))
    car = prim("uv_sphere", "Caruncle", pink, location=(0.9, -0.12, lid_y(0.9, False) * 0.2),
               radius=1.0, segments=24, ring_count=12, scale=(0.09, 0.05, 0.07))
    car["no_outline"] = True
    objs.append(car)

    # The iris and the pupil, clipped to the eye's opening.
    mask = slab("IrisMask", almond(0.99, 0.99), 2.0, sclera_m, bevel=0.0, at=(0, 0, 0))
    iris = prim("cylinder", "Iris", iris_m, location=(ix, -0.14, iz), radius=ir, depth=0.04,
                vertices=96, rotation=(math.pi / 2, 0, 0))
    boolean_intersect(iris, mask)
    iris["no_outline"] = True
    objs.append(iris)
    pupil = prim("cylinder", "Pupil", pupil_m, location=(ix, -0.17, iz), radius=ir * 0.34,
                 depth=0.02, vertices=64, rotation=(math.pi / 2, 0, 0))
    pupil["no_outline"] = True
    objs.append(pupil)
    # A soft shadow under the hooded upper lid, over the white and the iris.
    shade_pts = [(-1 + 2 * k / 40, lid_y(-1 + 2 * k / 40, True)) for k in range(41)]
    shade_pts += [(x, y - 0.11 * (1 - x * x) ** 0.5) for x, y in reversed(shade_pts)]
    lid_shadow = slab("LidShadow", shade_pts, 0.01, shadow, bevel=0.0, at=(0, -0.2, 0))
    boolean_intersect(lid_shadow, mask)
    lid_shadow["no_outline"] = True
    objs.append(lid_shadow)
    bpy.data.objects.remove(mask, do_unlink=True)

    # Catchlights, and tiny glints scattered in the iris.
    for x, z, r in ((ix - 0.08, iz + 0.12, 0.07), (ix + 0.17, iz - 0.12, 0.03)):
        c = prim("uv_sphere", "Catchlight", shine, location=(x, -0.2, z), radius=r,
                 segments=16, ring_count=8, scale=(1, 0.3, 1))
        c["no_outline"] = True
        objs.append(c)
    for _ in range(9):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(0.2, 0.36)
        x, z = ix + math.cos(a) * d, iz + math.sin(a) * d
        if z > lid_y(x, True) - 0.04 or z < lid_y(x, False) + 0.04:
            continue
        g = prim("uv_sphere", "Glint", sparkle, location=(x, -0.18, z),
                 radius=rng.uniform(0.008, 0.016), segments=8, ring_count=4)
        g["no_outline"] = True
        objs.append(g)

    # The lash lines: heavy along the top, flicking out past the outer corner; thin below.
    top = [(-1 + 2 * k / 40, lid_y(-1 + 2 * k / 40, True) + 0.01) for k in range(41)]
    wing = [(-1.0 - 0.06 * k, lid_y(-1, True) + 0.01 + 0.025 * k) for k in range(1, 5)]
    upper = list(reversed(wing)) + top
    objs.append(slab("UpperLiner", stroke(upper, 0.085, taper=(0.12, 0.85)), 0.05, liner,
                     bevel=0.01, at=(0, -0.12, 0)))
    bottom = [(-1 + 2 * k / 40, lid_y(-1 + 2 * k / 40, False) - 0.008) for k in range(41)]
    low = slab("LowerLiner", stroke(bottom, 0.03, taper=(0.1, 0.7)), 0.03, liner, bevel=0.005,
               at=(0, -0.1, 0))
    low["outline_scale"] = 0.3
    objs.append(low)

    # Lashes: curved strands off the lids, longest toward the outer corner.
    def lash(x, upper, length):
        y0 = lid_y(x, upper)
        out = 1 if upper else -1
        pts = []
        for k in range(6):
            t = k / 5
            pts.append((x - (0.08 + 0.1 * (0.5 - x * 0.5)) * t * t,
                        -0.12 - 0.05 * t,
                        y0 + out * length * t - out * 0.02 * t * t))
        o = tube_path("Lash", pts, 0.009, liner, sides=6, caps=True,
                      radii=[1.0, 0.95, 0.8, 0.6, 0.4, 0.15])
        o["no_outline"] = True
        return o
    for k in range(17):
        x = -0.95 + 1.7 * k / 16 + rng.uniform(-0.02, 0.02)
        objs.append(lash(x, True, 0.1 + 0.1 * (0.5 - x * 0.5) + rng.uniform(-0.02, 0.02)))
    for k in range(11):
        x = -0.85 + 1.5 * k / 10 + rng.uniform(-0.02, 0.02)
        objs.append(lash(x, False, 0.05 + 0.04 * (0.5 - x * 0.5)))

    # The brow: low, straight and heavy, sitting right over the eye; a dark fill under a mass
    # of hair strokes (the head's hairs stand up, the body's sweep out to the tail, the upper
    # ones angling down and the lower ones up, meeting along the middle).
    def brow_mid(t):  # t 0 = the head (inner, right) .. 1 = the tail (outer, left)
        return 1.08 - 2.45 * t, 0.5 + 0.1 * t + 0.06 * math.sin(math.pi * t * 0.8)

    def brow_half(t):
        return 0.22 * (1 - t) ** 0.5 * min(1.0, (t + 0.05) / 0.25) ** 0.7

    def fill_half(t):
        return brow_half(t) * 0.9

    band_top = [(brow_mid(k / 40)[0], brow_mid(k / 40)[1] + fill_half(k / 40))
                for k in range(41)]
    band_bottom = [(brow_mid(k / 40)[0], brow_mid(k / 40)[1] - fill_half(k / 40))
                   for k in range(40, -1, -1)]
    fill = slab("BrowFill", band_top + band_bottom, 0.04, brow_fill, bevel=0.01, at=(0, 0, 0))
    fill["no_outline"] = True
    objs.append(fill)
    for _ in range(650):
        t = rng.uniform(0.0, 0.97) ** 1.15
        mx, my = brow_mid(t)
        h = brow_half(t)
        s = rng.uniform(-1, 1)
        x0, y0 = mx, my + s * h * 1.05
        if t < 0.14:
            # The head: fanning up and out, leaning further toward the tail up top.
            dx, dy = -0.35 - 0.5 * max(s, 0.0) + rng.uniform(-0.15, 0.15), 1.0
        else:
            dx, dy = -1.0, -0.35 * s + rng.uniform(-0.12, 0.12)
        ln = math.hypot(dx, dy)
        dx, dy = dx / ln, dy / ln
        length = rng.uniform(0.14, 0.3) * (0.65 if t > 0.8 else 1.0) * (0.6 if t < 0.14 else 1.0)
        bend = rng.uniform(-0.03, 0.03)
        pts = []
        for k in range(4):
            u = k / 3
            pts.append((x0 + dx * length * u - dy * bend * u * u,
                        -0.05 - 0.01 * rng.random(),
                        y0 + dy * length * u + dx * bend * u * u))
        hair = tube_path("BrowHair", pts, 0.013, rng.choice(hairs), sides=6, caps=True,
                         radii=[1.0, 0.8, 0.5, 0.15])
        hair["no_outline"] = True
        objs.append(hair)

    # Sparkles: four-point stars off the eye.
    def star(cx, cz, r):
        pts = []
        for k in range(32):
            a = 2 * math.pi * k / 32
            c, s = math.cos(a), math.sin(a)
            rr = r * (abs(c) ** 3 + abs(s) ** 3) ** 2 * 0.95 + r * 0.05
            pts.append((cx + c * rr, cz + s * rr))
        o = slab("Sparkle", pts, 0.02, sparkle, bevel=0.0, at=(0, -0.3, 0))
        o["no_outline"] = True
        o["no_frame"] = True
        return o
    objs += [star(0.62, 0.2, 0.16), star(-0.55, -0.42, 0.1), star(0.4, -0.5, 0.06)]

    # Face the camera square on.
    q = CAM_DIR.to_track_quat("-Y", "Z")
    transform(objs, q.to_matrix().to_4x4())
    objs.append(glow("HunterGlow", (0, 0.15, 0), 1.2, "55E07A", strength=0.7, power=1.8))
    return objs


def super_bounce():
    """A glossy rainbow ball just off a bounce: the bounce's arc trailing behind it, impact
    lines and a star where it hit."""
    colors = ["FF4D4D", "FF9F1C", "FFE14D", "3DD66B", "3B9BFF", "A259FF"]
    C = Vector((0.42, 0, 0.32))
    R = 0.52
    m = bpy.data.materials.new("Rainbow")
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.18
    bsdf.inputs["Coat Weight"].default_value = 0.9
    coord = nodes.new("ShaderNodeTexCoord")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = Vector((0.5, -0.35, 0.8)).normalized()
    mr = nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -R
    mr.inputs["From Max"].default_value = R
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp_fill(ramp, [(i / len(colors), c) for i, c in enumerate(colors)], constant=True)
    links.new(coord.outputs["Object"], dot.inputs[0])
    links.new(dot.outputs["Value"], mr.inputs["Value"])
    links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    ball = prim("uv_sphere", "Ball", m, location=C, segments=64, ring_count=32, radius=R)
    objs = [ball]
    white = mat("Trail", "FFFFFF", rough=0.3, emit=0.3)
    floor = -0.62
    hit = Vector((-0.42, 0.05, floor))
    pts, radii = [], []
    # Falling in from the upper left to the hit, then rising to just behind the ball.
    for i in range(0, 21):
        t = i / 20
        x = -1.35 + (hit.x + 1.35) * t
        pts.append((x, 0.05, floor + 0.78 * (1 - t * t)))
        radii.append(0.25 + 0.35 * t)
    for i in range(1, 17):
        s = i / 16 * 0.62
        x = hit.x + (C.x - hit.x) * s
        z = floor + (C.z - floor) * (1 - (1 - s) ** 2)
        pts.append((x, 0.05, z))
        radii.append(0.6 + 0.4 * i / 16)
    trail = tube_path("Trail", pts, 0.085, white, sides=12, radii=radii)
    objs.append(trail)
    yellow = mat("Impact", "FFE14D", rough=0.3, emit=0.6)
    for deg in (160, 128, 96):
        a = math.radians(deg)
        d = Vector((math.cos(a), 0, math.sin(a)))
        objs.append(tube_path("Impact", [hit + d * 0.14, hit + d * 0.34], 0.035, yellow))
    star_pts = []
    for i in range(16):
        a = 2 * math.pi * i / 16
        r = 0.3 if i % 2 == 0 else 0.14
        star_pts.append((math.cos(a) * r, math.sin(a) * r))
    star = extrude_outline("Star", star_pts, 0.05, yellow)
    star.location = (hit.x, hit.y, floor - 0.03)
    star["outline_scale"] = 0.6
    objs.append(star)
    return objs


def ghost():
    """A cute ghost facing the camera: a round top, a wavy hem, arms up in a 'boo', big dark
    eyes with shines, a little open mouth and pink cheeks, a pale blue aura."""
    body_m = mat("GhostBody", "F1F7FF", rough=0.35, coat=0.5, emit=0.3, emit_color="D6E9FF")
    dark = mat("GhostDark", "1B2033", rough=0.2)
    pink = mat("GhostPink", "FF9CC8", rough=0.4)
    shine_m = mat("GhostShine", "FFFFFF", emit=2.0)
    R = 0.64
    bm = bmesh.new()
    rings = []
    n, levels = 48, 32
    for j in range(levels + 1):
        t = j / levels
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n
            if t < 0.5:
                r = R + 0.06 * (0.5 - t)
                z = -0.95 + t * 1.9
                if j == 0:
                    z += 0.12 * math.cos(a * 6)
            else:
                u = (t - 0.5) / 0.5
                r = R * math.cos(u * math.pi / 2) + 0.001
                z = 0.0 + R * math.sin(u * math.pi / 2)
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    for j in range(levels):
        for k in range(n):
            bm.faces.new((rings[j][k], rings[j][(k + 1) % n], rings[j + 1][(k + 1) % n],
                          rings[j + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    objs = [from_bmesh("Body", bm, body_m)]
    for side in (-1, 1):
        arm = prim("uv_sphere", "Arm", body_m, radius=1.0, segments=24, ring_count=12,
                   scale=(0.12, 0.12, 0.26))
        point_along(arm, (side * 0.8, -0.1, 0.6))
        arm.location = (side * 0.7, -0.05, -0.2)
        objs.append(arm)
        ex = 0.22 * side
        ey = -math.sqrt(R * R - ex * ex)
        eye = prim("uv_sphere", "Eye", dark, location=(ex, ey + 0.03, 0.12), radius=1.0,
                   segments=24, ring_count=12, scale=(0.1, 0.06, 0.15))
        shine = prim("uv_sphere", "Shine", shine_m, location=(ex - 0.03, ey - 0.03, 0.18),
                     radius=0.035, segments=12, ring_count=6)
        cx = 0.37 * side
        cy = -math.sqrt(R * R - cx * cx)
        cheek = prim("uv_sphere", "Cheek", pink, location=(cx, cy + 0.02, -0.04), radius=1.0,
                     segments=16, ring_count=8, scale=(0.085, 0.03, 0.05))
        for o in (eye, shine, cheek):
            o["no_outline"] = True
            objs.append(o)
    mouth = prim("uv_sphere", "Mouth", dark, location=(0, -R + 0.03, -0.1), radius=1.0,
                 segments=16, ring_count=8, scale=(0.07, 0.04, 0.085))
    mouth["no_outline"] = True
    objs.append(mouth)
    # Face the camera, leaning a little.
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH), 4, "Z")
              @ Matrix.Rotation(math.radians(-6), 4, "Y"))
    objs.append(glow("Aura", (0, 0.1, 0), 1.25, "9FD0FF", strength=1.2, power=1.5))
    return objs


def heat_seeker():
    """A cartoon missile flying up and to the right with a flame out of its tail, a red
    lock-on reticle over its nose."""
    white = mat("MissileWhite", "F2F4F7", rough=0.25)
    red = mat("MissileRed", "E8343A", rough=0.25)
    grey = mat("MissileGrey", "5A6270", rough=0.35, metal=0.4)
    flame = mat("Flame", "FFB02E", rough=0.5, emit=5.0, emit_color="FF7A1A")
    core = mat("FlameCore", "FFF4C2", rough=0.5, emit=8.0)
    ret = mat("Reticle", "FF2D2D", rough=0.3, emit=2.5)
    parts = [
        prim("cylinder", "Body", white, radius=0.17, depth=1.1, vertices=40),
        prim("uv_sphere", "Nose", red, location=(0, 0, 0.55), radius=0.17, segments=40,
             ring_count=20, scale=(1, 1, 2.1)),
        prim("cylinder", "Band", red, location=(0, 0, 0.3), radius=0.175, depth=0.1,
             vertices=40),
        prim("cylinder", "Nozzle", grey, location=(0, 0, -0.6), radius=0.13, depth=0.12,
             vertices=32),
    ]
    parts[2]["no_outline"] = True
    for k in range(4):
        fin = extrude_outline("Fin", [(0.14, -0.52), (0.44, -0.72), (0.44, -0.48),
                                      (0.14, -0.18)], 0.045, red)
        fin.rotation_euler = (math.pi / 2, 0, math.pi / 2 * k + math.pi / 4)
        parts.append(fin)
    fl = prim("cone", "Flame", flame, location=(0, 0, -0.9), radius1=0.0, radius2=0.14,
              depth=0.5, vertices=24)
    fc = prim("cone", "Core", core, location=(0, 0, -0.8), radius1=0.0, radius2=0.08,
              depth=0.3, vertices=24)
    fl["no_outline"] = True
    fc["no_outline"] = True
    parts += [fl, fc]
    axis = (SCREEN_RIGHT * 0.7 + SCREEN_UP * 0.7 + CAM_DIR * 0.15).normalized()
    M = axis.to_track_quat("Z", "Y").to_matrix().to_4x4()
    transform(parts, Matrix.Translation((-0.15, 0, -0.1)) @ M)
    nose = Matrix.Translation((-0.15, 0, -0.1)) @ M @ Vector((0, 0, 0.72))
    tail = Matrix.Translation((-0.15, 0, -0.1)) @ M @ Vector((0, 0, -1.05))
    parts.append(glow("FlameGlow", tail, 0.45, "FF8A1A", strength=3.0))
    # The reticle, facing the camera round the nose.
    rparts = [prim("torus", "Ring", ret, major_radius=0.36, minor_radius=0.03,
                   major_segments=64, minor_segments=10)]
    for k in range(4):
        a = math.pi / 2 * k
        tick = prim("cube", "Tick", ret, location=(math.cos(a) * 0.4, math.sin(a) * 0.4, 0),
                    scale=(0.1 if k % 2 == 0 else 0.022, 0.022 if k % 2 == 0 else 0.1, 0.022))
        rparts.append(tick)
    for o in rparts:
        o["outline_scale"] = 0.5
    centre = nose + CAM_DIR * 0.25
    transform(rparts, Matrix.Translation(centre) @ CAM_DIR.to_track_quat("Z", "Y")
              .to_matrix().to_4x4())
    return parts + rparts


def rewind():
    """Reference 02's glitchy |<< in 3D: a chunky white bar and two left-pointing triangles,
    two bands of it slipped sideways, magenta and cyan copies split off behind."""
    white = mat("RewindWhite", "FFFFFF", rough=0.25, emit=0.35)
    magenta = mat("RewindMagenta", "FF2BD6", rough=0.4, emit=2.5)
    cyan = mat("RewindCyan", "2BF0FF", rough=0.4, emit=2.5)
    shapes = [
        [(-1.0, -0.6), (-0.74, -0.6), (-0.74, 0.6), (-1.0, 0.6)],
        [(-0.74, 0.0), (0.06, -0.6), (0.06, 0.6)],
        [(0.06, 0.0), (0.86, -0.6), (0.86, 0.6)],
    ]
    # Bands of the height: (bottom, top, sideways slip).
    cuts = [(-0.6, -0.34, 0.0), (-0.34, -0.2, -0.12), (-0.2, 0.14, 0.0), (0.14, 0.26, 0.16),
            (0.26, 0.6, 0.0)]
    objs = []
    for y0, y1, slip in cuts:
        for shape in shapes:
            piece = clip_strip(shape, y0, y1)
            if piece:
                objs.append(slab("Strip", [(x + slip, y) for x, y in piece], 0.34, white,
                                 bevel=0.02))
    for m, dx, dz, dy in ((magenta, -0.1, 0.05, 0.14), (cyan, 0.1, -0.05, 0.22)):
        for shape in shapes:
            o = slab("Split", shape, 0.05, m, bevel=0.0, at=(dx, dy, dz))
            o["no_outline"] = True
            objs.append(o)
    for x, z, w, m in ((-1.14, 0.32, 0.16, cyan), (1.0, -0.26, 0.2, magenta),
                       (0.74, 0.7, 0.12, cyan), (-0.46, -0.72, 0.18, magenta)):
        px = prim("cube", "Pixel", m, location=(x, 0.0, z), scale=(w / 2, 0.035, 0.035))
        px["outline_scale"] = 0.5
        objs.append(px)
    return objs


def time_stop():
    """A gold pocket watch, its glass cracked from one blow, the hands stopped."""
    gold = mat("WatchGold", "F2C14E", rough=0.22, metal=0.9)
    face_m = mat("WatchFace", "FFF8E7", rough=0.5, coat=0.2)
    ink = mat("WatchInk", "2A2F45", rough=0.3)
    crack = mat("Crack", "EAF6FF", rough=0.2, emit=1.2, emit_color="BFE6FF")
    objs = []
    case = prim("cylinder", "Case", gold, radius=0.78, depth=0.24, vertices=64,
                rotation=(math.pi / 2, 0, 0))
    bev = case.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.06
    bev.segments = 4
    objs.append(case)
    objs.append(prim("torus", "Bezel", gold, location=(0, -0.12, 0), major_radius=0.74,
                     minor_radius=0.06, major_segments=64, minor_segments=12,
                     rotation=(math.pi / 2, 0, 0)))
    face = prim("cylinder", "Face", face_m, location=(0, -0.125, 0), radius=0.69,
                depth=0.02, vertices=64, rotation=(math.pi / 2, 0, 0))
    face["no_outline"] = True
    objs.append(face)
    for h in range(12):
        a = 2 * math.pi * h / 12
        big = h % 3 == 0
        t = prim("cube", "Tick", ink, location=(math.sin(a) * 0.56, -0.14, math.cos(a) * 0.56),
                 scale=(0.022 if big else 0.012, 0.01, 0.07 if big else 0.04),
                 rotation=(0, a, 0))
        t["no_outline"] = True
        objs.append(t)
    for a_deg, length, width in ((-58, 0.3, 0.035), (62, 0.46, 0.025)):
        a = math.radians(a_deg)
        hand = prim("cube", "Hand", ink, location=(math.sin(a) * length / 2, -0.15,
                                                  math.cos(a) * length / 2),
                    scale=(width, 0.012, length / 2), rotation=(0, a, 0))
        hand["no_outline"] = True
        objs.append(hand)
    cap = prim("cylinder", "Cap", gold, location=(0, -0.16, 0), radius=0.05, depth=0.03,
               vertices=24, rotation=(math.pi / 2, 0, 0))
    cap["no_outline"] = True
    objs.append(cap)
    objs.append(prim("cylinder", "Stem", gold, location=(0, 0, 0.84), radius=0.07,
                     depth=0.12, vertices=24))
    crown = prim("cylinder", "Crown", gold, location=(0, 0, 0.93), radius=0.11, depth=0.1,
                 vertices=24)
    objs.append(crown)
    objs.append(prim("torus", "Bow", gold, location=(0, 0, 1.12), major_radius=0.16,
                     minor_radius=0.04, major_segments=40, minor_segments=10,
                     rotation=(math.pi / 2, 0, 0)))
    # The crack: jagged lines out from one impact point on the glass.
    import random
    rng = random.Random(11)
    hit = Vector((0.22, -0.17, 0.2))
    for k in range(7):
        a = 2 * math.pi * k / 7 + rng.uniform(-0.25, 0.25)
        length = rng.uniform(0.3, 0.55)
        pts = [hit.copy()]
        p = hit.copy()
        for s in range(4):
            aa = a + rng.uniform(-0.45, 0.45)
            step = length / 4
            p = p + Vector((math.cos(aa) * step, 0, math.sin(aa) * step))
            if p.x * p.x + p.z * p.z > 0.66 * 0.66:
                break
            pts.append(p.copy())
        if len(pts) > 1:
            c = tube_path("Crack", pts, 0.011, crack, sides=6)
            c["no_outline"] = True
            objs.append(c)
    ring_pts = []
    for i in range(13):
        a = 2 * math.pi * i / 12
        r = 0.09 + 0.02 * ((i * 7) % 3)
        ring_pts.append(hit + Vector((math.cos(a) * r, 0, math.sin(a) * r)))
    c = tube_path("CrackRing", ring_pts, 0.009, crack, sides=6)
    c["no_outline"] = True
    objs.append(c)
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH * 0.6), 4, "Z")
              @ Matrix.Rotation(math.radians(-8), 4, "X"))
    objs.append(glow("TimeGlow", (0, 0.2, 0.1), 1.3, "7FD8FF", strength=1.2, power=1.6))
    return objs


def chain_lightning():
    """A forked lightning bolt, white-hot with a cyan glow."""
    bolt = mat("Bolt", "F2FDFF", rough=0.2, emit=1.6, emit_color="8FEFFF")
    main = [(0.18, 1.0), (-0.48, -0.02), (-0.06, -0.02), (-0.32, -1.0), (0.5, 0.16),
            (0.06, 0.16), (0.46, 1.0)]
    fork_r = [(0.3, 0.08), (0.78, -0.22), (0.6, -0.26), (0.98, -0.7), (0.46, -0.34),
              (0.62, -0.3), (0.2, 0.0)]
    fork_l = [(-0.2, -0.4), (-0.62, -0.5), (-0.52, -0.58), (-0.92, -0.86), (-0.42, -0.66),
              (-0.5, -0.6), (-0.14, -0.52)]
    objs = [slab("Bolt", main, 0.22, bolt, bevel=0.025),
            slab("ForkR", fork_r, 0.16, bolt, bevel=0.02, at=(0, 0.02, 0)),
            slab("ForkL", fork_l, 0.14, bolt, bevel=0.02, at=(0, 0.02, 0))]
    spark = mat("Spark", "FFFFFF", emit=4.0, emit_color="BFF6FF")
    for x, z, r in ((1.02, -0.74, 0.05), (-0.96, -0.9, 0.045), (0.55, 0.9, 0.04),
                    (-0.52, 0.55, 0.035)):
        s = prim("ico_sphere", "Spark", spark, location=(x, -0.05, z), radius=r,
                 subdivisions=2)
        s["outline_scale"] = 0.5
        objs.append(s)
    objs.append(glow("BoltGlow", (0, 0.2, 0), 1.35, "3BC8FF", strength=1.6, power=1.6))
    return objs


def portals():
    """Two portal rings linked through each other: A cyan, B violet-blue (the pick view's
    colours), each with a swirling translucent middle."""
    ring_a = mat("PortalA", "40E0FF", rough=0.2, emit=1.4)
    ring_b = mat("PortalB", "8068FF", rough=0.2, emit=1.4)
    R, r = 0.56, 0.1
    a = prim("torus", "RingA", ring_a, major_radius=R, minor_radius=r, major_segments=72,
             minor_segments=16)
    a.rotation_euler = (math.pi / 2, 0, 0)
    b = prim("torus", "RingB", ring_b, location=(R, 0, 0), major_radius=R, minor_radius=r,
             major_segments=72, minor_segments=16)
    b.rotation_euler = (math.radians(55), 0, 0)
    da = annulus("SwirlA", 0.0, R - r * 0.5,
                 swirl_material("SwirlAMat", 0.0, R, [(0.0, "E8FDFF"), (0.35, "40E0FF"),
                                                      (1.0, "0A2A60")], 2.0, alpha=0.8,
                                fade=6.0), rings=6)
    da.rotation_euler = (math.pi / 2, 0, 0)
    db = annulus("SwirlB", 0.0, R - r * 0.5,
                 swirl_material("SwirlBMat", 0.0, R, [(0.0, "F0E8FF"), (0.35, "8068FF"),
                                                      (1.0, "1A1050")], 2.0, alpha=0.8,
                                fade=6.0), rings=6)
    db.location = (R, 0, 0)
    db.rotation_euler = (math.radians(55), 0, 0)
    objs = [a, b, da, db]
    transform(objs, Matrix.Translation((-R / 2, 0, 0)))
    transform(objs, Matrix.Rotation(math.radians(-10), 4, "Y"))
    objs.append(glow("PortalGlow", (0, 0.3, 0), 1.4, "4A8BFF", strength=1.2, power=1.6))
    return objs


def steel_ball():
    """Reference 06's green ball: a glossy green steel ball in football panels, dark green
    pentagons and seams."""
    green = mat("SteelGreen", "6BE06A", rough=0.22, metal=0.55, coat=0.9)
    dark = mat("SteelDark", "2E9A44", rough=0.25, metal=0.55, coat=0.9)
    seam = mat("SteelSeam", "123D1C", rough=0.3, metal=0.3)
    R = 0.9
    ball = prim("uv_sphere", "Ball", green, segments=96, ring_count=48, radius=R)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    bm.verts.ensure_lookup_table()
    verts = [v.co.normalized() for v in bm.verts]
    nbrs = {i: set() for i in range(len(verts))}
    for e in bm.edges:
        i, j = e.verts[0].index, e.verts[1].index
        nbrs[i].add(j)
        nbrs[j].add(i)
    bm.free()
    ball.data.materials.append(dark)
    cos_panel = math.cos(math.radians(17.5))
    for p in ball.data.polygons:
        c = p.center.normalized()
        if max(c.dot(v) for v in verts) > cos_panel:
            p.material_index = 1
    objs = [ball]

    def third(i, j, t):
        return verts[i].lerp(verts[j], t)

    def arc(p, q, steps=6):
        return [p.slerp(q, s / steps).normalized() * (R * 1.004) for s in range(steps + 1)]
    seams = []
    for i in range(len(verts)):
        for j in nbrs[i]:
            if i < j:
                seams.append(arc(third(i, j, 1 / 3).normalized(), third(i, j, 2 / 3).normalized()))
            for k in nbrs[i]:
                if j < k and k in nbrs[j]:
                    seams.append(arc(third(i, j, 1 / 3).normalized(),
                                     third(i, k, 1 / 3).normalized()))
    for pts in seams:
        s = tube_path("Seam", pts, 0.018, seam, sides=6)
        s["no_outline"] = True
        objs.append(s)
    transform(objs, Matrix.Rotation(math.radians(20), 4, "Z")
              @ Matrix.Rotation(math.radians(15), 4, "X"))
    objs.append(glow("SteelGlow", (0, 0.3, 0), 1.35, "7CFF7A", strength=0.8, power=1.6))
    return objs


def black_flash():
    """Reference 07: a black lightning spark, jagged spikes of glossy black with red
    outlines and a red flare behind."""
    black = mat("FlashBlack", "0B0B0E", rough=0.12, coat=1.0)
    red = mat("FlashRed", "FF1E3C", rough=0.3, emit=3.0)
    import random
    rng = random.Random(5)

    def burst(n, inner, lengths, kink, seed_turn):
        pts = []
        for k in range(n):
            a = 2 * math.pi * k / n + seed_turn
            w = math.pi / n * 0.85
            L = lengths[k % len(lengths)]
            bend = rng.uniform(-0.12, 0.12)
            pts.append((math.cos(a - w) * inner, math.sin(a - w) * inner))
            ka = a - w * 0.3 + bend
            pts.append((math.cos(ka) * L * kink, math.sin(ka) * L * kink))
            ka2 = a - w * 0.55 + bend
            pts.append((math.cos(ka2) * L * (kink + 0.1), math.sin(ka2) * L * (kink + 0.1)))
            pts.append((math.cos(a + bend * 2) * L, math.sin(a + bend * 2) * L))
            ka3 = a + w * 0.35 + bend
            pts.append((math.cos(ka3) * L * (kink - 0.05), math.sin(ka3) * L * (kink - 0.05)))
        return pts
    lengths = [1.0, 0.62, 0.84, 0.55, 0.95, 0.6, 0.78, 0.66, 0.9]
    spark = slab("Spark", burst(9, 0.26, lengths, 0.5, 0.2), 0.2, black, bevel=0.015)
    spark["ink"] = "FF1E3C"
    spark["outline_scale"] = 1.3
    flare = slab("Flare", burst(9, 0.34, [v * 1.12 for v in lengths], 0.52, 0.2), 0.04, red,
                 bevel=0.0, at=(0, 0.14, 0))
    flare["no_outline"] = True
    objs = [spark, flare]
    for x, z, s, rot in ((1.05, 0.35, 0.12, 0.4), (-0.95, -0.55, 0.1, 1.2),
                         (0.3, -1.02, 0.09, 2.0), (-0.6, 0.9, 0.08, 0.8)):
        shard = slab("Shard", [(0, s), (-s * 0.5, -s * 0.6), (s * 0.6, -s * 0.4)], 0.06, black,
                     bevel=0.0, at=(x, -0.02, z))
        shard.rotation_euler = (math.pi / 2, rot, 0)
        shard["ink"] = "FF1E3C"
        objs.append(shard)
    core = prim("uv_sphere", "Core", red, location=(0, -0.13, 0), radius=0.12, segments=24,
                ring_count=12)
    core["no_outline"] = True
    objs.append(core)
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH * 0.7), 4, "Z"))
    objs.append(glow("FlashGlow", (0, 0.25, 0), 1.35, "FF1E3C", strength=1.6, power=1.4))
    return objs


def black_hole():
    """A black sphere with a glowing accretion disk (tilted toward the viewer, its far side
    lensed up round the top) and a thin bright photon ring."""
    void = mat("Void", "030305", rough=0.35, coat=0.3)
    sphere = prim("uv_sphere", "Hole", void, segments=64, ring_count=32, radius=0.42)
    sphere["no_outline"] = True
    stops = [(0.0, "FFF6D8"), (0.25, "FFC15A"), (0.55, "FF6A2A"), (1.0, "7A1E8C")]
    disk = annulus("Disk", 0.52, 1.18, swirl_material("DiskMat", 0.52, 1.18, stops, 3.5,
                                                      scale=2.5, distortion=12.0, fade=2.0))
    disk.rotation_euler = (math.radians(-8), 0, 0)
    halo = annulus("Halo", 0.44, 0.68, swirl_material("HaloMat", 0.44, 0.68, stops, 2.6,
                                                     scale=3.0, distortion=12.0, fade=1.6))
    face_camera(halo)
    halo.location = -CAM_DIR * 0.05
    ring = prim("torus", "Photon", mat("Photon", "FFF1C9", emit=6.0), major_radius=0.435,
                minor_radius=0.012, major_segments=96, minor_segments=8)
    face_camera(ring)
    ring["no_outline"] = True
    objs = [sphere, disk, halo, ring]
    transform(objs, Matrix.Rotation(math.radians(-16), 4, CAM_DIR))
    objs.append(glow("HoleGlow", -CAM_DIR * 0.3, 1.5, "8A4CFF", strength=0.9, power=1.4))
    return objs


def tiger():
    """A roaring tiger head, front three-quarter: orange with painted black stripes, white
    cheek ruffs and muzzle, angry yellow eyes, the jaw dropped open on four fangs."""
    orange = mat("TigerOrange", "F58A1F", rough=0.45, coat=0.3)
    white = mat("TigerWhite", "FFF6E8", rough=0.5, coat=0.2)
    black = mat("TigerBlack", "17120F", rough=0.5, coat=0.2)
    pink = mat("TigerPink", "F07C8C", rough=0.4)
    mouth_m = mat("TigerMouth", "5A0F1C", rough=0.5)
    tongue_m = mat("TigerTongue", "FF6F86", rough=0.35)
    fang_m = mat("TigerFang", "FFFDF5", rough=0.2, coat=0.6)
    eye_m = mat("TigerEye", "E8F04A", rough=0.1, emit=1.5, emit_color="D8E82A")
    RX, RY, RZ = 0.72, 0.62, 0.64
    head = prim("uv_sphere", "Head", orange, segments=64, ring_count=32, radius=1.0,
                scale=(RX, RY, RZ))
    objs = [head]
    # Ears.
    for side in (-1, 1):
        ear = prim("uv_sphere", "Ear", orange, location=(0.46 * side, 0.08, 0.52), radius=1.0,
                   segments=24, ring_count=12, scale=(0.2, 0.09, 0.22),
                   rotation=(0, 0.35 * side, 0))
        inner = prim("uv_sphere", "EarIn", white, location=(0.46 * side, -0.0, 0.5),
                     radius=1.0, segments=24, ring_count=12, scale=(0.12, 0.04, 0.14),
                     rotation=(0, 0.35 * side, 0))
        inner["no_outline"] = True
        objs += [ear, inner]
    # Cheek ruffs: white fur points out and down each side.
    for side in (-1, 1):
        for k, (z, ang) in enumerate(((-0.02, -10), (-0.2, -32), (-0.38, -55))):
            a = math.radians(ang)
            d = Vector((side * math.cos(a), -0.25, math.sin(a))).normalized()
            tuft = prim("cone", "Ruff", white, radius1=0.16, radius2=0.0, depth=0.4,
                        vertices=20, scale=(1, 0.7, 1))
            point_along(tuft, d)
            tuft.location = Vector((side * 0.56, -0.22, z)) + d * 0.16
            objs.append(tuft)
    # Muzzle: two whisker pads, the chin and the dropped jaw.
    for side in (-1, 1):
        objs.append(prim("uv_sphere", "Pad", white, location=(0.14 * side, -0.56, -0.08),
                         radius=1.0, segments=32, ring_count=16, scale=(0.2, 0.15, 0.14)))
    cavity = prim("uv_sphere", "Mouth", mouth_m, location=(0, -0.48, -0.34), radius=1.0,
                  segments=32, ring_count=16, scale=(0.26, 0.16, 0.2))
    tongue = prim("uv_sphere", "Tongue", tongue_m, location=(0, -0.56, -0.46), radius=1.0,
                  segments=24, ring_count=12, scale=(0.16, 0.1, 0.06))
    tongue["no_outline"] = True
    jaw = prim("uv_sphere", "Jaw", white, location=(0, -0.44, -0.6), radius=1.0,
               segments=32, ring_count=16, scale=(0.25, 0.16, 0.1))
    objs += [cavity, tongue, jaw]
    for side in (-1, 1):
        top = prim("cone", "Fang", fang_m, radius1=0.05, radius2=0.0, depth=0.17, vertices=16)
        point_along(top, (0, -0.15, -1))
        top.location = (0.13 * side, -0.6, -0.26)
        low = prim("cone", "Fang", fang_m, radius1=0.04, radius2=0.0, depth=0.13, vertices=16)
        point_along(low, (0, -0.1, 1))
        low.location = (0.12 * side, -0.56, -0.5)
        for f in (top, low):
            f["outline_scale"] = 0.5
        objs += [top, low]
    nose = prim("uv_sphere", "Nose", pink, location=(0, -0.66, 0.04), radius=1.0,
                segments=24, ring_count=12, scale=(0.11, 0.07, 0.065))
    nose["outline_scale"] = 0.6
    objs.append(nose)
    # Eyes, angry: yellow almonds with slit pupils under slanted black brows, white patches
    # above.
    for side in (-1, 1):
        ex, ez = 0.25 * side, 0.2
        ey = surface_y(ex, ez, RX, RY, RZ)
        patch = prim("uv_sphere", "Patch", white, location=(ex * 1.25, ey + 0.07, ez + 0.2),
                     radius=1.0, segments=24, ring_count=12, scale=(0.08, 0.04, 0.045))
        patch["no_outline"] = True
        eye = prim("uv_sphere", "Eye", eye_m, location=(ex, ey + 0.02, ez), radius=1.0,
                   segments=24, ring_count=12, scale=(0.12, 0.05, 0.065),
                   rotation=(0, 0.38 * side, 0))
        pupil = prim("uv_sphere", "Pupil", black, location=(ex - 0.01 * side, ey - 0.015, ez),
                     radius=1.0, segments=16, ring_count=8, scale=(0.022, 0.03, 0.055))
        eye["outline_scale"] = 0.5
        pupil["no_outline"] = True
        objs += [patch, eye, pupil]
        brow_a = Vector((ex + 0.15 * side, ey - 0.02, ez + 0.14))
        brow_b = Vector((ex * 0.2, ey - 0.02, ez + 0.0))
        objs.append(stripe("Brow", head, brow_a, brow_b, 0.1, black, (0, 0, 1),
                           shape="lens"))
    # Stripes: three on the forehead, three on each cheek side.
    for x, top, bottom, w in ((0.0, 0.64, 0.4, 0.15), (-0.17, 0.6, 0.42, 0.11),
                              (0.17, 0.6, 0.42, 0.11)):
        objs.append(stripe("Fore", head, (x, surface_y(x, top, RX, RY, RZ) - 0.02, top),
                           (x * 0.6, surface_y(x * 0.6, bottom, RX, RY, RZ) - 0.02, bottom),
                           w, black, (1, 0, 0), shape="taper"))
    for side in (-1, 1):
        for z, reach in ((0.36, 0.38), (0.18, 0.4), (0.0, 0.42)):
            a = Vector((0.72 * side, -0.1, z + 0.04))
            b = Vector((reach * side, surface_y(reach, z - 0.06, RX, RY, RZ) - 0.02, z - 0.06))
            objs.append(stripe("Side", head, a, b, 0.13, black, (0, 0, 1), shape="taper"))
    # Whiskers.
    wh = mat("Whisker", "FFFFFF", rough=0.3)
    for side in (-1, 1):
        for k, dz in enumerate((0.05, -0.03, -0.11)):
            p0 = Vector((0.22 * side, -0.62, -0.06 + dz * 0.5))
            p1 = p0 + Vector((0.32 * side, -0.05, dz * 1.4))
            w = tube_path("Whisker", [p0, (p0 + p1) / 2 + Vector((0, 0, 0.03)), p1], 0.008, wh,
                          sides=6)
            w["outline_scale"] = 0.3
            objs.append(w)
    transform(objs, Matrix.Rotation(math.radians(CAM_AZIMUTH * 0.75), 4, "Z")
              @ Matrix.Rotation(math.radians(-8), 4, "X"))
    objs.append(glow("TigerGlow", (0, 0.3, 0), 1.3, "FF9A2A", strength=0.9, power=1.6))
    return objs


BUILDERS = {
    "Magnet": magnet,
    "EaglesEye": hunter_eye,
    "SuperBounce": super_bounce,
    "Ghost": ghost,
    "HeatSeeker": heat_seeker,
    "Rewind": rewind,
    "TimeStop": time_stop,
    "ChainLightning": chain_lightning,
    "Portals": portals,
    "SteelBall": steel_ball,
    "BlackFlash": black_flash,
    "BlackHole": black_hole,
    "GuangdongTiger": tiger,
}


def fit_glows(objects):
    """Shrink any glow that would run past the frame's edge (a hard square cut)."""
    half = CAM_DISTANCE * 18.0 / LENS  # the frame's half-size at the origin's depth
    for o in objects:
        if not o.get("glow"):
            continue
        c = o.matrix_world.translation
        off = math.hypot(c.dot(SCREEN_RIGHT), c.dot(SCREEN_UP))
        near = (CAM_DISTANCE - c.dot(CAM_DIR)) / CAM_DISTANCE
        limit = max(half * near - off, 0.2) * 0.98
        r = o.matrix_world.to_scale().x
        if r > limit:
            o.scale = o.scale * (limit / r)
    bpy.context.view_layer.update()


def build(ult_id):
    common.clear_scene()
    for coll in (bpy.data.materials,):
        for block in list(coll):
            coll.remove(block)
    objects = BUILDERS[ult_id]()
    root, scale = normalise(objects)
    fit_glows(objects)
    outline(objects, scale)
    rig(RARITY_OF[ult_id])
    path = os.path.join(OUT, ult_id + ".png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ids = argv or [i for i in ORDER if i in BUILDERS]
    for ult_id in ids:
        print("icon:", build(ult_id))


if __name__ == "__main__":
    main()
