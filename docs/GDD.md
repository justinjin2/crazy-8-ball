# Crazy 8 Ball: Game Design Document

> **2026-09-22 multiplayer update:** [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md)
> is the agreed design for this update. It supersedes older turn rotation, break,
> assignment, 8-ball, timer, departure/surrender and reward details. Results are match-only;
> bots, abilities, difficulty and progression remain future work. Solo is built (spec, Solo).


Working name: **Crazy 8 Ball** (final name check is a release task). Rewritten 2026-09-20 from the
designer's full idea dump plus the earlier GDD. Every section has **Decided** (build to this) and
**Open** (not yet decided; do not guess, ask). Numbers marked *(tune)* live in `src/shared/Config.luau`
and are playtest values, not design decisions. Ideas that are not scheduled live in section 18.

## 1. The pitch

A 3D, satisfying, chill, competitive and social 8-ball pool game on Roblox. Your own avatar lines
up and plays every shot in a bright pool hall. It feels as crisp as GamePigeon 8-ball, with a
twist: every player brings one ability that helps them or sabotages the opponent. Every ball you
pocket pays money, win or lose. Money opens loot boxes of rare cues, ranks climb from
Bronze to Reyes, and the rarest items can be traded. Built for phones first, with PC and console.

The goal is longevity: the respected, premier 8-ball game on Roblox that people come back to,
not a trend that dies.

## 2. Audience and why Roblox

**Decided**
- Three audiences at once: adults who know pool and want a chill, skill-respecting game; pool
  lovers wanting a fresh 3D take; kids (the platform majority) who come for the abilities and
  the collecting. The appeal for all of them is the same: satisfying sound, visuals and
  gameplay, replayability, the gacha and economy, socialising, and competition.
- Why Roblox: it is the only platform where the player's own avatar plays the shot (2D pool
  games and first-person 3D ones cannot), the avatar catalog already exists, and its biggest
  markets (US, Philippines, Europe) are pool countries. Pool needs almost no language, so the
  game crosses language barriers by design.
- **All ages.** The game is not age-restricted. Both R6 and R15 avatars are allowed.
- Mobile first, PC and console (Xbox, gamepad) supported from the start. See section 5.

**Open**
- Whether age-verified adult purchases earn the higher DevEx rate under the chosen settings.
  Verify on Roblox's current policy page before writing any rule about it.

## 3. Design pillars

Every feature is checked against these. If it serves none, it waits.

1. **The shot is the game.** Aiming, striking and sinking must feel and sound incredible with
   nothing else in the game.
2. **Always something happening.** Fast turns, constant feedback, a reward for every ball.
   Always give the player something to do.
3. **Your avatar is the star.** You see yourself line up, shoot and celebrate.
4. **Skill respected, chaos welcome.** Abilities are balanced, never banned. Skill still wins
   over time, and the ranks make that visible.
5. **Nobody leaves empty-handed.** Losing still pays. Casual players can still get rare things.

## 4. Core loop

**Decided**
- Inside a match (seconds): aim, shoot, watch, feedback (sound, popup, money), next turn.
- Across matches (minutes): play, earn money for every ball plus bonuses, spend money on loot
  boxes for cues, roll abilities, rank up, trade, repeat.
- The currency is called **money** everywhere (UI, code, docs). Never "coins".

## 5. Platforms, controls and camera

**Decided**
- **Every feature works on phone, PC and gamepad, and is checked on all three in every
  milestone.** Every control works by touch, mouse and gamepad; a drag needs no button twin
  (changed 2026-09-26: the Fine controls panel is gone).
- PC: hold click and drag left or right to aim, scroll wheel to zoom, pull the power bar on the
  right down and release to shoot, click the cue-ball icon to set spin.
- Mobile: swipe left or right to aim, pinch to zoom, pull the power bar with a thumb, tap the
  cue-ball icon for spin.
- Spin UI: a larger cue-ball button sits at the left middle. Drag anywhere across the white
  selector to choose spin; its full disc represents the available physics range. Keep only
  Center and Done, with light background dimming and no title, hint, box or arrow buttons.
  Use a broad red marker on the selector and a smaller one on the left toggle. Clicking
  outside closes it and retains the selection. Gamepad stick controls remain.
