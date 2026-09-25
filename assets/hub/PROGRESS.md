# Skyline Club hub: progress

Brief: `docs/prompts/HUB_BLENDER_PROMPT.md`. Builder: `assets/hub/HubBuilder.py` (idempotent,
stages run through the Blender MCP or headless). Scene: `assets/hub/Hub.blend`.

## Status: stage 1 done, waiting for the designer's approval (the brief's only stop)

## Done

- **Stage 1: blockout and audit** (2026-09-25)
  - Shell (171.5 x 151.5 interior, 26 ceiling), full-height windows on the north, east and west,
    solid south wall with the high yellow band.
  - Zones: 1v1 (10 tables, north along the windows), 2v2 (4, south-west), 3v3 (2, north-east),
    marble walkway east-west, marble plaza, lounge, bar, cue room, piano stage, terrace.
  - Balcony (Z 11.2, 12 deep) with a spawn prow, 14-step stair and 7-tier stair seats.
  - 16 table instances of the appended PoolTable collection in the green look; join pads,
    `Table_n` / `Pad_n` / `Spawn` / screen / kiosk / statue / piano / pro-door anchors.
  - Seat-band proxies for the clearance and hearing-distance checks.
  - `layout_audit.md`: PASS. Longest required walk 105.3 studs (limit 128).
  - Renders (git-ignored checkpoints): `renders/checkpoint_stage1_{plan,spawn,eye_1v1,north_windows,overview}.png`.
  - Headless run verified: the same audit, byte for byte.

## Remaining

2. Architecture and materials: ceiling panels, bulkheads, LED lines, partitions (black frames),
   columns, the hero floors, windows, terrace, curved yellow wall.
3. Furniture, props, anchors, pendants, emissives, signs, cue room, piano placeholder.
4. Skyline, skyboxes, EEVEE dusk lighting preview and review renders.
5. Optimise, unwrap, bake, export, validation.
6. Final renders and `Readme.md`.

## Last success

`blockout audit render1 save` through the MCP, 2026-09-25; headless `blockout audit` matches.

## Exact resume step

After the designer approves the layout (or asks for changes to `PARAMETERS`, then re-run
`blockout audit render1 save`), start stage 2 by adding `stage_architecture` to
`HubBuilder.py`. It replaces the `BO_*` blockout objects in HUB_Shell, HUB_Ceiling, HUB_Balcony,
HUB_Zones and HUB_Circulation, keeps HUB_Tables and HUB_Markers, and re-runs `audit` at the end.
