# Status

One page. Rewritten at the end of every working session by whichever tool did the work.
Read this first, then the roadmap item it names.

**Last updated:** 2026-09-21 (pockets take the ball properly; three new recordings in).

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

The power control now has a cue in it. The vertical bar and its fill are unchanged, and a
top-down cue nearly fills the bar at rest and slides a whole bar height as you pull, leaving
the bar entirely at full power the way GamePigeon does. The cue is drawn from
`Config.Cue.Styles` through the new pure `src/shared/CueArt.luau`, so a collectible cue is a
data row and the same row will drive the 3D stick and an inventory thumbnail later. The bar sits high on the screen, clear of the Leave button, so the whole cue stays visible at
full pull. Drawing
back plays the rubber-tension recording only while the cue is actually still moving: holding
it at power is silent, and resuming a paused drag carries on from where the recording left
off rather than restarting it. Playback is held clear of the release at the end of that
recording, so it only ever sounds like something being stretched. **72 Lune tests.**

Pocketing a ball now nudges the camera a hair toward the pocket that took it - measured at
0.056 studs on a gentle drop, settled back to exactly zero a quarter of a second later.

## Pockets now take the ball when they look like they should

A ball that reached the jaws and ran out of steam used to sit there for the rest of the game,
visibly overhanging the hole. Three causes, all measured: the physics capture circle was
0.5 in TIGHTER than the hole that gets drawn, so a centre could be half an inch inside the
visible rim and still not fall; the opening sat so far back that a ball had to travel 3.12 in
past the mouth before anything took it, and a ball hugging the rail into a corner could never
reach the corner hole at all; and `capturePockets` skipped balls that had stopped, so a hanger
was never reconsidered.

The opening is now derived from the mouth: radius = half the mouth, placed so the rim is
tangent to the line joining the two cushion noses. A corner lands exactly on the table corner
at radius 2.600, and the jaw tips fall at 2.609 from that centre, so the rim and the jaws
coincide. TableBuilder cuts the hole one leather thickness wider than that same number, so
art and physics read one value and `Look.PocketLinerExtraInches` is gone.

A ball whose centre crosses the rim now TIPS IN: it pivots about the rim point, a solid sphere
on an edge, and leaves the lip when the edge stops pushing back. One rule covers everything -
a trickler hangs and takes about a third of a second to topple, anything at 50 in/s or more
separates immediately and behaves exactly as before. The pocket event fires when the ball
comes off the lip, so a hanger's drop reports ~17 in/s instead of ~0 and is audible.

Verified on the live server: 203 shots at a corner gave 174 pocketed, 29 rattled back onto
the cloth, **0 stranded**; 203 at a side gave 101, 102, 0. 40 full breaks pocketed 23 balls,
longest shot 9.41s, none capped, **no ball left sitting over an opening**. Tip times 0.163s at
3 in/s down to 0.000s at 60 and above. Console clean, no pocket-cut warnings. **84 Lune
tests**, 12 of them new in `tests/physics_pocket_test.luau`.

**Now seen.** The corner reads as a real pocket: a round opening centred on the table corner
with the jaw tips sitting on its rim. The predicted side-pocket notch is there - the hole is
cut 0.52 in past the outer face of the rail - but the leather ring wraps it and it reads as an
ordinary table detail, not damage. `Table.RailWidthInches` 6.1 would swallow it if it ever
looks wrong.

**One cosmetic regression the bigger hole exposed.** `TableBuilder`'s leather lining is an
annulus minus `innerHalfBox`, so it only covers the half of the throat AWAY from the table.
That was invisible while the opening sat mostly outside the cushion line; now that it is
centred on the corner, a quarter of it is inside the cloth and the bed's cut face shows there
as raw bright blue instead of leather. Fix is in `innerHalfBox` / the PocketWall build, not in
the physics.

## Three new recordings

**Cue strikes are banded by power.** cue_strike_2 over the bottom quarter of the bar,
cue_strike_1 over the middle half, cue_strike_3 (new) over the top quarter. The bands are
written as power fractions and converted to cue ball speeds in Config's derived block,
because speed goes as power^2.6: 25% of the bar is only 29 in/s out of 528. Verified at
runtime - 0.24 power picks the soft take, 0.26 the middle, 0.76 the hard one, and exactly on
a line either neighbour may play.

**The turn tick replaces the Roblox library click**, which was the last library sound in the
game, and now fires every **0.1 degrees** rather than every 2. A nudge tap is 0.2 degrees, so
under the old value careful aiming - the one place per-degree feedback is worth having - was
silent. `MinSecondsBetweenTicks` is a CEILING on the repeat rate, and both halves of the feel
fall out of it: at 10 a second and 0.1 degrees a step, anything slower than one degree a
second clicks on every single step, and anything faster stops trying to keep up. Measured -
at 0.5 deg/s all 9 steps played, at 1 deg/s all 17; by 3 deg/s it is one click per 0.38
degrees, at 40 one per 4.2, at 400 one per 44. Two voices at every speed, so ticks never
overlap and the level is the measured one.

**A bright sting layers on top of every pocket drop**, at 15.8 dB under the drop at the drop's
loudest, pitched dead straight. Withheld for the cue ball - a scratch is not a reward.

All three gains are measurements: peaks 0.940, 0.729 and 0.786, each levelled to 0.5 like
every other clip. **85 Lune tests.**

