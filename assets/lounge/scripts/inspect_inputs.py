import bpy,json
print('BLENDER',bpy.app.version_string)
print('CURRENT',bpy.data.filepath)
print('SCENES',[(s.name,len(s.objects)) for s in bpy.data.scenes])
lib='/Users/justinjin/Desktop/8ball/assets/table/PoolTable_9ft.blend'
with bpy.data.libraries.load(lib,link=False) as (src,dst):
    print('SOURCE_OBJECTS',src.objects)
    print('SOURCE_COLLECTIONS',src.collections)
    dst.objects=[n for n in src.objects if n in ('Bed','Cushions','Rails','Pockets','Apron','Legs','Sights')]
col=bpy.data.collections.get('Table_Source') or bpy.data.collections.new('Table_Source')
for o in dst.objects:
    col.objects.link(o)
    print('TABLE',o.name,tuple(o.dimensions),tuple(o.location),len(o.data.polygons),[m.name for m in o.data.materials])
print('IMAGES',[(i.name,tuple(i.size),bool(i.packed_file),i.filepath) for i in bpy.data.images if i.source=='FILE'][:40])
