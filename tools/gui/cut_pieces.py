"""Cut the Grand Opening card's pieces out of 13b (free, local; no image API).

For every cut piece: an alpha matte (BiRefNet HR on a crop, a soft disc for the blurred 8-balls,
a gold colour key for the confetti, a hand polygon where an edge is hidden), then the colours are
"decontaminated" (pymatting's foreground estimate, so no navy fringe rides on a soft edge), and
glows are added as "unmult over the local background" (alpha and colour chosen so that layer over
background gives back 13b exactly). Writes, into OUT (default the work folder, not the repo):

  layers/<id>.png         RGBA, cropped to its alpha with PAD px of clear border
  layers.json             each layer's x, y, w, h in 13b pixels, its z order and how it was cut
  masks/plate_fill.png    2172 x 724, white where the plate must be filled (every piece's hole,
                          where the piece is visible in 13b)
  masks/<id>_fill.png     in the layer's own pixels: where the layer itself is hidden in 13b
                          (block under the crown, balls behind buttons) and needs a masked fill
  plate_holes.png         13b with the holes cut out (alpha 0); the GPT masked edit fills them
  plate_preview_fill.png  the same holes filled by OpenCV inpainting: a stand-in for previews only

Usage: tools/gui/.venv/bin/python tools/gui/cut_pieces.py [--out DIR] [--only id,id]
BiRefNet weights download once from Hugging Face (ZhengPeng7/BiRefNet_HR, MIT); masks are cached
in OUT/cache so reruns are fast.
"""

import argparse
import json
import os
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw
from pymatting import estimate_foreground_ml
from scipy import ndimage as ndi

HERE = Path(__file__).resolve().parent
REFS = Path.home() / "Desktop/8ball-refs/gui-lively"
SRC = REFS / "13b-TARGET-grand-opening-original-2172px.png"
PIECES_JSON = HERE / "grand_opening/pieces.json"
PAD = 4  # clear px kept round every layer

# ---------------------------------------------------------------- the pieces
# roi: where the piece is worked on (13b px). z: stacking order (low = further back).
# Hand polygons are in 13b px. Values were read off 2-4x zooms with a grid and checked on the
# overlays this script writes to OUT/debug.
NEW_TAG = [(28, 116), (270, 92), (284, 207), (42, 232)]  # the NEW pill (real text; not cut)
ENDS_IN = [(106, 616), (446, 616), (446, 682), (106, 682)]  # "Ends in" text (real text)
# where the crown ends: everything above this line (inside the box) is crown, below is block
CROWN_POLY = [
    (225, 118), (500, 118), (500, 236), (470, 239), (448, 246), (432, 258), (426, 272),
    (423, 309), (395, 305), (360, 299), (325, 294), (290, 290), (260, 288), (238, 287),
    (231, 260), (231, 228), (225, 205),
]
# the block's outer silhouette where the crown and the text hide it: the visible top edges carried
# on to their meeting point (the back corner, about (303, 219)), the bottom edges likewise to the
# bottom corner (about (261, 638)); elsewhere the model mask is used
BLOCK_SIL = [(90, 248), (303, 217), (518, 316), (524, 336), (474, 601), (263, 639), (38, 522)]
BLOCK_HULL = [(80, 236), (296, 203), (534, 330), (490, 615), (285, 650), (30, 522)]

