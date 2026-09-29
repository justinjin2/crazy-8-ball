"""Cue skins: turn a skin file (skins/<id>.json) into the atlas maps for the shared cue mesh.

    Blender -b --factory-startup --python-exit-code 1 --python assets/cue/CueTextures.py -- \
        --skin assets/cue/skins/<id>.json

writes textures/<id>_{color,normal,roughness,metalness}.png (1024, dilated) plus
textures/<id>_emissive.png when the skin has a glow key, then renders/<id>.png.
    ... -- --areas    renders/areas.png: each paint-kit panel's area in its own colour (sheet.png)

How it works: every atlas pixel is rasterised back to the point on the cue it shows (its arc
length s along the profile, its angle theta, its 3D point; cue_common.rasterize). That point
picks its panel and the panel pixel: x runs tip (left) to butt (right) over the panel's stretch
of the cue, y runs once round from the seam (top row) through the top of the cue (middle row)
back to the seam (bottom row), and cap_end is the butt's end face seen from behind with the top
up. So a panel lands on the cue unstretched, unmirrored and the right way up, whatever the atlas
layout is. Tip, ferrule and bumper are plain skin colours.

A skin with "procedural": "classic" is drawn by classic() instead of panels: the default cue as
a real one (maple, rosewood, Irish linen, silver, black sleeve, rubber), straight to the atlas,
with no lighting in the colour map. Headless-safe: data calls and render only.
"""

import json
import math
import os
import sys

sys.dont_write_bytecode = True

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

TAG = 'CUE textures'
TEXTURES = os.path.join(HERE, 'textures')

TEXTURE = {
    'size': 1024,
    'dilate_px': 8,  # at least; the whole atlas is filled from the nearest strip
    'flat_normal': (128, 128, 255),
    'key_softness': 0.25,  # a metal or glow key fades out over the last quarter of its tolerance
    # Irish linen wrap (every skin): threads wound round the cue, one pitch per turn. Real
    # linen is finer than a texel here, so the pitch is stylised to read at 1024.
    'wrap_pitch_studs': 0.011,
    'wrap_depth_studs': 0.0004,
}

REGION = {name: i for i, name in enumerate(cc.REGIONS)}


# ---------------------------------------------------------------------------------------------
# The atlas: covered pixels as flat arrays
# ---------------------------------------------------------------------------------------------

class Atlas:
    def __init__(self, obj, params):
        size = TEXTURE['size']
        raster = cc.rasterize(obj, size)
        assert not raster['overlap'].any(), 'the UVs overlap'
        self.size = size
        self.mask = raster['mask']
        self.idx = np.nonzero(self.mask)
        pick = lambda key: raster[key][self.idx]  # noqa: E731
        self.s, self.theta = pick('s'), pick('theta')
        self.x, self.y, self.z = pick('x'), pick('y'), pick('z')
        self.d, self.r = -self.y, np.hypot(self.x, self.z)
        self.region = pick('region')
        self.around = self.theta * self.r  # arc round the cue from the seam (studs)
        # texels per stud at each pixel, from how fast s changes across the atlas
        gy, gx = np.gradient(np.where(self.mask, raster['s'], np.nan))
        g = np.hypot(gx, gy)[self.idx]
        g = np.where(np.isfinite(g) & (g > 0), g, np.nanmedian(g))
        self.density = 1.0 / g
        self.params = params
        self.panels = {p['name']: p for p in params['panels']}
        self.n = len(self.s)

    def full(self, values, fill):
        """Scatter per-pixel values back into a size x size (x channels) image."""
        values = np.asarray(values, np.float64)
        shape = (self.size, self.size) + values.shape[1:]
        out = np.empty(shape, np.float64)
        out[...] = fill
        out[self.idx] = values
        return out

    def in_region(self, *names):
        return np.isin(self.region, [REGION[n] for n in names])


# ---------------------------------------------------------------------------------------------
# Panels: which panel and which panel pixel every atlas pixel shows
# ---------------------------------------------------------------------------------------------

def r_of_s(params):
    s = np.array([p['s'] for p in params['profile']])
    r = np.array([p['r'] for p in params['profile']])
    return lambda at: np.interp(at, s, r)


