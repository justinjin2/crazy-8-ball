"""Procedural pool-table materials and resumable, per-object PBR baking.

Usage from Blender Python (5.2):
    setup_materials([bpy.data.objects[n] for n in OBJECT_NAMES])
    for name in OBJECT_NAMES:
        bake_object(bpy.data.objects[name], '/absolute/output/textures')

The caller supplies applied meshes with one active UV map. World-space source
textures share a scale measured in Blender units / Roblox studs. The bake keeps
the procedural source materials in the .blend, but binds one baked material per
object. PNGs use sRGB for BaseColor and Non-Color for all data maps. Normal maps
are tangent-space OpenGL (+Y). AO is a separate Cycles AO pass, not multiplied
into BaseColor. A JSON record after each map permits interrupted runs to resume.
"""

import bpy
import hashlib
import json
import os
import time
from array import array
from pathlib import Path


OBJECT_NAMES = ('Bed', 'Cushions', 'Rails', 'Pockets', 'Apron', 'Legs', 'Sights')
MAPS = ('BaseColor', 'Roughness', 'Normal', 'AO', 'Metalness')
BAKE_VERSION = 4


def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _color(rgb):
    return tuple(_linear(v) for v in rgb) + (1.0,)


def _node(nodes, kind, name, location=(0, 0)):
    n = nodes.new(kind)
    n.name = name
    n.label = name
    n.location = location
    return n


def _ramp(nodes, name, low, high, location):
    n = _node(nodes, 'ShaderNodeValToRGB', name, location)
    n.color_ramp.elements[0].position = 0.10
    n.color_ramp.elements[1].position = 0.90
    n.color_ramp.elements[0].color = low
    n.color_ramp.elements[1].color = high
    return n


def _make_source_material(obj):
    name = 'SOURCE_' + obj.name
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_fake_user = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    shader = _node(nodes, 'ShaderNodeBsdfPrincipled', 'Surface', (520, 80))
    out = _node(nodes, 'ShaderNodeOutputMaterial', 'Output', (840, 80))
    links.new(shader.outputs['BSDF'], out.inputs['Surface'])
    shader.inputs['Metallic'].default_value = 0.0
    shader.inputs['IOR'].default_value = 1.46
    shader.inputs['Specular IOR Level'].default_value = 0.30
    position = _node(nodes, 'ShaderNodeNewGeometry', 'World position in studs', (-1000, 240))

    if obj.name in ('Bed', 'Cushions'):
        mat['material_kind'] = 'Tournament-blue worsted cloth'
        mat.diffuse_color = _color((0.028, 0.550, 0.812))
        macro = _node(nodes, 'ShaderNodeTexNoise', 'Very subtle yarn color', (-780, 340))
        macro.inputs['Scale'].default_value = 9.0
        macro.inputs['Detail'].default_value = 2.0
        macro.inputs['Roughness'].default_value = 0.65
        links.new(position.outputs['Position'], macro.inputs['Vector'])
        color = _ramp(nodes, 'Tournament blue', _color((0.026, 0.533, 0.794)),
                      _color((0.031, 0.560, 0.824)), (-440, 400))
        links.new(macro.outputs['Fac'], color.inputs['Fac'])
        links.new(color.outputs['Color'], shader.inputs['Base Color'])
        shader.inputs['Roughness'].default_value = 0.86
        shader.inputs['Sheen Weight'].default_value = 0.035
        shader.inputs['Sheen Roughness'].default_value = 0.78
        nap = _node(nodes, 'ShaderNodeTexNoise', 'Fine worsted felt nap', (-770, -60))
        nap.inputs['Scale'].default_value = 13.0
        nap.inputs['Detail'].default_value = 2.0
        nap.inputs['Roughness'].default_value = 0.62
        links.new(position.outputs['Position'], nap.inputs['Vector'])
        rough = _ramp(nodes, 'Cloth roughness', (0.82, 0.82, 0.82, 1),
                      (0.90, 0.90, 0.90, 1), (-210, 10))
        links.new(nap.outputs['Fac'], rough.inputs['Fac'])
        links.new(rough.outputs['Color'], shader.inputs['Roughness'])
        bump = _node(nodes, 'ShaderNodeBump', 'Subtle cloth micro-normal', (270, -170))
        bump.inputs['Strength'].default_value = 0.19
        bump.inputs['Distance'].default_value = 0.00052
        links.new(nap.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])

    elif obj.name in ('Rails', 'Apron', 'Legs'):
        mat['material_kind'] = 'Matte black stained wood'
        mat.diffuse_color = _color((0.092, 0.101, 0.111))
        grain_vector = _node(nodes, 'ShaderNodeVectorMath', 'Lengthwise wood grain', (-800, 300))
        grain_vector.operation = 'MULTIPLY'
        # The Blender authoring scene is Z-up. Legs have vertical grain.
        grain_vector.inputs[1].default_value = ((4.0, 4.0, 0.25) if obj.name == 'Legs'
                                                 else (0.25, 4.0, 4.0))
        links.new(position.outputs['Position'], grain_vector.inputs[0])
        grain = _node(nodes, 'ShaderNodeTexNoise', 'Subtle stained wood fibers', (-560, 300))
        grain.inputs['Scale'].default_value = 3.4
        grain.inputs['Detail'].default_value = 3.0
        grain.inputs['Roughness'].default_value = 0.68
        links.new(grain_vector.outputs['Vector'], grain.inputs['Vector'])
        color = _ramp(nodes, 'Black wood variation', _color((0.067, 0.074, 0.082)),
                      _color((0.135, 0.145, 0.158)), (-220, 360))
        links.new(grain.outputs['Fac'], color.inputs['Fac'])
        links.new(color.outputs['Color'], shader.inputs['Base Color'])
        rough = _ramp(nodes, 'Matte finish variation', (0.59, 0.59, 0.59, 1),
                      (0.74, 0.74, 0.74, 1), (-210, 60))
        links.new(grain.outputs['Fac'], rough.inputs['Fac'])
        links.new(rough.outputs['Color'], shader.inputs['Roughness'])
        bump = _node(nodes, 'ShaderNodeBump', 'Fine wood relief', (270, -150))
        bump.inputs['Strength'].default_value = 0.28
        bump.inputs['Distance'].default_value = 0.0022
        links.new(grain.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])

    elif obj.name == 'Pockets':
        mat['material_kind'] = 'Matte black molded leather / plastic'
        mat.diffuse_color = _color((0.056, 0.060, 0.065))
        shader.inputs['Base Color'].default_value = mat.diffuse_color
        shader.inputs['Roughness'].default_value = 0.77
        grain = _node(nodes, 'ShaderNodeTexNoise', 'Fine pocket leather grain', (-600, 40))
        grain.inputs['Scale'].default_value = 105.0
        grain.inputs['Detail'].default_value = 2.0
        links.new(position.outputs['Position'], grain.inputs['Vector'])
        rough = _ramp(nodes, 'Matte pocket roughness', (0.70, 0.70, 0.70, 1),
                      (0.83, 0.83, 0.83, 1), (-200, 90))
        links.new(grain.outputs['Fac'], rough.inputs['Fac'])
        links.new(rough.outputs['Color'], shader.inputs['Roughness'])
        bump = _node(nodes, 'ShaderNodeBump', 'Pocket leather micro-normal', (250, -160))
        bump.inputs['Strength'].default_value = 0.035
        bump.inputs['Distance'].default_value = 0.0008
        links.new(grain.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])

    elif obj.name == 'Sights':
        mat['material_kind'] = 'White inset sight diamonds'
        mat.diffuse_color = _color((0.93, 0.935, 0.925))
        shader.inputs['Base Color'].default_value = mat.diffuse_color
        shader.inputs['Roughness'].default_value = 0.43
    else:
        raise ValueError('No pool-table material style defined for ' + obj.name)

    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.material_index = 0
    obj['source_material'] = mat.name
    return mat