PIECES = [
    # far 8-balls: soft discs (cx, cy, r, edge softness), minus what covers them in 13b
    {"id": "ball_top", "z": 10, "how": "disc", "disc": (448, 74, 61.5, 2.5),
     "cover": ["rim", "confetti", "sparkle_top"], "roi": (375, 5, 522, 145)},
    {"id": "ball_bottom", "z": 10, "how": "disc", "disc": (555, 665, 72.5, 2.5),
     "cover": ["button_money_1", "rim", "confetti"], "roi": (470, 580, 640, 724)},
    {"id": "ball_top_right", "z": 11, "how": "disc", "disc": (1788, 96, 72.5, 2.5),
     "cover": ["rim", "confetti"], "roi": (1705, 12, 1872, 178)},
    {"id": "ball_bottom_right", "z": 11, "how": "disc", "disc": (2118, 642, 92.5, 3.0),
     "cover": ["button_money_10", "button_robux_10", "rim", "ribbon_br"], "roi": (2010, 540, 2172, 724)},
    # gold confetti ribbons on plain navy: colour key + matting
    {"id": "confetti_1", "z": 20, "how": "gold", "roi": (1640, 75, 1715, 165)},
    {"id": "confetti_2", "z": 20, "how": "gold", "roi": (1835, 75, 1905, 175)},
    {"id": "confetti_3", "z": 20, "how": "gold", "roi": (605, 300, 670, 370)},
    {"id": "confetti_4", "z": 20, "how": "gold", "roi": (1195, 340, 1275, 435)},
    {"id": "confetti_5", "z": 20, "how": "gold", "roi": (1325, 295, 1390, 375)},
    {"id": "confetti_6", "z": 20, "how": "gold", "roi": (1700, 385, 1770, 450)},
    # the lucky block, its crown, the two stars: BiRefNet HR on a crop
    {"id": "block", "z": 30, "how": "block", "roi": (20, 105, 580, 690)},
    {"id": "crown", "z": 31, "how": "crown", "roi": (215, 110, 510, 320)},
    # stars: a colour key finds the gold star and its navy outline; the thin bright blue rim
    # outside that is added as a band `rim` px wide (a crisp sticker edge, no firework streaks)
    {"id": "star_left", "z": 40, "how": "sticker", "roi": (558, 52, 680, 168), "rim": 2.5},
    {"id": "star_right", "z": 40, "how": "sticker", "roi": (1512, 52, 1636, 168), "rim": 2.5},
    # the cues: a hand-traced body (straightened along its axis) plus its glow by unmult
    {"id": "beta_cue", "z": 50, "how": "cue", "roi": (595, 180, 1295, 455),
     "axis": ((625, 425), (1257, 235)),
     # (u along the axis, v of the top edge, v of the bottom edge), v positive towards bottom
     "edges": [(-12, -3, 18), (0, -4, 18), (150, -10, 22), (300, -16, 26), (350, -17, 27),
               (500, -21, 23), (650, -26, 18), (664, -25, 16), (668, -20, 10)],
     "glow": 16, "clip": (608, 191, 1284, 445)},  # clip: inside the card's rim, so no rim glow
    {"id": "go_cue", "z": 50, "how": "model_glow", "roi": (1400, 205, 2110, 445),
     "keep": ("band", (1438, 412), (2080, 240), 34), "glow": 8,
     "clip": (1325, 191, 2109, 445)},
]

# what covers the far balls in 13b (13b px boxes, rounded corners ignored: these are only used to
# cut the cover out of the ball and to mark the ball's own fill area)
COVERS = {
    "rim": "rim",  # the card's pale rim: found by colour
    "button_money_1": [(598, 548), (1040, 548), (1040, 650), (598, 650)],
    "button_money_10": [(1540, 548), (2045, 548), (2045, 650), (1540, 650)],
    "button_robux_10": [(1540, 470), (2045, 470), (2045, 560), (1540, 560)],
    "confetti": "gold",
    "sparkle_top": [(381, 72), (417, 72), (417, 128), (381, 128)],  # the sparkle on ball_top
    "ribbon_br": [(2100, 538), (2148, 538), (2148, 558), (2100, 558)],  # its warm highlight is its own
}

# ---------------------------------------------------------------- helpers


def load_src():
    return np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64) / 255.0


