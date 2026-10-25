# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-25 (the lobby boards). **The game is live** (officially released 2026-10-10). Work goes on
in `~/Desktop/8ball`, branch `gui-v4`. The STATUS from just before launch, in full, is the top
entry of `docs/archive/STATUS_HISTORY.md`.

## The game is live

- **Released 2026-10-10** with economy v6 (every save started over on the `_v2` stores before
  launch; from now on saves are real players' and are never wiped). The Grand Opening runs 46
  days from 2026-10-10 08:15 EDT (`Config.Shop.Deals.GrandOpening.StartsAt`).
- **The work from here** (designer, 2026-10-10): QA, quality of life, bug fixes, new features
  and updates, and a slow cleanup of old code and features as the game takes its form. Every
  update must not bring a critical bug or error to the live game: the rules are in CLAUDE.md,
  "The game is live".
- **Published by the designer 2026-10-25 (evening): everything pushed up to `e49ef20e`**, the
  lobby boards included (top 100, every country, No data yet), so the country store is counting
  real wins since then; the older not-yet-published notes below are live with it. **Pushed, not
  yet live:** a top player's flag after their name on Top players and yours on its You strip, and no "100+" there off the board
  (`Board_PlayerFlags_v1`; check live: top players' flags appear as they visit a lobby, and one
  who switches Show my country flag off loses it within about two minutes); the **portals ask
  first** (`e498885c`, `Config.Portals.Ask`; check live on a phone, a PC and a pad: stand on the
  Solo pad, the question, No keeps you there, walking off closes it, Yes teleports; read the
  `PortalAsk` custom event after a few days: how many answers are No or WalkedOff).
- **Published:** everything up to `c499ecf` (2026-10-12; the list is in STATUS_HISTORY). **Not
  yet published:** the Shop restock's "Epic or better!" tag removed (DECISIONS); the VIP card's perk
  list says "Gold chat tag" instead of "Rainbow chat tag" (`2c6972f`); the favorite card rewards
  the favorite only (`3037341`: "Favorite +" over a big blue "Like if you enjoy!", Verify is Roblox's
  favorite prompt, cancel says "Favorite the game first!", a favorite opens the check steps and
  the reward comes on Verify after a rejoin); a new tier plays the divisions' rank-up sound; Eagle's Eye draws Fire Shot's full aim lines;
  the spin packs' crossed-out prices (20 / 40 / 200 R$); the **server refresh** (`3340a74`,
  `b1383fd`: a lobby server 5 to 6 hours old moves everyone together to a fresh server;
  `Config.ServerRestart`, owner `/refreshserver`); the Grand Opening block's Firework Cue 5% and
  Beta Cue 1% (were 3.5% and 0.2%, from Rare); pulling a Firework or Beta Cue plays the
  Mythic cutscene (`0b30d95`, `Config.Cutscenes.SceneOf`); the ball-in-hand hint "Drag the cue ball anywhere", bigger (2026-10-25); the **lobby freecam** (2026-10-25, a test: Settings' Freecam row, `Config.Freecam.Enabled`; check on the live game: start it from Settings on a phone, a PC and a controller, fly into each wall and up to the cap, the eye, EXIT, and that a pad, Join, Play Global and the portals do nothing while it is on; read the Freecam custom event after a few days); the **250LIKES code** (`f1240c5`, 2026-10-24: 10 spins, the Abilities code box says USE CODE 250LIKES / NEXT CODE AT 1,000 LIKES, the tutorial points at it, 100LIKES answers "That code has expired."). **Since the 2026-10-24 publish:** country flags on by default and after the name over every head (`f36e3ac`, `4449f56`; watch the `FlagSwitched` custom event); the **VERTICAL shot camera** for clips (`3470655`, its aiming-view angle on trial `4aa55e0`, and the row as three buttons HORIZONTAL / VERTICAL / PLAYER `971507b`; watch `ShotCamSwitched`). **Pushed after the designer's 2026-10-25 publish, not yet live:** Settings on a phone (bigger names and lines, a margin above and below, the Codes gap, short camera lines; `43a300c`); every font back to Fredoka, the left column too (`a0f7789`); the nameplate's flag after the name's box (`221277a`); the **lobby boards** Top players (top 100) and Top countries (every country) under the pergola (`ba9d137`, `c0fb881`; `Config.Leaderboards.Lobby.Enabled`; check on the live game: Top players fills within a minute, Top countries says "No data yet" until the first win after the publish, the You row, scrolling with a mouse, a finger and a pad's right stick at the board, Top countries growing as people win; read the `Leaderboard` custom event after a few days). Already live on Roblox (synced): restock
  Epic 149 and Legendary 599 R$, spins 4 / 17 / 33 / 129 R$.
- **Now (2026-10-12): a tester's QA batch, committed on `gui-v4`, NOT pushed**, held until the
  designer approves the test page (Artifact "Oct 12 Fixes Checklist"). Rounds 1 and 2 (the
  tester's 8 notes, then the designer's first notes) are listed in STATUS_HISTORY's top entry.
  Third round (DECISIONS): Firework Cue 500 ever (`d18f412`), the ADMIN button on a phone
  (`7e4441e`), rising win-track money (`fb2ee13`), the quest's Mystery reward (`82d7ce9`), the
  Sky clock top right (`e60d105`), the win track open with no blocks and its folded amount
  (`8bc09de`), Play Global always (`15eb238`), the Rank then Cues pointer and the Cues glow
  (`b139ad8`, `43939a8`), the arrows off the table (`00a9c00`), the ABILITY IS READY popup
  (`2918d64`), a controller's suggested pocket (`dc94272`), rank bots that miss honestly, no
  planned scratch (`b33a4f2`, `382f003`, `c3f00be`, `343a20c`, `40d17f6`;
  `Config.Bots.HonestMisses`). Fourth round (2026-10-13, DECISIONS): the ability card's words
  inside (`dbcd213`), NEXT under the win track's tile (`9f5c39c`), a phone's Sky clock as icon
  and time (`4ddd9f1`), ADMIN in the corner on touch (`81e2b8e`), the table below Roblox's
  buttons (`fd554f5`), level same-size pocket arrows in the normal view (`69e3f7e`), in one
  line per row with two at each side pocket (`c3ff8e5`), a phone's result screen smaller and
  centred (`6595703`), no Play Global under a result (`65b231e`), the onboarding funnel
  rebuilt (`0077c50`: read the dashboard from the publish day), the TutorialLeft event
  (`fdec3b4`), and then the arrows switched off for the old named rings (`2fec727`). No save
  change (three tutorial moment bits appended). After approval: push, the designer publishes (Restart Servers
  optional), then watch a new account's tutorial on a phone, a lobby with bots and a phone
  match live.
- **Lint and tests (2026-10-12 late night, `gui-v4`):** lint OK (four old LocalShadow
  warnings); all 1253 Lune tests pass. The third round was checked in Studio at computer size
  (1920 x 1080; the phone emulator was off): the pointer, the quest line, the arrows, the popup,
  the suggested pocket, the lobby's win track over Play Global, a Play against PC game with the
  Bronze bot (7 shots: blunders and near misses, none scratched or fouled); console clean.
  The fourth round was checked on the phone emulator (750 x 381): the arrows, the table under
  Roblox's buttons, the ability card, the NEXT tag, the Sky clock, ADMIN; console clean.
  Open from the bot duel (DECISIONS): Bronze measures 85% player wins against a 90% target
  (the model player's own 8-ball losses), Reyes 15% against 30% (drifted before this change). The Studio
  save was put back as it was (Done, $15,820, 2 matches).

## In the game

Server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3 and solo; the global
queue and arena with rematch; Solo and Practice portals; bots (ten tiers, Play against PC,
lobby and disguised bots); ranks (XP only from winning) and money; economy v6
(docs/ECONOMY.md), saves at version 11; 13 abilities with the spin screen; cue skins with VFX
and outlines; lucky blocks (our own, the Mystery upgrade, the Gift and Sky drops); the Free
Reward menu (daily, playtime, the 28-day track, group and invites); Cues (My Cues, Index);
settings, our own player list and boards; the first-time tutorial (v2) and its soft part; the
rooftop map with a day and sunset cycle; pull cutscenes Rare to Secret; the ball streak.
**Off for now:** trading (`Config.Trade.Enabled`), the Daily Challenge
(`Config.UI.Corners.ChallengeOn`).

## Watch on the live game (fixed or built, not yet seen live)

One line each; the long form is the 2026-10-12 (evening) entry at the top of
`docs/archive/STATUS_HISTORY.md`.

- **Temporary lower prices and the 100LIKES code (2026-10-13, pushed, not yet published):** the Shop shows Mystery $10,000, Grand Opening $25,000 and the restock's new prices, and charges them; 100LIKES gave 5 spins and is expired since 2026-10-24 (250LIKES replaced it in the code box and the tutorial). Watch the Grand Opening sink and the Firework Cue's 500 copies on the dashboard.
- **Server refresh (2026-10-14, pushed, not yet published):** with a friend in a live server, type `/refreshserver`: a 30 s gold countdown, "Moving everyone to a fresh server...", and both land in the same new server (F9 server log: "[8ball] refresh" and "GQ refresh hop" lines). Then watch whether servers stay smooth; the first real refreshes come 5 hours after publishing.
- **Lag and vanished ability looks (V1423, 2026-10-13):** lobby bots turned off (cd9a8c2), then back ON the same day as a live test (designer); not proven to be the cause. After publishing with Restart Servers: play a match, use Verity / Black Hole / Guangdong Tiger, watch the frame rate; if still broken, open F9 during an ability shot (Client and Server logs) and screenshot.

- **Controller fixes** (2026-10-11): the 8's call by D-pad rows, a Mystery opened with R2; a
  real Xbox and PlayStation pad.
- **The tutorial batch** (2026-10-12): the zoom-in part, the quest's reward (TutorialQuest
  logs), a phone's spread-fingers hand.
- **The queue pad after a match** (`Config.Multiplayer.Queue.RejoinOnPad`): Leave and Rematch
  running out while on the pad, a 2v2 pad.
- **The VIP tag shut in a match**: a phone dragging the camera over it.
- **Sell Duplicate / Keep** (`Config.BlockOdds.DuplicateChoice`): a real pull on a phone and a
  gamepad.
- **The owner admin panel** (`Config.Admin.Enabled`): an all-servers message, a second player
  picking up drops, a phone.
- **The new rank ladder**: the `rank catch-up` server lines, claims, win rates against bots
  from Gold up.
- **Onboarding**, "Just one more game?", the Favorite card, Camera after a shot, Emotes: a new
  account, a phone and a controller. **Solo and Practice portals**: a real teleport. **Launch
  leftovers** and **the funnels**: the 2026-10-12 STATUS_HISTORY entry.

## Open, waiting on the designer

- **A real phone and a real controller** on the newest screens: the controller pass's button
  map (GDD section 5; "Press A" still in words on the reel, Mystery and bag hints), the
  tutorial on phones and the spin screen, Daily rewards, the Mystery screen, coin flip tokens,
  phone letterbox bars, the ball streak on a tablet, the Gift drop by the real Roblox
  menu button (phone) and Start (controller).
- **Looks to approve:** the Mythic and Secret pull cutscenes (`/cutscene mythic`, `/cutscene
  secret`); the Sky banner, the Index's Collect card and the offer tile on a phone; reel skip
  on Standard blocks and the tutorial reel's Legendary near miss; the Cues redo (see-through
  reel, numbered card mark A or B, the copy numbers' plan).
- **Being tried, nothing final:** Fredoka One (`Config.UI.FontTest`), blur not dims, NEW RANK!
  waiting for a free lobby, the 1v1 result cutscene, cue outlines and the "pop" aura, new cue
  card pictures, ball callouts, no fat-fingered shots (`Config.Input.TouchPull`), the player
  list size, the matchmaking bar and spawn pill (parked), lighting day 10 min / sunset 5.
- **The abilities:** the one-by-one review goes on (unreviewed ones are provisional); phone,
  controller, sounds by ear, the sneak with two players, the designer's voice lines.
- **Tutorial v2 leftovers** (`docs/prompts/TUTORIAL_V2_REPORT.md`, last section): the first
  session's money rescale, two-player paths, Max Players.
- **The cue rarity rework** continues after the Unique cues; Apex's first look was reverted.
- **The place file:** save `place/8ball.rbxl` (it has unsaved Studio changes in git).

## Not yet checked (the Studio tools cannot do these)

- Real multiplayer: 2v2 and 4-player matches, the global queue with real accounts
  (`docs/MULTIPLAYER_TESTING.md`), real Robux purchases.
- Sounds by ear (the levels were measured, not listened to), the click "boop" included.

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test` (Refill, SeedOnJoin) is off since 2026-10-08: the designer's
  blocks are used up like a player's (`/giveblock` gives more); timers still skip for them.
- Studio saves go to Studio-only stores (`PlayerData_Studio_v2`), never the live ones.
