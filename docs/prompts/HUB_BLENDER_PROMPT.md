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
4. `assets/table/TableModel.blend`: APPEND the table (8 meshes, 8,134 triangles) and place 12
   collection instances for layout and renders only. Never rebuild, edit or export it.

## What it is

**Skyline Club**: a modern pool club on the top floor of a skyscraper. Windows on three sides
look out over a city skyline, and a rooftop terrace opens off the lounge. It is the place where
players play, watch, show off cues, trade and hang out. Follow the reference's layout and
materials, with the changes listed below.

### Keep from the references

- **ref_01, ref_07:** the long hall. Black linear-slat ceiling, white ceiling bulkheads with
  inset LED lines, a warm yellow accent band high on the walls, cool gray walls, charcoal
  carpet with light streaks, black-framed glass partitions, and slim spectator armchairs with
  small side tables.
- **ref_04, ref_05, ref_07:** geometric pendants over every table: nested squares, hexagon
  rings and Y shapes, with glowing undersides. Use a different pendant shape per zone.
- **ref_02, ref_03:** the lounge. Light marble-look floor, low sofas with amber cushions, a
  white bar counter with gold-legged stools, vertical LED wall lines, and a fluted glass
  screen.
- **ref_05, ref_06:** three wall screens above the bar and a display cabinet. The screens
  become leaderboards and the cabinet becomes the cue showcase.
- **ref_06:** the giant billiard-ball mural wall. It becomes the big **featured-match
  screen**.
- **ref_04:** the terrace with umbrellas and a railing, seen through the glass.

### Changes from the references

1. **A taller room.** The main hall ceiling is 26 studs (tune). Clear height is at least 20
   over every table and at least 10 under anything people walk beneath. Roblox's camera
   zooms in when ceilings are low, so no low beams over walkways.
2. **No reception desk, no checkout computer, no cash register.** The bar stays (it serves
   drinks and snacks; no alcohol anywhere).
3. **Three zones: 1v1, 2v2, 3v3.** Each is its own area, separated by glass partitions and
   walkways. Zone identity comes from:
   - an accent colour: 1v1 amber `#F2B84B`, 2v2 teal `#2FA7A0`, 3v3 violet `#7B5CE0`;
   - a big overhead zone sign;
   - a carpet inlay stripe;
   - the pendant shape.

   Table split is a parameter: `ZONE_TABLES = {1v1: 6, 2v2: 4, 3v3: 2}` (tune).
4. **A balcony along the south wall.** Players spawn up here, looking over the whole club. The
   way down is a wide stair with sittable stair seats beside it, facing the tables.
5. **The mirrored columns become brushed-gold and black metal.** Roblox reflects only the
   sky, never the room, so mirrors look broken.
6. **Brighter and more colourful than the reference.** The photos are too gray for a young
   audience:
   - lift the wall grays lighter;
   - push the accents about 15% more saturated;
   - warm the light slightly.

   The tables must stay the brightest, highest-contrast thing in every view.

## Style: stylized realism

Somewhere between low-poly cartoon and realistic, and never busy:

- **Simplified shapes:** drop about a third of real-world detail. Nothing thinner than 0.25
  studs, because it flickers on a phone.
- **Soft bevels on every exposed edge**, bigger than real life (0.1 to 0.3 studs), so edges
  catch light and read at phone size.
- **Clean, low-noise PBR:**
  - flat colour, gentle gradients and baked AO;
  - roughness does the material work;
  - no photo grime;
  - large, low-contrast patterns (the carpet streaks stay subtle).
- **Linear slat ceiling as a texture, not geometry.** Use a few large dark ceiling panels with
  a baked slat texture (colour plus roughness), plus a handful of real beams. Hundreds of thin
  slats would shimmer on phones and waste triangles.
- **Glossy floors are faked.** Use roughness around 0.35 to 0.45, plus soft light streaks
  baked into the colour map under lamps and bright windows. Roblox has no real floor
  reflections.

Palette (starting point; you may adjust for harmony, and log it):

| Colour | Hex | Where |
|---|---|---|
| Light gray | `#C9CED3` | walls |
| Cool gray | `#8C949C` | accent walls |
| White | `#F4F5F6` | bulkheads, bar |
| Near-black | `#1E2124` | ceiling |
| Charcoal gray | `#5B6168` | carpet, with `#9AA1A8` streaks |
| Marble white | `#E6E4E0` | lounge floor |
| Teal | `#2E8F8C` | upholstery |
| Amber | `#E8A13A` | cushions |
| Brushed gold | `#C9A45C` | trim, stool legs |

Table cloth colours come from the table package. Which zone uses the green look and which the
blue is still open, so make it a parameter (`ZONE_LOOK`) and default every zone to blue.

## Scale, layout and gameplay rules

- **Units:** 1 Blender unit = 1 stud. Author Z-up; export FBX the way the table package does.
  X runs east, Y runs north. The main floor is Z = 0.
- **Avatars:** 5 studs tall, 4 wide with arms out. Walk speed is 16 studs/s.
- **The table:** 18.24 × 10.24 studs with rails (9 ft Pro-Am at 0.16 stud per inch). The cloth
  is at 2.9. Place the long axis along X.
- **Table clearance:** keep 10 studs clear around every table to anything standing on the
  floor: walls, furniture, partitions, steps, other tables. Corridors between tables may be
  shared.
- **Join pads:** each table has a 6 × 6 floor pad centred 14 studs from the table centre
  towards the head rail. It is flat and code-built, but leave the floor there clear.
- **Size:** the interior is at most about 150 × 125 studs. From the spawn, every zone, the
  bar and the terrace door are within a 10-second walk.
- **Starting plan** (improve it if the audit passes):
  - **North, along the windows:** the 2v2 zone (2 × 2 tables) and the 3v3 zone (2 tables in
    one row, with extra room for six players).
  - **Main walkway:** runs east to west through the middle. Spawn, bar, featured screen and
    kiosks meet at one crossroads, the busiest spot on purpose.
  - **South:** the 1v1 zone (3 × 2 tables) and the lounge.
  - **Balcony:** along the south wall, floor at Z = 11.2 (fourteen 0.8-rise, 1.6-run steps),
    12 deep, with a solid-faced 3.5-stud railing.
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
- **Kiosks and fixtures:** `Showcase_Cue_*` (cabinet slots), `Kiosk_Shop`, `Kiosk_Trade`,
  `Jukebox`.
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

- **Triangles:** at most 120,000 for the environment, including the skyline. The 12 tables add
  about 98,000 on top. At most 10,000 per mesh.
- **Textures:** at most 10 sets at 1024 (colour and roughness; metalness only where there is
  metal; normal maps only where they clearly help). Small props share 512 or 256 atlases.
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
around 25 or fewer.

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

1. **Blockout and audit.** Shell, windows, zones, balcony, stairs, walkways and the 12 table
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
   replaceable meshes with their own texture).
4. **Skyline** (skyboxes, cards, towers, haze deck), then the lighting preview in EEVEE. Render:
   - the spawn view;
   - the 1v1 view;
   - the lounge and bar;
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
