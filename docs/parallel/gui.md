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

2026-10-03: interview done, brief approved (`docs/prompts/GUI_PROMPT.md`). Building step by
step (steps 1-14 of the brief).

- **Step 1 done: the style foundation.** `UIAnim` gains one shared loop clock (`loop`) and
  `drift`, `shake`, `glowBurst`, `sparkle`, `stripes`, `rainbow`, `slam`, `bob`; the new
  `Quality` module holds the Lower effects multiplier. Menu sheets and popup cards
  (`HudParts.popupCard`) carry a drifting 8-ball pattern (a CanvasGroup clips it to the round
  corners); every candy button bursts a glow of its colour when pressed; a menu opening glows.
  `MenuFrame.layout` centres a menu on the whole screen on a computer with at least
  `BottomGapPx` (36) to the bottom. VIP's nameplate and [VIP] chat tag are gold. UI_STYLE
  section 13 holds the new rules. A Studio-only test hook `GuiQA` (PlayerScripts BindableFunction)
  opens menus and plays moments for checks.
  - Checked: lint, 947 Lune tests; Studio PC (1529 x 666 viewport): the Inventory panel sits
    60 px from the top and 39 px from the bottom, its pattern moved 9 px a second, the press
    halo shows round the Equip button; console clean. Phone: the phone layout path is
    unchanged (previews of the rebuilt screens come with their steps).

- **Step 2 done: cue pictures everywhere.** Every skin's card picture was rendered again with
  no aura and its 3D piece frozen in place (`CuePreview.py --thumb --noaura`): the Celestial
  Dragon now spirals round its cue, Phoenix shows its wings, Kraken its tentacles. 41 of the 59
  changed (the rest had no aura); uploaded to the group and wired through
  `tools/cue_skins_data.py` (which now finds ids uploaded from any worktree). The power bar's
  cue is the equipped skin's picture, turned tip-up and preloaded (cues with no skin keep the
  colour bands). A still picture costs one ImageLabel, so no live ViewportFrames are used.
  - Checked: lint, 947 Lune tests; Studio PC: Phoenix and Celestial Dragon in the power bar
    match the cue in hand; the Inventory cards show the new pictures. Phone: the power bar's
    place and size are unchanged.

- **Step 3 done: the shop.** Server side: the release sale (`Config.Shop.ReleaseSale`: 30% off
  money packs 4-7, VIP and 10 Mystery Cases for 14 days from the Grand Opening Cue's start; six
  new sale products `Pack4Sale`..`Pack7Sale`, `VipSale`, `Mystery10Sale`, created on Roblox,
  given exactly like their normal products and sold only inside the window); the Legendary
  restock has no shared limit; Roblox Plus members earn +10% match money
  (`Economy.PlusBoost`). `tools/economy_model.py` now models Plus (12% of players): Day 30 Epic
  6.76% -> 6.72%, Legendary 1.17% -> 1.16%, so Plus moves nothing (Epic was already 35% over
  its 5% target before this lane).
  Client: the Shop is one scrolling page (`ShopMenu`, `ShopPage` words it from ShopState,
  `ShopCards` draws hero cards and tiles): big yellow "— VIP —" headers, the Starter Pack
  offer, VIP "x1 > x2 MONEY" (welcome offer or sale price with the real old price crossed
  out), Limited, the restock (countdown, lucky slot shining, money and Robux buys), Mystery
  Cases (x1, x10 for money, x10 for Robux), the money packs (FIRST BUY x2, BEST VALUE, big
  packs crossed out against the same money in Handfuls, sale prices during the sale), Quick
  Cases, Money Party, Roblox Plus (hidden for members). Four jump buttons (Deals, Cases,
  Money, Passes) outside the panel on a computer, inside on a phone; the current one glows;
  red NEW badges on a new restock / offer, and a count on the column's Shop tile. LB / RB jump
  with a gamepad. "Need $X more" opens a need-money popup with the smallest covering pack
  (`ShopNeed`), never within 60 s of a lost match. A thank-you burst after any Robux purchase
  (`ShopThanks`). A rotating limited-offer popup once a session after joining
  (`ShopOfferPopup`) through the new one-at-a-time popup queue (`Popups`: no popup in a match,
  over a menu or while `TutorialActive`). 14 new icons (`assets/ui/icons/README.md`), the
  basket is the Shop icon, and every pass and product now has its icon on Roblox
  (`tools/roblox_products.py --icons`); VIP's product descriptions say gold, not rainbow
  (`--describe`). The old tab modules (`ShopCases`, `ShopLimited`, `ShopMoney`, `ShopVip`) are
  gone.
  - Checked: lint, Lune tests; Studio PC (1529 x 666): every section, each jump button, the
    need-money popup (Handful $18,000 lit), the offer popup and "See offer", the thank-you
    burst, console clean. Phone (the Shop in an 844 x 390 frame): jump buttons inside, cards
    and the restock grid fit and read. Gamepad: LB / RB bound while open, a selected card
    scrolls into view. Not checked: a real Robux purchase (needs the live game).

