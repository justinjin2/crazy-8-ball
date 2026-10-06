"""Textures for the gate 1 motion spike (SHOP_LIVELY_PROMPT section 7.1).

- pattern_2x2.png: the header's soft 8-ball tile (assets/ui/art/pattern.png, 512 px) repeated
  2 x 2 into 1024 px, so a window of up to 512 texels can slide one whole period and wrap.
- float_ball.png: a crisp ink-outlined 8-ball, 224 px inside a 256 px image (16 px of clear
  border), so a label can show it shifted by a fraction of a pixel with ImageRectOffset.

Run: tools/gui/.venv/bin/python tools/gui/spike_art.py <out_dir>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
INK = (27, 32, 51, 255)


def pattern_2x2(out: Path) -> None:
    tile = Image.open(ROOT / "assets/ui/art/pattern.png").convert("RGBA")
    size = tile.width
    sheet = Image.new("RGBA", (size * 2, size * 2))
    for x in (0, size):
        for y in (0, size):
            sheet.paste(tile, (x, y))
    sheet.save(out / "pattern_2x2.png")


def float_ball(out: Path) -> None:
    scale = 4  # drawn big, then shrunk, for clean edges
    s = 256 * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 16 * scale
    d.ellipse((pad, pad, s - pad, s - pad), fill=INK)
    ring = 10 * scale
    d.ellipse((pad + ring, pad + ring, s - pad - ring, s - pad - ring), fill=(40, 44, 60, 255))
    c = s / 2
    r = 52 * scale
    d.ellipse((c - r, c - r - 10 * scale, c + r, c + r - 10 * scale), fill=(255, 255, 255, 255))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 80 * scale)
    except OSError:
        font = ImageFont.load_default()
    d.text((c, c - 10 * scale), "8", fill=INK, font=font, anchor="mm")
    d.ellipse((c - 70 * scale, pad + 30 * scale, c - 20 * scale, pad + 60 * scale), fill=(255, 255, 255, 140))
    img.resize((256, 256), Image.LANCZOS).save(out / "float_ball.png")


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "tools/gui/out/spike")
    target.mkdir(parents=True, exist_ok=True)
    pattern_2x2(target)
    float_ball(target)
    print("wrote", target)
