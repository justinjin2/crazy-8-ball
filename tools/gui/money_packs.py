#!/usr/bin/env python3
"""The Shop's Money tab pictures (pick B, 2026-10-08): the seven money packs, smallest to biggest.

    python3 tools/gui/money_packs.py SOURCE_DIR

SOURCE_DIR holds pack1.png .. pack7.png from tools/openai_image.py (1024 x 1024, transparent;
the prompts are in ~/Desktop/8ball-refs/gui-mocks-v4/build/money/gen.sh and gen2.sh: the cash
icon's style, packs 5-7 redone without coins, since money is green cash, never coins). Each
picture is trimmed to what it shows, set in a square with a clear border (so a glow or a pop
never cuts it), its almost-opaque pixels made opaque (the generator leaves the body at 253),
and shrunk in premultiplied alpha to OUT_PX into assets/ui/shop_money/. Pillow only.
"""

import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, 'assets', 'ui', 'shop_money')
OUT_PX = 512  # the hero card shows the biggest at about 220 px on a computer
BORDER = 0.04  # a clear border round the picture, a share of the square
SOLID = 248  # alpha at or above this becomes fully opaque


def bake(src, dst):
    im = Image.open(src).convert('RGBA')
    alpha = im.getchannel('A').point(lambda a: 255 if a >= SOLID else a)
    im.putalpha(alpha)
    box = alpha.getbbox()
    im = im.crop(box)
    side = max(im.size)
    inner = round(OUT_PX * (1 - 2 * BORDER))
    scale = inner / side
    size = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
    small = im.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')
    out = Image.new('RGBA', (OUT_PX, OUT_PX), (0, 0, 0, 0))
    out.alpha_composite(small, ((OUT_PX - size[0]) // 2, (OUT_PX - size[1]) // 2))
    out.save(dst, optimize=True)
    return size


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = sys.argv[1]
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in range(1, 8):
        dst = os.path.join(OUT_DIR, f'pack{n}.png')
        size = bake(os.path.join(source, f'pack{n}.png'), dst)
        print(f'{os.path.relpath(dst, ROOT)}: {OUT_PX} px, the picture {size[0]} x {size[1]}')


if __name__ == '__main__':
    main()
