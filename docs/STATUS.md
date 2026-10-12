# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-12 (evening, the QA batch). **The game is live** (officially released 2026-10-10). Work goes on
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
- **Published:** the 2026-10-12 publish has everything up to `c499ecf`: the new rank ladder,
  the owner admin panel, Sell Duplicate / Keep, Settings' "Camera after a shot", unbox
  announcements without "(1 in N)", "Gonna let that slide?", the controller fixes, the
  tutorial batch (zoom-in lesson, the quest's $2,500 reward), the VIP tag shut in a match,
  Portals lasting 2 shots and the pad queuing you again 1.5 s after a match. The rank ladder
  needs "Restart Servers for Updates" (the designer was reminded). **Not yet published:**
  the Shop restock's "Epic or better!" tag removed (DECISIONS).
- **Now (2026-10-12): a tester's QA batch, committed on `gui-v4`, NOT pushed.** The designer
  relayed a friend's 8 notes (DECISIONS 2026-10-12); each fix is its own commit, held until the
  designer approves the test page (Artifact "Oct 12 Fixes Checklist"): OPPONENT'S TURN held
  (`29d9a02`), replay catch-up (`9849fb6`), tutorial game 1 shorter (break streak x1-x3
  `c1e3f67`, the bot's accidents `9eeada5`, a three-solid break `7b5a192`), ability info
  (`b6ce19f`), pocket arrows (`5eb2f81`), the lighter chain after game 1 (`2d8e830`), Ranked
  width and long ability names (`4cb6f9b`, `e059e70`), lobby bots back (`3f7602c`). No save
  change. After approval: push, the designer publishes (Restart Servers optional), then watch a
  new account's tutorial, a lobby filling with bots and a phone match live.
- **Lint and tests (2026-10-12 evening, `gui-v4`):** lint OK (four old LocalShadow warnings);
  all 1243 Lune tests pass.

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

- **Controller fixes** (2026-10-11): the 8's call by D-pad rows, a Mystery opened with R2; a
  real Xbox and PlayStation pad.
- **The tutorial batch** (2026-10-12): the zoom-in part, the quest's $2,500 (TutorialQuest
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
- **Onboarding** (2026-10-10), **"Just one more game?"**, **Like + Favorite**
  (`Config.Social.LikeRejoin`), **Camera after a shot**, **Emotes**
  (`Config.Emotes.FillEmptySlots`): a brand-new account, a phone and a controller.
- **Solo and Practice portals**: a real teleport. **Launch leftovers:** server CPU per shot,
  "+10% Permanent" wording, the day 7 cue flyer, the Sky ping trusting the client, products at
  about 0.8x price, server size 24. **The funnels** (`docs/TUTORIAL_FUNNELS.md`).

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
