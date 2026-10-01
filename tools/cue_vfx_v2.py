#!/usr/bin/env python3
"""Cue VFX v2: rewrite skins' auras so they read in the bright lobby (designer, 2026-10-01).

    python3 tools/cue_vfx_v2.py            # every skin with a recipe below
    python3 tools/cue_vfx_v2.py kitsune    # just these skin files
    python3 tools/cue_skins_data.py        # then regenerate the game rows

Edits assets/cue/skins/<id>.json in place and is safe to run again (each recipe sets its
emitters by name). The v2 standard, tuned in the real lobby with tools/vfx_lab.luau, not on the
dark Blender preview:
  * a saturated BODY layer (smoke, LightEmission 0) carries the colour on the cream floor;
  * an additive GLOW layer (LightEmission 1, Brightness 2-8) that the lobby's Bloom picks up;
  * crisp ACCENTS (star flares, glints) at Brightness 5-8;
  * the full rate on the back (no BackRateScale), a Highlight on the 3D piece when it must
    stand out of the cloud, and the stick's outline colour (Outline) when its tier's is wrong.
Sprites are tools/vfx_sprites.py's (assets/cue/vfx/v2).
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'assets', 'cue', 'skins')


def v2(name):
    return 'vfx/v2/%s.png' % name


def cyl(a0, a1, width):
    """A cylinder volume host along the cue, from a0 to a1 studs (tip 0), `width` across as
    tuned on the 0.2 cue: widened like tools/cue_widen.py does, so its gap above the surface
    stays the same on today's cue."""
    import cue_widen
    cue_widen.R_NEW = cue_widen.new_envelope()
    far = min(max(a0, a1), 7)
    return {'Kind': 'Part', 'FromStuds': a0, 'ToStuds': a1,
            'Width': round(width + 2 * cue_widen.gain(far), 4), 'Shape': 'Cylinder', 'ShapeStyle': 'Volume'}


def at(studs):
    return {'Kind': 'Attachment', 'AtStuds': studs}


def em(name, texture, host, **k):
    """An emitter row with the v2 defaults (LightInfluence 0, not locked)."""
    row = {'Name': name, 'Texture': texture, 'Host': host}
    if texture.endswith('_8x8.png'):
        row['FlipbookLayout'] = 'Grid8x8'
        row['FlipbookMode'] = 'OneShot'
    row.update({'LightInfluence': 0, 'LockedToPart': False})
    row.update(k)
    return row


def body(name, host, rate, colors, transparency=None, size=None):
    """The saturated body layer: soft smoke puffs, normal blend, deep colour."""
    return em(name, v2('smoke_8x8'), host, Rate=rate, Lifetime=[1.2, 1.8], Speed=[0.3, 0.7],
              SpreadAngle=[180, 180], Drag=1.2, Size=size or [[0, 0.9], [1, 2.4]],
              Transparency=transparency or [[0, 1], [0.15, 0.15], [0.7, 0.4], [1, 1]],
              Rotation=[0, 360], RotSpeed=[-30, 30], Color=colors, LightEmission=0, Brightness=1)


def stars(name, host, rate, colors, size=0.45, brightness=8):
    """Crisp star flares that burst out and fade (the accent layer)."""
    return em(name, v2('flare'), host, Rate=rate, Lifetime=[0.5, 1.0], Speed=[0.6, 1.6],
              SpreadAngle=[180, 180], Drag=2.5,
              Size=[[0, 0], [0.15, size], [0.5, size * 0.45], [1, 0]], Transparency=0,
              Rotation=[0, 45], Color=colors, LightEmission=1, Brightness=brightness)


def glints(rate, colors=None):
    """Gold four-point glints locked to the cue."""
    return em('GoldGlints', v2('glint'), cyl(0.5, 7.0, 0.5), Rate=rate, Lifetime=[0.4, 0.7],
              Speed=[0, 0.1], SpreadAngle=[180, 180], Size=[[0, 0], [0.25, 0.75], [1, 0]],
              Transparency=0, Rotation=[-20, 20],
              Color=colors or [[0, '#FFE9A8'], [1, '#FFC94A']], LightEmission=1, Brightness=7,
              LockedToPart=True)


