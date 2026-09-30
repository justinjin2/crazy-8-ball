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
  * A bright Core ribbon down the middle of every trail: the trail's lightest colour, only a
    little whiter, half blended. Fully additive light on the blue felt turns orange and red to
    pink and white (Roblox adds LightEmission light the same way), so the core stays half
    blended and plain trails' bodies too; their Brightness above 1 is what makes them glow.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'assets', 'cue', 'skins')

LIFETIME = {'Secret': 1.2, 'Mythic': 1.2, 'Legendary': 1.1, 'Epic': 1.0, 'Exclusive': 1.0, 'Rank': 1.0,
            'Rare': 0.9, 'Uncommon': 0.8}
BRIGHTNESS = {'Secret': 2.4, 'Mythic': 2.4, 'Legendary': 2.2, 'Epic': 2.0, 'Exclusive': 2.0, 'Rank': 2.0,
              'Rare': 1.8, 'Uncommon': 1.6}
CORE_BRIGHTNESS = 2.2
CORE_LE = 0.6              # half blended: an additive core turns warm colours pink over the blue felt
CORE_LIGHTEN = 0.2         # toward white: more and the core loses the trail's hue
PLAIN_LE = 0.5             # untextured trails: blended enough that their colour covers the felt
WARM_LE = 0.2              # warm trails (red, orange, gold): nearly all blended, see warmth()
WARM_RB = 80               # warm: red the strongest channel of the seen colour, above blue by this
CORE_WIDTH = 0.2           # of the trail's width
RED_BRIGHTNESS = 1.2       # deep red trails: see deep_red()
# textured trails whose body is a dark colour: added onto the bright felt it vanished and only the
# pale centre showed (Master read as a thin white line), so mostly blended
BLENDED = {'master_cue': 0.35}
# dark trails: a black body that must read as black (their brightness comes from the core); named
# rather than judged from LightEmission, which the warm cap below lowers
DARK = {'eclipse', 'infernal', 'kraken', 'void', 'grandmaster_cue'}


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


def seen_colour(tr):
    """The trail's colour as seen: its tint times its texture's average colour (weighted by
    alpha; the shared soft wisp is white)."""
    cols = trail_colours(tr)
    tint = [sum(c[i] for c in cols) / len(cols) for i in range(3)]
    tex = tr.get('Texture')
    if not tex:
        return tint
    from PIL import Image
    im = Image.open(os.path.join(ROOT, 'assets', 'cue', tex)).convert('RGBA')
    px = im.resize((64, 64)).getdata()
    w = sum(a for _, _, _, a in px) or 1
    mean = [sum(p[i] * p[3] for p in px) / w for i in range(3)]
    return [tint[i] * mean[i] / 255 for i in range(3)]


def is_warm_rgb(rgb):
    r, g, b = rgb
    return r >= g and r - b > WARM_RB


def warm(tr):
    """Warm trails keep their colour only nearly fully blended: Roblox keeps the felt behind a
    trail at 1 - alpha * (1 - LightEmission), so added red over the blue felt reads pink."""
    return is_warm_rgb(seen_colour(tr))


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
        tr['LightEmission'] = PLAIN_LE
    is_warm = warm(tr)
    if is_warm:
        tr['LightEmission'] = min(float(tr.get('LightEmission', 0.4)), WARM_LE)
    le = float(tr.get('LightEmission', 0.4))
    dark = skin.get('id') in DARK
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
    core['Color'] = core.get('Color') or lighten(light, CORE_LIGHTEN)
    core['Width'] = max(float(core.get('Width', 0)), CORE_WIDTH)
    core['NearTransparency'] = 0.0
    core['Transparency'] = [[0, 0.0], [0.5, 0.15], [1, 1]]
    core['WidthScale'] = [[0, 1], [0.6, 0.75], [1, 0.4]]
    core['LightEmission'] = WARM_LE if is_warm or is_warm_rgb(core['Color']) else CORE_LE
    core['Brightness'] = CORE_BRIGHTNESS
    tr['Core'] = core
    if skin.get('id') in BLENDED:
        tr['LightEmission'] = BLENDED[skin['id']]
    if deep_red(tr):
        # a deep red trail read pink over the blue felt even at WARM_LE (Brightness above 1 pushes
        # it toward the additive look): fully blended and no brighter than its colour
        tr['LightEmission'] = 0.0
        tr['Brightness'] = min(tr['Brightness'], RED_BRIGHTNESS)
        core['LightEmission'] = 0.0
        core['Brightness'] = RED_BRIGHTNESS
    return True


def deep_red(tr):
    """Red the trail's seen colour, green and blue both well below it (not orange or pink)."""
    r, g, b = seen_colour(tr)
    return r > 180 and g < 0.3 * r and b < 0.3 * r


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
