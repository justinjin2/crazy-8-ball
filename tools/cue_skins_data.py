#!/usr/bin/env python3
"""Write the cue skins' game data from the skin files (data, not code: CLAUDE.md).

    python3 tools/cue_skins_data.py [--allow-missing] [--also-manifest <path>]... [--allow-over-budget]

Reads assets/cue/skins/<id>.json, assets/cue/pieces/<piece>/piece.json and the asset ids in
tools/upload_manifest.json, and writes (generated, never edited by hand):

    src/shared/CueSkins/Skins/<CatalogId>.luau   one row per skin (surface maps, aura, trail, pocket...)
    src/shared/CueSkins/Pieces/<piece>.luau      a 3D piece: parts, joints, motions, paths
    src/shared/CueSkins/Index.luau               every skin's name, tier, thumbnail and flat colours
                                                 (small: the catalog and the UI read it)
    src/shared/CueSkins/Textures.luau            the default texture of each effect role

A skin with "draft": true is left out (still being built; its assets are not uploaded yet).
Halloween 2026 keys (lane hw-cues-a, docs/prompts/HW_CUES_A_PROMPT.md 2.2): "body": "<piece>"
(the cue drawn by its own model: row.Body and Index[id].Body; the shared mesh is hidden under
it), "maps_from": "classic" (the hidden mesh wears Classic's uploaded maps, shown only if the
body is missing), "look": {Shaft, Forearm, Wrap, Ring, Tip?, Cap?, Accent?} (the flat colours
as given, hex or 0-255 lists, since there is no colour map to sample). --also-manifest <path>
(repeatable) reads another worktree's manifest after the repo's own, read-only, so rows can be
generated from ids uploaded there before the branches merge. A piece over the hard budget (a
body over 8 parts or 10,000 triangles, an aura piece over 10,000, a pocket piece over 20,000,
from piece.json) stops the run with its numbers; --allow-over-budget is for work in progress
only, never for a committed run.
Every file path in the skin data becomes its uploaded id ("rbxassetid://<image id>"); a path with
no id stops the run unless --allow-missing (then it is "" and listed). Notes, budgets and the
review-only keys are dropped. Colours stay as the skin files write them (hex strings or 0-255
lists); the runtime (CueSkinLook, CuePiece, Effects) reads them. `Look` is the cue's flat colours
for the 2D power-bar cue and the band fallback, sampled from the colour map's areas.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CUE = os.path.join(ROOT, 'assets', 'cue')
OUT = os.path.join(ROOT, 'src', 'shared', 'CueSkins')
MANIFEST = os.path.join(ROOT, 'tools', 'upload_manifest.json')
ASSET = re.compile(r'\.(png|glb|obj|wav|ogg|mp3)$')
DROP = {'Note', 'Budget', 'frame', 'Triangles', 'File'}  # notes and review-only keys
MAPS = ('color', 'normal', 'roughness', 'metalness', 'emissive')

manifest = json.load(open(MANIFEST))
# --also-manifest <path> (repeatable): another worktree's uploads, read after the repo's own and
# never written; a row the repo's manifest already has wins.
for _i, _arg in enumerate(sys.argv):
    if _arg == '--also-manifest' and _i + 1 < len(sys.argv):
        for _k, _r in json.load(open(os.path.expanduser(sys.argv[_i + 1]))).items():
            manifest.setdefault(_k, _r)
missing = []

# Every id the generated rows carry today (read before main() rewrites them): when a file has
# several "ok" uploads (the same picture uploaded from two worktrees), the one the shipped rows
# already use wins, so a regenerate from any worktree reproduces the live rows exactly and a
# re-upload never swaps a live id by itself (delete the old manifest row to move to a new one).
shipped_ids = set()
for _sub in ('Skins', 'Pieces'):
    _d = os.path.join(OUT, _sub)
    for _name in (os.listdir(_d) if os.path.isdir(_d) else ()):
        shipped_ids.update(re.findall(r'(?:rbxassetid://)?(\d{6,})', open(os.path.join(_d, _name)).read()))

# The hard budgets by a piece's role (parts, triangles) for the body cues' pieces (a skin with
# "body": the Halloween 2026 cues; the older pieces predate the rule: the Celestial Dragon's
# aura alone is 36,790 triangles): the same limits as both cue lanes' briefs, so the tool never
# refuses a Mythic's pocket piece. A role's None means no part limit.
BUDGET = {'body': (8, 10000), 'aura': (None, 10000), 'pocket': (None, 20000)}


def check_budget(pid, spec, roles, allow):
    """Stop the run when piece `pid` (its piece.json `spec`, used in `roles`) passes a hard
    budget; with `allow` only warn."""
    parts = len(spec.get('Parts') or [])
    tris = spec.get('Triangles') or sum(int(p.get('Triangles') or 0) for p in spec.get('Parts') or [])
    over = []
    for role in sorted(roles):
        max_parts, max_tris = BUDGET[role]
        if max_parts is not None and parts > max_parts:
            over.append('%s: %d parts, at most %d as a %s' % (pid, parts, max_parts, role))
        if tris > max_tris:
            over.append('%s: %d triangles, at most %d as a %s' % (pid, tris, max_tris, role))
    for line in over:
        print(('over budget (allowed for now): ' if allow else 'over budget: ') + line)
    if over and not allow:
        sys.exit('a piece is over its hard budget (--allow-over-budget only for work in progress, never for a committed run)')
    return over


def asset_id(rel):
    """`vfx/x.png`, `textures/x.png`, `pieces/p/x.glb` or `sounds/x.wav` -> its uploaded id string
    (an image id for a picture, `rbxassetid://` for a sound, the bare id for a model)."""
    path = os.path.join(CUE, rel)
    row = manifest.get(path) or {}
    if not row:
        # Uploaded from another worktree (~/Desktop/8ball, 8ball-gui, ...): the manifest is keyed
        # by absolute path, so match the path inside assets/cue instead, the main checkout's
        # upload first (the rows the game runs on), so every lane generates the same rows.
        tail = os.sep + os.path.join('assets', 'cue', rel)
        hits = [(k, r) for k, r in manifest.items() if k.endswith(tail) and r.get('status') == 'ok']
        hits.sort(key=lambda kr: (
            0 if (str(kr[1].get('imageId') or '') in shipped_ids or str(kr[1].get('assetId') or '') in shipped_ids) else 1,
            0 if kr[0].startswith(os.path.join(os.path.expanduser('~'), 'Desktop', '8ball') + os.sep) else 1,
            kr[0]))
        row = hits[0][1] if hits else {}
    if row.get('status') == 'ok':
        if rel.endswith('.png') and row.get('imageId'):
            return 'rbxassetid://%s' % row['imageId']
        if rel.endswith(('.wav', '.ogg', '.mp3')) and row.get('assetId'):
            return 'rbxassetid://%s' % row['assetId']
        if not rel.endswith('.png') and row.get('assetId'):
            return row['assetId']
    missing.append(rel)
    return ''


def uploaded(rel):
    tail = os.sep + os.path.join('assets', 'cue', rel)
    return any(k.endswith(tail) and r.get('status') == 'ok' for k, r in manifest.items())


def resolve(x):
    if isinstance(x, dict):
        return {k: resolve(v) for k, v in x.items() if k not in DROP}
    if isinstance(x, list):
        return [resolve(v) for v in x]
    if isinstance(x, str) and ASSET.search(x) and '/' in x:
        return asset_id(x)
    return x


IDENT = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def lua(x, indent=0):
    pad = '\t' * (indent + 1)
    if x is None:
        return 'nil'
    if isinstance(x, bool):
        return 'true' if x else 'false'
    if isinstance(x, int):
        return str(x)
    if isinstance(x, float):
        r = repr(x)  # the shortest exact form: a path's Step is used thousands of times over
        return r[:-2] if r.endswith('.0') else r
    if isinstance(x, str):
        return json.dumps(x)
    if isinstance(x, list):
        if not x:
            return '{}'
        if all(not isinstance(v, (dict, list)) for v in x):
            return '{ ' + ', '.join(lua(v) for v in x) + ' }'
        return '{\n' + ''.join(pad + lua(v, indent + 1) + ',\n' for v in x) + '\t' * indent + '}'
    if isinstance(x, dict):
        if not x:
            return '{}'
        body = ''
        for k, v in x.items():
            key = k if IDENT.match(k) else '[%s]' % json.dumps(k)
            body += '%s%s = %s,\n' % (pad, key, lua(v, indent + 1))
        return '{\n' + body + '\t' * indent + '}'
    raise TypeError(type(x))


def write_module(path, comment, value):
    with open(path, 'w') as fh:
        fh.write('--!nocheck\n-- %s\n-- Generated by tools/cue_skins_data.py from assets/cue: do not edit by hand.\n\n' % comment)
        fh.write('return ' + lua(value) + '\n')


def hexrgb(h):
    h = h.lstrip('#')
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def recorded_look(catalog_id):
    """The Look the current Index.luau records for a cue (its generated, fixed layout), for a
    worktree without that skin's colour map (textures/ is not committed; a lane rebuilds only
    its own skins' maps)."""
    try:
        text = open(os.path.join(OUT, 'Index.luau')).read()
    except FileNotFoundError:
        return None
    m = re.search(r'\n\t%s = \{\n(.*?)\n\t\},' % re.escape(catalog_id), text, re.S)
    if not m:
        return None
    look = re.search(r'Look = \{\n(.*?)\n\t\t\},', m.group(1), re.S)
    if not look:
        return None
    out = {k: [int(a), int(b), int(c)] for k, a, b, c in re.findall(r'(\w+) = \{ (\d+), (\d+), (\d+) \}', look.group(1))}
    return out or None