def tile_coordinate(atlas, s_vals, repeats):
    """Where along the repeating tile each shaft point is (0..repeats): each repeat is laid with
    square texels where it lies, so repeats shorten toward the tip with the taper."""
    tile = atlas.panels['shaft_tile']
    w, h = tile['size_px']
    radius = r_of_s(atlas.params)
    grid = np.linspace(tile['s_from'], tile['s_to'], 4001)
    rate = 1.0 / ((w / h) * 2 * math.pi * radius(grid))
    F = np.concatenate([[0.0], np.cumsum((rate[1:] + rate[:-1]) / 2 * np.diff(grid))])
    return np.interp(s_vals, grid, F) / F[-1] * repeats


def panel_lookup(atlas, repeats):
    """Per pixel: (panel name or '', x in 0..1, y in 0..1). Tip, ferrule and bumper get ''."""
    P = atlas.panels
    name = np.full(atlas.n, '', dtype=object)
    px = np.zeros(atlas.n)
    py = atlas.theta / (2 * math.pi)
    shaft = atlas.in_region('shaft')
    top0 = P['shaft_top']['s_from']
    in_tile = shaft & (atlas.s < top0)
    in_top = shaft & (atlas.s >= top0)
    t = tile_coordinate(atlas, atlas.s[in_tile], repeats)
    name[in_tile] = 'shaft_tile'
    px[in_tile] = t - np.floor(t)
    for panel, mask in (('shaft_top', in_top), ('forearm', atlas.in_region('joint', 'forearm')),
                        ('butt', atlas.in_region('ring', 'wrap', 'cap'))):
        p = P[panel]
        name[mask] = panel
        px[mask] = np.clip((atlas.s[mask] - p['s_from']) / (p['s_to'] - p['s_from']), 0, 1)
    end = atlas.in_region('end')
    p = P['cap_end']
    size = p['size_px'][0]
    k = p['disc_radius_px'] / p['face_radius_studs']
    name[end] = 'cap_end'
    px[end] = (size / 2 + atlas.x[end] * k) / size
    py = np.where(end, (size / 2 - atlas.z * k) / size, py)
    return name, px, py


def sample(image, x, y, wrap_x, wrap_y):
    """Bilinear sample of an H x W x C float image at x, y in 0..1 (pixel centres at (i+0.5)/n)."""
    h, w = image.shape[:2]
    fx, fy = x * w - 0.5, y * h - 0.5
    x0, y0 = np.floor(fx).astype(np.int64), np.floor(fy).astype(np.int64)
    tx, ty = (fx - x0)[:, None], (fy - y0)[:, None]

    def index(i, n, wrap):
        return np.mod(i, n) if wrap else np.clip(i, 0, n - 1)
    xa, xb = index(x0, w, wrap_x), index(x0 + 1, w, wrap_x)
    ya, yb = index(y0, h, wrap_y), index(y0 + 1, h, wrap_y)
    top = image[ya, xa] * (1 - tx) + image[ya, xb] * tx
    bottom = image[yb, xa] * (1 - tx) + image[yb, xb] * tx
    return top * (1 - ty) + bottom * ty


# ---------------------------------------------------------------------------------------------
# Detail shared by every skin: the Irish linen wrap's threads
# ---------------------------------------------------------------------------------------------

def wrap_height(atlas):
    """The wrap's thread relief (studs) at every pixel, 0 off the wrap."""
    h = np.zeros(atlas.n)
    m = atlas.in_region('wrap')
    pitch = TEXTURE['wrap_pitch_studs']
    # one pitch per turn: seamless round the cue
    phase = atlas.d[m] / pitch + atlas.theta[m] / (2 * math.pi)
    ridge = 0.5 - 0.5 * np.cos(2 * math.pi * phase)
    ridge = ridge ** 0.6
    slub = cc.fbm(atlas.x[m] * 90, atlas.d[m] * 25, atlas.z[m] * 90, 3, seed=31)
    h[m] = TEXTURE['wrap_depth_studs'] * ridge * (0.7 + 0.6 * slub)
    return h, ridge, m


# ---------------------------------------------------------------------------------------------
# Classic: the default cue, procedurally
# ---------------------------------------------------------------------------------------------

