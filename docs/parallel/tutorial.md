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

- **Step 4 done: game 1, the rigged match.** `Shared/Tutorial/Break` (the rack and break, found
  offline by `lune run tools/tutorial_break.luau`: seed 153, cue ball at (-25, -6), straight at
  the apex, full power; it pots 1, 6 and 7 and leaves the 4 a 3.7 degree cut into a corner),
  `Shared/Tutorial/Rig` (called by MatchEngine only for a table with `t.tutorial`: the player
  breaks from the fixed spot whatever they aim or pull, no shot clock, Magnet's pull on the
  player's own first-hit ball with nothing drawn (`Hidden`), and the 8 guard: a loss on the 8
  becomes the foul "EightBack" with the 8 put back). The bot (`Bots/Script`): it plays as if it
  had stripes while the table is open, its first visit pots one and scratches, every later
  visit is `Script.poor` (a soft legal miss that moves none of the player's balls or the 8, or
  nudges the 8 beside a pocket). `TutorialGames` sets the rig when the bot is called, counts
  the player's shots, fills the ability bar after the aim shot, publishes the lesson
  (`TutorialLesson`: Break, Aim, Ability, Pick, BallInHand, Eight) and the hand's targets, and
  makes the bot storm off (AUGHHHH!) just after the winning 8 drops, the result waiting for it
  (`BotService.stormOff`). Client: each lesson's line, dim and gesture per device; the break's
  aim locked straight; the aim lesson starts 7 degrees off its pot and says "Now pull the power
  bar to shoot!" once the player turns; the longer guideline and the strong ball outlines (the
  player's colour is solids from the break on) in game 1; the free-spin toast hides while
  Abilities is hidden.
  - Checked: lint, tests (962, new `tutorial_game_test`: the break's outcome, the engine's rigged
    break whatever the input, the hidden assist, the 8 guard, the bot's poor shots); Studio PC:
    a whole game 1 twice. The break dropped exactly 1, 6, 7 both times. A missed aim shot ->
    the bot potted a stripe, then scratched -> "Ball in hand!" with the ghost-ball drag. A potted
    aim shot -> the bar filled -> "Press G to use your ability!" (bar lit, hand) -> G -> Heat
    Seeker's pick with the hand on the best solid -> CONFIRM lit -> the shot. The bot's later
    visits were quiet misses. "SELECT WHICH POCKET!" lit the obvious open pocket (the nearer one
    was blocked) -> the 8 -> WonGame1 -> step Drop. Funnel steps 1-10 printed in order.
    Fixed on the way: the dim no longer sticks when its target hides; the drag demo heads for
    the table; the ball-in-hand lesson ends once the ball is moved; the pick lines sit under the
    pick view's own title. Not yet seen: the AUGHHHH exit on screen (it ran; the capture
    missed it; checked again with step 5's result screen), phone and gamepad runs.

- **Step 5 done: after game 1 (first server).** Server: `Items.setOpenHooks` (Bronze's
  Standard Case opens to a random Uncommon cue from the Standard Case at step Drop),
  `UltSpins.setSpinHooks` + `SpinView`'s `forced` (the starter spin lands on Magnet at step
  Spin), `Rewards.onRedeemed` (RELEASE moves Code on); `TutorialService` runs Drop -> RareDrop
  -> Abilities -> Spin -> Code -> Back -> Arrow2 from those hooks and the client's events
  (RareSeen, OpenedAbilities, ClosedAbilities). Client: the stand-in case card
  `TutorialReveal` ("You got a Standard Case!" + Open now, then "You got a Rare Case!" with its
  timer + OK) until GUI's 8-ball is merged; the hand on Open now, OK, Abilities, SPIN, the code
  box (phone: the Odds button first), Back; on the full-screen Abilities menu the line sits
  just over the lit button ("Near") so the menu's title stays readable. NEW RANK! shows the
  gold "Claim your rewards in Rank!" line with nothing flying when the rewards are held.
  - Checked: lint, tests (962); Studio PC: a whole game 1 won -> step Drop -> the card with the
    hand on Open now -> the case opening landed on the Hornet Cue (Uncommon) -> the Rare card
    ("Opens in 59:xx") -> OK -> the hand on Abilities -> SPIN landed on Magnet (twice) ->
    "Type RELEASE for 3 more spins!" on the code box -> RELEASE gave 3 spins -> "Click Back!"
    -> Back -> Arrow2 with a new table reserved. Funnel 11-14 printed in order; console clean.
    Fixed on the way: the hole and hand sat 58 px too high on screens that ignore the top-bar
    inset (every ScreenGui's AbsolutePosition starts under the bar, so the overlay now always
    adds the inset); the card's picture was blank and the card covered the hand; the Rare
    timer read an older Rare timer (now the newest). Not yet seen on screen: the result screen,
    NEW RANK! with the claim line, and the AUGHHHH exit (they ran; the captures came after);
    phone and gamepad. All three go into step 10's full run.

