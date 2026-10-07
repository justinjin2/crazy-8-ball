"""The table's logo plate with the game's logo on it (designer, 2026-10-06).

Builds the plain plate exactly as TableTextures.build_logo does (satin black, nickel
pinstripe), then lays assets/ui/logo/Crazy8Logo.png in the middle of it, inside the pinstripe,
and writes textures/LogoPlate_Color.png (the 1024 upload) and its 4096 master.

The plate is 9 x 3 in but its colour map is a square, so the map is three times finer across
the plate's height than along it: the logo is squeezed to match here and comes out in its own
proportions on the table. Run it after TableTextures.py (which writes the plain plate):

    python3 assets/table/LogoPlate.py

Needs numpy and Pillow (Pillow only to read and resample the logo).
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import TableTextures as TT  # noqa: E402

LOGO = os.path.join(HERE, '..', 'ui', 'logo', 'Crazy8Logo.png')
PLATE_W_IN, PLATE_H_IN = 9.0, 3.0
# The logo's height on the plate, inches: inside the pinstripe (inset 0.28 in) with a little
# room above and below it. Its width follows from the logo's own proportions. (tune)
LOGO_HEIGHT_IN = 2.2


def main():
    plate = TT.build_logo({})['LogoPlate_Color']  # (N, N, 3) sRGB 0..1
    n = plate.shape[0]
    logo = Image.open(LOGO).convert('RGBA')
    aspect = logo.width / logo.height
    height_in = LOGO_HEIGHT_IN
    width_in = height_in * aspect
    inner_w = PLATE_W_IN - 2 * TT.CFG['logo_line_inset'] - 0.2
    if width_in > inner_w:
        width_in, height_in = inner_w, inner_w / aspect
    w_px = int(round(width_in / PLATE_W_IN * n))
    h_px = int(round(height_in / PLATE_H_IN * n))
    art = np.asarray(logo.resize((w_px, h_px), Image.LANCZOS), dtype=np.float64) / 255.0
    rgb, alpha = art[..., :3], art[..., 3:4]
    top, left = (n - h_px) // 2, (n - w_px) // 2
    region = plate[top:top + h_px, left:left + w_px]
    plate[top:top + h_px, left:left + w_px] = rgb * alpha + region * (1 - alpha)
    os.makedirs(TT.MASTER_DIR, exist_ok=True)
    TT.write_png(os.path.join(TT.MASTER_DIR, 'LogoPlate_Color.png'), plate)
    small = TT.box_down(plate, n // TT.UP)
    out = os.path.join(TT.TEX_DIR, 'LogoPlate_Color.png')
    TT.write_png(out, small)
    print('logo %.2f x %.2f in on the %g x %g in plate -> %s' % (width_in, height_in, PLATE_W_IN, PLATE_H_IN, out))


if __name__ == '__main__':
    main()
