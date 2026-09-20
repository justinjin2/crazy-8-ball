# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-21 (lounge set aside; testing on a baseplate with one table).

## The lounge is switched off

The designer does not like the placeholder lounge, so `Config.Lounge.Enabled = false` and
`Config.Lounge.TableCount = 1`: the game runs on a plain Roblox baseplate with one table,
which is the setup the shot is being tuned on. The imported lounge model was MOVED to
`ServerStorage.Lounge` rather than deleted, because it is six FBX imports of hand work; say
the word and it goes for good.

Nothing else changed. Tables are still server-owned, shots are still validated, simulated
and broadcast by the server, clients still replay from the server's seed, and the floor pad
still seats you. Set `Enabled = true` and `TableCount = 12` to get the lounge back.

## Where the build is

Phase 0 and Roadmap 1.1 to 1.4 are done and verified. **Roadmap 1.5 is built end to end but
its box is NOT ticked**, because two of its own acceptance criteria have never been run: see
"Before 1.5 can be ticked" below.

Concretely, the game now is: a baseplate with one pool table; you join it by standing on its
floor pad, which turns green; the client sends only shot inputs and the server validates,
simulates and broadcasts them, and every client replays the same shot from the same numbers.
The twelve-table lounge, the renderer pool, the watched cues and the sofa seats are all
built and switched off behind one Config flag. 42 Lune tests.

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
- Triangle budget with everything resident: lounge 78,422, twelve tables 230,640, balls
  8,448 (four drawn tables on the 528-triangle mesh; it was 101,376 with twelve tables on
  the old 2,208-triangle one). Real frame rates are still unmeasured
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
  twelve pendant lights, the Lighting recipe, the spawn and the 528-triangle
  `ServerStorage.BallMesh` live only in the place file. Ctrl+S is enough once the place has
  been saved once; "Save to File As" is only for the first time or to refresh the
  `place/8ball.rbxl` copy that Git tracks.
- Click Connect in the Rojo plugin after every Studio or Rojo restart.
