#!/usr/bin/env python3
"""Economy model for Crazy 8 Ball: the approved economy plan's 60-day player-population simulation,
reading every game number from src/shared/Config.luau (through tools/economy_config.json).

    python3 tools/economy_model.py               # the 60-day population sim, day-30 check vs targets
    python3 tools/economy_model.py --plan-only   # the same with every addition switched off (the plan's sim)
    python3 tools/economy_model.py --without group,codes   # switch some additions off
    python3 tools/economy_model.py --compare     # plan-only, full, and full minus each addition, side by side
    python3 tools/economy_model.py --like-codes  # also hand out the like-milestone codes
    python3 tools/economy_model.py tables        # odds per Mystery block, money per hour, rank ladder hours, gap factors
    python3 tools/economy_model.py shop          # money packs, restock shop, prices in Robux and hours
    python3 tools/economy_model.py loot          # reference players: hours and days to a first Epic ... Secret
    python3 tools/economy_model.py hours         # (same as loot)
    python3 tools/economy_model.py supply        # cues entering the game per day at 500 / 2k / 10k peak CCU
    python3 tools/economy_model.py ranks         # a year of players on the rank ladder (slow, a few minutes)

The numbers come from tools/economy_config.json, which tools/export_economy.luau writes from Config
(this script runs it through Lune when the JSON is missing or older than Config). Everything else
(how players behave) is an ASSUMPTION constant below, each with a one-line comment.

Not modelled: sell-back money, the Starter Pack, Money Party, timer skips, Limited cues, trading,
the restock Legendary block's 25-worldwide cap, anti-farm and PC/bot money rules.
Nothing here runs in the game. Python 3 standard library only.
"""

import argparse
import bisect
import json
import math
import random
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_JSON = ROOT / "tools" / "economy_config.json"
EXPORTER = "tools/export_economy.luau"
SOURCES = [ROOT / "src/shared/Config.luau", ROOT / "src/shared/Progression/Catalog.luau", ROOT / EXPORTER]

# ------------------------------------------------------------------------------------------------
# Targets (the designer, plan 2026-10-02): share of players active in the last 7 days who own one
# of the rarity at day 30.
# ------------------------------------------------------------------------------------------------
TARGETS = {"Epic": 5.0, "Legendary": 1.0}  # percent, "about"
CAPS = {"Mythic": 0.5, "Secret": 0.05}  # percent, at most (Secret "far rarer": a tenth of Mythic's cap)
DRIFT_LIMIT = 0.20  # flag a metric more than 20% from its target

# ------------------------------------------------------------------------------------------------
# Population assumptions (the plan's economy_sim.py, unchanged)
# ------------------------------------------------------------------------------------------------
SEED = 1  # the plan's seed
SAMPLE = 1.0  # share of the real player base simulated (the plan used 0.3; the whole base cuts the noise)
DAYS = 60  # days simulated
REPORT_DAYS = (30, 60)  # days reported
ARRIVALS_DAY0 = 1700  # new players on launch day (real scale; ~500 peak CCU in week 1)
ARRIVAL_GROWTH = 1.055  # arrivals grow this much a day...
GROWTH_DAYS = 40  # ...for this many days, then stay flat (~5k peak CCU by day 45-60)
ONE_DAY_SHARE = 0.55  # players who play one day and never return
LIFE_MIN, LIFE_SHAPE, LIFE_SCALE, LIFE_CAP = 2, 0.75, 3, 2000  # the rest: 2 + Lomax(0.75) x 3 days, capped
PLAY_CHANCE = 0.62  # chance a still-playing player shows up on a given day
MINUTES_MEDIAN, MINUTES_SIGMA = 22, 0.85  # minutes on a day played: lognormal median and spread...
MINUTES_ENGAGEMENT = 2.5  # ...times (1 + ln(1 + lifetime days) / this): stayers play longer
MINUTES_CAP = 420  # no one plays more than 7 h a day
DAY_SPREAD = (0.6, 1.4)  # each day's minutes vary by this factor
WIN_RATE_MEAN, WIN_RATE_SD, WIN_RATE_RANGE = 0.5, 0.06, (0.3, 0.72)  # win rate per player
MIN_PER_MATCH = 8.0  # minutes per match including the end screen (7.5 matches an hour)
PAYER_SHARE_STAYERS, PAYER_SHARE_OTHERS = 0.06, 0.012  # pay Robux: lifetime 7+ days / shorter
BUDGET_MEDIAN, BUDGET_SIGMA, BUDGET_CAP = 450, 1.2, 40000  # a payer's Robux a month (lognormal)
BUDGET_DAYS = 20  # a payer spends budget / this on each day played
VIP_SHARE_OF_PAYERS = 0.4  # payers who own VIP
SAVER_SHARE = 0.3  # players who never buy Mystery blocks (save for the restock shop / Limited)
MYSTERY_SPEND_SHARE = 0.7  # the others spend this share of their balance on Mystery blocks each day
WINNER_BALLS, LOSER_BALLS = 7.5, 4.0  # balls that pay the winner / loser in a match
WINNER_NICE, LOSER_NICE = 0.5, 0.3  # nice shots per match, winner / loser
PAYER_PACKS = ("Pack3", "Pack4", "Pack5", "Pack6", "Pack7")  # packs a payer buys (average money per Robux)

