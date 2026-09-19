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
    o=cube('COL_SnackCounter',(-46.75,-8,1.6),(3.5,12.15,3.2),mat,'','Collision',0,False);o.hide_render=True;o.display_type='WIRE'


def configure_cycles(samples=32):
    s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.samples=samples;s.cycles.use_denoising=True
    p=bpy.context.preferences.addons['cycles'].preferences
    try:
        p.compute_device_type='METAL';p.get_devices()
        for d in p.devices:d.use=(d.type=='METAL')
        s.cycles.device='GPU'
    except Exception:s.cycles.device='CPU'
    return s


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


def bake_atlases():
    import numpy as np
    s=configure_cycles(8);s.render.bake.use_selected_to_active=False
    all_objects=[o for o in s.objects if o.type=='MESH' and o.get('export_group') in GROUPS]
    sets=sorted({o.get('set_name') for o in all_objects if o.get('set_name')})
    state={o.name:o.hide_render for o in s.objects}
    manifest={}
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
        for o in s.objects:
            if o.name in state:o.hide_render=state[o.name]
    return manifest


def export_packages():
    """Same FBX coordinate/unit options as PoolTable.py; selection excludes table instances."""
    s=bpy.context.scene
    for group in GROUPS:
        bpy.ops.object.select_all(action='DESELECT')
        objects=[o for o in s.objects if o.type=='MESH' and o.get('export_group')==group]
        for o in objects:o.hide_set(False);o.select_set(True)
        bpy.ops.export_scene.fbx(filepath=str(OUTPUT_DIR/'exports'/f'Lounge_{group}.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1.0,apply_unit_scale=False,apply_scale_options='FBX_SCALE_UNITS',use_space_transform=True,bake_space_transform=True,use_mesh_modifiers=True,use_triangles=True,mesh_smooth_type='OFF',add_leaf_bones=False,bake_anim=False,path_mode='RELATIVE',embed_textures=False,use_custom_props=True)
    return reimport_coordinate_test()


def reimport_coordinate_test():
    """Verify the complete emissive package's world vertices after clean FBX reimport."""
    from mathutils.kdtree import KDTree
    original={o.name:[o.matrix_world@v.co for v in o.data.vertices] for o in bpy.context.scene.objects if o.get('export_group')=='Emissive'}
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(OUTPUT_DIR/'exports'/'Lounge_Emissive.fbx'),use_custom_normals=False)
    imported=list(set(bpy.data.objects)-before);c=collection('Reimport_Validation')
    maximum=0.;records=[]
    for o in imported:
        for old in list(o.users_collection):old.objects.unlink(o)
        c.objects.link(o)
        if o.type!='MESH':continue
        name=o.name
        match=next((n for n in original if name==n or name.startswith(n+'.')),None)
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
    result={'passed':maximum<=1e-6 and len(records)==len(original),'tolerance_studs':1e-6,'maximum_error_studs':maximum,'tested_package':'Lounge_Emissive.fbx','objects':records,'method':'Clean collection import; bidirectional nearest world-vertex coordinates for every emissive mesh.'}
    (OUTPUT_DIR/'scripts'/'fbx_reimport.json').write_text(json.dumps(result,indent=2));return result
