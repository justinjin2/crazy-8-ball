"""Super Bounce (ABILITIES_PROMPT 7.3): the cue ball's rainbow shell and the "boing" ring.

  RainbowShell  a sphere of unit radius (scaled at runtime a little over the cue ball) in
                diagonal rainbow bands (the house rainbow, UI_STYLE's VIP colours). Roblox
                cannot scroll a mesh's texture, so the look turns the shell each frame: the
                colours move across the ball.
  BoingRing     a flat cartoon impact: a ring with twelve star points round it, pale yellow
                with a white core line, lying in the XY plane at unit radius (popped and faded
                at each rail and ball hit).

One small baked image for both (one material): the top of the image is the rainbow (its six
bands along u), the bottom the boing's two colours. Run headless or through the MCP.
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

OUT = common.asset_dir("SuperBounce")

RAINBOW = ["FF4D4D", "FF9F1C", "FFE14D", "3DD66B", "3B9BFF", "A259FF"]
BOING = "FFE680"
BOING_CORE = "FFFFFF"
BANDS_ALONG = Vector((0.55, -0.3, 0.78)).normalized()  # the stripes run across this axis
STRIPES = 2  # the six colours repeat this many times over the ball

# The texture's rows by v: the rainbow in RAINBOW_V, the boing's colour at BOING_V and its core
# at CORE_V.
RAINBOW_V = (0.4, 0.98)
BOING_V = 0.22
CORE_V = 0.07


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def texture():
    """128 x 64: along u the six rainbow colours with soft 1-pixel edges (rows in RAINBOW_V),
    under them the boing's pale yellow and white."""
    w, h = 128, 64
    img = np.zeros((h, w, 4))
    for row in range(h):
        v = 1 - (row + 0.5) / h
        for col in range(w):
            u = (col + 0.5) / w
            if v >= 0.33:
                f = u * len(RAINBOW)
                i = int(f) % len(RAINBOW)
                j = (i + 1) % len(RAINBOW)
                frac = f - int(f)
                mix = max(0.0, (frac - 0.9) / 0.1)  # a soft edge into the next band
                c = hex_rgb(RAINBOW[i]) * (1 - mix) + hex_rgb(RAINBOW[j]) * mix
                shine = 0.12 * math.exp(-((v - 0.8) ** 2) / 0.01)
                img[row, col, :3] = np.clip(c + shine, 0, 1)
            elif v >= 0.15:
                img[row, col, :3] = hex_rgb(BOING)
            else:
                img[row, col, :3] = hex_rgb(BOING_CORE)
            img[row, col, 3] = 1
    return common.image_from_array("SuperBounce", img, os.path.join(OUT, "textures", "bounce.png"))


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


def shell(mat, segs=48, rings=24):
    """A UV sphere whose u runs across BANDS_ALONG: each vertex's u is where it sits along that
    axis, STRIPES times round the rainbow, so the bands cross the ball diagonally."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for f in bm.faces:
        for loop in f.loops:
            p = loop.vert.co
            t = (p.dot(BANDS_ALONG) + 1) / 2
            # Wrap-safe: the stripes repeat, so u never needs to jump inside one face.
            u = (t * STRIPES) % 1.0
            loop[uv].uv = (u, RAINBOW_V[0] + (RAINBOW_V[1] - RAINBOW_V[0]) * (0.3 + 0.4 * t))
        us = [lp[uv].uv[0] for lp in f.loops]
        if max(us) - min(us) > 0.5:  # a face across a wrap: pull its low corners up by 1
            for lp in f.loops:
                if lp[uv].uv[0] < 0.5:
                    lp[uv].uv = (lp[uv].uv[0] + 1, lp[uv].uv[1])
    return new_object("RainbowShell", bm, mat)


def boing_ring(mat, points=12, inner=0.62, band=0.12, spike=0.42, depth=0.05):
    """A flat star-burst ring: an annulus from `inner` to inner + band, with `points` spikes
    out to 1 + spike * 0.3 (unit radius at the spikes' base), a thin white core line."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    n = points * 4
    outer_pts, inner_pts = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = i % 4
        r = inner + band + (spike if k == 0 else (spike * 0.35 if k == 2 else 0.0))
        outer_pts.append((math.cos(a) * r, math.sin(a) * r))
        inner_pts.append((math.cos(a) * inner, math.sin(a) * inner))
    scale = 1.0 / (inner + band + spike)
    top_o = [bm.verts.new((x * scale, y * scale, depth / 2)) for x, y in outer_pts]
    top_i = [bm.verts.new((x * scale, y * scale, depth / 2)) for x, y in inner_pts]
    bot_o = [bm.verts.new((x * scale, y * scale, -depth / 2)) for x, y in outer_pts]
    bot_i = [bm.verts.new((x * scale, y * scale, -depth / 2)) for x, y in inner_pts]

    def face(vs, v):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[uv].uv = (0.5, v)
    for i in range(n):
        j = (i + 1) % n
        face((top_i[i], top_o[i], top_o[j], top_i[j]), BOING_V)
        face((bot_i[j], bot_o[j], bot_o[i], bot_i[i]), BOING_V)
        face((top_o[i], bot_o[i], bot_o[j], top_o[j]), BOING_V)
        face((top_i[j], bot_i[j], bot_i[i], top_i[i]), CORE_V)
    return new_object("BoingRing", bm, mat, smooth=False)


def build():
    common.clear_scene()
    mat = common.image_material("SuperBounce", texture(), roughness=0.35)
    objects = [shell(mat), boing_ring(mat)]
    print("SuperBounce triangles:", common.triangles(objects))
    objects[1].location = (2.6, 0, 0)
    common.render_preview(os.path.join(OUT, "renders", "set.png"), size=640, distance=6.0,
                          elevation=35, azimuth=20, target=(1.3, 0, 0))
    for obj in objects:
        obj.location = (0, 0, 0)
    common.export_glb(os.path.join(OUT, "SuperBounce.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "SuperBounce.blend"))


if __name__ == "__main__":
    build()
