"""Shared helpers for the cue package (assets/cue): the envelope from Shape.json, PNG writing,
reading images, rasterising the atlas, dilation, noise, and the headless scene helpers.

Headless-safe: bmesh and data calls only; the only operators used anywhere in the package are
glTF export/import, render and save. Numpy ships with Blender; nothing else is imported.

Units: studs. d is the distance from the tip toward the butt. Blender frame: the tip at the
origin, the cue along -Y, so a point at distance d and angle theta sits at
(r sin theta, -d, -r cos theta). theta = 0 is the UV seam, facing Blender -Z (Roblox local -Y,
down in the hand); theta runs seam -> +X -> +Z (the top) -> -X -> seam.
"""

import hashlib
import json
import math
import os
import struct
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
SHAPE_PATH = os.path.join(HERE, 'Shape.json')
PARAMETERS_PATH = os.path.join(HERE, 'Parameters.json')
BLEND_PATH = os.path.join(HERE, 'CueModel.blend')
SHAPE_SCHEMA = 1

# The mesh's regions (a face attribute), tip to butt. Zones are Shape.json's eight; the cap zone
# is split into the glossy sleeve, the rubber bumper's side and the flat end face.
REGIONS = ['tip', 'ferrule', 'shaft', 'joint', 'forearm', 'ring', 'wrap', 'cap', 'bumper', 'end']
REGION_ZONE = {'bumper': 'cap', 'end': 'cap'}


def zone_of(region):
    return REGION_ZONE.get(region, region)


def log(tag, *parts):
    print(tag, *parts, flush=True)


def fail(tag, message):
    print(tag, 'FAIL', message, flush=True)
    sys.exit(1)


def script_args():
    """The arguments after Blender's '--'."""
    argv = sys.argv
    return argv[argv.index('--') + 1:] if '--' in argv else []


# ---------------------------------------------------------------------------------------------
# Shape.json
# ---------------------------------------------------------------------------------------------

def load_shape(path=SHAPE_PATH):
    with open(path, 'rb') as handle:
        raw = handle.read()
    shape = json.loads(raw)
    assert shape.get('schema_version') == SHAPE_SCHEMA, ('Shape.json schema', shape.get('schema_version'))
    return shape, hashlib.sha256(raw).hexdigest()


class Envelope:
    """CueShape.radiusAt rebuilt exactly from the Profile rows in Shape.json (a piecewise-linear,
    never-decreasing radius), checked against the sampled envelope."""

    def __init__(self, shape):
        self.length = float(shape['length_studs'])
        tip, butt = shape['tip_diameter_studs'], shape['butt_diameter_studs']
        self.ends, self.radii = [], []
        for row in shape['profile']:
            self.ends.append(self.length * row['to'])
            self.radii.append((tip + (butt - tip) * row['taper']) / 2)
        self.tip_radius, self.butt_radius = tip / 2, butt / 2
        worst = max(abs(self(d) - r) for d, r in shape['envelope'])
        assert worst < 1e-9, ('the rebuilt envelope differs from Shape.json by', worst)

    def __call__(self, d):
        if d <= 0:
            return self.tip_radius
        if d >= self.length:
            return self.butt_radius
        start = 0.0
        for i, end in enumerate(self.ends):
            if d <= end:
                here = self.radii[i]
                there = self.radii[i + 1] if i + 1 < len(self.radii) else here
                k = (d - start) / (end - start) if end > start else 1.0
                return here + (there - here) * k
            start = end
        return self.radii[-1]


# ---------------------------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------------------------

def clean(value):
    """Round away float noise and never write -0.0."""
    if isinstance(value, float):
        return round(value, 9) + 0.0
    if isinstance(value, (list, tuple)):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()}
    return value


def write_json(path, data):
    with open(path, 'w') as handle:
        json.dump(clean(data), handle, indent=2, sort_keys=True)
        handle.write('\n')


def read_parameters():
    with open(PARAMETERS_PATH) as handle:
        return json.load(handle)


