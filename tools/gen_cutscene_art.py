#!/usr/bin/env python3
"""Generate the pull cutscenes' effect textures (Config.Cutscenes.Art; designer, 2026-10-05).

Most art is white on transparency, tinted in Roblox (Beam.Color, ParticleEmitter.Color,
ImageLabel.ImageColor3); the Mythic's sky art is colour baked (straight alpha, bright colours
only, for additive LightEmission 1, so dark means transparent). Drawn with numpy and Pillow from
fixed seeds so a rerun gives the same pixels. A Beam's texture runs along the beam on the
image's X axis and across its width on Y, so the beam textures tile in X (TextureMode Wrap).

The first five images share RNG (seed 8, consumed in order); every image added after them owns
its own generator, so the older files stay byte-identical whatever changes below them.

Outputs (assets/cutscenes/):
  beam_energy.png    512 x 128  bright streaks running along the beam inside a soft core
  beam_soft.png      64 x 128   a plain soft falloff across the width (the beam's wide glow)
  aurora_curtain.png 512 x 256  aurora curtain: fine vertical rays, a bright lower band
                                fading up into nothing, tileable along the curtain
  light_streak.png   64 x 512   one soft light streak (shooting lights, the warp's stars)
  star_flare.png     512 x 512  a pointed eight-spike star with a hot core (the Legendary's star)
  Mythic "Starfall" (docs/prompts/PULL_CUTSCENES_V2.md):
  milky_way.png      1024 x 256 colour baked: a pastel galactic band (pink, lilac and cyan
                                clouds, a whitish core, dark dust lanes, dense star dust) for a
                                Stretch Beam; fades out at the top, bottom and both ends
  nebula_puff_a.png  512 x 512  colour baked: a soft pink-to-lilac nebula cloud, faint stars,
                                transparent well before the edges
  nebula_puff_b.png  512 x 512  colour baked: the same in cyan to lilac
  celestial_sigil.png 1024 x 1024 white: a celestial magic circle for the ground (glowing rings,
                                a 72/12 tick dial, constellations, 8- and 12-point star polygons,
                                sparkles, a bright centre); corners transparent
  light_shard.png    128 x 512  white: a thin glowing crystal shard (bright core line, soft glow)

Upload with tools/roblox_upload.py (Decal ids), turn them into image ids with
tools/manifest_image_ids.py, and paste the image ids into Config.Cutscenes.Art.

Run: python3 tools/gen_cutscene_art.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cutscenes")
RNG = np.random.default_rng(8)


def save(name, alpha):
    """White pixels with `alpha` (0..1 floats, rows x columns) as a PNG."""
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = a
    Image.fromarray(rgba).save(os.path.join(OUT, name))
    print("wrote", name, a.shape[1], "x", a.shape[0])


def tileable_noise(width, octaves, rng):
    """1D noise along X that wraps (sums of whole-period sines with random phases)."""
    x = np.arange(width) / width
    n = np.zeros(width)
    for k in range(1, octaves + 1):
        n += rng.uniform(0.3, 1.0) / k * np.sin(2 * np.pi * (k * x + rng.uniform()))
    n -= n.min()
    return n / max(n.max(), 1e-6)


def beam_energy():
    w, h = 512, 128
    y = (np.arange(h) - (h - 1) / 2) / (h / 2)  # -1..1 across the width
    core = np.exp(-(y / 0.22) ** 2)  # the bright centre line
    soft = np.exp(-(y / 0.6) ** 2) * 0.35
    alpha = np.tile((core + soft)[:, None], (1, w))
    # Streaks running along the beam: thin lines at random heights, each with a tileable
    # brightness that comes and goes along X.
    for _ in range(26):
        row = RNG.uniform(-0.75, 0.75)
        thick = RNG.uniform(0.02, 0.06)
        line = np.exp(-((y - row) / thick) ** 2)
        along = tileable_noise(w, 5, RNG) ** 3
        alpha += line[:, None] * along[None, :] * RNG.uniform(0.5, 1.0)
    edge = np.clip(1 - np.abs(y) ** 4, 0, 1)  # fade to nothing at both edges
    save("beam_energy.png", alpha * edge[:, None])


def beam_soft():
    w, h = 64, 128
    y = (np.arange(h) - (h - 1) / 2) / (h / 2)
    alpha = np.exp(-(y / 0.45) ** 2) * np.clip(1 - np.abs(y) ** 3, 0, 1)
    save("beam_soft.png", np.tile(alpha[:, None], (1, w)))


def aurora_curtain():
    w, h = 512, 256
    v = np.arange(h) / (h - 1)  # 0 top .. 1 bottom
    # Bright just above the lower edge, a quick fall below it, a long fade upward.
    band = np.where(v < 0.8, (v / 0.8) ** 2.2, np.exp(-((v - 0.8) / 0.07) ** 2))
    # Fine vertical rays, tileable along X: many sines plus thin random spikes.
    rays = 0.35 + 0.65 * tileable_noise(w, 24, RNG)
    x = np.arange(w)
    for _ in range(40):
        c = RNG.uniform(0, w)
        d = np.minimum(np.abs(x - c), w - np.abs(x - c))  # wrapped distance
        rays += RNG.uniform(0.3, 0.9) * np.exp(-(d / RNG.uniform(1.5, 5)) ** 2)
    rays /= rays.max()
    # Rays reach different heights: the top edge of each ray moves with a slow noise.
    reach = 0.25 + 0.6 * tileable_noise(w, 6, RNG)
    top = np.clip((v[:, None] - (1 - reach[None, :]) * 0.8) / 0.35 + 0.5, 0, 1)
    alpha = band[:, None] * (0.55 + 0.45 * rays[None, :]) * top
    save("aurora_curtain.png", alpha / alpha.max())


def light_streak():
    w, h = 64, 512
    x = (np.arange(w) - (w - 1) / 2) / (w / 2)
    v = np.arange(h) / (h - 1)
    across = np.exp(-(x / 0.18) ** 2) + 0.3 * np.exp(-(x / 0.5) ** 2)
    # A bright head near the bottom tapering into a long tail toward the top.
    along = np.where(v > 0.85, np.exp(-((v - 0.85) / 0.06) ** 2), (v / 0.85) ** 1.6)
    save("light_streak.png", np.outer(along, across))


def star_flare():
    size = 512
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size]
    x = (xx - c) / c  # -1..1
    y = (yy - c) / c
    r = np.sqrt(x * x + y * y)
    alpha = np.zeros((size, size))
    # (angle, length, base width): vertical longest, horizontal next, diagonals short.
    spikes = [(90, 1.0, 0.05), (0, 0.72, 0.045), (45, 0.42, 0.035), (135, 0.42, 0.035)]
    for angle, length, width in spikes:
        a = np.radians(angle)
        along = np.abs(x * np.cos(a) + y * np.sin(a))  # both directions
        across = np.abs(-x * np.sin(a) + y * np.cos(a))
        k = np.clip(1 - along / length, 0, 1)  # 1 at the middle, 0 at the tip
        w = width * k ** 1.3 + 1e-4  # tapers to a point
        alpha = np.maximum(alpha, np.exp(-((across / w) ** 2)) * k ** 0.8)
    core = np.exp(-((r / 0.07) ** 2))
    halo = np.exp(-((r / 0.22) ** 2)) * 0.35
    save("star_flare.png", np.clip(alpha + core + halo, 0, 1))


# --- Mythic "Starfall" art (docs/prompts/PULL_CUTSCENES_V2.md) ---------------------------------
# Every function below makes its own np.random.default_rng(seed) and never touches RNG, so the
# five images above stay byte-identical.

PINK = np.array([255, 156, 230]) / 255
LILAC = np.array([183, 156, 255]) / 255
CYAN = np.array([127, 231, 255]) / 255
WHITE = np.ones(3)
SS = 2  # line art is drawn at SS times the size, then shrunk with LANCZOS (anti-aliasing)


def save_rgba(name, rgb, alpha):
    """Colour-baked pixels: `rgb` (rows x columns x 3) and `alpha` (rows x columns), 0..1
    floats, straight (not premultiplied) alpha. Keep rgb bright even where alpha is ~0, so
    filtering and mipmaps never pull a dark fringe into an additive texture."""
    a = np.round(np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    rgba[..., 3] = a
    Image.fromarray(rgba).save(os.path.join(OUT, name))
    print("wrote", name, a.shape[1], "x", a.shape[0])


def smooth(e0, e1, x):
    """Smoothstep: 0 at e0, 1 at e1 (either order), smooth in between."""
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def norm01(a, lo=1, hi=99):
    """Stretch `a` so its lo..hi percentiles span 0..1 (clipped)."""
    p0, p1 = np.percentile(a, [lo, hi])
    return np.clip((a - p0) / (p1 - p0), 0, 1)


def mix(a, b, t):
    """Blend colour a into colour b by t (an array of weights, or a number)."""
    t = np.asarray(t, float)
    return a + (b - a) * (t[..., None] if t.ndim else t)


class Noise:
    """2D gradient (Perlin) noise with a quintic fade on a wrapping lattice of random unit
    gradients drawn from `rng`: smooth at every scale (clouds, never static), about -1..1."""

    def __init__(self, rng, size=512):
        angle = rng.uniform(0, 2 * np.pi, (size, size))
        self.gx, self.gy, self.size = np.cos(angle), np.sin(angle), size

    def __call__(self, x, y):
        x0, y0 = np.floor(x), np.floor(y)
        fx, fy = x - x0, y - y0
        i0 = x0.astype(np.int64) % self.size
        j0 = y0.astype(np.int64) % self.size
        i1, j1 = (i0 + 1) % self.size, (j0 + 1) % self.size

        def corner(j, i, dx, dy):
            return self.gx[j, i] * dx + self.gy[j, i] * dy

        u = fx**3 * (fx * (fx * 6 - 15) + 10)
        v = fy**3 * (fy * (fy * 6 - 15) + 10)
        top = corner(j0, i0, fx, fy) * (1 - u) + corner(j0, i1, fx - 1, fy) * u
        bottom = corner(j1, i0, fx, fy - 1) * (1 - u) + corner(j1, i1, fx - 1, fy - 1) * u
        return (top * (1 - v) + bottom * v) * np.sqrt(2)

    def fbm(self, x, y, octaves, gain=0.5, puffy=False):
        """Fractal sum: each octave twice the frequency and `gain` the strength of the last,
        turned and shifted so the lattices never line up. About -1..1 (0..1 when `puffy`: the
        octaves' absolute values, billowing cloud shapes)."""
        total = np.zeros(np.broadcast(x, y).shape)
        amp, freq, norm = 1.0, 1.0, 0.0
        for k in range(octaves):
            c, s = np.cos(0.9 * k + 0.3), np.sin(0.9 * k + 0.3)
            xr, yr = (x * c - y * s) * freq + 31.7 * k, (x * s + y * c) * freq + 17.3 * k
            layer = self(xr, yr)
            total += amp * (np.abs(layer) if puffy else layer)
            norm += amp
            amp *= gain
            freq *= 2
        return total / norm


def blur(img, sigma):
    """Gaussian blur (sigma in pixels) with transparent surroundings (FFT on a padded copy)."""
    pad = int(4 * sigma) + 2
    big = np.pad(img, pad)
    fy = np.fft.fftfreq(big.shape[0])[:, None]
    fx = np.fft.rfftfreq(big.shape[1])[None, :]
    kernel = np.exp(-2 * (np.pi * sigma) ** 2 * (fx * fx + fy * fy))
    out = np.fft.irfft2(np.fft.rfft2(big) * kernel, s=big.shape)
    return np.clip(out[pad:-pad, pad:-pad], 0, None)


def downsample(img, factor=SS):
    """Shrink a float image by `factor` with LANCZOS: the anti-aliasing step of the line art."""
    h, w = img.shape
    small = Image.fromarray(img.astype(np.float32))
    small = small.resize((w // factor, h // factor), Image.LANCZOS)
    return np.clip(np.asarray(small, float), 0, None)


class Canvas:
    """Line art drawn as coverage on a canvas SS times the final size (positions and sizes in
    final pixels, pixel centres at i + 0.5): every edge is anti-aliased, then the LANCZOS
    downsample smooths it again. Overlaps keep the brighter value."""

    def __init__(self, w, h):
        self.img = np.zeros((h * SS, w * SS))

    def _box(self, x0, y0, x1, y1):
        h, w = self.img.shape
        xa, xb = max(int(x0 * SS) - 2, 0), min(int(x1 * SS) + 3, w)
        ya, yb = max(int(y0 * SS) - 2, 0), min(int(y1 * SS) + 3, h)
        yy, xx = np.mgrid[ya:yb, xa:xb]
        return (slice(ya, yb), slice(xa, xb)), (xx + 0.5) / SS, (yy + 0.5) / SS

    def _put(self, box, edge, alpha):
        """`edge`: signed distance inside the shape, in final pixels."""
        cov = np.clip(edge * SS + 0.5, 0, 1) * alpha
        np.maximum(self.img[box], cov, out=self.img[box])

    def ring(self, cx, cy, radius, width, alpha=1.0):
        reach = radius + width
        box, xx, yy = self._box(cx - reach, cy - reach, cx + reach, cy + reach)
        self._put(box, width / 2 - np.abs(np.hypot(xx - cx, yy - cy) - radius), alpha)

    def line(self, x0, y0, x1, y1, width, alpha=1.0):
        """A straight stroke with round ends."""
        box, xx, yy = self._box(
            min(x0, x1) - width, min(y0, y1) - width, max(x0, x1) + width, max(y0, y1) + width
        )
        vx, vy = x1 - x0, y1 - y0
        t = np.clip(((xx - x0) * vx + (yy - y0) * vy) / max(vx * vx + vy * vy, 1e-9), 0, 1)
        self._put(box, width / 2 - np.hypot(xx - x0 - t * vx, yy - y0 - t * vy), alpha)

    def dot(self, x, y, radius, alpha=1.0):
        box, xx, yy = self._box(x - radius - 1, y - radius - 1, x + radius + 1, y + radius + 1)
        self._put(box, radius - np.hypot(xx - x, yy - y), alpha)

    def sparkle(self, x, y, length, width, angle=0.0, alpha=1.0):
        """A four-point star: two crossed spikes tapering to sharp tips, and a round core."""
        box, xx, yy = self._box(x - length, y - length, x + length, y + length)
        dx, dy = xx - x, yy - y
        c, s = np.cos(angle), np.sin(angle)
        a, b = np.abs(dx * c + dy * s), np.abs(dy * c - dx * s)
        edge = width * 0.55 - np.hypot(dx, dy)
        for along, across in ((a, b), (b, a)):
            k = 1 - along / length
            edge = np.maximum(edge, np.where(k > 0, width / 2 * np.clip(k, 0, 1) ** 2 - across, -1))
        self._put(box, edge, alpha)

    def down(self):
        return downsample(self.img)


def erf(x):
    """The error function (Abramowitz and Stegun 7.1.26, error under 2e-7): numpy has none."""
    t = 1 / (1 + 0.3275911 * np.abs(x))
    poly = 1.421413741 + t * (-1.453152027 + t * 1.061405429)
    poly = t * (0.254829592 + t * (-0.284496736 + t * poly))
    return np.sign(x) * (1 - poly * np.exp(-x * x))


def stars(shape, xs, ys, sigma, peak, colour=None):
    """Gaussian stars, one per entry of the arrays `xs`, `ys` (pixel position), `sigma` (size
    in pixels) and `peak` (brightness of a star centred on a pixel). Each star is integrated over
    the pixel area, so sub-pixel positions stay anti-aliased. With `colour` (stars x 3) the field
    is rows x columns x 3."""
    h, w = shape
    r = int(np.ceil(3.5 * np.max(sigma)))
    off = np.arange(-r, r + 1)
    px = np.floor(xs).astype(np.int64)[:, None] + off
    py = np.floor(ys).astype(np.int64)[:, None] + off
    s = np.sqrt(2) * np.asarray(sigma, float)[:, None]
    wx = 0.5 * (erf((px + 1 - xs[:, None]) / s) - erf((px - xs[:, None]) / s))
    wy = 0.5 * (erf((py + 1 - ys[:, None]) / s) - erf((py - ys[:, None]) / s))
    centred = erf(0.5 / s[:, 0]) ** 2  # a centred star's share of its own pixel
    wgt = wy[:, :, None] * wx[:, None, :] * (np.asarray(peak, float) / centred)[:, None, None]
    yy = np.broadcast_to(py[:, :, None], wgt.shape)
    xx = np.broadcast_to(px[:, None, :], wgt.shape)
    ok = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
    idx = (yy * w + xx)[ok]
    if colour is None:
        return np.bincount(idx, weights=wgt[ok], minlength=h * w).reshape(h, w)
    layers = []
    for col in colour.T:  # one channel at a time
        layers.append(np.bincount(idx, weights=(wgt * col[:, None, None])[ok], minlength=h * w))
    return np.stack(layers, axis=-1).reshape(h, w, 3)


def star_colours(rng, n, tint=0.45):
    """Mostly white stars, some faintly pink, lilac or cyan."""
    tinted = [mix(WHITE, col, tint) for col in (PINK, LILAC, CYAN)]
    choices = np.array([WHITE, WHITE, WHITE] + tinted)
    return choices[rng.integers(0, len(choices), n)]


def emission_to_rgba(emission, fallback_rgb, knee=0.6):
    """Additive light (rows x columns x 3, premultiplied) to straight-alpha colour: alpha is the
    brightest channel, rolled off softly above `knee` so hot spots never clip flat; rgb is the
    light's colour at full brightness (the fallback colour where there is no light)."""
    m = emission.max(axis=2)
    alpha = np.where(m < knee, m, knee + (1 - knee) * (1 - np.exp(-(m - knee) / (1 - knee))))
    lit = m[..., None] > 1e-5
    rgb = np.where(lit, emission / np.maximum(m, 1e-5)[..., None], fallback_rgb)
    return rgb, alpha


def palette(t):
    """0 cyan, 0.5 lilac, 1 pink."""
    t = np.clip(t, 0, 1)
    return np.where((t < 0.5)[..., None], mix(CYAN, LILAC, t * 2), mix(LILAC, PINK, t * 2 - 1))


def milky_way():
    rng = np.random.default_rng(21)
    noise = Noise(rng)
    w, h = 1024, 256
    u = (np.arange(w) + 0.5) / w  # 0..1 along the band
    v = (np.arange(h) + 0.5 - h / 2) / (h / 2)  # -1..1 across it
    U, V = np.meshgrid(u, v)
    px, py = U * 7.0, V * 1.8  # noise space: clouds stretched along the band
    flat = np.zeros_like(U)

    # The band: a centre line that wanders a little, wider and brighter in the middle (bulge).
    centre = 0.1 * noise.fbm(px * 0.3, flat + 5.5, 3)
    bulge = np.exp(-(((U - 0.46) / 0.2) ** 2))
    width = 0.27 + 0.1 * bulge
    d = (V - centre) / width  # distance from the centre line, in band widths
    warp_x = noise.fbm(px + 5.2, py + 1.3, 4)
    warp_y = noise.fbm(px + 1.7, py + 9.2, 4)
    profile = np.exp(-1.2 * (d + 0.8 * warp_y) ** 2)  # wispy edges
    clouds = smooth(0.1, 0.9, norm01(noise.fbm(px + 1.6 * warp_x, py + warp_y, 6))) ** 1.2
    haze = 0.3 * np.exp(-((d / 2.0) ** 2)) * (0.65 + 0.35 * bulge)
    body = 0.9 * profile * (0.15 + 0.85 * clouds) * (0.65 + 0.35 * bulge)
    grain = norm01(noise.fbm(px * 2.6 + 7.7, py * 2.6 + 2.2, 5))  # star-cloud mottling
    core = 1.9 * np.exp(-((d / 0.32) ** 2)) * (0.35 + 0.65 * grain) * (0.35 + 0.65 * bulge)

    # Small glowing knots along the band (star clusters, pink and cyan nebulae).
    knots = np.zeros((h, w, 3))
    k = 16
    kx, ky = rng.uniform(0.1, 0.9, k) * w, (1 + rng.normal(0, 0.12, k)) * h / 2
    kcol = np.array([PINK, mix(PINK, WHITE, 0.4), CYAN, LILAC])[rng.integers(0, 4, k)]
    gx, gy = U * w, (V + 1) * h / 2  # pixel coordinates
    for i in range(k):
        size = rng.uniform(3, 9)
        blob = np.exp(-(((gx - kx[i]) / (size * 1.6)) ** 2 + ((gy - ky[i]) / size) ** 2))
        knots += blob[..., None] * kcol[i] * rng.uniform(0.25, 0.55)

    # Dust: soft dark patches stretched along the band and crowded near its plane, and a
    # dark rift running just off the core along the middle stretch, torn into pieces.
    lane = norm01(noise.fbm(px * 0.9 + 0.8 * warp_x + 3.0, py * 3.2 + 1.2 * warp_y + 6.6, 6))
    lanes = blur(smooth(0.48, 0.85, lane), 1.5) * np.exp(-((d / 0.9) ** 2))
    lanes *= 0.4 + 0.6 * norm01(noise.fbm(px * 1.7 + 2.2, py * 1.7 + 7.4, 4))  # thin in places
    wander = 0.15 * np.sin(U * 9.0 + 0.8) + 0.2 * noise.fbm(px * 0.8 + 3.3, flat + 8.8, 3)
    rift_v = centre + width * wander
    rift = np.exp(-(((V - rift_v) / (width * (0.12 + 0.1 * bulge))) ** 2))
    rift *= smooth(0.12, 0.3, U) * smooth(0.88, 0.7, U)
    rift *= smooth(0.3, 0.65, norm01(noise.fbm(px * 1.3 + 9.1, py * 2 + 4.4, 4)))
    clear = 1 - np.clip(0.6 * lanes + 0.65 * rift, 0, 0.82)

    # Colour drifts through cyan, lilac and pink along the band (an S-curve keeps real pink and
    # cyan regions, blending through lilac); the core is pinker and whiter.
    hue = norm01(noise.fbm(px * 0.35 + 13.1, py * 0.5 + 5.3, 3)) + 0.25 * (bulge - 0.5)
    hue = smooth(0.12, 0.88, hue)
    cloud_rgb = palette(hue)
    core_rgb = mix(palette(np.clip(hue + 0.2, 0, 1)), WHITE, 0.78)
    light = (haze + body)[..., None] * cloud_rgb + core[..., None] * core_rgb + knots
    for c in range(3):  # a soft bloom makes the band glow; dust and stars come after it
        light[..., c] += 0.3 * blur(light[..., c], 3) + 0.25 * blur(light[..., c], 10)
    light *= clear[..., None]

    # Stars: dust (tiny, faint, crowding the bright clear parts), field stars, a few bright ones.
    dens = (body + core) * clear
    dens /= dens.max()
    n = 16000
    sx, sy = rng.uniform(0, w, n * 4), rng.uniform(0, h, n * 4)
    keep = rng.uniform(0, 1, n * 4) < 0.04 + 0.96 * dens[sy.astype(int), sx.astype(int)]
    sx, sy = sx[keep][:n], sy[keep][:n]
    k = len(sx)
    peak = 0.06 + 0.4 * rng.uniform(0, 1, k) ** 3
    light += stars((h, w), sx, sy, np.full(k, 0.5), peak, star_colours(rng, k))
    k = 900
    sx, sy = rng.uniform(0, w, k), rng.uniform(0, h, k)
    sig, peak = rng.uniform(0.5, 0.75, k), 0.25 + 0.55 * rng.uniform(0, 1, k) ** 2
    light += stars((h, w), sx, sy, sig, peak, star_colours(rng, k))
    k = 28
    sx, sy = rng.uniform(0, w, k), h / 2 + rng.normal(0, h * 0.2, k)
    cols = star_colours(rng, k, 0.3)
    light += stars((h, w), sx, sy, rng.uniform(0.7, 0.9, k), rng.uniform(0.85, 1.0, k), cols)
    sig, peak = rng.uniform(2.5, 4.0, k), rng.uniform(0.12, 0.2, k)
    light += stars((h, w), sx, sy, sig, peak, cols)  # their glow

    # Fade to nothing at the top and bottom and over the last ~12% of each end.
    fade = smooth(0, 0.12, U) * smooth(1, 0.88, U) * smooth(1.0, 0.55, np.abs(V))
    rgb, alpha = emission_to_rgba(0.8 * light * fade[..., None], cloud_rgb, knee=0.55)
    save_rgba("milky_way.png", rgb, alpha)


def nebula_puff(name, seed, dense, thin):
    """A soft nebula cloud: `dense` colour in its bright folds, `thin` in its wisps."""
    rng = np.random.default_rng(seed)
    noise = Noise(rng)
    size = 512
    c = (np.arange(size) + 0.5 - size / 2) / (size / 2)  # -1..1
    X, Y = np.meshgrid(c, c)
    r = np.hypot(X, Y)

    # Layers of gently domain-warped noise (a strong warp turns to marble): a soft base, puffy
    # billows, and faint bright filaments (the ridges of a third noise), all kept continuous so
    # the bright parts have gradients rather than flat plateaus.
    f = 1.4
    q1, q2 = noise.fbm(X * f + 1.3, Y * f + 7.1, 4), noise.fbm(X * f + 8.4, Y * f + 2.6, 4)
    base = norm01(noise.fbm(X * f + 0.9 * q1, Y * f + 0.9 * q2, 6))
    billow = norm01(noise.fbm(X * 2.2 + 1.2 * q1 + 9.0, Y * 2.2 + 1.2 * q2 + 3.0, 6, puffy=True))
    ridge = 1 - np.abs(noise.fbm(X * 2.0 + 1.5 * q2 + 4.0, Y * 2.0 + 1.5 * q1 + 6.0, 5)) * 3
    filaments = np.clip(ridge, 0, 1) ** 4

    # The silhouette: a soft radial falloff whose radius wobbles, hard-limited to 0.84 of the
    # half size, so the cloud is gone well before the edges and never shows its square.
    wobble = noise.fbm(X * 1.1 + 21.0, Y * 1.1 + 4.0, 3)
    rw = r * (1 + 0.6 * wobble)
    limit = smooth(0.84, 0.62, r)
    fall = np.exp(-((rw / 0.44) ** 2)) * limit
    cloud = fall * (0.1 + 0.9 * base**1.8) * (0.45 + 0.55 * billow) * 1.6
    cloud += 0.35 * filaments * fall * base
    cloud += 0.18 * np.exp(-((rw / 0.3) ** 2)) * limit  # a luminous heart

    t = np.clip(cloud / cloud.max() * 1.3 + 0.3 * noise.fbm(X * 0.9 + 5.0, Y * 0.9 + 1.0, 3), 0, 1)
    rgb = mix(mix(thin, dense, t), WHITE, 0.35 * t**3)
    light = cloud[..., None] * rgb
    for ch in range(3):
        light[..., ch] += 0.35 * blur(light[..., ch], 5)

    # Faint stars embedded in the cloud.
    k = 90
    ang, rad = rng.uniform(0, 2 * np.pi, k), 0.62 * np.sqrt(rng.uniform(0, 1, k))
    sx, sy = size / 2 * (1 + rad * np.cos(ang)), size / 2 * (1 + rad * np.sin(ang))
    peak = (0.15 + 0.45 * rng.uniform(0, 1, k) ** 2) * smooth(0.65, 0.3, rad)
    light += stars((size, size), sx, sy, rng.uniform(0.5, 0.8, k), peak, star_colours(rng, k, 0.3))
    rgb, alpha = emission_to_rgba(light * 1.1, mix(thin, dense, 0.5))
    save_rgba(name, rgb, alpha)


def celestial_sigil():
    rng = np.random.default_rng(63)
    size = 1024
    c = R = size / 2  # the centre; radii below are fractions of R
    art = Canvas(size, size)

    def at(radius, angle):
        return c + radius * R * np.cos(angle), c + radius * R * np.sin(angle)

    def star_polygon(n, k, radius, turn, width, alpha=1.0):
        """{n/k}: n points on a circle, each joined to the one k steps on."""
        pts = [at(radius, turn + 2 * np.pi * i / n) for i in range(n)]
        for i in range(n):
            art.line(*pts[i], *pts[(i + k) % n], width, alpha)
        return pts

    def tidy(pts, edges, radii):
        """No two lines cross, and no line passes close to a star it does not join."""

        def side(a, b, p):
            return np.sign((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]))

        def gap(p, a, b):  # distance from p to the segment ab
            ab, ap = np.subtract(b, a), np.subtract(p, a)
            return np.hypot(*(ap - np.clip(ap @ ab / (ab @ ab), 0, 1) * ab))

        for m, e in enumerate(edges):
            a, b = pts[e[0]], pts[e[1]]
            for f in edges[m + 1 :]:
                p, q = pts[f[0]], pts[f[1]]
                cross = side(a, b, p) != side(a, b, q) and side(p, q, a) != side(p, q, b)
                if cross and not set(e) & set(f):
                    return False
            if any(gap(p, a, b) < radii[k] + 7 for k, p in enumerate(pts) if k not in e):
                return False
        return True

    # Rings and the dial: 72 small ticks, 12 large ones joining the dial to the crisp ring.
    band_stars = []  # every dot in the constellation band, so the faint stars keep clear
    art.ring(c, c, 0.885 * R, 3)
    art.ring(c, c, 0.855 * R, 2)
    art.ring(c, c, 0.795 * R, 2)
    for i in range(72):
        a = 2 * np.pi * i / 72 - np.pi / 2
        if i % 6 == 0:
            art.line(*at(0.795, a), *at(0.885, a), 4)
            art.dot(*at(0.773, a), 3.5)
            band_stars.append(at(0.773, a))
        else:
            art.line(*at(0.855, a), *at(0.83, a), 2)
    art.ring(c, c, 0.6 * R, 3)
    art.ring(c, c, 0.575 * R, 2)

    # The octagram {8/3} touching the inner rings, sparkles at its points; a {12/5} rosette in
    # a small ring at its heart.
    points = star_polygon(8, 3, 0.575, -np.pi / 2, 2.5)
    art.ring(c, c, 0.3 * R, 2)
    small = star_polygon(12, 5, 0.3, -np.pi / 2, 2, 0.9)
    glints = []  # (x, y, size): soft halos added at full size
    for x, y in points:
        art.sparkle(x, y, 22, 6, np.arctan2(y - c, x - c) + np.pi / 4)
        glints.append((x, y, 7))
    for x, y in small:
        art.dot(x, y, 3)

    # Constellations: one per 30-degree sector of the band between the dial and the inner rings,
    # 3-6 stars chained nearest-first (sometimes closing a small loop), joined by thin lines
    # that stop short of each star; faint single stars scattered between them.
    for sector in range(12):
        mid = 2 * np.pi * (sector + 0.5) / 12 - np.pi / 2
        n = int(rng.integers(3, 7))
        while True:  # draw clusters until one is tidy
            pts = []
            while len(pts) < n:
                p = at(rng.uniform(0.65, 0.75), mid + rng.uniform(-0.18, 0.18))
                if all(np.hypot(p[0] - q[0], p[1] - q[1]) > 26 for q in pts):
                    pts.append(p)
            pts.sort(key=lambda p: np.arctan2(p[1] - c, p[0] - c) - mid)
            chain = [pts.pop(0)]
            while pts:
                pts.sort(key=lambda p: np.hypot(p[0] - chain[-1][0], p[1] - chain[-1][1]))
                chain.append(pts.pop(0))
            radii = rng.uniform(2.4, 3.4, n)
            radii[rng.integers(0, n)] = 4.6  # each cluster's brightest star
            edges = [(i, i + 1) for i in range(n - 1)]
            if tidy(chain, edges, radii):
                break
        if n >= 5 and rng.uniform() < 0.6 and tidy(chain, edges + [(n - 1, n - 4)], radii):
            edges.append((n - 1, n - 4))
        for i, j in edges:
            (x0, y0), (x1, y1) = chain[i], chain[j]
            length = np.hypot(x1 - x0, y1 - y0)
            ux, uy = (x1 - x0) / length, (y1 - y0) / length
            g0, g1 = radii[i] + 4, radii[j] + 4
            art.line(x0 + ux * g0, y0 + uy * g0, x1 - ux * g1, y1 - uy * g1, 1.8, 0.8)
        for (x, y), rad in zip(chain, radii):
            art.dot(x, y, rad)
            band_stars.append((x, y))
            if rad > 4:
                art.sparkle(x, y, 12, 3.5, np.pi / 4)
                glints.append((x, y, 5))
    placed = 0
    while placed < 40:
        x, y = at(rng.uniform(0.63, 0.77), rng.uniform(0, 2 * np.pi))
        if all(np.hypot(x - p[0], y - p[1]) > 14 for p in band_stars):
            art.dot(x, y, rng.uniform(1.1, 1.7), rng.uniform(0.45, 0.8))
            band_stars.append((x, y))
            placed += 1

    # Soft light at full size: the thick glowing outer ring, the bright centre (saturating
    # smoothly, so no disc edge), halos on the sparkles, a faint glow over the disc, and a glow
    # around every line.
    lines = art.down()
    yy, xx = np.mgrid[0:size, 0:size] + 0.5
    r = np.hypot(xx - c, yy - c) / R
    outer = 0.7 * np.exp(-(((r - 0.93) / 0.016) ** 2)) + 0.3 * np.exp(-(((r - 0.93) / 0.03) ** 2))
    centre = 1.2 * np.exp(-((r / 0.035) ** 2)) + 0.55 * np.exp(-((r / 0.09) ** 2))
    centre = 1 - np.exp(-1.6 * (centre + 0.25 * np.exp(-((r / 0.2) ** 2))))
    halo = sum(0.5 * np.exp(-((xx - x) ** 2 + (yy - y) ** 2) / (2 * s * s)) for x, y, s in glints)
    fill = 0.05 * smooth(0.9, 0.86, r)
    glow = 0.45 * blur(lines, 3) + 0.3 * blur(lines, 10)
    alpha = np.clip(lines + glow + outer + centre + halo + fill, 0, 1) * smooth(0.995, 0.975, r)
    save("celestial_sigil.png", alpha)


def light_shard():
    """A thin crystal shard of light: a long diamond, widest above its middle, with a lit facet
    and a shaded one, a bright rim, a sharp core line running past both tips, and a soft glow."""
    w, h = 128, 512
    top, widest, bottom, half = 24.0, 200.0, 488.0, 9.0  # tips, widest row, half-width (pixels)
    yy, xx = np.mgrid[0 : h * SS, 0 : w * SS]
    x, y = (xx + 0.5) / SS - w / 2, (yy + 0.5) / SS
    upper = y < widest
    hw = np.where(upper, half * (y - top) / (widest - top), half * (bottom - y) / (bottom - widest))
    slope = np.where(upper, half / (widest - top), half / (bottom - widest))
    edge = (hw - np.abs(x)) / np.sqrt(1 + slope**2)  # distance inside the outline
    body = np.clip(edge * SS + 0.5, 0, 1)
    across = np.clip(np.abs(x) / np.maximum(hw, 1e-3), 0, 1)
    facet = np.where(x < 0, 0.4, 0.24) + 0.18 * (1 - across) ** 2  # lit from the left
    rim = np.clip((1.1 - edge) * SS, 0, 1) * body * np.where(x < 0, 0.8, 0.5)
    reach = smooth(top - 26, top + 12, y) * smooth(bottom + 26, bottom - 12, y)
    core = downsample(np.clip((0.7 - np.abs(x)) * SS + 0.5, 0, 1) * reach)
    shard = np.maximum(downsample(np.maximum(body * facet, rim)), core)
    glow = 0.3 * blur(shard, 2) + 0.7 * blur(shard, 7) + blur(shard, 18) + 0.5 * blur(core, 1.2)
    # Screen the glow over the shard (the body never flattens to white), fade out at the edges.
    alpha = 1 - (1 - np.clip(shard, 0, 1)) * (1 - np.clip(glow, 0, 1))
    v, u = (np.arange(h) + 0.5) / h, (np.arange(w) + 0.5) / w
    ends, sides = smooth(0, 0.03, v) * smooth(1, 0.97, v), smooth(0, 0.08, u) * smooth(1, 0.92, u)
    fade = np.outer(ends, sides)
    save("light_shard.png", alpha * fade)


def main():
    os.makedirs(OUT, exist_ok=True)
    beam_energy()
    beam_soft()
    aurora_curtain()
    light_streak()
    star_flare()
    milky_way()
    nebula_puff("nebula_puff_a.png", 34, PINK, LILAC)
    nebula_puff("nebula_puff_b.png", 41, CYAN, LILAC)
    celestial_sigil()
    light_shard()


if __name__ == "__main__":
    main()