# ------------------------------------------------------------------------------------------------
# The additions the plan's sim lacked (each can be switched off; --plan-only switches all off)
# ------------------------------------------------------------------------------------------------
PLAN_PLAYTIME_MAX_MINUTES = 90  # the plan's sim had playtime gifts up to 90 min (no 120-min Rare block)
GROUP_JOIN_SHARE = 0.30  # players who join the group on their first day (3 Mystery blocks, +10% money)
MODE_MIX = {"Classic": 0.5, "Difficult": 0.3, "Challenger": 0.2}  # tables played once harder ones unlock
INVITED_SHARE = 0.05  # new players who arrive through a friend's invite
CODE_REDEEM_SHARE = 0.7  # new players who redeem the launch codes (WELCOME, 8BALL, ROOFTOP) on day 1
LAUNCH_UNIX = 1793491200  # assumed release, 2026-11-01 UTC (a code's Expires is checked against it)
LIKE_CODE_DAYS = {"LIKES1K": 5, "LIKES5K": 12, "LIKES10K": 20, "LIKES25K": 35, "LIKES50K": 50, "LIKES100K": 75}  # day each is switched on
LIKE_CODE_REDEEM_SHARE = 0.4  # active players who redeem a like code once it is on (only with --like-codes)
RESTOCK_BUYER_SHARE = 0.2  # players who buy the restock Rare and Uncommon slots when they have the money
RESTOCK_VISITS_PER_DAY = 1  # restocks such a player buys from in a day
PLUS_SHARE = 0.12  # players with Roblox Plus (Premium), an estimate: +Economy.PlusBoost match money
SPIN_SPEND_SHARE = 0.10  # share of a spender's daily spend that goes on ability spins (money sink)
EXTRAS = {
    "playtime120": "the 120-minute playtime Rare block",
    "group": "group: 3 Mystery blocks once, +10% match money",
    "difficulty": "difficulty money multiplier (and mode XP) once Gold unlocks harder tables",
    "invites": "invites: both players get a Rare block, 5 a month cap",
    "codes": "launch codes (WELCOME, 8BALL, ROOFTOP; like codes only with --like-codes)",
    "restock": "restock Rare and Uncommon slots (and VIP's extra Rare)",
    "streak": "win-streak money and XP (3rd win in a row on)",
    "rankSteps": "rank money for each new division II-V",
    "index": "finder's money and Index row money",
    "spins": "ability spins bought with money (a sink)",
    "bulk": "Mystery blocks bought 10 at a time at the bulk price when the money allows",
    "plus": "Roblox Plus members: +10% match money (about 12% of players)",
}

RAR = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
SRC = ["win drops", "mystery (money)", "restock shop", "login + track", "playtime", "rank rewards", "group/invite/codes"]


# ------------------------------------------------------------------------------------------------
# Config (through the Lune exporter)
# ------------------------------------------------------------------------------------------------
def load_config():
    stale = not CONFIG_JSON.exists() or any(CONFIG_JSON.stat().st_mtime < s.stat().st_mtime for s in SOURCES if s.exists())
    if stale:
        if shutil.which("lune") is None:
            sys.exit(f"{CONFIG_JSON.name} is missing or older than Config.luau, and Lune is not installed to rebuild it.\n"
                     f"Install Lune (see docs/STUDIO_NOTES.md), then run: lune run {EXPORTER}")
        r = subprocess.run(["lune", "run", EXPORTER], cwd=ROOT, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"lune run {EXPORTER} failed:\n{r.stdout}{r.stderr}")
    with open(CONFIG_JSON) as f:
        return json.load(f)


