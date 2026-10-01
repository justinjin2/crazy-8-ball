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
    # designer, 2026-09-30: space, orbital, galaxy vibes round a glowing eclipse, not gold lightning
    # (the Arcs and the gold fire are gone). The orbital rings, planet-beads and asteroid belt are
    # 3D (CuePiecesMythic.eclipse); here: a spiral galaxy turning slowly behind the eclipse, dark
    # nebula clouds, twinkling stars and gold star dust round the cue, the corona sized to the
    # bigger eclipse sphere (radius 0.36, was 0.28)
    a.pop('Arcs', None)
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] not in ('GoldFlame', 'DarkVeil')]
    k = 0.36 / 0.28
    named(a['Emitters'], 'Corona')['Size'] = [[0, round(1.02 * k, 3)], [1, round(1.1 * k, 3)]]
    named(a['Emitters'], 'Flares')['Size'] = round(1.4 * k, 3)
    put(a['Emitters'], {
        'Name': 'Galaxy', 'Texture': 'vfx/eclipse/galaxy.png', 'Host': {'Kind': 'Attachment', 'AtStuds': 7.56},
        'Rate': 1.2, 'Lifetime': 2.5, 'Speed': 0, 'Size': [[0, 3.8], [1, 4.2]], 'Rotation': [0, 360],
        'RotSpeed': [14, 14], 'Transparency': [[0, 1], [0.3, 0.1], [0.7, 0.1], [1, 1]], 'Color': '#FFFFFF',
        'Brightness': 1.5, 'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': True, 'ZOffset': -0.8})
    put(a['Emitters'], {
        'Name': 'Nebula', 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(0.4, 7.6, 1.0), 'Rate': 4, 'Lifetime': [2.4, 3.2],
        'Speed': [0.02, 0.08], 'SpreadAngle': [180, 180], 'Size': [[0, 0.9], [1, 1.8]], 'Rotation': [0, 360],
        'RotSpeed': [-10, 10], 'Transparency': [[0, 1], [0.3, 0.72], [0.7, 0.78], [1, 1]],
        'Color': [[0, '#8A5A2A'], [1, '#3A2458']], 'LightEmission': 0.6, 'LightInfluence': 0, 'LockedToPart': False})
    put(a['Emitters'], {
        'Name': 'Stars', 'Texture': 'vfx/_shared/star4.png', 'Host': cyl(0.2, 7.8, 1.6) | {'ShapeStyle': 'Volume'},
        'Rate': 10, 'Lifetime': [0.8, 1.6], 'Speed': 0, 'Size': [[0, 0], [0.5, 0.14, 0.06], [1, 0]],
        'Rotation': [0, 45], 'Transparency': 0, 'Color': [[0, '#FFFFFF'], [1, '#FFE3A0']], 'LightEmission': 1,
        'LightInfluence': 0, 'LockedToPart': True})
    # designer, 2026-09-30: a giant eclipse behind the cue's back half, its ring like the concept's
    # (a black disc about half the cue long, a razor-thin white-gold rim, fiery wisps licking off
    # it). Camera-facing, so it is a disc from every side; ZOffset puts it behind
    # the cue and the 3D orbits, and the galaxy behind it. The disc and ring never turn and their
    # fades overlap exactly (a new one every 2 s fading in over 1 s as the oldest fades out), so
    # they hold steady; the wisps turn and cross-fade so the corona's flames churn.
    G = {'Kind': 'Attachment', 'AtStuds': 4.6}
    RG = 1.8                                        # the giant disc's radius, studs
    steady = [[0, 1], [0.2, 0], [0.8, 0], [1, 1]]
    put(a['Emitters'], {
        'Name': 'GiantEclipse', 'Texture': 'vfx/eclipse/giant_eclipse.png', 'Host': G, 'Rate': 0.5,
        'Lifetime': 5, 'Speed': 0, 'Size': round(2 * RG / 0.8, 3), 'Rotation': [0, 0], 'Transparency': steady,
        'Color': '#FFFFFF', 'LightEmission': 0, 'LightInfluence': 0, 'LockedToPart': True, 'ZOffset': -1.6})
    put(a['Emitters'], {
        'Name': 'GiantRing', 'Texture': 'vfx/eclipse/giant_corona.png', 'Host': G, 'Rate': 0.5,
        'Lifetime': 5, 'Speed': 0, 'Size': round(2 * RG / 0.5, 3), 'Rotation': [0, 0], 'Transparency': steady,
        'Color': '#FFFFFF', 'Brightness': 0.9, 'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': True,
        'ZOffset': -1.5})
    put(a['Emitters'], {
        'Name': 'GiantWisps', 'Texture': 'vfx/eclipse/giant_wisps.png', 'Host': G, 'Rate': 0.9,
        'Lifetime': 4, 'Speed': 0, 'Size': [[0, round(2 * RG / 0.5, 3)], [1, round(2.2 * RG / 0.5, 3)]],
        'Rotation': [0, 360], 'RotSpeed': [-6, 6], 'Transparency': [[0, 1], [0.3, 0.25], [0.7, 0.25], [1, 1]],
        'Color': '#FFFFFF', 'Brightness': 1.6, 'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': True,
        'ZOffset': -1.5})
    # (giant solar flares on its rim read as thick white tubes at that size: the wisps carry the flames)
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] != 'GiantFlares']
    gx = named(a['Emitters'], 'Galaxy')              # the galaxy now turns behind the giant eclipse
    gx.update({'Host': dict(G), 'Rate': 0.5, 'Lifetime': 5, 'Size': [[0, 8.0], [1, 8.4]], 'RotSpeed': [6, 6],
               'Transparency': [[0, 1], [0.2, 0.3], [0.8, 0.3], [1, 1]], 'Brightness': 1.3, 'ZOffset': -2.4})
    # the orbit loops round the cue: brighter, longer trails, like the concept's gold loops
    for o in a['Orbiters']:
        o['Radius'] = 0.38
        o['Wobble'] = 0.08
        o['Trail'].update({'Lifetime': 1.2, 'WidthStuds': 0.08, 'Brightness': 3,
                           'Transparency': [[0, 0], [0.6, 0.25], [1, 1]]})
        o['Head']['Size'] = 0.24
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
    g['Rate'] = 16                  # 18 until the giant eclipse needed the room
    a['Note'] = ('Space round a glowing eclipse (designer, 2026-09-30): behind the cue\'s back half a giant '
                 'eclipse about half the cue across, a black disc in a razor-thin white-gold ring with fiery '
                 'wisps churning off it, a spiral galaxy turning slowly behind it; two huge gold orbits sweep '
                 'round the cue and the eclipse, the cue running through them (3D, the piece); past the butt a '
                 'small black eclipse sphere in its blazing corona, solar flares licking off it; four gold '
                 'orbital rings circle the cue, tilted '
                 'every way like an atom\'s orbits, each precessing with a glowing planet running round it, and '
                 'an asteroid belt of dark rocks orbits the cue, tumbling (3D, the piece); three gold orbit '
                 'trails with small eclipses at their heads loop along the cue (Orbiters); dark nebula clouds '
                 'drift round it (alpha-blended), stars twinkle, gold star dust glitters, obsidian chips drift; '
                 'a gold glow along the cue and a warm gold light at the eclipse.')


def apex(d):
    v = d['vfx']
    a = v['Aura']
    E = a['Emitters']
    # more and bigger HUD rings (the concept has five or six along the cue at once; there were two)
    c = named(E, 'HudRingsCyan')
    c.update({'Rate': 1.6, 'Size': [[0, 0.7], [0.1, 1.45], [0.9, 1.45], [1, 1.8]], 'Brightness': 1.6})
    o = named(E, 'HudRingsOrange')
    o.update({'Rate': 1.2, 'Size': [[0, 0.9], [0.1, 1.7], [0.9, 1.7], [1, 2.1]], 'Brightness': 1.6})
    named(E, 'ScanPulses')['Rate'] = 2.0
    em = named(E, 'Embers')          # orange embers from the forearm back, twice as many
    em['Rate'] = 10
    em['Host']['FromStuds'] = 2.0
    # the circuit-trace runners: thick enough to read from the player's distance
    for r in a['Orbiters']:
        r['Trail'].update({'WidthStuds': 0.045, 'Lifetime': 0.6, 'Brightness': 3})
    # the ball trail's afterimage rings: bigger and longer-lived so a row of them hangs behind the ball
    T = v['Trail']['Emitters']
    named(T, 'RingsCyan').update({'Rate': 8, 'Lifetime': 0.7, 'Size': [[0, 0.35], [1, 0.75]]})
    named(T, 'RingsOrange').update({'Rate': 6, 'Lifetime': 0.6, 'Size': [[0, 0.4], [1, 0.8]]})
    v['Budget']['BallTrail'] = sum(x.get('Rate', 0) for x in T)


