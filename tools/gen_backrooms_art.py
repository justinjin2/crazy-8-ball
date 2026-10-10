#!/usr/bin/env python3
"""Generate the Secret pull cutscene's art (Config.Cutscenes.Secret; designer, 2026-10-10).

Brief: docs/prompts/PULL_CUTSCENES_V2.md ("Secret" and "Assets"). The Secret's dream is the
backrooms (the internet's Level 0: endless mono-yellow office halls, damp carpet, buzzing
fluorescent panels) seen through a worn VHS tape. Drawn with numpy and Pillow, each image from
its own fixed seed, so a rerun gives the same pixels and editing one image leaves the others
alone. Every noise, blur and splat here wraps at the image's edges (the blurs work in the
frequency domain), so the tileable images have no seams.

Outputs (assets/cutscenes/):
  backrooms_wallpaper.png 512 x 512  opaque. One full wall height (row 0 meets the ceiling, the
                                     last row the carpet), seamless left to right; square
                                     pixels, so a wall shows one image per wall height across.
                                     Sickly mono-yellow paper with a faint tone-on-tone print
                                     (every 32 px a ribbon of small stacked chevrons between two
                                     hairlines), fine grain, faint vertical streaks, strip seams
                                     every 256 px, a few drips, rising-damp tide marks and grime
                                     at the foot, a slightly darker top.
  backrooms_carpet.png    512 x 512  opaque, seamless both ways: damp worn beige-yellow-brown
                                     office carpet, fibres and noise at a few scales, soft
                                     darker damp blotches.
  backrooms_ceiling.png   512 x 512  opaque, seamless both ways: 2 x 2 yellowed acoustic drop
                                     ceiling tiles (256 px each) in a 7 px recessed grid with a
                                     slight bevel, pinholes and fissures, two faint water stains.
  vhs_scanlines.png       256 x 256  black with alpha, seamless: a 1 px line (alpha about 0.55,
                                     fluttering a little per line) every 3 px. 256 is not a
                                     multiple of 3: 85 lines, the one gap at the wrap is 4 px.
  vhs_noise.png           256 x 256  opaque grey grain (a touch smeared sideways like tape
                                     noise), seamless; its opacity is set in Roblox.
  vhs_tracking.png        1024 x 64  white with alpha: a tracking-error band of torn,
                                     sideways-streaked noise, densest on a jagged middle line,
                                     clear at the top and bottom rows; wraps left to right.
  vignette.png            512 x 512  white with alpha (tinted black for the tape's vignette and
                                     red for the heartbeat's edges in Roblox): clear in a wide
                                     middle, about 0.75 at the edge middles and 0.9 in the
                                     corners, dithered (no bands).

Upload with tools/roblox_upload.py (Decal ids), turn them into image ids with
tools/manifest_image_ids.py, and paste the image ids into Config.Cutscenes.Secret.

Run: python3 tools/gen_backrooms_art.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cutscenes")
SEED = 20261010  # each image draws from its own generator: SEED + 1, SEED + 2, ...


# ------------------------------------------------------------------------------------------ helpers


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smootherstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * t * (t * (6 * t - 15) + 10)


def blur(img, sx, sy=None):
    """Gaussian blur (standard deviations sx, sy in px) that wraps at the edges: it multiplies in
    the frequency domain, so a tileable image stays tileable."""
    sy = sx if sy is None else sy
    fy = np.fft.fftfreq(img.shape[0])[:, None]
    fx = np.fft.fftfreq(img.shape[1])[None, :]
    g = np.exp(-2 * np.pi**2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * g))


def normalised(n):
    n = n - n.mean()
    return n / n.std()


def noise(rng, shape, sx, sy=None):
    """Tileable gaussian noise, mean 0 and standard deviation 1, with features about sx by sy px
    (sx = 0: one value per pixel)."""
    n = rng.standard_normal(shape)
    if sx > 0 or (sy or 0) > 0:
        n = blur(n, sx, sy)
    return normalised(n)


def wrapped(d, period):
    """A signed offset folded into [-period / 2, period / 2): a distance that wraps."""
    return (d + period / 2) % period - period / 2


def splat(target, px, py, value):
    """Add `value` at the sub-pixel spots (px, py), shared bilinearly between the four nearest
    pixels; a spot past an edge lands on the other side."""
    h, w = target.shape
    x0 = np.floor(px - 0.5).astype(int)
    y0 = np.floor(py - 0.5).astype(int)
    fx = px - 0.5 - x0
    fy = py - 0.5 - y0
    for ox, oy, share in (
        (0, 0, (1 - fx) * (1 - fy)),
        (1, 0, fx * (1 - fy)),
        (0, 1, (1 - fx) * fy),
        (1, 1, fx * fy),
    ):
        np.add.at(target, ((y0 + oy) % h, (x0 + ox) % w), value * share)


def strokes(rng, size, count, length, value, curl=0.0):
    """`count` short strokes (carpet fibres, tile fissures) splatted into a size x size map that
    wraps: lengths in px from the (lo, hi) range, each carrying `value` (one per stroke), bending
    by up to about `curl` radians per px."""
    out = np.zeros((size, size))
    x = rng.uniform(0, size, count)
    y = rng.uniform(0, size, count)
    angle = rng.uniform(0, 2 * np.pi, count)
    turn = rng.normal(0, curl, count)
    step = rng.uniform(length[0], length[1], count)
    spots = int(np.ceil(length[1] * 2)) + 1  # about two spots per px
    step /= spots - 1
    for _ in range(spots):
        splat(out, x, y, value / spots)
        x += np.cos(angle) * step
        y += np.sin(angle) * step
        angle += turn * step
    return out


def darken(rgb, amount, tint=(1.0, 1.0, 1.0)):
    """Darken `rgb` (rows x columns x 3) by `amount` (0..1, per pixel; below 0 lightens). A tint
    above 1 on blue darkens blue faster: yellow goes brown."""
    rgb *= 1 - np.asarray(amount)[..., None] * np.asarray(tint)


def to_bytes(x, rng):
    """0..1 floats to bytes with a one-step triangular dither, so no gradient bands."""
    x = np.clip(x, 0, 1) * 255 + rng.uniform(-0.5, 0.5, x.shape) + rng.uniform(-0.5, 0.5, x.shape)
    return np.clip(np.round(x), 0, 255).astype(np.uint8)


def save(name, img):
    """Bytes (rows x columns x 3 or 4) as an RGB or RGBA PNG."""
    Image.fromarray(img).save(os.path.join(OUT, name))
    print("wrote", name, img.shape[1], "x", img.shape[0])


def save_rgb(name, rgb, rng):
    save(name, to_bytes(rgb, rng))


def save_ink(name, value, alpha, rng):
    """One flat colour (0 black, 255 white) with `alpha` (0..1); alpha 0 stays exactly 0."""
    a = to_bytes(alpha, rng)
    a[alpha <= 0] = 0
    rgba = np.zeros(alpha.shape + (4,), np.uint8)
    rgba[..., :3] = value
    rgba[..., 3] = a
    save(name, rgba)


# ------------------------------------------------------------------------------------- the hallway


def wallpaper_print(size, ss=4):
    """Coverage (0..1) of the wallpaper's tone-on-tone print, drawn ss times larger and averaged
    down so the thin strokes have soft edges: every 32 px a ribbon of small stacked chevrons
    (pointing up, 10 px apart down the wall) between two hairlines 14 px apart, with a plain
    band between ribbons. 512 / 32 is whole, so the print wraps left to right."""
    n = size * ss
    c = (np.arange(n) + 0.5) / ss  # pixel coordinates of the subsamples
    x = c[None, :]
    y = c[:, None]
    u = wrapped(x, 32.0)  # across a ribbon: 0 on its middle
    v = y % 10.0  # down one chevron
    arm, drop, half = 4.6, 0.75, 0.55  # chevron half width, arm slope, stroke half width (px)
    dist = np.abs((v - 2.0) - drop * np.abs(u)) / np.sqrt(1 + drop * drop)
    chevrons = (dist < half) & (np.abs(u) <= arm)
    rails = np.abs(np.abs(u) - 7.0) < 0.42
    ink = 1.0 * chevrons + 0.7 * rails
    return ink.reshape(size, ss, size, ss).mean(axis=(1, 3))


def wallpaper():
    """Level 0's wallpaper: one full wall height (row 0 meets the ceiling, the last row the
    carpet), tiling left to right."""
    rng = np.random.default_rng(SEED + 1)
    s = 512
    rows = np.arange(s)[:, None] + 0.5
    v = rows / s  # 0 at the ceiling .. 1 at the carpet
    x = np.arange(s)[None, :] + 0.5
    full = np.ones((s, s))

    # The paper: fine grain, fibres running down, faint vertical streaks, broad soft mottling.
    shade = (
        1
        + 0.012 * noise(rng, (s, s), 0)
        + 0.010 * noise(rng, (s, s), 0.6, 2.2)
        + 0.006 * noise(rng, (s, s), 3, 80)
        + 0.010 * noise(rng, (s, s), 55)
    )
    rgb = np.empty((s, s, 3))
    rgb[:] = np.array([210, 192, 106]) / 255
    rgb *= shade[..., None]
    rgb[..., 2] *= 1 - 0.025 * noise(rng, (s, s), 70)  # the yellow's strength wanders a little

    # The print: a darker, slightly richer yellow, worn a little unevenly.
    ink = wallpaper_print(s) * np.clip(0.85 + 0.2 * noise(rng, (s, s), 40), 0.4, 1.2)
    darken(rgb, ink, (0.075, 0.08, 0.13))

    # Seams between the strips of wallcovering (commercial rolls are about half a wall height
    # wide): a faint dark hairline with a lighter lip beside it, plainer in places.
    for cx in (8.0, 264.0):
        dx = wrapped(x - cx, s) * full
        strength = np.clip(0.7 + 0.35 * noise(rng, (s, 1), 0, 40), 0.2, 1.2)
        lip = np.exp(-(((dx - 1.3) / 0.6) ** 2))
        darken(rgb, strength * (0.05 * np.exp(-((dx / 0.55) ** 2)) - 0.02 * lip))

    # Drips: a few faint runs down from the ceiling, tapering out.
    for _ in range(3):
        cx = rng.uniform(0, s)
        length = rng.uniform(90, 240)
        width = rng.uniform(2.0, 4.5)
        sway = 2.5 * noise(rng, (s, 1), 0, 25)  # the run wanders a little sideways
        across = np.abs(wrapped(x - cx - sway, s)) / width
        along = smoothstep(length, length * 0.3, rows) * smoothstep(0, 12, rows)
        darken(rgb, rng.uniform(0.02, 0.035) * np.exp(-(across**2)) * along, (0.8, 1.0, 1.3))

    # Dirt specks, most of them low on the wall.
    specks = np.zeros((s, s))
    count = 160
    splat(specks, rng.uniform(0, s, count), s - np.abs(rng.normal(0, 110, count)),
          rng.uniform(0.3, 1.0, count))
    darken(rgb, np.clip(blur(specks, 0.6), 0, 1) * 0.35, (0.85, 1.0, 1.2))

    # Rising damp: ragged tide lines along the foot of the wall, each fading in and out along
    # it, with fainter older lines below and a slightly darker, browner inside.
    bend = 1.2 * noise(rng, (s, s), 1.5) + 2.5 * noise(rng, (s, s), 6)  # px, wiggles the lines
    for height, k in ((92, 1.0), (52, 0.8), (138, 0.55)):
        top = s - height
        top = top - 20 * noise(rng, (1, s), 45) - 6 * noise(rng, (1, s), 12)
        top = top - 1.5 * noise(rng, (1, s), 3)
        strength = k * smoothstep(-0.7, 0.8, noise(rng, (1, s), 70))
        d = rows + bend - top  # px below the line
        lines = np.exp(-((d / 1.6) ** 2)) + 0.4 * np.exp(-(((d - 8) / 1.4) ** 2))
        lines += 0.2 * np.exp(-(((d - 19) / 1.3) ** 2))
        inside = smoothstep(-1.0, 6.0, d)
        darken(rgb, strength * (0.065 * lines + 0.03 * inside), (0.8, 1.0, 1.35))

    # Grime: a dirty band at the foot with a ragged top, darkest at the carpet, browner, in
    # smudges that run along the wall (scuffs, mop splashes).
    edge = 0.84 + 0.03 * noise(rng, (1, s), 20) + 0.01 * noise(rng, (1, s), 4)
    smudges = 0.8 + 0.18 * noise(rng, (s, s), 22, 5) + 0.08 * noise(rng, (s, s), 3, 1.5)
    grime = smoothstep(edge, 1.0, v) ** 1.5 * np.clip(smudges, 0, 1.3)
    darken(rgb, 0.22 * grime, (0.85, 1.0, 1.1))
    darken(rgb, 0.22 * smoothstep(1 - 9 / s, 1, v) ** 1.5 * full, (0.9, 1.0, 1.1))  # the corner
    # The top: a slight darkening toward the ceiling.
    darken(rgb, 0.07 * smoothstep(0.17, 0.0, v) ** 1.3 * full)
    save_rgb("backrooms_wallpaper.png", rgb, rng)


def carpet():
    """Damp, worn office carpet; tiles both ways."""
    rng = np.random.default_rng(SEED + 2)
    s = 512
    # Fibres: many short strokes lying every way, some lighter, some darker.
    count = 90000
    fibres = normalised(blur(strokes(rng, s, count, (1.5, 4.5), rng.normal(0, 1, count)), 0.35))
    hue = normalised(blur(strokes(rng, s, count, (1.5, 4.5), rng.normal(0, 1, count)), 0.35))
    shade = (
        1
        + 0.065 * fibres
        + 0.035 * noise(rng, (s, s), 0)  # single fibre tips
        + 0.030 * noise(rng, (s, s), 1.6)  # tufts
        + 0.022 * noise(rng, (s, s), 6)  # clumps
        + 0.020 * noise(rng, (s, s), 26)  # the pile lying different ways
        + 0.012 * noise(rng, (s, s), 90)  # broad wear
    )
    rgb = np.empty((s, s, 3))
    rgb[:] = np.array([154, 134, 83]) / 255
    rgb *= shade[..., None]
    # The fibres differ a little in hue: some yellower, some browner.
    rgb[..., 0] *= 1 + 0.02 * hue
    rgb[..., 2] *= 1 - 0.035 * hue
    # Worn paths: broad, slightly lighter and greyer patches.
    wear = smoothstep(0.9, 2.2, noise(rng, (s, s), 55))
    rgb *= 1 + 0.03 * wear[..., None]
    rgb[..., 2] *= 1 + 0.03 * wear
    # Damp blotches: where a broad noise peaks, big soft darker browner patches.
    field = noise(rng, (s, s), 58) + 0.28 * noise(rng, (s, s), 16) + 0.08 * noise(rng, (s, s), 4)
    damp = smoothstep(0.9, 2.3, field)
    darken(rgb, 0.13 * damp, (0.9, 1.0, 1.15))
    save_rgb("backrooms_carpet.png", rgb, rng)


def ceiling():
    """2 x 2 yellowed acoustic drop-ceiling tiles in a recessed grid; tiles both ways."""
    rng = np.random.default_rng(SEED + 3)
    s, t = 512, 256
    full = np.ones((s, s))
    x = (np.arange(s)[None, :] + 0.5) * full
    y = (np.arange(s)[:, None] + 0.5) * full
    shade = (
        1
        + 0.020 * noise(rng, (s, s), 0)
        + 0.018 * noise(rng, (s, s), 1.2)
        + 0.018 * noise(rng, (s, s), 25)
    )
    tile = np.empty((s, s, 3))
    tile[:] = np.array([229, 223, 193]) / 255
    tile *= shade[..., None]
    # Each tile a little different (age, how yellowed).
    ix = (x // t).astype(int)
    iy = (y // t).astype(int)
    tile *= 1 + rng.normal(0, 0.012, (2, 2))[iy, ix][..., None]
    tile[..., 2] *= 1 - np.abs(rng.normal(0, 0.03, (2, 2)))[iy, ix]

    # Pinholes: a dense fine grey speckle, softened a little.
    holes = np.zeros((s, s))
    count = 20000
    depth = rng.uniform(0.1, 0.36, count) * (1 + 0.7 * (rng.random(count) < 0.15))
    splat(holes, rng.uniform(0, s, count), rng.uniform(0, s, count), depth)
    # Fissures: short worm-like grooves in the acoustic finish.
    count = 700
    holes += strokes(rng, s, count, (3, 9), rng.uniform(0.25, 0.5, count), curl=0.3)
    darken(tile, np.clip(blur(holes, 0.45), 0, 0.45), (1.0, 1.0, 0.9))

    # Faint water stains inside two tiles: a tinted inside and a browner tide line (plus a
    # fainter older line inside it), the edge bent by noise.
    bend = 0.10 * noise(rng, (s, s), 6) + 0.05 * noise(rng, (s, s), 2)
    for cx, cy, r, k in ((150, 360, 58, 1.0), (395, 120, 34, 0.6)):
        d = np.sqrt(((x - cx) / r) ** 2 + ((y - cy) / (r * 0.8)) ** 2) + bend
        inside = smoothstep(1.02, 0.96, d)
        lines = np.exp(-(((d - 1.0) / 0.035) ** 2)) + 0.4 * np.exp(-(((d - 0.72) / 0.03) ** 2))
        darken(tile, k * (0.035 * inside + 0.07 * lines), (0.6, 0.9, 1.6))

    # Each tile a touch darker toward its edges (a slight sag and the bevel's shade).
    sx = wrapped(x - 0.5, t)  # whole px across a vertical grid line, 0 on its centre
    sy = wrapped(y - 0.5, t)
    darken(tile, 0.03 * smoothstep(60, 4, np.minimum(np.abs(sx), np.abs(sy))))

    # The grid: 7 px lines centred on columns and rows 0 and 256 (so they wrap), a darker
    # beige-grey; the side away from the light in shade, the lit side a little brighter.
    grid = np.empty((s, s, 3))
    grid[:] = np.array([178, 171, 148]) / 255
    grid *= (1 + 0.02 * noise(rng, (s, s), 0.8))[..., None]
    # Light by px across a line, the line's own edges at +-2..3, the tiles' chamfers at +-4..5.
    profile = {-5: 0.96, -4: 0.90, -3: 0.82, -2: 0.91, 2: 1.05, 3: 1.10, 4: 1.04, 5: 1.015}

    def bevel(across, along):
        f = np.ones_like(across)
        for offset, light in profile.items():
            f[across == offset] = light
        return np.where(np.abs(along) <= 3, 1.0, f)  # no edges inside the crossing line

    on_grid = (np.abs(sx) <= 3) | (np.abs(sy) <= 3)
    rgb = np.where(on_grid[..., None], grid, tile)
    rgb *= (bevel(sx, sy) * bevel(sy, sx))[..., None]
    save_rgb("backrooms_ceiling.png", rgb, rng)


# ------------------------------------------------------------------------------------ the VHS tape


def vhs_scanlines():
    """Black lines with alpha: one row every 3, alpha about 0.55 with a slight flutter."""
    rng = np.random.default_rng(SEED + 4)
    s = 256
    alpha = np.zeros((s, s))
    for row in range(0, s - 3, 3):  # rows 0, 3, ..., 252: the gap across the wrap is 4 rows
        alpha[row] = np.clip(0.55 + rng.normal(0, 0.03), 0.46, 0.64)
    alpha *= 1 + 0.03 * noise(rng, (s, s), 6, 0)  # and a faint shimmer along each line
    save_ink("vhs_scanlines.png", 0, alpha, rng)


def vhs_noise():
    """Grey grain, mostly per pixel with a little sideways smear like tape noise."""
    rng = np.random.default_rng(SEED + 5)
    s = 256
    g = normalised(0.75 * noise(rng, (s, s), 0) + 0.45 * noise(rng, (s, s), 1.6, 0.3))
    grey = to_bytes(0.5 + 0.17 * g, rng)
    rgba = np.empty((s, s, 4), np.uint8)
    rgba[..., :3] = grey[..., None]
    rgba[..., 3] = 255
    save("vhs_noise.png", rgba)


def vhs_tracking():
    """White with alpha: a torn tracking-error band, wrapping left to right."""
    rng = np.random.default_rng(SEED + 6)
    w, h = 1024, 64
    x = np.arange(w)[None, :] + 0.5
    y = np.arange(h)[:, None] + 0.5
    # The tear: the middle line jumps between heights in runs (wrapping), plus a jitter.
    cuts = np.sort(rng.uniform(0, w, 22))
    levels = rng.normal(0, 2.6, len(cuts))
    seg = np.searchsorted(cuts, x[0]) % len(cuts)
    mid = h / 2 + levels[seg] + 0.8 * noise(rng, (1, w), 2)[0] + 1.5 * noise(rng, (1, w), 60)[0]
    gain = rng.uniform(0.35, 1.0, len(cuts))[seg]  # how strong each torn run is
    dy = y - mid[None, :]
    # Streaks: noise stretched sideways at three lengths, kept to its bright peaks.
    long = smoothstep(0.4, 2.2, noise(rng, (h, w), 40, 0.6))
    mid_len = smoothstep(0.6, 2.4, noise(rng, (h, w), 9, 0.5))
    specks = smoothstep(1.0, 2.6, noise(rng, (h, w), 1.5, 0.4))
    core = np.exp(-((dy / 1.7) ** 2)) * gain[None, :]
    near = np.exp(-((dy / 7.5) ** 2))
    wide = np.exp(-((dy / 17.0) ** 2))
    alpha = core * (0.6 + 0.4 * mid_len) + near * (0.85 * long + 0.6 * mid_len)
    alpha += wide * (0.25 * long + 0.6 * specks)
    # Dropouts: thin bright dashes near the tear.
    for _ in range(40):
        row = int(np.clip(round(h / 2 + rng.normal(0, 5)), 0, h - 1))
        start = rng.uniform(0, w)
        length = rng.uniform(6, 160)
        along = wrapped(x[0] - start - length / 2, w)
        dash = smoothstep(length / 2, length / 2 - 4, np.abs(along)) * rng.uniform(0.5, 1.0)
        alpha[row] = np.maximum(alpha[row], dash)
    edge = np.minimum(y, h - y)  # clear at the top and bottom rows
    alpha = np.clip(alpha, 0, 1) * smoothstep(0.5, 16, edge)
    save_ink("vhs_tracking.png", 255, alpha, rng)


def vignette():
    """White with alpha (tinted in Roblox): clear in a wide middle, darker toward the edges and most in the
    corners (about 0.75 at the edge middles, 0.9 at the corners), dithered."""
    rng = np.random.default_rng(SEED + 7)
    s = 512
    c = (np.arange(s) + 0.5) / s * 2 - 1  # -1..1 across
    p = 4.0  # a rounded square: d is 1 at the edge middles, 2 ** (1 / p) in the corners
    d = (np.abs(c)[None, :] ** p + np.abs(c)[:, None] ** p) ** (1 / p)
    # Clear inside 55 % of the half width, a soft rise to 0.75 at the edge middles, then on
    # along the edges to 0.9 in the corners.
    alpha = 0.75 * smootherstep(0.55, 1.0, d) + 0.15 * smootherstep(1.0, 2 ** (1 / p), d)
    save_ink("vignette.png", 255, alpha, rng)


def main():
    os.makedirs(OUT, exist_ok=True)
    wallpaper()
    carpet()
    ceiling()
    vhs_scanlines()
    vhs_noise()
    vhs_tracking()
    vignette()


if __name__ == "__main__":
    main()
