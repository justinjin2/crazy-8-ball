#!/usr/bin/env python3
"""Meshy image-to-3D for the cue skins' creature models. Standard library only.

    python3 tools/meshy_generate.py <name> --image ref.png [--image side.png ...]
        [--texture-prompt "..."] [--polycount 30000] [--model latest] [--no-pbr]
        [--texture-resolution 2k] [--geometry standard|2k]
    python3 tools/meshy_generate.py <name> --resume <task id> [--multi]
    python3 tools/meshy_generate.py --log          (every task so far and the credits used)

One --image calls Image to 3D; two to four call Multi-Image to 3D (the first is the front view).
Images go up as base64 data URIs. The task is polled until it finishes, then the GLB, every
texture map (base colour, and with PBR metallic, roughness, normal, emission) and the preview
thumbnail are saved to assets/cue/models/<name>/, with meta.json (the task, its parameters and
consumed_credits). Every task is appended to assets/cue/models/meshy_log.jsonl.

The key is read from the macOS Keychain (service MESHY_API_KEY) and never printed or written.
"""

import argparse
import base64
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, 'assets', 'cue', 'models')
LOG = os.path.join(MODELS, 'meshy_log.jsonl')
API = 'https://api.meshy.ai/openapi/v1/'
POLL_SECONDS = 10
TIMEOUT_SECONDS = 30 * 60


def api_key():
    out = subprocess.run(['security', 'find-generic-password', '-s', 'MESHY_API_KEY', '-w'],
                         capture_output=True, text=True)
    key = out.stdout.strip()
    if out.returncode != 0 or not key:
        sys.exit('meshy_generate: no MESHY_API_KEY in the Keychain')
    return key


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header('Authorization', 'Bearer ' + api_key())
    if data is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as err:
        sys.exit('meshy_generate: HTTP %d on %s %s: %s' % (err.code, method, path, err.read().decode()[:600]))


def data_uri(path):
    mime = mimetypes.guess_type(path)[0] or 'image/png'
    with open(path, 'rb') as handle:
        return 'data:%s;base64,%s' % (mime, base64.b64encode(handle.read()).decode())


def download(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as resp, open(path, 'wb') as out:
        out.write(resp.read())
    print('MESHY saved', os.path.relpath(path, ROOT))


def log(entry):
    os.makedirs(MODELS, exist_ok=True)
    with open(LOG, 'a') as handle:
        handle.write(json.dumps(entry) + '\n')


def show_log():
    total = 0
    if os.path.isfile(LOG):
        for line in open(LOG):
            e = json.loads(line)
            total += e.get('credits') or 0
            print('%s  %-24s %-8s credits %s' % (e.get('time', ''), e.get('name', ''), e.get('status', ''),
                                                 e.get('credits')))
    print('MESHY total credits:', total)


def poll(kind, task_id):
    start = time.time()
    last = None
    while True:
        task = request('GET', '%s/%s' % (kind, task_id))
        status = task.get('status')
        prog = task.get('progress')
        if (status, prog) != last:
            print('MESHY %s %s %s%%' % (task_id, status, prog), flush=True)
            last = (status, prog)
        if status in ('SUCCEEDED', 'FAILED', 'CANCELED'):
            return task
        if time.time() - start > TIMEOUT_SECONDS:
            sys.exit('meshy_generate: timed out waiting for ' + task_id)
        time.sleep(POLL_SECONDS)


def save(name, kind, task, params):
    out = os.path.join(MODELS, name)
    os.makedirs(out, exist_ok=True)
    urls = task.get('model_urls') or {}
    if urls.get('glb'):
        download(urls['glb'], os.path.join(out, 'model.glb'))
    for i, maps in enumerate(task.get('texture_urls') or []):
        for key, url in maps.items():
            if url:
                download(url, os.path.join(out, '%s%s.png' % (key, '' if i == 0 else '_%d' % i)))
    if task.get('thumbnail_url'):
        download(task['thumbnail_url'], os.path.join(out, 'thumbnail.png'))
    meta = {'name': name, 'endpoint': kind, 'task_id': task.get('id'), 'status': task.get('status'),
            'credits': task.get('consumed_credits'), 'params': params,
            'finished_at': task.get('finished_at'), 'task_error': task.get('task_error')}
    with open(os.path.join(out, 'meta.json'), 'w') as handle:
        json.dump(meta, handle, indent=2)
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('name', nargs='?')
    ap.add_argument('--image', dest='images', action='append', default=[])
    ap.add_argument('--texture-prompt')
    ap.add_argument('--texture-image')
    ap.add_argument('--polycount', type=int, default=0)
    ap.add_argument('--model', default='latest')
    ap.add_argument('--no-pbr', action='store_true')
    ap.add_argument('--no-texture', action='store_true')
    ap.add_argument('--texture-resolution', default='2k')
    ap.add_argument('--geometry', default='standard')
    ap.add_argument('--symmetry', default='')
    ap.add_argument('--resume')
    ap.add_argument('--multi', action='store_true')
    ap.add_argument('--log', action='store_true')
    args = ap.parse_args()
    if args.log:
        show_log()
        return
    if not args.name:
        ap.error('name is required')

    multi = args.multi or len(args.images) > 1
    kind = 'multi-image-to-3d' if multi else 'image-to-3d'
    params = {}
    if args.resume:
        task_id = args.resume
    else:
        if not args.images:
            ap.error('--image is required')
        params = {'ai_model': args.model, 'should_texture': not args.no_texture,
                  'enable_pbr': not args.no_pbr, 'geometry_resolution': args.geometry,
                  'target_formats': ['glb']}
        if not args.no_texture and not multi:
            params['texture_resolution'] = args.texture_resolution
        if args.texture_prompt:
            params['texture_prompt'] = args.texture_prompt[:800]
        if args.texture_image and not multi:
            params['texture_image_url'] = data_uri(args.texture_image)
        if args.polycount:
            params['should_remesh'] = True
            params['target_polycount'] = args.polycount
            params['topology'] = 'triangle'
        if args.symmetry:
            params['symmetry_mode'] = args.symmetry
        body = dict(params)
        if multi:
            body['image_urls'] = [data_uri(p) for p in args.images[:4]]
        else:
            body['image_url'] = data_uri(args.images[0])
        task_id = request('POST', kind, body)['result']
        print('MESHY started', kind, task_id, flush=True)
        params = {k: v for k, v in params.items() if k != 'texture_image_url'}
        params['images'] = [os.path.relpath(p, ROOT) if os.path.isabs(p) else p for p in args.images]
    task = poll(kind, task_id)
    meta = save(args.name, kind, task, params)
    log({'time': time.strftime('%Y-%m-%d %H:%M'), 'name': args.name, 'task_id': task_id, 'endpoint': kind,
         'status': task.get('status'), 'credits': task.get('consumed_credits')})
    print('MESHY %s %s, credits %s' % (args.name, task.get('status'), meta['credits']))
    if task.get('status') != 'SUCCEEDED':
        sys.exit(1)


if __name__ == '__main__':
    main()
