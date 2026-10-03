# Lane: Economy (money, ranks, odds and rarities, Robux)

Folder `~/Desktop/8ball-economy`, branch `lane-economy`, Rojo port 34873, Studio file
`place/lane-economy.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

Every number in the game's economy, and the server code behind buying things. The screens are
the GUI lane's (the shop included); the reveal moments are the Cutscenes lane's.

- **Money** (the designer, 2026-10-02): how much a match, an hour, the Index, rank rewards,
  daily and playtime gifts, codes and sell-back pay; VIP's 2x money. Today a match pays about
  $97 (about $730 an hour); see ECONOMY sections 0-3.
- **Odds and the rarity distribution.** Epic and above must be truly rare and worth a lot
  (Legendary, Mythic and Secret especially; few in circulation), even though every win gives a
  free case. The cue skins stay as they are for release; what changes is how rare each rarity
  is, which cue sits in which rarity, and the case odds. The designer suggested a Legendary
  Case should take about 2 weeks of 5 hours a day to afford, or the paid Rare/Epic/Legendary
  cases go. Check every source of Epic+: free cases, the login streak's cases, rank rewards,
  the Index rows (the Epic row pays $25,000), find money, codes.
- **Ability spins**: their odds and prices too. The measured ladder has inversions: Time Stop
  (Epic) is weaker than Rewind (Rare) and about equal to Magnet (Common); Heat Seeker
  (Uncommon) is weaker than Magnet; Chain Lightning (Epic) wins only about 50% against Magnet
  (ECONOMY 11.8). Propose rarity moves; the abilities' rules are not yours.
- **Ranks**: the XP rework is done (2026-10-02, ECONOMY section 4: 100 XP a win, 0 a loss, a
  wins-counted ladder, no Rookie/VIP/first-win boosts). The rank REWARDS (money, cases) were
  sized for the old, faster ladder: resize them. Any further XP change is the designer's call.
- **Robux**: what Robux buys and its prices (money packs, VIP, passes, spins, the Starter
  Pack, Limited cues), checked against Roblox's paid-random-item rules (ECONOMY 11.7, 13).
  Early on, hand the designer the exact list to create on the Creator Dashboard (name, game
  pass or developer product, Robux price, description); wire the ids they paste back into
  `Config.Products` and check a test purchase in Studio.
- **Timed Limited drops** at release: the server side (which cues, prices, copies, timers,
  counters); the GUI lane shows them.

Decide nothing alone: bring the designer options with numbers (`tools/economy_model.py`
simulates them; keep it in step with Config).

## You own

- Config: `Economy`, `Cases`, `Index`, `Daily`, `Shop`, `Products`, `Ranks` (rewards, XP),
  `Ults.Earn` and `Ults.Roll` (prices and odds), the rarity of each catalog row.
  `docs/ECONOMY.md`, GDD sections 11-12, `tools/economy_model.py`.
- Shared Progression: `Cases`, `Money`, `Shop`, `ShopView`, `Daily`, `Inventory`, `Counts`,
  `RewardView`, `Ranks`, `Catalog` (rarity fields only), and **`SaveSchema` (the only lane that
  may change the save; bump to version 6 at most once)**.
- Server: `Store`, `Items`, `Economy`, `Rewards`, `Counters`, `Ranking`, `UltSpins` (prices).

Not yours: any screen (GUI lane), the reveal and result moments (Cutscenes lane). When a
number or a payload field changes, write it in your status so GUI and Cutscenes can follow.

## Ask the designer (in the interview)

- In hours of play, how long until a first Epic, Legendary, Mythic and Secret? How many of
  each should exist in the game? Keep the paid cases (at what price) or remove them?
- Money per match and per hour: keep, cut or raise? What should Robux buy, at what prices?
- Limited drops at release: which cues, prices, how long, how many copies.

## Status

2026-10-03: interview done, brief approved (`docs/prompts/ECONOMY_PROMPT.md`).

- **Step 1 done (2026-10-03): save version 6 and money x10.**
  - Save v6 (`SaveSchema.WipeBelow = 6`): any older save starts over as a new player's,
    keeping only its `Shop.Purchases` receipt ids. The old migrations 1-5 are gone. New fields
    for the whole brief: `Inventory.PaidCues/PaidUnique/PaidCases/Timers`, `Daily.PcDrops/
    Disguised`, `Shop.BoostEnds/QuickApplied/Restock`, `Drops` (pity), `Social` (group,
    invites), `Trades` (history 50, applied ids). Each is cleaned by `validate`.
  - Money x10 (`Config.Economy`): ball $100, nice $150/$200, win $500, loss $150, streak $250,
    PC win/loss bonus $250/$80, PC cap $10,000; solo 30% ($30 a ball) to $3,000 then $10;
    short matches $2,000 then $10; difficulty multiplier on. Boosts add (VIP, Party, Starter
    hour 1 each, group 0.1). Solo pays no nice shots. Disguised bots pay the PC rows after 20
    disguised wins a UTC day (`Settle.moneyKind`, hidden). Starter Pack $75,000.
  - `Format.money`: full digits to $999,999, then $1.2M.
  - Analytics: `PlayerData.MoneyChanged` (player, delta, reason, balance) and the new
    `src/server/EconomyLog.luau` (`AnalyticsService:LogEconomyEvent`, batched per reason,
    every 60 s and on leave).
  - Checked: lint, 906 Lune tests; Studio (lane-economy.rbxl): a fresh save reads v6 and $0, a
    real 1v1 win paid $600 ($100 ball + $500 win), solo $30 a ball then $10 past $3,000,
    `LogEconomyEvent` fires, HUD reads $1.23M for $1,234,567.
  - Still old until their steps: case prices and the first-win cue (step 2), money packs
    (step 3), daily/playtime/codes/rank rewards (step 5).
- **Step 2 done (2026-10-03): Case Drops, the six cases, timers, pity, the reveal payload.**
  - `Config.Cases`: six cases (Standard, Uncommon, Rare, Epic, Legendary, Mythic), odds out of
    1,000,000 exactly as the plan, timers 0 / 0 / 1 h / 6 h / 24 h / 48 h, Quick Cases x0.5.
    No case is sold (Price 0, Enabled false; BuyCase answers NotSold). The Event Case is gone.
    `Config.Cases.Drop`: the six weights, pity Rare by the 10th and Epic by the 150th, the first
    win's Rare Case.
  - New pure `Progression/CaseDrop.luau`: roll with pity, climbs, the per-drop rarity % and the
    climb chances (both match the plan; tested), the payload.
  - Every real win drops one (anti-farm rules kept; Play against PC: 10 drops a UTC day).
    The first win's drop is a Rare Case on its normal 1 h timer. Cases land ready (instant) or
    on a timer; timers finish by themselves on the next change; opening a case on its timer
    answers "NotReady". Paid-origin cases and cues are tracked (taken first when opened; sold
    first; a trade will move free copies first). Quick Cases owned halves running timers once.
  - Announcements: Legendary pulls in the server; Mythic and Secret now in every server.
  - Dev: `/freecase` now rolls a Case Drop and sends its reveal; new `/skiptime <minutes>`.
  - Checked: lint, 914 Lune tests (a million drops against the weights, pity at exactly 10 and
    150, 200,000 rolls per case); Studio: a fresh first win gave a Rare Case on a 1 h timer in
    `MatchSummary.caseDrop`, opening it early answered NotReady, after skipping the hour it
    opened, three reward drops came on the `CaseDrop` remote, BuyCase answers NotSold, the
    inventory and the case reel still work (PC).
- **For Cutscenes** (the 8-ball reveal): the payload is `{ source, tier, climbs, readyAt,
  instant, pity = { rare, epic } }` (pity = drops left until guaranteed; 1 = the next).
  A win's comes in `MatchSummary.caseDrop`; everything else (Mystery, rewards, /freecase) on
  the new `CaseDrop` RemoteEvent as a list. The case is already in the save when it arrives.
  Climb chances for any "shake" pacing: `CaseDrop.climbChances()`.
- **For GUI**: `ItemState` gains `timers = { { id, readyAt, paid } }` (cases on their timers,
  soonest first; `cases` lists only ready ones). New reason `NotReady` (Strings.Reasons has
  "Not ready yet"). `MatchSummary.firstWin` is gone (the first win's case waits 1 h);
  `freeCase` is now the drop's tier. Cue-card % per drop: `CaseDrop.rarityOdds()` /
  `rarityPercent(rarity)`. New case names in Strings: Uncommon Case, Mythic Case (no chest
  icons of their own yet: the plain chest shows). The shop's case cards show nothing to buy
  (`Cases.list()` is empty).
- **Step 3 done (2026-10-03): the Creator Dashboard list in Config, ids still 0.**
  - `Config.Products`: exactly the 4 game passes and 24 developer products of the brief (step
    3 table: names, prices, descriptions). Fast Open is now the `QuickCases` pass (299 R$);
    the Starter Pack is 99 R$ and adds 1 hour of 2x money (`Shop.BoostEnds`); money packs are
    $9,000 ... $1,300,000; `Mystery1`/`Mystery10` grant 1/10 paid Case Drops (each revealed on
    the `CaseDrop` remote, source "Mystery"). `Random = true` marks paid random items (Mystery,
    Restock, Skip, spins): refused with "Restricted" where PolicyService restricts them.
    Restock and Skip products answer "ComingSoon" on a plain Buy until step 4 wires them.
    The Founder's Cue product stays (off) until step 7 removes its Limited row.
  - `Config.Shop.Order` (the one-scroll page), `Config.Shop.RobloxPlus`, `Products.BestValue`.
    StoreRequest "RobloxPlus" prompts the Roblox Plus subscription.
  - Limited cues bought with money or Robux are paid origin.
  - Checked: lint, all Lune tests (+3 shop tests: the Dashboard list, Mystery and Starter
    grants, restricted items and the page order); Studio: `/buy`-style grants of Mystery10
    (10 paid drops, the 10th a Rare by pity, all 10 revealed), StarterPack ($75,000, the hour
    of 2x, the `MoneyBoostEnds` attribute), Pack1 (doubled: $18,000); StoreRequest RobloxPlus
    answers ok; the old "FastOpen" key still resolves. Waiting on the designer's ids to test
    real purchases.
- **For GUI** (step 3): `ShopState` gains `order`, `robloxPlus`, `bestValue`, `packs`. Product
  key `FastOpen` is now `QuickCases` (the server still takes "FastOpen"; the player attribute
  keeps the name `FastOpen`). New keys: Mystery1, Mystery10, RestockEpic, RestockLegendary,
  Skip1h/6h/24h/48h. Roblox Plus: `StoreRequest:InvokeServer("RobloxPlus")`.
- **For GUI**: `Format.money` changed (M from $1,000,000). Player attribute `MoneyBoostEnds`
  (unix time the Starter hour ends; 0 none).
- **For Bots**: the disguised limit counts in `Daily.Disguised` (Ranking, on a disguised win).
- **Step 4 done (2026-10-03): Mystery Cases, the restock shop and timer skips.**
  - Mystery Cases for money: $4,900, 10 for $44,100 (`Config.Shop.Mystery`); each is a paid
    Case Drop revealed on `CaseDrop` (source "Mystery"). Robux: Mystery1/Mystery10.
  - New pure `Progression/Restock.luau`: a restock every 10 minutes on the clock, the same in
    every server (an integer hash of the slot number). Uncommon Case $14,900 (3 a player),
    Rare Case $34,900 in 60% (2), the lucky slot Epic Case 4% ($349,000 / RestockEpic, 1) or
    Legendary Case 0.15% ($3,490,000 / RestockLegendary, 1, 25 in every server together) or
    3 Mystery Cases $14,700 (1), and a VIP-only Rare Case $34,900 (1). Cases bought are paid
    origin and land on their normal timers. A restock with a Legendary is announced in every
    server (Banner kind "Restock").
  - The Legendary's 25: an atomic DataStore counter (`Counters.reserveStock/releaseStock`,
    `RestockStock_v1`; a Studio memory copy without DataStores). A Robux prompt reserves a unit
    when it opens, a cancel or a leave gives it back; a money buy reserves and gives it back if
    the buy fails. The shop reads the stock as soon as it shows a restock and with every
    counts refresh (120 s), so other servers' buys show.
  - Skips: money $25 a minute left (min $250, $1,500 an hour); Robux Skip1h/6h/24h/48h on the
    case the player picked (StoreRequest "Skip", remembered from prompt to receipt).
  - Restricted regions: Mystery Cases, restock buys and skips answer "Restricted".
  - Dev: `/restock <item>` shows the next restock holding that item until the real one ends
    (on the real countdown).
  - Checked: lint, 924 Lune tests (100,000 restocks against each chance, per-player stock, the
    shared-stock transforms, skip prices, the new requests); Studio: BuyMystery 10 ok;
    BuyRestock Uncommon 3 times then SoldOut; Vip answers VipOnly for a non-VIP; SkipTimer took
    $1,500 for an hour left; a forced Legendary restock bought for $3,490,000 landed a paid
    Legendary Case on a 24 h timer, a second buy SoldOut, ShopState showed 24 of 25 left and
    the Banner the real end; a restricted player refused; console clean.
- **For GUI** (step 4): `ShopState` gains `restock = { slot, startsAt, endsAt, items = { { id,
  case?, mystery?, price, product?, stock, left, global?, globalLeft?, vip, canBuy, reason? }
  } }`, `mystery = { price, bulkPrice, bulkCount }`, `skip = { moneyPerMinute, minMoney }`,
  `pity = { rare, epic }`. ItemRequest actions `BuyMystery` (count 1 or 10), `BuyRestock`
  (item id), `SkipTimer` (case id, the timer's readyAt) reply `{ ok, price, ... }`; new
  reasons `VipOnly`, `NoTimer` (Strings.Reasons). Robux: `StoreRequest:InvokeServer("Skip",
  caseId, readyAt)` and `StoreRequest("Buy", "RestockEpic"/"RestockLegendary")`. Banner
  `{ kind = "Restock", case = "Legendary", endsAt }`.
- **Step 5 done (2026-10-03): free rewards and rank rewards.**
  - Login loop (`Config.Daily.Streak`): $5,000 / 1 Case Drop / $10,000 / 2 / $15,000 / 3 /
    Rare Case + 2 spins, repeating. Day 1 is claimed by itself on join (3 s after load, so
    VIP is known). One streak freeze a UTC week (Monday start) covers one missed day by
    itself. VIP adds 1 ability spin to each day's claim (`Config.Daily.VipSpins`).
  - 28-day track (`Config.Daily.Track`): every day claimed counts (never resets, repeats):
    day 7 Rare Case, 14 2 Rare, 21 2 Rare, 28 Epic Case, added to that day's claim.
  - Playtime: 10 min $2,000; 30 min 1 Case Drop; 60 min 2 Case Drops + 1 spin; 90 min
    $10,000; 120 min a Rare Case.
  - Codes: WELCOME $5,000 + 1 Case Drop, 8BALL $2,500, ROOFTOP Rare (to 2026-12-31),
    ABILITIES 3 spins; six like codes LIKES1K/5K/10K/25K/50K/100K (the designer's six steps)
    are `Live` and refused as unknown until `/code on <CODE>` (new `src/server/LiveCodes.luau`:
    a DataStore set + MessagingService, every server at once; `/code list`, `/code off`).
  - Group 675425213 (new `src/server/Social.luau`, pure `Progression/Social.luau`): membership
    asked of Roblox on join and on Claim (the `InGroup` attribute: +10% match money); Claim =
    3 Case Drops once (RewardRequest "ClaimGroup").
  - Invites: launch data `invite:<inviter UserId>`; a brand-new save (no match, made under
    10 min ago) records the inviter; its first non-solo win gives it a Rare Case and queues
    the inviter's (DataStore key per inviter, MessagingService to their server, or on their
    next join), at most 5 a UTC month.
  - Rank rewards, Index rows ($10,000 / $25,000 / $75,000 / $250,000), finder's money
    ($500 ... $500,000; Exclusive $5,000, Unique $10,000) and sell-back ($150 ...
    $25,000,000): the plan's tables. Bronze I gives 2 Case Drops (Ranks `drops`,
    `rewardDrops`). Money ability spins $17,500. Magnet is Uncommon, Heat Seeker Common.
  - Checked: lint, 933 Lune tests (new `social_test`; `daily_test` rewritten: loop, freeze,
    track, VIP, playtime, codes, like codes); Studio: day 1 auto-claimed $5,000 on join;
    InGroup true for the designer's account and ClaimGroup gave 3 Case Drops; day 2 (1 Case
    Drop), track day 7 (2 Rare + 2 spins), day 28 (Rare + Epic + 2 spins); all five playtime
    gifts; WELCOME; LIKES1K Unknown, then ok after `/code on likes1k`; 9 Case Drops revealed
    on the client; an invited fresh save's win gave its Rare Case; the inviter's queue gave 5
    Rare Cases and refused the 6th; `/xp 100` from a fresh save paid Bronze I's $2,500,
    2 Case Drops, the Bronze Cue and its spin; console clean.
- **For GUI** (step 5): `RewardState` changed (Net.luau): rewards carry `drops`; `login`
  gains `total`, `frozen`, `freezeReady`; new `trackDays`, `trackPlace`, `track`, `group`,
  `invite`; `days[].bonus` is always false (the old week bonus is the track). The Rewards
  screen needs: Case Drop and spin chips on tiles and gifts (five gifts now), the 28-day track,
  the freeze, a group card (Join = `GroupService:PromptJoinAsync(group.id)`, then
  `RewardRequest("ClaimGroup")`, reason `NotMember` in Strings), an invite card
  (`SocialService:PromptGameInvite` with `ExperienceInviteOptions.LaunchData =
  Progression/Social.launchData(LocalPlayer.UserId)`). Rank rows carry `drops` (MatchSummary,
  RankEvent `rewardDrops`). `Config.Daily.WeeksForBonus`/`WeekBonus` are kept only so the
  current screen runs (WeekBonus now reads "an Epic Case").
- **Step 6 done (2026-10-03): bots' cues.**
  - New pure `Progression/BotCues.luau`: `BotCues.pick(tier, roll)` (roll in [0, 1)) picks
    the rarity from `Config.BotCues` (the plan's Epic+ / Legendary+ / Mythic+ table per tier;
    Common, Uncommon and Rare spread by the Case Drop's odds) and then one case cue of that
    rarity, each equally. Mythic+ is a Mythic: a bot never shows the Secret cue.
  - The disguised daily limit (20 wins, then PC rows, no drop) and the PC drop limit (10 a
    UTC day) are the step 1 rules (`Settle.moneyKind`, `Cases.dropFor`), Lune-tested in
    `settle_test` and `bots_settle_test`.
  - Checked: lint, Lune `botcues_test` (100,000 picks per tier inside 4 sigma of the table;
    never Secret; even within a rarity; the edges); Studio (Roblox Luau): 20,000 picks per tier
    land on the table (Reyes 99.1% / 70.5% / 14.9%). Not checked in Studio: a full Play against
    PC game and a disguised-bot game paying their rows (the QA hooks only fake human
    opponents); try by hand: 11 PC wins in a day, the 11th drops no case.
- **For Bots** (step 6): in `Look.cue`, replace the `Config.Bots.CueCase` roll with
  `BotCues.pick(tier, Rng.uniform(rng))` (keep `TierCueChance` if you want the tier cues).
- **Step 7 done (2026-10-03): the Limited shelf, Grand Opening Cue.**
  - `Config.Shop.Limited` holds one row: `GrandOpeningCue`, $149,000, 14 days, no cap, one
    per player, numbered (`Counters.takeLimited`). `StartsAt = 0` means off: not on the
    shelf, BuyLimited answers "NotStarted" (never "Ended"). Founder's and Beta have no row
    (off until scheduled; their catalog cues stay for saves); the `FoundersCue` product is
    gone from `Config.Products`.
  - New catalog cue `GrandOpeningCue` (Unique, Legendary colour tag, placeholder look:
    black shaft, gold rings, felt-green wrap) and its name in Strings.
  - Dev: `/limited start [minutes]` (default 14 days from now), `/limited end`, `/limited
    off` set every Limited row's window in this server only (`Shop.setWindow`,
    `Items.setLimitedWindow`; ShopState re-sent).
  - `Counters.takeLimited` gained a Studio memory fallback (the lane place has no
    DataStores), like the restock stock.
  - Checked: lint, 938 Lune tests (the row, off, the override, NotStarted; the old Beta and
    Founder's rows kept as test-only rows for the Limited paths); Studio: off answered
    NotStarted; `/limited start` then a buy took $149,000 and gave copy #1 (paid origin, +$10,000
    finder's money), a second buy answered Owned; after `/limited end` a fresh save got Ended;
    ShopState showed the row with `sold = 1`.
- **Step 8 done (2026-10-03): trading, server side.**
  - New pure `Progression/Trade.luau`: items are cue ids or `Case:<caseId>` (one entry a
    copy), at most 8 a side, no empty side, never money; case and Unique cues and the Starter
    Cue trade, Classic and other Exclusive cues never; ready cases only; free copies move
    first and paid ones keep their paid origin; a paid copy moves only where both players'
    PolicyService allows paid item trading; a Unique keeps its number, one per player; no
    finder's money from a trade; history (last 50) and applied ids; the lopsided warning by
    N exist (`Config.Trade`).
  - New `src/server/Trading.luau` with remotes `TradeRequest` / `TradeState` (Net.luau):
    invite anyone in the server, accept or decline, offers, both accept, then a 3-second
    wait that any change restarts; cancel; leaving closes it.
  - The swap: planned on copies of both saves, written to both players' ledger keys
    (`TradeLedger_v1`), then both live saves change together (refused unless they move
    exactly the plan), then both are saved and the ledger entries removed. A load replays a
    ledger trade its save missed, 30 s after loading (`ReplayDelaySeconds`).
  - Checked: lint, 946 Lune tests (new `trade_test`: every refusal, the swap, paid origin,
    Unique numbers, history caps, replay once, the ledger key, the warning); Studio (one
    player): Self / NotHere / NoSession / NoInvite answers, History; a ledger entry for a
    "lost" trade replayed once (Neon Cue out, Rare Case in, history and applied id), the
    ledger emptied, a second check changed nothing; console clean. **Not checked in Studio:
    a real two-player trade** (Studio's 2-player local server cannot be started from the
    MCP). Try by hand: Test > Clients and Servers > 2 players, trade, change an item during
    the 3 seconds, leave mid-trade.
- **For GUI** (step 8): the trade screen on `TradeRequest` / `TradeState` (shapes in
  Net.luau), reasons in `Strings` (NotHere, Self, NoInvite, NoSession, Empty, NotTradable,
  PaidBlocked, Changed). Show `lopsided` as a warning, `problem` as why accept is off, the
  `confirmAt` countdown, and the history from "History".

### Changes to shared files (existing lines)

- `Config.luau`: `Config.Economy` rewritten (x10, boosts, `DisguisedDailyWins`,
  `PcDropsPerDay`, `Analytics`); `Config.Save` + `MaxTimerEntries`, `MaxTradeHistory`,
  `MaxAppliedTrades`, `MaxTradeSideItems`; `Config.Shop.StarterMoney` 75000,
  `StarterBoostSeconds` 3600.
- `PlayerData.luau`: every money change carries a reason (`addMoneyTo`/`takeMoney`,
  `giveReward(data, reward, reason)`), new `MoneyChanged` event, `dailyCount`, `countDaily`,
  attribute `MoneyBoostEnds`, QA calls `dailyCount`/`countDaily`.
- `Ranking.luau` `settleOne`: pays by `Settle.moneyKind`; counts disguised wins; no free case
  from a disguised bot past the limit.
- `Bootstrap.server.luau`: `EconomyLog.start()` after `Rewards.start()`.
- `DevCommands.luau` (~line 320): `Money.boost({ vip = true, party = ... })` (a table now).
- `Items.luau`: `QUIET_OPS` + `countDaily`; (step 2) sends `CaseDrop` from
  `PlayerData.CaseDropped`.
- (step 2) `Config.Cases` rewritten; `Config.Debug` command alias `SkipTime`. `Strings`: case
  names Uncommon and Mythic (Event removed), dev command words for `/freecase` and
  `/skiptime`. `Net`: new `CaseDrop` RemoteEvent; MatchSummary docs (`caseDrop`, no
  `firstWin`); ItemState `timers`. `PlayerData`: `liveData` finishes timers, `addCasesTo`
  lands cases with timers, `rollDrop`, `caseDrop`, `advanceTimers`, `applyQuickCases`,
  `CaseDropped`, reward `drops`, `openCases` NotReady and paid origin. `Ranking`: the free case
  is now the Case Drop (`giveDrop`), `Ranking.freeCase` returns the tier only. `Announce`:
  Legendary here, Mythic/Secret published to every server. `Store`: halves timers when Quick
  Cases is owned. `Catalog`: case cues drop from every case in `Config.Cases.Order`.
- (step 3) `Config.Products` rewritten; `Config.Shop` + `Order`, `RobloxPlus`. `Strings`:
  `PassNames.QuickCases`, the /fastopen help line. `Net`: ShopState and StoreRequest docs.
  `PlayerData`: grant fields `drops`, `boostEnds`; `giveUnique(..., paid)`; `rollDrop(...,
  paid)`. `Store`: QuickCases, old-key alias, `RobloxPlus`. `UltSpins`: the pass key
  `QuickCases`. `DevCommands`: `/fastopen` fakes QuickCases.
- (step 4) `Config.Shop` + `Mystery`, `Skip`, `Restock`; `Config.Items` + `StockStore`,
  `StockStudioStore`; `Config.Debug` alias `Restock`. `Strings`: `/restock` help, reasons
  VipOnly and NoTimer. `Net`: ShopState, StoreRequest ("Skip"), ItemRequest and Banner docs.
  `Progression/Counts` + shared stock; `Shop` + `skipPrice`, `skipProduct`, `mysteryPrice`,
  grant `restock`/`skip`; `ShopView` restock checks and fields; `Requests` + 3 actions.
  `PlayerData`: `buyMystery`, `buyRestock`, `skipTimer`, purchase `restock`/`skip`.
  `Items`: the three handlers, `restockSlot`, `forceRestock`, ItemsQA `forceRestock`.
  `Store`: restock and skip grants, the Legendary reserve, the restock tick and stock resend.
  `Counters`: shared stock. `Announce`: `restock`. `DevCommands`: `/restock`.
- (step 5) `Config.Ranks.Rewards`, `Config.Cases.SellBack`, `Config.Index` (Rows,
  FindMoney), `Config.Daily` (rewritten: Streak, FreezePerWeek, VipSpins, AutoClaimDayOne,
  Track, Playtime, Codes with Live, Live* store names), new `Config.Social`,
  `Config.Ults.Earn` (StreakDay7 and PlaytimeLast gone; MoneyPerSpin 17500),
  `Config.Ults.Catalog` Magnet Uncommon / HeatSeeker Common, `Config.Debug` alias `Code`.
  `SaveSchema` Login = { LastDay, StreakDay, Total, FreezeWeek } (Week dropped). `Ranks`:
  `drops`, `rewardDrops`. `Ranking`: pays and sends rank Case Drops. `PlayerData`:
  `claimDaily(player, vip)`, `redeemCode(player, text, liveOn)`, `recordMatch` invite case,
  `setInvitedBy`, `giveInviteRewards`, `claimGroup`, `InviteWon`. `Rewards`: ClaimGroup,
  day 1 auto-claim, VIP/InGroup resend, RewardsQA invitedBy/inviteWon/liveCode, starts
  LiveCodes and Social. `RewardView`, `Daily` rewritten (above). `DevCommands`: `/code`.
  `Strings`: `/code` lines, reason NotMember. `Net`: RewardState/RewardRequest docs. Tests
  touched outside economy: `ult_roll_test`, `ult_spins_test`, `ult_slots_test` (Magnet's
  rarity, the spin price).
- (step 6) new `Config.BotCues` (no existing lines changed).
- (step 8) new `Config.Trade`; `Inventory.takeCases(save, id, n, freeFirst)` (new optional
  argument); `PlayerData`: `tradePlan`, `applyTrade`, `replayTrade`, `tradeApplied`,
  `tradeHistory`; `Net`: `TradeRequest`, `TradeState`; `Bootstrap`: `Trading.start()`;
  `Strings`: trade reasons.
- (step 7) `Config.Shop.Limited` (only the Grand Opening row), `Config.Products` (FoundersCue
  removed), `Config.Debug` alias `Limited`. `Catalog`: GrandOpeningCue. `Strings`: its name,
  `/limited` lines. `Shop`: `limited()` lists scheduled rows only, `limitedState` treats
  StartsAt 0 as off, `setWindow`, `limitedIds`. `Items.setLimitedWindow`. `Counters.takeLimited`
  Studio fallback. `DevCommands`: `/limited`. Tests: `catalog_test` (3 Unique), `shop_test`
  and `requests_test` (test-only Beta/Founder's rows).

## Requests to other lanes or the integrator

- **GUI**: the shop is ONE scrolling page with no tabs (like Steal An Egg), in the order of
  `Config.Shop.Order`: personal offer (Starter Pack or VIP welcome offer, only while active),
  VIP, restock shop, Limited, Mystery Cases, money packs, Quick Cases and Money Party, Get
  Roblox Plus. One buy button per product. Unopened cases sit at the top of the inventory (no
  Cases tab) with their timers and skip buttons. Odds are shown as percentages everywhere (Case
  Drops, every case, every cue, ability spins), never "1 in X". Cue cards read
  "RARITY · x% · N exist" (x = its rarity's % per Case Drop; "fewer than 10" until 10 copies).
  The trade screen. The group, invite and code cards in Rewards. "Need $X more" opens the
  money packs with the smallest covering pack highlighted, never right after a loss. Payload
  fields are listed in Status as each step lands.
- **Cutscenes**: the Case Drop reveal is a magic 8-ball the player shakes with a finger (mouse,
  gamepad); it flips and the triangle shows the case tier; each shake can climb one step
  (Starr Drop style). The server decides first: the `CaseDrop` payload sends the final tier and
  `climbs`; no fake "almost" moments. Instant cases (Standard, Uncommon) end on Open now / Later;
  timed ones go to the inventory. Same reveal for win drops, Mystery Cases and reward drops.
- **Bots**: (1) a bot's equipped cue: call `BotCues.pick(tier, roll)` (shared Progression,
  step 6) from `Look.cue`, replacing `Config.Bots.CueCase` and `TierCueChance`'s case roll.
  (2) `Config.Bots.Money` x10 (money is x10 everywhere). (3) The disguised limit (20 disguised
  wins a UTC day, then PC rows and no drop) is server-side and hidden: nothing to show.
- **Tutorial**: the first win's Case Drop is a guaranteed Rare Case shown through the 8-ball,
  and it waits its normal 1 h timer (designer, 2026-10-03). The first case the player can open
  comes from the second tutorial win's drop (Standard or Uncommon 93% of the time).
- **Integrator**: (1) Game Settings > Avatar: R15 only (Roblox pays 42% more per Robux on
  purchases by age-checked US adults only in games without R6). (2) Create the 4 game passes
  and 24 developer products with the designer (list in the brief, step 3) and paste the ids
  into `Config.Products`. (3) Set `GrandOpeningCue`'s `StartsAt` (UTC) right before publishing
  the release. (4) Save v6 wipes every save (designer, 2026-10-03).

## Decisions (dated; the integrator copies them to DECISIONS.md)

- 2026-10-03 (designer, interview): save v6 is a full wipe (only friends played); the first
  win's Rare Case keeps its 1 h timer; the Starter hour's 2x adds to VIP's (x3); restock filler
  3 Mystery Cases at $14,700; Legendary pulls announced in the server; group 675425213 with
  Join + Claim (3 Case Drops) and +10% while a member; six like codes switched on live; invites
  with light checks (invite launch data, brand new, any real win, 5 a month); trading open to
  anyone in the server with no gate; 50 trades of history; the hidden disguised limit shows
  nothing; Grand Opening starts on a date the designer sets; no next Limited scheduled; instant
  cases end the reveal on Open now / Later; the Grand Opening Cue gets placeholder colours.
- 2026-10-03 (lane, step 5): "Day 1 claimed on join" read as: today's claim is given by itself
  on join whenever it is loop day 1 (a new player or a streak that started over); other days
  are claimed in the menu. The streak freeze covers exactly one missed day, once a UTC week
  (Monday start). VIP's daily +1 spin is added to each day's login claim. The like codes are
  named LIKES1K ... LIKES100K. "Any real match (bots count)" for invites = any recorded match
  win that is not solo (people, disguised bots, Play against PC).
- 2026-10-03 (lane, step 6): a bot's Mythic+ cue is always a Mythic, never the Secret cue (a
  bot carrying the one Secret would make the rarest cue look common).
