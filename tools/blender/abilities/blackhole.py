"""Black Hole (ABILITIES_PROMPT 7.12, reference 08 and a real black hole): the hole standing
over the cloth, and the dark vortex on the cloth under it.

  BHHorizon    the event horizon: a pure black sphere of unit radius.
  BHPhoton     the photon ring: a smooth torus just outside it (radius 1.08, tube 0.06) in Blender's
               XZ plane (it faces Roblox -Z; the look turns it to face the camera), drawn as
               white-hot Neon.
  BHLens       the lensed light round the shadow: an annulus from 1.0 to 1.6 in the same plane,
               two-sided, UV-mapped square over it, for lens.png (the look turns it with the
               photon ring: the far side of the disk bent up over the top and under the bottom).
  BHDisk       the accretion disk: an annulus from 1.25 to 2.6 in Blender's XY plane (flat on the
               cloth in Roblox; the look tilts and spins it), two-sided, UV-mapped square, for
               disk.png.
  BHVortex     a flat unit disc in XY (UV square) for vortex.png, spun on the cloth.

Rendered images (textures/, RGBA, made in numpy):
  disk.png     the disk's hot gas: a blue-white inner edge, white-gold, orange only in the outer
               30%, fading out; streaks curling in along a spiral, cloudy.
  lens.png     the lensed disk: thin white-gold arcs over and under the shadow (1.05 to 1.5
               radii), the left side twice as bright (Doppler beaming), the right dim.
  vortex.png   reference 08: a black core with blue clouds spiralling in, fading out in blue.
  pop_ring.png a thin white ring with a pale blue glow (the collapse's pop).

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

OUT = common.asset_dir("BlackHole")


def link(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def sphere(name, mat, segs=32, rings=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    for f in bm.faces:
        f.smooth = True
    return link(name, bm, mat)


def torus(name, major, minor, segs, sides, mat, plane="XZ"):
    bm = bmesh.new()
    rings = []
    for i in range(segs):
        a = i / segs * 2 * math.pi
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for j in range(sides):
            b = j / sides * 2 * math.pi
            w = minor * math.cos(b)
            h = minor * math.sin(b)
            x, y, z = (major + w) * ca, (major + w) * sa, h
            ring.append(bm.verts.new((x, z, y) if plane == "XZ" else (x, y, z)))
        rings.append(ring)
    for i in range(segs):
        nxt = (i + 1) % segs
        for j in range(sides):
            k = (j + 1) % sides
            f = bm.faces.new((rings[i][j], rings[nxt][j], rings[nxt][k], rings[i][k]))
            f.smooth = True
    bm.normal_update()
    return link(name, bm, mat)


def annulus(name, inner, outer, segs, mat, plane):
    """A flat ring, both sides, UVs square over [-outer, outer]."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()

    def pos(r, a):
        x, y = r * math.cos(a), r * math.sin(a)
        return (x, 0.0, y) if plane == "XZ" else (x, y, 0.0)

    for flip in (False, True):
        ins = [bm.verts.new(pos(inner, i / segs * 2 * math.pi)) for i in range(segs)]
        outs = [bm.verts.new(pos(outer, i / segs * 2 * math.pi)) for i in range(segs)]
        for i in range(segs):
            j = (i + 1) % segs
            quad = [ins[i], outs[i], outs[j], ins[j]]
            if flip:
                quad.reverse()
            f = bm.faces.new(quad)
            for loop in f.loops:
                co = loop.vert.co
                u, v = (co.x, co.z) if plane == "XZ" else (co.x, co.y)
                loop[uv].uv = (u / outer * 0.5 + 0.5, v / outer * 0.5 + 0.5)
    return link(name, bm, mat)


def disc(name, segs, mat):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new()
    centre = bm.verts.new((0, 0, 0))
    edge = [bm.verts.new((math.cos(i / segs * 2 * math.pi), math.sin(i / segs * 2 * math.pi), 0))
            for i in range(segs)]
    for i in range(segs):
        f = bm.faces.new((centre, edge[i], edge[(i + 1) % segs]))
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x * 0.5 + 0.5, co.y * 0.5 + 0.5)
    return link(name, bm, mat)


