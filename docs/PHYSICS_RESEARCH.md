# Physics realism research (2026-09-22)

Consultant report on making the shot as real as Virtual Pool 4 / ShootersPool. Sources are
Dr. David Alciatore's technical proofs (TP) and FAQ (drdavepoolinfo.com), Marlow, Shepard,
Mathavan et al. 2010, Han 2005, the pooltool library (github.com/ekiefl/pooltool), the VP4
manual (celeris.com/ftp/vp4help.pdf) and ShootersPool's own changelogs. Every number below
was fact-checked by a second pass; where sources disagree the range is given.

## 1. Is it possible on Roblox?

**Yes.** ShootersPool and VP4 are closed source, but both developers say they built on the
same published physics (the ShootersPool author credits Dr. Dave's site, and Dr. Dave called
its physics "very realistic" and lists it as a good simulator). pooltool, which is open
source, has an architecture almost identical to ours: closed-form sliding/rolling/spinning
between events, exact event times, pluggable impulse resolvers. Our engine already has that
skeleton in pure Luau, server-authoritative, with replay-by-seed and a checksum.

What ShootersPool models that we do not: throw and spin transfer (ball-ball friction), squirt
and swerve (off-centre hit with a real cue), angle/speed-dependent restitution, a per-cloth
"rolling accuracy", jumps, and a stick-based power model. None of that needs Roblox physics;
it is all impulse maths inside `src/shared/Physics`.

Two real risks, both manageable:

- **Cross-platform determinism.** Luau's `math.sin/cos/exp/atan2` call the platform C library
  and are not bit-identical across Windows, macOS, iOS, Android and the Linux server. `+ - * /`
  and `math.sqrt` are exact. So: keep clients as replayers that resnap to the server's final
  state (already the design), avoid `exp()` in the friction fit (use a table), and treat the
  checksum as a drift detector, not a guarantee.
- **Cost.** A 16-ball shot at 240 Hz is well within budget; `--!native` is server-only today.

## 2. What the reference sims do

- **VP4** exposes six table knobs (Table Speed, Table Skid, Rail Speed, Rail Grab, Rail Cut,
  Pocket Size), models throw (grows with cut angle and english, shrinks with speed, cancelled
  by gearing outside english), squirt opposite the tip side, swerve, jump, and rail
  compression. No coefficients published.
- **ShootersPool** changelogs confirm: angle-dependent ball-ball restitution, throw and spin
  transfer, a per-cloth rolling-accuracy wander that grows as a ball slows, elevation and
  jumps. No coefficients published. The Ouschan video is a demonstration that a calibrated
  model set up from the real positions reproduces a real multi-rail shot; that is exactly what
  known-answer tests do for us.
- **Pure Pool** is rated below both by serious players (locked camera, ball hops, kicks that
  need wrong aim). Consensus ranking: ShootersPool >= VP4 >> Pure Pool.
- What serious players say makes a sim feel real, in order: tangent line and 30/90 degree
  rules, rail rebound angle vs speed, throw (so inside/outside english matters), squirt,
  realistic draw/follow distances, roll-out distance, and no free spin.

## 3. Parameter table (current vs published vs recommended)

