# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-20 (Roadmap 1.5 in progress: stages a and b done).

## Where the build is

Done and verified in Studio: Phase 0, Roadmap 1.1 to 1.4, and stages a and b of 1.5.
Concretely: custom physics with 38 passing Lune tests; corridor guideline; orbit camera with
continuous zoom; posed faded avatar; imported Blender 9 ft table
(`ServerStorage.PoolTableModel`, 7 MeshParts, 28 PBR maps); sphere-mesh balls
(`ServerStorage.BallMesh`) with 16 baked textures; join by holding E on a ProximityPrompt (to
be replaced by a floor pad in 1.5e); ONE table, now standing at Table_01's real lounge spot
(-30, 0, 0) at yaw 90; shots run on the client only (no networking yet).

## Current milestone

**Roadmap 1.5: Lounge and twelve server-owned tables.** Being built in stages; the plan
splits it so it can be stopped after any one of them.

- [x] **1.5a Placement.** `src/shared/Placement.luau` (pure, Lune-tested) replaces the single
  `Config.World.TableOrigin`: any table can stand anywhere at any yaw. `Config.Lounge.Tables`
  holds the twelve rows, checked against `assets/lounge/Markers.json` by a test. Tables live
  in `Workspace.Tables/Table_NN`; client visuals in `Workspace.ClientVisuals`.
- [x] **1.5b Rolling and the frame freeze.** Balls turn from their real angular velocity, not
  from distance travelled. `Match` steps a live simulation from the render loop instead of
  calling `Simulation.run` up front. Ball mesh regenerated at 528 triangles.
- [x] **1.5c Gamepad.** Left stick aims, D-pad nudges, right stick zooms, right trigger is
  the power bar (ButtonA for digital-trigger pads), ButtonB leaves. Bound through
  ContextActionService only while at the table. **The buttons have never been physically
  pressed** (see the debts below).
- [ ] **1.5d Import the lounge, build twelve tables, phone perf checkpoint.**
- [ ] **1.5e Floor pads, join and leave, pooled per-table renderers.**
- [ ] **1.5f Server authority:** `Net`, `TableService`, `ShotService`.
- [ ] **1.5g Aim replication, seats, pad VFX.**

## Open bugs and debts

- **The gamepad has never been tested with a real controller.** The aim rate, dead zone,
  aim curve, zoom rate, power ramp and the ContextActionService bind/unbind are all verified
  numerically in Studio, but no pad was connected, so the mapping from each physical button
  to each action is unproven. This breaks the standing rule that every milestone is checked
  on phone, PC and gamepad; 1.5 is not finishable until someone presses the buttons.
- This place has no `PlayerModule` in `PlayerScripts`, so the usual
  `GetControls():Disable()` does nothing. The ContextActionService sink covers it, but if
  walking ever fights aiming again, that is why.
- The "apparent issues" with the mesh balls were the ROLLING ROTATION; fixed in 1.5b.
- `assets/balls/ball_sphere.obj` is regenerated at 528 triangles but the place still holds
  the old 2,208-triangle `ServerStorage.BallMesh`. Needs a re-import by hand.
- One shadow-casting SpotLight per table (`Config.Look.TableLight`) will not scale to twelve
  tables; it is deleted in 1.5d in favour of sun shadows plus the package's twelve
  non-shadow pendant SurfaceLights.
- `Cue.strike` uses `math.cos`/`math.sin`/`pow`, which are platform libm and not correctly
  rounded, so a client replaying a shot could diverge from the server. 1.5f sends the
  server's post-strike cue-ball state as the replay seed instead, plus a hash check.
- `src/shared/Rules/` is an empty folder; rules are Roadmap 2.1.
- Lighting.Technology of the place is unknown (not readable through the tools); check by hand
  if shadows look wrong.

## Things only the user can do

- **Test the gamepad** (1.5c): plug in any controller, Play, hold E at the table, then check
  the left stick aims, the D-pad nudges, the right stick zooms, holding and releasing the
  right trigger shoots with the power it was pulled to, and B leaves the table.
- **Re-import `assets/balls/ball_sphere.obj`** (3D Importer, Scale Unit: Stud, scale 1) and
  replace `ServerStorage.BallMesh` with it: 528 triangles instead of 2,208.
- **Import the six lounge FBX files** for 1.5d (see `assets/lounge/Readme.md` and the stage's
  click steps).
- Save the place to `place/8ball.rbxl` (File, Save to File As) and publish, after any Edit-mode
  change. The place holds the table model, ball mesh and cloth material.
- Click Connect in the Rojo plugin after every Studio or Rojo restart.
