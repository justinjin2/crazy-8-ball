# Economy: money, ranks, lucky blocks, the shop and Robux

The one place that says how the game's economy works and every number in it. Rewritten
2026-10-08 for **economy v4, "the forgiving economy"**: the plan the designer approved on
2026-10-08 (`docs/prompts/ECONOMY_V4_PLAN.md`, from research and a 60-day population
simulation) and the designer's answers that day, on top of the first economy plan (approved
2026-10-02) and the lucky blocks that replaced cases (2026-10-04). GDD sections 11 and 12 point
here. Every number is a starting value *(tune)*: it lives in `src/shared/Config.luau` and changes
after playtests. Change a number here and in Config together, then re-run the model.

```bash
python3 tools/economy_model.py                 # v4 at day 7, 30 and 60, against the targets
python3 tools/economy_model.py --built-only    # without the planned features (section 10.6)
python3 tools/economy_model.py --compare       # the economy before v4, v4 built only, v4
python3 tools/economy_model.py --retention typical   # a typical Roblox game's retention
python3 tools/economy_model.py tables          # odds per block and per Mystery block, money, rank hours
python3 tools/economy_model.py value           # the Robux value ladder; money against Robux
python3 tools/economy_model.py players         # reference players: first session ... day 30
python3 tools/economy_model.py copies          # when each cue's first 100 copies are gone
python3 tools/economy_model.py ranks           # a year of players on the rank ladder (slow)
```

The model reads every game number from Config (through `tools/export_economy.luau` and
`tools/economy_config.json`); only how players behave is assumed.

**Built for a small launch, ready to grow.** Nothing assumes the game blows up. The ranks, blocks
and rewards work the same with 200 players online as with 20,000; the few things that should
change as the game grows are listed with their triggers in section 14.

**Odds are percentages everywhere**: the Mystery block's tier roll, every block, every cue, the
restock slots, ability spins. Every list adds up to exactly 100%, and tiny values keep enough
decimals to stay above zero. Since v4 a tiny chance also shows **"1 in N" beside its %**
(0.0001%, 1 in 1,000,000; v4 plan section 13, approved 2026-10-08).

---

## 0. At a glance

- **The forgiving economy** (designer, 2026-10-08): rare things are reachable, so players get
  the "what could I get" moment often, but each rarity keeps its place. About 5 to 8 times as
  many players own a Legendary, Mythic or Secret as before v4 (section 1).
- **One bar: rank XP.** No Levels. XP is never lost and comes only from winning: **100 XP a
  win, 0 a loss** (designer, 2026-10-02). Rank is the main way to show status.
- **Money**: $100 a ball, $500 for a win, $150 for a loss. A Classic match pays the winner about
  **$1,340** and the loser about **$600**: about **$7,300 an hour** (unchanged by v4).
  Difficult pays x1.5 and Challenger x2.
- **The daily win track** (v4): the first 10 wins of each day give lucky blocks in a set order,
  **Rare, Mystery, Mystery, Uncommon, Mystery, Mystery, Rare, Mystery, Mystery, Epic**; win 11
  and later pay money and XP only. **Every daily thing resets at 08:00 UTC** (section 7.5).
- **The Mystery block** starts as Standard on its upgrade screen and climbs over **5 presses**:
  half end above Standard (Standard 50%, Uncommon 40%, Rare 9.52%, Epic 0.42%, Legendary 0.05%,
  Mythic 0.01%). Pity (Rare by 10, Epic by 100) counts every Mystery block, bought ones too.
- **Every block can surprise**: each tier block keeps its floor (never below the rarity under
  its name) and every block can now give the Secret (section 7.2).
- **The first week** (v4): any 7 login days within 14 days of joining. Day 2 an **Epic block**,
  day 7 a **Legendary block**. A day counts once a match is finished that day (section 10.1).
- **Money buys** Mystery blocks ($4,900), the **restock shop** (Rare-or-better blocks every 10
  minutes, a Mythic block about every 5 days), the Grand Opening block while it runs ($24,900)
  and ability spins ($12,500). Timers are skipped for Robux only, **4 / 9 / 15 R$** by time left.
- **Robux is the smart route**: buying with money costs about 2-3x more for everyday blocks and
  4.5-6.6x more for the restock's rare blocks (section 11.9). Top price **1,699 R$**.
- **VIP** (399 R$): 2x money, no timers and a **Rare block every day** ($5,000 where paid random
  items are restricted).
- **Robux**: 3 game passes and 34 developer products (6 of them retired, never deleted),
  plus a Get Roblox Plus button (section 11.5).
- **Trading**: anyone in the server, cues and ready lucky blocks, never money, an atomic swap
  with a ledger (designer, 2026-10-03). Block worth is worked out live (section 12).
- **No reward popups** (designer, 2026-10-04): every reward is claimed in the Rewards menu.
- **Saves**: version 9 (v4, 2026-10-08) adds the win track and the first week (section 18).

---

## 1. The designer's targets, and how v4 meets them

**The metric** (designer, 2026-10-02): the share of players active in the last 7 days who own
at least one cue of a rarity. **The targets** were approved with v4 on 2026-10-08: week 1 is the
designer's own (Legendary 2-3%, Mythic 1% or less, the Secret far rarer); Epic in week 1 and
every day-30 and day-60 range are the plan's. They replace the old day-30 targets (Epic about 5%,
Legendary about 1%, Mythic 0.5% or less).

The model (`python3 tools/economy_model.py`, re-run 2026-10-08 on the numbers in Config):

| Rarity | Week 1 target | Day 7 | Day 30 target | Day 30 | Day 60 target | Day 60 | Before v4 (day 7 / 30 / 60) |
|---|---|---|---|---|---|---|---|
| Epic | 15-22% | **18.63%** | 25-35% | **32.37%** | 35-45% | **42.07%** | 2.67% / 5.77% / 10.04% |
| Legendary | 2-3% | **2.30%** | 6-9% | **7.82%** | 10-14% | **12.43%** | 0.46% / 0.88% / 1.89% |
| Mythic | 1% or less | **0.23%** | 0.7-1.2% | **0.93%** | 1.2-2% | **1.61%** | 0.05% / 0.10% / 0.23% |
| Secret | 0-0.05% | **0.01%** | 0.05-0.15% | **0.10%** | 0.1-0.3% | **0.17%** | 0.01% / 0.01% / 0.03% |

**Every target is met.** Without the planned features (section 10.6; `--built-only`) the shares
barely move: Epic 17.27 / 31.57 / 41.54%, Legendary 2.27 / 7.63 / 12.30%, Mythic 0.27 / 0.93 /
1.61%, Secret 0.02 / 0.09 / 0.19%: also every target met.

**Why the shares grow over time:** players active at day 60 are mostly veterans, and almost
everyone who stays a week owns an Epic (the first week's day-7 Legendary block is Epic or
better). Epic becomes "you stuck around"; Legendary stays about 1 in 8 veterans, Mythic about
1 in 60, the Secret about 1 in 500.

**How sure is this?** The model assumes a very strong game: 1,700 new players on day 0, growing
5.5% a day for 40 days (about 500 peak players online in week 1, about 5,000 by day 45-60), and
about 28% of new players back the next day, more than Roblox's top 1% (22%; the median game
keeps 10.3%, GameAnalytics 2026). With typical retention (`--retention typical`, about 12% next
day) every share is about half and below the targets: Epic 12.49 / 19.11 / 23.65%, Legendary
1.68 / 3.39 / 5.25%, Mythic 0.16 / 0.45 / 0.65%, Secret 0.01 / 0.05 / 0.06% (day 7 / 30 / 60).
The plan keeps the strong assumption every past plan used; watch the real numbers after launch
(section 14).

**Where the Epic-and-up copies come from** (day 30): login and the 28-day track about 42% of
Epics and 54% of Legendaries, the win track about 25% and 15%, the Grand Opening about 10%,
playtime 7%, the rest small. **Cues entering the game per day** (average of the week before,
day 30): Rare about 31,800, Epic 2,800, Legendary 410, Mythic 47, Secret 4.

**What a player gets** (`players`: 1,000 identical players each, 50% win rate, every day from
launch; free players spend 70% of their money on Mystery blocks and spins):

| Player | Own one at day 7 (Epic / Legendary / Mythic / Secret) | Day 30 | Money earned by day 30 |
|---|---|---|---|
| Free, 30 min a day | 84% / 27% / 3.4% / 0.6% | 97% / 38% / 6.6% / 0.8% | $338,000 |
| Free, 1 h a day | 84% / 31% / 3.7% / 0.6% | 99.6% / 48% / 6.0% / 1.0% | $571,000 |
| Free, 3 h a day | 97% / 37% / 4.6% / 0.4% | 100% / 77% / 17% / 1.7% | $1,489,000 |
| VIP, 1 h a day | 87% / 29% / 4.6% / 0.5% | 99.6% / 48% / 8.4% / 0.7% | $848,000 |
| Small spender: VIP, 1 h, 500 R$ a month | 90% / 34% / 4.0% / 0.4% | 99.8% / 52% / 7.7% / 1.3% | $990,000 |
| Big spender: VIP, 3 h, 5,000 R$ a month | 100% / 72% / 11% / 0.7% | 100% / 99% / 39% / 4.1% | $3,258,000 |

These players never skip a day; most real players do, which is why the whole-game shares above
are far lower.

**Other targets (still true):**

