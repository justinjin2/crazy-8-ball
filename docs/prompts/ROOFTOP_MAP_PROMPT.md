# Rooftop map: master prompt

For the agent. The designer starts a session with one line that points here. This file is the
brief for building the hub map. Run it stage by stage, stop at every CHECKPOINT, and keep the
progress log at the bottom current, so a fresh session (or one after a context compaction)
knows exactly where to pick up. Before each stage, re-read that stage in section 9.

## 0. The job

Build the hub map of Crazy 8 Ball: an open-air **rooftop pool club** on top of a tower, with a
**city skyline on the left** and a **tropical coast with steep green mountain islands on the
right**, as seen from the entrance. Match the concept art in `assets/map/reference/` as closely
as Roblox allows: layout, proportions, props, colours, lighting and mood. There are two lighting
states, **Day** and **Sunset** (no night), and the game cycles between them. It must run well on
phones, consoles and PCs.

"As close as possible" means a player standing at the entrance recognises the art at a glance:
the same layout, the same props in the same places, the same colours, the same skyline and
islands behind, and the same warm lantern glow at sunset. Where the designer decided otherwise
(section 3), the decision wins over the art.

## 1. Read first

1. `CLAUDE.md`, `docs/STATUS.md`, `docs/ARCHITECTURE.md`.
2. `docs/GDD.md` section 10 (hub) and section 16 (table looks); the last 30 lines of
   `docs/DECISIONS.md`.
3. `docs/STUDIO_NOTES.md` in full (Rojo, Studio MCP, SurfaceAppearance facts, Blender).
4. `assets/table/Readme.md`, `assets/table/TableModel.py` and `table_common.py`: the proven
   Blender to FBX to 3D Importer to `prepareImport` pipeline. Copy its conventions: parameters
   and seed at the top of each script, built-in checks, renders.
5. `src/shared/Config.luau` (`Config.Hub`, `Config.Spawn`, `Config.TableModel`,
   `Config.Multiplayer.Queue`) and `src/shared/Placement.luau` (`matchFence`, `queueBox`): the
   gameplay footprint the map must leave clear.
6. Every image in `assets/map/reference/`. Look at each one.

Do **not** look at the git history, renders, briefs or packages of removed maps (the Skyline
Club hub and the older 12-table lounge). The designer wants zero influence from them.

## 2. The references

| File | Authority for |
|---|---|
| `02-day-view.jpg` | The rooftop at near-player height: floor, tables, planters, lanterns, glass railing, pergola, couches, umbrellas, palms. **Highest authority for the rooftop.** |
| `03-detail-assets.jpg` | Each prop's design: lounge couch, fire pit, pergola, umbrella seating, planter, light. **Highest authority for props.** |
| `panels/top-down.jpg` | The layout: 4 by 4 tables, the pergola lounge across the back, entrance steps at the front centre, city left, ocean right. |
| `panels/day.jpg`, `panels/sunset.jpg` | The whole rooftop from a high three-quarter view in each light. Sunset: magenta and purple sky, an orange sun low over the ocean on the right, warm lanterns, lit windows. |
| `panels/entrance.jpg`, `panels/lounge-back.jpg` | Eye-level views: the entrance columns and the lounge. |
| `panels/city-side.jpg`, `panels/ocean-side.jpg` | The backdrop's content and density. |
| `panels/key-assets.jpg` | Extra prop views (same props as `03`). |
| `01-concept-sheet.jpg` | The original sheet the panels were cut from. |

When images disagree, `02` wins for the rooftop and `03` wins for props. The art's tables are
blue; ours are green (section 3). The art shows an infinity-pool strip and red banners; both
are out.

## 3. Decided by the designer (2026-09-26)

- **All 16 tables use the Green look** (the regular lobby; blue stays for the Pro lobby).
  `Config.TableModel.LookByTable` becomes empty (`DefaultLook` is already Green).
- **Tables turned sideways, like the art:** their long sides face the entrance, 4 across and
  4 deep. Recompute `Config.Hub.Tables`: yaw 0 or 180, whichever puts each queue box where it
  reads best; spacing = the match fence (`Placement.matchFence`) plus a walkway of at least
  6 studs, so planters fit at the aisle crossings like the art. `Config.Spawn` goes on the
  landing at the top of the entrance steps, facing the tables. The rooftop floor stays at
  Y = 0, so table Y stays 0.
