# BUILD THE SKYLINE CLUB: the game's hub map, via Blender MCP

You are building the one map of a Roblox 8-ball pool game in Blender 5.2 through the Blender
MCP, delivered as a Roblox-ready package. Work in stages. **Stop and wait for my review at the
two gates marked STOP**; everywhere else, decide for yourself, log real tradeoffs in
`assets/hub/DECISIONS.md`, and keep going.

This is a brand-new design built from the references below.

## Read first, in this order

1. `assets/hub/reference/ref_01` to `ref_07` (the look to match; details below).
2. `docs/MAP_RESEARCH.md`: why the map is shaped this way. The "Build for change" point is a
   hard requirement.
3. `assets/table/Readme.md` and `assets/table/Parameters.json`: the finished pool table and the
   package conventions (units, axes, naming, one material per mesh, baked maps, FBX settings,
   validation). The hub package must read as if the same author made it.
4. `assets/table/TableModel.blend`: APPEND the table (8 meshes, 8,134 triangles) and place 16
   collection instances for layout and renders only. Never rebuild, edit or export it.

## What it is

**Skyline Club**: a modern pool club on the top floor of a skyscraper. Windows on three sides
look out over a city skyline, and a rooftop terrace opens off the lounge. It is the place where
players play, watch, show off cues, trade and hang out. Follow the reference's layout and
materials, with the changes listed below.

### Keep from the references

- **ref_01, ref_07 (the hall):**
  - A long hall whose centre ceiling is a band of black linear slats, flanked by white
    ceiling bulkheads with recessed downlights and inset LED lines.
  - A warm yellow band high on the walls. In ref_07 it sweeps round a curved wall; keep that
    curve somewhere.
  - The **gray carpet-plank floor with light streaks**, laid in alternating directions (see
    Materials).
  - Tall columns clad in glossy black glass with gold edges.
  - Black-framed glass partitions, and white geometric lattice screens (ref_07) as
    see-through dividers.
  - Along the edges: slim velvet armchairs on thin gold legs, each pair with a small dark
    side table.
- **ref_01, ref_04, ref_05, ref_07 (pendants):** geometric pendants over every table, with
  glowing undersides. The shapes are long hexagon frames (ref_01), nested double squares
  (ref_04) and Y or three-arm stars (ref_05, ref_07). Use one shape per zone.
- **ref_02 (the entry and walkway):**
  - A glossy white marble floor meeting the carpet in a clean straight edge.
  - A glass wall separating the walkway from the hall.
  - A curved yellow feature wall.
  - A recessed tray ceiling outlined in LED over the walkway.
  - A **cue room behind a big glass window**, with cues racked on the wall inside. This
    becomes the cue showcase.
- **ref_03 (the lounge and bar):**
  - Polished marble floor.
  - Low sofas with plump cushions in a row along a wall with **diagonal LED lines** set into
    it.
  - **Capsule-shaped fluted glass screens with gold frames** as dividers.
  - A **white marble bar counter** with gold-legged stools.
  - A wavy LED ribbon light hanging above.
- **ref_05, ref_06:** three screens above the bar, a tall display case, and a giant
  billiard-ball wall mural with armchairs lined up beneath it. The bar screens become
  leaderboards; the mural becomes the big **featured-match screen**.
- **ref_04:** full-height windows, and a terrace outside with umbrellas and a railing.

### Changes from the references

1. **A taller room.** The main hall ceiling is 26 studs (tune). Clear height is at least 20
   over every table and at least 10 under anything people walk beneath. Roblox's camera
   zooms in when ceilings are low, so no low beams over walkways.
2. **No reception desk, no checkout computer, no cash register.** The bar stays (it serves
   drinks and snacks; no alcohol anywhere).
3. **Three zones: 1v1, 2v2, 3v3.** Each is its own area, separated by glass partitions and
   walkways. Zone identity comes from:
   - an accent colour: 1v1 amber `#FFB000`, 2v2 turquoise `#00C2A8`, 3v3 violet `#8A4DFF`;
   - the spectator armchairs, upholstered in the zone's colour;
   - a big overhead zone sign;
   - a carpet inlay stripe;
   - the pendant shape.

   **16 tables:** `ZONE_TABLES = {1v1: 10, 2v2: 4, 3v3: 2}` (a parameter, tune).
