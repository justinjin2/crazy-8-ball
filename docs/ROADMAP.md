# Roadmap

How to use this file:

- **The current milestone is the first unticked box.** Work on one at a time, top to bottom.
- Every milestone ends in something you can play or see. "Done means" is the test.
- **Standing rule for every milestone:** works on phone, PC and gamepad and is checked on all
  three; lint and tests pass; playtested in Studio; console clean; screenshot taken; STATUS.md
  updated; commit and push; save the place file when Edit-mode assets changed.
- New ideas go in the GDD's parked list (section 18), not into the current milestone.
- Decisions that change a milestone go in DECISIONS.md with the date.

Rewritten 2026-09-20. Order follows the designer's priority: the shot, then feel, then
abilities, then the lounge look, then collectibles, then ranks, then economy, then public
release, then trading. The lounge with twelve server-owned tables was pulled forward (1.5)
because the server move is needed anyway and the map is already built.

---

## Phase 0: Setup

- [x] **0.1 Project folder.** Git, Rojo syncing into Studio, StyLua, Selene, luau-lsp.
- [x] **0.2 AI connected.** Studio MCP connected, rules file written.

## Phase 1: The shot

- [x] **1.1 One ball rolls.** Custom physics: rolling, friction, rail bounces, rest.
- [x] **1.2 Balls collide and sink.** Ball-ball collisions, six pockets with jaws, rack, break,
  physical pocket drop.
- [x] **1.3 Aim and shoot.** Drag to aim, corridor guideline with contact ring, pull-back power
  bar, mouse and touch.
- [x] **1.4 Camera and avatar.** One orbit camera opposite the aim with automatic whole-table
  framing and continuous zoom to a down-the-cue view; posed, faded avatar; pull-out during a
  shot. Imported Blender table model, sphere-mesh balls with baked textures.
- [ ] **1.5 Lounge and twelve server-owned tables.** Import the lounge package
  (`assets/lounge/`, tables placed from `Markers.json`). Each table is owned by the server:
  the client sends shot inputs, the server validates and runs the simulation, every client
  replays the same shot, so everyone in the server sees every table's balls. Join by stepping
  on the table's floor pad (sound, VFX, green indicator); first joiner is host; second joiner
  is the opponent; host and settings slots exist from day one. Opponent and spectators see the
  shooter's cue turn (aim angle and ball-in-hand position replicated at a low rate). Invisible
  seats on the sofas and chairs. StreamingEnabled on, no per-table shadow lights, ball mesh
  reduced to about 550 triangles. Gamepad: aim with the stick, zoom, shoot.
  Done means: two players in one server play at two different tables while a third walks
  between them and sees both games, on phone, PC and gamepad.
*Order note (2026-09-21): 1.7 is being built before 1.6 at the designer's request.*
*Order note (2026-09-22): the designer requested `prompts/PHYSICS_REALISM_PROMPT.md`.
Work proceeds A-F, reporting after each; the remaining 1.5 checks stay open.*

- [ ] **1.6 Spin.** Spin selector (tap the cue-ball icon, pick the strike point) feeding the
  physics. Done means: top spin follows through, back spin draws back, side spin changes the
  rail rebound, visibly.
  Physics realism A-C are implemented: tuning, spin decay, throw, spin transfer, cushions and
  corner shelf; 109 tests and desktop Studio checks pass. Phone/controller acceptance and
  the imported-table pocket art choice remain open; D-F are not built;
  this box stays unticked until E and the platform acceptance checks are complete.
- [ ] **1.7 Sound and juice, pass one.** Cue strike, clack by speed, rail thud, pocket drop, aim
  ticks, power-bar stretch, sink burst, "Nice shot" popup. Plus the cue ball's trail. Trails
  and pocket bursts are CUE DATA (GDD section 12): the default cue's minimalist white wisp
  is built now, and rarer cues bring their own pair in 5.2. Done means: you catch yourself
  shooting balls around for fun with no goal.

**FRIEND TEST 1.** Hand it to a friend with no explanation. Do they keep shooting? Compare side
by side with GamePigeon. Fix the feel before moving on.

## Phase 2: A real match

- [ ] **2.1 Rules on the server.** Full 8-ball rules per GDD section 7 (open table after the
  break, 8 on the break re-spotted, fouls, ball in hand anywhere, timeouts, leave = forfeit,
  forfeit button), plus Solo mode. Done means: a full legal 1v1 and a Solo game play start to
  finish and every foul is handled.
- [ ] **2.2 Difficulty levels.** Classic, Difficult, Challenger as a host setting for the whole
  table, no lock yet. Done means: all three guidelines behave as described and both players see
  the same one.
- [ ] **2.3 Pace and presence.** Shot timer, emotes during the opponent's turn, spectators,
  ball X marks and highlights, pocketed-balls HUD. Done means: there is never a moment where a
  player has nothing to do or see.
