"""Generated models (Meshy, tools/meshy_generate.py) made ready for a cue piece, in headless Blender.

    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CueModels.py -- inspect <name>

    Blender ... --python assets/cue/CueModels.py -- compact <name>

compact: writes the committed copy (source.glb reduced to 150k triangles, maps/ at 1024 px); the
full download (model.glb and its 2k maps) stays local and out of git (models/.gitignore).

inspect: imports assets/cue/models/<name>/model.glb, prints its triangle count and size, and
renders it from four sides with its own textures (then `python3 assets/cue/CueModels.py --join
<name>` joins them into assets/cue/models/<name>/views.png), so the model can be judged before
it is fitted to a cue.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, 'models')
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def import_glb(bpy, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name, 'model.glb'))
    obs = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    return obs


def bounds(obs):
    from mathutils import Vector
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in obs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def triangles(obs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in obs)


def render_views(bpy, obs, out, size=512):
    """Four views (front, right, back, top) with a key light, joined into one image."""
    from mathutils import Vector
    import cue_common as cc  # noqa: F401
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.render.film_transparent = False
    world = bpy.data.worlds.new('W') if not scene.world else scene.world
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get('Background')
    bg.inputs[0].default_value = (0.05, 0.055, 0.07, 1)
    bg.inputs[1].default_value = 1.0
    lo, hi = bounds(obs)
    centre = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-3)
    for kind, rot, energy in (('SUN', (0.8, 0.2, 0.6), 3.0), ('SUN', (-0.6, -0.4, -2.4), 1.2)):
        ld = bpy.data.lights.new('L', kind)
        ld.energy = energy
        lo_ = bpy.data.objects.new('L', ld)
        lo_.rotation_euler = rot
        scene.collection.objects.link(lo_)
    cam_d = bpy.data.cameras.new('C')
    cam_d.lens = 50
    cam = bpy.data.objects.new('C', cam_d)
    scene.collection.objects.link(cam)
    scene.camera = cam
    frames = []
    for i, d in enumerate((Vector((0, -1, 0.15)), Vector((1, 0, 0.15)), Vector((0, 1, 0.15)), Vector((0.01, 0, 1)))):
        d = d.normalized()
        cam.location = centre + d * radius * 3.2
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        path = os.path.join(os.path.dirname(out), '_view%d.png' % i)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        frames.append(path)
    from PIL import Image  # noqa (Blender's Python may lack PIL: fall back to leaving the views)
    ims = [Image.open(p) for p in frames]
    sheet = Image.new('RGB', (size * 4, size))
    for i, im in enumerate(ims):
        sheet.paste(im.convert('RGB'), (i * size, 0))
    sheet.save(out)
    for p in frames:
        os.remove(p)


def inspect(name):
    import bpy
    import cue_common as cc
    cc.clear_scene('CueModels')
    obs = import_glb(bpy, name)
    lo, hi = bounds(obs)
    print('CUE model %s: %d objects, %d triangles, size %.3f x %.3f x %.3f' % (
        name, len(obs), triangles(obs), *(hi - lo)))
    try:
        render_views(bpy, obs, os.path.join(MODELS, name, 'views.png'))
        print('CUE model views', os.path.join(MODELS, name, 'views.png'))
    except ImportError:
        print('CUE model: no PIL in Blender, views left as _view*.png')


def compact(name, keep_tris=150000, map_px=1024):
    """The committed copy of a generated model: source.glb (reduced to keep_tris, UVs kept, no
    images) and its maps at map_px in maps/ (Roblox's SurfaceAppearance limit is 1024, so nothing
    is lost for the game). The full download (model.glb, 2k maps) stays local and out of git."""
    import bpy
    import cue_common as cc
    from CuePieces import apply_modifier
    cc.clear_scene('CueModels')
    obs = import_glb(bpy, name)
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    tris = triangles([ob])
    if tris > keep_tris:
        apply_modifier(bpy, ob, 'DECIMATE', decimate_type='COLLAPSE', ratio=keep_tris / tris,
                       use_collapse_triangulate=True)
    ob.data.materials.clear()
    for o in list(bpy.data.objects):
        if o != ob:
            bpy.data.objects.remove(o)
    d = os.path.join(MODELS, name)
    bpy.ops.export_scene.gltf(filepath=os.path.join(d, 'source.glb'), export_format='GLB', use_selection=False,
                              export_materials='NONE', export_normals=True, export_texcoords=True)
    os.makedirs(os.path.join(d, 'maps'), exist_ok=True)
    for f in ('base_color', 'normal', 'roughness', 'metallic', 'emission'):
        path = os.path.join(d, f + '.png')
        if not os.path.isfile(path):
            continue
        img = bpy.data.images.load(path)
        if img.size[0] > map_px:
            img.scale(map_px, map_px)
        img.filepath_raw = os.path.join(d, 'maps', f + '.png')
        img.file_format = 'PNG'
        img.save()
    print('CUE model compact %s: %d -> %d triangles' % (name, tris, triangles([ob])))


def join_views(name, size=512):
    """Outside Blender (plain Python with Pillow): join the _view*.png renders into views.png."""
    from PIL import Image
    d = os.path.join(MODELS, name)
    paths = sorted(p for p in os.listdir(d) if p.startswith('_view'))
    sheet = Image.new('RGB', (size * len(paths), size))
    for i, p in enumerate(paths):
        sheet.paste(Image.open(os.path.join(d, p)).convert('RGB').resize((size, size)), (i * size, 0))
        os.remove(os.path.join(d, p))
    sheet.save(os.path.join(d, 'views.png'))
    print('CUE model views', os.path.join(d, 'views.png'))


def main():
    if '--' not in sys.argv and len(sys.argv) >= 3 and sys.argv[1] == '--join':
        join_views(sys.argv[2])
        return
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    if len(argv) >= 2 and argv[0] == 'inspect':
        inspect(argv[1])
    elif len(argv) >= 2 and argv[0] == 'compact':
        compact(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
