"""Texture sheets for the pool table (assets/table/TableModel.blend, Parameters.json uv_layout).

Run it headless from the repository root after TableModel.py:

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
        --python assets/table/TableTextures.py

It paints every sheet at 4096 (textures/masters/, git-ignored) and box-filters it to the 1024
upload PNG (textures/, what Roblox gets: uploads render at 1024 at most). It writes
Textures.json (maps, recipe, seeds, sources, hashes) and sources/Sources.json.

Conventions (docs/STUDIO_NOTES.md, SurfaceAppearance facts):
- Images are authored in Blender's UV convention: UV (0, 0) is the image's bottom-left, so a
  strip at v0..v1 occupies image rows (1 - v1) .. (1 - v0) from the top. The FBX import keeps
  this mapping in Roblox.
- UVs outside 0..1 repeat, so every trim strip is seamless along U (grain runs along U).
- SurfaceAppearance.Color multiplies the ColorMap: Cloth_Color is a near-white grey, tinted per
  look. Vertex colours are ignored, so contact darkening is painted into the colour sheets.
- Normal maps are OpenGL (+Y = image top). A missing Metalness map means non-metal.

Sources (CC0, downloaded into sources/<name>/, git-ignored, rebuilt from Sources.json): the
TextureCan #527 billiard cloth scan (its spectrum only, re-synthesised with random phases so the
tile is seamless and has no blotches), Poly Haven cherry_veneer (grain luminance, recoloured) and
ambientCG Leather026 (pebble detail and normal). Any source that fails to download is replaced
by a procedural stand-in, recorded as such in Textures.json.

Deterministic: fixed seeds (numpy default_rng), no clocks in the pixels, a fixed PNG writer.
"""

import datetime
import hashlib
import json
import os
import struct
import sys
import urllib.request
import zipfile
import zlib

sys.dont_write_bytecode = True
import numpy as np  # noqa: E402

try:
    import bpy  # only to decode JPG/PNG sources
except ImportError:  # pragma: no cover
    bpy = None

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
TEX_DIR = os.path.join(HERE, 'textures')
MASTER_DIR = os.path.join(TEX_DIR, 'masters')
SRC_DIR = os.path.join(HERE, 'sources')

N = 4096  # master size
UP = 1024  # upload size (Roblox renders uploads at 1024 at most)

SEEDS = {'cloth_phase': 5270, 'cloth_rough': 5271, 'wood_fallback': 7101, 'pearl': 7102, 'black_fine': 7103,
         'leather_fallback': 2601, 'chrome': 4901, 'marks': 8801, 'logo': 6001}

# Every tuning number, with what it does. Colours are sRGB 0..255.
CFG = {
    # ---- Cloth (tile = 1.5 studs = 9.375 in; master 4096 px, so 437 px per inch) ----
    'cloth_mean': 0.95,  # mean of the grey colour map (tinted per look in Roblox)
    'cloth_color_amp': 0.016,  # colour fibre noise, standard deviation
    'cloth_highpass_cycles': (14, 40),  # remove structure longer than tile/14 (0.7 in); full by tile/40
    'cloth_normal_strength': 0.9,  # fibre slope scale (unit-std height, per master px)
    'cloth_twill_cycles': 150,  # twill ridges: 150 cycles per tile on each axis (a 1.1 mm pitch diagonal)
    'cloth_twill_amp': 0.35,  # twill height relative to the fibre noise
    'cloth_rough': (0.89, 0.022, 0.82, 0.96),  # mean, noise std, clip low, clip high
    # ---- Wood ----
    'wood_highpass_sigma': 220.0,  # source px; removes lighting drift from the scan
    'rails_sy': 0.39,  # source rows per master row on the rails (0.41 = true scale)
    'rails_y0': (1170.0, 2650.0),  # source rows for the profile (straight grain) and end strips
    'body_sy': 0.8,  # source rows per master row on the body (0.81 = true scale)
    'body_y0': {'skirt': 2600.0, 'block': 3850.0, 'leg': 1480.0},  # source rows per strip
    'cherry_ramp': ([85, 47, 35], [124, 72, 56], [153, 97, 75]),  # grain dark, mean, light (#552F23 #7C4838 #99614B)
    'cherry_contrast': 0.24,  # ramp position per grain standard deviation
    'black_ramp': ([13, 13, 15], [21, 21, 24], [30, 30, 34]),  # #0D0D0F .. #1E1E22, satin black PRC
    'black_contrast': 0.20,
    'wood_rough': (0.38, 0.018, 0.34, 0.42),  # mean, per grain std, clip (satin lacquer, both looks)
    'wood_normal_strength': 0.06,  # grain relief (very faint: a lacquered surface)
    'end_grain_dark': 0.78,  # colour factor on the mitre/seam end faces
    'pearl': [236, 231, 220],  # mother-of-pearl sight base
    'pearl_iridescence': 7.0,  # +- sRGB swing of the pearl's colour drift
    'pearl_rough': 0.22,
    'hidden_rgb': [12, 11, 11],
    'cabinet_rgb': [17, 17, 19],  # black cabinet in both looks
    'cabinet_rough': 0.45,
    'rubber_rgb': [16, 16, 16],
    'rubber_rough': 0.85,
    # contact darkening (colour factor at the contact, and its reach in inches)
    'ao_skirt_top': (0.42, 0.9),  # under the rail lip on the skirt top
    'ao_skirt_bead': (0.75, 0.25),  # under the skirt bead
    'ao_block_top': (0.5, 0.8),  # corner block tops under the rail
    'ao_leg_top': (0.45, 0.9),  # leg tops under the corner blocks
    'ao_leg_groove': 0.45,  # the seam groove a third of the way down the leg
    'ao_leg_foot': (0.7, 0.4),  # leg bottom above the leveller
    'ao_cabinet_top': (0.55, 0.5),
    'ao_rail_inner': (0.8, 0.25),  # the rail edge against the cushion
    'ao_rail_bottom': (0.72, 0.6),  # the bottom of the rail's outer face
    # ---- Parts (leather, cups, chrome) ----
    'leather_rgb': [21, 21, 21],  # ~#151515
    'leather_detail': 0.75,  # exponent on the scan's luminance ratio
    'leather_repeats': 6,  # scan repeats across the atlas width (3.6 in each)
    'leather_normal_gain': 7.0,  # pebble slope gain (the 3x + 4x filtering flattens the scan's normal)
    'leather_rough': (0.60, 0.05),  # mean and half-range (0.55..0.65)
    'leather_wall': (0.035, 0.17, 0.62),  # darkening from v 0.035 (rim edge) to v 0.17 (cloth level) down to 0.62
    'cup_falloff_v': 0.075,  # exponential darkening down the cup (v per e-fold)
    'cup_floor_rgb': [3, 3, 3],
    'cup_rough': 0.75,
    'chrome_rgb': [214, 209, 203],
    'chrome_rough': 0.15,
    'chrome_under_rgb': [120, 117, 113],  # the cap underside sits in the leather's shadow
    'chrome_under_rough': 0.3,
    # ---- Logo plate (9 x 3 in) ----
    'logo_rgb': [19, 19, 21],
    'logo_line_rgb': [178, 176, 170],
    'logo_line_inset': 0.28,  # in
    'logo_line_width': 0.05,  # in
    'logo_line_radius': 0.18,  # in, corner radius of the pinstripe
    'logo_rough_note': 'no roughness map: Roblox shades it fairly matte',
    # ---- Marks (RGBA overlay) ----
    'sticker_rgb': [246, 246, 242],
    'sticker_alpha': 0.95,
    'sticker_diameter': 0.9,  # of the 1 in quad
    'rack_alpha': 0.0,  # off: Roblox dithers faint alpha, so the patch drew as a checkered triangle in Studio (2026-09-24)
    'rack_rgb': [228, 228, 228],
    'streak_alpha': 0.0,  # off: under Roblox's faint-alpha dither the streak drew as a dotted white line (seen in Studio 2026-09-24)
    'streak_rgb': [225, 225, 225],
    'chalk_rgb': [40, 100, 170],
    'chalk_alpha': 0.5,
    'toe_alpha': 0.35,
    'rim_alpha': 0.35,
}