| Quantity | Now | Published | Recommend | Source |
|---|---|---|---|---|
| Ball radius | 1.3 in | 1.125 in +/-0.0025 | **1.125** in physics; scale render only | WPA spec |
| Sliding friction mu_s | 0.25 | 0.15-0.4, typical 0.2 (Mathavan 0.178-0.245) | **0.20** | Dr. Dave properties page |
| Rolling resistance mu_r | 0.012 | 0.005-0.015, typical 0.01 (Mathavan 0.0127) | **0.010**, presets 0.008/0.012/0.015 | TP B.2 |
| Side-spin decel | 32.7 rad/s^2 (from SpinFriction 0.044 and R) | 5-15, typical **10 rad/s^2** | constant 10.9 rad/s^2, R-independent | TP B.2, pooltool |
| Ball-ball COR e_b | 0.93 | 0.92-0.98 (pooltool 0.95, Mathavan fit 0.89) | **0.95** | Dr. Dave, pooltool |
| Ball-ball friction mu_b | none | 0.03-0.08, speed dependent: mu = 0.009951 + 0.108 exp(-1.088 v[m/s]) | that fit as a piecewise-linear table in in/s (exp(-0.02764 v_in)) | TP A.14 |
| Throw cap | none | tangential impulse <= (1/7) m |v_rel,t| (no slip reversal) | implement | TP A.14 |
| Max spin transfer | none | 5/14 of cue-ball spin at gearing | falls out of the model | TP A.27 |
| Cushion nose height | 0.625 D | 0.635 D +/-0.01 | **0.635 D** | WPA |
| Cushion COR e_c | 0.8 constant | 0.6-0.9; measured 0.818 effective for rolling ball 11-138 in/s; Mathavan fit 0.98 with mu 0.14 | 0.85 (pooltool), then speed-dependent | Dr. Dave, Mathavan 2010 |
| Cushion friction f_c | 0.2 | 0.14-0.2 | 0.2 | pooltool, Mathavan |
| Steep-angle speed loss | ~5% (bug, see 4) | about 50% at near-perpendicular | fix model | Dr. Dave cushion FAQ |
| Cue-ball speed, play | bar maps to 15-528 in/s | soft <1 mph, slow 1-2, medium 2-4, fast 4-7, power 7-10 mph | play stroke tops out ~12 mph (211 in/s) | Dr. Dave speed table |
| Cue-ball speed, break | 528 in/s (30 mph) | pro average 24 mph, powerful 25-30, best ~35 | keep 30 mph as break ceiling only | Onoda data, Dr. Dave |
| Cue mass / tip COR | none | 18-21 oz; tip e 0.71-0.75 leather, 0.81-0.87 phenolic | model stick: M = 19 oz, e = 0.73 | TP A.30, HSV B.42 |
| Spin factor | 2.5 rigid | 2.5 rigid; HSV max wR/v = 1.37 at 0.55R | keep 2.5, offset limit 0.5R | TP A.12, HSV A.98-109 |
| Squirt | none | 0.5-2.3 deg at max offset; pivot length 10-50 in; endmass ratio m_r 15-40 | tan(a) = 2.5 (b/R) sqrt(1-(b/R)^2) / (1 + m_r + 2.5(1-(b/R)^2)), m_r = 25 default, per-cue stat | TP A.31, squirt FAQ |
| Corner mouth | 2.0 D | 4.5-4.625 in = 2.0-2.06 D | keep | WPA |
| Corner shelf | 0 | 1-2.25 in | 1.5 in (needs opening moved back) | WPA |

## 4. Gap analysis of the current engine

High impact:

- **Ball-ball is frictionless** (`Simulation.luau` resolveBalls). No throw, no spin transfer,
  no effect of english on the object ball. Replace with the frictional impulse in section 5.
- **No squirt** (`Cue.luau` strike). Side spin has no aiming cost. Real: 1.5-5 deg opposite
  the english, nearly speed independent.
- **Side spin decays 3x too fast**: 32.7 rad/s^2 vs measured ~10. English is gone by the
  second rail. Also `Ball.isMoving` waits for wz to reach 0, so with the correct rate a hard
  english shot would spin in place for 26-46 s and hit MaxShotSeconds. End the shot on
  translation only.
- **Cushion impulse is physically wrong in two ways**: the horizontal normal impulse applied
  above centre produces an unlimited vertical friction torque (the true normal passes through
  the centre; contact is at 15.7 deg above centre so tan = 0.258 > mu), and the friction cone
  bounds only the along-rail component. Result: rolling ball keeps ~95% of speed, stun ball
  ~56%; real is ~50% loss at steep angles and speed-dependent. Replace with Han 2005 as in
  pooltool (section 5). A branch also lets the ball keep moving into the rail when
  backspin nearly cancels the contact velocity.
