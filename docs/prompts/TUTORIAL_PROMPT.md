# Tutorial & funnel lane: the brief (becomes `docs/prompts/TUTORIAL_PROMPT.md`)

## Context

The tutorial is the funnel that decides whether a new player stays (designer: "the most
important part of the game; finish everything"). Today nothing runs it: the Bots lane left a
tutorial bot (`BotService.tutorialBot`, its pot-then-scratch script, the AUGHHHH exit) that
only a Studio hook calls, `Config.Guideline.TutorialStubLengthInches` and
`StrongBallHighlights` are unwired, there is no floor arrow, no pointer hand, no analytics
funnel. This lane builds the whole first session: game 1 (rigged, in the real public server
the player lands in), the rewards that follow, game 2 (global queue against a disguised bot),
and the real-server nudges. It also makes the designer's rule changes for everyone (rank
rewards held until claimed, 1 starter spin, Heat Seeker default, code RELEASE, Bronze gives 1
Case Drop, no money before the daily popup) and the analytics funnels.

Lane: folder `~/Desktop/8ball-tutorial`, branch `lane-tutorial`, Rojo port **34877**, Studio
window **lane-tutorial.rbxl** only. `docs/parallel/README.md` and CLAUDE.md apply.

## The references (files in `~/Desktop/8ball-refs/tutorial/`)

