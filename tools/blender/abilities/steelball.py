"""Steel Ball (ABILITIES_PROMPT 7.10, reference 06): the green steel ball the cue ball becomes,
the golden spiral ribbons round it, and its images.

  SteelShell    a sphere of unit radius, UV-mapped (longitude, latitude), with the raised
                hexagon panel, the raised round panel, the carved grooves and the swirls pushed
                in and out of it; drawn with steel_shell.png, the halftone manga texture.
  (An inverted-hull outline, the same sphere inside out, drew solid black in Roblox, which
  ignores the flipped winding: the look draws the outline with a Highlight instead.)
  GoldSpiral    a flat golden-ratio spiral ribbon in Blender's XY plane (r = 1.1 x phi^(turns))
                over one and a half turns from just outside the ball, tapering to a point; UVs
                run along it (u) and across it (v) for gold_ribbon.png; both sides drawn.
                The look spins a few.

Rendered images (textures/, RGBA, made in numpy):
  steel_shell.png   the shell's texture: green with pale yellow-green flats, halftone dot
                    shading, and heavy black ink lines on the hexagon, the round panel, the
                    grooves and the swirls (equirectangular, 1024 x 512).
  gold_ribbon.png   across the ribbon: a white-hot core, gold, fading to clear at the edges.
  gold_path.png     a strip of golden spiral curls for the guided ball's path on the cloth
                    (tiles along its length).
  gold_burst.png    a gold ring with rays (a guided pot).
  gold_sparkle.png  a four-point star.

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

OUT = common.asset_dir("SteelBall")
PHI = (1 + math.sqrt(5)) / 2


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


# The panels' axes on the ball (Blender coordinates).
HEX_AXIS = unit((-0.45, -0.35, 0.82))
ROUND_AXIS = unit((0.62, -0.28, 0.45))
SWIRL_AXIS = unit((0.2, 0.75, -0.3))
GROOVES = [  # plane normal, the side it shows on (axis, min dot)
    (unit((0.15, 0.95, 0.25)), unit((0.3, -0.2, 0.9)), 0.1),
    (unit((0.9, 0.1, -0.35)), unit((-0.2, 0.3, -0.9)), 0.05),
    (unit((-0.3, 0.2, 0.93)), unit((0.1, 0.9, 0.3)), 0.25),
]


def basis(axis):
    helper = np.array([0.0, 0.0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    e1 = unit(np.cross(axis, helper))
    e2 = np.cross(axis, e1)
    return e1, e2


def gnomonic(d, axis):
    """(x, y, facing): d projected onto the plane touching the ball at `axis`."""
    e1, e2 = basis(axis)
    c = d @ axis
    safe = np.where(c > 1e-3, c, 1e-3)
    return (d @ e1) / safe, (d @ e2) / safe, c


def hex_sd(x, y, r):
    """Signed distance to a flat-sided hexagon of inradius r (negative inside)."""
    out = np.full(np.shape(x), -np.inf)
    for k in range(3):
        a = k * math.pi / 3 + math.pi / 6
        out = np.maximum(out, np.abs(x * math.cos(a) + y * math.sin(a)))
    return out - r


def features(d):
    """Per direction d (..., 3): the hexagon's and round panel's signed distances, the groove
    and swirl line distances (all roughly in radians on the ball)."""
    hx, hy, hc = gnomonic(d, HEX_AXIS)
    hexd = np.where(hc > 0.2, hex_sd(hx, hy, 0.72) * hc, 1.0)
    rc = np.clip(d @ ROUND_AXIS, -1, 1)
    roundd = np.arccos(rc) - 0.42
    groove = np.full(d.shape[:-1], 1.0)
    for normal, side, least in GROOVES:
        on = (d @ side) > least
        g = np.abs(d @ normal)
        # Stop the groove short of the panels (they sit on top).
        g = np.where(on & (hexd > 0.06) & (roundd > 0.06), g, 1.0)
        groove = np.minimum(groove, g)
    sx, sy, sc = gnomonic(d, SWIRL_AXIS)
    r = np.sqrt(sx * sx + sy * sy) + 1e-6
    th = np.arctan2(sy, sx)
    arms = 3
    phase = (th + 2.2 * np.log(r)) * arms / (2 * math.pi)
    frac = np.abs(phase - np.round(phase))
    swirl = np.where((sc > 0.35) & (r > 0.12) & (r < 0.9), frac * 2 * math.pi * r / arms * sc, 1.0)
    swirl = np.where((hexd > 0.05) & (roundd > 0.05), swirl, 1.0)
    return hexd, roundd, groove, swirl


def shell_texture(w=1024, h=512):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, Vv = np.meshgrid(u, v)
    lon = U * 2 * math.pi - math.pi
    lat = math.pi / 2 - Vv * math.pi  # row 0 is the image's top (v = 1): the north pole
    d = np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], axis=-1)
    hexd, roundd, groove, swirl = features(d)
    rng = np.random.default_rng(4)
    # Blotchy light and dark areas fixed on the ball (the manga's flat shading).
    blot = np.zeros(d.shape[:-1])
    for _ in range(9):
        c = unit(rng.normal(size=3))
        blot += rng.uniform(-1, 1) * np.exp(-((1 - d @ c) / rng.uniform(0.08, 0.3)))
    shade = 0.5 + 0.5 * (d @ unit((-0.3, -0.5, 0.8))) + 0.35 * blot
    # Emerald with cream highlights and deep shadow (the art director: the lime first tried
    # vanished into the felt; the reference is darker with heavy ink).
    green = np.array([0.18, 0.56, 0.12])
    pale = np.array([0.90, 0.95, 0.55])
    dark = np.array([0.063, 0.227, 0.047])
    ink = np.array([0.02, 0.05, 0.02])
    col = np.broadcast_to(green, d.shape).copy()
    col[shade > 0.95] = pale
    # Halftone dots on the dark side: a dot grid on the cube face each direction falls on (no
    # pinching at the poles as a grid in UV would).
    pitch = 0.07  # the dot spacing on the ball (radians, roughly): coarse, to read small
    ax = np.argmax(np.abs(d), axis=-1)
    big = np.take_along_axis(np.abs(d), ax[..., None], axis=-1)[..., 0]
    a1 = np.where(ax == 0, d[..., 1], d[..., 0]) / big
    a2 = np.where(ax == 2, d[..., 1], d[..., 2]) / big
    fa, fb = a1 / pitch, a2 / pitch
    gx, gy = fa - np.round(fa), fb - np.round(fb)
    dist = np.sqrt(gx * gx + gy * gy) * 2
    tone = np.clip((0.62 - shade) / 0.5, 0, 1)  # 0 light .. 1 dark
    dots = dist < np.sqrt(tone) * 1.05
    col[dots] = dark
    # The hexagon: a pale flat inside shading off into halftone toward one corner, a heavy
    # double ink line round it.
    inside = hexd < -0.02
    e1, e2 = basis(HEX_AXIS)
    across = d @ unit(0.8 * e1 - 0.6 * e2)
    inner_tone = np.clip((across - 0.05) / 0.45, 0, 1)
    col[inside] = pale * 0.95 + green * 0.05
    col[inside & (dist < np.sqrt(inner_tone) * 0.9)] = green
    col[(np.abs(hexd) < 0.035) | (np.abs(hexd + 0.09) < 0.016)] = ink
    # The round panel: mid green, a dark halftone crescent, an ink line.
    rin = roundd < -0.02
    crescent = rin & ((d @ unit((0.5, 0.3, -0.2))) > 0.35)
    col[rin & ~crescent & ~dots] = green * 1.1
    col[crescent & dots] = dark
    col[np.abs(roundd) < 0.032] = ink
    # Grooves: an ink channel with a pale lip beside it.
    col[(groove > 0.035) & (groove < 0.055)] = pale
    col[groove < 0.035] = ink
    # Swirls.
    col[swirl < 0.04] = ink
    # A solid black ink crescent on the far side from the hexagon (about a quarter of the
    # ball), edged in coarse halftone: the manga's heavy shadow.
    shadow = d @ unit((0.35, 0.55, -0.75))
    col[(shadow > 0.25) & (shadow <= 0.45) & dots] = ink
    col[(shadow > 0.25) & (shadow <= 0.45) & ~dots & (hexd > 0)] = dark
    col[shadow > 0.45] = ink
    rgba = np.concatenate([np.clip(col, 0, 1), np.ones(d.shape[:-1] + (1,))], axis=-1)
    return common.image_from_array("SteelShell", rgba, os.path.join(OUT, "textures", "steel_shell.png"))


def sphere(name, radius, segs, rings, mat, displace=False):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    grid = []
    for j in range(rings + 1):
        lat = -math.pi / 2 + math.pi * j / rings
        row = []
        for i in range(segs + 1):
            lon = -math.pi + 2 * math.pi * i / segs
            d = np.array([math.cos(lat) * math.cos(lon), math.cos(lat) * math.sin(lon), math.sin(lat)])
            r = radius
            if displace:
                hexd, roundd, groove, swirl = (float(np.ravel(x)[0]) for x in features(d[None, :]))
                # Raised panels and carved grooves, eased over their edges (no stair steps on
                # the grid).
                r += 0.025 * min(1.0, max(0.0, (-hexd) / 0.04))
                r += 0.018 * min(1.0, max(0.0, (-roundd) / 0.04))
                r -= 0.015 * min(1.0, max(0.0, (0.03 - groove) / 0.03))
            row.append((bm.verts.new(tuple(d * r)), (i / segs, j / rings)))
        grid.append(row)
    for j in range(rings):
        for i in range(segs):
            quad = [grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]]
            if j == 0:
                quad = [grid[j][i], grid[j + 1][i + 1], grid[j + 1][i]]
            elif j == rings - 1:
                quad = [grid[j][i], grid[j][i + 1], grid[j + 1][i]]
            try:
                f = bm.faces.new([q[0] for q in quad])
            except ValueError:
                continue
            for loop, q in zip(f.loops, quad):
                loop[uvl].uv = q[1]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def gold_spiral(name, mat, turns=1.5, steps=120, r0=1.1, width=0.6):
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new()
    pairs = []
    total = turns * 2 * math.pi
    for k in range(steps + 1):
        s = k / steps
        th = total * s
        r = r0 * PHI ** (th / (2 * math.pi))
        c, sn = math.cos(th), math.sin(th)
        # The outward normal of the curve in the plane (roughly radial).
        w = width * (1 - s) ** 0.7 * (0.6 + 0.4 * math.sin(math.pi * min(1, s * 4)))
        z = 0.08 * math.sin(th * 1.5)
        inner = bm.verts.new(((r - w / 2) * c, (r - w / 2) * sn, z))
        outer = bm.verts.new(((r + w / 2) * c, (r + w / 2) * sn, z))
        pairs.append((inner, outer, s))
    # Both sides (Roblox draws a face from its front only): the up face on these verts, the
    # down face on a copy of them.
    back = [(bm.verts.new(p[0].co), bm.verts.new(p[1].co), p[2]) for p in pairs]
    for k in range(steps):
        a, b = pairs[k], pairs[k + 1]
        f = bm.faces.new((a[0], a[1], b[1], b[0]))
        for loop, uv in zip(f.loops, ((a[2], 0), (a[2], 1), (b[2], 1), (b[2], 0))):
            loop[uvl].uv = uv
        a, b = back[k], back[k + 1]
        f = bm.faces.new((a[0], b[0], b[1], a[1]))
        for loop, uv in zip(f.loops, ((a[2], 0), (b[2], 0), (b[2], 1), (a[2], 1))):
            loop[uvl].uv = uv
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ribbon_image(w=256, h=64):
    """Across the ribbon: bright gold in the middle to orange, a dark brown edge line (it holds
    against the green cloth), clear past it; fading in at the ribbon's start."""
    v = (np.arange(h) + 0.5) / h
    across = np.abs(v * 2 - 1)[:, None] * np.ones((1, w))
    u = ((np.arange(w) + 0.5) / w)[None, :] * np.ones((h, 1))
    gold = np.array([1.0, 0.816, 0.25])
    orange = np.array([1.0, 0.54, 0.0])
    edge = np.array([0.54, 0.32, 0.0])
    k = np.clip(across / 0.75, 0, 1)[..., None]
    col = gold * (1 - k) + orange * k
    rim = (across > 0.75)[..., None]
    col = np.where(rim, edge, col)
    alpha = (across < 0.95) * np.clip(u * 8, 0, 1)
    rgba = np.concatenate([col, alpha[..., None]], axis=-1)
    return common.image_from_array("GoldRibbon", rgba, os.path.join(OUT, "textures", "gold_ribbon.png"))