### Changes to shared files (existing lines)

- `Main.client.luau`: one line before the ready print starts `GuiQA` (Studio-only hook).
- `Config.luau`: `Config.UI.Kit` gains Motion.Drift/Shake/Glow/Sparkle/Stripes/RainbowSeconds/
  Slam/Bob, `Big`, `Numbers`, `Vip`, `SecretGlitch`; new `Config.UI.Quality`;
  `Config.UI.Menu.Frame.BottomGapPx`.
- `Config.luau` (step 3): `Economy.PlusBoost = 0.1` (new line); `Shop.Restock.Legendary` loses
  `GlobalStock = 25`; new `Shop.ReleaseSale`; six new `Products.List` rows (`*Sale`, with
  `SaleOf`, and `Vip = true` on `VipSale`).
- Economy-owned (C14), step 3:
  - `Progression/Shop.luau`: `ProductRow` gains `SaleOf`, `Vip`; `receiptCheck` returns "Owned"
    for a `Vip` row when VIP; the first-pack check reads `row.SaleOf or key`; `grantFor` sets
    `vip` for `row.Vip`; new `Shop.releaseSale(now)` and `Shop.saleOf(key)` at the end.
  - `Progression/ShopView.luau`: `check` closes a `SaleOf` row outside the window; `owned`
    includes `row.Vip`; the payload gains `releaseSale`; `nextChange` wakes at the sale's start
    and end; the LIST type gains `SaleOf`, `Vip`.
  - `Progression/Money.luau`: `Boosts.plus`, added in `boost`.
  - `server/Economy.luau`: the boosts read `plus` from `MembershipType`.
  - `server/Store.luau`: a `Vip` product waits for the VIP pass check like the welcome offer.
  - `Net.luau`: the ShopState comment lists `releaseSale`.
  - `tools/economy_model.py`: the `plus` addition; `tools/economy_config.json` regenerated.
  - Tests: `restock_test` (no shared Legendary limit), `shop_test` (the sale), `money_test`
    (Plus).
- `Config.luau` (step 3, client): `Config.Shop.Order` moves "Limited" up after "Vip" (the Deals
  group sits together); `Kit.Icons.Shop` is the new basket id; new icon keys after `Limited`;
  `Config.UI.Shop`'s old Cases/Limited/Money/Vip blocks replaced by `Page`, `Need`, `Thanks`,
  `OfferPopup`, `ProductIcons`.
- `Strings.luau` (step 3): `Menus.Shop.VipName` says gold; new keys at the end of
  `Menus.Shop` (Sections ... MoneyName).
- `Progression.luau` (client, mine to change but shared by every screen): a loss sets
  `deps.lostAt`; the popup gate (`Popups.setGate`), `ShopThanks.start`, `ShopOfferPopup.start`;
  `MenuColumn` gets `shopNew`.