def dust(name, host, rate, colors, brightness=3):
    return em(name, v2('dust'), host, Rate=rate, Lifetime=[1.0, 1.6], Speed=[0.2, 0.5],
              SpreadAngle=[180, 180], Drag=1, Size=[[0, 0.6], [1, 1.2]],
              Transparency=[[0, 1], [0.3, 0.15], [1, 1]], Rotation=[0, 360],
              RotSpeed=[-60, 60], Color=colors, LightEmission=1, Brightness=brightness)


def by_name(aura):
    return {e['Name']: e for e in aura['Emitters']}


def finish(aura, note, beams=None, light=None, highlight=None, outline=None):
    """`outline`: the stick's outline colour (else its tier's, Config.CueSkins.Outline)."""
    aura.pop('BackRateScale', None)
    if outline:
        aura['Outline'] = outline
    else:
        aura.pop('Outline', None)
    aura['Note'] = note
    for b in aura.get('Beams', []):
        b.update(beams or {})
    for l in aura.get('Lights', []):
        l.update(light or {})
    if highlight:
        aura['Highlight'] = highlight
    else:
        aura.pop('Highlight', None)


def celestial_dragon(aura):
    keep = []
    for e in aura['Emitters']:
        if e['Host'].get('Kind') == 'Segment':
            # Spirit flames on the coil and the head: bigger, saturated, glowing.
            e.update(Texture=v2('flame_8x8'), FlipbookLayout='Grid8x8', FlipbookMode='OneShot',
                     Size=[[0, 0.45], [0.4, 0.95], [1, 0.3]],
                     Rate=14 if e['Name'] == 'Wisps' else 6, Brightness=2, LightEmission=0.5,
                     LightInfluence=0, Transparency=[[0, 0.6], [0.2, 0.1], [1, 1]],
                     Color=[[0, '#CFEBFF'], [0.35, '#4E9BFF'], [1, '#1F3FD0']])
            keep.append(e)
    keep += [
        body('MistBody', cyl(0.3, 7.0, 0.9), 90, [[0, '#2A5CFF'], [1, '#12237A']]),
        em('MistGlow', v2('smoke_8x8'), cyl(0.3, 7.0, 0.8), Rate=16, Lifetime=[1.0, 1.5],
           Speed=[0.1, 0.35], SpreadAngle=[180, 180], Drag=1.2, Size=[[0, 0.5], [1, 1.2]],
           Transparency=[[0, 1], [0.2, 0.7], [1, 1]], Rotation=[0, 360], RotSpeed=[-40, 40],
           Color=[[0, '#7FC0FF'], [1, '#4D74FF']], LightEmission=1, Brightness=1.2),
        stars('Starlight', cyl(0.2, 7.2, 1.0), 90, [[0, '#FFFFFF'], [1, '#BFE3FF']]),
        dust('StarDust', cyl(0.3, 7.0, 1.1), 28, [[0, '#FFFFFF'], [1, '#9FD2FF']]),
        glints(18),
        em('Rising', v2('streak'), cyl(0.3, 7.0, 0.5), Rate=35, Lifetime=[0.5, 0.9],
           Speed=[1.5, 3], SpreadAngle=[25, 25], EmissionDirection='Top', Acceleration=[0, 2, 0],
           Orientation='VelocityParallel', Size=[[0, 0.35], [1, 0.15]],
           Transparency=[[0, 1], [0.2, 0.2], [1, 1]], Color=[[0, '#C9EDFF'], [1, '#6FB3FF']],
           LightEmission=1, Brightness=3),
        em('Swirls', v2('swirl_8x8'), cyl(0.5, 6.8, 0.7), Rate=14, Lifetime=[0.9, 1.3],
           Speed=[0.1, 0.3], SpreadAngle=[180, 180], Size=[[0, 0.6], [1, 1.4]],
           Transparency=[[0, 1], [0.25, 0.3], [1, 1]], Rotation=[0, 360], RotSpeed=[-90, 90],
           Color=[[0, '#BFE6FF'], [1, '#3E6BFF']], LightEmission=0.6, Brightness=2),
    ]
    aura['Emitters'] = keep
    aura.pop('Arcs', None)
    finish(aura,
           'v2 (2026-10-01): a dense deep-blue starlight cloud round the whole cue (smoke body, '
           'soft blue glow), white star flares bursting out, star dust, gold glints, light '
           'streaks rising and swirls; big blue spirit flames along the coiling dragon, which '
           'is outlined (Highlight) so it reads through the cloud.',
           beams={'Width0': 0.8, 'Width1': 1.6, 'Brightness': 3},
           light={'Brightness': 1.2, 'Range': 7, 'Color': '#3F7BFF'},
           highlight={'FillColor': '#7FC8FF', 'FillTransparency': 0.55,
                      'OutlineColor': '#E6F6FF', 'OutlineTransparency': 0},
           outline='#3E8BFF')


