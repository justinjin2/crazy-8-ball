#!/usr/bin/env python3
"""The power bar's ability skins (Config.UI.PowerSkins): the images a Legendary or Mythic
ability dresses the bar in while it is armed (the designer, 2026-09-30).

    python3 tools/gen_power_skins.py

Writes assets/abilities/powerskins/:
  FlashBolts.png    Black Flash: a 4 x 4 flipbook (128 x 256 frames) of black lightning with a
                    red glow, bolts running down the bar, on transparent
  SteelBall.png     Steel Ball: a steel ball with spiral grooves (256, transparent)
  SpaceTile.png     Black Hole: deep space, a purple and blue nebula with stars, tiling in
                    both directions (256)
  BlackHole.png     Black Hole: a black hole seen from above, a glowing accretion swirl round
                    it (256, transparent), turned in the UI
  TigerSkin.png     Guangdong Tiger: orange fur with black stripes, tiling in both directions
                    (256)

Seeded, so a rerun draws the same images. Only numpy and Pillow.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "abilities", "powerskins")


def hexrgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255


def ramp(t, stops):
    """Colour ramp: t (array 0..1) through [(pos, hex), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    pos = [p for p, _ in stops]
    cols = [hexrgb(c) for _, c in stops]
    for c in range(3):
        out[..., c] = np.interp(t, pos, [col[c] for col in cols])
    return out


def periodic_noise(size, octaves, rng, base=2):
    """Noise that tiles: a sum of random sines with whole-number frequencies over the tile."""
    h, w = size
    y, x = np.mgrid[0:h, 0:w]
    u, v = x / w, y / h
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        f = base * (2 ** o)
        for _ in range(6):
            fx, fy = rng.integers(-f, f + 1), rng.integers(-f, f + 1)
            if fx == 0 and fy == 0:
                continue
            phase = rng.uniform(0, 2 * math.pi)
            total += amp * np.sin(2 * math.pi * (fx * u + fy * v) + phase)
            norm += amp
        amp *= 0.55
    return 0.5 + 0.5 * total / max(norm, 1e-6) * 2.2


def save(arr_rgba, name):
    img = Image.fromarray((np.clip(arr_rgba, 0, 1) * 255).astype(np.uint8))
    path = os.path.join(OUT, name)
    img.save(path)
    print("wrote", path)


# ------------------------------------------------------------------------------------------
# Black Flash: black lightning with a red glow
# ------------------------------------------------------------------------------------------

def bolt_path(rng, x0, y0, x1, y1, rough, depth):
    """Midpoint displacement from (x0, y0) to (x1, y1)."""
    pts = [(x0, y0), (x1, y1)]
    for _ in range(depth):
        nxt = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            mx, my = (ax + bx) / 2, (ay + by) / 2
            length = math.hypot(bx - ax, by - ay)
            nx, ny = -(by - ay) / (length or 1), (bx - ax) / (length or 1)
            d = rng.normal(0, rough * length)
            nxt += [(mx + nx * d, my + ny * d), (bx, by)]
        pts = nxt
    return pts


def flash_bolts():
    rng = np.random.default_rng(11)
    fw, fh, cols, rows = 128, 256, 4, 4
    sheet = Image.new("RGBA", (fw * cols, fh * rows), (0, 0, 0, 0))
    for i in range(cols * rows):
        glow = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        core = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        gd, cd = ImageDraw.Draw(glow), ImageDraw.Draw(core)
        for b in range(2):
            x0 = rng.uniform(0.25, 0.75) * fw
            x1 = rng.uniform(0.2, 0.8) * fw
            main = bolt_path(rng, x0, -8, x1, fh + 8, 0.16, 5)
            branches = []
            for _ in range(3):
                k = rng.integers(4, len(main) - 4)
                sx, sy = main[k]
                ex = sx + rng.uniform(-0.45, 0.45) * fw
                ey = sy + rng.uniform(0.15, 0.35) * fh
                branches.append(bolt_path(rng, sx, sy, ex, ey, 0.2, 3))
            for path, width in [(main, 1.0)] + [(p, 0.55) for p in branches]:
                gd.line(path, fill=(255, 20, 30, 255), width=int(20 * width), joint="curve")
                cd.line(path, fill=(255, 70, 70, 255), width=max(3, int(9 * width)), joint="curve")
                cd.line(path, fill=(6, 0, 0, 255), width=max(2, int(5 * width)), joint="curve")
        glow = glow.filter(ImageFilter.GaussianBlur(6))
        # The blur thins the glow's alpha: lift it back so the red reads on the dark bar.
        r_, g_, b_, a_ = glow.split()
        a_ = a_.point(lambda q: min(255, int(q * 1.8)))
        glow = Image.merge("RGBA", (r_, g_, b_, a_))
        frame = Image.alpha_composite(glow, core)
        sheet.paste(frame, ((i % cols) * fw, (i // cols) * fh), frame)
    path = os.path.join(OUT, "FlashBolts.png")
    sheet.save(path)
    print("wrote", path)


# ------------------------------------------------------------------------------------------
# Steel Ball: a steel ball with spiral grooves
# ------------------------------------------------------------------------------------------

def steel_ball():
    n = 256
    y, x = np.mgrid[0:n, 0:n]
    u = (x + 0.5) / n * 2 - 1
    v = 1 - (y + 0.5) / n * 2
    r = 0.9
    d2 = (u * u + v * v) / (r * r)
    inside = d2 <= 1
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    nx, ny = u / r, v / r
    # Light from the upper left, a studio's soft top light and a rim.
    lx, ly, lz = -0.5, 0.6, 0.62
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    diffuse = np.clip((nx * lx + ny * ly + nz * lz) / ln, 0, 1)
    hx, hy, hz = lx / ln, ly / ln, lz / ln + 1
    hn = math.sqrt(hx * hx + hy * hy + hz * hz)
    spec = np.clip((nx * hx + ny * hy + nz * hz) / hn, 0, 1) ** 60
    # A brushed-steel sky reflection: bright band above the horizon, dark below.
    sky = ramp(0.5 + 0.5 * ny, [(0, "3A4048"), (0.45, "6E7782"), (0.55, "C9D1DA"), (1, "F2F5F8")])
    base = sky * (0.55 + 0.45 * diffuse[..., None])
    # Spiral grooves: bands of the ball's own longitude twisted with its latitude.
    ax, ay, az = nx, ny * math.cos(0.5) - nz * math.sin(0.5), ny * math.sin(0.5) + nz * math.cos(0.5)
    lon = np.arctan2(ay, ax)
    lat = np.arcsin(np.clip(az, -1, 1))
    g = np.abs(np.sin(3 * lon + 3.2 * lat))
    groove = np.clip(1 - g / 0.09, 0, 1)
    lip = np.clip(1 - np.abs(np.sin(3 * lon + 3.2 * lat + 0.12)) / 0.07, 0, 1)
    col = base * (1 - 0.65 * groove[..., None]) + 0.35 * lip[..., None]
    col = col + spec[..., None] * 1.2
    edge = np.clip((np.sqrt(d2) - 0.93) / 0.07, 0, 1)
    col = col * (1 - 0.55 * edge[..., None])
    out = np.zeros((n, n, 4))
    out[..., :3] = col
    # An ink outline just outside the ball, the kit's look.
    ring = (np.sqrt(u * u + v * v) > r) & (np.sqrt(u * u + v * v) <= r + 0.05)
    out[..., 3] = np.where(inside, 1.0, 0.0)
    out[ring, :3] = hexrgb("1B2033")
    out[ring, 3] = 1.0
    save(out, "SteelBall.png")


# ------------------------------------------------------------------------------------------
# Black Hole: deep space, and the hole itself
# ------------------------------------------------------------------------------------------

def space_tile():
    rng = np.random.default_rng(5)
    n = 256
    a = periodic_noise((n, n), 4, rng)
    b = periodic_noise((n, n), 4, rng)
    neb = ramp(a, [(0, "04020C"), (0.45, "12082A"), (0.62, "3A1466"), (0.78, "7A2FC4"),
                   (1, "C07BFF")])
    blue = ramp(b, [(0, "000000"), (0.6, "000000"), (0.8, "1C3C9A"), (1, "4A86FF")])
    col = neb * 0.85 + blue * 0.55
    # Stars, wrapping round the tile's edges so it tiles.
    y, x = np.mgrid[0:n, 0:n]
    for _ in range(90):
        sx, sy = rng.uniform(0, n), rng.uniform(0, n)
        size = rng.choice([0.6, 0.8, 1.1, 1.8], p=[0.5, 0.3, 0.15, 0.05])
        bright = rng.uniform(0.6, 1.0)
        dx = (x - sx + n / 2) % n - n / 2
        dy = (y - sy + n / 2) % n - n / 2
        star = np.exp(-(dx * dx + dy * dy) / (2 * size * size)) * bright
        tint = hexrgb(rng.choice(["FFFFFF", "D6E4FF", "FFE9D6", "F0D6FF"]))
        col = col + star[..., None] * tint
    out = np.ones((n, n, 4))
    out[..., :3] = col
    save(out, "SpaceTile.png")


def black_hole():
    n = 256
    y, x = np.mgrid[0:n, 0:n]
    u = (x + 0.5) / n * 2 - 1
    v = 1 - (y + 0.5) / n * 2
    r = np.sqrt(u * u + v * v)
    th = np.arctan2(v, u)
    hole = 0.26
    # The accretion swirl: spiral arms, hot near the hole, cooling to purple and blue.
    arms = 0.55 + 0.45 * np.sin(3 * (th + 3.2 * np.log(np.maximum(r, 1e-3))))
    band = np.exp(-((r - 0.46) / 0.2) ** 2)
    heat = np.clip(1 - (r - hole) / 0.62, 0, 1)
    col = ramp(heat, [(0, "1B2A8C"), (0.35, "6A2BD9"), (0.6, "D23CE0"), (0.82, "FF9A5A"),
                      (1, "FFF1D6")])
    glow = band * arms
    photon = np.exp(-((r - hole - 0.015) / 0.018) ** 2)
    alpha = np.clip(glow * 1.3 + photon, 0, 1) * np.clip((0.98 - r) / 0.12, 0, 1)
    col = col * np.clip(glow * 1.2 + photon * 1.5, 0, 1.6)[..., None]
    out = np.zeros((n, n, 4))
    out[..., :3] = col
    out[..., 3] = alpha
    centre = r < hole
    out[centre, :3] = 0
    out[centre, 3] = 1
    save(out, "BlackHole.png")


# ------------------------------------------------------------------------------------------
# Guangdong Tiger: tiger skin
# ------------------------------------------------------------------------------------------

def tiger_skin():
    rng = np.random.default_rng(3)
    n = 256
    y, x = np.mgrid[0:n, 0:n]
    u, v = x / n, y / n
    fur = periodic_noise((n, n), 5, rng, base=3)
    base = ramp(0.35 + 0.5 * fur, [(0, "C9620E"), (0.5, "E8841E"), (1, "F7B452")])
    wob = periodic_noise((n, n), 3, rng, base=2) - 0.5
    width = periodic_noise((n, n), 3, rng, base=2)
    # Stripes run across the bar at a slant, wavy, breaking apart and running out to points
    # where the width noise is low (a tiger's broken, forked stripes, not even bands).
    stripes = 5
    phase = (v * stripes + u + 0.18 * np.sin(2 * math.pi * (3 * u + 0.1)) + 0.5 * wob)
    s = np.abs(((phase % 1) - 0.5) * 2)  # 0 at a stripe's middle line, 1 between stripes
    thick = 0.42 * np.clip((width - 0.32) / 0.45, 0, 1) ** 0.8
    ink = np.clip((thick - s) / 0.04, 0, 1)
    # A soft dark edge round each stripe, none where a stripe has run out (no hairline).
    edge = (np.clip((thick + 0.06 - s) / 0.06, 0, 1) - ink) * np.clip(thick / 0.08, 0, 1)
    col = base * (1 - 0.35 * edge[..., None])
    col = col * (1 - ink[..., None]) + hexrgb("140B06") * ink[..., None]
    out = np.ones((n, n, 4))
    out[..., :3] = col
    save(out, "TigerSkin.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    flash_bolts()
    steel_ball()
    space_tile()
    black_hole()
    tiger_skin()
