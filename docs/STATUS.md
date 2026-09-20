# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-20 (Roadmap 1.5 code complete; two acceptance checks outstanding).

## Where the build is

Phase 0 and Roadmap 1.1 to 1.4 are done and verified. **Roadmap 1.5 is built end to end but
its box is NOT ticked**, because two of its own acceptance criteria have never been run: see
"Before 1.5 can be ticked" below.

Concretely, the game now is: a lounge of twelve tables in three tiers; you join one by
standing on its floor pad, which turns green so the room can see it is taken; the client
sends only shot inputs and the server validates, simulates and broadcasts them, and every
client replays the same shot from the same numbers; the nearest few tables draw their balls
and you can watch other people's cues turn at them; the sofas are sittable. 42 Lune tests.

## Current milestone

**Roadmap 1.5: Lounge and twelve server-owned tables.** All seven stages committed.

- [x] **1.5a Placement.** `src/shared/Placement.luau` (pure, Lune-tested) replaced the single
  global table origin: a table can stand anywhere at any yaw. Fixed three yaw bugs the
  obvious search missed (`Camera.aimDirection`, `AvatarPose`'s world-axis rim test and its
  single floor height).
- [x] **1.5b Rolling and the frame freeze.** Balls turn from the simulation's real angular
  velocity, so a struck ball visibly skids before it rolls. `Match` steps a live simulation
  from the render loop instead of calling `Simulation.run` inside one frame. Ball mesh
  regenerated at 528 triangles.
- [x] **1.5c Gamepad.** Left stick aims, D-pad nudges, right stick zooms, right trigger is
  the power bar, ButtonB leaves. Bound through ContextActionService only while at a table.
- [x] **1.5d Lounge and twelve tables.** Six FBX packages imported and corrected;
  `src/shared/LoungeBuilder.luau` does materials, collision, lights, lighting, spawn and
  seats from Config and is re-runnable. Per-table shadow light deleted.
- [x] **1.5e Floor pads.** Server-owned seats, 5 Hz polling with a dwell, and a renderer
  pool so only the nearest tables draw balls.
- [x] **1.5f Server authority.** `Net`, `TableService`, `ShotService`. Clients replay from
  the server's post-strike seed and settle on its final positions; every shot carries a
  checksum.
- [x] **1.5g Aim replication and seats.** Batched unreliable aim stream, watched cues on the
  renderer pool, invisible sofa seats (free look), pad flash.

## Before 1.5 can be ticked

Both need a human; neither can be driven from an agent session.

1. **Gamepad has never been tested with a real controller.** Every number behind it is
   verified (aim rate, dead zone, curve, zoom rate, power ramp, the bind/unbind), but no pad
   was ever connected, so the mapping from each physical button to each action is unproven.
   The standing rule is that every milestone is checked on phone, PC and gamepad.
2. **Two players in one server have never been run.** Studio's **Start Server + 2 Players**
   is the test: two clients at two different tables while a third walks between them and
   sees both games. The server authority and the aim stream are verified single-client and
   with an injected second player, but not with two real clients.

## Open bugs and debts

- The lounge is a PLACEHOLDER the designer will replace. Do not polish its art. After
  importing a new build, run `LoungeBuilder.setUp(workspace)` in Edit mode.
- `assets/balls/ball_sphere.obj` is 528 triangles but the place may still hold the old
  2,208-triangle `ServerStorage.BallMesh`. Needs a re-import by hand.
- Triangle budget with everything resident: lounge 78,422, twelve tables 230,640, balls
  33,792 now that only four tables draw (was 101,376). Real frame rates are still unmeasured
  because Studio throttles an unfocused viewport to 15 FPS.
- Cross-platform determinism is instrumented but unproven: same-machine replays match the
  server exactly (0.0000 in), which does not exercise a different libm. The first phone
  playtest will either be silent or print a drift warning.
- Remote players' bodies are not posed for watchers, only their cue. `AvatarPose` anchors
  individual limbs, which does not replicate reliably from the owning client. Deferred to
  2.3.
- Studio caches Edit-mode `require` results for the whole session. Editing a shared module
  and re-running it in Edit mode silently runs the old copy; restart Studio first.
- `src/shared/Rules/` is an empty folder; rules are Roadmap 2.1.
- `Lighting.Technology` is not readable or writable through the tools; set it to Future by
  hand if shadows look wrong.

## Things only the user can do

- **Test the gamepad** and **run Start Server + 2 Players** (see above). These are what is
  standing between 1.5 and a tick.
- **Save and publish the place.** The imported lounge, its materials and collision, the
  twelve pendant lights, the Lighting recipe and the spawn live only in the place file.
- **Re-import `assets/balls/ball_sphere.obj`** (3D Importer, Scale Unit: Stud, scale 1) over
  `ServerStorage.BallMesh`.
- Click Connect in the Rojo plugin after every Studio or Rojo restart.
