"""Draw the Grand Opening card's drawn pieces (lively GUI pipeline, no image API).

Everything here is drawn from code with a fixed seed, so a rerun gives the same pixels:
  bokeh_disc.png      a soft white disc (tinted in game) for the drifting bokeh
  block_glow.png      a soft white radial glow (tinted gold in game) behind the block
  beta_bg.png         the Beta card's background: navy with a faint blueprint grid
  beta_panel_1..5.png blueprint panels in cyan line work (circles, a cue section, a grid with a
                      curve, dimension lines, a reticle), transparent, drawn at 2x then shrunk
  beta_code.png       a strip of made-up glyphs (never English), cyan, transparent
  go_bg.png           the Grand Opening card's background: navy with soft bokeh, no fireworks
  *_mask.png          a white silhouette of a picture (its alpha), for shine sweeps:
                      `--mask IN.png OUT.png` makes one from any piece
The block's rays reuse assets/ui/lucky-rays.png (white, tinted in game).

  tools/gui/.venv/bin/python tools/gui/draw_pieces.py [--out assets/ui/grand_opening]
  tools/gui/.venv/bin/python tools/gui/draw_pieces.py --mask IN.png OUT.png
"""

import argparse
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SEED = 8  # every random choice comes from this
CYAN = (90, 220, 255)
NAVY_TOP, NAVY_BOTTOM = (16, 30, 92), (6, 12, 44)


def soft_disc(size=128):
    """A white disc with a soft rim: bright flat middle, falling off over the outer third."""
    y, x = np.mgrid[0:size, 0:size].astype(float)
    r = np.hypot(x - (size - 1) / 2, y - (size - 1) / 2) / (size / 2)
    a = np.clip((1 - r) / 0.35, 0, 1) ** 1.5
    return Image.fromarray(np.dstack([np.full_like(a, 255), np.full_like(a, 255), np.full_like(a, 255), a * 255]).astype("uint8"), "RGBA")


def glow(size=256):
    """A white glow fading from the middle to nothing at the edge (gaussian-like)."""
    y, x = np.mgrid[0:size, 0:size].astype(float)
    r = np.hypot(x - (size - 1) / 2, y - (size - 1) / 2) / (size / 2)
    a = np.exp(-((r / 0.62) ** 2) * 1.2) * np.clip(1 - r, 0, 1) ** 0.6
    return Image.fromarray(np.dstack([np.full_like(a, 255)] * 3 + [a * 255]).astype("uint8"), "RGBA")


def gradient(w, h, top, bottom):
    t = np.linspace(0, 1, h)[:, None, None]
    rows = np.array(top) * (1 - t) + np.array(bottom) * t
    return np.repeat(rows, w, axis=1)


def vignette(rgb, strength=0.45):
    h, w = rgb.shape[:2]
    y, x = np.mgrid[0:h, 0:w].astype(float)
    r = np.hypot((x - w / 2) / (w / 2), (y - h / 2) / (h / 2)) / math.sqrt(2)
    return rgb * (1 - strength * r[..., None] ** 2)


def beta_bg(w=1024, h=512):
    """Navy, brighter in the middle, a faint cyan blueprint grid (major every 4th line)."""
    rgb = vignette(gradient(w, h, NAVY_TOP, NAVY_BOTTOM))
    img = Image.fromarray(rgb.clip(0, 255).astype("uint8"), "RGB").convert("RGBA")
    lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lines)
    step = 32
    for i in range(0, max(w, h) + 1, step):
        major = (i // step) % 4 == 0
        a = 60 if major else 26
        d.line([(i, 0), (i, h)], fill=CYAN + (a,), width=1)
        d.line([(0, i), (w, i)], fill=CYAN + (a,), width=1)
    img.alpha_composite(lines)
    return img.convert("RGB")


def go_bg(w=1024, h=512):
    """Navy with soft bokeh in blue, cyan and a little purple and gold, no fireworks."""
    rng = random.Random(SEED)
    rgb = vignette(gradient(w, h, (20, 34, 104), NAVY_BOTTOM))
    img = Image.fromarray(rgb.clip(0, 255).astype("uint8"), "RGB").convert("RGBA")
    tints = [(70, 120, 255), (60, 200, 255), (150, 90, 255), (255, 190, 80)]
    for blur, count, (lo, hi), alpha in ((12, 9, (40, 80), 34), (4, 16, (12, 30), 52), (1.5, 22, (4, 9), 90)):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        for _ in range(count):
            r = rng.uniform(lo, hi)
            x, y = rng.uniform(0, w), rng.uniform(0, h)
            tint = tints[0 if rng.random() < 0.45 else 1 if rng.random() < 0.6 else 2 if rng.random() < 0.8 else 3]
            d.ellipse([x - r, y - r, x + r, y + r], fill=tint + (alpha,), outline=tint + (min(255, alpha + 50),), width=2)
        img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))
    return img.convert("RGB")


