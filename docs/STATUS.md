# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-12. **The game is live** (officially released 2026-10-10). Work goes on
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
- **Published:** the 2026-10-11 publish (about 5:15 AM EDT) has everything up to `1a2b25c`
  (Like + Favorite with one Verify, emotes, "Just one more game?", the onboarding fixes), and
  servers were restarted. **Not yet published:** Settings' "Camera after a shot" (below), unbox announcements
  without their "(1 in N)", "Gonna let that slide?" wiggling over Rematch for the side that lost,
  **the new rank ladder** (below; needs "Restart Servers for Updates"), **the owner admin
  panel** (below: announcements now type out on screen only, money rain has This server / All
  servers), **Sell Duplicate / Keep on a duplicate's reveal card**, **the controller fixes**
  and **the tutorial batch of 2026-10-12** (both below) and **the VIP tag shut in a match**.
  All pushed up to the docs commit after `f99de00`.
- **Now (designer, 2026-10-11):** fixing console (gamepad) controls for this update, from the
  designer's own tutorial run on a controller. Done: the 8's pocket by D-pad rows, the tutorial's
  D-pad fine aim, a Mystery held out and opened with R2, the Mystery screen's A button, the
  D-pad picture lighting each way (below). The designer lists the next ones; check each with
  gamepad emulation in Studio, touch and mouse unchanged (CLAUDE.md).
- **Lint and tests (2026-10-12, `gui-v4`):** lint OK (four old LocalShadow warnings); all 1229
  Lune tests pass.

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

- **Controller fixes** (2026-10-11, DECISIONS): the 8's call by D-pad rows (starts top left, the
  tutorial's on its pocket; the lit pocket gold, glowing, its ring bigger and breathing), the
  combination turn's "Fine-tune your aim" line, a Mystery held with LB / RB and opened with R2
  (white burst; `Config.LuckyBlocks.PadHoldMystery`). Checked in Studio with the controller
  forced (QA presses) and a tutorial run from Arrow on path S. Live: a real controller (Xbox
  and PlayStation glyphs), the burst's look from the player's own camera, others seeing a
  Mystery in someone's hands, the designer's look at the lit pocket.

- **The tutorial batch** (2026-10-12, DECISIONS): the aim lesson's "zoom all the way in" part
  (waits until closer than the default view), a {DPad} picture lighting each way, the Mystery
  screen's A button on a controller, and the quest "Now go win a match! 0/1" ending in "Have
  fun!" with the chime and **$2,500** flying into the money HUD (`Config.Tutorial.Soft.QuestReward`).
  Checked in Studio on PC: the zoom-in part, the quest's words, the reward paid once (a second
  claim refused), a quest owed from elsewhere finishing on rejoin, a fresh join at Arrow. Live:
  the reward's money in the logs (TutorialQuest), a phone's spread-fingers hand, the quest line
  on a narrow phone, the chime by ear.
- **The VIP tag in a match** (2026-10-12, DECISIONS): hover and press do nothing in a match.
  Checked in Studio (the tag shut in a QA match, live in the lobby). Live: a phone dragging
  the camera over the tag.

- **Sell Duplicate / Keep on a duplicate's reveal card** (2026-10-11, DECISIONS;
  `Config.BlockOdds.DuplicateChoice`): checked in Studio on PC through the real reveal screen
  (buttons, Escape keeps, Sell sold the copy for $200). Live: a real pull's Sell on a phone and
  with a gamepad, the money flying into the HUD, Common duplicates now kept unless sold.

- **The owner admin panel** (2026-10-11, DECISIONS; `Config.Admin.Enabled`): ADMIN bottom right,
  Painicane only. Checked in Studio on PC: announcements (on screen only), Give/Drop/Backspace drops
  and pickup, ability and money by part of a name, money rain (standing icons, amounts,
  sparkles, same floor only, 60 s life, CashLand on pickup). Announcements now open with a white
  streak and a button pop, then type out with the designer's keyboard click, just
  under the Sky Lucky Block timer. Live: an all-servers message, the text filter, a second player
  picking up drops and bills, a phone (button above the jump), the click's loudness, an
  All servers money rain (it falls round each other lobby's spawn).

- **The new rank ladder** (2026-10-11, ECONOMY 2, DECISIONS): fast to Gold, then each tier about
  twice the last; from Expert Classic wins fade (x0.5 down to x0.25) and Difficult x1.5 /
  Challenger x2 carry the climb (Reyes about a year on Challenger at an hour a day). Until the
  difficulty picker returns every match is Classic, so Expert and up climb slowly. Saves catch up
  as they load (about 1,110 of 4,112 move up, NEW RANK! says why, rewards claimed in Rank).
  Checked in Studio on PC (an old save caught up and claimed, a fresh first win, a normal
  rank-up, Expert 1's "28 WINS TO EXPERT 2!" at 50 XP a Classic win). Watch live: the `rank
  catch-up` server lines, claims, a phone and a controller on the popup, win rates against bots
  from Gold up (bots now meet players sooner).
- **Onboarding** (2026-10-10): game 1 lost or quick-won goes on to the chain; the Daily
  Rewards and invite popups after the first match (skippers at once); the Gift drop over a
  closing menu. Check with a brand-new account once published (recipes: STUDIO_NOTES "Real
  shots through PoolMatchQA" and the last DECISIONS lines).
- **"Just one more game?" over Roblox's menu** (2026-10-10, DECISIONS): checked in Studio
  with the designer on PC (1722 x 814) and the phone emulator, with the Gift falling behind
  the menu. Open: a real tablet and phone (the panel's place is worked out, not read), a
  controller's Start.
- **Like + Favorite** (2026-10-11, DECISIONS): one Verify on the Free Reward card (the
  Favorite button went: Verify opens the favorite prompt itself),
  the "ALMOST THERE!" popup (concept A), the reward after a rejoin ($5,000 + Lucky 8 +
  Mystery). Checked in Studio on PC through the real buttons (GuiQA `pressButton`): the
  not-favorited path (now Roblox's favorite prompt, then the notice if closed), the popup, Later, closing the menu over it, Leave & Like sending the
  player out, the flag kept over the rejoin. Open: the designer's look at the popup, a phone
  and a controller. Off switch: `Config.Social.LikeRejoin`.
- **Camera after a shot** (2026-10-11, DECISIONS): a Settings switch, blue TOP (default) or
  gold PLAYER; PLAYER hands the player their own Roblox camera and body once the stroke has
  played, until their next turn (never in the guided tutorial). Checked in Studio on PC: the
  row both ways; PLAYER on a break (Roblox's camera, walking, the table view back next turn);
  TOP unchanged. Open: a real stroke (QA shots skip it), a phone and a controller.
- **Emotes** (2026-10-11, DECISIONS): the wheel's empty slots are filled on each spawn, so it
  no longer says "disabled". Checked in Studio (join, respawn, an emote playing). Watch:
  emoting at a table (the shooter's pose is ours), on a phone and a controller. Off switch:
  `Config.Emotes.FillEmptySlots`.
- **Solo and Practice portals**: a real teleport on the live game.
- **Launch review leftovers:** server CPU per shot (MicroProfiler live), "+10% Permanent" group wording, the day 7 cue not in the claim flyer, the
  Sky ping trusts the client. Roblox shows products at about 0.8x their price (regional
  pricing or price optimization). Server size 24 in the Creator Dashboard.
- **The funnels** in the Creator Dashboard (roadmap 8.2; `docs/TUTORIAL_FUNNELS.md`): where
  new players quit.

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