- **Day and sunset cycle, the same for everyone on a server:** Day 10 min, 1 min fade, Sunset
  5 min, 1 min fade, repeat. No night.
- **In:** the pergola lounge with sectional couches and round coffee tables, a **fire pit** in
  the lounge, a **grand piano** under the pergola, the **snack counter** (GDD section 10;
  visuals only for now: the drink tool is a later feature, so leave an Attachment named
  `SnackCounterServe` where it will hand drinks out), square planters with ferns, palms,
  lanterns, umbrella seating with loungers, the glass railing, the entrance steps.
- **Out:** the infinity-pool strip, banners, and anything else that is not in the art.
- Couches, loungers and the piano bench are sittable (GDD section 10): Seat parts.
- Four checkpoints where you stop and wait for the designer's OK (section 9).

Record these in GDD section 10 (Decided) and `docs/DECISIONS.md` if they are not there yet.

**Later decisions win.** The Stage 0 interview changed some of the above (the table looks by
mode, the queue pads in front of each table, the side seating, the prop scale, the back bar):
`assets/map/Spec.md` section 0 is the current list.

## 4. The look

- **Kid-friendly, calm and clean. Bright and saturated, never neon or muddy.** The playing area
  reads first; everything else supports it.
- **Colours are measured from the art, not guessed.** In Stage 0, sample each region of the
  references with Python (Pillow and numpy, k-means on a crop): floor, grout, planter, couch,
  each cushion colour, lantern glass, railing frame, foliage light and dark, palm trunk, water
  near and far, sand, island green, mountain far, sky top and horizon for Day and for Sunset,
  sun, city glass day and sunset. Write the hex values into `assets/map/Spec.md` and use only
  those (via `map_common.py`). The green table look is the existing one.
- **Style: "low poly, clean", like the asset sheet.** Simple bevelled shapes, smooth colour
  gradients, soft baked ambient occlusion in the colour maps (Roblox has no GI on phones, so AO
  is what makes props read). No grime, noise, dirt or photo textures left raw: Poly Haven
  textures are only inputs to a bake, tinted and simplified to the palette.
- **Not busy (hard rules):**
  - Main walkways at least 8 studs wide from the spawn to every queue box and to the lounge.
    Nothing inside any match fence or queue box. Nothing to snag on in a walkway.
  - Props in a regular, symmetric rhythm like the art: along the edges and at aisle crossings,
    never scattered.
  - Floor: large light tiles with low-contrast grout, no fine pattern that shimmers on a phone.
  - The green cloth is the most saturated thing at eye level. The backdrop is hazier and less
    saturated than the rooftop.
  - No flashing, strobing or fast motion. Ambient motion only: two or three sailboats drifting
    slowly, the water, a gentle fire-pit flicker.
  - Start with the prop counts in the art. At Checkpoint B the designer may thin them.

## 5. Layout (from the top-down panel)

From the front (the entrance, +Z toward the spawn) to the back:

- **Entrance:** wide steps up at the front centre, flanked by big planters with palms and two
  tall lanterns (entrance panel: cream columns frame the view). The spawn is on the landing.
- **Table field:** the 4 by 4 grid, centred left to right. Small square fern planters at the
  aisle crossings. Lanterns along the outer aisles. A soft warm **under-table glow** on the
  floor around each table's base: a flat textured glow plane, not a light.
- **Sides:** a low parapet with a dark-framed glass railing. City side (left): planters and
  palms against the railing. Ocean side (right): two or three umbrella sets with loungers, and
  palms.
- **Back:** raised by one or two steps, the pergola lounge across the back: cream columns, a
  slatted roof with vines and a few pink flowers (as in `02`), hanging globe lights; U-shaped
  sectional couches in warm grey with blue, teal and orange cushions and round dark coffee
  tables; the fire pit in the middle of one couch group; the grand piano; the snack counter at
  one end. Behind the lounge, the railing and open sea.
- **The sun:** before placing the backdrop, measure `Lighting:GetSunDirection()` at the sunset
  `ClockTime` you pick (and `GeographicLatitude`). The sunset sun must sit low over the ocean,
  to the right and slightly behind, as in `panels/sunset.jpg`. If it does not, change latitude
  and time within reason, or else swap which world side the ocean is on (the composition from
  the entrance must stay city left, ocean right). Never fake the sun. Use
  `Sky.SkyboxOrientation` to put the painted sunset glow behind the sun.
