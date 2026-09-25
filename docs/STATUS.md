# Status

**2026-09-25: the remade table and jump shots are signed off by the designer and merged into
main.**

- Both roadmap boxes are ticked. The jump heights and pocket feel stay as tuned.
- The place is saved to `place/8ball.rbxl` and published. The old seven-mesh table is gone
  from the place and the repo.
- Next up: the hub map (Skyline Club, brief in `docs/prompts/`), or the next roadmap box.

---

**2026-09-24 (later): jump shots reviewed by three independent agents, fixed and retuned.**

- **Landing before the foul (designer):** a ball that flies off now skips off the rail if it
  hits it, falls to the floor, bounces and rolls for about a second. Only then does the foul
  card show. The server waits exactly that long.
- **Regression check:** 8,658 ordinary 4-degree shots played exactly as before jump shots
  existed. Object balls never left the cloth.
- **Bugs fixed from the reviews:**
  - A ball rising into a cushion froze in mid-air.
  - Cushions launched flying balls 4-11 ft up.
  - A ball coming down onto a cushion top was teleported.
  - Off-table was wrong at corner pocket mouths.
  - A ball perched on another bounced until the shot timed out.
  - A tiny energy gain on separation.
  - A hard flat shot hopping into a pocket wasn't pocketed, so a scratch became off the
    table.
  - The power bar dipped where the flat hop begins.
- **Speed:** normal shots were 48% slower than before jump shots; now about 6%.
- **Realism:**
  - Jumping a ball over another is realistic. The model now follows Dr. Dave's TP B.10:
    slate bounce 0.6, and a raised cue's top stroke is 12 mph.
  - Full-power jumps rise about 9, 18 and 26 in at 30, 45 and 60 degrees (they were 19,
    41 and 62).
  - At 45 degrees a ball clears a blocker from about 70% power. 60 degrees at full power
    still flies off.
  - Flat full-power shots at a nearby ball send the cue ball off about 5% of the time.

Still required: a real controller, a phone, a two-player check and the designer's feel check.

---

**2026-09-24: jump shots landed (branch `jump-shots`, from `table-remake`). A real
controller, a phone and a two-player check are still to do.**

What was built:
- A cue-angle slider sits beside the white ball in the spin panel. It runs from 4 degrees
  (normal) to 60. Tap or drag the track, or use the up and down arrow keys. On a gamepad,
  hold L1 and push the left stick. The chosen angle shows under the spin button, and it
  resets after every shot, the same as spin.
- A raised cue drives the cue ball into the slate, so it bounces. With the right power it
  jumps a blocking ball. Too much power sends it off the table. The ball carries on to the
  floor, bounces and fades out.
- Rules:
  - A ball off the table is a foul, and the opponent gets ball in hand.
  - An object ball that flies off goes back on the foot spot.
  - The 8 flying off loses the game. On the break, the 8 goes back on its spot instead.
- Very hard flat shots only rarely pop the cue ball, and object balls never leave the cloth.
- The aim line follows a jump. It skips the balls the cue ball clears, puts a small ring
  where it lands, and shows a red cross where it would fly off.
- Other players see your raised cue. A flying ball has a shadow under it, and it knocks
  when it lands.

Verified:
- Lint is clean and all 330 Lune tests pass. They include new tests for flight, bounces,
  clearing a ball, flying off, dropping into a pocket from the air, energy, replay
  checksums, the aim line and the off-table rules.
- Every ordinary 4-degree shot plays exactly as before (the saved test shots are
  unchanged).
- In Studio Play:
  - The slider set 32 degrees from a tap and 34 after two up-arrow presses. The badge
    showed 34.
  - L1 opened the panel.
  - A 60-degree full-power shot flew off: it rose about 61 inches, dropped to the floor and
    faded. The FOUL card read "A ball flew off the table.", followed by ball in hand.
  - A 45-degree jump showed its shadow.
  - The console was clean.

Still required:
- A real controller (L1 + left stick, and the D-pad, which Studio's input tool cannot
  press).
- A phone: tap the slider.
- A two-client check that a watcher sees the raised cue and the flight.
- The designer's feel check on jump heights. The tuning numbers are
  `Config.Physics.SlateRestitution` and `ClothHopLossSpeed`.
- Merge `table-remake`, then `jump-shots`, into main.

---

**2026-09-24: the new table is in Studio (branch `table-remake`). Designer playtest, device
check and the milestone save are pending.**

The table was remade from scratch (ROADMAP "Table remake"):
- One model, styled on the Diamond Pro-Am with no brand, built by a Blender script straight
  from the physics (`assets/table/`). The cushions, jaws and pocket rims sit within 0.004 in of
  where the balls play. The old table's pockets were 15% wider than the physics.
- 7 in rounded rails, chrome caps on all six pockets (removable), two-piece bolted legs,
  corner blocks, 18 pearl sights and a blank logo plate. 8,134 triangles (the old table had
  19,220).
- Two looks on the same mesh: bright blue cloth with satin black wood, and bright green cloth
  with red-brown wood. 17 textures at 1024 are shared by all tables; the cloth is one
  repeating tile tinted per look.