def path_image(w=256, h=64):
    """A continuous looping gold line (a prolate trochoid: three loops a tile) with a dark
    brown edge, tiling along the path's length."""
    img = np.zeros((h, w, 4))
    py, px = np.mgrid[0:h, 0:w]
    x = (px + 0.5) / h  # in tile heights (the tile is 4 long)
    y = (py + 0.5) / h - 0.5
    loops = 3
    c = 4 / (loops * 2 * math.pi)
    t = np.linspace(-2 * math.pi, (loops + 1) * 2 * math.pi, 1600)
    cx = (c * t - 0.5 * np.sin(t)) % 4
    cy = 0.33 * np.cos(t)
    dist = np.full((h, w), 9.0)
    for sx, sy in zip(cx, cy):
        for shift in (-4, 0, 4):
            dd = (x - sx - shift) ** 2 + (y - sy) ** 2
            dist = np.minimum(dist, dd)
    dist = np.sqrt(dist)
    core = dist < 0.045
    edge = (dist >= 0.045) & (dist < 0.075)
    gold = np.array([1.0, 0.82, 0.25])
    brown = np.array([0.35, 0.23, 0.0])
    img[core, 0:3] = gold
    img[core, 3] = 1
    img[edge, 0:3] = brown
    img[edge, 3] = 0.8
    return common.image_from_array("GoldPath", img, os.path.join(OUT, "textures", "gold_path.png"))


