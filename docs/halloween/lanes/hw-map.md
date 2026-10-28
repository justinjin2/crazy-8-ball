# Lane hw-map (W5): Map + Pumpkin King

Folder `~/Desktop/8ball-hw-map`, branch `hw-map`, Rojo 34886, Studio `place/lane-hw-map.rbxl`,
Opus 5.5 · xhigh. Brief: `docs/prompts/HW_MAP_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.

Launch and restart: the command printed by `tools/halloween/lanes.sh command hw-map` (never your
own flags). Waiting for Justin (before 11:00 only):
`touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (not `.git/overnight-waiting`).

## Owns

From PLAN §4 (everything else is read-only to this lane; ask through Requests):

- `Config.HalloweenMap`: the Night preset settings, skybox ids, table looks by mode, the decor
  kit, the props replace-list and placements, candy-drop spawning, the King's look, throne,
  difficulty and MaxAtOnce.
- `Config.Lighting.Night` (the preset itself, same keys as Day) and the event lighting helpers in
  `src/shared/LightCycle.luau` (`LightCycle.event`, `mixStates`) and `src/client/DayCycle.luau`.
- `TableBuilder.addDecor` (`src/shared/TableBuilder.luau`).
- Event props, as `.rbxm` under `src/server/HalloweenMap/Assets/` or built by code; their Blender
  scripts and exports under `assets/halloween/map/`; the `night` light of `assets/map/gen_sky.py`.
- The King's body, head, crown, cape, throne and prompt (`src/server/HalloweenMap/KingLook.luau`,
  `src/client/HalloweenMap/`).
- `src/server/HalloweenMap/BossService.luau`, `EventMap.luau`, `CandyDrop.luau` (a copy of
  MoneyRain), `src/shared/HalloweenMap/Rules.luau`, `tests/halloween_map_test.luau`,
  `tools/halloween/hw_map_cloth_check.py`, `tools/upload_manifest_hw_map.json`.
- The BotService boss hooks (`src/server/Bots/BotService.luau` spawn/seatInfo/attributesOf/
  playBoss/BotsQA "boss", `src/server/Bots/Body.luau` animations and dress arguments,
  `src/client/People.luau` portrait icon).
- `Strings.HalloweenMap`; the Net remotes `HalloweenMapFx` and `KingChallenge`.

## Interfaces

- Switch keys core's quest fallbacks read (always booleans, false until verified):
  `Config.HalloweenMap.Enabled` (master), `Config.HalloweenMap.Boss.Enabled`,
  `Config.HalloweenMap.Candy.Enabled`; core uses `HM.Enabled and HM.Boss.Enabled` and
  `HM.Enabled and HM.Candy.Enabled`.
- No hour-cap key here: the pickup cap lives only in `Config.Halloween.Pickup.HourCap` (core),
  enforced by `CandyService.pickup(player) -> (ok, reason: "Cap" | "NotLive" | "NotLoaded" | nil)`;
  the bag-full note shows only for `"Cap"`.
- Consumed from core: `Config.Halloween.CandyIcon`, `CandyService.bossCooldown(player) -> number`
  (unix seconds, 0 if none), `bossWon`, `isLive`, `Event.state(Clock.now())`, player attribute `HwOn`.
- Attributes: `PumpkinKingReadyAt` on players (unix seconds his cooldown ends, from core's
  `bossCooldown`/`bossWon`; `Config.HalloweenMap.Boss.ReadyAttribute`); on workspace
  `HalloweenMapState` (string: "Before" | "Countdown" | "Live" | "Ended") and `HalloweenMapFlipAt`
  (server time of the last change) (`Config.HalloweenMap.StateAttribute`/`FlipAtAttribute`);
  Studio-only force: workspace `HalloweenMapForce` (a state name).
- Net: `HalloweenMapFx` (server -> clients: `{ kind = "Burst" | "Pickup" | "BagFull", ... }`),
  `KingChallenge` (client -> server, no arguments).