LOOK_KEYS = ('Shaft', 'Forearm', 'Wrap', 'Ring')
LOOK_OPTIONAL = ('Tip', 'Cap', 'Accent')


def given_look(skin_id, look):
    """A skin's "look" as given (a body cue has no colour map to sample): Shaft, Forearm, Wrap
    and Ring required, Tip, Cap and Accent optional, each a hex string or a 0-255 list."""
    out = {}
    for key in LOOK_KEYS + LOOK_OPTIONAL:
        v = look.get(key)
        if v is None:
            if key in LOOK_KEYS:
                sys.exit('%s: "look" needs %s' % (skin_id, ', '.join(LOOK_KEYS)))
            continue
        rgb = hexrgb(v) if isinstance(v, str) else [int(x) for x in v]
        if len(rgb) != 3 or any(x < 0 or x > 255 for x in rgb):
            sys.exit('%s: "look" %s is not a colour' % (skin_id, key))
        out[key] = rgb
    extra = sorted(set(look) - set(LOOK_KEYS) - set(LOOK_OPTIONAL))
    if extra:
        sys.exit('%s: unknown "look" keys %s' % (skin_id, ', '.join(extra)))
    return out


def sample_look(skin_id, colours, catalog_id=None):
    """The cue's flat colours from its colour map: the shaft, forearm and butt strips' middles."""
    path = os.path.join(CUE, 'textures', skin_id + '_color.png')
    try:
        from PIL import Image
    except ImportError:
        sys.exit('needs Pillow (pip3 install pillow)')
    if not os.path.isfile(path):
        kept = recorded_look(catalog_id or '')
        if kept:
            return kept
        sys.exit('no colour map for %s (textures/%s_color.png) and no Look recorded in Index.luau' % (skin_id, skin_id))
    im = Image.open(path).convert('RGB')
    layout = {u['strip']: u for u in json.load(open(os.path.join(CUE, 'Parameters.json')))['uv_layout']}

    def mean(strip, a=0.3, b=0.7):
        x, y, w, h = layout[strip]['rect_px']
        crop = im.crop((x + int(w * a), y + int(h * 0.1), x + int(w * b), y + int(h * 0.9))).resize((1, 1), Image.BOX)
        return list(crop.getpixel((0, 0)))

    metal = colours.get('metal') or colours.get('gold') or '#C8CCD0'
    return {
        'Shaft': mean('shaft_2'),
        'Forearm': mean('forearm', 0.15, 0.85),
        'Wrap': mean('butt', 0.35, 0.8),
        'Ring': hexrgb(metal),
        'Tip': hexrgb(colours.get('tip', '#1E2438')),
        'Cap': mean('butt', 0.92, 0.99),
    }


