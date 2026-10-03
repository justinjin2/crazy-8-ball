# Economy lane brief (ECONOMY_PROMPT.md)

## Context

The game is close to release. The economy (money, cases, odds, Robux) was sized for an older,
slower game: a match pays about $97, every case is sold for money permanently, and Epic+ is
too common. On 2026-10-02 the designer approved a new economy after a research session and a
60-day player simulation. This lane turns that plan into Config, server code, the save,
`docs/ECONOMY.md`, GDD 11-12 and `tools/economy_model.py`. Screens belong to the GUI lane and
reveal moments to the Cutscenes lane; this lane sends them the data.

**The references** (`~/Desktop/8ball-refs/economy/`, no images in this lane):
- `00-economy-plan.md`: the approved plan with every number (money table, Case Drop weights,
  six case odds rows, timers, restock shop, the 4 game passes and 24 developer products, free
  rewards, rank rewards, Limited cues, ability spins, trading, Roblox rules). **It wins over
  ECONOMY.md, Config and the old briefs; numbers are copied exactly.** Checked: the drop
  weights total 1,000,000, every case row is 100%, and the per-drop rarity and climb chances
  match the plan.
- `economy_sim.py`: the 60-day population simulation behind it. Re-run as-is it gives day 30
  (active last 7 days): Epic 5.85%, Legendary 1.01%, Mythic 0.11%, Secret 0.02%.

**Targets** (designer): at day 30, about 5% of active players own an Epic, 1% a Legendary,
≤0.5% a Mythic, Secret far rarer. If the full model drifts more than about 20% off a target,
the designer is told before anything is trimmed.

## Interview answers (2026-10-03)

| Question | Answer |
|---|---|
| Old saves | **Full wipe in v6**: every save starts new (only friends played). No x10 conversion. |
| First win's Rare Case | Normal **1 h timer** (revealed through the 8-ball, opened later). |
| Starter Pack 2x + VIP 2x | **They add** (x3 for that hour). |
| Restock filler | **3 Mystery Cases for $14,700**, 1 per player per restock: approved. |
| Legendary pulls | **Announced in the server**: approved. |
| Group | Roblox group **675425213** ("Lucky 8"). Rewards card: **Join** (in-game prompt) then **Claim** = 3 Case Drops once; +10% match money on by itself while a member. |
| Like codes | **Six steps**, switched on live by the designer (no republish): 1k $10,000 + 1 Case Drop; 5k $25,000 + 2 Case Drops; 10k Rare Case + 3 ability spins; 25k 2 Rare Cases; 50k $100,000 + 2 Rare Cases; 100k 3 Rare Cases + 5 ability spins. |
| Invites | **Light checks**: joined through your in-game invite, brand new to the game, wins any real match (bots count). Both get a Rare Case; inviter max 5 a month. |
| Trading reach | **Anyone in the server, no gate at all** (no 25-win gate, no friends/nearby rules). |
| Trade history | **Last 50 trades** per player. |
| Hidden disguised limit | **Nothing special** on the result screen: smaller numbers, no case, no message. |
| Grand Opening start | **A date the designer sets** (Config start time, off until filled in right before release). |
| Next Limited | **None scheduled**; a new Limited is one Config row. |
| Drop flow | Instant cases end the 8-ball reveal on **Open now / Later**; timed cases go to the inventory top. |
| Grand Opening art | **Placeholder colours now** (black shaft, gold rings, felt-green wrap); real skin later. |

**Clashes found with the current game** (reported, handled as below):
- The tutorial's first Rare Case now waits 1 h, so the tutorial lane's "opened the first case"
  funnel step comes from the second tutorial win's Case Drop instead (an instant case 93% of
  the time). Written as a Tutorial request.
- With no trade gate, the only alt protection is the free-drop rules (the loser must have 5 real
  matches, at most 3 drops a day from the same account), plus the 5-a-month invite cap.
- The GUI lane's current shop screens read case prices, Buy-10 and sales that go away. I keep
  harmless shims (return "not sold") so the game and lint keep working until GUI rebuilds the
  shop, and list each in my status.
