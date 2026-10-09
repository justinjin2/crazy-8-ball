"""Verity v3 (the designer's second rework round, 2026-10-08, from their reference "use this
reference exactly"): the evil Verity ball as the creepy smiling face. It replaces the toothy
chomper of verity_evil.py (asset 131086829663737) with the same pieces, axes and hinge, so
src/client/VerityFx.luau plays it unchanged.

The face: a dark mustard-ochre skin (mottled, darker toward the bottom), two hollow eye sockets
(dimples sunk into the shell with near-black holes at their bottoms and soft shadowed rims), no
brows and no teeth, and a huge smile of a mouth: the jaws part along a smile curve (low at the
front, up at the corners), each edge lined with a thick band of lip in a pale pink-white with
fine ridges across it, a near-black dark maroon inside and a dark tongue. Original: no character's
design is copied; the reference was only looked at.

Axes as catchball.py and verity_evil.py: unit radius (the shell's outer radius is 1.0), front =
Blender -Y, up = +Z, the hinge at the back (+Y). Roblox: Blender +Y arrives as Roblox +Z and +Z
(up) as Roblox +Y, so the front (-Y) is Roblox -Z, the LookVector of an unturned part. The top
jaw's highest point and the bottom jaw's lowest are the poles (+-1), which VerityFx reads for the
ball's centre and radius.

Objects (one material and one 1024 x 1024 atlas, so each object is one MeshPart; every
object's origin is the hinge pin H):

  VerityTop     the upper jaw: the shell above the seam with the two socket dimples, the near-
                black roof inside, a dark rim on the seam and the upper lip along its front.
  VerityBottom  the lower jaw: the shell below the seam, the throat inside, the lower lip and the
                tongue lying in the bowl.
  VerityEyes    the two hollow eyes: near-black linings at the bottoms of the sockets, turned with
                VerityTop (no Neon and no light: they are holes).
  J_Hinge       a tiny cube at H (the importer may not keep object origins: read this one).

The seam is a smile: SEAM_FRONT high at the front, rising to SEAM_CORNER at the sides and back
down to 0 at the hinge. The jaw opens by turning VerityTop (and VerityEyes with it) about the X
axis through H, the front edge rising. At rest the mouth hangs open (REST degrees): the creepy
smile; GAPE opens it wide.

The atlas (assets/abilities/VerityEvil/textures/verity_creepy_atlas.png): the skin as an
equirectangular map of the outer shell in its top half (u = longitude from the back, v =
latitude), then the inside's gradient strip, the lips' ridge strip, the socket and seam cells
and the tongue in the bottom half.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/verity_creepy.py [-- render names]
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
NAME = "verity_creepy"

R_OUT = 1.0
R_IN = 0.955
SEGS = 128  # longitudes round the shells
H = Vector((0.0, 1.035, 0.0))  # the hinge pin's axis point (the pivot), as catchball.py
FRONT = -math.pi / 2  # the longitude of the front (-Y)

# The jaw angles the renders check (degrees, the front edge rising).
SHUT, REST, GAPE = 0.0, 35.0, 72.0

# The seam between the jaws (heights on the unit sphere): low at the front, up at the mouth's
# corners (the sides), back down to the hinge.
SEAM_FRONT, SEAM_CORNER = -0.45, 0.4

# ------------------------------------------------------------------------------------------
# The look (colours as hex, sRGB)
# ------------------------------------------------------------------------------------------

# The skin by latitude (the top pole .. the bottom pole): a dark mustard ochre, darker below.
SKIN = [(0.0, "BA9444"), (0.3, "B08A3E"), (0.5, "9E7A34"), (0.75, "7E5E28"), (1.0, "56401C")]
SOCKET_DARK = "120A06"  # the sockets' shadowed insides on the skin
EYE_HOLE = "060303"  # the holes themselves (VerityEyes)
INSIDE = [(0.0, "300A0E"), (0.15, "1A0508"), (1.0, "080203")]  # the mouth's inside by depth
SEAM = "2A0A0E"  # the cut rim between the outside and the inside
LIP_PALE = "E6C8C0"  # the lips' pale pink-white
LIP_LINE = "94525A"  # the fine lines between their ridges
LIP_DEEP = "3A0E14"  # their edge toward the mouth's inside
TONGUE = ("401419", "260A0F", "1A0508", "84424E")  # base, edges, the groove, the lit rim

# The eyes, in the face's front orthographic view (x across, z up; unit = the radius), on the
# top jaw as it stands shut: hollow sockets just above the smile.
EYE_X, EYE_Z = 0.4, 0.12
SOCKET_R = 0.22  # the dimple's radius (chord, in units)
SOCKET_DEPTH = 0.13  # how deep it sinks at its centre
HOLE_R = 0.1  # the dark hole at its bottom (VerityEyes' radius across)
SOCKET_SHADE_R = 0.28  # the skin darkens within this of the socket's centre

# The lips: bands along the seam's front, LIP_SPAN degrees each side of the front; LIP_H half
# their height (along the face) and LIP_T half their thickness at the front, tapering to LIP_END
# at their ends; centred LIP_C from the middle, hanging (the upper) or riding (the lower) LIP_SET
# of their height past the seam.
LIP_SPAN = 125.0
LIP_FADE = (95.0, 118.0)  # past the mouth's corners the lip darkens to its inner colour
LIP_H, LIP_T, LIP_END = 0.12, 0.05, 0.025
LIP_C = 0.96
LIP_SET = 0.75
LIP_SEGS = 110  # segments along each lip (a ridge each)
LIP_RING = 16  # sides round the band

# ------------------------------------------------------------------------------------------
# The atlas: 1024 x 1024. The top half is the skin (an equirectangular map of the outer shell);
# the bottom half holds strips and cells (pixel boxes: x0, y0, w, h, rows from the image top).
# ------------------------------------------------------------------------------------------

ATLAS = 1024
SKIN_ROWS = 512
BOX_INSIDE = (0, 520, 48, 496)
BOX_SEAM = (56, 520, 32, 32)
BOX_HOLE = (56, 560, 32, 32)
BOX_LIP = (96, 520, 104, 256)  # the first of LIP_VARIANTS ridge cells side by side
LIP_VARIANTS = 4
BOX_TONGUE = (512, 512, 512, 512)


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


def blur(img, r):
    """A box blur of a 2-D array (radius r px), wrapping across (the map's longitude) and
    clamped up and down."""
    if r <= 0:
        return img
    k = 2 * r + 1
    p = np.concatenate([img[:, -r - 1:], img, img[:, :r]], axis=1)
    c = np.cumsum(p, axis=1)
    out = (c[:, k:] - c[:, :-k]) / k
    p = np.pad(out, ((r + 1, r), (0, 0)), mode="edge")
    c = np.cumsum(p, axis=0)
    return (c[k:, :] - c[:-k, :]) / k


# ------------------------------------------------------------------------------------------
# The seam and the sockets
# ------------------------------------------------------------------------------------------

def seam_z(phi):
    """The seam's height at `phi` radians round from the front (either way)."""
    a = min(abs(phi), math.pi)
    if a <= math.pi / 2:
        return SEAM_FRONT + (SEAM_CORNER - SEAM_FRONT) * math.sin(a) ** 2
    return SEAM_CORNER * math.cos(a - math.pi / 2) ** 2


def seam_lat(phi):
    return math.asin(seam_z(phi))


def seam_point(phi):
    return sph(seam_lat(phi), FRONT + phi, 1.0)


def eye_centres():
    """The two socket centres as unit vectors (on the shut top jaw)."""
    out = []
    for sx in (1.0, -1.0):
        x, z = sx * EYE_X, EYE_Z
        y = -math.sqrt(max(1.0 - x * x - z * z, 1e-6))
        out.append(Vector((x, y, z)))
    return out


def socket_bump(n):
    """How far (0..1) the unit direction `n` is sunk by the sockets: 1 at a centre."""
    best = 0.0
    for c in eye_centres():
        d = (n - c).length
        if d < SOCKET_R:
            q = 1.0 - (d / SOCKET_R) ** 2
            best = max(best, q * q)
    return best


def phi_of(index):
    """The angle round from the front of longitude column `index` (0 = the back)."""
    a = math.pi + 2 * math.pi * index / SEGS
    return math.atan2(math.sin(a), math.cos(a))


def lon_of(index):
    return FRONT + math.pi + 2 * math.pi * index / SEGS


def skin_uv(lat, lon_index):
    """The UV of the outer shell at latitude `lat` and longitude column `lon_index` (0 at the
    back, SEGS = the back again: the map's u wraps there)."""
    u = lon_index / SEGS
    v = 0.5 + 0.5 * (lat + math.pi / 2) / math.pi
    return (min(max(u, 0.0005), 0.9995), min(max(v, 0.503), 0.997))


def box_uv(box, s, t):
    """UV of the point (s, t) in 0..1 inside pixel box `box` (s across, t down the image)."""
    x0, y0, w, h = box
    px = x0 + 1 + s * (w - 2)
    py = y0 + 1 + t * (h - 2)
    return (px / ATLAS, 1 - py / ATLAS)


# ------------------------------------------------------------------------------------------
# The atlas
# ------------------------------------------------------------------------------------------

def atlas_image():
    img = np.zeros((ATLAS, ATLAS, 4))
    img[..., 3] = 1.0
    img[..., 0:3] = srgb(SEAM)
    # The skin: the outer shell's map. Each texel's direction on the sphere.
    rows, cols = SKIN_ROWS, ATLAS
    v = 1 - (np.arange(rows) + 0.5) / ATLAS  # this row's UV v
    lat = ((v - 0.5) / 0.5) * math.pi - math.pi / 2
    u = (np.arange(cols) + 0.5) / cols
    lon = FRONT + math.pi + 2 * math.pi * u
    LON, LAT = np.meshgrid(lon, lat)
    X, Y, Z = np.cos(LAT) * np.cos(LON), np.cos(LAT) * np.sin(LON), np.sin(LAT)
    col = gradient(SKIN, (math.pi / 2 - LAT) / math.pi)
    # Mottling: a soft blotchy noise and a fine grain.
    rng = np.random.default_rng(11)
    mottle = blur(blur(rng.standard_normal((rows, cols)), 14), 10)
    mottle /= max(np.abs(mottle).max(), 1e-6)
    grain = blur(rng.standard_normal((rows, cols)), 1)
    grain /= max(np.abs(grain).std() * 3, 1e-6)
    col = col * (1 + 0.07 * mottle + 0.025 * grain)[..., None]
    # A soft crease along the lips: the skin darkens toward the seam's front.
    phi = np.angle(np.exp(1j * (LON - FRONT)))
    seam = np.vectorize(seam_lat)(phi[0])[None, :]
    near = np.clip(1 - np.abs(LAT - seam) / 0.16, 0, 1) ** 2
    near *= np.clip((math.radians(LIP_SPAN) - np.abs(phi)) / 0.5, 0, 1)
    col = col * (1 - 0.3 * near[..., None])
    # The sockets: the skin darkens toward each centre (soft shadowed rims) to a near-black
    # core the size of the hole.
    shade = np.zeros((rows, cols))
    for c in eye_centres():
        d = np.sqrt((X - c.x) ** 2 + (Y - c.y) ** 2 + (Z - c.z) ** 2)
        k = np.clip(1 - d / SOCKET_SHADE_R, 0, 1)
        core = np.clip((HOLE_R * 1.45 - d) / (HOLE_R * 0.6), 0, 1)
        shade = np.maximum(shade, np.maximum(0.9 * k ** 1.1, core))
    col = col * (1 - shade[..., None]) + srgb(SOCKET_DARK) * shade[..., None]
    img[0:rows, :, 0:3] = np.clip(col, 0, 1)
    # The inside's strip: by depth (t = 0 at the lip, 1 at the bottom of the bowl).
    x0, y0, w, h = BOX_INSIDE
    t = (np.arange(h) + 0.5) / h
    img[y0:y0 + h, x0:x0 + w, 0:3] = gradient(INSIDE, t)[:, None, :]
    # The seam and the holes.
    x0, y0, w, h = BOX_SEAM
    img[y0:y0 + h, x0:x0 + w, 0:3] = srgb(SEAM)
    x0, y0, w, h = BOX_HOLE
    img[y0:y0 + h, x0:x0 + w, 0:3] = srgb(EYE_HOLE)
    # The lips' cells: s (across) one ridge, a fine line between ridges that wanders a little
    # (each cell its own way, so the ridges are not all alike); t (down) from the lip's edge
    # against the skin (0) over its face to its edge toward the mouth's inside (1). A dark crease
    # where it meets the skin, the face pale, the lines deepening toward the inner edge, which
    # darkens to the inside.
    x0, y0, w, h = BOX_LIP
    s = (np.arange(w) + 0.5) / w
    t = (np.arange(h) + 0.5) / h
    S, T = np.meshgrid(s, t)
    for n, (wob, freq, width, mid) in enumerate(((0.06, 1.0, 0.07, 0.0), (0.09, 1.6, 0.06, 0.32),
                                                  (0.05, 2.3, 0.08, -0.25), (0.1, 1.3, 0.065, 0.5))):
        edge = 0.5 + wob * np.sin(2 * np.pi * (freq * T + 0.17 * n))  # where the line sits
        line = np.exp(-((np.abs(S - 0.5) - edge) / width) ** 2)
        if mid:  # a fainter line part way up the ridge
            line = np.maximum(line, 0.45 * np.exp(-((S - 0.5 - 0.22 * mid) / (width * 0.8)) ** 2) * (T > 0.3))
        strength = (0.5 + 0.4 * np.clip(T / 0.6, 0, 1))[..., None]
        round_ = 0.86 + 0.14 * np.sin(np.pi * np.clip(T / 0.8, 0, 1))  # the band's roundness
        face = srgb(LIP_PALE) * round_[..., None]
        face = face * (1 - strength * line[..., None]) + srgb(LIP_LINE) * (strength * line[..., None])
        deep = np.clip((T - 0.62) / 0.33, 0, 1)[..., None]
        crease = np.clip(1 - T / 0.06, 0, 1)[..., None]
        lip = face * (1 - deep) + srgb(LIP_DEEP) * deep
        lip = lip * (1 - 0.7 * crease) + srgb(SOCKET_DARK) * (0.7 * crease)
        img[y0:y0 + h, x0 + n * w:x0 + (n + 1) * w, 0:3] = lip
    # The tongue: dark, darker toward its edges, a groove down the middle that fades toward the
    # tip, a lit rim round its front edge.
    x0, y0, w, h = BOX_TONGUE
    c = (np.arange(w) + 0.5) / w * 2 - 1
    x, y = np.meshgrid(c, c)
    base, edge, groove_c, rim_c = (srgb(cc) for cc in TONGUE)
    e = np.clip(np.abs(x), 0, 1)[..., None] ** 2
    col = base * (1 - e) + edge * e
    groove = np.exp(-(x / 0.09) ** 2) * np.clip(0.6 + 0.5 * y, 0.2, 1) * 0.75
    col = col * (1 - groove[..., None]) + groove_c * groove[..., None]
    r = np.sqrt(x * x + np.minimum(y, 0) ** 2)  # the front half's round edge (the tip: y < 0)
    rim = np.exp(-((r - 0.8) / 0.07) ** 2) * (y < 0.3) * 0.7
    col = col * (1 - rim[..., None]) + rim_c * rim[..., None]
    img[y0:y0 + h, x0:x0 + w, 0:3] = col
    return common.image_from_array("VerityCreepyAtlas", img,
                                   os.path.join(OUT, "textures", NAME + "_atlas.png"))


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


def set_uvs(face, uvl, uvs):
    for loop, uv in zip(face.loops, uvs):
        loop[uvl].uv = uv


def jaw_steps(upper):
    """The rings of a jaw's shell as fractions of the way from the seam (0) to its pole (1). The
    top jaw is fine through the sockets' band and coarser above it; the bottom jaw is even."""
    if upper:
        return [0.025 * j for j in range(21)] + [0.58, 0.65, 0.72, 0.79, 0.86, 0.93, 1.0]
    return [j / 18 for j in range(19)]


def shell(bm, uvl, upper, sockets):
    """A closed shell between the seam and a pole: the outside (R_OUT, the skin map, sunk at the
    sockets when `sockets`), the inside (R_IN, the inside strip by depth, sunk the same so the
    wall keeps its thickness) and the cut rim along the seam."""
    steps = jaw_steps(upper)
    pole = math.pi / 2 if upper else -math.pi / 2
    lats = [[seam_lat(phi_of(i)) + (pole - seam_lat(phi_of(i))) * f for i in range(SEGS)] for f in steps]

    def rings(r):
        out = []
        for j in range(len(steps)):
            if j == len(steps) - 1:
                out.append([bm.verts.new(Vector((0, 0, r if upper else -r)))] * SEGS)
                continue
            ring = []
            for i in range(SEGS):
                p = sph(lats[j][i], lon_of(i), 1.0)
                depth = SOCKET_DEPTH * socket_bump(p) if sockets else 0.0
                ring.append(bm.verts.new(p * (r - depth)))
            out.append(ring)
        return out

    outer, inner = rings(R_OUT), rings(R_IN)
    for rows, is_out in ((outer, True), (inner, False)):
        for j in range(len(steps) - 1):
            last = j == len(steps) - 2
            for i in range(SEGS):
                i2 = (i + 1) % SEGS
                if is_out:
                    uv = [skin_uv(lats[j][i], i), skin_uv(lats[j][i2], i + 1),
                          skin_uv(lats[j + 1][i2], i + 1), skin_uv(lats[j + 1][i], i)]
                else:
                    t0, t1 = steps[j], steps[j + 1]
                    s0, s1 = 0.3 + 0.4 * (i % 2), 0.3 + 0.4 * ((i + 1) % 2)
                    uv = [box_uv(BOX_INSIDE, s0, t0), box_uv(BOX_INSIDE, s1, t0),
                          box_uv(BOX_INSIDE, s1, t1), box_uv(BOX_INSIDE, s0, t1)]
                verts = [rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]]
                if last:  # the pole: a triangle
                    verts, uv = verts[:3], uv[:2] + [((uv[2][0] + uv[3][0]) / 2, uv[2][1])]
                f = bm.faces.new(verts)
                f.smooth = True
                set_uvs(f, uvl, uv)
    # The cut rim along the seam.
    for i in range(SEGS):
        i2 = (i + 1) % SEGS
        f = bm.faces.new((outer[0][i], outer[0][i2], inner[0][i2], inner[0][i]))
        f.smooth = False
        set_uvs(f, uvl, [box_uv(BOX_SEAM, 0.3, 0.3), box_uv(BOX_SEAM, 0.7, 0.3),
                         box_uv(BOX_SEAM, 0.7, 0.7), box_uv(BOX_SEAM, 0.3, 0.7)])


