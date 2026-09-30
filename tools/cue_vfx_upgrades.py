#!/usr/bin/env python3
"""The VFX upgrade pass on the cue skins (designer, 2026-09-30: many effects were underwhelming,
flat or choppy; go back one skin at a time from the rarest). Edits assets/cue/skins/<id>.json in
place and is safe to run again (each change sets values, it does not stack).

    python3 tools/cue_vfx_upgrades.py [id ...]     (no ids: every skin that has an upgrade)

* Every skin: flipbooks that have a 64-frame Grid8x8 twin are switched to it (smooth instead of
  about 11-15 frames a second).
* Per skin: the changes in UPGRADES, one function per skin, rarest first.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'assets', 'cue', 'skins')

# Grid4x4 sheet -> its 64-frame Grid8x8 twin (CueVfx.flipbook8)
SMOOTH = {
    'vfx/_shared/fire_4x4.png': 'vfx/_shared/fire_8x8.png',
    'vfx/_shared/smoke_4x4.png': 'vfx/_shared/smoke_8x8.png',
    'vfx/rank/energy_flame_4x4.png': 'vfx/_shared/energy_flame_8x8.png',
    'vfx/eclipse/flare_4x4.png': 'vfx/eclipse/flare_8x8.png',
}


def emitters(vfx):
    """Every particle emitter spec in a skin's vfx block (aura, trail, pocket)."""
    for block in ('Aura', 'Trail', 'Pocket'):
        b = vfx.get(block) or {}
        for key in ('Emitters', 'Layers'):
            for e in b.get(key) or []:
                yield e


def smooth(vfx):
    for e in emitters(vfx):
        if e.get('Texture') in SMOOTH:
            e['Texture'] = SMOOTH[e['Texture']]
            e['FlipbookLayout'] = 'Grid8x8'


def named(items, name):
    return next(i for i in items if i['Name'] == name)


def put(items, spec):
    """Add spec to a list, or replace the item of the same Name."""
    for i, item in enumerate(items):
        if item['Name'] == spec['Name']:
            items[i] = spec
            return
    items.append(spec)


def cyl(a0, a1, width):
    return {'Kind': 'Part', 'FromStuds': a0, 'ToStuds': a1, 'Width': width, 'Shape': 'Cylinder',
            'ShapeStyle': 'Surface'}