| Target (designer) | How it is met |
|---|---|
| A guaranteed better block early (2026-10-08) | win 1 of every day is a Rare block; the first week's day 2 is an Epic block |
| Legendary and Mythic stay reachable (2026-10-08) | every block reaches the Secret; the Mystery block climbs to Mythic 1 in 10,000 |
| Lots of duplicates of Commons to Rares | about 10 blocks a day from wins, 93% of a Mystery block's cues Common or Uncommon |
| Block cues keep their value | no direct buying (section 9); copy caps on the Grand Opening's Uniques |
| (2026-10-02) 1 win to Bronze I, 2 to Bronze II, 3 to Bronze III... | divisions in wins of 100 XP (section 4.2) |
| (2026-10-02) 3 h a day at 50%: Expert 1 month, Veteran 2, Master 3-4, Grandmaster 6, Reyes 7+ | the ramp from Diamond (section 4.2) |
| (2026-10-02) XP strictly from skill | wins only; harder modes, streaks and stronger opponents pay more |
| Losing is never a punishment (2026-09-28) | a loss gives 0 XP, never negative, and $150 |
| VIP 2x money, not overpowered | 2x money, no timers and one Rare block a day; never better odds, never XP |
| Most expensive item about a phone Robux pack (2026-10-08) | 1,699 R$ (one $19.99 pack of 1,700 R$) |

---

## 2. The first hour (onboarding)

What a new player gets, in order, at an ordinary 50% win rate (all claimed in the Rewards menu,
except the tutorial's blocks):

| When | What happens |
|---|---|
| Join | 1 starter ability spin (the tutorial, 2026-10-03). |
| The first win (the tutorial) | Unranked to **Bronze I**: a **Standard lucky block at once** (the tutorial opens it to an Uncommon cue; `Config.Tutorial.BronzeBlockKind`), then $2,500, a Mystery block, the Bronze Cue, the [BRONZE] tag and +1 ability spin once claimed in Rank. The win's own block is step 1 of the day's win track, a **Rare block** (5-minute timer): the first win ever is always a Rare block. |
| The first finished match | first-week day 1 can be claimed: **$5,000 + a Mystery block** (a login day counts once a match is finished that day). |
| 5 minutes | playtime gift: $1,000 |
| The second and third wins | 2 Mystery blocks (win track steps 2 and 3); the third win is **Bronze II**: $1,000 |
| 15 minutes | playtime gift: 1 Mystery block |
| The fourth win | an Uncommon block (step 4) |
| 30 and 45 minutes | playtime gifts: 1 Mystery block each |
| 60 minutes | playtime gift: **a Rare block + 1 ability spin** |

Every new cue also pays finder's money the first time (section 18). The model's first 20
minutes (the tutorial, then the group, the favorite and the launch codes): about **10 Mystery
blocks, 2 Rare blocks** (the first win and ROOFTOP), the Lucky 8 block and Bronze's Standard
block, about **$28,600** earned, and about 6% already own an Epic. **Login day 2 is an Epic
block**: a 30-minute player's chance to own an Epic goes from about 8% to about 29%. Silver
comes after about 6 hours of play (21 wins). The Starter Pack offer appears after the first
block opening (section 11.4).

---

## 3. Money

Money is earned by playing and spent in the shop. It **never trades** between players.
Unchanged by v4.

### 3.1 One match (1v1 against a person, Classic)

| What | Money | Notes |
|---|---|---|
| Each ball that counts for you | **$100** | your group, legal open-table pots, the break's balls, the 8 when it wins |
| Nice shot on top | **bank or kick +$150, combo or carom +$200** | to the shooter only |
| Win | **+$500** | only after a real match (past the one-minute mark, not a quick forfeit) |
| Loss | **+$150** | money even when you lose; the leaver gets nothing |
| Win streak | **+$250** on each win from the 3rd in a row | against people only |

Average match: winner about **$1,340**, loser about **$600**. At 7.5 matches an hour that is
**about $7,300 an hour** (plan, 2026-10-02; v4 kept it: the money prices moved instead).

### 3.2 By opponent

| | Against people | Play against PC (on purpose) | Disguised bot (queue fallback, tutorial, lobby bots) | Solo |
|---|---|---|---|---|
| Each ball | $100 | $100 | $100 | **$30** until $3,000 of solo money in a day, then **$10** |
| Nice shot on top | bank/kick +$150, combo/carom +$200 | same | same | none |
| Win / loss bonus | $500 / $150 | **$250 / $80** | $500 / $150 | none |
| Win streak (3rd win in a row on) | +$250 | none | none | none |
| Daily limit | the same-opponent rules (3.6) | after **$10,000** of PC money in a day, everything pays half | after **20 disguised wins** in a day they pay the PC rows and give no block (hidden) | as above |
| Moves the win track (7.5) | every win | the **first 10 PC wins** of a day | every win (until the 20) | never |
| XP | 100 a win | x0.75, x0.5 from Expert | like a person, stored as a PC win, no streak | none |

"A day" for every daily limit starts at **08:00 UTC** since v4 (section 7.5).

- The disguised limit is **hidden** (designer, 2026-10-03): the result screen just shows the
  smaller numbers and no block, with no message. It stops farming lobby bots in an empty server.
- A disguised bot that forfeits gives a full disguised win, even under one minute. Both
  tutorial games are real wins, and the tutorial bot's early 8 pays in full.
- A disguised win counts as a PC win in the stats (never on the most-wins board).

### 3.3 Team matches (2v2, 3v3)

Every ball your team pots pays **each teammate $100**, so an hour of 2v2 or 3v3 earns about the
same as 1v1. The nice-shot bonus goes only to the shooter. The win and loss bonus, the win
track's block (each winner) and XP are per player, by the same rules; XP uses the opposing
team's average rank for the gap (section 4.4).

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

money = base x difficulty x (1 + VIP 1.0 + Money Party 1.0 + Starter hour 1.0 + group 0.1 + Roblox Plus 0.1)

- Only **match money** is boosted (balls, nice shots, match bonuses). Never rewards, finder's
  money, sell-back or packs.
- The Starter Pack's hour of 2x adds to VIP's: x3 for that hour (designer, 2026-10-03).
- The group's +10% is on while the player is a member of the game's group (section 10.4).
- No boost ever changes block odds or how many blocks a player gets. VIP's block timers (none)
  and daily Rare block (11.2) are its perks outside money.

### 3.6 Anti-farming (alts and friends)

- **Same opponent, same day:** matches 1-5 pay in full; 6-10 pay half the XP and half the
  win/loss bonus and move no win-track step; from the 11th, no XP, a quarter of the bonus, half
  the ball pay, no step. At most **3 win-track steps a day from beating the same account**
  (`Config.Economy.DropsPerOpponent`).
- **The loser must have played 5 real matches** for the winner's step (a fresh alt can't feed
  blocks; `Config.Economy.DropLoserMinMatches`).
- **A login day counts only after a finished match that day** (v4), so an alt can't collect the
  first week's Epic and Legendary blocks by just joining (section 10.1).
- **Short matches:** pots are still paid live, but money from matches that end before the
  one-minute mark counts toward a **$2,000 a day** short-match limit; past it, balls before the
  one-minute mark pay **$10** each.
- Forfeits, leavers and the one-minute mark stay as built (GDD section 13).
- Private servers, when they come: no XP, no blocks, solo-rate money.
- With no trade gate (section 12), these rules and the invite cap are the alt protection. The
  designer chose not to hold first-week cues from trading (2026-10-08: the match rule is enough
  for now; watch the trades).

### 3.7 How money is shown

Full digits up to **$999,999**, then short: **$1.2M** (`Format.money`). The currency is always
called "money".

---

## 4. Ranks (XP)

Unchanged by v4 except the rank rewards (4.8).

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

- **XP boosts**: only the win streak (+25%, 4.3). The Rookie Boost, the first win of each day
  and VIP's XP were removed on 2026-10-02: they were not skill.
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

`Config.Ranks.Rewards`. Money for each new division is unchanged; v4 (2026-10-08) pays better
blocks from Platinum up and the first Legendary block at Expert (about a month at 3 hours a
day; before v4 it waited for Master). Reaching a tier also gives the tier's cue (the Ranked
rarity, never traded or sold), its chat tag and ability spins (+1 for Bronze, Silver and Gold;
+2 for Platinum and Diamond; +3 from Expert up).

| Tier (Classic wins to reach) | Each new division II-V | Reaching the tier (division I) | Before v4 |
|---|---|---|---|
| Bronze (1) | $1,000 | $2,500, a Mystery block (plus the Standard block given at once with the first win) | same |
| Silver (21) | $2,000 | $5,000, a Rare block | same |
| Gold (66) | $3,500 | $10,000, 2 Rare blocks | same |
| Platinum (136) | $6,000 | $20,000, **an Epic block** | 3 Rare blocks |
| Diamond (232) | $15,000 | $50,000, **2 Epic blocks** | an Epic block |
| Expert (393) | $30,000 | $100,000, **a Legendary block** | 2 Epic blocks |
| Veteran (675) | $50,000 | $200,000, **a Legendary block and an Epic block** | 3 Epic blocks |
| Master (1,180) | $80,000 | $400,000, **2 Legendary blocks** | a Legendary block |
| Grandmaster (2,025) | $150,000 | $750,000, **a Mythic block** | 2 Legendary blocks |
| Reyes (3,075) | - | $2,000,000, **2 Mythic blocks**, the rainbow tag | a Mythic block |

Blocks from rank rewards land in the hotbar on their normal timers (section 7.2). Only Bronze's
Standard block is given at once (the tutorial opens it); every other reward waits in Rank until
claimed (designer, 2026-10-03). A Reyes Cue proves Reyes: it can't be traded. Rank rewards stay
a small source (about 2-4% of Epic-and-up copies) because few players climb that far.

