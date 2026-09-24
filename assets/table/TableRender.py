"""Designer checkpoint renders for the pool table (assets/table/TableModel.blend).

Run it headless from the repository root after TableModel.py:

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        --python assets/table/TableRender.py

It appends the eight table meshes from TableModel.blend into an empty scene, dresses them in
clay/ID materials, adds render-only helpers (floor, lights, a few balls, the physics outline in
red) that never reach the FBX, renders nine 960 x 540 frames with Cycles (Metal when available,
else CPU) and tiles them into renders/checkpoint_shape.png (3 x 3). Frames are also kept as
renders/checkpoint_<n>_<name>.png. renders/checkpoint_*.png is git-ignored.

Stages (after `--`): `shape` (the default, above), `looks`, or `all`:

    ... --python assets/table/TableRender.py -- looks

The looks stage (run TableTextures.py first) dresses the meshes in the real upload textures the
way Roblox shades a SurfaceAppearance (ColorMap x Color tint, normal, roughness, metalness; no
sheen, no AO beyond the maps), lights a bright pool hall and renders both looks (blue cloth with
black wood, green cloth with cherry wood): renders/preview_<look>.png (the hero view) and
renders/checkpoint_looks.png (hero, corner pocket with caps, close aim view, far view per look).

Headless-safe: data calls only; the only operators are render and image saving.
"""

import math
import os
import sys

sys.dont_write_bytecode = True
from math import cos, radians, sin

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import table_common as tc  # noqa: E402

RENDER = {
    'resolution': [960, 540],  # one frame; the sheet is 3 x 3 of these
    'samples': 48,  # Cycles samples per frame (denoised)
    'lens_mm': 35.0,
    'use_gpu': True,  # Metal on Apple Silicon; falls back to the CPU
    # clay/ID colours (sRGB) and (roughness, metallic) per mesh
    'looks': {'Cloth': ([20, 120, 190], 0.9, 0.0), 'Rails': ([92, 58, 42], 0.45, 0.0),
              'Body': ([70, 46, 36], 0.5, 0.0), 'Pockets': ([34, 28, 26], 0.6, 0.0),
              'Caps': ([215, 218, 224], 0.18, 1.0), 'Hardware': ([215, 218, 224], 0.2, 1.0),
              'LogoPlate': ([200, 196, 180], 0.35, 0.3), 'Marks': ([255, 255, 255], 0.9, 0.0)},
    'physics_red': [255, 30, 20],
}
MESHES = ('Cloth', 'Rails', 'Body', 'Pockets', 'Caps', 'Hardware', 'LogoPlate', 'Marks')


def load_table(scene):
    path = os.path.join(HERE, 'TableModel.blend')
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n in MESHES]
    coll = bpy.data.collections.new('PoolTable')
    scene.collection.children.link(coll)
    objects = {}
    for obj in dst.objects:
        coll.objects.link(obj)
        objects[obj.name] = obj
    assert sorted(objects) == sorted(MESHES), sorted(objects)
    for name, obj in objects.items():
        rgb, rough, metal = RENDER['looks'][name]
        mat = tc.preview_material('Clay_' + name, rgb, rough, metal)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
    objects['Marks'].hide_render = True  # a transparent overlay; clay would draw it solid
    pearl_sights(objects['Rails'].data.materials[0])
    return objects


