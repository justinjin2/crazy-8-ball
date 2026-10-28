"""Print the scopes of each Roblox API key in the macOS Keychain, never the key itself.

    python3 tools/halloween/key_scopes.py [SERVICE ...]   (default: ROBLOX_API_KEY ROBLOX_USER_KEY)

Calls Roblox's own POST https://apis.roblox.com/api-keys/v1/introspect and lists the key's
name, owner, enabled/expired and every scope with its operations and targets, then says which
of the Halloween build's scopes are still missing on that key.

Two keys (2026-10-28): ROBLOX_API_KEY is the group key (uploads, products, passes, the icon);
ROBLOX_USER_KEY is Painicane's user key (badges, the title, the Experience Event, thumbnails),
because Creator Hub offers the legacy badge scopes only on user keys.
"""

import json
import subprocess
import sys
import urllib.error
import urllib.request

# service -> (scope name -> operations the Halloween build calls), see HW_COORDINATOR §2.5 and HW_SYS
NEEDED = {
    "ROBLOX_API_KEY": {
        "asset": {"read", "write"},  # uploads, the icon test
        "developer-product": {"read", "write"},  # Candy packs
    },
    "ROBLOX_USER_KEY": {
        "legacy-universe.badge": {"manage-and-spend-robux"},  # create the 52 badges
        "universe.event": {"read", "write"},  # the Experience Event
    },
}
OPTIONAL = {
    "ROBLOX_API_KEY": {"game-pass": {"read", "write"}},
    "ROBLOX_USER_KEY": {
        "universe.place": {"write"},  # the title countdown (PATCH cloud/v2 .../places/{id}); else by hand
        "legacy-badge": {"manage"},  # change a badge icon later
        "universe.thumbnail": {"read", "write"},  # the Halloween thumbnail
    },
}


def read_key(service):
    out = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ""


def introspect(key):
    req = urllib.request.Request(
        "https://apis.roblox.com/api-keys/v1/introspect",
        data=json.dumps({"apiKey": key}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def missing(scopes, wanted):
    have = {}
    for s in scopes:
        have.setdefault(s.get("name"), set()).update(s.get("operations", []))
    return [f"{n}:{op}" for n, ops in wanted.items() for op in sorted(ops) if op not in have.get(n, set())]


def main():
    for service in sys.argv[1:] or list(NEEDED):
        key = read_key(service)
        if not key:
            print(f"{service}: not in the Keychain")
            continue
        try:
            info = introspect(key)
        except urllib.error.HTTPError as e:
            print(f"{service}: HTTP {e.code} {e.read()[:200].decode(errors='replace')}")
            continue
        info.pop("apiKey", None)
        print(f"{service} (length {len(key)}): {info.get('name')!r}, user {info.get('authorizedUserId')}, "
              f"enabled {info.get('enabled')}, expired {info.get('expired')}")
        scopes = info.get("scopes", [])
        for s in scopes:
            targets = s.get("universeIds") or s.get("groupIds") or ["all"]
            print(f"  {s.get('name')}: {', '.join(s.get('operations', []))}  (targets {', '.join(targets)})")
        need, extra = missing(scopes, NEEDED.get(service, {})), missing(scopes, OPTIONAL.get(service, {}))
        print("  needed for Halloween: " + ("all there" if not need else "MISSING " + ", ".join(need)))
        print("  optional: " + ("all there" if not extra else "missing " + ", ".join(extra)))


if __name__ == "__main__":
    main()