- **Cue angle (jump shots, decided 2026-09-24):** a vertical slider beside the white ball in
  the spin panel sets how steeply the cue is raised, 4 degrees (normal) to 60, in whole
  degrees. Tap or drag the track; the arrow keys and L1 + left stick (or D-pad) step it. A
  raised angle shows under the spin toggle and resets to 4 after every shot, like spin.
  Raising the cue and striking down bounces the cue ball off the slate: it can jump a
  blocking ball, and too much power sends it off the table. The guideline follows the jump:
  a small ring where it comes down, and a red cross where it would fly off.
- Gamepad: left stick aims, up and down on the right stick (or triggers) zooms, a hold-and-
  release button shoots with power, the spin selector is a stick target. Exact bindings are a
  milestone task, not a design question.
- Aim ticks: a soft tick sound on every step of rotation; a stretch sound while pulling the
  power bar back (GamePigeon style, original audio).
- **Camera:** one 3D orbit view (no toggle; top-down only while calling the 8-ball pocket). It
  sits on the side opposite the aim and looks across the table along the aim line, framing the
  whole table automatically for any ball position, aim and screen shape. Zoom is one continuous
  gesture from "whole table" down to a low "down the cue" view behind the ball. Fully zoomed
  out always shows the whole table.
  - The **home view** is the middle of that zoom: behind the cue ball, halfway between the
    whole table and the down-the-cue view (`Config.Camera.View.ZoomDefault`). Every turn
    starts there and the camera always comes back to it.
  - After the strike the camera holds a beat (less if a ball is about to leave the screen),
    pulls out to the whole table so every ball's path is visible, then eases back to the home
    view.
  - Cue-ball placement (break and ball in hand) happens in this 3D view; the camera holds still
    while the ball is dragged.
  - The one exception: the shooter's view goes top-down to call the 8-ball pocket, and returns
    to the home view once the pocket is called.
  - Only the shooter's camera is taken; everyone else, including during the coin flip, keeps
    the ordinary Roblox camera.
  - **The shooter's body** (decided 2026-09-24, reworked 2026-09-25): avatars stay normal
    Roblox size (R15 and R6), the cue is always its own length (about 7 studs, no extension)
    and there is **no rake**. Only the body's pose and position change to reach the ball. It
    is not tied to the cue line: like a real player it stands wherever it reaches, for
    example at the side rail beside a ball whose shot runs along that rail. Poses: standing
    on the floor, leaning further in, stretching over the rail with the belly on its edge
    (always both feet planted on the floor: no floating feet, no lifted leg), kneeling on the
    table, and as a last resort kneeling up on the rail top. A foot on the floor only reaches
    so far onto a table this size, so far-in shots are taken kneeling on the table (accepted
    as a bit of humour). Each pose is shaped by how far the body turns to the cue, whether
    the cue runs under the chin or by the hip, and how far it leans. The body climbs only
    when it must: about 48% of shots from the floor, 4% stretching and 48% kneeling on the
    table for the default body. The head is the avatar's own, measured, and stays clearly
    above the table (big hats and costumes may still dip in). Both hands are always on the
    cue: the grip arm reaches back to hold the cue near its butt, and the bridge arm reaches
    out nearly straight toward the ball (the bridge on the cloth or the rail top under the
    cue); the head looks at the cue ball. Smaller or R6 bodies cannot reach about 2% of shots
    (a ball frozen to a cushion under a steep jump cue): they stand, the hands as near the
    cue as they get. The cue tilts up to clear a rail or a ball behind the cue ball: the tilt is visual
    only, the physics stays at 4 degrees.
  - The cue **winds up** with the power pull, and everyone sees it; release plays a quick
    stroke through the ball. Once the stroke has played (about a second) the shooter can walk
    again while the balls roll, the shot camera still following the balls until they stop
    (designer, 2026-09-25). If it is still their turn they go back into the aiming pose from
    wherever they walked; if not, the normal camera comes back where they stand.
  - The shooter sees their own body mostly transparent (and fading as the camera nears it);
    everyone else sees it fully, posed.
