"""Verity v2 (the designer's second rework round, 2026-10-08): the evil Verity ball.

The monster model never made it into the game, so Verity stays a ball: at the first contact the
yellow smiley cue ball turns evil, swells up and eats the ball it hit. This is that evil ball:
a yellow ball split at the equator into two jaws hinged at the back (a toothy chomper crossed
with an evil smiley), glowing angry eyes under thick brows, rows of sharp teeth, a dark maroon
mouth and a tongue. Original: no character's design is copied.

Axes as catchball.py: unit radius (the shell's outer radius is 1.0), front = Blender -Y, up =
+Z, the hinge at the back (+Y). Roblox: Blender +Y arrives as Roblox +Z and +Z (up) as Roblox
+Y, so the front (-Y) is Roblox -Z, the LookVector of an unturned part (STUDIO_NOTES).

Objects (one shared material and one small atlas texture, so each object is one MeshPart; every
object's origin is the hinge pin H):

  VerityTop     the upper jaw: the shell (z >= 0), warm yellow outside (a little deeper toward
                the bottom), the dark maroon roof inside, a dark lip on the seam, a gum ring
                just inside it with the upper teeth hanging from its front (about 200 degrees of
                the rim, the longest at the front, none near the hinge), the two eye sockets
                (dark rings standing a little proud, so the eyes sit recessed in them) and the
                thick black brows slanting down toward the middle.
  VerityBottom  the lower jaw: the shell (z <= 0), yellow outside, maroon inside, the lip and a
                gum ring with the lower teeth standing up inside the upper row (they interleave
                without touching), and the tongue lying in the bowl.
  VerityEyes    the two angry eyes in the sockets, one flat red (Roblox: make it Neon so they
                glow). Turned with VerityTop.
  J_Hinge       a tiny cube at H (the importer may not keep object origins: read this one).

The jaw opens by turning VerityTop (and VerityEyes with it) about the X axis through H (Roblox:
about the X axis through the hinge, the front edge rising). The poses checked in the renders:
shut (0 degrees: nothing inside pokes out), the grin at rest (10 degrees: the two rows of teeth
show interleaved) and the gape (70 degrees: the maroon mouth, the tongue and both rows).

Images (assets/abilities/VerityEvil/): textures/verity_evil_atlas.png, the colour atlas of the
model (embedded in the .glb): flat cells in the top rows, three vertical gradient strips (the
yellow outside by latitude, the inside by depth, the teeth from the gum to the tip) and the
tongue (a groove down its middle) in the bottom-right quarter.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/verity_evil.py
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("VerityEvil")

R_OUT = 1.0
R_IN = 0.955
SEGS = 64
H = Vector((0.0, 1.035, 0.0))  # the hinge pin's axis point (the pivot), as catchball.py
FRONT = -math.pi / 2  # the longitude of the front (-Y)
# A thin dark band on the outside along the seam (radians of latitude on each jaw), so the
# mouth still reads as a mouth when it shuts on a chomp.
SEAM_BAND = 0.03

# The jaw angles the renders check (degrees, the front edge rising).
SHUT, GRIN, GAPE = 0.0, 10.0, 70.0

# ------------------------------------------------------------------------------------------
# The atlas: 256 x 256. Flat cells (32 px) along the top row; three vertical gradient strips
# from row STRIP_Y0 down; the tongue in the bottom-right quarter.
# ------------------------------------------------------------------------------------------

ATLAS = 256
CELL = 32
CELLS = {  # name: column on the top row
    "brow": 0,
    "socket": 1,
    "gum": 2,
    "eye": 3,
    "lip": 4,
}
COLOURS = {
    "brow": "120D0C",
    "socket": "2A0A0D",
    "gum": "9C2338",
    "eye": "FF2A14",
    "lip": "4E0B16",
}
STRIP_Y0 = 40
STRIPS = {  # name: (x0, width) in px; each runs from row STRIP_Y0 to the bottom
    "yellow": (0, 16),
    "inside": (16, 16),
    "tooth": (32, 16),
}
# Each strip's colour stops (t = 0 at STRIP_Y0, 1 at the bottom).
GRADIENTS = {
    # The outside by latitude: the top pole, the face's warm yellow (the smiley's FFD21F at the
    # equator), a deeper orange-yellow toward the bottom pole.
    "yellow": [(0.0, "FFE24D"), (0.35, "FFD82E"), (0.5, "FFD21F"), (0.75, "F5B814"), (1.0, "D9900B")],
    # The inside by depth: red at the lip, a deep maroon at the bottom of the bowl (never black:
    # it must read as a mouth, not a hole).
    "inside": [(0.0, "8E1C2E"), (0.3, "6A1220"), (1.0, "3A0710")],
    # The teeth: a warm ivory at the gum to a clean bright white at the tip.
    "tooth": [(0.0, "D9C9A3"), (0.35, "F2E9D2"), (1.0, "FFFEF8")],
}
TONGUE_BOX = (0.5, 0.0, 0.5, 0.5)  # u0, v0, du, dv (UV space, v up): the bottom-right quarter


def srgb(hexstr):
    return np.array([int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def gradient(stops, t):
    """Colour at t (0..1, an array) along the stops."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        a, b = srgb(c0), srgb(c1)
        m = (t >= t0) & (t <= t1)
        k = ((t - t0) / max(t1 - t0, 1e-9))[..., None]
        out[m] = (a * (1 - k) + b * k)[m]
    return out


