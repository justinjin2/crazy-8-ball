# Status

**2026-09-22: multiplayer playtest fixes landed; real multiplayer/device acceptance pending.**

The current update is [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md), revised after the
designer's first playtest. The baseplate has three blue-cloth tables for shared 1v1, 2v2
and 3v3 matches, and the stored lounge stays disabled. No bots, rewards, saved wins,
difficulty or abilities.

Latest changes:
- Every turn starts in the **home view** (the pre-multiplayer middle framing), and the
  camera pulls out during the shot and returns afterwards.
- The only top-down view is the 8-ball pocket call. Break and ball-in-hand placement
  happen in 3D with no Lock button: drag the ball (it moves instantly) and shoot at any
  time within the 10 s.
- The bonus plays for the owning team in the same frame as the drop, including the first
  ball, which assigns groups. The HUD shows who is solids and who is stripes the moment
  that ball drops.
- Pocketed balls get a red X across the whole ball.
- The camera stays pulled out until the next turn starts, then either returns to the home
  view or eases (no cut) back into the player's own camera.
- Breaks now spread properly: touching racked balls push on each other at once
  (Physics/Cluster.luau). Over 200 seeds, 61% of full breaks pocket a ball and about 12
  balls reach a rail. Every game opens on a random rack.

Verified: lint clean and 232 Lune tests pass. On one Studio client, the home view pose
was checked numerically, as were the top-down-only pocket call, a real mouse drag with
the camera holding, the drop-frame reveal and bonus, and a red X screenshot. No project
errors or drift warnings. See [MULTIPLAYER_PROGRESS.md](../MULTIPLAYER_PROGRESS.md).

Still required:
- Real full matches in each mode.
- Two-client watcher smoothness.
- A phone (touch) and a physical controller: LT + left stick, held arrows.
- Audio listening.
Known art debt: imported mesh pockets differ slightly from regulation geometry.
