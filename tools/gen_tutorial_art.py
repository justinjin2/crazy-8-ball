#!/usr/bin/env python3
"""The tutorial's art (docs/prompts/TUTORIAL_PROMPT.md step 2), drawn in code so it is ours.

- hand.png: the pointer hand (redrawn 2026-10-03 after the designer's "tap here" icon): a flat
  white cartoon hand pointing UP with its index finger, the other three fingers folded down the
  right, the thumb out to the left; a light-blue shade on its lower-right edges and a very
  thick black outline. Its fingertip is Config.Tutorial.Hand.TipX/TipY, the point it taps.
- hand_rays.png: the five tap lines over that fingertip, the same size, laid over hand.png.
- mouse.png: a computer mouse in the same style (the hand drags it on a computer).
- floor_arrow.png: one white up-arrow (reference 02's arrow path: a wide head on a short stem,
  soft edges), pointing up in the image; the client lays many on the floor.

Run from the repo root: python3 tools/gen_tutorial_art.py  (writes assets/ui/tutorial/)
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "tutorial")
SS = 4  # supersampling

WHITE = (255, 255, 255, 255)
SHADE = (176, 220, 240, 255)  # the light-blue edge shade
INK = (14, 16, 24, 255)


def capsule(draw, a, b, r, fill=255):
    """A stroke from a to b with round ends, radius r (in supersampled pixels)."""
    draw.line([a, b], fill=fill, width=int(2 * r))
    for (x, y) in (a, b):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def grow(mask, r):
    """The mask dilated by about r pixels (round): a blur, then a low threshold."""
    blurred = mask.filter(ImageFilter.GaussianBlur(r / 2))
    return blurred.point(lambda v: 255 if v > 8 else 0)


def shrink(mask, r):
    inv = ImageChops.invert(mask)
    return ImageChops.invert(grow(inv, r))


def shade_band(mask, dx, dy):
    """The part of the mask along its lower-right edges: the mask minus itself moved by (dx, dy)."""
    moved = ImageChops.offset(mask, -int(dx), -int(dy))
    return ImageChops.subtract(mask, moved)


def compose(parts_masks, outline, shade_dx, shade_dy, size, separators=()):
    """Fills the union of masks white, shades its lower-right edges, inks the outline around it
    and the separator strokes inside (lines between fingers)."""
    union = Image.new("L", size, 0)
    for m in parts_masks:
        union = ImageChops.lighter(union, m)
    union = grow(shrink(union, 6 * SS), 6 * SS)  # soften inner corners
    outer = grow(union, outline)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.paste(INK, (0, 0), outer)
    img.paste(WHITE, (0, 0), union)
    band = shade_band(union, shade_dx, shade_dy)
    # Each part also shades its own lower-right edge (the fingers read as separate blocks).
    for m in parts_masks:
        band = ImageChops.lighter(band, ImageChops.multiply(shade_band(m, shade_dx, shade_dy), union))
    img.paste(SHADE, (0, 0), band)
    if separators:
        sep = Image.new("L", size, 0)
        d = ImageDraw.Draw(sep)
        for (a, b, w) in separators:
            capsule(d, a, b, w)
        img.paste(INK, (0, 0), ImageChops.multiply(sep, union))
    return img


def finish(img, final):
    return img.resize((final, final), Image.LANCZOS)


def layer(img, mask, edge, shade_dx, shade_dy):
    """Draws one part over img: a thin ink edge round it, the white fill, and the light-blue
    shade on its lower-right edges."""
    img.paste(INK, (0, 0), grow(mask, edge))
    img.paste(WHITE, (0, 0), mask)
    img.paste(SHADE, (0, 0), shade_band(mask, shade_dx, shade_dy))


# The hand is drawn on a 512 grid, then shrunk and moved down by this so the tap lines above
# its fingertip fit in the picture (hand_rays.png uses the same placing).
HAND_K, HAND_DX, HAND_DY = 0.84, 38, 50


def hand_point(x, y):
    """A point on the hand's drawing grid, in supersampled pixels of the picture."""
    return ((x * HAND_K + HAND_DX) * SS, (y * HAND_K + HAND_DY) * SS)


