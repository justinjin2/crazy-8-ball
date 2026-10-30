# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-30 09:45 (**live: everything up to `107e7843`**, the designer's Oct 29 ~22:20 EDT
publish; pushed since, not published: the boost lines' "i"). **The game is live** (officially released 2026-10-10). Work goes on
in `~/Desktop/8ball`, branch `halloween` (it holds all of `gui-v4`). The STATUS from just before launch, in full, is the top
entry of `docs/archive/STATUS_HISTORY.md`.

## Halloween 2026 (branch `halloween`, LIVE: published by the designer Oct 29 ~20:00 EDT)

- **Pushed Oct 30 ~09:45 EDT, NOT yet published: the boost lines' "i" on a phone** (designer,
  morning). On a touch screen with no mouse the Money Boost / Candy Boost lines take no touch
  (a finger on them walks), and a tiny blue "i" left of each opens that line's card; PC hover
  and click and a pad's A are as before; no "i" in a match (`a8cd6153`, `8c9d9b27`;
  `Config.UI.BoostPill.Info.Enabled` false = the old way). The cards lost their grey hint lines
  under Total ("Candy too", group, VIP; the Candy card keeps the Rush timer; `a517637b`).
  Baseline: `BoostCard` "Opened" on phones 36,137 (24,724 players, 71% of phone tile players;
  PC 0.8%) from Oct 30 00:00 to ~12:00 UTC, ~2,500-3,400 an hour. Measure after the publish: phone opens an hour
  should fall to a small share of that. Checked: lint, 1,571 tests, Studio at a phone-sized HUD
  (the "i" forced on: both cards open and close from it, the in-match hide, a fresh-player
  join, skip, first solo game and back). Check by hand on a real phone: walk with a finger
  over the lines (no card), tap each "i". No save change; Restart Servers optional.
- **Live read Oct 30 ~09:00 EDT (Creator Hub, first ~13 h of Halloween):** CCU ~3,100 (+40%
  on the same hours a day earlier, the same growth as the day before); Halloween products
  20,965 R$ (Sword 35 sales), all Robux +10.6% on a day earlier; servers healthy (P10 56-59).
  **Watch: client frame rate P10** fell to ~1 FPS at 12:00 UTC on phones and PCs (Oct 29 too,
  worse since the update; client script CPU 1.5-2.5x). Pitchfork 11% of first-Candy players
  (rule 30%): re-read the full UTC Oct 30 at ~22:00 EDT before any retune.
- **Published** (Oct 29 ~20:00 EDT, up to `e879ef8e`): v3 (the designer's ~12:00 list), **v4,
  the 14:20 GUI round**, **v5, the 17:30 fixes**, and **v6, the 19:20 Rush and Friend Boost
  round**. The checklist and every switch are in `docs/halloween/RELEASE.md`. The LIVE store
  icon is set (91272722538693) and the description has the 5KLIKES/10KLIKES lines, a Halloween
  line and "Still working codes: 2KLIKES" (saved 20:01).
- **Published Oct 29 ~22:20 EDT (up to `107e7843`): ground candy far fewer, 4 Candy each.** The designer, live: dozens on the map (a spawn every 4.5 s a player, most never
  collectable under the cap). Now one every 20 s (+-5), ~1.5 around a player, **4 Candy a candy,
  a bag of 38 a UTC hour (152 Candy)**; a full bag stops that player's spawns and hides every
  candy on their screen until the next UTC hour (`HalloweenMap.Candy.HideWhenFull`, attribute
  `HwCandyFull`); board 3/5 Pickups quests 8 / 35. The 3 h-a-day player: Broom ~4.6 h, Jack
  ~8.5 h, Sword ~14.6 h (ECONOMY, Halloween). Studio fresh-player run Oct 29 ~22:00: join, skip,
  +4 pickups, the 38th hides the candy with the note, a first match vs a lobby bot (+7 a pot in
  the Rush, Matches and Wins done), boards 3-6 by time jump (board 2's two finished quests
  auto-paid +160 at board 3, x2 on Oct 31), the end converted 325 Candy to $3,250 and the lobby
  went back to normal. Check live: few candies; fill a bag (38) and the candy vanishes with
  the note, then comes back at :00. Restart: no save change, any.
- **Published Oct 29 ~22:20 EDT: the King-quest auto-pay fix.** A live bug found by the Candy review: at each board's open the auto-claim read the King
  slots (run as their Alts all event) at the King's need, paying 250 Candy for 1 s of play
  (2.4, at board 3's open, Oct 30 19:00 EDT), for 2 wins (4.4, board 5) and 3 nice shots (6.4,
  the end). Fixed in `Quests.endClaimable`; Lune test and Studio board-jump check. Watch at
  board 3's open (Oct 30 19:00 EDT): HwQuest "Auto" events for key 2.4 should be rare (only a
  real 60 min of play), not most board-2 players.
