"""Heat Seeker (ABILITIES_PROMPT 7.5): the lock-on reticle, the exhaust flame and the impact's
smoke ring, and the smoke puffs' flipbook.

  Reticle       a flat target lock of unit radius in Blender's XY plane (flat on the cloth in
                Roblox): four L brackets at the corners of a square, four chevrons pointing in
                and a thin broken ring. Red, with a bright core line on the brackets. It closes
                in on the locked ball and spins.
  ExhaustFlame  a flame one unit long along +X (Roblox's -X: the look turns it), its nozzle
                (radius 0.4) at x = 0 and its tip at x = 1: an outer red-orange shell and an
                inner white-yellow core, fading out toward the tip (alpha). It trails the cue
                ball, pointing back along its path.
  SmokeRing     a soft grey torus of unit radius, flat in XY, that spreads at the impact.

One small texture for the three (one material, alpha on); its rows by v: the reticle's red
and core, the flame's two gradients (u along the length), the smoke grey. The flipbook is a
separate image (textures/smoke_flipbook.png, 4 x 4 frames of a puff swelling and thinning)
for a ParticleEmitter. Run headless or through the MCP.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("HeatSeeker")

RED = "FF2B2B"
RED_CORE = "FFB0A0"
FLAME = ["FFE680", "FF9A1F", "FF4A12", "D81E10"]  # nozzle to tip
CORE = ["FFFFFF", "FFE890", "FFB040"]
SMOKE = "D9D6D2"

# The texture's rows by v.
RED_V = 0.94
RED_CORE_V = 0.86
FLAME_V = (0.55, 0.75)  # the outer shell's gradient (u along the flame)
CORE_V = (0.32, 0.5)  # the core's
SMOKE_V = 0.12


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def ramp(colours, t):
    """A colour along evenly spaced stops, t in 0..1."""
    t = min(max(t, 0.0), 1.0) * (len(colours) - 1)
    i = min(int(t), len(colours) - 2)
    f = t - i
    return hex_rgb(colours[i]) * (1 - f) + hex_rgb(colours[i + 1]) * f


def texture():
    w, h = 128, 128
    img = np.zeros((h, w, 4))
    for row in range(h):
        v = 1 - (row + 0.5) / h
        for col in range(w):
            u = (col + 0.5) / w
            if v >= 0.9:
                img[row, col] = (*hex_rgb(RED), 1)
            elif v >= 0.8:
                img[row, col] = (*hex_rgb(RED_CORE), 1)
            elif v >= FLAME_V[0] - 0.02:
                # The outer flame: colour along u, alpha fading to the tip and to the edges.
                across = np.clip((v - FLAME_V[0]) / (FLAME_V[1] - FLAME_V[0]), 0, 1)
                edge = 1 - abs(2 * across - 1) ** 3
                alpha = (1 - u) ** 0.8 * (0.5 + 0.5 * edge)
                img[row, col] = (*ramp(FLAME, u), np.clip(alpha, 0, 1))
            elif v >= CORE_V[0] - 0.02:
                across = np.clip((v - CORE_V[0]) / (CORE_V[1] - CORE_V[0]), 0, 1)
                edge = 1 - abs(2 * across - 1) ** 3
                alpha = (1 - u) ** 2.2 * (0.5 + 0.5 * edge)
                img[row, col] = (*ramp(CORE, u), np.clip(alpha, 0, 1))
            else:
                img[row, col] = (*hex_rgb(SMOKE), 0.85)
    return common.image_from_array("HeatSeeker", img, os.path.join(OUT, "textures", "heatseeker.png"))


def flipbook(frames=4, size=128, seed=7):
    """A 4 x 4 flipbook of a smoke puff: a few soft lumps swelling out and thinning, grey-white
    with a slightly darker underside; frame 1 top left, read along rows."""
    rng = np.random.default_rng(seed)
    n = frames * frames
    lumps = [(rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), rng.uniform(0.18, 0.3))
             for _ in range(6)]
    grain = rng.uniform(0, 1, (size, size))
    # A soft blur of the grain for a cloudy break-up.
    for _ in range(10):
        grain = (grain + np.roll(grain, 1, 0) + np.roll(grain, -1, 0) + np.roll(grain, 1, 1)
                 + np.roll(grain, -1, 1)) / 5
    grain = (grain - grain.min()) / (grain.max() - grain.min())
    ys, xs = np.mgrid[0:size, 0:size]
    px = (xs + 0.5) / size * 2 - 1
    py = 1 - (ys + 0.5) / size * 2
    sheet = np.zeros((size * frames, size * frames, 4))
    for k in range(n):
        t = k / (n - 1)
        grow = 0.55 + 0.45 * t
        density = np.zeros((size, size))
        for lx, ly, lr in lumps:
            r = lr * grow * 2.4
            d2 = ((px - lx * grow) ** 2 + (py - ly * grow) ** 2) / (r * r)
            density = np.maximum(density, np.exp(-d2 * 1.6))
        density *= 0.8 + 0.4 * (grain - 0.5)
        fade = (1 - t) ** 1.1
        alpha = np.clip(density * fade * 1.6, 0, 1)
        shade = 0.72 + 0.28 * np.clip(0.5 + 0.5 * py, 0, 1)
        grey = hex_rgb(SMOKE)
        tile = np.zeros((size, size, 4))
        tile[..., 0] = grey[0] * shade
        tile[..., 1] = grey[1] * shade
        tile[..., 2] = grey[2] * shade
        tile[..., 3] = alpha
        r0, c0 = (k // frames) * size, (k % frames) * size
        sheet[r0:r0 + size, c0:c0 + size] = tile
    return common.image_from_array("SmokeFlipbook", sheet,
                                   os.path.join(OUT, "textures", "smoke_flipbook.png"))


def new_object(name, bm, mat, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def slab(bm, uv, outline, depth, v):
    """A flat prism from a 2D outline (counter-clockwise, XY), `depth` thick, texture row v."""
    top = [bm.verts.new((x, y, depth / 2)) for x, y in outline]
    bottom = [bm.verts.new((x, y, -depth / 2)) for x, y in outline]
    faces = [bm.faces.new(top), bm.faces.new(list(reversed(bottom)))]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((bottom[i], bottom[j], top[j], top[i])))
    for f in faces:
        for lp in f.loops:
            lp[uv].uv = (0.5, v)


def reticle(mat, depth=0.04):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    # The brackets: an L at each corner of a square of half-size 0.72, arms 0.3 long, 0.07 thick;
    # a thinner core line inside each in the bright row, a hair above.
    s, arm, t = 0.72, 0.3, 0.07
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts = [(s, s), (s - arm, s), (s - arm, s - t), (s - t, s - t), (s - t, s - arm),
                   (s, s - arm)]
            outline = [(x * sx, y * sy) for x, y in pts]
            if sx * sy < 0:
                outline = list(reversed(outline))
            slab(bm, uv, outline, depth, RED_V)
            core = [(s - 0.02, s - 0.02), (s - arm + 0.03, s - 0.02), (s - arm + 0.03, s - 0.045),
                    (s - 0.045, s - 0.045), (s - 0.045, s - arm + 0.03), (s - 0.02, s - arm + 0.03)]
            core = [(x * sx, y * sy) for x, y in core]
            if sx * sy < 0:
                core = list(reversed(core))
            top = [bm.verts.new((x, y, depth / 2 + 0.004)) for x, y in core]
            f = bm.faces.new(top)
            for lp in f.loops:
                lp[uv].uv = (0.5, RED_CORE_V)
    # Chevrons pointing in at N, E, S, W, just inside the ring.
    for k in range(4):
        a = k * math.pi / 2
        c, sn = math.cos(a), math.sin(a)
        # The tip at radius 0.84 pointing at the centre, the base at 1.0.
        local = [(0.84, 0.0), (1.0, -0.1), (1.0, 0.1)]
        pts = [(x * c - y * sn, x * sn + y * c) for x, y in local]
        slab(bm, uv, pts, depth, RED_V)
    # A thin ring broken into eight arcs between the brackets and chevrons.
    segs = 96
    r_in, r_out = 0.9, 0.94
    for k in range(segs):
        a0 = 2 * math.pi * k / segs
        a1 = 2 * math.pi * (k + 1) / segs
        mid = (a0 + a1) / 2
        # Gaps at the chevrons (0, 90, 180, 270) and at the diagonals (the brackets).
        phase = (mid % (math.pi / 4)) / (math.pi / 4)
        if phase < 0.18 or phase > 0.82:
            continue
        pts = [(r_in * math.cos(a0), r_in * math.sin(a0)), (r_out * math.cos(a0), r_out * math.sin(a0)),
               (r_out * math.cos(a1), r_out * math.sin(a1)), (r_in * math.cos(a1), r_in * math.sin(a1))]
        slab(bm, uv, list(reversed(pts)), depth * 0.6, RED_V)
    return new_object("Reticle", bm, mat, smooth=False)


def revolve(bm, uv, profile, v_range, segs=20):
    """A shell revolved round X from `profile` [(x, radius)], u = x (0..1) along it, v across
    the texture rows `v_range` by the angle (so the edge fade wraps)."""
    rings = []
    for x, r in profile:
        ring = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            ring.append(bm.verts.new((x, r * math.cos(a), r * math.sin(a))))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for i in range(segs):
            k = (i + 1) % segs
            f = bm.faces.new((rings[j][i], rings[j][k], rings[j + 1][k], rings[j + 1][i]))
            for lp in f.loops:
                co = lp.vert.co
                ang = (math.atan2(co.z, co.y) / (2 * math.pi)) % 1.0
                # Mirror the angle so the texture's two edges meet (no seam).
                across = 1 - abs(2 * ang - 1)
                lp[uv].uv = (min(max(co.x, 0.0), 0.999), v_range[0] + (v_range[1] - v_range[0]) * across)
    # Close the nozzle end with a fan.
    x0, _ = profile[0]
    centre = bm.verts.new((x0, 0, 0))
    for i in range(segs):
        k = (i + 1) % segs
        f = bm.faces.new((rings[0][k], rings[0][i], centre))
        for lp in f.loops:
            lp[uv].uv = (0.01, (v_range[0] + v_range[1]) / 2)


def flame(mat, n=14):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    outer = []
    inner = []
    for i in range(n + 1):
        x = i / n
        # A bulb just behind the nozzle, then a long taper to a point.
        r = 0.4 * (1 - x) ** 0.85 * (1 + 0.25 * math.sin(math.pi * min(x * 2.2, 1)))
        outer.append((x, max(r, 0.002)))
        inner.append((x * 0.7, max(0.22 * (1 - x) ** 0.8, 0.002)))
    revolve(bm, uv, outer, FLAME_V)
    revolve(bm, uv, inner, CORE_V, segs=14)
    return new_object("ExhaustFlame", bm, mat)


def smoke_ring(mat, major=1.0, minor=0.2, segs=40, sides=10):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    grid = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * 0.6 * math.sin(b))))
        grid.append(row)
    for i in range(segs):
        for j in range(sides):
            f = bm.faces.new((grid[i][j], grid[(i + 1) % segs][j], grid[(i + 1) % segs][(j + 1) % sides],
                              grid[i][(j + 1) % sides]))
            for lp in f.loops:
                lp[uv].uv = (0.5, SMOKE_V)
    return new_object("SmokeRing", bm, mat)


def build():
    common.clear_scene()
    mat = common.image_material("HeatSeeker", texture(), alpha=True, roughness=0.45)
    flipbook()
    objects = [reticle(mat), flame(mat), smoke_ring(mat)]
    print("HeatSeeker triangles:", common.triangles(objects))
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(-40), 0, math.radians(-20))
    bpy.context.scene.collection.objects.link(sun)
    objects[1].location = (-0.3, -1.6, 0.3)
    objects[2].location = (1.9, 0.6, 0)
    objects[2].scale = (0.6, 0.6, 0.6)
    common.render_preview(os.path.join(OUT, "renders", "set.png"), size=640, distance=5.0,
                          elevation=55, azimuth=10, target=(0.3, -0.3, 0))
    bpy.data.objects.remove(sun, do_unlink=True)
    for obj in objects:
        obj.location = (0, 0, 0)
        obj.scale = (1, 1, 1)
    common.export_glb(os.path.join(OUT, "HeatSeeker.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "HeatSeeker.blend"))


if __name__ == "__main__":
    build()
