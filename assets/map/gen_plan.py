"""Draws the rooftop plan (map_layout.py) as a top-down PNG, and a side-by-side with the art.

    python3 assets/map/gen_plan.py

Writes assets/map/Plan.png (the plan, committed with the Spec) and
assets/map/checkpoints/plan-vs-art.jpg (the art's top-down panel on the left, the plan on the
right). North is -Z (the lounge) at the top, the city on the left, the ocean on the right: the
same way round as panels/top-down.jpg.
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import map_layout as ml  # noqa: E402

PX = 5  # pixels per stud
MARGIN = 60  # studs of backdrop round the terrace
COLOURS = {
    'backdrop_city': (120, 130, 150),
    'backdrop_ocean': (60, 150, 200),
    'terrace': (236, 228, 214),
    'grid': (224, 214, 198),
    'landing': (228, 218, 200),
    'steps': (200, 190, 176),
    'lounge': (214, 200, 182),
    'pergola': (190, 150, 110),
    'walkway': (250, 246, 236),
    'fence': (90, 90, 90),
    'box': (70, 200, 110),
    'cloth': (40, 175, 45),
    'rail': (120, 60, 40),
    'railing': (40, 44, 52),
    'text': (30, 30, 30),
}
CLOTH = {'Green': (40, 175, 45), 'RedWood': (191, 38, 89), 'CharcoalWood': (90, 94, 102)}
PROP_COLOURS = {
    'fern_planter': (70, 150, 70),
    'palm_planter': (30, 120, 60),
    'lantern': (255, 190, 80),
    'lantern_tall': (255, 170, 40),
    'umbrella_set': (245, 240, 225),
    'side_couch': (150, 140, 130),
    'lounge_couch': (150, 140, 130),
    'coffee_table': (80, 60, 50),
    'fire_pit': (240, 110, 40),
    'piano': (20, 20, 20),
    'piano_bench': (40, 40, 40),
    'snack_counter': (200, 120, 60),
    'globe_light': (255, 230, 150),
    'column': (245, 238, 220),
    'table_glow': (255, 200, 120),
}


def font(size):
    for name in ('/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Helvetica.ttc'):
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def draw_plan(plan):
    tx0, tz0, tx1, tz1 = plan['zones']['terrace']
    lz1 = plan['zones']['lower_landing'][3]
    x0, x1 = tx0 - MARGIN, tx1 + MARGIN
    z0, z1 = tz0 - MARGIN / 2, lz1 + MARGIN / 2
    w, h = int((x1 - x0) * PX), int((z1 - z0) * PX)
    img = Image.new('RGB', (w, h), COLOURS['backdrop_ocean'])
    d = ImageDraw.Draw(img, 'RGBA')

    def pt(x, z):
        return ((x - x0) * PX, (z - z0) * PX)

    def rect(r, fill=None, outline=None, width=1):
        a, b = pt(r[0], r[1]), pt(r[2], r[3])
        d.rectangle([a[0], a[1], b[0], b[1]], fill=fill, outline=outline, width=width)

    def text(x, z, s, size=14, fill=COLOURS['text'], anchor='mm'):
        d.text(pt(x, z), s, fill=fill, font=font(size), anchor=anchor)

    # Backdrop halves: city left, ocean right (and behind).
    d.rectangle([0, 0, pt(tx0, 0)[0], h], fill=COLOURS['backdrop_city'])
    text(tx0 - MARGIN / 2, 0, 'CITY', 28, (255, 255, 255))
    text(tx1 + MARGIN / 2, 0, 'OCEAN', 28, (255, 255, 255))
    text(0, tz0 - MARGIN / 4, 'SEA (behind the lounge)', 20, (255, 255, 255))

    z = plan['zones']
    rect(z['terrace'], COLOURS['terrace'])
    # Faint 6-stud tile grid (the floor idea; the real tile is decided in Stage 2).
    gx = math.ceil(tx0 / 6) * 6
    while gx < tx1:
        d.line([pt(gx, tz0), pt(gx, tz1)], fill=COLOURS['grid'], width=1)
        gx += 6
    gz = math.ceil((tz0 - 3) / 6) * 6 + 3
    while gz < tz1:
        d.line([pt(tx0, gz), pt(tx1, gz)], fill=COLOURS['grid'], width=1)
        gz += 6
    for name in ('landing',):
        rect(z[name], COLOURS['landing'])
    rect(z['lounge'], COLOURS['lounge'])
    rect(z['lounge_steps'], COLOURS['steps'])
    d.line([pt(z['lounge'][0], z['lounge'][3]), pt(z['lounge'][2], z['lounge'][3])], fill=(150, 140, 130), width=3)
    rect(z['steps'], COLOURS['steps'])
    rect(z['lower_landing'], COLOURS['landing'])
    # Step lines.
    sx0, sz0, sx1, sz1 = z['steps']
    n = ml.P['step_count']
    for k in range(1, n):
        zz = sz0 + (sz1 - sz0) * k / n
        d.line([pt(sx0, zz), pt(sx1, zz)], fill=(150, 140, 130), width=2)
    lx0, lz0, lx1, lz1b = z['lounge_steps']
    n = ml.P['lounge_step_count']
    for k in range(1, n):
        zz = lz0 + (lz1b - lz0) * k / n
        d.line([pt(lx0, zz), pt(lx1, zz)], fill=(150, 140, 130), width=2)
    # Walkways.
    for r in plan['walkways'].values():
        rect(r, COLOURS['walkway'] + (160,))
    # Pergola roof outline.
    rect(z['pergola'], COLOURS['pergola'] + (70,), COLOURS['pergola'], 3)
    # Railing round the terrace (not across the entrance steps) and round the lower landing.
    d.rectangle([*pt(tx0, tz0), *pt(tx1, tz1)], outline=COLOURS['railing'], width=4)
    d.line([pt(sx0, tz1), pt(sx1, tz1)], fill=COLOURS['terrace'], width=5)
    lr = z['lower_landing']
    d.line([pt(lr[0], sz0), pt(lr[0], lr[3]), pt(lr[2], lr[3]), pt(lr[2], sz0)], fill=COLOURS['railing'], width=4)

    # Fences (dashed), queue boxes, tables.
    for f in plan['fences']:
        a, b = pt(f[0], f[1]), pt(f[2], f[3])
        for (p0, p1) in (((a[0], a[1]), (b[0], a[1])), ((b[0], a[1]), (b[0], b[1])),
                         ((b[0], b[1]), (a[0], b[1])), ((a[0], b[1]), (a[0], a[1]))):
            length = math.dist(p0, p1)
            steps = int(length // 10)
            for s in range(0, steps, 2):
                q0 = (p0[0] + (p1[0] - p0[0]) * s / steps, p0[1] + (p1[1] - p0[1]) * s / steps)
                q1 = (p0[0] + (p1[0] - p0[0]) * (s + 1) / steps, p0[1] + (p1[1] - p0[1]) * (s + 1) / steps)
                d.line([q0, q1], fill=COLOURS['fence'], width=2)
    for pad in plan['pads']:
        a, b = pt(pad['X'] - pad['radius'], pad['Z'] - pad['radius']), pt(pad['X'] + pad['radius'], pad['Z'] + pad['radius'])
        d.ellipse([a[0], a[1], b[0], b[1]], fill=(245, 248, 255, 230), outline=COLOURS['box'], width=3)
    tl, tw = ml.GAME['table_length'], ml.GAME['table_width']
    for t, pad in zip(plan['tables'], plan['pads']):
        rect((t['X'] - tl / 2, t['Z'] - tw / 2, t['X'] + tl / 2, t['Z'] + tw / 2), COLOURS['rail'])
        inset = 7 * 0.16
        rect((t['X'] - tl / 2 + inset, t['Z'] - tw / 2 + inset, t['X'] + tl / 2 - inset, t['Z'] + tw / 2 - inset),
             CLOTH[t['look']])
        text(t['X'], t['Z'], str(t['id']), 16, (255, 255, 255))
        n = t['teamSize']
        text(pad['X'], pad['Z'], '%dv%d' % (n, n), 13, (40, 90, 160))

    # Props (glow first, under everything).
    order = sorted(plan['props'], key=lambda p: p['kind'] != 'table_glow')
    for p in order:
        r = ml.footprint(p)
        col = PROP_COLOURS.get(p['kind'], (255, 0, 255))
        if p['kind'] == 'table_glow':
            continue  # drawn as a soft halo below instead
        if p['kind'] in ('fire_pit', 'coffee_table', 'globe_light', 'lantern', 'lantern_tall'):
            a, b = pt(r[0], r[1]), pt(r[2], r[3])
            d.ellipse([a[0], a[1], b[0], b[1]], fill=col, outline=(40, 40, 40))
        elif p['kind'] in ('umbrella_set', 'palm_planter'):
            a, b = pt(r[0], r[1]), pt(r[2], r[3])
            if p['kind'] == 'palm_planter':
                rect(r, (150, 140, 130), (90, 90, 90))
                c = pt(p['X'], p['Z'])
                d.ellipse([c[0] - 30, c[1] - 30, c[0] + 30, c[1] + 30], fill=col + (170,))
            else:
                d.ellipse([a[0], a[1], b[0], b[1]], fill=col + (220,), outline=(120, 110, 100), width=2)
        else:
            rect(r, col, (40, 40, 40))

    # Spawn arrow.
    s = plan['spawn']
    c = pt(s['X'], s['Z'])
    d.polygon([(c[0], c[1] - 18), (c[0] - 12, c[1] + 10), (c[0] + 12, c[1] + 10)], fill=(230, 40, 40))
    text(s['X'], s['Z'] + 4, 'SPAWN', 14, (200, 30, 30))

    # Sun directions (from Spec: the sunset sun 36 degrees right of -Z, the day sun 128).
    cx, cz = 0.0, (tz0 + tz1) / 2
    for label, az, colour in (('sunset sun', 36.4, (255, 120, 40)), ('day sun', 128.2, (255, 220, 60))):
        a = math.radians(az)
        ex, ez = cx + 130 * math.sin(a), cz - 130 * math.cos(a)
        d.line([pt(cx, cz), pt(ex, ez)], fill=colour + (200,), width=3)
        text(ex, ez, label, 16, colour)

    # Scale bar and dimensions.
    d.line([pt(tx0, tz1 + 12), pt(tx0 + 50, tz1 + 12)], fill=(255, 255, 255), width=4)
    text(tx0 + 25, tz1 + 16, '50 studs (10 players tall)', 14, (255, 255, 255))
    text(0, tz0 + 4, 'LOUNGE (raised, pergola)', 16)
    return img


def side_by_side(plan_img):
    art = Image.open(os.path.join(HERE, 'reference', 'panels', 'top-down.jpg')).convert('RGB')
    h = 900
    a = art.resize((round(art.width * h / art.height), h), Image.LANCZOS)
    p = plan_img.resize((round(plan_img.width * h / plan_img.height), h), Image.LANCZOS)
    out = Image.new('RGB', (a.width + p.width + 20, h), (255, 255, 255))
    out.paste(a, (0, 0))
    out.paste(p, (a.width + 20, 0))
    return out


if __name__ == '__main__':
    plan = ml.build()
    problems = ml.check(plan)
    for line in problems:
        print('PROBLEM:', line)
    img = draw_plan(plan)
    img.save(os.path.join(HERE, 'Plan.png'), optimize=True)
    os.makedirs(os.path.join(HERE, 'checkpoints'), exist_ok=True)
    side_by_side(img).save(os.path.join(HERE, 'checkpoints', 'plan-vs-art.jpg'), quality=90)
    print(ml.summary(plan))
    print('wrote Plan.png', img.size)
