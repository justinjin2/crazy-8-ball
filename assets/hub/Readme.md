# Skyline Club (the hub map package)

This folder holds the game's one hub map: a pool club on the top floor of a skyscraper at
sunset. It was built headlessly in Blender from `HubBuilder.py`, following the brief in
`docs/prompts/HUB_BLENDER_PROMPT.md`. It uses the same conventions as `assets/table`.

The building never changes. Everything that should change later hangs off named anchors in
`Markers.json`: screens, statues, decor, seasonal props, secrets, lights and seats.

## Files

| File | What it is |
|---|---|
| `HubBuilder.py` | The builder. One idempotent script with a `PARAMETERS` block, run in stages. |
| `Hub.blend` | The scene: architecture, furniture, prop library and placements, skyline, lights, anchors. |
| `Hub_Architecture.fbx` | Floors, walls, windows, ceiling, balcony, stair, columns, frames, cue room, piano stage, terrace, marble reflection overlay. |
| `Hub_Furniture.fbx` | Unique pieces: bar, kiosks, booths, jukebox, lounge extras, sign frames, `Placeholder_Piano`, `Placeholder_Piano_Bench`. |
| `Hub_PropLibrary.fbx` | Every repeated prop once, at the origin: armchair, side table, sofa, bar stool, pouf, plant, cue rack, plinth, umbrella, the three pendants, four skyline towers. |
| `Hub_Emissive.fbx` | Glow meshes (`Emissive_*`), which become Neon. |
| `Hub_Glass.fbx` | Window panes, glass partitions, the cue-room window, the fluted capsule screens. |
| `Hub_Skyline.fbx` | The five silhouette cards and the haze deck. |
| `Hub_Screens.fbx` | Flat quads with 0 to 1 UVs: every `Screen_*`, `Sign_Zone_*` and `Sign_Logo_*`. |
| `Hub_Collision.fbx` | 78 hidden `COL_*` boxes and one stair ramp. |
| `Markers.json` | Every anchor, table, pad, screen, prop placement, seat, light, collision box, mesh setting, plus the skybox mapping and the Lighting recipe. Positions are in Roblox space. |
| `textures/*.png` | Upload maps, 1024 at most. The 4096 masters in `textures/masters/` are git-ignored and rebuilt from seeds. |
| `sky/{Dusk,Day,Night}_{Ft,Bk,Lf,Rt,Up,Dn}.png` | Three skyboxes, 1024 per face. `sky/test/` holds the labelled test faces. |
| `Textures.json` | Texture recipes and hashes. |
| `layout_audit.md` | Clearance, join pad, seating, height and walk-distance audit (PASS). |
| `Validation.json`, `Validation.md` | Package validation (PASS). |
| `renders/final_*.png` | The final dusk renders. `checkpoint_*` renders are git-ignored. |
| `DECISIONS.md`, `PROGRESS.md` | Choices made while building, and the stage log. |

## Rebuild

From the repo root, with `B=/Applications/Blender.app/Contents/MacOS/Blender`:

```bash
# everything, from an empty scene (about 3 minutes; the Cycles bakes take about 1)
$B -b --factory-startup --python-exit-code 1 --python assets/hub/HubBuilder.py -- \
   blockout architecture furnish skyline lighting bake export validate save
$B -b assets/hub/Hub.blend --factory-startup --python-exit-code 1 --python assets/hub/HubBuilder.py -- skyboxes final
```

Through the Blender MCP, run any list of stages with
`exec(compile(open(p).read(), p, 'exec'), {'__file__': p, '__name__': '__main__', 'HUB_ARGS': [...]})`.

| Stage | Does |
|---|---|
| `blockout` / `audit` / `render1` | Stage 1: the approved layout, the audit, the plan renders. |
| `architecture` | Stage 2: architecture, texture sets, collision. |
| `furnish` | Stage 3: prop library and placements, furniture, signs, screens, anchors, pendants. |
| `skyline`, `skyboxes`, `lighting`, `render` | Stage 4: towers, cards, haze deck, the far city, the three skyboxes, the preview lights, the review renders. |
| `bake`, `export`, `validate` | Stage 5: prop atlas and marble reflection bakes, the FBX packages, `Markers.json`, validation. |
| `final` | Stage 6: final dusk renders. |
| `skytest` | The labelled test cubemap. |

Change a number in `PARAMETERS` and rerun from the first stage it affects. `furnish` rebuilds
the prop masters, so run `bake` again after it.

## Units and frame

