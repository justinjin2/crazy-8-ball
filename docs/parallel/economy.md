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

2026-10-03: interview done, brief approved (`docs/prompts/ECONOMY_PROMPT.md`). Building step 1.

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
