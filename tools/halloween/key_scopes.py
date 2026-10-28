"""Print the scopes of each Roblox API key in the macOS Keychain, never the key itself.

    python3 tools/halloween/key_scopes.py [SERVICE ...]   (default: ROBLOX_API_KEY)

Calls Roblox's own POST https://apis.roblox.com/api-keys/v1/introspect and lists the key's
name, owner, enabled/expired and every scope with its operations and targets, then says which
of the Halloween build's scopes are still missing.
"""

import json
import subprocess
import sys
import urllib.error
import urllib.request

# scope name -> operations the Halloween build calls (docs/prompts/HW_COORDINATOR_PROMPT.md, HW_SYS)
NEEDED = {
    "asset": {"read", "write"},  # uploads, the icon test
    "developer-product": {"read", "write"},  # Candy packs
    "legacy-universe.badge": {"manage-and-spend-robux"},  # create the 52 badges
    "universe.place": {"write"},  # the title countdown (PATCH cloud/v2 .../places/{id})
    "universe.event": {"read", "write"},  # the Experience Event
}
OPTIONAL = {
    "legacy-badge": {"manage"},  # change a badge icon later
    "universe.thumbnail": {"read", "write"},  # the Halloween thumbnail
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
    for service in sys.argv[1:] or ["ROBLOX_API_KEY"]:
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
        need, extra = missing(scopes, NEEDED), missing(scopes, OPTIONAL)
        print("  needed for Halloween: " + ("all there" if not need else "MISSING " + ", ".join(need)))
        print("  optional: " + ("all there" if not extra else "missing " + ", ".join(extra)))


if __name__ == "__main__":
    main()
