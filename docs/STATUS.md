# Status

**2026-09-26: the rooftop map, Stage 5 of 8 done (the mid backdrop: the skyline and the
near islands).**

- **Built:**
  - `assets/map/gen_backdrop.py` with two modules:
    - the city from 450 to 2,300 studs: 1,054 low-poly buildings stepping up with
      distance, five landmark towers, tree lawns;
    - eight jungle islands with turquoise shallows.
  - 57,199 triangles (cap 110,000).
  - Phones draw nothing that far, so everything beyond is painted into the sky next
    (DECISIONS).
- **Verified:**
  - In Studio the count matches Blender.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds; what they left is in Spec section 9.
- **Next:** Stage 6, the far horizon painted into the skybox, then Checkpoint C (the city
  side, the ocean side and the high view, for the designer).

---

**Earlier on 2026-09-26: the rooftop map, Stage 4 of 8 done (the near world, the sea and the
day sky).**

- **Built:**
  - A day sky rendered in Blender (`assets/map/gen_sky.py`): a blue gradient with small
    cartoon cumulus low on the horizon.
  - A calm, bright blue sea out to 8,000 studs.
  - The near world 300 studs below the roof (`assets/map/gen_near.py`, 9,451 triangles):
    - the tower's walls and lobby;
    - streets and a park;
    - 23 neighbour buildings;
    - a promenade and a beach that curves round the tower's corner, with palm clumps and a
      turquoise band of shallows;
    - three sailboats drifting slowly (`MapMotion`, `MapAmbience`; the same for every
      player).
  - The coast moved out to fit the beach (DECISIONS).
- **Verified:**
  - In Studio, 9,525 triangles including the boats (cap 50,000) and 11 MeshParts.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds (the cap); what they left is carried to Stages 5 to 7 in Spec
    section 9.
- **Waiting:** a Near.fbx re-import for the shallows' corner fix, which goes in with Stage 5's
  import.
- **Next:** Stage 5, the mid backdrop (the real skyline and islands).

---

**2026-09-26: the rank badges are drawn (not in the game yet).**

- **What:** 47 badges in `assets/ui/ranks/`: Unranked, Bronze I to Grandmaster V (stars up to
  Diamond, gems from Expert, crowns from Expert that grow each tier), and Reyes. Redrawn the
  same day so each tier is its own badge like the designer's reference sheet, then: Diamond
  cyan, Grandmaster black and gold, Reyes rainbow, and bold outlined pips on the ring's bottom
  edge (no tray). Each has a
  white shine mask for the light sweep, plus a sparkle image. Made by
  `tools/gen_rank_badges.py`; look and shine in `docs/UI_STYLE.md` sections 6 and 7.
- **Verified:** every badge rendered and checked on a contact sheet and at full size (none
  touches the image edge; the generator warns if one does); `preview.html` shows the sweep,
  the sparkles and Reyes' gold rays running.
- **Still to do (later, after the map work in Studio):** upload the 95 images, add the ids and
  shine timings to Config, and build the badge and its shine in the UI kit (steps in
  `assets/ui/ranks/README.md`).

---

**2026-09-26 (latest): the queue pad is a rectangle again, and the floating sign floats over it
instead of sinking into the floor.**

- **Pad:** a white rounded rectangle with a glowing rim, lying along the table's long side
  toward the entrance, 10, 14 or 18 studs long for 1v1, 2v2 and 3v3. The mode and STEP IN or
  the count read along it from the entrance; rounded outlines pulse out of it and the arrow
  bobs over it while it has room.
- **Sign fix:** the sign's height is measured in the pad's own axes, and the round pad was a
  cylinder lying on its side, so the sign went sideways into the floor. The rectangle lies
  level, so the sign sits 6.5 studs above it.
