#!/usr/bin/env python3
"""Write assets/balls/tex_0.png .. tex_15.png: one equirectangular (2:1) texture per ball for
the sphere mesh from tools/gen_ball_mesh.py. Needs Pillow and numpy.

Layout on the sphere: the number discs sit on the equator at longitude -90 and +90
(u = 0.25 and 0.75, where an equirectangular map is least distorted); the stripe is the band
within STRIPE_HALF_DEG of the great circle that lies halfway between the two discs.
Upload the images and paste the ids into Config.Balls.Textures.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1024, 512
SS = 2  # supersampling for crisp edges
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "balls")

DISC_DEG = 23  # angular radius of the number disc
STRIPE_HALF_DEG = 31  # half-width of the stripe band
WHITE = (250, 247, 240)
INK = (24, 22, 22)
COLORS = {
    0: (245, 240, 225),
    1: (250, 200, 40),
    2: (30, 80, 200),
    3: (210, 40, 40),
    4: (100, 40, 150),
    5: (245, 120, 30),
    6: (20, 130, 70),
    7: (120, 30, 30),
    8: (20, 20, 22),
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    print("warning: no bold system font found, using Pillow default", file=sys.stderr)
    return ImageFont.load_default()


def direction_grid(w, h):
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    lon = (u - 0.5) * 2 * math.pi
    lat = (0.5 - v) * math.pi
    lon, lat = np.meshgrid(lon, lat)
    c = np.cos(lat)
    return c * np.cos(lon), np.sin(lat), c * np.sin(lon)


def ball_texture(n):
    w, h = W * SS, H * SS
    x, y, z = direction_grid(w, h)
    base = COLORS[n] if n <= 8 else COLORS[n - 8]
    img = np.zeros((h, w, 3), dtype=np.float32)
    if 1 <= n <= 8:
        img[:] = base
    else:
        img[:] = WHITE
        if n >= 9:
            band = np.abs(z) < math.sin(math.radians(STRIPE_HALF_DEG))
            img[band] = base
    disc = np.abs(z) > math.cos(math.radians(DISC_DEG))
    if n >= 1:
        img[disc] = WHITE
    pil = Image.fromarray(img.astype(np.uint8))
    draw = ImageDraw.Draw(pil)
    if n >= 1:
        # Number at each disc centre (u = 0.25 and 0.75). A degree of arc is w / 360 px here.
        px_per_deg = w / 360
        font = load_font(int(DISC_DEG * px_per_deg * (1.25 if n < 10 else 1.05)))
        text = str(n)
        bbox = draw.textbbox((0, 0), text, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        for cx in (w * 0.25, w * 0.75):
            draw.text((cx - tw / 2 - bbox[0], h / 2 - th / 2 - bbox[1]), text, font=font, fill=INK)
    else:
        # Cue ball: a small red dot at one disc spot (spin reads better later).
        r = 4 * px_per_deg_default(w)
        cx, cy = w * 0.25, h / 2
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(200, 30, 30))
    pil = pil.resize((W, H), Image.LANCZOS)
    return pil


def px_per_deg_default(w):
    return w / 360


def main():
    os.makedirs(OUT, exist_ok=True)
    for n in range(16):
        ball_texture(n).save(os.path.join(OUT, f"tex_{n}.png"))
    print(f"wrote 16 textures to {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()
