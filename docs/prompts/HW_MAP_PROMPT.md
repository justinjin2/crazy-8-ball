# Halloween lane W5: the Haunted Rooftop and the Pumpkin King

**Written 2026-10-28 07:20 EDT by the coordinator for the designer (Justin).** Lane `hw-map`
(W5): folder `~/Desktop/8ball-hw-map`, branch `hw-map` (cut from `halloween`), Rojo **34886**,
Studio window `place/lane-hw-map.rbxl` (and only that one), **Opus 5.5 · xhigh**. The shared
contract is [`docs/halloween/PLAN.md`](../halloween/PLAN.md) (decisions, epochs, lanes, ownership,
interfaces, timeline); the numbered requirements are `docs/halloween/REQUIREMENTS.md`; your lane
file is `docs/halloween/lanes/hw-map.md`. All times are EDT. Go-live is **19:00 today
(`1793228400`)**, the end **Tue Nov 3 19:00 EST (`1793750400`)**.

Start and restart: the coordinator launches this lane with `tools/halloween/lanes.sh launch`;
every launch or restart line is exactly the command printed by `tools/halloween/lanes.sh command
hw-map` (never write your own flags).

**Attended until 11:00.** The Progress list at the end is the source of truth; the Stop hook
(`tools/overnight/hw_map.json`) sends you back to work while any `- [ ]` remains. Before 11:00,
when you truly need Justin (a call where guessing would lower the quality, a click only he can
make), run `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (NOT
`.git/overnight-waiting`: in a worktree `.git` is a file and that fails, whatever the hook's
message says), ask one clear question with a picture, and stop.
**After 11:00 never stop to ask** (he may sleep until about 16:30): decide the way he would (PLAN
decisions, `docs/DECISIONS.md`, `docs/UI_STYLE.md`, simple for kids), write it under Assumptions
in your lane file (a change to a PLAN decision starts with `OVERRULED:`), keep going.

Hard rules: builds stop **16:00** (every open line done, or ticked `CUT:`/`BLOCKED:` with a
reason); **17:00** freeze (only fixes the coordinator asks for). **Never publish. Never touch the
Team Create place. Blender headless only** (`/Applications/Blender.app/Contents/MacOS/Blender -b
--factory-startup --python-exit-code 1 --python ...`; the Blender MCP is shared by every
terminal). No audio uploads (Roblox library sounds only). Images, meshes and the skybox may be
uploaded to group 675425213 without asking; never print a key. Everything the real game needs
travels with your branch: code, `.rbxm` under `src/`, or an exact Request; anything only built
by hand in your Studio copy is lost at the merge. Loop for every step: `tools/lint.sh`,
`tools/test.sh`, a Studio check in YOUR window, a small commit on `hw-map` with the attribution
line, `git push -u origin hw-map`, tick the Progress line, a dated line in your lane file's Status.

## 0. Read first

1. **Contract and rules:** `docs/halloween/PLAN.md` (all of it), `docs/halloween/REQUIREMENTS.md`
   (rows R3.x, R4.x and §9), `CLAUDE.md`, `docs/parallel/README.md` (its rules hold, with PLAN
   §4's lanes and ports and branch `halloween` instead of `release`), your lane file,
   `docs/STUDIO_NOTES.md` (Sky faces, Rojo, MCP, Blender), `docs/UI_STYLE.md` (fonts and colours
   for the billboards you add), `assets/map/Budget.md` (the map's triangle, part, texture and
   light budget) and `assets/map/Readme.md`.
2. **Agent reports** in `~/Desktop/8ball-refs/halloween/research/agents/`: `code-bot-map.md`
   (main: King, map, night, candy; file:line for every claim), `economy-candy.md` (§2 pickups, §7
   risks), `code-roam.md` (MoneyRain and pads, players roaming during a match), `cloth_contrast.py`
   (the CIEDE2000 maths). The coordinator spot-checked them at 07:15 against gui-v4 @ 12ee4888.
   Also the neighbours' briefs, for the interfaces only: `docs/prompts/HW_CORE_PROMPT.md` §2.2-2.4
   and §2.11 (Event, Clock and its test offset, CandyService, the `HwOn` gate, the quest Alts that
   read your switches) and `docs/prompts/HW_SYS_PROMPT.md` (Roam; `Badges.grant`).
   **Corrections to the reports:** BotService lives at `src/server/Bots/BotService.luau`; its
   `skill = tierOf(spec.skill or tier)` (BotService.luau:143) turns any name that is not a rank
   tier into Bronze, so the King uses an existing tier row; the event times are PLAN's, not the
   economy report's 5 PM numbers; the cycle is **Night 10 min → Sunset 5 min with Night in Day's
   slot**, not "Sunset aliased to Night"; tables are built once at boot, so the event looks are
   applied at run time, not through `LookByTable`.
3. **Code you change or call** (read each before editing):
   - Light: `src/shared/LightCycle.luau` (sun :97, skyStage :126, state :192),
     `src/client/DayCycle.luau` (sky preload :61-78, update :128, `LightCycle.state(blend, L)`
     :159), `src/shared/MapLighting.luau`, `Config.Lighting` (Config.luau:8691; Cycle 600/10/300,
     SkySwaps :8713, DuskSky :8716, DuskWarm :8734, SunPath :8752, Day :8762, Sunset :8863),
     `tests/light_cycle_test.luau:134-145` (Day and Sunset have the same keys), `assets/map/gen_sky.py`.
   - Tables: `src/shared/TableBuilder.luau` (lookFor :180, applyLook :359, addLamp :737, build
     :768), `Config.TableModel` (Looks :763, black frames `Blue`/`RedBlack`/`CharcoalBlack`;
     DefaultLook :846; LookByTable :853; "Tint ... is the one thing scripts may change at run time"
     :760), `Config.Hub.Tables` (:627, `teamSize` per id; WalkSpeed 20.8 :615), `Config.Arena.Look`
     (:9060, `Blue`), `src/server/Bootstrap.server.luau:150` (tables built once).
   - Map: `src/shared/MapBuilder.luau` (prepareProps :518, Edit mode only),
     `src/server/MapData/GrayBox.json` (git-ignored copy: Palm 18, PalmPlanter 18, FernPlanter 12,
     PlanterBed 11; Piano at (0, 2, -86.05) yaw 180, PianoBench at (0, 2, -92.45)),
     `src/client/Portals.luau:217` (hidePlanters) and `Config.Portals.Replaces` (:3583).
   - Bots: `src/server/Bots/BotService.luau` (matchEnded :83, spawn :120 with
     `description = Identity.robot()` :127, attributesOf :164, seatInfo :180, seat :194, say :317,
     ended :447, playPc :619 and :653, BotsQA studioHook :665), `src/server/Bots/Body.luau`
     (animate :32 reads `B.Animations`, build :81), `src/server/Bots/Identity.luau:160`,
     `src/client/People.luau:141` (portrait), `src/shared/Progression/Settle.luau:93`
     (opponentKind: "Pc" pays as PC), `Config.Bots` (:14480; Tiers :14500, Robot :14702,
     Animations :14868), `Config.Ranks.Tiers` (:1780), `tests/bot_duel.luau`, `tools/bot_duel.luau`.
   - Tables at run time (TableService belongs to hw-sys: call, never edit):
     `src/server/TableService.luau` freeTable :1838, placeOnPad :1758, onFlush :532, padSpot
     :1897; `src/server/LocalSearch.luau:255` (botHere, its `promised` set),
     `src/server/PortalService.luau:47` (allowed: the checks to copy), `src/server/SoloSearch.luau:118`
     (cancel), `src/server/GlobalQueue.luau:891` (notify) and `Strings.GlobalQueue.Failed`
     (Strings.luau:~237).
   - Drops and prompts: `src/server/MoneyRain.luau` (rootOf :51, spot :63, tick :259, start :300),
     `src/client/MoneyRainFx.luau`, `Config` Rain block (:16557), `src/client/GiftDrop.luau:547`
     (a client-made ProximityPrompt), `src/client/MenuColumn.luau:268` (X on prompts),
     `src/server/Funnel.luau:222` (Funnel.event), `src/client/Quality.luau` (isLow),
     `src/client/GuiQA.luau` ("pad").
4. **Pictures** (open each before you build; recheck at every gate):
   - `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/MAP2_lobby.png`: **the mood.** A
     violet night sky with a big full moon over the sea, pink-lit clouds, bats; leafless dead trees
     with hanging orange lanterns where the palms stand; glowing jack-o'-lanterns in the planters
     and along the front; orange and purple string lights on the pergola and the railing; cobwebs
     on the pergola corners; tables with black frames, bat emblems on the aprons, a glow ring in
     the mode colour round each. **Ignore its orange 2v2 cloth** (decided: charcoal with orange
     glow) and its piano (the throne replaces it).
   - `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/P1_pumpkin_king.png`: **the King
     (approved).** A glowing carved jack-o'-lantern head with an angry grin and a tilted gold crown
     with purple gems; black suit, orange-pinstripe vest, orange bow tie, gold chain, small
     jack-o'-lantern epaulettes; purple velvet cape with orange lining and gold trim; black-and-gold
     cue with a jack-o'-lantern butt; purple and orange flame aura; idle pose leaning on the cue.
     The throne: a giant jack-o'-lantern back, a purple tufted seat, a crown on top, candles, small
     pumpkins, purple banners with the 8-ball crown crest, a purple carpet with a crown and an 8,
     and the prompt "Hold E: CHALLENGE".
   - `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/M2_table_close.png` (earlier mock): the
     haunted-table mood for the decor kit only (bat and web reliefs on the apron, a thin orange
     glow line under the rail). No new table mesh, nothing on the pockets.

## 1. Goal

This lane owns **R3.1** (spooky map: sky, ambience, trees and decor replaced), **R3.2** (table
colours show the mode, §9: 1v1 orchid, 2v2 charcoal + orange glow, 3v3 toxic green), **R3.3**
(haunted tables = black frames + decor kit), **R3.4** (Night: purple sky, as readable as day),
**R3.5** (lobby candy drops: spawning and pickup; the Candy itself is core's), **R4.1-R4.4** (the
King as PLAN §2; R4.4's amount is core's `bossWon`, the explosion is yours), the map side of
**R1.6** (on at go-live by itself), and **R0.5/R0.6** for everything you add.

Done, in player terms:
- Before 19:00 the lobby is exactly today's. At 19:00:00 on the server clock every server fades,
  in a few seconds, into a purple night: a new purple sky with a full moon, the roof as bright and
  readable as by day. Then every 15 minutes: 10 min Night, 5 min Sunset, the usual 10 s fades.
- The palms are dead trees with lanterns, the planters hold glowing pumpkins, string lights and
  cobwebs hang on the pergola and the railing. Nothing blocks an aisle, a pad, a camera or a cue.
- Each table says its mode at a glance (1v1 orchid purple; 2v2 charcoal with glowing orange trim
  and pumpkin corners; 3v3 toxic green; black frames and a small haunted kit), and every ball is
  clearly visible on every cloth under Night and Sunset.
- At the end of the spawn aisle, where the piano was, the Pumpkin King sits glowing on his pumpkin
  throne. Hold E / tap / X: "Challenge the Pumpkin King", and you are on a free lobby table against
  him (two ranks above you, at least Gold; he taunts). Lose: walk back and try again at once. Win: a
  candy explosion over the table, +50 Candy (the first 2 wins a UTC day), then his prompt shows
  your 15:00 cooldown. New players see him from the spawn in their first session; his prompt
  appears once the tutorial is Done or Skipped.
- Candy pieces pop up on the roof near active players, about 25 an hour each, +1 when you walk
  over one, never more than 40 an hour (core's cap, enforced by `CandyService.pickup`).
- On Tue Nov 3 19:00 EST it all switches off by itself and the lobby is today's again.
- Low-end phones keep their frame rate: few parts, shared meshes, almost no real lights.

## 2. Design

### 2.1 Files

New (yours):
- `src/shared/HalloweenMap/Rules.luau`: pure, no Instances: event lighting composition, the King
  tier rule, eligibility and teleport checks, the decor bounds check, the hide-list filter, spawn
  pacing, the pickup-reason handling (only `"Cap"` shows the note), the state-change actions. All
  of it tested in Lune.
- `src/server/HalloweenMap/EventMap.luau`: the switch, the state attributes, the table relook and
  decor, props and hides, the throne.
- `src/server/HalloweenMap/KingLook.luau`: the King's description and dressing, used by the throne
  figure and the table body alike.
- `src/server/HalloweenMap/BossService.luau`: the challenge flow, reward call, cooldown, taunts,
  analytics.
- `src/server/HalloweenMap/CandyDrop.luau`: a copy of MoneyRain for Candy.
- `src/server/HalloweenMap/Assets/*.rbxm`: templates (props, throne, King pieces, candy) assembled
  in your window from uploaded meshes; code clones them. **Check the Rojo round trip with the
  first one** (delete the Studio copy, let Rojo re-sync, the mesh still shows in Play). If
  MeshParts lose their mesh, use `AssetService:CreateMeshPartAsync` from ids in Config, cached
  once at boot.
- `src/client/HalloweenMap/MapClient.luau` (follows the state: lighting table and preload, the
  King prompt, candy spin and +1, the burst); split it past about 400 lines.
- `tests/halloween_map_test.luau`; `tools/halloween/hw_map_cloth_check.py` (ΔE from sampled colours).
- `assets/halloween/map/` (Blender scripts `gen_props.py`, `gen_king.py`, `gen_throne.py`, exported
  GLBs and PNGs); `assets/map/gen_sky.py` gains a `night` light.

Changed (each line goes in your lane file's Shared-file changes). The shared files are PLAN §7's
list plus `HubCorners.luau`, `Net.luau`, `DevCommands.luau`, `tests/save_schema_test.luau` and
`tests/config_test.luau`: in each, add only your own block or line, list it in your lane file, and
the coordinator resolves overlaps at the merge.
- `Config.luau`: the `Config.HalloweenMap` block (after `Config.Lighting`) and
  `Config.Lighting.Night` (after Sunset; the same keys as Day).
- `Strings.luau`: a `Strings.HalloweenMap` block; four reason keys in `Strings.GlobalQueue.Failed`
  (`KingBusy`, `KingNoTable`, `KingCooldown`, `KingNotNow`).
- `Net.luau` (shared: core and GUI add their own lines): `HalloweenMapFx` (RemoteEvent, server to
  client) and `KingChallenge` (RemoteEvent, client to server, no arguments).
- `Bootstrap.server.luau`: one block after MoneyRain (:183): `EventMap.start(isArena)`,
  `BossService.start(not isArena)`, `CandyDrop.start(not isArena)`, each pcall-guarded.
- `Main.client.luau`: one line starting MapClient (and handing DayCycle its lighting source).
- `LightCycle.luau`: `LightCycle.event(lighting, night)` and an exported `mixStates(a, b, w)`.
- `DayCycle.luau`: the lighting table from MapClient (`L` or the event one), Night faces preloaded
  at Countdown, a crossfade on a flip.
- `TableBuilder.luau`: `TableBuilder.addDecor(model, p, kit?)` (nil removes the kit).
- `Bots/BotService.luau`: `spawn` takes `spec.description`, `spec.icon`, `spec.animations`,
  `spec.dress`; `seatInfo` and `attributesOf` carry `icon`; `BotService.playBoss(t, p, spec)`;
  BotsQA `("boss", userId)`.
- `Bots/Body.luau`: `build` takes optional `animations` and `dress(model)` (run before parenting,
  so the body never shows undressed).
- `People.luau`: `if bot.icon then return nil, bot.icon end` before the robot icon.
- `LocalSearch.luau`: a read-only `LocalSearch.isPromised(t)`, so the King never races a search.
- `DevCommands.luau` (shared: core has its own `/hw` block there; never edit it): a designer-only
  block: `/king` (a real King match now, cooldown ignored), for Justin's 17:00 playtest.
- `tests/config_test.luau` (shared: core and sys add theirs): your own block checking the
  `Config.HalloweenMap` shape (§4).

### 2.2 The switch (EventMap)

- Source of truth: core's `Event.state(Clock.now())` (`"Before"`, `"Countdown"`, `"Live"`,
  `"Ended"`; `src/shared/Halloween/Event.luau` and `Clock.luau`), polled every `PollSeconds` (1)
  on the server. Never read the raw clock: `Clock.now()` carries core's test offset
  (`HwTimeOffset`, honoured in Studio and on the test place, where the server sets it at boot so
  the event is Live for Justin's 17:00-18:30 playtest; `/hw time` moves it). In Studio only
  (`RunService:IsStudio()`), your workspace attribute `HalloweenMapForce` (a state name) also
  overrides it, so every map transition can be tested without core and without waiting.
- The server publishes `workspace.HalloweenMapState` (string) and `workspace.HalloweenMapFlipAt`
  (server time of the last change). **Clients follow only these two attributes** (lighting,
  prompt, FX), so server and clients always agree, arenas included.
- Live: relook the tables and add the decor, hide the replace list, parent the prepared props and
  the throne, start the King and the drops. Ended (or a Studio force back to Before): undo all of
  it in reverse. King matches already running finish; no new challenge; unclaimed candy goes.
- Build everything at boot into a ServerStorage holder (nothing visible), so a flip is only
  reparenting. Every step pcall-wrapped and idempotent (Live twice changes nothing); every part
  obeys its own switch and the master `Enabled`.
- Nothing of yours is in workspace before Live. At Countdown the client only preloads the Night
  faces and the prop meshes (`ContentProvider:PreloadAsync`), so 19:00 never shows a grey sky.
- A server booted after 19:00 goes straight to Live with no fade; a client joining mid-event sees
  Night at once (FlipAt is long past).

### 2.3 Night: the preset, the cycle, the sky

- `Config.Lighting.Night`: Sunset's keys with overrides. Starting values (tune in **Play**
  captures, never Edit's preview): Brightness 3, ExposureCompensation 0.15, OutdoorAmbient
  `#A898C8`, ColorShift_Top `#E8D4FF`, Atmosphere Density 0.08 with Haze 0 (Sunset's lesson: haze
  fogs the city into one flat colour), Color `#B48CFF`, Decay `#5B2A8C`, ColorCorrection TintColor
  `#F2EAFF`, **Bloom exactly Sunset's (0.8, 24, 2.6)**, TableLights 3, Fire 1, Windows lit,
  Glow.Lantern `#FF7A1A`, TableGlow tint purple (`#B26BFF`), Water purple (`#4A3A9A`), Islands
  violet. If the mid-fade turns brown, give the event table its own DuskWarm colours.
- The event cycle: Night takes Day's slot: Night 600 s, fade 10, Sunset 300, fade 10
  (`Config.Lighting.Cycle` unchanged, period 920 s). `LightCycle.event(L, L.Night)` returns a
  lighting table with `Day = Night`, `DuskSky = Night.Sky` (the only sky change is Night to Sunset
  at blend 0.6, under SwapHaze) and `SunPath` held at Sunset's sun (GeographicLatitude -30,
  ClockTime 7.4 at both ends: "sun path kept", the light from the moon's side). Generic, so Night
  can become permanent later with one switch (R3.4: "maybe permanent later").
- DayCycle: `LightCycle.state(blend, lighting)` with the event table while the state is Live,
  else `L`. On a flip, crossfade from the last written state to the new one over `FlipSeconds`
  (4) with `mixStates`, then force a full rewrite (`self.last = nil`). `/day` and `/sunset` holds
  keep working (blend 0 is Night during the event).
- The sky: `gen_sky.py -- night`, headless: the same seed's cloud scene; zenith deep violet
  (`#3B1D7A`) to a lilac-pink horizon (`#E08AD8`); clouds lavender-pink, lit from the moon's side;
  stars in the upper half; a large soft full moon (cream `#FFF1D6` with a glow) painted in
  `SUN['sunset']`'s direction (over the sea, where the mock has it); the far city's windows lit.
  Six 1024 faces, uploaded with `tools/roblox_upload.py --group-id 675425213 --manifest
  tools/upload_manifest_hw_map.json` (your own manifest: no merge conflicts), image ids through
  `tools/manifest_image_ids.py`, written to `Night.Sky`; SunAngularSize, MoonAngularSize and
  StarCount 0 (all painted). The sky reads violet, never black.
- "As readable as day" (Play, same camera, Day held vs Night held): mean luminance of the floor
  and table area at least `Night.MinBrightnessShare` (0.9) of Day's. Numbers in the lane file.

### 2.4 Tables by mode, and the decor kit

- On Live, for every table model in `workspace[TableBuilder.FolderName]`:
  `TableBuilder.applyLook(model, "Blue")` (the black-frame look the arena already uses, so its
  SurfaceAppearances are in `ServerStorage.TableLooks`; confirm in your window), then set the
  Cloth SurfaceAppearance's `Color` to the mode's tint. Mode = `teamSize` from `Config.Hub.Tables`
  (never hard-coded ids). On Ended: `applyLook(model, TableBuilder.lookFor(id))`, or
  `Config.Arena.Look` in an arena. No new table images (ImageBudget 18), no new table mesh.
- Tints, exactly PLAN's: 1v1 orchid (185, 90, 230), 2v2 charcoal (90, 94, 102), 3v3 toxic green
  (88, 176, 32) (was (110, 220, 40), ΔE 16.5 rendered; coordinator 11:41). Never an orange cloth (balls 5 and 13 vanish).
- **CIEDE2000 ≥ 17 between each cloth and every ball, as rendered under Night and under Sunset.**
  In Play, top-down captures of a racked table of each mode (`/bot` on a 1v1; BotsQA seats for
  2v2 and 3v3), sample the median cloth colour and each ball's lit median, run
  `tools/halloween/hw_map_cloth_check.py` (the `cloth_contrast.py` maths on sampled colours).
  Raw-colour values today: orchid 23.2 (ball 4), charcoal 20.4 (ball 2), toxic 29.4 (ball 0).
  A rendered pair under 17: shift that tint's lightness within its hue and re-measure. Write the
  final table (cloth, closest ball, ΔE, both lightings) in the lane file.
- `TableBuilder.addDecor(model, p, kit)`: clears `model.HalloweenDecor`, then builds the kit from
  Config (code-built parts plus shared MeshParts from Assets). Every decor part: Anchored,
  CanCollide, CanQuery, CanTouch and CastShadow false, Massless; **its top below the rail top**
  (`Table.SurfaceHeightStuds + RailTopInches * StudsPerInch`) and **inside the Body's footprint**
  (its box in table space). `Rules.decorInside` checks every part; one that fails is not added
  (warn once). Nothing touches Cloth, Rails or Pockets (they stay aligned with the physics).
- Kits (at most 10 parts and 1,500 triangles a table): every mode gets an **underglow** (a Neon
  plate in the mode colour under the body, inside the footprint: the glowing ring of light round
  the table's foot) and **two bat emblems** on the long aprons (one shared image or mesh).
  1v1 "Orchid": purple underglow, bats. 2v2 "Pumpkin": an **orange Neon trim strip on the apron
  just under the rail line** (PLAN's glowing orange rails/trim), orange underglow, **4 small
  pumpkins at the corners** (shared mesh). 3v3 "Toxic": green underglow, green trim, a cobweb card
  at two corners.
- Assumption to log and show at gate 1: PLAN's "orange pad glow" is the 2v2 underglow ring; the
  queue pads keep their state colours (blue free, green occupied, gold full: they carry meaning).
  If Justin wants mode-coloured pad rims, that is a PadEffects change (Request to the coordinator).

### 2.5 Props, hides, budget

- The replace list (`Props.Hide`, name patterns under `workspace.Map`; confirm every name in your
  window first and record what you found):
  - `^Palm_%d+$`: the trees only. The PalmPlanter pots and their `palm_planter_NN` collision stay;
    a dead tree grows from the same pot at the same CFrame and scale.
  - `^FernPlanter_%d+$` and `^PlanterBed_%d+$` (visual): swapped for a spooky planter of the same
    footprint (dark box, pumpkins, dead bushes); their collision twins stay.
  - The piano: `Piano_*`, `PianoBench_*`, collision `piano_60` and `piano_bench_59`, the bench
    seat `Seat_11` (GrayBox names).
  - **Never `Config.Portals.Replaces`** (PlanterBed_42, PlanterBed_48, planter_bed_53,
    planter_bed_57: the portals' client hides them already; `Rules.hideList` filters them out,
    tested).
  Hidden instances are reparented to a ServerStorage holder (never destroyed) and put back on Ended.
- Props (headless Blender to GLB, uploaded, assembled into Assets): dead trees (≤ 1,500 triangles,
  2-3 hanging lantern cards with an emissive mask, no lights) ×18; pumpkins in 3 sizes with
  glowing carved faces (SurfaceAppearance emissive mask, ≤ 400 triangles) in clusters at the
  planters, the lantern bases and along the front parapet (about 40, or merged cluster meshes);
  tombstones (≤ 200) ×6-8 in planter beds; string lights (one MeshPart per strand, bulbs baked as
  Neon or emissive, orange and purple) ×8-12 on the pergola beams and the railing; cobweb alpha
  cards on the pergola corners. One shared atlas texture where it works.
- **Event budget** (in Config and the lane file; counted in Studio): ≤ 60,000 triangles, ≤ 130
  MeshParts, ≤ 8 unique meshes, ≤ 6 new textures (the sky not counted), **real lights ≤ 6 in all
  (`Budget.Lights = 6`): the throne ≤ 2 PointLights, the throne King's aura 1, each table King's
  aura 1 (3 at most), nothing else**, Shadows off. The glow comes from Neon and
  emissive masks under the unchanged Bloom.
- Placements live in Config; a prop replacing a GrayBox placement takes its position, yaw and
  scale in code. Nothing in an aisle, on a pad, in a table's match area (`Placement.matchWalls`),
  at the spawn or in front of a portal. Prop models use `ModelStreamingMode = Atomic`; the throne
  `Persistent` (it is seen from the spawn).
- Optional, first to cut: a quiet spooky ambience loop (a Roblox library sound in the game's sound
  group, respecting Settings) and a few bats crossing the sky (client sprites).

### 2.6 The throne and the King's look (KingLook)

- **Throne** at the piano spot, facing the spawn (+Z): pivot (0, 2, -86.05), inside X ±15 and Z
  -96.5..-77 (columns at X ±19.17), at most 18 studs tall (22 clear under the pergola beam; globe
  lights hang at Y 18.4; the back must show over the lobby boards at Z -59.5, 15.5 tall). Pieces
  (Blender): the giant jack-o'-lantern back with an emissive grin, a purple tufted seat, a gold
  crown on top, steps, candles (Neon flames), small pumpkins, two purple crest banners, a purple
  carpet toward the aisle (one image). One invisible box collision part; everything else
  CanCollide false. Prompt anchor at about (0, 3, -79).
- **King body:** `Players:CreateHumanoidModelFromDescription` from a fixed HumanoidDescription
  (blocky R15, black and charcoal body colours; a public catalog suit Shirt and Pants by id if they
  load in your window, else body colours alone), plus welded MeshParts: the pumpkin head (Head and
  face transparent; the carved grin and eyes glow through an emissive mask), the tilted gold crown
  with purple gems, the cape (purple outside, orange lining, gold trim, on UpperTorso), the orange
  bow tie, a gold chain, two small jack-o'-lantern epaulettes. All WeldConstraints (AvatarPose keeps
  them while he shoots); CanCollide, CanQuery, CanTouch false; Massless.
- **Aura:** two ParticleEmitters on the root (purple and orange flame wisps from the built-in
  `rbxasset://textures/particles/fire_main.dds`, embers; the client halves rates when
  `Quality.isLow()`), one orange PointLight (Range 10, Shadows off).
- **Idle:** the Roblox-owned Vampire animation package (find its ids through the Studio MCP and
  confirm they load with no console error) through Body's new `animations` argument. On the throne
  he sits, the cue upright in his right hand like a sceptre. If seated reads poorly at gate 2, he
  stands beside the throne leaning on the cue (the mock's idle pose).
- His cue: `JackOLanternCue` (Cues A's Catalog row: a teaser of the 500-Candy prize; an existing
  cue id while the row is missing). Name "Pumpkin King" (Strings). Portrait: a 256² headshot of
  your King (one image) through `bot.icon`.
- The throne figure is a separate anchored model with no bot attributes (never in the player list
  or the bot nameplates), with its own small "Pumpkin King" billboard. It stays on the throne while
  up to 3 table copies play.

### 2.7 BotService hooks and BossService

- **BotService** (about 40 lines): `spawn` takes `spec.description` (default `Identity.robot()`),
  `spec.icon`, `spec.animations`, `spec.dress`; `seatInfo` and `attributesOf` carry `icon`;
  `BotService.playBoss(t, p, spec)` is playPc with `{ kind = "Pc", name =
  Strings.HalloweenMap.KingName, tier = kingTier, skill = kingTier, playerTier = theirs, cue =
  Boss.Cue, rematch = "Never", description, icon, animations, dress }`. **Keep kind "Pc":**
  `Settle.opponentKind` pays it as PC (practice money, the PC daily cap, no XP, no block), so the
  King can't be farmed for money or rank; a new kind would pay like a real match.
- **Prompt** (client-made on the throne's anchor, the GiftDrop.luau:547 pattern): ActionText
  "Challenge the Pumpkin King", E, ButtonX, `ClickablePrompt` for touch, HoldDuration 0.4,
  MaxActivationDistance 10, RequiresLineOfSight false. Shown only while the player attribute
  `HwOn == true` (core: save loaded, event on, tutorial Done or Skipped: "nothing Halloween shows
  unless HwOn"); hidden in Freecam, in a match and in an arena. During the player's cooldown it
  stays visible as "Ready in 14:32" (updated once a second, only while shown); triggering it then
  only shows a short note. Triggered: `KingChallenge:FireServer()`.
- **Cooldown source:** core's `CandyService.bossCooldown(player) -> number` (unix seconds, 0 if
  none; the save's `KingReadyAt`, so a server hop keeps it), copied to the player attribute `PumpkinKingReadyAt` at join, at the flip
  to Live and after every win (from `bossWon`'s `cooldownEndsAt`). This lane never touches the save.
- **Server checks** (PortalService.allowed minus its Wins check): a lobby (not an arena; private
  servers allowed); PlayerData loaded and not handed off; `HwOn == true`; not in the guided
  tutorial; not Freecam; not in a match (hw-sys's Request: a roaming player mid-match is refused;
  alone as host on a waiting 1v1 pad is fine, he plays you right there); within 14 studs of the
  anchor; a 5 s throttle; `bossCooldown` past (else `KingCooldown`); fewer than `MaxAtOnce` (3)
  King bots alive (else `KingBusy`). Cancel a spawn-pill search
  (`SoloSearch.cancel`). Table: `Tables.freeTable(1, root.Position, kingPromised, 2)`, skipping
  `LocalSearch.isPromised`; none: `KingNoTable` (`GlobalQueue.notify` with `kind = "Failed"` and
  the new reason). Then `Tables.placeOnPad(t, p)`, then `BotService.playBoss`; on any failure remove
  the bot, notify, log. If a person takes the seat while the King's body builds (it yields), drop
  the King quietly: they get a real match.
- **Difficulty** (`Boss.TierFor`, data): two tiers above the player's, at least Gold, at most
  Reyes (Unranked counts as Bronze): Bronze→Gold, Silver→Platinum, Gold→Diamond,
  Platinum→Expert, Diamond→Veteran, Expert→Master, Veteran→Grandmaster, Master, Grandmaster and
  Reyes→Reyes. **Measure every row** with `lune run tools/bot_duel.luau <KingTier> --player
  <PlayerTier> --games 200 --no-write`; write the model player's win share per row in the lane
  file. Aim for 25-45%. A row under 20%: step its King down one tier and log it as `OVERRULED:`
  with the number. 91% of players are new (mostly Bronze against a Gold King): that row must be
  winnable.
- **Taunts** (`BotService.say`, at most one every `TauntEverySeconds` 6, driven by `Tables.onFlush`):
  on seating, his pot, his foul, the player's good pot, his win, his loss. Kid-friendly, short, no
  insults; 3-4 lines each in `Strings.HalloweenMap.Taunts`.
- **Result** (on `BotService.matchEnded` for a King bot; keep a botId → player map): the player won
  when `not info.won and info.reason ~= "EmptyTeam"`, the player is still in the server and was
  seated in that match. Then **call `CandyService.bossWon(player)` on every win** (core counts the
  quests and decides grant and cooldown), set `player:SetAttribute("PumpkinKingReadyAt",
  r.cooldownEndsAt)`, call hw-sys's `Badges.grant(player, "PumpkinSlayer", "Boss")` (guarded
  require of `src/server/Badges.luau` + pcall; missing means no award, nothing breaks; hw-sys also
  back-pays it from the save's `KingWins` through its `{ halloween = "KingWins", atLeast = 1 }`
  rule), then the burst. Each call in its own pcall: a failure in one never blocks the others. Lose, leave, EmptyTeam, removed: no reward, no cooldown. He leaves after the
  result in a purple puff with a last line.
- **Candy explosion** (client; `HalloweenMapFx` `{ kind = "Burst", tableId, at, amount, winner }`
  to everyone, drawn within 120 studs): a one-shot Emit of about 50 candy sprites (a 2×2 sheet of
  four candies, one image), 30 sparkles and a ring, about 2 s, half on low quality; a "+50 CANDY"
  billboard for the winner (UI_STYLE fonts); a Roblox library pop or fanfare. Not granted (the day's
  2 used): a small victory burst, no number.

### 2.8 CandyDrop (a copy of MoneyRain)

- Server loop, lobby only, while Live: every `SpawnEverySeconds` 30 (±10) per eligible player, a
  candy at a random floor spot 10-30 studs from them (MoneyRain.spot's raycast: a floor within 1.5
  studs of their feet; not within 6 studs of a queue or portal pad; not in a table's match area; 20
  tries, then skip). At most 3 alive per player and 40 per server; each lives 60 s.
- Eligible (to be targeted and to pick up): a lobby, Live, `HwOn == true` (core's gate: loaded,
  tutorial Done or Skipped), not Freecam, **not in a match** (`Tables.tableOf(p) == nil`: PLAN's
  "skip seated"; hw-sys documents that roamers collect no lobby Candy), not sitting
  (`Humanoid.SeatPart`), moved at least 4 studs in the last 60 s (not AFK).
- Pace: only lobby time earns pickups, about a fifth of a typical player's time (6.3 min a match
  including the lobby), so one candy every ~30 s of eligible lobby time gives a typical player
  about 25 an hour; a player who stays in the lobby hits core's hour cap (40,
  `Config.Halloween.Pickup.HourCap`, the only copy of that number), which is the cap's job. Retune
  `SpawnEverySeconds` from the `CandyPickups` event after publishing; log the reasoning as an
  assumption.
- Pickup tick 0.2 s, radius 5 studs. **Teleport check:** skip a player whose root moved more than
  `TeleportStuds` 12.5 (20.8 × 0.2 × 3) since the last tick, and for 1 s after (turn teleports and
  portals included). Then `local ok, reason = CandyService.pickup(player)` (core enforces the hour
  cap; this lane never counts or caps pickups itself): `ok` → destroy the candy and send that
  player `HalloweenMapFx { kind = "Pickup", at }` (a +1 billboard with the candy icon and a library
  pop); `reason == "Cap"` → leave it for others, tell the player once ("Your candy bag is full
  until :00", Strings) and stop targeting them until the next UTC hour; `"NotLive"`, `"NotLoaded"`
  or any other failure → leave it, show nothing, try again on a later tick. No client remote
  collects anything.
- Look: one shared wrapped-candy MeshPart (orange and purple Color variants), floating and spinning
  on the client (the MoneyRainFx pattern), a tiny sparkle emitter (Rate 4; 0 on low quality), a
  0.4 s pop-in.

### 2.9 Config.HalloweenMap (PLAN's numbers; every switch false until verified)

```lua
Config.HalloweenMap = {
	Enabled = false, -- the master switch: off turns every part below off; core's quests read it too
	PollSeconds = 1, FlipSeconds = 4,
	ForceAttribute = "HalloweenMapForce", -- Studio only
	StateAttribute = "HalloweenMapState", FlipAtAttribute = "HalloweenMapFlipAt",
	Night = { Enabled = false, MinBrightnessShare = 0.9,
		SunPath = { { Blend = 0, GeographicLatitude = -30, ClockTime = 7.4 },
			{ Blend = 0.5, GeographicLatitude = -30, ClockTime = 7.4 } } },
	Tables = { Enabled = false, Base = "Blue", MinDeltaE = 17,
		ByTeamSize = { [1] = { Cloth = { 185, 90, 230 }, Kit = "Orchid" },
			[2] = { Cloth = { 90, 94, 102 }, Kit = "Pumpkin" },
			[3] = { Cloth = { 88, 176, 32 }, Kit = "Toxic" } } },
	Decor = { Enabled = false, MaxPartsPerTable = 10, MaxTrianglesPerTable = 1500, Kits = {} },
	Props = { Enabled = false, Hide = {}, Place = {},
		Budget = { Triangles = 60000, MeshParts = 130, UniqueMeshes = 8, Textures = 6,
			Lights = 6 } }, -- throne 2 + the throne King's aura 1 + 3 table Kings
	Throne = { Enabled = false, Pivot = { 0, 2, -86.05 }, YawDegrees = 0, MaxHeightStuds = 18,
		PromptAt = { 0, 3, -79 } },
	Boss = { Enabled = false, Kind = "Pc", Rematch = "Never", MinTier = "Gold", TiersAbove = 2,
		TierFor = {}, MaxAtOnce = 3, SpareTables = 2, PromptStuds = 10, ServerStuds = 14,
		HoldSeconds = 0.4, ThrottleSeconds = 5, TauntEverySeconds = 6, Cue = "JackOLanternCue",
		ReadyAttribute = "PumpkinKingReadyAt", Aura = { Rate = 12, LightRange = 10 },
		Burst = { Candies = 50, Sparkles = 30, Seconds = 2, ShowStuds = 120 } },
	Candy = { Enabled = false, -- no hour cap here: core's Halloween.Pickup.HourCap
		SpawnEverySeconds = 30, JitterSeconds = 10, NearStuds = { 10, 30 }, PadClearStuds = 6,
		LifeSeconds = 60, MaxAlive = 40, MaxAlivePerPlayer = 3, PickupStuds = 5,
		PickupTickSeconds = 0.2, TeleportStuds = 12.5, TeleportGraceSeconds = 1,
		IdleSeconds = 60, IdleStuds = 4, FloorWithinStuds = 1.5, SpotTries = 20 },
}
```
Every number gets its comment in the real block (CLAUDE.md). **Keep these three keys exactly, at
these paths, always booleans:** `Config.HalloweenMap.Enabled` (the master),
`Config.HalloweenMap.Boss.Enabled` and `Config.HalloweenMap.Candy.Enabled`. Core's quest fallbacks
read them as `HM.Enabled and HM.Boss.Enabled` (King quests) and `HM.Enabled and HM.Candy.Enabled`
(pickup quests); while either is false or missing, those quests fall back to their Alt (Wins,
Balls). The prose says "King"; the Config key is `Boss`. The 10/5 cycle is `Config.Lighting.Cycle`
(Day 600, Sunset 300, Fade 10), unchanged. The Candy amounts (+1 a pickup, +50 a win, the 2-a-day
and the 15:00 cooldown) and the pickup hour cap (40, only in `Config.Halloween.Pickup.HourCap`,
enforced by `CandyService.pickup`) are core's: never copy them here.

### 2.10 Analytics (`Funnel.event`, server)

- `PumpkinKing`: value = match seconds (1 for the other steps); a = `Challenge`, `NoTable`,
  `Busy`, `Cooldown`, `Won`, `Lost` or `Left`; b = `"<playerTier>><kingTier>"`; c =
  `Funnel.device(p)`. After publishing it shows challenges per DAU, the win share per TierFor row
  (to retune it), and the NoTable + Busy share (to retune MaxAtOnce and SpareTables; keep it under 10%).
- `CandyPickups`: once per player per session, at leave: value = the Candy picked up (since
  2026-10-29; pickups = value / Pickup.Candy); a = `capped` or `ok`; b = eligible minutes bucket;
  c = device. Target about 270 Candy (54 pickups) per match hour; the cap-hit share shows exploit
  pressure.
- Neither has a number today (new features): say so in the lane file. Context (economy-candy.md
  §1): DAU about 24.9K (Oct 26), 91% new; Console 33%, PC 31%, Phone 28%, Tablet 8%, so the
  controller and phone checks matter as much as PC.

### 2.11 Edge cases (each tested, or reasoned in the lane file)

- A server booted before 19:00 flips live; one booted after starts live; Live → Ended flips back;
  a Studio force cycle Before → Countdown → Live → Ended → Live works twice in a row.
- Arenas (reserved servers of the same place): Night lighting and the 1v1 orchid look yes; throne,
  King and candy no. Props in arenas only if they cost nothing extra; decide and log.
- The event ends during a King match: it finishes; `bossWon` only while `CandyService.isLive()`;
  the throne goes once no King match runs.
- Two players race for the last free table: one gets KingNoTable. Three Kings already playing:
  KingBusy. A King bot removed by the server refresh: EmptyTeam, no reward.
- A tutorial player (`HwOn` not true) never sees the prompt and gets no candy until the tutorial
  is Done or Skipped; core's `HwOn` missing means nothing of the King or candy shows.
- `pickup` refused with `"NotLoaded"` (save still loading) or `"NotLive"` (the event just ended):
  the candy stays, no note; only `"Cap"` shows the bag-full note.
- Freecam: no prompt, no candy. Queue and portal pads never get candy on them.
- Roaming (hw-sys): a player in a match, roaming or not, neither gets candy nor can challenge;
  right after a match the teleport grace covers the move back to the lobby.
- `/day` and `/sunset` holds still work; `Config.Lighting.Cycle.Speed` stays 1 (a test checks).
- Only the throne's one box collides; nothing blocks the aisle to the throne or any pad.

## 3. Interfaces

**Deliver first** (PLAN §5; the coordinator includes this commit in the 08:15-08:30 interface
merge, so push it by 08:15; after this, your shared-file edits stay inside your own blocks):
1. `Config.HalloweenMap` (the whole shape above, every switch false, no hour-cap key;
   **`Enabled`, `Boss.Enabled` and `Candy.Enabled` are the keys core's quest fallbacks read**) and
   `Config.Lighting.Night` (first values, the same keys as Day; `light_cycle_test` passes).
2. `Strings.HalloweenMap` and the four `Strings.GlobalQueue.Failed` reason keys.
3. Net remotes `HalloweenMapFx` and `KingChallenge`.
4. The Bootstrap and Main.client blocks (guarded, switches off) and the module files they start
   (`EventMap`, `BossService`, `CandyDrop`, `MapClient`; each returns at once while its switch is
   off, nothing visible).
5. In your lane file: the attribute names (`PumpkinKingReadyAt` on players, unix seconds;
   `HalloweenMapState` and `HalloweenMapFlipAt` on workspace) and the switch keys above.
One small commit, lint and tests green, pushed; lane file Status "interfaces pushed <sha>".

**Consumed** (guarded `pcall(require, ...)` or a nil check, never a stub; after 08:30 `git fetch
&& git merge halloween`):
- Core `src/shared/Halloween/Event.luau` + `Clock.luau`: `Event.state(Clock.now())`. Missing:
  the map stays today's (never live); your Studio force works without it.
- Core `src/server/Halloween/CandyService.luau`: `bossWon(player) -> { granted, amount,
  cooldownEndsAt }`, `bossCooldown(player) -> number` (unix seconds, 0 if none),
  `pickup(player) -> (ok: boolean, reason: "Cap" | "NotLive" | "NotLoaded" | nil)` (core enforces
  `Config.Halloween.Pickup.HourCap`; you show the bag-full note only for `"Cap"`), `isLive()`.
  Missing: no candy spawns; King matches play but grant nothing (a Studio warning). Both must be
  merged by the 11:00 gate; if not, say so in Requests.
- Core's `Config.Halloween.CandyIcon` (the Candy image for the +1 and +50 billboards): a nil
  check; your own candy image while it is missing.
- Core's player attribute `HwOn` (the tutorial gate for anything Halloween). Missing: no prompt,
  no candy.
- hw-sys `src/server/Badges.luau`: `Badges.grant(player, "PumpkinSlayer", "Boss")`. Missing: no
  award.
- Cues A: the `JackOLanternCue` Catalog row (an existing cue id until it lands).
- hw-sys (Roam): nothing else to call; King matches roam like any lobby match.

**Requests to write in your lane file at once:**
- Core: you read `Config.Halloween.CandyIcon` and `CandyService.bossCooldown` (both in core's
  interface); say when either is missing after the 08:30 merge.
- Core: confirm the quest fallbacks read `HM.Enabled and HM.Boss.Enabled` and
  `HM.Enabled and HM.Candy.Enabled` (`HM = Config.HalloweenMap`, the keys you shipped in step 1),
  and that `pickup` returns `(ok, reason)` with `"Cap"` for the hour cap.
- hw-sys: noted their Request (the King's prompt refuses a player in a match; CandyDrop skips
  players in a match) and that BossService calls `Badges.grant(p, "PumpkinSlayer", "Boss")`.

## 4. Checks

- **Lune** (`tests/halloween_map_test.luau`, plus additions to `light_cycle_test` and your own
  block in the shared `config_test`): the Config shape (every `HalloweenMap` `Enabled` boolean,
  the master included; PLAN's numbers exact: the three tints, MaxAtOnce 3, SpareTables 2,
  Budget.Lights 6, the cycle 600/300/10; no hour-cap key under `HalloweenMap`); Night has Day's keys;
  `LightCycle.event` (blend 0 is Night, DuskSky is Night.Sky, SunPath held, blend 1 is Sunset);
  `Rules.kingTier` for every tier and Unranked; `Rules.hideList` never returns a
  `Config.Portals.Replaces` name; `Rules.decorInside` (inside, outside, too high);
  `Rules.eligible` (HwOn nil/false/true, freecam, in a match, sitting, idle, arena, not live);
  `Rules.teleported`; the pickup reasons (`"Cap"` shows the note and pauses targeting to the next
  UTC hour; `"NotLive"`, `"NotLoaded"` and nil show nothing); the state-change actions (Before → Countdown preloads only, → Live all on, →
  Ended all off, Live → Live nothing); the three tints' raw ΔE ≥ 17 against the ball colours if
  Config has them (else the Python check is the guard).
- `tools/lint.sh` and `tools/test.sh` green before every commit; `tools/format.sh` only on the
  files you changed.
- **Studio, your window only** (`list_roblox_studios`, pick `lane-hw-map.rbxl`; Rojo 34886;
  scripts are files, never made through MCP): console clean in Edit and Play; the force cycle;
  Day vs Night captures from one camera; a King match from the prompt to the burst (a test win
  through BotsQA or a weak tier, then the real tier); 5 minutes walking for candy (count; core's cap
  reached in Studio shows the bag-full note, a not-loaded refusal shows none); the ΔE captures; the counts (triangles, MeshParts, lights, emitters)
  against the budget; frame time (Stats/MicroProfiler) with everything on vs off.
- **Devices:** the prompt (and its cooldown text), the notices, the +1 and +50 billboards and the
  King's portrait in the match HUD at phone 844×390, iPad 1024×768, PC 1920×1080 and TV 1920×1080
  with GuiQA "pad" (the prompt shows the X glyph). `tools/halloween/studio_size.sh lane-hw-map.rbxl
  <w> <h>`, then read `workspace.CurrentCamera.ViewportSize` through MCP and adjust until it
  matches. If the helper fails (macOS permission), say so in the lane file and rely on the
  coordinator's sweep.
- **Fresh-player run** (you touch join lighting, the tutorial's lobby and the first match): a new
  save joins during Live; the tutorial (no King prompt, no candy), the Skip path too; the first
  match on an orchid table under Night (balls readable); then the prompt appears; console clean.
- **Screenshots** to `~/Desktop/8ball-refs/halloween/shots/hw-map/` (gate sets in `gate1/` and
  `gate2/`), one line per image in the lane file's Gate shots.

## 5. Cut order (a cut is switched off and listed, never half-visible)

1. The ambience sound and the bats.
2. Cape sway, string lights, cobwebs.
3. Taunts beyond the intro and result lines.
4. Decor kit extras (bat emblems, pumpkin corners, cobweb cards); keep the underglow and trim.
5. The new purple sky (Night keeps Sunset's sky; DuskSky = Sunset.Sky).
6. Dead trees (the palms stay; pumpkins at their pots).
7. The throne figure's aura and idle (a still, seated King).

**Never cut** (the release and core's quests depend on them): Night lighting and the event cycle,
the table colours by mode, the throne with the King challenge, `bossWon` and a burst, CandyDrop
with its pickups, the automatic on and off. If one of these is at risk by 13:00, write it in
Requests at once. Should the King or the drops ever ship switched off, core's quests fall back to
their Alt by themselves (they read `HM.Enabled and HM.Boss.Enabled` and `HM.Enabled and
HM.Candy.Enabled`), so a cut never leaves a quest nobody can finish.

## 6. Gates

Lane clock: 07:30-08:15 interfaces; to 09:00 Night and table looks; to 11:00 the King (bot_duel
runs in the background from step 6); 11:00-14:00 candy, decor, props, sky; 14:00-16:00 the flip
test, performance, switches on, devices, fresh player, merge. From 08:45 the coordinator merges on
request: ask in your lane file's Requests when a verified part should land early.

- **09:00 Gate 1** (`gate1/`): the lobby wide from MAP2's angle, Day vs Night from one camera, and
  Sunset; the three table looks close up under Night with the ΔE table; the Night sky (uploaded
  faces, or gen_sky's cross preview if not uploaded yet); the brightness numbers. If needed, one
  question: the pad-glow reading.
- **11:00 Gate 2** (`gate2/`): the throne at the end of the aisle seen from the spawn; the King
  close up on the throne (head, crown, cape, aura, cue; a placeholder King head is accepted here,
  labelled as such, with the real one by 13:00); a King match in progress at a lobby table; the
  candy explosion; the difficulty table (the rows bot_duel has finished). Candy pieces and first
  props if ready.

## Progress

- [x] 1. Interfaces pushed by 08:15: Config.HalloweenMap (all switches off; the `Enabled`, `Boss.Enabled` and `Candy.Enabled` keys; no hour-cap key) and Lighting.Night shape, Strings, the two Net remotes, the Bootstrap and Main blocks with their switched-off modules; lane file Requests and attribute names written; lint and tests green.
- [x] 2. `HalloweenMap/Rules.luau` with its Lune tests (kingTier, hideList, decorInside, eligible, teleported, state actions).
- [x] 3. EventMap's switch: Event.state with the Studio force, the two workspace attributes, idempotent on and off, a boot during Live.
- [x] 4. Night: Lighting.Night tuned in Play, `LightCycle.event` and `mixStates`, DayCycle following the state with preload and crossfade; Night ≥ 0.9 of Day's brightness, measured.
- [x] 5. Table looks by mode at run time (black frame + tints, restored at the end); rendered ΔE ≥ 17 under Night and Sunset, table in the lane file; gate 1 shots by 09:00.
- [x] 6. First start `bot_duel` in the background for every TierFor row (200 games each, `--no-write`, output to a log outside the repo) so step 9 only reads it; then the BotService boss hooks (description, icon, animations, dress, playBoss, BotsQA "boss"), Body's new arguments, People's icon.
- [x] 7. King look (description, head, crown, cape, suit pieces, aura, idle; a placeholder head is fine for gate 2, the real one by 13:00) and the throne at the piano spot with the throne figure; the piano hidden; the Rojo round trip of the first .rbxm checked.
- [x] 8. BossService: prompt, server checks, free table with 2 spare, MaxAtOnce 3, notices, taunts, analytics; a King match end to end in Studio.
- [x] 9. Difficulty from the background bot_duel runs for every TierFor row (win shares in the lane file; a row under 20% stepped down, re-measured and logged).
- [x] 10. The reward: bossWon on every win, bossCooldown into `PumpkinKingReadyAt` and the prompt countdown, `Badges.grant` Pumpkin Slayer, the candy explosion; gate 2 shots by 11:00.
- [x] 11. CandyDrop and its client FX: spawning, eligibility, the teleport check, CandyService.pickup's `(ok, reason)`, the bag-full note only for `"Cap"`, analytics; a 5-minute walk test.
- [x] 12. The purple night sky: gen_sky night variant (headless), 6 uploads, Night.Sky ids, the Night-to-Sunset swap checked in Play.
- [x] 13. `TableBuilder.addDecor` and the three kits (bounds-checked, no collision), on every table, removed at the end.
- [x] 14. Props: dead trees, pumpkins, spooky planters, tombstones, string lights, cobwebs (headless Blender, uploads, Assets); the hide list applied and restored; the budget counted.
- [x] 15. The full flip test: Before → Countdown → Live → Ended → Live in one Play session, a boot during Live, an arena (lighting and tables only); console clean.
- [x] 16. Performance pass: counts against the budget, frame time on vs off, the low-quality path, the server loops' cost.
- [x] 17. Every verified part's switch set true in Config, each checked once with its own switch off (before the device and fresh-player runs, so they test what ships).
- [x] 18. Devices: prompt, notices, billboards and portrait at the four sizes and with the pad; screenshots.
- [x] 19. Fresh-player run during Live (tutorial, Skip, first match, the prompt after the tutorial).
- [x] 20. Lane file Status final + all screenshots.
- [x] 21. Merge halloween, re-test, push.

## Notes
