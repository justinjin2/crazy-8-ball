# Economy v5: the plan

Written 2026-10-09 from the designer's answers on the review page
(`03-economy-v5-review.md`, https://claude.ai/artifact/7xDwi8S8XffahhgxhdTrQY) and two
follow-ups in chat. It replaces the numbers of `02-economy-v4-plan.md` wherever they differ. The
build brief is `ECONOMY_V5_PROMPT.md`. Every number here was simulated with
`economy_v5_sim.py --only plan` (results: `economy_v5_plan.txt` and `.json`).

**Nothing in the game has changed yet.** The build runs in `~/Desktop/8ball` on `gui-v4` (a
backup branch `before-economy-v5` first), and Robux prices come last, after you approve them.

---

## 0. The short version

1. **Every block climbs from its name, and the name is its floor.** A Rare block always gives
   Rare or better. The tier a block ends on *is* the cue's rarity; the reel only picks which
   cue of that rarity.
2. **One ladder for every block:** 50 / 35 / 18 / 10 / 15 / 2.5%. A Mystery block reaches
   Epic or better 1 in 32, Legendary or better 1 in 317, Mythic or better 1 in 2,116, and the
   Secret 1 in 84,656.
3. **Grand Opening Luck for the first 30 days:** Rare to Epic 27% and Epic to Legendary 15%.
   A Mystery then reaches Epic or better 1 in 21 and Legendary or better 1 in 141 (your 5% /
   1%). A clover next to the money and VIP bars shows it.
4. **Fewer, better blocks:** about 6.7 a day for a free 1-hour player (v4: 14.8). Wins 1, 4,
   7 and 10 give an Uncommon, a Mystery, a Mystery and an **Epic** block; the other six give
   $1,000.
5. **Day 7 of the first week gives the Week One Cue:** a new Legendary cue that is never in
   any block. Tradable and sellable like any Legendary. Day 28 of the 28-day track gives an
   Epic block.
6. **The Mystery block costs $14,900, or 5 for $66,900.** Pity: Rare by the 10th, Epic by
   the 40th, and new players' bars start partly filled.
7. **The restock:** 2 slots every 10 minutes, the first always Epic or better, plus VIP's
   slot. A Legendary or better in 1 restock in 3, a Mythic about 7 times a day.
8. **What it does** (players active in the last 7 days who own one, day 7 / 30 / 60): Epic
   59 / 67 / 65%, Legendary 14 / 21 / 18% plus the Week One Cue, Mythic 2.4 / 4.6 / 4.3%,
   the Secret 0.08 / 0.14 / 0.12%.
9. **Robux prices last**, after you approve them (section 13). One is already decided: the
   timer skip costs **1 R$ for an Uncommon or Rare block** (5 minutes or less left).

---

## 1. Your answers (2026-10-09)

| # | Question | Your answer | In the plan |
|---|---|---|---|
| 1 | How rare a Legendary after the launch month | About 1 a month, like today (Strict) | The ladder 50 / 35 / 18 / 10. A free 1-hour player climbs to Legendary or better about 1.1 times a month after the launch. |
| 2 | Mythic and Secret | Goals that grinders can reach | Legendary to Mythic 15%, Mythic to Secret 2.5% (section 2.3). No copy cap on the Secret. |
| 3 | A more generous launch | Grand Opening Luck, ×1.5 on Rare to Epic and Epic to Legendary for 30 days. *"Some clover next to the money/VIP bars in the bottom left; clicking on it says extra luck for release."* | Section 3.4 and hand-off 11.1. |
| 4 | If cues lose value later | Add new cues each season and retire old ones from blocks; never lower printed odds | Section 7.6. |
| 5 | How a block works | Every block climbs from its name, and the name is its floor | Section 3. |
| 6 | How many daily wins give a block | 4: wins 1, 4, 7 and 10 | Section 4. |
| 7 | Win 10 | An Epic block | Section 4. |
| 8 | Calendar Legendaries | Neither, with a note: keep day-7 retention high, more important than value | Then in chat: day 7 = the **Week One Cue**; *"it should be tradable"*; and *"dont worry about that either to prevent farming, all of that will be worried about IF this game does good"*. Day 28 = an Epic block. Section 5. |
| 9 | What Robux buys | Mystery blocks, like today | Section 6.1. |
| 10 | The Mystery's money price | Other: *"lowering the amount you can buy for 10? like 5 or something? you let me know and make a valid decision"* | $14,900, and 5 for $66,900 (section 2.1). |
| 11 | Epic pity | By the 40th Mystery block | Section 3.6. |
| 12 | The restock | Rare 55 / Epic 34 / Legendary 9.5 / Mythic 1.5% a slot, priced by what each block promises | Section 6.2. |
| 13 | Restock extras | The banner in every server, and one slot always Epic or better. *"is 3 restocks even too much? maybe just 2, +1 for VIP? you make an informed decision"* | 2 slots + VIP's (section 2.2). |
| 14 | Extras | Quick reveal and "Open all" for Common and Uncommon; a server message with the "1 in N" for Legendary or better; pity bars with a head start | Sections 3.6, 3.8, 3.9. |
| 15 | Your vision | *"Should feel special, but also at the same time to each to their own feel rewarding to own, not too common where everyone walks around with one but not impossible (achievable easier through means of robux obviously, or lots of grinding)."* | The targets in section 7. |
| – | The skip (in chat) | *"for uncommon/rare the skip timer should be reduced to just 1 robux since really are people going to spend 4 robux to skip a 60 second timer"* | A 1 R$ skip for 5 minutes or less left (section 3.7). |

---

## 2. My calls on what you passed back

Each is logged as a dated line in `DECISIONS.md` by the build, and each can be overruled.

1. **The bundle is 5 for $66,900** (10% off, like v4's 10-pack). At $14,900 a block, 10 would
   cost $134,100: about 3.4 days of a 1-hour player's match money. 5 is about 1.7 days, so the
   bundle stays within reach. The Robux 10-pack becomes a 5-pack too (made in the Robux pass).
2. **The restock has 2 slots plus VIP's, and the first is always Epic or better.** It keeps the
   same rare stock as 3 random slots (a Legendary or better in 32.8% of restocks against 30%;
   a Mythic in 4.8% against 4.4%), but every restock now shows a real Epic, and fewer slots
   make each one feel like an event.
3. **Mythic and the Secret:** Legendary to Mythic **15%** (Strict had 7%) and Mythic to Secret
   **2.5%** (Strict had 5%). "Reachable" means about 5% of active players own a Mythic; the
   Secret stays a trophy (a Legendary block reaches it 0.375% of the time; Strict had 0.35%).
4. **Day 7 is the Week One Cue** (your pick in chat). It is tradable, and sellable like any
   Legendary, with no farming limits for now. Details in section 5.
5. **Playtime keeps 5 gifts** (the Free Reward screen shows five tiles): the 45-minute gift is
   $3,500 instead of a Mystery block.
6. **When the climb happens, for every block: like the Mystery today.** A new block shows
   OPEN!. A tap opens the climb screen (4 presses). The block becomes the block of the tier it
   reached, which waits on that tier's timer, then opens with the reel. So timers belong to the
   block after its climb, exactly as for the Mystery's result today. The Gift keeps its 12-hour
   comeback wait before its climb.
7. **A climb that reaches the Secret gives the Secret cue at once.** There is no Secret block
   (no model or timer); the full show plays straight away.
8. **The pity head start:** new players' bars start at 2/10 (Rare) and 10/40 (Epic), so their
   first Epic is guaranteed by their 30th Mystery block.
9. **The Grand Opening Luck** starts with the Grand Opening (its `StartsAt`) and lasts 30 days
   on its own clock, so changing the Grand Opening's length never changes it. Only the two
   middle steps are boosted; Mythic and the Secret still come about 2.25× as often while it
   runs, because more blocks reach Legendary.
10. **Claim All still claims day 7**, so a player can buy the Week One Cue early with it. Its
    prices are redone in the Robux pass (v4 priced the first week mostly by day 7's Legendary
    block).
11. **Lucky 8** (the favorite reward) and **the Gift** climb from Uncommon; **the Sky block**
    (Lucky Rain) climbs from Standard. The Grand Opening and Starter blocks keep their approved
    odds and don't climb.
12. **ROOFTOP gives an Uncommon block** (everyone gets it, like a calendar gift). **The LIKES
    codes stay as they are** (rare celebration gifts, switched on by hand).
13. **Pity is for Mystery blocks only** (as today), and gives exactly the guaranteed rarity.
14. **The "1 in N"** in the server message is the chance of that exact cue from the block it
    started as, with the odds live at the climb, rounded to 3 significant figures.
15. **Win 10's Epic block makes grinders strong.** A free 3-hour player climbs to Legendary or
    better about 4 times a month after the launch, and about half own a Mythic by day 30. It
    fits "lots of grinding". If Legendaries feel too common among grinders, making win 10 a
    Rare block is the lever.

---

## 3. How a block works

### 3.1 The rules

- **A block's name is its floor.** A Rare block always gives Rare or better.
- **Every block climbs**, one step at a time, on one ladder. The tier it ends on is the cue's
  rarity. Then the reel picks which cue of that rarity, every cue equally likely, as today.
- **The Mystery block is a Standard start.** Lucky 8 and the Gift are Uncommon starts; the Sky
  block is a Standard start.
- **The Grand Opening and Starter blocks keep their approved odds** (they don't climb). Rank
  rewards keep their blocks, which now follow these rules (Expert's Legendary block is a
  guaranteed Legendary).
- **The server rolls the final tier first**, so the shown odds are the real odds (no fake
  near-misses).

### 3.2 The ladder

| Step | Chance | During the Grand Opening Luck |
|---|---|---|
| Standard to Uncommon | 50% | 50% |
| Uncommon to Rare | 35% | 35% |
| Rare to Epic | 18% | **27%** |
| Epic to Legendary | 10% | **15%** |
| Legendary to Mythic | 15% | 15% |
| Mythic to Secret | 2.5% | 2.5% |

In Config's parts of a million: 500,000 / 350,000 / 180,000 / 100,000 / 150,000 / 25,000; the
launch's two steps 270,000 and 150,000.

### 3.3 What each block gives

The rarity of the cue, in percent (each row adds to 100):

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Mystery (and Sky) | 50 | 32.5 | 14.35 | 2.835 | 0.26775 | 0.0460688 | 0.00118125 |
| Uncommon (and Lucky 8, Gift) | – | 65 | 28.7 | 5.67 | 0.5355 | 0.0921375 | 0.0023625 |
| Rare | – | – | 82 | 16.2 | 1.53 | 0.26325 | 0.00675 |
| Epic | – | – | – | 90 | 8.5 | 1.4625 | 0.0375 |
| Legendary | – | – | – | – | 85 | 14.625 | 0.375 |
| Mythic | – | – | – | – | – | 97.5 | 2.5 |

The same as "or better" chances:

| Block | Epic or better | Legendary or better | Mythic or better | Secret |
|---|---|---|---|---|
| Mystery | 3.15% (1 in 32) | 0.315% (1 in 317) | 0.04725% (1 in 2,116) | 1 in 84,656 |
| Uncommon | 6.3% (1 in 16) | 0.63% (1 in 159) | 0.0945% (1 in 1,058) | 1 in 42,328 |
| Rare | 18% (1 in 5.6) | 1.8% (1 in 56) | 0.27% (1 in 370) | 1 in 14,815 |
| Epic | 100% | 10% (1 in 10) | 1.5% (1 in 67) | 1 in 2,667 |
| Legendary | 100% | 100% | 15% (1 in 6.7) | 1 in 267 |
| Mythic | 100% | 100% | 100% | 2.5% (1 in 40) |

### 3.4 During the Grand Opening Luck (the first 30 days)

| Block | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|
| Mystery (and Sky) | 50 | 32.5 | 12.775 | 4.01625 | 0.6024375 | 0.1036547 | 0.0026578 |
| Uncommon (and Lucky 8, Gift) | – | 65 | 25.55 | 8.0325 | 1.204875 | 0.2073094 | 0.0053156 |
| Rare | – | – | 73 | 22.95 | 3.4425 | 0.5923125 | 0.0151875 |
| Epic | – | – | – | 85 | 12.75 | 2.19375 | 0.05625 |
| Legendary | – | – | – | – | 85 | 14.625 | 0.375 |
| Mythic | – | – | – | – | – | 97.5 | 2.5 |

- A Mystery: Epic or better 4.725% (1 in 21), Legendary or better 0.70875% (1 in 141), Mythic
  or better 1 in 941, the Secret 1 in 37,625.
- It's free, the same for everyone, dated, and shown with a countdown. Every odds screen shows
  the boosted odds while it runs (Roblox requires live odds). When it ends, the event ends;
  nobody's odds get cut.
- **The clover** (your note): a clover icon next to the money and VIP bars, bottom left, only
  while the luck runs. A tap opens a small popup: "Extra luck for the release!", the countdown,
  and the two boosted steps (Rare to Epic 18% → 27%, Epic to Legendary 10% → 15%).

### 3.5 The climb screen

- Every new block (Mystery, tier blocks, Lucky 8, the Gift, the Sky block) arrives
  **unclimbed** and shows OPEN!. A tap opens the climb screen: 4 presses, as today ("just 4",
  2026-10-09).
- The server rolls the final tier first (with the luck and, for a Mystery, pity). The first
  press shows the start: the block's own tier, or higher when the later presses couldn't
  reach the final tier otherwise (start = the higher of the block's tier and the final tier
  minus 3). Each later press climbs one tier or doesn't. A climb never fizzles or falls back.
- The block then becomes the block of the tier it reached (**climbed**), which waits on that
  tier's timer (VIP: none; a bought block: none) and opens with the reel as today.
- The screen has 7 tiers now: the Secret is on top. A Secret result skips the block and plays
  the full show at once (section 2.7).
- A climbed block of a tier never climbs again; an unclimbed one always can. Both can be
  traded once ready (unclimbed blocks have no timer).

### 3.6 Pity (Mystery blocks only)

- **Rare by the 10th** Mystery block in a row without a Rare or better; **Epic by the 40th**
  without an Epic or better. A pity result is that exact rarity now (v4's Epic pity gave a Rare
  cue 77% of the time).
- **Head start:** a new save starts the counters at 2 (Rare) and 10 (Epic). The bars show
  2/10 and 10/40 from the first day.
- Shown as bars with the number ("Epic guaranteed in 23 blocks"), on the Mystery screen and in
  the odds list. When pity is due, the odds screen shows the live odds with the guaranteed
  tier (as v4 does).
- How often it fires: among players who open that many Mystery blocks, about 4 in 10 get their
  first Epic from pity at block 30 (1 in 4 during the launch); after that, about 3 in 10 each
  time (1 in 7 during the launch). The Rare pity fires for about 1 player in 4 the first time.

### 3.7 Timers (unchanged by tier)

Standard 0, Uncommon 1 minute, Rare 5 minutes, Epic 30 minutes, Legendary 6 hours, Mythic 12
hours. They apply to the climbed block (section 3.5). The Gift keeps its 12-hour comeback wait
before its climb. VIP has no timers; a bought block opens at once.

**The skip** (by time left, as in v4):

| Time left | Today (v4) | v5 |
|---|---|---|
| 5 minutes or less (every Uncommon and Rare block) | 4 R$ | **1 R$** (a new product; designer, 2026-10-09) |
| 30 minutes or less (an Epic block) | 4 R$ | 4 R$ |
| 6 hours or less (a Legendary block) | 9 R$ | 9 R$ |
| more (a Mythic block) | 15 R$ | 15 R$ |

Skip credits already saved keep the price they were bought at (they are numbered by row
today, so the new first row needs a migration).

### 3.8 Quick reveal and "Open all"

- A Common or Uncommon result opens with a quick 1-2 second reveal; the full show from Rare up.
- **"Open all"** opens every ready climbed Standard and Uncommon block at once, with a short
  summary of what came out. One server request, rate-limited like the others.

### 3.9 Server messages

- A Legendary result is announced in the opener's server; Mythic and the Secret in every
  server (as v4).
- New: the message carries the **"1 in N"**: the chance of that exact cue from the block it
  started as (section 2.14). From a Mystery block: a Legendary cue 1 in 2,610 (7 Legendary
  cues), a Mythic cue 1 in 6,510 (3 Mythic cues), the Eclipse Cue 1 in 84,700.
- The restock banner stays: a Legendary or Mythic block in a shared slot is announced in every
  server.

---

## 4. Where blocks come from

| Source | Today (v4) | v5 |
|---|---|---|
| Daily wins (the win track) | a block on all 10: Rare, Mystery, Mystery, Uncommon, Mystery, Mystery, Rare, Mystery, Mystery, Epic | wins 1, 4, 7, 10: **Uncommon, Mystery, Mystery, Epic**; $1,000 on wins 2, 3, 5, 6, 8, 9; after win 10 money and XP only (as today) |
| First win ever | a Rare block | a Rare block (it stands in for win 1, as today) |
| Playtime (minutes a day) | 5: $1,000; 15, 30, 45: a Mystery; 60: a Rare block + 1 spin | 5: $1,000; 15: a Mystery; 30: $2,500; 45: $3,500; 60: $5,000 + 1 spin |
| First week (7 login days within 14, each with a finished match) | $5,000 + Mystery; Epic; $10,000; 2 Mystery; Rare; 3 Mystery; Legendary + 2 spins | $5,000 + Mystery; **Rare**; $10,000; 2 Mystery; $15,000; 2 Mystery; **the Week One Cue** + 2 spins |
| Later weeks (the streak) | $5,000; Rare; $10,000; 2 Mystery; $15,000; 3 Mystery; Epic + 2 spins | $5,000; Mystery; $10,000; Mystery; $15,000; Mystery; **Rare** + 2 spins |
| 28-day track | day 8 $50,000; day 14 Epic; day 21 $150,000; day 28 Legendary | day 8 $50,000; day 14 **Rare**; day 21 $150,000; day 28 **Epic** |
| VIP's daily block | a Rare block | an **Uncommon** block |
| Codes | WELCOME $5,000 + Mystery; 8BALL $2,500; ROOFTOP a Rare block; RELEASE 3 spins; the LIKES codes | the same, except ROOFTOP: an **Uncommon** block |
| The group | 3 Mystery | **2** Mystery |
| An invite (both players) | a Rare block | an **Uncommon** block |
| Favorite | $10,000 + a Lucky 8 block (the Rare row) | $10,000 + a Lucky 8 block (an Uncommon start) |
| The Gift (first leave) | the Rare row, 12 hours | an Uncommon start, 12 hours |
| Rank rewards | Mystery / Rare / 2 Rare / Epic / 2 Epic / Legendary / Legendary + Epic / 2 Legendary / Mythic / 2 Mythic | the same blocks, now climbing from their names |
| Lucky Rain (planned) | a Sky block, or a Rare block 1 time in 20 | the same (the Sky block is now a Standard start) |
| Lucky Shot (planned, free) | Miss $500; Grey $1,500; Blue $3,000; Red a Mystery; Gold a Rare block | Gold: an **Uncommon** block |
| Golden Shot (planned, 15 R$) | Miss $5,000; Grey $7,500 + Uncommon; Blue Rare; Red $10,000 + Rare; Gold $25,000 + 2 Rare | Grey $7,500 + **Mystery**; Blue **Uncommon**; Red $10,000 + **Uncommon**; Gold $25,000 + **1 Rare** |
| Grand Opening block, Starter block | approved rows | unchanged |
| Sell-back, finder's money, Index rows | | unchanged |

A free player who plays every day and wins half their matches opens about 4.8 blocks a day at
30 minutes, 6.7 at 1 hour and 11.7 at 3 hours (v4: about 15 at 1 hour).

---

## 5. The Week One Cue

- **What it is:** a new Legendary cue (working name), given on day 7 of a player's first week:
  their 7th login day within 14 days of joining, each day with a finished match (today's rule).
  Plus the day's 2 spins.
- **Never in any block, reel, restock or shop list.** Its only way in is day 7 (and Claim All,
  section 2.10), and trading.
- **Like any Legendary:** tradable; sellable back for $250,000; $25,000 finder's money the
  first time; counted in the Index's Legendary row; numbered copies like every Rare-or-rarer
  cue.
- **Its trade worth follows its own copies** (1 / copies, like every cue). Many will exist, so
  it will trade low next to block Legendaries: it's a "played my first week" badge, not a luck
  trophy. It never changes another cue's worth.
- **No farming limits for now** (your words: "all of that will be worried about IF this game
  does good").
- **The first-week calendar shows it from day 1**, on day 7's card, as the goal to come back
  for.
- **Its look is new art** for the cue pipeline (you pick the look). Until it exists the cue
  uses the default look with its own name.
- **Simulated:** 16% of active players hold it on day 30 and 29% on day 60 (11% and 20% if 3
  owners in 10 sell it). Counting it, 29% (day 30) and 35% (day 60) of active players own "a
  Legendary"; from blocks alone 21% and 18%.
- **Selling it** pays $250,000, about 17 Mystery blocks. Simulated with 3 owners in 10 selling,
  that money moves Legendary owners by about 1 point (section 7.5).

---

## 6. The shop

### 6.1 Mystery blocks

| | Today (v4) | v5 |
|---|---|---|
| One | $4,900 (5 R$) | **$14,900** (Robux in the Robux pass) |
| Bundle | 10 for $44,100 (45 R$) | **5 for $66,900** (a new Robux 5-pack; the 10-pack retired, never deleted) |
| Launch bonus (Robux bundle) | 10 come as 13 | 5 come as 6 (my lean; decided with the Robux prices) |

Each v5 Mystery is 8× as likely to reach Epic or better as v4's, so $14,900 is the same value
per dollar as $4,900 was. A 1-hour player buys about 2.3 a day with match money.

### 6.2 The restock

Every 10 minutes, the same in every server.

| Slot | Rare | Epic | Legendary | Mythic |
|---|---|---|---|---|
| 1 (always Epic or better) | – | 75.56% | 21.11% | 3.33% |
| 2 | 55% | 34% | 9.5% | 1.5% |
| VIP's slot | 40% | 40% | 16% | 4% |

(In Config's parts of 10,000: slot 1 7,556 / 2,111 / 333; slot 2 5,500 / 3,400 / 950 / 150; VIP
4,000 / 4,000 / 1,600 / 400.)

| | Today (v4) | v5 |
|---|---|---|
| Epic or better | 34% of restocks (every ~29 min) | every restock |
| Legendary or better | 3% (every ~5.6 h) | 32.8% (every ~31 min); 46.2% with VIP's slot |
| Mythic | about every 4.6 days | 4.8% (every ~3.5 h, about 7 a day); 8.6% with VIP's slot |
| Prices (money) | $19,900 / $199,000 / $1,490,000 / $4,990,000 | **$49,900 / $249,000 / $1,290,000 / $4,990,000** |
| Days of a 1-hour player's match money (~$39,000 a day) | 0.5 / 5 / 38 / 129 | 1.3 / 6.4 / 33 / 129 |
| Robux | 15 / 99 / 599 / 1,699 | 39 / 149 / 599 / 1,699 proposed; set in the Robux pass |
| Stock per player per restock | Rare 2, the others 1 | the same |
| What a block gives | mostly the rarity below its name | at least its name, with a chance to climb |

- Legendary and Mythic blocks stay expensive because they are guarantees now; if a guaranteed
  Legendary cost a few hours of play, Legendaries would flood.
- The banner in every server for a Legendary or Mythic block in a shared slot stays (v4).

### 6.3 Unchanged

The Grand Opening block (odds, caps, prices, 30 days), the Starter Pack, VIP's price and its
no-timers perk, money packs, the skip's 4 / 9 / 15 R$ rows, Money Party, spins and slots. VIP's perk text changes to
"an Uncommon block a day".

---

## 7. What it does (simulated)

The game's own model (`tools/economy_model.py`, today's Config) with v5 patched in
(`economy_v5_sim.py`), 60 days, about 144,000 players by day 60, free players and spenders.
"Own" = players active in the last 7 days who own at least one.

### 7.1 Ownership

| Day 7 / 30 / 60 | Today (v4) | v5 |
|---|---|---|
| Epic | 18 / 32 / 42% | 59 / 67 / 65% |
| Legendary (from blocks) | 2.3 / 8.1 / 12.9% | 13.8 / 21.2 / 17.9% |
| The Week One Cue | – | 0.2 / 15.8 / 29.0% |
| A Legendary or the Week One Cue | – | 13.9 / 28.9 / 35.3% |
| Mythic | 0.30 / 0.95 / 1.74% | 2.4 / 4.6 / 4.3% |
| Secret | 0.03 / 0.11 / 0.18% | 0.08 / 0.14 / 0.12% |

- **Epic** becomes the good pull most players get every few days.
- **Legendary** is generous in the launch month, then settles about 1.4× today's owners.
- **Mythic** is a grinder's goal (about 4-5% of active players), as you chose.
- **The Secret** stays the trophy, rarer than today by day 60.

### 7.2 A free player (wins half, plays every day)

| | 30 min a day | 1 hour a day | 3 hours a day |
|---|---|---|---|
| Blocks a day | 4.8 | 6.7 | 11.7 |
| Common or Uncommon | 70% | 71% | 67% |
| Climbs to Epic or better, a week (launch month / after) | 2.5 / 1.8 | 3.5 / 2.5 | 5.4 / 3.9 |
| Climbs to Legendary or better, a month (launch / after) | 1.6 / 0.85 | 2.5 / 1.1 | 7.3 / 4.0 |
| Owns a Legendary by day 30 (launch / after) | 76% / 54% | 88% / 66% | 100% / 100% |
| Owns a Mythic by day 30 (launch / after) | 20% / 11% | 33% / 14% | 69% / 51% |

(v4, 1 hour a day: 14.8 blocks a day, an Epic-or-better climb 0.86 times a week, a
Legendary-or-better climb 0.18 times a month.)

### 7.3 Copies entering per 100 active players a day (day 30)

| | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|
| v4 | 59.7 | 5.3 | 0.80 | 0.08 | 0.01 |
| v5 | 56.6 | 18.7 | 2.76 | 0.46 | 0.01 |

More Epic, Legendary and Mythic copies per player is the price of frequent climbs, the launch
luck and a reachable Mythic. Trade worth per cue drops with them; section 7.6 is how value is
kept over time.

### 7.4 Where the day-30 copies come from (Epic / Legendary / Mythic)

| Source | Share |
|---|---|
| Daily wins | 40 / 40 / 41% |
| Group, favorite, invites, codes, the Gift | 14 / 14 / 14% |
| Login and the 28-day track | 12 / 12 / 12% |
| Playtime | 6 / 7 / 7% |
| Rank rewards | 6 / 7 / 6% |
| The Grand Opening block | 6 / 7 / 4% |
| Mystery blocks bought with money | 4 / 4 / 4% |
| The restock (money) | 4 / 4 / 4% |
| Lucky Rain | 4 / 4 / 3% |
| Lucky Shot and Golden Shot | 2 / 2 / 2% |
| Mystery blocks bought with Robux | 1 / 1 / 1% |

No single gift is a leak. 98% of Legendary-or-better copies come from climbs above the block's
promise (v4: 53% of day-30 Legendaries came from two calendar gifts).

### 7.5 What the simulation includes

**In every run above:** the daily win track and match money (with the VIP, group and Roblox
Plus money boosts); the first week, the later weeks and the 28-day track; the five playtime
gifts; the Daily Challenge (the free Lucky Shot, taken on 80% of play days, and the 15 R$ Golden
Shot, bought by 1 payer in 4 on days they play); Lucky Rain and the stay bonus (both planned);
the group, favorite, invites, launch codes and the Gift; rank rewards; VIP (40% of payers: the
daily block and the VIP restock slot); the Starter Pack (half of payers, in their first week: its
block and $25,000); money packs bought with Robux (with the launch bonus); Mystery and restock
blocks bought with money or Robux; the Grand Opening block.

**Added on 2026-10-09 (the designer asked):** finder's money, the Index rows and selling cues
back were not in the model. With them in (`economy_v5_sell.txt`), every first copy kept:

| Day 7 / 30 / 60 | The plan | + finder's money, Index, selling (middle) | + every duplicate sold (upper bound) |
|---|---|---|---|
| Epic | 59 / 67 / 65% | 60 / 69 / 66% | 59 / 69 / 67% |
| Legendary (from blocks) | 13.8 / 21.2 / 17.9% | 14.3 / 23.0 / 19.0% | 14.7 / 24.0 / 20.4% |
| Mythic | 2.4 / 4.6 / 4.3% | 2.7 / 5.2 / 4.8% | 2.7 / 5.4 / 5.1% |
| Secret | 0.08 / 0.14 / 0.12% | 0.09 / 0.16 / 0.15% | 0.07 / 0.17 / 0.15% |
| A 1-hour player's Mystery blocks bought a day | 2.3 | 3.3 | 3.5 |

- "Middle" means duplicates sold: every Common and Uncommon, Rare 90%, Epic 60%, Legendary 40%,
  Mythic and the Secret 25%, and 30% of players sell their Week One Cue.
- This extra money is large next to match money for new players (finder's money pays $500 to
  $2,500 for each new cue in the first session), but it mostly buys Mystery blocks, which give a
  small share of the good copies. So the ownership numbers move only 1 to 2.5 points: the plan
  holds.
- **Still not modelled:** Money Party (+100% match money for 15 minutes, bought by payers),
  timer skips (they change when, not what), trading (moves cues, never makes them), Limited
  cues (none planned), anti-farm limits (they only lower the numbers), the pity head start (a
  few extra Epics in the first 30 Mystery blocks), and Robux Mystery blocks at their v5 prices
  (the runs use today's 5 R$; Robux Mystery blocks are about 1% of the good copies).

### 7.6 Keeping value as the game grows (your answer 4)

- Add new cues each season and retire old ones from blocks (`Vaulted`); never lower printed
  odds. Retired cues get rarer by themselves.
- If the launch is small, the base ladder can be raised later (a buff is always welcome).
- If a number must ever go down, announce it a week ahead with numbers and new cues.

---

## 8. Value and trading

- **Trade worth:** an unclimbed block is worth its climb odds against the live copies of each
  rarity (like v4's `Trade.blockWorth`); a climbed block is worth its tier exactly; the Week One
  Cue by its own copies.
- `Config.Trade.BlockExists` (the fallback until the counters load) is refilled from the v5
  model at day 30, with entries for climbed and unclimbed blocks.
- Sell-back, finder's money and the Index's row rewards stay as they are.

---

## 9. Roblox's rules

- **Live odds** on every paid random item: the boosted odds during the Grand Opening Luck, and
  the guaranteed tier when pity is due.
- **The climb shows the real result:** the server rolls the final tier first; the presses only
  reveal it. No fake near-misses (ECONOMY 11.7 holds).
- **Pity is disclosed** with its numbers.
- **Paid random items stay refused where PolicyService restricts them:** Robux Mystery and
  restock blocks, Claim All, the Golden Shot, and VIP's daily block (VIP then pays
  `VipRestrictedMoney` instead).

---

## 10. Every place the change lands

- **Config:** `BlockOdds` (the climb ladder and its launch steps, every kind's start, pity and
  the head start, the win track with money steps, the announce sets), `LuckyBlocks.Kinds`
  (starts instead of rows for climbing kinds), `Daily` (first week, streak, 28-day track, VIP's
  block, playtime, ROOFTOP), `Social` (group, invites), `Planned` (Lucky Shot, Golden Shot),
  `Shop.Mystery` and `Shop.Deals.Mystery` (price, the 5-pack), `Shop.Restock` (2 slots, the
  first slot's table, VIP's table, prices), `Shop.LaunchBonus`, `Trade` (`BlockExists`, the
  Week One Cue tradable), `Products` (the 5-pack row; prices in the Robux pass), the catalog
  row for the Week One Cue.
- **Shared code:** `BlockDrop` (the climb from any start, `startOf` with a floor, the path,
  pity with the head start, odds lists for every block, live luck), `BlockOdds`, `LuckyBlocks`
  (unclimbed and climbed blocks, timers on the climbed block, "Open all"), `Daily`, `Restock`,
  `Shop`, `ShopView`, `Trade`, `Catalog`, `Inventory`, `Social`.
- **Server:** `LuckyBlockService` (climb any unclimbed block, the Secret result, "Open all",
  the "1 in N" message), `Rewards` (the Week One Cue on day 7), `Store` (restock, the 5-pack),
  `Items`, `Social`, `GiftDropService`.
- **Saves:** the unclimbed/climbed mark on blocks, the pity head start for new saves, the
  restock's slot change; a version bump with a migration (old saves' tier blocks count as
  unclimbed).
- **Tests, Strings, `tools/economy_model.py`** (v5 inside the model, reproducing this plan's
  numbers), **`tools/economy_config.json`**, **docs** (`ECONOMY.md` rewritten for v5, GDD 11 and
  12, `DECISIONS.md`, `ROADMAP.md`, `STATUS.md` at the end).
- **Products, last:** after your approval (section 13).

---

## 11. Hand-offs

### 11.1 The GUI session (`~/Desktop/8ball`, branch `gui-v4`)

1. **The climb screen for every block**, from the block's own tier: OPEN! on every unclimbed
   block (hotbar and bag), the 4 presses, the Secret on top of the screen, the climbed block
   landing back in its slot on its timer. A small mark that tells an unclimbed block from a
   climbed one of the same tier (bag, hotbar, trade).
2. **A Secret result** goes straight to the full reveal.
3. **Quick reveal** (1-2 s) for Common and Uncommon results; **"Open all"** for ready climbed
   Standard and Uncommon blocks.
4. **Pity bars** (Rare 10, Epic 40) with the head start, on the Mystery screen and in the odds
   list.
5. **The Grand Opening Luck clover**: bottom left next to the money and VIP bars, only while it
   runs; a tap opens "Extra luck for the release!" with the countdown and the two boosted steps.
6. **Odds & Details** for every block from the new data, live during the luck and when pity is
   due. The Week One Cue appears in no block's list.
7. **The "1 in N"** in the Legendary-or-better messages (the server sends the text).
8. **The restock:** 2 shared slots plus VIP's; slot 1 marked "Epic or better"; the new prices.
9. **The shop's Mystery band:** $14,900, 5 for $66,900; the Robux 5-pack after the Robux pass.
10. **The win track bar:** money steps ($1,000) between the block steps, and win 10's Epic block.
11. **Free Reward:** day 7's card shows the Week One Cue from day 1; the later weeks; the 28-day
    track (day 14 Rare, day 28 Epic); five playtime tiles; VIP's "an Uncommon block a day".
12. **Trading and the Index:** the unclimbed/climbed mark; the Week One Cue tradable and in the
    Legendary row, with "Day 7 of your first week" where block cues show odds.

The build keeps small shims so the game, lint and tests still work until these land (for
example, holding an unclimbed tier block climbs it on the server and opens it), and lists each
one.

### 11.2 The tutorial session (`~/Desktop/8ball-tutorial`, branch `tutorial-v2`)

- The first win's Rare block now arrives unclimbed (OPEN!) and climbs before its timer.
- Bronze's Mystery block works as before (scripted Standard to Uncommon); a forced result goes
  through the server's forced-roll path.
- Read every number from Config (Mystery price, rewards, playtime, the win track's money steps).
- Whichever branch merges second resolves the clashes (mostly `Config.luau`).

### 11.3 The thumbnail session

Odds labels to update (a Mystery block, after the launch; use these, or the launch numbers
only with "launch luck" in the art):

| | v5 | During the Grand Opening Luck |
|---|---|---|
| Epic or better | 1 in 32 | 1 in 21 |
| Legendary or better | 1 in 317 | 1 in 141 |
| Mythic or better | 1 in 2,116 | 1 in 941 |
| The Secret | 1 in 84,656 | 1 in 37,625 |

### 11.4 Cue art

The Week One Cue: a new Legendary look (aura, trail and pocket finisher like the other
Legendaries), plus its card icon for the calendar. You pick the look; it's its own task.

---

## 12. Clashes with past decisions

| Decision | Was | Now | Why |
|---|---|---|---|
| First-week day 7 (designer, 2026-10-08) | a Legendary block | the Week One Cue | your 2026-10-09 pick: a guaranteed Legendary for every 7-day player without flooding block Legendaries |
| 28-day day 28 (designer, 2026-10-08) | a Legendary block | an Epic block | your answer "Neither" |
| Block names (v4 plan 4) | floor = the rarity below the name | the name is the floor | your answer 5 |
| The upgrade screen | Mystery blocks only | every block | the climb is the moment |
| Win track (v4 plan 5) | a block on all 10 wins | 4 blocks and $1,000 steps | fewer, better blocks (answer 6) |
| Playtime (v4 plan 6.3) | 3 Mystery + a Rare block | 1 Mystery + money | fewer blocks |
| VIP's daily block (v4 plan 6.7) | Rare | Uncommon | a v5 Uncommon has 6× the Epic chance of v4's Rare row |
| Epic pity (v4) | by the 100th | by the 40th | answer 11 |
| Restock (v4 plan 8.4) | 3 slots + VIP | 2 + VIP, slot 1 Epic or better | your note on answer 13 |
| Mystery bundle | 10 for $44,100 | 5 for $66,900 | your note on answer 10 |
| The skip (v4 plan 8.2) | 4 R$ for 30 minutes or less | 1 R$ for 5 minutes or less, then 4 R$ | your words in chat |
| Exclusive cues | never tradable or sellable | the Week One Cue is both | your words in chat |
| Group, invite, ROOFTOP | 3 Mystery, Rare, Rare | 2 Mystery, Uncommon, Uncommon | everyone gets them |
| Claim All prices | mostly day 7's Legendary | redone | the days changed |
| Copy numbers (first 100 copies of Rare-or-rarer cues) | timed with the v4 model | re-run with v5 and reported; nothing changes without your say | more Legendary copies a day |
| `ECONOMY.md` 10.2 | Rare / 2 Rare / 2 Rare / Epic (stale) | v5's track | doc drift found 2026-10-09 |

---

## 13. The Robux pass (last)

The build writes a proposal (`05-economy-v5-robux.md`) and changes no prices; you approve, then
the products change (`--dry-run` first, never delete a product). The one exception is the 1 R$
skip below, which you already approved: the build makes that product. The rule from v4 stays: the Robux route is about 3× better value than money.

- **Mystery 1 and the new 5-pack** (today 5 R$ and 45 R$ for 10). Each v5 Mystery is worth
  about 8× a v4 one, so 5 R$ would be a giveaway.
- **The launch bonus** for the 5-pack (my lean: 5 come as 6).
- **The restock:** 39 / 149 / 599 / 1,699 R$ proposed.
- **Claim All:** the six products, re-priced for the new days.
- **The Golden Shot** (planned, 15 R$): check it against its new prizes.
- **The skip, already approved (2026-10-09):** a new 1 R$ product for 5 minutes or less left,
  which covers every Uncommon and Rare block. The 4 / 9 / 15 R$ rows stay.
- Everything else stays unless the value check says otherwise.

---

## 14. Files

- This plan: `04-economy-v5-plan.md`. The build brief: `ECONOMY_V5_PROMPT.md`.
- `economy_v5_sim.py`: the scenario simulator (`--only plan` runs this plan; `--selftest` proves
  the patched model equals v4's with no patch used; `ECONOMY_REPO` picks the repo it reads).
  Results: `economy_v5_plan.txt` and `.json`; with finder's money, the Index and selling,
  `economy_v5_sell.txt` and `.json`; the earlier runs in `economy_v5_results.*`, `economy_v5_final.*` (the four day-7 options),
  `economy_v5_rec.*`, `economy_v5_price.*`, `economy_v5_launch.*`, `economy_v5_mix.json`,
  `economy_v5_tune.json`.
- The review: `03-economy-v5-review.md`, its page `economy-v5-review.html` (built by
  `build_v5_page.py`), research in `research-2026-10-09/`.

---

## 15. Economy v5.1, "Lively" (approved 2026-10-09 evening)

The designer's question that evening: a Mystery that stopped on Rare could never give more than
a Rare, so it had no suspense, against their Mystery design of 7 October ("even a Standard can
reach Legendary"). Their aims for the fix: upgrades happen more often, blocks are opened less
often, no block is limited to its name, even a Standard can reach Legendary, Mythic and the
Secret, and the whole a little more generous than v5. They approved "Lively" on the plan page
(https://claude.ai/artifact/Ay5viRk4YeU7Rs7N1PS45Q) with "everything yes".

**The rule.** A Mystery turns into a real lucky block first, the same block the restock, the
win track and the rewards give, and that block then climbs from its name like any other.

| | v5.1 | v5 |
|---|---|---|
| The Mystery's roll (its 4-press screen; `Config.BlockOdds.Turn`) | 30 / 25 / 10 / 5% a step, Standard up to Legendary | none: one climb from Standard |
| It turns into | Standard 70%, Uncommon 22.5%, Rare 6.75%, Epic 0.7125%, Legendary 0.0375% | - |
| Both steps: Epic+ / Legendary+ / Mythic+ / Secret | 1 in 18 / 169 / 1,125 / 45,007 | 1 in 32 / 317 / 2,116 / 84,656 |
| The same in the launch month | 1 in 12 / 81 | 1 in 21 / 141 |
| Upgrades a player watches per Mystery | 0.99 (its roll 0.38) | 0.71 |
| Money price | **$19,900**, 5 for **$89,900** | $14,900, 5 for $66,900 |
| Robux | **9 R$**, 5 for **39 R$** (45 one by one) | 7, 5 for 29 |
| Playtime, 15 minutes | **$2,000** | a Mystery |
| Worth per Robux (restock: 2.75 to 4.18) | 3.83 | 2.89 |

- **Pity** stays Rare by the 10th and Epic by the 40th with the 2/10 and 10/40 head start, but
  counts the cue a Mystery finally gives. It is checked at the roll: a due Mystery turns into a
  Rare (or Epic) block, which can still climb. A roll that lands on a Rare-or-better block
  resets that counter at once; the rest ride on the block and count at its climb. Counting the
  block instead gave about 20% more Legendaries in the model.
- The Grand Opening Luck boosts every climb, never the roll. Timers, skips, VIP, the restock,
  the win track, logins, the 28-day track, rank rewards, the Week One Cue and every other
  product stay as v5.
- The tutorial's scripted first Mystery (on `tutorial-v2`) needs its own scripted climb now;
  a hand-off note for that session is in DECISIONS.md.

**What it does** (`python3 tools/economy_model.py`, the same model and Config as the game;
players active in the last 7 days who own one, day 7 / 30 / 60):

| | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|
| v5.1 | 60.86 / 69.21 / 66.66% | 14.83 / 22.24 / 18.65% | 2.57 / 4.80 / 4.58% | 0.10 / 0.17 / 0.16% |
| v5 | 58.05 / 66.59 / 64.53% | 13.57 / 20.69 / 17.49% | 2.38 / 4.72 / 4.36% | 0.08 / 0.14 / 0.13% |

A free 1-hour player opens about 5.2 blocks a day (v5: 6.7), 3.2 of them Mysteries, and climbs
to Legendary or better about 2.6 times in the launch month and 1.3 times a month after (v5: 2.5
and 1.1). Without the higher price and the playtime change, Legendary owners would reach about
24.5% at day 30 and the Mystery would be worth 4.92 per Robux, a better buy than every restock
block. The runs and the other variants (a literal "Rare stays Rare plus a climb", Balanced at 15
/ 15 / 10 / 5%) are in `~/Desktop/8ball-refs/economy/economy_v5_unified.py` and
`unified_final.txt`.
