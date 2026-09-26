"""Shared helpers for the rooftop map package (assets/map).

The top half is pure Python (no bpy), so gen_textures.py can use it outside Blender: the
palette, the architecture trim sheet's layout, colour maths. The bottom half builds meshes in
Blender: a small mesh builder that works in Roblox studs and axes, trim-sheet UVs, bevelled
prisms, the FBX export and the checks.

Axes. Everything is built in Roblox world coordinates (studs): X right from the entrance (the
city is -X), Y up (the rooftop floor is Y = 0), Z toward the entrance. Roblox (X, Y, Z) is
Blender (X, -Z, Y); the FBX export (axis_forward -Z, axis_up Y, the table package's settings)
turns it back. Every object's origin is the world origin. The 3D Importer may still move or
turn the model, so it carries three anchor cubes (AnchorO at the origin, AnchorX 10 studs
along +X, AnchorZ 10 along +Z) that MapBuilder.prepareImport uses to put it back exactly.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------------------------------------
# Palette (measured, Palette.json; the Spec's section 2 picks which region is each material)
# ---------------------------------------------------------------------------------------------

with open(os.path.join(HERE, 'Palette.json')) as _handle:
    PALETTE = json.load(_handle)


def hexc(name, which='hex'):
    return PALETTE[name][which]


def desaturate(hex_colour, amount):
    """Move a colour toward the grey of the same luma by amount 0..1, as a hex string."""
    r, g, b = (int(hex_colour.lstrip('#')[i:i + 2], 16) for i in (0, 2, 4))
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    out = [round(c + (y - c) * amount) for c in (r, g, b)]
    return '#%02X%02X%02X' % tuple(out)


# The albedo of each material (Spec section 2). Only these colours are used. (A half-
# desaturated floor was tried first: under Roblox's cool sky it rendered neutral grey, so the
# measured colours are used as they are; Stage 2 critic.)
ALBEDO = {
    'floor': hexc('floor_panel_day'),
    'stone': hexc('step'),
    'stone_shade': hexc('step', 'shade'),
    'cream': hexc('column'),
    'cream_shade': hexc('column', 'shade'),
    'wood': hexc('pergola_slat'),
    'frame': hexc('railing_frame'),
    'glass': hexc('railing_glass'),
    'glow': hexc('under_table_glow'),
    'shadow': hexc('floor_shade'),  # the painter's cool shade: every AO darkens toward it
    'leaf_lit': hexc('leaf_lit'),
    'leaf_mid': hexc('leaf_mid'),
    'leaf_dark': hexc('leaf_dark'),
    'flower': hexc('flower_vivid'),
    'flower_dark': hexc('flower_pink'),
    'facade': hexc('city_facade_day'),
    'window': hexc('city_glass_day'),
    'window_sky': hexc('sky_horizon_day'),
}


def rgb(hex_colour):
    h = hex_colour.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """Blend two (r, g, b) tuples, t = 0 gives a."""
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def shade(colour, amount):
    """Darken toward the palette's shadow tint (a soft, cool AO), amount 0..1."""
    return mix(colour, rgb(ALBEDO['shadow']), amount)


def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# ---------------------------------------------------------------------------------------------
# The architecture trim sheet (textures/arch_color.png): horizontal strips, each a material
# with its soft AO baked in as a vertical gradient. A face's U runs along it and repeats (every
# strip is seamless left to right); its V spans the strip from bottom to top, so the gradient
# lands at the face's foot. Rows are image pixels from the top of a 1024 image.
# ---------------------------------------------------------------------------------------------

TRIM_PX = 1024
TRIM = {
    # name: (first row, last row + 1, studs per image width along U)
    'wall': (0, 160, 8.0),  # parapet and wall faces: AO at the foot, a light top edge
    'top': (160, 224, 8.0),  # lit horizontal tops: coping, treads
    'riser': (224, 352, 8.0),  # step risers and the lounge riser: AO at the foot, a nosing highlight
    'column': (352, 544, 4.0),  # cream columns: AO at the foot and under the capital
    'fascia': (544, 640, 8.0),  # the pergola's fascia: a shadow line along its underside
    'wood': (640, 736, 6.0),  # slats: grain along U
    'facade': (736, 992, 20.0),  # one tower floor, 10 studs tall: a band of windows
    'dark': (992, 1024, 8.0),  # near black (spare)
}
TRIM_PAD = 3  # pixels kept clear at each strip edge in V (mip bleeding)
FACADE_FLOOR_STUDS = 10.0  # the 'facade' strip is one floor this tall


def trim_v(strip, frac):
    """Blender V (0 at the image bottom) for a height fraction 0..1 within a strip."""
    top, bottom, _ = TRIM[strip]
    lo = 1.0 - (bottom - TRIM_PAD) / TRIM_PX
    hi = 1.0 - (top + TRIM_PAD) / TRIM_PX
    return lo + (hi - lo) * max(0.0, min(1.0, frac))