- `Config.HalloweenMap.Props.Budget.Lights = 6` (throne 2 + the throne King's aura 1 + 3 table Kings).

## Status
- 12:24 hw-map: **READY @88e9cceb**: the 12:16 BLOCKER fixed (c1e75749), halloween @5dae747d
  merged in (clean), lint OK, 1,462 tests. Cause as the review found: EventMap's first Live pass
  waited on the meshes in the props, BossService's addPart turned the throne on on Bootstrap's
  thread, and the resuming pass reached the new part too; both passed `built == nil`. Fix:
  `HalloweenMap.Once` (a build runs once however many ask; the second waits for it) for the
  throne and the props; an off during the wait wins over the waiting on; `turnOn` walks the
  parts as they were and `addPart` turns a late part on in its own thread (Bootstrap no longer
  waits on the meshes). Test: two ons at once build once (two without the guard), plus retry
  and error cases. Studio: three Plays into Live, one throne and one King each; a forced Ended
  left none, the piano and the props back; Live again one; on the merged tree once more one,
  console clean.
- 12:15 coordinator: `halloween` @5dae747d adds map 7fd462cc + 39815514 (night rooftop, King, drops, /king), core d7120fac (the 11:30 review fixed, the Rush chip names what runs) and gui c9f01ea6 (the boost lines restyle, VIP perks in the Soft step). The contract test is now STRICT. Lint OK, 1,460 tests, Team Create play console clean (shots/coordinator/merge_5dae747d_boost_lines.jpg). Known blocker sent to map: the throne builds twice on a server that starts during Live. Run `git fetch && git merge origin/halloween` before your next READY.
- 12:03 hw-map: **READY @39815514** (step 21): halloween @02e046e1 merged in (clean), lint OK,
  1,459 tests, Studio boot on the merged tree: Live, 16 tables with the look, 44 decor pieces,
  51 props, the throne; console clean but for the Studio store lines, the known 203785492 ones
  and `1621084` (the tutorial bot's random avatar, not in src). New since READY 7fd462cc:
  aaaffdbe and 9af68c6a (King notices fit the card, a test), 10489ad6 (`LocalSearch.isPromised`),
  b86b9142 (the designer's `/king [tier]`), lane-file updates. All 21 steps ticked.
- 11:59 hw-map: **Status final** (step 20). Everything below is on (`Config.HalloweenMap`, all
  eight switches true), follows core's Event.state and was checked in my Studio window:
  - **Night**: while Live the event light takes Day's slot of the cycle (Countdown preloads the
    sky, a flip fades over FlipSeconds, a mid-event join sees it at once); after Live, Config's
    own light. Roof brightness L* 0.91 of Day's.
  - **Tables**: orchid 1v1 (185,90,230), charcoal 2v2 (90,94,102), toxic green 3v3 (88,176,32)
    on black frames; rendered ΔE 24.6 / 28.4 / 19.9 (all ≥ 17); decor kits Orchid, Pumpkin,
    Toxic inside the body footprint; arenas get the look and the kit; all restored after.
  - **Props**: dead trees in the palms' pots, spooky planters, 6 strands, 4 cobwebs, 2 pumpkin
    clusters; 18 palms, 12 fern planters and 9 beds put away and back. Budget: 47,786 of 60,000
    triangles, 112 of 130 MeshParts, 3 of 6 lights.
  - **The Pumpkin King**: the throne at the piano spot, his own look and portrait, the prompt
    (hold E, tap, X; "Ready in m:ss" on cooldown), real King matches by tier (won, lost, left
    logged; a win pays core's Candy and starts the cooldown), the +50 CANDY burst, the
    designer's `/king [tier]`; he skips tables a local search promised.
  - **Candy**: pieces near eligible players (HwOn, the lobby), +1 on pickup to core's
    CandyService (its hour cap), animated within 160 studs (60 on Lower effects).
  - Checked on: PC in my window; the fresh-player run (tutorial, Skip, first match, the prompt
    after). Phone, iPad, TV and the pad: nothing I add depends on the screen size (step 18), so
    the four-size screenshots and the X glyph are the coordinator's sweep.
  - Shared files: the list under Shared-file changes (all landed lines with their commits).
  - Needs: Justin's gate 2 throne answer (staying at the piano spot until then, see
    Assumptions); the coordinator's device sweep. Not mine, seen while testing: `RequestLeave`
    has no server handler (cleanup list); the King's Jack-o'-Lantern Cue body piece is not in
    my window's CuePieces (cues-a's asset; drawn with the shared mesh here).
- 11:54 hw-map: step 19 done (fresh-player run, Studio, a new save each Play). Core's BootLive
  puts the clock at Live + 60 s: the join shows the Night sky, orchid tables, dead trees and
  strands (fresh `01`). In the tutorial `HwOn` is false: the King prompt exists but is off (no
  prompt UI is even made) and no candy spawns near the player. The first match is on table 2,
  orchid, balls readable (fresh `02`). Skip mid-match: `HwOn` turns true, the prompt stays off
  while seated; after the match (Surrender) it is on within 3 s and shows at the throne (fresh
  `03`, behind the result card until Continue). Console clean (Studio store lines and the known
  203785492 ones). Notes for the sweep: (a) the MCP resets CameraType after every execute_luau,
  which undid the game's own camera return after the match, and a prompt only shows in view:
  a test artifact; (b) `RequestLeave` (Hub.requestLeave) has no server handler: a dead remote,
  not mine, for the cleanup list; (c) one earlier run's Play stopped by itself about 20 s after
  its tutorial match ended on its own after Skip (HwMatch, HwCandy 77, a Mystery block; no error,
  no kick line). The same path ran clean once more; not reproduced.
- 11:54 hw-map: step 18 done as far as one window allows (aaaffdbe notices, 9af68c6a test).
  Nothing I add depends on the screen size: the prompt is Roblox's default (fixed px; tap works,
  ClickablePrompt), the queue card is a fixed 320 px with no UIScale, the +1/+50 billboards are
  sized in studs, the portrait is a square image in the gui lane's MatchHUD slot. Measured in
  Studio (TextService, FredokaOne 18 px, 300 px of text room): KingBusy 295, KingNoTable 311
  (about 17 px), KingCooldown 267, KingNotNow 286; the new test holds them to 43 characters.
  devices/ `01`-`04` as above, `05` the +1 and +50 CANDY billboards (the board clips the +50 only
  because the shot copy has AlwaysOnTop off). Left to the coordinator's sweep: the four-size
  screenshots (the resize helper is blocked) and the pad's X glyph (Roblox's prompt follows the
  real last input; GetImageForKeyCode(ButtonX) resolves to DefaultController/ButtonX@2x.png;
  GuiQA "pad" drives only our PadMode).
- 11:49 coordinator: `halloween` @64085ab2 adds core de236025 (the NEW CUE! card and end screen count in Progression.quiet) and cues-b a431419b (Witch Broom, Black Cat and Spider out of draft). cue_skins_data.py clean on halloween (66 skins, 28 pieces). Lint OK, 1,441 tests, Team Create play console clean. Map's READY 7fd462cc is next. Run `git fetch && git merge origin/halloween` before your next READY.
- 11:45 hw-map: **READY @7fd462cc** for merge pass 1: steps 1-17 (5 now too; all Studio-checked), with
  halloween @070893de merged in (clean, no conflicts). Lint OK, 1,453 tests. Step 18 (devices)
  is partly done and left for later as asked; 19-21 follow.
