#!/usr/bin/env python3
"""Builds the Crazy 8 Ball Discord server (plan: 8ball-refs/discord/01-discord-server-plan.md).

The bot token is read from the macOS Keychain (service DISCORD_BOT_TOKEN) and never printed.
The bot must be in exactly one server, with Administrator (needed to turn on Community).

    python3 tools/discord_setup.py              # inspect only: prints the server as it is
    python3 tools/discord_setup.py --apply      # build it (safe to run again: skips what exists,
                                                # but resets roles and channel permissions to these)
    python3 tools/discord_setup.py --apply --remove-template   # also delete Discord's starter channels

Stdlib only (no requests), so it runs on a fresh Mac.
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://discord.com/api/v10"
LOGO = os.path.expanduser("~/Desktop/8ball-refs/group-logo/Lucky8_group_logo.png")

# Permission bits (discord.com/developers/docs/topics/permissions).
P = {
    "CREATE_INSTANT_INVITE": 1 << 0,
    "KICK_MEMBERS": 1 << 1,
    "BAN_MEMBERS": 1 << 2,
    "ADMINISTRATOR": 1 << 3,
    "MANAGE_CHANNELS": 1 << 4,
    "ADD_REACTIONS": 1 << 6,
    "VIEW_AUDIT_LOG": 1 << 7,
    "VIEW_CHANNEL": 1 << 10,
    "SEND_MESSAGES": 1 << 11,
    "MANAGE_MESSAGES": 1 << 13,
    "EMBED_LINKS": 1 << 14,
    "ATTACH_FILES": 1 << 15,
    "READ_MESSAGE_HISTORY": 1 << 16,
    "USE_EXTERNAL_EMOJIS": 1 << 18,
    "MANAGE_NICKNAMES": 1 << 27,
    "USE_APPLICATION_COMMANDS": 1 << 31,
    "MANAGE_EVENTS": 1 << 33,
    "MANAGE_THREADS": 1 << 34,
    "CREATE_PUBLIC_THREADS": 1 << 35,
    "SEND_MESSAGES_IN_THREADS": 1 << 38,
    "MODERATE_MEMBERS": 1 << 40,
}


def bits(*names):
    total = 0
    for name in names:
        total |= P[name]
    return str(total)


# Everyone can read, react, chat in the open channels, invite friends and use bot commands
# (Bloxlink's /verify). No links, files, @everyone, threads or external apps by default.
EVERYONE = bits(
    "VIEW_CHANNEL",
    "READ_MESSAGE_HISTORY",
    "ADD_REACTIONS",
    "SEND_MESSAGES",
    "SEND_MESSAGES_IN_THREADS",
    "USE_APPLICATION_COMMANDS",
    "USE_EXTERNAL_EMOJIS",
    "CREATE_INSTANT_INVITE",
)
# Discord's guide: mods moderate, but get no channel, server, role or webhook control.
MOD = bits(
    "KICK_MEMBERS",
    "BAN_MEMBERS",
    "MODERATE_MEMBERS",
    "MANAGE_MESSAGES",
    "MANAGE_THREADS",
    "MANAGE_NICKNAMES",
    "VIEW_AUDIT_LOG",
    "EMBED_LINKS",
    "ATTACH_FILES",
)
DEV = str(int(MOD) | P["MANAGE_CHANNELS"] | P["MANAGE_EVENTS"])

ROLES = [
    # name, permissions, color, hoist (listed apart in the member list)
    ("Developer", DEV, 0xF5B800, True),
    ("Moderator", MOD, 0x3BA55C, True),
    ("Verified", "0", 0x5865F2, False),
    ("Update Pings", "0", 0, False),
    ("Code Pings", "0", 0, False),
    ("PC", "0", 0, False),
    ("Mobile", "0", 0, False),
    ("Console", "0", 0, False),
]

READ_ONLY = bits("SEND_MESSAGES", "SEND_MESSAGES_IN_THREADS", "CREATE_PUBLIC_THREADS")
STAFF_ALLOW = bits("VIEW_CHANNEL", "SEND_MESSAGES", "READ_MESSAGE_HISTORY", "EMBED_LINKS", "ATTACH_FILES")

TYPE_TEXT, TYPE_CATEGORY, TYPE_NEWS, TYPE_FORUM = 0, 4, 5, 15

RULES_TEXT = """**Welcome to Crazy 8 Ball!** Read these before you chat.

