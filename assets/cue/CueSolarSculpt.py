"""Eclipse's painted solar sculpture, deformed as ten independent dimensional prominences.
The generated master supplies the forked silhouette and painted ridges. Blender builds the
corona volume, normalizes it for both cue and pocket, and authors all skeleton timing.
"""
import math
import numpy as np
import bmesh
from mathutils import Vector, Matrix
from CuePiecesDimensional import _volume_material, _closed_flame


def corona(k, root, centre, radius, normal):
    C,N=Vector(centre),Vector(normal).normalized()
    U=N.orthogonal().normalized();V=N.cross(U)
    def unit(ob):
        points=np.array([v.co[:] for v in ob.data.vertices]);lo,hi=points.min(0),points.max(0)
        height=hi[2]-lo[2]
        return Matrix.Scale(1/height,4) @ Matrix.Translation((-(lo[0]+hi[0])/2,-(lo[1]+hi[1])/2,-lo[2]))
    ob=k.model(root,root+'SolarSculpt','eclipse_solar_flame',unit,target_tris=1800,
        texture_px=1024,emissive=lambda rgb:.34+.62*np.clip(rgb[...,0]*.34+rgb[...,1]*.55+rgb[...,2]*.11,0,1)**1.25,
        emissive_tint='#FFF1D6',emissive_strength=1.8)
    # Retain actual three-dimensional geometry; every UV island remains on its sculpted face.
    master=ob.data.copy();original=np.array([v.co[:] for v in master.vertices])
    tags={};bones={};copies=[]
    def key(p):return tuple(round(float(x),5) for x in p)
    def vals(coords):return [tags.get(key(p),(-1,0)) for p in coords]
    count=10
    for n in range(count):
        phi=n*math.tau/count;radial=U*math.cos(phi)+V*math.sin(phi)
        incline=.32*math.sin(n*2.4);length=.9+.18*math.sin(n*4.13)
        def centreline(t):
            a=phi+.42*t
            return C+(U*math.cos(a)+V*math.sin(a))*radius*(.91+length*t)+N*radius*(incline+.20*math.sin(math.pi*t))
        b=root+'Tongue%d'%n;m=b+'Curl';q=b+'Tip';phase=n*137.5;period=2.5+(n%4)*.31
        k.joint(b,pivot=tuple(centreline(0)),parent=root,motion=[
            {'Kind':'Bob','Dir':tuple(radial),'Amp':radius*.085,'Period':3.3+n*.12,'Phase':phase,'Shape':'pulse'},
            {'Kind':'Hinge','Axis':tuple(N),'Amp':5,'Period':period,'Phase':phase}])
        k.joint(m,pivot=tuple(centreline(.42)),parent=b,motion=[
            {'Kind':'Hinge','Axis':tuple(N),'Amp':13,'Period':period,'Phase':phase-55},
            {'Kind':'Hinge','Axis':tuple(radial),'Amp':11,'Period':period*1.23,'Phase':phase}])
        k.joint(q,pivot=tuple(centreline(.73)),parent=m,motion=[
            {'Kind':'Hinge','Axis':tuple(N),'Amp':25,'Period':period,'Phase':phase-115},
            {'Kind':'Bob','Dir':tuple(radial),'Amp':radius*.055,'Period':period*.73,'Phase':phase}])
        bones[b]=lambda coords,n=n:np.array([float(i==n) for i,t in vals(coords)])
        bones[m]=lambda coords:np.array([np.clip((t-.12)/.44,0,1) for i,t in vals(coords)])
        bones[q]=lambda coords:np.array([np.clip((t-.56)/.38,0,1) for i,t in vals(coords)])
        cp=ob if n==0 else k.bpy.data.objects.new(root+'TongueMesh'+str(n),master.copy())
        if n==0:cp.data=master.copy()
        else:k.bpy.context.scene.collection.objects.link(cp)
        for v,co in zip(cp.data.vertices,original):
            x,y,t=co;a=phi+.42*t;across=-U*math.sin(a)+V*math.cos(a)
            tilt=.48*math.sin(n*1.9)+.25*math.sin(t*math.pi)
            side=across*math.cos(tilt)+N*math.sin(tilt)
            depth=-across*math.sin(tilt)+N*math.cos(tilt)
            pos=centreline(t)+side*x*radius*2.25+depth*y*radius*1.6
            v.co=pos;tags[key(pos)]=(n,float(t))
        copies.append(cp)
    k.bpy.ops.object.select_all(action='DESELECT')
    for cp in copies:cp.select_set(True)
    k.bpy.context.view_layer.objects.active=ob;k.bpy.ops.object.join()
    k.skins[root+'SolarRig']={'root':root,'bones':bones,'meshes':[ob]}
    # Continuous sculpted incandescent rim grounds the moving roots on the dark sphere.
    _volume_material(k,'SolarVolume')
    bm=bmesh.new();uv=bm.loops.layers.uv.new('UVMap')
    for layer in (-1,1):
        def rim(t):
            a=math.tau*t;r=radius*(1.015+.020*math.sin(a*7+layer))
            return C+(U*math.cos(a)+V*math.sin(a))*r+N*radius*(layer*.055+.018*math.sin(a*5))
        _closed_flame(bm,uv,rim,lambda t:radius*.057,lambda t:radius*.04,lambda p,t:None,segments=64,sides=8)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges)
    k.add(root,k.mesh_object(root+'SolarRim',bm,['SolarVolume']))