def write_png(path, array):
    """Write an 8-bit PNG (H x W, H x W x 3 or H x W x 4, row 0 at the top), deterministically."""
    a = np.ascontiguousarray(np.clip(array, 0, 255).astype(np.uint8))
    if a.ndim == 2:
        a = a[:, :, None]
    h, w, c = a.shape
    kind = {1: 0, 3: 2, 4: 6}[c]
    rows = np.concatenate([np.zeros((h, 1), np.uint8), a.reshape(h, w * c)], axis=1)
    body = zlib.compress(rows.tobytes(), 9)

    def chunk(tag, data):
        out = struct.pack('>I', len(data)) + tag + data
        return out + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'wb') as handle:
        handle.write(b'\x89PNG\r\n\x1a\n')
        handle.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, kind, 0, 0, 0)))
        handle.write(chunk(b'IDAT', body))
        handle.write(chunk(b'IEND', b''))


def read_image(path):
    """Any image Blender can open, as float RGBA 0..1, row 0 at the top, values as stored (no
    colour conversion)."""
    import bpy
    image = bpy.data.images.load(path, check_existing=False)
    try:
        image.colorspace_settings.name = 'Non-Color'
        w, h = image.size
        pixels = np.empty(w * h * 4, np.float32)
        image.pixels.foreach_get(pixels)
    finally:
        bpy.data.images.remove(image)
    return pixels.reshape(h, w, 4)[::-1].copy()


# ---------------------------------------------------------------------------------------------
# Scene helpers (the table package's pattern)
# ---------------------------------------------------------------------------------------------

def clear_scene(name):
    import bpy
    scene = bpy.context.scene
    for other in list(bpy.data.scenes):
        if other != scene:
            bpy.data.scenes.remove(other)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for pool in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
                 bpy.data.collections, bpy.data.worlds, bpy.data.images, bpy.data.node_groups):
        for block in list(pool):
            pool.remove(block)
    scene.name = name
    scene.unit_settings.system = 'NONE'
    scene.unit_settings.scale_length = 1.0
    return scene


def embed_scripts(names):
    import bpy
    for text_name in names:
        source = os.path.join(HERE, text_name)
        if not os.path.isfile(source):
            continue
        text = bpy.data.texts.get(text_name) or bpy.data.texts.new(text_name)
        text.clear()
        with open(source) as handle:
            text.write(handle.read())


def save_blend(path):
    import bpy
    bpy.ops.wm.save_as_mainfile(filepath=path, check_existing=False, compress=True)
    backup = path + '1'
    if os.path.exists(backup):
        os.remove(backup)  # a headless rebuild regenerates everything; no .blend1 residue


def load_cue_object():
    """Append the Cue object from CueModel.blend into the current file and return it."""
    import bpy
    with bpy.data.libraries.load(BLEND_PATH, link=False) as (src, dst):
        dst.objects = ['Cue']
    obj = dst.objects[0]
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------------------------
# The atlas: rasterise the mesh's UVs with the per-corner attributes CueModel stores
# ---------------------------------------------------------------------------------------------