- **Step 6 done: game 2.** After Back the arrow leads to a newly reserved 1v1 pad; on it the host card
  shows only Join Global Queue (dim, hand, per-device words). The search goes into the real
  global queue, and for a player at step Queue the Bots lane's fallback (a disguised bot of
  the player's tier, Bronze by now, no rematch) comes after 1 s instead of 10 s
  (`BotService.setFallbackWait`, `Config.Tutorial.Games.Game2BotAfterSeconds`); "Finding you an
  opponent..." meanwhile (funnel 15 JoinedGlobalQueue). The arena loads the save at Queue as
  Game2 (`Steps.resume`). When game 2's result shows, a win is funnel 16 WonGame2 and a loss is
  the side event TutorialLostGame2, and the step becomes Lobby. The post-match row shows only
  Lobby (no Rematch, no Play another), with the hand and "Click Lobby!". Back in a lobby
  server, Lobby resumes as Nudges (step 7). While Free Reward is hidden, the result screen
  shows no daily-reward line.
  - Checked: lint, tests (962; steps test: the arena resume); Studio PC lobby: Arrow2 -> the
    pad -> "Click Join Global Queue!" with the hand on the only button; the search itself
    cannot start in this unpublished place (no MemoryStore: "could not start a search:
    Store"). Studio arena (StudioArena 1 + StudioArenaBot Bronze, removed afterwards): Game2 ->
    the game against a disguised Bronze bot -> a forfeit -> TutorialLostGame2 -> Lobby -> the
    row with Lobby alone, hand and line -> Lobby -> "Studio cannot teleport ... back to the
    lobby". Console clean. Fixed on the way: the arena no longer runs the lobby's pad rules,
    the "Opponent left" line is gone while Rematch is hidden, and so is the daily-reward
    reminder while Free Reward is hidden.
  - **Needs the published game** (integrator or designer): the search becoming the bot match
    after 1 s, the teleport into the arena with the step at Game2, a win (funnel 16), and
    Lobby back to a public server with the step at Nudges.

- **Step 7 done: the real server.** Entering Nudges releases the held day-1 claim, which
  comes with GUI's daily popup (funnel 18, logged after 17 BackInLobby). Then the nudges come
  one at a time (`Steps.nudge`, server `TutorialService`; the player attribute TutorialNudge,
  blank while the player is on a table's pad or seat). Each shows the hand, the light dim and
  a line on its button: Rank ("Claim your rank rewards!"; skipped when nothing is held; inside
  Rank the hand moves to CLAIM), Inventory ("Your Rare Case opens when its timer ends!"),
  Shop ("Check out the Shop!") and Free Reward ("Claim your free reward!"). A nudge is answered
  by opening its menu (Rank by the claim) and stays until it is. A popup or another menu hides
  it for the moment. The Rare Case pill beside Inventory (`TutorialCasePill`) shows the case
  and "28:52", then a breathing gold "Ready!". Then "Your case is ready!" with the hand on
  Inventory, and opening Inventory is Done. The server keeps the case's time in
  Flags.TutorialCase (an ended timer leaves the save's Timers), follows a skipped or halved
  timer, and drops the case nudge if the case is opened first (funnel 20 OpenedRareCase).
  - **The rank claim for everyone** (`RankClaimBlock`): with rewards held, Rank (the roadmap)
    shows a small card at its foot: "Rewards ready!", chips (money, cases, Case Drops, spins,
    cue, chat tag) and CLAIM. CLAIM is paid by the server (RankClaimService); the roadmap
    closes, the money flies into the money HUD (which counts up), and the spins, cases and
    cue fly into Abilities and Inventory (RewardsFlyer). The server now also publishes
    RankClaimed for the chips.
  - The hand turns round and points up when its target is too near the top of the screen
    (the Rank HUD).
  - Checked: lint, tests (963; steps test: the nudge order); Studio PC: /xp to Bronze held its
    rewards -> NEW RANK! with "Claim your rewards in Rank!" -> the Rank nudge (hand turned up)
    -> Rank -> the claim block -> CLAIM -> $5,500 and the spin flew, money counted up, tag on
    -> Inventory, Shop, Free Reward nudges in order, each answered by opening it -> CaseWait
    with the pill counting -> /skiptime -> "Your case is ready!" + "Ready!" pill -> Inventory
    -> Done. Console clean. Not yet: phone and gamepad (step 10).

- **Step 8 done: skip, cancel and resume** (nothing new to build; checked). Skip tutorial
  asks "Skip the tutorial?" Yes / No. Yes ends it (Skipped). Stepping on another table ends
  it at once (Cancelled, "OtherTable"); a second real player on the pad before the bot comes
  is "Friend". Either way everything shows, the held day-1 claim comes (funnel 18) and
  TutorialExit logs why. Skipped in game 1, the game goes on with no guidance, and the bot
  keeps playing badly with the 8 guard on: the rig stays on the table until that game ends.
  The first win is then the normal one: Bronze held, its drop rolled normally (not the
  forced Standard), the Rare Case, and the GUI popups, since TutorialActive is off.
  Resume: game 1 starts over from the arrow, the queue goes back to game 2's arrow, and every
  other step resumes where it was (Steps.resume, tested).
  - Checked: Studio PC: Arrow1 -> stepped on table 5 instead of the reserved 2 -> Cancelled,
    the full host card and all menus, ClaimedDaily, TutorialExit LeftOtherTable. A real game 1
    -> the aim lesson -> Skip -> "Skip the tutorial?" -> Yes -> Skipped, guidance gone, the
    same game still on, TutorialExit LeftSkip, ClaimedDaily. Console clean.
  - **For the designer by hand**: a friend stepping on the pad with a new player (needs two
    players), and leaving then rejoining at each step (Studio's test saves reset on Stop, so a
    real rejoin needs the published game).

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
- `Rules/MatchEngine.luau` (step 4): requires `Tutorial.Rig`; `setup`'s `timed` also asks
  `TutorialRig.timed`; `beginTurn` (a block before `t.ballInHand = hand`), `acceptShot` (a block
  after the `sim` clone; the assist when no ult is armed), `finalizeShot` (the judgement through
  `TutorialRig.judge`) and `resolve` (the `eightBack` block after `respotEight`), each only for
  a table with `t.tutorial`.
- `Bots/Script.luau` (step 4, this lane owns the script): requires `Tutorial.Break`;
  `Script.Visits` names "Poor"; new `tutorialView` and `poor` at the end (eightBlunder stays).
- `Bots/Driver.luau` (step 4): `decide` uses `tutorialView`, and every visit after the first
  plays `poor` (was eightBlunder on visit 2).
- `Bots/BotService.luau` (step 4): new `BotService.stormOff` before `ended`.
- `MagnetFx.luau` and `AbilityFx.luau` (step 4): a Magnet shot with `overrides.Hidden` draws
  nothing (one condition each).
- `PowerCue.luau`, `UltHud.luau`, `UltPick.luau`, `MatchTargets.luau` (step 4): require
  `TutorialAnchors`; one-line registrations (PowerBar, UltButton, UltConfirm, PickBall<id>,
  Pocket<id>, CueBallHandle); UltPick also sets the `UltPicked` flag in `update`.
- `Input.luau` (step 4): requires `TutorialAnchors`; `rotate` does nothing while the tutorial
  locks the aim, and notes the turn.
- `Main.client.luau` (step 4): requires `TutorialAnchors`; `renderFrame` applies an aim the
  tutorial asked for; `highlightOwn` uses the strong style and solids in game 1.
- `Guideline.luau` (step 4): requires `TutorialAnchors`; game 1 uses `TutorialStubLengthInches`.
- `Reminders.luau` (step 4): the free-spin toast waits while the tutorial hides Abilities.
- `Strings.luau` (step 4): `Match.FoulShort.EightBack` and `Match.FoulReasons.EightBack`.
- `Items.luau` (step 5): `openForce`/`onOpened` locals and `Items.setOpenHooks`; `OpenCase`
  uses the forced cues when the hook gives exactly one per case, and calls `onOpened` after.
- `Ults/SpinView.luau` (step 5): `SpinOptions.forced`; after `Roll.roll` a forced id replaces
  the roll (no pity credit).
- `PlayerData.luau` (step 5): `ultSpin` takes `forced: string?` (last parameter) into the
  SpinView options.
- `UltSpins.luau` (step 5): `UltSpins.setSpinHooks`; `spinOnce` passes the forced id (normal
  spins only) and calls `onSpun`.
- `Rewards.luau` (step 5): `redeemed` local and `Rewards.onRedeemed` before `onRewardRequest`;
  a successful Redeem spawns it.
- `NewRankPopup.luau` (step 5): with `event.held`, a `ClaimLine` label under the chips, the card
  one line taller, and no item flights. `ResultScreen.luau`: passes `held` on the rank event.
- `UltScreen.luau` (step 5): requires `TutorialAnchors`; anchors `UltOddsButton`, `SpinBack`,
  `SpinButton`, probe `UltSpinning`. `UltOdds.luau`: anchor `CodeBox`.
- `Progression.luau` (step 5): `Progression.openCase(caseId)` and `Progression.caseOpeningUp()`.
- `Bots/BotService.luau` (step 6): `fallbackWait` local and `BotService.setFallbackWait` after
  `fallbackBusy`; `watchSearches` asks it for a solo search's wait (three lines).
- `PostMatch.luau` (step 6): requires `TutorialAnchors`; anchor `Lobby`; `set` drops buttons the
  tutorial hides (Rematch, Another, Cancel in game 2) and the "Opponent left" line with them.
- `Reminders.luau` (step 6): `Reminders.line` answers nil while the tutorial hides Free Reward.
- `Progression.luau` (step 7): requires `RankClaimBlock`; builds it after `TradeMenu.new`
  (four lines).
- `RankClaimService.luau` (step 7): `refresh` also sets the RankClaimed attribute.
- `TutorialHand.luau` (step 7, this lane's): `placeHand` takes `flipped`.
- `Config.luau` / `Strings.luau` (step 5): only inside this lane's `Tutorial` blocks
  (BronzeCueRarity, SpinUlt, Reveal, Overlay.LineNearGapPx; the step 5 lines).
- Tests changed for the new values: `ranks_test`, `save_schema_test`, `ult_slots_test`,
  `ult_spins_test`; `tools/economy_config.json` re-exported.

## Requests to other lanes or the integrator

- **GUI**: (1) keep the one-line `TutorialAnchors.set(...)` registrations and the column's
  hidden-tile check through your rework, so the tutorial's hand finds your buttons; (2) the
  rank claim block on the roadmap is built in your style kit as a small block: restyle it
  freely, keep its claim call; (3) `Popups` waits while the player attribute `TutorialActive`
  is true (as your brief already plans); (4) the Rank button shows a red dot and a glow while
  the player attribute `RankPending` is true; (5) a UI_STYLE line: the tutorial's light dim is
  a deliberate exception to "popups never darken" (designer, 2026-10-03); (6) step 5 (after
  game 1) uses a stand-in case card (`TutorialReveal`) because the 8-ball (`MagicBall`) is in
  `lane-gui` only. Once merged, please: (a) add `MagicBall.play(list, done)` that shows at once
  without the popup queue (the tutorial calls it for Bronze's Standard Case and then the Rare
  Case), and register its buttons with `TutorialAnchors.set("OpenNow", ...)` and
  `TutorialAnchors.set("RevealOk", ...)`; (b) skip `MagicBall.push` for drops while
  `TutorialActive` is true (the tutorial shows them itself; otherwise they show again in the
  real server); the integrator then points `TutorialReveal.show` at `MagicBall.play`. (7) Your
  NEW RANK! rework: keep the `held` line ("Claim your rewards in Rank!", nothing flies) this
  lane added to `NewRankPopup`, and the one-line anchors in `UltScreen` / `UltOdds` (SpinButton,
  SpinBack, UltOddsButton, CodeBox) and the `UltSpinning` probe. (8) Your Rewards change (the
  server claims every day on join) must keep this lane's claim gate: no claim while the
  player is in the tutorial's first server (`Rewards.setClaimGate`).
- **Integrator**: a VIP account gets $5,000 on its very first join anyway: the VIP Cue enters
  its Index and pays the Exclusive finder's money (`Config.Index.FindMoney.Exclusive` 5000, via
  `Store` -> `PlayerData.giveVipCue`). The designer's Studio account is VIP, so a Studio test
  of "no money on join" shows $5,000; a normal new player starts at $0. Left as is (not this
  lane's rule); ask the designer whether VIP's cue should pay finder's money.
- **GUI** (step 7): the rank claim block (`RankClaimBlock`, a card at the roadmap's foot) and
  the Rare Case pill beside Inventory (`TutorialCasePill`) are stand-ins in the kit's style:
  restyle or move them freely, keep the CLAIM call (RankClaim remote), the `RankClaim` and
  `Inventory` anchors, and the TutorialCaseAt attribute the pill reads.
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
- 2026-10-03 (lane): game 1 has no shot clock (a first game, no hurry); the bot plays as if it
  had stripes while the table is open, so its pot never takes the player's colour.
- 2026-10-03 (lane): game 1's assist is Magnet's own effect on the player's first-hit ball
  (theirs, or the 8 toward the called pocket), hidden; there is no separate stronger 8 pull,
  since the bot's nudge and the guard already make the 8 safe.
- 2026-10-03 (lane): the starter spin is forced to Magnet on the first normal spin at step Spin;
  the existing daily free spin stays, so a new player has one spin left after the tutorial's
  spin (plus RELEASE's 3).
- 2026-10-03 (lane): on the Abilities screen the tutorial's line sits just over the lit button
  instead of at the top, where it covered the menu's ability name.
- 2026-10-03 (lane): game 2's search goes through the real global queue (a real Bronze player
  who happens to search in that second is a fair game 2 too); only the bot's wait is cut to
  1 s. A direct bot match that skips the queue would need a fake search inside TableService.
- 2026-10-03 (lane): in the first server the result screen shows no daily-reward line (Free
  Reward is hidden and its claim waits for the real server).
- 2026-10-03 (lane): the nudges' "lobby only" means not on a table's pad or seat; a popup or
  an open menu also holds a nudge back for the moment. The Rank nudge is skipped when nothing
  is held (claimed already), and a later rank-up does not bring it back.
- 2026-10-03 (lane): the tutorial ends (Done) when "Your case is ready!" is answered; if the
  Rare Case is opened first, the case part is simply over.
- 2026-10-03 (lane): CLAIM closes Rank so the rewards are seen flying into the money HUD,
  Abilities and Inventory.
