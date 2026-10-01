"""The paint kit's images (brief 4.2), drawn from the panels in Parameters.json.

    python3 assets/cue/CueTemplate.py            template/<panel>_{input,guide,test}.png
    python3 assets/cue/CueTemplate.py --sheet    template/sheet.png (needs renders/areas.png from
                                                 CueTextures.py -- --areas)

Plain Python 3 with Pillow (Blender's Python has no Pillow; this script needs no Blender).
Every panel: left is toward the tip, right toward the butt; top to bottom is once round the cue
from the seam underneath, through the top of the cue (the middle row), back to the seam, so the
top and bottom edges join. cap_end is the butt's flat end seen from behind, top up.

  _input: what goes to ChatGPT. Flat mid-grey, thin dark zone lines, a 1 px border. No text.
  _guide: for the designer. The same with the zone names, directions and sizes.
  _test:  a numbered checker with TIP / BUTT / UP marks, to prove the mapping (skins/_test.json).
"""

import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cue_common as cc  # noqa: E402

TEMPLATE = os.path.join(HERE, 'template')
FONT_PATHS = ['/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
              '/System/Library/Fonts/Supplemental/Arial.ttf']
STYLE = {
    'grey': (128, 128, 128),  # the input fill: flat mid-grey
    'line': (48, 48, 48),  # zone lines and the border
    'line_px': 3,
    'label': (20, 20, 24),
    'note': (45, 45, 55),
    'cell_px': 64,  # the test checker's cell
}