def kitsune(d):
    v = d['vfx']
    a = v['Aura']
    E = a['Emitters']
    # foxfire is violet: the white flame sheet takes the tint (the orange fire sheet turned it red)
    w = named(E, 'Wisps')
    w.update({'Texture': 'vfx/_shared/energy_flame_8x8.png', 'Size': [[0, 0.3], [0.4, 0.6], [1, 0.15]],
              'Color': [[0, '#FFD0F6'], [0.5, '#D070FF'], [1, '#7A30E0']], 'Brightness': 1.5})
    named(v['Pocket']['Layers'], 'Column').update({'Texture': 'vfx/_shared/energy_flame_8x8.png',
                                                    'Color': [[0, '#FFD0F6'], [0.5, '#D070FF'], [1, '#7A30E0']]})
    # kitsunebi: violet foxfire licking up all along the cue, and a faint violet haze round it
    put(E, {'Name': 'Foxfire', 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
            'FlipbookMode': 'OneShot', 'Host': cyl(0.4, 6.6, 0.2), 'Rate': 10, 'Lifetime': [0.6, 0.9],
            'Speed': [0.3, 0.6], 'SpreadAngle': [25, 25], 'EmissionDirection': 'Top', 'Acceleration': [0, 1.4, 0],
            'Size': [[0, 0.25], [0.35, 0.5], [1, 0.15]], 'Transparency': [[0, 0.35], [0.3, 0.1], [1, 1]],
            'Color': [[0, '#FFD0F6'], [0.5, '#C860FF'], [1, '#6A28D0']], 'LightEmission': 1, 'LightInfluence': 0,
            'Brightness': 1.5, 'LockedToPart': False})
    put(E, {'Name': 'Haze', 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
            'FlipbookMode': 'OneShot', 'Host': cyl(0.5, 7.3, 0.3), 'Rate': 5, 'Lifetime': [1.4, 2.0],
            'Speed': [0.05, 0.15], 'SpreadAngle': [180, 180], 'Acceleration': [0, 0.15, 0],
            'Size': [[0, 0.5], [1, 1.1]], 'Rotation': [0, 360], 'RotSpeed': [-20, 20],
            'Transparency': [[0, 1], [0.3, 0.72], [1, 1]], 'Color': [[0, '#E080FF'], [1, '#7A30E0']],
            'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False})
    # the foxfire orbs: bigger, with longer, wider trails
    for o in a['Orbiters']:
        o['Head']['Size'] = 0.46
        o['Trail'].update({'Lifetime': 0.85, 'WidthStuds': 0.12, 'Brightness': 2.6,
                           'Transparency': [[0, 0], [0.6, 0.3], [1, 1]], 'WidthScale': [[0, 1], [1, 0.3]]})
    # the mask is a generated model reaching 0.57 studs past the butt: the nine tails now stream
    # back from its collar along the handle (fanned round it), leaving its face clear
    for b in v['Moving']['Beams']:
        if b['Name'].startswith('Tail') and b['ToStuds'] > b['FromStuds']:   # not yet turned
            reach = b['ToStuds'] - b['FromStuds']            # 0.56-1.13 out past the butt before
            b['FromStuds'] = 6.9
            b['ToStuds'] = round(6.9 - 0.55 - 0.6 * reach, 3)
    a['Note'] = ('Layered: nine foxfire tails stream back from the mask along the handle (above); violet foxfire licks up all along the cue '
                 'and a faint violet haze drifts round it; three large foxfire orbs, each a glowing orb with a small '
                 'fox-mask face, circle the cue up and down it trailing long violet fire (Orbiters with a Head); '
                 'foxfire wisps lick up round the mask; cherry petals drift down; pink-violet sparkles; a violet '
                 'glow round the cue (a halo Beam) and a violet light at the mask. A small nine-tailed spirit fox '
                 '(the 3D piece, a violet hologram) gallops round and round the forearm, leaving a wisp of '
                 'foxfire behind it; it is aura and goes with the rest on the shooter\'s turn.')
    v['Piece']['Note'] = ('pieces/kitsune: FoxMask.glb, the generated mask as a hologram (Mask, EarLeft/Right, '
                          'Jaw), on the butt; RunningFox.glb, a small generated nine-tailed fox as a violet hologram, '
                          'on the bones FoxRun (root, a Spin round the forearm: its lap), FoxBody (rise and pitch each '
                          'stride), FoxFront and FoxHind (the legs, half a stride apart), FoxHead and FoxTails. The '
                          'fox\'s joints are Aura (hidden on the shooter\'s turn).')
    # designer, 2026-09-30: the running spirit fox (CuePiecesMythic._running_fox) sheds foxfire as
    # it runs (a short stretch of its back, as the builder prints it, riding its lap)
    put(a['Emitters'], {
        'Name': 'FoxTrail', 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Rate': 6, 'Lifetime': [0.4, 0.6], 'Speed': [0.02, 0.1],
        'SpreadAngle': [40, 40], 'EmissionDirection': 'Top', 'Acceleration': [0, 0.3, 0],
        'Size': [[0, 0.1], [0.4, 0.2], [1, 0.05]], 'Transparency': [[0, 0.4], [0.3, 0.15], [1, 1]],
        'Color': [[0, '#F6E6FF'], [0.5, '#C070FF'], [1, '#6A2AD8']], 'Brightness': 1.6, 'LightEmission': 1,
        'LightInfluence': 0, 'LockedToPart': False,
        'Host': {'Kind': 'Segment', 'Joint': 'FoxRun', 'From': [4.3, 0.527, 0.16], 'To': [4.3, 0.5, -0.07],
                 'Radius': 0.04}})


# the dragon's flame hosts: a short stretch of its back at each body bone and at the head, as the
# builder prints them (CuePiecesMythic.celestial_dragon: [AtStuds, Up, Side] in the rest pose;
# each rides its bone, so the flames peel off as the dragon swims round the cue)
DRAGON_FLAMES = [
    ('Body1', [6.35, -0.066, 0.252], [6.558, 0.069, 0.282]),
    ('Body2', [5.541, -0.181, -0.28], [5.744, -0.302, -0.196]),
    ('Body3', [4.708, 0.356, 0.086], [4.904, 0.388, -0.066]),
    ('Body4', [3.874, -0.336, 0.194], [4.064, -0.251, 0.332]),
    ('Body5', [3.064, 0.088, -0.4], [3.249, -0.077, -0.432]),
    ('Body6', [2.231, 0.223, 0.369], [2.41, 0.37, 0.275]),
    ('Body7', [1.413, -0.438, 0.231], [1.652, -0.365, 0.252]),
]
DRAGON_HEAD = [1.158, -0.445, 0.184]


def celestial_dragon(d):
    v = d['vfx']
    a = v['Aura']
    # designer, 2026-09-30: the whole spirit dragon coils round the cue (CuePiecesMythic): the
    # starlight runners that traced the old thin coil are gone; blue spirit flames peel off the
    # dragon's back all along it and off its head, left behind as it swims round the cue
    a.pop('Orbiters', None)
    v['Budget'].pop('Orbiters', None)
    flame = {'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8', 'FlipbookMode': 'OneShot',
             'Lifetime': [0.5, 0.8], 'Speed': [0.05, 0.2], 'SpreadAngle': [60, 60], 'EmissionDirection': 'Top',
             'Acceleration': [0, 0.3, 0], 'Size': [[0, 0.22], [0.4, 0.48], [1, 0.16]],
             'Transparency': [[0, 0.4], [0.3, 0.15], [1, 1]],
             'Color': [[0, '#EAF6FF'], [0.5, '#6FB8FF'], [1, '#2A5CE0']], 'Brightness': 1.5,
             'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False}
    a['Emitters'] = [e for e in a['Emitters'] if not e['Name'].startswith('SpiritFlames')]
    for jn, f0, f1 in DRAGON_FLAMES:
        e = dict(flame, Name='SpiritFlames' + jn[4:], Rate=2, Brightness=1.8,
                 Host={'Kind': 'Segment', 'Joint': jn, 'From': f0, 'To': f1, 'Radius': 0.04})
        a['Emitters'].append(e)
    w = named(a['Emitters'], 'Wisps')               # the mane's flames, on the head now
    w.update(dict(flame, Name='Wisps', Rate=6, Size=[[0, 0.25], [0.4, 0.5], [1, 0.15]], Brightness=1.6,
                  Host={'Kind': 'Segment', 'Joint': 'Head', 'From': DRAGON_HEAD,
                        'To': [DRAGON_HEAD[0] + 0.25, DRAGON_HEAD[1], DRAGON_HEAD[2] - 0.1], 'Radius': 0.08}))
    named(a['Emitters'], 'StarDust')['Rate'] = 18
    named(a['Emitters'], 'BlueLight')['Rate'] = 12
    a['Lights'][0]['AtStuds'] = 4.0                   # the head moved: the light lights the coil
    v['Piece']['Note'] = ('pieces/celestial_dragon: the spirit dragon as two skinned GLBs. DragonBody.glb: the body '
                          '(DragonBody, a SurfaceAppearance of translucent blue scales, AlphaMode Transparency), its '
                          'ForceField sheath, Neon core and Neon flame fins, on the bones Coil (root, a Spin round '
                          'the cue\'s axis) and Body1-7 (each a Bob a beat after the last: a wave down the body). '
                          'DragonHead.glb: the generated head as a hologram with its ForceField shell, on Head (riding '
                          'Body7), Jaw and Mane. Every joint is Aura (hidden on the shooter\'s turn); piece.json has '
                          'each pivot and motion, and each Bone\'s Transform is set as the report says (6.3).')
    a['Note'] = ('A spirit dragon of blue light coils round the cue (the 3D piece: its tail at the butt, 2.25 '
                 'turns up the cue, its head rising off it near the tip, a few inches short of it, roaring), swimming slowly round the cue with a '
                 'wave running down its body; blue spirit flames peel off its back all along it and off its '
                 'head and trail behind as it swims; drifting star dust (four-point stars twinkling in and out, '
                 'white to blue); soft blue light motes; a soft blue glow round the cue (a halo Beam, breathing) '
                 'and a blue light on the coil. The dragon is aura: it goes with the rest on the shooter\'s turn.')


def phoenix(d):
    v = d['vfx']
    a = v['Aura']
    # the wings are a 3D piece now (CuePiecesLegendary.phoenix), not flat flipbook sprites
    d['piece'] = 'phoenix'
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] not in ('WingRight', 'WingLeft')]
    # fire licks off each wing's leading edge and its primaries, riding the wing as it beats
    # (Segment hosts on the piece's joints: in Roblox, emitters parented to the wing parts)
    for side, sname in ((1, 'Right'), (-1, 'Left')):
        for jname, a0, a1, rate in (('Wing', [4.4, 0.06, 0.07 * side], [4.838, 0.476, 1.164 * side], 4),
                                    ('Primaries', [4.838, 0.476, 1.164 * side], [5.258, 0.875, 2.215 * side], 4)):
            put(a['Emitters'], {
                'Name': jname + 'Fire' + sname, 'Texture': 'vfx/_shared/fire_8x8.png', 'FlipbookLayout': 'Grid8x8',
                'FlipbookMode': 'OneShot', 'Host': {'Kind': 'Segment', 'Joint': jname + sname, 'From': a0, 'To': a1,
                                                    'Radius': 0.05},
                'Rate': rate, 'Lifetime': [0.4, 0.6], 'Speed': [0.1, 0.3], 'SpreadAngle': [30, 30],
                'EmissionDirection': 'Top', 'Acceleration': [0, 2.0, 0], 'Size': [[0, 0.3], [0.4, 0.55], [1, 0.15]],
                'Transparency': [[0, 0.4], [0.3, 0.1], [1, 1]], 'Color': '#FFFFFF', 'LightEmission': 1,
                'LightInfluence': 0, 'LockedToPart': False})
    pj = json.load(open(os.path.join(ROOT, 'assets', 'cue', 'pieces', 'phoenix', 'piece.json')))
    v['Budget']['PieceTriangles'] = pj['Triangles']


def kraken(d):
    v = d['vfx']
    a = v['Aura']
    # the tentacles are a 3D piece now (CuePiecesLegendary.kraken), not a flat flipbook
    d['piece'] = 'kraken'
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] != 'GhostTentacle']
    pj = json.load(open(os.path.join(ROOT, 'assets', 'cue', 'pieces', 'kraken', 'piece.json')))
    v['Budget']['PieceTriangles'] = pj['Triangles']


