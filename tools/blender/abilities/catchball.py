"""Catch-a-Ball (ABILITIES_REWORK_PLAN step 3): the black and white catch ball the hit ball is
caught in, and its effect images.

Black over white, nothing at the seam but the edge between them, and a small 8-ball for a
button (the designer, 2026-10-09: "get rid of the iconic like black lines that distinctively
make it look like a pokeball ... the bottom is still white, but the iconic red is now black";
"for like a button make it an 8 ball"); the back carries a notched hinge (alternating knuckles
on a pin).

Axes: unit radius (the shell's outer radius is 1.0), front = Blender -Y, up = +Z, the hinge
at the back (+Y). Roblox: Blender +Y arrives as Roblox +Z and +Z (up) as Roblox +Y, so the
front (-Y) is Roblox -Z, the LookVector of an unturned part (STUDIO_NOTES).

Objects (one shared material and one small atlas texture, so each object is one MeshPart):

  CatchTop     the upper shell (z >= 0), black outside, dark inside; carries the two lid
               knuckles of the hinge. Origin at the hinge pin H.
  CatchBottom  the lower shell (z <= -LIP), white outside, dark inside. Origin at H.
  CatchBand    the rest of the lower shell (-LIP <= z <= 0), white like it (no band shows),
               plus the hinge's three base knuckles, the pin and a notched (zig-zag) leaf plate
               at the back. Origin at H.
  CatchButton  the 8-ball at the front, centred on the seam and standing out of the shell:
               black, its front a white circle with a black 8 (the atlas's bottom-left
               quarter, projected from the front). Origin at H.
  CatchInner   the dark disc inside the bottom half just under the seam (dark with a faint red
               ring and a small light centre), seen when the lid is open. Origin at H.
  J_Hinge      a tiny cube at H (the importer may not keep object origins: read this one).

The lid opens by turning CatchTop about the X axis through H (Roblox: about the X axis through
the hinge, the front edge rising).

Images (assets/abilities/CatchABall/, RGBA, numpy):
  textures/catch_atlas.png  the colour atlas of the model (embedded in the .glb).
  CatchGlow.png   256 x 256, a soft white radial glow on clear.
  CatchStar.png   128 x 128, a white four-point sparkle star on clear.
  CatchBeam.png   256 x 64, a red-white energy beam, clear at the top and bottom edges, tiling
                  along U (its wobble uses whole periods across the tile).

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/catchball.py
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("CatchABall")

R_OUT = 1.0
R_IN = 0.955
LIP = 0.085  # the lower shell's top part (CatchBand) below the seam, in radians
BUTTON_R = 0.16  # the 8-ball button's radius
BUTTON_Y = -0.94  # its centre (Blender Y; the front is -Y): it stands BUTTON_R + 0.94 - 1 out
SEGS = 72
H = Vector((0.0, 1.035, 0.0))  # the hinge pin's axis point (the pivot)

# ------------------------------------------------------------------------------------------
# The atlas: 256 x 256, an 8 x 8 grid of flat colour cells in the top half, a radial disc for
# the inner disc in the bottom-right quarter.
# ------------------------------------------------------------------------------------------

ATLAS = 256
CELLS = {  # name: (column, row) in the 8 x 8 grid, row 0 at the image top
    "red": (0, 0),
    "white": (1, 0),
    "black": (2, 0),
    "inside": (3, 0),
    "plate": (4, 0),
    "face": (5, 0),
    "ring": (6, 0),
    "metal": (7, 0),
}
COLOURS = {
    "red": "E3262E",
    "white": "F4F4F4",
    "black": "17171C",
    "inside": "2A2B33",
    "plate": "1E1F26",
    "face": "F7F7F7",
    "ring": "B8BCC6",
    "metal": "3A3C46",
}
DISC_BOX = (0.5, 0.0, 0.5, 0.5)  # u0, v0, du, dv (UV space, v up): the bottom-right quarter
EIGHT_BOX = (0.0, 0.0, 0.5, 0.5)  # the 8-ball's face: the bottom-left quarter


def srgb(hexstr):
    return np.array([int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def atlas_image():
    img = np.zeros((ATLAS, ATLAS, 4))
    img[..., 3] = 1.0
    img[..., 0:3] = srgb(COLOURS["inside"])
    cell = ATLAS // 8
    for name, (cx, cy) in CELLS.items():
        img[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell, 0:3] = srgb(COLOURS[name])
    # The inner disc, in the bottom-right quarter (rows 128..255, columns 128..255).
    n = ATLAS // 2
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.sqrt(x * x + y * y)
    dark = srgb("1A1B22")
    red = srgb("E3262E")
    col = np.broadcast_to(dark, (n, n, 3)).copy()
    ring = np.exp(-((r - 0.62) / 0.06) ** 2) * 0.8
    col = col * (1 - ring[..., None]) + red * ring[..., None]
    centre = np.clip(1 - (r - 0.12) / 0.03, 0, 1)
    col = col * (1 - centre[..., None]) + srgb("5A5C6A") * centre[..., None]
    col *= (1 - 0.35 * np.clip(r, 0, 1) ** 2)[..., None]  # darker toward the wall
    img[n:, n:, 0:3] = col
    # The 8-ball's face, in the bottom-left quarter: black, a white circle, a black 8 (two
    # stacked rings, the top one smaller). Up in the image is +Z on the ball.
    x, y = np.meshgrid(c, -c)

    def inside(dist, edge=0.02):
        return np.clip(0.5 - dist / edge, 0, 1)

    ball = srgb(COLOURS["black"])
    face = srgb("F4F4F4")
    white = inside(np.sqrt(x * x + y * y) - 0.6)
    eight = np.zeros_like(x)
    for cy, ro, ri in ((0.2, 0.19, 0.085), (-0.18, 0.23, 0.11)):
        r = np.sqrt(x * x + (y - cy) ** 2)
        eight = np.maximum(eight, inside(r - ro) * (1 - inside(r - ri)))
    col = np.broadcast_to(ball, (n, n, 3)).copy()
    col = col * (1 - white[..., None]) + face * white[..., None]
    col = col * (1 - eight[..., None]) + ball * eight[..., None]
    img[n:, :n, 0:3] = col
    return common.image_from_array("CatchAtlas", img, os.path.join(OUT, "textures", "catch_atlas.png"))


def cell_uv(name):
    cx, cy = CELLS[name]
    u = (cx + 0.5) / 8
    v = 1 - (cy + 0.5) / 8
    return u, v


def paint(bm, uvl, face, name):
    """Give a face's loops a small spread of UVs inside the colour cell `name`."""
    u, v = cell_uv(name)
    k = len(face.loops)
    for i, loop in enumerate(face.loops):
        a = 2 * math.pi * i / k
        loop[uvl].uv = (u + 0.015 * math.cos(a), v + 0.015 * math.sin(a))


