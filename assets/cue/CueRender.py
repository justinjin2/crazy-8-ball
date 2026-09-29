"""Preview renders of the cue package (Cycles, fixed cameras, studio lighting).

    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CueRender.py -- --mesh
        renders/checkpoint_mesh.png: the full cue side-on, a 3/4 view of the handle, close-ups of
        the tip and ferrule, the joint, the butt and bumper, and the handle in clay and in
        wireframe. Colours here are the Classic zone colours, flat, to read the shape.
    ... -- --skin <id>
        renders/<id>.png from the maps in textures/<id>_*.png (CueTextures.py calls this).

Run CueModel.py first. Headless-safe: data calls only; the only operators are render and save.
"""

import math
import os
import sys
import tempfile

sys.dont_write_bytecode = True

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

TAG = 'CUE render'
RENDERS = os.path.join(HERE, 'renders')
TEXTURES = os.path.join(HERE, 'textures')

RENDER = {
    'samples': 64,  # Cycles samples per frame (denoised)
    'use_gpu': True,  # Metal on Apple Silicon; falls back to the CPU
    'background': (0.16, 0.17, 0.19),  # the world colour, linear
    'clay': (0.55, 0.55, 0.55),
    'wire_px': 1.2,  # wireframe line width in pixels
    'tile': (800, 450),  # one close-up frame; the full-cue strip is three tiles wide
}


def setup_engine(scene, size):
    scene.render.engine = 'CYCLES'
    device = 'CPU'
    if RENDER['use_gpu']:
        try:
            prefs = bpy.context.preferences.addons['cycles'].preferences
            prefs.compute_device_type = 'METAL'
            prefs.get_devices()
            usable = [d for d in prefs.devices if d.type == 'METAL']
            for d in prefs.devices:
                d.use = d.type == 'METAL'
            if usable:
                device = 'GPU'
        except Exception as exc:  # no Metal: stay on the CPU
            print(TAG, 'Metal unavailable (%s); using the CPU' % exc)
    scene.cycles.device = device
    scene.cycles.samples = RENDER['samples']
    scene.cycles.use_denoising = True
    scene.cycles.seed = 0
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'Standard'
    return device


def studio(scene):
    world = bpy.data.worlds.new('Studio')
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = RENDER['background'] + (1.0,)
    bg.inputs[1].default_value = 0.5
    scene.world = world
    # key, fill and rim area lights around the cue's middle
    for name, loc, energy, size in (('Key', (-3.0, -2.0, 4.0), 380.0, 4.0),
                                    ('Fill', (3.5, -4.5, 1.5), 120.0, 5.0),
                                    ('Rim', (0.5, -9.0, -2.5), 160.0, 3.0),
                                    ('Top', (0.0, -3.5, 6.0), 100.0, 8.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        aim(obj, (0.0, -3.5, 0.0), (0.0, 1.0, 0.0) if loc[0] == 0.0 else (0.0, 0.0, 1.0))
        scene.collection.objects.link(obj)


def aim(obj, target, up=(0.0, 0.0, 1.0)):
    """Point the object's -Z at target with `up` as the screen's up."""
    from mathutils import Matrix
    f = (Vector(target) - obj.location).normalized()
    right = f.cross(Vector(up))
    if right.length < 1e-6:
        right = f.cross(Vector((0.0, 1.0, 0.0)))
    right.normalize()
    true_up = right.cross(f)
    obj.rotation_euler = Matrix((right, true_up, -f)).transposed().to_euler()


def camera(scene, loc, target, lens=None, ortho=None, up=(0.0, 0.0, 1.0)):
    data = bpy.data.cameras.new('Cam')
    data.clip_start = 0.002
    data.clip_end = 100
    if ortho is not None:
        data.type = 'ORTHO'
        data.ortho_scale = ortho
    else:
        data.lens = lens
    obj = bpy.data.objects.new('Cam', data)
    obj.location = loc
    aim(obj, target, up)
    scene.collection.objects.link(obj)
    scene.camera = obj
    return obj


def new_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    return mat, nodes, mat.node_tree.links, bsdf


def region_material(shape):
    """Flat Classic zone colours by the mesh's cue_region face attribute."""
    mat, nodes, links, bsdf = new_material('Regions')
    attr = nodes.new('ShaderNodeAttribute')
    attr.attribute_type = 'GEOMETRY'
    attr.attribute_name = 'cue_region'
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'CONSTANT'
    colours = {z['name']: z['color'] for z in shape['zones']}
    colours['bumper'] = [12, 12, 12]
    colours['end'] = [12, 12, 12]
    n = len(cc.REGIONS)
    scale = nodes.new('ShaderNodeMath')
    scale.operation = 'MULTIPLY_ADD'
    scale.inputs[1].default_value = 1.0 / n
    scale.inputs[2].default_value = 0.5 / n
    elements = ramp.color_ramp.elements
    while len(elements) < n:
        elements.new(0.5)
    for i, region in enumerate(cc.REGIONS):
        elements[i].position = i / n
        elements[i].color = cc_linear(colours[region])
    links.new(attr.outputs['Fac'], scale.inputs[0])
    links.new(scale.outputs[0], ramp.inputs['Fac'])
    links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.4
    return mat


def cc_linear(rgb):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)


def clay_material(wire):
    mat, nodes, links, bsdf = new_material('Wire' if wire else 'Clay')
    bsdf.inputs['Base Color'].default_value = RENDER['clay'] + (1.0,)
    bsdf.inputs['Roughness'].default_value = 0.6
    if wire:
        w = nodes.new('ShaderNodeWireframe')
        w.use_pixel_size = True
        w.inputs['Size'].default_value = RENDER['wire_px']
        mix = nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs['A'].default_value = RENDER['clay'] + (1.0,)
        mix.inputs['B'].default_value = (0.02, 0.05, 0.12, 1.0)
        links.new(w.outputs['Fac'], mix.inputs['Factor'])
        links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])
    return mat


