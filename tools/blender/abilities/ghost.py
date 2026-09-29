"""Ghost (ABILITIES_PROMPT 7.4): the little ghost, the wisp and the ripple.

  LittleGhost  a cartoon ghost about one unit tall: a round head flowing into a skirt with
               five scalloped tails, two little arms, big black oval eyes and a small "o"
               mouth on its front (Blender -Y, Roblox's LookVector). It pops out of the armed
               cue ball and circles it.
  GhostWisp    a flowing sheet one unit long along +X, wavy, narrowing to a point, both sides
               faced; its texture fades out along its length and to its edges (alpha). Two or
               three trail behind the cue ball, rippling.
  Ripple       a flat soft ring of unit radius (Blender's XY plane: flat on the cloth in
               Roblox) that spreads round a ball the cue ball passes through.

One small texture for all three (one material, alpha on): the rows by v are the ghost's body
(a cool white fading to pale blue down the skirt), the eyes' ink, the ripple's blue and the
wisp's soft gradient. Run headless or through the MCP.
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

OUT = common.asset_dir("Ghost")

BODY_TOP = "F6FBFF"
BODY_BOTTOM = "B9D6F5"
INK = "1B2030"
RIPPLE = "CFE6FF"
WISP = "E4F1FF"

# The texture's rows by v: the body from BODY_V[0] (the skirt's hem) to BODY_V[1] (the crown),
# the ink at INK_V, the ripple at RIPPLE_V, the wisp in WISP_V (u along its length, v across).
BODY_V = (0.62, 0.98)
INK_V = 0.52
RIPPLE_V = 0.42
WISP_V = (0.02, 0.3)


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)]) / 255.0


def texture():
    w, h = 128, 128
    img = np.zeros((h, w, 4))
    for row in range(h):
        v = 1 - (row + 0.5) / h
        for col in range(w):
            u = (col + 0.5) / w
            if v >= 0.58:
                t = np.clip((v - BODY_V[0]) / (BODY_V[1] - BODY_V[0]), 0, 1)
                img[row, col, :3] = hex_rgb(BODY_BOTTOM) * (1 - t) + hex_rgb(BODY_TOP) * t
                img[row, col, 3] = 1
            elif v >= 0.47:
                img[row, col, :3] = hex_rgb(INK)
                img[row, col, 3] = 1
            elif v >= 0.36:
                img[row, col, :3] = hex_rgb(RIPPLE)
                img[row, col, 3] = 1
            else:
                across = np.clip((v - WISP_V[0]) / (WISP_V[1] - WISP_V[0]), 0, 1)
                edge = 1 - abs(2 * across - 1) ** 2
                along = (1 - u) ** 1.3
                img[row, col, :3] = hex_rgb(WISP)
                img[row, col, 3] = np.clip(edge * along * 0.9, 0, 1)
    return common.image_from_array("Ghost", img, os.path.join(OUT, "textures", "ghost.png"))


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


def ellipsoid(bm, uv, centre, radii, v, segs=16, rings=10):
    """An ellipsoid added to `bm`, every face on texture row `v`."""
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = geom["verts"]
    for vert in verts:
        vert.co = (centre[0] + vert.co.x * radii[0], centre[1] + vert.co.y * radii[1],
                   centre[2] + vert.co.z * radii[2])
    faces = {f for vert in verts for f in vert.link_faces}
    for f in faces:
        for lp in f.loops:
            lp[uv].uv = (0.5, v)


def little_ghost(mat, segs=40, rings=26, tails=5):
    """The body revolved from a profile: a round crown (z 0.5) widening to a skirt whose hem
    dips in `tails` scallops (z about -0.5); the hem is closed by a slightly domed cap. Then the
    arms, the eyes and the mouth."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    grid = []
    for j in range(rings + 1):
        t = j / rings  # 0 at the crown, 1 at the hem
        grid_row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            if t < 0.5:  # the crown: a quarter circle, radius 0.42
                phi = (t / 0.5) * (math.pi / 2)
                r = 0.42 * math.sin(phi)
                z = 0.08 + 0.42 * math.cos(phi)
            else:  # the skirt: flares a little, the hem scalloped
                s = (t - 0.5) / 0.5
                r = 0.42 + 0.08 * s * s
                hem = -0.46 + 0.07 * math.cos(tails * a) * s ** 3
                z = 0.08 + (hem - 0.08) * s
            grid_row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        grid.append(grid_row)
    for j in range(rings):
        for i in range(segs):
            k = (i + 1) % segs
            f = bm.faces.new((grid[j][i], grid[j + 1][i], grid[j + 1][k], grid[j][k]))
            for lp in f.loops:
                zz = lp.vert.co.z
                lp[uv].uv = (0.5, BODY_V[0] + (BODY_V[1] - BODY_V[0]) * (zz + 0.5) / 1.0)
    # The hem's cap (a fan to a centre a little up inside).
    centre = bm.verts.new((0, 0, -0.36))
    hem = grid[rings]
    for i in range(segs):
        k = (i + 1) % segs
        f = bm.faces.new((hem[k], hem[i], centre))
        for lp in f.loops:
            lp[uv].uv = (0.5, BODY_V[0] + 0.02)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    # Arms: little rounded nubs out of the sides, reaching forward a touch.
    for side in (-1, 1):
        ellipsoid(bm, uv, (side * 0.47, -0.05, -0.02), (0.14, 0.09, 0.08), BODY_V[0] + 0.15)
    # Eyes: tall black ovals on the front (-Y), and a small round mouth under them.
    for side in (-1, 1):
        ellipsoid(bm, uv, (side * 0.14, -0.395, 0.2), (0.065, 0.035, 0.1), INK_V, segs=14, rings=8)
    ellipsoid(bm, uv, (0, -0.415, 0.02), (0.045, 0.025, 0.05), INK_V, segs=12, rings=6)
    # Unit height: crown 0.5, hem about -0.5.
    return new_object("LittleGhost", bm, mat)


