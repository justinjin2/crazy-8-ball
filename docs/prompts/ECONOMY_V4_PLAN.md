# Crazy 8 Ball economy v4: the forgiving economy (proposal, 2026-10-08)

For the designer. Written after five research reports (`research-2026-10-08/`, every number
linked), two interview rounds (your answers are marked "designer, 2026-10-08") and a 60-day
population simulation (`economy_v4_sim.py`; every output is in `economy_v4_results.txt`).
Nothing is built. Once you say "approved", this file is the source for the rebuild.

**How odds are written:** percentages everywhere; every table adds up to exactly 100; tiny odds
keep their decimals; "1 in N" sits next to the rare ones.

---

## 0. The short version

1. **About 5 to 8 times as many players own a Legendary, Mythic or Secret, and they stay
   rare.** One week after release, of players active in the last 7 days: **Epic 18.7%,
   Legendary 2.5%, Mythic 0.33%, Secret 0.02%** (your targets: Legendary 2-3%, Mythic 1% or
   less, the Secret far rarer). Day 30: Epic 31%, Legendary 7.4%, Mythic 0.9%, Secret 0.1%.
   Day 60: Epic 42%, Legendary 12.5%, Mythic 1.7%, Secret 0.2%. Today's economy, in the same
   model: Legendary 0.45% / 0.9% / 1.9%.
2. **Half of all Mystery blocks climb, and you see every climb.** The reveal now starts at
   Standard and has **5 presses**; each press can lift the block one tier. Final tier: Standard
   50%, Uncommon 40%, Rare 9.52%, Epic 0.42%, Legendary 0.05%, Mythic 0.01%. Pity: Rare by the
   10th, Epic by the 100th (was 150th), bought blocks included.
