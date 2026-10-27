"""Popcorn emote props (designer's concept v2, 2026-10-26: assets/emotes/concepts/popcorn_v2.png).

The player lounges on a beach lounger under a beach umbrella, a striped popcorn bucket in one
hand, throwing handfuls at their mouth. One material for the whole set (a small atlas of flat
colour tiles, each face mapped to its tile), so every object is one MeshPart:

  Lounger   white tube frame and a sling with lengthwise stripes of the table's blue felt and
            white. Origin: the floor under the hip (where the seat meets the backrest).
  Umbrella  eight light-blue and white panels with a scalloped edge, a white pole and weighted
            base, leaning a little over the lounger from the player's left, behind them.
  Bucket    red and white stripes, a white lip and a heap of popcorn. Origin: its centre.
  KernelA, KernelB   one lumpy popcorn piece each (the flying and spilled ones).

Also renders popcorn_sprite.png, one piece on a clear background for the spill particles.

Studs throughout (1 Blender metre = 1 stud). The lounger faces Blender -Y (the player's look
direction once imported; STUDIO_NOTES: Blender +Y arrives as Roblox +Z, +X as -X), sized for a
default R15 body; the runtime scales the set to the body.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/emotes/popcorn.py
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emote_common as ec  # noqa: E402
from emote_common import common, fillet, new_object, resample  # noqa: E402

OUT = ec.out_dir("popcorn")

# The atlas: 4 x 4 tiles of flat colour (col, row from the top) so filtering never mixes two
# looks at the sizes the set is seen at.
A = ec.Atlas({
    "White": ((0, 0), (0.95, 0.96, 0.97)),
    "Sky": ((1, 0), (0.62, 0.82, 0.95)),  # the umbrella's light blue
    "Felt": ((2, 0), (110 / 255, 165 / 255, 215 / 255)),  # Config.Table.FeltColor
    "Red": ((3, 0), (0.86, 0.17, 0.15)),
    "Corn": ((0, 1), (1.0, 0.96, 0.84)),
    "Butter": ((1, 1), (1.0, 0.86, 0.45)),
    "Hull": ((2, 1), (0.72, 0.46, 0.2)),
    "Grey": ((3, 1), (0.42, 0.45, 0.5)),
})
paint = A.paint
tube = A.tube
sphere = A.sphere
sheet = A.sheet

TUBE_R = 0.085  # the lounger's frame tubes
HALF_W = 1.25  # the frame's half width (a default R15 body is 2 studs across the shoulders)

rng = random.Random(8)


def fwd(f, z, x=0.0):
    """Lounger space (forward f toward the feet, up z, x to the player's right) to Blender."""
    return Vector((-x, -f, z))


# ------------------------------------------------------------------------------------------
# The lounger: the sling's centre line in (forward, up), the seat sagging a little, the back at
# about 39 degrees, its top high enough to rest a default head on.
SLING_PATH = [(2.55, 0.78), (0.15, 0.6), (-1.95, 2.3)]
RAIL_PATH = [(2.65, 0.84), (0.15, 0.68), (-2.0, 2.42)]
FRONT_F, BACK_FOOT_F, FLOOR_Z = 2.65, -2.3, 0.09
STRIPES = 7  # lengthwise bands across the sling, felt blue at both edges


def build_lounger(mat):
    bm = bmesh.new()
    rail = [Vector((0, f, z)) for f, z in RAIL_PATH]
    rail = fillet(rail, size=0.45, steps=3)
    for side in (-1, 1):
        x = side * HALF_W
        tube(bm, [fwd(p.y, p.z, x) for p in rail], TUBE_R, "White")
        # A runner on the floor, the front leg and the back leg, one bent tube.
        leg = fillet([Vector((0, RAIL_PATH[0][0], RAIL_PATH[0][1])),
                      Vector((0, FRONT_F, FLOOR_Z)),
                      Vector((0, BACK_FOOT_F, FLOOR_Z)),
                      Vector((0, RAIL_PATH[2][0] - 0.05, RAIL_PATH[2][1] - 0.35))],
                     size=0.25, steps=3)
        tube(bm, [fwd(p.y, p.z, x) for p in leg], TUBE_R, "White")
        # The middle leg under the hip.
        tube(bm, [fwd(0.15, 0.62, x), fwd(0.15, FLOOR_Z, x)], TUBE_R * 0.9, "White")
        # Grey feet so it reads as standing on the floor.
        for f in (FRONT_F - 0.1, BACK_FOOT_F + 0.1):
            sphere(bm, fwd(f, FLOOR_Z - 0.02, x), TUBE_R * 1.25, "Grey", subdivisions=1)
    # Cross bars at the foot end, the head end and on the floor.
    for f, z in (RAIL_PATH[0], RAIL_PATH[2], (FRONT_F, FLOOR_Z), (BACK_FOOT_F, FLOOR_Z)):
        tube(bm, [fwd(f, z, -HALF_W), fwd(f, z, HALF_W)], TUBE_R, "White")

    # The sling: rows along the path, columns across, sagging a little in the middle.
    centre = resample(fillet([Vector((0, f, z)) for f, z in SLING_PATH], size=0.5, steps=3), 0.9)
    cols = STRIPES + 1
    half = HALF_W - TUBE_R * 1.6
    grid = []
    for p in centre:
        row = []
        for c in range(cols):
            u = c / (cols - 1)
            x = -half + 2 * half * u
            sag = 0.07 * math.sin(math.pi * u)
            row.append(fwd(p.y, p.z - sag, x))
        grid.append(row)
    sheet(bm, grid, lambda r, c: "Felt" if c % 2 == 0 else "White", 0.035)
    return new_object("Lounger", bm, mat)


# ------------------------------------------------------------------------------------------
# The umbrella: its pole stands to the player's left (+X in Blender) and behind the hip, leaning
# so the canopy's centre sits over the chest.
POLE_BASE = Vector((1.95, 0.95, 0.0))
CANOPY_TOP = Vector((0.85, 0.55, 6.2))
CANOPY_R, CANOPY_DROP = 3.1, 0.95
PANELS, PANEL_STEPS = 8, 3
VALANCE = 0.3  # the scalloped edge's depth


def build_umbrella(mat):
    bm = bmesh.new()
    axis = (CANOPY_TOP - POLE_BASE).normalized()
    side = axis.cross(Vector((0, 1, 0))).normalized()
    front = side.cross(axis).normalized()

    def at(r, phi, drop):
        return CANOPY_TOP + (side * math.cos(phi) + front * math.sin(phi)) * r - axis * drop

    # Flat panels between ribs: the rim is an octagon, not a circle.
    def panel_r(phi):
        width = 2 * math.pi / PANELS
        d = (phi % width) - width / 2
        return math.cos(width / 2) / math.cos(d)

    cols = PANELS * PANEL_STEPS
    radii = [0.0, 1.1, 2.15, CANOPY_R]
    grid = []
    for r in radii:
        row = []
        for c in range(cols + 1):
            phi = 2 * math.pi * c / cols
            rr = r * panel_r(phi)
            row.append(at(rr, phi, CANOPY_DROP * (r / CANOPY_R) ** 1.35 - 0.0))
        grid.append(row)
    # The scalloped valance: one row hanging down, deepest in each panel's middle.
    rim = []
    for c in range(cols + 1):
        phi = 2 * math.pi * c / cols
        t = (c % PANEL_STEPS) / PANEL_STEPS
        depth = VALANCE * (0.35 + 0.65 * math.sin(math.pi * t))
        p = grid[-1][c] - axis * depth
        rim.append(p)
    grid.append(rim)

    def panel_tile(r, c):
        return "Sky" if (c // PANEL_STEPS) % 2 == 0 else "White"

    sheet(bm, grid, panel_tile, 0.04)
    # The pole (through the canopy to a small finial), the cap and the weighted base.
    tube(bm, [POLE_BASE + axis * 0.15, CANOPY_TOP + axis * 0.25], 0.075, "White")
    sphere(bm, CANOPY_TOP + axis * 0.3, 0.14, "White", subdivisions=2)
    base = bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.55, radius2=0.42,
                                 depth=0.16)
    for v in base["verts"]:
        v.co += POLE_BASE + Vector((0, 0, 0.08))
    for f in {f for v in base["verts"] for f in v.link_faces}:
        paint(bm, f, "Grey")
    return new_object("Umbrella", bm, mat)


# ------------------------------------------------------------------------------------------
BUCKET_H, BUCKET_R0, BUCKET_R1 = 0.95, 0.34, 0.46
BUCKET_SEGS = 32  # 16 stripes, two segments each, so the round reads smooth up close


def random_dir(r):
    return Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-1, 1))).normalized()


