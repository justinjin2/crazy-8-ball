#!/usr/bin/env python3
"""The Halloween tables' cloth contrast check (hw-map lane, PLAN section 2 "Tables"): every cloth
must keep CIEDE2000 >= 17 from every ball as rendered under Night and under Sunset.

The colours come from Play captures: a top-down shot of a racked table of each mode, the cloth's
median colour sampled round the rack and each ball's lit median (the maths is
~/Desktop/8ball-refs/halloween/research/agents/cloth_contrast.py, run on sampled colours instead
of raw ones).

    python3 tools/halloween/hw_map_cloth_check.py samples.json
    python3 tools/halloween/hw_map_cloth_check.py --raw          # Config's raw tints vs balls

samples.json: {"<lighting>": {"<mode>": {"cloth": [r, g, b], "balls": {"<n>": [r, g, b]}}}}.
Or sample a capture: --png shot.png --cloth x,y[,r] --ball n:x,y[,r] ... (medians of a square of
radius r pixels, default 6), printing the colours to paste into samples.json.

Prints, per lighting and mode, the closest ball and its distance, and exits 1 if any is under
the minimum.
"""
import json
import math
import sys

MIN_DELTA_E = 17
RAW_CLOTHS = {'1v1': (185, 90, 230), '2v2': (90, 94, 102), '3v3': (88, 176, 32)}
RAW_BALLS = {0: (245, 240, 225), 1: (250, 200, 40), 2: (30, 80, 200), 3: (210, 40, 40),
             4: (100, 40, 150), 5: (245, 120, 30), 6: (12, 92, 52), 7: (120, 30, 30),
             8: (20, 20, 22)}


def lab(c):
    def f(u):
        u /= 255
        return ((u + 0.055) / 1.055) ** 2.4 if u > 0.04045 else u / 12.92
    r, g, b = map(f, c)
    X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def g_(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = g_(X), g_(Y), g_(Z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def delta_e(c1, c2):
    L1, a1, b1 = lab(c1)
    L2, a2, b2 = lab(c2)
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)

    def h(b, a):
        return math.degrees(math.atan2(b, a)) % 360
    h1, h2 = h(b1, a1p), h(b2, a2p)
    dL, dC = L2 - L1, C2p - C1p
    dh = h2 - h1
    if C1p * C2p == 0:
        dh = 0
    elif dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dh / 2))
    Lb, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
    if C1p * C2p == 0:
        hb = h1 + h2
    elif abs(h1 - h2) <= 180:
        hb = (h1 + h2) / 2
    elif h1 + h2 < 360:
        hb = (h1 + h2 + 360) / 2
    else:
        hb = (h1 + h2 - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hb - 30)) + 0.24 * math.cos(math.radians(2 * hb))
         + 0.32 * math.cos(math.radians(3 * hb + 6)) - 0.2 * math.cos(math.radians(4 * hb - 63)))
    dth = 30 * math.exp(-((hb - 275) / 25) ** 2)
    RC = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    SL = 1 + 0.015 * (Lb - 50) ** 2 / math.sqrt(20 + (Lb - 50) ** 2)
    SC, SH = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
    RT = -math.sin(math.radians(2 * dth)) * RC
    return math.sqrt((dL / SL) ** 2 + (dC / SC) ** 2 + (dH / SH) ** 2 + RT * (dC / SC) * (dH / SH))


def closest(cloth, balls):
    return min((delta_e(cloth, c), n) for n, c in balls.items())


def report(samples):
    ok = True
    print('%-9s %-5s %-16s %-5s %s' % ('lighting', 'mode', 'cloth', 'ball', 'deltaE'))
    for lighting, modes in samples.items():
        for mode, s in modes.items():
            balls = {int(n): tuple(c) for n, c in s['balls'].items()}
            d, n = closest(tuple(s['cloth']), balls)
            flag = '' if d >= MIN_DELTA_E else '  UNDER %d' % MIN_DELTA_E
            ok = ok and d >= MIN_DELTA_E
            print('%-9s %-5s %-16s %-5d %.1f%s' % (lighting, mode, tuple(s['cloth']), n, d, flag))
    return ok


def sample_png(argv):
    from PIL import Image
    import numpy as np
    path = argv[argv.index('--png') + 1]
    img = np.asarray(Image.open(path).convert('RGB')).astype(float)

    def median(spec):
        parts = [int(v) for v in spec.split(',')]
        x, y, r = parts[0], parts[1], parts[2] if len(parts) > 2 else 6
        patch = img[max(0, y - r):y + r + 1, max(0, x - r):x + r + 1].reshape(-1, 3)
        return [int(round(v)) for v in np.median(patch, axis=0)]
    out = {'cloth': median(argv[argv.index('--cloth') + 1]), 'balls': {}}
    for i, a in enumerate(argv):
        if a == '--ball':
            n, spec = argv[i + 1].split(':')
            out['balls'][n] = median(spec)
    print(json.dumps(out))


def main(argv):
    if '--png' in argv:
        sample_png(argv)
        return 0
    if '--raw' in argv:
        samples = {'raw': {m: {'cloth': c, 'balls': {str(k): v for k, v in RAW_BALLS.items()}}
                           for m, c in RAW_CLOTHS.items()}}
    else:
        samples = json.load(open(argv[1]))
    return 0 if report(samples) else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
