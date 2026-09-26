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
abilities, then the hub map, then collectibles, then ranks, then economy, then public
release, then trading. Server-owned tables were pulled forward (1.5) because the server move is needed
anyway.

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
- [ ] **1.5 Server-owned tables (sixteen of them).** Tables stand on the baseplate until the hub map
  (4.1) exists. Each table is owned by the server:
  the client sends shot inputs, the server validates and runs the simulation, every client
  replays the same shot, so everyone in the server sees every table's balls. Join by stepping
  into the table's queue box (sound, VFX, green indicator); first joiner is host and starts
  the game from the queue menu; host and settings slots exist from day one. Opponent and spectators see the
  shooter's cue turn (aim angle and ball-in-hand position replicated at a low rate). StreamingEnabled on, no per-table shadow lights, ball mesh
  reduced to about 550 triangles. Gamepad: aim with the stick, zoom, shoot.
  Done means: two players in one server play at two different tables while a third walks
  between them and sees both games, on phone, PC and gamepad.
*Progress (2026-09-25): sixteen tables run on the baseplate (8 green, 8 blue), each with one
queue box for up to six (1v1, 2v2 or 3v3, the host's Start), a barrier and a fence; checked
in Studio play-solo. The two-player, phone and gamepad checks in "Done means" are still open.*
*Order note (2026-09-21): 1.7 is being built before 1.6 at the designer's request.*
*Order note (2026-09-22): the designer requested `prompts/PHYSICS_REALISM_PROMPT.md`.
Work proceeds A-F; the designer then requested continuing through D-F in one run.
The remaining 1.5 checks stay open.*

- [ ] **1.6 Spin.** Spin selector (tap the cue-ball icon, pick the strike point) feeding the
  physics. Done means: top spin follows through, back spin draws back, side spin changes the
  rail rebound, visibly.
  Physics realism A-F are implemented: cue impact, spin controls, validated replay, regulation
  physics size, seeded racks and scenario harness. 132 tests and desktop Studio checks pass.
  Phone/controller acceptance remains open. The current imported table stays; its mesh update
  is deferred. This box stays unticked until physical-device and two-client acceptance checks
  are complete.
- [ ] **1.7 Sound and juice, pass one.** Cue strike, clack by speed, rail thud, pocket drop, aim
  ticks, power-bar stretch, sink burst, "Nice shot" popup. Plus the cue ball's trail. Trails
  and pocket bursts are CUE DATA (GDD section 12): the default cue's minimalist white wisp
  is built now, and rarer cues bring their own pair in 5.2. Done means: you catch yourself
  shooting balls around for fun with no goal.

**FRIEND TEST 1.** Hand it to a friend with no explanation. Do they keep shooting? Compare side
by side with GamePigeon. Fix the feel before moving on.

## Table remake (2026-09-24)

The designer moved the focus to the table. Decisions: DECISIONS.md (2026-09-24), GDD
sections 5 and 16, ARCHITECTURE section 7.

- [x] Audit the current table and interview the designer.
- [x] **Remade Pro-Am table in two looks.** One Blender-built model generated from the physics
  geometry, so the drawn pockets match the physics. Blue cloth with satin black, and green
  cloth with red-brown wood. Done means: both looks stand side by side in Studio. No ball
  bounces off air or starts dropping over cloth. The cloth stays sharp in the close aim view
  on phone, PC and gamepad. The table is within the budget in ARCHITECTURE section 7.

## Jump shots (2026-09-24)

The designer made jump shots the priority. Decisions: DECISIONS.md (2026-09-24), GDD
sections 5 and 7, ARCHITECTURE section 3.

- [x] **Jump shots.** A cue-angle slider in the spin panel (4-60 degrees). Raised, the cue
  ball bounces off the slate, can clear a ball, and too much power flies it off the table
  (foul, ball in hand; object balls respotted; the 8 loses). Hard flat shots pop the cue ball
  only rarely; object balls never leave the cloth. Done means: jump a ball and fly one off
  in Studio on phone, PC and a real controller; lint, tests and console clean.

## Shooter reach without the rake (2026-09-25)

The designer removed the rake. The cue and the table stay as they are; only the body's pose
and position change. Decisions: DECISIONS.md (2026-09-25), GDD section 5.

- [ ] **Shooter reach without the rake.** The stance searches spots round and over the
  table: floor, leaning, stretching over the rail with both feet planted, kneeling on the
  table (and last, on the rail top); the body is not tied to the cue line; the head clears
  the table; the grip arm reaches back to the butt and the bridge arm out toward the ball.
  Done means: every shot is reached with both hands on a normal-length cue by the default
  body (the Lune sweep; small and R6 bodies nearly all); in Studio the R15 and R6 rigs look
  right in each pose from a watcher's view;
  the aim turns all the way round with the body gliding, not jumping; a ball along a side
  rail is played from that side rail; phone, PC and gamepad checked; console clean.
- [ ] **Walk while the balls roll.** Once the stroke has played the shooter can walk while
  the balls roll; the shot camera stays until they stop; their next turn poses them again
  from wherever they walked. Done means: checked in Studio with a watcher client; phone
  thumbstick and controller stick move the body; console clean.

## UI redo (2026-09-25)

The designer asked for every screen in the new style (UI_STYLE.md): white cards with ink
outlines and a faint pool-ball pattern, candy buttons, glossy icons. Choices: DECISIONS.md
(2026-09-25). It moves part of 4.2 forward; 4.2 keeps the victory and post-match screens.

- [x] **Kit and art.** `tools/gen_ui_art.py` draws the icons and effect images; the kit
  (HudParts: card, pill, text, candy button, icon, HUD ball) and UIAnim; tokens in
  `Config.UI.Kit`. Done means: a kit sample renders right in Studio; lint and tests clean.
- [x] **Match screen.** The reference's match bar on white: portraits, outlined glossy
  balls, a status card with a phase icon, the clock and a red Leave (a compact bar on
  phones); the foul popup with no panel, gone after 3 s; the wrong-target text and the
  ball-in-hand hint; the coin flip, win and lose cards; the leave and surrender dialog; fine
  controls.
- [x] **Queue area.** The host menu (difficulty tiles with aim-line icons), the floor box, and
  the table sign that pops up only when you walk right up to that table.
- [ ] **Everything else.** Pocket targets, the power bar and the spin panel.
- [ ] **Checked on every device.** PC, phone-sized screens and gamepad selection in Studio;
  the designer's look; a real phone and controller.

## Authorized multiplayer update (2026-09-22)

The current user request overrides the ordinary milestone order and conflicting match
rules. See MULTIPLAYER_SPEC.md. No solo, bots, abilities, difficulty, rewards or progression
are part of this update; the older broader phase boxes below are not completed by it.

- [x] Inspect project/assets/tools and agree gameplay/design decisions.
- [x] Shared authority, independent queues, rules and turn flow for all three team sizes.
- [x] Integrate multiplayer HUD, camera, setup controls, audio and match lifecycle.
- [x] Integrated automated/Studio QA, responsive layout repairs and visual polish within
  the connected tools. Evidence is tracked in MULTIPLAYER_PROGRESS.md.
- [ ] Real full multiplayer matches and physical touch/controller acceptance. Follow
  docs/MULTIPLAYER_TESTING.md; fixtures and emulator screenshots do not replace these.

## Phase 2: A real match

- [ ] **2.1 Rules on the server.** Full 8-ball rules per GDD section 7 (open table after the
  break, 8 on the break re-spotted, fouls, ball in hand anywhere, timeouts, leave = forfeit,
  forfeit button), plus Solo mode. Done means: a full legal 1v1 and a Solo game play start to
  finish and every foul is handled.
- [ ] **2.2 Difficulty levels.** Classic, Difficult, Challenger as a host setting for the whole
  table, no lock yet. Done means: all three guidelines behave as described and both players see
  the same one.
*Progress (2026-09-25): built. The host picks it in the queue menu; Classic draws every line,
Difficult the aim line only, Challenger none (ball glow and red X stay). Checked in Studio
play-solo on PC; the phone, gamepad and two-player checks are open.*
- [ ] **2.3 Pace and presence.** Shot timer, emotes during the opponent's turn, spectators,
  ball X marks and highlights, pocketed-balls HUD. Done means: there is never a moment where a
  player has nothing to do or see.
- [ ] **2.4 PC opponent.** Bot that picks reasonable shots with a skill knob and human-like
  delay, behind the queue menu's Play against PC; versus screen. Done means: a solo player
  steps into a box and gets a fair, beatable match without anyone else in the server.
*Progress (2026-09-25): the queue menu is built (host name, difficulty, abilities on/off as a
placeholder, Start; alone, Play solo and Play against PC, which says "Coming soon"). There is
no automatic start against PC (designer).*
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

- [ ] **4.1 The hub map.** To be designed: the designer will choose the map (GDD section 10,
  Open). Import it, place the tables in it, lighting, sittable seats, snack counter with drink
  and snack tools and animations, zone signs, pro-lobby door placeholder. Until then the tables
  stand on the baseplate.
- [ ] **4.2 UI pass.** Clean consistent HUD, popups, host popup, victory and post-match screens;
  thumb-friendly and gamepad-navigable; one strings module.
- [ ] **4.3 Save data.** Session-locked, versioned saves; money and stats persist.
- [ ] **4.4 Performance pass.** Low-end phone with sixteen busy tables: streaming, LOD, shadow
  and light budget, no stutter.

## Phase 5: Collectibles

- [ ] **5.1 Item catalog and inventory.** Unified catalog (cues and abilities; the item type
  leaves room for table skins later), unique IDs with serials, inventory UI, equip.
- [ ] **5.2 Cues.** Cue model pipeline (one mesh per cue), 30 cues at release, rarities, pocket
  VFX for rare ones.
  Done means (5.1 to 5.2): equip a cue, walk to a pad, and play with it (its trail and pocket
  effect included).
*Scope note (2026-09-23): first release ships cue skins only. Table skins (the old 5.3) moved
to Phase 9.*

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
- [ ] **7.2 Loot boxes.** Permanent cue box; Season 0 limited cue box.
- [ ] **7.3 Shop.** One menu; quantity-limited Founder's and Beta cues.
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

- [ ] Trading (cues, never money; tables too once they exist).
- [ ] Collectible table skins: table model pipeline with a strict per-table budget, the host's
  table used for the match, rare ones with VFX, a table loot box and limited tables.
- [ ] Seasons and themed limited sets.
- [ ] Cross-server matchmaking; a worldwide 1v1 and 2v2 server.
- [ ] Private friend-locked tables, party up.
- [ ] Replay and clip feature; creator outreach.
- [ ] More abilities, new modes, new table types.
