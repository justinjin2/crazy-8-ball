#!/usr/bin/env python3
"""Fill in `imageId` for uploaded images in tools/upload_manifest.json.

Open Cloud uploads a PNG as a Decal; ImageLabels, SurfaceAppearances and ParticleEmitters
need the image inside it, which only Studio can read (docs/STUDIO_NOTES.md, "Images come back as
a Decal ID"). Two steps, as often as needed:

    python3 tools/manifest_image_ids.py emit [--limit 120] [--prefix assets/cue/] > batch.luau
        prints a Luau snippet: run it in Studio's Edit mode (Studio MCP execute_luau); it
        returns one "decalId=imageId" line per Decal (or "decalId=ERR ...")
    python3 tools/manifest_image_ids.py apply result.txt
        writes each imageId into the manifest entries with that assetId
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, 'tools', 'upload_manifest.json')

LUAU = '''local InsertService = game:GetService("InsertService")
local out = {}
for _, id in { %s } do
	local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
	local decal = ok and model:FindFirstChildWhichIsA("Decal", true)
	local image = decal and string.match(decal.Texture, "%%d+")
	table.insert(out, ("%%d=%%s"):format(id, image or ("ERR " .. tostring(model))))
	if ok then
		model:Destroy()
	end
end
return table.concat(out, "\\n")
'''


def load():
    return json.load(open(MANIFEST))


def pending(manifest, prefix):
    rows = []
    for path, row in sorted(manifest.items()):
        rel = os.path.relpath(path, ROOT)
        if (row.get('status') == 'ok' and row.get('assetType') == 'Decal' and not row.get('imageId')
                and rel.startswith(prefix)):
            rows.append(row['assetId'])
    return rows


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ('emit', 'apply'):
        sys.exit(__doc__)
    manifest = load()
    if args[0] == 'emit':
        limit = int(args[args.index('--limit') + 1]) if '--limit' in args else 120
        prefix = args[args.index('--prefix') + 1] if '--prefix' in args else 'assets/cue/'
        ids = pending(manifest, prefix)
        sys.stderr.write('%d decals without an image id; emitting %d\n' % (len(ids), min(limit, len(ids))))
        print(LUAU % ', '.join(ids[:limit]))
        return
    pairs = {}
    for line in open(args[1]):
        line = line.strip()
        if '=' in line:
            decal, image = line.split('=', 1)
            if image.isdigit():
                pairs[decal] = image
            else:
                print('not resolved: %s %s' % (decal, image))
    n = 0
    for row in manifest.values():
        if row.get('assetId') in pairs and not row.get('imageId'):
            row['imageId'] = pairs[row['assetId']]
            n += 1
    with open(MANIFEST, 'w', encoding='utf-8') as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
    print('filled %d image ids; %d decals still without one' % (n, len(pending(manifest, 'assets/'))))


if __name__ == '__main__':
    main()
