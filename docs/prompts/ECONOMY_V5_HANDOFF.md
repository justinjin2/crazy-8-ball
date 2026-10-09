# Economy v5: the hand-offs

Written 2026-10-09 by the economy v5 build (`ECONOMY_V5_PROMPT.md`, on `gui-v4`). The plan is
`ECONOMY_V5_PLAN.md`; every number is in `docs/ECONOMY.md`. The economy, its saves, requests and
tests are built and Lune-tested; **the screens are not**. This file is the plan's section 11
made concrete: for each screen, what the player sees, what it reads, what it calls and the shim
it replaces.

Who it is for:

1. **The GUI session** (`~/Desktop/8ball`, branch `gui-v4`): section 1. Follow the lively-gui
   skill and `docs/UI_STYLE.md`; concept art first, one screen at a time (the designer's rule).
2. **The tutorial session** (`~/Desktop/8ball-tutorial`, branch `tutorial-v2`): section 2.
3. **The thumbnail session**: section 3.
4. **The cue-art task** (the Week One Cue): section 4.

Every player-facing word lives in `src/shared/Strings.luau`; the ones the build already added
are named below. Read the climb's odds from the shared functions, never from typed numbers: the
Grand Opening Luck changes them live for 30 days.

---

## 1. The GUI session

### 1.1 The climb screen for every block

**What the player sees.** Every new block (Mystery, the tier blocks, Lucky 8, the Gift once its
12-hour wait ends, the Sky block, restock and reward blocks) lands **unclimbed** in its hotbar or
bag slot with **OPEN!** and no timer. A tap opens the climb screen: the block over a blur, **4
presses**, the first showing its start (its own tier, or higher), each later press climbing one
tier or not, never down. The screen shows **7 tiers** with the **Secret on top**. After the last
press the block jumps back into its slot as the **climbed** block of that tier, on that tier's
timer (none for a VIP or a bought block), and opens later with the reel as today. A climbed
block never climbs again.

**Reads.**
- `BlockState` (remote): `{ blocks = { { id, kind, readyAt, climbed? } } }`; `climbed` marks a
  climbed block (`LuckyBlocks.snapshot`).
- `LuckyBlocks.climbs(kind)` (the kind climbs at all), `LuckyBlocks.unclimbed(block)` (the
  saved block has its climb ahead), `LuckyBlocks.wait(kind)` (the Gift's wait),
  `LuckyBlocks.timer(kind)`.
- `Config.LuckyBlocks.Kinds[kind].Climb` (its start tier), `Config.BlockOdds.Climb.Tiers` (the
  7 tiers, Secret on top), `Config.BlockOdds.Climb.Rarity` (tier to cue rarity),
  `Config.BlockOdds.Drop.Upgrade.Clicks` (4).
- `BlockDrop.startOf(final, start)`, `BlockDrop.path(final, rng, start)` (already done by the
  server; the client only replays `path`).

**Calls.** `BlockRequest("Reveal", id)` for any unclimbed block (it answers "NotMystery" for a
block with no climb ahead). The answer:
`{ ok, id, tiers, path, kind, readyAt, pity = { rare, epic }, from, luck, secret, cue?, rarity?,
new?, found?, count? }`. **Use `path`** (the true presses, the Secret included); `tiers` is the
old screen's copy with the Secret shown as Mythic. `kind` and `readyAt` are the climbed block's.

**Replaces shims.**
- Shim 1: `LuckyBlockService.climbFirst` (server). Holding or throwing an unclimbed
  non-Mystery block climbs it on the server, then it opens as before. Once the client sends
  every unclimbed block to the climb screen, make `HANDLERS.Hold` refuse an unclimbed block
  with `"Reveal"` as it does for the Mystery block today (the Mystery's `Roll = true` in
  `Config.LuckyBlocks.Kinds` is what `Hold` checks now) and remove `climbFirst`.
- Shim 2: `BlockDrop.shown` in `HANDLERS.Reveal` (the `tiers` field). Drop `tiers` once the
  screen reads `path`.
- Today's `MysteryReveal` opens Mystery blocks only, from `LuckyHotbar`'s tap; the tap should
  open it for any block with `LuckyBlocks.unclimbed`.

**A small mark** tells an unclimbed block from a climbed one of the same tier, in the hotbar,
the bag and the trade window (both look like the same block today).

**One thing to confirm with the designer.** Earlier on 2026-10-09 the designer removed the pity
counters and the description line from the Mystery upgrade screen ("get rid of the description
up top"; DECISIONS.md). The v5 plan's answer 14 asks for pity **bars** with a head start
(1.4). Build the bars as the plan says, and show the concept art before placing them on the climb
screen.

### 1.2 A Secret result

**Sees.** A climb that reaches the Secret plays the full show at once: there is no Secret block
(no model, no timer, nothing lands in the slot).

**Reads.** The Reveal answer's `secret = true`, `cue`, `rarity` ("Secret"), `new`, `found`,
`count`; the block is already gone from `BlockState`.

**Replaces shims.** Shim 3: `LuckyClient` plays the Secret cue's reel after the Mystery screen's
last press (and after Hold, shim 1's path). The real screen goes straight from the 7th tier to
the Secret's pull cutscene.

### 1.3 The quick reveal and "Open all"

**Sees.** A Common or Uncommon result opens with a quick 1-2 second reveal instead of the full
reel; Rare and up keep the full show. An **"Open all"** button opens every ready climbed Standard
and Uncommon block at once and shows a short summary of what came out.

**Reads.** `Config.LuckyBlocks.QuickReveal` ({ "Common", "Uncommon" }),
`Config.LuckyBlocks.QuickRevealSeconds` (1.5), `LuckyBlocks.quickReveal(rarity)`;
`Config.LuckyBlocks.OpenAll` (`Tiers` = Standard and Uncommon, `Max` 50, `MinGapSeconds` 3).
Show the button only when at least one such block is ready (climbed, kind in `OpenAll.Tiers`,
`readyAt` passed); `LuckyBlocks.openAllIds(state, now, userId)` is the server's rule.
Strings ready: `Strings.LuckyBlocks.OpenAll`, `OpenAllSummary`, `OpenAllOne`;
`Strings.LuckyBlocks.Reasons.NoneReady`.

**Calls.** `BlockRequest("OpenAll")` (no id). Answer `{ ok, opened = { { id, cue, rarity, kind,
new, found, count } } }`, or a refusal: "NoneReady", "TooFast" (under 3 s since the last one).
The server skips the block in the hands and thrown ones; each opened block counts like a normal
open (copies, finder's money, the Unbox message for a Legendary or better, which these blocks
can't give).

**Replaces.** Nothing (new). Opening blocks one at a time stays as it is.

### 1.4 Pity bars

**Sees.** Two bars on the Mystery block's climb screen and in its odds list: "Rare guaranteed in
N blocks" out of 10 and "Epic guaranteed in N blocks" out of 40. A new player's bars start at
2/10 and 10/40 (the head start). When pity is due the odds list shows the guaranteed tier.

**Reads.** `ShopState.pity` (Mystery blocks left until each guarantee; `ShopView`), the Reveal
answer's `pity = { rare, epic }` (as before this block), `Config.BlockOdds.Drop.PityRare` (10),
`PityEpic` (40), `PityStart` ({ SinceRare = 2, SinceEpic = 10 }), `BlockDrop.pityLeft`,
`BlockDrop.floorOf` (the guaranteed tier, or nil).

**Calls.** None.

**Replaces.** `ShopMystery`'s pity line ("MysteryPity") is text today; the bars replace it.

### 1.5 The Grand Opening Luck clover

**Sees.** A clover icon next to the money and VIP bars, bottom left, **only while the luck
runs**. A tap opens a small popup: "Extra luck for the release!", the countdown, and the two
boosted steps: Rare to Epic 18% to 27%, Epic to Legendary 10% to 15%.

**Reads.** `BlockDrop.luckWindow()` (start and end, unix seconds; (0, 0) while the Grand
Opening's `StartsAt` is 0), `BlockDrop.luckLive(workspace:GetServerTimeNow())`,
`BlockDrop.stepParts(tier, luck)` for the two percentages, `Config.BlockOdds.Climb.Luck`
(`With` = "GrandOpening", `Seconds`, `Steps`). Strings: new ones needed (the popup's title, its
countdown line and the two steps).

**Calls.** None (the luck is the same for everyone; the server reads the same clock).

**Replaces.** Nothing. Test it by setting `Config.Shop.Deals.GrandOpening.StartsAt` to a recent
time in a Studio test (never on the live place).

### 1.6 Odds & Details for every block

**Sees.** Each block's odds list from the new data, **live**: the boosted odds while the luck
runs, the guaranteed tier when pity is due. An unclimbed block's list is its climb's odds (each
rarity and each cue with its % and "1 in N"); a climbed block's list is the cues of its one
rarity. The Week One Cue is in no block's list.

**Reads.** `BlockDrop.chances(floor, { start, luck })` (each final tier),
`BlockDrop.rarityOdds`, `BlockDrop.cueGroups`, `BlockDrop.cueChances(floor, { start, luck })`,
`BlockDrop.rarityPercent`, `BlockDrop.cuePercent`, `BlockDrop.oneIn`; for a climbed block or a
block that never climbs (Grand Opening, Starter) `BlockOdds.list`, `BlockOdds.cueOdds`,
`BlockOdds.cueGroups` with the kind's `Odds` row; `Format.oneIn`.

**Calls.** None.

**Replaces shims.** Shim 4: `OddsDetails` and `ShopMysteryOdds` already show the climb's odds
with the live luck, inside today's layout. The new screen keeps that data and gets its own look.

### 1.7 The "1 in N" in the messages

**Sees.** A Legendary-or-better unboxing message ends with "(1 in 2,610)": the chance of that
exact cue from the block it started as.

**Reads.** The `Banner` remote's Unbox payload: `{ kind = "Unbox", userId, name, cue, rarity,
oneIn?, from? }` (`Net.luau`); `Strings.Banner.OneIn` ("%s (1 in %s)");
`Format.oneIn`.

**Calls.** None: the server sends the number.

**Replaces.** Nothing to remove: `Banner` already appends it. Restyle with the banner if wanted.

### 1.8 The restock

**Sees.** Three cards: **slot 1 marked "Epic or better"**, slot 2, and VIP's slot (crowned), each
with its block, price and stock; the new money prices ($49,900 / $249,000 / $1,290,000 /
$4,990,000); each slot's odds.

**Reads.** `ShopState`'s restock items (`Restock.view`; ids "Slot1", "Slot2", "Vip"),
`Config.Shop.Restock` (`Slots` 2, `SlotOdds` (slot 1's table), `Odds` (slot 2), `VipOdds`,
`Kinds[kind].Price` and `.Stock`), `Restock.oddsOf(i)` (slot i's table), `Restock.chanceOf(kind,
vip?)` (a kind's chance in a restock), `Strings.Menus.Shop.Blocks.FirstSlotOdds`.

**Calls.** `ItemRequest("BuyRestock", itemId)` for money; the restock products for Robux
(prompted by the server as today).

**Replaces shims.** Shim 8: `ShopRestock`'s single odds line "Slot 1: Epic or better · Slot 2:
...", and its panel that now draws three cards where it drew four (`Config.UI` restock
layout).

### 1.9 The shop's Mystery band

**Sees.** $14,900 for one, **5 for $66,900**; with Robux the single block and the **5-pack**
(6 during the launch bonus). Until the designer approves the Robux prices, the 5-pack's button
says "Coming soon".

**Reads.** `Config.Shop.Mystery` (`Price`, `BulkCount` 5, `BulkPrice`),
`Config.Shop.Deals.Mystery` (`Money = { [1] = 14900, [5] = 66900 }`, `Products = { [1] =
"Mystery1", [5] = "Mystery5" }`), `Config.Shop.LaunchBonus.MysteryBulkCount` (6),
`Config.Products.Mystery5` (`Id` 0 until made), the live price from `ShopState`,
`Strings.Menus.Shop.ComingSoon`.

**Calls.** `ItemRequest("BuyBlocks", "Mystery", 1 | 5)` for money; `StoreRequest` for Robux.

**Replaces shims.** Shim 9: `ShopMystery` shows "Coming soon" for a product with Id 0. Keep the
rule; the band's real layout is yours. `Config.UI` already renamed its stage ids to
`MysteryRobux5` / `MysteryMoney5`.

### 1.10 The win track bar

**Sees.** The day's 10 steps: **Uncommon, $1,000, $1,000, Mystery, $1,000, $1,000, Mystery,
$1,000, $1,000, Epic** (money tiles between the block tiles), the count of the day's wins, and
win 10's Epic block as the goal. The result screen shows the money step on its own line
("Win track +$1,000").

**Reads.** `RewardState`'s `wins = { given, kinds }` (`RewardView`; a money step's kind is
"Money"), `Config.BlockOdds.Drop.WinTrack`, `WinTrackMoney` (1,000), `BlockDrop.trackKind(i)`,
`BlockDrop.trackMoney()`; `MatchSummary.money.track` (that win's money step alone) and
`MatchSummary.block` (`{ kind, readyAt }` for a block step).

**Calls.** None.

**Replaces shims.** Shim 5: `Ranking` adds the money step to `MatchSummary.money.bonus` (the
win bonus's line). Once `ResultScreen` draws `money.track` on its own line, take it out of
`bonus` (`src/server/Ranking.luau`, the `bonus = paid.bonus + (paid.trackMoney or 0)` line).
`WinTrack.luau` (client) draws a "Money" step as a blank tile today.

### 1.11 Free Reward

**Sees.**
- **The first week**: $5,000 + Mystery, **Rare**, $10,000, 2 Mystery, $15,000, 2 Mystery, **the
  Week One Cue** + 2 spins. **Day 7's card shows the Week One Cue from day 1** (its picture,
  name and "Legendary"), as the goal to come back for.
- **Later weeks**: $5,000, Mystery, $10,000, Mystery, $15,000, Mystery, **Rare** + 2 spins.
- **The 28-day track**: day 8 $50,000, **day 14 a Rare block**, day 21 $150,000, **day 28 an
  Epic block**.
- **Five playtime tiles**: 5 min $1,000, 15 min a Mystery, 30 min $2,500, 45 min $3,500, 60 min
  $5,000 + 1 spin.
- **VIP's line**: "an Uncommon block a day" (the perk texts already say Uncommon; check the
  width of the longer words).
- The group's card: 2 Mystery blocks; the invite card: an Uncommon block each; ROOFTOP's: an
  Uncommon block.

**Reads.** `RewardState` (`RewardView.build`): each reward is `{ money, blocks, spins, cues }`
(`cues` new: a list of cue ids, the Week One Cue on day 7; `RewardView.reward`),
`Config.Daily.FirstWeek`, `Streak`, `Track`, `Playtime`, `VipBlocks`, `Config.Social`,
`Daily.rewardCues()` (every cue a login row gives), `Catalog.get("WeekOneCue")`,
`Strings.Items.Cues.WeekOneCue`.

**Calls.** `RewardRequest` as today (claims, Claim All).

**Replaces shims.** Shim 7: `RewardsParts` names the Week One Cue in the reward words
(`addCueParts`). The card with the cue's picture replaces it.

### 1.12 Trading and the Index

**Sees.**
- **Trading**: the unclimbed/climbed mark on blocks (1.1); a climbed block named by its tier;
  the Week One Cue tradable like any cue.
- **The Index**: the Week One Cue in the **Legendary row**; where block cues show their odds,
  it shows **"Day 7 of your first week"** instead.

**Reads.** Trade items: `"Block:<kind>"` (unclimbed or never-climbing) and `"Climbed:<tier>"`
(`Trade.blockItem(kind, climbed)`, `Trade.itemBlock(item) -> (kind, climbed)`,
`Trade.offerable`); `Strings.Trade.Climbed` ("Climbed %s"); for the Index,
`InventoryCues.oddsLine` (nil for the Week One Cue today) and the catalog row (`Blocks = {}`).

**Calls.** `TradeRequest` as today (an item string per copy).

**Replaces shims.** Shim 6: `TradeMenu` names climbed blocks "Climbed ..." with the plain block
icon. The mark and a real name replace it. The Index line needs a new string ("Day 7 of your
first week").

### 1.13 Shims, all in one list

| # | Where | What it does today | Removed when |
|---|---|---|---|
| 1 | `src/server/LuckyBlockService.luau` `climbFirst` | Hold or Throw of an unclimbed non-Mystery block climbs it first | 1.1: every unclimbed block goes to the climb screen |
| 2 | `LuckyBlockService` `HANDLERS.Reveal`, `BlockDrop.shown` | `tiers` shows a Secret as Mythic | 1.1: the screen reads `path` |
| 3 | `src/client/LuckyClient.luau` | plays a Secret's reel after the Mystery screen and after Hold | 1.2 |
| 4 | `src/client/OddsDetails.luau`, `ShopMysteryOdds.luau` | climb odds with the live luck in the old layout | 1.6 (keep the data calls) |
| 5 | `src/server/Ranking.luau` | the money step in the win bonus's line | 1.10 |
| 6 | `src/client/TradeMenu.luau` | "Climbed ..." names | 1.12 |
| 7 | `src/client/RewardsParts.luau` | the Week One Cue in reward words | 1.11 |
| 8 | `src/client/ShopRestock.luau` | one odds line for two slot tables | 1.8 |
| 9 | `src/client/ShopMystery.luau` | "Coming soon" for the 5-pack | keep the rule; 1.9 |
| 10 | `src/server/TutorialService.luau` `stayFor` | the tutorial's Uncommon block skips its climb | the tutorial session's call (2) |

---

## 2. The tutorial session (`~/Desktop/8ball-tutorial`, branch `tutorial-v2`)

What changed on `gui-v4` that touches the tutorial (nothing was changed on `tutorial-v2`):

- **The first win's Rare block** now arrives **unclimbed** (OPEN!, no timer) and climbs when
  tapped (or, with today's client, when held: shim 1); its climbed block then waits on its
  tier's timer (Rare 5 minutes, more if it climbed). The RareBlock, BlockWait and BlockReady
  steps assumed a 5-minute countdown from the start. `TutorialService`'s `rareAt` now counts
  a block whose `Kind` or `From` is "Rare".
- **Bronze's block is an Uncommon block** on `gui-v4` (`Config.Tutorial.BronzeBlockKind =
  "Uncommon"`; v5 Standard blocks give Commons only) that **skips its climb**: the server's
  third open hook, `LuckyBlockService.setOpenHooks(forced, opened, stay)`, with
  `TutorialService.stayFor(player, kind)` (true during the "Block" step for that kind). The
  funnel name "OpenedStandardBlock" is kept for the analytics. `tutorial-v2` has no
  `BronzeBlockKind` and calls `setOpenHooks` with two arguments, so whichever branch merges
  second decides how the lesson's block opens under v5 (pass a `stay` hook, or let it climb).
- **The Mystery block** still opens on the climb screen with the server's forced-roll path
  (`forcedOpen`), now climbing on v5's ladder; Bronze's reward Mystery block is unchanged.
- **The tutorial's Rare block line** reads "You won a Rare Lucky Block! Tap it to see."
  (`Strings`, it dropped "opens in 5 minutes"); reword it as you like.
- **Read every number from Config**: the Mystery price ($14,900), the rewards (first-week day
  1 is still $5,000 + a Mystery block), the playtime gifts, the win track's money steps
  (`Drop.WinTrack`, `WinTrackMoney`).
- **The save**: `gui-v4` is at **version 11** (blocks climbed or not, skip credits by product,
  the pity head start); `tutorial-v2` is at 10. If `tutorial-v2` adds a version before merging,
  renumber it after 11.
- **Merge clashes**: mostly `src/shared/Config.luau` (Tutorial, Daily, BlockOdds, LuckyBlocks)
  and `src/shared/Strings.luau`; also `src/server/TutorialService.luau` and
  `src/client/Tutorial.luau` (a comment). Whichever branch merges second resolves them.
- GDD section 14 still describes the 5-minute Rare block countdown; it notes the change.

---

## 3. The thumbnail session

The odds labels for a Mystery block (`docs/ECONOMY.md` 7.2 and 7.3). Use the v5 numbers, or the
launch numbers only with "launch luck" in the art:

| | v5 | During the Grand Opening Luck |
|---|---|---|
| Epic or better | 1 in 32 | 1 in 21 |
| Legendary or better | 1 in 317 | 1 in 141 |
| Mythic or better | 1 in 2,116 | 1 in 941 |
| The Secret | 1 in 84,656 | 1 in 37,625 |

---

## 4. The Week One Cue's art

- **What exists**: the catalog row `WeekOneCue` (`src/shared/Progression/Catalog.luau`):
  Legendary, Group "Block", tradable, sellable, no block rows, `Effect = "Legendary"` (the
  Legendary aura, trail and pocket finisher), and the Classic cue's colours as its `Look`
  (default bands, no skin). Its name is `Strings.Items.Cues.WeekOneCue` ("Week One Cue",
  a working name). `tests/cue_mesh_test.luau` lists it as awaiting art.
- **What is needed**: a new Legendary look (its own skin and mesh through the cue pipeline,
  `docs/prompts/CUE_SKINS_PROMPT.md` and `CUE_MESH_PROMPT.md`, like the other Legendaries), plus
  its card icon for the calendar's day 7 card (1.11). The designer picks the look; it is its own
  task.
- When it lands: add its skin to `src/shared/CueSkins`, take it off the `awaitingArt` list in
  `tests/cue_mesh_test.luau`, and give it a final name in Strings if the designer wants one.