4. **A balcony along the south wall.** Players spawn up here, looking over the whole club. The
   way down is a wide stair with sittable stair seats beside it, facing the tables.
5. **The mirrored columns become brushed-gold and black metal.** Roblox reflects only the
   sky, never the room, so mirrors look broken.
6. **Far more saturated than the reference. This matters more than matching the photos.**
   The reference is dull and gray; our players are mostly kids and teens on phones, and
   saturated colour reads as happy and energetic. Keep the reference's layout and shapes,
   but recolour everything soft or decorative with bold, clean, candy-bright colour:
   - **the sofas are bright cobalt blue, not gray-blue or navy;**
   - every armchair, stool, cushion and sign is a strong saturated colour from the palette;
   - **no gray, beige or muted upholstery anywhere;**
   - walls stay light and clean so the colours pop. The carpet is the one gray surface,
     exactly like the reference, and its calm gray makes the coloured chairs pop even more.

   Check every render against the palette swatches: if a colour looks dusty, washed out or
   gray, push it back to the palette value. Saturation must survive the lighting and AO
   (bake AO lightly, and never let tinted light desaturate the furniture). The pool tables
   stay the focal point through the light pools over them, not by keeping the room dull.
7. **A piano spot (placeholder).** In the lounge, near the windows and visible from the main
   walkway, add a low round stage: about 14 studs across, 0.8 high, with a single step and a
   gold edge. On it goes `Placeholder_Piano`, a simple glossy-black grand piano silhouette
   (at most 2,000 triangles) with a bench, which will be swapped for a real playable piano
   later. Give it `Piano` and `Piano_Bench` anchors, a light marker above it, and a ring of
   standing room around it for people to gather.

## Style: stylized realism

Somewhere between low-poly cartoon and realistic, and never busy:

- **Simplified shapes:** drop about a third of real-world detail. Nothing thinner than 0.25
  studs, because it flickers on a phone.
- **Soft bevels on every exposed edge**, bigger than real life (0.1 to 0.3 studs), so edges
  catch light and read at phone size.
- **Clean, low-noise PBR:**
  - flat colour, gentle gradients and baked AO;
  - roughness does the material work;
  - no photo grime.

  The two hero floors below are the exception: they get real, detailed textures.
- **Linear slat ceiling as a texture, not geometry.** Use a few large dark ceiling panels with
  a baked slat texture (colour plus roughness), plus a handful of real beams. Hundreds of thin
  slats would shimmer on phones and waste triangles.

## Materials: the two hero floors and the shiny parts

Floors split by use: **carpet where people play, marble where people walk and hang out.**
The main walkway, the spawn landing, the balcony, the lounge, the bar and the piano stage are
marble. The three play zones are carpet.

**Marble (polished and reflective, like ref_02 and ref_03):**
- Large warm-white tiles, about 6 × 6 studs, with soft gray veining that varies tile to
  tile, and fine grout lines in the texture (not geometry).
- Its own texture set: colour, roughness (0.12 to 0.2, polished) and a subtle normal map.
- **How it looks reflective in Roblox.** Roblox has no real mirror reflections, so fake them
  in three layers:
  1. The low roughness gives sharp highlights from every Roblox light and from the sun.
  2. The surface picks up the skybox, which reads as the city reflected near the windows.
  3. Bake a soft, blurred reflection of the brightest things above the floor into its colour
     map at low strength: pendants, LED lines, windows and the bar. Use a Cycles glossy bake
     from a straight-down view, blurred.

  The result should look like a polished floor from any normal walking view.

**Gray carpet (high quality and textured, like ref_01, ref_04 and ref_07):**
- Carpet planks about 1.6 × 6.4 studs, laid in alternating directions (quarter-turned
  blocks), as in the references.
- Base gray `#5E636B` with fine light streaks `#B9BDC4` running along each plank, and each
  plank a slightly different shade.
- Its own texture set: colour, roughness (0.85 to 0.95, matte) and a **normal map with a
  visible loop-pile fibre texture and faint plank seams**. It should look like real
  commercial carpet up close and like calm, even gray from across the room.
