# 8BALL Lounge — delivery notes

Built through the connected Blender MCP in Blender 5.2.2 LTS. The lounge uses cream plaster, honey timber, teal seating, blue playing-zone rugs, coral and butter accents, and warm sunset lighting. Twelve unchanged source-table collection instances form three ascending rows of four. There is no real-world table branding.

**Final validation: PASS.** Read `Validation.md` for the readable results and `Validation.json` for complete numeric checks.

Open `Lounge.blend`. The embedded `LoungeBuilder.py` and the standalone script are the rebuildable source. `PARAMETERS` controls room dimensions, table positions, stair dimensions, palette-related construction, texture size, AO strength, camera, and render settings. All new output remains beside the script. `../table/PoolTable.py` and the source table files remain unchanged.

## Coordinates and layout

One Blender coordinate unit is one Roblox stud, with 0.16 stud per inch. Authoring is native Z-up. FBX exports use −Z Forward / Y Up, scale factor 1, and FBX Unit Scale, transforming `(x, y, z)` into `(x, z, −y)`. All six packages retain the same world-zero assembly origin. Architecture uses world-zero mesh origins. Movable furniture keeps base-centre pivots with placement translation retained; rotations and scales are applied. Table instances rotate +90° around native Z, equivalent to +90° around exported Roblox Y.

| Parameter | Value |
|---|---|
| Interior dimensions | 98.00 × 163.00 studs |
| Table column centres, native X | -30, -10, 10, 30 |
| Table row centres, native Y | 0, 43, 86 |
| Floor heights, native Z / exported Y | 0, 2.4, 4.8 |
| Rotated table footprint | 9.76 across X × 17.76 along native Y |
| Source table cloth / rail top | 2.9 / 3.2328 studs above each floor |
| Minimum table clearance | 10 studs to tables, walls, furniture, railings, and steps |
| Each stair flight | Three 0.8-rise × 1.6-run steps; 80-stud usable width |
| Pendant lower edge | 7.5 studs above its table floor |
| Foreground entrance | 5 wide × 8 high |

Shared ten-stud corridors separate adjacent tables. The long room and generous tier spacing prioritize the numeric cue clearance over the tightly packed reference image. Table numbers 1–4 are the front row, 5–8 the middle row, and 9–12 the rear row. `DECISIONS.md` records architectural and composition tradeoffs.

## Package assembly in Roblox Studio

1. Import each of the six FBX files below. In File Geometry, set **Scale Unit: Stud** and keep scale factor **1**. Retain child MeshPart positions and pivots. Place the package containers at the common assembly origin; do not individually centre, resize, or reposition their children.
2. Import the existing table package separately once using the same Stud setting. Duplicate or instance that model twelve times using `Markers.json` positions and Y rotations. The lounge FBX files intentionally contain no table meshes. The Blender file references one appended collection of the source’s seven finished table meshes.
3. Assign one SurfaceAppearance per textured MeshPart. Use its `set_name` / baked material name to choose `<Set>_Color.png` for ColorMap and `<Set>_Roughness.png` for RoughnessMap. Assign MetalnessMap when the set has a matching metalness file. Texture colour spaces are sRGB for Color and data/Non-Color for Roughness and Metalness.
4. Assign `Emissive_*` meshes Roblox **Neon**, using their flat warm colours. They require no SurfaceAppearance. Assign `Glass_Windows` Roblox **Glass** with a light blue tint and approximately 0.65 transparency. Keep glass separate from opaque architecture.
5. Keep every environment object anchored. Use Box collision for simple rectangular architecture and Hull for appropriate convex pieces. Import `COL_*` proxies from the Collision package, set Transparency=1 and CanCollide=true, and use Box/Hull collision as appropriate. Stair and tier-edge proxies are intentionally simple. Set decorative furniture details, plants, art, signs, Neon, and glass CanCollide=false; use the supplied proxy where a decorative assembly needs collision. Disable decorative CastShadow where useful for mobile performance.
6. Add the twelve downward-facing pendant lights and a seating-area spawn using `Markers.json`. Its positions are already Roblox Y-up studs; do not apply a second axis conversion. The included Lighting, Bloom, and ColorCorrection values are adjustable starting settings.

