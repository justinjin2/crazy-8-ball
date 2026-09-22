# Status

**Last updated:** 2026-09-22. Physics realism C implemented; A-C are verified code steps.
Report after C, per `prompts/PHYSICS_REALISM_PROMPT.md`. D-F are not started.

## Current work: physics realism C

Cushions now use Han 2005's tilted contact normal through the ball centre and full tangential
friction, including english and draw/follow. Restitution interpolates from 0.9 at 20 in/s to
0.6 at 300 in/s of normal approach speed; the constant fallback is 0.85 and friction is 0.2.
Only tangential impulses create torque. Vertical translation is discarded. Extreme future
material overrides also have an energy-preserving outward constraint.

Corner openings move back to leave a supported shelf: **1.733333 in with today's 2.6 in
balls**, becoming **1.5 in with regulation balls in F**. Corner facings now reach the shifted
opening rim so balls cannot escape through a gap behind the jaw. Side geometry is unchanged.

**Verified:** 109 Lune tests, StyLua, Selene and luau-lsp. New coverage checks measured
rebounds, running/reverse english, interpolation/fallback, mirror/rotation symmetry, heavy
draw and 4,000 deterministic cushion contacts without energy gain or inward rebounds.
Pocket coverage includes 84 corner entries across angles, speeds up to 528 in/s and english,
plus a ball that can stop on the supported shelf. Existing break guards, throw, determinism,
trace and server replay checks pass.

Rojo sync was confirmed before fresh Studio Play. Runtime measurements match Lune:
- Rolling 100 in/s at 45 degrees: **43.863807 degrees**, **76.397643 in/s** outgoing.
- Perpendicular stun: **50.418857%** speed retained at 300 in/s, **70.285286%** at 100 in/s.
  The prompt's half-speed test needed its impact speed specified; the model was not retuned.
- Actual desktop power-bar break: **6.10 s**, 26 ball hits, 25 rails, one pocketed.
  Console clean, no replay drift warning, native screenshot shows the settled table.

Bank length also depends on spin reaching the cushion and the cloth after rebound. From one
fixed centre-strike setup, gentle 40 in/s reaches the rail rolling and its settled rebound
runs long (**57.216 degrees** from normal); hard 160 in/s is still sliding on arrival and
settles short (**40.877 degrees**). Immediate contact angles alone do not have this ordering;
it is not a universal claim for every launch spin or speed.

**Visual choice pending:** the live table is `ServerStorage.PoolTableModel`, an imported mesh.
It does not rebuild its holes from Config. The physics and generated table share the new
shelf; the imported mesh still has different pocket geometry. Asked whether to temporarily
use the matching generated table or retain the imported appearance and defer its mesh update.
No table art or place assets have been changed while that choice is pending.

**Phone/controller acceptance remains deferred at the designer's request to move on.**
Controller detection in A was not a successful controller shot. No new device attempt was
made in B/C. Spin inputs remain scripted until the selector and wire arrive in E.

## Previous verified contact step B

Ball contacts use the six-point friction table, capped tangential impulse, throw and spin
transfer. Normal restitution is 0.95. Full contact torque is retained while translation stays
planar. Dropping vertical slip would prevent rolling-to-backspin transfer, so the research
and prompt were corrected. The table's half-ball stun benchmark is **25.88181 degrees**;
fixed friction 0.06 gives **26.56637**, and gearing english gives **30.00000**.
B passed 98 tests including 20,000 deterministic contact pairs and guarded full breaks.
The existing strong draw/follow setup starts 6 in behind the object to preserve enough spin;
its original three-inch separation assertions remain. Classic's object-ball line stays
geometric and does not compensate for throw.

## Physics A and later decisions

