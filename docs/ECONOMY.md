# Economy: money, EXP, ranks, cases, the Limited shelf and Robux

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

- **Two bars.** **RP** (rank points) decide the rank and can go down at the top; **EXP** fills
  the account **Level**, only ever goes up and pays money every level.
- **A match** (1v1 against a person, Classic) pays about **$134 to the winner and $60 to the
  loser**: $10 a ball, $15/$20 nice shots, $50 win / $15 loss. That is about **$730 an hour**.
  Difficult pays 1.5x and Challenger 2x.
- **The winner of every real match gets a free Standard Case** (every win for a new player's
  first 50 wins; after that the first 10 wins a day, then every 2nd win).
- **Four cases**: Standard $150, Rare $500, Epic $1,500, Legendary $5,000. Each guarantees one
  rarity below its name; a legendary is never guaranteed.
- **A 1-hour-a-day player** gets a first Epic after about **2 hours** of play, a first
  Legendary in about **8 days** (6-10 by what they buy), a first Mythic in about **6-8
  weeks**; a Secret is a lottery a 3-hour-a-day player wins in about 6-11 months (a
  lucky quarter within about 3).
- **No direct buying of case cues**: they come from cases and trading only. A **Limited
  shelf** sells exclusive, numbered cues for a short time, then they are trade-only forever.
- **Ranks**: Silver in the first hour, Diamond in about 11 hours, then a real wall. Expert and
  up are a skill ladder (Elo-style); Grandmaster and Reyes are leaderboard seats.
- **Robux**: 49 R$ buys $900 (about 1.2 hours of play), up to 4,999 R$ for $130,000 (+42%).
  **VIP 599 R$**: 2x money, 2x EXP, the VIP Cue; never odds, never rank.

---

## 1. The designer's targets, and how the plan meets them

| Target (designer) | Plan | Model says |
|---|---|---|
| First epic after a few hours | Free cases plus money cases | median 2.1 h played (p25 1.2 h, p75 3.4 h) |
| First legendary in 1-2 weeks (1 h a day) | Case odds, section 7 | median 6-10 days (8.6 h played buying Epic Cases); 5-9 with VIP; 3-4 at 3 h a day |
| First mythic in at least a month | Case odds | median 6-8 weeks at 1 h a day; 2.5-4 weeks at 3 h a day |
| Secret: months | Case odds of 1 in 400 Legendary Cases at best | a 3 h a day player: median 6-11 months, a quarter within about 3; a 1 h player: 1.3-2.4 years |
| Lots of duplicates of commons to rares | Free case every win, 90% of it Common/Uncommon | about 5 commons/uncommons and 1.7 rares per hour |
| Case cues keep their value | No direct buying; a Limited shelf of exclusives instead (section 9) | the designer replaced the rotating shop after the research |
| Unranked to Bronze I after the tutorial, then 1-2 matches a division | Bronze 250 RP a division, a win 250 | Bronze 1.4 matches, Silver 2.2 |
| Plateau from Gold, 5-6 matches a division | Gold 800 RP, loss still +50 | 5.3 matches |
| Diamond much harder, Classic fades | Diamond 4,000 RP, Classic win halved, losses cost | 53-64 matches a division in the hard modes; Classic stalls at 50% |
| From Expert: only Difficult/Challenger climb, skill decides | Elo-style RP, Classic x0.2 | Expert averages the top 25% by skill, Veteran the top 7%, Master the top 1.5% |
| Losses: gain a little to Gold, 0 in Platinum, lose a little in Diamond, Elo from Expert | Loss table, section 4.2 | as asked |
| Less for beating much lower players | Opponent-gap factor, section 4.4 | 1 division lower x0.86, a tier lower x0.38, two tiers lower x0.11 |
| A few dozen Reyes, a few hundred Grandmasters | Leaderboard seats that grow with the player count | section 4.7 |
| VIP 2x money, 2x EXP, not overpowered | EXP never touches rank, VIP never touches odds | first legendary 1-2 days sooner, first mythic about 10 days sooner |
| Onboarding feels fast | Rookie Boost, fast Bronze/Silver, early rewards (section 2) | Level 6 and Silver I in the first hour |

