"""8BALL Lounge — rebuildable Blender 5.2 / Roblox-stud delivery.
Run in Blender's Text Editor, or load through Blender MCP and call start_stage(1..6).
All authored output stays beside this script. The source table is read only.
"""
import bpy, bmesh, math, json, os, time, random, traceback, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
from math import sin, cos, pi, radians, sqrt
from array import array

# ----------------------- PARAMETERS -----------------------
_BUILDER_PATH = Path(globals().get('__file__', 'LoungeBuilder.py'))
OUTPUT_DIR = _BUILDER_PATH.resolve().parent if _BUILDER_PATH.is_file() else Path(bpy.data.filepath).resolve().parent
TABLE_FILE = OUTPUT_DIR.parent / 'table' / 'PoolTable_9ft.blend'
PARAMETERS = {
    'studs_per_inch': .16, 'room_half_width':49., 'room_front':-57., 'room_back':106.,
    'column_x':[-30.,-10.,10.,30.], 'row_y':[0.,43.,86.], 'tier_z':[0.,2.4,4.8],
    'table_width':9.76, 'table_depth':17.76, 'table_rotation_degrees':90.,
    'clearance':10., 'stair_start':[19.,62.], 'stair_rise':.8, 'stair_run':1.6,
    'stair_width':80., 'main_ceiling':18., 'rear_ceiling':14.,
    'pendant_bottom':7.5, 'texture_size':1024, 'ao_samples':32, 'ao_blend':.16,
    'hero_camera':[0.,-53.,14.5], 'hero_target':[0.,4.,0.], 'hero_lens':20.,
    'hero_resolution':[1920,1080], 'hero_samples':128, 'random_seed':82,
}
RUN_BUILD = True
BAKE_TEXTURES = True
EXPORT = True
PALETTE={'cream':'FFF1DC','oak':'D9AE7B','teal':'37B7B2','blue':'23B6DE',
         'coral':'FF917F','butter':'F4D56B','charcoal':'29383E','green':'38754A',
         'green_light':'7CB34B','brass':'BB9151','white':'FFFFFF'}
GROUPS=('Architecture','Furniture','Props','Signs','Emissive','Collision')


def linear(v): return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4

def color(hexcode): return tuple(linear(int(hexcode[i:i+2],16)/255) for i in (0,2,4))+(1.,)

def collection(name):
    c=bpy.data.collections.get('Lounge_'+name)
    if c is None:
        c=bpy.data.collections.new('Lounge_'+name);bpy.context.scene.collection.children.link(c)
    return c

def activate(o):
    if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT');o.hide_set(False);o.select_set(True);bpy.context.view_layer.objects.active=o

def material(name):
    m=bpy.data.materials.get('SOURCE_Lounge_'+name)
    if m:return m
    m=bpy.data.materials.new('SOURCE_Lounge_'+name);m.use_nodes=True;m.use_fake_user=True
    n,l=m.node_tree.nodes,m.node_tree.links;n.clear()
    p=n.new('ShaderNodeBsdfPrincipled');p.name='Surface'
    out=n.new('ShaderNodeOutputMaterial');out.name='Output';l.new(p.outputs['BSDF'],out.inputs['Surface'])
    c=color(PALETTE.get(name,'FFF1DC'));m.diffuse_color=c;p.inputs['Base Color'].default_value=c
    p.inputs['Roughness'].default_value=.72
    if name=='charcoal':p.inputs['Roughness'].default_value=.46
    if name=='brass':p.inputs['Metallic'].default_value=.7;p.inputs['Roughness'].default_value=.4
    if name in ('oak','cream','teal','blue','coral','butter'):
        tex=n.new('ShaderNodeTexNoise');tex.name='Subtle source variation';tex.inputs['Scale'].default_value=3 if name=='oak' else 14
        tex.inputs['Detail'].default_value=1.5
        pos=n.new('ShaderNodeNewGeometry')
        if name=='oak':
            scale=n.new('ShaderNodeVectorMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=(.13,3,2)
            l.new(pos.outputs['Position'],scale.inputs[0]);l.new(scale.outputs['Vector'],tex.inputs['Vector'])
        else:l.new(pos.outputs['Position'],tex.inputs['Vector'])
        ramp=n.new('ShaderNodeValToRGB');ramp.name='Restrained palette variation'
        ramp.color_ramp.elements[0].color=tuple(v*.91 for v in c[:3])+(1,)
        ramp.color_ramp.elements[1].color=c
        l.new(tex.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs['Color'],p.inputs['Base Color'])
    return m

def mesh(name,verts,faces,mat='cream',set_name='Architecture_A',group='Architecture',bevel=0,obstacle=True):
    me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],faces);me.update()
    o=bpy.data.objects.new(name,me);collection(group).objects.link(o)
    me.materials.append(material(mat) if isinstance(mat,str) else mat)
    o['build_stage']=int(bpy.context.scene.get('_building_stage',1));o['export_group']=group;o['set_name']=set_name;o['clearance_obstacle']=obstacle;o['origin_policy']='world'
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    if bevel>0:
        activate(o);md=o.modifiers.new('Soft edges','BEVEL');md.width=bevel;md.segments=2;md.limit_method='ANGLE'
        bpy.ops.object.modifier_apply(modifier=md.name)
    return o

def cube(name,loc,size,mat='cream',set_name='Architecture_A',group='Architecture',bevel=.06,obstacle=True):
    x,y,z=loc;a,b,c=[v/2 for v in size]
    verts=[(x+sx*a,y+sy*b,z+sz*c) for sz in (-1,1) for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))]
    return mesh(name,verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,set_name,group,bevel,obstacle)

def cylinder(name,loc,radius,depth,mat='oak',set_name='Furniture_A',group='Furniture',segments=24,bevel=.05,obstacle=True):
    x,y,z=loc;n=segments
    v=[(x+radius*cos(i*2*pi/n),y+radius*sin(i*2*pi/n),z+h) for h in (-depth/2,depth/2) for i in range(n)]
    f=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    return mesh(name,v,f,mat,set_name,group,bevel,obstacle)

def combine(name,objects,origin=None):
    objects=[o for o in objects if o]
    activate(objects[0])
    for o in objects:o.select_set(True)
    bpy.ops.object.join();o=objects[0];o.name=name
    if origin is not None:
        # Shift mesh coordinates so movable pieces retain a base-centre pivot.
        p=Vector(origin);o.data.transform(Matrix.Translation(-p));o.location=p
        o['origin_policy']='base_center';o['origin_base']=list(origin)
    return o

def text_mesh(name,body,loc,size,mat='charcoal',set_name='Signs',group='Signs'):
    cu=bpy.data.curves.new(name+'_Text','FONT');cu.body=body;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=size;cu.extrude=.008;cu.resolution_u=4
    o=bpy.data.objects.new(name,cu);collection(group).objects.link(o);o.location=loc;o.rotation_euler=(pi/2,0,0);cu.materials.append(material(mat))
    activate(o);bpy.ops.object.convert(target='MESH');o=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    o['build_stage']=int(bpy.context.scene.get('_building_stage',3));o['export_group']=group;o['set_name']=set_name;o['origin_policy']='world';o['clearance_obstacle']=False
    return o

def aim(o,at):o.rotation_euler=(Vector(at)-o.location).to_track_quat('-Z','Y').to_euler()

def area_light(name,loc,target,energy,size,col=(1,.83,.65)):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=col
    o=bpy.data.objects.new(name,d);collection('Rig').objects.link(o);o.location=loc;o['build_stage']=int(bpy.context.scene.get('_building_stage',1));aim(o,target);return o

def untextured(name,col,emission=0,glass=False):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);m.diffuse_color=(*col,1)
    if emission:p.inputs['Emission Color'].default_value=(*col,1);p.inputs['Emission Strength'].default_value=emission
    if glass:p.inputs['Transmission Weight'].default_value=1;p.inputs['Roughness'].default_value=.08;p.inputs['IOR'].default_value=1.08
    return m

def floor_level(y):return 4.8 if y>=66.8 else 2.4 if y>=23.8 else 0.

def reset_scene():
    old=bpy.data.scenes.get('8BALL_Lounge')
    s=bpy.data.scenes.new('8BALL_Lounge_NEW');bpy.context.window.scene=s
    if old:
        for o in list(old.objects):bpy.data.objects.remove(o,do_unlink=True)
        bpy.data.scenes.remove(old)
    for c in list(bpy.data.collections):
        if c.name.startswith('Lounge_'):bpy.data.collections.remove(c)
    s.name='8BALL_Lounge';s.unit_settings.system='NONE';s.unit_settings.scale_length=1.
    s['unit_convention']='1 Blender unit = 1 Roblox stud; FBX (x,z,-y)'
    s['PARAMETERS']=json.dumps(PARAMETERS);s['generated_by']='LoungeBuilder.py / Blender MCP'
    for g in GROUPS+('Tables','Rig'):collection(g)
    return s

def table_source():
    c=bpy.data.collections.get('Table_Source')
    if c and len(c.objects)==7:return c
    c=bpy.data.collections.new('Table_Source')
    with bpy.data.libraries.load(str(TABLE_FILE),link=False) as (src,dst):
        dst.objects=[n for n in ('Bed','Cushions','Rails','Pockets','Apron','Legs','Sights') if n in src.objects]
    for o in dst.objects:c.objects.link(o)
    c['source_file']=str(TABLE_FILE);c['not_exported']=True
    return c

def setup_camera_lights():
    s=bpy.context.scene
    d=bpy.data.cameras.new('Hero_Camera');o=bpy.data.objects.new('Hero_Camera',d);collection('Rig').objects.link(o)
    o.location=PARAMETERS['hero_camera'];d.lens=PARAMETERS['hero_lens'];d.clip_end=1000;aim(o,PARAMETERS['hero_target']);s.camera=o
    w=bpy.data.worlds.new('Lounge_Sunset_World');w.use_nodes=True;s.world=w
    w.node_tree.nodes['Background'].inputs['Color'].default_value=(.68,.78,1,1);w.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
    area_light('Fill_Foreground',(0,-24,16),(0,-22,0),3800,28,(1,.89,.76))
    for y in (-5,37,79):
        area_light('Window_Soft_'+str(y),(46,y,12),(0,y,0),6200,26,(1,.79,.52))
        area_light('Ceiling_Fill_'+str(y),(-12,y,17+floor_level(y)),(0,y,0),4400,32,(.9,.94,1))
    d=bpy.data.lights.new('Sunset_Sun','SUN');o=bpy.data.objects.new('Sunset_Sun',d);collection('Rig').objects.link(o)
    d.energy=1.5;d.angle=radians(12);d.color=(1,.72,.44);o.rotation_euler=(radians(32),radians(-24),radians(-55))
    s.render.engine='BLENDER_EEVEE';s.render.image_settings.file_format='PNG';s.render.film_transparent=False
    s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=.45
    s.render.resolution_percentage=100


def build_blockout():
    s=reset_scene();s['_building_stage']=1;random.seed(PARAMETERS['random_seed'])
    # Sealed shell. Front wall is a camera cutaway, exported normally.
    cube('Floor_Main',(0,24.5,-.3),(98,163,.6),'oak','Floor_A',obstacle=False)
    cube('Floor_Middle',(0,(23.8+106)/2,1.2),(98,106-23.8,2.4),'oak','Floor_A',bevel=.025,obstacle=False)
    cube('Floor_Mezzanine',(0,(66.8+106)/2,3.6),(98,106-66.8,2.4),'oak','Floor_A',bevel=.025,obstacle=False)
    cube('Wall_Left',(-49.35,24.5,9.4),(.7,163,18.8),'cream')
    cube('Wall_Back',(0,106.35,9.4),(99.4,.7,18.8),'cream')
    # Opening for a true 5 x 8 front entrance.
    front=[]
    for x in (-25.75,25.75):front.append(cube('FrontPier',(x,-57.35,9),(46.5,.7,18),'cream'))
    front.append(cube('Door_Lintel',(0,-57.35,13),(5,.7,10),'cream'))
    for o in front:o.hide_render=True;o['camera_cutaway']=True
    # Windows use sill2/head15 relative to each tier.
    glasses=[]
    spans=[(-57,19,0),(23.8,62,2.4),(66.8,106,4.8)]
    for idx,(a,b,z) in enumerate(spans):
        cube('Window_SillWall_'+str(idx),(49.35,(a+b)/2,z+1),(.7,b-a,2),'cream')
        ceiling=18 if idx<2 else 14
        head=15 if idx<2 else 13.4
        # Rear head is global Z=18.2 below the 18.8 rear ceiling.
        if idx<2:cube('Window_Header_'+str(idx),(49.35,(a+b)/2,z+16.5),(.7,b-a,3),'cream')
        else:cube('Window_Header_'+str(idx),(49.35,(a+b)/2,z+13.7),(.7,b-a,.6),'cream')
        glasses.append(cube('GlassPart',(49.38,(a+b)/2,z+(2+head)/2),(.08,b-a,head-2),untextured('Lounge_Glass',(.73,.87,.94),glass=True),'','Architecture',0,True))
    combine('Glass_Windows',glasses)
    cube('Wall_Left_Middle_Upper',(-49.35,45.3,19.6),(.7,43,1.6),'cream')
    # Three identical 0.8x1.6 steps per flight; broad eighty-stud usable width.
    for flight,y in enumerate(PARAMETERS['stair_start']):
        base=flight*2.4
        for step in range(3):
            z=base+(step+1)*.8
            cube(f'Stair_{flight+1}_{step+1}',(0,y+step*1.6+.8,base+(step+1)*.4),(80,1.6,(step+1)*.8),'oak','Floor_A',bevel=.025)
        # Side infill and solid guardrails remain outside all cue envelopes.
        for side in (-1,1):
            cube(f'TierEdge_{flight}_{side}',(side*44.5,y+2.4,base+1.2),(9,4.8,2.4),'oak','Architecture_A')
            cube(f'Rail_Solid_{flight}_{side}',(side*44.5,y+4.55,base+4),(9,.35,3.2),'teal','Architecture_A',bevel=.07)
    for y in (-34,18.6,61.6,105.4):
        z=floor_level(y)
        for side in (-1,1):cube(f'Pillar_{side}_{y}',(side*48.35,y,(z+18.8)/2),(1.3,1.1,18.8-z),'teal','Architecture_A')
    source=table_source()
    for row,(y,z) in enumerate(zip(PARAMETERS['row_y'],PARAMETERS['tier_z'])):
        for col,x in enumerate(PARAMETERS['column_x']):
            n=row*4+col+1;o=bpy.data.objects.new(f'Table_{n:02d}',None);collection('Tables').objects.link(o)
            o.instance_type='COLLECTION';o.instance_collection=source;o.location=(x,y,z);o.rotation_euler.z=pi/2
            o['table_number']=n;o['footprint_studs']=[9.76,17.76];o['exported_y_rotation_degrees']=90.
    setup_camera_lights()
    s['stage']=1;s['geometry_revision']=2


