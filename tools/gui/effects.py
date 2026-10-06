"""The lively GUI's effect flipbooks, drawn from code with a fixed seed (no image API).

A flipbook is one 1024 x 1024 sheet of 8 x 8 frames, 128 px each, played on one ImageLabel by
stepping ImageRectOffset (docs/STUDIO_NOTES.md, smooth slow GUI motion). Sparks are drawn at
2x with light adding up, given a soft glow, shrunk, then "unscreened" (brightness becomes alpha)
so a sheet sits on any background. Colours are baked (a white-hot core cools into the colour),
because ImageColor3 can only darken white, never make it.

Each sheet gets a <name>.json beside it: columns, rows, frame size, frame count, fps, loop.

  firework_<colour>.png  a burst: a flash, sparks flying out with trails, gravity, fading tips
  sparkle.png            a four-point twinkle that grows, holds and shrinks (white, tintable)

  tools/gui/.venv/bin/python tools/gui/effects.py [--out assets/ui/effects] [--preview DIR]
"""

import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SEED = 8
GRID, FRAME = 8, 128  # 8 x 8 frames of 128 px: one 1024 sheet
FPS = {"firework": 30, "sparkle": 30}  # playback rate the frames were timed for
LOOP = {"firework": False, "sparkle": True}  # a burst plays once; a twinkle repeats
SCALE = 2  # drawn at 2x, then shrunk
COLOURS = {  # 13b's firework colours
    "gold": (255, 196, 70),
    "pink": (255, 80, 200),
    "cyan": (70, 215, 255),
    "purple": (165, 95, 255),
    "orange": (255, 125, 35),
}


def _unscreen(acc):
    """Light added on black -> straight-alpha RGBA (alpha = brightest channel)."""
    m = acc.max(-1, keepdims=True)
    alpha = np.clip(m, 0, 1)
    rgb = np.clip(acc / np.maximum(m, 1e-4), 0, 1)
    return np.concatenate([rgb, alpha], -1)


def _to_frame(acc, glow=6):
    """A 2x float canvas -> one 128 px RGBA frame with a soft glow under the sparks."""
    img = Image.fromarray((np.clip(acc, 0, 1) * 255).astype("uint8"), "RGB")
    halo = np.asarray(img.filter(ImageFilter.GaussianBlur(glow))).astype(float) / 255
    lit = np.clip(acc + halo * 0.9, 0, 1.5)
    rgba = _unscreen(np.minimum(lit, 1))
    out = Image.fromarray((rgba * 255).round().astype("uint8"), "RGBA")
    return out.resize((FRAME, FRAME), Image.LANCZOS)


