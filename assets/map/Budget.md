# Map budget

The running count for the hub map. Triangles are counted twice: in Blender (evaluated meshes,
after modifiers) before export, and in Studio after import (EditableMesh, STUDIO_NOTES). The
caps are the brief's (`docs/prompts/ROOFTOP_MAP_PROMPT.md` section 6). The whole game stays under
1,000,000 triangles with players in it.

## Triangles by group

| Group | Cap | Blender | Studio | Stage |
|---|---:|---:|---:|---|
| 16 tables (existing, 8,134 each) | 130,000 | 130,144 | 130,144 | existing |
| Balls, cues, effects (existing) | 20,000 | | | existing |
| Rooftop architecture: floor, parapet, railing, steps, pergola, tower top | 60,000 | 3,754 | 3,754 | 2 |
| Props | 140,000 | 60,959 | 60,959 | 3 |
| Near surroundings: tower walls, neighbour roofs, streets, promenade, beach, boats | 50,000 | 8,809 | 8,809 | 4 |
| Mid backdrop: skyline and islands | 110,000 | 66,665 | 66,665 | 5, 6 |
| Far horizon: painted into the day skybox, no geometry | 2,000 | 0 | 0 | 6 |
| **Everything we ship** | **512,000** | | | |
| Headroom for avatars | 488,000 or more | | | |

## Per-instance caps

| Prop | Cap | Count in plan | Built | Total |
|---|---:|---:|---:|---:|
| Palm (trunk 600 or less, fronds as alpha cards) | 2,500 | 18 | 1,092 (trunk 236) | 19,656 |
| Fern planter | 1,200 | 12 (the 4 at the crossings scaled 1.3) | 890 | 10,680 |
| Square planter box | 300 | 18 palm boxes (the fern and trough boxes are in their kinds) | 258 | 4,644 |
| Sectional couch | 3,000 | 2 U sectionals, 3 sofa groups | 1,480 / 794 | 5,342 |
| Coffee table | 500 | 1 | 278 | 278 |
| Lantern | 400 | 12 + 2 tall | 202 | 2,828 |
| Umbrella with two loungers | 2,500 | 3 | 838 | 2,514 |
| Fire pit | 1,500 | 1 | 1,061 | 1,061 |
| Grand piano | 4,000 | 1 (and its bench, 92) | 658 | 750 |
| Snack counter | 4,000 | 0 (out for now, Checkpoint A) | | |
| Fern trough (ours, no brief cap) | 1,200 | 11 | 1,122 | 12,342 |
| Globe light | 150 | 6 | 144 | 864 |
| Pergola | 8,000 | 1 (counted in architecture) | about 460 with its slats (plain columns) | 460 |

Built (Stage 3), the props come to 60,959 triangles over every placement, inside the props
group's 140,000. Studio's EditableMesh count matches Blender's.

## Other limits

| Item | Limit | Used |
|---|---:|---:|
| Unique map textures (1024 exports) | 20 | 13 (arch, floor colour, floor normal, foliage, overlays, props, plants, near, skyline, islands, shallows, and the emissive masks for the skyline's windows and the table glow) |
| Skyboxes | 2 (six faces each) | 3 (day, dusk, sunset; gen_sky.py): the brief's allowed in-between sky, because one swap popped (DECISIONS) |
| Far-card images | 4 | 0 (the far horizon is painted into the skybox faces instead) |
| MeshParts, rooftop and props | 400 | 171 (architecture 10, props 161) |
| MeshParts, backdrop | about 30 | 25 (the near world: 8 meshes and 3 boats; the mid backdrop: 14 chunks) |
| PointLights, SpotLights, SurfaceLights (Shadows off) | 20 | 9 (the two tall lanterns, the fire pit, the six pergola globes) |

## Stage 2: the architecture (2026-09-26)

After three critic rounds: 3,834 triangles, Blender and Studio (EditableMesh) agreeing. The
first build was 4,302; plain columns (no plinths or capitals) and a simpler pergola took it
down. `checkpoints/rooftop_triangles.txt` lists each mesh.

The floor is Parts with a tiled MaterialVariant: no triangles. No lights yet.

## Stage 4: the near world, the sea and the sky (2026-09-26)

`gen_near.py` builds the near world at 8,795 triangles, plus two more sailboats (37 each) in
Studio: 8,869, matching Blender. It has 11 MeshParts: the tower's walls, the ground, two
building chunks, the coast, the shallows band, palms, trees, and three boats. There is one new
texture (`near_color.png`) and one skybox (six faces, `gen_sky.py`). The Terrain water reaches
8,000 studs; it costs no triangles.

## Stage 5: the mid backdrop (2026-09-26)

`gen_backdrop.py` drives two builder modules:
- `backdrop/skyline.py`: 1,054 lots from 450 to 2,300 studs, five landmarks and tree lawns,
  44,465 triangles;
- `backdrop/islands.py`: eight islands with their shallows, 12,734 triangles.

That's 57,199 triangles in 12 chunks, each at most 12,148 triangles and 1,332 studs across.
In Studio the count matches Blender. With the near world there are 23 backdrop MeshParts
(budget 30). There are three new images: `skyline_color`, `islands_color`, and
`shallows_color` (the shallows alone, so far-off mip levels no longer bleed into them). That
makes 11 of the 20.

## Stage 6: the far horizon (2026-09-26)

No new geometry and no new images. `gen_sky.py` renders the far world into the day skybox's
six faces (1,024 pixels each): 5,837 far lots (59,455 faces) and 23 far islands (20,184
faces), in Blender only. The 3D water and land slabs shrank from 8,000 to 2,600 studs, so
the gray-box lost its far island cones and slabs.

The second critic round reshaped the mid city (the stair side eases in by bearing, the outer
400 studs step down): the skyline module went from 44,465 to 45,129 triangles, the backdrop to
57,863 in the same 12 chunks, matching in Studio.

## The stair side filled, and full detail (2026-09-26)

The designer found a flat grey plain behind the spawn (the thinned mid city) and warped towers
at a distance. The mid city now keeps every block on the stair side (still low), and the strip
beside the beach promenade is built too (`city_plan.blocks`' `fill_beyond`). The near world's
blocks and the painted far city are unchanged.
- The skyline module is 53,931 triangles, and the backdrop 66,665 in 14 chunks (two new ones
  beside the beach). Studio matches Blender.
- The near world is 8,735 in Blender and 8,809 in Studio with the boats. Some parks between 450
  and 520 studs out became city cells.
- 25 backdrop MeshParts (budget 30).
- Every near and backdrop mesh but the tower now draws at RenderFidelity Precise, so each
  triangle counted here is drawn at every distance. Performance's LOD crumpled the boxes.

