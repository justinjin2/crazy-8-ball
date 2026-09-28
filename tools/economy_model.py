#!/usr/bin/env python3
"""Economy model for Crazy 8 Ball (docs/ECONOMY.md is the design; this checks its numbers).

Every number here mirrors a table in docs/ECONOMY.md. Change a number in both places, then run:

    python3 tools/economy_model.py tables   # case odds, money per hour, ranks per division, gap factors
    python3 tools/economy_model.py shop     # the shop's odds and prices, money packs, Robux costs
    python3 tools/economy_model.py loot     # days to a player's first Epic/Legendary/Mythic/Secret
    python3 tools/economy_model.py hours    # the same in hours played, with the spread
    python3 tools/economy_model.py supply   # cues entering the game per day at 500 / 2k / 10k CCU
    python3 tools/economy_model.py ranks    # a year of players on the rank ladder (a few minutes)

Nothing here runs in the game. It is a calculator so the designer can re-tune with evidence.
"""

import argparse
import math
import random
import statistics

import numpy as np

# ------------------------------------------------------------------------------------------
# Match pace and pay (docs/ECONOMY.md section 2)
# ------------------------------------------------------------------------------------------
MATCH_MINUTES = {"Classic": 6.5, "Difficult": 7.5, "Challenger": 8.5}  # break to last ball
BETWEEN_MATCH_MINUTES = 1.5  # end screen, rematch, walking to a pad

BALL_PAY = 10
NICE_SHOT_PAY = 17.5  # average of bank/kick $15 and combo/carom $20
WIN_BONUS = 50
LOSS_BONUS = 15
# Average balls that pay the shooter in one 1v1 match (winner pots its 7 and the 8 most of the
# time; some wins come from the other side's foul on the 8). Checked against playtests later.
WINNER_BALLS, LOSER_BALLS = 7.5, 4.0
WINNER_NICE, LOSER_NICE = 0.5, 0.3
MONEY_MULT = {"Classic": 1.0, "Difficult": 1.5, "Challenger": 2.0}

# ------------------------------------------------------------------------------------------
# Cases (section 4). Odds in percent, each row sums to exactly 100.
# ------------------------------------------------------------------------------------------
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]

CASES = {
    "Standard": {
        "price": 150,
        "odds": {
            "Common": 64.3,
            "Uncommon": 26.0,
            "Rare": 8.4,
            "Epic": 1.0,
            "Legendary": 0.25,
            "Mythic": 0.047,
            "Secret": 0.003,
        },
    },
    "Rare": {
        "price": 500,
        "odds": {"Uncommon": 62.5, "Rare": 31.0, "Epic": 5.5, "Legendary": 0.85, "Mythic": 0.14, "Secret": 0.01},
    },
    "Epic": {
        "price": 1500,
        "odds": {"Rare": 73.4, "Epic": 22.0, "Legendary": 4.0, "Mythic": 0.56, "Secret": 0.04},
    },
    "Legendary": {
        "price": 5000,
        "odds": {"Epic": 76.5, "Legendary": 20.0, "Mythic": 3.25, "Secret": 0.25},
    },
}

# Sell-back money per rarity (section 5). Always well under what the rarity costs to roll.
SELL = {"Common": 15, "Uncommon": 40, "Rare": 120, "Epic": 600, "Legendary": 3000, "Mythic": 15000, "Secret": 75000}

# ------------------------------------------------------------------------------------------
# Free rewards (sections 4, 7, 8)
# ------------------------------------------------------------------------------------------
FIRST_WIN_CASE = "Rare"  # the very first win's reveal (GDD section 14)
NEW_PLAYER_CASE_WINS = 50  # the first 50 wins ever each drop a free Standard Case
DAILY_CASE_WINS = 10  # after that: the first 10 wins each day drop one...
LATE_CASE_EVERY = 2  # ...then every 2nd win

# 7-day login streak: (money, [cases]) per day. Finishing 4 weeks in a row adds a Legendary Case.
STREAK = [
    (250, []),
    (0, ["Standard", "Standard"]),
    (500, []),
    (0, ["Rare"]),
    (1000, []),
    (0, ["Rare", "Rare"]),
    (0, ["Epic"]),
]
STREAK_MONTH_BONUS = ["Legendary"]
# Playtime gifts, once per day, by minutes played that day: (minutes, money, [cases]).
PLAYTIME_GIFTS = [(10, 100, []), (30, 0, ["Standard"]), (60, 0, ["Standard", "Standard"])]

