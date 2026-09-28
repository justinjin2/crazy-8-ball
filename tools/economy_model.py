#!/usr/bin/env python3
"""Economy model for Crazy 8 Ball (docs/ECONOMY.md is the design; this checks its numbers).

Every number here mirrors a table in docs/ECONOMY.md. Change a number in both places, then run:

    python3 tools/economy_model.py tables   # case odds, money per hour, ranks per division, gap factors
    python3 tools/economy_model.py shop     # the shop's odds and prices, money packs, Robux costs
    python3 tools/economy_model.py loot     # days to a player's first Epic/Legendary/Mythic/Secret
    python3 tools/economy_model.py hours    # the same in hours played, with the spread
    python3 tools/economy_model.py supply   # cues entering the game per day at 500 / 2k / 10k CCU
    python3 tools/economy_model.py ranks    # population simulation of the rank ladder (about a minute)

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

# Account Level (section 8): EXP to go from level L to L+1.
def exp_to_next(level):
    return min(100 + 75 * (level - 1), 5000)


WIN_EXP, LOSS_EXP, FIRST_WIN_OF_DAY_EXP = 100, 50, 200
ROOKIE_MATCHES = 25  # a new player's first 25 matches earn +100% EXP (adds to VIP's +100%)
EXP_MULT = {"Classic": 1.0, "Difficult": 1.25, "Challenger": 1.5}


def level_reward(level):
    """Money and cases for reaching `level` (section 8)."""
    # Money only, never cases: VIP's 2x EXP speeds levels up, and a free case that a purchase
    # can speed up would count as a paid random item (Roblox policy, section 10).
    money = min(50 + 10 * level, 1000)
    if level % 10 == 0:
        money += 25 * level  # milestone levels pay extra (and a cosmetic title, not modelled)
    return money, []


# ------------------------------------------------------------------------------------------
# Ranks (section 3)
# ------------------------------------------------------------------------------------------
TIERS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Expert", "Veteran", "Master"]
DIV_WIDTH = {
    "Bronze": 250,
    "Silver": 350,
    "Gold": 800,
    "Platinum": 1000,
    "Diamond": 4000,
    "Expert": 1500,
    "Veteran": 2000,
    "Master": 2000,
}
# RP against an equal opponent in Classic, before the mode multiplier: (win, loss).
BASE_RP = {
    "Bronze": (250, 100),
    "Silver": (250, 75),
    "Gold": (250, 50),
    "Platinum": (250, 0),
    "Diamond": (200, -100),
    "Expert": (150, -115),
    "Veteran": (150, -115),
    "Master": (150, -115),
    "Grandmaster": (150, -115),
}
MODE_RP_MULT = {"Classic": 1.0, "Difficult": 1.25, "Challenger": 1.5}
# Classic's diminishing returns: a factor on Classic WINS by tier (Expert and up: on losses too).
CLASSIC_WIN_FACTOR = {"Diamond": 0.5, "Expert": 0.2, "Veteran": 0.2, "Master": 0.2, "Grandmaster": 0.2}
CLASSIC_LOSS_FACTOR = {"Expert": 0.2, "Veteran": 0.2, "Master": 0.2, "Grandmaster": 0.2}
GAP_SCALE = 8.0  # divisions: the logistic's scale for the opponent-gap factor
PC_RP_MULT_LOW, PC_RP_MULT_HIGH = 0.5, 0.5  # Bronze-Diamond / Expert and up (launch; 0.1 once the global queue exists)

# Cumulative RP where each division starts. Division index 1 = Bronze I ... 40 = Master V.
DIV_START = [0]
for _t in TIERS:
    for _d in range(5):
        DIV_START.append(DIV_START[-1] + DIV_WIDTH[_t])
# Reaching Master V makes a player eligible for the Grandmaster/Reyes leaderboard (section 3.5).
GM_THRESHOLD = DIV_START[39]
DIV_START = DIV_START[:40]  # DIV_START[i] is where division i+1 starts


def division_of(rp):
    """1..40 by RP, 41+ above the Grandmaster threshold (one per 2,500 RP, for the gap only)."""
    if rp >= GM_THRESHOLD + DIV_WIDTH["Master"]:
        return 41 + int((rp - GM_THRESHOLD - DIV_WIDTH["Master"]) // 2000)
    lo, hi = 0, 39
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if DIV_START[mid] <= rp:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


def tier_of_div(div):
    if div > 40:
        return "Grandmaster"
    return TIERS[(div - 1) // 5]


def floor_rp(div):
    """Where a loss stops (section 3): Bronze to Expert never fall out of their tier.
    Veteran and up can fall a tier (the 3-loss shield is ignored in the population sim)."""
    tier_index = (min(div, 40) - 1) // 5
    tier = TIERS[tier_index]
    if tier in ("Veteran", "Master") or div > 40:
        return DIV_START[25]  # Expert I is the lowest a high player can fall
    return DIV_START[tier_index * 5]


def gap_factors(gap):
    """gap = my division - opponent division. Returns (win factor, gain-on-loss factor, loss factor)."""
    e = 1.0 / (1.0 + 10 ** (-gap / GAP_SCALE))
    win = min(max(2 * (1 - e), 0.1), 1.5)
    return win, min(win, 1.0), min(max(2 * e, 0.5), 1.5)


def rp_change(rp, won, mode, opp_div, vs_pc=False):
    div = division_of(rp)
    tier = tier_of_div(div)
    w, l = BASE_RP[tier]
    m = MODE_RP_MULT[mode]
    win_f, pos_loss_f, neg_loss_f = gap_factors(div - opp_div)
    if won:
        delta = w * m * win_f
        if mode == "Classic":
            delta *= CLASSIC_WIN_FACTOR.get(tier, 1.0)
    else:
        if l >= 0:
            delta = l * m * pos_loss_f
        else:
            delta = l * m * neg_loss_f
            if mode == "Classic":
                delta *= CLASSIC_LOSS_FACTOR.get(tier, 1.0)
    if vs_pc:
        delta *= PC_RP_MULT_HIGH if div > 25 else PC_RP_MULT_LOW
    new = rp + delta
    if delta < 0:
        new = max(new, floor_rp(div))
    return new


# Money paid the first time the peak reaches a division (section 3.6).
DIV_REWARD = {
    "Bronze": 50,
    "Silver": 75,
    "Gold": 150,
    "Platinum": 250,
    "Diamond": 600,
    "Expert": 1500,
    "Veteran": 2500,
    "Master": 4000,
}
TIER_REWARD = {  # money, cases (the tier cue and chat tag are not modelled)
    "Bronze": (100, ["Standard", "Standard"]),
    "Silver": (300, ["Rare"]),
    "Gold": (600, ["Rare", "Rare"]),
    "Platinum": (1200, ["Epic"]),
    "Diamond": (3000, ["Legendary"]),
    "Expert": (10000, ["Legendary", "Legendary"]),
    "Veteran": (15000, ["Legendary"] * 3),
    "Master": (25000, ["Legendary"] * 5),
    "Grandmaster": (50000, ["Legendary"] * 10),
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
    level, exp = 1, 0
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
            # EXP
            e = (WIN_EXP if won else LOSS_EXP) * EXP_MULT[mode]
            if won and not first_win_done:
                e += FIRST_WIN_OF_DAY_EXP
                first_win_done = True
            matches_total += 1
            exp += e * (1 + (1 if vip else 0) + (1 if matches_total <= ROOKIE_MATCHES else 0))
            while exp >= exp_to_next(level):
                exp -= exp_to_next(level)
                level += 1
                m, cs = level_reward(level)
                money += m
                pending_cases += cs
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
                rp = rp_change(rp, won, mode, division_of(rp))
                new_div = division_of(rp)
            while peak_div < min(new_div, 41):
                peak_div += 1
                tier = tier_of_div(peak_div)
                if (peak_div - 1) % 5 == 0 or peak_div == 41:
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
    return first, hours, earned, owned_counts, peak_div, level


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
    print("Rank ladder: matches per division against equal opponents (50% and 60% win rate)\n")
    for tier in TIERS:
        w, l = BASE_RP[tier]
        row = []
        for mode in ("Classic", "Difficult", "Challenger"):
            m = MODE_RP_MULT[mode]
            ww = w * m * (CLASSIC_WIN_FACTOR.get(tier, 1.0) if mode == "Classic" else 1.0)
            ll = l * m * (CLASSIC_LOSS_FACTOR.get(tier, 1.0) if mode == "Classic" and l < 0 else 1.0)
            for p in (0.5, 0.6):
                ev = p * ww + (1 - p) * ll
                row.append(f"{DIV_WIDTH[tier] / ev:6.1f}" if ev > 0 else "   n/a")
        print(f"  {tier:10s} width {DIV_WIDTH[tier]:5d}  C {row[0]} {row[1]}   D {row[2]} {row[3]}   Ch {row[4]} {row[5]}")
    print(f"\n  Grandmaster/Reyes leaderboard eligibility at {GM_THRESHOLD:,} RP")
    print("\nOpponent-gap factors (gap in divisions; + means you are higher)\n")
    for g in (-5, -3, -2, -1, 0, 1, 2, 3, 5, 8, 10, 15):
        wf, pl, nl = gap_factors(g)
        print(f"  gap {g:+3d}: win x{wf:4.2f}  small-gain loss x{pl:4.2f}  RP-losing loss x{nl:4.2f}")


# ------------------------------------------------------------------------------------------
# Population simulation of the ladder (section 3.9)
# ------------------------------------------------------------------------------------------
def rank_sim(days=180, new_per_day=4000, seed=3, report_days=(30, 60, 90, 120, 180)):
    rng = np.random.default_rng(seed)
    pyrng = random.Random(seed)
    # Per player: skill, minutes a day when active, how many days they stay, join day.
    skill, minutes, life, joined, rp, alive = [], [], [], [], [], []
    k_mode = {"Classic": 1.0, "Difficult": 1.3, "Challenger": 1.6}
    results = {}
    for day in range(days):
        # Arrivals: lifetime in days is heavy-tailed (most leave on day 1, a few stay for months).
        n = new_per_day
        skill += list(rng.normal(0, 1, n))
        # Minutes per active day: median 25, long tail; players who stay longer tend to play more.
        lt = np.minimum(rng.pareto(0.9, n) * 2 + 1, 400).astype(int)
        life += list(lt)
        minutes += list(np.minimum(rng.lognormal(math.log(25), 0.8, n) * (1 + np.log1p(lt) / 3), 360))
        joined += [day] * n
        rp += [-1.0] * n
        sk = np.array(skill)
        age = day - np.array(joined)
        active = (age < np.array(life)) & (rng.random(len(sk)) < 0.7)
        idx = np.nonzero(active)[0]
        mins = np.array(minutes)[idx]
        avg_ccu = mins.sum() / 1440.0  # players online on average today
        n_matches = (mins / 8.5).astype(int)
        rps = np.array(rp)
        # Unranked players' first match: Bronze I.
        for r in range(int(n_matches.max()) if len(idx) else 0):
            players = idx[n_matches > r]
            if len(players) < 2:
                break
            # Some matches are with whoever is at the next table; the rest are with players near
            # your rank (the pro lobby, friends, difficulty locks). Diamond and up mostly meet
            # near-rank players (80%), everyone else half the time.
            divs = np.array([division_of(max(rps[p], 0)) for p in players], dtype=float)
            wants_near = rng.random(len(players)) < np.where(divs >= 21, 0.8, 0.5)
            near_players = players[wants_near]
            near_players = near_players[np.argsort(divs[wants_near] + rng.normal(0, 2, wants_near.sum()))]
            order = np.concatenate([near_players, rng.permutation(players[~wants_near])])
            for a, b in zip(order[0::2], order[1::2]):
                ra, rb = rps[a], rps[b]
                if ra < 0 or rb < 0:  # tutorial/first match
                    rps[a] = max(ra, 0.0)
                    rps[b] = max(rb, 0.0)
                    continue
                da, db = division_of(ra), division_of(rb)
                mode = typical_mode(max(da, db), pyrng)
                p_a = 1 / (1 + math.exp(-k_mode[mode] * (sk[a] - sk[b])))
                a_won = pyrng.random() < p_a
                rps[a] = rp_change(ra, a_won, mode, db)
                rps[b] = rp_change(rb, not a_won, mode, da)
        rp = list(rps)
        if day + 1 in report_days:
            weekly = (age < np.array(life)) & (age >= 0)
            weekly_idx = np.nonzero(weekly & (rps >= 0))[0]
            counts = {}
            for p in weekly_idx:
                d = division_of(rps[p])
                t = "GM-eligible" if d >= 40 else tier_of_div(d)
                counts[t] = counts.get(t, 0) + 1
            total = len(weekly_idx)
            results[day + 1] = (total, counts, sk[weekly_idx], rps[weekly_idx], avg_ccu)
    order = TIERS + ["GM-eligible"]
    for d, (total, counts, sks, rpv, avg_ccu) in results.items():
        peak = avg_ccu * 2  # peak is roughly twice the daily average on Roblox (assumption)
        print(f"Day {d}: {total:,} ranked players in the population, about {peak:,.0f} peak CCU")
        print(f"  {'tier':12s} {'players':>8s} {'share':>7s} {'per 1k peak CCU':>16s} {'mean skill':>11s}")
        divs = np.array([division_of(x) for x in rpv])
        for t in order:
            c = counts.get(t, 0)
            share = c / total * 100 if total else 0
            if t == "GM-eligible":
                mask = divs >= 40
            else:
                i = TIERS.index(t)
                mask = (divs > i * 5) & (divs <= i * 5 + 5) & (divs < 40)
            ms = f"{sks[mask].mean():+.2f}" if mask.sum() else "   -"
            print(f"  {t:12s} {c:8d} {share:6.2f}% {c / peak * 1000:16.1f} {ms:>11s}")
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
        rank_sim(days=min(args.days, 180))


if __name__ == "__main__":
    main()