---

## 2. The first hour (onboarding)

The first session should feel like a rush of rewards. What a new player sees, in order, at an
ordinary 50% win rate after the tutorial:

| When | What happens |
|---|---|
| Join | Day 1 of the login streak: $250 |
| Match 1 (the tutorial, always a win) | Unranked to **Bronze I** (NEW RANK!, $100, 2 Standard Cases, the Bronze Cue, [BRONZE] tag); the first win's **Rare Case** reveal (in place of that win's Standard Case); **Level 1 to 3**; about $125 |
| 10 minutes | Playtime gift: $100 |
| Matches 2-4 | A win is a new Bronze division every time ($50 each); **Level 4, then 5** |
| 30 minutes | Playtime gift: a Standard Case |
| Around match 8 | **Silver I** (the NEW TIER screen: $300, a Rare Case, the Silver Cue); **Level 6** |
| 60 minutes | Playtime gift: 2 Standard Cases |

By the end of the hour (model, 50% win rate): about **8 cases opened**, two rank tiers, five
levels, two exclusive cues and about $2,000 of money. About 1 in 6 players already has an
Epic from free cases alone, and 1 in 3 if they spend that money on an Epic Case. Day 2 opens
with 2 Standard Cases from the streak and the first-win-of-the-day bonus.

**Rookie Boost:** a new player's first 25 matches earn +100% EXP ("ROOKIE x2" on the EXP bar).
With VIP it adds up to x3.

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
| Free case for the winner | every win (section 7.1) | **every 2nd PC win** | never | yes, plus the first win's Rare Case |
| RP | full | x0.5 | none | places you at Bronze I |
| EXP | full | x0.5 | 20 a game (first 5 games a day) | full |

### 3.3 Team matches (2v2, 3v3)

Every ball your team pots pays **each teammate $10**, so an hour of 2v2 or 3v3 earns the same
as 1v1. The nice-shot bonus goes only to the shooter. The win and loss bonus, the free case
(each winner), RP and EXP are per player, by the same rules; RP uses the opposing team's
average rank for the gap (section 4.4).

### 3.4 Difficulty

| | Classic | Difficult | Challenger |
|---|---|---|---|
| Money | x1 | **x1.5** | **x2** |
| EXP | x1 | x1.25 | x1.5 |
| RP | see section 4.3 | | |
| Match length (assumed) | 6.5 min | 7.5 min | 8.5 min |
| Money an hour | about $730 | about $970 | about $1,160 |

`Config.Economy.UseDifficultyMultiplier` turns on only with the difficulty lock (Roadmap 6.2),
as the audit asked.

### 3.5 Boosts and how they stack

Boosts **add**, then difficulty multiplies: money = base x difficulty x (1 + VIP 1.0 +
Money Party 1.0). EXP = base x difficulty x (1 + VIP 1.0 + Rookie 1.0). So the most is x3
before difficulty, x6 in Challenger during a Money Party with VIP. Boosts never change RP, case
odds or free-case counts.

### 3.6 Anti-farming (alts and friends)

- **Same opponent, same UTC day:** matches 1-5 pay in full; 6-10 pay half the RP and half the
  win/loss bonus and drop no free case; from 11, no RP, a quarter of the bonus, half the ball
  pay. At most **3 free cases a day from beating the same account**.
- **The loser must be Level 3 or higher** for the winner's free case (a fresh alt can't feed
  cases).