### 4.9 How long each tier takes

Hours of play against equal opponents (a Classic match plus the time between is about 8
minutes, so 7.5 matches an hour; the streak bonus included; `economy_model.py tables`):

**Classic only:**

| Win rate | Silver | Gold | Platinum | Diamond | Expert | Veteran | Master | Grandmaster | Reyes |
|---|---|---|---|---|---|---|---|---|---|
| 45% | 6 h | 19 h | 38 h | 65 h | 111 h | 190 h | 333 h | 571 h | 867 h |
| 50% | 5 h | 17 h | 34 h | 58 h | 99 h | 169 h | 296 h | 508 h | 772 h |
| 55% | 5 h | 15 h | 31 h | 52 h | 89 h | 152 h | 266 h | 456 h | 693 h |
| 60% | 4 h | 13 h | 28 h | 47 h | 80 h | 138 h | 241 h | 413 h | 627 h |

**A typical mix of modes** (Classic early, some Difficult and Challenger from Gold): about 5-10%
faster from Diamond (50%: Expert 93 h, Grandmaster 472 h, Reyes 716 h).

In months for the designer's reference player (**3 hours a day, 50%, Classic**): Silver on
day 2, Gold in about 6 days, Diamond in about 3 weeks, **Expert 1.1 months, Veteran 1.9,
Master 3.3, Grandmaster 5.6, Reyes 8.6**. An hour-a-day player takes three times as long
(Expert in about 3 months); a 5-hour-a-day grinder at 55% about half as long (Expert in about
18 days, Reyes in about 5 months).

### 4.10 What the ranks look like over a year (simulation)

