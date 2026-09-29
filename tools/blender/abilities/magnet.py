"""Magnet (ABILITIES_PROMPT 7.1, reference 01-magnet-field-lines.png): the field-line meshes.

The reference is a flat dipole diagram: nested blue loops with arrowheads from N round to S,
and flared straight lines out of each pole. Built here as thin round tubes with filled
triangle arrowheads, all in the reference's flat blue, baked into one small image so the whole
set is one material:

  FieldArcs   three nested loops on each side of a dipole whose poles sit at x = -1 and +1
              (S at -1, N at +1), lying in the XY plane, arrows pointing N -> S along the top.
              Scaled at runtime to the cue ball (armed) or the hit ball (contact burst).
  FieldFlares the flared side lines out of one pole (+x), five lines fanning out with an
              arrow on each: the pocket's straight lines.
  FieldRing   a flat ring of eight arrows chasing round a circle: the drop's shockwave.
  Chevron     one arrowhead, for the arrows that flow along the pocket-to-ball field lines
              (moved along the curve in Luau).

All in studs at unit size (the runtime scales them). Run headless or through the MCP.
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

OUT = common.asset_dir("Magnet")

# The reference's blue (#7BA3D6) and a lighter core for a little roundness.
BLUE = np.array([0x7B, 0xA3, 0xD6]) / 255.0
LIGHT = np.array([0xB8, 0xD2, 0xF2]) / 255.0
DARK = np.array([0x55, 0x80, 0xBE]) / 255.0

TUBE = 0.035  # tube radius at unit size (the loops span 2 between the poles)
SIDES = 8


def field_texture():
    """64 x 64: across v (around the tube) dark edge -> light core -> dark edge; the arrows
    use the middle column."""
    h = w = 64
    img = np.zeros((h, w, 4))
    for row in range(h):
        t = row / (h - 1)
        core = math.exp(-((t - 0.35) ** 2) / 0.02)  # the light catches the upper side
        edge = min(t, 1 - t) * 2
        col = DARK + (BLUE - DARK) * min(1, edge * 1.6) + (LIGHT - BLUE) * core
        img[row, :, :3] = np.clip(col, 0, 1)
        img[row, :, 3] = 1
    return common.image_from_array("MagnetField", img, os.path.join(OUT, "textures", "field.png"))


def tube(bm, uv, points, radius):
    """A round tube along `points` (Vectors), UV u along the length, v around."""
    n = len(points)
    rings = []
    length = [0.0]
    for i in range(1, n):
        length.append(length[-1] + (points[i] - points[i - 1]).length)
    total = length[-1] or 1
    up = Vector((0, 0, 1))
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, n - 1)]
        tangent = (b - a).normalized()
        side = tangent.cross(up)
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        normal = side.cross(tangent).normalized()
        ring = []
        for k in range(SIDES):
            ang = 2 * math.pi * k / SIDES
            ring.append(bm.verts.new(p + (side * math.cos(ang) + normal * math.sin(ang)) * radius))
        rings.append(ring)
    for i in range(n - 1):
        for k in range(SIDES):
            k2 = (k + 1) % SIDES
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            for loop, (li, lk) in zip(f.loops, ((i, k), (i, k + 1), (i + 1, k + 1), (i + 1, k))):
                loop[uv].uv = (length[li] / total, lk / SIDES)
    # Round caps: a fan at each end.
    for ring, p in ((rings[0], points[0]), (rings[-1], points[-1])):
        c = bm.verts.new(p)
        for k in range(SIDES):
            f = bm.faces.new((ring[k], ring[(k + 1) % SIDES], c))
            for loop in f.loops:
                loop[uv].uv = (0.5, 0.5)


def arrow(bm, uv, tip, direction, size, flip_normal=Vector((0, 0, 1))):
    """A filled triangle arrowhead (a thin prism) pointing along `direction`, tip at `tip`."""
    d = direction.normalized()
    side = d.cross(flip_normal).normalized()
    back = tip - d * size
    thick = size * 0.18
    corners = [tip, back + side * size * 0.55, back - side * size * 0.55]
    top = [bm.verts.new(c + flip_normal * thick) for c in corners]
    bot = [bm.verts.new(c - flip_normal * thick) for c in corners]
    faces = [top, list(reversed(bot))]
    for k in range(3):
        k2 = (k + 1) % 3
        faces.append([top[k], bot[k], bot[k2], top[k2]])
    for vs in faces:
        f = bm.faces.new(vs)
        for loop in f.loops:
            loop[uv].uv = (0.5, 0.45)


def loop_points(height, steps=40):
    """A loop from the N pole (+1, 0) up and over to the S pole (-1, 0), shaped like the
    reference's: a half-ellipse whose feet start just off the pole, `height` tall."""
    pts = []
    gap = 0.22  # radians left open at each foot, so the loops stop short of the ball
    for i in range(steps + 1):
        a = gap + (math.pi - 2 * gap) * i / steps  # near N first, near S last
        x = math.cos(a) * (0.55 + 0.45 * height)
        y = math.sin(a) * height
        pts.append(Vector((x, y, 0)))
    return pts