def polar(size):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    return np.sqrt(x ** 2 + y ** 2), np.arctan2(y, x)


def clouds(rng, size, cell, passes=8):
    coarse = rng.uniform(0, 1, (size // cell, size // cell))
    cloud = np.kron(coarse, np.ones((cell, cell)))
    for axis in (0, 1):
        acc = np.zeros_like(cloud)
        for k in range(-passes, passes + 1):
            acc += np.roll(cloud, k, axis=axis)
        cloud = acc / (2 * passes + 1)
    return (cloud - cloud.min()) / (cloud.max() - cloud.min() + 1e-9)


def ramp(t, stops):
    """Colour along t in [0, 1] through (position, rgb) stops."""
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        k = np.clip((t - p0) / (p1 - p0), 0, 1)[..., None]
        inside = ((t >= p0) & (t <= p1))[..., None]
        out = np.where(inside, np.array(c0) + (np.array(c1) - np.array(c0)) * k, out)
    out = np.where((t < stops[0][0])[..., None], np.array(stops[0][1]), out)
    out = np.where((t > stops[-1][0])[..., None], np.array(stops[-1][1]), out)
    return out


def disk_image(size=512, inner=1.25 / 2.6):
    r, th = polar(size)
    rng = np.random.default_rng(3)
    t = np.clip((r - inner) / (1 - inner), 0, 1)
    # Streaks curling in: a tight log spiral, many arms, cloud-modulated.
    phase = th * 7 + 14.0 * np.log(np.maximum(r, 0.05))
    streak = 0.65 + 0.35 * (0.5 + 0.5 * np.cos(phase)) ** 3
    cloud = 0.6 + 0.4 * clouds(rng, size, 16)
    heat = streak * cloud
    # White-gold, a blue-white inner edge, orange only in the outer 30%.
    colour = ramp(t, [
        (0.0, (0.7, 0.85, 1.0)),
        (0.1, (0.9, 0.95, 1.0)),
        (0.22, (1.0, 0.95, 0.82)),
        (0.7, (1.0, 0.86, 0.6)),
        (1.0, (1.0, 0.5, 0.15)),
    ]) * heat[..., None]
    alpha = np.clip((r - inner) / 0.015, 0, 1) * np.clip((1 - r) / 0.3, 0, 1) ** 1.3
    alpha = alpha * (0.55 + 0.45 * heat)
    img = np.zeros((size, size, 4))
    img[..., 0:3] = np.clip(colour, 0, 1)
    img[..., 3] = np.clip(alpha, 0, 1)
    return common.image_from_array("BHDiskGas", img, os.path.join(OUT, "textures", "disk.png"))


def lens_image(size=512, inner=1.0 / 1.6):
    r, th = polar(size)
    rr = r / inner  # in horizon radii
    # The lensed disk: a few thin arcs, strongest over and under the shadow (|sin| high),
    # thinning toward the sides, the innermost hugging it.
    vert = np.abs(np.sin(th)) ** 0.6
    arcs = np.zeros_like(r)
    for radius, width, gain in ((1.06, 0.02, 1.0), (1.16, 0.03, 0.8), (1.3, 0.05, 0.55),
                                (1.45, 0.07, 0.3)):
        arcs += np.exp(-((rr - radius) / width) ** 2) * gain * (0.35 + 0.65 * vert)
    # Doppler beaming: the left side (coming toward us) twice the right.
    beam = 0.7 + 0.3 * np.cos(th - math.pi)
    beam = beam / beam.max() * 1.0
    beam = np.where(np.cos(th) < 0, beam, 0.4 + 0.6 * beam)
    light = np.clip(arcs * beam * 1.3, 0, 1) * (r >= inner) * (r < 1)
    light *= np.clip((1 - r) / 0.08, 0, 1)
    colour = ramp(np.clip(1 - arcs, 0, 1), [(0.0, (1.0, 0.98, 0.92)), (1.0, (1.0, 0.82, 0.5))])
    img = np.zeros((size, size, 4))
    img[..., 0:3] = colour
    img[..., 3] = light
    return common.image_from_array("BHLensLight", img, os.path.join(OUT, "textures", "lens.png"))


def vortex_image(size=512):
    r, th = polar(size)
    rng = np.random.default_rng(8)
    arms = 3
    phase = th * arms + 7.0 * np.log(np.maximum(r, 0.02))
    band = (0.5 + 0.5 * np.cos(phase)) ** 2
    cloud = clouds(rng, size, 32, 12)
    fine = clouds(np.random.default_rng(12), size, 8, 4)
    light = band * (0.45 + 0.55 * cloud) * (0.8 + 0.2 * fine)
    light *= np.clip((r - 0.28) / 0.35, 0, 1)
    colour = ramp(np.clip(light * 1.4, 0, 1), [
        (0.0, (0.0, 0.0, 0.02)),
        (0.35, (0.03, 0.12, 0.35)),
        (0.7, (0.15, 0.45, 0.85)),
        (1.0, (0.6, 0.85, 1.0)),
    ])
    # The rim fades out in blue, not a dark smudge: past r 0.7 the black core blends to blue.
    rim = np.clip((r - 0.7) / 0.3, 0, 1)[..., None]
    colour = colour * (1 - rim) + np.maximum(colour, np.array([0.1, 0.3, 0.7])) * rim
    alpha = np.clip((1.0 - r) / 0.3, 0, 1) ** 1.5
    img = np.zeros((size, size, 4))
    img[..., 0:3] = colour
    img[..., 3] = alpha
    return common.image_from_array("BHVortexClouds", img,
                                   os.path.join(OUT, "textures", "vortex.png"))


def pop_image(size=256):
    r, _ = polar(size)
    ring = np.exp(-((r - 0.8) / 0.03) ** 2)
    glow = np.exp(-((r - 0.8) / 0.12) ** 2) * 0.6
    img = np.zeros((size, size, 4))
    white = np.clip(ring * 1.2, 0, 1)
    for ch, lo in enumerate((0.55, 0.8, 1.0)):
        img[..., ch] = lo + (1 - lo) * white
    img[..., 3] = np.clip(ring + glow, 0, 1) * (r < 1)
    return common.image_from_array("BHPop", img, os.path.join(OUT, "textures", "pop_ring.png"))


def solid(name, colour):
    img = np.ones((8, 8, 4))
    img[:, :, 0:3] = colour
    return common.image_from_array(name, img, os.path.join(OUT, "textures", name + ".png"))


def build():
    common.clear_scene()
    disk = disk_image()
    lens = lens_image()
    vortex = vortex_image()
    pop_image()
    black = common.image_material("BHBlack", solid("black", (0.0, 0.0, 0.0)), roughness=1.0)
    hot = common.image_material("BHHot", solid("hot", (1.0, 0.95, 0.85)), emission=1.0)
    disk_mat = common.image_material("BHDiskMat", disk, emission=1.0, alpha=True)
    lens_mat = common.image_material("BHLensMat", lens, emission=1.0, alpha=True)
    vortex_mat = common.image_material("BHVortexMat", vortex, alpha=True)
    horizon = sphere("BHHorizon", black)
    photon = torus("BHPhoton", 1.08, 0.06, 96, 8, hot)
    lensing = annulus("BHLens", 1.0, 1.6, 128, lens_mat, "XZ")
    accretion = annulus("BHDisk", 1.25, 2.6, 96, disk_mat, "XY")
    floor = disc("BHVortex", 64, vortex_mat)
    objects = [horizon, photon, lensing, accretion, floor]
    print("BlackHole triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 4) for v in o.dimensions))
    # Preview: the disk tilted, the lens and photon ring facing the camera, the vortex below.
    accretion.rotation_euler = (math.radians(-12), 0, 0)
    floor.scale = (6, 6, 6)
    floor.location.z = -1.2
    common.render_preview(os.path.join(OUT, "renders", "blackhole.png"), size=640, distance=9,
                          elevation=10, azimuth=0, background=(0.1, 0.35, 0.2, 1))
    accretion.rotation_euler = (0, 0, 0)
    floor.scale = (1, 1, 1)
    floor.location.z = 0
    common.export_glb(os.path.join(OUT, "BlackHole.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "BlackHole.blend"))


build()