| File | Contents |
|---|---|
| `exports/Lounge_Architecture.fbx` | Shell, floors, tiers, steps, ceiling grid, pillars, windows, and separate Glass_Windows |
| `exports/Lounge_Furniture.fbx` | Seating, rugs, coffee table, ottoman, and snack-counter furniture |
| `exports/Lounge_Props.fbx` | Plants, art, clock, cue racks, pendant housings, and small related props |
| `exports/Lounge_Signs.fbx` | Table numbers, separate 1v1 / 2v2 / 3v3 zone signs, Refresh & Play, and blank logo panel |
| `exports/Lounge_Emissive.fbx` | Separate untextured Neon geometry |
| `exports/Lounge_Collision.fbx` | Hidden simple COL_* collision proxies |

## Geometry and texture delivery

Each exported mesh has one material and one 0–1 UV map. The bake workflow packs related source pieces into shared atlases by texture set, applies modifiers and transforms as appropriate to the pivot policy, and triangulates export geometry. `SOURCE_Lounge_*` procedural materials remain available in the blend. Source BaseColor, Roughness, and Metalness channels use Cycles emission-pass baking; direct lighting and cast shadows are excluded from Color maps. A separate 32-sample Cycles AO bake is multiplied into BaseColor at 16% strength. Maps are 1024 × 1024 or smaller. Normal maps are omitted because the restrained stylized surfaces and modeled bevels do not require them.

The `Signs` atlas is separate and replaceable. Zone signs and table placeholders remain independently named and editable. Replace the sign artwork within its UV island, or update the text in the builder and rebake the Signs set. `Sign_Logo_Blank` is a blank 10 × 3 stud panel for the game’s own artwork.

| Texture set found on disk | Maps | Color dimensions |
|---|---|---|
| Architecture_A | Color, Roughness | 1024 × 1024 |
| Floor_A | Color, Roughness | 1024 × 1024 |
| Furniture_A | Color, Roughness | 1024 × 1024 |
| GameProps_A | Color, Roughness | 1024 × 1024 |
| Props_A | Color, Roughness, Metalness | 1024 × 1024 |
| Signs | Color, Roughness | 1024 × 1024 |
| Timber_A | Color, Roughness | 1024 × 1024 |

Final per-object triangle counts (table instances excluded):