def maps_material(maps):
    """A material from a skin's maps: {'color', 'normal', 'roughness', 'metalness', 'emissive'?}."""
    mat, nodes, links, bsdf = new_material('Skin')
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'

    def tex(path, colour):
        node = nodes.new('ShaderNodeTexImage')
        node.image = bpy.data.images.load(path, check_existing=False)
        node.image.colorspace_settings.name = 'sRGB' if colour else 'Non-Color'
        node.interpolation = 'Linear'
        links.new(uv.outputs['UV'], node.inputs['Vector'])
        return node

    links.new(tex(maps['color'], True).outputs['Color'], bsdf.inputs['Base Color'])
    links.new(tex(maps['roughness'], False).outputs['Color'], bsdf.inputs['Roughness'])
    links.new(tex(maps['metalness'], False).outputs['Color'], bsdf.inputs['Metallic'])
    nm = nodes.new('ShaderNodeNormalMap')
    nm.space = 'TANGENT'
    nm.uv_map = 'UVMap'
    links.new(tex(maps['normal'], False).outputs['Color'], nm.inputs['Color'])
    links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if maps.get('emissive'):
        em = tex(maps['emissive'], True)
        links.new(em.outputs['Color'], bsdf.inputs['Emission Color'])
        bsdf.inputs['Emission Strength'].default_value = 2.0
    return mat


def render_frame(scene, size, view, workdir, name):
    for obj in [o for o in scene.objects if o.type == 'CAMERA']:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.cameras.remove(data)
    camera(scene, **view)
    scene.render.resolution_x, scene.render.resolution_y = size
    path = os.path.join(workdir, name + '.png')
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return (cc.read_image(path)[:, :, :3] * 255.0 + 0.5).astype(np.uint8)


def compose(rows, gap=6):
    """rows: lists of equal-height uint8 images; each row is centred on the widest."""
    width = max(sum(im.shape[1] for im in row) + gap * (len(row) - 1) for row in rows)
    height = sum(row[0].shape[0] for row in rows) + gap * (len(rows) - 1)
    sheet = np.full((height, width, 3), 24, np.uint8)
    y = 0
    for row in rows:
        w = sum(im.shape[1] for im in row) + gap * (len(row) - 1)
        x = (width - w) // 2
        for im in row:
            sheet[y:y + im.shape[0], x:x + im.shape[1]] = im
            x += im.shape[1] + gap
        y += row[0].shape[0] + gap
    return sheet


# Views, in studs (the tip at the origin, the butt at y = -7, the top of the cue +Z).
FULL = dict(loc=(-12.0, -3.5, 0.0), target=(0.0, -3.5, 0.0), ortho=7.3)
HANDLE_34 = dict(loc=(-1.25, -3.55, 0.75), target=(0.0, -5.25, 0.0), lens=50)
TIP = dict(loc=(-0.42, 0.3, 0.2), target=(0.0, -0.12, 0.0), lens=85)
JOINT = dict(loc=(-0.6, -3.3, 0.25), target=(0.0, -3.69, 0.0), lens=85)
BUTT = dict(loc=(-0.6, -7.45, 0.28), target=(0.0, -6.9, 0.0), lens=85)
HANDLE_SIDE = dict(loc=(-3.2, -5.3, 0.9), target=(0.0, -5.3, 0.0), lens=85)