- **Below and around:** the tower's own walls with windows dropping to street level. City side:
  streets and neighbour roofs below ours, with a few towers taller than ours as in the art.
  Ocean side: a beach promenade, sand and palms, turquoise shallows, then deep blue sea and the
  islands.

## 6. Budgets (the whole game stays under 1,000,000 triangles)

| Group | Triangle cap |
|---|---|
| 16 tables (existing, 8,134 each) | 130,000 |
| Balls, cues, effects (existing) | 20,000 |
| Rooftop architecture: floor, parapet, railing, steps, pergola, tower top | 60,000 |
| Props: couches, coffee tables, planters, palms, lanterns, umbrellas, loungers, fire pit, piano, snack counter, globe lights | 140,000 |
| Near surroundings: tower walls, neighbour roofs, streets, promenade, beach, boats | 50,000 |
| Mid backdrop: skyline and islands | 110,000 |
| Far cards | 2,000 |
| **Everything we ship** | **512,000** |
| Headroom for players' avatars and accessories | 488,000 or more |

Per-instance caps: palm 2,500 (trunk 600 or less, fronds as alpha cards); fern planter 1,200;
square planter box 300; sectional couch 3,000; coffee table 500; lantern 400; umbrella with two
loungers 2,500; fire pit 1,500; grand piano 4,000; snack counter 4,000; globe light 150;
pergola 8,000.

Everything else:
- **Textures:** 20 unique images at most for the map, authored at 2048 to 4096 and exported at
  1024 (Roblox renders 1024 at most; downsampling avoids shimmer). Share atlases: an
  architecture trim sheet, a props atlas, a foliage alpha atlas, a window strip, the floor-tile
  MaterialVariant. Plus two skyboxes (six faces each) and four far-card images at most.
- **Mesh counts:** 400 MeshParts at most for the rooftop and props; about 30 for the backdrop
  (the agreed plan), merged by material and split into chunks around the rooftop.
- **Lights:** 20 PointLights, SpotLights or SurfaceLights at most in total, Shadows off. Every
  other glow is Neon or an emissive-looking texture.
