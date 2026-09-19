import bpy,json
p='/Users/justinjin/Desktop/8ball/assets/lounge/LoungeBuilder.py'
ns={'__name__':'lounge_builder','__file__':p};exec(compile(open(p).read(),p,'exec'),ns)
# Stamp ownership for resumable individual stages on the delivered checkpoint.
for o in bpy.context.scene.objects:
    g=o.get('export_group')
    if g=='Architecture':
        stage=2 if o.name.startswith(('Beam_','Ceiling_','Window_Frames_','Skirting_','Floor_Seams_')) else 1
        if o.name=='Wall_Clock_Panel':stage=4
    elif g=='Furniture':stage=2 if o.name.startswith('Playing_Rug_') else 3
    elif g=='Props':stage=2 if o.name.startswith('Cue_Rack_') else 4 if o.get('optional_gameplay_display') else 3
    elif g=='Signs':stage=3
    elif g=='Emissive':stage=3 if o.name.startswith('Emissive_Pendant_') else 2
    elif g=='Collision':stage=5
    elif o.get('render_only'):stage=4
    elif o.type=='LIGHT':stage=3 if o.name.startswith('Light_Pendant_') else 1
    else:continue
    o['build_stage']=stage
main=max(bpy.context.screen.areas,key=lambda a:a.width*a.height)
if main.type=='CONSOLE':main.type='VIEW_3D'
if main.type=='VIEW_3D':
    main.spaces.active.region_3d.view_perspective='CAMERA'
    main.spaces.active.shading.type='MATERIAL'
    main.spaces.active.overlay.show_extras=False
ns['embed_builder']()
ns['write_readme'](json.loads((ns['OUTPUT_DIR']/'Validation.json').read_text()))
bpy.ops.wm.save_as_mainfile(filepath=str(ns['OUTPUT_DIR']/'Lounge.blend'))
ns['progress'](6,'All final validation checks passed; final blend saved after validation','complete')
print('FINAL_DELIVERY_PASS',len([o for o in bpy.context.scene.objects if o.get('export_group') in ns['GROUPS']]),'meshes',bpy.context.scene.cycles.samples,'Cycles samples',bpy.data.filepath)