def _line_canvas(size):
    return Image.new("RGBA", size, (0, 0, 0, 0))


def _finish(img, glow_px=3):
    """Shrink the 2x drawing and add a soft cyan glow under the lines."""
    halo = img.filter(ImageFilter.GaussianBlur(glow_px * 2))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(halo)
    out.alpha_composite(img)
    return out.resize((img.width // 2, img.height // 2), Image.LANCZOS)


def panel_circles(s=512):
    """Concentric circles with tick marks and a cross: a gauge."""
    img = _line_canvas((s, s))
    d = ImageDraw.Draw(img)
    c = s / 2
    for r, w, a in ((0.46, 4, 230), (0.38, 2, 160), (0.24, 3, 210), (0.1, 2, 160)):
        d.ellipse([c - s * r, c - s * r, c + s * r, c + s * r], outline=CYAN + (a,), width=w)
    for k in range(60):
        ang = k * math.tau / 60
        inner = 0.40 if k % 5 else 0.36
        d.line([(c + math.cos(ang) * s * inner, c + math.sin(ang) * s * inner),
                (c + math.cos(ang) * s * 0.44, c + math.sin(ang) * s * 0.44)], fill=CYAN + (200,), width=2)
    d.line([(c, s * 0.02), (c, s * 0.98)], fill=CYAN + (110,), width=2)
    d.line([(s * 0.02, c), (s * 0.98, c)], fill=CYAN + (110,), width=2)
    d.arc([c - s * 0.31, c - s * 0.31, c + s * 0.31, c + s * 0.31], 200, 320, fill=CYAN + (255,), width=6)
    return _finish(img)


def panel_section(s=(640, 384)):
    """A cue's cross-section and side view: a taper with rings and a circle cut."""
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    d.rectangle([4, 4, w - 5, h - 5], outline=CYAN + (120,), width=2)
    # the side view: a long taper
    d.polygon([(40, h * 0.42), (w * 0.62, h * 0.36), (w * 0.62, h * 0.64), (40, h * 0.58)], outline=CYAN + (230,), width=3)
    for x in (0.18, 0.34, 0.5):
        d.line([(w * x, h * 0.37), (w * x, h * 0.63)], fill=CYAN + (170,), width=2)
    # the section: a circle with an inner core and hatching
    cx, cy, r = w * 0.81, h * 0.5, h * 0.3
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=CYAN + (240,), width=3)
    d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45], outline=CYAN + (200,), width=2)
    for k in range(-6, 7):
        off = k * r / 6
        half = math.sqrt(max(0, r * r - off * off))
        d.line([(cx + off - half * 0.7, cy - half * 0.7), (cx + off + half * 0.7, cy + half * 0.7)], fill=CYAN + (60,), width=1)
    d.line([(w * 0.62, h * 0.36), (cx, cy - r)], fill=CYAN + (110,), width=2)
    d.line([(w * 0.62, h * 0.64), (cx, cy + r)], fill=CYAN + (110,), width=2)
    return _finish(img)


def panel_curve(s=(512, 384)):
    """A small grid with a rising curve and its points."""
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    for i in range(0, w, 32):
        d.line([(i, 0), (i, h)], fill=CYAN + (55,), width=1)
    for i in range(0, h, 32):
        d.line([(0, i), (w, i)], fill=CYAN + (55,), width=1)
    d.rectangle([2, 2, w - 3, h - 3], outline=CYAN + (180,), width=3)
    pts = [(x, h * 0.85 - (h * 0.7) * (1 - math.cos(x / w * math.pi)) / 2) for x in range(16, w - 15, 8)]
    d.line(pts, fill=CYAN + (255,), width=5, joint="curve")
    for x, y in pts[::8]:
        d.ellipse([x - 7, y - 7, x + 7, y + 7], outline=CYAN + (255,), width=3)
    return _finish(img)