3. **Every block can surprise.** Even the Standard block can now give a Secret (1 in 1,000,000).
   Floors stay: each block still guarantees the rarity below its name (tested: dropping them
   moves every target by 0.3 points or less, and the floor is what makes "day 7 = Epic or
   better" true).
4. **10 lucky blocks a day from wins:** Rare, Mystery, Mystery, Uncommon, Mystery, Mystery,
   Rare, Mystery, Mystery, **Epic**. Then money and XP only until the reset, which moves to
   **08:00 UTC** for every daily thing (00:00 UTC is 8 pm in New York, mid-evening play).
5. **The first week hooks them:** any 7 login days within 14 days of joining. Day 2 an **Epic
   block**, day 7 a **Legendary block**. Later weeks: a Rare block on day 2, an Epic block on
   day 7. The 28-day track's first prize moves to login day 8.
6. **Everything costs less.** Top price **1,699 R$** (was 4,999). Mystery block **5 R$**
   (was 25). Grand Opening block **19 R$** (was 49). VIP **399 R$** (was 499) with a **free Rare
   block every day**. Starter Pack **19 R$** (was 99). Skip **4 / 9 / 15 R$** by time left (was
   19). Money packs from **25 R$**.
7. **Robux is the smart route:** buying with money costs about **2-3x** more for the everyday
   blocks (Mystery, Grand Opening, restock Rare) and **4.5-6.6x** more for the restock's Epic,
   Legendary and Mythic blocks. An hour of play earns about $7,300 (unchanged), the same money
   as 16-23 R$ of packs.
8. **The restock sells Rare or better**, with a Legendary about 4 times a day and a **Mythic
   block about every 5 days** (1,699 R$ or $4,990,000), announced in every server.
9. **The Grand Opening block:** Rare or better, Epic 10%, Legendary 1.6%, the **Firework Cue 6%
   and the Beta Cue 0.4%, capped at 1,000 and 100 copies**, so stretching the window to 30-45
   days never makes more. Beta guaranteed by your 1,000th block (was 400th) while any are left.
10. **No fake discounts:** the 30% release sale becomes a **launch bonus** (+30% money in every
    pack, 13 Mystery blocks for the price of 10) for the Grand Opening's days.

**Two calls are still yours** (my recommendation is the default if you just say "approved"):

- **Copy numbers** (12.4): under v4 a Legendary cue's #100 is gone by about day 11. Keep
  "#1-100" as a launch-month badge (recommended), or number the first 500 of Legendary and up.
- **Alts and the first week's Legendary block** (15): a login day counts only after a finished
  match (recommended, built now), and we watch the trades; or also hold the cues from first-week
  blocks for 7 days before they can be traded (more work and a save change, research 03).

---

## 1. The targets, and what the simulation gives

Share of players active in the last 7 days who own at least one (the designer's metric).

| | Week 1 target | Week 1 | Day 30 target | Day 30 | Day 60 target | Day 60 | Today's economy (week 1 / 30 / 60) |
|---|---|---|---|---|---|---|---|
| Epic | 15-22% (proposed) | **18.69%** | 25-35% | **31.07%** | 35-45% | **42.03%** | 2.64% / 5.61% / 10.10% |
| Legendary | 2-3% (designer) | **2.46%** | 6-9% | **7.43%** | 10-14% | **12.46%** | 0.45% / 0.92% / 1.85% |
| Mythic | 1% or less (designer) | **0.33%** | 0.7-1.2% | **0.92%** | 1.2-2% | **1.66%** | 0.06% / 0.13% / 0.25% |
| Secret | far rarer (designer) | **0.02%** | 0.05-0.15% | **0.11%** | 0.1-0.3% | **0.19%** | 0.01% / 0.01% / 0.03% |

**Why these day-30 and day-60 targets.** You approved counting any 7 login days (designer,
2026-10-08), knowing it lifts day 30 to about 7% and day 60 to about 12%. The shares grow over
time because players active at day 60 are mostly veterans, and almost everyone who stays a week
owns an Epic (the day-7 Legendary block is Epic or better). Epic becomes "you stuck around",
worth a few dollars; Legendary stays about 1 in 8 veterans; Mythic about 1 in 60; the Secret 1 in
500. These replace the old day-30 targets (Epic about 5%, Legendary about 1%, Mythic 0.5% or
less).

**How sure is this?** The model assumes a very strong game: about 28% of new players come back
the next day, more than Roblox's top 1% (22%; the median game keeps 10.3%,
[GameAnalytics 2026](https://www.gameanalytics.com/reports/2026-roblox-report)). With typical
retention (about 12% next day) every share is about half: week 1 Epic 12.4%, Legendary 1.7%,
Mythic 0.19%; day 30 Legendary 3.3%; day 60 Legendary 5.3%. The plan keeps the model's
standard assumption (every past plan used it) and says what to change after launch (section 16).
Run with today's numbers, the model matches the repo's own `tools/economy_model.py` (day 30:
Epic 5.61% against 5.73%, Legendary 0.92% against 0.88%).

---

## 2. What a player gets

The simulation's reference players play every day from launch at a 50% win rate (1,000 of each).
Free players spend 70% of their money on Mystery blocks and spins each day.

**The first 20 minutes, everyone** (the tutorial, then the group, the favorite and the three
codes): about **10 Mystery blocks, 2 Rare blocks** (the tutorial's first win and ROOFTOP), the
**Lucky 8 block**, Bronze's Standard block and about **$28,600** earned. About 6% already own an
Epic. A small spender who buys the 19 R$ Starter Pack also has the Starter block (Rare or
better).

**Chance to own one** (Epic / Legendary / Mythic / Secret):

| Player | Day 1 | Day 2 | Day 7 | Day 30 |
|---|---|---|---|---|
| Free, 30 min a day | 8% / 1% / 0.2% / 0% | 30% / 3% / 0.6% / 0% | 82% / 29% / 4% / 0.3% | 98% / 43% / 6% / 0.4% |
| Free, 1 h a day | 9% / 1% / 0.3% / 0% | 34% / 3% / 0.6% / 0% | 87% / 30% / 4% / 0.4% | 99% / 47% / 7% / 0.9% |
| Free, 3 h a day | 24% / 3% / 0.5% / 0% | 55% / 6% / 0.8% / 0.1% | 97% / 39% / 5% / 0.5% | 100% / 78% / 16% / 2.4% |
| VIP, 1 h a day | 11% / 1% / 0.1% / 0% | 32% / 3% / 0.4% / 0% | 87% / 31% / 4% / 0.8% | 100% / 50% / 8% / 1.2% |
| Small spender: VIP, 1 h, 500 R$ a month | 19% / 2% / 0.3% / 0% | 41% / 5% / 0.5% / 0% | 90% / 34% / 5% / 0.3% | 100% / 53% / 9% / 1.1% |
| Big spender: VIP, 3 h, 5,000 R$ a month | 53% / 9% / 1.1% / 0% | 86% / 19% / 3.2% / 0% | 100% / 68% / 13% / 0.9% | 100% / 97% / 35% / 4.3% |

**What arrives by day 30** (blocks received, money earned before spending):

| Player | Mystery | Rare | Epic | Legendary | Money earned |
|---|---|---|---|---|---|
| Free, 30 min a day | 179 | 45 | 5 | 1 | $338,000 |
| Free, 1 h a day | 287 | 83 | 6 | 1 | $571,000 |
| Free, 3 h a day | 553 | 122 | 30 | 2 | $1,489,000 |
| VIP, 1 h a day | 330 | 116 | 6 | 1 | $848,000 |
| Small spender | 396 | 120 | 7 | 1 | $998,000 (575 R$ spent) |
| Big spender | 1,345 | 173 | 45 | 2 | $3,348,000 (7,304 R$ spent; 103 Grand Opening blocks) |

- **Day 2** is the Epic block (login day 2): a 30-minute player's Epic chance jumps from 8% to
  30%. **Day 7** is the Legendary block: every 7-day player owns an Epic or better, and about
  29-39% own a Legendary.
- A free 1-hour player who keeps playing has about a coin flip at a Legendary by day 30, and
  about 1 in 14 a Mythic. The 3-hour player's daily Epic block (win 10) is the grind reward.
- These players never skip a day; most real players don't, which is why the whole-game shares
  in section 1 are far lower.

---

## 3. The Mystery block

### 3.1 How often it climbs (designer: "you pick the share, 1 in 3 to 1 in 2")

**Half end above Standard (50%).** Every one of them visibly climbs. Why half:
- It is the top of your range, and it matches Brawl Stars' Starr Drop, which also climbs 50% of
  the time ([02 §2.6](research-2026-10-08/02-brawl-stars-clash-royale.md)).
- The extra climbs go to Uncommon, which barely moves the rare outcomes: going from 42% to 50%
  above Standard changed week-1 Legendary owners by under 0.05 points.

| Final tier | Today | New |
|---|---|---|
| Standard | 68% | **50%** |
| Uncommon | 25% | **40%** |
| Rare | 6.7% | **9.52%** |
| Epic | 0.28% (1 in 357) | **0.42%** (1 in 238) |
| Legendary | 0.0196% (1 in 5,102) | **0.05%** (1 in 2,000) |
| Mythic | 0.0004% (1 in 250,000) | **0.01%** (1 in 10,000) |
| **Total** | 100% | **100%** |

**Per Mystery block, each cue rarity** (the cue cards' chance chip and the thumbnails use these):

| | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Total |
|---|---|---|---|---|---|---|---|---|
| Today | 61% | 33.83% | 5.0423% | 0.10872% (1 in 920) | 0.016644% (1 in 6,008) | 0.0021197% (1 in 47,176) | 0.0002163% (1 in 462,321) | 100% |
| New | 52.25% | 40.5736% | 6.79586% | 0.32688% (1 in 306) | 0.046268% (1 in 2,161) | 0.0066328% (1 in 15,077) | 0.0007592% (1 in 131,718) | 100% |

### 3.2 The presses (designer: "solve how Legendary and Mythic stay reachable")

- **The block starts as Standard on screen. 5 presses; each press either lifts it one tier or
  doesn't.** The server rolls the final tier first (by the weights above, with pity), then picks
  which presses climb, every choice equally likely. A Mythic climbs on all 5; a Legendary on 4
  of the 5; an Uncommon on 1 (it might be the last press).
- Today the first press shows a hidden, rolled starting tier, so only about 1 in 6 blocks
  visibly climb and a Standard start can't get past Epic. Starting at the bottom with one press
  per tier above it is how Brawl Stars and Clash Royale do it: Starr Drop 50%, Clash Royale's
  Lucky Chest 68% ([02 §2.6](research-2026-10-08/02-brawl-stars-clash-royale.md)).
- **Honest by construction:** a climb never fizzles or falls back, and the screen never shows
  a "chance per press" (it isn't a fixed number). It says "The result is decided when you open
  it; the presses reveal it" and shows the final-tier table, each tier block's cue odds, the pity
  counters and the live pity odds (Roblox's rules,
  [05 §1.3-1.5](research-2026-10-08/05-roblox-rules.md)).
- Chance to reach each tier: Uncommon or better 50%, Rare or better 10%, Epic or better 0.48%,
  Legendary or better 0.06%, Mythic 0.01%.

### 3.3 Pity

- **Rare by the 10th** Mystery block in a row below Rare (as today), **Epic by the 100th** below
  Epic (was 150th). With Epic-or-better at 0.48% a block, about 6 in 10 players who open 100
  Mystery blocks get there by pity. Pity never gives a Legendary.
- **Every Mystery block counts and gets pity, bought ones too.** `ECONOMY.md` 7.1 already says
  so, but the code gives a bought block the plain odds (`PlayerData.revealMystery`). v4 makes the
  code match. Roblox requires pity to be stated in numbers and the odds screen to show the
  guaranteed tier when it is live.

---

## 4. Every block's odds

Each tier block guarantees the rarity below its name (**floors kept**), and now every block can
reach the Secret. Rows add to exactly 100.

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Opens in |
|---|---|---|---|---|---|---|---|---|
| Standard | 72.5% | 25% | 2.4% | 0.09% (1 in 1,111) | 0.009% (1 in 11,111) | 0.0009% (1 in 111,111) | 0.0001% (1 in 1,000,000) | at once |
| Uncommon | 40% | 54% | 5.8% | 0.18% (1 in 556) | 0.018% (1 in 5,556) | 0.0018% (1 in 55,556) | 0.0002% (1 in 500,000) | 1 min |
| Rare | - | 68% | 31% | 0.9% (1 in 111) | 0.09% (1 in 1,111) | 0.009% (1 in 11,111) | 0.001% (1 in 100,000) | 5 min |
| Epic | - | - | 77.3% | 21% | 1.5% (1 in 67) | 0.18% (1 in 556) | 0.02% (1 in 5,000) | **30 min** |
| Legendary | - | - | - | 72% | 25% | 2.7% (1 in 37) | 0.3% (1 in 333) | 6 h |
| Mythic | - | - | - | - | 72% | 25% | 3% (1 in 33) | 12 h |
| Starter | - | - | 90% | 9% | 0.9% (1 in 111) | 0.09% (1 in 1,111) | 0.01% (1 in 10,000) | at once |
| Sky | 45% | 45% | 9.5% | 0.45% (1 in 222) | 0.045% (1 in 2,222) | 0.0045% (1 in 22,222) | 0.0005% (1 in 200,000) | at once |
| Lucky 8, Gift | the Rare row | | | | | | | at once; Gift 12 h |

Today, for comparison: Standard 75 / 23 / 1.99 / 0.009 / 0.0009 / 0.0001 / no Secret; Uncommon
40 / 54 / 5.95 / 0.045 / 0.0045 / 0.0005 / no Secret; Rare 70 / 29.6 / 0.35 / 0.045 / 0.0045 /
0.0005; Epic 78 / 19 / 2.6 / 0.36 / 0.04; Legendary 75 / 22 / 2.7 / 0.3; Mythic 75 / 22 / 3;
Starter 97 / 2.5 / 0.45 / 0.045 / 0.005; Sky 45 / 45 / 9.9 / 0.09 / 0.009 / 0.001 / no Secret.

**Why each row moved:**
- **Standard, Uncommon and Rare blocks** now reach every rarity with a real (tiny) chance: the
  Standard block's Epic is 10x today's, and the Secret is new. That gives the "what could I
  get" moment you asked for, at a cost too small to show in the targets.
- **The Epic block gives slightly less top end** (Legendary 2.6% to 1.5%, Mythic 0.36% to
  0.18%). About 9 times as many are opened in the first month (about 92,000 against 10,000 in
  the model: win 10 every day, login day 2, later day 7s, rank rewards), so each one carries a
  little less. Legendary owners still go up 5 to 8 times.
- **The Legendary and Mythic blocks** give their own rarity more often (22% to 25%).
- **The Starter block** gets a real Epic chance (2.5% to 9%) because it now costs 19 R$, and its
  pack must feel like the best deal in the game.
- **The Sky block** (Lucky Rain, built later) follows the Uncommon block: Epic 0.09% to 0.45%,
  and the Secret is new.

**Your idea (higher blocks keep the lower rarities, just much less), tested.** A Rare block with
3% Common, an Epic block with 0.5% Common and 2.5% Uncommon, and so on, changed every target by
0.3 points or less (sample run in this session). So the choice is about feel, and the floors win:
- "A Legendary block is Epic or better" is your day-7 promise, and it is only true with floors.
- A block bought in the restock for Robux must never give a Common; with kids that reads as a
  scam.
- Brawl Stars and Clash Royale never drop below the drop's own rarity.

**The spin reel** (designer, 2026-10-08: rare cues pass by more often, with safeguards). The
reel's look is the GUI session's; the rules are:
1. Every reel shows only cues from that block's own pool, and the pool includes every rarity it
   can drop (so the Standard block's reel can show its Secret).
2. Each spin gets **one showcase tile** (an Epic-to-Secret cue from that block's pool), placed
   in the first two-thirds of the strip, never within 8 tiles of where the reel stops. Every
   other tile is drawn at the real odds.
3. The showcase tile prints its odds on itself ("SECRET · 1 in 1,000,000").
4. The reel never slows near a rare tile, and win effects play only for Rare or better.
5. Under the reel: "The reel shows what this block can drop. Your chances are under Odds."
6. No slot-machine looks (lever, 7s, "JACKPOT"): a gambling look risks a Moderate rating, which
   means no Roblox Kids.

Roblox's rules don't mention reels. In Roblox's own policy thread, a developer called rare items
shown more often than their odds "clearly deceptive", and staff never answered
([DevForum #16](https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622/16)).
The safeguards keep it honest about what each block can give. If Roblox ever rules against it,
the showcase tile turns off with one Config switch and the rest stays.

---

## 5. The 10-step daily win track

| Win of the day | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11+ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Block | **Rare** | Mystery | Mystery | Uncommon | Mystery | Mystery | **Rare** | Mystery | Mystery | **Epic** | money and XP only |

**Why this shape:**
- **Win 1 is a Rare block**, your "guaranteed better block early" ask. It is the biggest daily
  hook: Brawl Stars says rewarding the 3 first wins (instead of 8) "stopped the decline of DAU"
  ([Supercell](https://supercell.com/en/games/brawlstars/blog/community/2025-in-review-franks-blog-post/)).
  The tutorial's first win is the first step of day 1, so "the first win ever gives a
  guaranteed Rare block" stays true with no special case.
- **Six Mystery blocks** keep Mystery blocks the main way to get blocks, with the climbs.
- **Steps 4 and 7 are known blocks** (Uncommon, Rare) so the track never feels like six coin
  flips in a row.
- **Win 10 is an Epic block**: a real daily goal (about 20 matches, nearly 3 hours). It is the
  grinder's reward: a 3-hour player reaches it about 3 days in 4, so about 22 Epic blocks a
  month. Making it a Rare block instead takes 0.4 points off day-30 Legendary owners (tested:
  7.43% to 7.04%); I kept the Epic block.
- **Clash Royale ran exactly this shape** in April 2025: rewards for the first 10 wins, then
  currency only ([Supercell](https://supercell.com/en/games/clashroyale/blog/release-notes/april-update/)).
- Brawl Stars no longer rewards "the 1st, 4th and 8th wins"; since late 2025 it rewards each of
  the first 6 ([02 §0](research-2026-10-08/02-brawl-stars-clash-royale.md)).

**The anti-farm rules carry over unchanged:** a win advances the track exactly when today's rules
would have dropped a block. So the first 10 PC wins a day count, disguised-bot wins count up to
20 a day, at most 3 steps a day come from beating the same account, the loser must have played 5
real matches, and solo never counts. VIP gets no extra steps (designer, 2026-10-08: VIP's perk is
a daily Rare block instead).

**The reset is 08:00 UTC, for every daily thing** (the track, the login day, playtime, VIP's
block, the Lucky Shot, and the anti-farm "same day" limits). Today's 00:00 UTC is 8 pm in New
York and 5 pm in Los Angeles, the middle of US evening play, so one sitting can collect two days.
08:00 UTC is 3-4 am in New York, 5 am in Brazil, 8-10 am in Europe. Brawl Stars resets at
08:00 UTC ([wiki](https://brawlstars.fandom.com/wiki/Daily_Streak)). No minimum gap between two
claims: a session that crosses 08:00 UTC can claim two days, which only moves one reward
earlier (my call; simpler for kids).

**The bar above the hotbar** (the GUI session's): the next step's block, "Lucky Blocks today
7/10", and the time to the reset; after win 10, "10/10 · wins pay money and XP today".

---

## 6. Free rewards

### 6.1 Login: the first week, then later weeks

| Login day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Today (every week) | $5,000 | 1 Mystery | $10,000 | 2 Mystery | $15,000 | 3 Mystery | Rare block + 2 spins |
| **First week** (once ever) | $5,000 + 1 Mystery | **Epic block** | $10,000 | 2 Mystery | Rare block | 3 Mystery | **Legendary block** + 2 spins |
| **Later weeks** | $5,000 | Rare block | $10,000 | 2 Mystery | $15,000 | 3 Mystery | **Epic block** + 2 spins |

- **First week = your first 7 login days within 14 days of joining**, in a row or not (designer,
  2026-10-08). After 7 claims, or after day 14, the later-weeks loop takes over. Kids miss days;
  HoYoverse and AFK Arena count login days inside a window, and Brawl Stars and Adopt Me forgive
  misses ([03 Rule 5](research-2026-10-08/03-login-retention.md)).
- Later weeks keep today's streak: a missed day restarts the week, except one free miss a week.
- **Day 2's Epic block** is the day-1 retention hook (Brawl Stars gives a whole brawler on day
  2). Show the 7-day strip at the end of the first session so it reads as a promise.
- **Day 7's Legendary block** (your ask). Later weeks drop to an Epic block, about Anime
  Vanguards' step-down (its day 7 goes from 100 to 25 rerolls after the first week,
  [wiki](https://animevanguards.fandom.com/wiki/Daily_Rewards)).
- **A login day counts once you finish one match that day** (any mode, PC included). This stops
  an alt from collecting the first week's Epic and Legendary blocks by just joining.
- VIP's extra spin a day stays (+1).

### 6.2 The 28-day track (total login days, never resets)

| Login day | Today | New |
|---|---|---|
| 7 | Rare block | - |
| **8** | - | **Rare block** |
| 14 | 2 Rare blocks | 2 Rare blocks |
| 21 | 2 Rare blocks | 2 Rare blocks |
| 28 | Epic block | Epic block |

The first prize moves from day 7 to **day 8**: day 7 already has the Legendary block, and
Roblox's D7 counts a return on the 8th day, so day 8 needs its own reason
([03 Rule 3](research-2026-10-08/03-login-retention.md)).

### 6.3 Playtime gifts (minutes in a day, across sessions)

| Today | 10 min $2,000 | 30 min 1 Mystery | 60 min 2 Mystery + 1 spin | 90 min $10,000 | 120 min Rare block |
|---|---|---|---|---|---|
| **New** | **5 min $1,000** | **15 min 1 Mystery** | **30 min 1 Mystery** | **45 min 1 Mystery** | **60 min Rare block + 1 spin** |

Everything lands inside the first hour: Roblox's ranking counts playtime only up to 60 minutes a
day, and most sessions are short ([Discovery](https://create.roblox.com/docs/discovery)). A
1-hour player gets more than today (a Rare block instead of $1,000); a 2-hour player gets the
same blocks as today and $11,000 less money.

### 6.4 The Daily Challenge: Lucky Shot and Golden Shot (numbers now; built later)

Your concept screens, priced for v4. Not built yet; the numbers go in `ECONOMY.md` and Config
now, and the feature gets its own brief.

| Ring | Miss | Grey | Blue | Red | Gold |
|---|---|---|---|---|---|
| Lucky Shot (free, once a day) | $500 | $1,500 | $3,000 | 1 Mystery block | 1 Rare block |
| Golden Shot (**15 R$**, once a day; the v3 plan said 29) | $5,000 | $7,500 + Uncommon block | Rare block | Rare block + $10,000 | 2 Rare blocks + $25,000 |

At an average player's rings (Miss 30%, Grey 30%, Blue 20%, Red 12%, Gold 8%; the v3
simulation's), the Golden Shot is worth about 26 R$ on the value ladder (section 9), so 15 R$ is
a good daily deal. Its top prize stays 2 Rare blocks, never an Epic block (the v3 plan's rule): a
skilled player can aim for gold every day.

### 6.5 Lucky Rain and the stay bonus (numbers now; built later)

- **Lucky Rain** (the v3 plan's rules): in servers with 4+ players, a Sky block falls about
  every 30 minutes (1 minute sooner for each match finished there, never under 15 minutes);
  95% a Sky block, 5% a Rare block; everyone who reaches it in 90 seconds gets one; **3 a day**.
  Players seated in a match can't reach it, so the model counts about 0.4 an hour of play (the
  v3 plan's figure).
- **Stay bonus:** +1% match money every 2 minutes in the server, up to +25% at 50 minutes;
  match money only; it pauses when idle and resets on leaving.

### 6.6 Group, favorite, invites, codes, the first-leave gift

| Reward | Today | New |
|---|---|---|
| Join the group | 3 Mystery blocks (+10% match money while a member) | unchanged |
| Favorite the game | $10,000 + 1 Mystery block in Config; you chose a Lucky 8 block (2026-10-08) | $10,000 + **Lucky 8 block** (Config made to match your decision) |
| Invite (friend's first win) | a Rare block each; the inviter once ever | unchanged |
| First leave | a Gift block (Rare row, 12 h) | unchanged |
| WELCOME / 8BALL / ROOFTOP / RELEASE | $5,000 + Mystery / $2,500 / Rare block / 3 spins | unchanged |
| LIKES1K ... LIKES100K | as today | unchanged; word them as thanks for a milestone, never "like to unlock" ([05 §5](research-2026-10-08/05-roblox-rules.md)) |

These already sit at the right size: together they are about a day's worth of blocks once. The
favorite is reported by the client (Roblox can't check it); one $10,000 + Lucky 8 block per
account is a small risk.

### 6.7 VIP's daily Rare block (designer, 2026-10-08)

A Rare block each day a VIP logs in, claimed on Free Reward. Where PolicyService restricts paid
random items, it becomes **$5,000** instead, and the pass description says so. It is never
better odds: the same Rare row as every Rare block.

What it costs us under Roblox's rules ([05 §3.3](research-2026-10-08/05-roblox-rules.md)): VIP
becomes a paid random item, so the VIP card shows the Rare block's odds, and VIP can no longer
be promoted on Roblox's Buy Robux page (a pass promoted there "cannot grant paid random items").

---

## 7. Rank rewards

Money for each division (`Ranks.Rewards.Step`) is unchanged. Each tier's division I:

| Tier (wins to reach) | Today | New |
|---|---|---|
| Bronze (1) | $2,500 + Mystery, and a Standard block at once (the tutorial's) | unchanged |
| Silver (21) | $5,000 + Rare | unchanged |
| Gold (66) | $10,000 + 2 Rare | unchanged |
| Platinum (136) | $20,000 + 3 Rare | $20,000 + **Epic** |
| Diamond (232) | $50,000 + Epic | $50,000 + **2 Epic** |
| Expert (393) | $100,000 + 2 Epic | $100,000 + **Legendary** |
| Veteran (675) | $200,000 + 3 Epic | $200,000 + **Legendary + Epic** |
| Master (1,180) | $400,000 + Legendary | $400,000 + **2 Legendary** |
| Grandmaster (2,025) | $750,000 + 2 Legendary | $750,000 + **Mythic** |
| Reyes (3,075) | $2,000,000 + Mythic | $2,000,000 + **2 Mythic** |

Why: in a game where a week of logging in brings a Legendary block, today's first Legendary block
at Master (about 3.5 months at 3 hours a day) is far too stingy for the most skilled players.
Expert (about a month at 3 hours a day) now pays the first one. Rank rewards stay a small source
(2-4% of Epic-and-up copies) because few players climb that far.

---

## 8. The shop

### 8.1 Money prices (match money stays about $7,300 an hour of Classic)

| Item | Today | New | Hours of play |
|---|---|---|---|
| Mystery block | $4,900 | $4,900 | 0.7 |
| 10 Mystery blocks | $44,100 | $44,100 | 6 |
| Grand Opening block (1 / 3 / 10) | $49,000 / $139,000 / $441,000 | **$24,900 / $69,900 / $219,000** | 3.4 for one |
| Restock Uncommon | $14,900 (3 a restock) | **gone** (a Mystery block beats it) | - |
| Restock Rare | $34,900 (1 a restock) | **$19,900** (2 a restock) | 2.7 |
| Restock Epic | $349,000 | **$199,000** | 27 |
| Restock Legendary | $3,490,000 | **$1,490,000** | 205 |
| Restock Mythic | never sold | **$4,990,000** | 686 |
| Ability spin | $17,500 | **$12,500** | 1.7 |

**Why match money stays at $7,300:** nothing in the targets needed it to move; the money prices
moved instead. The stay bonus (section 6.5) adds up to +25% for long sessions.

### 8.2 Every Robux product

| Product | Today R$ | New R$ | What it gives (new) |
|---|---|---|---|
| VIP (pass) | 499 | **399** | 2x money, no timers, +1 spin a day, Skip and Auto Spin on the spin screen, the VIP restock slot, the VIP Cue and tag, **a Rare block every day** (designer, 2026-10-08) |
| VIP welcome offer | 249 | **199** | VIP at half price, first 24 hours (and one comeback day at day 7) |
| Starter Pack | 99 | **19** | the Starter block (Rare or better) + **$25,000** (was $75,000) + 1 hour of 2x money; once, first 7 days |
| Money packs 1-7 | 49 / 99 / 249 / 499 / 999 / 2,499 / 4,999 for $9,000 / $19,500 / $52,500 / $110,000 / $235,000 / $625,000 / $1,300,000 (bonus 0 / 7 / 15 / 20 / 28 / 36 / 42%) | **25 / 49 / 99 / 199 / 399 / 799 / 1,699** | **$8,000 / $16,500 / $35,000 / $75,000 / $160,000 / $335,000 / $760,000** (bonus 0 / 5 / 10 / 18 / 25 / 31 / 40%); about 1.7x today's money per Robux |
| Mystery 1 / 10 | 25 / 229 | **5 / 45** | 1 / 10 Mystery blocks (13 during the launch bonus) |
| Grand Opening 1 / 3 / 10 | 49 / 129 / 349 | **19 / 49 / 149** | Grand Opening blocks, during its window (the 3 and 10 save 14% and 22% against buying one at a time: 57 and 190) |
| Restock Rare / Epic / Legendary | 99 / 999 / 4,999 | **15 / 99 / 599** | that restock block, while in stock (the Rare one was never created on Roblox: its id is 0, so it gets made now) |
| Restock Mythic | - | **1,699 (new)** | the restock Mythic block, while in stock |
| Skip | 19 (flat) | **4 / 9 / 15 by time left (2 new)** | finishes one block's timer: 30 min or less left 4 R$, 6 h or less 9 R$, more 15 R$ |
| Money Party | 199 | **49** | +100% match money for everyone in the server, 15 minutes |
| Ability spins 1 / 5 / 10 / 50 | 15 / 50 / 100 / 449 | **9 / 39 / 75 / 299** | ability spins (one at a time: 45 / 90 / 450, so the bundles save 13% / 17% / 34%) |
| Lucky Spins 1 / 3 | 49 / 129 | **25 / 65** | Lucky Spins (no Commons; 3 one at a time: 75) |
| Ability slot 2 / 3 (passes) | 59 / 99 | **49 / 79** | the second / third ability slot |
| Golden Shot | - | **15 (later, with its feature)** | section 6.4 |
| Release sale copies (Pack4Sale-Pack7Sale, VipSale, Mystery10Sale) | 349-3,499 | **retired** | never offered again; kept on Roblox (never deleted) so an old receipt still pays |

**The most expensive single item is 1,699 R$** (the Mythic block and the biggest pack): it fits
one $19.99 phone Robux pack (1,700 R$). VIP at 399 fits one $4.99 pack (400 R$); about
two-thirds of Robux is bought on phones and consoles
([01 §6](research-2026-10-08/01-roblox-purchase-psychology.md)).

**The first-pack double goes.** None of 15 top Roblox games has one, it nudges a kid toward the
biggest pack first, and the 19 R$ Starter Pack now does its job (the first purchase)
([01 §1](research-2026-10-08/01-roblox-purchase-psychology.md)).

**Bundle savings and "Best value" stay true.** A bundle's saving is shown against buying the
same thing one at a time today ("57 R$ one by one"), never as a crossed-out former price
([05 §3.4](research-2026-10-08/05-roblox-rules.md)). The "Best value" mark moves from pack 6 to
pack 7, the pack that really gives the most money per Robux (my call; today pack 7 already
beats pack 6).

**The launch bonus replaces the 30% release sale** (designer, 2026-10-08). For the Grand
Opening's days: every money pack gives **+30% money**, and 10 Mystery blocks come as **13**. It
is shown as "Launch bonus +30%" with the real end date and ends on that date. A "30% off" a
price nobody was ever charged is a fake former price under Roblox's deception rule and, from
1 Nov 2026, consumer law ([05 §3.4](research-2026-10-08/05-roblox-rules.md)). It needs no new
products: the receipt adds the bonus while the window is open (10 minutes of grace).

**The skip by time left** (designer, 2026-10-08). The skip button shows the price for the time
left right now. Still the cheapest skip per hour of any game found: Steal An Egg charges 9 R$
for 15 minutes and 299 R$ for 12 hours
([API](https://apis.roblox.com/developer-products/v2/universes/10563114921/developerproducts?limit=50)).
VIP keeps no timers at all.

**Money Party at 49 R$** makes it a cheap gift to the whole server (the buyer's name is
announced, as today). **Spins** come down 22-50% and the **ability slots** about 20%; the ability
spin odds and pity don't change (the ability economy has no rarity targets; spins stay a money
sink in the model).

### 8.3 Robux against money (designer: "about 3x, you set the final ratio")

How many times more the money route costs than buying directly with Robux (money at the biggest
pack's rate; at the smallest pack add about 40%):

| Item | Money | Robux | Money route costs |
|---|---|---|---|
| Mystery block | $4,900 | 5 | 2.2x |
| Grand Opening block | $24,900 | 19 | 2.9x |
| Restock Rare | $19,900 | 15 | 3.0x |
| Restock Epic | $199,000 | 99 | 4.5x |
| Restock Legendary | $1,490,000 | 599 | 5.6x |
| Restock Mythic | $4,990,000 | 1,699 | 6.6x |

**The ratio: about 2-3x for the everyday blocks, rising to about 6x for the rarest known blocks.**
The rise copies the top Roblox games: their Robux prices span about 100x while money prices span
millions of times, so Robux is near the money price for cheap things and far better for rare ones
([01 §5](research-2026-10-08/01-roblox-purchase-psychology.md)). It makes the money route to a
Mythic block a long-term dream while Mystery blocks stay a fair money buy.

**Buying money is clearly better than grinding:** an hour of play ($7,300) is 16-23 R$ of packs.
In other top games an hour of grinding costs 20-100 R$ (Kick a Lucky Block sells an hour of
income for 67 R$; [01 §5c](research-2026-10-08/01-roblox-purchase-psychology.md)).

### 8.4 The restock shop and the Mystery block: both worth buying

The restock changes every 10 minutes, the same in every server (as today): 3 slots, plus a fourth
for VIP.

| Slot odds | Uncommon | Rare | Epic | Legendary | Mythic | Total |
|---|---|---|---|---|---|---|
| Today, each slot | 62% | 36.6% | 1.35% | 0.05% | - | 100% |
| **New, each slot** | - | **87%** | **12%** | **0.95%** | **0.05%** (1 in 2,000) | 100% |
| Today, VIP slot | - | 96% | 3.85% | 0.15% | - | 100% |
| **New, VIP slot** | - | **80%** | **17%** | **2.8%** | **0.2%** (1 in 500) | 100% |

- **How often:** an Epic in about 1 restock in 3; a Legendary about 4 times a day; a **Mythic
  block about every 5 days** (VIP's slot about every 3.5 days).
- **Stock per player per restock:** today Uncommon 3, Rare 1, Epic 1, Legendary 1; new Rare 2,
  Epic 1, Legendary 1, Mythic 1. Money and Robux share the same stock, so "occasional" stays true.
- **The VIP slot rolls from its own richer table** (as today). Every block in it has the same
  odds as anywhere else, so it shows VIPs more good blocks without giving them better odds.
- **A Legendary or Mythic block in the restock is announced in every server** ("A MYTHIC block is
  in the restock for 9:41!"). Mythic blocks were never sold before; that rule goes (your ask).
- **Publish the slot odds** on the restock screen (Roblox never answered whether it must; it is
  harmless and honest).

**Are both worth buying?** Yes:
- The Mystery block is the cheap gamble: worth about 6.1 R$ on the value ladder for 4.5-5 R$
  (1.2-1.35x), with the climbs.
- A restock block is a known block, so it costs a little more for what it gives: Rare 1.07x,
  Epic 1.2x, Legendary 1.45x, Mythic 2.4x on the ladder. The rare ones are better deals because
  they are rare and capped at 1,699 R$.
- The Uncommon restock slot is gone because a Mystery block beat it at any price (it gave less
  than half a Mystery block's worth for twice the money).

### 8.5 The Grand Opening block

| | Uncommon | Rare | Epic | Legendary | Mythic | Secret | Firework Cue | Beta Cue | Total |
|---|---|---|---|---|---|---|---|---|---|
| Today | 56.35% | 37.45% | 2.5% | 0.35% | 0.046% | 0.004% | 3% | 0.3% | 100% |
| **New** | - | **81.84%** | **10%** | **1.6%** (1 in 63) | **0.15%** (1 in 667) | **0.01%** (1 in 10,000) | **6%** | **0.4%** (1 in 250) | 100% |

- **Rare or better, never an Uncommon** (your ask), at **19 R$**, 3 for 49, 10 for 149. The
  bundles save 14% and 22%, a little more than most games (0-5% for 3, 15-20% for 10:
  [01 Rule 3](research-2026-10-08/01-roblox-purchase-psychology.md)). With money: $24,900 (3.4
  hours of play), 3 for $69,900, 10 for $219,000.
- **About 1,000 Firework and 100 Beta Cues (your ask), made certain by caps.** You'll start at
  publish and may stretch it to 30-45 days (designer, 2026-10-08). Without caps that would make
  anywhere from about 600 to 5,700 Firework Cues, depending on the window and on how many
  players come. With caps of **1,000 and 100**, once a cue's copies are all found its row's
  share goes to Rare, the odds update everywhere at once, and the card counts down ("Beta Cue ·
  23 of 100 left"; copies read "#4 of 100", like your concept's "#4 of 20").

  | Window | Strong retention, with caps | Typical retention, with caps | Without caps (strong / typical) |
  |---|---|---|---|
  | 21 days | Firework 1,000 (all found day 21), Beta 90 | Firework 635, Beta 53 | Firework 1,031 / 635, Beta 90 / 53 |
  | 30 days | Firework 1,000 (day 21), Beta 100 (day 23) | Firework 1,000 (day 26), Beta 98 | Firework 2,124 / 1,319, Beta 178 / 98 |
  | 45 days | Firework 1,000 (day 21), Beta 100 (day 23) | Firework 1,000 (day 26), Beta 100 (day 31) | Firework 5,722 / 3,378, Beta 514 / 248 |

- **The Beta Cue stays the rarest cue in the game:** 100 copies ever. The Secret passes 100
  copies around day 33 in the model and keeps growing.
- **Guarantee: your 1,000th Grand Opening block is the Beta Cue if you have none and any are
  left** (was the 400th). At 0.4% a block, 98% of players who open 1,000 get one before the
  guarantee. At the new price, 1,000 blocks cost about 14,900 R$ (about $186), in line with your
  "$100 or more" for the rarest cue; keeping the 400th would make it about 5,960 R$ ($74). Today
  the 400th costs 13,960 R$ ($174).
- **Per-player odds (Roblox's one-instance rule):** a player who owns the Firework or Beta Cue
  can't get another, so their odds show that row as Rare. Today's code re-rolls quietly, which
  makes the shown odds wrong for owners ([05 §1.4](research-2026-10-08/05-roblox-rules.md)).
- It is the launch gift: worth about 88 R$ on the value ladder plus the Uniques, for 14.9-19 R$.

**Kids can't see the game at publish** until Roblox's evaluation (250 engaged 16+ players), or
the 50,000 R$ fast review. You chose to start at publish and stretch the window if needed
(designer, 2026-10-08); the caps make that safe.

### 8.6 The Starter Pack (designer: "under 20 R$, you pick what goes in it")

**19 R$: the Starter block (Rare or better: Epic 9%, Legendary 0.9%) + $25,000 + 1 hour of 2x
money.** Once, in the first 7 days. Worth about 150 R$ (about 8x its price; Roblox's guide asks
for about 90% off, [starter pack design](https://create.roblox.com/docs/production/game-design/starter-pack-design)).
Adopt Me sells its starter pack at 9 R$, and Pet Simulator 99 starts at 4 R$
([01 §1](research-2026-10-08/01-roblox-purchase-psychology.md)). Where PolicyService restricts
paid random items it has no block: **$40,000 + the hour of 2x money**.

---

## 9. The value ladder (designer: "a Robux value ladder per rarity")

What one cue of each rarity is worth to the price list, in R$ (and in dollars at the phone price
of Robux, 400 R$ for $4.99):

| | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Ladder | 1 R$ | 3 R$ | 30 R$ ($0.37) | 250 R$ ($3) | 1,500 R$ ($19) | 6,000 R$ ($75) | 50,000 R$ ($624) |
| Your feel | | | | "a few dollars" | | "tens of dollars" | "$100 or more" |
| Your feel in R$ (the band I checked against) | | | 8-80 | 80-400 | 400-2,400 | 800-8,000 | 8,000-80,000 |
| Cheapest way to pull one (that rarity or better) with Robux, new | | | **16** (Grand Opening), 47 (restock Rare) | **127** (Grand Opening), 436 (restock Epic) | **847** (Grand Opening), 1,699-2,139 (restock) | **6,068** (restock Mythic) | **56,633** (restock Mythic) |
| The same, today | | | 86 | 1,203 | 8,725 | 69,800 | 872,500 |
| Peers | | | | | Adopt Me 825, MM2 1,538-2,000 | PS99 Huge 2,116-3,175 | MM2 Godly 38,462-50,000 |

Every new cheapest pull sits inside your feel; today's are 1 to 11 times above it. After the
Grand Opening ends, the cheapest Epic is the restock Epic block (436 R$) and the cheapest
Legendary the restock Mythic block (1,699 R$), still inside the bands.

Peers are from [04 §4.2](research-2026-10-08/04-value-and-trading.md). The game never supports
real-money trading; these are only for pricing.

**Every product against the ladder** (worth of what it gives / its price):

| Product | Price | Worth | Worth / price |
|---|---|---|---|
| Mystery block (10 for 45) | 4.5 R$ | 6.1 R$ | 1.35 (1.75 during the launch bonus) |
| Grand Opening (10 for 149) | 14.9 R$ | 88 R$ + the Uniques | 5.9 (the launch gift) |
| Restock Rare / Epic / Legendary / Mythic | 15 / 99 / 599 / 1,699 R$ | 16 / 119 / 867 / 4,080 R$ | 1.07 / 1.20 / 1.45 / 2.40 |
| Starter Pack (the block alone) | 19 R$ | 73 R$ | 3.9 (with the money, about 8) |
| Golden Shot | 15 R$ | about 26 R$ | 1.7 |

Nothing sells below its worth on the ladder, so no product is a rip-off, and the gamble (Mystery)
is a little better than the known blocks, as you asked.

---

## 10. Timers and the skip

| Block | Today | New |
|---|---|---|
| Standard | at once | at once |
| Uncommon | 1 min | 1 min |
| Rare | 5 min | 5 min |
| Epic | 1 h | **30 min** |
| Legendary | 6 h | 6 h |
| Mythic | 12 h | 12 h |
| Gift | 12 h | 12 h |
| Starter, Sky, Lucky 8, Grand Opening, Mystery | at once | at once |

A won Mystery block still lands on the timer of the tier it became; a bought block and every VIP
block open at once (as today). Skip: section 8.2.

---

## 11. Values and trading

| Item | Today | New | Why |
|---|---|---|---|
| Sell-back | Common $150, Uncommon $400, Rare $1,500, Epic $25,000, Legendary $250,000, Mythic $2.5M, Secret $25M | **unchanged** | Selling removes copies, which protects value; no sell-and-rebuy loop exists (a Legendary sells for a sixth of a restock Legendary block) |
| Finder's money (first time you get each cue) | Common $500 ... Secret $500,000 | **unchanged** | Paid once per cue ever; faster finding just brings it sooner |
| Index rows | Common $10,000, Uncommon $25,000, Rare $75,000, Epic $250,000 | **unchanged** | The Epic row (all 9 Epic cues) still takes months |
| Trade warning's block values (`Trade.BlockExists`) | fixed: Standard 100,000 ... Mythic 30 | **worked out live** from each block's odds row and the live copies of each rarity | With supply growing about 5x between day 30 and day 60, fixed numbers go stale within weeks. Until counters load, a fallback table: Standard 160,000, Uncommon 140,000, Rare 73,000, Epic 11,000, Legendary 1,600, Mythic 400, Mystery 120,000, Grand Opening 15,000, Starter 19,000, Sky 115,000, Lucky 8 and Gift 73,000 (the model at day 30) |

**The bots' cue table** (`Config.BotCues`, the share of bots at each rank showing an Epic-or-better,
Legendary-or-better and Mythic-or-better cue), from the simulation's real players at day 60:

| Tier | Today | New |
|---|---|---|
| Bronze | 5% / 0.8% / 0.1% | 25% / 4.5% / 0.5% |
| Silver | 10% / 1.5% / 0.2% | 80% / 24% / 3% |
| Gold | 20% / 3% / 0.4% | 95% / 36% / 4.5% |
| Platinum | 34% / 6% / 0.8% | 98% / 45% / 6% |
| Diamond | 50% / 10% / 1.3% | 99% / 58% / 9% |
| Expert | 70% / 16% / 2% | 99% / 75% / 15% |
| Veteran | 88% / 26% / 4% | 99% / 85% / 25% |
| Master | 97% / 40% / 6.5% | 99% / 92% / 35% |
| Grandmaster | 99% / 58% / 11% | 99% / 96% / 50% |
| Reyes | 99% / 70% / 15% | 99% / 98% / 65% |

(Master and up are extrapolated: almost nobody reaches them in 60 days.)

**Value lessons applied:** the number of copies of each exact cue is what sets its trade worth
([04 §1.1](research-2026-10-08/04-value-and-trading.md): Pet Simulator 99 Huges whose copies grew
1.5x lost a median 27%). So, for later updates: make rarities easier by **adding new cues and
retiring old ones**, not by raising odds on the same seven Legendaries.

---

## 12. The simulation

`economy_v4_sim.py` uses the population model of `luckyblock_sim.py` and `tools/economy_model.py`
unchanged: 1,700 new players on day 0, growing 5.5% a day for 40 days; 55% play one day; the same
lifetimes, minutes, win rates and payers (6% of those who stay a week, 1.2% of the rest; budgets a
median of 450 R$ a month). v4 assumes cheaper prices bring 1.5x as many payers with the same
budgets. `--plan today` reproduces today's economy (day 30 Legendary 0.92%; the official model
says 0.88%).

### 12.1 Cues entering the game per day (average of the week before)

| | Rare | Epic | Legendary | Mythic | Secret | Firework | Beta |
|---|---|---|---|---|---|---|---|
| Day 7 | 5,366 | 395 | 44 | 5.6 | 0.3 | 27 | 1.1 |
| Day 30 | 30,322 | 2,565 | 372 | 43 | 5.1 | 0 | 0 |
| Day 60 | 94,080 | 8,232 | 1,205 | 140 | 13 | 0 | 0 |

(The game grows to about 5,000 players online by day 45-60 in the model.)

### 12.2 Where the Epic-and-up copies come from (day 30)

Share of all copies in the game at day 30 (42,218 Epic, 6,092 Legendary, 678 Mythic and 77
Secret copies; the Secret column is small, so it is noisy):

| Source | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|
| Login + 28-day track | 43% | **57%** | **57%** | 50% |
| Win track | 26% | 17% | 18% | 17% |
| Playtime | 8% | 6% | 6% | 5% |
| Grand Opening | 5% | 5% | 5% | 5% |
| Mystery blocks bought with money | 5% | 5% | 6% | 14% |
| Group, favorite, invites, codes, gift | 5% | 4% | 2% | 3% |
| Rank rewards | 3% | 2% | 3% | 4% |
| Lucky Rain, Lucky Shot, Golden Shot | 2% | 2% | 1% | 0% |
| Restock (money and Robux) | 2% | 1% | 2% | 1% |
| Starter Pack, VIP's daily block, Mystery for Robux | 1% | 1% | 0% | 1% |
| **Total** | **100%** | **100%** | **100%** | **100%** |

**The login track is the biggest Legendary and Mythic source, on purpose:** it is your day-7
Legendary block, given to everyone who plays 7 days. That is not a leak (it rewards coming back,
not a trick), but it is the handout pattern the value research warns about (Adopt Me's 2D Kitty
lost 73% in a free 1.5% box), and it is the one prize an alt account could farm (section 15). If
Legendary trade values sag after launch, this is the lever: lower the first-week block's top end,
or hold its cue for 7 days before it can be traded.

**Robux doesn't flood the game:** everything bought with Robux (Mystery, restock, the Starter
Pack, VIP's block and the Robux share of the Grand Opening, about a quarter) adds up to about
2-3% of each rarity's copies (my estimate from these numbers). Most Grand Opening blocks are
bought with money.

### 12.3 The Grand Opening's Uniques

Firework Cue: 1,000, all found by day 21 with strong retention. Beta Cue: 90 when the window
is 21 days, 100 when it is 30 days or longer. See 8.5 for each window length.

### 12.4 Copy numbers #1-100 (re-timed; nothing changed)

The GUI session numbers the first 100 copies of every Rare-or-rarer cue (approved 2026-10-08,
timed with the old model). The day each cue's #100 is gone:

| | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|
| Old model (the approval) | day 1 | day 13 | day 29 | day 49 | about 3 months |
| v4, strong retention | day 1 | **day 4** | **day 11** | **day 21** | **day 33** |
| v4, typical retention | day 1 | day 5 | day 15 | day 30 | day 50 |

So "#12/100" becomes a launch-month badge for every rarity. That still carries value: Team
Fortress 2 numbered only #1-100 and traders paid extra only there; Roblox Limiteds ask about 1.6x
for #2-100 ([04 §3](research-2026-10-08/04-value-and-trading.md)). **Nothing changes without
your say.** If you'd rather the numbers last longer, one option is "first 500" for Legendary and
up.

---

## 13. Roblox's rules: what this plan does about them

From [05](research-2026-10-08/05-roblox-rules.md) (no August 2026 change to the paid random
items rules exists; the last is 26 May 2026):

- **Odds:** every block, the Mystery tiers, the restock slots and the Grand Opening show % that
  add to 100, per cue, under a button labelled "Odds & Details", with "1 in N" beside them.
- **Pity** stated in numbers, with the live guaranteed tier shown.
- **Paid random items** are: every block bought (Robux or money), the skip, the Starter Pack,
  VIP (its daily block), the Golden Shot, spins. Where `PolicyService` says paid random items are
  restricted: no block, skip, spin or Golden Shot purchase; VIP's block becomes $5,000; the
  Starter Pack becomes $40,000 + the 2x hour; free blocks and rewards still work.
- **Not Listed:** every developer product that holds a random item, so it can't be bought
  outside the game without odds. Passes are always listed, so VIP's description says the daily
  block is money where restricted, and VIP is never promoted on Roblox's Buy Robux page.
- **Trading:** a paid-origin copy moves only when both players' `IsPaidItemTradingAllowed` is
  true (built). New: an unopened paid block can't be traded or gifted to a player whose paid
  random items are restricted.
- **No fake discounts, no restarting countdowns, no "LAST CHANCE"**; prices shown from
  `GetProductInfoAsync`.
- **The reel and the Mystery screen:** section 3.2 and 4.

---

## 14. The research in 10 rules

1. **Start the reveal at the bottom tier, one press per tier above it.** Brawl Stars' Starr Drop
   climbs 50%, Clash Royale's Lucky Chest 68%
   ([Starr Drop odds](https://support.supercell.com/brawl-stars/en/articles/starr-drops-chances-2.html),
   [Lucky Chests](https://support.supercell.com/clash-royale/en/articles/lucky-chests-6.html)).
2. **Reward win 1 best, then taper to currency.** Clash Royale: rewards for 10 wins, then currency
   ([April update](https://supercell.com/en/games/clashroyale/blog/release-notes/april-update/));
   Brawl Stars: 3 wins instead of 8 "stopped the decline of DAU"
   ([Frank's 2025 review](https://supercell.com/en/games/brawlstars/blog/community/2025-in-review-franks-blog-post/)).
3. **A one-time first week, then a smaller loop**
   ([Anime Vanguards](https://animevanguards.fandom.com/wiki/Daily_Rewards),
   [Brawl Stars](https://brawlstars.fandom.com/wiki/Daily_Streak)).
4. **Count login days and forgive misses**
   ([Honkai: Star Rail](https://honkai-star-rail.fandom.com/wiki/Gift_of_Odyssey/2026-09-28),
   [Adopt Me Star Rewards](https://adoptme.fandom.com/wiki/Star_Rewards)); reset at 08:00 UTC
   ([Brawl Stars](https://brawlstars.fandom.com/wiki/Daily_Streak)).
5. **A tiny, one-time starter pack wins the first purchase**
   ([Roblox's guide](https://create.roblox.com/docs/production/game-design/starter-pack-design),
   [Adopt Me 9 R$](https://adoptme.fandom.com/wiki/Starter_Pack)).
6. **Compress Robux prices: top items near 1,000-2,000 R$, priced to phone Robux packs**
   ([Grow a Garden seed shop](https://growagarden.fandom.com/wiki/Seed_Shop),
   [Robux prices](https://www.thepricer.org/how-much-do-robux-cost/),
   [Naavik](https://naavik.co/deep-dives/the-state-of-ugc-games-2026/)).
7. **Price skips by time left, and keep timers few**
   ([Steal An Egg products](https://apis.roblox.com/developer-products/v2/universes/10563114921/developerproducts?limit=50),
   [Roblox on timers](https://create.roblox.com/docs/production/monetization)).
8. **Honest offers only: no fake former prices; bonus content and real end dates are fine**
   ([Community Standards](https://about.roblox.com/community-standards)).
9. **Disclose odds, pity and per-player odds; gate paid random items by PolicyService**
   ([paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items),
   [26 May 2026 post](https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622)).
10. **Copies of the exact item set its worth; add and retire items instead of flooding**
    ([PS99 exists](https://ps99.biggamesapi.io/api/exists),
    [04 §1](research-2026-10-08/04-value-and-trading.md)).

---

## 15. Clashes with past decisions

| Past decision | v4 | Recommendation |
|---|---|---|
| Every real win gives a Mystery block, forever (`ECONOMY` 7.1, 2026-10-04) | 10 track steps a day, then money and XP | As you asked. The anti-farm rules carry over exactly (section 5). |
| No blocks from VIP; "never more blocks" (plan 2026-10-02, `ECONOMY` 11.2, 11.7) | A Rare block a day for VIP | As you chose. It makes VIP a paid random item: $5,000 where restricted, said in the pass description, odds on the VIP card, never promoted on the Buy Robux page. |
| Mythic blocks are never sold (`ECONOMY` 7.2, 9.1) | The restock sells one about every 5 days | As you asked; announced in every server, stock 1, 1,699 R$ or $4,990,000. One warning from the research: Steal a Brainrot pulled its Robux dealer for its rarest units after a week as "pay to win" (01 Rule 5). Ours stays a block (72% of the time a Legendary), rare to see, one per player, and the Secret is never sold directly. |
| "No fake near-misses" (`ECONOMY` 11.7; reel decision 2026-10-03) | One labelled showcase tile per spin, rare cues more often than their odds | As you chose, with the 6 rules in section 4. The showcase tile is never near the stop, so there is still no near-miss. Risk: Roblox has never ruled on it. |
| Copy numbers timed with the old model (2026-10-08) | #100 gone at day 4 (Epic) to day 33 (Secret) | Keep as approved (a launch-month badge); "first 500" for Legendary+ is the option. Your call. |
| The 30% release sale (2026-10-03) | Launch bonus +30% | As you chose. The sale products are retired, never deleted. |
| VIP 499 (2026-10-04) | 399 | As you chose. |
| First money pack pays double (11.1) | Removed | Recommended (section 8.2). |
| "Always-on Epic or Legendary blocks" ruled out (11.7) | The restock shows Epic in about 1 restock in 3 | Still not always-on: slots rotate and stock is 1. |
| Pity counts bought Mystery blocks (`ECONOMY` 7.1), but the code skips them | Code follows the doc | Recommended: one rule for every Mystery block. |
| Anyone can trade, no gate (2026-10-03) | Unchanged | **Your call.** The first week's Legendary block is the one prize an alt account could farm: 7 days with one finished match each, about 1,000 R$ on the value ladder per alt. Recommended: a login day counts only after a finished match (built now), and analytics watch first-week cues traded within a week; if alts show up, add a 7-day trade hold on cues from first-week blocks. The other option is to build that hold now (research 03 Rule 7; PS99 holds code items 7 days), which needs a save change. |
| The favorite reward: Config still gives a Mystery block (decision 2026-10-08: a Lucky 8 block) | Lucky 8 block | Config follows your decision. |
| Bundle prices crossed out ("Was" in `Config.Products`); "Best value" on pack 6 | "57 R$ one by one"; "Best value" on pack 7 | Recommended: both claims stay literally true (section 8.2). |
| Daily things reset at 00:00 UTC | 08:00 UTC | Recommended (section 5). |
| The 28-day track's first prize on day 7; playtime gifts at 90 and 120 minutes | Day 8; everything within 60 minutes | Recommended (sections 6.2, 6.3). |
| The Grand Opening: 21 days, 400th-block Beta guarantee, odds shown the same for everyone | Copy caps, 1,000th-block guarantee, per-player odds, start at publish | Caps and per-player odds are needed (your 30-45 day window; Roblox's one-instance rule). |
| The old day-30 targets (Epic about 5%, Legendary about 1%, Mythic 0.5% or less) | Section 1 | Replace. |

---

## 16. After launch: what to watch and what to change

- **If week-1 Legendary owners come in under 2%** (likely if retention is typical): raise the
  Mystery block's Legendary tier from 0.05% to 0.08%, or make login day 5 an Epic block.
- **If they come in over 3%:** make win 10 a Rare block (-0.4 points at day 30).
- **If Legendary trade values sag:** the first-week Legendary block (section 12.2).
- **If first-week cues are traded away soon after they're found** (a sign of alt farming): the
  7-day trade hold (section 15).
- **If the Grand Opening runs past day 30:** nothing; the caps hold.
- Economy analytics already log every block's source; add the win track's step and the
  first-week flag so these checks are a query.

---

## 17. Every place the change lands

**Config (`src/shared/Config.luau`):** `BlockOdds` (every row, `Drop.Weights`, `Drop.PityEpic`
100, `Drop.Upgrade.Clicks` 5, the Grand Opening row with caps), `LuckyBlocks.Kinds` (Epic timer
30 min, the Grand Opening's guarantee 1,000 and caps), a new win-track table, `Daily` (first week,
later weeks, the 28-day track, playtime, the reset hour), `Social` (the favorite's Lucky 8
block), `Ranks.Rewards.Tier`, `Shop` (Deals, Mystery, Restock, the Starter Pack, the VIP offer,
the launch bonus, the first-pack double off, Money Party), `Products` (every price, the
bundles' one-by-one prices, "Best value" on pack 7, 3 new rows: the restock Mythic block and two
skip prices, the sale rows retired), `Trade` (live block worth), `BotCues`,
`Ults.Earn.MoneyPerSpin`, and the planned numbers for the Lucky Shot, Golden Shot, Lucky Rain and
the stay bonus (marked not built).

**Server:** the Mystery path (5 presses from Standard; pity for bought blocks); the 10-step win
track (with the anti-farm rules and `MatchSummary.block`); the 08:00 UTC reset everywhere; the
first-week login (7 login days within 14, a day counts after a finished match); VIP's daily block
with PolicyService; the restock's Mythic block and its announcement; the Grand Opening's caps,
guarantee and per-player odds; the launch bonus on receipts; the Starter Pack's new contents and
its restricted version; the skip by time left (3 products); no paid blocks to restricted players
in trades; live block worth in the trade warning.

**Saves** (`SaveSchema.Version` 8 today on both branches): new fields for the first week (days
claimed, the join day), the win track (today's steps), VIP's daily block (last day), and a
migration for the new playtime list and the 08:00 UTC day. The GUI session plans a bump for copy
numbers: check its version right before writing; if it is 9 by then, ours is 10 and both
migrations chain.

**Tests (Lune):** every odds row adds to 100; the Mystery path climbs only and ends on the rolled
tier; pity for bought blocks; the win track (steps, cap, anti-farm, reset); the first week (count
mode, the 14-day window, the match rule); the 28-day track; playtime; VIP's block and its
restricted money; the restock's odds and the Mythic block; the Grand Opening's caps, guarantee and
per-player odds; the launch bonus; the skip's three prices; the Starter Pack's two versions; the
products spec; the migration.

**Strings:** the bar ("Lucky Blocks today 7/10"), the first week ("Day 7: Legendary block · log in
on any 7 days within 14"), the skip prices, VIP's perks and its restricted note, the launch bonus,
the restock's Mythic announcement, the Grand Opening's "N of 100 left", the reel's line, the
Mystery screen's "The result is decided when you open it".

**Tools:** `tools/economy_model.py` (v4's sources, as in `economy_v4_sim.py`), `tools/economy_config.json`
through `tools/export_economy.luau`, `tools/products_spec.json` and `tools/roblox_products.py`
(the last build step, right before the merge: `--dry-run`, then for real; nothing deleted). The
tool only creates items and sets icons and descriptions today, so it gets a price-update mode
for the passes and products that already exist (Open Cloud's update endpoints).

**Docs:** `docs/ECONOMY.md` rewritten (today's state, your answers dated), `GDD.md` sections 11
and 12, a dated `DECISIONS.md` line per decision, a `ROADMAP.md` box, `STATUS.md` at the merge.

---

## 18. Hand-offs

### 18.1 For the GUI session (every screen that changes)

1. **The next-reward bar above the hotbar** (it shares the space with the matchmaking bar): the
   next step's block, "Lucky Blocks today 7/10", the time to the reset; "10/10 · wins pay money
   and XP today" after win 10.
2. **The result screen's block chip:** the track's block for that win (Rare, Mystery, Uncommon,
   Epic), not always Mystery; no chip after win 10.
3. **The Mystery upgrade screen:** starts as Standard, 5 presses (`Config.BlockOdds.Drop.Upgrade.Clicks`
   = 5), plays `BlockDrop.path` (one entry per press, climbs only), the line "The result is decided
   when you open it; the presses reveal it", pity counters.
4. **Free Reward:** the first-week strip (Epic on day 2, Legendary on day 7, "any 7 days within
   14"), the later-weeks strip, the 28-day track (day 8), playtime 5 / 15 / 30 / 45 / 60 minutes,
   VIP's daily Rare block card; later the Lucky Shot, Lucky Rain and stay bonus.
5. **The shop's Blocks page:** the Mystery block (5 R$ / $4,900, 10 for 45 R$ / $44,100, "13 for
   10" during the launch bonus); the Grand Opening (19 / 49 / 149 R$, $24,900 / $69,900 /
   $219,000, per-player odds, "N of 1,000 left" and "N of 100 left"); the restock (Rare, Epic,
   Legendary and **Mythic** slots, no Uncommon, the VIP slot, the slot odds, a Rare stock of 2);
   the Starter Pack (19 R$, its contents). Bundle savings read "57 R$ one by one", not a
   crossed-out price.
6. **The Money page:** 7 packs at 25-1,699 R$, "Best value" on pack 7, the "Launch bonus +30%"
   badge with its end date, no "FIRST BUY x2".
7. **The Passes page:** VIP 399 R$ with the new perk text (and "the daily block is $5,000 where
   restricted"), the Rare block's odds on the VIP card, the ability slots 49 / 79, Money Party 49,
   Roblox Plus.
8. **The skip button:** the price for the time left (4 / 9 / 15 R$).
9. **Each block's reel pool and YOU GOT:** the full pool (every rarity incl. the Secret), one
   showcase tile per spin with its odds, never within 8 tiles of the stop, the reel's line,
   effects only for Rare or better.
10. **Cue cards' chance chip and odds screens:** the new per-Mystery % (section 3.1) and rows.
11. **The ability spin screen:** 9 / 39 / 75 / 299 R$, Lucky 25 / 65, $12,500 a spin.
12. **The restock announcement banner** for a Legendary or Mythic block.
13. **The Mystery block's "Odds & Details":** the final-tier table, each tier block's cue odds,
    the pity counters and the live pity odds, with "1 in N" beside the rare ones.

**Shims** (kept so the game, lint and tests work until the GUI rebuilds each screen):
- `Config.Shop.ReleaseSale` stays with `Percent = 0` (off); the shop reads the new
  `Config.Shop.LaunchBonus` next.
- `Config.Shop.FirstPackMultiplier` stays at 1 (off) instead of being removed.
- `Config.Daily.Streak` becomes the later-weeks loop; the first week is the new
  `Config.Daily.FirstWeek`. `WeeksForBonus` and `WeekBonus` stay (already shims).
- `Config.BlockOdds.Drop.Upgrade.Chances` stays (unused by the server) until `MysteryReveal`
  stops reading the old table.
- The `LuckyBlockSkip` product keeps its key (now 4 R$); the 9 and 15 R$ ones are new keys the
  server picks.
- The sale products stay in `Config.Products` with `Retired = true`.
- `Was` on the bundles stays, now meaning "the same count bought one at a time today" (57 and
  190; 45, 90 and 450; 75), until the shop shows it as "one by one".
- `Config.Products.BestValue` stays, set to `Pack7`.

### 18.2 For the thumbnail session (every shown odd that changes)

| Label today | What it is | New |
|---|---|---|
| "1 IN 450,000" | the Secret, per Mystery block (exactly 1 in 462,321) | **1 in 131,718: "1 IN 132,000"** (rounded so it never looks better than true) |
| "1 IN 6,000" | a Legendary, per Mystery block (1 in 6,008) | **1 in 2,161: "1 IN 2,200"** |
| (if shown) a Mythic per Mystery block | 1 in 47,176 | **1 in 15,077: "1 IN 15,100"** |
| (if shown) an Epic per Mystery block | 1 in 920 | **1 in 306: "1 IN 310"** |
| (if shown) any block's row | section 4 | the new rows |
| (if shown) Grand Opening odds | Firework 3%, Beta 0.3% | **Firework 6% ("only 1,000 ever"), Beta 0.4% (1 in 250, "only 100 ever")** |

---

## 19. Build order (the Progress list, once approved)

1. Merge the newest `shop-lively` commit into the worktree; copy the brief to
   `docs/prompts/ECONOMY_V4_PROMPT.md` with this list and this plan beside it; commit.
2. Config: every table in section 17, with Strings. Lint, test, model, commit, push.
3. The Mystery block: tier weights, 5-press path from Standard, pity for bought blocks.
4. The 10-step daily win track and the 08:00 UTC reset for every daily thing.
5. Login: the first week (7 days within 14, the match rule), later weeks, the 28-day track,
   playtime.
6. VIP's daily Rare block with PolicyService.
7. The restock: Rare-or-better slots, the Mythic block and its announcement.
8. The Grand Opening (caps, guarantee, per-player odds), the launch bonus, the Starter Pack, the
   first-pack double off.
9. Timers and the skip by time left.
10. Trading: live block worth; no paid blocks to restricted players.
11. Saves and the migration (check the GUI branch's version first).
12. `tools/economy_model.py` and `economy_config.json`.
13. Docs: `ECONOMY.md`, GDD 11-12, `DECISIONS.md`, `ROADMAP.md`.
14. Products: `products_spec.json`, `roblox_products.py --dry-run`, then for real (right before
    the merge).
15. The merge (when you say), `STATUS.md`.

Every step: `tools/lint.sh`, `tools/test.sh`, re-run the model, commit, push `economy-v4`.