def lumpy_kernel(bm, centre, radius, seed, subdivisions=3):
    """One popcorn piece: an icosphere puffed out into five or six fused lobes (the popped
    flakes), cream with a butter-yellow patch and a small brown hull where it split."""
    r = random.Random(seed)
    lobes = [(random_dir(r), r.uniform(0.3, 0.5)) for _ in range(r.choice((6, 7)))]
    hull = random_dir(r)
    butter = random_dir(r)
    geom = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    for v in geom["verts"]:
        n = v.co.normalized()
        puff = sum(w * max(0.0, n.dot(d)) ** 7 for d, w in lobes)
        dent = 0.12 * max(0.0, n.dot(hull)) ** 2  # the hull end sits a little in
        v.co = n * radius * (0.5 + min(puff, 0.6) - dent + r.uniform(-0.035, 0.035)) + Vector(centre)
    for f in {f for v in geom["verts"] for f in v.link_faces}:
        n = (f.calc_center_median() - Vector(centre)).normalized()
        if n.dot(hull) > 0.88:
            paint(bm, f, "Hull")
        elif n.dot(butter) > 0.55 + r.uniform(-0.1, 0.1):
            paint(bm, f, "Butter")
        else:
            paint(bm, f, "Corn")


def ring_verts(bm, radius, z, segs, jitter=0.0):
    return [bm.verts.new((radius * math.cos(2 * math.pi * k / segs) + rng.uniform(-jitter, jitter),
                          radius * math.sin(2 * math.pi * k / segs) + rng.uniform(-jitter, jitter),
                          z + rng.uniform(-jitter, jitter)))
            for k in range(segs)]


