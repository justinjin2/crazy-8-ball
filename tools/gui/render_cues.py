"""Card art for the Shop's Grand Opening card (docs/prompts/SHOP_LIVELY_PROMPT.md section 6): the
two cues rendered from the real in-game mesh, skins and pieces, on a transparent film.

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python tools/gui/render_cues.py -- go beta ribbons [loose]
        [--frames 32] [--samples 64] [--tip right|left] [--out ~/Desktop/8ball-refs/gui-lively/work/renders]

Writes into --out (never into the repo):
    go_cue.png, go_cue_mask.png        the Grand Opening Cue alone, and its silhouette (white, alpha)
    beta_cue.png, beta_cue_mask.png    the Beta Cue hologram alone (no panels), and its silhouette
    go_ribbons/frame_NN.png            the two gold ribbons (RibbonA/B), one full turn, cue held out
    go_ribbons_loose/frame_NN.png      (job "loose") the same ribbons with a longer pitch and wider,
                                       like 13b's painted loops; not the in-game piece
    layout.json                        canvas size, pixels per stud, tip and butt pixels, camera

Every picture shares one camera and canvas, so the ribbons overlay go_cue.png exactly. The cue
lies horizontal, tip to the right, seen from its side with the camera raised ELEVATION degrees and
turned YAW degrees toward the tip (the tip's end face shows), orthographic.

How each is made (all EEVEE, then post in numpy here: a multi-size bloom, a soft highlight
shoulder, sRGB):
  * go       lit: the skin's maps (textures/grand_opening_*), a clear lacquer coat, a warm key,
             a gold rim from behind above and a magenta rim from behind below; the emissive
             inlays and bursts pushed to EMISSIVE_GO. The cue is opaque, so its alpha is the
             coverage; the bloom outside it becomes alpha by unmult (glow / max channel).
  * beta     a hologram is light, so every material is additive emission (no lighting) and the
             whole picture is unmulted (brightness becomes alpha). Body: the colour map's fill
             and the emissive linework, plus a cyan fresnel rim; the piece's lattice, magenta
             rings and ring edges. No panels, leaders or scan ring.
  * ribbons  the piece's RibbonA/RibbonB as additive gold emission with the cue as a holdout
             (hidden behind it where they pass round the back), sparks drawn in numpy at points
             riding the ribbons (hidden behind the cue too), bloom, unmult. One full turn of the
             screw in --frames frames, so the loop is seamless.
"""
import json
import math
import os
import sys
import tempfile

sys.dont_write_bytecode = True

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CUE = os.path.join(ROOT, 'assets', 'cue')
sys.path.insert(0, CUE)
import cue_common as cc  # noqa: E402

# ---- framing ---------------------------------------------------------------------------------
CUE_PX = 2048            # the cue's length on the canvas, px
CANVAS = (2304, 640)     # canvas px (margin for the glow and the ribbons)
ELEVATION = 50.0         # degrees the camera rises above the cue's side (3/4 read)
YAW = 9.0                # degrees the camera turns toward the tip (its end face shows)
TIP_LEFT = False         # --tip left: the mirror framing (13b draws both cues tip lower-left)
THICKEN = 1.4            # the cue (and its piece) drawn this much thicker across, as 13b paints it
                         # (CuePreview's thumbnails use 1.15); length unchanged

# ---- look ------------------------------------------------------------------------------------
SAMPLES = 64             # EEVEE samples per picture
EMISSIVE_GO = 4.0        # the GO skin's emissive strength here (in game 1.6, pulsing 1.2-2.0)
GO_COAT = (1.0, 0.06)    # lacquer coat weight, roughness
BLOOM = {                # threshold (linear), then (sigma px, weight) layers
    'go': (0.8, [(3, 0.40), (9, 0.36), (24, 0.28), (56, 0.18)]),
    'beta': (0.35, [(3, 0.45), (9, 0.40), (22, 0.32), (50, 0.22)]),
    'ribbons': (0.25, [(2, 0.40), (6, 0.34), (16, 0.28), (34, 0.18)]),
}
SHOULDER = 0.72          # display: linear values above this roll softly to 1 (per channel)