def trim_u(strip, studs):
    return studs / TRIM[strip][2]


# The overlays (textures/overlays.png, RGBA): the warm glow under each table, a linear contact
# shade along the foot of a wall, and a soft round shade under a column. UV rectangles in
# Blender convention (u0, v0, u1, v1).
OVERLAY = {
    'glow': (0.0, 0.0, 0.5, 1.0),
    'edge': (0.5, 0.5, 1.0, 1.0),  # V: 0.5 at the wall (dark) to 1.0 (clear); constant along U
    'blob': (0.5, 0.0, 1.0, 0.5),
}

# The foliage atlas (textures/foliage.png, RGBA).
FOLIAGE = {
    'drape': (0.0, 0.5, 1.0, 1.0),  # a hanging vine band, seamless along U, leaves at the top
    'climb': (0.0, 0.0, 0.5, 0.5),  # a climbing vine for column faces
    'bloom': (0.5, 0.0, 1.0, 0.5),  # a bougainvillea cluster
}


# ---------------------------------------------------------------------------------------------
# Blender: meshes in Roblox coordinates
# ---------------------------------------------------------------------------------------------

def rb(p):
    """Roblox (X, Y, Z) to Blender (X, -Z, Y)."""
    return (p[0], -p[2], p[1])


class Mesh:
    """Faces in Roblox studs with per-corner UVs. Winding: counterclockwise seen from the
    front (outside), right-handed as in Blender; face() takes the corners in that order.
    Horizontal outlines (x, z) go in outward_rect's order (up the -X side along +Z first), so
    each edge's wall (Mesh.wall) faces out of the outline and its flat top faces up."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []  # (indices, uvs)

    def face(self, points, uvs, double=False):
        base = len(self.verts)
        self.verts.extend(points)
        idx = tuple(range(base, base + len(points)))
        self.faces.append((idx, list(uvs)))
        if double:
            # The back face on its own vertices (a face over the same vertices would be the
            # same face to bmesh).
            back = len(self.verts)
            self.verts.extend(points)
            self.faces.append((tuple(range(back + len(points) - 1, back - 1, -1)), list(reversed(uvs))))

    def triangles(self):
        return sum(len(i) - 2 for i, _ in self.faces)

    # -- building blocks ------------------------------------------------------------------

    def wall(self, a, b, y0, y1, strip, u0=0.0, v_range=(0.0, 1.0), normal_out=None):
        """A vertical quad from a to b (x, z) between heights y0 and y1, its normal (-dz, 0, dx)
        for d = b - a, so walls round an outline in outward_rect's order face out. Seen from
        the front, a is on the left. U runs along it from u0 studs; V maps y0..y1 to v_range
        of the strip."""
        (ax, az), (bx, bz) = a, b
        length = math.hypot(bx - ax, bz - az)
        u1 = u0 + length
        va, vb = trim_v(strip, v_range[0]), trim_v(strip, v_range[1])
        pts = [(ax, y0, az), (bx, y0, bz), (bx, y1, bz), (ax, y1, az)]
        uvs = [(trim_u(strip, u0), va), (trim_u(strip, u1), va), (trim_u(strip, u1), vb), (trim_u(strip, u0), vb)]
        self.face(pts, uvs)
        return u1

    def flat(self, poly, y, strip, up=True, frac=0.5, along='x'):
        """A horizontal polygon (x, z) at height y, facing up (or down); U planar along X (or
        Z), V a constant line in the strip."""
        v = trim_v(strip, frac)
        pts = [(x, y, z) for x, z in poly]
        uvs = [(trim_u(strip, x if along == 'x' else z), v) for x, z in poly]
        if not up:
            pts, uvs = list(reversed(pts)), list(reversed(uvs))
        self.face(pts, uvs)

    def prism(self, poly, y0, y1, strip, top=True, bottom=False, top_strip='top', v_range=(0.0, 1.0)):
        """A vertical prism over a convex outline (x, z) in outward_rect's order, from y0 to y1;
        the sides UV'd along the perimeter."""
        n = len(poly)
        u = 0.0
        for i in range(n):
            a, b = poly[i], poly[(i + 1) % n]
            u = self.wall(a, b, y0, y1, strip, u, v_range)
        if top:
            self.flat(poly, y1, top_strip, up=True)
        if bottom:
            self.flat(poly, y0, top_strip, up=False)

    def box_x(self, x0, x1, y0, y1, z0, z1, strip, ends=True, top_strip='top'):
        """An axis-aligned box as a prism (walls all round, a top, optional end caps)."""
        poly = outward_rect(x0, z0, x1, z1)
        self.prism(poly, y0, y1, strip, top=True, top_strip=top_strip)

    def quad(self, p0, p1, p2, p3, uv_rect, double=False):
        """Any quad (Roblox points, counterclockwise from the front) with a UV rectangle
        (u0, v0, u1, v1): p0 at (u0, v0), p1 (u1, v0), p2 (u1, v1), p3 (u0, v1)."""
        u0, v0, u1, v1 = uv_rect
        self.face([p0, p1, p2, p3], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], double=double)


