"""The rooftop map's textures, drawn procedurally (no photos), so a re-run is the tweak.

    python3 assets/map/gen_textures.py

Each image is authored at 2048 and exported at 1024 (Roblox renders 1024 at most; the
downsample avoids shimmer) into assets/map/textures/. Colours come only from the measured
palette (map_common.ALBEDO); soft ambient occlusion is painted into the colour maps as
gradients that darken toward the art's cool shadow tint, since Roblox has no GI on phones.

    arch_color.png     the architecture trim sheet (map_common.TRIM): wall, top, riser,
                       column, fascia, wood, facade, dark strips
    floor_color.png    the floor MaterialVariant: 2 x 2 tiles of 4.5 studs (StudsPerTile 9)
    floor_normal.png   its normal map (OpenGL, +Y up): the grout sits a little lower
    foliage.png        RGBA: a hanging vine band, a climbing vine, a bougainvillea cluster
    overlays.png       RGBA: the warm glow under a table, a wall-foot shade, a column shade
"""

import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_common as mc  # noqa: E402

SEED = 26092026
MASTER = 2048
EXPORT = 1024
OUT = os.path.join(HERE, 'textures')

P = {
    'tile_studs': 4.5,  # one floor tile
    'grout_studs': 0.07,  # grout line width
    'grout_darken': 0.11,  # grout this much darker (about 8 L*)
    'tile_jitter': 0.022,  # per-tile lightness variation
    'mottle': 0.012,  # soft variation inside a tile
    'edge_soft_studs': 0.05,  # the tile's rounded edge
    'normal_strength': 3.0,
}


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

def periodic_noise(rng, h, w, scale_px):
    """Smooth noise, periodic in both axes (FFT low-pass of white noise), mean 0, std 1."""
    white = rng.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    sigma = 1.0 / max(scale_px, 1.0)
    filt = np.exp(-(fx * fx + fy * fy) / (2 * sigma * sigma))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    return (out - out.mean()) / (out.std() + 1e-9)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def colour_array(hex_colour):
    return np.array(mc.rgb(hex_colour), dtype=np.float64)


def toward_shadow(base, amount):
    """base (..., 3) darkened toward the palette's cool shadow tint by amount (...)."""
    tint = colour_array(mc.ALBEDO['shadow'])
    return base + (tint - base) * amount[..., None]


def save_rgb(arr, name):
    img = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8)).convert('RGB')
    img = img.resize((EXPORT, EXPORT), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    return img


def save_rgba(rgb_arr, alpha, name, bleed=None):
    """Premultiplied downsample (no dark fringes), then the RGB of clear pixels is set to
    `bleed` (a nearby colour) so mip levels do not halo."""
    a = np.clip(alpha, 0.0, 1.0)
    pre = np.dstack([rgb_arr * a[..., None], a * 255.0])
    img = Image.fromarray(np.clip(pre + 0.5, 0, 255).astype(np.uint8))
    small = np.asarray(img.resize((EXPORT, EXPORT), Image.LANCZOS)).astype(np.float64)
    sa = small[..., 3] / 255.0
    rgb_out = np.where(sa[..., None] > 1e-3, small[..., :3] / np.maximum(sa[..., None], 1e-3), 0.0)
    if bleed is not None:
        fill = np.broadcast_to(np.asarray(bleed, dtype=np.float64), rgb_out.shape)
        weight = smoothstep(0.0, 0.25, sa)[..., None]
        rgb_out = rgb_out * weight + fill * (1 - weight)
    out = np.dstack([np.clip(rgb_out, 0, 255), small[..., 3]])
    img = Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8))
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    return img


# ---------------------------------------------------------------------------------------------
# Floor
# ---------------------------------------------------------------------------------------------