- **Guideline** (Classic difficulty): a corridor one ball wide from the cue ball to first
  contact, a ring at the contact point, a short line for the object ball and a short line for
  the cue ball's deflection. The two short lines scale with how full the hit is (GamePigeon
  style): the object ball's line is longest on a straight-on hit and shrinks as the cut
  thins (cos of the cut angle), the cue ball's line does the reverse (sin). See section 7 for the harder difficulties.
- Balls not in your group are marked with an X and your group gets a slight highlight, drawn on
  each viewer's own screen. A HUD shows which balls you have pocketed.
- **Physics realism choices (2026-09-22, implemented):** keep one power bar
  reaching 30 mph, with no separate break control. Classic shows the predicted cue-ball
  launch direction. Side spin does not bend it (2026-09-23): no squirt and no swerve, so the
  cue ball leaves along the aim and runs straight to first contact; side spin acts only at
  contacts (cushion rebound, throw, spin transfer). Use regulation 2.25 in balls in the
  physics with visual scaling for readability. Cue elevation is 4 degrees unless the player
  raises it for a jump (2026-09-24, above), and all collectible cues have identical physics.
  Ordinary shots stay on the cloth: only the very top of the power bar hops the cue ball a
  whisker, and only rarely does that pop it off a nearby ball and off the table. Object
  balls never leave the cloth. Physics milestones D-F implement these
  choices. The table is being remade (2026-09-24, section 16) from the physics geometry, so
  its drawn pockets match the physics exactly: regulation pro cut, corners 2.0 and sides 2.2
  ball widths.

## 6. Modes, tables and joining

**Decided**
- Players spawn in the hub and walk to any free table. There are no menus to find a game.
- **Every table plays one mode** (changed 2026-09-26; for a day any table played any mode from
  one long queue box). Of sixteen tables, **ten are 1v1, four 2v2 and two 3v3**, the 1v1
  tables nearest the spawn and the 3v3 at the back.
- **Joining: step onto the table's queue pad.** Each table has one glowing rectangular pad in
  front of it, lying along the long side that faces the entrance (changed 2026-09-26 for the
  rooftop map; a round pad was tried the same day and dropped), longer for bigger modes,
  holding both teams (2, 4 or 6). Its mode is written big on it with STEP IN or the count;
  outlines pulse out of it and a big arrow bobs over it while it has room. Joining is instant: the host menu pops up the moment you step on. Stepping on plays a
  sound and a VFX and the rim turns green so everyone can see someone is queueing. There is no
  accept step; anyone may step onto a waiting pad with room, and walking off (or Leave) leaves
  at once. Everyone else can stand around and watch. The sign over a table (mode, host, count,
  abilities, difficulty) shows only when you walk right up to it.
- The first person on is the **host**. Everyone on the pad sees the **queue menu**: the host's
  name, how many are on the pad, the **difficulty** (Classic, Difficult, Challenger; Classic
  preselected) and **abilities** on or off (on by default; the toggle does nothing until
  abilities exist). Only the host can change them or press **Start**. If the host leaves, the
  next to arrive becomes host and the settings stay; they go back to Classic and on when the
  pad empties and after every game.
- **Start** needs the pad full; the game begins at once, no countdown: straight to the coin
  flip. **Teams go by arrival**: the first on (the host) is team A, the next team B, and so on
  alternately. Until the pad is full the menu says how many more are needed. Alone on a **1v1
  table**, Start offers **Play solo** (starts immediately) and **Play against PC** (does
  nothing until bots exist); the 2v2 and 3v3 tables have no solo. There is no automatic
  start against PC.
- Every match is played on the one standard table model, in one of its looks (section 16).
  Collectible table skins are parked until after release (section 18).
- **Modes at release: Solo, 1v1, 2v2, 3v3**, each with friends or PC fill.
  Solo: normal rules with no opponent; the first legally pocketed group is cleared first, then
  the other group, then the called 8. A foul gives yourself ball in hand; the 8 early, on a foul
  or in the wrong pocket loses (changed 2026-09-23; it no longer re-racks). No shot clock, money
  per ball, no win bonus, no rank change.
  Teams: teams alternate turns and teammates rotate (A1, B1, A2, B2), teammates share a group,
  each player uses their own ability, the shot clock is per shooter, a whole team must agree to
  forfeit, PC can fill any seat, team matches are rated by team average.
- Before any two-sided match a short **versus screen** shows each player's avatar, cue and
  rank. Never for Solo.
