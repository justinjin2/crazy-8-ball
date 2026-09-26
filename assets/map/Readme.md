# Rooftop map package

The hub map: an open-air rooftop pool club. The brief is `docs/prompts/ROOFTOP_MAP_PROMPT.md`;
the measured facts are `Spec.md`; the budget is `Budget.md`.

## Files

| File | What it is |
|---|---|
| `map_layout.py` | Every position (tables, zones, props, cameras) with checks; writes `Layout.json` |
| `measure_palette.py` | The colours measured from the art; writes `Palette.json` |
| `gen_plan.py` | Draws `Plan.png` and the side-by-side with the art's top-down |
| `gen_graybox.py` | The gray-box data for Studio (`src/server/MapData/GrayBox.json`, git-ignored) |
| `gen_compare.py` | Art-versus-game side-by-sides for the checkpoints |
| `map_common.py` | Shared helpers: the palette, the trim sheet layout, the Blender mesh builder, the FBX export |
| `gen_textures.py` | The textures, drawn procedurally at 2048 and exported at 1024 into `textures/` |
| `gen_rooftop.py` | The architecture (Blender, headless); writes `fbx/Rooftop.fbx` and `Map.blend` |
| `gen_props.py`, `props/*.py` | The props: one template per kind (family modules), headless; writes `fbx/Props.fbx`, `Props.json` and `Props.blend` |
| `reference/` | The concept art |
| `checkpoints/` | Captures and side-by-sides (git-ignored) |

## Rebuild

From the repo root, with `B=/Applications/Blender.app/Contents/MacOS/Blender`:

```bash
python3 assets/map/map_layout.py        # the plan; fails on any layout problem
python3 assets/map/gen_textures.py      # the textures
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_rooftop.py            # the FBX
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_rooftop.py -- render  # and Blender renders
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_props.py              # the props FBX
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_props.py -- render    # and a render per kind
python3 assets/map/gen_graybox.py       # the gray-box data (Rojo syncs it)
tools/test.sh                           # map_layout_test and map_config_test among them
```

## Import into Studio (the architecture and the props)

Do this whenever `fbx/Rooftop.fbx` or `fbx/Props.fbx` changes; re-importing only the one that
changed is fine.

1. In Studio, **File**, then **Import 3D**, then choose `assets/map/fbx/Rooftop.fbx`.
2. In the import window: **Scale Unit: Stud**, scale **1**, **Merge Meshes off**, **Import
   Materials/Textures off**. Click **Import**. The model, named `Rooftop`, lands in Workspace;
   where does not matter.
3. The same again for `assets/map/fbx/Props.fbx` (the model is named `Props`).
4. Run this in the command bar (or the agent runs it through the MCP):

   ```lua
   local Server, Shared = game.ServerScriptService.Server, game.ReplicatedStorage.Shared
   local MB, spec = require(Shared.MapBuilder:Clone()), require(Shared.Config:Clone()).Map
   local data = require(Server.MapData.GrayBox:Clone())
   print(MB.prepareImport(spec, data)) print(MB.prepareProps(spec, data))
   ```

   - **The architecture:** `prepareImport` places it by its anchor cubes and sets every mesh
     up from `Config.Map.Meshes`. It makes the floor's MaterialVariant and builds
     `Workspace.Map.Collision.Arch`.
   - **The props:** `prepareProps` keeps the imported props as templates in
     `ServerStorage.MapProps`, then clones one to every spot in the plan
     (`Workspace.Map.Props`). It makes the invisible Seat parts (`Workspace.Map.Seats`) and
     the lights, and builds `Workspace.Map.Collision.Props`.
   - Each removes the gray-box parts it replaces. Any `PROBLEM:` line says what to fix. Both
     are safe to run twice.
5. Save the place and publish (once per milestone).

## Changing a texture

1. Re-run `gen_textures.py`.
2. Upload the changed PNGs through the Studio MCP `upload_image` from a local
   `python3 -m http.server` (four per batch). Uploads render at 1024.
3. Put the ids in `Config.Map.Maps` or `Config.Map.Floor`, then run step 4 above again.

## Credits

`CREDITS.md`. Everything so far is drawn by the scripts; no outside assets.