def classic(atlas, skin):
    """Colour (0..255), roughness, metalness and height (studs) per pixel for Classic."""
    n = atlas.n
    col = np.zeros((n, 3))
    rough = np.zeros(n)
    metal = np.zeros(n)
    height = np.zeros(n)
    X, D, Z = atlas.x, atlas.d, atlas.z
    colours = skin['colours']

    def rgb(name):
        return np.array(cc.hex_rgb(colours[name]), np.float64)

    # tip: blue chalky leather, speckled with chalk dust
    m = atlas.in_region('tip')
    speck = cc.fbm(X[m] * 900, D[m] * 900, Z[m] * 900, 3, seed=3)
    dust = np.clip((cc.noise3(X[m] * 2600, D[m] * 2600, Z[m] * 2600, seed=4) - 0.72) * 4, 0, 1)
    col[m] = rgb('tip') * (0.9 + 0.2 * speck)[:, None] + (np.array([150, 170, 210]) - rgb('tip')) * (0.35 * dust)[:, None]
    rough[m] = 0.92
    height[m] = 0.00004 * speck

    # ferrule: ivory-white, very faint mottling
    m = atlas.in_region('ferrule')
    mott = cc.fbm(X[m] * 200, D[m] * 60, Z[m] * 200, 3, seed=5)
    col[m] = rgb('ferrule') * (0.97 + 0.04 * mott)[:, None]
    rough[m] = 0.3

    # shaft: hard maple with fine straight grain along the length
    m = atlas.in_region('shaft')
    warp = cc.fbm(D[m] * 1.5, X[m] * 4, Z[m] * 4, 2, seed=7)
    g = cc.fbm(X[m] * 140 + warp * 3, D[m] * 2.2, Z[m] * 140 + warp * 3, 4, seed=8)
    lines = np.abs(np.mod(g * 14, 1.0) - 0.5) * 2  # 0 on a grain line
    line = np.clip(1 - lines / 0.18, 0, 1)
    fleck = cc.fbm(X[m] * 700, D[m] * 40, Z[m] * 700, 2, seed=9)
    shade = 0.93 + 0.1 * g - 0.09 * line + 0.03 * fleck
    col[m] = rgb('shaft') * shade[:, None]
    rough[m] = 0.34 + 0.06 * line
    height[m] = -0.00002 * line

    # joint collar and ring: polished silver, faintly brushed round the cue
    m = atlas.in_region('joint', 'ring')
    brush = cc.fbm(D[m] * 3000, X[m] * 20, Z[m] * 20, 2, seed=11)
    col[m] = rgb('metal') * (0.96 + 0.06 * brush)[:, None]
    rough[m] = 0.16 + 0.05 * brush
    metal[m] = 1.0

    # forearm: dark rosewood, visible wavy grain, satin finish
    m = atlas.in_region('forearm')
    warp = cc.fbm(D[m] * 2.0, X[m] * 6, Z[m] * 6, 3, seed=13)
    g = cc.fbm(X[m] * 55 + warp * 5, D[m] * 1.6, Z[m] * 55 + warp * 5, 4, seed=14)
    lines = np.abs(np.mod(g * 11, 1.0) - 0.5) * 2
    line = np.clip(1 - lines / 0.28, 0, 1)
    pores = np.clip((cc.noise3(X[m] * 1500, D[m] * 220, Z[m] * 1500, seed=15) - 0.62) * 3, 0, 1)
    base = rgb('forearm')
    dark = np.array([40, 18, 13], np.float64)
    light = base * 1.18
    k = np.clip(0.55 + 0.9 * (g - 0.5), 0, 1)
    wood = light * k[:, None] + base * (1 - k)[:, None]
    wood = wood * (1 - 0.55 * line)[:, None] + dark * (0.55 * line)[:, None]
    col[m] = wood * (1 - 0.25 * pores)[:, None]
    rough[m] = 0.3 + 0.08 * line + 0.1 * pores
    height[m] = -0.000025 * line - 0.00002 * pores

    # wrap: black Irish linen; the threads come from wrap_height (every skin has them)
    m = atlas.in_region('wrap')
    wh, ridge, wm = wrap_height(atlas)
    fibre = cc.fbm(X[m] * 1200, D[m] * 300, Z[m] * 1200, 2, seed=17)
    col[m] = rgb('wrap') * (0.75 + 0.35 * ridge[:] + 0.15 * fibre)[:, None]
    rough[m] = 0.78

    # sleeve: glossy black
    m = atlas.in_region('cap')
    col[m] = rgb('cap') * (0.97 + 0.06 * cc.fbm(X[m] * 80, D[m] * 80, Z[m] * 80, 2, seed=19))[:, None]
    rough[m] = 0.12

    # bumper and end face: matte black rubber; two molded rings on the end face
    m = atlas.in_region('bumper', 'end')
    grain = cc.fbm(X[m] * 1500, D[m] * 1500, Z[m] * 1500, 2, seed=21)
    col[m] = rgb('bumper') * (0.92 + 0.16 * grain)[:, None]
    rough[m] = 0.86
    height[m] = 0.00002 * grain
    e = atlas.in_region('end')
    face_r = atlas.panels['cap_end']['face_radius_studs']
    rr = atlas.r[e] / face_r
    ring = sum(np.exp(-((rr - c) / 0.018) ** 2) for c in (0.55, 0.62))
    height[e] = height[e] - 0.00012 * ring
    return col, rough, metal, height + wh