A set sliding friction 0.20, rolling resistance 0.010, cloth presets 0.015/0.012/0.008,
ball restitution 0.95, cushion nose 0.635 diameters, rest cutoff 0.25 in/s and instant-contact
tolerance 1e-7 s. Side spin decays at 10.9 rad/s^2 independent of radius. Spin in place no
longer holds a shot open; keep it while other balls move and clear it when the shot ends.
Horizontal spin and pocket motion still count. A's known answers remain tested: 30 in/s
stun reaches rolling at 21.428571 in/s after 0.111003 s; +/-60 rad/s spin reaches zero at
step 1322 (5.508333 s) at both radii. No place assets changed in A-C.

**Decided for D-F:** one bar reaching 30 mph, Classic predicts cue-ball launch direction
including squirt, regulation physics balls with visual scaling, fixed 4-degree elevation,
and identical physics across collectible cues. Current radius remains 1.3 in until F.
Roadmap 1.6 stays unticked until E and its platform acceptance checks are complete.

## Existing build and outstanding checks

- Roadmap 0 and 1.1-1.4 done. 1.5 built (placement, incremental rendering, gamepad bindings,
  lounge, server pads, validated shot simulation, replay seeds, watched cues and sofa seats),
  but real-controller and Start Server + 2 Players checks have never passed. Leave unticked.
- Lounge disabled (`Lounge.Enabled = false`, `TableCount = 1`): plain baseplate and one
  table for tuning. Imported lounge preserved in `ServerStorage.Lounge`. Enable and set
  TableCount to 12 to restore it; do not polish the placeholder lounge.
- Sound/juice 1.7 is partly built: original impact/rolling/tick recordings, measured gains,
  power-banded cue strikes, cushion take, clack stacking, crossfaded rolling, pocket sting
  and nudge, cue art in the power bar and pull-only stretch playback. Nice-shot popup remains.
  Previous status still listed stretch work despite describing implemented playback; verify
  its intended completion by ear. No human listening acceptance is recorded for the latest
  cue strike, tick density/level or pocket sting. Status HUD toggles with F3.
- Aim visuals hide immediately on release. Camera holds 0.5 s, pulls out over 0.7 s with
  0.22 s easing, and returns to zoom 0.625. Small-shot cutoff uses half-table rollout;
  0.06 screen-edge margin overrides the hold. Real wide-bank edge override remains untested.
- Generated table opening and lip tipping share geometry with physics; imported art does
  not. Pocket regressions pass. Generated corner leather lining leaves exposed blue bed
  cut-face: a remaining cosmetic TableBuilder issue.

## Known debts to preserve

- Multiplayer: watched cue cleanup, late-join rack state, duplicate ShotResult restarting
  replays, two shooters sharing one cue/visibility, pad glow with two occupants,
  unvalidated RequestSeat, unclamped initial replay lateness, and narrow immediate re-seat.
- Cross-device determinism remains unproven; same-machine replay is exact. Remote avatar
  pose replication is deferred to 2.3. Rules are not written (2.1).
- On-screen aiming arrows were removed by the designer. PC/phone lack the required button
  alternative to aiming drag; gamepad D-pad still nudges.
- Real low-end performance with twelve tables is unmeasured. Keep the 528-triangle ball
  mesh `rbxassetid://95659700767034`, DoubleSided false. Rolling take 1's boosted noise
  floor needs listening; SoundService clamps DopplerScale zero to 0.001.
- MCP Play screenshots are documented as black; native screenshots worked this session
  before the UI automation failure. Edit requires can be stale, and MCP module copies do
  not share running-game upvalues. Read STUDIO_NOTES before troubleshooting.

## Next checks and handoff

Try gentle shots and a hard break on phone and a real controller; verify motion finishes
and aiming returns. Run Start Server + 2 Players for the still-open 1.5 acceptance.
After reporting C, D is the cue-impact model; preserve the explicit stop after each milestone.
No place assets were edited in A-C. The standing milestone handoff asks the user
to save `place/8ball.rbxl` and publish; scripts themselves are edited only through Rojo.
