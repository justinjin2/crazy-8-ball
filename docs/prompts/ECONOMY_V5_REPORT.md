# Economy v5: the report

The unattended build of `ECONOMY_V5_PROMPT.md` (the plan: `ECONOMY_V5_PLAN.md`), 2026-10-09, on
`gui-v4`, steps 0 to 15, each committed and pushed. Nothing is BLOCKED. Every number is in
`docs/ECONOMY.md`; the screens are the GUI session's (`ECONOMY_V5_HANDOFF.md`).

## Read this first: things that change what players get

Updated after the designer's answers (2026-10-09, later the same day):

1. **Robux prices: done.** The designer approved the proposal and the prices are live on Roblox:
   Mystery block 7 R$, the 5-pack 29 R$ (product 3717476154), restock 39 / 149 / 599 / 1,699,
   later weeks' Claim All 79 / 69 / 35, the new texts. Until `gui-v4` is published, the live
   game sells these prices with its older grants: publish once the GUI brief's screens are in.
2. **The 10-pack is off sale on Roblox** (never deleted; an old receipt still pays 10).
3. **The tutorial's first block: a scripted Mystery block** (the designer's pick, as tutorial
   v2 already plans): it climbs Standard to Uncommon on screen and is ready at once. The server
   needs a hook that forces a climb's tier (the GUI brief's economy step); `gui-v4`'s interim
   Uncommon block goes when the tutorial merges.