- After a match the post-match screen shows **Rematch** and **Leave**. If both sides press
  Rematch within 15 seconds *(tune)* the same match restarts with the same host and settings
  and a fresh coin flip; otherwise the table frees. PC and Solo matches get an instant Play
  again.
- One **Find another server** button, hidden during a match. Cross-server and worldwide
  matchmaking are not planned for release (section 18).
- Servers hold about 30 players *(tune)*. Every table seats 1v1, 2v2 or 3v3, decided by who
  is in its box. PC never plays PC.

- **Spectator seating:** the chairs and sofas are sittable, and sitting is free look - the
  player is seated and the camera is left alone. Watching a table through its own camera is
  a separate feature and waits for spectating proper (Roadmap 2.3).

## 7. Rules

**Decided**
- Standard 8-ball. A coin flip decides who breaks (the first-time player always breaks, see
  section 14). The table stays **open after the break**: the first ball legally sunk after the
  break decides solids and stripes. Sink your ball, shoot again; miss, the turn passes. Fouls
  (scratch, wrong group first, no ball hit) give the opponent **ball in hand anywhere**. Clear
  your group then sink the 8 to win. Sinking the 8 early, or scratching on the 8, loses the
  game immediately. The 8 sunk on the break is re-spotted and the same player continues. No
  calling pockets.
- **A ball off the table** (jump shots, decided 2026-09-24, standard rules): a foul with ball
  in hand. An object ball that flies off goes back on the foot spot (or the nearest free
  spot). The 8 off the table loses the game, except on the break, where it is re-spotted
  (and it is still a foul).
- **Shot clock** about 20 seconds *(tune)*. Zero = foul with ball in hand. Two timeouts in a
  row = automatic forfeit *(tune)*.
- **Forfeit** button, costs rating, behind a confirmation that warns "you will lose rating".
  Leaving or disconnecting mid-match is an immediate forfeit: the opponent gets the win and
  reward (subject to the real-match rules in section 13), the table frees, no PC takes over.
- **Three difficulty levels, chosen by the host for the whole table** (both players see the
  same guideline):
  - **Classic** (default, recommended): full guideline as in section 5.
  - **Difficult**: the aim line only (the corridor to first contact and its ring), no
    object-ball line, no deflection or bounce line, no jump landings.
  - **Challenger**: no lines at all (changed 2026-09-25; it used to be a short aim stub).
  All three exist from the start. Until ranks exist there is no lock. Once ranks exist, the
  host cannot pick Difficult or Challenger until their peak rank unlocks them *(tune,
  placeholder Diamond I for both)*; a guest below that rank sees "Your rank is not qualified
  for this difficulty" with a Play anyway button. Unlocks never re-lock. Ball highlights and X
  marks stay on in every difficulty.

## 8. Feel: the satisfying layer

This is pillar 1 and 2 in practice. It is part of the core, not polish for later.

**Decided**
- Sounds: cue strike, ball-on-ball clack scaled by speed, soft rail thud, deep pocket drop, aim
  ticks, power-bar stretch, UI clicks. ASMR quality, original or licensed audio only.
- A small VFX and a rewarding sound on every pocketed ball, bigger and flashier for the 8.
- **Streak:** the first pocketed ball in a turn starts x1, the next x2 "on fire", x3 blue fire,
  and so on, with rising sound pitch and a money multiplier.
- **Trickshot bonuses:** extra money and a popup for bank shots (one or more rails before the
  pocket), combos (your ball knocks another in), and multi-ball shots ("Double", "Triple").
  Lucky sinks count and get the full celebration.
- "Nice shot" popup with a dopamine sound, shown on about half of good shots *(tune)*.
- Victory screen for the winner. The loser is simply shown as having lost. No finisher effect.
- Emotes during the opponent's turn for players and spectators.

## 9. Abilities

**Decided**
- Every player equips **exactly one** ability per match. Abilities are balanced: they add fun
  and moments worth clipping, they do not decide matches by themselves. At the strongest they
  can guarantee one ball goes in or stop the opponent pocketing one ball.