- **v4 (designer 14:20, with an interview):**
  - The Sword's soft pre-v3 aura is back, also on its menu card. Its dark purple trail has
    glowing embers instead of painted flames, and its finisher is a purple energy burst standing
    on the hole (no fire face).
  - The Broom's finisher keeps its stars only (no witch, no bats).
  - The event menu: bigger cue pictures, with the Pitchfork's fork 2.2x and the Jack's pumpkin
    1.5x (new art 130408256165091, 103301193919705). The Robux button is the Candy button's
    size. The "2026" badge sits bottom right above the name everywhere.
  - The menu has its **Haunted night** look (`Menu.Theme`). A **PREVIEW** button on each card
    opens the Cue Preview on TRAIL for the four event cues only (`CuePreview.Event`); on a phone
    it is the icon alone.
  - Permanently, only Painicane sees "N exist" (`Inventory.ExistOwnerOnly`).
- **v5 (designer ~17:30-17:50):**
  - The Jack's card picture shows the pumpkin in the model's own shape, 1.2x, on the centre line,
    so the PULL bar stands it in the middle (75460670405284).
  - PREVIEW plays like the concept clips: black screen, the cue alone, the trail, the finisher,
    looping, only the X (`CuePreview.Showcase`). The Sword is turned so its blade shows. A
    "Watched" event counts whole loops.
  - On a phone the boost lines and the Candy pill stack under the left buttons, smaller
    (`BoostPill.ShortBesideColumn` false).
  - Verified (18:30-18:50): lint and 1,564 tests; Studio at a phone-sized 750x323 HUD: the boost
    lines and pill under FREE REWARD, the event menu with the new Jack card, the Sword's and the
    Jack's model shots on black, the Jack in the PULL bar of a solo game (centred, round).
- **v6 (designer ~19:20) and the release sweep:**
  - The boost cards' friends row is "Friend Boost", +0% until a friend joins.
  - The Candy Rush is personal: 2x for 10 minutes when Halloween turns on for the player, then
    every 45 minutes; the start is saved, so a rejoin keeps the cycle (`Rush.Personal`).
  - Sweep fixes: the boost lines and the Candy pill show at the soft part (they waited for
    Done); the money pill's "+" hides in the guided tutorial; the Sky banner waits for the soft
    part again.
  - The owner panel's **Give Candy** row and `/hw candy <n> <player>` (Painicane only).
  - Verified (20:00-20:06, Studio, a fresh save): Arrow -> Soft turns Halloween on and starts
    the personal 2x ("CANDY RUSH 9:50"); the Candy pill, Candy Boost line and HALLOWEEN button
    show at Soft; Give Candy +400 and `/hw candy 50 pain` +50; the Pitchfork bought for 300
    Candy (owned); the 300 and 1,200 Candy packs through the real receipt handler, a replayed
    receipt paying nothing; board 2's four quests claimed (+560), a second claim paying
    nothing. Console clean. Lint and 1,567 tests.
- **In it from v3:**
  - No Pumpkin King.
  - Four cues for Candy or Robux: Pitchfork 300 / 49 R$, Broom 2,500 / 249 R$, Jack 4,500 /
    399 R$, Sword 7,500 / 599 R$.
  - Candy about a third each from pockets (+3 a paying pot), quests (60/100/150/250) and the
    ground (1 each, 150 an hour at most; a spawn every 20 s since d7fdbd45, below). The
    tutorial's real match pays quietly.
  - The Pitchfork's prongs stay and its flames are calm. The Jack's laugh is quieter and near
    only. The Broom's head is shorter.
  - Codes: 5KLIKES and 10KLIKES (10 spins, $10,000; the tutorial types it) and 2KLIKES lowered.
  - Roaming and the badges.
