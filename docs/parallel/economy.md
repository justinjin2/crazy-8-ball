# Lane: Economy, shop GUI, monetization and Limited drops

Folder `~/Desktop/8ball-economy`, branch `lane-economy`, Rojo port 34873, Studio file
`place/lane-economy.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

Make money, cases and Robux feel right, and give the shop the look the designer wants.

- **Balance** (the designer, 2026-10-02): Epic and above must be truly rare and worth a lot
  (Legendary, Mythic and Secret especially; few in circulation), even though every win gives a
  free case. Today a Legendary Case costs about 7 hours of Classic play and guarantees an Epic;
  the designer suggested a Legendary Case should take about 2 weeks of 5 hours a day, or the
  paid Rare/Epic/Legendary cases go. Also check every other source of Epic+ and money:
  rank rewards (sized for the OLD rank ladder; ranks are now much slower, ECONOMY section 4),
  the Index rows (the Epic row pays $25,000), find money, the login streak's cases, codes,
  sell-back, VIP's 2x money. Decide nothing alone: bring the designer options with numbers
  (`tools/economy_model.py` simulates them; update it with every change).
- **Ability rarities** are part of the review: Time Stop (Epic) measures weaker than Rewind
  (Rare) and about equal to Magnet (Common); Heat Seeker (Uncommon) is weaker than Magnet;
  Chain Lightning (Epic) wins only about 50% against Magnet (ECONOMY 11.8). Spin prices too.
- **Shop GUI**: the designer wants a new shop; research what the most popular Roblox games
  sell and how their shops look, then interview the designer with their reference images.
- **Monetization**: every product id in `Config.Products` is still 0 ("Coming soon"). Early on,
  hand the designer the exact list to create on the Creator Dashboard (name, game pass or
  developer product, Robux price, description), then wire the ids they paste back and check a
  test purchase in Studio.
- **Timed Limited drops** at release (the shelf exists: `ShopLimited`, ECONOMY section 9).
- Paid random items (cases, ability spins): the odds screens and PolicyService restrictions
  must keep working (ECONOMY section 13).

## You own

- Config: `Economy`, `Cases`, `Index`, `Daily`, `Shop`, `Products`, `Ranks.Rewards`,
  `Ults.Earn` and `Ults.Roll` (prices and odds; not the abilities' rules), `UI.Shop` and the UI
  rows of the menus below. `docs/ECONOMY.md`, GDD section 12, `tools/economy_model.py`.
- Shared Progression: `Cases`, `Money`, `Shop`, `ShopView`, `Daily`, `Inventory`, `Counts`,
  `RewardView`, `Catalog` (rarity rows only), and **`SaveSchema` (the only lane that may
  change the save; bump to version 6 at most once)**.
- Server: `Store`, `Items`, `Economy`, `Rewards`, `Counters`, `UltSpins` (prices).
- Client: `Shop*.luau`, `Inventory*.luau`, `Rewards*.luau`, `MoneyHud`, `UltBuy`, `UltOdds`.

Not yours: how a reward is SHOWN when it is won (case reveal, result screen, rank-up): that is
the Cutscenes lane. Trading is not in this release.

## Ask the designer (in the interview)

- Paid cases: keep them (and at what price), or remove them? How rare should a first Epic,
  Legendary, Mythic and Secret be, in hours of play?
- Money per match and per hour: keep, cut or raise? What should Robux buy, and at what prices?
- The new shop: which tabs, what goes on the front page, reference images.
- Limited drops at release: which cues, prices, how long, how many copies.

## Status

(Write here: what is done, what is checked on PC / phone / gamepad, what you changed in shared
files, the product list handed to the designer.)

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
