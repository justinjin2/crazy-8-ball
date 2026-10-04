"""Limited cue art: precisely drafted geometry, authored independently of sale rules."""
import math
import bmesh
from mathutils import Vector, Matrix
from CuePieces import piece, sweep


def stroke(bm, points, radius=0.007):
    sweep(bm, [Vector(p) for p in points], [radius]*len(points), segs=4, cap=True)


def arc(bm, centre, r, start=0, end=360, normal=(1, 0, 0), radius=0.008, steps=None):
    c = Vector(centre)
    n = Vector(normal).normalized()
    a = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((0, 0, 1))).normalized()
    b = n.cross(a)
    steps = steps or max(5, int(abs(end-start)/6))
    stroke(bm, [c+r*(math.cos(math.radians(start+(end-start)*i/steps))*a+
                       math.sin(math.radians(start+(end-start)*i/steps))*b) for i in range(steps+1)], radius)


def materials(k):
    k.material('Blue', 'SmoothPlastic', '#115AD0')
    k.material('Ice', 'Neon', '#6ECFFF')
    k.material('Magenta', 'Neon', '#E52BCD')


def add(k, joint, bm, mat):
    k.add(joint, k.mesh_object(joint+'_'+mat, bm, [mat]))


def drafted_panel(k, name, centre, size, variant, phase):
    """No filled rectangle: open corner frame, cue elevation, section and dimension strokes."""
    x, y, z = centre
    w, h = size
    k.joint(name, pivot=centre, aura=True, layer='Structure', motion=[
        {'Kind':'Bob','Dir':(0,0,1),'Amp':0.10,'Period':4.5,'Phase':phase},
        {'Kind':'Hinge','Axis':(0,1,0),'Amp':8,'Period':6,'Phase':phase}])
    bm, hot = bmesh.new(), bmesh.new()
    def p(u,v): return (x, y+u*w/2, z+v*h/2)
    def line(coords, radius=0.007, mesh=bm): stroke(mesh,[p(a,b) for a,b in coords],radius)
    # Deliberately interrupted corners and crosshair registration marks.
    for a in (-1,1):
        for b in (-1,1):
            line([(a*.58,b),(a,b),(a,b*.58)],.011)
    line([(-.85,-.84),(.45,-.84)],.005)
    for i in range(8):
        u=-.8+i*.15
        line([(u,-.78),(u,-.7 if i%2 else -.65)],.005)
    if variant == 0:
        # A side elevation of the cue, with successive diameter stations.
        line([(-.82,-.06),(.72,-.22),(.78,-.20),(.78,.20),(.72,.22),(-.82,.06),(-.82,-.06)],.01)
        line([(-.88,0),(.9,0)],.005)
        for u in (-.48,-.1,.35,.61): line([(u,-.29),(u,.29)],.006)
        line([(-.72,.58),(.68,.58)],.007)
        for u in (-.72,.68): line([(u-.06,.5),(u,.58),(u-.06,.66)],.007)
    elif variant == 1:
        # Orthographic section with construction ellipse and bolt-free axes.
        for r in (.28,.43):
            arc(bm,(x,y,z),r,normal=(1,0,0),radius=.008,steps=40)
        line([(-.85,0),(.85,0)],.005)
        line([(0,-.75),(0,.75)],.005)
        for u in (-.67,.67): line([(u,-.32),(u,.32)],.006)
        line([(-.5,.65),(.5,.65)],.006)
    else:
        # Exploded sleeve detail with alternating registration bars.
        for u in (-.58,-.23,.12,.47):
            line([(u,-.44),(u+.17,-.34),(u+.17,.34),(u,.44),(u,-.44)],.009)
        line([(-.8,0),(.84,0)],.005)
        for u in (-.6,-.1,.4): line([(u,.61),(u+.3,.61)],.005)
    line([(.6,-.84),(.84,-.84)],.009,hot)
    line([(-.85,.83),(-.49,.83)],.009,hot)
    add(k,name,bm,'Blue'); add(k,name,hot,'Magenta')