**Studio's screen capture through MCP works in EDIT mode and returns a pure black frame in
PLAY mode.** Restarting Studio fixed Edit; Play is still black, with the default camera as
well as a scripted one, so it is not a camera problem. To look at anything an agent needs a
temporary table built in Edit mode - `TableBuilder.build(folder, Placement.forTable(1), 1)`
into a throwaway folder, screenshot, then DESTROY the folder, because Team Create saves the
place continuously and nothing built this way belongs in it.

Before the restart, Edit was black too. That was proven not to be the environment: Studio was
frontmost, visible and rendering, the display awake, and an OS-level `screencapture` of the
same screen at the same moment came back correctly exposed.

**Nobody has HEARD any of this yet.** It is verified mechanically - the right clip ids reach
the right voices at the right volumes - but the three judgements that need ears are: whether
cue_strike_3 sits right at the top of the bar, whether the tick is at a comfortable level and
density (the designer called this v1 and may swap it), and whether the bonus sting is too
forward or too buried over the drop. `Audio.Tick` (level), `Audio.MinSecondsBetweenTicks`
(density) and `Audio.Bonus.MaxVolume` are the numbers to move.

## Aiming visuals end at the release

The cue, the ghost ball and the guideline used to stay on screen through the whole server
round trip after a shot was sent, still pointing at a shot already taken. The only thing
hiding them was `match:isBusy()`, and the shot does not begin on the client: inputs go to the
server and the balls move when it broadcasts back, so `isBusy()` is false for the entire trip.

A client-side `awaitingShot` now carries that state from the release to the server's answer,
and one `canAim()` decides whether any of the aiming visuals are drawn. Cleared at the end of
the shot, on a rejected shot, and on leaving the table. Measured at 60 Hz through a real
drag-and-release on the power bar: the cue and the guideline go in the SAME sample as the bar
returning to zero, 0.0 ms after release, stay gone for the whole shot, and come back when it
ends.

`canAim()` is where turns hook in at Roadmap 2.1 - "is a shot running" becomes "is it my
turn", in one place.

## The HUD is down to the power bar and Leave

The on-screen nudge arrows are gone at the designer's call, and the status line is off by
default with **F3** to bring it in and out (`Config.Debug.StatusKey`). At a table the screen
now holds the power bar and the Leave button, nothing else. Verified in Studio: no nudge
buttons anywhere in the GUI tree, status hidden on join, F3 toggles it on and off.

**This leaves a gap against CLAUDE.md's "every drag has a button alternative".** The nudge
buttons were the only non-drag way to aim on phone and on PC. The gamepad keeps its D-pad
nudge and `Config.Input.NudgeDegrees` stays because that path uses it. If fine aiming needs a
button again, keyboard arrow keys are the cheap fix for PC; the phone would need something
new.

## The camera holds, then pulls out, then comes back to one framing

Every turn now starts from `Camera.View.ZoomDefault` (0.625), the exact midpoint of the zoom
range and also the halfway point in scroll notches, since the distance is interpolated
geometrically. At the 9 ft table that is 5.3 studs from the cue ball at a 35 degree pitch
(fitted is 10.1 studs at 50 degrees; closest is 2.2 at 18). The camera resets to it at the end
of every shot rather than keeping whatever the player pinched to.

And it no longer leaves at the strike, or always leaves at all. Three rules decide it:

- **Is it worth leaving for?** `Shot.MinTravelTableLengths` (0.5). If the cue ball could not
  run half a table length on an empty table, the camera never moves - a tap has nothing to
  show at the far end. The test is `Cue.rollOutDistance`, a new pure closed form verified
  against the integrator to within 0.05 in, and it BOUNDS every ball in the shot, so it can
  never hold still on a shot where something really travels.
- **When to go.** `Shot.HoldSeconds` (0.5) after the strike...
- **...or sooner.** `Shot.OffScreenMargin` (0.06) - a ball counts as gone once its centre is
  within 6% of the screen edge, and that overrides both of the above, because wherever the
  shot has gone the camera has to follow.

Then it pulls out over `Shot.PullOutSeconds`
(0.7) against a 0.22s easing, smoothstepped so the move has no corners. That pair was 1.2 and
0.35, which took 1.6s to get 95% of the way out and read as slow; it now does it in 0.93s, and
the eased shape survives the cut (7%, 22%, 40%, 58%, 74%, 89%, 96%).

Measured in Studio against the TABLE CENTRE, which is fixed - measuring against the cue ball
is meaningless mid-shot, because the ball moves while the camera's anchor is frozen: strike at
6.22s, camera first moves at 6.78s (a 0.57s hold), 95% of the way out 0.93s later, settled
back at zoom 0.625 when the balls stopped. Strike to whole table is about 1.5s, against 2.7s
when the hold was 1.0 and the move 1.6.

The off-screen rule was verified by forcing the margin to 0.92 at runtime, so any off-centre
ball trips it: the hold fell to 0.33s against the 0.50s fallback, camera first moving 0.13s
after the strike. At the real 0.06 the straight shots that could be driven from an agent
session never tripped it and the fallback governed - expected, since the close view looks DOWN
the aim line and balls mostly stay inside the cone. **It has not been seen firing on a real
bank shot**, which needs a human aiming wide.

The small-shot cutoff was verified directly: a 0.13-power tap moved the camera 0.00 studs
across a 2.51s shot, and a full-power shot straight after pulled out 7.07 studs on a 0.65s
hold and a 0.95s move.

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
