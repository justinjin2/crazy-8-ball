"""Draw the Grand Opening card's drawn pieces (lively GUI pipeline, no image API).

Everything here is drawn from code with a fixed seed, so a rerun gives the same pixels:
  bokeh_disc.png      a soft white disc (tinted in game) for the drifting bokeh
  block_glow.png      a soft white radial glow (tinted gold in game) behind the block
  beta_bg.png         the Beta card's background: navy with a faint blueprint grid
  beta_panel_1..5.png blueprint panels in cyan line work (circles, a cue section, a grid with a
                      curve, dimension lines, a reticle), transparent, drawn at 2x then shrunk
  beta_code.png       a strip of made-up glyphs (never English), cyan, transparent
  beta_panel_6..10    more panels: a hex grid, a bar chart, a scope, a circuit, a glyph readout
  beta_ring.png       the section ring round the cue's middle (ticks, gaps, magenta dashes); spins
  beta_callouts.png   leader lines, glyph callout boxes and a dimension line drawn on the Beta
                      cue render's own canvas (cue_layout.json), so it overlays the cue exactly
  beta_mote.png       a small glowing square (white, tinted) for the drifting data motes
  firework_bg.png           the Grand Opening card's background: navy with soft bokeh, no fireworks
  confetti_1..6.png   `--confetti SHEET`: a generated 3 x 2 sheet of gold ribbons on black,
                      unscreened (brightness becomes alpha) and split, the halo fading
                      with distance from the ribbon
  *_mask.png          a white silhouette of a picture (its alpha), for shine sweeps:
                      `--mask IN.png OUT.png` makes one from any piece
The block's rays reuse assets/ui/lucky-rays.png (white, tinted in game).

  tools/gui/.venv/bin/python tools/gui/draw_pieces.py [--out assets/ui/grand_opening]
  tools/gui/.venv/bin/python tools/gui/draw_pieces.py --mask IN.png OUT.png
  tools/gui/.venv/bin/python tools/gui/draw_pieces.py --confetti SHEET.png
"""

import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt

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


def firework_bg(w=1024, h=512):
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


