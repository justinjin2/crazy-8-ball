# Economy v5: build the approved plan (an unattended nonstop run)

Written 2026-10-09 by the designer (Justin, Roblox name Painicane) with Claude. You are a Claude
Code session in `~/Desktop/8ball` on branch `gui-v4`. You will:

1. read the plan and how the economy works today,
2. build economy v5 everywhere it lives, nonstop, step by step (the Progress list at the end),
3. write the hand-offs for the GUI, tutorial and thumbnail sessions,
4. write the Robux price proposal for the designer (a file; no stop),
5. write the report.

**The spec is `docs/prompts/ECONOMY_V5_PLAN.md`**, a copy of
`~/Desktop/8ball-refs/economy/04-economy-v5-plan.md`. The designer approved it by starting this
run. The research, the interview and the simulations are done: build what it says. Every number
in it was simulated by `~/Desktop/8ball-refs/economy/economy_v5_sim.py` (`--only plan`).

**The designer has left and is not watching. Never stop to ask.** Decide, log it, and keep
going until every Progress step is ticked. The designer is a beginner: the report explains
every decision in plain words.

---

## 0. Where you work, and what you never touch

- **Your folder:** `~/Desktop/8ball`, branch `gui-v4`. Nothing else uses it right now (the
  designer, 2026-10-09: "nothing is using the 8ball main folder... just directly edit the main
  project folder"). This brief, the plan copy and the Stop hook
  `tools/overnight/economy_v5.json` are in it, uncommitted; step 0 commits them.
- **A backup first:** step 0 makes the branch `before-economy-v5` at the starting commit and
  pushes it, so the designer can always go back.
- **`place/8ball.rbxl` has the designer's own uncommitted change.** Never stage, commit, stash,
  reset, check out or delete it. Stage files by name: never `git add -A`, `git add .`,
  `git commit -a`, `git stash` or `git reset --hard`.
- **No Studio for the whole run:** no Rojo, no Studio MCP tools, no place files, no
  publishing. Check everything with Lune (`tools/lint.sh`, `tools/test.sh`). Anything that truly
  needs Studio goes on the report's "try in Studio" list.
- **Other sessions, never touch:** `~/Desktop/8ball-tutorial` (branch `tutorial-v2`, Rojo
  34877; it may be running), `~/Desktop/8ball-abilities`, `~/Desktop/8ball-gui-v3`,
  `~/Desktop/8ball-lane-backup`, and every `~/Desktop/8ball-refs/` folder except `economy/`.
- **Where you write:**
  - code and docs: `~/Desktop/8ball`;
  - simulation output and the Robux proposal: `~/Desktop/8ball-refs/economy/`.
- **Git:** commit and push only `gui-v4` and `before-economy-v5`. Never push or change `main`,
  `release`, `tutorial-v2` or any other branch. Never force-push or rewrite history.
- **Robux products: exactly one change.** The 1 R$ skip (`LuckyBlockSkip1`) is approved
  (section 6). Make it with `python3 tools/roblox_products.py --only LuckyBlockSkip1 --dry-run`,
  then the same without `--dry-run`. Never run `--sync`, and never create, change, reprice or
  delete any other product: every other price is a proposal for the designer. The API key is
  in the macOS Keychain (`ROBLOX_API_KEY`): never print, echo, log or write it.
- **No uploads.** This run needs no images.
- **If a step is truly blocked**, tick it as `- [x] BLOCKED: <why>`, write it in Notes and the
  report, and move on to the next step.

---

## 1. How the run goes

1. **Step 0, setup:** the backup branch, commit the three files, lint and the tests green, the
   baseline numbers.
2. **Read** (section 2).
3. **Build nonstop**, following the Progress list. After each step: `tools/lint.sh`,
   `tools/test.sh`, re-run the model when numbers changed, then commit (files by name) and push
   `gui-v4`, and tick the step. Keep the plan, Config, the model and `ECONOMY.md` in sync.
4. **The Robux proposal** (a file, section 6) and **the report** (section 7). Then the run ends.

**Deciding:** decide everything yourself, choosing what the designer would most likely want
from the plan, their past decisions and simple Roblox game design. Log each call as a dated line
in `docs/DECISIONS.md` marked "(Claude's call)" and list it in the report. If the code
contradicts the plan in a way that changes what players get, pick the option closest to the
plan's numbers and rules, and put it at the top of the report.

---

## 2. Read first

- `docs/prompts/ECONOMY_V5_PLAN.md`, all of it. Sections 3 to 6 are the rules and numbers;
  section 10 lists where they land; section 11 the hand-offs; section 12 the clashes.
- `~/Desktop/8ball-refs/economy/03-economy-v5-review.md`: why (skim).
- `CLAUDE.md` (the house rules apply: scripts only under `src/`, every tunable in Config with a
  comment, saves only through the versioned save layer, player-facing words in `Strings`,
  commit as soon as a step is verified).
- In `docs/`: `STATUS.md`, all of `ECONOMY.md` (v4, today), `GDD.md` sections 11 and 12, the
  last week of `DECISIONS.md`, and `prompts/ECONOMY_V4_PROMPT.md` with the v4 commits
  (`git log --oneline --grep="v4"`): build v5 the way v4 was built.
- In `src/shared/Config.luau`: `BlockOdds` (rows, `Drop`, `Upgrade`, pity, `SellBack`,
  `Announce`), `LuckyBlocks` (kinds, timers, skips, the Gift), `Daily`, `Trade`, `Social`,
  `Planned`, `Shop` (`Deals`, `Mystery`, `Restock`, `LaunchBonus`), `Products`, `Index`, and the
  rank rewards. The catalog: `src/shared/Progression/Catalog.luau`.
- The code: `src/shared/Progression/` (`BlockDrop`, `BlockOdds`, `LuckyBlocks`, `Daily`,
  `Restock`, `Shop`, `ShopView`, `Trade`, `Catalog`, `Inventory`, `Social`, `SaveSchema`), the
  server (`LuckyBlockService`, `Rewards`, `Store`, `Items`, `Social`, `GiftDropService`, the
  announcement code), and the client scripts that read these (`MysteryReveal`, the hotbar and
  bag, the opening and reel, the shop, Free Reward, the trade window), so your shims keep them
  working.
- The reference simulator, `~/Desktop/8ball-refs/economy/economy_v5_sim.py`: how the plan's
  numbers were made. It patches `tools/economy_model.py` in `~/Desktop/8ball` (or wherever
  `ECONOMY_REPO` points).

---

## 3. What to build

### 3.1 The ladder (plan 3.1-3.4)

- **Config:** one climb table in `Config.BlockOdds`: the six step chances in parts of
  `OddsTotal` (500,000 / 350,000 / 180,000 / 100,000 / 150,000 / 25,000), the Grand Opening
  Luck's two steps (Rare 270,000, Epic 150,000), and its window: from the Grand Opening deal's
  `StartsAt`, for its own 30 days.
- **Every climbing kind names its start:** Mystery Standard (with pity), the six tier kinds
  their own tier, Lucky 8 Uncommon, the Gift Uncommon, the Sky block Standard. The Grand Opening
  and Starter blocks keep their rows and never climb.
- **`BlockDrop`/`BlockOdds`:** roll the final tier from any start (the ladder, the live luck,
  pity for a Mystery only); `startOf` with a floor (the higher of the start and the final tier
  minus `Clicks - 1`); the press path; the odds lists (`rarityOdds`, `cueGroups` and the rest)
  for every kind, live during the luck and when pity is due.
- **The ladder has 7 tiers:** the Secret is on top. A climb that reaches it gives the Secret cue
  at once; there is no Secret block.
- **Tests:** every number in the plan's 3.3 and 3.4 tables, exact (they are products of the
  steps); the roll's final odds equal the listed odds; a climbed block of a tier always gives a
  cue of that rarity; the Week One Cue is in no list.

