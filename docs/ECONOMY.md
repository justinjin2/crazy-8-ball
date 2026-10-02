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

- **One bar: rank XP.** No Levels. XP is never lost and comes only from winning (reworked
  2026-10-02): **100 XP a win, 0 a loss**, no Rookie, first-win or VIP boosts. Rank is the
  main way to show status.
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
- **Ranks**, counted in wins: 1 win to Bronze I, then one more win each division (2, 3, 4...)
  to Platinum, then a steady ramp. For a 3-hour-a-day player winning half their games:
  Silver after about 6 hours of play, Expert in about a month, Veteran 2, Master 3.5,
  Grandmaster 6, Reyes (307,500 XP, 3,075 Classic wins) about 9 months.
- **Robux**: 49 R$ buys $900 (about 1.2 hours of play), up to 4,999 R$ for $130,000 (+42%).
  **VIP 599 R$**: 2x money, the VIP Cue; never odds, never XP.

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
| (2026-10-02) 1 win to Bronze I, 2 to Bronze II, 3 to Bronze III... | Divisions in wins of 100 XP: one more win each division to Platinum, then a ramp | Silver I at 21 wins, Gold I 66, Diamond I 232 |
| (2026-10-02) No Silver before about 2 hours | Silver I at 21 wins | about 6 hours of play at 50% |
| (2026-10-02) 3 h a day at 50%: Expert 1 month, Veteran 2, Master 3-4, Grandmaster 6, Reyes 7+ | The ramp from Diamond (section 4.2) | about 1.1, 1.9, 3.3, 5.6 and 8.6 months, Classic only |
| (2026-10-02) XP strictly from skill | Wins only; no Rookie, first-win or VIP boosts; harder modes, streaks and stronger opponents pay more | a Challenger win is 1.5 Classic wins |
| Losing is never a punishment (changed 2026-09-28) | A loss gives 0 XP, never negative | nobody ever drops a rank |
| Less for beating much lower players | Opponent-gap factor, section 4.4 | to Diamond: a tier lower x0.55, never under x0.3; from Expert: a tier lower x0.38, two tiers x0.11 |
| Only a few hundred ever reach Reyes | Fixed Reyes at 307,500 XP (3,075 Classic wins) | about 240 in the first year at 2,300 CCU (section 4.10) |
| VIP 2x money, not overpowered | 2x money only, never odds or XP (XP removed 2026-10-02) | a VIP climbs at the same speed |
| Onboarding feels fast | Small early divisions (Bronze II after 3 wins), early rewards (section 2) | Bronze I on the first win |

---

## 2. The first hour (onboarding)

The first session should feel like a rush of rewards. What a new player sees, in order, at an
ordinary 50% win rate after the tutorial:

| When | What happens |
|---|---|
| Join | Day 1 of the login streak: $250 |
| The first win (usually match 1 or 2) | Unranked to **Bronze I** (NEW RANK!, $100, 2 Standard Cases, the Bronze Cue, [BRONZE] tag); the first win's **Rare Case** reveal (in place of that win's Standard Case) |
| 10 minutes | Playtime gift: $100 |
| 30 minutes | Playtime gift: a Standard Case |
| The third win (about 45 minutes) | **Bronze II** ($50) |
| 60 minutes | Playtime gift: 2 Standard Cases |

By the end of the hour (50% win rate, about 7 matches): about 3-4 wins, Bronze I or II, about
8 cases opened (the Rare reveal, a free Standard Case per win, 2 from Bronze I, 3 from
playtime), the Bronze Cue and about $1,200. Silver comes after about 6 hours of play (21 wins).
Day 2 opens with 2 Standard Cases from the streak.