class Game:
    """The Config numbers the simulation uses, in handy shapes."""

    def __init__(self, c):
        self.c = c
        cs = c["BlockOdds"]
        self.cases = cs["Order"]
        self.total = cs["OddsTotal"]
        assert cs["Rarities"] == RAR, cs["Rarities"]
        drop = cs["Drop"]
        self.drop_cum = self._cum([drop["Weights"].get(k, 0) for k in self.cases])
        self.case_cum = [self._cum([cs["List"][k]["Odds"].get(r, 0) for r in RAR]) for k in self.cases]
        self.pity_rare, self.pity_epic = drop["PityRare"], drop["PityEpic"]
        self.first_win = self.cases.index(drop["FirstWin"])
        self.RARE, self.EPIC = self.cases.index("Rare"), self.cases.index("Epic")
        e = c["Economy"]
        nice = sum(e["NiceShotPay"].values()) / len(e["NiceShotPay"])
        self.win_pay = WINNER_BALLS * e["BallPay"] + WINNER_NICE * nice + e["WinBonus"]
        self.loss_pay = LOSER_BALLS * e["BallPay"] + LOSER_NICE * nice + e["LossBonus"]
        self.streak_bonus = e["StreakBonus"]
        self.vip_boost, self.group_boost = e["VipBoost"], e["GroupBoost"]
        self.plus_boost = e.get("PlusBoost", 0)
        dm = c["DifficultyMoney"] if e["UseDifficultyMultiplier"] else {k: 1 for k in MODE_MIX}
        self.mode_money = sum(MODE_MIX[m] * dm[m] for m in MODE_MIX)
        rk = c["Ranks"]
        self.mode_xp = sum(MODE_MIX[m] * rk["ModeXp"][m] for m in MODE_MIX)
        self.streak_xp = rk["Boosts"]["Streak"]
        self.win_xp = rk["BaseXp"]["Bronze"]["Win"]
        packs = {p["Key"]: p for p in c["Packs"]}
        self.money_per_robux = sum(packs[k]["Money"] / packs[k]["Robux"] for k in PAYER_PACKS) / len(PAYER_PACKS)
        self.mystery = c["Shop"]["Mystery"]["Price"]
        self.bulk_count, self.bulk_price = c["Shop"]["Mystery"]["BulkCount"], c["Shop"]["Mystery"]["BulkPrice"]
        self.spin_price = c["Ults"]["Earn"]["MoneyPerSpin"]
        # Rank ladder: XP where each tier (division I) and each division starts.
        tiers = rk["Tiers"]
        self.tiers = tiers
        self.tier_xp, self.div_xp = [], []  # div_xp: (xp, tier) for divisions II-V
        xp = 0
        for t in tiers:
            self.tier_xp.append(max(xp, self.win_xp))  # Bronze I is reached by the first win
            for w in rk["DivisionXp"].get(t, [])[:-1]:
                xp += w
                self.div_xp.append((xp, t))
            xp += rk["DivisionXp"].get(t, [0])[-1]
        self.unlock_tier = min(tiers.index(rk["Unlocks"][m]) for m in ("Difficult", "Challenger"))
        self.tier_reward = [rk["Rewards"]["Tier"][t] for t in tiers]
        self.step_money = rk["Rewards"]["Step"]
        d = c["Daily"]
        self.login, self.track, self.track_days = d["Streak"], d["Track"], d["TrackDays"]
        self.playtime = d["Playtime"]
        codes = d["Codes"]
        self.launch_codes = [codes[k] for k in sorted(codes) if not codes[k].get("Live") and codes[k].get("Expires", 1e18) > LAUNCH_UNIX]
        self.like_codes = [(LIKE_CODE_DAYS[k], codes[k]) for k in sorted(LIKE_CODE_DAYS) if k in codes]
        so = c["Social"]
        self.group_reward = so["GroupReward"]
        self.invite_case = self.cases.index(so["InviteBlock"])
        self.invites_per_month = so["InvitesPerMonth"]
        rs = c["Shop"]["Restock"]
        ct = rs["ChanceTotal"]
        self.slot_minutes = rs["SlotSeconds"] / 60
        self.lucky = [(self.cases.index(rs[k]["Case"]), rs[k + "Chance"] / ct, rs[k]["Price"]) for k in ("Epic", "Legendary")]
        self.rare_slot = (self.cases.index(rs["Rare"]["Case"]), rs["RareChance"] / ct, rs["Rare"]["Price"], rs["Rare"]["Stock"])
        self.unc_slot = (self.cases.index(rs["Uncommon"]["Case"]), rs["Uncommon"]["Price"], rs["Uncommon"]["Stock"])
        self.vip_slot = (self.cases.index(rs["Vip"]["Case"]), rs["Vip"]["Price"], rs["Vip"]["Stock"])
        self.cue_count = [c["BlockCues"].get(r, 0) for r in RAR]
        ix = c["Index"]
        self.find_money = [ix["FindMoney"].get(r, 0) for r in RAR]
        self.row_money = [ix["Rows"].get(r, {}).get("Money", 0) for r in RAR]

    def _cum(self, weights):
        assert sum(weights) == self.total, (weights, self.total)
        out, acc = [], 0
        for w in weights:
            acc += w
            out.append(acc)
        return out

    def per_drop_odds(self):
        """Each rarity's chance per Mystery block, no pity (fractions)."""
        p = [0.0] * 7
        w = self.c["BlockOdds"]["Drop"]["Weights"]
        for k in self.cases:
            for i, r in enumerate(RAR):
                p[i] += w.get(k, 0) / self.total * self.c["BlockOdds"]["List"][k]["Odds"].get(r, 0) / self.total
        return p


# ------------------------------------------------------------------------------------------------
# Small random helpers (stdlib versions of the numpy draws the plan used)
# ------------------------------------------------------------------------------------------------
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


def binomial(rng, n, p):
    return sum(1 for _ in range(n) if rng.random() < p)