### 3.2 Unclimbed and climbed blocks (plan 3.5, 3.7)

- **Every new block of a climbing kind arrives unclimbed**, with no timer (the Gift keeps its
  12-hour comeback wait). The climb request (today's Mystery Reveal, made general) turns it into
  the **climbed** block of the final tier, on that tier's timer (VIP: none; a bought block:
  none). A climbed block never climbs again; an unclimbed one always can.
- **Saves:** mark climbed blocks. Bump the save version with a migration: blocks in older saves
  count as unclimbed (pre-release test saves; generous). `tutorial-v2` is also at version 10:
  write in the report that its merge will need to renumber if it bumps too.
- **Shims for today's client** (screens are the GUI session's, section 4): holding an unclimbed
  non-Mystery block climbs it on the server and opens it; the Mystery screen keeps working with
  v5 odds; a Secret result never breaks a screen that doesn't know the Secret tier yet (pick the
  safest way after reading the client). List every shim.
- **Tests:** the states, the timers, the migration, the shims.

### 3.3 Pity (plan 3.6)

`PityRare` 10, `PityEpic` 40, a head start for new saves only (Rare counter 2, Epic 10), Mystery
blocks only, and a pity result is exactly that rarity. Tests.

### 3.4 Rewards (plan section 4)

The win track with money steps (Uncommon, $1,000, $1,000, Mystery, $1,000, $1,000, Mystery,
$1,000, $1,000, Epic); the first win's Rare block unchanged; the first week, the later weeks and
the 28-day track; VIP's Uncommon block (its restricted money unchanged); the five playtime gifts;
ROOFTOP; the group (2 Mystery); invites (Uncommon); the favorite's Lucky 8; the Gift;
`Config.Planned`'s Lucky Shot and Golden Shot prizes. The legacy `WeekBonus` stays consistent
with day 28 (an Epic block). Tests.