def burst_image(size=256):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    ring = np.exp(-((r - 0.62) / 0.05) ** 2)
    rays = (0.5 + 0.5 * np.cos(th * 16)) ** 6 * np.exp(-((r - 0.6) / 0.3) ** 2) * (r < 0.98)
    core = np.exp(-(r / 0.25) ** 2) * 0.6
    a = np.clip(ring + rays * 0.9 + core, 0, 1)
    img = np.zeros((size, size, 4))
    hot = np.clip(ring + core, 0, 1)
    gold = np.array([1.0, 0.72, 0.15])
    for ch in range(3):
        img[..., ch] = gold[ch] + (1 - gold[ch]) * hot
    img[..., 3] = a
    return common.image_from_array("GoldBurst", img, os.path.join(OUT, "textures", "gold_burst.png"))


def sparkle_image(size=128):
    c = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(c, -c)
    star = np.exp(-(np.abs(x) / 0.06)) * np.exp(-(np.abs(y) / 0.7)) + np.exp(-(np.abs(y) / 0.06)) * np.exp(-(np.abs(x) / 0.7))
    dot = np.exp(-((x * x + y * y) / 0.02))
    a = np.clip(star + dot, 0, 1)
    img = np.zeros((size, size, 4))
    img[..., 0] = 1.0
    img[..., 1] = 0.85 + 0.15 * dot
    img[..., 2] = 0.45 + 0.55 * dot
    img[..., 3] = a
    return common.image_from_array("GoldSparkle", img, os.path.join(OUT, "textures", "gold_sparkle.png"))


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


