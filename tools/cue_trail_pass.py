#!/usr/bin/env python3
"""The ball-trail standard for the cue skins (designer, 2026-09-30: trails brighter, clearer and
longer). Rewrites vfx.Style.Trail in assets/cue/skins/<id>.json; safe to run again.

    python3 tools/cue_trail_pass.py [id ...]      (no ids: every skin with a tier below)

What it sets, by tier:
  * Lifetime at least LIFETIME[tier] seconds: the trail streams further behind the ball.
  * Transparency held nearly solid for most of the life, fading only at the end (the old trail
    faded straight from the ball, so the back half was barely there).
  * WidthScale that ends at no less than half width, so the tail still reads.
  * Brightness (Roblox Trail.Brightness) so the glow reads on the felt; dark trails (Eclipse,
    Kraken, Void ...) keep their low LightEmission body so the black still shows, and get their
    brightness from the core.
  * A bright Core ribbon down the middle of every trail (a wider, fully glowing line of the
    trail's lightest colour).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'assets', 'cue', 'skins')

LIFETIME = {'Secret': 1.2, 'Mythic': 1.2, 'Legendary': 1.1, 'Epic': 1.0, 'Exclusive': 1.0, 'Rank': 1.0,
            'Rare': 0.9}
BRIGHTNESS = {'Secret': 2.4, 'Mythic': 2.4, 'Legendary': 2.2, 'Epic': 2.0, 'Exclusive': 2.0, 'Rank': 2.0,
              'Rare': 1.8}
CORE_BRIGHTNESS = 3.0
CORE_WIDTH = 0.2           # of the trail's width
DARK_LE = 0.6              # below this the trail body is a dark trail (black must read)


def lighten(rgb, k):
    return [round(c + (255 - c) * k) for c in rgb]


def hex_rgb(h):
    h = h.lstrip('#')
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def trail_colours(tr):
    if tr.get('Colors'):
        return [c if isinstance(c, list) else hex_rgb(c) for c in tr['Colors']]
    c = tr.get('Color', [255, 255, 255])
    return [c if isinstance(c, list) else hex_rgb(c)]


def apply(skin):
    tier = skin.get('tier')
    style = (skin.get('vfx') or {}).get('Style')
    if tier not in LIFETIME or not style or not style.get('Trail'):
        return False
    tr = style['Trail']
    textured = bool(tr.get('Texture'))
    tr['Lifetime'] = max(float(tr.get('Lifetime', 0.34)), LIFETIME[tier])
    if not textured:
        # the shared soft wisp, tinted: wider and solid instead of the old half-transparent line
        tr['WidthStuds'] = max(float(tr.get('WidthStuds', 0.21)), 0.3)
        tr['LightEmission'] = 1
    le = float(tr.get('LightEmission', 0.4))
    dark = le < DARK_LE
    tr['NearTransparency'] = 0.0
    tr['Transparency'] = [[0, 0.0], [0.55, 0.12], [1, 1]] if not dark else [[0, 0.0], [0.6, 0.1], [1, 1]]
    ws = tr.get('WidthScale') or [[0, 1], [1, 0.35]]
    if ws[-1][1] < 0.5:
        ws = [k for k in ws if k[0] < 0.6] + [[0.6, max(0.8, ws[0][1] * 0.85)], [1, 0.5]]
    tr['WidthScale'] = ws
    tr['Brightness'] = 1.0 if dark else BRIGHTNESS[tier]
    cols = trail_colours(tr)
    light = max(cols, key=sum)
    core = dict(tr.get('Core') or {})
    core['Color'] = core.get('Color') or lighten(light, 0.45)
    core['Width'] = max(float(core.get('Width', 0)), CORE_WIDTH)
    core['NearTransparency'] = 0.0
    core['Transparency'] = [[0, 0.0], [0.5, 0.15], [1, 1]]
    core['WidthScale'] = [[0, 1], [0.6, 0.75], [1, 0.4]]
    core['LightEmission'] = 1
    core['Brightness'] = CORE_BRIGHTNESS
    tr['Core'] = core
    return True


def main():
    want = set(sys.argv[1:])
    for name in sorted(os.listdir(SKINS)):
        if not name.endswith('.json'):
            continue
        path = os.path.join(SKINS, name)
        skin = json.load(open(path))
        if want and skin.get('id') not in want:
            continue
        if apply(skin):
            with open(path, 'w') as fh:
                json.dump(skin, fh, indent=2)
            tr = skin['vfx']['Style']['Trail']
            print('CUE trail %-18s %-9s life %.2f  bright %.1f  LE %.2f  core %.2f' % (
                skin['id'], skin['tier'], tr['Lifetime'], tr['Brightness'], tr['LightEmission'], tr['Core']['Width']))


if __name__ == '__main__':
    main()
