# GUI lane brief: the GUI and cutscenes rework (docs/prompts/GUI_PROMPT.md)

## Context

The designer wants every screen and reward moment reworked before release: a livelier, bigger,
always-moving style; a one-page shop that sells well; a better inventory and Index; real
cutscenes for the case drop, case opening, rare pulls, match result and a first-leave gift; a
custom player list with trading and global boards; rewards that pop up instead of living in a
menu; and settings. The Cutscenes lane is folded into this lane (designer, 2026-10-03). The
Economy lane is finished and merged, so the small Economy changes this needs (C14) are made here
as blocks and listed in the lane file.

What the code map found (it shapes the steps):
- The 8-ball Case Drop reveal does not exist on the client: nothing listens to the `CaseDrop`
  remote or `MatchSummary.caseDrop`; the result screen's case reveal still keys on the removed
  `firstWin`, so real wins show only a chip. Case timers (`ItemState.timers`) are never shown.
- No settings, no music, no SoundGroups, no effects-quality switch, no custom player list (no
  `SetCoreGuiEnabled`), no global boards; the trade screen is a "Soon" stub.
- No remote announces a Robux grant, and nothing checks Roblox Plus (`MembershipType`).
- Cue thumbnails are pre-rendered images (`assets/cue/thumbs`, 59) but they show the full aura,
  and the Celestial Dragon and Kitsune pieces barely show. The Index's 3D view waits on texture
  warm-up (`CueAssets.whenReady`, up to 15 s) and never attaches the pieces. The power bar's
  cue is flat colour bands, not the skin.
- Menus (`MenuFrame.layout`) centre under the top bar with a 4 px margin and a 20 px shadow, so
  on short PC windows they reach the bottom edge.
- The faint 8-ball pattern is one tiled ImageLabel per card, static.
- Daily days 2-7 and playtime gifts are claimed by request in the Rewards menu.

## The references (`~/Desktop/8ball-refs/gui/`)