(The Rookie Boost, +100% XP for the first 25 matches, was removed on 2026-10-02: friends
reached Gold in a few hours.)

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
Levels are gone). Its number is **XP** (the save's `RankXp`). **XP is never lost**, so nobody
ever drops a rank, and losing a match is never a punishment, only a missed step.

**Reworked 2026-10-02** (designer, after friends reached Gold I in a few hours of play): XP
comes **only from winning**, and only skill makes it come faster. **A win is 100 XP, a loss
0.** The Rookie Boost, the first-win-of-the-day bonus, VIP's +50% XP and Classic's fade are
gone. Everyone's rank was reset to Unranked (save version 5); rewards already paid stay paid,
and the old peak is kept so no division pays twice.

### 4.2 The ladder

Counted in wins of 100 XP: **1 win to Bronze I** (a player is Unranked until their first win),
**2 more to Bronze II, then 3, 4, 5... one more win each division up to Platinum V**, then a
steady ramp sized so that a **3-hour-a-day player who wins half their games** reaches Expert
in about a month, Veteran 2, Master 3.5, Grandmaster 6 and Reyes about 9. No division is ever
smaller than the one before it (no wall like the old Diamond I). The first win's 100 XP lands
inside Bronze I, so Bronze I is 300 wide.

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

How it is built (for Config): a base of 100 for a win and 0 for a loss at every tier, times
the mode (Classic 1, Difficult 1.25, Challenger 1.5), the opponent gap (4.4), PC (4.5) and
the win streak (4.3). Unranked plays by Bronze's row.

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

- **XP boosts**: only the win streak (+25%, 4.3). The Rookie Boost (+100% for the first 25
  matches), the first win of each UTC day (+100%) and VIP (+50%) were removed on 2026-10-02:
  they were not skill.
- **PC**: XP x0.75 below Expert and x0.5 from Expert at launch, so a player in a quiet server
  still climbs against the bot of their rank. Once the global queue exists and the top is
  busy, Expert and up drops to x0.1 (section 14).
- **Forfeits**: as built. The forfeiter gets no XP at all; the winner is paid only after the
  one-minute mark.

### 4.6 Grandmaster and Reyes

Fixed XP amounts, like every other tier: Grandmaster I at 202,500 XP (2,025 Classic wins),
**Reyes at 307,500 XP** (3,075 Classic wins; 2,050 Challenger wins). For a 3-hour-a-day player
winning half their games that is about 9 months of play; at an hour a day, over 2 years. The
first player ever to reach Reyes is announced in every server and gets a one-of-one Unique
title; each later Reyes is announced too. How many ever get there: 4.10.

### 4.7 Difficulty unlocks

By rank: host a **Difficult** or **Challenger** table from **Gold I** (2026-10-02; Challenger
was Diamond I). Gold I is 66 wins, about 17 hours of Classic play. Below it the host card greys
them with "Requires Gold I+". Anyone
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

Hours of play against equal opponents (`python3 tools/economy_model.py tables`; a Classic match
plus the time between is about 8 minutes, so 7.5 matches an hour; the streak bonus included):

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

Simulation (`ranks`, rerun 2026-10-02): 2,000 new players a day for a year (about 2,300 peak
CCU by the end), most leaving on day one and a few staying for a year or more (playing up to 6
hours a day), each with a hidden skill; half their matches near their own rank. "Ever" counts
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
- **The ladder spreads out.** No tier holds a pile of players (the old ladder put a third of
  them in Diamond, behind its 8,000 XP wall); each tier up holds fewer, and the share above
  Expert grows slowly over the year.
- **Nobody reaches Grandmaster in the first 3 months, or Reyes in the first 6.** About 240
  players reach Reyes in the first year at about 2,300 CCU: the heavy grinders. If that is
  too many, the lever is the Grandmaster widths.
- **Rank still rewards time as well as skill**, since a loss costs nothing: mean skill rises
  tier by tier, but a steady average player does get to Expert and beyond.

The retention and playtime in the simulation are guesses, so read it for shape, not exact
counts.

### 4.11 Seasons

**Ranks never reset** (designer, 2026-09-28): your XP is yours forever. (The one exception was
before release: the 2026-10-02 rework reset every tester's rank, keeping their rewards.) Seasons can still
give a reward for the highest tier reached during that season (a season-coloured tier cue,
Exclusive, plus cases), without taking anything away.

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
| Case rarities | Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret | cases (and trades) only | yes | yes |
| **Unique** | numbered Limited cues (Founder's Cue 50, Beta Cue 1,000, and every Limited drop) | the Limited shelf, for a set time | yes | no |
| **Exclusive** | the VIP Cue, the Starter Cue, the ten rank cues (Bronze Cue ... Reyes Cue), later season cues | one special way each | **never**, except the Starter Cue (designer: VIP never, 2026-09-28; the Starter Cue trades, 2026-09-29) | no |

What rarity looks like (GDD section 12, UI_STYLE section 4 colours): Common and Uncommon keep
the plain wisp trail (Uncommon tinted); Rare adds a coloured trail and small pocket burst; Epic
has its own trail and pocket effect; Legendary an animated trail, pocket effect and sound;
Mythic the celestial shimmer and its own VFX; Secret a one-of-a-kind full set.

**Launch catalog: 46 case cues** (the cue skins plan, imported 2026-10-01): 7 Common,
9 Uncommon, 10 Rare, 9 Epic, 7 Legendary, 3 Mythic, 1 Secret. Classic is labelled Common too
but is the free default: everyone owns it, no case drops it, and it is never traded or sold.
Plus 12 Exclusive (10 rank, VIP, Starter) and 3 Unique (Founder's, Beta, Grand Opening).
The list and order are `Progression/Catalog.luau`; each cue's look is its skin
(`src/shared/CueSkins`, ARCHITECTURE "Cue skins").

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
in the case**. With the launch catalog, each Legendary in the Legendary Case is 20 / 7 =
2.857%, each Mythic 3.25 / 3 = 1.083%. The case screen has a button that says **"Odds"** (a word,
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
2 Standard Cases. The reminder on menu open and focus loss
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
- **No XP boost** (designer, 2026-10-02; it was +50%): rank comes from skill only.
- **The VIP Cue** (Exclusive, rainbow, never traded), a **[VIP]** chat tag before the rank
  tag ("[VIP] [GOLD] Name") and a rainbow name over the head, its colours drifting slowly
  (designer, 2026-09-28).
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

For the first 7 days after first join, once: **the Starter Cue** (Exclusive, its own look; tradable, designer 2026-09-29, the one
Exclusive that trades) **and $3,000**. No case inside, which keeps it outside the paid-random-item rules
(a bundle with a case in it would count as one).

### 11.5 At launch

| Product | Type | Robux | Why |
|---|---|---|---|
| Money packs (7) | developer products | 49 to 4,999 | the core |
| VIP | game pass | 599 | 2x money; research median VIP about 400 R$, 2x-money passes 300-600 |
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

Paid re-rolls or "reveal the next case" for cases (both paid random items), luck boosts or
pity skips for cases, extra or faster free cases, anything that protects rank, in-match aids
(longer guidelines, hints, power or spin upgrades), anything that hurts an opponent, and
purchase prompts right after a loss.

**The exception: ult spins** (players see "Ability Spins": ults are called Abilities
everywhere players look since 2026-09-28, while code and these docs keep "ult"; designer,
2026-09-28, the ultimates interview). Normal spins
are sold for Robux and money, and **Lucky Spins** (a luck boost: no Commons) for Robux. They
are paid random items, so: the odds are always shown on the spin screen (the true current
odds), pity is kept (the 100th spin without an Epic or better is Epic+), and players in
regions where PolicyService restricts paid random items can't pay for spins at all (the R$
and $ buy buttons and Lucky Spins are hidden, with the case shop's note); their free spins
still work. The ult bar itself is never bought: it fills by the same rules for everyone.

### 11.8 Ult spins (2026-09-28)

Players see these as **Ability Spins** on the **Abilities** screen (the designer,
2026-09-28); in code they stay ult spins (`Config.Ults`, the `Ults` save field).

Numbers in `Config.Ults` (Roll, Earn) and `Config.Products`; all *(tune)*.

**Odds** (each rarity's share split evenly between its ults; a rarity with no built ult passes
its share down to the next one below that has one, and the Odds panel shows the true odds;
all 13 are built and the screen is live since 2026-09-29, so each Common is 18.333%, each
Uncommon 15%, each Rare 6.117%, each Epic 1%, each Legendary 0.333% and each Mythic 0.05%):

| Rarity | Normal spin | Lucky Spin |
|---|---|---|
| Common | 55% | 0% |
| Uncommon | 30% | 63.1667% |
| Rare | 12.2333% | 25% |
| Epic | 2% | 8% |
| Legendary | 0.6667% (1 in 150) | 3.3333% (1 in 30) |
| Mythic | 0.1% (1 in 1,000) | 0.5% (1 in 200) |

**Pity:** every spin adds 1; the 100th without an Epic or better is Epic+ (Epic 72.3%,
Legendary 24.1%, Mythic 3.6%); any Epic+ resets it. About 6.2% of 100-spin stretches reach
it.

**Getting spins:** 3 starter spins (new and existing saves); 1 free spin a UTC day (not
stacked; the SPIN button reads FREE SPIN and uses it first; the Abilities button has a red dot and
the leave reminder mentions it); rank-ups (+1 per new tier up to Gold, +2 Platinum and
Diamond, +3 above); +2 on day 7 of the login streak; +1 on the day's last playtime gift;
codes (the spin screen's code box, starting with ABILITIES for 3 spins); Fast Open (99 R$) adds
Skip and Auto Spin.

**Prices:**

| Product | Robux | Was |
|---|---|---|
| 1 spin | 15 | |
| 5 spins | 50 | 75 |
| 10 spins | 100 | 150 |
| 50 spins | 449 | 750 |
| 1 Lucky Spin | 49 | |
| 3 Lucky Spins | 129 | 147 |
| Slot 2 (game pass) | 59 | |
| Slot 3 (game pass) | 99 | |

With money: **$1,750 a spin** (1, 5, 10 or 50; no bulk discount): about 2.4 hours of
Classic play a spin (an hour is worth about $735, 11.1's anchor), so money spins are a slow
trickle for savers and Robux the cheap route ("way more expensive", the designer).

**How strong each ult is** (the measured ladder, 2026-09-29, GDD section 9). Worth = extra own
balls per use, net of the opponent's balls gifted, a careful shooter, the mean of three skills
(`tests/ult_value.luau`, 120 tables, `tools/ult_value_results.json`); it is
`Config.Ults.Catalog[id].Worth`. The careless column is skill 2, aiming only for the pot (the
five area abilities of the skill rule; the others have no careless choice).

| Rarity | Target | Ult | Worth | Careless |
|---|---|---|---|---|
| Common | 0.33 | Magnet | 0.46 | 0.56 |
| | | Eagle's Eye | 0.34 | |
| | | Super Bounce | 0.33 | |
| Uncommon | 0.5 | Ghost | 0.47 | |
| | | Heat Seeker | 0.40 | |
| Rare | 1 | Rewind | 0.53 | |
| | | Time Stop | 0.47 | |
| Epic | 1.5 | Chain Lightning | 0.96 | 0.72 |
| | | Portals | 0.42 (a low bound) | |
| Legendary | 2.2 | Steel Ball | 1.09 | |
| | | Black Flash | 1.21 | 1.00 |
| Mythic | 2.6 | Black Hole | 1.32 | 1.08 |
| | | Guangdong Tiger | 1.30 | 1.07 |

Rarity means 0.37, 0.44, 0.50, 0.69, 1.15, 1.31: each a little above the one below. The top
targets can't be reached inside the reach cap (a fifth of the table, 20 in) and the ball caps,
so the rows are reported as measured. Two inversions: Magnet over Heat Seeker, and Portals
(which the model shooter never reuses across the turn) under the Rares.

**Win rates** (`tools/ult_model.py`, each rarity's best ult against Magnet at equal skill,
10,000 matches a row):

| Rarity (ult) | Classic 0.60 | Classic 0.70 | Difficult 0.45 |
|---|---|---|---|
| Common (Magnet) | 50.2% | 50.1% | 49.4% |
| Uncommon (Ghost) | 50.5% | 49.8% | 50.1% |
| Rare (Rewind) | 49.5% | 49.6% | 50.9% |
| Epic (Chain Lightning) | 50.2% | 50.5% | 51.3% |
| Legendary (Black Flash) | 55.8% | 54.6% | 56.2% |
| Mythic (Black Hole) | 56.2% | 55.9% | 56.4% |

So a Mythic wins about 56 matches in 100 against an equal player with Magnet, well under the
62-64% the old rough "2-3 sure balls" model allowed. The levers if playtests want more or
less: each ult's reach, caps and counts in `Config.Ults`, the opponent's factor, the Legendary
and Mythic odds, or top ults filling slower (none applied).

---

## 12. Trading

- Cues only; **money never trades** (GDD section 12). Up to 8 cues a side; any change restarts
  a 3-second confirm on both sides.
- **Open to everyone from the start** (designer, 2026-09-27: no level gate). No Exclusive cue
  can be traded (rank, season and VIP cues; designer, 2026-09-28) except the Starter Cue
  (designer, 2026-09-29); case and Unique cues can. Alt farming is held back by the free-case rules instead (section 3.6:
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
| Reyes XP | 307,500 | if Reyes gets crowded (a few hundred a year), raise it for everyone not yet there |
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
  each code once per player, case-insensitive, with an optional expiry. Codes give only money,
  free cases or free ult spins and Lucky Spins (ABILITIES: 3 spins, 11.7), never a cue, pass or
  boost sold for Robux. A free case or free spin is not a paid random item, so a restricted
  player may redeem it (2026-09-28).
- **Index completion** (closes the Open item in 17). A cue never owned is a "?" card; tapping
  it shows its name and its black 3D silhouette turning (designer, 2026-09-28). A cue counts
  once it has ever been owned (selling it later keeps it in the
  Index). Completing a rarity row pays once: Commons $1,000, Uncommons $2,500, Rares $7,500,
  Epics $25,000. Legendary, Mythic and Secret rows have no reward (money there would reward
  luck more than play), nor do the Exclusive and Unique groups. The rows' "Collector" titles
  were dropped (designer, 2026-09-28: no substance); old saves keep them, unlisted. The one
  title left is the first Reyes', listed in the Index; showing a title over the head is
  parked.
- **Finder's money** (designer, 2026-09-28): the first time a cue enters a player's Index it
  pays once, by rarity: Common $50, Uncommon $100, Rare $250, Epic $750, Legendary $2,500,
  Mythic $10,000, Secret $50,000, Exclusive $500, Unique $1,000 (`Config.Index.FindMoney`,
  *(tune)*: the designer asked for "some extra money" and named no amounts). Selling a cue and
  finding it again pays nothing (the Index keeps it), so there is no loop. It counts as
  earned money, not boosted by VIP or a party. About $950 over a new player's first Commons
  and Uncommons (a bit over an hour of play); all case cues together pay $83,700 over a
  whole collection, small next to what the rare ones cost to roll (a Mythic find is about 6%
  of its average roll cost). For the trading session to decide: a cue got by trade enters the
  Index too; paying for those would let alts pass cues round for money (suggestion: trades
  pay no finder's money).
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
  codes WELCOME ($500 and a Standard Case), 8BALL ($250), ROOFTOP (a Rare Case, through
  2026-12-31) and ABILITIES (3 ult spins, 2026-09-28, first named ULTS; shown on the spin
  screen's code banner).
- **From the overnight audit (2026-09-28, overnight assumptions):** a case sale is at most
  **50% off** (`Config.Cases.MaxSalePercent`; past about 61% off, buying 10, opening and
  selling back pays more than it costs). A Robux receipt that no longer qualifies when it
  arrives (the VIP offer when already VIP or after its window plus 10 minutes, a second
  Starter Pack, a Founder's Cue sold out, ended or already owned) pays money instead at the
  first pack's rate, Robux x 900 / 49 (VIP offer $5,491, Starter Pack $1,451, Founder's
  $27,532). A paid Money Party always adds its full 15 minutes; the one-hour queue only
  stops the purchase box. The same-opponent table (3.6) keeps 300 accounts a day; past that,
  a new account counts as the 11th match (floor pay, no free case).
