"""The rooftop map's props, built headlessly in Blender: one template per kind, placed in Studio
by MapBuilder.prepareProps at every spot in Layout.json.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \\
        --python assets/map/gen_props.py [-- render [Kind ...]]

The kinds live in family modules, assets/map/props/*.py; each exposes KINDS = {name: build},
and build() returns a dict:

    'Opaque'   map_common.Mesh on the props trim sheet (p_ strips; textures/props_color.png)
    'Foliage'  map_common.Mesh on the plants atlas (map_common.PLANTS; textures/plants.png), alpha
    'Glow'     map_common.Mesh drawn in one flat emissive colour (GLOW below)
    'seats'    [(x, y, z, yaw)]: where a Seat part goes (its top surface centre), prop-local
    'lights'   [(x, y, z)]: where a PointLight goes, prop-local

Any of the meshes may be missing. Prop-local frame: Roblox axes and studs, the prop's
footprint centred on the origin, the floor at Y 0 (the Palm's origin is the top of its
planter box; the GlobeLight's is the globe's centre), the front toward +Z (map_layout
turns it by the placement's yaw).

It writes fbx/Props.fbx (the meshes named <Kind>__<Group>, plus the anchor cubes), Props.json
(each kind's groups, triangles, seats, lights and size) and Props.blend. It fails (exit 1) on
any check: a per-kind triangle cap, the props group's total over its placements, the anchors,
the FBX round trip. With `-- render` it also renders each kind (or those named) against the
floor to checkpoints/props/<Kind>.png and a contact sheet, checkpoints/props/sheet.png.
"""

import importlib.util
import json
import math
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import map_common as mc  # noqa: E402

# The brief's per-instance caps (section 6), by kind.
CAPS = {
    'LoungeCouch': 3000, 'SideCouch': 3000, 'CoffeeTable': 500, 'FirePit': 1500,
    'FernPlanter': 1200, 'PalmPlanter': 300, 'Palm': 2500, 'PlanterBed': 1200,
    'Lantern': 400, 'LanternTall': 400, 'GlobeLight': 150, 'UmbrellaSet': 2500,
    'Piano': 4000, 'PianoBench': 500,
}
PROPS_CAP = 140000  # the props group (the brief, section 6), over every placement
# Which Layout.json kind each template dresses (map_common.PROP_TEMPLATES, turned round).
LAYOUT_KIND = {t: k for k, ts in mc.PROP_TEMPLATES.items() for t in ts}
PALM_HEIGHT = mc.PALM_HEIGHT
PLANTER_BOX_HEIGHT = mc.PLANTER_BOX_HEIGHT
# Flat colours for the Glow meshes (Config.Map.Props repeats them for Studio).
GLOW = {
    'Lantern': mc.hexc('globe_light'), 'LanternTall': mc.hexc('globe_light'),
    'GlobeLight': mc.hexc('globe_light'), 'FirePit': mc.hexc('fire'),
}
GROUPS = ('Opaque', 'Foliage', 'Glow')
LAYOUT = json.load(open(os.path.join(HERE, 'Layout.json')))


def load_kinds(only=None):
    """Every family module's KINDS, or only the modules named in `only` (a builder testing
    its own family: PROPS_ONLY=seating)."""
    kinds = {}
    folder = os.path.join(HERE, 'props')
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if not name.endswith('.py') or name.startswith('_') or name.endswith('_textures.py'):
            continue
        if only and name[:-3] not in only:
            continue
        spec = importlib.util.spec_from_file_location('props_' + name[:-3], os.path.join(folder, name))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for kind, build in getattr(module, 'KINDS', {}).items():
            assert kind not in kinds, ('two modules build', kind)
            kinds[kind] = build
    return kinds


def placements(kind):
    return sum(1 for p in LAYOUT['props'] if p['kind'] == LAYOUT_KIND.get(kind))


# ---------------------------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------------------------