def setup_materials(objects):
    """Bind a separate procedural source material to each supplied mesh."""
    if isinstance(objects, dict):
        objects = objects.values()
    result = {}
    for obj in objects:
        if isinstance(obj, str):
            obj = bpy.data.objects[obj]
        if obj.type == 'MESH':
            result[obj.name] = _make_source_material(obj)
    return result


def _save_progress(outdir, objname, record):
    path = outdir / (objname + '_bake.json')
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    os.replace(temporary, path)


def _load_image(path, colorspace):
    image = bpy.data.images.load(str(path), check_existing=True)
    image.colorspace_settings.name = colorspace
    return image


def _geometry_signature(obj):
    """Invalidate cached pixels when any geometry or UV coordinate changes."""
    digest = hashlib.sha256()
    xyz = array('f', [0.0]) * (len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get('co', xyz)
    digest.update(xyz.tobytes())
    uv = array('f', [0.0]) * (len(obj.data.loops) * 2)
    obj.data.uv_layers.active.data.foreach_get('uv', uv)
    digest.update(uv.tobytes())
    digest.update(repr(tuple(tuple(row) for row in obj.matrix_world)).encode('utf-8'))
    return digest.hexdigest()


def _bake_image(obj, source, name, path, size):
    image = bpy.data.images.new(obj.name + '_' + name, width=size, height=size,
                                alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'sRGB' if name == 'BaseColor' else 'Non-Color'
    image.filepath_raw = str(path)
    image.file_format = 'PNG'
    nodes, links = source.node_tree.nodes, source.node_tree.links
    target = nodes.new('ShaderNodeTexImage')
    target.name = 'BAKE_TARGET'
    target.image = image
    for n in nodes:
        n.select = False
    target.select = True
    nodes.active = target
    shader, output = nodes['Surface'], nodes['Output']
    old_surface = output.inputs['Surface'].links[0].from_socket
    emitter = None
    try:
        if name == 'Metalness':
            image.pixels.foreach_set(array('f', (0.0, 0.0, 0.0, 1.0)) * (size * size))
        elif name in ('BaseColor', 'Roughness'):
            source_input = shader.inputs['Base Color' if name == 'BaseColor' else 'Roughness']
            emitter = nodes.new('ShaderNodeEmission')
            emitter.inputs['Strength'].default_value = 1.0
            if source_input.is_linked:
                links.new(source_input.links[0].from_socket, emitter.inputs['Color'])
            else:
                value = source_input.default_value
                emitter.inputs['Color'].default_value = ((value, value, value, 1)
                                                          if isinstance(value, float) else value)
            links.new(emitter.outputs['Emission'], output.inputs['Surface'])
            bpy.ops.object.bake(type='EMIT', use_clear=True, margin=6)
        elif name == 'Normal':
            bpy.ops.object.bake(type='NORMAL', use_clear=True, margin=6,
                                normal_space='TANGENT', normal_r='POS_X',
                                normal_g='POS_Y', normal_b='POS_Z')
        elif name == 'AO':
            old_samples=bpy.context.scene.cycles.samples
            bpy.context.scene.cycles.samples=256
            bpy.ops.object.bake(type='AO', use_clear=True, margin=6)
            bpy.context.scene.cycles.samples=old_samples
        else:
            raise ValueError(name)
        image.save()
    finally:
        if emitter is not None:
            links.new(old_surface, output.inputs['Surface'])
            nodes.remove(emitter)
        nodes.remove(target)
    return image


def _bind_baked_material(obj, source, images):
    name = obj.name + '_PBR'
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = source.diffuse_color
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    shader = _node(nodes, 'ShaderNodeBsdfPrincipled', 'Surface', (350, 150))
    output = _node(nodes, 'ShaderNodeOutputMaterial', 'Output', (700, 150))
    links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    shader.inputs['Metallic'].default_value = 0.0
    shader.inputs['IOR'].default_value = 1.46
    shader.inputs['Specular IOR Level'].default_value = 0.30
    if obj.name in ('Bed', 'Cushions'):
        shader.inputs['Sheen Weight'].default_value = 0.035
        shader.inputs['Sheen Roughness'].default_value = 0.78
    uv = _node(nodes, 'ShaderNodeUVMap', 'Single non-overlapping UV', (-650, 220))
    uv.uv_map = obj.data.uv_layers.active.name
    for index, mapname in enumerate(MAPS):
        tex = _node(nodes, 'ShaderNodeTexImage', mapname, (-340, 450 - index * 240))
        tex.image = images[mapname]
        tex.interpolation = 'Linear'
        tex.extension = 'EXTEND'
        links.new(uv.outputs['UV'], tex.inputs['Vector'])
        if mapname == 'BaseColor':
            links.new(tex.outputs['Color'], shader.inputs['Base Color'])
        elif mapname == 'Roughness':
            links.new(tex.outputs['Color'], shader.inputs['Roughness'])
        elif mapname == 'Metalness':
            links.new(tex.outputs['Color'], shader.inputs['Metallic'])
        elif mapname == 'Normal':
            normal = _node(nodes, 'ShaderNodeNormalMap', 'OpenGL tangent normal', (20, -150))
            normal.space = 'TANGENT'
            normal.uv_map = obj.data.uv_layers.active.name
            links.new(tex.outputs['Color'], normal.inputs['Color'])
            links.new(normal.outputs['Normal'], shader.inputs['Normal'])
        elif mapname == 'AO':
            tex.label = 'AO — separate map, not multiplied into BaseColor'
    mat['source_material'] = source.name
    mat['normal_convention'] = 'Tangent OpenGL +Y'
    mat['AO'] = 'Separate Cycles ambient occlusion bake'
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return mat


def bake_object(obj, outdir, size=1024):
    """Bake all five PNGs and bind their single PBR material; resumes saved maps.

    Other render-visible objects participate in the actual Cycles AO bake.
    Keep staging floors/cameras out of the scene until asset baking finishes.
    Geometry and UV changes invalidate the cache. Delete an object's *_bake.json
    to force regeneration after edits to other scene objects that affect its AO.
    """
    outdir = Path(outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)
    if obj.type != 'MESH' or len(obj.data.uv_layers) != 1:
        raise ValueError(obj.name + ' must be a mesh with exactly one UV map')
    source = bpy.data.materials.get(obj.get('source_material', ''))
    if source is None:
        source = _make_source_material(obj)
    obj.data.materials.clear()
    obj.data.materials.append(source)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 16
    scene.cycles.device = 'CPU'
    scene.render.bake.use_selected_to_active = False
    scene.render.bake.margin = 6
    scene.render.bake.use_clear = True
    if hasattr(scene.render.bake, 'margin_type'):
        scene.render.bake.margin_type = 'EXTEND'
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    obj.hide_set(False)
    obj.hide_render = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    record = {'object': obj.name, 'size': size, 'version': BAKE_VERSION,
              'vertices': len(obj.data.vertices), 'polygons': len(obj.data.polygons),
              'geometry_uv_signature': _geometry_signature(obj),
              'samples': 16, 'maps': {}, 'complete': False}
    record_path = outdir / (obj.name + '_bake.json')
    if record_path.exists():
        prior = json.loads(record_path.read_text())
        keys = ('size', 'version', 'vertices', 'polygons', 'geometry_uv_signature')
        if all(prior.get(key) == record[key] for key in keys):
            record = prior
    images = {}
    for mapname in MAPS:
        path = outdir / (obj.name + '_' + mapname + '.png')
        if mapname in record['maps'] and path.exists() and path.stat().st_size > 0:
            images[mapname] = _load_image(path, 'sRGB' if mapname == 'BaseColor' else 'Non-Color')
            print('BAKE RESUME:', obj.name, mapname, flush=True)
            continue
        started = time.monotonic()
        print('BAKE START:', obj.name, mapname, flush=True)
        images[mapname] = _bake_image(obj, source, mapname, path, size)
        record['maps'][mapname] = {'file': path.name, 'seconds': round(time.monotonic() - started, 3)}
        _save_progress(outdir, obj.name, record)
        print('BAKE DONE:', obj.name, mapname, flush=True)
    _bind_baked_material(obj, source, images)
    record['complete'] = True
    _save_progress(outdir, obj.name, record)
    return record
# Parametric tournament table. Blender Z-up; FBX converts to Y-up.
import bpy, bmesh, math, json, os
from mathutils import Vector
from math import sin,cos,pi,sqrt,radians
PRESETS = {'9ft':(100.0,50.0),'8ft':(88.0,44.0),'7ft':(78.0,39.0)}
PARAMETERS = {
 'studs_per_inch':0.16, 'ball_diameter':2.6, 'cushion_nose_height':1.625,
 'cushion_width':1.8, 'rail_height':2.08, 'rail_width':5.5,
 'corner_mouth':5.2, 'side_mouth':5.72, 'facing_length':1.6,
 'corner_facing_angle':38.0, 'side_facing_angle':13.0,
 'corner_hole_radius':2.45, 'corner_hole_diagonal_offset':2.47,
 'side_hole_radius':2.58, 'side_hole_offset':2.73,
 'cloth_height':2.9, 'bed_thickness':2.0, 'apron_height':7.0,
 'rail_base_below_cloth':0.5, 'apron_inset':0.28, 'bed_top_edge_inset':0.08, 'bed_lower_edge_inset':0.65,
 'apron_wall_thickness':1.15, 'apron_bottom_chamfer_height':0.55,
 'apron_bottom_flare':0.18, 'leg_top_width':6.1, 'leg_bottom_width':4.2,
 'leg_corner_inset':7.0, 'leg_top_overlap':0.45,
 'wood_edge_bevel':0.09, 'cloth_hole_roll':0.085, 'cushion_edge_bevel':0.025,
 'casting_width':0.72, 'casting_height':0.16, 'pocket_lining_thickness':0.10,
 'pocket_depth':6.5, 'hole_segments':64, 'casting_segments':32,
 'sight_long_diagonal':0.52, 'sight_short_diagonal':0.26,
 'sight_offset_from_nose':3.55, 'sight_inset':0.025,
 'sight_recess_border':0.035, 'texture_resolution':1024,
 'uv_pack_margin':0.014, 'spot_fraction_from_end':0.25,
}
PRESET = '9ft'
OUTPUT_DIR = os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.getcwd()
MESH_NAMES=['Bed','Cushions','Rails','Pockets','Apron','Legs','Sights']

def activate(o):
 if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o

def mesh_obj(name,verts,faces,collection=None):
 m=bpy.data.meshes.new(name+'Mesh');m.from_pydata(verts,[],faces);m.update()
 o=bpy.data.objects.new(name,m);(collection or bpy.context.scene.collection).objects.link(o)
 bm=bmesh.new();bm.from_mesh(m);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(m);bm.free()
 return o

def cuboid(name,x,y,z0,z1,cx=0,cy=0):
 v=[(cx+sx*x/2,cy+sy*y/2,z) for z in (z0,z1) for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))]
 return mesh_obj(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])

