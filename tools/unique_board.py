#!/usr/bin/env python3
"""A concept board for a Unique cue laid out like the designer's references (2026-10-04): the
title, the full cue, the handle close-up, the cue with its aura from a three-quarter view, the
ball trail and the pocket finisher, all rendered from our own work (the CuePreview stills and
clip frames).

    python3 tools/unique_board.py <skin id> [<skin id> ...]
        -> assets/cue/concepts/unique/<id>-board.png

Needs renders/skins/<id>/stills/ (tools/cue_skin.py <id> --stills) and renders/skins/<id>/frames/
(--clip; the frames the clip was encoded from). The trail and pocket frames are picked from the
clip's shot and pocket segments (CuePreview.PREVIEW's segment lengths).
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CUE = os.path.join(ROOT, 'assets', 'cue')
sys.path.insert(0, CUE)
import CuePreview  # noqa: E402

OUT = os.path.join(CUE, 'concepts', 'unique')
BG = (16, 18, 23)
W, H = 2000, 667


def font(size, bold=False):
    for name in (['/System/Library/Fonts/HelveticaNeue.ttc', '/System/Library/Fonts/Helvetica.ttc'] if not bold
                 else ['/System/Library/Fonts/HelveticaNeue.ttc', '/System/Library/Fonts/Helvetica.ttc']):
        try:
            return ImageFont.truetype(name, size, index=1 if bold else 0)
        except Exception:
            continue
    return ImageFont.load_default()


def fit(im, w, h):
    """Scale to cover w x h, then centre-crop."""
    s = max(w / im.width, h / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def frame_index(seg_name, seconds_in):
    """The clip frame at `seconds_in` into segment seg_name (turn, back, shot, pocket)."""
    segs = CuePreview.PREVIEW['segments']
    fps = CuePreview.PREVIEW['fps']
    start = 0.0
    for name in ('turn', 'back', 'shot', 'pocket'):
        if name == seg_name:
            return int(round((start + seconds_in) * fps))
        start += segs[name]
    raise KeyError(seg_name)


def board(skin_id):
    skin = json.load(open(os.path.join(CUE, 'skins', skin_id + '.json')))
    rdir = CuePreview.skin_dir(skin_id)
    stills = os.path.join(rdir, 'stills')
    frames = os.path.join(rdir, 'frames')

    def still(name):
        p = os.path.join(stills, name + '.png')
        return Image.open(p).convert('RGB') if os.path.isfile(p) else None

    def frame(seg, t):
        p = os.path.join(frames, '%05d.png' % frame_index(seg, t))
        return Image.open(p).convert('RGB') if os.path.isfile(p) else None

    canvas = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(canvas)
    # title
    d.rectangle([42, 22, 45, 62], fill=(200, 200, 210))
    d.text((60, 18), skin['name'].upper(), fill=(240, 240, 245), font=font(40, True))
    d.text((62, 64), 'UNIQUE CUE  /  CONCEPT BOARD FROM OUR RENDERS (BLENDER, THE SKIN FILE, THE PIECE, THE VFX DATA)', fill=(150, 155, 170), font=font(16))
    d.text((1160, 30), 'RENDERED, NOT PAINTED', fill=(120, 125, 140), font=font(16))
    # the divider
    d.line([(1385, 0), (1385, H)], fill=(45, 48, 58), width=2)
    # left: full cue, handle close-up
    full = still('full')
    if full:
        canvas.paste(fit(full, 1310, 150), (40, 110))
    d.text((44, 264), 'FULL CUE (RENDER)', fill=(150, 155, 170), font=font(16))
    row = [still('joint'), still('forearm'), still('butt')]
    x = 42
    widths = [330, 520, 460]
    for img, w in zip(row, widths):
        if img:
            canvas.paste(fit(img, w, 215), (x, 300))
        x += w + 4
    d.rectangle([40, 298, 1356, 517], outline=(60, 64, 75), width=2)
    d.text((44, 530), 'HANDLE CLOSE-UP: JOINT, FOREARM, BUTT (RENDERS)', fill=(150, 155, 170), font=font(16))
    note = skin.get('note', '')
    # the note, wrapped
    words, lines, cur = note.split(), [], ''
    for wd in words:
        if d.textlength(cur + ' ' + wd, font=font(14)) > 1300:
            lines.append(cur)
            cur = wd
        else:
            cur = (cur + ' ' + wd).strip()
    lines.append(cur)
    for i, ln in enumerate(lines[:5]):
        d.text((44, 560 + i * 19), ln, fill=(120, 125, 140), font=font(14))
    # right: aura three-quarter, trail, pocket
    aura = still('aura') or still('threeq')
    if aura:
        canvas.paste(fit(aura, 590, 350), (1405, 10))
    d.text((1410, 364), 'CUE WITH AURA, 3/4 VIEW (RENDER)', fill=(150, 155, 170), font=font(14))
    trail = frame('shot', 2.0)
    if trail:
        canvas.paste(fit(trail, 285, 215), (1410, 385))
    d.rectangle([1408, 383, 1696, 601], outline=(60, 64, 75), width=2)
    d.text((1410, 608), 'BALL TRAIL (CLIP FRAME)', fill=(150, 155, 170), font=font(14))
    pocket = frame('pocket', 1.0)
    if pocket:
        canvas.paste(fit(pocket, 285, 215), (1712, 385))
    d.rectangle([1710, 383, 1998, 601], outline=(60, 64, 75), width=2)
    d.text((1712, 608), 'POCKET FINISHER (CLIP FRAME)', fill=(150, 155, 170), font=font(14))
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, '%s-board.png' % skin_id)
    canvas.save(out, optimize=True)
    print('wrote', os.path.relpath(out, ROOT))
    return out


def main():
    for skin_id in sys.argv[1:]:
        board(skin_id)


if __name__ == '__main__':
    main()
