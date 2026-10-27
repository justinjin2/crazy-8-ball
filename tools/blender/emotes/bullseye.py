"""Bullseye emote props (designer's concept v2, 2026-10-26: assets/emotes/concepts/bullseye_v2.png).

A bow pops into the player's left hand and a classic archery target a few steps ahead; the arrow
flies into the gold. One material for the set (flat colour tiles plus the painted target face),
so every object is one MeshPart:

  Bow     a wooden recurve, 3.3 studs tip to tip, a dark leather grip. Built upright with its
          string side toward the archer (Blender +Y, Roblox +Z): the model's own axes are the
          bow's place at full draw. The string is two Beams at runtime (tip, hand, tip).
  Arrow   2.9 studs, nock at the origin, pointing Blender -Y (Roblox -Z): red and white
          fletching, a steel point.
  Target  a round straw boss with the face's rings (gold, red, blue, black, white) on a
          wooden easel, the face looking at the archer (Blender +Y). Its centre at FACE_H.

Prints, and writes to bullseye_points.json, the points the runtime needs, measured from each
part's bounding-box centre (where Roblox puts a MeshPart): the bow's grip and string tips,
the arrow's nock and point, the target face's centre.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/emotes/bullseye.py
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emote_common as ec  # noqa: E402
from emote_common import common, fillet, new_object  # noqa: E402

OUT = ec.out_dir("bullseye")
rng = random.Random(11)

# 4 x 4 tiles of 128 px; the top-left 2 x 2 is the target face, painted.
A = ec.Atlas({
    "BowWood": ((2, 0), (0.55, 0.27, 0.12)),
    "Grip": ((3, 0), (0.17, 0.11, 0.08)),
    "Straw": ((2, 1), (0.86, 0.72, 0.42)),
    "StrawDark": ((3, 1), (0.72, 0.56, 0.3)),
    "Wood": ((0, 2), (0.62, 0.42, 0.24)),
    "Shaft": ((1, 2), (0.86, 0.7, 0.48)),
    "Fletch": ((2, 2), (0.88, 0.16, 0.14)),
    "FletchWhite": ((3, 2), (0.96, 0.96, 0.96)),
    "Metal": ((0, 3), (0.62, 0.65, 0.7)),
    "Nock": ((1, 3), (0.98, 0.62, 0.12)),
    "Dark": ((2, 3), (0.2, 0.2, 0.22)),
}, grid=4, tile=128)

FACE_R = 1.5  # the face's radius: big enough to read at 7 studs on a phone
FACE_H = 4.45  # the face's centre over the floor: the aim line's height 7 studs out
BOSS_DEPTH = 0.45
BOW_HALF = 1.65
ARROW_LEN = 2.9

# The World Archery colours, outside in, each split by a thin line (a 10-zone face).
RINGS = [(0.98, 0.98, 0.98), (0.12, 0.12, 0.13), (0.0, 0.66, 0.89), (0.93, 0.22, 0.25), (1.0, 0.86, 0.2)]


def face_pixels():
    """The atlas with the target face painted in its top-left quarter (256 px across)."""
    rgba = A.pixels()
    size = A.tile * 2
    ss = 4  # supersampling for clean ring edges
    ys, xs = np.mgrid[0:size * ss, 0:size * ss]
    r = np.hypot((xs + 0.5) / ss - size / 2, (ys + 0.5) / ss - size / 2) / (size / 2)
    img = np.zeros((size * ss, size * ss, 3), dtype=np.float32)
    img[:] = (0.86, 0.72, 0.42)  # straw beyond the face
    edge = 0.97  # the face's printed edge (a sliver of straw shows round it)
    for zone in range(10):
        outer = edge * (1 - zone / 10)
        inner = edge * (1 - (zone + 1) / 10)
        mask = (r <= outer) & (r > inner)
        img[mask] = RINGS[zone // 2]
    # Thin dividing lines (dark on the light zones, light on the black ones).
    for zone in range(1, 10):
        rr = edge * (1 - zone / 10)
        line = np.abs(r - rr) < 0.0045
        img[line] = (0.85, 0.85, 0.85) if zone in (3, 4) else (0.2, 0.2, 0.22)
    img[np.abs(r - edge) < 0.006] = (0.2, 0.2, 0.22)
    # The centre's small cross.
    c = size * ss / 2
    cross = ((np.abs(xs - c) < 0.6 * ss) & (np.abs(ys - c) < 3 * ss)) | ((np.abs(ys - c) < 0.6 * ss) & (np.abs(xs - c) < 3 * ss))
    img[cross] = (0.2, 0.2, 0.22)
    small = img.reshape(size, ss, size, ss, 3).mean(axis=(1, 3))
    rgba[0:size, 0:size, :3] = small
    return rgba


def face_uv(x, z):
    """A point on the face (x across, z up, from its centre) to the painted quarter's UV."""
    return (0.25 + (x / FACE_R) * 0.25, 0.75 + (z / FACE_R) * 0.25)


