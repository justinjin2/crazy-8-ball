#!/usr/bin/env python3
"""Ult bar model (ultimates step 1, 2026-09-28).

Plays many simulated 8-ball matches, shot by shot, and checks the designer's ult bar goals
against the SAME numbers the game uses: it runs `lune run tools/export_ult_config.luau`, which
prints Config.Ults.Fill, BarMax and MaxPerMatch from src/shared/Config.luau as JSON. Change
Config, and the model changes with it.

What it models (every rate below is an estimate, see the ASSUMPTIONS block; there are no bots
yet to measure real pot rates):
  - The break: 0-4 balls drop (they are the breaker's balls for the bar), a break scratch is a
    foul, and the table stays open until the first legal pot after the break picks a group
    (the shooter takes the group with more balls already down).
  - Each shot has a leave: easy, normal or hard (a hard leave is a bank, kick or long thin cut).
    A player's skill is their pot chance on a normal leave; easy and hard leaves scale it.
  - Fouls: some misses are fouls (scratch, wrong ball first, no rail), more on hard leaves and
    for weaker players; a pot can also end in a scratch. A foul gives the next shooter ball in
    hand, which raises their pot chance. Pocketing the 8 early, or scratching on the 8, loses.
  - Safeties: a player facing a hard leave plays safe some share of the time (stronger players
    more). A safety is a legal miss; a good one "snookers" the opponent (a much lower pot
    chance next shot, more fouls), and they may play safe back.
  - NICE SHOT! (bank, kick, combo, carom): a share of pots, higher from hard leaves; half of all
    two-ball pots are combos or caroms.
  - The bar exactly as section 5 of docs/prompts/ULTIMATES_PROMPT.md: own balls by position in
    the turn, the nice-shot bonus, the opponent's-ball fill with "behind", turn-end fill for
    legal turns and for the opponent's turns under the TurnCap, the difficulty multiplier, the
    x AfterFirst slowdown (and the cap restarting) after the first ult, and the per-match
    maximum. Balls pocketed on an ult shot fill nothing for the user (the opponent still gets
    theirs). "Behind" uses balls left once groups are set (a side on the 8 has 0 left) and balls
    pocketed on an open table.
  - The hold rule: a player with a full bar does not use it at once. They use it (never on the
    break) when the shot in front of them is below their average pot chance (a hard leave or a
    snooker), when they are behind, when they are on the 8, or when the opponent is on
    the 8. The ult shot is always an attempt, never a safety.
  - Ults: Magnet (Common) adds MAGNET_BOOST to the ult shot's pot chance (the power ladder's
    "about 1/3 of a ball"). The top ult (Legendary/Mythic) pockets 2 or 3 of your balls for sure
    (3 at most, never the 8 before your legal 8 shot; on the 8 shot it pockets the 8).
  - The rarity table: an ult worth W balls per use (measured by the value harness,
    tools/ult_value.luau) pockets floor(W) of your balls for sure and adds W - floor(W) to the
    shot's pot chance (on the 8 shot it adds W to the 8's pot chance). Each rarity's best
    measured ult plays one worth Magnet's measured worth, at equal skill. The worths come from
    tools/ult_value_results.json (the careful shooter's net worth at skill 2, the average
    player) when it has the ult, else Config.Ults.Catalog[id].Worth for a built ult.
  - Goal 2 cheaters: a "tapper" makes a legal tap every shot until the bar is full; a
    "safety farmer" plays a safety every shot until the bar is full. Then each uses the ult at
    once and plays honestly from there.

Run-outs (left out of goal 1, as the designer said): the winner pocketed all of their group
and the 8 in one turn (they had pocketed none of their own balls before that turn; balls they
dropped on their own break count as the same turn).

Run (from anywhere; needs lune on the PATH):
    python3 tools/ult_model.py                       # every check with Config's numbers
    python3 tools/ult_model.py --results other.json  # the rarity table from another harness run
    python3 tools/ult_model.py --fill TurnLegal=18 --fill Difficulty.Classic=1.5
    python3 tools/ult_model.py --fill Own=8,6,5,4 --n 2000 --seed 7
Python standard library only; seeded, so the same inputs print the same numbers.
"""
import argparse
import json
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------------------------
# ASSUMPTIONS (estimates; no bots exist yet to measure them)
# ---------------------------------------------------------------------------------------------
# A player's skill = their pot chance on a normal leave. Classic's long aiming line makes pots
# easier than Difficult/Challenger's short one.
SKILL = {
    "Classic": {"weak": 0.45, "average": 0.62, "strong": 0.80},
    "Difficult": {"weak": 0.30, "average": 0.45, "strong": 0.60},  # Challenger plays the same
}
LEAVES = [("easy", 0.30, 1.25), ("normal", 0.45, 1.00), ("hard", 0.25, 0.55)]  # share, x skill
MAX_POT = 0.97            # nobody pots more often than this, even with ball in hand
BALL_IN_HAND_GAIN = 0.5   # ball in hand: pot chance = p + (1 - p) x this
SNOOKER_MULT = 0.35       # after a good safety: pot chance = p x this (a hard leave)
DOUBLE_POT = 0.07         # share of pots that drop two of your balls
POT_SCRATCH = 0.03        # share of pots where the cue ball follows in (a foul; on the 8, a loss)
EARLY_EIGHT = 0.004       # share of misses (not on the 8) that knock the 8 in: a loss
SAFETY_FOUL = 0.05        # share of safeties that foul
NICE_SHARE = {"easy": 0.02, "normal": 0.06, "hard": 0.30, "snookered": 0.50, "bih": 0.03}
NICE_DOUBLE = 0.5         # share of two-ball pots that are combos or caroms
BREAK_BALLS = [(0, 0.30), (1, 0.35), (2, 0.22), (3, 0.10), (4, 0.03)]  # balls down on the break
BREAK_SCRATCH = 0.06      # a break scratch: a foul, the balls stay down, the table stays open
MAGNET_BOOST = 0.30       # Magnet: + this pot chance on its shot (Common: about 1/3 of a ball)
MAX_SHOTS = 500           # a match longer than this is dropped (never happens in practice)


