"""Halloween Candy pacing model (hw3-core, retuned 2026-10-29 ~13:00; docs/ECONOMY.md, Halloween).

Minutes of play; one day = one quest board (boards 2-6 after the Oct 29 evening release, the King
off so his quests read as their Alts). Each board's quests are done at their clock minutes (every
quest moves at once while playing, one kind each). Pockets: eligible pots an hour x PerPocket x
the Rush's average (or 2 on Oct 31) x the friends + group boost; ground: a flat rate an hour
(bounded by Config.Halloween.Pickup.HourCap). Sources of each number: docs/ECONOMY.md.
Run: python3 tools/halloween/pacing.py
"""
MIN = {"Matches": 6.3, "Wins": 12.6, "Balls": 6.3 / 5.75, "NiceShots": 18.9, "UltMatches": 12.6,
       "Pickups": 60 / 30, "Active": 1 / 60, "TeamMatches": 8}
REW = [60, 100, 150, 250]
# boards 2..6 with the King off (release reading)
BOARDS = {
    2: [("Matches", 1), ("Wins", 1), ("Balls", 15), ("Active", 3600)],
    3: [("Balls", 8), ("Wins", 1), ("Pickups", 8), ("UltMatches", 4)],
    4: [("Matches", 1), ("Balls", 12), ("Active", 1200), ("Wins", 6)],
    5: [("Balls", 8), ("Wins", 1), ("Matches", 3), ("Pickups", 35)],
    6: [("Matches", 1), ("Wins", 1), ("Balls", 15), ("NiceShots", 5)],
}
PER_POCKET = 3
POTS_H = 60 / 6.3 * 5.75 * 0.85  # eligible pots an hour
RUSH = 1 + 10 / 45  # the personal Rush: 10 of every 45 minutes (Config.Halloween.Rush)
BOOST = 1.05
GROUND_H = 120  # ~30 pickups an hour at 4 Candy a candy (2026-10-29 ~21:40; a spawn every ~20 s, a bag of 38)
DOUBLE_DAY = 3  # day 3 = board 4 (Oct 31 evening EDT)


def pots_per_min(day):
    m = 2 if day == DOUBLE_DAY else RUSH
    return POTS_H * PER_POCKET * m * BOOST / 60


def quest_times(board):
    return [(MIN[k] * n, REW[i]) for i, (k, n) in enumerate(BOARDS[board])]


def run(minutes_per_day, tutorial=0, days=5):
    """Returns list of (cumulative minute of play, cumulative candy, src totals) per minute."""
    total = {"pots": 0.0, "ground": 0.0, "quests": 0.0}
    timeline = []
    t = 0
    for day in range(1, days + 1):
        board = day + 1
        play = minutes_per_day - (tutorial if day == 1 else 0)
        qs = quest_times(board)
        done = [False] * 4
        if day == 1:
            for _ in range(tutorial):
                t += 1
                timeline.append((t, sum(total.values()), dict(total)))
        for m in range(1, int(play) + 1):
            t += 1
            total["pots"] += pots_per_min(day)
            total["ground"] += GROUND_H / 60
            for i, (need, r) in enumerate(qs):
                if not done[i] and m >= need:
                    done[i] = True
                    total["quests"] += r
            timeline.append((t, sum(total.values()), dict(total)))
    return timeline


def when(timeline, amount):
    for t, c, _ in timeline:
        if c >= amount:
            return t
    return None


print("pots/h normal %.0f, Oct 31 %.0f; eligible pots/h %.1f" % (pots_per_min(1) * 60, pots_per_min(3) * 60, POTS_H))
ref = run(180)
print("REFERENCE 3 h/day")
for cue, price in [("Pitchfork", 300), ("Broom", 2500), ("Jack", 4500), ("Sword", 7500)]:
    w = when(ref, price)
    print("  %s %d at %s min (%.1f h)" % (cue, price, w, (w or 0) / 60))
end = ref[-1]
print("  end: %.0f Candy (%s)" % (end[1], {k: round(v) for k, v in end[2].items()}))
for d in range(1, 6):
    _, c, src = ref[d * 180 - 1]
    print("  after day %d (%d h): %.0f  pots %.0f ground %.0f quests %.0f" % (d, d * 3, c, src["pots"], src["ground"], src["quests"]))
new = run(22, tutorial=5)
print("NEW 22 min/day (5 min tutorial on day 1)")
print("  Pitchfork at %s min of play" % when(new, 300))
for d in range(1, 6):
    _, c, src = new[d * 22 - 1]
    print("  after day %d (%d min): %.0f  pots %.0f ground %.0f quests %.0f" % (d, d * 22, c, src["pots"], src["ground"], src["quests"]))
one = run(15, tutorial=5, days=1)
print("  a 15-min first session: %.0f" % one[-1][1])
for mpd in (60,):
    r = run(mpd)
    print("1 h/day: end %.0f; Broom at %s min" % (r[-1][1], when(r, 2500)))
