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

- **Step 4 done: Inventory and Index.** Two tabs, **Items** and **Index** (the Cues and Cases
  tabs are merged into Items). Items opens with a strip of case tiles across the top
  (`InventoryCases`): ready cases with Open (and Open 10 with Quick Cases), cases on their
  timers counting down with a money skip and a Robux skip side by side (no skips for
  restricted players). The cue grid under it has bigger cards, each reading "x% chance · N
  exist" with the % in the rarity colour; Uncommon and up have a light sweeping across them,
  Epic and up also sparkle. Tapping a cue opens a big card over the page: picture, name,
  rarity, odds, "You own N", Equip and **one** "Sell duplicates" that turns into a count
  chooser (- 1 +, Max) with a red "Sell N for $X" (confirm from `ConfirmSellFrom`, as
  before). On a landscape space (phones, short PC windows) the card lays out side by side,
  the picture filling the left like ref 07. The Index shows unfound cues as black silhouettes
  (name, rarity and odds only), shows the still picture at once and swaps in the turning 3D
  cue when it has loaded; cues with a 3D piece keep their still (see Decisions).
  - Checked: lint, Lune tests; Studio PC (1529 x 666): the strip (Standard x3 Open; two Rare
    Cases "Ready in 29:47", $750 / 12 R$ skips), the grid with shimmer and sparkle, Celestial
    Dragon's and Phoenix's big cards, Sell duplicates -> Max (3) -> confirm -> sold
    $750,000 and the card updated to "You own 1"; Index silhouettes, Classic Cue turning in 3D,
    Celestial Dragon's still. Phone (844 x 390 frame): strip, grid and the side-by-side card
    with its chooser fit and read; plus counted to 2 ("Sell 2 for $500,000"). Console clean.
    Gamepad: the card is a selection group, B closes it (bound in code; Studio's emulator
    cannot press B or Escape, so this needs a controller by hand).

- **Step 5 done: opening a case, the reel and rare pulls.** Opening a case now shows it big in
  front ("Click to open!" / "Tap to open!" / A), bobbing; a press shakes it harder and harder,
  it swells and bursts in a white shine, then the reel (or the Quick Cases grid). While it opens
  every other screen hides (the menu under it, the HUD), so only the roll shows; they come back
  with the prize card or the finished grid. The open is sent the moment the overlay opens, so
  the answer is there when the case cracks. The reel's cards are bigger and read the cue's name
  and its odds in its rarity's colour; the strip's pictures are fetched during the intro.
  **Near-misses** (D15): about 1 roll in 5 a rarer cue sits next to the prize
  (`Progression/ReelPlan`, pure, tested): the reel slows onto it, waits a beat, then creeps
  over onto the server's prize (a skip lands on the prize at once). The landing card says
  **YOU PULLED** (shaking), the cue's odds in this case, and **Sell / Keep** (any sellable pull
  can be sold now, not only duplicates; Keep reads "Keep, open next (3)" while cases remain;
  Equip stays). **Rare and up play a cutscene** before the card (`PullCutscene`): Rare blue
  streaks; Epic purple streaks, a black beat, a white burst; Legendary the world drains to
  grey, a gold beam (a thin bright core in a soft shell, the player visible inside) drops onto
  the player, the camera swoops low round them, a gold burst; Mythic the sky turns to deep
  space with pastel aurora, the camera rises into the stars, the cue comes down on a beam of
  light; Secret a red-white glitch, the map's lights go out one by one, silence and a
  heartbeat, a shockwave, the camera shakes and spins, the sky flickers red and white. One
  owner holds the camera, light, sky, atmosphere, the map's lights and the playing sounds
  (DayCycle is held) and puts every one back exactly. Others in the server get a short sky tint
  from Legendary up (through the Unbox banner; never a camera or screen effect). Quick Cases'
  grid has bigger cards; its rarest card, if Rare or better, rattles before it turns and the
  sky flashes its colour. A cutscene can be skipped (tap, A, B, Escape) once its kind was seen
  (this session for now; step 8 saves it in Flags).
  - Checked: lint, Lune tests (new `reelplan_test`: 20,000 rolls tease 18-22%, always rarer,
    always end on the prize); Studio PC: the intro, the crack, the reel with names and odds,
    the card (Heritage Cue, NEW! +$500, 10.714% chance, Equip / Sell $150 / Keep, HUD back);
    Legendary, Mythic and Secret cutscenes on screen; after each one the camera (Custom, FOV
    70), sky, atmosphere density, clock time, brightness, all 58 map lights and the effects
    were exactly as before; the remote tint on its own (camera untouched); the grid's rattle.
    Phone (844 x 390): the intro and the reel fit. Console clean. Not checked: a real second
    player seeing the tint, and a controller's A on the intro (both by hand).