- **Verified:**
  - Lint is clean and the placement tests pass. `tests/map_layout_test` fails for now (3
    tests) until the rooftop session regenerates `assets/map/Layout.json` for the new pad
    size.
  - Studio Play on the rooftop gray-box:
    - the sign over a 1v1 pad at head height;
    - the pad from above ("1v1 / STEP IN", upright from the entrance);
    - stepping on: the host menu in about 0.1 s, the rim green, "1/2", the sign hidden;
    - a 2v2 sign and the 3v3 pads from above;
    - a clean console.

**Earlier on 2026-09-26: every table plays one mode again, with one glowing queue pad each,
and each mode has its own look.**

- **Tables:**
  - Ten 1v1, four 2v2 and two 3v3; the 1v1 tables at the front, the 2v2 together in the
    back-left corner and the 3v3 in the back-right corner.
  - The left two columns have wood frames (the regular lobby's looks: green 1v1, raspberry
    red 2v2, slate charcoal 3v3); the right two have black frames (the pro lobby's: blue 1v1,
    the same red and charcoal). Every combination is on the baseplate for testing.
- **Queue pad:**
  - One pad per table (now a rectangle, above), sized by mode, with the mode written big on
    it and STEP IN or the count.
  - While it has room, rings pulse out of it and a big arrow bobs over it. Its rim is blue,
    green once somebody is on, gold when full or playing.
  - Stepping on is instant: the host menu shows the same frame, before the server has seated
    you (0.03 s measured in Studio, 0.42 s before).
- **Menu:**
  - Start needs the pad full ("Need 3 more players" until then).
  - Teams go by arrival, alternately, the host team A.
  - Solo and Play against PC only on 1v1 tables.
  - The table sign's title is the table's mode.
- **Verified:**
  - Lint is clean and 332 Lune tests pass. The rewritten tests cover a full pad, teams by
    arrival, start needs a full pad, solo only on 1v1, and every mode in every look on the
    grid.
  - Studio (phone emulator):
    - prepareImport built six looks, with the template check clean;
    - the grid and pads from above;
    - close-ups of the red and charcoal felts with a full rack (every ball, the 8 included,
      clearly visible);
    - joining a 1v1, a 2v2 and a 3v3 pad (the menu, counts and messages; stepping off closes
      it);
    - fixtures filling the 2v2 and 3v3 with teams alternating;
    - a clean console.
- **For the designer:**
  - In play the raspberry reads quite pink and the charcoal a slate grey. A redder or darker
    felt costs contrast with the maroon balls and the 8; it's one Config number each.
- **Still to do:**
  - Save the place (ServerStorage.TableLooks now holds six looks) and publish.
  - A real phone and controller, and real two- and four-player games.

---

**2026-09-26 (latest): the status card and the host menu, round three (designer's playtest).**

- **Status card:** one line ("YOUR TURN", "THEIR TURN", "ALLY'S TURN", "FOUL!", "ROLLING",
  "COIN FLIP", "GAME OVER"), a bigger clock, and Leave as a small red door (still a 44 px touch
  area). It no longer overlaps the words.
- **Portraits:** no names under them (a rank badge comes later). A player who left gets a red X.
- **Host menu:**
  - One column on the right again, short enough to fit a phone (94% size in the 750x361
    emulator), beside the jump button.
  - Leave is a small red door beside Start.
  - Under each difficulty: a cash icon and 1x, 1.5x or 2x money (Config.Difficulty; the new
    Money icon).
  - Shorter description and messages; no DIFFICULTY heading or "Start alone" hint.
- **Fixed on the way:** the OPEN TABLE label would have errored once balls were down on an
  open table (it asked for a size that no longer existed); caught by an Edit preview.
- **Verified:**
  - Lint is clean and 332 Lune tests pass.
  - Studio Play in the phone emulator: the host menu, a 1v1 bar with "YOUR TURN" and "THEIR
    TURN" fitting beside the clock and the door, and a clean console.
  - Edit-preview numbers for solo, 1v1, 3v3 and an open table at 1280x720, 1920x1080 and
    667x375: every bar on one line, the status words inside their space (a 3v3 on the
    smallest phone shrinks them a little).
- **Still to do:** the designer's look on a PC window, a real phone and controller, and a
  two-player match.

---

**2026-09-26 (latest): the UI redo's second round, from the designer's playtest: phone
layout fixed, Fine controls removed, smaller PC GUI, clearer small text.**

- **Phones:**
  - The top bar sits in Roblox's top row beside its menu, chat and voice buttons (solo and
    1v1; a 2v2 or 3v3 sits just under them on one line).
  - With the table no longer half covered, the camera stops backing away, and the power bar
    starts near the top.
  - The host menu shows its two columns side by side, bigger, and fits on the screen.