def panel_dimensions(s=(576, 320)):
    """A rectangle with dimension lines and arrows, like a drawing sheet."""
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([w * 0.12, h * 0.22, w * 0.88, h * 0.7], radius=18, outline=CYAN + (230,), width=3)
    d.ellipse([w * 0.66, h * 0.32, w * 0.8, h * 0.6], outline=CYAN + (180,), width=2)
    y = h * 0.86
    d.line([(w * 0.12, y), (w * 0.88, y)], fill=CYAN + (200,), width=2)
    for x, sgn in ((w * 0.12, 1), (w * 0.88, -1)):
        d.line([(x, y - 14), (x, y + 14)], fill=CYAN + (200,), width=2)
        d.polygon([(x, y), (x + sgn * 18, y - 7), (x + sgn * 18, y + 7)], fill=CYAN + (220,))
    x = w * 0.05
    d.line([(x, h * 0.22), (x, h * 0.7)], fill=CYAN + (200,), width=2)
    for yy, sgn in ((h * 0.22, 1), (h * 0.7, -1)):
        d.polygon([(x, yy), (x - 7, yy + sgn * 18), (x + 7, yy + sgn * 18)], fill=CYAN + (220,))
    return _finish(img)


def panel_reticle(s=384):
    """A targeting reticle: broken ring, corner brackets, a centre dot."""
    img = _line_canvas((s, s))
    d = ImageDraw.Draw(img)
    c = s / 2
    for start in range(0, 360, 90):
        d.arc([c - s * 0.36, c - s * 0.36, c + s * 0.36, c + s * 0.36], start + 12, start + 78, fill=CYAN + (240,), width=5)
    L = s * 0.12
    for sx, sy in ((0.06, 0.06), (0.94, 0.06), (0.06, 0.94), (0.94, 0.94)):
        x, y = s * sx, s * sy
        dx = L if sx < 0.5 else -L
        dy = L if sy < 0.5 else -L
        d.line([(x, y), (x + dx, y)], fill=CYAN + (200,), width=3)
        d.line([(x, y), (x, y + dy)], fill=CYAN + (200,), width=3)
    d.ellipse([c - 9, c - 9, c + 9, c + 9], fill=CYAN + (255,))
    d.ellipse([c - s * 0.16, c - s * 0.16, c + s * 0.16, c + s * 0.16], outline=CYAN + (130,), width=2)
    return _finish(img)


def glyph_code(w=2048, h=96, count=40):
    """Made-up glyphs from strokes on a 3x4 grid (never letters of a real script)."""
    rng = random.Random(SEED + 1)
    img = _line_canvas((w, h))
    d = ImageDraw.Draw(img)
    cell = w / count
    gw, gh = cell * 0.5, h * 0.62
    for i in range(count):
        if rng.random() < 0.12:
            continue  # a gap, like a word break
        ox, oy = i * cell + (cell - gw) / 2, (h - gh) / 2
        pts = [(ox + gw * gx / 2, oy + gh * gy / 3) for gy in range(4) for gx in range(3)]
        for _ in range(rng.randint(2, 4)):
            a, b = rng.sample(range(12), 2)
            d.line([pts[a], pts[b]], fill=CYAN + (235,), width=5)
        if rng.random() < 0.4:
            p = pts[rng.randrange(12)]
            d.ellipse([p[0] - 5, p[1] - 5, p[0] + 5, p[1] + 5], fill=CYAN + (235,))
    return _finish(img, glow_px=2)


def silhouette(src, out):
    """A white picture with the source's alpha: the mask a shine sweep is clipped to."""
    a = Image.open(src).convert("RGBA").getchannel("A")
    white = Image.new("RGBA", a.size, (255, 255, 255, 0))
    white.putalpha(a)
    white.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "assets/ui/grand_opening"))
    ap.add_argument("--mask", nargs=2, metavar=("IN", "OUT"))
    a = ap.parse_args()
    if a.mask:
        silhouette(*a.mask)
        return
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    pieces = {
        "bokeh_disc": soft_disc(),
        "block_glow": glow(),
        "beta_bg": beta_bg(),
        "go_bg": go_bg(),
        "beta_panel_1": panel_circles(),
        "beta_panel_2": panel_section(),
        "beta_panel_3": panel_curve(),
        "beta_panel_4": panel_dimensions(),
        "beta_panel_5": panel_reticle(),
        "beta_code": glyph_code(),
    }
    for name, img in pieces.items():
        img.save(out / f"{name}.png", optimize=True)
        print(name, img.size)


if __name__ == "__main__":
    main()
