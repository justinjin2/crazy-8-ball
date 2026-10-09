#!/usr/bin/env python3
"""Meshy auto-rigging and the animation library for a humanoid model. Standard library only.

    python3 tools/meshy_rig.py library [--search run] [--category WalkAndRun] [--json]
    python3 tools/meshy_rig.py rig <out dir> (--task-id <image-to-3d task> | --model <file.glb>)
        [--height 1.7] [--texture base_color.png]
    python3 tools/meshy_rig.py animate <out dir> --rig-task <rig task id> --action <id> [--action <id> ...]
        [--fps 24]
    python3 tools/meshy_rig.py resume <out dir> (--rig <task id> | --anim <task id>)

rig: POST /rigging (5 credits). The model must be a textured biped facing glTF +Z. Saves
rigged.glb / rigged.fbx and the free walking and running clips (walking.glb, running.glb) into
<out dir>, with rig_meta.json.

animate: one POST /animations per action id (3 credits each), each task polled to the end;
saves anim_<id>_<slug>.glb (the rigged character with that one clip) and appends to
anims_meta.json. `library` lists the action ids (GET /animations/library, free).

Every task is appended to assets/cue/models/meshy_log.jsonl like tools/meshy_generate.py. The key
is read from the macOS Keychain (service MESHY_API_KEY) and never printed or written.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, 'assets', 'cue', 'models', 'meshy_log.jsonl')
API = 'https://api.meshy.ai/openapi/v1/'
POLL_SECONDS = 8
TIMEOUT_SECONDS = 30 * 60
_KEY = None


def api_key():
    global _KEY
    if _KEY is None:
        out = subprocess.run(['security', 'find-generic-password', '-s', 'MESHY_API_KEY', '-w'],
                             capture_output=True, text=True)
        _KEY = out.stdout.strip()
        if out.returncode != 0 or not _KEY:
            sys.exit('meshy_rig: no MESHY_API_KEY in the Keychain')
    return _KEY


def request(method, path, body=None, query=None):
    url = API + path
    if query:
        url += '?' + urllib.parse.urlencode({k: v for k, v in query.items() if v not in (None, '')})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('Authorization', 'Bearer ' + api_key())
    if data is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        sys.exit('meshy_rig: HTTP %d on %s %s: %s' % (err.code, method, path, err.read().decode()[:600]))


def download(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as resp, open(path, 'wb') as out:
        out.write(resp.read())
    print('MESHY saved', os.path.relpath(path, ROOT), flush=True)


def log(entry):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, 'a') as handle:
        handle.write(json.dumps(entry) + '\n')


def poll(kind, task_id):
    start = time.time()
    last = None
    while True:
        task = request('GET', '%s/%s' % (kind, task_id))
        status, prog = task.get('status'), task.get('progress')
        if (status, prog) != last:
            print('MESHY %s %s %s %s%%' % (kind, task_id, status, prog), flush=True)
            last = (status, prog)
        if status in ('SUCCEEDED', 'FAILED', 'CANCELED'):
            return task
        if time.time() - start > TIMEOUT_SECONDS:
            sys.exit('meshy_rig: timed out waiting for ' + task_id)
        time.sleep(POLL_SECONDS)


def slug(text):
    return re.sub(r'[^a-z0-9]+', '_', (text or '').lower()).strip('_')[:40]


def append_json(path, entry):
    rows = []
    if os.path.isfile(path):
        with open(path) as handle:
            rows = json.load(handle)
    rows.append(entry)
    with open(path, 'w') as handle:
        json.dump(rows, handle, indent=2)


def cmd_library(args):
    # The endpoint returns the whole catalogue in one response (paging is ignored); dedupe anyway.
    res = request('GET', 'animations/library', query={'search': args.search, 'category': args.category})
    items = res if isinstance(res, list) else (res.get('result') or res.get('data') or res.get('items') or [])
    rows = sorted({r.get('action_id'): r for r in items}.values(), key=lambda r: r.get('action_id') or 0)
    if args.json:
        print(json.dumps(rows, indent=1))
        return
    for r in rows:
        print('%5s  %-14s %-22s %s' % (r.get('action_id', r.get('id')), r.get('category', ''),
                                       r.get('sub_category', ''), r.get('name', r.get('key', ''))))
    print('MESHY %d animations' % len(rows))


def save_rig(out, task):
    res = task.get('result') or {}
    if res.get('rigged_character_glb_url'):
        download(res['rigged_character_glb_url'], os.path.join(out, 'rigged.glb'))
    if res.get('rigged_character_fbx_url'):
        download(res['rigged_character_fbx_url'], os.path.join(out, 'rigged.fbx'))
    for name, url in (res.get('basic_animations') or {}).items():
        if url and name.endswith('_glb_url') and 'armature' not in name:
            download(url, os.path.join(out, name.replace('_glb_url', '.glb')))
    meta = {'rig_task_id': task.get('id'), 'status': task.get('status'), 'credits': task.get('consumed_credits'),
            'task_error': task.get('task_error'), 'finished_at': task.get('finished_at')}
    with open(os.path.join(out, 'rig_meta.json'), 'w') as handle:
        json.dump(meta, handle, indent=2)
    log({'time': time.strftime('%Y-%m-%d %H:%M'), 'name': os.path.basename(out.rstrip('/')),
         'task_id': task.get('id'), 'endpoint': 'rigging', 'status': task.get('status'),
         'credits': task.get('consumed_credits')})
    print('MESHY rig %s, credits %s' % (task.get('status'), task.get('consumed_credits')))
    if task.get('status') != 'SUCCEEDED':
        print('MESHY rig error:', json.dumps(task.get('task_error')))
        sys.exit(1)


def cmd_rig(args):
    os.makedirs(args.out, exist_ok=True)
    body = {'height_meters': args.height}
    if args.task_id:
        body['input_task_id'] = args.task_id
    elif args.model:
        with open(args.model, 'rb') as handle:
            body['model_url'] = 'data:model/gltf-binary;base64,' + base64.b64encode(handle.read()).decode()
    else:
        sys.exit('meshy_rig: rig needs --task-id or --model')
    if args.texture:
        with open(args.texture, 'rb') as handle:
            body['texture_image_url'] = 'data:image/png;base64,' + base64.b64encode(handle.read()).decode()
    task_id = request('POST', 'rigging', body)['result']
    print('MESHY started rigging', task_id, flush=True)
    save_rig(args.out, poll('rigging', task_id))


def save_anim(out, task, action_id, name):
    res = task.get('result') or {}
    fname = 'anim_%s_%s.glb' % (action_id, slug(name))
    if res.get('animation_glb_url'):
        download(res['animation_glb_url'], os.path.join(out, fname))
    append_json(os.path.join(out, 'anims_meta.json'),
                {'action_id': action_id, 'name': name, 'file': fname, 'task_id': task.get('id'),
                 'status': task.get('status'), 'credits': task.get('consumed_credits'),
                 'task_error': task.get('task_error')})
    log({'time': time.strftime('%Y-%m-%d %H:%M'), 'name': '%s/%s' % (os.path.basename(out.rstrip('/')), fname),
         'task_id': task.get('id'), 'endpoint': 'animations', 'status': task.get('status'),
         'credits': task.get('consumed_credits')})
    print('MESHY anim %s %s %s, credits %s' % (action_id, name, task.get('status'), task.get('consumed_credits')))


def cmd_animate(args):
    os.makedirs(args.out, exist_ok=True)
    names = {}
    lib = request('GET', 'animations/library', query={'action_ids': ','.join(str(a) for a in args.action)})
    for r in (lib if isinstance(lib, list) else (lib.get('result') or lib.get('data') or [])):
        names[int(r.get('action_id', r.get('id', -1)))] = r.get('name') or r.get('key') or ''
    failed = 0
    for action_id in args.action:
        body = {'rig_task_id': args.rig_task, 'action_id': action_id}
        if args.fps:
            body['post_process'] = {'operation_type': 'change_fps', 'fps': args.fps}
        task_id = request('POST', 'animations', body)['result']
        print('MESHY started animation', action_id, names.get(action_id, ''), task_id, flush=True)
        task = poll('animations', task_id)
        save_anim(args.out, task, action_id, names.get(action_id, ''))
        failed += task.get('status') != 'SUCCEEDED'
    if failed:
        sys.exit(1)


def cmd_resume(args):
    os.makedirs(args.out, exist_ok=True)
    if args.rig:
        save_rig(args.out, poll('rigging', args.rig))
    elif args.anim:
        task = poll('animations', args.anim)
        save_anim(args.out, task, args.action_id or 0, args.name or '')


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('library')
    p.add_argument('--search')
    p.add_argument('--category')
    p.add_argument('--json', action='store_true')
    p = sub.add_parser('rig')
    p.add_argument('out')
    p.add_argument('--task-id')
    p.add_argument('--model')
    p.add_argument('--texture')
    p.add_argument('--height', type=float, default=1.7)
    p = sub.add_parser('animate')
    p.add_argument('out')
    p.add_argument('--rig-task', required=True)
    p.add_argument('--action', type=int, action='append', required=True)
    p.add_argument('--fps', type=int, default=0)
    p = sub.add_parser('resume')
    p.add_argument('out')
    p.add_argument('--rig')
    p.add_argument('--anim')
    p.add_argument('--action-id', type=int)
    p.add_argument('--name')
    args = ap.parse_args()
    {'library': cmd_library, 'rig': cmd_rig, 'animate': cmd_animate, 'resume': cmd_resume}[args.cmd](args)


if __name__ == '__main__':
    main()