- Every ability declares **who it targets** (me or opponent) and **when it may fire** (my turn,
  opponent's turn, any time). The framework supports all of these from day one.
- **Cooldowns count in the user's own turns** ("ready in 2 turns"), scaled to the ability's
  power: weak abilities return fast, strong ones rarely.
- Abilities are on by default; the host can turn them off for a match. Abilities-off matches
  still count for rank.
- **At release every player has one starter ability: Magnet Pocket**, kept free forever. All
  other abilities come from the ability gacha (section 12). Before release, friend tests may
  unlock every built ability with a developer flag in Config.
- First three to build, in this order: **Magnet Pocket** (choose a pocket, for one shot it
  gently pulls your balls toward it; a nudge that rescues near misses, never a vacuum),
  **Time Stop** (freezes the shot clock for one turn with an original dramatic effect and
  sound; no copyrighted audio), **Super Bounce** (rainbow cue ball that loses almost no speed
  off rails for one shot; built into the physics). Every later ability follows the same
  framework. Rarities match the item rarities (section 12).

**Open**
- The full ability list and how many exist at release.
- Exact cooldown lengths per ability *(tune)*.

## 10. The hub and the world

**Decided**
- **For now, a plain baseplate**: sixteen tables in a grid of four by four (ten 1v1 at the
  front, four 2v2, two 3v3 at the back; section 6), the left two columns in the regular
  lobby's wood looks and the right two in the pro lobby's black looks (section 16), so every
  combination can be tried; the spawn in front of them (designer, 2026-09-26).
- Chairs and sofas are sittable. No alcohol anywhere. (The snack counter is parked, section
  18.)
- **Pro lobby:** a separate Roblox place, reached by a teleport door, for Diamond I *(tune)*
  and above, where only Difficult and Challenger are available. All its tables have black frames
  (blue felt 1v1, red 2v2, charcoal 3v3; section 16); the rest of its look is decided later (a dim, moody neon room is the candidate).
- A player's win streak shows above their head, and their country flag next to their name.

- **The hub map is an open-air rooftop pool club** (designer, 2026-09-26), matching the
  concept art in `assets/map/reference/`: a city skyline on the left and a tropical coast with
  green mountain islands on the right, as seen from the entrance. The brief is
  `docs/prompts/ROOFTOP_MAP_PROMPT.md`. Nothing carries over from the removed maps.
  - All 16 tables have the regular lobby's wood frames: green felt 1v1, red 2v2, charcoal 3v3
    (section 16; the black-frame looks stay for the Pro lobby). The tables turn sideways like the art: long sides face the entrance, four across
    and four deep.
  - Day and Sunset only, no night, the same for everyone on a server: about 10 minutes of
    day, a 1 minute fade, 5 minutes of sunset, a 1 minute fade back *(tune)*.
  - In: the pergola lounge with couches, a fire pit, a grand piano, planters, palms,
    lanterns, umbrella seating and the glass railing. Out: the art's infinity-pool strip,
    banners and pink light pillar, and (for now) the snack counter.
  - On the map every queue pad sits **in front of its table**, centred on the long side that
    faces the entrance (designer, 2026-09-26). The pad's shape may still change; the table
    grid is computed from its size, so it re-spaces itself.
  - The sides follow the day view: the city side has planters, palms and lanterns; the ocean
    side has umbrella sets with loungers and sofa groups along the railing.
  - The grand piano is the lounge's centrepiece, centred at the back under the pergola, the
    player at the keys facing the tables; a sofa group either side of it.
  - The glass railing round the roof reaches a character's head (5 studs).
  - The city is densest and most detailed in the view the player gets on arrival (ahead and
    to the left); behind the spawn, the stair side, it stays low and sparse.
  - The entrance stair walks down to a small dead-end landing.
  - Props: seats, steps and railings are sized for the player; planters, palms, umbrellas and
    the pergola about 1.4 times that, so they hold their own beside the big tables; the
    spacing follows the art's layout.
  - Calm and clean for kids: bright saturated colours, wide walkways, props in a regular
    rhythm. Everything we ship stays under about 512k triangles, so the whole game stays
    under 1 million with players in it.

**Open**
- The rooftop's exact dimensions, prop counts and palette: measured in the brief's Stage 0
  (`assets/map/Spec.md`), confirmed at its checkpoints.

## 11. Progression and ranks

**Decided**
- Tiers: **Bronze, Silver, Gold, Platinum, Diamond, Expert, Veteran, Master, Grandmaster,
  Reyes**. Each has divisions **I to V** (I is the bottom, V the top) except Reyes. Reyes is
  named after Efren Reyes (placeholder, check rights before launch).
- Players are **Unranked** until their first rated match, then Bronze I after one game.
- **Rank badges** are drawn (2026-09-26, `assets/ui/ranks/`): 1 to 5 stars show the division
  from Bronze to Diamond, 1 to 5 gems from Expert to Grandmaster; crowns from Expert up; Reyes
  and Unranked have one badge each. Look and shine: `docs/UI_STYLE.md` sections 6 and 7.
- **One visible rating number** drives the rank; bands per division live in Config and widen
  higher up. Rank follows the number both ways with a floor at Bronze I. A **peak rank** is
  saved: rank-up rewards are granted once per division, difficulty unlocks use the peak.
- Every match against a person or PC changes rating. Solo never does. Beating a much higher
  rating pays more, a higher-rated player beating a lower one gains little.
- **Difficulty multiplies gains and losses** *(tune, placeholders 1x Classic, 5x Difficult,
  10x Challenger)*. Classic gains shrink to a trickle above Diamond, and PC matches give full
  rating only up to the top of Diamond and a fraction beyond, so Expert and above come only
  from the harder difficulties against people. PC skill scales with the player's rating.
- Bronze to Platinum is fast, Diamond is a buffer, and the top ranks are exponentially harder.
  Reyes should be held by a few dozen to a few hundred players depending on population.
- Rating is saved under a season label ("Season 0"); no resets at launch.

**Open**
- The rating formula, points per game and division widths *(tune)*: solve on paper, then test.

## 12. Economy

**Decided**
- **Money** is earned for every ball pocketed, more on streaks and trickshots, in every mode
  including Solo and PC. Solo and PC income slows after a daily amount *(tune)*, never to zero.
  Money farming with macros is not punished.
- **Difficulty multiplies money** (designer, 2026-09-26): 1x Classic, 1.5x Difficult, 2x
  Challenger *(tune)*, shown under each difficulty in the host menu
  (`Config.Difficulty.MoneyMultiplier`). This is separate from the rating multiplier in
  section 11.
- **Money packs are sold for Robux.** Because of that, every loot box, gacha and trade is a
  paid random item under Roblox policy: odds are shown on every box, and players in regions
  where paid random items are restricted get a direct-purchase catalog instead of boxes.
- **First release collectibles are cue skins only (decided 2026-09-23).** There are no table
  skins at release: every table uses the standard model. Table skins are parked in
  section 18 for after release.
- **A permanent loot box** bought with money, for cues. Goal at release: 30 cues. Rarities
  for everything: **common, uncommon, rare, epic, legendary, mythic, unique and VIP** (their
  order is Open; "ultra" is dropped). Colours in `docs/UI_STYLE.md`. Rarer cues have special
  trail and pocket VFX.
- **A cue carries its own effects.** Every cue defines the cue ball's TRAIL and the burst
  when a ball is pocketed, so the cue you equip changes how the table looks while you play,
  not just what the stick looks like. The default cue and every common one use the same
  minimalist trail: a thin white translucent wisp, like wind off the ball. Rarer cues
  replace it with their own trail and their own pocket effect, and that pairing is the main
  reason to want one. Effects are catalog data (a named style), never code per cue.
- **Limited seasonal boxes** that leave and may or may not return. Season 0 has one, for cues.
- **Shop** with high-priced, quantity-limited items that sell out and become limited forever.
  At release: a Founder's cue (about 25 to 50 copies) and a Beta cue (about 500 to 1000
  copies). All economy screens live under one menu.
