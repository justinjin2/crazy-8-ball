"""The mid backdrop round the rooftop (Stage 5; Spec section 7), built headlessly in Blender: the
city's skyline from the near world's edge (450 studs) out to city_plan's reach (2,300), and
the near islands out to about 2,500 on the ocean side. Everything beyond is painted into the
skybox (Stage 6), because at low graphics levels Roblox draws nothing that far (STUDIO_NOTES).

    B=/Applications/Blender.app/Contents/MacOS/Blender
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_backdrop.py            # the FBX
    $B -b --factory-startup --python-exit-code 1 --python assets/map/gen_backdrop.py -- render  # and renders
    BACKDROP_ONLY=skyline $B ... -- render   # one module: no export, renders in checkpoints/backdrop/skyline/

The pieces live in family modules, assets/map/backdrop/<name>.py (the brief's skyline and
islands generators). Each exposes:
    CAP        its triangle cap
    MATERIALS  {chunk prefix: (image file in textures/, alpha)}: every chunk's image
    SMOOTH     (optional) chunk prefixes to smooth-shade: their coincident vertices are merged
               and every face shaded smooth (soft slopes instead of facets; Stage 5 critic)
    build()    [(chunk name, map_common.Mesh)], in world studs and Roblox axes; pieces with the
               same chunk name are merged into one mesh (one MeshPart in Studio). A chunk name
               is Prefix_i_j (map_common.cell_name); the prefix picks its Config.Map.Backdrop row.
Its strips are its own sheet's, <name>_textures.py (STRIPS, PAD, IMAGE, SEED, draw()), which it
registers with map_common.register_trim so every Mesh method can use them.

It writes fbx/Backdrop.fbx (the chunks plus the anchor cubes; MapBuilder.prepareBackdrop places
it), Backdrop.json (triangles per chunk and module) and Backdrop.blend. It fails (exit 1) on any
check: a chunk wider than a MeshPart can be, a chunk over CHUNK_CAP triangles (the 3D Importer
and EditableMesh stop at 20,000), a module over its cap, the total over TOTAL_CAP, the anchors,
the FBX round trip.
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

import city_plan as cp  # noqa: E402
import map_common as mc  # noqa: E402

TOTAL_CAP = 110000  # the mid backdrop (the brief, section 6)
CHUNK_CAP = 15000  # per MeshPart, well under the importer's 20,000
SPAN_CAP = 2040.0  # studs: a MeshPart is at most 2,048 on a side
LAYOUT = json.load(open(os.path.join(HERE, 'Layout.json')))
W = cp.WORLD


def load_modules(only=None):
    folder = os.path.join(HERE, 'backdrop')
    if folder not in sys.path:
        sys.path.insert(0, folder)
    modules = {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith('.py') or name.startswith('_') or name.endswith('_textures.py'):
            continue
        if only and name[:-3] not in only:
            continue
        spec = importlib.util.spec_from_file_location('backdrop_' + name[:-3], os.path.join(folder, name))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        modules[name[:-3]] = module
    return modules


def image_material(name, image_file, alpha=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nodes.new('ShaderNodeTexImage')
    path = os.path.join(HERE, 'textures', image_file)
    if os.path.exists(path):
        tex.image = bpy.data.images.load(path, check_existing=True)
        links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
        if alpha:
            links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
            if hasattr(mat, 'surface_render_method'):
                mat.surface_render_method = 'BLENDED'
    bsdf.inputs['Roughness'].default_value = 0.8
    return mat


def smooth(obj):
    """Merge an object's coincident vertices (Mesh.face gives every face its own) and shade
    it smooth, so the FBX carries soft normals. UVs are per corner, so they are kept."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.01)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(obj.data)
    bm.free()
    obj['triangle_count'] = len(obj.data.polygons)


def build(modules):
    """{chunk name: Mesh}, {module: triangles}, {chunk: module}, {prefix: (image, alpha)}."""
    chunks, per_module, owner, materials = {}, {}, {}, {}
    for mname, module in modules.items():
        total = 0
        for prefix, mat in module.MATERIALS.items():
            assert prefix not in materials or materials[prefix] == mat, ('two modules use prefix', prefix)
            materials[prefix] = mat
        for chunk, piece in module.build():
            prefix = chunk.split('_')[0]
            assert prefix in module.MATERIALS, ('%s: chunk %s has no material prefix' % (mname, chunk))
            assert owner.get(chunk, mname) == mname, ('two modules build chunk', chunk)
            owner[chunk] = mname
            chunks.setdefault(chunk, mc.Mesh(chunk)).add(piece)
            total += piece.triangles()
        assert total <= module.CAP, ('%s over its cap' % mname, total, module.CAP)
        per_module[mname] = total
    return chunks, per_module, owner, materials


