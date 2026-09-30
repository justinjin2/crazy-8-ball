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
                 'glow round the cue (a halo Beam) and a violet light at the mask.')


def celestial_dragon(d):
    v = d['vfx']
    a = v['Aura']
    # the energy flowing along the dragon's coils (runners matched to the body's helix): wide,
    # long and streaky so the whole body reads as flowing starlight, not a thin wire
    for o in a['Orbiters']:
        o['Wobble'] = 0.0
        o['Trail'].update({'Lifetime': 1.0, 'WidthStuds': 0.11, 'Color': '#9CCBFF', 'Brightness': 3,
                           'Transparency': [[0, 0], [0.6, 0.25], [1, 1]], 'WidthScale': [[0, 1], [1, 0.4]],
                           'Texture': 'vfx/celestial_dragon/trail_starlight.png'})
        o['Head']['Size'] = 0.22
    # blue energy flames stream back off the head (the concept's burning mane)
    w = named(a['Emitters'], 'Wisps')
    w.update({'Texture': 'vfx/_shared/energy_flame_8x8.png', 'FlipbookLayout': 'Grid8x8', 'FlipbookMode': 'OneShot',
              'Size': [[0, 0.25], [0.4, 0.5], [1, 0.15]], 'Transparency': [[0, 0.35], [0.3, 0.1], [1, 1]],
              'Color': [[0, '#EAF6FF'], [0.5, '#6FB8FF'], [1, '#2A5CE0']], 'Brightness': 1.6, 'Rate': 12,
              'Squash': 0, 'Transparency': [[0, 0.35], [0.3, 0.1], [1, 1]], 'Acceleration': [0, 1.2, 0]})
    a['Note'] = ('Layered: wide streams of starlight flow along the coils of the dragon body (Orbiters matched to the '
                 'body\'s helix, streaky starlight trails); drifting star dust (four-point stars twinkling in and out, '
                 'white to blue); soft blue light motes; blue energy flames stream back off the head; a soft blue '
                 'glow round the cue (a halo Beam, breathing) and a blue light at the head.')


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
    # pocket: the eruption kept from turning pink over the felt; the skull rises clear of the
    # default swirl ribbons (they crossed in front of it)
    v['Pocket']['KeepRibbons'] = False
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


def pocket_piece(d, piece_id, drop_layer, **timing):
    """The pocket finisher's creature as a rising 3D piece (CuePiecesPocket) in place of its flat
    flipbook layer."""
    P = d['vfx']['Pocket']
    P['Layers'] = [x for x in P['Layers'] if x['Name'] != drop_layer]
    spec = {'Piece': piece_id, 'Delay': 0.1, 'Seconds': 1.35}
    spec.update(timing)
    P['Piece'] = spec
    pj = json.load(open(os.path.join(ROOT, 'assets', 'cue', 'pieces', piece_id, 'piece.json')))
    d['vfx']['Budget']['PocketPieceTriangles'] = pj['Triangles']


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
    'kraken': ('kraken_pocket', 'Tentacle', {
        'Rise': [[0, -3.3], [0.3, -0.35], [1, -0.2]], 'Scale': [[0, 0.8], [0.3, 1.0], [1, 1.0]],
        'Spin': [[0, 0], [1, 25]], 'Transparency': [[0, 0], [0.75, 0], [1, 1]]}),
}


UPGRADES = {'eclipse': eclipse, 'apex': apex, 'kitsune': kitsune, 'celestial_dragon': celestial_dragon,
            'phoenix': phoenix, 'kraken': kraken, 'infernal': infernal}


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
