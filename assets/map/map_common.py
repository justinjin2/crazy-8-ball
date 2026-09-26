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
    'soffit': (992, 1008, 8.0),  # the pergola fascia's underside and inner faces: the cream's shade
    'dark': (1008, 1024, 8.0),  # near black (spare)
}
TRIM_PAD = 3  # pixels kept clear at each strip edge in V (mip bleeding)
FACADE_FLOOR_STUDS = 10.0  # the 'facade' strip is one floor this tall

# The props trim sheet (textures/props_color.png), laid out the same way: one strip per prop
# material, soft AO at each strip's foot. The names start with p_ so a mesh can never mix the
# two sheets by accident (a prop mesh uses only p_ strips, an architecture mesh none).
PROP_STRIP_PX = 46
_PROP_STRIPS = [
    # name, studs per image width along U, what it is
    ('p_fabric', 4.0),  # couch fabric: warm grey-cream
    ('p_cushion_blue', 4.0),
    ('p_cushion_teal', 4.0),  # the art's light blue-grey cushion
    ('p_cushion_orange', 4.0),
    ('p_cushion_white', 4.0),
    ('p_wood', 4.0),  # warm wood (coffee table top, umbrella frame): grain along U
    ('p_wood_dark', 4.0),  # dark wood (table legs and aprons, lounger frames)
    ('p_stone_dark', 4.0),  # the fire pit's dark stone
    ('p_stone_cap', 4.0),  # the fire pit's light stone cap
    ('p_glass_ring', 4.0),  # the fire pit's blue glass ring
    ('p_frame', 4.0),  # lantern frames: dark bronze
    ('p_canvas', 6.0),  # umbrella canvas: cream, soft panel shading along U
    ('p_pole', 4.0),  # umbrella pole: wood
    ('p_lounger', 4.0),  # lounger body: dark warm grey
    ('p_piano', 4.0),  # the grand piano: black with a sheen near the top of the strip
    ('p_keys', 1.2),  # piano keys: white keys with the black ones in 2s and 3s along U
    ('p_planter', 4.0),  # planter boxes: warm light stone
    ('p_soil', 4.0),  # soil in a planter
    ('p_trunk', 4.0),  # palm trunk: rings along V
    ('p_metal', 4.0),  # metal: brushed grey
    ('p_leaf', 4.0),  # solid leaf green (opaque leafy bits)
    ('p_white', 4.0),  # off-white (lounger cushions, piano bench cushion)
]
PROP_TRIM = {name: (k * PROP_STRIP_PX, (k + 1) * PROP_STRIP_PX, studs)
             for k, (name, studs) in enumerate(_PROP_STRIPS)}

# The near world's trim sheet (textures/near_color.png, RGBA: opaque except the shallows strip),
# laid out like the architecture sheet with n_ names. Facades are one floor (FACADE_FLOOR_STUDS)
# tall, like the tower's; frac 0 is a strip's foot.
NEAR_TRIM = {
    'n_glass': (0, 96, 20.0),  # blue glass curtain wall: mullions every 2.5, a spandrel at the floor
    'n_stone': (96, 192, 20.0),  # cream stone, punched windows
    'n_terracotta': (192, 288, 20.0),  # salmon terracotta, punched windows
    'n_white': (288, 384, 20.0),  # white modern, ribbon windows
    'n_lobby': (384, 480, 20.0),  # a ground floor: tall glass with a lit interior between piers
    'n_roof': (480, 528, 16.0),  # flat roof: light grey membrane, faint seams along U
    'n_cap': (528, 560, 8.0),  # roof parapet caps and rooftop boxes
    'n_road': (560, 640, 24.0),  # a street across V (kerb to kerb): edge lines, a dashed centre
    'n_crosswalk': (640, 688, 12.0),  # zebra stripes along U
    'n_sidewalk': (688, 736, 8.0),  # paving slabs
    'n_plaza': (736, 784, 12.0),  # the tower's plaza: big light slabs
    'n_promenade': (784, 832, 8.0),  # warm paving along the sea wall
    'n_seawall': (832, 864, 8.0),  # the sea wall's face: stone, shade at the foot
    'n_sand': (864, 928, 16.0),  # wet sand at the foot (the waterline), dry at the top
    'n_shallows': (928, 976, 16.0),  # alpha: clear at the foot, turquoise, foam at the top (the sand)
    'n_hull': (976, 992, 8.0),  # boat hull: white with a blue stripe
    'n_sail': (992, 1008, 8.0),  # sail cloth: cream
    'n_wood': (1008, 1024, 4.0),  # dark wood and trunks: masts, decks, palm and tree trunks
}
FACADE_STYLES = ('n_glass', 'n_stone', 'n_terracotta', 'n_white')
_ALL_TRIM = dict(TRIM, **PROP_TRIM, **NEAR_TRIM)