- **Verified for v4 (Oct 29, 16:00-16:35):**
  - Lint and 1,556 Lune tests on the merge, including new tests that the Broom finisher has no
    bats and that the Sword's burst holds its column and fire past 1 s.
  - Studio PC: the menu owned and unowned (Haunted night, the bigger art, equal buttons, the
    badge, four PREVIEW buttons) and the menu at phone size 844x390. PREVIEW opened the Cue
    Preview on TRAIL with the Sword's loop, and closing it came back to the menu.
  - The Sword and Broom finishers fired at real pockets: on the hole; the Broom's stars only.
    The Sword's burst was first too small (all but gone by 1 s), so it was scaled up (`bb2334d7`):
    about half the v3 face, the body held to ~1.5 s, a dark violet smoke core so it reads violet,
    not white, on the magenta lobby cloth (checked in Studio). 116 particles once.
  - "1 exists" on the owner's big card.
  - A fresh-player run on a new Studio store: join, tutorial skip, Daily, the event menu
    unowned, a first match against a disguised bot won to its result (7 Candy).
  - Console clean apart from the known 203785492 line. No uploads in v4 but the menu's four
    theme pictures; no template rebuild.
- **Open:**
  - A real phone, iPad and controller check (only PC here).
  - The non-owner "exist" line is checked by test only (Studio plays as the owner).
  - On a phone the 2026 badge touches the right side of the Jack's pumpkin.
  - By hand: the Pitchfork's bridge hand on a short bridge, the Broom on a small avatar's back.
  - After the publish, client memory on phones.
  - Stale comments (`Net.luau:457`, the HalloweenMap budget comment). Now-unused art for a later
    cleanup: the Sword's fire_face and toon_flame sheets and `tools/hw_sword_fx.py`, the Broom's
    witch_fly sheet, the old Pitchfork and Jack thumbs.
- **After the publish:**
  - Save the place to `place/8ball.rbxl`.
  - By hand on live: a new account's tutorial into the Halloween UI, the personal 2x chip, a
    cue bought with Candy (RELEASE 1).
  - Watch 3_FirstCandy -> 4_Pitchfork, `HwCandy` vs `CandyPickups` vs `HwQuest`, `HwBuy`, the
    new `CuePreview` "Halloween" opens, FPS and memory (RELEASE 6).
- **Parked:** Robux Limited cues (branch `hw-core-limited`). The Grand Opening block stays off
  the Shop (it was ~37% of dev product revenue before; earlier decision).

## The game is live

