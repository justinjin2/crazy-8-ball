# Pool table package (Pro-Am style, two looks)

This folder holds one table model, built headlessly in Blender from the game's physics. Every
look (skin) uses the same model and only changes textures. The standing brief is
`docs/prompts/TABLE_BLENDER_PROMPT.md`. The decisions behind it are in `docs/DECISIONS.md`
(2026-09-24).

## Rebuild

Run everything from the repo root. With `B=/Applications/Blender.app/Contents/MacOS/Blender`:

```bash
lune run tools/export_table_geometry.luau                                  # physics -> Geometry.json
$B -b --factory-startup --python-exit-code 1 --python assets/table/TableModel.py     # model, ~10 s
$B -b --factory-startup --python-exit-code 1 --python assets/table/TableTextures.py  # 17 maps
$B -b assets/table/TableModel.blend --factory-startup --python-exit-code 1 --python assets/table/TableRender.py            # shape renders
$B -b assets/table/TableModel.blend --factory-startup --python-exit-code 1 --python assets/table/TableRender.py -- looks   # look renders
tools/test.sh   # table_geometry_test, table_looks_test, table_model_test
```

- `TableModel.py` fails (exit 1) if any check fails: the physics match within 0.01 in,
  triangle budgets, gaps, UVs, the FBX round trip and orientation.
- Its measurements go to `Parameters.json`, which `tests/table_model_test.luau` checks against
  Config and the physics.

## Files

| File | What it is |
|---|---|
| `Geometry.json` | The physics, exported for Blender. Generated; do not edit. |
| `TableModel.py`, `table_common.py` | The model builder. |
| `PoolTable.fbx` | The model (8 meshes). |
| `TableModel.blend` | The .blend (scripts embedded). |
| `Parameters.json` | Measurements, UV layout and validation results. |
| `TableTextures.py` | The texture builder. |
| `textures/*.png` | The 1024 upload maps. |
| `Textures.json` | Texture recipe, seeds and hashes. |
| `sources/Sources.json` | The CC0 sources. The downloads themselves and the 4096 masters are git-ignored. |
| `TableRender.py` | Checkpoint renders. |
| `renders/preview_*.png` | The approved look renders. |
| `legacy/` | The old 7-mesh table, kept until sign-off. |

The meshes are Cloth, Rails, Body, Pockets, Caps (removable chrome caps), Hardware (leg bolts),
LogoPlate (the orientation marker, at the foot) and Marks (a transparent overlay). The total is
8,134 triangles.

## Import into Studio (after the mesh changes)

1. Home, then **Import 3D**, then `assets/table/PoolTable.fbx`.
2. Settings: **Scale Unit: Stud**, scale 1, **Merge Meshes off**, **Import Materials/Textures
   off**.
3. Name the model **PoolTable** and drag it into **ServerStorage**. Do not rotate it.
4. Run the prepare snippet in `docs/STUDIO_NOTES.md` ("Preparing an imported table"). It undoes
   the importer's half turn and builds `ServerStorage.TableLooks`.
5. Save and publish.

## Changing a look or textures

1. Re-run `TableTextures.py`.
2. Upload the changed PNGs through the Studio MCP `upload_image`, from a local
   `python3 -m http.server`, 4 per batch. Uploads render at 1024.
3. Put the ids in `Config.TableModel.Maps`.
4. Run the prepare snippet again, then save.

Cloth colours are tints (`Config.TableModel.Looks.<Look>.Cloth.Tint`) and can change without
any new images. A new skin is a new `Looks` row plus maps, never new code.

## Credits (all CC0)

- Billiard cloth statistics: TextureCan #527.
- Cherry veneer grain: Poly Haven `cherry_veneer`.
- Leather: ambientCG Leather026.

Details are in `sources/Sources.json`.