def main():
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    only = [m for m in os.environ.get('BACKDROP_ONLY', '').split(',') if m]
    scene = mc.clear_scene()
    collection = bpy.data.collections.new('Backdrop')
    scene.collection.children.link(collection)
    modules = load_modules(only or None)
    chunks, per_module, owner, prefixes = build(modules)
    smooth_prefixes = set().union(*(getattr(m, 'SMOOTH', set()) for m in modules.values())) if modules else set()
    mats = {prefix: image_material(prefix, image, alpha) for prefix, (image, alpha) in prefixes.items()}
    report, objects, counts = [], [], {}
    total = 0
    for name in sorted(chunks):
        m = chunks[name]
        tris = m.triangles()
        (lo, hi) = m.bounds()
        span = max(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2])
        assert span < SPAN_CAP, (name, round(span), 'wider than a MeshPart can be')
        assert tris <= CHUNK_CAP, (name, tris, 'over the per-chunk cap')
        counts[name] = tris
        total += tris
        report.append('%-22s %6d triangles, %5.0f studs across  (%s)' % (name, tris, span, owner[name]))
        obj = mc.to_object(m, collection, mats[name.split('_')[0]])
        if name.split('_')[0] in smooth_prefixes:
            smooth(obj)
        objects.append(obj)
    for mname, tris in per_module.items():
        report.append('module %-15s %6d triangles (cap %d)' % (mname, tris, modules[mname].CAP))
    assert total <= TOTAL_CAP, ('the mid backdrop over its cap', total)
    report.append('total                  %6d triangles in %d chunks (cap %d)' % (total, len(chunks), TOTAL_CAP))
    if not only:
        anchor_mat = next(iter(mats.values()))
        for a in mc.anchor_meshes():
            objects.append(mc.to_object(a, collection, anchor_mat))
        for name, want in (('AnchorO', (0, 0, 0)), ('AnchorX', (10, 0, 0)), ('AnchorZ', (0, 0, 10))):
            obj = bpy.data.objects[name]
            centre = sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
            got = (centre.x, centre.z, -centre.y)
            assert max(abs(a - b) for a, b in zip(got, want)) < 1e-6, (name, got)
        fbx = os.path.join(HERE, 'fbx', 'Backdrop.fbx')
        mc.export_fbx(fbx, objects)
        worst = mc.roundtrip_check(fbx, objects)
        report.append('FBX round trip within %.2g studs' % worst)
        with open(os.path.join(HERE, 'Backdrop.json'), 'w') as handle:
            json.dump({'chunks': counts, 'modules': per_module, 'total_triangles': total}, handle, indent=1,
                      sort_keys=True)
            handle.write('\n')
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, 'Backdrop.blend'), check_existing=False, compress=True)
        backup = os.path.join(HERE, 'Backdrop.blend1')
        if os.path.exists(backup):
            os.remove(backup)
    print('\n'.join(report))
    if 'render' in args:
        render(collection, os.path.join(HERE, 'checkpoints', 'backdrop', '+'.join(only) if only else 'all'))


# ---------------------------------------------------------------------------------------------
# Checkpoint renders from the roof (render only: a flat sea and ground, the Day sun)
# ---------------------------------------------------------------------------------------------

def _flat(collection, name, rect, y, hex_colour):
    x0, z0, x1, z1 = rect
    data = bpy.data.meshes.new(name)
    data.from_pydata([mc.rb((x0, y, z0)), mc.rb((x0, y, z1)), mc.rb((x1, y, z1)), mc.rb((x1, y, z0))], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    mat = bpy.data.materials.new(name + 'Mat')
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = tuple(mc.srgb_to_linear(c) for c in mc.rgb(hex_colour)) + (1.0,)
    data.materials.append(mat)


def render(collection, out_dir):
    scene = bpy.context.scene
    try:
        scene.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        scene.render.engine = 'CYCLES'
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.view_settings.view_transform = 'Standard'
    r = 6000.0
    _flat(collection, 'SeaPreview', (-r, -r, r, r), W['sea_y'], '#2F92D8')
    _flat(collection, 'LandPreview', (-r, cp.land_z(), cp.land_x(), r), W['street_y'] + 0.05, '#8E9298')
    _flat(collection, 'LandBackPreview', (-r, -r, W['city_back_x'], cp.land_z()), W['street_y'] + 0.05, '#8E9298')
    light = bpy.data.lights.new('Sun', 'SUN')
    light.energy = 4.0
    sun = bpy.data.objects.new('Sun', light)
    collection.objects.link(sun)
    sun.rotation_euler = Vector(mc.rb((0.465, 0.806, 0.367))).normalized().to_track_quat('Z', 'Y').to_euler()
    world = scene.world or bpy.data.worlds.new('World')
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs['Color'].default_value = tuple(mc.srgb_to_linear(c) for c in mc.rgb(mc.hexc('sky_horizon_day'))) + (1.0,)
    bg.inputs['Strength'].default_value = 0.8
    os.makedirs(out_dir, exist_ok=True)
    cams = LAYOUT['cameras']
    views = {v: (cams[v]['pos'], cams[v]['look'], cams[v]['fov']) for v in ('city-side', 'ocean-side', 'high-day', 'entrance')}
    views['overview'] = ((600.0, 1500.0, 1800.0), (-500.0, -300.0, -500.0), 55.0)
    for view, (pos, look, fov) in views.items():
        cam_data = bpy.data.cameras.new('Cam_' + view)
        cam_data.sensor_fit = 'VERTICAL'
        cam_data.angle_y = math.radians(fov)
        cam_data.clip_end = 12000
        cam = bpy.data.objects.new('Cam_' + view, cam_data)
        collection.objects.link(cam)
        p, lk = Vector(mc.rb(pos)), Vector(mc.rb(look))
        cam.location = p
        cam.rotation_euler = (lk - p).to_track_quat('-Z', 'Y').to_euler()
        scene.camera = cam
        scene.render.filepath = os.path.join(out_dir, '%s.png' % view)
        bpy.ops.render.render(write_still=True)
        print('rendered', os.path.relpath(scene.render.filepath, HERE))


main()
