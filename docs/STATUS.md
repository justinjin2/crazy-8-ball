# Status

**2026-09-28 (branch `economy`): the designer's first economy changes.**

- **Built:** the left column without its blue tiles (bigger icons); VIP in chat as "[VIP]
  [GOLD] Name" (the name in Roblox's colour) and a calmly drifting rainbow name over the
  head; Exclusive cues never trade (VIP and Starter included), Unique cues do; the Index
  overhaul ("?" cards for cues not found; a panel with the name and the cue turning in 3D,
  black until found, real colours after; "Find it for +$250"); finder's money the first time
  any cue enters the Index (Common $50 to Secret $50,000, Exclusive $500, Unique $1,000),
  shown as "NEW! +$250" on a case prize with its money flying in, or a banner line for other
  sources.
- **Verified:** lint clean, 631 tests pass (new: a first find is reported once, even after
  selling; every cue but Classic has a finder's money; no Exclusive cue trades). In Studio on
  the PC window: the column (the "y" of Inventory was clipped by the next tile's red dot;
  fixed by drawing each tile over the one below); /givecue Masse paid $250 once with its
  banner, a second copy nothing; a Rare Case reel onto a new Tiki Torch Cue read "NEW! +$100"
  with the HUD held until the card popped; the Index's "?" cards, the black silhouette
  turning, a found cue in colour with "2 exist"; a controller's selection on a card switches
  the panel; the chat prefix read "[VIP] [GOLD] Painicane:"; the overhead rainbow drifting
  (screenshots). The Index at 750 x 361 (the menu resized) and the column in a 750 x 361
  frame. Console clean.
- **Needs a check by hand:** a real phone and controller; the overhead rainbow on another
  player (Studio's capture would not draw your own plate under a big hat, so it was checked
  on a copy). The menu's own money pill (and the Cues tab's NEW dot) still update before a
  reel stops.

---

**2026-09-28 (design only): abilities are back as ultimates, in the release** (GDD section 9,
ROADMAP "Ultimates"). A comeback bar, used about once a match, activated before the shot. No
code yet; the designer has more details coming and picks the other seven ults from the
brainstorm list in section 9's Open.

**2026-09-28 (branch `economy`, overnight run): the whole economy.**

- **Built (docs/prompts/ECONOMY_UI_PROMPT.md; the morning report is
  `docs/prompts/ECONOMY_UI_REPORT.md`):** the real rank and money numbers from `docs/ECONOMY.md`
  (the ladder, per-tier and mode XP, the Classic fade, XP never lost, the gap factor, PC pay,
  team pay, the win streak, anti-farm, short matches, Rookie and first-win boosts); save v2
  with a migration from v1; a catalog of 44 cues plus Classic (placeholder names and looks);
  four money cases (Standard, Rare, Epic, Legendary) with true-odds rolls, selling and
  duplicates; free win cases with their limits and the first win's Rare Case revealed on the
  result screen; rank-up rewards paid for real (money, cases, the tier cue, [TIER]); the
  copies-in-existence counter on every cue and the numbered Beta Cue (Limited). The left
  column (Shop, Inventory, Rewards, Trade) with red dots and D-pad shortcuts; Inventory (Cues
  with filters, detail, Equip and Sell, Cases, Index); cases open on a spinning reel, Fast
  Open's grid of ten; Shop (Cases with Buy 10 and Odds, Limited, Money packs, VIP); Rewards
  (a 7-day streak in four-week cycles, playtime gifts, codes, reminders); Trade as a "Soon"
  frame. Robux ready to switch on: every product and pass in `Config.Products` with id 0
  ("Coming soon"), receipts granted once, the starter and VIP offers, Money Party. The result
  screen's boost chips and case chips, NEW RANK!'s rewards, the roadmap's real case and cue,
  the ROOKIE pill, the [VIP] rainbow chat tag, banners for Mythic and Secret unboxings, Money
  Party and Reyes. 17 economy dev commands (`/econhelp` lists them). New icons from
  `tools/gen_ui_art.py`.
- **Verified:** lint clean, 629 tests pass (new: ranks, money, save v2 and its migration, the
  catalog, cases and odds, the inventory, daily, the shop and receipts, settle, requests,
  the Limited counter). In Studio with
  the real DataStores: a v1 save loaded as v2; buying, Buy 10, opening, Fast Open, selling
  duplicates and every refusal through the server; Robux grants once per purchase id (Studio
  QA hooks, not real receipts); daily, codes and playtime; a fresh save's first real win
  (the Rare Case reel, the result chips, NEW RANK! with Bronze's rewards); a VIP win (2x
  money, +50% XP) and a streak win; every new screen on the PC window, at 750 x 361 and
  844 x 390 (phone) and 1024 x 700 (tablet) by resizing each menu inside the Play window.
  Console clean. A fresh agent audited everything that pays (7 findings, none critical) and a
  second reviewed the whole branch (23); all fixed but two listed ones, and the fixes checked
  in Studio (receipts that no longer qualify pay money, the Limited counter keeps a player's
  number, sales capped at 50%, the reel closes when a match starts, the Index line in
  Rewards, the result screen on a phone). Details in the brief's Notes and the report.
- **Needs a check by hand:** a real phone (touch, the keyboard over the code box), a
  controller (D-pad up to the Shop and B to close cannot be sent by Studio's tools; selection
  inside the menus), the reminder toast (open Roblox's menu), two real players (team pay, the
  Trade list), and a live server: real Robux receipts once the ids are in, PolicyService and
  MessagingService (the Reyes news across servers).
- **To do (designer):** create the products and passes on the Creator Hub and paste their ids
  (the report has the click-by-click guide), save and publish the place, then merge
  `ranks-money` and `economy` into `main` when happy. Next session: trading.

---

**2026-09-28 (branch `ranks-money`): the global queue, the arena and rematch.**