- **Ability gacha:** spins cost Robux (packs of 1, 5, 10, 50) and there is one free spin per
  day. You keep every ability you roll; duplicates give spin credit that only buys more spins.
- **VIP** (one-time pass): 2x money, an exclusive cue, other perks. Never better odds.
- **Starter offer:** a cheap cue for each player's first three days *(tune)*.
- **Items:** one catalog for cues and abilities (stable id, type, rarity, model, effect); the
  type field leaves room for table skins later. Every cue is a unique object with its own ID
  and a serial number for limited items. Abilities are owned flags. **Cues can be traded,
  including VIP and starter-offer ones. Abilities are account-bound. Money is never traded.**
- **Cue models:** every cue is its own small mesh plus a named effect style. Hundreds are
  expected, added as data rows plus assets.
- **Shop, inventory, save data and the first-time flow exist before the game is public.**

**Open**
- Money per ball, box prices, drop odds, pack prices *(tune)*: research other games first.
- The order of the rarities (where mythic and unique sit), and whether VIP is the top
  loot-box rarity or only for VIP-pass items (the VIP pass above has an exclusive cue).

## 13. Fair play and security

**Decided**
- The server owns every match, validates every shot and ability, and never trusts the client.
- **Real matches count, rematches are unlimited.** Anyone, friends included, can play the
  same opponent as many times as they like. A match pays rating and money (scaled by the
  rating difference as in section 11) as long as it was a real match: it lasted longer than
  **one minute** *(tune)* of match time and ended by play, not by a forfeit. The server
  tracks match time from the break to the final ball, and only the server decides whether a
  match was real.
