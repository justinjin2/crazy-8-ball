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

- **Step 7 done: the left column, corners and rewards without a menu.** The column is now
  **Shop, Inventory, Abilities, Free Reward** (Rewards and Trade left it). Hovering or pressing a
  tile shakes its icon hard and bursts a glow behind it. **Free Reward** (the gift, bobbing in
  front of turning gold rays) shows only while the group or the favorite reward is left; it
  opens the **Free Reward page**: two big cards, "Join the group" (3 Case Drops, +10% match
  money; Join is Roblox's join prompt, then the server checks and gives it; a member sees Claim)
  and "Favorite the game" ($10,000 + 1 Case Drop; Roblox's favorite prompt, then GetFavorite
  when Roblox answers it, then the claim) with "Liking the game helps us too!" and no reward
  tied to a like. Each card goes once claimed; both gone: "All claimed. Thank you!" and the
  tile leaves the column. **Right edge**: the Daily Challenge target, its glow flashing; a
  press says "Daily Challenges are coming soon!" in a bubble. **Bottom left** beside the money:
  **Invite** (Roblox's invite prompt with our launch data) and **Roblox Plus** (hidden for
  members and where the shop does not offer Plus). **Daily login**: the server now claims
  every day by itself on join (and at midnight UTC for players still online); a popup shows
  "DAY 3 LOGIN REWARD!", what was given, the week's seven days (claimed checked, today gold),
  "Day 10 of 28" with its bar and the next track prize, and the streak freeze; Collect flies
  it in. **Playtime gifts** are given by the server as each is reached, each with a "THANKS FOR
  PLAYING!" popup. Every popup waits its turn (one at a time, never in a match, over a menu or
  during the tutorial); a reward's Case Drops play their 8-ball right after its popup. The
  inviter's reward is now given **once ever** (their first invited friend's first win).
  **D-pad** in the hub: up Shop, right Inventory, down Free Reward (the Daily Challenge once
  Free Reward is gone); left is kept for the player list (step 10); X Abilities and Y the
  roadmap stay. Also fixed: the 8-ball's Skip did nothing (its bigger touch area ran an empty
  action).
  - Checked: lint, Lune tests (954 passed: new invite-once and favorite-card tests); Studio
    PC: the day 1 popup on join (day 1 checked, Day 1 of 28, freeze line), Collect flying the
    money and spin, the offer popup after it; the Free Reward page, the group Claim (3 drops,
    card gone, x3 8-ball after the menu closed), the favorite claim through the server (gave
    $10,000 + 1 drop; a second claim refused), both gone: thank-you line and the tile gone;
    /playtime 30: both reached gifts given by themselves, their popups in order, then the
    gift's 8-ball; Skip on a seen 8-ball; hover shake; the Daily Challenge bubble. Phone (844
    x 390): the daily popup and the Free Reward page fit and read. Console clean. Not checked
    (by hand): Roblox's favorite and join prompts (Studio cannot finish them), the invite
    prompt, the D-pad map on a controller, the corners on a real phone, and a real new UTC day.