def confetti(sheet, out, cols=3, rows=2, size=256):
    """A generated sheet of gold ribbons on black -> one sprite per cell. Brightness becomes
    alpha (the glow turns into a soft halo over any colour), the cores stay solid, and the halo
    fades to nothing before the sprite's edge, so no box shows where it was cut."""
    a = np.asarray(Image.open(sheet).convert("RGB")).astype(float)
    m = a.max(-1)
    alpha = np.clip((m / 255 - 0.08) / 0.92, 0, 1) ** 1.4
    alpha = np.maximum(alpha, np.clip((m - 170) / 50, 0, 1))
    rgb = np.clip(a / np.maximum(m[..., None] / 255, 1e-3), 0, 255)
    H, W = m.shape
    n = 0
    for r in range(rows):
        for c in range(cols):
            cell = alpha[r * H // rows:(r + 1) * H // rows, c * W // cols:(c + 1) * W // cols]
            colour = rgb[r * H // rows:(r + 1) * H // rows, c * W // cols:(c + 1) * W // cols]
            ys, xs = np.where(cell > 0.5)  # the ribbon itself
            pad = 40
            y0, y1 = max(0, ys.min() - pad), min(cell.shape[0], ys.max() + pad)
            x0, x1 = max(0, xs.min() - pad), min(cell.shape[1], xs.max() + pad)
            al, co = cell[y0:y1, x0:x1].copy(), colour[y0:y1, x0:x1]
            # the halo fades with distance from the ribbon, gone well before the crop's edge
            core = al > 0.5
            dist = distance_transform_edt(~core)
            halo = np.clip(1 - dist / (pad * 0.75), 0, 1) ** 1.5 * 0.7
            al = np.where(core, al, al * halo)
            img = Image.fromarray(np.dstack([co, al * 255]).round().astype("uint8"), "RGBA")
            img.thumbnail((size, size), Image.LANCZOS)
            n += 1
            img.save(Path(out) / f"confetti_{n}.png", optimize=True)
            print(f"confetti_{n}", img.size)


def _glyph(d, ox, oy, gw, gh, rng, width=4, alpha=235):
    """One made-up glyph: 2-4 strokes on a 3 x 4 grid of points, sometimes a dot."""
    pts = [(ox + gw * gx / 2, oy + gh * gy / 3) for gy in range(4) for gx in range(3)]
    for _ in range(rng.randint(2, 4)):
        a, b = rng.sample(range(12), 2)
        d.line([pts[a], pts[b]], fill=CYAN + (alpha,), width=width)
    if rng.random() < 0.4:
        p = pts[rng.randrange(12)]
        d.ellipse([p[0] - width, p[1] - width, p[0] + width, p[1] + width], fill=CYAN + (alpha,))


def _glyph_line(d, x, y, count, size, rng, width=3, alpha=210):
    """A short 'word' of glyphs, for labels in callouts and panels."""
    for i in range(count):
        _glyph(d, x + i * size * 0.8, y, size * 0.5, size, rng, width, alpha)


def panel_hex(s=(448, 384)):
    """A hex grid with a few cells lit."""
    rng = random.Random(SEED + 2)
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    r = 30
    for row in range(int(h / (r * 1.5)) + 1):
        for col in range(int(w / (r * 1.75)) + 1):
            cx = col * r * 1.732 + (row % 2) * r * 0.866 + r
            cy = row * r * 1.5 + r
            hexagon = [(cx + r * math.cos(math.pi / 6 + k * math.pi / 3), cy + r * math.sin(math.pi / 6 + k * math.pi / 3)) for k in range(6)]
            lit = rng.random() < 0.15
            d.polygon(hexagon, outline=CYAN + (220 if lit else 90,), fill=CYAN + (60,) if lit else None, width=2)
    d.rectangle([2, 2, w - 3, h - 3], outline=CYAN + (170,), width=3)
    return _finish(img)


def panel_bars(s=(448, 320)):
    """A bar chart with a glyph label under each bar and a baseline."""
    rng = random.Random(SEED + 3)
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    base = h - 70
    d.line([(24, base), (w - 24, base)], fill=CYAN + (220,), width=3)
    d.line([(24, 20), (24, base)], fill=CYAN + (160,), width=2)
    for i in range(8):
        x = 46 + i * 48
        top = base - rng.uniform(0.2, 0.95) * (base - 30)
        d.rectangle([x, top, x + 28, base], outline=CYAN + (230,), fill=CYAN + (55,), width=2)
        _glyph(d, x + 6, base + 14, 14, 28, rng, 3, 200)
    for y in range(int(base) - 40, 20, -40):
        d.line([(18, y), (30, y)], fill=CYAN + (160,), width=2)
    return _finish(img)


def panel_wave(s=(512, 224)):
    """Two waveforms on a framed grid, like a scope."""
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, w - 3, h - 3], radius=14, outline=CYAN + (190,), width=3)
    for x in range(0, w, 32):
        d.line([(x, 8), (x, h - 8)], fill=CYAN + (40,), width=1)
    d.line([(8, h / 2), (w - 8, h / 2)], fill=CYAN + (90,), width=1)
    for amp, freq, phase, a, wd in ((h * 0.32, 3.0, 0.0, 255, 4), (h * 0.18, 7.0, 1.2, 150, 2)):
        pts = [(x, h / 2 + amp * math.sin(x / w * math.tau * freq + phase) * math.sin(x / w * math.pi)) for x in range(10, w - 9, 4)]
        d.line(pts, fill=CYAN + (a,), width=wd, joint="curve")
    return _finish(img)


def panel_nodes(s=(448, 384)):
    """A schematic: nodes joined by right-angle traces, like a circuit."""
    rng = random.Random(SEED + 4)
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    nodes = [(rng.uniform(40, w - 40), rng.uniform(40, h - 40)) for _ in range(9)]
    for i in range(1, len(nodes)):
        (x0, y0), (x1, y1) = nodes[rng.randrange(i)], nodes[i]
        d.line([(x0, y0), (x1, y0), (x1, y1)], fill=CYAN + (170,), width=3)
    for x, y in nodes:
        r = rng.choice((8, 11, 16))
        d.ellipse([x - r, y - r, x + r, y + r], outline=CYAN + (240,), fill=(8, 20, 60, 255), width=3)
        if r > 10:
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=CYAN + (255,))
    return _finish(img)