def build():
    common.clear_scene()
    shell_img = shell_texture()
    ribbon = ribbon_image()
    path_image()
    burst_image()
    sparkle_image()
    for name in ("gold_ribbon", "gold_path", "gold_burst", "gold_sparkle"):
        preview_on_black(name)

    shell_mat = common.image_material("SteelShellMat", shell_img, emission=0.7, roughness=0.45)  # emission: the preview only
    gold_mat = common.image_material("GoldRibbonMat", ribbon, emission=1.0, alpha=True)
    shell = sphere("SteelShell", 1.0, 80, 48, shell_mat, displace=True)
    spiral = gold_spiral("GoldSpiral", gold_mat)
    objects = [shell, spiral]
    print("SteelBall triangles:", common.triangles(objects))
    for o in objects:
        print(o.name, tuple(round(v, 4) for v in o.dimensions))
    spiral.rotation_euler = (0.5, 0.2, 0)
    common.render_preview(os.path.join(OUT, "renders", "steelball.png"), size=640, distance=7.5,
                          elevation=25, azimuth=30)
    spiral.rotation_euler = (0, 0, 0)
    # Face on to the hexagon panel (the reference's view), for the art director.
    spiral.hide_render = True
    common.render_preview(os.path.join(OUT, "renders", "steelball_hex.png"), size=640, distance=4.2,
                          elevation=55.1, azimuth=-51.9)
    spiral.hide_render = False
    common.export_glb(os.path.join(OUT, "SteelBall.glb"), objects)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "SteelBall.blend"))


build()