# Parameters.json uv_layout, mirrored here for the per-strip painting (asserted against the file).
PX_PER_IN = {'rails': 400.0 * 4 * 0.16, 'body': 200.0 * 4 * 0.16, 'parts': 300.0 * 4 * 0.16}

SOURCES = [
    {'name': 'cloth527', 'title': 'TextureCan #527 Snooker Pool Table Cloth (Fabrics 0075), 4K',
     'url': 'https://www.texturecan.com/downloads/fabrics_0075/fabrics_0075_4k_TgPizN.zip',
     'page': 'https://www.texturecan.com/details/527/', 'licence': 'CC0',
     'licence_url': 'https://www.texturecan.com/terms/', 'file': 'fabrics_0075_4k.zip',
     'members': ['fabrics_0075_color_4k.jpg', 'fabrics_0075_height_4k.png']},
    {'name': 'cherry_veneer', 'title': 'Poly Haven cherry_veneer diffuse, 4K',
     'url': 'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/4k/cherry_veneer/cherry_veneer_diff_4k.jpg',
     'page': 'https://polyhaven.com/a/cherry_veneer', 'licence': 'CC0',
     'licence_url': 'https://polyhaven.com/license', 'file': 'cherry_veneer_diff_4k.jpg', 'members': []},
    {'name': 'leather026', 'title': 'ambientCG Leather026, 2K JPG',
     'url': 'https://ambientcg.com/get?file=Leather026_2K-JPG.zip',
     'page': 'https://ambientcg.com/view?id=Leather026', 'licence': 'CC0',
     'licence_url': 'https://docs.ambientcg.com/license/', 'file': 'Leather026_2K-JPG.zip',
     'members': ['Leather026_2K-JPG_Color.jpg', 'Leather026_2K-JPG_NormalGL.jpg', 'Leather026_2K-JPG_Roughness.jpg']},
]


# ---------------------------------------------------------------------------------------------
# Files: download, hash, decode, PNG writer
# ---------------------------------------------------------------------------------------------

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def load_sources_record():
    path = os.path.join(SRC_DIR, 'Sources.json')
    if os.path.exists(path):
        with open(path) as f:
            return {s['name']: s for s in json.load(f).get('sources', [])}
    return {}


def fetch(src, previous):
    """Download (or reuse) one source; returns {member: path} or None when unavailable."""
    folder = os.path.join(SRC_DIR, src['name'])
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, src['file'])
    rec = previous.get(src['name'], {})
    try:
        if not os.path.exists(path):
            print('TEX download', src['url'])
            req = urllib.request.Request(src['url'], headers={'User-Agent': 'Mozilla/5.0 (table texture builder)'})
            with urllib.request.urlopen(req, timeout=300) as r, open(path + '.part', 'wb') as f:
                while True:
                    chunk = r.read(1 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(path + '.part', path)
            rec = {}
        sha = sha256_file(path)
        if rec.get('sha256') and rec['sha256'] != sha:
            print('TEX warning: %s sha256 changed (%s -> %s)' % (src['name'], rec['sha256'], sha))
        out = {'__file__': path, '__sha__': sha, '__date__': rec.get('date', datetime.date.today().isoformat())}
        if src['members']:
            with zipfile.ZipFile(path) as z:
                names = z.namelist()
                for m in src['members']:
                    target = os.path.join(folder, m)
                    if not os.path.exists(target):
                        match = next(n for n in names if n.endswith(m))
                        with z.open(match) as a, open(target, 'wb') as b:
                            b.write(a.read())
                    out[m] = target
        else:
            out[src['file']] = path
        return out
    except Exception as exc:  # offline or moved: procedural stand-in
        print('TEX source %s unavailable (%s); synthesising instead' % (src['name'], exc))
        return None


def load_pixels(path):
    """Decode an image with Blender; float32 (H, W, C) raw stored values 0..1, top row first."""
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = 'Non-Color'
    w, h = img.size
    ch = img.channels
    px = np.empty(w * h * ch, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, ch)[::-1].copy()


def luminance(a):
    return (0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]).astype(np.float64)