# ------------------------------------------------------------------------------------------
# Where the string ties on, near each tip (y toward the archer, z from the grip).
NOCK_Y, NOCK_Z = 0.4, 1.53


def build_bow(mat):
    bm = bmesh.new()
    # The upper limb's profile (y toward the archer, z up) from the grip: a straight riser,
    # the limb bending back toward the string, then the tip curling forward (the recurve).
    upper = [(0.0, 0.0), (0.0, 0.42), (0.07, 0.68), (0.18, 0.98), (0.3, 1.25), (0.39, 1.45),
             (0.41, 1.56), (0.36, 1.65), (0.25, BOW_HALF + 0.05)]
    profile = [(y, -z) for y, z in reversed(upper[1:])] + upper
    pts = fillet([Vector((0, y, z)) for y, z in profile], size=0.12, steps=2)
    n = len(pts)

    def radius(s):
        z = abs(pts[min(int(round(s * (n - 1))), n - 1)].z)
        if z < 0.42:
            return 0.1  # the riser
        return 0.075 - 0.037 * min((z - 0.42) / (BOW_HALF - 0.42), 1)

    def tile(a, b):
        z = abs((a[0].co + b[0].co).z / 2)
        return "Grip" if z < 0.26 else "BowWood"

    A.tube(bm, pts, radius, tile, sides=10)
    # Flat, wide limbs (side to side) like a real bow; the riser stays round.
    for v in bm.verts:
        if abs(v.co.z) > 0.42:
            v.co.x *= 1.55
    for sgn in (1, -1):
        A.sphere(bm, (0, NOCK_Y, NOCK_Z * sgn), 0.05, "Dark", subdivisions=1)
    return new_object("Bow", bm, mat)


def build_arrow(mat):
    bm = bmesh.new()
    A.tube(bm, [(0, -0.06, 0), (0, -(ARROW_LEN - 0.2), 0)], 0.035, "Shaft", sides=6)
    # The point: a short steel cone.
    tip = bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.075, radius2=0.0, depth=0.22)
    for v in tip["verts"]:
        v.co = Vector((v.co.x, -v.co.z - (ARROW_LEN - 0.11), v.co.y))
    for f in {f for v in tip["verts"] for f in v.link_faces}:
        A.paint(bm, f, "Metal")
    # The nock.
    A.tube(bm, [(0, 0.0, 0), (0, -0.07, 0)], 0.045, "Nock", sides=6)
    # Three vanes, 120 degrees apart, the odd one white; each a thin two-sided fin.
    for i in range(3):
        ang = math.radians(90 + 120 * i)
        out = Vector((math.cos(ang), 0, math.sin(ang)))
        y0, y1 = -0.12, -0.55
        quad = [Vector((0, y0, 0)) + out * 0.03, Vector((0, y1, 0)) + out * 0.03,
                Vector((0, y1 + 0.12, 0)) + out * 0.15, Vector((0, y0 - 0.02, 0)) + out * 0.13]
        side = out.cross(Vector((0, 1, 0))).normalized() * 0.006
        front = [bm.verts.new(p + side) for p in quad]
        back = [bm.verts.new(p - side) for p in quad]
        name = "FletchWhite" if i == 0 else "Fletch"
        A.paint(bm, bm.faces.new(front), name)
        A.paint(bm, bm.faces.new(list(reversed(back))), name)
    return new_object("Arrow", bm, mat)