- 11:45 hw-map: step 5 done (7fd462cc): the CONTRACT CHANGE in one commit: the 3v3 cloth is
  (88,176,32) in Config, `tests/config_test.luau`, `tests/halloween_contract_test.luau:252` and
  `tools/halloween/hw_map_cloth_check.py` (`--raw`: 3v3's nearest ball 31.6; rendered under Night
  19.9, gate1 `12`). Studio after the merge: Tables 15 and 16 wear (88,176,32) with the Toxic
  kit while Live (gate1 `13-3v3-88-176-32-merged`), console clean (only the Studio store lines
  and the known 203785492 ContentId ones). Brief §2.4 and its Config block updated to match.
- 11:45 hw-map: step 18 so far (not ticked). aaaffdbe shortens the four King notices, so each
  fits the queue card on one line (it is min(StatusWidth 320, screen - 20) px, so the same on
  a phone). Shots at my window's size (devices/): `01` the prompt's "Ready in 11:11", `02`
  "Challenge the Pumpkin King", `03` the KingNoTable notice, `04` the King's pumpkin portrait in
  the match bar. Notes: the MCP capture leaves out AlwaysOnTop billboards (STUDIO_NOTES), so
  the prompt shots set the prompt's AlwaysOnTop off on the client; the +1/+50 billboards are
  sized in studs (TextScaled), so no screen size changes them. Left: the four sizes by Root-frame
  emulation (the resize helper is blocked: the Studio windows are on another Space), and the pad:
  the prompt is Roblox's default UI with GamepadKeyCode ButtonX, which follows the real last
  input, not GuiQA "pad" (PadMode is our UI's flag only), so the X glyph needs a real controller
  or the coordinator's sweep.
- 11:41 coordinator: **CONTRACT CHANGE: go with (88,176,32)** (the same hue at 80% lightness, ΔE 19.9, the brief's §2.4 rule). PLAN §2 Tables updated (halloween @ the PLAN commit after 8a104005). In ONE commit change Config, your tests, the cloth tool **and** `tests/halloween_contract_test.luau` line 252 (`rgb(by[3].Cloth, 88, 176, 32)`), so `halloween` stays green when it merges. Include it in your READY for the 12:00 pass.
- 11:42 coordinator: merge pass 1 is at 12:00. Post a `READY @<sha>` line (pushed, with halloween @537270fd merged in) for your Studio-checked steps through 17, and I'll merge it then. Leave the device step (18) for later; real window resizing is still blocked (the Studio windows are on another Space), so use Root-frame emulation like core and cues-a did.
- 11:36 coordinator: `halloween` @537270fd has cues-a 83e876db (drop 3 body path, CuePreview bodies, Candy Corn + Jack-o'-Lantern, Upright, analytics, Aim-fade fix), core 3c4b87aa (event menu, tile, quests, Spider, packs, art), sys c5b6b607 and gui 3438ea94 (review fixes). Lint OK, 1,436 tests, Team Create play console clean (only the known 203785492 ContentId lines), tile + 2x chip + pill +120% seen. Review of this merge is running; findings come back as Requests. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare.

- 11:32 hw-map: step 17 done (f61bb19a). All eight `Config.HalloweenMap` switches are true
  (the map still follows core's Event.state: nothing before the event, all gone after). Each
  checked in Studio, Live, with only it off: master (no state attribute, the normal cycle, nothing
  up, no prompt), Night (the normal cycle's sky and exposure; all else on), Tables (today's
  cloth; the kits still on), Decor (looks, no kits), Props (the 41 palms and planters stay),
  Throne (the piano stays; no prompt), Boss (no throne either), Candy (none in a 45 s walk).
  Found: the King's prompt lives on the throne, so Throne off with Boss on would leave core's
  King quest unfinishable; a test now holds Boss on only with Throne on, and the switches say
  "switch both off together". Now: devices (18).
- 11:24 hw-map: step 16 done. **Counts** (step 14's, Studio): 47,786 triangles of 60,000, 112
  MeshParts of 130, 16 unique meshes (OVERRULED), 3 lights of 6; every event MeshPart is
  RenderFidelity Automatic (Roblox's own LOD on weak devices), touches nothing, is never
  queried and casts no shadow (103 checked). **Client, on vs off** (Play, one camera over the
  lobby, 4 s each): draw calls 445 / 504 Live vs 483 Before, scene triangles 439.5k / 491.6k vs
  467.6k: the day cycle's light moves them more than the event does; graphics mesh memory 4.2
  MB both ways; +470 instances. Frame time could not be told apart here: the lane window renders
  in the background, throttled to 15 fps both ways (RenderCPU/GPUFrameTime read 0 in Studio).
  **Low quality:** the burst, candy sparkles and the King's aura already halve or go; new
  (aa8c2804): the per-frame candy float only within `AnimateStudsLow` 60 studs with Lower
  effects (160 otherwise; it was a hardcoded 160), checked in Studio through SettingsState.
  **Server:** heartbeat time 0.098 / 0.094 ms Live vs 0.108 ms Before (one player); the map's
  loops are the 1 s state poll, the 1 s King and candy spawn ticks, and the 0.2 s pickup check
  (at most 40 candies x players, distance only); nothing per frame. Now: switches (17).
- 11:20 hw-map: step 15 done (the full flip test, Studio, switches on in the working tree only).
  Lobby, one Play session, server parts and the client's light read at each state: Before (no
  look, kit, prop, throne; the 41 Models and the piano in the map; client Day sky, exposure
  -0.05) -> Countdown (the same; the six Night faces fetched) -> Live (16 looks, 16 kits, 51
  props, the throne, 39 Models hidden; client Night sky, exposure 0.45, sun at 7.4; the King's
  prompt on once `HwOn` is set) -> Ended (all back as Before) -> Live (all on again) -> force
  cleared (core's clock keeps it Live). Boot during Live: every Play start (FlipAt 0, no fade).
  Arena (`StudioArena` 1): boots Live, its one table orchid (185,90,230) with the Orchid kit, no
  props, hides, throne, prompt or candy, client Night; Ended gives back the Blue look's cloth and
  takes the kit; Live again re-dresses it. Console clean of map lines in both (the only new line,
  asset 1668310 "not approved", is not ours: an avatar asset). Now: performance (16).
- 11:17 hw-map: step 14 done (68dbca8e meshes, ebfbe1f7 MapProps, d8d0f166 budget). While Live
  the lobby hides its 18 palms, 12 fern planters and 9 planter beds (found in the window:
  `Palm_N` x18 Models, `FernPlanter_N` x12, `PlanterBed_N` x11 of which 42 and 48 are the
  portals'; their pots `PalmPlanter_N` and collision twins stay; the piano is the throne's own
  hide). Each palm's pot grows a dead tree (scaled to the palm, leaning inward, its lanterns
  glowing); each planter becomes a dark box in its pot's place with a dressing on top (beds: two
  tombstones, two dead bushes, three jack-o'-lanterns; pots: a bush and a jack-o'-lantern); six
  strings of lights (orange, purple) hang under the pergola's front and middle beams, cobwebs in
  its four front corners, pumpkin clusters at the throne's two lanterns. Flip test: Live 51
  props and 39 hidden; Ended and Before put all 41 Models and the piano back; Live again the
  same. **Budget** (counted in Studio, Live, lobby at rest): 47,786 triangles of 60,000, 112
  MeshParts of 130, 16 unique meshes (OVERRULED below), 3 lights of 6 (throne 2, aura 1);
  first count was 159 MeshParts, fixed by merging each table's pairs into one mesh and the
  throne's small pumpkins into the one-piece mesh. Worst case on top: 40 candies (9,760 tris,
  40 MeshParts) and 3 table Kings (2,520, 9) while they last. Shots: `shots/hw-map/props/01-03`,
  `decor/04`. Now: the flip test with an arena (15).
- 11:00 hw-map: step 13 done (28fd816f meshes, fa43df20 kits). Every table wears its mode's
  kit while Live, arenas too, and loses it at the end: Orchid 1v1 (purple underglow, two glowing
  bats on the long aprons; 3 parts, 196 tris), Pumpkin 2v2 (orange underglow, trim ring under
  the rail line, bats, four small jack-o'-lanterns by the legs; 8 parts, 956 tris), Toxic 3v3
  (green underglow, trim, bats, cobwebs in two opposite corners; 6 parts, 676 tris). Studio: all
  16 tables built (74 parts), every piece passed `Rules.decorInside` (no warnings), a forced
  Ended removed every kit and look, Live again put the same 74 back, Live twice changed nothing.
  New meshes in the props GLB (re-uploaded, Model 113325392217599): PumpkinSmall (182 tris, one
  piece) and Trim. Shots: `shots/hw-map/decor/01-03`. Now: props and hides (14).
- 10:55 hw-map: step 11 done. Candy walk test (5 min, the player walked by Humanoid:MoveTo, core
  live): 4 candies spawned near the moving player, all 4 picked up by walking over them, core's
  save PickCount 4 and Earned +4 (+1 each); none while idle. About one per 30 s of eligible
  lobby time, as the brief sets (a lobby-only player reaches core's 40/hour cap; ~25/hour for a
  typical player). The lobby candy is the event mesh (`shots/hw-map/candy-lobby.jpg`).
- 10:45 hw-map: merged halloween @f32c3d1b (core's CandyService, sys's badges; lint OK, 1418
  tests). With core live in Studio (BootLive) the King's whole chain works: prompt, match, a
  staged real win -> `Won`, core's save Earned 50, KingPaid 1, KingWins 1, cooldown 15:00 on
  `PumpkinKingReadyAt` and the prompt's "Ready in 14:30". Fixes found by testing: a win never
  paid (a38b71e1), the King sat backwards (8df3864c), see-through pumpkin eyes and a floating
  crown (c88e894c), core's clock for the cooldown (a5b303ba). New: candy meshes in the lobby
  and the burst (6925d850), the King's portrait and Vampire idle (4bf19ec7). Steps 3, 4, 6-10, 12
  ticked; 5 waits on the CONTRACT CHANGE (3v3 tint). Still stand-ins in Studio: `HwOn` set by
  hand (core's client state not built yet). Now: the candy walk test, then decor kits (13).
- 09:50 hw-map: pushed ea730d46. Merged halloween @403da7da (lint OK, 1382 tests). Done since
  08:50: Rules + tests (step 2), the Night sky uploaded (6 faces), Night/LightCycle.event/
  DayCycle crossfade, EventMap and the table looks, the King end to end in code (BotService
  hooks, KingLook, BossService, taunts, reward), CandyDrop + MapFx, the event meshes (one GLB,
  Model 137550009666802; King head, crown, throne from them), the coordinator's two requests
  (Main `do...end`, Night in map_config_test). Step 9 done: difficulty table under Assumptions,
  top three rows stepped down to a Grandmaster King (OVERRULED line). **Blocked on Studio:** the
  lane window's Rojo plugin dropped again ("Disconnected from an error: WebSocket error: 400"),
  so steps 3-5, 7-8 and the gate 1 shots wait for a Connect.
- 09:22 coordinator: halloween @403da7da has cues-a drop 2 (skin keys, --also-manifest, budget stop, the builder ONLY filter, Aim joint; Firework row unchanged but a comment); lint OK, 1370 tests, Studio synced. Run `git fetch && git merge origin/halloween`. Cues B: you can generate rows now.
- 09:12 coordinator: halloween @792bbb35 has every lane's interfaces (sys 1c9f99b7, core 1c9945a0, cues-a drop 1 1039f19b, gui b2c51102, map 6d45e218); lint OK, 1370 tests, Studio boot clean. Run `git fetch && git merge origin/halloween` now. Gate 1 is at 10:00: shots + one caption line each in your Gate shots by 09:55.
- 09:12 coordinator REQUESTS: (1) wrap your Main.client block in `do ... end` (it adds 2 top-level locals; Main is near Luau's 200 limit; see the 09:05 line). (2) add "Night" to the lighting-state loop in tests/map_config_test.luau:167 so a typo'd Night sky id fails a test. Your ROJO RECONNECT: done 08:55 (Justin reconnected; Studio pid 17672 on 34886).
- 09:05 coordinator REQUEST (all lanes, blocks a merge): `src/client/Main.client.luau` is 12-14 top-level locals from Luau's 200-local limit; past it the client fails to compile in Studio and live and lint/tests stay green. Put every Main.client addition inside `do ... end` (zero new top-level locals), e.g. `do local ok, err = pcall(...) ... end`. New test `tests/client_compiles_test.luau` (on halloween @HEAD) compiles every src script and fails if Main.client has fewer than 8 locals left; run it before you push.
- 08:50 interfaces pushed (step 1, 0b5ef756): `Config.HalloweenMap` (every
  switch false; `Enabled`, `Boss.Enabled`, `Candy.Enabled`; no hour-cap key), `Config.Lighting.Night`
  (first values, Day's keys), `Strings.HalloweenMap` + 4 `GlobalQueue.Failed` keys, Net
  `HalloweenMapFx`/`KingChallenge`, Bootstrap + Main blocks (pcall-guarded) and the four modules,
  each returning at once while its switch is off. Late against 08:15 (lane started 08:43).

- 09:16 code pushed, all switches off, **Studio unchecked (no Rojo in the lane window)**:
  355ce0a8 Rules + Lune tests (step 2 done); ccb73403 Night (LightCycle.event, mixStates,
  DayCycle crossfade), EventMap switch + table looks by mode, the night sky rendered headless and
  uploaded (6 faces, ids in `Config.Lighting.Night.Sky`, `tools/upload_manifest_hw_map.json`),
  `tools/halloween/hw_map_cloth_check.py` (raw: orchid 23.2, charcoal 20.4, toxic 29.4);
  0498b301 BotService boss hooks, KingLook (code-built placeholder King and throne), BossService,
  CandyDrop, MapClient prompt + MapFx. bot_duel for the 10 TierFor rows running in the background.
  Night sky preview: `~/Desktop/8ball-refs/halloween/shots/hw-map/gate1/night-sky-cross.png`.
- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
- 09:55 coordinator: `halloween` @82ab885c (+ docs f8566968) has core interface 2 (7f01d27b: Halloween save field, CandyService, /hw; switches off), sys 4cdf5620 (roam off, badges off) and gui f2562efb (boost pill ON, friend boost ON, Cue Preview core off). Lint OK, 1,404 tests, Studio play console clean, pill shows +120%. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare: hooks stay inside `do ... end`.
- 09:56 coordinator: your Rojo server on 34886 is up (pid 20013, since the 08:47 watchdog restart); only the plugin dropped. Asked Justin to click Connect in lane-hw-map (terminal + notification). Until then keep going on headless work (props, decor kits, Rules tests) and queue the Studio steps. Your ea730d46 (Grandmaster King rows) is noted; I merge map once steps 3-5 are Studio-checked.

## Shared-file changes

Landed (only my own blocks unless said):
- `Config.luau`: `Config.Lighting.Night` (after Sunset), `Config.HalloweenMap` (after Lighting) — 0b5ef756, ccb73403, 0498b301.
- `Strings.luau`: `Strings.HalloweenMap` (after `Arena`); 5 keys in `GlobalQueue.Failed` (`KingBusy`,
  `KingNoTable`, `KingCooldown`, `KingNotNow`, `CandyBagFull`: the bag-full note reuses the queue
  notice) — 0b5ef756, 0498b301.
- `Net.luau`: `HalloweenMapFx`, `KingChallenge` at the end of REMOTES — 0b5ef756.
- `Bootstrap.server.luau`: one block after MoneyRain — 0b5ef756.
- `Main.client.luau`: one guarded block after `DayCycle.new()` (MapClient.start(dayCycle, hub)) — 0b5ef756, 0498b301.
- `tests/config_test.luau`, `tests/light_cycle_test.luau`: my own tests — 0b5ef756, ccb73403.
- Existing lines changed: `LightCycle.luau` (two new functions only), `DayCycle.luau` (the
  lighting source: `setLighting`, `self.lighting` instead of `L` in update, a crossfade),
  `Bots/BotService.luau` (spawn takes description/icon/animations/dress, seatInfo/attributesOf
  carry icon, `playBoss`, BotsQA "boss"), `Bots/Body.luau` (build takes animations, dress),
  `People.luau` (portrait: bot.icon / BotIcon first) — ccb73403, 0498b301.
- `TableBuilder.luau`: `addDecor` and its helpers (new functions only) — fa43df20.
- `Main.client.luau`: the MapClient block moved inside `do ... end` (coordinator) — 4c0e3895.
- `Config.luau`: the 3v3 cloth (88,176,32) — 7fd462cc; `Config.Debug.Commands.King = "/king"`
  after core's `Halloween` line — b86b9142.
- `tests/halloween_contract_test.luau:252`: the 3v3 tint, as the coordinator asked — 7fd462cc.
- `Strings.luau`: the four King notices shortened to fit the queue card — aaaffdbe;
  `KingDevStarted`, `KingDevFailed` in `Strings.HalloweenMap` — b86b9142.
- `DevCommands.luau`: the designer-only `/king [tier]` block after core's `/hw` — b86b9142.
- `LocalSearch.luau`: `isPromised(t)`, read-only (one new function) — 10489ad6.

Shared files (PLAN §7 plus `HubCorners.luau`, `Net.luau`, `DevCommands.luau`,
`tests/save_schema_test.luau`, `tests/config_test.luau`): only your own block or line; the
coordinator resolves overlaps. Planned (add the commit sha when each lands):

- `src/shared/Config.luau`: the `Config.HalloweenMap` block (after `Config.Lighting`) and
  `Config.Lighting.Night` (after Sunset).
- `src/shared/Strings.luau`: `Strings.HalloweenMap`; four `Strings.GlobalQueue.Failed` keys
  (`KingBusy`, `KingNoTable`, `KingCooldown`, `KingNotNow`).
- `src/shared/Net.luau`: `HalloweenMapFx` and `KingChallenge` (core and GUI add their own lines).
- `src/server/Bootstrap.server.luau`: one block after MoneyRain (EventMap, BossService, CandyDrop).
- `src/client/Main.client.luau`: one line starting MapClient.
- `src/server/DevCommands.luau`: the designer-only `/king` block (core's `/hw` block is separate).
- `tests/config_test.luau`: your own `Config.HalloweenMap` block (core and sys add theirs).
- Outside your folders (§2.1 of the brief): `LightCycle.luau`, `DayCycle.luau`, `TableBuilder.luau`
  (`addDecor`), `Bots/BotService.luau`, `Bots/Body.luau`, `People.luau`, `LocalSearch.luau`
  (`isPromised`).

## Requests

- RESOLVED 11:41 (coordinator: go with (88,176,32); done as the step 5 commit). **CONTRACT CHANGE** (10:05, updated 10:50; coordinator): the 3v3 toxic green (110,220,40)
  renders (167,243,23) at the table and sits **ΔE 16.5** from the yellow balls (1 and 9) under
  Night and Sunset alike (they read the same up close), under PLAN's 17. The brief's rule (§2.4:
  "shift that tint's lightness within its hue and re-measure") gives **(88,176,32)**: the same
  hue at 80% lightness, renders (139,219,32), **ΔE 19.9** (gate1 `12`). Recommended: it keeps
  PLAN's lime. (A greener (70,210,55) reads 23.9 but moves the hue; gate1 `08`.) It needs PLAN
  §2 Tables and `tests/halloween_contract_test.luau:214` (yours) changed: say go and I change
  Config, my tests and the cloth tool in one commit, or change the contract line yourself and I
  follow.
- RESOLVED 10:00 (Justin reconnected). **ROJO CONNECT AGAIN** (09:50): the `lane-hw-map.rbxl` window's plugin shows `[Rojo-Warn]
  Disconnected from an error: WebSocket error: 400` and has none of this branch's code. Rojo on
  34886 is up (pid 20013 since 08:47). Please click Connect to `localhost:34886` once more
  (and Accept if it asks to confirm the changes).
- RESOLVED 09:00. **ROJO RECONNECT** (08:53): the `lane-hw-map.rbxl` window has none of this branch's code (no
  `ServerScriptService.Server.HalloweenMap`, no `Config.HalloweenMap`), so its Rojo plugin is not
  on 34886 (maybe auto-connected to 34872). Please Connect it to `localhost:34886` (Rojo on
  34886 is up). Working on files meanwhile.

- Core: this lane reads `Config.Halloween.CandyIcon` and `CandyService.bossCooldown(player) ->
  number` (unix seconds, 0 if none), `bossWon`, `pickup`, `isLive`, `Event.state(Clock.now())`
  and the player attribute `HwOn`. Say if any is missing after the 08:30 merge.
- Core: please confirm the quest fallbacks read `HM.Enabled and HM.Boss.Enabled` and
  `HM.Enabled and HM.Candy.Enabled` (`HM = Config.HalloweenMap`, shipped in step 1, all false
  now), and that `pickup` returns `(ok, reason)` with `"Cap"` for the hour cap.
- hw-sys: noted your Request: the King's prompt refuses a player in a match and CandyDrop skips
  players in a match (`Tables.tableOf(p) ~= nil`); BossService calls
  `Badges.grant(p, "PumpkinSlayer", "Boss")` (guarded require + pcall).
- Coordinator: please include the step-1 interface commit in the interface merge.

## Assumptions

- The throne stays at the piano spot (gate 2 option (c)) until Justin answers the gate 2 question
  (`gate2/05`): from the spawn it reads as a glow between the two lobby boards, and the prompt
  and the glow lead players there. Option (a) is a two-line change (`Throne.Pivot` z about -66
  and `PromptAt` with it), to be checked in Studio against the boards and the last table row.

- OVERRULED (Justin: yes, 12:16 via the coordinator): the top three TierFor rows play a Grandmaster King, not Reyes (PLAN: two ranks
  above, at most Reyes). Measured: a Reyes King left the model player 11.5% (Master), 13.5%
  (Grandmaster) and 14.0% (Reyes), all under the brief's 20% floor; stepped down one tier they
  read 26.5% / 33.0% / 36.0%, inside 25-45%. The Reyes row's King is now one tier below the
  player (the only row so).

- `TableBuilder.addDecor(model, kit?)` reads the table's frame from the model's pivot (the
  placement's own, set by `buildFromModel`), so it takes no `p`: EventMap finds tables by model,
  and an arena's table is placed the same way.
- The trim is one mesh ring (Assets `Trim`, the body footprint's size, 32 tris), not strips: four
  strips put the 2v2 kit at 11 parts, and a solid plate would show inside the pocket cups.
- The bats glow Neon in the kit's colour: the brief's black bat vanishes on the black-frame
  apron. They sit 0.022 studs proud of the apron (the footprint leaves 0.024).
- The underglow stays inside the footprint, as the brief rules: at Transparency 0.45 it reads as
  a pool of light under the table (a solid Neon plate read as a yellow slab). The 2v2 kit's
  orange is (255, 90, 10): Neon draws (255, 122, 26) nearly yellow.
- The decor goes on arena tables too (part of the table's look, like the cloth tint).

- OVERRULED (Justin: yes, 12:16 via the coordinator): `Props.Budget.UniqueMeshes` is 16, not the brief's 8. The event's 16 meshes hold
  6,900 triangles in all on one palette texture (one upload); getting to 8 would merge props
  whose places are data (trees, strings of lights, dressings) into fixed meshes. The draw cost
  the cap guards is met by the MeshParts count (112 of 130) and the shared texture.
- Spooky planters: the brief's "dark box" is a Slate Part the size and place of the hidden
  planter's pot (`__Opaque` part), shadow on, no collision (the collision twin stays); the fern
  dressing is drawn 1.39x on the 4.16 pots so it fills the top instead of sitting small.
- String lights hang only on the pergola (front and middle beams, 6 strands); none on the
  railing (it is 400 studs round; cut-order 2 anyway). Pumpkin clusters only at the throne's two
  lanterns: the spawn's tall lanterns stand at the spawn (the brief keeps the spawn clear) and
  the side lanterns sit by beds that now carry pumpkins.

### King difficulty (bot_duel, 200 games a row, `--no-write`, 2026-10-28)

| Player | King | Player wins | Note |
|---|---|---|---|
| Bronze | Gold | 44.5% | |
| Silver | Platinum | 39.5% | |
| Gold | Diamond | 33.5% | |
| Platinum | Expert | 39.5% | |
| Diamond | Veteran | 36.0% | |
| Expert | Master | 26.0% | |
| Veteran | Grandmaster | 27.5% | |
| Master | Grandmaster | 26.5% | Reyes King: 11.5% |
| Grandmaster | Grandmaster | 33.0% | Reyes King: 13.5% |
| Reyes | Grandmaster | 36.0% | Reyes King: 14.0% |

## Gate shots

Gate 1 (`~/Desktop/8ball-refs/halloween/shots/hw-map/gate1/`, Play captures, lane window):

- `01-night-spawn.jpg`: Live (Studio force), from the spawn: the Night light (purple sky,
  violet haze-free light), the 1v1 tables orchid on black frames, the throne at the aisle's end.
- `02-day-spawn.jpg`: the same camera after forcing Before: Day, blue cloths and wood frames,
  the piano back (the off path restores everything).
- `03-three-looks-night.jpg`: the table looks under Night (Live): 2v2 charcoal (left, front
  and back), 1v1 orchid (front right), 3v3 toxic green (back right), all on the black frame.
  Server check: all 16 tables carry `HalloweenLook`, cloth tints exactly 185,90,230 / 90,94,102
  / 110,220,40; forcing Before clears them and restores Blue. Note for gate 2: the lobby boards
  stand in front of the throne, which half-hides it from the spawn.
- ΔE (CIEDE2000, closest ball), raw tints: 1v1 23.2 (ball 4), 2v2 20.4 (ball 2), 3v3 29.4
  (cue ball).
- Rendered ΔE (`05`-`10`: the 16 balls in a 4x4 grid on a table of each mode, a fixed camera
  2.4 studs over the cloth, cloth and ball centres sampled with hw_map_cloth_check's medians):
  Night 1v1 **24.6** (ball 12), 2v2 **28.4** (ball 2), 3v3 **16.5 (ball 9 yellow), UNDER 17**.
  Sunset reads the same to the unit up close (the table lamps light the cloth and balls; `11`
  shows the Sunset hold took). The 3v3 tint (70,210,55) renders (95,240,47): **23.9** under both
  (`08`, `09`). See Requests: CONTRACT CHANGE.
- Brightness after tuning (`04-night-spawn-tuned.jpg` vs `02`, exposure 0.45, shade #B8A8D8):
  L* floor **0.91**, lobby band **0.93**, whole frame 0.89 (the purple sky is darker than the
  blue one by design). The roof meets the 0.9 target.
- Brightness, Night vs Day, same camera (01 vs 02): perceived lightness L* 0.81 whole frame,
  0.84 floor, 0.83 lobby band; linear luminance 0.66. **Under the 0.9 target**: step 4 tunes
  Night up (Brightness/Exposure, the purple kept).
- `night-sky-cross.png`: the Night sky's six faces (gen_sky night: moon, stars, violet
  gradient), uploaded as the six ids in `Config.Lighting.Night.Sky`.
- `12-dE-3v3-88-176-32.jpg`: the 3v3 cloth at (88,176,32), the CONTRACT CHANGE tint (the same
  hue at 80% lightness): renders (139,219,32), **19.9** from the yellow balls under Night.
- `13-3v3-88-176-32-merged.jpg`: Table 15 with that tint and the Toxic kit while Live, after
  merging halloween @070893de (7fd462cc).


Gate 2 (`~/Desktop/8ball-refs/halloween/shots/hw-map/gate2/`, Play captures, lane window, Live forced):

- `01-throne-night.jpg`: the throne at the piano spot (0, 2, -86) from its carpet: the carved
  pumpkin back (the event mesh), the crown over it, purple banners, steps, candles, four small
  carved pumpkins (meshes). The piano and its bench hidden; 98 parts, 28 meshes, 3 lights.
- `02-king-close.jpg`: the King on his throne, the real head (carved pumpkin mesh, tilted gold
  crown with purple gems), black suit, orange vest, seated, the cue as a sceptre.
  `00-king-backwards-before-fix.jpg`: he first sat facing the pumpkin (fixed, 8df3864c).
  Note: his orange head sits on the orange pumpkin back, so he reads less than he could.
- `03-king-match.jpg`: a King match at table 11 from the prompt (the real path: tutorial
  skipped, HwOn set by hand as core's server is not merged yet): Gold King vs an Unranked
  player, JackOLanternCue, Pc kind. The loss (he ran the table) logged Lost, no cooldown, and a
  second challenge right after worked (lose = retry at once).
- A staged win (PoolMatchQA finalEight, a real shot) found a bug: every win logged "Left" and
  paid nothing (the table lets the player go before the bot sees the result). Fixed
  (a38b71e1, `Rules.kingOutcome` + test); now "Won", and the reward runs to core's
  CandyService (missing here: "a King win grants nothing" warning until core merges).
- `04-candy-burst.jpg`: the candy explosion over table 11 (the real Burst remote): the event's
  wrapped candy meshes flung up, an orange pop, sparkles; "+50 CANDY" riser checked in the
  client (not in this frame: the candies were frozen 0.3 s in for the shot).
- `05-throne-from-spawn.jpg`: **gate 2 question**: from the spawn the throne is only a glow
  between the two lobby boards (Top players / Top countries) that stand in the aisle in front
  of the piano spot. Options: (a) move the throne forward of the boards (z about -66, still on
  the aisle's axis; mine, one Config line); (b) part the boards while Live (LobbyBoards, not
  mine); (c) leave it (the prompt and the glow lead players there). I suggest (a).
- Difficulty table: under Assumptions (all ten rows measured; the top three play a
  Grandmaster King).
- The PC-kind King pays a Pc match's money for balls (the staged win: +$66 for one ball), as
  PLAN chose ("Pc" so no farming). His portrait was the PC robot here; it is now his own
  (`Config.HalloweenMap.King.Icon`, devices `04`).

Decor kits (`decor/`, step 13, Live forced):

- `01-pumpkin-2v2.jpg`: the Pumpkin kit on a 2v2 table: orange underglow, the trim ring, bats,
  the small jack-o'-lanterns by the legs.
- `02-toxic-3v3-cobweb.jpg`: a low view of a 3v3 table's corner (Toxic kit): the green trim
  ring and underglow, the cobweb at a leg.
- `03-orchid-1v1.jpg`: the Orchid kit on a 1v1 table: purple underglow and the two bats.
- `04-pumpkin-2v2-merged.jpg`: the 2v2 kit after merging each table's pairs into one mesh (the
  MeshParts fix, 159 -> 112).

Props (`props/`, step 14, Live forced):

- `01-pergola-strands-webs-clusters.jpg`: the pergola's strings of lights (orange, purple), the
  cobwebs in its front corners, the pumpkin clusters at the throne's lanterns.
- `02-corner-trees-planters.jpg`: dead trees in the palms' pots and the dark planter boxes with
  their dressings.
- `03-fern-planter-from-spawn-side.jpg`: a fern planter's spooky twin (the dressing at 1.39x).

Candy (step 11): `candy-lobby.jpg`: a lobby candy, the event's wrapped candy mesh.

Devices (`devices/`, step 18, my window's size, 1523x814 viewport; captures at 1920 wide):

- `01_prompt_ready_in.jpg`: the King's prompt on cooldown, "Ready in 11:11", key E.
- `02_prompt_challenge.jpg`: the prompt when ready, "Challenge the Pumpkin King".
- `03_notice_king_no_table.jpg`: the KingNoTable notice on the queue card, one line.
- `04_king_match_portrait.jpg`: a King match: his pumpkin-and-crown portrait in the match bar.
- `05_billboards_plus1_plus50.jpg`: the +1 pickup and the +50 CANDY burst risers, the candy
  burst on the floor.

Fresh player (`fresh/`, step 19, a new save, core's BootLive):

- `01-join-tutorial-night.jpg`: the join: Night sky, orchid tables, dead trees, strands; the
  tutorial's "Join a table!" arrow; no prompt, no candy.
- `02-tutorial-first-match-orchid.jpg`: the tutorial's first match on table 2, orchid, balls
  readable.
- `03-prompt-after-tutorial-result-card.jpg`: after Skip and the match, the King's prompt at the
  throne (behind the result card until Continue).
