#!/usr/bin/env python3
"""Move every skin's cue effects out with the wider cue (designer, 2026-10-01: the cue 1.6x wider,
the tip kept). One-shot and safe to re-run: each skin file is stamped "shape": 2 when done.

    python3 tools/cue_widen.py            # every skin file
    python3 tools/cue_widen.py --check    # list what would change, write nothing

Shape 1 (before 2026-10-01): tip 0.09, butt 0.2, tapers 0/.1/.36/.73/1. Shape 2 is read from
assets/cue/Shape.json (Config.Cue). Everything a skin places in absolute studs from the cue's
axis keeps its gap above the surface:
  * Part hosts (cylinder volumes along the cue): Width + 2 * the radius gain at their far end
    (not the hair-thin ones that emit on the axis on purpose);
  * Orbiters without RadiusFromSurface, and Arcs: Radius + the radius gain at their far end;
  * Attachment hosts with Up/Side: pushed out along that direction by the gain where they sit
    (past the butt end, on a sleeve piece grown with the butt: scaled with it);
  * Moving beams (the surface's flowing overlays, as wide as the cue): Width0/Width1 and
    ZOffset scaled by the new radius over the old where they are.
Segment and Point hosts follow their piece (rebuilt by CuePieces.py), not the cue.
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKINS = os.path.join(ROOT, 'assets', 'cue', 'skins')
SHAPE = os.path.join(ROOT, 'assets', 'cue', 'Shape.json')
STAMP = 2
ON_AXIS = 0.05  # a Part host thinner than this emits on the axis on purpose (Apex's scan rings)

TO = [0.012, 0.3, 0.55, 0.78, 1]
OLD = {'tip': 0.09, 'butt': 0.2, 'tapers': [0, 0.1, 0.36, 0.73, 1], 'length': 7}


def envelope(tip, butt, tapers, length):
    """CueShape.radiusAt: within a piece the radius runs from its diameter to the next one's."""
    diam = [tip + (butt - tip) * t for t in tapers]

    def radius(d):
        if d <= 0:
            return tip / 2
        if d >= length:
            return butt / 2
        start = 0
        for i, to in enumerate(TO):
            end = length * to
            if d <= end:
                here = diam[i]
                there = diam[i + 1] if i + 1 < len(diam) else here
                k = (d - start) / (end - start) if end > start else 1
                return (here + (there - here) * k) / 2
            start = end
        return butt / 2
    return radius


def new_envelope():
    shape = json.load(open(SHAPE))
    tapers = [row['taper'] if 'taper' in row else row['Taper'] for row in shape['profile']]
    return envelope(shape['tip_diameter_studs'], shape['butt_diameter_studs'], tapers,
                    shape.get('length_studs', 7))


R_OLD = envelope(OLD['tip'], OLD['butt'], OLD['tapers'], OLD['length'])
R_NEW = None


def gain(d):
    return R_NEW(d) - R_OLD(d)


def r3(x):
    return round(x, 4)


def widen_skin(skin, log):
    vfx = skin.get('vfx') or {}
    for section in ('Aura', 'Moving'):
        sec = vfx.get(section)
        if not isinstance(sec, dict):
            continue
        for e in sec.get('Emitters', []):
            h = e.get('Host') or {}
            if h.get('Kind') == 'Part' and h.get('Width', 0) >= ON_AXIS:
                far = max(h.get('FromStuds', 0), h.get('ToStuds', 7))
                w = h['Width']
                h['Width'] = r3(w + 2 * gain(min(far, 7)))
                log.append('%s %s Width %.3f -> %.3f' % (section, e.get('Name'), w, h['Width']))
            elif h.get('Kind') == 'Attachment' and ('Up' in h or 'Side' in h):
                up, side = h.get('Up', 0), h.get('Side', 0)
                r = math.hypot(up, side)
                at = h.get('AtStuds', 5)
                if r > 1e-6:
                    if at > 7:
                        # past the butt end, on a sleeve piece grown with the butt about the
                        # butt end (CuePieces Kit.grow): the same scale, along and out
                        k = R_NEW(7) / R_OLD(7)
                        h['AtStuds'] = r3(7 + (at - 7) * k)
                    else:
                        k = (r + gain(at)) / r
                    if 'Up' in h:
                        h['Up'] = r3(up * k)
                    if 'Side' in h:
                        h['Side'] = r3(side * k)
                    log.append('%s %s Up/Side x%.3f' % (section, e.get('Name'), k))
        for o in sec.get('Orbiters', []):
            if not o.get('RadiusFromSurface') and 'Radius' in o:
                far = max(o.get('FromStuds', 0.3), o.get('ToStuds', 6.9))
                r = o['Radius']
                o['Radius'] = r3(r + gain(min(far, 7)))
                log.append('%s %s Radius %.3f -> %.3f' % (section, o.get('Name'), r, o['Radius']))
        for a in sec.get('Arcs', []):
            far = max(a.get('FromStuds', 3.6), a.get('ToStuds', 6.9))
            r = a.get('Radius', 0.12)
            a['Radius'] = r3(r + gain(min(far, 7)))
            log.append('%s %s Radius %.3f -> %.3f' % (section, a.get('Name'), r, a['Radius']))
        if section == 'Moving':
            for b in sec.get('Beams', []):
                d0, d1 = b.get('FromStuds', 3.8), b.get('ToStuds', 5.3)
                for key, d in (('Width0', d0), ('Width1', d1)):
                    if key in b:
                        b[key] = r3(b[key] * R_NEW(d) / R_OLD(d))
                if 'ZOffset' in b:
                    mid = (d0 + d1) / 2
                    b['ZOffset'] = r3(b['ZOffset'] * R_NEW(mid) / R_OLD(mid))
                log.append('Moving %s widths %s/%s' % (b.get('Name'), b.get('Width0'), b.get('Width1')))


def main():
    global R_NEW
    R_NEW = new_envelope()
    check = '--check' in sys.argv
    for name in sorted(os.listdir(SKINS)):
        if not name.endswith('.json') or name.startswith('_'):
            continue
        path = os.path.join(SKINS, name)
        skin = json.load(open(path))
        if skin.get('shape', 1) >= STAMP:
            continue
        log = []
        widen_skin(skin, log)
        skin['shape'] = STAMP
        print('%s: %d changes' % (name[:-5], len(log)))
        for line in log if check else []:
            print('   ', line)
        if not check:
            with open(path, 'w') as f:
                json.dump(skin, f, indent=2, ensure_ascii=False)
                f.write('\n')


if __name__ == '__main__':
    main()