| Object | FBX group | Texture set | Triangles | Validation |
|---|---|---|---:|---|
| Beam_Cross_0_-13.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_0_-27.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_0_-41.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_0_-55.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_0_1.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_0_15.0 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_1_25.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_1_39.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_1_53.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_2_68.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_2_82.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Cross_2_96.8 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_-10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_-30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_-48 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_0_48 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_-10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_-30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_-48 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_1_48 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_-10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_-30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_-48 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_10 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_30 | Architecture | Timber_A | 108 | PASS |
| Beam_Long_2_48 | Architecture | Timber_A | 108 | PASS |
| COL_SnackCounter | Collision | Untextured | 12 | PASS |
| COL_Stair_Ramp_1 | Collision | Untextured | 8 | PASS |
| COL_Stair_Ramp_2 | Collision | Untextured | 8 | PASS |
| COL_TierEdge_1_-1 | Collision | Untextured | 12 | PASS |
| COL_TierEdge_1_1 | Collision | Untextured | 12 | PASS |
| COL_TierEdge_2_-1 | Collision | Untextured | 12 | PASS |
| COL_TierEdge_2_1 | Collision | Untextured | 12 | PASS |
| Ceiling_0 | Architecture | Architecture_A | 12 | PASS |
| Ceiling_1 | Architecture | Architecture_A | 12 | PASS |
| Ceiling_2 | Architecture | Architecture_A | 12 | PASS |
| Cue_Rack_0 | Props | Props_A | 1868 | PASS |
| Cue_Rack_1 | Props | Props_A | 1868 | PASS |
| Cue_Rack_2 | Props | Props_A | 1868 | PASS |
| Door_Lintel | Architecture | Architecture_A | 108 | PASS |
| Emissive_Downlight_0_-20_-16.6 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_-20_-48.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_-20_16.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_-40_-16.6 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_-40_-48.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_-40_16.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_0_-16.6 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_0_-48.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_0_16.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_20_-16.6 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_20_-48.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_20_16.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_40_-16.6 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_40_-48.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_0_40_16.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-20_32.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-20_45.3 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-20_59.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-40_32.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-40_45.3 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_-40_59.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_0_32.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_0_45.3 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_0_59.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_20_32.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_20_45.3 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_20_59.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_40_32.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_40_45.3 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_1_40_59.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-20_75.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-20_86.4 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-20_99.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-40_75.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-40_86.4 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_-40_99.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_0_75.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_0_86.4 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_0_99.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_20_75.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_20_86.4 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_20_99.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_40_75.8 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_40_86.4 | Emissive | Untextured | 60 | PASS |
| Emissive_Downlight_2_40_99.0 | Emissive | Untextured | 60 | PASS |
| Emissive_Pendant_01 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_02 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_03 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_04 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_05 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_06 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_07 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_08 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_09 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_10 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_11 | Emissive | Untextured | 108 | PASS |
| Emissive_Pendant_12 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_0_0 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_0_1 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_0_2 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_1_0 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_1_1 | Emissive | Untextured | 108 | PASS |
| Emissive_Stair_1_2 | Emissive | Untextured | 108 | PASS |
| Floor_Main | Architecture | Floor_A | 108 | PASS |
| Floor_Mezzanine | Architecture | Floor_A | 108 | PASS |
| Floor_Middle | Architecture | Floor_A | 108 | PASS |
| Floor_Seams_0 | Architecture | Floor_A | 312 | PASS |
| Floor_Seams_1 | Architecture | Floor_A | 156 | PASS |
| Floor_Seams_2 | Architecture | Floor_A | 156 | PASS |
| FrontPier | Architecture | Architecture_A | 108 | PASS |
| FrontPier.001 | Architecture | Architecture_A | 108 | PASS |
| Furniture_Armchair_Teal_Right | Furniture | Furniture_A | 1296 | PASS |
| Furniture_CoffeeTable_Oak | Furniture | Furniture_A | 716 | PASS |
| Furniture_Loveseat_Cream | Furniture | Furniture_A | 1512 | PASS |
| Furniture_Ottoman_Butter | Furniture | Furniture_A | 852 | PASS |
| Furniture_Rug_Lounge | Furniture | Furniture_A | 1696 | PASS |
| Furniture_SideTable_Oak | Furniture | Furniture_A | 852 | PASS |
| Furniture_SnackCounter | Furniture | Furniture_A | 1314 | PASS |
| Furniture_SnackFridge | Furniture | Furniture_A | 324 | PASS |
| Furniture_SnackWallCabinet | Furniture | Furniture_A | 540 | PASS |
| Furniture_Sofa_Teal_Foreground | Furniture | Furniture_A | 1944 | PASS |
| Furniture_Sofa_Teal_Left | Furniture | Furniture_A | 1728 | PASS |
| Glass_Windows | Architecture | Untextured | 36 | PASS |
| Pendant_01_Housing | Props | Props_A | 164 | PASS |
| Pendant_02_Housing | Props | Props_A | 164 | PASS |
| Pendant_03_Housing | Props | Props_A | 164 | PASS |
| Pendant_04_Housing | Props | Props_A | 164 | PASS |
| Pendant_05_Housing | Props | Props_A | 164 | PASS |
| Pendant_06_Housing | Props | Props_A | 164 | PASS |
| Pendant_07_Housing | Props | Props_A | 164 | PASS |
| Pendant_08_Housing | Props | Props_A | 164 | PASS |
| Pendant_09_Housing | Props | Props_A | 164 | PASS |
| Pendant_10_Housing | Props | Props_A | 164 | PASS |
| Pendant_11_Housing | Props | Props_A | 164 | PASS |
| Pendant_12_Housing | Props | Props_A | 164 | PASS |
| Pillar_-1_-34 | Architecture | Architecture_A | 108 | PASS |
| Pillar_-1_105.4 | Architecture | Architecture_A | 108 | PASS |
| Pillar_-1_18.6 | Architecture | Architecture_A | 108 | PASS |
| Pillar_-1_61.6 | Architecture | Architecture_A | 108 | PASS |
| Pillar_1_-34 | Architecture | Architecture_A | 108 | PASS |
| Pillar_1_105.4 | Architecture | Architecture_A | 108 | PASS |
| Pillar_1_18.6 | Architecture | Architecture_A | 108 | PASS |
| Pillar_1_61.6 | Architecture | Architecture_A | 108 | PASS |
| Playing_Rug_0 | Furniture | Furniture_A | 108 | PASS |
| Playing_Rug_1 | Furniture | Furniture_A | 108 | PASS |
| Playing_Rug_2 | Furniture | Furniture_A | 108 | PASS |
| Props_Art_Back_Eight | Props | Props_A | 1236 | PASS |
| Props_Art_Back_Rack | Props | Props_A | 3164 | PASS |
| Props_Art_Left_Eight | Props | Props_A | 1236 | PASS |
| Props_Art_Left_Rack | Props | Props_A | 3164 | PASS |
| Props_Clock_Main | Props | Props_A | 2080 | PASS |
| Props_CoffeeTable_StillLife | Props | Props_A | 784 | PASS |
| Props_Plant_CoffeeTable | Props | Props_A | 392 | PASS |
| Props_Plant_Left_01 | Props | Props_A | 392 | PASS |
| Props_Plant_Left_02 | Props | Props_A | 392 | PASS |
| Props_Plant_Left_03 | Props | Props_A | 392 | PASS |
| Props_Plant_Left_04 | Props | Props_A | 392 | PASS |
| Props_Plant_Lounge_Left | Props | Props_A | 392 | PASS |
| Props_Plant_Lounge_Rear | Props | Props_A | 392 | PASS |
| Props_Plant_Lounge_Right | Props | Props_A | 392 | PASS |
| Props_Plant_Right_01 | Props | Props_A | 392 | PASS |
| Props_Plant_Right_02 | Props | Props_A | 392 | PASS |
| Props_Plant_Right_03 | Props | Props_A | 392 | PASS |
| Props_Plant_Right_04 | Props | Props_A | 392 | PASS |
| Props_Plant_SideTable | Props | Props_A | 392 | PASS |
| Props_SnackCounter_Service | Props | Props_A | 4476 | PASS |
| Rail_Solid_0_-1 | Architecture | Architecture_A | 108 | PASS |
| Rail_Solid_0_1 | Architecture | Architecture_A | 108 | PASS |
| Rail_Solid_1_-1 | Architecture | Architecture_A | 108 | PASS |
| Rail_Solid_1_1 | Architecture | Architecture_A | 108 | PASS |
| Sign_Logo_Blank | Signs | Signs | 108 | PASS |
| Sign_RefreshAndPlay | Signs | Signs | 1112 | PASS |
| Sign_RefreshAndPlay_Panel | Signs | Signs | 108 | PASS |
| Skirting_-1_0 | Architecture | Timber_A | 108 | PASS |
| Skirting_-1_1 | Architecture | Timber_A | 108 | PASS |
| Skirting_-1_2 | Architecture | Timber_A | 108 | PASS |
| Skirting_1_0 | Architecture | Timber_A | 108 | PASS |
| Skirting_1_1 | Architecture | Timber_A | 108 | PASS |
| Skirting_1_2 | Architecture | Timber_A | 108 | PASS |
| Stair_1_1 | Architecture | Floor_A | 108 | PASS |
| Stair_1_2 | Architecture | Floor_A | 108 | PASS |
| Stair_1_3 | Architecture | Floor_A | 108 | PASS |
| Stair_2_1 | Architecture | Floor_A | 108 | PASS |
| Stair_2_2 | Architecture | Floor_A | 108 | PASS |
| Stair_2_3 | Architecture | Floor_A | 108 | PASS |
| Table_DisplayProps_01 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_02 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_03 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_04 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_05 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_06 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_07 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_08 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_09 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_10 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_11 | Props | GameProps_A | 1316 | PASS |
| Table_DisplayProps_12 | Props | GameProps_A | 1316 | PASS |
| Table_Number_01 | Signs | Signs | 96 | PASS |
| Table_Number_02 | Signs | Signs | 212 | PASS |
| Table_Number_03 | Signs | Signs | 284 | PASS |
| Table_Number_04 | Signs | Signs | 144 | PASS |
| Table_Number_05 | Signs | Signs | 224 | PASS |
| Table_Number_06 | Signs | Signs | 272 | PASS |
| Table_Number_07 | Signs | Signs | 128 | PASS |
| Table_Number_08 | Signs | Signs | 368 | PASS |
| Table_Number_09 | Signs | Signs | 288 | PASS |
| Table_Number_10 | Signs | Signs | 248 | PASS |
| Table_Number_11 | Signs | Signs | 132 | PASS |
| Table_Number_12 | Signs | Signs | 248 | PASS |
| TierEdge_0_-1 | Architecture | Architecture_A | 108 | PASS |
| TierEdge_0_1 | Architecture | Architecture_A | 108 | PASS |
| TierEdge_1_-1 | Architecture | Architecture_A | 108 | PASS |
| TierEdge_1_1 | Architecture | Architecture_A | 108 | PASS |
| Wall_Back | Architecture | Architecture_A | 108 | PASS |
| Wall_Clock_Panel | Architecture | Architecture_A | 108 | PASS |
| Wall_Left | Architecture | Architecture_A | 108 | PASS |
| Wall_Left_Middle_Upper | Architecture | Architecture_A | 108 | PASS |
| Window_Frames_0 | Architecture | Timber_A | 756 | PASS |
| Window_Frames_1 | Architecture | Timber_A | 756 | PASS |
| Window_Frames_2 | Architecture | Timber_A | 756 | PASS |
| Window_Header_0 | Architecture | Architecture_A | 108 | PASS |
| Window_Header_1 | Architecture | Architecture_A | 108 | PASS |
| Window_Header_2 | Architecture | Architecture_A | 108 | PASS |
| Window_SillWall_0 | Architecture | Architecture_A | 108 | PASS |
| Window_SillWall_1 | Architecture | Architecture_A | 108 | PASS |
| Window_SillWall_2 | Architecture | Architecture_A | 108 | PASS |
| Zone_1v1 | Signs | Signs | 156 | PASS |
| Zone_2v2 | Signs | Signs | 388 | PASS |
| Zone_3v3 | Signs | Signs | 532 | PASS |