def font(size):
    for path in FONT_PATHS:
        if os.path.isfile(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def base(panel):
    """The input image: grey, zone lines, a 1 px border (and the disc outline for cap_end)."""
    w, h = panel['size_px']
    img = Image.new('RGB', (w, h), STYLE['grey'])
    draw = ImageDraw.Draw(img)
    for line in panel['lines']:
        x = round(line['x'] * w)
        draw.rectangle([x - STYLE['line_px'] // 2, 0, x + STYLE['line_px'] // 2, h - 1], fill=STYLE['line'])
    if panel['name'] == 'cap_end':
        c, r = w / 2, panel['disc_radius_px']
        draw.ellipse([c - r, c - r, c + r, c + r], outline=STYLE['line'], width=STYLE['line_px'])
    draw.rectangle([0, 0, w - 1, h - 1], outline=STYLE['line'], width=1)
    return img


def text(draw, xy, s, size, fill=None, anchor='mm'):
    draw.text(xy, s, font=font(size), fill=fill or STYLE['label'], anchor=anchor)


def vertical(img, centre, s, size):
    """Text reading bottom to top, centred on `centre`."""
    f = font(size)
    box = f.getbbox(s)
    label = Image.new('RGBA', (box[2] - box[0] + 8, box[3] - box[1] + 8), (0, 0, 0, 0))
    ImageDraw.Draw(label).text((4 - box[0], 4 - box[1]), s, font=f, fill=STYLE['label'])
    label = label.rotate(90, expand=True)
    img.paste(label, (round(centre[0] - label.width / 2), round(centre[1] - label.height / 2)), label)


def arrow(draw, x0, y0, x1, y1, fill, width=6):
    draw.line([x0, y0, x1, y1], fill=fill, width=width)
    a = math.atan2(y1 - y0, x1 - x0)
    head = 3.2 * width
    for side in (-1, 1):
        draw.line([x1, y1, x1 - head * math.cos(a + side * 0.5), y1 - head * math.sin(a + side * 0.5)],
                  fill=fill, width=width)


def zone_names(panel):
    names = {
        'shaft_tile': ['shaft (repeats)'],
        'shaft_top': ['top of the shaft'],
        'forearm': ['joint collar', 'joint collar', 'forearm'],
        'butt': ['ring', 'wrap', 'sleeve', 'end'],
    }
    return names.get(panel['name'], [])


def guide(panel):
    img = base(panel)
    draw = ImageDraw.Draw(img)
    w, h = panel['size_px']
    if panel['name'] == 'cap_end':
        text(draw, (w / 2, 40), 'the flat end of the butt', 26)
        text(draw, (w / 2, 72), 'seen from behind, the top of the cue up', 18, STYLE['note'])
        arrow(draw, w / 2, h / 2 + 40, w / 2, h / 2 - 60, STYLE['label'], 4)
        text(draw, (w / 2, h / 2 + 64), 'up', 20)
        text(draw, (w / 2, h - 60), 'paint inside the circle', 18, STYLE['note'])
        text(draw, (w / 2, h - 34), '%.3f studs across' % (2 * panel['face_radius_studs']), 18, STYLE['note'])
        return img
    cuts = [0.0] + [line['x'] for line in panel['lines']] + [1.0]
    names = zone_names(panel)
    for i in range(len(cuts) - 1):
        if i < len(names) and names[i]:
            span = (cuts[i + 1] - cuts[i]) * w
            centre = ((cuts[i] + cuts[i + 1]) / 2 * w, h * 0.42)
            if span > 200:
                text(draw, centre, names[i], 26)
            else:  # a narrow zone: the name runs up the zone
                vertical(img, centre, names[i], 18)
    text(draw, (14, h * 0.82), 'tip ←', 22, anchor='lm')
    text(draw, (w - 14, h * 0.82), '→ butt', 22, anchor='rm')
    text(draw, (w / 2, 20), 'top and bottom edges join (the underside of the cue)', 18, STYLE['note'])
    text(draw, (w / 2, h - 20), 'top and bottom edges join (the underside of the cue)', 18, STYLE['note'])
    text(draw, (w / 2, h * 0.56), 'the middle row is the top of the cue in your hands', 18, STYLE['note'])
    c0, c1 = panel['circumference_studs']
    size = '%s: %d x %d px, %.2f studs long, %.2f to %.2f studs round' % (
        panel['name'], w, h, panel['length_studs'], c0, c1)
    if panel['name'] == 'shaft_tile':
        size = 'shaft_tile: %d x %d px, repeats about %d times up the shaft, seamless on all four edges' % (
            w, h, panel['default_repeats'])
    text(draw, (w / 2, h * 0.66), size, 18, STYLE['note'])
    if panel['name'] == 'shaft_top':
        text(draw, (w - 14, h * 0.75), 'meets the joint →', 18, STYLE['note'], anchor='rm')
    return img


def test(panel):
    """A checker in the panel's area colour, every cell named (row letter, column number), with
    TIP / BUTT / UP marks: a mirrored, flipped or stretched mapping shows at a glance."""
    w, h = panel['size_px']
    colour = tuple(cc.AREA_COLOURS[panel['name']])
    light = tuple(int(c + (255 - c) * 0.72) for c in colour)
    img = Image.new('RGB', (w, h), light)
    draw = ImageDraw.Draw(img)
    cell = STYLE['cell_px']
    cols, rows = (w + cell - 1) // cell, (h + cell - 1) // cell
    for j in range(rows):
        for i in range(cols):
            if (i + j) % 2 == 0:
                draw.rectangle([i * cell, j * cell, (i + 1) * cell - 1, (j + 1) * cell - 1], fill=colour)
            label = '%s%d' % (chr(ord('A') + j % 26), i + 1)
            fill = (255, 255, 255) if (i + j) % 2 == 0 else (30, 30, 30)
            text(draw, (i * cell + cell / 2, j * cell + cell / 2), label, 18, fill)
    mark = (0, 0, 0)
    if panel['name'] == 'cap_end':
        c, r = w / 2, panel['disc_radius_px']
        draw.ellipse([c - r, c - r, c + r, c + r], outline=mark, width=4)
        arrow(draw, c, c + 60, c, c - 110, (220, 20, 20), 10)
        text(draw, (c, c + 90), 'UP', 40, (220, 20, 20))
        text(draw, (c + 120, c), 'R', 40, mark)
        return img
    band = [0, h * 0.5 - 34, w, h * 0.5 + 34]
    draw.rectangle(band, fill=(255, 255, 255))
    text(draw, (20, h * 0.5), '← TIP', 40, (0, 0, 0), anchor='lm')
    text(draw, (w - 20, h * 0.5), 'BUTT →', 40, (0, 0, 0), anchor='rm')
    text(draw, (w / 2, h * 0.5), panel['name'].upper(), 40, colour)
    for x in (w * 0.3, w * 0.7):
        arrow(draw, x, h * 0.5 - 40, x, h * 0.5 - 150, (220, 20, 20), 10)
        text(draw, (x + 44, h * 0.5 - 110), 'UP', 34, (220, 20, 20))
    # the seam rows: the top and bottom edges, which must meet on the underside
    draw.rectangle([0, 0, w - 1, 5], fill=(250, 220, 0))
    draw.rectangle([0, h - 6, w - 1, h - 1], fill=(250, 220, 0))
    return img


def write(img, path):
    img.save(path, 'PNG', optimize=False)
    print('CUE template wrote', os.path.relpath(path, HERE))


def panels():
    with open(cc.PARAMETERS_PATH) as handle:
        return json.load(handle)['panels']


def make_panels():
    os.makedirs(TEMPLATE, exist_ok=True)
    for panel in panels():
        name = panel['name']
        write(base(panel), os.path.join(TEMPLATE, name + '_input.png'))
        write(guide(panel), os.path.join(TEMPLATE, name + '_guide.png'))
        write(test(panel), os.path.join(TEMPLATE, name + '_test.png'))


def make_sheet():
    areas_path = os.path.join(HERE, 'renders', 'areas.png')
    if not os.path.isfile(areas_path):
        sys.exit('CUE template FAIL: run CueTextures.py -- --areas first (renders/areas.png)')
    areas = Image.open(areas_path).convert('RGB')
    width = 1800
    areas = areas.resize((width, round(areas.height * width / areas.width)), Image.LANCZOS)
    items = []
    for panel in panels():
        g = Image.open(os.path.join(TEMPLATE, panel['name'] + '_guide.png')).convert('RGB')
        scale = min(1.0, 1500 / g.width, 300 / g.height)
        items.append((panel, g.resize((round(g.width * scale), round(g.height * scale)), Image.LANCZOS)))
    pad = 24
    height = 90 + areas.height + pad + sum(im.height + pad + 36 for _, im in items)
    sheet = Image.new('RGB', (width + 2 * pad, height), (246, 246, 248))
    draw = ImageDraw.Draw(sheet)
    text(draw, (pad, 40), 'Cue paint kit: every panel and where it goes on the cue', 34, anchor='lm')
    text(draw, (pad, 74), 'Colours on the cue match the bar beside each panel. Grey: tip; white: '
         'ferrule; black: bumper (a skin sets those three colours). Send the _input.png files to ChatGPT.',
         18, STYLE['note'], anchor='lm')
    sheet.paste(areas, (pad, 90))
    y = 90 + areas.height + pad
    for panel, im in items:
        colour = tuple(cc.AREA_COLOURS[panel['name']])
        draw.rectangle([pad, y, pad + 18, y + 26 + im.height], fill=colour)
        text(draw, (pad + 30, y + 12), '%s  (%s)' % (panel['name'], panel['note']), 20, anchor='lm')
        sheet.paste(im, (pad + 30, y + 30))
        y += im.height + pad + 36
    write(sheet, os.path.join(TEMPLATE, 'sheet.png'))


if __name__ == '__main__':
    if '--sheet' in sys.argv:
        make_sheet()
    else:
        make_panels()