def boolean(obj,cut):
 activate(obj);md=obj.modifiers.new('Precision cut','BOOLEAN');md.operation='DIFFERENCE';md.solver='EXACT';md.object=cut
 bpy.ops.object.modifier_apply(modifier=md.name);bpy.data.objects.remove(cut,do_unlink=True)

def cylinder_cut(obj,cx,cy,r,lo,hi,segments):
 v=[(cx+r*cos(2*pi*i/segments),cy+r*sin(2*pi*i/segments),z) for z in (lo,hi) for i in range(segments)]
 faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]+[(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
 boolean(obj,mesh_obj('cutter',v,faces))

def bevel(o,w,segments=2):
 activate(o);m=o.modifiers.new('Small edge round','BEVEL');m.width=w;m.segments=segments;m.limit_method='ANGLE';m.angle_limit=radians(25)
 bpy.ops.object.modifier_apply(modifier=m.name)

def combine(name,objects):
 if len(objects)==1: objects[0].name=name;return objects[0]
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();objects[0].name=name
 return objects[0]

def ring_loft(name,levels):
 # Rounded/chamfered rectangle ring with eight vertices per contour.
 def rect(a,b,c,z):return [(-a+c,-b,z),(a-c,-b,z),(a,-b+c,z),(a,b-c,z),(a-c,b,z),(-a+c,b,z),(-a,b-c,z),(-a,-b+c,z)]
 v=[]
 for z,a,b,ai,bi,c in levels:v+=rect(a,b,c,z)+rect(ai,bi,c,z)
 f=[]
 for k in range(len(levels)-1):
  for j in range(8):
   jn=(j+1)%8;v0=k*16
   f.append((v0+j,v0+jn,v0+16+jn,v0+16+j))
   f.append((v0+8+jn,v0+8+j,v0+24+j,v0+24+jn))
 for j in range(8):
  jn=(j+1)%8
  f.append((j,8+j,8+jn,jn));v0=(len(levels)-1)*16
  f.append((v0+j,v0+jn,v0+8+jn,v0+8+j))
 return mesh_obj(name,v,f)

def tapered_leg(name,cx,cy,bottom,top,height):
 v=[]
 for z,w in [(0,bottom),(height,top)]:
  c=.10*w
  v += [(cx+x,cy+y,z) for x,y in [(-w/2+c,-w/2),(w/2-c,-w/2),(w/2,-w/2+c),(w/2,w/2-c),(w/2-c,w/2),(-w/2+c,w/2),(-w/2,w/2-c),(-w/2,-w/2+c)]]
 return mesh_obj(name,v,[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)])

def build_table(preset='9ft',overrides=None):
 p=dict(PARAMETERS);p.update(overrides or {});u=p['studs_per_inch'];inch=lambda n:n*u
 a,b=[inch(q/2) for q in PRESETS[preset]];rw=inch(p['rail_width']);cw=inch(p['cushion_width']);h=p['cloth_height'];rt=h+inch(p['rail_height']);nh=h+inch(p['cushion_nose_height'])
 old_generated=[q for q in bpy.data.scenes if q.get('generated_by')=='Blender MCP / named-parameter Python']
 scene=bpy.data.scenes.new('PoolTable_'+preset)
 bpy.context.window.scene=scene
 for old in old_generated:
  for old_object in list(old.objects):bpy.data.objects.remove(old_object,do_unlink=True)
  bpy.data.scenes.remove(old)
 scene.name='PoolTable_'+preset
 scene.unit_settings.system='NONE';scene.unit_settings.scale_length=1.0
 scene['PARAMETERS']=json.dumps(p,sort_keys=True);scene['PRESETS']=json.dumps(PRESETS);scene['active_preset']=preset
 scene['unit_convention']='1 Blender coordinate unit = 1 Roblox stud; 0.16 stud/in; native Z up; FBX -Z forward Y up'
 scene['pocket_order']='Top is native +Y, exported -Z. Top-left then clockwise.'
 scene['corner_offset_convention']='Radial distance along 45-degree bisector, divided by sqrt(2) on each axis.'
 scene['generated_by']='Blender MCP / named-parameter Python'
 d=inch(p['corner_hole_diagonal_offset'])/sqrt(2);s=inch(p['side_hole_offset']);cr=inch(p['corner_hole_radius']);sr=inch(p['side_hole_radius'])
 holes=[(-a-d,b+d,cr),(0,b+s,sr),(a+d,b+d,cr),(a+d,-b-d,cr),(0,-b-s,sr),(-a-d,-b-d,cr)]
 for i,(x,y,r) in enumerate(holes,1):
  e=bpy.data.objects.new('Pocket'+str(i),None);scene.collection.objects.link(e);e.location=(x,y,h);e.empty_display_type='CIRCLE';e.empty_display_size=r;e['radius_studs']=r;e['export_xyz_studs']=[x,h,-y]
 for name,x in [('HeadSpot',-a+2*a*p['spot_fraction_from_end']),('FootSpot',a-2*a*p['spot_fraction_from_end'])]:
  e=bpy.data.objects.new(name,None);scene.collection.objects.link(e);e.location=(x,0,h);e.empty_display_type='PLAIN_AXES';e.empty_display_size=.12;e['export_xyz_studs']=[x,h,0]
 bv=[]
 for z,inset_bed in [(h-inch(p['bed_thickness']),p['bed_lower_edge_inset']),(h-inch(.49),p['bed_lower_edge_inset']),(h-inch(.36),p['bed_top_edge_inset']),(h,p['bed_top_edge_inset'])]:
  ax=a+rw-inch(inset_bed);by=b+rw-inch(inset_bed)
  c=inch(.9)
  bv += [(-ax+c,-by,z),(ax-c,-by,z),(ax,-by+c,z),(ax,by-c,z),(ax-c,by,z),(-ax+c,by,z),(-ax,by-c,z),(-ax,-by+c,z)]
 bf=[tuple(range(7,-1,-1)),tuple(range(24,32))]
 for k in range(3):
  for j in range(8):bf.append((k*8+j,k*8+(j+1)%8,(k+1)*8+(j+1)%8,(k+1)*8+j))
 bed=mesh_obj('Bed',bv,bf)
 for x,y,r in holes:cylinder_cut(bed,x,y,r,h-inch(p['bed_thickness'])-.5,h+.5,p['hole_segments'])
 bevel(bed,inch(p['cloth_hole_roll']),3)
 # Relief below the cloth collar prevents coplanar cloth/black liner walls.
 for x,y,r in holes:cylinder_cut(bed,x,y,r+inch(p['pocket_lining_thickness'])+inch(.015),h-inch(p['bed_thickness'])-.5,h-inch(.14),p['hole_segments'])
 bed['hole_radius_convention']='Specified radius at vertical throat; top cloth rolls outward by cloth_hole_roll.'
 # Six continuous strips. Nose tips and entire hard ridge remain exact.
 cc=inch(p['corner_mouth'])/sqrt(2);sc=inch(p['side_mouth'])/2;fl=inch(p['facing_length'])
 corner=(fl*cos(radians(p['corner_facing_angle'])),fl*sin(radians(p['corner_facing_angle'])))
 side=(fl*sin(radians(p['side_facing_angle'])),fl*cos(radians(p['side_facing_angle'])))
 parts=[];nose_records=[];facing_records=[]
 def cushion(name,A,B,N,types):
  A=Vector(A);B=Vector(B);N=Vector(N);T=(B-A).normalized();length=(B-A).length
  av,ao=corner if types[0]=='corner' else side;bv,bo=corner if types[1]=='corner' else side
  # Footprint extends toward pocket at both ends; true angled facing ends at a heel seam.
  pts=[(0,0),(length,0),(length+bv,bo),(length+bv,cw),(-av,cw),(-av,ao)]
  # Nose profile: lower sloped face, exact sharp nose, rising sloped shoulder and flat back.
  profile=[(inch(.30),h+inch(.08)),(0,nh),(inch(.46),rt),(cw,rt),(cw,h+inch(.08))]
  # Build longitudinal swept profile; end caps are clipped to facing then heel.
  def extension(v,amount,outward):return amount*min(v/outward,1.0)
  verts=[]
  for end in (0,1):
   for v,z in profile:
    q=-extension(v,av,ao) if end==0 else length+extension(v,bv,bo)
    xy=A+T*q+N*v;verts.append((xy.x,xy.y,z))
  faces=[(j,(j+1)%5,(j+1)%5+5,j+5) for j in range(5)]
  # End faces need the exact 1.6-in angled facing plus a heel at its end.
  # Split end surfaces at specified facing extent using intersecting profile cross sections.
  for end,amount,outward in [(0,av,ao),(1,bv,bo)]:
   idx=end*5
   # profile point on top and underside at the facing/heel boundary
   q=-amount if end==0 else length+amount
   xy=A+T*q+N*outward
   it=len(verts);verts.extend([(xy.x,xy.y,rt),(xy.x,xy.y,h+inch(.08))])
   faces.extend([(idx,idx+1,idx+2,it,it+1),(idx+2,idx+3,it),(idx+3,idx+4,it+1,it),(idx+4,idx,it+1)])
   nose=A if end==0 else B;tip=nose+(-T if end==0 else T)*amount+N*outward
   facing_records.append({'type':types[end],'nose':[nose.x,nose.y,nh],'heel':[tip.x,tip.y,nh],'length':fl})
  o=mesh_obj(name,verts,faces)
  # Bevel non-nose edges only. Exact collision ridge remains pinned.
  attr=o.data.attributes.new('bevel_weight_edge','FLOAT','EDGE')
  for e in o.data.edges:
   z0=o.data.vertices[e.vertices[0]].co.z;z1=o.data.vertices[e.vertices[1]].co.z
   attr.data[e.index].value=0 if abs(z0-nh)<1e-6 or abs(z1-nh)<1e-6 else 1
  activate(o);md=o.modifiers.new('Rounded cloth heels','BEVEL');md.limit_method='WEIGHT';md.width=inch(p['cushion_edge_bevel']);md.segments=2;bpy.ops.object.modifier_apply(modifier=md.name)
  nose_records.append({'A':[A.x,A.y,nh],'B':[B.x,B.y,nh]});parts.append(o)
 for sy in (-1,1):
  cushion('longL',(-a+cc,sy*b),(-sc,sy*b),(0,sy),('corner','side'))
  cushion('longR',(sc,sy*b),(a-cc,sy*b),(0,sy),('side','corner'))
 for sx in (-1,1):cushion('end',(sx*a,-b+cc),(sx*a,b-cc),(sx,0),('corner','corner'))
 cushions=combine('Cushions',parts);cushions['nose_lines_native']=json.dumps(nose_records);cushions['facings_native']=json.dumps(facing_records)
 # Black rail ring, rounded outer corners.
 rails=ring_loft('Rails',[(h-inch(p['rail_base_below_cloth']),a+rw,b+rw,a+cw-inch(.05),b+cw-inch(.05),inch(.65)),(rt,a+rw,b+rw,a+cw-inch(.05),b+cw-inch(.05),inch(.65))])
 for x,y,r in holes:cylinder_cut(rails,x,y,r+inch(.035),h-1,rt+1,p['hole_segments'])
 safe_rail_bevel=min(p['wood_edge_bevel'],.4*(p['rail_width']-p['side_hole_offset']-p['side_hole_radius']-.035))
 bevel(rails,inch(safe_rail_bevel),2)
 rails['effective_bevel_in']=safe_rail_bevel
 # Diamond recesses and separately materialized white inlays.
 sights=[];site=[];off=inch(p['sight_offset_from_nose'])
 for sy in (-1,1):
  for k in (-3,-2,-1,1,2,3):site.append((a*k/4,sy*(b+off),0))
 for sx in (-1,1):
  for k in (-1,0,1):site.append((sx*(a+off),b*k/2,pi/2))
 def diamond(name,x,y,angle,long,short,z0,z1):
  xy=[(0,long/2),(short/2,0),(0,-long/2),(-short/2,0)]
  v=[(x+vx*cos(angle)-vy*sin(angle),y+vx*sin(angle)+vy*cos(angle),z) for z in (z0,z1) for vx,vy in xy]
  return mesh_obj(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
 for x,y,ang in site:
  ld=inch(p['sight_long_diagonal']);sd=inch(p['sight_short_diagonal']);border=inch(p['sight_recess_border']);inset=inch(p['sight_inset'])
  boolean(rails,diamond('Recess',x,y,ang,ld+border,sd+border,rt-inset-inch(.015),rt+1))
  o=diamond('Inlay',x,y,ang,ld,sd,rt-inset-inch(.013),rt-inset);bevel(o,inch(.008),1);sights.append(o)
 sight=combine('Sights',sights);sight['sight_count']=18
 # Pocket lip exterior halves, six complete dark shafts and floors.
 pockets=[];depth=inch(p['pocket_depth']);lining=inch(p['pocket_lining_thickness'])
 for index,(x,y,r) in enumerate(holes):
  outward=math.atan2(y/b,x/a) if abs(x)>1e-8 else (pi/2 if y>0 else -pi/2)
  n=p['casting_segments'];v=[];f=[];width=inch(p['casting_width']);ch=inch(p['casting_height'])
  # Smooth rounded cap with radial profile; outer boundary fits stated footprint.
  profile=[(r+inch(.015),rt-inch(.015)),(r+inch(.045),rt+ch*.65),(r+width*.32,rt+ch),(r+width*.76,rt+ch*.83),(r+width,rt+ch*.25),(r+width,rt-inch(.035))]
  if abs(x)>1e-8:profile=[(r+inch(.015),rt-inch(.015)),(r+inch(.045),rt+ch*.65),(r+width*.32,rt+ch),(r+width*.76,rt+ch*.83),(r+width,rt+ch*.20),(r+width,rt+inch(.01)),(r+width,rt-inch(.035))]
  for profile_index,(rr,zz) in enumerate(profile):
   for j in range(n+1):
    t=outward-pi/2+pi*j/n
    rad=rr
    if abs(x)>1e-8 and profile_index>=5:
     distances=[]
     if cos(t)*x>0:distances.append(((a+rw)* (1 if x>0 else -1)-x)/cos(t))
     if sin(t)*y>0:distances.append(((b+rw)* (1 if y>0 else -1)-y)/sin(t))
     den=(1 if x>0 else -1)*cos(t)+(1 if y>0 else -1)*sin(t)
     if den>0:distances.append((a+b+2*rw-inch(.65)-abs(x)-abs(y))/den)
     if distances:rad=min(distances)
    vx=max(-a-rw,min(a+rw,x+rad*cos(t)));vy=max(-b-rw,min(b+rw,y+rad*sin(t)))
    v.append((vx,vy,zz))
  for k in range(len(profile)-1):
   for j in range(n):q=k*(n+1)+j;f.append((q,q+1,q+n+2,q+n+1))
  f.append(tuple(k*(n+1) for k in range(len(profile)-1,-1,-1)))
  f.append(tuple(k*(n+1)+n for k in range(len(profile))))
  for j in range(n):
   last=(len(profile)-1)*(n+1);f.append((last+j,last+j+1,j+1,j))
  pockets.append(mesh_obj('Casting',v,f))
  # Below cloth: inner shaft with bottom, outer wall for watertight lining.
  n=p['hole_segments'];v=[]
  for rr,z in [(r,h-inch(.14)),(r,h-depth),(r+lining,h-depth-lining),(r+lining,h-inch(.14))]:
   v += [(x+rr*cos(2*pi*j/n),y+rr*sin(2*pi*j/n),z) for j in range(n)]
  f=[]
  for k in (0,2):
   for j in range(n):j1=(j+1)%n;f.append((k*n+j,k*n+j1,(k+1)*n+j1,(k+1)*n+j))
  for j in range(n):j1=(j+1)%n;f.append((3*n+j,3*n+j1,j1,j))
  # Dark shaft floor closes full interior circle at requested depth.
  v.append((x,y,h-depth));cent=len(v)-1
  for j in range(n):f.append((cent,n+j,n+(j+1)%n))
  v.append((x,y,h-depth-lining));cent=len(v)-1
  for j in range(n):f.append((cent,2*n+(j+1)%n,2*n+j))
  pockets.append(mesh_obj('Lining',v,f))
 pocket=combine('Pockets',pockets)
 # Apron top insets slightly, last lower band flares outward.
 atop=h-inch(p['rail_base_below_cloth']);abot=atop-inch(p['apron_height']);inset=inch(p['apron_inset']);flare=inch(p['apron_bottom_flare']);th=inch(p['apron_wall_thickness']);ox=a+rw-inset;oy=b+rw-inset
 apron=ring_loft('Apron',[(abot,ox+flare,oy+flare,ox-th,oy-th,inch(.75)),(abot+inch(p['apron_bottom_chamfer_height']),ox,oy,ox-th,oy-th,inch(.75)),(atop,ox,oy,ox-th,oy-th,inch(.75))]);bevel(apron,inch(p['wood_edge_bevel']),2)
 parts=[]
 for sx in (-1,1):
  for sy in (-1,1):
   cx=sx*(a+rw-inch(p['leg_corner_inset']));cy=sy*(b+rw-inch(p['leg_corner_inset']))
   o=tapered_leg('Leg',cx,cy,inch(p['leg_bottom_width']),inch(p['leg_top_width']),abot+inch(p['leg_top_overlap']));bevel(o,inch(p['wood_edge_bevel']),2);parts.append(o)
 legs=combine('Legs',parts)
 objects=[bed,cushions,rails,pocket,apron,legs,sight]
 for o in objects:
  activate(o);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  # Remove bevel degenerates before the final UVs and triangulation.
  bm=bmesh.new();bm.from_mesh(o.data)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000002)
  bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.0000001)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(o.data);bm.free()
  # Triangulation is applied to source as well as enabled in the FBX exporter.
  m=o.modifiers.new('Triangulated delivery','TRIANGULATE');m.quad_method='BEAUTY';m.ngon_method='BEAUTY';bpy.ops.object.modifier_apply(modifier=m.name)
  for poly in o.data.polygons:poly.use_smooth=True
  bm=bmesh.new();bm.from_mesh(o.data)
  for edge in bm.edges:edge.smooth=len(edge.link_faces)==2 and edge.calc_face_angle()<radians(40)
  bm.to_mesh(o.data);bm.free()
  assert len(o.data.polygons)<10000,(o.name,len(o.data.polygons))
  o['triangle_count']=len(o.data.polygons)
 setup_materials(objects)
 scene['physics_native']=json.dumps({'pockets':holes,'nose_height':nh,'rail_top':rt,'playing_half_length':a,'playing_half_width':b})
 return scene,objects

