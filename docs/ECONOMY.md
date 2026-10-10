# Economy: money, ranks, lucky blocks, the shop and Robux

The one place that says how the game's economy works and every number in it. Rewritten
2026-10-09 for **economy v5, "every block climbs"**: the plan the designer approved on
2026-10-09 (`docs/prompts/ECONOMY_V5_PLAN.md`, from their answers on the review page, two
follow-ups in chat and a 60-day population simulation), with **v5.1 "Lively"** the same evening
(the Mystery turns into a real block that then climbs; plan section 15) and **v5.2** (2026-10-09:
only the Mystery keeps its upgrade screen; every other block climbs as it opens, shown by the reel,
the same odds; 7.1), on top of economy v4 (2026-10-08,
`docs/prompts/ECONOMY_V4_PLAN.md`), the first economy plan (2026-10-02) and the lucky blocks that
replaced cases (2026-10-04). GDD sections 11 and 12 point here. Every number is a starting value
*(tune)*: it lives in `src/shared/Config.luau` and changes after playtests. Change a number here
and in Config together, then re-run the model.

**The v5 Robux prices are live** (approved and synced 2026-10-09; section 11): restock 39 / 149
/ 599 / 1,699 R$, the 1 R$ timer skip, and since v5.1 the Mystery block **9 R$** and a 5-pack
**39 R$** (v5: 7 and 29). The reasoning is `~/Desktop/8ball-refs/economy/05-economy-v5-robux.md`
and the v5.1 plan page (plan section 15).

```bash
python3 tools/economy_model.py                 # v5.1 at day 7, 30 and 60, against the plan
python3 tools/economy_model.py --built-only    # without the planned features (section 10.6)
python3 tools/economy_model.py --compare       # before v4, v4, v5 built only, v5
python3 tools/economy_model.py --sell          # with finder's money, the Index rows and selling back
python3 tools/economy_model.py --retention typical   # a typical Roblox game's retention
python3 tools/economy_model.py tables          # each block's odds over its climb, money, rank hours
python3 tools/economy_model.py value           # the Robux value ladder; money against Robux
python3 tools/economy_model.py players         # reference players: first session ... day 30
python3 tools/economy_model.py copies          # when each cue's first 100 copies are gone
python3 tools/economy_model.py exists          # copies per cue at day 30 (the trade fallback)
python3 tools/economy_model.py ranks           # a year of players on the rank ladder (slow)
```

The model reads every game number from Config (through `tools/export_economy.luau` and
`tools/economy_config.json`); only how players behave is assumed. Its v5 runs of 2026-10-09 are
in `~/Desktop/8ball-refs/economy/v5-build/`; the v5.1 comparison (`economy_v5_unified.py`,
`unified_final.txt`) is beside them.

**Built for a small launch, ready to grow.** Nothing assumes the game blows up. The ranks, blocks
and rewards work the same with 200 players online as with 20,000; the few things that should
change as the game grows are listed with their triggers in section 14.

**Odds are percentages everywhere**: every block's climb, every cue, the restock slots, ability
spins. Every list adds up to exactly 100%, and tiny values keep enough decimals to stay above
zero. A tiny chance also shows **"1 in N" beside its %** (0.0001%, 1 in 1,000,000; v4, approved
2026-10-08).

---

## 0. At a glance

- **Every block climbs** (economy v5, designer 2026-10-09): **a block's name is its floor** (a
  Rare block always gives Rare or better), and every block climbs from it on **one ladder:
  50 / 35 / 18 / 10 / 15 / 2.5%** (Standard to Uncommon ... Mythic to the Secret). The tier it
  ends on *is* the cue's rarity. The climb is rolled when the block opens and the reel shows it
  (v5.2: a Rare block's reel is Rare 82%, Epic 16.2%...; no climb screen). A Standard block
  reaches Epic or better 1 in 32, Legendary or better 1 in 317 (section 7).
- **The Mystery turns into a real block first** (v5.1 "Lively", designer 2026-10-09): its own
  roll on its 4-press screen, **30 / 25 / 10 / 5%** a step, turns it into a Standard (70%),
  Uncommon (22.5%), Rare (6.75%), Epic (0.7125%) or Legendary (0.0375%) block, the same block
  the restock sells, which then climbs from its name. Both steps together: Epic or better
  **1 in 18**, Legendary or better **1 in 169**, Mythic or better 1 in 1,125, the Secret 1 in
  45,007 (7.4).
- **The Grand Opening Luck**: for the first 30 days, Rare to Epic 27% and Epic to Legendary 15%
  (x1.5), on every climb, never the Mystery's roll. A Mystery then reaches Epic or better 1 in
  12 and Legendary or better 1 in 81. A clover next to the money shows it (7.3).
- **Fewer, better blocks**: a free player who plays an hour a day opens about 5.2 blocks a day
  (v5: 6.7, v4: 14.8), about 3.2 of them Mysteries.
- **One bar: rank XP.** No Levels. XP is never lost and comes only from winning: **100 XP a
  win, 0 a loss** (designer, 2026-10-02). Rank is the main way to show status.
- **Money**: $100 a ball, $500 for a win, $150 for a loss, and from STREAK x3 a small bonus on
  each ball in a row (section 3.1). A Classic match pays the winner about **$1,420** and the
  loser about **$650**: about **$7,750 an hour**. Difficult pays x1.5 and Challenger x2.
- **The daily win track** (v5): wins 1, 4, 7 and 10 of each day give **an Uncommon, a Mystery, a
  Mystery and an Epic block**; wins 2, 3, 5, 6, 8 and 9 give **$1,000**; win 11 and later pay
  money and XP only. The first win ever is a Rare block. **Every daily thing resets at 08:00
  UTC** (section 7.5).
- **Pity, for Mystery blocks only**: Rare by the 10th, **Epic by the 40th**, and a new player's
  bars start at 2/10 and 10/40. Since v5.1 it counts the cue a Mystery finally gives, and a due
  Mystery turns into a Rare (or Epic) block that can still climb (7.4).
- **The first week**: any 7 login days within 14 days of joining, each with a finished match.
  Day 2 a **Rare block**; **day 7 the Week One Cue**, a Legendary cue no block ever drops,
  tradable and sellable (section 10.1).
- **Money buys** Mystery blocks (**$19,900, or 5 for $89,900**; v5: $14,900 and $66,900), the
  **restock shop** (2 slots every 10 minutes, the first always Epic or better, plus VIP's slot),
  the Grand Opening block while it runs ($24,900) and ability spins ($12,500). Timers are
  skipped for Robux only, **1 / 4 / 9 / 15 R$** by time left (1 R$ for 5 minutes or less: every
  Uncommon and Rare block).
- **Robux**: Mystery block **9 R$**, 5 for **39 R$** (v5.1; v5: 7 and 29), restock **39 / 149 /
  599 / 1,699 R$**; the Robux route stays about 2.5 times better value than money (section 11).
- **VIP** (399 R$): 2x money, no timers and an **Uncommon block every day** ($5,000 where paid
  random items are restricted).
- **Robux products**: 3 game passes and 42 developer products on Roblox (9 of them retired), and
  a Get Roblox Plus button (11.5).
- **Trading**: anyone in the server, cues and ready lucky blocks, never money, an atomic swap
  with a ledger (designer, 2026-10-03). A block trades as unclimbed or climbed; its worth is
  worked out live (section 12).
- **No reward popups** (designer, 2026-10-04): every reward is claimed in the Rewards menu.
- **Saves**: version 11 (v5, 2026-10-09) marks every block unclimbed or climbed and keeps skip
  credits by product (section 18).

---

## 1. The designer's targets, and how v5.1 meets them

**The metric** (designer, 2026-10-02): the share of players active in the last 7 days who own
at least one cue of a rarity.

**The aim** (designer, 2026-10-09, answer 15): *"Should feel special, but also at the same time
to each to their own feel rewarding to own, not too common where everyone walks around with one
but not impossible (achievable easier through means of robux obviously, or lots of grinding)."*
Their answers set the shape: a Legendary about once a month for a 1-hour player after the
launch month (answer 1, "Strict"), Mythic and the Secret as goals grinders can reach (answer 2)
and a more generous launch (answer 3, the Grand Opening Luck). v5.1 (2026-10-09 evening) asked
for more upgrades, fewer blocks opened, no tier capped at its name and a little more than v5;
its simulated shares are the targets now.

The model (`python3 tools/economy_model.py`, re-run 2026-10-09 on the numbers in Config; v5's
own run in brackets):

| Rarity | Day 7 | Day 30 | Day 60 | v4 (day 7 / 30 / 60) | Before v4 |
|---|---|---|---|---|---|
| Epic | **60.86%** (58.05) | **69.21%** (66.59) | **66.66%** (64.53) | 18.37 / 32.39 / 42.40% | 2.73 / 5.75 / 10.09% |
| Legendary (from blocks) | **14.83%** (13.57) | **22.24%** (20.69) | **18.65%** (17.49) | 2.29 / 8.10 / 12.92% | 0.43 / 0.84 / 1.90% |
| The Week One Cue | 0.18% | 15.77% | 28.99% | - | - |
| A Legendary or the Week One Cue | 14.91% (13.68) | 29.56% (28.57) | 35.59% (35.11) | | |
| Mythic | **2.57%** (2.38) | **4.80%** (4.72) | **4.58%** (4.36) | 0.30 / 0.95 / 1.74% | 0.06 / 0.14 / 0.23% |
| Secret | **0.10%** (0.08) | **0.17%** (0.14) | **0.16%** (0.13) | 0.03 / 0.11 / 0.18% | 0.02 / 0.01 / 0.02% |

**Slightly more generous than v5 everywhere, as asked.** Without the planned features (section
10.6; `--built-only`): Epic 58.59 / 67.29 / 64.90%, Legendary 14.00 / 20.94 / 17.87%, Mythic
2.37 / 4.64 / 4.35%, Secret 0.08 / 0.13 / 0.13%.

- **Epic** is the good pull most players get every few days.
- **Legendary** is generous in the launch month, then settles at about 1.4 times v4's owners. A
  free 1-hour player climbs to Legendary or better about 2.6 times in the launch month and about
  1.3 times a month after it (v5: 2.5 and 1.1).
- **Mythic** is a grinder's goal (about 4-5% of active players).
- **The Secret** stays the trophy, rarer than v4's by day 60.
- **The shares dip after day 30** because the Grand Opening Luck ends then.

**With finder's money, the Index rows and selling** (`--sell`: every duplicate Common and
Uncommon sold, Rare 90%, Epic 60%, Legendary 40%, Mythic and the Secret 25%, and 3 owners in 10
sell the Week One Cue): Epic 62.08 / 70.58 / 68.02%, Legendary 14.94 / 24.11 / 20.56%, Mythic
2.91 / 5.37 / 5.12%, Secret 0.12 / 0.15 / 0.15%; the Week One Cue is held by 11.03% (day 30) and
20.23% (day 60). Over 60 days that money adds up to 1.7 times all match money (finder's money
86%, the Index rows 18%, sell-back 38%, Week One Cues sold 24%), but it mostly buys Mystery
blocks, a small share of the good copies, so the shares move only 1 to 2 points.

**How sure is this?** The model assumes a very strong game: 1,700 new players on day 0, growing
5.5% a day for 40 days (about 500 peak players online in week 1, about 5,000 by day 45-60), and
about 28% of new players back the next day, more than Roblox's top 1% (22%; the median game
keeps 10.3%, GameAnalytics 2026). With typical retention (`--retention typical`, about 12% next
day): Epic 55.78 / 59.80 / 53.50%, Legendary 11.42 / 15.54 / 10.76%, Mythic 2.01 / 3.02 / 2.30%,
Secret 0.06 / 0.08 / 0.05%, the Week One Cue 0.03 / 5.13 / 10.04% (day 7 / 30 / 60): about
two-thirds of the Legendary and Mythic shares. The plan keeps the strong assumption every past
plan used; watch the real numbers after launch (section 14).