# ------------------------------------------------------------------------------------------
# Rank XP (section 4). One bar, no Levels. XP is never lost; from Diamond a loss gives nothing.
# ------------------------------------------------------------------------------------------
TIERS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Expert", "Veteran", "Master", "Grandmaster"]
# XP to fill each division, I to V. Flat and quick to Platinum, then about 17% more each
# division from Diamond I, so the climb keeps getting longer. Reyes starts where Grandmaster V ends.
DIV_WIDTHS = {
    "Bronze": [250, 250, 250, 250, 250],
    "Silver": [350, 350, 350, 350, 350],
    "Gold": [800, 800, 800, 800, 800],
    "Platinum": [1200, 1200, 1200, 1200, 1200],
    "Diamond": [8000, 9500, 11000, 13000, 15000],
    "Expert": [17500, 20500, 24000, 28000, 33000],
    "Veteran": [38000, 45000, 53000, 62000, 72000],
    "Master": [85000, 100000, 115000, 135000, 160000],
    "Grandmaster": [185000, 215000, 255000, 295000, 345000],
}
# XP for a Classic win and loss against an equal opponent, before the mode multiplier.
BASE_XP = {
    "Bronze": (250, 100),
    "Silver": (250, 75),
    "Gold": (250, 50),
    "Platinum": (250, 25),
    "Diamond": (250, 0),
    "Expert": (450, 0),
    "Veteran": (450, 0),
    "Master": (450, 0),
    "Grandmaster": (450, 0),
    "Reyes": (450, 0),
}
MODE_XP_MULT = {"Classic": 1.0, "Difficult": 1.25, "Challenger": 1.5}
# Classic fades: its wins are worth this share from Diamond and from Expert.
CLASSIC_WIN_FACTOR = {"Diamond": 0.5, "Expert": 0.2, "Veteran": 0.2, "Master": 0.2, "Grandmaster": 0.2, "Reyes": 0.2}
WIN_STREAK_FROM, WIN_STREAK_BONUS = 3, 0.25  # from the 3rd win in a row, each win +25%
# The opponent-gap factor's logistic scale (divisions) and the least a win can be worth.
GAP_SCALE_LOW, GAP_FLOOR_LOW = 12.0, 0.3  # Bronze to Diamond
GAP_SCALE, GAP_FLOOR = 8.0, 0.1  # Expert and up
# PC XP share: Bronze-Diamond / Expert and up (launch; Expert+ drops to 0.1 once the global
# queue exists).
PC_XP_MULT_LOW, PC_XP_MULT_HIGH = 0.75, 0.5
# XP boosts, which add together: Rookie (first 25 matches), VIP, the first win of the UTC day.
ROOKIE_MATCHES, ROOKIE_BOOST = 25, 1.0
VIP_XP_BOOST = 0.5
FIRST_WIN_OF_DAY_BOOST = 1.0

# Where each division starts: DIV_START[i] is division i+1 (1 = Bronze I ... 45 = Grandmaster V);
# the last entry is where Reyes starts.
DIV_START = [0]
for _t in TIERS:
    for _w in DIV_WIDTHS[_t]:
        DIV_START.append(DIV_START[-1] + _w)
REYES_XP = DIV_START[-1]
DIV_START = DIV_START[:-1]


def division_of(xp):
    """1..45 by XP (Bronze I ... Grandmaster V), 46 = Reyes."""
    if xp >= REYES_XP:
        return 46
    lo, hi = 0, len(DIV_START) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if DIV_START[mid] <= xp:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


