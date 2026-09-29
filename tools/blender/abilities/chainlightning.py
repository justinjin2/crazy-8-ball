"""Chain Lightning (ABILITIES_PROMPT 7.8, reference 04): the branching bolts, and the crackle,
glow and spark images.

  Bolt1..Bolt4       four jagged lightning variants with side forks (the look swaps them every
  (Core and Glow)    couple of frames so a bolt flickers). Each is two meshes on the same path:
                     BoltNCore, a thin white-hot tube, and BoltNGlow, a fatter shell the look
                     draws cyan and see-through. Unit length along Blender X (Roblox X), flat in
                     Blender's XY plane (Roblox's XZ: the look rolls it to face the camera), its
                     bounding box centred on the origin (the jags are scaled to the same reach
                     either side) so a MeshPart's centre is the bolt's middle. The forks and the
                     tips taper. The glow follows every other point of the core's path (it is
                     soft and wide; half the triangles).

Rendered images (textures/, transparent, Eevee, Standard view):
  crackle_flipbook.png   4 x 4 frames (256 px each) of short blue-white arcs crackling round a
                         ball's outline: the charged ball, the struck balls and the armed cue ball.
  glow.png               a soft round blue glow, white in the middle (the cloth's flash, halos).
  spark.png              a small four-point star (the struck balls' sparks).

Run headless or through the MCP.
"""

import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("ChainLightning")

WHITE = (1.0, 1.0, 1.0)
CYAN = (0.45, 0.85, 1.0)
BLUE = (0.12, 0.42, 1.0)

CORE_R = 0.008
GLOW_R = 0.026
REACH = 0.09  # the jags' reach either side of the axis, as a share of the length


# --------------------------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------------------------

def jagged(rng, a, b, steps, rough):
    """Midpoint displacement from a to b (2D): `steps` rounds, each halving the segments and
    pushing each new midpoint sideways by up to `rough` x the segment's length."""
    pts = [np.array(a, float), np.array(b, float)]
    for _ in range(steps):
        out = [pts[0]]
        for p, q in zip(pts[:-1], pts[1:]):
            d = q - p
            n = np.array([-d[1], d[0]])
            mid = (p + q) / 2 + n * rng.uniform(-rough, rough)
            out += [mid, q]
        pts = out
    return pts


def bolt_paths(seed):
    """The main path (list of (point, radius share)) and its forks, before centring."""
    rng = np.random.default_rng(seed)
    main = jagged(rng, (-0.5, 0.0), (0.5, 0.0), 6, 0.26)
    n = len(main)
    # Calmer toward the tips, so each end meets its ball.
    for i, p in enumerate(main):
        t = i / (n - 1)
        main[i] = np.array([p[0], p[1] * min(1.0, 5 * min(t, 1 - t))])
    # Radius share along the main path: full through the middle, tapering at the tips.
    main_r = [min(1.0, 0.35 + 1.3 * min(i, n - 1 - i) / (n - 1)) for i in range(n)]
    forks = []
    count = rng.integers(5, 8)
    picks = sorted(rng.choice(np.arange(6, n - 10), size=count, replace=False))
    side = 1 if rng.uniform() < 0.5 else -1
    for i in picks:
        p = main[i]
        d = main[min(i + 2, n - 1)] - main[max(i - 2, 0)]
        d = d / (np.linalg.norm(d) + 1e-9)
        angle = rng.uniform(0.45, 0.9) * side
        side = -side
        c, s = math.cos(angle), math.sin(angle)
        fd = np.array([c * d[0] - s * d[1], s * d[0] + c * d[1]])
        length = rng.uniform(0.12, 0.32)
        end = p + fd * length
        path = jagged(rng, p, end, 3, 0.3)
        m = len(path)
        forks.append((path, [0.55 * (1 - k / (m - 1)) + 0.12 for k in range(m)]))
        # A twig off the longer forks.
        if length > 0.18:
            j = m // 2
            q = path[j]
            twig_angle = -angle * 0.8
            c, s = math.cos(twig_angle), math.sin(twig_angle)
            td = np.array([c * fd[0] - s * fd[1], s * fd[0] + c * fd[1]])
            tpath = jagged(rng, q, q + td * length * 0.45, 2, 0.3)
            tm = len(tpath)
            forks.append((tpath, [0.3 * (1 - k / (tm - 1)) + 0.1 for k in range(tm)]))
    return (main, main_r), forks


