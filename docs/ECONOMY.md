# Economy: money, ranks, lucky blocks, the shop and Robux (v6)

The one place that says how the game's economy works and every number in it. **Economy v6**,
rebuilt from scratch and approved by the designer on 2026-10-10, the soft-launch morning ("yes
to all of those, build this economy now"). The plan page with the reasoning and the simulation:
https://claude.ai/artifact/LngEA3qwDYZBZ7iPQkHkBK (a copy and the simulator in
`~/Desktop/8ball-refs/economy/v6/`; the simulator is also `tools/economy_v6_sim.py`). The build
checklist: `docs/prompts/ECONOMY_V6_PLAN.md`. Every number lives in `src/shared/Config.luau`
*(tune)*; change a number here and in Config together.

**Rules that did not change in v6** are still described in `docs/archive/ECONOMY_V5.md`: match
money per ball, nice shots and the ball streak (3.1), team matches (3.3), difficulty (3.4), boosts
(3.5), anti-farming (3.6), the XP ladder and its speed (4.1 to 4.7), seasons, rarities and the
catalog rules (6), the climb mechanics and the reel (7.1, 7.6, 7.7), announcements (7.8), the
restock's timing and slots (9.1), copies in existence (9.3), money packs, VIP and the Starter
Pack (11.1 to 11.4), ability spins (11.8), trading rules (12) and the Roblox rules checklist (13).
Where that file and this one disagree, **this one wins**.

## 0. At a glance

- Pace for a player who plays 1 hour a day: about **3.4 lucky blocks a day** after week 1 (v5:
  4.4), **Epic on day 1 about 1 in 9**, **a Legendary from luck about every 6 weeks**, about
  **$16,700 earned a day**.
- One match pays about **$1,000** (win about $1,400, loss about $650). A Mystery costs **$25,000**
  (about 3 hours of matches); every shop price is about **$2,500 for each Robux** of its Robux
  price.
- **Fewer, rarer good cues.** Chroma and Candy Cane leave the blocks and become rewards. Duplicate
  Commons and Uncommons turn into money. Finder's money is claimed in the Index.
- **No launch luck.** The Grand Opening Luck is removed, so the ad-weekend test measures the real
  economy. The Grand Opening block itself runs **45 days** from the moment v6 is published.
- **Every save started over** (2026-10-10): saves and every game-wide store moved to `_v2` names.

## 1. Money

| Source | Pays |
|---|---|
| A ball, nice shots, ball streak, win bonus $500, loss bonus $150, win streak $250 | unchanged (archive 3.1) |
| **Solo and practice against PC** | **$30 a ball** (SoloShare 0.3) until **$3,000 a day, the two together**, then $10 a ball. No nice shots, no ball streak, no match bonus, no XP, no lucky blocks, no win-track steps, no login/Sky/trade-gate credit |
| A disguised bot past 20 wins a day | pays the practice rows (hidden) |
| Win-track money step | $250 |

Practice is reachable only through the developer commands until the Solo and Practice portals
are built (planned with the designer, 2026-10-10).

## 2. Ranks: the rank-up rewards

