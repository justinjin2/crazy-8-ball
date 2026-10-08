#!/usr/bin/env python3
"""
Create the game's game passes and developer products through Open Cloud.

    POST https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes
    POST https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products

The list is tools/products_spec.json (key, kind Pass|Product, name, robux, description; the
same rows as docs/prompts/ECONOMY_PROMPT.md step 3). Anything already in products_ids.json, or
whose name already exists in the universe, is skipped, so a rerun only creates what is missing. Every item is made for sale
with Managed Pricing off (the VIP Welcome Offer's "half price" must stay true). The ids land in
tools/products_ids.json (key -> id); paste them into Config.Products.

--sync brings the passes and products already in products_ids.json in line with the spec: the
price, name and description, and isForSale (false for an item marked "retired", which is never
deleted). It reads each item's live row first and PATCHes only what differs (the same update
endpoints as --icons, form fields price, name, description, isForSale). Run it with --dry-run
first: a price change goes live in every server at once.

--icons sets the icon of the passes and products already in products_ids.json instead, from
tools/products_icons.json (key -> PNG path relative to the repo), through the update endpoints
(multipart/form-data, the image in the field imageFile; both answer 204 No Content):

    PATCH https://apis.roblox.com/game-passes/v1/universes/{u}/game-passes/{gamePassId}
    PATCH https://apis.roblox.com/developer-products/v2/universes/{u}/developer-products/{productId}

The key is read from the macOS Keychain (service ROBLOX_API_KEY, see docs/STUDIO_NOTES.md) and
is never printed or written anywhere. It needs game-pass and developer-product read and write.

Usage
    python3 tools/roblox_products.py --dry-run
    python3 tools/roblox_products.py --only UltSlot2
    python3 tools/roblox_products.py
    python3 tools/roblox_products.py --icons --dry-run
    python3 tools/roblox_products.py --icons --only Vip,Pack1
    python3 tools/roblox_products.py --describe --only Vip,VipOffer   (send descriptions again)
    python3 tools/roblox_products.py --sync --dry-run   (what would change: prices, names, text, sale)
    python3 tools/roblox_products.py --sync
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
REPO = os.path.dirname(HERE)
ICONS = os.path.join(HERE, "products_icons.json")
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


def live_rows(kind, universe, key):
    """Every pass or product in the universe: id -> its row."""
    rows, token = {}, ""
    while True:
        url = BASE[kind].format(universe) + "/creator?pageSize=50"
        if token:
            url += "&pageToken=" + token
        status, data = request("GET", url, key)
        if status != 200:
            sys.exit(f"List {kind} failed: HTTP {status} {data}")
        for row in data.get(LIST_FIELD[kind]) or []:
            rows[row[ID_FIELD[kind]]] = row
        token = data.get("nextPageToken") or ""
        if not token:
            return rows


def multipart(fields, files=None):
    """fields: name -> text value; files: name -> (path, content type)."""
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode()
        )
    for name, (path, ctype) in (files or {}).items():
        with open(path, "rb") as f:
            data = f.read()
        head = (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; '
            f'filename="{os.path.basename(path)}"\r\nContent-Type: {ctype}\r\n\r\n'
        )
        parts.append(head.encode() + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def set_icons(spec, args):
    """Set the icon of every pass and product in products_ids.json from products_icons.json."""
    universe = spec["universeId"]
    kinds = {item["key"]: item["kind"] for item in spec["items"]}
    ids = json.load(open(IDS))
    icons = json.load(open(ICONS))
    keys = list(ids)
    if args.only:
        wanted = set(args.only.split(","))
        keys = [k for k in keys if k in wanted]
    key = None if args.dry_run else api_key()
    failed = 0
    for k in keys:
        kind = kinds.get(k)
        path = icons.get(k)
        if not kind:
            print(f"skip    {k:<17} not in products_spec.json")
            continue
        if not path:
            print(f"skip    {k:<17} no icon in products_icons.json")
            continue
        full = os.path.join(REPO, path)
        if not os.path.isfile(full):
            print(f"FAILED  {k:<17} missing file {path}")
            failed += 1
            continue
        url = f"{BASE[kind].format(universe)}/{ids[k]}"
        if args.dry_run:
            print(f"icon    {k:<17} {kind:<7} {ids[k]}  {path}")
            continue
        body, content_type = multipart({}, {"imageFile": (full, "image/png")})
        status, data = request("PATCH", url, key, body, content_type)
        if status in (200, 204):
            print(f"set     {k:<17} {kind:<7} {ids[k]}  {path}")
        else:
            failed += 1
            print(f"FAILED  {k:<17} {kind:<7} {ids[k]}  HTTP {status} {data}")
    if failed:
        sys.exit(f"{failed} icon(s) failed")


def set_descriptions(spec, args):
    """Send every made pass's and product's description from products_spec.json again
    (Open Cloud PATCH, the form field `description`): for wording changes after creation."""
    universe = spec["universeId"]
    ids = json.load(open(IDS))
    items = [i for i in spec["items"] if i["key"] in ids]
    if args.only:
        wanted = set(args.only.split(","))
        items = [i for i in items if i["key"] in wanted]
    key = None if args.dry_run else api_key()
    failed = 0
    for item in items:
        k, kind = item["key"], item["kind"]
        url = f"{BASE[kind].format(universe)}/{ids[k]}"
        if args.dry_run:
            print(f"text    {k:<17} {kind:<7} {ids[k]}  {item['description']}")
            continue
        body, content_type = multipart({"description": item["description"]})
        status, data = request("PATCH", url, key, body, content_type)
        if status in (200, 204):
            print(f"set     {k:<17} {kind:<7} {ids[k]}")
        else:
            failed += 1
            print(f"FAILED  {k:<17} {kind:<7} {ids[k]}  HTTP {status} {data}")
    if failed:
        sys.exit(f"{failed} description(s) failed")


def sync(spec, args):
    """PATCH each made pass's and product's price, name, description and isForSale to the spec."""
    universe = spec["universeId"]
    ids = json.load(open(IDS))
    items = [i for i in spec["items"] if i["key"] in ids]
    if args.only:
        wanted = set(args.only.split(","))
        items = [i for i in items if i["key"] in wanted]
    key = api_key()
    rows = {kind: live_rows(kind, universe, key) for kind in BASE}
    failed = changed = 0
    for item in items:
        k, kind = item["key"], item["kind"]
        row = rows[kind].get(ids[k])
        if row is None:
            failed += 1
            print(f"FAILED  {k:<17} {kind:<7} {ids[k]}  not found in the universe")
            continue
        price = (row.get("priceInformation") or {}).get("defaultPriceInRobux")
        want = {
            "price": item["robux"],
            "name": item["name"],
            "description": item["description"],
            "isForSale": not item.get("retired"),
        }
        have = {
            "price": price,
            "name": row.get("name"),
            "description": row.get("description"),
            "isForSale": row.get("isForSale"),
        }
        if item.get("retired"):  # only taken off sale; its other fields stay as they were
            want = {"isForSale": False}
        diff = {f: v for f, v in want.items() if have[f] != v}
        if not diff:
            print(f"same    {k:<17} {kind:<7} {ids[k]}")
            continue
        changed += 1
        notes = []
        for f in diff:
            if f == "description":
                notes.append("description")
            else:
                notes.append(f"{f} {have[f]!r} -> {want[f]!r}")
        verb = "would" if args.dry_run else "set   "
        if args.dry_run:
            print(f"{verb}   {k:<17} {kind:<7} {ids[k]}  " + "; ".join(notes))
            continue
        fields = {f: (str(v).lower() if isinstance(v, bool) else v) for f, v in diff.items()}
        body, content_type = multipart(fields)
        status, data = request("PATCH", f"{BASE[kind].format(universe)}/{ids[k]}", key, body, content_type)
        if status in (200, 204):
            print(f"set     {k:<17} {kind:<7} {ids[k]}  " + "; ".join(notes))
        else:
            failed += 1
            print(f"FAILED  {k:<17} {kind:<7} {ids[k]}  HTTP {status} {data}")
    print(f"{changed} to change, {failed} failed")
    if failed:
        sys.exit(f"{failed} item(s) failed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only", help="comma-separated keys")
    parser.add_argument("--icons", action="store_true", help="set icons from products_icons.json")
    parser.add_argument(
        "--sync", action="store_true", help="bring prices, names, text and sale state in line with the spec"
    )
    parser.add_argument(
        "--describe", action="store_true", help="send the descriptions in products_spec.json again"
    )
    args = parser.parse_args()

    spec = json.load(open(SPEC))
    if args.icons:
        set_icons(spec, args)
        return
    if args.describe:
        set_descriptions(spec, args)
        return
    if args.sync:
        sync(spec, args)
        return
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
        if item["key"] in ids:  # made already (its name may have changed since: --sync renames it)
            print(f"exists  {item['key']:<17} {ids[item['key']]}  (in products_ids.json)")
            continue
        if item.get("retired"):
            continue
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
