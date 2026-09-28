# Economy: money, ranks, cases, the Limited shelf and Robux

The one place that says how the game's economy works and every number in it. Written
2026-09-27 from the designer's anchors and interview, research on Roblox and other games, and a
model that simulates thousands of players (`tools/economy_model.py`). GDD sections 11 and 12
point here. Every number is a starting value *(tune)*: it goes into `src/shared/Config.luau`
and changes after playtests. Change a number here, in the model, and in Config together, then
re-run the model to see what it does.

```bash
python3 tools/economy_model.py tables   # case odds, money per hour, ranks per division, gap factors
python3 tools/economy_model.py shop     # money packs, Limited prices, Robux costs
python3 tools/economy_model.py loot     # days to a player's first Epic, Legendary, Mythic, Secret
python3 tools/economy_model.py hours    # the same in hours played, with the spread
python3 tools/economy_model.py supply   # cues entering the game per day at 500 / 2k / 10k CCU
python3 tools/economy_model.py ranks    # population simulation of the rank ladder
```

**Built for a small launch, ready to grow.** Nothing assumes the game blows up. The ranks, cases
and rewards work the same with 200 players online as with 20,000; the few things that should
change as the game grows are listed with their triggers in section 14.

---

## 0. At a glance

- **One bar: rank XP.** No Levels. XP is never lost: losses give a little to Platinum and
  nothing from Diamond, so nobody drops a rank. Rank is the main way to show status.
- **A match** (1v1 against a person, Classic) pays about **$134 to the winner and $60 to the
  loser**: $10 a ball, $15/$20 nice shots, $50 win / $15 loss. That is about **$730 an hour**.
  Difficult pays 1.5x and Challenger 2x.
- **The winner of every real match gets a free Standard Case** (every win for a new player's
  first 50 wins; after that the first 10 wins a day, then every 2nd win).
- **Four cases**: Standard $150, Rare $500, Epic $1,500, Legendary $5,000. Each guarantees one
  rarity below its name; a legendary is never guaranteed.
- **A 1-hour-a-day player** gets a first Epic after about **2 hours** of play, a first
  Legendary in about **7 days** (6-10 by what they buy), a first Mythic in about **6-8
  weeks**; a Secret is a lottery a 3-hour-a-day player wins in about 6-11 months (a
  lucky quarter within about 3).
- **No direct buying of case cues**: they come from cases and trading only. A **Limited
  shelf** sells exclusive, numbered cues for a short time, then they are trade-only forever.
  Deals are only ever on cases (bulk opening, occasional real case sales, timed special
  cases), never a guaranteed case cue.
- **Ranks**: Silver in the first half hour, Diamond in about 7.5 hours, Expert in about 2
  months at an hour a day, Reyes (2,352,500 XP) about a year for a 3-hour-a-day grinder.
- **Robux**: 49 R$ buys $900 (about 1.2 hours of play), up to 4,999 R$ for $130,000 (+42%).
  **VIP 599 R$**: 2x money, +50% XP, the VIP Cue; never odds.

---

## 1. The designer's targets, and how the plan meets them

| Target (designer) | Plan | Model says |
|---|---|---|
| First epic after a few hours | Free cases plus money cases | median 2.0 h played (p25 1.1 h, p75 3.2 h) |
| First legendary in 1-2 weeks (1 h a day) | Case odds, section 7 | median 6-10 days (7.1 h played buying Epic Cases); 5-6 with VIP; 3-4 at 3 h a day |
| First mythic in at least a month | Case odds | median 6-8 weeks at 1 h a day; 2.5-4 weeks at 3 h a day |
| Secret: months | Case odds of 1 in 400 Legendary Cases at best | a 3 h a day player: median 6-11 months, a quarter within about 3; a 1 h player: 1.3-2.4 years |
| Lots of duplicates of commons to rares | Free case every win, 90% of it Common/Uncommon | about 5 commons/uncommons and 1.7 rares per hour |
| Case cues keep their value | No direct buying; a Limited shelf of exclusives instead (section 9) | the designer replaced the rotating shop after the research |
| Unranked to Bronze I after the tutorial, then 1-2 matches a division | Bronze 250 XP a division, a win 250 | Bronze about 1.4 matches, Silver about 2 |
| Plateau from Gold, 5-6 matches a division | Gold 800 XP, loss still +50 | about 5 matches |
| Diamond much harder, Classic fades | Divisions from 8,000 XP growing 17% each, Classic win halved, losses give 0 | Diamond I to Expert takes about 50 hours |
| From Expert: only Difficult/Challenger climb, skill speeds you up | Classic x0.2, Challenger x1.5, win streak, opponent gap | a Challenger win is worth 7.5 Classic wins |
| Losing is never a punishment (changed 2026-09-28) | Losses +100/+75/+50/+25 to Platinum, 0 from Diamond, never negative | nobody ever drops a rank |
| Less for beating much lower players | Opponent-gap factor, section 4.4 | to Diamond: a tier lower x0.55, never under x0.3; from Expert: a tier lower x0.38, two tiers x0.11 |
| Only a few hundred ever reach Reyes | Fixed Reyes at 2,352,500 XP | section 4.10 |
| VIP 2x money, faster XP, not overpowered | +50% XP only, never odds | a VIP climbs about a third faster |
| Onboarding feels fast | Rookie Boost, fast Bronze/Silver, early rewards (section 2) | Silver in about 30 minutes |

---

## 2. The first hour (onboarding)

The first session should feel like a rush of rewards. What a new player sees, in order, at an
ordinary 50% win rate after the tutorial:

