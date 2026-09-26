"""The map's skybox: a sky gradient and stylised cumulus clouds, rendered in Blender to the six
faces of a Roblox Sky (brief section 9, Stage 4; Spec section 2 for the colours).

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_sky.py            # Day
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_sky.py -- sunset  # (Stage 7)

Writes textures/sky_<light>_<Face>.png (1024 square) and checkpoints/sky/<light>-cross.png, a
preview with the faces unfolded round the front.

The clouds are "toon" emission: each point's colour comes from its normal against the sun (the
Spec's Day sun, so they are lit from the side the real sun is on) and its height in the cloud,
so the render has no noise, needs no denoising and the faces meet without seams. The same
cloud scene (same seed) renders the sunset sky in Stage 7, so the swap reads as a colour
change. No sun is painted: Roblox draws it.

Face directions (docs/STUDIO_NOTES.md "Sky faces", tested): Ft looks toward Roblox -Z, Bk +Z,
Rt -X, Lf +X, all upright; Up has its image top toward +X and its right toward -Z; Dn its top
toward -X and its right toward -Z. Roblox (x, y, z) is Blender (x, -z, y) (map_common.rb).
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_common as mc  # noqa: E402

SEED = 4026
SIZE = 1024  # each face; Cycles' samples antialias it (Roblox shows 1024 at most)
SAMPLES = 48

P = {
    'radius': 1000.0,  # the dome the clouds sit on (Blender units; only angles matter)
    'count': 20,
    # (lowest, highest elevation in degrees, share of the clouds): most low down, as in the art.
    'bands': ((1.0, 8.0, 0.45), (8.0, 18.0, 0.4), (18.0, 32.0, 0.15)),
    'width_deg': (12.0, 27.0),  # a cloud's angular width: the art's big puffy cumulus
    'squash': 0.92,  # clouds are a little wider than tall
    'base_flat': 0.3,  # the flat base sits this far (of a base ball's radius) below its centre
    'horizon_haze': 0.35,  # clouds at the horizon blend this far toward the horizon colour...
    'haze_top_deg': 14.0,  # ...fading out by this elevation
    'sky_curve': 0.55,  # the gradient's power: under 1 keeps the pale band near the horizon
    'sea_band': 0.006,  # below the horizon the sky turns to the far sea over this much of sin(elevation)
}

# The Spec's Day sun (latitude 45, clock 10), toward the sun, Roblox axes.
SUN = {'day': (0.465, 0.806, 0.367)}

COLOURS = {
    'day': {
        'top': mc.hexc('sky_top_day'),
        'horizon': mc.hexc('sky_horizon_day'),
        # Below the horizon: the Terrain water's rendered blue (between #349BD6 at high quality
        # and #1791D8 at low). At low quality Roblox draws the water only near the camera and
        # the sky shows beyond it, so the two must match; the art's far sea is #3187DE.
        'sea': '#2F92D8',
        'cloud_lit': '#F7F8FF',  # the art's sunlit tops read near white; cloud_day is their average
        'cloud_mid': mc.hexc('cloud_day'),
        'cloud_shade': mc.hexc('cloud_day', 'shade'),
    },
}

# Face -> (forward, image up) in Blender axes (see the docstring).
FACES = {
    'Ft': ((0, 1, 0), (0, 0, 1)),
    'Bk': ((0, -1, 0), (0, 0, 1)),
    'Rt': ((-1, 0, 0), (0, 0, 1)),
    'Lf': ((1, 0, 0), (0, 0, 1)),
    'Up': ((0, 0, 1), (1, 0, 0)),
    'Dn': ((0, 0, -1), (-1, 0, 0)),
}


def linear(hex_colour):
    return tuple(mc.srgb_to_linear(c) for c in mc.rgb(hex_colour)) + (1.0,)


def node(tree, kind, **inputs):
    n = tree.nodes.new(kind)
    for key, value in inputs.items():
        n.inputs[key].default_value = value
    return n


def ramp(tree, stops):
    """A colour ramp through (position, hex) stops."""
    n = tree.nodes.new('ShaderNodeValToRGB')
    elements = n.color_ramp.elements
    while len(elements) > len(stops):
        elements.remove(elements[-1])
    while len(elements) < len(stops):
        elements.new(0.5)
    for element, (pos, colour) in zip(elements, stops):
        element.position = pos
        element.color = linear(colour)
    return n


def math_node(tree, op, a=None, b=None, clamp=False):
    n = tree.nodes.new('ShaderNodeMath')
    n.operation = op
    n.use_clamp = clamp
    if isinstance(a, (int, float)):
        n.inputs[0].default_value = a
    if isinstance(b, (int, float)):
        n.inputs[1].default_value = b
    return n


def world(scene, c):
    """The sky gradient by the ray's elevation, the far sea below the horizon."""
    w = bpy.data.worlds.new('Sky')
    scene.world = w
    w.use_nodes = True
    t = w.node_tree
    t.nodes.clear()
    coord = t.nodes.new('ShaderNodeTexCoord')
    sep = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(coord.outputs['Generated'], sep.inputs[0])
    up = math_node(t, 'MAXIMUM', b=0.0)
    t.links.new(sep.outputs['Z'], up.inputs[0])
    curve = math_node(t, 'POWER', b=P['sky_curve'])
    t.links.new(up.outputs[0], curve.inputs[0])
    sky = ramp(t, [(0.0, c['horizon']), (1.0, c['top'])])
    t.links.new(curve.outputs[0], sky.inputs['Fac'])
    below = t.nodes.new('ShaderNodeMapRange')
    below.clamp = True
    below.inputs['From Min'].default_value = 0.0
    below.inputs['From Max'].default_value = -P['sea_band']
    t.links.new(sep.outputs['Z'], below.inputs['Value'])
    mix = t.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.inputs['B'].default_value = linear(c['sea'])
    t.links.new(below.outputs['Result'], mix.inputs['Factor'])
    t.links.new(sky.outputs['Color'], mix.inputs['A'])
    bg = node(t, 'ShaderNodeBackground', Strength=1.0)
    t.links.new(mix.outputs['Result'], bg.inputs['Color'])
    out = t.nodes.new('ShaderNodeOutputWorld')
    t.links.new(bg.outputs[0], out.inputs['Surface'])


