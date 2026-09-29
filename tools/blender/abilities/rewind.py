"""Rewind (ABILITIES_PROMPT 7.6, reference 02): the armed dial and the VHS screen images.

  RewindDial   a flat counter-clockwise circular arrow of unit radius in Blender's XY plane
               (flat on the cloth in Roblox): a 300-degree band with an arrowhead at its end
               and twelve clock ticks inside it. Its texture bakes the reference's RGB split
               across the band: a magenta outer edge, a white core, a green inner edge. It
               lies round the cue ball while Rewind is armed and marks the spot the table
               goes back to, turning backward.

Rendered images (textures/, each on a transparent background, Eevee, Standard view):
  icon_flipbook.png   4 x 4 frames (256 px each) of the big white rewind icon (a bar and two
                      left-pointing triangles) cut into scanline strips, with a magenta copy
                      to the left, a green one to the right and a faint cyan one, the split
                      and the tearing (strips knocked sideways) changing every frame.
  static.png          2 x 2 frames (512 px each) of sparse white grain, for a flicker.
  scanlines.png       dark horizontal lines, 4 px apart, over the whole screen.
  tear.png            ragged horizontal tearing bands (white, magenta, green, cyan slivers).
  tracking.png        one VHS tracking-noise band (white streaks, denser at its middle) across
                      an otherwise empty square; it scrolls up the screen.
  fringe.png          the screen's edges split: magenta fading in from the left edge, green
                      from the right.

Run headless or through the MCP.
"""

import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("Rewind")

WHITE = (1.0, 1.0, 1.0)
MAGENTA = (1.0, 0.1, 0.95)
GREEN = (0.15, 1.0, 0.2)
CYAN = (0.1, 0.95, 1.0)


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


# --------------------------------------------------------------------------------------------
# The dial (a mesh with a baked texture)
# --------------------------------------------------------------------------------------------

def dial_texture():
    """64 x 64: v across the band, 0 = inner edge (green), 1 = outer edge (magenta), a white
    core between; the ticks use the white middle."""
    w, h = 64, 64
    img = np.zeros((h, w, 4))
    for row in range(h):
        v = 1 - (row + 0.5) / h
        if v > 0.8:
            c = hex_rgb("FF2AF0")
        elif v < 0.2:
            c = hex_rgb("30FF40")
        else:
            c = hex_rgb("FFFFFF")
        img[row, :] = (*c, 1)
    return common.image_from_array("RewindDialTex", img, os.path.join(OUT, "textures", "dial.png"))


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


def quad(bm, uv, pts, uvs, depth):
    """A thin slab from a flat quad outline `pts` (counter-clockwise from above) with `uvs`."""
    top = [bm.verts.new((x, y, depth / 2)) for x, y in pts]
    bot = [bm.verts.new((x, y, -depth / 2)) for x, y in pts]
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bot)))]
    for f, loop_uvs in ((faces[0], uvs), (faces[1], list(reversed(uvs)))):
        for loop, t in zip(f.loops, loop_uvs):
            loop[uv].uv = t
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        side = bm.faces.new((top[i], top[j], bot[j], bot[i]))
        for loop in side.loops:
            loop[uv].uv = (0.5, 0.5)