def eclipse(d):
    v = d['vfx']
    a = v['Aura']
    # molten-gold lightning crawling over the whole cue (the concept's gold filaments)
    a['Arcs'] = [
        {'Name': 'MoltenCrawl', 'Count': 4, 'Segments': 12, 'FromStuds': 0.3, 'ToStuds': 7.0, 'Length': [0.9, 2.0],
         'Around': 200, 'Radius': 0.15, 'Jitter': 0.12, 'Interval': 0.11, 'Duty': 0.75, 'WidthStuds': 0.09,
         'Color': '#FFC24A', 'Brightness': 2.2, 'Texture': 'vfx/_shared/bolt_strip.png'},
        {'Name': 'MoltenLeap', 'Count': 2, 'Segments': 14, 'FromStuds': 2.0, 'ToStuds': 7.0, 'Length': [1.6, 3.0],
         'Around': 320, 'Radius': 0.24, 'Jitter': 0.2, 'Interval': 0.2, 'Duty': 0.5, 'WidthStuds': 0.11,
         'Color': '#FFD774', 'Brightness': 2.4, 'Texture': 'vfx/_shared/bolt_strip.png'},
    ]
    # the orbit loops: wide enough to read as the concept's orbit rings, with brighter, longer trails
    for o in a['Orbiters']:
        o['Radius'] = 0.38
        o['Wobble'] = 0.08
        o['Trail'].update({'Lifetime': 0.9, 'WidthStuds': 0.055, 'Brightness': 3,
                           'Transparency': [[0, 0], [0.6, 0.25], [1, 1]]})
        o['Head']['Size'] = 0.24
    # gold fire licking up round the forearm and butt, strongest where the concept blazes
    put(a['Emitters'], {
        'Name': 'GoldFlame', 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(3.6, 7.0, 0.22), 'Rate': 10, 'Lifetime': [0.6, 0.9],
        'Speed': [0.3, 0.6], 'SpreadAngle': [25, 25], 'EmissionDirection': 'Top', 'Acceleration': [0, 1.4, 0],
        'Size': [[0, 0.4], [0.35, 0.85], [1, 0.25]], 'Transparency': [[0, 0.3], [0.3, 0.05], [1, 1]],
        'Color': [[0, '#FFF6D0'], [0.5, '#FFC030'], [1, '#FF8A00']], 'Brightness': 1.6, 'LightEmission': 1, 'LightInfluence': 0,
        'LockedToPart': False})
    # a faint cloud of gold energy round the forearm and butt (the concept's glowing haze)
    put(a['Emitters'], {
        'Name': 'GoldHaze', 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(3.0, 7.2, 0.3), 'Rate': 5, 'Lifetime': [1.4, 2.0],
        'Speed': [0.05, 0.15], 'SpreadAngle': [180, 180], 'Acceleration': [0, 0.15, 0],
        'Size': [[0, 0.5], [1, 1.1]], 'Rotation': [0, 360], 'RotSpeed': [-20, 20],
        'Transparency': [[0, 1], [0.3, 0.72], [1, 1]], 'Color': [[0, '#FFC040'], [1, '#FF8A1A']],
        'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False})
    # pocket: the black disc fills the corona ring exactly (corona ring at 0.55 of its size, the
    # disc edge at 0.42 of the eclipse sprite's, so 1.31 times the size, same timing) and sits in
    # front of the gold column; the prominences are scaled so they rise off the corona's rim
    P = v['Pocket']['Layers']
    e = named(P, 'Eclipse')
    e.update({'Delay': 0.4, 'Lifetime': 1.0, 'Size': [[0, 1.7], [0.3, 4.45], [1, 5.0]],
              'Transparency': [[0, 0], [0.7, 0], [1, 1]], 'ZOffset': 0.6})
    named(P, 'CoronaBurst')['ZOffset'] = 0.7
    # the prominences read as tangled wire at pocket size: radiating gold light streaks instead
    P[:] = [x for x in P if x['Name'] != 'Prominences']
    put(P, {'Name': 'RayBurst', 'Texture': 'vfx/_shared/streak.png', 'Host': {'Kind': 'Point', 'Offset': [0, 1.8, 0]},
            'Burst': 28, 'Delay': 0.42, 'Lifetime': [0.35, 0.6], 'Speed': [9, 15], 'SpreadAngle': [180, 180],
            'Drag': 4, 'Orientation': 'VelocityParallel', 'Size': [[0, 0.7], [1, 0.25]], 'Squash': -2.2,
            'Transparency': [[0, 0], [0.7, 0.2], [1, 1]], 'Color': [[0, '#FFF6D8'], [1, '#FFB300']],
            'LightEmission': 1, 'LightInfluence': 0, 'Brightness': 2})
    # the ball trail: gold fire peels off the rolling ball (the concept's fiery trail)
    put(v['Trail']['Emitters'], {
        'Name': 'GoldFire', 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': {'Kind': 'Point'}, 'Rate': 10, 'Lifetime': [0.4, 0.6],
        'Speed': [0.2, 0.5], 'SpreadAngle': [60, 60], 'EmissionDirection': 'Top', 'Acceleration': [0, 1.5, 0],
        'Size': [[0, 0.3], [0.35, 0.55], [1, 0.2]], 'Transparency': [[0, 0.3], [0.3, 0.05], [1, 1]],
        'Color': [[0, '#FFF6D0'], [0.5, '#FFC030'], [1, '#FF8A00']], 'LightEmission': 1, 'LightInfluence': 0,
        'Brightness': 1.6})
    v['Budget']['BallTrail'] = sum(x.get('Rate', 0) for x in v['Trail']['Emitters'])
    v['Trail']['Note'] = ('A long half gold, half black light trail with a white-gold core (1.2 s); gold fire peels off '
                          'the ball, obsidian chips and gold sparks fly off, small eclipses drop behind and fade.')
    v['Pocket']['Note'] = ('Staged over 1.5 s: a dark ring pulses out flat over the pocket twice as it is eclipsed '
                           '(0 and 0.22 s, alpha-blended); a black eclipse swells above the pocket (0.4 s) exactly '
                           'filling its corona as the corona bursts out, in front of a column of gold light; gold '
                           'light streaks burst out radially, obsidian shards and gold sparks blast out, a gold ring '
                           'spreads; a gold flash. The default gust is tinted gold.')
    g = named(a['Emitters'], 'GoldSparks')
    g['Rate'] = 18
    a['Note'] = ('Solar flares lick off the corona (64-frame sheet) while the air round the cue darkens slightly '
                 '(black smoke, alpha-blended); molten-gold lightning crawls and leaps over the whole cue (Arcs); '
                 'gold fire licks up round the forearm and butt; gold sparks fly off the corona and glitter all '
                 'along the cue; obsidian chips drift and tumble round it; three wide gold orbit rings with small '
                 'eclipses at their heads circle the cue (Orbiters); a gold glow along the cue; a warm gold light '
                 'at the eclipse.')


UPGRADES = {'eclipse': eclipse}


def budget(d):
    """Refresh the Budget's particle numbers after an upgrade."""
    v = d['vfx']
    a = v.get('Aura') or {}
    b = v.get('Budget')
    if not b:
        return
    rate = sum(e.get('Rate', 0) for e in a.get('Emitters') or [])
    b['ParticlesPerSecond'] = round(rate, 1)
    b['Back'] = round(rate * a.get('BackRateScale', 0.5), 1)
    if a.get('Orbiters'):
        b['Orbiters'] = len(a['Orbiters'])
    if a.get('Arcs'):
        b['Arcs'] = sum(x.get('Count', 3) for x in a['Arcs'])


def main():
    want = set(sys.argv[1:])
    for name in sorted(os.listdir(SKINS)):
        if not name.endswith('.json'):
            continue
        path = os.path.join(SKINS, name)
        d = json.load(open(path))
        sid = d.get('id')
        if want and sid not in want:
            continue
        before = json.dumps(d, sort_keys=True)
        if d.get('vfx'):
            smooth(d['vfx'])
            if sid in UPGRADES:
                UPGRADES[sid](d)
                budget(d)
        if json.dumps(d, sort_keys=True) != before:
            with open(path, 'w') as fh:
                json.dump(d, fh, indent=2)
            print('CUE upgrade', sid, d['vfx'].get('Budget'))


if __name__ == '__main__':
    main()