- 1 Blender unit is 1 stud. Blender uses X east, Y north, Z up, and the main floor is Z = 0.
- All packages share one origin: the room centre on the main floor.
- Roblox position = (x, z, -y) of the Blender position. Every position in `Markers.json`
  is already converted, and the Blender value is kept alongside as `*_blender`.
- `yaw_deg` is a turn about Roblox +Y, the same number as the Blender turn about +Z. Build
  a CFrame as `CFrame.new(position) * CFrame.Angles(0, math.rad(yaw_deg), 0)`.
- Facing names: Blender +Y (north) is Roblox -Z, Blender -Y is +Z, and ±X is unchanged.

## Import into Studio

1. Home, then **Import 3D**. Import each `Hub_*.fbx` with **Scale Unit: Stud**, scale 1,
   **Merge Meshes off** and **Import Materials/Textures off**, the same settings as the table.
   Keep each model's name (`Hub_Architecture` and so on). Put `Hub_PropLibrary` in
   **ServerStorage**, where the game clones from it. Put the others in **Workspace**.
2. Line the models up. The importer may leave them offset or turned half a turn, as it did
   with the table. Paste this into the command bar in Edit mode. It compares two meshes with
   their expected centres from `Markers.json` and moves every hub model the same way:

   ```lua
   local want = {Arch_Floor_Marble = Vector3.new(14.75, 5.6, 36.26), Emissive_ProDoor = Vector3.new(-85.325, 8.3, 4.82)}
   local a = workspace.Hub_Architecture:FindFirstChild("Arch_Floor_Marble", true).Position
   local b = workspace.Hub_Emissive:FindFirstChild("Emissive_ProDoor", true).Position
   local best
   for _, turn in ipairs({0, math.pi}) do
   	local r = CFrame.Angles(0, turn, 0)
   	local offset = want.Arch_Floor_Marble - r:PointToWorldSpace(a)
   	local err = (r:PointToWorldSpace(b) + offset - want.Emissive_ProDoor).Magnitude
   	if not best or err < best.err then best = {err = err, t = CFrame.new(offset) * r} end
   end
   for _, n in ipairs({"Hub_Architecture", "Hub_Furniture", "Hub_Emissive", "Hub_Glass", "Hub_Screens", "Hub_Skyline", "Hub_Collision"}) do
   	local m = workspace:FindFirstChild(n)
   	if m then m:PivotTo(best.t * m:GetPivot()) end
   end
   print("hub aligned, leftover error", best.err)
   ```

   The leftover error should be under 0.01. The pro-lobby door should now be at the west end
   (-X) of the main walkway, and the terrace on the east side (+X).
3. Set every imported MeshPart to **Anchored** and **CanCollide off**, except in
   `Hub_Collision`. Give those parts **Transparency 1**, **CanCollide on**,
   **CollisionFidelity Box** and **CastShadow off**. Instead of importing `Hub_Collision`, you
   can build plain Parts from `Markers.json.collision`. Each entry has a centre and a size in
   Roblox axes, and `COL_StairRamp` is a Wedge that rises towards `rises_towards`.
4. Save and publish.

## Textures and SurfaceAppearance

Upload the PNGs in `textures/` the same way as the table's, through the Studio MCP
`upload_image` from a local `python3 -m http.server`, four per batch. Then give each MeshPart
a SurfaceAppearance using the maps listed under its name in `Markers.json.meshes`.

| Set | Size | Maps | Meshes |
|---|---|---|---|
| Marble | 1024 (4096 master) | Color, Roughness, Normal | `Arch_Floor_Marble`, `Furn_Bar_Marble` |
| Carpet | 1024 (4096 master) | Color, Roughness, Normal | `Arch_Floor_Carpet` |
| Slats | 1024 | Color, Roughness | `Arch_Ceiling_Slats` |
| Palette | 512 | Color, Roughness, Metalness | every `Arch_*` palette mesh, `Furn_*` (not the bar marble), `Placeholder_Piano*` |
| Props | 1024 (baked, AO included) | Color, Roughness, Metalness | every `Prop_*` master |
| MarbleReflection | 1024 x 512 | Color (with alpha) | `Arch_Floor_Reflection`: **AlphaMode Transparency** |
| FlutedGlass | 512 | Color (with alpha), Normal | `Glass_Fluted`: **AlphaMode Transparency** |
| Facade_Day / Facade_Night | 1024 | Color, Roughness (+ EmissiveMask at night) | `Tower_A` to `Tower_D` |
| Cards_Day / Cards_Night | 1024 x 256 (4096 master) | Color (with alpha), Roughness (+ EmissiveMask at night) | `Sky_Card_1` to `5`: **AlphaMode Transparency** |
| Sign_Zone_1v1 / 2v2 / 3v3 | 512 x 256 | Color | `Sign_Zone_*` |
| Sign_Logo | 512 | Color | `Sign_Logo_*` (the blank placeholder; replace when the logo exists) |

