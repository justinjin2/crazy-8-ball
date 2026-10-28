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

- **ROJO CONNECT AGAIN** (09:50): the `lane-hw-map.rbxl` window's plugin shows `[Rojo-Warn]
  Disconnected from an error: WebSocket error: 400` and has none of this branch's code. Rojo on
  34886 is up (pid 20013 since 08:47). Please click Connect to `localhost:34886` once more
  (and Accept if it asks to confirm the changes).
- **ROJO RECONNECT** (08:53): the `lane-hw-map.rbxl` window has none of this branch's code (no
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

- OVERRULED: the top three TierFor rows play a Grandmaster King, not Reyes (PLAN: two ranks
  above, at most Reyes). Measured: a Reyes King left the model player 11.5% (Master), 13.5%
  (Grandmaster) and 14.0% (Reyes), all under the brief's 20% floor; stepped down one tier they
  read 26.5% / 33.0% / 36.0%, inside 25-45%. The Reyes row's King is now one tier below the
  player (the only row so).

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
