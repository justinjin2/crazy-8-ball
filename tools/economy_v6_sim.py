#!/usr/bin/env python3
"""Economy v6 simulator (scratch): reference players day by day, today's economy (v5.2 as built,
soft launch: no launch luck, no planned features) against the v6 plan. Standard library only."""
import random, math, sys, copy, json

RAR = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
TIER = {"Standard": 0, "Uncommon": 1, "Rare": 2, "Epic": 3, "Legendary": 4, "Mythic": 5}

# ---------------------------------------------------------------- odds helpers
def climb(start, steps):
    out = [0.0] * 7; p = 1.0
    for i in range(start, 7):
        if i == 6: out[6] += p; break
        out[i] += p * (1 - steps[i]); p *= steps[i]
    return out

def turn_dist(turn):
    out = [0.0] * 5; p = 1.0
    for i in range(5):
        if i == 4: out[4] += p; break
        out[i] += p * (1 - turn[i]); p *= turn[i]
    return out

def mystery_final(turn, steps):
    fin = [0.0] * 7
    for b, pb in enumerate(turn_dist(turn)):
        c = climb(b, steps)
        for i in range(7): fin[i] += pb * c[i]
    return fin

def pick(rng, dist):
    r = rng.random(); acc = 0
    for i, p in enumerate(dist):
        acc += p
        if r < acc: return i
    return len(dist) - 1

# ---------------------------------------------------------------- configs
def R(money=0, blocks=None, spins=0, cues=None):
    return {"money": money, "blocks": blocks or {}, "spins": spins, "cues": cues or []}

TODAY = dict(
    name="today (v5.2 as built)",
    steps=[.5, .35, .18, .10, .15, .025], turn=[.3, .25, .10, .05],
    pity=(10, 40), pity_start=(2, 10),
    catalog={"Common": 7, "Uncommon": 9, "Rare": 10, "Epic": 9, "Legendary": 7, "Mythic": 3, "Secret": 1},
    win_track=["Uncommon", "$", "$", "Mystery", "$", "$", "Mystery", "$", "$", "Epic"], step_money=1000,
    first_win="Rare",
    sky=None,
    playtime=[(5, 500, 0), (15, 1000, 0), (30, 1500, 0), (45, 2000, 0), (60, 2500, 1)],
    first_week=[R(5000), R(blocks={"Mystery": 1}), R(spins=3), R(blocks={"Rare": 1}), R(50000),
                R(blocks={"Mystery": 3}), R(cues=["Legendary:WeekOne"])],
    first_missed=R(blocks={"Epic": 1}),
    later_week=[R(5000), R(spins=1), R(blocks={"Mystery": 1}), R(25000), R(blocks={"Mystery": 2}), R(45000),
                R(blocks={"Rare": 1})],
    track28={8: R(50000), 14: R(blocks={"Rare": 1}), 21: R(150000), 28: R(blocks={"Epic": 1})},
    div_money={"Bronze": 1000, "Silver": 2000, "Gold": 3500, "Platinum": 6000, "Diamond": 15000, "Expert": 30000},
    tier_reward={"Bronze": R(2500, cues=["Uncommon:4"]), "Silver": R(5000, {"Rare": 1}, 1), "Gold": R(10000, {"Rare": 2}, 1),
                 "Platinum": R(20000, {"Epic": 1}, 2), "Diamond": R(50000, {"Epic": 2}, 2),
                 "Expert": R(100000, {"Legendary": 1}, 3)},
    rank_cue_find=5000,
    tutorial_bronze_kind=None,  # Bronze's block is the Mystery above (scripted to an Uncommon)
    group=R(blocks={"Mystery": 2}), favorite=R(10000, {"Lucky8": 1}),
    codes=[R(5000, {"Mystery": 1}), R(2500), R(blocks={"Uncommon": 1}), R(spins=3)],
    gift="Uncommon", invite=R(blocks={"Uncommon": 1}),
    find={"Common": 500, "Uncommon": 1000, "Rare": 2500, "Epic": 7500, "Legendary": 25000, "Mythic": 100000,
          "Secret": 500000},
    rows={"Common": 10000, "Uncommon": 25000, "Rare": 75000, "Epic": 250000},
    vip_daily=R(blocks={"Mystery": 1}, spins=1), vip_mult=2.0,
    mystery_price=19900, spin_price=12500,
    starter=R(25000, {"Starter": 1}),
    sell={"Common": 150, "Uncommon": 400, "Rare": 1500, "Epic": 25000, "Legendary": 250000, "Mythic": 2500000,
          "Secret": 25000000},
    lucky_shot=None,
    tutorial_scripted=True,
)