- **Part settings:** everything Anchored. CastShadow off for small props, foliage and the
  backdrop. CanCollide, CanTouch and CanQuery off except the floor, steps, parapet, railing,
  walls, pergola posts and big props (those get CollisionFidelity Box or Hull). RenderFidelity
  Automatic on rooftop props (Roblox's own LOD), Performance on the backdrop. If
  `Workspace.StreamingEnabled` is on, the backdrop models use ModelStreamingMode Persistent so
  the skyline never pops.
- **Transparency:** few, large transparent surfaces (glass panels, water). Foliage uses alpha
  cards merged per planter.
- **Safety:** an invisible wall above the railing tall enough that nobody can jump off, and
  `Workspace.FallenPartsDestroyHeight` below the street.

Count triangles in Blender before export (evaluated meshes, after modifiers) and again in Studio
after import (EditableMesh, see STUDIO_NOTES). Keep a running table in `assets/map/Budget.md`.

## 7. Tools, sources and agents

**MCP servers** (check them in Stage 0):
- **roblox-studio:** `list_roblox_studios` first (every call needs `studio_id`), `execute_luau`
  (Edit-mode building, property writes, camera placement), `screen_capture`,
  `inspect_instance`, `search_game_tree`, `upload_image` (http URLs from a local
  `python3 -m http.server`, batches of four), `start_stop_play`, `get_console_output`, and the
  `skill` tool: `rbx-scene-analysis` (memory and draw stats), `rbx-device-simulator-lua` (phone
  views), `rbx-perf-profiling`, `rbx-docs-search` (API facts; use it instead of guessing).
- **blender** (Blender 5.2): `execute_blender_code`, `get_viewport_screenshot`,
  `get_scene_info`; Poly Haven (`search_polyhaven_assets`, `download_polyhaven_asset`: CC0
  textures such as tiles, concrete, wood, fabric, bark, sand); Poly Pizza
  (`search_polypizza_models`, `download_polypizza_model`: low-poly models, a fallback for
  palms and ferns only). Headless runs:
  `/Applications/Blender.app/Contents/MacOS/Blender -b --python <script>`.

**Sources, in this order:**
1. Procedural Blender scripts in the repo, for everything by default: they are reproducible and
   keep one style.
2. Poly Haven CC0 textures, as inputs to the texture bake.
3. Poly Pizza models, CC0 or CC-BY only, when a procedural palm or fern clearly loses to the
   art after one round; restyle and retexture them to the palette.

Record every outside asset (name, author, licence, URL) in `assets/map/CREDITS.md`. Never use
NC or ND licences, Sketchfab, Creator Store models, or AI generators (Hyper3D, Hunyuan3D, Tripo,
and Studio's `generate_mesh`, `generate_procedural_model`, `generate_texture`,
`generate_material`). They cannot be rebuilt from the repo, they drift from the style, and
they break the budgets.

**The package, `assets/map/`** (laid out like `assets/table/`):
- `map_common.py`: the palette from the Spec, shared materials, bevel and AO helpers, the FBX
  export, the triangle counter.
- One generator per group, each with its parameters and seed at the top: `gen_rooftop.py`,
  `gen_props.py` (one function per prop), `gen_near.py`, `gen_skyline.py`, `gen_islands.py`,
  `gen_farcards.py`, `gen_sky.py`. A re-run is the tweak.
- `textures/` (1024 exports committed; masters are rebuilt from scripts), `fbx/`, `Map.blend`
  (commit only when the model changed), `renders/` (final reference-view renders only),
  `Readme.md` (import steps), `Spec.md`, `Budget.md`, `CREDITS.md`.
- Checkpoint and comparison images go in `assets/map/checkpoints/` (gitignored).

**The Roblox side:**
- `Workspace.Map` holds the Edit-mode content in the place: `Rooftop`, `Props`, `Near`,
  `Backdrop` (chunks), `FarCards`, all imported with the 3D Importer.
- A `prepareImport`-style function in `src/shared/MapBuilder.luau`, run from `execute_luau` in
  Edit mode like `TableBuilder.prepareImport` (with the `Config:Clone()` trick from
  STUDIO_NOTES). It is safe to run twice: it parents and flattens, sets anchoring, collision,
  shadows, fidelity and streaming, applies SurfaceAppearances and MaterialVariants from Config
  ids, creates Seats, lights and glow parts, and prints `PROBLEM:` lines (a budget over its
  cap, a part inside a match fence, a missing texture id).
- **Day and sunset:** every number in a new `Config.Lighting` section (colours as hex strings,
  because Config loads in Lune where `Color3` does not exist). A pure cycle function in
  `src/shared` (server time to phase and blend 0..1), Lune-tested. A client module applies the
  blend to Lighting, Atmosphere, Sky, ColorCorrection, Bloom, SunRays, lantern and window glow,
  driven by `workspace:GetServerTimeNow()` so every client agrees with no network traffic.
  Plus an Edit-mode preview call that applies Day or Sunset for screenshots.
- Scripts are files under `src/`, synced by Rojo. Never create or edit scripts through MCP.

**Agents:**
- **You (the main session)** own the live Blender and the live Studio. Only one agent touches
  each at a time.
- **Parallel builders** (Agent tool, general-purpose): in stages 3 and 5, independent
  generators (a prop family each; skyline and islands) can be written in parallel by subagents.
  They only run headless Blender on their own files and return renders and triangle counts.
  They never touch the live Blender, Studio, Config or git. Give each one the Spec,
  `map_common.py`, its caps and its reference crops.
- **Reference analyst** (Stage 0): a subagent drafts the Spec from the images; you check its
  numbers against the gameplay footprint.
- **Critic** (Agent tool, a fresh one every time, never a builder): reviews the side-by-side
  images after every stage (section 8).

## 8. The verification loop (every stage)

1. **Blender:** render or viewport-screenshot the new work from the matching reference angles.
   Check the triangle counts.
2. **Studio (Edit mode):** import and prepare, then place `workspace.CurrentCamera` at the
   Spec's camera poses (CFrame and FieldOfView) and `screen_capture` each one: entrance,
   day-view (`02`), high three-quarter (day and sunset panels), top-down, lounge-back,
   city-side, ocean-side, and a phone-size view at player eye height.
3. **Side by side:** reference on the left, capture on the right, same crop and aspect, made
   with Pillow into `assets/map/checkpoints/<stage>-<view>.jpg`.
4. **Critic:** a fresh subagent with this prompt, filled in:
   > You are a strict art director for a kids' Roblox game. In each image, LEFT is the concept
   > art and RIGHT is the game: `<paths>`. Score 1 to 10: layout and proportions, silhouettes,
   > palette, materials, lighting and mood, backdrop, calm (not busy), readability on a phone.
   > List the 5 biggest differences in order of how much they hurt the likeness, each with a
   > concrete fix (what, where, how much). Flag anything busy, dark, muddy or noisy, anything
   > hard to read on a phone, and anything in the game that is not in the art. No praise.
5. **Fix and repeat,** up to 3 rounds per stage, until every score is 8 or more, or the
   remaining gap is a Roblox limit (say which one).
6. **Numbers:** the budget table, texture and light counts, a script check that no part sits
   inside a match fence or queue box, a clean console in play-solo, and `tools/lint.sh` and
   `tools/test.sh` passing when code changed.
7. **Commit** only this stage's files (other sessions may have work in progress), push, and add
   a line to the progress log.

## 9. Stages and checkpoints

**Stage 0: preflight and spec**
- Check: `list_roblox_studios`; Blender `get_addon_status` (up to date),
  `get_polyhaven_status` and `get_polypizza_status` (enabled); `rojo serve` running and synced
  (`script_grep` for a string you know); `git status`. If `Config.luau` or any file you will
  touch has uncommitted changes from another session, stop and tell the designer.
- Write `assets/map/Spec.md`: the measured palette (section 4); the prop list with counts;
  sizes in studs (the table's real size from Config is the scale bar for everything in the
  art; a player is about 5 studs tall); the rooftop plan with dimensions, walkway widths and
  prop positions; a camera pose for each reference view; the sun plan.
- Draw the plan as a top-down PNG (Pillow) with the fences, queue boxes, walkways and props, and
  compare it with `panels/top-down.jpg`.

**Stage 1: grid and gray-box**
- Config: the new `Hub.Tables`, `Spawn`, and an empty `LookByTable`; update the tests; lint and
  test.
- Studio: remove the baseplate. Gray-box Parts for the floor, steps, parapet, railing, pergola,
  lounge, planters, palms (cylinders and spheres), lanterns and umbrellas; the tower below;
  simple blocks for the city and islands at their distances; a Terrain water plane.
- Play-solo: walk from the spawn to every queue box and to the lounge. Nothing blocks, and
  nobody can fall off.
- **CHECKPOINT A:** stop. Show the designer the plan PNG, and the entrance and high
  three-quarter captures side by side with the art, with the layout numbers. Wait for OK.

**Stage 2: rooftop architecture (Blender)**
- Floor tiles as a MaterialVariant (or a baked mesh if the tile grid must line up with the
  tables), parapet, dark-framed glass railing, steps, pergola (columns, slatted roof, vines),
  the tower's top floors, the under-table glow planes. Import, prepare, verify.

**Stage 3: props (Blender; parallel builders allowed)**
- Every prop in `03-detail-assets.jpg`, plus palms, the grand piano, the snack counter, globe
  lights and loungers. Seats. Import, place them from the Spec, verify.
- **CHECKPOINT B:** the rooftop and props in day light (use a temporary Day preset from the
  Spec; Stage 7 makes the real one). Wait for OK. The designer may thin props here.

**Stage 4: near surroundings, ocean and the day sky**
- Tower walls, neighbour roofs and streets below, the promenade, the beach, Terrain water,
  sailboats. The day skybox (clouds only), rendered in Blender by `gen_sky.py` to six faces.
  Atmosphere day values.

**Stage 5: mid backdrop (parallel builders allowed)**
- Skyline generator: glass towers of varied heights like the art, a window-strip texture, a
  few landmark towers. Islands generator: steep green conical mountains, beaches and rocks.
  Merged into about 10 to 20 MeshParts sharing one palette texture, split into chunks around the
  rooftop so the ones behind the camera are not drawn.

**Stage 6: far cards**
- Skyline and island silhouettes rendered from the same generators to transparent PNGs, on flat
  cards at 2000 studs and beyond, faded by Atmosphere.
- **CHECKPOINT C:** city side, ocean side and the high three-quarter view against the art. Wait
  for OK.

**Stage 7: sunset and the cycle**
- The sunset skybox, rendered from the **same cloud scene** as the day one (same cloud shapes,
  sunset light), so swapping skies at mid-fade reads as a colour change. Sunset Atmosphere,
  ColorCorrection, Bloom and SunRays. The Neon window-glow mesh, on only at sunset. Lanterns,
  globe lights, under-table glow and the fire pit brighter at sunset.
- `Config.Lighting`, the pure cycle function with Lune tests, the client module. If the sky
  swap pops, add a short haze bump or a third in-between skybox, and say which you chose.
- Ask the designer to set `Lighting.Technology` to Future in Properties (scripts cannot). Check
  the look at quality levels 1 and 10, the `rbx-scene-analysis` numbers, and phone-size views
  via `rbx-device-simulator-lua`.
- **CHECKPOINT D:** day, sunset and a mid-fade capture against the art, and a short timed run
  of the cycle in Play (a test-only speed multiplier in Config). Wait for OK.

**Stage 8: finish**
- The final budget table, the Readme's import steps, the docs (STATUS, DECISIONS, GDD section
  10, and STUDIO_NOTES for anything learned), commit and push. Then ask the designer once to
  save the place to `place/8ball.rbxl` and publish. List what still needs a real phone, a
  console and a PC.