def cloud_material(c, sun):
    """Emission by sunlit side and height in the cloud, hazed toward the horizon colour low down."""
    m = bpy.data.materials.new('Cloud')
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    geo = t.nodes.new('ShaderNodeNewGeometry')
    dot = t.nodes.new('ShaderNodeVectorMath')
    dot.operation = 'DOT_PRODUCT'
    dot.inputs[1].default_value = sun
    t.links.new(geo.outputs['Normal'], dot.inputs[0])
    lit = t.nodes.new('ShaderNodeMapRange')
    lit.clamp = True
    lit.inputs['From Min'].default_value = -0.35
    lit.inputs['From Max'].default_value = 0.9
    t.links.new(dot.outputs['Value'], lit.inputs['Value'])
    coord = t.nodes.new('ShaderNodeTexCoord')
    sep = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(coord.outputs['Generated'], sep.inputs[0])
    # 60% which way the surface faces, 40% how high in the cloud it is (the flat base is shaded).
    a = math_node(t, 'MULTIPLY', b=0.6)
    t.links.new(lit.outputs['Result'], a.inputs[0])
    b = math_node(t, 'MULTIPLY', b=0.4)
    t.links.new(sep.outputs['Z'], b.inputs[0])
    f = math_node(t, 'ADD', clamp=True)
    t.links.new(a.outputs[0], f.inputs[0])
    t.links.new(b.outputs[0], f.inputs[1])
    tone = ramp(t, [(0.0, c['cloud_shade']), (0.45, c['cloud_mid']), (0.8, c['cloud_lit'])])
    t.links.new(f.outputs[0], tone.inputs['Fac'])
    # Haze: the point's elevation from the dome's centre (the camera).
    norm = t.nodes.new('ShaderNodeVectorMath')
    norm.operation = 'NORMALIZE'
    t.links.new(geo.outputs['Position'], norm.inputs[0])
    sep2 = t.nodes.new('ShaderNodeSeparateXYZ')
    t.links.new(norm.outputs['Vector'], sep2.inputs[0])
    haze = t.nodes.new('ShaderNodeMapRange')
    haze.clamp = True
    haze.inputs['From Min'].default_value = 0.0
    haze.inputs['From Max'].default_value = math.sin(math.radians(P['haze_top_deg']))
    haze.inputs['To Min'].default_value = P['horizon_haze']
    haze.inputs['To Max'].default_value = 0.0
    t.links.new(sep2.outputs['Z'], haze.inputs['Value'])
    mix = t.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.inputs['B'].default_value = linear(c['horizon'])
    t.links.new(haze.outputs['Result'], mix.inputs['Factor'])
    t.links.new(tone.outputs['Color'], mix.inputs['A'])
    em = node(t, 'ShaderNodeEmission', Strength=1.0)
    t.links.new(mix.outputs['Result'], em.inputs['Color'])
    out = t.nodes.new('ShaderNodeOutputMaterial')
    t.links.new(em.outputs[0], out.inputs['Surface'])
    return m


