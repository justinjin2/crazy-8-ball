#!/usr/bin/env python3
"""Build one cue skin end to end (the skins run's driver):

    python3 tools/cue_skin.py <id> [--paint] [--maps] [--stills] [--clip] [--sheet] [--all] [--quick]

--paint   assets/cue/CuePaint.py <id>        (the panels; OpenAI takes are kept, never re-bought)
--maps    CueTextures.py --skin ... --no-render   (textures/<id>_*.png)
--stills  CuePreview.py --stills              (renders/skins/<id>/stills/)
--sheet   CuePreview.py --sheet <id>          (renders/skins/<id>/sheet.png)
--clip    CuePreview.py --clip                (renders/skins/<id>/clip.mp4)
--thumb   CuePreview.py --thumb               (thumbs/<id>.png, the game's card picture, aura and outline)
--noaura  leave the aura out of the card picture
--all     every step (the default with no step flags). Headless Blender only, one at a time.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = '/Applications/Blender.app/Contents/MacOS/Blender'
CUE = os.path.join(ROOT, 'assets', 'cue')


def blender(script, *args):
    cmd = [B, '-b', '--factory-startup', '--python-exit-code', '1', '--python', os.path.join(CUE, script), '--'] + list(args)
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    keep = [l for l in res.stdout.splitlines() + res.stderr.splitlines()
            if l.startswith('CUE') or 'Error' in l or 'Traceback' in l or l.strip().startswith('File ')]
    print('\n'.join(keep[-25:]))
    if res.returncode != 0:
        sys.exit('%s failed' % script)


def main():
    args = sys.argv[1:]
    ids = [a for a in args if not a.startswith('--')]
    steps = [a for a in args if a.startswith('--') and a not in ('--quick', '--noaura')]
    if not steps or '--all' in steps:
        steps = ['--paint', '--maps', '--stills', '--sheet', '--clip']
    for skin_id in ids:
        if '--paint' in steps:
            subprocess.run([sys.executable, os.path.join(CUE, 'CuePaint.py'), skin_id], cwd=ROOT, check=True)
        if '--maps' in steps:
            blender('CueTextures.py', '--skin', os.path.join(CUE, 'skins', skin_id + '.json'), '--no-render')
        if '--stills' in steps:
            blender('CuePreview.py', '--skin', skin_id, '--stills')
        if '--sheet' in steps:
            subprocess.run([sys.executable, os.path.join(CUE, 'CuePreview.py'), '--sheet', skin_id], cwd=ROOT, check=True)
        if '--thumb' in steps:
            blender('CuePreview.py', '--skin', skin_id, '--thumb', *(['--noaura'] if '--noaura' in args else []))
        if '--clip' in steps:
            blender('CuePreview.py', '--skin', skin_id, '--clip', *(['--quick'] if '--quick' in args else []))


if __name__ == '__main__':
    main()