| When | What happens |
|---|---|
| Join | Day 1 of the login streak: $250 |
| Match 1 (the tutorial, always a win) | Unranked to **Bronze I** (NEW RANK!, $100, 2 Standard Cases, the Bronze Cue, [BRONZE] tag); the first win's **Rare Case** reveal (in place of that win's Standard Case); about $125 |
| 10 minutes | Playtime gift: $100 |
| Matches 2-4 | With the Rookie Boost a win is worth two Bronze divisions ($50 each) |
| 30 minutes | Playtime gift: a Standard Case |
| Around match 4 (about 30 minutes) | **Silver I** (the NEW TIER screen: $300, a Rare Case, the Silver Cue) |
| Matches 5-8 | Silver II, III, maybe IV ($75 each) |
| 60 minutes | Playtime gift: 2 Standard Cases |

By the end of the hour (model, 50% win rate): about **8 cases opened**, two rank tiers and
several divisions, two exclusive cues and about $2,000 of money. About 1 in 6 players already has an
Epic from free cases alone, and 1 in 3 if they spend that money on an Epic Case. Day 2 opens
with 2 Standard Cases from the streak and the first-win-of-the-day bonus.

**Rookie Boost:** a new player's first 25 matches earn +100% XP ("ROOKIE x2" on the rank bar).
With VIP it adds up to x2.5.

---

## 3. Money

Money is earned by playing and spent on cases and the Limited shelf. It never trades between players.

### 3.1 One match (1v1 against a person, Classic)

| What | Money | Notes |
|---|---|---|
| Each ball that counts for you | **$10** | as built: your group, legal open-table pots, the break's balls, the 8 when it wins |
| Nice shot on top | **bank or kick +$15, combo or carom +$20** | as built |
| Win | **+$50** | only after a real match (one minute, not a quick forfeit) |
| Loss | **+$15** | money even when you lose; the leaver gets nothing |
| Win streak | **+$25** on each win from the 3rd in a row | against people only; "streaks" in GDD section 12 |

Average match: winner about $134 (7.5 balls, half a nice shot, the win), loser about $60
(4 balls, the loss bonus). **About $97 a match and 7.5 matches an hour, so $730 an hour.**

### 3.2 By opponent

| | Person | PC (bot) | Solo | Tutorial (disguised PC) |
|---|---|---|---|---|
| Ball and nice-shot pay | full | full | 30% ($3 a ball) | full |
| Win / loss bonus | $50 / $15 | **$25 / $8** | none | $50 |
| Daily limit | none (anti-farm rules, 3.6) | after **$1,000** of PC money in a UTC day, PC pays half (never zero) | after **$300** of solo money in a UTC day, $1 a ball | once |
| Free case for the winner | every win (section 7.1) | **every win** (same limits) | never | yes, plus the first win's Rare Case |
| XP | full | x0.75 to Diamond, x0.5 from Expert | none | places you at Bronze I |

### 3.3 Team matches (2v2, 3v3)

Every ball your team pots pays **each teammate $10**, so an hour of 2v2 or 3v3 earns the same
as 1v1. The nice-shot bonus goes only to the shooter. The win and loss bonus, the free case
(each winner) and XP are per player, by the same rules; XP uses the opposing team's
average rank for the gap (section 4.4).

### 3.4 Difficulty

| | Classic | Difficult | Challenger |
|---|---|---|---|
| Money | x1 | **x1.5** | **x2** |
| XP | see section 4.2 | | |
| Match length (assumed) | 6.5 min | 7.5 min | 8.5 min |
| Money an hour | about $730 | about $970 | about $1,160 |

`Config.Economy.UseDifficultyMultiplier` turns on only with the difficulty lock (Roadmap 6.2),
as the audit asked.

### 3.5 Boosts and how they stack

Boosts **add**, then difficulty multiplies: money = base x difficulty x (1 + VIP 1.0 +
Money Party 1.0). So the most is x3 before difficulty, x6 in Challenger during a Money Party
with VIP. XP boosts are in section 4.5. No boost ever changes case odds or free-case counts.

### 3.6 Anti-farming (alts and friends)

- **Same opponent, same UTC day:** matches 1-5 pay in full; 6-10 pay half the XP and half the
  win/loss bonus and drop no free case; from 11, no XP, a quarter of the bonus, half the ball
  pay. At most **3 free cases a day from beating the same account**.
- **The loser must have played 5 real matches** for the winner's free case (a fresh alt
  can't feed cases).