def unwrap_consistent(objects,p=None):
 p=p or PARAMETERS;densities={}
 for o in objects:
  activate(o);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
  bpy.ops.uv.smart_project(angle_limit=radians(30 if o.name=='Rails' else 66),island_margin=p['uv_pack_margin'],area_weight=0,correct_aspect=True,scale_to_bounds=False)
  bpy.ops.uv.average_islands_scale();bpy.ops.uv.pack_islands(rotate=True,margin=p['uv_pack_margin'])
  bpy.ops.object.mode_set(mode='OBJECT');o.data.uv_layers.active.name='UVMap'
  uv=o.data.uv_layers.active.data;area=0
  for f in o.data.polygons:
   aa,bb,cc=[uv[i].uv for i in f.loop_indices];area+=abs((bb.x-aa.x)*(cc.y-aa.y)-(bb.y-aa.y)*(cc.x-aa.x))/2
  mesh_area=sum(f.area for f in o.data.polygons);densities[o.name]=sqrt(area/mesh_area)
 common=min(densities.values())
 for o in objects:
  ratio=common/densities[o.name]
  for loop in o.data.uv_layers.active.data:loop.uv=(loop.uv-Vector((.5,.5)))*ratio+Vector((.5,.5))
  o['texel_density_px_per_stud']=common*p['texture_resolution']
 return common*p['texture_resolution']