- **Built (designer's request, moved ahead of the roadmap):** Join Global Queue on every
  pad's host card (1v1 alone, 2v2 with 2 on the pad, 3v3 with 3; the first whole side goes).
  A MemoryStore queue that one server at a time pairs every second, closest rank first and
  anyone after 10 s; Cancel, and stepping off cancels. "Match found!", a teleport screen, and
  the players' saves let go before the teleport so the arena opens them at once. The arena is
  a reserved server of this same place: the same rooftop, started at day, with one table in
  the middle in blue felt on black (designer's follow-up: reuse the map), players stood at
  it, the matched teams. After every two-sided
  game (lobby tables too) the result screen has a row: Rematch (all must agree, 20 s, the
  other side breaks), Play another and Lobby in an arena (Leave on a lobby table), the series
  score in place of VS and a "Series 1-0" pill during rematches. A code review by a fresh
  agent found seven edge cases in the arena and queue; all fixed.
- **Verified:** lint clean, 461 tests pass (new: matchmaking, the queue core with 12
  simulated servers, a dying leader and cancel races; rematch and series; arena teams; the
  pad's search). Studio, real MemoryStore: a search posted in 67 ms, matched against a
  pretend other server in 0.9 s, Studio's "cannot teleport" notice, Cancel removes it.
  Studio arena (the StudioArena attribute): the rooftop at day (12 s into the cycle), one
  blue table at the centre, the player stood at it, the save opens in about 1 s, the
  game starts, the result shows the row and 1-0, Rematch starts the next game with the other
  side breaking and the Series pill, 2-0, Play another matched from the arena in 1.3 to
  1.7 s, Lobby. Each game of a series paid rank XP (+250) and money (+$50) exactly once in
  the save. The 2v2 card greyed with "Needs 2 on the pad". The row fits a 750 x 361 phone
  screen. Console clean. Screenshots taken.
- **Not checkable in Studio (needs the published game):** the real teleports, the arena
  loading screen hand-off (`src/first/Arrival`), Lobby back to the same server, timings
  (MULTIPLAYER_TESTING.md, "Global queue"). A real controller's A on the row (Studio's
  simulated A presses no selected button at all). A real phone.
- **Also (designer):** every button on the host card is evenly spaced (Play against PC sat
  twice as far below Join Global Queue: its fold's outline room added to the gap); checked
  in Studio: all gaps 6 px (7.8 on screen at 1.3), the searching card's too, and the rematch
  row's buttons 8 px apart and centred.
- **Fixed after the first live test (designer's screenshot):** Lobby showed Roblox's
  "Teleport Failed ... Server is no longer available (Error Code: 771)". The lobby server
  both players came from had emptied and shut down, and the code retried it three times.
  Now every lobby server marks itself open (with its player count) in MemoryStore; Lobby
  only goes back to the old server while it is open, not empty and has room, and otherwise
  (or if that one try fails) straight to any lobby server. Lune-tested; needs a live check.
- **Also (designer): the win streak over the head.** "🔥 3" in gold on a line above the badge
  and name, from 1, bouncing as it rises; saved (Stats.WinStreak). A real win against people
  adds one; any loss ends it, a quick surrender or leaving too (before, those kept it). Checked
  in Studio: shown at 2, a real win made it 3, a quick win left it, a quick surrender cleared
  it and the line hid; 464 tests pass.
- **To do before the live test:** restart Rojo and reconnect (the new ReplicatedFirst
  folder), then publish.

---

**2026-09-27 (branch `ranks-money`): controller pass with a PS5 pad.**

- **Built:** Y in the hub opens or closes Ranked (it selected the rank badge, and a selected
  button takes the left stick, so the character froze); a hard stick push that goes nowhere
  in the host menu or the opponent prompt lets go of the menu; a pull (X or R2) is called off
  by moving the stick or the D-pad; holding L1, left stick = spin, right stick = cue angle;
  choosing the 8's pocket, each ring's up/down/left/right is the ring that way on screen; a
  controller guide strip at the bottom left (Turn, Fine aim, Zoom, Spin & angle, Shoot, with
  Roblox's own glyphs and the kit's white chevrons) and a Circle beside Leave. A game started
  from the host menu with the pad is playable at once: a leftover selection (Roblox handed it
  from the hidden menu to the spin toggle, so Circle was needed first) is dropped in a match.
  While L1 holds the spin panel open, the guide shows Spin (left stick), Angle (right stick)
  and Center spin (Y) instead; checked in Studio (screenshot), back to the aim rows on release.
  X (Xbox A) is now the only shot button (hold to build power, release to shoot); the R2
  pull is gone and R2 is unbound.
- **Also built:** a red Cancel under "Requested!" on the host's card: the server drops the
  request (the CancelRequest action, tested), everyone's popup closes (it now needs the
  snapshot's requestedAt to match its ask) and the card unfolds to the full choices; a new
  request waits 3 s. Checked in Studio: Request, then Cancel (screenshots), the server's
  requestedAt nil. Needs a check with a second player that their popup closes.
- **Verified:** lint clean, 425 tests pass. Studio: Play solo selected with Y, the game
  started under it, and the selection was gone a frame later (no frame on the spin toggle).
  Y opens and closes Ranked with nothing
  left selected; X held and released shoots, X held with a D-pad press during the pull does
  not; the pocket links from the top-down view (1 2 3 over 6 5 4: 4 left is 5, 5 up is 2);
  the guide and the Circle showing PlayStation glyphs (screenshots). Console clean.
- **Needs a check by hand (PS5 pad):** the left-stick cancel and the L1 stick swap (Studio
  cannot move a real stick); the guide appearing by itself when the pad is used; walking off
  the pad with a hard push after Y on the host menu.

---

**2026-09-27 (branch `ranks-money`): the economy plan.**

- **Written:** `docs/ECONOMY.md`, every economy and rank number from the designer's interview:
  money per match and mode, RP for every tier and difficulty, the opponent-gap factor, the
  Grandmaster/Reyes seats, the account Level (EXP), rarities, the free win case, four money
  cases with odds, sell-back, today's deals, daily rewards, money packs, VIP and its welcome
  offer, the starter pack, other Robux products, trading's gates and Roblox's rules.
- **Checked:** `tools/economy_model.py` simulates players and the rank ladder. At an hour a
  day: first Epic after about 2 hours of play, first Legendary in 6-10 days, first Mythic in
  6-8 weeks; Silver in the first hour, Diamond in about 11 hours, Expert players around the top
  quarter by skill.
- **Not built yet:** nothing in `src/` changed. The next rank and economy work builds to
  ECONOMY.md (its section 16 lists the Config and save changes and the order).

---

**2026-09-27 (branch `ranks-money`): rank screen polish.**

- **Built:** the roadmap's line of XP rules is gone (the cards sit at the bottom); its < and >
  arrows carry a one-piece chevron image (four rotated bars left a seam at the tip, and their
  overlap showed when faded); the rank HUD is 1.5 times its phone size on a computer (was
  1.15); the hover sound is Roblox's "RBLX UI Hover 01", 0.2 s (was a 2.7 s pop).
- **Verified:** lint clean, 425 tests pass. Studio on a PC window: the HUD 346 x 105 px, the
  roadmap with no rules line, both chevrons clean at 42 px in a 56 px arrow (the faded one
  fades as one piece), the new hover sound loaded and playing on a tier. Console clean.
- **Needs a check by hand:** the roadmap and HUD in the phone emulator; how the new hover
  sound feels.
- **Also built:** calling the 8, the chosen pocket's marker now sits inside the hole while you
  shoot (sized from the hole on screen, no caption), so it never covers the jaws; choosing
  keeps the 44 px rings. Verified in Studio on a far side pocket (a small ring in the hole)
  and a near corner (a 53 px ring in the hole), and the six 44 px rings while choosing.
- **Also built:** every panel's pattern is now faint soft 8 balls of a few sizes, each turned
  its own way (after the designer's reference; an even grid was tried and dropped), instead
  of tiny dots; one new tile image
  (`tools/gen_ui_art.py pattern`), so every current and future panel has it. Checked on the
  roadmap and the rank and money pills.
- **Also built:** menus after the designer's Ranked reference: a pale-blue header band with
  the title and close button, the content on a near-white sheet with big rounded top corners
  and a light-blue edge (`HudParts.menuCard`). On the roadmap and the host menu; the rule for
  future menus is in UI_STYLE section 2. Checked in Studio on a PC window; console clean.

---

**2026-09-27 (branch `ranks-money`): the designer's first changes to the rank screens.**

- **Built:** the whole rank HUD grows on hover and squish-bounces on click; badges sparkle,
  with only a faint light sweep every 7 to 9 s; the roadmap redone after reference 03 (the ten
  tiers side by side with arrows, your rank card with an arrow to the next division and its
  money, "Rewards for <tier>": money, Case, chat tag, Cue); a coloured [TIER] tag before your
  name in chat; no celebration for an 8 that loses the game; no darkened screen behind the end
  screen or NEW RANK! (written into UI_STYLE: popups never dim; only the roadmap does).
- **Verified:** lint clean, 425 tests pass. Studio: the HUD's scale 1 -> 1.06 on hover and
  0.95 -> 1.17 -> 1.06 on click, then the roadmap opens; the badge sweep visible 15% of the
  time at a quarter strength with two sparkles on Gold; a real chat message shows
  "[GOLD] Painicane:" with the tag in gold; the server marks a legal 8 `eightWins = true` and a
  wrong-pocket 8 false; the roadmap on a PC window and at phone size; the end screen with no
  dim. Console clean.
- **Needs a check by hand:** a controller on the roadmap (arrows, A on a tier, B); a phone
  swipe on the tier row; how the chat tag looks in the real chat window.

---

**2026-09-27 (branch `ranks-money`, overnight): saves, ranks and money.**

- **Built:** saves (ProfileStore behind `PlayerData`, save layout v1 with migrations and
  validation, a separate Studio store); ranks (46 divisions from rank XP, all 1,000 XP for now,
  win +250, tier floors, one-time money rewards, forfeits and the one-minute mark); money ($10 a
  ball, nice shots $15/$20, win $50 / loss $15, solo 30% then $1 after $300 a day); the rank HUD
  top left, the money HUD bottom left, nameplates, badges in the match bar, the flying cash, one
  end-of-match screen for both players, NEW RANK!, the rank roadmap, nine UI sounds; the
  developer commands /rank, /xp, /money, /addmoney, /result, /newrank, /resetdata, /rankhelp;
  Rank and Money in the player list. Two audits by fresh subagents. Morning report:
  `docs/prompts/RANKS_MONEY_REPORT.md`.
- **Verified:** lint clean, all tests pass (Lune: the save layout, ranks, money, formatting,
  nice-shot kinds, the match result). Studio with API access: saves persist across play
  sessions, bad input refused, a failed load kicks; every command; money per pot and the match
  settle (wins, losses, forfeits before and after a minute, solo); every screen on a PC window
  and at phone size; sounds load and play. Console clean.
- **Needs a check by hand:** a real phone (the thumbstick under the money HUD, the rank HUD in
  Roblox's top bar), a controller (A on the badge, the roadmap's D-pad and B, the popups' A),
  two real players (both result screens), listening to the placeholder sounds, a two-server
  save takeover (live only). Then merge `ranks-money` into `main`.

---
**2026-09-27: a bigger host card on big screens.**

- **Built:** `Style.QueueWideScale` 1.3 (was 1) for screens at least 500 px tall; there the
  card is also raised to end above a touch jump button (a tablet).
- **Verified:** lint clean, 366 tests pass; Studio tablet emulator (1023 x 768): the card at
  338 x 325 px on the right, ending at 488 px above the jump button at 500. Console clean.
- **Needs a check by hand:** a PC window.

---

**2026-09-27: the green balls are deeper green.**

- **Built:** balls 6 and 14 in RGB 12, 92, 52 (was 20, 130, 70): `Config.Balls.Colors[6]`
  (the HUD balls too) and `tools/gen_ball_textures.py`; tex_6 and tex_14 regenerated and
  uploaded from Studio (new ids in `Config.Balls.Textures`). Against the green cloth the colour
  difference went from 17.2 to 31.6 (CIEDE2000).
- **Verified:** lint clean, 366 tests pass; Studio: every table's 6 and 14 carry the new
  textures, and a close-up of a rack shows them clearly apart from the cloth.

---

**2026-09-27: the host card goes at once off the pad; a smaller request popup.**

- **Built:** stepping off the pad hides the host's card on your own screen at once
  (`QueueMenu.setAway`), before the server's exit grace lets you go; back on in time, it
  returns. The request popup is 250 x 66 (was 330 x 96), 6 px off the bottom, with a 48 px
  face and 30 px buttons that still take a 44 px touch.
- **Verified:** lint clean, 366 tests pass. Studio phone emulator: the card hid 0.22 s after
  stepping off (its pop-out); the popup sits below the character's feet. Console clean.
- **Needs a check by hand:** two players: the popup on the other player's screen.

---

**2026-09-27: ball in hand after a foul gets 10 s to move the ball (was 15).**

- **Built:** `Multiplayer.PlacementSeconds` 15 -> 10; the shot clock follows as before. The
  break keeps its own 20 s.
- **Verified:** lint clean, 366 tests pass (the placement-window tests read the setting).

---

**2026-09-27: queue GUI polish.**

- **Built:** the sign's player count and difficulty are centred 16 px apart (their text kept
  at its old drawn size, 22 px: `Sign.InfoTextPx`). The host card sits in the very top right
  corner, beside Roblox's top bar, at 85% on phones, and shrinks only to clear a showing jump
  button (no more 120 px gap without one). Its folding parts reach past the column so Play
  against PC and Play solo are not cut at the sides. "Waiting for opponent" has three dots
  lighting one by one (`Style.QueueDotSeconds`), the unlit ones drawn clear so the words hold
  still.
- **Verified:** lint clean, 366 tests pass. Studio phone emulator: the sign spacing (count
  22-87 px, difficulty 103-197 px, inside the 14-206 px card); the corner card at 85% with
  whole buttons, above the jump button; the dots cycling. Another Studio user took the
  session before the fold was re-checked (the fold logic is unchanged apart from its width).
- **Needs a check by hand:** Request folds and unfolds; the right-side placement on a big
  screen; a controller; two players.

---

**2026-09-27: smaller queue GUI that folds after a request.**

- **Built:** the sign over the pad is smaller (fits its rows, 220 px wide) with the mode big;
  no JOIN pill or "Join to play" on an empty pad; the pad's arrow hides while its sign is up.
  The host card is tucked into the top right corner at 72% on phone-sized screens and on the
  right, halfway down, on big ones (`Style.QueueWideMinHeight`). After Request opponent it
  folds (animated, `Style.QueueFoldSeconds`) to the game and "Requested!", and unfolds with
  Play against PC and Play solo if nobody joined within `Queue.RequestSeconds` (15 s, now one
  window for the popup, the fold and asking again).
- **Verified:** lint clean, 366 tests pass. Studio phone emulator: the small sign (big 1v1,
  0/2, Classic, no pill, no arrow over it); the corner card; Request folds it to Requested!;
  it unfolds after 15 s (height 107 to 163 px over about 0.35 s, sampled per frame). Console
  clean.
- **Needs a check by hand:** the right-side placement on a PC-sized window or tablet; a
  controller; two players (popup Join, the countdown).

---

**2026-09-27: the queue pad just plays: no settings, no Start.**

- **Built:** the pad says JOIN and is see-through glass tinted with its rim. Stepping on gives
  the host a small card top right: "Classic 1v1" (or 2v2, 3v3), the count, "Waiting for
  opponent..." (players), and Request opponent (Request players on team tables); alone on 1v1
  also Play against PC and Play solo. A full pad starts by itself 3 s after the last one stepped
  on (`MatchEngine.startsAt`, `Queue.ReadyGraceSeconds`), shown as "Starting in 3" on the card
  and STARTING 3 on the sign. The sign is back over the pad, without abilities; guests on the
  pad see it too. A request sends everyone not at a table a bottom popup (`OpponentPrompt`:
  the host's face, "<name> needs an opponent..." or "needs players...", Join and Dismiss); Join
  teleports them onto the pad. Difficulty tiles, the abilities toggle, Start and Leave are gone.
- **Verified:** lint clean, 366 tests pass (a full pad starting after the grace, 1v1 and 2v2; a
  walker stepping off in the grace; requests while the pad has room, their cooldown, and a new
  host starting fresh; solo only alone on 1v1). Studio phone emulator: the sign over the pad;
  the 1v1 card; Request opponent (greys to Requested!) and Play solo by real clicks; the 2v2
  card with Request players; the popup's look (earlier today). Console clean.
- **Needs a check by hand:** a PC-sized window and a controller (Y focuses the card, and the
  popup's Join); two players: a guest sees the sign, the 3 s countdown, and the popup's Join
  teleporting onto the pad.

---

**2026-09-27: NICE SHOT! is a lot smaller.**

- **Built:** its word is 18 px (was 40, then 22) and the rays behind it 74 px (was 150).
- **Verified:** lint clean, 363 tests pass; Studio phone emulator, QA combo: the smaller word
  over the side pocket, readable. Console clean.

---

**2026-09-27: the zoom guide goes away once you zoom.**

- **Built:** the first zoom (mouse wheel or pinch, on your turn) hides the zoom guide for the
  rest of the session; it shows again when the player rejoins.
- **Verified:** lint clean, 363 tests pass; Studio: the guide shows on your turn. The phone
  emulator takes neither the tool's mouse wheel nor a pinch, so the hide was not triggered there.
- **Needs a check by hand:** scroll (PC) or pinch (phone) on your turn: the guide goes and does
  not come back next turn or next match; rejoin and it is back.

---

**2026-09-27: no more darkened screens.**

- **Built:** the coin flip, win/lose, leave/surrender cards and the spin picker pop up over the
  game without darkening it (`Multiplayer.Style.ModalDim` 0, `UI.Spin.OverlayTransparency` 1);
  a dialog's see-through backdrop still blocks taps behind it.
- **Verified:** lint clean, 363 tests pass; Studio phone emulator: the coin card and YOU WIN!
  over the undimmed game. Console clean.

---

**2026-09-27: NICE SHOT! for banks, combos, kicks and caroms.**

- **Built:** a good pot that was not plain gets a gold tilted "NICE SHOT!" just over the pocket
  (it pops, floats up and fades in 1.5 s, over turning gold rays) and gold sparkles, on top of
  the pocket burst. The rule is pure (`Rules/NiceShot`); rail hits now carry their spot so the
  pocket jaws do not count as a bank. Never on the break or for the other side's balls.
- **Verified:** lint clean, 363 tests pass (new: plain, bank, combo, kick, carom, jaw rattle,
  and a real-simulation sweep where banked pots read as nice and straight ones do not). Studio
  phone emulator, QA spots: a combo into the side pocket showed NICE SHOT! over it; a straight
  pot into the same pocket did not. Console clean.
- **Needs a check by hand:** a real bank and kick in a match, and how it reads on PC.

---

**2026-09-27: the coin flip says a few words at a time.**

- **Built:** the coin card shows "YOU ARE HEADS" (or TAILS) on the still coin, flips, then "YOU
  BREAK" or "<NAME> BREAKS" over the landed coin for 1.3 s; 3 s in all (was 2.6). The team
  line and "wins the flip" are gone and the card is smaller; the flip sound plays as it spins.
- **Verified:** lint clean, 358 tests pass (the multiplayer tests now follow CoinSeconds).
  Studio phone emulator, QA coin: YOU ARE HEADS 0.5 s, the flip 1.2 s, YOU BREAK 1.3 s.
  Console clean.
- **Needs a check by hand:** the loser's view ("<NAME> BREAKS"; the QA coin always falls to
  the local player), and PC.

---

**2026-09-27: the break has one 20 s clock; running out is a foul.**

- **Built:** on the break, moving the cue ball and shooting share one 20 s clock
  (`Multiplayer.BreakSeconds`), shown on the big clock with no MOVE pill, red and ticking in
  its last 5 s. Running out is a timeout foul (it counts toward the two-timeout forfeit) and
  the opponent gets ball in hand anywhere. Ball in hand after a foul is unchanged (15 s MOVE,
  then 20 s to shoot).
- **Verified:** lint clean, 358 tests pass (new: the break's one clock and its timeout foul).
  Studio phone emulator, QA break: one clock, no pill, red under 5 s, then Foul and the
  opponent's turn with ball in hand. Console clean.
- **Needs a check by hand:** a real match start (coin flip, then the break), and PC.

---

**2026-09-27: the break's hint is short and in capitals.**

- **Built:** "DRAG BALL ANYWHERE ON LINE" (gamepad: "HOLD LT + LEFT STICK TO SLIDE ON LINE").
- **Verified:** lint clean, 357 tests pass; Studio phone emulator, QA break: the pill shows it.
  Console clean.

---

**2026-09-27: ball in hand shows the time to move apart from the time to shoot.**

- **Built:** while the cue ball can be moved, a blue "MOVE 12s" pill with the hand sits under the
  big clock and counts the moving time; the big clock holds at 20 (the shot clock) and the
  portrait ring stays full until the pill reaches 0, then both run. The turn and foul popups
  drop below the pill while it shows.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator, QA fixture: 20 held and ring
  full while MOVE counted 8 to 1, then the pill went and the clock ran 20, 19 with the ring
  draining; YOUR TURN sat under the pill (checked before the hold change). Console clean.
- **Needs a check by hand:** a PC window; a real foul in a match (the fixture skips the foul).

---

**2026-09-27: the group popup stays a second longer.**

- **Built:** YOU ARE SOLIDS / YOU ARE STRIPES now stays up 3.5 s (was 2.5).
- **Verified:** lint clean, 357 tests pass. In Play (phone emulator, QA fixture) the popup was
  on screen 3.5 s when the groups were decided. Console clean.

---

**2026-09-27: the shot clock ring hugs the shooter's portrait and drains.**

- **Built:** the clock round the shooter's portrait is now a rounded ring on the portrait's own
  outline (it was four square bars sized from the scaled bar, so on a phone it sat off the
  icon). It starts full and empties back round to twelve o'clock through placing the cue ball, calling the
  pocket and aiming (it only drained while aiming, and a static green border under it hid the
  drain); red in the last five seconds of aiming. The border stays ink under the ring.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator, QA fixture: the ring's
  halves sit exactly on the portrait at the bar's scale, drain during ball in hand and aiming,
  red arc with 3 s left, zoomed captures show it round and on the edge. Console clean.
- **Needs a check by hand:** a PC window (same code, the bar just scales differently).

---

**2026-09-27: a popup tells each player their group.**

- **Built:** when the groups are decided, the turn popup shows "YOU ARE SOLIDS" or "YOU ARE
  STRIPES" in gold with a solid or striped ball, for 2.5 s, as the deciding ball drops.
- **Verified:** lint clean, 357 tests pass. In Play, an open-table shot that decided the groups
  showed "YOU ARE SOLIDS" with the ball on the client. Console clean.

---

**2026-09-27: bigger Leave icon, clearer zoom guide, bar pinned to the top row, closer phone camera.**

- **Built:** the Leave door fills its button; the zoom guide lighter and bigger, the mouse wheel
  circled in red; the top bar placed from Roblox's real top row (fixes the iPhone 17 Pro drawing
  it lower); on a phone every turn starts a zoom step closer and the break opens at that view.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator: door fills Leave, zoom guide
  clear with the ringed wheel, bar in the top row, aiming and break views closer (the break shows
  the rack and far pockets, the near pockets off screen). Console clean.
- **Needs a check by hand:** the iPhone 17 Pro emulator (the bar should now sit in the top row
  like the 16 Pro Max), and a real phone.

---

**2026-09-27: power bar a little higher; small text keeps its letters' holes.**

- **Built:** on a computer or tablet the power bar sits 5% of the screen higher. Text under 20 px
  gets a 1 px outline (was 2 px), which kept closing the holes of o, a, e, 0, 8; Fredoka One
  stays (the designer's pick from a Studio comparison of five fonts).
- **Verified:** lint clean, 357 tests pass; Studio PC view: bar top at 28% of the screen, the hint
  pill, MOVE and the zoom guide with open letters. Console clean.

---

**2026-09-26: the top bar redone for every screen; bigger centred power bar; zoom guide.**

- **Built:** one-row top bar scaled to fit any width (team, big centred clock, team, Leave at
  the right; solo: 15 balls and Leave); the status card replaced by a 2 s turn popup; on a
  computer or tablet the power bar is bigger and centred on the right; a zoom guide (mouse
  wheel or pinch icon and "Zoom") over the spin button during your turn. Also fixed: the clock
  could flash the whole server time on the first frame.
- **Verified:** lint clean, 357 tests pass. Studio's iPad emulator: 1v1, 3v3 and solo each on
  one row, clock centred, Leave at the right, power bar centred and bigger, zoom guide shown,
  YOUR TURN popup under the bar, OPPONENT'S TURN text on the other side's turn. Console clean.
- **Needs a check by hand:** the phone emulator and a real phone (by the numbers a 1v1 fits
  one row at about 18 px balls on the narrowest emulator phone), a real iPad, and PC.

---

**2026-09-26: a little more room to walk about while waiting in a match.**

- **Built:** the invisible walls round a match stand 3 studs beyond its area on every side
  (`Fence.RoomStuds`); the area, pads and signs are unchanged.
- **Verified:** lint clean, 357 tests pass (a new one: neighbours' walls never meet, 2 and 4
  studs apart). An Edit-mode drawing of old and new walls round four tables. Not yet walked
  in Play: the designer's two-player test was running on the old code, so it was left alone.
- **Try by hand:** restart the test and walk about while the other player aims.

---

**2026-09-26: the shot clock ticks in its last 5 seconds.**

- **Built:** the shooter hears a clock tick at 5, 4, 3, 2 and 1 seconds left while aiming (the
  last two a little higher), stopping the moment they shoot. Licensed APM clip, first tick only.
- **Verified:** lint clean, 356 tests pass. In Play: ticks at 4.99, 3.99, 2.99, 1.99 and 1.00 s
  before the deadline; a shot fired after the first tick stopped the rest. Console clean.
- **Needs a check by hand:** how it sounds and how loud (`Config.Audio.ClockTick.Volume`).

---

**2026-09-26: the match HUD shrunk to the minimum; the break plays the bonus sound.**

- **Built:** the top bar is the balls plus a sliver (37 px computer, 30 phone; was 64 and 52),
  everything in it fitted to that height (Leave keeps a 44 px touch area); one row of balls
  shrinks to 16 px before two rows; the ball-in-hand hint is a thin line as wide as its words.
  Separately, balls pocketed on the break now give the breaker the bonus sound.
- **Verified:** lint clean, 356 Lune tests pass. Studio's phone emulator (750 wide): slim status
  card, two ball rows (one row cannot fit there even at 16 px). A break that pocketed the 2
  granted the breaker the bonus and its sound played at the drop. Console clean.
- **Needs a check by hand:** the PC layout (Studio was on the phone emulator), a wider phone
  (it should get one row), and a controller.
- **Next (designer to confirm):** the aiming camera keeping the table's far end clear of the
  top bar.

---

**2026-09-26: brighter, more saturated lighting; the sunset is a golden hour.**

- **Built (Config.Lighting only):** by day a stronger sun, a lighter and cleaner shade, half the
  haze, and +20% saturation, +12% contrast. At sunset the sun sits 12 degrees up instead of 4,
  golden and stronger, with a warm tan shade instead of lavender, less of the magenta sky's
  fill, a thinner peach haze and +15% saturation; the painted sunset sky is unchanged. The
  fade's warm midpoint matches. Edit mode was relit with the new day look.
- **Verified:** lint clean, 355 Lune tests pass; Play captures of the spawn view and a table,
  day and sunset, before and after, plus the mid-fade and the sun against the sunset sky
  (its disc sits in the painted glow). Console clean.
- **Needs a check by hand:** a real phone at low graphics (post effects and haze differ there).
- **Waiting:** the designer's save to `place/8ball.rbxl` (Edit-mode lighting changed) and publish.

---

**2026-09-26: after a shot the camera swings to a side view of the whole table (a test).**

- **Built:** once the half-second hold ends, the shooter's camera swings round the table (0.9 s,
  eased) to a fixed semi-top-down view from the nearer long side, the table centred and as
  large as the match HUD allows, and swings back to the aiming view when the balls stop. Soft
  shots still keep the aiming view. `Config.Camera.Shot.PullOutView = "Aim"` brings the old
  pull-out back.
- **Verified:** lint clean, 355 Lune tests pass. In Studio Play (PC window, shots fired with the
  controller's A button): a shot aimed down the length (a quarter turn, to the side the camera
  stood on), a shot turning 76 degrees, and a soft tap that stayed in the aiming view. A
  per-frame camera trace showed each swing takes 0.9 s, never loses a table corner from view
  and never jumps; the side view matches the designer's reference framing. Console clean.
- **Needs a check by hand:** the phone emulator and a real phone (a narrower screen changes
  the fit), and a real controller.
- **Open:** in the side view the shooter's own avatar, standing at the table, can cover a corner
  of it.

---

**2026-09-26: the road to release is set; the next work is the pool game itself.**

- **Decided (designer):** the order is (1) the pool game, its UI and mechanics on phone, PC and
  console; (2) ranks and EXP; (3) ten bots, one per tier; (4) cues, money, the shop, inventory,
  the index, loot boxes and trading; then the first-time flow and release. Abilities, the pro
  lobby and the global queue are out of the release (the pro lobby and global queue about one
  to two weeks after it; abilities up for debate). ROADMAP.md is reordered into these stages;
  the GDD and DECISIONS record it, with EXP, the bots' details and the index as Open.
- **Next:** Stage 1 of the roadmap. The first unticked box is 1.5 (server-owned tables), which
  waits on real two-player, phone and gamepad checks.
- **Waiting:** the designer's save of the rooftop map to `place/8ball.rbxl` and publish.

---

**2026-09-26: the rooftop map is finished (all 8 stages; Checkpoint D approved).**

- **Built:** the open-air rooftop pool club from the concept art. The city on the left, the
  coast and green islands on the right, and a day and sunset cycle that is the same for everyone.
  - **At sunset:** lamps over the tables, the fire pit's fire and lit city windows.
  - **Faster walking:** 30% over Roblox's default.
  - **Moving sea:** gentle waves with sailboats drifting on it.
  - **Designer's commands:** `/day` and `/sunset`, which fade the whole server there.
  - About 260,000 triangles of the 512,000 budget (`assets/map/Budget.md`).
- **Verified:**
  - 355 Lune tests pass and lint is clean.
  - Blender and Studio agree on every count.
  - In Play: 24 of 24 walking paths, 7 of 7 edge pushes, and a clean console. Day, fade and
    sunset were captured, and the lowest graphics level too.
- **Needs a real device (Studio cannot fully fake these):**
  - **A phone:** the table lamps, lit windows, bloom and haze at sunset; the fire at low
    graphics; the far view at the lowest graphics level; walking speed with the thumbstick.
  - **A gamepad or console:** walking and the camera round the roof; `/day` and `/sunset` are
    chat commands, for the designer only, so no controller path is needed.
  - **A PC:** the depth-of-field blur on the background (PC-class graphics only) and the full
    sunset at high graphics.
- **Waiting:** the designer's save to `place/8ball.rbxl` and publish (once, now).
- **Next:** ROADMAP 4.1's remaining parts (zone signs, the pro-lobby door), or the next phase.

---

**2026-09-26 (latest): the rooftop city fixed after the designer's look in Play: no warped
towers, no empty grey ground, a soft far edge.**

- **Built:**
  - The near world and the city backdrop draw at full detail (RenderFidelity Precise). Roblox's
    distance LOD had crumpled the far towers and broken up the parks and beach below the
    tower.
  - The side behind the spawn is a full low city now (155 more blocks, the strip by the beach
    included), not a flat grey plain. `Near.fbx` and `Backdrop.fbx` were regenerated and
    imported. The near world's own blocks and the painted far city are unchanged.
  - A light haze (Atmosphere Density 0.15, Offset 0.2, by day and at sunset) fades the far
    city and its join with the painted sky.
- **Verified:**
  - 355 Lune tests pass and lint is clean.
  - Blender and Studio agree: the backdrop is 66,665 triangles (cap 110,000) and the near
    world 8,809 (cap 50,000), with 25 MeshParts (budget 30).
  - Play captures of the designer's three views (the high view over the stair side, the
    railing toward the city, and looking down toward the spawn), by day and at sunset, and at
    phone graphics (level 4). The console is clean.
- **Still to do:** save the place to `place/8ball.rbxl` and publish (the map imports changed),
  then Checkpoint D.

---

**2026-09-26: the rooftop map, Stage 7 of 8 built (the sunset and the day/sunset cycle), waiting at
Checkpoint D.**

- **Built:**
  - The cycle, the same for everyone (Day 10 min, a 1 min fade, Sunset 5 min, a fade back), from
    the server's clock with no network traffic: `LightCycle` (pure, Lune-tested), `MapLighting`,
    `DayCycle`.
  - A sunset sky and a dusk sky rendered from the day's cloud scene (the approved day sky is
    unchanged): a violet sky, the sun low over the sea right of the lounge, the far city lit up,
    island silhouettes.
  - At sunset: the city's windows light up, a warm rim glows under each table, and the
    lanterns, pergola globes (now lit: 9 lights of 20) and fire pit warm up.
  - Depth of field keeps the background soft (the designer's direction at Checkpoint C).
  - `/day` and `/sunset` chat commands for the designer: the whole server fades there.
- **Verified:** 355 Lune tests pass; the fade and both commands were run in Play; 24 of 24 paths
  and 7 of 7 edge pushes pass; a clean console; three critic rounds (notes in Spec section 9).
- **Found:** this place is on Roblox's unified lighting, so there is no Technology setting to
  switch (STUDIO_NOTES).
- **Waiting:** the designer's OK at Checkpoint D.
- **Next:** Stage 8, the finish (docs, then the one save and publish).

---

**2026-09-26: the rooftop map, Stage 6 of 8 done (the far horizon); Checkpoint C approved.**

- **Built:**
  - The far horizon painted into the day sky (`assets/map/gen_sky.py`), which every device
    shows, even phones that draw nothing past a few hundred studs:
    - a far city to 7,000 studs out, its towers gathered in three downtowns ahead-left with
      six landmarks, over a low carpet with blue hills behind;
    - far islands and islets on the painted sea, five of them nearer so phones see islands
      on the ocean side.
  - The 3D sea and land stop at 2,600 studs, where the painting takes over.
  - The mid city steps down toward the painting and eases out on the stair side (a
    re-exported `Backdrop.fbx`, 57,863 triangles); a green waterfront on the far shore.
- **Verified:**
  - No seams or ghost peaks at the join from the Checkpoint C views; the lowest graphics
    level shows the city, the downtowns and the mountains.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds; what they left is in Spec section 9.
- **Checkpoint C:** approved as it is. The backdrop is background: Stage 7's lighting and
  atmosphere soften and blur it so the pool tables are the focal point (DECISIONS).
- **Next:** Stage 7, the sunset sky and the day and sunset cycle.

---

**2026-09-26: the rooftop map, Stage 5 of 8 done (the mid backdrop: the skyline and the
near islands).**

- **Built:**
  - `assets/map/gen_backdrop.py` with two modules:
    - the city from 450 to 2,300 studs: 1,054 low-poly buildings stepping up with
      distance, five landmark towers, tree lawns;
    - eight jungle islands with turquoise shallows.
  - 57,199 triangles (cap 110,000).
  - Phones draw nothing that far, so everything beyond is painted into the sky next
    (DECISIONS).
- **Verified:**
  - In Studio the count matches Blender.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds; what they left is in Spec section 9.
- **Next:** Stage 6, the far horizon painted into the skybox, then Checkpoint C (the city
  side, the ocean side and the high view, for the designer).

---

**Earlier on 2026-09-26: the rooftop map, Stage 4 of 8 done (the near world, the sea and the
day sky).**

- **Built:**
  - A day sky rendered in Blender (`assets/map/gen_sky.py`): a blue gradient with small
    cartoon cumulus low on the horizon.
  - A calm, bright blue sea out to 8,000 studs.
  - The near world 300 studs below the roof (`assets/map/gen_near.py`, 9,451 triangles):
    - the tower's walls and lobby;
    - streets and a park;
    - 23 neighbour buildings;
    - a promenade and a beach that curves round the tower's corner, with palm clumps and a
      turquoise band of shallows;
    - three sailboats drifting slowly (`MapMotion`, `MapAmbience`; the same for every
      player).
  - The coast moved out to fit the beach (DECISIONS).
- **Verified:**
  - In Studio, 9,525 triangles including the boats (cap 50,000) and 11 MeshParts.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds (the cap); what they left is carried to Stages 5 to 7 in Spec
    section 9.
- **Waiting:** a Near.fbx re-import for the shallows' corner fix, which goes in with Stage 5's
  import.
- **Next:** Stage 5, the mid backdrop (the real skyline and islands).

---

**2026-09-26: the rank badges are drawn (not in the game yet).**

- **What:** 47 badges in `assets/ui/ranks/`: Unranked, Bronze I to Grandmaster V (stars up to
  Diamond, gems from Expert, crowns from Expert that grow each tier), and Reyes. Redrawn the
  same day so each tier is its own badge like the designer's reference sheet, then: Diamond
  cyan, Grandmaster black and gold, Reyes rainbow, crisp bevelled pips on the ring's bottom
  edge (no tray, nothing below them), and more glare. `--gif` renders them all shining. Each has a
  white shine mask for the light sweep, plus a sparkle image. Made by
  `tools/gen_rank_badges.py`; look and shine in `docs/UI_STYLE.md` sections 6 and 7.
- **Verified:** every badge rendered and checked on a contact sheet and at full size (none
  touches the image edge; the generator warns if one does); `preview.html` shows the sweep,
  the sparkles and Reyes' gold rays running.
- **Still to do (later, after the map work in Studio):** upload the 95 images, add the ids and
  shine timings to Config, and build the badge and its shine in the UI kit (steps in
  `assets/ui/ranks/README.md`).

---

**2026-09-26 (latest): the queue pad is a rectangle again, and the floating sign floats over it
instead of sinking into the floor.**

- **Pad:** a white rounded rectangle with a glowing rim, lying along the table's long side
  toward the entrance, 10, 14 or 18 studs long for 1v1, 2v2 and 3v3. The mode and STEP IN or
  the count read along it from the entrance; rounded outlines pulse out of it and the arrow
  bobs over it while it has room.
- **Sign fix:** the sign's height is measured in the pad's own axes, and the round pad was a
  cylinder lying on its side, so the sign went sideways into the floor. The rectangle lies
  level, so the sign sits 6.5 studs above it.
- **Verified:**
  - Lint is clean and the placement tests pass. `tests/map_layout_test` fails for now (3
    tests) until the rooftop session regenerates `assets/map/Layout.json` for the new pad
    size.
  - Studio Play on the rooftop gray-box:
    - the sign over a 1v1 pad at head height;
    - the pad from above ("1v1 / STEP IN", upright from the entrance);
    - stepping on: the host menu in about 0.1 s, the rim green, "1/2", the sign hidden;
    - a 2v2 sign and the 3v3 pads from above;
    - a clean console.

**Earlier on 2026-09-26: every table plays one mode again, with one glowing queue pad each,
and each mode has its own look.**

- **Tables:**
  - Ten 1v1, four 2v2 and two 3v3; the 1v1 tables at the front, the 2v2 together in the
    back-left corner and the 3v3 in the back-right corner.
  - The left two columns have wood frames (the regular lobby's looks: green 1v1, raspberry
    red 2v2, slate charcoal 3v3); the right two have black frames (the pro lobby's: blue 1v1,
    the same red and charcoal). Every combination is on the baseplate for testing.
- **Queue pad:**
  - One pad per table (now a rectangle, above), sized by mode, with the mode written big on
    it and STEP IN or the count.
  - While it has room, rings pulse out of it and a big arrow bobs over it. Its rim is blue,
    green once somebody is on, gold when full or playing.
  - Stepping on is instant: the host menu shows the same frame, before the server has seated
    you (0.03 s measured in Studio, 0.42 s before).
- **Menu:**
  - Start needs the pad full ("Need 3 more players" until then).
  - Teams go by arrival, alternately, the host team A.
  - Solo and Play against PC only on 1v1 tables.
  - The table sign's title is the table's mode.
- **Verified:**
  - Lint is clean and 332 Lune tests pass. The rewritten tests cover a full pad, teams by
    arrival, start needs a full pad, solo only on 1v1, and every mode in every look on the
    grid.
  - Studio (phone emulator):
    - prepareImport built six looks, with the template check clean;
    - the grid and pads from above;
    - close-ups of the red and charcoal felts with a full rack (every ball, the 8 included,
      clearly visible);
    - joining a 1v1, a 2v2 and a 3v3 pad (the menu, counts and messages; stepping off closes
      it);
    - fixtures filling the 2v2 and 3v3 with teams alternating;
    - a clean console.
- **For the designer:**
  - In play the raspberry reads quite pink and the charcoal a slate grey. A redder or darker
    felt costs contrast with the maroon balls and the 8; it's one Config number each.
- **Still to do:**
  - Save the place (ServerStorage.TableLooks now holds six looks) and publish.
  - A real phone and controller, and real two- and four-player games.

---

**2026-09-26 (latest): the status card and the host menu, round three (designer's playtest).**

- **Status card:** one line ("YOUR TURN", "THEIR TURN", "ALLY'S TURN", "FOUL!", "ROLLING",
  "COIN FLIP", "GAME OVER"), a bigger clock, and Leave as a small red door (still a 44 px touch
  area). It no longer overlaps the words.
- **Portraits:** no names under them (a rank badge comes later). A player who left gets a red X.
- **Host menu:**
  - One column on the right again, short enough to fit a phone (94% size in the 750x361
    emulator), beside the jump button.
  - Leave is a small red door beside Start.
  - Under each difficulty: a cash icon and 1x, 1.5x or 2x money (Config.Difficulty; the new
    Money icon).
  - Shorter description and messages; no DIFFICULTY heading or "Start alone" hint.
- **Fixed on the way:** the OPEN TABLE label would have errored once balls were down on an
  open table (it asked for a size that no longer existed); caught by an Edit preview.
- **Verified:**
  - Lint is clean and 332 Lune tests pass.
  - Studio Play in the phone emulator: the host menu, a 1v1 bar with "YOUR TURN" and "THEIR
    TURN" fitting beside the clock and the door, and a clean console.
  - Edit-preview numbers for solo, 1v1, 3v3 and an open table at 1280x720, 1920x1080 and
    667x375: every bar on one line, the status words inside their space (a 3v3 on the
    smallest phone shrinks them a little).
- **Still to do:** the designer's look on a PC window, a real phone and controller, and a
  two-player match.

---

**2026-09-26 (latest): the UI redo's second round, from the designer's playtest: phone
layout fixed, Fine controls removed, smaller PC GUI, clearer small text.**

- **Phones:**
  - The top bar sits in Roblox's top row beside its menu, chat and voice buttons (solo and
    1v1; a 2v2 or 3v3 sits just under them on one line).
  - With the table no longer half covered, the camera stops backing away, and the power bar
    starts near the top.
  - The host menu shows its two columns side by side, bigger, and fits on the screen.
- **Everywhere:**
  - Fine controls are gone. The project rule is now "every control works by touch, mouse and
    gamepad" (CLAUDE.md, GDD).
  - Small text (descriptions, notes, the detail line) is dark with no outline.
  - The PC GUI is about 80% of its old size.
  - The ball-in-hand ring is plain blue.
  - The table sign shows abilities ON or OFF.
  - The host menu lists Play against PC first, with no SOON tag. Until bots exist, the button
    does nothing.
  - The extra notes are gone, and the difficulty descriptions are the designer's own words.
- **Verified:**
  - Lint is clean and 332 Lune tests pass.
  - Studio Play in the phone emulator (750x361): the host menu, the table sign with its
    abilities pill, 1v1 and solo bars beside Roblox's buttons, the power bar with its PULL
    label, no Fine controls, and a clean console.
  - Edit previews (numbers) of the solo, 1v1 and 3v3 bars at 1280x720, 1920x1080, 750x361 and
    667x375: every mode on one line.
- **Still to do:** the designer's look on a PC window (Studio is set to the phone emulator), a
  real phone and controller, and a two-player match.

---

**2026-09-25 (latest): every screen is redone in the new cartoony style: white inked cards, a
faint pool-ball pattern, candy buttons, Fredoka One and glossy icons. The table sign only
shows when you walk right up to a table.**

- **Top bar:** the reference match bar on white. Portraits with the clock running round the
  shooter; glossy balls with a thick ink ring (stripes no longer melt into the white), grey
  with a red X once down. The status card has a phase icon (a cue on your turn, an hourglass
  on theirs, a glove, a target, a whistle, a coin, a trophy), the clock pill and a red Leave.
  Your turn makes the cue pop and a shine sweep the card. Phones get a compact bar: a 3v3
  fits on one line and Leave is the door icon.
- **Foul popup:** no panel. A whistle, a big red FOUL! and a few plain words ("Scratched the
  white ball"), gone after 3 s (it was an 8 s card).
- **Queue area:**
  - The host menu has a crown, a people count, and difficulty tiles with aim-line pictures (the
    chosen one blue; a guest sees the others faded). The ON toggle is green and Start breathes
    once it can be pressed; the menu pops in and out.
  - The floor box is white and inked with a people icon.
  - The sign over a table now pops in only within 6 studs of that table, one at a time, and
    hides while you are in a box or playing. The server no longer builds sixteen billboards.
- **Also restyled:** the coin flip, win (trophy over turning rays) and lose cards, the leave and
  surrender dialog, fine controls, the ball-in-hand hint and ring, the wrong-target warning,
  the pocket targets, the power bar (fill runs green to red) and the spin panel.
- **How:** a UI kit (`HudParts`, `UIAnim`, `Config.UI.Kit`) and 25 icons plus effect images
  drawn by `tools/gen_ui_art.py`, uploaded to Roblox. Choices: DECISIONS.md and UI_STYLE.md.
- **Verified:**
  - Lint is clean and 332 Lune tests pass (new: the nearest-table check).
  - Studio Edit previews at 1920x1080 and at 844x390 and 667x375 phone sizes: solo, 1v1 and
    3v3 bars, open table, the foul popup, coin, win, lose, the leave dialog, fine controls,
    and the host menu (host, alone, solo choices, four uneven, four even, guest).
  - Studio Play: a 1v1 top bar, the foul popup, placement, the pocket call, the spin panel,
    the power bar, the sign popping in near a table and hiding in the box, the green team
    halves with four in, and gamepad Y putting the selection on Start. The console is clean.
- **Still to do:**
  - The designer's look.
  - A real phone and controller.
  - A two-player match.
  - B on a gamepad: Studio's input tool cannot press it; the code is unchanged.
  - Uploaded images need Roblox moderation before other players see them.
  - The place save and publish from the earlier rounds.

---

**2026-09-25 (latest): one queue box per table, a host menu with three difficulties, and no
countdown. Any of the sixteen tables plays 1v1, 2v2 or 3v3.**

- Every table has one long box along its right side (as you walk in from the spawn) for up to
  six. The first in hosts. Everyone in the box sees the queue menu (top right): the host's
  name, players n/6, difficulty (Classic, Difficult, Challenger), abilities on/off (does
  nothing yet) and, for the host, Start.
- Start: two play at once (straight to the coin flip); four or six must split evenly between
  the box's two halves, which show grey and turn green when even; three or five are greyed
  out with "Need 2, 4 or 6 players". Alone: Play solo, or Play against PC ("Coming soon").
- Difficulty (Config.Difficulty): Classic every line; Difficult the aim line and ring only;
  Challenger no lines. The group glow and red X stay.
- The grid moved to 26 studs apart across to fit the boxes. Gamepad: Y puts the selection on
  the menu, B takes it off. On touch screens the card sits left of the jump button.
- Also fixed: the "INVALID FIRST TARGET" warning was stuck in the top left of every match, and
  held placement arrows and the surrender-vote count had stopped updating (a block of
  MatchHUD.update was lost on 2026-09-23; restored).
- Verified: lint clean, 331 Lune tests pass. Studio play-solo: the boxes and floor words,
  joining, host menu, the difficulty and abilities choices reaching the server, Play solo in
  each difficulty (lines checked per level), Play against PC's notice, the guest's read-only
  menu, 3 players greyed, 4 uneven (grey halves) then even (green), Start into a 2v2 coin
  flip, L and walking out leaving. Fake players came from the Studio QA fixture.
- Still to do: a real two-player check (Studio's Clients and Servers), and the menu on a real
  phone and gamepad. Save the place to `place/8ball.rbxl` and publish (from the map removal);
  check `Lighting.Technology`.

---

**2026-09-25: back on a plain baseplate with sixteen 1v1 tables, eight green and
eight blue. The test hub map is removed from the game and the repo.**

- The map's code, package, brief, tests and notes are gone; the hub map's look is Open again
  (GDD section 10), for the designer to come back to.
- Config.Hub.Tables is a four by four grid, 20 studs across and 43 along; every table is 1v1.
  The left two columns are green cloth with wood, the right two blue cloth with black wood
  (Config.TableModel.LookByTable). The spawn is in front of the grid, facing it.
- In the place (through Studio MCP, Edit mode): `workspace.Hub` and its prop library are
  deleted; the Baseplate (512 by 512, top at y 0, grid texture), the visible 12 by 12 spawn pad
  and the lighting are back as they were in `place/8ball.rbxl` before the map (Soft, 14:30,
  Brightness 3, a default Sky, Bloom, ColorCorrection and DepthOfField off).
  `ServerStorage.BridgeModel`, a leftover of the removed rake, is still in the place.
- Verified: lint clean, 327 Lune tests pass (the grid, the looks and the fences are tested).
  Studio play-solo: 16 tables built, 8 of each look, 2 pads each, the spawn in front, a solo
  game on a blue table, no console errors.
- Still to do: save the place to `place/8ball.rbxl` and publish; check `Lighting.Technology`
  (scripts cannot read it; before the map it was ShadowMap).

---

**2026-09-25 (merged into `main`): the body reaches every shot by pose and position alone,
with both feet planted, the head clear of the table, and both arms reaching along the cue.
Checked in Studio play-solo on R15; the designer's look at this round is next.**

- Poses: standing, leaning further in, stretching over the rail (belly on the edge), kneeling
  on the table, and last kneeling up on the rail top. Both feet stay on the floor in every
  standing pose. Each pose can turn to the cue in seven ways (Config.Stance.Sides), and the
  body is not tied to the cue line.
- Default R15 on an even grid: 48% floor, 4% stretching, 48% kneeling on the table, every
  shot reached. A foot on the floor only reaches about 2.5 studs onto this table.
- The head: AvatarPose.measureBody now measures the neck and the head; the stance places the
  head as the pose looks at the cue ball and keeps it HeadGapStuds above anything under it.
  Natural lean 45 degrees.
- The grip arm reaches back to hold the cue near its butt (a long wind-up slides the cue
  through the hand); the bridge arm reaches out nearly straight toward the ball.
- R6 and smaller bodies cannot reach about 2% of ordinary shots (a ball frozen to a cushion
  under a steep jump cue): they stand with the hands as near the cue as they get.
- Verified: lint clean, 328 Lune tests pass. Studio play-solo (R15, accessories hidden in a
  test camera): the break, a side-rail shot and a kneel look right, feet on the floor, the
  head above the rail, no console errors.
- New: the shooter can walk while the balls roll, about a second after the shot (the shot
  camera keeps following the balls); their next turn poses them again from where they
  walked. Checked in Studio play-solo: released 1 s after the shot, walked to the fence,
  back into the aiming pose on the next turn, no console errors.
- Still required: the designer's look; the walk checked with a watcher client and on a phone
  and a controller; R6 in Studio; a 360-degree aim sweep watched from a
  second client; the climb back down after a kneel (still a cut); phone, PC, gamepad.

---

**2026-09-25: the remade table and jump shots are signed off by the designer and merged into
main.**

- Both roadmap boxes are ticked. The jump heights and pocket feel stay as tuned.
- The place is saved to `place/8ball.rbxl` and published. The old seven-mesh table is gone
  from the place and the repo.

---

**2026-09-24 (later): jump shots reviewed by three independent agents, fixed and retuned.**

- **Landing before the foul (designer):** a ball that flies off now skips off the rail if it
  hits it, falls to the floor, bounces and rolls for about a second. Only then does the foul
  card show. The server waits exactly that long.
- **Regression check:** 8,658 ordinary 4-degree shots played exactly as before jump shots
  existed. Object balls never left the cloth.
- **Bugs fixed from the reviews:**
  - A ball rising into a cushion froze in mid-air.
  - Cushions launched flying balls 4-11 ft up.
  - A ball coming down onto a cushion top was teleported.
  - Off-table was wrong at corner pocket mouths.
  - A ball perched on another bounced until the shot timed out.
  - A tiny energy gain on separation.
  - A hard flat shot hopping into a pocket wasn't pocketed, so a scratch became off the
    table.
  - The power bar dipped where the flat hop begins.
- **Speed:** normal shots were 48% slower than before jump shots; now about 6%.
- **Realism:**
  - Jumping a ball over another is realistic. The model now follows Dr. Dave's TP B.10:
    slate bounce 0.6, and a raised cue's top stroke is 12 mph.
  - Full-power jumps rise about 9, 18 and 26 in at 30, 45 and 60 degrees (they were 19,
    41 and 62).
  - At 45 degrees a ball clears a blocker from about 70% power. 60 degrees at full power
    still flies off.
  - Flat full-power shots at a nearby ball send the cue ball off about 5% of the time.

Still required: a real controller, a phone, a two-player check and the designer's feel check.

---

**2026-09-24: jump shots landed (branch `jump-shots`, from `table-remake`). A real
controller, a phone and a two-player check are still to do.**

What was built:
- A cue-angle slider sits beside the white ball in the spin panel. It runs from 4 degrees
  (normal) to 60. Tap or drag the track, or use the up and down arrow keys. On a gamepad,
  hold L1 and push the left stick. The chosen angle shows under the spin button, and it
  resets after every shot, the same as spin.
- A raised cue drives the cue ball into the slate, so it bounces. With the right power it
  jumps a blocking ball. Too much power sends it off the table. The ball carries on to the
  floor, bounces and fades out.
- Rules:
  - A ball off the table is a foul, and the opponent gets ball in hand.
  - An object ball that flies off goes back on the foot spot.
  - The 8 flying off loses the game. On the break, the 8 goes back on its spot instead.
- Very hard flat shots only rarely pop the cue ball, and object balls never leave the cloth.
- The aim line follows a jump. It skips the balls the cue ball clears, puts a small ring
  where it lands, and shows a red cross where it would fly off.
- Other players see your raised cue. A flying ball has a shadow under it, and it knocks
  when it lands.

Verified:
- Lint is clean and all 330 Lune tests pass. They include new tests for flight, bounces,
  clearing a ball, flying off, dropping into a pocket from the air, energy, replay
  checksums, the aim line and the off-table rules.
- Every ordinary 4-degree shot plays exactly as before (the saved test shots are
  unchanged).
- In Studio Play:
  - The slider set 32 degrees from a tap and 34 after two up-arrow presses. The badge
    showed 34.
  - L1 opened the panel.
  - A 60-degree full-power shot flew off: it rose about 61 inches, dropped to the floor and
    faded. The FOUL card read "A ball flew off the table.", followed by ball in hand.
  - A 45-degree jump showed its shadow.
  - The console was clean.

Still required:
- A real controller (L1 + left stick, and the D-pad, which Studio's input tool cannot
  press).
- A phone: tap the slider.
- A two-client check that a watcher sees the raised cue and the flight.
- The designer's feel check on jump heights. The tuning numbers are
  `Config.Physics.SlateRestitution` and `ClothHopLossSpeed`.
- Merge `table-remake`, then `jump-shots`, into main.

---

**2026-09-24: the new table is in Studio (branch `table-remake`). Designer playtest, device
check and the milestone save are pending.**

The table was remade from scratch (ROADMAP "Table remake"):
- One model, styled on the Diamond Pro-Am with no brand, built by a Blender script straight
  from the physics (`assets/table/`). The cushions, jaws and pocket rims sit within 0.004 in of
  where the balls play. The old table's pockets were 15% wider than the physics.
- 7 in rounded rails, chrome caps on all six pockets (removable), two-piece bolted legs,
  corner blocks, 18 pearl sights and a blank logo plate. 8,134 triangles (the old table had
  19,220).
- Two looks on the same mesh: bright blue cloth with satin black wood, and bright green cloth
  with red-brown wood. 17 textures at 1024 are shared by all tables; the cloth is one
  repeating tile tinted per look.
- In Studio the template is `ServerStorage.PoolTable` and its looks are in
  `ServerStorage.TableLooks`. Table 2 is green as a temporary side-by-side showcase; which
  tables use which look is still open.

Verified:
- lint clean and 314 Lune tests pass, including the new geometry, looks and model tests;
- `TableModel.py` passes every check (physics match, gaps, budgets, UVs, FBX round trip);
- in Edit mode, both looks render correctly;
- in Play, the server builds 3 tables (blue, green, blue) with all 8 textured parts; console
  clean.

Still required:
- the designer's playtest (pockets feel, close aim view);
- a phone, PC and gamepad look at the cloth up close;
- save to `place/8ball.rbxl` and publish;
- then merge `table-remake` into main and delete `assets/table/legacy/` and
  `ServerStorage.PoolTableModel`.

---

**2026-09-24: realistic shooter pose landed (rake, cue extension, rail-clearing cue, wind-up,
idle after the shot, everyone sees it). Multi-client and device acceptance pending.**

The shooter now looks like a pool player (modelled on "9 Ball Roulette"):
- The body stands anywhere round the table (never in it) and changes with reach: standing,
  leaning over, a bridge (rake) under the cue, then an automatic cue extension. Both hands
  hold the cue; the head watches the cue ball. R15 and R6.
- The cue is about 7 studs and tilts up over a rail or a ball behind the cue ball (visual
  only; physics stays at 4 degrees).
- Pulling the power draws the cue back for everyone; release plays a quick stroke.
- After the shot the shooter idles on the spot, facing the table. Same shooter: back to
  aiming. Turn passes: normal camera and walking from that spot, no teleport.
- The shooter sees their own body translucent; everyone else sees it fully visible.
- The server places the shooter with the same stance maths, so every screen agrees.

Verified: lint clean and 297 Lune tests pass. In Studio: default R15 and R6 test rigs posed
in Edit mode (hands on the cue and the rake to 0.001 studs, joints closed, body outside the
table, about 0.05 ms per pose), and on one Play client with the real avatar: aim pose and
rake, wind-up from a real mouse drag, stroke, the idle animation on the shot spot facing the
table, solo continuation back to aim, and a 1v1 turn pass releasing the body in place with
the normal camera. Console clean.

Still required for the pose: a two-client check (watcher sees the posed, fully visible body,
the wind-up and the stroke), an R6 avatar in Play, phone and controller. The bridge mesh
(`assets/bridge/BridgeModel.fbx`) still needs importing into ServerStorage; until then a
parts stand-in is used.

---

The current update is [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md), revised after the
designer's first playtest. The baseplate has three blue-cloth tables for shared 1v1, 2v2
and 3v3 matches, on the baseplate. No bots, rewards, saved wins,
difficulty or abilities.

Latest changes:
- Every turn starts in the **home view** (the pre-multiplayer middle framing), and the
  camera pulls out during the shot and returns afterwards.
- The only top-down view is the 8-ball pocket call. Break and ball-in-hand placement
  happen in 3D with no Lock button: drag the ball (it moves instantly) and shoot at any
  time within the 15 s placement window (20 s to aim, 10 s for an 8-ball call).
- The bonus plays for the owning team in the same frame as the drop, including the first
  ball, which assigns groups. The HUD shows who is solids and who is stripes the moment
  that ball drops.
- Pocketed balls get a red X across the whole ball.
- Break and ball-in-hand turns open two zoom notches wider than the home view. Timers:
  15 s to place, 20 s to aim, 10 s to call the 8. Invisible walls keep everyone off the
  tables. Queue slots light up with a light column, sparkles, a rising scan frame and a
  sound when someone steps on one.
- The camera stays pulled out until the next turn starts, then either returns to the home
  view or eases (no cut) back into the player's own camera.
- Breaks now spread properly: touching racked balls push on each other at once
  (Physics/Cluster.luau). Over 200 seeds, 61% of full breaks pocket a ball and about 12
  balls reach a rail. Every game opens on a random rack.

- 2026-09-23 playtest fixes:
  - Solo mode: a Play Solo button when you're alone on a pad. Clear your first group, then
    the other group, then the 8. No clock. A foul gives ball in hand; an early 8 loses.
  - Fixed the permanent cursor lock after a turn.
  - Walking is normal again: physical fences replace the teleport loop.
  - Side spin no longer bends the line or the shot.
  - Your group glows green and the other group is greyed.
  - Balls pocketed while the table is open show next to OPEN TABLE.

Verified: lint clean and 242 Lune tests pass. On one Studio client, the home view pose
was checked numerically, as were the top-down-only pocket call, a real mouse drag with
the camera holding, the drop-frame reveal and bonus, and a red X screenshot. No project
errors or drift warnings. See [MULTIPLAYER_PROGRESS.md](../MULTIPLAYER_PROGRESS.md).

Still required:
- Real full matches in each mode.
- Two-client watcher smoothness.
- A phone (touch) and a physical controller: LT + left stick, held arrows.
- Audio listening.
Known art debt: imported mesh pockets differ slightly from regulation geometry.
