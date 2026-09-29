#!/usr/bin/env python3
"""OpenAI images for the cue skins (the texture painter and sprite maker). Standard library only.

    python3 tools/openai_image.py --prompt "..." --out assets/cue/skins/<id>/forearm_raw.png \
        [--image layout.png --image concept_crop.png ...] [--size 1536x1024] [--quality high] \
        [--background transparent|opaque|auto] [--model gpt-image-2.5-sunburst] [--tag <skin id>]

With one or more --image it calls the edits endpoint (the first image is the layout, the rest
are design references); with none it calls generations. Every call is appended to
assets/cue/concepts/openai_log.jsonl (model, size, quality, the usage returned, an estimated
cost, the output path) and the running estimate is printed.

The key is read from the macOS Keychain (service OPENAI_API_KEY) and never printed or written.
    --total   print the running estimated spend and exit
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
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(ROOT, 'assets', 'cue', 'concepts', 'openai_log.jsonl')
API = 'https://api.openai.com/v1/images/'

# The newest gpt-image the key can use (listed from /v1/models on 2026-09-29): GPT Image 2.5,
# whose Sunburst variant holds intricate detail and precise edits (the panels need exact zone
# lines); Flare is the fast one.
DEFAULT_MODEL = 'gpt-image-2.5-sunburst'

# Estimated USD per million tokens. GPT Image 2.5 shares GPT Image 2's token rates; the image
# input rate is taken at the higher of the two published figures so the estimate errs high.
RATES = {'text_in': 5.0, 'image_in': 8.0, 'cached_in': 1.25, 'image_out': 30.0, 'text_out': 10.0}
SPEND_NOTE_EVERY = 25.0  # the brief: a chat note at every $25
SPEND_STOP = 150.0  # the brief: stop and ask before the estimate passes this


def api_key():
    out = subprocess.run(['security', 'find-generic-password', '-s', 'OPENAI_API_KEY', '-w'],
                         capture_output=True, text=True)
    key = out.stdout.strip()
    if out.returncode != 0 or not key:
        sys.exit('openai_image: no OPENAI_API_KEY in the Keychain')
    return key


def total_spend():
    total = 0.0
    if os.path.isfile(LOG):
        with open(LOG) as handle:
            for line in handle:
                line = line.strip()
                if line:
                    total += float(json.loads(line).get('cost_usd', 0) or 0)
    return total


def estimate(usage):
    if not usage:
        return 0.0
    details = usage.get('input_tokens_details') or {}
    text_in = details.get('text_tokens', 0) or 0
    image_in = details.get('image_tokens', 0) or 0
    cached = details.get('cached_tokens', 0) or 0
    if not details:
        text_in = usage.get('input_tokens', 0) or 0
    out_details = usage.get('output_tokens_details') or {}
    image_out = out_details.get('image_tokens', usage.get('output_tokens', 0)) or 0
    text_out = out_details.get('text_tokens', 0) or 0
    return (text_in * RATES['text_in'] + image_in * RATES['image_in'] + cached * RATES['cached_in']
            + image_out * RATES['image_out'] + text_out * RATES['text_out']) / 1e6


def multipart(fields, files):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields:
        parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n'
                      % (boundary, name, value)).encode())
    for name, path in files:
        mime = mimetypes.guess_type(path)[0] or 'application/octet-stream'
        with open(path, 'rb') as handle:
            data = handle.read()
        parts.append(('--%s\r\nContent-Disposition: form-data; name="%s"; filename="%s"\r\n'
                      'Content-Type: %s\r\n\r\n' % (boundary, name, os.path.basename(path), mime)).encode()
                     + data + b'\r\n')
    parts.append(('--%s--\r\n' % boundary).encode())
    return b''.join(parts), 'multipart/form-data; boundary=' + boundary


def call(args):
    key = api_key()
    fields = [('model', args.model), ('prompt', args.prompt), ('size', args.size),
              ('quality', args.quality), ('n', '1')]
    if args.background:
        fields.append(('background', args.background))
    if args.images:
        body, ctype = multipart(fields, [('image[]', p) for p in args.images])
        url = API + 'edits'
    else:
        payload = {k: v for k, v in fields}
        payload['n'] = 1
        body, ctype = json.dumps(payload).encode(), 'application/json'
        url = API + 'generations'
    request = urllib.request.Request(url, data=body, method='POST',
                                     headers={'Authorization': 'Bearer ' + key, 'Content-Type': ctype})
    last = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=600) as response:
                return json.load(response), url
        except urllib.error.HTTPError as exc:
            text = exc.read().decode('utf-8', 'replace')
            last = 'HTTP %d: %s' % (exc.code, text[:600])
            if exc.code in (429, 500, 502, 503, 504):
                time.sleep(10 * (attempt + 1))
                continue
            break
        except (urllib.error.URLError, TimeoutError) as exc:
            last = str(exc)
            time.sleep(10 * (attempt + 1))
    sys.exit('openai_image: ' + (last or 'failed'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prompt')
    parser.add_argument('--prompt-file')
    parser.add_argument('--image', dest='images', action='append', default=[])
    parser.add_argument('--out')
    parser.add_argument('--size', default='1536x1024')
    parser.add_argument('--quality', default='high')
    parser.add_argument('--background')
    parser.add_argument('--model', default=DEFAULT_MODEL)
    parser.add_argument('--tag', default='')
    parser.add_argument('--total', action='store_true')
    args = parser.parse_args()
    before = total_spend()
    if args.total:
        print('openai_image: estimated spend so far $%.2f' % before)
        return
    if args.prompt_file:
        with open(args.prompt_file) as handle:
            args.prompt = handle.read()
    if not args.prompt or not args.out:
        sys.exit('openai_image: --prompt (or --prompt-file) and --out are required')
    if before >= SPEND_STOP - 0.5:
        sys.exit('openai_image: STOP - the estimate ($%.2f) is at the $%.0f limit; ask the designer'
                 % (before, SPEND_STOP))
    started = time.time()
    data, url = call(args)
    item = data['data'][0]
    raw = base64.b64decode(item['b64_json'])
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'wb') as handle:
        handle.write(raw)
    usage = data.get('usage') or {}
    cost = estimate(usage)
    entry = {'time': time.strftime('%Y-%m-%dT%H:%M:%S'), 'tag': args.tag, 'model': args.model,
             'endpoint': url.rsplit('/', 1)[-1], 'size': args.size, 'quality': args.quality,
             'background': args.background or '', 'inputs': [os.path.relpath(p, ROOT) for p in args.images],
             'usage': usage, 'cost_usd': round(cost, 4), 'seconds': round(time.time() - started, 1),
             'out': os.path.relpath(os.path.abspath(args.out), ROOT)}
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, 'a') as handle:
        handle.write(json.dumps(entry) + '\n')
    after = before + cost
    print('openai_image: wrote %s ($%.3f, total $%.2f)' % (entry['out'], cost, after))
    if int(after // SPEND_NOTE_EVERY) > int(before // SPEND_NOTE_EVERY):
        print('openai_image: SPEND NOTE - passed $%d' % (int(after // SPEND_NOTE_EVERY) * SPEND_NOTE_EVERY))


if __name__ == '__main__':
    main()
