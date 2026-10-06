# Economy: money, ranks, lucky blocks, the shop and Robux

The one place that says how the game's economy works and every number in it. Rewritten
2026-10-03 from the economy plan the designer approved on 2026-10-02
(`~/Desktop/8ball-refs/economy/00-economy-plan.md`, built from research and a 60-day population
simulation), the designer's interview answers (2026-10-03) and what the Economy lane built
(steps 1-8, `docs/parallel/economy.md`). Cases were replaced by **lucky blocks** on 2026-10-04
(designer): every "case" in the plan is a lucky block here. GDD sections 11 and 12 point here.
Every number is a starting value *(tune)*: it lives in `src/shared/Config.luau` and changes after playtests.
Change a number here, in the model and in Config together, then re-run the model.

```bash
python3 tools/economy_model.py --help   # the model's commands: day-30 targets, ranks, money
```

**Built for a small launch, ready to grow.** Nothing assumes the game blows up. The ranks, blocks
and rewards work the same with 200 players online as with 20,000; the few things that should
change as the game grows are listed with their triggers in section 14.

**Odds are percentages everywhere** (plan, 2026-10-02): the Mystery block's tier roll, every
block, every cue, ability spins. Never "1 in X". Tiny values keep enough decimals to stay above zero (0.0004%),
and every list adds up to exactly 100%.

---

## 0. At a glance

- **One bar: rank XP.** No Levels. XP is never lost and comes only from winning: **100 XP a
  win, 0 a loss** (designer, 2026-10-02). Rank is the main way to show status.
- **Money is x10 of the old numbers** (plan, 2026-10-02): $100 a ball, $500 for a win, $150
  for a loss. A Classic match pays the winner about **$1,340** and the loser about **$600**:
  about **$7,300 an hour**. Difficult pays x1.5 and Challenger x2.
- **Every real win gives a Mystery lucky block** (designer, 2026-10-04: lucky blocks replaced
  cases): 5 minutes after the win it can be thrown and opened in the world, and the server
  rolls its tier then, from Standard (68%) to Mythic (0.0004%). Rare and better blocks open on
  a timer (1 h to 48 h). No block is sold permanently.
- **Money buys** Mystery blocks ($4,900), the **restock shop** (new blocks every 10 minutes,
  the same in every server), the Grand Opening block while its deal runs and ability spins
  ($17,500). A block's timer is skipped for Robux only (19 R$).
- **How rare things are** (the plan's simulation, day 30): about **5.4%** of active players own
  an Epic, **1.0%** a Legendary, **0.12%** a Mythic and about **0.01-0.02%** the Secret.
- **Robux**: 3 game passes (VIP 499 R$, two ability slots) and 31 developer products (money
  packs 49 to 4,999 R$, Mystery and Grand Opening blocks, restock blocks, the block timer
  skip, Money Party, spins, the launch-sale copies), plus a Get Roblox Plus button. Quick
  Cases and the four case timer skips are retired (designer, 2026-10-04).
- **Trading** is in: anyone in the server, cues and ready lucky blocks, never money, an atomic
  swap with a ledger (designer, 2026-10-03).
- **No reward popups** (designer, 2026-10-04): every reward, day 1 included, is claimed in the
  Rewards menu; nothing is given by itself on join.
- **Save version 6 wiped every save** (designer, 2026-10-03: only friends had played). Version
  7 (2026-10-04) dropped every case, case timer and the Quick Cases flag, nothing converted.

---

## 1. The designer's targets, and how the plan meets them

**The main target** (designer, 2026-10-02): at **day 30**, among active players (played in the
last 7 days):

| Rarity | Target: share of active players who own one | The plan's simulation (day 30) |
|---|---|---|
| Epic | about 5% | 5.4% |
| Legendary | about 1% | 1.0% |
| Mythic | 0.5% or less | 0.12% |
| Secret | far rarer | about 0.01-0.02% |

The simulation assumed 500 peak players online in week 1, about 1,900 by day 30 and about
5,600 by day 60. Re-run as-is it gives Epic 5.85%, Legendary 1.01%, Mythic 0.11%, Secret 0.02%.
Regulars still get Epics: a player who plays an hour a day has about a 64% chance to own one by
day 30. The share stays low because most players leave early.

**`tools/economy_model.py` checks these targets.** Re-run it after any number change. If the
model drifts more than about 20% off a target, the designer is told before anything is
trimmed.

Other targets (still true):

| Target (designer) | How it is met |
|---|---|
| Epic and up truly rare and worth a lot (2026-10-02) | the Mystery block's tier weights (section 7.1), no block sold permanently, Epic and Legendary blocks only from rewards and the restock shop |
| Lots of duplicates of Commons to Rares | a Mystery block every win, 94.8% of its cues Common or Uncommon |
| Block cues keep their value | no direct buying (section 9) |
| (2026-10-02) 1 win to Bronze I, 2 to Bronze II, 3 to Bronze III... | divisions in wins of 100 XP (section 4.2) |
| (2026-10-02) No Silver before about 2 hours | Silver I at 21 wins, about 6 hours of play at 50% |
| (2026-10-02) 3 h a day at 50%: Expert 1 month, Veteran 2, Master 3-4, Grandmaster 6, Reyes 7+ | the ramp from Diamond (section 4.2): about 1.1, 1.9, 3.3, 5.6 and 8.6 months |
| (2026-10-02) XP strictly from skill | wins only; harder modes, streaks and stronger opponents pay more |
| Losing is never a punishment (2026-09-28) | a loss gives 0 XP, never negative, and $150 |
| Only a few hundred ever reach Reyes | fixed Reyes at 307,500 XP (section 4.10) |
| VIP 2x money, not overpowered | 2x money and faster block timers, never odds, blocks or XP |
| Onboarding feels fast | a Rare block and Bronze I on the first win (section 2) |

---

## 2. The first hour (onboarding)

What a new player gets, in order, at an ordinary 50% win rate:

| When | What happens |
|---|---|
| Join | 1 starter ability spin (the tutorial, 2026-10-03). Day 1 of the login loop (**$5,000**) waits in the Rewards menu until claimed (designer, 2026-10-04: no popups, nothing given on join). |
| The first win (the tutorial) | Unranked to **Bronze I**: a **Standard lucky block at once** (the tutorial opens it to an Uncommon cue; `Config.Tutorial.BronzeBlockKind`), then $2,500, a Mystery block, the Bronze Cue, the [BRONZE] tag and +1 ability spin once claimed in Rank. The win's own block is a **guaranteed Rare block** in the hotbar, on its normal **1 h timer** (designer, 2026-10-03). |
| The second tutorial win | its Mystery block is usually the first one the player opens (5 minutes after the win: Standard or Uncommon, 93%) |
| 10 minutes | playtime gift: $2,000 |
| 30 minutes | playtime gift: 1 Mystery block |
| The third win | **Bronze II**: $1,000 |
| 60 minutes | playtime gift: 2 Mystery blocks + 1 ability spin |
| About 1 hour after the first win | the Rare block's timer is done: it opens |

Every new cue also pays finder's money the first time (section 18: $500 a Common, $1,000 an
Uncommon). A rough count, not a model run: about $20,000 by the end of the first hour, about
8 blocks opened, and Bronze I or II. Silver comes after about 6 hours of play (21 wins).
The Starter Pack offer appears after the first block opening (section 11.4).

---

## 3. Money

Money is earned by playing and spent in the shop. It **never trades** between players.

### 3.1 One match (1v1 against a person, Classic)

| What | Money | Notes |
|---|---|---|
| Each ball that counts for you | **$100** | your group, legal open-table pots, the break's balls, the 8 when it wins |
| Nice shot on top | **bank or kick +$150, combo or carom +$200** | to the shooter only |
| Win | **+$500** | only after a real match (past the one-minute mark, not a quick forfeit) |
| Loss | **+$150** | money even when you lose; the leaver gets nothing |
| Win streak | **+$250** on each win from the 3rd in a row | against people only |

Average match: winner about **$1,340**, loser about **$600**. At 7.5 matches an hour that is
**about $7,300 an hour** (plan, 2026-10-02).

### 3.2 By opponent