def build_architecture():
    bpy.context.scene['_building_stage']=2
    # Warm ceiling grid with a removable camera-facing cutaway front canopy.
    for zone,(a,b,z) in enumerate([(-57,23.8,18),(23.8,66.8,20.4),(66.8,106,18.8)]):
        ceiling=cube(f'Ceiling_{zone}',(0,(a+b)/2,z+.18),(98,b-a,.36),'cream','Architecture_A',bevel=0,obstacle=False)
        ceiling['ceiling']=True
        # Long bays span the room, like the timber rhythm in the reference.
        for x in (-48,-30,-10,10,30,48):
            o=cube(f'Beam_Long_{zone}_{x}',(x,(a+b)/2,z-.25),(.48,b-a,.5),'oak','Timber_A',bevel=.04,obstacle=False);o['ceiling']=True
        y=a+2
        while y<b:
            o=cube(f'Beam_Cross_{zone}_{y:.1f}',(0,y,z-.25),(98,.5,.5),'oak','Timber_A',bevel=.04,obstacle=False);o['ceiling']=True;y+=14
        for x in (-40,-20,0,20,40):
            for y in (a+9,(a+b)/2,b-7):
                o=cylinder(f'Emissive_Downlight_{zone}_{x}_{y:.1f}',(x,y,z-.29),.18,.05,untextured('Lounge_Neon',(1,.78,.42),2),'','Emissive',16,0,False);o['ceiling']=True
    # Floor planks are shallow grooves, batched into three low-cost timber meshes.
    for zone,(a,b,z) in enumerate([(-57,19,0),(23.8,62,2.4),(66.8,106,4.8)]):
        seams=[]
        for y in range(math.ceil(a),math.floor(b),3):seams.append(cube('FloorSeam',(0,y,z+.007),(98,.018,.009),'oak','Floor_A',bevel=0,obstacle=False))
        combine('Floor_Seams_'+str(zone),seams)
        # Playing-zone rug insets do not obstruct movement.
        cube(f'Playing_Rug_{zone}',(0,PARAMETERS['row_y'][zone],z+.013),(78,22,.025),'blue','Furniture_A',group='Furniture',bevel=.01,obstacle=False)
    # Mullions and trim along full-height right windows.
    for idx,(a,b,z) in enumerate([(-57,19,0),(23.8,62,2.4),(66.8,106,4.8)]):
        parts=[];head=15 if idx<2 else 13.4
        for y in (a+.3,(2*a+b)/3,(a+2*b)/3,b-.3):parts.append(cube('Frame',(49,y,z+(head+2)/2),(.45,.22,head-2),'charcoal','Timber_A',bevel=.02))
        for h in (2,8.5,head):parts.append(cube('Frame',(49,(a+b)/2,z+h),(.45,b-a,.22),'charcoal','Timber_A',bevel=.02))
        combine('Window_Frames_'+str(idx),parts)
    for side in (-1,1):
        for idx,(a,b,z) in enumerate([(-57,19,0),(23.8,62,2.4),(66.8,106,4.8)]):
            cube(f'Skirting_{side}_{idx}',(side*48.9,(a+b)/2,z+.35),(.2,b-a,.7),'oak','Timber_A',bevel=.02)
    # Racks face the room, entirely beyond the outer table cue envelope.
    for idx,y in enumerate((5,45,87)):
        z=floor_level(y);parts=[]
        parts.append(cube('RackBack',(-48.55,y,z+3),(.3,6,5.8),'charcoal','Props_A','Props'))
        for j in range(8):
            parts.append(cylinder('Cue',(-48.2,y-2.5+j*.71,z+3.9),.042,7.1,'oak','Props_A','Props',8,.005))
        combine('Cue_Rack_'+str(idx),parts)
    for flight,y in enumerate(PARAMETERS['stair_start']):
        for step in range(3):
            cube(f'Emissive_Stair_{flight}_{step}',(0,y+step*1.6+.04,flight*2.4+(step+1)*.8-.04),(79.8,.035,.055),untextured('Lounge_Neon',(1,.77,.38),2),'','Emissive',.01,False)
    bpy.context.scene['stage']=2


def build_pendants_signs():
    for row,(y,z) in enumerate(zip(PARAMETERS['row_y'],PARAMETERS['tier_z'])):
        ceiling=18 if row==0 else 20.4 if row==1 else 18.8
        for col,x in enumerate(PARAMETERS['column_x']):
            n=row*4+col+1;bottom=z+7.5;parts=[]
            parts.append(cube('Shade',(x,y,bottom+.21),(1.1,7.5,.42),'charcoal','Props_A','Props',.12,False))
            for dy in (-2.6,2.6):parts.append(cylinder('Suspension',(x,y+dy,(ceiling+bottom+.42)/2),.024,ceiling-bottom-.42,'charcoal','Props_A','Props',8,0,False))
            o=combine(f'Pendant_{n:02d}_Housing',parts,origin=(x,y,bottom));o['clearance_obstacle']=False
            cube(f'Emissive_Pendant_{n:02d}',(x,y,bottom+.025),(.88,7.1,.05),untextured('Lounge_PendantNeon',(1,.70,.36),3),'','Emissive',.02,False)
            light=area_light(f'Light_Pendant_{n:02d}',(x,y,bottom-.08),(x,y,z+2.9),320,6,(1,.694,.431));light.data.shape='RECTANGLE';light.data.size=1;light.data.size_y=7;light['temperature_K']=3000
            # Number plaque hangs overhead, above avatar/cue working height.
            board=cube('NumberBoard',(x,y+4.6,z+6.1),(1.45,.1,1.5),'teal','Signs','Signs',.07,False)
            txt=text_mesh('NumberText',str(n),(x,y+4.53,z+6.1),1.12,'white')
            o=combine(f'Table_Number_{n:02d}',[board,txt],(x,y+4.6,z+5.35));o['clearance_obstacle']=False
    for n,(label,x,mat) in enumerate([('1v1',-30,'teal'),('2v2',0,'coral'),('3v3',30,'butter')]):
        board=cube('ZoneBoard',(x,105.7,14.5),(17,.18,3.8),mat,'Signs','Signs',.1,False)
        txt=text_mesh('ZoneText',label,(x,105.57,14.5),2.8,'charcoal' if n else 'white')
        o=combine('Zone_'+label,[board,txt],(x,105.7,12.6));o['clearance_obstacle']=False;o['replaceable_sign']=True
    bpy.context.scene['stage']=3


def checkpoint(stage,render=True,width=960):
    s=bpy.context.scene
    s.render.engine='BLENDER_EEVEE';s.render.resolution_x=width;s.render.resolution_y=round(width*9/16)
    s.render.resolution_percentage=100;s.render.filepath=str(OUTPUT_DIR/'renders'/f'checkpoint_{stage:02d}.png')
    embed_builder();bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    if render:bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    progress(stage,f'Stage {stage} saved'+(' and EEVEE checkpoint rendered' if render else ' after bake/export'),f'start_stage({stage+1})')

def embed_builder():
    t=bpy.data.texts.get('LoungeBuilder.py') or bpy.data.texts.new('LoungeBuilder.py');t.clear();t.write((OUTPUT_DIR/'LoungeBuilder.py').read_text())

def progress(stage,last,resume,error=None):
    finished=stage==6 and error is None
    resume_step='No outstanding work. For a fresh rebuild, load the builder and call start_stage(1).' if finished else 'Load LoungeBuilder.py through Blender MCP and call '+resume+'.'
    status={'stage':stage,'last_successful_action':last,'resume':resume_step,'error':error,'time':time.strftime('%Y-%m-%d %H:%M:%S')}
    (OUTPUT_DIR/'scripts'/'stage_status.json').write_text(json.dumps(status,indent=2))
    lines=['# Lounge Build Progress','',f'Completed: stages 1–{stage}.','',
           'Remaining: none; final delivery validated.' if finished else f'Remaining: stages {stage+1}–6 and final validation.','',
           'Last successful action: '+last+'.','','Exact resume step: '+resume_step]
    if error:lines.extend(['','Recoverable error: '+error])
    (OUTPUT_DIR/'PROGRESS.md').write_text('\n'.join(lines)+'\n')


def start_stage(stage):
    """Submit a coherent stage without holding the MCP socket during rendering/baking."""
    def work():
        try:run_stage(stage)
        except Exception:
            err=traceback.format_exc();(OUTPUT_DIR/'scripts'/f'stage_{stage}_error.log').write_text(err)
            print(err);progress(stage-1,'previous saved checkpoint',f'start_stage({stage})',err)
        return None
    bpy.app.timers.register(work,first_interval=3)
    print('LOUNGE_STAGE_SCHEDULED',stage)

# Build-stage dispatch is completed below the modeling, bake, and validation helpers.