def skin_row(skin):
    sid = skin['id']
    vfx = skin.get('vfx') or {}
    row = {'Id': sid, 'CatalogId': skin['catalog_id'], 'Name': skin['name'], 'Tier': skin['tier']}
    maps = {}
    # "maps_from": "classic": the shared mesh wears Classic's maps (a body cue hides it; the
    # maps show only when the body template is missing, the fail-safe).
    maps_sid = skin.get('maps_from') or sid
    for key in MAPS:
        rel = 'textures/%s_%s.png' % (maps_sid, key)
        # the map is on disk, or (a lane without the other skins' maps: textures/ is not
        # committed) already uploaded
        if os.path.isfile(os.path.join(CUE, rel)) or uploaded(rel):
            maps[key.capitalize()] = asset_id(rel)
    row['Maps'] = maps
    if skin.get('surface'):
        row['Surface'] = resolve(skin['surface'])
    moving = vfx.get('Moving') or {}
    if moving.get('Frames'):
        frames = resolve(moving['Frames'])
        frames['Maps'] = [{k.capitalize(): v for k, v in m.items()} for m in frames['Maps']]
        row['Frames'] = frames
    if vfx.get('Aura'):
        row['Aura'] = resolve(vfx['Aura'])
    moving_rest = {k: v for k, v in moving.items() if k in ('Beams', 'Emitters', 'BeamPulse')}
    if moving_rest:
        row['Moving'] = resolve(moving_rest)
    if (vfx.get('Trail') or {}).get('Emitters'):
        row['TrailEmitters'] = resolve(vfx['Trail']['Emitters'])
    if vfx.get('Style'):
        row['Style'] = resolve(vfx['Style'])
    pocket = {k: v for k, v in (vfx.get('Pocket') or {}).items() if k in ('Layers', 'Rings', 'Flash', 'Piece', 'KeepRibbons', 'Sound')}
    if pocket:
        row['Pocket'] = resolve(pocket)
    if skin.get('piece'):
        row['Piece'] = skin['piece']
    if skin.get('carrier'):
        row['Carrier'] = skin['carrier']  # a piece built on the carrying character (a Secret's engulfing aura)
    if skin.get('body'):
        row['Body'] = skin['body']  # the cue's own model (Halloween 2026): CueSkins.bodyOf draws it over the hidden mesh
    row['Thumb'] = asset_id('thumbs/%s.png' % sid)
    row['Look'] = given_look(sid, skin['look']) if skin.get('look') else sample_look(sid, skin.get('colours') or {}, skin['catalog_id'])
    return row


