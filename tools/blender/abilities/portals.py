"""Portals (ABILITIES_PROMPT 7.9, reference 05): the portal ring lying on the cloth, and its
swirl, sparkle and burst images.

  PortalRim    a ragged energy rim: a torus of unit radius in Blender's XY plane (flat on the
               cloth in Roblox), its tube pushed in and out by noise round the ring and across
               it, so the edge is torn like the reference's. Drawn as glowing Neon in the
               portal's colour.
  PortalCore   a thin, smoother white-hot ring just inside the rim.
  PortalDisc   a flat disc of unit radius, UV-mapped square over it, for the swirl images (the
               look spins it).

Rendered images (textures/, RGBA, made in numpy):
  swirl.png          the inner disc: a dark blue-black middle with pale blue spiral arms curling
                     in, brighter toward the rim, fading out past it.
  sparkles.png       streaks and dots along the same spiral (spun faster over the swirl, they
                     read as sparkles streaming in).
  burst_ring.png     a thin bright ring with a soft blue glow either side (a ball coming out).

Run headless or through the MCP.
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

OUT = common.asset_dir("Portals")


def smooth_noise(rng, n, octaves):
    """A periodic 1D noise of length n: a few random sine octaves."""
    t = np.arange(n) / n * 2 * math.pi
    out = np.zeros(n)
    for k in range(1, octaves + 1):
        freq = 2 ** k + rng.integers(0, 3)
        out += rng.uniform(0.5, 1.0) / k * np.sin(freq * t + rng.uniform(0, 2 * math.pi))
    return out / np.abs(out).max()


def torus(name, major, minor, segs, sides, rough, seed, mat):
    """A torus in XY with its tube radius pushed by noise round the ring (and a little across
    it), so the rim is ragged."""
    rng = np.random.default_rng(seed)
    along = smooth_noise(rng, segs, 6)
    # Fine tearing: a jag per segment, smoothed once so it is torn, not spiky.
    raw = rng.uniform(-1, 1, segs)
    jag = (raw + np.roll(raw, 1) + np.roll(raw, -1)) / 3 * 0.8
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    rings = []
    for i in range(segs):
        a = i / segs * 2 * math.pi
        ca, sa = math.cos(a), math.sin(a)
        r_tube = minor * (1 + rough * (0.7 * along[i] + jag[i]))
        ring = []
        for j in range(sides):
            b = j / sides * 2 * math.pi
            # Flattened across (the rim lies on the cloth): wider in the plane than up.
            w = r_tube * math.cos(b)
            h = r_tube * 0.45 * math.sin(b)
            ring.append(bm.verts.new(((major + w) * ca, (major + w) * sa, h)))
        rings.append(ring)
    for i in range(segs):
        nxt = (i + 1) % segs
        for j in range(sides):
            k = (j + 1) % sides
            f = bm.faces.new((rings[i][j], rings[nxt][j], rings[nxt][k], rings[i][k]))
            for loop, (u, v) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv].uv = (u / segs, v / sides)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def disc(name, segs, mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    centre = bm.verts.new((0, 0, 0))
    edge = [bm.verts.new((math.cos(i / segs * 2 * math.pi), math.sin(i / segs * 2 * math.pi), 0))
            for i in range(segs)]
    for i in range(segs):
        a, b = edge[i], edge[(i + 1) % segs]
        f = bm.faces.new((centre, a, b))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x * 0.5 + 0.5, co.y * 0.5 + 0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def polar(size):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    return np.sqrt(x ** 2 + y ** 2), np.arctan2(y, x)


def swirl_image(size=512):
    r, th = polar(size)
    rng = np.random.default_rng(5)
    # Spiral arms: bright where theta + k * log(r) lines up, several arms.
    arms = 4
    phase = th * arms + 9.0 * np.log(np.maximum(r, 0.02))
    band = 0.5 + 0.5 * np.cos(phase)
    band = band ** 7
    # Soft cloudy variation (coarse noise, blown up and blurred), not salt or stripes.
    coarse = rng.uniform(0, 1, (size // 16, size // 16))
    cloud = np.kron(coarse, np.ones((16, 16)))
    for axis in (0, 1):
        acc = np.zeros_like(cloud)
        for k in range(-8, 9):
            acc += np.roll(cloud, k, axis=axis)
        cloud = acc / 17
    grain = 0.55 + 0.45 * cloud
    light = band * grain * np.clip((r - 0.1) / 0.75, 0, 1) ** 1.4
    # A brighter band toward the rim (the reference's lit inner edge).
    light = np.maximum(light, np.exp(-((r - 0.9) / 0.09) ** 2) * 0.55 * grain)
    colour = np.zeros((size, size, 4))
    deep = np.array([0.02, 0.04, 0.16])
    pale = np.array([0.55, 0.8, 1.0])
    k = np.clip(light * 1.3, 0, 1)[..., None]
    colour[..., 0:3] = deep + (pale - deep) * k
    # Opaque inside, fading out past the rim.
    colour[..., 3] = np.clip((1.02 - r) / 0.1, 0, 1)
    return common.image_from_array("PortalSwirl", colour, os.path.join(OUT, "textures", "swirl.png"))


def sparkle_image(size=512):
    r, th = polar(size)
    rng = np.random.default_rng(9)
    img = np.zeros((size, size, 4))
    alpha = np.zeros((size, size))
    # Short streaks along the spiral: points placed on spiral arms, each a small elongated blob.
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    for _ in range(170):
        rr = rng.uniform(0.18, 0.95)
        base = rng.uniform(0, 2 * math.pi)
        # Along the spiral's tangent (the same curl as the swirl).
        t = base
        px, py = rr * math.cos(t), rr * math.sin(t)
        # The spiral heading: mostly round, a little inward.
        tx, ty = -math.sin(t) - 0.25 * math.cos(t), math.cos(t) - 0.25 * math.sin(t)
        tl = math.hypot(tx, ty)
        tx, ty = tx / tl, ty / tl
        dx, dy = x - px, y - py
        along = dx * tx + dy * ty
        across = -dx * ty + dy * tx
        length = rng.uniform(0.015, 0.06) * (0.4 + rr)
        width = 0.004 + 0.004 * rr
        blob = np.exp(-(along / length) ** 2 - (across / width) ** 2)
        alpha = np.maximum(alpha, blob * rng.uniform(0.5, 1.0))
    alpha *= np.clip((1.0 - r) / 0.08, 0, 1)
    img[..., 0:3] = np.array([0.85, 0.95, 1.0])
    img[..., 3] = np.clip(alpha * 1.4, 0, 1)
    return common.image_from_array("PortalSparkles", img,
                                   os.path.join(OUT, "textures", "sparkles.png"))


def burst_image(size=256):
    r, _ = polar(size)
    ring = np.exp(-((r - 0.8) / 0.03) ** 2)
    glow = np.exp(-((r - 0.8) / 0.12) ** 2) * 0.55
    a = np.clip(ring + glow, 0, 1) * (r < 1)
    img = np.zeros((size, size, 4))
    white = np.clip(ring * 1.2, 0, 1)
    for ch, (lo, hi) in enumerate(zip((0.25, 0.6, 1.0), (1.0, 1.0, 1.0))):
        img[..., ch] = lo + (hi - lo) * white
    img[..., 3] = a
    return common.image_from_array("PortalBurst", img,
                                   os.path.join(OUT, "textures", "burst_ring.png"))


def preview_on_black(name):
    img = bpy.data.images.load(os.path.join(OUT, "textures", name + ".png"))
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    rgb = px[:, :, :3] * px[:, :, 3:4]
    out = np.concatenate([rgb, np.ones((h, w, 1))], axis=2)
    prev = bpy.data.images.new(name + "_prev", width=w, height=h, alpha=True)
    prev.pixels.foreach_set(out.astype(np.float32).ravel())
    prev.filepath_raw = os.path.join(OUT, "renders", name + ".png")
    prev.file_format = "PNG"
    prev.save()


def solid(name, colour):
    img = np.ones((8, 8, 4))
    img[:, :, 0:3] = colour
    return common.image_from_array(name, img, os.path.join(OUT, "textures", name + ".png"))


def build():
    common.clear_scene()
    swirl = swirl_image()
    sparkle_image()
    burst_image()
    for name in ("swirl", "sparkles", "burst_ring"):
        preview_on_black(name)

    rim_mat = common.image_material("PortalRimMat", solid("rim", (0.35, 0.75, 1.0)), emission=1.0)
    core_mat = common.image_material("PortalCoreMat", solid("core", (1.0, 1.0, 1.0)), emission=1.0)
    disc_mat = common.image_material("PortalDiscMat", swirl, emission=1.0, alpha=True)
    rim = torus("PortalRim", 1.0, 0.06, 160, 6, 0.6, 3, rim_mat)
    core = torus("PortalCore", 0.95, 0.025, 128, 5, 0.5, 8, core_mat)
    d = disc("PortalDisc", 48, disc_mat)
    d.location.z = -0.01
    objects = [rim, core, d]
    print("Portals triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 4) for v in o.dimensions))
    common.render_preview(os.path.join(OUT, "renders", "portal.png"), size=640, distance=3.4,
                          elevation=55, azimuth=20)
    common.export_glb(os.path.join(OUT, "Portals.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Portals.blend"))


build()