V6 = dict(
    name="v6",
    steps=[.40, .30, .10, .15, .10, .025], turn=[.30, .20, .10, .05],
    pity=(10, 50), pity_start=(0, 0),
    catalog={"Common": 7, "Uncommon": 9, "Rare": 9, "Epic": 9, "Legendary": 6, "Mythic": 3, "Secret": 1},
    win_track=["Mystery", "$", "$", "$", "Mystery", "$", "$", "$", "$", "Rare"], step_money=250,
    first_win=None,
    sky=dict(every=30, cap=2, kind="Standard"),
    playtime=[(5, 250, 0), (15, 250, 0), (30, 500, 0), (45, 500, 0), (60, 1000, 1)],
    first_week=[R(5000), R(spins=2), R(blocks={"Mystery": 1}), R(30000), R(blocks={"Mystery": 2}),
                R(blocks={"Rare": 1}), R(cues=["Legendary:Chroma"])],
    first_missed=R(blocks={"Epic": 1}),
    later_week=[R(1000), R(2500), R(5000), R(spins=1), R(spins=2), R(blocks={"Mystery": 1}), R(blocks={"Rare": 1})],
    track28={8: R(blocks={"Mystery": 1}), 14: R(blocks={"Rare": 1}), 21: R(50000), 28: R(blocks={"Epic": 1})},
    div_money={"Bronze": 1000, "Silver": 2000, "Gold": 3000, "Platinum": 5000, "Diamond": 10000, "Expert": 20000},
    tier_reward={"Bronze": R(2500, {"Uncommon": 1}), "Silver": R(5000, {"Rare": 1}, 1), "Gold": R(10000, {"Rare": 1}, 1),
                 "Platinum": R(20000, {"Epic": 1}, 2), "Diamond": R(40000, {"Epic": 1}, 2),
                 "Expert": R(75000, {"Legendary": 1}, 3)},
    rank_cue_find=1000,
    tutorial_bronze_kind="Uncommon",
    group=R(blocks={"Mystery": 1}), favorite=R(5000, {"Lucky8": 1}),
    codes=[R(5000), R(2500), R(2500), R(spins=3)],
    gift="Uncommon", invite=R(cues=["Rare:Candy"]),
    find={"Common": 250, "Uncommon": 500, "Rare": 1000, "Epic": 2500, "Legendary": 10000, "Mythic": 25000,
          "Secret": 100000},
    rows={"Common": 5000, "Uncommon": 10000, "Rare": 25000, "Epic": 100000},
    vip_daily=R(blocks={"Mystery": 1}, spins=1), vip_mult=2.0,
    mystery_price=25000, spin_price=10000,
    starter=R(25000, {"Starter": 1}),
    sell={"Common": 200, "Uncommon": 500, "Rare": 2000, "Epic": 10000, "Legendary": 100000, "Mythic": 1000000,
          "Secret": 10000000},
    lucky_shot=None,
    tutorial_scripted=False,
)

STARTER_ODDS = [0, 0, .90, .09, .009, .0009, .0001]

# Rank ladder: XP widths (Classic wins = XP/100)
WIDTHS = {"Bronze": [300, 300, 400, 500, 600], "Silver": [700, 800, 900, 1000, 1100],
          "Gold": [1200, 1300, 1400, 1500, 1600], "Platinum": [1700, 1800, 1900, 2000, 2200],
          "Diamond": [2500, 2800, 3200, 3600, 4000], "Expert": [4500, 5000, 5600, 6200, 6900]}
TIERS = ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Expert"]
DIVS = []  # (xp_start, tier, div)
x = 0
for t in TIERS:
    for d, w in enumerate(WIDTHS[t]):
        DIVS.append((x, t, d)); x += w

# ---------------------------------------------------------------- behaviour assumptions
MIN_PER_MATCH = 8.0
WIN_PAY, LOSS_PAY = 1420, 650  # Classic, streak bonus included (ECONOMY 3.1)
GROUP_SHARE, FAV_SHARE, CODE_SHARE, INVITED_SHARE = 0.30, 0.25, 0.70, 0.05
DAY_SPREAD = (0.6, 1.4)


