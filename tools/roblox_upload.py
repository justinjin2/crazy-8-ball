#!/usr/bin/env python3
"""
Upload audio / models / images to Roblox through the Open Cloud Assets API.

    POST https://apis.roblox.com/assets/v1/assets     -> returns an Operation
    GET  https://apis.roblox.com/assets/v1/operations/{id}  -> poll until done

The key is read from the ROBLOX_API_KEY environment variable and is never
written to the manifest, the log, or anywhere else.

Usage
    python roblox_upload.py --list files.txt --dry-run
    python roblox_upload.py --list files.txt
    python roblox_upload.py --dir ./sounds --type Audio

Every result lands in manifest.json keyed by absolute source path, so a second
run skips whatever already succeeded. Audio is quota-limited by Roblox (100 a
month if the account is ID-verified, 10 if not), which is why nothing here
uploads a whole folder unless you say so explicitly.
"""

import argparse
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

CREATE_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_URL = "https://apis.roblox.com/assets/v1/operations/{}"

MAX_BYTES = 20 * 1024 * 1024  # Roblox rejects anything larger

# extension -> (assetType, content-type). .obj is deliberately absent: Open
# Cloud does not accept it, convert to .fbx or .glb first.
KINDS = {
    ".mp3": ("Audio", "audio/mpeg"),
    ".ogg": ("Audio", "audio/ogg"),
    ".wav": ("Audio", "audio/wav"),
    ".flac": ("Audio", "audio/flac"),
    ".fbx": ("Model", "model/fbx"),
    ".glb": ("Model", "model/gltf-binary"),
    ".gltf": ("Model", "model/gltf+json"),
    ".rbxm": ("Model", "model/x-rbxm"),
    # A KeyframeSequence saved as XML uploads as an Animation (use --force-type Animation).
    ".rbxmx": ("Animation", "model/x-rbxm"),
    ".png": ("Decal", "image/png"),
    ".jpg": ("Decal", "image/jpeg"),
    ".jpeg": ("Decal", "image/jpeg"),
    ".bmp": ("Decal", "image/bmp"),
    ".tga": ("Decal", "image/tga"),
}


def kind_for(path):
    return KINDS.get(os.path.splitext(path)[1].lower())


def build_multipart(request_json, file_path, content_type):
    """Assemble a multipart/form-data body with stdlib only."""
    boundary = "----roblox" + uuid.uuid4().hex
    sep = ("--" + boundary).encode()
    out = []

    out.append(sep)
    out.append(b'Content-Disposition: form-data; name="request"')
    out.append(b"Content-Type: application/json")
    out.append(b"")
    out.append(json.dumps(request_json).encode("utf-8"))

    with open(file_path, "rb") as handle:
        blob = handle.read()

    name = os.path.basename(file_path).encode("utf-8")
    out.append(sep)
    out.append(b'Content-Disposition: form-data; name="fileContent"; filename="' + name + b'"')
    out.append(b"Content-Type: " + content_type.encode())
    out.append(b"")
    out.append(blob)
    out.append(("--" + boundary + "--").encode())

    return b"\r\n".join(out), "multipart/form-data; boundary=" + boundary


def call(url, api_key, data=None, content_type=None):
    request = urllib.request.Request(url, data=data)
    request.add_header("x-api-key", api_key)
    if content_type:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return response.status, json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", "replace")
        try:
            return err.code, json.loads(body)
        except ValueError:
            return err.code, {"raw": body[:400]}


def upload(path, api_key, creator, display_name=None, description="", poll_for=180, force_type=None):
    kind = kind_for(path)
    if not kind:
        return {"status": "skipped", "reason": "unsupported extension"}

    asset_type, content_type = kind
    if force_type:
        asset_type = force_type
    size = os.path.getsize(path)
    if size > MAX_BYTES:
        return {"status": "skipped", "reason": "over 20MB (%.1fMB)" % (size / 1048576)}

    payload = {
        "assetType": asset_type,
        "displayName": display_name or os.path.splitext(os.path.basename(path))[0],
        "description": description or "Uploaded via Open Cloud",
        "creationContext": {"creator": creator},
    }

    body, ctype = build_multipart(payload, path, content_type)
    status, result = call(CREATE_URL, api_key, body, ctype)
    if status not in (200, 201):
        return {"status": "error", "httpStatus": status, "detail": result}

    operation = result.get("operationId") or (result.get("path") or "").split("/")[-1]
    if not operation:
        return {"status": "error", "detail": result}

    # Moderation runs before the id exists, so this can take a little while.
    deadline = time.time() + poll_for
    while time.time() < deadline:
        time.sleep(2)
        status, result = call(OPERATION_URL.format(operation), api_key)
        if status not in (200, 201):
            return {"status": "error", "httpStatus": status, "detail": result}
        if result.get("done"):
            response = result.get("response") or {}
            asset_id = response.get("assetId")
            if asset_id:
                return {"status": "ok", "assetId": str(asset_id), "assetType": asset_type}
            return {"status": "error", "detail": result}

    return {"status": "pending", "operationId": operation,
            "note": "still moderating; re-run to pick it up"}


