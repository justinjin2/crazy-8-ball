"""The streak's pixel fire and impact burst (the ball streak, designer 2026-10-09).

Draws, at the Press Start 2P font's own pixel size (one art pixel = TextSize / 8 on screen,
so the flames share the letters' pixel grid):

- one looping fire flipbook per streak level from x3 to x8 (`fire_x<n>.png`): FRAMES frames
  of FRAME_W x FRAME_H art pixels in a COLS-wide grid, played at 30 fps. The flames rise from
  a band behind the words (the words are real text drawn over them in game). The loop is
  seamless: every noise layer scrolls a whole number of its own periods per loop, and the
  sway and the embers are periodic in the loop's phase.
- `burst.png`: the white impact burst (a ring and rays, BURST_FRAMES frames), tinted in game.

Usage (the GUI venv, see tools/gui/README.md):
    tools/gui/.venv/bin/python tools/gui/streak_fire.py OUT_DIR [--preview]
"""

import argparse
import colorsys
import math
import os

import numpy as np
from PIL import Image

FRAMES = 32  # one loop, 30 fps: about 1.07 s
COLS = 8
FRAME_W = 104  # art pixels: the words' 9.5 glyphs (76 px) and a margin each side
FRAME_H = 48
EMIT_Y = 36  # the flames' base line: one row into the words, so they rise out of the letters
TEXT_TOP, TEXT_BOTTOM = 35, 43  # where the words sit in the frame (the font's 8-px cell)
SEED = 8

# Each level: reach (art px above the base line), the palette from rim to core, the emitter's
# half width, turbulence, and how many embers rise. Levels grow hotter and taller.
LEVELS = {
    3: dict(reach=10, half=36, turb=0.55, embers=0,
            pal=["#5c1200", "#d23a06", "#ff8a1a", "#ffd23f", "#fff6c8"]),
    4: dict(reach=13, half=37, turb=0.6, embers=4,
            pal=["#0b1a66", "#1d4fe0", "#2fa0ff", "#8fe3ff", "#f2fdff"]),
    5: dict(reach=15, half=38, turb=0.65, embers=6,
            pal=["#2a0a5c", "#6a1fd0", "#a35cff", "#dcb6ff", "#fbf3ff"]),
    6: dict(reach=18, half=39, turb=0.7, embers=8,
            pal=["#0a0004", "#3a0010", "#b00020", "#ff3048", "#ffd6dc"]),
    7: dict(reach=21, half=40, turb=0.72, embers=10,
            pal=["#7a4200", "#e09000", "#ffc61a", "#fff09a", "#ffffff"]),
    8: dict(reach=24, half=41, turb=0.78, embers=14, rainbow=True,
            pal=["#3a0a5c", "#ff2d6f", "#ffb020", "#7dfcff", "#ffffff"]),
}
THRESHOLDS = [0.08, 0.3, 0.52, 0.72, 0.88]  # intensity edges of rim, outer, mid, hot, core