- `Config.Bots.Money` (bots' shown balance, Bots lane) needs x10: a request.
- Founder's Cue and Beta Cue products leave the Dashboard list (switched off until scheduled).
- GDD 12 still says "Trade (later)" and "free Standard Case per win": rewritten with GDD 11-12.

## Build order (the designer's priority order)

After every step: `tools/lint.sh`, `tools/test.sh`, Rojo on port 34873 synced into
`lane-economy.rbxl` (checked with `script_grep`), play-test in that window only, commit and
push `lane-economy`, update the Status section of `docs/parallel/economy.md`. Small choices go
in the lane file's Decisions; anything that changes look, feel or play, or touches another
lane, is asked first.

### Step 1. Save version 6 and money x10

- **One save bump, 5 → 6, holding every new field of this whole brief** (the bump happens
  once, so the layout is designed up front). Migration 5 → 6 = full wipe: a fresh template,
  keeping only `Shop.Purchases` (receipt ids, so a purchase in flight is never paid twice).
  New fields: case stacks with timers and origin, Case Drop pity, cue paid-origin counts,
  Unique paid flags, restock purchases per slot, daily counters (PC drops, disguised wins),
  Starter boost end time, login loop (freeze week, total days), group claimed, invite state
  (invited by, invites this month), live codes redeemed, trade history (50), applied trade ids.
- `SaveSchema.validate` cleans every new field; `tests/save_schema_test` covers the wipe and
  each field.
- **Money x10 everywhere** in `Config.Economy` (ball $100, nice $150/$200, win $500, loss
  $150, streak $250; PC bonuses $250/$80, PC cap $10,000 then half; solo $30 until $3,000 then
  $10; short matches $2,000 then $10).
- **Difficulty money multiplier ON** (Difficult x1.5, Challenger x2).
- **Boosts add**: base x difficulty x (1 + VIP 1 + Money Party 1 + Starter hour 1 + group 0.1),
  match money only.
- **Disguised and PC pay**: Play against PC gets the PC bonus rows, and a Case Drop only for
  the first 10 PC wins a UTC day. A disguised bot pays like a person; after 20 disguised wins
  in a UTC day it pays the PC rows with no drop, hidden. Solo never drops cases.
- `Format.money` shows full digits to $999,999, then $1.2M.
- **Analytics**: a `PlayerData` money hook (amount, reason, balance) feeds a new server
  `EconomyLog.luau` calling `AnalyticsService:LogEconomyEvent` for every source and sink
  (sources: match, rewards, packs, sell-back, find, Index; sinks: Mystery, restock, skips,
  spins, Limited).
- **Checked**: Lune tests (money, settle, bots_settle rewritten to the new numbers); Studio:
  `/resetdata`, a real 1v1 win through `PoolMatchQA` fixture against the synthetic opponent,
  a PC game and a solo rack; read the money totals, the console and the analytics calls;
  the money HUD on PC, phone (emulated) and gamepad shows the new amounts.

### Step 2. Case Drops, cases, timers, pity and the reveal payload

- `Config.Cases`: OddsTotal 1,000,000; six cases (Standard, Uncommon, Rare, Epic, Legendary,
  Mythic) with the plan's odds and timers (instant, instant, 1 h, 6 h, 24 h, 48 h); no prices;
  the four money cases, Buy-10, case sales and the Event case go. `Config.Cases.Drop`: the
  six tier weights (679,043 / 250,000 / 66,667 / 4,000 / 286 / 4), pity (Rare by the 10th,
  Epic by the 150th, never Legendary), the climb chances.
- New pure `Progression/CaseDrop.luau`: roll a tier with pity; the first win's drop forced
  Rare. Pity counts every drop (wins, Mystery, rewards).
- Cases are stored as stacks per tier and origin, ready or timed; timers start when the case
  lands, all run at once, and finish lazily on read. Quick Cases halves timers (also the ones
  already running when bought). Opening a case refuses one that isn't ready.
- Every win drops one (anti-farm rules stay: matches 6-10 vs the same account no drop, max 3
  drops a day from one account, the loser needs 5 real matches).
- **Reveal payload** (new `CaseDrop` remote, server to player, a list):
  `{source, tier, climbs, readyAt, instant, pity = {rare, epic}}`. `climbs` = steps above
  Standard (the server decides the tier first; the 8-ball only shows it). The match summary
  carries the win's drop instead of the old `firstWin` cue. The OpenCase reply is unchanged
  (`results = {cue, rarity, new, duplicate, count, found}`).
- Announcements: Legendary pulls in the server, Mythic and Secret in every server.
- Cue cards' data: rarity, its % per Case Drop (60.9283 / 33.7847 / 5.1241 / 0.1381 / 0.0217
  / 0.0028 / 0.00029) and "N exist" ("fewer than 10" below 10) come from shared `Cases`.
  Every odds list is percentages that sum to exactly 100.