def rasterize(obj, size):
    """Every atlas pixel centre inside a UV triangle gets that surface point's attributes:
    s (arc length along the profile from the tip), theta (0..2 pi from the seam), the 3D point,
    and the face's region. Returns a dict of H x W arrays plus 'mask' (covered) and 'overlap'
    (pixels strictly inside more than one triangle)."""
    mesh = obj.data
    n_loops = len(mesh.loops)
    uv = np.empty(n_loops * 2, np.float64)
    mesh.uv_layers['UVMap'].data.foreach_get('uv', uv)
    uv = uv.reshape(-1, 2)
    s = np.empty(n_loops, np.float64)
    mesh.attributes['cue_s'].data.foreach_get('value', s)
    th = np.empty(n_loops, np.float64)
    mesh.attributes['cue_theta'].data.foreach_get('value', th)
    region = np.empty(len(mesh.polygons), np.int64)
    mesh.attributes['cue_region'].data.foreach_get('value', region)
    vidx = np.empty(n_loops, np.int64)
    mesh.loops.foreach_get('vertex_index', vidx)
    co = np.empty(len(mesh.vertices) * 3, np.float64)
    mesh.vertices.foreach_get('co', co)
    co = co.reshape(-1, 3)
    loop_start = np.empty(len(mesh.polygons), np.int64)
    mesh.polygons.foreach_get('loop_start', loop_start)

    px = uv[:, 0] * size
    py = (1.0 - uv[:, 1]) * size
    out = {k: np.zeros((size, size), np.float64) for k in ('s', 'theta', 'x', 'y', 'z')}
    out['region'] = np.full((size, size), -1, np.int64)
    count = np.zeros((size, size), np.int32)
    for f, start in enumerate(loop_start):
        a, b, c = start, start + 1, start + 2
        xs, ys = px[[a, b, c]], py[[a, b, c]]
        x0, x1 = int(max(math.floor(xs.min() - 0.5), 0)), int(min(math.ceil(xs.max() + 0.5), size - 1))
        y0, y1 = int(max(math.floor(ys.min() - 0.5), 0)), int(min(math.ceil(ys.max() + 0.5), size - 1))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        det = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(det) < 1e-12:
            continue
        l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / det
        l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / det
        l2 = 1.0 - l0 - l1
        eps = 1e-9
        inside = (l0 >= -eps) & (l1 >= -eps) & (l2 >= -eps)
        strict = (l0 > 1e-6) & (l1 > 1e-6) & (l2 > 1e-6)
        if not inside.any():
            continue
        sub = (slice(y0, y1 + 1), slice(x0, x1 + 1))
        count[sub] += strict
        w = (l0[inside], l1[inside], l2[inside])
        iy, ix = np.nonzero(inside)
        iy, ix = iy + y0, ix + x0
        verts = vidx[[a, b, c]]
        for key, values in (('s', s[[a, b, c]]), ('theta', th[[a, b, c]]),
                            ('x', co[verts, 0]), ('y', co[verts, 1]), ('z', co[verts, 2])):
            out[key][iy, ix] = w[0] * values[0] + w[1] * values[1] + w[2] * values[2]
        out['region'][iy, ix] = region[f]
    out['mask'] = out['region'] >= 0
    out['overlap'] = count > 1
    out['d'] = -out['y']
    out['r'] = np.hypot(out['x'], out['z'])
    return out


def dilate(image, mask, minimum=8):
    """Bleed covered pixels outward until the whole image is filled (at least `minimum` px):
    each empty pixel next to a filled one takes the average of its filled neighbours."""
    img = image.astype(np.float64).copy()
    if img.ndim == 2:
        img = img[:, :, None]
    filled = mask.copy()
    img[~filled] = 0
    steps = 0
    while not filled.all():
        acc = np.zeros_like(img)
        n = np.zeros(filled.shape, np.float64)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                shifted_f = np.zeros_like(filled)
                shifted_i = np.zeros_like(img)
                ys = slice(max(dy, 0), filled.shape[0] + min(dy, 0))
                yd = slice(max(-dy, 0), filled.shape[0] + min(-dy, 0))
                xs = slice(max(dx, 0), filled.shape[1] + min(dx, 0))
                xd = slice(max(-dx, 0), filled.shape[1] + min(-dx, 0))
                shifted_f[yd, xd] = filled[ys, xs]
                shifted_i[yd, xd] = img[ys, xs]
                acc += shifted_i * shifted_f[:, :, None]
                n += shifted_f
        grow = (~filled) & (n > 0)
        if not grow.any():
            break
        img[grow] = acc[grow] / n[grow][:, None]
        filled = filled | grow
        steps += 1
    assert steps >= minimum or filled.all(), 'dilation stopped early'
    return img[:, :, 0] if image.ndim == 2 else img


# ---------------------------------------------------------------------------------------------
# Deterministic noise (value noise on an integer hash; no random module)
# ---------------------------------------------------------------------------------------------

def _hash3(ix, iy, iz, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263
         + iz.astype(np.int64) * 2147483647 + seed * 1013904223) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def noise3(x, y, z, seed=0):
    """Smooth value noise in 0..1 at float arrays x, y, z (period 1)."""
    ix, iy, iz = np.floor(x), np.floor(y), np.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    ux, uy, uz = (fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz))
    ix, iy, iz = ix.astype(np.int64), iy.astype(np.int64), iz.astype(np.int64)
    out = 0.0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                w = ((ux if dx else 1 - ux) * (uy if dy else 1 - uy) * (uz if dz else 1 - uz))
                out = out + w * _hash3(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(x, y, z, octaves=4, seed=0):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * noise3(x * 2 ** o, y * 2 ** o, z * 2 ** o, seed + 17 * o)
        norm += amp
        amp *= 0.5
    return total / norm


def hex_rgb(value):
    value = value.lstrip('#')
    return [int(value[i:i + 2], 16) for i in (0, 2, 4)]