def image_material(name, image_file, alpha=False):
    mat = bpy.data.materials.new(name)
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Roughness'].default_value = 0.75
    path = os.path.join(HERE, 'textures', image_file)
    if not os.path.exists(path):
        bsdf.inputs['Base Color'].default_value = (0.5, 0.6, 0.3, 1.0)
        return mat
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(path, check_existing=True)
    links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if alpha:
        links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        if hasattr(mat, 'surface_render_method'):
            mat.surface_render_method = 'DITHERED'
    return mat


def glow_material(name, hex_colour):
    mat = bpy.data.materials.new(name)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    col = tuple(mc.srgb_to_linear(c) for c in mc.rgb(hex_colour)) + (1.0,)
    bsdf.inputs['Base Color'].default_value = col
    if 'Emission Color' in bsdf.inputs:
        bsdf.inputs['Emission Color'].default_value = col
        bsdf.inputs['Emission Strength'].default_value = 1.5
    return mat


# ---------------------------------------------------------------------------------------------
# Build, check, export
# ---------------------------------------------------------------------------------------------

def build_all(kinds, collection, materials):
    records, objects, problems = {}, [], []
    total = 0
    for kind in sorted(kinds):
        out = kinds[kind]()
        rec = {'layout_kind': LAYOUT_KIND.get(kind), 'groups': [], 'triangles': 0,
               'seats': [list(s) for s in out.get('seats', [])],
               'lights': [list(p) for p in out.get('lights', [])]}
        lo, hi = [math.inf] * 3, [-math.inf] * 3
        for group in GROUPS:
            mesh = out.get(group)
            if mesh is None or not mesh.faces:
                continue
            mesh.name = '%s__%s' % (kind, group)
            if group == 'Opaque':
                mat = materials['Opaque']
            elif group == 'Foliage':
                mat = materials['Foliage']
            else:
                mat = materials.setdefault('Glow_' + kind, glow_material('Glow_' + kind, GLOW.get(kind, '#FFF4C8')))
            obj = mc.to_object(mesh, collection, mat)
            objects.append(obj)
            rec['groups'].append(group)
            rec['triangles'] += obj['triangle_count']
            (a, b) = mesh.bounds()
            lo = [min(lo[i], a[i]) for i in range(3)]
            hi = [max(hi[i], b[i]) for i in range(3)]
        rec['bounds'] = [lo, hi]
        cap = CAPS.get(kind)
        if cap is None:
            problems.append('%s has no triangle cap' % kind)
        elif rec['triangles'] > cap:
            problems.append('%s: %d triangles, over its cap of %d' % (kind, rec['triangles'], cap))
        count = placements(kind)
        rec['placements'] = count
        total += rec['triangles'] * count
        records[kind] = rec
    if total > PROPS_CAP:
        problems.append('the props group: %d triangles over its placements, over %d' % (total, PROPS_CAP))
    return records, objects, problems, total