- **Short matches:** pots are still paid live, but money from matches that end before the
  one-minute mark counts toward a **$200 a day** short-match limit (the audit's "break,
  surrender, repeat" hole).
- Forfeits, leavers and the one-minute mark stay as built (GDD section 13).
- Private servers, when they come: no RP, no free cases, solo-rate money.

---

## 4. Ranks (RP)

### 4.1 Two bars

The saved `RankXp` number stays; the screens call it **RP**. It can go down from Diamond.
**EXP** is new (section 5) and only goes up. VIP boosts EXP and money, never RP.

### 4.2 The ladder

Divisions I to V per tier. RP for a win and a loss against an **equal** opponent (the gap
factor in 4.4 changes these), all rounded to whole numbers:

| Tier | RP a division | Classic win / loss | Difficult win / loss | Challenger win / loss |
|---|---|---|---|---|
| Bronze | 250 | +250 / **+100** | +312 / +125 | +375 / +150 |
| Silver | 350 | +250 / **+75** | +312 / +94 | +375 / +112 |
| Gold | 800 | +250 / **+50** | +312 / +62 | +375 / +75 |
| Platinum | 1,000 | +250 / **0** | +312 / 0 | +375 / 0 |
| Diamond | 4,000 | **+100** / -100 | +250 / -125 | +300 / -150 |
| Expert | 1,500 | **+30 / -23** | +188 / -144 | +225 / -172 |
| Veteran | 2,000 | +30 / -23 | +188 / -144 | +225 / -172 |
| Master | 2,000 | +30 / -23 | +188 / -144 | +225 / -172 |
| Grandmaster, Reyes | leaderboard | +30 / -23 | +188 / -144 | +225 / -172 |

How that is built (for Config): each tier has a base win and loss (Bronze to Platinum 250 and
+100/+75/+50/0, Diamond 200 / -100, Expert and up 150 / -115), times the mode (Classic 1,
Difficult 1.25, Challenger 1.5), times Classic's fade (Diamond: Classic wins x0.5; Expert and
up: Classic wins and losses x0.2).

**Matches a division against equal opponents** (50% and 60% win rate):

| Tier | Classic | Difficult | Challenger |
|---|---|---|---|
| Bronze | 1.4 / 1.3 | 1.1 / 1.1 | 1.0 / 0.9 |
| Silver | 2.2 / 1.9 | 1.7 / 1.6 | 1.4 / 1.3 |
| Gold | 5.3 / 4.7 | 4.3 / 3.8 | 3.6 / 3.1 |
| Platinum | 8.0 / 6.7 | 6.4 / 5.3 | 5.3 / 4.4 |
| Diamond | never / 200 | 64 / 40 | 53 / 33 |
| Expert | 429 / 171 | 69 / 27 | 57 / 23 |
| Veteran, Master | 571 / 227 | 91 / 36 | 76 / 30 |

Expert and up are Elo-style: an average player there barely moves (about +26 RP a match in
Challenger), a better one climbs, and every loss costs. The small upward drift rewards
dedication; seasons (4.12) trim it later.

### 4.3 Why the harder modes pay more RP

Challenger has no guidelines, so skill decides more of the result, and its matches run longer.
The multipliers (Difficult x1.25, Challenger x1.5) roughly make up for the longer matches
from Platinum and make the hard modes the fastest road from Diamond. Classic fades exactly
where the designer asked: at Diamond a Classic win is +100 against a -100 loss, so a 50% player
stops climbing there, and from Expert Classic barely moves RP either way (so friends can still
play Classic without risking their rank).

### 4.4 Beating much lower players pays less (smurf protection)

The gap is your division minus the opponent's (Bronze I = 1 ... Master V = 40; a team uses the
opposing team's average). The factor comes from the Elo expectation with a scale of 8
divisions:

| Gap (divisions) | +15 | +10 | +8 | +5 | +3 | +2 | +1 | 0 | -1 | -2 | -3 | -5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Win x | 0.10 | 0.11 | 0.18 | 0.38 | 0.59 | 0.72 | 0.86 | 1 | 1.14 | 1.28 | 1.41 | 1.50 |
| RP-losing loss x | 1.50 | 1.50 | 1.50 | 1.50 | 1.41 | 1.28 | 1.14 | 1 | 0.86 | 0.72 | 0.59 | 0.50 |

Formula: E = 1 / (1 + 10^(-gap / 8)); win factor = 2(1 - E), clamped 0.1 to 1.5; a loss that
costs RP uses 2E, clamped 0.5 to 1.5; a loss that still gains RP (Bronze to Gold) uses the win
factor, capped at 1. A Gold V who beats a Bronze II gets 10% of the win. The win bonus money
uses the same factor (never under half); ball money is untouched.

### 4.5 PC, forfeits