- **Checked**: Lune tests (a million-roll check of the drop and every case within tolerance,
  pity at exactly 10 and 150, timers, Quick Cases); Studio: win → the `CaseDrop` payload read
  through a client attribute; a Rare Case's timer; `/skiptime` to finish it; open; the
  existing inventory and case opening on PC, phone and gamepad still work with the new data.

### Step 3. The Creator Dashboard list (handed over now) and wiring the ids

`Config.Products` is rewritten to exactly these (ids 0 until pasted back). The designer creates
them on the Creator Dashboard; I wire each id and test a purchase in Studio.

**Game passes (4)**

| Key | Name on Roblox | R$ | Description |
|---|---|---|---|
| Vip | VIP | 599 | 2x money from every match, 1 free Ability Spin every day, a VIP slot in the restock shop, the rainbow VIP Cue, a [VIP] chat tag and a rainbow name. |
| QuickCases | Quick Cases | 299 | Case timers run twice as fast. Open all your ready cases at once and skip the reveal. Adds Skip and Auto Spin to Ability Spins. |
| UltSlot2 | Ability Slot 2 | 59 | Unlocks a second ability slot. |
| UltSlot3 | Ability Slot 3 | 99 | Unlocks a third ability slot. |

**Developer products (24)**

| Key | Name on Roblox | R$ | Description |
|---|---|---|---|
| VipOffer | VIP Welcome Offer | 299 | VIP at half price for a short time: 2x money, a free daily Ability Spin, the VIP restock slot, the VIP Cue, tag and rainbow name. |
| StarterPack | Starter Pack | 99 | The Starter Cue, $75,000 and 1 hour of 2x money. Once per player, in your first 7 days. |
| Pack1 | Handful of Cash | 49 | $9,000. Your first money pack pays double, once. |
| Pack2 | Stack of Cash | 99 | $19,500 (+7%). |
| Pack3 | Bundle of Cash | 249 | $52,500 (+15%). |
| Pack4 | Briefcase of Cash | 499 | $110,000 (+20%). |
| Pack5 | Vault of Cash | 999 | $235,000 (+28%). |
| Pack6 | Bank of Cash | 2,499 | $625,000 (+36%). Best value. |
| Pack7 | Fortune | 4,999 | $1,300,000 (+42%). |
| Mystery1 | Mystery Case | 25 | One Mystery Case: the Magic 8-Ball picks a case from Standard to Mythic. Odds are shown in the game. |
| Mystery10 | 10 Mystery Cases | 229 | Ten Mystery Cases, each picked by the Magic 8-Ball. Odds are shown in the game. |
| RestockEpic | Restock Epic Case | 999 | The Epic Case in the restock shop, while it is in stock. Odds are shown in the game. |
| RestockLegendary | Restock Legendary Case | 4,999 | The Legendary Case in the restock shop, while it is in stock (25 worldwide each time it appears). Odds are shown in the game. |
| Skip1h | Finish Case Timer (1 h) | 15 | Opens a case timer with up to 1 hour left right away. |
| Skip6h | Finish Case Timer (6 h) | 49 | Opens a case timer with up to 6 hours left right away. |
| Skip24h | Finish Case Timer (24 h) | 99 | Opens a case timer with up to 24 hours left right away. |
| Skip48h | Finish Case Timer (48 h) | 149 | Opens a case timer with up to 48 hours left right away. |
| MoneyParty | Money Party | 199 | +100% money for everyone in your server for 15 minutes. Your name is announced. |
| Spin1 | 1 Ability Spin | 15 | One Ability Spin. Odds are shown in the game. |
| Spin5 | 5 Ability Spins | 50 | Five Ability Spins. Odds are shown in the game. |
| Spin10 | 10 Ability Spins | 100 | Ten Ability Spins. Odds are shown in the game. |
| Spin50 | 50 Ability Spins | 449 | Fifty Ability Spins. Odds are shown in the game. |
| Lucky1 | 1 Lucky Spin | 49 | One Lucky Spin: no Commons. Odds are shown in the game. |
| Lucky3 | 3 Lucky Spins | 129 | Three Lucky Spins: no Commons. Odds are shown in the game. |