def poly_mask(shape, pts, ox=0, oy=0, ss=4):
    """Anti-aliased polygon mask (4x supersampled) in a box of `shape` whose corner is (ox, oy)."""
    h, w = shape
    im = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([((x - ox) * ss, (y - oy) * ss) for x, y in pts], fill=255)
    return np.asarray(im.resize((w, h), Image.BOX)).astype(np.float64) / 255.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


_MODEL = {}


def birefnet(rgb, key, cache_dir, variant="BiRefNet_HR", size=2048):
    """Soft mask from BiRefNet (MIT) for an RGB float crop; cached as a 16-bit PNG."""
    path = cache_dir / f"{variant}_{key}.png"
    if path.exists():
        return np.asarray(Image.open(path)).astype(np.float64) / 65535.0
    import torch
    from torchvision import transforms
    from transformers import AutoModelForImageSegmentation

    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    if variant not in _MODEL:
        m = AutoModelForImageSegmentation.from_pretrained(f"ZhengPeng7/{variant}", trust_remote_code=True)
        _MODEL[variant] = m.float().to(dev).eval()
    tf = transforms.Compose([
        transforms.Resize((size, size)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])
    pil = Image.fromarray((rgb * 255).round().astype(np.uint8))
    with torch.no_grad():
        p = _MODEL[variant](tf(pil).unsqueeze(0).to(dev))[-1].sigmoid().cpu()[0, 0].numpy()
    a = np.asarray(Image.fromarray(p.astype(np.float32), mode="F").resize(pil.size, Image.BILINEAR))
    a = np.clip(a, 0, 1)
    Image.fromarray((a * 65535).round().astype(np.uint16)).save(path)
    return a.astype(np.float64)


def local_background(rgb, hole, sigma=10.0):
    """Smooth guess of what lies behind `hole` (0..1): normalised blur of the pixels outside it."""
    w = (1 - hole) ** 4
    num = np.stack([ndi.gaussian_filter(rgb[..., c] * w, sigma) for c in range(3)], -1)
    den = ndi.gaussian_filter(w, sigma)[..., None]
    return num / np.maximum(den, 1e-4)


def unmult_over(rgb, bg):
    """Alpha and colour so that colour*alpha + bg*(1-alpha) == rgb wherever rgb is brighter
    than bg (a glow), with the least alpha that keeps colour inside 0..1."""
    excess = np.clip(rgb - bg, 0, None)
    a = np.max(excess / np.maximum(1 - bg, 1e-3), axis=-1)
    a = np.clip(a, 0, 1)
    col = bg + excess / np.maximum(a[..., None], 1e-3)
    return a, np.clip(col, 0, 1)


def dist_outside(mask_bool):
    """Distance in px from the mask, 0 inside."""
    return ndi.distance_transform_edt(~mask_bool)


def rim_mask(rgb):
    """The card's pale blue-white rim: bright and unsaturated, in big pieces only (a ball's
    small white highlight is not rim)."""
    mx, mn = rgb.max(-1), rgb.min(-1)
    m = smoothstep(0.62, 0.75, mn) * smoothstep(0.30, 0.18, mx - mn)
    lab, n = ndi.label(m > 0.1)
    if n:
        sizes = ndi.sum(m > 0.1, lab, range(1, n + 1))
        m = m * np.isin(lab, 1 + np.nonzero(sizes >= 200)[0])
    return m


def gold_key(rgb):
    """0..1 'how gold' a pixel is: warm (red over blue) and bright."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    warm = smoothstep(0.10, 0.38, r - b) * smoothstep(0.05, 0.25, g - b * 0.8)
    return warm * smoothstep(0.25, 0.55, r)


def refine_alpha(rgb, a, fg_t=0.97, bg_t=0.03, band=2):
    """Closed-form matting in a thin unknown band round the mask edge (sharpens soft model
    edges against the real pixels)."""
    from pymatting import estimate_alpha_cf

    fg = ndi.binary_erosion(a > fg_t, iterations=band)
    bg = ndi.binary_erosion(a < bg_t, iterations=band)
    tri = np.full(a.shape, 0.5)
    tri[fg] = 1
    tri[bg] = 0
    if (tri == 0.5).sum() == 0:
        return a
    return np.clip(estimate_alpha_cf(rgb, tri), 0, 1)


# ---------------------------------------------------------------- cutters
# each returns (alpha, colour, fill) on the roi: colour may be None (use decontaminated 13b);
# fill marks pixels of the layer that are hidden in 13b and must be painted by a masked edit.


def cut_disc(p, rgb, ox, oy):
    """A blurred 8-ball: a soft disc (r = the rim's outer half-max, measured on radial profiles)
    plus its blue rim glow by unmult. What covers it in 13b (buttons, the card rim, sparkles)
    does not bite the ball: the ball stays whole there and those pixels are marked to fill."""
    h, w = rgb.shape[:2]
    cx, cy, r, soft = p["disc"]
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.hypot(xx + ox + 0.5 - cx, yy + oy + 0.5 - cy)
    core = smoothstep(r + soft, r - soft, d)
    cover = np.zeros((h, w))
    for c in p["cover"]:
        spec = COVERS[c]
        if spec == "rim":
            m = rim_mask(rgb)
        elif spec == "gold":  # sparkles and ribbons: strong gold blobs of a fair size only
            # (blue below 0.55 keeps a ball's own white highlight out)
            m = (gold_key(rgb) > 0.4) & (rgb[..., 2] < 0.55)
            lab, n = ndi.label(m)
            if n:
                sizes = ndi.sum(m, lab, range(1, n + 1))
                m = np.isin(lab, 1 + np.nonzero(sizes >= 15)[0])
            m = ndi.binary_dilation(m, iterations=3).astype(float)
        else:
            m = poly_mask((h, w), spec, ox, oy)
            # include the button's dark outline and its shadow
            m = ndi.maximum_filter(m, 9)
        cover = np.maximum(cover, m)
    cover = ndi.gaussian_filter(ndi.maximum_filter(cover, 5), 1.0)
    _, ga, gcol, _ = add_glow(rgb, core, 7, extra_hole=cover)
    ga = ga * (1 - np.clip(cover, 0, 1))
    fill = np.clip(cover, 0, 1) * (core > 0.02)
    return core, (ga, gcol), fill


def cut_gold(p, rgb, ox, oy):
    from pymatting import estimate_alpha_cf

    k = gold_key(rgb)
    fg = ndi.binary_opening(k > 0.85, iterations=1)
    lab, n = ndi.label(fg)
    if n > 1:  # keep the biggest gold blob: the ribbon, not stray sparks
        sizes = ndi.sum(fg, lab, range(1, n + 1))
        fg = lab == (1 + int(np.argmax(sizes)))
    near = ndi.binary_dilation(fg, iterations=7)
    tri = np.full(k.shape, 0.5)
    tri[ndi.binary_erosion(fg, iterations=1)] = 1
    tri[~near] = 0
    a = np.clip(estimate_alpha_cf(rgb, tri), 0, 1)
    a[~near] = 0
    # the ribbon's soft gold glow: unmult over the local navy, a few px only
    bg = local_background(rgb, ndi.binary_dilation(near, iterations=3).astype(float), 6)
    ga, gcol = unmult_over(rgb, bg)
    ring = smoothstep(7, 2, dist_outside(a > 0.5)) * (1 - a)
    ga = ga * ring * gold_key(np.clip(gcol, 0, 1)) ** 0.5
    return a, ga, gcol, bg


def cut_model(p, rgb, ox, oy, cache, key):
    a = birefnet(rgb, key, cache)
    if "keep" in p:
        a = a * keep_mask(p["keep"], a.shape, ox, oy)
    return a


def keep_mask(spec, shape, ox, oy):
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    if spec[0] == "ellipse":
        _, cx, cy, rx, ry = spec
        d = np.hypot((xx + ox - cx) / rx, (yy + oy - cy) / ry)
        return smoothstep(1.05, 0.95, d)
    if spec[0] == "band":
        _, p0, p1, half = spec
        p0, p1 = np.array(p0, float), np.array(p1, float)
        L = np.linalg.norm(p1 - p0)
        d = (p1 - p0) / L
        u = (xx + ox - p0[0]) * d[0] + (yy + oy - p0[1]) * d[1]
        v = -(xx + ox - p0[0]) * d[1] + (yy + oy - p0[1]) * d[0]
        inside = np.minimum(smoothstep(half + 2, half - 2, np.abs(v)),
                            smoothstep(-half - 2, -half + 2, u) * smoothstep(L + half + 2, L + half - 2, u))
        return inside
    raise ValueError(spec)


def cue_body(p, shape, ox, oy):
    """The hand-traced cue silhouette: edges given in (u, v) along the axis, back to 13b px."""
    p0, p1 = (np.array(q, float) for q in p["axis"])
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    n = np.array([-d[1], d[0]])
    top = [p0 + u * d + v * n for u, v, _ in p["edges"]]
    bot = [p0 + u * d + v * n for u, _, v in p["edges"]]
    pts = [tuple(q) for q in top] + [tuple(q) for q in reversed(bot)]
    return poly_mask(shape, pts, ox, oy)


def add_glow(rgb, core, width, extra_hole=None):
    """Core (solid) plus its glow: unmult over the local background in a ring `width` px wide.
    The ring uses a median-filtered image so thin background lines (blueprints) stay behind."""
    hole = ndi.binary_dilation(core > 0.02, iterations=width + 2).astype(float)
    if extra_hole is not None:
        hole = np.maximum(hole, extra_hole)
    bg = local_background(rgb, hole, 12)
    med = np.stack([ndi.median_filter(rgb[..., c], size=5) for c in range(3)], -1)
    ga, gcol = unmult_over(med, bg)
    ring = smoothstep(width, 0, dist_outside(core > 0.5))
    ga = ga * ring
    alpha = core + ga * (1 - core)
    return alpha, ga, gcol, bg


# ---------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REFS / "work/pieces"))
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    out = Path(os.path.expanduser(args.out))
    for sub in ("layers", "masks", "cache", "debug"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    src = load_src()
    H, W = src.shape[:2]
    only = set(filter(None, args.only.split(",")))

    layers_path = out / "layers.json"
    layers = json.loads(layers_path.read_text())["layers"] if (only and layers_path.exists()) else []
    layers = [l for l in layers if l["id"] not in only]

    for p in PIECES:
        if only and p["id"] not in only:
            continue
        x0, y0, x1, y1 = p["roi"]
        rgb = src[y0:y1, x0:x1]
        shape = rgb.shape[:2]
        key = f"{x0}_{y0}_{x1}_{y1}"
        how = p["how"]
        fill = np.zeros(shape)  # 0..1: how much of this layer pixel is hidden in 13b
        glow = None  # (glow alpha, glow colour): composited under the decontaminated core

        if how == "disc":
            core, glow, fill = cut_disc(p, rgb, x0, y0)
        elif how == "gold":
            core, ga, gcol, _ = cut_gold(p, rgb, x0, y0)
            glow = (ga, gcol)
        elif how == "model":
            core = refine_alpha(rgb, cut_model(p, rgb, x0, y0, out / "cache", key))
            if "keep" in p:
                core = core * keep_mask(p["keep"], shape, x0, y0)
        elif how == "sticker":
            # gold star = the biggest gold blob near the crop centre; its navy outline = dark
            # pixels within 11 px of it (fireworks are bright, so they stay out)
            g = gold_key(rgb) > 0.5
            lab, n = ndi.label(g)
            sizes = ndi.sum(g, lab, range(1, n + 1))
            cyx = np.array(shape) / 2
            big = [i + 1 for i in np.nonzero(sizes > 300)[0]]
            best = min(big, key=lambda i: np.hypot(*(np.argwhere(lab == i).mean(0) - cyx)))
            star = ndi.binary_fill_holes(lab == best)
            ring = ndi.binary_dilation(star, iterations=11) & (rgb.max(-1) < 0.30)
            m = ndi.binary_fill_holes(star | ring)
            m = ndi.binary_opening(ndi.binary_closing(m, iterations=2), iterations=2)
            sd = ndi.distance_transform_edt(~m) - ndi.distance_transform_edt(m)  # signed, + outside
            sd = ndi.gaussian_filter(sd, 0.8)
            core = smoothstep(p["rim"] + 0.7, p["rim"] - 0.7, sd)
        elif how == "block":
            m = birefnet(rgb, key, out / "cache")
            hull = poly_mask(shape, BLOCK_HULL, x0, y0)
            crown = poly_mask(shape, CROWN_POLY, x0, y0)
            new = ndi.maximum_filter(poly_mask(shape, NEW_TAG, x0, y0), 5)
            text = poly_mask(shape, ENDS_IN, x0, y0)
            sil = poly_mask(shape, BLOCK_SIL, x0, y0)
            m = refine_alpha(rgb, m * hull * (1 - new))
            # under the crown and the "Ends in" text: the block's continued silhouette (solid),
            # to be painted by a masked fill. Sums (not max) so the anti-aliased seams add to 1.
            cover = np.maximum(crown, text)
            hidden = sil * cover
            core = m * ndi.maximum_filter(sil, 5) * (1 - cover) + hidden
            fill = hidden
        elif how == "crown":
            m = birefnet(rgb, key, out / "cache")
            # the block's own run sees the crown as solid where it sits on the block: use both
            bx0, by0, bx1, by1 = next(q["roi"] for q in PIECES if q["id"] == "block")
            mb = birefnet(src[by0:by1, bx0:bx1], f"{bx0}_{by0}_{bx1}_{by1}", out / "cache")
            m = np.maximum(m, mb[y0 - by0:y1 - by0, x0 - bx0:x1 - bx0])
            crown = poly_mask(shape, CROWN_POLY, x0, y0)
            new = ndi.maximum_filter(poly_mask(shape, NEW_TAG, x0, y0), 5)
            core = refine_alpha(rgb, m * (1 - new)) * crown * (1 - new)
        elif how == "cue":
            core = cue_body(p, shape, x0, y0)
            core = ndi.gaussian_filter(core, 0.6)
            _, ga, gcol, _ = add_glow(rgb, core, p["glow"])
            glow = (ga, gcol)
        elif how == "model_glow":
            m = cut_model(p, rgb, x0, y0, out / "cache", key)
            core = refine_alpha(rgb, m) * keep_mask(p["keep"], shape, x0, y0)
            _, ga, gcol, _ = add_glow(rgb, core, p["glow"])
            glow = (ga, gcol)
        else:
            raise ValueError(how)

        # decontaminate the core's colours: foreground estimate from 13b and the core alpha
        fgc = estimate_foreground_ml(rgb, np.clip(core, 0, 1))
        if glow is not None:
            ga, gcol = glow
            alpha = core + ga * (1 - core)
            col = (fgc * core[..., None] + gcol * (ga * (1 - core))[..., None]) / np.maximum(alpha[..., None], 1e-4)
        else:
            alpha, col = core, fgc
        if fill.max() > 0.02:
            # stand-in paint for hidden parts (OpenCV inpaint) until the masked regen fills them;
            # sources: only the layer's own visible pixels (alpha > 0.5 and not hidden)
            paint = (fill > 0.02) | (alpha < 0.5)
            if how == "block":  # never paint from the covered area (no text colours)
                paint |= (cover > 0.02) & (ndi.maximum_filter(sil, 5) > 0.02)
            im8 = (col * 255).round().astype(np.uint8)
            painted = cv2.inpaint(im8, (paint * 255).astype(np.uint8), 5, cv2.INPAINT_TELEA) / 255.0
            col = np.where(paint[..., None], painted, col)
        if "clip" in p:
            cx0, cy0, cx1, cy1 = p["clip"]
            alpha = alpha * poly_mask(shape, [(cx0, cy0), (cx1, cy0), (cx1, cy1), (cx0, cy1)], x0, y0)
        alpha = np.where(alpha < 1.5 / 255, 0, alpha)

        # tight crop with PAD px of clear border, in 13b coordinates
        ys, xs = np.nonzero(alpha > 0)
        bx0, by0 = max(xs.min() - PAD, 0), max(ys.min() - PAD, 0)
        bx1, by1 = min(xs.max() + 1 + PAD, shape[1]), min(ys.max() + 1 + PAD, shape[0])
        rgba = np.dstack([col, alpha])[by0:by1, bx0:bx1]
        Image.fromarray((np.clip(rgba, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(out / "layers" / f"{p['id']}.png")
        fill_rel = None
        if fill.max() > 0.02:
            fill_rel = f"masks/{p['id']}_fill.png"
            Image.fromarray((fill[by0:by1, bx0:bx1] * 255).round().astype(np.uint8)).save(out / fill_rel)
        gx, gy = x0 + bx0, y0 + by0
        layers.append({
            "id": p["id"], "file": f"layers/{p['id']}.png", "x": int(gx), "y": int(gy),
            "w": int(bx1 - bx0), "h": int(by1 - by0), "z": p["z"], "how": how,
            "fill_mask": fill_rel,
        })
        print(f"{p['id']:18s} box [{gx}, {gy}, {gx + bx1 - bx0}, {gy + by1 - by0}]  how={how}")

    # the plate's holes: union of every layer's visible alpha, alpha x (1 - fill) (read back from
    # the files so a partial --only run still sees the others), grown 2 px. Where a layer is
    # hidden (a ball behind a button), the plate keeps what covers it.
    hole = np.zeros((H, W))
    for l in layers:
        la = np.asarray(Image.open(out / l["file"]))[..., 3] / 255.0
        if l["fill_mask"]:
            la = la * (1 - np.asarray(Image.open(out / l["fill_mask"])) / 255.0)
        hole[l["y"]:l["y"] + l["h"], l["x"]:l["x"] + l["w"]] = np.maximum(
            hole[l["y"]:l["y"] + l["h"], l["x"]:l["x"] + l["w"]], la)
    hole_b = ndi.binary_dilation(hole > 0.02, iterations=2)
    Image.fromarray((hole_b * 255).astype(np.uint8)).save(out / "masks/plate_fill.png")
    src8 = (src * 255).round().astype(np.uint8)
    Image.fromarray(np.dstack([src8, (~hole_b * 255).astype(np.uint8)]), "RGBA").save(out / "plate_holes.png")
    prev = cv2.inpaint(src8, (hole_b * 255).astype(np.uint8), 7, cv2.INPAINT_TELEA)
    Image.fromarray(prev).save(out / "plate_preview_fill.png")

    layers.sort(key=lambda l: (l["z"], l["id"]))
    layers_path.write_text(json.dumps({
        "about": "Layers cut from 13b by tools/gui/cut_pieces.py. x, y, w, h in 13b px (2172 x 724); "
                 "stack by z over plate_holes.png (filled). fill_mask (0-255, layer px): how much of that layer "
                 "is hidden in 13b (under the crown, the text, a button, the rim); those pixels are painted "
                 "for now by OpenCV inpaint and want a masked regen.",
        "source": str(SRC), "size": [W, H], "plate": "plate_holes.png",
        "plate_fill_mask": "masks/plate_fill.png", "layers": layers,
    }, indent=1))


if __name__ == "__main__":
    main()
