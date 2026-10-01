#!/usr/bin/env python3
"""Cut each cue's references out of the concept sheets (assets/cue/concepts/<code>.png) into
assets/cue/concepts/cues/<id>/<name>.png, from the boxes in assets/cue/concepts/crops.json:
    {"C1": {"midnight": {"full": [x0, y0, x1, y1], "closeup": [...], ...}, ...}, ...}
Boxes are in the sheet's own pixels; a list of boxes is cut and joined side by side. Needs Pillow.

    python3 tools/crop_concepts.py [ids...]     (no ids: every cue in crops.json)
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONCEPTS = os.path.join(ROOT, 'assets', 'cue', 'concepts')


def main():
    want = set(sys.argv[1:])
    with open(os.path.join(CONCEPTS, 'crops.json')) as handle:
        spec = json.load(handle)
    for sheet, cues in spec.items():
        if sheet.startswith('_'):
            continue
        path = os.path.join(CONCEPTS, sheet + '.png')
        if not os.path.isfile(path):
            print('missing sheet', sheet)
            continue
        image = Image.open(path).convert('RGB')
        for cue, boxes in cues.items():
            if want and cue not in want:
                continue
            out = os.path.join(CONCEPTS, 'cues', cue)
            os.makedirs(out, exist_ok=True)
            for name, box in boxes.items():
                if isinstance(box[0], list):
                    # several boxes side by side (e.g. a Legendary sheet's forearm and butt
                    # panels joined into one handle close-up), scaled to the first one's height
                    parts = [image.crop(tuple(b)) for b in box]
                    h = parts[0].height
                    parts = [p.resize((max(1, round(p.width * h / p.height)), h)) for p in parts]
                    joined = Image.new('RGB', (sum(p.width for p in parts), h))
                    x = 0
                    for p in parts:
                        joined.paste(p, (x, 0))
                        x += p.width
                    joined.save(os.path.join(out, name + '.png'), optimize=True)
                    continue
                image.crop(tuple(box)).save(os.path.join(out, name + '.png'), optimize=True)
            print(sheet, cue, ', '.join(boxes))


if __name__ == '__main__':
    main()