# white-hot to orange, ending orange-red (a crimson end left dark red flame tips floating off the cue)
HELLFIRE = [[0, '#FFF0B0'], [0.35, '#FFA030'], [0.75, '#FF5A14'], [1, '#D0280E']]


def infernal(d):
    v = d['vfx']
    a = v['Aura']
    # the horned skull is a 3D piece on the butt now (CuePiecesLegendary.infernal)
    d['piece'] = 'infernal'
    # hellfire from the white flame-tongue sheet tinted gold to orange to crimson (the orange
    # fire sheet tinted pink read as red drops): big flames wreathing the forearm and butt,
    # smaller licks along the shaft, both left behind as the cue moves
    for name, a0, a1, width, rate, life, size, accel in (
            ('Hellfire', 3.6, 7.0, 0.2, 24, [0.6, 0.95], [[0, 0.5], [0.35, 1.15], [1, 0.3]], 2.2),
            ('Licks', 0.4, 3.6, 0.12, 12, [0.4, 0.65], [[0, 0.28], [0.4, 0.62], [1, 0.15]], 1.6)):
        put(a['Emitters'], {
            'Name': name, 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
            'FlipbookMode': 'OneShot', 'Host': cyl(a0, a1, width), 'Rate': rate, 'Lifetime': life,
            'Speed': [0.3, 0.7], 'SpreadAngle': [20, 20], 'EmissionDirection': 'Top', 'Acceleration': [0, accel, 0],
            'Size': size, 'Transparency': [[0, 0.3], [0.2, 0.0], [0.6, 0.35], [0.85, 1], [1, 1]],
            'Rotation': [-12, 12],
            'Color': HELLFIRE, 'Brightness': 1.5, 'LightEmission': 0.6, 'LightInfluence': 0, 'LockedToPart': False})
    for o in a.get('Orbiters') or []:
        o['Trail'].update({'Lifetime': 0.8, 'WidthStuds': 0.28, 'WidthScale': [[0, 1], [0.6, 0.7], [1, 0.3]],
                           'Transparency': [[0, 0], [0.6, 0.15], [1, 1]]})
    # pocket: the eruption kept from turning pink over the felt
    P = v['Pocket']['Layers']
    e = named(P, 'Eruption')
    # (the orange fire sheet, not the flame tongues: at this size and speed they streak to ribbons)
    e.update({'Burst': 24, 'Color': [[0, '#FFFFFF'], [0.5, '#FFC8A8'], [1, '#FF7050']], 'Brightness': 1.4,
              'LightEmission': 0.5})
    t = v['Trail']
    named(t['Emitters'], 'Flames').update({'Texture': 'vfx/_shared/energy_flame_8x8.png', 'Color': HELLFIRE,
                                            'Brightness': 1.4, 'LightEmission': 0.5, 'Rate': 10,
                                            'Size': [[0, 0.3], [1, 0.5]]})
    v['Budget']['BallTrail'] = sum(x.get('Rate', 0) for x in t['Emitters'])
    # the trail's red-hot core orange rather than red (red read pink down the middle)
    v['Style']['Trail']['Core']['Color'] = [255, 122, 26]
    a['Note'] = ('Layered: hellfire wreathes the handle (big flames from the forearm to the butt and '
                 'smaller licks along the shaft, the white flame-tongue flipbook tinted gold to orange to '
                 'crimson, left behind as the cue moves); three ribbons of black-and-red fire wind round the '
                 'cue; dark smoke rolls off the butt; ember sparks rise; a deep red glow round the cue (a halo '
                 'Beam, flickering) and a flickering red light. The horned skull on the butt is a 3D piece.')


def clockwork(d):
    v = d['vfx']
    a = v['Aura']
    # the gears are a 3D piece now (CuePiecesLegendary.clockwork): meshing brass and copper gears
    # turning on the forearm, the butt and the shaft, in place of the flat floating cog sprites
    d['piece'] = 'clockwork'
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] != 'BigCogs']
    named(a['Emitters'], 'Steam')['Rate'] = 10
    for o in a.get('Orbiters') or []:
        o['Trail'].update({'Lifetime': 1.1, 'WidthStuds': 0.08})
    a['Note'] = ('Layered: brass and copper gears turn on the cue, meshing pairs rolling together (a 3D '
                 'piece: a pair on top of the forearm and one on its side, a cluster round the butt, small '
                 'gears on the shaft, hubs glowing amber); glowing brass loops spiral round the cue (three '
                 'Orbiters with bright amber trails); tiny cogs drop off and fall; steam puffs rise from the '
                 'handle; brass sparks spit; a warm amber glow round the cue (a halo Beam) and an amber light.')
    # pocket: three big meshing gears rise out of the pocket turning (a 3D piece) among the burst
    # of small cogs; the flat big-cog layer goes
    P = v['Pocket']['Layers']
    P[:] = [x for x in P if x['Name'] != 'BigCogs']


