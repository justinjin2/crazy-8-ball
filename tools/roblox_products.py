#!/usr/bin/env python3
"""
Create the game's game passes and developer products through Open Cloud.

    POST https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes
    POST https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products

The list is tools/products_spec.json (key, kind Pass|Product, name, robux, description; the
same rows as docs/prompts/ECONOMY_PROMPT.md step 3). Anything whose name already exists in
the universe is skipped, so a rerun only creates what is missing. Every item is made for sale
with Managed Pricing off (the VIP Welcome Offer's "half price" must stay true). The ids land in
tools/products_ids.json (key -> id); paste them into Config.Products.

The key is read from the macOS Keychain (service ROBLOX_API_KEY, see docs/STUDIO_NOTES.md) and
is never printed or written anywhere. It needs game-pass and developer-product read and write.

Usage
    python3 tools/roblox_products.py --dry-run
    python3 tools/roblox_products.py --only UltSlot2
    python3 tools/roblox_products.py
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HERE, "products_spec.json")
IDS = os.path.join(HERE, "products_ids.json")

BASE = {
    "Pass": "https://apis.roblox.com/game-passes/v1/universes/{}/game-passes",
    "Product": "https://apis.roblox.com/developer-products/v2/universes/{}/developer-products",
}
LIST_FIELD = {"Pass": "gamePasses", "Product": "developerProducts"}
ID_FIELD = {"Pass": "gamePassId", "Product": "productId"}


def api_key():
    out = subprocess.run(
        ["security", "find-generic-password", "-s", "ROBLOX_API_KEY", "-w"],
        capture_output=True,
        text=True,
    )
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit("No ROBLOX_API_KEY in the Keychain (docs/STUDIO_NOTES.md).")
    return out.stdout.strip()


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as err:
        return err.code, err.read().decode(errors="replace")[:500]


def existing(kind, universe, key):
    names, token = {}, ""
    while True:
        url = BASE[kind].format(universe) + "/creator?pageSize=50"
        if token:
            url += "&pageToken=" + token
        status, data = request("GET", url, key)
        if status != 200:
            sys.exit(f"List {kind} failed: HTTP {status} {data}")
        for row in data.get(LIST_FIELD[kind]) or []:
            names[row["name"]] = row[ID_FIELD[kind]]
        token = data.get("nextPageToken") or ""
        if not token:
            return names


def multipart(fields):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
        )
    parts.append(f"--{boundary}--\r\n")
    return "".join(parts).encode(), f"multipart/form-data; boundary={boundary}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only", help="comma-separated keys")
    args = parser.parse_args()

    spec = json.load(open(SPEC))
    universe = spec["universeId"]
    items = spec["items"]
    if args.only:
        wanted = set(args.only.split(","))
        items = [i for i in items if i["key"] in wanted]

    key = api_key()
    ids = json.load(open(IDS)) if os.path.exists(IDS) else {}
    have = {kind: existing(kind, universe, key) for kind in BASE}

    for item in items:
        kind, name = item["kind"], item["name"]
        if name in have[kind]:
            ids[item["key"]] = have[kind][name]
            print(f"exists  {item['key']:<17} {have[kind][name]}  {name}")
            continue
        if args.dry_run:
            print(f"create  {item['key']:<17} {kind:<7} {item['robux']:>5} R$  {name}")
            continue
        body, content_type = multipart(
            {
                "name": name,
                "description": item["description"],
                "price": item["robux"],
                "isForSale": "true",
                "isManagedPricingEnabled": "false",
            }
        )
        status, data = request("POST", BASE[kind].format(universe), key, body, content_type)
        if status != 200:
            print(f"FAILED  {item['key']:<17} HTTP {status} {data}")
            continue
        ids[item["key"]] = data[ID_FIELD[kind]]
        print(f"created {item['key']:<17} {ids[item['key']]}  {name}")
        with open(IDS, "w") as f:
            json.dump(ids, f, indent=1)

    with open(IDS, "w") as f:
        json.dump(ids, f, indent=1)


if __name__ == "__main__":
    main()
