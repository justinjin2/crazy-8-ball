#!/usr/bin/env python3
"""Draw the particle sprites for our own lucky blocks (designer, 2026-10-07: "create your own
unique extra particles"). White sprites are tinted by each emitter's Color; the mini 8-ball keeps
its own colours. tools/luckyblock_template.luau puts them on the blocks.

    python3 tools/luckyblock_sprites.py

Writes assets/luckyblocks/particles/<name>.png (128 x 128, transparent).
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "luckyblocks", "particles")
S = 128


def canvas():
    return Image.new("RGBA", (S * 4, S * 4), (0, 0, 0, 0))  # drawn 4x, then shrunk (smooth edges)


def done(img, name, blur=0):
    img = img.resize((S, S), Image.LANCZOS)
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    img.save(os.path.join(OUT, name + ".png"))


def feather():
    img = canvas()
    d = ImageDraw.Draw(img)
    c = S * 2
    d.ellipse([c - 70, 40, c + 70, S * 4 - 60], fill=(255, 255, 255, 255))
    for i in range(9):  # the barbs' notches
        y = 110 + i * 34
        d.line([(c, y), (c + 90, y - 40)], fill=(0, 0, 0, 0), width=8)
        d.line([(c, y), (c - 90, y - 40)], fill=(0, 0, 0, 0), width=8)
    d.line([(c, 50), (c, S * 4 - 20)], fill=(235, 235, 240, 255), width=10)
    done(img, "feather")


def puff():
    img = canvas()
    d = ImageDraw.Draw(img)
    for x, y, r in [(256, 290, 120), (170, 300, 90), (345, 305, 95), (220, 220, 95), (305, 225, 90)]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255))
    done(img, "puff", 2)


def ember():
    img = canvas()
    d = ImageDraw.Draw(img)
    for r, a in [(240, 30), (170, 80), (110, 170), (60, 255)]:
        d.ellipse([256 - r, 256 - r, 256 + r, 256 + r], fill=(255, 255, 255, a))
    done(img, "ember", 3)


def confetti():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([150, 60, 362, 452], radius=40, fill=(255, 255, 255, 255))
    done(img, "confetti")


def bubble():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([40, 40, 472, 472], outline=(255, 255, 255, 255), width=34)
    d.ellipse([60, 60, 452, 452], fill=(255, 255, 255, 50))
    d.ellipse([140, 120, 230, 190], fill=(255, 255, 255, 230))  # the shine
    done(img, "bubble")


def leaf():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([140, 40, 372, 470], fill=(255, 255, 255, 255))
    d.line([(256, 70), (256, 480)], fill=(225, 225, 225, 255), width=12)
    done(img, "leaf")


def spark():
    """A small zigzag bolt."""
    img = canvas()
    d = ImageDraw.Draw(img)
    pts = [(300, 20), (170, 240), (260, 250), (190, 492), (360, 210), (265, 200), (340, 20)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    done(img, "spark")


def ball8():
    """A mini 8-ball: glossy black, a white circle with an 8."""
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse([20, 20, 492, 492], fill=(18, 18, 22, 255))
    d.ellipse([150, 120, 362, 332], fill=(250, 250, 252, 255))
    try:
        f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Black.ttf", 170)
    except OSError:
        f = ImageFont.load_default()
    d.text((256, 232), "8", font=f, fill=(18, 18, 22, 255), anchor="mm")
    d.ellipse([90, 70, 170, 130], fill=(255, 255, 255, 110))  # the shine
    done(img, "ball8")


def main():
    os.makedirs(OUT, exist_ok=True)
    for make in (feather, puff, ember, confetti, bubble, leaf, spark, ball8):
        make()
    print("luckyblock_sprites:", ", ".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
