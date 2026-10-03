#!/usr/bin/env python3
"""The tutorial's art (docs/prompts/TUTORIAL_PROMPT.md step 2), drawn in code so it is ours.

- hand.png: the pointer hand, after reference 01's style (~/Desktop/8ball-refs/tutorial/
  01-pointer-hand-cursor.png): a flat white cartoon hand pointing down with its index finger,
  the other three fingers folded in a row, the thumb along the right; a light-blue shade on its
  lower-right edges and a very thick black outline. Its fingertip is at the image's bottom
  centre (HAND_TIP), which is where the client puts the point it taps.
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
    moved = ImageChops.offset(mask, -dx, -dy)
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


def hand():
    n = 512 * SS
    size = (n, n)
    s = SS

    def P(x, y):
        return (x * s, y * s)

    def blank():
        m = Image.new("L", size, 0)
        return m, ImageDraw.Draw(m)

    # The block: the back of the hand, the index finger and the thumb as one piece.
    block, d = blank()
    d.polygon([P(200, 74), P(390, 92), P(414, 262), P(312, 336), P(196, 262)], fill=255)
    capsule(d, P(216, 96), P(378, 110), 30 * s)
    capsule(d, P(386, 106), P(400, 250), 30 * s)
    capsule(d, P(282, 262), P(258, 440), 36 * s)  # the index finger, tip at the bottom
    capsule(d, P(392, 214), P(344, 322), 30 * s)  # the thumb
    block = grow(shrink(block, 8 * s), 8 * s)
    # The folded fingers: a row of stubs down the block's left edge, back to front.
    fingers = []
    for top, bottom in (((226, 132), (180, 214)), ((236, 186), (192, 268)), ((248, 240), (214, 316))):
        m, d = blank()
        capsule(d, P(*top), P(*bottom), 28 * s)
        fingers.append(m)
    union = block
    for m in fingers:
        union = ImageChops.lighter(union, m)
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    img.paste(INK, (0, 0), grow(union, 26 * s))  # the thick outline round it all
    layer(img, block, 0, 22 * s, 24 * s)
    # The thumb's crease and the index finger's knuckle line.
    d = ImageDraw.Draw(img)
    capsule(d, P(368, 232), P(334, 300), 4 * s, fill=INK)
    for m in fingers:
        layer(img, m, 7 * s, 12 * s, 14 * s)
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
    for name, make in (("hand.png", hand), ("mouse.png", mouse), ("floor_arrow.png", floor_arrow)):
        path = os.path.join(OUT, name)
        make().save(path)
        print("wrote", os.path.abspath(path))


if __name__ == "__main__":
    main()