def setup(size):
    scene = cc.clear_scene('CueRender')
    setup_engine(scene, size)
    studio(scene)
    obj = cc.load_cue_object()
    return scene, obj


def render_mesh():
    shape, _ = cc.load_shape()
    tw, th = RENDER['tile']
    scene, obj = setup((tw, th))
    regions = region_material(shape)
    obj.data.materials.clear()
    obj.data.materials.append(regions)
    work = tempfile.mkdtemp(prefix='cue_render_')
    full = render_frame(scene, (tw * 3 + 12, 260), FULL, work, 'full')
    frames = [render_frame(scene, (tw, th), v, work, n) for n, v in
              (('handle', HANDLE_34), ('tip', TIP), ('joint', JOINT), ('butt', BUTT))]
    obj.data.materials.clear()
    obj.data.materials.append(clay_material(False))
    clay = render_frame(scene, (tw, th), HANDLE_SIDE, work, 'clay')
    obj.data.materials.clear()
    obj.data.materials.append(clay_material(True))
    wire = render_frame(scene, (tw, th), HANDLE_SIDE, work, 'wire')
    sheet = compose([[full], frames[:3], [frames[3], clay, wire]])
    out = os.path.join(RENDERS, 'checkpoint_mesh.png')
    cc.write_png(out, sheet)
    cc.log(TAG, 'wrote', out)


def skin_views():
    """Four sides of the whole cue (top, the side, the seam side below, the far side) and
    close-ups: the tip, the joint, the butt end, the seam from below, the shaft_top/forearm
    join and the forearm/butt join."""
    # The top and below views keep the tip on the left; the far side is seen upright, so its
    # tip is on the right, as when walking round the cue.
    views = []
    for name, loc, up in (('top', (0.0, -3.5, 12.0), (1.0, 0.0, 0.0)),
                          ('side', (-12.0, -3.5, 0.0), (0.0, 0.0, 1.0)),
                          ('below', (0.0, -3.5, -12.0), (-1.0, 0.0, 0.0)),
                          ('far', (12.0, -3.5, 0.0), (0.0, 0.0, 1.0))):
        views.append((name, dict(loc=loc, target=(0.0, -3.5, 0.0), ortho=7.3, up=up)))
    close = [('tip', TIP), ('joint', JOINT), ('butt', BUTT),
             ('seam', dict(loc=(-0.25, -3.1, -0.75), target=(0.0, -3.7, 0.0), lens=50)),
             ('join_forearm', dict(loc=(-0.9, -3.0, 0.55), target=(0.0, -3.9, 0.0), lens=50)),
             ('join_butt', dict(loc=(-0.9, -4.6, 0.55), target=(0.0, -5.4, 0.0), lens=50))]
    return views, close


def render_skin(skin_id, maps=None, out=None):
    tw, th = RENDER['tile']
    scene, obj = setup((tw, th))
    maps = maps or {k: os.path.join(TEXTURES, '%s_%s.png' % (skin_id, k))
                    for k in ('color', 'normal', 'roughness', 'metalness', 'emissive')}
    if not os.path.isfile(maps.get('emissive') or ''):
        maps.pop('emissive', None)
    obj.data.materials.clear()
    obj.data.materials.append(maps_material(maps))
    work = tempfile.mkdtemp(prefix='cue_render_')
    sides, close = skin_views()
    strips = [render_frame(scene, (tw * 3 + 12, 200), view, work, name) for name, view in sides]
    frames = [render_frame(scene, (tw, th), v, work, n) for n, v in close]
    sheet = compose([[s] for s in strips] + [frames[:3], frames[3:]])
    out = out or os.path.join(RENDERS, '%s.png' % skin_id)
    cc.write_png(out, sheet)
    cc.log(TAG, 'wrote', out)
    return out


def main():
    args = cc.script_args()
    if '--mesh' in args:
        render_mesh()
    elif '--skin' in args:
        render_skin(args[args.index('--skin') + 1])
    else:
        cc.fail(TAG, 'pass --mesh or --skin <id>')


if __name__ == '__main__':
    main()
