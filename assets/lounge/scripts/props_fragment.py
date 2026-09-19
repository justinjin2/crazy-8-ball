def build_furniture_props():
    """Create the lounge's finished movable furniture and restrained wall props.

    Primitives are closed; joined multicolour source meshes are atlased later.
    The foreground's northernmost furniture bound remains below Y=-19.25.
    """
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
