# Economy v6: the plan and the build checklist

Approved by the designer on 2026-10-10 ("yes to all of those, build this economy now"). The plan
page with every number and the simulation against v5.2: https://claude.ai/artifact/LngEA3qwDYZBZ7iPQkHkBK
(copy and the simulator in `~/Desktop/8ball-refs/economy/v6/`). This file is the build's memory:
tick each box as it is done so a session that lost its context can carry on.

## Decisions (designer, 2026-10-10)

- Pace: ~3 blocks a day for a 1-hour player; Epic on day 1 ~1 in 10; Legendary from luck every
  1-2 months.
- **Sky Lucky Block**: every 30 min of active play in a day, **max 1 a day** (yes to A); needs one
  finished real match that day; pauses when idle; climbs from Standard; falls with the Gift
  cutscene; top banner "Next Sky Lucky Block in mm:ss".
- **B yes**: a duplicate Common or Uncommon turns into its sell money ($200 / $500) instead of a
  copy ("Duplicate · +$200").
- **C yes**: trading unlocks after 10 real wins.
- VIP unchanged (399 R$, 199 R$ welcome offer, perks). Candy Cane Cue to both invite players,
  tradable. Solo and practice vs bot: small money only.
- **Grand Opening**: active, **45 days**, StartsAt set to the moment the designer publishes v6.
  **Launch bonus: +30% on money packs only** (no 6th Mystery). Grand Opening Luck removed.
- **Wipe**: every save and every game-wide counter starts over (new DataStore names).
- Chroma and Candy Cane cards in reward GUIs reuse the cue card pictures.

## The numbers

Climb steps: C→U 40%, U→R 30%, R→E 10%, E→L 15%, L→M 10%, M→S 2.5%. Mystery roll 30/20/10/5.
Pity Rare 10, Epic 50, no head start. No launch luck.
Timers: Uncommon 5 min, Rare 10 min, Epic 1 h, Legendary 12 h, Mythic 24 h. Skips 1/4/9/15 R$
for ≤10 min / ≤1 h / ≤12 h / more.
Win track: Mystery, $250, $250, $250, Mystery, $250, $250, $250, $250, Rare; no first-win Rare.
First week: $5,000 · 2 spins · 1 Mystery · $30,000 · 2 Mysteries · a Rare block · Chroma Cue (7 in
a row) else an Epic block. Later weeks: $1,000 · $2,500 · $5,000 · 1 spin · 2 spins · 1 Mystery ·
a Rare block. 28-day: d8 1 Mystery, d14 Rare block, d21 $50,000, d28 Epic block.
Playtime: 5m $250, 15m $250, 30m $500, 45m $500, 60m $1,000 + 1 spin.
Ranks: divisions Bronze 1k, Silver 2k, Gold 3k, Plat 5k, Diamond 10k, Expert 20k, Veteran 30k,
Master 50k, GM 75k. Tiers: Bronze $2,500 + Uncommon; Silver $5,000 + Rare; Gold $10,000 + Rare;
Plat $20,000 + Epic; Diamond $40,000 + Epic; Expert $75,000 + Legendary; Veteran $150,000 +
Legendary; Master $250,000 + 2 Legendary; GM $500,000 + Mythic; Reyes $1,000,000 + 2 Mythic.
Spins as before.
Index find (claimed): C 250, U 500, R 1,000, E 2,500, L 10,000, M 25,000, S 100,000, Ranked and
Exclusive 1,000, Unique 5,000. Rows: C 5k, U 10k, R 25k, E 100k.
Sell: C 200, U 500, R 2,000, E 10,000, L 100,000, M 1,000,000, S 10,000,000.
Social: group 1 Mystery; favorite $5,000 + Lucky 8; invite Candy Cane Cue (both). Codes: WELCOME
$5,000, 8BALL $2,500, ROOFTOP $2,500, RELEASE 3 spins; LIKES1K $10,000 + Mystery, LIKES5K 2
Mysteries, LIKES10K Rare + 3 spins, LIKES25K Rare + $25,000, LIKES50K 2 Rare, LIKES100K Epic + 5
spins.
Shop money: Mystery $25,000, 5 for $100,000; Grand Opening $100,000 / 3 $270,000 / 10 $850,000;
restock Rare $100,000, Epic $500,000, Legendary $2,500,000, Mythic $5,000,000; spin $10,000.
Robux: Mystery 9 / 39; Grand Opening 39 / 99 / 299; restock 39 / 199 / 999 / 1,699; later-week
Claim All 49 / 39 / 19 (first week 499 / 449 / 399).
Grand Opening odds: Rare 85.875, Epic 9, Legendary 1.3, Mythic 0.12, Secret 0.005, Firework 3.5,
Beta 0.2; Beta guarantee at the 500th.
Practice vs bot and Solo: $30 a ball up to $3,000 a day shared, then $10; no bonus, XP, blocks or
steps. Daily Challenge numbers (planned): see the plan page section 9.

## Build checklist

- [x] 1 Config numbers (all of the above) + products_spec.json + Robux sync (dry run first)
- [x] 2 Catalog: Chroma and Candy out of the blocks; WeekOneCue retired (Chroma is day 7)
- [x] 3 Invite gives the Candy Cane Cue (both); counters count it
- [x] 4 Tutorial: real Mystery, Bronze Uncommon block, both ready at once; texts
- [x] 5 Index: finder's money claimed in the Index (unclaimed list, claim, dot)
- [x] 6 Duplicates of Common/Uncommon pay money instead of a copy (server + result card)
- [x] 7 Trade gate: 10 real wins
- [x] 8 Sky Lucky Block: server timer, drop via the Gift cutscene, top banner
- [x] 9 Practice/Solo pay rows
- [x] 10 Grand Opening 45 days, launch bonus packs only, luck removed; StartsAt at publish
- [x] 11 Wipe: new DataStore names for saves and every global counter
- [x] 12 Strings / GUI texts (Odds & Details, VIP texts, reward cards with Chroma/Candy pictures)
- [x] 13 Bots' cues and trade fallback tables refit
- [x] 14 Tests (1205 pass), lint, Studio check on PC (phone and gamepad: the designer's look)
- [x] 15 Docs: ECONOMY.md v6, GDD pointers, DECISIONS, STATUS, ROADMAP; the model replaced
