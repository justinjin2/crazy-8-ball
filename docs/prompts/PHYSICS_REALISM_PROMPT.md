# Paste this into Claude Code CLI, run from ~/Desktop/8ball

Build the realistic physics and spin system for Crazy 8 Ball. Read `CLAUDE.md`,
`docs/STATUS.md` and `docs/PHYSICS_RESEARCH.md` first (the research doc has the parameter
table in section 3, the gap list in section 4, the equations in section 5 and the tests in
section 6). Plan in plan mode before editing. Work one milestone at a time, in the order
below. Designer update: continue through D-F in one run, reporting progress and committing
verified steps along the way.

Rules that must hold: physics stays pure Luau in `src/shared/Physics` (no Roblox types, no
`math.random`, no `os.clock`, no hash-order iteration, no `exp()` in the replay path);
inches, seconds, radians; every number in `src/shared/Config.luau` with a comment naming its
source and range; tests in Lune via `tools/test.sh`, lint via `tools/lint.sh`; existing tests
must keep passing (energy never increases, rail mirror, trace matches simulation,
determinism, shot authority); commit each verified step without asking; every input works on
phone, PC and gamepad. Where a line says ASK THE DESIGNER, stop and ask before building it.

## Milestone A: correct the numbers (Config only plus two small code changes)

Files: `src/shared/Config.luau`, `src/shared/Physics/Simulation.luau`,
`src/shared/Physics/Ball.luau`, `tests/physics_motion_test.luau`.
- SlidingFriction 0.25 -> 0.20; RollingFriction 0.012 -> 0.010 and add
  `ClothPresets = {slow=0.015, medium=0.012, fast=0.008}`; BallRestitution 0.93 -> 0.95;
  CushionNoseBallFraction 0.625 -> 0.635; RestSpeed 1.0 -> 0.25; InstantHitSeconds 1e-5 -> 1e-7.
- Replace SpinFriction with `SideSpinDecel = 10.9` rad/s^2 applied directly:
  `wz -= sign(wz) * min(|wz|, SideSpinDecel * h)`. It must not scale with ball radius.
- `Ball.isMoving` and `Simulation.isAtRest`: a ball that only spins in place (wz ~= 0, no
  translation, not sliding) is at rest for shot-end purposes; zero its wz when the shot ends.
Tests (known answers): stun ball 30 in/s slides for 30/(3.5*0.2*386.09) s and rolls at 5/7 v;
wz = 60 spins down in 5.5 s with the same step count at R = 1.125 and R = 1.3; a
max-english shot ends within MaxShotSeconds. Done means: all tests pass, a shot with side
spin does not hang at the end.

## Milestone B: ball-ball friction (throw and spin transfer)

Files: `src/shared/Physics/Simulation.luau` (resolveBalls), `src/shared/Config.luau`,
`tests/physics_collision_test.luau`.
Correction verified 2026-09-22 against TP A.14 and pooltool's 2D resolver: keep vertical
contact slip/impulse for torque; discard only the resulting vertical translation. Removing
vertical slip would prevent the required rolling-to-backspin transfer. The supplied friction
table gives 4.11819 deg throw at the specified stun hit; 3.43363 deg uses fixed mu = 0.06.
Implement, with unit mass and I = 0.4 R^2, n = unit(b - a):
```
vn = (va - vb).n ; if vn <= 0 return
Jn = (1+e)/2 * vn ; va -= Jn n ; vb += Jn n
vrel = (va - vb) + R*(wa + wb) x n ; vt = vrel - (vrel.n) n
mu = BallFriction(|vt|)   -- Config table, piecewise linear over in/s:
     points from 0.009951 + 0.108*exp(-0.02764*v): v=0:0.118, 20:0.072, 40:0.046, 80:0.022, 120:0.014, 200:0.010
Jt = min(mu*Jn, |vt|/7) * (-unit(vt))     -- zero if |vt| < 1e-9
va += Jt ; vb -= Jt ; wa += 2.5*(n x Jt)/R ; wb += 2.5*(n x Jt)/R
va.z = 0 ; vb.z = 0   -- planar translation, full angular impulse retained
```
Config: `BallFrictionTable`, `BallRestitution = 0.95`. Keep event speed = vn.
Tests: full hit 100 in/s gives object 97.5, cue 2.5; half-ball stun hit at 40 in/s leaves the
object at 25.88181 deg (4.11819 deg throw) with the table; a separate fixed-mu = 0.06
benchmark gives 26.56637 deg (3.43363 deg throw); the same with gearing outside english
wz = 40*sin(30deg)/R gives exactly 30.00 deg; a rolling full hit gives the object backspin and
never more than 5/14 of the cue ball's spin; 20,000 random pairs never gain energy; the
break test still passes and no ball is stopped by the wedge or budget paths.
Done means: a slow cut visibly throws the object ball; english on the cue ball changes it.