- **Step 8 done: Settings and music.** A gear beside the rank card (top left, word "Settings")
  opens **Settings**: four big rows, each one press to flip its switch (green ON, grey OFF):
  **Sound effects**, **Music**, **Lower effects**, **Show my country flag** (off until turned
  on). Under them, the **codes box** whenever the Abilities screen is not live, so codes are
  always reachable (the Rewards menu's box, moved). Every switch is saved on the server (the
  save's existing `Settings` map; the new `src/server/Settings.luau`, SettingsState and
  SettingsRequest, rate-limited) and comes back on the next join. Sound effects and Music are
  two **sound groups**: every sound in the game joins "Sfx" by itself; the music is in
  "Music". **Lobby music**: three calm, upbeat tracks from Roblox's licensed APM library (no
  uploads: "Nice Mood Guitar", "Tonight's Guest", "Feeling Lucky"), shuffled with a short gap,
  quieter in a match. **Lower effects** now really lowers the cue auras' and the ability
  aura's particles (CueVfx's emitters follow the setting live; UltAura's rates) besides the UI
  loops; never to zero. **Show my country flag** sets the player's `CountryFlag` attribute
  (their country from Roblox) for the player list (step 10); off clears it. The cutscenes'
  "seen once" (the Skip) is now saved too (Flags "Seen:<kind>"), so a moment seen in an
  earlier session can be skipped.
  - Checked: lint, Lune tests; Studio PC: the music loaded and playing (Tonight's Guest at
    0.25), all 58 world sounds in the Sfx group, the gear beside the rank card, Settings
    open, Music off (its group silent), Lower effects and the flag on (CountryFlag = US), each
    held after the server's answer. Phone (844 x 390): the rows fit. Console clean. Not
    checked: a rejoin keeping the switches (Studio's save store is wiped at each stop: by
    hand in the live game), the codes box (the Abilities screen is live in Studio), the
    music's feel (the designer should listen and approve the three tracks).

