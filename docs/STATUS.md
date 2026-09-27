# Status

**2026-09-27 (latest): the queue area is one card over the table, with Request opponent.**

- **Built:** the pad says JOIN and is see-through glass tinted with its rim. The host's menu
  floats over the middle of their table (kept on screen), with the money in each difficulty tile
  and a full-width Start (no Leave: walk off). Everyone else, guests on the pad included, sees
  the table's sign there. Start on a pad that is not full turns the card to waiting (settings
  shown, Back); the server starts the game 3 s after the pad fills (`MatchEngine.startsAt`,
  `Queue.ReadyGraceSeconds`), and the sign counts STARTING 3, 2, 1. Alone on a 1v1 table the
  waiting card offers Request opponent, Play against PC and Play solo. Request opponent sends
  everyone not at a table a bottom popup (`OpponentPrompt`: the host's face, "<name> needs an
  opponent...", Join and Dismiss); Join teleports them onto the pad.
- **Verified:** lint clean, 367 tests pass (new: waiting and the 3 s grace, a walker stepping
  off in the grace, Back, the host leaving, solo from waiting, a full pad starting at once,
  Request opponent's rules and cooldown). Studio phone emulator: JOIN on the glass pad; the
  sign over the table with its pill; the host card over the table; Start alone, Request
  opponent (greys to Requested!), Back, Start, Play solo by real clicks; the popup's look.
  Console clean.
- **Needs a check by hand:** a PC-sized window and a controller (Y focuses the card, and the
  popup's Join); two players: a guest sees the sign, the 3 s countdown, and the popup's Join
  teleporting onto the pad.

---

**2026-09-27: NICE SHOT! is a lot smaller.**

- **Built:** its word is 18 px (was 40, then 22) and the rays behind it 74 px (was 150).
- **Verified:** lint clean, 363 tests pass; Studio phone emulator, QA combo: the smaller word
  over the side pocket, readable. Console clean.

---

**2026-09-27: the zoom guide goes away once you zoom.**

- **Built:** the first zoom (mouse wheel or pinch, on your turn) hides the zoom guide for the
  rest of the session; it shows again when the player rejoins.
- **Verified:** lint clean, 363 tests pass; Studio: the guide shows on your turn. The phone
  emulator takes neither the tool's mouse wheel nor a pinch, so the hide was not triggered there.
- **Needs a check by hand:** scroll (PC) or pinch (phone) on your turn: the guide goes and does
  not come back next turn or next match; rejoin and it is back.

---

**2026-09-27: no more darkened screens.**

- **Built:** the coin flip, win/lose, leave/surrender cards and the spin picker pop up over the
  game without darkening it (`Multiplayer.Style.ModalDim` 0, `UI.Spin.OverlayTransparency` 1);
  a dialog's see-through backdrop still blocks taps behind it.
- **Verified:** lint clean, 363 tests pass; Studio phone emulator: the coin card and YOU WIN!
  over the undimmed game. Console clean.

---

**2026-09-27: NICE SHOT! for banks, combos, kicks and caroms.**

- **Built:** a good pot that was not plain gets a gold tilted "NICE SHOT!" just over the pocket
  (it pops, floats up and fades in 1.5 s, over turning gold rays) and gold sparkles, on top of
  the pocket burst. The rule is pure (`Rules/NiceShot`); rail hits now carry their spot so the
  pocket jaws do not count as a bank. Never on the break or for the other side's balls.
- **Verified:** lint clean, 363 tests pass (new: plain, bank, combo, kick, carom, jaw rattle,
  and a real-simulation sweep where banked pots read as nice and straight ones do not). Studio
  phone emulator, QA spots: a combo into the side pocket showed NICE SHOT! over it; a straight
  pot into the same pocket did not. Console clean.
- **Needs a check by hand:** a real bank and kick in a match, and how it reads on PC.

---

**2026-09-27: the coin flip says a few words at a time.**

- **Built:** the coin card shows "YOU ARE HEADS" (or TAILS) on the still coin, flips, then "YOU
  BREAK" or "<NAME> BREAKS" over the landed coin for 1.3 s; 3 s in all (was 2.6). The team
  line and "wins the flip" are gone and the card is smaller; the flip sound plays as it spins.
- **Verified:** lint clean, 358 tests pass (the multiplayer tests now follow CoinSeconds).
  Studio phone emulator, QA coin: YOU ARE HEADS 0.5 s, the flip 1.2 s, YOU BREAK 1.3 s.
  Console clean.
- **Needs a check by hand:** the loser's view ("<NAME> BREAKS"; the QA coin always falls to
  the local player), and PC.

---

**2026-09-27: the break has one 20 s clock; running out is a foul.**

- **Built:** on the break, moving the cue ball and shooting share one 20 s clock
  (`Multiplayer.BreakSeconds`), shown on the big clock with no MOVE pill, red and ticking in
  its last 5 s. Running out is a timeout foul (it counts toward the two-timeout forfeit) and
  the opponent gets ball in hand anywhere. Ball in hand after a foul is unchanged (15 s MOVE,
  then 20 s to shoot).
- **Verified:** lint clean, 358 tests pass (new: the break's one clock and its timeout foul).
  Studio phone emulator, QA break: one clock, no pill, red under 5 s, then Foul and the
  opponent's turn with ball in hand. Console clean.
- **Needs a check by hand:** a real match start (coin flip, then the break), and PC.

---

**2026-09-27: the break's hint is short and in capitals.**

- **Built:** "DRAG BALL ANYWHERE ON LINE" (gamepad: "HOLD LT + LEFT STICK TO SLIDE ON LINE").
- **Verified:** lint clean, 357 tests pass; Studio phone emulator, QA break: the pill shows it.
  Console clean.

---

**2026-09-27: ball in hand shows the time to move apart from the time to shoot.**

- **Built:** while the cue ball can be moved, a blue "MOVE 12s" pill with the hand sits under the
  big clock and counts the moving time; the big clock holds at 20 (the shot clock) and the
  portrait ring stays full until the pill reaches 0, then both run. The turn and foul popups
  drop below the pill while it shows.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator, QA fixture: 20 held and ring
  full while MOVE counted 8 to 1, then the pill went and the clock ran 20, 19 with the ring
  draining; YOUR TURN sat under the pill (checked before the hold change). Console clean.
- **Needs a check by hand:** a PC window; a real foul in a match (the fixture skips the foul).

---

**2026-09-27: the group popup stays a second longer.**

- **Built:** YOU ARE SOLIDS / YOU ARE STRIPES now stays up 3.5 s (was 2.5).
- **Verified:** lint clean, 357 tests pass. In Play (phone emulator, QA fixture) the popup was
  on screen 3.5 s when the groups were decided. Console clean.

---

**2026-09-27: the shot clock ring hugs the shooter's portrait and drains.**

- **Built:** the clock round the shooter's portrait is now a rounded ring on the portrait's own
  outline (it was four square bars sized from the scaled bar, so on a phone it sat off the
  icon). It starts full and empties back round to twelve o'clock through placing the cue ball, calling the
  pocket and aiming (it only drained while aiming, and a static green border under it hid the
  drain); red in the last five seconds of aiming. The border stays ink under the ring.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator, QA fixture: the ring's
  halves sit exactly on the portrait at the bar's scale, drain during ball in hand and aiming,
  red arc with 3 s left, zoomed captures show it round and on the edge. Console clean.
- **Needs a check by hand:** a PC window (same code, the bar just scales differently).

---

**2026-09-27: a popup tells each player their group.**

- **Built:** when the groups are decided, the turn popup shows "YOU ARE SOLIDS" or "YOU ARE
  STRIPES" in gold with a solid or striped ball, for 2.5 s, as the deciding ball drops.
- **Verified:** lint clean, 357 tests pass. In Play, an open-table shot that decided the groups
  showed "YOU ARE SOLIDS" with the ball on the client. Console clean.

---

**2026-09-27: bigger Leave icon, clearer zoom guide, bar pinned to the top row, closer phone camera.**

- **Built:** the Leave door fills its button; the zoom guide lighter and bigger, the mouse wheel
  circled in red; the top bar placed from Roblox's real top row (fixes the iPhone 17 Pro drawing
  it lower); on a phone every turn starts a zoom step closer and the break opens at that view.
- **Verified:** lint clean, 357 tests pass. Studio phone emulator: door fills Leave, zoom guide
  clear with the ringed wheel, bar in the top row, aiming and break views closer (the break shows
  the rack and far pockets, the near pockets off screen). Console clean.
- **Needs a check by hand:** the iPhone 17 Pro emulator (the bar should now sit in the top row
  like the 16 Pro Max), and a real phone.

---

**2026-09-27: power bar a little higher; small text keeps its letters' holes.**

- **Built:** on a computer or tablet the power bar sits 5% of the screen higher. Text under 20 px
  gets a 1 px outline (was 2 px), which kept closing the holes of o, a, e, 0, 8; Fredoka One
  stays (the designer's pick from a Studio comparison of five fonts).
- **Verified:** lint clean, 357 tests pass; Studio PC view: bar top at 28% of the screen, the hint
  pill, MOVE and the zoom guide with open letters. Console clean.

---

**2026-09-26: the top bar redone for every screen; bigger centred power bar; zoom guide.**

- **Built:** one-row top bar scaled to fit any width (team, big centred clock, team, Leave at
  the right; solo: 15 balls and Leave); the status card replaced by a 2 s turn popup; on a
  computer or tablet the power bar is bigger and centred on the right; a zoom guide (mouse
  wheel or pinch icon and "Zoom") over the spin button during your turn. Also fixed: the clock
  could flash the whole server time on the first frame.
- **Verified:** lint clean, 357 tests pass. Studio's iPad emulator: 1v1, 3v3 and solo each on
  one row, clock centred, Leave at the right, power bar centred and bigger, zoom guide shown,
  YOUR TURN popup under the bar, OPPONENT'S TURN text on the other side's turn. Console clean.
- **Needs a check by hand:** the phone emulator and a real phone (by the numbers a 1v1 fits
  one row at about 18 px balls on the narrowest emulator phone), a real iPad, and PC.

---

**2026-09-26: a little more room to walk about while waiting in a match.**

- **Built:** the invisible walls round a match stand 3 studs beyond its area on every side
  (`Fence.RoomStuds`); the area, pads and signs are unchanged.
- **Verified:** lint clean, 357 tests pass (a new one: neighbours' walls never meet, 2 and 4
  studs apart). An Edit-mode drawing of old and new walls round four tables. Not yet walked
  in Play: the designer's two-player test was running on the old code, so it was left alone.
- **Try by hand:** restart the test and walk about while the other player aims.

---

**2026-09-26: the shot clock ticks in its last 5 seconds.**

- **Built:** the shooter hears a clock tick at 5, 4, 3, 2 and 1 seconds left while aiming (the
  last two a little higher), stopping the moment they shoot. Licensed APM clip, first tick only.
- **Verified:** lint clean, 356 tests pass. In Play: ticks at 4.99, 3.99, 2.99, 1.99 and 1.00 s
  before the deadline; a shot fired after the first tick stopped the rest. Console clean.
- **Needs a check by hand:** how it sounds and how loud (`Config.Audio.ClockTick.Volume`).

---

**2026-09-26: the match HUD shrunk to the minimum; the break plays the bonus sound.**

- **Built:** the top bar is the balls plus a sliver (37 px computer, 30 phone; was 64 and 52),
  everything in it fitted to that height (Leave keeps a 44 px touch area); one row of balls
  shrinks to 16 px before two rows; the ball-in-hand hint is a thin line as wide as its words.
  Separately, balls pocketed on the break now give the breaker the bonus sound.
- **Verified:** lint clean, 356 Lune tests pass. Studio's phone emulator (750 wide): slim status
  card, two ball rows (one row cannot fit there even at 16 px). A break that pocketed the 2
  granted the breaker the bonus and its sound played at the drop. Console clean.
- **Needs a check by hand:** the PC layout (Studio was on the phone emulator), a wider phone
  (it should get one row), and a controller.
- **Next (designer to confirm):** the aiming camera keeping the table's far end clear of the
  top bar.

---

**2026-09-26: brighter, more saturated lighting; the sunset is a golden hour.**

- **Built (Config.Lighting only):** by day a stronger sun, a lighter and cleaner shade, half the
  haze, and +20% saturation, +12% contrast. At sunset the sun sits 12 degrees up instead of 4,
  golden and stronger, with a warm tan shade instead of lavender, less of the magenta sky's
  fill, a thinner peach haze and +15% saturation; the painted sunset sky is unchanged. The
  fade's warm midpoint matches. Edit mode was relit with the new day look.
- **Verified:** lint clean, 355 Lune tests pass; Play captures of the spawn view and a table,
  day and sunset, before and after, plus the mid-fade and the sun against the sunset sky
  (its disc sits in the painted glow). Console clean.
- **Needs a check by hand:** a real phone at low graphics (post effects and haze differ there).
- **Waiting:** the designer's save to `place/8ball.rbxl` (Edit-mode lighting changed) and publish.

---

**2026-09-26: after a shot the camera swings to a side view of the whole table (a test).**

- **Built:** once the half-second hold ends, the shooter's camera swings round the table (0.9 s,
  eased) to a fixed semi-top-down view from the nearer long side, the table centred and as
  large as the match HUD allows, and swings back to the aiming view when the balls stop. Soft
  shots still keep the aiming view. `Config.Camera.Shot.PullOutView = "Aim"` brings the old
  pull-out back.
- **Verified:** lint clean, 355 Lune tests pass. In Studio Play (PC window, shots fired with the
  controller's A button): a shot aimed down the length (a quarter turn, to the side the camera
  stood on), a shot turning 76 degrees, and a soft tap that stayed in the aiming view. A
  per-frame camera trace showed each swing takes 0.9 s, never loses a table corner from view
  and never jumps; the side view matches the designer's reference framing. Console clean.
- **Needs a check by hand:** the phone emulator and a real phone (a narrower screen changes
  the fit), and a real controller.
- **Open:** in the side view the shooter's own avatar, standing at the table, can cover a corner
  of it.

---

**2026-09-26: the road to release is set; the next work is the pool game itself.**

- **Decided (designer):** the order is (1) the pool game, its UI and mechanics on phone, PC and
  console; (2) ranks and EXP; (3) ten bots, one per tier; (4) cues, money, the shop, inventory,
  the index, loot boxes and trading; then the first-time flow and release. Abilities, the pro
  lobby and the global queue are out of the release (the pro lobby and global queue about one
  to two weeks after it; abilities up for debate). ROADMAP.md is reordered into these stages;
  the GDD and DECISIONS record it, with EXP, the bots' details and the index as Open.
- **Next:** Stage 1 of the roadmap. The first unticked box is 1.5 (server-owned tables), which
  waits on real two-player, phone and gamepad checks.
- **Waiting:** the designer's save of the rooftop map to `place/8ball.rbxl` and publish.

---

**2026-09-26: the rooftop map is finished (all 8 stages; Checkpoint D approved).**

- **Built:** the open-air rooftop pool club from the concept art. The city on the left, the
  coast and green islands on the right, and a day and sunset cycle that is the same for everyone.
  - **At sunset:** lamps over the tables, the fire pit's fire and lit city windows.
  - **Faster walking:** 30% over Roblox's default.
  - **Moving sea:** gentle waves with sailboats drifting on it.
  - **Designer's commands:** `/day` and `/sunset`, which fade the whole server there.
  - About 260,000 triangles of the 512,000 budget (`assets/map/Budget.md`).
- **Verified:**
  - 355 Lune tests pass and lint is clean.
  - Blender and Studio agree on every count.
  - In Play: 24 of 24 walking paths, 7 of 7 edge pushes, and a clean console. Day, fade and
    sunset were captured, and the lowest graphics level too.
- **Needs a real device (Studio cannot fully fake these):**
  - **A phone:** the table lamps, lit windows, bloom and haze at sunset; the fire at low
    graphics; the far view at the lowest graphics level; walking speed with the thumbstick.
  - **A gamepad or console:** walking and the camera round the roof; `/day` and `/sunset` are
    chat commands, for the designer only, so no controller path is needed.
  - **A PC:** the depth-of-field blur on the background (PC-class graphics only) and the full
    sunset at high graphics.
- **Waiting:** the designer's save to `place/8ball.rbxl` and publish (once, now).
- **Next:** ROADMAP 4.1's remaining parts (zone signs, the pro-lobby door), or the next phase.

---

**2026-09-26 (latest): the rooftop city fixed after the designer's look in Play: no warped
towers, no empty grey ground, a soft far edge.**

- **Built:**
  - The near world and the city backdrop draw at full detail (RenderFidelity Precise). Roblox's
    distance LOD had crumpled the far towers and broken up the parks and beach below the
    tower.
  - The side behind the spawn is a full low city now (155 more blocks, the strip by the beach
    included), not a flat grey plain. `Near.fbx` and `Backdrop.fbx` were regenerated and
    imported. The near world's own blocks and the painted far city are unchanged.
  - A light haze (Atmosphere Density 0.15, Offset 0.2, by day and at sunset) fades the far
    city and its join with the painted sky.
- **Verified:**
  - 355 Lune tests pass and lint is clean.
  - Blender and Studio agree: the backdrop is 66,665 triangles (cap 110,000) and the near
    world 8,809 (cap 50,000), with 25 MeshParts (budget 30).
  - Play captures of the designer's three views (the high view over the stair side, the
    railing toward the city, and looking down toward the spawn), by day and at sunset, and at
    phone graphics (level 4). The console is clean.
- **Still to do:** save the place to `place/8ball.rbxl` and publish (the map imports changed),
  then Checkpoint D.

---

**2026-09-26: the rooftop map, Stage 7 of 8 built (the sunset and the day/sunset cycle), waiting at
Checkpoint D.**

- **Built:**
  - The cycle, the same for everyone (Day 10 min, a 1 min fade, Sunset 5 min, a fade back), from
    the server's clock with no network traffic: `LightCycle` (pure, Lune-tested), `MapLighting`,
    `DayCycle`.
  - A sunset sky and a dusk sky rendered from the day's cloud scene (the approved day sky is
    unchanged): a violet sky, the sun low over the sea right of the lounge, the far city lit up,
    island silhouettes.
  - At sunset: the city's windows light up, a warm rim glows under each table, and the
    lanterns, pergola globes (now lit: 9 lights of 20) and fire pit warm up.
  - Depth of field keeps the background soft (the designer's direction at Checkpoint C).
  - `/day` and `/sunset` chat commands for the designer: the whole server fades there.
- **Verified:** 355 Lune tests pass; the fade and both commands were run in Play; 24 of 24 paths
  and 7 of 7 edge pushes pass; a clean console; three critic rounds (notes in Spec section 9).
- **Found:** this place is on Roblox's unified lighting, so there is no Technology setting to
  switch (STUDIO_NOTES).
- **Waiting:** the designer's OK at Checkpoint D.
- **Next:** Stage 8, the finish (docs, then the one save and publish).

---

**2026-09-26: the rooftop map, Stage 6 of 8 done (the far horizon); Checkpoint C approved.**

- **Built:**
  - The far horizon painted into the day sky (`assets/map/gen_sky.py`), which every device
    shows, even phones that draw nothing past a few hundred studs:
    - a far city to 7,000 studs out, its towers gathered in three downtowns ahead-left with
      six landmarks, over a low carpet with blue hills behind;
    - far islands and islets on the painted sea, five of them nearer so phones see islands
      on the ocean side.
  - The 3D sea and land stop at 2,600 studs, where the painting takes over.
  - The mid city steps down toward the painting and eases out on the stair side (a
    re-exported `Backdrop.fbx`, 57,863 triangles); a green waterfront on the far shore.
- **Verified:**
  - No seams or ghost peaks at the join from the Checkpoint C views; the lowest graphics
    level shows the city, the downtowns and the mountains.
  - 24 of 24 paths and 7 of 7 edge pushes pass, and the console is clean.
  - Three critic rounds; what they left is in Spec section 9.
- **Checkpoint C:** approved as it is. The backdrop is background: Stage 7's lighting and
  atmosphere soften and blur it so the pool tables are the focal point (DECISIONS).
- **Next:** Stage 7, the sunset sky and the day and sunset cycle.

---

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
  cyan, Grandmaster black and gold, Reyes rainbow, crisp bevelled pips on the ring's bottom
  edge (no tray, nothing below them), and more glare. `--gif` renders them all shining. Each has a
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