Division steps (each division of the tier, paid once): Bronze $1,000, Silver $2,000, Gold $3,000,
Platinum $5,000, Diamond $10,000, Expert $20,000, Veteran $30,000, Master $50,000, Grandmaster
$75,000. Tier rewards (the tier's first division), with the spins as before:

| Tier | Money | Block |
|---|---|---|
| Bronze | $2,500 | an Uncommon block (ready at once: the tutorial's second block) |
| Silver | $5,000 | a Rare block |
| Gold | $10,000 | a Rare block |
| Platinum | $20,000 | an Epic block |
| Diamond | $40,000 | an Epic block |
| Expert | $75,000 | a Legendary block |
| Veteran | $150,000 | a Legendary block |
| Master | $250,000 | 2 Legendary blocks |
| Grandmaster | $500,000 | a Mythic block |
| Reyes | $1,000,000 | 2 Mythic blocks |

## 3. Lucky blocks

A block's name is its floor; when opened it climbs one step at a time (the reel shows the odds).

| Step up | Chance (v5) |
|---|---|
| Common → Uncommon | 40% (50%) |
| Uncommon → Rare | 30% (35%) |
| Rare → Epic | 10% (18%) |
| Epic → Legendary | 15% (10%) |
| Legendary → Mythic | 10% |
| Mythic → Secret | 2.5% |

**The Mystery** first turns into a block on its upgrade screen (4 presses): Standard → Uncommon
30%, Uncommon → Rare 20%, Rare → Epic 10%, Epic → Legendary 5%. That block then climbs. A
Mystery's cue: Common 42%, Uncommon 36.4%, Rare 18.9%, Epic or better 1 in 37, Legendary or better
1 in 232, Mythic or better 1 in 2,323, the Secret 1 in 92,915. **Pity** (Mysteries only): the 10th
without a Rare-or-better cue turns into a Rare block, the 50th without an Epic-or-better into an
Epic block; a new save starts at 0 / 0.

**Timers** (a free block's wait; paid blocks and VIP have none): Standard none, Uncommon 5 min,
Rare 10 min, Epic 1 h, Legendary 12 h, Mythic 24 h. A Mystery waits the timer of the block it
turns into. **Skips**: 1 R$ (10 min or less left), 4 R$ (1 h or less), 9 R$ (12 h or less), 15 R$
(any).

**Duplicates**: a block that gives a **Common or Uncommon cue you already own** pays its sell money
instead ("Duplicate · +$200"); no copy is added and the copies in existence do not change.

**The Grand Opening block** (Rare or better, money or Robux): Rare 85.875%, Epic 9%, Legendary 1.3%,
Mythic 0.12%, Secret 0.005%, the numbered Firework Cue 3.5% (1,000 ever), the numbered Beta Cue
0.2% (100 ever; guaranteed on a player's 500th). Runs **45 days** from StartsAt, set to the moment
the designer publishes v6. The **launch bonus** in that window is **+30% on money packs only**.

**The Starter block** (Starter Pack): unchanged (Rare 90%, Epic 9%, Legendary 0.9%, Mythic 0.09%,
Secret 0.01%).

### 3.1 The daily win track

The first 10 counted wins of the day (the day starts 08:00 UTC): win 1 **a Mystery**, wins 2-4
**$250** each, win 5 **a Mystery**, wins 6-9 **$250** each, win 10 **a Rare block**. There is no
first-win Rare block any more; the first win is win 1 like any day. Later wins pay money and XP.

### 3.2 The Sky Lucky Block

After **30 minutes of active play** in a day (across visits; a 2-minute idle pauses the clock),
once a real match has been finished that day, a Sky block (climbs from Standard) falls from the
sky in front of the player with the Gift's cutscene: **at most 1 a day**. In an arena it waits for
the lobby. The lobby's top shows "Next Sky Lucky Block in mm:ss". (Config.SkyBlock; replaces the
planned Lucky Rain.)

### 3.3 The tutorial's blocks

The first win gives a real Mystery (a normal roll; no scripted Uncommon, no forced Cosmo Cue), its
block ready at once, plus Bronze's Uncommon block from the Rank claim, also ready at once: both
open at once.

## 4. Cues: sell-back and the Index

| | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Sell back | $200 | $500 | $2,000 | $10,000 | $100,000 | $1,000,000 | $10,000,000 |
| Finder's money | $250 | $500 | $1,000 | $2,500 | $10,000 | $25,000 | $100,000 |

Finder's money for Ranked and Exclusive cues $1,000, Unique $5,000. **It is claimed in the
Index** ("New cues found!" and Collect at the top; a "!" on the Cues button and the Index tab),
never paid at once. **Index rows** (claimed once complete): Common $5,000, Uncommon $10,000, Rare
$25,000, Epic $100,000.

**Reward cues** (in no block, so in no pool, reel, restock or odds list; tradable and sold back
like their rarity; counted in their Index row):
- **The Chroma Cue** (Legendary): the first week's day 7, for 7 days in a row (else an Epic block).
  It replaced the Week One Cue.
- **The Candy Cane Cue** (Rare): the invite reward, to **both** players when the invited friend
  wins their first match (the inviter's once ever, 5 invites a month).

The block pool is now Common 7, Uncommon 9, Rare 9, Epic 9, Legendary 6, Mythic 3, Secret 1.

## 5. What money buys

| | Money | Robux |
|---|---|---|
| Mystery block | **$25,000** | 9 R$ |
| 5 Mystery blocks | **$100,000** | 39 R$ |
| Grand Opening block | **$100,000** | **39 R$** |
| 3 Grand Opening blocks | **$270,000** | **99 R$** |
| 10 Grand Opening blocks | **$850,000** | **299 R$** |
| Restock Rare block | **$100,000** | 39 R$ |
| Restock Epic block | **$500,000** | **199 R$** |
| Restock Legendary block | **$2,500,000** | **999 R$** |
| Restock Mythic block | **$5,000,000** | 1,699 R$ |
| Ability spin | **$10,000** each | 9 R$ (packs as before) |

Restock slots, stock and odds are unchanged (archive 9.1).

## 6. Free rewards

**Login, first week** (any 7 login days within 14 of joining; a day needs one finished match):
$5,000 · 2 spins · a Mystery · $30,000 · 2 Mysteries · a Rare block · **the Chroma Cue** (7 in a
row) else an Epic block. **Later weeks**: $1,000 · $2,500 · $5,000 · 1 spin · 2 spins · a Mystery ·
a Rare block. **The 28-day track**: day 8 a Mystery, day 14 a Rare block, day 21 $50,000, day 28 an
Epic block. **VIP every day**: a Mystery and a spin (unchanged).

**Claim All** (Robux): first week 499 / 449 / 399 R$ (unchanged), later weeks **49 / 39 / 19 R$**.

**Playtime gifts**: 5 min $250, 15 min $250, 30 min $500, 45 min $500, 60 min $1,000 + a spin.

**Social**: the group **1 Mystery**; a favorite **$5,000 + the Lucky 8 block**; invites the
Candy Cane Cue (section 4). **Codes**: WELCOME $5,000, 8BALL $2,500, ROOFTOP $2,500 (to
2026-12-31), RELEASE 3 spins. **Like codes** (switched on by the designer): 1K $10,000 + a Mystery,
5K 2 Mysteries, 10K a Rare block + 3 spins, 25K a Rare block + $25,000, 50K 2 Rare blocks, 100K an
Epic block + 5 spins.

**Planned, not built** (Config.Planned): the Daily Challenge (its button is off for the release),
Lucky Shot free (miss $250, grey $500, blue $1,000, red $2,500, gold a Mystery) and Golden Shot
15 R$ (miss a Mystery; grey a Mystery + $10,000; blue 2 Mysteries; red a Rare block; gold a Rare
block + 2 Mysteries). Lucky Rain and the stay bonus are dropped.

## 7. Robux

VIP 399 R$ and its 199 R$ welcome offer, the Starter Pack 29 R$, the money packs and Money Party are
unchanged (archive 11). The v6 Robux changes (synced to Roblox 2026-10-10): Grand Opening 39 / 99
/ 299 R$, restock Epic 199 R$ and Legendary 999 R$, later-week Claim All 49 / 39 / 19 R$, the skip
names by the new brackets. Note (2026-10-10): Roblox reports these products at about 80% of their
list price in Studio (regional pricing or price optimization in the Creator Dashboard); the game
shows Roblox's live price.

## 8. Trading

Unchanged rules (archive 12) plus **the trade gate**: trading unlocks after **10 real wins**
(practice and solo never count); both players need it. The lopsided warning's fallback worths were
refit for v6 (Config.Trade.BlockExists, ClimbedExists).

## 9. Bots' cues

The bots' Epic+ / Legendary+ / Mythic+ shares by tier were refit to v6's rarer high tiers
(Config.BotCues): Bronze .15 / .03 / .003 up to Reyes .99 / .99 / .75.

## 10. The wipe (2026-10-10)

Every save and every game-wide store moved to a new name: `PlayerData_v2`, `CueCounts_v2`,
`LimitedCounts_v2` (the Grand Opening's numbered copies), `Firsts_v2`, `RestockStock_v2`,
`TradeLedger_v2`, `InviteRewards_v2` and the boards `Board_*_v2` (Studio's and the test place's
too). The `_v1` stores are untouched and recoverable. LiveCodes kept its name.