- Author the textures at 4096 and upload at 1024. Tile the texture so it never shows an
  obvious repeat. The zone stripes are inlays in their zone colour, cut into the plank
  pattern.

**Other shiny parts:**
- The bar top and bar front: white marble, same set as the floor.
- Column cladding: glossy black (roughness about 0.1), which reads as black glass with
  sharp highlights, with bright gold edges.
- Gold trim and chair legs: metallic gold, roughness about 0.25.
- Screen faces: glossy black when off.
- Glass: windows, partitions, the cue-room window, and the fluted capsule screens (for the
  fluted ones, use a ribbed normal map on a single pane).

Palette. **Use these values; do not tone them down.** You may add in-between shades of the
same hues for variety, never grayer versions. About 60% light neutrals, 30% saturated
furniture, 10% zone accents and glow.

| Group | Colour | Hex | Where |
|---|---|---|---|
| Neutrals | Cloud white | `#EEF1F6` | walls, bulkheads |
| Neutrals | Soft sky | `#B9C7DC` | accent wall panels |
| Neutrals | Warm marble | `#F4F0E8` | walkway, lounge, bar, balcony and stage floors, bar top (gray veining) |
| Neutrals | Carpet gray | `#5E636B` | play-zone carpet, with `#B9BDC4` streaks |
| Neutrals | Sunny yellow | `#FFD23F` | the high wall band and the curved feature wall |
| Neutrals | Midnight navy | `#19213A` | slat ceiling, partition frames, glossy column cladding |
| Furniture | Cobalt blue | `#2563FF` | lounge sofas (velvet) |
| Furniture | Sunflower | `#FFC531` | cushions, ottomans |
| Furniture | Tangerine | `#FF7A1A` | cushions, poufs |
| Furniture | Coral red | `#FF4F5E` | bar stool seats, booth backs |
| Furniture | Glossy white | `#FFFFFF` | bar counter, screen frames |
| Furniture | Leaf green | `#2DBE4E` | plants |
| Zones | 1v1 amber | `#FFB000` | 1v1 armchairs, sign, carpet stripe, LED lines |
| Zones | 2v2 turquoise | `#00C2A8` | 2v2 armchairs, sign, carpet stripe, LED lines |
| Zones | 3v3 violet | `#8A4DFF` | 3v3 armchairs, sign, carpet stripe, LED lines |
| Metal and glow | Bright gold | `#F0B429` | trim, stool legs, column caps |
| Metal and glow | Warm LED | `#FFF3D6` | pendant undersides, ceiling LED lines |
| Tables | Blue cloth | `#01A9F7` | from the table package, not editable here |
| Tables | Green cloth | `#28AF2D` | from the table package, not editable here |

Table cloth colours come from the table package. Which zone uses the green look and which the
blue is still open, so make it a parameter (`ZONE_LOOK`) and default every zone to blue.

## Scale, layout and gameplay rules

- **Units:** 1 Blender unit = 1 stud. Author Z-up; export FBX the way the table package does.
  X runs east, Y runs north. The main floor is Z = 0.
- **Avatars:** 5 studs tall, 4 wide with arms out. Walk speed is 16 studs/s.
- **The table:** 18.24 × 10.24 studs with rails (9 ft Pro-Am at 0.16 stud per inch). The cloth
  is at 2.9. Either orientation is fine; the starting plan runs the long axis north-south.
- **Table clearance:** keep 10 studs clear around every table to anything standing on the
  floor: walls, furniture, partitions, steps, other tables. Corridors between tables may be
  shared.
- **Join pads:** each table has a 6 × 6 floor pad centred 14 studs from the table centre
  towards the head rail. It is flat and code-built, but leave the floor there clear.
- **Size:** the interior is at most about 170 × 150 studs. Every table, the bar and the
  terrace door are within an 8-second walk (128 studs) of the foot of the spawn stair.