- **01-pointer-hand-cursor.png**: a white cartoon hand, index finger pointing down and a
  little to the left, the other three fingers folded in a row; flat white with a light-blue
  shade along its right and lower edges (a cel-shaded block look, not a puffy glove), inside a
  very thick black outline. **Copy**: the shape language, the white + light-blue shading and the
  thick black outline. **Do not use the picture** (another game's): we draw our own hand in this
  style (`tools/gen_tutorial_art.py`, PIL, like `gen_ui_art.py`), uploaded to the group. Used
  for every pointing moment, with a small tap animation (dips 12 px and squishes, 0.5 s loop).
  The GUI lane's `hand_pointer.png` (a puffy upright glove) is a different look and stays theirs.
- **02-arrow-trail-to-target-and-banner.png**: another Roblox game. **Copy only the white arrow
  path**: a single line of solid white up-arrows (a wide triangular head on a short stem, soft
  edges, evenly spaced, about one arrow per 1.5 studs) lying flat on the floor and flowing
  continuously from the player toward the target. **Ignore** the hand, the big caption, the car
  card and the room's colours.

## The designer's answers (interview, 2026-10-03)

1. The break pots **3 solids** (no stripe, no 8, no scratch) and leaves a **4th solid** close to
   a corner pocket, needing only a small aim adjustment.
2. **RELEASE replaces ABILITIES** (3 spins); the spin screen's code banner says RELEASE.
3. **No wander timeout**: the arrow stays until they step on the pad, press Skip, or join
   another table.
4. Leaving mid-game-1: **game 1 again from the start** next time.
5. Heat Seeker's pick: **the hand taps a ball**, then points at Confirm.
6. Top text: **our style, no strip** (big white Fredoka, thick ink outline, a small pop per new
   line, a soft sound).
7. The Rare Case timer: **a pill next to Inventory** (case picture + "58:12", glows "Ready!").
8. Tutorial bot badge: **Silver** (as built).
9. Bronze Case Drop: **through the 8-ball**, lands on Standard, the hand points at "Open now",
   it opens to an Uncommon cue; then a second 8-ball for the match's Rare Case (1 h timer).
10. Game 1 assist: **a gentle hidden pull** (Magnet's strength) on the player's own balls near a
    pocket, nothing shown on screen. Game 1 only.
11. The 8: **the bot nudges it**: the break leaves the 8 near a pocket and the bot never touches
    it; if it has moved, the bot's last bad shot taps it beside a pocket with a clear line; if no
    such shot exists, the 8 shot gets a strong hidden pull into the called pocket.
12. Funnels besides onboarding: **Skipped/cancelled, Shop (repeating), Case Drop, Ability
    spins**.
13. Held rank rewards: **Bronze's 1 Case Drop is given at once** (the 8-ball after the first win,
    tutorial or not); every other rank reward (money, cases, cue, tag, spins) and every later
    rank-up is **held until claimed in Rank**.
14. NEW RANK! still shows after the match, **with "Claim your rewards in Rank!"**; chips don't
    fly; Rank gets a red dot and a glow until claimed.
15. Skip during game 1: **keep playing, guidance off** (everything appears, the bot still plays
    badly); Skip asks "Skip the tutorial?" Yes / No.
16. Real-server nudges: **one at a time, lobby only, an ignored one returns** when they are back
    in the lobby, until clicked.

## Rule changes for everyone (listed in the lane file for the integrator)

- Reaching Bronze gives **1** Case Drop (`Config.Ranks.Rewards.Tier.Bronze.Drops` 2 -> 1), given
  at once; every other rank reward is held until claimed (below).
- **No money on join**: the day-1 $5,000 auto-claim waits until the player is past the
  tutorial's first server (done, skipped or cancelled), so it arrives with the daily popup.
- **1 starter ability spin** (`Config.Ults.Earn.Starter` 3 -> 1). Code **RELEASE** = 3 spins,
  ABILITIES removed (`Config.Daily.Codes`, `Config.Ults.CodeBanner.ActiveCode`).
- **Heat Seeker is the default ability** (`Config.Ults.Default`); Magnet stays Uncommon.
- **Rank rewards are held until claimed**, for every player and rank-up: the save keeps the last
  claimed division in `Flags.RankClaimed` (a number; no save-layout change); pending = the
  rewards between it and `PeakDivision` (Bronze's drop excluded, already given). Clicking Rank
  shows a small claim block on the roadmap (GUI's style kit): Claim -> money flies to the money
  HUD (bottom left), the spin icon to Abilities, cases to Inventory (and their 8-ball), the cue
  into the Index, the chat tag switches on. Existing saves migrate with `RankClaimed =
  PeakDivision` so nothing pays twice.
- **This lane owns the tutorial bot's script** (replaces the Bots lane's step 5 version); the
  second game's Bronze bot stays as the Bots lane built it.

## How it is built (architecture)

- **Server `src/server/TutorialService.luau`**: one state machine per player, saved as
  `Flags.Tutorial` (a step name) through a new `PlayerData.setFlag(player, key, value)`
  mutation. Steps: `Arrow1 -> Game1 -> Rank1 -> Drop -> OpenCase -> RareDrop -> Abilities ->
  Spin -> Code -> Back -> Arrow2 -> Game2 -> Lobby -> Nudges -> Done`, plus `Skipped` /
  `Cancelled` (with the reason). Sets the player attribute **`TutorialActive`** (the GUI lane's
  popups wait on it) and `TutorialStep` (what the client shows). Owns: the reserved table, the
  bot (behind one small `Opponent` interface: `join(t)`, `onEnded`), the rigged break, the
  assist, the 8 guard, the rigged drop / case / spin, resume on rejoin, cancel rules.
  A brand-new save starts at `Arrow1`; a save with any win and no flag is `Done`.
- **Server `src/server/Funnel.luau`**: the only place AnalyticsService is called for funnels
  (pcall-wrapped, once per player per step, remembered in `Flags.Funnel` so a step never
  logs twice across sessions).
- **Shared `src/shared/Tutorial/`** (pure Luau, Lune-tested): `Break.luau` (the rigged rack
  layout + break shot, found offline by `tools/tutorial_break.luau` and checked at server start
  by simulation), `BotPlan.luau` (the tutorial bot's shot filters: never move the player's balls
  or the 8, never pot its last ball; the 8-nudge search), `Steps.luau` (step order, resume
  rules, funnel numbering).
- **Client `src/client/Tutorial.luau`** (+ `TutorialOverlay`, `TutorialHand`, `TutorialArrow`,
  `TutorialAnchors`): reads `TutorialStep`, shows the top text, light dim with a lit hole, the
  hand and its gestures, the floor arrow; hides the column tiles and host-card buttons it should;
  tells the server what the player did (`TutorialEvent` remote, validated server-side).
  `TutorialAnchors` is a tiny registry: other screens register their buttons with one line
  (`Anchors.set("Abilities", button)`), so the hand finds them without knowing their layout.
- **Device**: one helper in `Tutorial.luau` (last input: mouse/keyboard, touch, gamepad) picks
  each prompt's own words and gesture: PC mouse drag / G; phone swipe / tap the ability button;
  gamepad left stick, hold A to pull, X for the ability (the existing bindings), Roblox's own
  glyph images.
- Every number in `Config.Tutorial`, every word in `Strings.Tutorial` (whole sentences with
  placeholders, sized for +40%).

## The build, in order of importance (each step: lint, tests, Studio check, commit, push, status)

### Step 0. Lane setup
Copy this brief to `docs/prompts/TUTORIAL_PROMPT.md`; lane file: Decisions (the answers above,
dated 2026-10-03), Requests (below).

### Step 1. Foundations and the rule changes
- `PlayerData.setFlag` (new function), `TutorialService` skeleton with steps, resume, the
  `TutorialActive`/`TutorialStep` attributes, `Funnel.luau`, `Config.Tutorial`,
  `Strings.Tutorial`, `Net` remotes `TutorialEvent` (client -> server) and `RankClaim`.
- Rule changes: starter spins 1, Heat Seeker default, RELEASE replaces ABILITIES, Bronze 1 drop,
  day-1 auto-claim held while the tutorial's first server runs (`Rewards` small block).
- Held rank rewards (server): `Ranking.applyRank` pays only Bronze's drop at once; the rest is
  pending (`RankClaimed`); `RankClaim` pays it through `PlayerData.grantReward(..., "RankUp")`;
  the migration line in `prepare`. `MatchSummary.xp` / `RankEvent` carry `held = true`.
- Dev command (designer only) `/tutorial reset | step <name> | skip | off`.
- Check: Lune tests (steps and resume, pending rewards between divisions and no double pay,
  funnel once-only); Studio: a fresh save starts at Arrow1 with $0 and 1 spin, Heat Seeker
  equipped; `/xp 100` holds Bronze's money/cue/spin, gives its 1 drop.

### Step 2. The overlay kit and the art
- `tools/gen_tutorial_art.py`: the hand (ref 01's style, our own drawing, 512 px, a pointing
  pose and a flat "drag" pose), the floor arrow tile (ref 02's white up-arrow, tiling), a
  mouse, a swipe trail; uploaded with `tools/roblox_upload.py`, ids in `Config.Tutorial.Art`.
- `TutorialOverlay`: the big top text (UI_STYLE 3: Fredoka, white, ink outline, about 40 px
  PC / 30 px phone, pops in, a soft "ding" per new prompt), the **light dim** (black at about
  0.8 transparency, built oversized like UI_STYLE 2's so no edge shows) with a lit hole round the
  target and a soft pulsing ring; touches outside the hole are blocked only when a step requires
  that exact button. The small **Skip tutorial** button (top right, under Roblox's bar).
- `TutorialHand`: point-and-tap at any anchor or world point; translucent gesture loops: pull
  down the power bar, drag across the screen (PC: hand with the mouse; phone: a finger swipe;
  gamepad: the left-stick glyph tilting), drag a ghost cue ball, tap a ball.
- `TutorialArrow`: a flowing line of white arrows on the floor from the player to a pad,
  following a PathfindingService path round the tables, re-planned as the player moves, ending
  in a pulsing ring on the pad; hidden in a match.
- Check: Studio PC, phone (844 x 390 emulation) and gamepad: each piece shown by `/tutorial
  step`, screenshots compared with refs 01 and 02.

### Step 3. Joining game 1
- On load at `Arrow1`: the server reserves the **nearest empty 1v1 table** (lobby bots playing
  there get up and leave; lobby bots never walk to, wait on or answer requests at a reserved
  table: a `reserved` check in `LobbyBots`' three places and `answer`); the arrow and "Join a
  table!" lead there. If every 1v1 table holds real players, "Waiting for a free table..." until
  one frees.
- Shop, Inventory, Abilities, Rank and Free Reward hidden; no join popups from others reach a
  tutorial player, and the tutorial player's request is not broadcast (`sendRequest` filter).
- On the pad: the host card shows only **Request opponent** (dim, lit, hand taps it); 2 s later
  the tutorial bot (random real look and name, Silver badge) appears on the pad and the game
  starts, the player breaking.
- Another table = cancel at once (reason "OtherTable"); a second real player on the pad with
  them before the bot comes = a friend game, cancel (reason "Friend").
- Check: Studio with `/lobbybots on` (bots step off the reserved table, never return), PC,
  phone, gamepad (the hand on Request; A presses it).

### Step 4. Game 1, the rigged match
- **Break**: a tutorial rack layout and break shot (`Shared/Tutorial/Break`): the cue ball fixed
  on the break line, the aim locked straight up the table (no aim, no placement, no spin or
  angle). Found offline in Lune: 3 solids down, no stripe/8/scratch, a 4th solid within easy
  reach of a corner, the 8 near a pocket, the other solids open. The server re-simulates it at
  start; the player's pull sets only timing: any pull counts, the server plays the rigged power.
  Guidance: light dim lighting the power bar, a translucent hand pulling it all the way down
  (gamepad: "Hold A" with the glyph filling), "Pull all the way back!".
- **Aim lesson** (the 4th solid): "Drag to aim!" with the device's gesture and the long
  guideline (`TutorialStubLengthInches`) and strong ball highlights; then the pull reminder.
  A miss is allowed.
- **Assist**: game 1 only, the player's shots get Magnet's effect on their own balls (and on
  the 8 once called) with the visuals off (a `Hidden` override the Magnet FX skips).
- **Ability**: after the aim shot the server fills the player's bar; "Use your ability!": press
  G / X / tap the ability button (lit, hand); Heat Seeker's pick: "Tap one of your balls!", the
  hand taps the best solid, then Confirm.
- **The bot** (this lane's script): the first time the player misses, the bot pots one ball and
  scratches in that visit; the player gets ball in hand: "You have ball in hand! Drag the cue
  ball anywhere" with a translucent hand dragging a ghost cue ball (gamepad: L2 + stick). After
  that the bot plays poorly: only shots that move none of the player's balls or the 8, never its
  last ball, no early 8. Before the player reaches the 8, the bot's shot that leaves the 8 by a
  pocket with a clear line is preferred (answer 11).
- **The 8**: "SELECT WHICH POCKET" with the dim, the obvious pocket (nearest the 8 with a clear
  line) glowing and the hand on it; all six stay clickable (gamepad: D-pad, A). Losing on the 8
  is impossible in game 1: an early 8, a scratch on the 8 or a wrong pocket puts the 8 back
  where it was and counts as a plain foul (the bot gets the turn and plays badly).
- **The exit**: on the winning shot the bot says "AUGHHHH!", jumps and vanishes mid-air before
  the result screen (the result waits about 1.5 s for it).
- Check: Lune (the break's outcome; the bot filters never touch the player's balls; the 8 guard)
  ; Studio: many full games on PC with deliberate misses, scratches and the 8 on every pocket;
  phone and gamepad runs; console clean.

### Step 5. After game 1 (first server)
Order: result screen (money, XP) -> NEW RANK! Unranked -> Bronze ("Claim your rewards in
Rank!") -> the Bronze Case Drop 8-ball (forced Standard) -> hand on "Open now" -> the opening
lands on an Uncommon cue (forced, a random Uncommon from the Standard Case) -> the match's Rare
Case 8-ball (its reveal sent only after the Standard opening; the case and its 1 h timer start
at settle) -> the Abilities icon appears, light dim, hand -> the one starter spin, forced to
Magnet -> the hand on the code box: "Type RELEASE for 3 more spins!" -> "Click Back" (hand on
the spin screen's Back) -> Arrow2.
- Check: Studio PC/phone/gamepad, the whole sequence from a win; leaving at each point and
  rejoining picks up there (the case steps resume through the Inventory).
- **Depends on the GUI lane** (the 8-ball `MagicBall`, the `Popups` queue, the new column):
  built against release's current screens with a stand-in, then wired to GUI's once merged.

### Step 6. Game 2
- Arrow to a 1v1 pad (reserved as in step 3); the host card shows only **Join Global Queue**,
  hand on it; the search turns into the bot match at once (no 10 s): the Bots lane's disguised
  Bronze bot in a global arena via `GlobalQueue.botMatch` + `TableService.searchToMatch`.
- After the game (win or lose) no rematch; "Press Lobby!" with the hand; the teleport lands in a
  public server.
- Check: the arena half in Studio (`StudioArena`/`StudioArenaBot`); the teleport halves only in
  the published game (integrator / designer by hand).

### Step 7. The real server
- Everything shows. The day-1 claim ($5,000) runs now, so GUI's daily popup shows it, then their
  limited-offer popup (both from the GUI lane's `Popups`, which wait while `TutorialActive`).
- Nudges, one at a time, lobby only, an ignored one returns (answer 16): **Rank** ("Claim your
  rank rewards!", the claim with the fly animation), **Inventory** ("Your Rare Case opens when
  its timer ends"), **Shop**, **Free Reward** right after Shop. Red dots on Shop, Inventory,
  Rank meanwhile.
- The Rare Case timer pill beside Inventory (answer 7); at 0 a one-time "Your case is ready!"
  nudge with the hand on Inventory.
- Then `Done`.
- Check: Studio, a save set to `Lobby` (`/tutorial step Lobby`), each nudge on PC, phone,
  gamepad; ignoring one and playing a match brings it back after.

### Step 8. Skip, cancel and resume (all steps)
Skip tutorial (confirm Yes/No) at any step; another table or a friend cancels; a cancelled or
skipped player gets everything shown at once, the normal first win (Bronze, its drop rolled
normally, the Rare Case) and the real-server popups. Resume rules from `Steps.luau`. Check
each path in Studio.

### Step 9. The funnels (`Funnel.luau`, server)
- **Onboarding** (LogOnboardingFunnelStepEvent, in order): 1 Joined, 2 Saw the arrow, 3 Stepped
  on the tutorial pad, 4 Pressed Request opponent, 5 Game 1 started, 6 Broke, 7 Potted the aim
  shot, 8 Used the ability, 9 Called the 8 pocket, 10 Won game 1, 11 Opened the Standard Case,
  12 Saw the Rare Case drop, 13 Opened Abilities, 14 Spun the ability, 15 Joined Global Queue,
  16 Won game 2, 17 Back in the lobby, 18 Claimed the daily reward, 19 Claimed the rank
  rewards, 20 Opened the Rare Case, 21 Played a 3rd match, 22 Came back the next day.
- **Side events** (LogCustomEvent): ball in hand shown, the bot's scratch, lost game 2.
- **TutorialExit** funnel: skipped/cancelled (with reason) -> first game -> first win -> 2nd
  match -> next day.
- **Shop** (repeating, LogFunnelStepEvent with a session id): opened, viewed an item, pressed
  buy, bought. **Case Drop** (per case): got, timer done, opened, equipped. **Ability spins**:
  opened Abilities, spun, equipped, used in a match.
- Hooks inside other lanes' screens go in as one-line `Funnel` calls (server side where the
  server already sees the action; a `TutorialEvent`/`FunnelEvent` for client-only views like
  "viewed an item"), each listed.
- Check: Lune (order, once-only); Studio console prints each step in debug mode; the Creator
  Dashboard only after publishing.

### Step 10. Final pass
Whole first session on PC, phone and gamepad emulation in my window, every skip/cancel path,
console clean; GDD section 14 rewritten; lane Status, Requests and Decisions complete.

## Shared and other lanes' files touched (each a small block, listed in the lane file)

`Config` (Tutorial block; Ranks Bronze Drops; Ults Earn.Starter, Default, CodeBanner; Daily
Codes), `Strings` (Tutorial block), `Net` (TutorialEvent, RankClaim), `PlayerData` (setFlag,
RankClaimed migration, pending rank rewards), `Ranking` (hold rewards), `Rewards` (hold day-1
claim), `TableService` (reservation, request filter, tutorial hooks), `Bootstrap` (start
TutorialService), `Main.client` (start Tutorial; the per-frame locks), `MatchEngine` (the
tutorial's rigged break and the 8 guard as a hook), `Bots/BotService` + `Driver` +
`LobbyBots` (tutorial script, reserved tables), `UltSpins` (forced first spin), `Items` (forced
Standard case result), `MagnetFx` (skip when `Hidden`), `QueueMenu`, `MenuColumn`, `RankHud`,
`UltScreen`/`UltOdds`, `MatchTargets`, `PowerCue`, `ChatTags` (one-line anchors or flags).

## Requests (to write in the lane file)

- **GUI**: keep the `TutorialAnchors.set(...)` lines and the column's hidden-tile check through
  the rework; the rank claim block on the roadmap is mine in your style (look free to restyle);
  `Popups` waits on `TutorialActive` (as planned); the Rank button's dot/glow while
  `RankPending`; UI_STYLE line: the tutorial's light dim is a deliberate exception to "popups
  never darken".
- **Integrator**: the teleport halves of game 2 and the funnels need the published game; ask the
  designer to save/publish once per milestone.

## Verification (how every step is checked)

`tools/lint.sh`, `tools/test.sh` (new `tests/tutorial_*_test.luau`), Rojo on 34877 synced into
lane-tutorial.rbxl, play-test through Studio MCP in that window only: PC, phone (Studio device
emulation, 844 x 390 landscape), gamepad emulation; `/tutorial step <name>` to jump; console read
for errors; screenshots compared with refs 01 and 02; commit + push `lane-tutorial`; Status in
`docs/parallel/tutorial.md`.