def trim_v(strip, frac):
    """Blender V (0 at the image bottom) for a height fraction 0..1 within a strip (of either
    trim sheet: architecture strips or p_ prop strips)."""
    top, bottom, _ = _ALL_TRIM[strip]
    lo = 1.0 - (bottom - TRIM_PAD) / TRIM_PX
    hi = 1.0 - (top + TRIM_PAD) / TRIM_PX
    return lo + (hi - lo) * max(0.0, min(1.0, frac))


def trim_u(strip, studs):
    return studs / _ALL_TRIM[strip][2]


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

# The plants atlas (textures/plants.png, RGBA; drawn by props/plants_textures.py).
PLANTS = {
    'frond': (0.0, 0.5, 1.0, 1.0),  # a palm frond: its stem along U, the base at u0, the tip at u1
    'fern': (0.0, 0.0, 0.5, 0.5),  # a fern frond: the same way round
    'clump': (0.5, 0.0, 1.0, 0.5),  # a round leafy clump seen from above
}


# Which prop templates (gen_props.py kinds) dress each Layout.json prop kind. A palm planter is
# a PalmPlanter box with a Palm on top, scaled to the planned height.
PROP_TEMPLATES = {
    'lounge_couch': ['LoungeCouch'], 'side_couch': ['SideCouch'], 'coffee_table': ['CoffeeTable'],
    'fire_pit': ['FirePit'], 'fern_planter': ['FernPlanter'], 'palm_planter': ['PalmPlanter', 'Palm'],
    'planter_bed': ['PlanterBed'], 'lantern': ['Lantern'], 'lantern_tall': ['LanternTall'],
    'globe_light': ['GlobeLight'], 'umbrella_set': ['UmbrellaSet'], 'piano': ['Piano'],
    'piano_bench': ['PianoBench'],
}
PALM_HEIGHT = 22.8  # the Palm template's crown top above its origin (26 overall on its box)
PLANTER_BOX_HEIGHT = 3.2  # the PalmPlanter box; the Palm stands on it


def angles(rx=0.0, ry=0.0, rz=0.0):
    """The 3x3 rotation of Roblox's CFrame.Angles(rx, ry, rz), degrees: v' = Rx(Ry(Rz v))."""
    def rot(axis, deg):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        if axis == 'x':
            return ((1, 0, 0), (0, c, -s), (0, s, c))
        if axis == 'y':
            return ((c, 0, s), (0, 1, 0), (-s, 0, c))
        return ((c, -s, 0), (s, c, 0), (0, 0, 1))

    def mul(a, b):
        return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    return mul(mul(rot('x', rx), rot('y', ry)), rot('z', rz))