def piece_row(spec):
    pid = spec['id']
    rigid = asset_id('pieces/%s/%s_parts.glb' % (pid, pid)) if any(p['File'].endswith('.obj') for p in spec['Parts']) else None
    models = {}
    parts = []
    for p in spec['Parts']:
        part = resolve(p)
        if p['File'].endswith('.glb'):
            name = os.path.splitext(os.path.basename(p['File']))[0]
            models[name] = asset_id(p['File'])
            part['Model'] = name
        parts.append(part)
    joints = {name: resolve(j) for name, j in spec['Joints'].items()}
    for j in joints.values():
        j.pop('Pivot', None)  # the Blender pivot; the runtime uses PivotRoblox
    row = {'Id': pid, 'Frame': spec.get('Frame', 'cue'), 'Rigid': rigid, 'Models': models, 'Parts': parts, 'Joints': joints}
    if spec.get('Paths'):
        row['Paths'] = spec['Paths']
    if spec.get('Upright'):
        row['Upright'] = True  # rigid parts keep the design's orientation (CuePiece: no FLIP)
    return row


def main():
    allow = '--allow-missing' in sys.argv
    allow_budget = '--allow-over-budget' in sys.argv
    skins = []
    for name in sorted(os.listdir(os.path.join(CUE, 'skins'))):
        if name.endswith('.json') and not name.startswith('_'):
            skin = json.load(open(os.path.join(CUE, 'skins', name)))
            if skin.get('catalog_id') and not skin.get('draft'):
                skins.append(skin)  # "draft": true keeps a skin still being built out of the game
    os.makedirs(os.path.join(OUT, 'Skins'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'Pieces'), exist_ok=True)
    for sub in ('Skins', 'Pieces'):  # a skin or piece removed from assets/cue goes too
        for old in os.listdir(os.path.join(OUT, sub)):
            os.remove(os.path.join(OUT, sub, old))
    index = {}
    for skin in skins:
        row = skin_row(skin)
        index[row['CatalogId']] = {k: row[k] for k in ('Id', 'Name', 'Tier', 'Thumb', 'Look')}
        if row.get('Piece'):
            index[row['CatalogId']]['Piece'] = row['Piece']
        if row.get('Body'):
            index[row['CatalogId']]['Body'] = row['Body']
        write_module(os.path.join(OUT, 'Skins', row['CatalogId'] + '.luau'), '%s (%s): the cue skin\'s look.' % (skin['name'], skin['tier']), row)
    # only the pieces an included skin wears (a draft skin's pieces are not uploaded yet)
    used = set()
    roles = {}  # piece id -> the roles it plays for a body cue (body, aura, pocket): the budget check
    for skin in skins:
        budgeted = bool(skin.get('body'))

        def use(pid, role):
            used.add(pid)
            if budgeted:
                roles.setdefault(pid, set()).add(role)
        if skin.get('piece'):
            use(skin['piece'], 'aura')
        if skin.get('carrier'):
            use(skin['carrier'], 'aura')
        if skin.get('body'):
            use(skin['body'], 'body')
        pocket = ((skin.get('vfx') or {}).get('Pocket') or {}).get('Piece') or {}
        if pocket.get('Piece'):
            use(pocket['Piece'], 'pocket')
    pieces = sorted(d for d in os.listdir(os.path.join(CUE, 'pieces'))
                    if os.path.isfile(os.path.join(CUE, 'pieces', d, 'piece.json')) and d in used)
    for pid in used - set(pieces):
        missing.append('pieces/%s/piece.json' % pid)
    for pid in pieces:
        spec = json.load(open(os.path.join(CUE, 'pieces', pid, 'piece.json')))
        check_budget(pid, spec, roles.get(pid, set()), allow_budget)
        row = piece_row(spec)
        write_module(os.path.join(OUT, 'Pieces', pid + '.luau'), 'The %s piece: parts, joints and motions.' % pid, row)
    # The preview's defaults for a texture a row leaves out (CueVfx.py), by role.
    defaults = {'Emitter': 'vfx/_shared/glow_soft.png', 'Beam': 'vfx/_shared/glow_soft.png',
                'Trail': 'vfx/_shared/trail_soft.png', 'Head': 'vfx/_shared/glow_core.png',
                'Arc': 'vfx/_shared/bolt_strip.png', 'Ring': 'vfx/_shared/ring.png'}
    write_module(os.path.join(OUT, 'Textures.luau'), 'The default texture of each effect role (a row may leave its own out).',
                 {k: asset_id(v) for k, v in defaults.items()})
    write_module(os.path.join(OUT, 'Index.luau'), 'Every cue skin by catalog id: name, tier, thumbnail, flat colours.',
                 dict(sorted(index.items())))
    subprocess.run(['stylua', os.path.join(OUT, 'Skins'), os.path.join(OUT, 'Pieces'), os.path.join(OUT, 'Index.luau'),
                    os.path.join(OUT, 'Textures.luau')], check=True)
    print('wrote %d skins, %d pieces' % (len(skins), len(pieces)))
    if missing:
        print('%d paths have no uploaded id, e.g. %s' % (len(set(missing)), sorted(set(missing))[:5]))
        if not allow:
            sys.exit(1)


if __name__ == '__main__':
    main()