# ---------------------------------------------------------------------------------------------
# Panel skins
# ---------------------------------------------------------------------------------------------

def load_panel(path):
    img = cc.read_image(path)
    return img[:, :, :3] * 255.0


def paint_panels(atlas, skin, base_dir):
    """Colour per pixel from the skin's panels (missing ones fall back to a flat colour)."""
    tile_opts = skin.get('shaft_tile', {})
    natural = atlas.panels['shaft_tile']['default_repeats']
    repeats = tile_opts.get('repeats') or natural
    name, px, py = panel_lookup(atlas, repeats)
    col = np.zeros((atlas.n, 3))
    panels = skin.get('panels', {})
    fallback = skin.get('fallback', {})
    for panel in ('shaft_tile', 'shaft_top', 'forearm', 'butt', 'cap_end'):
        m = name == panel
        if not m.any():
            continue
        path = panels.get(panel)
        full = os.path.join(base_dir, path) if path else None
        if full and os.path.isfile(full):
            img = load_panel(full)
            col[m] = sample(img, px[m], py[m], wrap_x=(panel == 'shaft_tile'), wrap_y=(panel != 'cap_end'))
            cc.log(TAG, 'panel', panel, os.path.relpath(full, HERE), img.shape[1], 'x', img.shape[0])
        else:
            if path:
                cc.log(TAG, 'panel', panel, 'missing:', path, '- flat colour')
            col[m] = np.array(cc.hex_rgb(fallback.get(panel, '#808080')), np.float64)
    fade = float(tile_opts.get('fade', 0) or 0)
    if fade > 0:
        tile = atlas.panels['shaft_tile']
        m = name == 'shaft_tile'
        u = (atlas.s[m] - tile['s_from']) / (tile['s_to'] - tile['s_from'])
        w = np.clip(u / fade, 0, 1)
        w = w * w * (3 - 2 * w)
        to = np.array(cc.hex_rgb(tile_opts.get('fade_color', fallback.get('shaft_tile', '#D6B07C'))), np.float64)
        col[m] = col[m] * w[:, None] + to * (1 - w)[:, None]
    colours = skin.get('colours', {})
    for region, key, default in (('tip', 'tip', '#222C4A'), ('ferrule', 'ferrule', '#F2EEE2'),
                                 ('bumper', 'bumper', '#121212')):
        col[atlas.in_region(region)] = np.array(cc.hex_rgb(colours.get(key, default)), np.float64)
    return col, name


def key_mask(col, keys):
    """1 where a pixel's colour is within a key's tolerance (soft at the edge), else 0."""
    out = np.zeros(len(col))
    soft = TEXTURE['key_softness']
    for key in keys or []:
        c = np.array(cc.hex_rgb(key['color']), np.float64)
        tol = float(key.get('tolerance', 40))
        dist = np.linalg.norm(col - c, axis=1)
        out = np.maximum(out, np.clip((tol - dist) / (tol * soft), 0, 1))
    return out


def panel_skin(atlas, skin, base_dir):
    col, _ = paint_panels(atlas, skin, base_dir)
    rough_by = skin.get('roughness', {})
    rough = np.zeros(atlas.n)
    defaults = {'tip': 0.9, 'ferrule': 0.3, 'shaft': 0.35, 'joint': 0.3, 'forearm': 0.3, 'ring': 0.3,
                'wrap': 0.78, 'cap': 0.15, 'bumper': 0.86, 'end': 0.86}
    for region in cc.REGIONS:
        rough[atlas.in_region(region)] = float(rough_by.get(region, defaults[region]))
    metal = key_mask(col, skin.get('metal'))
    rough = rough * (1 - metal) + float(skin.get('metal_roughness', 0.18)) * metal
    glow = key_mask(col, skin.get('glow'))
    wh, _, _ = wrap_height(atlas)
    return col, rough, metal, wh, (glow if skin.get('glow') else None)