class Player:
    def __init__(s, cfg, minutes, vip=False, spend=True, rng=None, days=60, every_day=True, play_chance=1.0,
                 starter=False, sell_dupes=False):
        s.c = cfg; s.minutes = minutes; s.vip = vip; s.spend = spend; s.rng = rng or random.Random(1)
        s.days = days; s.play_chance = play_chance; s.starter = starter; s.sell_dupes = sell_dupes
        s.money = 0; s.earned = {}; s.blocks_got = {}; s.opened = 0; s.spins = 0
        s.owned = {}  # cue id -> copies
        s.found = set(); s.rows_paid = set()
        s.xp = 0; s.div_index = -1
        s.since_rare, s.since_epic = cfg["pity_start"]
        s.login_first = 0; s.first_missed = False; s.last_claim = None; s.total_claims = 0; s.later_idx = 0
        s.snap = {}
        s.first_epic_day = None; s.first_leg_day = None
        s.cues_by_rar = {r: 0 for r in RAR}
        s.pool_by_rar = {r: 0 for r in RAR}
        s.daily_blocks = []

    # -------------------------------------------------------------- money
    def pay(s, amt, src):
        s.money += amt; s.earned[src] = s.earned.get(src, 0) + amt

    # -------------------------------------------------------------- cues
    def give_cue(s, rar, cid, day):
        s.cues_by_rar[rar] += 1
        fixed = cid.split(":")[1] in ("WeekOne", "Chroma", "Candy") or cid.startswith("Rank:")
        if not fixed:
            s.pool_by_rar[rar] += 1
        first = cid not in s.owned
        s.owned[cid] = s.owned.get(cid, 0) + 1
        if first:
            s.found.add(cid)
            if not cid.startswith("Rank:"):
                s.pay(s.c["find"][rar], "index finds")
            s.check_rows()
        elif s.sell_dupes and rar in ("Common", "Uncommon"):
            s.owned[cid] -= 1; s.pay(s.c["sell"][rar], "sell-back")
        if rar in ("Epic", "Legendary", "Mythic", "Secret") and s.first_epic_day is None: s.first_epic_day = day
        if rar in ("Legendary", "Mythic", "Secret") and s.first_leg_day is None: s.first_leg_day = day

    def check_rows(s):
        for rar, amt in s.c["rows"].items():
            if rar in s.rows_paid: continue
            n = s.c["catalog"][rar]
            ids = [f"{rar}:{i}" for i in range(n)]
            extra = []
            if rar == "Rare" and s.c["catalog"]["Rare"] == 9: extra = ["Rare:Candy"]
            if all(i in s.owned for i in ids + extra):
                s.rows_paid.add(rar); s.pay(amt, "index rows")

    def roll_cue(s, tier, day):
        if tier == 6:
            s.give_cue("Secret", "Secret:0", day); return 6
        rar = RAR[tier]
        n = s.c["catalog"][rar]
        s.give_cue(rar, f"{rar}:{s.rng.randrange(n)}", day)
        return tier

    # -------------------------------------------------------------- blocks
    def open_block(s, kind, day, paid=False):
        s.opened += 1
        steps = s.c["steps"]
        if kind == "Mystery":
            pr, pe = s.c["pity"]
            s.since_rare += 1; s.since_epic += 1
            if s.since_epic >= pe:
                b = 3
            elif s.since_rare >= pr:
                b = 2
            else:
                b = pick(s.rng, turn_dist(s.c["turn"]))
            t = pick(s.rng, climb(b, steps))
            got = s.roll_cue(t, day)
            if got >= 2: s.since_rare = 0
            if got >= 3: s.since_epic = 0
            return got
        if kind == "Starter":
            return s.roll_cue(pick(s.rng, STARTER_ODDS), day)
        start = {"Sky": 0, "Lucky8": 1, "Gift": 1}.get(kind, TIER.get(kind, 0))
        return s.roll_cue(pick(s.rng, climb(start, steps)), day)

    def add_blocks(s, blocks, src, day):
        for k, n in blocks.items():
            for _ in range(n):
                s.blocks_got[src] = s.blocks_got.get(src, 0) + 1
                s.today_blocks += 1
                s.open_block(k, day)

    def reward(s, row, src, day):
        if row["money"]: s.pay(row["money"], src)
        s.spins += row["spins"]
        s.add_blocks(row["blocks"], src, day)
        for c in row["cues"]:
            rar, cid = c.split(":")
            s.give_cue(rar, rar + ":" + cid, day)

    # -------------------------------------------------------------- rank
    def add_xp(s, xp, day):
        s.xp += xp
        while s.div_index + 1 < len(DIVS) and s.xp >= DIVS[s.div_index + 1][0] + (0 if s.div_index + 1 > 0 else 100):
            s.div_index += 1
            _, t, d = DIVS[s.div_index]
            if d == 0:
                s.reward(s.c["tier_reward"][t], "rank", day)
                s.give_cue("Common", f"Rank:{t}", day)  # rank cue (not in rarity rows)
                s.cues_by_rar["Common"] -= 1
                s.pay(s.c["rank_cue_find"], "index finds")
            else:
                s.pay(s.c["div_money"][t], "rank")

    # -------------------------------------------------------------- a day
    def play_day(s, day):
        s.today_blocks = 0
        c = s.c
        mins = s.minutes * s.rng.uniform(*DAY_SPREAD)
        if day == 1:
            # social and codes on day 1
            if s.rng.random() < GROUP_SHARE: s.reward(c["group"], "group/fav/codes/invite", day)
            if s.rng.random() < FAV_SHARE: s.reward(c["favorite"], "group/fav/codes/invite", day)
            if s.rng.random() < CODE_SHARE:
                for row in c["codes"]: s.reward(row, "group/fav/codes/invite", day)
            if s.rng.random() < INVITED_SHARE: s.reward(c["invite"], "group/fav/codes/invite", day)
            if s.starter:
                s.reward(c["starter"], "starter pack", day)
        if day == 2 and c["gift"]:
            s.add_blocks({c["gift"]: 1}, "gift", day)
        matches = int(mins / MIN_PER_MATCH + s.rng.random())
        matches = max(matches, 1)
        wins_today = 0
        mult = s.c["vip_mult"] if s.vip else 1.0
        for m in range(matches):
            won = (day == 1 and m == 0) or s.rng.random() < 0.5
            if won:
                s.pay(WIN_PAY * mult, "match money")
                wins_today += 1
                s.add_xp(100, day)
                first_ever = (day == 1 and m == 0)
                if wins_today <= 10:
                    step = c["win_track"][wins_today - 1]
                    if wins_today == 1 and first_ever and c["first_win"]:
                        step = c["first_win"]
                    if step == "$":
                        s.pay(c["step_money"], "win track money")
                    else:
                        s.add_blocks({step: 1}, "win track", day)
                if first_ever and c["tutorial_bronze_kind"]:
                    pass  # the Bronze tier reward (an Uncommon block in v6) comes through add_xp
            else:
                s.pay(LOSS_PAY * mult, "match money")
        # Sky blocks
        if c["sky"]:
            n = min(int(mins // c["sky"]["every"]), c["sky"]["cap"])
            if n: s.add_blocks({c["sky"]["kind"]: n}, "sky", day)
        # playtime
        for t, money, spins in c["playtime"]:
            if mins >= t:
                s.pay(money, "playtime"); s.spins += spins
        # login (claimed every day played)
        s.login(day)
        if s.vip: s.reward(c["vip_daily"], "vip daily", day)
        # spend
        if s.spend:
            while s.money >= c["mystery_price"]:
                s.money -= c["mystery_price"]
                s.blocks_got["bought (money)"] = s.blocks_got.get("bought (money)", 0) + 1
                s.today_blocks += 1
                s.open_block("Mystery", day)
        s.daily_blocks.append(s.today_blocks)

    def login(s, day):
        c = s.c
        if s.login_first < 7 and day <= 14:
            if s.last_claim is not None and day - s.last_claim > 1: s.first_missed = True
            s.login_first += 1
            if s.login_first == 7:
                row = c["first_missed"] if s.first_missed else c["first_week"][6]
            else:
                row = c["first_week"][s.login_first - 1]
            s.reward(row, "login", day)
        else:
            s.reward(c["later_week"][s.later_idx % 7], "login", day); s.later_idx += 1
        s.last_claim = day
        s.total_claims += 1
        tk = ((s.total_claims - 1) % 28) + 1
        if tk in c["track28"]: s.reward(c["track28"][tk], "28-day track", day)

    def run(s, snaps=(1, 7, 30, 60)):
        for day in range(1, s.days + 1):
            if day == 1 or s.rng.random() < s.play_chance:
                s.play_day(day)
            if day in snaps:
                s.snap[day] = dict(own={r: any(s.owned.get(k, 0) for k in s.owned if k.startswith(r + ":")) for r in RAR},
                                   opened=s.opened, cues=dict(s.cues_by_rar), pool=dict(s.pool_by_rar), distinct=len([k for k in s.owned if not k.startswith("Rank:")]),
                                   earned=sum(s.earned.values()), xp=s.xp)
        return s


def own_rarity_or_better(snap, r):
    i = RAR.index(r)
    return any(snap["own"][x] for x in RAR[i:])


def ref(cfg, minutes, vip=False, n=2000, seed=7, spend=True, starter=False, days=60, sell_dupes=False):
    rng = random.Random(seed)
    ps = [Player(cfg, minutes, vip=vip, spend=spend, rng=random.Random(rng.random()), starter=starter, days=days, sell_dupes=sell_dupes).run()
          for _ in range(n)]
    out = {}
    for d in (1, 7, 30, 60):
        if d > days: continue
        sn = [p.snap[d] for p in ps]
        out[d] = dict(
            epic=sum(own_rarity_or_better(x, "Epic") for x in sn) / n,
            leg=sum(own_rarity_or_better(x, "Legendary") for x in sn) / n,
            leg_pool=None,
            myth=sum(own_rarity_or_better(x, "Mythic") for x in sn) / n,
            sec=sum(x["own"]["Secret"] for x in sn) / n,
            opened=sum(x["opened"] for x in sn) / n,
            distinct=sum(x["distinct"] for x in sn) / n,
            earned=sum(x["earned"] for x in sn) / n,
            cues={r: sum(x["cues"][r] for x in sn) / n for r in RAR},
            pepic=sum((x["pool"]["Epic"] + x["pool"]["Legendary"] + x["pool"]["Mythic"] + x["pool"]["Secret"]) > 0 for x in sn) / n,
            pleg=sum((x["pool"]["Legendary"] + x["pool"]["Mythic"] + x["pool"]["Secret"]) > 0 for x in sn) / n,
            nleg=sum(x["pool"]["Legendary"] + x["pool"]["Mythic"] + x["pool"]["Secret"] for x in sn) / n,
            nepic=sum(x["pool"]["Epic"] for x in sn) / n,
            ncommon=sum(x["pool"]["Common"] for x in sn) / n,
        )
    # sources over 60 days
    src = {}
    for p in ps:
        for k, v in p.blocks_got.items(): src[k] = src.get(k, 0) + v / n
    money = {}
    for p in ps:
        for k, v in p.earned.items(): money[k] = money.get(k, 0) + v / n
    # steady-state blocks a day (days 8-60)
    steady = sum(sum(p.daily_blocks[7:]) / max(1, len(p.daily_blocks[7:])) for p in ps) / n
    leg_luck = 0
    return dict(snap=out, src=src, money=money, steady=steady, players=ps)


def fmt_money(x):
    return f"${x:,.0f}"


def report(cfg, kinds=((30, False), (60, False), (180, False), (60, True)), n=1500):
    print("=" * 110); print(cfg["name"])
    m = mystery_final(cfg["turn"], cfg["steps"])
    print("  Mystery final: " + "  ".join(f"{RAR[i]} {m[i]*100:.3g}%" for i in range(7)),
          "| Epic+ 1 in %.0f, Leg+ 1 in %.0f, Myth+ 1 in %.0f" % (1/sum(m[3:]), 1/sum(m[4:]), 1/sum(m[5:])))
    res = {}
    for mins, vip in kinds:
        r = ref(cfg, mins, vip, n=n)
        res[(mins, vip)] = r
        print(f"  -- {'VIP' if vip else 'Free'} {mins} min/day: steady blocks/day {r['steady']:.2f}")
        for d, s in r["snap"].items():
            print(f"     day {d:2d}: opened {s['opened']:6.1f} distinct {s['distinct']:4.1f} | luck: own Epic+ {s['pepic']*100:5.1f}% "
                  f"Leg+ {s['pleg']*100:5.1f}% (n {s['nleg']:.2f})  Epics {s['nepic']:.1f} Commons {s['ncommon']:.0f} | Myth+ {s['myth']*100:5.2f}% "
                  f"Secret {s['sec']*100:4.2f}% | money {fmt_money(s['earned'])}")
        print("     blocks by source (60 d): " + ", ".join(f"{k} {v:.1f}" for k, v in sorted(r["src"].items(), key=lambda kv: -kv[1])))
        print("     money by source (60 d): " + ", ".join(f"{k} {fmt_money(v)}" for k, v in sorted(r["money"].items(), key=lambda kv: -kv[1])))
    return res


if __name__ == "__main__":
    import itertools
    args = sys.argv[1:]
    if not args or args[0] == "today": report(TODAY)
    if not args or args[0] == "v6": report(V6)
    if args and args[0] == "vars":
        for el in (0.15, 0.18, 0.20):
            for cap in (2, 1):
                c = copy.deepcopy(V6); c["steps"][3] = el; c["sky"]["cap"] = cap; c["name"] = f"v6 E->L {el:.0%} sky cap {cap}"
                report(c, kinds=((30, False), (60, False), (180, False)), n=800)
    if args and args[0] == "price":
        for p in (20000, 25000, 30000):
            c = copy.deepcopy(V6); c["mystery_price"] = p; c["name"] = f"v6 Mystery ${p:,}"
            report(c, kinds=((30, False), (60, False), (180, False)), n=800)