# ------------------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------------------

def to_object(name, bm, material, smooth=True, recalc=True):
    """A mesh object from `bm` (built in world coordinates) with its origin at H. Every part
    but the inner disc is a closed solid, so recalc_face_normals points its faces outward."""
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co -= H
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = smooth
    if smooth:
        # The flat rims stay sharp, so they never bend the shell's shading into a bright line.
        me.set_sharp_from_angle(angle=math.radians(40))
    obj = bpy.data.objects.new(name, me)
    obj.location = H
    bpy.context.scene.collection.objects.link(obj)
    return obj


def sph(lat, lon, r):
    return Vector((r * math.cos(lat) * math.cos(lon), r * math.cos(lat) * math.sin(lon), r * math.sin(lat)))


def shell_band(bm, uvl, lats, outer_paint, inner_paint, rim0=None, rim1=None):
    """A closed ring-shaped shell over the increasing latitudes `lats` (radians; +-pi/2 closes
    at a pole), outer radius R_OUT and inner R_IN. outer_paint(lat_mid) -> cell name. rim0/rim1:
    the paint of the flat rim faces at the first/last latitude (None where it closes at a
    pole)."""
    rings = len(lats) - 1

    def grid(r):
        rows = []
        for lat in lats:
            if abs(abs(lat) - math.pi / 2) < 1e-6:
                rows.append([bm.verts.new(sph(lat, 0, r))] * SEGS)
            else:
                rows.append([bm.verts.new(sph(lat, 2 * math.pi * i / SEGS, r)) for i in range(SEGS)])
        return rows

    outer, inner = grid(R_OUT), grid(R_IN)
    for rows, painter in ((outer, outer_paint), (inner, lambda lat: inner_paint)):
        for j in range(rings):
            mid = (lats[j] + lats[j + 1]) / 2
            for i in range(SEGS):
                i2 = (i + 1) % SEGS
                quad = [rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]]
                uniq = []
                for v in quad:
                    if v not in uniq:
                        uniq.append(v)
                if len(uniq) < 3:
                    continue
                f = bm.faces.new(uniq)
                paint(bm, uvl, f, painter(mid))
    for j, rim in ((0, rim0), (rings, rim1)):
        if rim is None:
            continue
        for i in range(SEGS):
            i2 = (i + 1) % SEGS
            f = bm.faces.new((outer[j][i], outer[j][i2], inner[j][i2], inner[j][i]))
            paint(bm, uvl, f, rim)