def pick_clouds(rng):
    """(azimuth, elevation, width) in degrees for every cloud: stratified round the sky so they
    never bunch, most of them low."""
    n = P['count']
    elevs = []
    for lo, hi, share in P['bands']:
        elevs += [(lo, hi)] * round(n * share)
    elevs = elevs[:n] + [P['bands'][0][:2]] * max(0, n - len(elevs))
    rng.shuffle(elevs)
    clouds = []
    for k in range(n):
        az = 360.0 * (k + rng.uniform(0.15, 0.85)) / n
        lo, hi = elevs[k]
        el = rng.uniform(lo, hi)
        width = rng.uniform(*P['width_deg']) * (1.0 - 0.3 * (el / 40.0))
        clouds.append((az, el, width))
    return clouds


def cloud_mesh(name, rng, width):
    """A cumulus: a row of base balls, a tier above, a crown; metaballs meshed, the base cut flat.
    Local axes: X across, Y away from the camera, Z up; the base at Z 0."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = width * 0.03
    mb.render_resolution = width * 0.03
    mb.threshold = 0.5  # low enough that neighbouring puffs merge without holes
    obj = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(obj)
    base_r = []
    n_base = rng.randint(5, 8)
    for k in range(n_base):
        x = (k / (n_base - 1) - 0.5) * width * 0.8 + rng.uniform(-0.04, 0.04) * width
        r = width * rng.uniform(0.17, 0.25) * (1.0 - 0.35 * abs(x) / width)
        base_r.append(r)
        e = mb.elements.new()
        e.co = (x, rng.uniform(-0.08, 0.08) * width, 0.0)
        e.radius = r
    for _ in range(rng.randint(3, 5)):
        e = mb.elements.new()
        e.co = (rng.uniform(-0.3, 0.3) * width, rng.uniform(-0.06, 0.06) * width, width * rng.uniform(0.14, 0.24))
        e.radius = width * rng.uniform(0.18, 0.26)
    for _ in range(rng.randint(2, 3)):
        e = mb.elements.new()
        e.co = (rng.uniform(-0.18, 0.18) * width, 0.0, width * rng.uniform(0.3, 0.4))
        e.radius = width * rng.uniform(0.15, 0.21)
    # Small puffs along the upper edge: the art's cauliflower tops.
    for _ in range(rng.randint(5, 8)):
        a = rng.uniform(0.15, 0.85) * math.pi
        e = mb.elements.new()
        e.co = (math.cos(a) * width * 0.36, rng.uniform(-0.05, 0.05) * width, math.sin(a) * width * 0.3 + width * 0.05)
        e.radius = width * rng.uniform(0.07, 0.11)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.metaballs.remove(mb)
    floor = -min(base_r) * P['base_flat']
    for v in mesh.vertices:
        if v.co.z < floor:
            v.co.z = floor
        v.co.z = (v.co.z - floor) * P['squash']
    mesh.update()
    return mesh


def build(scene, light):
    c = COLOURS[light]
    sun = Vector(mc.rb(SUN[light])).normalized()
    world(scene, c)
    material = cloud_material(c, sun)
    rng = random.Random(SEED)
    R = P['radius']
    for k, (az, el, w) in enumerate(pick_clouds(rng)):
        width = 2 * R * math.tan(math.radians(w) / 2)
        mesh = cloud_mesh('Cloud%02d' % k, rng, width)
        mesh.materials.append(material)
        obj = bpy.data.objects.new('Cloud%02d' % k, mesh)
        scene.collection.objects.link(obj)
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
        depth = Vector((d.x, d.y, 0.0)).normalized()
        up = Vector((0.0, 0.0, 1.0))
        right = depth.cross(up)
        basis = Matrix((right, depth, up)).transposed().to_4x4()
        obj.matrix_world = Matrix.Translation(d * R) @ basis


def render_faces(scene, light):
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    cam_data = bpy.data.cameras.new('SkyCam')
    cam_data.sensor_fit = 'HORIZONTAL'
    cam_data.angle = math.pi / 2
    cam_data.clip_start = 1.0
    cam_data.clip_end = P['radius'] * 4
    cam = bpy.data.objects.new('SkyCam', cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    paths = {}
    for face, (forward, up) in FACES.items():
        f, u = Vector(forward), Vector(up)
        r = f.cross(u)
        cam.matrix_world = Matrix((r, u, -f)).transposed().to_4x4()
        path = os.path.join(HERE, 'textures', 'sky_%s_%s.png' % (light, face))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths[face] = path
        print('rendered', os.path.relpath(path, HERE))
    return paths


def preview(paths, light):
    """The faces unfolded round Ft: Rt Ft Lf Bk across, Up above Ft and Dn below, each turned
    so its edge meets Ft's (a seam check)."""
    import numpy as np

    def load(face):
        img = bpy.data.images.load(paths[face])
        a = np.empty(SIZE * SIZE * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        bpy.data.images.remove(img)
        return a.reshape(SIZE, SIZE, 4)[::-1]  # Blender rows run bottom to top; flip to top-down

    cross = np.zeros((SIZE * 3, SIZE * 4, 4), dtype=np.float32)
    cross[..., 3] = 1.0
    for col, face in enumerate(('Rt', 'Ft', 'Lf', 'Bk')):
        cross[SIZE:2 * SIZE, col * SIZE:(col + 1) * SIZE] = load(face)
    # Up's right edge faces -Z, the edge it shares with Ft's top: turn it clockwise. Dn's right
    # edge meets Ft's bottom: turn it anticlockwise.
    cross[0:SIZE, SIZE:2 * SIZE] = np.rot90(load('Up'), k=-1)
    cross[2 * SIZE:3 * SIZE, SIZE:2 * SIZE] = np.rot90(load('Dn'), k=1)
    out = bpy.data.images.new('Cross', SIZE * 4, SIZE * 3)
    out.pixels.foreach_set(np.ascontiguousarray(cross[::-1]).ravel())
    folder = os.path.join(HERE, 'checkpoints', 'sky')
    os.makedirs(folder, exist_ok=True)
    out.filepath_raw = os.path.join(folder, '%s-cross.png' % light)
    out.file_format = 'PNG'
    out.save()
    print('preview', os.path.relpath(out.filepath_raw, HERE))


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    light = 'sunset' if 'sunset' in args else 'day'
    if light not in COLOURS:
        raise SystemExit('no %s sky yet (Stage 7)' % light)
    scene = mc.clear_scene()
    build(scene, light)
    paths = render_faces(scene, light)
    if 'nopreview' not in args:
        preview(paths, light)


main()
