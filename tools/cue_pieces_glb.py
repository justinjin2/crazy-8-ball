#!/usr/bin/env python3
"""Turn each cue piece folder's rigid OBJ parts into one GLB for Open Cloud (which takes no .obj).

    python3 tools/cue_pieces_glb.py [piece ...]      (no names: every folder with OBJs)

Writes assets/cue/pieces/<piece>/<piece>_parts.glb: one object per piece.json part (named by the
part's `Name`, which Roblox keeps as the MeshPart's name), UVs kept, normals recalculated, no
materials (Material, Color and maps come from piece.json at runtime). The OBJs are in the Roblox
cue frame, recentred on each part's box; Roblox's importer turns Blender (x, y, z) into Roblox
(-x, z, y), so each vertex goes in as (-X, Z, Y). Placement at runtime comes from the part's
`Offset`, never from where the importer puts it. Skinned parts keep their own GLBs.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIECES = os.path.join(ROOT, 'assets', 'cue', 'pieces')
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'


def read_obj(path):
    verts, uvs, faces, smooth = [], [], [], []
    shading = False
    with open(path) as fh:
        for line in fh:
            bits = line.split()
            if not bits:
                continue
            if bits[0] == 'v':
                x, y, z = map(float, bits[1:4])
                verts.append((-x, z, y))
            elif bits[0] == 'vt':
                uvs.append((float(bits[1]), float(bits[2])))
            elif bits[0] == 's':
                shading = bits[1] not in ('0', 'off')
            elif bits[0] == 'f':
                faces.append([tuple(int(i) - 1 if i else None for i in (c.split('/') + [''])[:2]) for c in bits[1:]])
                smooth.append(shading)
    return verts, uvs, faces, smooth


def build(piece):
    import bmesh
    import bpy
    spec = json.load(open(os.path.join(PIECES, piece, 'piece.json')))
    rigid = [p for p in spec['Parts'] if p['File'].endswith('.obj')]
    if not rigid:
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for part in rigid:
        verts, uvs, faces, smooth = read_obj(os.path.join(ROOT, 'assets', 'cue', part['File']))
        mesh = bpy.data.meshes.new(part['Name'])
        bm = bmesh.new()
        bv = [bm.verts.new(v) for v in verts]
        uvl = bm.loops.layers.uv.new('UVMap') if uvs else None
        for f, shading in zip(faces, smooth):
            try:
                face = bm.faces.new([bv[i] for i, _ in f])
                face.smooth = shading
            except ValueError:
                continue  # a duplicate face
            if uvl is not None:
                for loop, (_, t) in zip(face.loops, f):
                    if t is not None:
                        loop[uvl].uv = uvs[t]
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(part['Name'], mesh)
        bpy.context.scene.collection.objects.link(obj)
    out = os.path.join(PIECES, piece, piece + '_parts.glb')
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_materials='NONE', export_apply=True)
    print('CUE glb %s: %d parts -> %s' % (piece, len(rigid), os.path.relpath(out, ROOT)))


def main():
    if '--' in sys.argv:  # inside Blender
        names = sys.argv[sys.argv.index('--') + 1:]
        for piece in names:
            build(piece)
        return
    names = sys.argv[1:] or sorted(d for d in os.listdir(PIECES)
                                   if any(f.endswith('.obj') for f in os.listdir(os.path.join(PIECES, d))))
    res = subprocess.run([BLENDER, '-b', '--factory-startup', '--python-exit-code', '1', '--python', __file__, '--'] + names,
                         capture_output=True, text=True)
    for line in (res.stdout + res.stderr).splitlines():
        if line.startswith('CUE') or 'Error' in line or 'Traceback' in line:
            print(line)
    sys.exit(res.returncode)


if __name__ == '__main__':
    main()