def read_api_key():
    """
    Prefer the macOS Keychain (or the Windows registry), fall back to the environment.

    On a Mac the key lives in the login Keychain as a generic password with
    service ROBLOX_API_KEY, added with
        security add-generic-password -a "$USER" -s ROBLOX_API_KEY -w
    so it is never in a shell profile or a file. On Windows, setx writes to the
    user Environment registry key, but a process that was already running when
    it was set keeps the old environment, and so does everything it spawns. The
    registry is the CURRENT key: after a key rotation the inherited environment
    still held the dead one (401).
    """
    if sys.platform == "darwin":
        try:
            found = subprocess.run(
                ["security", "find-generic-password", "-s", "ROBLOX_API_KEY", "-w"],
                capture_output=True, text=True, timeout=10)
            if found.returncode == 0 and found.stdout.strip():
                return found.stdout.strip()
        except Exception:
            pass
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as handle:
            value, _ = winreg.QueryValueEx(handle, "ROBLOX_API_KEY")
            if value:
                return value
    except Exception:
        pass
    return os.environ.get("ROBLOX_API_KEY") or None


def load_manifest(path):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    return {}


def save_manifest(path, data):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, sort_keys=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--list", help="text file with one path per line")
    source.add_argument("--dir", help="directory to take files from (not recursive)")
    parser.add_argument("--type", help="only upload this asset type (Audio/Model/Decal/Animation)")
    parser.add_argument("--force-type", help="upload every queued file as this asset type (e.g. Animation for .rbxmx)")
    parser.add_argument("--manifest", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "upload_manifest.json"))
    # No default owner: an asset must belong to whoever owns the place, or the
    # game cannot load it. Crazy 8 Ball is group-owned: --group-id 675425213.
    owner = parser.add_mutually_exclusive_group(required=True)
    owner.add_argument("--user-id")
    # Uploading under the group is usually what you want: a group-owned audio
    # asset is usable by that group's experiences without whitelisting each one.
    owner.add_argument("--group-id")
    parser.add_argument("--limit", type=int, default=0, help="stop after N uploads")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    creator = {"groupId": str(args.group_id)} if args.group_id else {"userId": str(args.user_id)}

    api_key = read_api_key()
    if not api_key and not args.dry_run:
        sys.exit("ROBLOX_API_KEY is not set (checked the environment and the registry).")

    if args.list:
        with open(args.list, encoding="utf-8") as handle:
            files = [line.strip() for line in handle if line.strip() and not line.startswith("#")]
    else:
        files = [os.path.join(args.dir, name) for name in sorted(os.listdir(args.dir))]
        files = [f for f in files if os.path.isfile(f)]

    manifest = load_manifest(args.manifest)
    queue = []
    for path in files:
        path = os.path.abspath(path)
        kind = kind_for(path)
        if not kind:
            continue
        if args.type and kind[0] != args.type:
            continue
        if manifest.get(path, {}).get("status") == "ok":
            continue
        queue.append((path, kind[0]))

    counts = {}
    for _, asset_type in queue:
        counts[asset_type] = counts.get(asset_type, 0) + 1
    print("queued: " + (", ".join("%d %s" % (n, t) for t, n in sorted(counts.items())) or "nothing"))
    print("uploading as: " + json.dumps(creator))

    if args.dry_run:
        for path, asset_type in queue[:50]:
            print("  %-6s %s" % (asset_type, path))
        if len(queue) > 50:
            print("  ... and %d more" % (len(queue) - 50))
        if counts.get("Audio", 0) > 10:
            print("\nNOTE: %d audio files. Roblox allows 100 audio uploads a month on an "
                  "ID-verified account, 10 otherwise." % counts["Audio"])
        return

    done = 0
    for path, _ in queue:
        if args.limit and done >= args.limit:
            print("stopping at --limit %d" % args.limit)
            break
        result = upload(path, api_key, creator, force_type=args.force_type)
        manifest[path] = result
        save_manifest(args.manifest, manifest)
        label = result.get("assetId") or result.get("reason") or result.get("httpStatus") or ""
        print("%-8s %-50s %s" % (result["status"], os.path.basename(path)[:50], label))
        if result["status"] == "error":
            detail = json.dumps(result.get("detail", ""))[:200]
            print("         %s" % detail)
        done += 1

    print("\nmanifest written to %s" % args.manifest)


if __name__ == "__main__":
    main()