- **Step 6 done: the magic 8-ball Case Drop reveal.** Every Case Drop (a win's drop, read from
  the match summary, so it shows after the result screen; the `CaseDrop` remote for the rest:
  `/freecase`, login drops, Mystery Cases) now plays a giant magic 8-ball (`MagicBall`): "SHAKE
  MAGIC 8 BALL!" shaking, turning rays behind it, a meter, and a see-through finger sweeping to
  show how. A shake is a drag back and forth (touch or mouse), a tap or click, the left stick
  pushed side to side, A, or a real phone shake. At each of the server's climbs the rays jump to
  the next tier's colour with a ding, a burst and a bounce. Full, it flips to the triangle
  window, which ticks slower and slower through the tier names to the real one in its colour.
  Then the case slams in front: an openable case gets **Open now** (straight into the case
  opening) and **Later**; a timed one says "Ready in 29:12" (ticking) and **OK**. Many drops at
  once are one ball marked "x6", one shake, then a row of triangles ticking one by one (rarest
  last), then the cases with their counts, "6 cases!", "They are in your Inventory." and
  **Collect**. It waits its turn in the popup queue (never over a menu, a match or another
  popup). Skip (bottom right; Y on a gamepad) shows once it was seen (this session for now; the
  new `Seen` module is where step 8 plugs the saved Flags in; PullCutscene uses it too). Four
  new icons (ball, ball window, triangle, hand pointer).
  - Checked: lint, Lune tests (952 passed); Studio PC: one drop (drag shakes, the climbs, the
    tick, Rare Case with the ticking timer, OK), six drops (rays, "x6", the triangle row, the
    six cases, Collect), `/freecase` through the real server path ending on Open now, which
    opened the case's intro; Skip on the second ball. Phone (844 x 390): the stage fits; Skip
    moved from beside the title (it covered the "!") to the bottom right. Console clean. Not
    checked: a real match win's drop (the summary path; code read only), a controller's stick
    and A, and a real phone's shake (all by hand).

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
- `Config.luau` (step 4): `Config.UI.Inventory.CardMinPx` {104,128} -> {118,150} and
  `CardAspect` 1.3 -> 1.42 (bigger cards with an odds line); new `Items` block and
  `CardOddsTextPx` after `CardAspect`.
- `Strings.luau` (step 4): `Menus.Tabs.Inventory` gains `Items`; new keys at the end of
  `Menus.Inventory` (CasesHeader ... Close).
- `Config.luau` (step 5): `UI.CaseOpening.HintHeightPx` 24 -> 30 and `HintPx` 18 -> 24; `Reel`
  card size 104 x 124 -> 136 x 176, `ThumbShare` 0.9 -> 0.8, `ThumbCentreShare` 0.46 -> 0.37,
  new name / odds / near-miss keys; `Card.WidthPx` 380 -> 400 and new `PulledPx`; `Grid` card
  112 x 116 -> 136 x 148, `ThumbPx` 64 -> 86, new `LastPauseSeconds`; new `Intro` block;
  `Audio.Ui` gains `Heartbeat` and `Shockwave` (licensed library sounds); `Kit.Motion.Shake`
  gains `Hard`; new `Config.Cutscenes` before the derived values.
- `Strings.luau` (step 5): new keys at the end of `CaseOpening` (OpenTouch ... KeepNext).
- `DayCycle.luau` (client): new `DayCycle.hold()`; `update` returns while held and rewrites
  everything once released.
- New shared module `Progression/ReelPlan.luau` (pure; the reel's near-miss) and its test.
- `Config.luau` (step 6): `Kit.Icons` gains `MagicBall`, `MagicBallWindow`, `MagicTriangle`,
  `HandPointer` (after `Heart`); new `Config.UI.MagicBall` before `Config.Cutscenes`.
- `Strings.luau` (step 6): new `MagicBall` block before `Banner`.
- `Progression.luau` (client): one line starts `MagicBall`.

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
- 2026-10-03 (lane): in the Index, a cue with a 3D piece (Phoenix and Kitsune wings, the
  Celestial Dragon, Kraken) keeps its still picture instead of turning in 3D: a ViewportFrame
  draws no Neon glow or ForceField, so the piece came out faint, while the new still picture
  (step 2) shows it in full. Plain cues still turn in 3D once loaded.
- 2026-10-03 (lane): a win's 8-ball shows after the result screen, through the same popup
  queue as every other popup, never over the result. A plain tap or click on the ball counts as
  a shake too (so a mouse with no drag, or a player who does not get "drag", still gets
  through).
- 2026-10-03 (lane): a case's open is sent as the overlay opens (the "Click to open" moment is
  presentation, the case is already being spent), so closing during it gives the usual "Your
  cue is in your Inventory." line.
- 2026-10-03 (lane): the landing card sells any sellable pull (not only duplicates), as "Sell /
  Keep" asks; Equip stays as a third button.
- 2026-10-03 (lane): sounds from Roblox's licensed library, no uploads: APM "Heart Beat"
  (1839088414) and Pro Sound Effects "Thruster Blast 8" (9120009360) for the Secret pull.
- 2026-10-03 (lane): the Inventory's Cues and Cases tabs become one **Items** tab (cases in a
  strip on top), as the brief asked; the chosen cue's big card lays out side by side on any
  landscape space.
