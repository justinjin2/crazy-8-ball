#!/usr/bin/env python3
"""Guideline images (assets/ui/):
  guide_dash.png   one white dash with a gap, tiled along a thin ribbon and scrolled so the
                   line visibly flows towards the target (image vertical axis = along the line)
  guide_ring.png   white circle outline on transparent: the contact ("ghost") ball marker
  guide_arrow.png  kept for reference (older chevron style)
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
os.makedirs(OUT, exist_ok=True)

# Dash tile: 32 wide x 128 tall. Dash occupies the middle 60% of the height, full width.
w, h = 32, 128
img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rectangle((0, 26, w, 102), fill=(255, 255, 255, 255))
img.save(os.path.join(OUT, "guide_dash.png"))

# Ring: 256x256, stroke ~9% of the diameter, anti-aliased by supersampling.
s = 1024
big = Image.new("RGBA", (s, s), (0, 0, 0, 0))
bd = ImageDraw.Draw(big)
stroke = int(s * 0.075)
pad = 8
bd.ellipse((pad, pad, s - pad, s - pad), outline=(255, 255, 255, 255), width=stroke)
big.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, "guide_ring.png"))
print("wrote guide_dash.png and guide_ring.png")