def centred(main, forks):
    """Scale each side's sideways offsets so both reach exactly REACH (the bounding box is then
    centred on the axis), and clip anything past the ends back inside them."""
    pts = list(main[0]) + [p for path, _ in forks for p in path]
    ys = np.array([p[1] for p in pts])
    up, down = ys.max(), -ys.min()

    def fix(p):
        x = min(max(p[0], -0.5), 0.5)
        y = p[1] * (REACH / up if p[1] > 0 else REACH / down)
        return np.array([x, y])

    main = ([fix(p) for p in main[0]], main[1])
    forks = [([fix(p) for p in path], r) for path, r in forks]
    return main, forks


# --------------------------------------------------------------------------------------------
# Meshes
# --------------------------------------------------------------------------------------------

def tube(name, path, radii, r, mat, sides):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = r
    curve.bevel_resolution = max(0, sides // 4 - 1)
    curve.use_fill_caps = True
    curve.materials.append(mat)
    spline = curve.splines.new("POLY")
    spline.points.add(len(path) - 1)
    for pt, (p, share) in zip(spline.points, zip(path, radii)):
        pt.co = (p[0], p[1], 0.0, 1.0)
        pt.radius = share
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def join_mesh(name, objs, mat):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def bolt(index, seed, core_mat, glow_mat):
    main, forks = bolt_paths(seed)
    main, forks = centred(main, forks)
    made = []
    for suffix, r, mat, sides in (("Core", CORE_R, core_mat, 4), ("Glow", GLOW_R, glow_mat, 4)):
        # The glow is soft and wide: every other point is enough (half the triangles).
        thin = (lambda xs: list(xs[::2]) + ([xs[-1]] if len(xs) % 2 == 0 else [])) \
            if suffix == "Glow" else (lambda xs: list(xs))
        parts = [tube("m", thin(main[0]), thin(main[1]), r, mat, sides)]
        for path, radii in forks:
            if len(path) >= 3:
                parts.append(tube("f", thin(path), thin(radii), r, mat, sides))
            else:
                parts.append(tube("f", path, radii, r, mat, sides))
        made.append(join_mesh("Bolt%d%s" % (index, suffix), parts, mat))
    return made


def solid_texture(name, colour):
    img = np.ones((8, 8, 4))
    img[:, :, 0:3] = colour
    return common.image_from_array(name, img, os.path.join(OUT, "textures", name + ".png"))


# --------------------------------------------------------------------------------------------
# Rendered images
# --------------------------------------------------------------------------------------------

def emission_material(name, colour, alpha=1.0):
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


def render_setup(size_x, size_y, ortho_w, centre, samples=16):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("OrthoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_w
    cam = bpy.data.objects.new("OrthoCam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (centre[0], centre[1], 10)
    cam.rotation_euler = (0, 0, 0)
    scene.camera = cam
    for name in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = name
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
    return cam


def render_to(path, objects, size, ortho_w, centre, samples=16):
    cam = render_setup(size[0], size[1], ortho_w, centre, samples)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)


def glow_layers(name, path, radii, width, z, mats):
    """A path drawn as a white core over two cyan-blue glow layers."""
    objs = []
    for k, (mat, scale) in enumerate(mats):
        o = tube("%s%d" % (name, k), path, radii, width * scale, mat, 6)
        o.location.z = z - k * 0.01
        objs.append(o)
    return objs


def crackle_flipbook():
    """16 frames in a 4 x 4 grid (1 unit each, frame (0, 0) top left): 2-4 arcs hugging a
    circle of radius 0.3 (the ball's outline at the frame's middle), leaping off it."""
    rng = np.random.default_rng(11)
    mats = [(emission_material("CrWhite", WHITE, 1.0), 1.0),
            (emission_material("CrCyan", CYAN, 0.55), 2.6),
            (emission_material("CrBlue", BLUE, 0.22), 6.0)]
    objects = []
    for f in range(16):
        cx, cy = f % 4 + 0.5, 3.5 - f // 4
        for _ in range(rng.integers(2, 5)):
            a0 = rng.uniform(0, 2 * math.pi)
            span = rng.uniform(0.6, 1.6)
            lift = rng.uniform(0.04, 0.16)
            steps = 7
            pts = []
            for k in range(steps + 1):
                t = k / steps
                a = a0 + span * t
                r = 0.3 + lift * math.sin(math.pi * t) + rng.uniform(-0.02, 0.02)
                pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
            path = []
            for p, q in zip(pts[:-1], pts[1:]):
                seg = jagged(rng, p, q, 2, 0.3)
                path += seg[:-1]
            path.append(np.array(pts[-1]))
            m = len(path)
            radii = [0.4 + 0.6 * math.sin(math.pi * k / (m - 1)) for k in range(m)]
            objects += glow_layers("cr", path, radii, 0.006, 1.0, mats)
    render_to(os.path.join(OUT, "textures", "crackle_flipbook.png"), objects, (1024, 1024), 4.0,
              (2, 2))


def radial_image(name, size, stops):
    """A round image: colour and alpha by distance from the centre (0 middle, 1 edge)."""
    c = (np.arange(size) + 0.5) / size * 2 - 1
    d = np.sqrt(c[None, :] ** 2 + c[:, None] ** 2)
    img = np.zeros((size, size, 4))
    xs = [s[0] for s in stops]
    for ch in range(4):
        img[:, :, ch] = np.interp(d, xs, [s[1][ch] for s in stops])
    return common.image_from_array(name, img, os.path.join(OUT, "textures", name + ".png"))


def star_image(name, size):
    """A four-point star: two thin bright crossed streaks over a small glow."""
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = c[None, :], c[:, None]
    d = np.sqrt(x ** 2 + y ** 2)
    streak = np.exp(-(np.abs(y) / 0.035) ** 1.5) * np.clip(1 - np.abs(x), 0, 1) ** 2
    streak = np.maximum(streak, np.exp(-(np.abs(x) / 0.035) ** 1.5) * np.clip(1 - np.abs(y), 0, 1) ** 2)
    core = np.exp(-(d / 0.18) ** 2)
    a = np.clip(streak + core * 0.8, 0, 1)
    img = np.zeros((size, size, 4))
    white = np.clip(core * 1.4, 0, 1)
    for ch, (lo, hi) in enumerate(zip(CYAN, WHITE)):
        img[:, :, ch] = lo + (hi - lo) * np.maximum(white, streak ** 0.5)
    img[:, :, 3] = a
    return common.image_from_array(name, img, os.path.join(OUT, "textures", name + ".png"))


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
    crackle_flipbook()
    radial_image("glow", 256, [
        (0.0, (1.0, 1.0, 1.0, 1.0)),
        (0.12, (0.75, 0.92, 1.0, 0.9)),
        (0.35, (0.3, 0.65, 1.0, 0.45)),
        (0.7, (0.12, 0.35, 1.0, 0.12)),
        (1.0, (0.1, 0.3, 1.0, 0.0)),
    ])
    star_image("spark", 128)
    for name in ("crackle_flipbook", "glow", "spark"):
        preview_on_black(name)

    common.clear_scene()
    core_mat = common.image_material("BoltCore", solid_texture("core", WHITE), emission=1.0)
    glow_mat = common.image_material("BoltGlow", solid_texture("glowshell", CYAN), emission=1.0)
    objects = []
    for i, seed in enumerate((21, 34, 55, 89), start=1):
        made = bolt(i, seed, core_mat, glow_mat)
        for o in made:
            o.location.y = (i - 2.5) * 0.35
        objects += made
    print("ChainLightning triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 4) for v in o.dimensions))
    for o in objects:
        if o.name.endswith("Glow"):
            o.hide_render = True
    common.render_preview(os.path.join(OUT, "renders", "bolts.png"), size=768, distance=2.2,
                          elevation=89, azimuth=0)
    for o in objects:
        o.hide_render = False
    for o in objects:
        o.location = (0, 0, 0)
    common.export_glb(os.path.join(OUT, "ChainLightning.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "ChainLightning.blend"))


build()