- **PC**: every RP change x0.5. At launch that holds at every tier, so a lone high player in a
  quiet server can still climb against the bot of their rank; once the global queue exists and
  the top is busy, drop it to x0.1 from Expert (section 14).
- **Forfeits**: as built. The forfeiter gets the loss (never the Bronze-Gold consolation RP),
  the winner is paid only after the one-minute mark.

### 4.6 Losing and demotion

- **Bronze to Expert: you never fall out of a tier.** Losses can drop you to division I, never
  below. Expert is safe forever once reached.
- **Veteran and up can fall a tier**, with a **3-loss shield**: at division I with an empty
  bar, the next 3 losses that would drop you are absorbed ("Shield 2 left"); the 4th drops you
  to division V of the tier below with a 75% bar. The shield refills when you reach division
  III of the tier again. The lowest anyone falls is Expert I.
- A match that never started (the coin flip) costs nobody RP.

### 4.7 Grandmaster and Reyes (leaderboard seats)

- **Eligible**: reach **Master V** (57,500 RP).
- **Seats**: Reyes = the top 10% of eligible players by RP, at most **50**, and each needs at
  least **61,500 RP** (Master V plus 4,000); Grandmaster = the next eligible players, at most
  **500**. Everyone else eligible shows Master V with their leaderboard place ("#612").
  Grandmaster I to V are fifths of the Grandmaster seats by place.
- The seats scale with the game by themselves: 30 eligible players make 3 Reyes and 27
  Grandmasters; 5,000 eligible make 50 and 500.
- **Keep your seat**: at least 10 rated Difficult or Challenger matches in the last 7 days,
  or you step back to Master V until you play again.
- A global leaderboard (OrderedDataStore) holds eligible players' RP, refreshed every 10
  minutes; each server reads the top 600 to set seats.
- **If nobody is there yet** (likely for the first months of a small launch), the roadmap and
  leaderboard say "No Reyes yet. Be the first." The first player ever to reach Reyes is
  announced in every server and gets a one-of-one Unique title.

### 4.8 Difficulty unlocks

By **peak** rank: host a **Difficult** table from **Gold I**, **Challenger** from
**Diamond I**. Anyone may join a harder table as a guest, with a warning and Play anyway. The
table's difficulty sets its money, EXP and RP multipliers for everyone at it.

### 4.9 Rank rewards (paid once, the first time your peak reaches it)

| Tier | Each new division II-V | Reaching the tier (division I) |
|---|---|---|
| Bronze | $50 | $100, 2 Standard Cases, the Bronze Cue, [BRONZE] chat tag |
| Silver | $75 | $300, a Rare Case, the Silver Cue, tag |
| Gold | $150 | $600, 2 Rare Cases, the Gold Cue, tag |
| Platinum | $250 | $1,200, an Epic Case, the Platinum Cue, tag |
| Diamond | $600 | $3,000, a Legendary Case, the Diamond Cue, tag |
| Expert | $1,500 | $10,000, 2 Legendary Cases, the Expert Cue, tag |
| Veteran | $2,500 | $15,000, 3 Legendary Cases, the Veteran Cue, tag |
| Master | $4,000 | $25,000, 5 Legendary Cases, the Master Cue, tag |
| Grandmaster | $6,000 | $50,000, 10 Legendary Cases, the Grandmaster Cue, tag |
| Reyes | - | $150,000, 25 Legendary Cases, the Reyes Cue, rainbow tag |

Rank cues are **Exclusive** (section 6) and can't be traded or sold: a Reyes Cue proves Reyes.

### 4.10 How long each tier takes

Hours of play to reach each tier against equal opponents, with a typical mix of modes
(Classic early, Difficult from Gold, mostly Challenger from Diamond):

| Win rate | Silver | Gold | Platinum | Diamond | Expert | Veteran | Master | Master V (eligible) |
|---|---|---|---|---|---|---|---|---|
| 50% | 1 h | 2.5 h | 6 h | 11 h | 61 h | 113 h | 183 h | about 240 h |
| 55% | 1 h | 2.4 h | 5.6 h | 10 h | 48 h | 78 h | 118 h | about 150 h |
| 60% | 1 h | 2.3 h | 5.3 h | 9.5 h | 40 h | 61 h | 89 h | about 110 h |

