"""Steel Ball, second look (the designer, 2026-10-09: Gyro's steel ball, "its a simple hexagonal
shape on two ends with line engravings, make sure its a lime saturated green", shiny): a glossy
lime ball drawn by a PBR SurfaceAppearance on a plain sphere.

  SteelShellV2  a UV sphere of unit radius (the cue ball's overlay, scaled at runtime). Its UV
                poles lie on Blender's X axis, so the hexagons (on Z) sit on clean texels.

The relief is a height field defined on the ball's directions (nothing stretches near the UV
poles):
  * a raised hexagon plate on each end (+Z and -Z), bevelled, with an engraved outline at its
    foot and a second line just inside its rim;
  * from each corner of the top hexagon an engraved line sweeps down round the ball, turning
    TwistDegrees on the way, to the matching corner of the bottom one (the bottom hexagon is
    turned to meet them);
  * an engraved ring round the middle.

Maps (textures/, 1024 x 512, equirectangular around X; Roblox caps images at 1024):
  shell_color.png      saturated lime, a lighter lime on the plates, dark green in the lines
  shell_normal.png     tangent space, OpenGL (+Y up, what Roblox reads), from the height field
                       sampled a step east and north of each texel's direction
  shell_metalness.png  a little metal (the colour stays saturated under white highlights)
  shell_roughness.png  glossy, rougher in the lines
  shell_preview.png    the colour lit from above, to compare quickly

Run headless or through the MCP (exec with EIGHTBALL_ROOT set):
  /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/steelball_v2.py
"""

import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else
                os.path.join(os.environ.get("EIGHTBALL_ROOT", ""), "tools", "blender", "abilities"))
import common  # noqa: E402

OUT = common.asset_dir("SteelBall")
W, H = 1024, 512

HEX_INRADIUS = 0.40  # the hexagon's inradius on the plane touching the pole (gnomonic)
TWIST = math.radians(60)  # how far each line turns round the ball from top to bottom


def unit(v):
    v = np.asarray(v, dtype=float)
    return v / np.linalg.norm(v)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hex_sd(x, y, r):
    """Signed distance to a flat-sided hexagon of inradius r (negative inside), corners on the
    angles 0, 60, ... degrees."""
    out = np.full(np.shape(x), -np.inf)
    for k in range(3):
        a = k * math.pi / 3 + math.pi / 6
        out = np.maximum(out, np.abs(x * math.cos(a) + y * math.sin(a)))
    return out - r


def groove(dist, width):
    """An engraved line's depth share (1 on the line, 0 off it), soft over a pixel or two."""
    return 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.006, np.abs(dist))


def wrap(a):
    return (a + np.pi) % (2 * np.pi) - np.pi


def relief(d):
    """Per direction d (..., 3): height (radians, roughly), the engraved share (0..1), the
    raised share (0..1) and 1 (no background mask: kept for the maps' signature)."""
    shape = d.shape[:-1]
    z = np.clip(d[..., 2], -1, 1)
    theta = np.arccos(z)  # from the top pole
    phi = np.arctan2(d[..., 1], d[..., 0])
    h = np.zeros(shape)
    raised = np.zeros(shape)
    ink = np.zeros(shape)
    for sign, turn in ((1.0, 0.0), (-1.0, TWIST)):
        c = d[..., 2] * sign
        safe = np.where(c > 1e-3, c, 1e-3)
        x, y = d[..., 0] / safe, d[..., 1] * sign / safe
        ct, st = math.cos(-turn * sign), math.sin(-turn * sign)
        x, y = x * ct - y * st, x * st + y * ct
        hd = np.where(c > 0.3, hex_sd(x, y, HEX_INRADIUS) * c, 1.0)
        plate = 1 - smoothstep(-0.03, 0.0, hd)
        h += 0.030 * plate
        raised = np.maximum(raised, plate)
        ink = np.maximum(ink, groove(hd - 0.010, 0.026))  # the outline at its foot
        ink = np.maximum(ink, groove(hd + 0.060, 0.016))  # the line inside the rim
    # The corner lines: from the top hexagon's corners (angles 0, 60, ...) to the bottom's.
    top = math.atan(HEX_INRADIUS / math.cos(math.pi / 6)) + 0.02
    span = math.pi - 2 * top
    s = np.clip((theta - top) / span, 0, 1)
    on = (theta > top) & (theta < math.pi - top)
    for k in range(6):
        want = k * math.pi / 3 + TWIST * s
        dist = np.abs(wrap(phi - want)) * np.sin(theta)
        ink = np.maximum(ink, groove(dist, 0.020) * on)
    # The ring round the middle.
    ink = np.maximum(ink, groove(theta - math.pi / 2, 0.020))
    h -= 0.010 * ink
    return h, ink, raised, np.ones(shape)