def kitsune(aura):
    old = by_name(aura)
    petals = old['Petals']
    petals.update(Rate=40, Size=[[0, 0.3], [1, 0.36]], LightEmission=0, LightInfluence=0,
                  Brightness=1.2, Color='#FFD3EC')
    petals['Host']['Width'] = cyl(0.5, 7.2, 1.4)['Width']
    trail = old['FoxTrail']
    trail.update(Texture=v2('flame_8x8'), FlipbookLayout='Grid8x8', FlipbookMode='OneShot',
                 Rate=18, Size=[[0, 0.3], [0.4, 0.6], [1, 0.2]], Brightness=2, LightEmission=0.4,
                 LightInfluence=0, Color=[[0, '#FFE0FA'], [0.4, '#E85BFF'], [1, '#6D1FD6']])
    aura['Emitters'] = [
        petals,
        trail,
        body('FoxBody', cyl(0.3, 7.0, 0.9), 85,
             [[0, '#C21FE0'], [0.5, '#7A12C8'], [1, '#2E0866']],
             transparency=[[0, 1], [0.15, 0.1], [0.7, 0.35], [1, 1]]),
        em('Foxfire', v2('flame_8x8'), cyl(0.3, 7.0, 0.8), Rate=40, Lifetime=[0.6, 1.0],
           Speed=[0.3, 0.8], SpreadAngle=[30, 30], EmissionDirection='Top',
           Acceleration=[0, 1.6, 0], Size=[[0, 0.4], [0.4, 0.9], [1, 0.3]],
           Transparency=[[0, 0.7], [0.2, 0.1], [1, 1]],
           Color=[[0, '#FFB8F4'], [0.3, '#FF3FD2'], [1, '#6A16D8']], LightEmission=0.25,
           Brightness=1.6),
        em('FoxOrbs', v2('orb'), cyl(0.4, 6.8, 1.2), Rate=8, Lifetime=[0.8, 1.4],
           Speed=[0.1, 0.3], SpreadAngle=[180, 180], Size=[[0, 0], [0.2, 0.25], [0.8, 0.2], [1, 0]],
           Transparency=0, Color=[[0, '#FF7BE6'], [1, '#C23CFF']], LightEmission=1,
           Brightness=2.5),
        stars('Sparkles', cyl(0.2, 7.2, 1.0), 55, [[0, '#FFFFFF'], [1, '#FFB3F0']], size=0.55,
              brightness=7),
        glints(14),
    ]
    for o in aura.get('Orbiters', []):
        o['Head'].update(Color='#FF7AE6', Size=0.36)
        o['Trail']['WidthStuds'] = 0.18
    finish(aura,
           'v2 (2026-10-01): a saturated magenta-violet foxfire cloud round the cue (smoke '
           'body), rising pink foxfire flames, sakura petals drifting, pink star flares and '
           'gold glints, three foxfire orbs looping along it; the mask and the running fox '
           'are outlined (Highlight) so they read through the cloud.',
           beams={'Width0': 0.7, 'Width1': 1.4, 'Brightness': 2.5},
           light={'Brightness': 1.2, 'Range': 7},
           highlight={'FillColor': '#FF8AE8', 'FillTransparency': 0.4,
                      'OutlineColor': '#FFFFFF', 'OutlineTransparency': 0},
           outline='#E040FF')


ECLIPSE_AT = 7.3  # the eclipse sits just inside the butt (studs from the tip)


