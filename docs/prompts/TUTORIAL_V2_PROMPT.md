# Tutorial v2: the first session, rebuilt (an attended nonstop run)

Written 2026-10-09 by the designer (Justin, Roblox name Painicane) with Claude, after an
interview. You are a Claude Code session in the worktree `~/Desktop/8ball-tutorial` (branch
`tutorial-v2`). You will:

1. read how the first session works today,
2. research briefly, then design and **simulate** the new tutorial with agents,
3. show the designer one plan page and wait for "approved" (the only planned stop),
4. build it, nonstop, step by step (the Progress list at the end),
5. make it bug-proof, test it in Studio and on the test place,
6. write the report. Merging back into `~/Desktop/8ball` happens only when the designer says
   (section 10).

The designer: "this tutorial is very important and crucial to the success of the game, so it's
important to make sure each funnel is measured and tracked, the game feels intuitive and
there's no bugs in the tutorial." And: "if the tutorial bugs then people leave and that's a
huge problem, so pay extra care." **Quality and zero bugs come before speed.**

The designer is a beginner. Explain every question, click and decision in plain words.

---

## 0. Where you work, and what you never touch

- **Your folder:** `~/Desktop/8ball-tutorial`, a git worktree on branch `tutorial-v2`, made on
  2026-10-09 from `gui-v4` (commit 19d27d4) by the session that wrote this brief. This brief and
  the Stop hook `tools/overnight/tutorial_v2.json` are in it, uncommitted; Step 0 commits them.
- **Your Rojo port is 34877.** Your Studio window opens the local file
  `place/lane-tutorial.rbxl` (git-ignored by `place/lane-*.rbxl`).
- **The designer works in `~/Desktop/8ball` at the same time** (their own Studio window on the
  Team Create place, Rojo 34872, and maybe other Claude or Codex sessions).
  - That folder is **read-only** for you until the merge. Read any file there, or use
    `git -C ~/Desktop/8ball show <commit>:<path>`.
  - Never edit, create, stage, stash, reset, check out or commit anything there. Never run
    scripts there that write files (`tools/economy_model.py` rewrites
    `tools/economy_config.json`).
  - Never connect anything to Rojo 34872.
  - **Never touch the designer's Studio window through MCP.** Before every Studio session, call
    `list_roblox_studios`, take the window whose place is `lane-tutorial.rbxl` (later also the
    test place copy), and pass that id to every Studio call. If you can't tell which window is
    yours, stop and ask. To close your window: `kill -9` the pid that matches
    `-localPlaceFile <your file>` only (STUDIO_NOTES).
- **Leave alone:** `~/Desktop/8ball-abilities`, `~/Desktop/8ball-gui-v3`,
  `~/Desktop/8ball-lane-backup`, and every `~/Desktop/8ball-refs/` folder except `tutorial/`.
- **Where you write:**
  - code and docs: only in this worktree;
  - research, simulation output, the plan page: `~/Desktop/8ball-refs/tutorial/`.
- **Git:** commit and push only `tutorial-v2`. Never push or change `main`, `release`, `gui-v4`
  or any other branch, and never force-push.
- **Publishing:** never publish to the real game (Crazy 8 Ball, place 107430170196919). The
  designer's test place is yours to publish to as often as you need: **Crazy 8 Test Place**,
  place `75362358216917`, universe `10769973956`, owned by the group 675425213, private.
- **Robux products:** never create, change or reprice a product. The new VIP / Starter Pack
  tile uses the products that exist.
- **Uploads:** images are allowed through `tools/roblox_upload.py` (group 675425213, dry-run
  first; read its STUDIO_NOTES section). Audio minds the monthly quota. The API key is in the
  macOS Keychain (`ROBLOX_API_KEY`): never print, echo, log or write it.
- **Economy numbers may change before the merge** (an economy v5 is likely). Read every price,
  reward, timer and amount from `Config`. Never write a number into a string or a comment that
  would go stale; use placeholders in `Strings`.
- **Asking a question:** in a worktree `.git` is a file, so the Stop hook's marker goes in the
  real git dir: `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`, then ask one
  short, clear question and stop. The hook lets that stop through.

---

## 1. How the run goes