def atlas_image():
    img = np.zeros((ATLAS, ATLAS, 4))
    img[..., 3] = 1.0
    img[..., 0:3] = srgb(COLOURS["lip"])
    for name, cx in CELLS.items():
        img[0:CELL, cx * CELL:(cx + 1) * CELL, 0:3] = srgb(COLOURS[name])
    rows = ATLAS - STRIP_Y0
    t = (np.arange(rows) + 0.5) / rows
    for name, (x0, w) in STRIPS.items():
        col = gradient(GRADIENTS[name], t)
        img[STRIP_Y0:, x0:x0 + w, 0:3] = col[:, None, :]
    # The tongue: pink-red, darker toward its edges, a groove down the middle (along V) that
    # fades out toward the tip and a soft highlight off-centre.
    n = ATLAS // 2
    c = (np.arange(n) + 0.5) / n * 2 - 1
    x, y = np.meshgrid(c, c)  # x across the tongue, y along it (row 0 = the image top = the back)
    base = srgb("E0566C")
    edge = srgb("A82A42")
    col = base * (1 - np.clip(np.abs(x), 0, 1)[..., None] ** 2) + edge * (np.clip(np.abs(x), 0, 1)[..., None] ** 2)
    groove = np.exp(-(x / 0.09) ** 2) * np.clip(0.6 - 0.5 * y, 0.2, 1) * 0.75
    col = col * (1 - groove[..., None]) + srgb("7A1428") * groove[..., None]
    hi = np.exp(-(((x + 0.35) / 0.18) ** 2 + ((y + 0.1) / 0.35) ** 2)) * 0.3
    col = col * (1 - hi[..., None]) + srgb("FFB3BF") * hi[..., None]
    img[n:, n:, 0:3] = col
    return common.image_from_array("VerityEvilAtlas", img,
                                   os.path.join(OUT, "textures", "verity_evil_atlas.png"))


def cell_uv(name):
    cx = CELLS[name]
    return (cx + 0.5) * CELL / ATLAS, 1 - 0.5 * CELL / ATLAS


def paint(uvl, face, name):
    """A face's loops get a small spread of UVs inside the flat colour cell `name`."""
    u, v = cell_uv(name)
    k = len(face.loops)
    for i, loop in enumerate(face.loops):
        a = 2 * math.pi * i / k
        loop[uvl].uv = (u + 0.012 * math.cos(a), v + 0.012 * math.sin(a))


def strip_uv(name, t, jitter=0.0):
    x0, w = STRIPS[name]
    t = min(max(t, 0.0), 1.0)
    rows = ATLAS - STRIP_Y0
    row = STRIP_Y0 + 1 + t * (rows - 2)
    return (x0 + w / 2 + jitter) / ATLAS, 1 - row / ATLAS


def paint_strip(uvl, face, name, tfun):
    """Each loop's UV down strip `name` at tfun(vertex position)."""
    k = len(face.loops)
    for i, loop in enumerate(face.loops):
        loop[uvl].uv = strip_uv(name, tfun(loop.vert.co), 3.0 * math.cos(2 * math.pi * i / k))


# ------------------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------------------