- **Starting plan** (improve it if the audit passes):
  - **North, along the windows (about 67 deep):** from west to east, the 2v2 zone (2 across
    × 2 deep, about 51 wide), the 3v3 zone (2 tables side by side with 12 studs of clearance
    for six players, about 60 wide), then the lounge and bar with the terrace door.
  - **Main walkway:** runs east to west through the middle. Spawn, bar, featured screen and
    kiosks meet at one crossroads, the busiest spot on purpose.
  - **South (about 67 deep):** the 1v1 zone (5 across × 2 deep, about 114 wide) and, beside
    it, the spawn stair, the kiosks and the featured screen.
  - **Balcony:** along the south wall, floor at Z = 11.2 (fourteen 0.8-rise, 1.6-run steps),
    12 deep, with a solid-faced 3.5-stud railing. It must not overhang any table's clear
    height; seating goes underneath it.
  - **Terrace:** off the lounge through the east glass.
- **Seating goes at the edges.** Put armchairs, benches and booths along partitions, windows
  and under the balcony, 7 to 20 studs from a table so watchers can hear the players. Keep
  the middles open for walking. Leave no blank walls.
- **Pendants:** one per table, bottom edge 9.5 studs above the floor (tune; it must not block
  the overhead pool camera). No collision.

## Build for change (required)

The building never changes; what is on it does. Add named, empty anchor points (Blender
empties, exported to `Markers.json`) for:

- **Screens:**
  - `Screen_Featured`: the mural wall;
  - `Screen_Leader_1` to `Screen_Leader_3`: above the bar;
  - `Screen_Zone_*`: one per zone.

  Each is a separate flat quad mesh with clean 0 to 1 UVs, so Roblox can put a SurfaceGui on
  it. Record its facing direction.
- **Statues:** `Statue_1` to `Statue_3`, plinths for the weekly top-3 players.
- **Kiosks and fixtures:** `Showcase_Cue_*` (rack slots in the glass cue room),
  `Kiosk_Shop`, `Kiosk_Trade`, `Jukebox`, `Piano`, `Piano_Bench`.
- **Decor slots:** `Decor_Seasonal_*`, 10 to 15 spots for swappable holiday props.
- **Hidden spots:** `Secret_*`, 3 to 5 tucked-away nooks for hidden collectibles.
- **Spawn:** on the balcony.
- **Per table:** `Table_<n>` with its zone, position and yaw, and `Pad_<n>`.

## The skyline trick (few triangles, looks fully 3D)

Build the city in layers so it costs almost nothing in Roblox:

1. **Far layer: 0 triangles.** Build a detailed city in Blender (as heavy as you like), then
   render it into two Roblox skyboxes, `Day` and `Night`: 6 square 1024 faces each, from the
   room centre, with only the far city visible. Roblox Sky face orientation is easy to get
   wrong, so first render a labelled test cubemap (big arrows and face names) and document
   the correct mapping.
2. **Middle layer: about 3 to 5 large flat cards,** 400 to 800 studs out. They carry baked
   alpha-cutout skyline silhouettes (day and night variants). Their parallax against the
   skybox sells depth when players walk.
3. **Near layer: 20 to 40 low-poly towers,** 150 to 400 studs out, inside the view from the
   windows only:
   - 12 to 40 triangles each, with no backs, bottoms or hidden faces;
   - built from 3 or 4 master meshes reused many times;
   - sharing one facade trim-sheet texture with window grids;
   - with a night variant of that texture where the windows are lit.
4. **Haze deck:** a large gradient plane just below the window sills hides the street level
   and the tower bottoms. Leave distance haze to Roblox Atmosphere.

Skyline budget: 6,000 triangles and 4 texture sets at most, not counting the skyboxes. Render
views looking out of each window wall to prove it holds up.

## Mobile budget (low-end phones)

- **Triangles:** at most 200,000 for the environment, including the skyline and the piano
  placeholder. The 16 tables add about 130,000 on top. At most 10,000 per mesh. Spend the
  triangles where players look closely: soft, rounded sofas and chairs, bevels on edges near
  eye level, the pendants, the bar and the lounge. Not on the skyline, the ceiling or
  corners nobody sees.
- **Textures:** at most 12 sets at 1024. Each has colour and roughness; metalness only where
  there is metal. Normal maps go on the carpet, the marble and the fluted glass, and
  elsewhere only where they clearly help. Small props share 512 or 256 atlases.