@piece
def beta(k):
    import cue_common as cc
    materials(k)
    shape,_=cc.load_shape()
    # Use the final shared profile for every contour; no independently guessed shaft taper.
    profile=cc.read_parameters()['profile']
    def radius(d):
        for a,b in zip(profile,profile[1:]):
            if a['d'] <= d <= b['d']:
                f=(d-a['d'])/max(b['d']-a['d'],1e-9)
                return a['r']*(1-f)+b['r']*f
        return profile[-1]['r']
    k.joint('Contour')
    bm=bmesh.new()
    stations=sorted(set([.25,6.96]+[q['d'] for q in profile if .25<q['d']<6.96]))
    for a in range(4):
        th=math.tau*a/4
        stroke(bm,[(math.cos(th)*(radius(d)+.007),-d,math.sin(th)*(radius(d)+.007)) for d in stations],.006)
    for d in (.25,1.1,2.5,3.38,3.78,4.45,5.05,5.43,6.3,6.62,6.94):
        arc(bm,(0,-d,0),radius(d)+.007,normal=(0,1,0),radius=.006,steps=40)
    add(k,'Contour',bm,'Ice')
    k.joint('Collars')
    bm=bmesh.new()
    for d in (3.63,3.73,5.34,5.4,6.88):
        arc(bm,(0,-d,0),radius(d)+.011,normal=(0,1,0),radius=.012,steps=48)
    add(k,'Collars',bm,'Magenta')
    # Schematic rotary assembly, deliberately cut into arcs with clear empty gaps.
    centre=(0,-4.7,0)
    k.joint('Schematic',pivot=centre,aura=True,layer='Essential',motion=[{'Kind':'Spin','Axis':(1,0,0),'Rate':11}])
    bm,hot=bmesh.new(),bmesh.new()
    for j in range(3):
        arc(bm,centre,1.23,start=j*120+8,end=j*120+108,radius=.017)
        arc(bm,centre,1.08,start=j*120+23,end=j*120+87,radius=.007)
    for j in range(24):
        th=math.tau*j/24
        r0,r1=1.24,1.35 if j%3==0 else 1.29
        stroke(bm,[(0,centre[1]+math.cos(th)*r,math.sin(th)*r) for r in (r0,r1)],.009)
    for j in range(3):
        th=math.tau*j/3
        arc(hot,centre,1.23,start=math.degrees(th)-3,end=math.degrees(th)+3,radius=.025,steps=4)
    add(k,'Schematic',bm,'Blue');add(k,'Schematic',hot,'Magenta')
    k.joint('SectionRing',pivot=(0,-5.95,0),aura=True,layer='Essential',motion=[{'Kind':'Spin','Axis':(0,1,0),'Rate':-18}])
    bm=bmesh.new()
    arc(bm,(0,-5.95,0),.72,normal=(0,1,0),start=12,end=168,radius=.012)
    arc(bm,(0,-5.95,0),.72,normal=(0,1,0),start=192,end=348,radius=.012)
    for a in range(4):
        th=math.tau*a/4
        stroke(bm,[(math.cos(th)*r,-5.95,math.sin(th)*r) for r in (.5,.82)],.009)
    add(k,'SectionRing',bm,'Ice')
    drafted_panel(k,'Elevation',(.25,-3.0,1.05),(1.9,.9),0,0)
    drafted_panel(k,'Section',(-.15,-5.0,-1.18),(1.2,1.0),1,120)
    drafted_panel(k,'Sleeve',(.32,-6.6,.9),(1.3,.9),2,240)
    # The back's roll differs from the held cue. A 55-degree dihedral makes diagrams
    # readable in both views instead of disappearing edge-on on a walking player's back.
    R = Matrix.Rotation(math.radians(55), 4, 'Y')
    for j in k.joints.values():
        if not j['Aura']:
            continue
        j['Pivot'] = tuple(R @ Vector(j['Pivot']))
        for motion in j['Motion']:
            for key in ('Axis', 'Dir'):
                if key in motion:
                    motion[key] = tuple(R.to_3x3() @ Vector(motion[key]))
        for ob in j['objects']:
            ob.data.transform(R)


@piece
def beta_pocket(k):
    k.frame='pocket'
    materials(k)
    k.material('Blue', 'Neon', '#147DDD')
    k.joint('Funnel',layer='Essential',motion=[{'Kind':'Spin','Axis':(0,0,1),'Rate':32}])
    bm=bmesh.new()
    # Exponential horn, open in the middle: the reference's dimensional blueprint funnel.
    def rr(h):return .14+1.04*(h/1.9)**2
    for i in range(14):
        th=math.tau*i/14
        stroke(bm,[(math.cos(th)*rr(h),math.sin(th)*rr(h),h) for h in [j*1.9/28 for j in range(29)]],.015)
    for h in (.12,.45,.82,1.18,1.53,1.9):
        arc(bm,(0,0,h),rr(h),normal=(0,0,1),radius=.015,steps=56)
    add(k,'Funnel',bm,'Blue')
    k.joint('Rim',pivot=(0,0,1.9),layer='Essential',motion=[{'Kind':'Spin','Axis':(0,0,1),'Rate':-55}])
    bm=bmesh.new()
    for j in range(3): arc(bm,(0,0,1.9),1.22,j*120+5,j*120+110,normal=(0,0,1),radius=.022)
    add(k,'Rim',bm,'Magenta')
    for i in range(2):
        j='Scan'+str(i)
        k.joint(j,pivot=(0,0,1),layer='Structure',motion=[{'Kind':'Bob','Dir':(0,0,1),'Amp':.42,'Period':1.4,'Phase':i*180}])
        bm=bmesh.new()
        arc(bm,(0,0,1.05+i*.2),.7+i*.23,normal=(0,0,1),radius=.015)
        add(k,j,bm,'Ice')
    k.joint('DraftBase',layer='Structure',motion=[{'Kind':'Spin','Axis':(0,0,1),'Rate':-15}])
    bm=bmesh.new()
    for j in range(4):
        arc(bm,(0,0,.06),1.48,j*90+5,j*90+78,normal=(0,0,1),radius=.015)
        th=j*math.pi/2
        stroke(bm,[(math.cos(th)*r,math.sin(th)*r,.06) for r in (1.3,1.7)],.01)
    add(k,'DraftBase',bm,'Blue')
    # Keep the complete rim below the close-shot HUD, including the winning scale.
    height = .68
    S = Matrix.Diagonal((1, 1, height, 1))
    for joint in k.joints.values():
        p = joint['Pivot']
        joint['Pivot'] = (p[0], p[1], p[2]*height)
        for motion in joint['Motion']:
            if motion['Kind'] == 'Bob':
                motion['Amp'] *= height
        for ob in joint['objects']:
            ob.data.transform(S)
