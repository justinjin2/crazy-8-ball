# Independent lounge layout audit

This is a numeric design recommendation, not a certification of the finished Blender scene. Final validation must run against the actual built object bounds.

## Inputs and conventions

Read the complete lounge `BUILD_CONTRACT.md` and the authoritative `../table/Readme.md`. The table source has native X length 17.76 and Y width 9.76 studs. Use a +90° native Z rotation per collection instance to present the short end toward the hero camera: the plan footprint is then 9.76 across X × 17.76 along Y. This maintains the reference's four-column rhythm while allowing generous cue space. Do not scale or rebuild the table source.

Coordinates below are Blender Z-up. Export mapping is `(x, y, z) → (x, z, −y)`, so native Z rotation +90° becomes Roblox Y rotation +90°. Camera faces native +Y / Roblox −Z.

## Recommended robust layout

- Room interior: X = −49..49, Y = −35..106 (98 × 141 studs).
- Column centers: X = −30, −10, 10, 30.
- Front, middle, rear row centers: Y = 0, 43, 86.
- Row floor heights: Z = 0, 2.4, 4.8.
- Table numbering: 1–4 at front, 5–8 at middle, 9–12 at rear; number left to right from the hero camera.
- Main ceiling: world Z=18. Rear ceiling may rise to Z=18.8 to retain 14 studs above the rear floor.
- Stair flight 1: Y = 19..23.8, rises 0.8, 1.6, 2.4, each tread 1.6 deep.
- Stair flight 2: Y = 62..66.8, rises from floor Z=2.4 to 3.2, 4.0, 4.8, each tread 1.6 deep.
- Broad stairs may span the room. Alternatively use ≥14-stud clear openings with solid 3.2-high railing panels at the terrace fronts.
- Front furniture, lounge rug border, and snack counter bodies must end at Y≤−19.25 if they overlap the four-column footprint in X.
- Side furniture/pillars/plants overlapping table rows must have their innermost physical silhouette at |X|≥45.2 (the strict minimum is 44.88). Include leaf spread, bevels, and railing caps in these bounds.

### Verified numeric margins for this proposal

| Constraint | Calculation | Clear space |
|---|---|---:|
| Neighboring tables across X | 20 − 9.76 | 10.24 |
| Front/middle table rear to next stair front | 19 − 8.88 | 10.12 |
| Middle/rear table front to previous stair rear | 43 − 8.88 − 23.8 | 10.32 |
| Outer table to side wall | 49 − 30 − 4.88 | 14.12 |
| Rear table to rear wall | 106 − 86 − 8.88 | 11.12 |
| Front table to foreground furniture ending Y=−19.25 | −8.88 − (−19.25) | 10.37 |
| Outer table to side silhouettes at |X|=45.2 | 45.2 − 34.88 | 10.32 |
| Neighboring rows table-to-table | 43 − 17.76 | 25.24 |

Because each stair flight is 4.8 studs deep and both neighboring rows require their own 10-stud clearance, a full-width stair arrangement mathematically requires row pitch ≥17.76 + 10 + 4.8 + 10 = 42.56 studs. The proposed 43 pitch leaves a small robust margin. The image's tightly packed depth cannot coexist with the numeric clearance contract.

The 10-stud corridor between adjacent tables is shared open floor. Requiring two exclusive ten-stud zones would imply twenty studs between tables, which is not stated in the contract and is unnecessary for the explicitly measured table-to-table gap. Document this shared-corridor interpretation.

## Composition guidance

Begin with camera `(0, −54, 16)` looking toward `(0, 45, 5.5)` and 20–22 mm lens. Adjust after an EEVEE preview. Keep X=0 and no camera roll for orderly symmetry. Foreground seating should occupy roughly X=−25..25 and Y=−32..−20, with tall sofa backs at the nearest edge. Place the snack counter in the front left, where its depth cannot invade table side clearances. Use windows along the right wall and a restrained timber ceiling grid.

The large room depth makes rear tables smaller in perspective. Raising the eye to near the main ceiling reveals their blue cloth above nearer rails; excessively raising it would produce a bird's-eye composition and require a ceiling cutaway. A slightly wider lens and a framing cutaway at the foreground shell are preferable to reducing gameplay clearances. Use bright table cloth and enlarged, separately editable table numbers to retain legibility at phone size. All twelve pendant bottoms must be floor Z + 7.5; each successive row therefore uses world Z=7.5, 9.9, 12.3.

## Recommended final validation logic

1. Derive each table footprint from its authoritative dimensions and actual instance transform. Do not include lights, source marker empties, or render-only source floor in those bounds.
2. Test all table pairs by plan AABB separation, with a minimum Euclidean footprint distance of 10.0. Also report their facing X/Y corridor gaps.
3. Test walls and every furniture, pillar, plant, step, railing, counter, and sign support that intrudes into the floor-to-avatar-height zone. Table-mounted number plaques may remain within the authoritative footprint. Ceiling beams and pendants entirely above the walk/cue zone do not obstruct horizontal floor clearance; document that scope explicitly.
4. For tiered floors, treat the stair flight and exposed terrace edge as obstacles. A supporting floor slab beneath the table is not a clearance obstacle.
5. Using rectangles inflated by ten studs is a conservative test for diagonal obstacles. Exclude only explicit supporting floor/rug surfaces and overhead fixtures, not arbitrary decorations.
6. Validate railings at ≥3.2 studs relative to their local floor, stair openings at ≥14 clear studs after caps/posts, and each rise/run from actual geometry.
7. Preserve numeric slack. Do not use an error tolerance to excuse a modeled clearance under ten studs.

The source table is 19,220 triangles. Twelve render instances represent 230,640 table triangles, intentionally excluded from the ≤150,000-triangle lounge environment budget. They must also be absent from all six lounge FBX exports.
