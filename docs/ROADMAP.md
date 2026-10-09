# Roadmap

How to use this file:

- **The current milestone is the first unticked box.** Work on one at a time, top to bottom.
- Every milestone ends in something you can play or see. "Done means" is the test.
- **Standing rule for every milestone:** works on phone, PC and gamepad and is checked on all
  three; lint and tests pass; playtested in Studio; console clean; screenshot taken; STATUS.md
  updated; commit and push; save the place file when Edit-mode assets changed.
- New ideas go in the GDD's parked list (section 18), not into the current milestone.
- Decisions that change a milestone go in DECISIONS.md with the date.
- **A milestone's number is its name, not its place.** Code comments and older notes cite the
  numbers (2.4, 5.1 and so on), so a milestone keeps its number when it moves; the order on
  this page is the order of work.

Rewritten 2026-09-20; reordered 2026-09-26 to the designer's road to release (below).

---

## Lucky-block follow-up (designer, 2026-10-03)

- [x] Native hold prompt, larger held models, brighter world/hotbar/bag appearance, faster
  1.4 s opening spin, 0.5 s hold and clear cue reveal. Keyboard and phone-emulator checks,
  screenshots, lint and 979 tests passed.
- [x] Multiple independent floor blocks, reconnect safety, three new tiers, designer timer
  bypass, 19 Robux skip with durable receipts/credits, padded icons, rarity lights, softer
  reveal rays/dim and the confirmed audio replacements. Studio and automated checks recorded
  in STATUS.md.
- [x] Fix orphaned holding animations after repeated equips; enlarge Legendary in hands,
  on the floor and in inventory. Live equip/unequip/throw checks and 983 tests passed.
- [x] Two-stage lucky-block skip: first click shows the final landing; second click reveals
  immediately. Studio transition checks, lint and all 983 tests passed.
- [x] Lucky-block skip reworked to one tap: the strip speeds to the prize in 0.7 s instead
  of jumping (designer, 2026-10-04). Also: 0.6 s pocket settle (was 1 s), measured sound
  levels, no ability-ready sound in solo.
- [x] Cases, the Magic 8 Ball and the reward popups retired; lucky blocks are the only gacha
  (a win = one Mystery block, rewards and trades in blocks, save v7, Rewards-menu claims,
  pull cutscenes on the lucky reel, Inventory on Cues, the Shop emptied for the GUI
  overhaul). Studio computer-window checks, lint and 977 tests passed (2026-10-04).
- [x] The lively Shop (branch `shop-lively`, 2026-10-06): the new frame (unroll, scrolling
  header, dots, tabs outside, the 8-ball flair, HudFocus) and the Featured page's Grand
  Opening card, five gates approved; the method saved as the `lively-gui` skill; the Firework
  Cue rename with save v8. Phone, computer and gamepad checked; 1001 tests passed
  (`docs/prompts/SHOP_LIVELY_REPORT.md`).
