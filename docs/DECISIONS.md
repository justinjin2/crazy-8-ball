# Decisions

Dated one-liners with the reason. This is the only place that records when something was
decided; the GDD and roadmap state the result without dates. Newest at the bottom.

- 2026-09-18: Custom physics instead of Roblox physics. Precision, determinism, and abilities
  need hooks inside the simulation.
- 2026-09-18: 9 ft table at 0.16 studs per inch; balls 1.3 in radius. Readability on phones.
- 2026-09-19: One 3D aim camera, no top-down toggle. Top-down made the 3D pointless.
- 2026-09-19: Orbit camera opposite the aim with automatic whole-table framing; zoom is one
  continuous axis down to a low "down the cue" view. Solved the "aiming backwards shows floor"
  problem without going top-down.
- 2026-09-19: Shot camera pulls out to the whole table instead of following the cue ball.
  Trickshots on other balls were invisible.
- 2026-09-19: Guideline drawn as a one-ball-wide corridor. The centre line alone read wrong
  from the low view.
- 2026-09-19: Sphere-mesh balls with baked textures instead of decals on Ball parts. Decals
  blurred up close.
- 2026-09-19: Imported Blender table model and bright lounge package replace the parts-built
  table and the planned dim room.
- 2026-09-20: Working name Crazy 8 Ball. Currency is "money". No loser finisher effect.
- 2026-09-20: Next milestone is the lounge with twelve server-owned tables (Roadmap 1.5), then
  spin, sound and rules. The server move is needed anyway and the map is built.
- 2026-09-20: Shop, inventory, save data and the first-time flow must exist before the game is
  public; Founder's and Beta items go on sale at that release.
- 2026-09-20: All three difficulty levels are built early as a host option with no lock until
  ranks exist; then the host is locked by peak rank and guests get a warning with Play anyway.
- 2026-09-20: Ability cooldowns count in the user's own turns; the framework supports
  opponent-targeting and opponent-turn abilities from day one.
- 2026-09-20: Solo, 1v1, 2v2 and 3v3 are all in the release; table code is team-shaped from
  the start.
- 2026-09-20: Join by stepping on a floor pad with sound, VFX and a green indicator, replacing
  the hold-E prompt.
- 2026-09-20: Open table after the break; 8 on the break is re-spotted; timeouts are fouls,
  two in a row forfeit; leaving is a forfeit.
- 2026-09-20: PC opponents are labelled everywhere except the scripted first match, which uses
  one disguised PC.
- 2026-09-20: One visible rating number with divisions I (bottom) to V (top), peak rank saved,
  difficulty multipliers, Classic and PC gains capped above Diamond.
- 2026-09-20: One match type: every match against a person or PC changes rating; the old
  "ranked = self-help abilities only" rule is deleted.
- 2026-09-20: Anti-boost by opponents-played-today counters: rating shrinks to zero, money
  shrinks but never to zero, no friend exemption.
- 2026-09-20: Money packs are sold for Robux; all boxes, gacha and trading follow Roblox's
  paid-random-item rules (odds shown, restricted-region catalog).
- 2026-09-20: Unified item catalog; unique IDs with serials per cue and table; abilities are
  account-bound flags; cues and tables trade, including VIP and starter-offer ones; money
  never trades.
- 2026-09-20: Every table collectible is its own full 3D model under a strict budget.
- 2026-09-20: All ages, R6 and R15 allowed, non-alcoholic snack counter, no wagering.
- 2026-09-20: First-time flow per GDD section 14; starter ability Magnet Pocket, kept forever;
  at release players own only the starter and roll the rest.
- 2026-09-20: Rematch and Leave on the post-match screen with a 15 second window.
- 2026-09-20: Aim angle and ball-in-hand position replicated live to opponents and spectators.
- 2026-09-20: Gamepad support is built and checked in every milestone from now on; the pro
  lobby is a separate place reached by teleport.
- 2026-09-20: Reminders trigger on menu open and window focus loss (subtle in-game toast), not
  inside Roblox's own menu.
- 2026-09-20: Codex also writes game code; both tools follow the same rules file (AGENTS.md is
  a symlink to CLAUDE.md) and update STATUS.md. Private GitHub remote; place file committed at
  each milestone; binaries stay in plain git with hygiene rules.
- 2026-09-20: Spectators sitting on lounge chairs get free look only; table cameras wait for
  Roadmap 2.3. Closes the open question in GDD section 6.
- 2026-09-20: Table position and yaw live in a pure `Placement` module, not in TableBuilder.
  A pool table is symmetric end to end, so a yaw sign error builds a table that looks right
  and plays mirrored; only a Lune test can catch that.
- 2026-09-20: Balls are turned by the simulation's own angular velocity, never by distance
  travelled. The old way hid the skid, hid side spin, and spun balls wildly down pockets.
- 2026-09-20: Clients step a live simulation from the render loop instead of calling
  `Simulation.run` up front, which blocked a whole frame per break and built a frames table
  of several megabytes. `run` keeps its frames for the tests; the server gets `runHeadless`.
- 2026-09-20: Join by stepping on a floor pad, polled on the server at 5 Hz with a three
  poll dwell. Touched misses a player who stands still; the dwell stops someone crossing a
  pad on the way somewhere else being dragged into a seat.
- 2026-09-20: Pads sit 14 studs out from the table centre, clear of where the shooter
  stands. At 11 studs the shooter was standing on the pad and could never leave.
- 2026-09-20: Clients replay a shot from the server's POST-STRIKE cue ball state, not from
  {angle, power}. Cue.strike goes through libm sin/cos/pow, which are not correctly rounded,
  so re-striking on each client risks a one ulp difference and therefore a different break.
- 2026-09-20: Every shot carries a checksum of the server's final positions and clients warn
  when their replay lands elsewhere. Determinism is measured, not assumed.
- 2026-09-20: Only the nearest few tables draw their balls (a renderer pool). Twelve racked
  tables is 192 ball meshes for something that is a few pixels across the room.
- 2026-09-20: Aim is replicated as one batched unreliable message per tick for all tables,
  not one per table per player.
- 2026-09-20: Gamepad power is on the right trigger, not zoom. A trigger's travel is a power
  bar; mapping an analog axis to zoom wastes it. Departs from the GDD's "or triggers" aside.
- 2026-09-20: Remote players' bodies are not posed for watchers; only their cue is
  replicated. AvatarPose anchors individual limbs, which does not replicate reliably from
  the owning client. Body posing for watchers is deferred to Roadmap 2.3.