def tier_of_div(div):
    if div >= 46:
        return "Reyes"
    return TIERS[(div - 1) // 5]


def gap_factor(gap, my_div=45):
    """gap = my division - opponent division. The share of a win's XP (and of a loss's small gain)."""
    scale, floor = (GAP_SCALE_LOW, GAP_FLOOR_LOW) if my_div <= 25 else (GAP_SCALE, GAP_FLOOR)
    e = 1.0 / (1.0 + 10 ** (-gap / scale))
    return min(max(2 * (1 - e), floor), 1.5)


def xp_change(xp, won, mode, opp_div, vs_pc=False, streak=0, boost=0.0):
    """XP after one match. `streak` counts this win if won; `boost` is the sum of active boosts."""
    div = division_of(xp)
    tier = tier_of_div(div)
    w, l = BASE_XP[tier]
    f = gap_factor(div - opp_div, div)
    if won:
        delta = w * MODE_XP_MULT[mode] * f
        if mode == "Classic":
            delta *= CLASSIC_WIN_FACTOR.get(tier, 1.0)
        if streak >= WIN_STREAK_FROM:
            delta *= 1 + WIN_STREAK_BONUS
    else:
        delta = l * MODE_XP_MULT[mode] * min(f, 1.0)
    if vs_pc:
        delta *= PC_XP_MULT_HIGH if div > 25 else PC_XP_MULT_LOW
    return xp + delta * (1 + boost)


# Money paid the first time you reach each division (II to V), and each new tier's reward.
# The old Level money moved here (designer, 2026-09-28).
DIV_REWARD = {
    "Bronze": 50,
    "Silver": 75,
    "Gold": 150,
    "Platinum": 250,
    "Diamond": 1500,
    "Expert": 3000,
    "Veteran": 5000,
    "Master": 8000,
    "Grandmaster": 15000,
}
TIER_REWARD = {  # money, cases (the tier cue and chat tag are not modelled)
    "Bronze": (100, ["Standard", "Standard"]),
    "Silver": (300, ["Rare"]),
    "Gold": (600, ["Rare", "Rare"]),
    "Platinum": (1200, ["Epic"]),
    "Diamond": (3000, ["Epic", "Epic"]),
    "Expert": (10000, ["Legendary", "Legendary"]),
    "Veteran": (15000, ["Legendary"] * 3),
    "Master": (25000, ["Legendary"] * 5),
    "Grandmaster": (50000, ["Legendary"] * 10),
    "Reyes": (150000, ["Legendary"] * 25),
}


def typical_mode(div, rng):
    """What a typical player picks at their rank (unlocks: Difficult at Gold, Challenger at Diamond)."""
    tier = tier_of_div(div)
    r = rng.random()
    if tier in ("Bronze", "Silver"):
        return "Classic"
    if tier == "Gold":
        return "Difficult" if r < 0.3 else "Classic"
    if tier == "Platinum":
        return "Difficult" if r < 0.5 else "Classic"
    return "Challenger" if r < 0.6 else ("Difficult" if r < 0.9 else "Classic")


# ------------------------------------------------------------------------------------------
# Loot model: one player at a time, day by day
# ------------------------------------------------------------------------------------------
def open_case(name, rng):
    roll = rng.random() * 100
    acc = 0.0
    for rarity, pct in CASES[name]["odds"].items():
        acc += pct
        if roll < acc:
            return rarity
    return list(CASES[name]["odds"])[-1]


def simulate_player(minutes_per_day, days, strategy, vip, win_rate, rng):
    """Returns hours played when the player first owned each rarity, plus totals."""
    first = {}
    hours = 0.0
    money = 0.0
    earned = 0.0
    rp = 0.0
    peak_div = 0
    streak = 0
    wins_total = 0
    matches_total = 0
    owned_counts = {r: 0 for r in RARITIES}
    pending_cases = []

    def gain(rarity):
        owned_counts[rarity] += 1
        if rarity not in first:
            first[rarity] = hours
        # Players sell most duplicate commons and uncommons (section 5).
        nonlocal money
        if rarity in ("Common", "Uncommon") and owned_counts[rarity] > 1 and rng.random() < 0.8:
            money += SELL[rarity]

    for day in range(days):
        minutes_left = minutes_per_day * rng.uniform(0.7, 1.3)
        played_today = 0.0
        wins_today = 0
        first_win_done = False
        while True:
            mode = typical_mode(max(peak_div, 1), rng) if peak_div else "Classic"
            length = MATCH_MINUTES[mode] + BETWEEN_MATCH_MINUTES
            if minutes_left < length:
                break
            minutes_left -= length
            played_today += length
            hours += length / 60
            won = rng.random() < win_rate
            mult = MONEY_MULT[mode] * (2 if vip else 1)
            if won:
                pay = (WINNER_BALLS * BALL_PAY + WINNER_NICE * NICE_SHOT_PAY + WIN_BONUS) * mult
            else:
                pay = (LOSER_BALLS * BALL_PAY + LOSER_NICE * NICE_SHOT_PAY + LOSS_BONUS) * mult
            money += pay
            earned += pay
            matches_total += 1
            streak = streak + 1 if won else 0
            # Free case for the winner (section 4.2)
            if won:
                wins_total += 1
                wins_today += 1
                if wins_total == 1:
                    pending_cases.append(FIRST_WIN_CASE)  # the first win's reveal (GDD section 14)
                elif wins_total <= NEW_PLAYER_CASE_WINS or wins_today <= DAILY_CASE_WINS:
                    pending_cases.append("Standard")
                elif (wins_today - DAILY_CASE_WINS) % LATE_CASE_EVERY == 0:
                    pending_cases.append("Standard")
            # Rank (an equal opponent, so no gap)
            if peak_div == 0:
                rp = 0.0
                new_div = 1
            else:
                boost = (ROOKIE_BOOST if matches_total <= ROOKIE_MATCHES else 0) + (VIP_XP_BOOST if vip else 0)
                if won and not first_win_done:
                    boost += FIRST_WIN_OF_DAY_BOOST
                rp = xp_change(rp, won, mode, division_of(rp), streak=streak, boost=boost)
                new_div = division_of(rp)
            if won:
                first_win_done = True
            while peak_div < new_div:
                peak_div += 1
                tier = tier_of_div(peak_div)
                if (peak_div - 1) % 5 == 0:
                    m, cs = TIER_REWARD[tier]
                    money += m
                    pending_cases += cs
                else:
                    money += DIV_REWARD[tier]
        # Daily rewards (the streak never breaks in this model)
        s_money, s_cases = STREAK[day % 7]
        money += s_money
        pending_cases += s_cases
        if day % 28 == 27:
            pending_cases += STREAK_MONTH_BONUS
        for mins, m, cases in PLAYTIME_GIFTS:
            if played_today >= mins:
                money += m
                pending_cases += cases
        # Open every free case, then spend money by strategy
        for c in pending_cases:
            gain(open_case(c, rng))
        pending_cases = []
        if strategy != "save":
            buy = {"standard": "Standard", "rare": "Rare", "epic": "Epic", "legendary": "Legendary"}[strategy]
            while money >= CASES[buy]["price"]:
                money -= CASES[buy]["price"]
                gain(open_case(buy, rng))
    return first, hours, earned, owned_counts, peak_div


def loot_report(runs=1500, days=365, seed=7):
    rng = random.Random(seed)
    profiles = [
        ("Casual 30 min/day", 30, False),
        ("Regular 1 h/day", 60, False),
        ("Regular 1 h/day + VIP", 60, True),
        ("Dedicated 3 h/day", 180, False),
    ]
    strategies = ["epic", "legendary", "rare", "save"]
    print("Median DAYS to first of each rarity (50% win rate, streak never missed)\n")
    print(f"{'profile':28s}{'buys':11s}" + "".join(f"{r:>10s}" for r in ["Epic", "Legendary", "Mythic", "Secret"]))
    for label, mins, vip in profiles:
        for strat in strategies:
            per = {r: [] for r in ["Epic", "Legendary", "Mythic", "Secret"]}
            for _ in range(runs):
                first, hours, *_ = simulate_player(mins, days, strat, vip, 0.5, rng)
                for r in per:
                    per[r].append(first[r] / (mins / 60) if r in first else float("inf"))
            cells = []
            for r in per:
                med = statistics.median(per[r])
                cells.append(f"{med:9.1f}d" if med != float("inf") else f"{'>' + str(days):>9s}d")
            print(f"{label:28s}{strat:11s}" + "".join(f"{c:>10s}" for c in cells))
        print()


def loot_hours(runs=1500, days=365, seed=11):
    """Median HOURS played to each first, the way the designer's targets are written."""
    rng = random.Random(seed)
    print("Median HOURS played to first (1 h/day, buys Epic Cases) and the share who have one by then\n")
    per = {r: [] for r in ["Epic", "Legendary", "Mythic", "Secret"]}
    for _ in range(runs):
        first, *_ = simulate_player(60, days, "epic", False, 0.5, rng)
        for r in per:
            per[r].append(first.get(r, float("inf")))
    for r, xs in per.items():
        xs.sort()
        q = lambda p: xs[int(p * (len(xs) - 1))]
        print(f"  {r:10s} p25 {q(0.25):6.1f} h   median {q(0.5):6.1f} h   p75 {q(0.75):6.1f} h")
    print()


# ------------------------------------------------------------------------------------------
# Tables for the doc
# ------------------------------------------------------------------------------------------
# The Limited shelf (section 9): exclusive cues sold for a set time, then trade-only. Money price.
LIMITED_TIERS = [("Limited", 25000), ("Limited Deluxe", 75000), ("Limited Grand", 250000)]
# Money packs for Robux (section 9): (Robux, money).
PACKS = [(49, 900), (99, 1950), (249, 5250), (499, 11000), (999, 23500), (2499, 62500), (4999, 130000)]


def shop_and_packs():
    base = PACKS[0][1] / PACKS[0][0]
    print("Money packs\n")
    for rbx, money in PACKS:
        print(f"  {rbx:>5} R$  ${money:>8,}  ${money / rbx:5.1f} per R$  bonus +{(money / rbx / base - 1) * 100:3.0f}%")
    print()
    per_rbx = PACKS[-1][1] / PACKS[-1][0]
    print("What things cost in Robux at the best pack rate and at the smallest pack's rate\n")
    per_hour = {"Classic 1 h/day": 728, "Challenger 3 h/day": 1164 * 3}
    for label, dollars in [("Standard Case", 150), ("Legendary Case", 5000)] + LIMITED_TIERS:
        days = "  ".join(f"{k}: {dollars / v:5.0f} days" for k, v in per_hour.items())
        print(f"  {label:15s} ${dollars:>9,}  ~{dollars / per_rbx:7,.0f} R$ best  ~{dollars / base:7,.0f} R$ smallest  {days}")


def supply_per_day(runs=300, days=120, seed=5):
    """New cues of each rarity per hour played, averaged over a regular player's first months,
    scaled to game-wide supply at a few sizes (about 24 player-hours a day per peak-CCU point / 2)."""
    rng = random.Random(seed)
    totals = {r: 0 for r in RARITIES}
    hours_total = 0.0
    for _ in range(runs):
        first, hours, earned, owned, *_ = simulate_player(60, days, "epic", False, 0.5, rng)
        for r in RARITIES:
            totals[r] += owned[r]
        hours_total += hours
    print("Cues entering the game per hour played, and per day at a given peak CCU\n")
    print(f"  {'rarity':10s} {'per hour':>9s} {'500 CCU':>9s} {'2k CCU':>9s} {'10k CCU':>9s}")
    for r in RARITIES:
        rate = totals[r] / hours_total
        # player-hours a day = average CCU x 24, and average CCU is about half the peak.
        cells = [rate * ccu * 0.5 * 24 for ccu in (500, 2000, 10000)]
        print(f"  {r:10s} {rate:9.4f} " + " ".join(f"{c:9,.0f}" for c in cells))


def tables():
    print("Case odds check (each must sum to 100) and money per rarity from each case\n")
    for name, c in CASES.items():
        total = sum(c["odds"].values())
        ev_sell = sum(SELL[r] * p / 100 for r, p in c["odds"].items())
        per = {r: c["price"] / (c["odds"].get(r, 0) / 100) if c["odds"].get(r) else None for r in RARITIES[3:]}
        print(
            f"  {name:10s} ${c['price']:>5}  sum {total:7.3f}  sell-back EV ${ev_sell:7.1f} "
            f"({ev_sell / c['price'] * 100:4.0f}% of price)  "
            + "  ".join(f"{r[:3]} ${v:>9,.0f}" for r, v in per.items() if v)
        )
    print()
    for mode in ("Classic", "Difficult", "Challenger"):
        cycle = MATCH_MINUTES[mode] + BETWEEN_MATCH_MINUTES
        per_match = 0.5 * (WINNER_BALLS * BALL_PAY + WINNER_NICE * NICE_SHOT_PAY + WIN_BONUS) + 0.5 * (
            LOSER_BALLS * BALL_PAY + LOSER_NICE * NICE_SHOT_PAY + LOSS_BONUS
        )
        per_match *= MONEY_MULT[mode]
        print(f"  {mode:10s} {60 / cycle:4.1f} matches/h, ${per_match:6.1f}/match, ${per_match * 60 / cycle:7.0f}/h")
    print()
    print("Rank XP: each tier's divisions, and hours to reach each tier at a win rate\n")
    for tier in TIERS:
        print(f"  {tier:12s} {DIV_WIDTHS[tier]}  total {sum(DIV_WIDTHS[tier]):>9,}")
    print(f"  Reyes at {REYES_XP:,} XP\n")
    print(ladder_hours_table())
    print("\nOpponent-gap factor on a win (gap in divisions; + means you are higher)\n")
    for label, d in (("Bronze to Diamond", 20), ("Expert and up", 30)):
        cells = "  ".join(f"{g:+d}: x{gap_factor(g, d):4.2f}" for g in (-5, -3, -1, 0, 1, 3, 5, 8, 10, 15))
        print(f"  {label:18s} {cells}")


MODE_MIX = {
    "Bronze": {"Classic": 1.0},
    "Silver": {"Classic": 1.0},
    "Gold": {"Classic": 0.7, "Difficult": 0.3},
    "Platinum": {"Classic": 0.5, "Difficult": 0.5},
}
HIGH_MIX = {"Challenger": 0.6, "Difficult": 0.3, "Classic": 0.1}


def ladder_hours(p):
    """Hours of play to reach each tier against equal opponents at win rate p (typical mode mix)."""
    out, h = {}, 0.0
    for tier in TIERS:
        out[tier] = h
        w, l = BASE_XP[tier]
        ev = mins = 0.0
        for mode, f in MODE_MIX.get(tier, HIGH_MIX).items():
            ww = w * MODE_XP_MULT[mode] * (CLASSIC_WIN_FACTOR.get(tier, 1.0) if mode == "Classic" else 1.0)
            ww *= 1 + WIN_STREAK_BONUS * p * p  # share of wins that are 3rd-or-later in a row
            ev += f * (p * ww + (1 - p) * l * MODE_XP_MULT[mode])
            mins += f * (MATCH_MINUTES[mode] + BETWEEN_MATCH_MINUTES)
        h += sum(DIV_WIDTHS[tier]) / ev * mins / 60
    out["Reyes"] = h
    return out


def ladder_hours_table():
    names = TIERS[1:] + ["Reyes"]
    lines = ["  win rate " + "".join(f"{t[:6]:>8s}" for t in names)]
    for p in (0.45, 0.5, 0.55, 0.6):
        hs = ladder_hours(p)
        lines.append(f"  {int(p * 100):3d}%     " + "".join(f"{hs[t]:7.0f}h" for t in names))
    return "\n".join(lines)


# ------------------------------------------------------------------------------------------
# Population simulation of the ladder (section 3.9)
# ------------------------------------------------------------------------------------------
def rank_sim(days=365, new_per_day=2000, seed=3, report_days=(90, 180, 365)):
    rng = np.random.default_rng(seed)
    pyrng = random.Random(seed)
    # Per player: skill, minutes a day when active, how many days they stay, join day, XP, streak.
    skill, minutes, life, joined, xp_list, streak_list = [], [], [], [], [], []
    k_mode = {"Classic": 1.0, "Difficult": 1.3, "Challenger": 1.6}
    results = {}
    for day in range(days):
        # Arrivals: lifetime in days is heavy-tailed (most leave on day 1, a few stay for a year+).
        n = new_per_day
        skill += list(rng.normal(0, 1, n))
        lt = np.minimum(rng.pareto(0.9, n) * 2 + 1, 800).astype(int)
        life += list(lt)
        # Minutes per active day: median 25, long tail; players who stay longer tend to play more.
        minutes += list(np.minimum(rng.lognormal(math.log(25), 0.8, n) * (1 + np.log1p(lt) / 3), 360))
        joined += [day] * n
        xp_list += [-1.0] * n
        streak_list += [0] * n
        sk = np.array(skill)
        age = day - np.array(joined)
        active = (age < np.array(life)) & (rng.random(len(sk)) < 0.7)
        idx = np.nonzero(active)[0]
        mins = np.array(minutes)[idx]
        avg_ccu = mins.sum() / 1440.0  # players online on average today
        n_matches = (mins / 9.0).astype(int)
        xps = np.array(xp_list)
        streaks = np.array(streak_list)
        for r in range(int(n_matches.max()) if len(idx) else 0):
            players = idx[n_matches > r]
            if len(players) < 2:
                break
            # Half the matches are with whoever is at the next table and half with players near
            # your rank (the pro lobby, friends, difficulty locks); Diamond and up 80% near-rank.
            divs = np.array([division_of(max(xps[p], 0)) for p in players], dtype=float)
            wants_near = rng.random(len(players)) < np.where(divs >= 21, 0.8, 0.5)
            near_players = players[wants_near]
            near_players = near_players[np.argsort(divs[wants_near] + rng.normal(0, 2, wants_near.sum()))]
            order = np.concatenate([near_players, rng.permutation(players[~wants_near])])
            for a, b in zip(order[0::2], order[1::2]):
                xa, xb = xps[a], xps[b]
                if xa < 0 or xb < 0:  # the tutorial: Unranked to Bronze I
                    xps[a] = max(xa, 0.0)
                    xps[b] = max(xb, 0.0)
                    continue
                da, db = division_of(xa), division_of(xb)
                mode = typical_mode(max(da, db), pyrng)
                p_a = 1 / (1 + math.exp(-k_mode[mode] * (sk[a] - sk[b])))
                a_won = pyrng.random() < p_a
                streaks[a] = streaks[a] + 1 if a_won else 0
                streaks[b] = 0 if a_won else streaks[b] + 1
                xps[a] = xp_change(xa, a_won, mode, db, streak=streaks[a])
                xps[b] = xp_change(xb, not a_won, mode, da, streak=streaks[b])
        xp_list = list(xps)
        streak_list = list(streaks)
        if day + 1 in report_days:
            alive = (age < np.array(life)) & (xps >= 0)
            ever = xps >= 0
            results[day + 1] = (alive, ever, sk, xps, avg_ccu)
    for d, (alive, ever, sks, xpv, avg_ccu) in results.items():
        peak = avg_ccu * 2  # peak is roughly twice the daily average on Roblox (assumption)
        tiers = np.array([tier_of_div(division_of(x)) if x >= 0 else "-" for x in xpv])
        print(f"Day {d}: {alive.sum():,} ranked players still playing, about {peak:,.0f} peak CCU")
        print(f"  {'tier':12s} {'playing':>8s} {'share':>7s} {'per 1k CCU':>11s} {'ever reached':>13s} {'mean skill':>11s}")
        order_ = TIERS + ["Reyes"]
        for t in order_:
            here = alive & (tiers == t)
            at_or_above = ever & np.isin(tiers, order_[order_.index(t):])
            c = int(here.sum())
            ms = f"{sks[here].mean():+.2f}" if c else "   -"
            print(f"  {t:12s} {c:8d} {c / alive.sum() * 100:6.2f}% {c / peak * 1000:11.1f} {int(at_or_above.sum()):13d} {ms:>11s}")
        print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", choices=["loot", "ranks", "tables", "hours", "shop", "supply"])
    ap.add_argument("--runs", type=int, default=1500)
    ap.add_argument("--days", type=int, default=365)
    args = ap.parse_args()
    if args.what == "loot":
        loot_report(runs=args.runs, days=args.days)
    elif args.what == "hours":
        loot_hours(runs=args.runs, days=args.days)
    elif args.what == "tables":
        tables()
    elif args.what == "shop":
        shop_and_packs()
    elif args.what == "supply":
        supply_per_day()
    else:
        rank_sim(days=args.days)


if __name__ == "__main__":
    main()