- [ ] **Lucky block look, our own blocks (designer, 2026-10-07).** One master block built in
  Blender (glossy bevelled cube, raised "?" faces, corner studs, like the Grand Opening shop
  art), rigged with the pack's `joint1`/`joint2` bones so the uploaded Box Idle plays on it;
  every kind is the master plus a texture, an optional topper on the top bone and a recoloured
  pack VFX set, as Config data. Wings (the pack's winged rig and idle) on Legendary, Mythic
  and Sky. In order:
  - [x] Concept sheet: 8 Ball, gift-wrapped Starter, Gift (clock), Mythic, Sky, Mystery,
    with the Grand Opening block as the style key; designer approves. Round A:
    https://claude.ai/artifact/7u35cgsdy9uZt1jPyUSDEL (art in `~/Desktop/8ball-refs/lucky-blocks/`).
  - [x] Then the same concepts for Standard, Uncommon, Rare, Epic and Legendary (round B; the
    designer said "do all of them", 2026-10-07; Standard redrawn with beige rims, brown faces).
  - [x] Glossy 2D icon for every kind (the approved concept art, `assets/luckyblocks/icons`);
    the hotbar and bag show it, and so does every BlockIcon (rewards, trades, the roadmap)
    instead of a 3D view (2026-10-07). The Shop's Grand Opening banner keeps its own art.
  - [x] The 3D master block and its rig in headless Blender (`tools/luckyblock_build.py`),
    built to the approved icons, with the pack's idle on our rig (LuckyBoxIdle) and a wing
    flap (LuckyWingIdle).
  - [x] All 12 kinds in 3D (2026-10-07): every kind on our own model with its own particles;
    held, thrown, landed and idling checked in Studio. Designer to look them over.
  - [x] Gift delivery (2026-10-07): the first leave owes it (12 h from the leave), it falls
    from the sky on the next lobby visit and is picked up (`/giftdrop` to test). The pack's
    pulsing glow waits for a block's timer.
- [ ] **The GUI redo (designer, 2026-10-08)**, one screen at a time, each from an approved
  concept (`docs/prompts/CUES_LIVELY_PROMPT.md`):
  - [x] The Abilities screen and the Ranked roadmap show again (they opened blank).
  - [x] The cue card (concept 1, round 4): built for the Cues grid and the Index; the rank cues
    are one rarity, Ranked (2026-10-08). Phone, PC size and gamepad by the designer.
  - [ ] The Cues menu (the Inventory renamed, a cue icon, no tab row, the Index as a book
    button, two rows of cards on open).
  - [ ] The lucky block spin and YOU GOT with the same cards; rarer cues shown more often on
    the reel (looks only).
  - [ ] Free Reward: the Lucky 8 Block for the favorite.
  - [ ] Upgrade ideas for Abilities and Ranked (concepts; built only if approved).
- [ ] The Shop's Blocks, Money and Passes pages with the `lively-gui` skill.
- [ ] Physical controller hold acceptance; save the updated place and publish its templates.

---

## The road to release (2026-09-26)

The designer's order, one stage at a time:

1. **The pool game on every device.** Finish and polish the match itself, its UI and its
   mechanics, until it fits and plays well on phone, PC and console.
2. **Ranks and EXP.** Save data first, then the rating and tiers, EXP and the leaderboards.
3. **Bots.** Ten bots, one per tier from Bronze (easiest) to Reyes (hardest); each player
   meets the bot of their rank.
4. **Cues, economy and trading.** Cue models and textures, money, the shop, inventory, the
   index, loot boxes and trading.
5. **The first-time tutorial and funnel, then release.** Once everything else is done: the
   onboarding first match and the analytics funnel, then the performance pass and the game page.

**Not in the release:** the pro lobby. It follows about one to two weeks after release
(nobody can reach the pro lobby's rank at launch anyway). **Ultimates (the abilities, reworked)
are in the release** (designer, 2026-09-28; GDD section 9), built on branch `ultimates` (below). **The global queue was moved in and built first (designer,
2026-09-28; below).**

---

## Global queue, arena and rematch (2026-09-28)

The designer asked for it now, ahead of the stages below: when nobody in your server wants to
play, find someone of your rank in any server. Decisions: DECISIONS.md (2026-09-28), GDD
section 6, ARCHITECTURE "Global queue and arenas".

- [x] **Matchmaking.** Join Global Queue on every pad (1v1 alone, 2v2 with 2, 3v3 with 3), a
  MemoryStore queue paired by one leader server each second, closest rank first and anyone
  after 10 s, Cancel, stepping off cancels. Done means: Lune tests (many simulated servers,
  cancel races, a leader dying) and a real MemoryStore match in Studio. Done 2026-09-28.
- [x] **The arena and the post-game row.** A reserved server of this place: the rooftop at
  day with one blue table in the middle; Rematch (everyone agrees, alternate breaks), the series score, Play
  another and Lobby; lobby tables get Rematch and Leave. Done means: in Studio the arena
  plays, rematches (1-0, 2-0) and each game pays rank XP and money once. Done 2026-09-28.
- [ ] **Checked live.** Publish, then two accounts: a 1v1 and a 2v2 through the queue; the
  `GQ` timing lines in the server log (MULTIPLAYER_TESTING.md, Global queue); rematch, Play
  another, Lobby back to the same server; a real phone and a real controller on the row.


---

## Stage 1: The pool game on every device

Finish the match, its UI and its mechanics so it fits and plays well on a phone, PC and a
console controller. Many boxes here wait only on checks with a real phone, a real controller
and real two- and four-player matches.

### Phase 0: Setup

- [x] **0.1 Project folder.** Git, Rojo syncing into Studio, StyLua, Selene, luau-lsp.
- [x] **0.2 AI connected.** Studio MCP connected, rules file written.

### Phase 1: The shot

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

### Table remake (2026-09-24)

The designer moved the focus to the table. Decisions: DECISIONS.md (2026-09-24), GDD
sections 5 and 16, ARCHITECTURE section 7.

- [x] Audit the current table and interview the designer.
- [x] **Remade Pro-Am table in two looks.** One Blender-built model generated from the physics
  geometry, so the drawn pockets match the physics. Blue cloth with satin black, and green
  cloth with red-brown wood. Done means: both looks stand side by side in Studio. No ball
  bounces off air or starts dropping over cloth. The cloth stays sharp in the close aim view
  on phone, PC and gamepad. The table is within the budget in ARCHITECTURE section 7.

### Jump shots (2026-09-24)

The designer made jump shots the priority. Decisions: DECISIONS.md (2026-09-24), GDD
sections 5 and 7, ARCHITECTURE section 3.

- [x] **Jump shots.** A cue-angle slider in the spin panel (4-60 degrees). Raised, the cue
  ball bounces off the slate, can clear a ball, and too much power flies it off the table
  (foul, ball in hand; object balls respotted; the 8 loses). Hard flat shots pop the cue ball
  only rarely; object balls never leave the cloth. Done means: jump a ball and fly one off
  in Studio on phone, PC and a real controller; lint, tests and console clean.

### Shooter reach without the rake (2026-09-25)

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

### Fixed-mode tables and queue pads (2026-09-26)

The designer went back to one mode per table, with one rectangular pad each to step onto, and a
look per mode and lobby. Decisions: DECISIONS.md (2026-09-26), GDD sections 6, 10 and 16.

*Queue card (2026-09-27): JOIN on a glass pad; no settings or Start, a full pad starts by
itself after 3 s; the host's card offers Request opponent/players, and on 1v1 alone Play
against PC and Play solo. Checked in Studio on the phone emulator; PC size, gamepad and two
players are open.*

- [ ] **Tables, pads and looks.** Ten 1v1, four 2v2 and two 3v3 tables (1v1 at the front);
  one glowing rectangular pad per table in front of its long side that joins instantly,
  pulsing outlines and an arrow while it has room; teams by arrival; solo only on 1v1; six looks (green/wood, blue/black, red on
  either, charcoal on either), the baseplate showing each. Done means: lint, tests, Studio
  play (joining, fixtures, looks), the place saved.
- [ ] **Checked on every device.** A real phone and controller, and a real two-player and
  four-player match.

### UI redo (2026-09-25)

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
- [x] **Everything else.** Pocket targets, the ball-in-hand ring, the power bar and the spin
  panel.
- [ ] **Checked on every device.** PC, phone-sized screens and gamepad selection in Studio;
  the designer's look; a real phone and controller.

### Authorized multiplayer update (2026-09-22)

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

### Phase 2: A real match

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
- [ ] **2.5 Teams.** 2v2 and 3v3: rotating turns, shared groups, per-shooter clock, whole-team
  forfeit (PC fill comes with the bots, 2.4). Done means: four friends finish a 2v2.
- [ ] **2.6 Juice, pass two.** Turn streaks (x2 on fire, x3 blue fire), trickshot detection
  (bank, combo, multi-ball) with popups, money per ball win or lose, victory screen, loser
  shown as lost, Rematch and Play again. Done means: a lucky bank shot makes you react out loud.
  Progress 2026-10-09: the **ball streak** is built (STREAK x1 to x8 under the match popups,
  sprays, fire from x3, a growing shake, a small money bonus from x3; GDD section 8, UI_STYLE
  section 28). Open: a real phone and the sound by ear.
- [ ] **4.2 UI pass.** Clean consistent HUD, popups, host popup, victory and post-match screens;
  thumb-friendly and gamepad-navigable; one strings module.
  Moved here from Phase 4 (2026-09-26): it is part of the pool game's UI.

**FRIEND TEST 2.** Two friends play each other. Do they rematch without being asked?

---

## Stage 2: Ranks and EXP

  Progress 2026-10-03 (the GUI lane, merged into `release`): every screen and reward moment
  reworked (shop, inventory, case opening, 8-ball reveal, column, settings, player list,
  result cutscene, NEW RANK!). Still to do: the designer's list of fixes, phone and gamepad.
- [x] **4.3 Save data.** Session-locked, versioned saves; money and stats persist.
  Moved ahead of ranks (2026-09-26): ranks, EXP and money must survive leaving.
  Done 2026-09-27 on the branch `ranks-money`: ProfileStore behind `PlayerData`, save layout
  v1 with migrations and validation (Lune-tested), audited; checked in Studio with API access
  (persists across play sessions, bad input refused, failed load kicks). A real two-server
  takeover can only be checked live.
- [ ] **6.1 Rating and tiers.** One rating, tiers Bronze to Reyes with divisions, Unranked to
  Bronze after one game, peak rank, rewards per division, difficulty multipliers, PC ceiling.
  Progress 2026-09-27 (branch `ranks-money`): rank XP drives 46 divisions (all 1,000 XP,
  placeholder), win +250, the tier floors, Unranked to Bronze I after the first match, the
  peak and one-time money rewards per division, forfeits and the one-minute mark; the rank
  HUD, nameplates, result screen, NEW RANK! and the roadmap. Placeholder: every number (the
  real rating formula is still Open). Not built: difficulty multipliers on XP, the PC ceiling
  (Config hook only), seasons. **The real numbers were decided 2026-09-27**: `docs/ECONOMY.md`
  section 4 (reworked 2026-09-28: XP never lost, growing division sizes, fixed Reyes XP, XP
  boosts, the win streak and the opponent-gap factor).
  Progress 2026-09-28 (branch `economy`, overnight): those real numbers are in (the ladder,
  per-tier and mode XP, the Classic fade, XP never lost, the gap factor, the boosts and the
  streak) and rank-up rewards pay money, cases, the tier cue and the chat tag for real.
  Still to do: difficulty multipliers wait for the difficulty picker, the PC ceiling for bots.
- [x] **6.6 EXP.** Dropped 2026-09-28 (designer): there is no separate account Level or EXP;
  rank XP is the one progression bar (`docs/ECONOMY.md` sections 4 and 5).
- [ ] **6.2 Difficulty unlocks and warnings.** Host lock by peak rank, guest warning with Play
  anyway.
- [ ] **6.4 Leaderboards, flags, win streaks.** Rating board, wins-against-people board, nation
  board, country flags, win streak above the head, match history.
  Progress 2026-09-28: the win streak above the head is built ("🔥 3", Stats.WinStreak).
  Progress 2026-10-03 (the GUI lane): Most wins vs players and Highest rank, as lobby signs
  and a player-list tab. No nation board. Still to do: a live check (Studio has no DataStores).
- [ ] **6.5 Real-match check.** Server-tracked match time, the one-minute mark, forfeit
  accounting (forfeiter always loses rating; repeat forfeits against the same opponent give
  the winner nothing), forfeit confirmation warning.

---

## Stage 3: Bots

- [ ] **2.4 Bots (PC opponent).** Ten bots, one per tier: the Bronze bot is the easiest, the
  Reyes bot the hardest, and a player meets the bot of their rank (GDD section 11). Each picks
  reasonable shots with a human-like delay, behind the queue menu's Play against PC; versus
  screen. PC fill for any seat at a 2v2 or 3v3 table (moved here from 2.5). Done means: a solo
  player of any rank steps onto a 1v1 pad and gets a fair, beatable match against the bot of
  their rank without anyone else in the server; a beginner can beat the Bronze bot and the
  Reyes bot is hard for a strong player.
*Progress (2026-09-25): the queue menu is built (host name, difficulty, abilities on/off as a
placeholder, Start; alone, Play solo and Play against PC, which says "Coming soon"). There is
no automatic start against PC (designer).*
*Progress (2026-10-02, the Bots lane, merged into `release`): built, all ten tiers, Play
against PC, Fill with PC on 2v2/3v3, disguised global-queue and lobby bots and the tutorial bot
(`docs/parallel/bots.md`). Still to check: the published game's queue fallbacks, two real
players, phone and gamepad.*

---

## Stage 4: Cues, economy and trading

- [x] **5.1 Item catalog and inventory.** Unified catalog (cues and abilities; the item type
  leaves room for table skins later), unique IDs with serials, inventory UI, equip.
  Done 2026-09-28 (branch `economy`, overnight): the catalog of 44 cues plus Classic as data
  rows (`Progression/Catalog`), counts per cue in save v2 with copy numbers for numbered
  Limited cues, the Inventory menu (Cues with filters, detail, Equip, Sell, sell all
  duplicates; Cases; Index), equip replicated to everyone. Checked in Studio on PC and phone
  sizes. Abilities are not catalog rows yet (they come with 3.x).
- [ ] **5.2 Cues.** Cue model pipeline (one mesh per cue), 30 cues at release, rarities, pocket
  VFX for rare ones.
  Done means (5.1 to 5.2): equip a cue, walk to a pad, and play with it (its trail and pocket
  effect included).
  Progress 2026-09-28 (branch `economy`, overnight): the rarities, 30 case cues plus ten rank
  cues and the Starter, VIP, Founder's and Beta cues, all with placeholder names and looks
  (colours on the built stick, the 2D power cue and a trail and pocket burst per rarity);
  equipping one and playing a solo game with it checked in Studio. Still to do: the real cue
  models (one mesh each) and their final effects.
  Progress 2026-10-01 (branch `abilities`): the cue skins are imported. The placeholders are
  replaced by the plan's 46 case cues (7/9/10/9/7/3/1) and the Starter, VIP and Rank cues
  get their skins: surface, aura on the back, 3D pieces, trails and pocket finishers, all as
  data rows and uploaded assets; rendered pictures in the menus. Checked on PC in Studio.
  Still to do: the phone and gamepad check, and the Unique cues' own skins.
*Scope note (2026-09-23): first release ships cue skins only. Table skins (the old 5.3) moved
to after release (Later, at the bottom).*
- [x] **5.4 Index.** A collection screen of the game's cues. What it shows for cues you do not
  own, and whether filling it pays anything, are Open (GDD section 12).
  Done 2026-09-28 (branch `economy`, overnight; the designer decided both): never-owned cues
  are dark silhouettes with "?", and completing a rarity row pays once (money and a title up
  to Epic, a title only for Legendary, Mythic and Secret). Checked in Studio. The titles were
  dropped on 2026-09-28 (money up to Epic, nothing above).
*Every number and rule for 7.1 to 7.7 (cases, odds, the shop, packs, VIP, the starter pack,
daily rewards, trading's gates, Roblox policy): `docs/ECONOMY.md`.*
- [ ] **7.1 Money packs for Robux** and paid-random-item compliance: odds screens, restricted-
  region direct-purchase catalog.
  Progress 2026-09-28 (branch `economy`, overnight): the six packs, the first-purchase double,
  receipts granted once per purchase id (checked with Studio's QA hook), the Odds panel on
  every case, and PolicyService's restricted players refused paid random cases (a note in the
  Shop; free cases still open). Still to do: the product ids from the Creator Hub (id 0 shows
  "Coming soon"), a live receipt, and a restricted-region direct-purchase shelf if needed.
  Progress 2026-10-03 (the Economy lane, merged into `release`): money x10, the new Dashboard
  list in `Config.Products` (4 passes, 24 products: packs $9,000 to $1,300,000, Mystery, restock
  cases, skips), odds as percentages, restricted regions refused paid random items. The 4
  passes and 24 products were created through Open Cloud on 2026-10-03 and their ids are in
  Config. Still to do: a live purchase.
- [x] **7.2 Loot boxes.** Permanent cue box; Season 0 limited cue box.
  Done 2026-09-28 (branch `economy`, overnight) for the money cases: Standard, Rare, Epic and
  Legendary cases bought with money (Buy 10 for the price of 9, sales), free win cases, the
  spinning reel and Fast Open's grid, duplicates and selling, Mythic and Secret banners. The
  Event Case exists switched off; a Season 0 limited case waits for seasons.
- [ ] **7.3 Limited shelf.** One economy menu; timed, numbered Limited cues (never in cases),
  including the Founder's and Beta cues; copies-in-existence counts on every cue.
  Progress 2026-09-28 (branch `economy`, overnight): the Shop's Limited tab, the Beta Cue for
  money with numbered copies ("#1 of 1,000"), the Founder's Cue for Robux (id 0), and "N exist"
  on every cue from a shared counter. Still to do: a live check of the counters across
  servers, and the real timed drops.
  Progress 2026-10-03 (the Economy lane): the shelf holds one row, the Firework Cue
  ($149,000, 14 days, numbered), off until its `StartsAt` is set before publishing; `/limited`
  to test. Founder's and Beta have no row.
- [ ] **7.5 VIP pass and starter offer.**
  Progress 2026-09-28 (branch `economy`, overnight): VIP (2x money, +50% XP (removed
  2026-10-02), the VIP Cue, the
  [VIP] rainbow tag and name shine), Fast Open, the Starter Pack and the welcome VIP offer with
  their timers, the Money Party; all behind product ids that are still 0. Still to do: the ids
  and a live purchase.
  Progress 2026-10-03 (the Economy lane): VIP 599 R$ (+1 daily spin), the Starter Pack 99 R$
  ($75,000 and an hour of 2x money), Quick Cases 299 R$ (replaces Fast Open: halves timers).
  Ids in Config (2026-10-03). Still to do: a live purchase.
- [x] **7.6 Retention.** 7-day daily streak, playtime reward, reminders on menu open, focus
  loss and the post-match screen.
  Done 2026-09-28 (branch `economy`, overnight): the daily streak in four-week cycles (a
  Legendary Case on day 28), playtime gifts, codes, and the reminder line on the result screen
  and the toast on Roblox's menu or a focus loss. Checked in Studio but the toast (hand check).
- [ ] **7.7 Trading.** Cues only, never money (GDD section 12); moved into the release from
  after it. The save layer changes both players' saves together or not at all, so no cue is
  ever duplicated or lost. Done means: two players swap cues, and a trade broken off at any
  moment (a player leaves, the server shuts down) leaves both inventories as they were.
- [ ] **7.8 Economy v4, "the forgiving economy".** Approved 2026-10-08 (`docs/prompts/ECONOMY_V4_PLAN.md`;
  numbers in `docs/ECONOMY.md`). Built on branch `economy-v4` (Lune-tested, 2026-10-08): the
  Mystery block's 5-press climb from Standard with pity for every Mystery block, a Secret in
  every odds row, the 10-step daily win track, the 08:00 UTC reset, the first week (7 login
  days within 14) and later weeks, VIP's daily Rare block, the restock with Mythic blocks and
  announcements, the Grand Opening's copy caps and guarantee, the launch bonus, the 19 R$
  Starter Pack, the skip by time left (4 / 9 / 15 R$), live block worth in trading, every
  Robux price lowered, save version 9. Done means: merged, the prices live on Roblox, and a
  Studio check of the shop prices, the Mystery screen, the rewards, the timers and the skip.
  Still to come with the GUI: the screens listed in the plan's hand-off (section 18). Planned,
  not built: the Lucky Shot, Golden Shot, Lucky Rain and the stay bonus (`Config.Planned`).
- [ ] **7.9 Economy v5, "every block climbs".** Approved 2026-10-09
  (`docs/prompts/ECONOMY_V5_PLAN.md`; numbers in `docs/ECONOMY.md`). Built on `gui-v4`
  (Lune-tested, 2026-10-09; backup branch `before-economy-v5`): one climb ladder for every
  block (the name is the floor), the Grand Opening Luck, pity 10 / 40 with a head start,
  unclimbed and climbed blocks (save version 11), the win track's 4 blocks and $1,000 steps, the
  Week One Cue on the first week's day 7, the new rewards, the restock's 2 slots (the first
  Epic or better), the Mystery block at $14,900 (5 for $66,900), the 1 R$ skip (made on
  Roblox), "Open all", the "1 in N" messages, climbed blocks in trades and the model doing v5.
  The Robux pass is approved and live on Roblox (2026-10-09: Mystery 7 R$, the 29 R$ 5-pack,
  restock 39 / 149, later weeks' Claim All 79 / 69 / 35). Done means: every screen
  (`docs/prompts/ECONOMY_V5_GUI_PROMPT.md`, spec in `docs/prompts/ECONOMY_V5_HANDOFF.md`),
  merged, and a Studio check of a Mystery block and a tier block from a win, the restock, the
  Mystery band, Free Reward's first week, a trade of a block, the 1 R$ skip and the luck's odds.

---

## Stage 5: The first-time tutorial, the funnel and release

  Progress 2026-10-03 (the Economy lane): the server side (invite, offers, both accept, a
  3-second wait, the atomic swap with a ledger that replays a lost trade), anyone in the
  server, cues and ready cases. Still to do: the trade screen (GUI lane) and a real
  two-player trade.
  Progress 2026-10-03 (the GUI lane): the trade screen, started from the player list. Still to
  do: a real two-player trade.
- [ ] **4.1 The hub map.** The rooftop pool club (GDD section 10): the map, the tables in it,
  lighting, sittable seats and zone signs.
  - [x] The rooftop pool club: the map, the tables in it, the day and sunset lighting, sittable
    seats (2026-09-26; `docs/prompts/ROOFTOP_MAP_PROMPT.md`, all four checkpoints approved).
  - [ ] Still to do: zone signs. The snack counter is parked (GDD section 18). The pro-lobby
    door comes with the pro lobby after release (6.3); whether a locked door stands on the
    roof at release is Open (GDD section 10).
- [ ] **8.1 First-time playthrough (the tutorial).** Hidden popup, disguised PC that walks in
  and blunders, ghost break guide, first-win cue box, Unranked to Bronze (GDD section 14).
  Progress 2026-10-03 (the Tutorial lane, merged into `release`): built in the real public
  server, all ten steps of its brief. Still to do: the 8-ball in the tutorial, the published
  game's teleport halves of game 2, phone and gamepad.
- [ ] **8.2 Analytics funnel** with Roblox's built-in analytics.
  Progress 2026-10-03 (the Tutorial lane): onboarding (22 steps), skip/cancel, shop, Case
  Drop and spin funnels in `src/server/Funnel.luau`. Still to do: check them in the Creator
  Dashboard after publishing.
- [ ] **4.4 Performance pass.** Low-end phone with sixteen busy tables: streaming, LOD, shadow
  and light budget, no stutter.
- [ ] **8.3 Name, icon, thumbnails, game page.** Final name check.
- [ ] **8.4 Public release.** Watch where players quit. Everything above must exist.

**RELEASE.** Review what players love and ignore. That decides the order after the first weeks.

---

## After release

### About one to two weeks after release

- [ ] **6.3 Pro lobby.** Separate place with a teleport door, Diamond I and above, Difficult
  and Challenger only.

### Ultimates (in the release; built on branch `ultimates`, 2026-09-28)

The rules, the 13 ults and the spin screen: GDD section 9; every number: ECONOMY 11.7-11.8.

- [x] **3.1 Ult framework.** Equip one ult; the ult bar and its fill rules (your own balls,
  trickshots, the opponent's balls weighted by how far behind you are, a small per-turn
  trickle); the full bar shakes; activate before the shot with a short cutscene and an "ULT"
  mark on the cue ball; server-validated; developer flag that unlocks every built ult for
  tests. Done means: a placeholder ult fills in a test match, shakes when full, is used before
  a shot and empties, and a player 4-5 balls behind has a full bar.
  Done 2026-09-28 (branch `ultimates`, overnight): the bar (G, a tap or ButtonX), two ults a
  match, the 1.6 s manga cutscene for everyone at the table, then a 1 s arming wait with the
  clock paused; the fill model checked (a player 4 behind fills from level, both players use
  an ult in 85% of games at worst); Ults On and Off pools in the global queue; `/ulthelp`.
  Checked in Studio on PC and phone sizes.
- [x] **3.2 Magnet** (the starter ult everyone gets). Done 2026-09-28: a near miss within about
  one ball width of a pocket drops (88% of the closest misses, none past 2.5 widths); only
  your own balls, never the cue ball; its armed rings, pull beams, pocket ring and sounds.
- [x] **3.3 Eagle's Eye.** Done 2026-09-29 (branch `abilities`): the shot's full path while
  aiming, both balls through every cushion.
- [x] **3.4 The rest of the 13** as the designer picks them (catalog rows exist, as
  placeholders that neither roll nor play until built).
  Done means (3.2 to 3.4): each creates at least one "did you see that" moment in a test match
  and PC matches still feel fair.
  Done 2026-09-29 (branch `abilities`, `docs/prompts/ABILITIES_PROMPT.md`): all 13 built with
  their rules (GDD section 9), 3D icons, Blender-made effects and sounds; Magnet reworked; the
  skill rule (the opponent's balls at half strength); each measured by the value harness and
  tuned to its rarity (ECONOMY 11.8: Common to Epic 49-51% against Magnet, Legendary 55-56%,
  Mythic 56%); played through in a real match on PC and the phone emulator; the spin screen is
  live (`Config.Ults.ScreenLive`). A real phone, a controller and two real players are still a
  hand check.

**FRIEND TEST 3.** Do ults bring matches back without deciding them? Tune the bar.

- [ ] **7.4 How ults are earned.** Decided 2026-09-28 (GDD section 9): a spin screen rolls a
  random ult into one of three slots (odds, pity at 100, Lucky Spins), with spins earned
  (starter, daily free spin, rank-ups, streak day 7, playtime, codes) or bought for money
  ($1,750) or Robux. Progress: the server, saves, rewards and chips are built and checked; the
  spin screen itself is in progress.

### Later

- [ ] Collectible table skins: table model pipeline with a strict per-table budget, the host's
  table used for the match, rare ones with VFX, a table loot box and limited tables; tradable.
- [ ] Seasons and themed limited sets.
- [ ] Private friend-locked tables, party up.
- [ ] Replay and clip feature; creator outreach.
- [ ] New modes, new table types.