- **Step 9 done: the rank and XP bar.** White stripes now slide along the gold XP fill all the
  time. When one win against an equal player would rank up (the same XP rule as the server,
  `Ranks.matchXp`), the badge wiggles, the bar rattles and a shaking gold "ONE MORE WIN!" sits
  under the bar (on a phone, inside the pill's name row, right-aligned, so the column below
  stays clear). It goes as soon as the XP moves out of reach.
  - Checked: lint; Studio PC: /xp 220 (Bronze I, 220 / 300): stripes, the wiggle and ONE MORE
    WIN! under the bar. Console clean. Not checked: the phone placement inside the pill (Studio
    cannot shrink the rank HUD's screen through the MCP: by hand on a phone).

- **Step 10a done: the player list and the global boards.** Roblox's list is off; ours sits
  top right: a header "Players (N)" that opens and closes it (open on a computer, closed on a
  phone at first) and three tabs. **Players**: you first, then by rank: the rank badge, the
  username with the country flag when that player turned it on, wins vs players and money.
  Disguised and tutorial bots are listed like people (their rank and money, a fixed believable
  wins count for their tier, never a flag; pressing one does nothing); PC robots are not
  listed. Pressing a real player opens a small card: Trade (a trade invite), Add friend and
  View profile (Roblox's own prompts). **Top Wins** and **Top Rank**: the global boards (top 50)
  and "Your place: #N" (or "Not on the board yet"). The list hides in a match, under menus and
  popups. The D-pad's left in the hub opens it and selects the first row.
  - New `src/server/Leaderboards.luau`: two OrderedDataStores (wins vs players, rank XP),
    written by the server when a value changes (at most once a minute per player, and on
    leaving), read once a minute and sent to everyone; two lobby signs (top 10) either side of
    the spawn, facing it.
  - Checked: lint, tests (957 pass, 3 new); Studio PC with `/lobbybots on`: 11 people listed,
    you first, bots with badges, wins and money; the header collapses and opens; Top Rank shows
    "#1 Painicane, Bronze III, Your place: #1" after /xp (Studio's fallback board: this
    server's players); the list hides under the 8-ball and the daily popup; the signs read
    "WINS VS PLAYERS" / "HIGHEST RANK" with "Be the first!" and the rank row. Console clean.
    Not checked: the popout's buttons (need a second real player: by hand), the D-pad's left
    (Studio cannot send it), the phone's collapsed list (by hand on a phone), the live
    OrderedDataStores (the published game).

- **Step 10b done: the trade screen (D12).** Trade from the player list sends an invite; the
  other player gets a card at the top middle ("Painicane wants to trade!", Accept / Decline,
  gone when it runs out). Accepting opens the screen for both: two big halves (you left, them
  right) with headshots and 8 slots each, a giant READY under each (yours turns into "Undo
  READY"; theirs shows "Waiting..." or "READY!"), a big 3-2-1 over the halves when both are
  ready, a big yellow banner when one side gives far more (or a red line saying why the sides
  cannot swap), and a strip of big cards below with two tabs: **Your items** (tap to add a
  copy; a slot tap takes it back; what they asked for wears a gold ring and "They want this!")
  and **Their items** (tap to ask, again to take the ask back: "Asked!"). Closing it (X, B, a
  match) cancels the trade; a finished trade shows a big TRADE DONE! with confetti and closes.
  - Server (small block in Economy's `Trading`): a "Want" action (an ask never moves anything;
    at most 8; only for an item they can trade) and the Session payload's `myItems`,
    `theirItems`, `theyWant`, `iWant`; pure `Trade.offerable` (tradable cues and ready cases,
    free copies only when paid trading is off) with a test; `PlayerData.tradeOfferable`.
  - Checked: lint, tests (958 pass); Studio PC through a Studio hook that plays TradeState
    payloads (Studio has one player): the invite card, a session (slots, READY states, the
    lopsided banner, the problem banner, both tabs, the gold ring), the 3-2-1, a tap answered
    by the real server ("This trade is over" path), TRADE DONE! and the screen closing; phone
    844 x 390: everything fits. Console clean. Not checked: a real two-player trade (by hand,
    two accounts in a live server or a Studio 2-player test), the controller's moves.

- **Step 11 done: the 1v1 match-result cutscene (C11a, D2).** After a 1v1 (a person, a
  disguised bot or a PC robot; lobby table or arena) the screen fades to black, then beside the
  table the winner stands holding their cue upright with the other arm up, and the loser lies
  face down with their cue dropped beside them; the camera comes down onto them and the result
  screen opens in the top part of the screen, both bodies in view under it. Closing the result
  screen puts everything back. The bodies are local copies (the real ones, their back cues,
  name tags and anyone else walking near are hidden on this screen only); the camera picks the
  table side whose view is clear, and the lobby signs hide meanwhile. Not for 2v2, 3v3, Solo,
  a draw, a surrender or a player who left (the plain screen). Once seen, a tap, click or A
  skips the camera move. A rematch starting ends it.
  - Checked: lint, tests (958 pass); Studio PC with a made-up 1v1 summary against a lobby bot
    (Studio has no second player and no quick real match end): a win and a loss on tables 1
    and 2, the pose on Roblox's newer avatar joints, the result screen lifted, the HUD hidden,
    the skip, everything restored (camera, bodies) after. Console clean. Not checked: a real
    match end (by hand: a 1v1 vs PC win and loss), an arena, the phone (the lifted screen
    scales down into the top 60%), a gamepad's A skip.

- **Step 12 done: keeping players (C15, D3).** Every time Roblox's menu opens or the window
  loses focus, a big "COME BACK TOMORROW FOR" appears in the middle of the screen with
  tomorrow's login reward in a gold ring (turning rays behind it, the reward in words under it);
  it stays while the player is away and goes 2.5 s after they are back. The small reminder toast
  now only carries the free ult spin's line. The first time ever, the server gifts a Rare Case on
  its normal 1 h timer (once per save, `Flags.LeaveGift`); when the player comes back (through
  the popup queue, never in a match) the case falls out of the sky in front of them, the camera
  looks up and follows it down, it crashes with a gold ring, sparkles and a shake, and big words
  say "A GIFT FOR YOU! A free Rare Case, ready in 1 hour! It's in your Inventory." The HUD hides
  meanwhile and the camera comes back as it was.
  - Checked: lint, tests (958 pass); Studio PC through Studio hooks (the MCP cannot open
    Roblox's menu): the message (away), back, the server's gift (the Inventory badge went to 1),
    the gift's scene (look up, fall, crash, words, camera back), a second claim refused
    ("AlreadyClaimed"). Console clean. Not checked: Roblox's real menu and a real focus loss
    (by hand: press Esc, click outside the window), a rejoin (no second gift), the phone.

- **Step 13 done: the rest restyled (C5, D14).** NEW RANK!'s title slams in (big pop, gold
  shockwave) and then keeps a gentle shake; a new tier slams it again; the badge gets a gold glow
  burst. The ability spin shows the tier word under the name in its rarity colour, ticking with
  every name (reference 10's slot window) and slamming on the result; the skip hint sits under it
  and the description comes back once it goes. The roadmap's XP bar has the moving stripes.
  The queue card's Play against PC button twinkles gold while the card is up. YOUR TURN! slams
  in green on your turn. The in-match ability panel's name flares gold and the title jolts as
  the words land. While the queue card is up, the player list and the Daily Challenge step
  aside (they sat on top of it), and the D-pad's Left and Down leave them alone.
  - Checked: lint, tests (958 pass); Studio PC: NEW RANK! through `/xp`, four ability spins
    (Common, Uncommon, Legendary, Mythic tiers ticking; the description back after), the
    roadmap's stripes, the queue card on table 1 (list and target hidden), a match against
    the PC (YOUR TURN!), the ability panel through its Studio preview. Console clean. Not
    checked: the phone (the tier word is 22 px there), a gamepad, a full match to the end.

- **Step 14 done: finish.** The economy model rerun (`python3 tools/economy_model.py`):
  day-30 ownership among players active in the last 7 days is Epic 6.72% (target ~5%, +34%,
  the same as since step 3), Legendary 1.16% (~1%), Mythic 0.17% (cap 0.5%), Secret 0.03%
  (cap 0.05%). The model does not count the favorite reward ($10,000 + 1 Case Drop) or the
  first-leave Rare Case; both are once per player, so they add a little to Epic and up.
  **The whole brief (steps 0-14) is built.** Lint OK, 958 Lune tests pass.
  - What only a person can check (Studio cannot): two real players (a trade from start to
    end, the player list's Trade / Add friend / View profile, the server-wide Secret sky); a
    real phone (touch, the 844 x 390 layouts, a real shake for the 8-ball) and a real
    controller (D-pad Left to the list, every new button, B backing out); a real 1v1 to the
    end (the result cutscene, also in an arena); Esc and clicking outside the window (COME BACK
    TOMORROW) and a rejoin (no second gift, settings kept); Roblox's favorite, group and invite
    prompts; real Robux purchases in the published game; a new UTC day's login popup.

- **Designer feedback 1 (2026-10-03).** The lobby music is gone (the `Music` module, its
  Settings switch, its words and `Config.Audio.Music`; the request for track approval is void).
  Hovering a column tile or a corner icon no longer shakes it hard: it keeps the original small
  sway and soft sun rays fade in behind it (on a layer under the column, so they cover no other
  tile). Every idle icon bob is now a gentle turn (a pixel move looked like a 2 fps sprite);
  the shakes are slower so no frame jumps far; the Daily Challenge's glow pulses smoothly
  instead of blinking; the Free Reward gift no longer bobs (its rays still turn).
  - Checked: lint, tests (958 pass); Studio PC: hover on Shop, Inventory and Free Reward (rays
    behind, the dots and words on top), console clean.

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
- `Config.luau` (step 7): `Daily` gains `AutoClaimEveryDay` and `AutoGivePlaytime`; `Social`
  gains `InviterOnce` and `FavoriteReward`; `UI.Menu.Column.Order` is Shop, Inventory, Ults,
  FreeReward and `PadKeys` lose Rewards and Trade and gain FreeReward (down), plus new
  hover and Free Reward keys; `Kit.Icons.FreeReward`; new `UI.RewardPopups`, `UI.FreeReward`,
  `UI.Corners` before `Config.Cutscenes`; `UI.MagicBall.QueueDelaySeconds`.
- `Strings.luau` (step 7): `Menus.Column` and `Menus.Titles` gain FreeReward (now one key a
  line); new `RewardPopups`, `FreeReward`, `Corners` blocks before `Banner`.
- `Net.luau` (step 7): new `RewardGiven`; the RewardRequest and RewardState comments name
  `ClaimFavorite` and `favorite`.
- Economy-owned (C9, C18), step 7:
  - `server/Rewards.luau`: `claimToday` (every day with AutoClaimEveryDay, also at a new UTC
    day for players here), `giveReachedGifts` after each playtime credit, `tell` (RewardGiven),
    RewardRequest "ClaimFavorite", `claimFavorite` in REWARD_OPS, `build` passes the Flags.
  - `server/PlayerData.luau`: `INVITER_FLAG` / `FAVORITE_FLAG`; `giveInviteRewards` gives at
    most one, once ever (`Social.inviteOnce`); new `PlayerData.claimFavorite`.
  - `Progression/Social.luau`: new `Social.inviteOnce`. `Progression/RewardView.luau`: new
    `FavoriteFlag`, `FavoriteView`, `build`'s optional `flags`, the payload's `favorite`.
  - `server/EconomyLog.luau`: `Favorite` is an Onboarding source.
  - Tests: `social_test` (invite once), `daily_test` (the favorite card).
- `Progression.luau` (client): builds `RewardPopups`, `FreeRewardMenu`, `HubCorners`; the
  corners show with the column; the D-pad's down falls back to the Daily Challenge.
- `MenuColumn.luau` (client): the Free Reward tile, hover jiggle, Rewards dot only if the tile
  exists.
- `Config.luau` (step 8): new `Config.Settings`, `Config.UI.Settings`, `Config.Audio.Music`
  before `Config.Cutscenes`.
- `Strings.luau` (step 8): new `Settings` block; `Corners.Settings`.
- `Net.luau` (step 8): new `SettingsState`, `SettingsRequest`.
- `Bootstrap.server.luau` (step 8): requires and starts `Settings` (two lines).
- `PlayerData.luau` (step 8): new `setSetting` and `markMomentSeen` (the save's existing
  Settings map and Flags; no layout change).
- `CueVfx.luau` and `UltAura.luau` (client, step 8): their particle rates follow
  `Quality.rate()` (Lower effects).
- `Progression.luau` (client, step 8): starts `SettingsState` and `Music`, builds
  `SettingsMenu`, tells Music when a match is on.
- `Config.luau` (step 9): `UI.Progress.RankHud` gains `OneMoreTextPx`, `OneMoreGapPx`,
  `OneMoreShortTextPx`. `Strings.luau`: `Ranks.OneMoreWin`.

- Step 10a: `PlayerData.luau`: `ATTR.WinsVsPlayers` and one `replicate` line (Stats.Wins);
  `Bootstrap.server.luau`: requires and starts `Leaderboards`; `Net.luau`: new `Leaderboards`
  remote; `Config.luau`: `UI.Menu.Column.PadKeys` gains `PlayerList = "DPadLeft"`, new
  `Config.Leaderboards` and `Config.UI.PlayerList` at the end; `Strings.luau`: new
  `PlayerList` block; `Progression.luau` (client): builds `PlayerList`, shows it in `update`,
  the D-pad's left in `padRoute`. New shared module `Progression/PlayerListView.luau` (pure)
  and `tests/playerlist_test.luau`.

- Step 10b: `Config.luau`: `Config.UI.Trade` (the old "Soon" list's sizes) replaced by the
  trade screen's; `Strings.luau`: new top-level `Trade` block after `PlayerList` (the old
  `Menus.Trade` "Soon" words are now unused: safe to delete); `Net.luau`: the TradeRequest and
  TradeState comments name `Want` and the new Session fields; `ItemState.luau`: `REQUESTS`
  allows `TradeRequest`. Economy-owned: `server/Trading.luau` (`Session.wants`, the "Want"
  action, the Session payload's four new fields), `Progression/Trade.luau` (new
  `Trade.offerable`), `server/PlayerData.luau` (new `PlayerData.tradeOfferable`),
  `tests/trade_test.luau` (one test). `TradeMenu.luau` is rewritten (the screen; it no longer
  lists the players: the player list does).

- Step 11: `Config.luau`: new `Config.Cutscenes.Result` at the end of `Config.Cutscenes`;
  `ResultScreen.luau`: `layout` keeps to the top share of the screen when lifted (new
  `ResultScreen.setLifted`); `Progression.luau` (client): the MatchSummary handler plays
  `ResultCutscene` first for a 1v1, `busy` includes it, the nameplates of its two stay hidden,
  and a match starting stops it.

- Step 12: `Config.luau`: `Config.Social.LeaveGift` (after `FavoriteReward`), new
  `Config.UI.ComeBack` (before the ult bar block), new `Config.Cutscenes.LeaveGift`;
  `Strings.luau`: new `ComeBack` block; `Net.luau`: the RewardRequest comment names
  `ClaimLeaveGift`; `Reminders.luau`: the toast shows only the free spin's line. Economy-owned:
  `server/Rewards.luau` ("ClaimLeaveGift", `claimLeaveGift` in the op list), `server/PlayerData.luau`
  (`LEAVE_GIFT_FLAG`, new `PlayerData.claimLeaveGift`), `server/EconomyLog.luau` (LeaveGift is an
  Onboarding source). `Progression.luau` (client): starts `ComeBack`; `busy` includes its scene.

- Step 13: `Config.luau`: `Config.UI.UltCutscene.WordsJoltSeconds` (new, at the top of the
  block), `Config.UI.UltScreen.Spin.TierTextPx`, `TierGapPx`, `TierHoldSeconds` (new, at the
  end of `Spin`); `Main.client.luau`: the `Progression.update` call passes `queueOpen` (the
  queue card is up). Client modules: `NewRankPopup`, `UltSpinAnim`, `UltScreen` (the
  description waits for the tier word; new `tierGone` hook), `Roadmap`, `QueueMenu`,
  `MatchHUD`, `UltCutscene`, `HubCorners` (new `setChallengeHidden`), `Progression` (the
  list and the target hide while the queue card is up).

## Requests to other lanes or the integrator

- **Integrator**: the Cutscenes lane is folded into this one (designer, 2026-10-03): every item
  `cutscenes.md` listed under "You own" (the case opening, the result moments, NEW RANK!, the
  reward flyers, the banner, the spin reveal, `Config.Cutscenes`, the moments' sounds) and its
  interview topics are this lane's.
- **Tutorial lane**: please set a player attribute `TutorialActive = true` (server-side) while a
  player's tutorial runs and clear it when it ends. The GUI holds every join popup (daily login,
  offers, playtime, the come-back message) while it is true.

- **Integrator**: merge `lane-gui`, then save `place/8ball.rbxl` and publish once (this lane
  built nothing in Edit mode: the boards and every scene are made by code; the place save is
  the milestone's).
- **Integrator**: created on Roblox in this lane: six sale products (`Pack4Sale`..`Pack7Sale`,
  `VipSale`, `Mystery10Sale`, ids in `Config.Products.List`), icons on all 34 passes and
  products, and VIP's descriptions now say gold. Sounds used are from Roblox's licensed library
  (no uploads): Heartbeat 1839088414 and Shockwave 9120009360 (the lobby music was dropped).
- **Integrator**: `Strings.Menus.Trade` (the old "Soon" words) is unused now; safe to delete.
- **Designer**: Epic ownership is still 6.72% against ~5% (since step 3); a lower Epic chance
  in Case Drops or the playtime gifts would bring it in. Your call.
- **Designer**: an Uncommon Case picture (a green chest) is missing; the grey Standard chest
  stands in.

- **From the integrator, after merging Tutorial (2026-10-03)** (`release` has both lanes now;
  take it before fixing anything):
  - Done by the integrator: the Rank badge's red "!" while `RankPending` (RankHud), and
    `MagicBall.push` skips drops while `TutorialActive` (the tutorial shows its own).
  - Still to do: the tutorial's case reveals use its stand-in card (`TutorialReveal`). Add
    `MagicBall.play(list, done)` that shows at once without the popup queue, register its
    buttons as `TutorialAnchors.set("OpenNow", ...)` and `("RevealOk", ...)`, and point
    `TutorialReveal.show` at it (tutorial.md, Requests (6)).
  - Seen in Studio during the tutorial's first server: Free Reward, Daily Challenge, the
    Settings gear, Invite and the player list all show (the tutorial hides the old column
    only), and "Skip tutorial" sits on top of the player list's header. Hide the new pieces in
    the first server (`TutorialActive`, or a `TutorialAnchors.hidden` check) and move Skip or
    the list so they never overlap.

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
- 2026-10-03 (lane, step 7): the daily login is claimed by the server on join every day and
  also at midnight UTC for players still online (they get the popup then). The Rewards menu and
  the Trade menu stay built but leave the column: the codes box moves to Settings in step 8 and
  trading starts from the player list in step 10. The D-pad's left waits for the player list.
  A reward's Case Drops play their 8-ball just after the reward's popup (a 0.5 s hold).
- 2026-10-03 (lane, step 7): there is no Uncommon case picture yet, so an Uncommon Case shows
  the grey Standard chest (in the 8-ball's end screen and elsewhere). A green chest icon is
  worth making with the next batch of icons.
- 2026-10-03 (lane, step 8): the switches are saved in the save's existing `Settings` map (it
  was empty) and the seen moments in `Flags`; no layout change. The three lobby tracks are from
  Roblox's licensed APM library (not uploaded); the designer approves or swaps them
  (`Config.Audio.Music.Tracks`).
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
- 2026-10-03 (lane, step 10): the global boards are OrderedDataStores written only by the
  server (the one exception to "saves go through the save layer": a public ranking, never a
  save). "Wins vs players" is the save's `Stats.Wins` (wins against people only). In Studio,
  where DataStores are closed, the boards show the server's own players.
- 2026-10-03 (lane, step 10): the two lobby signs stand either side of the spawn, a little
  toward the tables (X -24 and 24, Z 70), turned to face the spawn (`Config.Leaderboards.Signs`).
- 2026-10-03 (lane, step 10): a disguised bot's wins in the list are a fixed number from its
  seat, inside a range for its tier (`Config.UI.PlayerList.BotWins`), so it never changes while
  you watch.
- 2026-10-03 (lane, step 10): asking for one of the other player's items ("Want") only marks
  it on their screen; nothing moves until they add it themselves and both press READY. Up to 8
  asks. Closing the trade screen calls the trade off; if the screen cannot open (a match or a
  popup is up) the trade is called off too.
- 2026-10-03 (lane, step 11): the result cutscene uses local copies of both bodies posed by
  turning their shoulder joints (both Motor6D and Roblox's newer AnimationConstraint avatar
  joints); nobody else sees it. It skips surrenders and players who left, as the brief says.
- 2026-10-03 (lane, step 12): the first-leave gift is asked by the client the first time the
  menu opens or the window loses focus, and the server gives it once per save (a client asking
  early still gets only the one Rare Case every player gets anyway). The scene plays when the
  player comes back, through the popup queue. The old bottom toast keeps only the free ult
  spin's line, since the big message now carries tomorrow's reward.
- 2026-10-03 (lane, step 13): the ability spin's tier word takes the description's row while
  it spins (the hint moves under it) and the description comes back 1.6 s after landing. The
  player list and the Daily Challenge hide while the queue card is up, since all three share
  the right edge.
- 2026-10-03 (designer): **no lobby music** (dropped after hearing it). Hovering an icon keeps
  the original small sway plus soft sun rays behind it, not a hard shake. No icon moves up and
  down in a loop (it looked choppy); idle icons turn gently instead.