| | Against people | Play against PC (on purpose) | Disguised bot (queue fallback, tutorial, lobby bots) | Solo |
|---|---|---|---|---|
| Each ball | $100 | $100 | $100 | **$30** until $3,000 of solo money in a UTC day, then **$10** |
| Nice shot on top | bank/kick +$150, combo/carom +$200 | same | same | none |
| Win / loss bonus | $500 / $150 | **$250 / $80** | $500 / $150 | none |
| Win streak (3rd win in a row on) | +$250 | none | none | none |
| Daily limit | the same-opponent rules (3.6) | after **$10,000** of PC money in a UTC day, everything pays half | after **20 disguised wins** in a UTC day they pay the PC rows and drop no block (hidden) | as above |
| Mystery block on a win | every win | the **first 10 PC wins** of a UTC day | every win (until the 20) | never |
| XP | 100 a win | x0.75, x0.5 from Expert | like a person, stored as a PC win, no streak | none |

- The disguised limit is **hidden** (designer, 2026-10-03): the result screen just shows the
  smaller numbers and no block, with no message. It stops farming lobby bots in an empty server.
- A disguised bot that forfeits gives a full disguised win, even under one minute. Both
  tutorial games are real wins, and the tutorial bot's early 8 pays in full.
- A disguised win counts as a PC win in the stats (never on the most-wins board).

### 3.3 Team matches (2v2, 3v3)

Every ball your team pots pays **each teammate $100**, so an hour of 2v2 or 3v3 earns about the
same as 1v1. The nice-shot bonus goes only to the shooter. The win and loss bonus, the Mystery
block (each winner) and XP are per player, by the same rules; XP uses the opposing team's
average rank for the gap (section 4.4).

### 3.4 Difficulty

The difficulty money multiplier is **on** (designer, 2026-09-26; switched on 2026-10-03 now that
the rank lock exists from Gold I). It is separate from the XP mode multiplier (1.25 / 1.5).

| | Classic | Difficult | Challenger |
|---|---|---|---|
| Money | x1 | **x1.5** | **x2** |
| Match length (assumed) | 6.5 min | 7.5 min | 8.5 min |
| Money an hour | about $7,300 | about $9,700 | about $11,600 |

### 3.5 Boosts and how they stack

Boosts **add**, then difficulty multiplies (plan, 2026-10-02):

money = base x difficulty x (1 + VIP 1.0 + Money Party 1.0 + Starter hour 1.0 + group 0.1)

- Only **match money** is boosted (balls, nice shots, match bonuses). Never rewards, finder's
  money, sell-back or packs.
- The Starter Pack's hour of 2x adds to VIP's: x3 for that hour (designer, 2026-10-03).
- The group's +10% is on while the player is a member of the game's group (section 10.4).
- The most is x4.1 before difficulty, x8.2 in Challenger.
- No boost ever changes block odds or how many blocks a player gets. VIP's halved block
  timers (11.2) are the one VIP perk outside money.

### 3.6 Anti-farming (alts and friends)

- **Same opponent, same UTC day:** matches 1-5 pay in full; 6-10 pay half the XP and half the
  win/loss bonus and drop no block; from the 11th, no XP, a quarter of the bonus, half the
  ball pay, no block. At most **3 blocks a day from beating the same account**
  (`Config.Economy.DropsPerOpponent`).
- **The loser must have played 5 real matches** for the winner's block (a fresh alt can't
  feed blocks; `Config.Economy.DropLoserMinMatches`).
- **Short matches:** pots are still paid live, but money from matches that end before the
  one-minute mark counts toward a **$2,000 a day** short-match limit; past it, balls before the
  one-minute mark pay **$10** each.
- Forfeits, leavers and the one-minute mark stay as built (GDD section 13).
- Private servers, when they come: no XP, no blocks, solo-rate money.
- With no trade gate (section 12), these rules and the invite cap are the alt protection.

### 3.7 How money is shown

Full digits up to **$999,999**, then short: **$1.2M** (`Format.money`). The currency is always
called "money".

---

## 4. Ranks (XP)

### 4.1 One bar, never lost

Rank is the one progression bar and the game's main way to show status (designer, 2026-09-28:
Levels are gone). Its number is **XP** (the save's `RankXp`). **XP is never lost**, so nobody
ever drops a rank, and losing a match is never a punishment, only a missed step.

**Reworked 2026-10-02** (designer, after friends reached Gold I in a few hours of play): XP
comes **only from winning**, and only skill makes it come faster. **A win is 100 XP, a loss
0.** The Rookie Boost, the first-win-of-the-day bonus, VIP's +50% XP and Classic's fade are
gone. Save version 6 (2026-10-03) then started every save over from Unranked.

### 4.2 The ladder

Counted in wins of 100 XP: **1 win to Bronze I** (a player is Unranked until their first win),
**2 more to Bronze II, then 3, 4, 5... one more win each division up to Platinum V**, then a
steady ramp sized so that a **3-hour-a-day player who wins half their games** reaches Expert
in about a month, Veteran 2, Master 3.5, Grandmaster 6 and Reyes about 9. No division is ever
smaller than the one before it. The first win's 100 XP lands inside Bronze I, so Bronze I is
300 wide.

XP needed for each division, I to V (wins = XP / 100):

| Tier | I | II | III | IV | V | Tier total | Tier starts at (wins) |
|---|---|---|---|---|---|---|---|
| Bronze | 300 | 300 | 400 | 500 | 600 | 2,100 | 0 XP (the first win) |
| Silver | 700 | 800 | 900 | 1,000 | 1,100 | 4,500 | 2,100 (21) |
| Gold | 1,200 | 1,300 | 1,400 | 1,500 | 1,600 | 7,000 | 6,600 (66) |
| Platinum | 1,700 | 1,800 | 1,900 | 2,000 | 2,200 | 9,600 | 13,600 (136) |
| Diamond | 2,500 | 2,800 | 3,200 | 3,600 | 4,000 | 16,100 | 23,200 (232) |
| Expert | 4,500 | 5,000 | 5,600 | 6,200 | 6,900 | 28,200 | 39,300 (393) |
| Veteran | 7,700 | 8,800 | 10,000 | 11,300 | 12,700 | 50,500 | 67,500 (675) |
| Master | 14,300 | 15,700 | 17,000 | 18,000 | 19,500 | 84,500 | 118,000 (1,180) |
| Grandmaster | 20,000 | 20,500 | 21,000 | 21,500 | 22,000 | 105,000 | 202,500 (2,025) |
| **Reyes** | | | | | | | **307,500 (3,075)** |

XP for a match against an equal opponent, at every tier:

| | Classic | Difficult | Challenger |
|---|---|---|---|
| Win | **+100** | +125 | +150 |
| Loss | 0 | 0 | 0 |

How it is built: a base of 100 for a win and 0 for a loss at every tier, times the mode
(Classic 1, Difficult 1.25, Challenger 1.5), the opponent gap (4.4), PC (4.5) and the win
streak (4.3). Unranked plays by Bronze's row.

### 4.3 How skill still counts

With no XP loss, time alone would eventually reach the top, so skill decides the speed:
- **Only wins count**: a player who wins twice as often climbs twice as fast.
- **Harder modes pay more**: a Difficult win is 1.25 wins, a Challenger win 1.5.
- **Win streak**: from the 3rd win in a row against people, each win gives +25% XP.
- **Opponent strength** (4.4): beating stronger players pays up to 1.5x, much weaker ones far
  less.

### 4.4 Beating much lower players pays less (smurf protection)

The gap is your division minus the opponent's (Bronze I = 1 ... Grandmaster V = 45; a team uses
the opposing team's average). The factor comes from the Elo expectation. It is **gentler from
Bronze to Diamond** (scale 12 divisions, a win never under 30%), because in a small server the
only people around may be weaker, and **strict from Expert up** (scale 8, down to 10%):

| Gap (divisions) | +15 | +10 | +8 | +5 | +3 | +1 | 0 | -1 | -3 | -5 |
|---|---|---|---|---|---|---|---|---|---|---|
| Win x, Bronze to Diamond | 0.30 | 0.30 | 0.35 | 0.55 | 0.72 | 0.90 | 1 | 1.10 | 1.28 | 1.45 |
| Win x, Expert and up | 0.10 | 0.11 | 0.18 | 0.38 | 0.59 | 0.86 | 1 | 1.14 | 1.41 | 1.50 |

Formula: E = 1 / (1 + 10^(-gap / scale)); factor = 2(1 - E), clamped to the floor (0.3 or
0.1) and 1.5. The win bonus money uses it too (never under half); ball money is untouched.

### 4.5 Boosts, PC and forfeits

- **XP boosts**: only the win streak (+25%, 4.3). The Rookie Boost, the first win of each UTC
  day and VIP's XP were removed on 2026-10-02: they were not skill.
- **PC**: XP x0.75 below Expert and x0.5 from Expert at launch, so a player in a quiet server
  still climbs against the bot of their rank. Once the global queue exists and the top is
  busy, Expert and up drops to x0.1 (section 14).
- **Disguised bots**: XP like a person, stored as a PC win, no streak.
- **Forfeits**: as built. The forfeiter gets no XP at all; the winner is paid only after the
  one-minute mark.

### 4.6 Grandmaster and Reyes

Fixed XP amounts, like every other tier: Grandmaster I at 202,500 XP (2,025 Classic wins),
**Reyes at 307,500 XP** (3,075 Classic wins; 2,050 Challenger wins). For a 3-hour-a-day player
winning half their games that is about 9 months of play; at an hour a day, over 2 years. The
first player ever to reach Reyes is announced in every server and gets a one-of-one Unique
title; each later Reyes is announced too. How many ever get there: 4.10.

### 4.7 Difficulty unlocks

By rank: host a **Difficult** or **Challenger** table from **Gold I** (2026-10-02). Gold I is 66
wins, about 17 hours of Classic play. Below it the host card greys them with "Requires Gold
I+". Anyone may join a harder table as a guest, with a warning and Play anyway. The table's
difficulty sets its money and XP multipliers for everyone at it.

### 4.8 Rank rewards (paid once, the first time you reach it)

The plan's table (plan, 2026-10-02, section 6; `Config.Ranks.Rewards`). Reaching a tier also
gives the tier's cue (Exclusive, never traded or sold), its chat tag and ability spins (+1 for
Bronze, Silver and Gold; +2 for Platinum and Diamond; +3 from Expert up).