**Where the Epic-and-up copies come from** (day 30, Epic / Legendary / Mythic): the win track
41 / 41 / 42%; login and the 28-day track 15 / 15 / 17%; the group, favorite, invites, codes and
the Gift 13 / 13 / 12%; rank rewards 8 / 8 / 8%; the Grand Opening block 6 / 7 / 4%; Mystery
blocks bought with money 5 / 4 / 5%; the restock with money 4%; Lucky Rain 3-4%; the Lucky and
Golden Shot 2-3%; Mystery blocks bought with Robux 1%. Playtime gives no blocks since v5.1 (its
15-minute Mystery became $2,000). About a third of all Epic-and-up copies come out of Mysteries,
wherever the Mystery came from. No single gift is a leak: almost every Legendary-or-better copy
comes from a climb above the block's promise (v4: 53% of day-30 Legendaries came from two
calendar gifts). **Cues entering the game per day** (average of the week before, day 30): Rare
about 30,800, Epic 10,600, Legendary 1,600, Mythic 261, Secret 8 (v5: Rare 30,300, Epic 10,000,
Legendary 1,470, Mythic 256, Secret 7; v4: Rare 31,800, Epic 2,800, Legendary 410, Mythic 47,
Secret 4).

**What a player gets** (`players`: 1,000 identical players each, 50% win rate, every day from
launch, so the launch luck is on for the whole month; free players spend 70% of their money on
Mystery blocks and spins):

| Player | Own one at day 7 (Epic / Legendary / Mythic / Secret) | Day 30 | Money earned by day 30 |
|---|---|---|---|
| Free, 30 min a day | 91% / 30% / 6.2% / 0.2% | 100% / 77% / 23% / 0.8% | $727,000 |
| Free, 1 h a day | 98% / 40% / 10% / 0.1% | 100% / 88% / 34% / 0.7% | $1,268,000 |
| Free, 3 h a day | 100% / 78% / 21% / 0.7% | 100% / 100% / 74% / 2.5% | $2,339,000 |
| VIP, 1 h a day | 99% / 48% / 10% / 0.0% | 100% / 95% / 39% / 0.4% | $1,562,000 |
| Small spender: VIP, 1 h, 500 R$ a month | 99.4% / 51% / 11% / 0.1% | 100% / 94% / 41% / 1.1% | $1,746,000 |
| Big spender: VIP, 3 h, 5,000 R$ a month | 100% / 96% / 41% / 1.2% | 100% / 100% / 91% / 6.6% | $4,998,000 |

These players never skip a day; most real players do, which is why the whole-game shares above
are far lower. Money earned roughly doubles against v4 ($571,000 for the 1-hour player): the
playtime gifts and the win track's money steps replaced blocks with money. (v5.1 run; the
Secret column moves a few tenths between runs, about 1 owner in 1,000 players.)

**Other targets (still true):**

| Target (designer) | How it is met |
|---|---|
| A guaranteed better block early (2026-10-08) | the first win ever is a Rare block, win 1 of every day an Uncommon block, the first week's day 2 a Rare block |
| Legendary and Mythic stay reachable (2026-10-08, 2026-10-09) | every block can climb to the Secret; Legendary to Mythic is 15% |
| Lots of duplicates of Commons to Rares | about 70% of a free player's blocks end Common or Uncommon |
| Block cues keep their value | no direct buying (section 9); new cues each season and old ones retired (section 6); copy caps on the Grand Opening's Uniques |
| (2026-10-02) 1 win to Bronze I, 2 to Bronze II, 3 to Bronze III... | divisions in wins of 100 XP (section 4.2) |
| (2026-10-02) 3 h a day at 50%: Expert 1 month, Veteran 2, Master 3-4, Grandmaster 6, Reyes 7+ | the ramp from Diamond (section 4.2) |
| (2026-10-02) XP strictly from skill | wins only; harder modes, streaks and stronger opponents pay more |
| Losing is never a punishment (2026-09-28) | a loss gives 0 XP, never negative, and $150 |
| VIP 2x money, not overpowered | 2x money, no timers and one Uncommon block a day; never better odds, never XP |
| Most expensive item about a phone Robux pack (2026-10-08) | 1,699 R$ (one $19.99 pack of 1,700 R$) |

---

## 2. The first hour (onboarding)