def floor(rng):
    n = MASTER
    studs = 2 * P['tile_studs']
    px = n / studs
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    tx, ty = (x / px) % P['tile_studs'], (y / px) % P['tile_studs']
    # Distance to the nearest grout line, studs.
    d = np.minimum(np.minimum(tx, P['tile_studs'] - tx), np.minimum(ty, P['tile_studs'] - ty))
    half = P['grout_studs'] / 2
    inside = smoothstep(half, half + P['edge_soft_studs'], d)  # 0 in the grout, 1 on the tile
    base = colour_array(mc.ALBEDO['floor'])
    # Per-tile lightness (the four tiles of the image), and a soft mottle.
    ix, iy = (x // (px * P['tile_studs'])).astype(int), (y // (px * P['tile_studs'])).astype(int)
    jitter = rng.uniform(-1, 1, (2, 2))[iy % 2, ix % 2] * P['tile_jitter']
    mottle = periodic_noise(rng, n, n, n / 6) * P['mottle']
    tile = base[None, None, :] * (1 + jitter + mottle)[..., None]
    grout = toward_shadow(base[None, None, :] * (1 - P['grout_darken']), np.full((n, n), 0.12))
    colour = tile * inside[..., None] + grout * (1 - inside[..., None])
    save_rgb(colour, 'floor_color.png')
    # Normal map from a height field (the tile surface 1, the grout 0), OpenGL convention.
    h = inside
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / 2
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) / 2
    k = P['normal_strength']
    nx, ny, nz = -gx * k, gy * k, np.ones_like(h)  # image rows go down, +Y (green) points up
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.dstack([nx / length, ny / length, nz / length])
    save_rgb((normal * 0.5 + 0.5) * 255.0, 'floor_normal.png')


# ---------------------------------------------------------------------------------------------
# Architecture trim sheet
# ---------------------------------------------------------------------------------------------

