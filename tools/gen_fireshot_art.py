"""Fire Shot's cloth art (the designer's third rework round, 2026-10-08): the scorch marks the
look lays on the cloth where the burning cue ball rolled, and the fire under its aim lines. Our
own procedural art (numpy + PIL).

    python3 tools/gen_fireshot_art.py

Writes assets/abilities/FireShot/:
  * scorch_strip.png (128 x 512): the burn line, tileable along its length (V). A ragged
    char band down the middle with streaks, soft soot round it and speckles at its edges.
  * scorch_splat.png (256 x 256): the burn under a hit or the launch: a jagged blot with
    flame-shaped rays and speckles round it.
Both are light greyscale with the shape in the alpha, so the look tints them (Decal or
Texture Color3) from hot orange to char as they cool.
  * fire_river.png (128 x 512): the river of fire under the aim lines (a Beam's texture: a
    Beam lays an image's height along its length), tileable along its length (V). A band of flame with ragged, flickering edges: yellow-orange
    down the middle, orange, then red to a dark red rim that holds it off the bright blue
    cloth, bright streaks running along it and a few embers beside it. Coloured, opaque inside:
    it is alpha-blended, as an additive glow washes out to pink and white on the cloth.
"""

import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "abilities", "FireShot")
os.makedirs(OUT, exist_ok=True)
RNG = np.random.default_rng(20261008)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def periodic_noise_1d(v, terms):
    """A smooth wobble along v in [0, 1) that wraps (integer frequencies)."""
    out = np.zeros_like(v)
    for freq, amp in terms:
        out += amp * np.sin(2 * math.pi * (freq * v + RNG.random()))
    return out


def periodic_noise_2d(u, v, octaves, wrap_u=False):
    """Value-ish noise from random sine waves: wraps along v (and u when asked)."""
    out = np.zeros_like(u)
    for freq_v, freq_u, amp in octaves:
        for _ in range(3):
            fu = freq_u if wrap_u else freq_u * (0.7 + 0.6 * RNG.random())
            ph = RNG.random()
            out += amp / 3 * np.sin(2 * math.pi * (freq_v * v + fu * u + ph))
    return out


def strip():
    w, h = 128, 512
    u, v = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    half = 0.27 + periodic_noise_1d(v, [(3, 0.03), (7, 0.02), (13, 0.012), (29, 0.006)])
    jitter = periodic_noise_2d(u, v, [(17, 9.0, 0.025), (41, 23.0, 0.012)])
    d = np.abs(u - 0.5) + jitter
    core = smoothstep(half + 0.035, half - 0.035, d)
    # Soot round the band, fading out before the strip's sides.
    blotches = periodic_noise_2d(u, v, [(2, 4.0, 0.6), (5, -7.0, 0.4), (9, 11.0, 0.3)])
    soot = smoothstep(0.47, half, d) * (0.42 + 0.2 * blotches)
    soot = np.clip(soot, 0, 1)
    # Speckles: a few scattered blots of soot beyond the band's edge.
    speck = np.zeros_like(u)
    for _ in range(70):
        cy = RNG.random()
        side = 1 if RNG.random() < 0.5 else -1
        cx = 0.5 + side * (0.24 + RNG.random() * 0.2)
        r = 0.006 + RNG.random() * 0.016
        dy = np.minimum(np.abs(v - cy), 1 - np.abs(v - cy)) * (h / w)  # wraps along v
        dist = np.sqrt((u - cx) ** 2 + dy ** 2)
        speck = np.maximum(speck, smoothstep(r, r * 0.4, dist) * (0.55 + 0.4 * RNG.random()))
    alpha = np.clip(np.maximum(core * 0.95, np.maximum(soot, speck)), 0, 1)
    # Light inside, streaked along the burn, a touch darker at the band's edge.
    streak = periodic_noise_2d(u, v, [(1, 13.0, 1.0), (2, 29.0, 0.5), (7, 3.0, 0.4)])
    value = 0.86 + 0.1 * streak - 0.12 * smoothstep(half * 0.4, half, d)
    value = np.clip(value, 0.55, 1.0)
    return value, alpha