def hex_rgb(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


class PeriodicNoise:
    """Value noise on a lattice that wraps in y (and x), smooth-stepped between cells."""

    def __init__(self, rng, cells_x: int, cells_y: int, cell_w: float, cell_h: float):
        self.g = rng.random((cells_y, cells_x))
        self.cx, self.cy = cells_x, cells_y
        self.cw, self.ch = cell_w, cell_h

    @property
    def period_y(self) -> float:
        return self.cy * self.ch

    def sample(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        fx, fy = x / self.cw, y / self.ch
        x0, y0 = np.floor(fx).astype(int), np.floor(fy).astype(int)
        tx, ty = fx - x0, fy - y0
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        x0m, x1m = x0 % self.cx, (x0 + 1) % self.cx
        y0m, y1m = y0 % self.cy, (y0 + 1) % self.cy
        a, b = self.g[y0m, x0m], self.g[y0m, x1m]
        c, d = self.g[y1m, x0m], self.g[y1m, x1m]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fire_frames(level: int) -> list:
    spec = LEVELS[level]
    rng = np.random.default_rng(SEED + level)
    # Two layers: big tongues and fine flicker, each scrolling up a whole number of its
    # periods per loop (1 and 2), so frame FRAMES is frame 0 again.
    big = PeriodicNoise(rng, 20, 4, 5.0, 11.0)
    fine = PeriodicNoise(rng, 35, 8, 3.0, 4.0)
    ys, xs = np.mgrid[0:FRAME_H, 0:FRAME_W].astype(float)
    cx = FRAME_W / 2
    pal = [hex_rgb(c) for c in spec["pal"]]
    embers = [
        (rng.uniform(cx - spec["half"] + 4, cx + spec["half"] - 4), rng.random(), rng.uniform(0.6, 1.0))
        for _ in range(spec["embers"])
    ]
    frames = []
    for f in range(FRAMES):
        p = f / FRAMES
        sway = 1.2 * np.sin(2 * math.pi * (p + ys / 15.0))
        sx = xs + sway
        n = 0.6 * big.sample(sx, ys + p * big.period_y) + 0.4 * fine.sample(
            sx, ys + p * 2 * fine.period_y
        )
        v = np.clip((EMIT_Y - ys) / spec["reach"], -1, 1.6)  # 0 at the base line, 1 at the reach
        edge = np.clip((spec["half"] - np.abs(xs - cx)) / 6.0, 0, 1)  # tapered ends
        # The noise thins out above the reach, so no loose blobs float off the top.
        calm = np.clip(1.0 - np.maximum(v - 0.9, 0) * 1.6, 0.25, 1.0)
        inten = edge * (1.12 - np.abs(v)) + (n - 0.5) * spec["turb"] * 1.4 * calm * np.sqrt(edge)
        inten = np.where(v >= 1.4, 0, inten)
        # Under the base line the flames die within three rows: nothing under the words.
        inten = np.where(ys > EMIT_Y, inten - (ys - EMIT_Y) * 0.8, inten)
        img = np.zeros((FRAME_H, FRAME_W, 4), dtype=np.uint8)
        for i, t in enumerate(THRESHOLDS):
            m = inten >= t
            img[m, :3] = pal[i]
            img[m, 3] = 255
        if spec.get("rainbow"):
            # The rainbow level: the outer three bands take a hue that runs along the flames and
            # turns once per loop; the core stays white.
            hue = (xs / FRAME_W * 0.8 - p + ys / 90.0) % 1.0
            for i, (lo, sat, val) in enumerate([(0, 0.85, 0.55), (1, 0.9, 1.0), (2, 0.55, 1.0)]):
                band = (inten >= THRESHOLDS[lo]) & (
                    inten < (THRESHOLDS[lo + 1] if lo + 1 < len(THRESHOLDS) else 9)
                )
                rgb = np.array([colorsys.hsv_to_rgb(hh, sat, val) for hh in hue[band]]) * 255
                if len(rgb):
                    img[band, :3] = rgb.astype(np.uint8)
        # Embers: single pixels rising from the flames, periodic in the loop.
        for ex, phase, speed in embers:
            q = (p * (1 if speed > 0.8 else 2) + phase) % 1.0
            ey = int(EMIT_Y - spec["reach"] * 0.4 - q * (spec["reach"] * 1.1))
            exx = int(round(ex + 2.0 * math.sin(2 * math.pi * (q + phase))))
            if 0 <= ey < FRAME_H and 0 <= exx < FRAME_W and q < 0.9:
                img[ey, exx, :3] = pal[3] if q < 0.5 else pal[2]
                img[ey, exx, 3] = 255
        frames.append(img)
    return frames


def sheet(frames: list, cols: int) -> Image.Image:
    h, w = frames[0].shape[:2]
    rows = math.ceil(len(frames) / cols)
    out = np.zeros((rows * h, cols * w, 4), dtype=np.uint8)
    for i, fr in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * h : (r + 1) * h, c * w : (c + 1) * w] = fr
    return Image.fromarray(out, "RGBA")


BURST_FRAMES = 8
BURST_W, BURST_H = 128, 48


def burst_frames() -> list:
    """A white pixel burst for the step-up: an ellipse ring racing out and rays that shoot
    out and thin, wider than tall to sit round the words."""
    frames = []
    ys, xs = np.mgrid[0:BURST_H, 0:BURST_W].astype(float)
    cx, cy = (BURST_W - 1) / 2, (BURST_H - 1) / 2
    ex, ey = (xs - cx) / (BURST_W / 2), (ys - cy) / (BURST_H / 2)
    r = np.sqrt(ex * ex + ey * ey)
    ang = np.arctan2(ey, ex)
    for f in range(BURST_FRAMES):
        p = (f + 1) / BURST_FRAMES
        img = np.zeros((BURST_H, BURST_W, 4), dtype=np.uint8)
        ring_r = 0.35 + 0.62 * (1 - (1 - p) ** 2)
        width = 0.09 * (1 - p) + 0.02
        ring = np.abs(r - ring_r) < width
        rays = (np.cos(ang * 14) > 0.93 - 0.05 * p) & (r > 0.25 + 0.6 * p) & (r < 0.55 + 0.5 * p)
        m = ring | rays
        if p > 0.75:  # the ring breaks up into dots at the end
            m &= ((xs + ys + f) % 3) < 1.5
        img[m] = (255, 255, 255, 255)
        frames.append(img)
    return frames


FONT = "/Applications/RobloxStudio.app/Contents/Resources/content/fonts/PressStart2P-Regular.ttf"
TEXT_COLOURS = {3: "#ff8a1f", 4: "#4fb6ff", 5: "#b67cff", 6: "#ff3346", 7: "#fff0a0", 8: "#ffffff"}


def preview(frames: list, level: int, frame: int = 0, scale: int = 4) -> Image.Image:
    """One frame on the table's blue with the words drawn over it at the font's pixel size
    (a one-pixel square ink outline), upscaled with no smoothing."""
    from PIL import ImageDraw, ImageFont

    base = Image.new("RGBA", (FRAME_W, FRAME_H), (64, 200, 245, 255))
    base.alpha_composite(Image.fromarray(frames[frame], "RGBA"))
    big = base.resize((FRAME_W * scale, FRAME_H * scale), Image.NEAREST)
    words = f"STREAK x{level}"
    size = 64
    font = ImageFont.truetype(FONT, size)
    size = int(size * (FRAME_W - 26) * scale / font.getlength(words))  # the words span the flames
    font = ImageFont.truetype(FONT, size)
    width = font.getlength(words)
    x0, y0 = (big.width - width) / 2, TEXT_TOP * scale
    ink = Image.new("RGBA", big.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ink)
    o = max(2, scale)
    for dx in (-o, 0, o):
        for dy in (-o, 0, o):
            d.text((x0 + dx, y0 + dy), words, font=font, fill=(27, 32, 51, 255))
    d.text((x0 + o, y0 + 2 * o), words, font=font, fill=(27, 32, 51, 255))
    d.text((x0, y0), words, font=font, fill=hex_rgb(TEXT_COLOURS[level]) + (255,))
    big.alpha_composite(ink)
    return big


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--preview", action="store_true")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    previews = []
    for level in LEVELS:
        frames = fire_frames(level)
        sheet(frames, COLS).save(os.path.join(a.out, f"fire_x{level}.png"))
        if a.preview:
            previews.append(preview(frames, level))
    sheet(burst_frames(), BURST_FRAMES).save(os.path.join(a.out, "burst.png"))
    if a.preview:
        w, h = previews[0].size
        board = Image.new("RGBA", (w * 2, h * 3), (0, 0, 0, 255))
        for i, im in enumerate(previews):
            board.paste(im, ((i % 2) * w, (i // 2) * h))
        board.save(os.path.join(a.out, "preview.png"))


if __name__ == "__main__":
    main()
