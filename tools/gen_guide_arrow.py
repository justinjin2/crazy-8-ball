#!/usr/bin/env python3
"""Generate the guideline arrow tile (assets/ui/guide_arrow.png).

Roblox Beams run the image's VERTICAL axis along the ribbon (one tile per TextureLength) and
the horizontal axis across the ribbon's width. So the chevron points UP in the image, spans
the full width, and leaves clear space above and below so repeated tiles read as separate
arrows rather than a zigzag."""
import os
from PIL import Image, ImageDraw

SIZE = 128
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "guide_arrow.png")

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
t = 26  # stroke thickness (vertical)
left, right, mid = 6, SIZE - 6, SIZE // 2
tipY, wingY = 26, 74  # arrow tip near the top, wings lower
outer = [(left, wingY), (mid, tipY), (right, wingY), (right, wingY + t), (mid, tipY + t), (left, wingY + t)]
draw.polygon(outer, fill=(255, 255, 255, 255))
img.save(OUT)
print("wrote", os.path.abspath(OUT))