def dial(mat, r_in=0.78, r_out=1.0, depth=0.03, segs=48):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    # The band: from 60 degrees round to 360 (300 degrees), counter-clockwise.
    start, sweep = math.radians(70), math.radians(290)
    for k in range(segs):
        a0 = start + sweep * k / segs
        a1 = start + sweep * (k + 1) / segs
        pts = [(r_in * math.cos(a0), r_in * math.sin(a0)), (r_out * math.cos(a0), r_out * math.sin(a0)),
               (r_out * math.cos(a1), r_out * math.sin(a1)), (r_in * math.cos(a1), r_in * math.sin(a1))]
        quad(bm, uv, pts, [(0.5, 0.02), (0.5, 0.98), (0.5, 0.98), (0.5, 0.02)], depth)
    # The arrowhead at the band's end, pointing on counter-clockwise.
    a = start + sweep
    mid_r = (r_in + r_out) / 2
    wide = (r_out - r_in) * 1.25
    tangent = (-math.sin(a), math.cos(a))
    radial = (math.cos(a), math.sin(a))
    base_c = (mid_r * radial[0], mid_r * radial[1])
    tip = (base_c[0] + tangent[0] * 0.32, base_c[1] + tangent[1] * 0.32)
    outer = (base_c[0] + radial[0] * wide, base_c[1] + radial[1] * wide)
    inner = (base_c[0] - radial[0] * wide, base_c[1] - radial[1] * wide)
    tri = [inner, outer, tip]
    top = [bm.verts.new((x, y, depth / 2)) for x, y in tri]
    bot = [bm.verts.new((x, y, -depth / 2)) for x, y in tri]
    f = bm.faces.new(top)
    for loop, t in zip(f.loops, [(0.5, 0.02), (0.5, 0.98), (0.5, 0.5)]):
        loop[uv].uv = t
    g = bm.faces.new(list(reversed(bot)))
    for loop in g.loops:
        loop[uv].uv = (0.5, 0.5)
    for i in range(3):
        j = (i + 1) % 3
        s = bm.faces.new((top[i], top[j], bot[j], bot[i]))
        for loop in s.loops:
            loop[uv].uv = (0.5, 0.5)
    # Twelve clock ticks inside the band (the quarters longer).
    for k in range(12):
        ang = 2 * math.pi * k / 12
        long = k % 3 == 0
        r0, r1 = (0.5 if long else 0.6), 0.7
        half = 0.035 if long else 0.022
        c, s = math.cos(ang), math.sin(ang)
        px, py = -s * half, c * half
        pts = [(r0 * c - px, r0 * s - py), (r1 * c - px, r1 * s - py),
               (r1 * c + px, r1 * s + py), (r0 * c + px, r0 * s + py)]
        quad(bm, uv, pts, [(0.5, 0.5)] * 4, depth * 0.8)
    return new_object("RewindDial", bm, mat)


# --------------------------------------------------------------------------------------------
# The rendered images
# --------------------------------------------------------------------------------------------

