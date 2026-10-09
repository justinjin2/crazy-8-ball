#!/usr/bin/env python3
"""Ranks search_combo.luau's breaks (tutorial v2, the combination layout): prints each with its
second ball's creep, the pair (front ball to the corner's mouth, the back ball's distance and
cut) and the aim lesson's pot, best first, and writes the top N as a shortlist for
eval_combo.luau's sim mode.

    python3 tools/tutorial_v2/rank_combo.py <breaks.jsonl> <shortlist.jsonl> [N]
"""
import json
import sys

rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 12


def score(r):
    p, a = r["pair"], r["aim"]
    # A near-frozen pair close to its pocket, a gentle aim pot, a long creep.
    return (
        -p["back"] * 1.5
        - p["cut"]
        - p["toMouth"] * 0.3
        - a["cut"] * 0.8
        - a["toGhost"] * 0.1
        + min(r["slow"], 1.5) * 8
        # the aim lesson played at a few powers (search_combo's afterAim): its pot, then the
        # combination on from where the cue ball stopped
        + r.get("aimPots", 0) * 20
        + r.get("comboAfter", 0) * 40
    )


rows.sort(key=score, reverse=True)
for r in rows[:40]:
    p, a = r["pair"], r["aim"]
    print(
        f"seed {r['seed']:5d} dy {r['dy']:+.4f} turn {r['turn']:+.4f} pow {r['power']:.2f} "
        f"creep {r['slow']:.2f}s | pair {p['a']}->{p['b']} P{p['pocket']} mouth {p['toMouth']:.1f} "
        f"back {p['back']:.1f} cut {p['cut']:.1f} | aim {a['ball']}->P{a['pocket']} cut {a['cut']:.1f} "
        f"ghost {a['toGhost']:.1f} | after aim: pot {r.get('aimPots', 0):.2f} combo {r.get('comboAfter', 0):.2f} "
        f"| score {score(r):.1f}"
    )
with open(sys.argv[2], "w") as f:
    for r in rows[:n]:
        f.write(json.dumps(r) + "\n")
print(len(rows), "breaks;", min(n, len(rows)), "shortlisted")