def render(kinds, records, objects):
    scene = bpy.context.scene
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'CYCLES'
    scene.render.resolution_x = scene.render.resolution_y = 640
    if hasattr(scene, 'eevee'):
        scene.eevee.taa_render_samples = 32
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new('World')
    scene.world = world
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    sky = mc.rgb(mc.hexc('sky_horizon_day'))
    bg.inputs['Color'].default_value = tuple(mc.srgb_to_linear(c) for c in sky) + (1.0,)
    bg.inputs['Strength'].default_value = 0.9
    extra = bpy.data.collections.new('RenderOnly')
    scene.collection.children.link(extra)
    light = bpy.data.lights.new('Sun', 'SUN')
    light.energy = 4.0
    sun = bpy.data.objects.new('Sun', light)
    extra.objects.link(sun)
    sun.rotation_euler = Vector(mc.rb((0.465, 0.806, 0.367))).normalized().to_track_quat('Z', 'Y').to_euler()
    floor_mat = image_material('FloorPreview', 'floor_color.png')
    floor = mc.Mesh('RenderFloor')
    s = 40.0
    floor.face([(-s, 0, s), (s, 0, s), (s, 0, -s), (-s, 0, -s)], [(-s / 9, -s / 9), (s / 9, -s / 9), (s / 9, s / 9), (-s / 9, s / 9)])
    mc.to_object(floor, extra, floor_mat)
    cam_data = bpy.data.cameras.new('Cam')
    cam_data.lens = 50
    cam_data.clip_end = 2000
    cam = bpy.data.objects.new('Cam', cam_data)
    extra.objects.link(cam)
    scene.camera = cam
    out_dir = os.path.join(HERE, 'checkpoints', 'props')
    os.makedirs(out_dir, exist_ok=True)
    by_kind = {}
    for obj in objects:
        by_kind.setdefault(obj.name.split('__')[0], []).append(obj)
    written = []
    for kind in kinds:
        for other in objects:
            other.hide_render = other not in by_kind.get(kind, [])
        lo, hi = records[kind]['bounds']
        centre = Vector(mc.rb(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2)))
        radius = max(hi[i] - lo[i] for i in range(3)) * 0.75 + 0.5
        view = Vector(mc.rb((0.75, 0.5, 1.0))).normalized()  # from the front-right, above
        cam.location = centre + view * radius * 3.2
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(out_dir, kind + '.png')
        bpy.ops.render.render(write_still=True)
        written.append(scene.render.filepath)
    for other in objects:
        other.hide_render = False
    try:
        from PIL import Image
        tiles = [Image.open(p) for p in written]
        cols = 4
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new('RGB', (cols * 320, rows * 320), (255, 255, 255))
        for i, t in enumerate(tiles):
            sheet.paste(t.convert('RGB').resize((320, 320)), ((i % cols) * 320, (i // cols) * 320))
        sheet.save(os.path.join(out_dir, 'sheet%s.png' % ('-' + '-'.join(sorted(set(kinds))) if len(kinds) < 6 else '')))
    except ImportError:
        pass  # Blender's Python has no Pillow: the single renders are enough
    return written


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    do_render = bool(argv) and argv[0] == 'render'
    wanted = argv[1:] if do_render else []
    scene = mc.clear_scene()
    collection = bpy.data.collections.new('Props')
    scene.collection.children.link(collection)
    materials = {
        'Opaque': image_material('Props', 'props_color.png'),
        'Foliage': image_material('Plants', 'plants.png', alpha=True),
    }
    # PROPS_ONLY=seating,plants builds only those modules and exports nothing (renders and
    # checks only), so builders working at once never overwrite each other's files.
    only = [m for m in os.environ.get('PROPS_ONLY', '').split(',') if m]
    kinds = load_kinds(only)
    records, objects, problems, total = build_all(kinds, collection, materials)
    for kind in sorted(records):
        r = records[kind]
        print('%-12s %5d triangles (cap %s) x %2d placements  groups %s  seats %d  lights %d'
              % (kind, r['triangles'], CAPS.get(kind), r['placements'], '+'.join(r['groups']),
                 len(r['seats']), len(r['lights'])))
    print('props total over placements: %d (cap %d)' % (total, PROPS_CAP))
    missing = sorted(set(CAPS) - set(kinds))
    if missing:
        print('not built yet:', ', '.join(missing))
    if do_render:
        for p in render(wanted or sorted(records), records, objects):
            print('rendered', p)
    for line in problems:
        print('PROBLEM:', line)
    if problems:
        raise SystemExit(1)
    if not objects or only:
        return
    anchors = [mc.to_object(m, collection, materials['Opaque']) for m in mc.anchor_meshes()]
    fbx = os.path.join(HERE, 'fbx', 'Props.fbx')
    mc.export_fbx(fbx, objects + anchors)
    worst = mc.roundtrip_check(fbx, objects + anchors)
    print('FBX round trip within %.2g studs' % worst)
    doc = {'palm_height': PALM_HEIGHT, 'planter_box_height': PLANTER_BOX_HEIGHT, 'kinds': records,
           'total_triangles': total}
    with open(os.path.join(HERE, 'Props.json'), 'w') as handle:
        json.dump(doc, handle, indent=1, sort_keys=True)
        handle.write('\n')
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'Props.blend'), check_existing=False, compress=True)
    backup = os.path.join(HERE, 'Props.blend1')
    if os.path.exists(backup):
        os.remove(backup)


main()