def lip(bm, uvl, upper):
    """A band of lip along the front of a jaw's edge: an elliptical tube following the seam,
    tallest at the front and tapering to its ends (capped), the upper one hanging below the top
    jaw's edge and the lower riding above the bottom's. Each segment is one ridge of the lip strip
    (s across); t runs over the band's face from the skin to the mouth, its back side dark."""
    span = math.radians(LIP_SPAN)
    rings, tees = [], []
    for k in range(LIP_SEGS + 1):
        f = -1 + 2 * k / LIP_SEGS  # -1 .. 1 along the lip
        phi = f * span
        w = math.cos(abs(f) * math.pi / 2) ** 1.6
        hu = LIP_END + (LIP_H - LIP_END) * w
        hn = LIP_END * 0.8 + (LIP_T - LIP_END * 0.8) * (0.4 + 0.6 * w)
        p = seam_point(phi)
        tangent = (seam_point(phi + 1e-3) - seam_point(phi - 1e-3)).normalized()
        up = p.cross(tangent).normalized()
        if up.z < 0:
            up = -up
        centre = p * LIP_C + up * (hu * LIP_SET * (-1 if upper else 1))
        ring, tt = [], []
        for m in range(LIP_RING):
            psi = 2 * math.pi * m / LIP_RING - math.pi  # -pi .. pi; 0 = straight out, +pi/2 = up
            ring.append(bm.verts.new(centre + p * (hn * math.cos(psi)) + up * (hu * math.sin(psi))))
            if abs(psi) > math.pi / 2:
                tt.append(1.0)  # the back side, inside the jaw: dark
            else:
                tt.append((math.pi / 2 - psi) / math.pi if upper else (psi + math.pi / 2) / math.pi)
        fade = min(max((math.degrees(abs(phi)) - LIP_FADE[0]) / (LIP_FADE[1] - LIP_FADE[0]), 0.0), 1.0)
        rings.append(ring)
        tees.append([t + (1 - t) * fade for t in tt])
    for k in range(LIP_SEGS):
        x0, y0, w, h = BOX_LIP
        cell = (x0 + w * ((k * 7 + (3 if upper else 0)) % LIP_VARIANTS), y0, w, h)  # a ridge cell
        for m in range(LIP_RING):
            m2 = (m + 1) % LIP_RING
            f = bm.faces.new((rings[k][m], rings[k + 1][m], rings[k + 1][m2], rings[k][m2]))
            f.smooth = True
            set_uvs(f, uvl, [box_uv(cell, 0.0, tees[k][m]), box_uv(cell, 1.0, tees[k + 1][m]),
                             box_uv(cell, 1.0, tees[k + 1][m2]), box_uv(cell, 0.0, tees[k][m2])])
    for ring, first in ((rings[0], True), (rings[-1], False)):
        verts = list(reversed(ring)) if first else ring
        f = bm.faces.new(verts)
        f.smooth = True
        set_uvs(f, uvl, [box_uv(BOX_LIP, 0.5, 0.4)] * len(verts))


