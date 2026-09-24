"""Shared helpers for the pool table package: TableModel.py builds and validates the meshes,
TableRender.py renders the designer sheet. Headless-safe: bmesh and data calls only; the only
operators used anywhere in the package are FBX export/import, render and save.

Units. Every builder works in inches in the physics frame of Geometry.json (x along the length,
head -x / foot +x; y across, the top rail with pockets 1-3 is +y; z up with the cloth at z = 0).
Part.to_bmesh converts to Blender studs: (x * s, y * s, z * s + h), s = studs_per_inch,
h = cloth.above_floor_studs, so the floor is Blender Z = 0 and every origin is the table centre
on the floor.
"""

import hashlib
import json
import math
import os
from array import array
from math import acos, atan2, ceil, cos, pi, sin, sqrt

import bmesh
import bpy
from mathutils import Vector
from mathutils import geometry as mgeom

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()


# ---------------------------------------------------------------------------------------------
# Pure helpers reused verbatim from assets/table/legacy/PoolTable.py (the brief names these four)
# ---------------------------------------------------------------------------------------------

def _linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _color(rgb):
    return tuple(_linear(v) for v in rgb) + (1.0,)


def _save_progress(outdir, objname, record):
    path = outdir / (objname + '_bake.json')
    temporary = path.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    os.replace(temporary, path)


