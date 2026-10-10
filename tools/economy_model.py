#!/usr/bin/env python3
"""Economy model for Crazy 8 Ball (economy v5.1, "every block climbs"): a 60-day player-population
simulation that reads every game number from src/shared/Config.luau (through tools/economy_config.json).

    python3 tools/economy_model.py                # v5.1 at day 7, 30 and 60, against the plan's numbers
    python3 tools/economy_model.py --built-only   # the same without the planned, not yet built features
    python3 tools/economy_model.py --compare      # before v4, v4 (frozen), v5 built only and v5 side by side
    python3 tools/economy_model.py --sell         # v5 with finder's money, the Index rows and selling back
    python3 tools/economy_model.py --retention typical   # a typical Roblox game's retention instead of the plan's
    python3 tools/economy_model.py tables         # odds per block and per Mystery block, money per hour, rank hours
    python3 tools/economy_model.py value          # the Robux value ladder: R$ to pull each rarity, money vs Robux
    python3 tools/economy_model.py players        # reference players: first session ... day 30
    python3 tools/economy_model.py copies         # when each cue's first 100 copies are gone
    python3 tools/economy_model.py exists         # Config.Trade.BlockExists and ClimbedExists at day 30
    python3 tools/economy_model.py ranks          # a year of players on the rank ladder (slow, a few minutes)

Sources modelled: the 10-step daily win track (blocks and money steps; wins 11+ pay money and XP
only), the climb (economy v5: every block climbs from its name on one ladder, Config.BlockOdds.Climb,
with the Grand Opening Luck for its first days; a climbed block gives exactly its tier's rarity,
the Secret climb its cue), the Mystery (economy v5.1: its roll, Config.BlockOdds.Turn, turns it into
an unclimbed block that then climbs; pity with its head start, bought ones too, counted on the cue
it finally gives), the Grand Opening and Starter blocks' own rows, the first week (any 7 login days within 14 of
joining; day 7 the Week One Cue) and the later weeks, the 28-day track, playtime gifts, VIP's daily
block, the group, favorite, invites, launch codes and the first-leave Gift, rank rewards, the
restock shop (money and Robux; slot 1 its own table), the Grand Opening block (window, copy caps,
guarantee), the Starter Pack, money packs and the launch bonus. Config.Planned (the Lucky Shot,
Golden Shot, Lucky Rain and stay bonus) is designed but not built; it is in by default, as in the
approved plan, and --built-only switches it off. --sell adds finder's money, the Index rows'
money and selling duplicates (and the Week One Cue) back, by the ASSUMPTION shares below.

The numbers come from tools/economy_config.json, which tools/export_economy.luau writes from Config
(this script runs it through Lune when the JSON is missing or older than Config). How players
behave is an ASSUMPTION constant below, each with a comment. "before" (--compare) is a frozen copy
of the economy before v4, and "v4" (--compare) is built from tools/economy_config_v4.json, the
exported Config at the last v4 commit (f4e17c0); both are kept only for comparison.

Not modelled: Money Party, timer skips, Limited cues, trading, anti-farm and PC/bot money rules
(sell-back money only with --sell). Nothing here runs in the game. Python 3 standard library only.
"""

import argparse
import bisect
import copy
import json
import math
import random
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_JSON = ROOT / "tools" / "economy_config.json"
CONFIG_V4_JSON = ROOT / "tools" / "economy_config_v4.json"  # frozen: Config at f4e17c0, for --compare
EXPORTER = "tools/export_economy.luau"
SOURCES_LUAU = [ROOT / "src/shared/Config.luau", ROOT / "src/shared/Progression/Catalog.luau", ROOT / EXPORTER]