- **Repeated props are exported ONCE.** Chairs, stools, sofas, pendants, plants, cue racks,
  plinths and towers each go into `Hub_PropLibrary.fbx` as a single master. Every placement
  goes into `Markers.json` and Roblox clones them. Identical meshes batch cheaply in Roblox.
- **Glass:** window panes and partitions only, never two panes stacked in one line of sight
  where you can avoid it. Everything else is opaque.
- **Glow:** meshes separate, untextured, named `Emissive_*` (they become Roblox Neon). This
  covers pendant undersides, LED lines and sign faces.
- **Collision:** simple hidden `COL_*` boxes and ramps. Stairs get a ramp proxy.

## Lights for Roblox (data, not baked)

Do not bake direct light into colour maps (AO only). In `Markers.json`, write every light the
game should create: position, direction, shape and size of the glowing face, colour
temperature, and a suggested Roblox light type with Brightness, Range and Angle. Table
pendants are a `SurfaceLight` facing down, sized to the pendant's glowing face. Keep the total
around 30 or fewer (16 table pendants plus a few ambient lights).

Also write a suggested Roblox Lighting recipe:

- LightingStyle Realistic, and it must still look right in Soft;
- Ambient and OutdoorAmbient;
- EnvironmentDiffuseScale and EnvironmentSpecularScale;
- Atmosphere;
- Bloom;
- ColorCorrection;
- day and night ClockTime.

The pools of light on the tables must read even with shadows off.

## Stages

Use one idempotent `assets/hub/HubBuilder.py` with a `PARAMETERS` block, run in a few large
stages through the MCP's `execute_blender_code`. It must also run headless:
`/Applications/Blender.app/Contents/MacOS/Blender -b`.

After every stage:
- save `assets/hub/Hub.blend`;
- update `assets/hub/PROGRESS.md`: done, remaining, last success, exact resume step;
- check the result with an MCP viewport screenshot.

1. **Blockout and audit.** Shell, windows, zones, balcony, stairs, walkways and the 16 table
   instances. Run a numeric clearance and walk-distance audit and write it to
   `assets/hub/layout_audit.md`. Render:
   - a labelled top-down plan;
   - the spawn view from the balcony;
   - an eye-level view in the 1v1 zone;
   - a view out of the north windows.

   **STOP. Show me the renders and wait for my review.**
2. **Architecture and materials:** ceiling panels, bulkheads, LED lines, partitions, columns,
   floors, windows, terrace.
3. **Furniture, props, anchors, pendants, emissives, signs** (zone signs as separate
   replaceable meshes with their own texture), the cue room, and the piano stage with its
   placeholder.
4. **Skyline** (skyboxes, cards, towers, haze deck), then the lighting preview in EEVEE. Render:
   - the spawn view;
   - the 1v1 view;
   - the lounge, bar and piano stage;
   - close-ups at avatar eye height of the marble floor (showing its reflections) and the
     carpet (showing fibre and planks);
   - a window view by day and by night;
   - one 390 × 844 phone-framed crop to check phone readability.

   **STOP. Show me the renders and wait for my review.**
5. **Optimise, unwrap, bake, export:**
   - FBX packages `Hub_Architecture`, `Hub_Furniture` (unique pieces only),
     `Hub_PropLibrary`, `Hub_Emissive`, `Hub_Glass`, `Hub_Skyline`, `Hub_Screens`,
     `Hub_Collision`;
   - `textures/`, `sky/Day_*.png` and `sky/Night_*.png`, and `Markers.json`;
   - validation of FBX round trip, triangle budgets, UV overlap, closed meshes, clearances and
     texture sizes into `Validation.json` and `Validation.md`. Do not relax a threshold to
     pass.
6. **Final renders and `assets/hub/Readme.md`:** Roblox import steps, SurfaceAppearance
   assignment, the Neon and Glass list, how the prop clones and lights are placed from
   `Markers.json`, the skybox setup, and the Lighting recipe.

If time runs short, cut decoration before architecture, budgets, exports or documentation. A
smaller finished package beats a bigger unfinished one.
