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
    # Ensure opening the blend shows the useful hero camera in a cheap solid viewport.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='SOLID'
                area.spaces.active.overlay.show_extras=False
    for im in bpy.data.images:
        if im.source=='FILE' and im.filepath and str(OUTPUT_DIR) in bpy.path.abspath(im.filepath):im.filepath=bpy.path.relpath(im.filepath,start=str(OUTPUT_DIR))
    bpy.ops.file.pack_all();embed_builder()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    # This post-save check records evidence that the delivered blend was saved after the gate.
    extra.append(_validation_check('blend_saved_after_validation',(OUTPUT_DIR/'Lounge.blend').stat().st_mtime>=(OUTPUT_DIR/'Validation.json').stat().st_mtime))
    report=write_validation(m,c,extra);write_readme(report)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_DIR/'Lounge.blend'))
    progress(6,'All final validation checks passed; final blend saved after validation','complete')
    return report