def eye_holes(bm, uvl):
    """The hollow eyes: a near-black lining at the bottom of each socket, its face following the
    dimple (dished), so the socket reads as a hole and not as a bead."""
    for c in eye_centres():
        res = bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0)
        t1 = c.cross(Vector((0, 0, 1))).normalized()
        t2 = c.cross(t1).normalized()
        for v in res["verts"]:
            x, y, z = v.co
            d = (c + (t1 * x + t2 * y) * HOLE_R).normalized()
            surface = R_OUT - SOCKET_DEPTH * socket_bump(d)
            v.co = d * (surface + (0.004 if z >= 0 else -0.012 * math.sqrt(-z)))
        faces = {f for v in res["verts"] for f in v.link_faces}
        for f in faces:
            f.smooth = True
            set_uvs(f, uvl, [box_uv(BOX_HOLE, 0.5, 0.5)] * len(f.loops))


def tongue(bm, uvl):
    """The tongue filling the bowl's floor: a fat flattened ellipsoid, its back arched up so it
    shows over the lower lip from the front, its tip lower; UVs projected from above into the
    tongue's box."""
    res = bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    verts = res["verts"]
    cx, cy, cz = 0.0, 0.05, -0.42
    ax, ay, az = 0.46, 0.6, 0.2
    for v in verts:
        x, y, z = v.co.x * ax, v.co.y * ay, v.co.z * az
        along = -y / ay  # 1 at the tip, -1 at the back
        z -= 0.08 * max(0.0, along) ** 2
        v.co = Vector((cx + x, cy + y, cz + z))
    faces = {f for v in verts for f in v.link_faces}
    for f in faces:
        f.smooth = True
        uvs = []
        for loop in f.loops:
            co = loop.vert.co
            s = 0.5 + 0.5 * (co.x - cx) / ax
            t = 0.5 + 0.5 * (co.y - cy) / ay  # 0 at the tip (front), 1 at the back
            uvs.append(box_uv(BOX_TONGUE, min(max(s, 0.01), 0.99), min(max(t, 0.01), 0.99)))
        set_uvs(f, uvl, uvs)


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