def _geometry_signature(obj):
    """Invalidate cached pixels when any geometry or UV coordinate changes."""
    digest = hashlib.sha256()
    xyz = array('f', [0.0]) * (len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get('co', xyz)
    digest.update(xyz.tobytes())
    uv = array('f', [0.0]) * (len(obj.data.loops) * 2)
    obj.data.uv_layers.active.data.foreach_get('uv', uv)
    digest.update(uv.tobytes())
    digest.update(repr(tuple(tuple(row) for row in obj.matrix_world)).encode('utf-8'))
    return digest.hexdigest()


# ---------------------------------------------------------------------------------------------
# Geometry.json: load, assert the schema and the consistency the brief asks for
# ---------------------------------------------------------------------------------------------

def load_geometry(path):
    with open(path, 'rb') as handle:
        raw = handle.read()
    g = json.loads(raw)
    assert g.get('schema_version') == 1, ('Geometry.json schema_version', g.get('schema_version'))
    for key in ('frame', 'units', 'legend'):
        assert isinstance(g.get(key), (str, dict)) and g[key], 'Geometry.json has no ' + key
    check_geometry(g)
    return g, hashlib.sha256(raw).hexdigest()


def _near(a, b, tol=1e-9):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def check_geometry(g):
    """Every cushion chain closes (legend.cushions), facings and jaws belong to their holes, the
    corner jaw points lie on their hole rims, and the counts match the brief."""
    assert len(g['holes']) == 6 and len(g['segments']) == 18 and len(g['points']) == 24
    assert len(g['cushions']) == 6 and len(g['rack']['balls']) == 15
    segs = {s['name']: s for s in g['segments']}
    pts = {p['name']: p for p in g['points']}
    for c in g['cushions']:
        rail, f1, f2 = segs[c['rail']], segs[c['facings'][0]], segs[c['facings'][1]]
        assert rail['kind'] == 'rail' and f1['kind'] == 'facing' and f2['kind'] == 'facing', c
        # facings[1] runs b -> a into the rail's a; the rail runs a -> b; facings[2] leaves from b.
        assert _near(f1['a'], rail['a']) and _near(f2['a'], rail['b']), ('cushion chain open', c)
        assert f1['pocket'] == c['pockets'][0] and f2['pocket'] == c['pockets'][1], c
    for h in g['holes']:
        centre = (h['x'], h['y'])
        assert abs(h['clear_radius'] - (h['radius'] - g['ball']['radius'] + g['ball']['render_radius'])) < 1e-9
        for fname, jname in zip(h['facings'], h['jaws']):
            f, j = segs[fname], pts[jname]
            assert f['pocket'] == h['id'] and j['pocket'] == h['id'] and j['facing'] == fname, (h['id'], fname)
            assert _near(f['b'], (j['x'], j['y'])), ('jaw is not the facing b end', jname)
            assert abs(j['radius'] - g['pockets']['jaw_radius']) < 1e-12
            if h['kind'] == 'corner':
                assert abs(math.dist((j['x'], j['y']), centre) - h['radius']) < 1e-9, ('jaw off the rim', jname)
        # Turning counterclockwise from jaws[1] to jaws[2] crosses the mouth: the table side.
        j1, j2 = pts[h['jaws'][0]], pts[h['jaws'][1]]
        a1 = atan2(j1['y'] - h['y'], j1['x'] - h['x'])
        a2 = atan2(j2['y'] - h['y'], j2['x'] - h['x'])
        mid = a1 + ccw_span(a1, a2) / 2
        assert (cos(mid) * -h['x'] + sin(mid) * -h['y']) > 0, ('mouth is not on the table side', h['id'])
    for p in g['points']:
        f = segs[p['facing']]
        end = f['a'] if p['kind'] == 'nose' else f['b']
        assert _near(end, (p['x'], p['y'])), p['name']


# ---------------------------------------------------------------------------------------------
# 2D vector helpers (tuples) and arcs
# ---------------------------------------------------------------------------------------------

def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def length(a):
    return sqrt(a[0] * a[0] + a[1] * a[1])


def unit(a):
    n = length(a)
    return (a[0] / n, a[1] / n)


def ang(a):
    return atan2(a[1], a[0])


def polar(c, r, a):
    return (c[0] + r * cos(a), c[1] + r * sin(a))


def ccw_span(a0, a1):
    """Counterclockwise turn from angle a0 to a1, in [0, 2 pi)."""
    return (a1 - a0) % (2 * pi)


def line_intersect(p, d, q, e):
    """Intersection of the lines p + s d and q + t e."""
    den = cross(d, e)
    assert abs(den) > 1e-12, 'parallel lines'
    s = cross(sub(q, p), e) / den
    return add(p, mul(d, s))


def ray_circle(origin, direction, centre, radius):
    """First forward hit of a ray from inside the circle."""
    f = sub(origin, centre)
    b = dot(f, direction)
    c = dot(f, f) - radius * radius
    disc = b * b - c
    assert disc >= 0, 'ray misses circle'
    return add(origin, mul(direction, -b + sqrt(disc)))


def line_circle(p, d, centre, radius):
    """Both parameters s (p + s d, d unit) where the line meets the circle, sorted."""
    f = sub(p, centre)
    b = dot(f, d)
    c = dot(f, f) - radius * radius
    disc = b * b - c
    if disc < 0:
        return []
    r = sqrt(disc)
    return [-b - r, -b + r]


def arc_steps(radius, span, tol):
    """Segments so the sagitta stays within tol (equal-error tessellation halves it again)."""
    if radius <= tol:
        return 1
    return max(1, ceil(abs(span) / (2 * acos(1 - tol / radius)) - 1e-9))


def arc(centre, radius, a0, span, n, equal_error=False, ends=True):
    """n segments from angle a0 turning span (signed). With equal_error the interior vertices sit
    at r (1 + sec(phi / 2)) / 2 so the polygon straddles the true circle; the ends stay exact."""
    phi = abs(span) / n
    rr = radius * (1 + 1 / cos(phi / 2)) / 2 if equal_error else radius
    out = []
    for k in range(n + 1):
        if not ends and k in (0, n):
            continue
        rad = radius if k in (0, n) else rr
        out.append(polar(centre, rad, a0 + span * k / n))
    return out


def point_in_poly(p, poly):
    x, y = p
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            if x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                inside = not inside
    return inside


def poly_area(poly):
    return 0.5 * sum(cross(poly[i], poly[(i + 1) % len(poly)]) for i in range(len(poly)))


def seg_dist(p, a, b):
    ab = sub(b, a)
    t = max(0.0, min(1.0, dot(sub(p, a), ab) / dot(ab, ab)))
    return length(sub(p, add(a, mul(ab, t))))


def triangulate(outer, holes=(), extra_edges=()):
    """Constrained Delaunay triangulation of a polygon (with holes), returned as CCW index
    triples into outer + holes concatenated. extra_edges are (i, j) pairs in that indexing that
    must appear as edges. Raises if the CDT had to add or merge a vertex."""
    loops = [list(outer)] + [list(h) for h in holes]
    verts, edges = [], []
    for loop in loops:
        base = len(verts)
        verts += loop
        edges += [(base + i, base + (i + 1) % len(loop)) for i in range(len(loop))]
    edges += list(extra_edges)
    out = mgeom.delaunay_2d_cdt([Vector(p) for p in verts], edges, [], 0, 1e-9)
    overts, ofaces, orig = out[0], out[2], out[3]
    remap = []
    for i, ids in enumerate(orig):
        assert len(ids) == 1, ('triangulate merged or added a vertex', i, ids, tuple(overts[i]))
        remap.append(ids[0])
    tris = []
    for f in ofaces:
        idx = [remap[i] for i in f]
        a, b, c = (verts[i] for i in idx)
        cen = ((a[0] + b[0] + c[0]) / 3, (a[1] + b[1] + c[1]) / 3)
        if not point_in_poly(cen, loops[0]) or any(point_in_poly(cen, h) for h in loops[1:]):
            continue
        if cross(sub(b, a), sub(c, a)) < 0:
            idx = [idx[0], idx[2], idx[1]]
        tris.append(tuple(idx))
    return verts, tris


# ---------------------------------------------------------------------------------------------
# Parts: inch-space vertex/face lists with per-loop UVs and a face tag, turned into bmesh
# ---------------------------------------------------------------------------------------------

class Part:
    """A piece of a mesh. Faces keep their winding (front = counterclockwise seen from outside);
    each face carries per-loop UVs and an integer tag the validators read."""

    def __init__(self, name='part', closed=False):
        self.name = name
        self.closed = closed
        self.co = []
        self.faces = []

    def v(self, p):
        self.co.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.co) - 1

    def vk(self, p):
        """A shared vertex: the same rounded position always gives the same index."""
        if not hasattr(self, '_pool'):
            self._pool = {}
        key = tuple(round(c, 7) for c in p)
        if key not in self._pool:
            self._pool[key] = self.v(p)
        return self._pool[key]

    def f(self, idx, uvs, tag):
        idx = tuple(idx)
        assert len(set(idx)) == len(idx) >= 3, ('degenerate face', self.name, idx)
        assert len(uvs) == len(idx)
        self.faces.append((idx, [tuple(u) for u in uvs], tag))

    def quad(self, a, b, c, d, uvs, tag):
        self.f((a, b, c, d), uvs, tag)

    def flip(self, start=0):
        self.faces[start:] = [(tuple(reversed(i)), list(reversed(u)), t) for i, u, t in self.faces[start:]]

    def fix_uv_sign(self, k):
        """Mirror u on face k if its UVs turn against its winding (planar faces only)."""
        idx, uvs, t = self.faces[k]
        area = 0.0
        for i in range(len(uvs)):
            a, b = uvs[i], uvs[(i + 1) % len(uvs)]
            area += a[0] * b[1] - a[1] * b[0]
        if area < 0:
            self.faces[k] = (idx, [(-u, v) for u, v in uvs], t)

    def signed_volume(self):
        vol = 0.0
        for idx, _, _ in self.faces:
            p0 = self.co[idx[0]]
            for k in range(1, len(idx) - 1):
                a, b = self.co[idx[k]], self.co[idx[k + 1]]
                vol += (p0[0] * (a[1] * b[2] - a[2] * b[1]) - p0[1] * (a[0] * b[2] - a[2] * b[0])
                        + p0[2] * (a[0] * b[1] - a[1] * b[0])) / 6.0
        return vol

    def orient_closed(self):
        """Closed shells built from mirrored templates: make the signed volume positive."""
        if self.signed_volume() < 0:
            self.flip()

    def face_normal(self, k):
        idx = self.faces[k][0]
        a, b, c = (Vector(self.co[i]) for i in idx[:3])
        return (b - a).cross(c - a).normalized()