RAR = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
# The climb ladder (economy v5): the six block tiers and the Secret on top (no Secret block: a
# climb that reaches it gives the Secret cue, its own row below).
TIERS = ["Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
OUTS = RAR + ["Firework", "Beta"]
UNIQUES = {"FireworkCue": "Firework", "BetaCue": "Beta"}  # the Grand Opening's numbered cues, as outcomes
CUES = {}  # cues of each rarity that can drop (filled from Config)

# ------------------------------------------------------------------------------------------------
# Population ASSUMPTIONS (the approved plans' model; v4 ones marked)
# ------------------------------------------------------------------------------------------------
SEED, DAYS, SAMPLE = 1, 60, 1.0
REPORT = (7, 30, 60)
ARRIVALS_DAY0, ARRIVAL_GROWTH, GROWTH_DAYS = 1700, 1.055, 40  # ~500 peak CCU week 1, ~5k by day 45-60
ONE_DAY_SHARE = 0.55  # play one day and never return
LIFE_MIN, LIFE_SHAPE, LIFE_SCALE, LIFE_CAP = 2, 0.75, 3, 2000  # the rest: 2 + Lomax(0.75) x 3 days, capped
PLAY_CHANCE = 0.62  # a still-playing player shows up on a given day
MINUTES_MEDIAN, MINUTES_SIGMA, MINUTES_ENGAGEMENT, MINUTES_CAP = 22, 0.85, 2.5, 420  # minutes a day played
DAY_SPREAD = (0.6, 1.4)  # each day's minutes vary by this factor
WIN_RATE_MEAN, WIN_RATE_SD, WIN_RATE_RANGE = 0.5, 0.06, (0.3, 0.72)
MIN_PER_MATCH = 8.0  # minutes per match including the end screen (7.5 matches an hour)
WINNER_BALLS, LOSER_BALLS = 7.5, 4.0  # balls that pay the winner / loser in a match
WINNER_NICE, LOSER_NICE = 0.5, 0.3  # nice shots per match, winner / loser
# The share of paying balls at each ball streak level (x1..x8+): the all-rank average of
# tools/streak_model.luau (200 bot-duel games a rank, 2026-10-09). Prices the streak bonus.
BALL_STREAK_LEVELS = {1: 0.520, 2: 0.244, 3: 0.121, 4: 0.062, 5: 0.032, 6: 0.015, 7: 0.006, 8: 0.002}
MODE_MIX = {"Classic": 0.5, "Difficult": 0.3, "Challenger": 0.2}  # tables played once harder ones unlock
MODE_RANK_XP = 1.3  # rank XP a win earns on that mix, against Classic (for the rank rewards)
PAYER_SHARE_STAYERS, PAYER_SHARE_OTHERS = 0.06, 0.012  # pay Robux: lifetime 7+ days / shorter
BUDGET_MEDIAN, BUDGET_SIGMA, BUDGET_CAP, BUDGET_DAYS = 450, 1.2, 40000, 20  # Robux a month; budget / 20 a day played
VIP_SHARE_OF_PAYERS = 0.4
SAVER_SHARE = 0.3  # never buy Mystery blocks with money
MYSTERY_SPEND_SHARE = 0.7  # the others spend this share of their money on Mystery blocks a day
SPIN_SPEND_SHARE = 0.10  # ...and this share of that on ability spins
GROUP_JOIN_SHARE, FAVORITE_SHARE = 0.30, 0.25  # join the group / favorite the game on day 1
INVITED_SHARE, CODE_REDEEM_SHARE, PLUS_SHARE = 0.05, 0.7, 0.12  # arrive invited / redeem launch codes / Roblox Plus
GIFT_SHARE = 0.8  # players who leave once and come back for the Gift (the leave itself is ~everyone)
RESTOCK_BUYER_SHARE = 0.2  # buy the Rare restock slots with money when they can (everyone buys Epic and up)
# v4: cheaper Robux prices bring more first purchases. Conversion x1.5 (a 19 R$ Starter Pack and a
# 4 R$ skip; research 01), the same Robux budget per payer.
V4_PAYER_LIFT = 1.5
STARTER_TAKE = 0.5  # payers who buy the Starter Pack (shown in their first 7 days)
# A payer's daily Robux, split (v4: there are products to buy directly; before: all into packs,
# plus Grand Opening blocks in the window, the v3 sim's split).
SPLIT_V4 = {"go": 0.40, "mystery": 0.25, "restock": 0.15, "packs": 0.20}  # inside the Grand Opening window
SPLIT_V4_AFTER = {"go": 0.0, "mystery": 0.40, "restock": 0.25, "packs": 0.35}
SPLIT_BEFORE = {"go": 0.50, "mystery": 0.0, "restock": 0.0, "packs": 0.50}
SPLIT_BEFORE_AFTER = {"go": 0.0, "mystery": 0.0, "restock": 0.0, "packs": 1.0}
GO_MONEY_FANS = 0.5  # non-savers who buy Grand Opening blocks with money first in the window
RINGS = [0.30, 0.30, 0.20, 0.12, 0.08]  # Lucky / Golden Shot: miss, grey, blue, red, gold for an average player (v3 sim)
LUCKY_SHOT_SHARE = 0.8  # days played on which the free Lucky Shot is taken
GOLDEN_BUYER_SHARE = 0.25  # payers who buy the Golden Shot on a day they play
LUCKY_RAIN_CATCH = 0.2  # share of Lucky Rains a player is in a match for and reaches a block
# --sell (economy v5 plan 7.5): the share of DUPLICATE copies a player sells back by rarity (first
# copies are kept, for the Index), and the share of Week One Cue owners who sell theirs.
SELL_DUPLICATES = {"Common": 1.0, "Uncommon": 1.0, "Rare": 0.9, "Epic": 0.6, "Legendary": 0.4, "Mythic": 0.25,
                   "Secret": 0.25}
WEEK_ONE_SELL = 0.3

SOURCES = ["win track", "mystery (money)", "mystery (Robux)", "restock (money)", "restock (Robux)", "login + 28-day",
           "playtime", "rank rewards", "group/fav/invite/codes/gift", "vip daily", "grand opening", "starter pack",
           "lucky + golden shot", "lucky rain"]
S = {s: i for i, s in enumerate(SOURCES)}

RETENTION = {
    # The plans' assumption (2026-10-02): about D1 28%, D7 12% (a top-1% Roblox game).
    "plan": {"ONE_DAY_SHARE": 0.55, "PLAY_CHANCE": 0.62, "LIFE_SHAPE": 0.75},
    # A typical big Roblox game (GameAnalytics 2026 median D1 10.3%, D7 1.6%; research 03): about D1 12%, D7 4%.
    "typical": {"ONE_DAY_SHARE": 0.75, "PLAY_CHANCE": 0.5, "LIFE_SHAPE": 1.0},
}


def set_retention(name):
    for k, v in RETENTION[name].items():
        globals()[k] = v


# ------------------------------------------------------------------------------------------------
# Config (through the Lune exporter)
# ------------------------------------------------------------------------------------------------
def load_config():
    stale = not CONFIG_JSON.exists() or any(CONFIG_JSON.stat().st_mtime < s.stat().st_mtime for s in SOURCES_LUAU if s.exists())
    if stale:
        if shutil.which("lune") is None:
            sys.exit(f"{CONFIG_JSON.name} is missing or older than Config.luau, and Lune is not installed to rebuild it.\n"
                     f"Install Lune (see docs/STUDIO_NOTES.md), then run: lune run {EXPORTER}")
        r = subprocess.run(["lune", "run", EXPORTER], cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"lune run {EXPORTER} failed:\n{r.stdout}{r.stderr}")
    with open(CONFIG_JSON) as f:
        return json.load(f)


def reward(row):
    """A Config reward row ({Money, Blocks, Cues, Spins}) as {"money": n, kind: n, "cues": [ids]}.
    Spins are not loot."""
    out = {}
    if row.get("Money"):
        out["money"] = row["Money"]
    out.update(row.get("Blocks") or {})
    if row.get("Cues"):
        out["cues"] = list(row["Cues"])
    return out


def chain_dist(chain, start):
    """The final tier (percent) of a block that starts at `start` and climbs one step with
    chain[tier] (0-1) until a step fails (economy v5: Config.BlockOdds.Climb)."""
    out, p, t = {}, 1.0, TIERS.index(start)
    while True:
        up = chain.get(TIERS[t], 0.0) if t < len(TIERS) - 1 else 0.0
        out[TIERS[t]] = p * (1 - up) * 100
        if up <= 0:
            break
        p *= up
        t += 1
    return {k: out.get(k, 0.0) for k in TIERS}


def per_block(plan, kind, launch=False):
    """One block of `kind`'s cue rarity odds (percent, no pity): a climbing kind's climb from its
    start (with the launch luck when `launch`) times each final tier's row, else its own row."""
    rows = plan["rows"]
    kind = plan.get("alias", {}).get(kind, kind)
    cl = plan.get("climb")
    if kind == "Mystery":
        tier = plan["tier_launch"] if launch and plan.get("tier_launch") else plan["tier"]
        if plan.get("unified"):
            # Economy v5.1: the block it turns into, then that block's own climb.
            out = {r: 0.0 for r in RAR}
            for t, pt in tier.items():
                if pt:
                    for r, pr in per_block(plan, t, launch).items():
                        out[r] += pt / 100 * pr
            return out
    elif cl and kind in cl["starts"]:
        tier = chain_dist(cl["launch_chain"] if launch else cl["chain"], kind)
    else:
        return {r: rows[kind].get(r, 0.0) for r in RAR}
    out = {r: 0.0 for r in RAR}
    for t, pt in tier.items():
        for r, pr in rows.get(t, {}).items():
            if r in out:
                out[r] += pt / 100 * pr
    return out


def pct_row(odds, total):
    return {UNIQUES.get(k, k): v * 100 / total for k, v in odds.items()}


def rank_wins(c):
    """Classic wins against equal opponents to reach division I of each tier (no streaks)."""
    L = Ladder(c)
    out, xp, wins = [], 0.0, 0
    for t in L.tiers:
        while L.tier_of(L.division_of(xp)) != t:
            xp = L.xp_after(xp, True, "Classic", L.division_of(xp))
            wins += 1
        out.append(max(wins, 1))  # Bronze I is reached by the first win
    return out


def plan_from_config(c, built_only=False):
    """The plan in the simulation's shapes, every number from Config: economy v5 (Config has the
    climb, Config.BlockOdds.Climb), or v4 for the frozen tools/economy_config_v4.json."""
    CUES.update(c["BlockCues"])
    bo, total = c["BlockOdds"], c["BlockOdds"]["OddsTotal"]
    v5 = "Climb" in bo
    assert bo["Rarities"] == RAR, bo["Rarities"]
    drop, kinds = bo["Drop"], c["LuckyBlocks"]["Kinds"]
    daily, social, shop, prod = c["Daily"], c["Social"], c["Shop"], c["Products"]
    e = c["Economy"]
    nice = sum(e["NiceShotPay"].values()) / len(e["NiceShotPay"])
    # The ball streak's bonus on an average paying ball (Config.Economy.BallStreak*).
    streak_ball = e["BallPay"] * e["BallStreakShare"] * sum(
        p * max(n - e["BallStreakFrom"] + 1, 0) for n, p in BALL_STREAK_LEVELS.items())
    dm = c["DifficultyMoney"] if e["UseDifficultyMultiplier"] else {m: 1 for m in MODE_MIX}
    rk = c["Ranks"]
    wins_at = rank_wins(c)
    unlock = min(rk["Tiers"].index(rk["Unlocks"][m]) for m in ("Difficult", "Challenger"))
    rs = shop["Restock"]
    deal = shop["Deals"]["GrandOpening"]
    go_kind = kinds["GrandOpening"]
    lb = shop["LaunchBonus"]
    bonus_on = lb["Percent"] > 0 and lb["With"] == "GrandOpening"
    rows = {k: pct_row(row["Odds"], total) for k, row in bo["List"].items()}
    rows["Secret"] = {"Secret": 100.0}  # the top of the climb: the Secret cue (no block)
    # The win track: a block kind, or (economy v5) "Money", a step paying WinTrackMoney.
    track = [{"money": drop["WinTrackMoney"]} if k == "Money" else k for k in drop["WinTrack"]]
    bulk = shop["Mystery"]["BulkCount"]
    bulk_key = f"Mystery{bulk}" if f"Mystery{bulk}" in prod else "Mystery10"
    start = drop.get("PityStart") or {}
    plan = {
        "name": ("v5.1" if "Turn" in bo else "v5" if v5 else "v4") + (" built only" if built_only else ""),
        "rows": rows,
        "pity": {"Rare": drop["PityRare"], "Epic": drop["PityEpic"]},
        # A new save's pity counters (economy v5: a head start; v4: none).
        "pity_start": (start.get("SinceRare", 0), start.get("SinceEpic", 0)),
        "pity_paid": True,  # every Mystery block counts and gets pity, bought ones too
        "first_win": drop["FirstWin"],
        "track": track, "vip_track": [],
        "vip_daily": reward({"Blocks": daily["VipBlocks"]}),
        "login_first": [reward(r) for r in daily["FirstWeek"]],
        "login_later": [reward(r) for r in daily["Streak"]],
        "login_resets": True, "first_week_count": True, "first_week_window": daily["FirstWeekWindow"],
        "track28": {r["Day"]: reward(r) for r in daily["Track"]},
        "playtime": [(r["Minutes"], reward(r)) for r in daily["Playtime"]],
        # The launch codes everyone can redeem (the like codes are switched on later, one by one).
        "codes": [reward(r) for _, r in sorted(daily["Codes"].items()) if not r.get("Live") and reward(r)],
        "group": reward(social["GroupReward"]), "favorite": reward(social["FavoriteReward"]),
        "invite": social["InviteBlock"],
        "ranks": [(w, reward(rk["Rewards"]["Tier"][t])) for w, t in zip(wins_at, rk["Tiers"])],
        "mystery_money": shop["Mystery"]["Price"], "mystery_bulk": (shop["Mystery"]["BulkCount"], shop["Mystery"]["BulkPrice"]),
        "go_money": deal["Money"][0], "go_days": deal["Seconds"] / 86400,
        "go_pity": go_kind["Guarantee"]["At"], "go_pity_cue": UNIQUES[go_kind["Guarantee"]["Cue"]],
        "go_caps": {UNIQUES[k]: v for k, v in (bo["List"]["GrandOpening"].get("Caps") or {}).items()},
        # kind: (slot chance %, VIP slot chance %, money price, Robux price, stock)
        "restock": {k: (rs["Odds"].get(k, 0) * 100 / rs["ChanceTotal"], rs["VipOdds"].get(k, 0) * 100 / rs["ChanceTotal"],
                        row["Price"], prod[row["Product"]]["Robux"] if row.get("Product") else None, row["Stock"])
                    for k, row in sorted(rs["Kinds"].items(), key=lambda kv: TIERS.index(kv[0]))},
        "restock_slots": rs["Slots"],
        # Slots with their own table (economy v5: slot 1 is always Epic or better), by slot index.
        "restock_own": {n: {k: v * 100 / rs["ChanceTotal"] for k, v in own.items()}
                        for n, own in enumerate(rs.get("SlotOdds") or []) if own},
        "packs": [(p["Robux"], p["Money"]) for p in c["Packs"]],
        "mystery_robux": (prod["Mystery1"]["Robux"], prod[bulk_key]["Robux"]),
        "go_robux": (prod["GrandOpening1"]["Robux"], prod["GrandOpening3"]["Robux"], prod["GrandOpening10"]["Robux"]),
        "starter": {"robux": prod["StarterPack"]["Robux"], "money": shop["StarterMoney"], "block": "Starter"},
        "vip_robux": prod["Vip"]["Robux"], "skip_robux": prod["LuckyBlockSkip"]["Robux"],
        "launch_bonus": lb["Percent"] / 100 if bonus_on else 0.0,
        "launch_bulk": lb["MysteryBulkCount"] if bonus_on else shop["Mystery"]["BulkCount"],
        "robux_bulk": bulk if bulk_key != "Mystery10" or bulk == 10 else 10,
        # Match money (Config.Economy) and the money sink.
        "win_pay": WINNER_BALLS * (e["BallPay"] + streak_ball) + WINNER_NICE * nice + e["WinBonus"],
        "loss_pay": LOSER_BALLS * (e["BallPay"] + streak_ball) + LOSER_NICE * nice + e["LossBonus"],
        "streak_bonus": e["StreakBonus"],
        "boosts": {"vip": e["VipBoost"], "group": e["GroupBoost"], "plus": e.get("PlusBoost", 0)},
        "mode_money": sum(MODE_MIX[m] * dm[m] for m in MODE_MIX), "unlock_wins": wins_at[unlock],
        "spin_price": c["Ults"]["Earn"]["MoneyPerSpin"],
        "lucky_shot": None, "golden_shot": None, "lucky_rain": None, "stay": None,
    }
    if not built_only:
        pl = c["Planned"]
        rings = ("Miss", "Grey", "Blue", "Red", "Gold")
        plan["lucky_shot"] = [reward(pl["LuckyShot"][r]) for r in rings]
        plan["golden_shot"] = {"robux": pl["GoldenShot"]["Robux"], "rings": [reward(pl["GoldenShot"][r]) for r in rings]}
        rain = pl["LuckyRain"]
        plan["lucky_rain"] = {"per_minute": 60 / rain["EverySeconds"] * LUCKY_RAIN_CATCH, "cap": rain["PerDay"],
                              "rare_share": 1 / rain["RareOneIn"]}
        sb = pl["StayBonus"]
        plan["stay"] = {"per_minute": sb["PercentPerStep"] / 100 / (sb["StepSeconds"] / 60), "cap": sb["MaxPercent"] / 100}
    if v5:
        # The climb: one chance per step (parts of OddsTotal); the Grand Opening Luck's steps for
        # its first Seconds (the model's Grand Opening window starts on day 0, as the deal's).
        cl = bo["Climb"]
        chain = {t: cl["Steps"].get(t, 0) / total for t in TIERS}
        luck = dict(chain, **{t: v / total for t, v in cl["Luck"]["Steps"].items()})
        plan["climb"] = {"chain": chain, "launch_chain": luck,
                         "starts": [t for t in TIERS if (kinds.get(t) or {}).get("Climb") == t]}
        turn = bo.get("Turn")
        if turn:
            # Economy v5.1: the Mystery's roll (its own steps up to Top; the luck never lifts it)
            # turns it into an unclimbed block, which climbs from its name. Pity forces the
            # block and counts the cue the Mystery finally gives.
            top = TIERS.index(turn["Top"])
            steps = {t: (turn["Steps"].get(t, 0) / total if TIERS.index(t) < top else 0.0) for t in TIERS}
            plan["tier"] = chain_dist(steps, "Standard")
            plan["tier_launch"] = plan["tier"]
            plan["unified"], plan["pity_final"] = True, True
        else:
            plan["tier"] = chain_dist(chain, "Standard")  # v5: a Standard start, with pity
            plan["tier_launch"] = chain_dist(luck, "Standard")
        plan["luck_days"] = cl["Luck"]["Seconds"] / 86400 if cl["Luck"]["With"] == "GrandOpening" else 0
        # Kinds that climb from another kind's start (Lucky 8, the Gift, the Sky block).
        plan["alias"] = {k: row["Climb"] for k, row in kinds.items()
                         if row.get("Climb") and row["Climb"] != k and not row.get("Pity")}
        plan["lucky8"], plan["gift"] = "Lucky8", "Gift"
    else:
        plan["tier"] = {t: drop["Weights"].get(t, 0) * 100 / total for t in TIERS}
        plan["lucky8"], plan["gift"] = kinds["Lucky8"]["Odds"], kinds["Gift"]["Odds"]
    return plan


# ------------------------------------------------------------------------------------------------
# The economy before v4 (Config on shop-lively 0cdd550, 2026-10-08), frozen for --compare only.
# Match money, boosts and unlocks are taken from today's Config (v4 did not change them).
# ------------------------------------------------------------------------------------------------
BEFORE = {
    "name": "before v4",
    "rows": {
        "Standard": {"Common": 75.0, "Uncommon": 23.0, "Rare": 1.99, "Epic": 0.009, "Legendary": 0.0009, "Mythic": 0.0001},
        "Uncommon": {"Common": 40.0, "Uncommon": 54.0, "Rare": 5.95, "Epic": 0.045, "Legendary": 0.0045, "Mythic": 0.0005},
        "Rare": {"Uncommon": 70.0, "Rare": 29.6, "Epic": 0.35, "Legendary": 0.045, "Mythic": 0.0045, "Secret": 0.0005},
        "Epic": {"Rare": 78.0, "Epic": 19.0, "Legendary": 2.6, "Mythic": 0.36, "Secret": 0.04},
        "Legendary": {"Epic": 75.0, "Legendary": 22.0, "Mythic": 2.7, "Secret": 0.3},
        "Mythic": {"Legendary": 75.0, "Mythic": 22.0, "Secret": 3.0},
        "Starter": {"Rare": 97.0, "Epic": 2.5, "Legendary": 0.45, "Mythic": 0.045, "Secret": 0.005},
        "Sky": {"Common": 45.0, "Uncommon": 45.0, "Rare": 9.9, "Epic": 0.09, "Legendary": 0.009, "Mythic": 0.001},
        "GrandOpening": {"Uncommon": 56.35, "Rare": 37.45, "Epic": 2.5, "Legendary": 0.35, "Mythic": 0.046, "Secret": 0.004,
                         "Firework": 3.0, "Beta": 0.3},
    },
    "lucky8": "Rare", "gift": "Rare",
    "tier": {"Standard": 68.0, "Uncommon": 25.0, "Rare": 6.7, "Epic": 0.28, "Legendary": 0.0196, "Mythic": 0.0004},
    "pity": {"Rare": 10, "Epic": 150},
    "pity_paid": False,  # PlayerData.revealMystery: a paid Mystery block rolls the natural odds
    "first_win": "Rare",
    # The win track: None = every win drops a Mystery block (PC wins: the first 10 a day).
    "track": None, "vip_track": [], "vip_daily": None,
    "login_first": [{"money": 5000}, {"Mystery": 1}, {"money": 10000}, {"Mystery": 2}, {"money": 15000}, {"Mystery": 3}, {"Rare": 1}],
    "login_later": None,  # None: the same as the first week
    "login_resets": True,  # a missed day (beyond the weekly freeze) starts the loop over
    "first_week_window": None,  # first-week rewards only within this many days of joining (None: any time)
    "track28": {7: {"Rare": 1}, 14: {"Rare": 2}, 21: {"Rare": 2}, 28: {"Epic": 1}},
    "playtime": [(10, {"money": 2000}), (30, {"Mystery": 1}), (60, {"Mystery": 2}), (90, {"money": 10000}), (120, {"Rare": 1})],
    "codes": [{"money": 5000, "Mystery": 1}, {"money": 2500}, {"Rare": 1}],  # WELCOME, 8BALL, ROOFTOP
    "group": {"Mystery": 3}, "favorite": {"money": 10000, "Lucky8": 1}, "invite": "Rare",
    "ranks": [  # (wins, reward): division I of each tier, Classic wins against equals
        (1, {"money": 2500, "Mystery": 1, "Standard": 1}), (21, {"money": 5000, "Rare": 1}), (66, {"money": 10000, "Rare": 2}),
        (136, {"money": 20000, "Rare": 3}), (232, {"money": 50000, "Epic": 1}), (393, {"money": 100000, "Epic": 2}),
        (675, {"money": 200000, "Epic": 3}), (1180, {"money": 400000, "Legendary": 1}),
        (2025, {"money": 750000, "Legendary": 2}), (3075, {"money": 2000000, "Mythic": 1})],
    # Shop, money prices.
    "mystery_money": 4900, "mystery_bulk": (10, 44100),
    "go_money": 49000, "go_days": 21, "go_pity": 400,
    "restock": {  # kind: (slot chance %, VIP slot chance %, money price, Robux price or None, stock)
        "Uncommon": (62.0, 0.0, 14900, None, 3),
        "Rare": (36.6, 96.0, 34900, 99, 1),
        "Epic": (1.35, 3.85, 349000, 999, 1),
        "Legendary": (0.05, 0.15, 3490000, 4999, 1),
    },
    "restock_slots": 3,
    # Robux.
    "packs": [(49, 9000), (99, 19500), (249, 52500), (499, 110000), (999, 235000), (2499, 625000), (4999, 1300000)],
    "mystery_robux": (25, 229),  # 1 and 10
    "go_robux": (49, 129, 349),  # 1, 3, 10
    "starter": {"robux": 99, "money": 75000, "block": "Starter"},
    "vip_robux": 499, "skip_robux": 19,
    # Planned, not built (the v3 plan and the designer's concepts): the free daily Lucky Shot, the
    # paid Golden Shot (once a day), Lucky Rain (Sky blocks, 3 a day). None in today's game.
    "lucky_shot": None, "golden_shot": None, "lucky_rain": None,
    "stay": None, "launch_bonus": 0.0, "first_week_count": False,
    "go_pity_cue": "Beta", "launch_bulk": 10, "spin_price": 17500,
}


def cum(table, keys):
    out, acc = [], 0.0
    for k in keys:
        acc += table.get(k, 0.0)
        out.append(acc)
    assert abs(acc - 100.0) < 1e-9, (table, acc)
    return out


def per_mystery(plan):
    """Each outcome's chance per Mystery block, no pity (percent)."""
    if plan.get("unified"):
        return per_block(plan, "Mystery")
    p = {r: 0.0 for r in RAR}
    for t in TIERS:
        for r in RAR:
            p[r] += plan["tier"][t] / 100 * plan["rows"][t].get(r, 0.0)
    return p


def poisson(rng, lam):
    if lam <= 0:
        return 0
    if lam > 30:
        return max(0, int(round(rng.gauss(lam, math.sqrt(lam)))))
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def best_pack_rate(plan, robux):
    """Money per Robux for a spend of about `robux` (the biggest pack it affords; Pack1 floor)."""
    rate = plan["packs"][0][1] / plan["packs"][0][0]
    for r, m in plan["packs"]:
        if r <= max(robux, plan["packs"][0][0]):
            rate = m / r
    return rate


class Sim:
    def __init__(self, plan, seed=SEED, sample=SAMPLE, days=DAYS, report=REPORT, ref=None, sell=None):
        self.p, self.seed, self.sample, self.days, self.report, self.ref = plan, seed, sample, days, report, ref
        self.sell = sell  # --sell: {"find", "rows", "back"} money from Config (sell_rules)
        self.v4 = plan["track"] is not None
        self.go_cue = OUTS.index(plan["go_pity_cue"])
        self.tier_cum = cum(plan["tier"], TIERS)
        self.tier_cum_launch = cum(plan["tier_launch"], TIERS) if plan.get("tier_launch") else self.tier_cum
        self.row_cum = {k: cum(v, OUTS) for k, v in plan["rows"].items()}
        if not plan.get("climb"):
            self.row_cum["Lucky8"] = self.row_cum[plan["lucky8"]]  # the favorite's block rolls this row
            self.row_cum["Gift"] = self.row_cum[plan["gift"]]
        rs = plan["restock"]
        self.slot_cum = cum({k: v[0] for k, v in rs.items()}, list(rs))
        own = plan.get("restock_own") or {}
        self.slot_cums = [cum({k: own[n].get(k, 0.0) for k in rs}, list(rs)) if n in own else self.slot_cum
                          for n in range(plan["restock_slots"])]
        self.extra_money = {"find": 0.0, "index rows": 0.0, "sell-back": 0.0, "week one sold": 0.0}
        self.match_money = 0.0
        self.week_one_given = [0] * days  # Week One Cue copies given, by day (cumulative)
        vip_tab = {k: v[1] for k, v in rs.items() if v[1] > 0}
        self.vip_cum = cum(vip_tab, list(vip_tab))
        self.vip_kinds = list(vip_tab)

    def run(self):
        P = self.p
        pop, act = random.Random(self.seed), random.Random(self.seed + 1000)
        loot, xtra = random.Random(self.seed + 2000), random.Random(self.seed + 3000)
        days = self.days
        ref = self.ref
        if ref:
            arrivals = [ref["n"]] + [0] * (days - 1)
        else:
            arrivals = [int(ARRIVALS_DAY0 * ARRIVAL_GROWTH ** min(d, GROWTH_DAYS) * self.sample) for d in range(days)]
        N = sum(arrivals)
        joined = [d for d, n in enumerate(arrivals) for _ in range(n)]
        lift = V4_PAYER_LIFT if self.v4 else 1.0
        life, minutes, wr, payer, budget, vip, saver = [], [], [], [], [], [], []
        for _ in range(N):
            lt = 1 if pop.random() < ONE_DAY_SHARE else int(min(LIFE_MIN + (pop.paretovariate(LIFE_SHAPE) - 1) * LIFE_SCALE, LIFE_CAP))
            life.append(lt)
            minutes.append(min(pop.lognormvariate(math.log(MINUTES_MEDIAN), MINUTES_SIGMA) * (1 + math.log1p(lt) / MINUTES_ENGAGEMENT), MINUTES_CAP))
            wr.append(min(max(pop.gauss(WIN_RATE_MEAN, WIN_RATE_SD), WIN_RATE_RANGE[0]), WIN_RATE_RANGE[1]))
            pays = pop.random() < (PAYER_SHARE_STAYERS if lt >= 7 else PAYER_SHARE_OTHERS) * lift
            payer.append(pays)
            budget.append(min(pop.lognormvariate(math.log(BUDGET_MEDIAN), BUDGET_SIGMA), BUDGET_CAP) if pays else 0.0)
            vip.append(pays and pop.random() < VIP_SHARE_OF_PAYERS)
            saver.append(pop.random() < SAVER_SHARE)
        group = [xtra.random() < GROUP_JOIN_SHARE for _ in range(N)]
        fav = [xtra.random() < FAVORITE_SHARE for _ in range(N)]
        invited = [xtra.random() < INVITED_SHARE for _ in range(N)]
        redeems = [xtra.random() < CODE_REDEEM_SHARE for _ in range(N)]
        restock_buyer = [xtra.random() < RESTOCK_BUYER_SHARE for _ in range(N)]
        plus = [xtra.random() < PLUS_SHARE for _ in range(N)]
        gifted = [xtra.random() < GIFT_SHARE for _ in range(N)]
        go_fan = [(not saver[i]) and xtra.random() < GO_MONEY_FANS for i in range(N)]
        starter_buyer = [payer[i] and xtra.random() < STARTER_TAKE for i in range(N)]
        if ref:
            life = [10 ** 6] * N
            minutes = [ref["minutes"]] * N
            wr = [0.5] * N
            payer = [bool(ref.get("budget"))] * N
            budget = [ref.get("budget", 0)] * N
            vip = [ref.get("vip", False)] * N
            saver = [False] * N
            group = fav = redeems = gifted = [True] * N
            invited = [False] * N
            go_fan = [False] * N
            starter_buyer = [bool(ref.get("budget"))] * N

        money = [0.0] * N
        wins = [0] * N
        owned = [[0] * 9 for _ in range(N)]
        rare_p, epic_p = [P.get("pity_start", (0, 0))[0]] * N, [P.get("pity_start", (0, 0))[1]] * N
        week1 = [0] * N  # holds the Week One Cue (economy v5: first-week day 7)
        week1_total = [0]
        sl = self.sell
        found = [[0] * 9 for _ in range(N)] if sl else None  # --sell: the cues found, per rarity (bits)
        sellrng = random.Random(20261009)
        streak, claims, last_active, freeze_week = [0] * N, [0] * N, [-99] * N, [-1] * N
        first_done = [0] * N  # first-week loop days already given (bitmask)
        rank_idx = [0] * N
        go_opened = [0] * N
        unique_made = {7: 0, 8: 0}  # Firework and Beta copies found so far (every server)
        wallet = [0.0] * N  # a payer's Robux put aside for restock blocks
        source = [[0] * 9 for _ in SOURCES]
        first_seen = {r: [None] * N for r in range(2, 9)}  # (day, hours played) of the first copy
        hours = [0.0] * N
        copies_by_day = []
        opened = {}
        robux_spent = {"starter": 0.0, "go": 0.0, "mystery": 0.0, "restock": 0.0, "packs": 0.0, "golden": 0.0}
        golden_buyer = [payer[i] and xtra.random() < GOLDEN_BUYER_SHARE for i in range(N)]
        out = {}
        day_now = [0]
        received = {}  # blocks received by kind, a Mystery block counted as Mystery
        spent = [0.0] * N  # money spent (so money earned = money + spent)
        snaps = {}

        pity_paid_ok = [True]  # whether the Mystery being opened counts pity (roll_tier sets it)

        def luck_on():
            return P.get("luck_days") and day_now[0] < P["luck_days"]

        def climb_from(start):
            """Economy v5: the final tier of a block starting at `start` (one chance a step)."""
            cl = P["climb"]
            ch = cl["launch_chain"] if luck_on() else cl["chain"]
            t = TIERS.index(start)
            while t < len(TIERS) - 1 and loot.random() < ch[TIERS[t]]:
                t += 1
            return TIERS[t]

        def open_row(i, kind, src, recv=None, climbed=False):
            received[recv or kind] = received.get(recv or kind, 0) + 1
            kind = P.get("alias", {}).get(kind, kind)
            if P.get("climb") and not climbed and kind in P["climb"]["starts"]:
                kind = climb_from(kind)
            r = bisect.bisect_right(self.row_cum[kind], loot.random() * 100.0)
            r = min(r, len(OUTS) - 1)
            if kind == "GrandOpening":
                go_opened[i] += 1
                caps = P.get("go_caps") or {}
                left = {u: caps.get(OUTS[u], math.inf) * self.sample - unique_made[u] for u in (7, 8)}
                g = self.go_cue
                if P["go_pity"] and go_opened[i] == P["go_pity"] and owned[i][g] == 0 and left[g] > 0:
                    r = g
                # One copy of each Unique a player (Roblox's one-instance rule: an owner's odds
                # show that row as Rare), and none once its copies are all found (the cap).
                if r in (7, 8) and (owned[i][r] > 0 or left[r] <= 0):
                    r = 2
                if r in (7, 8):
                    unique_made[r] += 1
            owned[i][r] += 1
            if recv == "Mystery" and P.get("pity_final") and (pity_paid_ok[0]):
                # Economy v5.1: the counters count the cue the Mystery finally gave.
                rare_p[i] = 0 if r >= 2 else rare_p[i] + 1
                epic_p[i] = 0 if r >= 3 else epic_p[i] + 1
            source[src][r] += 1
            opened[kind] = opened.get(kind, 0) + 1
            if r >= 2 and first_seen[r][i] is None:
                first_seen[r][i] = (day_now[0], hours[i])
            if sl:
                if r >= 7:
                    if owned[i][r] == 1:
                        money[i] += sl["find"]["Unique"]
                        self.extra_money["find"] += sl["find"]["Unique"]
                else:
                    c_ = sellrng.randrange(CUES[RAR[r]])
                    if not (found[i][r] >> c_) & 1:
                        found[i][r] |= 1 << c_
                        money[i] += sl["find"][RAR[r]]
                        self.extra_money["find"] += sl["find"][RAR[r]]
                        if found[i][r] == (1 << CUES[RAR[r]]) - 1:
                            money[i] += sl["rows"].get(RAR[r], 0)
                            self.extra_money["index rows"] += sl["rows"].get(RAR[r], 0)
                    elif sellrng.random() < SELL_DUPLICATES[RAR[r]]:
                        money[i] += sl["back"][RAR[r]]
                        self.extra_money["sell-back"] += sl["back"][RAR[r]]
                        owned[i][r] -= 1

        def give_cue(i, cue):
            """A cue a reward gives (economy v5: the Week One Cue, a Legendary in no block)."""
            week1[i] = 1
            week1_total[0] += 1
            if sl:
                money[i] += sl["find"]["Legendary"]
                self.extra_money["find"] += sl["find"]["Legendary"]
                if sellrng.random() < WEEK_ONE_SELL:
                    money[i] += sl["back"]["Legendary"]
                    self.extra_money["week one sold"] += sl["back"]["Legendary"]
                    week1[i] = 0

        def roll_tier(i, paid):
            tc = self.tier_cum_launch if luck_on() else self.tier_cum
            t = min(bisect.bisect_right(tc, loot.random() * 100.0), len(TIERS) - 1)
            pity_paid_ok[0] = not paid or P["pity_paid"]
            if not pity_paid_ok[0]:
                return TIERS[t]
            if t < 3 and epic_p[i] + 1 >= P["pity"]["Epic"]:
                t = 3
            elif t < 2 and rare_p[i] + 1 >= P["pity"]["Rare"]:
                t = 2
            if not P.get("pity_final"):
                rare_p[i] = 0 if t >= 2 else rare_p[i] + 1
                epic_p[i] = 0 if t >= 3 else epic_p[i] + 1
            return TIERS[t]

        def give(i, reward, src, paid=False):
            for k, n in reward.items():
                if k == "money":
                    money[i] += n
                    continue
                if k == "cues":
                    for cue in n:
                        give_cue(i, cue)
                    continue
                for _ in range(n):
                    if k == "Mystery":
                        open_row(i, roll_tier(i, paid), src, recv="Mystery", climbed=not P.get("unified"))
                    else:
                        open_row(i, k, src)

        def restock_slots():
            kinds = []
            for n in range(P["restock_slots"]):
                kinds.append(list(P["restock"])[bisect.bisect_right(self.slot_cums[n], xtra.random() * 100.0)])
            return kinds

        alive = []
        for day in range(days):
            day_now[0] = day
            wk, month = day // 7, day // 30
            hi = sum(arrivals[: day + 1])
            alive = [i for i in alive if day - joined[i] < life[i]] + list(range(hi - arrivals[day], hi))
            today = [i for i in alive if joined[i] == day or ref or act.random() < PLAY_CHANCE]
            go_open = day < P["go_days"]
            for i in today:
                mins = minutes[i] * (1.0 if ref else act.uniform(*DAY_SPREAD))
                hours[i] += mins / 60
                matches = poisson(act, mins / MIN_PER_MATCH) if not ref else int(round(mins / MIN_PER_MATCH))
                w = sum(1 for _ in range(matches) if act.random() < wr[i])
                unlocked = wins[i] >= P["unlock_wins"]
                bo = P["boosts"]
                boost = 1 + (bo["vip"] if vip[i] else 0) + (bo["group"] if group[i] else 0) + (bo["plus"] if plus[i] else 0)
                if P["stay"]:
                    # The stay bonus's average over the day's play (one sitting): it climbs
                    # per_minute a minute to its cap.
                    ramp = P["stay"]["cap"] / P["stay"]["per_minute"]
                    if mins <= ramp:
                        boost += P["stay"]["per_minute"] * mins / 2
                    else:
                        boost += P["stay"]["cap"] * (ramp / 2 + (mins - ramp)) / mins
                pay = w * (P["win_pay"] + P["streak_bonus"] * wr[i] ** 2) + (matches - w) * P["loss_pay"]
                money[i] += pay * (P["mode_money"] if unlocked else 1) * boost
                self.match_money += pay * (P["mode_money"] if unlocked else 1) * boost
                # Login loop (first week, then later weeks), weekly freeze, 28-day track.
                gap = day - last_active[i]
                freeze = gap == 2 and freeze_week[i] != wk
                if freeze:
                    freeze_week[i] = wk
                if P["login_resets"]:
                    streak[i] = streak[i] + 1 if gap == 1 or freeze else 1
                else:
                    streak[i] += 1
                last_active[i] = day
                claims[i] += 1
                loop_day = (streak[i] - 1) % 7
                # Each day of the first-week loop is given once ever (the first time a player
                # reaches that day); after that the later weeks' row.
                in_window = P["first_week_window"] is None or day - joined[i] < P["first_week_window"]
                if P.get("first_week_count") and in_window and first_done[i] != 127:
                    # Count mode: the first week's days go to the first 7 login days (no streak).
                    k = bin(first_done[i]).count("1")
                    first_done[i] |= 1 << k
                    give(i, P["login_first"][k], S["login + 28-day"])
                elif P["login_later"] is None or (in_window and not first_done[i] >> loop_day & 1):
                    first_done[i] |= 1 << loop_day
                    give(i, P["login_first"][loop_day], S["login + 28-day"])
                else:
                    give(i, P["login_later"][loop_day], S["login + 28-day"])
                tr = P["track28"].get(((claims[i] - 1) % 28) + 1)
                if tr:
                    give(i, tr, S["login + 28-day"])
                for mn, rw in P["playtime"]:
                    if mins >= mn:
                        give(i, rw, S["playtime"])
                def ring():
                    x, acc = xtra.random(), 0.0
                    for k, q in enumerate(RINGS):
                        acc += q
                        if x < acc:
                            return k
                    return len(RINGS) - 1
                if P["lucky_shot"] and xtra.random() < LUCKY_SHOT_SHARE:
                    give(i, P["lucky_shot"][ring()], S["lucky + golden shot"])
                    if P["golden_shot"] and golden_buyer[i]:
                        robux_spent["golden"] += P["golden_shot"]["robux"]
                        give(i, P["golden_shot"]["rings"][ring()], S["lucky + golden shot"], paid=True)
                if P["lucky_rain"]:
                    lr = P["lucky_rain"]
                    for _ in range(min(lr["cap"], poisson(xtra, mins * lr["per_minute"]))):
                        give(i, {"Rare" if xtra.random() < lr["rare_share"] else "Sky": 1}, S["lucky rain"])
                if vip[i] and P["vip_daily"]:
                    give(i, P["vip_daily"], S["vip daily"])
                if day == joined[i]:
                    if group[i]:
                        give(i, P["group"], S["group/fav/invite/codes/gift"])
                    if fav[i]:
                        give(i, P["favorite"], S["group/fav/invite/codes/gift"])
                    if redeems[i]:
                        for rw in P["codes"]:
                            give(i, rw, S["group/fav/invite/codes/gift"])
                if day == joined[i] + 1 and gifted[i]:
                    give(i, {P["gift"]: 1}, S["group/fav/invite/codes/gift"])
                # Win blocks.
                if self.v4:
                    steps = P["track"] + (P["vip_track"] if vip[i] else [])
                    for k in range(min(w, len(steps))):
                        kind = steps[k]
                        if wins[i] == 0 and k == 0:
                            kind = P["first_win"]
                        give(i, kind if isinstance(kind, dict) else {kind: 1}, S["win track"])
                else:
                    for k in range(w):
                        give(i, {P["first_win"] if (wins[i] == 0 and k == 0) else "Mystery": 1}, S["win track"])
                if w and wins[i] == 0 and invited[i]:
                    give(i, {P["invite"]: 2}, S["group/fav/invite/codes/gift"])  # both players' (the inviter's, folded in)
                wins[i] += w
                while rank_idx[i] < len(P["ranks"]) and wins[i] * (MODE_RANK_XP if unlocked else 1) >= P["ranks"][rank_idx[i]][0]:
                    give(i, P["ranks"][rank_idx[i]][1], S["rank rewards"])
                    rank_idx[i] += 1
                # Robux.
                if payer[i]:
                    robux = budget[i] / BUDGET_DAYS
                    if starter_buyer[i] and day == joined[i]:
                        st = P["starter"]
                        robux_spent["starter"] += st["robux"]
                        robux -= st["robux"]
                        money[i] += st["money"]
                        give(i, {st["block"]: 1}, S["starter pack"])
                        robux = max(robux, 0)
                    if vip[i] and day == joined[i]:
                        robux = max(robux - P["vip_robux"] / 5, 0)  # VIP spread over the first days' budget
                    split = (SPLIT_V4 if go_open else SPLIT_V4_AFTER) if self.v4 else (SPLIT_BEFORE if go_open else SPLIT_BEFORE_AFTER)
                    if split["go"]:
                        r1, r3, r10 = P["go_robux"]
                        spend = robux * split["go"]
                        n10 = int(spend // r10)
                        spend -= n10 * r10
                        n1 = int(spend // r1)
                        n = n10 * 10 + n1
                        robux_spent["go"] += n10 * r10 + n1 * r1
                        for _ in range(n):
                            open_row(i, "GrandOpening", S["grand opening"])
                    if split["mystery"]:
                        r1, r10 = P["mystery_robux"]
                        spend = robux * split["mystery"]
                        n10 = int(spend // r10)
                        n1 = int((spend - n10 * r10) // r1)
                        robux_spent["mystery"] += n10 * r10 + n1 * r1
                        bulk = P.get("robux_bulk", 10)
                        per = P["launch_bulk"] if go_open else bulk  # the launch bonus: 5 come as 6
                        give(i, {"Mystery": n10 * per + n1}, S["mystery (Robux)"], paid=True)
                    wallet[i] += robux * split["restock"]
                    packs = robux * split["packs"]
                    robux_spent["packs"] += packs
                    money[i] += packs * best_pack_rate(P, budget[i]) * (1 + (P["launch_bonus"] if go_open else 0))
                # Restock: every 10 minutes 3 slots (+1 VIP); a player buys what they can afford.
                restocks = int(mins / 10)
                for _ in range(restocks):
                    kinds = restock_slots()
                    if vip[i] and self.vip_kinds:
                        kinds.append(self.vip_kinds[bisect.bisect_right(self.vip_cum, xtra.random() * 100.0)])
                    for kind in sorted(set(kinds), key=TIERS.index, reverse=True):
                        chance, _, price, rprice, stock = P["restock"][kind]
                        lucky = TIERS.index(kind) >= 3
                        if not (lucky or restock_buyer[i]):
                            continue
                        if rprice and wallet[i] >= rprice and lucky:
                            wallet[i] -= rprice
                            robux_spent["restock"] += rprice
                            open_row(i, kind, S["restock (Robux)"])
                        elif money[i] >= price and (lucky or restock_buyer[i]):
                            n = min(stock, int(money[i] // price))
                            money[i] -= n * price
                            spent[i] += n * price
                            for _ in range(n):
                                open_row(i, kind, S["restock (money)"])
                # Money: Grand Opening blocks (fans, in the window), spins, Mystery blocks.
                if go_open and go_fan[i]:
                    n = int(money[i] // P["go_money"])
                    money[i] -= n * P["go_money"]
                    spent[i] += n * P["go_money"]
                    for _ in range(n):
                        open_row(i, "GrandOpening", S["grand opening"])
                if not saver[i]:
                    sp = money[i] * MYSTERY_SPEND_SHARE
                    n = int(sp * SPIN_SPEND_SHARE // P["spin_price"])
                    money[i] -= n * P["spin_price"]
                    spent[i] += n * P["spin_price"]
                    sp -= n * P["spin_price"]
                    bc, bp = P["mystery_bulk"]
                    tens = int(sp // bp)
                    n = int((sp - tens * bp) // P["mystery_money"])
                    money[i] -= tens * bp + n * P["mystery_money"]
                    spent[i] += tens * bp + n * P["mystery_money"]
                    give(i, {"Mystery": tens * bc + n}, S["mystery (money)"])
            copies_by_day.append([sum(source[s][r] for s in range(len(SOURCES))) / self.sample for r in range(9)])
            self.week_one_given[day] = week1_total[0] / self.sample
            if ref and day + 1 in REF_SNAPS:
                snaps[day + 1] = {
                    "received": {k: v / N for k, v in received.items()},
                    "earned": sum(money[i] + spent[i] for i in range(N)) / N,
                    "own": [sum(1 for i in range(N) if owned[i][r]) / N for r in range(9)],
                    "copies": [sum(owned[i][r] for i in range(N)) / N for r in range(9)],
                    "robux": sum(robux_spent.values()) / N,
                }
            if day + 1 in self.report:
                ever = [i for i in range(hi) if wins[i] > 0]
                recent = [i for i in ever if day - last_active[i] < 7]
                res = {"ever": len(ever) / self.sample, "recent": len(recent) / self.sample,
                       "avg_money_recent": sum(money[i] for i in recent) / max(len(recent), 1)}
                for r in range(2, 9):
                    res[OUTS[r]] = (sum(1 for i in recent if owned[i][r]) / max(len(recent), 1),
                                    sum(owned[i][r] for i in range(hi)) / self.sample)
                res["source"] = [[x / self.sample for x in row] for row in source]
                res["opened"] = {k: v / self.sample for k, v in opened.items()}
                res["robux"] = {k: v / self.sample for k, v in robux_spent.items()}
                res["wins_owned"] = [(wins[i], owned[i][:]) for i in recent]
                # Economy v5: the Week One Cue's holders, and a Legendary from blocks or it.
                res["WeekOne"] = sum(1 for i in recent if week1[i]) / max(len(recent), 1)
                res["LegOrWeekOne"] = sum(1 for i in recent if owned[i][4] or week1[i]) / max(len(recent), 1)
                out[day + 1] = res
        if ref:
            return {"first": first_seen, "owned": owned, "hours": hours, "N": N, "snaps": snaps}
        out["copies_by_day"] = copies_by_day
        out["week_one_given"] = self.week_one_given
        out["extra_money"] = dict(self.extra_money)
        out["match_money"] = self.match_money
        return out


# ------------------------------------------------------------------------------------------------
# Reports
# ------------------------------------------------------------------------------------------------
# Economy v5.1 (the designer's approved "Lively", 2026-10-09, docs/prompts/ECONOMY_V5_PLAN.md
# section 15; this model on that Config): share of players active in the last 7 days who own one
# (percent), as (low, high) within about the simulation's noise. Legendary is from blocks; the
# Week One Cue is apart. (v5, plan 7.1: Epic 58.9 / 67.3 / 65.0, Legendary 13.8 / 21.2 / 17.9,
# Mythic 2.41 / 4.63 / 4.34, Secret 0.08 / 0.14 / 0.12.)
PLAN_V5 = {
    7: {"Epic": 60.9, "Legendary": 14.8, "Mythic": 2.57, "Secret": 0.10, "WeekOne": 0.18},
    30: {"Epic": 69.2, "Legendary": 22.2, "Mythic": 4.80, "Secret": 0.17, "WeekOne": 15.8},
    60: {"Epic": 66.7, "Legendary": 18.7, "Mythic": 4.58, "Secret": 0.16, "WeekOne": 29.0},
}
TARGETS = {d: {r: (v - (1.5 if v >= 10 else 0.5 if v >= 1 else 0.05), v + (1.5 if v >= 10 else 0.5 if v >= 1 else 0.05))
               for r, v in row.items() if r != "WeekOne"} for d, row in PLAN_V5.items()}


def pct(x, d=2):
    return f"{x * 100:.{d}f}%"


def show_run(out, label):
    print(f"=== {label} ===")
    for d in REPORT:
        res = out[d]
        print(f"Day {d}: {res['ever']:,.0f} players ever won, {res['recent']:,.0f} active in the last 7 days, "
              f"average money of an active player ${res['avg_money_recent']:,.0f}")
        print("  own one (active 7d):  " + "  ".join(f"{r} {pct(res[r][0])} ({res[r][1]:,.0f} copies)" for r in OUTS[3:]))
        if "WeekOne" in res:
            print(f"  the Week One Cue: {pct(res['WeekOne'])} hold it; a Legendary from blocks or it: {pct(res['LegOrWeekOne'])}")
        src = res["source"]
        print("  Epic / Legendary / Mythic / Secret copies by source:")
        tot = [sum(src[s][r] for s in range(len(SOURCES))) for r in range(9)]
        for s, name in enumerate(SOURCES):
            if any(src[s][3:7]):
                print(f"    {name:30s} " + " / ".join(f"{src[s][r]:7,.0f} ({src[s][r] / max(tot[r], 1) * 100:3.0f}%)" for r in range(3, 7)))
        if d == REPORT[-1] or d == 30:
            print("  Robux spent (all players so far): " + ", ".join(f"{k} {v:,.0f}" for k, v in res["robux"].items()))
            print("  Blocks opened: " + ", ".join(f"{k} {v:,.0f}" for k, v in sorted(res["opened"].items(), key=lambda kv: -kv[1])))
    # Cues entering the game per day (the average of the 7 days up to each report day).
    cbd = out["copies_by_day"]
    print("  Cues entering the game per day (average of the week before):")
    for d in REPORT:
        lo = cbd[d - 8] if d >= 8 else [0] * 9
        n = min(d, 7)
        print(f"    day {d:2d}: " + ", ".join(f"{OUTS[r]} {(cbd[d - 1][r] - lo[r]) / n:,.1f}" for r in range(2, 9)))
    print()


def tables(plan):
    if plan.get("climb"):
        print(f"Plan {plan['name']}: each block's cue odds over its whole climb (percent; the launch luck after /)\n")
        kinds = ["Mystery"] + plan["climb"]["starts"] + sorted(plan.get("alias", {})) + ["GrandOpening", "Starter"]
        for k in kinds:
            o, ol = per_block(plan, k), per_block(plan, k, launch=True)
            up = sum(o[r] for r in RAR[4:])
            cells = ", ".join(f"{r} {o[r]:.4g}" + (f"/{ol[r]:.4g}" if abs(ol[r] - o[r]) > 1e-9 else "") + "%" for r in RAR if o[r])
            print(f"  {k:13s} {cells}  (Legendary or better 1 in {100 / up:,.0f})" if up else f"  {k:13s} {cells}")
        print("\n  Climb steps: " + ", ".join(f"{t} {plan['climb']['chain'][t] * 100:g}%" for t in TIERS[:-1])
              + f"; the Grand Opening Luck ({plan['luck_days']:g} days): "
              + ", ".join(f"{t} {plan['climb']['launch_chain'][t] * 100:g}%" for t in TIERS[:-1]
                          if plan['climb']['launch_chain'][t] != plan['climb']['chain'][t]))
    print(f"Plan {plan['name']}: each odds row (percent, each row adds to 100), 1 in N for the rare ones\n")
    for k, row in plan["rows"].items():
        cells = []
        for r in OUTS:
            if row.get(r):
                v = row[r]
                cells.append(f"{r} {v:g}%" + (f" (1 in {100 / v:,.0f})" if v < 1 else ""))
        print(f"  {k:13s} " + ", ".join(cells))
    print("\n  Mystery block, " + ("turns into" if plan.get("unified") else "final tier") + ": "
          + ", ".join(f"{t} {plan['tier'][t]:g}%" for t in TIERS if plan["tier"][t] or not plan.get("unified")))
    pm = per_mystery(plan)
    print("  Mystery block, per cue rarity: " + ", ".join(f"{r} {pm[r]:.4g}%" + (f" (1 in {100 / pm[r]:,.0f})" if pm[r] < 1 else "") for r in RAR))
    print(f"  Ends above Standard: {100 - plan['tier']['Standard']:g}%   pity: Rare by {plan['pity']['Rare']}, Epic by {plan['pity']['Epic']}"
          + (f" (a new save starts at {plan['pity_start'][0]} and {plan['pity_start'][1]})" if any(plan.get("pity_start", ())) else ""))
    print()


# The Robux value ladder (v4): what one cue of each rarity is worth to the price list, in R$.
# Set so the known restock blocks come out a little above fair (1.0-1.5x) and the Mystery block,
# the gamble, a little better again. In dollars at the phone price of Robux (400 R$ for $4.99):
# Rare $0.37, Epic $3, Legendary $19, Mythic $75, Secret $620 (designer, 2026-10-08: most cues
# at most a few dollars, Mythic tens of dollars, the Secret $100 or more).
LADDER = {"Common": 1, "Uncommon": 3, "Rare": 30, "Epic": 250, "Legendary": 1500, "Mythic": 6000, "Secret": 50000}
# The designer's words as R$ ranges (80 R$ a dollar): under $1, a few dollars, between, tens of
# dollars, $100 or more.
FEEL = {"Rare": (8, 80), "Epic": (80, 400), "Legendary": (400, 2400), "Mythic": (800, 8000), "Secret": (8000, 80000)}


def value_ladder(plan):
    """R$ to pull one cue of each rarity (Rare and up), by every Robux route, at the list price."""
    pm = per_mystery(plan)
    routes = []
    r1, r10 = plan["mystery_robux"]
    bulk = plan.get("robux_bulk", 10)
    routes.append(("Mystery block (1)", r1, pm))
    routes.append((f"Mystery block ({bulk}-pack)", r10 / bulk, pm))
    g1, g3, g10 = plan["go_robux"]
    routes.append(("Grand Opening (10-pack)", g10 / 10, {r: plan["rows"]["GrandOpening"].get(r, 0) for r in RAR}))
    for k, (_, _, _, rp, _) in plan["restock"].items():
        if rp:
            # Economy v5: a restock block arrives unclimbed and climbs from its tier.
            routes.append((f"Restock {k} block", rp, per_block(plan, k)))
    st = plan["starter"]
    print(f"Plan {plan['name']}: Robux to pull one cue of each rarity or better (R$ per block / chance of that rarity or better)\n")
    print(f"  {'route':26s} {'R$':>6s} " + " ".join(f"{r:>12s}" for r in RAR[2:]))
    best = {}
    for name, price, odds in routes:
        cells = []
        for k, r in enumerate(RAR[2:], start=2):
            up = sum(odds.get(x, 0) for x in RAR[k:])
            cost = price / (up / 100) if up else math.inf
            best[r] = min(best.get(r, math.inf), cost)
            cells.append(f"{cost:12,.0f}" if cost < math.inf else f"{'-':>12s}")
        print(f"  {name:26s} {price:6,.1f} " + " ".join(cells))
    print(f"\n  {'cheapest':26s} {'':6s} " + " ".join(f"{best[r]:12,.0f}" for r in RAR[2:]))
    print(f"  {'feel (designer)':26s} {'':6s} " + " ".join(f"{FEEL[r][0]:>5,}-{FEEL[r][1]:<6,}" if r in FEEL else f"{'':12s}" for r in RAR[2:]))
    # Each product's expected worth on the ladder (LADDER below) against its price: near 1 is a
    # fair pull; a known block (restock) a little under 1 (you pay for knowing the tier).
    print(f"\n  Worth on the ladder ({', '.join(f'{r} {v:,}' for r, v in LADDER.items())} R$) per R$ paid:")
    for name, price, odds in routes + [("Starter Pack (block only)", st["robux"], {r: plan["rows"]["Starter"].get(r, 0) for r in RAR})]:
        ev = sum(odds.get(r, 0) / 100 * LADDER[r] for r in RAR)
        print(f"    {name:28s} worth {ev:9,.1f} R$ for {price:7,.1f} R$  = {ev / price:4.2f}")
    rate = plan["packs"][-1][1] / plan["packs"][-1][0]
    hour = 60 / MIN_PER_MATCH * (plan["win_pay"] + plan["loss_pay"]) / 2
    print(f"\n  Money: ${hour:,.0f} an hour of Classic; the biggest pack ${rate:,.0f} a Robux; 1 hour of play = {hour / rate:.0f} R$ of packs.")
    print("  Money price against Robux (hours of play; how many times more the money route costs than the direct Robux price):")
    rows = [("Mystery block", plan["mystery_money"], r1), ("Grand Opening block", plan["go_money"], g1)]
    for k, (_, _, mp, rp, _) in plan["restock"].items():
        rows.append((f"Restock {k}", mp, rp))
    for name, mp, rp in rows:
        ratio = f"{mp / (rp * rate):4.1f}x" if rp else "   -"
        print(f"    {name:22s} ${mp:>10,} = {mp / hour:6.1f} h    {rp if rp else '-':>5} R$   money route costs {ratio} the Robux price at the best pack")
    print()


def copies_report(plan, out):
    """When the first 100 copies of one cue of each rarity are gone (the GUI session's copy numbers)."""
    cbd = out["copies_by_day"]
    print(f"Plan {plan['name']}: copies of ONE cue of each rarity over time (copies of the rarity / cues of it), and the day its first 100 are gone\n")
    for r in ["Rare", "Epic", "Legendary", "Mythic", "Secret"]:
        k = OUTS.index(r)
        per = [c[k] / CUES[r] for c in cbd]
        gone = next((d + 1 for d, x in enumerate(per) if x >= 100), None)
        print(f"  {r:10s} day 7 {per[6]:9,.1f}  day 30 {per[29]:9,.1f}  day 60 {per[59]:9,.1f}   first 100 gone: "
              + (f"day {gone}" if gone else f"after day 60 (about day {60 * 100 / max(per[59], 1e-9):,.0f} at this pace)"))
    for r in ["Firework", "Beta"]:
        k = OUTS.index(r)
        print(f"  {r:10s} day 7 {cbd[6][k]:9,.0f}  day 21 {cbd[20][k]:9,.0f}  (one cue; numbered every copy)")
    w1 = out.get("week_one_given")
    if w1 and w1[-1]:
        gone = next((d + 1 for d, x in enumerate(w1) if x >= 100), None)
        print(f"  {'Week One':10s} day 7 {w1[6]:9,.1f}  day 30 {w1[29]:9,.1f}  day 60 {w1[59]:9,.1f}   first 100 gone: "
              + (f"day {gone}" if gone else "after day 60") + "  (one cue, given on first-week day 7)")
    print()


def exists_report(plan, out, day=30, min_exists=10):
    """Config.Trade's fallback block worths (economy v5 plan section 8): a block's worth is the sum
    over cues of (its chance of that cue) / (that cue's copies in existence); BlockExists is
    1 / that worth at `day` for an unclimbed block (the climb from its start, no luck: the launch
    luck is over by day 30) or a kind that never climbs, ClimbedExists for a climbed block of each
    tier (exactly its rarity). Rounded to 2 significant figures, as Config keeps them."""
    made = out["copies_by_day"][day - 1]  # copies made so far, by outcome (none sold here)
    per_cue = {r: max(made[k] / CUES.get(r, 1), min_exists) for k, r in enumerate(OUTS)}

    def worth(odds):
        return sum(p / 100 / per_cue[r] for r, p in odds.items() if p and r in per_cue)

    def sig2(x):
        e = 10 ** max(int(math.floor(math.log10(x))) - 1, 0)
        return int(round(x / e) * e)

    kinds = ["Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Mystery", "GrandOpening", "Lucky8", "Sky",
             "Starter", "Gift"]
    print(f"Plan {plan['name']}: copies in existence per cue at day {day}: "
          + ", ".join(f"{r} {v:,.0f}" for r, v in per_cue.items()))
    print("  BlockExists = {")
    for k in kinds:
        odds = per_block(plan, k)
        if "GrandOpening" == k:
            odds = dict(odds, **{u: plan["rows"]["GrandOpening"].get(u, 0) for u in ("Firework", "Beta")})
        w = worth(odds)
        print(f"    {k} = {sig2(1 / w)},")
    print("  },")
    print("  ClimbedExists = {")
    for t in TIERS[:-1]:
        w = worth(plan["rows"][t])
        print(f"    {t} = {sig2(1 / w)},")
    print("  },")
    print()


REF_PLAYERS = [
    ("Free, 30 min a day", {"minutes": 30}),
    ("Free, 1 h a day", {"minutes": 60}),
    ("Free, 3 h a day", {"minutes": 180}),
    ("VIP, 1 h a day", {"minutes": 60, "vip": True}),
    ("Small spender: VIP, 1 h, 500 R$ a month", {"minutes": 60, "vip": True, "budget": 500}),
    ("Big spender: VIP, 3 h, 5,000 R$ a month", {"minutes": 180, "vip": True, "budget": 5000}),
]
REF_SNAPS = (1, 2, 7, 30)
FIRST_SESSION_MIN = 20  # "the first session": the first 20 minutes of play (Roblox's median session is ~10 min)
KIND_ORDER = ["Mystery", "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Starter", "GrandOpening", "Sky", "Lucky8",
              "Gift"]


def players(plan, n=1000):
    print(f"Plan {plan['name']}: what a player gets ({n} identical players each, 50% win rate, every day from launch;")
    print("money earned counts everything, before spending; blocks are averages per player; free players spend 70% of their")
    print("money on Mystery blocks and spins each day; spenders spend their Robux as the population does).\n")
    for name, ref in REF_PLAYERS:
        print(f"  {name}")
        print(f"    {'':16s} {'money earned':>13s}  {'own one: Epic / Legendary / Mythic / Secret':44s} blocks received")
        first = Sim(plan, days=1, ref=dict(ref, n=n, minutes=min(ref["minutes"], FIRST_SESSION_MIN))).run()["snaps"][1]
        res = Sim(plan, days=31, ref=dict(ref, n=n)).run()["snaps"]
        for label, sn in [(f"first {FIRST_SESSION_MIN} min", first)] + [(f"day {d}", res[d]) for d in REF_SNAPS]:
            own = " / ".join(f"{sn['own'][OUTS.index(r)] * 100:5.1f}%" for r in ("Epic", "Legendary", "Mythic", "Secret"))
            blocks = ", ".join(f"{k} {sn['received'][k]:.1f}" for k in KIND_ORDER if sn["received"].get(k, 0) >= 0.05)
            extra = f"  (Robux spent {sn['robux']:,.0f})" if sn["robux"] else ""
            print(f"    {label:16s} ${sn['earned']:>12,.0f}  {own:44s} {blocks}{extra}")
        print()


def summary(rows):
    print("Players active in the last 7 days who own at least one (day 7 / 30 / 60):\n")
    print(f"  {'plan':16s} " + " ".join(f"{r:>24s}" for r in ("Epic", "Legendary", "Mythic", "Secret", "Firework", "Beta", "WeekOne")))
    for label, out in rows:
        cells = []
        for r in ("Epic", "Legendary", "Mythic", "Secret", "Firework", "Beta"):
            cells.append("/".join(f"{out[d][r][0] * 100:.2f}" for d in REPORT) + "%")
        cells.append("/".join(f"{out[d]['WeekOne'] * 100:.2f}" for d in REPORT) + "%" if "WeekOne" in out[REPORT[0]] else "-")
        print(f"  {label:16s} " + " ".join(f"{c:>24s}" for c in cells))
    print("\n  The plan's numbers (economy v5.1, 2026-10-09, about the simulation's noise either side):")
    for r in ("Epic", "Legendary", "Mythic", "Secret"):
        print(f"    {r:10s} " + "  ".join(f"day {d}: {TARGETS[d][r][0]:g}-{TARGETS[d][r][1]:g}%" for d in REPORT))
    print("    WeekOne    " + "  ".join(f"day {d}: {PLAN_V5[d]['WeekOne']:g}%" for d in REPORT))
    for label, out in rows:
        miss = [f"{r} day {d} {out[d][r][0] * 100:.2f}%" for d in REPORT for r in TARGETS[d]
                if not TARGETS[d][r][0] <= out[d][r][0] * 100 <= TARGETS[d][r][1]]
        print(f"  {label}: " + ("every number near the plan's" if not miss else "away from the plan: " + ", ".join(miss)))
    print()



# ---------------------------------------------------------------- the rank ladder (Config.Ranks)
class Ladder:
    def __init__(self, c):
        rk = c["Ranks"]
        self.tiers = rk["Tiers"]
        self.base = rk["BaseXp"]
        self.mode_xp = rk["ModeXp"]
        self.gap = rk["Gap"]
        self.pc = rk["PcXp"]
        self.streak_from, self.streak = rk["Boosts"]["StreakFrom"], rk["Boosts"]["Streak"]
        self.widths = rk["DivisionXp"]
        self.starts = [0]
        for t in self.tiers[:-1]:
            for w in self.widths[t]:
                self.starts.append(self.starts[-1] + w)
        self.reyes_xp = self.starts.pop()
        self.strict_div = self.tiers.index(self.gap["StrictFromTier"]) * 5 + 1

    def division_of(self, xp):
        """1..45 (Bronze I ... Grandmaster V), 46 Reyes."""
        return 46 if xp >= self.reyes_xp else bisect.bisect_right(self.starts, xp)

    def tier_of(self, div):
        return self.tiers[min((div - 1) // 5, len(self.tiers) - 1)]

    def gap_factor(self, gap, my_div):
        strict = my_div >= self.strict_div
        scale = self.gap["StrictScale"] if strict else self.gap["Scale"]
        floor = self.gap["StrictFloor"] if strict else self.gap["Floor"]
        e = 1 / (1 + 10 ** (-gap / scale))
        return min(max(2 * (1 - e), floor), self.gap["Max"])

    def xp_after(self, xp, won, mode, opp_div, streak=0):
        div = self.division_of(xp)
        row = self.base[self.tier_of(div)]
        f = self.gap_factor(div - opp_div, div)
        if won:
            d = row["Win"] * self.mode_xp[mode] * f * (1 + self.streak if streak >= self.streak_from else 1)
        else:
            d = row["Loss"] * self.mode_xp[mode] * min(f, self.gap["LossMax"])
        return xp + d


LADDER_MIX = MODE_MIX  # tables played once Gold unlocks the harder ones
BETWEEN_MATCH_MINUTES = 1.5  # end screen, rematch, walking to a pad
MATCH_MINUTES = {"Classic": 6.5, "Difficult": 7.5, "Challenger": 8.5}  # break to last ball


def ladder_hours(L, p, classic_only):
    out, h = {}, 0.0
    gold = L.tiers.index("Gold")
    for i, tier in enumerate(L.tiers[:-1]):
        out[tier] = h
        mix = {"Classic": 1.0} if classic_only or i < gold else LADDER_MIX
        ev = mins = 0.0
        for mode, f in mix.items():
            ww = L.base[tier]["Win"] * L.mode_xp[mode] * (1 + L.streak * p * p)
            ev += f * (p * ww + (1 - p) * L.base[tier]["Loss"] * L.mode_xp[mode])
            mins += f * (MATCH_MINUTES[mode] + BETWEEN_MATCH_MINUTES)
        h += sum(L.widths[tier]) / ev * mins / 60
    out[L.tiers[-1]] = h
    return out


def cmd_ranks(c, args, new_per_day=2000, seed=3, report_days=(90, 180, 365)):
    """A year of players on the ladder: arrivals, heavy-tailed lifetimes, half the matches against
    near-rank players (80% from Diamond), win chance by skill (sharper on harder tables)."""
    L = Ladder(c)
    rng = random.Random(seed)
    k_mode = {"Classic": 1.0, "Difficult": 1.3, "Challenger": 1.6}  # skill matters more on harder tables
    skill, minutes, life, joined, xp, streak = [], [], [], [], [], []
    gold = L.tiers.index("Gold")

    def mode_for(div):
        if (div - 1) // 5 < gold:
            return "Classic"
        r, acc = rng.random(), 0.0
        for m, f in LADDER_MIX.items():
            acc += f
            if r < acc:
                return m
        return "Classic"

    for day in range(args.days):
        for _ in range(new_per_day):
            lt = int(min((rng.paretovariate(0.9) - 1) * 2 + 1, 800))
            skill.append(rng.gauss(0, 1))
            life.append(lt)
            minutes.append(min(rng.lognormvariate(math.log(25), 0.8) * (1 + math.log1p(lt) / 3), 360))
            joined.append(day)
            xp.append(-1.0)
            streak.append(0)
        idx = [p for p in range(len(skill)) if day - joined[p] < life[p] and rng.random() < 0.7]
        n_matches = {p: int(minutes[p] / 9.0) for p in idx}
        avg_ccu = sum(minutes[p] for p in idx) / 1440
        for r in range(max(n_matches.values(), default=0)):
            players = [p for p in idx if n_matches[p] > r]
            if len(players) < 2:
                break
            divs = {p: L.division_of(max(xp[p], 0)) for p in players}
            near = [p for p in players if rng.random() < (0.8 if divs[p] >= 21 else 0.5)]
            near_set = set(near)
            near.sort(key=lambda p: divs[p] + rng.gauss(0, 2))
            rest = [p for p in players if p not in near_set]
            rng.shuffle(rest)
            order = near + rest
            for a, b in zip(order[0::2], order[1::2]):
                da, db = divs[a], divs[b]
                mode = mode_for(max(da, db))
                a_won = rng.random() < 1 / (1 + math.exp(-k_mode[mode] * (skill[a] - skill[b])))
                streak[a] = streak[a] + 1 if a_won else 0
                streak[b] = 0 if a_won else streak[b] + 1
                if xp[a] >= 0 or a_won:
                    xp[a] = L.xp_after(max(xp[a], 0.0), a_won, mode, db, streak[a])
                if xp[b] >= 0 or not a_won:
                    xp[b] = L.xp_after(max(xp[b], 0.0), not a_won, mode, da, streak[b])
        if day + 1 in report_days:
            alive = [p for p in range(len(skill)) if day - joined[p] < life[p] and xp[p] >= 0]
            peak = avg_ccu * 2  # peak is about twice the daily average on Roblox
            print(f"Day {day + 1}: {len(alive):,} ranked players still playing, about {peak:,.0f} peak CCU")
            print(f"  {'tier':12s} {'playing':>8s} {'share':>7s} {'per 1k CCU':>11s} {'mean skill':>11s}")
            for t in L.tiers:
                here = [p for p in alive if L.tier_of(L.division_of(xp[p])) == t]
                ms = f"{sum(skill[p] for p in here) / len(here):+.2f}" if here else "   -"
                print(f"  {t:12s} {len(here):8d} {len(here) / max(len(alive), 1) * 100:6.2f}% {len(here) / max(peak, 1) * 1000:11.1f} {ms:>11s}")
            print()



def rank_tables(c, plan):
    """Match money per hour, and the rank ladder: hours to each tier, the opponent-gap factor."""
    dm = c["DifficultyMoney"] if c["Economy"]["UseDifficultyMultiplier"] else {m: 1 for m in MODE_MIX}
    print("Match money (50% win rate, no boosts)\n")
    for mode in MODE_MIX:
        per = (plan["win_pay"] + plan["loss_pay"]) / 2 * dm[mode]
        print(f"  {mode:10s} ${per:6,.0f} a match, about ${per * 60 / MIN_PER_MATCH:7,.0f} an hour")
    L = Ladder(c)
    print(f"\nRank XP: each tier's divisions (Reyes at {L.reyes_xp:,} XP); Classic wins against equals to reach it\n")
    for (wins, rw), t in zip(plan["ranks"], L.tiers):
        widths = f"{L.widths[t]}  total {sum(L.widths[t]):>9,}" if t in L.widths else ""
        print(f"  {t:12s} {wins:5,} wins  reward {rw}  {widths}")
    names = L.tiers[1:]
    for label, classic in (("Classic only", True), (f"mode mix from Gold {LADDER_MIX}", False)):
        print(f"\n  Hours to reach each tier, equal opponents, {label}\n  win rate " + "".join(f"{t[:6]:>8s}" for t in names))
        for wr in (0.45, 0.5, 0.55, 0.6):
            hs = ladder_hours(L, wr, classic)
            print(f"  {int(wr * 100):3d}%     " + "".join(f"{hs[t]:7.0f}h" for t in names))
    print("\nOpponent-gap factor on a win (gap in divisions; + means you are higher)\n")
    for label, d in (("Bronze to Diamond", 20), (f"{L.gap['StrictFromTier']} and up", 30)):
        print(f"  {label:18s} " + "  ".join(f"{gp:+d}: x{L.gap_factor(gp, d):4.2f}" for gp in (-5, -3, -1, 0, 1, 3, 5, 8, 10, 15)))
    print()


def sell_rules(c):
    """--sell: finder's money (Config.Index.FindMoney), the Index rows' money (Config.Index.Rows)
    and the sell-back prices (Config.BlockOdds.SellBack)."""
    return {"find": c["Index"]["FindMoney"], "rows": {r: row["Money"] for r, row in c["Index"]["Rows"].items()},
            "back": c["BlockOdds"]["SellBack"]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="?", default="sim",
                    choices=["sim", "tables", "value", "players", "copies", "exists", "ranks"])
    ap.add_argument("--built-only", action="store_true", help="switch the planned, not yet built features off")
    ap.add_argument("--before", action="store_true", help="the economy before v4 (frozen, for comparison)")
    ap.add_argument("--compare", action="store_true", help="before v4, v4 (frozen), v5 built only and v5 side by side")
    ap.add_argument("--sell", action="store_true", help="add finder's money, the Index rows and selling duplicates back")
    ap.add_argument("--retention", default="plan", choices=list(RETENTION))
    ap.add_argument("--sample", type=float, default=SAMPLE, help="share of the real player base simulated")
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--days", type=int, default=365, help="days for the ranks sim")
    args = ap.parse_args()
    set_retention(args.retention)
    c = load_config()
    v5 = plan_from_config(c, args.built_only)
    built = plan_from_config(c, True)
    for k in ("win_pay", "loss_pay", "streak_bonus", "boosts", "mode_money", "unlock_wins", "ranks"):
        BEFORE.setdefault(k, built[k])
    plan = BEFORE if args.before else v5
    sell = sell_rules(c) if args.sell else None
    if args.what == "tables":
        tables(plan)
        rank_tables(c, plan)
    elif args.what == "value":
        value_ladder(plan)
    elif args.what == "players":
        players(plan)
    elif args.what == "copies":
        copies_report(plan, Sim(plan, args.seed, args.sample, sell=sell).run())
    elif args.what == "exists":
        exists_report(plan, Sim(plan, args.seed, args.sample).run())
    elif args.what == "ranks":
        cmd_ranks(c, args)
    elif args.compare:
        with open(CONFIG_V4_JSON) as f:
            v4 = plan_from_config(json.load(f))
        CUES.clear()
        CUES.update(c["BlockCues"])  # the v4 export refilled them; the counts are the same
        summary([(p["name"], Sim(p, args.seed, args.sample).run()) for p in (BEFORE, v4, built, plan_from_config(c))])
    else:
        out = Sim(plan, args.seed, args.sample, sell=sell).run()
        show_run(out, plan["name"] + (" + selling" if sell else ""))
        if sell:
            mm = max(out["match_money"], 1)
            print("  Money over 60 days beside match money: "
                  + ", ".join(f"{k} {v / mm * 100:.1f}%" for k, v in out["extra_money"].items())
                  + f" (all {sum(out['extra_money'].values()) / mm * 100:.1f}%)\n")
        summary([(plan["name"], out)])


if __name__ == "__main__":
    main()