- [ ] **2.4 PC opponent and the host popup.** Bot that picks reasonable shots with a skill knob
  and human-like delay; the host popup (Solo, Wait for a player, Play against PC, difficulty,
  abilities on/off) with the 15-second auto-start; versus screen. Done means: a solo player
  steps on a pad and gets a fair, beatable match without anyone else in the server.
- [ ] **2.5 Teams.** 2v2 and 3v3: rotating turns, shared groups, per-shooter clock, whole-team
  forfeit, PC fill for any seat. Done means: four friends finish a 2v2.
- [ ] **2.6 Juice, pass two.** Turn streaks (x2 on fire, x3 blue fire), trickshot detection
  (bank, combo, multi-ball) with popups, money per ball win or lose, victory screen, loser
  shown as lost, Rematch and Play again. Done means: a lucky bank shot makes you react out loud.

**FRIEND TEST 2.** Two friends play each other. Do they rematch without being asked?

## Phase 3: Abilities

- [ ] **3.1 Ability framework.** Equip one ability; each ability declares target and firing
  window; cooldown in the user's own turns; server-validated; developer flag that unlocks every
  built ability for tests. Done means: a placeholder ability can be equipped, used, and is
  greyed out until its cooldown ends.
- [ ] **3.2 Magnet Pocket** (the starter ability everyone gets).
- [ ] **3.3 Time Stop.**
- [ ] **3.4 Super Bounce.**
  Done means (3.2 to 3.4): each creates at least one "did you see that" moment in a test match
  and PC matches still feel fair.

**FRIEND TEST 3.** Do abilities make matches more fun, or just more random? Tune.

## Phase 4: Look, feel and platforms

- [ ] **4.1 Lounge art and lighting pass.** Lighting recipe from the package, snack counter
  with drink and snack tools and animations, signs, pro-lobby door placeholder.
- [ ] **4.2 UI pass.** Clean consistent HUD, popups, host popup, victory and post-match screens;
  thumb-friendly and gamepad-navigable; one strings module.
- [ ] **4.3 Save data.** Session-locked, versioned saves; money and stats persist.
- [ ] **4.4 Performance pass.** Low-end phone with twelve busy tables: streaming, LOD, shadow
  and light budget, no stutter.

## Phase 5: Collectibles

- [ ] **5.1 Item catalog and inventory.** Unified catalog (cues, tables, abilities), unique IDs
  with serials, inventory UI, equip.
- [ ] **5.2 Cues.** Cue model pipeline (one mesh per cue), 30 cues at release, rarities, pocket
  VFX for rare ones.
- [ ] **5.3 Tables.** Table model pipeline with a strict per-table budget, the host's table is
  used in the match, VFX for rare ones.
  Done means (5.1 to 5.3): equip a cue and a table, walk to a pad, and play on them.

## Phase 6: Ranks

- [ ] **6.1 Rating and tiers.** One rating, tiers Bronze to Reyes with divisions, Unranked to
  Bronze after one game, peak rank, rewards per division, difficulty multipliers, PC ceiling.
- [ ] **6.2 Difficulty unlocks and warnings.** Host lock by peak rank, guest warning with Play
  anyway.
- [ ] **6.3 Pro lobby.** Separate place with a teleport door, Diamond I and above, Difficult
  and Challenger only.
- [ ] **6.4 Leaderboards, flags, win streaks.** Rating board, wins-against-people board, nation
  board, country flags, win streak above the head, match history.
- [ ] **6.5 Real-match check.** Server-tracked match time, the one-minute mark, forfeit
  accounting (forfeiter always loses rating; repeat forfeits against the same opponent give
  the winner nothing), forfeit confirmation warning.

## Phase 7: Economy

- [ ] **7.1 Money packs for Robux** and paid-random-item compliance: odds screens, restricted-
  region direct-purchase catalog.
- [ ] **7.2 Loot boxes.** Permanent cue box and table box; Season 0 limited boxes.
- [ ] **7.3 Shop.** One menu; quantity-limited Founder's and Beta cue and table.
- [ ] **7.4 Ability gacha.** Robux spins in packs, one free daily spin, keep everything, spin
  credit for duplicates.
- [ ] **7.5 VIP pass and starter offer.**
- [ ] **7.6 Retention.** 7-day daily streak, playtime reward, reminders on menu open, focus
  loss and the post-match screen.

## Phase 8: First-time flow and public release

- [ ] **8.1 First-time playthrough.** Hidden popup, disguised PC that walks in and blunders,
  ghost break guide, first-win cue box, Unranked to Bronze.
- [ ] **8.2 Analytics funnel** with Roblox's built-in analytics.
- [ ] **8.3 Name, icon, thumbnails, game page.** Final name check.
- [ ] **8.4 Public release.** Watch where players quit. Everything above must exist.

**RELEASE.** Review what players love and ignore. That decides the order below.

## Phase 9: After release

- [ ] Trading (cues and tables, never money).
- [ ] Seasons and themed limited sets.
- [ ] Cross-server matchmaking; a worldwide 1v1 and 2v2 server.
- [ ] Private friend-locked tables, party up.
- [ ] Replay and clip feature; creator outreach.
- [ ] More abilities, new modes, new table types.
