# Status

**Last updated:** 2026-09-22. Physics realism A implemented and verified in automated tests
and desktop Studio. Stop here to report, per `prompts/PHYSICS_REALISM_PROMPT.md`.

## Current work: physics realism A

The designer requested the realism prompt ahead of the remaining roadmap checks. A changes
only physics tuning, side-spin decay and shot-end behavior; B-F are not started. Roadmap 1.6
stays unticked until E and its platform acceptance checks are complete.

- Sliding friction 0.20, rolling resistance 0.010; optional slow/medium/fast cloth values
  0.015/0.012/0.008. Ball restitution 0.95; cushion nose 0.635 ball diameters.
- Rest cutoff 0.25 in/s; instant-contact tolerance 1e-7 s.
- Side spin decays at 10.9 rad/s^2 regardless of radius. Spin in place no longer delays
  the next shot. Keep that spin while other balls move, then clear it when the shot ends.
  Horizontal spin, pocket overhangs, tipping and falling still keep the simulation active.
- Removed the unused RestSpin cutoff. Updated the old test that demanded spin-only motion
  delay shot completion. Client Match already clears spin in its server reconciliation.

**Verified:** `tools/lint.sh` passes StyLua, Selene and luau-lsp; **92 Lune tests pass**.
The new cases cover known-answer sliding, both spin signs at radii 1.125 and 1.3, rest and
pocket behavior, and all three whole-shot APIs. Existing energy, rail, pocket, determinism,
trace and server-seed replay tests pass. Rojo sync confirmed by reading the new symbol in
Studio before starting a fresh Play session.

Studio server measurements: a 30 in/s stun ball reaches rolling in **0.111003 s** at
**21.428571 in/s**; 60 rad/s side spin reaches zero at step **1322 (5.508333 s)**.
Six full-power maximum-english rack shots finished in **8.008-9.792 s**, none capped, with
zero final side spin. A client Match replay matched the simulation's **3288 steps / 13.70 s**
and cleared spin. These are scripted checks; spin has no player selector until E.

A real desktop power-bar drag at 90% power produced 34 ball hits, 24 rail hits, one pocket
and a **7.48 s** shot. Console clean, no replay drift warning. Native Studio screenshot
shows the settled table and restored aiming visuals; no screenshot/cache added to git.
**Phone and controller playtests are still pending.** Studio's controller emulator reports
Gamepad1 connected, but injected ButtonA did not fire a shot. Native UI automation then
returned `noWindowsAvailable`; do not count detection as a controller playtest.

**Decided for D-F:** one bar reaching 30 mph; Classic predicts the ball's launch direction
including side-spin deflection; regulation physics balls with visual scaling; fixed 4-degree
cue elevation; all collectible cues have identical physics. Current ball radius remains
1.3 in until F. These choices are in the GDD and dated decision log.

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
- Pocket opening and lip tipping share geometry with art. Previous pocket sweeps found no
  stranded overhangs; pocket regressions still pass. Corner leather lining leaves exposed
  blue bed cut-face: cosmetic TableBuilder fix, not a physics change.

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
After reporting A, B is ball-ball friction/throw; preserve the explicit stop after each
milestone. No place assets were edited in A. The standing milestone handoff asks the user
to save `place/8ball.rbxl` and publish; scripts themselves are edited only through Rojo.