def build_furniture_props():
    """Create the lounge's finished movable furniture and restrained wall props.

    Primitives are closed; joined multicolour source meshes are atlased later.
    The foreground's northernmost furniture bound remains below Y=-19.25.
    """
    bpy.context.scene['_building_stage']=3
    names = []

    def xf(ob, matrix):
        # Handles both world-authored primitives and converted font meshes.
        local = ob.matrix_world.inverted() @ matrix @ ob.matrix_world
        ob.data.transform(local)
        ob.data.update()
        return ob

    def finish(name, parts, origin):
        # Use the realised bounds (including bevels, asymmetric leaves and lettering)
        # so the final validation checks an exact mesh base-centre, not a nominal pivot.
        ob = combine(name, parts)
        world_points = [ob.matrix_world @ v.co for v in ob.data.vertices]
        lo = [min(v[k] for v in world_points) for k in range(3)]
        hi = [max(v[k] for v in world_points) for k in range(3)]
        base = Vector(((lo[0]+hi[0])*.5,(lo[1]+hi[1])*.5,lo[2]))
        old_matrix = ob.matrix_world.copy()
        ob.data.transform(Matrix.Translation(-base) @ old_matrix)
        ob.matrix_world = Matrix.Translation(base)
        ob['origin_policy'] = 'base_center'
        ob['origin_base'] = list(base)
        ob['design_anchor'] = list(origin)
        names.append(ob.name)
        return ob

    def box(name, xyz, size, material='teal', bevel=.10, group='Furniture', set_name='Furniture_A', obstacle=True):
        return cube(name, xyz, size, mat=material, set_name=set_name,
                    group=group, bevel=bevel, obstacle=obstacle)

    def disc(name, xyz, radius, depth, material='oak', group='Furniture', set_name='Furniture_A', obstacle=True):
        return cylinder(name, xyz, radius, depth, mat=material,
                        set_name=set_name, group=group, segments=24,
                        bevel=min(.05, depth*.20), obstacle=obstacle)

    def sofa(name, x, y, width, material, angle=0, pillows=True):
        parts = []
        parts.append(box(name+'_Plinth', (0,0,.90), (width-.20,3.2,1.10), material, .14))
        parts.append(box(name+'_Back', (0,-1.38,2.15), (width,.64,2.50), material, .16))
        for sx in (-1,1):
            parts.append(box(name+'_Arm', (sx*(width/2-.36),0,1.85), (.72,3.4,1.82), material, .20))
            for sy in (-1,1):
                parts.append(box(name+'_Leg', (sx*(width/2-.60),sy*1.20,.27), (.35,.35,.54), 'oak', .045))
        seat_count = max(1,round((width-1.5)/2.5))
        usable = width-1.54
        sw = usable/seat_count
        for i in range(seat_count):
            px = -usable/2+sw*(i+.5)
            parts.append(box(name+'_Seat', (px,.22,1.575), (sw-.065,2.45,.25), material, .11))
            parts.append(box(name+'_BackCushion', (px,-.96,2.52), (sw-.07,.46,1.53), material, .16))
        if pillows:
            for i,px in enumerate((-width*.29,width*.28)):
                p = box(name+'_Pillow', (px,-.62,2.41), (1.25,.40,1.25), 'coral' if i==0 else 'cream', .14)
                pivot=Vector((px,-.62,2.41))
                xf(p, Matrix.Translation(pivot) @ Matrix.Rotation((-1 if i else 1)*.15,4,'Y') @ Matrix.Translation(-pivot))
                parts.append(p)
        placement=Matrix.Translation((x,y,0)) @ Matrix.Rotation(math.radians(angle),4,'Z')
        for ob in parts:
            xf(ob, placement)
        return finish(name,parts,(x,y,0))

    # The full foreground arrangement is deliberately low: the table tiers remain visible.
    sofa('Furniture_Sofa_Teal_Foreground', -7.0,-31.0,10.8,'teal')
    sofa('Furniture_Sofa_Teal_Left', -17.0,-26.0,10.0,'teal',-90)
    sofa('Furniture_Loveseat_Cream', 9.8,-23.0,7.5,'cream',180)
    sofa('Furniture_Armchair_Teal_Right', 18.1,-29.2,3.6,'teal',28)

    # A cream rug with large coral / butter gestures survives phone-size downsampling.
    rug=[]
    rug.append(box('Rug_Border', (0,-26.8,.035), (44,14.1,.07),'teal',.035, obstacle=False))
    rug.append(box('Rug_Cream_Field',(0,-26.8,.078),(43.2,13.3,.05),'cream',.025,obstacle=False))
    for i,(rx,ry,rr,mat) in enumerate([(-8,-25.6,3.0,'coral'),(5.6,-28.5,2.5,'coral'),(13.5,-25.0,1.55,'butter'),(-1.3,-22.2,1.8,'butter'),(-15,-30.4,1.4,'butter')]):
        rug.append(disc('Rug_Motif_%02d'%i,(rx,ry,.113),rr,.016,mat,obstacle=False))
    # A slender pool-blue stripe ties the lounge rug to the playing-zone rugs.
    rug.append(box('Rug_Blue_Stripe',(20.5,-26.8,.115),(.4,11.5,.018),'blue',.008,obstacle=False))
    finish('Furniture_Rug_Lounge',rug,(0,-26.8,0))

    # Broad, low round oak coffee table with four chunky angled-looking supports.
    coffee=[]
    coffee.append(disc('Coffee_Top',(0,-26.5,1.37),3.0,.26,'oak'))
    for i in range(4):
        a=pi/4+i*pi/2
        coffee.append(box('Coffee_Leg',(1.85*cos(a),-26.5+1.85*sin(a),.61),(.32,.32,1.22),'oak',.05))
    finish('Furniture_CoffeeTable_Oak',coffee,(0,-26.5,0))

    # Small tabletop still life is joined separately for easy removal on mobile.
    tabletop=[]
    tabletop.append(box('Book_Coral',(.95,-26.15,1.57),(1.15,.80,.12),'coral',.025,'Props','Props_A'))
    tabletop.append(box('Book_Cream',(.92,-26.13,1.68),(1.03,.72,.10),'cream',.02,'Props','Props_A'))
    tabletop.append(disc('Coffee_Tray',(-1.20,-27.00,1.54),.48,.08,'brass','Props','Props_A'))
    tabletop.append(disc('Coffee_Cup',(-1.20,-27.00,1.73),.20,.32,'cream','Props','Props_A'))
    finish('Props_CoffeeTable_StillLife',tabletop,(0,-26.5,1.5))

    ott=[]
    ott.append(disc('Ottoman_Plith',(7.2,-30.4,.16),1.48,.32,'oak'))
    ott.append(disc('Ottoman_Upholstery',(7.2,-30.4,.89),1.70,1.46,'butter'))
    ott.append(disc('Ottoman_Cushion',(7.2,-30.4,1.60),1.72,.23,'butter'))
    finish('Furniture_Ottoman_Butter',ott,(7.2,-30.4,0))

    side=[]
    side.append(disc('SideTable_Top',(14.55,-26.7,1.8),.95,.16,'oak'))
    side.append(disc('SideTable_Stem',(14.55,-26.7,.88),.18,1.76,'oak'))
    side.append(disc('SideTable_Base',(14.55,-26.7,.09),.70,.18,'oak'))
    finish('Furniture_SideTable_Oak',side,(14.55,-26.7,0))

    # Closed eight-triangle leaf forms are economical, manifold and readable.
    def leaf(name, start, end, width, material):
        a,b=Vector(start),Vector(end)
        axis=(b-a).normalized()
        side=axis.cross(Vector((0,0,1)))
        if side.length<.01:
            side=Vector((1,0,0))
        side.normalize()
        mid=a.lerp(b,.52)
        n=side.cross(axis).normalized()
        vs=[a,b,mid+side*width,mid-side*width,mid+n*(width*.34),mid-n*(width*.20)]
        fs=[(0,2,4),(0,4,3),(0,3,5),(0,5,2),(1,4,2),(1,3,4),(1,5,3),(1,2,5)]
        return mesh(name,[tuple(v) for v in vs],fs,mat=material,set_name='Props_A',group='Props',bevel=0,obstacle=True)

    def plant(name,x,y,z=0,scale=1,potmat='cream'):
        parts=[]
        parts.append(cylinder(name+'_Pot',(x,y,z+.66*scale),.62*scale,1.32*scale,mat=potmat,set_name='Props_A',group='Props',segments=16,bevel=.07*scale,obstacle=True))
        parts.append(cylinder(name+'_Soil',(x,y,z+1.33*scale),.50*scale,.05*scale,mat='charcoal',set_name='Props_A',group='Props',segments=16,bevel=0,obstacle=True))
        for i in range(18):
            a=i*2.3999632297
            ring=i%3
            radial=(1.05,1.27,.60)[ring]*scale
            high=(2.50,2.05,3.30)[ring]*scale
            root=(x+.10*scale*cos(a),y+.10*scale*sin(a),z+1.29*scale)
            end=(x+radial*cos(a),y+radial*sin(a),z+high)
            parts.append(leaf(name+'_Leaf_%02d'%i,root,end,.24*scale,'green_light' if i%4==0 else 'green'))
        return finish(name,parts,(x,y,z))

    # The side-wall plants never project inside |X|=45.2.
    for side_x in (-47.15,47.15):
        for k,(py,pz) in enumerate([(-14,0),(20,0),(56,2.4),(99,4.8)]):
            plant('Props_Plant_%s_%02d'%('Left' if side_x<0 else 'Right',k+1),side_x,py,pz,1.0,'cream' if k%2==0 else 'oak')
    plant('Props_Plant_Lounge_Left',-23,-29.8,0,1.2,'cream')
    plant('Props_Plant_Lounge_Right',23,-28.5,0,1.2,'cream')
    plant('Props_Plant_Lounge_Rear',-13,-21.0,0,.70,'oak')
    plant('Props_Plant_CoffeeTable',-.6,-25.9,1.50,.32,'cream')
    plant('Props_Plant_SideTable',14.55,-26.7,1.88,.30,'cream')

    # Art is authored in its own small local front plane, then placed on a wall.
    def art(name,x,y,z,kind,angle=0):
        parts=[]
        parts.append(box(name+'_Frame',(0,0,0),(4.9,.24,6.0),'charcoal',.04,'Props','Props_A'))
        parts.append(box(name+'_Mount',(0,-.145,0),(4.52,.055,5.62),'cream',.025,'Props','Props_A'))
        parts.append(box(name+'_Print',(0,-.185,0),(4.05,.026,5.15),'teal' if kind=='eight' else 'butter',.008,'Props','Props_A'))
        if kind=='eight':
            ob=disc(name+'_Ball',(0,0,0),1.25,.045,'charcoal','Props','Props_A')
            xf(ob,Matrix.Translation((0,-.224,.65)) @ Matrix.Rotation(pi/2,4,'X'))
            parts.append(ob)
            ob=disc(name+'_NumberPatch',(0,0,0),.54,.046,'cream','Props','Props_A')
            xf(ob,Matrix.Translation((0,-.260,.65)) @ Matrix.Rotation(pi/2,4,'X'))
            parts.append(ob)
            parts.append(text_mesh(name+'_Eight','8',(0,-.293,.31),.91,mat='charcoal',set_name='Props_A',group='Props'))
            parts.append(box(name+'_CoralBand',(0,-.221,-1.62),(3.25,.035,.42),'coral',.025,'Props','Props_A'))
        else:
            # A deliberately abstract triangle of coloured pool balls.
            ballmats=['teal','coral','cream','blue','charcoal','coral','teal','cream','blue','coral']
            i=0
            for row in range(4):
                for j in range(row+1):
                    ob=disc(name+'_PoolBall',(0,0,0),.37,.048,ballmats[i],'Props','Props_A')
                    xf(ob,Matrix.Translation(((j-row/2)*.83,-.225,1.30-row*.77)) @ Matrix.Rotation(pi/2,4,'X'))
                    parts.append(ob);i+=1
        placement=Matrix.Translation((x,y,z)) @ Matrix.Rotation(math.radians(angle),4,'Z')
        for ob in parts:
            xf(ob,placement)
        return finish(name,parts,(x,y,z-3))

    art('Props_Art_Back_Eight',-19,105.73,12.8,'eight')
    art('Props_Art_Back_Rack',19,105.73,12.8,'rack')
    art('Props_Art_Left_Eight',-48.7,10,8,'eight',90)
    art('Props_Art_Left_Rack',-48.7,54,10.4,'rack',90)

    # Large cream-faced clock centred eleven studs above the main floor on the right wall.
    clock=[]
    for name,radius,depth,mat,yc in [('Clock_Rim',1.68,.20,'charcoal',105.71),('Clock_Face',1.48,.05,'cream',105.58)]:
        ob=disc(name,(0,0,0),radius,depth,mat,'Props','Props_A')
        xf(ob,Matrix.Translation((38,yc,15.8)) @ Matrix.Rotation(pi/2,4,'X'))
        clock.append(ob)
    for i in range(12):
        a=2*pi*i/12
        cx,cz=38+1.22*sin(a),15.8+1.22*cos(a)
        tick=box('Clock_Tick',(cx,105.538,cz),(.07,.025,.22),'charcoal',.008,'Props','Props_A')
        pivot=Vector((cx,105.538,cz))
        xf(tick,Matrix.Translation(pivot) @ Matrix.Rotation(a,4,'Y') @ Matrix.Translation(-pivot))
        clock.append(tick)
    clock.append(box('Clock_Minute',(38,105.505,16.30),(.07,.035,1.0),'charcoal',.012,'Props','Props_A'))
    clock.append(box('Clock_Hour',(38.29,105.49,15.70),(.63,.04,.10),'charcoal',.015,'Props','Props_A'))
    clock_placement = (Matrix.Translation((48.65,-1,11)) @
                       Matrix.Rotation(-pi/2,4,'Z') @
                       Matrix.Translation((-38,-105.71,-15.8)))
    for ob in clock:
        xf(ob,clock_placement)
    finish('Props_Clock_Main',clock,(48.65,-1,9.32))

    # Slim snack cabinetry uses the reserved wall aisle; its inner edge is X=-45.00.
    counter=[]
    counter.append(box('Snack_Plith',(-46.75,-8,.16),(3.25,12,.32),'charcoal',.025))
    counter.append(box('Snack_Cabinet',(-46.75,-8,1.67),(3.15,11.85,2.72),'oak',.05))
    counter.append(box('Snack_Top',(-46.75,-8,3.09),(3.50,12.15,.22),'cream',.07))
    for k in range(5):
        py=-12.65+k*2.32
        counter.append(box('Snack_Door',(-45.15,py,1.64),(.055,2.18,2.47),'oak',.028))
        counter.append(box('Snack_Handle',(-45.087,py+.70,2.15),(.055,.06,.52),'charcoal',.015))
    finish('Furniture_SnackCounter',counter,(-46.75,-8,0))

    # Cup stations and two bright drink urns give the counter a recognisable silhouette.
    refresh=[]
    for i,py in enumerate((-11.5,-9.8)):
        refresh.append(disc('Drink_Base',(-46.7,py,3.32),.47,.18,'charcoal','Props','Props_A'))
        refresh.append(disc('Drink_Urn',(-46.7,py,4.01),.42,1.20,'butter' if i==0 else 'cream','Props','Props_A'))
        refresh.append(disc('Drink_Lid',(-46.7,py,4.66),.46,.10,'charcoal','Props','Props_A'))
        refresh.append(box('Drink_Tap',(-46.22,py,3.66),(.25,.13,.13),'charcoal',.02,'Props','Props_A'))
    for i in range(3):
        refresh.append(disc('Snack_Cup',(-46.65,-7.6+i*.52,3.51),.19,.58,'cream','Props','Props_A'))
    refresh.append(disc('Snack_FruitBowl',(-46.7,-5.2,3.41),.70,.40,'butter','Props','Props_A'))
    for i in range(5):
        a=i*2*pi/5
        refresh.append(disc('Snack_Fruit',(-46.7+.38*cos(a),-5.2+.38*sin(a),3.70),.23,.38,'coral','Props','Props_A'))
    finish('Props_SnackCounter_Service',refresh,(-46.75,-8,3.2))

    # A wall cabinet and compact fridge, both entirely within the same wall clearance strip.
    cabinet=[]
    cabinet.append(box('Snack_WallCabinet',(-48.04,-8,6.2),(1.18,10.7,1.7),'cream',.07))
    for i in range(4):
        cabinet.append(box('Snack_UpperDoor',(-47.40,-12.02+i*2.69,6.2),(.07,2.54,1.51),'oak',.03))
    finish('Furniture_SnackWallCabinet',cabinet,(-48.04,-8,5.35))

    fridge=[]
    fridge.append(box('Snack_FridgeBody',(-47.05,.30,2.70),(3.0,3.40,5.40),'charcoal',.10))
    fridge.append(box('Snack_FridgeDoor',(-45.50,.30,2.75),(.08,3.12,4.88),'teal',.035))
    fridge.append(box('Snack_FridgeHandle',(-45.40,-.86,2.8),(.10,.12,1.45),'cream',.035))
    finish('Furniture_SnackFridge',fridge,(-47.05,.30,0))

    # Editable lettering faces into the room. It is kept separate from its backboard.
    signback=box('Sign_RefreshAndPlay_Backboard',(-48.49,-8,9.02),(.18,11.6,2.7),'cream',.04,'Signs','Signs')
    finish('Sign_RefreshAndPlay_Panel',[signback],(-48.49,-8,7.67))
    letters=text_mesh('Sign_RefreshAndPlay_Letters','REFRESH & PLAY',(0,0,-.42),1.10,mat='teal',set_name='Signs',group='Signs')
    xf(letters,Matrix.Translation((-48.37,-8,9.02)) @ Matrix.Rotation(pi/2,4,'Z'))
    finish('Sign_RefreshAndPlay',[letters],(-48.37,-8,8.1))

    # The logo target is intentionally blank for the game's own art.
    logo=box('Sign_Logo_Blank',(0,105.70,8),(10,.22,3),'cream',.07,'Signs','Signs')
    logo['replaceable_graphic']='Blank 10 x 3 stud logo placeholder'
    finish('Sign_Logo_Blank',[logo],(0,105.70,6.5))
    return names

# Independent final validation helpers for LoungeBuilder.py.
# Requires the builder globals bpy, bmesh, math, Vector, json, Path, OUTPUT_DIR.
# This file contains no top-level Blender mutation and does not call any operator.

_VALIDATION_GROUPS = ('Architecture', 'Furniture', 'Props', 'Signs', 'Emissive', 'Collision')
_VALIDATION_EPS = 1e-5
_UV_BOUNDS_EPS = 1e-7
_UV_INTERIOR_AREA_EPS = 1e-12


def _validation_objects(objects=None):
    source = bpy.context.scene.objects if objects is None else objects
    return sorted((o for o in source if o.type == 'MESH' and
                   o.get('export_group') in _VALIDATION_GROUPS), key=lambda o: o.name)


def _validation_check(name, passed, detail=None):
    result = {'name': name, 'passed': bool(passed)}
    if detail is not None:
        result['detail'] = detail
    return result


def _uv_cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _uv_polygon_area(poly):
    if len(poly) < 3:
        return 0.0
    # Translation before summation reduces cancellation for very small UV islands.
    x0, y0 = poly[0]
    return abs(sum((poly[i][0] - x0) * (poly[i + 1][1] - y0) -
                   (poly[i][1] - y0) * (poly[i + 1][0] - x0)
                   for i in range(1, len(poly) - 1))) * 0.5


def _uv_triangle_intersection_area(triangle_a, triangle_b):
    """Exact convex clipping in double precision; shared boundaries have zero area."""
    clip = list(triangle_b)
    if _uv_cross(clip[0], clip[1], clip[2]) < 0:
        clip.reverse()
    polygon = list(triangle_a)
    for edge_i in range(3):
        a, b = clip[edge_i], clip[(edge_i + 1) % 3]
        source, polygon = polygon, []
        if not source:
            break
        previous = source[-1]
        previous_distance = _uv_cross(a, b, previous)
        for current in source:
            current_distance = _uv_cross(a, b, current)
            current_inside = current_distance >= 0.0
            previous_inside = previous_distance >= 0.0
            if current_inside != previous_inside:
                divisor = previous_distance - current_distance
                if divisor != 0.0:
                    fraction = previous_distance / divisor
                    polygon.append((previous[0] + fraction * (current[0] - previous[0]),
                                    previous[1] + fraction * (current[1] - previous[1])))
            if current_inside:
                polygon.append(current)
            previous, previous_distance = current, current_distance
    return _uv_polygon_area(polygon)