- In Studio the template is `ServerStorage.PoolTable` and its looks are in
  `ServerStorage.TableLooks`. Table 2 is green as a temporary side-by-side showcase; which
  tables use which look is still open.

Verified:
- lint clean and 314 Lune tests pass, including the new geometry, looks and model tests;
- `TableModel.py` passes every check (physics match, gaps, budgets, UVs, FBX round trip);
- in Edit mode, both looks render correctly;
- in Play, the server builds 3 tables (blue, green, blue) with all 8 textured parts; console
  clean.

Still required:
- the designer's playtest (pockets feel, close aim view);
- a phone, PC and gamepad look at the cloth up close;
- save to `place/8ball.rbxl` and publish;
- then merge `table-remake` into main and delete `assets/table/legacy/` and
  `ServerStorage.PoolTableModel`.

---

**2026-09-24: realistic shooter pose landed (rake, cue extension, rail-clearing cue, wind-up,
idle after the shot, everyone sees it). Multi-client and device acceptance pending.**

The shooter now looks like a pool player (modelled on "9 Ball Roulette"):
- The body stands anywhere round the table (never in it) and changes with reach: standing,
  leaning over, a bridge (rake) under the cue, then an automatic cue extension. Both hands
  hold the cue; the head watches the cue ball. R15 and R6.
- The cue is about 7 studs and tilts up over a rail or a ball behind the cue ball (visual
  only; physics stays at 4 degrees).
- Pulling the power draws the cue back for everyone; release plays a quick stroke.
- After the shot the shooter idles on the spot, facing the table. Same shooter: back to
  aiming. Turn passes: normal camera and walking from that spot, no teleport.
- The shooter sees their own body translucent; everyone else sees it fully visible.
- The server places the shooter with the same stance maths, so every screen agrees.

Verified: lint clean and 297 Lune tests pass. In Studio: default R15 and R6 test rigs posed
in Edit mode (hands on the cue and the rake to 0.001 studs, joints closed, body outside the
table, about 0.05 ms per pose), and on one Play client with the real avatar: aim pose and
rake, wind-up from a real mouse drag, stroke, the idle animation on the shot spot facing the
table, solo continuation back to aim, and a 1v1 turn pass releasing the body in place with
the normal camera. Console clean.

Still required for the pose: a two-client check (watcher sees the posed, fully visible body,
the wind-up and the stroke), an R6 avatar in Play, phone and controller. The bridge mesh
(`assets/bridge/BridgeModel.fbx`) still needs importing into ServerStorage; until then a
parts stand-in is used.

---

The current update is [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md), revised after the
designer's first playtest. The baseplate has three blue-cloth tables for shared 1v1, 2v2
and 3v3 matches, on the baseplate. No bots, rewards, saved wins,
difficulty or abilities.

Latest changes:
- Every turn starts in the **home view** (the pre-multiplayer middle framing), and the
  camera pulls out during the shot and returns afterwards.
- The only top-down view is the 8-ball pocket call. Break and ball-in-hand placement
  happen in 3D with no Lock button: drag the ball (it moves instantly) and shoot at any
  time within the 15 s placement window (20 s to aim, 10 s for an 8-ball call).
- The bonus plays for the owning team in the same frame as the drop, including the first
  ball, which assigns groups. The HUD shows who is solids and who is stripes the moment
  that ball drops.
- Pocketed balls get a red X across the whole ball.
- Break and ball-in-hand turns open two zoom notches wider than the home view. Timers:
  15 s to place, 20 s to aim, 10 s to call the 8. Invisible walls keep everyone off the
  tables. Queue slots light up with a light column, sparkles, a rising scan frame and a
  sound when someone steps on one.
- The camera stays pulled out until the next turn starts, then either returns to the home
  view or eases (no cut) back into the player's own camera.
- Breaks now spread properly: touching racked balls push on each other at once
  (Physics/Cluster.luau). Over 200 seeds, 61% of full breaks pocket a ball and about 12
  balls reach a rail. Every game opens on a random rack.

- 2026-09-23 playtest fixes:
  - Solo mode: a Play Solo button when you're alone on a pad. Clear your first group, then
    the other group, then the 8. No clock. A foul gives ball in hand; an early 8 loses.
  - Fixed the permanent cursor lock after a turn.
  - Walking is normal again: physical fences replace the teleport loop.
  - Side spin no longer bends the line or the shot.
  - Your group glows green and the other group is greyed.
  - Balls pocketed while the table is open show next to OPEN TABLE.

Verified: lint clean and 242 Lune tests pass. On one Studio client, the home view pose
was checked numerically, as were the top-down-only pocket call, a real mouse drag with
the camera holding, the drop-frame reveal and bonus, and a red X screenshot. No project
errors or drift warnings. See [MULTIPLAYER_PROGRESS.md](../MULTIPLAYER_PROGRESS.md).

Still required:
- Real full matches in each mode.
- Two-client watcher smoothness.
- A phone (touch) and a physical controller: LT + left stick, held arrows.
- Audio listening.
Known art debt: imported mesh pockets differ slightly from regulation geometry.