def thunderstrike(d):
    v = d['vfx']
    a = v['Aura']
    # the arcs sat at the cue's own surface (radius 0.1, hidden inside it) and were hair-thin with
    # no brightness, so they read as faint grey zigzags: out off the surface, thicker, longer,
    # brighter and more of them, the leaps bowing well clear of the cue; finely jagged (many short
    # segments: few long ones read as bent wire) and wide enough that the strip's blue glow shows
    put(a['Arcs'], {'Name': 'Crawl', 'Count': 5, 'Segments': 20, 'FromStuds': 0.3, 'ToStuds': 7.0,
                    'Length': [0.8, 1.8], 'Around': 220, 'Radius': 0.15, 'Jitter': 0.06, 'Interval': 0.09,
                    'Duty': 0.75, 'WidthStuds': 0.16, 'Color': '#5AAEFF', 'Brightness': 2.2,
                    'Texture': 'vfx/_shared/bolt_strip.png'})
    put(a['Arcs'], {'Name': 'Leap', 'Count': 3, 'Segments': 26, 'FromStuds': 0.8, 'ToStuds': 7.0,
                    'Length': [1.6, 3.2], 'Around': 300, 'Radius': 0.2, 'Jitter': 0.11, 'Interval': 0.14,
                    'Duty': 0.55, 'WidthStuds': 0.2, 'Color': '#7AC0FF', 'Brightness': 2.4,
                    'Texture': 'vfx/_shared/bolt_strip.png'})
    # the concept's blue electric haze round the whole cue
    put(a['Emitters'], {
        'Name': 'StormHaze', 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(0.3, 7.0, 0.35), 'Rate': 6, 'Lifetime': [1.0, 1.5],
        'Speed': [0.05, 0.15], 'SpreadAngle': [180, 180], 'Size': [[0, 0.4], [1, 0.9]], 'Rotation': [0, 360],
        'RotSpeed': [-25, 25], 'Transparency': [[0, 1], [0.3, 0.7], [1, 1]],
        'Color': [[0, '#4A9AFF'], [1, '#1A3AA0']], 'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False})
    # the trail: a wider electric sheath, more crackling static round the ball
    v['Style']['Trail']['WidthStuds'] = 0.5
    st = named(v['Trail']['Emitters'], 'Static')
    st.update({'Rate': 10, 'Size': 0.5})
    v['Budget']['BallTrail'] = sum(x.get('Rate', 0) for x in v['Trail']['Emitters'])
    a['Note'] = ('Layered: a flickering blue glow round the cue as the core (a halo Beam) inside a haze of blue '
                 'electric mist; lightning arcs crawl up and down the whole cue just off its surface, re-struck '
                 'every 0.09 s, and big arcs leap well clear of it (Arcs: chains of short Beams a script '
                 're-jitters); a small storm cloud of static churns round the butt (dark cloud puffs with '
                 'crackling static balls inside); blue sparks spit off and charge motes hang in the air; a blue '
                 'light, and a second one that cracks bright twice every 1.7 s.')


def seraph(d):
    v = d['vfx']
    a = v['Aura']
    # the halo is a 3D ring of gold light now (CuePiecesLegendary.seraph), not two orbiter trails
    d['piece'] = 'seraph'
    a['Orbiters'] = [o for o in a['Orbiters'] if not o['Name'].startswith('Halo')]
    for o in a['Orbiters']:
        o['Trail'].update({'Lifetime': 1.1, 'WidthStuds': 0.2})
    # more feathers, tumbling smoothly (64 frames: they live three seconds)
    f = named(a['Emitters'], 'Feathers')
    f.update({'Texture': 'vfx/seraph/feather_white_8x8.png', 'FlipbookLayout': 'Grid8x8', 'Rate': 9,
              'FlipbookFramerate': [16, 24]})
    # the concept's golden light round the cue
    put(a['Emitters'], {
        'Name': 'GoldenLight', 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(0.5, 7.2, 0.35), 'Rate': 5, 'Lifetime': [1.4, 2.0],
        'Speed': [0.05, 0.15], 'SpreadAngle': [180, 180], 'Acceleration': [0, 0.15, 0],
        'Size': [[0, 0.5], [1, 1.1]], 'Rotation': [0, 360], 'RotSpeed': [-20, 20],
        'Transparency': [[0, 1], [0.3, 0.72], [1, 1]], 'Color': [[0, '#FFF0C0'], [1, '#FFC860']],
        'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False})
    pf = named(v['Pocket']['Layers'], 'Feathers')
    pf.update({'Texture': 'vfx/seraph/feather_white_8x8.png', 'FlipbookLayout': 'Grid8x8', 'Burst': 16,
               'FlipbookFramerate': 36})
    a['Note'] = ('Layered: a halo of golden light floats just beyond the butt (a 3D ring: a glowing gold core in '
                 'a shimmering sheath, bobbing and swaying, over a soft breathing glow); three ribbons of golden '
                 'light wind round the cue (Orbiters with a gold strand trail made for Seraph) in a haze of '
                 'golden light; soft white feathers drift down, tumbling as they fall (a 64-frame feather '
                 'flipbook made for Seraph); gold motes rise and sparkles glint; a warm glow round the cue (a '
                 'halo Beam) and a warm light.')


def chroma(d):
    v = d['vfx']
    a = v['Aura']
    # the crystal shards are a 3D piece now (CuePiecesLegendary.chroma): eight faceted rainbow
    # crystals orbiting and tumbling, in place of the small flat shard sprites
    d['piece'] = 'chroma'
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] != 'Shards']
    named(a['Emitters'], 'RainbowSparkles')['Rate'] = 24
    # the rainbow ribbons: bold bands of light, not hairlines
    for o in a['Orbiters']:
        o['Trail'].update({'Lifetime': 0.9, 'WidthStuds': 0.14, 'Brightness': 2.2,
                           'WidthScale': [[0, 1], [0.6, 0.7], [1, 0.25]],
                           'Transparency': [[0, 0], [0.6, 0.15], [1, 1]]})
        if o.get('Head'):
            o['Head']['Size'] = 0.3
    a['Note'] = ('Layered: a soft rainbow glow round the whole cue (a halo Beam graded red at the tip to violet '
                 'at the butt, breathing) as the core; four bold rainbow ribbons loop round the stick (Orbiters '
                 'with a rainbow-textured Trail and a white star head, up and down it at different speeds, the '
                 "concept's loops); eight faceted crystal shards, red through violet, orbit the cue and tumble "
                 '(a 3D piece: see-through shimmering crystal over a glowing core); rainbow sparkles and glitter '
                 'dust fill the air; a light whose colour cycles with the cue.')


# --- the Epics (designer 2026-09-30: auras underwhelming next to their concepts) ---------------
# Epics keep their particle budget (35 a second), so the density comes from bigger particles that
# live longer, from Orbiter ribbons (no particles) and from Arcs and Beams.

def grow(e, base, k):
    """Set an emitter's Size to its original size `base` (a number, or [time, value(, envelope)]
    keys, as the skin had it before this pass) scaled by k: from the original, so running the pass
    again changes nothing."""
    if isinstance(base, (int, float)):
        e['Size'] = round(base * k, 3)
    else:
        e['Size'] = [[p[0], round(p[1] * k, 3)] + [round(x * k, 3) for x in p[2:]] for p in base]


def haze(name, a0, a1, cols, rate=5, lift=0.15, fade=0.72):
    """A faint cloud of coloured light round the cue (the concepts' glowing mist)."""
    return {'Name': name, 'Texture': 'vfx/_shared/smoke_8x8.png', 'FlipbookLayout': 'Grid8x8',
            'FlipbookMode': 'OneShot', 'Host': cyl(a0, a1, 0.35), 'Rate': rate, 'Lifetime': [1.4, 2.0],
            'Speed': [0.05, 0.15], 'SpreadAngle': [180, 180], 'Acceleration': [0, lift, 0],
            'Size': [[0, 0.5], [1, 1.1]], 'Rotation': [0, 360], 'RotSpeed': [-20, 20],
            'Transparency': [[0, 1], [0.3, fade], [1, 1]], 'Color': [[0, cols[0]], [1, cols[1]]],
            'LightEmission': 1, 'LightInfluence': 0, 'LockedToPart': False}


def ribbons(a, width, life, radius=None, head=None, bright=None):
    for i, o in enumerate(a.get('Orbiters') or []):
        o['Trail'].update({'WidthStuds': width, 'Lifetime': life})
        if bright:
            o['Trail']['Brightness'] = bright
        if radius:
            o['Radius'] = radius[i % len(radius)]
        if head and o.get('Head'):
            o['Head']['Size'] = head


def extra_orbiters(a, n, radius, phase0=45, delay0=0.4):
    """n more orbiters copied from the first (another phase, speed and delay each)."""
    base = a['Orbiters'][0]
    have = len(a['Orbiters'])
    for j in range(n):
        o = json.loads(json.dumps(base))
        o['Name'] = '%s%d' % (base['Name'].rstrip('0123456789'), have + j + 1)
        o['Radius'] = radius[j % len(radius)]
        o['Phase'] = (phase0 + 97 * j) % 360
        o['Delay'] = round(delay0 + 0.5 * j, 2)
        o['TurnsPerSecond'] = round(-o.get('TurnsPerSecond', 1.0) * (0.9 + 0.1 * j), 2)
        o['TravelSeconds'] = round(o.get('TravelSeconds', 2.6) * (1.1 + 0.1 * j), 2)
        a['Orbiters'].append(o)


def aurora(d):
    a = d['vfx']['Aura']
    # the concept's curtains of light swirl wide round the cue: wider ribbons further out, four of them
    if len(a['Orbiters']) < 4:
        extra_orbiters(a, 1, [0.44])
    ribbons(a, 0.22, 1.2, radius=[0.3, 0.38, 0.26, 0.44], bright=1.8)
    m = named(a['Emitters'], 'Motes')
    grow(m, [[0, 0], [0.3, 0.07], [0.7, 0.06], [1, 0]], 1.8)
    m['Rate'] = 16
    named(a['Emitters'], 'Sparkles')['Rate'] = 7
    put(a['Emitters'], haze('AuroraVeil', 0.3, 7.0, ['#2BF0B0', '#7A5CFF']))


def blood_moon(d):
    a = d['vfx']['Aura']
    # the mist read as red blobs (even fainter): gone, its budget to the concept's red energy, as
    # arcs crackling round the cue and red flame tongues licking off it
    a['Emitters'] = [e for e in a['Emitters'] if e['Name'] != 'CrimsonMist']
    put(a['Emitters'], {
        'Name': 'BloodFlame', 'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8',
        'FlipbookMode': 'OneShot', 'Host': cyl(0.4, 7.0, 0.14), 'Rate': 18, 'Lifetime': [0.6, 0.9],
        'Speed': [0.3, 0.6], 'SpreadAngle': [25, 25], 'EmissionDirection': 'Top', 'Acceleration': [0, 1.4, 0],
        'Size': [[0, 0.4], [0.35, 0.9], [1, 0.25]], 'Transparency': [[0, 0.3], [0.2, 0.0], [0.6, 0.35], [0.9, 1], [1, 1]],
        'Rotation': [-12, 12], 'Color': [[0, '#FFB0B0'], [0.35, '#FF3040'], [1, '#A00818']], 'Brightness': 1.5,
        'LightEmission': 0.6, 'LightInfluence': 0, 'LockedToPart': False})
    named(a['Emitters'], 'RedMotes')['Rate'] = 10
    a['Arcs'] = [{'Name': 'BloodArcs', 'Count': 4, 'Segments': 18, 'FromStuds': 0.5, 'ToStuds': 7.0,
                  'Length': [0.8, 1.8], 'Around': 240, 'Radius': 0.16, 'Jitter': 0.08, 'Interval': 0.12,
                  'Duty': 0.6, 'WidthStuds': 0.14, 'Color': '#FF2A3A', 'Brightness': 2.2,
                  'Texture': 'vfx/_shared/bolt_strip.png'}]


def disco(d):
    a = d['vfx']['Aura']
    # the concept is a storm of coloured light: bigger specks and glints, the spotlights brighter
    # with longer tails
    s_ = named(a['Emitters'], 'LightSpecks')
    grow(s_, [[0, 0], [0.2, 0.09], [0.8, 0.09], [1, 0]], 1.8)
    s_['Rate'] = 20
    g = named(a['Emitters'], 'MirrorGlints')
    grow(g, [[0, 0], [0.5, 0.25], [1, 0]], 1.5)
    g['Rate'] = 14
    ribbons(a, 0.16, 0.8, radius=[0.32, 0.28, 0.36, 0.3], head=0.45)


def hacked(d):
    v = d['vfx']
    a = v['Aura']
    # the concept is a curtain of falling code: bigger digits, living longer, and green data
    # streams winding round the cue (Orbiters with the skin's data trail)
    r = named(a['Emitters'], 'DigitRain')
    grow(r, [[0, 0.12, 0.03], [1, 0.12, 0.03]], 1.6)
    r.update({'Rate': 28, 'Lifetime': [1.3, 1.8]})
    named(a['Emitters'], 'Glitch')['Rate'] = 4
    a['Orbiters'] = [
        {'Name': 'DataStream%d' % (i + 1), 'FromStuds': 0.3, 'ToStuds': 7.0, 'TravelSeconds': 2.4 + 0.5 * i,
         'Loop': 'pingpong', 'TurnsPerSecond': (0.8 if i % 2 == 0 else -0.7), 'Radius': 0.28 + 0.08 * i,
         'Phase': 120 * i, 'Delay': 0.7 * i,
         'Trail': {'Lifetime': 1.0, 'WidthStuds': 0.16, 'Color': '#6BFF8A', 'Brightness': 1.8,
                   'Transparency': [[0, 0], [0.6, 0.2], [1, 1]], 'WidthScale': [[0, 1], [1, 0.4]],
                   'LightEmission': 1, 'Texture': v['Style']['Trail']['Texture'], 'TextureMode': 'Stretch'}}
        for i in range(3)]


def magma(d):
    a = d['vfx']['Aura']
    # the flames were the orange fire sheet tinted, reading as drops: flame tongues from the white
    # sheet in hellfire colours (as Infernal), bigger; bigger lava drips
    l_ = named(a['Emitters'], 'Licks')
    l_.update({'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8', 'Rate': 16,
               'Lifetime': [0.6, 0.9], 'Size': [[0, 0.45], [0.35, 1.1], [1, 0.3]], 'Color': HELLFIRE,
               'Brightness': 1.5, 'LightEmission': 0.6,
               'Transparency': [[0, 0.3], [0.2, 0.0], [0.6, 0.35], [0.85, 1], [1, 1]]})
    grow(named(a['Emitters'], 'LavaDrips'), [[0, 0.03], [0.25, 0.11], [1, 0.09]], 1.4)
    named(a['Emitters'], 'Embers')['Rate'] = 10
    named(a['Emitters'], 'Smoke')['Rate'] = 3


def prism(d):
    a = d['vfx']['Aura']
    # the concept's crystals float big round the cue in a glitter of light: bigger, more shards
    # and glints, four refraction ribbons with longer spectrum tails, a pale haze
    sh = named(a['Emitters'], 'Shards')
    grow(sh, [[0, 0], [0.2, 0.16, 0.04], [0.8, 0.16, 0.04], [1, 0]], 1.75)
    sh['Rate'] = 12
    gl = named(a['Emitters'], 'PrismGlints')
    grow(gl, [[0, 0], [0.4, 0.28], [1, 0]], 1.4)
    gl['Rate'] = 14
    if len(a['Orbiters']) < 4:
        extra_orbiters(a, 2, [0.26, 0.42])
    ribbons(a, 0.14, 0.8, radius=[0.3, 0.36, 0.26, 0.42], head=0.26, bright=1.8)
    put(a['Emitters'], haze('PrismHaze', 0.3, 7.0, ['#E8F4FF', '#C8B8FF'], rate=5, fade=0.8))


def shooting_star(d):
    a = d['vfx']['Aura']
    # the concept's golden comet streaks sweep wide: brighter, longer, wider star trails
    ribbons(a, 0.1, 1.1, head=0.36, bright=2.0)
    grow(named(a['Emitters'], 'Twinkles'), [[0, 0], [0.5, 0.2], [1, 0]], 1.5)
    for b in a.get('Beams') or []:
        if b['Name'].startswith('StarStream'):
            b.update({'Width0': 0.08, 'Width1': 0.2})


def toxic(d):
    a = d['vfx']['Aura']
    # the concept is thick with bubbles and green fumes: bigger, more of both, a green haze
    b = named(a['Emitters'], 'Bubbles')
    grow(b, [[0, 0.06], [0.6, 0.2, 0.05], [1, 0.23, 0.05]], 1.6)
    b['Rate'] = 14
    f = named(a['Emitters'], 'Fumes')
    grow(f, [[0, 0.1], [1, 0.3]], 2.0)
    f['Rate'] = 7
    grow(named(a['Emitters'], 'GooDrips'), [[0, 0.02], [0.3, 0.07], [1, 0.06]], 1.4)
    put(a['Emitters'], haze('ToxicHaze', 0.3, 7.0, ['#9BFF3A', '#2E8A10'], rate=5, lift=0.3))


def void(d):
    v = d['vfx']
    a = v['Aura']
    # the concept's dark energy swirls round the cue with shards of rock pulled in: bigger
    # particles, and two violet energy ribbons winding round it (Orbiters with the smoke trail)
    grow(named(a['Emitters'], 'PulledIn'), [[0, 0.08], [0.3, 0.22], [1, 0.0]], 1.4)
    grow(named(a['Emitters'], 'DarkMatter'), [[0, 0.75], [1, 0.2]], 1.3)
    grow(named(a['Emitters'], 'Shards'), [[0, 0.02], [0.2, 0.11], [1, 0.02]], 1.8)
    a['Orbiters'] = [
        {'Name': 'VoidRibbon%d' % (i + 1), 'FromStuds': 0.3, 'ToStuds': 7.0, 'TravelSeconds': 2.8 + 0.6 * i,
         'Loop': 'pingpong', 'TurnsPerSecond': (0.9 if i == 0 else -0.8), 'Radius': 0.3 + 0.08 * i,
         'Wobble': 0.05, 'WobbleHz': 0.8, 'Phase': 180 * i, 'Delay': 0.9 * i,
         'Trail': {'Lifetime': 1.0, 'WidthStuds': 0.22, 'Color': '#C8A0FF', 'Brightness': 1.6,
                   'Transparency': [[0, 0], [0.6, 0.2], [1, 1]], 'WidthScale': [[0, 1], [1, 0.4]],
                   'LightEmission': 0.8, 'Texture': v['Style']['Trail']['Texture'], 'TextureMode': 'Stretch'}}
        for i in range(2)]


def pocket_piece(d, piece_id, drop_layer, **timing):
    """The pocket finisher's creature as a rising 3D piece (CuePiecesPocket) in place of its flat
    flipbook layer."""
    P = d['vfx']['Pocket']
    P['Layers'] = [x for x in P['Layers'] if x['Name'] != drop_layer]
    spec = {'Piece': piece_id, 'Delay': 0.1, 'Seconds': 1.35}
    spec.update(timing)
    P['Piece'] = spec
    # the default swirl ribbons would cross in front of the creature
    P['KeepRibbons'] = False
    pj = json.load(open(os.path.join(ROOT, 'assets', 'cue', 'pieces', piece_id, 'piece.json')))
    d['vfx']['Budget']['PocketPieceTriangles'] = pj['Triangles']


# ---- Rares (at most 20 particles a second; Orbiters, Beams and Arcs are not particles) ----------

def ribbon(name, colors, radius, width=0.1, life=1.4, turns=0.8, travel=2.6, phase=0, delay=0.0,
           wobble=0.05, le=1, bright=2.2, texture='vfx/_shared/trail_soft.png'):
    """An Orbiter carrying a soft ribbon of light round the cue, tip to butt and back: the soft
    band, fully additive (the thin wisp texture read as grey threads)."""
    return {'Name': name, 'FromStuds': 0.3, 'ToStuds': 7.0, 'TravelSeconds': travel, 'Loop': 'pingpong',
            'TurnsPerSecond': turns, 'Radius': radius, 'Wobble': wobble, 'WobbleHz': 0.9, 'Phase': phase,
            'Delay': delay,
            'Trail': {'Lifetime': life, 'WidthStuds': width, 'Color': colors, 'Brightness': bright,
                      'Transparency': [[0, 0.05], [0.6, 0.3], [1, 1]], 'WidthScale': [[0, 1], [1, 0.35]],
                      'LightEmission': le, 'Texture': texture, 'TextureMode': 'Stretch'}}


def soft_band(a):
    """An aura's ribbons on the soft glowing band, fully additive (the thin wisp texture read as
    faint grey threads)."""
    for o in a.get('Orbiters') or []:
        o['Trail'].update({'Texture': 'vfx/_shared/trail_soft.png', 'TextureMode': 'Stretch', 'LightEmission': 1})
        o['Trail'].pop('TextureLength', None)


def rare_pocket(d):
    """(assumption) Rares add no pocket layers, but the default gust is tinted in the skin's own
    colours (the trail and its core) for most of its particles instead of the potted ball's."""
    t = d['vfx']['Style']['Trail']
    cols = [list(c) for c in (t.get('Colors') or [t['Color']])]
    if t.get('Core', {}).get('Color'):
        cols.append(list(t['Core']['Color']))
    d['vfx']['Style']['Pocket'] = {'Colors': cols, 'ColorShare': 0.7}
    d['vfx']['Pocket']['Note'] = ("The default gust, most of it in the skin's own colours (Rares add no layers).")


def upgraded(a, text):
    """Append the pass's note to the aura's Note (once)."""
    a['Note'] = a['Note'].split(' Upgraded 2026-09-30:')[0] + ' Upgraded 2026-09-30: ' + text


def blaze(d):
    a = d['vfx']['Aura']
    f = named(a['Emitters'], 'Flames')
    grow(f, [[0, 0.5], [0.3, 1.1], [1, 0.6]], 1.4)
    f['Lifetime'] = [0.75, 1.05]                       # longer-lived, so the tongues overlap into a blaze
    grow(named(a['Emitters'], 'Embers'), [[0, 0.05], [1, 0.02]], 1.8)
    named(a['Beams'], 'HeatGlow').update({'Width0': 0.45, 'Width1': 0.95})
    upgraded(a, 'the flame tongues 40% bigger and longer-lived so they run together, bigger embers, a wider heat glow.')
    rare_pocket(d)


def candy(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'Sprinkles'), [[0, 0.13], [1, 0.13]], 1.7)
    grow(named(a['Emitters'], 'Sugar'), [[0, 0], [0.5, 0.1], [1, 0]], 1.6)
    if len(a['Orbiters']) < 2:
        extra_orbiters(a, 1, [0.3], phase0=180, delay0=0.9)
    ribbons(a, 0.13, 1.6, radius=[0.22, 0.3])
    put(a['Emitters'], haze('SugarHaze', 0.3, 7.0, ['#FFB8D0', '#FFFFFF'], rate=2, fade=0.8))
    upgraded(a, 'two candy-stripe ribbons winding round the cue (wider, longer), sprinkles and sugar sparkles '
                'bigger, a faint pink sugar haze.')
    rare_pocket(d)


def frostbite(d):
    a = d['vfx']['Aura']
    s_ = named(a['Emitters'], 'Snowflakes')
    grow(s_, [[0, 0.1], [1, 0.13]], 1.8)
    s_['Rate'] = 9
    grow(named(a['Emitters'], 'FrostGlints'), [[0, 0], [0.5, 0.12], [1, 0]], 1.6)
    named(a['Emitters'], 'ColdMist')['Rate'] = 6
    ice = [[0, '#FFFFFF'], [0.45, '#9EE6FF'], [1, '#3A8BD8']]
    a['Orbiters'] = [ribbon('FrostRibbon1', ice, 0.26, width=0.16, turns=0.7, travel=2.8, le=1, bright=2.4),
                     ribbon('FrostRibbon2', ice, 0.32, width=0.13, turns=-0.6, travel=3.2, phase=180, delay=1.0,
                            le=1, bright=2.4)]
    upgraded(a, 'two icy ribbons of frost wind round the cue, snowflakes nearly twice the size, bigger glints.')
    rare_pocket(d)


def honeycomb(d):
    a = d['vfx']['Aura']
    b = named(a['Emitters'], 'Bees')
    grow(b, [[0, 0], [0.1, 0.36], [0.9, 0.36], [1, 0]], 1.35)
    b['Rate'] = 4
    grow(named(a['Emitters'], 'HoneyDrops'), [[0, 0.05], [0.2, 0.12], [1, 0.1]], 1.4)
    named(a['Emitters'], 'Glints')['Rate'] = 6
    a['Orbiters'] = [ribbon('HoneyRibbon', [[0, '#FFF8D0'], [0.5, '#FFD050'], [1, '#FFA020']], 0.3,
                            width=0.14, turns=0.6, travel=3.0, le=1, bright=2.4)]
    upgraded(a, 'a ribbon of golden honey light winds round the cue, bigger bees (four a second) and honey drops.')
    rare_pocket(d)


def nature(d):
    a = d['vfx']['Aura']
    lv = named(a['Emitters'], 'Leaves')
    grow(lv, [[0, 0.2], [1, 0.22]], 1.6)
    lv['Rate'] = 8
    bl = named(a['Emitters'], 'Blossoms')
    grow(bl, [[0, 0.14], [1, 0.15]], 1.8)
    bl['Rate'] = 3
    vine = [[0, '#E8FFB0'], [0.5, '#5FD84A'], [1, '#1E7A2A']]
    a['Orbiters'] = [ribbon('Vine1', vine, 0.2, width=0.12, turns=0.55, travel=3.2, bright=2.4),
                     ribbon('Vine2', vine, 0.24, width=0.1, turns=0.5, travel=3.6, phase=180, delay=1.2,
                            bright=2.4)]
    upgraded(a, 'two glowing green vines twine round the cue, leaves and blossoms bigger and more of them.')
    rare_pocket(d)


def neon(d):
    a = d['vfx']['Aura']
    ribbons(a, 0.075, 1.4, head=0.22, bright=2.4)
    for n in ('PinkSparks', 'CyanSparks'):
        e = named(a['Emitters'], n)
        grow(e, [[0, 0.07], [1, 0.02]], 1.5)
        e['Rate'] = 7
    put(a['Emitters'], haze('NeonHaze', 0.3, 7.0, ['#FF2BD6', '#2BF0FF'], rate=5, fade=0.8))
    upgraded(a, 'the neon tubes thicker with longer glowing tails and bigger heads, bigger sparks, a pink-and-cyan haze.')
    rare_pocket(d)


def phantom(d):
    a = d['vfx']['Aura']
    g = named(a['Emitters'], 'Ghosts')
    grow(g, [[0, 0.18], [0.2, 0.45], [1, 0.48]], 1.35)
    g['Rate'] = 2
    sm = named(a['Emitters'], 'GhostSmoke')
    grow(sm, [[0, 0.2], [1, 0.6]], 1.4)
    sm['Rate'] = 5
    mo = named(a['Emitters'], 'SpiritMotes')
    grow(mo, [[0, 0], [0.3, 0.05], [1, 0]], 1.6)
    mo['Rate'] = 7
    spirit = [[0, '#FFFFFF'], [0.5, '#9FF5E6'], [1, '#4FB8C8']]
    a['Orbiters'] = [ribbon('SpiritTrail1', spirit, 0.3, width=0.2, life=1.6, turns=0.5, travel=3.4, wobble=0.1,
                            bright=2.4),
                     ribbon('SpiritTrail2', spirit, 0.36, width=0.16, life=1.6, turns=-0.45, travel=3.8,
                            phase=180, delay=1.4, wobble=0.1, bright=2.4)]
    upgraded(a, 'two pale spirit trails drift round the cue, the ghosts a third bigger and more of them, more smoke '
                'and motes.')
    rare_pocket(d)


def plasma(d):
    a = d['vfx']['Aura']
    # the arcs sat inside the cue (Radius 0.12) and read as bent wire (7-10 segments): off the
    # surface, finely jagged, a little wider (the Arc standard, see Thunderstrike)
    arcs = {x['Name']: x for x in a['Arcs']}
    arcs['HandleArcs'].update({'Radius': 0.18, 'Segments': 18, 'Jitter': 0.075, 'WidthStuds': 0.12, 'Count': 5})
    arcs['ShaftArcs'].update({'Radius': 0.16, 'Segments': 20, 'Jitter': 0.07, 'WidthStuds': 0.1, 'Count': 4})
    arcs['FarArcs'].update({'Radius': 0.34, 'Segments': 24, 'Jitter': 0.09, 'WidthStuds': 0.1})
    # at Brightness 3 the pale violet blew out to white: saturated violet at the standard 2.3
    for x, col in (('HandleArcs', '#A868FF'), ('ShaftArcs', '#9A58FF'), ('FarArcs', '#C090FF')):
        arcs[x].update({'Color': col, 'Brightness': 2.3})
    grow(named(a['Emitters'], 'PlasmaSparks'), [[0, 0.08], [1, 0.02]], 1.4)
    hz = named(a['Emitters'], 'PlasmaHaze')
    grow(hz, [[0, 0.2], [0.5, 0.45], [1, 0.3]], 1.5)
    put(a['Emitters'], haze('PlasmaVeil', 0.3, 7.0, ['#C99BFF', '#6A3AFF'], rate=4, fade=0.8))
    upgraded(a, 'more arcs, standing off the cue, finely jagged and wider, bigger sparks and glow, a violet veil.')
    rare_pocket(d)


def sakura(d):
    a = d['vfx']['Aura']
    p = named(a['Emitters'], 'Petals')
    grow(p, [[0, 0.09], [1, 0.11]], 1.8)
    p['Rate'] = 12
    grow(named(a['Emitters'], 'PinkMotes'), [[0, 0], [0.3, 0.06], [1, 0]], 1.5)
    if len(a['Orbiters']) < 2:
        extra_orbiters(a, 1, [0.36], phase0=180, delay0=1.0)
    ribbons(a, 0.14, 1.8, radius=[0.3, 0.36], bright=1.8)
    soft_band(a)                                       # the silk read dim
    put(a['Emitters'], haze('BlossomHaze', 0.3, 7.0, ['#FFC8DE', '#FF7AB8'], rate=2, fade=0.82))
    upgraded(a, 'two glowing silk ribbons now, wider and longer, petals nearly twice as big, a faint blossom haze.')
    rare_pocket(d)


def tidal(d):
    a = d['vfx']['Aura']
    b = named(a['Emitters'], 'Bubbles')
    grow(b, [[0, 0.04], [0.85, 0.1], [0.92, 0.14], [1, 0.02]], 1.5)
    b['Rate'] = 10
    grow(named(a['Emitters'], 'Droplets'), [[0, 0.04], [1, 0.03]], 1.6)
    if len(a['Orbiters']) < 3:
        extra_orbiters(a, 1, [0.32], phase0=240, delay0=1.1)
    ribbons(a, 0.17, 1.5, radius=[0.24, 0.28, 0.32], bright=2.2)
    soft_band(a)                                       # the water read grey
    put(a['Emitters'], haze('SeaHaze', 0.3, 7.0, ['#7FF0FF', '#1A6AD8'], rate=4, fade=0.8))
    upgraded(a, 'three wider water ribbons swirl round the cue, bigger bubbles and droplets, a sea-blue haze.')
    rare_pocket(d)


# ---- Rank cues and VIP (the VFX climb with the rank: Gold to Diamond at most 20 a second like a
# Rare, Veteran and up at most 35 like an Epic; Bronze and Silver keep none) ----------------------

def own_trail(d, rgb, note):
    """(assumption) Gold, Platinum and Diamond had the shared white wisp: the wisp tinted in their
    metal, as a Rare's (tools/cue_trail_pass.py then gives it the Rank length, brightness and core)."""
    st = d['vfx'].setdefault('Style', {})
    if 'Trail' not in st:
        st['Trail'] = {'Color': rgb, 'NearTransparency': 0.0, 'LightEmission': 0.5, 'Lifetime': 1.0,
                       'WidthStuds': 0.3, 'Transparency': [[0, 0.0], [0.55, 0.12], [1, 1]],
                       'WidthScale': [[0, 1], [0.6, 0.85], [1, 0.5]]}
    d['vfx']['Trail']['Note'] = note


def wider_glow(a, name='Glow', w0=0.3, w1=0.55):
    for b in a.get('Beams') or []:
        if b['Name'] == name:
            b.update({'Width0': w0, 'Width1': w1})


def runners(a, width=0.09, life=1.0, radius=0.14):
    """The rank runners (Orbiters) were hair-thin (0.04) and short-lived: wider, longer, further out."""
    for o in a.get('Orbiters') or []:
        o['Radius'] = radius
        o['Trail'].update({'WidthStuds': width, 'Lifetime': life})


def gold_cue(d):
    a = d['vfx']['Aura']
    s_ = named(a['Emitters'], 'Sparkles')
    grow(s_, [[0, 0], [0.4, 0.12, 0.036], [1, 0]], 1.6)
    s_['Rate'] = 8
    put(a['Emitters'], haze('GoldHaze', 0.3, 7.0, ['#FFE08A', '#FFB020'], rate=4, fade=0.82))
    a['Beams'] = [{'Name': 'Glow', 'FromStuds': 0.0, 'ToStuds': 7.0, 'Width0': 0.26, 'Width1': 0.46, 'Segments': 16,
                   'Texture': 'vfx/_shared/halo_strip.png', 'TextureMode': 'Stretch', 'Color': '#FFC040',
                   'Transparency': [[0, 1], [0.06, 0.72], [0.9, 0.67], [1, 1]], 'LightEmission': 1, 'FaceCamera': True}]
    own_trail(d, [255, 196, 70], 'The wisp tinted gold, with a bright core.')
    d['vfx']['Budget']['Beams'] = 5                  # the four shine beams and the new glow
    upgraded(a, 'sparkles bigger and more of them, a faint gold haze and a gold glow round the cue, a gold trail.')


def platinum_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'Sparkles'), [[0, 0], [0.4, 0.12, 0.036], [1, 0]], 1.5)
    grow(named(a['Emitters'], 'Shimmer'), [[0, 0], [0.4, 0.22], [1, 0]], 1.4)
    a['Orbiters'] = [ribbon('PlatinumRibbon', [[0, '#FFFFFF'], [0.5, '#D8ECFF'], [1, '#8FB8E8']], 0.26,
                            width=0.11, turns=0.8, travel=2.6, bright=2.4)]
    own_trail(d, [200, 225, 255], 'The wisp tinted ice-white, with a bright core.')
    upgraded(a, 'bigger sparkles and shimmer, an ice-white ribbon winding round the cue, an ice-white trail.')