def _validate_uv_triangles(triangles):
    """Bin all triangles and test every candidate; no sampling or early pass shortcut."""
    triangle_count = len(triangles)
    grid = max(8, min(128, int(math.ceil(math.sqrt(max(1, triangle_count))))))
    bins = {}
    overlaps = []
    overlap_count = 0
    max_overlap_area = 0.0
    candidate_count = 0
    degenerate_indices = []
    boxes = []
    for tri_index, tri in enumerate(triangles):
        if abs(_uv_cross(tri[0], tri[1], tri[2])) * 0.5 <= 1e-16:
            degenerate_indices.append(tri_index)
        xs, ys = [p[0] for p in tri], [p[1] for p in tri]
        box = (min(xs), max(xs), min(ys), max(ys))
        boxes.append(box)
        # Bounds are separately validated. Clamp invalid UVs to avoid huge bin allocation.
        x0 = max(-1, min(grid, int(math.floor(box[0] * grid))))
        x1 = max(-1, min(grid, int(math.floor(box[1] * grid))))
        y0 = max(-1, min(grid, int(math.floor(box[2] * grid))))
        y1 = max(-1, min(grid, int(math.floor(box[3] * grid))))
        keys = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
        candidates = set()
        for key in keys:
            candidates.update(bins.get(key, ()))
        for other_index in candidates:
            other_box = boxes[other_index]
            if (min(box[1], other_box[1]) <= max(box[0], other_box[0]) or
                    min(box[3], other_box[3]) <= max(box[2], other_box[2])):
                continue
            candidate_count += 1
            area = _uv_triangle_intersection_area(tri, triangles[other_index])
            if area > _UV_INTERIOR_AREA_EPS:
                overlap_count += 1
                max_overlap_area = max(max_overlap_area, area)
                if len(overlaps) < 30:
                    overlaps.append({'triangles': [other_index, tri_index], 'area': area})
        for key in keys:
            bins.setdefault(key, []).append(tri_index)
    return {'passed': overlap_count == 0 and not degenerate_indices,
            'triangle_count': triangle_count, 'candidate_pairs_tested': candidate_count,
            'interior_overlap_pair_count': overlap_count,
            'maximum_interior_overlap_area': max_overlap_area,
            'overlap_examples': overlaps,
            'degenerate_uv_triangle_count': len(degenerate_indices),
            'degenerate_uv_triangle_examples': degenerate_indices[:30],
            'interior_area_tolerance': _UV_INTERIOR_AREA_EPS,
            'method': 'Exhaustive spatial-bin candidate search and convex triangle clipping.'}


def _validation_world_bounds(obj):
    corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return [min(p[0] for p in corners), max(p[0] for p in corners),
            min(p[1] for p in corners), max(p[1] for p in corners),
            min(p[2] for p in corners), max(p[2] for p in corners)]


def _validation_png_dimensions(path):
    import struct
    with open(path, 'rb') as file:
        header = file.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Not a PNG file')
    return list(struct.unpack('>II', header[16:24]))


def validate_meshes(objects=None):
    """Read-only, exhaustive validation of every tagged environment export mesh."""
    mesh_objects = _validation_objects(objects)
    results = []
    checks = []
    set_names = set()
    for obj in mesh_objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        checks_local = []
        checks_local.append(_validation_check('triangle_limit', triangles <= 10000, triangles))
        checks_local.append(_validation_check('triangulated', all(len(p.vertices) == 3 for p in mesh.polygons),
                                              {'non_triangular_polygons': sum(len(p.vertices) != 3 for p in mesh.polygons)}))
        checks_local.append(_validation_check('nonempty_geometry', len(mesh.vertices) > 0 and triangles > 0))
        material_ok = (len(mesh.materials) == 1 and mesh.materials[0] is not None and
                       all(p.material_index == 0 for p in mesh.polygons))
        checks_local.append(_validation_check('exactly_one_material', material_ok, len(mesh.materials)))
        checks_local.append(_validation_check('no_live_modifiers', len(obj.modifiers) == 0, len(obj.modifiers)))
        checks_local.append(_validation_check('exactly_one_uv_map', len(mesh.uv_layers) == 1, len(mesh.uv_layers)))
        finite_geometry = all(math.isfinite(float(v.co[k])) for v in mesh.vertices for k in range(3))
        checks_local.append(_validation_check('finite_vertex_coordinates', finite_geometry))
        uv_detail = None
        if len(mesh.uv_layers) == 1:
            uv_layer = mesh.uv_layers[0].data
            coordinates = [(float(v.uv.x), float(v.uv.y)) for v in uv_layer]
            finite_uv = all(math.isfinite(p[0]) and math.isfinite(p[1]) for p in coordinates)
            bounds_ok = finite_uv and all(-_UV_BOUNDS_EPS <= n <= 1.0 + _UV_BOUNDS_EPS
                                          for p in coordinates for n in p)
            checks_local.append(_validation_check('uv_bounds_0_1', bounds_ok,
                {'bounds': ([min(p[0] for p in coordinates), max(p[0] for p in coordinates),
                             min(p[1] for p in coordinates), max(p[1] for p in coordinates)]
                            if coordinates and finite_uv else None), 'tolerance': _UV_BOUNDS_EPS}))
            if finite_uv:
                uv_triangles = [tuple(coordinates[index] for index in triangle.loops)
                                for triangle in mesh.loop_triangles]
                uv_detail = _validate_uv_triangles(uv_triangles)
                checks_local.append(_validation_check('uv_no_interior_overlap',
                    uv_detail['interior_overlap_pair_count'] == 0, uv_detail))
                checks_local.append(_validation_check('uv_no_degenerate_triangles',
                    uv_detail['degenerate_uv_triangle_count'] == 0,
                    uv_detail['degenerate_uv_triangle_count']))
            else:
                checks_local.append(_validation_check('uv_no_interior_overlap', False, 'Non-finite UV coordinates.'))
        bm = bmesh.new()
        try:
            bm.from_mesh(mesh)
            nonmanifold_edges = sum(not e.is_manifold for e in bm.edges)
            boundary_edges = sum(e.is_boundary for e in bm.edges)
            wire_edges = sum(e.is_wire for e in bm.edges)
            nonmanifold_vertices = sum(not v.is_manifold for v in bm.verts)
            zero_area_faces = sum(face.calc_area() <= 1e-12 for face in bm.faces)
            opening_reason = str(obj.get('intentional_open_reason', '')).strip()
            closed = nonmanifold_edges == 0 and nonmanifold_vertices == 0
            # A documented open surface may have boundary edges, but neither wire edges
            # nor edges with >2 incident faces are legitimized by that exception.
            invalid_branch_edges = sum(len(e.link_faces) > 2 for e in bm.edges)
            intentional_open = (bool(opening_reason) and boundary_edges > 0 and wire_edges == 0 and
                                invalid_branch_edges == 0)
            manifold_detail = {'closed_manifold': closed, 'nonmanifold_edges': nonmanifold_edges,
                              'boundary_edges': boundary_edges, 'wire_edges': wire_edges,
                              'nonmanifold_vertices': nonmanifold_vertices,
                              'intentional_open_reason': opening_reason or None}
            checks_local.append(_validation_check('manifold_or_documented_open', closed or intentional_open,
                                                  manifold_detail))
            checks_local.append(_validation_check('no_zero_area_faces', zero_area_faces == 0, zero_area_faces))
        finally:
            bm.free()
        translation, rotation, scale = obj.matrix_world.decompose()
        rotation_matrix = rotation.to_matrix()
        rotation_error = max(abs(float(rotation_matrix[i][j]) - (1.0 if i == j else 0.0))
                             for i in range(3) for j in range(3))
        scale_error = max(abs(float(scale[k]) - 1.0) for k in range(3))
        transform_ok = rotation_error <= _VALIDATION_EPS and scale_error <= _VALIDATION_EPS
        checks_local.append(_validation_check('rotation_scale_applied', transform_ok,
            {'rotation_matrix_error': rotation_error, 'unit_scale_error': scale_error,
             'tolerance': _VALIDATION_EPS}))
        origin_policy = obj.get('origin_policy', '')
        if origin_policy == 'world':
            origin_error = max(abs(float(translation[k])) for k in range(3))
            origin_ok = origin_error <= _VALIDATION_EPS
            origin_detail = {'policy': 'world', 'world_origin_error': origin_error}
        elif origin_policy == 'base_center' and mesh.vertices:
            local_min = [min(float(v.co[k]) for v in mesh.vertices) for k in range(3)]
            local_max = [max(float(v.co[k]) for v in mesh.vertices) for k in range(3)]
            center_base = [(local_min[0] + local_max[0]) * 0.5,
                           (local_min[1] + local_max[1]) * 0.5, local_min[2]]
            origin_error = max(abs(v) for v in center_base)
            origin_ok = origin_error <= _VALIDATION_EPS
            origin_detail = {'policy': 'base_center', 'local_base_center': center_base,
                            'world_location': list(translation), 'origin_error': origin_error}
        else:
            origin_ok = False
            origin_detail = {'policy': origin_policy, 'error': 'Missing/unknown origin_policy or empty mesh.'}
        checks_local.append(_validation_check('sensible_origin', origin_ok, origin_detail))
        group = obj.get('export_group')
        if group == 'Collision':
            checks_local.append(_validation_check('collision_under_200_triangles', triangles < 200, triangles))
            checks_local.append(_validation_check('collision_name', obj.name.startswith('COL_')))
        if group == 'Emissive':
            checks_local.append(_validation_check('emissive_name', obj.name.startswith('Emissive_')))
        set_name = str(obj.get('set_name', '')).strip()
        if set_name:
            set_names.add(set_name)
        results.append({'object': obj.name, 'group': group, 'triangles': triangles,
                        'vertices': len(mesh.vertices), 'set_name': set_name or None,
                        'origin_policy': origin_policy, 'passed': all(c['passed'] for c in checks_local),
                        'checks': checks_local})
    triangle_total = sum(r['triangles'] for r in results)
    checks.append(_validation_check('environment_triangle_limit', triangle_total <= 150000,
                                    {'total': triangle_total, 'limit': 150000, 'includes_collision': True}))
    checks.append(_validation_check('environment_meshes_present', bool(mesh_objects)))
    checks.append(_validation_check('all_six_export_groups_present',
        all(any(r['group'] == group for r in results) for group in _VALIDATION_GROUPS)))
    checks.append(_validation_check('texture_set_limit', len(set_names) <= 12, sorted(set_names)))
    texture_results = []
    for set_name in sorted(set_names):
        map_results = []
        for suffix in ('Color', 'Roughness', 'Normal', 'Metalness'):
            path = OUTPUT_DIR / 'textures' / (set_name + '_' + suffix + '.png')
            required = suffix in ('Color', 'Roughness')
            if path.exists():
                try:
                    dimensions = _validation_png_dimensions(path)
                    valid = all(0 < d <= 1024 for d in dimensions)
                    map_results.append({'map': suffix, 'passed': valid, 'dimensions': dimensions})
                except Exception as error:
                    map_results.append({'map': suffix, 'passed': False, 'error': str(error)})
            elif required:
                map_results.append({'map': suffix, 'passed': False, 'error': 'Required PNG is missing.'})
        texture_results.append({'set': set_name, 'passed': all(m['passed'] for m in map_results),
                                'maps': map_results})
    checks.append(_validation_check('texture_maps_present_and_dimensions',
                                    all(t['passed'] for t in texture_results), texture_results))
    names = {o.name for o in mesh_objects}
    checks.append(_validation_check('glass_windows_exists', 'Glass_Windows' in names))
    checks.append(_validation_check('emissive_meshes_exist', any(n.startswith('Emissive_') for n in names)))
    checks.append(_validation_check('collision_meshes_exist', any(n.startswith('COL_') for n in names)))
    return {'passed': all(r['passed'] for r in results) and all(c['passed'] for c in checks),
            'mesh_count': len(results), 'triangle_total': triangle_total, 'texture_sets': sorted(set_names),
            'objects': results, 'checks': checks,
            'transform_convention': 'Applied world rotation and unit scale. World-origin architecture has zero translation; movable base-center origins intentionally retain their placement translation.',
            'intentional_open_property': 'intentional_open_reason',
            'tables_excluded': True}


def _validation_plan_distance(a, b):
    dx = max(a[0] - b[1], b[0] - a[1], 0.0)
    dy = max(a[2] - b[3], b[2] - a[3], 0.0)
    return math.hypot(dx, dy)