def hand():
    n = 512 * SS
    size = (n, n)
    s = SS * HAND_K  # a radius on the drawing grid
    P = hand_point

    def blank():
        m = Image.new("L", size, 0)
        return m, ImageDraw.Draw(m)

    # The index finger straight up (its tip at HAND_TIP), the palm under it, the thumb out to the
    # left and the other three fingers folded down the right, each a step lower (reference:
    # the "tap here" pointer icon, designer 2026-10-03).
    index, d = blank()
    capsule(d, P(214, 74), P(214, 330), 38 * s)
    palm, d = blank()
    d.rounded_rectangle([P(176, 262), P(446, 470)], radius=96 * s, fill=255)
    d.polygon([P(176, 300), P(446, 300), P(430, 440), P(200, 440)], fill=255)
    thumb, d = blank()
    capsule(d, P(214, 392), P(108, 296), 34 * s)
    fingers = []
    for x, top, r in ((284, 206, 35), (350, 232, 33), (410, 262, 30)):
        m, d = blank()
        capsule(d, P(x, top), P(x, 340), r * s)
        fingers.append(m)
    union = Image.new("L", size, 0)
    for m in [index, palm, thumb] + fingers:
        union = ImageChops.lighter(union, m)
    union = grow(shrink(union, 6 * s), 6 * s)  # soften the inner corners
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.paste(INK, (0, 0), grow(union, 24 * s))  # the thick outline round it all
    img.paste(WHITE, (0, 0), union)
    img.paste(SHADE, (0, 0), shade_band(union, 18 * s, 18 * s))
    # Each raised part also shades its own lower-right edge, so the fingers read apart.
    for m in [index] + fingers:
        img.paste(SHADE, (0, 0), ImageChops.multiply(shade_band(m, 12 * s, 0), union))
    # The lines between the fingers, down to the knuckles, and the thumb's crease.
    d = ImageDraw.Draw(img)
    for (x, top, bottom) in ((251, 200, 318), (318, 230, 324), (381, 260, 330)):
        capsule(d, P(x, top), P(x, bottom), 6 * s, fill=INK)
    capsule(d, P(176, 352), P(214, 384), 6 * s, fill=INK)
    return finish(img, 512)


def hand_rays():
    """The five short tap lines over the fingertip (up, the two diagonals, left and right), on a
    square the hand's size, so it lines up with hand.png when placed on top of it."""
    n = 512 * SS
    size = (n, n)
    s = SS * HAND_K
    P = hand_point
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    cx, cy = 214, 74  # the fingertip's round end, the same point as in hand()
    for deg in (180, 225, 270, 315, 0):
        a = math.radians(deg)
        ux, uy = math.cos(a), math.sin(a)
        inner, outer = 70, 112
        capsule(d, P(cx + ux * inner, cy + uy * inner), P(cx + ux * outer, cy + uy * outer), 9 * s)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.paste(INK, (0, 0), grow(m, 8 * s))
    img.paste(WHITE, (0, 0), m)
    return finish(img, 512)


def mouse():
    n = 256 * SS
    size = (n, n)
    s = SS

    def P(x, y):
        return (x * s, y * s)

    body = Image.new("L", size, 0)
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([P(66, 36), P(190, 224)], radius=60 * s, fill=255)
    img = compose([body], 14 * s, 9 * s, 10 * s, size, [(P(128, 40), P(128, 108), 4 * s), (P(70, 108), P(186, 108), 4 * s)])
    # The wheel.
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([P(118, 60), P(138, 96)], radius=10 * s, fill=INK)
    return finish(img, 256)


def floor_arrow():
    n = 256 * SS
    size = (n, n)
    s = SS
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    # A wide head and a short stem, pointing up, centred, clear space round it.
    d.polygon([(128 * s, 24 * s), (226 * s, 132 * s), (30 * s, 132 * s)], fill=255)
    d.rectangle([92 * s, 128 * s, 164 * s, 214 * s], fill=255)
    m = grow(shrink(m, 10 * s), 10 * s)  # rounded corners
    soft = m.filter(ImageFilter.GaussianBlur(3 * s))
    img = Image.new("RGBA", size, (255, 255, 255, 0))
    img.putalpha(soft)
    return img.resize((256, 256), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in (
        ("hand.png", hand),
        ("hand_rays.png", hand_rays),
        ("mouse.png", mouse),
        ("floor_arrow.png", floor_arrow),
    ):
        path = os.path.join(OUT, name)
        make().save(path)
        print("wrote", os.path.abspath(path))


if __name__ == "__main__":
    main()
