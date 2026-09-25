# Status

**2026-09-25 (merged into `main`): the body reaches every shot by pose and position alone,
with both feet planted, the head clear of the table, and both arms reaching along the cue.
Checked in Studio play-solo on R15; the designer's look at this round is next.**

- Poses: standing, leaning further in, stretching over the rail (belly on the edge), kneeling
  on the table, and last kneeling up on the rail top. Both feet stay on the floor in every
  standing pose. Each pose can turn to the cue in seven ways (Config.Stance.Sides), and the
  body is not tied to the cue line.
- Default R15 on an even grid: 48% floor, 4% stretching, 48% kneeling on the table, every
  shot reached. A foot on the floor only reaches about 2.5 studs onto this table.
- The head: AvatarPose.measureBody now measures the neck and the head; the stance places the
  head as the pose looks at the cue ball and keeps it HeadGapStuds above anything under it.
  Natural lean 45 degrees.
- The grip arm reaches back to hold the cue near its butt (a long wind-up slides the cue
  through the hand); the bridge arm reaches out nearly straight toward the ball.
- R6 and smaller bodies cannot reach about 2% of ordinary shots (a ball frozen to a cushion
  under a steep jump cue): they stand with the hands as near the cue as they get.
- Verified: lint clean, 328 Lune tests pass. Studio play-solo (R15, accessories hidden in a
  test camera): the break, a side-rail shot and a kneel look right, feet on the floor, the
  head above the rail, no console errors.
- New: the shooter can walk while the balls roll, about a second after the shot (the shot
  camera keeps following the balls); their next turn poses them again from where they
  walked. Checked in Studio play-solo: released 1 s after the shot, walked to the fence,
  back into the aiming pose on the next turn, no console errors.
- Still required: the designer's look; the walk checked with a watcher client and on a phone
  and a controller; R6 in Studio; a 360-degree aim sweep watched from a
  second client; the climb back down after a kneel (still a cut); phone, PC, gamepad.

---

**2026-09-25 (later): the Skyline Club is in the game. All sixteen tables play in it.**

- Imported and aligned: every mesh is where the package puts it (within 0.0001 studs).
- Textured: 50 SurfaceAppearances with the uploaded maps (ids in `assets/hub/Uploads.json`),
  plus Neon glow, Glass and the Dusk sky.
- Lighting: Realistic style, ClockTime 18.1, neutral ambient, Atmosphere, Bloom and
  ColorCorrection. DepthOfField is off.
- Code:
  - `HubService` builds 277 prop copies, 188 seats (Sit prompt), 30 lights and 78 collision
    boxes from `src/shared/HubLayout.luau`, which is generated from `Markers.json`.
  - `TableService` and the client now run sixteen tables, each seating its zone's size.
  - The match fence is lopsided so the 2v2 tables don't trap each other's players.
  - `HubDecor` hides your own table's pendant while you play.
- Checked in Studio play-solo:
  - spawn on the balcony, then down the stair to the plaza, lounge and terrace;
  - nobody can jump off the terrace;
  - stepping on a pad joins the table;
  - the Sit prompt seats you;
  - no console errors.
- Tests: 336 pass, including the new `hub_layout_test`. Lint is clean.
- Fixed along the way: some hand-built faces faced out of the room, so Roblox hid them.
  - In the place: DoubleSided on the affected meshes.
  - At the source: HubBuilder, plus a validation check.
- Still to do:
  - Set `Lighting.Technology` to **Future** by hand (scripts cannot touch it).
  - Save to `place/8ball.rbxl` and publish.
  - Check on a real phone and a controller: frame rate, readability, the Sit prompt, joining
    a pad.
  - Two players on two tables.
  - Snack counter tools.

---

**2026-09-25: the hub map package (Skyline Club) is built and import-ready in `assets/hub`.
It is not imported into Studio yet (that is roadmap 4.1).**

- Layout: approved by the designer after the stage 1 stop.
  - 1v1 (10 tables) along the north windows, 2v2 (4) in the south-west, 3v3 (2) in the
    north-east.
  - A spawn balcony with a prow and a wide stair into the central plaza crossroads.
  - Bar, lounge, piano stage and terrace in the south-east.
  - Every table, the bar and the terrace door are within a 105-stud walk of the stair
    (limit 128).
- Package:
  - Eight FBX files, `Markers.json` (anchors, tables, pads, 277 prop placements, 188 seats,
    30 lights, collision, mesh settings, sky mapping, Lighting recipe) and textures.
  - Three skyboxes (Dusk, Day, Night).
  - `Validation.md` passes: 182,533 of 200,000 environment triangles, 9 of 12 texture sets,
    FBX round trip exact.
- Renders: `assets/hub/renders/final_*.png`.
- Import steps: `assets/hub/Readme.md`.
- Studio fact found: the Sky face orientation, now in STUDIO_NOTES.
  - The test uploaded 6 small labelled images to the account.
  - The place's own Sky was put back unchanged.
- Next up: roadmap 4.1 in Studio.
  - Import the packages, align them, upload the textures and skyboxes.
  - Place the tables, props, seats and lights from `Markers.json`.
  - Apply the Lighting recipe, then check it on a phone.

---

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
