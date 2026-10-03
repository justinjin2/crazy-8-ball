# Lane: GUI and cutscenes (every screen, every reward moment, the shop and the leaderboard)

Folder `~/Desktop/8ball-gui`, branch `lane-gui`, Rojo port 34876, Studio file
`place/lane-gui.rbxl`. Rules for all lanes: [README.md](README.md).

The Cutscenes lane was folded into this one (designer, 2026-10-03): one lane owns every
screen and every big moment, so one style runs through all of them.

## The job

The designer wants the game's screens and reward moments reworked to their own pictures (they
will paste references). Read `docs/UI_STYLE.md` first: it is today's style; if the designer
changes the style, write the new rules into UI_STYLE.

- **Every screen**: the HUDs (rank, money, match bar, ability bar), the menu column, the host
  card and queue screens, inventory, the Index, rewards (daily, playtime, codes, the 28-day
  track, group and invite cards), the rank roadmap, the ability spin screen's layout,
  settings, the trade screen.
- **The shop**, new: research what the most popular Roblox games sell and how their shops
  look, then build the designer's version. Every price, product and offer comes from the
  Economy lane's Config (`Config.Shop`, `Config.Products`, `Config.Cases`); show what the
  server sends, never decide a number.
- **The cutscenes and reward moments** (the designer has very specific pictures of these):
  - **After a match**: the result (win and loss), the money and XP counting up, the Case Drop.
  - **The Case Drop reveal**: the magic 8-ball (see Economy's requests below).
  - **Opening a case and pulling a cue**: the build-up and the reveal by rarity (Epic,
    Legendary, Mythic, Secret should each feel bigger than the last); Quick Cases' open-all.
  - **Rank-up** (NEW RANK!, a new tier) and **ability spin reveals**, if the designer wants
    them in.
  - The in-match ability cutscene (`UltCutscene`) only if the designer asks for it.
  The basic versions exist; read them first and keep what works (the server already sends
  everything: the match summary, case results, rank results).
- **A simple leaderboard** (ROADMAP 6.4): for example most wins against people and highest
  rank. Bots and PC matches never put anyone on it. Storage needs an OrderedDataStore: CLAUDE.md
  forbids raw DataStore calls for saves, so ask the designer to allow this one exception, in
  one server module (`src/server/Leaderboards.luau`), written from the server, refreshed about
  once a minute, never read as a save.
- Every screen and moment works on phone, PC and gamepad (CLAUDE.md), and every cutscene can be
  skipped after the first time or two.

**Read before the interview**: the Requests sections of [economy.md](economy.md) (the shop's
one-scroll page, odds as percentages, cue cards, the trade screen, the 8-ball reveal) and
[bots.md](bots.md) (bots in the player list, the Fill with PC button), and the "For GUI" and
"For Cutscenes" lines in economy.md's Status: they list every payload field you can show. All
of those requests are now yours.

## You own

- Client screens: `HudParts`, `UIAnim`, `UI`, `Menus`, `MenuColumn`, `MenuFrame`, `MatchHUD`,
  `RankHud`, `MoneyHud`, `Nameplates`, `QueueMenu`, `QueueStatus`, `OpponentPrompt`,
  `TableSign`, `Shop*.luau`, `Inventory*.luau`, `Rewards*.luau`, `Roadmap`, `Reminders`,
  `RewardChips`, `Ult*` screen modules (`UltScreen`, `UltScreenParts`, `UltSlots`, `UltBuy`,
  `UltOdds`, `UltHud`, `UltBar`, `UltPick`, `UltFast`, `UltSpinState`), `ZoomHint`,
  `PadGuide`, new `Leaderboard*.luau`, new trade screen modules.
- Client moments: `CaseOpening*.luau`, `ResultScreen`, `PostMatch`, `NewRankPopup`,
  `RewardsFlyer`, `CashFlyer`, `Banner`, `UltSpinAnim`, `UltStage`, `UltCutscene` (only if
  asked), and any new cutscene modules.
- Config: `Config.UI`, `Config.Leaderboards`, new `Config.Cutscenes`; the sounds for these
  moments in `Config.Audio`/`UISound`; `Strings` for these screens; the kit art
  (`tools/gen_ui_art.py`, `assets/ui`); uploaded images, sounds and meshes (ids in Config).
- Server: new `Leaderboards.luau`.

Not yours: what a reward is or costs and what the server sends (ask the integrator in
Requests if you need a field). The Bots lane added "Play against PC" and "Fill with PC" to the
host card's logic; you own their look.

## Ask the designer (in the interview)

- Which screens and moments matter most for release (do those first), and for each: reference
  images or clips, layout on phone and PC, colours, what is on it.
- For each cutscene: what happens second by second, the camera, colours, text, sounds, how
  long, how it is skipped on phone, PC and gamepad, what other players in the server see.
- The shop: the front page, how offers, the restock shop and Limited drops are shown.
- The leaderboard: which boards, where (in the world and/or a menu), how many rows.

## Status

## Requests to other lanes or the integrator

## Decisions (dated; the integrator copies them to DECISIONS.md)