def wisp(mat, n=24, width=0.34):
    """A wavy sheet along +X from 0 to 1, narrowing to a point, tilted 45 degrees round X so it
    reads from above and from the side; both sides faced."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    tilt = math.radians(45)
    # Each side gets its own vertices (a face over the same ones reversed is refused).
    sides = []
    for _ in range(2):
        a_side, b_side = [], []
        for i in range(n + 1):
            x = i / n
            y = 0.1 * math.sin(2 * math.pi * x * 1.2)
            z = 0.06 * math.sin(math.pi * x)
            half = width / 2 * (1 - x) ** 0.8 + 0.004
            dy, dz = half * math.cos(tilt), half * math.sin(tilt)
            a_side.append(bm.verts.new((x, y + dy, z + dz)))
            b_side.append(bm.verts.new((x, y - dy, z - dz)))
        sides.append((a_side, b_side))
    for i in range(n):
        u0, u1 = i / n, (i + 1) / n
        for flip, (a_side, b_side) in zip((False, True), sides):
            quad = (a_side[i], b_side[i], b_side[i + 1], a_side[i + 1])
            uvs = [(u0, WISP_V[1]), (u0, WISP_V[0]), (u1, WISP_V[0]), (u1, WISP_V[1])]
            if flip:
                quad = tuple(reversed(quad))
                uvs = list(reversed(uvs))
            f = bm.faces.new(quad)
            for lp, c in zip(f.loops, uvs):
                lp[uv].uv = c
    me = bpy.data.meshes.new("GhostWisp")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new("GhostWisp", me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ripple(mat, segs=48, inner=0.82, depth=0.03):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    outer_t, inner_t, outer_b, inner_b = [], [], [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        c, s = math.cos(a), math.sin(a)
        outer_t.append(bm.verts.new((c, s, depth / 2)))
        inner_t.append(bm.verts.new((c * inner, s * inner, depth / 2)))
        outer_b.append(bm.verts.new((c, s, -depth / 2)))
        inner_b.append(bm.verts.new((c * inner, s * inner, -depth / 2)))
    for i in range(segs):
        j = (i + 1) % segs
        for quad in ((inner_t[i], outer_t[i], outer_t[j], inner_t[j]),
                     (inner_b[j], outer_b[j], outer_b[i], inner_b[i]),
                     (outer_t[i], outer_b[i], outer_b[j], outer_t[j]),
                     (inner_t[j], inner_b[j], inner_b[i], inner_t[i])):
            f = bm.faces.new(quad)
            for lp in f.loops:
                lp[uv].uv = (0.5, RIPPLE_V)
    return new_object("Ripple", bm, mat)


def build():
    common.clear_scene()
    mat = common.image_material("Ghost", texture(), alpha=True, roughness=0.4)
    objects = [little_ghost(mat), wisp(mat), ripple(mat)]
    print("Ghost triangles:", common.triangles(objects))
    sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(-50), 0, math.radians(-25))
    bpy.context.scene.collection.objects.link(sun)
    objects[1].location = (0.7, 0, 0)
    objects[2].location = (-1.6, 0, -0.5)
    common.render_preview(os.path.join(OUT, "renders", "set.png"), size=640, distance=4.2,
                          elevation=20, azimuth=15, target=(0, 0, 0))
    bpy.data.objects.remove(sun, do_unlink=True)
    for obj in objects:
        obj.location = (0, 0, 0)
    common.export_glb(os.path.join(OUT, "Ghost.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Ghost.blend"))


if __name__ == "__main__":
    build()