### 3.5 The Week One Cue (plan section 5)

- A catalog row (`WeekOneCue`, working name "Week One Cue" in `Strings`): rarity Legendary, in
  no block's pool, reel or odds list; tradable; sellable for the Legendary price; Legendary
  finder's money; counted in the Index's Legendary row; numbered copies like every
  Rare-or-rarer cue. Choose the catalog group the code handles most cleanly, and prove the
  rules with tests.
- First-week day 7 grants it (a cue, plus the day's 2 spins); Claim All grants it too. A player
  who already owns one (from a trade) gets another copy.
- No farming limits (the designer: "all of that will be worried about IF this game does good").
  Today's first-week rule stays (7 login days within 14, each with a finished match).
- Its look: the default cue look until its art exists (hand-off 11.4).

### 3.6 The restock (plan 6.2)

2 shared slots plus VIP's; slot 1's own table (Epic 7,556 / Legendary 2,111 / Mythic 333 of
10,000); slot 2 (Rare 5,500 / Epic 3,400 / Legendary 950 / Mythic 150); VIP's (4,000 / 4,000 /
1,600 / 400); prices $49,900 / $249,000 / $1,290,000 / $4,990,000; stock Rare 2, the others 1;
the banner unchanged. A restock block is unclimbed (it climbs from its tier). The Robux prices
stay as they are until the designer approves new ones. Tests, including the per-restock chances
(Legendary or better 32.8%, Mythic 4.8%; with VIP's slot 46.2% and 8.6%).

### 3.7 The Mystery shop (plan 6.1)

`Shop.Mystery` and `Shop.Deals.Mystery`: $14,900, 5 for $66,900. A `Mystery5` products row (Id
0, so the Robux 5-pack shows "Coming soon" until the designer approves its price and it is
made); `Mystery10` and `Mystery10Sale` stay, retired, and an old receipt still pays what it
bought. `LaunchBonus.MysteryBulkCount` for the 5-pack: 6. Tests.

### 3.8 Quick reveal and "Open all" (plan 3.8)

Config for which results get the quick reveal (Common, Uncommon), and a server request that opens
every ready climbed Standard and Uncommon block at once, rate-limited, returning the cues. Tests.

### 3.9 The "1 in N" (plan 3.9)

Legendary-or-better messages carry the chance of that exact cue from the block it started as,
with the odds live at the climb, rounded to 3 significant figures (store what you need on the
climbed block). Words in `Strings` with placeholders. Tests.

### 3.10 Trade (plan section 8)

An unclimbed block's worth from its climb odds and the live copies; a climbed block's from its
tier; `Config.Trade.BlockExists` refilled from your model at day 30. Tests.

### 3.11 The model and the docs

- **`tools/economy_model.py` does v5 natively** (port the reference simulator's patches: climbs
  from any start, money steps on the win track, the launch luck, the restock's first slot, the
  Week One Cue; the selling/finder's-money/Index option too). It reads every number from Config.
  Its default run must match the plan's section 7.1 within noise (about 1 point). Keep
  `--compare` (v4 side by side). Rewrite `tools/economy_config.json` through
  `tools/export_economy.luau`.
- Re-run the copy-number timeline (`tools/economy_model.py copies`) and report it; change
  nothing there.
- **Docs:** `docs/ECONOMY.md` rewritten for v5 (the designer's answers dated 2026-10-09, and fix
  the stale 10.2 track); GDD sections 11 and 12; one dated `DECISIONS.md` line per answer and per
  call; a `ROADMAP.md` box; `STATUS.md` ("economy v5 built on `gui-v4`; screens next").

---

## 4. Hand-offs

Write `docs/prompts/ECONOMY_V5_HANDOFF.md`: the plan's section 11 made concrete. For each GUI
item: what the player sees, the Config keys and shared functions it reads, the requests or
remotes it calls, and the shim it replaces. Then the tutorial session's list and the thumbnail
labels (plan 11.2, 11.3) and the Week One Cue's art (11.4). The GUI session builds the screens
next, in this same folder; never edit client scripts beyond a shim that keeps the game working.

---

## 5. Tests and checks

- Lint and the tests after every step; new tests for every rule above.
- The model's numbers against the plan (7.1, 7.2, 6.2's restock chances) in the report.
- A "today → v5" table of every changed number in the report.

---

## 6. Robux

### 6.1 Approved: the 1 R$ skip (build it in step 8)

The designer, 2026-10-09: "for uncommon/rare the skip timer should be reduced to just 1 robux
since really are people going to spend 4 robux to skip a 60 second timer".

- A new first row `{ UpTo = 300, Product = "LuckyBlockSkip1" }` in `Config.LuckyBlocks.Skips`
  (5 minutes or less left: every Uncommon and Rare block). `SkipProduct` stays on the cheapest.
  The 4 / 9 / 15 R$ rows stay as they are.
- Saved skip credits are numbered by row today (`SkipCredits1`, `SkipCredits2`, `SkipCredits`),
  so a new first row would change what they buy. Migrate them (or key them by product) so every
  saved credit keeps the price it was bought at. Tests.
- The product: add `LuckyBlockSkip1` (1 R$, Random like the other skips) to
  `tools/products_spec.json`, then `python3 tools/roblox_products.py --only LuckyBlockSkip1
  --dry-run`, then the same without `--dry-run`; its id from `tools/products_ids.json` into
  `Config.Products`. Nothing else.

### 6.2 Everything else: a proposal, no changes

Write `~/Desktop/8ball-refs/economy/05-economy-v5-robux.md`: each item with today's price, your
proposed price and the reason, from `tools/economy_model.py value` (Robux to pull each rarity,
money against Robux). v4's rule stays: the Robux route is about 3× better value than money.
The items: Mystery 1 and the new 5-pack (today 5 R$, and 45 R$ for 10); the launch bonus for
the 5-pack; the restock (39 / 149 / 599 / 1,699 R$ proposed in the plan); the six Claim All
products (the first week no longer ends on a Legendary block); the Golden Shot (planned); VIP's
perk text. Don't change any of these products: the designer approves them later.

---

## 7. The report

`docs/prompts/ECONOMY_V5_REPORT.md`, short and in plain words:

- what changed (the today → v5 table) and what you checked;
- the model against the plan;
- every "(Claude's call)", every shim, every BLOCKED step;
- where the hand-off file and the Robux proposal are;
- **try in Studio:** a Mystery block and a tier block from a win (climb and open), the restock,
  the shop's Mystery band, Free Reward's first week, a trade of a block, the 1 R$ skip, and the
  Grand Opening Luck's odds with a test `StartsAt`;
- how to go back if needed: the `before-economy-v5` branch.

---

## Progress (tick each box when it is verified, committed and pushed)

- [x] 0. Setup: make and push the branch `before-economy-v5` at the starting commit; commit this
  brief, `docs/prompts/ECONOMY_V5_PLAN.md` and `tools/overnight/economy_v5.json` (by name); copy
  any git-ignored tool files lint or the tests need; lint and tests green; save
  `python3 tools/economy_model.py` to `~/Desktop/8ball-refs/economy/v5-build/baseline.txt`; run
  `python3 ~/Desktop/8ball-refs/economy/economy_v5_sim.py --selftest` and `--only plan` and check
  it matches `economy_v5_plan.txt` (small differences are fine if Config changed since: note
  them); push `gui-v4`.
- [x] 1. Read section 2; write the touch list (every file you expect to change) in Notes.
- [x] 2. The ladder (3.1).
- [x] 3. Unclimbed and climbed blocks, saves and shims (3.2).
- [x] 4. Pity (3.3).
- [x] 5. Rewards (3.4).
- [x] 6. The Week One Cue (3.5).
- [x] 7. The restock (3.6).
- [x] 8. The Mystery shop (3.7), and the 1 R$ skip with its credit migration and its product
  (6.1).
- [x] 9. Quick reveal and "Open all" (3.8).
- [x] 10. The "1 in N" (3.9).
- [x] 11. Trade (3.10).
- [x] 12. The model v5, `economy_config.json`, the copy-number timeline (3.11).
- [x] 13. The docs (3.11) and the hand-off file (section 4).
- [x] 14. The Robux proposal file (6.2), with no product changes.
- [ ] 15. The report (section 7) and `STATUS.md`.

---

## Notes (yours: the starting commit, the touch list, every call, every shim, open items)

- **Starting commit:** `f4e17c0` (gui-v4, 2026-10-09). Backup branch `before-economy-v5` made
  there and pushed.
- **Step 0 checks:** lint OK (three old LocalShadow warnings); 1139 Lune tests pass (156 s);
  `economy_model.py` baseline saved to `~/Desktop/8ball-refs/economy/v5-build/baseline.txt`
  (v4: every target met); `economy_v5_sim.py --selftest` True; `--only plan` is identical to
  `economy_v5_plan.txt` (no Config change since). No git-ignored tool files were needed.
- **Touch list (step 1):**
  - Config: `BlockOdds` (a `Climb` table: the six steps, the Secret on top, the Grand Opening
    Luck's steps and window; the tier rows become "the climbed block": exactly its rarity;
    `Drop`: pity 10 / 40 with `PityStart` 2 / 10, the win track with "Money" steps and
    `WinTrackMoney`; `Upgrade.Chances` and `Weights` go: the ladder computes them),
    `LuckyBlocks.Kinds` (`Climb` = the start; `Wait` = the Gift's 12 h before its climb;
    `Reveal.Tiers.Secret` for the Mystery screen), `Skips` (the 1 R$ row), `Daily`, `Social`,
    `Planned`, `Shop` (`Mystery`, `Deals.Mystery`, `Restock`, `LaunchBonus`), `Trade`
    (`BlockExists`), `Products` (`Mystery5` Id 0, `LuckyBlockSkip1`, `Mystery10` retired).
  - Shared: `BlockDrop` (the climb from any start, luck, pity, `startOf` with a floor, `path`,
    the odds lists for every kind), `BlockOdds`, `LuckyBlocks` (climbed/unclimbed, timers,
    `Wait`, skip credits by product, Open all), `Catalog` (`WeekOneCue`, block cues with no
    rows drop from nothing), `SaveSchema` (version 11), `Daily` (cues in rewards),
    `RewardView` (money steps, the cue), `Restock` (slot 1's table), `Shop`, `ShopView`,
    `Trade` (climbed items, worth), `Strings`.
  - Server: `PlayerData` (climb, open, win track money, credits), `LuckyBlockService` (the
    general climb request, the Hold shim, the Secret, Open all, the 1 in N), `Ranking` (the
    money step), `Announce` (1 in N), `Store` (skip tiers, Mystery5), `Trading`, `DevCommands`.
  - Client shims only: `LuckyClient` (a Secret result), `OddsDetails` (climb odds for an
    unclimbed kind's dice).
  - Tests: blockdrop, blockodds, luckyblocks, save_schema, daily, restock, shop, trade,
    catalog, inventory, config. Tools: `economy_model.py`, `export_economy.luau`,
    `economy_config.json`, `products_spec.json`, `products_ids.json`. Docs: ECONOMY, GDD 11-12,
    DECISIONS, ROADMAP, STATUS, the hand-off and the report.
- Steps 2-4 (one commit: the ladder, the climbed blocks and pity share BlockDrop and the save):
  `Config.BlockOdds.Climb` and `Drop` (pity 10/40, head start 2/10), tier rows = climbed
  blocks, Sky row removed, `LuckyBlocks` Climb/Wait/Pity/Roll, save v11 (blocks unclimbed,
  credits by product), trade items "Climbed:<tier>", tutorial game-1 block Uncommon with a
  `stay` hook. The model (`tools/economy_model.py`) still reads v4's `Drop.Weights` and fails
  to load until step 12 ports it; numbers are checked against the plan's tables in
  `tests/blockdrop_test.luau` meanwhile.
- Shims (keep today's client working until the GUI session's screens): (1) Hold/Throw of an
  unclimbed non-Mystery block climbs it on the server first (`LuckyBlockService.climbFirst`);
  (2) Reveal answers `tiers` with the Secret shown as Mythic (`BlockDrop.shown`) plus the true
  `path`, `secret`, `cue`; (3) `LuckyClient` plays a Secret's cue reel after the Mystery screen
  (and after Hold); (4) `OddsDetails` and `ShopMysteryOdds` show climb odds with the live luck;
  (5) `Ranking` folds a win track money step into the result screen's bonus line; (6) the
  trade window names climbed blocks "Climbed ...".
- Step 5: rewards set in `Config.Daily`, `Social`, `Planned` (the win track was set in step 2).
  First-week day 7 stays the Legendary block until step 6 makes it the Week One Cue. VIP texts
  say "Uncommon"; the tutorial's Rare block line drops "opens in 5 minutes".
- Step 6: `WeekOneCue` (Block group, no rows), `Catalog.droppable` skips cues with no rows in
  the Extra rows' whole pool, `Daily` rewards carry `cues`, the server counts the copies on a
  claim and on Claim All, `InventoryCues.oddsLine` shows no chance for it, `RewardsParts`
  names it in reward words (a shim). Studio check: equip it (default bands, no skin).
- Step 7: `Config.Shop.Restock` Slots 2 + `SlotOdds` (slot 1), `Restock.oddsOf`,
  `Restock.chanceOf` (32.8% / 4.8%, 46.2% / 8.6% tested). Client shim: the restock odds line
  names slot 1's floor and slot 2's odds. Studio check: the restock panel with three cards.
- Step 8: Mystery $14,900 / 5 for $66,900, `Mystery5` Id 0, `Mystery10` retired, launch bonus
  6 for 5. `LuckyBlockSkip1` made on Roblox (dry run, then the real run): id 3717460488 in
  `Config.Products` and `tools/products_ids.json`; spec row added to `tools/products_spec.json`.
  The credit migration was step 3's (credits by product). No other product touched. Client
  shim: the Mystery band's Robux button reads "Coming soon" for `Mystery5`.
- Step 9: `Config.LuckyBlocks.QuickReveal`, `QuickRevealSeconds`, `OpenAll`;
  `LuckyBlocks.quickReveal`, `openAllIds`, the "OpenAll" action and "NoneReady" reason;
  `LuckyBlockService` HANDLERS.OpenAll. No client button yet (the GUI session's): Strings
  `OpenAll`, `OpenAllSummary`, `OpenAllOne` are ready for it.
- Step 10: `LuckyBlocks.oneIn(cue, from, luck)`, `Format.oneIn`, `Strings.Banner.OneIn`; the
  Unbox payload carries `oneIn` and `from`; `Banner` appends it. Every open now passes its
  start kind (a never-climbing kind uses its own row).
- Step 11: `Trade.blockWorth(kind, copies, climbed)` (step 3), `Config.Trade.BlockExists`
  from `tools/economy_model.py exists` at day 30 (v5), new `ClimbedExists`; the worth fallback
  reads the climbed table for "Climbed:" items. The model's port is step 12's commit.
- Step 12: the model's runs are in `~/Desktop/8ball-refs/economy/v5-build/` (`model_v5.txt`,
  `model_compare.txt`, `model_copies.txt`, `model_tables.txt`, `model_value.txt`,
  `model_sell.txt`, `model_exists.txt`, `model_players.txt`). Default run within about a point
  of plan 7.1 everywhere; `--sell` matches `economy_v5_sell.txt`. Small known differences from
  the plan's run: the pity head start (now in Config), the Robux Mystery bundle (5 for 45 R$
  in Config, 10 for 45 in the plan's run) and the restock's Robux prices (v4's in Config).
- Step 13: `docs/ECONOMY.md` rewritten for v5 (the stale 10.2 track fixed; doc drift caught up
  too: the Claim All products, the retired Lucky Spins, the Starter Pack's 29 R$), GDD 11 and 12
  (and the tutorial lines in GDD 14 that named the Standard block), 31 dated DECISIONS lines
  (the designer's 15 answers, the plan's 15 calls, the docs step), ROADMAP box 7.9, stale
  remote comments in `Net.luau`, and `docs/prompts/ECONOMY_V5_HANDOFF.md` (GUI 1.1-1.13 with
  the shim table, the tutorial list, the thumbnail labels, the Week One Cue's art). Found: the
  designer removed the pity counters from the Mystery upgrade screen earlier on 2026-10-09,
  while answer 14 asks for pity bars: the hand-off asks the GUI session to show concept art
  first. `tutorial-v2` no longer has `Config.Tutorial.BronzeBlockKind` and calls
  `setOpenHooks` with two arguments: listed for whichever branch merges second.
- Step 14: `~/Desktop/8ball-refs/economy/05-economy-v5-robux.md`. Proposed: Mystery1 7 R$, the
  5-pack 29 R$ (6 during the launch bonus), restock 39 / 149 / 599 / 1,699 R$ (the plan's),
  Claim All first week unchanged 399 / 349 / 299 and later weeks 79 / 69 / 35 (half the shop
  value, v4's rule), the Golden Shot 15 R$ unchanged, VIP's text "an Uncommon Lucky Block every
  day". Checked with the game's model at those prices without touching Config
  (`v5-build/robux_value.txt`, `robux_sim.txt`): every cheapest pull inside the designer's feel
  ranges, ownership unchanged (noise). No product, spec or Config price changed; the paste-ready
  spec rows and the make-it-live steps are in the file.
