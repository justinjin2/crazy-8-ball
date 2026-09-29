"""Time Stop (ABILITIES_PROMPT 7.7, reference 03): the lens bubble, the clock face on the cloth
and the screen's warp ring and lens edge.

  TimeBubble  a unit UV sphere whose texture is the bubble's warp pattern (fine streaks fanning
              from the poles, faint rings, bright near the rim of each band). In Roblox it is
              drawn with the ForceField material, which lights the edges seen side-on and the
              pattern, so it reads as a refracting lens with a bright rim.
  ClockFace   a flat ring of unit radius in Blender's XY plane (flat on the cloth in Roblox):
              a thin band with sixty ticks inside it, the twelve hours long, white with violet
              edges. It counts the 5 s of stopped time round the frozen cue ball.
  ClockHand   the sweeping hand: a thin needle from the centre out to 0.85 along +Y (Roblox's
              +Z; the look turns it), with a hub.

Rendered images (textures/, transparent, Eevee, Standard view):
  warp_ring.png      the freeze's screen ring: a white-hot ring with a violet glow either side
                     and fine streaks, grown from the centre past the screen's edges.
  lens_edge.png      stopped time's frame (the reference's lens): clear inside, a bright
                     white-violet rim, dark violet out to the corners. Stretched over the screen.

Run headless or through the MCP.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("TimeStop")

VIOLET = (0.62, 0.45, 1.0)
WHITE = (1.0, 1.0, 1.0)


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


# --------------------------------------------------------------------------------------------
# Meshes
# --------------------------------------------------------------------------------------------

def bubble_texture():
    """512 x 256 (u round the sphere, v pole to pole): streaks along v (lines of longitude
    that fan from the poles), faint rings along u, brighter toward the equator."""
    w, h = 512, 256
    rng = np.random.default_rng(3)
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    streak = np.zeros(w)
    for _ in range(90):
        c = rng.uniform(0, 1)
        width = rng.uniform(0.001, 0.004)
        strength = rng.uniform(0.3, 1.0)
        d = np.minimum(np.abs(u - c), 1 - np.abs(u - c))
        streak += strength * np.exp(-(d / width) ** 2)
    streak = np.clip(streak, 0, 1)
    rings = 0.5 + 0.5 * np.cos(v * math.pi * 14)
    rings = rings ** 8
    equator = np.sin(v * math.pi) ** 0.7
    value = np.clip(streak[None, :] * equator[:, None] * 0.9 + rings[:, None] * 0.35, 0, 1)
    img = np.zeros((h, w, 4))
    tint = hex_rgb("E8DEFF")
    img[:, :, 0:3] = value[:, :, None] * tint[None, None, :]
    img[:, :, 3] = 1
    return common.image_from_array("TimeBubbleTex", img,
                                   os.path.join(OUT, "textures", "bubble.png"))


def bubble(mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1.0)
    obj = bpy.context.active_object
    obj.name = "TimeBubble"
    obj.data.name = "TimeBubble"
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def clock_texture():
    """64 x 64: v across a band, violet edges, white core."""
    w, h = 64, 64
    img = np.zeros((h, w, 4))
    for row in range(h):
        v = 1 - (row + 0.5) / h
        c = hex_rgb("B48CFF") if (v < 0.22 or v > 0.78) else hex_rgb("FFFFFF")
        img[row, :] = (*c, 1)
    return common.image_from_array("ClockTex", img, os.path.join(OUT, "textures", "clock.png"))


def new_object(name, bm, mat):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def slab(bm, uv, pts, uvs, depth):
    top = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
    bot = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
    f = bm.faces.new(top)
    for loop, t in zip(f.loops, uvs):
        loop[uv].uv = t
    g = bm.faces.new(list(reversed(bot)))
    for loop, t in zip(g.loops, list(reversed(uvs))):
        loop[uv].uv = t
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        s = bm.faces.new((top[i], top[j], bot[j], bot[i]))
        for loop in s.loops:
            loop[uv].uv = (0.5, 0.5)


def clock_face(mat, depth=0.02, segs=96):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    r_in, r_out = 0.94, 1.0
    for k in range(segs):
        a0 = 2 * math.pi * k / segs
        a1 = 2 * math.pi * (k + 1) / segs
        pts = [(r_in * math.cos(a0), r_in * math.sin(a0)), (r_out * math.cos(a0), r_out * math.sin(a0)),
               (r_out * math.cos(a1), r_out * math.sin(a1)), (r_in * math.cos(a1), r_in * math.sin(a1))]
        slab(bm, uv, pts, [(0.5, 0.05), (0.5, 0.95), (0.5, 0.95), (0.5, 0.05)], depth)
    for k in range(60):
        ang = 2 * math.pi * k / 60
        hour = k % 5 == 0
        r0, r1 = (0.74 if hour else 0.84), 0.9
        half = 0.022 if hour else 0.008
        c, s = math.cos(ang), math.sin(ang)
        px, py = -s * half, c * half
        pts = [(r0 * c - px, r0 * s - py), (r1 * c - px, r1 * s - py),
               (r1 * c + px, r1 * s + py), (r0 * c + px, r0 * s + py)]
        slab(bm, uv, pts, [(0.5, 0.05), (0.5, 0.05), (0.5, 0.95), (0.5, 0.95)], depth * 0.8)
    return new_object("ClockFace", bm, mat)


def clock_hand(mat, depth=0.02):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    # The needle: a long thin kite from just behind the hub to the tip at +Y.
    pts = [(0.0, -0.12), (0.03, 0.0), (0.0, 0.85), (-0.03, 0.0)]
    slab(bm, uv, pts, [(0.5, 0.5), (0.5, 0.1), (0.5, 0.5), (0.5, 0.9)], depth)
    # The hub.
    n = 16
    hub = [(0.06 * math.cos(2 * math.pi * i / n), 0.06 * math.sin(2 * math.pi * i / n)) for i in range(n)]
    slab(bm, uv, hub, [(0.5, 0.5)] * n, depth * 1.2)
    return new_object("ClockHand", bm, mat)


# --------------------------------------------------------------------------------------------
# Rendered images
# --------------------------------------------------------------------------------------------

def radial_material(name, stops, streaks=0.0, streak_scale=60.0):
    """An emission plane coloured and faded by its distance from the centre of its UVs:
    `stops` = [(radius, (r, g, b), alpha), ...] in increasing radius (0.5 = the edge's middle).
    `streaks` darkens and brightens it along thin radial lines."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sub = nt.nodes.new("ShaderNodeVectorMath")
    sub.operation = "SUBTRACT"
    sub.inputs[1].default_value = (0.5, 0.5, 0.0)
    length = nt.nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    ramp_c = nt.nodes.new("ShaderNodeValToRGB")
    ramp_a = nt.nodes.new("ShaderNodeValToRGB")
    for ramp, colour in ((ramp_c, True), (ramp_a, False)):
        els = ramp.color_ramp.elements
        while len(els) > 1:
            els.remove(els[-1])
        for i, (r, rgb, a) in enumerate(stops):
            el = els[0] if i == 0 else els.new(r)
            el.position = r
            el.color = (*rgb, 1) if colour else (a, a, a, 1)
    nt.links.new(tc.outputs["UV"], sub.inputs[0])
    nt.links.new(sub.outputs[0], length.inputs[0])
    nt.links.new(length.outputs["Value"], ramp_c.inputs["Fac"])
    nt.links.new(length.outputs["Value"], ramp_a.inputs["Fac"])
    alpha = ramp_a.outputs["Color"]
    if streaks > 0:
        # Radial streaks: a noise of the angle only.
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        atan = nt.nodes.new("ShaderNodeMath")
        atan.operation = "ARCTAN2"
        nt.links.new(sub.outputs[0], sep.inputs[0])
        nt.links.new(sep.outputs["Y"], atan.inputs[0])
        nt.links.new(sep.outputs["X"], atan.inputs[1])
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(atan.outputs[0], comb.inputs["X"])
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = streak_scale
        nt.links.new(comb.outputs[0], noise.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.3
        mr.inputs["From Max"].default_value = 0.7
        mr.inputs["To Min"].default_value = 1 - streaks
        mr.inputs["To Max"].default_value = 1.0
        nt.links.new(noise.outputs["Fac"], mr.inputs["Value"])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        nt.links.new(alpha, bw.inputs[0])
        nt.links.new(bw.outputs[0], mul.inputs[0])
        nt.links.new(mr.outputs["Result"], mul.inputs[1])
        alpha = mul.outputs[0]
    else:
        bw = nt.nodes.new("ShaderNodeRGBToBW")
        nt.links.new(alpha, bw.inputs[0])
        alpha = bw.outputs[0]
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ramp_c.outputs["Color"], em.inputs["Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "BLENDED"
    except Exception:
        pass
    return mat


def uv_plane(name, mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    vs = [bm.verts.new((0, 0, 0)), bm.verts.new((1, 0, 0)), bm.verts.new((1, 1, 0)), bm.verts.new((0, 1, 0))]
    f = bm.faces.new(vs)
    for loop, t in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop[uv].uv = t
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_plane(path, mat, size):
    scene = bpy.context.scene
    obj = uv_plane("RenderPlane", mat)
    cam_data = bpy.data.cameras.new("OrthoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.0
    cam = bpy.data.objects.new("OrthoCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.5, 0.5, 5)
    scene.camera = cam
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    try:
        scene.eevee.taa_render_samples = 16
    except Exception:
        pass
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.objects.remove(obj, do_unlink=True)


def preview_on_black(name):
    img = bpy.data.images.load(os.path.join(OUT, "textures", name + ".png"))
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    rgb = px[:, :, :3] * px[:, :, 3:4]
    out = np.concatenate([rgb, np.ones((h, w, 1))], axis=2)
    prev = bpy.data.images.new(name + "_prev", width=w, height=h, alpha=True)
    prev.pixels.foreach_set(out.astype(np.float32).ravel())
    prev.filepath_raw = os.path.join(OUT, "renders", name + ".png")
    prev.file_format = "PNG"
    prev.save()


def build():
    common.clear_scene()
    deep = (0.16, 0.08, 0.32)
    # The warp ring: clear, a violet glow rising to a white-hot line at 0.44, falling off.
    render_plane(os.path.join(OUT, "textures", "warp_ring.png"), radial_material("WarpRing", [
        (0.0, VIOLET, 0.0),
        (0.34, VIOLET, 0.0),
        (0.41, VIOLET, 0.4),
        (0.436, WHITE, 1.0),
        (0.446, WHITE, 1.0),
        (0.46, (0.8, 0.68, 1.0), 0.55),
        (0.49, VIOLET, 0.0),
    ], streaks=0.5, streak_scale=80.0), 1024)
    # The lens edge: clear inside, the rim, deep violet out to the corners.
    render_plane(os.path.join(OUT, "textures", "lens_edge.png"), radial_material("LensEdge", [
        (0.0, VIOLET, 0.0),
        (0.36, VIOLET, 0.0),
        (0.43, (0.8, 0.7, 1.0), 0.55),
        (0.465, WHITE, 0.95),
        (0.5, (0.5, 0.35, 0.9), 0.85),
        (0.6, deep, 0.9),
        (0.71, deep, 0.95),
    ], streaks=0.35, streak_scale=40.0), 1024)
    for name in ("warp_ring", "lens_edge"):
        preview_on_black(name)

    common.clear_scene()
    btex = bubble_texture()
    bmat = common.image_material("TimeBubbleMat", btex, emission=1.0)
    b = bubble(bmat)
    ctex = clock_texture()
    cmat = common.image_material("ClockMat", ctex, emission=1.0)
    face = clock_face(cmat)
    hand = clock_hand(cmat)
    face.location.x = 2.5
    hand.location.x = 2.5
    objects = [b, face, hand]
    print("TimeStop triangles:", common.triangles(objects))
    common.render_preview(os.path.join(OUT, "renders", "set.png"), size=640, target=(1.2, 0, 0),
                          distance=6.0, elevation=55, azimuth=0)
    face.location.x = 0
    hand.location.x = 0
    common.export_glb(os.path.join(OUT, "TimeStop.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "TimeStop.blend"))


build()