def build_target(mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    segs = 40
    # The face: a disc just in front of the boss, its UVs on the painted rings.
    centre = bm.verts.new((0, 0.01, FACE_H))
    ring = [bm.verts.new((FACE_R * math.cos(2 * math.pi * k / segs), 0.01,
                          FACE_H + FACE_R * math.sin(2 * math.pi * k / segs))) for k in range(segs)]
    for k in range(segs):
        f = bm.faces.new((centre, ring[(k + 1) % segs], ring[k]))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = face_uv(co.x, co.z - FACE_H)
    # The straw boss behind it: a fat cylinder with a lumpy rim, strands in two shades.
    br = FACE_R + 0.08
    rows = [(0.0, br * 0.995), (-0.06, br), (-BOSS_DEPTH + 0.06, br), (-BOSS_DEPTH, br * 0.97)]
    rings = []
    for y, r in rows:
        rings.append([bm.verts.new(((r + rng.uniform(-0.02, 0.02)) * math.cos(2 * math.pi * k / segs), y,
                                    FACE_H + (r + rng.uniform(-0.02, 0.02)) * math.sin(2 * math.pi * k / segs)))
                      for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
            A.paint(bm, f, "StrawDark" if k % 3 == 0 else "Straw")
    front_c = bm.verts.new((0, 0.0, FACE_H))
    back_c = bm.verts.new((0, -BOSS_DEPTH, FACE_H))
    for k in range(segs):
        A.paint(bm, bm.faces.new((front_c, rings[0][k], rings[0][(k + 1) % segs])), "Straw")
        A.paint(bm, bm.faces.new((back_c, rings[-1][(k + 1) % segs], rings[-1][k])), "Straw")
    # The easel: two front legs leaning back past the boss's sides to a top joint, a back leg,
    # and a shelf the boss sits on.
    top = Vector((0, -0.62, FACE_H + FACE_R + 0.45))
    for sgn in (1, -1):
        foot = Vector((sgn * 1.25, 0.35, 0.0))
        A.tube(bm, [foot, top + Vector((sgn * 0.22, 0, 0))], 0.08, "Wood", sides=6)
    A.tube(bm, [top + Vector((0, 0.02, 0.05)), Vector((0, -2.0, 0.0))], 0.08, "Wood", sides=6)
    shelf_z = FACE_H - br - 0.06
    A.tube(bm, [Vector((-1.1, 0.12, shelf_z)), Vector((1.1, 0.12, shelf_z))], 0.09, "Wood", sides=6)
    A.tube(bm, [Vector((-1.0, -0.28, shelf_z)), Vector((1.0, -0.28, shelf_z))], 0.09, "Wood", sides=6)
    return new_object("Target", bm, mat)


def bbox_centre(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2))


def roblox(v):
    """A Blender offset as Roblox studs (STUDIO_NOTES: Blender +X is Roblox -X, +Y is +Z, +Z is +Y)."""
    return [round(-v.x, 4), round(v.z, 4), round(v.y, 4)]


def main():
    common.clear_scene()
    img = A.image("BullseyeAtlas", os.path.join(OUT, "bullseye_atlas.png"), face_pixels())
    mat = common.image_material("BullseyeSet", img, roughness=0.65)
    bow = build_bow(mat)
    arrow = build_arrow(mat)
    target = build_target(mat)
    parts = [bow, arrow, target]
    for obj in parts:
        print(f"{obj.name}: {common.triangles([obj])} triangles, size {tuple(round(d, 2) for d in obj.dimensions)}")
    print(f"total: {common.triangles(parts)} triangles")

    # Points from each part's box centre, in Roblox axes, for Config.
    bc, ac, tc = bbox_centre(bow), bbox_centre(arrow), bbox_centre(target)
    points = {
        "BowGrip": roblox(Vector((0, 0, 0)) - bc),
        "BowTopTip": roblox(Vector((0, NOCK_Y, NOCK_Z)) - bc),
        "BowBottomTip": roblox(Vector((0, NOCK_Y, -NOCK_Z)) - bc),
        "ArrowNock": roblox(Vector((0, 0, 0)) - ac),
        "ArrowPoint": roblox(Vector((0, -ARROW_LEN, 0)) - ac),
        "TargetFace": roblox(Vector((0, 0.01, FACE_H)) - tc),
        "TargetFloor": roblox(Vector((0, 0, 0)) - tc),
    }
    print(json.dumps(points))
    with open(os.path.join(OUT, "bullseye_points.json"), "w") as f:
        json.dump(points, f, indent=1)

    # Side by side for the export; the runtime places them.
    arrow.location = (3.0, 0, 1.0)
    bow.location = (-3.0, 0, 2.0)
    common.export_glb(os.path.join(OUT, "bullseye.glb"), parts)

    # Previews: the archer's view of the target with an arrow in the gold, and the bow.
    ec.preview_scene()
    arrow.location = (0.02, ARROW_LEN - 0.75, FACE_H + 0.02)
    bow.location = (0, 7.5, 3.5)
    renders = os.path.join(OUT, "renders")
    common.render_preview(os.path.join(renders, "target.png"), size=800, target=(0, 0, FACE_H - 0.8),
                          distance=9, elevation=12, azimuth=160, background=(0.3, 0.42, 0.55, 1))
    common.render_preview(os.path.join(renders, "bow.png"), size=700, target=(0, 7.5, 3.5),
                          distance=4.5, elevation=8, azimuth=-80, background=(0.3, 0.42, 0.55, 1))


main()