Plus the **Get Roblox Plus** button (`MarketplaceService:PromptRobloxSubscriptionPurchase`, no
product to create). `Config.Shop.Order` holds the one-scroll page order: personal offer, VIP,
restock, Limited, Mystery Cases, money packs, Quick Cases and Money Party, Roblox Plus.
VIP Welcome Offer stays opted out of Managed Pricing so "half price" stays true. A receipt that
no longer qualifies pays money at Pack1's rate, as built.
- **Checked**: Studio test purchases for one pass and one product of each kind once ids exist;
  before that, `/buy <key>` and `StoreQA` grants of every key; the prompt opens from PC, phone
  and gamepad emulation.

### Step 4. Mystery Cases, the restock shop and timer skips

- **Mystery Case**: $4,900, 10 for $44,100; Robux Mystery1/Mystery10; each is one Case Drop
  (same odds, pity and 8-ball payload, source "Mystery").
- **Restock shop**: new pure `Progression/Restock.luau` picks a 10-minute slot's items from the
  slot number with an integer hash (UTC :00, :10…; every server gets the same items, no
  messaging). Slots: Uncommon Case $14,900 (3 per player), Rare Case $34,900 in 60% (2),
  lucky slot Epic Case 4% ($349,000 or 999 R$, 1) / Legendary Case 0.15% ($3,490,000 or 4,999 R$,
  **25 worldwide** per appearance through an atomic DataStore counter, reserved when the prompt
  opens and released on cancel) / otherwise 3 Mystery Cases $14,700 (1); VIP slot: extra Rare
  Case $34,900 (1 per VIP). A Legendary appearance is announced in every server at slot start.
  Mythic Cases never sold.
- **Skips**: money $25 per minute left (= $1,500 an hour), min $250; Robux Skip1h/6h/24h/48h
  applied to the case the player picked (the server remembers the pick before the prompt).
- **Paid origin**: Mystery Cases, restock cases and Limited cues bought with money or Robux are
  paid-origin, and the cues they give inherit it. Skipping a timer does not change origin.
- **Restricted regions** (`ArePaidRandomItemsRestricted`): Mystery Cases, restock cases, skips,
  Quick Cases' timer perk, VIP's daily spin and ability spins are hidden or refused; free
  rewards work.
- New `ShopState` fields: `restock {slot, endsAt, items[]}`, `mystery`, `order`, `pity`,
  `robloxPlus`.
- **Checked**: Lune tests (restock odds over 100,000 slots, stock limits, skip prices, the
  global counter transform); Studio: buy each with money via `ItemsQA`, a restricted player
  refused, `/restock legendary` forcing a slot, two buys past the cap refused.

### Step 5. Free rewards and rank rewards

- **Login loop**: Day 1 $5,000, Day 2 1 Case Drop, Day 3 $10,000, Day 4 2 Case Drops, Day 5
  $15,000, Day 6 3 Case Drops, Day 7 Rare Case + 2 ability spins; Day 1 claimed on join; one
  free streak freeze a UTC week used by itself on a missed day.
- **28-day track** (total days, never resets, repeats): day 7 Rare Case, 14 2 Rare, 21 2 Rare,
  28 Epic Case. Plus the free ability spin a day (VIP +1).
- **Playtime**: 10 min $2,000; 30 min 1 Case Drop; 60 min 2 Case Drops + 1 spin; 90 min
  $10,000; 120 min a Rare Case.
- **Group 675425213**: Join (`GroupService:PromptJoinAsync`) + Claim = 3 Case Drops once; +10%
  while a member (checked on join and on Claim).
- **Codes**: WELCOME $5,000 + 1 Case Drop; 8BALL $2,500; ROOFTOP Rare Case (to 2026-12-31);
  ABILITIES 3 spins; the six like codes written but off until the designer types
  `/code on <CODE>` (DataStore + MessagingService, live in every server).
- **Invites**: `SocialService:PromptGameInvite` carries the inviter's id in launch data; a
  brand-new player who wins any real match gives both a Rare Case; the inviter's 5-a-month cap;
  an offline inviter gets theirs on next join.
- **Rank rewards**: the plan's table (Bronze $1,000 a division / $2,500 + 2 Case Drops … Reyes
  $2,000,000 + Mythic Case); tier cue, tag and spins as built.
- **Index rows** $10,000 / $25,000 / $75,000 / $250,000; **finder's money** Common $500 …
  Secret $500,000, Exclusive $5,000, Unique $10,000, never for traded cues; **sell-back** Common
  $150 … Secret $25,000,000.
- **Ability spins**: $17,500 a money spin; odds and pity unchanged, sent as %; Magnet →
  Uncommon, Heat Seeker → Common; Portals flagged for a re-measure in ECONOMY.