def panel_readout(s=(384, 288)):
    """Rows of glyph 'text' with a header bar and a progress bar: a data readout."""
    rng = random.Random(SEED + 5)
    w, h = s
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    d.rectangle([2, 2, w - 3, h - 3], outline=CYAN + (170,), width=3)
    d.rectangle([2, 2, w - 3, 40], fill=CYAN + (70,))
    _glyph_line(d, 16, 8, 6, 26, rng, 3, 255)
    for row in range(5):
        y = 56 + row * 36
        _glyph_line(d, 16, y, rng.randint(3, 7), 22, rng, 3, 190)
        d.line([(w * 0.62, y + 11), (w - 18, y + 11)], fill=CYAN + (70,), width=2)
    d.rectangle([16, h - 30, w - 16, h - 16], outline=CYAN + (200,), width=2)
    d.rectangle([18, h - 28, 18 + (w - 36) * 0.68, h - 18], fill=CYAN + (200,))
    return _finish(img)


def beta_ring(s=640):
    """The section ring around the cue's middle (13b's big circle): ticks, gaps, an inner
    dashed ring. Spins slowly in game (Rotation is smooth)."""
    img = _line_canvas((s, s))
    d = ImageDraw.Draw(img)
    c = s / 2
    for start in (8, 128, 248):
        d.arc([c - s * 0.46, c - s * 0.46, c + s * 0.46, c + s * 0.46], start, start + 100, fill=CYAN + (230,), width=6)
    for k in range(72):
        ang = k * math.tau / 72
        r0 = 0.40 if k % 6 else 0.37
        d.line([(c + math.cos(ang) * s * r0, c + math.sin(ang) * s * r0), (c + math.cos(ang) * s * 0.43, c + math.sin(ang) * s * 0.43)], fill=CYAN + (150,), width=2)
    for k in range(36):
        a0 = k * 10
        d.arc([c - s * 0.32, c - s * 0.32, c + s * 0.32, c + s * 0.32], a0, a0 + 5, fill=(255, 90, 220, 200), width=4)
    for ang in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        x, y = c + math.cos(ang) * s * 0.46, c + math.sin(ang) * s * 0.46
        d.polygon([(x + math.cos(ang) * 14, y + math.sin(ang) * 14), (x - math.sin(ang) * 9, y + math.cos(ang) * 9), (x + math.sin(ang) * 9, y - math.cos(ang) * 9)], fill=CYAN + (255,))
    return _finish(img)


def beta_callouts(layout, s=(2048, 568)):
    """Leader lines, callout boxes with glyph labels and a dimension line, on the cue render's own
    canvas (beta_cue.png's size, at 2x), so the overlay sits on the cue exactly and turns with it.
    `layout` gives the tip and butt pixels and the canvas the cue was rendered on."""
    rng = random.Random(SEED + 6)
    w, h = s
    k = w / layout["canvas"][0]  # canvas px -> this drawing's px
    tip = layout["tip_px"][0] * k
    butt = layout["butt_px"][0] * k
    mid = layout["tip_px"][1] * k
    img = _line_canvas(s)
    d = ImageDraw.Draw(img)
    along = lambda f: tip + (butt - tip) * f  # noqa: E731
    # (where along the cue, which side, how far the box sits along, glyph count)
    calls = [(0.03, 1, 0.10, 4), (0.52, -1, 0.40, 5), (0.77, -1, 0.86, 4), (0.95, 1, 0.80, 3)]
    for f, side, box_f, count in calls:
        ax, ay = along(f), mid + side * 50
        bx, by = along(box_f), mid + side * 205
        d.ellipse([ax - 9, ay - 9, ax + 9, ay + 9], outline=CYAN + (255,), width=4)
        d.line([(ax, ay), (ax + (bx - ax) * 0.35, by), (bx, by)], fill=CYAN + (220,), width=3)
        bw = count * 34 + 30
        left = bx if bx >= ax else bx - bw
        top = by - 26 if side < 0 else by - 26
        d.rectangle([left, top, left + bw, top + 52], outline=CYAN + (230,), fill=(8, 20, 60, 170), width=3)
        _glyph_line(d, left + 14, top + 10, count, 34, rng, 4, 240)
    # the dimension line under the cue: end ticks, arrows, a tick every tenth
    y = mid + 120
    d.line([(tip, y), (butt, y)], fill=CYAN + (200,), width=3)
    for x, sgn in ((tip, 1), (butt, -1)):
        d.line([(x, y - 22), (x, y + 22)], fill=CYAN + (220,), width=3)
        d.polygon([(x, y), (x + sgn * 26, y - 9), (x + sgn * 26, y + 9)], fill=CYAN + (230,))
    for i in range(1, 10):
        x = along(i / 10)
        d.line([(x, y - (14 if i % 5 else 22)), (x, y)], fill=CYAN + (170,), width=2)
    _glyph_line(d, along(0.5) - 50, y + 18, 3, 34, rng, 4, 220)
    return _finish(img, glow_px=2)