def _sheet(frames):
    sheet = Image.new("RGBA", (GRID * FRAME, GRID * FRAME), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % GRID) * FRAME, (i // GRID) * FRAME))
    return sheet


def firework(colour):
    """64 frames: a white flash, ~38 sparks out with drag and gravity, trails, then fading."""
    rng = random.Random(SEED)
    tint = np.array(colour, float) / 255
    S = FRAME * SCALE
    c = S / 2
    sparks = []
    for k in range(72):
        ang = k / 72 * math.tau + rng.uniform(-0.1, 0.1)
        # mixed speeds fill the disc (an even ring reads as a wreath, not a burst)
        speed = rng.choice((rng.uniform(0.9, 1.0), rng.uniform(0.55, 0.9), rng.uniform(0.3, 0.6)))
        sparks.append((ang, speed, rng.uniform(0.8, 1.2)))
    n = GRID * GRID
    frames = []

    def pos(ang, speed, t):
        # out fast, slowing (drag), then a little fall
        reach = S * 0.43 * speed * (1 - math.exp(-4.2 * t)) / (1 - math.exp(-4.2))
        return c + math.cos(ang) * reach, c + math.sin(ang) * reach + S * 0.06 * t * t

    for i in range(n):
        t = i / (n - 1)
        layer = Image.new("RGB", (S, S), (0, 0, 0))
        d = ImageDraw.Draw(layer)
        life = min(1.0, 1.25 * max(0.0, 1 - t) ** 0.6)
        heat = max(0.0, 1 - t / 0.18) ** 2  # white early, the colour soon after
        col = tint * (1 - heat) + np.ones(3) * heat
        for ang, speed, size in sparks:
            # the trail: a few points back in time, dimmer and thinner
            pts = [pos(ang, speed, max(0.0, t - back * 0.05)) for back in range(7)]
            for j in range(6):
                a = life * (1 - j / 6)
                rgb = tuple(int(255 * min(1, v * a)) for v in col)
                d.line([pts[j], pts[j + 1]], fill=rgb, width=max(1, int(4 * size * (1 - j / 7))))
            x, y = pts[0]
            r = 3.2 * size * (0.6 + 0.4 * life)
            twinkle = 0.75 + 0.25 * math.sin(i * 1.7 + ang * 5)
            tip = tuple(int(255 * min(1, (v * 0.8 + 0.35) * life * twinkle)) for v in col)
            d.ellipse([x - r, y - r, x + r, y + r], fill=tip)
        acc = np.asarray(layer).astype(float) / 255
        if t < 0.12:  # the opening flash
            yy, xx = np.mgrid[0:S, 0:S].astype(float)
            fl = np.exp(-(((xx - c) ** 2 + (yy - c) ** 2) / (2 * (S * (0.05 + 0.25 * t)) ** 2)))
            acc = acc + fl[..., None] * (1 - t / 0.12) * 1.2
        frames.append(_to_frame(acc))
    return _sheet(frames)


def sparkle():
    """64 frames of a four-point twinkle: grows, holds with a slow turn, shrinks. White."""
    S = FRAME * SCALE
    c = S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(float) - c
    n = GRID * GRID
    frames = []
    for i in range(n):
        t = i / (n - 1)
        amount = math.sin(math.pi * t) ** 0.7
        turn = t * math.pi / 4
        x = xx * math.cos(turn) + yy * math.sin(turn)
        y = -xx * math.sin(turn) + yy * math.cos(turn)
        length = S * 0.45 * amount + 1e-3
        ray = np.exp(-np.abs(y) / (S * 0.012)) * np.clip(1 - np.abs(x) / length, 0, 1) ** 2
        ray += np.exp(-np.abs(x) / (S * 0.012)) * np.clip(1 - np.abs(y) / length, 0, 1) ** 2
        core = np.exp(-(xx**2 + yy**2) / (2 * (S * 0.05 * amount + 1e-3) ** 2))
        v = np.clip(ray + core, 0, 1) * amount
        frames.append(_to_frame(np.repeat(v[..., None], 3, -1), glow=4))
    return _sheet(frames)


def preview(sheet, out, frames=(2, 8, 16, 26, 38, 52)):
    """Some frames on navy, side by side, for a gate sheet."""
    img = Image.new("RGBA", (len(frames) * FRAME, FRAME), (12, 20, 64, 255))
    for k, f in enumerate(frames):
        fr = sheet.crop(((f % GRID) * FRAME, (f // GRID) * FRAME, (f % GRID + 1) * FRAME, (f // GRID + 1) * FRAME))
        img.alpha_composite(fr, (k * FRAME, 0))
    img.convert("RGB").save(out, quality=90)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "assets/ui/effects"))
    ap.add_argument("--preview")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    sheets = {f"firework_{name}": firework(rgb) for name, rgb in COLOURS.items()}
    sheets["sparkle"] = sparkle()
    for name, sheet in sheets.items():
        sheet.save(out / f"{name}.png", optimize=True)
        kind = name.split("_")[0]
        (out / f"{name}.json").write_text(json.dumps({
            "image": f"{name}.png", "columns": GRID, "rows": GRID, "frame_width": FRAME,
            "frame_height": FRAME, "frame_count": GRID * GRID, "fps": FPS[kind], "loop": LOOP[kind],
            "order": "left to right, then top to bottom",
        }, indent=2) + "\n")
        print(name, sheet.size)
        if a.preview:
            Path(a.preview).mkdir(parents=True, exist_ok=True)
            preview(sheet, Path(a.preview) / f"{name}.jpg")


if __name__ == "__main__":
    main()
