# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-20 (docs reorganised, no code change since 2026-09-19).

## Where the build is

Done and verified in Studio: Phase 0, Roadmap 1.1 to 1.4. Concretely: custom physics with
21 passing Lune tests; corridor guideline; orbit camera with continuous zoom; posed faded
avatar; imported Blender 9 ft table (`ServerStorage.PoolTableModel`, 7 MeshParts, 28 PBR
maps); sphere-mesh balls (`ServerStorage.BallMesh`) with 16 baked textures; join by holding E
on a ProximityPrompt (to be replaced by a floor pad in 1.5); one table at the world origin;
shots run on the client only (no networking yet).

## Current milestone

**Roadmap 1.5: Lounge and twelve server-owned tables.** Nothing started. Plan it in plan mode
first; the server move touches Match, BallRenderer, Main and Bootstrap. Importing the six
lounge FBX files and the tables is a user click step (see `assets/lounge/Readme.md`).

## Open bugs and debts

- The mesh balls have "apparent issues" the designer has not described yet. Ask before 1.5.
- Ball mesh is 2,208 triangles; regenerate at 24 x 12 (about 550) and re-import.
- One shadow-casting SpotLight per table (`Config.Look.TableLight`) will not scale to twelve
  tables; switch to sun shadows plus non-shadow lights in 1.5.
- `src/shared/Rules/` is an empty folder; rules are Roadmap 2.1.
- Lighting.Technology of the place is unknown (not readable through the tools); check by hand
  if shadows look wrong.

## Things only the user can do

- Save the place to `place/8ball.rbxl` (File, Save to File As) and publish, after any Edit-mode
  change. The place holds the table model, ball mesh and cloth material.
- Create the private GitHub repo and connect it (not done yet: no remote exists).
- Click Connect in the Rojo plugin after every Studio or Rojo restart.