- **Everywhere:**
  - Fine controls are gone. The project rule is now "every control works by touch, mouse and
    gamepad" (CLAUDE.md, GDD).
  - Small text (descriptions, notes, the detail line) is dark with no outline.
  - The PC GUI is about 80% of its old size.
  - The ball-in-hand ring is plain blue.
  - The table sign shows abilities ON or OFF.
  - The host menu lists Play against PC first, with no SOON tag. Until bots exist, the button
    does nothing.
  - The extra notes are gone, and the difficulty descriptions are the designer's own words.
- **Verified:**
  - Lint is clean and 332 Lune tests pass.
  - Studio Play in the phone emulator (750x361): the host menu, the table sign with its
    abilities pill, 1v1 and solo bars beside Roblox's buttons, the power bar with its PULL
    label, no Fine controls, and a clean console.
  - Edit previews (numbers) of the solo, 1v1 and 3v3 bars at 1280x720, 1920x1080, 750x361 and
    667x375: every mode on one line.
- **Still to do:** the designer's look on a PC window (Studio is set to the phone emulator), a
  real phone and controller, and a two-player match.

---

**2026-09-25 (latest): every screen is redone in the new cartoony style: white inked cards, a
faint pool-ball pattern, candy buttons, Fredoka One and glossy icons. The table sign only
shows when you walk right up to a table.**

- **Top bar:** the reference match bar on white. Portraits with the clock running round the
  shooter; glossy balls with a thick ink ring (stripes no longer melt into the white), grey
  with a red X once down. The status card has a phase icon (a cue on your turn, an hourglass
  on theirs, a glove, a target, a whistle, a coin, a trophy), the clock pill and a red Leave.
  Your turn makes the cue pop and a shine sweep the card. Phones get a compact bar: a 3v3
  fits on one line and Leave is the door icon.
