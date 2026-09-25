# Brief: the Pro-Am pool table model (headless Blender)

This is the standing brief for building and rebuilding `assets/table/`. Read the whole brief
before writing code. The decisions behind it are in `docs/DECISIONS.md` (2026-09-24), GDD
section 16 and `docs/STUDIO_NOTES.md` ("SurfaceAppearance facts").

## What you are making

One pool table model for a Roblox game, styled on the Diamond Pro-Am 9 ft. It carries no brand
name, logo, or "Diamond"/"Pro-Am" text anywhere. It is one mesh set that every look shares (blue
cloth with satin black wood, green cloth with red-brown wood, and future skins); a look only
changes textures. **The cushions and pockets must match the game's physics exactly.**
- The physics comes from `assets/table/Geometry.json`, which `tools/export_table_geometry.luau`
  generates.
- Never invent or re-derive physics numbers. Read them.
- A drawn surface the ball touches must lie within 0.01 in of the physics surface.

Pro-Am features:
- **Rails:** 7 in wide, rounded (bullnose) outer edge, mitred corners, seams behind the side
  pockets, 18 flush pearl diamond sights.
- **Skirt and cabinet:** a tall wooden skirt over a black cabinet, with tapered corner blocks.
- **Legs:** two-piece tapered legs, with a seam a third of the way down and two chrome bolt
  heads per outer face.
- **Pockets:** black leather rims flush with the rail, with chrome caps over them (a separate,
  removable mesh; the corners must look finished without it).
- **Foot end:** a blank logo plate.
- **Left out:** no ball-return window, no drop baskets.

Scale:
- 1 Blender unit = 1 Roblox stud = 6.25 in (0.16 stud per inch).
- The playing area is 16 x 8 studs.
- The cloth top is 2.9 studs (18.125 in) above the floor. This is fixed, so the table sits
  lower than a real one: fit the skirt, cabinet and legs into 18 in.

## Hard rules

- **Headless only:**
  `/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 --python assets/table/TableModel.py`
  - Build geometry with bmesh and data calls only.
  - Never use `bpy.context.window`, `bpy.context.screen`, edit-mode operators, boolean or bevel
    modifiers, or `smart_project`.
  - The only operators allowed are FBX export and import, render and save.
- **Use `assets/table/TableModel.py` as the template** (it was built from the rake's
  `Bridge.py`, removed 2026-09-25): a commented `PARAMETERS` dict,
  `clear_scene`, `finish`, `validate`, `export_fbx`, `reimport_check`, `write_parameters`,
  `clean()` rounding, embedding the script in the .blend, deleting any `.blend1`, and printing
  progress lines (`TABLE ...` / `TABLE OK`) with exit code 1 on any failed check.
- **Reuse** only the pure helpers from `assets/table/legacy/PoolTable.py`: `_linear`, `_color`,
  `_geometry_signature`, `_save_progress`. Nothing else from it is headless-safe.
- **Deterministic:** the same inputs give byte-identical outputs. Seed any randomness and iterate
  in fixed orders.
- **Meshes:** one material and one UV map (named `UVMap`) per mesh. Triangles only. Every mesh
  origin is at (0,0,0), the table centre on the floor. Transforms are applied. No parent
  empties are exported.
