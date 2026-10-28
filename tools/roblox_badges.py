#!/usr/bin/env python3
"""
Create the game's Roblox badges through Open Cloud and write their ids back into Config.

    python3 tools/roblox_badges.py              dry run: the plan (key, name, cost, running total)
    python3 tools/roblox_badges.py --create [--only Key ...] [--limit N] [--max-spend 4700]
    python3 tools/roblox_badges.py --write-config   manifest ids over `BadgeId = 0` in Config
    python3 tools/roblox_badges.py --probe    quota, price, and a deliberately invalid create
                                              (proves the key and scope; charges nothing)
    python3 tools/roblox_badges.py --self-test    offline checks of the guards and write-back
    python3 tools/roblox_badges.py --sync [--icons] [--only Key ...] [--apply]
                                              names and descriptions (and with --icons the
                                              icons) from Strings and assets onto the made
                                              badges, and every manifest badge no longer in
                                              Config disabled; a dry run unless --apply (free)

The rows come from `lune run tools/export_badges.luau` (Config.Badges + Strings.Badges), so
the game and Roblox never disagree. Every created badge goes into tools/badges_manifest.json
right after Roblox answers, before the next call; a re-run skips a key already in the
manifest or already on the universe under the same name (recorded into the manifest by name),
so a crash never pays twice; a create that gets no answer (timeout) stops the run. The
cost is 0 while the day's free quota lasts, then the metadata price; a cost above
MAX_COST_EACH or a running total above --max-spend refuses the call. Payment: group funds
(paymentSourceType 2; the universe belongs to group 675425213).

The key is Painicane's user key, Keychain service ROBLOX_USER_KEY (Creator Hub offers the
legacy badge scopes only on user keys; ROBLOX_API_KEY is the group key and has none). It is
sent only as the x-api-key header and is never printed, logged or written anywhere.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

UNIVERSE_ID = 10767330648
KEY_SERVICE = "ROBLOX_USER_KEY"
QUOTA_URL = "https://badges.roblox.com/v1/universes/{}/free-badges-quota"
METADATA_URL = "https://badges.roblox.com/v1/badges/metadata"
CREATE_URL = "https://apis.roblox.com/legacy-badges/v1/universes/{}/badges"
LIST_URL = "https://badges.roblox.com/v1/universes/{}/badges?limit=100&sortOrder=Asc"
UPDATE_URL = "https://apis.roblox.com/legacy-badges/v1/badges/{}"  # PATCH name, description, enabled
ICON_URL = "https://apis.roblox.com/legacy-publish/v1/badges/{}/icon"  # POST a new icon (moderated)
INFO_URL = "https://badges.roblox.com/v1/badges/{}"
ICON_VERSION = 2  # the hand-drawn pool balls (designer, 2026-10-28); the manifest notes what is up
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "tools", "badges_manifest.json")
CONFIG = os.path.join(ROOT, "src", "shared", "Config.luau")
PAYMENT_GROUP = 2  # paymentSourceType: 1 user funds, 2 group funds (the spec's order)
MAX_COST_EACH = 100  # Robux: never pay more than Roblox's price for one badge
DEFAULT_MAX_SPEND = 4700  # Robux: the designer's approval for today's 52 (47 paid)
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


NETWORK = 0  # call()'s status when no answer came back (timeout, reset, DNS): outcome unknown


def call(url, api_key=None, data=None, content_type=None, method=None):
    """(status, parsed JSON) for one request; never raises on an HTTP or network error.

    A network error returns NETWORK: for a create POST that means it may have been charged."""
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
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as err:
        return NETWORK, {"network": str(getattr(err, "reason", err))[:200]}


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


def export_rows():
    """The registry rows from Config + Strings, in registry order."""
    out = subprocess.run(["lune", "run", "tools/export_badges.luau"], cwd=ROOT,
                         capture_output=True, text=True, check=True)
    data = json.loads(out.stdout)
    if data["universeId"] != UNIVERSE_ID:
        raise SystemExit(f"Config.Badges.UniverseId {data['universeId']} is not {UNIVERSE_ID}")
    return data["rows"]


def load_manifest(path=MANIFEST):
    if os.path.exists(path):
        with open(path) as handle:
            return json.load(handle)
    return {}


def save_manifest(manifest, path=MANIFEST):
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)


def existing_badges():
    """Every badge already on the universe: {name: id} (public list, paginated)."""
    found, cursor = {}, None
    while True:
        url = LIST_URL.format(UNIVERSE_ID) + (f"&cursor={cursor}" if cursor else "")
        status, body = call(url)
        if status != 200:
            raise SystemExit(f"listing the universe's badges failed: HTTP {status} {body}")
        for badge in body.get("data") or []:
            found[badge.get("name")] = badge.get("id")
        cursor = body.get("nextPageCursor")
        if not cursor:
            return found


def adopt_existing(rows, manifest, existing, price):
    """Rows already on the universe by name but not in the manifest (a create whose answer was
    lost) go into the manifest with their ids. Their cost is unknown, so the price is counted
    against --max-spend. Returns the adopted keys."""
    adopted = []
    for row in rows:
        if row["key"] not in manifest and row["name"] in existing:
            manifest[row["key"]] = {"id": existing[row["name"]], "cost": price, "name": row["name"],
                                    "foundByName": True, "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
            adopted.append(row["key"])
    return adopted


def to_create(rows, manifest, existing):
    """Rows still to create: BadgeId 0, with a Rule, not in the manifest, no badge of that name."""
    out = []
    for row in rows:
        if row["badgeId"] or row["key"] in manifest or row["name"] in existing:
            continue
        out.append(row)
    return out


def next_cost(quota, price, total, max_spend):
    """(cost, refusal or None) for the next badge: free while quota lasts, else the price."""
    cost = 0 if quota > 0 else price
    if cost > MAX_COST_EACH:
        return cost, f"cost {cost} is above {MAX_COST_EACH}"
    if total + cost > max_spend:
        return cost, f"total {total + cost} would pass --max-spend {max_spend}"
    return cost, None


def read_quota_price():
    status, quota = call(QUOTA_URL.format(UNIVERSE_ID))
    if status != 200 or not isinstance(quota, int):
        raise SystemExit(f"free quota read failed: HTTP {status} {quota}")
    status, meta = call(METADATA_URL)
    if status != 200 or "badgeCreationPrice" not in meta:
        raise SystemExit(f"metadata read failed: HTTP {status} {meta}")
    return quota, int(meta["badgeCreationPrice"])


def select(rows, only):
    if not only:
        return rows
    wanted = set(only)
    return [r for r in rows if r["key"] in wanted]


def plan(args):
    rows = select(export_rows(), args.only)
    manifest = load_manifest()
    existing = existing_badges()
    quota, price = read_quota_price()
    todo = to_create(rows, manifest, existing)
    print(f"free quota today {quota}, price {price}, {len(existing)} badges on the universe, "
          f"{len(manifest)} in the manifest, {len(todo)} to create")
    total = 0
    for i, row in enumerate(todo[: args.limit or None]):
        cost, refusal = next_cost(quota - i if quota - i > 0 else 0, price, total, args.max_spend)
        icon = os.path.join(ROOT, row["icon"])
        flags = [] if os.path.exists(icon) else ["NO ICON"]
        if not row["hasRule"]:
            flags.append("no Rule yet")
        if refusal:
            print(f"  STOP at {row['key']}: {refusal}")
            break
        total += cost
        print(f"  {row['key']:<16} {row['name']:<28} cost {cost:>3}  total {total:>5}  {' '.join(flags)}")
    return 0


def create(args):
    api_key = read_api_key()
    if not api_key:
        print(f"no key in the Keychain under {KEY_SERVICE}")
        return 2
    rows = select(export_rows(), args.only)
    manifest = load_manifest()
    existing = existing_badges()
    adopted = adopt_existing(rows, manifest, existing, read_quota_price()[1])
    if adopted:
        save_manifest(manifest)
        print(f"on the universe but not in the manifest, recorded by name: {', '.join(adopted)}")
    todo = to_create(rows, manifest, existing)[: args.limit or None]
    total = sum(int(e.get("cost") or 0) for e in manifest.values())
    print(f"{len(todo)} to create; {total} R$ already spent by the manifest")
    for row in todo:
        icon = os.path.join(ROOT, row["icon"])
        if not os.path.exists(icon):
            print(f"{row['key']}: no icon at {row['icon']}: stopped")
            return 1
        quota, price = read_quota_price()
        cost, refusal = next_cost(quota, price, total, args.max_spend)
        if refusal:
            print(f"{row['key']}: refused: {refusal}")
            return 1
        fields = {"name": row["name"], "description": row["description"],
                  "paymentSourceType": PAYMENT_GROUP, "expectedCost": cost, "isActive": "true"}
        for attempt in range(3):
            body, ctype = multipart(fields, icon)
            status, reply = call(CREATE_URL.format(UNIVERSE_ID), api_key, body, ctype, "POST")
            if status != 429:
                break
            print("  429: waiting 60 s")
            time.sleep(60)
        if status == NETWORK:
            print(f"{row['key']}: no answer from Roblox ({reply.get('network')}): it may have been "
                  "created and charged. Stopped: check the universe's badges before re-running "
                  "(a re-run records a badge it finds by name instead of paying again)")
            return 1
        codes = error_codes(reply)
        if status == 200 and reply.get("id"):
            manifest[row["key"]] = {"id": reply["id"], "iconImageId": reply.get("iconImageId"),
                                    "cost": cost, "name": row["name"],
                                    "time": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
            save_manifest(manifest)
            total += cost
            print(f"  {row['key']:<16} id {reply['id']}  cost {cost}  total {total}")
        elif 18 in codes:
            print(f"{row['key']}: error 18, the cost changed (sent {cost}); quota {read_quota_price()}: stopped")
            return 1
        elif 17 in codes or 16 in codes:
            print(f"{row['key']}: HTTP {status} codes {codes} (funds or payment source): stopped, ask")
            return 1
        elif 6 in codes:
            print(f"{row['key']}: text moderated (code 6): skipped; pick a new name")
            continue
        elif status == 401 or (status == 403 and any(c in (0, 12) for c in codes)):
            print("SCOPE MISSING: " + SCOPE_MESSAGE)
            return 1
        else:
            print(f"{row['key']}: HTTP {status} codes {codes}: stopped")
            return 1
        time.sleep(1)  # Roblox allows 100 a minute
    print(f"done: {total} R$ spent in all (manifest)")
    return 0


def sync_plan(rows, manifest, live, icons, icon_version=ICON_VERSION):
    """What --sync would send: [(key, id, kind, payload)] with kind "text", "disable" or "icon".

    `live` maps a badge id to Roblox's {name, description, enabled}; a row already matching is
    skipped, and so is an icon the manifest says is at `icon_version`."""
    out = []
    keys = set()
    for row in rows:
        keys.add(row["key"])
        entry = manifest.get(row["key"])
        if not entry:
            continue
        now = live.get(entry["id"], {})
        if now.get("name") != row["name"] or now.get("description") != row["description"]:
            out.append((row["key"], entry["id"], "text", {"name": row["name"], "description": row["description"]}))
        if icons and entry.get("iconVersion") != icon_version:
            out.append((row["key"], entry["id"], "icon", row["icon"]))
    for key, entry in sorted(manifest.items()):
        if key not in keys and live.get(entry["id"], {}).get("enabled", True):
            out.append((key, entry["id"], "disable", {"enabled": False}))
    return out


def sync(args):
    rows = export_rows()  # all of them: a row left out would read as retired and be disabled
    manifest = load_manifest()
    live = {}
    for entry in manifest.values():
        status, info = call(INFO_URL.format(entry["id"]))
        if status != 200:
            raise SystemExit(f"reading badge {entry['id']} failed: HTTP {status} {info}")
        live[entry["id"]] = info
    todo = sync_plan(rows, manifest, live, args.icons)
    if args.only:
        todo = [t for t in todo if t[0] in set(args.only)]
    for key, badge_id, kind, payload in todo:
        if kind == "text":
            now = live[badge_id]
            print(f"  {key:<16} text  {now.get('name')!r} -> {payload['name']!r}"
                  + ("" if now.get("description") == payload["description"]
                     else f"; description -> {payload['description']!r}"))
        elif kind == "disable":
            print(f"  {key:<16} disable ({live[badge_id].get('name')!r}, not in Config any more)")
        else:
            print(f"  {key:<16} icon  {payload}")
    if not args.apply:
        print(f"dry run: {len(todo)} changes; nothing sent (add --apply)")
        return 0
    api_key = read_api_key()
    if not api_key:
        print(f"no key in the Keychain under {KEY_SERVICE}")
        return 2
    for key, badge_id, kind, payload in todo:
        for attempt in range(3):
            if kind == "icon":
                body, ctype = multipart({}, os.path.join(ROOT, payload))
                status, reply = call(ICON_URL.format(badge_id), api_key, body, ctype, "POST")
            else:
                status, reply = call(UPDATE_URL.format(badge_id), api_key, json.dumps(payload).encode(),
                                     "application/json", "PATCH")
            if status != 429:
                break
            print("  429: waiting 60 s")
            time.sleep(60)
        if status == 200:
            if kind == "icon":
                manifest[key]["iconVersion"] = ICON_VERSION
                if isinstance(reply, dict) and reply.get("targetId"):
                    manifest[key]["iconImageId"] = reply["targetId"]
            elif kind == "text":
                manifest[key]["name"] = payload["name"]
            else:
                manifest[key]["disabled"] = True
            save_manifest(manifest)
            print(f"  {key:<16} {kind} OK")
        elif status == 401 or (status == 403 and any(c in (0, 12) for c in error_codes(reply))):
            print(f"{key}: HTTP {status} {reply}: the key lacks the scope for this call; stopped")
            return 1
        else:
            print(f"{key}: {kind} HTTP {status} {reply}: stopped")
            return 1
        time.sleep(0.7)  # well under Roblox's limit
    print(f"done: {len(todo)} changes sent")
    return 0


def write_back(manifest, config_text):
    """Config text with each manifest id over its row's `BadgeId = 0`; exactly one match a key."""
    for key, entry in sorted(manifest.items()):
        # StyLua may split a long row over lines once it has an id: allow any space between.
        pattern = re.compile(r'(Key = "' + re.escape(key) + r'",\s*BadgeId = )0\b')
        already = re.search(r'Key = "' + re.escape(key) + r'",\s*BadgeId = ' + str(entry["id"]) + r'\b', config_text)
        matches = pattern.findall(config_text)
        if already and not matches:
            continue
        if len(matches) != 1:
            raise SystemExit(f"{key}: {len(matches)} rows match `Key = \"{key}\", BadgeId = 0` (need 1)")
        config_text = pattern.sub(lambda m: m.group(1) + str(int(entry["id"])), config_text)
    return config_text