**1.** Be respectful. No personal attacks on players or devs.
**2.** No slurs, hate, harassment or NSFW.
**3.** No scams, account selling, trading for real money, or begging for Robux.
**4.** No advertising other servers or games. Your own clips go in #clips.
**5.** Keep personal info private. Don't DM people asking for stuff.
**6.** Feedback goes in #suggestions or #bug-reports, not spammed in #general.
**7.** Staff have the final say. Follow Discord's Terms (13+ only).

**What happens if you break them:** warning, then a 1 hour timeout, then a 24 hour timeout, then a ban.
Scams, NSFW, slurs, raids and anything that puts a kid at risk are an instant ban.

See something bad? Right-click the message (long-press on a phone) and pick **Report Message**. Reports are reviewed and the right action is taken."""

# Rules screening: new members tick "I agree" to these before they can chat or DM anyone here.
SCREENING_RULES = [
    "Be respectful. No personal attacks on players or devs.",
    "No slurs, hate, harassment or NSFW.",
    "No scams, account selling, real-money trading or begging for Robux.",
    "No advertising other servers or games.",
    "Keep personal info private. Don't DM people asking for stuff.",
    "Feedback goes in #suggestions or #bug-reports.",
]

SUGGESTION_GUIDE = (
    "One idea per post. Say what you want and why it would make the game more fun. "
    "Search first and 👍 an existing post instead of making a copy. "
    "Tags like Planned or Added are set by the dev."
)
BUG_GUIDE = (
    "Title: what went wrong in a few words. In the post: what happened, the steps to make it "
    "happen again, your platform (PC, Mobile or Console) and about what time. "
    "Screenshots or clips help a lot."
)


def token():
    out = subprocess.run(
        ["security", "find-generic-password", "-s", "DISCORD_BOT_TOKEN", "-w"],
        capture_output=True,
        text=True,
    )
    value = out.stdout.strip()
    if out.returncode != 0 or not value:
        sys.exit("No DISCORD_BOT_TOKEN in the Keychain. See the plan's setup steps.")
    return value


TOKEN = None


def call(method, path, body=None, reason=None):
    for _ in range(5):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", "Bot " + TOKEN)
        req.add_header("User-Agent", "DiscordBot (crazy8ball-setup, 1.0)")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        if reason:
            req.add_header("X-Audit-Log-Reason", reason)
        try:
            with urllib.request.urlopen(req) as res:
                raw = res.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as err:
            raw = err.read().decode(errors="replace")
            if err.code == 429:
                wait = json.loads(raw).get("retry_after", 1)
                time.sleep(float(wait) + 0.2)
                continue
            raise RuntimeError(f"{method} {path} -> {err.code}: {raw}") from None
    raise RuntimeError(f"{method} {path}: still rate limited")


_counter = 0


def snowflake():
    # Onboarding prompts and options need ids; Discord accepts client-made snowflakes.
    global _counter
    _counter += 1
    return str(((int(time.time() * 1000) - 1420070400000) << 22) + _counter)


def overwrite(target_id, allow="0", deny="0"):
    return {"id": target_id, "type": 0, "allow": allow, "deny": deny}


def inspect(guild, roles, channels):
    print(f"Server: {guild['name']} ({guild['id']}), owner {guild['owner_id']}")
    print(f"Features: {', '.join(guild.get('features', [])) or 'none'}")
    print("Roles:", ", ".join(r["name"] for r in sorted(roles, key=lambda r: -r["position"])))
    cats = {c["id"]: c["name"] for c in channels if c["type"] == TYPE_CATEGORY}
    for c in sorted(channels, key=lambda c: (c.get("parent_id") or "", c["position"])):
        if c["type"] == TYPE_CATEGORY:
            continue
        print(f"  [{cats.get(c.get('parent_id'), '-')}] #{c['name']} (type {c['type']})")
    for name in cats.values():
        print(f"  category: {name}")


def main():
    global TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--remove-template", action="store_true")
    args = ap.parse_args()
    TOKEN = token()

    me = call("GET", "/users/@me")
    guilds = call("GET", "/users/@me/guilds")
    if len(guilds) != 1:
        sys.exit(f"The bot is in {len(guilds)} servers; it must be in exactly one.")
    gid = guilds[0]["id"]
    guild = call("GET", f"/guilds/{gid}?with_counts=true")
    roles = call("GET", f"/guilds/{gid}/roles")
    channels = call("GET", f"/guilds/{gid}/channels")
    print(f"Bot: {me['username']}")
    inspect(guild, roles, channels)
    if not args.apply:
        return

    reason = "Crazy 8 Ball server setup"

    # Discord's starter channels from "Create My Own". Only removed on request, and only when
    # no one but the bot and owner could have used them yet (the server is brand new).
    our_cats = {"START HERE", "COMMUNITY", "FEEDBACK", "STAFF"}
    if args.remove_template:
        if guild.get("approximate_member_count", 99) > 3:
            sys.exit("More than 3 members: not deleting any channels.")
        keep = {c["id"] for c in channels if c["type"] == TYPE_CATEGORY and c["name"] in our_cats}
        for c in channels:
            if c["id"] not in keep and c.get("parent_id") not in keep:
                call("DELETE", f"/channels/{c['id']}", reason=reason)
                print(f"deleted starter channel {c['name']}")
        channels = call("GET", f"/guilds/{gid}/channels")

    # Roles
    by_name = {r["name"]: r for r in roles}
    call("PATCH", f"/guilds/{gid}/roles/{gid}", {"permissions": EVERYONE}, reason)
    for name, perms, color, hoist in ROLES:
        body = {"name": name, "permissions": perms, "color": color, "hoist": hoist, "mentionable": False}
        if name in by_name:
            call("PATCH", f"/guilds/{gid}/roles/{by_name[name]['id']}", body, reason)
        else:
            by_name[name] = call("POST", f"/guilds/{gid}/roles", body, reason)
            print(f"role {name}")
    rid = {name: by_name[name]["id"] for name, *_ in ROLES}
    call("PUT", f"/guilds/{gid}/members/{guild['owner_id']}/roles/{rid['Developer']}", reason=reason)

    staff_ow = [overwrite(rid["Moderator"], STAFF_ALLOW), overwrite(rid["Developer"], STAFF_ALLOW)]
    read_only = [overwrite(gid, deny=READ_ONLY)] + staff_ow
    hidden = [overwrite(gid, deny=bits("VIEW_CHANNEL"))] + staff_ow

    existing = {(c["name"], c.get("parent_id")): c for c in channels}
    cat_by_name = {c["name"]: c for c in channels if c["type"] == TYPE_CATEGORY}

    def category(name, ows):
        if name in cat_by_name:
            c = cat_by_name[name]
            call("PATCH", f"/channels/{c['id']}", {"permission_overwrites": ows}, reason)
        else:
            c = call("POST", f"/guilds/{gid}/channels",
                     {"name": name, "type": TYPE_CATEGORY, "permission_overwrites": ows}, reason)
            cat_by_name[name] = c
            print(f"category {name}")
        return c["id"]

    def channel(name, parent, ows, kind=TYPE_TEXT, **extra):
        body = {"name": name, "type": kind, "parent_id": parent, "permission_overwrites": ows, **extra}
        c = existing.get((name, parent))
        if c:
            body.pop("type")
            c = call("PATCH", f"/channels/{c['id']}", body, reason)
        else:
            c = call("POST", f"/guilds/{gid}/channels", body, reason)
            existing[(name, parent)] = c
            print(f"#{name}")
        return c

    start = category("START HERE", read_only)
    rules = channel("rules", start, read_only, topic="Read before chatting.")
    announcements = channel("announcements", start, read_only, topic="News from the dev.")
    updates = channel("updates", start, read_only, topic="Patch notes for every update.")
    codes = channel("codes", start, read_only,
                    topic="Codes for Crazy 8 Ball. Redeem them in the game's code box.")

    staff = category("STAFF", hidden)
    channel("mod-chat", staff, hidden)
    modlog = channel("mod-log", staff, hidden, topic="AutoMod alerts and Discord safety alerts.")

    # Community mode: rules screening, announcement channels, onboarding, insights.
    features = set(guild.get("features", []))
    settings = {
        "verification_level": 3,  # High: verified email and 10 minutes in the server
        "explicit_content_filter": 2,  # scan media from all members
        "default_message_notifications": 1,  # only @mentions, so members aren't flooded
        "rules_channel_id": rules["id"],
        "public_updates_channel_id": modlog["id"],
        "safety_alerts_channel_id": modlog["id"],
        "system_channel_id": modlog["id"],
        "system_channel_flags": (1 << 0) | (1 << 2) | (1 << 3),  # no join or setup-tip posts
        "description": "The official server for Crazy 8 Ball on Roblox: codes, updates and trickshots.",
    }
    if "COMMUNITY" not in features:
        settings["features"] = sorted(features | {"COMMUNITY"})
    if os.path.exists(LOGO) and not guild.get("icon"):
        with open(LOGO, "rb") as f:
            settings["icon"] = "data:image/png;base64," + base64.b64encode(f.read()).decode()
    call("PATCH", f"/guilds/{gid}", settings, reason)
    print("server settings + Community on")

    # Announcement channels (followable from other servers) need Community first.
    for c in (announcements, updates, codes):
        if c["type"] != TYPE_NEWS:
            call("PATCH", f"/channels/{c['id']}", {"type": TYPE_NEWS}, reason)

    open_ow = staff_ow
    community = category("COMMUNITY", open_ow)
    general = channel("general", community, open_ow, rate_limit_per_user=5,
                      topic="Talk about Crazy 8 Ball. Be nice.")
    clips = channel("clips", community, open_ow + [overwrite(gid, bits("ATTACH_FILES", "EMBED_LINKS"))],
                    rate_limit_per_user=30, topic="Trickshots, wins and funny moments. Clips and screenshots only.")
    offtopic = channel("off-topic", community, open_ow, rate_limit_per_user=5,
                       topic="Anything that isn't Crazy 8 Ball.")

    feedback = category("FEEDBACK", open_ow)
    forum_ow = open_ow + [overwrite(gid, bits("CREATE_PUBLIC_THREADS"))]
    suggestions = channel(
        "suggestions", feedback, forum_ow, TYPE_FORUM, topic=SUGGESTION_GUIDE,
        rate_limit_per_user=600, default_thread_rate_limit_per_user=5,
        default_reaction_emoji={"emoji_name": "👍"},
        available_tags=[
            {"name": "Under Review", "moderated": True},
            {"name": "Planned", "moderated": True},
            {"name": "Added", "moderated": True},
            {"name": "Not Planned", "moderated": True},
        ],
    )
    bugs = channel(
        "bug-reports", feedback,
        forum_ow + [overwrite(gid, bits("CREATE_PUBLIC_THREADS", "ATTACH_FILES"))],
        TYPE_FORUM, topic=BUG_GUIDE, rate_limit_per_user=300, default_thread_rate_limit_per_user=5,
        available_tags=[
            {"name": "PC", "moderated": False},
            {"name": "Mobile", "moderated": False},
            {"name": "Console", "moderated": False},
            {"name": "Known Issue", "moderated": True},
            {"name": "Fixed", "moderated": True},
        ],
    )

    # Category order: START HERE, COMMUNITY, FEEDBACK, STAFF.
    call("PATCH", f"/guilds/{gid}/channels", [
        {"id": start, "position": 0}, {"id": community, "position": 1},
        {"id": feedback, "position": 2}, {"id": staff, "position": 3},
    ], reason)

    # AutoMod. Moderators and Developers are exempt. Criticism words ("AI", "slop") are
    # deliberately not filtered (plan: filtering criticism backfires).
    exempt = [rid["Moderator"], rid["Developer"]]
    alert = {"type": 2, "metadata": {"channel_id": modlog["id"]}}
    block = {"type": 1, "metadata": {"custom_message": "Blocked by AutoMod. See #rules."}}
    timeout = {"type": 3, "metadata": {"duration_seconds": 600}}
    automod = [
        {"name": "Slurs, sexual content, profanity", "trigger_type": 4,
         "trigger_metadata": {"presets": [1, 2, 3]}, "actions": [block, alert]},
        {"name": "Mention spam", "trigger_type": 5,
         "trigger_metadata": {"mention_total_limit": 5, "mention_raid_protection_enabled": True},
         "actions": [block, alert, timeout]},
        {"name": "Spam", "trigger_type": 3, "actions": [block, alert]},
        {"name": "Invites and scams", "trigger_type": 1, "trigger_metadata": {"keyword_filter": [
            "*discord.gg/*", "*discord.com/invite*", "*discordapp.com/invite*",
            "free robux*", "robux generator*", "*free nitro*", "*nitro for free*",
            "*robux for free*", "*rbx.gg*", "*buy my account*", "*selling my account*",
        ]}, "actions": [block, alert, timeout]},
    ]
    have = {r["name"] for r in call("GET", f"/guilds/{gid}/auto-moderation/rules")}
    for rule in automod:
        if rule["name"] in have:
            continue
        call("POST", f"/guilds/{gid}/auto-moderation/rules",
             {**rule, "event_type": 1, "enabled": True, "exempt_roles": exempt}, reason)
        print(f"automod: {rule['name']}")

    # Welcome screen and onboarding (ping roles, platform roles, default channels).
    call("PATCH", f"/guilds/{gid}/welcome-screen", {
        "enabled": True,
        "description": "Codes, updates and trickshots for Crazy 8 Ball.",
        "welcome_channels": [
            {"channel_id": codes["id"], "description": "Get the latest codes", "emoji_name": "🎁"},
            {"channel_id": updates["id"], "description": "See what's new", "emoji_name": "📢"},
            {"channel_id": general["id"], "description": "Chat with players", "emoji_name": "💬"},
            {"channel_id": clips["id"], "description": "Share your trickshots", "emoji_name": "🎱"},
            {"channel_id": suggestions["id"], "description": "Suggest ideas", "emoji_name": "💡"},
        ],
    }, reason)

    def option(title, role, emoji, desc=None):
        o = {"id": snowflake(), "title": title, "role_ids": [rid[role]], "channel_ids": [],
             "emoji": {"name": emoji}}
        if desc:
            o["description"] = desc
        return o

    call("PUT", f"/guilds/{gid}/onboarding", {
        "enabled": True,
        "mode": 0,
        "default_channel_ids": [c["id"] for c in (rules, announcements, updates, codes, general,
                                                  clips, offtopic, suggestions, bugs)],
        "prompts": [
            {"id": snowflake(), "type": 0, "title": "What do you want pings for?",
             "single_select": False, "required": False, "in_onboarding": True, "options": [
                 option("New codes", "Code Pings", "🎁", "A ping when a new code drops"),
                 option("Updates", "Update Pings", "📢", "A ping when the game updates"),
             ]},
            {"id": snowflake(), "type": 0, "title": "What do you play on?",
             "single_select": False, "required": False, "in_onboarding": True, "options": [
                 option("PC", "PC", "🖥️"),
                 option("Mobile", "Mobile", "📱"),
                 option("Console", "Console", "🎮"),
             ]},
        ],
    }, reason)
    print("welcome screen + onboarding")

    # The rules post: posted once, edited in place when RULES_TEXT changes.
    rules_embed = {"embeds": [{"description": RULES_TEXT, "color": 0xF5B800}]}
    msgs = call("GET", f"/channels/{rules['id']}/messages?limit=5")
    mine = [m for m in msgs if m["author"]["id"] == me["id"]]
    if not mine:
        call("POST", f"/channels/{rules['id']}/messages", rules_embed)
        print("rules posted")
    elif (mine[0].get("embeds") or [{}])[0].get("description") != RULES_TEXT:
        call("PATCH", f"/channels/{rules['id']}/messages/{mine[0]['id']}", rules_embed)
        print("rules updated")

    # Rules screening (the client's own endpoint; not in the public docs, so a refusal only warns).
    try:
        call("PATCH", f"/guilds/{gid}/member-verification", {
            "enabled": True,
            "description": "Crazy 8 Ball's server. Agree to the rules to start chatting.",
            "form_fields": [{"field_type": "TERMS", "label": "Read and agree to the server rules",
                             "values": SCREENING_RULES, "required": True}],
        }, reason)
        print("rules screening on")
    except RuntimeError as err:
        print(f"rules screening not set (turn it on in Server Settings): {err}")

    print("\nDone.")
    inspect(call("GET", f"/guilds/{gid}"), call("GET", f"/guilds/{gid}/roles"),
            call("GET", f"/guilds/{gid}/channels"))


if __name__ == "__main__":
    main()