def capsule_x(bm, uvl, x0, x1, radius, centre, name, sides=16):
    """A cylinder along X from x0 to x1 through `centre` (y, z), capped."""
    rows = []
    for x in (x0, x1):
        rows.append([bm.verts.new((x, centre[0] + radius * math.cos(2 * math.pi * i / sides),
                                   centre[1] + radius * math.sin(2 * math.pi * i / sides)))
                     for i in range(sides)])
    for i in range(sides):
        i2 = (i + 1) % sides
        paint(bm, uvl, bm.faces.new((rows[0][i], rows[0][i2], rows[1][i2], rows[1][i])), name)
    paint(bm, uvl, bm.faces.new(rows[0]), name)
    paint(bm, uvl, bm.faces.new(rows[1]), name)


def box(bm, uvl, lo, hi, name):
    xs, ys, zs = (lo[0], hi[0]), (lo[1], hi[1]), (lo[2], hi[2])
    v = {(a, b, c): bm.verts.new((xs[a], ys[b], zs[c])) for a in (0, 1) for b in (0, 1) for c in (0, 1)}
    for quad in (((0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)), ((0, 0, 1), (0, 1, 1), (1, 1, 1), (1, 0, 1)),
                 ((0, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0)), ((0, 1, 0), (1, 1, 0), (1, 1, 1), (0, 1, 1)),
                 ((0, 0, 0), (0, 1, 0), (0, 1, 1), (0, 0, 1)), ((1, 0, 0), (1, 0, 1), (1, 1, 1), (1, 1, 0))):
        paint(bm, uvl, bm.faces.new([v[q] for q in quad]), name)


def prism(bm, uvl, poly_xz, y0, y1, name):
    """A flat polygon in XZ (convex or a simple outline, counter-clockwise) extruded y0..y1."""
    front = [bm.verts.new((x, y0, z)) for x, z in poly_xz]
    back = [bm.verts.new((x, y1, z)) for x, z in poly_xz]
    paint(bm, uvl, bm.faces.new(front), name)
    paint(bm, uvl, bm.faces.new(list(reversed(back))), name)
    n = len(poly_xz)
    for i in range(n):
        i2 = (i + 1) % n
        paint(bm, uvl, bm.faces.new((front[i], back[i], back[i2], front[i2])), name)


KNUCKLE_R = 0.05
KNUCKLES = [(-0.25, -0.15), (-0.15, -0.05), (-0.05, 0.05), (0.05, 0.15), (0.15, 0.25)]