def pearl_sights(mat):
    """Colour the Rails trim sheet's pearl strip (UV v 0.87..0.94) white so the flush sights show."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'
    sep = nodes.new('ShaderNodeSeparateXYZ')
    links.new(uv.outputs['UV'], sep.inputs['Vector'])
    lo = nodes.new('ShaderNodeMath')
    lo.operation = 'GREATER_THAN'
    lo.inputs[1].default_value = 0.865
    hi = nodes.new('ShaderNodeMath')
    hi.operation = 'LESS_THAN'
    hi.inputs[1].default_value = 0.945
    links.new(sep.outputs['Y'], lo.inputs[0])
    links.new(sep.outputs['Y'], hi.inputs[0])
    both = nodes.new('ShaderNodeMath')
    both.operation = 'MULTIPLY'
    links.new(lo.outputs[0], both.inputs[0])
    links.new(hi.outputs[0], both.inputs[1])
    mix = nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    links.new(both.outputs[0], mix.inputs['Factor'])
    mix.inputs['A'].default_value = tuple(bsdf.inputs['Base Color'].default_value)
    mix.inputs['B'].default_value = (0.85, 0.85, 0.82, 1.0)
    links.new(mix.outputs['Result'], bsdf.inputs['Base Color'])


def emission_material(name, rgb, strength=4.0):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    em = nodes.new('ShaderNodeEmission')
    out = nodes.new('ShaderNodeOutputMaterial')
    links.new(em.outputs['Emission'], out.inputs['Surface'])
    em.inputs['Color'].default_value = tc._color([c / 255.0 for c in rgb])
    em.inputs['Strength'].default_value = strength
    return mat


def physics_overlay(scene, g):
    """The physics outline at nose height: segments, jaw circles and hole circles, as thin tubes."""
    s, h = g['studs_per_inch'], g['cloth']['above_floor_studs']
    z = h + g['cushion']['nose_height'] * s
    curve = bpy.data.curves.new('PhysicsOutline', 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = 0.006
    curve.bevel_resolution = 1

    def poly(points, cyclic=False):
        sp = curve.splines.new('POLY')
        sp.points.add(len(points) - 1)
        for pt, (x, y) in zip(sp.points, points):
            pt.co = (x * s, y * s, z, 1.0)
        sp.use_cyclic_u = cyclic
    for sg in g['segments']:
        poly([tuple(sg['a']), tuple(sg['b'])])
    for pt in g['points']:
        if pt['radius'] > 0:
            poly([(pt['x'] + pt['radius'] * cos(2 * math.pi * k / 24), pt['y'] + pt['radius'] * sin(2 * math.pi * k / 24))
                  for k in range(24)], cyclic=True)
    for hl in g['holes']:
        poly([(hl['x'] + hl['radius'] * cos(2 * math.pi * k / 64), hl['y'] + hl['radius'] * sin(2 * math.pi * k / 64))
              for k in range(64)], cyclic=True)
    obj = bpy.data.objects.new('PhysicsOutline', curve)
    curve.materials.append(emission_material('PhysicsRed', RENDER['physics_red']))
    scene.collection.objects.link(obj)
    return obj


def add_ball(scene, g, x_in, y_in, rgb, name):
    s, h = g['studs_per_inch'], g['cloth']['above_floor_studs']
    rr = g['ball']['render_radius'] * s
    mesh = bpy.data.meshes.new(name)
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=rr)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = (x_in * s, y_in * s, h + rr)
    mesh.materials.append(tc.preview_material(name + 'Mat', rgb, 0.15, 0.0))
    scene.collection.objects.link(obj)
    return obj


def setup_world(scene):
    world = bpy.data.worlds.new('RenderWorld')
    if world.node_tree is None:
        world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (0.55, 0.58, 0.64, 1.0)
    bg.inputs['Strength'].default_value = 0.9
    scene.world = world
    for name, loc, power, size in (('Key', (6, -8, 14), 900.0, 8.0), ('Fill', (-12, 6, 10), 350.0, 10.0),
                                   ('Over', (0, 0, 12), 600.0, 12.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = power
        data.shape = 'DISK'
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        obj.visible_camera = False  # light only, never a white disc in frame
        obj.visible_glossy = False
        aim(obj, (0, 0, 2.5))
        scene.collection.objects.link(obj)
    fm = bpy.data.meshes.new('Floor')
    import bmesh
    bm = bmesh.new()
    sz = 60.0
    bm.faces.new([bm.verts.new(c) for c in ((-sz, -sz, 0), (sz, -sz, 0), (sz, sz, 0), (-sz, sz, 0))])
    bm.to_mesh(fm)
    bm.free()
    floor = bpy.data.objects.new('Floor', fm)
    fm.materials.append(tc.preview_material('FloorMat', [150, 150, 146], 0.8, 0.0))
    scene.collection.objects.link(floor)


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def setup_engine(scene):
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
            print('TABLE render: Metal unavailable (%s); using the CPU' % exc)
    scene.cycles.device = device
    scene.cycles.samples = RENDER['samples']
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = RENDER['resolution']
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.view_settings.view_transform = 'Standard'
    return device


def camera(scene, name, loc, target, lens=None, fov=None, ortho=None):
    data = bpy.data.cameras.new(name)
    data.clip_start = 0.01
    data.clip_end = 200
    if ortho is not None:
        data.type = 'ORTHO'
        data.ortho_scale = ortho
    elif fov is not None:
        data.sensor_fit = 'HORIZONTAL'
        data.angle = radians(fov)
    else:
        data.lens = lens or RENDER['lens_mm']
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    aim(obj, target)
    scene.collection.objects.link(obj)
    return obj


def frames(g):
    """(name, camera kwargs, hide Caps, show physics) for the nine frames, in studs."""
    s, h = g['studs_per_inch'], g['cloth']['above_floor_studs']
    holes = {hl['id']: hl for hl in g['holes']}
    c3 = (holes[3]['x'] * s, holes[3]['y'] * s)
    c2 = (holes[2]['x'] * s, holes[2]['y'] * s)
    # the close aim view: a ball near the top rail, the camera 2.24 studs away at 30 degrees, FOV 60
    bx, by = 30.0 * s, 18.0 * s
    bz = h + g['ball']['render_radius'] * s
    d = 2.24
    back = Vector((-0.35, -1.0, 0.0)).normalized()
    aim_loc = (bx + back.x * d * cos(radians(30)), by + back.y * d * cos(radians(30)), bz + d * sin(radians(30)))
    ox, oy = g['rail']['outer_half_length'] * s, g['rail']['outer_half_width'] * s
    return [
        ('hero', dict(loc=(15.5, -13.0, 9.0), target=(0.6, 0.0, 2.2), lens=35), False, False),
        ('top', dict(loc=(0.0, 0.0, 30.0), target=(0.0, 0.0, 0.0), ortho=19.6), False, True),
        ('corner_caps', dict(loc=(c3[0] - 1.9, c3[1] - 2.4, h + 2.2), target=(c3[0] + 0.1, c3[1] + 0.1, h), lens=35), False, False),
        ('corner_bare', dict(loc=(c3[0] - 1.9, c3[1] - 2.4, h + 2.2), target=(c3[0] + 0.1, c3[1] + 0.1, h), lens=35), True, False),
        ('side_pocket', dict(loc=(c2[0] + 1.2, c2[1] - 3.0, h + 2.1), target=(c2[0], c2[1] + 0.1, h), lens=35), False, False),
        ('aim_close', dict(loc=aim_loc, target=(bx, by, bz), fov=60), False, False),
        ('leg', dict(loc=(ox + 2.6, -oy - 2.4, 1.2), target=(ox - 0.8, -oy + 0.8, 1.0), lens=35), False, False),
        ('foot_logo', dict(loc=(ox + 7.5, -1.2, 2.0), target=(ox - 1.0, 0.0, 1.9), lens=40), False, False),
        ('player_eye', dict(loc=(0.0, -oy - 3.0, 4.5), target=(0.0, 1.0, h), lens=24), False, False),
    ]


def compose(paths, out_path, cols=3):
    import numpy as np
    w, h = RENDER['resolution']
    rows = (len(paths) + cols - 1) // cols
    sheet = np.zeros((rows * h, cols * w, 4), dtype=np.float32)
    for k, path in enumerate(paths):
        img = bpy.data.images.load(path, check_existing=False)
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        r, c = k // cols, k % cols
        # image rows run bottom-up: the first frame belongs at the top-left
        sheet[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = px
        bpy.data.images.remove(img)
    out = bpy.data.images.new('CheckpointSheet', cols * w, rows * h, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = out_path
    out.file_format = 'PNG'
    out.save()


def render_shape(g):
    scene = tc.clear_scene('TableRender')
    objects = load_table(scene)
    setup_world(scene)
    device = setup_engine(scene)
    print('TABLE render device', device)
    overlay = physics_overlay(scene, g)
    balls = [add_ball(scene, g, 30.0, 18.0, [240, 238, 228], 'CueBall'),
             add_ball(scene, g, 25.0, 0.0, [230, 190, 30], 'OneBall'),
             add_ball(scene, g, 27.0, 1.2, [30, 60, 180], 'TwoBall'),
             add_ball(scene, g, 27.0, -1.2, [200, 30, 30], 'ThreeBall')]
    out_dir = os.path.join(HERE, 'renders')
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for k, (name, cam_kw, hide_caps, show_physics) in enumerate(frames(g), start=1):
        cam = camera(scene, 'Cam_' + name, **cam_kw)
        scene.camera = cam
        objects['Caps'].hide_render = hide_caps
        overlay.hide_render = not show_physics
        for b in balls:
            b.hide_render = show_physics
        path = os.path.join(out_dir, 'checkpoint_%d_%s.png' % (k, name))
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
        print('TABLE render', path)
    sheet = os.path.join(out_dir, 'checkpoint_shape.png')
    compose(paths, sheet)
    print('TABLE render sheet', sheet)


# ---------------------------------------------------------------------------------------------
# Looks stage: the real texture sheets from TableTextures.py, shaded the way Roblox shades a
# SurfaceAppearance (ColorMap x Color tint, normal, roughness, metalness; no sheen, no AO)
# ---------------------------------------------------------------------------------------------

LOOKS = {
    # tint = SurfaceAppearance.Color on the Cloth (sRGB 0..255); the wood sheets per look
    'blue': {'tint': [1, 169, 247], 'wood': 'Black'},
    'green': {'tint': [40, 175, 45], 'wood': 'Cherry'},
}
LOOK_RENDER = {
    'frame': [960, 540],  # sheet frames
    'preview': [1600, 900],  # preview_<look>.png (the hero view)
    'samples': 96,
    'sky': (0.95, 0.30, 0.12),  # world radiance straight up, at the horizon, below (a bright hall)
    'softbox': (15.0, 8.5, 7.0, 1.75),  # overhead light: width, depth (studs), height above the cloth, radiance
    'floor': [92, 88, 84],  # hall floor (sRGB)
}
TEX_MAPS = {  # mesh -> (colour sheet or None per look, normal, roughness, metalness, default roughness)
    'Cloth': ('Cloth_Color', 'Cloth_Normal', 'Cloth_Roughness', None, 0.9),
    'Rails': ('Rails_Color_{wood}', 'Rails_Normal', 'Rails_Roughness', None, 0.4),
    'Body': ('Body_Color_{wood}', 'Body_Normal', 'Body_Roughness', None, 0.4),
    'Pockets': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.6),
    'Caps': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.2),
    'Hardware': ('Parts_Color', 'Parts_Normal', 'Parts_Roughness', 'Parts_Metalness', 0.2),
    'LogoPlate': ('LogoPlate_Color', None, None, None, 0.7),  # no roughness map: Roblox shades it fairly matte
    'Marks': ('Marks_Color', None, None, None, 0.9),
}


def tex_image(name, data):
    img = bpy.data.images.get(name + '.png')
    if img is None:
        img = bpy.data.images.load(os.path.join(HERE, 'textures', name + '.png'), check_existing=True)
        img.colorspace_settings.name = 'Non-Color' if data else 'sRGB'
        img.alpha_mode = 'STRAIGHT'
    return img


def look_material(mesh, look):
    col_name, nrm_name, rgh_name, met_name, rough_default = TEX_MAPS[mesh]
    col_name = col_name.format(wood=LOOKS[look]['wood'])
    mat = bpy.data.materials.new('Look_%s_%s' % (look, mesh))
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    bsdf = nodes.new('ShaderNodeBsdfPrincipled')
    out = nodes.new('ShaderNodeOutputMaterial')
    links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'UVMap'

    def tex(name, data):
        node = nodes.new('ShaderNodeTexImage')
        node.image = tex_image(name, data)
        node.interpolation = 'Linear'
        node.extension = 'REPEAT'  # Roblox repeats UVs outside 0..1
        links.new(uv.outputs['UV'], node.inputs['Vector'])
        return node
    c = tex(col_name, False)
    colour = c.outputs['Color']
    if mesh == 'Cloth':  # SurfaceAppearance.Color multiplies the ColorMap
        mix = nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        links.new(colour, mix.inputs['A'])
        mix.inputs['B'].default_value = tc._color([v / 255.0 for v in LOOKS[look]['tint']])
        colour = mix.outputs['Result']
    links.new(colour, bsdf.inputs['Base Color'])
    if mesh == 'Marks':
        links.new(c.outputs['Alpha'], bsdf.inputs['Alpha'])
    if nrm_name:
        nm = nodes.new('ShaderNodeNormalMap')
        nm.space = 'TANGENT'
        nm.uv_map = 'UVMap'
        links.new(tex(nrm_name, True).outputs['Color'], nm.inputs['Color'])
        links.new(nm.outputs['Normal'], bsdf.inputs['Normal'])
    if rgh_name:
        links.new(tex(rgh_name, True).outputs['Color'], bsdf.inputs['Roughness'])
    else:
        bsdf.inputs['Roughness'].default_value = rough_default
    if met_name:
        links.new(tex(met_name, True).outputs['Color'], bsdf.inputs['Metallic'])
    else:
        bsdf.inputs['Metallic'].default_value = 0.0
    return mat


def dress_look(objects, look):
    for name, obj in objects.items():
        obj.data.materials.clear()
        obj.data.materials.append(look_material(name, look))
        obj.hide_render = False


def setup_hall(scene, g):
    """A well-lit pool hall: bright sky dome (brighter overhead), a big soft light over the table
    (visible in reflections, not to the camera) and a mid-grey floor. Standard view transform."""
    world = bpy.data.worlds.new('HallWorld')
    if world.node_tree is None:
        world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    nodes.clear()
    coord = nodes.new('ShaderNodeTexCoord')
    sep = nodes.new('ShaderNodeSeparateXYZ')
    links.new(coord.outputs['Generated'], sep.inputs['Vector'])
    ramp = nodes.new('ShaderNodeValToRGB')
    up, hor, down = LOOK_RENDER['sky']
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (down, down, down, 1.0)
    els[1].position, els[1].color = 1.0, (up, up, up, 1.0)
    mid = els.new(0.5)
    mid.color = (hor, hor, hor, 1.0)
    # Generated coordinates on the world are the view direction; z -1..1 -> 0..1
    mapr = nodes.new('ShaderNodeMapRange')
    mapr.inputs['From Min'].default_value = -1.0
    mapr.inputs['From Max'].default_value = 1.0
    links.new(sep.outputs['Z'], mapr.inputs['Value'])
    links.new(mapr.outputs['Result'], ramp.inputs['Fac'])
    bg = nodes.new('ShaderNodeBackground')
    links.new(ramp.outputs['Color'], bg.inputs['Color'])
    bg.inputs['Strength'].default_value = 1.0
    wout = nodes.new('ShaderNodeOutputWorld')
    links.new(bg.outputs['Background'], wout.inputs['Surface'])
    scene.world = world
    import bmesh
    w, d, hgt, radiance = LOOK_RENDER['softbox']
    zc = g['cloth']['above_floor_studs'] + hgt
    me = bpy.data.meshes.new('Softbox')
    bm = bmesh.new()
    vs = [bm.verts.new(c) for c in ((-w / 2, -d / 2, zc), (-w / 2, d / 2, zc), (w / 2, d / 2, zc), (w / 2, -d / 2, zc))]
    bm.faces.new(vs)  # normal faces down
    bm.to_mesh(me)
    bm.free()
    box = bpy.data.objects.new('Softbox', me)
    box.visible_camera = False
    me.materials.append(emission_material('SoftboxLight', [255, 255, 255], radiance))
    scene.collection.objects.link(box)
    fm = bpy.data.meshes.new('Floor')
    bm = bmesh.new()
    sz = 60.0
    bm.faces.new([bm.verts.new(c) for c in ((-sz, -sz, 0), (sz, -sz, 0), (sz, sz, 0), (-sz, sz, 0))])
    bm.to_mesh(fm)
    bm.free()
    floor = bpy.data.objects.new('Floor', fm)
    fm.materials.append(tc.preview_material('FloorMat', LOOK_RENDER['floor'], 0.85, 0.0))
    scene.collection.objects.link(floor)


def look_frames(g):
    """(name, camera kwargs): hero, a corner pocket with its cap, the close aim view, a far view."""
    base = {name: kw for name, kw, _, _ in frames(g)}
    return [('hero', base['hero']), ('corner_caps', base['corner_caps']), ('aim_close', base['aim_close']),
            ('far', dict(loc=(-3.0, -17.0, 15.0), target=(0.0, 0.3, 2.9), lens=35))]


def render_looks(g):
    scene = tc.clear_scene('TableLooks')
    objects = load_table(scene)
    setup_hall(scene, g)
    device = setup_engine(scene)
    scene.cycles.samples = LOOK_RENDER['samples']
    print('TABLE looks device', device)
    for name, x, y, rgb in (('CueBall', 30.0, 18.0, [242, 240, 232]), ('OneBall', 25.0, 0.0, [235, 185, 20]),
                            ('TwoBall', 27.0, 1.2, [25, 60, 190]), ('ThreeBall', 27.0, -1.2, [210, 30, 30]),
                            ('EightBall', 29.0, 0.0, [14, 14, 16])):
        add_ball(scene, g, x, y, rgb, name)
    out_dir = os.path.join(HERE, 'renders')
    os.makedirs(out_dir, exist_ok=True)
    cams = {name: camera(scene, 'Cam_' + name, **kw) for name, kw in look_frames(g)}
    paths = []
    for look in LOOKS:
        dress_look(objects, look)
        scene.render.resolution_x, scene.render.resolution_y = LOOK_RENDER['frame']
        for name, _ in look_frames(g):
            scene.camera = cams[name]
            path = os.path.join(out_dir, 'checkpoint_looks_%s_%s.png' % (look, name))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            paths.append(path)
            print('TABLE render', path)
        scene.camera = cams['hero']
        scene.render.resolution_x, scene.render.resolution_y = LOOK_RENDER['preview']
        path = os.path.join(out_dir, 'preview_%s.png' % look)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print('TABLE render', path)
    scene.render.resolution_x, scene.render.resolution_y = LOOK_RENDER['frame']
    sheet = os.path.join(out_dir, 'checkpoint_looks.png')
    compose(paths, sheet, cols=4)
    print('TABLE render sheet', sheet)


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    stages = argv or ['shape']
    g, _ = tc.load_geometry(os.path.join(HERE, 'Geometry.json'))
    for stage in stages:
        if stage in ('shape', 'all'):
            render_shape(g)
        if stage in ('looks', 'all'):
            render_looks(g)
    print('TABLE render OK')


if __name__ == '__main__':
    main()
