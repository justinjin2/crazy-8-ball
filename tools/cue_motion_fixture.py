#!/usr/bin/env python3
"""Write tests/cue_motion_fixture.json: joint transforms from the Blender reference
(assets/cue/CuePieces.py joint_matrix) for a few pieces and times, turned into the Roblox cue
frame, for tests/cue_motion_test.luau to check CueSkins.Motion against.

    python3 tools/cue_motion_fixture.py      (runs headless Blender for mathutils)
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CUE = os.path.join(ROOT, 'assets', 'cue')
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'
PIECES = ['kitsune', 'celestial_dragon', 'chroma', 'phoenix_pocket', 'apex', 'eclipse', 'eclipse_pocket', 'beta', 'beta_pocket']
TIMES = [0.0, 0.73, 3.1, 7.45]


def inside():
    import numpy as np
    sys.path.insert(0, CUE)
    import CuePieces as K
    A = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
    out = []
    for pid in PIECES:
        spec = K.link_paths(json.load(open(os.path.join(CUE, 'pieces', pid, 'piece.json'))))
        zoff = K.ZOFF[spec.get('Frame', 'cue')]
        C = np.eye(4)
        C[:3, :3] = A
        C[2, 3] = zoff
        Ci = np.linalg.inv(C)
        for t in TIMES:
            for name in sorted(spec['Joints']):
                J = C @ K.joint_matrix(spec['Joints'], name, t) @ Ci
                out.append({'piece': pid, 't': t, 'joint': name,
                            'R': [round(float(x), 9) for x in J[:3, :3].ravel()],
                            'P': [round(float(x), 9) for x in J[:3, 3]]})
    with open(os.path.join(ROOT, 'tests', 'cue_motion_fixture.json'), 'w') as fh:
        json.dump(out, fh)
    print('CUE fixture %d joints' % len(out))


if __name__ == '__main__':
    if '--' in sys.argv:
        inside()
    else:
        res = subprocess.run([BLENDER, '-b', '--factory-startup', '--python-exit-code', '1', '--python', __file__, '--'],
                             capture_output=True, text=True)
        print('\n'.join(l for l in (res.stdout + res.stderr).splitlines() if l.startswith('CUE') or 'Error' in l or 'Traceback' in l))
        sys.exit(res.returncode)
