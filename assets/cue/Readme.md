# Cue package (one shared mesh, many skins)

Every cue that has a skin is the same mesh with different pictures on it. The mesh is a lathe
(a profile spun round, 32 sides) built headlessly in Blender from the game's own cue outline,
so the drawn cue and the band cues have exactly the same shape. Classic is the first skin; the
other cues keep their band look until they get one. The brief was
`docs/prompts/CUE_MESH_PROMPT.md`; the report is `docs/prompts/CUE_MESH_REPORT.md`.

## Rebuild

Run everything from the repo root. With `B=/Applications/Blender.app/Contents/MacOS/Blender`:

```bash
lune run tools/export_cue_shape.luau        # Config + Catalog -> Shape.json (only after changing the cue's size, Profile or Classic zones)
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CueModel.py                 # mesh, UVs, checks, Cue.glb (~5 s)
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CueRender.py -- --mesh      # renders/checkpoint_mesh.png
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CueTextures.py -- --areas   # renders/areas.png (for the sheet)
python3 assets/cue/CueTemplate.py                                                           # template/<panel>_{input,guide,test}.png
python3 assets/cue/CueTemplate.py --sheet                                                   # template/sheet.png
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CueTextures.py -- --skin assets/cue/skins/_test.json    # renders/template_check.png
$B -b --factory-startup --python-exit-code 1 --python assets/cue/CueTextures.py -- --skin assets/cue/skins/classic.json  # Classic's maps and render
tools/test.sh   # cue_shape_test (Shape.json is current), cue_mesh_test (MeshSkins are catalog cues)
```

- `CueModel.py` exits 1 if any check fails: the outline matches Shape.json, closed and
  outward-facing, triangles under budget, UVs without overlap, mirroring or stretch, the glb
  round trip. The results go to `Parameters.json`.
- `CueTemplate.py` runs on the Mac's own Python 3 with Pillow (`pip3 install pillow`), not
  in Blender.
- Changing the mesh means uploading it again and rebuilding every skin's template in Studio,
  because a new upload is a new asset id. Do that only when the shape really changes.
- **When the cue's width changes** (shape 3, 2026-10-04: butt 0.32 -> 0.36, slim front kept), everything built
  on the old shape follows, in this order: Shape.json and the mesh (above); every skin repainted
  (`python3 tools/cue_skin.py <ids> --paint --maps --thumb --noaura`; Classic with `--maps --thumb`
  only, it has no paint recipe); `python3 tools/cue_widen.py` moves each skin's effects out with
  the surface (idempotent, migrates from frozen `shapes/shape2.json`, stamps `"shape": 3`); the pieces on the butt read the new radius
  (`CuePieces.butt_gain`/`butt_growth`) and are rebuilt with `CuePieces.py -- <ids> --no-preview` and
  `tools/cue_pieces_glb.py`; the Dragon's and Phoenix's Segment hosts are copied from the build
  prints; then everything is uploaded again and the templates rebuilt in Studio. The AI-painted
  panels are resized to the new panel shapes, not re-bought: from the side only half the
  circumference shows, so the squeeze barely reads.

## Files

| File | What it is |
|---|---|
| `Shape.json` | The cue's outline and zones, exported from Config and the catalog. Generated. |
| `CueModel.py`, `cue_common.py` | The mesh and UV builder, and the shared helpers. |
| `Cue.glb` | The mesh (4,160 triangles), uploaded to Roblox. |
| `CueModel.blend` | The .blend (scripts embedded). |
| `Parameters.json` | Axes, the UV layout, the paint-kit panels and every check's result. |
| `CueTemplate.py`, `template/` | The paint kit: `sheet.png`, and per panel `_input` (for ChatGPT), `_guide` (for you), `_test` (the mapping check). `CHATGPT.md` is the how-to. |
| `CueTextures.py` | Turns a skin file into the four 1024 maps. |
| `skins/*.json` | Skin files. `classic.json` is procedural; `_test.json` is the mapping check. |
| `textures/<id>_*.png` | The maps (color, normal, roughness, metalness; emissive when a skin glows). |
| `CueRender.py`, `renders/` | Preview renders (git-ignored). |

## Make a new skin

1. **Paint the panels.** Follow `template/CHATGPT.md`. Save the five pictures in
   `assets/cue/skins/<id>/` and write `assets/cue/skins/<id>.json` (copy `_test.json`). `<id>`
   is lower case, for example `neon`.
2. **Build the maps.** Run the `CueTextures.py -- --skin assets/cue/skins/<id>.json` line
   above. Look at `renders/<id>.png`: every side of the cue and close-ups of each join. Fix the
   pictures and run it again until it looks right.
3. **Upload the maps.** Put the four (or five) map paths in a text file, one per line, then:
   ```bash
   python3 tools/roblox_upload.py --list maps.txt --group-id 675425213 --dry-run
   python3 tools/roblox_upload.py --list maps.txt --group-id 675425213
   ```
   Each image comes back as a Decal id. Get the real image id from it (docs/STUDIO_NOTES.md,
   "Images come back as a Decal ID") and write it into `tools/upload_manifest.json`.
4. **Build the template in Studio (Edit mode, not Play).** In the Explorer, open
   `ReplicatedStorage > CueSkins`, copy `Classic` and paste it into `CueSkins`. Rename the
   copy to the cue's catalog id, exactly as in `src/shared/Progression/Catalog.luau` (for
   example `NeonCue`). Select its `Cue > SurfaceAppearance` and paste the four image ids into
   ColorMap, NormalMap, RoughnessMap and MetalnessMap (`rbxassetid://<image id>`). Leave
   everything else as it is.
5. **Turn it on.** Add the id to `Config.Cue.MeshSkins`. The first time there are two mesh
   skins, write the SurfaceAppearance swap in `CueStickBuilder` (the note in `paintStick` says
   how) and lift the one-skin guard in `tests/cue_mesh_test.luau`.
6. **Check and save.** Play, equip the cue, look at it in your hands, on your back and in the
   Index. Then save the place to `place/8ball.rbxl` and publish.

## Frames (so a skin lands the right way up)

- Blender: 1 unit = 1 stud, the tip at the origin, the cue along −Y, the UV seam along −Z.
- Roblox's glTF import turns the model 180° about Y and centres it: in the MeshPart the tip
  is at local +Z 3.5 and the seam faces local −Y (down in the hand, toward the body on the
  back). The template's `PivotOffset` puts the pivot at the tip with +Z toward the butt, the
  frame `CueStickBuilder` places every cue in.