- **FBX export** (the table's proven settings): `axis_forward='-Z', axis_up='Y',
  global_scale=1.0, apply_unit_scale=False, apply_scale_options='FBX_SCALE_UNITS',
  bake_space_transform=True, use_triangles=True, mesh_smooth_type='OFF',
  path_mode='RELATIVE', embed_textures=False, colors_type='NONE', object_types={'MESH'}`.
  Vertex colours are not used: Roblox ignores them under a SurfaceAppearance.
- **Scope:** do not touch `src/`, `tests/`, `docs/` (except this brief if told to), or the
  legacy folder. Do not commit.

## Frames

- **Geometry.json:** inches, physics frame. x runs along the length (head rail -x, foot rail +x),
  y across (the top rail with pockets 1 to 3 is +y), and the cloth is at z = 0. Its `frame`,
  `units` and `legend` strings are the authority. Read them.
- **Blender native:** (x·s, y·s, z·s + h), with s = 0.16 and h = 2.9. The floor is at Z = 0.
- **Roblox local after the importer:** (x·s, z·s + h, −y·s). The foot (+x) is where the rack,
  the foot spot and the logo plate are.

## Geometry.json keys you use

- `studs_per_inch`
- `cloth` {half_length 50, half_width 25, above_floor 18.125, bed_thickness}
- `ball` {radius 1.125, render_radius 1.215}
- `cushion` {nose_height 1.42875, width 1.8}
- `rail` {width 7, top 2.08, outer_half_length 57, outer_half_width 32, barrier_half_extents_studs}
- `pockets`:
  - {casting_top, casting_reach 4, casting_blend 1, min_depth 6.5, drop_depth 5, jaw_radius 0.3}
  - corner {mouth 4.5, radius 2.25, shelf 1.5, facing_degrees 38, facing_length ~2.615}
  - side {mouth 4.95, radius 2.475, inset 2.475, facing_degrees 13, facing_length 1.6}
- `pockets.fade_depth` and `pockets.fade_drift`: how far the fading drawn ball keeps falling
  after the physics drop. The cup does not have to hold it; its floor is near-black.
- `holes[6]` {id, name, kind, x, y, radius, clear_radius, facings[2], jaws[2]}: turning
  counterclockwise from jaws[1] to jaws[2] crosses the mouth
- `segments[18]` {name, kind rail|facing, a, b, normal, pocket?}: a is the nose end, b the jaw
  end; normal is the inward unit normal, pointing onto the cloth
- `points[24]` {name, kind nose|jaw, x, y, radius, facing, pocket}
- `cushions[6]` {rail, facings[2], pockets[2]}: the nose outline order is in `legend.cushions`.
  Use these relationships. Never infer them from names; the rail segment called "topLeft" is
  not hole "topLeft".
- `spots` {head, foot, break_line_x}
- `rack` {apex, balls[15]}

Assert the schema version and the consistency: every cushion chain closes, and corner jaw
points lie on their hole rims. Store the file's sha256 in Parameters.json.

## How the physics works (what the drawing must honour)

- **2D contacts:** a ball touches a segment when its centre is `ball.radius` from the line. It
  touches a point when its centre is `ball.radius + point.radius` from it.
  - Nose points have radius 0: a sharp corner where the rail line meets the facing.
  - Jaw points have radius 0.3: a round rubber knob centred on the end of each facing. It bulges
    0.3 in out from the facing plane into the throat.
  - Draw the knob exactly. Blend it into the facing with a concave fillet no bigger than the
    ball radius; the ball can never touch that fillet.
- **Dropping:** a ball is captured when its centre crosses its hole's circle (`holes[i].radius`).
  It tips over the lip, then falls, and its **surface** rides a liner at that radius. The drawn
  ball is 1.08x, so draw the cup wall at `clear_radius` (radius + 0.09) plus 0.01. The drop
  stops 5 in down (drawn ball bottom). Cups must be at least `min_depth`; build 7 in with a
  near-black floor.
- **Nose height:** the cushion nose line is at `cushion.nose_height` above the cloth.

## Meshes (exact names), contents and triangle budgets

The total must be at most 13,000 (warn above 11,500), and each mesh under 20,000.

| Mesh | Contents | Budget |
|---|---|---|
| `Cloth` | Bed top (cloth), 6 cushions (tops, noses, facings, knobs, fillets), the cloth rolls into the holes | 3,400 |
| `Rails` | 6 rail cap pieces (flat band, bullnose, outer face) with mitres and side seams; 18 flush pearl sights as faces of the rail top | 2,500 |
| `Body` | Skirt (4 sides), black cabinet, 4 corner blocks, 4 two-piece legs, 4 rubber levellers | 2,000 |
| `Pockets` | 6 leather rims flush with the rail top, leather walls behind the jaws, 6 cups | 1,900 |
| `Caps` | 6 chrome caps over the rims, closed shells with a finished underside; removable | 1,600 |
| `Hardware` | Chrome bolt heads: 2 per outer leg face on the upper leg block | 700 |
| `LogoPlate` | One blank plate on the foot skirt, centred, about 9 x 3 in; the orientation marker (centroid x > 0) | 64 |
| `Marks` | Transparent overlay quads 0.004 studs above the cloth: foot-spot sticker, rack patch, break streak, chalk near each pocket, darkening strips along the cushion toes, darkening rings round the rims | 400 |

Segment counts come from chord tolerance: 0.005 in on physics-critical curves (knobs, hole
rims), 0.02 in elsewhere. Use equal-error tessellation, with vertices at r(1+sec(phi/2))/2 on
arcs the ball touches.

## Construction

**Cushions (in Cloth)**
- **Nose outline per cushion:** follow the physics segments exactly, through the sharp mitre at
  each Nose point, the facing, the concave fillet (default 0.5 in, never more than the ball
  radius), the knob (radius `jaw_radius` about the Jaw point), then a heel line back to the
  cushion's back line. The back line is `cushion.width` behind the nose line.
- **Profile** (outward distance from the nose line, height above the cloth):
  - toe (0.30, -0.01), seated just into the cloth
  - nose (0, nose_height), exact
  - rounding levels ±0.1 in around the nose
  - the top rising to (width, rail.top - 0.02)
  - Loft every level with the same vertex count. The knob radius at a level is
    `max(jaw_radius - setback, 0.02)`, centred on the offset facing.
- **UVs:** u is arc length along the nose outline, v is arc length along the profile. Both are
  in studs divided by **1.5** (the cloth tile repeats every 1.5 studs). Continuous UVs that
  exceed 0..1 are fine (tested: Roblox repeats them). Keep the same texel density as the bed.

**Bed (in Cloth)**
- The top at cloth height covers the play rectangle, extended 0.15 in under the cushion toes.
  Pocket openings are removed.
- At each hole the flat cloth ends at `radius + 0.07`. A quarter-round roll (rho 0.07 in) turns
  vertical exactly at `radius`, then the bore continues 0.25 in down and tucks behind the cup.
- Rolls exist only on the arc between the jaw knobs. Behind the jaws the leather wall takes over.
- **UVs:** planar, u = x_studs / 1.5 and v = y_studs / 1.5, continuous with the cushions where
  they meet.
- There is no hidden underside and no stepped band. Nobody sees below the cloth except inside
  the pockets.

**Rails**
- **Plan:** each of the 6 pieces spans from the cushion back (`cushion.width` behind the nose)
  to the outer edge (`rail.width` behind the nose). Mitres run at 45° from each corner pocket
  cut to the outer corner. Long rails are split at x = 0 behind each side pocket, with a
  0.03 in chamfer at the piece ends so the seam reads as a hairline. The pocket cut arcs clear
  the leather rim.
- **Profile** (distance from the nose, height above the cloth):
  - flat band at `rail.top` from the cushion back to about 5.2 in;
  - a quarter-ellipse bullnose about 1.8 in wide and 1.0 in tall down to the outer face;
  - the outer face vertical down to the skirt top.
  - The crown (highest point) is exactly `rail.top`.
- **Sights:** 18 diamonds, flush, as their own faces in the flat band. They sit 3.6875 in from
  the nose to the diamond centre. Long rails have 3 per half, at x = ±12.5, ±25, ±37.5 in; end
  rails have y = 0 and ±12.5 in (WPA spacing 12.5 in). Each is about 1.0 x 0.44 in, with the
  long axis across the rail.
- **UVs:** the Rails trim sheet, 1024 px at about 400 px per stud. U runs along each piece
  (the grain direction) with a different U offset per piece. V runs across the profile, in
  strips: top band + bullnose + outer face; seam/end region; pearl patch (sights); hidden faces.
  Write the strip rectangles (in UV) to Parameters.json `uv_layout.Rails`.

**Body**
- **Skirt:** 4 wooden panels under the rail, from 1.0 in below the cloth down `skirt_height`
  (default 6.5 in). About 0.9 in thick, flush with the rail's outer face or 0.1 in inset,
  small rounded lips.
- **Cabinet:** black, inset 1.0 in, visible 2.5 in below the skirt, with a closed bottom.
- **Corner blocks:** at each corner, from the skirt top to the cabinet bottom, slightly proud of
  the skirt (0.15 in), tapering from about 6.5 in wide at the top to 5.5 in, with thin chamfered
  edges.
- **Legs:** below each corner block, down to the floor.
  - Tapered square with chamfered corners, 5.0 in at the top to 3.75 in at the floor.
  - A 0.06 in seam groove a third of the way down marks the two pieces.
  - A black rubber leveller 0.4 in tall at the foot.
  - The legs meet the floor exactly (min Z = 0).
- **UVs:** the Body trim sheet, 1024 px at about 200 px per stud. Strips: skirt (grain
  horizontal along each side), corner block (grain vertical), leg faces (grain vertical),
  cabinet black, leveller rubber, hidden. Write them to `uv_layout.Body`.

**Pockets, Caps, Hardware**
- **Leather rim:** a 0.08 in roll from the pocket opening onto the rail top, flush, about 0.35 in
  wide.
- **Leather wall:** covers the far arc between the cushion heels, flaring from `clear_radius`
  at cloth level to the rail cut at the rail top.
- **Cups:** single-sided with inward normals, 32 segments, 7 in deep, at radius
  `clear_radius + 0.01`, with a flat floor. They must never poke through the skirt or cabinet:
  keep at least 0.25 in clearance, and clamp to the skirt's inner face where needed. The old
  model's side cups poked out.
- **Caps:** one chrome cap per pocket following the rim (about 270° on the corners, 180° on the
  sides), over the leather rim and a little of the wood.
  - Closed profile: crown about 0.2 in above `rail.top`, a rounded outer edge, and an inner lip
    whose underside is modelled.
  - **Cue clearance limit:** at plan distance d (inches) from the hole centre, the top may not
    exceed `rail.top + (casting_top_target - rail.top) * clamp((casting_reach - d) / casting_blend, 0, 1)`.
    So the cap's full height stays within 3 in of the hole centre and slopes to rail height
    by 4 in. Use casting_top_target = rail.top + 0.2 (2.28 in) unless told otherwise. The cue
    clearance tests fail above 2.351 in, so never exceed that.
  - Report the measured crown as `PocketCastingTopInches`.
  - The bottom of each cap is 0.003 in above the rail/leather surface.
- **Hardware:** chrome bolt heads, 0.35 in across and 0.08 in proud, with a slight dome. Two per
  outer face of each upper leg block.
- **UVs:** the Parts atlas, 1024, shared by Pockets, Caps and Hardware. Regions: leather; cup
  (v runs with depth so the texture can darken downward); chrome top; chrome underside;
  leveller rubber if needed. Write them to `uv_layout.Parts`.

**LogoPlate:** a thin plate (0.06 in proud) centred on the foot skirt, with its own UV 0..1
over the front face (the back maps to one corner). It is blank for now; a future logo is a
texture swap.

**Marks:** quads 0.004 studs above the cloth, never over a hole opening. UVs point into regions
of the Marks atlas (1024 RGBA): sticker, rack patch, break streak, 4 chalk variants, a toe
darkening strip, a rim darkening ring. Write them to `uv_layout.Marks`.
- **Foot-spot sticker:** about 1 in across, at `spots.foot`.
- **Rack patch:** a soft triangle under `rack.balls`.
- **Break streak:** along y = 0 from `spots.head` to the rack.
- **Chalk:** 6 smudges near the pocket mouths.
- **Toe strips:** about 1.5 in wide, along every cushion toe.
- **Rim rings:** from `radius + 0.07` out 1 in.

## Validation (every failure exits 1; record every result in Parameters.json)

1. **Topology:** triangles only; no zero-area faces (under 1e-8 square studs); no loose
   vertices. Closed shells (caps, bolts, rail pieces, legs, blocks, plate) are manifold with
   positive volume. Open sheets (bed, cups, walls, marks) may only have their expected boundary
   edges.
2. **Budgets:** per mesh and in total (see the table).
3. **Physics match (0.01 in):**
   - (a) Slice the cushions at nose height and check that every sampled ball centre on the
     physics offset boundary is exactly R from the drawn slice.
   - (b) Free centres (at least R from physics, within 4 in of any cushion or pocket) are at
     least R - 0.01 from the drawn slice.
   - (c) No rubber sits in front of the nose line at any height.
   - (d) 3D sphere clearance: from free centres at z = R, and from falling centres (within
     `radius - R` of a hole, z from R down to -5 in), the drawn ball (render radius) never
     intersects any geometry except the cloth plane it rests on and the liner it rides. Use a
     BVH.
   - (e) A circle fitted to the roll where it turns vertical has its centre and radius within
     0.01 in of the physics hole.
   - (f) Downward rays on a 0.1 in grid hit the cloth plane at the right height everywhere
     outside the rims, and never hit flat cloth inside `radius - 0.01`.
   - (g) The sights are at the stated positions within 0.01 in.
4. **Clearances:** cups at least 0.25 in inside the skirt and cabinet; cups at least `min_depth`
   deep; everything inside `rail.outer_half_*` and inside the barrier.
5. **No see-through gaps:** rays from above and at 30° from 8 directions hit a front face.
   Run it twice, with and without Caps.
6. **UVs:**
   - Cloth density is 683 px/stud at 1024 (±10%; knobs and fillets ±35%).
   - Rails about 400 px/stud (±15%); Body about 200 px/stud (±15%); Parts at least 250;
     LogoPlate aspect within 2%.
   - Wood grain alignment |cos| is at least 0.98 along each piece.
   - No mirrored faces (every tangent bitangent sign is +1).
7. **FBX round trip:** re-import into a clean scene, with bounds within 1e-5 per mesh and names
   exact.
8. **Orientation:** the LogoPlate centroid is at x > 0.

## Parameters.json (tests/table_model_test.luau reads it)

- `geometry_source` {file, sha256, schema}
- `frame` (text)
- `roblox_local`:
  - `Table` {StudsPerInch, SurfaceHeightStuds, RailWidthInches, RailTopInches,
    PocketCastingTopInches (measured cap crown), MinPocketDepthInches}
  - `TableModel` {Name "PoolTable", MeshNames [sorted], MeshSizes {name: [x,y,z] studs,
    Roblox axes}, MeshCentres {name: [x,y,z]}}
- `measured` (inches, physics frame):
  - `cushion_nose_height`, `rail_top`, `rail_outer_half_extents` [2], `bounds_half_extents_studs` [2]
  - `segments` [{name, a, b, max_deviation}]
  - `points` [{name, x, y, radius}]
  - `holes` [{id, x, y, rim_min, rim_max, clear_min, depth}]
  - `casting_profile` {corner: [[d, z_max]...], side: [...]}: the highest point of Caps plus
    Pockets per 0.5 in band of plan distance from the hole centre
  - `logo_plate_x`, `spot_sticker` [2], `break_line_x`
  - `max_deviation` {nose_line, ball_envelope, sphere_clearance, hole_rim, sight}
- `triangle_counts` {mesh: n}, `triangle_budget`
- `uv_layout` {Cloth: {studs_per_repeat 1.5}, Rails: {...strips}, Body: {...}, Parts: {...},
  LogoPlate, Marks: {...regions}}
- `uv_stats`, `validation`, `parameters` (every PARAMETERS entry)

## Renders for the designer (TableRender.py, clay/ID materials, Cycles on Metal with a CPU fallback)

Make `renders/checkpoint_shape.png`, a 3x3 sheet of 960x540 frames:
1. Hero 3/4 view from the foot corner.
2. Top-down orthographic with the physics drawn in thin red at nose height.
3. Corner pocket with caps.
4. The same corner without caps.
5. Side pocket.
6. The close aim view: camera 2.24 studs from a ball at 30°, FOV 60.
7. Leg, bolts and corner block.
8. Foot end with the logo plate.
9. Player-eye view: standing 3 studs from the long rail, eye height 4.5 studs.

Render-only objects never go into the FBX. `renders/checkpoint_*.png` is git-ignored.

## Outputs in assets/table/

`table_common.py`, `TableModel.py`, `TableRender.py`, `PoolTable.fbx`, `TableModel.blend`
(script embedded, no .blend1) and `Parameters.json`. Textures come later from
`TableTextures.py`, which reads `uv_layout`.