def bridge(bm, a, b, tile_of):
    segs = len(a)
    for k in range(segs):
        if len(b) == 1:
            f = bm.faces.new((a[k], a[(k + 1) % segs], b[0]))
        else:
            f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
        paint(bm, f, tile_of(k))


def build_bucket(mat):
    bm = bmesh.new()
    z0, z1 = -BUCKET_H / 2, BUCKET_H / 2
    segs = BUCKET_SEGS
    stripe = (lambda k: "Red" if (k // 2) % 2 == 0 else "White")
    # The paper wall, straight and tapered, with a small rounded foot.
    foot = ring_verts(bm, BUCKET_R0 - 0.03, z0, segs)
    wall = [ring_verts(bm, BUCKET_R0, z0 + 0.04, segs),
            ring_verts(bm, (BUCKET_R0 + BUCKET_R1) / 2, 0.0, segs),
            ring_verts(bm, BUCKET_R1, z1, segs)]
    bridge(bm, foot, wall[0], stripe)
    for a, b in zip(wall, wall[1:]):
        bridge(bm, a, b, stripe)
    centre = bm.verts.new((0, 0, z0))
    bridge(bm, list(reversed(foot)), [centre], lambda k: "White")
    # The rolled lip: a thin white tube round the top edge.
    lip_r, minor, minor_segs = BUCKET_R1 + 0.02, 0.035, 6
    lip = []
    for j in range(minor_segs):
        a = 2 * math.pi * j / minor_segs
        lip.append(ring_verts(bm, lip_r + minor * math.cos(a), z1 + minor * math.sin(a), segs))
    for j in range(minor_segs):
        bridge(bm, lip[j], lip[(j + 1) % minor_segs], lambda k: "White")
    # The heap: a lumpy dome a little over the rim, then pieces packed on it in rings.
    heap_rows = [(BUCKET_R1 * 1.02, z1 + 0.03), (0.4, z1 + 0.14), (0.28, z1 + 0.24), (0.14, z1 + 0.3)]
    heap = [ring_verts(bm, r, z, segs // 2, jitter=0.02) for r, z in heap_rows]
    top = bm.verts.new((0, 0, z1 + 0.32))
    for a, b in zip(heap, heap[1:]):
        bridge(bm, a, b, lambda k: "Corn")
    bridge(bm, heap[-1], [top], lambda k: "Corn")
    seed = 100
    for ring_r, count, z in ((0.42, 9, z1 + 0.08), (0.27, 6, z1 + 0.22), (0.0, 1, z1 + 0.33)):
        for i in range(count):
            ang = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / count
            seed += 1
            lumpy_kernel(bm, (ring_r * math.cos(ang), ring_r * math.sin(ang), z + rng.uniform(-0.02, 0.03)),
                         0.13, seed, subdivisions=2)
    return new_object("Bucket", bm, mat)


KERNEL_R = 0.15  # a loose piece: big enough to read on a phone


def build_kernels(mat):
    out = []
    for name, seed in (("KernelA", 7), ("KernelB", 19)):
        bm = bmesh.new()
        lumpy_kernel(bm, (0, 0, 0), KERNEL_R, seed, subdivisions=3)
        out.append(new_object(name, bm, mat))
    return out


# ------------------------------------------------------------------------------------------
def stand_in_body():
    """A grey box body lounging on the chair, for the preview renders only (not exported)."""
    mat = bpy.data.materials.new("StandIn")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.95, 0.8, 0.2, 1)
    objs = []

    def box(name, size, centre, tilt):
        bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
        obj = bpy.context.object
        obj.name = name
        obj.scale = size
        obj.rotation_euler = (tilt, 0, 0)
        obj.data.materials.append(mat)
        objs.append(obj)

    tilt = math.atan2(1.7, 2.1)  # the backrest's angle up from the floor
    hip = fwd(0.25, 1.08)
    up_back = Vector((0, 2.1, 1.7)).normalized()  # up the backrest, toward the head
    box("Torso", (2.0, 1.0, 2.0), hip + up_back * 1.0 + Vector((0, -0.25, 0.3)), -(math.pi / 2 - tilt))
    box("Head", (1.2, 1.2, 1.2), hip + up_back * 2.6 + Vector((0, -0.35, 0.45)), -(math.pi / 2 - tilt))
    for x in (-0.5, 0.5):
        box("Leg", (0.95, 2.3, 0.95), fwd(1.45, 1.05, x), 0)
    return objs


def main():
    common.clear_scene()
    img = A.image("PopcornAtlas", os.path.join(OUT, "popcorn_atlas.png"))
    mat = common.image_material("PopcornSet", img, roughness=0.6)
    lounger = build_lounger(mat)
    umbrella = build_umbrella(mat)
    bucket = build_bucket(mat)
    kernels = build_kernels(mat)
    parts = [lounger, umbrella, bucket] + kernels
    for obj in parts:
        print(f"{obj.name}: {common.triangles([obj])} triangles, size {tuple(round(d, 2) for d in obj.dimensions)}")
    print(f"total: {common.triangles(parts)} triangles")

    # The bucket and kernels sit beside the scene in the file (the runtime places them).
    bucket.location = (4.5, 0, 0.5)
    kernels[0].location = (4.2, -1.2, 0.2)
    kernels[1].location = (4.8, -1.2, 0.2)
    common.export_glb(os.path.join(OUT, "popcorn.glb"), parts)

    # Previews: the set as it is seen, with a stand-in body and popcorn spilled on the floor.
    body = stand_in_body()
    bucket.location = fwd(0.9, 1.75, -0.35)
    bucket.rotation_euler = (math.radians(-15), 0, 0)
    spilled = []
    for i in range(14):
        k = (kernels[i % 2]).copy()
        k.data = kernels[i % 2].data
        k.location = (rng.uniform(-2.2, 2.2), rng.uniform(-3.2, 1.0), KERNEL_R * 0.7)
        k.rotation_euler = (rng.uniform(0, 6), rng.uniform(0, 6), rng.uniform(0, 6))
        bpy.context.scene.collection.objects.link(k)
        spilled.append(k)
    kernels[0].location = fwd(1.2, 3.1, 0.6)
    kernels[1].location = fwd(1.5, 3.4, 0.2)
    floor = ec.preview_scene()
    renders = os.path.join(OUT, "renders")
    common.render_preview(os.path.join(renders, "scene_front.png"), size=900, target=(0.3, -0.4, 2.0),
                          distance=14, elevation=24, azimuth=-35, background=(0.3, 0.42, 0.55, 1))
    common.render_preview(os.path.join(renders, "scene_side.png"), size=900, target=(0.3, -0.4, 2.0),
                          distance=14, elevation=12, azimuth=-95, background=(0.3, 0.42, 0.55, 1))
    common.render_preview(os.path.join(renders, "scene_behind.png"), size=900, target=(0.3, -0.4, 2.0),
                          distance=14, elevation=30, azimuth=180, background=(0.3, 0.42, 0.55, 1))
    for obj in body + spilled + [floor]:
        obj.hide_render = True
    lounger.hide_render = umbrella.hide_render = True
    bucket.location = (0, 0, 0.67)
    bucket.rotation_euler = (0, 0, 0)
    kernels[0].location = (0.75, -0.35, 0.12)
    kernels[1].location = (1.05, -0.1, 0.12)
    common.render_preview(os.path.join(renders, "bucket.png"), size=700, target=(0.4, -0.1, 0.6),
                          distance=3.4, elevation=24, azimuth=15, background=(0.3, 0.42, 0.55, 1))

    # The spill particle: one piece of popcorn on a clear background (256 px), lit like the set.
    bucket.hide_render = True
    kernels[1].hide_render = True
    kernels[0].location = (0, 0, 0)
    kernels[0].rotation_euler = (0.4, 0.2, 0.9)
    common.render_preview(os.path.join(OUT, "popcorn_sprite.png"), size=256, target=(0, 0, 0),
                          distance=0.62, elevation=30, azimuth=20, transparent=True,
                          background=(0.95, 0.95, 0.95, 1))  # a bright sky: no grey cast


main()
