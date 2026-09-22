# Status

**Last updated:** 2026-09-22. Physics realism A-F implemented. D, E and F were requested in
one run. Code is verified; physical-device and real two-client acceptance remain open.

## Physics realism: current build

- **A-C:** corrected cloth/ball tuning, radius-independent side-spin decay, ball friction,
  throw/spin transfer, Han cushion contacts, normal-speed restitution, and supported corner
  shelves. Pure side spin does not keep a shot open. Details and equations are in DECISIONS.
- **D:** cue impact uses a 19 oz stick, 6 oz ball, tip restitution 0.73 and endmass ratio 25.
  One power bar gives 15-528 in/s for centre hits; maximum stick speed is 406.981692 in/s.
  Off-centre impact trades forward speed for spin. Elevation stays fixed at 4 degrees for
  players; all cue styles have identical physics. Tilted spin feeds the existing cloth
  integrator to produce swerve. Camera rollout includes the ball's current angular velocity.
- **E:** mouse/touch spin selector with full-disc dragging, Center and Done. The 80 px ball
  toggle sits at the left middle; the selector has 10% dimming, no panel/title/hint/arrows,
  and outside clicks close it while retaining spin. The whole disc maps to the existing
  0.5R physics limit, with the dot kept inside its edge. Both red markers use the left
  toggle's 17.6 px diameter, as requested after the proportional selector dot was too large. Gamepad:
  hold L1 + right stick, Y to center, release L1 to keep the choice. Spin resets after a shot
  or rack/seat change, moves the 3D cue tip and updates the launch guideline. Modal input
  blocks aim, zoom and shooting, including old cancelled pulls. HUD copy lives in Strings.
  The actual server uses the tested ShotInput validator and seed quantizer, rejecting
  malformed/non-finite inputs and alternate elevation, and clamping spin to the 0.5R disc.
  Per-shot material overrides copy through simulation/replay and clear afterward. SuperBounce
  is development hook data only; live ability requests are denied pending authorization.
- **F:** regulation radius **1.125 in**, cosmetic RenderScale **1.08** (2.43 in mesh diameter).
  Physics never reads render scale. Shelf is **1.5 in**, cushion nose **1.42875 in**, corner/
  side mouths **4.5/4.95 in**. Rack jitter is deterministic xorshift32, +/-0.001 in per axis
  on 14 balls; cue and apex spots stay exact. Seed and exact starting positions travel in
  TableState. The Studio B-key reset now runs on the server and advances the seed, fixing
  its former local-only desync. A reset received during replay queues until it finishes.
  Named follow, draw and side-cut fixtures provide a reusable Lune scenario harness with
  0.02 in position tolerances. These are synthetic regression cases, not measured real shots.

**The current imported table is retained**, as the designer requested. Its mesh does not
rebuild from Config, so its visible pockets/cushion nose still differ from the new physics.
That art update is deferred. No place assets changed in A-F.

Classic predicts the cue ball's **initial launch direction including squirt**. It remains a
straight aid: later swerve can change a distant contact. Object-ball direction stays geometric
and the cue's outgoing stub stays tangent; no post-contact curved preview is claimed.

## Verification

**132 Lune tests pass**, with StyLua, Selene and luau-lsp clean. Coverage includes energy,
contact symmetry, heavy draw, spin-disc bounds, invalid wire requests, exact same-machine
seed replay, per-shot material reset, legal seeded racks, pockets and named scenarios.

Useful measured answers:
- Stick 100 in/s: centre **129.735566 in/s** at 4 degrees (**131.48** level); maximum side
  **79.541985**, correcting the prompt's approximate 0.75 speed ratio to **0.613109**.
- Maximum side squirt **2.223977 degrees**. Studio slow english curves to **0.234541 degrees**
  after 0.25 s. A 20 in/s maximum-follow ball runs **54.909259 in** at 4 degrees, or
  **59.849110 in** level, correcting the original approximate rollout target.
- Rolling 100 in/s at 45 degrees banks at **43.863807 degrees**, keeping **76.397643%** speed.
  Perpendicular stun keeps **50.418857%** at 300 in/s, **70.285286%** at 100 in/s.
- The 96-break seed study moved **11-15 balls** beyond a diameter, mean **13.395833**;
  **23-33** ball contacts each, no emergency stops or duration caps. The old universal
  13-moved assertion was too strict for jittered regulation racks. Acceptance now keeps all
  contact/overlap/containment guards, requires at least 10 moved and 20 contacts each, and
  a 13-ball mean across the fixed 32-seed x 3-angle ensemble. No physics/seed was tuned to it.

Rojo was confirmed before fresh Studio runs. Actual desktop checks:
- Selector drag sent side spin (seed wz **89.957759 rad/s**), then reset to centre. That
  shot finished in **5.52 s**, 36 ball contacts, 4 rails and one pocket, with no drift.
- Regulation-size seeded break: **8.02 s**, 25 ball contacts, 22 rails, no pockets; clean
  console/no drift. Runtime mesh diameter **2.43 in**; physics diameter **2.25 in**.
- Server rack seed **2**, then rerack **3**, matched all 16 displayed balls within
  **0.000006 in** of transmitted positions (world-render rounding).
- Two independent actual Match replays matched the server checksum **1836635184** before
  reconciliation. A rack reset queued during replay was applied afterward. This exercises
  the real client module on one machine; it is not a Start Server + 2 Players test.
- Scripted gamepad handling reaches diagonal spin (+0.353553,+0.353553), resets with Y,
  closes with L1 release and emits no zoom. A cancelled pull fires zero shots; the next
  deliberate pull fires once. HUD layouts fit 320x568 and 568x262; action targets stay 44 px.
  Native screenshots captured the selector and gameplay.
- Selector simplification: desktop dragging reaches the edge and stays open when dragged
  beyond it; Center resets, Done closes, and outside clicks (including transparent padding
  and over the power bar) close without firing. Fixed a duplicate top-bar inset subtraction
  that shifted pointer placement upward. Updated 320x568 and 568x262 layout checks pass;
  console and lint are clean, and all 132 Lune tests still pass.
- Larger strike marker: desktop edge dragging and 320x568/568x262 layouts retain full spin
  without clipping. Native screenshot and clean console confirmed; lint and 132 tests pass.

**Phone/controller hands-on acceptance remains deferred at the designer's request to move
on.** Scripted input/layout checks do not replace those or a real two-client session. Roadmap
1.6 stays unticked until those acceptance checks pass.

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

Try the selector's top, bottom and side offsets on PC/phone, then L1 + right stick and Y on a
real controller. Check follow, draw, cushion english, selector reset and normal zoom after
closing. In Studio, Start Server + 2 Players should show both clients agreeing after spin
shots and a new rack; watch for replay-drift warnings. The imported-table art update remains
deferred. Save `place/8ball.rbxl` and publish in Studio for the live place; no assets were
edited during this physics pass.