def arch(rng):
    n = MASTER
    s = n / mc.TRIM_PX  # master pixels per trim pixel
    img = np.zeros((n, n, 3))
    stone = colour_array(mc.ALBEDO['stone'])
    cream = colour_array(mc.ALBEDO['cream'])
    wood = colour_array(mc.ALBEDO['wood'])

    def strip(name):
        top, bottom, _ = mc.TRIM[name]
        r0, r1 = int(top * s), int(bottom * s)
        v = 1.0 - (np.arange(r0, r1) + 0.5 - r0) / (r1 - r0)  # 1 at the strip's top, 0 at its foot
        return r0, r1, v[:, None]

    def paint(name, colour_fn):
        r0, r1, v = strip(name)
        img[r0:r1] = colour_fn(v, r1 - r0)

    fine = periodic_noise(rng, n, n, 18)
    soft = periodic_noise(rng, n, n, 160)

    def texture(base, rows, r0, amount_fine=0.008, amount_soft=0.012):
        var = fine[r0:r0 + rows] * amount_fine + soft[r0:r0 + rows] * amount_soft
        return base[None, None, :] * (1 + var)[..., None]

    # Wall: AO over the lowest fifth, a light top edge.
    r0, r1, v = strip('wall')
    col = texture(stone, r1 - r0, r0)
    ao = (1 - smoothstep(0.0, 0.22, v)) * 0.42 + (1 - smoothstep(0.0, 0.05, v)) * 0.12
    col = toward_shadow(col, np.broadcast_to(ao, col.shape[:2]))
    col = col * (1 + 0.05 * smoothstep(0.93, 0.99, v))[..., None]
    img[r0:r1] = col
    # Top: the lit tops, slightly lighter.
    r0, r1, v = strip('top')
    img[r0:r1] = texture(stone * 1.04, r1 - r0, r0, 0.006, 0.01)
    # Riser: AO at the foot, a nosing highlight at the top.
    r0, r1, v = strip('riser')
    col = texture(stone * 0.97, r1 - r0, r0)
    ao = (1 - smoothstep(0.0, 0.3, v)) * 0.5
    col = toward_shadow(col, np.broadcast_to(ao, col.shape[:2]))
    col = col * (1 + 0.06 * smoothstep(0.86, 0.96, v))[..., None]
    img[r0:r1] = col
    # Column: AO at the foot and a little under the capital.
    r0, r1, v = strip('column')
    col = texture(cream, r1 - r0, r0, 0.006, 0.01)
    ao = (1 - smoothstep(0.0, 0.12, v)) * 0.38 + smoothstep(0.93, 1.0, v) * 0.14
    img[r0:r1] = toward_shadow(col, np.broadcast_to(ao, col.shape[:2]))
    # Fascia: a shadow line along its underside, a light top.
    r0, r1, v = strip('fascia')
    col = texture(cream * 1.02, r1 - r0, r0, 0.006, 0.01)
    ao = (1 - smoothstep(0.0, 0.18, v)) * 0.3
    col = toward_shadow(col, np.broadcast_to(ao, col.shape[:2]))
    img[r0:r1] = col * (1 + 0.05 * smoothstep(0.85, 0.97, v))[..., None]
    # Wood: grain along U (stretched noise), lighter towards the top.
    r0, r1, v = strip('wood')
    rows = r1 - r0
    grain = periodic_noise(rng, rows, n, 3)
    grain = (grain + np.roll(grain, 1, 1) + np.roll(grain, 2, 1) + np.roll(grain, -1, 1)) / 4
    streak = periodic_noise(rng, rows, n, 40)
    col = wood[None, None, :] * (1 + 0.07 * grain + 0.05 * streak)[..., None]
    col = col * (0.9 + 0.14 * v)[..., None]
    img[r0:r1] = col
    # Facade: one floor of the tower, 20 studs across, four windows.
    r0, r1, v = strip('facade')
    rows = r1 - r0
    studs_u = mc.TRIM['facade'][2]
    u = (np.arange(n) + 0.5) / n * studs_u
    hgt = v * mc.FACADE_FLOOR_STUDS  # studs above the floor line
    wall = mc.mix(mc.rgb(mc.ALBEDO['stone']), mc.rgb(mc.ALBEDO['facade']), 0.35)
    col = texture(np.array(wall), rows, r0, 0.006, 0.01)
    cell = u % 5.0
    win_x = (cell > 0.7) & (cell < 4.3)
    win_y = (hgt > 2.2) & (hgt < 8.6)
    glass_top = np.array(mc.rgb(mc.ALBEDO['window_sky']), dtype=np.float64)
    glass_low = np.array(mc.rgb(mc.ALBEDO['window']), dtype=np.float64)
    t = np.clip((hgt - 2.2) / 6.4, 0, 1)
    glass = glass_low[None, None, :] + (glass_top - glass_low)[None, None, :] * (t[..., None] ** 1.5)
    glass = np.broadcast_to(glass, (rows, n, 3))
    mask = (win_x[None, :] & win_y)
    col = np.where(mask[..., None], glass, col)
    # A sill shade under each window and the slab line at the foot.
    sill = (hgt > 1.9) & (hgt <= 2.2) & win_x[None, :]
    col = np.where(sill[..., None], toward_shadow(col, np.full(col.shape[:2], 0.35)), col)
    slab = hgt < 0.8
    col = np.where(np.broadcast_to(slab, col.shape[:2])[..., None], toward_shadow(col, np.full(col.shape[:2], 0.18)), col)
    img[r0:r1] = col
    # Dark: near black.
    r0, r1, v = strip('dark')
    img[r0:r1] = colour_array('#17171D')[None, None, :]
    save_rgb(img, 'arch_color.png')


# ---------------------------------------------------------------------------------------------
# Foliage
# ---------------------------------------------------------------------------------------------