def mote(s=48):
    """A small glowing square: the data motes drifting up behind the Beta cue (white, tinted)."""
    img = _line_canvas((s * 2, s * 2))
    d = ImageDraw.Draw(img)
    c = s
    d.rectangle([c - 10, c - 10, c + 10, c + 10], fill=(255, 255, 255, 255))
    return _finish(img, glow_px=5)


def silhouette(src, out):
    """A white picture with the source's alpha: the mask a shine sweep is clipped to."""
    a = Image.open(src).convert("RGBA").getchannel("A")
    white = Image.new("RGBA", a.size, (255, 255, 255, 0))
    white.putalpha(a)
    white.save(out)


def for_motion(out):
    """Copies the game's smooth-motion code needs (gate 1): each confetti ribbon centred on a
    clear 256 square (the drift's glide windows a square picture), and the Beta card's glyph
    strip shrunk to half width and laid twice across 1024, so a window up to 512 texels wide
    can scroll along it and wrap (one period = 512)."""
    out = Path(out)
    for i in range(1, 7):
        src = Image.open(out / f"confetti_{i}.png").convert("RGBA")
        sq = Image.new("RGBA", (256, 256))
        sq.paste(src, ((256 - src.width) // 2, (256 - src.height) // 2))
        sq.save(out / f"confetti_sq_{i}.png", optimize=True)
    strip = Image.open(out / "beta_code.png").convert("RGBA")
    half = strip.resize((512, strip.height // 2), Image.LANCZOS)
    tile = Image.new("RGBA", (1024, half.height))
    tile.paste(half, (0, 0))
    tile.paste(half, (512, 0))
    tile.save(out / "beta_code_tile.png", optimize=True)
    print("confetti_sq_1..6 (256 x 256), beta_code_tile", tile.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "assets/ui/grand_opening"))
    ap.add_argument("--mask", nargs=2, metavar=("IN", "OUT"))
    ap.add_argument("--confetti", metavar="SHEET", help="split a generated 3 x 2 ribbon sheet")
    ap.add_argument("--for-motion", action="store_true", help="the square confetti and code tile")
    a = ap.parse_args()
    if a.for_motion:
        for_motion(a.out)
        return
    if a.mask:
        silhouette(*a.mask)
        return
    if a.confetti:
        confetti(a.confetti, a.out)
        return
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    pieces = {
        "bokeh_disc": soft_disc(),
        "block_glow": glow(),
        "beta_bg": beta_bg(),
        "firework_bg": firework_bg(),
        "beta_panel_1": panel_circles(),
        "beta_panel_2": panel_section(),
        "beta_panel_3": panel_curve(),
        "beta_panel_4": panel_dimensions(),
        "beta_panel_5": panel_reticle(),
        "beta_code": glyph_code(),
        "beta_panel_6": panel_hex(),
        "beta_panel_7": panel_bars(),
        "beta_panel_8": panel_wave(),
        "beta_panel_9": panel_nodes(),
        "beta_panel_10": panel_readout(),
        "beta_ring": beta_ring(),
        "beta_callouts": beta_callouts(json.loads((out / "cue_layout.json").read_text())),
        "beta_mote": mote(),
    }
    for name, img in pieces.items():
        img.save(out / f"{name}.png", optimize=True)
        print(name, img.size)


if __name__ == "__main__":
    main()
