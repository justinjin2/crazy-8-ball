# BUILD THE "8BALL" POOL LOUNGE: Roblox-ready environment via Blender MCP

You are working unattended for ~60 minutes with a hard usage cap. Never ask me questions. Make every decision yourself, log it in `DECISIONS.md`, and keep going. Finish with a complete, importable package even if you have to cut scope: a smaller finished package beats a bigger unfinished one.

## What you are making

A bright, warm, upscale pool lounge for a Roblox 8-ball game, built in Blender 5.2 through the Blender MCP, delivered as Roblox-ready FBX meshes with baked PBR textures, exactly like the pool table package that already exists in this repo. The lounge is the real game map for testing and release. It must look stunning in the render AND run well on low-end phones in Roblox.

Attached: a reference image of the lounge (the look, layout and mood to match) and a colour palette screenshot. Take creative liberties where they make it look better; the reference is a target, not a cage.

## Inputs already on disk (read these first, in this order)

1. `assets/table/Readme.md` — delivery conventions of the existing table package. Follow every convention in it: units, axes, naming, one material per mesh, baked maps, validation. The lounge package must read as if the same author made it.
2. `assets/table/PoolTable.py` — the table build script. REUSE its unwrap, bake and FBX export helpers instead of writing new ones. Copy the functions you need into your lounge script.
3. `assets/table/PoolTable_9ft.blend` — the finished 9 ft table. APPEND it as a collection and place collection instances for every table in the layout. Tables are for layout, scale and the render only. DO NOT re-export the table meshes; the table is already in Roblox.

## Scale rules (the single most important section)

- 1 Blender unit = 1 Roblox stud. 0.16 stud per inch. Z-up in Blender; FBX exports -Z forward / Y up, same settings as the table.
- The table footprint is 17.76 × 9.76 studs, cloth top at Z=2.9, rail top at Z=3.23. Everything else is sized to sit next to that and next to a Roblox avatar, which is 5 studs tall and 4 studs wide with arms out. Build to avatar scale, not real-world scale.
- Cue length is 9.3 studs. Keep a clear 10-stud gap around every table on all sides: to walls, to other tables, to furniture, to railings, to steps.
- Reference dimensions in studs: main ceiling 18 (mezzanine ceiling may be 14), doors 8 tall × 5 wide, windows sill at 2 and head at 15, mezzanine floor raised 2.4 (three steps of 0.8 rise, 1.6 run, step width at least 14 so avatars pass side by side), railings 3.2 tall with a solid or dense-baluster face so avatars cannot walk through, sofa seat 1.7 / back 3.4 / depth 3.4, coffee table 1.5 tall, bar counter 3.2 tall, pendant lamps hanging with their bottom edge at Z=7.5 over table centres, framed art centred at Z=8, wall clock at Z=11.
- Layout: keep the reference arrangement of tables (front row of four, a raised row behind, a mezzanine row at the back). Tables are placeholders that I will move later in Roblox, so also write their transforms to a markers file (see Deliverables). Zone signs ("1v1", "2v2", "3v3") are placeholders too: keep them as separate sign meshes with their own texture so I can swap the text later.

## Look and colour

Bright, warm, airy, welcoming. Golden-hour sunset light through big windows, warm pendants over each table, cream walls, honey wood, teal upholstery, pool-blue felt, coral and butter accents, charcoal table cabinets. Stylized clean-modern, not photoreal, not kid-cartoony. Clean readable shapes, soft bevels, no noise or grunge.

Palette (starting point, adjust for harmony and contrast):
- Cream #FFF1DC walls, rug base
- Honey oak #D9AE7B floors, beams, furniture wood
- Fresh teal #37B7B2 sofas, sign accents, pillars
- Pool blue #23B6DE felt (the table already has its own felt; use this for rugs, carpet zones)
- Soft coral #FF917F pillows, art, rug shapes
- Butter #F4D56B ottoman, small accents, sign backgrounds
- Charcoal #29383E table cabinets, lamp housings, cue racks

Apply the 60/30/10 rule: roughly 60% cream and honey wood, 30% teal and pool blue, 10% coral and butter. Keep large surfaces low-saturation and reserve the saturated colours for small accents so the pool tables stay the focal point. Check contrast: every prop must read against its background at phone size.

## Roblox and mobile constraints (hard limits)