def new_object(name, bm, mat):
    # Roblox draws only the front of a face: every face outward before export.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build():
    common.clear_scene()
    mat = common.image_material("MagnetField", field_texture(), roughness=0.6)
    objects = []

    # FieldArcs: three nested loops above the axis and their mirror below.
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for side in (1, -1):
        for height in (0.55, 1.0, 1.5):
            pts = loop_points(height)
            if side < 0:
                pts = [Vector((p.x, -p.y, 0)) for p in pts]
            tube(bm, uv, pts, TUBE)
            mid = len(pts) // 2
            # The arrow at the top of each loop, pointing on toward S (-x).
            arrow(bm, uv, pts[mid] + Vector((-0.09, 0, 0)), Vector((-1, 0, 0)), 0.16)
    objects.append(new_object("FieldArcs", bm, mat))

    # FieldFlares: five lines fanning out of the +x pole, arrows pointing outward.
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for spread in (-0.6, -0.3, 0.0, 0.3, 0.6):
        pts = []
        for i in range(21):
            t = i / 20
            pts.append(Vector((0.15 + t * 1.2, spread * (0.25 + t * t * 1.4), 0)))
        tube(bm, uv, pts, TUBE)
        tip = pts[14]
        arrow(bm, uv, tip + (pts[15] - pts[13]).normalized() * 0.08, pts[15] - pts[13], 0.16)
    objects.append(new_object("FieldFlares", bm, mat))

    # FieldRing: a thin ring with eight arrows chasing round it (counter-clockwise).
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    steps = 64
    ring = [Vector((math.cos(2 * math.pi * i / steps), math.sin(2 * math.pi * i / steps), 0))
            for i in range(steps + 1)]
    tube(bm, uv, ring, TUBE * 0.8)
    for k in range(8):
        a = 2 * math.pi * k / 8
        tip = Vector((math.cos(a), math.sin(a), 0))
        arrow(bm, uv, tip, Vector((-math.sin(a), math.cos(a), 0)), 0.14)
    objects.append(new_object("FieldRing", bm, mat))

    # Chevron: one arrowhead pointing +x, 1 stud long at unit size.
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    arrow(bm, uv, Vector((0.5, 0, 0)), Vector((1, 0, 0)), 1.0)
    objects.append(new_object("Chevron", bm, mat))

    # Lay them out apart for the preview render (the export keeps each at its own origin).
    offsets = {"FieldArcs": (-2.2, 0.8), "FieldFlares": (1.0, 0.8), "FieldRing": (-1.6, -1.8),
               "Chevron": (1.6, -1.8)}
    for obj in objects:
        ox, oy = offsets[obj.name]
        obj.location = (ox, oy, 0)
    tris = common.triangles(objects)
    print("Magnet triangles:", tris)
    common.render_preview(os.path.join(OUT, "renders", "field_set.png"), size=768,
                          distance=7.5, elevation=80, azimuth=0, background=(1, 1, 1, 1))
    for obj in objects:
        obj.location = (0, 0, 0)
    common.export_glb(os.path.join(OUT, "MagnetField.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Magnet.blend"))
    return tris


if __name__ == "__main__":
    build()
