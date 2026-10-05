#!/usr/bin/env python3
"""Generate the pull cutscenes' effect textures (Config.Cutscenes.Art; designer, 2026-10-05).

White art on transparency, tinted in Roblox (Beam.Color, ParticleEmitter.Color,
ImageLabel.ImageColor3), drawn with numpy and Pillow from a fixed seed so a rerun gives the same
pixels. A Beam's texture runs along the beam on the image's X axis and across its width on Y,
so the beam textures tile in X (TextureMode Wrap).

Outputs (assets/cutscenes/):
  beam_energy.png    512 x 128  bright streaks running along the beam inside a soft core
  beam_soft.png      64 x 128   a plain soft falloff across the width (the beam's wide glow)
  aurora_curtain.png 512 x 256  aurora curtain: fine vertical rays, a bright lower band
                                fading up into nothing, tileable along the curtain
  light_streak.png   64 x 512   one soft light streak (shooting lights, the warp's stars)

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


def main():
    os.makedirs(OUT, exist_ok=True)
    beam_energy()
    beam_soft()
    aurora_curtain()
    light_streak()


if __name__ == "__main__":
    main()