- Every mesh ≤ 10,000 triangles. Whole environment (excluding tables) ≤ 150,000 triangles. Report a per-object triangle table.
- Every mesh: one material, one non-overlapping UV map, no n-gons, no live modifiers, transforms applied, origin at a sensible pivot (architecture at world origin, furniture at its own base centre), triangulated on export.
- Textures: 1024 × 1024 max (Roblox downsamples anything larger). At most 12 texture SETS for the whole lounge. Use atlases: group many small objects onto one 1024 sheet (e.g. `Furniture_A`, `Props_A`, `Signs`). Per set: BaseColor (sRGB) and Roughness required; Normal only where surface detail matters (wood floor, plaster, fabric); Metalness only if the set contains metal, otherwise omit it. Bake AO at 128 samples and MULTIPLY it into BaseColor (Roblox has no AO slot). Do not bake direct lighting or shadows into colour; Roblox lighting will add those.
- Glowing things (lamp bulbs, sign letters that should glow, strip lights) are SEPARATE untextured meshes named `Emissive_*` with a flat colour material; I will set them to Roblox Neon.
- Window glass is a separate untextured mesh `Glass_Windows`; I will use Roblox Glass. Do not model the outside world; Roblox skybox handles it. If time remains at the very end, add a ring of low-poly trees `Outside_Trees` outside the windows for parallax.
- Collision: architecture pieces should be simple enough for Roblox "Box" or "Hull" collision. For anything a player walks on that is not a box (stairs, mezzanine edge, curved counter), export a matching low-poly collision mesh named `COL_<name>` (under 200 triangles each).
- Split the export into logical FBX files so a Roblox import is manageable: `Lounge_Architecture.fbx` (floor, walls, ceiling, beams, steps, mezzanine, railings, pillars, window frames, glass), `Lounge_Furniture.fbx` (sofas, chairs, ottoman, coffee table, rug, bar counter, cabinets, piano), `Lounge_Props.fbx` (plants, art frames, clock, cue racks, pendant lamps, vending machine, small items), `Lounge_Signs.fbx` (zone signs, "Refresh & Play", one blank logo sign 10 × 3 studs on the main wall for a future game logo), `Lounge_Emissive.fbx`, `Lounge_Collision.fbx`. Same origin for all files so they line up on import.
- No real-world brands or logos anywhere. No "Diamond" text on anything.

## Working method (this is how you stay inside the usage cap)

- SCRIPT FIRST. Write ONE rebuildable script `assets/lounge/LoungeBuilder.py` in the style of `PoolTable.py`, with a PARAMETERS block, `RUN_BUILD`, `BAKE_TEXTURES` and `EXPORT` flags. Run it through the MCP `execute_blender_code` tool in large chunks. Do not build the room by hand with dozens of tiny MCP calls.
- Check progress with low-cost viewport screenshots (EEVEE, ~800 px). Use Cycles only for the bakes and the final hero render.
- Use the Blender MCP PolyHaven integration freely (already enabled) for base textures at 1k: wood floor, plaster, fabric, and a sunset HDRI for the render. Use Hyper3D or Sketchfab only for a prop that would take you more than a few minutes procedurally (the piano is a candidate). Everything else is procedural geometry with simple bevels.
- Save the .blend and update `assets/lounge/PROGRESS.md` (what is done, what is next, how to resume) at the end of EVERY stage. If I run out of usage mid-way, the next session must be able to resume from that file without re-reading this prompt.
- Time-box the stages below. If a stage overruns, cut scope from the "last" items, log it, and move on. Baking is last because it is slowest.

## Stages (checkpoint after each)

1. **Blockout (10 min).** Room shell, steps, mezzanine, railings, windows, table instances placed with the 10-stud clearances, camera set to the reference angle. Screenshot. Save.
2. **Architecture detail and materials (12 min).** Wood floor with subtle plank pattern, cream plaster walls, ceiling beams with recessed warm downlights, teal pillars, window frames, cue racks on the walls. Assign source materials. Screenshot. Save.
3. **Furniture and props (15 min).** In priority order: lounge sofas + rug + coffee table + ottoman, plants, framed art + clock, pendant lamps over every table, zone signs, snack bar "Refresh & Play" counter. Last, only if on time: vending machine, piano, outside trees. Screenshot. Save.
4. **Lighting for the render (5 min).** Sunset HDRI through the windows, warm 3000K pendant emitters over tables, soft warm ambient fill, exposure so the felt and cream walls are bright but not blown out. One EEVEE test render at 1280 px. Save.
5. **Optimize, UV, bake, export (15 min).** Merge small props into atlases, check triangle budgets, unwrap, bake at 1024 using the table package's helper, multiply AO into BaseColor, export the FBX files, reimport one FBX to verify coordinates match to 1e-6 studs. Save.
6. **Render and docs (3 min).** Final Cycles hero render 1920 × 1080 at 128 samples with denoise from the reference angle, plus one wide top-down layout render. Write the Readme.

## Deliverables (all under `assets/lounge/`)

- `Lounge.blend`, `LoungeBuilder.py`, `PROGRESS.md`, `DECISIONS.md`
- The six FBX files listed above
- `textures/` with `<Set>_Color.png`, `<Set>_Roughness.png`, and `_Normal` / `_Metalness` where used
- `renders/hero.png`, `renders/layout_top.png`
- `Markers.json` in exported Roblox coordinates (studs, Y up): every table centre position + Y rotation in degrees, every pendant lamp position + colour temperature + suggested Roblox brightness/range, the spawn point (in the lounge seating area, facing the tables), and a suggested Roblox `Lighting` recipe (ClockTime, Brightness, Ambient, OutdoorAmbient, ColorShift_Top, EnvironmentDiffuseScale, EnvironmentSpecularScale, and Bloom / ColorCorrection values) that reproduces the render's warmth.
- `Readme.md` in the same format as the table Readme: conventions, per-object triangle table, texture sets, import steps for Roblox Studio (Scale Unit: Stud, scale factor 1), which meshes get Neon / Glass / collision meshes, validation results.

## Final validation (print the results, fix failures before you stop)

Per mesh: triangle count under limit, single material, UV bounds within 0-1 and no interior overlap, manifold or intentionally open (state which), no n-gons, no modifiers, transforms applied. Total environment triangles under 150,000. Texture sets ≤ 12, all ≤ 1024. All emissive, glass and COL_ meshes present and correctly named. FBX reimport coordinate check passes. Every table instance has ≥ 10 studs of clearance in all directions (compute it, do not eyeball it). Both renders exist.