def diamond_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'Sparkles'), [[0, 0], [0.4, 0.14, 0.042], [1, 0]], 1.4)
    grow(named(a['Emitters'], 'Crystals'), [[0, 0], [0.2, 0.13], [0.8, 0.13], [1, 0]], 1.7)
    wider_glow(a)
    ice = [[0, '#FFFFFF'], [0.5, '#8FD8FF'], [1, '#2A7AE0']]
    a['Orbiters'] = [ribbon('DiamondRibbon1', ice, 0.24, width=0.1, turns=0.9, travel=2.4, bright=2.0),
                     ribbon('DiamondRibbon2', ice, 0.3, width=0.08, turns=-0.8, travel=2.9, phase=180, delay=1.0,
                            bright=2.0)]
    own_trail(d, [110, 190, 255], 'The wisp tinted diamond blue, with a bright core.')
    upgraded(a, 'bigger sparkles and crystals, two diamond-blue ribbons winding round the cue, a wider glow, a '
                'diamond-blue trail.')


def veteran_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'SpiritFlame'), [[0, 0.4], [0.35, 0.8], [1, 0.24]], 1.3)
    grow(named(a['Emitters'], 'Leaves'), [[0, 0], [0.2, 0.12], [0.8, 0.12], [1, 0]], 1.6)
    runners(a)
    wider_glow(a)
    upgraded(a, 'flames a third bigger, the spirit runners wide enough to see with longer tails, bigger leaves, a '
                'wider glow.')


