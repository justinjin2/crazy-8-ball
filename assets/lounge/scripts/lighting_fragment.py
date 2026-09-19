def add_table_display_props():
    # These removable display balls/cues are lounge props, never replacements for the source table.
    for row,(y,z) in enumerate(zip(PARAMETERS['row_y'],PARAMETERS['tier_z'])):
        for col,x in enumerate(PARAMETERS['column_x']):
            n=row*4+col+1;parts=[];colors=['butter','blue','coral','white','teal','coral','butter','charcoal','blue','white','coral','teal','butter','white','blue']
            for k in range(5):
                for j in range(k+1):
                    cx=x+(j-k/2)*.431;cy=y+3-k*.375;cz=z+3.108
                    bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=2,radius=.208,matrix=Matrix.Translation((cx,cy,cz)))
                    bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
                    vs=[tuple(v.co) for v in bm.verts];fs=[tuple(v.index for v in f.verts) for f in bm.faces];bm.free()
                    parts.append(mesh('Display_Ball',vs,fs,colors[len(parts)],'GameProps_A','Props',0,False))
            bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=2,radius=.208,matrix=Matrix.Translation((x-1,y-3,z+3.108)))
            bm.verts.ensure_lookup_table();parts.append(mesh('Cue_Ball',[tuple(v.co) for v in bm.verts],[tuple(v.index for v in f.verts) for f in bm.faces],'white','GameProps_A','Props',0,False));bm.free()
            a=Vector((x+2.2,y-5,z+2.97));b=Vector((x+2.9,y+4.2736,z+2.97));axis=(b-a).normalized();side=axis.cross(Vector((0,0,1))).normalized();up=axis.cross(side)
            verts=[tuple(p+(.045 if e==0 else .026)*(cos(t*2*pi/10)*side+sin(t*2*pi/10)*up)) for e,p in enumerate((a,b)) for t in range(10)]
            faces=[tuple(range(9,-1,-1)),tuple(range(10,20))]+[(i,(i+1)%10,(i+1)%10+10,i+10) for i in range(10)]
            parts.append(mesh('Display_Cue',verts,faces,'oak','GameProps_A','Props',0,False))
            o=combine(f'Table_DisplayProps_{n:02d}',parts,(x,y,z+2.9));o['clearance_obstacle']=False;o['optional_gameplay_display']=True


def tune_lighting_composition():
    s=bpy.context.scene;camera=bpy.data.objects['Hero_Camera'];camera.location=PARAMETERS['hero_camera'];aim(camera,PARAMETERS['hero_target']);camera.data.lens=PARAMETERS['hero_lens']
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
    # Gentle warm top light, with neutral broad fill so blue felt remains blue.
    for o in collection('Rig').objects:
        if o.type=='LIGHT' and o.name.startswith('Ceiling_Fill'):o.data.energy=6900
        if o.type=='LIGHT' and o.name.startswith('Window_Soft'):o.data.energy=10000
        if o.type=='LIGHT' and o.name=='Fill_Foreground':o.data.energy=6200
    s.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=.8
    add_table_display_props()
    s['stage']=4