- **Short matches:** pots are still paid live, but money from matches that end before the
  one-minute mark counts toward a **$200 a day** short-match limit (the audit's "break,
  surrender, repeat" hole).
- Forfeits, leavers and the one-minute mark stay as built (GDD section 13).
- Private servers, when they come: no XP, no free cases, solo-rate money.

---

## 4. Ranks (XP)

### 4.1 One bar, never lost

Rank is the one progression bar and the game's main way to show status (designer, 2026-09-28:
Levels are gone). Its number is **XP** (the save's `RankXp`). **XP is never lost**: from
Bronze to Platinum a loss still gives a little, and from Diamond up a loss gives nothing. So
nobody ever drops a rank, and losing a match is never a punishment, only a missed step.
Division sizes grow up the ladder, so the climb keeps getting longer.

### 4.2 The ladder

XP needed for each division, I to V:

| Tier | I | II | III | IV | V | Tier total |
|---|---|---|---|---|---|---|
| Bronze | 250 | 250 | 250 | 250 | 250 | 1,250 |
| Silver | 350 | 350 | 350 | 350 | 350 | 1,750 |
| Gold | 800 | 800 | 800 | 800 | 800 | 4,000 |
| Platinum | 1,200 | 1,200 | 1,200 | 1,200 | 1,200 | 6,000 |
| Diamond | 8,000 | 9,500 | 11,000 | 13,000 | 15,000 | 56,500 |
| Expert | 17,500 | 20,500 | 24,000 | 28,000 | 33,000 | 123,000 |
| Veteran | 38,000 | 45,000 | 53,000 | 62,000 | 72,000 | 270,000 |
| Master | 85,000 | 100,000 | 115,000 | 135,000 | 160,000 | 595,000 |
| Grandmaster | 185,000 | 215,000 | 255,000 | 295,000 | 345,000 | 1,295,000 |
| **Reyes** | at **2,352,500 XP** in total | | | | | |

Quick and flat to Platinum (onboarding), then about 17% bigger every division from Diamond I.

XP for a win and a loss against an equal opponent:

| Tier | Classic win / loss | Difficult win / loss | Challenger win / loss |
|---|---|---|---|
| Bronze | +250 / +100 | +312 / +125 | +375 / +150 |
| Silver | +250 / +75 | +312 / +94 | +375 / +112 |
| Gold | +250 / +50 | +312 / +62 | +375 / +75 |
| Platinum | +250 / +25 | +312 / +31 | +375 / +38 |
| Diamond | **+125** / 0 | +312 / 0 | +375 / 0 |
| Expert to Reyes | **+90** / 0 | +562 / 0 | +675 / 0 |

How it is built (for Config): a base win and loss per tier (250 and +100/+75/+50/+25 to
Platinum, 250 / 0 in Diamond, 450 / 0 from Expert), times the mode (Classic 1, Difficult 1.25,
Challenger 1.5), times Classic's fade on wins (x0.5 in Diamond, x0.2 from Expert).

### 4.3 How skill still counts

With no XP loss, time alone would eventually reach the top, so skill decides the speed:
- **Harder modes pay more.** From Expert a Challenger win is worth 7.5 Classic wins, so the
  players who can win without guidelines climb far faster.
- **Win streak**: from the 3rd win in a row, each win gives +25% XP.
- **Opponent strength** (4.4): beating stronger players pays up to 1.5x, much weaker ones far
  less.
- Only wins count from Diamond, so a player who wins twice as often climbs about twice as fast.

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
0.1) and 1.5. The small XP a Bronze-to-Platinum loss gives uses the same factor, capped at 1.
The win bonus money uses it too (never under half); ball money is untouched.

### 4.5 Boosts, PC and forfeits

- **XP boosts add together**: **Rookie Boost** +100% for a new player's first 25 matches,
  **VIP** +50%, and the **first win of each UTC day** counts double (+100%). A new VIP
  player's first win of the day is x3.5.
- **PC**: XP x0.75 from Bronze to Diamond and x0.5 from Expert at launch, so a player in a
  quiet server still climbs against the bot of their rank. Once the global queue exists and
  the top is busy, Expert and up drops to x0.1 (section 14).
- **Forfeits**: as built. The forfeiter gets no XP at all; the winner is paid only after the
  one-minute mark.

### 4.6 Grandmaster and Reyes

Fixed XP amounts (designer, 2026-09-28), like every other tier: Grandmaster I at 1,057,500
XP, **Reyes at 2,352,500 XP**. For a 55% player at 3 hours a day that is about a year of
play; for an hour-a-day player, several years. The first player ever to reach Reyes is
announced in every server and gets a one-of-one Unique title; each later Reyes is announced
too. How many ever get there: 4.10.

### 4.7 Difficulty unlocks

By rank: host a **Difficult** table from **Gold I**, **Challenger** from **Diamond I**. Anyone
may join a harder table as a guest, with a warning and Play anyway. The table's difficulty sets
its money and XP multipliers for everyone at it.

### 4.8 Rank rewards (paid once, the first time you reach it)

The money that Levels used to pay now comes from ranks.

| Tier | Each new division II-V | Reaching the tier (division I) |
|---|---|---|
| Bronze | $50 | $100, 2 Standard Cases, the Bronze Cue, [BRONZE] chat tag |
| Silver | $75 | $300, a Rare Case, the Silver Cue, tag |
| Gold | $150 | $600, 2 Rare Cases, the Gold Cue, tag |
| Platinum | $250 | $1,200, an Epic Case, the Platinum Cue, tag |
| Diamond | $1,500 | $3,000, 2 Epic Cases, the Diamond Cue, tag |
| Expert | $3,000 | $10,000, 2 Legendary Cases, the Expert Cue, tag |
| Veteran | $5,000 | $15,000, 3 Legendary Cases, the Veteran Cue, tag |
| Master | $8,000 | $25,000, 5 Legendary Cases, the Master Cue, tag |
| Grandmaster | $15,000 | $50,000, 10 Legendary Cases, the Grandmaster Cue, tag |
| Reyes | - | $150,000, 25 Legendary Cases, the Reyes Cue, rainbow tag |

Rank cues are **Exclusive** (section 6) and can't be traded or sold: a Reyes Cue proves Reyes.

### 4.9 How long each tier takes

Hours of play against equal opponents, with a typical mix of modes (Classic early, Difficult
from Gold, mostly Challenger from Diamond), not counting the Rookie Boost:

| Win rate | Silver | Gold | Platinum | Diamond | Expert | Veteran | Master | Grandmaster | Reyes |
|---|---|---|---|---|---|---|---|---|---|
| 45% | 1 h | 2 h | 6 h | 12 h | 69 h | 139 h | 295 h | 637 h | 1,381 h |
| 50% | 1 h | 2 h | 6 h | 11 h | 62 h | 124 h | 263 h | 567 h | 1,229 h |
| 55% | 1 h | 2 h | 5 h | 10 h | 56 h | 112 h | 236 h | 509 h | 1,104 h |
| 60% | 1 h | 2 h | 5 h | 9 h | 50 h | 102 h | 214 h | 461 h | 999 h |