## Milestone C: cushion rewrite (Han 2005) and speed-dependent restitution

Files: `src/shared/Physics/Simulation.luau` (resolveRail), `src/shared/Config.luau`,
`src/shared/Physics/Table.luau` (corner shelf), `tests/physics_collision_test.luau`,
`tests/physics_pocket_test.luau`.
Port pooltool's `han_2005` resolver (read
https://raw.githubusercontent.com/ekiefl/pooltool/main/pooltool/physics/resolve/ball_cushion/han_2005/__init__.py
and its blog derivation; the implementation is now in sibling `model.py`): contact angle
`sin(theta) = 2h/D - 1`; the normal impulse acts along
the tilted TRUE normal through the ball centre with restitution e_c; Coulomb friction with
f_c on the full tangential slip vector at the contact point with a stick/slip test; angular
impulses from the full contact (the true normal's torque cancels); discard the vertical
translational result. Guarantee the ball leaves
moving away from the rail in every branch. Config: `RailRestitution = 0.85`,
`RailFriction = 0.2`, then `RailRestitutionBySpeed` (piecewise linear, e.g. 0.9 at 20 in/s
to 0.6 at 300 in/s, tuned so a near-perpendicular ball loses about half its speed). Move the
corner opening back by `CornerShelfInches = 1.5` (scaled by ball diameter) and re-run the
pocket tests. resolveRail takes e and mu as arguments (needed by Milestone E).
Tests: rolling ball 100 in/s at 45 deg rebounds at a shorter angle than 45 and keeps 0.6-0.8
of its speed; stun ball perpendicular at 300 in/s keeps 0.5-0.6 (at 100 in/s this curve
gives 0.70285); running english lengthens and speeds
the rebound, reverse shortens and slows it; heavy backspin into the rail never keeps a
component into the rail; energy never increases. Done means: a bank at speed goes short, a
soft bank runs long, visibly.

## Milestone D: the cue stick, squirt and elevation

Files: `src/shared/Physics/Cue.luau`, `src/shared/Config.luau`, `src/shared/Physics/Aim.luau`,
`tests/physics_aim_test.luau`, new `tests/physics_cue_test.luau`.
- Shot becomes `{angle, power, spin = {x, y}, elevation?}` with spin in ball radii clamped to
  the 0.5 R disc; elevation defaults to `Config.Cue.CueElevationDegrees` (4).
- Power maps to STICK speed V, not ball speed. Config: `StickMassOunces = 19`,
  existing `Balls.MassOunces = 6`, `TipRestitution = 0.73`, `MaxStickSpeed` so that a centre
  hit gives 30 mph (528 in/s) at full bar. Designer chose one bar, with finer low-power
  control and no separate break button. All collectible cues remain physically identical.
- Strike (TP A.30 / pooltool): K = 1 + m/M + 2.5(a^2 + (b cos th)^2 + (c sin th)^2 - 2bc cos th sin th),
  c = sqrt(1 - a^2 - b^2); eta = ((1 - m_r e)^2 + m_r(1+e)^2)/(1+m_r)^2 with m_r = m/M;
  v = V (1 + sqrt(1 - ((1-eta)/m_r) K)) / K; w = (v/(0.4 R^2)) * R * (-c sin th + b cos th, a sin th, -a cos th)
  in the cue frame, rotated into the table frame. Horizontal ball speed is v cos th.
- Squirt: `Cue.launchDirection(shot)` rotates the aim by
  alpha = atan2(2.5 a sqrt(1-a^2), 1 + m_r + 2.5(1-a^2)) away from the tip side, with
  `Config.Cue.EndmassRatio = 25` (per-cue stat later: 15 break, 40 low-deflection).
  `Aim.trace` must cast along `Cue.launchDirection`, so guideline and shot agree.
  Designer chose the predicted launch line for Classic. Elevation stays fixed at 4 degrees
  for player inputs; no elevation control is required.
- Swerve needs no new integrator code: the tilted spin axis feeds the existing sliding phase.
- `Cue.rollOutDistance(speed, wx, wy)` takes launch-local initial spin. Straight follow
  is exact; curved/reversing sliding paths use a conservative travel bound.
Tests: centre hit V = 100 gives horizontal v = 129.735566 at 4 degrees (131.48 level);
a = 0.5 gives 79.541985 in/s with the stated inelastic equation, about 0.61311x centre
speed rather than the original 0.75 estimate. Squirt is 2.223977 deg at a = 0.5 with
EndmassRatio = 25, and 0 at a = 0. Trace follows that launch ray; later swerve can change
a distant contact. Test near contacts with side spin. At the current rolling friction 0.010,
a level maximum-follow ball at 20 in/s runs 59.84911 in, rather than the original 50 estimate.
Done means: side spin visibly deflects the cue ball and slow english curves back.

## Milestone E: spin on the wire, the selector, and the ability hook

Files: `src/client/Input.luau`, `src/client/UI.luau`, `src/client/Hub.luau`,
`src/client/Main.client.luau`, `src/shared/Net.luau`, `src/server/ShotService.luau`,
`src/client/Match.luau`, `src/client/Guideline.luau`, `tests/shot_authority_test.luau`.
- Spin selector: tap/click the cue-ball icon, drag the strike point, reset to centre after
  each shot; gamepad: hold a modifier and use the right stick. Draw the tip offset on the
  3D cue. Player text goes in the shared strings module.
- Wire: `{tableId, angle, power, spin = {x, y}, elevation}`; `ShotService.validate` rejects
  non-finite values (including math.huge) and clamps spin to the 0.5 R disc server-side;
  the quantised seed already carries wx/wy/wz, so assert in shot_authority_test that spin
  {0.5,0}, {0,0.45}, {-0.3,-0.4} round-trips and the client replay matches the server.
- Per-shot modifiers: `State.overrides` (rail e and mu, later others) set by
  `Simulation.strike` from `shot.ability`, validated server-side, carried in ShotResult, applied
  in Match.replay and cleared at the end, so Super Bounce replays identically on every client.
- Guideline: object-ball line stays geometric on Classic; cue-ball stub curves for follow and
  draw (tangent then the 30-degree-rule curve) if cheap, otherwise leave the tangent and note it.
Done means: top spin follows through, back spin draws back, side spin bends the rail rebound,
visibly, on phone, PC and gamepad, and two clients replay the same result.

## Milestone F: regulation scale and the harness

- Designer chose `Balls.RadiusInches = 1.125` with a render scale factor so balls still read well;
  every R-dependent number is expressed physically (nose height, shelf, mouths in diameters).
- Seeded deterministic rack jitter (`Rack.GapInches` plus a tiny per-ball offset from a seed
  in the replicated rack) to remove the straight-break order bias.
- A scenario harness: a Lune test that loads a named layout plus shot and asserts final
  positions within a tolerance, so known real shots accumulate as regression data.

## Reporting after each milestone

Say plainly what was built, which tests prove it (with the numbers), what was playtested in
Studio and what to try by hand. Update `docs/STATUS.md`, tick `docs/ROADMAP.md` 1.6 when
Milestone E is done, and add dated lines to `docs/DECISIONS.md` for every number changed.
