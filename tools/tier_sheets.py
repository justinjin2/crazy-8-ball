#!/usr/bin/env python3
"""Tier contact sheets for the cue skins: assets/cue/renders/tiers/<tier>.png, every skin of a
tier the same way up (its full-cue still, labelled), then a small aura row, so the designer can
judge the balance of a tier at a glance. Each sheet is kept under 2 MB (it is committed).

    python3 tools/tier_sheets.py [tier ...]      (no tiers: all of them)

Needs Pillow, and each skin's stills (python3 tools/cue_skin.py <id> --stills).
"""
import io
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CUE = os.path.join(ROOT, 'assets', 'cue')
SKINS = os.path.join(CUE, 'skins')
RENDERS = os.path.join(CUE, 'renders')
ORDER = ['Common', 'Uncommon', 'Rare', 'Epic', 'Legendary', 'Mythic', 'Secret', 'Exclusive', 'Rank']
BG = (22, 24, 30)
MAX_BYTES = 2 * 1024 * 1024
WIDTH = 2000          # the sheet's width before any shrinking
ROW_H = 150           # one full-cue strip
AURA_W = 380          # one aura thumbnail


def font(size):
    for path in ('/System/Library/Fonts/Avenir Next.ttc', '/System/Library/Fonts/Helvetica.ttc'):
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                pass
    return ImageFont.load_default()


def skins_by_tier():
    """Skins grouped by tier, in plan.json's order (then any others, by id)."""
    plan = json.load(open(os.path.join(CUE, 'concepts', 'plan.json')))
    rows = plan if isinstance(plan, list) else plan.get('skins', plan.get('cues', []))
    order = {row['id']: i for i, row in enumerate(rows)}
    tiers = {}
    for name in os.listdir(SKINS):
        if not name.endswith('.json'):
            continue
        skin = json.load(open(os.path.join(SKINS, name)))
        if skin.get('tier'):          # Classic (built before this run) and test files have none
            tiers.setdefault(skin['tier'], []).append(skin)
    for skins in tiers.values():
        skins.sort(key=lambda s: (order.get(s['id'], 10 ** 6), s['id']))
    return tiers


def still(skin_id, name):
    path = os.path.join(RENDERS, 'skins', skin_id, 'stills', name + '.png')
    return Image.open(path).convert('RGB') if os.path.isfile(path) else None


def sheet(tier, skins):
    title_f, label_f = font(44), font(26)
    per_row = max(1, (WIDTH - 40) // AURA_W)
    aura_rows = (len(skins) + per_row - 1) // per_row
    aura_h = int(AURA_W * 0.75)
    height = 90 + len(skins) * (ROW_H + 10) + 50 + aura_rows * (aura_h + 40) + 20
    img = Image.new('RGB', (WIDTH, height), BG)
    draw = ImageDraw.Draw(img)
    draw.text((30, 22), '%s  (%d)' % (tier.upper(), len(skins)), fill=(240, 240, 245), font=title_f)
    y = 90
    for skin in skins:
        full = still(skin['id'], 'full')
        if full is not None:
            full = full.resize((WIDTH - 40, int(full.height * (WIDTH - 40) / full.width)))
            top = max(0, (full.height - ROW_H) // 2)
            img.paste(full.crop((0, top, full.width, top + ROW_H)), (20, y))
        draw.text((30, y + 6), skin['name'], fill=(235, 235, 240), font=label_f)
        y += ROW_H + 10
    draw.text((30, y + 8), 'AURA', fill=(200, 200, 210), font=label_f)
    y += 50
    for i, skin in enumerate(skins):
        aura = still(skin['id'], 'aura')
        x = 20 + (i % per_row) * AURA_W
        yy = y + (i // per_row) * (aura_h + 40)
        if aura is not None:
            img.paste(aura.resize((AURA_W - 10, aura_h)), (x, yy))
        draw.text((x + 6, yy + aura_h + 4), skin['name'], fill=(220, 220, 228), font=font(22))
    return img


def save_under(img, path):
    """Save as PNG, shrinking (then quantising) until it fits under MAX_BYTES."""
    scale = 1.0
    for attempt in range(12):
        im = img if scale == 1.0 else img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
        if attempt >= 3:
            im = im.quantize(colors=256)
        buf = io.BytesIO()
        im.save(buf, 'PNG', optimize=True)
        if buf.tell() <= MAX_BYTES:
            with open(path, 'wb') as handle:
                handle.write(buf.getvalue())
            return im.size, buf.tell()
        scale *= 0.85
    raise SystemExit('tier sheet too big: ' + path)


def main():
    want = set(sys.argv[1:])
    tiers = skins_by_tier()
    out = os.path.join(RENDERS, 'tiers')
    os.makedirs(out, exist_ok=True)
    for tier in ORDER + sorted(t for t in tiers if t not in ORDER):
        if tier not in tiers or (want and tier not in want):
            continue
        path = os.path.join(out, tier.lower() + '.png')
        size, nbytes = save_under(sheet(tier, tiers[tier]), path)
        print('CUE tiers %s: %d skins, %dx%d, %.2f MB' % (tier, len(tiers[tier]), size[0], size[1], nbytes / 1048576))


if __name__ == '__main__':
    main()