def write_config():
    manifest = load_manifest()
    with open(CONFIG) as handle:
        text = handle.read()
    new = write_back(manifest, text)
    if new == text:
        print("Config already has every manifest id")
        return 0
    with open(CONFIG, "w") as handle:
        handle.write(new)
    subprocess.run(["stylua", CONFIG], cwd=ROOT, check=True)
    print(f"wrote {len(manifest)} ids into src/shared/Config.luau")
    return 0


def self_test():
    # sync: a changed name is sent, a matching one is not, a retired key is disabled once,
    # an icon already at this version is skipped
    rows = [{"key": "A", "name": "New", "description": "d", "icon": "a.png"},
            {"key": "B", "name": "Same", "description": "d", "icon": "b.png"}]
    manifest = {"A": {"id": 1}, "B": {"id": 2, "iconVersion": ICON_VERSION}, "Gone": {"id": 3}}
    live = {1: {"name": "Old", "description": "d", "enabled": True},
            2: {"name": "Same", "description": "d", "enabled": True},
            3: {"name": "Gone", "description": "d", "enabled": True}}
    got = sync_plan(rows, manifest, live, icons=True)
    assert [(k, kind) for k, _, kind, _ in got] == [("A", "text"), ("A", "icon"), ("Gone", "disable")], got
    live[3]["enabled"] = False
    assert [k for k, _, kind, _ in sync_plan(rows, manifest, live, icons=False)] == ["A"]
    # cost guard
    assert next_cost(5, 100, 0, 4700) == (0, None)
    assert next_cost(0, 100, 4600, 4700) == (100, None)
    assert next_cost(0, 100, 4650, 4700)[1] is not None, "running total guard"
    assert next_cost(0, 150, 0, 4700)[1] is not None, "price guard"
    # duplicate skip: manifest key, existing name, an id already in Config
    rows = [{"key": "A", "name": "Alpha", "badgeId": 0}, {"key": "B", "name": "Beta", "badgeId": 0},
            {"key": "C", "name": "Gamma", "badgeId": 0}, {"key": "D", "name": "Delta", "badgeId": 7}]
    left = to_create(rows, {"A": {"id": 1}}, {"Beta": 2})
    assert [r["key"] for r in left] == ["C"], left
    # a create whose answer was lost: found by name, recorded with its id, counted as paid
    manifest = {"A": {"id": 1, "cost": 0}}
    assert adopt_existing(rows, manifest, {"Beta": 2, "Alpha": 1}, 100) == ["B"]
    assert manifest["B"]["id"] == 2 and manifest["B"]["cost"] == 100 and manifest["B"]["foundByName"]
    assert adopt_existing(rows, manifest, {"Beta": 2}, 100) == [], "a second run adopts nothing"
    # a network error is an answer, not an exception (a timeout on a create stops the run)
    status, body = call("http://127.0.0.1:9/")
    assert status == NETWORK and "network" in body, (status, body)
    # manifest save is atomic and round-trips
    tmp = tempfile.mkdtemp()
    try:
        path = os.path.join(tmp, "m.json")
        save_manifest({"A": {"id": 11, "cost": 0}}, path)
        assert load_manifest(path) == {"A": {"id": 11, "cost": 0}}
        # write-back on a copy of the real Config
        copy = os.path.join(tmp, "Config.luau")
        shutil.copy(CONFIG, copy)
        with open(copy) as handle:
            text = handle.read()
        # The copy's first row made inert again (Config's rows all have ids once created).
        first_key = re.search(r'Key = "(\w+)",\s*BadgeId = \d+', text).group(1)
        text = re.sub(r'(Key = "' + first_key + r'",\s*BadgeId = )\d+', r"\g<1>0", text, count=1)
        new = write_back({first_key: {"id": 123456789}}, text)
        assert f'Key = "{first_key}", BadgeId = 123456789' in new
        assert new.count("BadgeId = 123456789") == 1
        assert write_back({first_key: {"id": 123456789}}, new) == new, "a second run changes nothing"
        split = new.replace(f'Key = "{first_key}", BadgeId', f'Key = "{first_key}",\n\t\t\tBadgeId')
        assert write_back({first_key: {"id": 123456789}}, split) == split, "a row split over lines"
        try:
            write_back({"NoSuchKey": {"id": 5}}, text)
            raise AssertionError("an unknown key must refuse")
        except SystemExit:
            pass

    finally:
        shutil.rmtree(tmp)
    print("self-test OK")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--probe", action="store_true", help="quota, price and an invalid create")
    parser.add_argument("--create", action="store_true", help="create the badges (spends Robux past the free quota)")
    parser.add_argument("--only", nargs="*", help="only these keys")
    parser.add_argument("--limit", type=int, default=0, help="create at most this many")
    parser.add_argument("--max-spend", type=int, default=DEFAULT_MAX_SPEND, help="Robux cap for the run, manifest included")
    parser.add_argument("--write-config", action="store_true", help="write manifest ids into Config")
    parser.add_argument("--self-test", action="store_true", help="offline checks")
    parser.add_argument("--sync", action="store_true", help="text (and --icons) onto the made badges; retired ones disabled")
    parser.add_argument("--icons", action="store_true", help="with --sync: upload the icons too")
    parser.add_argument("--apply", action="store_true", help="with --sync: send (else a dry run)")
    args = parser.parse_args()
    if args.probe:
        return probe()
    if args.self_test:
        return self_test()
    if args.write_config:
        return write_config()
    if args.create:
        return create(args)
    if args.sync:
        return sync(args)
    return plan(args)


if __name__ == "__main__":
    sys.exit(main())
