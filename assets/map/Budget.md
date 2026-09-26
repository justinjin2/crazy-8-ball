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
| Rooftop architecture: floor, parapet, railing, steps, pergola, tower top | 60,000 | | | 2 |
| Props | 140,000 | | | 3 |
| Near surroundings: tower walls, neighbour roofs, streets, promenade, beach, boats | 50,000 | | | 4 |
| Mid backdrop: skyline and islands | 110,000 | | | 5 |
| Far cards | 2,000 | | | 6 |
| **Everything we ship** | **512,000** | | | |
| Headroom for avatars | 488,000 or more | | | |

## Per-instance caps

| Prop | Cap | Count in plan | Built | Total |
|---|---:|---:|---:|---:|
| Palm (trunk 600 or less, fronds as alpha cards) | 2,500 | 12 | | 30,000 at cap |
| Fern planter | 1,200 | 12 | | 14,400 at cap |
| Square planter box | 300 | 24 (one under every palm and fern) | | 7,200 at cap |
| Sectional couch | 3,000 | 5 (2 U sectionals, 3 sofa groups) | | 15,000 at cap |
| Coffee table | 500 | 1, plus 3 ottomans | | 2,000 at cap |
| Lantern | 400 | 14 (2 of them tall) | | 5,600 at cap |
| Umbrella with two loungers | 2,500 | 3 | | 7,500 at cap |
| Fire pit | 1,500 | 1 | | 1,500 at cap |
| Grand piano | 4,000 | 1 | | 4,000 at cap |
| Snack counter | 4,000 | 0 (out for now, Checkpoint A) | | |
| Globe light | 150 | 10 | | 1,500 at cap |
| Pergola | 8,000 | 1 (counted in architecture) | | 8,000 at cap |

At their caps the props come to about 89,000 triangles (the pergola aside), inside the
props group's 140,000.

## Other limits

| Item | Limit | Used |
|---|---:|---:|
| Unique map textures (1024 exports) | 20 | 0 |
| Skyboxes | 2 (six faces each) | 0 |
| Far-card images | 4 | 0 |
| MeshParts, rooftop and props | 400 | 0 |
| MeshParts, backdrop | about 30 | 0 |
| PointLights, SpotLights, SurfaceLights (Shadows off) | 20 | 0 |