At an hour a day: Diamond in under two weeks, Expert in 1.5 to 2 months. At 3 hours a day a
strong player reaches the Grandmaster race in about 5 to 6 weeks. In practice players' win
rates fall as they climb, which is what stops the average player at Diamond.

### 4.11 What the ranks look like after a few months (simulation)

Simulation (`ranks`): 4,000 new players a day, most leaving on day one and a few staying
for months, each with a hidden skill; half their matches are with whoever is at the next table
and half near their own rank (80% from Diamond up, the pro lobby). Shares of ranked players,
and players per 1,000 peak CCU:

| Tier | Day 30 | Day 90 | Day 120 | Per 1k peak CCU (day 120) | Mean skill (day 120) |
|---|---|---|---|---|---|
| Bronze | 22.2% | 14.8% | 13.0% | 1,690 | -0.14 |
| Silver | 17.7% | 11.8% | 10.9% | 1,420 | -0.12 |
| Gold | 22.5% | 16.1% | 14.7% | 1,910 | -0.12 |
| Platinum | 16.3% | 13.0% | 12.0% | 1,560 | -0.18 |
| Diamond | 20.4% | 35.7% | 37.0% | 4,810 | -0.11 |
| Expert | 0.9% | 7.0% | 9.4% | 1,220 | +0.70 |
| Veteran | 0.07% | 1.5% | 2.5% | 320 | +1.50 |
| Master | 0 | 0.16% | 0.46% | 59 | +2.19 |
| Master V (Grandmaster race) | 0 | 0.02% | 0.06% | 8 | +2.77 |

So at 5,000 peak CCU after four months, about 40 players would be racing for the seats (a
few Reyes and the rest Grandmaster), about 300 Masters and 1,600 Veterans; at 500 CCU, about
30 Masters and a few players in the race. The simulation leaves out the 3-loss shield and
bots, and its retention and playtime are guesses, so read it for shape, not exact counts.

Diamond is the long plateau where most regular players settle; Expert and up are sorted by
skill (the mean skill column is in standard deviations; +1.5 is about the top 7%).

### 4.12 Seasons (later)

Season 0 has no reset. Later, about every 3 months: Bronze to Expert never reset; Veteran and
up keep half their RP above Expert I (never below Expert I). A season reward by season peak
(a season-coloured tier cue, Exclusive, plus cases) makes the reset feel like a prize.

---

## 5. Account Level (EXP)

| EXP source | EXP |
|---|---|
| Win / loss (against a person) | 100 / 50 |
| First win of the UTC day | +200 |
| PC match | half |
| Solo game | 20 (first 5 a day) |
| Difficulty | x1 / x1.25 / x1.5 |
| Boosts (add) | Rookie +100% (first 25 matches), VIP +100% |

**EXP to the next level** = 100 + 75 x (level - 1), at most 5,000 (from level 66).

| Level | 2 | 5 | 10 | 25 | 50 | 75 | 100 |
|---|---|---|---|---|---|---|---|
| Total EXP | 100 | 850 | 3,600 | 23,100 | 93,100 | 207,475 | 332,475 |
| At 1 h a day, about | the first match | the first hour | day 2-3 | week 4 | month 4 | month 9 | month 14 |

**Rewards**: every level pays **$50 + $10 x level** (at most $1,000); every 10th level also
pays **$25 x level** and a title. Levels 25, 50, 75 and 100 give a nameplate frame. Levels
never give cases (section 13: a case a purchase can speed up counts as a paid random item).
**There is no max level**: 100 is only the last milestone in the table, and every level after
66 costs a flat 5,000 EXP.

The Level shows as a small "Lv 12" chip with a thin EXP bar next to the rank HUD (exact look:
UI_STYLE, when it is built).

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
- PC wins drop one on every 2nd PC win. Solo never drops cases.
- Anti-farm limits in section 3.6.
- The very first win's case is a **Rare Case** instead, opened on the post-match screen with
  Equip (GDD section 14).

