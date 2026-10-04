#!/usr/bin/env python3
"""Paint recoloured lucky-block textures from the Lucky Block 3.0 source atlases.

Re-runnable: every output PNG under assets/luckyblocks/textures/ is rewritten.
Sources are read only, never modified.

Outputs:
  sky_colormap.png      pale baby-blue recolour of Unique1 (Diamond Ghost)
  mythic_colormap.png   pastel rainbow recolour of Unique8 (Gold Titan)
  mystery_colormap.png  near-black navy body + rainbow rims from the standard atlas
  mystery_debug.png     rim mask in magenta over the source
  starter_colormap.png  cherry-red body + gold ribbon cross (and a bow on the top tile)
  starter_debug.png     face-tile squares outlined in cyan on the source
  lucky8_face.png       512x512 RGBA decal, white disc with a bold black "8"
  contact.png           labelled contact sheet of the six outputs
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SRC = "/Users/justinjin/Downloads/LuckyBlock3.0/Lucky Block 3.0/"
SRC_STANDARD = SRC + "BatchOne/Textures/C_01_M_01_BaseColorYellow.png"
SRC_GHOST = SRC + "BatchThree/Textures/Unique1/Unique1_BM.png"
SRC_TITAN = SRC + "BatchThree/Textures/Unique8/Unique8_BM.png"

OUT = "/Users/justinjin/Desktop/8ball/assets/luckyblocks/textures/"

# Standard atlas face tiles (x0, y0, x1, y1), exclusive upper bounds.
# Measured from the white "?" blobs: columns centred at x~120/364, rows at
# y~417/664/907, pitch ~244px. Top-left tile is the "top" face for the bow.
TILE = 244
TILE_X0 = (0, 244)
TILE_Y0 = (296, 540, 784)
TILES = [(x, y, x + TILE, min(y + TILE, 1024)) for y in TILE_Y0 for x in TILE_X0]

RIM_WIDTH = 18          # ring just inside each tile edge
RIM_NEAR_BG = 20        # body pixels this close to background also count as rim
TOP_BAND_Y = 150        # y < this is the top edge-trim band
RIGHT_TRIM_X = 700      # x >= this is the right-side edge trim


# ---------------------------------------------------------------- helpers

def load_rgb(path):
    return Image.open(path).convert("RGB")


def to_hsv(img_rgb):
    """Return H (0-360), S (0-1), V (0-1) float arrays from a PIL RGB image."""
    hsv = np.asarray(img_rgb.convert("HSV")).astype(np.float32)
    return hsv[..., 0] * (360.0 / 255.0), hsv[..., 1] / 255.0, hsv[..., 2] / 255.0


def from_hsv(h, s, v):
    """Vectorised HSV (0-360, 0-1, 0-1) -> uint8 RGB array."""
    h = np.mod(h, 360.0) / 60.0
    s = np.clip(s, 0, 1)
    v = np.clip(v, 0, 1)
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return (np.stack([r, g, b], axis=-1) * 255 + 0.5).astype(np.uint8)


def dilate(mask, radius):
    """Binary dilation with a square structuring element (radius px)."""
    out = mask.copy()
    pad = np.pad(mask, radius)
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            out |= pad[radius + dy:radius + dy + h, radius + dx:radius + dx + w]
    return out


def save(img, name):
    path = os.path.join(OUT, name)
    img.save(path)
    return path


def standard_masks(img):
    """Classify the standard atlas into body (orange), white, background (dark brown)."""
    H, S, V = to_hsv(img)
    orange_hue = (H >= 20) & (H <= 55) & (S > 0.45)
    body = orange_hue & (V > 0.47)            # background brown sits at V ~0.42
    background = orange_hue & (V <= 0.47)
    white = (~orange_hue) & (V > 0.55) & (S < 0.3)
    return body, white, background, (H, S, V)


# ---------------------------------------------------------------- 1. sky

def make_sky():
    src = Image.open(SRC_GHOST).convert("RGBA")
    alpha = np.asarray(src)[..., 3] > 8
    img = src.convert("RGB")
    H, S, V = to_hsv(img)
    white = (S < 0.18) & (V > 0.78)
    dark = V < 0.35                                   # the "?" marks and deep shadows
    hue = np.full_like(H, 203.0)
    sat = np.clip(S * 0.9, 0, 0.45)                   # clean baby blue, never greyish
    sat = np.where(V > 0.72, S * 0.35, sat)           # wings / bright faces drift to white
    val = 1.0 - (1.0 - V) * 0.4                       # lift everything: pale and soft
    # soften the near-black marks to a mid blue-grey
    sat = np.where(dark, 0.38, sat)
    val = np.where(dark, 0.42 + V * 0.6, val)
    out = from_hsv(hue, sat, val)
    out[white] = np.clip(np.asarray(img)[white].astype(int) + 8, 0, 255).astype(np.uint8)
    out[~alpha] = from_hsv(np.float32(203), np.float32(0.25), np.float32(0.97))  # flat fill under alpha 0
    return Image.fromarray(out)


# ---------------------------------------------------------------- 2. mythic

def make_mythic():
    src = Image.open(SRC_TITAN).convert("RGBA")
    alpha = np.asarray(src)[..., 3] > 8
    rgb = np.asarray(src.convert("RGB")).astype(np.float32) / 255.0
    lum = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    h, w = lum.shape
    yy, xx = np.mgrid[0:h, 0:w]
    hue = (xx + yy) / float(w + h - 2) * 360.0      # diagonal top-left -> bottom-right
    sat = np.full_like(lum, 0.45)
    # value follows luminance but sits high so the result is pastel, not muddy
    val = 0.95 * (0.5 + 0.5 * np.power(lum, 0.6))
    # darkest source pixels ("?" marks, deep shadows) stay dark so the shapes read
    dark = lum < 0.16
    val = np.where(dark, np.minimum(0.12 + lum / 0.16 * 0.23, 0.35), val)
    sat = np.where(dark, 0.35, sat)
    # smooth the hand-over between dark and lit so there is no hard step
    band = (lum >= 0.16) & (lum < 0.24)
    t = (lum - 0.16) / 0.08
    val = np.where(band, 0.35 * (1 - t) + val * t, val)
    out = from_hsv(hue, sat, val)
    out[~alpha] = from_hsv(hue, np.float32(0.3), np.float32(0.97))[~alpha]
    return Image.fromarray(out)


# ---------------------------------------------------------------- 3. mystery

def rim_mask(body, background):
    h, w = body.shape
    yy, xx = np.mgrid[0:h, 0:w]
    rim = np.zeros_like(body)
    for (x0, y0, x1, y1) in TILES:
        inside = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
        edge = (xx < x0 + RIM_WIDTH) | (xx >= x1 - RIM_WIDTH) | \
               (yy < y0 + RIM_WIDTH) | (yy >= y1 - RIM_WIDTH)
        rim |= inside & edge
    rim |= yy < TOP_BAND_Y
    rim |= xx >= RIGHT_TRIM_X
    rim |= dilate(background, RIM_NEAR_BG)
    return rim & body


def rainbow_for(rim, body):
    """Hue per rim pixel: angle around tile centre inside tiles, x along the top band,
    y down the right trim, x+y elsewhere."""
    h, w = rim.shape
    yy, xx = np.mgrid[0:h, 0:w]
    hue = (xx + yy) / float(w + h) * 360.0 * 2.0
    hue = np.where(yy < TOP_BAND_Y, xx / float(w) * 360.0 * 2.0, hue)
    hue = np.where(xx >= RIGHT_TRIM_X, yy / float(h) * 360.0 * 2.0, hue)
    for (x0, y0, x1, y1) in TILES:
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        inside = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
        ang = np.degrees(np.arctan2(yy - cy, xx - cx)) % 360.0
        hue = np.where(inside, ang, hue)
    return hue


def make_mystery():
    img = load_rgb(SRC_STANDARD)
    body, white, background, (H, S, V) = standard_masks(img)
    src = np.asarray(img)
    out = src.copy()
    # body -> near-black navy, slight lighting modulation so it is not flat
    navy = np.stack([14 + (V - 0.5) * 6, 14 + (V - 0.5) * 6, 24 + (V - 0.5) * 10], axis=-1)
    out[body] = np.clip(navy[body], 0, 255).astype(np.uint8)
    # white "?" -> slightly cool white, keep baked shading
    cool = src.astype(np.float32) * np.array([0.92, 0.94, 1.0]) + np.array([20, 20, 30])
    out[white] = np.clip(cool[white], 0, 255).astype(np.uint8)
    # rainbow rims
    rim = rim_mask(body, background)
    hue = rainbow_for(rim, body)
    shade = np.clip(0.95 * (0.7 + 0.35 * (V - 0.45)), 0.6, 1.0)   # keep the baked gradient
    rainbow = from_hsv(hue, np.full_like(hue, 0.75), shade)
    out[rim] = rainbow[rim]
    result = Image.fromarray(out)

    dbg = src.copy()
    dbg[rim] = (dbg[rim] * 0.35 + np.array([255, 0, 255]) * 0.65).astype(np.uint8)
    debug = Image.fromarray(dbg)
    return result, debug


# ---------------------------------------------------------------- 4. starter

GOLD = (255, 200, 40)
GOLD_EDGE = (220, 160, 20)


def draw_ribbon(draw, tile, with_bow):
    x0, y0, x1, y1 = tile
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    bw = int(round((x1 - x0) * 0.14))
    half = bw // 2
    e = 2  # edge line thickness
    # vertical band
    draw.rectangle([cx - half, y0, cx + half, y1 - 1], fill=GOLD)
    draw.rectangle([cx - half, y0, cx - half + e - 1, y1 - 1], fill=GOLD_EDGE)
    draw.rectangle([cx + half - e + 1, y0, cx + half, y1 - 1], fill=GOLD_EDGE)
    # horizontal band
    draw.rectangle([x0, cy - half, x1 - 1, cy + half], fill=GOLD)
    draw.rectangle([x0, cy - half, x1 - 1, cy - half + e - 1], fill=GOLD_EDGE)
    draw.rectangle([x0, cy + half - e + 1, x1 - 1, cy + half], fill=GOLD_EDGE)
    # the cross centre is solid gold (bands overlap)
    draw.rectangle([cx - half + e, cy - half + e, cx + half - e, cy + half - e], fill=GOLD)
    if with_bow:
        lw, lh = int((x1 - x0) * 0.26), int((y1 - y0) * 0.16)
        # two loops, left and right, slightly tilted up
        for sgn in (-1, 1):
            bx = cx + sgn * (lw // 2 + 6)
            draw.ellipse([bx - lw // 2, cy - lh // 2, bx + lw // 2, cy + lh // 2],
                         fill=GOLD, outline=GOLD_EDGE, width=3)
            draw.ellipse([bx - lw // 4, cy - lh // 4, bx + lw // 4, cy + lh // 4],
                         fill=(255, 220, 90), outline=GOLD_EDGE, width=2)
        # tails under the knot
        tl = int((y1 - y0) * 0.14)
        draw.polygon([(cx - 4, cy + 4), (cx - 22, cy + tl + 10), (cx - 6, cy + tl + 4)], fill=GOLD, outline=GOLD_EDGE)
        draw.polygon([(cx + 4, cy + 4), (cx + 22, cy + tl + 10), (cx + 6, cy + tl + 4)], fill=GOLD, outline=GOLD_EDGE)
        # knot
        k = 13
        draw.ellipse([cx - k, cy - k, cx + k, cy + k], fill=(235, 175, 25), outline=GOLD_EDGE, width=3)


def make_starter():
    img = load_rgb(SRC_STANDARD)
    body, white, background, (H, S, V) = standard_masks(img)
    src = np.asarray(img)
    orange_hue = body | background
    hue = np.where(orange_hue, 357.0, H)
    out = from_hsv(hue, S, V)
    out[white] = src[white]
    result = Image.fromarray(out)
    draw = ImageDraw.Draw(result)
    for i, tile in enumerate(TILES):
        draw_ribbon(draw, tile, with_bow=(i == 0))

    debug = img.copy()
    d = ImageDraw.Draw(debug)
    for i, (x0, y0, x1, y1) in enumerate(TILES):
        d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=(0, 255, 255), width=3)
        d.text((x0 + 8, y0 + 8), f"tile {i}", fill=(0, 255, 255))
    return result, debug


# ---------------------------------------------------------------- 5. lucky 8 decal

def load_bold_font(size):
    for path in ("/System/Library/Fonts/Supplemental/Arial Black.ttf",
                 "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=1 if path.endswith("Helvetica.ttc") else 0)
            except OSError:
                continue
    return ImageFont.load_default()


def make_lucky8():
    img = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([256 - 200, 256 - 200, 256 + 200, 256 + 200], fill=(255, 255, 255, 255))
    target_h = 300
    size = 300
    font = load_bold_font(size)
    for _ in range(6):   # converge on a glyph ~300px tall
        l, t, r, b = font.getbbox("8")
        h = b - t
        if abs(h - target_h) < 3:
            break
        size = int(size * target_h / max(h, 1))
        font = load_bold_font(size)
    l, t, r, b = font.getbbox("8")
    w, h = r - l, b - t
    d.text((256 - w / 2 - l, 256 - h / 2 - t), "8", font=font, fill=(0, 0, 0, 255))
    return img


# ---------------------------------------------------------------- contact sheet

def make_contact(entries):
    cell, pad, label_h = 340, 16, 28
    cols = 3
    rows = math.ceil(len(entries) / cols)
    sheet = Image.new("RGB", (cols * (cell + pad) + pad, rows * (cell + label_h + pad) + pad), (60, 60, 60))
    d = ImageDraw.Draw(sheet)
    font = load_bold_font(18)
    checker = Image.new("RGB", (cell, cell), (120, 120, 120))
    cd = ImageDraw.Draw(checker)
    for y in range(0, cell, 20):
        for x in range(0, cell, 20):
            if (x // 20 + y // 20) % 2 == 0:
                cd.rectangle([x, y, x + 19, y + 19], fill=(160, 160, 160))
    for i, (label, img) in enumerate(entries):
        cx = pad + (i % cols) * (cell + pad)
        cy = pad + (i // cols) * (cell + label_h + pad)
        thumb = img.resize((cell, cell), Image.LANCZOS)
        if thumb.mode == "RGBA":
            bg = checker.copy()
            bg.paste(thumb, (0, 0), thumb)
            thumb = bg
        sheet.paste(thumb.convert("RGB"), (cx, cy))
        d.text((cx + 4, cy + cell + 4), label, font=font, fill=(255, 255, 255))
    return sheet


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    paths = []

    sky = make_sky()
    paths.append(save(sky, "sky_colormap.png"))

    mythic = make_mythic()
    paths.append(save(mythic, "mythic_colormap.png"))

    mystery, mystery_dbg = make_mystery()
    paths.append(save(mystery, "mystery_colormap.png"))
    paths.append(save(mystery_dbg, "mystery_debug.png"))

    starter, starter_dbg = make_starter()
    paths.append(save(starter, "starter_colormap.png"))
    paths.append(save(starter_dbg, "starter_debug.png"))

    lucky8 = make_lucky8()
    paths.append(save(lucky8, "lucky8_face.png"))

    contact = make_contact([
        ("sky_colormap", sky),
        ("mythic_colormap", mythic),
        ("mystery_colormap", mystery),
        ("starter_colormap", starter),
        ("lucky8_face", lucky8),
        ("mystery_debug", mystery_dbg),
    ])
    paths.append(save(contact, "contact.png"))

    print("Face tiles (x0,y0,x1,y1):", TILES)
    for p in paths:
        print(p)


if __name__ == "__main__":
    main()
