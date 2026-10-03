# Lane: Tutorial and funnel (a new player's first minutes)

Folder `~/Desktop/8ball-tutorial`, branch `lane-tutorial`, Rojo port 34877, Studio file
`place/lane-tutorial.rbxl`. Rules for all lanes: [README.md](README.md).

## The job

ROADMAP 8.1, GDD section 14 (read it first): a brand-new player's first minutes. The GDD has a
plan (a hidden popup, a disguised PC that walks in and blunders, a ghost break guide, the longer
tutorial guideline `Config.Guideline.TutorialStubLengthInches`, the first win's Rare Case that
already exists, Unranked to Bronze I on that first win). Confirm it all with the designer: their
pictures may differ.

- **Depends on Bots.** The first opponent is a disguised PC from the Bots lane, which is being
  built at the same time. Build the flow, the guidance, the popups and the camera moments first
  against a stand-in (a scripted opponent or Solo), keep the opponent behind one small
  interface, and plug the real bot in once Bots is merged into `release` (watch `bots.md`).
- Remember who has done it with a flag in the existing save `Flags` map (add a PlayerData
  mutation as a new function); do not change the save layout (only Economy may).
- Every step must work on phone, PC and gamepad, and be skippable for players who know pool.
- **The funnel** (ROADMAP 8.2): log each step of a new player's first session with Roblox's
  built-in analytics (`AnalyticsService` funnel events: joined, saw the tutorial, reached a
  table, started the first match, finished it, opened the first case, played a second match,
  came back the next day...), so the designer can see in the Creator Dashboard where new
  players quit. Agree the steps with the designer. Server-side, once per player per step.

## You own

- New: `src/client/Tutorial*.luau`, `src/server/TutorialService.luau` (or similar), a
  `src/server/Funnel.luau` for the analytics steps, `Config.Tutorial`, `Strings.Tutorial`,
  GDD section 14. The tutorial's popups use the GUI lane's kit and style.
- The tutorial hooks you add to `TableService`, `Main.client.luau`, `Bootstrap.server.luau`
  (list each).

## Ask the designer (in the interview)

- What a new player sees from the moment they join, step by step, with reference images:
  where they spawn, what points them to a table, what is explained and how (arrows, text, a
  hand, a voice?), how the first match goes, what happens after.
- Is the first opponent disguised as a real player or shown as PC? (GDD: disguised in the
  first match only, never on a leaderboard, stored as PC.)

## Status

2026-10-03: interview done, brief approved (`docs/prompts/TUTORIAL_PROMPT.md`). Building step
by step (steps 1-10 of the brief).

- **Step 1 done: foundations and the rule changes.** `TutorialService` (steps saved in
  `Flags.Tutorial`, resume on rejoin, attributes `TutorialStep` / `TutorialActive`, Skip,
  `/tutorial reset | skip | off | step <name>`, Studio hook `ServerStorage.TutorialQA`),
  `Funnel` (onboarding once per player, one-time and repeating funnels, side events; Studio
  prints each step), `RankClaimService` (held rank rewards, the `RankClaim` remote, attributes
  `RankPending` and `RankTag`), pure `Tutorial/Steps` and `Tutorial/RankClaim`, `Config.Tutorial`,
  `Strings.Tutorial` / `Strings.RankClaim`. Rule changes: Bronze 1 drop, 1 starter spin, Heat
  Seeker default, RELEASE replaces ABILITIES, day-1 claim held while the tutorial's first server
  runs, rank rewards held until claimed (chat tag included).
  - Checked: lint, 957 Lune tests (new `tutorial_steps_test`, `tutorial_rankclaim_test`);
    Studio (PC): a fresh save joins at Arrow1 (TutorialActive, Heat Seeker, 1 spin, no day-1
    claim); `/xp 100` made Bronze I, gave 1 Standard Case and held $2,500, the spin and the
    Bronze Cue (RankPending true, chat tag still none); the RankClaim remote paid them (spins
    2, tag Bronze, funnel 19 logged); `/tutorial skip` gave the day-1 $5,000 at once. Console
    clean. (The designer's Studio account starts with $5,000: Studio counts it as owning VIP,
    so the VIP Cue's finder's money; a real new player starts at $0.) Phone and gamepad: no
    screens yet in this step.