## 10. Things only the designer can do

Tell the designer the exact clicks, one step at a time, when each one is needed:
- **Rojo:** click Connect in the Rojo plugin after any Studio or Rojo restart.
- **3D Importer:** File > Import 3D, choose the FBX, the settings from `assets/map/Readme.md`
  (Scale Unit: Stud, scale 1), Import. Then you run `prepareImport`.
- **Lighting.Technology = Future** in Properties (Stage 7).
- **Save and publish** once, at the end.
- Uploaded images need Roblox moderation before other players see them.

## 11. Reporting

The designer is a beginner. After each stage, say in plain words: what was built, what was
checked (with the side-by-side paths and the critic's scores), the budget table, what to look
at in Studio, and what comes next. Commit as soon as a stage is verified; never ask for commit
approval. Never guess an Open item: ask.

## 12. Progress log

One line per stage: date, stage, result, commit.

- 2026-09-26: brief written, references saved in `assets/map/reference/`, designer decisions
  recorded. Next: Stage 0.
- 2026-09-26: Stage 0 done. Preflight: Studio and Rojo synced; headless Blender 5.2 runs;
  the Blender MCP add-on file is updated (protocol 11) but its live connection waits on a
  Blender restart and Start MCP Server. Spec, measured palette (79 regions), layout with checks, plan PNG,
  budget table; designer interview recorded in Spec section 0. Sun measured: sunset is a
  dawn sun (latitude -30, ClockTime 6.4). Next: Stage 1, which also moves the queue pad to
  the table's front long side in Placement.
- 2026-09-26: Stage 1 done.
  - Config: the rooftop grid (16 sideways tables, 36 x 31.5 apart), mode looks and the spawn
    mat. The queue pad sits in front of each table (Queue.PadSide); the other session made it
    a rectangle, and the rows re-spaced from it.
  - The gray-box: MapBuilder.buildGrayBox from gen_graybox.py data.
  - Critic, 3 rounds: layout 5, 5, 6; calm 5, 6, 5; phone 5, 4, 6. The rest waits for later
    stages.
  - Play: 24 of 24 paths from the spawn and 7 of 7 edge pushes pass.
  - Commits 51e2b89, c67d1c5, 616c555, 6446ee3.
  - Carried forward (Spec section 7 and the stages): the big island right of the pergola
    (azimuth about 25, about 6 degrees tall); a denser, slimmer skyline; heavier pergola
    columns and fascia (Stage 2); the stair-flank palms against ferns (Checkpoint B).
  - Waiting at CHECKPOINT A.
- 2026-09-26: CHECKPOINT A approved by the designer with changes: the snack counter is out,
  the piano is centred at the back of the lounge, the railing is 5 studs tall, and the city
  is densest ahead and left of the spawn (a street-grid gray-box). Next: Stage 2.
- 2026-09-26: Stage 2 done (three critic rounds, the cap).
  - The architecture is built in Blender by gen_rooftop.py: parapet, the glass railing at a
    character's head, steps, the pergola, the tower top, the table glow and floor shade.
  - The floor is Parts with a MaterialVariant (Part materials map in world space).
  - Five procedural 1024 textures and a Day light preset (Config.Lighting.Day).
  - In Studio 3,834 triangles, matching Blender; 24 of 24 paths and 7 of 7 edge pushes pass.
  - Critic: layout 6, calm 6, phone 5; the rest waits for props and lighting.
  - The last round's pergola change (3 bays, taller; 3,790 triangles) is built but not yet
    imported: it goes in with Stage 3's import.
  - Commits 9b098db, 6f6c794, e845f10, 237a2e8, 9aab8e7. Next: Stage 3 (props).