# Beta hologram (linear emission strengths)
BETA_FILL = 1.3         # the colour map's fill, times its alpha
BETA_LINES = 2.6         # the emissive linework (white-hot lines)
BETA_RIM = (0.35, 0.85, 1.0)   # fresnel rim colour (cyan-white)
BETA_RIM_STRENGTH = 2.4
BETA_BACK = 0.45         # back faces (seen through the body) at this share
BETA_LATTICE = 1.1       # the piece's Neon lattice (#3B8CFF, Transparency 0.3 in game)
BETA_RINGS = 0.8         # magenta tori (#FF3FD6)
BETA_RING_EDGES = 0.35   # their pale edges (#FFD9F8)

# Ribbons
RIBBON_STRENGTH = 0.95   # gold emission
RIBBON_CORE = 0.12       # extra white-gold where the ribbon faces the camera
RIBBON_GLITTER = (28.0, 0.22, 3.0)  # Voronoi scale, dot radius (cell units), dot gain
# the ribbons' golds, a little deeper than in game (#FFB83A, #FFD070) to match 13b's orange-gold
RIBBON_COLOURS = {'RibbonA': '#FFA42A', 'RibbonB': '#FFBC4C'}
SPARKS_PER_RIBBON = 150  # sparks riding each ribbon (drawn in numpy)
SPARK_SEED = 8
LOOSE = (3.4, 0.3)       # --loose ribbons: a turn every 3.4 studs, 0.3 off the surface (13b's loops)


def args_get(args, flag, default):
    return type(default)(args[args.index(flag) + 1]) if flag in args else default


# ---- scene -----------------------------------------------------------------------------------