- **Step 2 done: the overlay kit and the art.** `tools/gen_tutorial_art.py` draws our own
  pointer hand in reference 01's style (flat white, light-blue shade on the lower-right edges,
  very thick black outline, index finger down, the other three folded as separate blocks), a
  mouse in the same style and reference 02's white floor arrow; uploaded to the group
  (`Config.Tutorial.Art`, ids in `tools/upload_manifest_tutorial.json`). Client:
  `TutorialOverlay` (the big instruction line with a ding, the light dim with a lit hole and a
  pulsing gold ring, Skip tutorial with a Yes / No confirm, View button on a gamepad),
  `TutorialHand` (point-and-tap, see-through gestures: pull, hold a button, swipe with or
  without the mouse, stick, drag a ghost ball), `TutorialArrow` (a flowing line of white
  arrows on the floor, routed by PathfindingService), `TutorialAnchors` (where other screens
  register the buttons the hand points at), `Tutorial` (the controller, started from Main;
  Studio hook `PlayerScripts.TutorialClientQA`).
  - Checked: lint, tests; Studio PC (1529 x 666): the line "Join a table!", Skip, the hand
    tapping the money HUD inside the dimmed screen's lit hole, the swipe with the mouse, Hold A
    with Roblox's own A glyph and the filling bar; the arrows flow from the player round to
    table 1's pad and point at it (seen from above; they pointed backwards at first, fixed).
    The dim at 28% black was too faint to read in a capture; it is 35% now (still light).
    Phone: the layer covers the whole screen past the safe area (`ScreenInsets.None`); its
    phone sizes are checked with the flow in step 3. Gamepad: the glyphs are Roblox's own;
    a real pad press is a hand check (MCP cannot drive a gamepad).

- **Step 3 done: joining game 1.** `TutorialGames` (server) reserves the nearest waiting 1v1
  table for a player at Arrow1 / Arrow2 (`t.reservedFor`, the player attribute
  `TutorialTable`); lobby bots get up from it and never walk to, wait on or answer requests at
  it. Stepping on its pad moves to Request; walking off goes back to the arrow; any other
  table cancels ("OtherTable"); a second real player on the pad cancels ("Friend"). Nobody in
  the tutorial's first server sends or gets a Request opponent popup (`TableService`'s new
  request filter). Pressing Request opponent there brings the tutorial bot (2 s,
  `Config.Bots.Tutorial.JoinDelay`) and the game's start moves to Game1. Client: "Join a
  table!" with the floor arrow ("Waiting for a free table..." while none is free); on the pad
  the host card shows only Request opponent, lit in the dim with the hand tapping it, words
  per device ("Click", "Tap", "Press A"; on a gamepad the button is selected for A, and "Press
  Y, then A" once the selection moves off), then "Finding you an opponent...". Shop,
  Inventory, Abilities, Rank, Free Reward and Trade are hidden in the first server.
  - Checked: lint, tests (957); Studio PC: the arrow to table 2, onto the pad -> Request (the
    card with only Request opponent, the dim and hand), the press -> the bot on the pad about
    2 s later -> Starting in 3 -> Game1; funnel steps 1-5 printed in order. `/lobbybots on`:
    a bot waiting on the reserved table left within a second and none came back in 30 s.
    A `/tutorial reset` while seated in a running game cancels as "OtherTable" (correct: the
    player sits at a table that is not the reserved one). Phone and gamepad presses: hand
    checks (the gamepad selection path is in the code; MCP cannot press a pad button).

### Rule changes for everyone (made in this lane; the integrator moves them to the docs)

- Reaching Bronze gives 1 Case Drop (was 2), given at once after the first win.
- No money on join: the day-1 $5,000 auto-claim waits until the player is past the tutorial's
  first server, so it arrives with the daily-reward popup.
- 1 starter ability spin (was 3). Code RELEASE gives 3 ability spins; ABILITIES is removed.
- Heat Seeker is everyone's default ability; Magnet stays Uncommon.
- Rank rewards for every rank-up, for every player, are held until claimed in Rank (Bronze's
  1 Case Drop excepted), with a fly animation on claim.
- This lane owns the tutorial bot's script (replaces the Bots lane's step 5 version).

### Changes to shared or other lanes' files (existing lines)

- `Config.luau`: `Ranks.Rewards.Tier.Bronze.Drops` 2 -> 1; `Daily.Codes` ABILITIES -> RELEASE;
  `Ults.Default` Magnet -> HeatSeeker; `Ults.Earn.Starter` 3 -> 1; `Ults.CodeBanner.ActiveCode`
  RELEASE; new blocks `Config.Tutorial` (before `Config.Debug`) and `Debug.Commands.Tutorial`.
- `Strings.luau`: two `Dev` lines (Tutorial); new `Tutorial` and `RankClaim` blocks at the end.
- `Net.luau`: `TutorialEvent`, `TutorialCue`, `RankClaim` remotes (end of the list).
- `PlayerData.luau`: requires `Tutorial.RankClaim`; `prepare` sets `Flags.RankClaimed` to the
  peak on a save without it; `reset` sets it to 0; new block (before Dev): `setFlag`, `flag`,
  `rankPending`, `claimRank`, `setDrop`.
- `Ranking.luau`: `rewardOf` replaced by `atOnceOf` + `Ranking.setDropTier` (a rank-up pays only
  the at-once drops; the rest is claimed in Rank); `xpPart` and `rankEvent` carry `held` and
  `dropsAtOnce`.