What a new player gets, in order, at an ordinary 50% win rate (all claimed in the Rewards menu,
except the tutorial's blocks):

| When | What happens |
|---|---|
| Join | 1 starter ability spin (the tutorial, 2026-10-03). |
| The first win (the tutorial) | Unranked to **Bronze I**: an **Uncommon lucky block at once**, which skips its climb and opens to an Uncommon cue (`Config.Tutorial.BronzeBlockKind`; v5 Claude's call, since a v5 Standard block gives only Commons), then $2,500, a Mystery block, the Bronze Cue, the [BRONZE] tag and +1 ability spin once claimed in Rank. The win's own step is step 1 of the day's win track: the first win ever is always a **Rare block**, which waits its 5-minute timer and climbs as it opens (v5.2). |
| The first finished match | first-week day 1 can be claimed: **$5,000 + a Mystery block** (a login day counts once a match is finished that day). |
| 5 minutes | playtime gift: $1,000 |
| The second and third wins | $1,000 each (win track steps 2 and 3); the third win is **Bronze II**: $1,000 |
| 15 minutes | playtime gift: **$2,000** (v5.1; v5: a Mystery block) |
| The fourth win | a Mystery block (step 4) |
| 30 and 45 minutes | playtime gifts: $2,500 and $3,500 |
| 60 minutes | playtime gift: **$5,000 + 1 ability spin** |

Every new cue also pays finder's money the first time (section 18). The model's first 20
minutes (the tutorial, then the group, the favorite and the launch codes): about **6 Mystery
blocks, an Uncommon block** (ROOFTOP), the first win's Rare block and the Lucky 8 block, about
**$31,000** earned, and during the launch luck about **55% already own an Epic** and 1 in 10 a
Legendary. **Login day 2 is a Rare block.** Silver comes after about 6 hours of play (21 wins).
The Starter Pack offer appears after the first block opening (section 11.4).

---

## 3. Money

Money is earned by playing and spent in the shop. It **never trades** between players.
Unchanged by v4 and v5, except the win track's $1,000 steps (7.5), which are rewards.

### 3.1 One match (1v1 against a person, Classic)

| What | Money | Notes |
|---|---|---|
| Each ball that counts for you | **$100** | your group, legal open-table pots, the break's balls, the 8 when it wins |
| Nice shot on top | **bank or kick +$150, combo or carom +$200** | to the shooter only |
| Win | **+$500** | only after a real match (past the one-minute mark, not a quick forfeit) |
| Loss | **+$150** | money even when you lose; the leaver gets nothing |
| Ball streak on top | **+$25 a ball at STREAK x3, +$50 at x4, ... +$150 at x8** | to the shooter only; a quarter of the ball pay for each level from x3 (`Config.Economy.BallStreak*`) |
| Win streak | **+$250** on each win from the 3rd in a row | against people only |

**The ball streak** (designer, 2026-10-09): the balls a team pots in a row in its turn show as
"STREAK x1" up to x8 (the GDD section 8). It is a bonus on top of the ball pay, never a
multiplier: from x3 each counted ball pays an extra quarter of the ball pay for each level from
x3, so x3 +$25, x4 +$50, x5 +$75, x6 +$100, x7 +$125, x8 +$150 (a run-out of all eight balls
pays $525 on top of its $800), and x9, the most outside Solo (one ball on the break, then the
seven and the 8), +$175. The break counts as x1 however many balls drop; a foul, a shot
that pots none of yours or the table passing ends it. It is boosted like other match money
(VIP, difficulty), pays the shooter only, and pays nothing in Solo or at a flat after-cap pay.
Measured in 1,600 bot-duel games (`tools/streak_model.luau`): about 52% of paying balls are x1,
24% x2, 12% x3, 6% x4, 3% x5 and under 2% x6 to x8, so an average paying ball earns about $11
more: **about +6% an hour**.

Average match: winner about **$1,420**, loser about **$650**. At 7.5 matches an hour that is
**about $7,750 an hour** (the plan's $7,300 of 2026-10-02, kept by v4, plus the ball streak's
6% since 2026-10-09).

### 3.2 By opponent

| | Against people | Play against PC (on purpose) | Disguised bot (queue fallback, tutorial, lobby bots) | Solo |
|---|---|---|---|---|
| Each ball | $100 | $100 | $100 | **$30** until $3,000 of solo money in a day, then **$10** |
| Nice shot on top | bank/kick +$150, combo/carom +$200 | same | same | none |
| Ball streak on top (x3 on) | +$25 to +$150 | same | same | none |
| Win / loss bonus | $500 / $150 | **$250 / $80** | $500 / $150 | none |
| Win streak (3rd win in a row on) | +$250 | none | none | none |
| Daily limit | the same-opponent rules (3.6) | after **$10,000** of PC money in a day, everything pays half | after **20 disguised wins** in a day they pay the PC rows and move no win-track step (hidden) | as above |
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
same as 1v1. The nice-shot and ball streak bonuses go only to the shooter (the team carries
one streak across its rotating shooters). The win and loss bonus, the win
track's step (each winner) and XP are per player, by the same rules; XP uses the opposing
team's average rank for the gap (section 4.4).

### 3.4 Difficulty

The difficulty money multiplier is **on** (designer, 2026-09-26; switched on 2026-10-03 now that
the rank lock exists from Gold I). It is separate from the XP mode multiplier (1.25 / 1.5).

| | Classic | Difficult | Challenger |
|---|---|---|---|
| Money | x1 | **x1.5** | **x2** |
| Match length (assumed) | 6.5 min | 7.5 min | 8.5 min |
| Money an hour | about $7,750 | about $10,300 | about $12,400 |

### 3.5 Boosts and how they stack

Boosts **add**, then difficulty multiplies (plan, 2026-10-02):

money = base x difficulty x (1 + VIP 1.0 + Money Party 1.0 + Starter hour 1.0 + group 0.1 + Roblox Plus 0.1)

- Only **match money** is boosted (balls, nice shots, match bonuses). Never rewards (the win track's
  $1,000 steps too), finder's money, sell-back or packs.
- The Starter Pack's hour of 2x adds to VIP's: x3 for that hour (designer, 2026-10-03).
- The group's +10% is on while the player is a member of the game's group (section 10.4).
- No boost ever changes block odds or how many blocks a player gets. VIP's block timers (none)
  and daily Uncommon block (11.2) are its perks outside money.

### 3.6 Anti-farming (alts and friends)

- **Same opponent, same day:** matches 1-5 pay in full; 6-10 pay half the XP and half the
  win/loss bonus and move no win-track step; from the 11th, no XP, a quarter of the bonus, half
  the ball pay, no step. At most **3 win-track steps a day from beating the same account**
  (`Config.Economy.DropsPerOpponent`).
- **The loser must have played 5 real matches** for the winner's step (a fresh alt can't feed
  blocks; `Config.Economy.DropLoserMinMatches`).
- **A login day counts only after a finished match that day** (v4), so an alt can't collect the
  first week's Rare block and the Week One Cue by just joining (section 10.1).
- **Short matches:** pots are still paid live, but money from matches that end before the
  one-minute mark counts toward a **$2,000 a day** short-match limit; past it, balls before the
  one-minute mark pay **$10** each (and no nice-shot or ball streak bonus).
- Forfeits, leavers and the one-minute mark stay as built (GDD section 13).
- Private servers, when they come: no XP, no blocks, solo-rate money.
- With no trade gate (section 12), these rules and the invite cap are the alt protection. The
  designer chose not to hold first-week cues from trading (2026-10-08: the match rule is enough
  for now; watch the trades; and for the Week One Cue, 2026-10-09: "all of that will be worried
  about IF this game does good").

### 3.7 How money is shown

Full digits up to **$999,999**, then short: **$1.2M** (`Format.money`). The currency is always
called "money".

---

## 4. Ranks (XP)

Unchanged by v4 except the rank rewards (4.8). v5 keeps the rewards' blocks, which now climb
from their names (7.1).

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
| Bronze (1) | $1,000 | $2,500, a Mystery block (plus the Uncommon block given at once with the first win; v4: a Standard block) | same |
| Silver (21) | $2,000 | $5,000, a Rare block | same |
| Gold (66) | $3,500 | $10,000, 2 Rare blocks | same |
| Platinum (136) | $6,000 | $20,000, **an Epic block** | 3 Rare blocks |
| Diamond (232) | $15,000 | $50,000, **2 Epic blocks** | an Epic block |
| Expert (393) | $30,000 | $100,000, **a Legendary block** | 2 Epic blocks |
| Veteran (675) | $50,000 | $200,000, **a Legendary block and an Epic block** | 3 Epic blocks |
| Master (1,180) | $80,000 | $400,000, **2 Legendary blocks** | a Legendary block |
| Grandmaster (2,025) | $150,000 | $750,000, **a Mythic block** | 2 Legendary blocks |
| Reyes (3,075) | - | $2,000,000, **2 Mythic blocks**, the rainbow tag | a Mythic block |

Blocks from rank rewards arrive unclimbed and climb from their names (7.1): Expert's Legendary
block is a guaranteed Legendary, Grandmaster's Mythic block a guaranteed Mythic. Only Bronze's
Uncommon block is given at once (the tutorial opens it without a climb); every other reward
waits in Rank until claimed (designer, 2026-10-03). A Reyes Cue proves Reyes: it can't be traded. Rank rewards stay
a small source (about 7% of Epic-and-up copies at day 30) because few players climb that far.

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
| Block rarities | Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret | lucky blocks (and trades) only; the Week One Cue from the first week's day 7 (10.1) | yes | yes |
| **Unique** | numbered cues (only two: the Firework Cue, 1,000 copies ever, and the Beta Cue, 100 ever, both from the Grand Opening block; there is no Founder's Cue, ever) | the Grand Opening block's two Unique rows (9.2), or the Limited shelf for a set time | yes | no |
| **Ranked** | the ten rank cues (Bronze Cue ... Reyes Cue): one rarity since 2026-10-08 (designer), each card in its tier's colours; their group stays Exclusive | reaching each tier, once | **never** | no |
| **Exclusive** | the VIP Cue, the Starter Cue, later season cues | one special way each | **never**, except the Starter Cue (designer: VIP never, 2026-09-28; the Starter Cue trades, 2026-09-29) | no |

What rarity looks like (GDD section 12, UI_STYLE section 4 colours): Common and Uncommon keep
the plain wisp trail (Uncommon tinted); Rare adds a coloured trail and small pocket burst; Epic
has its own trail and pocket effect; Legendary an animated trail, pocket effect and sound;
Mythic the celestial shimmer and its own VFX; Secret a one-of-a-kind full set.

**Launch catalog: 46 block cues in the blocks**: 7 Common, 9 Uncommon, 10 Rare, 9 Epic, 7
Legendary, 3 Mythic, 1 Secret, **plus the Week One Cue** (v5): a Legendary block cue that no
block drops, given on the first week's day 7 (10.1). Classic is labelled Common too but is the free default: everyone owns it,
no block drops it, and it is never traded or sold. Plus 10 Ranked (the rank cues), 2 Exclusive
(VIP, Starter) and 2 Unique (Firework and Beta, both from the Grand Opening block). The list
and order are `Progression/Catalog.luau`; each cue's look is its skin (`src/shared/CueSkins`).

Adding cues later keeps each rarity's % per block; each cue's own share shrinks. **Keeping value
as the game grows** (designer, 2026-10-09, answer 4): add new cues each season and retire old
ones from blocks (`Vaulted`); **never lower printed odds**. Retired cues get rarer by
themselves. If the launch is small the ladder can be raised later (a buff is always welcome);
if a number must ever go down, it is announced a week ahead with numbers and new cues (plan
7.6).

**Copy numbers** (GUI session, approved 2026-10-08): the first 100 copies of every Rare-or-rarer
cue are numbered #1-100. Under v5 (`economy_model.py copies`, re-run 2026-10-09,
nothing changed) each cue's #100 is gone by about day 1 (Rare and Epic), day 4 (Legendary), day
7 (Mythic) and day 29 (the Secret), and the Week One Cue's by day 9 (v4: day 1, 4, 11, 22 and
35), so "#12/100" is a launch-week badge for Legendary and Mythic. The designer kept #1-100
(2026-10-08); numbering more is theirs to decide (section 17).

---

## 7. Lucky blocks

A block waits in the hotbar (and its bag), is held, thrown into the world and opened there with
a hold prompt; the reel plays (`BlockReel`), a Rare or better cue plays its pull cutscene, then
the "YOU GOT" card (designer, 2026-10-04: lucky blocks replaced cases). **Since v5 every block
climbs first** (designer, 2026-10-09). The ladder is `Config.BlockOdds.Climb`
(`Progression/BlockDrop.luau`), each kind's start `Config.LuckyBlocks.Kinds[kind].Climb`, and a
climbed block's row `Config.BlockOdds.List` (`Progression/BlockOdds.luau`).

### 7.1 How a block works

- **A block's name is its floor.** A Rare block always gives Rare or better.
- **Every block climbs**, one step at a time, on one ladder (7.2). The tier it ends on is the
  cue's rarity; then one cue of that rarity, every cue equally likely.
- **Where each kind starts**: the Sky block (Lucky Rain) from Standard; Lucky 8 and the Gift
  from Uncommon; each tier block from its own tier. **The Mystery turns into one of those tier
  blocks first** (v5.1, 7.4), which then climbs from its name. **The Grand Opening and Starter
  blocks keep their approved odds and never climb** (7.2). Rank rewards keep their blocks, which
  follow these rules (Expert's Legendary block is a guaranteed Legendary).
- **The climb happens at the open, shown by the reel** (v5.2, designer 2026-10-09: "only
  mystery lucky block is supposed to have upgrade chances"). A block waits **its own name's
  timer** (7.6), is held, thrown and opened like any block, and the server rolls its climb then
  (`BlockDrop.climbFor`, with the launch luck; `PlayerData.planLuckyOpen`). The reel's strip is
  that climb's odds: a Rare block's shows Rare cards at 8.2% each and Epic cards at 1.8% each
  (Rare 82%, Epic 16.2%, Legendary 1.53%, Mythic 0.26%, the Secret 1 in 14,815), so the odds did
  not change, only how they are shown. A Common or Uncommon cue opens with the quick reveal.
- **Only the Mystery has an upgrade screen** (like Brawl Stars' Starr Drop): its slot says
  **OPEN!** and wears the climb mark, and a tap opens its **4 presses** (`Drop.Upgrade.Clicks`;
  designer: "just 4"), which are its roll (7.4). The server rolls first; the presses only reveal
  it. They end on the block it turns into, which jumps back to the hotbar on that block's timer
  and then opens like any other. The first press shows Standard, or higher when the 3 later
  presses couldn't reach the result otherwise (`BlockDrop.startOf`); each later press climbs one
  tier or doesn't, every choice equally likely (`BlockDrop.path`). It never falls back.
- v5 (before v5.2) gave every block that climb screen; a block that climbed there is a
  **climbed** block (its tier kept, `Climbed`) and opens from exactly its tier's cues. None are
  made any more.
- **The Secret**: a climb that reaches it gives the Secret cue with the full show (the reel,
  then its pull). There is no Secret block (no model, no timer).
- **Honest by construction**: the shown odds are the real odds. The Mystery's screen never
  shows a fake near-miss or a "chance per press" (it isn't a fixed number).

**The client** (checked in Studio 2026-10-09, v5.2): a Rare block is held from its slot (no
OPEN!), thrown and opened into a reel titled "Rare Lucky Block" mixing Rare and Epic cards;
only the Mystery's slot says OPEN! and opens the upgrade screen (`MysteryReveal`).

### 7.2 The ladder, and what each block gives

| Step | Chance | During the Grand Opening Luck (7.3) | Config (parts of 1,000,000) |
|---|---|---|---|
| Standard to Uncommon | 50% | 50% | 500,000 |
| Uncommon to Rare | 35% | 35% | 350,000 |
| Rare to Epic | 18% | **27%** | 180,000 (270,000) |
| Epic to Legendary | 10% | **15%** | 100,000 (150,000) |
| Legendary to Mythic | 15% | 15% | 150,000 |
| Mythic to Secret | 2.5% | 2.5% | 25,000 |

The cue's rarity from each block over its whole climb, in percent (each row adds to 100;
`BlockDrop`, the `tables` run):

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Standard, Sky | 50 | 32.5 | 14.35 | 2.835 | 0.26775 | 0.0460688 | 0.00118125 |
| Uncommon, Lucky 8, Gift | - | 65 | 28.7 | 5.67 | 0.5355 | 0.0921375 | 0.0023625 |
| Rare | - | - | 82 | 16.2 | 1.53 | 0.26325 | 0.00675 |
| Epic | - | - | - | 90 | 8.5 | 1.4625 | 0.0375 |
| Legendary | - | - | - | - | 85 | 14.625 | 0.375 |
| Mythic | - | - | - | - | - | 97.5 | 2.5 |
| **Mystery** (v5.1: its roll, then that block's climb; 7.4) | 35 | 37.375 | 22.0375 | 4.995 | 0.503625 | 0.0866531 | 0.0022219 |

The same as "or better":

| Block | Epic or better | Legendary or better | Mythic or better | Secret |
|---|---|---|---|---|
| **Mystery** (v5.1) | 5.5875% (1 in 18) | 0.5925% (1 in 169) | 0.088875% (1 in 1,125) | 1 in 45,007 |
| Standard (v5's Mystery) | 3.15% (1 in 32) | 0.315% (1 in 317) | 0.04725% (1 in 2,116) | 1 in 84,656 |
| Uncommon | 6.3% (1 in 16) | 0.63% (1 in 159) | 0.0945% (1 in 1,058) | 1 in 42,328 |
| Rare | 18% (1 in 5.6) | 1.8% (1 in 56) | 0.27% (1 in 370) | 1 in 14,815 |
| Epic | 100% | 10% (1 in 10) | 1.5% (1 in 67) | 1 in 2,667 |
| Legendary | 100% | 100% | 15% (1 in 6.7) | 1 in 267 |
| Mythic | 100% | 100% | 100% | 2.5% (1 in 40) |

The kinds:

| Block | Climbs from | Comes from |
|---|---|---|
| Mystery | turns into a Standard to Legendary block first, with pity (7.4) | the win track, the shop, rewards |
| Standard, Uncommon, Rare, Epic, Legendary, Mythic | its own tier | the win track, rewards, rank rewards, the restock |
| Sky | Standard | Lucky Rain (planned, 10.6) |
| Lucky 8 | Uncommon | the favorite reward (10.4) |
| Gift | Uncommon, after a 12-hour wait from the leave | once, the first time a player leaves the game; it falls from the sky on their next visit |
| Grand Opening | never climbs: Rare 81.84%, Epic 10%, Legendary 1.6% (1 in 63), Mythic 0.15% (1 in 667), Secret 0.01% (1 in 10,000), **the Firework Cue 6%, the Beta Cue 0.4%** (1 in 250), capped and per player (9.2); opens at once | the shop, while it runs (9.2) |
| Starter | never climbs: Rare 90%, Epic 9%, Legendary 0.9% (1 in 111), Mythic 0.09% (1 in 1,111), Secret 0.01% (1 in 10,000); opens at once | the Starter Pack (11.4) |

- **No block is sold permanently** except through the shop's Mystery deal (plan, 2026-10-02):
  blocks come from wins, rewards, the shop's Mystery and Grand Opening deals and the restock
  shop. Mythic blocks are sold in the restock only (v4).
- Blocks live in the hotbar and its bag (`Config.LuckyBlocks.MaxBlocks`), never in the
  Inventory menu.
- A block can be **traded** once it is ready, once its timer is done (section 12).

**The spin reel** (designer, 2026-10-08: rare cues pass by more often, with safeguards; the
reel's look is the GUI session's): every reel shows only cues from that block's own pool, so a
climbed block's reel shows the cues of its one rarity; where the pool holds Epic or better, each
spin gets **one showcase tile** from it in the first two-thirds of the strip, never within 8
tiles of where it stops, printing its own odds; every other tile is drawn at the real odds; the
reel never slows near a rare tile; under it: "The reel shows what this block can drop. Your
chances are under Odds." No slot-machine looks (lever, 7s, "JACKPOT"). If Roblox ever rules
against the showcase tile, it turns off and the rest stays.

### 7.3 The Grand Opening Luck (the first 30 days)

The designer's answer 3 (2026-10-09): x1.5 on Rare to Epic and Epic to Legendary for 30 days.

- It runs **30 days from the Grand Opening's `StartsAt`** (`Config.BlockOdds.Climb.Luck`), on its
  own clock: changing the Grand Opening's length never changes it, and `StartsAt` 0 means off.
- Only the two middle steps are boosted (Rare to Epic 27%, Epic to Legendary 15%); Mythic and the
  Secret still come about 2.25 times as often while it runs, because more blocks reach
  Legendary.

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Standard, Sky | 50 | 32.5 | 12.775 | 4.01625 | 0.6024375 | 0.1036547 | 0.0026578 |
| Uncommon, Lucky 8, Gift | - | 65 | 25.55 | 8.0325 | 1.204875 | 0.2073094 | 0.0053156 |
| Rare | - | - | 73 | 22.95 | 3.4425 | 0.5923125 | 0.0151875 |
| Epic | - | - | - | 85 | 12.75 | 2.19375 | 0.05625 |
| Legendary | - | - | - | - | 85 | 14.625 | 0.375 |
| Mythic | - | - | - | - | - | 97.5 | 2.5 |

- A Mystery (v5.1; the luck lifts its block's climb, never its roll): Common 35%, Uncommon
  37.375%, Rare 19.61875%, Epic 6.7734375%, Legendary 1.0478906%, Mythic 0.1802988%, the Secret
  0.004623%: Epic or better 8.00625% (1 in 12), Legendary or better 1.232812% (1 in 81), Mythic
  or better 1 in 541, the Secret 1 in 21,631 (v5's Mystery: 1 in 21, 141, 941 and 37,625).
- It is free, the same for everyone, dated and shown with a countdown. Every odds screen shows
  the boosted odds while it runs (Roblox requires live odds). When it ends, the event ends;
  nobody's odds get cut. A climb uses the luck live at the moment the server rolls it.
- **The clover** (the designer's note): a clover icon next to the money and VIP bars, bottom
  left, only while the luck runs. A tap opens a small popup: "Extra luck for the release!", the
  countdown and the two boosted steps (Rare to Epic 18% to 27%, Epic to Legendary 10% to 15%).
  It is the GUI session's; the odds screens already read the live luck.

### 7.4 The Mystery: its roll and pity

**The roll** (economy v5.1 "Lively", designer 2026-10-09; `Config.BlockOdds.Turn`,
`BlockDrop.turnRoll`): v5 made a Mystery's climb final, so a Mystery that stopped on Rare could
never go higher. Since v5.1 a Mystery **turns into a real lucky block** first, the same block
the restock, the win track and the rewards give, and that block then climbs from its name like
any other.

- On the Mystery's screen (4 presses, the dots) each step up is one chance: Standard to Uncommon
  **30%**, Uncommon to Rare **25%**, Rare to Epic **10%**, Epic to Legendary **5%**; it stops at
  the first miss and never goes past Legendary (`Turn.Top`). It turns into a **Standard block
  70%**, Uncommon 22.5%, Rare 6.75%, Epic 0.7125% (1 in 140) or Legendary 0.0375% (1 in 2,667).
- The block it becomes keeps the Mystery's slot and origin (a Robux one opens at once), waits
  **that block's timer** (7.6) and climbs as it opens, with that block's own odds shown by the
  reel (7.2, v5.2). Every block can still reach the Secret, a Standard one too.
- The Grand Opening Luck boosts the climb, never the roll.
- The shop's Mystery card lists the five blocks it turns into; each row's dice opens that
  block's normal odds. Its Odds & Details shows the roll, what it ends with over both steps,
  pity and each cue's chance over both steps.
- Worth: about 1.7 times v5's Mystery, which is why the price rose to $19,900 / 9 R$ and the
  15-minute playtime Mystery became $2,000 (9.1, 10.3). Its value per Robux (3.83) stays inside
  the restock's range (2.75 to 4.18).

**Pity**:

- For Mystery blocks only, bought ones too. **Rare by the 10th** Mystery in a row without a
  Rare-or-better cue; **Epic by the 40th** without an Epic-or-better (`Drop.PityRare`,
  `PityEpic`; v4: the 100th). Pity is checked at the roll: a due Mystery turns into a **Rare
  (or Epic) block**, which can still climb. Pity never gives a Legendary block.
- **It counts the cue the Mystery finally gives** (v5.1), after its block's climb. A roll that
  lands on a Rare-or-better block resets that counter at once (the block promises it), so two
  Mysteries rolled while pity is due are never both lifted. The counters a roll can't settle yet
  ride on the block as a hidden mark (`Block.Pity`) and count when it climbs; a block still held
  counts once it is opened, so pity can come late but is never lost. Counting the block instead
  would hand out a Rare block almost every 10th Mystery (about 20% more Legendaries).
- **The head start**: a new save starts the counters at 2 (Rare) and 10 (Epic)
  (`Drop.PityStart`), so the bars show 2/10 and 10/40 on the first day and the first Epic is
  guaranteed by the 30th Mystery block. Old saves keep their counters (the save's
  `Drops.SinceRare` and `SinceEpic`).
- **Shown as bars with the number** ("Epic guaranteed in 23") **in Odds & Details and on the
  shop's Mystery card only**, never on the climb screen (designer, 2026-10-09: it stays clean);
  the card's bars update as soon as a Mystery rolls or its block climbs. When pity is due, the
  odds screen shows the block it turns into (as v4).
- How often it fires (plan 3.6, v5's numbers; v5.1's better roll makes it fire a little less):
  among players who open that many Mystery blocks, about 4 in 10 get their first Epic from pity
  at block 30 (1 in 4 during the launch); after that about 3 in 10 each time (1 in 7 during the
  launch). The Rare pity fires for about 1 player in 4 the first time.

### 7.5 The daily win track

Each real win (one that passes the anti-farm rules, 3.2 and 3.6) moves the day's **win track**
one step and gives that step's block or money (v5, 2026-10-09; `Config.BlockOdds.Drop.WinTrack`):

| Win of the day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| v5 | **Uncommon** | $1,000 | $1,000 | Mystery | $1,000 | $1,000 | Mystery | $1,000 | $1,000 | **Epic** | money and XP only |
| v4 | Rare | Mystery | Mystery | Uncommon | Mystery | Mystery | Rare | Mystery | Mystery | Epic | |

- **Fewer, better blocks** (the designer's answer 6: four wins give a block). The $1,000 steps
  (`Drop.WinTrackMoney`) are rewards: earned, never boosted.
- **The first win ever is a Rare block** (`Drop.FirstWin`); it stands in for win 1 of day 1.
- **Win 10 is an Epic block** (answer 7): a real daily goal (about 20 matches, nearly 3 hours).
  It makes grinders strong: a free 3-hour player climbs to Legendary or better about 4 times a
  month after the launch, and about half own a Mythic by day 30. That fits "lots of grinding";
  if Legendaries feel too common among grinders, making win 10 a Rare block is the lever (plan
  2.15).
- The steps follow the anti-farm rules exactly: a win moves the track only when it would have
  given a block before v4. So the first 10 PC wins a day count, disguised-bot wins up to 20 a
  day, at most 3 steps a day from beating the same account, the loser must have played 5 real
  matches, and solo never counts. **VIP gets no extra steps** (VIP's perk is a daily block,
  10.5).
- **The day starts at 08:00 UTC for every daily thing** (`Config.Daily.ResetHour`): the win
  track, the login day, playtime, VIP's block and the anti-farm "same day" limits. 00:00 UTC
  was 8 pm in New York, the middle of US evening play; 08:00 UTC is 3-4 am in New York, 5 am in
  Brazil, 8-10 am in Europe (Brawl Stars resets at 08:00 UTC too). There is no minimum gap
  between two claims: a session that crosses 08:00 UTC can claim two days.
- **The payload**: a win's block rides `MatchSummary.block = { kind, readyAt }` (already in the
  hotbar when it arrives); a money step is paid at once and, until the win track bar shows money
  tiles, folded into the result screen's bonus line. `RewardView` sends the day's track
  (`wins = { given, kinds }`, a money step's kind "Money") for the bar above the hotbar ("Lucky
  Blocks today 7/10"). The server decides everything before any reel starts; the reel only
  shows it.
- A free player who plays every day and wins half their matches opens about 3.5 blocks a day at
  30 minutes, 5.2 at 1 hour and 9.4 at 3 hours, about 70% of them ending Common or Uncommon
  (v5.1; v5: 4.8, 6.7 and 11.7; v4: about 15 a day at 1 hour).

### 7.6 Timers, the skip, the quick reveal and "Open all"

**Every block waits its own name's timer** (v5.2; `Config.LuckyBlocks.Kinds[kind].Timer`):
Standard at once, Uncommon 1 minute, Rare 5 minutes, Epic 30 minutes, Legendary 6 hours, Mythic
12 hours, whatever it climbs to when it opens (v5: the tier it climbed to). The Mystery, Sky,
Lucky 8, Grand Opening and Starter blocks have none (the Gift: its 12-hour comeback wait); a
block a Mystery turned into waits that block's timer from the turn.

- Timers start by themselves when the block lands in its slot. They all run at once;
  there are no slots. Opening a block before its timer is done answers "Not ready yet"; the
  hotbar slot counts down. A bought block (paid origin) opens at once.
- **VIP has no timers**: every block opens at once (`Config.LuckyBlocks.VipTimerFactor` 0,
  designer 2026-10-07).

**The timer skip, by time left** (`Config.LuckyBlocks.Skips`): a timer is finished with Robux
only, never money, and the skip button shows the price for the time left right now:

| Time left on the block's timer | Product | Robux | v4 |
|---|---|---|---|
| 5 minutes or less (every Uncommon and Rare block) | LuckyBlockSkip1 (3717460488, made 2026-10-09) | **1** | 4 |
| 30 minutes or less (an Epic block) | LuckyBlockSkip (3716368528) | **4** | 4 |
| 6 hours or less (a Legendary block) | LuckyBlockSkip9 | **9** | 9 |
| more (a Mythic block) | LuckyBlockSkip15 | **15** | 15 |

- The 1 R$ row is the designer's (2026-10-09): *"for uncommon/rare the skip timer should be
  reduced to just 1 robux since really are people going to spend 4 robux to skip a 60 second
  timer"*.
- A late receipt whose block is already ready keeps a saved **skip credit** for the next timer.
  **Credits are kept per product** (`LuckyBlocks.Credits`, save version 11), so a new row never
  changes what one buys; a credit only skips a timer its own price covers, so a 4 R$ credit
  never skips a 12-hour timer.
- It is a paid random item (section 13), and it can't be gifted. A skip does not change a
  block's origin. Only the designer's account may bypass timers without paying (testing); the
  countdown stays visible. VIP keeps no timers at all.
- Still the cheapest skip per hour of any game found (Steal An Egg: 9 R$ for 15 minutes, 299 R$
  for 12 hours).

**The quick reveal** (the designer's answer 14): a Common or Uncommon result opens with a quick
1.5-second reveal instead of the full show (`Config.LuckyBlocks.QuickReveal`,
`QuickRevealSeconds`; `LuckyBlocks.quickReveal`); the full show from Rare up. The GUI session
builds it.

**"Open all"** (answer 14): one server request (`OpenAll`) opens every ready Standard and
Uncommon block in the hotbar and bag at once (up to 50, at most once every 3 seconds;
`Config.LuckyBlocks.OpenAll`), skipping held and thrown ones, each climbing as it opens (v5.2),
and answers a short list of what came out. The summary shows the Common and Uncommon cues; a
block that climbed to Rare or better gets its own reel after it, one by one.

### 7.7 Odds screen and per-cue odds

Every cue of a rarity in a block has an equal share: **cue % = the rarity's % from that block
(7.2) / cues of that rarity**. From a Mystery (v5.1, both steps) each Legendary cue is
0.503625 / 7 = 0.0719% (1 in 1,390), each Mythic 1 in 3,460 and the one Secret 1 in 45,007; from
a Standard block 1 in 2,610, 6,510 and 84,656. The shop's block cards and
the reel show the odds; an **"Odds & Details"** button (words, not just an icon) lists every
outcome with its % and "1 in N" and totals exactly 100%. An unclimbed block's list is its climb's
odds with the live luck; the Mystery's adds the blocks it turns into (with the guaranteed block
when pity is due) and counts both steps (7.4); a climbed block's list is the cues of its one
rarity. The Grand Opening's odds are the player's own (9.2). **The Week One Cue
is in no block's list.**

**Cue cards** show the rarity, **its % per Mystery and "N exist"**, for example "EPIC · 0.555%
· 1,284 exist" (4.995% / 9 Epic cues; v5.1, both steps). A cue's own % from other blocks shows only in the
Odds list. "N exist" reads "fewer than 10" until there are 10 copies. The Week One Cue shows no
% (the GUI session adds "Day 7 of your first week").

### 7.8 Announcements and retiring

- Unboxing a **Mythic or Secret** is announced in every server; a **Legendary** in the opener's
  server (plan, 2026-10-02). The every-server line reads "[GLOBAL]: <username> pulled a
  Mythical Cue!" in a pastel rainbow, or "... a Secret Cue!" in red (designer, 2026-10-05). No
  announcement names the cue, only its rarity (designer, 2026-10-05).
- **The "1 in N"** (v5, answer 14): the message carries the chance of that exact cue from the
  block it started as, with the odds live at the climb (the launch luck if it was on; pity left
  out), rounded to 3 significant figures (`LuckyBlocks.oneIn`, `Strings.Banner.OneIn`): from a
  Standard block, a Legendary cue "1 in 2,610", a Mythic cue "1 in 6,510", the Secret "1 in
  84,700". Since v5.1 a Mystery's cue counts from the block it turned into, the block that
  climbed. A block that never climbs uses its own row.
- **A Legendary or Mythic block in the restock** is announced in every server ("A MYTHIC block
  is in the restock for 9:41!"; `Config.Shop.Restock.Announce`).
- **Retired (vaulted) cues never come back** (plan, 2026-10-02). Odds screens update the moment a
  cue is retired.

---

## 8. Selling cues back

Any block-rarity cue can be sold for money, with a confirm step from Epic up and a "Duplicate"
tag on extras. Ranked, Exclusive and Unique cues can't be sold. A paid-origin copy is sold first.
Unchanged by v4 and v5. A Legendary sells for about a fifth of a restock Legendary block
($1,290,000), so there is no sell-and-rebuy loop. **The Week One Cue sells like any Legendary**
($250,000, about 17 Mystery blocks; no farming limits for now, designer 2026-10-09).

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| $150 | $400 | $1,500 | $25,000 | $250,000 | $2,500,000 | $25,000,000 |

Selling also removes cues from the game, which keeps the ones that stay worth more.

---

## 9. What money buys, and the Limited shelf

**Block cues are never sold directly** (designer, 2026-09-27). A Common-to-Secret cue comes
only from a lucky block, a trade or (the Week One Cue) the first week. That keeps every block a
chance at something money can't simply buy, and gives trading its purpose.

Money prices (v5, 2026-10-09; the Mystery v5.1; "hours of play" is Classic match money, about
$7,750 an hour; a 1-hour player earns about $40,000 a day with every reward):

| Item | Price | Hours of play | v4 |
|---|---|---|---|
| Mystery block | **$19,900**; 5 for **$89,900** (10% off; v5: $14,900 and $66,900) | 2.6; 11.6 for 5 | $4,900; 10 for $44,100 |
| Grand Opening block | $24,900; 3 for $69,900; 10 for $219,000 | 3.2 for one | same |
| Restock Rare / Epic / Legendary / Mythic | **$49,900 / $249,000 / $1,290,000 / $4,990,000** | 6.4 / 32 / 166 / 644 | $19,900 / $199,000 / $1,490,000 / $4,990,000 |
| Ability spin | $12,500 each (buy 1, 5, 10 or 50; no bulk discount) | 1.6 | same |
| Timer skip | Robux only, **1 / 4 / 9 / 15 R$** (7.6) | - | 4 / 9 / 15 R$ |
| Limited cues | none at release | - | - |

**When a player has part of the price**, the buy button says "Need $X more" and opens the money
packs with the smallest pack that covers the gap highlighted. Never right after a lost match.

### 9.1 Mystery blocks and the restock shop

**Mystery blocks** (economy v5.1, designer 2026-10-09): **$19,900, or 5 for $89,900**
(`Config.Shop.Deals.Mystery.Money` is what the server charges, `Config.Shop.Mystery` what the
card shows; keep them the same). v5 was $14,900 and 5 for $66,900 (the designer's answer 10 and
plan 2.1). The bundle is 10% off like v4's 10-pack, and 5 instead of 10 keeps it within reach.
A v5.1 Mystery is worth about 1.7 times v5's (it turns into a block that still climbs, 7.4), so
the price rose by a third and the 15-minute playtime Mystery became money (10.3); together they
keep the economy just above v5, as asked.

- **With Robux** (v5.1): Mystery1 **9 R$** (v5: 7) and the **Mystery5** 5-pack **39 R$** (7.8 a
  block, "45 R$ one by one"; **6** during the launch bonus, 11.1). The Robux 10-pack (Mystery10)
  is retired: off sale on Roblox, never deleted; an old receipt still pays 10.
- A bought Mystery is paid origin; the block it turns into keeps that and climbs like any other
  (pity included); its climbed block opens at once. They are paid random items (section 13).

**The restock shop** (v5, the designer's answers 12 and 13) restocks every **10 minutes on the
clock** (UTC :00, :10, ...). Every server shows the same blocks (picked from the time slot's
number), with a real countdown (`Config.Shop.Restock`, `Progression/Restock.luau`). **Two shared
slots, the first always Epic or better**, plus a VIP-only slot with its own richer table
(chances out of 10,000):

| Slot | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|
| 1, always Epic or better (`SlotOdds`) | - | 75.56% | 21.11% | 3.33% |
| 2 (`Odds`) | 55% | 34% | 9.5% | 1.5% |
| VIP's slot (`VipOdds`) | 40% | 40% | 16% | 4% |

| Block | Money | Robux (v5, live 2026-10-09) | Stock per player per restock |
|---|---|---|---|
| Rare | $49,900 | **39 R$** (RestockRare; was 15) | **2** |
| Epic | $249,000 | **149 R$** (RestockEpic; was 99) | 1 |
| Legendary | $1,290,000 | 599 R$ (RestockLegendary) | 1; announced in every server |
| Mythic | $4,990,000 | 1,699 R$ (RestockMythic) | 1; announced in every server |

- **How often:** an Epic or better in every restock; a Legendary or better in 32.8% of
  restocks (about every 31 minutes; 46.2% counting VIP's slot); a Mythic in 4.8% (about every
  3.5 hours, about 7 a day; 8.6% counting VIP's slot). v4: an Epic or better in 34% of
  restocks, a Legendary or better in 3%, a Mythic about every 5 days.
- **Why two slots** (plan 2.2): the same rare stock as three random slots (a Legendary or better
  in 32.8% of restocks against 30%, a Mythic in 4.8% against 4.4%), but every restock shows a
  real Epic and fewer slots make each one feel like an event.
- **A restock block is a guarantee now**: it gives at least its name, with a chance to climb
  (it arrives unclimbed). That is why Legendary and Mythic blocks stay expensive: if a
  guaranteed Legendary cost a few hours of play, Legendaries would flood.
- Stock is per slot, one block per press; **money and Robux share the stock**. The slot odds are
  published on the restock screen (today one line: "Slot 1: Epic or better · Slot 2: ..."). Every
  block in the VIP slot has its usual odds: VIPs see more good blocks, never better odds.
- A slot's shared stock counter (`GlobalStock`, the old plan's "25 worldwide") is in the code
  but no row sets it.
- Blocks bought here are paid origin; their climbed blocks open at once.

The timer skip is in 7.6.

### 9.2 The Grand Opening and the Limited shelf

**The Grand Opening block** (v4 plan 8.5; `Config.Shop.Deals.GrandOpening`) is the launch gift:
Rare or better, never an Uncommon (the designer's ask, 2026-10-08), with the game's only two
Unique cues.

- **Price**: $24,900, 3 for $69,900, 10 for $219,000; or **19 / 49 / 149 R$** (the 3 and 10 save
  14% and 22% against 57 and 190 R$ one by one).
- **Window: 30 days** from `StartsAt` (0 = off), which the designer sets at publish (designer,
  2026-10-08: start at publish, maybe 30-45 days); a "Vaulted" card stays 7 days after the end.
  The launch bonus (11.1) runs on the same window, and the Grand Opening Luck (7.3) on its own
  30-day clock from the same `StartsAt`.
- **The soft launch** (designer, 2026-10-09, temporary; `Deals.GrandOpening.SoftLaunch`): while
  `StartsAt` is 0 the block is on sale for money and Robux **with no end date** and no
  countdown. It does not start the Grand Opening Luck or the launch bonus. Setting `StartsAt`
  for the release starts the real 30-day window (and the luck and the bonus); `SoftLaunch =
  false` closes it again. The copy caps hold either way.
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
Every reward row is `{ Money, Blocks = { [kind] = n }, Spins, Cues }` (`Config.Daily`; `Cues`
since v5, for the Week One Cue), and **every reward is claimed in the Rewards menu** (designer,
2026-10-04: no reward popups; nothing is given by itself on join). Every block a reward gives
climbs from its name (7.1).

### 10.1 Login: the first week, then later weeks

| Login day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| **First week** (once ever) | $5,000 + 1 Mystery block | **a Rare block** | $10,000 | 2 Mystery blocks | $15,000 | 2 Mystery blocks | **the Week One Cue** + 2 ability spins |
| **Later weeks** | $5,000 | 1 Mystery block | $10,000 | 1 Mystery block | $15,000 | 1 Mystery block | **a Rare block** + 2 ability spins |
| v4 first week | $5,000 + 1 Mystery | an Epic block | $10,000 | 2 Mystery | a Rare block | 3 Mystery | a Legendary block + 2 spins |
| v4 later weeks | $5,000 | a Rare block | $10,000 | 2 Mystery | $15,000 | 3 Mystery | an Epic block + 2 spins |

- **The first week = the first 7 login days within 14 days of joining, in a row or not**
  (designer, 2026-10-08; `Config.Daily.FirstWeek`, `FirstWeekWindow` 14; the join's day is day
  1). After 7 claims, or after the window, the later weeks take over. Kids miss days; this
  forgives them.
- **A login day counts only once the player has finished a match that day** (any mode, PC
  included; `NeedsMatch`; designer, 2026-10-08), so an alt can't collect the first week by
  just joining. Until then the Rewards menu says to play a match first.
- **Day 7: the Week One Cue** (the designer's pick, 2026-10-09; plan section 5): a new Legendary
  cue (`WeekOneCue`) that is **never in any block, reel, restock or shop list**. Its only ways in
  are day 7, Claim All and trading. Like any Legendary it is **tradable** (designer: "it should
  be tradable"), sells back for $250,000, pays $25,000 finder's money the first time, counts in
  the Index's Legendary row and has numbered copies. Its trade worth follows its own copies, so
  it trades low next to block Legendaries: a "played my first week" badge, not a luck trophy.
  **No farming limits for now** (designer: "all of that will be worried about IF this game does
  good"). The first-week calendar shows it from day 1, on day 7's card (the GUI session's). Its
  look is new art the designer picks; until then it uses the default bands with its own name.
  Simulated: 16% of active players hold it on day 30 and 29% on day 60.
- **Day 2's Rare block** is the day-1 retention hook (v4: an Epic block). It climbs: Epic or
  better 18% of the time, 27% during the launch luck.
- **Later weeks keep the streak** (`Config.Daily.Streak`): one claim per day; **one free streak
  freeze a week** (weeks start Monday): one missed day is covered by itself and the streak goes
  on. Two or more missed days start the week over.
- **Claim All** (designer, 2026-10-08): Robux claims every day still ahead in this 7-day row at
  once (`Config.Daily.ClaimAll`; first week 399 / 349 / 299 R$ for 6-7 / 3-5 / 1-2 days left,
  later weeks **79 / 69 / 35 R$** since v5, were 129 / 99 / 59). It still claims day 7, so a
  player can buy the Week One Cue early (plan 2.10); its cue comes as paid origin, like its
  blocks. A paid random item, never a gift. Priced at about half the shop value of the days it
  claims (money at Pack1's rate, blocks at their Robux prices, the Week One Cue like a restock
  Legendary block). Selling the Week One Cue from ClaimAllFirst2 beats the $250,000 money pack
  once per player; the designer kept 299 R$ (2026-10-09).
- **VIP adds 1 ability spin and an Uncommon block** to each day's claim (10.5).
- Everyone also gets **1 free ability spin a day** on the Abilities screen (11.8).
- The day starts at 08:00 UTC (7.5).
- **Save version 9's migration**: a save that had already claimed 7 or more days counts its
  first week as done (it gets the later weeks).

### 10.2 The 28-day track

Counts every day claimed in total. It never resets and repeats every 28 days. On the day the
count reaches a step, its reward is added to that day's claim (`Config.Daily.Track`):

| | Day 8 | Day 14 | Day 21 | Day 28 |
|---|---|---|---|---|
| v5 | $50,000 | **a Rare block** | $150,000 | **an Epic block** |
| v4 (designer, 2026-10-08) | $50,000 | an Epic block | $150,000 | a Legendary block |

Day 28 is an Epic block because the designer chose "Neither" for calendar Legendaries (answer 8,
2026-10-09). (This section still showed an older track, a Rare block / 2 Rare / 2 Rare / an Epic
block, until 2026-10-09; it is fixed here.) The first prize is on **day 8**, not day 7: day 7
has the Week One Cue, and Roblox's D7 counts a return on the 8th day, so day 8 needs its own
reason.

### 10.3 Playtime gifts

Minutes played in a day, across sessions, each claimable once that day in the Rewards menu
(never given by itself). **Everything lands inside the first hour** (Roblox's ranking counts
playtime up to 60 minutes a day):

| | 5 min | 15 min | 30 min | 45 min | 60 min |
|---|---|---|---|---|---|
| v5.1 | $1,000 | **$2,000** | $2,500 | $3,500 | $5,000 + 1 ability spin |
| v5 | $1,000 | 1 Mystery block | **$2,500** | **$3,500** | **$5,000** + 1 ability spin |
| v4 | $1,000 | 1 Mystery block | 1 Mystery block | 1 Mystery block | a Rare block + 1 ability spin |

Fewer blocks (v5): one Mystery block instead of three and a Rare block. **v5.1 (designer,
2026-10-09) made the 15-minute gift $2,000** to pay for the better Mystery: playtime now gives
money only. The five gifts stay, because the Free Reward screen shows five tiles (plan 2.5).

### 10.4 Group, likes, invites and codes

- **Group** (designer, 2026-10-03): the game's Roblox group **675425213** ("Lucky 8"). The
  Rewards card has **Join** (an in-game prompt) then **Claim**: **2 Mystery blocks** (v5; v4:
  3), once per player. While a member, match money gets **+10%** by itself (checked on join and
  on Claim).
- **Favorite**: favoriting the game through Roblox's prompt gives **$10,000 + a Lucky 8 block**
  (an Uncommon start since v5) once (designer, 2026-10-08; `Config.Social.FavoriteReward`).
  Roblox gives the server no way to check a favorite, so the client reports it.
- **Like codes** (designer, 2026-10-03): six codes, written now and **switched on live** by the
  designer with `/code on <CODE>` (every server at once, no republish) when the game reaches
  each like milestone. Word them as thanks for a milestone, never "like to unlock". They stay
  as they were (plan 2.12: rare celebration gifts, switched on by hand); their blocks climb from
  their names.

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
  gives **both of you an Uncommon block** (v5; v4: a Rare block; `Config.Social.InviteBlock`).
  The inviter's reward comes once ever (their first invited friend's first win;
  `InviterOnce`), within the **5 a month** cap; an offline inviter gets theirs on their next
  join. Every invited friend still gets their own block.
- **The first leave**: a Gift block (an Uncommon start, after a 12-hour wait from the leave),
  once (7.2).
- **Codes** (case-insensitive, once per player, an optional end date):

| Code | Gives |
|---|---|
| WELCOME | $5,000 + 1 Mystery block |
| 8BALL | $2,500 |
| ROOFTOP | **an Uncommon block** (v5; v4: a Rare block; until 2026-12-31) |
| RELEASE | 3 ability spins (the tutorial's code) |

  Codes give only money, lucky blocks and spins: never a cue, pass or boost sold for Robux.

Together the group, favorite, codes and invite are about a day's worth of blocks once.

### 10.5 VIP's daily Uncommon block

An **Uncommon block each day a VIP claims** (v5; v4, designer 2026-10-08: a Rare block;
`Config.Daily.VipBlocks`), added to the day's claim. A v5 Uncommon block has 6 times the Epic
chance of v4's Rare row; it climbs like every Uncommon block, never better odds. **Where
PolicyService restricts paid random items it is $5,000 instead** (`VipRestrictedMoney`), and so
is it while PolicyService hasn't answered (an unknown policy counts as restricted). VIP is a paid
random item: its card shows the Uncommon block's odds, and VIP is never promoted on Roblox's Buy
Robux page (a pass promoted there can't grant paid random items).

### 10.6 Planned, not built yet

**Planned features** (v4 plan 6.4 and 6.5, 2026-10-08; their blocks redone by v5). Their
numbers are set now in `Config.Planned` so the model and this doc price them; nothing in the
game reads them yet, and each feature gets its own brief. The model includes them by default
(`--built-only` leaves them out; section 1).

- **The Daily Challenge: Lucky Shot and Golden Shot** (the designer's concept screens; "there
  will still be a golden shot for the lucky shot challenge", 2026-10-08). One shot a day at a
  ring target; the reward is by the ring hit:

| Ring | Miss | Grey | Blue | Red | Gold |
|---|---|---|---|---|---|
| Lucky Shot (free, once a day) | $500 | $1,500 | $3,000 | 1 Mystery block | **an Uncommon block** (v4: a Rare block) |
| Golden Shot (**15 R$**, once a day) | $5,000 | $7,500 + **a Mystery block** | **an Uncommon block** | **an Uncommon block** + $10,000 | **a Rare block** + $25,000 |
| v4's Golden Shot | $5,000 | $7,500 + an Uncommon block | a Rare block | a Rare block + $10,000 | 2 Rare blocks + $25,000 |

  The Golden Shot's top prize is one Rare block, never an Epic block: a skilled player can aim
  for gold every day. It is a paid random item; its 15 R$ stays (worth about 35 R$ at an
  average player's rings; checked in the v5 Robux pass, 11).
- **Lucky Rain**: in a server with 4+ players, a block falls about every 30 minutes (each match
  finished there brings it 1 minute sooner, never under 15 minutes); a Sky block (a Standard
  start), or a Rare block 1 time in 20; everyone who reaches it within 90 seconds gets one;
  **3 a day**.
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

**v5's Robux pass** (approved and synced 2026-10-09; the reasoning is
`~/Desktop/8ball-refs/economy/05-economy-v5-robux.md`): v5's blocks give much more, so v4's prices
undersold them (11.9). Changed: the Mystery block 5 to 7 R$, the new 5-pack 29 R$, the 10-pack
off sale, the restock Rare 15 to 39 R$ and Epic 99 to 149 R$, the later weeks' Claim All 129 /
99 / 59 to 79 / 69 / 35 R$, the 1 R$ skip, and the texts (VIP's Uncommon block, Claim All's Week
One Cue, the Mystery block climbing to the Secret). Kept: the restock Legendary and Mythic
blocks, the first week's Claim All, the Golden Shot (15 R$, planned), everything else.

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

**Boosted on 2026-10-08** (designer, on the GUI mock page: "spending 1700 robux for 760000 and
that's still not enough to buy a legendary lucky block ... money definitely needs a boost"). The
biggest pack buys more than a restock Legendary block's money price ($1,290,000 since v5). Unchanged by v5.
Through money, each block costs more than its own Robux price (at the best pack: Mystery 2.4x,
the 5-pack 2.6x, Grand Opening 1.5x, restock Rare 1.4x, Epic 1.9x, Legendary 2.4x, Mythic 3.3x;
`python3 tools/economy_model.py value`). Bought money mostly buys Mystery blocks, a
small share of where good cues come from. **"Best value" is Pack7** (`Config.Products.BestValue`).
An hour of Classic play (about $7,750) is about 9 R$ of the biggest pack.

**The first-pack double is off** (v4, 2026-10-08; `Config.Shop.FirstPackMultiplier` 1): no top
Roblox game has one, it nudged a kid toward the biggest pack first, and the 29 R$ Starter Pack
now wins the first purchase.

**The launch bonus** replaces the 30% release sale (designer, 2026-10-08;
`Config.Shop.LaunchBonus`). During the Grand Opening's window, **every money pack gives +30%
money**, and **the Robux Mystery 5-pack (29 R$) gives 6 Mystery blocks** instead of 5 (v5,
`MysteryBulkCount`; v4's 10-pack gave 13). It is
shown as "Launch bonus +30%" with its real end date and ends on that date; a receipt counts
inside the window plus 10 minutes of grace. A "30% off" a price nobody was ever charged would be
a fake former price. The six release-sale products are **retired**: never offered again, kept
on Roblox (never deleted) so an old receipt still pays.

### 11.2 VIP (game pass, 399 R$)

399 R$ since v4 (2026-10-08; was 499 in Config and 599 on Roblox until that day's `--sync`).

- **2x money** (+100%, adds with other boosts) on match money only (3.5).
- **No block timers** (designer, 2026-10-07): every block opens at once
  (`Config.LuckyBlocks.VipTimerFactor` 0), and timers already running when VIP arrives finish.
- **An Uncommon block every day** (v5; v4: a Rare block), added to the day's login claim;
  **$5,000** where paid random items are restricted (10.5).
- **Skip and Auto Spin** on the ability spin screen (11.8; without VIP they answer "NoVip").
- **+1 free ability spin a day** (added to the day's login claim, 10.1).
- **The VIP restock slot**: a third slot every restock, Rare 40% / Epic 40% / Legendary 16% /
  Mythic 4% (9.1).
- **The VIP Cue** (Exclusive, rainbow, never traded), a **[VIP]** chat tag before the rank tag
  ("[VIP] [GOLD] Name") and a rainbow name over the head (designer, 2026-09-28).
- **No XP, no discount, no extra win-track steps.** Never better block odds.

The pass description on Roblox says the daily block is money where paid random items aren't
allowed (`tools/products_spec.json`); since 2026-10-09 it says "an Uncommon Lucky Block every
day", like the VIP offer's text and the in-game perk lines.

### 11.3 VIP welcome offer (developer product, 199 R$)

**VIP at half price for 24 hours from a player's first join**, with a real countdown that never
restarts. If they don't buy it, **one "welcome back" window of 24 hours** opens 7 days later,
then never again. It is a developer product that grants VIP in the save (VIP = owns the pass
**or** bought the offer), so only that player sees it. Friendly wording ("Welcome offer"),
never "LAST CHANCE". Managed Pricing is off so "half price" stays true.

### 11.4 Starter Pack (developer product, 29 R$)

Unchanged by v5 (its block never climbs). Once per player, in the first 7 days after the first
join, shown after the first block opening
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

**3 game passes and 42 developer products on Roblox, 9 of them retired** (`Config.Products`; the names, prices and descriptions are
`tools/products_spec.json`, sent to Roblox by `tools/roblox_products.py`):

| # | Key | Kind | Robux | Before v4 | Gives |
|---|---|---|---|---|---|
| 1 | Vip | Game pass | **399** | 499 | 11.2 |
| 2 | UltSlot2 | Game pass | **49** | 59 | the second ability slot |
| 3 | UltSlot3 | Game pass | **79** | 99 | the third ability slot |
| 4 | VipOffer | Product, once | **199** | 249 | 11.3 |
| 5 | StarterPack | Product, once | **29** | 99 | 11.4 |
| 6-12 | Pack1-Pack7 | Products | **25 / 49 / 99 / 199 / 399 / 799 / 1,699** | 49 ... 4,999 | 11.1 |
| 13 | Mystery1 | Product | **9** (v5.1; v5 7, v4 5) | 25 | 1 Mystery block |
| 14 | Mystery5 | Product (3717476154, v5) | **39** (45 one by one; v5 29) | new | 5 Mystery blocks (6 during the launch bonus) |
| 15 | Mystery10 | Product, **retired** (off sale, never deleted) | 45 | 229 | 10 Mystery blocks (an old receipt still pays) |
| 16-18 | GrandOpening1, GrandOpening3, GrandOpening10 | Products | **19 / 49 / 149** (57 / 190 one by one) | 49 / 129 / 349 | Grand Opening blocks, only while it runs (9.2) |
| 19 | RestockRare | Product | **39** (v5; v4 15) | 99 (never created) | the restock Rare block, while in stock |
| 20 | RestockEpic | Product | **149** (v5; v4 99) | 999 | the restock Epic block, while in stock |
| 21 | RestockLegendary | Product | **599** | 4,999 | the restock Legendary block, while in stock |
| 22 | RestockMythic | Product | **1,699** | new | the restock Mythic block, while in stock |
| 23-26 | LuckyBlockSkip1, LuckyBlockSkip, LuckyBlockSkip9, LuckyBlockSkip15 | Products | **1 / 4 / 9 / 15** | 19 (one product) | finish a block's timer, by time left (7.6) |
| 27 | MoneyParty | Product | **49** | 199 | +100% match money for everyone in the server for 15 minutes, the buyer's name announced; buying again adds 15 minutes (the shop offers it up to an hour queued) |
| 28-33 | ClaimAllFirst7, 5, 2; ClaimAllWeek7, 5, 2 | Products | **399 / 349 / 299; 79 / 69 / 35** (v5; v4 later weeks 129 / 99 / 59) | new (2026-10-08) | the rest of this 7-day login row at once (10.1) |
| 34-37 | Spin1, Spin5, Spin10, Spin50 | Products | **9 / 39 / 75 / 299** | 15 / 50 / 100 / 449 | ability spins (11.8) |
| 38-39 | Lucky1, Lucky3 | Products | 25 / 65 | 49 / 129 | **retired** with Lucky Spins (designer, 2026-10-08) |
| 40-45 | Pack4Sale-Pack7Sale, VipSale, Mystery10Sale | Products | - | 349 ... 3,499 | **retired** (the release sale; `Retired = true`, shown as closed, taken off sale on Roblox, never deleted) |

Plus a **Get Roblox Plus** button (`MarketplaceService:PromptRobloxSubscriptionPurchase`, no
product to create; Roblox pays the game 250 R$ a month for up to 3 months for each subscriber
signed up in the game). Later, with its feature: the **Golden Shot** (15 R$, 10.6).

**Bundle savings are always true**: a bundle's "Was" is the same count bought one at a time
today ("57 R$ one by one"), never a crossed-out former price (v4; `Was` in `Config.Products`).

**The shop is one scrolling page, no tabs** (`Config.Shop.Order`): 1 the Grand Opening block
(while it runs), 2 the Mystery block, 3 the restock shop, 4 the Starter Pack and VIP side by
side, 5 money packs, 6 Money Party, the ability slots and Get Roblox Plus. The timer skip is
offered on the block itself; spins on the Abilities screen. (UI_STYLE section 15 is the
reference.)

**Gifts**: a developer product can be bought for another player in the server, except the
restock blocks, the skips and Claim All (they name the buyer's own restock, block or login row).
**A player whose paid random items are restricted can't gift a random product** (v4).

A Robux receipt that no longer qualifies when it arrives (the VIP offer when already VIP or
after its window plus 10 minutes, a second Starter Pack) pays plain money instead at Pack1's
rate, Robux x 10,000 / 25 (the VIP offer $79,600, the Starter Pack $11,600).

**Setting the prices on Roblox**: `python3 tools/roblox_products.py --sync --dry-run`, then
`--sync`, brings every made pass and product in line with `products_spec.json` (price, name,
description, off sale for a retired one); the plain run creates missing ones and writes their
ids to `tools/products_ids.json` for `Config.Products` (`--only <Key>` for one). A price change
goes live in every server at once. Done 2026-10-08: RestockRare, RestockMythic and the two new
skips made, every price, name and text synced, the six sale products off sale (none deleted).
2026-10-09: LuckyBlockSkip1 and Mystery5 made (`--only`; neither has an icon yet), then the v5
prices and texts synced (`--sync --only` the changed keys, Mystery10 off sale). **By hand, on
the Creator Hub** (the Open Cloud API has no field for it): set every developer product that
holds a random item to **Not Listed**, so it can't be bought outside the game without its odds
(13).

### 11.6 Later (not at release)

In this order (plan, 2026-10-02): a season **Cue Pass** (449 / 1,199 R$), more gifts, a Robux
restock refill, a $4.99 a month subscription, rewarded ads paying money. Seasons, the Cue Pass
and event blocks all come after release.

### 11.7 Never sell

**Ruled out** (plan, 2026-10-02): a luck economy (potions, server luck, luck stats), money bets
on matches, offline income, money for idle time, always-on Epic or Legendary blocks, fake
near-misses. Also never: anything that protects rank, in-match aids (longer guidelines, hints,
power or spin upgrades), anything that hurts an opponent, and purchase prompts right after a
loss. Two later calls by the designer sit next to this list: VIP's daily block (v4, 2026-10-08;
an Uncommon block since v5), and the restock's first slot, always Epic or better (v5,
2026-10-09, answer 13): it changes every 10 minutes, one per player, at a guarantee's price, so
it is a rotating offer rather than an always-on Epic block. The Grand Opening Luck is a free,
dated event for everyone, never sold.

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

**Lucky Spins were retired on 2026-10-08** (designer: "just get rid of lucky spins as it doesnt
exist anymore"; `Config.Ults.Earn.LuckySpins` false, Lucky1 and Lucky3 retired, save v10 turned
held ones into plain spins). Their rows below are history.

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
| The designer's feel (2026-10-08) | | | 8-80 R$, under $1 | 80-400 R$, "a few dollars" | 400-2,400 R$ | 800-8,000 R$, "tens of dollars" | 8,000-80,000 R$, "$100 or more" |
| Cheapest pull with Robux (that rarity or better, v5.1 prices) | | | 16 R$ (Grand Opening; 28 R$ from the 5-pack after it) | 127 R$ (Grand Opening; 140 R$ from the 5-pack after it) | 599 R$ (restock Legendary) | 1,699 R$ (restock Mythic) | 67,960 R$ (restock Mythic) |

**Every product against the ladder** (worth of what it gives / its price; v5.1 prices): Mystery
block 3.83, the 5-pack 4.41 (5.3 during the launch bonus), Grand Opening 5.9 (the launch gift),
restock Rare / Epic / Legendary / Mythic 2.75 / 3.08 / 3.91 / 4.18, the Starter Pack's block 2.5,
the Golden Shot about 2.3. v5's Mystery was 2.89 (7 R$); without its higher price v5.1's would
be 4.92, a better buy than every restock block. At v4's Robux prices v5's blocks were worth 4 to 7 times their price
(the Mystery 4.05, the restock Rare 7.15); under v4 every product sat between 1.07 and 2.4.

**How many times more the money route costs** than buying directly with Robux (money at the
biggest pack's rate): Mystery block 2.5x, the 5-pack 2.6x, Grand Opening block 1.5x, restock
Rare 1.4x, Epic 1.9x, Legendary 2.4x, Mythic 3.3x. The rule stays v4's (designer: "about 3x, you
set the final ratio", 2026-10-08): **the Robux route is about 2.5-3 times better value than money**
for the everyday blocks; the restock's Rare and Epic blocks sit lower on purpose, because their
money prices are the free player's way in. Like the top Roblox games, Robux prices span about
100x while money prices span millions of times.

---

## 12. Trading

Built on the server (2026-10-03; the trade screen is the GUI lane's): `Progression/Trade.luau`,
`src/server/Trading.luau`, remotes `TradeRequest` and `TradeState`.

**Who and what**
- **Anyone in the server, no gate at all** (designer, 2026-10-03: no 25-win gate, no friends or
  nearby rules).
- **Cues and ready lucky blocks**, **up to 8 items a side**, one entry per copy. **Never money.**
  No empty side. A block trades once its timer is done (v5.2; offered as "Block:<kind>"); an
  old **climbed** block from v5's climb screen as "Climbed:<tier>", named "Climbed Rare" and so
  on in the trade window. The Gift trades once its 12-hour wait is over. A traded block lands
  ready.
- Block cues, Unique cues, the Starter Cue and **the Week One Cue** trade (v5, designer
  2026-10-09: "it should be tradable"). Classic, the Ranked cues and every other Exclusive cue
  never (rank, season and VIP cues; designer, 2026-09-28).
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
  `Config.Trade.MinExists`); the Week One Cue too, by its own copies. **A lucky block's worth
  is worked out live** (`Trade.blockWorth`): an unclimbed block by its climb's odds from its
  start, a climbed block by exactly its tier's cues, the Grand Opening and Starter blocks by
  their own rows; each cue worth 1 / its live copies. An unclimbed Mystery by its roll and
  climb together (v5.1); a block a Mystery turned into is an ordinary unclimbed block of its
  tier (traded, it loses its hidden pity mark). Until the counters load, fallback tables from
  the v5.1 model at day 30 (`python3 tools/economy_model.py exists`): **unclimbed and
  never-climbing blocks** (`Config.Trade.BlockExists`): Standard and Sky 47,000, Uncommon,
  Lucky 8 and Gift 46,000, Mystery 44,000, Rare 32,000, Epic 12,000, Legendary 2,800, Mythic
  1,100, Grand Opening 7,800, Starter 38,000; **climbed blocks** (`ClimbedExists`): Standard
  48,000, Uncommon 60,000, Rare 50,000, Epic 19,000, Legendary 3,800, Mythic 1,400. With supply growing
  about 5x between day 30 and day 60, fixed numbers would go stale within weeks.
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
invite cap (10.4). No trade hold on first-week rewards, the Week One Cue included (designer,
2026-10-08 and 2026-10-09).

**Retiring cues ("Vaulted")**: the designer can retire block cues; they stop dropping and never
come back (7.8), which keeps old cues worth trading for. Adding new cues each season and
retiring old ones is how value is kept (section 6).

---

## 13. Roblox rules checklist

- **Odds as percentages** before every purchase: every outcome with its % (and "1 in N" beside
  the tiny ones), totals exactly 100, an "Odds & Details" button in words, **live odds**: the
  boosted odds while the Grand Opening Luck runs, and the guaranteed tier when pity is due. The
  Grand Opening shows each player their own odds (9.2). **Pity is stated in numbers.**
- **The climb shows the real result**: the server rolls the final tier first; the presses only
  reveal it. No fake near-misses (11.7).
- **Paid random items** are: Mystery and Grand Opening blocks (money or Robux), restock blocks,
  the block timer skips, Claim All, VIP (its daily block and timer perk, and its daily spin),
  ability spins, and later the Golden Shot (`Random = true` in `Config.Products`). Where
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
  release sale's "30% off". The Grand Opening Luck is dated, with a real countdown, and ends
  without cutting anyone's odds.
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
| The climb ladder, the win track and the rewards | section 7 | if the active-player shares drift from the plan's (section 1); with typical retention expect about two-thirds of the model's Legendary and Mythic shares. If the launch is small, raise the ladder (a buff is always welcome); **never lower printed odds** (section 6) |
| Win 10's block | an Epic block | if Legendaries feel too common among grinders: a Rare block (plan 2.15) |
| The Grand Opening Luck | 30 days from `StartsAt`, Rare to Epic 27%, Epic to Legendary 15% | it ends by itself; its length is `Config.BlockOdds.Climb.Luck.Seconds` |
| The Grand Opening window | 30 days | stretch to 45 if few players came; the caps keep the Uniques at 1,000 and 100 either way |
| Restock Legendary and Mythic | slot 1: 21.11% and 3.33%; slot 2: 9.5% and 1.5%; no worldwide cap set | if they pile up or never sell (set `GlobalStock`) |
| The Week One Cue | no farming limits | if alts farm it once the game does well (designer, 2026-10-09) |
| Copy numbers | #1-100 | if the numbers should last longer: the first 500 of Legendary and up (v5: Legendary's #100 gone by day 4, Mythic's by day 7) |
| Limited drops | one about every 2 weeks | faster once the art pipeline allows; add copy caps if values fall |
| Seasons | ranks never reset | season rewards for the highest tier reached, once seasons start; new cues each season, old ones retired |

**Watch these numbers** (Roblox analytics and our own events): the share of active players
owning an Epic, Legendary, Mythic and Secret (section 1), D1 and D7 retention, players' average
saved money (rising fast = too much income; v5 pays more money and fewer blocks), how many sell
back Epics (high = too many Epics), how many sell the Week One Cue, Mystery block and restock
sales, Starter Pack and money-pack conversion, and trades of first-week cues between new
accounts (alts).

---

## 15. Bots' cues

A bot's equipped cue matches what real players at its rank own (`Config.BotCues`,
`BotCues.pick(tier, roll)`; kept from v4 by v5, to re-fit later (section 17); v4: from the simulation's real players at day 60, Master and up
extrapolated). Each column is the chance the cue is that rarity or better; Common, Uncommon and
Rare are spread by the Mystery's odds (v5.1: its roll and climb together), and the cue is then
one block cue of that rarity, each equally likely.

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

- **The Week One Cue's look**: a new Legendary look (aura, trail and pocket finisher) and its
  card icon, its own task. Until then it shows the default bands with its own name.
- When the Grand Opening starts (`StartsAt`), set at publish; the Grand Opening Luck and the
  launch bonus start with it. Whether to stretch its window past 30 days.
- The Not Listed setting for random-item developer products on the Creator Hub (11.5).
- When to schedule the next Limited.
- Copy numbers past #100 for Legendary and up: under v5 Legendary's #100 is gone by about day
  4 and Mythic's by day 7.
- Bots' cues (section 15) are still v4's table; under v5 real players own more Epics and
  Legendaries, so bots may look a little poor until it is re-fit (best from launch data).

---

## 18. The menus and how items are kept

- **The menus** (designer, 2026-09-28): four buttons in one column on the left: **Shop**,
  **Inventory**, **Rewards** and **Trade**. The Shop is one scrolling page with no tabs
  (11.5). The Inventory has two tabs, **Cues** (first) and **Index**; lucky blocks are not in
  it: they live in the hotbar and its bag. Rewards holds the login days (first week or later
  weeks), the 28-day track, playtime gifts, VIP's block, codes and the group, favorite and
  invite cards; everything is claimed there and nothing pops up by itself (designer,
  2026-10-04). Trading is in the first release.
- **How items are saved** (save version 11, 2026-10-09): a count per cue id for block and
  Exclusive cues, with how many of them are paid origin; Unique cues keep their copy number
  (#412) and a paid flag; lucky blocks as a list (`LuckyBlocks.List`, each `{ Id, Kind,
  ReadyAt, Paid?, Climbed?, From?, Luck?, Pity? }`: `Climbed` marks a climbed block, `From` the
  kind it climbed from and `Luck` whether the launch luck was on, for the "1 in N"; `Pity`, since
  v5.1 with no version bump, the pity counters a block a Mystery turned into still owes, "Rare"
  or "Epic", kept only on an unclimbed tier block) plus skip credits
  per product (`LuckyBlocks.Credits`). **Version 11** (economy v5) counts every block already
  held as unclimbed (a tier block's running timer ends; the Gift keeps its wait), moves the old
  tiered credits to their products (`SkipCredits1` to LuckyBlockSkip, `SkipCredits2` to
  LuckyBlockSkip9, `SkipCredits` to LuckyBlockSkip15), and starts a new save's pity counters at
  the head start (2 and 10). Version 10 (2026-10-08) turned Lucky Spins into plain spins.
  Version 9 (v4, 2026-10-08) added the day's win-track count and finished matches
  (`Daily.Track`, `Daily.Matches`) and the first week's claimed days (`Login.FirstWeek`); its
  migration started today's daily counters over for the new 08:00 UTC day and counted a save
  with 7 or more claimed days as having had its first week. (Version 7, 2026-10-04, dropped the
  old cases; version 6, 2026-10-03, was a full wipe.) The default Classic cue is always owned
  and never counted, sold or traded. Saves go through the session-locked, versioned save layer.
- **Opening blocks.** One at a time, in the world: hold the block from its hotbar slot, throw
  it, hold the prompt; the reel, the pull cutscene (Rare and up) and the "YOU GOT" card follow.
  The block climbs as it opens and the reel shows that climb's odds (v5.2, 7.1); a Mystery
  rolls on its upgrade screen first. A Common or Uncommon cue skips the reel: its result card
  alone, gone by itself after 1.5 s (the quick reveal). **"Open all"** (v5), a green button
  right of the hotbar's bag button, opens every ready Standard and Uncommon block at once and
  shows one summary of the cues, then a reel for each Rare or better (7.6).
- **Index completion.** A cue never owned is a "?" card; tapping it shows its name and its
  black 3D silhouette turning (designer, 2026-09-28). A cue counts once it has ever been owned
  (selling it later keeps it). The Week One Cue sits in the Legendary row. Completing a rarity
  row pays once (`Config.Index.Rows`):

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

## 19. Differences from the v5 plan, and the shims

The approved plan is `docs/prompts/ECONOMY_V5_PLAN.md`; the build's report is
`docs/prompts/ECONOMY_V5_REPORT.md`. Built differently, or decided where the plan was silent
(Claude's calls, each a dated line in DECISIONS.md, 2026-10-09):

- **The climb odds are computed, not stored**: Config holds the six steps and the luck; every
  block's table comes from `BlockDrop`. The v4 tier weights and per-press chances are gone.
- **The Sky block's own odds row is gone**: it climbs from Standard (plan 2.11).
- **Old saves' blocks all count as unclimbed** (version 11), and a tier block's running timer
  ends; skip credits are keyed by the product bought.
- **A climbed block is its own trade item** ("Climbed:<tier>"), so an unclimbed and a climbed
  Rare block are never mixed up in a trade.
- **The Secret's pool**: a Secret climb gives a cue from the Secret row of the core pool.
- **The tutorial's Bronze block is an Uncommon block that skips its climb**
  (`Config.Tutorial.BronzeBlockKind`, the server's `stay` hook): a v5 Standard block gives only
  Commons, and the tutorial promises an Uncommon cue.
- **The win track's money steps count like block steps** for the anti-farm rules and PC limits.
- **The Week One Cue** sits in the Block group with a Legendary effect and Classic's look until
  its art exists; in place of a chance it shows "Day 7" on its card and "Day 7 of your first
  week" in its details and the Index, and the first week's day 7 card shows it from day 1;
  Claim All gives it as paid origin like its blocks; the server counts its copies on a claim.
- **A Robux button for a product off sale or not made** shows its price greyed (the 5-pack
  exists since 2026-10-09).
- **"Open all"** skips a block whose open has a special plan (a forced or unique result), which
  the one-by-one open handles.
- **The "1 in N"** rounds to the nearest 3 significant figures, leaves pity out, and uses a
  never-climbing block's own row.
- **`Config.Trade.ClimbedExists`** is new beside `BlockExists`, both from the v5 model at day 30.
- **The restock** shows three cards across the band, slot 1 with a tilted "Epic or better!" tag,
  and each slot's own odds under its card (VIP's too).
- **The shop's Robux prices are the live ones** (what Roblox charges the player), the Grand
  Opening card's too; a bundle's struck-through or "one by one" price is the live single price
  times the count.
- **The model's small differences from the plan's run**: the pity head start (in Config now)
  and the v5 Robux prices (the plan's run used v4's); the ownership shares move by noise only
  (`v5-build/robux_sim.txt`).

**Economy v5.1** (designer, 2026-10-09 evening; plan section 15). Claude's calls, each a dated
line in DECISIONS.md:

- **Pity is checked at the roll and counts the final cue.** A roll that lands on a Rare-or-better
  block resets that counter at once; the rest ride on the block (`Block.Pity`, "Rare" or "Epic",
  kept by the save fixer only on an unclimbed tier block) and count at its climb. No save
  version bump: an old save has no marks.
- **The roll is the same 4-press screen**, ending on the block (no Secret rung for a Mystery);
  the block lands back in its slot unclimbed and ready.
- **The tutorial's scripted first Mystery** (on `tutorial-v2`) now turns it into a block that
  needs its own climb; the `forced` hook names the block it turns into (pity still counted), and
  `stay` turns it into a Standard block with no pity counted. Hand-off note for the tutorial
  session in DECISIONS.md.
- **The shop's pity bars refresh** after a Mystery rolls or a marked block climbs (they used to
  wait for the next ShopState).
- **Odds & Details for the Mystery** adds "Ends with a cue that is" (each rarity over both
  steps), as the plan page promised.
- **The money price lives in two places** (`Shop.Deals.Mystery.Money`, charged, and
  `Shop.Mystery`, shown); a test keeps them equal.

**Shims**: the GUI run (`docs/prompts/ECONOMY_V5_GUI_PROMPT.md`, 2026-10-09) removed shims 1-5
and 7-9 as their screens were updated (the climb screen for every block, the Secret rung, Odds
& Details, the result screen's own "Win track" line, the Week One Cue's card, the restock's
cards, the greyed off-sale price). Two stay:

6. The trade window names climbed blocks "Climbed ..." (trading is not in the release).
10. The tutorial's `stay` hook (above): the tutorial session's call when `tutorial-v2` is
    merged.

**Kept from v4** (still true): the Grand Opening runs 30 days; the restock Rare block's stock is
2 a restock; the Starter Pack is not a `Random` product (where restricted it is $40,000 and the
hour); "Best value" is Pack7; a bundle's "Was" is the one-by-one price; no minimum gap between
two claims; an unknown policy counts as restricted for VIP's block; trading has no gate
(designer, 2026-10-03); a bot never shows the Secret cue (lane, 2026-10-03); VIP's daily spin is
added to the day's login claim (lane, 2026-10-03).

**Not built yet** (planned, 10.6): the Lucky Shot and Golden Shot, Lucky Rain, the stay bonus.
**Built by the GUI run** (2026-10-09): the climb screen for every block, the unclimbed mark, the
Secret rung and reveal, the quick reveal, "Open all" and its summary, every block's Odds &
Details with each cue's "1 in N" and the pity bars, the Grand Opening Luck's clover, the
Mystery card's rows (5 since v5.1: the blocks it turns into) and pity bars, the restock's three
cards, the 5-pack, the win track's money tiles, the first week's day 7 cue and the Index's Week
One Cue line.