- **Power bar wastes range**: 42% of the bar is break-only (8-30 mph); the 1-4 mph band that
  most shots live in gets 29%. Spin is free (same speed for any offset; real max offset gives
  ~0.75x). Move to a stick model (section 5) and a separate break stroke.
- **Spin never reaches the server**: `ShotService.validate` ignores `payload.spin`, Lounge.fire
  sends only angle and power, and `math.huge` passes the angle check. Clamp spin to the 0.5R
  disc server-side.
- **Guideline** casts along the raw aim angle (Aim.trace) so it will lie by the squirt angle,
  and its object-ball line has no throw.
- **Super Bounce has no hook**: resolveRail reads Config directly; a server-only override
  would desync replays. Per-shot modifiers must ride in the seed.

Medium/low: SlidingFriction 0.25 vs 0.2 (stun window 20% short), RollingFriction 0.012 vs
0.01, BallRestitution 0.93 vs 0.95 (rack keeps 51% of break energy), straight-break order bias
(the 2 ball is always resolved before the 9: add seeded deterministic rack jitter),
InstantHitSeconds 1e-5 is larger than the rack-gap closing time at break speed (use 1e-7),
RestSpeed 1.0 in/s cuts the last 0.1 in of creep (use 0.25), zero corner shelf,
`Cue.rollOutDistance` ignores spin (max follow runs 2.25x further), sin/cos/asin in the pocket
tip path are libm calls in the replay path.

## 5. The model to implement

Equations in ASCII, unit mass, I = 0.4 R^2. n = unit line of centres, z = up.

**Stick strike** (TP A.30, pooltool): inputs stick speed V, stick mass M, ball mass m,
tip offset (a side, b vertical) in R units, elevation theta, tip COR e.
K = 1 + m/M + 2.5 (a^2 + (b cos th)^2 + (c sin th)^2 - 2 b c cos th sin th), c = sqrt(1-a^2-b^2)
v = 2V / K (elastic) or v = V (1 + sqrt(1 - ((1-eta)/m_r) K)) / K with eta = ((1-m_r e)^2 + m_r(1+e)^2)/(1+m_r)^2
w = (v / (0.4 R^2)) * R * (-c sin th + b cos th, a sin th, -a cos th) in the cue frame, then
rotate into the table frame. Centre hit with 19 oz cue, e = 0.73: v = 1.27-1.35 V.
Squirt: rotate the launch direction by alpha = atan2(2.5 a sqrt(1-a^2), 1 + m_r + 2.5(1-a^2))
away from the tip side, with m_r = ball mass / effective endmass (15 break cue, 25 default,
40 low-deflection). Swerve needs no new code: the tilted spin axis from elevation feeds the
existing sliding integrator.

**Cloth**: unchanged sliding/rolling equations (they are already right). wz decays at a
constant 10.9 rad/s^2 regardless of R.

**Ball-ball** (TP A.5 + A.14 + A.27, pooltool frictional_inelastic):
v_n = (v1 - v2).n; if v_n <= 0 return. J_n = (1+e) v_n / 2; v1 -= J_n n; v2 += J_n n.
v_rel = (v1 - v2) + R (w1 + w2) x n; v_t = v_rel - (v_rel.n) n (retain vertical slip).
J_t = min( mu(|v_t|) J_n, |v_t| / 7 ) opposing v_t. v1 += J_t; v2 -= J_t;
w1 += 2.5 (n x J_t) / R; w2 += 2.5 (n x J_t) / R.
Discard only the resulting vertical translation, as pooltool's 2D resolver does. These
signs and retained vertical torque correct the original summary (verified 2026-09-22).
mu from the TP A.14 fit as a monotone table over |v_t| in in/s (no exp in the replay path).
Expected: 4.11819 deg throw on a half-ball stun hit at 40 in/s with the prompt's table
(mu = 0.072 at 20 in/s slip), 0 with gearing outside english. The 3.43363 deg benchmark
uses fixed mu = 0.06, as in TP A.14's initial example, rather than the speed-dependent fit.