- **Foul popup:** no panel. A whistle, a big red FOUL! and a few plain words ("Scratched the
  white ball"), gone after 3 s (it was an 8 s card).
- **Queue area:**
  - The host menu has a crown, a people count, and difficulty tiles with aim-line pictures (the
    chosen one blue; a guest sees the others faded). The ON toggle is green and Start breathes
    once it can be pressed; the menu pops in and out.
  - The floor box is white and inked with a people icon.
  - The sign over a table now pops in only within 6 studs of that table, one at a time, and
    hides while you are in a box or playing. The server no longer builds sixteen billboards.
- **Also restyled:** the coin flip, win (trophy over turning rays) and lose cards, the leave and
  surrender dialog, fine controls, the ball-in-hand hint and ring, the wrong-target warning,
  the pocket targets, the power bar (fill runs green to red) and the spin panel.
- **How:** a UI kit (`HudParts`, `UIAnim`, `Config.UI.Kit`) and 25 icons plus effect images
  drawn by `tools/gen_ui_art.py`, uploaded to Roblox. Choices: DECISIONS.md and UI_STYLE.md.
- **Verified:**
  - Lint is clean and 332 Lune tests pass (new: the nearest-table check).
  - Studio Edit previews at 1920x1080 and at 844x390 and 667x375 phone sizes: solo, 1v1 and
    3v3 bars, open table, the foul popup, coin, win, lose, the leave dialog, fine controls,
    and the host menu (host, alone, solo choices, four uneven, four even, guest).
  - Studio Play: a 1v1 top bar, the foul popup, placement, the pocket call, the spin panel,
    the power bar, the sign popping in near a table and hiding in the box, the green team
    halves with four in, and gamepad Y putting the selection on Start. The console is clean.
- **Still to do:**
  - The designer's look.
  - A real phone and controller.
  - A two-player match.
  - B on a gamepad: Studio's input tool cannot press it; the code is unchanged.
  - Uploaded images need Roblox moderation before other players see them.
  - The place save and publish from the earlier rounds.

---

**2026-09-25 (latest): one queue box per table, a host menu with three difficulties, and no
countdown. Any of the sixteen tables plays 1v1, 2v2 or 3v3.**

- Every table has one long box along its right side (as you walk in from the spawn) for up to
  six. The first in hosts. Everyone in the box sees the queue menu (top right): the host's
  name, players n/6, difficulty (Classic, Difficult, Challenger), abilities on/off (does
  nothing yet) and, for the host, Start.
- Start: two play at once (straight to the coin flip); four or six must split evenly between
  the box's two halves, which show grey and turn green when even; three or five are greyed
  out with "Need 2, 4 or 6 players". Alone: Play solo, or Play against PC ("Coming soon").
- Difficulty (Config.Difficulty): Classic every line; Difficult the aim line and ring only;
  Challenger no lines. The group glow and red X stay.
- The grid moved to 26 studs apart across to fit the boxes. Gamepad: Y puts the selection on
  the menu, B takes it off. On touch screens the card sits left of the jump button.
- Also fixed: the "INVALID FIRST TARGET" warning was stuck in the top left of every match, and
  held placement arrows and the surrender-vote count had stopped updating (a block of
  MatchHUD.update was lost on 2026-09-23; restored).
- Verified: lint clean, 331 Lune tests pass. Studio play-solo: the boxes and floor words,
  joining, host menu, the difficulty and abilities choices reaching the server, Play solo in
  each difficulty (lines checked per level), Play against PC's notice, the guest's read-only
  menu, 3 players greyed, 4 uneven (grey halves) then even (green), Start into a 2v2 coin
  flip, L and walking out leaving. Fake players came from the Studio QA fixture.
- Still to do: a real two-player check (Studio's Clients and Servers), and the menu on a real
  phone and gamepad. Save the place to `place/8ball.rbxl` and publish (from the map removal);
  check `Lighting.Technology`.

---

**2026-09-25: back on a plain baseplate with sixteen 1v1 tables, eight green and
eight blue. The test hub map is removed from the game and the repo.**

- The map's code, package, brief, tests and notes are gone; the hub map's look is Open again
  (GDD section 10), for the designer to come back to.
- Config.Hub.Tables is a four by four grid, 20 studs across and 43 along; every table is 1v1.
  The left two columns are green cloth with wood, the right two blue cloth with black wood
  (Config.TableModel.LookByTable). The spawn is in front of the grid, facing it.
- In the place (through Studio MCP, Edit mode): `workspace.Hub` and its prop library are
  deleted; the Baseplate (512 by 512, top at y 0, grid texture), the visible 12 by 12 spawn pad
  and the lighting are back as they were in `place/8ball.rbxl` before the map (Soft, 14:30,
  Brightness 3, a default Sky, Bloom, ColorCorrection and DepthOfField off).
  `ServerStorage.BridgeModel`, a leftover of the removed rake, is still in the place.
- Verified: lint clean, 327 Lune tests pass (the grid, the looks and the fences are tested).
  Studio play-solo: 16 tables built, 8 of each look, 2 pads each, the spawn in front, a solo
  game on a blue table, no console errors.
- Still to do: save the place to `place/8ball.rbxl` and publish; check `Lighting.Technology`
  (scripts cannot read it; before the map it was ShadowMap).

---

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

**2026-09-25: the remade table and jump shots are signed off by the designer and merged into
main.**

- Both roadmap boxes are ticked. The jump heights and pocket feel stay as tuned.
- The place is saved to `place/8ball.rbxl` and published. The old seven-mesh table is gone
  from the place and the repo.

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