def outward_rect(x0, z0, x1, z1):
    """A rectangle's corners in the order whose walls (Mesh.wall) face outward."""
    return [(x0, z0), (x0, z1), (x1, z1), (x1, z0)]


def chamfer_rect(cx, cz, hx, hz, c):
    """A rectangle centred (cx, cz), half extents (hx, hz), corners cut by c, in outward order."""
    pts = [(-hx, -hz + c), (-hx, hz - c), (-hx + c, hz), (hx - c, hz), (hx, hz - c), (hx, -hz + c),
           (hx - c, -hz), (-hx + c, -hz)]
    return [(cx + x, cz + z) for x, z in pts]


# ---------------------------------------------------------------------------------------------
# Blender objects, export and checks
# ---------------------------------------------------------------------------------------------

def to_object(mesh, collection, material=None):
    import bmesh
    import bpy
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    verts = [bm.verts.new(rb(p)) for p in mesh.verts]
    for idx, uvs in mesh.faces:
        # Roblox -> Blender is a proper rotation (a quarter turn about X), so windings keep.
        face = bm.faces.new([verts[i] for i in idx])
        for loop, coord in zip(face.loops, uvs):
            loop[uv].uv = coord
        face.smooth = False
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='FIXED', ngon_method='EAR_CLIP')
    data = bpy.data.meshes.new(mesh.name + 'Mesh')
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(mesh.name, data)
    collection.objects.link(obj)
    if material is not None:
        data.materials.append(material)
    obj['triangle_count'] = len(data.polygons)
    return obj


def anchor_meshes():
    """Three 0.2-stud cubes: AnchorO at the origin, AnchorX at (10, 0, 0), AnchorZ at (0, 0, 10)."""
    out = []
    for name, (x, z) in (('AnchorO', (0, 0)), ('AnchorX', (10, 0)), ('AnchorZ', (0, 10))):
        m = Mesh(name)
        h = 0.1
        m.prism(outward_rect(x - h, z - h, x + h, z + h), -h, h, 'dark', top=True, bottom=True)
        out.append(m)
    return out


def clear_scene():
    import bpy
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.collections, bpy.data.images):
        for block in list(pool):
            pool.remove(block)
    scene = bpy.context.scene
    scene.unit_settings.system = 'NONE'
    scene.unit_settings.scale_length = 1.0
    return scene


def export_fbx(path, objects):
    """The table package's export settings (assets/table/table_common.py)."""
    import bpy
    if 'fbx' not in dir(bpy.ops.export_scene):
        import addon_utils
        addon_utils.enable('io_scene_fbx', default_set=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in objects)
    bpy.context.view_layer.objects.active = objects[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={'MESH'},
                             axis_forward='-Z', axis_up='Y', global_scale=1.0, apply_unit_scale=False,
                             apply_scale_options='FBX_SCALE_UNITS', use_space_transform=True,
                             bake_space_transform=True, use_mesh_modifiers=True, use_triangles=True,
                             mesh_smooth_type='OFF', add_leaf_bones=False, bake_anim=False,
                             path_mode='RELATIVE', embed_textures=False, colors_type='NONE',
                             use_custom_props=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(False)


def roundtrip_check(path, objects, tolerance=1e-3):
    """Re-import the FBX into a scratch scene and compare every mesh's world bounds."""
    import bpy

    def bounds(obj):
        pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
        return [min(p[i] for p in pts) for i in range(3)] + [max(p[i] for p in pts) for i in range(3)]

    expected = {o.name: bounds(o) for o in objects}
    names = {o: o.name for o in objects}
    for o in objects:
        o.name = o.name + '__source'
    before = {pool: set(getattr(bpy.data, pool)) for pool in ('objects', 'meshes', 'materials')}
    scratch = bpy.data.scenes.new('MapReimportCheck')
    with bpy.context.temp_override(scene=scratch, view_layer=scratch.view_layers[0]):
        bpy.ops.import_scene.fbx(filepath=path)
    worst = 0.0
    found = []
    for obj in scratch.objects:
        found.append(obj.name)
        want = expected.get(obj.name)
        assert want is not None, ('reimported name is not exact', obj.name)
        worst = max(worst, max(abs(a - b) for a, b in zip(bounds(obj), want)))
    for pool, old in before.items():
        for block in list(getattr(bpy.data, pool)):
            if block not in old:
                getattr(bpy.data, pool).remove(block)
    bpy.data.scenes.remove(scratch)
    for o, n in names.items():
        o.name = n
    assert sorted(found) == sorted(expected), ('reimported meshes', sorted(found))
    assert worst <= tolerance, ('FBX round trip moved a bounding box by', worst)
    return worst
