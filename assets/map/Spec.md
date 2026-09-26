# Rooftop map: spec

The measured facts every stage builds to. The brief is `docs/prompts/ROOFTOP_MAP_PROMPT.md`;
the art is `assets/map/reference/`.

- **Positions** come from `map_layout.py` (written to `Layout.json`, drawn as `Plan.png`).
- **Colours** come from `measure_palette.py` (written to `Palette.json`).

Change those scripts, never the numbers here by hand, then update this file.

## 0. Designer decisions (2026-09-26, Stage 0 interview)

- **Side seating follows 02.**
  - City side: planters, palms and lanterns only.
  - Ocean side: umbrella sets with loungers, plus sofa groups along the railing.
- **The entrance stair** walks down to a small dead-end landing, closed off by the railing and
  an invisible wall.
- **Table looks follow the table's mode**, with wood frames (the regular lobby): green 1v1,
  raspberry 2v2 (`RedWood`), charcoal 3v3 (`CharcoalWood`). This replaces the brief's "all
  green". Ten 1v1 tables sit at the front, four 2v2 and two 3v3 toward the back, as on the
  baseplate.
- **Queue pads sit in front of each table:** centred on the long side that faces the
  entrance. The pad's shape (a circle now) may change, so the grid is computed from the pad
  numbers in Config and re-spaces itself when they change.
- **Prop scale is split.**
  - Spacing and zones follow the table's scale (the art's layout).
  - Anything a player sits on, climbs or leans on is at player scale.
  - Big decor (planters, palms, umbrellas, the pergola) is about 1.4x player scale, so it
    holds its own beside the 18-stud tables.
- **The snack counter is the art's lit back bar**, centred along the back of the lounge
  under the pergola.
