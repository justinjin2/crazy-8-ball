#!/usr/bin/env python3
"""
Create the game's Roblox badges through Open Cloud and write their ids back into Config.

    python3 tools/roblox_badges.py --probe    quota, price, and a deliberately invalid create
                                              (proves the key and scope; charges nothing)

The key is Painicane's user key, Keychain service ROBLOX_USER_KEY (Creator Hub offers the
legacy badge scopes only on user keys; ROBLOX_API_KEY is the group key and has none). It is
sent only as the x-api-key header and is never printed, logged or written anywhere.
"""

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

UNIVERSE_ID = 10767330648
KEY_SERVICE = "ROBLOX_USER_KEY"
QUOTA_URL = "https://badges.roblox.com/v1/universes/{}/free-badges-quota"
METADATA_URL = "https://badges.roblox.com/v1/badges/metadata"
CREATE_URL = "https://apis.roblox.com/legacy-badges/v1/universes/{}/badges"
SCOPE_MESSAGE = (
    "the API key needs scope `legacy-universe.badge:manage-and-spend-robux` on universe "
    f"{UNIVERSE_ID}, and its owner needs the group's spend-funds permission"
)


def read_api_key():
    """The user key from the macOS Keychain (service ROBLOX_USER_KEY), else the environment."""
    if sys.platform == "darwin":
        try:
            found = subprocess.run(
                ["security", "find-generic-password", "-s", KEY_SERVICE, "-w"],
                capture_output=True, text=True, timeout=10)
            if found.returncode == 0 and found.stdout.strip():
                return found.stdout.strip()
        except Exception:
            pass
    import os
    return os.environ.get(KEY_SERVICE, "").strip()


def multipart(fields, file_path=None):
    """multipart/form-data body from text fields plus an optional PNG under `files`."""
    boundary = "----badge" + uuid.uuid4().hex
    out = []
    for name, value in fields.items():
        out.append(("--" + boundary).encode())
        out.append(f'Content-Disposition: form-data; name="{name}"'.encode())
        out.append(b"")
        out.append(str(value).encode("utf-8"))
    if file_path:
        with open(file_path, "rb") as handle:
            blob = handle.read()
        out.append(("--" + boundary).encode())
        out.append(b'Content-Disposition: form-data; name="files"; filename="icon.png"')
        out.append(b"Content-Type: image/png")
        out.append(b"")
        out.append(blob)
    out.append(("--" + boundary + "--").encode())
    return b"\r\n".join(out) + b"\r\n", "multipart/form-data; boundary=" + boundary


def call(url, api_key=None, data=None, content_type=None, method=None):
    """(status, parsed JSON) for one request; never raises on an HTTP error."""
    request = urllib.request.Request(url, data=data, method=method)
    if api_key:
        request.add_header("x-api-key", api_key)
    if content_type:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", "replace")
        try:
            return err.code, json.loads(body)
        except ValueError:
            return err.code, {"raw": body[:300]}


def error_codes(body):
    return [e.get("code") for e in (body.get("errors") or []) if isinstance(e, dict)]


def probe():
    status, quota = call(QUOTA_URL.format(UNIVERSE_ID))
    print(f"free quota today: HTTP {status} -> {quota}")
    status, meta = call(METADATA_URL)
    print(f"metadata: HTTP {status} -> {meta}")
    api_key = read_api_key()
    if not api_key:
        print(f"no key in the Keychain under {KEY_SERVICE}")
        return 2
    # Empty name and an invalid payment source: Roblox must refuse it before any charge.
    body, ctype = multipart({"name": "", "description": "", "paymentSourceType": 0,
                             "expectedCost": 0, "isActive": "false"})
    status, reply = call(CREATE_URL.format(UNIVERSE_ID), api_key, body, ctype, "POST")
    codes = error_codes(reply)
    messages = [e.get("message") for e in (reply.get("errors") or []) if isinstance(e, dict)]
    print(f"invalid create: HTTP {status}, codes {codes}, messages {messages}")
    if status == 400 and any(c in (14, 16) for c in codes):
        print("scope OK: the key reached validation and nothing was charged")
        return 0
    if status == 401 or (status == 403 and any(c in (0, 12) for c in codes)):
        print("SCOPE MISSING: " + SCOPE_MESSAGE)
        return 1
    print("unexpected reply: read it before creating anything")
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--probe", action="store_true", help="quota, price and an invalid create")
    args = parser.parse_args()
    if args.probe:
        return probe()
    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
