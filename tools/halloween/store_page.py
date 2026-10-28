"""The Halloween 2026 store page: icons, the countdown, the Experience Event and the title.

    python3 tools/halloween/store_page.py status
    python3 tools/halloween/store_page.py icon-upload [--go]       the 7 icons + a copy of today's icon
    python3 tools/halloween/store_page.py icon-check               moderation of every uploaded icon
    python3 tools/halloween/store_page.py icon-set NAME|ID [--go]  set the game icon (APPROVED only)
    python3 tools/halloween/store_page.py icon-schedule [--go]     the 5H..LIVE swaps (run under caffeinate)
    python3 tools/halloween/store_page.py event [--go]             create "Haunted Rooftop", then read it back
    python3 tools/halloween/store_page.py event-get                list the game's events
    python3 tools/halloween/store_page.py title TEXT [--go]        rename (needs universe.place:write)
    python3 tools/halloween/store_page.py selftest

Every call that changes something is a dry run (the request is printed without the key) unless
--go is given; real calls are logged to STORE/log.txt. Keys come from the macOS Keychain and are
never printed: ROBLOX_API_KEY (group key: asset read/write on group 675425213) for the icon calls,
ROBLOX_USER_KEY (Painicane's user key) for the event and the title. The icon route
(PATCH /assets/v1/assets/{rootPlace}?updateMask=icon) is unofficial (research-boosts-hype.md B2):
test it with the identical copy first, and never set an image that is not APPROVED, because a
pending icon shows a blank placeholder on the game page.
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://apis.roblox.com"
UNIVERSE = 10767330648
ROOT_PLACE = 107430170196919
GROUP = 675425213
STORE = Path.home() / "Desktop/8ball-refs/halloween/shots/coordinator/store"
ICONS = STORE / "icons"
STATE = STORE / "icons.json"
LOG = STORE / "log.txt"
ORIGINAL_ICON = 123614794049673  # recorded 2026-10-28 08:58 EDT (store/original.json)

# (unix time, icon name): from this moment on the game shows that icon (HW_COORDINATOR §2.5)
SCHEDULE = [
    (1793210400, "5H"),  # 14:00 EDT
    (1793214000, "4H"),
    (1793217600, "3H"),
    (1793221200, "2H"),
    (1793224800, "1H"),
    (1793228400, "LIVE"),  # 19:00 EDT, the event goes live
]
UPLOADS = ["5H", "4H", "3H", "2H", "1H", "LIVE", "plain", "current"]

EVENT = {
    "title": "Haunted Rooftop",
    "subtitle": "5 Halloween cues · Pumpkin King · Candy",
    "description": (
        "The rooftop turns haunted for 6 days! Play matches to collect Candy, finish the daily quests "
        "and unlock 5 Halloween cues that never come back. Challenge the Pumpkin King on his throne. "
        "Candy Rush: 2x Candy the first 10 minutes of every hour. Ends Nov 3."
    ),
    "startTime": "2026-10-28T23:00:00.000Z",  # 19:00 EDT, 1793228400
    "endTime": "2026-11-04T00:00:00.000Z",  # 19:00 EST Nov 3, 1793750400
    "visibility": "public",
    "groupId": GROUP,
    "placeId": ROOT_PLACE,
    "categories": [{"category": "festival", "rank": 1}],
}


def key(service):
    out = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    value = out.stdout.strip()
    if out.returncode or not value:
        sys.exit(f"store_page: no {service} in the Keychain")
    return value


def log(line):
    STORE.mkdir(parents=True, exist_ok=True)
    with LOG.open("a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + line + "\n")


def call(method, path, service, body=None, content_type=None, retries=3):
    """One Open Cloud call; returns (status, parsed json or text)."""
    headers = {"x-api-key": key(service)}
    if content_type:
        headers["Content-Type"] = content_type
    for attempt in range(retries):
        req = urllib.request.Request(API + path, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                text = r.read().decode()
                return r.status, (json.loads(text) if text.strip() else {})
        except urllib.error.HTTPError as e:
            text = e.read().decode(errors="replace")
            if (e.code == 429 or e.code >= 500) and attempt < retries - 1:
                time.sleep(2 ** attempt * 2)
                continue
            try:
                return e.code, json.loads(text)
            except ValueError:
                return e.code, text[:400]
        except urllib.error.URLError as e:
            if attempt < retries - 1:
                time.sleep(2 ** attempt * 2)
                continue
            return 0, str(e)
    return 0, "unreachable"


def multipart(fields, file_field=None, file_name=None, file_bytes=None, file_type="image/png"):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    if file_field:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{file_name}"\r\n'
            f"Content-Type: {file_type}\r\n\r\n".encode() + file_bytes + b"\r\n"
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(state):
    STATE.write_text(json.dumps(state, indent=2, sort_keys=True))


def asset_id_from(result):
    value = str((result or {}).get("assetId") or "")
    if not value and str((result or {}).get("path", "")).startswith("assets/"):
        value = result["path"].split("/", 1)[1]
    return value if value.isdigit() else None


def live_icon():
    status, data = call("GET", f"/assets/v1/assets/{ROOT_PLACE}?readMask=icon", "ROBLOX_API_KEY")
    icon = data.get("icon", "") if status == 200 else ""
    return icon.split("/", 1)[1] if icon.startswith("assets/") else None


def icon_thumb():
    url = f"https://thumbnails.roblox.com/v1/games/icons?universeIds={UNIVERSE}&size=512x512&format=Png&isCircular=false"
    with urllib.request.urlopen(url, timeout=20) as r:
        data = json.load(r)["data"][0]
    return data.get("state"), data.get("version"), data.get("imageUrl")


def cmd_status():
    status, place = call("GET", f"/cloud/v2/universes/{UNIVERSE}/places/{ROOT_PLACE}", "ROBLOX_USER_KEY")
    print("title:", place.get("displayName") if status == 200 else (status, place))
    print("live icon asset:", live_icon(), "(original", ORIGINAL_ICON, ")")
    print("icon thumbnail:", icon_thumb()[:2])
    for name, entry in sorted(load_state().items()):
        print(f"  {name:8} {entry.get('asset_id', '-'):>16} {entry.get('status')}")


def cmd_icon_upload(go):
    state = load_state()
    for name in UPLOADS:
        if state.get(name, {}).get("asset_id") or state.get(name, {}).get("operation"):
            print(f"{name}: already uploaded ({state[name].get('asset_id') or state[name].get('operation')})")
            continue
        path = ICONS / f"{name}.png"
        if not path.exists():
            print(f"{name}: {path} missing, skipped")
            continue
        request = {
            "assetType": "Image",
            "displayName": f"Crazy 8 Ball Halloween icon {name}",
            "description": "Halloween 2026 game icon",
            "creationContext": {"creator": {"groupId": str(GROUP)}},
        }
        if not go:
            print(f"DRY {name}: POST /assets/v1/assets {json.dumps(request)} file={path.name} ({path.stat().st_size} bytes)")
            continue
        body, ctype = multipart({"request": json.dumps(request)}, "fileContent", f"{name}.png", path.read_bytes())
        status, result = call("POST", "/assets/v1/assets", "ROBLOX_API_KEY", body, ctype)
        log(f"icon-upload {name} -> {status} {json.dumps(result)[:300]}")
        if status != 200:
            print(f"{name}: upload failed {status} {result}")
            continue
        found = asset_id_from(result.get("response")) if result.get("done") else None
        state[name] = {"asset_id": found, "status": "moderating"} if found else {"operation": result.get("path"), "status": "uploading"}
        print(f"{name}: {state[name]}")
        save_state(state)
        time.sleep(1)
    save_state(state)


def cmd_icon_check():
    state = load_state()
    for name, entry in sorted(state.items()):
        if entry.get("status") == "uploading" and entry.get("operation"):
            status, result = call("GET", f"/assets/v1/{entry['operation']}", "ROBLOX_API_KEY")
            if status == 200 and result.get("done"):
                found = asset_id_from(result.get("response"))
                if found:
                    entry.update(asset_id=found, status="moderating")
                    entry.pop("operation", None)
        if entry.get("asset_id") and entry.get("status") in ("moderating", "uploading", None):
            status, result = call(
                "GET", f"/assets/v1/assets/{entry['asset_id']}?readMask=moderationResult,assetType,state", "ROBLOX_API_KEY"
            )
            verdict = str(((result or {}).get("moderationResult") or {}).get("moderationState", "")).upper()
            if verdict.endswith("APPROVED"):
                entry["status"] = "approved"
            elif verdict.endswith("REJECTED"):
                entry["status"] = "rejected"
        print(f"  {name:8} {entry.get('asset_id', '-'):>16} {entry.get('status')}")
    save_state(state)
    print("live icon asset:", live_icon(), "| thumbnail:", icon_thumb()[:2])


def resolve(name_or_id, state):
    """The asset id to set, only if it is safe: an APPROVED upload or the recorded original."""
    if str(name_or_id) == str(ORIGINAL_ICON) or name_or_id == "original":
        return str(ORIGINAL_ICON)
    entry = state.get(name_or_id)
    if entry is None:
        entry = next((e for e in state.values() if e.get("asset_id") == str(name_or_id)), None)
    if not entry or entry.get("status") != "approved" or not entry.get("asset_id"):
        return None
    return entry["asset_id"]


def set_icon(asset_id, go):
    fields = {"request": json.dumps({"assetId": str(ROOT_PLACE), "icon": f"assets/{asset_id}"})}
    if not go:
        print(f"DRY PATCH /assets/v1/assets/{ROOT_PLACE}?updateMask=icon {fields['request']}")
        return True
    body, ctype = multipart(fields)
    status, result = call("PATCH", f"/assets/v1/assets/{ROOT_PLACE}?updateMask=icon", "ROBLOX_API_KEY", body, ctype)
    log(f"icon-set {asset_id} -> {status} {json.dumps(result)[:300]}")
    if status != 200:
        print("icon-set failed:", status, result)
        return False
    for _ in range(12):
        if live_icon() == str(asset_id):
            log(f"icon-set {asset_id} confirmed by GET")
            print("set and confirmed:", asset_id, "| thumbnail:", icon_thumb()[:2])
            return True
        time.sleep(5)
    log(f"icon-set {asset_id} NOT confirmed by GET")
    print("Roblox accepted it but the GET still shows", live_icon())
    return False


def cmd_icon_set(name_or_id, go):
    asset_id = resolve(name_or_id, load_state())
    if not asset_id:
        sys.exit(f"refused: {name_or_id} is not an APPROVED upload or the original icon")
    set_icon(asset_id, go)


def stage_for(now):
    """The icon name the game should show at unix time `now` (None = leave today's icon)."""
    current = None
    for at, name in SCHEDULE:
        if now >= at:
            current = name
    return current


def cmd_icon_schedule(go):
    state = load_state()
    missing = [n for _, n in SCHEDULE if not resolve(n, state)]
    if missing:
        sys.exit(f"refused: not APPROVED yet: {', '.join(missing)}")
    last_good = live_icon()
    applied = None
    log(f"icon-schedule start (go={go}) live={last_good}")
    while True:
        now = time.time()
        want = stage_for(now)
        if want and want != applied:
            asset_id = resolve(want, state)
            ok = set_icon(asset_id, go)
            if go:
                time.sleep(20)
                st, version, _ = icon_thumb()
                if not ok or live_icon() != asset_id or st != "Completed":
                    log(f"icon-schedule {want}: doubt (ok={ok} state={st}); back to {last_good} and stop")
                    if last_good:
                        set_icon(last_good, go)
                    sys.exit(f"stopped at {want}")
                log(f"icon-schedule {want} live ({asset_id}, thumbnail {st} {version})")
            last_good, applied = asset_id, want
            if want == SCHEDULE[-1][1]:
                log("icon-schedule done (LIVE)")
                return
        nxt = min((at for at, _ in SCHEDULE if at > now), default=now + 30)
        time.sleep(max(5, min(60, nxt - now)))


def cmd_event(go):
    body = json.dumps(EVENT).encode()
    if not go:
        print("DRY POST /virtual-events/v3/universes/%d/game-events %s" % (UNIVERSE, json.dumps(EVENT, ensure_ascii=False)))
        return
    status, result = call("POST", f"/virtual-events/v3/universes/{UNIVERSE}/game-events", "ROBLOX_USER_KEY", body, "application/json")
    log(f"event create -> {status} {json.dumps(result)[:500]}")
    print(status, json.dumps(result, indent=1, ensure_ascii=False)[:1500])
    cmd_event_get()


def cmd_event_get():
    status, result = call("GET", f"/virtual-events/v3/universes/{UNIVERSE}/game-events", "ROBLOX_USER_KEY")
    print(status, json.dumps(result, indent=1, ensure_ascii=False)[:3000])


def cmd_title(text, go):
    body = json.dumps({"displayName": text}).encode()
    path = f"/cloud/v2/universes/{UNIVERSE}/places/{ROOT_PLACE}?updateMask=displayName"
    if not go:
        print("DRY PATCH", path, body.decode())
        return
    status, result = call("PATCH", path, "ROBLOX_USER_KEY", body, "application/json")
    log(f"title {text!r} -> {status} {json.dumps(result)[:300]}")
    print(status, result if status != 200 else result.get("displayName"))


def cmd_selftest():
    hour = 3600
    assert stage_for(SCHEDULE[0][0] - 1) is None, "before 14:00 the icon must stay today's"
    for i, (at, name) in enumerate(SCHEDULE):
        assert stage_for(at) == name and stage_for(at + hour - 1) == (name if i == len(SCHEDULE) - 1 else name), name
        if i + 1 < len(SCHEDULE):
            assert stage_for(SCHEDULE[i + 1][0] - 1) == name, name
    assert stage_for(1793750400) == "LIVE"
    assert [n for _, n in SCHEDULE] == ["5H", "4H", "3H", "2H", "1H", "LIVE"]
    assert all(b - a == hour for (a, _), (b, _) in zip(SCHEDULE, SCHEDULE[1:])), "one swap an hour"
    assert SCHEDULE[-1][0] == 1793228400, "LIVE at the go-live time"
    fake = {"5H": {"asset_id": "11", "status": "approved"}, "4H": {"asset_id": "12", "status": "moderating"},
            "3H": {"asset_id": "13", "status": "rejected"}, "2H": {"operation": "operations/x", "status": "uploading"}}
    assert resolve("5H", fake) == "11"
    assert resolve("11", fake) == "11"
    assert resolve("4H", fake) is None and resolve("12", fake) is None, "never a pending id"
    assert resolve("3H", fake) is None and resolve("2H", fake) is None and resolve("1H", fake) is None
    assert resolve("original", fake) == str(ORIGINAL_ICON)
    for name in UPLOADS:
        if name != "current":
            assert (ICONS / f"{name}.png").exists(), f"{name}.png missing"
    print("store_page selftest: OK (schedule, approved-only, icons present)")


def main():
    args = [a for a in sys.argv[1:] if a != "--go"]
    go = "--go" in sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    cmd = args[0]
    if cmd == "status":
        cmd_status()
    elif cmd == "icon-upload":
        cmd_icon_upload(go)
    elif cmd == "icon-check":
        cmd_icon_check()
    elif cmd == "icon-set" and len(args) == 2:
        cmd_icon_set(args[1], go)
    elif cmd == "icon-schedule":
        cmd_icon_schedule(go)
    elif cmd == "event":
        cmd_event(go)
    elif cmd == "event-get":
        cmd_event_get()
    elif cmd == "title" and len(args) == 2:
        cmd_title(args[1], go)
    elif cmd == "selftest":
        cmd_selftest()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    os.umask(0o022)
    main()