- `Rewards.luau`: `autoClaim` split into the gate (`Rewards.setClaimGate`) and
  `Rewards.claimDayOne`.
- `Bootstrap.server.luau`: starts `RankClaimService` and `TutorialService` after BotService.
- `DevCommands.luau`: the `/tutorial` command (one block).
- `ChatTags.luau`: the rank tag reads `RankTag` first (the claimed tier).
- `UltSpins.luau`: a comment (RELEASE).
- `Main.client.luau`: one line before the RenderStepped hook starts `Tutorial` (step 2).
- `TableService.luau`: a `requestFilter` local and `Service.setRequestFilter` before
  `sendRequest`; `sendRequest`'s loop condition also asks the filter (step 3).
- `Bots/LobbyBots.luau`: a reserved table (`t.reservedFor`) is skipped in `freeTables`, on
  arrival in `goPlay` and in `answer`; the tick's eviction also gets bots off a reserved table
  (step 3).
- `QueueMenu.luau`: requires `TutorialAnchors`; registers `Request` and `GlobalQueue`; the
  update hides HostMore (vs PC, solo, fill with PC), HostRequest, HostGlobal, HostLevels when
  the tutorial says so (step 3).
- `MenuColumn.luau`: requires `TutorialAnchors`; registers each tile; a tile hides while the
  tutorial hides it (refreshed on `TutorialAnchors.Changed`) (step 3).
- `Progression.luau`: requires `TutorialAnchors`; registers `Rank` and `MoneyHud`; the rank HUD
  hides while the tutorial hides Rank (step 3).
- Tests changed for the new values: `ranks_test`, `save_schema_test`, `ult_slots_test`,
  `ult_spins_test`; `tools/economy_config.json` re-exported.

## Requests to other lanes or the integrator

- **GUI**: (1) keep the one-line `TutorialAnchors.set(...)` registrations and the column's
  hidden-tile check through your rework, so the tutorial's hand finds your buttons; (2) the
  rank claim block on the roadmap is built in your style kit as a small block: restyle it
  freely, keep its claim call; (3) `Popups` waits while the player attribute `TutorialActive`
  is true (as your brief already plans); (4) the Rank button shows a red dot and a glow while
  the player attribute `RankPending` is true; (5) a UI_STYLE line: the tutorial's light dim is
  a deliberate exception to "popups never darken" (designer, 2026-10-03).
- **Integrator**: the teleport halves of game 2 (Join Global Queue to the arena, Lobby back to
  a public server) and the analytics funnels can only be checked in the published game.

## Decisions (dated; the integrator copies them to DECISIONS.md)

- 2026-10-03 (designer, interview): the tutorial runs in the real public server the player
  joins, with real players and lobby bots; the Bots lane's 15-bot tutorial lobby is dropped.
- 2026-10-03 (designer): the break pots 3 solids (no stripe, no 8, no scratch) and leaves a
  4th solid near a corner pocket; the aim is locked straight; any pull counts as full power.
- 2026-10-03 (designer): no wander timeout; the arrow stays until the pad, Skip or another
  table.
- 2026-10-03 (designer): leaving mid-game-1 restarts game 1 next time; later steps resume where
  they were.
- 2026-10-03 (designer): the hand also shows Heat Seeker's ball pick; the instruction text is
  our style (big white Fredoka, ink outline, no strip); the Rare Case timer sits beside
  Inventory; the tutorial bot keeps its Silver badge.
- 2026-10-03 (designer): the Bronze Case Drop is shown through the 8-ball (forced Standard),
  opened with "Open now" to a forced Uncommon cue; then the match's Rare Case 8-ball.
- 2026-10-03 (designer): game 1 gives the player's own balls a gentle hidden pull (Magnet's
  strength, no visuals); the bot nudges the 8 beside a pocket if it has moved; losing on the 8
  is impossible in game 1.
- 2026-10-03 (designer): funnels: onboarding (22 steps), skipped/cancelled, shop (repeating),
  Case Drop, ability spins.
- 2026-10-03 (designer): Bronze's 1 Case Drop is given at once; every other rank reward and
  every later rank-up is held until claimed in Rank. NEW RANK! still shows, with "Claim your
  rewards in Rank!"; Rank gets a red dot and a glow until claimed.
- 2026-10-03 (designer): Skip during game 1 keeps the game going (the bot still plays badly)
  with the guidance off; Skip asks to confirm.
- 2026-10-03 (designer): real-server nudges show one at a time, only in the lobby, and an
  ignored one comes back until clicked.
- 2026-10-03 (lane): Trade is hidden in the first server too (it sits in the same column and
  would distract from the one button the tutorial teaches); it shows with the rest in the real
  server.
- 2026-10-03 (lane): on a gamepad the tutorial puts the selection on Request opponent itself,
  so one A press works; if the player moves it off, the line says "Press Y, then A".