Cases go to the inventory and open whenever the player wants (after a match, or ten at once).

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
| Casual, 30 min a day | Epic Cases | 2.9 | 14 | 72 | over 3 years |
| | Legendary Cases | 4.3 | 10 | 59 | about 2 years |
| | nothing (saves) | 5.9 | 24 | 140 | over 3 years |
| Regular, 1 h a day | Epic Cases | 2.1 | 9.1 | 52 | about 21 months |
| | Legendary Cases | 2.8 | 7.6 | 37 | about 16 months |
| | Rare Cases | 2.4 | 10 | 63 | about 29 months |
| | nothing (saves) | 5.8 | 16 | 105 | over 3 years |
| Regular + VIP | Epic Cases | 1.9 | 6.6 | 40 | about 14 months |
| | Legendary Cases | 2.0 | 5.7 | 31 | about 10 months |
| Dedicated, 3 h a day | Epic Cases | 1.2 | 3.9 | 23 | about 11 months |
| | Legendary Cases | 1.2 | 3.4 | 17 | about 6 months |
| | nothing (saves) | 2.7 | 11 | 55 | about 32 months |

In hours played (1 h a day, buying Epic Cases): Epic median 2.1 h (p25 1.2, p75 3.4),
Legendary 8.5 h (p25 4.2, p75 13.1), Mythic 53 h (p25 25, p75 97), Secret 670 h (p25 268).

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

## 9. No direct buying of case cues; the Limited shelf

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

## 10. Daily and playtime rewards

**Login streak** (one claim per UTC day; missing a day starts again at day 1):

| Day 1 | Day 2 | Day 3 | Day 4 | Day 5 | Day 6 | Day 7 |
|---|---|---|---|---|---|---|
| $250 | 2 Standard Cases | $500 | Rare Case | $1,000 | 2 Rare Cases | **Epic Case** |

**Four full weeks in a row** add a **Legendary Case** on day 28.

**Playtime gifts** (minutes played in a UTC day): 10 min $100, 30 min a Standard Case, 60 min
2 Standard Cases. **First win of the day**: +200 EXP. The reminder on menu open and focus loss
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
- **2x EXP** (+100%): faster Levels, never RP.
- **The VIP Cue** (Exclusive, rainbow, tradable), a **[VIP]** chat tag after the rank tag and
  a VIP nameplate shine.
- Never better case odds, never more free cases, never RP. (A VIP perk that gives cases would
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
| VIP | game pass | 599 | 2x money and EXP; research median VIP about 400 R$, 2x-money passes 300-600 |
| VIP welcome offer | developer product | 299 | first join and one comeback |
| Starter Pack | developer product | 79 | pool competitors sell 39-79 R$ starter packs |
| **Money Party** | developer product | 199 | +100% money for **everyone in the server for 15 minutes**, the buyer's name announced; buying again adds 15 minutes (up to an hour queued). Social and cheap to build; money only, so not a paid random item |
| **Fast Open** | game pass | 99 | skip the case animation and open 10 at once; same odds |

### 11.6 After launch

| Product | Robux | Notes |
|---|---|---|
| **Cue Pass** (season pass) | 449 premium, 1,199 premium plus 15 tiers | free and premium tracks of fixed cues, money and titles (no cases on either track); tiers from EXP; comes with seasons |
| Pass tier skips | 59 each, 10 for 499 | pass tiers only, never rank |
| Gift versions of VIP and the Cue Pass | same as the product | opt gifts out of Managed Pricing; only gift from an equal or pricier region (`GetUsersPriceLevelsAsync`) |
| Win celebrations and emotes | 99-249 | the avatar is the star (pillar 3); mute option |
| Private servers | 99 a month | practice with friends: no RP, no free cases, solo-rate money |
| Trader Pass | 199 | extra trade slots and trade history, if trading takes off |
| Club (subscription) | $4.99 a month | a monthly Exclusive cue, a daily money stipend, a club tag; clearly different from VIP |

### 11.7 Never sell

Paid re-rolls or "reveal the next case" (both paid random items), luck boosts, pity
skips, extra or faster free cases, anything that protects or boosts RP, in-match aids (longer
guidelines, hints, power or spin upgrades), anything that hurts an opponent, and purchase
prompts right after a loss.

---

## 12. Trading

- Cues only; **money never trades** (GDD section 12). Up to 8 cues a side; any change restarts
  a 3-second confirm on both sides.
- **Open to everyone from the start** (designer, 2026-09-27: no level gate). Rank and season
  cues can't be traded. Alt farming is held back by the free-case rules instead (section 3.6:
  the loser must be Level 3, at most 3 cases a day from the same account).
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
  why VIP, Money Party and Levels never give cases.
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
| PC RP at Expert and up | x0.5 | the global queue is live and there are 200+ Master and up: x0.1 |
| Diamond division | 4,000 RP | after 60 days, if under 1% of weekly players have reached Expert: 3,000 |
| Expert to Master divisions | 1,500 / 2,000 / 2,000 | after 90 days, if nobody is eligible for Grandmaster: shrink by a quarter |
| Reyes and Grandmaster seats | automatic, at most 50 / 500 | raise the caps only if the game passes about 20,000 CCU |
| Limited drops | one every 1-2 weeks | faster once the art pipeline allows; add copy caps if values fall |
| New-player free cases | 50 wins | if D1 retention is weak: 75 |
| Seasons | none (Season 0) | about 3 months after release, once the top tiers have players |