| Tier | Each new division II-V | Reaching the tier (division I) |
|---|---|---|
| Bronze | $1,000 | $2,500, a Mystery block (plus the Standard block given at once with the first win) |
| Silver | $2,000 | $5,000, a Rare block |
| Gold | $3,500 | $10,000, 2 Rare blocks |
| Platinum | $6,000 | $20,000, 3 Rare blocks |
| Diamond | $15,000 | $50,000, an Epic block |
| Expert | $30,000 | $100,000, 2 Epic blocks |
| Veteran | $50,000 | $200,000, 3 Epic blocks |
| Master | $80,000 | $400,000, a Legendary block |
| Grandmaster | $150,000 | $750,000, 2 Legendary blocks |
| Reyes | - | $2,000,000, a Mythic block, the rainbow tag |

Blocks from rank rewards (`Config.Ranks.Rewards.Tier[tier].Blocks`) land in the hotbar on their
normal timers (section 7.2). Only Bronze's Standard block is given at once (the tutorial opens
it); every other reward waits in Rank until claimed (designer, 2026-10-03). A Reyes Cue proves
Reyes: it can't be traded.

### 4.9 How long each tier takes

Hours of play against equal opponents (a Classic match plus the time between is about 8
minutes, so 7.5 matches an hour; the streak bonus included):

**Classic only:**

| Win rate | Silver | Gold | Platinum | Diamond | Expert | Veteran | Master | Grandmaster | Reyes |
|---|---|---|---|---|---|---|---|---|---|
| 45% | 6 h | 19 h | 38 h | 65 h | 111 h | 190 h | 333 h | 571 h | 867 h |
| 50% | 5 h | 17 h | 34 h | 58 h | 99 h | 169 h | 296 h | 508 h | 772 h |
| 55% | 5 h | 15 h | 31 h | 52 h | 89 h | 152 h | 266 h | 456 h | 693 h |
| 60% | 4 h | 13 h | 28 h | 47 h | 80 h | 138 h | 241 h | 413 h | 627 h |

**A typical mix of modes** (Classic early, some Difficult from Gold, mostly Challenger from
Diamond): about 10% faster from Diamond (50%: Expert 91 h, Grandmaster 445 h, Reyes 673 h).

In months for the designer's reference player (**3 hours a day, 50%, Classic**): Silver on
day 2, Gold in about 6 days, Diamond in about 3 weeks, **Expert 1.1 months, Veteran 1.9,
Master 3.3, Grandmaster 5.6, Reyes 8.6**. An hour-a-day player takes three times as long
(Expert in about 3 months); a 5-hour-a-day grinder at 55% about half as long (Expert in about
18 days, Reyes in about 5 months).

### 4.10 What the ranks look like over a year (simulation)

Simulation (rerun 2026-10-02): 2,000 new players a day for a year (about 2,300 peak players
online by the end), most leaving on day one and a few staying for a year or more (playing up to
6 hours a day), each with a hidden skill; half their matches near their own rank. "Ever" counts
everyone who reached the tier or higher, including players who later quit.

| Tier | Share of players still playing, day 90 / 180 / 365 | Ever reached by day 365 | Mean skill (day 365) |
|---|---|---|---|
| Bronze | 39% / 32% / 26% | 574,000 (everyone who ever won) | -0.17 |
| Silver | 26% / 21% / 18% | 165,000 | -0.09 |
| Gold | 16% / 16% / 13% | 71,000 | -0.08 |
| Platinum | 8.8% / 11% / 10% | 38,600 | -0.02 |
| Diamond | 5.0% / 7.4% / 8.4% | 23,200 | +0.02 |
| Expert | 3.4% / 6.7% / 8.8% | 14,500 | +0.16 |
| Veteran | 1.1% / 4.5% / 7.9% | 7,800 | +0.29 |
| Master | 0.05% / 1.7% / 5.1% | 3,300 | +0.52 |
| Grandmaster | 0 / 0.23% / 2.2% | 1,050 | +0.73 |
| **Reyes** | 0 / 0 / 0.76% | **238** | +1.33 |

What this means:
- **The ladder spreads out.** No tier holds a pile of players; each tier up holds fewer, and
  the share above Expert grows slowly over the year.
- **Nobody reaches Grandmaster in the first 3 months, or Reyes in the first 6.** About 240
  players reach Reyes in the first year: the heavy grinders. If that is too many, the lever is
  the Grandmaster widths.
- **Rank still rewards time as well as skill**, since a loss costs nothing: mean skill rises
  tier by tier, but a steady average player does get to Expert and beyond.

The retention and playtime in the simulation are guesses, so read it for shape, not exact
counts.

### 4.11 Seasons

**Ranks never reset** (designer, 2026-09-28): your XP is yours forever. Seasons can still give
a reward for the highest tier reached during that season (a season-coloured tier cue,
Exclusive, plus blocks), without taking anything away. Seasons come after release.

---

## 5. No Levels

The account Level and its EXP are gone (designer, 2026-09-28). What they did moved:
- **Money every level** now comes from rank divisions (4.8).
- The **Rookie Boost**, the **first win of the day** and **VIP's XP** moved to rank XP, then
  were removed on 2026-10-02 (4.5).
- The anti-alt rule "the loser must be Level 3" became "the loser must have played 5 real
  matches" (3.6).

---

## 6. Rarities and the catalog