def areas_skin(atlas):
    name, _, _ = panel_lookup(atlas, atlas.panels['shaft_tile']['default_repeats'])
    col = np.zeros((atlas.n, 3))
    A = cc.AREA_COLOURS
    for panel in ('shaft_tile', 'shaft_top', 'forearm', 'butt', 'cap_end'):
        col[name == panel] = A[panel]
    for region in ('tip', 'ferrule', 'bumper'):
        col[atlas.in_region(region)] = A[region]
    return col, np.full(atlas.n, 0.6), np.zeros(atlas.n), np.zeros(atlas.n), None


# ---------------------------------------------------------------------------------------------
# Maps
# ---------------------------------------------------------------------------------------------

def normal_map(atlas, height):
    """Tangent-space normals (OpenGL, +Y up the image) from a height field in studs: T is +U
    (right in the atlas), B is +V (up the atlas)."""
    h = cc.dilate(atlas.full(height, 0.0), atlas.mask)
    gy, gx = np.gradient(h)  # per pixel, y down
    dens = atlas.full(atlas.density, 0.0)
    dens = cc.dilate(dens, atlas.mask)
    nx = -gx * dens
    ny = gy * dens  # d/dB = -d/dy
    nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return (n * 0.5 + 0.5) * 255.0


def write_maps(atlas, out_prefix, col, rough, metal, height, glow):
    mask = atlas.mask
    minimum = TEXTURE['dilate_px']
    paths = {}
    colour = cc.dilate(atlas.full(np.clip(col, 0, 255), 0.0), mask, minimum)
    paths['color'] = out_prefix + '_color.png'
    cc.write_png(paths['color'], np.round(colour))
    nm = normal_map(atlas, height)
    paths['normal'] = out_prefix + '_normal.png'
    cc.write_png(paths['normal'], np.round(nm))
    r = cc.dilate(atlas.full(np.clip(rough, 0, 1) * 255.0, 0.0), mask, minimum)
    paths['roughness'] = out_prefix + '_roughness.png'
    cc.write_png(paths['roughness'], np.round(np.repeat(r[:, :, None], 3, axis=2)))
    mt = cc.dilate(atlas.full(np.clip(metal, 0, 1) * 255.0, 0.0), mask, minimum)
    paths['metalness'] = out_prefix + '_metalness.png'
    cc.write_png(paths['metalness'], np.round(np.repeat(mt[:, :, None], 3, axis=2)))
    emissive = out_prefix + '_emissive.png'
    if glow is not None:
        em = cc.dilate(atlas.full(np.clip(col, 0, 255) * glow[:, None], 0.0), mask, minimum)
        cc.write_png(emissive, np.round(em))
        paths['emissive'] = emissive
    elif os.path.isfile(emissive):
        os.remove(emissive)
    for key, path in paths.items():
        cc.log(TAG, 'wrote', os.path.relpath(path, HERE))
    return paths


def main():
    import bpy  # noqa: F401  (Blender only)
    args = cc.script_args()
    params = cc.read_parameters()
    cc.clear_scene('CueTextures')
    obj = cc.load_cue_object()
    atlas = Atlas(obj, params)
    cc.log(TAG, 'atlas', atlas.n, 'covered pixels')
    import CueRender
    if '--areas' in args:
        col, rough, metal, height, glow = areas_skin(atlas)
        import tempfile
        prefix = os.path.join(tempfile.mkdtemp(prefix='cue_areas_'), '_areas')
        maps = write_maps(atlas, prefix, col, rough, metal, height, glow)
        CueRender.render_areas(maps)
        return
    if '--skin' not in args:
        cc.fail(TAG, 'pass --skin <skin json> or --areas')
    skin_path = os.path.abspath(args[args.index('--skin') + 1])
    with open(skin_path) as handle:
        skin = json.load(handle)
    skin_id = skin['id']
    base_dir = HERE  # panel paths in a skin are relative to assets/cue
    if skin.get('procedural') == 'classic':
        col, rough, metal, height = classic(atlas, skin)
        glow = None
    else:
        col, rough, metal, height, glow = panel_skin(atlas, skin, base_dir)
    os.makedirs(TEXTURES, exist_ok=True)
    maps = write_maps(atlas, os.path.join(TEXTURES, skin_id), col, rough, metal, height, glow)
    out = None
    if skin_id == '_test':
        out = os.path.join(CueRender.RENDERS, 'template_check.png')
    CueRender.render_skin(skin_id, dict(maps), out)
    cc.log(TAG, 'OK', skin_id)


if __name__ == '__main__':
    main()