def write_png(path, arr):
    """arr float 0..1 or uint8, (H, W) or (H, W, 3|4); deterministic 8-bit PNG."""
    if arr.dtype != np.uint8:
        arr = np.clip(np.round(arr * 255.0), 0, 255).astype(np.uint8)
    if arr.ndim == 2:
        arr = np.repeat(arr[..., None], 3, axis=2)
    h, w, c = arr.shape
    ctype = {3: 2, 4: 6}[c]
    raw = np.concatenate([np.zeros((h, 1), np.uint8), arr.reshape(h, w * c)], axis=1).tobytes()

    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, ctype, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


# ---------------------------------------------------------------------------------------------
# Pixel helpers
# ---------------------------------------------------------------------------------------------

def srgb(c):
    return np.asarray(c, dtype=np.float64) / 255.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def box_down(a, f):
    h, w = a.shape[:2]
    rest = a.shape[2:]
    return a.reshape(h // f, f, w // f, f, *rest).mean(axis=(1, 3))


def rows(v0, v1, n=N):
    """Image rows (top first) covering UV v0..v1."""
    return slice(int(round((1.0 - v1) * n)), int(round((1.0 - v0) * n)))


def v_of_rows(n=N):
    return 1.0 - (np.arange(n) + 0.5) / n


def u_of_cols(n=N):
    return (np.arange(n) + 0.5) / n


def fft_gauss_blur(a, sigma):
    """Periodic Gaussian blur of a 2D field."""
    h, w = a.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.rfftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    return np.fft.irfft2(np.fft.rfft2(a) * g, s=a.shape)


def standardize(a):
    a = a - a.mean()
    return a / (a.std() + 1e-12)


def sample_wrap(src, xs, ys):
    """Bilinear sample of a 2D periodic field at float coords (broadcast), wrapping both axes."""
    h, w = src.shape
    x0 = np.floor(xs).astype(np.int64)
    y0 = np.floor(ys).astype(np.int64)
    fx, fy = xs - x0, ys - y0
    x0 %= w
    y0 %= h
    x1, y1 = (x0 + 1) % w, (y0 + 1) % h
    return (src[y0, x0] * (1 - fx) * (1 - fy) + src[y0, x1] * fx * (1 - fy) +
            src[y1, x0] * (1 - fx) * fy + src[y1, x1] * fx * fy)


def normal_from_height(hgt, strength):
    """OpenGL tangent normal from a height field (top row first; +v is up), periodic in x."""
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * 0.5
    dv = -(np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * 0.5  # rows run down, v runs up
    n = np.stack([-dx * strength, -dv * strength, np.ones_like(hgt)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def encode_normal(n):
    n = n / np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def down_normal(enc, f):
    n = box_down(enc * 2.0 - 1.0, f)
    return encode_normal(n)


def ramp3(t, dark, mid, light):
    """sRGB ramp: t 0 -> dark, 0.5 -> mid, 1 -> light."""
    t = np.clip(t, 0.0, 1.0)[..., None]
    d, m, l_ = srgb(dark), srgb(mid), srgb(light)
    lo = d + (m - d) * (t / 0.5)
    hi = m + (l_ - m) * ((t - 0.5) / 0.5)
    return np.where(t < 0.5, lo, hi)


def fill(shape, rgb):
    out = np.empty(shape + (3,), dtype=np.float64)
    out[...] = srgb(rgb)
    return out


# ---------------------------------------------------------------------------------------------
# Cloth: random-phase synthesis of the scan's spectrum (seamless, no blotches)
# ---------------------------------------------------------------------------------------------

def random_phase(amplitude, phase, cycles):
    """Real field with this rfft amplitude and phase, high-passed (cycles per tile), unit std."""
    h, w = N, N
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.rfftfreq(w)[None, :] * w
    k = np.sqrt(fx * fx + fy * fy)
    hp = smoothstep(cycles[0], cycles[1], k)
    field = np.fft.irfft2(amplitude * hp * phase, s=(h, w))
    return standardize(field)


def build_cloth(srcs, log):
    rng = np.random.default_rng(SEEDS['cloth_phase'])
    white = rng.standard_normal((N, N))
    phase = np.fft.rfft2(white)
    phase /= np.abs(phase) + 1e-12
    cyc = CFG['cloth_highpass_cycles']
    if srcs.get('cloth527'):
        col = luminance(load_pixels(srcs['cloth527']['fabrics_0075_color_4k.jpg'])[..., :3])
        hgt = load_pixels(srcs['cloth527']['fabrics_0075_height_4k.png'])[..., 0].astype(np.float64)
        assert col.shape == (N, N) and hgt.shape == (N, N), (col.shape, hgt.shape)
        amp_c = np.abs(np.fft.rfft2(col - col.mean()))
        amp_h = np.abs(np.fft.rfft2(hgt - hgt.mean()))
        log['cloth'] = 'random-phase synthesis of the TextureCan #527 colour and height spectra'
    else:
        fy = np.fft.fftfreq(N)[:, None] * N
        fx = np.fft.rfftfreq(N)[None, :] * N
        k = np.sqrt(fx * fx + fy * fy) + 1.0
        amp_c = amp_h = np.exp(-(k / 420.0) ** 2) / np.sqrt(k)  # felt-like band around 10 px features
        log['cloth'] = 'procedural spectrum (source unavailable)'
    nc = random_phase(amp_c, phase, cyc)
    nh = random_phase(amp_h, phase, cyc)
    color = np.clip(CFG['cloth_mean'] + CFG['cloth_color_amp'] * nc, 0.0, 1.0)
    color += CFG['cloth_mean'] - color.mean()
    yy, xx = np.mgrid[0:N, 0:N]
    tw = CFG['cloth_twill_cycles']
    twill = np.sin(2 * np.pi * tw * (xx + yy) / N)
    hgt = nh + CFG['cloth_twill_amp'] * twill
    normal = encode_normal(normal_from_height(hgt, CFG['cloth_normal_strength']))
    rng2 = np.random.default_rng(SEEDS['cloth_rough'])
    rph = np.fft.rfft2(rng2.standard_normal((N, N)))
    rph /= np.abs(rph) + 1e-12
    nr = random_phase(amp_h, rph, cyc)
    m, sd, lo, hi = CFG['cloth_rough']
    rough = np.clip(m + sd * nr, lo, hi)
    return {'Cloth_Color': np.repeat(color[..., None], 3, axis=2), 'Cloth_Normal': normal,
            'Cloth_Roughness': rough}


# ---------------------------------------------------------------------------------------------
# Wood: the veneer scan's grain, recoloured per look, laid out on the Rails and Body strips
# ---------------------------------------------------------------------------------------------

def wood_grain_source(srcs, log):
    if srcs.get('cherry_veneer'):
        lum = luminance(load_pixels(srcs['cherry_veneer']['cherry_veneer_diff_4k.jpg'])[..., :3])
        g = lum - fft_gauss_blur(lum, CFG['wood_highpass_sigma'])
        log['wood'] = 'Poly Haven cherry_veneer luminance, high-passed and recoloured'
        return standardize(g)
    rng = np.random.default_rng(SEEDS['wood_fallback'])
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    warp = fft_gauss_blur(rng.standard_normal((N, N)), 90.0)
    warp = standardize(warp) * 30.0
    rings = np.sin(2 * np.pi * (yy + warp) / 38.0) ** 8
    fine = fft_gauss_blur(rng.standard_normal((N, N)), 1.2)
    log['wood'] = 'procedural grain (source unavailable)'
    return standardize(-rings + 0.3 * standardize(fine))


def wood_band(G, nrows, y0, sy):
    """Grain along U (full source width across the atlas, so the strip is seamless in U)."""
    xs = np.arange(N, dtype=np.float64)[None, :] * (G.shape[1] / N)
    ys = y0 + np.arange(nrows, dtype=np.float64)[:, None] * sy
    return sample_wrap(G, xs, ys)


def colour_from_grain(g, look):
    ramp = CFG['cherry_ramp'] if look == 'Cherry' else CFG['black_ramp']
    k = CFG['cherry_contrast'] if look == 'Cherry' else CFG['black_contrast']
    return ramp3(0.5 + k * g, *ramp)


def ao_factor(dist_in, floor, reach):
    """Contact darkening: `floor` at the contact, 1 at `reach` inches away."""
    return floor + (1.0 - floor) * smoothstep(0.0, reach, dist_in)


def build_rails(G, log):
    V = v_of_rows()
    grain = np.zeros((N, N))
    region = np.full(N, 'profile', dtype=object)
    region[rows(0.65, 0.865)] = 'ends'
    region[rows(0.865, 0.945)] = 'pearl'
    region[rows(0.945, 1.0)] = 'hidden'
    prof = rows(0.0, 0.65)
    grain[prof] = wood_band(G, prof.stop - prof.start, CFG['rails_y0'][0], CFG['rails_sy'])
    ends = rows(0.65, 0.865)
    grain[ends] = wood_band(G, ends.stop - ends.start, CFG['rails_y0'][1], CFG['rails_sy'])
    m, sd, lo, hi = CFG['wood_rough']
    rough = np.clip(m + sd * grain, lo, hi)
    hgt = -grain.copy()
    # profile v: 0.019 inner edge (cushion), 0.344 bullnose start, ~0.61 outer face bottom
    ppi = PX_PER_IN['rails'] / N  # v per inch
    fac = np.ones(N)
    f_in = ao_factor((V - 0.019) / ppi, *CFG['ao_rail_inner'])
    f_bot = ao_factor((0.6125 - V) / ppi, *CFG['ao_rail_bottom'])
    pm = region == 'profile'
    fac[pm] = np.minimum(f_in, f_bot)[pm]
    fac[region == 'ends'] = CFG['end_grain_dark']
    out = {}
    rng = np.random.default_rng(SEEDS['pearl'])
    pr = rows(0.865, 0.945)
    npr = pr.stop - pr.start
    swirl = [standardize(fft_gauss_blur(rng.standard_normal((npr, N)), 14.0)) for _ in range(2)]
    pearl = srgb(CFG['pearl'])[None, None, :] + (CFG['pearl_iridescence'] / 255.0) * (
        swirl[0][..., None] * np.array([1.0, -0.3, 0.6]) + swirl[1][..., None] * np.array([-0.4, 0.8, 0.2]))
    for look in ('Black', 'Cherry'):
        col = colour_from_grain(grain, look) * fac[:, None, None]
        col[pr] = pearl
        col[rows(0.945, 1.0)] = srgb(CFG['hidden_rgb'])
        out['Rails_Color_' + look] = np.clip(col, 0, 1)
    rough[pr] = CFG['pearl_rough'] + 0.02 * swirl[0]
    rough[rows(0.945, 1.0)] = 0.6
    hgt[pr] = 0.0
    hgt[rows(0.945, 1.0)] = 0.0
    out['Rails_Normal'] = encode_normal(normal_from_height(hgt, CFG['wood_normal_strength']))
    out['Rails_Roughness'] = rough
    return out


def build_body(G, geo, log):
    V = v_of_rows()
    U = u_of_cols()
    kb = PX_PER_IN['body'] / N  # uv per inch
    grain = np.zeros((N, N))
    bands = {'skirt': (0.0, 0.305), 'block': (0.305, 0.535), 'leg': (0.535, 0.725)}
    for name, (a, b) in bands.items():
        r = rows(a, b)
        grain[r] = wood_band(G, r.stop - r.start, CFG['body_y0'][name], CFG['body_sy'])
    fac = np.ones((N, N))
    # skirt: v = arc length from the top chamfer down (inches * kb)
    r = rows(0.0, 0.305)
    d_top = V[r] / kb
    f = ao_factor(d_top, *CFG['ao_skirt_top'])
    d_bead = np.abs(V[r] / kb - geo['skirt_bead_arc'])
    f = np.minimum(f, ao_factor(d_bead, *CFG['ao_skirt_bead']))
    fac[r] = f[:, None]
    # block: u = 0.5 + z * kb (grain up the block); its top meets the rail bottom
    r = rows(0.305, 0.535)
    fac[r] = ao_factor(np.abs(geo['u_block_top'] - U) / kb, *CFG['ao_block_top'])[None, :]
    # leg: u = 0.5 + z * kb, wrapping below u = 0
    r = rows(0.535, 0.725)
    f = ao_factor(np.abs(geo['u_leg_top'] - U) / kb, *CFG['ao_leg_top'])
    groove = np.abs(U - geo['u_leg_seam']) < (geo['groove_half_u'] + 0.5 / UP)
    f = np.where(groove, CFG['ao_leg_groove'], f)
    above_foot = (U - geo['u_leg_foot']) % 1.0  # the leg runs up from the foot, wrapping past u = 1
    f = np.minimum(f, ao_factor(np.minimum(above_foot, 1.0 - above_foot) / kb, *CFG['ao_leg_foot']))
    fac[r] = f[None, :]
    m, sd, lo, hi = CFG['wood_rough']
    rough = np.clip(m + sd * grain, lo, hi)
    hgt = -grain.copy()
    rng = np.random.default_rng(SEEDS['black_fine'])
    cab = rows(0.725, 0.835)
    ncab = cab.stop - cab.start
    fine = standardize(fft_gauss_blur(rng.standard_normal((ncab, N)), 1.5))
    lev = rows(0.835, 0.905)
    hid = rows(0.905, 1.0)
    out = {}
    for look in ('Black', 'Cherry'):
        col = colour_from_grain(grain, look) * fac[..., None]
        c = srgb(CFG['cabinet_rgb']) * (1 + 0.04 * fine[..., None])
        c *= ao_factor((geo['v_cab_top'] - V[cab]) / kb, *CFG['ao_cabinet_top'])[:, None, None]
        col[cab] = c
        col[lev] = srgb(CFG['rubber_rgb'])
        col[hid] = srgb(CFG['hidden_rgb'])
        out['Body_Color_' + look] = np.clip(col, 0, 1)
    rough[cab] = CFG['cabinet_rough'] + 0.01 * fine
    rough[lev] = CFG['rubber_rough']
    rough[hid] = 0.6
    hgt[cab] = 0.15 * fine
    hgt[lev] = 0.0
    hgt[hid] = 0.0
    out['Body_Normal'] = encode_normal(normal_from_height(hgt, CFG['wood_normal_strength']))
    out['Body_Roughness'] = rough
    return out


# ---------------------------------------------------------------------------------------------
# Parts: leather rims and walls, cups, chrome caps and bolts
# ---------------------------------------------------------------------------------------------

def leather_source(srcs, log):
    reps = CFG['leather_repeats']
    if srcs.get('leather026'):
        s = srcs['leather026']
        col = luminance(load_pixels(s['Leather026_2K-JPG_Color.jpg'])[..., :3])
        nor = load_pixels(s['Leather026_2K-JPG_NormalGL.jpg'])[..., :3].astype(np.float64)
        rgh = load_pixels(s['Leather026_2K-JPG_Roughness.jpg'])[..., 0].astype(np.float64)
        log['leather'] = 'ambientCG Leather026 luminance ratio, normal and roughness, %d repeats' % reps
    else:
        rng = np.random.default_rng(SEEDS['leather_fallback'])
        cells = standardize(fft_gauss_blur(rng.standard_normal((2048, 2048)), 7.0))
        col = 0.1 + 0.02 * cells
        nor = encode_normal(normal_from_height(cells * 6.0, 0.5))
        rgh = 0.6 + 0.1 * cells
        log['leather'] = 'procedural pebble (source unavailable)'
    return col, nor, rgh


def tile_down(src, nrows, reps):
    """Tile a square seamless source `reps` times across N, box-filtered (integer factor)."""
    s = src.shape[0]
    f = s * reps // N
    assert f * N == s * reps, (s, reps)
    need = nrows * f
    ty = -(-need // s)
    big = np.tile(src, (ty, reps) + (1,) * (src.ndim - 2))[:need]
    return box_down(big, f)


def build_parts(srcs, log):
    V = v_of_rows()
    U = u_of_cols()
    lcol, lnor, lrgh = leather_source(srcs, log)
    ratio = lcol / lcol.mean()
    lr = rows(0.0, 0.30)
    nl = lr.stop - lr.start
    reps = CFG['leather_repeats']
    detail = tile_down(ratio, nl, reps) ** CFG['leather_detail']
    lnrm = tile_down(lnor * 2 - 1, nl, reps)
    flat = np.array([0.0, 0.0, 1.0])
    lnrm = lnrm / np.linalg.norm(lnrm, axis=-1, keepdims=True)
    lnrm[..., :2] *= CFG['leather_normal_gain']
    lrg = tile_down(lrgh, nl, reps)
    lrg = standardize(lrg)
    col = np.zeros((N, N, 3))
    nrm = np.zeros((N, N, 3))
    nrm[...] = flat
    rough = np.zeros((N, N))
    metal = np.zeros((N, N))
    base = srgb(CFG['leather_rgb'])
    v0, v1, dark = CFG['leather_wall']
    wall = 1.0 - (1.0 - dark) * smoothstep(v0, v1, V[lr])
    col[lr] = base * detail[..., None] * wall[:, None, None]
    nrm[lr] = lnrm
    m, hr = CFG['leather_rough']
    rough[lr] = np.clip(m + hr * 0.5 * lrg, m - hr, m + hr)
    # cup: v 0.30 at the cloth, down 0.0469 per inch; the floor sits at u 0.72.. v 0.30..0.56
    cr = rows(0.30, 0.68)
    ncr = cr.stop - cr.start
    cup_detail = tile_down(ratio, ncr, reps) ** CFG['leather_detail']
    fall = dark * np.exp(-np.maximum(V[cr] - 0.30, 0) / CFG['cup_falloff_v'])
    ccol = base * cup_detail[..., None] * fall[:, None, None]
    ccol = np.maximum(ccol, srgb(CFG['cup_floor_rgb']))
    floor = (U[None, :] >= 0.715) & (V[cr][:, None] <= 0.565)
    ccol[floor] = srgb(CFG['cup_floor_rgb'])
    col[cr] = ccol
    rough[cr] = CFG['cup_rough']
    # chrome top 0.68..0.805, underside 0.805..0.905, rubber 0.905..1
    rng = np.random.default_rng(SEEDS['chrome'])
    ct = rows(0.68, 0.805)
    cu = rows(0.805, 0.905)
    rb = rows(0.905, 1.0)
    for r, rgb, rgh in ((ct, CFG['chrome_rgb'], CFG['chrome_rough']), (cu, CFG['chrome_under_rgb'], CFG['chrome_under_rough'])):
        nn = r.stop - r.start
        wob = standardize(fft_gauss_blur(rng.standard_normal((nn, N)), 20.0))
        col[r] = srgb(rgb) * (1 + 0.006 * wob[..., None])
        rough[r] = rgh + 0.008 * wob
        metal[r] = 1.0
    col[rb] = srgb(CFG['rubber_rgb'])
    rough[rb] = CFG['rubber_rough']
    return {'Parts_Color': np.clip(col, 0, 1), 'Parts_Normal': encode_normal(nrm), 'Parts_Roughness': rough,
            'Parts_Metalness': metal}


# ---------------------------------------------------------------------------------------------
# Logo plate and Marks
# ---------------------------------------------------------------------------------------------

def rounded_rect_sd(x, y, cx, cy, hx, hy, r):
    qx = np.abs(x - cx) - (hx - r)
    qy = np.abs(y - cy) - (hy - r)
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    return outside + np.minimum(np.maximum(qx, qy), 0) - r


def build_logo(log):
    w_in, h_in = 9.0, 3.0
    xs = (np.arange(N) + 0.5) / N * w_in
    ys = (np.arange(N) + 0.5) / N * h_in
    x, y = np.meshgrid(xs, ys[::-1])
    ins = CFG['logo_line_inset']
    sd = rounded_rect_sd(x, y, w_in / 2, h_in / 2, w_in / 2 - ins, h_in / 2 - ins, CFG['logo_line_radius'])
    px = h_in / N  # inch per row (the finer axis)
    line = 1.0 - smoothstep(CFG['logo_line_width'] / 2 - 1.5 * px, CFG['logo_line_width'] / 2 + 1.5 * px, np.abs(sd))
    rng = np.random.default_rng(SEEDS['logo'])
    brushed = standardize(fft_gauss_blur(rng.standard_normal((N, 64)), 0.8))
    brushed = np.repeat(brushed, N // 64, axis=1)  # streaks along the plate
    brushed = fft_gauss_blur(brushed, 6.0)
    plate = srgb(CFG['logo_rgb']) * (1 + 0.06 * standardize(brushed)[..., None])
    col = plate * (1 - line[..., None]) + srgb(CFG['logo_line_rgb']) * line[..., None]
    return {'LogoPlate_Color': np.clip(col, 0, 1)}


def region_px(reg, n=N):
    u0, v0, u1, v1 = reg
    return int(round((1 - v1) * n)), int(round((1 - v0) * n)), int(round(u0 * n)), int(round(u1 * n))


def build_marks(layout, log):
    regs = layout['Marks']['regions']
    rgb = np.zeros((N, N, 3))
    a = np.zeros((N, N))
    rng = np.random.default_rng(SEEDS['marks'])

    def local(reg):
        r0, r1, c0, c1 = region_px(reg)
        h, w = r1 - r0, c1 - c0
        uu = (np.arange(w) + 0.5) / w  # 0..1 across the region (u)
        vv = 1.0 - (np.arange(h) + 0.5) / h  # 0..1 up the region (v)
        U_, V_ = np.meshgrid(uu, vv)
        return (slice(r0, r1), slice(c0, c1)), U_, V_
    # sticker: a white disc (anti-aliased) on the 1 in quad
    sl, U_, V_ = local(regs['sticker'])
    r = np.hypot(U_ - 0.5, V_ - 0.5)
    rad = CFG['sticker_diameter'] / 2
    edge = 1.0 / (sl[0].stop - sl[0].start)
    rgb[sl] = srgb(CFG['sticker_rgb'])
    a[sl] = CFG['sticker_alpha'] * (1 - smoothstep(rad - 1.5 * edge, rad + 1.5 * edge, r))
    # rack: a soft lighter triangle (rack box; the apex points to the head, -x = -u)
    sl, U_, V_ = local(regs['rack'])
    m = 0.14  # margin fraction of the box
    t = (U_ - m) / (1 - 2 * m)  # 0 at the apex column, 1 at the back row
    half = 0.5 * np.clip(t, 0, 1) * (1 - 2 * m)
    d_side = np.abs(V_ - 0.5) - half
    d = np.maximum(np.maximum(d_side, -t * (1 - 2 * m)), (t - 1) * (1 - 2 * m))
    blot = standardize(fft_gauss_blur(rng.standard_normal(U_.shape), 20.0))
    rgb[sl] = srgb(CFG['rack_rgb'])
    a[sl] = CFG['rack_alpha'] * (1 - smoothstep(-0.09, 0.08, d)) * np.clip(0.85 + 0.12 * blot, 0, 1)
    # break streak: a thin worn line along u, broken and fading at both ends
    sl, U_, V_ = local(regs['streak'])
    along = standardize(fft_gauss_blur(rng.standard_normal((1, U_.shape[1])), 6.0))
    width = 0.09 + 0.02 * along
    core = np.exp(-((V_ - 0.5 - 0.02 * along) / width) ** 2)
    ends = smoothstep(0.0, 0.08, U_) * smoothstep(1.0, 0.85, U_)
    speck = np.clip(0.75 + 0.35 * standardize(fft_gauss_blur(rng.standard_normal(U_.shape), 1.5)), 0, 1)
    rgb[sl] = srgb(CFG['streak_rgb'])
    a[sl] = CFG['streak_alpha'] * core * ends * speck
    # chalk: four blue smudges (a few scuffs of dust in each)
    for k in range(4):
        sl, U_, V_ = local(regs['chalk%d' % k])
        acc = np.zeros(U_.shape)
        for _ in range(3 + k % 2):
            cx, cy = 0.5 + rng.uniform(-0.15, 0.15), 0.5 + rng.uniform(-0.15, 0.15)
            ang = rng.uniform(0, np.pi)
            sx, sy = rng.uniform(0.09, 0.2), rng.uniform(0.04, 0.09)
            du, dv = U_ - cx, V_ - cy
            pu = du * np.cos(ang) + dv * np.sin(ang)
            pv = -du * np.sin(ang) + dv * np.cos(ang)
            acc += rng.uniform(0.35, 0.7) * np.exp(-(pu / sx) ** 2 - (pv / sy) ** 2)
        dust = np.clip(0.7 + 0.3 * standardize(fft_gauss_blur(rng.standard_normal(U_.shape), 2.0)), 0, 1)
        fade = 1 - smoothstep(0.38, 0.5, np.maximum(np.abs(U_ - 0.5), np.abs(V_ - 0.5)))
        rgb[sl] = srgb(CFG['chalk_rgb'])
        a[sl] = CFG['chalk_alpha'] * np.clip(acc, 0, 1) * dust * fade
    # toe strip: v 0 is 0.3 in under the cushion rubber; darkest at the nose (v 0.2), gone at v 1
    sl, U_, V_ = local(regs['toe'])
    ends = smoothstep(0.0, 0.03, U_) * smoothstep(1.0, 0.97, U_)
    rgb[sl] = 0.0
    a[sl] = CFG['toe_alpha'] * (1 - smoothstep(0.2, 1.0, V_)) ** 1.6 * ends
    # rim ring: v 0 at the hole edge, v 1 an inch out
    sl, U_, V_ = local(regs['rim'])
    ends = smoothstep(0.0, 0.05, U_) * smoothstep(1.0, 0.95, U_)
    rgb[sl] = 0.0
    a[sl] = CFG['rim_alpha'] * (1 - smoothstep(0.0, 1.0, V_)) ** 1.4 * ends
    return {'Marks_Color': np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], axis=2)}


# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------

def body_geometry(params, g):
    """Where the painted contact lines sit in the Body strips (inches, physics frame)."""
    p = params
    kb = PX_PER_IN['body'] / N
    rail_bottom = p['rail_bottom']
    z_top = rail_bottom - p['skirt_height'] - p['cabinet_visible']
    z_floor = -g['cloth']['above_floor']
    z_seam = z_top + (z_floor - z_top) * p['leg_seam_fraction']
    z_foot = z_floor + p['leveller_height']
    bead_arc = p['skirt_top_chamfer'] * 2 ** 0.5 + (p['skirt_height'] - p['skirt_top_chamfer'] - 0.3)
    return {'u_block_top': 0.5 + rail_bottom * kb, 'u_leg_top': 0.5 + z_top * kb, 'u_leg_seam': 0.5 + z_seam * kb,
            'groove_half_u': p['leg_groove'] / 2 * kb, 'u_leg_foot': 0.5 + z_foot * kb,
            'skirt_bead_arc': bead_arc + 0.2, 'v_cab_top': 0.73}


MAP_INFO = {
    'Cloth_Color': ('Cloth', 'ColorMap', 'sRGB', 'near-white grey, tinted per look by SurfaceAppearance.Color'),
    'Cloth_Normal': ('Cloth', 'NormalMap', 'Non-Color', 'fibre + faint twill, OpenGL'),
    'Cloth_Roughness': ('Cloth', 'RoughnessMap', 'Non-Color', '0.82..0.96'),
    'Rails_Color_Black': ('Rails', 'ColorMap', 'sRGB', 'blue look: satin black PRC, faint grain, pearl sights'),
    'Rails_Color_Cherry': ('Rails', 'ColorMap', 'sRGB', 'green look: red-brown cherry, pearl sights'),
    'Rails_Normal': ('Rails', 'NormalMap', 'Non-Color', 'faint grain relief, both looks'),
    'Rails_Roughness': ('Rails', 'RoughnessMap', 'Non-Color', 'satin lacquer, both looks'),
    'Body_Color_Black': ('Body', 'ColorMap', 'sRGB', 'blue look; black cabinet, rubber levellers'),
    'Body_Color_Cherry': ('Body', 'ColorMap', 'sRGB', 'green look; black cabinet, rubber levellers'),
    'Body_Normal': ('Body', 'NormalMap', 'Non-Color', 'both looks'),
    'Body_Roughness': ('Body', 'RoughnessMap', 'Non-Color', 'both looks'),
    'Parts_Color': ('Pockets, Caps, Hardware', 'ColorMap', 'sRGB', 'leather, cups, chrome'),
    'Parts_Normal': ('Pockets, Caps, Hardware', 'NormalMap', 'Non-Color', 'leather pebble'),
    'Parts_Roughness': ('Pockets, Caps, Hardware', 'RoughnessMap', 'Non-Color', ''),
    'Parts_Metalness': ('Pockets, Caps, Hardware', 'MetalnessMap', 'Non-Color', '1 on chrome'),
    'LogoPlate_Color': ('LogoPlate', 'ColorMap', 'sRGB', 'blank satin black plate, nickel pinstripe'),
    'Marks_Color': ('Marks', 'ColorMap', 'sRGB+alpha', 'AlphaMode Transparency; RGB dilated under alpha 0'),
}


def main():
    with open(os.path.join(HERE, 'Parameters.json')) as f:
        params_all = json.load(f)
    with open(os.path.join(HERE, 'Geometry.json')) as f:
        g = json.load(f)
    layout = params_all['uv_layout']
    params = params_all['parameters']
    assert layout['Cloth']['studs_per_repeat'] == 1.5
    assert layout['Rails']['strips']['pearl']['v'] == [0.87, 0.94]
    assert layout['Body']['strips']['cabinet']['v'] == [0.73, 0.83]
    assert layout['Parts']['regions']['chrome_top']['v'] == [0.7, 0.8]
    os.makedirs(MASTER_DIR, exist_ok=True)
    os.makedirs(SRC_DIR, exist_ok=True)
    previous = load_sources_record()
    srcs = {s['name']: fetch(s, previous) for s in SOURCES}
    log = {}
    geo = body_geometry(params, g)
    maps = {}
    order = []

    def emit(d):
        for name, arr in d.items():
            maps[name] = arr
            order.append(name)
            master = os.path.join(MASTER_DIR, name + '.png')
            upload = os.path.join(TEX_DIR, name + '.png')
            write_png(master, arr)
            if name.endswith('_Normal'):
                small = down_normal(arr, N // UP)
            else:
                small = box_down(arr, N // UP)
            write_png(upload, small)
            stats = small.reshape(UP * UP, -1).mean(axis=0)
            print('TEX', name, 'mean', np.round(stats * 255, 1).tolist())
            maps[name] = (master, upload, stats)
    emit(build_cloth(srcs, log))
    G = wood_grain_source(srcs, log)
    emit(build_rails(G, log))
    emit(build_body(G, geo, log))
    del G
    emit(build_parts(srcs, log))
    emit(build_logo(log))
    emit(build_marks(layout, log))

    today = datetime.date.today().isoformat()
    src_records = []
    for s in SOURCES:
        got = srcs[s['name']]
        rec = {k: s[k] for k in ('name', 'title', 'url', 'page', 'licence', 'licence_url')}
        if got:
            rec.update({'date': got['__date__'], 'file': os.path.relpath(got['__file__'], HERE), 'sha256': got['__sha__'],
                        'used': {m: sha256_file(got[m]) for m in (s['members'] or [s['file']])}})
        else:
            rec.update({'date': today, 'unavailable': True})
        src_records.append(rec)
    with open(os.path.join(SRC_DIR, 'Sources.json'), 'w') as f:
        json.dump({'note': 'CC0 sources for TableTextures.py; files live in sources/<name>/ (git-ignored) and are '
                           'downloaded again from these URLs; sha256 is of the downloaded file',
                   'sources': src_records}, f, indent=2, sort_keys=True)
        f.write('\n')
    entries = []
    for name in order:
        master, upload, stats = maps[name]
        mesh, slot, space, note = MAP_INFO[name]
        entries.append({'name': name, 'file': os.path.relpath(upload, HERE), 'size': [UP, UP],
                        'channels': 'RGBA' if name == 'Marks_Color' else 'RGB', 'mesh': mesh,
                        'surface_appearance': slot, 'colour_space': space, 'note': note,
                        'mean_0_255': [round(float(x) * 255, 1) for x in stats],
                        'sha256': sha256_file(upload), 'master': os.path.relpath(master, HERE),
                        'master_size': [N, N], 'master_sha256': sha256_file(master)})
    looks = {
        'blue': {'Cloth.Color': [1, 169, 247], 'Rails.ColorMap': 'Rails_Color_Black', 'Body.ColorMap': 'Body_Color_Black'},
        'green': {'Cloth.Color': [40, 175, 45], 'Rails.ColorMap': 'Rails_Color_Cherry', 'Body.ColorMap': 'Body_Color_Cherry'},
    }
    doc = {
        'generator': 'assets/table/TableTextures.py',
        'parameters_sha256': sha256_file(os.path.join(HERE, 'Parameters.json')),
        'master_px': N, 'upload_px': UP,
        'convention': 'Blender UV: (0,0) bottom-left of the image; OpenGL normals; uploads are the masters '
                      'box-filtered 4x (normals renormalised)',
        'looks': looks,
        'maps': entries,
        'recipe': {
            'cloth': log.get('cloth'), 'wood': log.get('wood'), 'leather': log.get('leather'),
            'strips': 'grain along U, every strip seamless in U; contact darkening painted in (skirt top under '
                      'the rail lip, block tops, leg tops, leg seam groove, cabinet top, rail edges)',
            'config': CFG,
        },
        'seeds': SEEDS,
        'sources': 'sources/Sources.json',
    }
    with open(os.path.join(HERE, 'Textures.json'), 'w') as f:
        json.dump(doc, f, indent=2, sort_keys=True)
        f.write('\n')
    print('TEX OK', len(entries), 'maps')


if __name__ == '__main__':
    main()
