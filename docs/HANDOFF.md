# Handoff (written 2026-09-19, from the Claude desktop session to Claude Code CLI)

Read this after `CLAUDE.md` and before `docs/ROADMAP.md` and `docs/MVP_PLAN.md`. It is the
state of the project the moment the previous session stopped, plus everything that session
learned the hard way. The user (Justin) is a beginner: explain clicks and decisions simply.

## Where things stand

Done and committed (all verified in Studio): M0 setup, M1 rolling ball, M2 collisions and
pockets, M3 aim and shoot, M4 camera and avatar. On top of the plan:

- Imported Blender 9 ft table (`ServerStorage.PoolTableModel` in the place, 7 MeshParts,
  19,220 triangles, 28 PBR maps) with the parts-built table as fallback.
- Smart orbit camera: sits opposite the aim, auto-frames the whole table for any ball
  position, aim and screen shape, zooms continuously into a low "down the cue" view, pulls
  out to the whole table during a shot and returns to the player's zoom. `Config.Camera`.
- Guideline drawn as a corridor one ball wide (two edge lines plus dashed centre), ring at
  first contact, object and cue stubs. `Config.Guideline`.
- Mesh balls: `ServerStorage.BallMesh` (imported sphere, id `rbxassetid://123564130691976`),
  16 baked textures in `Config.Balls.Textures`, set as `TextureID` per clone. Fallback to
  Part and decals when the mesh is missing. One shadow-casting SpotLight over the table.
- Join flow: walk up, hold E on the table's ProximityPrompt, Leave button. Avatar posed
  procedurally, faded, invisible when close to the camera.

Not done: M5 spin selector, M6 look pass, M7 sound and juice, M8 rules (ROADMAP 2.1).
The user also said the mesh balls have "apparent issues" to come back to (not described yet).
Known cheap improvements: the ball mesh is 2,208 triangles, 24 x 12 (about 550) is enough;
one shadow light per table will not scale to 12 tables (use sun shadows plus non-shadow lights).

## The next phase, as the user asked for it (2026-09-19)

"The blend has 12 tables, just make them all playable, make the chairs sittable and make it
so you can actually get drinks from the bar and drink/eat." This is the user's decision to
bring the lounge into scope now; `CLAUDE.md`'s "ask before adding a lounge" no longer applies.
Still out of scope unless asked: bots, abilities, coins, shop, data saving, menus beyond
joining a table.

What that implies, to be planned before coding (use plan mode and ask the user the few
questions that change the design):

1. **Twelve playable tables in one server means other players must see every table's
   balls.** Today `Match` runs `Simulation.run` on the client and `BallRenderer` creates
   ball parts on the client only. The physics was designed for this move: the server owns
   each table's `state`, receives `{angle, power, spin}` through a RemoteEvent, runs
   `Simulation.run` (pure Luau, already server-safe), and broadcasts the `ShotResult`
   (or just inputs plus a deterministic seed-free replay) so every client plays the same
   frames. One table module instance per table (`PoolTable_01` .. `_12`), join prompt per
   table, `Config.World.TableOrigin` becomes per-table origins from `assets/lounge/Markers.json`.
2. **Seats**: Roblox `Seat` parts placed on the sofa, loveseat, armchair and ottoman meshes
   (`Furniture_*` in `exports/Lounge_Furniture.fbx`), invisible, anchored; the default
   humanoid sit handles the pose.
3. **Bar**: `Furniture_SnackCounter`, `Furniture_SnackFridge`, `Props_SnackCounter_Service`.
   A ProximityPrompt gives a `Tool` (drink or snack, a few variants) into the backpack;
   activating it plays a short drink/eat animation (procedural like the aiming pose, or a
   Creator Store animation) and removes the tool. No currency.
4. **Performance**: `StreamingEnabled` on, table meshes `RenderFidelity = Automatic`,
   decorative meshes `CastShadow = false`, no per-table shadow lights.

The lounge package is in `assets/lounge/` (built by a separate Blender agent; read its
`Readme.md`, `Markers.json`, `DECISIONS.md`). Six FBX files in `assets/lounge/exports/`
(Architecture, Furniture, Props, Signs, Emissive, Collision), textures in
`assets/lounge/textures/`. The lounge FBX files contain no table meshes: tables are placed
at the twelve `Markers.json` positions (rotation 90 degrees around Y) using the existing
`ServerStorage.PoolTableModel`. Importing FBX is a user click step (3D Importer, Scale
Unit: Stud, scale 1); `TableBuilder.applyModelTextures` shows how SurfaceAppearances were
applied to the table in Edit mode, do the same for the lounge sets.

## Studio and tooling facts

- Rojo: `rojo serve default.project.json` (port 34872) must be running, and after every
  Studio restart or Rojo restart the user must click Connect in the Rojo plugin. Verify sync
  with the MCP `script_grep` for a string you just added before playtesting. Studio's
  Play copy is a snapshot: stop Play, sync, start Play.
- The place file holds things scripts cannot create: `PoolTableModel` (with
  SurfaceAppearances and collision fidelity), `BallMesh`, the `PoolClothBlue`
  MaterialVariant. The user must save the place after any Edit-mode change.
- Studio MCP: every call needs `studio_id` from `list_roblox_studios`. `screen_capture`
  is black in Play mode; preview visuals in Edit mode (build the table with
  `TableBuilder.build(workspace)`, add preview parts in a `CameraPreview` folder, set the
  camera, capture, then destroy the preview and the table). Edit-mode `require` results
  are cached for the Studio session: when Config changed since the last Edit require,
  patch the cached table in the preview script. Beams do not render in captures.
  `upload_image` needs http URLs: `python3 -m http.server 8765 --bind 127.0.0.1 --directory assets`,
  batches of 4 or Studio disconnects. `execute_luau` in Edit is unavailable during Play.
  MCP tools can leave Edit `UserInputService.MouseBehavior = LockCurrentPosition`; reset
  it to Default after previews. Mouse/keyboard input tools are flaky; prefer numeric
  checks through `execute_luau` on the Client (e.g. `WorldToViewportPoint`).
- Simulating the join prompt from a Client script: teleport the character next to
  `workspace.PoolTable.JoinPrompt`, wait half a second, then `InputHoldBegin`, wait,
  `InputHoldEnd`.
- The user gave standing permission to stop an active Studio play session when verifying,
  and to commit after each verified step without waiting for the word "approve".
- Blender 5.2 is installed at `/Applications/Blender.app` (headless:
  `/Applications/Blender.app/Contents/MacOS/Blender -b file.blend --python-expr "..."`).
- StyLua reformatting breaks exact-string edits: after every scripted edit, grep for the
  new text. Lune tests: `tools/test.sh` (21 pass in about 0.6 s). `tools/lint.sh` before
  every commit.

## Verification loop that worked

`tools/lint.sh`, `tools/test.sh`, `script_grep` for sync, start Play, `execute_luau`
(Client) numeric checks, `get_console_output`, stop Play, Edit-mode preview screenshot,
cleanup, update docs, commit.
