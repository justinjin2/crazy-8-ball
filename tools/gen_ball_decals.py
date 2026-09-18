#!/usr/bin/env python3
"""Generate the ball decal images (needs Pillow, which ships with this Mac's Python).

Outputs to assets/balls/:
  number_1.png .. number_15.png  white disc with the number, transparent elsewhere.
                                 Used on the Front and Back faces of every numbered ball.
  stripe_band.png                white horizontal band on transparent. Used on the four
                                 side faces of stripes, tinted per ball via Decal.Color3.
Upload them to Roblox (Studio, or the MCP upload tool) and paste the ids into
Config.Balls.Decals.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "balls")

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    print("warning: no bold system font found, using Pillow default", file=sys.stderr)
    return ImageFont.load_default()


def number_decal(n):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # White disc a bit larger than the real thing so it stays readable once projected
    # onto the sphere (the projection shrinks the middle relative to the edges).
    radius = int(SIZE * 0.30)
    c = SIZE // 2
    draw.ellipse((c - radius, c - radius, c + radius, c + radius), fill=(255, 255, 255, 255))
    font = load_font(int(radius * (1.35 if n < 10 else 1.15)))
    text = str(n)
    bbox = draw.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((c - w / 2 - bbox[0], c - h / 2 - bbox[1]), text, font=font, fill=(20, 20, 20, 255))
    return img


def stripe_band():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Band covers the middle 52% of the face; poles stay white (the part colour).
    half = int(SIZE * 0.26)
    c = SIZE // 2
    draw.rectangle((0, c - half, SIZE, c + half), fill=(255, 255, 255, 255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for n in range(1, 16):
        number_decal(n).save(os.path.join(OUT, f"number_{n}.png"))
    stripe_band().save(os.path.join(OUT, "stripe_band.png"))
    print(f"wrote 16 images to {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()