def build_part(name, material, makers):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    for make in makers:
        make(bm, uvl)
    obj = to_object(name, bm)
    obj.data.materials.append(material)
    return obj


def build_model():
    atlas = atlas_image()
    m = common.image_material("VerityCreepyMat", atlas, roughness=0.7)
    top = build_part("VerityTop", m, [lambda bm, uvl: shell(bm, uvl, True, True),
                                      lambda bm, uvl: lip(bm, uvl, True)])
    bottom = build_part("VerityBottom", m, [lambda bm, uvl: shell(bm, uvl, False, False),
                                            lambda bm, uvl: lip(bm, uvl, False), tongue])
    eyes = build_part("VerityEyes", m, [eye_holes])
    return [top, bottom, eyes], marker("J_Hinge", H)


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


def preview_material():
    """Roblox's Plastic is near matte: take the shine off the preview (the exported model keeps
    its material)."""
    for mat in bpy.data.materials:
        if mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED" and "Specular IOR Level" in node.inputs:
                node.inputs["Specular IOR Level"].default_value = 0.2


def render(name, jaw, elevation, azimuth, distance=4.8, size=512):
    set_jaw(jaw)
    try:
        bpy.context.scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    common.render_preview(os.path.join(OUT, "renders", name + ".png"), size=size, distance=distance,
                          elevation=elevation, azimuth=azimuth, background=(0.1, 0.12, 0.11, 1),
                          target=(0, -0.1, 0.25 if jaw > 10 else 0.0))