1. **Setup, reading, short research** (Progress steps 0-2).
2. **Design and simulate with agents** (step 3, section 5). Use the Agent tool for parallel
   work (layout search, new-player simulation, server-size model, research, fresh-eyes UX and
   code reviews). The designer asked for agents and simulated scenarios ("make agents or
   whatever necessary to make this tutorial feel just right, run scenarios and simulated
   models"); multi-agent workflows are allowed too.
3. **The plan page, then stop** (section 9). Wait for "approved". Revise in rounds if asked.
4. **After "approved": build nonstop.** Follow the Progress list. Commit and push `tutorial-v2`
   after each verified step (lint, tests, Studio check), tick the box in this file, and keep
   going.
   - Stop to ask only when you truly can't decide at full quality, or need access or a click
     only the designer can make.
   - Otherwise decide as the designer would (past decisions in `docs/DECISIONS.md`, the UI
     style, what is simpler and more pleasing for a Roblox kid). Log each such call as a
     "(run assumption)" line in `docs/DECISIONS.md` and in your Notes, then continue. The
     designer: "when in doubt just continue."
5. **The design in section 4 is the spec.** You may propose changes that make the tutorial
   more intuitive or simpler ("you are free to change things around if it makes it more
   intuitive and simpler, but get my approval first"). Put them on the plan page, or ask after
   the stop. Never change the design silently.

---

## 2. Read first

- `CLAUDE.md` (the house rules apply here; "commit as soon as a step is verified" means on
  `tutorial-v2`).
- `docs/STATUS.md`, `docs/ARCHITECTURE.md`, `docs/UI_STYLE.md`.
- `docs/GDD.md` sections 5 (controls, camera), 6 (modes, tables, joining), 9 (abilities),
  11 (ranks), 12 (economy, lucky blocks) and **14 (the tutorial today)**.
- `.claude/skills/lively-gui/SKILL.md` before any screen, popup, icon or HUD work.
- `docs/STUDIO_NOTES.md`, especially: a second Studio window for a worktree, testing against a
  bot (`BotsQA`, `UltQA`), `execute_luau` runs in its own VM (drive the game through
  `ServerStorage.DevCommandsQA`, `ServerStorage.TutorialQA`, `PlayerScripts.GuiQA` and the
  client QA hooks), and "Bugs that only happen live: fake the lag".
- `docs/MULTIPLAYER_TESTING.md` (partly out of date).
- `docs/DECISIONS.md`: the last two weeks; grep tutorial, Play Global, spawn pill, win track,
  Free Reward, Fire Shot, Mystery, rank claim.
- `docs/prompts/TUTORIAL_PROMPT.md`: the first tutorial's brief (history; this brief wins).
- `docs/parallel/tutorial.md`: mostly out of date. Trust only its decisions log (about lines
  419-479) and its list of edits in other files (about lines 294-384).
- `~/Desktop/8ball-refs/tutorial/`:
  - `01-pointer-hand-cursor.png`: the hand's style (already drawn as our own).
  - `02-arrow-trail-to-target-and-banner.png`: the old floor arrow's reference (replaced by the
    new arrow in 4.3).
  - `03-current-break-pull-lesson-keep.webp`: today's break lesson. **The designer likes this
    dim and the pulling hand: keep that look.**
  - `04-ability-ready-press-g-aim-view.webp`: the aim view with the ability ready ("PRESS G
    TO ACTIVATE"), the guideline and the top ball bar.
- Appendix A (the designer's own words) and Appendix B (the interview answers) of this brief.

---

## 3. The first session today (code map of 2026-10-09; check it, the code wins)

**Modules.** Server `src/server/TutorialService.luau` (step machine, resume, chain hooks,
nudges, `/tutorial`), `src/server/TutorialGames.luau` (table reservation, game 1 lessons, game
2). Shared `src/shared/Tutorial/` (`Steps`, `Break`, `Rig`, `RankClaim`). Client
`src/client/Tutorial.luau` (controller, run every frame), `TutorialOverlay` (top text, dim with
a lit hole, Skip + Yes/No), `TutorialHand` (point, pull, hold, swipe, stick, drag),
`TutorialArrow` (flat floor arrows, PathfindingService, 60 parts, replans every 3 s),
`TutorialAnchors` (where screens register buttons; the hidden set). Hooks in other files:
`Ranking.setBlockKind`, `LuckyBlockService.setOpenHooks`, `Items.setEquipHook`,
`UltSpins.setSpinHooks`, `Rewards.onRedeemed`, `TableService.setRequestFilter`,
`BotService.setFallbackWait`, `GiftDropService` (waits), `RankClaimService`; started from
`Bootstrap.server.luau`. Numbers in `Config.Tutorial`, words in `Strings.Tutorial`.

**Steps today:** Arrow1 → Request → Game1 → Block → Equip → RareBlock → Abilities → Spin → Code
→ Back → Arrow2 → Queue → Game2 → Lobby → Nudges → Done (plus Skipped, Cancelled). Saved in
`Flags.Tutorial` through `PlayerData.setFlag` (any string up to a length is accepted, no check).
Save version 10.

**Live bugs and dead code found (fix or replace them):**
- **The tutorial dies right after game 1's win.** `TutorialGames.luau` (about line 373) sets
  the step `"Drop"`, a name from the case days that is no longer in `Steps.Order`. All
  guidance disappears, the forced Uncommon cue is lost, funnel steps 11-17 never fire, and a
  save holding `"Drop"` stays stuck. Old names (`Drop`, `RareDrop`, ...) may sit in saves.
- The funnel step `ClaimedDaily` is never logged.
- The `TutorialActive` attribute and the `TutorialCue` remote have no consumers;
  `TutorialCalling` is set but never read.
- The spin lands on Fire Shot, which every player already has. Heat Seeker is gone, so the
  "Pick" lesson never shows.
- Stale comments: `Steps.luau` ("press Request opponent", "1 h timer"), the `TutorialAnchors`
  header, `Rig.luau` (`bot =`), `Config.Tutorial` ("from Request opponent"), and
  `Config.Guideline.TutorialStubLengthInches` ("Not wired yet": it is wired).

**Facts that shape the design:**
- **Tables:** 16, but only **10 are 1v1** (tables 1-8, 11, 12). Tables 9, 10, 13, 14 are 2v2;
  15 and 16 are 3v3. One pad per table; standing on it joins (`TableService.onPad`). The host
  card is gone (2026-10-07). Lobby bots are off by default (2026-10-07).
- **Server size** is a Creator Hub setting (not in code); the designer set about 30.
- **The tutorial bot today** appears on the pad 2 s after the player steps on
  (`BotService.tutorialBot`, `joinTable`, `Config.Bots.Tutorial`), anchored, never walking. It
  leaves 0.25 s after the winning 8 ("AUGHHHH!", jump, gone), before the result screen.
  `LobbyBots.walkTo` (PathfindingService + `MoveTo`) and `BotService.walkIn` show how bots
  walk. Looks come from `Bots/Identity` (random real styled avatars, made-up names, 6 kept
  ready). Bots use the stock R15 animations, with no look-around or turning.
- **The rigged break today:** rack seed 153, cue ball at (-25, -6), angle 0.115, power 1
  (`Config.Tutorial.Break`), found by `tools/tutorial_break.luau` (seeds x offsets x turns), it
  pots 3 solids. `Tutorial/Break.play` copies the server's shot path exactly. Tests:
  `tests/tutorial_game_test.luau`, `tutorial_steps_test.luau`, `tutorial_rankclaim_test.luau`.
- **Hidden help today:** `Rig.assist` arms the real Magnet effect, invisibly
  (`Hidden = true`), on the player's own first-hit ball (and on the 8 toward the called pocket),
  game 1 only. Long guideline in game 1: `TutorialStubLengthInches` 16 (normal 7). No shot clock
  in game 1 (`Rig.timed`). The 8 guard (`Rig.judge`, "EightBack") makes losing on the 8
  impossible.
- **The tutorial bot's shots:** `Bots/Script` (`pot`, `scratch`, `poor`, `tutorialView`),
  `Bots/ShotFinder`, `Bots/Driver`. Normal bots: `Bots/Brain` (make chance, near misses
  0.7-3.2 degrees off).
- **Controls** (`src/client/Input.luau`, `PowerCue.luau`, `PullGesture.luau`, `Config.Input`):
  - PC: drag to aim, wheel to zoom, pull the bar on the right and release.
  - Touch: swipe to aim, pinch to zoom, the bar with a 24 px dead zone.
  - Gamepad: left stick aims, D-pad fine-aims, right stick zooms, **hold A to fill the bar
    (full in about 0.9 s), release to shoot**. R2 is unbound. X is the ability, B is leave.
    Spin and cue angle are on L1. Ball in hand is hold L2 + left stick. `PadGuide.luau` is the
    on-screen control strip.
  - The ability: G on a keyboard, tap the bar on a phone, X on a gamepad (`UltHud`, `UltBar`).
- **Camera** (`src/client/Camera.luau`, `Config.Camera`): one orbit view. Home zoom 0.625 sits
  behind the cue ball looking along the aim; only fully zoomed out (1.0) is sure to show the
  whole table. Phones start one notch closer. So a pocket beside or behind the cue ball can be
  off screen: that is what the zoom lesson uses.
- **Fire Shot** is everyone's starter (`Config.Ults.Default`): 2x cue speed, and its orange
  "full lines" run on to the next cushion, ball or pocket (`Physics/Aim.fullLines`).
- **Match HUD:** 20 s aim clock, YOU ARE SOLIDS/STRIPES (3.5 s), your group pulses green,
  the top bar of balls, NICE SHOT! for banks, kicks, combos and caroms (`Rules/NiceShot`), never
  on the break. **There is no "x2" callout in a match** (only the pocket sound rises).
- **Rewards:** the first win ever gives a Rare block on a 5-minute timer. Bronze gives $2,500,
  1 Mystery block (paid at once today, `BlocksAtOnce`) and the Bronze Cue (an Uncommon rank
  cue, `Progression/Catalog`). Every other rank reward waits until claimed in Rank
  (`RankClaimService`, `RankClaimBlock`, the `RankPending` attribute).
- **Lucky blocks:** hotbar `LuckyHotbar`, throw and open `LuckyClient` / `LuckyWorld` (0.5 s
  hold, E or gamepad X), `LuckyOpening`, `BlockReel` (the spin is 4.2 s; **no pause before it
  spins**: only a 0.15 s blur lead and a 0.04 s card stagger), `MysteryReveal` (the Mystery
  block's 4-press upgrade screen), server `LuckyBlockService` (`setOpenHooks`).
- **Abilities:** 1 starter spin today (`Config.Ults.Earn.Starter`), the code RELEASE = 3 spins
  (`Config.Ults.CodeBanner.ActiveCode`; the code box is on the Abilities screen and in
  Settings). A spin replaces the selected slot.
- **Play Global** (`src/server/GlobalQueue.luau`, `src/shared/Matchmaking/`,
  `src/client/MatchBar.luau`, `SoloSearch.luau`): **every match teleports** to a reserved arena
  server, even two players from the same lobby. The rank gap widens 1 / 3 / 6 divisions /
  anyone over 0-3 / 3-6 / 6-10 / 10+ s. The bot fallback comes after 5 s for 1v1 (25 s for
  teams), in an arena. The tutorial's game 2 cuts it to 1 s. Play Global shows on a pad at once;
  the spawn pill offers it to a player alone in a server.
- **HUD:** left column SHOP, CUES, ABILITIES, FREE REWARD (`MenuColumn`); the rank HUD top left
  (`Progression`); on the right edge `HubCorners`: Daily Challenge (a button that says "Soon")
  and **VIP and Starter Pack as two separate tiles**; the win track over the hotbar
  (`WinTrack`, hidden during the tutorial); the Free Reward menu (`FreeRewardMenu`, Daily /
  Playtime / Track / Group; `FreeSocial` holds group, favorite and like). There is **no quest
  system**.
- **Invites** (`InvitePrompt`, server `Social`): a Rare block for both when the invited friend
  wins their first non-solo match (inviter capped, paid once).
- **Funnels** (`src/server/Funnel.luau`): the onboarding funnel (22 steps), `TutorialExit`,
  Shop, Block, AbilitySpins, plus custom events (`TutorialLeft`, `TutorialBotScratch`,
  `TutorialBallInHand`, `TutorialLostGame2`). Roblox allows **10 funnels per game** (up to 100
  steps each) and **3 custom fields** (8,000 combined values; breakdowns use the first step's
  fields). Check the current limits in the Roblox docs before designing.
- **Offline physics:** pure Luau, fixed 1/240 s step, deterministic. A break takes about 50 ms
  in Lune (`/opt/homebrew/bin/lune`). `Simulation.newState`, `run`, `runHeadless`,
  `strike`/`settle`, `armEffect` (abilities); shots are `{angle, power, spin, elevation,
  ability}`. Table 100 x 50 in, origin at the centre, +x toward the foot rail; head spot
  (-25, 0), foot spot (+25, 0); pockets 1-6; `Rack.newGame(geometry, seed)` with 0.001 in
  seeded jitter.

---

## 4. The design (the designer's decisions; the spec)

### 4.1 Principles (the designer's words, kept)

- **One thing at a time:** the pointing hand, a light dim (not too dark) and, where it helps,
  large text telling them what to do.
- **Agency:** the player should feel the tutorial never restricts their control, even though it
  is rigged to make them feel rewarded (which they must never notice).
- **Learn by playing, not by being taught:** set up the situation so the action becomes
  necessary, then name the control. Example: line the shot up so a zoom-out is needed to see
  where the ball goes, so they know to zoom out.
- **Barely any waiting:** they should always be doing something. No gap over about 2 s without
  an action or a reward moment (balls rolling aside).
- **Natural:** the bot looks and moves like a real player who came to play.
- **Bug-free** (section 7).

### 4.2 Who gets what

- **Everything happens in the real public server they join.** Never a separate place or a fake
  bot lobby; no extra loading screens for the tutorial.
- **Path S, the rigged game:** whoever sits down **alone** at an empty table before their first
  win gets the rigged game against the tutorial bot.
- **Path R, a fair game:** if they sit with a real person, or a friend (or anyone) joins their
  table before the bot game starts, it is a normal fair game: no rigging, no hidden help. Only
  the rigged game ends, not the teaching. There is no need to detect how someone joined (a
  friend who sits alone still gets the bot game).
- **A friend who shows up after the bot game started:** finish the bot game first.
- **Losing a fair first game:** the next time they sit alone, still without a win, they get the
  rigged bot game. Everyone gets the first-win moment and its reward chain.
- **Two kinds of teaching:**
  - **Pool controls** (aim, power, zoom, ball in hand, choosing the 8's pocket): taught in their
    first game, whoever it is against. Turned off if they skip.
  - **Things only our game has** (the ability bar, ranking up and claiming, throwing and opening
    a lucky block and the Mystery upgrade, equipping a cue, ability spins, the RELEASE code):
    each one shows **the first time it happens, for everyone** (skippers and fair games
    included), **once each, saved so it never repeats**. On path S they come as the guided
    chain after game 1 (4.5); for everyone else as first-time hints (4.8).

### 4.3 Joining game 1: the arrow, any table, the bot walking in

**On join:** none of the menu icons show yet (they appear one by one in the chain, 4.5). The
small **Skip tutorial** button sits top right.

**The new arrow** (the designer: "WAY more noticeable"):
- White with a thick black outline, bigger, and **not on the ground**: it comes from the
  player's body (chest or waist height), not their feet, and runs to the table's pad.
- Smoother when it follows them: the start stays attached to the body every frame; the route
  round tables is re-planned smoothly (eased curves, no popping or jumping).
- It ends over the pad with a clear arrowhead and a pulsing ring. When the pad is off screen, a
  small arrow at the screen edge points the way too.
- It must read well on a phone. Suggested build (your call): camera-facing Beams through the
  path's points with an outlined chevron texture scrolling toward the table; or reused parts.
  No new Instances every frame. Show two looks as screenshots on the plan page.

**Any empty table:**
- The arrow points to the nearest empty 1v1 table, but stepping onto **any** empty table makes
  that the tutorial table. Picking a different one must never cancel the tutorial.
- Team tables count if the game can play a 1v1 on them; check, and propose on the plan page if
  it can't.
- Stepping onto a table where a real person waits alone is path R.
- The server must always have empty tables for new players (4.12).

**The bot (the "real player" who comes to play):**
- It is loaded as soon as the player joins (or kept warm before): avatar, name, rank badge.
  It waits **out of the player's sight** near the table they will most likely pick. The player
  must **never see it pop in**. The client reports its camera to the server so the server knows
  what is out of view; prefer spots out of every player's view.
- As the player heads for a table (judge it from distance and heading), the bot starts walking
  to the same table, timed so it steps onto the pad **0.5-2 s after the player**. **The player
  never waits more than 2 s.** If they switch tables, the bot re-routes. If it can't make it in
  time, it may move closer while out of sight.
- It comes from outside the player's view when possible (from behind or the side), "as if a
  real player wants to play against them."
- **Natural movement, never robotic:**
  - small stop-and-go and slight twitches forward;
  - a path that is not perfectly straight;
  - random look-arounds and turns, like shift-lock;
  - the odd jump (Roblox players jump);
  - it looks at the table or the player as it arrives;
  - idle fidgets while waiting.
  Everyone in the server sees the same bot. It is in the player list from the moment it
  appears.
- When it steps on, the match starts like any table's.
- If the player walks off the pad before the bot arrives, the bot waits near the table like a
  person would and steps on when they come back.

### 4.4 Game 1, the rigged match (path S)

**Looks like a normal game:** YOU ARE SOLIDS/STRIPES, your balls pulse green, the top bar, the
20-second clock and NICE SHOT! all show as usual. The long tutorial guideline stays for all of
game 1, as today.
- **The clock** pauses while a lesson prompt is on screen. If it runs out, the turn passes as
  normal.
- **AFK:** if the player is away for 2 turns, the clock stops and the prompt pulses.

**The break:**
- It starts like every other game: the cue ball straight in line with the head ball of the
  rack, aimed straight up the table. Not today's odd offset and angle.
- Aim and the ball's spot are locked for the break.
- **Keep today's look** (ref 03): the light dim, the hand pulling the bar, "Pull the power bar
  all the way down!". The text matches the device (4.10 for the controller).
- A release under half power does nothing: the bar springs back and the text shakes. Half or
  more plays the rigged full break.
- **Exactly 2 balls go in, both solids. The second one creeps in very slowly**, hanging at the
  pocket's edge before it drops ("to edge the player"). No stripe, no 8, no scratch. Today's
  break pots 3; this one pots 2.
- The rack must look normal. Invisible differences are allowed (a tiny rack jitter, the cue
  ball a hair off centre, a fraction of a degree of angle). Define "invisible" and stay under it.

**The 8:** the break leaves it somewhere carefully chosen: away from traffic, so it won't be
potted by accident, yet an easy pot once the game ends, whatever happens in between (near a
corner with a clear line). If it gets moved, the bot's misses may nudge it back (exists).

**Turn 2: aim and zoom** (the ball almost everyone will hit):
- The target solid sits close to a pocket. The aim opens a few degrees off it, so it needs only
  a small adjustment.
- First: "adjust the angle", with the device's gesture (PC drag, phone swipe, controller left
  stick).
- The cue ball is placed so that, at the home view, the pocket is hard to see. The light dim
  then says to zoom out to see the angle better (wheel, pinch or right stick), and **the target
  pocket glows**. Once they have zoomed out: "you can zoom in and out" (a short line).
- **This shot should go in for almost everyone** (target: 90% or more of simulated new
  players).
- **The ricochet:** after the pot, the cue ball comes back off a cushion and knocks another of
  their solids in. It must look coincidental. That gives NICE SHOT! and the new "x2!" (4.11).
  Target: 80% or more of the players who pot the first ball. The hidden help may bend the cue
  ball's path slightly after the first pot, invisibly, if the layout alone can't reach that.

**Turn 3: the ability:**
- The next shot opens lined up so it's relatively easy (the aim starts near the nearest solid;
  they are free to change it).
- Their bar is full: "Press G to use your ability!" (phone: tap it; controller: X), with the
  hand on the bar (ref 04).
- **Fire Shot is the default ability for all players.** Its long orange lines run to the edge
  of the table, so this shot should show why it helps: **the cue ball close to one of their
  balls, and that ball far from a corner or side pocket**. With Fire Shot's line they see it
  run all the way in. This should go in for almost everyone.

**Turn 4 and on: their own:**
- The next shot is a bit harder: not impossible, but the hope is they miss once, it being their
  first time.
- **Their first miss gives the bot its scripted visit.** The bot pots one of its own; on its
  next shot it pots a second one **and scratches** (the cue ball goes in). That teaches ball in
  hand: the hand and the light dim show they can move the white ball anywhere (controller:
  hold L2 + left stick).
- If they never miss, there is no bot visit, and ball in hand becomes a first-time hint in a
  later game.
- **The rest of their balls are easy to pocket**, so the game ends fast and they get to the
  other steps.
- **Every later bot visit** (designer's pick A): the bot never pots again. About half its
  misses are near misses (rattling in the jaws). Every miss leaves the player a makeable shot,
  close and good but never obviously gifted.
- **The 8:** "SELECT WHICH POCKET!" (exists), with the right pocket (the 8 already sits by it)
  glowing and the hand on it. Every pocket stays clickable.
- **They can never lose game 1.** An early 8, a scratch on the 8 or a wrong pocket puts the 8
  back where it was before the shot (it was already in an easy spot) as a plain foul. The
  designer said "back into the center"; the 2026-10-09 call is "where it was". The simulations
  should show this almost never happens.
- **Hidden help** on their own balls near pockets stays, invisible, as today, and on the 8
  toward the called pocket.
- **The script must survive anything the player does:** misses at any point, odd shots,
  pocketing in a different order, AFK. Key the plan to what is on the table now, with a "make
  the rest easy" fallback. Never a dead end.
- The bot's shots are real physics shots (ShotFinder / Script), with a believable 1.5-3 s think
  and the cue wiggle. It never pots its last ball and never touches the 8 early.
- **Length:** measure it. Aim for a median of 3 minutes or less from the break to the winning
  ball (propose the number).

### 4.5 After game 1: the guided chain (path S)

Pointers and light dims (not too dark) at every step, with big text where marked. Each step
has a re-prompt and a fallback (section 7).

1. **The win.** The bot stays at the table, idle and natural; it does not leave yet. The
   result screen shows with no rematch, only Continue.
2. **The first-win reward:** their Rare lucky block (today's first-win Rare block on its timer).
   Continue.
3. **NEW RANK! Bronze.** They click to dismiss it.
4. **Now the bot reacts and leaves.** It says one casual line in a chat bubble and in chat.
   The designer: something like "bro u cheated", but natural and casual; the old "AUGHHHH!" was
   corny. Pick at random from a small list of 6-10 lines in that tone (put them on the plan
   page). It keeps the line readable for about 2.5 s, walks a few steps away, then vanishes
   and leaves the player list, the way a real player leaving looks.
5. **Rank.** No other icons yet. "Open Rank and claim your reward!" points at the rank HUD (top
   left): CLAIM, and the rewards fly where they live (money, the Mystery block to the hotbar,
   the Bronze Cue to Cues). Then "Close Rank" with the hand on the X.
6. **The Mystery block.** "Tap your lucky block!" on its hotbar slot. Its upgrade screen (4
   presses) is rigged to climb **once** on screen, Standard to Uncommon, so they see an upgrade.
7. **Place and open.** The Uncommon block goes to the hotbar. **Big text "Place it!"**: they
   place (throw) it on the ground and open it at once.
   - **Before every reel spins (for every player, not just here)** there is a longer pause of
     about 1.2 s on the cards (a Config number), so they see the variety they can win: the
     Uncommon, Rare, Epic and Legendary cards, and so on.
   - In the tutorial's spin **the Secret cue flashes past once** (a near miss).
   - It lands on an **Uncommon**, from a hand-picked list of the best-looking Uncommons, clearly
     nicer than the Bronze Cue. Propose 3-5 with pictures on the plan page.
   - The reveal screen, then Keep.
8. **Cues.** The Cues icon appears (a lively pop): "Open Cues" → the new cue's card → Equip →
   "Close Cues".
9. **Abilities.** The Abilities icon appears: "Open Abilities".
   - **"Type RELEASE for 3 free spins!"** at the code box. They start with 0 spins.
   - On a controller the box comes filled in and they press Redeem; on PC and phone they type
     it.
   - Spins go 0 → 3. "Spin!" lands on **Magnet** (rigged), the reveal plays, then "Close
     Abilities".
   - The 2 spins left are theirs to use freely (a new spin may replace Magnet: their choice).
10. **The main tutorial ends.** Every remaining icon pops in, one after another (the lively
    stagger, about 1 s): Shop, Free Reward, Daily Challenge, the VIP / Starter Pack tile and the
    money pill, ready for the daily calendar (day 1 to claim, day 7's big reward on show).
    Each icon glows with a "!" until it has been clicked once. **Free Reward stands out most**:
    notification, bounce and glow until clicked.
11. **"Win a Match 0/1"** appears near the top of the screen, big but not too big. It stays
    until done. This is their bonus quest; from here on they have full agency.
12. **The invite popup:** small, polite, not distracting. "Invite a friend? You both get a free
    Rare lucky block!", an Invite button and a big close X. Shown once only.
    - Keep it honest: a small line says when the reward comes (today: when the friend wins their
      first match; read the rule from Config).
13. **Free Reward:** it bounces until clicked, then opens on Daily (the day-1 claim, day 7 in
    view). **The group, favorite and like frames are highlighted once** and never again after
    they've been clicked.
14. **Play Global glows** (the matchmaking bar or the spawn pill). That leads to game 2 (4.6).

### 4.6 Game 2 and the soft tutorial

- This part is soft: they are encouraged, never forced, and have every menu.
- **Game 2 is a real game** against whoever the new search finds (4.7). It is not rigged, and
  they may lose.
- **The goal is that game 2 is against a real person**, ideally in the same server and a fellow
  beginner. The order is a same-rank person in this server, then a same-rank person in a
  teleported global match, then a bot in this server. All within 5 s; a bot, at the latest,
  after 5 s.
- **After game 2, win or lose, the full tutorial is complete.**
  - If they won: "Win a Match 1/1" pops "Done!" and becomes the daily win track.
  - If they lost: the quest stays until they win.
- After game 2:
  - the Shop gets its click-once glow if it hasn't been clicked yet. Don't write
    economy-specific nudges: the numbers will change.
  - When the Rare block from game 1 has finished its timer, its slot glows "Ready!".
  - Daily Challenge shows; its "!" waits until the challenge is built (behind a Config switch).
    Today it only says "Soon".
- Funnel: record what game 2 was (a real player in this server, a real player global, a bot in
  this server, or an arena overflow) and how it ended.

### 4.7 The new search, for everyone (the designer: "for the rest of the game as well")

1. **This server first.** A search (Play Global, a pad's Play Global, the spawn pill) first
   looks in this server for anyone near their rank who is searching or waiting alone on a 1v1
   pad. Propose rank windows that widen quickly.
   - On a match, both move to a free table in this server with a quick fade. No teleport.
   - The same-server search keeps listening for the whole wait: someone here who starts
     searching during it beats the global queue.
2. **Then the global queue** as today (MemoryStore, an arena teleport).
3. **5 s at most, "no matter what"**, then a bot: a disguised bot of their tier **in this
   server**, at a free table, with no teleport.
   - If this server has no free table, today's arena bot (a teleport) is the fallback.
   - Team searches (2v2 / 3v3) also wait 5 s at most before bots fill (today 25 s).
4. Lobby bots stay off by default. A server with zero other players still gets a match, against
   the in-server bot.

### 4.8 First-time hints, for everyone

- Once each, saved: the ability bar full (how to use it on that device), the first rank-up
  (claim it in Rank), the first lucky block in the hotbar (tap, place, open), the first Mystery
  block (its upgrade screen), the first cue won (equip it in Cues), the first visit to Abilities
  (the RELEASE code if not redeemed yet, then spin), the first ball in hand and the first 8 call
  (when not already taught), and the first click on each new icon.
- Each hint is a pointer and a short line, with a light dim only where needed. It goes away when
  done.
- A hint is "ignored" if it times out or they do something else. It may come back once, later.
- In a fair match a hint never pauses the clock, never blocks the table, and never covers its
  middle.

### 4.9 Skip

- A small, visible **Skip tutorial** button top right with a Yes / No confirm. Never hidden.
- Skipping in game 1 keeps the game going with guidance off. The bot still plays as in the
  script.
- Skipping in the chain shows everything at once. The first-time hints still come when those
  things first happen.
- The funnel records the step they skipped at.

### 4.10 Shooting on a controller (everyone)

- **Default: hold R2 (RT) to fill the power bar, let go to shoot.** Any press of the trigger
  counts as held.
  - Never rely on how far the trigger is pressed. The designer tested trigger depth and it was
    finicky: it jumped from 0% to 100%, and triggers are hard to control.
  - **A does the same** (today's button).
  - **Cancel:** B while holding cancels the pull instead of opening Leave. Today's cancels stay
    too: moving the stick, the D-pad, L2.
- **Tune the fill:** smoother and easier to stop where you want than today's 0.9 s to full.
  Maybe a slower start, so soft shots are easy. It holds at full. Propose the numbers.
- **Build two more versions behind a Config switch** for the designer to try with a real
  controller ("we can test out different ways"):
  - **B:** the trigger's depth with heavy smoothing and a peak hold on release;
  - **C:** hold to fill, let go to freeze, press again to shoot.
  The designer picks after testing. Studio can't fake a gamepad.
- Update `PadGuide`, every hint string and the tutorial's controller words. Show Roblox's own
  button images (`UserInputService:GetImageForKeyCode`), e.g. "Hold R2 to fill the bar, let go
  to shoot!".
- Ball in hand stays hold L2 + left stick, the ability stays X, zoom stays the right stick.

### 4.11 Changes for every player (they ship with this branch)

- **Starter spins 0** for new saves (`Config.Ults.Earn.Starter` 1 → 0). RELEASE gives 3 spins.
  A new save's first spin lands on Magnet. On path S that is part of the chain; for everyone
  else it is a run assumption, so log it.
- **Bronze's Mystery block waits in Rank like every other rank reward** (no more `BlocksAtOnce`
  for it), so claiming is one rule for everyone. This is a run assumption: log it, and drop it
  if it breaks something.
- **The reel pauses about 1.2 s on the cards** before every spin.
- **"x2!" (or "x3!" and up):** a small pop beside NICE SHOT! when two or more of the shooter's
  balls drop in one shot. Never on the break.
- **The new search** (4.7).
- **Controller shooting** (4.10).
- **VIP + Starter Pack become one tile** that switches between the two offers (for example a
  flip every few seconds). That tile and **Daily Challenge get bigger**: about the size of the
  left column's tiles, or a bit bigger. Follow the lively GUI rules.
- **The new arrow look** wherever the arrow is used.

### 4.12 Server size and spare tables

- The designer set about 30 players and asks: is 20, 25 or 30 better?
- **Model it** (5.4): 10 1v1 tables plus the team tables; the new in-server matches, where a
  player against a bot holds a whole table; players away in arenas; idle players.
- Measure how often a new player finds no empty table, and how often in-server matches spill
  over to arenas, at 20, 24 and 30.
- Recommend on the plan page: the biggest size that keeps "no empty table for a new player"
  under about 1% of joins.
- **Backup:** if every 1v1 table is busy, a new player's rigged game may use an empty team
  table as a 1v1, if the game supports it.
- The designer sets Max Players in the Creator Hub. Give them the click steps.

---

## 5. Simulations and agents (before the plan page)

Run these in parallel with agents where you can. Put the scripts in `tools/` (committed) and
the outputs in `~/Desktop/8ball-refs/tutorial/sim-2026-10-09/`.

**5.1 Layout search** (Lune, building on `tools/tutorial_break.luau` and `Tutorial/Break.play`;
name it e.g. `tools/tutorial_v2_search.luau`).
- Search the invisible rack variations and break cue variations for a break that meets 4.4:
  - exactly 2 solids, the second a slow edge (measure the hang time at the lip);
  - no stripe, no 8, no scratch;
  - the 8 parked safely;
  - a turn-2 layout with the target near a pocket, the pocket out of frame at the home view
    (use `Camera.viewFor` and the home zoom for a 16:9 PC screen and a phone of about 2.16:1),
    and a ricochet line to a second solid;
  - good chances for the Fire Shot setup and an easy finish.
- After turn 2 the layout depends on the player's shot. Design the likely outcomes, and lean on
  the hidden help and the "make the rest easy" fallback.
- **If the designer's exact chain can't be found, say so honestly** on the plan page, show the
  closest and propose alternatives.

**5.2 The new-player simulation.**
- Model new players: an aim-error mix (careful, sloppy, wild), power choices (often too soft or
  too hard), some who don't zoom, some who ignore prompts, some who go AFK. Write the model's
  numbers down and say why.
- Play thousands of game 1s with the real physics, the hidden help and the bot's script, using
  several processes.
- Measure:
  - each planned shot's pot rate, the ricochet rate and the Fire Shot rate;
  - the share who miss at least once (and so see ball in hand);
  - the game's length (median and 90th percentile) and the number of turns;
  - 8-ball incidents, losses and dead ends (both must be 0).
- **Tune until:** the aim shot ≥ 90%; the ricochet ≥ 80% of those who pot; Fire Shot ≥ 85%;
  0 losses; 0 dead ends; a median of 3 minutes or less (or propose better targets).

**5.3 The bot's arrival:** wait times from stepping on to the bot stepping on (≥ 95% under
2 s); "seen popping in" must be 0 in the model (check the spawn spots against camera views).

**5.4 Server size** (4.12).

**5.5 The search:** for a few server populations, how often game 2 is against a real person in
this server, a real person global, or a bot, and the waits.

**5.6 Fresh eyes:** after each built piece, an agent compares Studio screenshots with 4.1 (one
thing at a time, not too dark, readable on a phone, natural) and with refs 03 and 04, and
lists what feels forced or confusing.

**5.7 Research (short, one agent, about a page):**
- Roblox onboarding best practice (show, don't tell; the first-time-experience funnel);
- how console pool and other console games handle shot power;
- Roblox analytics limits today;
- Roblox rules on rewards for invites, likes and favorites (today the like reward is a "verify"
  bluff and the server trusts the client's favorite; flag any risk).
Write it to `~/Desktop/8ball-refs/tutorial/research-2026-10-09/`. Don't over-research.

---

## 6. Funnels and telemetry

- Track each path separately:
  - solo rigged (path S);
  - first game with a real person or a friend (path R);
  - skipped, and at which step;
  - every first-time hint (shown, done, ignored);
  - game 2's kind and result;
  - the Win a Match quest, the invite popup (shown, invited, closed), and the Free Reward,
    group, favorite and like clicks.
- **Design within Roblox's limits** (check the docs: 10 funnels, 100 steps, 3 custom fields).
  - Use the onboarding funnel for the common steps.
  - Use separate funnels per path where breakdowns need it. Breakdowns use the first step's
    fields, and the path isn't known at join.
  - Use custom events with fields for hints (name, outcome, device).
  - Make room by reworking today's funnels.
- Add **time spent per step** (a custom event's value in seconds) to find slow steps, and the
  **device** (PC, phone, tablet, console) as a field wherever it helps.
- Log a **`TutorialError`** event (step plus a short message) from every guarded failure, so
  live bugs show in the dashboard.
- Studio doesn't send analytics. Add a designer-only `/funnel` dev command that prints what was
  logged for them, and print each event in Studio.
- Write `docs/TUTORIAL_FUNNELS.md`: every event, where it fires, and how to read it in the
  Creator Dashboard, in beginner steps.

---

## 7. Bug-proofing (as important as the design)

1. **Never stuck.** Every step has:
   - its expected action;
   - a re-prompt after a few seconds (the hand pulses, the text pops again);
   - a fallback after longer, or if its target button is missing (move on by itself, or a
     "Next" button);
   - a fail-safe: any error in tutorial code ends the tutorial gracefully (everything shows,
     the game works normally) and logs `TutorialError`. **The game must never break because the
     tutorial broke.**
2. **One source of truth:** the server's step machine. Add a Lune test that scans `src/` for
   every step name used and fails if one is not in the step list (this catches the `"Drop"`
   bug). Unknown saved steps are repaired by a migration map (old names: `Drop`, `RareDrop`,
   `Request`, `Queue`, `Arrow2`, `Lobby`, `Nudges`, ...). Players with any match or win never
   enter the tutorial.
3. **Saves:** avoid a save version bump if you can (economy v5 may bump it, and the merge would
   conflict). Use `Flags`. Test the migration on old saves.
4. **Resume:** leaving and rejoining at every step resumes correctly. Game 1 restarts from the
   arrow; the chain resumes where it was. When the player leaves, the bot leaves naturally and
   the table is freed.
5. **The rigged layouts are re-simulated at server start** (as today). If that check fails
   (for example because a later merge changed the physics), fall back to a safe plan (a normal
   break, the hidden help and the guidance) and log it. **A Lune test fails when a physics
   change breaks the layouts**; this is what protects the tutorial at merge time.
6. **The chaos list.** Try every item and record the result in Notes:
   - Leaving and rejoining:
     - leave and rejoin at every step;
     - skip at every step;
     - AFK for 5 minutes at every step.
   - The character and the camera:
     - reset, die or fall off the map (FallGuard) at every step;
     - walk away mid-step;
     - open other menus, Esc, or the Roblox menu mid-step;
     - switch device mid-step (mouse → gamepad → touch);
     - resize the screen or turn the phone.
   - Lag and load:
     - a low frame rate;
     - fake lag (STUDIO_NOTES);
     - spam clicks.
   - Other people:
     - two new players at once (two bots);
     - a friend joins during the bot game;
     - a real player steps on the tutorial table;
     - no free table.
   - The bot:
     - its avatar fails to load (a fallback look);
     - its path fails (a fallback route out of sight);
     - the player stands on the pad's edge, or steps on and off again and again.
   - The server and saves:
     - the server shuts down mid-tutorial (BindToClose);
     - DataStore errors (the tutorial still works in the session);
     - an old save with items never enters the tutorial.
7. **Automated run-throughs:** extend the QA hooks (`TutorialQA`, the client QA hook, `BotsQA`,
   `GuiQA`) into a driver that plays the whole first session by itself, with random choices
   (misses, delays, skips). **Target: 20 clean full runs in a row with no console errors**,
   plus the chaos list.
8. **Two fresh-eyes reviews before the end:**
   - a code reviewer agent over every file you touched (races, nils, leaks, cleanup, server
     checks on every remote);
   - an adversarial tester agent that lists ways to break the tutorial.
   Fix everything they find, then test again.
9. **Races:** the server validates every client action. The client re-syncs from attributes on
   CharacterAdded and whenever a menu closes. No timing guesses: wait on state, always with a
   timeout.
10. **Phones:** the arrow, dims and hand stay cheap (no new Instances every frame).

---

## 8. Testing

- **Studio, your window only:**
  - PC.
  - The phone through the device emulator. Claude can't switch it, so batch the phone checks
    and ask the designer once to switch it.
  - The controller is manual: the designer tries it with a real pad near the end, including
    the A / B / C shooting choices.
- **Two players in Studio:** if MCP can start a Server + Clients test, use it. If not, those
  checks move to the test place.
- **The test place** (Crazy 8 Test Place, place 75362358216917, universe 10769973956):
  - Build a full place file (your place copy plus the Rojo build, merged as in STUDIO_NOTES)
    and publish it with Open Cloud:
    `POST https://apis.roblox.com/universes/v1/10769973956/places/75362358216917/versions?versionType=Published`
    (body: the .rbxl file; header `x-api-key` read from the Keychain, never shown).
  - If the key isn't allowed (401 or 403), ask the designer to give the key place-publishing
    permission for Crazy 8 Test Place in the Creator Hub, in simple steps. As a last resort, ask
    them to publish from your Studio window (File → Publish to Roblox As… → Crazy 8 Test Place).
  - The test place has its own saves, so every account starts as a brand-new player there
    (ideal). `/tutorial reset` repeats it.
  - Products don't exist there: don't test purchases. Check the settings the game needs
    (Studio access to API services, Max Players).
- **The live checklist for the designer** (they need a second account or a friend; you can't
  play it yourself):
  - path S end to end on PC, phone and controller;
  - a friend joins mid bot game;
  - two sit together (path R);
  - same-server pairing (two accounts press Play Global);
  - global pairing (two servers);
  - the bot at 5 s, in this server;
  - teleports back;
  - the funnels in the Creator Dashboard (they arrive with some delay).
  Publish, give them the checklist, ask, wait for their results, fix, publish again.

---

## 9. The plan page (the one planned stop)

Make `~/Desktop/8ball-refs/tutorial/tutorial-v2-plan.html` (and a `.md` copy) in plain words,
with pictures:
- the whole first session as a timeline (each step: what they see and do, the time, the words
  per device);
- the rigged layouts as top-down drawings from the simulation (the break's result and each
  planned shot with its lines);
- the simulation numbers against the targets;
- the bot's arrival plan;
- two arrow looks (Studio screenshots);
- the controller versions and their default numbers;
- the server size model and the recommendation;
- the funnel design;
- the step list with every re-prompt, timeout and fallback;
- the 3-5 Uncommon cue candidates (pictures);
- the bot's lines;
- **every change you propose to the designer's design** (what, why, what they said), and the
  run assumptions so far;
- **what can't be done exactly as asked** (honest).

Open it in a browser for the designer, mark the waiting file, ask "Approved?" and stop.

---

## 10. Merging back later (only when the designer says)

The designer will keep working in `~/Desktop/8ball` meanwhile (maybe economy v5 and other
changes). **Merge only this run's work, and nothing else.**

- **During the run:**
  - Keep a **touch list** in Notes: every file outside the tutorial's own modules that you
    changed, and why. Keep those hook lines small, and put new code in new modules.
  - Read numbers from Config.
  - Never pull the designer's newer commits into this branch mid-run, unless you ask first.
- **When told to merge:**
  1. Ask which branch in `~/Desktop/8ball`, and check that the designer has committed their
     work and that no other session is working there.
  2. Find the fork commit F (in Notes; `git merge-base tutorial-v2 gui-v4` as recorded at
     Step 0).
     - If F is an ancestor of the target branch, merge there: `git merge --no-ff tutorial-v2`.
     - If it isn't, replay only this run's commits:
       `git branch tutorial-v2-replay tutorial-v2 && git rebase --onto <target> F tutorial-v2-replay`,
       then merge that.
  3. **Conflicts:**
     - Outside tutorial files, the designer's newer code wins. Re-add only the tutorial's hook
       lines from the touch list.
     - Never bring back anything the designer removed or changed.
     - Economy numbers come from the target's Config.
  4. After the merge, run lint, the tests (including the layout guard; if the physics changed,
     re-run the layout search and re-tune) and the simulations. Do a full Studio run-through
     only with the designer's OK, since it is their Studio window. Merge the docs (GDD 14,
     STATUS, DECISIONS).
  5. The designer publishes. Remove the worktree and branch only when they say.

---

## 11. The report

`docs/prompts/TUTORIAL_V2_REPORT.md`, in plain words:
- what changed (the first session step by step, and the rules for everyone);
- what was checked and on which device;
- what the designer must try by hand: the controller choices, phone, the test-place checklist;
- the Max Players to set;
- the funnel guide;
- open questions;
- every run assumption.

Also update `docs/GDD.md` section 14 (rewritten) and any other section you changed,
`docs/DECISIONS.md` (dated lines), and `docs/STATUS.md` (current state only, under 100
lines). All in the worktree.

---

## Progress (tick each box when it is verified, committed and pushed)

- [x] 0. Setup:
  - if `tutorial-v2` has no commits of its own yet, `git merge --ff-only gui-v4` to start from
    the newest game; record the fork commit in Notes;
  - copy any git-ignored tool files lint or tests need from `~/Desktop/8ball`; baseline
    `tools/lint.sh` and `tools/test.sh` (record the results);
  - the place copy `place/lane-tutorial.rbxl` from `~/Desktop/8ball/place/8ball.rbxl`. If
    something the tutorial needs is missing (lucky block templates, cue templates), ask the
    designer to save their place to that file and copy it again;
  - `rojo serve default.project.json --port 34877`; open your Studio window; ask the designer
    to set the Rojo plugin's port to 34877 and click Connect in **that** window;
  - commit this brief and the hook, then `git push -u origin tutorial-v2`.
- [x] 1. Read and map (section 2). Notes get the map, the touch list (started) and the old
  bugs.
- [ ] 2. Short research (5.7).
- [ ] 3. Simulations and models (5.1-5.5), the plan page (section 9). **Stop for
  "approved".**
- [ ] 4. Foundations:
  - the step machine v2 (paths S and R, the chain, first-time hints, resume, the migration
    map, the step-name guard test);
  - `Config.Tutorial` v2, `Strings.Tutorial` v2;
  - dev commands (`/tutorial reset | step | skip | path`, `/funnel`);
  - the fail-safe and `TutorialError`;
  - the funnel v2 skeleton.
- [ ] 5. The look: the new arrow (body to table, screen-edge pointer), the overlay (light dims,
  big text), the hand's gestures per device, Roblox's button images.
- [ ] 6. Controller shooting (4.10): R2/A hold-to-fill by default, versions B and C behind a
  Config switch, B to cancel, `PadGuide` and strings.
- [ ] 7. The bot (4.3): warm load on join, out-of-sight waiting, natural walking, at most 2 s
  of waiting, any empty table, waiting if they step off, leaving, cleanup.
- [ ] 8. Game 1 (4.4):
  - the break;
  - aim and zoom;
  - the ricochet and "x2!";
  - Fire Shot;
  - their own shots;
  - the bot's scripted visit and ball in hand;
  - the later bot visits;
  - the 8 and its rescue;
  - the clock and AFK;
  - the "make the rest easy" fallback;
  - the layout guard test.
- [ ] 9. The chain (4.5):
  - result, Rare block, NEW RANK!;
  - the bot's line and exit;
  - the Rank claim;
  - the Mystery upgrade;
  - Place it, open;
  - the reel pause for everyone and the Secret glimpse;
  - Cues and Equip;
  - Abilities: RELEASE and the Magnet spin.
- [ ] 10. The soft part (4.5 steps 10-14, 4.6):
  - icons pop in, with click-once glows;
  - Win a Match;
  - the invite popup;
  - Free Reward and highlight-once;
  - Play Global glow;
  - the Rare block's Ready glow;
  - the VIP / Starter tile and the bigger Daily Challenge.
- [ ] 11. The new search for everyone (4.7): this server first, global within 5 s, the bot in
  this server, teams 5 s, arena overflow.
- [ ] 12. Path R, skipping, first-time hints for everyone (4.8, 4.9), starter spins 0,
  Bronze's block in Rank, "x2!" for everyone.
- [ ] 13. Funnels and telemetry complete (section 6), `/funnel`, `docs/TUTORIAL_FUNNELS.md`.
- [ ] 14. Bug-proofing (section 7): the chaos list, 20 clean automated runs in a row, fake
  lag, the two review agents, fixes.
- [ ] 15. The test place (section 8): publish, the designer's live checklist, fixes,
  republish.
- [ ] 16. Docs and the report (section 11).

(The merge is not a Progress step: it waits for the designer's word, section 10.)

## Notes (yours: the fork commit, the touch list, run assumptions, chaos results, open items)

- **Fork commit F = `19d27d4`** (`git merge-base tutorial-v2 gui-v4`, 2026-10-09). The branch
  had no commits of its own and already sat on gui-v4's head, so the ff-only merge was a no-op.
- **Baseline (2026-10-09, before any change):** `tools/lint.sh` OK (3 old LocalShadow warnings:
  `PadGuide` 194, `MatchHUD` 799, `Main.client` 1338); `tools/test.sh` 1118 passed, 0 failed.
- **Ignored files copied from `~/Desktop/8ball`:** `tools/globalTypes.d.luau`,
  `src/server/MapData/GrayBox.json`; the place copy `place/lane-tutorial.rbxl` from the
  designer's `place/8ball.rbxl` (saved 05:42 today, newer than the committed one).
- **Rojo:** `nohup rojo serve default.project.json --port 34877` (log `.lanes/rojo.log`).
- **My Studio window:**
  Two other Studio windows are not mine: the designer's Crazy 8 Ball (Team Create) and a
  Crazy 8 Test Place window. A plain `open -a` only showed the Start Page; launching the binary
  with `-localPlaceFile <file>` opened it (pid 79859, Studio id `01707bb4…`, name
  `lane-tutorial.rbxl`). The designer connected Rojo 34877 in it (2026-10-09).

### Step 1: the code map (checked 2026-10-09; section 3 holds, with these additions)

- **Server.** `TutorialService` (step machine on `Flags.Tutorial`; attributes `TutorialStep`,
  `TutorialActive`, `TutorialNudge`; hooks set in `start`: `Ranking.setBlockKind`,
  `LuckyBlockService.setOpenHooks(forcedOpen, opened)`, `Items.setEquipHook`,
  `UltSpins.setSpinHooks(forcedSpin, spun)`, `Rewards.onRedeemed`, the `TutorialEvent` remote;
  `/tutorial reset|skip|off|step`; Studio `ServerStorage.TutorialQA` step/set/flag/block).
  `TutorialGames` (a 0.25 s Heartbeat `watch` per player: `reserve` the nearest usable 1v1 table
  (`t.reservedFor`, attribute `TutorialTable`), `rig` sets `e.tutorial` + the rack, `Opponent.join`
  = `BotService.tutorialBot()` + `joinTable(delay 2)`; game 1's lessons through the
  `TutorialLesson` attribute (Break, Aim, Ability, Pick, BallInHand, Eight), `TutorialAimAngle`,
  `TutorialPickBall`, `TutorialPocket`; the bar is filled after the aim shot (`UltMatch.setBar`);
  `exitOn` storms the bot off 0.25 s after the winning 8; `game1Over`; `game2Over`;
  `Tables.setRequestFilter`; `BotService.setFallbackWait`).
- **Shared.** `Tutorial/Steps` (order, `resume`, `initial`, `shows`, `nudge`, the 22-step
  onboarding funnel with bit masks), `Rig` (playerTeam/Group, `turnHand`, `timed`, `shot`
  (break override), `assist` (hidden Magnet), `judge` (EightBack)), `Break` (`rack`, `play` =
  the server's exact path, `lesson`, `eightPlaced`, `eightPocket`, `score`), `RankClaim`.
  `Bots/Script` (`pot`, `scratch`, `eightBlunder`, `tutorialView`, `poor`); `Bots/Driver.decide`
  (visit 1: pot then scratch; later visits `poor`).
- **Client.** `Tutorial` (RenderStepped scene per step, device words, `HOST_HIDES`, nudges,
  Studio `PlayerScripts.TutorialClientQA`), `TutorialOverlay` (line, 4-frame dim with a ring,
  Skip + confirm, ButtonSelect), `TutorialHand` (point, pull, hold, swipe, stick, drag),
  `TutorialArrow` (60 flat decal parts, PathfindingService every 3 s or 4 studs),
  `TutorialAnchors` (anchors, hidden set, aim lock/suggest, turn meter, flags/probes).
- **Every file that reads the tutorial today** (the guard test's scan set): client Guideline,
  HubCorners, Input, InventoryCues, LuckyClient, LuckyHotbar, Main, MatchBar, MatchTargets,
  MenuColumn, PostMatch, PowerCue, Progression, RankClaimBlock, UltHud, UltOdds, UltPick,
  UltScreen, WinTrack; server Bootstrap, BotService, DevCommands, Funnel, GiftDropService,
  LuckyBlockService, PlayerData, RankClaimService, Ranking, Rewards, SoloSearch, TableService,
  UltSpins; shared Bots/Script, Config, Net, Rules/MatchEngine, Strings.
- **Bots.** `BotService.spawn` (Identity look, yields), `seat` (builds the body on the pad),
  `joinTable` (teleports onto the pad after a delay), `stand`, `walkIn` (arena: stand 1 spot
  out, one `MoveTo`, seat), `remove` ("Vanish"/"Angry"), `stormOff`, `say` (BotSay remote:
  bubble + chat line), `poll` (0.1 s), `ended` (the tutorial bot's angry exit). `Driver.turn`:
  think + wiggle 2-4 s. `LobbyBots.walkTo` = PathfindingService + MoveTo.
- **Gamepad today:** ButtonA ramps the power at `Config.Input.Gamepad.PowerRampPerSecond` 1.1
  (full in 0.9 s), release shoots; R2 is unbound ("R2 was an analog pull; it did not work
  well"). STUDIO_NOTES' "Testing by hand" still says R2 shoots: stale, fix it in step 6.

### Old bugs and dead code (confirmed 2026-10-09)

- `TutorialGames.game1Over` sets `"Drop"` (not a step) after the game-1 win: guidance dies.
- `ClaimedDaily` (funnel step 18) is never logged; `ClaimedRank` is (RankClaimService).
- `TutorialActive` has no reader outside a Steps comment; the `TutorialCue` remote is unused;
  `TutorialCalling` is only ever set.
- The spin forces Fire Shot (everyone's starter); Heat Seeker is gone, so "Pick" never shows.
- **New finding:** since 2026-10-09 a lucky block on its timer cannot be thrown (NotReady, the
  skip popup). The Mystery block upgraded to Uncommon lands on the Uncommon timer (1 min), so
  the chain's "Place it!" needs that one block ready at once (the tutorial's own block only).

### Touch list (files outside the tutorial's own modules changed, and why)

- (none yet)

---

## Appendix A: the designer's own words (2026-10-09, kept as written)

> some overarching ideas for the tutorial
>
> * have them focus one thing at a time, pointer clickers, darkening screen, large text telling them what to do.
> * while the tutorial is meant to guide them, i want them to feel that they still have agency and that the tutorial is not restricting their freedoms to control the game (however the tutorial is still obviously rigged to make them feel rewareded which they dont know).
> * tutorial should feel natural and unforced, like for example dont just tell them to zoom out by telling them how to, the shot should be lined up in a perspective where essentially a zoom out is required to be able to see where the ball goes, so they intuitively also know to zoom out, they should learn the game by playing, not teaching and hand-holding.
> * barely any waiting time in between moments, they should always be doing something.
> * after tutorial is done give them a big text saying "Win a Match 0/1" as sort of a bonus quest for them and from there is complete agency for them to play. they should also get a popup to invite friends or heavily encouraged too, saying they get a free rare block or whatever, and also let them know about the free rewards for joining group and favoriting
>
> solo players vs friends, skipping, and where it happens
>
> * start from the current tutorial (GDD section 14, TutorialService, TutorialGames, Shared/Tutorial) and rework it, completely redo it if needed.
> * it all happens in the real public server they join, never a separate place or a fake bot lobby. no extra loading screens in the first session.
> * make sure the server always has empty tables for new players (max players below the 32 seats of 16 tables).
> * the rigged game is for whoever sits down alone. the arrow points to the nearest empty table, but any empty table they pick becomes the tutorial table, picking a different one must not cancel it. after they sit, the bot walks over from a few steps away in the lobby (not popping onto the pad) so it feels like someone came to play them.
> * if they sit with a real person, or a friend joins their table, it's a normal fair game (no rigging, no hidden assist). only the rigged game ends, not the teaching. a friend joiner who sits alone still gets the bot game, so there's no need to detect how they joined. if a friend shows up after the bot game started, finish the bot game first.
> * split the teaching in two:
>   - pool controls (aim, power, zoom, ball in hand, picking the 8's pocket): taught in their first game whoever it's against, turned off if they skip.
>   - things only our game has (ability bar, rank up and claiming, throwing and opening a lucky block, equipping a cue, ability spins, the RELEASE code): each one shows the first time it happens, for everyone including skippers and friend games, once each, saved so it never repeats.
> * keep a small visible skip tutorial button top right with a yes/no confirm, never a hidden one. skipping mid game 1 keeps the game going with guidance off.
> * track each path separately in the funnel: solo rigged, first game with a real person or friend, skipped (and at which step), and every first-time hint (shown, done, ignored).
>
> here's current revisions i have for whats in the tutorial so far:
>
> * WAY more noticeable arrow, smoother when it tracks you, make it like thick black outline and white, bigger, and not on the ground, comes from the persons body to the table, not their feet.
> * because theyre joining a public server now, there should be players hopefully already playing, rather than also a bot teleporting in, i maybe want instead the bot to walk in (have some like natural movements like slight like twitches forward, no robotic static movement, maybe random turning like with shiftlock or whatever to make them seem natural.
> * when the player first joins the game, the bot should already try to be loaded in as soon as possible, and possibly near the table where they are supposed to end up going, the player should never see the bot randomly spawn in, always out of sight. when the player steps into the tutorial and waits the bot should try and be out of the player's camera view to like seem like the "real player" who is the bot came up from behind or somewhere where they didnt notice, the player shouldnt wait for more than 2 seconds before the bot steps on the pad and queues up. if anything the bot should already start walking towards the same join table as the player based on how close they are to the table so when the player steps on they see the bot step on as if a real player wants to play against them.
> * for the rigged break, do not start at an obvious non straight position, it should start like every other game where the 8 ball is straight and angled parallel to the first ball in the break. the current dark screen and pull back is good for icon is pretty good already [image 1 = ref 03], just make sure on controller, it tells the player instead to hold whatever the key is (whatever the key is, and actually a fundamental rework for controller, should be when theyre holding a button, a power increases, and then they use another button to release, im not a controller player but you should research and use the commonly used buttons for most controller games that feel most intuitive for controller players, im not sure if maybe maybe the same button like holding a to increase power, then a again to release is good or two separate buttons, come up with a proposal)
> * right now the current break and positioning should all be redone and ill explain why.
> * on the break, instead of pocketing 3 balls on the break, just make 2 in, and the second one going in should barely look like it goes in like very very slowly to edge the player, then falls in.
> * the 8 ball right now on the current break is on the edge and hard to get to, should be somewhere more meticulously placed in scenario to be easy to pocket once the game has ended regardless of how the rest of the game plays out, where it is avoided to being pocketed on accident but good position to hit at the end.
> * the next ball that the person hits should already be aimed at that ball and requires only a bit of adjusting, in which will tell the player on pc/mobile/controller whatever their controls are to swipe drag or move their joystick to adjust angle. this ball should be the one in focus and the ball almost everyone should hit as its close to the pocket already, and also the white ball should be in a position where its hard to see the angle, and after telling them to adjust the angle gives them the darkened screen/instructions to zoom out and see the angle better which encourages them to zoom out, and which point it will tell them zoom in and out. (and should maybe even highlight the pocket to let them know this is the one to go for) at this point they should be guaranteed to hit this ball in, there should be an angle that almost everyone hits it at, at which point once they hit the ball in, you should find a way to position the balls to where it actually ricochets and bounces back into hitting another one of their balls into a pocket (looks coincidental) which gives them a 2x streak and also a NICE SHOT!" the game should still show regular rules like indicating "you are solids/stripes" and pulsating the green balls, 20 second timer, gui at the top, etc. after this turn it should again be at an angle thats lined up relatively easy for another shot when the game automatically points to the nearest one (but again agency is important), at which their ability is ready to activate and they are told to press g. the NEW default ability for all players is fire shot, which extends the aiming line/bounce line to the edge of a table, meaning that this ability should actually benefit the player as the next best shot they take, white ball should be close to one of their balls and the ball is far from a corner/side pocket. they should be able to hit this next ball in, and at this point they are left on their own to hit the rest of the balls in (a next angle shot should be a bit more difficult and not easy more but not impossible either, but with the hopes they will miss on a turn being their first time), failing their turn once turns it over to the bot, in which the bot will still hit one of their own balls in, but on their second turn hit a second one in but then scratch their ball. this will then teach them mechanics of moving the ball around when someone scratches, should again give the cursor pointing and also darken screen to show they can move it around. at this point the game should continue to play out (however the rest of their own balls should be positioned relatively easy to pocket to finish the game ASAP so they can get to the other funnels. whenever they mess up and its the bots turn, the bot should almost miss 50% of the time but always at least hit the ball in a way that positions the player for one of their own ball (not perfectly but still very closely and good enough to where its not obvious). hopefully they are able to get to the 8 ball and told which pocket to call (at which point this 8 ball should already be positioned very well and easy like already at a corner pocket) to which they end the game and win. in a rare scenario where they somehow scratch the 8ball (but this should not happen based on simulated run models), then just teleport the 8 ball back into the center, they should never lose in the tutorial. they are still given longer aim/bounces lines just like how it is right now.
> * once tutorial is completed, bot should still get mad and say something like "bro u cheated" or something but right now the bot leaves way too early, should wait a few seconds for the match results to show, and then they get their rare lucky block after their first win and press continue. at which point pressing continue they get the rank up! which they click to dismiss (this is where the bot should leave so they have enough time to saying text and then leaving (i think the current AUGHH dialogue is a little corny and artificial maybe a bit more like natural/casual). after this still none of the icons appear, (from here on out essentially all of these should have pointers/darkened screens, not too dark though, and big text wherever necessary(not always needed big text for everything but for some things, i may specifically mention it)) they should be told to open rank button and claim their reward. they then are told to close the rank button. at which point they know should have claimed a mystery lucky block from bronze. they are then told equip the lucky block by clicking on it (should be on the 2 hotbar or whatever its on doesnt matter), and will have them open a lucky block, this one should give them a standard one or maybe uncommon, but once it goes into their inventory it should tell them to "place it!" with big text telling them to place it on the ground, open it immediately. to see what they get, (on this spin, when the lucky block first shows the spin, it should show a variety of all the cues they can earn and pause a little bit (actually all spins for lucky blocks even outside of the tutorial have a little longer pause to see the cards before it starts to spin), and should show them like epic, legendary, rare, uncommon tiers, and while its spinning a glimpse of the secret cue. they should pull a common or uncommon (you decide whats best to feel rewarding). and then after seeing the reveal cue screen, once dismissing it, the game reveals to them the cues icon, and told to click on it. then guided to equip the cue they just pulled as well, then close out of cues. after closing out of cues, the abilities icon will appear, and told to click on it. they are told to type in RELEASE and given 3 free spins (start at 0), and told to spin it once, and at which point will give themb magnet. then they are told to close out of abilities. at this point the main tutorial is complete and the rest from here on out is a soft tutorial (which is like they are encouraged too but dont follow the recommendations of playing a second match and have access to all the gui from here on out) now the rest of the regular icons for the game appear and the game becomes normal, like free rewards, shop, daily challenge, starter offer/vip, all appear, as well as the daily calendar to redeem day 1 rewards and showing game 7. but are not told to do anything with them yet, as their new task is to "Win a Match 0/1!" in big text above their screen (not too big) and stays there until they do, this part is to hopefully give them agency to play on their own (and this point it should give a heavy encouragement or popup to invite friends right here). if nobody is in the server or everyone is busy, then the play global icon will appear as an option for them (but actually even if thats not the case and theres people available still give everyone the play global option) and they are encouraged to click on it (play global will actually have a different behavior too, if two people in the same server press play global then they get queued together in the same server without teleporting to the next available table). if this game is dead with no players, then when they press play global it will partner them against a bot without teleporting within the same server still (and this should be planned as a bot in the server should be in the server if ZERO players are in the server, but again this is a last case scenario contingency) the goal is that this second match they play is against an actual player (hopefully within the server) and also within their rank who are also beginners as well. again though goal is to always keep them playing, the priority of second match should be -> play against same rank person in same server -> play against same rank real person in a teleported global match -> play against a bot in the same server. in all scenarios, after the second match is complete (regardless of loss or win) this essentially completes the full tutorial. (im not sure if should tell them how to use shop and buy lucky blocks or just have them figure out themselves). i definitely want them though to be encouraged to first check out free rewards first (make it the most standing out icon with notification and like bouncing/glowing/popup till they click on it) to tell them they should favorite and like game, join the group (highlight these gui frames once and then never again when they click on it). after this point it should also give the player notification/encouragement to click on the shop to see deals, and also the daily challenge (which will be implemented later). below the daily challenge is the switching between VIP offer and starter pack in the same icon. the tutorial from here is complete (unless i forgot something important)
> * tell the claude to make agents or whatever necessary to make this tutorial feel just right, run scenarios and simulated models to see which one would work best to describe my tutorial.
> * you are free to change things around for the tutorial if needed if it makes it more intuitive and simpler, but make sure to get my approval first.
>
> one more thing to make note when building this tutorial, be careful and check for bugs and make sure its bugproof, if the tutorial bugs then people leave and thats a huge problem so its important to make sure no issues happen here to pay extra care to this

## Appendix B: the interview (2026-10-09)

What the code map found first: the tutorial dies after game 1 (the `"Drop"` step); only 10
1v1 tables; the controller holds A to charge; Play Global always teleports; Bronze gives $2,500,
a Mystery block and the Bronze Cue; 1 starter spin; VIP and Starter are two tiles; no quest
system; Roblox's 10-funnel limit.

1. **Folder:** a separate project folder, so the designer can work in the main `8ball`
   meanwhile. "When it's time to merge back there may be new changes like a new economy v5 …
   it's important to merge only the new tutorial and nothing else" (section 10).
2. **One approval stop** after the simulations: OK.
3. **Server size:** the designer wanted 30 at first, and asks whether 20 or 25 is better (the
   run models it, 4.12).
4. **Controller:** R2, but "many triggers are buggy and not reflective of how much you push
   down … rather than having to press slightly to control the bar, if the trigger is pressed at
   all, the bar fills up … we can test out different ways … R2 for deciding power was super
   finicky (jumped from 0% to 100%)" (4.10).
5. **A first game lost to a real person:** the rigged game next time they sit alone: OK.
6. **Later bot turns:** A (the bot never pots again; half its misses are near misses; it always
   leaves a makeable shot).
7. **The cue from the block:** the Mystery block climbs once (Standard to Uncommon), and the
   reel lands a hand-picked, better-looking Uncommon than the Bronze Cue: OK.
8. **Game 2 wait:** "even 10 seconds is too long, 5 seconds at most then bot."
9. **For the whole game:** "this new search is also for the rest of the game as well, same
   pairing even after the tutorial; global queue is now max 5 seconds wait no matter what,
   after 5 seconds it plays against a bot" (4.7).
10. **The invite popup:** after "Win a Match", "make sure the popup is not annoying, polite and
    not very distracting, like a simple small 'invite friend? you get a free rare lucky block!'
    with a big close."
11. **Shop nudge:** yes, but economy numbers will likely differ by the merge, "so tread lightly.
    Just the icons should be encouraged to click once so at least they know what it is."
12. **VIP / Starter as one switching icon:** "just build it here too. Daily challenge and the
    VIP/starter also need to be bigger icons than they currently are, around the same size as
    the left side GUI if not a bit bigger."
13. **Live testing:** the designer published Crazy 8 Test Place
    (https://www.roblox.com/games/75362358216917/Crazy-8-Test-Place) "to test and make sure
    teleport and everything related to multiplayer works good."

Small calls the designer did not object to: the game 1 clock pauses during lessons (AFK 2 turns
stops it); the break's aim is locked, and under half power does nothing; "x2!" for everyone;
the hidden help may bend the cue ball for the ricochet; the 8 after a scratch goes back where it
was; the bot's casual line, walk-off and vanish; the longer reel pause for everyone; RELEASE
pre-filled on a controller; the 2 spare spins are theirs; "Win a Match" stays until a win;
first-time hints for everyone; skippers see everything at once.