4. **Pity bars only in Odds & Details and on the shop's Mystery card**, never on the climb
   screen (the designer's pick).
5. **The restock's first slot is always Epic or better** (answer 13). ECONOMY 11.7's old
   "never always-on Epic blocks" line now notes it: a 10-minute rotating slot, one per player,
   at a guarantee's price.

The next step is `docs/prompts/ECONOMY_V5_GUI_PROMPT.md`: every screen for v5, then the Studio
checks and the release.

## What changed (today -> v5)

| | Today (v4) | v5 |
|---|---|---|
| How a block works | tier blocks keep a floor one below their name; the Mystery block rolls a tier | **every block climbs from its name** (the name is the floor); the tier it ends on is the cue's rarity |
| The ladder | Mystery tier roll 50 / 40 / 9.52 / 0.42 / 0.05 / 0.01% | **one ladder: 50 / 35 / 18 / 10 / 15 / 2.5%** (to Uncommon ... to the Secret) |
| A Mystery block: Epic or better / Legendary or better | about 1 in 262 / 1 in 1,860 (a cue) | **1 in 32 / 1 in 317** (launch: 1 in 21 / 1 in 141) |
| Launch luck | none | **Grand Opening Luck**: Rare to Epic 27%, Epic to Legendary 15% for 30 days |
| Pity (Mystery only) | Rare by 10, Epic by 100 | **Rare by 10, Epic by 40**, exact rarity, head start 2/10 and 10/40 |
| Blocks in the save | a block with a timer | **unclimbed** (no timer, OPEN!) then **climbed** (the tier's timer); save **version 11** |
| A Secret climb | (no climb) | the Secret cue at once, no block |
| Win track | R, M, M, U, M, M, R, M, M, E | **U, $1,000, $1,000, M, $1,000, $1,000, M, $1,000, $1,000, E** |
| First week | $5k+M, Epic, $10k, 2M, Rare, 3M, Legendary + 2 spins | $5k+M, **Rare**, $10k, 2M, **$15k**, 2M, **the Week One Cue** + 2 spins |
| Later weeks | $5k, Rare, $10k, 2M, $15k, 3M, Epic + 2 spins | $5k, **M**, $10k, **M**, $15k, **M**, **Rare** + 2 spins |
| 28-day track | $50k, Epic, $150k, Legendary | $50k, **Rare**, $150k, **Epic** |
| Playtime | $1k, M, M, M, Rare + spin | $1k, M, **$2.5k, $3.5k, $5k** + spin |
| VIP's daily block, invite, ROOFTOP | Rare, Rare, Rare | **Uncommon** each |
| Group | 3 Mystery | **2 Mystery** |
| Lucky 8, Gift, Sky | Rare row, Rare row, own row | **climb from Uncommon, Uncommon, Standard** |
| Lucky Shot gold; Golden Shot grey / blue / red / gold (planned) | Rare; $7.5k+U / Rare / $10k+Rare / $25k+2 Rare | **Uncommon; $7.5k+M / U / $10k+U / $25k+1 Rare** |
| Mystery block (money) | $4,900; 10 for $44,100 | **$14,900; 5 for $66,900** |
| Mystery block (Robux) | 5 R$; 10 for 45 R$ (13 in the launch bonus) | **7 R$; 5 for 29 R$** (6 in the launch bonus); 10-pack off sale |
| Restock | 3 slots 87 / 12 / 0.95 / 0.05% + VIP 80 / 17 / 2.8 / 0.2% | **2 slots: slot 1 Epic 75.56 / Legendary 21.11 / Mythic 3.33%, slot 2 55 / 34 / 9.5 / 1.5%; VIP 40 / 40 / 16 / 4%** |
| Restock money prices | $19,900 / $199,000 / $1,490,000 / $4,990,000 | **$49,900 / $249,000 / $1,290,000 / $4,990,000** |
| Restock Robux prices | 15 / 99 / 599 / 1,699 R$ | **39 / 149** / 599 / 1,699 R$ |
| Claim All, later weeks | 129 / 99 / 59 R$ | **79 / 69 / 35 R$** |
| Timer skip | 4 / 9 / 15 R$ | **1** / 4 / 9 / 15 R$ (1 R$ for 5 minutes or less; made on Roblox, product 3717460488) |
| Skip credits in the save | numbered by row | **kept per product** |
| New | | the **Week One Cue** (catalog row, 62 cues), **quick reveal** and **"Open all"** (server), the **"1 in N"** in Legendary-or-better messages |
| Trade | "Block:<kind>" | "Block:<kind>" (unclimbed) and **"Climbed:<tier>"**; new fallback tables (`BlockExists`, `ClimbedExists`) |
| Tutorial's Bronze block | Standard | **Uncommon, no climb** |

## What I checked

- **Lint and tests after every step:** lint OK (the three old LocalShadow warnings); **1156 Lune
  tests pass** (1139 at the start; new tests for the ladder, the luck, pity and its head start,
  unclimbed and climbed blocks, the save migration and credits, the rewards, the Week One Cue,
  the restock's slot table, the Mystery shop, Open all, the quick reveal, the "1 in N" and trade
  worth).
- **The model** (`tools/economy_model.py`) now does v5 natively from Config; `--compare`
  reproduces v4's numbers exactly from a frozen copy of v4's Config.
- **Not checked:** anything in Studio (this run had no Studio), a phone, a controller.

## The model against the plan

Players active in the last 7 days who own one (day 7 / 30 / 60):

| | The plan (7.1) | The build | v4 |
|---|---|---|---|
| Epic | 59 / 67 / 65% | 58.05 / 66.59 / 64.53% | 18.37 / 32.39 / 42.40% |
| Legendary (blocks) | 13.8 / 21.2 / 17.9% | 13.57 / 20.69 / 17.49% | 2.29 / 8.10 / 12.92% |
| The Week One Cue | 0.2 / 15.8 / 29.0% | 0.18 / 15.77 / 28.99% | - |
| Mythic | 2.4 / 4.6 / 4.3% | 2.38 / 4.72 / 4.36% | 0.30 / 0.95 / 1.74% |
| Secret | 0.08 / 0.14 / 0.12% | 0.08 / 0.14 / 0.13% | 0.03 / 0.11 / 0.18% |

- **Every number within about a point.** With selling (`--sell`): Epic 58.6 / 68.2 / 66.0%,
  Legendary 14.8 / 22.8 / 19.1%, Mythic 2.6 / 5.1 / 4.8% (the plan's middle column: 60 / 69 /
  66, 14.3 / 23.0 / 19.0, 2.7 / 5.2 / 4.8).
- **A free player (plan 7.2)**: blocks a day 4.7 / 6.7 / 11.7 at 30 minutes / 1 hour / 3 hours
  (plan 4.8 / 6.7 / 11.7); owns a Legendary by day 30 (from launch) 75 / 87 / 100% (plan 76 / 88
  / 100), a Mythic 23 / 29 / 70% (plan 20 / 33 / 69).
- **The restock (plan 6.2)**: a Legendary or better in 32.8% of restocks (46.2% with VIP's
  slot), a Mythic in 4.8% (8.6%), as the plan (tested in `tests/restock_test.luau`).
- **Small known differences from the plan's run:** the pity head start (in Config now), the
  Robux Mystery bundle (5 for 45 R$ in Config, 10 for 45 in the plan's run), the restock's Robux
  prices (v4's).
- **The copy numbers** (re-run, nothing changed): each cue's #100 gone by about day 1 (Rare and
  Epic), day 4 (Legendary), day 7 (Mythic), day 29 (the Secret); the Week One Cue's by day 9
  (v4: 1, 4, 11, 22, 35).
- Runs: `~/Desktop/8ball-refs/economy/v5-build/`.

## My calls (each a dated line in DECISIONS.md, 2026-10-09)

1. The climb's odds are worked out from the six steps, not stored as rows.
2. The Sky block's own odds row is gone (it climbs from Standard).
3. The Gift's 12-hour wait is its own field (`Wait`), before its climb.
4. Old saves' blocks all count as unclimbed and their timers end; skip credits move to their
   products.
5. A climbed block trades as its own item, "Climbed:<tier>".
6. A Secret climb gives a cue from the top row's Secret pool.
7. The tutorial's Bronze block is an Uncommon block that skips its climb; its Rare block line
   drops "opens in 5 minutes".
8. Win-track money steps count like block steps for the anti-farm and PC limits.
9. The Week One Cue sits in the Block group (Legendary effect, Classic's look, no odds line);
   rewards can carry cues; Claim All gives it as paid origin like its blocks.
10. The restock's odds line names slot 1's floor; the 5-pack's button says "Coming soon".
11. "Open all" skips any open with a special plan (none possible today).
12. The "1 in N" rounds to the nearest 3 significant figures, leaves pity out, and uses a
    never-climbing block's own row.
13. A separate `Config.Trade.ClimbedExists` table.
14. In the Robux proposal: every price in section 2 of that file (approved by the designer
    and live, 2026-10-09).

## Shims (the old client keeps working until the GUI session's screens)

1. Holding or throwing an unclimbed non-Mystery block climbs it on the server first.
2. The Reveal answer shows a Secret as Mythic (plus the true `path`).
3. `LuckyClient` plays a Secret's reel after the Mystery screen and after Hold.
4. `OddsDetails` and `ShopMysteryOdds` show the climb odds with the live luck.
5. `Ranking` folds a win-track money step into the result screen's bonus line.
6. The trade window names climbed blocks "Climbed ...".
7. `RewardsParts` names the Week One Cue in reward words.
8. The restock odds line "Slot 1: Epic or better · Slot 2: ...".
9. The Mystery band's "Coming soon" for the 5-pack.
10. The tutorial's `stay` hook.

The table with where each lives and when it goes: `ECONOMY_V5_HANDOFF.md` section 1.13.

## Where things are

- **The hand-off** (GUI, tutorial, thumbnail, cue art): `docs/prompts/ECONOMY_V5_HANDOFF.md`.
- **The Robux proposal:** `~/Desktop/8ball-refs/economy/05-economy-v5-robux.md` (approved and
  live since 2026-10-09).
- **The numbers:** `docs/ECONOMY.md` (rewritten for v5); GDD 11 and 12; ROADMAP 7.9.

## Try in Studio (none of this was possible in this run)

1. **A Mystery block and a tier block from a win**: OPEN!, the climb (a Mystery on the climb
   screen; a tier block climbs when held, shim 1), the climbed block's timer, the open and reel.
2. **The restock**: three cards, slot 1 always Epic or better, the new prices, buying one.
3. **The shop's Mystery band**: $14,900 and 5 for $66,900; 7 R$ and the 29 R$ 5-pack.
4. **Free Reward's first week**: day 2 a Rare block, day 7 the Week One Cue (named in words for
   now); equip the Week One Cue (default bands, Legendary effects).
5. **A trade of a block**: an unclimbed block and a climbed one ("Climbed Rare ...") between two
   players (Test > Clients and Servers > 2 players).
6. **The 1 R$ skip** on a climbed Uncommon or Rare block (a test purchase).
7. **The Grand Opening Luck's odds**: set `Config.Shop.Deals.GrandOpening.StartsAt` to a recent
   time in a Studio test (never published), then open Odds & Details: Rare to Epic 27%.
8. Also: the tutorial's game-1 block (Uncommon, opens to an Uncommon cue), the first win's
   Rare block, a few `/giveblock Mythic` blocks held one by one (a 2.5% Secret climb plays its
   reel after the hold, shim 3), the result screen's bonus line on a money step, and `OpenAll`
   (no button yet; the request answers).

## How to go back

The branch **`before-economy-v5`** (pushed) is `gui-v4` at the starting commit `f4e17c0`. To undo
v5: make a new branch from it, or revert the economy v5 commits on `gui-v4` (from `f39f815`
"Economy v5: the build brief" to "step 15"; nothing else was committed in between). The 1 R$
skip product stays on Roblox either way (unused by v4).