def leaf(draw, cx, cy, length, width, angle, lit, dark, ss):
    """A two-tone leaf (a lens), the lit half toward the top left."""
    ca, sa = np.cos(angle), np.sin(angle)
    pts_a, pts_b = [], []
    for k in range(9):
        t = k / 8
        along = (t - 0.5) * length
        half = width / 2 * np.sin(np.pi * t) ** 0.8
        for side, pts in ((1, pts_a), (-1, pts_b)):
            x = cx + along * ca - side * half * sa
            y = cy + along * sa + side * half * ca
            pts.append((x * ss, y * ss))
    spine = [(cx + (t - 0.5) * length * ca, cy + (t - 0.5) * length * sa) for t in (0, 1)]
    spine = [(x * ss, y * ss) for x, y in spine]
    # The half whose outward side faces up-left is lit.
    lit_first = (-sa - ca) < 0
    draw.polygon(pts_a + spine[::-1], fill=lit if lit_first else dark)
    draw.polygon(pts_b + spine[::-1], fill=dark if lit_first else lit)


def foliage(rng):
    n = MASTER
    ss = 1  # the master is already 2x the export
    canvas = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    lit = mc.rgb(mc.ALBEDO['leaf_lit']) + (255,)
    mid = mc.rgb(mc.ALBEDO['leaf_mid']) + (255,)
    dark = mc.rgb(mc.ALBEDO['leaf_dark']) + (255,)
    stem = tuple(int(c) for c in mc.mix(mc.rgb(mc.ALBEDO['leaf_dark']), (60, 40, 30), 0.4)) + (255,)

    def leaves_along(points, density, size, wrap_w=None, x_off=0):
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            seg = np.hypot(x1 - x0, y1 - y0)
            count = max(1, int(seg * density))
            for k in range(count):
                t = rng.uniform(0, 1)
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                ang = rng.uniform(-np.pi, np.pi)
                ln = size * rng.uniform(0.75, 1.25)
                off = ln * 0.45
                cx, cy = x + off * np.cos(ang), y + off * np.sin(ang)
                pair = (lit, mid) if rng.uniform() < 0.6 else (mid, dark)
                xs = [cx + x_off] if wrap_w is None else [cx + x_off, cx + x_off - wrap_w, cx + x_off + wrap_w]
                for xx in xs:
                    leaf(draw, xx, cy, ln, ln * 0.55, ang, pair[0], pair[1], ss)

    # Drape: the top half (rows 0..n/2), seamless along U.
    band_h = n // 2
    width = n
    for k in range(70):
        x = rng.uniform(0, width)
        length = band_h * rng.uniform(0.2, 0.92)
        pts = [(x, 0.0)]
        yy, xx = 0.0, x
        while yy < length:
            yy += band_h * 0.05
            xx += rng.uniform(-10, 10)
            pts.append((xx, yy))
        for dx in (-width, 0, width):
            draw.line([(px + dx, py) for px, py in pts], fill=stem, width=5)
        leaves_along(pts, 0.05, 42, wrap_w=width)
    # A dense crown along the top edge, so the band covers the fascia's lower edge.
    crown = [(float(x), rng.uniform(10, band_h * 0.14)) for x in np.linspace(0, width, 60)]
    leaves_along(crown, 0.35, 56, wrap_w=width)
    # Climb: the bottom-left quarter, stems from its foot to its top.
    q = n // 2
    for k in range(5):
        x = q * (0.15 + 0.7 * k / 4) + rng.uniform(-30, 30)
        pts = [(x, float(n - 4))]
        yy, xx = n - 4.0, x
        while yy > q + 20:
            yy -= q * 0.05
            xx += rng.uniform(-28, 28)
            xx = min(max(xx, 30), q - 30)
            pts.append((xx, yy))
        draw.line(pts, fill=stem, width=6)
        leaves_along(pts, 0.045, 48)
    # Bloom: the bottom-right quarter, a round bougainvillea cluster over a few leaves.
    cx, cy, radius = q + q / 2, q + q / 2, q * 0.42
    for k in range(40):
        a, r = rng.uniform(0, 2 * np.pi), radius * np.sqrt(rng.uniform(0, 1))
        leaf(draw, cx + r * np.cos(a), cy + r * np.sin(a), 60, 32, rng.uniform(-np.pi, np.pi), mid, dark, ss)
    pink = mc.rgb(mc.ALBEDO['flower']) + (255,)
    pink_dark = mc.rgb(mc.ALBEDO['flower_dark']) + (255,)
    pink_light = tuple(int(c) for c in mc.mix(mc.rgb(mc.ALBEDO['flower']), (255, 255, 255), 0.35)) + (255,)
    for k in range(260):
        a, r = rng.uniform(0, 2 * np.pi), radius * np.sqrt(rng.uniform(0, 1))
        fx, fy = cx + r * np.cos(a), cy + r * np.sin(a)
        size = rng.uniform(14, 22)
        colour = pink_light if (fy < cy - radius * 0.2 and rng.uniform() < 0.6) else (pink if rng.uniform() < 0.7 else pink_dark)
        for petal in range(3):
            ang = petal * 2 * np.pi / 3 + rng.uniform(0, 1)
            pts = [(fx, fy), (fx + size * np.cos(ang - 0.5), fy + size * np.sin(ang - 0.5)),
                   (fx + size * 1.2 * np.cos(ang), fy + size * 1.2 * np.sin(ang)),
                   (fx + size * np.cos(ang + 0.5), fy + size * np.sin(ang + 0.5))]
            draw.polygon(pts, fill=colour)
    arr = np.asarray(canvas).astype(np.float64)
    save_rgba(arr[..., :3], arr[..., 3] / 255.0, 'foliage.png', bleed=mc.rgb(mc.ALBEDO['leaf_mid']))