With the Rookie Boost a new player reaches Silver in about **30 minutes** and Diamond in
about **7.5 hours**. At an hour a day Expert takes about **2 months**. A 3-hour-a-day grinder
at 55% reaches Reyes in about a **year**.

**A small game** (model, with the Rookie Boost). "Weaker" means every opponent is 5
divisions below and you win 75%; "mix" is half bots, half weaker:

| Who they play | Silver | Gold | Platinum | Diamond | Expert |
|---|---|---|---|---|---|
| Equal players | 0.5 h | 1.2 h | 2.8 h | 7.5 h | 59 h |
| Only bots | 0.7 h | 1.6 h | 4.2 h | 11 h | 79 h |
| Only weaker players | 0.5 h | 1.5 h | 3.4 h | 9.6 h | 67 h |
| Half bots, half weaker | 0.7 h | 1.5 h | 3.8 h | 10.5 h | 73 h |

### 4.10 What the ranks look like over a year (simulation)

Simulation (`ranks`): 2,000 new players a day for a year (about 2,200 peak CCU by the end),
most leaving on day one and a few staying for a year or more, each with a hidden skill; half
their matches near their own rank. "Ever" counts everyone who reached the tier or higher,
including players who later quit.

| Tier | Share of players still playing, day 90 / 180 / 365 | Ever reached by day 365 | Mean skill (day 365) |
|---|---|---|---|
| Bronze | 15% / 12% / 10% | 625,000 (everyone ranked) | -0.17 |
| Silver | 11% / 9% / 8% | 374,000 | -0.12 |
| Gold | 16% / 13% / 11% | 255,000 | -0.10 |
| Platinum | 14% / 11% / 9% | 153,000 | -0.14 |
| Diamond | 34% / 33% / 30% | 99,700 | -0.12 |
| Expert | 7.6% / 12% / 13% | 24,000 | +0.07 |
| Veteran | 2.1% / 7.1% / 12% | 10,500 | +0.28 |
| Master | 0.1% / 1.6% / 6.5% | 3,270 | +0.56 |
| Grandmaster | 0 / 0.05% / 1.4% | 459 | +1.18 |
| **Reyes** | 0 / 0 / 0.01% | **4** | +2.44 |

What this means:
- **Reyes stays very rare**: 4 players in the first year at about 2,200 CCU (roughly 10 at
  5,000 CCU, 20 at 10,000). It keeps growing slowly every year, since XP is never lost.
- **With no XP loss, rank rewards time more than skill** below the very top: Expert and
  Veteran players are average-to-good (mean skill +0.07 and +0.28), because anyone who keeps
  playing gets there. Grandmaster (+1.18, about the top 12%) and Reyes (+2.44, about the top
  1%) still take real skill as well as time.
- **The high tiers fill up with long-time players.** A year in, about a third of the players
  still playing are Expert or higher. Measured against everyone who ever played it stays
  small: Expert 4%, Master 0.5%, Grandmaster 0.07%.

The retention and playtime in the simulation are guesses, so read it for shape, not exact
counts.

### 4.11 Seasons

**Ranks never reset** (designer, 2026-09-28): your XP is yours forever. Seasons can still
give a reward for the highest tier reached during that season (a season-coloured tier cue,
Exclusive, plus cases), without taking anything away.

---

## 5. No Levels

The account Level and its EXP are gone (designer, 2026-09-28). What they did moved:
- **Money every level** now comes from rank divisions (4.8).
- The **Rookie Boost** and the **first win of the day** now boost rank XP (4.5).
- **VIP** gives +50% rank XP instead of 2x EXP (11.2).
- The anti-alt rule "the loser must be Level 3" became "the loser must have played 5 real
  matches" (3.6).

---

## 6. Rarities and the catalog