def build_top(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    lats = [(math.pi / 2) * j / 20 for j in range(21)]
    shell_band(bm, uvl, lats, lambda lat: "black", "inside", rim0="black")
    # The lid's two knuckles (the 2nd and 4th) with their leaves up into the shell.
    for k in (1, 3):
        x0, x1 = KNUCKLES[k]
        capsule_x(bm, uvl, x0 + 0.004, x1 - 0.004, KNUCKLE_R, (H.y, H.z), "black")
        box(bm, uvl, (x0 + 0.01, 0.93, 0.0), (x1 - 0.01, H.y, 0.11), "black")
    return to_object("CatchTop", bm, material)


def build_bottom(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    lats = [-math.pi / 2 + (math.pi / 2 - LIP) * j / 22 for j in range(23)]
    shell_band(bm, uvl, lats, lambda lat: "white", "inside", rim1="inside")
    return to_object("CatchBottom", bm, material)


def build_band(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    shell_band(bm, uvl, [-LIP, -LIP / 2, 0.0], lambda lat: "white", "inside", rim0="black",
               rim1="black")
    # The base knuckles (1st, 3rd, 5th) and the pin through all five.
    for k in (0, 2, 4):
        x0, x1 = KNUCKLES[k]
        capsule_x(bm, uvl, x0 + 0.004, x1 - 0.004, KNUCKLE_R, (H.y, H.z), "black")
    capsule_x(bm, uvl, -0.27, 0.27, 0.022, (H.y, H.z), "metal", sides=10)
    # The leaf plate below the knuckles: a notched, zig-zag top edge between them.
    outline = [(-0.25, -0.2), (0.25, -0.2)]
    for i in range(10, -1, -1):  # the top edge, right to left: teeth between the knuckles
        outline.append((-0.25 + 0.05 * i, -0.045 if i % 2 == 0 else -0.085))
    prism(bm, uvl, outline, 0.955, 1.03, "black")
    return to_object("CatchBand", bm, material)


def build_button(material):
    """The 8-ball: a UV sphere at the front, its front half mapped flat from the front onto the
    atlas's 8-ball face (the back half is inside the shell)."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    centre = Vector((0.0, BUTTON_Y, 0.0))
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=BUTTON_R)
    for v in bm.verts:
        v.co += centre
    u0, v0, du, dv = EIGHT_BOX
    for f in bm.faces:
        for loop in f.loops:
            p = loop.vert.co - centre
            loop[uvl].uv = (u0 + du * (0.5 + 0.5 * p.x / BUTTON_R), v0 + dv * (0.5 + 0.5 * p.z / BUTTON_R))
    return to_object("CatchButton", bm, material)


def build_inner(material):
    """Two fans (up and down) a hair apart, wound by hand: an open disc has no outside for
    recalc_face_normals to find."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    u0, v0, du, dv = DISC_BOX
    z = -0.02
    r = math.sqrt(R_IN * R_IN - z * z) - 0.005
    for zz, up in ((z, True), (z - 0.006, False)):
        centre = bm.verts.new((0, 0, zz))
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / SEGS), r * math.sin(2 * math.pi * i / SEGS), zz))
                for i in range(SEGS)]
        for i in range(SEGS):
            i2 = (i + 1) % SEGS
            f = bm.faces.new((centre, ring[i], ring[i2]) if up else (centre, ring[i2], ring[i]))
            for loop in f.loops:
                co = loop.vert.co
                loop[uvl].uv = (u0 + du * (0.5 + 0.5 * co.x / r), v0 + dv * (0.5 + 0.5 * co.y / r))
    return to_object("CatchInner", bm, material, smooth=False, recalc=False)


def marker(name, at):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=0.02)
    for v in bm.verts:
        v.co += Vector(at)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_model():
    """The five parts and the hinge marker (no images written but the atlas)."""
    atlas = atlas_image()
    m = common.image_material("CatchMat", atlas, roughness=0.18)
    parts = [build_top(m), build_bottom(m), build_band(m), build_button(m), build_inner(m)]
    return parts, marker("J_Hinge", H)


# ------------------------------------------------------------------------------------------
# Effect images
# ------------------------------------------------------------------------------------------

def save_png(name, rgba):
    return common.image_from_array(name, rgba, os.path.join(OUT, name + ".png"))


def glow_image(size=256):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, c)
    r = np.sqrt(x * x + y * y)
    a = np.clip(1 - r, 0, 1) ** 2.2
    a += 0.35 * np.exp(-(r / 0.18) ** 2)
    a = np.clip(a, 0, 1) * (r < 1)
    img = np.ones((size, size, 4))
    img[..., 3] = a
    return save_png("CatchGlow", img)