def build():
    common.clear_scene()
    parts, hinge = build_model()
    objects = parts + [hinge]
    print("VerityCreepy triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, "tris", common.triangles([o]), tuple(round(v, 3) for v in o.location),
              tuple(round(v, 3) for v in o.dimensions))
    set_jaw(SHUT)
    common.export_glb(os.path.join(OUT, NAME + ".glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, NAME + ".blend"))
    preview_lights()
    preview_material()
    only = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else None
    shots = [
        ("creepy_rest_front34", REST, 18, 28, 4.8),
        ("creepy_rest_front", REST, 8, 0, 4.8),
        ("creepy_rest_high", REST, 55, 8, 4.8),
        ("creepy_gape_front34", GAPE, 24, 28, 5.4),
        ("creepy_gape_high", GAPE, 55, 8, 5.4),
        ("creepy_shut_front34", SHUT, 18, 28, 4.6),
        ("creepy_rest_back", REST, 20, 160, 4.8),
    ]
    for name, jaw, el, az, dist in shots:
        if only is None or name in only:
            render(name, jaw, el, az, dist)
    for extra in (25, 30, 40):
        if only is not None and ("rest%d" % extra) in only:
            render("creepy_rest%d_front34" % extra, extra, 18, 28, 4.8)
            render("creepy_rest%d_high" % extra, extra, 55, 8, 4.8)
    if only is None or "phone" in only:
        render("creepy_rest_high_phone", REST, 55, 8, 4.8, size=96)
        render("creepy_gape_high_phone", GAPE, 55, 8, 5.4, size=96)
    set_jaw(SHUT)


if __name__ == "__main__":
    build()