def splat():
    n = 256
    y, x = np.meshgrid((np.arange(n) + 0.5) / n - 0.5, (np.arange(n) + 0.5) / n - 0.5,
                       indexing="ij")
    r = np.sqrt(x * x + y * y)
    th = np.arctan2(y, x)
    # A jagged blot: its edge wobbles round the angle (integer harmonics, so it closes).
    edge = 0.2
    for k, amp in ((3, 0.02), (5, 0.016), (8, 0.012), (13, 0.008), (21, 0.005)):
        edge = edge + amp * np.sin(k * th + RNG.random() * 2 * math.pi)
    blot = smoothstep(edge + 0.02, edge - 0.02, r)
    # Flame-shaped rays licking out of it.
    rays = np.zeros_like(r)
    for _ in range(13):
        a0 = RNG.random() * 2 * math.pi
        length = 0.3 + RNG.random() * 0.15
        width = 0.09 + RNG.random() * 0.08
        da = np.angle(np.exp(1j * (th - a0)))
        along = np.clip((r - 0.12) / (length - 0.12), 0, 1)
        taper = width * (1 - along) ** 1.4
        inside = smoothstep(taper + 0.02, taper - 0.01, np.abs(da) * r / np.maximum(r, 1e-3)
                            * (1 + 2 * along))
        rays = np.maximum(rays, inside * (r < length) * (0.8 + 0.2 * RNG.random()))
    soot = smoothstep(0.46, 0.22, r) * 0.35
    speck = np.zeros_like(r)
    for _ in range(45):
        a = RNG.random() * 2 * math.pi
        dist0 = 0.24 + RNG.random() * 0.2
        cx, cy = math.cos(a) * dist0, math.sin(a) * dist0
        rr = 0.006 + RNG.random() * 0.014
        dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        speck = np.maximum(speck, smoothstep(rr, rr * 0.4, dist) * (0.5 + 0.4 * RNG.random()))
    alpha = np.clip(np.maximum(np.maximum(blot * 0.96, rays * 0.9), np.maximum(soot, speck)), 0, 1)
    alpha *= smoothstep(0.5, 0.44, r)  # nothing reaches the square's edge
    value = np.clip(0.88 - 0.14 * smoothstep(0.05, 0.22, r)
                    + 0.06 * periodic_noise_2d(x, y, [(9, 9.0, 1.0)], wrap_u=True), 0.55, 1.0)
    return value, alpha


def fire_river():
    w, h = 512, 128
    u, v = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    # The band's half height wobbles along its length (it wraps there): flame edges.
    half = 0.3 + periodic_noise_1d(u, [(2, 0.03), (5, 0.025), (11, 0.018), (23, 0.01), (47, 0.006)])
    jitter = periodic_noise_2d(v, u, [(31, 2.0, 0.02), (67, 5.0, 0.012)])
    d = np.abs(v - 0.5) + jitter
    t = np.clip(d / half, 0, 1.2)  # 0 down the middle, 1 at the edge
    stops = [
        (0.0, (255, 214, 92)),
        (0.45, (255, 160, 44)),
        (0.75, (238, 92, 22)),
        (0.93, (176, 42, 12)),
        (1.0, (120, 24, 8)),
    ]
    rgb = np.zeros((h, w, 3))
    for c in range(3):
        rgb[..., c] = np.interp(t, [p for p, _ in stops], [col[c] / 255 for _, col in stops])
    # Bright streaks running along it (stretched along U, wrapping there).
    streak = periodic_noise_2d(v, u, [(3, 9.0, 1.0), (6, 17.0, 0.6), (1, 29.0, 0.5)])
    hot = np.clip(streak, 0, None) * smoothstep(0.7, 0.2, t)
    rgb = rgb + hot[..., None] * np.array([0.0, 0.16, 0.18])
    alpha = smoothstep(1.04, 0.9, t)
    # Embers beside the band: small bright dots that flow with it.
    for _ in range(26):
        cx = RNG.random()
        side = 1 if RNG.random() < 0.5 else -1
        cy = 0.5 + side * (0.36 + RNG.random() * 0.1)
        r = 0.012 + RNG.random() * 0.016
        dx = np.minimum(np.abs(u - cx), 1 - np.abs(u - cx)) * (w / h)  # wraps along U
        dist = np.sqrt(dx ** 2 + (v - cy) ** 2)
        dot = smoothstep(r, r * 0.35, dist)
        rgb = rgb * (1 - dot[..., None]) + dot[..., None] * np.array([1.0, 0.78, 0.35])
        alpha = np.maximum(alpha, dot * (0.7 + 0.3 * RNG.random()))
    return np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)


def save(name, value, alpha):
    rgb = (np.clip(value, 0, 1) * 255).astype(np.uint8)
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    img = np.dstack([rgb, rgb, rgb, a])
    path = os.path.join(OUT, name)
    Image.fromarray(img).save(path)
    print("wrote", path)


def save_rgb(name, rgb, alpha):
    img = np.dstack([(np.clip(rgb, 0, 1) * 255).astype(np.uint8),
                     (np.clip(alpha, 0, 1) * 255).astype(np.uint8)])
    path = os.path.join(OUT, name)
    Image.fromarray(img).save(path)
    print("wrote", path)


if __name__ == "__main__":
    save("scorch_strip.png", *strip())
    save("scorch_splat.png", *splat())
    # Last, so the scorch images keep their random draws (and their uploaded look).
    rgb, alpha = fire_river()
    save_rgb("fire_river.png", rgb.transpose(1, 0, 2), alpha.T)  # upright: a Beam's length