def presentation(scene):
 # Studio rig is excluded from export by type/selection.
 def aim(obj,at):obj.rotation_euler=(Vector(at)-obj.location).to_track_quat('-Z','Y').to_euler()
 camd=bpy.data.cameras.new('Presentation Camera');cam=bpy.data.objects.new('Presentation Camera',camd);scene.collection.objects.link(cam);cam.location=(18,-23,20);aim(cam,(0,0,1.5));camd.type='ORTHO';camd.ortho_scale=23;scene.camera=cam
 for name,loc,power,size in [('Key',(-3,-7,17),2300,10),('Fill',(7,4,12),1800,9),('Edge',(-10,6,8),1400,7)]:
  ld=bpy.data.lights.new(name,'AREA');ld.energy=power;ld.shape='DISK';ld.size=size;o=bpy.data.objects.new(name,ld);scene.collection.objects.link(o);o.location=loc;aim(o,(0,0,1))
 world=bpy.data.worlds.new('Studio World');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.7,.75,.85,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45;scene.world=world
 scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1500;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.render.film_transparent=True
 scene.view_settings.view_transform='Standard'
 scene.view_settings.look='Medium High Contrast' if 'Medium High Contrast' in [x.identifier for x in scene.view_settings.bl_rna.properties['look'].enum_items] else 'None'
 for o in scene.objects:
  if o.type=='LIGHT':o.data.energy*=.45
 for area in bpy.context.screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL';area.spaces.active.overlay.show_extras=False