def expert_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'RedEnergy'), [[0, 0.4], [0.35, 0.8], [1, 0.24]], 1.3)
    grow(named(a['Emitters'], 'Sparks'), [[0, 0.06], [1, 0]], 1.6)
    runners(a)
    wider_glow(a)
    upgraded(a, 'flames a third bigger, the red runners wide enough to see with longer tails, bigger sparks, a '
                'wider glow.')
    # the trail's light red read pink over the blue felt: a deeper red (the trail pass then
    # derives the core from it)
    d['vfx']['Style']['Trail']['Color'] = [235, 40, 30]
    d['vfx']['Style']['Trail'].setdefault('Core', {})['Color'] = [245, 95, 75]


def master_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'PurpleFlame'), [[0, 0.4], [0.35, 0.8], [1, 0.24]], 1.3)
    grow(named(a['Emitters'], 'Amethysts'), [[0, 0], [0.2, 0.13], [0.8, 0.13], [1, 0]], 1.7)
    grow(named(a['Emitters'], 'Sparkles'), [[0, 0], [0.4, 0.12, 0.036], [1, 0]], 1.5)
    runners(a, width=0.1, life=1.1, radius=0.16)
    wider_glow(a)
    upgraded(a, 'flames a third bigger, the violet runners wide with long tails, bigger amethysts and sparkles, a '
                'wider glow.')
    # a textured trail's core had the white tint and drowned the texture's colour: its own colour
    d['vfx']['Style']['Trail']['Core']['Color'] = [205, 150, 255]
    d['vfx']['Style']['Trail']['Colors'] = [[205, 150, 255], [175, 110, 255]]   # untinted it read white
    d['vfx']['Style']['Trail']['WidthStuds'] = 0.5     # its texture is solid only in the middle


