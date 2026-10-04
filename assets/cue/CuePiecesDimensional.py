"""Dimensional cue VFX: closed deforming solar flames.
No complete aura is put on a card. All coordinates are in the package's Blender cue frame.
"""
import math
import json
from pathlib import Path
import bmesh
import numpy as np
from mathutils import Vector, Matrix


def _volume_material(k, name, violet=False):
    """Opaque painted colour wraps a closed sculpture; alpha never supplies its silhouette."""
    from CuePieces import HERE
    # Continuous round the circumference, with two irregular hot ridges and dark valleys.
    w,h=512,512
    u,v=np.meshgrid((np.arange(w)+.5)/w,(np.arange(h)+.5)/h)
    wave=.055*np.sin(v*12)+.020*np.sin(v*31)
    ridge=np.maximum(0,np.sin((u+wave)*math.tau))**.7
    other=np.maximum(0,-np.sin((u-wave*.7)*math.tau))**.8
    heat=np.maximum(ridge,other*.87)
    heat*=.75+.25*np.sin(v*math.pi)
    shadow=np.array([.14,.025,.09] if not violet else [.12,.035,.29])
    gold=np.array([1,.63,.11] if not violet else [.60,.27,1])
    hot=np.array([1,.94,.65] if not violet else [.90,.66,1])
    base=np.clip(.1+heat*1.8,0,1)[...,None]
    col=shadow+(gold-shadow)*base
    core=np.clip((heat-.58)/.32,0,1)[...,None]
    col=col+(hot-col)*core
    brush=.94+.06*np.sin(v*95+u*21)*np.sin(u*65-v*6)
    col*=brush[...,None]
    emissive=.38+.60*heat**1.3
    for suffix,arr in [('colour',col),('emissive',np.repeat(emissive[...,None],3,axis=2))]:
        rgba=np.concatenate([arr,np.ones((h,w,1))],axis=2).astype(np.float32)
        img=k.bpy.data.images.new(name+suffix,w,h,alpha=True)
        img.pixels.foreach_set(rgba.ravel())
        img.filepath_raw=str(Path(HERE)/'vfx/v3/eclipse'/f'{name}_{suffix}.png')
        img.file_format='PNG';img.save();k.bpy.data.images.remove(img)
    k.material(name,'SmoothPlastic','#FFFFFF',SurfaceAppearance={
        'ColorMap':f'vfx/v3/eclipse/{name}_colour.png',
        'EmissiveMask':f'vfx/v3/eclipse/{name}_emissive.png',
        'EmissiveTint':'#FFFFFF','EmissiveStrength':1.4,'AlphaMode':'Overlay'})


def _closed_flame(bm,uv,point,width,depth,tag,segments=28,sides=12,normal=None):
    """Closed tapered cross sections, transported along a curling centreline. No flat cards."""
    rings=[]
    for j in range(segments+1):
        t=j/segments;p=point(t)
        tangent=(point(min(1,t+.001))-point(max(0,t-.001))).normalized()
        # Consistent cross-section basis; all paths travel primarily around the corona.
        a=tangent.cross(normal if normal is not None else Vector((.317,.521,.793))).normalized()
        if a.length<.1:a=tangent.orthogonal().normalized()
        b=tangent.cross(a).normalized()
        twist=.34*math.sin(t*5)
        a,b=a*math.cos(twist)+b*math.sin(twist),-a*math.sin(twist)+b*math.cos(twist)
        row=[]
        for h in range(sides):
            phi=h*math.tau/sides
            # Sculpt a slightly pinched, four-ridged flame, substantial from every angle.
            ridges=1+.13*math.cos(phi*3+t*5)
            pos=p+a*(math.cos(phi)*width(t)*ridges)+b*(math.sin(phi)*depth(t)*ridges)
            row.append(bm.verts.new(pos));tag(pos,t)
        rings.append(row)
    for j in range(segments):
        for h in range(sides):
            q=(h+1)%sides
            face=bm.faces.new((rings[j][h],rings[j][q],rings[j+1][q],rings[j+1][h]))
            for lp,coord in zip(face.loops,[(h/sides,j/segments),((h+1)/sides,j/segments),((h+1)/sides,(j+1)/segments),(h/sides,(j+1)/segments)]):lp[uv].uv=coord
    for j,reverse in [(0,True),(segments,False)]:
        t=j/segments;pos=point(t);cap=bm.verts.new(pos);tag(pos,t)
        for h in range(sides):
            vs=(cap,rings[j][h],rings[j][(h+1)%sides])
            face=bm.faces.new(vs[::-1] if reverse else vs)
            for lp in face.loops:lp[uv].uv=(h/sides,t)



def celestial_streams(k):
    """Two tapered, closed violet currents occupy different depths along the cue."""
    C=Vector((0,-4.8,0));root='CelestialStreams'
    k.joint(root,pivot=tuple(C),aura=True,layer='Essential')
    _volume_material(k,'VioletVolume',violet=True)
    bm=bmesh.new();uv=bm.loops.layers.uv.new('UVMap');tags={};bones={}
    def key(p):return tuple(round(float(v),4) for v in p)
    for n in range(2):
        def pt(t):
            angle=n*math.pi+math.tau*.73*t
            r=.40+.24*math.sin(math.pi*t)
            return Vector((r*math.cos(angle),-(2.3+n*.3+4.2*t),r*math.sin(angle)))
        parent=root
        for j in range(5):
            name='Filament%d_%d'%(n,j);pivot=pt(j/5)
            k.joint(name,pivot=tuple(pivot),parent=parent,motion=[
                {'Kind':'Hinge','Axis':(0,1,0),'Amp':8 if j else 5,'Period':3.8+n*.6,'Phase':n*110-j*50},
                {'Kind':'Bob','Dir':(0,0,1),'Amp':.035,'Period':3.1+n*.3,'Phase':n*110-j*55}])
            if j==0:bones[name]=lambda coords,n=n:np.array([float(tags.get(key(p),(-1,0))[0]==n) for p in coords])
            else:bones[name]=lambda coords,j=j:np.array([np.clip((tags.get(key(p),(-1,0))[1]-(j-.7)/5)/.20,0,1) for p in coords])
            parent=name
        def tag(p,t,n=n):tags[key(p)]=(n,t)
        _closed_flame(bm,uv,pt,lambda t:.009+.085*math.sin(math.pi*t)**.8,
                      lambda t:.008+.052*math.sin(math.pi*t)**.8,tag,segments=40,sides=10)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges),'Celestial currents must be closed volumes'
    ob=k.add(root,k.mesh_object('CelestialCurrents',bm,['VioletVolume']))
    k.skins['CelestialCurrentsRig']={'root':root,'bones':bones,'meshes':[ob]}
