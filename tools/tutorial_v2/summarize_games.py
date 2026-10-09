#!/usr/bin/env python3
"""Tutorial v2: the measures of docs/prompts/TUTORIAL_V2_PROMPT.md 5.2 from sim_game.luau's
JSON lines (one simulated game 1 per line). Prints a table; --json writes the numbers.

    python3 tools/tutorial_v2/summarize_games.py games.jsonl [more.jsonl ...] [--json out.json]
"""
import json
import statistics
import sys


def pct(n, d):
    return 100.0 * n / d if d else 0.0


def quantile(values, q):
    if not values:
        return 0.0
    v = sorted(values)
    i = min(len(v) - 1, max(0, int(round(q * (len(v) - 1)))))
    return v[i]


def summarize(path):
    rows = [json.loads(line) for line in open(path) if line.strip()]
    n = len(rows)
    dead = [r for r in rows if r.get("dead")]
    lost = [r for r in rows if r.get("lost")]
    won = [r for r in rows if r.get("won")]
    aim = [r["aim"] for r in rows if r.get("aim")]
    aim_pot = [a for a in aim if a.get("pot")]
    ric = [a for a in aim_pot if a.get("ricochet")]
    planned = [a for a in aim_pot if a.get("plannedSecond")]
    ability = [r["ability"] for r in rows if r.get("ability")]
    ab_pot = [a for a in ability if a.get("pot")]
    ab_any = [a for a in ability if a.get("anyPot")]
    after = [r["after"] for r in rows if r.get("after")]
    after_pot = [a for a in after if a.get("pot")]
    missed = [r for r in rows if r.get("misses", 0) > 0]
    hand = [r for r in rows if r.get("hand")]
    secs = [r["seconds"] for r in won]
    turns = [r.get("playerTurns", 0) for r in won]
    shots = [r.get("shots", 0) for r in won]
    eight_back = sum(r.get("eightBack", 0) for r in rows)
    eight_games = sum(1 for r in rows if r.get("eightBack", 0) > 0)
    eight_bot = sum(1 for r in rows if r.get("eightMovedByBot", 0) > 0)
    bot_shots = [s for r in rows for s in r.get("botShots", [])]
    bot_pot_player = sum(1 for s in bot_shots if s.get("theirs", 0) > 0)
    bot_later_pots = sum(1 for s in bot_shots if s.get("visit", 1) > 1 and s.get("down", 0) > 0)
    visit1 = [s for s in bot_shots if s.get("visit") == 1]
    v1_scratch = sum(1 for s in visit1 if s.get("scratch"))
    v1_pot = sum(1 for s in visit1 if s.get("plan") == "pot" and s.get("down", 0) > 0)
    first_visits = sum(1 for r in rows if any(s.get("visit") == 1 for s in r.get("botShots", [])))
    by_kind = {}
    for r in rows:
        k = r.get("kind", "?")
        d = by_kind.setdefault(k, {"n": 0, "aim": 0, "secs": []})
        d["n"] += 1
        if r.get("aim", {}).get("pot"):
            d["aim"] += 1
        if r.get("won"):
            d["secs"].append(r["seconds"])
    out = {
        "file": path,
        "games": n,
        "won": len(won),
        "lost": len(lost),
        "dead": len(dead),
        "deadReasons": sorted({r["dead"] for r in dead})[:5],
        "aimPotPct": pct(len(aim_pot), len(aim)),
        "ricochetPctOfPotters": pct(len(ric), len(aim_pot)),
        "plannedRicochetPct": pct(len(planned), len(aim_pot)),
        "abilityPotPct": pct(len(ab_pot), len(ability)),
        "abilityAnyPotPct": pct(len(ab_any), len(ability)),
        "afterAbilityPotPct": pct(len(after_pot), len(after)),
        "missAtLeastOncePct": pct(len(missed), n),
        "ballInHandPct": pct(len(hand), n),
        "firstBotVisitScratchPct": pct(v1_scratch, first_visits),
        "firstBotVisitPotPct": pct(v1_pot, first_visits),
        "botPottedPlayerBall": bot_pot_player,
        "botPotsAfterVisit1": bot_later_pots,
        "eightBackFouls": eight_back,
        "gamesWithEightBack": eight_games,
        "gamesBotMovedEight": eight_bot,
        "secondsMedian": statistics.median(secs) if secs else 0,
        "secondsP90": quantile(secs, 0.9),
        "playerTurnsMedian": statistics.median(turns) if turns else 0,
        "shotsMedian": statistics.median(shots) if shots else 0,
        "byKind": {
            k: {
                "n": v["n"],
                "aimPotPct": pct(v["aim"], v["n"]),
                "secondsMedian": statistics.median(v["secs"]) if v["secs"] else 0,
            }
            for k, v in sorted(by_kind.items())
        },
    }
    return out


def main():
    args = sys.argv[1:]
    json_out = None
    if "--json" in args:
        i = args.index("--json")
        json_out = args[i + 1]
        args = args[:i] + args[i + 2 :]
    results = [summarize(p) for p in args]
    for r in results:
        print(f"== {r['file']} ({r['games']} games)")
        for k, v in r.items():
            if k in ("file", "byKind"):
                continue
            print(f"  {k}: {round(v, 1) if isinstance(v, float) else v}")
        for k, v in r["byKind"].items():
            print(f"  kind {k}: n {v['n']}, aim pot {v['aimPotPct']:.0f}%, median {v['secondsMedian']:.0f} s")
    if json_out:
        json.dump(results, open(json_out, "w"), indent=1)


if __name__ == "__main__":
    main()
