"""Side-by-side images for the verification loop (brief section 8): the concept art on the left,
the Studio capture on the right, the capture centre-cropped to the reference's aspect and both
scaled to the same height.

    python3 assets/map/gen_compare.py <stage> <view> <capture.jpg> [<view> <capture.jpg> ...]

The view names and their reference images are map_layout.cameras (Spec section 5). Writes
assets/map/checkpoints/<stage>-<view>.jpg (git-ignored) and prints each path.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_layout as ml  # noqa: E402

HEIGHT = 540  # pixels, each half
GAP = 12


def font(size):
    for name in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Helvetica.ttc'):
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def crop_to(img, aspect):
    w, h = img.size
    if w / h > aspect:
        nw = round(h * aspect)
        x0 = (w - nw) // 2
        return img.crop((x0, 0, x0 + nw, h))
    nh = round(w / aspect)
    y0 = (h - nh) // 2
    return img.crop((0, y0, w, y0 + nh))


def pair(stage, view, capture_path):
    cams = ml.build()['cameras']
    cam = cams[view]
    shot = Image.open(capture_path).convert('RGB')
    if cam['ref']:
        ref = Image.open(os.path.join(HERE, 'reference', cam['ref'])).convert('RGB')
        aspect = ref.width / ref.height
    else:
        ref = None
        aspect = cam.get('aspect', shot.width / shot.height)
    shot = crop_to(shot, aspect)
    width = round(HEIGHT * aspect)
    shot = shot.resize((width, HEIGHT), Image.LANCZOS)
    panes = [shot] if ref is None else [ref.resize((width, HEIGHT), Image.LANCZOS), shot]
    out = Image.new('RGB', (sum(p.width for p in panes) + GAP * (len(panes) - 1), HEIGHT + 28), (255, 255, 255))
    x = 0
    d = ImageDraw.Draw(out)
    labels = ['GAME'] if ref is None else ['ART: ' + cam['ref'], 'GAME (stage %s)' % stage]
    for pane, label in zip(panes, labels):
        out.paste(pane, (x, 28))
        d.text((x + 6, 6), label, fill=(20, 20, 20), font=font(16))
        x += pane.width + GAP
    os.makedirs(os.path.join(HERE, 'checkpoints'), exist_ok=True)
    path = os.path.join(HERE, 'checkpoints', '%s-%s.jpg' % (stage, view))
    out.save(path, quality=90)
    return path


if __name__ == '__main__':
    args = sys.argv[1:]
    if len(args) < 3 or len(args) % 2 != 1:
        raise SystemExit(__doc__)
    stage = args[0]
    for view, capture in zip(args[1::2], args[2::2]):
        print(pair(stage, view, capture))