| Group | Rarities | Comes from | Trade | Sell back |
|---|---|---|---|---|
| Case rarities | Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret | cases (and trades) only | yes | yes |
| **Unique** | numbered Limited cues (Founder's Cue 50, Beta Cue 1,000, and every Limited drop) | the Limited shelf, for a set time | yes | no |
| **Exclusive** | the VIP Cue, the Starter Cue, the ten rank cues (Bronze Cue ... Reyes Cue), later season cues | one special way each | VIP and Starter yes; rank and season cues no | no |

What rarity looks like (GDD section 12, UI_STYLE section 4 colours): Common and Uncommon keep
the plain wisp trail (Uncommon tinted); Rare adds a coloured trail and small pocket burst; Epic
has its own trail and pocket effect; Legendary an animated trail, pocket effect and sound;
Mythic the celestial shimmer and its own VFX; Secret a one-of-a-kind full set.

**Launch catalog: 30 case cues**: 7 Common, 6 Uncommon, 6 Rare, 5 Epic, 3 Legendary,
2 Mythic, 1 Secret. Plus 12 Exclusive (10 rank, VIP, Starter) and 2 Unique.

---

## 7. Cases

### 7.1 The free case

The winner of every real match (person or PC, over the one-minute mark, not a quick forfeit)
gets a **Standard Case**, as follows:
- **New players**: every win, for their first **50 wins** (about the first week).
- **After that**: every win for the first **10 wins each UTC day**, then **every 2nd win**.
- PC wins drop one too, under the same limits (a bot of your rank is a real match, not a
  farm). Solo never drops cases.
- Anti-farm limits in section 3.6.
- The very first win's case is a **Rare Case** instead, opened on the post-match screen with
  Equip (GDD section 14).

Cases go to the inventory and open whenever the player wants. Everyone opens them one at a time
on the reel (tap to skip to the result, then "Open next"); **Fast Open** (11.5) adds Open 10 (a
grid of ten results) and skips the reel (2026-09-28, section 18).

### 7.2 The four cases

Each guarantees at least the rarity below its name. Odds in percent; each row adds to exactly
100.

| Case | Price | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|---|
| **Standard** | $150 | 64.3 | 26 | 8.4 | 1 | 0.25 | 0.047 | 0.003 |
| **Rare** | $500 | - | 62.5 | 31 | 5.5 | 0.85 | 0.14 | 0.01 |
| **Epic** | $1,500 | - | - | 73.4 | 22 | 4 | 0.56 | 0.04 |
| **Legendary** | $5,000 | - | - | - | 76.5 | 20 | 3.25 | 0.25 |

The same odds as "1 in":

| Case | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|
| Standard | 1 in 100 | 1 in 400 | 1 in 2,128 | 1 in 33,333 |
| Rare | 1 in 18 | 1 in 118 | 1 in 714 | 1 in 10,000 |
| Epic | 1 in 4.5 | 1 in 25 | 1 in 179 | 1 in 2,500 |
| Legendary | (76.5%) | 1 in 5 | 1 in 31 | 1 in 400 |

Money it takes on average to roll one of a rarity (the best case for it): Epic $6,536,
Legendary $25,000, Mythic $153,846, Secret $2,000,000. Bigger cases are slightly better value, which rewards
saving up. A case's sell-back value averages about a third of its price, so buying cases to
sell never pays.

### 7.3 Odds screen and per-cue odds

Every cue of a rarity in a case has an equal share: **cue % = rarity % / cues of that rarity
in the case**. With the launch catalog, each Legendary in the Legendary Case is 20 / 3 =
6.667%, each Mythic 3.25 / 2 = 1.625%. The case screen has a button that says **"Odds"** (a word,
not just an icon), lists every cue with its %, and totals exactly 100%. Retiring a cue
(section 12) updates the list the moment it happens.

### 7.4 Time to a player's first of each rarity (model)

Median **days** until a player owns their first of each rarity, at a 50% win rate:

| Player | Buys | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|
| Casual, 30 min a day | Epic Cases | 2.9 | 11 | 72 | over 3 years |
| | Legendary Cases | 4.0 | 10 | 57 | about 2 years |
| | nothing (saves) | 5.4 | 24 | 147 | over 3 years |
| Regular, 1 h a day | Epic Cases | 2.0 | 6.9 | 48 | about 2 years |
| | Legendary Cases | 2.7 | 6.0 | 36 | about 16 months |
| | Rare Cases | 2.1 | 10 | 58 | about 30 months |
| | nothing (saves) | 4.2 | 25 | 102 | over 3 years |
| Regular + VIP | Epic Cases | 1.6 | 5.6 | 36 | about 17 months |
| | Legendary Cases | 2.0 | 4.8 | 30 | about 12 months |
| Dedicated, 3 h a day | Epic Cases | 1.1 | 3.5 | 23 | about 11 months |
| | Legendary Cases | 1.2 | 3.0 | 18 | about 8 months |
| | nothing (saves) | 2.0 | 14 | 56 | about 32 months |

In hours played (1 h a day, buying Epic Cases): Epic median 2.0 h (p25 1.1, p75 3.2),
Legendary 7.1 h (p25 3.3, p75 17.6), Mythic 51 h (p25 24, p75 99), Secret 720 h (p25 313).

"Buys" is what the player spends money on; "nothing" means they buy no cases (saving for a
Limited cue), so only free cases count. The model never misses a streak day. Every Secret
(and Mythic) unboxed is announced in the server, which makes each one a moment.

---

## 8. Selling cues back

Any case-rarity cue can be sold for money, with a confirm step from Epic up and a "Duplicate"
tag on extras. Exclusive and Unique cues can't be sold.

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| $15 | $40 | $120 | $600 | $3,000 | $15,000 | $75,000 |

About a tenth of what rolling costs: a floor, never a profit. Selling
also removes cues from the game, which keeps the ones that stay worth more.

---

## 9. No direct buying of case cues; the Limited shelf; case deals

**Case cues are never sold directly** (designer, 2026-09-27, replacing the rotating "today's
deals" shop). A Common-to-Secret cue comes only from a case or a trade. That keeps every case a
chance at something money can't simply buy, and gives trading its purpose: if you want a
specific cue, you trade for it. The research behind this: items that stay buyable lose their
trade value (Adopt Me pets still sold for Robux trade at about 1), while items sold for a
short time and then retired become the most valuable in the game (MM2's limited Robux bundle
godlies trade at 275-1,750 against 8-23 for godlies from boxes still sold).

**The Limited shelf** (in the one economy menu) sells **Unique** cues: exclusive designs that
never appear in any case.
- **For a set time only**, with a real countdown that never restarts: a new Limited cue about
  every one to two weeks at launch (as fast as cue art allows), and event cues during events.
  When the time is up it is **never sold again** and becomes trade-only forever.
- **Numbered** (#1, #2, ...), **one per player**, and optionally **copy-capped** (sold out
  when the cap is reached, across all servers).
- **Priced in money** so it is a real saving goal, with the "need $X more" nudge below. A few
  may be Robux bundles (a Limited cue plus money), like MM2's; a known item for Robux is not a
  paid random item.

| Tier | Money | About, in Robux | Copy cap | Saving time (Classic 1 h a day / Challenger 3 h a day) |
|---|---|---|---|---|
| Limited | $25,000 | 1,000-1,400 R$ | none | about 5 weeks / about a week |
| Limited Deluxe | $75,000 | 2,900-4,100 R$ | 5,000 | about 3.5 months / about 3 weeks |
| Limited Grand | $250,000 | 9,600-13,600 R$ | 500 | about a year / about 2.5 months |

At launch the shelf holds the **Founder's Cue** (1,499 R$, 50 numbered copies) and the **Beta
Cue** ($40,000, 1,000 numbered copies, first 30 days); the designer can change both.

**When a player has part of the price**, the buy button says "Need $X more" and opens the
money packs with the smallest pack that covers the gap highlighted. Never pop this up right
after a lost match.

**Copies in existence** (designer, 2026-09-27): every cue, in the inventory, the Index, trades
and the Limited shelf, shows how many exist in the game ("1,284 exist"). A global counter per
cue goes up when one is unboxed or bought and down when one is sold back.

### 9.1 Case deals and special cases

Deals are on **cases**, never on a guaranteed case cue (designer, 2026-09-27). Every one is
still random, with its odds shown.

- **Bulk opening** (always there, so it is a price, not a "sale"): 10 of any case for the
  price of 9.
- **Case sales**: now and then a single case type is cheaper for a set time, for example
  "Epic Cases 20% off this weekend". Rules so they stay real: at most one sale running, never
  the same case on sale twice in a row, about two weekends a month at most, a true countdown,
  and the normal price shown struck through, and never more than 50% off (2026-09-28: deeper,
  buying 10, opening and selling back would make money). Roblox's rules call an always-on or
  constantly repeating "sale" fake (section 13).
- **Special cases**: themed cases for events and seasons (the GDD's limited seasonal box),
  with their own pool of cues found in no other case. On sale for the event, then retired,
  after which their cues are trade-only. A retired (vaulted) cue can come back only this way.
  Starting odds, to be set per event:

| Special case | Price | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| Event Case (at least Rare) | $2,000 | 72.5 | 22 | 4.6 | 0.8 | 0.1 |

  It pays slightly worse per dollar than the Legendary Case for a Legendary ($43,000 against
  $25,000), which is fine because its cues exist nowhere else and stop dropping when it
  retires.
- A **free** special case can also be a reward (an event's login days or challenges); free
  ones never count as loot boxes.

## 10. Daily and playtime rewards

**Login streak** (one claim per UTC day; missing a day starts again at day 1):

| Day 1 | Day 2 | Day 3 | Day 4 | Day 5 | Day 6 | Day 7 |
|---|---|---|---|---|---|---|
| $250 | 2 Standard Cases | $500 | Rare Case | $1,000 | 2 Rare Cases | **Epic Case** |

**Four full weeks in a row** add a **Legendary Case** on day 28.

**Playtime gifts** (minutes played in a UTC day): 10 min $100, 30 min a Standard Case, 60 min
2 Standard Cases. **First win of the day**: double XP. The reminder on menu open and focus loss
("Come back tomorrow for your Rare Case") uses the real next streak reward.

---

## 11. Robux

Robux prices are shown from Roblox's live price (`GetProductInfoAsync`), never typed into the
UI, because Roblox Plus, regional pricing and Roblox's own discounts change what each player
pays.

### 11.1 Money packs (developer products)

Anchor: **an hour of Classic play is worth about 40 R$** at the smallest pack.

| Pack | Robux | Money | Bonus |
|---|---|---|---|
| Handful | 49 | $900 | - |
| Stack | 99 | $1,950 | +7% |
| Bundle | 249 | $5,250 | +15% |
| Briefcase | 499 | $11,000 | +20% |
| Vault | 999 | $23,500 | +28% |
| Bank | 2,499 | $62,500 | +36% |
| Fortune | 4,999 | $130,000 | +42% |

**First purchase double**: the first money pack a player ever buys gives +100% money, once.
It is shown as "First purchase: double money" on the packs, and it is true for every player
exactly once.

In Robux: a Legendary Case is about 190-270 R$ (Rivals sells a case for 249 R$); Limited
cues are in section 9. A player halfway to a $25,000 Limited finishes it with about 600 R$.

### 11.2 VIP (game pass, 599 R$)

- **2x money** (+100%, adds with other boosts) on everything earned in play: balls, nice
  shots, match bonuses. Not on rewards, sell-back or packs.
- **+50% XP** (designer, 2026-09-28): a VIP climbs ranks about a third faster. Adds with the
  Rookie Boost and the first win of the day.
- **The VIP Cue** (Exclusive, rainbow, tradable), a **[VIP]** chat tag after the rank tag and
  a VIP nameplate shine.
- Never better case odds, never more free cases. (A VIP perk that gives cases would
  make VIP a paid random item.)
- Model: a 1-hour-a-day VIP gets a first Legendary 1-2 days sooner and a first Mythic about
  10 days sooner. VIP's extra money matches the pass's price in money packs after about 15-20
  hours of play.

### 11.3 VIP welcome offer (developer product, 299 R$)

**50% off VIP for 24 hours from a player's first join**, with a real countdown that never
restarts. If they don't buy it, **one "welcome back" window of 24 hours** opens 7 days
later, then never again. It is a developer product that grants VIP in the save (VIP = owns the
pass **or** bought the offer), so only that player sees it; a discounted pass would show in the
public Store tab. Friendly wording ("Welcome offer"), never "LAST CHANCE". Opt it out of
Managed Pricing and show both prices live so "50% off" stays true.

### 11.4 Starter Pack (developer product, 79 R$)

For the first 7 days after first join, once: **the Starter Cue** (Exclusive, tradable, its
own look) **and $3,000**. No case inside, which keeps it outside the paid-random-item rules
(a bundle with a case in it would count as one).

### 11.5 At launch

| Product | Type | Robux | Why |
|---|---|---|---|
| Money packs (7) | developer products | 49 to 4,999 | the core |
| VIP | game pass | 599 | 2x money and +50% XP; research median VIP about 400 R$, 2x-money passes 300-600 |
| VIP welcome offer | developer product | 299 | first join and one comeback |
| Starter Pack | developer product | 79 | pool competitors sell 39-79 R$ starter packs |
| **Money Party** | developer product | 199 | +100% money for **everyone in the server for 15 minutes**, the buyer's name announced; buying again adds 15 minutes (up to an hour queued). Social and cheap to build; money only, so not a paid random item |
| **Fast Open** | game pass | 99 | skip the case animation and open 10 at once; same odds |

### 11.6 After launch

| Product | Robux | Notes |
|---|---|---|
| **Cue Pass** (season pass) | 449 premium, 1,199 premium plus 15 tiers | free and premium tracks of fixed cues, money and titles (no cases on either track); tiers from matches played; comes with seasons |
| Pass tier skips | 59 each, 10 for 499 | pass tiers only, never rank |
| Gift versions of VIP and the Cue Pass | same as the product | opt gifts out of Managed Pricing; only gift from an equal or pricier region (`GetUsersPriceLevelsAsync`) |
| Win celebrations and emotes | 99-249 | the avatar is the star (pillar 3); mute option |
| Private servers | 99 a month | practice with friends: no XP, no free cases, solo-rate money |
| Trader Pass | 199 | extra trade slots and trade history, if trading takes off |
| Club (subscription) | $4.99 a month | a monthly Exclusive cue, a daily money stipend, a club tag; clearly different from VIP |

### 11.7 Never sell

Paid re-rolls or "reveal the next case" (both paid random items), luck boosts, pity
skips, extra or faster free cases, anything that protects rank, in-match aids (longer
guidelines, hints, power or spin upgrades), anything that hurts an opponent, and purchase
prompts right after a loss.

---

## 12. Trading

- Cues only; **money never trades** (GDD section 12). Up to 8 cues a side; any change restarts
  a 3-second confirm on both sides.
- **Open to everyone from the start** (designer, 2026-09-27: no level gate). Rank and season
  cues can't be traded. Alt farming is held back by the free-case rules instead (section 3.6:
  the loser must have played 5 real matches, at most 3 cases a day from the same account).
- Players whose `IsPaidItemTradingAllowed` is false can't trade at all (every cue could have
  come from Robux-bought money).
- **Retiring cues ("Vaulted")**: each season the designer retires a few case cues; they stop
  dropping and can only come back in a special event case the designer makes. This keeps old cues
  worth trading for. The odds screens update at once.

---

## 13. Roblox rules checklist

- **Paid random items**: money is sold for Robux, so every case bought with money is a paid
  random item. Odds before purchase, every outcome with its %, totals exactly 100, an "Odds"
  or "Details" button in words, live updates.
- **Free cases are exempt** only while nothing paid can speed them up or add more. That is
  why VIP and Money Party never give cases.
- **`ArePaidRandomItemsRestricted`** (Roblox names Australia, Belgium, the Netherlands, the
  UK and Brazil for under-18s): hide the money cases. Free cases, the Limited shelf (a known cue
  at a fixed price) and everything else stay.
- **`IsPaidItemTradingAllowed`** false: no trading.
- **Discounts must be real**: no always-on "sale", no short pressure windows, no countdown
  that restarts or lies, no "LAST CHANCE, ACT NOW" wording for young players.
- Declare paid random items and paid item trading in the Maturity and Compliance
  Questionnaire.
- The US 18+ DevEx rate ($0.0054 a Robux against $0.0038) needs an R15-only game; this game
  allows R6 (GDD section 2), so it earns the standard rate. That is the designer's call.

---

## 14. Launch values, and what to change as the game grows

The launch numbers suit a game with a few hundred players online. The economy works
unchanged at any size; these are the dials to revisit:

| Dial | Launch | Change when |
|---|---|---|
| PC XP | x0.75 to Diamond, x0.5 from Expert | the global queue is live and there are 200+ Master and up: Expert and up x0.1 |
| Diamond I size and growth | 8,000 XP, +17% a division | after 60 days, if under 1% of players who stayed a month have reached Expert: 6,000 |
| Reyes XP | 2,352,500 | if Reyes gets crowded (a few hundred a year), raise it for everyone not yet there |
| Limited drops | one every 1-2 weeks | faster once the art pipeline allows; add copy caps if values fall |
| New-player free cases | 50 wins | if D1 retention is weak: 75 |
| Seasons | ranks never reset | season rewards for the highest tier reached, once seasons start |

**Watch these numbers** (Roblox analytics and our own events): median hours to a first
Legendary (target 8-14), players' average saved money (rising fast = too much income), the share
of players who sell back Epics (high = too many Epics), money-pack conversion, and D1 and D7
retention for the onboarding.

---

## 15. Cues entering the game at scale

| Rarity | Per hour played | 500 peak CCU (per day) | 2k peak CCU | 10k peak CCU |
|---|---|---|---|---|
| Common | 3.43 | 20,600 | 82,200 | 411,000 |
| Uncommon | 1.70 | 10,200 | 40,800 | 204,000 |
| Rare | 1.73 | 10,400 | 41,400 | 207,000 |
| Epic | 0.48 | 2,900 | 11,500 | 57,300 |
| Legendary | 0.097 | 580 | 2,300 | 11,700 |
| Mythic | 0.015 | 91 | 370 | 1,800 |
| Secret | 0.0009 | 6 | 22 | 110 |

(Player-hours a day taken as peak CCU x 0.5 x 24.)

These are early-life rates (they include the one-time rank rewards), so real supply settles
lower. Each rarity's supply is shared across its cues: at launch 3 Legendaries and 2 Mythics.

---

## 16. What changes in the build

- **Config** (`src/shared/Config.luau`): `Config.Ranks` gets the new division widths, the
  per-tier base win and loss, the mode multipliers, Classic's fade, the gap scale, the PC
  share by tier, the win streak, the XP boosts and the new rewards (money plus cases
  plus cue). `Config.Economy` gets the PC and short-match limits, team pay, the win streak,
  the same-opponent table and the boost rules. New: `Config.Cases`,
  `Config.Limited`, `Config.DailyRewards`, `Config.Products`, `Config.Trading`.
- **Save** (a new version with a migration): rookie matches left, win streak, unopened
  cases by type, wins today and lifetime wins (for the free case), streak day and last claim,
  playtime today, same-opponent counters for today, VIP-from-offer, welcome-offer windows,
  starter pack bought, first purchase done, Limited cues bought.
- **Order** (fits Roadmap stages 2 and 4): the new XP numbers, no-loss rule, boosts and gap
  factor (Config and the rank module), then the catalog, inventory and cases (free win case
  first), sell-back, copies-in-existence counters, the Limited shelf, daily rewards, the
  Robux products, trading's gates, the top-rank announcements, and the PolicyService checks.

---

## 17. Open (the designer's call)

- ~~Whether completing a row in the Index pays~~: decided 2026-09-28, section 18.
- R6 and the 18+ DevEx rate (section 13).

## 18. The menus and how items are kept (2026-09-28)

Added with the designer for the economy build (`docs/prompts/ECONOMY_UI_PROMPT.md`).

- **The left column and its menus.** Four buttons in one column on the left, top to bottom:
  **Shop** (tabs Cases, Limited, Money, VIP), **Inventory** (Cues, Cases, Index), **Rewards**
  (Daily, Playtime, Codes) and **Trade** ("Soon": trading is a later session). One menu at a
  time.
- **How cues are saved.** A count per cue id for case cues and Exclusive cues (small saves, no
  inventory limit; a duplicate is a count above 1). Unique cues keep their copy number (#412).
  Unopened cases stack as a count per case type. No inventory or case limit. The default
  Classic cue is always owned and never counted, sold or traded.
- **Opening many cases.** Everyone opens one at a time on the reel (tap to skip to the result,
  then "Open next"); Fast Open adds Open 10 and skips the reel (7.1, 11.5).
- **Codes.** Promo codes in the Rewards menu; the list lives in Config (`Config.Daily.Codes`);
  each code once per player, case-insensitive, with an optional expiry. Codes give only money
  or free cases, never anything sold for Robux (a free case is not a paid random item).
- **Index completion** (closes the Open item in 17). Cues never owned are dark silhouettes with
  "?" and no name. A cue counts once it has ever been owned (selling it later keeps it in the
  Index). Completing a rarity row pays once: Commons $1,000, Uncommons $2,500, Rares $7,500,
  Epics $25,000, each with a title ("Common Collector" ...). Legendary, Mythic and Secret rows
  give a title only (overnight assumption: money there would reward luck more than play).
  Exclusive and Unique groups are listed with no row reward. Titles are saved and listed in
  the Index; showing a title over the head is parked.
- **No rank-down screen.** XP is never lost, so the "Rank down" card is gone.
- **The first win's Rare Case** is rolled by the server when the match settles and revealed on
  the result screen with Equip (GDD 14).
- **Existing test saves** keep the division they show when the save layout changes (1,000-XP
  divisions mapped to the same fraction of the new ones), and get the cases and cues of the
  tiers they already reached, once (their money was already paid).
- **Private servers** (when they come): no XP, no free cases, solo-rate money. The arena is a
  *reserved* server (`PrivateServerId` set but `PrivateServerOwnerId` 0) and never counts as
  private.
- **Decided overnight (2026-09-28, overnight assumptions; each is a line in DECISIONS.md and
  can be overruled):** match XP rounds half to even, as section 4.2's table was printed
  (312.5 -> 312), and money rounds half up; the login streak runs in cycles of four weeks (the
  Legendary Case on day 28, then week 1 again); a team's same-opponent count (3.6) is the
  most-played opponent's; a player PolicyService never answers for is treated as restricted
  for the session (cases already owned still open); a Limited copy number taken for a purchase
  that then fails is burned, never reused; a Robux price is read once per server; placeholder
  codes WELCOME ($500 and a Standard Case), 8BALL ($250) and ROOFTOP (a Rare Case, through
  2026-12-31).
- **From the overnight audit (2026-09-28, overnight assumptions):** a case sale is at most
  **50% off** (`Config.Cases.MaxSalePercent`; past about 61% off, buying 10, opening and
  selling back pays more than it costs). A Robux receipt that no longer qualifies when it
  arrives (the VIP offer when already VIP or after its window plus 10 minutes, a second
  Starter Pack, a Founder's Cue sold out, ended or already owned) pays money instead at the
  first pack's rate, Robux x 900 / 49 (VIP offer $5,491, Starter Pack $1,451, Founder's
  $27,532). A paid Money Party always adds its full 15 minutes; the one-hour queue only
  stops the purchase box. The same-opponent table (3.6) keeps 300 accounts a day; past that,
  a new account counts as the 11th match (floor pay, no free case).
