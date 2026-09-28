#!/usr/bin/env python3
"""Rough ult bar model (planning session, 2026-09-28). Plays many simple 8-ball races and checks
the designer's goals:
  1. Both players use their ult in 80%+ of matches, leaving out run-outs (a player who pockets
     all 7 and the 8 in one turn). Classic (easy aiming, high pot rates, short matches) gets a
     fill multiplier; Difficult and Challenger go back and forth, so they fill naturally.
  2. Missing on purpose to farm the bar never pays: turn-end fill needs a legal shot and gives at
     most TurnCap of each bar, so someone must pocket balls for a bar to fill.
The ultimates run replaces this with a fuller model that reads the same numbers as Config.Ults.
Run: python3 tools/ult_model.py"""
import random

FILL = dict(
    own=[8, 6, 5, 4], own_after=2,   # your balls in one turn: +8, +6, +5, +4, then +2 each
    trick=20,                        # a nice shot (bank, kick, combo, carom) on top
    opp_base=8, opp_per_behind=7,    # an opponent's ball: +8, +7 per ball you are then behind
    turn=15,                         # each of your turns that ends on a LEGAL shot (no foul)
    opp_turn=6,                      # each of the opponent's turns that ends
    turn_cap=50,                     # turn-end fill gives at most this much of each bar
    second_mult=0.3, max_ults=2, cap=100,
)
DIFFICULTY_MULT = {"Classic": 1.3, "Difficult": 1.0, "Challenger": 1.0}  # every gain x this
FOUL_RATE = 0.08   # share of an honest player's misses that are fouls (no turn fill)
ULT_BOOST = 0.30   # extra pot chance on the ult shot (a Magnet-sized nudge)


def match(p_a, p_b, c, mult, rng, farmer=None):
    pl = [dict(p=p, left=7, bar=0.0, used=0, tfill=0.0) for p in (p_a, p_b)]

    def add(i, v, turn_fill=False):
        P = pl[i]
        if P["used"] >= c["max_ults"]:
            return
        v *= mult * (c["second_mult"] if P["used"] else 1)
        if turn_fill:
            v = max(0.0, min(v, c["turn_cap"] - P["tfill"]))
            P["tfill"] += v
        P["bar"] = min(c["cap"], P["bar"] + v)

    cur, first, shots = rng.randrange(2), True, 0
    while shots < 600:
        me, op, run, start_left = pl[cur], pl[1 - cur], 0, pl[cur]["left"]
        while True:
            shots += 1
            ult = me["bar"] >= 100 and me["used"] < c["max_ults"] and not first
            if ult:  # players here use it as soon as they can: this measures availability
                me["bar"], me["used"], me["tfill"] = 0, me["used"] + 1, 0.0
            farming = farmer == cur and not ult and not first
            p = 0 if farming else (0.55 if first else me["p"] + (ULT_BOOST if ult else 0))
            first = False
            if rng.random() >= p:
                if farming or rng.random() >= FOUL_RATE:  # a farmer's taps are legal shots
                    add(cur, c["turn"], True)
                add(1 - cur, c["opp_turn"], True)
                break
            if me["left"] == 0:
                return dict(pl=pl, win=cur, runout=start_left == 7)
            trick = rng.random() < 0.12
            for _ in range(2 if rng.random() < 0.07 and me["left"] >= 2 else 1):
                me["left"] -= 1
                if not ult:
                    add(cur, c["own"][run] if run < len(c["own"]) else c["own_after"])
                    if trick:
                        add(cur, c["trick"]); trick = False
                run += 1
                add(1 - cur, c["opp_base"] + c["opp_per_behind"] * max(0, op["left"] - me["left"]))
        cur = 1 - cur
    return None


def report(p_a, p_b, difficulty, n=15000, seed=1):
    rng = random.Random(seed)
    R = [m for m in (match(p_a, p_b, FILL, DIFFICULTY_MULT[difficulty], rng) for _ in range(n)) if m]
    fair = [m for m in R if not m["runout"]]
    both = sum(all(P["used"] >= 1 for P in m["pl"]) for m in fair) / len(fair)
    two = sum(P["used"] == 2 for m in R for P in m["pl"]) / (2 * len(R))
    print(f"  {difficulty:10s} shooters {p_a:.2f} vs {p_b:.2f}: both use an ult {both:.0%} "
          f"(run-outs left out: {1 - len(fair) / len(R):.0%}), second ults {two:.1%}")
    return both


def farmer_win_rate(p, difficulty, n=15000, seed=3):
    rng = random.Random(seed)
    R = [m for m in (match(p, p, FILL, DIFFICULTY_MULT[difficulty], rng, farmer=0)
                     for _ in range(n)) if m]
    return sum(m["win"] == 0 for m in R) / len(R)


if __name__ == "__main__":
    c = FILL
    four = sum(c["opp_base"] + c["opp_per_behind"] * k for k in range(1, 5))
    own7 = sum(c["own"]) + 3 * c["own_after"]
    print(f"4 opponent balls in a row from level: +{four} (x1.3 in Classic: +{four * 1.3:.0f})")
    print(f"your own run of 7: +{own7} (x1.3 in Classic: +{own7 * 1.3:.0f}); nice shots add 20")
    print(f"missing on purpose: at most +{c['turn_cap']} of any bar")
    worst = 1.0
    print("Classic (easy aiming, high pot rates):")
    for a, b in [(0.5, 0.5), (0.6, 0.6), (0.7, 0.7), (0.75, 0.75), (0.7, 0.5)]:
        worst = min(worst, report(a, b, "Classic"))
    print("Difficult / Challenger (lower pot rates, more back and forth):")
    for a, b in [(0.35, 0.35), (0.45, 0.45), (0.55, 0.55), (0.6, 0.4)]:
        worst = min(worst, report(a, b, "Difficult"))
    print(f"worst case: {worst:.0%} (goal 80%+)")
    print("a player who misses on purpose until the ult is ready, vs an honest equal player, wins: "
          + ", ".join(f"{farmer_win_rate(p, 'Classic'):.1%} at {p:.0%}" for p in (0.4, 0.55, 0.7)))