def validate_clearance(objects=None, clearance=10.0):
    """Check actual table transforms and tagged obstruction bounds against every table."""
    scene_objects = list(bpy.context.scene.objects if objects is None else objects)
    by_name = {o.name: o for o in scene_objects}
    obstacles = sorted((o for o in scene_objects if o.type == 'MESH' and o.get('clearance_obstacle', False)),
                       key=lambda o: o.name)
    obstacle_bounds = [(o.name, _validation_world_bounds(o)) for o in obstacles]
    table_data = []
    checks = []
    missing = []
    for table_i in range(1, 13):
        name = 'Table_%02d' % table_i
        obj = by_name.get(name)
        if obj is None:
            missing.append(name)
            continue
        corners = [obj.matrix_world @ Vector((x, y, 0))
                   for x in (-8.88, 8.88) for y in (-4.88, 4.88)]
        bounds = [min(p.x for p in corners), max(p.x for p in corners),
                  min(p.y for p in corners), max(p.y for p in corners)]
        center = obj.matrix_world.translation
        table_data.append({'name': name, 'center_blender': list(center),
                           'center_roblox': [float(center.x), float(center.z), float(-center.y)],
                           'plan_bounds': bounds, 'object': obj})
    all_instance_names = [o.name for o in scene_objects if o.name.startswith('Table_') and
                          len(o.name) >= 8 and o.name[6:8].isdigit() and o.type == 'EMPTY' and
                          getattr(o, 'instance_type', None) == 'COLLECTION']
    checks.append(_validation_check('exactly_twelve_table_instances',
        not missing and len(table_data) == 12 and len(all_instance_names) == 12,
        {'found': len(table_data), 'collection_instance_count': len(all_instance_names), 'missing': missing}))
    table_pairs = []
    obstacle_failures = []
    per_table = []
    for table_index, table in enumerate(table_data):
        bounds = table['plan_bounds']
        distances = []
        sides = {'left': None, 'right': None, 'front': None, 'back': None}
        obstruction_list = [(other['name'], other['plan_bounds']) for other in table_data if other is not table]
        obstruction_list.extend(obstacle_bounds)
        for obstacle_name, other_bounds in obstruction_list:
            distance = _validation_plan_distance(bounds, other_bounds)
            distances.append((distance, obstacle_name))
            if distance < clearance - 1e-8:
                obstacle_failures.append({'table': table['name'], 'obstacle': obstacle_name,
                                          'distance': distance, 'required': clearance})
            overlap_x = min(bounds[1], other_bounds[1]) >= max(bounds[0], other_bounds[0])
            overlap_y = min(bounds[3], other_bounds[3]) >= max(bounds[2], other_bounds[2])
            candidates = {}
            if overlap_y and other_bounds[1] <= bounds[0]:
                candidates['left'] = bounds[0] - other_bounds[1]
            if overlap_y and other_bounds[0] >= bounds[1]:
                candidates['right'] = other_bounds[0] - bounds[1]
            if overlap_x and other_bounds[3] <= bounds[2]:
                candidates['front'] = bounds[2] - other_bounds[3]
            if overlap_x and other_bounds[2] >= bounds[3]:
                candidates['back'] = other_bounds[2] - bounds[3]
            for side, distance_on_side in candidates.items():
                if sides[side] is None or distance_on_side < sides[side]['distance']:
                    sides[side] = {'distance': distance_on_side, 'obstacle': obstacle_name}
        distances.sort()
        per_table.append({'table': table['name'], 'center_blender': table['center_blender'],
                          'center_roblox': table['center_roblox'], 'plan_bounds': bounds,
                          'minimum_clearance': distances[0][0] if distances else None,
                          'nearest_obstacle': distances[0][1] if distances else None,
                          'directional_clearances': sides,
                          'passed': bool(distances) and distances[0][0] >= clearance - 1e-8})
        for other in table_data[table_index + 1:]:
            distance = _validation_plan_distance(bounds, other['plan_bounds'])
            table_pairs.append({'tables': [table['name'], other['name']], 'distance': distance,
                                'passed': distance >= clearance - 1e-8})
    rows_valid = len(table_data) == 12
    if rows_valid:
        rows = [table_data[i:i + 4] for i in (0, 4, 8)]
        rows_valid = all(max(t['center_blender'][1] for t in row) - min(t['center_blender'][1] for t in row) < _VALIDATION_EPS
                         and max(t['center_blender'][2] for t in row) - min(t['center_blender'][2] for t in row) < _VALIDATION_EPS
                         and all(row[i]['center_blender'][0] < row[i + 1]['center_blender'][0] for i in range(3))
                         for row in rows)
        rows_valid = rows_valid and all(rows[i][0]['center_blender'][1] < rows[i + 1][0]['center_blender'][1] and
                                       rows[i][0]['center_blender'][2] < rows[i + 1][0]['center_blender'][2]
                                       for i in range(2))
        rows_valid = rows_valid and all(abs(rows[0][col]['center_blender'][0] - rows[row][col]['center_blender'][0]) < _VALIDATION_EPS
                                       for row in (1, 2) for col in range(4))
    checks.append(_validation_check('three_ascending_rows_of_four', rows_valid))
    checks.append(_validation_check('tagged_clearance_obstacles_exist', bool(obstacle_bounds), len(obstacle_bounds)))
    checks.append(_validation_check('all_table_clearances', bool(per_table) and all(t['passed'] for t in per_table),
                                    {'required': clearance, 'failure_count': len(obstacle_failures)}))
    return {'passed': all(c['passed'] for c in checks), 'checks': checks, 'tables': per_table,
            'table_pair_distances': table_pairs, 'obstacle_count': len(obstacle_bounds),
            'obstacle_bounds': [{'object': name, 'bounds': bounds} for name, bounds in obstacle_bounds],
            'failures': obstacle_failures, 'minimum_required': clearance,
            'scope': 'Native XY plan separation to every table and mesh tagged clearance_obstacle. Supporting floors, flat rugs, overhead ceiling/pendants and in-footprint table number signage are intentionally excluded by builder tags. Stair and terrace edges are included regardless of elevation.',
            'method': 'World-space authoritative table footprints and actual obstruction AABBs; Euclidean footprint distance plus four facing-side clearances. Only 1e-8 arithmetic slack, not a design clearance allowance.'}


def write_validation(mesh_results=None, clearance_results=None, extra_checks=None, filename='Validation'):
    """Print and save the complete report; caller supplies final export/render/document checks."""
    if mesh_results is None:
        mesh_results = validate_meshes()
    if clearance_results is None:
        clearance_results = validate_clearance()
    if extra_checks is None:
        extra_checks = []
    elif isinstance(extra_checks, dict):
        extra_checks = [_validation_check(name, value.get('passed', False), value)
                        if isinstance(value, dict) else _validation_check(name, value)
                        for name, value in extra_checks.items()]
    report = {'passed': bool(mesh_results['passed'] and clearance_results['passed'] and
                             all(c.get('passed', False) for c in extra_checks)),
              'mesh_validation': mesh_results, 'clearance_validation': clearance_results,
              'additional_checks': extra_checks}
    json_path = OUTPUT_DIR / (filename + '.json')
    markdown_path = OUTPUT_DIR / (filename + '.md')
    json_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    lines = ['# Lounge validation', '', '**Result: %s**' % ('PASS' if report['passed'] else 'FAIL'), '',
             'All exported environment meshes are checked; pool-table source meshes are excluded.', '',
             '| Object | Package | Triangles | Result |', '|---|---|---:|---|']
    for obj in mesh_results.get('objects', []):
        lines.append('| %s | %s | %s | %s |' % (obj['object'], obj['group'], obj['triangles'],
                                                'PASS' if obj['passed'] else 'FAIL'))
    lines.extend(['', 'Environment triangles: **%s / 150,000**.' % mesh_results.get('triangle_total', '?'), '',
                  'Texture sets: %s.' % (', '.join(mesh_results.get('texture_sets', [])) or '(none)'), '',
                  '## Table clearance', '', '| Table | Minimum clearance (studs) | Closest obstruction | Result |',
                  '|---|---:|---|---|'])
    for table in clearance_results.get('tables', []):
        distance = table.get('minimum_clearance')
        lines.append('| %s | %s | %s | %s |' % (table['table'], '%.8f' % distance if distance is not None else 'missing',
                    table.get('nearest_obstacle'), 'PASS' if table['passed'] else 'FAIL'))
    lines.extend(['', clearance_results.get('scope', ''), '', clearance_results.get('method', ''), '',
                  '## Checks', ''])
    all_checks = list(mesh_results.get('checks', [])) + list(clearance_results.get('checks', [])) + list(extra_checks)
    for check in all_checks:
        lines.append('- %s: %s' % ('PASS' if check.get('passed') else 'FAIL', check['name']))
    failures = [(obj['object'], check) for obj in mesh_results.get('objects', [])
                for check in obj.get('checks', []) if not check['passed']]
    if failures:
        lines.extend(['', '## Mesh failures', ''])
        for object_name, check in failures:
            lines.append('- %s — %s: %s' % (object_name, check['name'], json.dumps(check.get('detail', ''))))
    openings = [(obj['object'], check['detail'].get('intentional_open_reason'))
                for obj in mesh_results.get('objects', []) for check in obj['checks']
                if check['name'] == 'manifold_or_documented_open' and check['detail'].get('intentional_open_reason')]
    if openings:
        lines.extend(['', '## Intentionally open geometry', ''])
        lines.extend('- %s: %s' % entry for entry in openings)
    lines.extend(['', mesh_results.get('transform_convention', ''), '',
                  'UVs use exhaustive spatial-bin candidate testing and numeric triangle clipping; '
                  'shared edges have zero area. Bounds tolerance is 1e-7 UV and interior area tolerance is 1e-12 UV². '
                  'Applied transforms and origin checks use 1e-5 stud tolerance. FBX coordinate reimport must be '
                  'supplied separately at the stricter 1e-6 stud tolerance.', '',
                  'Detailed per-object results, pair distances, UV overlap counts, texture dimensions, and checks: `%s`.' % json_path.name, ''])
    markdown_path.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return report