def grandmaster_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'DarkAura'), [[0, 0.3], [1, 0.9]], 1.35)
    grow(named(a['Emitters'], 'GoldEmbers'), [[0, 0.07], [1, 0]], 1.6)
    grow(named(a['Emitters'], 'Sparkles'), [[0, 0], [0.4, 0.12, 0.036], [1, 0]], 1.5)
    gold = [[0, '#FFF6D0'], [0.5, '#FFC030'], [1, '#B07000']]
    a['Orbiters'] = [ribbon('GoldRibbon1', gold, 0.26, width=0.11, turns=0.7, travel=2.8, bright=2.0, le=0.6),
                     ribbon('GoldRibbon2', gold, 0.32, width=0.09, turns=-0.6, travel=3.3, phase=180, delay=1.2,
                            bright=2.0, le=0.6)]
    wider_glow(a)
    upgraded(a, 'two gold ribbons wind through the dark aura, bigger smoke, embers and sparkles, a wider glow.')
    # a textured trail's core had the white tint and drowned the texture's colour: its own colour
    d['vfx']['Style']['Trail']['Core']['Color'] = [255, 196, 70]


def reyes_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'RainbowLight'), [[0, 0], [0.3, 0.36], [1, 0]], 1.3)
    grow(named(a['Emitters'], 'Sparkles'), [[0, 0], [0.4, 0.16, 0.048], [1, 0]], 1.4)
    ribbons(a, 0.12, 1.4, radius=[0.24, 0.3, 0.36], bright=2.0)
    wider_glow(a)
    upgraded(a, 'the rainbow ribbons wider and longer and further out, bigger rainbow light and sparkles, a wider glow.')