def foul_share(p):
    """Share of an honest miss that is a foul: weaker players foul more."""
    return 0.18 - 0.12 * p


def safety_share(p):
    """Chance a player facing a hard leave plays safe instead of going for it."""
    return 0.10 + 0.60 * p


def safety_success(p):
    """Chance a safety leaves the opponent snookered (else a normal leave)."""
    return 0.30 + 0.50 * p


# ---------------------------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------------------------
def load_config():
    try:
        out = subprocess.run(
            ["lune", "run", "tools/export_ult_config.luau"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as err:
        sys.exit(f"could not read Config through lune ({err}); is lune installed?")
    return json.loads(out)


def load_results(path):
    """The value harness's measurements (tools/ult_value.luau), or {} when there are none."""
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def measured_worths(cfg, results):
    """Each ult's worth per use for the rarity table: {id: (worth, careless, source)}. A
    harness result for a built ult wins (the careful shooter's net at skill 2, the average
    player; the careless one alongside); else a built ult's Config.Ults.Catalog Worth.
    Placeholders are left out."""
    out = {}
    for uid in cfg.get("Order", []):
        row = cfg.get("Catalog", {}).get(uid, {})
        rep = results.get(uid)
        if rep and rep.get("built"):
            skills = {s["skill"]: s for s in rep.get("skills", [])}
            s = skills.get(2) or next(iter(skills.values()), None)
            careful = s.get("careful") if s else None
            careless = s.get("careless") if s else None
            main = careful or careless
            if main:
                out[uid] = (main["net"], careless["net"] if careless else None,
                            f"harness {rep.get('measuredAt', 'unknown')}, "
                            f"{rep.get('samples')} states, skill {s['skill']}")
                continue
        if row.get("Built"):
            out[uid] = (float(row["Worth"]), None, "Config Worth")
    return out


def rarity_table(cfg, results, n, seed):
    """Each rarity's best measured ult against Magnet at equal skill."""
    worths = measured_worths(cfg, results)
    magnet = worths.get("Magnet", (MAGNET_BOOST, None, "MAGNET_BOOST"))[0]
    print(f"\nRarity table: each rarity's best measured ult vs Magnet (worth {magnet:+.2f}) "
          "at equal skill")
    print("  (worth = extra own balls per use, net of the opponent's; careless in [])")
    setups = [("Classic", 0.60), ("Classic", 0.70), ("Difficult", 0.45)]
    print("  " + " " * 44 + "".join(f"{d[:4]} {p:.2f}  " for d, p in setups))
    for k, rarity in enumerate(cfg.get("Rarities", [])):
        ids = [u for u in cfg.get("Order", [])
               if cfg["Catalog"].get(u, {}).get("Rarity") == rarity and u in worths]
        if not ids:
            targets = [cfg["Catalog"][u]["Worth"] for u in cfg.get("Order", [])
                       if cfg["Catalog"].get(u, {}).get("Rarity") == rarity]
            target = max(targets) if targets else 0.0
            label = f"{rarity:9s} (nothing measured; target {target:.2f})"
            best, worth, careless = None, float(target), None
        else:
            best = max(ids, key=lambda u: worths[u][0])
            worth, careless, _ = worths[best]
            extra = f" [{careless:+.2f}]" if careless is not None else ""
            label = f"{rarity:9s} {best} {worth:+.2f}{extra}"
        cells = []
        for j, (diff, p) in enumerate(setups):
            games = run_many(cfg, diff, p, p, n, seed + 400 + 10 * k + j,
                             ults=(float(max(worth, 0.0)), float(magnet)))
            cells.append(f"{win_rate(games):6.1%}    ")
        print(f"  {label:44s}" + "".join(cells))
    for uid, (worth, careless, source) in worths.items():
        extra = f", careless {careless:+.3f}" if careless is not None else ""
        print(f"    {uid}: {worth:+.3f}{extra} ({source})")


def apply_override(cfg, text):
    """--fill Key=Value on Config.Ults.Fill. Dotted keys reach inside (Difficulty.Classic=1.5),
    commas make a list (Own=8,6,5,4)."""
    key, _, value = text.partition("=")
    parts = key.split(".")
    target = cfg["Fill"]
    for part in parts[:-1]:
        target = target[part]
    def number(v):
        x = float(v)
        return int(x) if x.is_integer() else x

    if "," in value:
        target[parts[-1]] = [number(v) for v in value.split(",")]
    else:
        target[parts[-1]] = number(value)


# ---------------------------------------------------------------------------------------------
# One match
# ---------------------------------------------------------------------------------------------
class Player:
    def __init__(self, p, ult, cheat):
        self.p = p
        self.ult = ult          # "Magnet", "Top", or a float: an ult worth that many balls
        self.cheat = cheat      # None, "tap" or "safety"
        self.bar = 0.0
        self.used = 0
        self.turn_fill = 0.0    # turn-end fill counted against TurnCap since the last reset
        self.group = None
        self.pocketed = 0       # own balls this player has pocketed (break balls count)
        self.ever_full = False


class Match:
    def __init__(self, cfg, difficulty, pa, pb, rng, ults=("Magnet", "Magnet"),
                 cheats=(None, None)):
        self.fill = cfg["Fill"]
        self.bar_max = cfg["BarMax"]
        self.max_ults = cfg["MaxPerMatch"]
        self.mult = self.fill["Difficulty"][difficulty]
        self.rng = rng
        self.pl = [Player(pa, ults[0], cheats[0]), Player(pb, ults[1], cheats[1])]
        self.left = {"solids": 7, "stripes": 7}

    # --- the bar -----------------------------------------------------------------------------
    def add(self, i, value, turn_end=False):
        P = self.pl[i]
        if P.used >= self.max_ults or value <= 0:
            return
        value *= self.mult * (self.fill["AfterFirst"] if P.used else 1.0)
        if turn_end:  # the cap is in bar points and never scales
            value = max(0.0, min(value, self.fill["TurnCap"] - P.turn_fill))
            P.turn_fill += value
        P.bar = min(self.bar_max, P.bar + value)
        if P.bar >= self.bar_max:
            P.ever_full = True

    def ready(self, i):
        P = self.pl[i]
        return P.bar >= self.bar_max and P.used < self.max_ults

    def use(self, i):
        P = self.pl[i]
        P.bar, P.used, P.turn_fill = 0.0, P.used + 1, 0.0

    # --- table state -------------------------------------------------------------------------
    def balls_left(self, i):
        g = self.pl[i].group
        return None if g is None else self.left[g]

    def behind(self, i):
        """How many balls player i is behind (negative = ahead)."""
        me, op = self.pl[i], self.pl[1 - i]
        if me.group is None:  # open table: compare balls pocketed
            return op.pocketed - me.pocketed
        return self.left[me.group] - self.left[op.group]

    def pick_group(self, i):
        """First legal pot on an open table: take the group with more balls down."""
        a, b = self.left["solids"], self.left["stripes"]
        g = "solids" if a < b else "stripes" if b < a else self.rng.choice(("solids", "stripes"))
        self.pl[i].group = g
        self.pl[1 - i].group = "stripes" if g == "solids" else "solids"

    def pocket(self, s, n, run, nice, ult_shot):
        """Shooter s pockets n of their own balls. Returns the new run length."""
        o = 1 - s
        own, after = self.fill["Own"], self.fill["OwnAfter"]
        for _ in range(n):
            self.left[self.pl[s].group] -= 1
            self.pl[s].pocketed += 1
            if not ult_shot:
                self.add(s, own[run] if run < len(own) else after)
            run += 1
            self.add(o, self.fill["OppBase"] + self.fill["OppPerBehind"] * max(0, self.behind(o)))
        if nice and not ult_shot:
            self.add(s, self.fill["Nice"])
        return run

    # --- decisions ---------------------------------------------------------------------------
    def wants_ult(self, s, q):
        P, left = self.pl[s], self.balls_left(s)
        if P.cheat and P.used == 0:
            return True  # a farmer spends it at once: that was the point
        return (q < P.p or self.behind(s) >= 1 or left == 0
                or self.balls_left(1 - s) == 0)

    # --- play --------------------------------------------------------------------------------
    def play(self):
        rng, s = self.rng, self.rng.randrange(2)
        sit, shots = "break", 0
        while shots < MAX_SHOTS:
            o = 1 - s
            P = self.pl[s]
            own_before = P.pocketed  # a run-out pockets all of its own balls in one turn
            run, end = 0, None
            while end is None:
                shots += 1
                end, sit, run = self.shot(s, sit, run)
                if end in ("win", "lose"):
                    winner = s if end == "win" else o
                    runout = end == "win" and own_before == 0
                    return {"winner": winner, "runout": runout, "shots": shots}
            # the turn ended: turn-end fill
            if end == "legal":
                self.add(s, self.fill["TurnLegal"], turn_end=True)
            self.add(o, self.fill["OppTurn"], turn_end=True)
            s = o
        return None

    def shot(self, s, sit, run):
        """One shot. Returns (end, next situation, run): end is None (keep shooting), "legal",
        "foul", "win" or "lose"; the next situation is for whoever shoots next."""
        rng, P = self.rng, self.pl[s]
        if sit == "break":
            return self.break_shot(s)

        # the leave in front of the shooter
        p = P.p
        if sit == "bih":
            leave, q = "bih", p + (1 - p) * BALL_IN_HAND_GAIN
        elif sit == "snookered":
            leave, q = "snookered", p * SNOOKER_MULT
        else:
            x, leave, q = rng.random(), "hard", p * LEAVES[-1][2]
            for name, share, scale in LEAVES:
                if x < share:
                    leave, q = name, p * scale
                    break
                x -= share
        q = min(MAX_POT, q)
        hard = leave in ("hard", "snookered")
        left = self.balls_left(s)

        # the ult (never on the break)
        ult = self.ready(s) and self.wants_ult(s, q)
        if ult:
            self.use(s)
        elif P.cheat and P.used == 0:
            # a farmer wastes the shot until the bar is full
            if P.cheat == "tap":
                return "legal", "open", run
            return self.safety(s, run)
        elif hard and rng.random() < safety_share(p):
            return self.safety(s, run)

        # the attempt
        if ult and P.ult == "Top":
            if left == 0:
                return "win", None, run
            if left is None:
                self.pick_group(s)
                left = self.balls_left(s)
            n = min(left, rng.choice((2, 3)))
            run = self.pocket(s, n, run, False, True)
            if rng.random() < POT_SCRATCH:
                return "foul", "bih", run
            return None, "open", run
        if ult and isinstance(P.ult, float):
            return self.worth_shot(s, q, run, left, P.ult)
        if ult:
            q = min(MAX_POT, q + MAGNET_BOOST)
        if rng.random() < q:
            if left == 0:  # the 8
                return ("lose" if rng.random() < POT_SCRATCH else "win"), None, run
            if left is None:
                self.pick_group(s)
                left = self.balls_left(s)
            n = 2 if (left >= 2 and rng.random() < DOUBLE_POT) else 1
            nice = rng.random() < (NICE_DOUBLE if n == 2 else NICE_SHARE[leave])
            run = self.pocket(s, n, run, nice, ult)
            if rng.random() < POT_SCRATCH:
                return "foul", "bih", run
            return None, "open", run
        # a miss
        if left != 0 and rng.random() < EARLY_EIGHT:
            return "lose", None, run
        foul = foul_share(p) * (2.0 if leave == "snookered" else 1.5 if hard else 1.0)
        if rng.random() < foul:
            return "foul", "bih", run
        return "legal", "open", run

    def worth_shot(self, s, q, run, left, worth):
        """The ult shot of an ult worth `worth` balls a use: floor(worth) of your balls for
        sure, and the rest of it on the pot chance of the shot itself (never the 8 early)."""
        rng = self.rng
        sure, extra = int(worth), worth - int(worth)
        if left == 0:  # the 8: the whole worth goes on its pot chance
            if rng.random() < min(MAX_POT, q + worth):
                return ("lose" if rng.random() < POT_SCRATCH else "win"), None, run
            return "legal", "open", run
        n = sure + (1 if rng.random() < min(MAX_POT, q + extra) else 0)
        if n == 0:
            if rng.random() < foul_share(self.pl[s].p):
                return "foul", "bih", run
            return "legal", "open", run
        if left is None:
            self.pick_group(s)
            left = self.balls_left(s)
        run = self.pocket(s, min(n, left), run, False, True)
        if rng.random() < POT_SCRATCH:
            return "foul", "bih", run
        return None, "open", run

    def safety(self, s, run):
        rng, p = self.rng, self.pl[s].p
        if rng.random() < SAFETY_FOUL:
            return "foul", "bih", run
        return "legal", ("snookered" if rng.random() < safety_success(p) else "open"), run

    def break_shot(self, s):
        rng = self.rng
        x, k = rng.random(), 0
        for balls, share in BREAK_BALLS:
            if x < share:
                k = balls
                break
            x -= share
        o, own = 1 - s, self.fill["Own"]
        for run in range(k):
            self.left[rng.choice(("solids", "stripes"))] -= 1
            self.pl[s].pocketed += 1
            self.add(s, own[run] if run < len(own) else self.fill["OwnAfter"])
            self.add(o, self.fill["OppBase"] + self.fill["OppPerBehind"] * max(0, self.behind(o)))
        if rng.random() < BREAK_SCRATCH:
            return "foul", "bih", k
        if k == 0:
            return "legal", "open", 0
        return None, "open", k


# ---------------------------------------------------------------------------------------------
# Runs and reports
# ---------------------------------------------------------------------------------------------
def run_many(cfg, difficulty, pa, pb, n, seed, **kw):
    rng = random.Random(seed)
    games = []
    for _ in range(n):
        m = Match(cfg, difficulty, pa, pb, rng, **kw)
        r = m.play()
        if r:
            r["used"] = [P.used for P in m.pl]
            r["full"] = [P.ever_full for P in m.pl]
            games.append(r)
    return games


def goal1_row(cfg, difficulty, pa, pb, n, seed):
    games = run_many(cfg, difficulty, pa, pb, n, seed)
    fair = [g for g in games if not g["runout"]]
    both = sum(all(u >= 1 for u in g["used"]) for g in fair) / len(fair)
    both_full = sum(all(g["full"]) for g in fair) / len(fair)
    second = sum(u == 2 for g in games for u in g["used"]) / (2 * len(games))
    runouts = 1 - len(fair) / len(games)
    shots = sum(g["shots"] for g in games) / len(games)
    print(f"  {difficulty:9s} {pa:.2f} vs {pb:.2f}: both use an ult {both:5.1%} "
          f"(both filled {both_full:5.1%}), run-outs left out {runouts:4.1%}, "
          f"second ults {second:4.1%}, {shots:4.1f} shots a match")
    return both, second


def win_rate(games, player=0):
    return sum(g["winner"] == player for g in games) / len(games)


def pot_stats(cfg, n, seed):
    """Shot-level rates for the assumptions list: share of pots that are nice shots, fouls per
    turn. Measured with a counting wrapper around one average Classic matchup."""
    counts = {"pots": 0, "nice": 0}
    real_pocket = Match.pocket

    def counting_pocket(self, s, k, run, nice, ult_shot):
        counts["pots"] += 1
        counts["nice"] += nice
        return real_pocket(self, s, k, run, nice, ult_shot)

    Match.pocket = counting_pocket
    try:
        for diff in ("Classic", "Difficult"):
            p = SKILL[diff]["average"]
            run_many(cfg, diff, p, p, n, seed)
    finally:
        Match.pocket = real_pocket
    return counts["nice"] / counts["pots"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fill", action="append", default=[],
                    help="override a Config.Ults.Fill number, e.g. TurnLegal=18, "
                         "Difficulty.Classic=1.5, Own=8,6,5,4")
    ap.add_argument("--n", type=int, default=10000, help="matches per row (default 10000)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--results", default=os.path.join(ROOT, "tools", "ult_value_results.json"),
                    help="the value harness's results (tools/ult_value.luau)")
    args = ap.parse_args()

    cfg = load_config()
    for text in args.fill:
        apply_override(cfg, text)
    F, n, seed = cfg["Fill"], args.n, args.seed
    ok = True

    print("Config.Ults.Fill" + (" (with overrides)" if args.fill else "") + ":")
    print("  " + json.dumps(F, sort_keys=True))
    print(f"  BarMax {cfg['BarMax']}, MaxPerMatch {cfg['MaxPerMatch']}")

    print("\nFixed checks (from level, no nice shots, no turn fill):")
    for diff in ("Classic", "Difficult"):
        mult = F["Difficulty"][diff]
        four = mult * sum(F["OppBase"] + F["OppPerBehind"] * k for k in range(1, 5))
        three = mult * sum(F["OppBase"] + F["OppPerBehind"] * k for k in range(1, 4))
        own = F["Own"]
        seven = mult * sum(own[k] if k < len(own) else F["OwnAfter"] for k in range(7))
        good = four >= cfg["BarMax"] > three and seven < cfg["BarMax"]
        ok &= good
        print(f"  {diff:9s} 4 opponent balls +{four:.0f}, 3 opponent balls +{three:.0f}, "
              f"your own run of 7 +{seven:.0f}  {'OK' if good else 'MISSED'}")

    print(f"\nGoal 1: both players use an ult (hold rule), {n} matches a row, run-outs left out:")
    if F["Difficulty"]["Challenger"] == F["Difficulty"]["Difficult"]:
        print("  (Challenger plays as Difficult here: the same pot rates and multiplier)")
    else:
        print("  NOTE: Challenger's multiplier differs from Difficult's; rerun rows with it")
    worst, worst_second = 1.0, 0.0
    rows = []
    for diff in ("Classic", "Difficult"):
        S = SKILL[diff]
        for a, b in [("weak", "weak"), ("average", "average"), ("strong", "strong"),
                     ("strong", "weak"), ("average", "weak"), ("strong", "average")]:
            rows.append((diff, S[a], S[b]))
    for i, (diff, a, b) in enumerate(rows):
        both, second = goal1_row(cfg, diff, a, b, n, seed + i)
        worst, worst_second = min(worst, both), max(worst_second, second)
    good = worst >= 0.80 and worst_second <= 0.05
    ok &= good
    print(f"  worst: both use an ult {worst:.1%} (goal 80%+), second ults at most "
          f"{worst_second:.1%} (goal under about 5%)  {'OK' if good else 'MISSED'}")

    print("\nGoal 2: a player who misses on purpose until the ult is ready, vs an honest equal"
          " player (honest vs honest is 50%):")
    for diff in ("Classic", "Difficult"):
        for level, p in SKILL[diff].items():
            rates = []
            for k, cheat in enumerate(("tap", "safety")):
                games = run_many(cfg, diff, p, p, n // 2, seed + 100 + k, cheats=(cheat, None))
                rates.append(win_rate(games))
            good = max(rates) < 0.5
            ok &= good
            print(f"  {diff:9s} {level:7s} ({p:.2f}): tapper wins {rates[0]:5.1%}, "
                  f"safety farmer wins {rates[1]:5.1%}  {'OK' if good else 'MISSED'}")

    print("\nPower ladder: a top ult (2-3 sure balls, 3 at most) vs Magnet (rough model in [])")
    ladder = [("Classic", 0.60, 0.60, "60%"), ("Classic", 0.70, 0.70, "56%"),
              ("Difficult", 0.45, 0.45, "64%"), ("Classic", 0.50, 0.60, "63%")]
    for k, (diff, a, b, rough) in enumerate(ladder):
        games = run_many(cfg, diff, a, b, n, seed + 200 + k, ults=("Top", "Magnet"))
        print(f"  {diff:9s} {a:.2f} with the top ult vs {b:.2f} with Magnet: "
              f"top ult wins {win_rate(games):5.1%}  [{rough}]")
    games = run_many(cfg, "Classic", 0.50, 0.60, n, seed + 210)
    print(f"  Classic   0.50 vs 0.60, both Magnet: the 0.50 player wins {win_rate(games):5.1%}"
          f"  [31%]")
    for k, (diff, p) in enumerate((("Classic", 0.62), ("Difficult", 0.45))):
        games = run_many(cfg, diff, p, p, n, seed + 220 + k, ults=("Magnet", "Magnet"))
        print(f"  {diff:9s} {p:.2f} vs {p:.2f}, both Magnet: {win_rate(games):5.1%} "
              f"(a fair coin, as a control)")

    rarity_table(cfg, load_results(args.results), n, seed)

    nice = pot_stats(cfg, n // 4, seed + 300)
    print(f"\nNICE SHOT! share of pots (average players, both tables): {nice:.1%}")
    print("\nALL TARGETS MET" if ok else "\nA TARGET WAS MISSED (see MISSED above)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