def to_object(name, bm):
    """A mesh object from `bm` (built in world coordinates, each face's smoothness set) with its
    origin at H. Every part is a closed solid, so recalc_face_normals points faces outward."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for v in bm.verts:
        v.co -= H
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    obj.location = H
    bpy.context.scene.collection.objects.link(obj)
    return obj


def sph(lat, lon, r):
    return Vector((r * math.cos(lat) * math.cos(lon), r * math.cos(lat) * math.sin(lon), r * math.sin(lat)))


def lat_of(co):
    return math.asin(max(-1.0, min(1.0, co.z / max(co.length, 1e-9))))


def shell(bm, uvl, lats):
    """A closed hemispherical shell over the increasing latitudes `lats` (radians; one end at a
    pole, the other at the seam, latitude 0): outer radius R_OUT painted down the yellow strip
    by latitude (the lip's dark within SEAM_BAND of the seam), inner R_IN down the inside strip
    by depth, the flat lip at the seam."""
    rings = len(lats) - 1

    def grid(r):
        rows = []
        for lat in lats:
            if abs(abs(lat) - math.pi / 2) < 1e-6:
                rows.append([bm.verts.new(sph(lat, 0, r))] * SEGS)
            else:
                rows.append([bm.verts.new(sph(lat, 2 * math.pi * i / SEGS, r)) for i in range(SEGS)])
        return rows

    def outside_t(co):
        return (math.pi / 2 - lat_of(co)) / math.pi

    def inside_t(co):
        return abs(lat_of(co)) / (math.pi / 2)

    outer, inner = grid(R_OUT), grid(R_IN)
    for rows, strip, tfun in ((outer, "yellow", outside_t), (inner, "inside", inside_t)):
        for j in range(rings):
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
                f.smooth = True
                if strip == "yellow" and max(abs(lats[j]), abs(lats[j + 1])) <= SEAM_BAND + 1e-9:
                    paint(uvl, f, "lip")
                else:
                    paint_strip(uvl, f, strip, tfun)
    seam = 0 if abs(lats[0]) < 1e-6 else rings
    for i in range(SEGS):
        i2 = (i + 1) % SEGS
        f = bm.faces.new((outer[seam][i], outer[seam][i2], inner[seam][i2], inner[seam][i]))
        f.smooth = False
        paint(uvl, f, "lip")


def gum_ring(bm, uvl, r0, r1, z0, z1):
    """A flat closed ring (its cross-section a rectangle swept round Z): radii r0..r1, heights
    z0..z1. It hugs the shell's inside at the seam; the teeth stand on it."""
    corners = ((r0, z0), (r1, z0), (r1, z1), (r0, z1))
    rows = []
    for r, z in corners:
        rows.append([bm.verts.new((r * math.cos(2 * math.pi * i / SEGS),
                                   r * math.sin(2 * math.pi * i / SEGS), z)) for i in range(SEGS)])
    for k in range(4):
        a, b = rows[k], rows[(k + 1) % 4]
        for i in range(SEGS):
            i2 = (i + 1) % SEGS
            f = bm.faces.new((a[i], a[i2], b[i2], b[i]))
            f.smooth = k % 2 == 1  # the curved walls smooth, the flat faces crisp
            paint(uvl, f, "gum")


def tooth(bm, uvl, lon, half, r_out, r_in, r_tip, z_base, z_tip):
    """A sharp tooth: a pyramid on an arc-shaped base (radii r_in..r_out, longitudes lon +-
    half) at z_base, its point at radius r_tip, z_tip. Painted down the tooth strip."""
    def p(r, a, z):
        return Vector((r * math.cos(a), r * math.sin(a), z))
    b = [bm.verts.new(p(r_out, lon - half, z_base)), bm.verts.new(p(r_out, lon + half, z_base)),
         bm.verts.new(p(r_in, lon + half, z_base)), bm.verts.new(p(r_in, lon - half, z_base))]
    tip = bm.verts.new(p(r_tip, lon, z_tip))
    span = abs(z_tip - z_base)

    def t_of(co):
        return abs(co.z - z_base) / span

    for face in ((b[0], b[1], b[2], b[3]), (b[0], b[1], tip), (b[1], b[2], tip),
                 (b[2], b[3], tip), (b[3], b[0], tip)):
        f = bm.faces.new(face)
        f.smooth = False
        paint_strip(uvl, f, "tooth", t_of)


def teeth_row(bm, uvl, count, spacing_deg, half_deg, r_out, r_in, r_tip, lengths, upward, offset_deg=0.0):
    """`count` teeth centred on the front, `spacing_deg` apart; lengths(k_from_centre) gives
    each one's length (the front ones longest)."""
    mid = (count - 1) / 2
    for k in range(count):
        lon = FRONT + math.radians((k - mid) * spacing_deg + offset_deg)
        length = lengths(abs(k - mid) / max(mid, 1e-9))
        z_tip = length if upward else -length
        tooth(bm, uvl, lon, math.radians(half_deg), r_out, r_in, r_tip, 0.0, z_tip)


# The face, drawn in its own front orthographic view (x across, z up; unit = the radius) and
# laid on the sphere along its normals (sp), so every slab has an even thickness.

def sp(x, z, r):
    s = x * x + z * z
    n = Vector((x, -math.sqrt(max(1.0 - s, 1e-6)), z))
    return n.normalized() * r


EYE_C = (0.30, 0.38)  # the right eye's ellipse centre (x > 0; the left is its mirror)
EYE_AB = (0.235, 0.185)  # its half-width and half-height
CUT_P = (0.30, 0.45)  # the angry lid's line passes through here...
CUT_S = 0.4  # ...rising outward at this slope (the inner corner low)
EYE_IN = (0.31, 0.34)  # a point inside the eye the outlines are cast from
OUTLINE_N = 72
SOCKET_W = 0.045  # the dark socket ring round each eye
BROW_GAP = 0.02  # from the socket's top edge to the brow
BROW_IN, BROW_OUT = 0.03, 0.54  # the brow's ends (x)
BROW_TH_IN, BROW_TH_OUT = 0.17, 0.12  # its thickness at each end


def eye_rho(ang, grow=0.0):
    """Distance from EYE_IN to the eye's edge (grown by `grow`) along angle `ang`."""
    cx, cz = EYE_IN
    dx, dz = math.cos(ang), math.sin(ang)
    ex, ez = EYE_C
    a, b = EYE_AB[0] + grow, EYE_AB[1] + grow
    px, pz = (cx - ex) / a, (cz - ez) / b
    qx, qz = dx / a, dz / b
    A = qx * qx + qz * qz
    B = 2 * (px * qx + pz * qz)
    C = px * px + pz * pz - 1
    t_e = (-B + math.sqrt(B * B - 4 * A * C)) / (2 * A)
    lx, lz = CUT_P
    lz += grow * math.sqrt(1 + CUT_S * CUT_S)  # the line moved out by `grow` along its normal
    den = dz - CUT_S * dx
    t_l = math.inf
    if den > 1e-9:
        t_l = (lz + CUT_S * (cx - lx) - cz) / den
    return min(t_e, t_l)


def eye_outline(grow=0.0, mirror=False):
    cx, cz = EYE_IN
    pts = []
    for k in range(OUTLINE_N):
        ang = 2 * math.pi * k / OUTLINE_N
        r = eye_rho(ang, grow)
        pts.append((cx + r * math.cos(ang), cz + r * math.sin(ang)))
    if mirror:
        pts = [(-x, z) for x, z in pts]
    return pts


def brow_outline(mirror=False):
    lx, lz = CUT_P
    norm = 1 / math.sqrt(1 + CUT_S * CUT_S)
    nx, nz = -CUT_S * norm, norm  # the line's upward normal

    def on_line(x, extra):
        z = lz + CUT_S * (x - lx)
        return (x + nx * extra, z + nz * extra)

    lo = SOCKET_W + BROW_GAP
    pts = [on_line(BROW_IN, lo), on_line(BROW_OUT, lo),
           on_line(BROW_OUT + 0.025, lo + BROW_TH_OUT * 0.5),
           on_line(BROW_OUT, lo + BROW_TH_OUT), on_line(BROW_IN, lo + BROW_TH_IN)]
    if mirror:
        pts = [(-x, z) for x, z in reversed(pts)]
    return pts


def fan_slab(bm, uvl, outline, r_back, r_front, front_cell, side_cell=None, centre=None):
    """A slab on the sphere: the convex `outline` laid at r_front (a fan from its centre) and at
    r_back, closed by side walls."""
    if centre is None:
        centre = (sum(p[0] for p in outline) / len(outline), sum(p[1] for p in outline) / len(outline))
    fc = bm.verts.new(sp(centre[0], centre[1], r_front))
    bc = bm.verts.new(sp(centre[0], centre[1], r_back))
    fr = [bm.verts.new(sp(x, z, r_front)) for x, z in outline]
    br = [bm.verts.new(sp(x, z, r_back)) for x, z in outline]
    n = len(outline)
    for i in range(n):
        i2 = (i + 1) % n
        f = bm.faces.new((fc, fr[i], fr[i2]))
        f.smooth = True
        paint(uvl, f, front_cell)
        f = bm.faces.new((bc, br[i2], br[i]))
        f.smooth = True
        paint(uvl, f, side_cell or front_cell)
        f = bm.faces.new((fr[i], br[i], br[i2], fr[i2]))
        f.smooth = False
        paint(uvl, f, side_cell or front_cell)


def ring_slab(bm, uvl, inner, outer, r_back, r_front, cell):
    """A ring on the sphere between two outlines with the same number of points."""
    n = len(inner)
    fi = [bm.verts.new(sp(x, z, r_front)) for x, z in inner]
    fo = [bm.verts.new(sp(x, z, r_front)) for x, z in outer]
    bi = [bm.verts.new(sp(x, z, r_back)) for x, z in inner]
    bo = [bm.verts.new(sp(x, z, r_back)) for x, z in outer]
    for i in range(n):
        i2 = (i + 1) % n
        for quad, smooth in (((fi[i], fo[i], fo[i2], fi[i2]), True), ((bi[i], bi[i2], bo[i2], bo[i]), True),
                             ((fi[i], fi[i2], bi[i2], bi[i]), False), ((fo[i], bo[i], bo[i2], fo[i2]), False)):
            f = bm.faces.new(quad)
            f.smooth = smooth
            paint(uvl, f, cell)


# The rows of teeth. The upper row hangs from the outer part of the top gum, the lower row
# stands on the inner part of the bottom gum, half a spacing round, so they interleave with a
# gap between the rows (r 0.87 against 0.83) and never touch, shut or open.
TOP_TEETH = dict(count=11, spacing_deg=19.0, half_deg=8.2, r_out=0.95, r_in=0.87, r_tip=0.905)
BOTTOM_TEETH = dict(count=10, spacing_deg=19.0, half_deg=8.0, r_out=0.83, r_in=0.75, r_tip=0.79)


def top_length(u):
    """u: 0 at the front tooth, 1 at the row's ends. The front fangs longest."""
    return 0.13 + 0.15 * (1 - u * u)


def bottom_length(u):
    return 0.12 + 0.11 * (1 - u * u)


def build_top(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    shell(bm, uvl, [0.0, SEAM_BAND] + [(math.pi / 2) * j / 18 for j in range(1, 19)])
    gum_ring(bm, uvl, 0.86, 0.958, 0.0, 0.035)
    teeth_row(bm, uvl, lengths=top_length, upward=False, **TOP_TEETH)
    for mirror in (False, True):
        ring_slab(bm, uvl, eye_outline(0.0, mirror), eye_outline(SOCKET_W, mirror), 0.985, 1.04, "socket")
        fan_slab(bm, uvl, brow_outline(mirror), 0.985, 1.05, "brow")
    obj = to_object("VerityTop", bm)
    obj.data.materials.append(material)
    return obj


def build_eyes(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    for mirror in (False, True):
        cx, cz = EYE_IN
        fan_slab(bm, uvl, eye_outline(0.0, mirror), 0.98, 1.016, "eye",
                 centre=(-cx if mirror else cx, cz))
    obj = to_object("VerityEyes", bm)
    obj.data.materials.append(material)
    return obj


def tongue(bm, uvl):
    """The tongue lying in the bowl: a flattened ellipsoid, its tip toward the front, curling up
    a little; UVs projected from above into the tongue's quarter of the atlas."""
    res = bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    verts = res["verts"]
    cx, cy, cz = 0.0, 0.06, -0.46
    ax, ay, az = 0.34, 0.58, 0.085
    for v in verts:
        x, y, z = v.co.x * ax, v.co.y * ay, v.co.z * az
        # The front (tip) curls up toward the teeth; the back sinks into the throat.
        along = -y / ay  # 1 at the tip, -1 at the back
        front = max(0.0, along - 0.3) / 0.7
        z += 0.1 * front * front - 0.06 * max(0.0, -along) ** 2
        v.co = Vector((cx + x, cy + y, cz + z))
    u0, v0, du, dv = TONGUE_BOX
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.smooth = True
        for loop in f.loops:
            co = loop.vert.co
            u = 0.5 + 0.5 * (co.x - cx) / ax
            w = 0.5 + 0.5 * (co.y - cy) / ay  # 0 at the tip (front), 1 at the back
            loop[uvl].uv = (u0 + du * min(max(u, 0.01), 0.99), v0 + dv * min(max(w, 0.01), 0.99))


def build_bottom(material):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    shell(bm, uvl, [-(math.pi / 2) * (18 - j) / 18 for j in range(18)] + [-SEAM_BAND, 0.0])
    gum_ring(bm, uvl, 0.74, 0.958, -0.035, 0.0)
    teeth_row(bm, uvl, lengths=bottom_length, upward=True, **BOTTOM_TEETH)
    tongue(bm, uvl)
    obj = to_object("VerityBottom", bm)
    obj.data.materials.append(material)
    return obj


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
    atlas = atlas_image()
    m = common.image_material("VerityEvilMat", atlas, roughness=0.2)
    parts = [build_top(m), build_bottom(m), build_eyes(m)]
    return parts, marker("J_Hinge", H)


# ------------------------------------------------------------------------------------------
# Previews
# ------------------------------------------------------------------------------------------

def set_jaw(degrees):
    """Open the jaw: VerityTop and VerityEyes turned about X through H, the front rising."""
    for name in ("VerityTop", "VerityEyes"):
        bpy.data.objects[name].rotation_euler = (math.radians(-degrees), 0, 0)


def preview_lights():
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-20))
    bpy.context.scene.collection.objects.link(sun)
    fill = bpy.data.objects.new("PreviewFill", bpy.data.lights.new("PreviewFill", "SUN"))
    fill.data.energy = 1.1
    fill.rotation_euler = (math.radians(120), 0, math.radians(30))
    bpy.context.scene.collection.objects.link(fill)


def glow_eyes_for_preview(material):
    """The previews show the eyes as Roblox's Neon will: a glowing red (preview only; the .glb
    keeps the one shared material)."""
    glow = bpy.data.materials.new("PreviewEyeGlow")
    glow.use_nodes = True
    bsdf = next(n for n in glow.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (1.0, 0.02, 0.01, 1)
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.03, 0.01, 1)
    bsdf.inputs["Emission Strength"].default_value = 1.6
    eyes = bpy.data.objects["VerityEyes"]
    eyes.data.materials.clear()
    eyes.data.materials.append(glow)
    return lambda: (eyes.data.materials.clear(), eyes.data.materials.append(material))


def render(name, jaw, elevation, azimuth, distance=4.4, size=512):
    set_jaw(jaw)
    # Roblox shows colours as they are: no filmic curve on the previews either.
    try:
        bpy.context.scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    common.render_preview(os.path.join(OUT, "renders", name + ".png"), size=size, distance=distance,
                          elevation=elevation, azimuth=azimuth, background=(0.1, 0.12, 0.11, 1),
                          target=(0, 0, 0.25 if jaw > 30 else 0.0))


def build():
    common.clear_scene()
    parts, hinge = build_model()
    objects = parts + [hinge]
    print("VerityEvil triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 3) for v in o.location), tuple(round(v, 3) for v in o.dimensions))
    set_jaw(SHUT)
    common.export_glb(os.path.join(OUT, "verity_evil.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "verity_evil.blend"))
    preview_lights()
    restore = glow_eyes_for_preview(parts[0].data.materials[0])
    only = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else None
    shots = [
        ("grin_front34", GRIN, 18, 28, 4.4),
        ("grin_high", GRIN, 55, 8, 4.4),
        ("grin14_high", 14.0, 55, 8, 4.4),
        ("gape_front34", GAPE, 24, 28, 5.0),
        ("gape_high", GAPE, 55, 8, 5.0),
        ("shut_front34", SHUT, 18, 28, 4.4),
        ("shut_side", SHUT, 5, 90, 4.4),
        ("grin_back", GRIN, 20, 160, 4.4),
    ]
    for name, jaw, el, az, dist in shots:
        if only is None or name in only:
            render(name, jaw, el, az, dist)
    if only is None or "phone" in only:
        render("grin_high_phone", GRIN, 55, 8, 4.4, size=96)
        render("gape_high_phone", GAPE, 55, 8, 5.0, size=96)
    restore()
    set_jaw(SHUT)


if __name__ == "__main__":
    build()
