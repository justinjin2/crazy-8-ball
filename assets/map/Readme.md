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
| `reference/` | The concept art |
| `checkpoints/` | Captures and side-by-sides (git-ignored) |

## Rebuild

From the repo root, with `B=/Applications/Blender.app/Contents/MacOS/Blender`:

```bash
python3 assets/map/map_layout.py        # the plan; fails on any layout problem
python3 assets/map/gen_textures.py      # the textures
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_rooftop.py            # the FBX
$B -b --factory-startup --python-exit-code 1 --python assets/map/gen_rooftop.py -- render  # and Blender renders
python3 assets/map/gen_graybox.py       # the gray-box data (Rojo syncs it)
tools/test.sh                           # map_layout_test and map_config_test among them
```

## Import the architecture into Studio

1. In Studio, **File**, then **Import 3D**, then choose `assets/map/fbx/Rooftop.fbx`.
2. In the import window: **Scale Unit: Stud**, scale **1**, **Merge Meshes off**, **Import
   Materials/Textures off**. Click **Import**. The model, named `Rooftop`, lands in Workspace.
   It does not matter where: the next step puts it back exactly.
3. Run this in the command bar (or the agent runs it through the MCP):

   ```lua
   local Server, Shared = game.ServerScriptService.Server, game.ReplicatedStorage.Shared
   print(require(Shared.MapBuilder:Clone()).prepareImport(require(Shared.Config:Clone()).Map, require(Server.MapData.GrayBox:Clone())))
   ```

   It moves the model into `Workspace.Map`, places it by its anchor cubes, sets every mesh
   up from `Config.Map`, makes the floor's MaterialVariant, builds `Workspace.Map.Collision`
   and removes the gray-box parts the architecture replaces. Any `PROBLEM:` line in its report
   says what to fix. It is safe to run twice.
4. Save the place and publish (once per milestone).

## Changing a texture

1. Re-run `gen_textures.py`.
2. Upload the changed PNGs through the Studio MCP `upload_image` from a local
   `python3 -m http.server` (four per batch). Uploads render at 1024.
3. Put the ids in `Config.Map.Maps` or `Config.Map.Floor`, then run step 3 above again.

## Credits

`CREDITS.md`. Everything so far is drawn by the scripts; no outside assets.