def directions(lon, lat):
    """Poles on X: lat from the YZ plane toward +X, lon round X starting at +Z."""
    cl = np.cos(lat)
    return np.stack([np.sin(lat), -cl * np.sin(lon), cl * np.cos(lon)], axis=-1)


def maps():
    u = (np.arange(W) + 0.5) / W
    v = (np.arange(H) + 0.5) / H
    U, V = np.meshgrid(u, v)
    lon = U * 2 * math.pi - math.pi
    lat = math.pi / 2 - V * math.pi  # row 0 is the image's top (v = 1): lat +90
    d = directions(lon, lat)
    h, ink, raised, _ = relief(d)
    # The surface's tangents: east (lon growing, the u direction) and north (v, lat growing).
    eps = 0.0025
    east = directions(lon + eps / np.maximum(np.cos(lat), 1e-3), lat)
    north = directions(lon, lat + eps)
    he, _, _, _ = relief(east)
    hn, _, _, _ = relief(north)
    strength = 2.2
    dx = (he - h) / eps * strength
    dy = (hn - h) / eps * strength
    n = np.stack([-dx, -dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    normal = np.concatenate([n * 0.5 + 0.5, np.ones(h.shape + (1,))], axis=-1)

    lime = np.array([0.50, 0.90, 0.06])
    plate_col = np.array([0.66, 0.97, 0.20])
    line_col = np.array([0.05, 0.26, 0.02])
    col = lime[None, None, :] * np.ones(h.shape + (1,))
    col = col + (plate_col - lime) * raised[..., None]
    col = col + (line_col - col) * ink[..., None]
    color = np.concatenate([np.clip(col, 0, 1), np.ones(h.shape + (1,))], axis=-1)

    metal = 0.35 - 0.25 * ink
    rough = 0.12 - 0.03 * raised + 0.4 * ink
    gray = lambda x: np.concatenate([np.repeat(np.clip(x, 0, 1)[..., None], 3, axis=-1),
                                      np.ones(h.shape + (1,))], axis=-1)

    # A quick lit preview: the colour times a light from above-left plus a specular hint.
    light = unit((-0.4, 0.5, 0.75))
    lam = np.clip(n[..., 2] * 0.6 + 0.4, 0, 1)  # tangent-space z: how flat
    shade = 0.55 + 0.45 * np.clip(d @ light, 0, 1)
    prev = np.clip(col * (shade * lam)[..., None], 0, 1)
    preview = np.concatenate([prev, np.ones(h.shape + (1,))], axis=-1)
    return color, normal, gray(metal), gray(rough), preview


def build():
    common.clear_scene()
    color, normal, metal, rough, preview = maps()
    tex = os.path.join(OUT, "textures")
    imgs = {}
    for name, arr in (("shell_color", color), ("shell_normal", normal),
                      ("shell_metalness", metal), ("shell_roughness", rough),
                      ("shell_preview", preview)):
        imgs[name] = common.image_from_array(name, arr, os.path.join(tex, name + ".png"))
    for name in ("shell_normal", "shell_metalness", "shell_roughness"):
        imgs[name].colorspace_settings.name = "Non-Color"

    # The sphere, its UV poles on X: lon round X from +Z, lat toward +X.
    segs, rings = 96, 48
    verts, uvs, faces = [], [], []
    for j in range(rings + 1):
        lat = -math.pi / 2 + math.pi * j / rings
        for i in range(segs + 1):
            lon = -math.pi + 2 * math.pi * i / segs
            cl = math.cos(lat)
            verts.append((math.sin(lat), -cl * math.sin(lon), cl * math.cos(lon)))
            uvs.append((i / segs, j / rings))
    for j in range(rings):
        for i in range(segs):
            a = j * (segs + 1) + i
            b, c, e = a + 1, a + segs + 2, a + segs + 1
            faces.append((a, b, c, e))
    mesh = bpy.data.meshes.new("SteelShellV2")
    mesh.from_pydata(verts, [], faces)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = uvs[mesh.loops[li].vertex_index]
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.validate()
    obj = bpy.data.objects.new("SteelShellV2", mesh)
    bpy.context.scene.collection.objects.link(obj)

    mat = bpy.data.materials.new("SteelShellV2")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")

    def tex_node(img):
        t = nodes.new("ShaderNodeTexImage")
        t.image = img
        return t

    links.new(tex_node(imgs["shell_color"]).outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex_node(imgs["shell_metalness"]).outputs["Color"], bsdf.inputs["Metallic"])
    links.new(tex_node(imgs["shell_roughness"]).outputs["Color"], bsdf.inputs["Roughness"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(tex_node(imgs["shell_normal"]).outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT, "SteelBallV2.glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB",
                              export_yup=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "SteelBallV2.blend"))
    print("wrote", path)


build()