def new_scene(samples):
    scene = cc.clear_scene('CardCues')
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples = samples
    try:
        scene.eevee.use_raytracing = True
    except Exception:
        pass
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = CANVAS
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    s = scene.render.image_settings
    s.file_format = 'OPEN_EXR'
    s.color_mode = 'RGBA'
    s.color_depth = '32'
    world = bpy.data.worlds.new('Env')
    world.use_nodes = True
    wn, wl = world.node_tree.nodes, world.node_tree.links
    bg = next(n for n in wn if n.type == 'BACKGROUND')
    env = wn.new('ShaderNodeTexEnvironment')
    env.image = bpy.data.images.load(os.path.join(CUE, 'vfx', '_env', 'studio_small_09_1k.hdr'))
    wl.new(env.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 0.0
    scene.world = world
    return scene, bg


def place_camera(scene, cue_obj):
    """Orthographic, the cue's axis exactly horizontal on screen, tip to the right (TIP_LEFT: the
    camera on the cue's other side, tip to the left, lit the same way)."""
    e, y = math.radians(ELEVATION), math.radians(YAW)
    centre = cue_obj.matrix_world @ Vector((0, -3.5, 0))
    side = -1.0 if TIP_LEFT else 1.0
    back = Vector((side * math.cos(e) * math.cos(y), math.cos(e) * math.sin(y), math.sin(e)))  # to the camera
    axis = (cue_obj.matrix_world.to_3x3() @ Vector((0, 1, 0))).normalized()           # butt -> tip
    f = -back
    right = side * (axis - f * axis.dot(f)).normalized()
    up = right.cross(f)                 # right-handed: right x up = -f
    assert up.z > 0, up
    data = bpy.data.cameras.new('Cam')
    data.type = 'ORTHO'
    shown = 7.0 * math.sqrt(1 - axis.dot(f) ** 2)
    px_per_stud = CUE_PX / shown
    data.ortho_scale = CANVAS[0] / px_per_stud
    data.clip_start, data.clip_end = 0.01, 100
    cam = bpy.data.objects.new('Cam', data)
    m = Matrix((right, up, -f)).transposed().to_4x4()
    m.translation = centre + back * 20
    cam.matrix_world = m
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam, px_per_stud


def to_px(scene, cam, p):
    from bpy_extras.object_utils import world_to_camera_view
    v = world_to_camera_view(scene, cam, Vector(p))
    return (v.x * CANVAS[0], (1 - v.y) * CANVAS[1])


def light(scene, name, loc, target, energy, size, colour):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.size, data.color = energy, size, colour
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    f = (Vector(target) - Vector(loc)).normalized()
    r = f.cross(Vector((0, 0, 1)))
    r = r.normalized() if r.length > 1e-6 else Vector((1, 0, 0))
    obj.rotation_euler = Matrix((r, r.cross(f), -f)).transposed().to_euler()
    scene.collection.objects.link(obj)
    return obj


def load_cue():
    cue = cc.load_cue_object()
    cue.scale = (THICKEN, 1.0, THICKEN)
    return cue


def render(scene, work, name):
    path = os.path.join(work, name + '.exr')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    img.alpha_mode = 'CHANNEL_PACKED'   # pixels exactly as stored (premultiplied, linear)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].astype(np.float64)


# ---- materials -------------------------------------------------------------------------------

def mat_new(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    out = m.node_tree.nodes.new('ShaderNodeOutputMaterial')
    return m, m.node_tree.nodes, m.node_tree.links, out


def blended(m):
    try:
        m.surface_render_method = 'BLENDED'
    except Exception:
        m.blend_method = 'BLEND'
    m.use_backface_culling = False


def additive(nodes, links, out, colour_socket, strength_socket=None, strength=1.0):
    """Emission added over what is behind (a Transparent BSDF passes it all): light, no cover."""
    em = nodes.new('ShaderNodeEmission')
    links.new(colour_socket, em.inputs['Color'])
    if strength_socket is not None:
        links.new(strength_socket, em.inputs['Strength'])
    else:
        em.inputs['Strength'].default_value = strength
    tr = nodes.new('ShaderNodeBsdfTransparent')
    add = nodes.new('ShaderNodeAddShader')
    links.new(em.outputs[0], add.inputs[0])
    links.new(tr.outputs[0], add.inputs[1])
    links.new(add.outputs[0], out.inputs['Surface'])
    return em


def flat_additive(name, hex_colour, strength):
    m, nodes, links, out = mat_new(name)
    rgb = nodes.new('ShaderNodeRGB')
    rgb.outputs[0].default_value = lin(hex_colour) + (1,)
    additive(nodes, links, out, rgb.outputs[0], strength=strength)
    blended(m)
    return m


def solid_white(name):
    m, nodes, links, out = mat_new(name)
    em = nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (1, 1, 1, 1)
    links.new(em.outputs[0], out.inputs['Surface'])
    return m


def holdout(name):
    m, nodes, links, out = mat_new(name)
    links.new(nodes.new('ShaderNodeHoldout').outputs[0], out.inputs['Surface'])
    return m


def lin(hex_colour):
    c = [int(hex_colour[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def go_material():
    """The in-game SurfaceAppearance preview (CuePreview.cue_material) plus a lacquer coat and a
    stronger emissive."""
    import CuePreview
    skin = json.load(open(os.path.join(CUE, 'skins', 'grand_opening.json')))
    maps = {k: os.path.join(CUE, 'textures', 'grand_opening_%s.png' % k)
            for k in ('color', 'normal', 'roughness', 'metalness', 'emissive')}
    mat, out = CuePreview.cue_material(bpy, maps, skin.get('surface') or {}, 'grand_opening')
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Coat Weight'].default_value = GO_COAT[0]
    bsdf.inputs['Coat Roughness'].default_value = GO_COAT[1]
    out['em_strength'].outputs[0].default_value = EMISSIVE_GO
    return mat


def beta_body_material():
    """The Beta skin as light: fill (colour x its alpha) + linework (colour x emissive mask) +
    a cyan fresnel rim; back faces dimmer."""
    m, nodes, links, out = mat_new('BetaBody')
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'

    def tex(key, colour):
        t = nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(os.path.join(CUE, 'textures', 'beta_%s.png' % key))
        t.image.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
        t.image.alpha_mode = 'CHANNEL_PACKED'
        links.new(uv.outputs['UV'], t.inputs['Vector'])
        return t
    col, emi = tex('color', True), tex('emissive', False)

    def math_node(op, a, b):
        n = nodes.new('ShaderNodeMath')
        n.operation = op
        for i, v in enumerate((a, b)):
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                links.new(v, n.inputs[i])
        return n.outputs[0]

    def mix_rgb(op, a, b, fac=1.0):
        n = nodes.new('ShaderNodeMix')
        n.data_type = 'RGBA'
        n.blend_type = op
        n.inputs['Factor'].default_value = fac
        for key, v in (('A', a), ('B', b)):
            if isinstance(v, tuple):
                n.inputs[key].default_value = v
            else:
                links.new(v, n.inputs[key])
        return n.outputs['Result']

    fill_w = math_node('MULTIPLY', col.outputs['Alpha'], BETA_FILL)
    lines_w = math_node('MULTIPLY', emi.outputs['Color'], BETA_LINES)
    weight = math_node('ADD', fill_w, lines_w)
    body = mix_rgb('MULTIPLY', col.outputs['Color'], (1, 1, 1, 1))
    wv = nodes.new('ShaderNodeCombineColor')
    for i in range(3):
        links.new(weight, wv.inputs[i])
    body = mix_rgb('MULTIPLY', body, wv.outputs[0])
    lw = nodes.new('ShaderNodeLayerWeight')
    lw.inputs['Blend'].default_value = 0.5
    rim_w = math_node('POWER', lw.outputs['Facing'], 2.2)
    rim_w = math_node('MULTIPLY', rim_w, BETA_RIM_STRENGTH)
    rc = nodes.new('ShaderNodeCombineColor')
    for i in range(3):
        links.new(math_node('MULTIPLY', rim_w, BETA_RIM[i]), rc.inputs[i])
    total = mix_rgb('ADD', body, rc.outputs[0])
    geo = nodes.new('ShaderNodeNewGeometry')
    side = math_node('MULTIPLY_ADD', geo.outputs['Backfacing'], BETA_BACK - 1.0)  # 1 front, BACK back
    nodes_side = side.node
    nodes_side.inputs[2].default_value = 1.0
    sv = nodes.new('ShaderNodeCombineColor')
    for i in range(3):
        links.new(side, sv.inputs[i])
    total = mix_rgb('MULTIPLY', total, sv.outputs[0])
    additive(nodes, links, out, total, strength=1.0)
    blended(m)
    return m


def ribbon_material(name, hex_colour):
    """Gold light, a white-gold core where the ribbon faces the camera, a slow sparkler grain
    along it (object space, so it rides the ribbon)."""
    m, nodes, links, out = mat_new(name)
    lw = nodes.new('ShaderNodeLayerWeight')
    lw.inputs['Blend'].default_value = 0.3
    gold = nodes.new('ShaderNodeRGB')
    gold.outputs[0].default_value = lin(hex_colour) + (1,)
    core = nodes.new('ShaderNodeMix')
    core.data_type = 'RGBA'
    core.blend_type = 'ADD'
    links.new(gold.outputs[0], core.inputs['A'])
    core.inputs['B'].default_value = (RIBBON_CORE, RIBBON_CORE * 0.85, RIBBON_CORE * 0.5, 1)
    inv = nodes.new('ShaderNodeMath')
    inv.operation = 'SUBTRACT'
    inv.inputs[0].default_value = 1.0
    links.new(lw.outputs['Facing'], inv.inputs[1])
    links.new(inv.outputs[0], core.inputs['Factor'])
    tc = nodes.new('ShaderNodeTexCoord')
    noise = nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value = 9.0
    noise.inputs['Detail'].default_value = 3.0
    links.new(tc.outputs['Object'], noise.inputs['Vector'])
    grain = nodes.new('ShaderNodeMapRange')
    grain.inputs['From Min'].default_value = 0.3
    grain.inputs['From Max'].default_value = 0.7
    grain.inputs['To Min'].default_value = 0.65 * RIBBON_STRENGTH
    grain.inputs['To Max'].default_value = 1.2 * RIBBON_STRENGTH
    links.new(noise.outputs['Fac'], grain.inputs['Value'])
    # glitter: small hot dots on the ribbon (Voronoi cells' centres), so it reads as a sparkler
    vor = nodes.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = RIBBON_GLITTER[0]
    links.new(tc.outputs['Object'], vor.inputs['Vector'])
    dots = nodes.new('ShaderNodeMapRange')
    dots.inputs['From Min'].default_value = RIBBON_GLITTER[1]
    dots.inputs['From Max'].default_value = 0.0
    dots.inputs['To Min'].default_value = 1.0
    dots.inputs['To Max'].default_value = 1.0 + RIBBON_GLITTER[2]
    links.new(vor.outputs['Distance'], dots.inputs['Value'])
    both = nodes.new('ShaderNodeMath')
    both.operation = 'MULTIPLY'
    links.new(grain.outputs[0], both.inputs[0])
    links.new(dots.outputs[0], both.inputs[1])
    grain = both
    additive(nodes, links, out, core.outputs['Result'], strength_socket=grain.outputs[0])
    blended(m)
    m.use_backface_culling = True     # the ribbon is a thin closed slab: one surface emits, not two
    return m


# ---- post ------------------------------------------------------------------------------------

def blur(img, sigma):
    pad = int(3 * sigma) + 2
    h, w = img.shape[:2]
    p = np.pad(img, ((pad, pad), (pad, pad), (0, 0)))
    fy = np.fft.fftfreq(p.shape[0])[:, None]
    fx = np.fft.rfftfreq(p.shape[1])[None, :]
    g = np.exp(-2 * (math.pi * sigma) ** 2 * (fy ** 2 + fx ** 2))
    out = np.fft.irfft2(np.fft.rfft2(p, axes=(0, 1)) * g[..., None], s=p.shape[:2], axes=(0, 1))
    return out[pad:pad + h, pad:pad + w]


def bloom(rgb, kind):
    thr, layers = BLOOM[kind]
    bright = np.maximum(rgb - thr, 0.0)
    return sum(w * blur(bright, s) for s, w in layers)


def display(x):
    """Linear -> display 0..1: a soft shoulder above SHOULDER (hot colours go toward white), sRGB."""
    k = SHOULDER
    y = np.where(x < k, x, k + (1 - k) * (1 - np.exp(-(x - k) / (1 - k))))
    y = np.clip(y, 0, 1)
    return np.where(y <= 0.0031308, 12.92 * y, 1.055 * np.power(y, 1 / 2.4) - 0.055)


def finish_opaque(raw, kind):
    """An opaque object with glow: alpha = coverage, plus the glow's brightness outside it."""
    rgb, a = raw[..., :3], raw[..., 3:4]
    glow = bloom(rgb, kind)
    d = display(rgb + glow)
    g = np.max(display(glow), axis=2, keepdims=True)
    alpha = np.clip(a + (1 - a) * g, 0, 1)
    colour = np.where(alpha > 1e-4, np.clip(d / np.maximum(alpha, 1e-4), 0, 1), 0)
    return np.concatenate([colour, alpha], 2), a[..., 0]


def finish_light(rgb, kind):
    """Light on black -> straight RGBA by unmult: alpha = the brightest channel."""
    d = display(rgb + bloom(rgb, kind))
    alpha = np.max(d, axis=2, keepdims=True)
    colour = np.where(alpha > 1e-4, np.clip(d / np.maximum(alpha, 1e-4), 0, 1), 0)
    return np.concatenate([colour, alpha], 2)


EDGE_FADE = 24           # px: alpha fades to 0 at the canvas edges (no glow ever ends in a cut)


def save_rgba(path, rgba):
    h, w = rgba.shape[:2]
    ramp = lambda n: np.clip(np.minimum(np.arange(n), np.arange(n)[::-1]) / EDGE_FADE, 0, 1)  # noqa: E731
    rgba = rgba.copy()
    rgba[..., 3] *= ramp(h)[:, None] * ramp(w)[None, :]
    cc.write_png(path, np.round(np.clip(rgba, 0, 1) * 255))
    print('CARD wrote', path)


def save_mask(path, a):
    m = np.ones(a.shape + (4,))
    m[..., 3] = np.clip(a, 0, 1)
    save_rgba(path, m)


# ---- the three jobs --------------------------------------------------------------------------

# GO lights: (name, offset from the cue's middle in the camera's frame (along the cue, screen up,
# toward the camera), watts, (length along the cue, width), colour). Long thin strips, so the
# lacquer shows crisp streaks along the cue and stays deep navy between; the rims sit behind the
# cue above and below its silhouette whatever the elevation.
GO_LIGHTS = [
    ('Key', (0.6, 4.0, 5.0), 260, (14, 0.5), (1.0, 0.95, 0.88)),
    ('Soft', (0.0, 0.8, 6.0), 160, (12, 4.0), (0.45, 0.58, 1.0)),
    ('RimGold', (0.0, 3.6, -4.0), 520, (14, 0.8), (1.0, 0.70, 0.30)),
    ('RimMagenta', (0.0, -3.4, -4.0), 380, (14, 0.8), (1.0, 0.28, 0.85)),
    ('Under', (0.0, -4.0, 3.5), 90, (12, 3.0), (0.5, 0.35, 1.0)),
]
GO_ENV = 0.12            # the studio HDRI's strength (reflections in the gold and the coat)


def setup_go_lights(scene, cue, cam):
    c = cue.matrix_world @ Vector((0, -3.5, 0))
    right, up, toward = (cam.matrix_world.to_3x3() @ Vector(v) for v in ((1, 0, 0), (0, 1, 0), (0, 0, 1)))
    for name, (a, b, d), watts, (length, width), colour in GO_LIGHTS:
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.color, data.shape = watts, colour, 'RECTANGLE'
        data.size, data.size_y = length, width
        ob = bpy.data.objects.new(name, data)
        pos = c + right * a + up * b + toward * d
        f = (c - pos).normalized()
        x = (right - f * right.dot(f)).normalized()      # the strip's length along the cue
        m = Matrix((x, f.cross(x) * -1, -f)).transposed().to_4x4()
        m.translation = pos
        ob.matrix_world = m
        scene.collection.objects.link(ob)


def job_go(out, samples, work):
    scene, bg = new_scene(samples)
    bg.inputs['Strength'].default_value = GO_ENV
    cue = load_cue()
    cam, ppx = place_camera(scene, cue)
    cue.data.materials.clear()
    cue.data.materials.append(go_material())
    setup_go_lights(scene, cue, cam)
    raw = render(scene, work, 'go')
    rgba, cover = finish_opaque(raw, 'go')
    save_rgba(os.path.join(out, 'go_cue.png'), rgba)
    save_mask(os.path.join(out, 'go_cue_mask.png'), cover)
    return scene, cam, cue, ppx


def job_beta(out, samples, work):
    import CuePieces
    scene, _ = new_scene(samples)
    cue = load_cue()
    cam, _ = place_camera(scene, cue)
    cue.data.materials.clear()
    cue.data.materials.append(beta_body_material())
    CuePieces.attach(bpy, 'beta', cue)
    keep = {'Lattice': flat_additive('Lat', '#3B8CFF', BETA_LATTICE),
            'RingTori': flat_additive('Ring', '#FF3FD6', BETA_RINGS),
            'Rings_Ring': flat_additive('Ring2', '#FF3FD6', BETA_RINGS),
            'RingEdges': flat_additive('RingE', '#FFD9F8', BETA_RING_EDGES)}
    parts = [o for o in scene.objects if o.name.startswith('P_')]
    ring_objs = []
    for o in parts:
        hit = next((k for k in keep if o.name[2:].startswith(k)), None)
        if hit is None:          # panels, frames, leaders, the scan ring and disc
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        o.data.materials.clear()
        o.data.materials.append(keep[hit])
        if 'Ring' in hit:
            ring_objs.append(o)
    raw = render(scene, work, 'beta')
    save_rgba(os.path.join(out, 'beta_cue.png'), finish_light(raw[..., :3], 'beta'))
    # the silhouette: the body and the rings, solid white (the lattice hidden)
    white = solid_white('White')
    cue.data.materials.clear()
    cue.data.materials.append(white)
    for o in list(scene.objects):
        if o.name.startswith('P_') and o not in ring_objs:
            o.hide_render = True
    for o in ring_objs:
        o.data.materials.clear()
        o.data.materials.append(white)
    scene.eevee.taa_render_samples = 16
    mask = render(scene, work, 'beta_mask')
    save_mask(os.path.join(out, 'beta_cue_mask.png'), mask[..., 3])


def spark_points(R, sense, phase, rng, pitch, offset):
    """Points riding a ribbon (the CuePiecesUnique helix: a turn every `pitch` studs, R(d) + offset
    off the axis), jittered off it; in the cue's frame at t = 0. Returns positions, sizes, twinkle."""
    n = SPARKS_PER_RIBBON
    d = rng.uniform(0.35, 6.9, n)
    a = sense * 2 * math.pi * d / pitch + phase + rng.normal(0, 0.12, n)
    r = np.array([R(x) for x in d]) + offset + rng.normal(0.0, 0.035, n)
    d = d + rng.normal(0, 0.03, n)
    pos = np.stack([r * np.sin(a), -d, -r * np.cos(a)], 1)
    size = rng.choice([0.6, 0.8, 1.0, 1.4, 2.2], n, p=[0.3, 0.3, 0.2, 0.13, 0.07])
    twinkle = np.stack([rng.integers(1, 4, n), rng.uniform(0, 2 * math.pi, n)], 1)
    return pos, size, twinkle


def draw_sparks(img, pts, scene, cam, cue, R, s):
    """Add glints (a hot core and a 4-point cross) at visible points: a point is hidden when it
    is behind the cue (on the far side of the axis and inside the cue's silhouette)."""
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    to_cam = (cam.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()
    mw = cue.matrix_world
    ppx = CUE_PX / 7.0
    for (p, size, gain) in pts:
        wp = mw @ Vector(p)
        axis_pt = mw @ Vector((0, p[1], 0))
        off = wp - axis_pt
        along_view = off.dot(to_cam)
        perp = (off - to_cam * along_view).length
        if along_view < 0 and perp < R(-p[1]) * THICKEN * 1.02:
            continue
        x, y = to_px(scene, cam, wp)
        x0, x1 = int(max(0, x - 40)), int(min(w, x + 41))
        y0, y1 = int(max(0, y - 40)), int(min(h, y + 41))
        if x0 >= x1 or y0 >= y1:
            continue
        dx, dy = xx[y0:y1, x0:x1] - x, yy[y0:y1, x0:x1] - y
        rad = 1.1 * size * s
        core = np.exp(-(dx ** 2 + dy ** 2) / (2 * rad ** 2))
        arm = 9.0 * size * s
        cross = (np.exp(-np.abs(dx) / arm - dy ** 2 / (2 * (0.5 * s) ** 2)) +
                 np.exp(-np.abs(dy) / arm - dx ** 2 / (2 * (0.5 * s) ** 2)))
        val = gain * (3.0 * core + 0.9 * cross * (size >= 1.0))
        img[y0:y1, x0:x1] += val[..., None] * np.array([1.0, 0.78, 0.42])
    del ppx


def helix_ribbon(name, R, sense, phase, pitch, offset, parent):
    """CuePiecesUnique.grand_opening's ribbon (0.05 wide, 0.012 thick, d 0.3 to 6.95) with its
    pitch and offset as inputs: for the --loose variant, closer to 13b's painted loops."""
    import bmesh
    bm = bmesh.new()
    left, right, n = [], [], 260
    for i in range(n):
        d = 0.3 + (6.95 - 0.3) * i / (n - 1)
        pts = []
        for dd in (d, min(d + 0.01, 6.95)):
            a = sense * 2 * math.pi * dd / pitch + phase
            pts.append(Vector((0, -dd, 0)) + Vector((math.sin(a), 0, math.cos(a))) * (R(dd) + offset))
        a = sense * 2 * math.pi * d / pitch + phase
        radial = Vector((math.sin(a), 0, math.cos(a)))
        across = (pts[1] - pts[0]).normalized().cross(radial).normalized()
        left.append(bm.verts.new(pts[0] - across * 0.025))
        right.append(bm.verts.new(pts[0] + across * 0.025))
    for i in range(n - 1):
        bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    mod = ob.modifiers.new('Solid', 'SOLIDIFY')
    mod.thickness, mod.offset = 0.012, 0.0
    ob.parent = parent
    return ob


def job_ribbons(out, samples, work, frames, loose=False):
    import CuePieces
    R = cc.Envelope(cc.load_shape()[0])
    scene, _ = new_scene(samples)
    cue = load_cue()
    cam, _ = place_camera(scene, cue)
    cue.data.materials.clear()
    cue.data.materials.append(holdout('Hold'))
    rib = {'RibbonA': (1, 0.0, 50.0), 'RibbonB': (-1, math.pi, -50.0)}  # sense, phase, deg/s (the piece)
    mats = {k: ribbon_material(k, v) for k, v in RIBBON_COLOURS.items()}
    pitch, offset = LOOSE if loose else (1.6, 0.16)
    if loose:
        objs = {k: helix_ribbon(k, R, s_, ph, pitch, offset, cue) for k, (s_, ph, _) in rib.items()}
        for k, o in objs.items():
            o.data.materials.append(mats[k])

        def animate(t):     # the joints' Spin: about the cue's axis (Y), RibbonA +50, RibbonB -50 deg/s
            for k, o in objs.items():
                o.rotation_euler = (0, math.radians(rib[k][2] * t), 0)
    else:
        animate = CuePieces.attach(bpy, 'grand_opening', cue)
        for o in animate.parts:
            o.data.materials.clear()
            o.data.materials.append(mats['RibbonA' if 'RibbonA' in o.name else 'RibbonB'])
    rng = np.random.default_rng(SPARK_SEED)
    sparks = {k: spark_points(R, s_, ph, rng, pitch, offset) for k, (s_, ph, _) in rib.items()}
    period = 360.0 / 50.0               # one full turn of each ribbon (seconds in game)
    fdir = os.path.join(out, 'go_ribbons_loose' if loose else 'go_ribbons')
    os.makedirs(fdir, exist_ok=True)
    for i in range(frames):
        t = period * i / frames
        animate(t)
        bpy.context.view_layer.update()
        raw = render(scene, work, 'rib')
        rgb = raw[..., :3].copy()
        pts = []
        for k, (pos, size, tw) in sparks.items():
            ang = math.radians(rib[k][2] * t)    # the joint's spin about the axis (Y)
            ca, sa = math.cos(ang), math.sin(ang)
            for p, sz, (cyc, ph) in zip(pos, size, tw):
                # Spin about +Y through the pivot (0, -3.5, 0): x' = x cos + z sin, z' = -x sin + z cos
                x, y, z = p
                q = (x * ca + z * sa, y, -x * sa + z * ca)
                gain = 0.55 + 0.45 * math.sin(2 * math.pi * cyc * i / frames + ph)
                pts.append((q, sz, gain * 2.2))
        draw_sparks(rgb, pts, scene, cam, cue, R, 1.0)
        save_rgba(os.path.join(fdir, 'frame_%02d.png' % i), finish_light(rgb, 'ribbons'))
    return period


def main():
    global TIP_LEFT
    args = cc.script_args()
    TIP_LEFT = args_get(args, '--tip', 'right') == 'left'
    out = os.path.expanduser(args_get(args, '--out', '~/Desktop/8ball-refs/gui-lively/work/renders'))
    samples = args_get(args, '--samples', SAMPLES)
    frames = args_get(args, '--frames', 32)
    os.makedirs(out, exist_ok=True)
    work = tempfile.mkdtemp(prefix='card_cues_')
    layout = {}
    if 'go' in args:
        scene, cam, cue, ppx = job_go(out, samples, work)
        tip, butt = (cue.matrix_world @ Vector((0, 0, 0))), (cue.matrix_world @ Vector((0, -7, 0)))
        layout.update({'canvas': list(CANVAS), 'px_per_stud': ppx, 'tip_px': to_px(scene, cam, tip),
                       'butt_px': to_px(scene, cam, butt), 'elevation_deg': ELEVATION, 'yaw_deg': YAW,
                       'thicken': THICKEN, 'cue_length_px': CUE_PX,
                       'tip': 'left' if TIP_LEFT else 'right'})
    if 'beta' in args:
        job_beta(out, samples, work)
    if 'ribbons' in args:
        period = job_ribbons(out, samples, work, frames)
        layout['ribbons'] = {'frames': frames, 'game_period_s': period,
                             'note': 'one full turn of both ribbons (RibbonA +50, RibbonB -50 deg/s in game)'}
    if 'loose' in args:
        job_ribbons(out, samples, work, frames, loose=True)
        layout['ribbons_loose'] = {'frames': frames, 'pitch_studs': LOOSE[0], 'offset_studs': LOOSE[1],
                                   'note': 'not the in-game piece: its helix with a longer pitch, wider (13b)'}
    if layout:
        path = os.path.join(out, 'layout.json')
        old = json.load(open(path)) if os.path.isfile(path) else {}
        old.update(layout)
        cc.write_json(path, old)


if __name__ == '__main__':
    main()