**Cushion** (Han 2005 as in pooltool han_2005): contact angle theta from sin th = 2h/D - 1
(15.7 deg at 0.635 D). Work in the frame (n horizontal into table, t along rail, z up).
Contact velocity at the raised point; normal impulse along the TRUE normal (through the ball
centre, tilted by theta) with restitution e_c; Coulomb friction cone on the full tangential
slip vector with f_c and a stick/slip test; angular impulses from both. Discard the vertical
translational result (ball stays on the cloth). Expect a rolling ball at 45 deg to rebound
shorter than mirror and at about 70% speed; a stun ball perpendicular to keep about 50-60%.
Then make e_c fall with normal speed (e.g. linear from 0.9 at 20 in/s to 0.6 at 300 in/s;
tune against Dr. Dave's "half speed at steep angle").

## 6. Known-answer tests (Lune)

- Stun ball 30 in/s slides t = v/(3.5 mu_s g), reaches 5/7 v, rolls v^2/(2 mu_r g).
- Draw from rest with wy = -50 rad/s: natural roll speed (5 v0 + 2 R w0)/7.
- Max follow at 20 in/s speeds up to 1.071 v.
- wz = 60 rad/s spins down in 60/10.9 = 5.5 s, same step count at R = 1.125 and 1.3.
- Full hit at 100 in/s with e = 0.95: object 97.5, cue 2.5 in/s.
- Half-ball stun hit at 40 in/s, mu 0.06: object leaves at 26.57 deg (3.43 deg throw);
  gearing outside english (wz = V sin30 / R) gives exactly 30.00 deg.
- Rolling full hit transfers backspin 5/14 max; energy never increases over 20k random hits.
- Rolling ball, 45 deg into a rail: rebound angle shorter than 45, speed 0.6-0.8 v; stun
  ball perpendicular keeps 0.5-0.6 v; running english lengthens, reverse shortens.
- Squirt: a = 0.5, m_r = 25: alpha = 2.3 deg; a = 0: 0.
- Stick: centre hit V = 100 in/s, M = 19 oz, e = 0.73: v = 127-135 in/s; a = 0.5 gives ~0.75x.

## 7. Order of work

1. Numbers only: mu_s 0.2, mu_r 0.01, e_b 0.95, wz decel constant 10.9, nose 0.635 D,
   RestSpeed 0.25, InstantHitSeconds 1e-7, shot ends on translation. Half a day, tests first.
2. Ball-ball friction (throw, spin transfer) with the mu table. Guideline keeps geometric
   object line for now.
3. Cushion rewrite (Han 2005), then speed-dependent e_c. Add corner shelf.
4. Stick model + squirt + elevation in the Shot; power bar becomes stick speed with a play
   ceiling and a break stroke. rollOutDistance gets spin.
5. Spin UI (selector, wire, server clamp, renderer already handles w). Guideline uses
   Cue.launchDirection. Per-shot modifier hook for Super Bounce.
6. Regulation ball radius in physics with render scale; seeded rack jitter; scenario harness.

## 8. Questions for the designer

1. Regulation 2.25 in balls in the physics (table plays like a true 9 ft) with bigger
   rendering, or keep 2.6 in (plays like an 8 ft in ball units)?
2. Classic guideline: show the squirt-corrected cue-ball line (easier) or the stick line
   (real-life skill)? Recommend stick line on Difficult/Challenger, corrected on Classic.
3. Power: one bar in stick speed with a play ceiling (~12 mph ball speed) and a separate
   break stroke, or keep one 0-30 mph bar?
4. Cue elevation as a player control now (swerve/masse), or a fixed 4 deg until later?
5. Do cues differ physically (squirt endmass as a catalog stat)?