- **What is not a real match:** the forfeit button, leaving or disconnecting, and sinking the
  8 to end the game while the match is still under the one-minute mark (that is treated as a
  deliberate forfeit; after the mark an early 8 is just a lost real match). The forfeiter
  loses rating every time.
- **Forfeits against a repeat opponent give the winner nothing.** A forfeit counts for the
  winner (rating, win, money) only the first time against that opponent; every later forfeit
  by the same opponent adds nothing to rank, wins or money. Boosting therefore needs real
  matches, which is fine. No friend exemption. PC is exempt.
- Wins against PC are a separate stat and never count on the "most wins" board.
- No wagering of any kind (against Roblox rules).

**Open**
- How long "same opponent" is remembered for the repeat-forfeit rule (this server session,
  today, or forever).
- The one-minute mark *(tune)*: check it against how long a real break-to-8 game takes.

## 14. First-time playthrough and onboarding

**Decided**
- The first match: the queue menu is hidden. The new player joins a match against what looks
  like a real player and is actually a **disguised PC** (made-up name, never a real user's
  name; random avatar; a higher rank badge once ranks exist) that walks into the box from the
  edge of the player's view a few seconds after they arrive. They always break first. A
  passive, looping ghost animation shows pulling the cue back and moving the ball on the break
  line, and disappears on the first drag. No shot clock. They pocket a few balls, see the
  sounds and the money, and get to use their starter ability. The PC blunders and pockets the
  8 so they win early. Normal rules stand: if they lose, the same throwing PC repeats until the
  first win.
- **Stronger ball highlights for learning (2026-09-23):** during the first playthrough and
  tutorial, turn on `Config.Multiplayer.Style.StrongBallHighlights`. The player's balls get a
  vivid solid green outline, and the other group is washed grey, so "these are yours" is
  unmissable. Normal play keeps the subtle outline with nothing greyed (the designer's choice).
- **Longer guideline lines for learning (2026-09-23):** the tutorial and first playthrough use
  the longer object/cue lines (`Config.Guideline.TutorialStubLengthInches`, 16 in). Normal play
  uses the shorter `StubLengthInches` (8 in) to keep aiming a challenge.
- **First win:** a free cue box opened right on the post-match screen with a reveal (skewed
  toward rare, epic or legendary) and an Equip button, plus extra money.
- Unranked to Bronze after one game. The first opponent shows a much higher rank so the win
  feels earned. PC is labelled "PC" everywhere else; disguised PCs never appear on
  leaderboards and are stored as PC in match records.
- **Daily 7-day streak:** every day's reward is meaningful (day 1 a box, day 2 a rarer box,
  day 7 something great). A stay-long-enough playtime reward (for example a cue).
- **Reminders:** Roblox cannot put text inside its own leave menu, but the game knows when the
  menu opens (`GuiService.MenuOpened`) and when the window loses focus. Both trigger a subtle
  in-game reminder ("Come back tomorrow for your free rare box"). The same reminder sits on
  the post-match screen.
- A funnel is tracked with Roblox's built-in analytics: joined, reached a table, first shot,
  first pocket, used ability, won, opened box, equipped, second match.

## 15. Social