- Banners and the pink light pillar (the day panel's pergola ends, 02) are out, with the
  infinity-pool strip.

## 1. Scale and axes

- **Studs, Roblox world axes:**
  - X points right as seen from the entrance: the city is -X, the ocean +X.
  - Y points up; the rooftop floor is Y = 0.
  - Z points toward the entrance; the lounge is -Z.
  - Yaw is degrees about +Y (`CFrame.Angles(0, yaw, 0)`).
- **Two scale bars that disagree** (census, `checkpoints/census.md`):
  - The art draws a real-proportioned 9 ft table. Ours is 18.24 x 10.24 studs over the
    rails, but its cloth is only 2.9 studs up. So in plan it is 2.25x a real table, and in
    height only 1.3x.
  - A player is 5 studs, so 1.75 m = 5 studs: **1 m = 2.86 studs** (the P bar).
  - The table bar (T): 1 table length = 18.24 studs.
- **Which bar sizes what** (designer's split):
  - Layout, spacing and zone depths use T.
  - Seats, steps, railings and lanterns use P.
  - Planters, palms, umbrellas and the pergola use about 1.4 x P.

## 2. Palette

Every colour here comes from `Palette.json`, which `measure_palette.py` measures from the art:
k-means in CIELAB, and for small painted leaves and flowers the "vivid" rule (the most
saturated 15% of pixels). The art paints warm light onto every lit face and cool lavender into
every shadow. So:

- a material's colour (the albedo) is its **daylight** reading where the art has one (02, the
  day panel), not a lamp-lit one;
- the painter's cool shade (`floor_shade` #5D719E, `planter_shade` #797496) is the tint the
  baked ambient occlusion darkens toward, so props read like the art without Roblox GI;
- the sunset readings are targets for the lit result under the Sunset lighting (Stage 7), not
  albedos.

`map_common.py` holds this table; nothing else names a colour.

### Rooftop

| Material | Hex | Source region | Note |
|---|---|---|---|
| Floor tile | #F1CDBD | `floor_panel_day` | light warm tile; 02's #F1BFB8 is pinked by the table glow |
| Grout | the floor 8 L* darker | (rule) | the art's grout lines are 1-2 px, too thin to measure; low contrast by the brief |
| Cream stone: steps, parapet, planter boxes | #DECFD0 | `step` | shade #A08885 |
| Cream columns and beams (pergola, entrance) | #DEBAA8 | `column` | shade #A68E95 |
| Pergola slats (wood) | #725233 | `pergola_slat` | 03 and key-assets |
| Railing frame | #0D0D12 | `railing_frame` | near black |
| Railing glass | #66B4D2 | `railing_glass` | a faint cyan tint at high transparency |
| LED strip, lit trims | #FEE2B2 | `led_strip` | |
| Under-table glow | #EF9054 | `under_table_glow` | shade #C06D4A |
| AO and shadow tint | #5D719E | `floor_shade` | |

### Props

| Material | Hex | Source region | Note |
|---|---|---|---|
| Couch fabric (warm grey) | #F3D8C3 | `couch_day` | shade #AE8480 |
| Cushion blue | #184F73 | `cushion_blue` | |
| Cushion light (the brief's "teal") | #999E9C | `cushion_teal` | the art's light cushion is blue-grey |
| Cushion orange | #EC8C31 | `cushion_orange` | |
| Cushion white | #E2D1D0 | `cushion_white` | 02 ocean sofas |
| Coffee table top | #985D46 | `coffee_table` | apron and legs #372625 |
| Fire pit stone | #5D3E37 | `firepit_stone` | cap #E5AD96 |
| Fire pit glass ring | #5A93AE | `firepit_ring` | |
| Flame | #F6AA3F | `fire` | shade #A65015 |
| Lantern frame | #47322B | `lantern_frame` | |
| Lantern glass, day | #FDF5AB | `lantern_glass` | sunset #FAF4CF |
| Globe light | #FAE091 | `globe_light` | |
| Umbrella canvas | #FCF7E6 | `umbrella_canvas_day` | |
| Umbrella pole | #704433 | `umbrella_pole` | |
| Lounger | #4E4442 | `lounger` | |
| Grand piano | #0E0C0D | `piano_black` | |
| Leaves, lit / mid / deep | #91961E / #6A7409 / #2B4405 | `leaf_lit`, `leaf_mid`, `leaf_dark` | the foliage atlas's three stops |
| Palm fronds, lit / mid | #828913 / #6A770C | `palm_lit`, `palm_mid` | |
| Palm trunk | #6C4B44 | `palm_trunk` | shade #362019 |
| Bougainvillea | #BD1976 | `flower_vivid` | |

The art's greens are a warm yellow-green (Lab hue about 100 to 110). If the critic reads them
as muddy under Roblox's white sun, the fix is to turn the hue toward 120 at the same lightness
and chroma. That is a Checkpoint B adjustment, recorded here if it is made.

### Backdrop, day

| Material | Hex | Source region |
|---|---|---|
| Sky, top / horizon | #3894FC / #86C4FB | `sky_top_day`, `sky_horizon_day` |
| Cloud, lit / underside | #E4E8FC / #BAD1FC | `cloud_day` |
| Water, shallows / deep | #34A8CA / #3187DE | `water_near`, `water_far` |
| Sand | #F5DEC1 | `sand` |
| Island green, near / far | #61866F / #477F8C | `island_green`, `island_far` |
| Island rock | #827790 | `island_rock` |
| Far mountains | #3E93ED | `mountain_far` |
| City glass / facade / far city | #1D5EBB / #C2B2AA / #4875C7 | `city_glass_day`, `city_facade_day`, `city_far_day` |

The backdrop is hazier and less saturated than the rooftop (brief section 4). Atmosphere does
most of that; the far colours above already carry the painter's haze.

### Sunset (targets for the lit result)

| Region | Hex |
|---|---|
| Sky, top / mid / horizon | #7B60BB / #D96094 / #FD7E62 |
| Cloud | #F56077 (shade #CD4D8B) |
| Sun | #FCF480 |
| Sea, in the sun's path / elsewhere | #E87177 / #74519F |
| City glass / lit windows | #3E4C93 / #D5B59C |
| Island silhouettes | #564175 |
| Rooftop floor under sunset light | #EAA1A5 |
| Lantern glass | #FAF4CF |

## 3. The plan

![plan](Plan.png)

`Plan.png` beside the art's top-down panel: `checkpoints/plan-vs-art.jpg`.

### Table field

| Item | Value |
|---|---|
| Tables | 16 at yaw 0, long sides to the entrance. Ids 1 to 4 are the front row, left to right; 13 to 16 are the back row |
| Modes (front row to back) | 1v1 x4; 1v1 x4; 1v1, 2v2, 2v2, 1v1; 2v2, 3v3, 3v3, 2v2 |
| Looks | 1v1 Green, 2v2 RedWood, 3v3 CharcoalWood |
| Queue pads | centred in front of each table (+Z); radius 3.5 / 4.25 / 5 by mode (Config, may change) |
| Match fence | 26 across (X); from 8.5 behind the table centre to 10 + 2 x radius in front (27, 28.5 and 30 deep) |
| Pitch | 36 across, 36.5 deep (every row leaves room for the biggest pad) |
| Table centres | X = -54, -18, 18, 54; Z = 54.75, 18.25, -18.25, -54.75 |
| Field (fence outline) | X -67 to 67, Z -63.25 to 71.75 (134 x 135) |
| Aisles between fences | 10 between columns; 11, 9.5 and 8 between rows (front to back) |

The art spaces its rows about 22 to 24 studs apart. Ours are 36.5 apart, because each match
area holds the shooter's walkway on both long sides plus the pad in front. So the field is
about as deep as it is wide; the art's is wider than deep. The columns match the art: 36
against the art's 34.

### The terrace

| Zone | X | Z | Y |
|---|---|---|---|
| Terrace (railing inner face) | -93 to 93 (186) | -107.25 to 91.75 (199) | 0 |
| Front walkway | -77 to 77 | 71.75 to 81.75 | 0 |
| Entrance landing (spawn at X 0, Z 86.25, facing -Z) | full width | 81.75 to 91.75 | 0 |
| Entrance stair: 10 steps, 0.5 up, 1.6 deep | -13 to 13 | 91.75 to 107.75 | 0 down to -5 |
| Lower landing (dead end) | -13 to 13 | 107.75 to 115.75 | -5 |
| Side walkways | 67 to 77 each side | -63.25 to 71.75 | 0 |
| City side zone / ocean side zone | -93 to -77 / 77 to 93 | -107.25 to 81.75 | 0 |
| Back walkway | -77 to 77 | -71.25 to -63.25 | 0 |
| Lounge central flight: 4 steps, 0.5 up, 2 deep | -14 to 14 | -79.25 to -71.25 | 0 up to 2 |
| Lounge platform (the rest of its front edge is a 2-stud riser) | -56 to 56 | -107.25 to -79.25 | 2 |
| Pergola: 5 bays of 19.2, 15 clear | -48 to 48 | -104.25 to -82.25 | 2 |

- **The edge all round** is a low parapet (1.2 high, 1.2 thick) with a dark-framed glass
  railing to 3.6 above the floor, and an invisible wall above it to 40.
- **The back corners** beside the platform (X 56 to 93) stay at floor level.

### Walkways

- **Width:** every walkway is at least 8 studs.
  - The front walkway and the side walkways are 10.
  - The back walkway is 8.
  - The aisles between columns are 10, and between rows 8 to 11.
- **Nothing solid** stands in any walkway, the lounge flight or the entrance stair, except
  the crossing planters.
- **A crossing planter** keeps at least 8 studs of open floor to anything solid (table barriers
  and props). A match fence is open floor for everyone who is not playing that match.
- `map_layout.py` checks all of this and exits 1 on any problem.

### Props

Positions are in `Layout.json`. Counts follow the art (census): 6 crossing planters as in the
top-down, and one big item per table row along each railing.

| Prop | Count | Where |
|---|---:|---|
| Fern planter | 12 | 6 at the aisle crossings (none in the middle row gap); 2 on the city railing; 4 on the lounge edge beside the flight |
| Palm planter | 12 | 2 on the city railing; 2 on the ocean railing; 2 beside the stair; 2 in the front corners; 2 in the back corners; 2 at the platform's front corners |
| Lantern | 12 | 5 per side at the row gaps and the front and back walkways; 2 flanking the lounge flight |
| Tall lantern | 2 | flanking the stair head |
| Umbrella set (canopy and two loungers) | 3 | ocean side at rows 1 and 3; the ocean back corner |
| Sofa group (sofa, ottoman) | 3 | ocean side at rows 2 and 4; the city back corner |
| U sectional | 2 | under the pergola: city side round a coffee table, ocean side round the fire pit |
| Coffee table | 1 | inside the city U |
| Fire pit | 1 | inside the ocean U |
| Grand piano and bench | 1 | the ocean end of the pergola (02) |
| Snack counter (back bar) | 1 | centred along the back of the pergola; `SnackCounterServe` attachment on its front |
| Globe light | 10 | one per bay on the pergola's front and middle beams |
| Cream column | 2 + 12 | 2 framing the entrance; 12 pergola columns (two rows of six) |
| Under-table glow | 16 | a flat plane under each table |

## 4. Prop sizes

Width x depth x height in studs. "P" is player scale (1 m = 2.86 studs); decor is about 1.4 x P.

| Prop | Size | Detail |
|---|---|---|
| Fern planter | 3.2 x 3.2 x 7 | box 3.0 high (P 2.1 x 1.4); ferns to 7 |
| Palm planter | 4.8 x 4.8 box, 3.2 high | palm to about 26, crown about 18 across |
| Lantern | 1.5 x 1.5 x 4.0 | P 1.0 m lantern x 1.4 |
| Tall lantern | 2.2 x 2.2 x 6.5 | |
| Umbrella set | 12 canopy, rim at 9, top at 12 | two loungers 5.6 x 2.0, seat 1.0, back to 2.6 (P) |
| Sofa group | 12 x 6 footprint | sofa 11 x 3, seat 1.3, back 2.6 (P); ottoman 2.9 square, 1.1 high |
| U sectional | 20 x 9 x 2.6 | seat 1.3, back 2.3 to 2.6 (P); cushions on the back |
| Coffee table | 2.8 round x 1.3 | P |
| Fire pit | 4.5 round x 1.4 | flame about 1.4 above the rim |
| Grand piano | 4.4 x 5.8 x 3.0 | P (2.0 x 1.5 m, 1.0 m tall); bench 2.4 x 1.0 x 1.4 |
| Snack counter | 24 x 5 | counter 3.2 high (P 1.1 m), lit shelves behind to 8 |
| Globe light | 1.5 round | hangs 3 below the beams |
| Pergola | 96 x 22, 15 clear | columns 2.6 square, cream; slatted wood roof with vines and a few bougainvillea |
| Entrance column | 2.8 square x 16 | cream |
| Railing | 3.6 high overall | parapet 1.2; posts about every 4 |
| Steps | riser 0.5 | tread 1.6 (entrance), 2.0 (lounge) |

Every seat is a `Seat` part (GDD section 10): sofas, U sectionals, loungers and the piano
bench.

## 5. Camera poses

One pose per reference view, for the captures in every stage's verification. The capture is
cropped to the reference's aspect. These are first guesses from the art; Stage 1 tunes them
against the gray-box. `map_layout.cameras` holds them:

| View | Reference | Position | Looks at | FOV |
|---|---|---|---|---:|
| entrance | `panels/entrance.jpg` | (0, 6, 92.75) | (0, 3.5, 0) | 70 |
| day-view | `02-day-view.jpg` | (16, 26, 89.75) | (-6, 0, -53.6) | 62 |
| high three-quarter (day, sunset) | `panels/day.jpg`, `panels/sunset.jpg` | (0, 125, 216.75) | (0, 0, -20) | 55 |
| top-down | `panels/top-down.jpg` | (0, 600, -7.75), straight down, -Z up | | 30 |
| lounge-back | `panels/lounge-back.jpg` | (0, 8.5, -77.25) | (0, 4, -167.25) | 70 |
| city-side | `panels/city-side.jpg` | (-90, 26, 0) | (-600, -140, 0) | 45 |
| ocean-side | `panels/ocean-side.jpg` | (90, 26, -20) | (700, -120, -160) | 45 |
| phone eye | (none; 750 x 361) | (0, 5.5, 86.25) | (0, 4, 0) | 70 |

## 6. The sun

**The problem:**

- Roblox's sun rises toward +X and sets toward -X, whatever the latitude. This was measured
  in Studio on 2026-09-26 with `Lighting:GetSunDirection()`.
- Our ocean is +X, so an evening sun would set over the city.
- The only real sun low over the ocean is a dawn one.

**The plan:**

- The Sunset state uses a dawn `ClockTime`, and the latitude swings the sun round to the art's
  spot.
- The sun is never faked or painted.

| State | GeographicLatitude | ClockTime | Sun direction | Azimuth (0 = toward the lounge, 90 = toward the ocean) | Elevation |
|---|---:|---:|---|---:|---:|
| Day | 45 | 10.0 | (0.465, 0.806, 0.367) | 128 (right, toward the entrance side) | 54 |
| Sunset | -30 | 6.4 | (0.591, 0.062, -0.804) | 36 (right and ahead, over the sea) | 3.6 |

- **From the entrance, looking at the lounge,** the sunset sun sits 36 degrees right of
  straight ahead and just above the horizon. That is the same spot as in `panels/sunset.jpg`:
  0.8 of the way across the frame, just over the island.
- **The Day sun** is high and front-right, so the side the player sees is lit.
- **The cycle blends both numbers,** so during a fade the sun slides down (or up) the right
  side of the sky, never across it.
- **`Sky.SkyboxOrientation`** turns the painted sunset glow to sit behind the sun (Stage 7).
- **The sea is behind the lounge (-Z) and to the right (+X),** so the sun always sets over
  water.

## 7. The world round the rooftop

- **The tower:**
  - Its footprint is the terrace, plus the stair bay.
  - Its walls drop about 300 studs to the street (about 30 floors). Street level is Y = -300
    and sea level Y = -302.
  - `FallenPartsDestroyHeight` goes below the street (the place has -500).
- **The coast** makes an L round the tower:
  - Land (the city) is to the left and front-left; water is to the right and behind.
  - The beach promenade, sand and palms run along the tower's ocean side and round behind it.
  - Beyond the beach come turquoise shallows, then deep blue sea.
- **Near (Stage 4, within about 400 studs):** the tower's walls, neighbour roofs below ours,
  streets, the promenade, the beach, sailboats.
- **Mid (Stage 5, 400 to 2000 studs):**
  - The skyline, with a few towers taller than ours as in the art.
  - The islands: steep green cones with beaches and rocks, one beside the sunset sun.
- **Far (Stage 6, 2000 studs and beyond):** skyline and island silhouettes on cards, faded by
  Atmosphere.

## 8. Budgets

`Budget.md` holds the brief's caps and the running count.
