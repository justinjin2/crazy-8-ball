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
| Near surroundings: tower walls, neighbour roofs, streets, promenade, beach, boats | 50,000 | 8,869 | 8,869 | 4 |
| Mid backdrop: skyline and islands | 110,000 | 45,759 | | 5 |
| Far cards | 2,000 | | | 6 |
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
| Unique map textures (1024 exports) | 20 | 10 (arch, floor colour, floor normal, foliage, overlays, props, plants, near, skyline, islands) |
| Skyboxes | 2 (six faces each) | 1 (day; gen_sky.py) |
| Far-card images | 4 | 0 |
| MeshParts, rooftop and props | 400 | 171 (architecture 10, props 161) |
| MeshParts, backdrop | about 30 | 23 (the near world: 8 meshes and 3 boats; the mid backdrop: 12 chunks) |
| PointLights, SpotLights, SurfaceLights (Shadows off) | 20 | 3 (the tall lanterns, the fire pit) |

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