Simulation (rerun 2026-10-02; `economy_model.py ranks`): 2,000 new players a day for a year
(about 2,300 peak players online by the end), most leaving on day one and a few staying for a
year or more (playing up to 6 hours a day), each with a hidden skill; half their matches near
their own rank. "Ever" counts everyone who reached the tier or higher, including players who
later quit.

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
| **Unique** | numbered cues (only two: the Firework Cue, 1,000 copies ever, and the Beta Cue, 100 ever, both from the Grand Opening block; there is no Founder's Cue, ever) | the Grand Opening block's two Unique rows (9.2), or the Limited shelf for a set time | yes | no |
| **Ranked** | the ten rank cues (Bronze Cue ... Reyes Cue): one rarity since 2026-10-08 (designer), each card in its tier's colours; their group stays Exclusive | reaching each tier, once | **never** | no |
| **Exclusive** | the VIP Cue, the Starter Cue, later season cues | one special way each | **never**, except the Starter Cue (designer: VIP never, 2026-09-28; the Starter Cue trades, 2026-09-29) | no |

What rarity looks like (GDD section 12, UI_STYLE section 4 colours): Common and Uncommon keep
the plain wisp trail (Uncommon tinted); Rare adds a coloured trail and small pocket burst; Epic
has its own trail and pocket effect; Legendary an animated trail, pocket effect and sound;
Mythic the celestial shimmer and its own VFX; Secret a one-of-a-kind full set.

**Launch catalog: 46 block cues**: 7 Common, 9 Uncommon, 10 Rare, 9 Epic, 7 Legendary,
3 Mythic, 1 Secret. Classic is labelled Common too but is the free default: everyone owns it,
no block drops it, and it is never traded or sold. Plus 10 Ranked (the rank cues), 2 Exclusive
(VIP, Starter) and 2 Unique (Firework and Beta, both from the Grand Opening block). The list
and order are `Progression/Catalog.luau`; each cue's look is its skin (`src/shared/CueSkins`).

Adding cues later keeps each rarity's % per block; each cue's own share shrinks. **To make a
rarity easier later, add new cues and retire old ones**, never raise the odds on the same cues
(v4 plan section 11: copies of the exact cue set its trade worth).

**Copy numbers** (GUI session, approved 2026-10-08): the first 100 copies of every Rare-or-rarer
cue are numbered #1-100. Under v4 the model has each cue's #100 gone by about day 1 (Rare),
day 4 (Epic), day 11 (Legendary), day 22 (Mythic) and day 35 (the Secret), so "#12/100" is a
launch-month badge (the designer kept #1-100, 2026-10-08).

---

## 7. Lucky blocks

A block waits in the hotbar (and its bag), is held, thrown into the world and opened there with
a hold prompt; the reel plays (`BlockReel`), a Rare or better cue plays its pull cutscene, then
the "YOU GOT" card (designer, 2026-10-04: lucky blocks replaced cases). The odds engine is
`Config.BlockOdds` (`Progression/BlockOdds.luau`: one odds row per block kind,
`Config.LuckyBlocks.Kinds[kind].Odds`); the Mystery block's tier roll and the win track are
`Config.BlockOdds.Drop` (`Progression/BlockDrop.luau`).

### 7.1 The Mystery block

A Mystery block (from the win track, rewards or the shop) **rolls its tier when it is opened**,
out of 1,000,000 (`Config.BlockOdds.Drop.Weights`; v4, 2026-10-08: half end above Standard):

| Tier | Weight | Chance | Before v4 |
|---|---|---|---|
| Standard | 500,000 | 50% | 68% |
| Uncommon | 400,000 | 40% | 25% |
| Rare | 95,200 | 9.52% | 6.7% |
| Epic | 4,200 | 0.42% (1 in 238) | 0.28% |
| Legendary | 500 | 0.05% (1 in 2,000) | 0.0196% |
| Mythic | 100 | 0.01% (1 in 10,000) | 0.0004% |

Chance to reach each tier or better: Uncommon 50%, Rare 10%, Epic 0.48%, Legendary 0.06%,
Mythic 0.01%.

- **The upgrade screen** (v4 plan 3.2, like Brawl Stars' Starr Drop): the Mystery block has no
  timer. Its hotbar slot says **OPEN!**; a tap opens its upgrade screen, where the block
  **starts as Standard** and is opened by **5 presses** (`Drop.Upgrade.Clicks`). Each press
  lifts it one tier or doesn't. The server rolls the final tier first (by the weights, with
  pity), then picks which presses climb, **every choice equally likely** (`BlockDrop.path`): a
  Mythic climbs on all 5, a Legendary on 4 of the 5, an Uncommon on 1 (it may be the last).
  Every block above Standard visibly climbs; a climb never fizzles or falls back.
- **Honest by construction**: the screen never shows a "chance per press" (it isn't a fixed
  number). It says the result is decided when the block is opened and the presses reveal it,
  and it shows the final-tier table, each tier block's cue odds, the pity counters and the live
  pity odds. (`Drop.Upgrade.Chances`, the old per-press chain, is unused by the server and kept
  only until the GUI's MysteryReveal stops reading it.)
- The block becomes that tier's block in the save at once (same slot, its origin kept) and lands
  back in its slot on **that tier's own timer** (a bought one and a VIP's at once).
- **Pity, for every Mystery block, bought ones too** (v4: before v4 the code gave a bought
  block plain odds): the **10th** Mystery block in a row below Rare is Rare; the **100th** below
  Epic is Epic (was 150th). With Epic-or-better at 0.48% a block, about 6 in 10 players who
  open 100 Mystery blocks get there by pity. Pity never gives a Legendary. The counters
  (`PityRare`, `PityEpic`) are sent to the screen.

**Per Mystery block overall**, the chance of each cue rarity (`BlockDrop.rarityOdds()`; the cue
cards' chance chip):

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| 52.25% | 40.5736% | 6.79586% | 0.32688% (1 in 306) | 0.046268% (1 in 2,161) | 0.0066328% (1 in 15,077) | 0.0007592% (1 in 131,718) |

### 7.2 The blocks

**Each tier block keeps its floor** (never below the rarity under its name; the Mythic block is
Legendary or better) and **every block can reach the Secret** (v4, 2026-10-08). Odds in
percent; each row adds to exactly 100 (in Config, whole parts of 1,000,000). Timers are
`Config.LuckyBlocks.Kinds[kind].Timer`.

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Opens in |
|---|---|---|---|---|---|---|---|---|
| Standard | 72.5% | 25% | 2.4% | 0.09% (1 in 1,111) | 0.009% (1 in 11,111) | 0.0009% (1 in 111,111) | 0.0001% (1 in 1,000,000) | at once |
| Uncommon | 40% | 54% | 5.8% | 0.18% (1 in 556) | 0.018% (1 in 5,556) | 0.0018% (1 in 55,556) | 0.0002% (1 in 500,000) | 1 min |
| Rare | - | 68% | 31% | 0.9% (1 in 111) | 0.09% (1 in 1,111) | 0.009% (1 in 11,111) | 0.001% (1 in 100,000) | 5 min |
| Epic | - | - | 77.3% | 21% | 1.5% (1 in 67) | 0.18% (1 in 556) | 0.02% (1 in 5,000) | **30 min** (was 1 h) |
| Legendary | - | - | - | 72% | 25% | 2.7% (1 in 37) | 0.3% (1 in 333) | 6 h |
| Mythic | - | - | - | - | 72% | 25% | 3% (1 in 33) | 12 h |

The other kinds (`Config.BlockOdds.List`, each its own odds row):

| Block | Odds | Opens in | Comes from |
|---|---|---|---|
| Mystery | rolls a tier (7.1), on its upgrade screen | at once | the win track, the shop, rewards |
| Grand Opening | Rare 81.84%, Epic 10%, Legendary 1.6% (1 in 63), Mythic 0.15% (1 in 667), Secret 0.01% (1 in 10,000), **the Firework Cue 6%, the Beta Cue 0.4%** (1 in 250), capped and per player (9.2) | at once | the shop, while it runs (9.2) |
| Starter | Rare 90%, Epic 9%, Legendary 0.9% (1 in 111), Mythic 0.09% (1 in 1,111), Secret 0.01% (1 in 10,000) | at once | the Starter Pack (11.4) |
| Sky | Common 45%, Uncommon 45%, Rare 9.5%, Epic 0.45%, Legendary 0.045%, Mythic 0.0045%, Secret 0.0005% | at once | Lucky Rain (planned, 10.6) |
| Lucky 8 | the Rare row | at once | the favorite reward (10.4) |
| Gift | the Rare row | 12 h, from the leave | once, the first time a player leaves the game; it falls from the sky on their next visit |

- **No block is sold permanently** except through the shop's Mystery deal (plan, 2026-10-02):
  blocks come from wins, rewards, the shop's Mystery and Grand Opening deals and the restock
  shop. **Mythic blocks are sold now, in the restock only** (v4, the designer's ask, 2026-10-08).
- **Timers** start by themselves when the block lands in the hotbar. They all run at once;
  there are no slots. Opening a block before its timer is done answers "Not ready yet"; the
  hotbar slot counts down. A bought block (paid origin) opens at once.
- **VIP has no timers**: every block opens at once (`Config.LuckyBlocks.VipTimerFactor` 0,
  designer 2026-10-07).
- **Skips**: a timer is finished with Robux only, **4 / 9 / 15 R$ by time left** (9.1). No money
  skip.
- A block can be **traded** only once its timer is done (section 12).
- Blocks live in the hotbar and its bag (`Config.LuckyBlocks.MaxBlocks`), never in the
  Inventory menu.

**The spin reel** (designer, 2026-10-08: rare cues pass by more often, with safeguards; the
reel's look is the GUI session's): every reel shows only cues from that block's own pool, which
includes every rarity it can drop; each spin gets **one showcase tile** (an Epic-to-Secret cue
from the pool) in the first two-thirds of the strip, never within 8 tiles of where it stops, and
printing its own odds ("SECRET · 1 in 1,000,000"); every other tile is drawn at the real odds;
the reel never slows near a rare tile; under it: "The reel shows what this block can drop. Your
chances are under Odds." No slot-machine looks (lever, 7s, "JACKPOT"). If Roblox ever rules
against the showcase tile, it turns off and the rest stays.

### 7.3 Odds screen and per-cue odds

Every cue of a rarity in a block has an equal share: **cue % = rarity % / cues of that rarity
in the block**. With the launch catalog, each Legendary in the Legendary block is 25 / 7 =
3.5714%, each Mythic 2.7 / 3 = 0.9%, and the one Secret 0.3%. The shop's block cards and the
reel show the odds; an **"Odds & Details"** button (words, not just an icon) lists every cue
with its % and "1 in N", and totals exactly 100%. The Grand Opening's odds are the player's own
(9.2).

**Cue cards** show the rarity, **its % per Mystery block and "N exist"**, for example "EPIC ·
0.327% · 1,284 exist". A cue's own % shows only in the Odds list. "N exist" reads "fewer than
10" until there are 10 copies.

### 7.4 Announcements and retiring

- Unboxing a **Mythic or Secret** is announced in every server; a **Legendary** in the opener's
  server (plan, 2026-10-02). The every-server line reads "[GLOBAL]: <username> pulled a
  Mythical Cue!" in a pastel rainbow, or "... a Secret Cue!" in red (designer, 2026-10-05). No
  announcement names the cue, only its rarity (designer, 2026-10-05).
- **A Legendary or Mythic block in the restock** is announced in every server ("A MYTHIC block
  is in the restock for 9:41!"; `Config.Shop.Restock.Announce`).
- **Retired (vaulted) cues never come back** (plan, 2026-10-02). Odds screens update the moment a
  cue is retired.

### 7.5 The daily win track

Each real win (one that passes the anti-farm rules, 3.2 and 3.6) moves the day's **win track**
one step and gives that step's block (v4, 2026-10-08; `Config.BlockOdds.Drop.WinTrack`):

| Win of the day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Block | **Rare** | Mystery | Mystery | Uncommon | Mystery | Mystery | **Rare** | Mystery | Mystery | **Epic** | money and XP only |

- **Win 1 is a Rare block** every day: the guaranteed better block early (designer,
  2026-10-08). The first win ever is step 1 of day 1, so it is always a Rare block
  (`Drop.FirstWin`).
- **Win 10 is an Epic block**: a real daily goal (about 20 matches, nearly 3 hours). A 3-hour
  player reaches it about 3 days in 4.
- The steps follow the anti-farm rules exactly: a win moves the track only when it would have
  given a block before v4. So the first 10 PC wins a day count, disguised-bot wins up to 20 a
  day, at most 3 steps a day from beating the same account, the loser must have played 5 real
  matches, and solo never counts. **VIP gets no extra steps** (designer, 2026-10-08: VIP's perk
  is a daily Rare block instead, 11.2).
- **The day starts at 08:00 UTC for every daily thing** (`Config.Daily.ResetHour`): the win
  track, the login day, playtime, VIP's block and the anti-farm "same day" limits. 00:00 UTC
  was 8 pm in New York, the middle of US evening play; 08:00 UTC is 3-4 am in New York, 5 am in
  Brazil, 8-10 am in Europe (Brawl Stars resets at 08:00 UTC too). There is no minimum gap
  between two claims: a session that crosses 08:00 UTC can claim two days.
- **The payload**: a win's block rides `MatchSummary.block = { kind, readyAt }` (already in the
  hotbar when it arrives). `RewardView` sends the day's track (`wins = { given, kinds }`) for
  the bar above the hotbar ("Lucky Blocks today 7/10"). The server decides everything before
  any reel starts; the reel only shows it. No fake "almost" moments.

---

## 8. Selling cues back

Any block-rarity cue can be sold for money, with a confirm step from Epic up and a "Duplicate"
tag on extras. Ranked, Exclusive and Unique cues can't be sold. A paid-origin copy is sold first.
Unchanged by v4 (a Legendary sells for a sixth of a restock Legendary block, so there is no
sell-and-rebuy loop).

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| $150 | $400 | $1,500 | $25,000 | $250,000 | $2,500,000 | $25,000,000 |

Selling also removes cues from the game, which keeps the ones that stay worth more.

---

## 9. What money buys, and the Limited shelf

**Block cues are never sold directly** (designer, 2026-09-27). A Common-to-Secret cue comes
only from a lucky block or a trade. That keeps every block a chance at something money can't
simply buy, and gives trading its purpose.

Money prices (v4, 2026-10-08; match money stays about $7,300 an hour of Classic):

| Item | Price | Hours of play | Before v4 |
|---|---|---|---|
| Mystery block | **$4,900**; 10 for **$44,100** (the price of 9) | 0.7; 6 for 10 | same |
| Grand Opening block | **$24,900**; 3 for **$69,900**; 10 for **$219,000** | 3.4 for one | $49,000 / $139,000 / $441,000 |
| Restock Rare / Epic / Legendary / Mythic | **$19,900 / $199,000 / $1,490,000 / $4,990,000** | 2.7 / 27 / 205 / 686 | Uncommon $14,900, Rare $34,900, Epic $349,000, Legendary $3,490,000, no Mythic |
| Ability spin | **$12,500** each (buy 1, 5, 10 or 50; no bulk discount) | 1.7 | $17,500 |
| Timer skip | Robux only, **4 / 9 / 15 R$** | - | 19 R$ |
| Limited cues | none at release | - | - |

**When a player has part of the price**, the buy button says "Need $X more" and opens the money
packs with the smallest pack that covers the gap highlighted. Never right after a lost match.

### 9.1 Mystery blocks, the restock shop and the timer skip

**Mystery blocks**: bought with money ($4,900, or 10 for $44,100; `Config.Shop.Deals.Mystery`)
or Robux (Mystery1 **5 R$**, Mystery10 **45 R$**; 13 for 45 R$ during the launch bonus, 11.1).
A bought block is paid origin, opens at once and gets pity like any other (7.1). They are paid
random items (section 13). The Mystery block is the cheap gamble: worth about 6.1 R$ on the
value ladder for 4.5-5 R$ (11.9).

**The restock shop** restocks every **10 minutes on the clock** (UTC :00, :10, ...). Every
server shows the same blocks (picked from the time slot's number), with a real countdown
(`Config.Shop.Restock`, `Progression/Restock.luau`). **Three slots each roll one block kind**,
and a fourth, VIP-only slot rolls from its own richer table (chances out of 10,000; v4,
2026-10-08: **Rare or better**, the Uncommon slot is gone because a Mystery block beat it):

| Block | A normal slot | The VIP slot | Money | Robux | Stock per player per restock |
|---|---|---|---|---|---|
| Rare | 87% | 80% | $19,900 | 15 R$ (RestockRare) | **2** |
| Epic | 12% | 17% | $199,000 | 99 R$ (RestockEpic) | 1 |
| Legendary | 0.95% | 2.8% | $1,490,000 | 599 R$ (RestockLegendary) | 1; announced in every server |
| Mythic | 0.05% (1 in 2,000) | 0.2% (1 in 500) | $4,990,000 | 1,699 R$ (RestockMythic) | 1; announced in every server |

- **How often:** an Epic in about 1 restock in 3; a Legendary about 4 times a day; a **Mythic
  block about every 5 days** (the VIP slot's about every 3.5 days).
- Stock is per slot, one block per press; **money and Robux share the stock**. The slot odds
  are published on the restock screen. Every block in the VIP slot has its usual odds: VIPs
  see more good blocks, never better odds.
- A slot's shared stock counter (`GlobalStock`, the old plan's "25 worldwide") is in the code
  but no row sets it.
- Blocks bought here are paid origin and open at once. A known block costs a little more for
  what it gives than the gamble: Rare 1.07x, Epic 1.2x, Legendary 1.45x, Mythic 2.4x its price
  on the value ladder (11.9).

**The timer skip, by time left** (v4, designer 2026-10-08; `Config.LuckyBlocks.Skips`): the skip
button shows the price for the time left right now:

| Time left on the block's timer | Product | Robux |
|---|---|---|
| 30 minutes or less | LuckyBlockSkip (3716368528) | **4** |
| 6 hours or less | LuckyBlockSkip9 | **9** |
| more | LuckyBlockSkip15 | **15** |

- A late receipt whose block is already ready keeps a saved **skip credit** for the next timer.
  **Credits are tiered** (`SkipCredits1`, `SkipCredits2` in the save): a credit only skips a
  timer its own price covers, so a 4 R$ credit never skips a 12-hour timer.
- It is a paid random item (section 13), and it can't be gifted. A skip does not change a
  block's origin. Only the designer's account may bypass timers without paying (testing); the
  countdown stays visible. VIP keeps no timers at all.
- Still the cheapest skip per hour of any game found (Steal An Egg: 9 R$ for 15 minutes, 299 R$
  for 12 hours).

### 9.2 The Grand Opening and the Limited shelf

**The Grand Opening block** (v4 plan 8.5; `Config.Shop.Deals.GrandOpening`) is the launch gift:
Rare or better, never an Uncommon (the designer's ask, 2026-10-08), with the game's only two
Unique cues.

- **Price**: $24,900, 3 for $69,900, 10 for $219,000; or **19 / 49 / 149 R$** (the 3 and 10 save
  14% and 22% against 57 and 190 R$ one by one).
- **Window: 30 days** from `StartsAt` (0 = off), which the designer sets at publish (designer,
  2026-10-08: start at publish, maybe 30-45 days); a "Vaulted" card stays 7 days after the end.
  The launch bonus (11.1) runs on the same window.
- **Copy caps** (`Config.BlockOdds.List.GrandOpening.Caps`): **1,000 Firework Cues and 100 Beta
  Cues, ever.** Every server reads the copies taken from one shared counter. Once a cue's copies
  are all found, its row's share goes to Rare and the odds update everywhere at once; the card
  counts down ("Beta Cue · 23 of 100 left"), and copies read "#4 of 100". If another server took
  the last copy first, that open gives a Rare cue instead. So stretching the window never makes
  more. In the model all 1,000 Firework Cues are found by about day 21 and about 90 Beta Cues by
  day 21 (100 by about day 23).
- **Per-player odds** (Roblox's one-instance rule): a player who owns the Firework or Beta Cue
  can't get another, so their odds show that row as Rare (and the block rolls it as Rare).
- **The guarantee**: a player's **1,000th** Grand Opening block is the Beta Cue if they have
  none and any are left (was the 400th;
  `Config.LuckyBlocks.Kinds.GrandOpening.Guarantee`). At 0.4% a block, 98% of players who open
  1,000 get one before the guarantee; 1,000 blocks cost about 14,900 R$.
- Worth about 88 R$ on the value ladder plus the Uniques, for 14.9-19 R$.
- The Firework Cue has placeholder colours for now (designer, 2026-10-03); the real skin comes
  later. **There is no Founder's Cue**, ever (designer, 2026-10-05).

**The Limited shelf** sells **Unique** cues: exclusive designs that never appear in a tier block.
- **For a set time only**, with a real countdown that never restarts. When the time is up it
  is **never sold again** and becomes trade-only forever.
- **Numbered** (#1, #2, ...), **one per player**, optionally **copy-capped** (sold out when
  the cap is reached, across all servers).
- Priced in money, so it is a real saving goal. Some may be sold for Robux; a known item for
  Robux is not a paid random item. Limited cues bought with money or Robux are paid origin.
- **At release the shelf is empty** (designer, 2026-10-04). The shelf code stays
  (`Config.Shop.Limited`, one row per Limited plus its catalog cue); while empty nothing shows.
- **After launch**: one new Limited about every 2 weeks when art exists, $149,000-$499,000,
  some for Robux. None is scheduled yet (designer, 2026-10-03).

### 9.3 Copies in existence

Every cue, in the inventory, the Index, trades and the Limited shelf, shows how many exist in
the game ("1,284 exist"; "fewer than 10" below 10). A global counter per cue goes up when one is
unboxed or bought and down when one is sold back.

---

## 10. Free rewards

Free rewards are not paid random items, so they work everywhere, restricted regions included.
Every reward row is `{ Money, Blocks = { [kind] = n }, Spins }` (`Config.Daily`), and **every
reward is claimed in the Rewards menu** (designer, 2026-10-04: no reward popups; nothing is
given by itself on join).

### 10.1 Login: the first week, then later weeks

| Login day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| **First week** (once ever) | $5,000 + 1 Mystery block | **an Epic block** | $10,000 | 2 Mystery blocks | a Rare block | 3 Mystery blocks | **a Legendary block** + 2 ability spins |
| **Later weeks** | $5,000 | a Rare block | $10,000 | 2 Mystery blocks | $15,000 | 3 Mystery blocks | **an Epic block** + 2 ability spins |
| Before v4 (every week) | $5,000 | 1 Mystery | $10,000 | 2 Mystery | $15,000 | 3 Mystery | a Rare block + 2 spins |

- **The first week = the first 7 login days within 14 days of joining, in a row or not**
  (designer, 2026-10-08; `Config.Daily.FirstWeek`, `FirstWeekWindow` 14; the join's day is day
  1). After 7 claims, or after the window, the later weeks take over. Kids miss days; this
  forgives them.
- **A login day counts only once the player has finished a match that day** (any mode, PC
  included; `NeedsMatch`; designer, 2026-10-08), so an alt can't collect the first week by
  just joining. Until then the Rewards menu says to play a match first.
- **Day 2's Epic block** is the day-1 retention hook; **day 7's Legendary block** is the
  designer's ask. Later weeks step down to an Epic block on day 7.
- **Later weeks keep the streak** (`Config.Daily.Streak`): one claim per day; **one free streak
  freeze a week** (weeks start Monday): one missed day is covered by itself and the streak goes
  on. Two or more missed days start the week over.
- **VIP adds 1 ability spin and a Rare block** to each day's claim (11.2).
- Everyone also gets **1 free ability spin a day** on the Abilities screen (11.8).
- The day starts at 08:00 UTC (7.5).
- **Save version 9's migration**: a save that had already claimed 7 or more days counts its
  first week as done (it gets the later weeks).

### 10.2 The 28-day track

Counts every day claimed in total. It never resets and repeats every 28 days. On the day the
count reaches a step, its reward is added to that day's claim (`Config.Daily.Track`):

| Day 8 | Day 14 | Day 21 | Day 28 |
|---|---|---|---|
| a Rare block | 2 Rare blocks | 2 Rare blocks | an Epic block |

The first prize moved from day 7 to **day 8** (v4): day 7 already has the first week's
Legendary block, and Roblox's D7 counts a return on the 8th day, so day 8 needs its own reason.

### 10.3 Playtime gifts

Minutes played in a day, across sessions, each claimable once that day in the Rewards menu
(never given by itself). **Everything lands inside the first hour** (v4: Roblox's ranking counts
playtime up to 60 minutes a day):

| 5 min | 15 min | 30 min | 45 min | 60 min |
|---|---|---|---|---|
| $1,000 | 1 Mystery block | 1 Mystery block | 1 Mystery block | a Rare block + 1 ability spin |

Before v4: 10 min $2,000, 30 min 1 Mystery, 60 min 2 Mystery + 1 spin, 90 min $10,000, 120 min a
Rare block. A 1-hour player now gets more; a 2-hour player the same blocks and $11,000 less.

### 10.4 Group, likes, invites and codes

- **Group** (designer, 2026-10-03): the game's Roblox group **675425213** ("Lucky 8"). The
  Rewards card has **Join** (an in-game prompt) then **Claim**: **3 Mystery blocks**, once per
  player. While a member, match money gets **+10%** by itself (checked on join and on Claim).
- **Favorite**: favoriting the game through Roblox's prompt gives **$10,000 + a Lucky 8 block**
  once (designer, 2026-10-08; was a Mystery block; `Config.Social.FavoriteReward`). Roblox gives
  the server no way to check a favorite, so the client reports it.
- **Like codes** (designer, 2026-10-03): six codes, written now and **switched on live** by the
  designer with `/code on <CODE>` (every server at once, no republish) when the game reaches
  each like milestone. Word them as thanks for a milestone, never "like to unlock".

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
  once ever (their first invited friend's first win; `InviterOnce`), within the **5 a month**
  cap; an offline inviter gets theirs on their next join. Every invited friend still gets
  their own block.
- **The first leave**: a Gift block (the Rare row, 12 h from the leave), once (7.2).
- **Codes** (case-insensitive, once per player, an optional end date):

| Code | Gives |
|---|---|
| WELCOME | $5,000 + 1 Mystery block |
| 8BALL | $2,500 |
| ROOFTOP | a Rare block (until 2026-12-31) |
| RELEASE | 3 ability spins (the tutorial's code) |

  Codes give only money, lucky blocks and spins: never a cue, pass or boost sold for Robux.

Together the group, favorite, codes and invite are about a day's worth of blocks once.

### 10.5 VIP's daily Rare block

A **Rare block each day a VIP claims** (designer, 2026-10-08; `Config.Daily.VipBlocks`), added
to the day's claim. Same Rare row as every Rare block, never better odds. **Where PolicyService
restricts paid random items it is $5,000 instead** (`VipRestrictedMoney`), and so is it while
PolicyService hasn't answered (an unknown policy counts as restricted). VIP is now a paid random
item: its card shows the Rare block's odds, and VIP is never promoted on Roblox's Buy Robux page
(a pass promoted there can't grant paid random items).

### 10.6 Planned, not built yet

**Planned features** (v4 plan 6.4 and 6.5, 2026-10-08). Their numbers are set now in
`Config.Planned` so the model and this doc price them; nothing in the game reads them yet, and
each feature gets its own brief. The model includes them by default (`--built-only` leaves
them out; section 1).

- **The Daily Challenge: Lucky Shot and Golden Shot** (the designer's concept screens; "there
  will still be a golden shot for the lucky shot challenge", 2026-10-08). One shot a day at a
  ring target; the reward is by the ring hit:

| Ring | Miss | Grey | Blue | Red | Gold |
|---|---|---|---|---|---|
| Lucky Shot (free, once a day) | $500 | $1,500 | $3,000 | 1 Mystery block | 1 Rare block |
| Golden Shot (**15 R$**, once a day) | $5,000 | $7,500 + an Uncommon block | a Rare block | a Rare block + $10,000 | 2 Rare blocks + $25,000 |

  The Golden Shot's top prize stays 2 Rare blocks, never an Epic block: a skilled player can aim
  for gold every day. At an average player's rings it is worth about 26 R$ on the value ladder.
  It is a paid random item.
- **Lucky Rain**: in a server with 4+ players, a block falls about every 30 minutes (each match
  finished there brings it 1 minute sooner, never under 15 minutes); a Sky block, or a Rare
  block 1 time in 20; everyone who reaches it within 90 seconds gets one; **3 a day**.
- **The stay bonus**: +1% match money every 2 minutes in the server, up to **+25%** (at 50
  minutes); match money only; it pauses when idle and resets on leaving.

---

## 11. Robux

Robux prices are shown from Roblox's live price (`GetProductInfoAsync`), never typed into the
UI, because Roblox Plus, regional pricing and Roblox's own discounts change what each player
pays. A product whose id is 0 shows "Coming soon" and prompts nothing.

**v4 made everything cheaper** (2026-10-08): the most expensive single item is **1,699 R$** (the
Mythic block and the biggest pack: one $19.99 phone Robux pack), VIP at 399 fits one $4.99
pack (400 R$), and about two-thirds of Robux is bought on phones and consoles.

### 11.1 Money packs (developer products) and the launch bonus

| Key | Name on Roblox | Robux | Money | Bonus | v4 (2026-10-08 morning) | Before v4 |
|---|---|---|---|---|---|---|
| Pack1 | Handful of Cash | 25 | $10,000 | - | $8,000 | 49 R$, $9,000 |
| Pack2 | Stack of Cash | 49 | $21,000 | +7% | $16,500 | 99 R$, $19,500 |
| Pack3 | Bundle of Cash | 99 | $47,500 | +20% | $35,000 | 249 R$, $52,500 |
| Pack4 | Briefcase of Cash | 199 | $110,000 | +38% | $75,000 | 499 R$, $110,000 |
| Pack5 | Vault of Cash | 399 | $250,000 | +57% | $160,000 | 999 R$, $235,000 |
| Pack6 | Bank of Cash | 799 | $600,000 | +88% | $335,000 | 2,499 R$, $625,000 |
| Pack7 | Fortune | 1,699 | $1,500,000 | +121%, **Best value** | $760,000 | 4,999 R$, $1,300,000 |

**Boosted the same day** (designer, 2026-10-08, on the GUI mock page: "spending 1700 robux for
760000 and that's still not enough to buy a legendary lucky block ... money definitely needs a
boost"). The biggest pack now buys one restock Legendary block's money price ($1,490,000), and
the ladder is steeper, so the big packs are the deal. Every block still costs more through money
than its own Robux price (at the best pack: Mystery 1.1x, Grand Opening and restock Rare 1.5x,
Epic 2.3x, Legendary 2.8x, Mythic 3.3x; `python3 tools/economy_model.py value`), and the
model's rarity targets all still hold (`--built-only`: Epic, Legendary, Mythic and Secret
owners move by under half a point, because bought money mostly buys Mystery blocks, a small
share of where cues come from). **"Best value" is Pack7** (`Config.Products.BestValue`). An hour
of Classic play ($7,300) is 8-18 R$ of packs.

**The first-pack double is off** (v4, 2026-10-08; `Config.Shop.FirstPackMultiplier` 1): no top
Roblox game has one, it nudged a kid toward the biggest pack first, and the 29 R$ Starter Pack
now wins the first purchase.

**The launch bonus** replaces the 30% release sale (designer, 2026-10-08;
`Config.Shop.LaunchBonus`). During the Grand Opening's window, **every money pack gives +30%
money**, and **Mystery10 (45 R$) gives 13 Mystery blocks** instead of 10. It is shown as
"Launch bonus +30%" with its real end date and ends on that date; a receipt counts inside the
window plus 10 minutes of grace. It needs no new products. A "30% off" a price nobody was ever
charged would be a fake former price. The six release-sale products are **retired**: never
offered again, kept on Roblox (never deleted) so an old receipt still pays.

### 11.2 VIP (game pass, 399 R$)

399 R$ since v4 (2026-10-08; was 499 in Config and 599 on Roblox until that day's `--sync`).

- **2x money** (+100%, adds with other boosts) on match money only (3.5).
- **No block timers** (designer, 2026-10-07): every block opens at once
  (`Config.LuckyBlocks.VipTimerFactor` 0), and timers already running when VIP arrives finish.
- **A Rare block every day** (v4, designer 2026-10-08), added to the day's login claim; **$5,000**
  where paid random items are restricted (10.5).
- **Skip and Auto Spin** on the ability spin screen (11.8; without VIP they answer "NoVip").
- **+1 free ability spin a day** (added to the day's login claim, 10.1).
- **The VIP restock slot**: a fourth slot every restock, Rare 80% / Epic 17% / Legendary 2.8% /
  Mythic 0.2% (9.1).
- **The VIP Cue** (Exclusive, rainbow, never traded), a **[VIP]** chat tag before the rank tag
  ("[VIP] [GOLD] Name") and a rainbow name over the head (designer, 2026-09-28).
- **No XP, no discount, no extra win-track steps.** Never better block odds.

The pass description on Roblox says the daily block is money where paid random items aren't
allowed (`tools/products_spec.json`).

### 11.3 VIP welcome offer (developer product, 199 R$)

**VIP at half price for 24 hours from a player's first join**, with a real countdown that never
restarts. If they don't buy it, **one "welcome back" window of 24 hours** opens 7 days later,
then never again. It is a developer product that grants VIP in the save (VIP = owns the pass
**or** bought the offer), so only that player sees it. Friendly wording ("Welcome offer"),
never "LAST CHANCE". Managed Pricing is off so "half price" stays true.

### 11.4 Starter Pack (developer product, 29 R$)

Once per player, in the first 7 days after the first join, shown after the first block opening
(v4, 2026-10-08; 29 R$ since that afternoon, was 19, before v4 99): **the Starter Cue**
(Exclusive, the one that trades; `Config.Shop.StarterCue`; back in the pack, designer
2026-10-08), **a Starter lucky block** (Rare or better: Epic 9%, Legendary 0.9%;
`Config.Shop.StarterBlock`), **$25,000** (was $75,000) and **1 hour of 2x money** (adds to VIP:
x3, designer 2026-10-03). Worth about 150 R$ (the block alone about 73 R$ on the value ladder).

**Where PolicyService restricts paid random items it is still sold, with no block: the Starter
Cue, $40,000 and the hour of 2x money** (`Config.Shop.StarterRestrictedMoney`). So the Starter Pack is no longer
a `Random` product in Config (the restricted version has nothing random); it stays Not Listed
on Roblox (13).

### 11.5 Everything Robux buys

**3 game passes and 34 developer products, 6 of them retired** (`Config.Products`; the names,
prices and descriptions are `tools/products_spec.json`, sent to Roblox by
`tools/roblox_products.py`):

| # | Key | Kind | Robux | Before v4 | Gives |
|---|---|---|---|---|---|
| 1 | Vip | Game pass | **399** | 499 | 11.2 |
| 2 | UltSlot2 | Game pass | **49** | 59 | the second ability slot |
| 3 | UltSlot3 | Game pass | **79** | 99 | the third ability slot |
| 4 | VipOffer | Product, once | **199** | 249 | 11.3 |
| 5 | StarterPack | Product, once | **29** | 99 | 11.4 |
| 6-12 | Pack1-Pack7 | Products | **25 / 49 / 99 / 199 / 399 / 799 / 1,699** | 49 ... 4,999 | 11.1 |
| 13 | Mystery1 | Product | **5** | 25 | 1 Mystery block |
| 14 | Mystery10 | Product | **45** | 229 | 10 Mystery blocks (13 during the launch bonus) |
| 15-17 | GrandOpening1, GrandOpening3, GrandOpening10 | Products | **19 / 49 / 149** (57 / 190 one by one) | 49 / 129 / 349 | Grand Opening blocks, only while it runs (9.2) |
| 18 | RestockRare | Product | **15** | 99 (never created) | the restock Rare block, while in stock |
| 19 | RestockEpic | Product | **99** | 999 | the restock Epic block, while in stock |
| 20 | RestockLegendary | Product | **599** | 4,999 | the restock Legendary block, while in stock |
| 21 | RestockMythic | Product | **1,699** | new | the restock Mythic block, while in stock |
| 22-24 | LuckyBlockSkip, LuckyBlockSkip9, LuckyBlockSkip15 | Products | **4 / 9 / 15** | 19 (one product) | finish a block's timer, by time left (9.1) |
| 25 | MoneyParty | Product | **49** | 199 | +100% match money for everyone in the server for 15 minutes, the buyer's name announced; buying again adds 15 minutes (the shop offers it up to an hour queued) |
| 26-29 | Spin1, Spin5, Spin10, Spin50 | Products | **9 / 39 / 75 / 299** | 15 / 50 / 100 / 449 | ability spins (11.8) |
| 30-31 | Lucky1, Lucky3 | Products | **25 / 65** | 49 / 129 | Lucky Spins (11.8) |
| 32-37 | Pack4Sale-Pack7Sale, VipSale, Mystery10Sale | Products | - | 349 ... 3,499 | **retired** (the release sale; `Retired = true`, shown as closed, taken off sale on Roblox, never deleted) |

Plus a **Get Roblox Plus** button (`MarketplaceService:PromptRobloxSubscriptionPurchase`, no
product to create; Roblox pays the game 250 R$ a month for up to 3 months for each subscriber
signed up in the game). Later, with its feature: the **Golden Shot** (15 R$, 10.6).

**Bundle savings are always true**: a bundle's "Was" is the same count bought one at a time
today ("57 R$ one by one"), never a crossed-out former price (v4; `Was` in `Config.Products`).

**The shop is one scrolling page, no tabs** (`Config.Shop.Order`): 1 the Grand Opening block
(while it runs), 2 the Mystery block, 3 the restock shop, 4 the Starter Pack and VIP side by
side, 5 money packs, 6 Money Party, the ability slots and Get Roblox Plus. The timer skip is
offered on the block itself; spins on the Abilities screen. (The client's shop page is being
rebuilt by the GUI session; UI_STYLE section 15 is the reference.)

**Gifts**: a developer product can be bought for another player in the server, except the
restock blocks and the skips (they name the buyer's own restock or block). **A player whose
paid random items are restricted can't gift a random product** (v4).

A Robux receipt that no longer qualifies when it arrives (the VIP offer when already VIP or
after its window plus 10 minutes, a second Starter Pack) pays plain money instead at Pack1's
rate, Robux x 10,000 / 25 (the VIP offer $79,600, the Starter Pack $11,600).

**Setting the prices on Roblox**: `python3 tools/roblox_products.py --sync --dry-run`, then
`--sync`, brings every made pass and product in line with `products_spec.json` (price, name,
description, off sale for a retired one); the plain run creates missing ones and writes their
ids to `tools/products_ids.json` for `Config.Products`. A price change goes live in every server
at once. Done 2026-10-08: RestockRare, RestockMythic and the two new skips made, every price,
name and text synced, the six sale products off sale (none deleted). **By hand, on the Creator
Hub** (the Open Cloud API has no field for it): set every developer product that holds a random
item to **Not Listed**, so it can't be bought outside the game without its odds (13).

### 11.6 Later (not at release)

In this order (plan, 2026-10-02): a season **Cue Pass** (449 / 1,199 R$), more gifts, a Robux
restock refill, a $4.99 a month subscription, rewarded ads paying money. Seasons, the Cue Pass
and event blocks all come after release.

### 11.7 Never sell

**Ruled out** (plan, 2026-10-02): a luck economy (potions, server luck, luck stats), money bets
on matches, offline income, money for idle time, always-on Epic or Legendary blocks, fake
near-misses. Also never: anything that protects rank, in-match aids (longer guidelines, hints,
power or spin upgrades), anything that hurts an opponent, and purchase prompts right after a
loss. (VIP's daily Rare block is the one block VIP gives, the designer's call of 2026-10-08.)

### 11.8 Ability spins

Players see **Ability Spins** on the **Abilities** screen; in code they stay ult spins
(`Config.Ults.Roll`, `Config.Ults.Earn`). **Ability spins are the one luck purchase besides
blocks** (designer, 2026-09-28): normal spins for Robux and money, and **Lucky Spins** (no
Commons) for Robux. They are paid random items: the true odds are always on the spin screen,
pity is kept, and where PolicyService restricts paid random items the R$ and $ buy buttons and
Lucky Spins are refused; free spins still work. The ability bar itself is never bought.

**Odds** (unchanged, shown as %). Each rarity's share is split evenly between its abilities:

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

**Getting spins:** 1 starter spin; 1 free spin a day (never stacks); VIP +1 a day (10.1);
rank-ups (+1 for Bronze, Silver, Gold; +2 Platinum and Diamond; +3 from Expert up); +2 on login
day 7; +1 with the 60-minute playtime gift; codes (RELEASE 3; LIKES10K 3, LIKES100K 5); VIP adds
Skip and Auto Spin.

**Prices** (v4, 2026-10-08: 22-50% lower; "one by one" is the same count at the single price):

| Product | Robux | One by one | Before v4 |
|---|---|---|---|
| 1 spin | 9 | | 15 |
| 5 spins | 39 | 45 | 50 |
| 10 spins | 75 | 90 | 100 |
| 50 spins | 299 | 450 | 449 |
| 1 Lucky Spin | 25 | | 49 |
| 3 Lucky Spins | 65 | 75 | 129 |
| Ability Slot 2 (game pass) | 49 | | 59 |
| Ability Slot 3 (game pass) | 79 | | 99 |

With money: **$12,500 a spin** (was $17,500; buy 1, 5, 10 or 50; no bulk discount): about 1.7
hours of Classic play a spin, so money spins stay a slow trickle and Robux the cheap route.

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

### 11.9 The value ladder, and Robux against money

What one cue of each rarity is worth to the price list (v4 plan 9; `economy_model.py value`; in
dollars at the phone price of Robux, 400 R$ for $4.99):

| | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Ladder | 1 R$ | 3 R$ | 30 R$ ($0.37) | 250 R$ ($3) | 1,500 R$ ($19) | 6,000 R$ ($75) | 50,000 R$ ($624) |
| The designer's feel (2026-10-08) | | | under $1 | "a few dollars" | | "tens of dollars" | "$100 or more" |
| Cheapest pull with Robux (that rarity or better) | | | 16 R$ (Grand Opening) | 127 R$ (Grand Opening), 436 (restock Epic) | 847 R$ (Grand Opening), 1,699 (restock Mythic) | 6,068 R$ (restock Mythic) | 56,633 R$ (restock Mythic) |

Every product against the ladder (worth of what it gives / its price): Mystery block 1.35 (1.75
during the launch bonus), Grand Opening 5.9 (the launch gift), restock Rare / Epic / Legendary /
Mythic 1.07 / 1.20 / 1.45 / 2.40, the Starter Pack's block 3.9 (with the money about 8), the
Golden Shot about 1.7. Nothing sells below its worth on the ladder, and the gamble (Mystery) is
a little better than the known blocks.

**How many times more the money route costs** than buying directly with Robux (money at the
biggest pack's rate): Mystery block 2.2x, Grand Opening block 2.9x, restock Rare 3.0x, restock
Epic 4.5x, restock Legendary 5.6x, restock Mythic 6.6x. **About 2-3x for the everyday blocks,
rising to about 6x for the rarest known blocks** (designer: "about 3x, you set the final ratio",
2026-10-08), like the top Roblox games, whose Robux prices span about 100x while money prices
span millions of times.

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
- Block cues, Unique cues and the Starter Cue trade. Classic, the Ranked cues and every other
  Exclusive cue never (rank, season and VIP cues; designer, 2026-09-28).
- A Unique keeps its number, and a player can hold only one copy of each Unique.
- **Paid origin**: every block and cue copy carries a free or paid origin. Free copies move
  first; a paid copy keeps its paid origin and moves only where **both** players'
  `IsPaidItemTradingAllowed` is true.
- **A paid (unopened) block moves only between two players whose paid random items are not
  restricted** (v4, 2026-10-08; `blocksOk`, sent in the trade payload), so it never reaches a
  player who couldn't have bought it. Free blocks trade as before.
- **A trade pays no finder's money.**

**How a trade runs**
- Invite anyone in the server (an unanswered invite goes away after 30 s), accept or decline,
  both make offers, both accept, then a **3-second wait that any change restarts** on both
  sides. Either can cancel; leaving closes the trade.
- A **warning** when the sides are far apart: one side is worth more than 4 times the other.
  A cue is worth 1 / its copies in existence (fewer than 10 counts as 10,
  `Config.Trade.MinExists`). **A lucky block's worth is worked out live** (v4,
  `Trade.blockWorth`): what its odds row gives on average, each cue worth 1 / its live copies;
  a Mystery block weighs each tier's row by the tier weights. Until the counters load, a
  fallback table from the model at day 30 (`Config.Trade.BlockExists`: Standard 160,000,
  Uncommon 140,000, Rare 73,000, Epic 11,000, Legendary 1,600, Mythic 400, Mystery 120,000,
  Grand Opening 15,000, Starter 19,000, Sky 115,000, Lucky 8 and Gift 73,000). With supply
  growing about 5x between day 30 and day 60, fixed numbers would go stale within weeks.
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

**Alt farming** is held back by the win-track rules (3.6: the loser must have played 5 real
matches, at most 3 steps a day from one account), the first week's match rule (10.1) and the
invite cap (10.4). No trade hold on first-week cues for now (designer, 2026-10-08).

**Retiring cues ("Vaulted")**: the designer can retire block cues; they stop dropping and never
come back (7.4), which keeps old cues worth trading for.

---

## 13. Roblox rules checklist

- **Odds as percentages** before every purchase: every outcome with its % (and "1 in N" beside
  the tiny ones), totals exactly 100, an "Odds & Details" button in words, live updates. The
  Grand Opening shows each player their own odds (9.2). **Pity is stated in numbers**, with the
  live guaranteed tier shown.
- **Paid random items** are: Mystery and Grand Opening blocks (money or Robux), restock blocks,
  the block timer skips, VIP (its daily block and timer perk, and its daily spin), ability
  spins, and later the Golden Shot (`Random = true` in `Config.Products`). Where
  **`PolicyService:ArePaidRandomItemsRestricted`** is true (Roblox names Australia, Belgium,
  the Netherlands, the UK and Brazil for under-18s) they are hidden or refused ("Restricted");
  **VIP's block becomes $5,000 and the Starter Pack becomes $40,000 + the hour of 2x money**.
  Free rewards still work there, and so does the Limited shelf (a known cue at a fixed price).
  A player PolicyService never answers for is treated as restricted for the session.
- **`IsPaidItemTradingAllowed`** false: paid-origin items can't be traded (section 12). An
  unopened paid block can't be traded to, or gifted by, a player whose paid random items are
  restricted.
- **Not Listed** (by hand on the Creator Hub; Open Cloud has no field for it): every developer
  product that holds a random item, so it can't be bought outside the game without its odds.
  Passes are always listed, so VIP's description says the daily block is money where
  restricted, and **VIP is never promoted on Roblox's Buy Robux page**.
- **Discounts must be real**: no fake sales, no restarting countdowns, no "LAST CHANCE, ACT
  NOW" wording. Bundle savings are against the one-by-one price; the launch bonus replaced the
  release sale's "30% off".
- **The reel** (7.2): no slot-machine looks; a gambling look risks a Moderate rating, which
  means no Roblox Kids.
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
| The Mystery block's tier weights, the win track and block odds | section 7 | if the active-player shares drift outside the targets (section 1); with typical retention expect about half the model's shares |
| The Grand Opening window | 30 days | stretch to 45 if few players came; the caps keep the Uniques at 1,000 and 100 either way |
| Restock Legendary and Mythic | 0.95% and 0.05% a slot, no worldwide cap set | if they pile up or never sell (set `GlobalStock`) |
| Copy numbers | #1-100 | if the numbers should last longer: the first 500 of Legendary and up |
| Limited drops | one about every 2 weeks | faster once the art pipeline allows; add copy caps if values fall |
| Seasons | ranks never reset | season rewards for the highest tier reached, once seasons start |

**Watch these numbers** (Roblox analytics and our own events): the share of active players
owning an Epic, Legendary, Mythic and Secret (the targets), D1 and D7 retention, players'
average saved money (rising fast = too much income), how many sell back Epics (high = too many
Epics), Mystery block and restock sales, Starter Pack and money-pack conversion, and trades of
first-week cues between new accounts (alts).

---

## 15. Bots' cues

A bot's equipped cue matches what real players at its rank own (`Config.BotCues`,
`BotCues.pick(tier, roll)`; v4: from the simulation's real players at day 60, Master and up
extrapolated). Each column is the chance the cue is that rarity or better; Common, Uncommon and
Rare are spread by the Mystery block's odds, and the cue is then one block cue of that rarity,
each equally likely.

| Bot tier | Epic+ | Legendary+ | Mythic+ | Before v4 |
|---|---|---|---|---|
| Bronze | 25% | 4.5% | 0.5% | 5% / 0.8% / 0.1% |
| Silver | 80% | 24% | 3% | 10% / 1.5% / 0.2% |
| Gold | 95% | 36% | 4.5% | 20% / 3% / 0.4% |
| Platinum | 98% | 45% | 6% | 34% / 6% / 0.8% |
| Diamond | 99% | 58% | 9% | 50% / 10% / 1.3% |
| Expert | 99% | 75% | 15% | 70% / 16% / 2% |
| Veteran | 99% | 85% | 25% | 88% / 26% / 4% |
| Master | 99% | 92% | 35% | 97% / 40% / 6.5% |
| Grandmaster | 99% | 96% | 50% | 99% / 58% / 11% |
| Reyes | 99% | 98% | 65% | 99% / 70% / 15% |

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

- When the Grand Opening starts (`StartsAt`), set at publish, and whether to stretch its window
  past 30 days.
- The Not Listed setting for random-item developer products on the Creator Hub (11.5).
- When to schedule the next Limited.
- Copy numbers past #100 for Legendary and up, if the launch-month badge feels too short.

---

## 18. The menus and how items are kept

- **The menus** (designer, 2026-09-28): four buttons in one column on the left: **Shop**,
  **Inventory**, **Rewards** and **Trade**. The Shop is one scrolling page with no tabs
  (11.5). The Inventory has two tabs, **Cues** (first) and **Index**; lucky blocks are not in
  it: they live in the hotbar and its bag. Rewards holds the login days (first week or later
  weeks), the 28-day track, playtime gifts, VIP's block, codes and the group, favorite and
  invite cards; everything is claimed there and nothing pops up by itself (designer,
  2026-10-04). Trading is in the first release.
- **How items are saved** (save version 9, 2026-10-08): a count per cue id for block and
  Exclusive cues, with how many of them are paid origin; Unique cues keep their copy number
  (#412) and a paid flag; lucky blocks as a list (`LuckyBlocks.List`, each `{ Id, Kind,
  ReadyAt, Paid }`) plus the tiered skip credits (`SkipCredits`, `SkipCredits1`,
  `SkipCredits2`). **Version 9** adds the day's win-track count and finished matches
  (`Daily.Track`, `Daily.Matches`) and the first week's claimed days (`Login.FirstWeek`); its
  migration starts today's daily counters over for the new 08:00 UTC day and counts a save
  with 7 or more claimed days as having had its first week. (Version 7, 2026-10-04, dropped the
  old cases; version 6, 2026-10-03, was a full wipe.) The default Classic cue is always owned
  and never counted, sold or traded. Saves go through the session-locked, versioned save layer.
- **Opening blocks.** One at a time, in the world: hold the block from its hotbar slot, throw
  it, hold the prompt; the reel, the pull cutscene (Rare and up) and the "YOU GOT" card follow.
  No bulk opening.
- **Index completion.** A cue never owned is a "?" card; tapping it shows its name and its
  black 3D silhouette turning (designer, 2026-09-28). A cue counts once it has ever been owned
  (selling it later keeps it). Completing a rarity row pays once (`Config.Index.Rows`):

| Commons | Uncommons | Rares | Epics |
|---|---|---|---|
| $10,000 | $25,000 | $75,000 | $250,000 |

  Legendary, Mythic and Secret rows have no reward (money there would reward luck more than
  play), nor do the Ranked, Exclusive and Unique rows. The one title left is the first Reyes'.
- **Finder's money**: the first time a cue enters a player's Index it pays once, by rarity
  (`Config.Index.FindMoney`). Selling a cue and finding it again pays nothing, and **a trade
  pays no finder's money**. It is earned money, not boosted by VIP or a party.

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Ranked | Exclusive | Unique |
|---|---|---|---|---|---|---|---|---|---|
| $500 | $1,000 | $2,500 | $7,500 | $25,000 | $100,000 | $500,000 | $5,000 | $5,000 | $10,000 |

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

## 19. Differences from the v4 plan

The approved plan is `docs/prompts/ECONOMY_V4_PLAN.md`. Built differently on purpose (small
calls, each a dated line in DECISIONS.md, 2026-10-08):

- **The Grand Opening runs 30 days, not 21** (the designer's "start at publish, maybe 30-45
  days"; the caps keep the Uniques at 1,000 and 100 either way). The model uses 30.
- **The restock Rare block's stock is 2 a restock** (the plan's table; both money and Robux
  share it).
- **The launch bonus's 13-for-10 applies to the Robux Mystery10 only**; 10 Mystery blocks bought
  with money stay 10 for $44,100.
- **The Starter Pack is not a `Random` product**: where paid random items are restricted it is
  still sold, as $40,000 and the hour, so nothing in it is random there. It stays Not Listed.
- **"Best value" moved to Pack7** (the most money per Robux).
- **A bundle's "Was" is the one-by-one price** today (57 and 190 R$ for the Grand Opening's 3 and
  10; 45 / 90 / 450 for spins; 75 for 3 Lucky Spins), never a former price.
- **No minimum gap between two claims**: a session that crosses 08:00 UTC can claim two days.
- **An unknown policy counts as restricted for VIP's block**: until PolicyService answers, the
  day's VIP reward is $5,000.
- **The save migration treats 7 or more claimed days as a first week done**, so a player who
  already had a week of logins gets the later weeks, not a second first week.

**Kept from earlier plans** (still true): trading has no gate (designer, 2026-10-03); a bot never
shows the Secret cue (lane, 2026-10-03); VIP's daily spin is added to the day's login claim
(lane, 2026-10-03).

**Not built yet** (planned, 10.6): the Lucky Shot and Golden Shot, Lucky Rain, the stay bonus.