- **01-shop-one-scroll-side-jump-tabs.webp** (Steal an Egg's shop). Copy the format only: one
  long scrolling page, big jump buttons stacked down the right side outside the panel (icon over
  a word: Featured, Speed, Money) that scroll to sections, big centred section headers
  ("-- PASSES --" in yellow with dashes), and a small red crossed-out price sitting above the
  real price on a bundle button. Ignore the stud texture, green header and egg art.
- **02-shop-icon-red-basket.png**: a glossy red shopping basket with a silver metal handle,
  thick dark outline, the word "Shop" in white with a black outline under it. The new Shop icon,
  drawn in our glossy icon style.
- **03-case-reel-current.webp**: today's Standard Case reel: a white strip of cue cards across
  the middle, a gold marker with diamond ends, "Click to skip", plain grey strips under each
  cue, the inventory showing behind. It is flat and quiet; the opening must feel rewarding.
- **04-inventory-current-cues-grid.webp**: today's inventory: three tabs (Cues, Cases, Index),
  small cards with small names, a sort button and a "Sell all duplicates" bar, and a side panel
  that wastes space.
- **05-selected-cue-panel-wasted-space.png**: the selected Beta Cue panel: a small picture,
  name, rarity, "2 exist", "Copy #2", "Can't be sold", Equip, then a big empty space below.
- **06-selected-cue-two-sell-buttons.png**: Celestial Dragon's panel with Equip, a red
  "Sell $15,000" and a yellow "Sell duplicates: $15,000": two buttons doing the same thing.
- **07-index-classic-cue-big-card.png**: the Index detail card: a big rounded picture card
  (Classic Cue diagonal across it, a grey strip at the bottom), name, "Common", "In your
  collection". The selected cue in the inventory should be about this big.
- **08-shop-big-numbers-arrows-rainbow.webp**: a shop offer with a giant white "x1", a white
  triangle arrow and a giant gold "x2", and a row with "UPGRADE" in rainbow letters and a big
  red arrow from a small item to a bigger one. Take the ideas only: huge bright numbers, rainbow
  words, one big before -> after arrow, lots of white space.
- **09-xp-bar-current.png**: our rank card: Bronze I badge, "Bronze I", a plain flat yellow
  fill, "75 / 300 XP". It gets moving stripes and a wiggle.
- **10-tier-reveal-ticker-smash-roads.webp**: a machine whose dark window shows "COMMON" in
  green pixel letters, ticking through tier names. Copy the slow tick-tick reveal of the tier
  name in its rarity colour (for the magic 8-ball's triangle). Ignore the voxel machine.
- **11-match-result-winner-loser.webp**: the match-result idea: on the rooftop at sunset, the
  winner stands beside the pool table holding their cue upright, and the loser lies face down
  on the floor with their cue dropped beside them. The two name cards with "1 - 0" and the
  WINNER crown float above. Ignore the made-up title cards' details and anything saying "Lv.".

## Decisions from the interview (2026-10-03)

- D1 ref 11 exists. D2 the result cutscene plays for every 1v1 (person, disguised bot, PC
  robot) at lobby tables and in arenas; 2v2/3v3 and Solo keep the current screen.
- D3 the first-leave gift is a **Rare Case on its normal 1 h timer** ("ready in 1 hour");
  the big "COME BACK TOMORROW" message and ring play **every time** focus is lost or the
  Roblox menu opens.
- D4 favorite reward: **Favorite only, really checked** (Roblox's own Favorite prompt, then the
  game sees it favorited); it gives **$10,000 + 1 Case Drop**. The card adds "Liking helps
  too!" with no reward tied to the like. If Roblox does not allow the favorite prompt for a
  game, fall back to the rejoin + Verify flow with honest wording.
- D5 release sale: money packs 4-7, VIP and 10 Mystery Cases **30% off for 14 days**, starting
  with the Grand Opening Cue's `StartsAt`; separate sale products at the sale price, shown only
  during the window, so the crossed-out price is always the real normal price.
- D6 Roblox Plus: **+10% match money** if the economy model is fine (else 5%); tell the
  designer if Epic+ ownership moves.
- D7 invites: the inviter's reward **once ever** (their first invited friend's first real win);
  every invited friend still gets their Rare Case.
- D8 Secret: near-black with a slow red-white glitch shimmer. VIP for now: rich gold with a
  crown mark (placeholder; the designer decides VIP's new look later). Rainbow is free for
  deals.
- D9 global boards: **Most wins vs players** and **Highest rank**, as lobby signs (top 10) and
  a tab in the player list's popout (top 50 + your own place). No nation board.
- D10 disguised and tutorial bots in the list: real rank badge and money, a believable fixed
  "wins vs players" for their tier, never a flag. PC robots are not listed; all lobby bots are
  disguised.
- D11 the settings gear sits **next to the rank HUD** (top left); the player list is top right.
- D12 trade: two big halves (you left, them right), headshots, 8 big slots each, giant READY
  under each turning into 3-2-1; your own items as a strip of big cards below; the lopsided
  warning a big yellow banner. Plus **their tradable items, tap to ask**: a "wanted" highlight
  on their screen; nothing moves without them (small server addition).
- D13 jump buttons: **Deals · Cases · Money · Passes**.
- D14 also rework: NEW RANK! / new tier, the ability spin reveal, the Quick Cases grid and the
  in-match ability cutscene.
- D15 near-misses: **every case, about 1 roll in 5**, real odds unchanged (the designer
  overrides ECONOMY 11.7's "no fake near-misses"; noted in Decisions and ECONOMY's owner list).
- D16 Legendary / Mythic / Secret: the suggested three, with my polish (below).
- D17 rules: disguised bots in the list break no written rule (the designer's call, already
  made); flags are allowed when opt-in and off by default; the like reward is replaced by the
  checkable favorite.
- Also: the 8-ball **shows each climb while shaking** (Starr Drop style); **many drops at once =
  one shake, then a row of triangles**; **lobby music** is added from Roblox's free licensed
  library (the designer approves the tracks); a cutscene can be **skipped after it has been
  seen once** (per kind), and always ends on the server's result.

Small calls I make without asking (logged in the lane file's Decisions): first-time order of
join popups (daily login, then the one offer popup); the D-pad map; where the lobby boards
stand; sound choices from the Creator Store (no audio uploads); the code box also appears in
Settings whenever the Abilities screen is not live (`Config.Ults.ScreenLive`), so codes are
always reachable; the favorite claim is client-reported (Roblox gives the server no way to
check a favorite), so at worst a cheater gets one $10,000 + 1 drop once.

## Rules for every step

- Edit only under `src/` (plus docs, tools, assets). Studio window **lane-gui.rbxl** only, Rojo
  port **34876**. Every number in `Config` (new `Config.Cutscenes`, `Config.Leaderboards`,
  blocks in `Config.UI`), every word in `Strings`, sized for 40% longer translations.
- Shared files (`Config`, `Strings`, `Net`, `Main.client`, `Bootstrap`, `PlayerData`,
  `Ranking`): new blocks near the end of the matching part; every changed existing line listed
  in the lane file. Economy-owned server files (`Rewards`, `Social`, `Store`, `Counters`,
  `Items`, `Trading`, Progression `Shop`/`ShopView`/`Restock`/`Social`/`Daily`/`Money`): small
  blocks, each listed under "shared-file changes". No save-layout change: yes/no flags and
  settings go in the existing `Flags` map through a new `PlayerData.setFlag`-style mutation.
- Every reward is given and saved by the server, once (Flags); every price and number comes
  from the server or Config; PolicyService-restricted players never see Mystery Cases, restock
  buys or skips as buyable.
- After each step: `tools/lint.sh`, `tools/test.sh`, Rojo synced, play-test in lane-gui.rbxl
  on **phone** (Studio device emulation, a 844 x 390 landscape phone first), **PC** (1920 x
  1080 and a short 1366 x 600 window) and **gamepad** (every new button reachable, B backs
  out), console clean, screenshots compared with the reference images, commit + push
  `lane-gui`, Status updated in `docs/parallel/gui.md`. Then straight on to the next step.

## The build, in order of importance

### Step 0. Lane setup
- Copy this brief to `docs/prompts/GUI_PROMPT.md`. In `docs/parallel/gui.md`: Decisions (the
  Cutscenes fold-in and everything above, dated), Requests (integrator: the Cutscenes fold-in;
  Tutorial lane: a player attribute `TutorialActive` while the tutorial runs, so no popup shows
  during it; integrator: approve the music tracks with the designer).

### Step 1. The new style foundation (C1)
- `docs/UI_STYLE.md`: new rules: never still (something always moves, sparkles or breathes);
  bigger click/open/close effects; shaking text for big words; the 8-ball pattern drifts
  diagonally up; big menus centred on the whole screen with a clear gap at the bottom; big and
  simple (bigger minimum text, fewer description lines, single big arrows, white space); a
  themed number palette (gold for money and prices, green for gains and "free", sky blue for
  counts and odds, rainbow only for deals and multipliers, rarity colours for rarity); VIP gold
  (placeholder), Secret red-white glitch.
- `UIAnim` additions: `shakeText`, `glowBurst`, `sparkle`, `stripes` (moving fill pattern),
  `wiggle`, `rainbowText` (moving letter gradient), `slam` (big pop with shockwave), `drift`
  (the pattern). One shared clock; loops stop when their screen closes; all scaled down by the
  Low effects setting (Step 8).
- `HudParts`: the pattern becomes a drifting layer (an oversized tiled label moved inside a
  clipped holder; measured on phone: if many cards make it stutter, only menu sheets and
  popups drift). Big-number text helper, the crossed-out price, the before -> after arrow row,
  red "new" badge and number badge, rarity backgrounds.
- `MenuFrame.layout`: centred on the full screen (not under the bar), height capped so the
  panel plus its shadow keeps a gap at the bottom on PC; phones keep full screen.
- Check: open any menu on PC 1920 x 1080 and 1366 x 600 (never touches the bottom), phone
  (fits, readable); pattern drift smooth; gamepad unchanged.

### Step 2. Cue pictures everywhere (C13, C12)
- Re-render every skin's picture **without the aura**, with its add-on frozen in place (Phoenix
  and Kitsune wings, the Celestial Dragon spiralling round the cue), transparent background,
  512 px, the same angle as today. First measure the cheap option: a live ViewportFrame per
  card (inventory grid of ~40 on phone); if it is not smooth, the new still pictures are used
  everywhere. Upload with `tools/roblox_upload.py --group-id 675425213`, ids into the skin
  index.
- The power bar's cue (`PowerCue`) shows the equipped skin's picture instead of colour bands.
- Check: compare each Mythic and Legendary picture with the cue in hand in the lobby; power bar
  on phone and PC with three different equipped cues.

### Step 3. The shop (C4, C14)
- **One scrolling page** in `Config.Shop.Order` (personal offer, VIP, restock, Limited, Mystery
  Cases, money packs, Quick Cases and Money Party, Roblox Plus), big section headers
  ("— DEALS —"), and four big jump buttons down the right side: **Deals** (personal offer, VIP,
  Limited), **Cases** (restock, Mystery), **Money** (cash packs), **Passes** (Quick Cases,
  Money Party, Roblox Plus). The current section's button glows.
- Each section is big and simple: huge numbers, one big arrow before -> after (VIP "x1 -> x2
  MONEY", first money pack "$9,000 -> $18,000 FIRST BUY x2"), rainbow words on deals, a big
  live countdown on the restock and offers, the restock's lucky slot shining.
- **Real crossed-out prices, only where they matter**: big cash packs (the one-at-a-time
  total: the same money bought as Handfuls of Cash), VIP (the welcome offer's 599 -> 299, the
  release sale), 10 Mystery Cases ($49,000 -> $44,100; 250 -> 229 R$), the release sale items.
  No slashes on small items. Robux prices always from Roblox's live price.
- **Release sale** (D5): create sale products (Pack4-7, VIP as a product that grants VIP like
  the welcome offer, Mystery10) at 70% with `tools/roblox_products.py`, managed pricing off;
  `Config.Shop.ReleaseSale` (starts at the Grand Opening's `StartsAt`, 14 days); the server
  grants them like their normal products; the shop swaps them in only inside the window.
- **Icons**: generate with `tools/openai_image.py` (our glossy style, thick ink outline, no
  words) and upload: the basket Shop icon (ref 02), Deals/Cases/Money/Passes, Starter Pack,
  VIP crown, Mystery Case, each cash pack size, Money Party, Quick Cases, Roblox Plus, Free
  Reward gift, group, invite, favorite star, daily-challenge target, settings gear. Set every
  developer product's and pass's icon on Roblox too.
- **Need money**: clicking something unaffordable opens a popup "You need $X more" with the
  smallest covering pack made to look like a great deal; never right after a loss (the
  result screen's outcome is remembered for 60 s).
- **One join popup** for limited offers (Starter Pack after the first case opening, VIP half
  off, the Limited cue, the release sale), auto-rotating in one card, never stacked with other
  popups.
- **Thank-you burst** after every Robux purchase (client `PromptProductPurchaseFinished`,
  `PromptGamePassPurchaseFinished`, the Plus prompt): confetti, the item flying in, a big
  "THANK YOU!".
- Red badges on anything new (a new restock, a new Limited, a new offer), with a number where
  it counts.
- **Economy changes here**: the Legendary restock has no shared limit (anyone who can afford it
  buys it; `GlobalStock` and its reserve/counter paths off, texts updated); Roblox Plus +10%
  match money (`Config.Economy` boost, set from `MembershipType`, kept live with
  `PlayerMembershipChanged`) after rerunning `python3 tools/economy_model.py`; restricted
  players see no Mystery Cases, restock buys or skips as buyable.
- Check: scroll and every jump on phone/PC; buy each kind in Studio (money buys; Robux prompts
  open; Studio test purchases grant); the need-money popup; a restricted player via `/policy`;
  gamepad: jump buttons, scroll, every buy button.

### Step 4. Inventory and Index (C6)
- Two tabs: **Items** (owned cases first, at the top, each with its timer counting and skip
  buttons: money skip and Robux skip; then cues) and **Index**. No side panel wasting space:
  bigger cards, bigger pictures, bigger text.
- The selected cue opens a big card about the Index card's size (ref 07) with Equip and **one
  "Sell duplicates"** that opens a count chooser (starts at 1, minus / plus, **Max**), showing
  the money.
- Every cue card: name, then "x% chance · N exist" with the % in the rarity colour.
- Uncommon and up: rarity-coloured backgrounds with real movement (aura or sparkle), each rarity
  more than the last. **Measured on phone first**; if a grid of moving cards is not smooth,
  they stay still pictures.
- Index: a cue not found is a blacked-out silhouette; tapping it shows name, rarity and odds,
  never the model's detail. The detail shows the new still picture at once; the rotating model
  (with its frozen add-on) replaces it only once loaded, or the still stays if 3D is too slow.
- Check: phone grid scrolling smoothness, selected card size against ref 07, sell 1 / Max,
  timers ticking and skip prices, gamepad grid moves and the count chooser.

### Step 5. Opening a case, the reel and rare pulls (C11c, C11d)
- The case pops up in front: "Click to open"; it shakes, cracks and opens in a bright shine with
  sound; every GUI behind it (inventory, HUD) hides so only the roll shows.
- The reel: bigger tiles with each cue's picture, name and odds (odds in rarity colour);
  **about 1 roll in 5** it slows onto a rarer cue next to the prize, then ticks back or forward
  onto the real prize (the server's pick; "Click to skip" lands on it too).
- The landing: the cue big on screen, "YOU PULLED" above, picture, rarity, odds, **Sell /
  Keep**.
- **Rare and up** (each bigger than the last; local only for Rare and Epic; everyone in the
  server for Legendary, Mythic and Secret through the existing `Banner` Unbox broadcast):
  - Rare: sky streaks of blue.
  - Epic: purple streaks, then the screen goes black for a beat and the cue bursts in.
  - Legendary: the world drains to grey except gold, slow motion, a golden beam drops from the
    sky onto the player, the camera swoops low round them, then the cue lands in a gold burst.
  - Mythic: the sky turns to deep space with pastel aurora (Mythic's colours), the camera
    rises into the stars, the cue descends from them on a beam of light.
  - Secret: a red-white glitch, the map's lights go out one by one, silence and a heartbeat, a
    shockwave, the camera shakes and spins, the server's sky glitches red-white.
  - Built with our own effect instances (a ColorCorrection, our own Sky swap with DayCycle
    paused) so camera, lighting and sky go back **exactly** as they were: a single cutscene
    owner, restores on skip, on a second pull arriving, on leaving, and when a match starts.
    Players in a match see only a light sky tint, never a camera or screen effect.
- Quick Cases' open-all grid: big flipping cards, rarest last with its own mini sting and the
  sky flash for Rare+.
- Check: every rarity with `/opencase` and forced results, skip at every moment, two pulls at
  once, a pull while another player is mid-match (their view unchanged), phone, PC, gamepad.

### Step 6. The magic 8-ball Case Drop reveal (C11b)
- On `MatchSummary.caseDrop` (after the result) and the `CaseDrop` remote: a giant animated
  magic 8-ball, "SHAKE MAGIC 8 BALL!", and a see-through finger sweeping back and forth to
  show how. Shake by dragging back and forth (touch, mouse), the left stick (gamepad), and a
  real phone shake where the device has one. Each shake fills a meter; at the server's climbs
  the inner glow jumps a colour with a flash and a ding (Starr Drop style).
- Then it flips to the triangle window and slowly ticks through the tier names to the final one
  in its colour (Standard grey, Uncommon green, Rare blue, Epic purple, Legendary yellow, Mythic
  shimmer; ref 10), with a sparkle to confirm. The ball disappears, the case appears in front
  with **Open now / Open later** (instant cases) or "Ready in 6h" and off to the inventory
  (timed cases).
- Many drops at once: one ball labelled x10, one shake, it bursts into a row of triangles that
  tick one by one (rarest last). The first win's Rare Case is shown this way inside the flow.
- Check: a win's drop, `/freecase`, Mystery x10, a day-6 login (3 drops), skip after the first
  time, phone, PC, gamepad.

### Step 7. The left column, corners and rewards without a menu (C2, C8, C9, C18)
- Column: **Shop** (basket), **Inventory**, **Abilities**, and **Free Reward** (a glowing,
  bouncing gift) while something is left to claim. Trade and Rewards go. Hover or tap: a
  bigger shake and a glow burst behind.
- Right side: the **Daily Challenge** target (flashing); it only says "Soon".
- Bottom left beside money: small **Invite** and **Roblox Plus** icons (Plus hidden for
  members).
- **Daily login popup** at the start of a session: the server claims the day by itself on join
  (every day, not only day 1; Economy's `Rewards` block), and the popup shows what was given,
  the streak, the 28-day track and the freeze.
- **Playtime gifts** are given by the server by themselves when reached, with a popup "You
  earned X for playing".
- Join popups queue one at a time, none during the tutorial (`TutorialActive`), none in a
  match.
- **Free Reward page**: (1) Join the group: Roblox's join prompt, then the existing group
  reward (3 Case Drops); (2) Favorite the game: Roblox's favorite prompt, then $10,000 + 1
  Case Drop. Each part disappears once claimed; the icon goes when both are.
- Invite reward once ever per inviter (Economy's `Social` block); the Invite icon opens
  Roblox's invite prompt with our launch data.
- Gamepad: D-pad Up Shop, Right Inventory, Down Free Reward (Daily Challenge when none), Left
  the player list; X Abilities and Y the roadmap stay.
- Check: a fresh save (day 1 popup, Free Reward icon, both claims, icon gone), day 2 via
  `/skiptime`, a playtime gift reached, the tutorial flag holding popups, D-pad map.

### Step 8. Settings (C10)
- The small gear beside the rank HUD opens Settings: **SFX** on/off, **Music** on/off, **Lower
  effects** (cue auras and particles scaled down, never to zero, through one multiplier read by
  `CueVfx.emitter`, `UltAura` and the UI loops), **Show my country flag** (off by default), and
  the code box when the Abilities screen is not live. Saved in Flags.
- SoundGroups for SFX and Music; lobby music (2-3 calm upbeat tracks from Roblox's licensed
  library, quieter in a match).
- Check: each switch survives a rejoin; low effects visibly lighter in the lobby; phone,
  gamepad.

### Step 9. Rank and XP bar (C3)
- Moving stripes on the yellow fill; when one win away from ranking up, the badge and bar
  wiggle ("ONE MORE WIN!").
- Check: `/xp` to one win away, phone and PC.

### Step 10. Player list, global boards and trading (C7)
- Roblox's player list is switched off; our themed list top right: rank badge, username, flag
  (if that player turned it on), wins vs players, money; disguised bots in it like players
  (fixed believable wins, no flag; clicking does nothing). Tap a real player: **Trade**, **Add
  friend**, **View profile** (Roblox's own prompts). A tab with the global boards.
- `src/server/Leaderboards.luau` (the one OrderedDataStore exception): Most wins vs players and
  Highest rank, written on change from the server, read about once a minute, never a save;
  two lobby signs (top 10) built by code.
- Trade screen per D12, on `TradeRequest`/`TradeState`, with the wish list ("They want: X")
  added to `Trading` as a small block.
- Check: list with bots in a lobby (`/lobbybots on`), popup on a second Studio client (by
  hand), boards in Studio's memory store, a trade's every state, phone (list collapsed by
  default), gamepad (D-pad Left focuses the list).

### Step 11. Match-result cutscene, 1v1 (C11a)
- Fade to black, then fade in on the table: the winner stands holding their cue upright, the
  loser lies face down with the cue dropped beside them (local clones of both bodies, bots
  too), the camera pans down onto them; the result GUI sits higher so both show. Falls back to
  today's screen if a player left or forfeited, and for 2v2/3v3/Solo.
- Check: a 1v1 vs PC win and loss, a forfeit, an arena via the Studio arena, skip, phone, PC,
  gamepad.

### Step 12. Keeping players (C15)
- On focus lost or the Roblox menu opening (every time): a big message with a ring: "COME BACK
  TOMORROW FOR" and tomorrow's login reward.
- The first time ever: a Rare Case (1 h timer) gifted by the server once (Flags): the case
  falls out of the sky, the camera pans up then down as it crashes to the ground, and big text
  says it has been gifted to them.
- Check: unfocus twice, a fresh save's first leave, a rejoin (no second gift).

### Step 13. Restyle the rest (C5, D14)
- The ability spin screen and its reveal (the ref 10 tier tick), the rank roadmap, the queue
  screens and host card (the Fill with PC button's look), the match HUD, NEW RANK! and a new
  tier (badge slam, shockwave, shaking title), the in-match ability cutscene.
- Check: each screen on phone, PC, gamepad; a full match.

### Step 14. Finish
- Rerun `python3 tools/economy_model.py`; report Epic+ ownership. A last pass over every screen
  for lacklustre spots (C1's last line). Lane file Status: what works, what is checked on each
  device, the shared-file changes, Requests (the place save and publish, products created,
  anything built only in my window). Tell the designer what was built, checked, what to try by
  hand, and what the integrator must do.

## Verification (end to end)

- `tools/lint.sh` and `tools/test.sh` (new Lune tests for pure pieces: the near-miss reel
  plan always ends on the prize, the 8-ball climb sequence, bot wins by tier, sale windows,
  invite-once and the leave gift's flags, the price-anchor maths).
- Studio lane-gui.rbxl via MCP on Rojo 34876: every step's check above on phone, PC and
  gamepad, console read, screenshots compared with refs 01-11.
- By hand (designer): a real phone and controller, two real players (trade, player list popup,
  server-wide sky), real Robux purchases in the published game.
