"""Halloween pacing model (hw-core): minutes of play to each goal for two players.

Measured (live): 6.3 min a match including lobby time (2026-10-11), 23.1 min a day per DAU.
Everything else is a labelled ESTIMATE (see PERSONAS). Expected values, not dice: a "0.5 win"
counts as half a win, so quest progress moves smoothly.
"""

import sys

MATCH_MIN = 6.3  # measured: minutes a match with the lobby time
RUSH_SHARE = 10 / 60  # Candy Rush: 10 minutes of every hour at 2x
PER_BALL, FINISHED, WIN = 3, 10, 25  # Config.Halloween.Match
REWARDS = [60, 100, 150, 250]  # Config.Halloween.Quests.Rewards
TRACK = [50, 150, 300, 500, 1000, 1500, 2000, 3000, 4500, 5500, 7000]
TRACK_NAME = {150: "Candy Corn", 500: "Jack", 2000: "Bone", 7000: "Broom"}
SPIDER_MIN = 10860 / 60
KING_CANDY, KING_PAID = 50, 2
PICKUP_CAP = 40  # an hour

# Config.Halloween.Quests.Boards (the main rows; hooks are all on).
BOARDS = [
    [("Wins", 1), ("Balls", 15), ("Matches", 3), ("Pickups", 15)],
    [("TeamMatches", 1), ("King", 1), ("Wins", 2), ("Balls", 30)],
    [("UltMatches", 3), ("Wins", 3), ("NiceShots", 5), ("Pickups", 30)],
    [("Active", 30), ("King", 2), ("Balls", 50), ("Wins", 5)],
    [("TeamWins", 1), ("Wins", 6), ("Balls", 75), ("Pickups", 50)],
    [("Active", 45), ("King", 3), ("Wins", 8), ("Balls", 100)],
]

# ESTIMATES, per match unless said: balls the player pockets (a finished 1v1: the winner 8, the
# loser about 4; forfeits pull it down), nice shots, the share of matches with an ability used,
# the share that are 2v2/3v3, pickups an hour of play (the map targets 25 for an active player),
# King challenges a day and the share won, the boost (group +10%).
PERSONAS = {
    "casual": dict(
        min_per_day=23.1, win=0.5, balls=5.0, nice=0.3, ult=0.3, team=0.0,
        pickups_h=10, king_tries=0, king_win=0.0, boost=0.0,
    ),
    "active": dict(
        min_per_day=60, win=0.5, balls=5.0, nice=0.4, ult=0.6, team=0.15,
        pickups_h=25, king_tries=2, king_win=0.5, boost=0.1,
    ),
}


def run(p, days=7, step_min=0.1):
    q = {}  # (board, slot) -> progress
    claimed = set()
    candy = 0.0
    play = 0.0  # cumulative minutes of play
    reached = {}  # goal -> (day, minute of play)
    session_end = []
    for day in range(1, days + 1):
        double = day == 4  # Oct 31: 2x all day (Rush does not stack)
        mult = (2.0 if double else 1 + RUSH_SHARE) * (1 + p["boost"])
        open_boards = min(day, len(BOARDS))  # day 7 (Nov 3, to 19:00 EST): no new board
        start = play
        king_paid_today = 0
        t = 0.0
        while t < p["min_per_day"] - 1e-9:
            dt = min(step_min, p["min_per_day"] - t)
            t += dt
            play += dt
            m = dt / MATCH_MIN  # matches finished in this slice (expected)
            events = {
                "Matches": m,
                "Wins": m * p["win"] * (1 - p["team"]),
                "Balls": m * p["balls"] * (1 - p["team"] * 0.5),
                "NiceShots": m * p["nice"],
                "UltMatches": m * p["ult"],
                "TeamMatches": m * p["team"],
                "TeamWins": m * p["team"] * p["win"],
                "Pickups": min(p["pickups_h"], PICKUP_CAP) * dt / 60,
                "Active": dt,
            }
            # King: tries spread over the session's first half (each ~5 min of play).
            if p["king_tries"] and t <= p["min_per_day"] / 2:
                kw = p["king_tries"] * p["king_win"] * dt / (p["min_per_day"] / 2)
                events["King"] = kw
                paid = min(kw, KING_PAID - king_paid_today)
                king_paid_today += paid
                candy += paid * KING_CANDY
            candy += m * (p["balls"] * PER_BALL + FINISHED + p["win"] * WIN) * mult
            # Route: oldest open board's unfinished quest of the kind first, the rest flows.
            for kind, amount in events.items():
                left = amount
                for b in range(open_boards):
                    for s, (k, need) in enumerate(BOARDS[b]):
                        if k != kind or left <= 0:
                            continue
                        have = q.get((b, s), 0.0)
                        if have < need:
                            add = min(need - have, left)
                            q[(b, s)] = have + add
                            left -= add
            for b in range(open_boards):
                for s, (k, need) in enumerate(BOARDS[b]):
                    if (b, s) not in claimed and q.get((b, s), 0) >= need - 1e-6:
                        claimed.add((b, s))
                        candy += REWARDS[s]
                        reached[f"Q{b + 1}.{s + 1} {k} {need}"] = (day, play)
            for at in TRACK:
                if candy >= at and f"T{at}" not in reached:
                    reached[f"T{at}"] = (day, play)
            if play >= SPIDER_MIN and "Spider" not in reached:
                reached["Spider"] = (day, play)
        nxt = next((at for at in TRACK if candy < at), None)
        rate = (candy - (session_end[-1][1] if session_end else 0)) / max(play - start, 1e-9)
        open_q = [
            (b, s, k, need, q.get((b, s), 0.0))
            for b in range(open_boards)
            for s, (k, need) in enumerate(BOARDS[b])
            if (b, s) not in claimed
        ]
        # The closest unfinished quest by share done.
        close = max(open_q, key=lambda r: r[4] / r[3], default=None)
        session_end.append((day, candy, nxt, rate, close, play))
    return reached, session_end


def main():
    for name, p in PERSONAS.items():
        reached, ends = run(p)
        print(f"== {name}: {p['min_per_day']} min a day")
        for key in [f"T{a}" for a in TRACK] + ["Spider"]:
            if key in reached:
                d, m = reached[key]
                label = key if key == "Spider" else f"{key[1:]} {TRACK_NAME.get(int(key[1:]), '')}"
                print(f"  {label:>18}: day {d}, {m:6.0f} min of play")
            else:
                print(f"  {key:>18}: not by the end")
        print("  quests done:", sum(1 for k in reached if k.startswith("Q")), "of 24")
        for day, candy, nxt, rate, close, play in ends:
            gap = (nxt - candy) if nxt else 0
            mins = gap / rate if rate > 0 and nxt else 0
            cq = f"Q{close[0] + 1}.{close[1] + 1} {close[2]} {close[4]:.0f}/{close[3]}" if close else "-"
            print(
                f"  end of day {day}: {candy:6.0f} Candy, next step {nxt} in {gap:4.0f}"
                f" (~{mins:3.0f} min at today's pace); closest quest {cq}"
            )
        undone = [
            f"Q{b + 1}.{s + 1} {k} {need}"
            for b in range(len(BOARDS))
            for s, (k, need) in enumerate(BOARDS[b])
            if f"Q{b + 1}.{s + 1} {k} {need}" not in reached
        ]
        print("  not done by the end:", ", ".join(undone) or "none")


if __name__ == "__main__":
    sys.exit(main())