| Group | Rarities | Comes from | Trade | Sell back |
|---|---|---|---|---|
| Block rarities | Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret | lucky blocks (and trades) only | yes | yes |
| **Unique** | numbered Limited cues (only two: the Firework Cue and the Beta Cue, both from the Grand Opening block; there is no Founder's Cue, ever) | the Grand Opening block's two Unique rows (9.2), or the Limited shelf for a set time | yes | no |
| **Exclusive** | the VIP Cue, the Starter Cue, the ten rank cues (Bronze Cue ... Reyes Cue), later season cues | one special way each | **never**, except the Starter Cue (designer: VIP never, 2026-09-28; the Starter Cue trades, 2026-09-29) | no |

What rarity looks like (GDD section 12, UI_STYLE section 4 colours): Common and Uncommon keep
the plain wisp trail (Uncommon tinted); Rare adds a coloured trail and small pocket burst; Epic
has its own trail and pocket effect; Legendary an animated trail, pocket effect and sound;
Mythic the celestial shimmer and its own VFX; Secret a one-of-a-kind full set.

**Launch catalog: 46 block cues** (unchanged by the plan): 7 Common, 9 Uncommon, 10 Rare,
9 Epic, 7 Legendary, 3 Mythic, 1 Secret. Classic is labelled Common too but is the free
default: everyone owns it, no block drops it, and it is never traded or sold. Plus 12 Exclusive
(10 rank, VIP, Starter) and 2 Unique (Grand Opening and Beta, both from the Grand Opening
block; there is no Founder's Cue, ever: designer, 2026-10-05). The list and order are
`Progression/Catalog.luau`; each cue's look is its skin (`src/shared/CueSkins`).

Adding cues later keeps each rarity's % per block; each cue's own share shrinks.

---

## 7. Lucky blocks

Cases became **lucky blocks** on 2026-10-04 (designer): a block waits in the hotbar (and its
bag), is held, thrown into the world and opened there with a hold prompt; the reel plays
(`BlockReel`, the dark look), a Rare or better cue plays its pull cutscene, then the "YOU GOT"
card. The odds engine is `Config.BlockOdds` (`Progression/BlockOdds.luau`: one odds row per
block kind, `Config.LuckyBlocks.Kinds[kind].Odds`) and the Mystery block's tier roll is
`Config.BlockOdds.Drop` (`Progression/BlockDrop.luau`). The 8-ball reveal, its climb and the
`CaseDrop` payload are gone.

### 7.1 The win's Mystery block

After **every real win** the server gives one **Mystery lucky block** (plan, 2026-10-02; blocks
2026-10-04). It rolls its tier when it is opened, out of 1,000,000
(`Config.BlockOdds.Drop.Weights`; trimmed 2026-10-04 so the day-30 targets hold with the new
block sources):

| Tier | Weight | Chance |
|---|---|---|
| Standard | 680,000 | 68% |
| Uncommon | 250,000 | 25% |
| Rare | 67,000 | 6.7% |
| Epic | 2,800 | 0.28% |
| Legendary | 196 | 0.0196% |
| Mythic | 4 | 0.0004% |

- **Every win gives one, forever.** The old limits (every win for 50 wins, then 10 a day, then
  every 2nd) are gone. The anti-farm rules (3.6) and the PC and disguised limits (3.2) still
  apply. Solo never drops.
- **The Mystery block's timer is 5 minutes** when won (`Config.LuckyBlocks.Kinds.Mystery.Timer`
  *(tune)*); a bought one opens at once. VIP halves it (11.2). When it opens it morphs into
  the tier's block and that block opens in the same flow.
- **The first win's block is a guaranteed Rare block**, on its normal 1 h timer (designer,
  2026-10-03; `Config.BlockOdds.Drop.FirstWin`). The tutorial also gives Bronze's Standard
  block at once (section 2).
- **Pity** (the counters are sent to the screen): the **10th** Mystery block in a row that
  rolls below Rare is Rare; the **150th** below Epic is Epic. Pity never gives a Legendary. It
  counts every Mystery block: wins, bought and reward ones (`PityRare`, `PityEpic`).
- Mystery blocks also come from the shop (section 9.1) and from rewards (section 10).

**The payload**: a win's block rides `MatchSummary.block = { kind, readyAt }` (already in the
hotbar when it arrives; `readyAt` 0 = ready now). The server decides everything before the
reel starts; the reel only shows it. No fake "almost" moments.

**Per Mystery block overall**, the chance of each cue rarity (`BlockDrop.rarityOdds()`):

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| 61% | 33.83% | 5.0423% | 0.10872% | 0.016644% | 0.0021197% | 0.0002163% |

### 7.2 The blocks

Each tier block guarantees at least the rarity below its name (the Mythic block: Legendary or
better). Odds in percent; each row adds to exactly 100 (in Config, whole parts of 1,000,000).
Timers are `Config.LuckyBlocks.Kinds[kind].Timer`.

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Opens in |
|---|---|---|---|---|---|---|---|---|
| Standard | 75% | 23% | 1.99% | 0.009% | 0.0009% | 0.0001% | - | at once |
| Uncommon | 40% | 54% | 5.95% | 0.045% | 0.0045% | 0.0005% | - | at once |
| Rare | - | 70% | 29.6% | 0.35% | 0.045% | 0.0045% | 0.0005% | 1 h |
| Epic | - | - | 78% | 19% | 2.6% | 0.36% | 0.04% | 6 h |
| Legendary | - | - | - | 75% | 22% | 2.7% | 0.3% | 24 h |
| Mythic | - | - | - | - | 75% | 22% | 3% | 48 h |

The other kinds (`Config.BlockOdds.List`, each its own odds row):

| Block | Odds | Opens in | Comes from |
|---|---|---|---|
| Mystery | rolls a tier above (7.1) | 5 min when won, at once when bought | wins, the shop, rewards |
| Grand Opening | Uncommon 56.35%, Rare 37.45%, Epic 2.5%, Legendary 0.35%, Mythic 0.046%, Secret 0.004%, **the Firework Cue 3%, the Beta Cue 0.3%** (the 400th opened guarantees Beta) | at once | the shop's 21-day deal (9.2) |
| Starter | Rare 97%, Epic 2.5%, Legendary 0.45%, Mythic 0.045%, Secret 0.005% | at once | the Starter Pack (11.4) |
| Sky | Common 45%, Uncommon 45%, Rare 9.9%, Epic 0.09%, Legendary 0.009%, Mythic 0.001% | at once | Lucky Rain (no source wired yet) |
| Lucky 8 | the Rare row | at once | none yet (the group and favorite rewards give Mystery blocks today, 10.4) |
| Gift | the Rare row | 12 h | none yet |

- **No block is sold permanently** (plan, 2026-10-02). The four money cases, Buy-10, case
  sales and the Event Case are gone. Blocks come from wins, rewards, the shop's Mystery and
  Grand Opening deals and the restock shop. Mythic blocks are never sold.
- **Timers** start by themselves when the block lands in the hotbar. They all run at once;
  there are no slots. Opening a block before its timer is done answers "Not ready yet"; the
  hotbar slot counts down. A bought block (paid origin) opens at once.
- **VIP** halves every timer (`Config.LuckyBlocks.VipTimerFactor` 0.5; Quick Cases was
  retired into VIP, designer 2026-10-04).
- **Skips**: a timer is finished with Robux only, 19 R$ (section 9.1). No money skip.
- A block can be **traded** only once its timer is done (section 12).
- Blocks live in the hotbar and its bag (`Config.LuckyBlocks.MaxBlocks`), never in the
  Inventory menu.

### 7.3 Odds screen and per-cue odds

Every cue of a rarity in a block has an equal share: **cue % = rarity % / cues of that rarity
in the block**. With the launch catalog, each Legendary in the Legendary block is 22 / 7 =
3.1429%, each Mythic 2.7 / 3 = 0.9%, and the one Secret 0.3%. The shop's block cards and the
reel show the odds; an **"Odds"** button (a word, not just an icon) lists every cue with its
%, and totals exactly 100%.

**Cue cards** show the rarity, **its % per Mystery block and "N exist"**, for example "EPIC ·
0.109% · 1,284 exist". A cue's own % shows only in the Odds list. "N exist" reads "fewer than
10" until there are 10 copies.

### 7.4 Announcements and retiring

- Unboxing a **Mythic or Secret** is announced in every server; a **Legendary** in the opener's
  server (plan, 2026-10-02). The every-server line reads "[GLOBAL]: <username> pulled a
  Mythical Cue!" in a pastel rainbow, or "... a Secret Cue!" in red (designer, 2026-10-05). No
  announcement names the cue, only its rarity (designer, 2026-10-05).
- A **Legendary block appearing in the restock shop** is announced in every server.
- **Retired (vaulted) cues never come back** (plan, 2026-10-02; the old event-case return is
  gone). Odds screens update the moment a cue is retired.

