# Skyline Club hub: progress

Brief: `docs/prompts/HUB_BLENDER_PROMPT.md`. Builder: `assets/hub/HubBuilder.py`. Scene:
`assets/hub/Hub.blend`. How to use the package: `assets/hub/Readme.md`.

## Status: all six stages done; the package is import-ready (2026-09-25)

## Done

1. **Blockout and audit.** The layout was approved by the designer (see DECISIONS.md).
2. **Architecture and materials.**
   - Procedural textures: 4096 marble and carpet masters (1024 uploads), slat ceiling, palette
     atlas, fluted glass.
   - Walls and windows with the yellow band, curved NW and NE corners, the raised walkway tray,
     bulkheads with downlights and LED lines, beams.
   - Black-framed glass partitions, black glass columns with gold edges.
   - Balcony and prow, the stair, stair seats, the cue room, the yellow fin, the piano stage, the
     terrace, the collision boxes.
3. **Furniture and anchors.**
   - Prop library: armchair, side table, sofa, stool, pouf, plant, cue rack, plinth, umbrella and
     three pendant shapes, with 247 placements.
   - Unique furniture: bar, kiosks, booths, jukebox, capsule and lattice screens, the wavy ribbon,
     zone signs and screens, the featured screen, logo panels, the piano placeholder.
   - 86 anchors and 188 seats.
4. **Skyline and lights.**
   - The far city and mountains rendered into Dusk, Day and Night skyboxes. The face orientation
     was tested with labelled faces in Studio.
   - 30 near towers from 4 masters, 5 silhouette cards, the haze deck.
   - 30 Roblox lights and the EEVEE dusk preview. The review renders were checked against the
     palette and fixed.
5. **Optimise, bake, export.**
   - Prop atlas bake: colour × light AO, roughness, metalness.
   - Marble reflection overlay (a Cycles glossy bake, blurred).
   - Eight FBX packages, `Markers.json`, `Validation.md`: PASS.
6. **Final dusk renders** (`renders/final_*.png`) and `Readme.md`.

## Remaining (outside this brief)

Roadmap 4.1 continues in Studio: import, align, upload textures and skyboxes, place tables,
props, seats and lights from `Markers.json`, and apply the Lighting recipe.

## Last success

2026-09-25:
- Through the MCP: `architecture furnish skyline lighting audit save`.
- Headless on `Hub.blend`: `bake export validate save`, then `final`. Validation PASS.

## Exact resume step

None needed. To change anything, edit `PARAMETERS` and rerun from the first affected stage,
as described in the Readme's Rebuild section.
