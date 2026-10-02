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

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