def _circle(cx, cz, r, segs, phase=0.0):
    """Points round a circle in outward_rect's winding (so walls face out)."""
    out = []
    for i in range(segs):
        t = 2 * math.pi * (i + phase) / segs
        out.append((cx + r * math.cos(t), cz - r * math.sin(t)))
    return out


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

    # -- prop building blocks (Stage 3) --------------------------------------------------------

    def box(self, x0, y0, z0, x1, y1, z1, strip, top_strip=None, bottom=False, chamfer=0.0,
            v_range=(0.0, 1.0)):
        """An axis-aligned box, its vertical corners optionally chamfered; sides in `strip`
        (V over the height), the top (and optional bottom) in `top_strip` (default the same)."""
        hx, hz = (x1 - x0) / 2, (z1 - z0) / 2
        c = min(chamfer, hx * 0.9, hz * 0.9)
        poly = chamfer_rect((x0 + x1) / 2, (z0 + z1) / 2, hx, hz, c) if c > 0 else outward_rect(x0, z0, x1, z1)
        self.prism(poly, y0, y1, strip, top=True, bottom=bottom, top_strip=top_strip or strip, v_range=v_range)

    def frustum(self, cx, cz, r0, r1, y0, y1, segs, strip, top=True, bottom=False, top_strip=None,
                v_range=(0.0, 1.0), cy=0.0):
        """A vertical frustum (a cylinder when r0 == r1, a cone when r1 == 0) round (cx, cz),
        radius r0 at y0 and r1 at y1, `segs` sides; U round the bottom rim in studs."""
        lo = _circle(cx, cz, r0, segs)
        hi = _circle(cx, cz, max(r1, 1e-6), segs)
        va, vb = trim_v(strip, v_range[0]), trim_v(strip, v_range[1])
        step = 2 * math.pi * r0 / segs
        for i in range(segs):
            j = (i + 1) % segs
            ua, ub = trim_u(strip, i * step), trim_u(strip, (i + 1) * step)
            if r1 <= 1e-6:
                self.face([(lo[i][0], y0, lo[i][1]), (lo[j][0], y0, lo[j][1]), (cx, y1, cz)],
                          [(ua, va), (ub, va), ((ua + ub) / 2, vb)])
            else:
                self.face([(lo[i][0], y0, lo[i][1]), (lo[j][0], y0, lo[j][1]), (hi[j][0], y1, hi[j][1]),
                           (hi[i][0], y1, hi[i][1])], [(ua, va), (ub, va), (ub, vb), (ua, vb)])
        if top and r1 > 1e-6:
            self.flat(hi, y1, top_strip or strip, up=True)
        if bottom:
            self.flat(lo, y0, top_strip or strip, up=False)

    def cylinder(self, cx, cz, r, y0, y1, segs, strip, top=True, bottom=False, top_strip=None,
                 v_range=(0.0, 1.0)):
        self.frustum(cx, cz, r, r, y0, y1, segs, strip, top, bottom, top_strip, v_range)

    def sphere(self, cx, cy, cz, r, segs, rings, strip, squash=1.0):
        """A low-poly UV sphere (squash scales its height); V runs from the bottom of the strip
        at the south pole to its top at the north pole."""
        def ring(k):
            a = math.pi * k / rings - math.pi / 2
            return r * math.cos(a), cy + r * squash * math.sin(a)
        step = 2 * math.pi * r / segs
        for k in range(rings):
            (ra, ya), (rb_, yb) = ring(k), ring(k + 1)
            lo, hi = _circle(cx, cz, max(ra, 1e-6), segs), _circle(cx, cz, max(rb_, 1e-6), segs)
            va, vb = trim_v(strip, k / rings), trim_v(strip, (k + 1) / rings)
            for i in range(segs):
                j = (i + 1) % segs
                ua, ub = trim_u(strip, i * step), trim_u(strip, (i + 1) * step)
                if k == 0:
                    self.face([(cx, ya, cz), (hi[j][0], yb, hi[j][1]), (hi[i][0], yb, hi[i][1])],
                              [((ua + ub) / 2, va), (ub, vb), (ua, vb)])
                elif k == rings - 1:
                    self.face([(lo[i][0], ya, lo[i][1]), (lo[j][0], ya, lo[j][1]), (cx, yb, cz)],
                              [(ua, va), (ub, va), ((ua + ub) / 2, vb)])
                else:
                    self.face([(lo[i][0], ya, lo[i][1]), (lo[j][0], ya, lo[j][1]), (hi[j][0], yb, hi[j][1]),
                               (hi[i][0], yb, hi[i][1])], [(ua, va), (ub, va), (ub, vb), (ua, vb)])

    def add(self, other, rot=(0.0, 0.0, 0.0), offset=(0.0, 0.0, 0.0), scale=1.0):
        """Append another mesh: scaled (uniform, positive), turned by CFrame.Angles(*rot)
        (degrees) about its own origin, then moved by offset. Windings keep."""
        m = angles(*rot)
        base = len(self.verts)
        for x, y, z in other.verts:
            x, y, z = x * scale, y * scale, z * scale
            self.verts.append((m[0][0] * x + m[0][1] * y + m[0][2] * z + offset[0],
                               m[1][0] * x + m[1][1] * y + m[1][2] * z + offset[1],
                               m[2][0] * x + m[2][1] * y + m[2][2] * z + offset[2]))
        for idx, uvs in other.faces:
            self.faces.append((tuple(i + base for i in idx), list(uvs)))
        return self

    def bounds(self):
        xs, ys, zs = zip(*self.verts) if self.verts else ((0,), (0,), (0,))
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


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