How rare things end up across the whole game is section 1 (the day-30 targets).

---

## 8. Selling cues back

Any block-rarity cue can be sold for money, with a confirm step from Epic up and a "Duplicate"
tag on extras. Exclusive and Unique cues can't be sold. A paid-origin copy is sold first.

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| $150 | $400 | $1,500 | $25,000 | $250,000 | $2,500,000 | $25,000,000 |

Selling also removes cues from the game, which keeps the ones that stay worth more.

---

## 9. What money buys, and the Limited shelf

**Block cues are never sold directly** (designer, 2026-09-27). A Common-to-Secret cue comes
only from a lucky block or a trade. That keeps every block a chance at something money can't
simply buy, and gives trading its purpose. (Research: items that stay buyable lose their trade value, while
items sold for a short time and then retired become the most valuable in the game.)

| Item | Price | Notes |
|---|---|---|
| Mystery block | **$4,900**; 10 for **$44,100** (the price of 9) | the win's block, bought: same tier roll and pity, opens at once |
| Grand Opening block | **$49,000**; 3 for $139,000; 10 for $441,000 | only during its 21-day deal (9.2) |
| Restock shop | see 9.1 | new blocks every 10 minutes |
| Timer skip | Robux only, **19 R$** | no money skip (designer, 2026-10-04) |
| Ability spin | **$17,500** each (buy 1, 5, 10 or 50; no bulk discount) | section 11.8 |
| Limited cues | none at release | 9.2 |

**When a player has part of the price**, the buy button says "Need $X more" and opens the money
packs with the smallest pack that covers the gap highlighted. Never right after a lost match.

### 9.1 Mystery blocks, the restock shop and the timer skip

**Mystery blocks**: the win's block, bought (section 7.1) with money ($4,900, or 10 for
$44,100; `Config.Shop.Deals.Mystery`) or Robux (Mystery1 25 R$, Mystery10 229 R$). A bought
block is paid origin and opens at once. They are paid random items (section 13).