def emission_material(name, colour, alpha=1.0):
    """Unlit colour at `alpha` (a transparent-mixed emission, Standard view: exact colour)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*colour, 1)
    em.inputs["Strength"].default_value = 1.0
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = alpha
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "BLENDED"
    except Exception:
        pass
    return mat


def flat_mesh(name, rects, mat, z=0.0):
    """One object of axis-aligned rectangles [(x0, y0, x1, y1)] at height z."""
    bm = bmesh.new()
    for x0, y0, x1, y1 in rects:
        vs = [bm.verts.new((x0, y0, z)), bm.verts.new((x1, y0, z)),
              bm.verts.new((x1, y1, z)), bm.verts.new((x0, y1, z))]
        bm.faces.new(vs)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_setup(size_x, size_y, ortho_w, centre, samples=16):
    """An orthographic camera looking straight down at `centre`, `ortho_w` units across."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("OrthoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_w
    cam = bpy.data.objects.new("OrthoCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (centre[0], centre[1], 10)
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    engine = scene.render.engine
    for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = name
            engine = name
            break
        except TypeError:
            continue
    try:
        scene.eevee.taa_render_samples = samples
    except Exception:
        pass
    scene.render.resolution_x = size_x
    scene.render.resolution_y = size_y
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    return cam, engine


def render_to(path, objects, size, ortho_w, centre, samples=16):
    cam, _ = render_setup(size[0], size[1], ortho_w, centre, samples)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def icon_rows(rng, strips, height, tear_rows, tear_shift, rough):
    """The rewind icon (a bar and two left-pointing triangles) as horizontal strips with gaps:
    [(y0, y1, [(x0, x1), ...])], centred on the origin, `height` tall. `tear_rows` strips are
    knocked sideways by up to `tear_shift`; every left edge is roughened by up to `rough`."""
    half = height / 2
    bar = (-0.37, -0.285)
    tris = [(-0.285, 0.035), (0.025, 0.345)]  # (tip x, base x)
    rows = []
    step = height / strips
    torn = set(rng.sample(range(strips), tear_rows))
    for i in range(strips):
        y0 = -half + i * step
        y1 = y0 + step * 0.72  # the rest is the scanline gap
        yc = (y0 + y1) / 2
        k = abs(yc) / half  # 0 at the middle, 1 at the top and bottom
        segs = [bar]
        for tip, base in tris:
            segs.append((tip + k * (base - tip), base))
        shift = rng.uniform(-tear_shift, tear_shift) if i in torn else 0.0
        out = []
        for x0, x1 in segs:
            x0 += rng.uniform(0, rough)
            out.append((x0 + shift, x1 + shift + rng.uniform(-rough, rough) * 0.5))
        rows.append((y0, y1, out))
    return rows


def icon_flipbook():
    """16 frames in a 4 x 4 grid of unit cells, rendered at once (1024 px)."""
    rng = random.Random(2)
    mats = {
        "white": emission_material("IconWhite", WHITE, 1.0),
        "magenta": emission_material("IconMagenta", MAGENTA, 0.95),
        "green": emission_material("IconGreen", GREEN, 0.95),
        "cyan": emission_material("IconCyan", CYAN, 0.45),
    }
    objects = []
    for f in range(16):
        col, row = f % 4, f // 4
        cx, cy = col + 0.5, 3.5 - row  # frame 0 at the top left
        big = f % 5 == 2  # every few frames a hard glitch: a wider split and more tearing
        split = rng.uniform(0.018, 0.03) if not big else rng.uniform(0.045, 0.06)
        rows = icon_rows(rng, 26, 0.46, 3 if not big else 7, 0.05 if not big else 0.12, 0.012)
        layers = [("magenta", -split, 0.0, 0.00), ("green", split, 0.0, 0.01),
                  ("cyan", -split * 0.5, split * 0.3, 0.005), ("white", 0.0, 0.0, 0.02)]
        for name, dx, dy, z in layers:
            rects = []
            for y0, y1, segs in rows:
                for x0, x1 in segs:
                    rects.append((cx + x0 + dx, cy + y0 + dy, cx + x1 + dx, cy + y1 + dy))
            objects.append(flat_mesh(f"Icon{f}_{name}", rects, mats[name], z))
    render_to(os.path.join(OUT, "textures", "icon_flipbook.png"), objects, (1024, 1024), 4.0, (2, 2))


def noise_material(name, seed, scale, threshold):
    """Sparse white grain: a snapped white noise, shown where it passes `threshold`."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    snap = nt.nodes.new("ShaderNodeVectorMath")
    snap.operation = "SNAP"
    snap.inputs[1].default_value = (1 / scale, 1 / (scale * 0.6), 1)  # grains a little tall
    add = nt.nodes.new("ShaderNodeVectorMath")
    add.operation = "ADD"
    add.inputs[1].default_value = (seed * 17.3, seed * 5.1, seed)
    wn = nt.nodes.new("ShaderNodeTexWhiteNoise")
    wn.noise_dimensions = "3D"
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = threshold
    ramp.inputs["From Max"].default_value = 1.0
    ramp.inputs["To Min"].default_value = 0.0
    ramp.inputs["To Max"].default_value = 1.0
    ramp.clamp = True
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tc.outputs["UV"], snap.inputs[0])
    nt.links.new(snap.outputs[0], add.inputs[0])
    nt.links.new(add.outputs[0], wn.inputs["Vector"])
    nt.links.new(wn.outputs["Value"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "BLENDED"
    except Exception:
        pass
    return mat


def uv_plane(name, x0, y0, x1, y1, mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    vs = [bm.verts.new((x0, y0, 0)), bm.verts.new((x1, y0, 0)),
          bm.verts.new((x1, y1, 0)), bm.verts.new((x0, y1, 0))]
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


def static_flipbook():
    objects = []
    for f in range(4):
        col, row = f % 2, f // 2
        mat = noise_material(f"Static{f}", f + 1, 200, 0.82)
        objects.append(uv_plane(f"Static{f}", col, 1 - row, col + 1, 2 - row, mat))
    render_to(os.path.join(OUT, "textures", "static.png"), objects, (1024, 1024), 2.0, (1, 1), samples=1)


def scanlines():
    mat = emission_material("Scan", (0, 0, 0), 0.55)
    rects = []
    n = 256  # one line every 4 px at 1024
    for i in range(n):
        y0 = i / n
        rects.append((0, y0, 1, y0 + 0.45 / n))
    objects = [flat_mesh("Scanlines", rects, mat)]
    render_to(os.path.join(OUT, "textures", "scanlines.png"), objects, (1024, 1024), 1.0, (0.5, 0.5), samples=1)


def tear():
    rng = random.Random(5)
    mats = [(emission_material("TearWhite", WHITE, 0.8), 3), (emission_material("TearMagenta", MAGENTA, 0.75), 2),
            (emission_material("TearGreen", GREEN, 0.75), 2), (emission_material("TearCyan", CYAN, 0.6), 1)]
    buckets = [[] for _ in mats]
    weights = [w for _, w in mats]
    for _ in range(9):  # bands
        yc = rng.uniform(0.04, 0.96)
        band_h = rng.uniform(0.006, 0.03)
        x = rng.uniform(-0.1, 0.3)
        while x < 1.05:
            length = rng.uniform(0.03, 0.35)
            gap = rng.uniform(0.0, 0.12)
            h = band_h * rng.uniform(0.25, 1.0)
            y0 = yc + rng.uniform(-band_h, band_h) * 0.5
            k = rng.choices(range(len(mats)), weights)[0]
            buckets[k].append((x, y0, x + length, y0 + h))
            x += length + gap
    objects = []
    for i, (mat, _) in enumerate(mats):
        if buckets[i]:
            objects.append(flat_mesh(f"Tear{i}", buckets[i], mat, z=0.001 * i))
    render_to(os.path.join(OUT, "textures", "tear.png"), objects, (1024, 1024), 1.0, (0.5, 0.5), samples=4)


def tracking():
    rng = random.Random(9)
    levels = [emission_material("TrackA", WHITE, 0.25), emission_material("TrackB", WHITE, 0.55),
              emission_material("TrackC", WHITE, 0.9)]
    haze = emission_material("TrackHaze", (0.85, 0.85, 0.9), 0.18)
    buckets = [[] for _ in levels]
    centre, spread = 0.5, 0.07
    for _ in range(900):
        y = centre + rng.gauss(0, spread * 0.55)
        if abs(y - centre) > spread:
            continue
        x = rng.uniform(-0.1, 1.0)
        length = rng.uniform(0.01, 0.12) * (1.6 if abs(y - centre) < spread * 0.3 else 1.0)
        h = rng.uniform(0.0015, 0.0045)
        near = 1 - abs(y - centre) / spread
        k = min(2, int(near * 3 * rng.uniform(0.6, 1.2)))
        buckets[k].append((x, y, x + length, y + h))
    objects = [flat_mesh("TrackHaze", [(0, centre - spread * 0.6, 1, centre + spread * 0.6)], haze)]
    for i, mat in enumerate(levels):
        objects.append(flat_mesh(f"Track{i}", buckets[i], mat, z=0.001 * (i + 1)))
    render_to(os.path.join(OUT, "textures", "tracking.png"), objects, (1024, 1024), 1.0, (0.5, 0.5), samples=4)


def gradient_material(name, colour, reverse, reach):
    """`colour` at the plane's left edge (right when `reverse`) fading out by `reach` of it."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    if reverse:
        mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = 1 - reach, 1.0
    else:
        mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = reach, 0.0
    mr.inputs["To Min"].default_value, mr.inputs["To Max"].default_value = 0.0, 0.85
    mr.clamp = True
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*colour, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tc.outputs["UV"], sep.inputs[0])
    nt.links.new(sep.outputs["X"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    try:
        mat.surface_render_method = "BLENDED"
    except Exception:
        pass
    return mat


def fringe():
    objects = [
        uv_plane("FringeL", 0, 0, 1, 1, gradient_material("FringeMagenta", MAGENTA, False, 0.14)),
        uv_plane("FringeR", 0, 0, 1, 1, gradient_material("FringeGreen", GREEN, True, 0.14)),
    ]
    objects[1].location.z = 0.001
    render_to(os.path.join(OUT, "textures", "fringe.png"), objects, (512, 512), 1.0, (0.5, 0.5), samples=4)


def preview_on_black(name):
    """A copy of textures/<name>.png over black in renders/, to look at."""
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
    icon_flipbook()
    static_flipbook()
    scanlines()
    tear()
    tracking()
    fringe()
    for name in ("icon_flipbook", "static", "tear", "tracking", "fringe"):
        preview_on_black(name)

    common.clear_scene()
    tex = dial_texture()
    mat = common.image_material("RewindDialMat", tex, emission=1.0, alpha=False, roughness=0.6)
    d = dial(mat)
    print("RewindDial triangles:", common.triangles([d]))
    common.render_preview(os.path.join(OUT, "renders", "dial.png"), size=512, distance=3.2,
                          elevation=70, azimuth=0)
    common.export_glb(os.path.join(OUT, "Rewind.glb"), [d])
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Rewind.blend"))


build()