The tinted meshes are `Prop_Armchair_Fabric` and `Prop_Pouf_Fabric`. Their colour maps are
near white. For each placement, set **SurfaceAppearance.Color** to the placement's `tint`
(zone amber, turquoise or violet, cobalt, coral and so on).

The haze deck (`Sky_HazeDeck`) gets no SurfaceAppearance. Its vertex colours are the
gradient, and they only show on a bare MeshPart. Set its Color per time of day
(`HazeDeckColor` in the recipe).

**Neon** (Material Neon, Color as listed, CastShadow off):
`Emissive_LED_Ceiling`, `Emissive_LED_Tray`, `Emissive_LED_Balcony`, `Emissive_LED_Bar`,
`Emissive_LED_Lounge`, `Emissive_Downlights`, `Emissive_StringLights` and the three
`Emissive_Pendant_*` (all warm LED `#FFF3D6`); `Emissive_ProDoor` (`#F0B429`);
`Emissive_Zone_1v1` / `Emissive_SignGlow_1v1` (`#FFB000`), `_2v2` (`#00C2A8`) and `_3v3`
(`#8A4DFF`); `Emissive_Kiosk_Shop` (`#FF7A1A`), `Emissive_Kiosk_Trade` (`#FF4F5E`) and
`Emissive_Jukebox` (`#FFC531`).

**Glass** (Material Glass, Color `#CFE8F2`, Transparency about 0.7, CastShadow off):
`Glass_Windows`, `Glass_Partitions`, `Glass_CueRoom`. `Glass_Fluted` uses its
SurfaceAppearance instead.

**Screens** (`Screen_*`) are glossy black SmoothPlastic when off. Each record in
`Markers.json.screens` gives the `surfacegui_face` to put a SurfaceGui on. The zone signs
and logo panels are listed under `signs`.

## Tables, props, seats and anchors (all from Markers.json)

- **Tables:** `tables` has all 16, each with a zone, position, yaw, head end and pad. Place
  the table template at `position`, turned `yaw_deg`. The 6 x 6 join pad sits at
  `pad_position` and is code-built.
- **Props:** `props.masters` lists each master's parts in `Hub_PropLibrary`, whether it is
  tinted, and its seat points. `props.placements` has 277 entries (prop, position, yaw,
  scale, tint). For each one, clone the master's parts into a Model with its pivot at the
  origin and call `PivotTo`. When `scale` is not 1 (the plinths of the top-3 podium and the
  towers), multiply each part's Size and its offset from the pivot by `scale`, in Roblox axes
  (x, z, y).
- **Pendants:** the placements named `Pendant_T<n>` hang over table n at 9.5 studs. Give them
  no collision. Hide them for the local player (LocalTransparencyModifier) while the overhead
  pool camera is up, so they never block the shot.
- **Seats:** `seats` lists 188 sittable spots, with position and facing. They come from
  armchairs, sofas, stools, poufs, stair seats and booths. Create a Seat part at each one.
- **Anchors:** `anchors` holds the named empties for things the game places or swaps later:
  `Spawn`, `Door_ProLobby`, `Statue_1` to `Statue_3`, `Kiosk_Shop`, `Kiosk_Trade`,
  `Jukebox`, `Piano`, `Piano_Bench`, `Showcase_Cue_1` to `13`, `Decor_Seasonal_1` to `13`,
  `Secret_1` to `5`, `Pad_1` to `16`, and the `Seat_*` stair and booth spots.

## Lights

`lights` lists 30 lights: 16 pendant SurfaceLights plus 14 ambient ones for the tray,
plaza, bar, lounge, piano spot, cue room, balcony, under-balcony, booths, terrace, pro door
and 3v3 window lounge.

Each entry has a position, direction, colour, colour temperature, Brightness, Range and
Angle. A SurfaceLight goes on a thin invisible part the size of `face_size`, facing
`direction` (Face Bottom for all of these).

Pendant lights have shadows off, so the pools of light on the tables read in the Soft style
and on low graphics settings too.

## Sky

Upload the six faces of each time of day and put them in a Sky. The orientation was tested
in Studio on 2026-09-25 with the labelled faces in `sky/test/`, and nothing is mirrored:

| Sky property | Seen when looking | File |
|---|---|---|
| SkyboxFt | towards -Z (north, over the 1v1 windows), upright | `sky/<Time>_Ft.png` |
| SkyboxBk | towards +Z (south), upright | `sky/<Time>_Bk.png` |
| SkyboxRt | towards -X (west), upright | `sky/<Time>_Rt.png` |
| SkyboxLf | towards +X (east, the terrace), upright | `sky/<Time>_Lf.png` |
| SkyboxUp | up; image top towards +X, image right towards -Z | `sky/<Time>_Up.png` |
| SkyboxDn | down; image top towards -X, image right towards -Z | `sky/<Time>_Dn.png` |

Dusk is the default. The sun sits low in the west, so set `CelestialBodiesShown` off:
the sun is painted into the sky. Swap to Day or Night by replacing the six ids.

The skyline has three layers:
- the **skybox**, the far city and mountains, which costs 0 triangles;
- five **cards** 470 to 640 studs out;
- 30 **towers** 210 to 400 studs out.

The **haze deck** at Z -40 hides the street level and the tower bottoms.

## Lighting recipe

Suggested values, also stored in `Markers.json.lighting`:

- LightingStyle **Realistic**, Technology **Future**. It also reads in **Soft**, because the
  table pools come from shadowless SurfaceLights.
- EnvironmentDiffuseScale 0.35, EnvironmentSpecularScale 0.6, GlobalShadows on,
  ShadowSoftness 0.25.
- Bloom: Intensity 0.55, Size 22, Threshold 1.6.
- ColorCorrection: Brightness 0.02, Contrast 0.06, Saturation 0.18, TintColor white.

| | Dusk (default) | Day | Night |
|---|---|---|---|
| ClockTime | 18.1 | 13.0 | 21.5 |
| Brightness | 1.6 | 2.4 | 0.6 |
| Ambient | `#5C6278` | `#707884` | `#3A4058` |
| OutdoorAmbient | `#8C7A8E` | `#9AA6B8` | `#2A3050` |
| ExposureCompensation | 0.1 | 0 | 0.15 |
| Atmosphere Density / Offset | 0.32 / 0.2 | 0.28 / 0.1 | 0.35 / 0.15 |
| Atmosphere Color / Decay | `#E7B39A` / `#6A5B8C` | `#C9DDF0` / `#8FA9C8` | `#2C3561` / `#161B38` |
| Atmosphere Glare / Haze | 0.35 / 1.6 | 0.1 / 1.2 | 0 / 1.8 |
| Sky | `Dusk_*` | `Day_*` | `Night_*` |
| Haze deck Color | `#E9A48A` | `#D6E6F3` | `#1E2750` |
| Towers | Facade_Night, EmissiveMask `Facade_Night_EmissiveDusk.png`, EmissiveStrength 1.5 | Facade_Day | Facade_Night, EmissiveMask `Facade_Night_Emissive.png`, EmissiveStrength 3 |
| Cards | Cards_Night, EmissiveMask, strength 0.6 | Cards_Day | Cards_Night, EmissiveMask, strength 2 |

## Budgets (from Validation.md)

| Item | Result |
|---|---|
| Environment triangles | 182,533 of 200,000: 15,265 in unique meshes plus 167,268 in prop placements. The 16 tables add 130,144. |
| Largest mesh | `Furn_Bar`, 3,992 triangles. None goes over 10,000. |
| Skyline | 738 of 6,000 triangles; towers are 12 to 32 triangles each. |
| `Placeholder_Piano` | 663 of 2,000 triangles |
| Texture sets at 1024 | 9 of 12, plus 6 small sets (512 or less) |
| Lights | 30 |
| FBX round trip | worst bounding-box error 7.6e-5 studs |
| Layout audit | pass; the longest required walk from the stair foot is 104.8 studs (6.5 s) |

## Known limits and things to check in Studio

- **Import alignment:** the half turn after import is handled by the alignment snippet
  above, but it has not been run yet. The first import should confirm the leftover error is
  near 0.
- **Glass and the camera:** the glass partitions are 9 studs tall. If the Roblox camera pops
  in when walls of glass pass behind the player, set those parts' `CanQuery` off.
- **Lighting preview:** the Blender preview renders use EEVEE ray-traced reflections. In
  Roblox, the marble's reflections come from its low roughness, the sky, and the
  `Arch_Floor_Reflection` overlay.
- **Placeholders:** the piano is `Placeholder_Piano` (swap for the playable one), the logo
  panels show a placeholder 8-ball, and the jukebox and kiosks are simple shapes.