**The restock shop** restocks every **10 minutes on the clock** (UTC :00, :10, ...). Every
server shows the same blocks (picked from the time slot's number), with a real countdown
(`Config.Shop.Restock`, `Progression/Restock.luau`). **Three slots each roll one block kind**,
and a fourth, VIP-only slot rolls its own (chances out of 10,000):

| Block | A normal slot | The VIP slot | Price | Stock per player per restock |
|---|---|---|---|---|
| Uncommon | 62% | - | $14,900 | 3 |
| Rare | 36.6% | 96% | $34,900 or 99 R$ (RestockRare) | 1 |
| Epic | 1.35% | 3.85% | $349,000 or 999 R$ (RestockEpic) | 1 |
| Legendary | 0.05% | 0.15% | $3,490,000 or 4,999 R$ (RestockLegendary) | 1; announced in every server |

- Stock is per slot, one block per press. A slot's shared stock counter (`GlobalStock`, the
  Legendary's "25 worldwide" from the plan) is in the code but no row sets it today.
- Blocks bought here are paid origin and open at once.
- Mythic blocks are never sold.

**The timer skip**: Robux only, **19 R$** (`LuckyBlockSkip`, product 3716368528), on the block
the player picked, whatever its tier; the money skip and the four Skip products are gone
(designer, 2026-10-04). A late receipt whose block is already ready keeps a saved skip credit
for the next timer. It is a paid random item (section 13). A skip does not change a block's
origin. Only the designer's account may bypass timers without paying (testing); the countdown
stays visible.

### 9.2 The Limited shelf

The Limited shelf sells **Unique** cues: exclusive designs that never appear in a tier block.
- **For a set time only**, with a real countdown that never restarts. When the time is up it
  is **never sold again** and becomes trade-only forever.
- **Numbered** (#1, #2, ...), **one per player**, optionally **copy-capped** (sold out when
  the cap is reached, across all servers).
- Priced in money, so it is a real saving goal. Some may be sold for Robux; a known item for
  Robux is not a paid random item. Limited cues bought with money or Robux are paid origin.

**At release the shelf is empty** (designer, 2026-10-04): the $149,000 Firework Cue shelf
is gone. The Firework Cue and the Beta Cue come from the **Grand Opening block** only
(7.2; `Config.Shop.Deals.GrandOpening`): $49,000, 3 for $139,000, 10 for $441,000, or 49 / 129
/ 349 R$, for **21 days** from a start the designer sets right before the release is published
(`StartsAt` 0 = off; a "Vaulted" card stays 7 days after the end). The release sale (30% off
the big money packs, VIP and 10 Mystery blocks) runs on the same window
(`Config.Shop.ReleaseSale`).

- The shelf code stays (`Config.Shop.Limited`, one row per Limited plus its catalog cue) for
  a later Limited; while empty nothing shows.
- The Firework Cue has placeholder colours for now (black shaft, gold rings, felt-green
  wrap; designer, 2026-10-03); the real skin comes later.
- **There is no Founder's Cue**, ever (designer, 2026-10-05): its catalog cue, name and Robux
  product are gone.
- **After launch**: one new Limited about every 2 weeks when art exists, $149,000-$499,000,
  some for Robux. None is scheduled yet (designer, 2026-10-03). A new Limited is one Config row
  plus its catalog cue.

### 9.3 Copies in existence

Every cue, in the inventory, the Index, trades and the Limited shelf, shows how many exist in
the game ("1,284 exist"; "fewer than 10" below 10). A global counter per cue goes up when one is
unboxed or bought and down when one is sold back.

---

## 10. Free rewards

Free rewards are not paid random items, so they work everywhere, restricted regions included.

### 10.1 Daily login: a 7-day loop

One claim per UTC day; the seven days repeat (plan, 2026-10-02):

| Day 1 | Day 2 | Day 3 | Day 4 | Day 5 | Day 6 | Day 7 |
|---|---|---|---|---|---|---|
| $5,000 | 1 Mystery block | $10,000 | 2 Mystery blocks | $15,000 | 3 Mystery blocks | a Rare block + 2 ability spins |

- **Every day is claimed in the Rewards menu**, day 1 included (designer, 2026-10-04: no
  reward popups; nothing is given by itself on join, and the old `AutoClaim` fields are gone).
- Every reward row is `{ money, blocks = { [kind] = n }, spins, lucky }` (`Config.Daily`).
- **One free streak freeze a UTC week** (weeks start Monday): one missed day is covered by
  itself and the streak goes on. Two or more missed days start it over.
- **VIP adds 1 ability spin** to each day's claim.
- Everyone also gets **1 free ability spin a day** on the Abilities screen (11.8).

### 10.2 The 28-day track

Counts every day claimed in total. It never resets and repeats every 28 days. On the day the
count reaches a step, its reward is added to that day's claim:

| Day 7 | Day 14 | Day 21 | Day 28 |
|---|---|---|---|
| a Rare block | 2 Rare blocks | 2 Rare blocks | an Epic block |

This replaces the old weekly Epic Case and the day-28 Legendary Case.

### 10.3 Playtime gifts

Minutes played in a UTC day, each claimable once that day in the Rewards menu (never given by
itself; designer, 2026-10-04):

| 10 min | 30 min | 60 min | 90 min | 120 min |
|---|---|---|---|---|
| $2,000 | 1 Mystery block | 2 Mystery blocks + 1 ability spin | $10,000 | a Rare block |

### 10.4 Group, likes, invites and codes

- **Group** (designer, 2026-10-03): the game's Roblox group **675425213** ("Lucky 8"). The
  Rewards card has **Join** (an in-game prompt) then **Claim**: **3 Mystery blocks**, once per
  player. While a member, match money gets **+10%** by itself (checked on join and on Claim).
- **Favorite** (GUI lane, 2026-10-03): favoriting the game through Roblox's prompt gives
  **$10,000 + 1 Mystery block** once (`Config.Social.FavoriteReward`; Roblox gives the server
  no way to check a favorite, so the client reports it).
- **Like codes** (designer, 2026-10-03): six codes, written now and **switched on live** by the
  designer with `/code on <CODE>` (every server at once, no republish) when the game reaches
  each like milestone:

| Code | Likes | Gives |
|---|---|---|
| LIKES1K | 1,000 | $10,000 + 1 Mystery block |
| LIKES5K | 5,000 | $25,000 + 2 Mystery blocks |
| LIKES10K | 10,000 | a Rare block + 3 ability spins |
| LIKES25K | 25,000 | 2 Rare blocks |
| LIKES50K | 50,000 | $100,000 + 2 Rare blocks |
| LIKES100K | 100,000 | 3 Rare blocks + 5 ability spins |

  Until switched on, a like code answers as unknown. The spin screen's code banner shows the
  current code.
- **Invites** (designer, 2026-10-03, light checks): a friend who joins through your in-game
  invite, is brand new to the game, and wins any real match that is not solo (bots count)
  gives **both of you a Rare block** (`Config.Social.InviteBlock`). The inviter's reward comes
  once ever (their first invited friend's first win; GUI lane, 2026-10-03, `InviterOnce`),
  within the **5 a UTC month** cap; an offline inviter gets theirs on their next join. Every
  invited friend still gets their own block.
- **Codes** (case-insensitive, once per player, an optional end date):

| Code | Gives |
|---|---|
| WELCOME | $5,000 + 1 Mystery block |
| 8BALL | $2,500 |
| ROOFTOP | a Rare block (until 2026-12-31) |
| RELEASE | 3 ability spins (the tutorial's code; it replaced ABILITIES, 2026-10-03) |

  Codes give only money, lucky blocks and spins: never a cue, pass or boost sold for Robux.

---

## 11. Robux

Robux prices are shown from Roblox's live price (`GetProductInfoAsync`), never typed into the
UI, because Roblox Plus, regional pricing and Roblox's own discounts change what each player
pays. Every product id is 0 until the designer creates it on the Creator Dashboard and pastes
the id into `Config.Products`; until then the shop says "Coming soon".

### 11.1 Money packs (developer products)

| Key | Name on Roblox | Robux | Money | Bonus |
|---|---|---|---|---|
| Pack1 | Handful of Cash | 49 | $9,000 | - |
| Pack2 | Stack of Cash | 99 | $19,500 | +7% |
| Pack3 | Bundle of Cash | 249 | $52,500 | +15% |
| Pack4 | Briefcase of Cash | 499 | $110,000 | +20% |
| Pack5 | Vault of Cash | 999 | $235,000 | +28% |
| Pack6 | Bank of Cash | 2,499 | $625,000 | +36%, **Best value** |
| Pack7 | Fortune | 4,999 | $1,300,000 | +42% |

**First purchase double**: the first money pack a player ever buys pays double money, once. It
is true for every player exactly once.

### 11.2 VIP (game pass, 499 R$)

499 R$ since 2026-10-04 (designer; was 599), when the Quick Cases pass was retired into it.

- **2x money** (+100%, adds with other boosts) on match money only (3.5).
- **Block timers twice as fast** (`Config.LuckyBlocks.VipTimerFactor`), timers already running
  included.
- **Skip and Auto Spin** on the ability spin screen (11.8; without VIP they answer "NoVip").
- **+1 free ability spin a day** (added to the day's login claim, 10.1).
- **The VIP restock slot**: a fourth slot every restock, Rare 96% / Epic 3.85% / Legendary
  0.15% (9.1).
- **The VIP Cue** (Exclusive, rainbow, never traded), a **[VIP]** chat tag before the rank tag
  ("[VIP] [GOLD] Name") and a rainbow name over the head (designer, 2026-09-28).
- **No blocks, no XP, no discount.** Never better block odds, never more blocks.

### 11.3 VIP welcome offer (developer product, 249 R$)

**VIP at half price for 24 hours from a player's first join**, with a real countdown that never
restarts. If they don't buy it, **one "welcome back" window of 24 hours** opens 7 days later,
then never again. It is a developer product that grants VIP in the save (VIP = owns the pass
**or** bought the offer), so only that player sees it. Friendly wording ("Welcome offer"),
never "LAST CHANCE". Opt it out of Managed Pricing so "half price" stays true.

### 11.4 Starter Pack (developer product, 99 R$)

Once per player, in the first 7 days after the first join, shown after the first block opening:
**a Starter lucky block** (Rare or better, 7.2; designer, 2026-10-04, `Config.Shop.StarterBlock`;
it replaced the Starter Cue in the pack), **$75,000** and **1 hour of 2x money** (adds to VIP:
x3, designer 2026-10-03). With a block inside it is a paid random item (section 13).

### 11.5 Everything Robux buys at release

**3 game passes and 31 developer products** (plan, 2026-10-02, reworked for lucky blocks
2026-10-04; `Config.Products`; the names and descriptions are `tools/products_spec.json`). The
Quick Cases pass (retired into VIP), Skip1h-Skip48h and the money timer skip are gone
(designer, 2026-10-04).

| # | Key | Kind | Robux | Gives |
|---|---|---|---|---|
| 1 | Vip | Game pass | 499 | 11.2 |
| 2 | UltSlot2 | Game pass | 59 | the second ability slot |
| 3 | UltSlot3 | Game pass | 99 | the third ability slot |
| 4 | VipOffer | Product, once | 249 | 11.3 |
| 5 | StarterPack | Product, once | 99 | 11.4 |
| 6-12 | Pack1-Pack7 | Products | 49 / 99 / 249 / 499 / 999 / 2,499 / 4,999 | 11.1 |
| 13 | Mystery1 | Product | 25 | 1 Mystery block |
| 14 | Mystery10 | Product | 229 | 10 Mystery blocks |
| 15-17 | GrandOpening1, GrandOpening3, GrandOpening10 | Products | 49 / 129 (was 147) / 349 (was 490) | Grand Opening blocks, only during the deal (9.2); ids still 0 |
| 18 | RestockRare | Product | 99 | the restock Rare block (only while in stock); id still 0 |
| 19 | RestockEpic | Product | 999 | the restock Epic block (only while in stock) |
| 20 | RestockLegendary | Product | 4,999 | the restock Legendary block (only while in stock) |
| 21 | LuckyBlockSkip | Product | 19 | finish one block's timer (9.1) |
| 22 | MoneyParty | Product | 199 | +100% money for everyone in the server for 15 minutes, the buyer's name announced; buying again adds 15 minutes (the shop offers it up to an hour queued) |
| 23-26 | Spin1, Spin5, Spin10, Spin50 | Products | 15 / 50 / 100 / 449 | ability spins (11.8) |
| 27-28 | Lucky1, Lucky3 | Products | 49 / 129 | Lucky Spins (11.8) |
| 29-32 | Pack4Sale-Pack7Sale | Products | 349 / 699 / 1,749 / 3,499 | the release sale's 30%-off copies of Pack4-Pack7 (9.2) |
| 33 | VipSale | Product | 349 | VIP at 30% off during the release sale |
| 34 | Mystery10Sale | Product | 160 | 10 Mystery blocks at 30% off during the release sale |

Plus a **Get Roblox Plus** button (`MarketplaceService:PromptRobloxSubscriptionPurchase`, no
product to create; Roblox pays the game 250 R$ a month for up to 3 months for each subscriber
signed up in the game).

**The shop is one scrolling page, no tabs** (`Config.Shop.Order`): 1 the Grand Opening block
(while its deal runs), 2 the Mystery block, 3 the restock shop, 4 the Starter Pack and VIP side
by side, 5 money packs, 6 Money Party, the ability slots and Get Roblox Plus. The timer skip is
offered on the block itself; spins on the Abilities screen. (The client's shop page was emptied
for the GUI overhaul on 2026-10-04: the frame and four jump buttons stay, the sections are being
rebuilt; UI_STYLE section 15 is the reference.)

A Robux receipt that no longer qualifies when it arrives (the VIP offer when already VIP or
after its window plus 10 minutes, a second Starter Pack) pays plain money instead at Pack1's
rate, Robux x 9,000 / 49 (the VIP offer about $45,700, the Starter Pack about $18,200).

### 11.6 Later (not at release)

In this order (plan, 2026-10-02): a season **Cue Pass** (449 / 1,199 R$), gift versions, the
**Beta Cue** on its own (1,000 R$, 500 copies), a Robux
restock refill (49 R$), a $4.99 a month subscription, rewarded ads paying money. Seasons, the
Cue Pass and event blocks all come after release.

### 11.7 Never sell

**Ruled out** (plan, 2026-10-02): a luck economy (potions, server luck, luck stats), money bets
on matches, blocks from VIP, offline income, money for idle time, always-on Epic or Legendary
blocks, fake near-misses. Also never: anything that protects rank, in-match aids (longer
guidelines, hints, power or spin upgrades), anything that hurts an opponent, and purchase
prompts right after a loss.

**Ability spins are the one luck purchase** (designer, 2026-09-28): normal spins for Robux and
money, and **Lucky Spins** (no Commons) for Robux. They are paid random items: the true odds are
always on the spin screen, pity is kept, and where PolicyService restricts paid random items
the R$ and $ buy buttons and Lucky Spins are refused; free spins still work. The ability bar
itself is never bought.

### 11.8 Ability spins

Players see **Ability Spins** on the **Abilities** screen; in code they stay ult spins
(`Config.Ults.Roll`, `Config.Ults.Earn`).

**Odds** (unchanged by the plan, shown as %). Each rarity's share is split evenly between its
abilities:

| Rarity | Normal spin | Each ability (normal) | Lucky Spin | Each ability (Lucky) |
|---|---|---|---|---|
| Common | 55% | 18.3333% (3 abilities) | 0% | 0% |
| Uncommon | 30% | 15% (2) | 63.1667% | 31.5833% |
| Rare | 12.2333% | 6.1167% (2) | 25% | 12.5% |
| Epic | 2% | 1% (2) | 8% | 4% |
| Legendary | 0.6667% | 0.3333% (2) | 3.3333% | 1.6667% |
| Mythic | 0.1% | 0.05% (2) | 0.5% | 0.25% |

**Pity:** every spin adds 1; the 100th spin without an Epic or better is Epic or better (Epic
72.3%, Legendary 24.1%, Mythic 3.6%); any Epic or better resets it.

**Getting spins:** 3 starter spins; 1 free spin a UTC day (never stacks); VIP +1 a day (10.1);
rank-ups (+1 for Bronze, Silver, Gold; +2 Platinum and Diamond; +3 from Expert up); +2 on day
7 of the login loop; +1 with the 60-minute playtime gift; codes (RELEASE 3; LIKES10K 3,
LIKES100K 5); VIP adds Skip and Auto Spin (designer, 2026-10-04: Quick Cases retired).

**Prices:**

| Product | Robux | Was |
|---|---|---|
| 1 spin | 15 | |
| 5 spins | 50 | 75 |
| 10 spins | 100 | 150 |
| 50 spins | 449 | 750 |
| 1 Lucky Spin | 49 | |
| 3 Lucky Spins | 129 | 147 |
| Ability Slot 2 (game pass) | 59 | |
| Ability Slot 3 (game pass) | 99 | |

With money: **$17,500 a spin** (buy 1, 5, 10 or 50; no bulk discount): about 2.4 hours of
Classic play a spin, so money spins are a slow trickle and Robux the cheap route.

**Rarities after the plan** (plan, 2026-10-02, by measured strength): **Magnet moves to
Uncommon, Heat Seeker to Common.** Portals (Rare since 2026-09-30) is **flagged for a
re-measure**: its 0.42 is a low bound (the model shooter never reuses the kept portals as a
player will), so it was not moved.

How strong each ability is (the measured ladder, 2026-09-29, GDD section 9; Worth = extra own
balls per use, net of the opponent's balls gifted, `Config.Ults.Catalog[id].Worth`):

| Rarity (now) | Ability | Worth |
|---|---|---|
| Common | Heat Seeker | 0.40 |
| | Eagle's Eye | 0.34 |
| | Super Bounce | 0.33 |
| Uncommon | Ghost | 0.47 |
| | Magnet (everyone's free starter) | 0.46 |
| Rare | Rewind | 0.53 |
| | Portals | 0.42 (a low bound) |
| Epic | Chain Lightning | 0.96 |
| | Time Stop | 0.47 |
| Legendary | Black Flash | 1.21 |
| | Steel Ball | 1.09 |
| Mythic | Black Hole | 1.32 |
| | Guangdong Tiger | 1.30 |

One inversion is left: Time Stop (Epic, 0.47) measures under Rewind (Rare, 0.53). Win rates
(`tools/ult_model.py`, 2026-09-29): a Mythic wins about 56 matches in 100 against an equal
player with Magnet; the Common to Epic best abilities all sit near 50%.

---

## 12. Trading

Built on the server (2026-10-03; the trade screen is the GUI lane's): `Progression/Trade.luau`,
`src/server/Trading.luau`, remotes `TradeRequest` and `TradeState`.

**Who and what**
- **Anyone in the server, no gate at all** (designer, 2026-10-03: no 25-win gate, no friends or
  nearby rules).
- **Cues and ready lucky blocks** (a block only once its timer is done, offered as
  "Block:<kind>"), **up to 8 items a side**, one entry per copy. **Never money.** No empty
  side.
- Block cues, Unique cues and the Starter Cue trade. Classic and every other Exclusive cue
  never (rank, season and VIP cues; designer, 2026-09-28).
- A Unique keeps its number, and a player can hold only one copy of each Unique.
- **Paid origin**: every block and cue copy carries a free or paid origin. Free copies move
  first; a paid copy keeps its paid origin and moves only where **both** players'
  `IsPaidItemTradingAllowed` is true.
- **A trade pays no finder's money.**

**How a trade runs**
- Invite anyone in the server (an unanswered invite goes away after 30 s), accept or decline,
  both make offers, both accept, then a **3-second wait that any change restarts** on both
  sides. Either can cancel; leaving closes the trade.
- A **warning** when the sides are far apart: one side is worth more than 4 times the other,
  where a cue is worth 1 / its copies in existence (fewer than 10 counts as 10,
  `Config.Trade.MinExists`) and a block 1 / a set number per kind (`Config.Trade.BlockExists`:
  Standard 100,000 down to Mythic 30; a Mystery block 70,000).
- **History**: the last **50 trades** per player (designer, 2026-10-03).

**The atomic swap and the ledger**
- The swap is planned on copies of both saves, with every item checked against the save at that
  moment.
- It is written to both players' **ledger** keys first (`TradeLedger_v1`), then both live saves
  change together (refused unless they move exactly the plan), then both are saved and the
  ledger entries removed. Both saves change, or neither.
- A save that missed a ledger trade (a crash mid-swap) replays it once, 30 s after it loads.
  No item is ever duplicated or lost.
- Not yet checked in Studio with two real players (try by hand: Test > Clients and Servers >
  2 players).

**Alt farming** is held back by the free-drop rules (3.6: the loser must have played 5 real
matches, at most 3 drops a day from one account) and the invite cap (10.4).

**Retiring cues ("Vaulted")**: the designer can retire block cues; they stop dropping and never
come back (7.4), which keeps old cues worth trading for.

---

## 13. Roblox rules checklist

- **Odds as percentages** before every purchase: every outcome with its %, totals exactly 100,
  an "Odds" button in words, live updates.
- **Paid random items** are: Mystery and Grand Opening blocks (money or Robux), restock
  blocks, the Starter Pack (its block), the block timer skip, VIP's halved timers and daily
  spin, and ability spins (`Random = true` in `Config.Products`). Where **`PolicyService:ArePaidRandomItemsRestricted`** is true (Roblox
  names Australia, Belgium, the Netherlands, the UK and Brazil for under-18s) they are hidden or
  refused ("Restricted"). Free rewards still work there, and so does the Limited shelf (a known
  cue at a fixed price). A player PolicyService never answers for is treated as restricted for
  the session. VIP's timer perk and daily spin also wait until PolicyService has answered "not
  restricted" (2026-10-03).
- **`IsPaidItemTradingAllowed`** false: paid-origin items can't be traded (section 12).
- **Discounts must be real**: no fake sales, no restarting countdowns, no "LAST CHANCE, ACT
  NOW" wording.
- Declare paid random items and paid item trading in the Maturity and Compliance
  Questionnaire.
- **R15 only** (designer, 2026-10-02): Roblox pays about 42% more per Robux on purchases by
  age-checked US adults ($0.0054 against $0.0038), but only in games without R6. The game
  allows both today; the integrator switches Game Settings > Avatar to R15.

---

## 14. Launch values, and what to change as the game grows

| Dial | Launch | Change when |
|---|---|---|
| PC XP | x0.75 to Diamond, x0.5 from Expert | the global queue is live and there are 200+ Master and up: Expert and up x0.1 |
| Reyes XP | 307,500 | if Reyes gets crowded (a few hundred a year), raise it for everyone not yet there |
| The Mystery block's tier weights and block odds | section 7 | if the day-30 shares drift more than about 20% off the targets (section 1) |
| Restock Legendary | 0.05% a slot, no worldwide cap set | if Legendaries pile up or never sell out (set `GlobalStock`) |
| Limited drops | one about every 2 weeks | faster once the art pipeline allows; add copy caps if values fall |
| Seasons | ranks never reset | season rewards for the highest tier reached, once seasons start |

**Watch these numbers** (Roblox analytics and our own events): the share of active players
owning an Epic, Legendary, Mythic and Secret (the targets), players' average saved money
(rising fast = too much income), how many sell back Epics (high = too many Epics), Mystery block
and restock sales, money-pack conversion, and D1 and D7 retention.

---

## 15. Bots' cues

A bot's equipped cue matches what real players at its rank own (plan, 2026-10-02, the Bots
lane's request; `Config.BotCues`, `BotCues.pick(tier, roll)`). Each column is the chance the cue
is that rarity or better; Common, Uncommon and Rare are spread by the Mystery block's odds, and
the cue is then one block cue of that rarity, each equally likely.

| Bot tier | Epic+ | Legendary+ | Mythic+ |
|---|---|---|---|
| Bronze | 5% | 0.8% | 0.1% |
| Silver | 10% | 1.5% | 0.2% |
| Gold | 20% | 3% | 0.4% |
| Platinum | 34% | 6% | 0.8% |
| Diamond | 50% | 10% | 1.3% |
| Expert | 70% | 16% | 2% |
| Veteran | 88% | 26% | 4% |
| Master | 97% | 40% | 6.5% |
| Grandmaster | 99% | 58% | 11% |
| Reyes | 99% | 70% | 15% |

**A bot never shows the Secret cue**: Mythic+ is always a Mythic (lane, 2026-10-03: a bot
carrying the one Secret would make the rarest cue look common).

---

## 16. Economy analytics

Every money source and sink is sent to Roblox with **`AnalyticsService:LogEconomyEvent`**
(plan, 2026-10-02; `src/server/EconomyLog.luau`). Every money change carries a reason
(`PlayerData.MoneyChanged`: player, amount, reason, balance). Each player's changes are added
up by reason and sent once every 60 s and when they leave, so a match's many pots make one
event. Sources: match money, rewards, codes, group, invites, rank-ups, finder's money, Index
rows, packs, sell-back. Sinks: Mystery and Grand Opening blocks, restock, ability spins,
Limited cues.

---

## 17. Open (the designer's call)

- When the Firework Cue starts (`StartsAt`), set right before the release is published.
- When to schedule the Beta Cue on its own, and the next Limited.

---

## 18. The menus and how items are kept

- **The menus** (designer, 2026-09-28): four buttons in one column on the left: **Shop**,
  **Inventory**, **Rewards** and **Trade**. The Shop is one scrolling page with no tabs
  (11.5, plan 2026-10-02; emptied to its frame and jump buttons for the GUI overhaul,
  2026-10-04). The Inventory has two tabs, **Cues** (first) and **Index**; lucky blocks are
  not in it: they live in the hotbar and its bag. Rewards holds the login loop, the 28-day
  track, playtime gifts, codes and the group, favorite and invite cards; everything is claimed
  there and nothing pops up by itself (designer, 2026-10-04: no reward popups, no reminder
  toast, no come-back screen, no first-leave gift). Trading is in the first release.
- **How items are saved** (save version 7, 2026-10-04; version 6 of 2026-10-03 was a full wipe
  that kept only the receipt ids): a count per cue id for block and Exclusive cues, with how
  many of them are paid origin; Unique cues keep their copy number (#412) and a paid flag;
  lucky blocks as a list (`LuckyBlocks.List`, each `{ Id, Kind, ReadyAt, Paid }`) plus the
  skip credit. Version 7 dropped the old cases, their timers and the Quick Cases flag with no
  conversion (designer), and renamed `Flags.FirstWinCase` to `FirstWinBlock`. The default
  Classic cue is always owned and never counted, sold or traded. Saves go through the
  session-locked, versioned save layer.
- **Opening blocks.** One at a time, in the world: hold the block from its hotbar slot, throw
  it, hold the prompt; the reel, the pull cutscene (Rare and up) and the "YOU GOT" card follow.
  No bulk opening (Quick Cases is retired).
- **Index completion.** A cue never owned is a "?" card; tapping it shows its name and its
  black 3D silhouette turning (designer, 2026-09-28). A cue counts once it has ever been owned
  (selling it later keeps it). Completing a rarity row pays once (`Config.Index.Rows`):

| Commons | Uncommons | Rares | Epics |
|---|---|---|---|
| $10,000 | $25,000 | $75,000 | $250,000 |

  Legendary, Mythic and Secret rows have no reward (money there would reward luck more than
  play), nor do the Exclusive and Unique groups. The one title left is the first Reyes'.
- **Finder's money**: the first time a cue enters a player's Index it pays once, by rarity
  (`Config.Index.FindMoney`). Selling a cue and finding it again pays nothing, and **a trade
  pays no finder's money**. It is earned money, not boosted by VIP or a party.

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Exclusive | Unique |
|---|---|---|---|---|---|---|---|---|
| $500 | $1,000 | $2,500 | $7,500 | $25,000 | $100,000 | $500,000 | $5,000 | $10,000 |

- **No rank-down screen.** XP is never lost.
- **Private servers** (when they come): no XP, no blocks, solo-rate money. The arena is a
  *reserved* server and never counts as private.
- **Small rules kept from 2026-09-28** (each is a line in DECISIONS.md): match XP rounds half
  to even and money rounds half up; a team's same-opponent count is the most-played
  opponent's; a Limited copy number taken for a purchase that then fails is burned, never
  reused; a Robux price is read once per server; a paid Money Party always adds its full 15
  minutes; the same-opponent table keeps 300 accounts a day, and past that a new account
  counts as the 11th match.

---

## 19. Differences from the plan

**Changed on purpose since the plan** (built this way):
- **Trading has no gate.** The plan said it opens after 25 real wins; the designer opened it to
  anyone in the server (designer, 2026-10-03).
- **The first win's Rare block keeps its 1 h timer** (designer, 2026-10-03); the plan only said
  "a guaranteed Rare Case".
- **Cases are lucky blocks** (designer, 2026-10-04): opened in the world, no 8-ball, the Mystery
  block rolls its tier when opened, 5 minutes after the win; no money timer skip; Quick Cases
  retired into VIP; no reward popups.
- **The Firework Cue comes from the Grand Opening block, not a $149,000 shelf**, for 21
  days from a start the designer sets (`StartsAt` 0 = off; designer, 2026-10-03 and
  2026-10-04).
- **A bot never shows the Secret cue**: the plan's Mythic+ column is always a Mythic (lane,
  2026-10-03).
- **VIP's daily spin is added to the day's login claim**, so it comes when the player claims
  (lane, 2026-10-03).

**Not built as the plan says** (open): nothing at the moment.

### Lucky-block follow-up (2026-10-03, updated 2026-10-04)

Lucky block timer skip: **19 Robux base price**, developer product **3716368528**; skips one
owned block of any tier. Existing randomized-item purchase restrictions apply. Receipt grant
and deduplication use PlayerData/Store's existing save barrier. If its selected timer is gone
or already ready, retain a saved skip credit for the next timer instead. Only Painicane may
bypass timers without a purchase; the visible countdown is unchanged. The test blocks' odds
became the tier rows of 7.2 (the same odds the cases had), with the tier timers of 7.2; the
test timers (60 s, 1 h, 6 h) are gone.
