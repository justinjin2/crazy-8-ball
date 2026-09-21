# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-20 (the designer's own sound effects are in and wired).

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

## Sound is in (Roadmap 1.7, most of the way)

Fourteen of the designer's own recordings are uploaded to the group that owns the place, so
they resolve by id and nothing is inserted into Studio by hand. Six ball-on-ball takes in one
random pool, one cushion, two cue strikes, two pocket drops, three rolling takes. Only the
aim tick is still a library sound, because it is a UI click rather than a pool sound.

Clip choice is random and never repeats the previous clip; impact speed drives volume and
pitch on a logarithmic curve. Three numbers behind that are measurements, not guesses, and
each changed the design: the clips span 14 dB so every one carries a measured gain
(`tools/measure_audio.luau`); the median ball contact is only 3.6 in/s so a linear curve put
half of them in the bottom fifth of the range; and the camera sits 16-17.5 studs from the
table, so the old 8-stud rolloff minimum made the mix change with the zoom.

The rolling sound is one continuous sound for the table, following the fastest ball and
emitted from it, built from two Sounds that crossfade at equal power rather than one looped
Sound. The recordings are not known to loop seamlessly and Roblox re-encodes uploads anyway.

The arithmetic is in a new pure `src/shared/SoundMix.luau` with 11 Lune tests. **56 Lune
tests** in total now.

Verified in Studio over 13 shots: all 11 wired clips played, 0 back-to-back repeats in 41
plays, 0 silent frames mid-roll, exactly one cue strike per shot, peak 6 concurrent voices
against a cap of 24, console clean.

An adversarial review across four dimensions raised 15 findings; 5 survived verification and
all 5 are fixed. The two that mattered: leaving a table mid-shot abandoned the rolling voices
still playing at the table you had walked away from, and the same helper left the eased
volume behind so sitting down at a SETTLED table audibly started a rolling clip on a table
where nothing was moving. Also removed `MaxSoundsPerFrame`, which could never bind now that
each contact type has its own wall-clock gap — it was dead config that read like a safety
net. **60 Lune tests.**

A second cushion recording came in afterwards. Cushions are now chosen by impact speed (soft
take up to 70 in/s, hard from 40, overlapping between 40 and 70 so the choice blends rather
than switching at an audible line), and rails were turned down 10.1 dB - they sat 2.4 dB
below a clack at the same speed and now sit 12.6 dB below it, which is where the most
frequent contact in the game belongs. **62 Lune tests.**

Two mix corrections after that. The rolling loop was 13.1 dB too loud, from a real mixing
error: rolling clips are levelled on RMS and impact clips on peak, each right on its own, but
the two families were never checked against each other, and the roll was sitting 4.2 dB ABOVE
a clack continuously. And the floor for ball-on-ball sound dropped from 12 in/s to 1, because
66% of all ball contacts happen below 12 and the median is 3.6 - the old floor silenced two
thirds of the game's contacts, so gentle touches made no sound. Clacks also got their own
quiet end (1 in/s against the shared 10) so soft contacts differ from each other instead of
flattening onto one minimum, and the soft take is now banded to gentle contacts. **63 Lune
tests.**

The harder cushion recording was then dropped entirely - it did not sound like a ball meeting
a cushion - so one soft take now covers every rail contact, leaning on its own extra pitch
wobble for the variation the second take used to provide.

A break now stacks. Contacts at or above 110 in/s skip the gap between clacks and sound
together, which is what makes a hard launch land as one crack rather than a queue of clicks -
measured at nine clacks at once, about 10 dB on the old peak. The threshold is a measured
discriminator, not a guess: a contact cannot be faster than the ball that struck it, so
stacking is impossible below 52% power and stays out of ordinary play entirely. Cushions went
another 8 dB down in the same pass and now sit 22 to 30 dB below a ball contact. **64 Lune
tests.**

**Still to do in 1.7:** the power-bar stretch sound and the "Nice shot" popup. The box stays
unticked.

**What would help most if the designer records more:** a second slow-roll take (that tier has
one clip and the table spends two thirds of a shot in it), and a second cushion take (there
is one, and rails are the most frequent contact in the game after ball hits).

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

## Review findings (2026-09-20 adversarial pass, 39 confirmed)

Fixed so far, all the ones that reproduce with a single player:
- A scratch used to brick the table for the life of the server: the server stored a pocketed
  cue ball, and a state with no cue ball cannot be struck, so every later shot threw inside
  `Simulation.strike` and silently broadcast nothing. `Simulation.respotCueBall` is now
  called by both the server and the client, through the same helper.
- The server struck the ball TWICE: once to make the quantised seed for the wire, once
  unrounded inside `runHeadless`. It therefore ran a shot no client could reproduce.
  Measured over 123 breaks before the fix: 56 diverged, worst 51 inches, 4 ended with a
  different set of balls pocketed. `Simulation.settle` now runs the same numbers that go out.
- The drift warning could never fire: `reconcile` hashed the balls AFTER copying the
  server's answer over them, so it was hashing its own input.
- A refused shot left the client's controls dead. `ShotFired` now always gets an answer.
- Respawning while seated left the camera at the table while the body walked away.

Still open, all needing more than one table or more than one client:
- A cue stick is left standing at a table after the player who was aiming leaves.
- A client connecting after a shot sees a fresh rack on every played table.
- A `ShotResult` arriving mid-replay restarts from mid-flight positions.
- Two players at one table: neither sees the other's cue, and a watcher sees one cue
  swinging between both aims.
- Two players on one pad leave its glow stuck at flash brightness.
- `RequestSeat` is unvalidated: no proximity, dwell, cooldown or rate limit.
- The late-join catch-up seeds `elapsed` with the full lateness, unclamped.
- Leaving can seat you straight back in a narrow case near the head rail.

## Open bugs and debts

- The lounge is a PLACEHOLDER the designer will replace. Do not polish its art. After
  importing a new build, run `LoungeBuilder.setUp(workspace)` in Edit mode.
- Triangle budget with everything resident: lounge 78,422, twelve tables 230,640, balls
  8,448 (four drawn tables on the 528-triangle mesh; it was 101,376 with twelve tables on
  the old 2,208-triangle one). Real frame rates are still unmeasured
  because Studio throttles an unfocused viewport to 15 FPS.
- The ball mesh in the place is `rbxassetid://95659700767034`, wound outward (verified on
  the upload: 528 of 528 faces point out). `Config.Balls.DoubleSided` is false and should
  stay false; it only ever existed to hide the old inside-out upload.
- Cross-platform determinism is instrumented but unproven: same-machine replays match the
  server exactly (0.0000 in), which does not exercise a different libm. The first phone
  playtest will either be silent or print a drift warning.
- Remote players' bodies are not posed for watchers, only their cue. `AvatarPose` anchors
  individual limbs, which does not replicate reliably from the owning client. Deferred to
  2.3.
- `ball_rolling_1` measured 15x quieter than the other two rolling takes and carries a gain
  of 15 to match them. Its noise floor sits 10.4 dB below its own average, which is what says
  it survives the boost, but it is the clip to re-record if the roll ever hisses.
- `SoundService.DopplerScale` is set to 0 and reads back as 0.001; the engine clamps it. That
  is inaudible, not a failed write.
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