**Watch these numbers** (Roblox analytics and our own events): median hours to a first
Legendary (target 8-14), players' average saved money (rising fast = too much income), the share
of players who sell back Epics (high = too many Epics), money-pack conversion, and D1 and D7
retention for the onboarding.

---

## 15. Cues entering the game at scale

| Rarity | Per hour played | 500 peak CCU (per day) | 2k peak CCU | 10k peak CCU |
|---|---|---|---|---|
| Common | 3.44 | 20,600 | 82,500 | 413,000 |
| Uncommon | 1.70 | 10,200 | 40,800 | 204,000 |
| Rare | 1.69 | 10,200 | 40,700 | 203,000 |
| Epic | 0.47 | 2,800 | 11,300 | 56,500 |
| Legendary | 0.096 | 580 | 2,300 | 11,600 |
| Mythic | 0.014 | 81 | 330 | 1,600 |
| Secret | 0.0013 | 8 | 30 | 150 |

(Player-hours a day taken as peak CCU x 0.5 x 24.)

These are early-life rates (they include the one-time rank rewards), so real supply settles
lower. Each rarity's supply is shared across its cues: at launch 3 Legendaries and 2 Mythics.

---

## 16. What changes in the build

- **Config** (`src/shared/Config.luau`): `Config.Ranks` gets the new division widths, the
  per-tier base win and loss, the mode multipliers, Classic's fade, the gap scale, the PC
  share by tier, the shield, the leaderboard seat rules and the new rewards (money plus cases
  plus cue). `Config.Economy` gets the PC and short-match limits, team pay, the win streak,
  the same-opponent table and the boost rules. New: `Config.Level`, `Config.Cases`,
  `Config.Limited`, `Config.DailyRewards`, `Config.Products`, `Config.Trading`.
- **Save** (a new version with a migration): level and EXP, rookie matches left, unopened
  cases by type, wins today and lifetime wins (for the free case), streak day and last claim,
  playtime today, same-opponent counters for today, VIP-from-offer, welcome-offer windows,
  starter pack bought, first purchase done, Limited cues bought.
- **Order** (fits Roadmap stages 2 and 4): the new RP numbers and gap factor (Config and the
  rank module), then EXP and Levels, then the catalog, inventory and cases (free win case
  first), sell-back, copies-in-existence counters, the Limited shelf, daily rewards, the Robux products, trading's gates, the
  Grandmaster/Reyes leaderboard, and the PolicyService checks.

---

## 17. Open (the designer's call)

- Whether completing a row in the Index pays (suggestion: all Commons $1,000, Uncommons
  $2,500, Rares $7,500, Epics $25,000, plus a title).
- The Level chip's look, and the RP label on the rank HUD.
- R6 and the 18+ DevEx rate (section 13).