def vip_cue(d):
    a = d['vfx']['Aura']
    grow(named(a['Emitters'], 'GoldGlitter'), [[0, 0], [0.4, 0.14, 0.05], [1, 0]], 1.35)
    grow(named(a['Emitters'], 'RainbowShimmer'), [[0, 0], [0.3, 0.2], [1, 0]], 1.4)
    grow(named(a['Emitters'], 'Diamonds'), [[0, 0], [0.2, 0.16], [0.8, 0.16], [1, 0]], 1.5)
    ribbons(a, 0.1, 1.3, radius=[0.26, 0.32], bright=2.0)
    wider_glow(a, 'GoldGlow')
    upgraded(a, 'the gold loops wider with longer tails, bigger glitter, shimmer and diamonds, a wider glow.')
    # a textured trail's core had the white tint and drowned the texture's colour: its own colour
    d['vfx']['Style']['Trail']['Core']['Color'] = [255, 214, 110]


POCKET = {
    'celestial_dragon': ('celestial_dragon_pocket', 'Dragon', {
        'Rise': [[0, -3.2], [0.35, -0.25], [1, 0.1]], 'Scale': [[0, 0.7], [0.35, 1.0], [1, 1.05]],
        'Spin': [[0, -25], [1, 10]], 'Transparency': [[0, 0], [0.7, 0], [1, 1]]}),
    'kitsune': ('kitsune_pocket', 'Spirit', {
        'Rise': [[0, -2.6], [0.3, 0.15], [1, 0.6]], 'Scale': [[0, 0.7], [0.3, 1.0], [1, 1.05]],
        'Spin': [[0, 20], [1, -15]], 'Transparency': [[0, 0], [0.7, 0], [1, 1]]}),
    'phoenix': ('phoenix_pocket', 'Firebird', {
        'Rise': [[0, -2.8], [0.3, 0.1], [1, 0.7]], 'Scale': [[0, 0.7], [0.3, 1.0], [1, 1.08]],
        'Spin': [[0, -10], [1, 10]], 'Transparency': [[0, 0], [0.7, 0], [1, 1]]}),
    'infernal': ('infernal_pocket', 'Skull', {
        'Delay': 0.15, 'Seconds': 1.3,
        'Rise': [[0, -2.4], [0.3, 0.5], [1, 1.1]], 'Scale': [[0, 0.75], [0.3, 1.0], [1, 1.05]],
        'Spin': [[0, 0], [1, 0]], 'Transparency': [[0, 0], [0.65, 0], [1, 1]]}),
    'clockwork': ('clockwork_pocket', 'BigCogs', {
        'Delay': 0.05, 'Seconds': 1.3,
        'Rise': [[0, -3.0], [0.3, -0.2], [1, 0.3]], 'Scale': [[0, 0.7], [0.3, 1.0], [1, 1.05]],
        'Spin': [[0, 0], [1, 0]], 'Transparency': [[0, 0], [0.7, 0], [1, 1]]}),
    'kraken': ('kraken_pocket', 'Tentacle', {
        'Rise': [[0, -3.3], [0.3, -0.35], [1, -0.2]], 'Scale': [[0, 0.8], [0.3, 1.0], [1, 1.0]],
        'Spin': [[0, 0], [1, 25]], 'Transparency': [[0, 0], [0.75, 0], [1, 1]]}),
}


UPGRADES = {'eclipse': eclipse, 'apex': apex, 'kitsune': kitsune, 'celestial_dragon': celestial_dragon,
            'phoenix': phoenix, 'kraken': kraken, 'infernal': infernal,
            'clockwork': clockwork, 'thunderstrike': thunderstrike,
            'seraph': seraph, 'chroma': chroma,
            'aurora': aurora, 'blood_moon': blood_moon, 'disco': disco, 'hacked': hacked, 'magma': magma,
            'prism': prism, 'shooting_star': shooting_star, 'toxic': toxic, 'void': void,
            'blaze': blaze, 'candy': candy, 'frostbite': frostbite, 'honeycomb': honeycomb, 'nature': nature,
            'neon': neon, 'phantom': phantom, 'plasma': plasma, 'sakura': sakura, 'tidal': tidal,
            'gold_cue': gold_cue, 'platinum_cue': platinum_cue, 'diamond_cue': diamond_cue,
            'veteran_cue': veteran_cue, 'expert_cue': expert_cue, 'master_cue': master_cue,
            'grandmaster_cue': grandmaster_cue, 'reyes_cue': reyes_cue, 'vip_cue': vip_cue}


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
    else:
        b.pop('Arcs', None)
    if d.get('piece'):
        pj = json.load(open(os.path.join(ROOT, 'assets', 'cue', 'pieces', d['piece'], 'piece.json')))
        b['PieceTriangles'] = pj['Triangles']


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
            if sid in POCKET:
                pid, layer, timing = POCKET[sid]
                pocket_piece(d, pid, layer, **timing)
        if json.dumps(d, sort_keys=True) != before:
            with open(path, 'w') as fh:
                json.dump(d, fh, indent=2)
            print('CUE upgrade', sid, d['vfx'].get('Budget'))


if __name__ == '__main__':
    main()
