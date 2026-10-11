#!/usr/bin/env python3
"""Bots' cues by tier (Config.BotCues): how many 1-hour-a-day players own an Epic+, Legendary+ or
Mythic+ cue while they hold each tier, on the 2026-10-11 rank ladder and rank money. Runs
tools/economy_v6_sim.py's v6 players with the new ladder patched in, 6.3 minutes a match (measured
live 2026-10-11) and one Sky block a day; reward cues (Chroma, Candy Cane) are left out, as the
2026-10-10 fit did. Usage: python3 tools/botcues_fit.py [days=420] [players=300]."""
import importlib.util, copy, os, random, sys
spec = importlib.util.spec_from_file_location("sim", os.path.join(os.path.dirname(os.path.abspath(__file__)), "economy_v6_sim.py"))
sim = importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
R = sim.R
T = ["Bronze","Silver","Gold","Platinum","Diamond","Expert","Veteran","Master","Grandmaster"]
W = {"Bronze":[200,200,300,400,500],"Silver":[200,300,400,500,600],"Gold":[300,400,500,600,700],"Platinum":[400,500,600,700,800],"Diamond":[600,800,1000,1200,1400],"Expert":[1200,1600,2000,2400,2800],"Veteran":[2500,3000,3500,4000,4500],"Master":[4000,5500,7000,8500,10000],"Grandmaster":[9000,15000,22000,29000,35000]}
sim.WIDTHS = W; sim.TIERS = T
sim.DIVS.clear(); x = 0
for t in T:
    for d, w in enumerate(W[t]): sim.DIVS.append((x, t, d)); x += w
sim.DIVS.append((x, "Reyes", 0))
sim.MIN_PER_MATCH = 6.3
cfg = copy.deepcopy(sim.V6)
cfg["sky"]["cap"] = 1
cfg["div_money"] = {"Bronze":1000,"Silver":1250,"Gold":1500,"Platinum":2000,"Diamond":3000,"Expert":5000,"Veteran":10000,"Master":20000,"Grandmaster":50000}
cfg["tier_reward"] = {"Bronze":R(2500,{"Uncommon":1}),"Silver":R(4000,{"Rare":1},1),"Gold":R(6000,{"Rare":1},1),"Platinum":R(7500,{"Epic":1},2),"Diamond":R(10000,{"Epic":1},2),"Expert":R(15000,{"Legendary":1},3),"Veteran":R(30000,{"Legendary":1},3),"Master":R(50000,{"Legendary":2},3),"Grandmaster":R(100000,{"Mythic":1},3),"Reyes":R(1000000,{"Mythic":2},3)}
DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 420
N = int(sys.argv[2]) if len(sys.argv) > 2 else 300
agg = {}; tierdays = {}
rng = random.Random(7)
def owns(p, r):
    i = sim.RAR.index(r)
    return any(c > 0 for k, c in p.owned.items() if not k.startswith("Rank:") and k.split(":")[1] not in ("Chroma", "Candy", "WeekOne") and k.split(":")[0] in sim.RAR[i:])
for n in range(N):
    p = sim.Player(cfg, 60, rng=random.Random(rng.random()), days=DAYS)
    for day in range(1, DAYS + 1):
        p.play_day(day)
        tier = "Unranked" if p.div_index < 0 else sim.DIVS[p.div_index][1]
        a = agg.setdefault(tier, [0, 0, 0, 0])
        a[0] += 1; a[1] += owns(p, "Epic"); a[2] += owns(p, "Legendary"); a[3] += owns(p, "Mythic")
        tierdays.setdefault(tier, []).append(day)
print(f"1-hour players, {N} x {DAYS} days, 6.3 min a match, Sky 1 a day")
for t in T + ["Reyes"]:
    if t not in agg: print(t, "never reached"); continue
    a = agg[t]; d = sorted(tierdays[t])
    print(f"{t:12} days {d[len(d)//10]:>3}-{d[9*len(d)//10]:>3}  Epic+ {a[1]/a[0]:.3f}  Legendary+ {a[2]/a[0]:.3f}  Mythic+ {a[3]/a[0]:.3f}  ({a[0]} player-days)")