# ------------------------------------------------------------------------------------------------
# The population simulation
# ------------------------------------------------------------------------------------------------
def run(g, extras, days=DAYS, sample=SAMPLE, seed=SEED, report=REPORT_DAYS, ref=None, like_codes=False):
    """Simulates the player base day by day. Returns {day: results}, or with `ref` (a cohort of
    identical reference players) the hours played when each first owned each rarity."""
    on = lambda k: k in extras
    pop = random.Random(seed)  # player traits
    act = random.Random(seed + 1000)  # who plays, minutes, matches
    loot = random.Random(seed + 2000)  # block drops and block openings
    xtra = random.Random(seed + 3000)  # decisions of the additions (kept apart so they do not shift the rest)

    if ref:
        arrivals = [ref["n"]] + [0] * (days - 1)
    else:
        arrivals = [int(ARRIVALS_DAY0 * ARRIVAL_GROWTH ** min(d, GROWTH_DAYS) * sample) for d in range(days)]
    N = sum(arrivals)
    joined = [d for d, n in enumerate(arrivals) for _ in range(n)]
    life, minutes, wr, payer, budget, vip, saver = [], [], [], [], [], [], []
    for _ in range(N):
        lt = 1 if pop.random() < ONE_DAY_SHARE else int(min(LIFE_MIN + (pop.paretovariate(LIFE_SHAPE) - 1) * LIFE_SCALE, LIFE_CAP))
        life.append(lt)
        minutes.append(min(pop.lognormvariate(math.log(MINUTES_MEDIAN), MINUTES_SIGMA) * (1 + math.log1p(lt) / MINUTES_ENGAGEMENT), MINUTES_CAP))
        wr.append(min(max(pop.gauss(WIN_RATE_MEAN, WIN_RATE_SD), WIN_RATE_RANGE[0]), WIN_RATE_RANGE[1]))
        pays = pop.random() < (PAYER_SHARE_STAYERS if lt >= 7 else PAYER_SHARE_OTHERS)
        payer.append(pays)
        budget.append(min(pop.lognormvariate(math.log(BUDGET_MEDIAN), BUDGET_SIGMA), BUDGET_CAP) if pays else 0.0)
        vip.append(pays and pop.random() < VIP_SHARE_OF_PAYERS)
        saver.append(pop.random() < SAVER_SHARE)
    group = [xtra.random() < GROUP_JOIN_SHARE for _ in range(N)]
    invited = [xtra.random() < INVITED_SHARE for _ in range(N)]
    redeems = [xtra.random() < CODE_REDEEM_SHARE for _ in range(N)]
    restock_buyer = [xtra.random() < RESTOCK_BUYER_SHARE for _ in range(N)]
    plus_rng = random.Random(seed + 4000)  # its own stream, so switching it on shifts nothing else
    plus = [plus_rng.random() < PLUS_SHARE for _ in range(N)]
    if ref:
        life = [10**6] * N
        minutes = [ref["minutes"]] * N
        wr = [0.5] * N
        payer = [ref.get("payer", False)] * N
        budget = [ref.get("budget", 0)] * N
        vip = [ref.get("vip", False)] * N
        saver = [False] * N

    money = [0.0] * N
    wins = [0] * N
    xp = [0.0] * N
    owned = [[0] * 7 for _ in range(N)]
    rare_p, epic_p = [0] * N, [0] * N
    streak, login_days = [0] * N, [0] * N
    last_active, freeze_week = [-99] * N, [-1] * N
    tier_idx, step_idx = [0] * N, [0] * N  # next tier / division II-V reward to pay
    found = [[0] * 7 for _ in range(N)]  # Index: bitmask of the cues found, per rarity
    row_paid = [0] * N  # Index rows paid (bitmask by rarity)
    like_tried = [0] * N  # like codes already offered (bitmask)
    invites_month = {}  # (inviter, month) -> invite blocks received
    hours = [0.0] * N
    first_hour = {r: [math.inf] * N for r in range(3, 7)} if ref else None
    source = [[0] * 7 for _ in SRC]
    out = {}

    def give_case(p, tier, src):
        r = min(bisect.bisect_right(g.case_cum[tier], loot.random() * g.total), 6)
        owned[p][r] += 1
        source[src][r] += 1
        if first_hour is not None and r >= 3 and first_hour[r][p] > hours[p]:
            first_hour[r][p] = hours[p]
        if on("index") and g.cue_count[r]:
            bit = 1 << loot.randrange(g.cue_count[r])
            if not found[p][r] & bit:
                found[p][r] |= bit
                money[p] += g.find_money[r]
                if g.row_money[r] and found[p][r] == (1 << g.cue_count[r]) - 1 and not row_paid[p] >> r & 1:
                    row_paid[p] |= 1 << r
                    money[p] += g.row_money[r]

    def give_drop(p, src, forced=None):
        if forced is None:
            t = min(bisect.bisect_right(g.drop_cum, loot.random() * g.total), len(g.cases) - 1)
            if t < g.EPIC and epic_p[p] + 1 >= g.pity_epic:
                t = g.EPIC
            elif t < g.RARE and rare_p[p] + 1 >= g.pity_rare:
                t = g.RARE
        else:
            t = forced
        rare_p[p] = 0 if t >= g.RARE else rare_p[p] + 1
        epic_p[p] = 0 if t >= g.EPIC else epic_p[p] + 1
        give_case(p, t, src)

    def give_reward(p, row, src):
        money[p] += row.get("Money", 0)
        blocks = row.get("Blocks", {})
        for _ in range(blocks.get("Mystery", 0)):
            give_drop(p, src)
        for k in g.cases:
            for _ in range(blocks.get(k, 0)):
                give_case(p, g.cases.index(k), src)

    playtime = [row for row in g.playtime if on("playtime120") or row["Minutes"] <= PLAN_PLAYTIME_MAX_MINUTES]
    alive = []  # players still in their lifetime
    for day in range(days):
        wk, month = day // 7, day // 30
        hi = sum(arrivals[: day + 1])
        alive = [p for p in alive if day - joined[p] < life[p]] + list(range(hi - arrivals[day], hi))
        today = [p for p in alive if joined[p] == day or ref or act.random() < PLAY_CHANCE]
        for p in today:
            mins = minutes[p] * (1.0 if ref else act.uniform(*DAY_SPREAD))
            hours[p] += mins / 60
            matches = poisson(act, mins / MIN_PER_MATCH)
            w = binomial(act, matches, wr[p])
            unlocked = on("difficulty") and tier_idx[p] > g.unlock_tier
            boost = 1 + (g.vip_boost if vip[p] else 0) + (g.group_boost if on("group") and group[p] else 0)
            boost += g.plus_boost if on("plus") and plus[p] else 0
            win_pay = g.win_pay + (g.streak_bonus * wr[p] ** 2 if on("streak") else 0)  # 3rd+ win in a row: about wr^2 of wins
            money[p] += (w * win_pay + (matches - w) * g.loss_pay) * (g.mode_money if unlocked else 1) * boost
            # Login loop with the weekly freeze, and the 28-day track.
            gap = day - last_active[p]
            freeze = gap == 2 and freeze_week[p] != wk
            if freeze:
                freeze_week[p] = wk
            streak[p] = streak[p] + 1 if gap == 1 or freeze else 1
            last_active[p] = day
            login_days[p] += 1
            give_reward(p, g.login[(streak[p] - 1) % 7], 3)
            for row in g.track:
                if login_days[p] % g.track_days == row["Day"] % g.track_days:
                    give_reward(p, row, 3)
            # Day one: the group and the launch codes.
            if day == joined[p]:
                if on("group") and group[p]:
                    give_reward(p, g.group_reward, 6)
                if on("codes") and redeems[p]:
                    for row in g.launch_codes:
                        give_reward(p, row, 6)
            if on("codes") and like_codes:
                for i, (d0, row) in enumerate(g.like_codes):
                    if day >= d0 and not like_tried[p] >> i & 1:
                        like_tried[p] |= 1 << i
                        if xtra.random() < LIKE_CODE_REDEEM_SHARE:
                            give_reward(p, row, 6)
            for row in playtime:
                if mins >= row["Minutes"]:
                    give_reward(p, row, 4)
            # Win drops: one per real win; the first ever is the FirstWin case.
            for k in range(w):
                give_drop(p, 0, g.first_win if wins[p] == 0 and k == 0 else None)
            if w and wins[p] == 0 and on("invites") and invited[p]:
                give_case(p, g.invite_case, 6)
                inviters = [q for q in today if joined[q] < day]
                if inviters:
                    q = inviters[xtra.randrange(len(inviters))]
                    if invites_month.get((q, month), 0) < g.invites_per_month:
                        invites_month[(q, month)] = invites_month.get((q, month), 0) + 1
                        give_case(q, g.invite_case, 6)
            wins[p] += w
            xp_win = g.win_xp * (g.mode_xp if unlocked else 1) * (1 + g.streak_xp * wr[p] ** 2 if on("streak") else 1)
            xp[p] += w * xp_win
            # Rank rewards: each tier's division I, and (an addition) each division II-V.
            while tier_idx[p] < len(g.tiers) and wins[p] > 0 and xp[p] >= g.tier_xp[tier_idx[p]]:
                give_reward(p, g.tier_reward[tier_idx[p]], 5)
                tier_idx[p] += 1
            while step_idx[p] < len(g.div_xp) and xp[p] >= g.div_xp[step_idx[p]][0]:
                if on("rankSteps"):
                    money[p] += g.step_money[g.div_xp[step_idx[p]][1]]
                step_idx[p] += 1
            # Robux: payers turn their budget into money on days they play.
            if payer[p]:
                money[p] += budget[p] / BUDGET_DAYS * g.money_per_robux
            # Restock shop: the lucky Epic / Legendary block, bought by anyone who sees it and can pay.
            restocks = int(mins / g.slot_minutes)
            for tier, q, price in g.lucky:
                if loot.random() < 1 - (1 - q) ** restocks and money[p] >= price:
                    money[p] -= price
                    give_case(p, tier, 2)
            # (addition) The Rare and Uncommon slots, and VIP's extra Rare, for players who buy them.
            if on("restock") and restock_buyer[p]:
                for _ in range(min(RESTOCK_VISITS_PER_DAY, restocks)):
                    tier, q, price, stock = g.rare_slot
                    if xtra.random() < q:
                        n = min(stock, int(money[p] // price))
                        money[p] -= n * price
                        for _ in range(n):
                            give_case(p, tier, 2)
                    for tier, price, stock in ([g.vip_slot] if vip[p] else []) + [g.unc_slot]:
                        n = min(stock, int(money[p] // price))
                        money[p] -= n * price
                        for _ in range(n):
                            give_case(p, tier, 2)
            # Mystery blocks with money (and, an addition, ability spins).
            if not saver[p]:
                spend = money[p] * MYSTERY_SPEND_SHARE
                if on("spins"):
                    n = int(spend * SPIN_SPEND_SHARE // g.spin_price)
                    money[p] -= n * g.spin_price
                    spend -= n * g.spin_price
                tens = int(spend // g.bulk_price) if on("bulk") else 0
                spend -= tens * g.bulk_price
                n = int(spend // g.mystery)
                money[p] -= n * g.mystery + tens * g.bulk_price
                n += tens * g.bulk_count
                for _ in range(n):
                    give_drop(p, 1)

        if day + 1 in report:
            ever = [p for p in range(hi) if wins[p] > 0]
            recent = [p for p in ever if day - last_active[p] < 7]
            mins_today = {p: minutes[p] for p in today}
            res = {"ever": len(ever), "recent": len(recent), "player_minutes": sum(mins_today.values())}
            for r in range(3, 7):
                has = lambda p: owned[p][r] > 0
                w_has = sum(m for p, m in mins_today.items() if has(p))
                res[RAR[r]] = (
                    sum(map(has, ever)) / max(len(ever), 1),
                    sum(map(has, recent)) / max(len(recent), 1),
                    w_has / max(res["player_minutes"], 1),
                    sum(owned[p][r] for p in range(hi)) / sample,
                )
            res["source"] = [[x / sample for x in row] for row in source]
            out[day + 1] = res
    if ref:
        return first_hour
    return out


# ------------------------------------------------------------------------------------------------
# Reports
# ------------------------------------------------------------------------------------------------
def drift_flag(name, pct):
    if name in TARGETS:
        d = pct / TARGETS[name] - 1
        return (f"target ~{TARGETS[name]:g}%", f"{d * 100:+.0f}%", abs(d) > DRIFT_LIMIT)
    d = pct / CAPS[name] - 1
    return (f"cap {CAPS[name]:g}%", f"{d * 100:+.0f}%" if d > 0 else "under cap", d > 0)


def print_run(out, sample, label):
    print(f"=== {label} ===")
    for d, res in out.items():
        print(f"Day {d}: {res['ever'] / sample:,.0f} players ever won, {res['recent'] / sample:,.0f} active in the last 7 days, "
              f"peak CCU about {2 * res['player_minutes'] / 1440 / sample:,.0f}")
        print(f"  {'rarity':10s} {'own one: all players':>21s} {'active (7d)':>12s} {'in a server':>12s} {'copies':>10s}")
        for r in RAR[3:]:
            a, b, c, n = res[r]
            print(f"  {r:10s} {a * 100:20.2f}% {b * 100:11.2f}% {c * 100:11.2f}% {n:10,.0f}")
        src = res["source"]
        used = [i for i in range(len(SRC)) if any(src[i][3:])]
        print("  Epic/Legendary/Mythic/Secret copies by source: " + ", ".join(
            f"{SRC[i]} " + "/".join(f"{src[i][r]:,.0f}" for r in range(3, 7)) for i in used))
    print()


def summary(rows, day=30):
    """rows: [(label, out)]. A plain-English check of day `day` against the designer's targets."""
    print(f"Day {day}, players active in the last 7 days who own at least one cue of each rarity:\n")
    print(f"  {'rarity':10s} {'goal':>14s} " + " ".join(f"{lbl:>22s}" for lbl, _ in rows))
    flagged = []
    for r in ["Epic", "Legendary", "Mythic", "Secret"]:
        goal = drift_flag(r, 1)[0]
        cells = []
        for lbl, out in rows:
            pct = out[day][r][1] * 100
            _, d, bad = drift_flag(r, pct)
            cells.append(f"{pct:6.2f}% ({d}){' !' if bad else '  '}")
            if bad:
                flagged.append((lbl, r, pct, goal))
        print(f"  {r:10s} {goal:>14s} " + " ".join(f"{c:>22s}" for c in cells))
    print()
    if flagged:
        print("  Off target (more than 20% from the goal, or over a cap):")
        for lbl, r, pct, goal in flagged:
            print(f"    - {lbl}: {r} {pct:.2f}% against {goal}")
    else:
        print("  Every metric is within 20% of its goal (and Mythic and Secret are under their caps).")
    print("  Mythic and Secret rest on a few dozen and a few players in the sample: read them as rough.\n")


def assumptions_text(extras, like_codes):
    on = [f"    + {EXTRAS[k]}" for k in EXTRAS if k in extras]
    if like_codes and "codes" in extras:
        on.append("    + like-milestone codes")
    return "  Additions to the plan's sim switched on:\n" + ("\n".join(on) if on else "    (none: this is the plan's sim)")


def parse_extras(args):
    extras = set() if args.plan_only else set(EXTRAS)
    for k in filter(None, (args.without or "").split(",")):
        if k not in EXTRAS:
            sys.exit(f"--without: unknown addition {k!r}; pick from {', '.join(EXTRAS)}")
        extras.discard(k)
    return extras


def _job(job):
    g, extras, sample, seed, like = job
    return run(g, extras, sample=sample, seed=seed, like_codes=like)


def cmd_sim(g, args):
    p = g.per_drop_odds()
    print("Per Mystery block (no pity): " + ", ".join(f"{r} {x * 100:.4g}%" for r, x in zip(RAR, p) if x > 0))
    print(f"Money: winner ${g.win_pay:,.0f}, loser ${g.loss_pay:,.0f} a match (Classic, before boosts); "
          f"difficulty mix x{g.mode_money:.2f} from {g.tiers[g.unlock_tier]}; ${g.money_per_robux:.0f} per Robux\n")
    if args.compare:
        from multiprocessing import Pool

        labels = ["plan only", "full"] + [f"full minus {k}" for k in EXTRAS]
        sets = [set(), set(EXTRAS)] + [set(EXTRAS) - {k} for k in EXTRAS]
        with Pool() as pool:
            outs = pool.map(_job, [(g, s, args.sample, args.seed, args.like_codes) for s in sets])
        print(f"Day 30, active in the last 7 days (sample {args.sample}, seed {args.seed}):\n")
        print(f"  {'run':28s} {'Epic':>8s} {'Legendary':>10s} {'Mythic':>8s} {'Secret':>8s}")
        for lbl, out in zip(labels, outs):
            print(f"  {lbl:28s} " + " ".join(f"{out[30][r][1] * 100:{w}.2f}%" for r, w in (("Epic", 7), ("Legendary", 9), ("Mythic", 7), ("Secret", 7))))
        print()
        summary(list(zip(labels[:2], outs[:2])))
        return
    extras = parse_extras(args)
    out = run(g, extras, sample=args.sample, seed=args.seed, like_codes=args.like_codes)
    print_run(out, args.sample, "plan only" if not extras else "with the additions")
    summary([("plan only" if not extras else "this run", out)])
    print(assumptions_text(extras, args.like_codes))


REF_PLAYERS = [
    ("30 min a day", {"minutes": 30}),
    ("1 h a day", {"minutes": 60}),
    ("1 h a day + VIP", {"minutes": 60, "vip": True, "payer": True}),
    ("3 h a day", {"minutes": 180}),
    ("3 h + VIP + 1,000 R$/month", {"minutes": 180, "vip": True, "payer": True, "budget": 1000}),
    ("1 h + 5,000 R$/month (whale)", {"minutes": 60, "vip": True, "payer": True, "budget": 5000}),
]


def cmd_loot(g, args, extras):
    print(f"Reference players (50% win rate, every day, {args.n} each), hours played to a first ...")
    print("[median hours, and the share who own one by day 30 / day 90]\n")
    for name, ref in REF_PLAYERS:
        ref = dict(ref, n=args.n)
        fh = run(g, extras, days=90, sample=1, seed=5, ref=ref, report=())
        cells = []
        for r in range(3, 7):
            x = sorted(fh[r])
            med = x[len(x) // 2]
            d30 = sum(v <= ref["minutes"] / 60 * 30 for v in x) / len(x)
            d90 = sum(v <= ref["minutes"] / 60 * 90 for v in x) / len(x)
            cells.append(f"{RAR[r]} {('%.0f h' % med) if math.isfinite(med) else '-':>6s} {d30 * 100:5.1f}%/{d90 * 100:5.1f}%")
        print(f"  {name:30s} " + " | ".join(cells))


def cmd_supply(g, _args):
    """Cues entering the game from win drops, per player-hour and per day at a peak CCU (player-hours
    a day = average CCU x 24, the average CCU about half the peak)."""
    p = g.per_drop_odds()
    drops_per_hour = 60 / MIN_PER_MATCH * 0.5  # win drops alone, 50% win rate
    print("Cue supply from win drops alone (1 Mystery block a win, 7.5 matches an hour, 50% win rate):\n")
    print(f"  {'rarity':10s} {'per hour':>9s} {'500 CCU':>10s} {'2k CCU':>10s} {'10k CCU':>10s}  (a day)")
    for i, r in enumerate(RAR):
        rate = p[i] * drops_per_hour
        cells = [rate * ccu * 0.5 * 24 for ccu in (500, 2000, 10000)]
        print(f"  {r:10s} {rate:9.4f} " + " ".join(f"{c:10,.1f}" for c in cells))
    print("\n  The full sim's 'copies by source' lines (default command) add rewards and Mystery blocks.")


def cmd_shop(g, _args):
    c = g.c
    hour_money = 60 / MIN_PER_MATCH * (g.win_pay + g.loss_pay) / 2
    print(f"Money an hour, Classic, 50% win rate: about ${hour_money:,.0f}\n")
    print("Money packs\n")
    base = c["Packs"][0]["Money"] / c["Packs"][0]["Robux"]
    for pk in c["Packs"]:
        rate = pk["Money"] / pk["Robux"]
        print(f"  {pk['Key']:6s} {pk['Robux']:>5} R$  ${pk['Money']:>10,}  ${rate:6.1f} per R$  +{(rate / base - 1) * 100:3.0f}%")
    best = max(pk["Money"] / pk["Robux"] for pk in c["Packs"])
    rs = c["Shop"]["Restock"]
    items = [("Mystery block", g.mystery), ("Ability spin", g.spin_price), ("Restock Uncommon block", rs["Uncommon"]["Price"]),
             ("Restock Rare block", rs["Rare"]["Price"]), ("Restock Epic block", rs["Epic"]["Price"]),
             ("Restock Legendary block", rs["Legendary"]["Price"])]
    items += [(f"Limited {row['Cue']}", row["Price"]) for row in c["Shop"].get("Limited", []) if row.get("Price")]
    print("\nWhat things cost: Robux at the best pack rate, and hours of Classic play\n")
    for name, price in items:
        print(f"  {name:24s} ${price:>10,}  ~{price / best:7,.0f} R$  {price / hour_money:7.1f} h")
    print(f"\nRestock shop every {rs['SlotSeconds'] // 60} min: Rare block in {rs['RareChance'] / rs['ChanceTotal']:.0%} of restocks, "
          f"Epic {rs['EpicChance'] / rs['ChanceTotal']:.2%}, Legendary {rs['LegendaryChance'] / rs['ChanceTotal']:.2%} "
          f"(one in {rs['ChanceTotal'] / rs['LegendaryChance'] * rs['SlotSeconds'] / 3600:.0f} h)")


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


def cmd_tables(g, _args):
    p = g.per_drop_odds()
    print("Per Mystery block (no pity), and each odds row (must sum to OddsTotal)\n")
    print("  " + ", ".join(f"{r} {x * 100:.4g}% (1 in {1 / x:,.0f})" for r, x in zip(RAR, p) if x > 0))
    for k in g.cases:
        odds = g.c["BlockOdds"]["List"][k]["Odds"]
        print(f"  {k:10s} sum {sum(odds.values()):>9,}  timer {g.c['LuckyBlocks']['Kinds'][k]['Timer'] / 3600:4.0f} h  "
              + "  ".join(f"{r} {odds[r] / g.total * 100:.4g}%" for r in RAR if r in odds))
    print()
    for mode in ("Classic", "Difficult", "Challenger"):
        m = g.c["DifficultyMoney"][mode] if g.c["Economy"]["UseDifficultyMultiplier"] else 1
        per = (g.win_pay + g.loss_pay) / 2 * m
        print(f"  {mode:10s} ${per:6,.0f} a match, about ${per * 60 / MIN_PER_MATCH:7,.0f} an hour (50% win rate)")
    L = Ladder(g.c)
    print(f"\nRank XP: each tier's divisions (Reyes at {L.reyes_xp:,} XP)\n")
    for t in L.tiers[:-1]:
        print(f"  {t:12s} {L.widths[t]}  total {sum(L.widths[t]):>9,}")
    names = L.tiers[1:]
    for label, classic in (("Classic only", True), (f"mode mix from Gold {LADDER_MIX}", False)):
        print(f"\n  Hours to reach each tier, equal opponents, {label}\n  win rate " + "".join(f"{t[:6]:>8s}" for t in names))
        for wr in (0.45, 0.5, 0.55, 0.6):
            hs = ladder_hours(L, wr, classic)
            print(f"  {int(wr * 100):3d}%     " + "".join(f"{hs[t]:7.0f}h" for t in names))
    print("\nOpponent-gap factor on a win (gap in divisions; + means you are higher)\n")
    for label, d in (("Bronze to Diamond", 20), (f"{L.gap['StrictFromTier']} and up", 30)):
        print(f"  {label:18s} " + "  ".join(f"{gp:+d}: x{L.gap_factor(gp, d):4.2f}" for gp in (-5, -3, -1, 0, 1, 3, 5, 8, 10, 15)))


def cmd_ranks(g, args, new_per_day=2000, seed=3, report_days=(90, 180, 365)):
    """A year of players on the ladder: arrivals, heavy-tailed lifetimes, half the matches against
    near-rank players (80% from Diamond), win chance by skill (sharper on harder tables)."""
    L = Ladder(g.c)
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="?", default="sim", choices=["sim", "tables", "shop", "loot", "hours", "supply", "ranks"])
    ap.add_argument("--plan-only", action="store_true", help="switch every addition off (the plan's sim)")
    ap.add_argument("--without", help="comma list of additions to switch off: " + ", ".join(EXTRAS))
    ap.add_argument("--like-codes", action="store_true", help="also give out the like-milestone codes")
    ap.add_argument("--compare", action="store_true", help="plan-only, full, and full minus each addition")
    ap.add_argument("--sample", type=float, default=SAMPLE, help="share of the real player base simulated")
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument("--n", type=int, default=4000, help="reference players per profile (loot, hours)")
    ap.add_argument("--days", type=int, default=365, help="days for the ranks sim")
    args = ap.parse_args()
    g = Game(load_config())
    if args.what == "sim":
        cmd_sim(g, args)
    elif args.what in ("loot", "hours"):
        cmd_loot(g, args, parse_extras(args))
    elif args.what == "supply":
        cmd_supply(g, args)
    elif args.what == "shop":
        cmd_shop(g, args)
    elif args.what == "tables":
        cmd_tables(g, args)
    else:
        cmd_ranks(g, args)


if __name__ == "__main__":
    main()