def star_image(size=128):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, c)
    # Four points: a thin diamond-ish cross whose arms taper to points at the edge.
    ax, ay = np.abs(x), np.abs(y)
    arm_h = np.clip(1 - ay / (0.16 * np.clip(1 - ax / 0.95, 0, 1) + 1e-6), 0, 1)
    arm_v = np.clip(1 - ax / (0.16 * np.clip(1 - ay / 0.95, 0, 1) + 1e-6), 0, 1)
    core = np.exp(-((x * x + y * y) / 0.025))
    halo = 0.35 * np.exp(-((x * x + y * y) / 0.12))
    a = np.clip(np.maximum(arm_h, arm_v) ** 0.7 + core + halo, 0, 1)
    img = np.ones((size, size, 4))
    img[..., 3] = a
    return save_png("CatchStar", img)


def beam_image(w=256, h=64):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, V = np.meshgrid(u, v)
    # The beam's centre line wobbles with whole periods across the tile, so it tiles in U.
    wob = 0.04 * np.sin(2 * math.pi * 2 * U) + 0.02 * np.sin(2 * math.pi * 5 * U + 1.3)
    d = np.abs(V - 0.5 - wob)
    width = 0.24 + 0.05 * np.sin(2 * math.pi * 3 * U + 0.7)
    core = np.exp(-(d / (width * 0.42)) ** 4)
    body = np.exp(-(d / width) ** 2.5)
    # Energy streaks running along the beam.
    streak = 0.5 + 0.5 * np.sin(2 * math.pi * (4 * U + 9 * (V - 0.5)) ) * np.sin(2 * math.pi * 7 * U + 2)
    body = body * (0.75 + 0.25 * streak)
    edge = np.clip(np.minimum(V, 1 - V) / 0.12, 0, 1)  # clear at the top and bottom edges
    red = np.array([0.89, 0.15, 0.18])
    white = np.array([1.0, 0.97, 0.97])
    col = red[None, None, :] * (1 - core[..., None]) + white * core[..., None]
    a = np.clip(body * 1.1 + core, 0, 1) * edge
    img = np.concatenate([col, a[..., None]], axis=-1)
    return save_png("CatchBeam", img)


def preview_on_black(name, folder=OUT):
    img = bpy.data.images.load(os.path.join(folder, name + ".png"))
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    bg = np.array([0.12, 0.35, 0.18])  # the cloth, roughly
    rgb = px[:, :, :3] * px[:, :, 3:4] + bg * (1 - px[:, :, 3:4])
    out = np.concatenate([rgb, np.ones((h, w, 1))], axis=2)
    prev = bpy.data.images.new(name + "_prev", width=w, height=h, alpha=True)
    prev.pixels.foreach_set(out.astype(np.float32).ravel())
    prev.filepath_raw = os.path.join(OUT, "renders", name + ".png")
    prev.file_format = "PNG"
    prev.save()


def build():
    common.clear_scene()
    parts, hinge = build_model()
    glow_image()
    star_image()
    beam_image()
    for name in ("CatchGlow", "CatchStar", "CatchBeam"):
        preview_on_black(name)
    objects = parts + [hinge]
    print("CatchABall triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 3) for v in o.location), tuple(round(v, 3) for v in o.dimensions))
    common.export_glb(os.path.join(OUT, "catchball.glb"), objects)
    # Previews: closed from the front three-quarter, from the back (the hinge), and open; a
    # key light and a neutral world (preview only, not exported).
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 3.5
    fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", "SUN"))
    fill.data.energy = 1.2
    fill.rotation_euler = (math.radians(120), 0, math.radians(30))
    bpy.context.scene.collection.objects.link(fill)
    sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-20))
    bpy.context.scene.collection.objects.link(sun)
    common.render_preview(os.path.join(OUT, "renders", "catch_front.png"), size=512, distance=4.2,
                          elevation=20, azimuth=30, background=(0.05, 0.12, 0.07, 1))
    common.render_preview(os.path.join(OUT, "renders", "catch_back.png"), size=512, distance=4.2,
                          elevation=20, azimuth=160, background=(0.05, 0.12, 0.07, 1))
    top = bpy.data.objects["CatchTop"]
    top.rotation_euler = (math.radians(-70), 0, 0)  # the front edge rises (about X through H)
    common.render_preview(os.path.join(OUT, "renders", "catch_open.png"), size=512, distance=4.6,
                          elevation=30, azimuth=25, background=(0.05, 0.12, 0.07, 1))
    top.rotation_euler = (0, 0, 0)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "catchball.blend"))


if __name__ == "__main__":
    build()