- **Released 2026-10-10** with economy v6 (every save started over on the `_v2` stores before
  launch; from now on saves are real players' and are never wiped). The Grand Opening runs 46
  days from 2026-10-10 08:15 EDT (`Config.Shop.Deals.GrandOpening.StartsAt`).
- **The work from here** (designer, 2026-10-10): QA, quality of life, bug fixes, new features
  and updates, and a slow cleanup of old code and features as the game takes its form. Every
  update must not bring a critical bug or error to the live game: the rules are in CLAUDE.md,
  "The game is live".
- **Published by the designer 2026-10-26: everything pushed up to `da311fd6`**, checked working
  on the designer's phone (the MATCH RULES card whole and clear of Play Global; the freecam's
  thumbstick on the left half, the look on the right). The 2026-10-25 evening publish was up to
  `e49ef20e`, the lobby boards included, so the country store is counting real wins since then;
  every not-yet-published note below is live with it. **Published by the designer 2026-10-26 (later): everything up to `76eaf0e5`, not yet tried by hand** (the designer will test it later), so the two notes below are live: a raised cue drops its effects only on its shooter's own screen, everyone else sees the skin whole (`887bbd4b`); a 2v2/3v3 turn's cue swaps at once instead of showing the last shooter's cue for 1-2 s (`7c8fe244`, `CueAssets.holdLooks`). Check live in a 2v2 with a friend: raise your cue over a rail, they still see its aura; pass turns, their screen shows each shooter's own cue at once; Creator Hub client memory on phones the day after. **Also live since 2026-10-26: the 2v2/3v3 queue update** (`a81062ef`..`fe7abe16`, ROADMAP "The 2v2/3v3 queue update"): split team pads (TEAM 1 / TEAM 2, the half you stand on is your team, `Queue.Sides`); team pads ask again on each join and every 30 s while short, "<name>'s 2v2 needs 1 more!" (`Queue.TeamPings`); Fill with PC for a short team after 30 s, disguised bots, normal pay (`Bots.Fallback.TeamFill`); new custom events `TeamPad` and `TeamPing` (no team-queue numbers existed before: the first days are the baseline). Check live with friends on a phone, a PC and a pad: step onto each half, walk across, both halves full starts with those teams; the popup's "needs N more" and Join landing on the short half; alone 30 s on a 2v2 pad, Fill with PC starts a game; then read `TeamPad` (how waits end: Started / Global / PcFill / Left) after 2-3 days. Any part misbehaving: set its switch false and publish.
  **Live since 2026-10-26, checks still to do:** **phone
  QoL** (`4ca493c`, `4edd93e`, `6a7e40b`: the left column smaller and nearer the edge on a phone,
  upright too; MATCH RULES with the old level pictures; a small country flag on each match-bar
  portrait; the Settings gear closer to the rank HUD; the freecam keeps a phone's thumbstick);
  the **weekly community codes** (2026-10-26: BREAKSHOT, BANKSHOT, CUEBALL, TRICKSHOT,
  CORNERPOCKET, MASSESHOT, 5 spins each, Live and off; each stops at the end of its Monday-to-Monday
  UTC week; after publishing type `/code on BREAKSHOT`, redeem it once, and post it in the Discord's
  #codes; watch the new `CodeRedeemed` custom event, field = the code); a top player's flag after their name on Top players and yours on its You strip, and no "100+" there off the board
  (`Board_PlayerFlags_v1`; check live: top players' flags appear as they visit a lobby, and one
  who switches Show my country flag off loses it within about two minutes); the **portals ask
  first** (`e498885c`, `Config.Portals.Ask`; check live on a phone, a PC and a pad: stand on the
  Solo pad, the question, No keeps you there, walking off closes it, Yes teleports; read the
  `PortalAsk` custom event after a few days: how many answers are No or WalkedOff); the **1KLIKES
  code** (`0c253c15`: 15 spins + $10,000, the Abilities code box says USE CODE 1KLIKES / NEXT
  CODE AT 2,000 LIKES, the tutorial gives it; 250LIKES works until 2026-10-31 00:00 UTC; check
  live: redeem 1KLIKES once, then again for "already used"); the **server lag fix** (2026-10-25,
  branch `server-lag`: bots think inside one 8 ms budget a server frame, `Config.Bots.Think`,
  and `--!native` on the physics and bot brain; the worst tenth of live servers fell to 8 then
  under 2 FPS at 600-800 players. Studio: 8 bot matches at once, bots play normally, console
  clean. Check live: Creator Hub > Performance > server frame rate P10 at the next evening
  peak, target above 30 (was 1.6-13 on 2026-10-25), and that bots still take their shots;
  F9 must show no "replay drifted" warnings); the **error report fixes** (2026-10-25, DECISIONS: `CameraGuard` ends the frozen-camera loop behind 75K "BaseCamera:682 clamp" errors a day, `Config.Camera.Guard`; the aim stream goes only to loaded players and rests when nobody aims, behind 46K "did you forget to implement OnClientEvent" errors, `Config.Aim.ReadyOnly`, `SkipIdleBroadcasts`; check live: Creator Hub > Error report a day later, both rows near zero and a few "[8ball] CameraGuard" warnings instead; a watched opponent's cue still turns as they aim; the 64-track animation warning is not fixed yet).
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
- **The emote system, merged into `gui-v4` 2026-10-27 (`36cdb4c6`), published 2026-10-27**
  (switch `Config.EmoteMenu.Enabled`; Sync alone `Config.EmoteMenu.Sync.Enabled`): the EMOTE
  button (bottom right, R3) and tray of 13 dances (Popcorn, Rat Dance, Low Cortisol, Sega Walk,
  Bullseye, Gojo Walk, Geto Walk, Passinho, Scenario, Scuba, Rakai, Jackpot, Money) with the
  designer's own song uploads; dances go on while walking (at 16; Gojo/Geto 1.6) until a jump,
  another pick or a reset; Sync prompts on dancers in the lobby (Gojo/Geto pair one to one);
  the results screen without blur or DEFEAT, the losing side greyed. Last checked on the Crazy
  8 Test Place (version 23). **Fixed 2026-10-27, published 2026-10-27 (also on the Crazy 8 Test Place as version 27)**; two together 1.5x, not double (`MusicTwoTogether`)
  (`03896675`..`3bd0aa42`, DECISIONS): Sync in step on every screen (one server clock,
  `EmoteAlign`, `Config.EmoteMenu.Align`); the song from every dancer's body, louder together,
  up to 4 voices (`EmoteMusic`, Audio API); Popcorn and Bullseye stand still, Popcorn's lounger
  turns with shift lock; Gojo/Geto walk 1.72; in a match the EMOTE button shows once your
  stroke has played, and Sync works there on a controller's Y (`Sync.InMatch`). Then: a red
  "!" on the EMOTE button until the first press and "Jump to cancel emote at any time" until
  the first jump (once per player); dancing walk 8; the emotes' sounds as Sound effects'
  second switch (All / Emotes); Bullseye's puffs 70% smaller, half as many, and no emote puff
  on your screen while you shoot. A fresh-player run in Studio (tutorial skip, daily rewards,
  gift, invite) showed the dot and hint with nothing covered on a phone. Checked in
  Studio alone (a dance on the clock within 0.03 s, the song on the clock, Popcorn and
  Bullseye stillness, console clean); **not yet checked with two players**. A server-side
  "ContentId rbxassetid://203785492 failed: Asset type does not match" (a Roblox audio, "Pop
  Close Sound") shows once per Studio session about 0.5 s after the save loads: not in our
  code, the place, the emote or ability models, or the designer's avatar items; it was there
  before the emote fixes. Still open. **Live without
  its 2-player test, still to do on the live game:** a 2-player test (Studio Test > Clients and Servers, or two accounts on
  the test place): Sync, both screens in step, the song from both bodies; a match: the button
  after your stroke; a phone and a controller (Y in a match); the fan clip on Sega Walk and the
  uploaded songs are the designer's risk (they can be taken down: the dance then goes silent).
- **The 2KLIKES code, published 2026-10-27 (`d9c6175e`):** 15 spins + $20,000, the
  Abilities code box and the tutorial name it (USE CODE 2KLIKES / NEXT CODE AT 5,000 LIKES);
  1KLIKES works until 2026-11-01 00:00 UTC, 250LIKES until 2026-10-31 00:00 UTC. **The game
  description changes only once this is live** (top lines: THANK YOU FOR 2000 LIKES! / USE
  CODE "2KLIKES" FOR 15 FREE ABILITY SPINS + $20K CASH! / NEXT CODE AT 5000 LIKES! / Still
  working codes: 1KLIKES, 250LIKES). Check live: redeem 2KLIKES once, then again for "already
  used"; watch `CodeRedeemed` (field 2KLIKES). At 2,791 likes and ~900 a day on 2026-10-27.
- **No result cutscene after a 1v1, published 2026-10-27 (`7ad43dad`):** a 1v1's
  result screen opens at once like a 2v2's (no fade to black, no camera tilt from the sky;
  `Config.Cutscenes.Result.Enabled` false, true brings it back). New custom event
  `ResultChoice` (`16310059`): value the seconds from the result to the answer, fields the mode,
  the answer (Rematch, Decline, WalkedOff, Lobby, Another) and the device; nothing measured
  this before, so 2v2 (never had the cutscene) is the comparison. Checked in Studio: a 1v1
  surrender and the tutorial's first match (fresh player) open the result at once, Rematch and
  Leave log the event, console clean. Check live: finish a 1v1 on a phone, a PC and a pad.
- **Waiting to publish (pushed 2026-10-28, up to `b7e5050f`): the emote audio update.**
  Emote sounds heard 30% nearer (songs full to 8.4 studs, silent from 49, were 12 / 70;
  Popcorn's and Bullseye's sounds 7 / 42, were 10 / 60); every emote sound 18% quieter
  (`Loudness` 0.45, was 0.55); Popcorn's crunch about twice as loud as heard (Munch 0.17);
  Passinho 4th in the menu and Sega Walk 8th. **The Avatar Shop link fixed**: Roblox blocked
  the buy prompt for another creator's item ("AllowThirdPartySales has blocked the purchase
  prompt"), so Allow Third Party Sales is on in the place (Workspace; Game Settings >
  Security), a place setting that ships with the publish; Studio play tests still show the
  block (a Studio quirk). Bird Brain was added and then removed (designer, 2026-10-28): none of
  it is in the build, and the emote code is the live game's again. Checked in Studio: 13
  cards in the new order, Passinho's song at 0.35, a jump ends it, console clean. Check
  live: Avatar Shop on an emote opens Roblox's buy popup; the songs quieter and heard about a
  table away; Popcorn's crunch heard.
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