def eclipse(aura):
    old = by_name(aura)
    flares, sparks = old['Flares'], old['CoronaSparks']
    flares['Host'] = at(ECLIPSE_AT)
    sparks['Host'] = at(ECLIPSE_AT)
    aura['Emitters'] = [
        flares,
        sparks,
        # A small glowing eclipse (designer, 2026-10-01, replacing the giant black disc): a
        # black disc in a white-hot ring with gold corona rays, steady, in a blazing corona.
        em('EclipseOrb', v2('eclipse_orb'), at(ECLIPSE_AT), Rate=1, Lifetime=[2.2, 2.2],
           Speed=[0, 0], Size=1.25, Rotation=[0, 0],
           Transparency=[[0, 1], [0.12, 0], [0.88, 0], [1, 1]], Color='#FFFFFF',
           LightEmission=0, Brightness=1, LockedToPart=True, ZOffset=0.2),
        em('CoronaBlaze', 'vfx/eclipse/corona.png', at(ECLIPSE_AT), Rate=3, Lifetime=[1.2, 1.6],
           Speed=[0, 0], Size=[[0, 1.35], [1, 1.6]], Rotation=[0, 360], RotSpeed=[-20, 20],
           Transparency=[[0, 1], [0.2, 0.1], [0.8, 0.2], [1, 1]],
           Color=[[0, '#FFF4C8'], [1, '#FFB21E']], LightEmission=1, Brightness=5,
           LockedToPart=True, ZOffset=0.1),
        em('CoronaRing', v2('ring'), at(ECLIPSE_AT), Rate=2, Lifetime=[1.0, 1.0], Speed=[0, 0],
           Size=[[0, 1.0], [1, 2.6]], Transparency=[[0, 0.2], [1, 1]],
           Color=[[0, '#FFE7A0'], [1, '#FF9A1A']], LightEmission=1, Brightness=4,
           LockedToPart=True),
        body('SpaceBody', cyl(0.3, 7.0, 0.9), 80,
             [[0, '#4A2A9A'], [0.6, '#24124F'], [1, '#0D0820']],
             transparency=[[0, 1], [0.15, 0.2], [0.7, 0.45], [1, 1]], size=[[0, 0.9], [1, 2.3]]),
        em('Nebula', v2('smoke_8x8'), cyl(0.3, 7.0, 0.8), Rate=22, Lifetime=[1.2, 1.8],
           Speed=[0.2, 0.5], SpreadAngle=[180, 180], Drag=1.2, Size=[[0, 0.7], [1, 1.6]],
           Transparency=[[0, 1], [0.2, 0.55], [1, 1]], Rotation=[0, 360],
           Color=[[0, '#FFB24A'], [0.5, '#C05AFF'], [1, '#5A3CFF']], LightEmission=1,
           Brightness=1.6),
        dust('StarDust', cyl(0.3, 7.2, 1.1), 30, [[0, '#FFFFFF'], [1, '#FFE08A']], brightness=4),
        stars('Stars', cyl(0.2, 7.4, 1.1), 80, [[0, '#FFFFFF'], [1, '#FFE3A0']], brightness=7),
        glints(16, [[0, '#FFF1B0'], [1, '#FFB300']]),
    ]
    finish(aura,
           'v2 (2026-10-01, designer: a smaller glowing eclipse): just inside the butt a small '
           'eclipse, a black disc in a white-hot ring, blazing in a gold corona with an '
           'expanding gold ring, solar flares and sparks; round the cue a deep violet-navy '
           'space cloud with warm nebula glow, gold star dust, star flares and glints; three '
           'gold orbit trails with small eclipses loop along it, and the piece\'s gold orbits '
           'and asteroids turn round it.',
           beams={'Width0': 0.6, 'Width1': 1.2, 'Brightness': 2.5},
           light={'Brightness': 1.5, 'Range': 8, 'AtStuds': ECLIPSE_AT}, outline='#FFB21E')


RECIPES = {
    'celestial_dragon': celestial_dragon,
    'kitsune': kitsune,
    'eclipse': eclipse,
}


def main(ids):
    for sid in ids or sorted(RECIPES):
        path = os.path.join(SKINS, sid + '.json')
        skin = json.load(open(path))
        RECIPES[sid](skin['vfx']['Aura'])
        with open(path, 'w') as f:
            json.dump(skin, f, indent=2, ensure_ascii=False)
            f.write('\n')
        print('v2 aura:', sid, len(skin['vfx']['Aura']['Emitters']), 'emitters')


if __name__ == '__main__':
    main(sys.argv[1:])