def parts_to_bmesh(parts, s, h, merge):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    tag = bm.faces.layers.int.new('tag')
    for part in parts:
        verts = [bm.verts.new((x * s, y * s, z * s + h)) for x, y, z in part.co]
        made = []
        for idx, uvs, t in part.faces:
            face = bm.faces.new([verts[i] for i in idx])
            face[tag] = t
            for loop, coord in zip(face.loops, uvs):
                loop[uv].uv = coord
            made.append(face)
        # Merge within the part only: separate pieces (rail pieces, legs) stay separate shells.
        bmesh.ops.remove_doubles(bm, verts=[v for v in verts if v.is_valid], dist=merge)
        if part.closed:
            # A closed shell: make every face point out of its own component (UVs ride along).
            bmesh.ops.recalc_face_normals(bm, faces=[f for f in made if f.is_valid])
    bm.verts.ensure_lookup_table()
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    return bm


def finish(bm, name, collection, sharp_degrees, material):
    """Triangulate, smooth by angle, and link one object at the origin with one material."""
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3],
                          quad_method='FIXED', ngon_method='EAR_CLIP')
    bm.normal_update()
    sharp = math.radians(sharp_degrees)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        e.smooth = len(e.link_faces) == 2 and e.calc_face_angle(pi) < sharp
    mesh = bpy.data.meshes.new(name + 'Mesh')
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    tags = [0] * len(mesh.polygons)
    attr = mesh.attributes.get('tag')
    if attr is not None:
        attr.data.foreach_get('value', tags)
        mesh.attributes.remove(attr)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
    obj['triangle_count'] = len(mesh.polygons)
    mesh.materials.append(material)
    return obj, list(tags)