Environment total: **78422 / 150,000 triangles**. Largest exported mesh: **4476 / 10,000 triangles**. Collision proxies must each remain below 200 triangles. The source table is 19,220 triangles; its twelve render instances total 230,640 source-table triangles and are excluded from the lounge environment budget and exports.

## Validation

| Check | Result |
|---|---|
| Per-mesh triangle limit | PASS |
| Environment triangle limit | PASS |
| One material / one UV map | PASS |
| UV bounds / no interior overlap | PASS |
| Triangulation / no live modifiers | PASS |
| Applied rotation/scale and sensible origins | PASS |
| Manifold or explicitly documented open surfaces | PASS |
| Texture-set count and dimensions | PASS |
| Twelve tables / three ascending rows | PASS |
| Ten-stud table clearance | PASS |
| Glass / Neon / collision meshes present | PASS |
| all_required_deliverables_exist | PASS |
| six_aligned_fbx_packages | PASS |
| fbx_reimport_coordinates_1e_6 | PASS |
| hero_1920x1080_cycles_128_denoised | PASS |
| wide_top_down_render | PASS |
| ao_baked_without_direct_light | PASS |
| pendant_and_spawn_marker_data | PASS |
| blend_saved_after_validation | PASS |

UV validation exhaustively bins candidate triangle pairs and numerically clips their UV triangles to test interior intersection; it does not infer validity from an unwrap operator succeeding. UV bounds tolerance is 1e-7 and interior-area tolerance is 1e-12 UV². Applied transform and origin checks use 1e-5 stud tolerance. The independent FBX reimport coordinate gate uses the stricter **1e-6 stud** tolerance in a clean collection.