# ---------------------------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------------------------

def overlays():
    n = MASTER
    rgb_arr = np.zeros((n, n, 3))
    alpha = np.zeros((n, n))
    half = n // 2
    # Glow: the left half maps the 22 x 14 glow plane; the table (18.24 x 10.24) in its middle.
    ys, xs = np.mgrid[0:n, 0:half].astype(np.float64)
    px_x, px_y = (xs + 0.5) / half * 22.0 - 11.0, (ys + 0.5) / n * 14.0 - 7.0
    hx, hy, r = 9.12, 5.12, 1.2
    qx, qy = np.abs(px_x) - (hx - r), np.abs(px_y) - (hy - r)
    dist = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
    glow = np.where(dist < 0, 1.0, np.exp(-np.maximum(dist, 0) / 1.1))
    edge_fade = smoothstep(0.0, 0.6, np.minimum(np.minimum(px_x + 11, 11 - px_x), np.minimum(px_y + 7, 7 - px_y)))
    alpha[:, :half] = 0.5 * glow * edge_fade
    rgb_arr[:, :half] = colour_array(mc.ALBEDO['glow'])
    # Edge: the top-right quarter (Blender V 0.5..1); dark at its bottom row (the wall).
    rows = np.arange(half)[:, None].astype(np.float64)
    t = 1.0 - (rows + 0.5) / half  # 0 at the wall (the quarter's bottom row), 1 clear
    alpha[:half, half:] = np.broadcast_to(0.42 * (1 - t) ** 2.2, (half, half))
    rgb_arr[:half, half:] = colour_array(mc.ALBEDO['shadow'])
    # Blob: the bottom-right quarter, a soft squarish shade under a column.
    ys, xs = np.mgrid[0:half, 0:half].astype(np.float64)
    cx = (xs + 0.5) / half * 2 - 1
    cy = (ys + 0.5) / half * 2 - 1
    rr = (np.abs(cx) ** 4 + np.abs(cy) ** 4) ** 0.25
    alpha[half:, half:] = 0.4 * np.clip(1 - rr, 0, 1) ** 1.6
    rgb_arr[half:, half:] = colour_array(mc.ALBEDO['shadow'])
    save_rgba(rgb_arr, alpha, 'overlays.png')


if __name__ == '__main__':
    rng = np.random.default_rng(SEED)
    floor(rng)
    arch(rng)
    foliage(rng)
    overlays()
    for name in sorted(os.listdir(OUT)):
        if name.endswith('.png'):
            im = Image.open(os.path.join(OUT, name))
            print(name, im.size, im.mode)