# ---------------------------------------------------------------------------------------------
# Scene, materials, export, round trip, parameters, save (the Bridge.py template)
# ---------------------------------------------------------------------------------------------

def ensure_fbx_addon():
    if 'fbx' not in dir(bpy.ops.export_scene) or 'fbx' not in dir(bpy.ops.import_scene):
        import addon_utils
        addon_utils.enable('io_scene_fbx', default_set=True)
    assert 'fbx' in dir(bpy.ops.export_scene), 'the FBX exporter (io_scene_fbx) is not available'


def clear_scene(name):
    scene = bpy.context.scene
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.collections, bpy.data.worlds, bpy.data.images):
        for block in list(pool):
            pool.remove(block)
    scene.name = name
    scene.unit_settings.system = 'NONE'
    scene.unit_settings.scale_length = 1.0
    return scene


def preview_material(name, rgb, roughness, metallic):
    mat = bpy.data.materials.new(name)
    colour = _color([c / 255.0 for c in rgb])  # rgb is sRGB 0..255; _color takes 0..1
    mat.diffuse_color = colour
    if mat.node_tree is None:
        mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    out = nodes.new('ShaderNodeOutputMaterial')
    shader.location, out.location = (0, 0), (300, 0)
    links.new(shader.outputs['BSDF'], out.inputs['Surface'])
    shader.inputs['Base Color'].default_value = colour
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    return mat


def export_fbx(path, objects):
    view_layer = bpy.context.view_layer
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in objects)
    view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={'MESH'},
                             axis_forward='-Z', axis_up='Y', global_scale=1.0, apply_unit_scale=False,
                             apply_scale_options='FBX_SCALE_UNITS', use_space_transform=True,
                             bake_space_transform=True, use_mesh_modifiers=True, use_triangles=True,
                             mesh_smooth_type='OFF', add_leaf_bones=False, bake_anim=False,
                             path_mode='RELATIVE', embed_textures=False, colors_type='NONE',
                             use_custom_props=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)


def world_bounds(obj, matrix):
    pts = [matrix @ v.co for v in obj.data.vertices]
    return ([min(c[i] for c in pts) for i in range(3)], [max(c[i] for c in pts) for i in range(3)])


def reimport_check(path, objects, tolerance):
    expected = {o.name: world_bounds(o, o.matrix_world) for o in objects}
    names = {o: o.name for o in objects}
    for o in objects:  # free the names so the imported objects keep theirs exactly
        o.name = o.name + '__source'
    before = {pool: set(getattr(bpy.data, pool)) for pool in ('objects', 'meshes', 'materials', 'images')}
    scratch = bpy.data.scenes.new('TableReimportCheck')
    with bpy.context.temp_override(scene=scratch, view_layer=scratch.view_layers[0]):
        bpy.ops.import_scene.fbx(filepath=path)
    scratch.view_layers[0].update()
    imported = [o for o in scratch.objects]
    worst, found, per_mesh = 0.0, [], {}
    for obj in imported:
        assert obj.type == 'MESH', ('the FBX holds a non-mesh object', obj.name, obj.type)
        found.append(obj.name)
        lo, hi = world_bounds(obj, obj.matrix_world)
        elo, ehi = expected.get(obj.name, (None, None))
        assert elo is not None, ('reimported name is not exact', obj.name)
        err = max(abs(a - b) for a, b in zip(lo + hi, elo + ehi))
        per_mesh[obj.name] = err
        worst = max(worst, err)
    assert sorted(found) == sorted(expected), ('reimported meshes', sorted(found))
    for pool, old in before.items():
        for block in list(getattr(bpy.data, pool)):
            if block not in old:
                getattr(bpy.data, pool).remove(block)
    bpy.data.scenes.remove(scratch)
    for o, n in names.items():
        o.name = n
    assert worst <= tolerance, ('FBX round trip moved a bounding box by', worst)
    return worst, per_mesh


def clean(value):
    """Round away float noise and never write -0.0."""
    if isinstance(value, float):
        return round(value, 9) + 0.0
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    return value


def embed_scripts(names):
    for text_name in names:
        source = os.path.join(HERE, text_name)
        if not os.path.isfile(source):
            continue
        text = bpy.data.texts.get(text_name) or bpy.data.texts.new(text_name)
        text.clear()
        with open(source) as handle:
            text.write(handle.read())


def save_blend(path):
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False, compress=True)
    backup = path + '1'
    if os.path.exists(backup):
        os.remove(backup)  # a headless rebuild regenerates everything; no .blend1 residue