Clearance validation uses each table’s actual instance transform and authoritative footprint, then checks every other table and every tagged wall, furniture, plant, stair, and guardrail bounding box. It reports the minimum and four facing-side clearances per table. Supporting floors, flat rugs, overhead ceiling/pendants, and overhead table number plaques do not obstruct the floor clearance.

## Rendering and resuming work

`renders/hero.png` uses the final recipe of **1920 × 1080, Cycles, 128 samples, denoised**. `renders/layout_top.png` provides a clear wide top-down layout. EEVEE checkpoint images support the build stages; the lighting/composition checkpoint is 1280 pixels wide. No detailed exterior is required.

To rebuild from scratch, open the embedded or standalone `LoungeBuilder.py` in Blender’s Text Editor, set `RUN_BUILD=True`, `BAKE_TEXTURES=True`, and `EXPORT=True`, adjust `PARAMETERS` if needed, and Run Script. `RUN_BUILD=False` loads the helper functions without automatically rebuilding. `BAKE_TEXTURES=False` skips texture baking for geometry iteration, and `EXPORT=False` skips FBX writes.

For a checkpoint resume through Blender MCP, load the current script with `__name__` set to a non-main value so that it defines helpers without starting a full rebuild, then call `start_stage(N)` for the exact stage named in `PROGRESS.md`. Stages are: 1 blockout; 2 architecture; 3 furniture/props; 4 lighting/composition; 5 optimize/unwrap/bake/export; 6 final renders/documentation/validation. `start_stage` schedules one coherent stage on Blender’s main thread and writes recoverable errors and the next resume step into the progress log. Wait for that stage to finish before submitting another.

The builder is embedded in `Lounge.blend`; `PROGRESS.md` records the last successful action and exact resume step. `DECISIONS.md` records meaningful assumptions and deviations. Final validation is printed and saved to `Validation.md` and `Validation.json`, and the blend is saved after the final gate.

**Studio upload/import was not performed.** The FBX, texture, geometry, UV, clearance, and render validations are performed in the local Blender delivery workflow. The Roblox light/material/collision assignments above must be applied during Studio assembly.