**Decided**
- Leaderboards: top rating, most wins against people (global, all-time, refreshed every few
  minutes), and a nation board by total wins. Country flag auto-detected from Roblox's region,
  changeable in settings.
- Per-player match history: totals plus the last 20 matches.
- Trickshot clips are the organic marketing: creator outreach once clips look good.

## 16. Art direction

**Decided**
- The hub's look is Open (section 10). Everything reads at phone size. Clean glossy balls (sphere meshes with baked
  textures). Effects (streak fire, sink bursts, rainbow cue ball) must read at phone size.
- **The table (2026-09-24):** one model styled on the Diamond Pro-Am 9 ft, with no brand name
  or logo. Game size and cloth height stay as they are; the rails are the Pro-Am's 7 inch
  rounded rails. Two-piece tapered legs with bolts, corner blocks, rail seams at the side
  pockets, a blank plate on the foot end for our own logo later, no ball-return window. Chrome
  caps on all six pockets, built as a removable part so the corners also look finished
  without them. Looks are a cloth colour on one of two frames, **satin black wood showing
  faint grain** or **red-brown wood**, chrome on both (changed 2026-09-26):
  - **Regular lobby, wood frames:** bright yellow-green cloth (the reference photo's hue at
    real-cloth brightness) on the 1v1 tables, raspberry red on the 2v2, slate charcoal on the
    3v3.
  - **Pro lobby, black frames:** bright blue cloth (photo-16 blue) on the 1v1 tables, and the
    same raspberry red and slate charcoal on the 2v2 and 3v3.
  - The red and charcoal were picked by colour difference against every ball so none blends
    in: a truer red hides the red and maroon balls, a darker charcoal the 8.
  - Until the hub map, the baseplate shows every combination (section 10). The cloth is a fine
  repeating texture tinted per look, lightly played: a faint break line, a rack patch, chalk
  near the pockets and a spot sticker.
- UI: clean, thumb-friendly, icons before words. All text lives in one strings module; Roblox
  automatic translation is switched on at release; no hand translation before then.
- **UI style (`docs/UI_STYLE.md`):** cartoony and bubbly, white panels, Fredoka One for all
  text, white text with a dark outline, money shown as a stack of green cash.

## 17. Data and engineering principles

Design-level rules; the technical detail is in ARCHITECTURE.md.
- Modular systems that can be tweaked without rewrites; every tunable in Config.
- Built for hundreds of cues: items are data rows plus assets.
- Session-locked, versioned player saves with loss prevention from the first saved money.
- Track important metrics, especially the first-time funnel.

## 18. Parked ideas (not scheduled)

- **Snack counter** (parked 2026-09-26, taken off the rooftop map at its Checkpoint A): a
  counter that hands out non-alcoholic drinks and snacks the player can drink or eat (a tool
  with a short animation).

- Cross-server and worldwide matchmaking, a global server for 1v1 and 2v2.
- Private friend-locked tables. Party up with friends.
- Replay or "clip that" feature. Cinematic replay camera.
- Trading UI polish, item showcases, serial plaques.
- Seasons with themed sets beyond Season 0.
- More abilities: extended bounce guideline, shrink the opponent's guideline, fog, shaky aim,
  and anything new. New ideas go here.
- Offline play if Roblox ships it.
- New game modes and table types.
- **Collectible table skins** (parked 2026-09-23, after release): each a retexture of the one
  standard table model (changed 2026-09-24; it used to be a full model per skin), the host's
  table used for the match, rare ones with VFX, a
  table loot box, Founder's/Beta/VIP tables, tradable, serial plaques for limited ones.
- **Walk to the next shot** (parked 2026-09-24): when the same player shoots again from a
  different spot, their body currently jumps there; a short walk round the table would read
  better for watchers.
- **Swerve and a curved aim guideline for side spin** (parked 2026-09-23): squirt off the aim
  and a path that curves on the cloth, with the guideline curving to match. The physics exists
  behind Config.Cue.SideSpinBendsPath.

## 19. Open questions (collected)

- Age-rating and DevEx rate verification (section 2).
- Full ability list (section 9).
- Pro lobby look (section 10).
- Rating formula (section 11).
- Economy numbers, the rarity order and what VIP rarity means (section 12).