def export_table(path,objects):
 bpy.ops.object.select_all(action='DESELECT')
 for o in bpy.context.scene.objects:
  if o in objects or (o.type=='EMPTY' and (o.name.startswith('Pocket') or o.name in ('HeadSpot','FootSpot'))):o.select_set(True)
 bpy.ops.export_scene.fbx(filepath=path,use_selection=True,object_types={'MESH','EMPTY'},axis_forward='-Z',axis_up='Y',global_scale=1.0,apply_unit_scale=False,apply_scale_options='FBX_SCALE_UNITS',use_space_transform=True,bake_space_transform=True,use_mesh_modifiers=True,use_triangles=True,mesh_smooth_type='OFF',add_leaf_bones=False,bake_anim=False,path_mode='RELATIVE',embed_textures=False,use_custom_props=True)

# Edit PRESET / PARAMETERS then run this text to regenerate and export.
# Set BAKE_TEXTURES True for fully rebuilt maps; baking can take several minutes.
BAKE_TEXTURES=True
RUN_BUILD=True
if RUN_BUILD and __name__ == '__main__':
 scene,objects=build_table(PRESET)
 unwrap_consistent(objects)
 presentation(scene)
 if BAKE_TEXTURES:
  for obj in objects:bake_object(obj,os.path.join(OUTPUT_DIR,'textures'),size=PARAMETERS['texture_resolution'])
 for img in bpy.data.images:
  if img.source=='FILE' and img.filepath:img.filepath=bpy.path.relpath(img.filepath,start=OUTPUT_DIR)
 bpy.ops.file.pack_all()
 source=bpy.data.texts.get('PoolTable.py')
 if source is None and '__file__' in globals() and os.path.isfile(__file__):
  source=bpy.data.texts.new('PoolTable.py');source.write(open(__file__).read())
 export_table(os.path.join(OUTPUT_DIR,'PoolTable_'+PRESET+'.fbx'),objects)
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT_DIR,'PoolTable_'+PRESET+'.blend'))