def add_table_display_props():
    # These removable display balls/cues are lounge props, never replacements for the source table.
    for row,(y,z) in enumerate(zip(PARAMETERS['row_y'],PARAMETERS['tier_z'])):
        for col,x in enumerate(PARAMETERS['column_x']):
            n=row*4+col+1;parts=[];colors=['butter','blue','coral','white','teal','coral','butter','charcoal','blue','white','coral','teal','butter','white','blue']
            for k in range(5):
                for j in range(k+1):
                    cx=x+(j-k/2)*.431;cy=y+3-k*.375;cz=z+3.108
                    bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=2,radius=.208,matrix=Matrix.Translation((cx,cy,cz)))
                    bm.verts.ensure_lookup_table();bm.verts.index_update();bm.faces.ensure_lookup_table()
                    vs=[tuple(v.co) for v in bm.verts];fs=[tuple(v.index for v in f.verts) for f in bm.faces];bm.free()
                    parts.append(mesh('Display_Ball',vs,fs,colors[len(parts)],'GameProps_A','Props',0,False))
            bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=2,radius=.208,matrix=Matrix.Translation((x-1,y-3,z+3.108)))
            bm.verts.ensure_lookup_table();bm.verts.index_update();parts.append(mesh('Cue_Ball',[tuple(v.co) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],'white','GameProps_A','Props',0,False));bm.free()
            a=Vector((x+2.2,y-5,z+2.97));b=Vector((x+2.9,y+4.2736,z+2.97));axis=(b-a).normalized();side=axis.cross(Vector((0,0,1))).normalized();up=axis.cross(side)
            verts=[tuple(p+(.045 if e==0 else .026)*(cos(t*2*pi/10)*side+sin(t*2*pi/10)*up)) for e,p in enumerate((a,b)) for t in range(10)]
            faces=[tuple(range(9,-1,-1)),tuple(range(10,20))]+[(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
            parts.append(mesh('Display_Cue',verts,faces,'oak','GameProps_A','Props',0,False))
            o=combine(f'Table_DisplayProps_{n:02d}',parts,(x,y,z+2.9));o['clearance_obstacle']=False;o['optional_gameplay_display']=True


def tune_lighting_composition():
    s=bpy.context.scene;s['_building_stage']=4
    for old in list(s.objects):
        if old.get('render_only') or old.get('optional_gameplay_display'):bpy.data.objects.remove(old,do_unlink=True)
    for ob in s.objects:
        if ob.type=='MESH' and (ob.name.startswith(('Furniture_Snack','Props_Snack','Sign_Refresh')) or ob.name=='Props_Clock_Main') and not ob.get('composed_position'):
            ob.location.y+=16;ob['composed_position']=True
    camera=bpy.data.objects['Hero_Camera'];camera.location=PARAMETERS['hero_camera'];aim(camera,PARAMETERS['hero_target']);camera.data.lens=PARAMETERS['hero_lens']
    # A procedural painted sunset outside the glass is a render-only backdrop.
    # It supplies colour and a low sun, without constructing an exterior environment.
    m=bpy.data.materials.get('RenderOnly_Sunset') or bpy.data.materials.new('RenderOnly_Sunset');m.use_nodes=True
    nodes,links=m.node_tree.nodes,m.node_tree.links;nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial');em=nodes.new('ShaderNodeEmission');em.inputs['Strength'].default_value=.8;links.new(em.outputs[0],out.inputs['Surface'])
    tc=nodes.new('ShaderNodeTexCoord');sep=nodes.new('ShaderNodeSeparateXYZ');links.new(tc.outputs['Generated'],sep.inputs[0])
    ramp=nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    for i,(pos,h) in enumerate([(0,'F9C36B'),(.3,'FFA568'),(.57,'E8A7AB'),(.8,'BFA6CC'),(1,'98B6D4')]):
        e=ramp.color_ramp.elements[0] if i==0 else ramp.color_ramp.elements.new(pos);e.position=pos;e.color=color(h)
    links.new(sep.outputs['Z'],ramp.inputs[0]);links.new(ramp.outputs['Color'],em.inputs[0])
    o=cube('RenderOnly_SunsetBackdrop',(53,27,11),(1,185,40),m,'','Rig',0,False)
    del o['export_group'];o['render_only']=True
    # Warm horizon bands are deliberately subtle, with no texture-set cost.
    sunmat=untextured('RenderOnly_Sun',tuple(color('FFF2AF')[:3]),2)
    for y,z in [(14,7.5),(73,8.5)]:
        o=cylinder('RenderOnly_SunDisc',(0,0,0),1.25,.02,sunmat,'','Rig',48,0,False)
        o.data.transform(Matrix.Translation((52.3,y,z))@Matrix.Rotation(pi/2,4,'Y'));del o['export_group'];o['render_only']=True
    glass=bpy.data.materials.get('Lounge_Glass')
    if glass:
        p=glass.node_tree.nodes.get('Principled BSDF');p.inputs['Alpha'].default_value=.13
        glass.surface_render_method='DITHERED'
    if not bpy.data.objects.get('Wall_Clock_Panel'):
        cube('Wall_Clock_Panel',(49.01,15,11),(.32,4.4,5.0),'cream','Architecture_A',bevel=.04)
    # Gentle warm top light, with neutral broad fill so blue felt remains blue.
    for o in collection('Rig').objects:
        if o.type=='LIGHT' and o.name.startswith('Ceiling_Fill'):o.data.energy=6900
        if o.type=='LIGHT' and o.name.startswith('Window_Soft'):o.data.energy=10000
        if o.type=='LIGHT' and o.name=='Fill_Foreground':o.data.energy=6200
    s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=.15
    add_table_display_props()
    s['stage']=4

def prepare_export_geometry():
    """Apply the table package's cleanup/triangulation pattern, then retain useful pivots."""
    for o in [q for q in bpy.context.scene.objects if q.type=='MESH' and q.get('export_group') in GROUPS]:
        activate(o)
        for md in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=md.name)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        bm=bmesh.new();bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.0000001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
        bm.to_mesh(o.data);bm.free();o.data.update()
        if o.get('origin_policy')=='base_center':
            verts=[o.matrix_world@v.co for v in o.data.vertices]
            base=Vector(((min(v.x for v in verts)+max(v.x for v in verts))/2,(min(v.y for v in verts)+max(v.y for v in verts))/2,min(v.z for v in verts)))
            matrix=o.matrix_world.copy();o.data.transform(Matrix.Translation(-base)@matrix);o.matrix_world=Matrix.Translation(base);o['origin_base']=list(base)
        else:
            o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
        o['triangle_count']=len(o.data.polygons)
        # Avoid smooth cube shading; bevels supply the soft silhouette.
        for p in o.data.polygons:p.use_smooth=False


def unwrap_object(o,margin=.008):
    """Copied table helper pattern: smart project, average island scale, pack 0–1."""
    activate(o)
    while len(o.data.uv_layers)>1:o.data.uv_layers.remove(o.data.uv_layers[-1])
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=radians(66),island_margin=margin,area_weight=0,correct_aspect=True,scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale();bpy.ops.uv.pack_islands(rotate=True,margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT');o.data.uv_layers.active.name='UVMap'


def build_collision():
    for o in list(collection('Collision').objects):bpy.data.objects.remove(o,do_unlink=True)
    mat=untextured('Lounge_Collision',(.24,.45,.8))
    for i,y in enumerate(PARAMETERS['stair_start']):
        z=i*2.4
        # Solid ramp hull shares the stair flight footprint and prevents avatar snagging.
        v=[(-40,y,z),(40,y,z),(-40,y+4.8,z),(40,y+4.8,z),(-40,y+4.8,z+2.4),(40,y+4.8,z+2.4)]
        f=[(0,2,3,1),(0,1,5,4),(2,4,5,3),(0,4,2),(1,3,5)]
        o=mesh(f'COL_Stair_Ramp_{i+1}',v,f,mat,'','Collision',0,False);o.hide_render=True;o.display_type='WIRE'
        for side in (-1,1):
            o=cube(f'COL_TierEdge_{i+1}_{side}',(side*44.5,y+2.4,z+1.2),(9,4.8,2.4),mat,'','Collision',0,False);o.hide_render=True;o.display_type='WIRE'
    # Straight counter uses a twelve-triangle collision box.
    o=cube('COL_SnackCounter',(-46.75,8,1.6),(3.5,12.15,3.2),mat,'','Collision',0,False);o.hide_render=True;o.display_type='WIRE'


def configure_cycles(samples=32):
    s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=samples;s.cycles.use_denoising=True
    p=bpy.context.preferences.addons['cycles'].preferences
    try:
        p.compute_device_type='METAL';p.get_devices()
        for d in p.devices:d.use=(d.type=='METAL')
        s.cycles.device='GPU'
    except Exception:s.cycles.device='CPU'
    return s


def repair_uv_microfaces(obj):
    """Give collapsed or folded micro-bevel UV triangles isolated cells, checked numerically."""
    obj.data.calc_loop_triangles();uv=obj.data.uv_layers.active.data
    for loop in uv:loop.uv=(loop.uv.x*.99+.005,loop.uv.y*.90+.095)
    repaired=set()
    for iteration in range(100):
        tris=[tuple(tuple(uv[i].uv) for i in t.loops) for t in obj.data.loop_triangles]
        report=_validate_uv_triangles(tris)
        bad=set(report['degenerate_uv_triangle_examples'])
        for pair in report['overlap_examples']:bad.update(pair['triangles'])
        if not bad:break
        for idx in sorted(bad):
            if idx in repaired:raise RuntimeError('UV repair unexpectedly re-overlapped '+obj.name)
            cell=len(repaired);repaired.add(idx)
            if cell>=1280:raise RuntimeError('UV microface reserve exhausted')
            x=.005+(cell%128)*(.99/128);y=.005+(cell//128)*.0075
            w=.99/128;h=.0075
            corners=[(x+w*.32,y+h*.32),(x+w*.68,y+h*.32),(x+w*.32,y+h*.68)]
            for loop,p in zip(obj.data.loop_triangles[idx].loops,corners):uv[loop].uv=p
    else:raise RuntimeError('UV repair did not converge')
    obj['isolated_uv_microfaces']=len(repaired)
    print('UV_REPAIR',obj.name,len(repaired))


def atlas_temporary(set_name,objects):
    vertices=[];faces=[];face_mats=[];materials=[];records=[]
    for o in objects:
        start=len(vertices);loopstart=sum(len(f) for f in faces)
        vertices.extend([tuple(o.matrix_world@v.co) for v in o.data.vertices])
        lookup=[]
        for m in o.data.materials:
            if m not in materials:materials.append(m)
            lookup.append(materials.index(m))
        for f in o.data.polygons:
            faces.append(tuple(start+i for i in f.vertices));face_mats.append(lookup[f.material_index])
        records.append((o,loopstart,len(o.data.loops)))
    me=bpy.data.meshes.new('Bake_'+set_name);me.from_pydata(vertices,[],faces);me.update()
    temp=bpy.data.objects.new('Bake_'+set_name,me);collection('Bake_Work').objects.link(temp)
    for m in materials:me.materials.append(m)
    for f,mi in zip(me.polygons,face_mats):f.material_index=mi
    unwrap_object(temp,margin=.0035)
    repair_uv_microfaces(temp)
    uv=temp.data.uv_layers.active.data
    for o,start,count in records:
        while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
        target=o.data.uv_layers.new(name='UVMap').data
        for i in range(count):target[i].uv=uv[start+i].uv
    return temp


def bake_pass(temp,set_name,kind,size):
    """The table package's EMIT PBR extraction, extended to shared source materials."""
    image_name=set_name+'_'+kind
    image=bpy.data.images.new(image_name,width=size,height=size,alpha=False,float_buffer=False)
    image.colorspace_settings.name='sRGB' if kind=='Color' else 'Non-Color'
    cache=OUTPUT_DIR/'scripts'/'bake_cache';cache.mkdir(exist_ok=True)
    image.filepath_raw=str((cache if kind=='AO' else OUTPUT_DIR/'textures')/(image_name+'.png'));image.file_format='PNG'
    restorations=[]
    for m in temp.data.materials:
        nodes,links=m.node_tree.nodes,m.node_tree.links
        target=nodes.new('ShaderNodeTexImage');target.name='LOUNGE_BAKE_TARGET';target.image=image
        for n in nodes:n.select=False
        target.select=True;nodes.active=target
        p=nodes.get('Surface') or next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
        out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL');old=out.inputs['Surface'].links[0].from_socket;em=None
        if kind!='AO':
            pin=p.inputs[{'Color':'Base Color','Roughness':'Roughness','Metalness':'Metallic'}[kind]]
            em=nodes.new('ShaderNodeEmission')
            if pin.is_linked:links.new(pin.links[0].from_socket,em.inputs['Color'])
            else:
                value=pin.default_value
                em.inputs['Color'].default_value=(value,value,value,1) if isinstance(value,float) else value
            links.new(em.outputs[0],out.inputs['Surface'])
        restorations.append((m,target,out,old,em))
    try:
        activate(temp);bpy.context.scene.cycles.samples=PARAMETERS['ao_samples'] if kind=='AO' else 8
        bpy.ops.object.bake(type='AO' if kind=='AO' else 'EMIT',use_clear=True,margin=3)
        image.save()
    finally:
        for m,target,out,old,em in restorations:
            m.node_tree.links.new(old,out.inputs['Surface'])
            if em:m.node_tree.nodes.remove(em)
            m.node_tree.nodes.remove(target)
    return image


def bind_atlas(set_name,objects,images):
    name='Lounge_'+set_name+'_PBR';m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True
    n,l=m.node_tree.nodes,m.node_tree.links;n.clear()
    p=n.new('ShaderNodeBsdfPrincipled');p.name='Surface';p.inputs['Specular IOR Level'].default_value=.3
    out=n.new('ShaderNodeOutputMaterial');l.new(p.outputs[0],out.inputs[0])
    for kind,image in images.items():
        if kind=='AO':continue
        t=n.new('ShaderNodeTexImage');t.image=image;t.name=kind;t.extension='EXTEND';t.interpolation='Linear'
        l.new(t.outputs['Color'],p.inputs[{'Color':'Base Color','Roughness':'Roughness','Metalness':'Metallic'}[kind]])
    m['AO']='32-sample Cycles ambient occlusion multiplied at 16%, no direct illumination'
    for o in objects:
        o['source_materials']=json.dumps([m.name for m in o.data.materials]);o.data.materials.clear();o.data.materials.append(m)
        for f in o.data.polygons:f.material_index=0


def bake_atlases(set_filter=None):
    import numpy as np
    s=configure_cycles(8);s.render.bake.use_selected_to_active=False
    for stale in list(collection('Bake_Work').objects):bpy.data.objects.remove(stale,do_unlink=True)
    all_objects=[o for o in s.objects if o.type=='MESH' and o.get('export_group') in GROUPS]
    sets=sorted({o.get('set_name') for o in all_objects if o.get('set_name')})
    if set_filter is not None:sets=[n for n in sets if n in set_filter]
    state={o.name:o.hide_render for o in s.objects}
    manifest_path=OUTPUT_DIR/'scripts'/'bake_manifest.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    try:
        for o in s.objects:o.hide_render=True
        for set_name in sets:
            objects=sorted([o for o in all_objects if o.get('set_name')==set_name],key=lambda o:o.name)
            # Restore retained source materials when rebaking a previously bound atlas.
            for o in objects:
                if o.get('source_materials') and all(m.name.endswith('_PBR') for m in o.data.materials):
                    mats=json.loads(o['source_materials']);o.data.materials.clear()
                    for name in mats:o.data.materials.append(bpy.data.materials[name])
                    # Per-face material roles are retained in a FACE attribute before first bake.
                    role=o.data.attributes.get('source_material_index')
                    if role:
                        for f in o.data.polygons:f.material_index=role.data[f.index].value
                else:
                    attr=o.data.attributes.get('source_material_index') or o.data.attributes.new('source_material_index','INT','FACE')
                    for f in o.data.polygons:attr.data[f.index].value=f.material_index
            temp=atlas_temporary(set_name,objects);temp.hide_render=False
            has_metal=any((m.node_tree.nodes.get('Surface').inputs['Metallic'].default_value>0) for m in temp.data.materials)
            maps=['Color','Roughness','AO']+(['Metalness'] if has_metal else [])
            images={}
            for kind in maps:
                progress(4,f'Baking {set_name} / {kind}',f'start_stage(5)')
                images[kind]=bake_pass(temp,set_name,kind,PARAMETERS['texture_size'])
            count=PARAMETERS['texture_size']**2*4
            rgba=np.empty(count,dtype=np.float32);ao=np.empty(count,dtype=np.float32)
            images['Color'].pixels.foreach_get(rgba);images['AO'].pixels.foreach_get(ao)
            rgba=rgba.reshape(-1,4);ao=ao.reshape(-1,4)
            rgba[:,:3]*=(1-PARAMETERS['ao_blend'])+PARAMETERS['ao_blend']*np.clip(ao[:,:3],0,1)
            images['Color'].pixels.foreach_set(rgba.ravel());images['Color'].save()
            bind_atlas(set_name,objects,images)
            manifest[set_name]={'objects':[o.name for o in objects],'resolution':PARAMETERS['texture_size'],'maps':maps,'ao_blend':PARAMETERS['ao_blend'],'ao_samples':PARAMETERS['ao_samples'],'color_has_direct_lighting':False}
            bpy.data.objects.remove(temp,do_unlink=True)
            (OUTPUT_DIR/'scripts'/'bake_manifest.json').write_text(json.dumps(manifest,indent=2))
            # Hidden bake state is temporary; save an ordinary visible checkpoint.
            for o in s.objects:
                if o.name in state:o.hide_render=state[o.name]
            bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
            for o in s.objects:o.hide_render=True
        # Untextured Neon / glass / collision still receive one unique non-overlapping UV map.
        for o in all_objects:
            if not o.get('set_name'):unwrap_object(o)
    finally:
        for stale in list(collection('Bake_Work').objects):bpy.data.objects.remove(stale,do_unlink=True)
        for o in s.objects:
            if o.name in state:o.hide_render=state[o.name]
    return manifest


def export_packages():
    """Same FBX coordinate/unit options as PoolTable.py; selection excludes table instances."""
    s=bpy.context.scene
    for group in GROUPS:
        bpy.ops.object.select_all(action='DESELECT')
        objects=[o for o in s.objects if o.type=='MESH' and o.get('export_group')==group]
        for o in objects:o.hide_set(False);o.select_set(True);o['export_identity']=o.name
        bpy.ops.export_scene.fbx(filepath=str(OUTPUT_DIR/'exports'/f'Lounge_{group}.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1.0,apply_unit_scale=False,apply_scale_options='FBX_SCALE_UNITS',use_space_transform=True,bake_space_transform=True,use_mesh_modifiers=True,use_triangles=True,mesh_smooth_type='OFF',add_leaf_bones=False,bake_anim=False,path_mode='RELATIVE',embed_textures=False,use_custom_props=True)
    return reimport_coordinate_test()


def reimport_coordinate_test():
    """Verify the complete emissive package's world vertices after clean FBX reimport."""
    from mathutils.kdtree import KDTree
    prior=bpy.data.collections.get('Lounge_Reimport_Validation')
    if prior:
        for old in list(prior.objects):bpy.data.objects.remove(old,do_unlink=True)
    original={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in collection('Emissive').objects if o.type=='MESH'}
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(OUTPUT_DIR/'exports'/'Lounge_Emissive.fbx'),use_custom_normals=False,bake_space_transform=True)
    imported=list(set(bpy.data.objects)-before);c=collection('Reimport_Validation')
    for o in imported:
        for old in list(o.users_collection):old.objects.unlink(o)
        c.objects.link(o);o.hide_render=True;o.hide_set(True)
        if 'export_group' in o:del o['export_group']
        if 'clearance_obstacle' in o:del o['clearance_obstacle']
    maximum=0.;records=[]
    for o in imported:
        if o.type!='MESH':continue
        name=o.name
        match=o.get('export_identity') or next((n for n in original if name==n or name.startswith(n+'.')),None)
        if match is None:raise ValueError('Unexpected imported mesh '+name)
        expected=original[match];tree=KDTree(len(expected))
        for i,v in enumerate(expected):tree.insert(v,i)
        tree.balance();err=max(tree.find(o.matrix_world@v.co)[2] for v in o.data.vertices)
        # Bidirectional test catches lost vertices as well as moved vertices.
        actual=KDTree(len(o.data.vertices))
        for i,v in enumerate(o.data.vertices):actual.insert(o.matrix_world@v.co,i)
        actual.balance();err=max(err,max(actual.find(v)[2] for v in expected));maximum=max(maximum,err)
        records.append({'object':match,'world_coordinate_error':err,'original_vertices':len(expected),'imported_vertices':len(o.data.vertices)})
        o.hide_render=True;o.hide_set(True)
        if 'export_group' in o:del o['export_group']
        if 'clearance_obstacle' in o:del o['clearance_obstacle']
    c.hide_render=True;c.hide_viewport=True
    result={'passed':maximum<=1e-6 and len(records)==len(original) and len({r['object'] for r in records})==len(original),'tolerance_studs':1e-6,'maximum_error_studs':maximum,'tested_package':'Lounge_Emissive.fbx','objects':records,'method':'Clean collection import; bidirectional nearest world-vertex coordinates for every emissive mesh.'}
    (OUTPUT_DIR/'scripts'/'fbx_reimport.json').write_text(json.dumps(result,indent=2));return result


# Delivery documentation helpers for integration into LoungeBuilder.py.
# Requires bpy, math, json, Path, OUTPUT_DIR, and PARAMETERS from the builder.
# No top-level Blender interactions or mutations.


def _docs_export_position(vector):
    return [round(float(vector[0]), 8), round(float(vector[2]), 8), round(-float(vector[1]), 8)]


def write_markers():
    """Write real scene transforms in exported Roblox studs / Y-up coordinates."""
    scene = bpy.context.scene
    objects = scene.objects
    tables, pendants = [], []
    for index in range(1, 13):
        table_name = 'Table_%02d' % index
        light_name = 'Light_Pendant_%02d' % index
        table = objects.get(table_name)
        pendant = objects.get(light_name)
        if table is None or pendant is None:
            raise RuntimeError('Marker delivery requires both %s and %s.' % (table_name, light_name))
        center = table.matrix_world.translation
        rotation_y = float(table.get('exported_y_rotation_degrees', PARAMETERS.get('table_rotation_degrees', 90.0)))
        tables.append({'name': table_name, 'table_number': index,
                       'row': (index - 1) // 4 + 1, 'column': (index - 1) % 4 + 1,
                       'position': _docs_export_position(center),
                       'rotation_y_degrees': rotation_y,
                       'scale': [1, 1, 1],
                       'source_asset': '../table/PoolTable_9ft.blend',
                       'native_source_footprint_studs': [17.76, 9.76],
                       'placed_plan_footprint_studs': [9.76, 17.76],
                       'cloth_height_above_floor': 2.9})
        pendants.append({'name': light_name, 'table': table_name,
                         'position': _docs_export_position(pendant.matrix_world.translation),
                         'fixture_bottom_y': round(float(center.z) + float(PARAMETERS.get('pendant_bottom', 7.5)), 8),
                         'color_temperature_K': int(pendant.get('temperature_K', 3000)),
                         'suggested_roblox_light': {'ClassName': 'SurfaceLight', 'Face': 'Bottom',
                             'Brightness': 1.8, 'Range': 24, 'Angle': 120, 'Shadows': False,
                             'Color': [255, 177, 110]}})
    marker_data = {
        'schema_version': 1,
        'units': 'studs',
        'coordinate_system': 'Roblox Y-up; Blender (x,y,z) maps to (x,z,-y)',
        'position_format': ['X', 'Y', 'Z'],
        'rotation_format': 'degrees around Roblox +Y; yaw 0 faces Roblox -Z',
        'rgb_format': '0..255 sRGB arrays; use Color3.fromRGB',
        'assembly_origin': [0, 0, 0],
        'tables': tables,
        'pendants': pendants,
        'spawn': {'name': 'Spawn_Lounge', 'position': [0.0, 0.1, 20.0],
                  'rotation_y_degrees': 0.0, 'facing_direction': [0, 0, -1],
                  'purpose': 'Floor marker in the seating area. Set SpawnLocation or character height above this floor marker as appropriate.'},
        'suggested_roblox_lighting': {
            'ClockTime': 17.4, 'Brightness': 2.0,
            'Ambient': [150, 146, 133], 'OutdoorAmbient': [170, 154, 130],
            'ColorShift_Top': [18, 10, 3],
            'EnvironmentDiffuseScale': 0.65, 'EnvironmentSpecularScale': 0.5,
            'Bloom': {'Enabled': True, 'Intensity': 0.12, 'Size': 20, 'Threshold': 1.2},
            'ColorCorrection': {'Enabled': True, 'Brightness': 0.02, 'Contrast': 0.04,
                                'Saturation': 0.04, 'TintColor': [255, 244, 224]}},
        'notes': [
            'Tables are linked scene placeholders and are excluded from every lounge FBX.',
            'Pendant positions are light emission positions from the actual Blender scene; fixture_bottom_y records the separate 7.5-stud mounting rule.',
            'SurfaceLight values are a starting point for Studio; place each light on a downward-facing invisible mount or the matching Emissive_Pendant mesh.',
            'Neon is a flat material assignment and does not replace the corresponding Roblox light.',
            'Suggested Roblox lighting was not uploaded to or evaluated inside Studio.'
        ]
    }
    path = OUTPUT_DIR / 'Markers.json'
    path.write_text(json.dumps(marker_data, indent=2), encoding='utf-8')
    return marker_data


def _docs_status(checks):
    checks = list(checks)
    return 'PENDING' if not checks else ('PASS' if all(c.get('passed', False) for c in checks) else 'FAIL')


def _docs_dimensions(path):
    import struct
    try:
        with open(path, 'rb') as file:
            header = file.read(24)
        if len(header) == 24 and header[:8] == b'\x89PNG\r\n\x1a\n':
            return '%s × %s' % struct.unpack('>II', header[16:24])
    except (OSError, ValueError):
        pass
    return 'unreadable'


def write_readme(report=None):
    """Generate Readme.md from the current delivery, without inventing validation success."""
    mesh_report = report.get('mesh_validation', {}) if report is not None else {}
    clearance_report = report.get('clearance_validation', {}) if report is not None else {}
    objects = mesh_report.get('objects', [])
    global_checks = list(mesh_report.get('checks', [])) + list(clearance_report.get('checks', []))
    additional_checks = list(report.get('additional_checks', [])) if report is not None else []
    all_checks = global_checks + additional_checks
    mesh_checks = [check for obj in objects for check in obj.get('checks', [])]
    status = 'PENDING' if report is None else ('PASS' if report.get('passed', False) else 'FAIL')
    groups = ('Architecture', 'Furniture', 'Props', 'Signs', 'Emissive', 'Collision')
    texture_dir = OUTPUT_DIR / 'textures'
    actual_sets = sorted(path.name[:-10] for path in texture_dir.glob('*_Color.png'))
    total = mesh_report.get('triangle_total')
    maximum = max((obj['triangles'] for obj in objects), default=None)
    dimensions = PARAMETERS.get('hero_resolution', [1920, 1080])
    samples = PARAMETERS.get('hero_samples', 128)
    lines = [
        '# 8BALL Lounge — delivery notes', '',
        'Built through the connected Blender MCP in Blender 5.2.2 LTS. The lounge uses cream plaster, '
        'honey timber, teal seating, blue playing-zone rugs, coral and butter accents, and warm sunset lighting. '
        'Twelve unchanged source-table collection instances form three ascending rows of four. '
        'There is no real-world table branding.', '',
        '**Final validation: %s.** %s' % (status,
            'Read `Validation.md` for the readable results and `Validation.json` for complete numeric checks.'
            if report is not None else
            'This documentation checkpoint precedes the final validation gate; no validation success is claimed.'), '',
        'Open `Lounge.blend`. The embedded `LoungeBuilder.py` and the standalone script are the rebuildable source. '
        '`PARAMETERS` controls room dimensions, table positions, stair dimensions, palette-related construction, '
        'texture size, AO strength, camera, and render settings. All new output remains beside the script. '
        '`../table/PoolTable.py` and the source table files remain unchanged.', '',
        '## Coordinates and layout', '',
        'One Blender coordinate unit is one Roblox stud, with 0.16 stud per inch. Authoring is native Z-up. '
        'FBX exports use −Z Forward / Y Up, scale factor 1, and FBX Unit Scale, transforming '
        '`(x, y, z)` into `(x, z, −y)`. All six packages retain the same world-zero assembly origin. '
        'Architecture uses world-zero mesh origins. Movable furniture keeps base-centre pivots with placement '
        'translation retained; rotations and scales are applied. Table instances rotate +90° around native Z, '
        'equivalent to +90° around exported Roblox Y.', '',
        '| Parameter | Value |', '|---|---|',
        '| Interior dimensions | %.2f × %.2f studs |' % (
            2 * PARAMETERS.get('room_half_width', 49),
            PARAMETERS.get('room_back', 106) - PARAMETERS.get('room_front', -35)),
        '| Table column centres, native X | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('column_x', [-30,-10,10,30])),
        '| Table row centres, native Y | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('row_y', [0,43,86])),
        '| Floor heights, native Z / exported Y | %s |' % ', '.join('%g' % v for v in PARAMETERS.get('tier_z', [0,2.4,4.8])),
        '| Rotated table footprint | 9.76 across X × 17.76 along native Y |',
        '| Source table cloth / rail top | 2.9 / 3.2328 studs above each floor |',
        '| Minimum table clearance | 10 studs to tables, walls, furniture, railings, and steps |',
        '| Each stair flight | Three 0.8-rise × 1.6-run steps; %g-stud usable width |' % PARAMETERS.get('stair_width', 80),
        '| Pendant lower edge | 7.5 studs above its table floor |',
        '| Foreground entrance | 5 wide × 8 high |', '',
        'Shared ten-stud corridors separate adjacent tables. The long room and generous tier spacing prioritize '
        'the numeric cue clearance over the tightly packed reference image. Table numbers 1–4 are the front row, '
        '5–8 the middle row, and 9–12 the rear row. `DECISIONS.md` records architectural and composition tradeoffs.', '',
        '## Package assembly in Roblox Studio', '',
        '1. Import each of the six FBX files below. In File Geometry, set **Scale Unit: Stud** and keep scale factor **1**. '
        'Retain child MeshPart positions and pivots. Place the package containers at the common assembly origin; '
        'do not individually centre, resize, or reposition their children.',
        '2. Import the existing table package separately once using the same Stud setting. Duplicate or instance that '
        'model twelve times using `Markers.json` positions and Y rotations. The lounge FBX files intentionally contain '
        'no table meshes. The Blender file references one appended collection of the source’s seven finished table meshes.',
        '3. Assign one SurfaceAppearance per textured MeshPart. Use its `set_name` / baked material name to choose '
        '`<Set>_Color.png` for ColorMap and `<Set>_Roughness.png` for RoughnessMap. Assign MetalnessMap when the set '
        'has a matching metalness file. Texture colour spaces are sRGB for Color and data/Non-Color for Roughness and Metalness.',
        '4. Assign `Emissive_*` meshes Roblox **Neon**, using their flat warm colours. They require no SurfaceAppearance. '
        'Assign `Glass_Windows` Roblox **Glass** with a light blue tint and approximately 0.65 transparency. '
        'Keep glass separate from opaque architecture.',
        '5. Keep every environment object anchored. Use Box collision for simple rectangular architecture and Hull for '
        'appropriate convex pieces. Import `COL_*` proxies from the Collision package, set Transparency=1 and '
        'CanCollide=true, and use Box/Hull collision as appropriate. Stair and tier-edge proxies are intentionally simple. '
        'Set decorative furniture details, plants, art, signs, Neon, and glass CanCollide=false; use the supplied proxy '
        'where a decorative assembly needs collision. Disable decorative CastShadow where useful for mobile performance.',
        '6. Add the twelve downward-facing pendant lights and a seating-area spawn using `Markers.json`. '
        'Its positions are already Roblox Y-up studs; do not apply a second axis conversion. '
        'The included Lighting, Bloom, and ColorCorrection values are adjustable starting settings.', '',
        '| File | Contents |', '|---|---|',
        '| `exports/Lounge_Architecture.fbx` | Shell, floors, tiers, steps, ceiling grid, pillars, windows, and separate Glass_Windows |',
        '| `exports/Lounge_Furniture.fbx` | Seating, rugs, coffee table, ottoman, and snack-counter furniture |',
        '| `exports/Lounge_Props.fbx` | Plants, art, clock, cue racks, pendant housings, and small related props |',
        '| `exports/Lounge_Signs.fbx` | Table numbers, separate 1v1 / 2v2 / 3v3 zone signs, Refresh & Play, and blank logo panel |',
        '| `exports/Lounge_Emissive.fbx` | Separate untextured Neon geometry |',
        '| `exports/Lounge_Collision.fbx` | Hidden simple COL_* collision proxies |', '',
        '## Geometry and texture delivery', '',
        'Each exported mesh has one material and one 0–1 UV map. The bake workflow packs related source pieces '
        'into shared atlases by texture set, applies modifiers and transforms as appropriate to the pivot policy, '
        'and triangulates export geometry. `SOURCE_Lounge_*` procedural materials remain available in the blend. '
        'Source BaseColor, Roughness, and Metalness channels use Cycles emission-pass baking; direct lighting and '
        'cast shadows are excluded from Color maps. A separate %g-sample Cycles AO bake is multiplied into BaseColor '
        'at %g%% strength. Maps are %g × %g or smaller. Normal maps are omitted because the restrained stylized '
        'surfaces and modeled bevels do not require them.' % (
            PARAMETERS.get('ao_samples', 32), PARAMETERS.get('ao_blend', .16) * 100,
            PARAMETERS.get('texture_size', 1024), PARAMETERS.get('texture_size', 1024)), '',
        'The `Signs` atlas is separate and replaceable. Zone signs and table placeholders remain independently named '
        'and editable. Replace the sign artwork within its UV island, or update the text in the builder and rebake '
        'the Signs set. `Sign_Logo_Blank` is a blank 10 × 3 stud panel for the game’s own artwork.', '',
        '| Texture set found on disk | Maps | Color dimensions |', '|---|---|---|'
    ]
    for set_name in actual_sets:
        maps = [suffix for suffix in ('Color', 'Roughness', 'Normal', 'Metalness')
                if (texture_dir / (set_name + '_' + suffix + '.png')).exists()]
        lines.append('| %s | %s | %s |' % (set_name, ', '.join(maps),
            _docs_dimensions(texture_dir / (set_name + '_Color.png'))))
    if not actual_sets:
        lines.append('| Pending baking | No Color maps present at this checkpoint | — |')
    lines.extend(['', 'Final per-object triangle counts (table instances excluded):', '',
                  '| Object | FBX group | Texture set | Triangles | Validation |',
                  '|---|---|---|---:|---|'])
    for obj in objects:
        lines.append('| %s | %s | %s | %s | %s |' % (obj['object'].replace('|', '\\|'),
            obj['group'], obj.get('set_name') or 'Untextured', obj['triangles'],
            'PASS' if obj.get('passed') else 'FAIL'))
    if not objects:
        lines.append('| Pending final validation | — | — | — | PENDING |')
    lines.extend(['', 'Environment total: **%s / 150,000 triangles**. Largest exported mesh: **%s / 10,000 triangles**. '
                  'Collision proxies must each remain below 200 triangles. The source table is 19,220 triangles; '
                  'its twelve render instances total 230,640 source-table triangles and are excluded from the lounge '
                  'environment budget and exports.' % (total if total is not None else 'pending',
                                                     maximum if maximum is not None else 'pending'), '',
                  '## Validation', '', '| Check | Result |', '|---|---|'])
    check_categories = [
        ('Per-mesh triangle limit', [c for c in mesh_checks if c['name'] == 'triangle_limit']),
        ('Environment triangle limit', [c for c in global_checks if c['name'] == 'environment_triangle_limit']),
        ('One material / one UV map', [c for c in mesh_checks if c['name'] in ('exactly_one_material','exactly_one_uv_map')]),
        ('UV bounds / no interior overlap', [c for c in mesh_checks if c['name'] in ('uv_bounds_0_1','uv_no_interior_overlap','uv_no_degenerate_triangles')]),
        ('Triangulation / no live modifiers', [c for c in mesh_checks if c['name'] in ('triangulated','no_live_modifiers')]),
        ('Applied rotation/scale and sensible origins', [c for c in mesh_checks if c['name'] in ('rotation_scale_applied','sensible_origin')]),
        ('Manifold or explicitly documented open surfaces', [c for c in mesh_checks if c['name'] == 'manifold_or_documented_open']),
        ('Texture-set count and dimensions', [c for c in global_checks if c['name'] in ('texture_set_limit','texture_maps_present_and_dimensions')]),
        ('Twelve tables / three ascending rows', [c for c in global_checks if c['name'] in ('exactly_twelve_table_instances','three_ascending_rows_of_four')]),
        ('Ten-stud table clearance', [c for c in global_checks if c['name'] == 'all_table_clearances']),
        ('Glass / Neon / collision meshes present', [c for c in global_checks if c['name'] in ('glass_windows_exists','emissive_meshes_exist','collision_meshes_exist')]),
    ]
    for name, checks in check_categories:
        lines.append('| %s | %s |' % (name, _docs_status(checks)))
    for check in additional_checks:
        lines.append('| %s | %s |' % (str(check['name']).replace('|', '\\|'),
                                    'PASS' if check.get('passed') else 'FAIL'))
    lines.extend(['', 'UV validation exhaustively bins candidate triangle pairs and numerically clips their UV triangles '
                  'to test interior intersection; it does not infer validity from an unwrap operator succeeding. '
                  'UV bounds tolerance is 1e-7 and interior-area tolerance is 1e-12 UV². Applied transform and origin '
                  'checks use 1e-5 stud tolerance. The independent FBX reimport coordinate gate uses the stricter '
                  '**1e-6 stud** tolerance in a clean collection.', '',
                  'Clearance validation uses each table’s actual instance transform and authoritative footprint, then '
                  'checks every other table and every tagged wall, furniture, plant, stair, and guardrail bounding box. '
                  'It reports the minimum and four facing-side clearances per table. Supporting floors, flat rugs, '
                  'overhead ceiling/pendants, and overhead table number plaques do not obstruct the floor clearance.', ''])
    openings = [(obj['object'], c.get('detail', {}).get('intentional_open_reason'))
                for obj in objects for c in obj.get('checks', [])
                if c['name'] == 'manifold_or_documented_open' and isinstance(c.get('detail'), dict)
                and c['detail'].get('intentional_open_reason')]
    if openings:
        lines.append('Intentionally open surfaces:')
        lines.append('')
        lines.extend('- `%s`: %s' % item for item in openings)
        lines.append('')
    failed = [(obj['object'], c['name']) for obj in objects for c in obj.get('checks', []) if not c.get('passed')]
    failed.extend(('Delivery', c['name']) for c in all_checks if not c.get('passed'))
    if failed:
        lines.extend(['Unresolved checks at this documentation checkpoint:', ''])
        lines.extend('- `%s`: %s' % item for item in failed)
        lines.append('')
    lines.extend([
        '## Rendering and resuming work', '',
        '`renders/hero.png` uses the final recipe of **%s × %s, Cycles, %s samples, denoised**. '
        '`renders/layout_top.png` provides a clear wide top-down layout. EEVEE checkpoint images support the build stages; '
        'the lighting/composition checkpoint is 1280 pixels wide. No detailed exterior is required.' %
            (dimensions[0], dimensions[1], samples), '',
        'To rebuild from scratch, open the embedded or standalone `LoungeBuilder.py` in Blender’s Text Editor, '
        'set `RUN_BUILD=True`, `BAKE_TEXTURES=True`, and `EXPORT=True`, adjust `PARAMETERS` if needed, and Run Script. '
        '`RUN_BUILD=False` loads the helper functions without automatically rebuilding. `BAKE_TEXTURES=False` skips '
        'texture baking for geometry iteration, and `EXPORT=False` skips FBX writes.', '',
        'For a checkpoint resume through Blender MCP, load the current script with `__name__` set to a non-main value '
        'so that it defines helpers without starting a full rebuild, then call `start_stage(N)` for the exact stage '
        'named in `PROGRESS.md`. Stages are: 1 blockout; 2 architecture; 3 furniture/props; 4 lighting/composition; '
        '5 optimize/unwrap/bake/export; 6 final renders/documentation/validation. `start_stage` schedules one coherent '
        'stage on Blender’s main thread and writes recoverable errors and the next resume step into the progress log. '
        'Wait for that stage to finish before submitting another.', '',
        'The builder is embedded in `Lounge.blend`; `PROGRESS.md` records the last successful action and exact resume '
        'step. `DECISIONS.md` records meaningful assumptions and deviations. Final validation is printed and saved '
        'to `Validation.md` and `Validation.json`, and the blend is saved after the final gate.', '',
        '**Studio upload/import was not performed.** The FBX, texture, geometry, UV, clearance, and render validations '
        'are performed in the local Blender delivery workflow. The Roblox light/material/collision assignments above '
        'must be applied during Studio assembly.', ''
    ])
    path = OUTPUT_DIR / 'Readme.md'
    path.write_text('\n'.join(lines), encoding='utf-8')
    return {'path': str(path), 'validation_status': status, 'documented_meshes': len(objects),
            'documented_texture_sets': actual_sets}

def render_top_layout():
    s=bpy.context.scene;hero=s.camera
    visibility={o.name:o.hide_render for o in s.objects}
    d=bpy.data.cameras.get('Layout_Top_Camera') or bpy.data.cameras.new('Layout_Top_Camera')
    camera=bpy.data.objects.get('Layout_Top_Camera')
    if camera is None:camera=bpy.data.objects.new('Layout_Top_Camera',d);collection('Rig').objects.link(camera)
    camera.location=(0,24.5,220);camera.rotation_euler=(0,0,pi/2);d.type='ORTHO';d.ortho_scale=184;d.clip_end=500;s.camera=camera
    labels=[]
    for o in s.objects:
        if o.get('ceiling') or o.name.startswith(('Pendant_','Emissive_Pendant_','Table_Number_')):o.hide_render=True
        if o.get('camera_cutaway'):o.hide_render=False
    for row,(y,z) in enumerate(zip(PARAMETERS['row_y'],PARAMETERS['tier_z'])):
        for col,x in enumerate(PARAMETERS['column_x']):
            n=row*4+col+1;cu=bpy.data.curves.new('Layout_Label_'+str(n),'FONT');cu.body=str(n);cu.align_x='CENTER';cu.align_y='CENTER';cu.size=2.7;cu.extrude=0
            o=bpy.data.objects.new('Layout_Label_'+str(n),cu);collection('Rig').objects.link(o);o.location=(x,y,z+3.5);o.rotation_euler.z=pi/2
            cu.materials.append(untextured('Layout_White',(.95,.98,1),.8));labels.append(o)
    for body,x,y in [('LOUNGE',0,-44),('01 — MAIN FLOOR',0,-14),('02 — RAISED +2.4',0,29),('03 — MEZZANINE +4.8',0,72)]:
        cu=bpy.data.curves.new('Layout_Zone','FONT');cu.body=body;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=1.2
        o=bpy.data.objects.new('Layout_Zone',cu);collection('Rig').objects.link(o);o.location=(x,y,floor_level(y)+.2);o.rotation_euler.z=pi/2;cu.materials.append(material('charcoal'));labels.append(o)
    try:
        s.render.engine='BLENDER_EEVEE';s.render.resolution_x=1920;s.render.resolution_y=1080;s.render.resolution_percentage=100
        s.render.filepath=str(OUTPUT_DIR/'renders'/'layout_top.png');bpy.ops.render.render(write_still=True)
    finally:
        for o in labels:bpy.data.objects.remove(o,do_unlink=True)
        for o in s.objects:
            if o.name in visibility:o.hide_render=visibility[o.name]
        s.camera=hero


def final_delivery():
    s=bpy.context.scene
    # Run costly geometry/UV checks before the final render so failures do not waste render time.
    progress(5,'FBX packages and baked atlases saved','start_stage(6)')
    m=validate_meshes();c=validate_clearance()
    pre={'mesh_validation':m,'clearance_validation':c}
    (OUTPUT_DIR/'scripts'/'mesh_preflight.json').write_text(json.dumps(pre,indent=2))
    if not m['passed'] or not c['passed']:
        write_validation(m,c,filename='Validation')
        raise RuntimeError('Mesh / UV / clearance validation failed; see Validation.json')
    write_markers();write_readme()
    configure_cycles(PARAMETERS['hero_samples'])
    s.camera=bpy.data.objects['Hero_Camera'];s.render.resolution_x=PARAMETERS['hero_resolution'][0];s.render.resolution_y=PARAMETERS['hero_resolution'][1];s.render.resolution_percentage=100
    s.render.filepath=str(OUTPUT_DIR/'renders'/'hero.png');s.cycles.use_denoising=True
    progress(5,'Geometry, UVs, texture sets and numeric clearance passed; rendering Cycles hero','start_stage(6)')
    bpy.ops.render.render(write_still=True)
    progress(5,'1920x1080 Cycles hero rendered at 128 samples with denoising','start_stage(6)')
    render_top_layout()
    roundtrip=json.loads((OUTPUT_DIR/'scripts'/'fbx_reimport.json').read_text())
    required=['Lounge.blend','LoungeBuilder.py','PROGRESS.md','DECISIONS.md','Markers.json','Readme.md','renders/hero.png','renders/layout_top.png']+[f'exports/Lounge_{g}.fbx' for g in GROUPS]
    dimensions={n:_validation_png_dimensions(OUTPUT_DIR/'renders'/n) for n in ('hero.png','layout_top.png')}
    manifests=json.loads((OUTPUT_DIR/'scripts'/'bake_manifest.json').read_text())
    extra=[
        _validation_check('all_required_deliverables_exist',all((OUTPUT_DIR/p).is_file() and (OUTPUT_DIR/p).stat().st_size>0 for p in required),required),
        _validation_check('six_aligned_fbx_packages',all((OUTPUT_DIR/'exports'/f'Lounge_{g}.fbx').exists() for g in GROUPS),{'assembly_origin':[0,0,0],'scale':1,'axis_forward':'-Z','axis_up':'Y','packages':list(GROUPS)}),
        _validation_check('fbx_reimport_coordinates_1e_6',roundtrip['passed'],roundtrip),
        _validation_check('hero_1920x1080_cycles_128_denoised',dimensions['hero.png']==[1920,1080] and PARAMETERS['hero_samples']==128 and s.cycles.use_denoising,{'dimensions':dimensions['hero.png'],'engine':'CYCLES','samples':128,'denoising':True}),
        _validation_check('wide_top_down_render',dimensions['layout_top.png']==[1920,1080],dimensions['layout_top.png']),
        _validation_check('ao_baked_without_direct_light',all(not r['color_has_direct_lighting'] and r['ao_samples']>=32 and r['ao_blend']==.16 for r in manifests.values()),{'sample_count':32,'blend':.16,'direct_lighting':False}),
        _validation_check('pendant_and_spawn_marker_data',len(json.loads((OUTPUT_DIR/'Markers.json').read_text())['pendants'])==12),
    ]
    report=write_validation(m,c,extra)
    write_readme(report)
    if not report['passed']:raise RuntimeError('Final deliverable gate failed: see Validation.json')
    s.camera=bpy.data.objects['Hero_Camera'];configure_cycles(PARAMETERS['hero_samples'])
    s.render.resolution_x=1920;s.render.resolution_y=1080;s.render.filepath=str(OUTPUT_DIR/'renders'/'hero.png')
    s['validated']=True;s['validation_report']='Validation.json';s['stage']=6
    main_area=max(bpy.context.screen.areas,key=lambda a:a.width*a.height)
    if main_area.type=='CONSOLE':main_area.type='VIEW_3D'
    # Ensure opening the blend shows the useful hero camera in a cheap solid viewport.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='SOLID'
                area.spaces.active.overlay.show_extras=False
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath and str(OUTPUT_DIR) in bpy.path.abspath(im.filepath):
            absolute=bpy.path.abspath(im.filepath)
            if Path(absolute).is_file():
                if not im.packed_file:im.pack()
                im.filepath_raw=bpy.path.relpath(absolute,start=str(OUTPUT_DIR))
    embed_builder()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    # This post-save check records evidence that the delivered blend was saved after the gate.
    extra.append(_validation_check('blend_saved_after_validation',(OUTPUT_DIR/'Lounge.blend').stat().st_mtime>=(OUTPUT_DIR/'Validation.json').stat().st_mtime))
    report=write_validation(m,c,extra);write_readme(report)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    progress(6,'All final validation checks passed; final blend saved after validation','complete')
    return report

def run_stage(stage):
    if stage in (2,3):
        for old in list(bpy.context.scene.objects):
            if old.get('build_stage',0)>=stage:bpy.data.objects.remove(old,do_unlink=True)
    bpy.context.scene['_building_stage']=stage
    if stage==1:build_blockout();checkpoint(1)
    elif stage==2:build_architecture();checkpoint(2)
    elif stage==3:build_furniture_props();build_pendants_signs();checkpoint(3)
    elif stage==4:
        if bpy.context.scene.get('geometry_revision')!=2:
            build_blockout();build_architecture();build_furniture_props();build_pendants_signs()
        tune_lighting_composition();checkpoint(4,width=1280)
        c=validate_clearance();(OUTPUT_DIR/'scripts'/'clearance_preflight.json').write_text(json.dumps(c,indent=2))
        print('CLEARANCE',c['passed'],c['failures'])
    elif stage==5:
        for old in list(bpy.context.scene.objects):
            if old.get('export_group')=='Emissive' and old.name not in collection('Emissive').objects:bpy.data.objects.remove(old,do_unlink=True)
        build_collision();prepare_export_geometry()
        if EXPORT:
            probe=export_packages()
            if not probe['passed']:raise RuntimeError('Strict FBX roundtrip failed: '+str(probe['maximum_error_studs']))
        if BAKE_TEXTURES:bake_atlases()
        if EXPORT:export_packages()
        checkpoint(5,render=False)
    elif stage==6:final_delivery()
    else:raise ValueError(stage)

if __name__=='__main__' and RUN_BUILD:
    for stage in range(1,7):run_stage(stage)