## Requests to other lanes or the integrator

- **Integrator**: the Cutscenes lane is folded into this one (designer, 2026-10-03): every item
  `cutscenes.md` listed under "You own" (the case opening, the result moments, NEW RANK!, the
  reward flyers, the banner, the spin reveal, `Config.Cutscenes`, the moments' sounds) and its
  interview topics are this lane's.
- **Tutorial lane**: please set a player attribute `TutorialActive = true` (server-side) while a
  player's tutorial runs and clear it when it ends. The GUI holds every join popup (daily login,
  offers, playtime, the come-back message) while it is true.
- **Integrator**: the lobby music tracks (step 8) need the designer's OK; the ids will be in
  `Config.Audio.Music`.

## Decisions (dated; the integrator copies them to DECISIONS.md)

- 2026-10-03 (designer): **the Cutscenes lane is folded into the GUI lane**; everything
  `cutscenes.md` owned and its interview topics are now this lane's.
- 2026-10-03 (designer, interview; brief `docs/prompts/GUI_PROMPT.md`):
  - The 1v1 match-result cutscene (winner standing with the cue, loser lying on the ground)
    plays at lobby tables and in arenas, against people, disguised bots and PC robots; 2v2,
    3v3 and Solo keep the current result screen.
  - The first-leave gift is a Rare Case on its normal 1 h timer. The big "COME BACK TOMORROW"
    message and ring play every time the window loses focus or the Roblox menu opens.
  - The like + favorite reward becomes a **favorite** reward checked through Roblox's own
    favorite prompt ($10,000 + 1 Case Drop); the card asks for a like with no reward tied to
    it (Roblox gives games no way to check a like).
  - Release sale: money packs 4-7, VIP and 10 Mystery Cases 30% off for 14 days from the Grand
    Opening Cue's start, as separate sale products shown only in the window.
  - Roblox Plus members get +10% match money (5% if the economy model objects).
  - The invite reward is given to the inviter once ever; each invited friend still gets theirs.
  - Secret's colour: near-black with a slow red-white glitch shimmer. VIP drops the rainbow:
    gold with a crown mark until the designer picks its new look. The rainbow is for deals.
  - Global boards: Most wins vs players and Highest rank, as lobby signs (top 10) and a tab in
    the player list (top 50 and your place). No nation board.
  - Disguised and tutorial bots appear in the player list with their rank, money and a fixed,
    believable wins count for their tier; never a flag; clicking one does nothing.
  - The settings gear sits next to the rank HUD; the player list is top right.
  - Trade screen: two big halves, 8 slots each, giant READY with a 3-2-1; your items below;
    the other player's tradable items shown, and tapping one asks for it ("They want: X").
  - Shop jump buttons: Deals, Cases, Money, Passes.
  - NEW RANK!, the ability spin reveal, the Quick Cases grid and the in-match ability cutscene
    are restyled too.
  - **Near-misses on the case reel**: about 1 roll in 5 on every case (paid cases too), the
    real odds unchanged. This replaces ECONOMY 11.7's "no fake near-misses" (designer's call
    after being shown the clash).
  - Legendary, Mythic and Secret pulls: the gold beam, the deep-space sky and the red-white
    glitch blackout; the sky effects are local for Rare and Epic and server-wide from
    Legendary.
  - The 8-ball shows each climb while it is shaken; many drops at once are one shake and a row
    of triangles. Lobby music is added (tracks approved by the designer). A cutscene can be
    skipped once it has been seen once.
  - Roblox's rules (checked 2026-10-03): disguised bots in a player list break no written rule;
    country flags are fine opt-in and off by default.
- 2026-10-03 (lane): the code box also shows in Settings whenever the Abilities screen is not
  live, so codes are always reachable. The favorite claim is reported by the client (Roblox
  gives servers no way to check a favorite); it pays once per player.
