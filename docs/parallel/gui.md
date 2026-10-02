# Lane: GUI (every screen, the shop included, and the leaderboard)

Folder `~/Desktop/8ball-gui`, branch `lane-gui`, Rojo port 34876, Studio file
`place/lane-gui.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

The designer wants the game's screens reworked to their own pictures (they will paste
references). Read `docs/UI_STYLE.md` first: it is today's style; if the designer changes the
style, write the new rules into UI_STYLE so the Cutscenes lane follows them too.

- **Every screen except the big reveal moments**: the HUDs (rank, money, match bar, ability
  bar), the menu column, the host card and queue screens, inventory, the Index, rewards
  (daily, playtime, codes), the rank roadmap, the ability spin screen's layout, settings.
- **The shop**, new: research what the most popular Roblox games sell and how their shops
  look, then build the designer's version. Every price, product and offer comes from the
  Economy lane's Config (`Config.Shop`, `Config.Products`, `Config.Cases`); show what the
  server sends, never decide a number.
- **A simple leaderboard** (ROADMAP 6.4): for example most wins against people and highest
  rank. Bots and PC matches never put anyone on it. Storage needs an OrderedDataStore: CLAUDE.md
  forbids raw DataStore calls for saves, so ask the designer to allow this one exception, in
  one server module (`src/server/Leaderboards.luau`), written from the server, refreshed about
  once a minute, never read as a save.
- Every screen works on phone, PC and gamepad (CLAUDE.md).

## You own

- Client: `HudParts`, `UIAnim`, `UI`, `Menus`, `MenuColumn`, `MenuFrame`, `MatchHUD`,
  `RankHud`, `MoneyHud`, `Nameplates`, `QueueMenu`, `QueueStatus`, `OpponentPrompt`,
  `TableSign`, `Shop*.luau`, `Inventory*.luau`, `Rewards*.luau` (not `RewardsFlyer`),
  `Roadmap`, `Reminders`, `RewardChips`, `Ult*` screen modules (`UltScreen`, `UltScreenParts`,
  `UltSlots`, `UltBuy`, `UltOdds`, `UltHud`, `UltBar`, `UltPick`, `UltFast`, `UltSpinState`),
  `ZoomHint`, `PadGuide`, new `Leaderboard*.luau`.
- Config: `Config.UI` (except the rows the Cutscenes lane owns), `Config.Leaderboards`;
  `Strings` for these screens; the kit art (`tools/gen_ui_art.py`, `assets/ui`).
- Server: new `Leaderboards.luau`.

Not yours (Cutscenes lane): `CaseOpening*`, `ResultScreen`, `PostMatch`, `NewRankPopup`,
`RewardsFlyer`, `CashFlyer`, `Banner`, `UltSpinAnim`, `UltStage`, `UltCutscene`. The Bots lane
adds "Play against PC" to the host card's logic; you own its look.

## Ask the designer (in the interview)

- Which screens matter most for release (do those first), and for each: reference images,
  layout on phone and PC, colours, what is on it.
- The shop: tabs, the front page, how offers and Limited drops are shown.
- The leaderboard: which boards, where (in the world and/or a menu), how many rows.

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