- **Checked**: Lune tests (daily, ranks, codes, invites); Studio: `/setday`, `/newday`,
  `/playtime 120`, claim each, `/code on`, a group claim in Studio (the designer's account),
  a rank-up through `/rank`; the existing Rewards screen on PC, phone and gamepad.

### Step 6. Bots

- New pure `Progression/BotCues.luau`: `pick(tier, roll)` → a cue, rarity by the plan's tier
  table (Epic+ / Legendary+ / Mythic+), the rest spread by the case-cue odds below it. The Bots
  lane calls it from their `Look.cue` (a request).
- The disguised daily limit and PC drop limit from step 1 confirmed end to end.
- **Checked**: a 100,000-pick Lune test per tier against the table; Studio: a Play against PC
  game and `/lobbybots on` games paying the right rows.

### Step 7. Limited cues

- `GrandOpeningCue` catalog row (Unique, placeholder look: black shaft, gold rings, felt-green
  wrap), $149,000, 14 days from `StartsAt` (0 = off until the designer sets the release date),
  numbered, one per player, no cap. Founder's and Beta switched off. The system: real
  countdown, global numbering (the existing `Counters.takeLimited`), optional cap, sold out
  across servers, never sold again, tradable forever.
- **Checked**: Lune tests (window, cap, numbering); Studio with a test start time: buy, number
  shown, second buy refused, `/limited end` → refused.

### Step 8. Trading (server; the trade screen is the GUI lane's)

- New pure `Progression/Trade.luau` (offer rules, validation, the swap applied to two saves)
  and server `Trading.luau`; remotes `TradeRequest` (function) and `TradeState` (event).
- Anyone in the server, no gate. Cues and ready cases only; never money; never Exclusive
  (Starter Cue may); up to 8 items a side; no empty side; any change restarts the 3-second
  confirm on both; a lopsided warning by "N exist"; paid-origin items blocked where
  `IsPaidItemTradingAllowed` is false; no finder's money from trades.
- **Atomic**: both live saves are checked again at the swap; a trade ledger entry (DataStore)
  is written first, then both saves; a save that missed a ledger trade applies it on next load,
  so a crash mid-trade never duplicates or loses an item. History: last 50 per player.
- **Checked**: Lune tests (every refusal, the swap, the ledger replay); Studio with two test
  players (Studio's local server, 2 players): a trade, a change resetting the timer, a leave
  mid-trade leaving both inventories as they were.

### Step 9. Docs and the model

- `docs/ECONOMY.md` rewritten from the plan; GDD sections 11-12 updated.
- `tools/economy_model.py` gets the plan's simulation (default command), plus the 120-minute
  Rare Case, group +10%, the difficulty multiplier, invites, codes and the restock Rare and
  Uncommon slots; a Lune exporter writes the Config numbers to JSON so the model reads Config
  instead of copies. Re-run after every number change; drift over about 20% from a target is
  reported to the designer before trimming.

## Requests for other lanes (written into `docs/parallel/economy.md`)

- **GUI**: the one-scroll shop, no tabs, in `Config.Shop.Order`; one buy button per product;
  unopened cases at the top of the inventory with timers and skip buttons; odds as % everywhere;
  cue cards "RARITY · x% · N exist"; the trade screen on `TradeRequest`/`TradeState`; the group,
  invite and code cards in Rewards; "Need $X more" never right after a loss.
- **Cutscenes**: the magic 8-ball reveal on the `CaseDrop` payload (shake to climb, Open now /
  Later for instant cases).
- **Bots**: call `BotCues.pick` for a bot's cue; `Config.Bots.Money` x10; the hidden disguised
  limit is server-side (nothing to show).
- **Tutorial**: the first win's Rare Case goes through the 8-ball and waits 1 h; the first
  opened case is the second tutorial win's drop.
- **Integrator**: Game Settings > Avatar to R15 only; create the 4 passes and 24 products with
  the designer and paste the ids; set `GrandOpening` `StartsAt` at release.

## Verification, overall

Every step: lint, all Lune tests, Studio play-test in `lane-economy.rbxl` only (port 34873),
console clean, screenshots. Phone, PC and gamepad: the economy's server answers are the same
for all three; I check that every purchase prompt, claim, skip, restock buy and trade request
works from each input through the screens that exist now. The new screens' own three-device
check happens when GUI and Cutscenes deliver them.
