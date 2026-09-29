"""Black Flash (ABILITIES_PROMPT 7.11, reference 07): the black lightning bolts, the shattered
ball's shards, and the shockwave ring image.

  BFBolt1..BFBolt4   four thick jagged black bolts with side forks, radiating: the root (thick)
                     at Blender -X, the tip at +X, unit length along X (Roblox X), flat in
                     Blender's XY plane (Roblox XZ: the look rolls each to face the camera). Their
                     bounding box is centred on the origin (the jags reach the same either
                     side), so a MeshPart's centre is the bolt's middle and its root is half its
                     length back. The look draws them black Neon inside one red Highlight (the
                     red rim of the reference).
  Shard1..Shard12    a unit-radius ball shell 0.12 thick cut into 12 pieces (a spherical Voronoi
                     round 12 seed directions). UVs are the ball mesh's own (tools/gen_ball_mesh.py:
                     equirectangular, u = 0.5 at +X and growing toward Roblox +Z, v = 1 at the
                     top), so the look gives each shard the hit ball's TextureID and it wears the
                     ball's colour and number. Each shard's centre in the model is its offset from
                     the ball's centre.

Rendered images (textures/, RGBA, numpy):
  shock_ring.png   a red ring with a black edge inside it, soft outside (the shockwave).

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

OUT = common.asset_dir("BlackFlash")

CORE_R = 0.04
REACH = 0.14


def jagged(rng, a, b, steps, rough):
    pts = [np.array(a, float), np.array(b, float)]
    for _ in range(steps):
        out = [pts[0]]
        for p, q in zip(pts[:-1], pts[1:]):
            d = q - p
            n = np.array([-d[1], d[0]])
            mid = (p + q) / 2 + n * rng.uniform(-rough, rough)
            out += [mid, q]
        pts = out
    return pts


def bolt_paths(seed):
    """A radiating bolt: thick at the root (-0.5), tapering to a quarter at the tip (+0.5),
    with one or two thick forks leaning outward (fat strokes read from the table camera)."""
    rng = np.random.default_rng(seed)
    main = jagged(rng, (-0.5, 0.0), (0.5, 0.0), 5, 0.32)
    n = len(main)
    for i, p in enumerate(main):
        t = i / (n - 1)
        main[i] = np.array([p[0], p[1] * min(1.0, 6 * t)])  # the root on the axis
    main_r = [1.0 - 0.75 * (i / (n - 1)) for i in range(n)]
    forks = []
    count = rng.integers(1, 3)
    picks = sorted(rng.choice(np.arange(3, n - 6), size=count, replace=False))
    side = 1 if rng.uniform() < 0.5 else -1
    for i in picks:
        p = main[i]
        d = main[min(i + 2, n - 1)] - main[max(i - 2, 0)]
        d = d / (np.linalg.norm(d) + 1e-9)
        angle = rng.uniform(0.35, 0.8) * side
        side = -side
        c, s = math.cos(angle), math.sin(angle)
        fd = np.array([c * d[0] - s * d[1], s * d[0] + c * d[1]])
        length = rng.uniform(0.2, 0.35)
        path = jagged(rng, p, p + fd * length, 2, 0.3)
        m = len(path)
        base = main_r[i] * 0.7
        forks.append((path, [base * (1 - 0.7 * k / (m - 1)) + 0.1 for k in range(m)]))
    return (main, main_r), forks


def centred(main, forks):
    pts = list(main[0]) + [p for path, _ in forks for p in path]
    xs = np.array([p[0] for p in pts])
    ys = np.array([p[1] for p in pts])
    up, down = max(ys.max(), 1e-6), max(-ys.min(), 1e-6)
    lo, hi = xs.min(), xs.max()

    def fix(p):
        # Squeezed into [-0.5, 0.5] rather than clamped (a clamp stacks points into a blob).
        x = (p[0] - lo) / (hi - lo) - 0.5
        y = p[1] * (REACH / up if p[1] > 0 else REACH / down)
        return np.array([x, y])

    main = ([fix(p) for p in main[0]], main[1])
    forks = [([fix(p) for p in path], r) for path, r in forks]
    return main, forks


def tube(name, path, radii, r, mat, sides):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = r
    curve.bevel_resolution = max(0, sides // 4 - 1)
    curve.use_fill_caps = True
    curve.materials.append(mat)
    spline = curve.splines.new("POLY")
    spline.points.add(len(path) - 1)
    for pt, (p, share) in zip(spline.points, zip(path, radii)):
        pt.co = (p[0], p[1], 0.0, 1.0)
        pt.radius = share
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def join_mesh(name, objs, mat):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def bolt(index, seed, mat):
    main, forks = centred(*bolt_paths(seed))
    parts = [tube("m", main[0], main[1], CORE_R, mat, 4)]
    for path, radii in forks:
        parts.append(tube("f", path, radii, CORE_R, mat, 4))
    return join_mesh("BFBolt%d" % index, parts, mat)


def ball_uv(d):
    """The ball mesh's UV for a Blender direction d (Roblox X = Blender X, Roblox Y = Blender
    Z, Roblox Z = -Blender Y)."""
    rx, ry, rz = d[0], d[2], -d[1]
    lon = math.atan2(rz, rx)
    lat = math.asin(max(-1.0, min(1.0, ry)))
    return 0.5 + lon / (2 * math.pi), 0.5 + lat / math.pi


def shards(mat, count=12, segs=32, rings=16, thick=0.12, seed=7):
    """The shell cut into `count` pieces: each face of a UV sphere goes to its nearest seed
    direction; each piece gets its outer skin, its inner skin and the walls between."""
    rng = np.random.default_rng(seed)
    seeds = [v / np.linalg.norm(v) for v in rng.normal(size=(count, 3))]

    def dir_of(i, j):
        lat = -math.pi / 2 + math.pi * j / rings
        lon = -math.pi + 2 * math.pi * i / segs
        return np.array([math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)])

    cells = {k: [] for k in range(count)}
    for j in range(rings):
        for i in range(segs):
            quad = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
            mid = sum(dir_of(a, b) for a, b in quad)
            mid = mid / np.linalg.norm(mid)
            k = int(np.argmax([mid @ s for s in seeds]))
            cells[k].append(quad)
    objs = []
    for k in range(count):
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new()
        outer, inner = {}, {}

        def vert(store, key, radius):
            if key not in store:
                d = dir_of(*key)
                store[key] = bm.verts.new(tuple(d * radius))
            return store[key]

        edges = {}
        for quad in cells[k]:
            ov = [vert(outer, q, 1.0) for q in quad]
            iv = [vert(inner, q, 1.0 - thick) for q in quad]
            for verts, keys in ((ov, quad), (list(reversed(iv)), list(reversed(quad)))):
                try:
                    f = bm.faces.new(verts)
                except ValueError:
                    continue
                for loop, key in zip(f.loops, keys):
                    loop[uvl].uv = ball_uv(dir_of(*key))
            for a, b in zip(quad, quad[1:] + quad[:1]):
                e = (a, b)
                if (b, a) in edges:
                    del edges[(b, a)]
                else:
                    edges[e] = True
        # Walls on the piece's open edges (where it broke off).
        for a, b in edges:
            try:
                f = bm.faces.new((outer[b], outer[a], inner[a], inner[b]))
                for loop in f.loops:
                    loop[uvl].uv = (0.0, 0.5)
            except ValueError:
                pass
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        me = bpy.data.meshes.new("Shard%d" % (k + 1))
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        obj = bpy.data.objects.new("Shard%d" % (k + 1), me)
        bpy.context.scene.collection.objects.link(obj)
        objs.append(obj)
    return objs


def ring_image(size=256):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    r = np.sqrt(x * x + y * y)
    red = np.exp(-((r - 0.8) / 0.05) ** 2)
    black = np.exp(-((r - 0.7) / 0.04) ** 2)
    soft = np.exp(-((r - 0.86) / 0.07) ** 2) * 0.3
    a = np.clip(red + black + soft, 0, 1) * (r < 1)
    img = np.zeros((size, size, 4))
    k = np.clip(red + soft, 0, 1) / np.maximum(np.clip(red + soft + black, 1e-6, None), 1e-6)
    img[..., 0] = 1.0 * k
    img[..., 1] = 0.08 * k
    img[..., 2] = 0.1 * k
    img[..., 3] = a
    return common.image_from_array("ShockRing", img, os.path.join(OUT, "textures", "shock_ring.png"))


def build():
    common.clear_scene()
    ring_image()
    black = np.zeros((8, 8, 4))
    black[..., 3] = 1
    ink = common.image_from_array("BoltInk", black, os.path.join(OUT, "textures", "bolt_ink.png"))
    bolt_mat = common.image_material("BoltMat", ink, roughness=1.0)
    grey = np.ones((8, 8, 4)) * 0.8
    shard_mat = common.image_material("ShardMat",
                                      common.image_from_array("ShardGrey", grey,
                                                              os.path.join(OUT, "textures", "shard_grey.png")))
    bolts = [bolt(i + 1, 11 + 7 * i, bolt_mat) for i in range(4)]
    pieces = shards(shard_mat)
    objects = bolts + pieces
    print("BlackFlash triangles:", common.triangles(objects))
    for o in bolts:
        print(o.name, tuple(round(v, 4) for v in o.dimensions))
    for i, b in enumerate(bolts):
        b.location = (0, 0.4 * i - 0.6, 0.5)
    for p in pieces:
        p.location.x -= 1.8
    common.render_preview(os.path.join(OUT, "renders", "blackflash.png"), size=640, distance=4.2,
                          elevation=60, azimuth=0, background=(0.6, 0.1, 0.1, 1))
    for b in bolts:
        b.location = (0, 0, 0)
    for p in pieces:
        p.location.x += 1.8
    common.export_glb(os.path.join(OUT, "BlackFlash.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "BlackFlash.blend"))


build()
