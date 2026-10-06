"""Pack and preview the card cues that tools/gui/render_cues.py rendered.

    tools/gui/.venv/bin/python tools/gui/cue_sheets.py [--dir ~/Desktop/8ball-refs/gui-lively/work/renders]

Reads <dir>/firework_cue.png, beta_cue.png, firework_ribbons[_loose]/frame_NN.png, layout.json. Writes into <dir>:
    sheets/<set>_<variant>_<k>.png + .json   sprite sheets (at most 1024 x 1024) of the ribbon
                                                  loop; the JSON has columns, rows, frame size, frame
                                                  count, fps and where the frame sits on the cue canvas
    preview/<set>_loop.mp4                        the sheet frames over firework_cue.png on navy, looping
    preview/<name>_backgrounds.png                each render on navy, black, white and a checkerboard

Frames are cropped to the ribbons' union box over the whole loop (so every frame overlays the cue
picture at the same place), resized in premultiplied alpha (no dark fringes), then packed.
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

NAVY = (20, 24, 50)
# Sheet variants: (name, the widest frame px, take every n-th frame). 512 wide keeps the ribbons crisp at
# about 650 px on screen (13b's box) with a little upscale; at most 1024 x 1024 per sheet.
VARIANTS = [('32f_512', 512, 1), ('16f_512', 512, 2)]
MAX_FRAME_H = 128         # px: 2 x 8 frames fit one 1024 sheet
FPS_PER_TURN = 2.4        # seconds for one full turn of the ribbons on the card (in game: 7.2 s)
PAD = 4                   # px of clear border kept round the ribbons' union box (canvas px)
PREVIEW_W = 1120          # the preview's width (half the canvas)
PREVIEW_LOOPS = 4


def load(path):
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.float64) / 255.0


def save(path, rgba):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(np.round(np.clip(rgba, 0, 1) * 255).astype(np.uint8), 'RGBA').save(path, optimize=True)


def resize_premult(rgba, size):
    """Straight RGBA -> resized straight RGBA, filtered in premultiplied space (Lanczos)."""
    a = rgba[..., 3:4]
    pre = np.concatenate([rgba[..., :3] * a, a], 2)
    out = np.stack([np.asarray(Image.fromarray(pre[..., c].astype(np.float32), 'F').resize(size, Image.LANCZOS))
                    for c in range(4)], 2).astype(np.float64)
    out = np.clip(out, 0, 1)
    al = out[..., 3:4]
    rgb = np.where(al > 1e-4, np.clip(out[..., :3] / np.maximum(al, 1e-4), 0, 1), 0)
    return np.concatenate([rgb, al], 2)


def over(dst_rgb, src):
    a = src[..., 3:4]
    return src[..., :3] * a + dst_rgb * (1 - a)


def checker(h, w, cell=16):
    yy, xx = np.mgrid[0:h, 0:w]
    c = ((yy // cell + xx // cell) % 2).astype(np.float64)
    v = 0.62 + 0.2 * c
    return np.repeat(v[..., None], 3, 2)


def union_box(frames):
    alpha = np.max(np.stack([f[..., 3] for f in frames]), 0)
    ys, xs = np.nonzero(alpha > 3 / 255)
    h, w = alpha.shape
    x0, x1 = max(0, xs.min() - PAD), min(w, xs.max() + 1 + PAD)
    y0, y1 = max(0, ys.min() - PAD), min(h, ys.max() + 1 + PAD)
    return int(x0), int(y0), int(x1 - x0), int(y1 - y0)


def pack(frames, box, out_dir, set_name, name, width, step, layout):
    x, y, bw, bh = box
    picked = frames[::step]
    width = min(width, int(MAX_FRAME_H * bw / bh))   # keep 8 rows of 2 per 1024 sheet
    fh = int(round(bh * width / bw))
    small = [resize_premult(f[y:y + bh, x:x + bw], (width, fh)) for f in picked]
    cols = max(1, 1024 // width)
    rows_max = max(1, 1024 // fh)
    per = cols * rows_max
    n = len(small)
    sheets = int(math.ceil(n / per))
    per = int(math.ceil(n / sheets / cols)) * cols   # balance the sheets (32 -> 16 + 16)
    fps = n / FPS_PER_TURN
    written = []
    for k in range(sheets):
        chunk = small[k * per:(k + 1) * per]
        rows = int(math.ceil(len(chunk) / cols))
        sheet = np.zeros((rows * fh, cols * width, 4))
        for i, fr in enumerate(chunk):
            r, c = divmod(i, cols)
            sheet[r * fh:(r + 1) * fh, c * width:(c + 1) * width] = fr
        base = '%s_%s_%d' % (set_name, name, k + 1)
        save(os.path.join(out_dir, base + '.png'), sheet)
        meta = {
            'image': base + '.png', 'columns': cols, 'rows': rows, 'frame_width': width,
            'frame_height': fh, 'frame_count': len(chunk), 'first_frame': k * per,
            'total_frames': n, 'sheets': sheets, 'fps': round(fps, 3), 'loop': True,
            'order': 'left to right, then top to bottom; the frame after the last is the first',
            'canvas': layout.get('canvas'), 'crop_in_canvas': [x, y, bw, bh],
            'scale_from_canvas': round(width / bw, 6),
            'overlay': 'place the frame over firework_cue.png at crop_in_canvas (firework_cue.png is the whole canvas)',
            'seconds_per_turn': FPS_PER_TURN, 'game_seconds_per_turn': layout.get('ribbons', {}).get('game_period_s'),
        }
        with open(os.path.join(out_dir, base + '.json'), 'w') as fh_:
            json.dump(meta, fh_, indent=2)
            fh_.write('\n')
        written.append((base, meta))
        print('CARD sheet', base, '%dx%d' % (sheet.shape[1], sheet.shape[0]), meta['columns'], 'x', meta['rows'],
              'frames', meta['frame_width'], 'x', meta['frame_height'])
    return written, small


def backgrounds(rgba, path):
    """The render on navy, black, white and a checkerboard, stacked, at half size."""
    h, w = rgba.shape[:2]
    half = resize_premult(rgba, (w // 2, h // 2))
    hh, ww = half.shape[:2]
    rows = []
    for bg in (np.full((hh, ww, 3), np.array(NAVY) / 255.0), np.zeros((hh, ww, 3)), np.ones((hh, ww, 3)),
               checker(hh, ww)):
        rows.append(over(bg, half))
    img = np.concatenate([np.concatenate([r, np.full((6, ww, 3), 0.5)], 0) for r in rows], 0)[:-6]
    Image.fromarray(np.round(img * 255).astype(np.uint8)).save(path, optimize=True)
    print('CARD wrote', path)


def preview_mp4(cue, small, box, fps, path):
    """Each sheet frame scaled back to the canvas and laid over the cue, on navy; loops."""
    x, y, bw, bh = box
    h, w = cue.shape[:2]
    scale = PREVIEW_W / w
    ph = int(round(h * scale / 2)) * 2
    base = over(np.full((h, w, 3), np.array(NAVY) / 255.0), cue)
    tmp = tempfile.mkdtemp(prefix='ribbons_mp4_')
    try:
        for i, fr in enumerate(small):
            big = resize_premult(fr, (bw, bh))
            img = base.copy()
            img[y:y + bh, x:x + bw] = over(img[y:y + bh, x:x + bw], big)
            Image.fromarray(np.round(img * 255).astype(np.uint8)).resize((PREVIEW_W, ph), Image.LANCZOS).save(
                os.path.join(tmp, 'f_%03d.png' % i))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-stream_loop', str(PREVIEW_LOOPS - 1),
                        '-framerate', '%.4f' % fps, '-i', os.path.join(tmp, 'f_%03d.png'),
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', '-r', '30', path], check=True)
        print('CARD wrote', path)
    finally:
        shutil.rmtree(tmp)


def main():
    args = sys.argv[1:]
    d = os.path.expanduser(args[args.index('--dir') + 1] if '--dir' in args else
                           '~/Desktop/8ball-refs/gui-lively/work/renders')
    layout = json.load(open(os.path.join(d, 'layout.json')))
    cue = load(os.path.join(d, 'firework_cue.png'))
    for set_name in ('firework_ribbons', 'firework_ribbons_loose'):
        fdir = os.path.join(d, set_name)
        if not os.path.isdir(fdir):
            continue
        names = sorted(n for n in os.listdir(fdir) if n.startswith('frame_') and n.endswith('.png'))
        frames = [load(os.path.join(fdir, n)) for n in names]
        box = union_box(frames)
        print('CARD', set_name, len(frames), 'frames, union box', box)
        first = None
        for name, width, step in VARIANTS:
            written, small = pack(frames, box, os.path.join(d, 'sheets'), set_name, name, width, step, layout)
            if first is None:
                first = (small, written[0][1]['fps'])
        preview_mp4(cue, first[0], box, first[1], os.path.join(d, 'preview', set_name + '_loop.mp4'))
        backgrounds(frames[0], os.path.join(d, 'preview', set_name + '_frame00_backgrounds.png'))
        both = cue.copy()
        a = frames[0][..., 3:4]
        rgb = frames[0][..., :3] * a + both[..., :3] * both[..., 3:4] * (1 - a)
        al = a + both[..., 3:4] * (1 - a)
        backgrounds(np.concatenate([np.where(al > 1e-4, rgb / np.maximum(al, 1e-4), 0), al], 2),
                    os.path.join(d, 'preview', 'firework_cue_with_%s_backgrounds.png' % set_name))
    for name in ('firework_cue', 'beta_cue', 'firework_cue_mask', 'beta_cue_mask'):
        backgrounds(load(os.path.join(d, name + '.png')), os.path.join(d, 'preview', name + '_backgrounds.png'))


if __name__ == '__main__':
    main()
