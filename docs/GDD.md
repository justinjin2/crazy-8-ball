# Crazy 8 Ball: Game Design Document

> **2026-09-22 multiplayer update:** [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md)
> is the agreed design for this update. It supersedes older turn rotation, break,
> assignment, 8-ball, timer, departure/surrender and reward details. Results are match-only;
> bots, abilities, difficulty and progression remain future work. Solo is built (spec, Solo).


Working name: **Crazy 8 Ball** (final name check is a release task). Rewritten 2026-09-20 from the
designer's full idea dump plus the earlier GDD. Every section has **Decided** (build to this for
now; the designer can change any of it) and **Open** (not yet decided; do not guess, ask). Numbers
marked *(tune)* live in `src/shared/Config.luau` and are playtest values, not design decisions.
Ideas that are not scheduled live in section 18.

## 1. The pitch

A 3D, satisfying, chill, competitive and social 8-ball pool game on Roblox. Your own avatar lines
up and plays every shot in a bright pool hall. It feels as crisp as GamePigeon 8-ball, with a
twist: every player brings one ultimate, a comeback trump card that fills up as they fall
behind or pull off trickshots. Every ball you
pocket pays money, win or lose. Money opens loot boxes of rare cues, ranks climb from
Bronze to Reyes, and the rarest items can be traded. Built for phones first, with PC and console.

The goal is longevity: the respected, premier 8-ball game on Roblox that people come back to,
not a trend that dies.

**The first release** (designer, 2026-09-26): the pool game on phone, PC and console, ranks
and EXP, ten bots, cues, the economy, trading and ultimates (the abilities, reworked; designer,
2026-09-28; section 9). **Not in it:** the pro lobby, which follows about one to two weeks
after release. The global queue was moved into the release
and built first (designer, 2026-09-28; section 6). The order of work is in ROADMAP.md.

## 2. Audience and why Roblox

**Decided**
- Three audiences at once: adults who know pool and want a chill, skill-respecting game; pool
  lovers wanting a fresh 3D take; kids (the platform majority) who come for the ultimates and
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
4. **Skill respected, chaos welcome.** Ultimates are balanced comeback tools, never banned. Skill still wins
   over time, and the ranks make that visible.
5. **Nobody leaves empty-handed.** Losing still pays. Casual players can still get rare things.

## 4. Core loop

**Decided**
- Inside a match (seconds): aim, shoot, watch, feedback (sound, popup, money), next turn.
- Across matches (minutes): play, earn money for every ball plus bonuses, spend money on loot
  boxes for cues, rank up, trade, repeat (and collect ultimates; section 9).
- The currency is called **money** everywhere (UI, code, docs). Never "coins".

## 5. Platforms, controls and camera

**Decided**
- **Every feature works on phone, PC and gamepad, and is checked on all three in every
  milestone.** Every control works by touch, mouse and gamepad; a drag needs no button twin
  (changed 2026-09-26: the Fine controls panel is gone).
- PC: hold click and drag left or right to aim, scroll wheel to zoom, pull the power bar on the
  right down and release to shoot, click the cue-ball icon to set spin.
- Mobile: swipe left or right to aim, pinch to zoom, pull the power bar with a thumb, tap the
  cue-ball icon for spin. **No fat-fingered shots (designer, 2026-10-06):** on a finger the
  bar's first ~24 px down are a dead zone (letting go there cancels); past it the bar clicks in
  with a small bump at the softest shot, and full power is where it always was. A drag that
  goes mostly sideways is aiming and never shoots, and a press under 0.15 s never shoots
  (`Config.Input.TouchPull`). A mouse pulls as before.
- A small zoom guide sits over the spin button during your turn: a mouse-wheel icon (computer)
  or a pinching hand (touch) and "Zoom In/Out", greyed out like a control guide (designer,
  2026-09-26; the tutorial explains more). Gamepad guidance comes later. The first zoom hides
  it for the rest of the session; it comes back when the player rejoins (designer, 2026-09-27).
- Spin UI: a larger cue-ball button sits at the left middle. Drag anywhere across the white
  selector to choose spin; its full disc represents the available physics range. Keep only
  Center and Done, with no background dimming (nothing darkens the screen; designer,
  2026-09-27) and no title, hint, box or arrow buttons.
  Use a broad red marker on the selector and a smaller one on the left toggle. Clicking
  outside closes it and retains the selection. Gamepad stick controls remain.
- **Cue angle (jump shots, decided 2026-09-24):** a vertical slider beside the white ball in
  the spin panel sets how steeply the cue is raised, 4 degrees (normal) to 60, in whole
  degrees. Tap or drag the track; the arrow keys and L1 + right stick (or D-pad) step it. A
  raised angle shows under the spin toggle and resets to 4 after every shot, like spin.
  Raising the cue and striking down bounces the cue ball off the slate: it can jump a
  blocking ball, and too much power sends it off the table. The guideline follows the jump:
  a small ring where it comes down, and a red cross where it would fly off. In Classic it
  also draws the flight itself (2026-10-02): dots through the air along every hop, live with
  the pull, a faint shadow line on the cloth under each, and the aim line from where the
  ball settles.
- Gamepad: left stick aims, up and down on the right stick (or triggers) zooms, a hold-and-
  release button shoots with power, the spin selector is a stick target. Exact bindings are a
  milestone task, not a design question. Decided with a PS5 pad (designer, 2026-09-27):
  holding L1, the left stick moves the spin and the right stick raises or lowers the cue;
  moving the stick or the D-pad during a pull calls the shot off; Y in the hub opens or
  closes Ranked; choosing the 8's pocket, the stick goes to the ring that way on screen.
- Aim ticks: a soft tick sound on every step of rotation; a stretch sound while pulling the
  power bar back (GamePigeon style, original audio).
- **Camera:** one 3D orbit view (no toggle; top-down only while calling the 8-ball pocket). It
  sits on the side opposite the aim and looks across the table along the aim line, framing the
  whole table automatically for any ball position, aim and screen shape. Zoom is one continuous
  gesture from "whole table" down to a low "down the cue" view behind the ball. Fully zoomed
  out always shows the whole table.
  - On a phone every turn starts one zoom step closer, and the break (or any ball in hand)
    opens at that same close view rather than zoomed out; the pockets behind the cue ball may
    be off screen (designer, 2026-09-27).
  - The **home view** is the middle of that zoom: behind the cue ball, halfway between the
    whole table and the down-the-cue view (`Config.Camera.View.ZoomDefault`). Every turn
    starts there and the camera always comes back to it.
  - After the strike the camera holds a beat (less if a ball is about to leave the screen),
    then pulls out so every ball's path is visible. It swings round the table (about 0.9 s,
    eased) to a fixed, semi-top-down view of the whole table from one of its long sides, the
    table centred and as large as the match HUD allows: the same view every shot, still
    tilted enough to show perspective. It takes the long side that needs the smaller turn
    from where the shot was aimed (aimed straight down the length, the side the camera
    already stands on), so the camera never turns more than about a quarter of the way
    round. When the balls stop it swings back the short way to the home view. Soft shots
    (about 35% power and under) stay in the aiming view unless a ball reaches the screen
    edge. (A test, 2026-09-26; `Config.Camera.Shot.PullOutView = "Aim"` restores the older
    whole-table view along the aim.)
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
- **The balls pulse to call things out (designer, 2026-10-06):** when the groups are decided,
  your own group glows bright green and pulses with the YOU ARE popup (the other group does not
  glow). When a team is down to its last ball of its group (the 8 not counted), that ball
  pulses green for everyone as a warning to the other side: once per team per game, never again
  after a miss. Each callout is four slow pulses of about 2 s (8 s). Not in solo, and never for
  someone arriving mid-game.
- **Physics realism choices (2026-09-22, implemented):** keep one power bar, with no
  separate break control, reaching 25 mph (it was 30 until 2026-09-30: pros average about
  24 mph on the break). Rolling friction 0.0125, a medium cloth (0.010 until 2026-09-30,
  for a faster game). Classic shows the predicted cue-ball
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
  tables nearest the spawn. The four 2v2 stand together (2 x 2) in the back-left corner and
  the two 3v3 in the back-right corner, seen from the spawn (changed 2026-09-26).
- **Joining: step onto the table's queue pad.** Each table has one glowing rectangular pad in
  front of it, lying along the long side that faces the entrance (changed 2026-09-26 for the
  rooftop map; a round pad was tried the same day and dropped), as long as the table and just
  off its rail, the same for every mode (designer, 2026-10-08), holding both teams (2, 4 or 6).
  It is see-through glass tinted like its rim (blue with room, green with someone on, gold when
  full or playing; designer, 2026-09-27 and 2026-10-08). Its mode is written big on it with
  JOIN or the count. While it has room it is a **queue portal** (2026-10-08): glowing outlines
  rise from its rim one after another and fade as they climb, sparkles drift up, and a big
  arrow with JOIN under it bobs over it when you are near. Joining is instant: the host's card pops up the moment you step on. Stepping on plays a
  sound and a VFX and the rim turns green so everyone can see someone is queueing. There is no
  accept step; anyone may step onto a waiting pad with room, and walking off leaves at once. Everyone else can stand around and watch. Players in a match stay by their table:
  invisible walls, a few studs beyond its area and its pad, let someone waiting for their turn
  walk about a little but never reach another table (designer, 2026-09-26). The small sign
  over a table's pad (the mode big, the host, count and difficulty, and a WAITING, STARTING 3,
  FULL or PLAYING pill; an empty pad's sign has no pill and no "join" words, since stepping on
  is the way in; no abilities; designer, 2026-09-27) shows when you walk right up to it, never
  while you stand on a pad (the matchmaking bar says it all). That pad's bobbing arrow hides
  while its sign shows.
- **No settings and no Start: just play, one option only** (designer, 2026-09-27; the
  matchmaking bar, 2026-10-07: "simplify the whole matchmaking ... essentially 1 option
  only"). Everyone on a waiting pad gets one slim **matchmaking bar** just above the lucky
  block hotbar: the mode icon, a small "1/2" count chip and "Waiting for opponent..."
  ("Waiting for players..." on 2v2 and 3v3), its three dots lighting up one by one, or
  "Starting in 3" once the pad is full. The first person on is the **host**. Lobby tables
  play Classic with ults on (no difficulty choice for now, below). If the host leaves, the
  next to arrive becomes host.
- **The host's one choice, Play Global** (designer, 2026-10-07): the moment they step on,
  friends in the server or not (designer, 2026-10-09; it waited 3 s, 5 s with a friend),
  "Don't want to wait?" and a big green **Play Global** grow out of the bar's right end. Pressed, the bar shows "Searching...
  0:07" and a small red X (stepping off cancels too); see Global queue below. On 2v2 and 3v3
  it shows only once a whole side stands on the pad. A small red **X on Play Global's
  corner** dismisses it for someone who would rather keep waiting; it comes back on the next
  step-on (designer, 2026-10-07).
- **The spawn pill** (designer, 2026-10-07): a player in a public server with **nobody else
  free** (alone, or everyone else busy at a table: in a game, on its result or on a full pad;
  designer, 2026-10-09) gets "Don't want to wait?" and Play Global the moment they spawn (or
  the moment nobody is free), with no pad. Someone waiting on a pad with room counts as free. Never in a private server
  (people there want to play with their friends) and not before the tutorial is done or
  skipped. It goes when they press its X, after **20 s** *(tune)*, when they step on a pad
  (the pad's bar takes over) or when someone is free; it may come back each time nobody is. Pressed, the search runs from where
  they stand (1v1, ults on): "Searching... 0:03" with the red X, a bot of their level at 5 s,
  then the arena, like a pad search. Stepping onto a pad mid-search cancels it.
- **A full pad starts by itself**, **3 s** *(tune)* after the last one stepped on ("Starting in
  3"), so someone who walked on by accident can step off. Then straight to the coin flip,
  about 3 s and a few words at a time: "YOU ARE HEADS" (or TAILS), the flip, then "YOU BREAK"
  or "<NAME> BREAKS" for over a second (designer, 2026-09-27). **Teams go by arrival**: the
  first on (the host) is team A, the next team B, and so on alternately.
- **Play solo, Play against PC and Fill with PC are off the pad** (designer, 2026-10-07):
  they move somewhere else later (their server handlers stay). There is no automatic start
  against PC in the lobby.
- **"<name> needs an opponent!"** (designer, 2026-09-27; automatic 2026-10-07): a host who
  steps onto a pad sends it by themselves, friends in the server or not (designer,
  2026-10-09), nothing to press, once per step-on (stepping off and on again sends it no
  sooner than **15 s** *(tune)* after the last). Everyone in the server who is not at a table gets
  a small popup at the bottom of the screen, the host's face and "<name> needs an opponent!"
  (or "needs players!") with **Join** (stands them on the host's pad) and **Dismiss**, small
  and low so it never covers the player's legs. It goes by itself after 15 s *(tune)* or as
  soon as the pad fills or the host leaves. Lobby bots no longer answer it.
- Every match is played on the one standard table model, in one of its looks (section 16).
  Collectible table skins are parked until after release (section 18).
- **Modes at release: Solo, 1v1, 2v2, 3v3.** Lobby 2v2/3v3 tables: bots never join by
  themselves; the host presses **Fill with PC** once their own side is full (designer,
  2026-10-02).
  Solo: normal rules with no opponent; the first legally pocketed group is cleared first, then
  the other group, then the called 8. A foul gives yourself ball in hand; the 8 early, on a foul
  or in the wrong pocket loses (changed 2026-09-23; it no longer re-racks). No shot clock, money
  per ball, no win bonus, no rank change.
  Teams: teams alternate turns and teammates rotate (A1, B1, A2, B2), teammates share a group,
  each player has their own ult and bar, the shot clock is per shooter, a
  whole team must agree to forfeit, PC can fill any seat, team matches are rated by team
  average.
- Before any two-sided match a short **versus screen** shows each player's avatar, cue and
  rank. Never for Solo.
- **Rematch and the series** (designer, 2026-09-28): after a two-sided match the result screen
  (rank XP and money, as always) has a row under it: **Rematch** and **Leave** on a lobby
  table; **Rematch**, **Play another** and **Lobby** in an arena. Everyone in the match must
  press Rematch within **20 s** *(tune)*; then the same players play again at once, the side
  that did not break last game breaking (no coin), with the same teams. A running **series
  score** ("2 - 1", your side first) stands where VS was on the result screen and in a small
  "Series 2-1" pill under the clock during the next games; each game is paid (rank XP and
  money) like any other. One player saying no, leaving or walking away from the table (a
  lobby table), or the time running out, frees the table and ends the series. Rematches are
  unlimited. Solo keeps its short hold; PC matches get an instant Play again when bots exist.
- One **Find another server** button, hidden during a match.
- **Global queue** (designer, 2026-09-28; it had been planned for after release): the bar's
  **Play Global** (2026-10-07; it was the card's 4th choice, Join Global Queue) looks in every
  server for a side of similar rank and teleports both into an **arena**.
  - 1v1 alone; **2v2 needs 2 on the pad and 3v3 needs 3** (a whole side). The first whole
    side by arrival goes; anyone extra stays and hosts the pad. Play Global shows only then.
  - **Stay on the pad while searching**: the bar shows "Searching... 0:07" and a small red
    X; stepping off cancels. A 1v1 with no real opponent after **5 s** *(tune)* meets a
    disguised bot of its rank in an arena (section 13). Anyone in the server may still step on: a
    full pad plays locally and the search stops.
  - **Rank**: the closest rank first, widening every few seconds, **anyone after 10 s**
    *(tune)* ("as quick as possible", designer). A new game after an arena match avoids the
    last opponent for the first 10 s.
  - **Match found!** shows a full screen that stays through the teleport until the arena is
    ready. Nothing is kept waiting on the save: it is handed over before the teleport.
  - **The arena**: a private server of the same place: the same rooftop, light and day cycle,
    started at day, with just one table in the middle, blue felt on black (designer,
    2026-09-28: reuse the map instead of a new one, to save time). Players are stood at the
    table as they arrive and the game starts as soon as everyone is in (or after 25 s
    *(tune)* with both sides there; if a side never comes, the other searches again at once).
  - After each game: Rematch (above), **Play another** (a new opponent, straight from the
    arena; a team goes together once every teammate pressed it, and if a teammate picks
    Lobby or leaves, the rest go to the lobby too) or **Lobby** (back to the lobby server they
    came from, or any if that one is full or gone). Choosing nothing in the 20 s goes to
    the lobby.
  - Arena matches are rated and paid exactly like lobby matches.
- Servers hold about 30 players *(tune)*. Every table seats 1v1, 2v2 or 3v3, decided by who
  is in its box. Lobby bots may play each other at 1v1 tables while at least 3 stay free
  (designer, 2026-10-02; was "PC never plays PC").

- **Spectator seating:** the chairs and sofas are sittable, and sitting is free look - the
  player is seated and the camera is left alone. Watching a table through its own camera is
  a separate feature and waits for spectating proper (Roadmap 2.3).

**Open**
- Difficult and Challenger may be for pro lobbies only (designer thinking, 2026-09-27); until
  then public tables play Classic, with ults on (section 9). TEMPORARY (2026-09-30, for
  trying them): the host's card has a Classic / Difficult / Challenger picker under its title;
  no rank lock and no money multiplier yet, and the table goes back to Classic after a game.
- Whether the arena gets its own map later (the reference image) or keeps the rooftop, and
  whether players in the lobby can watch arena matches.

## 7. Rules

**Decided**
- Standard 8-ball. A coin flip decides who breaks (the first-time player always breaks, see
  section 14). The table stays **open after the break**: the first ball legally sunk after the
  break decides solids and stripes, and each player sees a popup saying which they are
  ("YOU ARE SOLIDS" / "YOU ARE STRIPES", designer, 2026-09-27). Sink your ball, shoot again; miss, the turn passes. Fouls
  (scratch, wrong group first, no ball hit) give the opponent **ball in hand anywhere**. Clear
  your group then sink the 8 to win. Sinking the 8 early, or scratching on the 8, loses the
  game immediately. The 8 sunk on the break is re-spotted and the same player continues. No
  calling pockets.
- **NICE SHOT!** (designer, 2026-09-27): a good pot that was not a plain one (a bank, a
  combo, a kick or a carom) puts a gold "NICE SHOT!" over the pocket with a sparkle burst.
  Plain means the cue ball went straight to the ball, touched it first, and it went straight
  in. Only the shooter's good pots (the ones that get the pocket burst), never on the break.
- **A ball off the table** (jump shots, decided 2026-09-24, standard rules): a foul with ball
  in hand. An object ball that flies off goes back on the foot spot (or the nearest free
  spot). The 8 off the table loses the game, except on the break, where it is re-spotted
  (and it is still a foul).
- **Shot clock** about 20 seconds *(tune)*. Zero = foul with ball in hand. The break has one
  20 s clock for moving the cue ball along the line and shooting; zero is the same timeout
  foul (designer, 2026-09-27). Ball in hand after a foul gets 10 s to move the ball first (was 15; designer, 2026-09-27),
  then the shot clock. Two timeouts in a
  row = automatic forfeit *(tune)*. In its last 5 seconds the shooter hears a clock tick once
  a second (the last two a little higher), until they shoot (designer, 2026-09-26).
- **Forfeit** button, costs rating, behind a confirmation that warns "you will lose rating".
  Leaving or disconnecting mid-match is an immediate forfeit: the opponent gets the win and
  reward (subject to the real-match rules in section 13), the table frees, no PC takes over.
- **Lobby tables play Classic for now** (designer, 2026-10-07: the matchmaking bar has no
  difficulty choice; Difficult and Challenger stay in the code to come back somewhere else).
  The three levels as built (2026-09-25 to 10-02), **chosen by the host for the whole table**
  (both players see the same guideline):
  - **Classic** (default, recommended): full guideline as in section 5.
  - **Difficult**: the aim line only (the corridor to first contact and its ring), no
    object-ball line, no deflection or bounce line, no jump landings.
  - **Challenger**: no lines at all (changed 2026-09-25; it used to be a short aim stub).
  The host can pick Difficult or Challenger only from **Gold I** (2026-10-02): below it the
  host card shows them greyed with "Requires Gold I+" under them, and the server refuses
  them. A guest below that rank still joins *(the guest warning is not built)*. Unlocks never
  re-lock (rank XP is never lost). Ball highlights and X
  marks stay on in every difficulty.

## 8. Feel: the satisfying layer

This is pillar 1 and 2 in practice. It is part of the core, not polish for later.

**Decided**
- Sounds: cue strike, ball-on-ball clack scaled by speed, soft rail thud, deep pocket drop, aim
  ticks, power-bar stretch, UI clicks. ASMR quality, original or licensed audio only.
- A small VFX and a rewarding sound on every pocketed ball, bigger and flashier for the 8.
- **Ball streak** (designer, 2026-10-09; the approved mockup
  https://claude.ai/artifact/7sj2aFqL94Zv5C1n7Us44T): "STREAK x1" up to **x8** in Press Start 2P,
  about YOUR TURN's size, in the match popups' row under the top bar; while a new turn or a
  foul shows there it steps aside and comes back after, and under YOU ARE SOLIDS / STRIPES it
  slides down and back up. Past x8 it counts on (x9, x10) in x8's look, with no spray. Seen
  and heard by everyone seated at the table. Each ball the team pots in a row in its turn steps it up one; two balls in
  one shot step twice. The break is x1 however many drop. A foul (its ball does not raise it), a
  shot that pots none of yours or the table passing ends it: it fades and starts again next turn.
  x1 is white and silent; each step after plays a Jet Set Radio spray over the pocket sounds
  (singles x2 to x7, the four-hit burst at x8), a new colour (white, yellow, orange, blue, purple,
  red, gold, rainbow), a slightly bigger size, white impact frames, a burst and pixel shards, and
  the words move more each level. From **x3** the words burn with low pixel flames hugging them
  (orange, blue, purple, black-red, gold-white, rainbow), taller each level up to about a letter
  at x8, and each step gives a tiny camera shake that grows each level. YOUR TURN pops only when
  the table comes to a new shooter, not after each pot of a run. Money is a
  small bonus on each ball from x3, never a multiplier (section 12, ECONOMY 3.1).
- **Trickshot bonuses:** extra money and a popup for bank shots (one or more rails before the
  pocket), combos (your ball knocks another in), and multi-ball shots ("Double", "Triple").
  Lucky sinks count and get the full celebration.
- "Nice shot" popup with a dopamine sound, shown on about half of good shots *(tune)*.
- **One end-of-match screen for both players** (designer, 2026-09-27; replaces the separate
  win and lose cards): both sides with VS, the winner's picture gets a shining crown, then
  your XP bar animates up, down or holds and the match's money is pocketed into your total. At
  each rank reached the bar holds full and yellow saying NEW RANK! for 1 s, then carries on.
  The big NEW RANK! popup comes only after the results close, once the player is free in a
  lobby server (never in an arena, a rematch or over the results): one popup per division
  gained since the last one seen, in order (designer, 2026-10-07). No finisher effect.
- Emotes during the opponent's turn for players and spectators.

## 9. Abilities (ults in code)

**Decided** (designer, 2026-09-28, after the ultimates interview; built on branch
`ultimates`, `docs/prompts/ULTIMATES_PROMPT.md`; the 13 abilities built on branch `abilities`,
2026-09-29, `docs/prompts/ABILITIES_PROMPT.md`)
- **Players see them as "Abilities" everywhere** (the designer, 2026-09-28: "Ult doesn't look
  right"): every button, label, notice and reward says Ability / Abilities (ABILITY in the
  all-caps spots). **In code and in these docs they are still called ults** (UltService,
  `Config.Ults`, the `Ults` save field, the Ult remotes), and the words "ult" / "ultimate"
  below mean the same thing. The promo code is **ABILITIES**.
- **Abilities (ults) are core gameplay, in the release.** An ult is
  a comeback trump card: its job is to level the field. **Both players should get to use
  their ult in 80%+ of matches**, leaving out the rare run-out (a player who pockets all 7
  and the 8 in one turn). A second ult only comes in long, slow matches.
- **Ults are on by default everywhere**: public tables, the global queue and arenas, and vs
  PC (this replaces "public tables play Classic with no abilities", 2026-09-27). Solo shows
  the **real ability bar, always full**: G, a tap on the bar or gamepad X arms your equipped
  ability for free, as often as you like, the break included; those shots (and a practice
  Rewind's redos) pay no money (2026-09-30). The global queue's Abilities: On / Off toggle
  was removed (2026-10-02): every search, arena and lobby table plays with ults on.
- **One bar per player, 0-100, filled by the same rules for everyone** (never by what they
  own), starting at 0 each game (rematches too). The numbers (`Config.Ults.Fill`, checked by
  `tools/ult_model.py`): your own balls in one turn +10, +8, +6, +5, then +3 each; a nice shot
  (bank, kick, combo, carom) +20 on top; an opponent's ball +8 plus 7 for every ball you are
  behind after it; each of your turns that ends on a legal shot +15; each of the opponent's
  turns that ends +6; turn-end fill gives at most 50 of a bar in total; a teammate's ball +2.
  Every gain x1.3 in Classic (x1.0 Difficult and Challenger; the 50 cap doesn't scale). After
  your first ult everything fills at x0.25 (the turn cap counts again from 0); at most **2
  ults a match**. "Behind" = your side's balls left minus the other's (a side on the 8 counts
  0; on an open table, compare the balls each side pocketed); balls on the break count as
  normal balls. **Balls pocketed on an ult shot fill nothing for its user** (they fill the
  opponent's bar as usual).
- **No farming:** turn-end fill needs a legal shot and gives at most 50, so missing on
  purpose can never fill a bar by itself; in the model a deliberate misser loses to an honest
  equal player.
- **The bar shows only on your turn**, bottom centre and compact, never over the middle of
  the table; it fades to 25% while you pull the cue back. Gains made during the opponent's
  turn are stored and animate when your turn starts (the bar slides up, counts, a floating
  "+34", and ult_ready once if it crosses 100). A full bar turns gold, sparkles, glows and
  shakes every ~2 s; the prompt reads PRESS [G] TO ACTIVATE (PC), TAP TO ACTIVATE (touch: the
  whole bar is the button), or PRESS [X/Square glyph] TO ACTIVATE (gamepad ButtonX). The
  opponent's match bar shows a small ult icon beside the user that lights up when their ult
  is ready.
- **Using it:** on your own turn, before the shot, with the balls at rest (ball in hand is
  fine); never on the break. Once pressed it can't be cancelled; if the shot clock runs out
  while armed the ult is spent. **Both players see a 0.8 s manga-strip cutscene** (the
  activating player's avatar in a tilted panel over a swirling backdrop in the ult's rarity
  colour, "ABILITY" and the ult's name, the ult_activate sound), then straight after it (0.1 s;
  the designer, 2026-09-28) the ult's own arming effect and an armed pill ("MAGNET: NEXT SHOT"; the opponent sees
  "Opponent's ability: MAGNET"). The shot clock pauses from activation until armed, for both
  sides.
- **Fouls still count on an ult shot.** No ult pockets, moves or removes the 8 before your
  legal 8 shot unless the list below says so, the cue ball is never pulled, pushed, swallowed
  or cut, and balls pocketed on an ult shot fill nothing for its user.
- **The opponent's balls, at half strength (the skill rule; designer, 2026-09-29):** Magnet,
  Chain Lightning, Black Flash's blast, Black Hole and Guangdong Tiger act on every object ball
  in reach, the opponent's at half strength (`Config.Ults.Shared.OpponentFactor` 0.5: half the
  pull or push, half the reach for the ones that remove balls), never on the 8 unless it is your
  legal 8 shot (then it counts as yours), never on the cue ball. On an open table every ball but
  the 8 counts as yours. An opponent's ball an ability sinks or removes counts as pocketed for
  them by the normal rules and fills nobody's bar; your turn goes on only if one of yours
  dropped. So where you aim the ability matters: set off next to their cluster, it helps them.
  While armed and aiming, these show a faint reach ring at the predicted first contact (a
  dashed inner ring for the opponent's reach, their balls inside outlined red); Magnet shows
  each pocket's capture zone instead. The other exceptions: **Portals move every ball**, the
  opponent's and the 8 included, like real physics; **Black Flash shatters any first ball** (an
  opponent's ball counts as theirs gone and a foul; the 8 by the normal 8 rules, a loss unless
  it is your legal 8 shot); **Time Stop's strikes** hit the cue ball, which may then hit any
  ball; **Catch-a-Ball and Verity take whatever ball the cue ball hits first** (an opponent's
  goes down for them, and hitting it first is still a foul; only the 8 off your legal 8 shot is
  spared). Steel Ball acts only on your balls.
- **Teams:** each player has their own bar; "behind" compares sides.
- **The bots** (the PC opponent) roll their ability like a spin, by rarity, each built ability
  even within its rarity (`Bots/Look.ability`; nothing above Epic against a player of Gold or
  below), and activate it when their bar is full and they are behind, or when their shot
  finder sees no easy shot (`Ults/Match.pcShouldActivate`).
- **Rarities and power** (designer, 2026-09-28): higher rarities are cooler *and* stronger,
  each a little better than the one below. The targets per use were Common about 1/3 of a
  ball, Uncommon 1/2, Rare 1, Epic 1.5, Legendary 2.2, Mythic 2.6; inside the reach cap (no
  capture radius over a fifth of the table's length, 20 in) and the ball caps the top rows
  can't reach them, so each ult is built to its row as far as the caps allow and its **measured
  worth** (extra own balls per use, net of the opponent's gifted, a careful shooter, the mean of
  three skills, `tests/ult_value.luau`, 120 tables) is `Config.Ults.Catalog[id].Worth`. The
  rarity means are **0.17, 0.50, 0.64, 0.94, 0.94 and 1.78** (2026-10-08, after the abilities
  rework's third round; Legendary 1.15 -> 0.94 with Steel Ball's one-pot cap, 2026-10-09; Common is Eagle's Eye 0.34 and Fire Shot 0; Rare and above pot in
  75-100% of uses, Look Over There! the lowest). Caps per use: at most 2 of your balls (Chain
  Lightning: the charged ball and one jump), 1 (Steel Ball: one in, one lined up) or 4 (Black
  Flash), and 2 of the opponent's (Black Flash's blast) or 1 (Chain Lightning's jump). Black
  Hole and Guangdong Tiger have no caps (the designer, 2026-10-08: "NO limit"; a hit on a solo
  break takes every ball but the 8): only their reach limits them. Against Magnet at equal skill the model
  (`tools/ult_model.py`) gives Common to Rare 49-51% wins, Epic 54-55%, Legendary 55-56% and
  Mythic 56-59% (2026-10-08, the second round; ECONOMY.md 11.8).
- **The catalog of 13, all built** (`Config.Ults.Catalog`, names and one-line descriptions
  in `Strings.Ults`, 3D icons rendered in Blender in `Config.Ults.Assets.Icons`). Each row's
  rules are in its effect module (`src/shared/Ults/Effects`), its look in `src/client/<Id>Fx`,
  and every number in `Config.Ults.<Id>`. Worth is the measured value above.
  - **Magnet** (Uncommon, 0.46; everyone's starter until the designer's third rework round,
    2026-10-08, and kept by every save that holds it): for the whole shot the
    **first ball the cue ball hits** (if it is yours; the 8 only on your legal 8 shot, toward
    the called pocket; the opponent's at half), moving toward a pocket and passing within the
    capture zone of its mouth (6.5 ball widths since the rework's buff, 2026-10-08: "nerfed too
    much"; was 5.25), is caught: braked from the zone's edge, bent toward the pocket's centre
    and snapped in at the mouth. It rescues near misses and jaw rattles, never a vacuum: pots
    73% of uses at skill 2 (23% before the buff). Only that one ball (2026-09-30: a cluster by a pocket let one shot
    pull about five in). A
    blue field-line dipole on the cloth round the armed cue ball that rides it until the first
    hit, where it passes to the hit ball in a flash of lines and sparks (2026-09-30); field
    lines pulling into the pocket, a shockwave on the drop. Nothing is drawn on the balls
    themselves (the red and blue caps and rings went, 2026-09-30).
  - **Eagle's Eye** (Common, 0.34): the full path of the shot while aiming, the cue ball's and
    the first object ball's, through every cushion, bounce rings and the reached pocket
    glowing (gold strips under the white guideline). Nothing changes the physics. The path
    shows only once the player starts pulling the cue back, and follows the pull (2026-09-30).
    Its icon is the eagle's eye alone (2026-09-30): a glistening pale-gold iris and big black
    pupil in a yellow ring, a black brow line cutting across its top.
  - **Fire Shot** (Common, 0; **everyone's starter, free forever**, since the designer's third
    rework round, 2026-10-08, when it replaced Super Bounce; Super Bounce is back beside it
    since 2026-10-09): armed, the cue ball bursts into flames, seen by everyone at the table. While the
    shooter aims, the guideline draws every line, and the object ball's line and the cue ball's
    line after the first contact run all the way on until they touch the next cushion, ball or
    pocket (the designer, 2026-10-08: "to the next edge of a table"; not a line bouncing round
    the cushions). The lines are the regular guideline's, orange (designer, 2026-10-09: the
    rivers of fire under them are gone). It never shows where anything stops,
    and it ignores the table's difficulty, like
    Eagle's Eye. The shot leaves the cue at **twice the speed** (the stroke's speed along the
    cloth and its spin, not a jump's height), the ball a comet of fire with low flames
    trailing behind it along its path (2026-10-09), and it **scorches the cloth** where it
    rolls: a faint dark char line that fades away about a second after the ball burnt it
    (designer, 2026-10-09: it was "way too aggressive"; cosmetic only). Measured: -0.08 /
    -0.03 / +0.03 net (about nothing: double speed alone neither pots nor misses more, and the
    model shooter plays no kicks or banks, where the line helps, nor Difficult or Challenger
    tables, where it shows what the normal lines hide). The tutorial's one starter spin lands
    on it. Icon: the cue ball as a fireball, a cartoon flame of five curling tongues streaming
    back from it.
  - **Super Bounce** (Common, 0.33; became Fire Shot on 2026-10-08, back as a third Common on
    2026-10-09, "just more in the pool"): the cue ball turns rainbow and keeps bouncing off the
    cushions, and the first ball of yours it hits bounces too and boings off a pocket's jaw
    straight in. Saves that held it on 2026-10-08 hold Fire Shot.
  - **Ghost** and **Heat Seeker** left the game (designer, 2026-10-08): a slot holding either
    becomes Magnet when the profile loads.
  - **Rewind** (Uncommon since 2026-10-08, was Rare; 0.53): a shot that drops none of your balls, fouls and scratches
    included, is undone (the foul erased) and redone on a 10 s clock with Eagle's Eye's full
    path shown; a missed redo rewinds again, two redos a use. Everyone at the table sees the
    VHS rewind.
  - **Catch-a-Ball** (Epic, 0.96; new in the rework, 2026-10-08; Epic since the designer's
    second round, swapped with Look Over There!): the cue ball becomes a red and white catch
    ball. Whatever ball it hits first is caught: the ball pops open, a red beam pulls the ball
    in as a glowing silhouette, it snaps shut, hops, and wobbles one, two, three times with a
    click (GOTCHA!), the shooter's camera easing in beside it. The caught ball counts as
    pocketed for its owner (an opponent's goes down for them, and hitting it first is still a
    foul); the cue ball stops dead where it made the contact. Then the second catch (the Epic
    buff): it leaps, flipping, to your nearest ball within 9 in (centre to centre, its way clear
    of the pocket mouths, never the 8) and catches that too, a quicker pull and DOUBLE CATCH!,
    and the cue ball sits on that ball's spot. The 8 off your legal 8 shot breaks free; after a
    legal 8 there is no hop. Measured: +0.80 / +1.02 / +1.05 net, pots 94-98% of uses (one
    catch measured +0.47 / +0.66 / +0.75 as a Rare; a 20 in reach was +1.28, above the
    Legendaries).
  - **Look Over There!** (Rare, 0.58; reworked in the designer's second round, 2026-10-08, and
    moved down from Epic, swapped with Catch-a-Ball, as it is no sure pot) is not a shot and has no activation panel or
    armed label: nobody may be warned. Armed, it opens the Sneak phase: the shooter points up
    and "says" "OMG LOOKK AT THAT!" (a Roblox chat bubble and a chat-window line, as if typed,
    for bots too), each opponent is locked in first person looking up and away from the table
    (walking frozen), and for about 3 s the shooter moves the cue ball anywhere free on the
    cloth, as with ball in hand (touch or mouse drag, the gamepad's stick). Then the opponents
    turn back, still in first person, their view on the cue ball's new spot, and a vine boom
    plays (the only sound). The shooter shoots from there on a fresh clock. Not on the break,
    nor when the shooter already has ball in hand; fine on the 8. Measured: +0.50 / +0.63 /
    +0.60 net, pots 75-97% of uses: the one shot only, not the run a free ball in hand sets up,
    so it plays stronger than it measures.
  - **Time Stop** (Epic since 2026-09-30, was Rare; 0.87): 1 s after the cue ball's first contact time freezes (a
    shot that touches nothing freezes 1.5 s in: the Rare+ buff, 2026-10-08); the shooter gets
    8 s to line up and strike the cue ball once more (untouched, time resumes by itself); the
    cue ball alone moves until it touches a ball or a cushion, and time resumes 1 s later,
    every ball's stored motion playing out (the designer, 2026-09-30: was three strikes, 5 s
    each). A ball of yours the stopped-time strike touches is sent: a line draws from it to its
    pocket, and as time resumes it rolls down the clear line in (its stored motion dropped).
    The clock on the cloth counts the stopped time down: its hand starts at 12 (the top of each
    player's screen) and goes once round in the 8 s, time resuming as it gets back to 12; after
    the strike it runs the rest of the way round as time resumes. Measured worth: +0.82 /
    +0.85 / +0.93 net at skills 1/2/3, pots 91-94% of uses (2026-10-08; was 0.24 / 0.31 /
    0.18 with one strike before the buff). The freeze plays the designer's own clip
    (2026-09-30).
  - **Chain Lightning** (Epic, 0.99): the first ball hit, if yours, is struck by lightning and
    driven down the clear line into the pocket nearest its heading (x1.25 speed at least; with
    no clear line, turned toward its best pocket by up to 15 degrees); then the lightning jumps
    once, to the nearest ball within 20 in, pushing it toward its closest pocket with a clear
    line in (theirs at half). The Rare+ buff (2026-10-08): pots 83-95% of uses, +0.87 / +1.07 /
    +1.03 net (three jumps with the driven charge measured +1.4, above the Legendaries).
  - **Portals** (Rare since 2026-09-30, was Epic; 0.69): place two portals for your whole turn (they
    close when the turn passes or the game ends). Any ball whose centre crosses a portal's ring
    (2.9 in from its centre) comes out of the other with the same motion; yours come out lined
    up: sent down the clear line into the pocket nearest the exit (put the exit by the pocket
    you mean), never slower than they went in (with no clear line, turned toward the pocket
    ahead by up to 15 degrees). The Rare+ buff (2026-10-08): pots 83-93% of uses, +0.65 / +0.71
    / +0.70 net, the whole turn's later shots counted only as a low bound.
  - **Verity** (Rare, 0.64; new in the rework, evil since the designer's second round,
    2026-10-08: the monster model never made it into the game; Rare since their third round,
    the same day, when she stopped eating on the roll): the cue ball becomes a bright
    yellow plush smiley ball (black oval eyes, a wide grin of white teeth in a thick black
    outline, after the designer's reference) and arming plays "Hi, I'm Verity, trust me, I know
    everything!" (a text-to-speech stand-in for the designer's clip). At the first contact she
    turns evil, the creepy face of the designer's second reference: a dark mustard-ochre ball
    with two hollow dark eye holes, no brows, and a huge smile of a mouth that hangs open, thick
    pale-pink ridged lips round a near-black throat and a tongue (no glow anywhere). She swells
    to three times the ball's size, her face turned to each player at the table, whose camera
    pushes in on her for about a second, lunges at the ball she hit as her jaws gape (her eyes
    over the open mouth) and eats it (a pot for its
    owner; an opponent's goes down for them and is still a foul; the 8 only off your legal 8
    shot, which wins). Balls inside her as she swells are shoved just clear (the 8 never toward
    a pocket). She chews, gulps and laughs, then rolls on along the shot line (up to 70 in,
    stopping before a cushion or pocket), shoving every ball she touches out of her way (the
    designer, 2026-10-08: "he shouldnt eat more he just pushes balls out of the way"); she hops
    over the 8. She burps and shrinks back into the cue ball where she stops. Measured: +0.49 /
    +0.68 / +0.76 net, pots 92-96% of uses (eating up to 2 more of yours on the roll measured
    +0.97 / +1.15 / +1.17, a Legendary).
  - **Steel Ball** (Legendary, 0.66 for the shot alone): the first ball hit, if yours, is
    guided into the pocket it was sent toward; the cue ball then curves on to your next nearest
    ball and lines it up (never in, one pot a use: the designer, 2026-10-09) and stops behind
    it; with your group gone the 8 is lined up, never potted. It never scratches. The designer's own clip
    plays on activation and on the cue ball's first hit (2026-09-30).
  - **Black Flash** (Legendary, 1.21): the first ball hit, whoever's, shatters and counts as
    pocketed for its owner; the blast nudges the balls within its reach toward their pockets (4
    of yours, 2 of theirs at half, never the 8). The reach grows with the shot's power
    (2026-09-30): 20 in at full power, 6.4 in at 15%, 4 in at the softest, so a soft shot keeps
    the blast off nearby opponent balls; the aiming ring and the shockwave on the cloth grow
    with it; the cue ball bounces straight back, never into a
    pocket. The cue ball launches at 3x the power bar's speed (2026-09-30), and the hit plays
    the designer's own clip. The blast's push was halved (2026-09-30: NudgeShare 0.75, at most
    20 in): measured worth fell to 0.51 / 0.68 / 0.77 net at skills 1/2/3 (was 1.29 / 1.47 /
    1.58), below the Epic mean; with the power-scaled reach 0.48 / 0.63 / 0.72. The shattered
    ball's pieces lie on the cloth about 6 s. Icon: a black lightning bolt with a red outline
    and the cue ball flying out of it with speed trails. The hit freezes 0.3 s (was 0.15) on
    anime impact frames (2026-10-08): the screen flickers between a blown-out negative and a
    red manga frame, and the camera of each player at the table crash-zooms toward the hit,
    rolled a little, then eases back.
  - **Black Hole** (Mythic, 1.78): at the first contact a black hole opens for 2.5 s and
    spirals in every ball within 20 in (the opponent's within 10 in; no caps since 2026-10-08,
    so a hit on a solo break swallows all but the 8), each swallowed and counted as pocketed
    for its owner; the cue ball is pushed away. Measured: +1.63 / +1.87 / +1.83 net, pots
    96-98% of uses (+1.21 / +1.36 / +1.39 with the old caps). The camera stays on the table (a cinematic
    close view was tried and taken out the same day, designer).
  - **Guangdong Tiger** (Mythic, 1.77): at the first contact a giant tiger leaps in and cuts
    every ball within 20 in (the opponent's within 10 in; no caps since 2026-10-08) off the
    table at once, counted as pocketed for their owners; the moment slows to watch it.
    Measured: +1.63 / +1.86 / +1.83 net, pots 95-97% of uses (+1.22 / +1.34 / +1.34 capped).
- **The power bar in the ability's colours** (2026-09-30): while your own Legendary or Mythic
  ability is armed, the power bar's fill wears it, stronger as you pull (`Config.UI.PowerSkins`,
  art from `tools/gen_power_skins.py`): Black Flash, black and red lightning crackling harder;
  Steel Ball, green with the steel ball riding the fill's edge, spinning faster; Black Hole,
  deep space drifting with the black hole turning at the edge; Guangdong Tiger, tiger skin.
  The outline glows in the ability's colour. Lower tiers keep the green-to-red bar and its
  rainbow.
- **Getting ults: the spin screen** (Untitled Boxing Game style; the left column's 5th
  button, **Abilities**, with a red dot when the daily free spin is ready). Three slots (slot 1
  free, slots 2 and 3 game passes); a spin rolls into the selected slot and replaces its ult;
  a locked slot can't be spun; the selected slot is the one equipped; replacing an Epic+ asks
  first. The avatar stands in the middle in its idle with a JoJo-style aura in the rarity's
  colour. True odds are always shown (Common 55%, Uncommon 30%, Rare 12.2333%, Epic 2%,
  Legendary 1 in 150, Mythic 1 in 1,000; a rarity with no built ult passes its share down),
  with **pity**: the 100th spin without an Epic or better is Epic+, and any Epic+ resets it.
  **Lucky Spins** (Robux only) never roll Common. Spins come from 3 starter spins, a free spin
  every day, rank-up rewards, day 7 of the login streak, the day's last playtime gift, codes,
  Robux packs (1 for 15 R$ up to 50 for 449) and money ($1,750 a spin). VIP adds Skip and Auto
  Spin (the Quick Cases pass was retired into VIP, 2026-10-04). Paid spins are paid random items: odds shown, and blocked
  where PolicyService restricts them (ECONOMY.md 11.7-11.8). The live screen stays hidden
  (`Config.Ults.ScreenLive`) was hidden until more ults than Magnet were built; it is live
  since all 13 were (2026-09-29).
- Sounds must be original or licensed (section 8): never clip a show's "nyo-ho" or time-stop
  sound. The designer's ult_activate and ult_ready are uploaded to the group; each ability's
  sounds are library or made clips (`Config.Ults.Sounds`, credits in
  `assets/abilities/CREDITS.md`). Verity's line is a text-to-speech stand-in until the
  designer records their own; Catch-a-Ball's catch sounds and the vine boom are fan uploads the
  designer chose (Roblox may mute them; licensed backups are named in `Config.Ults.Sounds`).

**Open**
- Playtests: whether any ability needs retuning with real players. Portals measures 0.69 (a
  low bound: the model shooter never reuses the kept portals; 0.42 before the Rare+ buff of
  2026-10-08), a Rare itself since 2026-09-30. The levers are all in `Config.Ults` (reach,
  caps, steer angles, strike and redo counts, OpponentFactor, the Legendary and Mythic odds).

## 10. The hub and the world

**Decided**
- **The hub is the rooftop pool club below** (built 2026-09-26; it replaced the plain
  baseplate): sixteen tables in a grid of four by four (ten 1v1 at the front, four 2v2 and two
  3v3 at the back; section 6), the spawn in front of them.
- Chairs and sofas are sittable. No alcohol anywhere. (The snack counter is parked, section
  18.)
- **Pro lobby:** a separate Roblox place, reached by a teleport door, for Diamond I *(tune)*
  and above, where only Difficult and Challenger are available. All its tables have black frames
  (blue felt 1v1, red 2v2, charcoal 3v3; section 16); the rest of its look is decided later (a dim, moody neon room is the candidate).
  Not in the release (designer, 2026-09-26): nobody can reach Diamond I at launch, so it
  follows about one to two weeks after release.
- A player's win streak shows above their head, and their country flag next to their name.
  **Built (designer, 2026-09-28):** "🔥 3" on a line over the rank badge and name, from the
  first win in a row (it starts at 1), saved across sessions. A real win against people adds
  one (the one-minute rule, section 13); any loss ends it, a surrender or leaving included, so
  quitting early never protects a streak; a draw leaves it. It bounces when it goes up.

- **The hub map is an open-air rooftop pool club** (designer, 2026-09-26), matching the
  concept art in `assets/map/reference/`: a city skyline on the left and a tropical coast with
  green mountain islands on the right, as seen from the entrance. The brief is
  `docs/prompts/ROOFTOP_MAP_PROMPT.md`. Nothing carries over from the removed maps.
  - All 16 tables have the regular lobby's wood frames: green felt 1v1, red 2v2, charcoal 3v3
    (section 16; the black-frame looks stay for the Pro lobby). The tables turn sideways like the art: long sides face the entrance, four across
    and four deep.
  - Day and Sunset only, no night (one was tried and dropped, 2026-10-05), the same for
    everyone on a server: about 10 minutes of day, a 10 second fade, 5 minutes of sunset, a
    10 second fade back *(tune)*. The sun's disc is hidden for now (designer, 2026-10-05: to
    see the map without it); the sun still lights the roof.
  - In: the pergola lounge with couches, a fire pit, a grand piano, planters, palms,
    lanterns, umbrella seating and the glass railing. Out: the art's infinity-pool strip,
    banners and pink light pillar, and (for now) the snack counter.
  - On the map every queue pad sits **in front of its table**, centred on the long side that
    faces the entrance (designer, 2026-09-26). The pad's shape may still change; the table
    grid is computed from its size, so it re-spaces itself. Since 2026-10-08 the pad runs
    over the shooter's walkway on that side and ends where the old one did, so the grid
    stayed put.
  - The sides follow the day view: the city side has planters, palms and lanterns; the ocean
    side has umbrella sets with loungers and sofa groups along the railing.
  - The grand piano is the lounge's centrepiece, centred at the back under the pergola, the
    player at the keys facing the tables; a sofa group either side of it.
  - The glass railing round the roof reaches a character's head (5 studs).
  - The city is densest and most detailed in the view the player gets on arrival (ahead and
    to the left); behind the spawn, the stair side, it stays low and sparse.
  - The entrance stair walks down to a small dead-end landing.
  - Props: steps and railings are sized for the player; what a player sits on (sofas,
    loungers, the piano and bench, and the coffee table) is sized for a Roblox character,
    1.6 times that (designer, Checkpoint B); planters, palms, umbrellas and the pergola about
    1.4 times it, so they hold their own beside the big tables; the spacing follows the
    art's layout.
  - Calm and clean for kids: bright saturated colours, wide walkways, props in a regular
    rhythm. Everything we ship stays under about 512k triangles, so the whole game stays
    under 1 million with players in it (the map came to about 260k).
  - The city, the mountains and the sea are background: kept soft (haze, depth of field) so
    the eye goes to the tables. Round the tower a normal city of small blocks and streets;
    the buildings light tan, grey and glass with windows, lit warm yellow at sunset.
  - At sunset a lamp over every table keeps the games easy to see, and the fire pit burns
    (Roblox's own fire; out by day).
  - **Bright, saturated and happy** (designer, 2026-09-26), in the spirit of the biggest Roblox
    games: clear colour and contrast by day, little haze. The sunset is a warm **golden hour**,
    not a dim dusk: the sun a little above the sea lights the roof gold and peach while the
    sky carries the magenta and purple.
  - Players walk 30% faster on the roof than Roblox's default; the camera zoom is Roblox's own.
  - The sea moves (gentle waves) and sailboats drift on it.

  - The rooftop's exact dimensions, prop counts and palette are in `assets/map/Spec.md`,
    confirmed at the brief's four checkpoints (the last, Checkpoint D, 2026-09-26).

**Open**
- Whether a locked pro-lobby door (a teaser) stands on the roof at release, or nothing until
  the pro lobby exists.

## 11. Progression and ranks

**Decided**
- Tiers: **Bronze, Silver, Gold, Platinum, Diamond, Expert, Veteran, Master, Grandmaster,
  Reyes**. Each has divisions **I to V** (I is the bottom, V the top) except Reyes. Reyes is
  named after Efren Reyes (placeholder, check rights before launch).
- Players are **Unranked** until their first win in a rated match, which makes them Bronze I
  (designer, 2026-10-02; a loss leaves them Unranked).
- **Rank badges** are drawn (2026-09-26, `assets/ui/ranks/`): 1 to 5 stars show the division
  from Bronze to Diamond, 1 to 5 gems from Expert to Grandmaster; crowns from Expert up; Reyes
  and Unranked have one badge each. Look and shine: `docs/UI_STYLE.md` sections 6 and 7.
- **One number, rank XP, is the only progression** (designer, 2026-09-28: the separate
  account Level and EXP are gone). Rank is the game's main way to show status. **XP is never
  lost**, so nobody ever drops a rank.
- **XP comes only from winning, and only skill speeds it up** (designer, 2026-10-02, after
  friends reached Gold in a few hours): **a win is 100 XP, a loss 0**. No Rookie Boost, no
  first-win-of-the-day bonus, no VIP XP. The ladder is counted in wins: **1 win to Bronze I,
  2 more to Bronze II, then 3, 4, 5... one more win each division to Platinum**, then a
  steady ramp (never a smaller step than the one before). Reyes is a fixed **307,500 XP**
  (3,075 Classic wins). All numbers: [ECONOMY.md](ECONOMY.md) section 4.
- Every match against a person or PC can give XP. Solo never does. **Skill sets the speed**:
  harder difficulties pay more (Classic 1, Difficult 1.25, Challenger 1.5; no Classic fade
  since 2026-10-02), a win streak gives +25% from the 3rd win in a row, and beating stronger
  players pays more and much weaker ones less (an Elo gap factor). PC matches give x0.75 XP
  below Expert and x0.5 from Expert at launch. Teams: every player by the same rules against
  the other team's average.
- Targets, for a **3-hour-a-day player who wins half their games** (designer, 2026-10-02):
  Silver after about 6 hours of play (never before 2), Expert in about a month, Veteran 2
  months, Master 3.5, Grandmaster 6, Reyes about 9. An hour-a-day player takes three times
  as long.
- **Difficulty unlocks by rank** (designer, 2026-09-27; Challenger moved to Gold I
  2026-10-02): host Difficult and Challenger from Gold I (about 18 hours of play since the
  rank rework); guests may join with a warning.
- **Ten bots, one per tier** (designer, 2026-09-26; built 2026-10-02, `docs/prompts/BOTS_PROMPT.md`):
  one skill level per tier; the player's chance of beating the bot of their own rank is
  Bronze 90%, Silver 80, Gold 65, Platinum 57, Diamond 50, Expert 50, Veteran 45, Master 40,
  Grandmaster 35, Reyes 30. **Play against PC** is a robot named "<Tier> Bot" at the player's
  own tier (Unranked: Bronze), whatever the table's difficulty; the real player always breaks.
  **Disguised bots** (the global queue's fallback after 5 s for 1v1 (10 s until 2026-10-07)
  and 25 s for teams, the
  lobby bots, off by default since 2026-10-07 so a server holds only real people, the tutorial) wear real Roblox avatars of random
  accounts with made-up names (designer's call, 2026-10-02); their wins pay like a real match
  with no win streak and are stored as PC wins (never on the most-wins board). After 20
  disguised wins in a day they pay the PC rows and drop no block, with nothing on screen
  (plan, 2026-10-02; designer, 2026-10-03: hidden). A bot's equipped cue is picked by its tier
  to match what real players at that rank own, and is never the Secret cue (ECONOMY.md
  section 15).
- Rating is saved under a season label ("Season 0"). **Ranks never reset** (designer,
  2026-09-28); seasons may give rewards for the highest tier reached that season. (Save
  version 6, 2026-10-03, started every save over before release: only friends had played.)
- **Forfeits** (built 2026-09-27, the small version of 13): whoever surrenders, leaves or runs
  out of timeouts gets no XP. The winner is paid only after the one-minute mark; under it the
  match pays nobody.
- **Rank-up rewards**, once, the first time you reach them (plan, 2026-10-02): money for each
  new division ($1,000 a Bronze division up to $150,000 a Grandmaster one); for each new tier
  money, lucky blocks (Bronze: a Standard block at once and a Mystery block; Silver a Rare
  block; from economy v4, 2026-10-08, Platinum an Epic block, Expert the first Legendary block,
  up to Reyes 2 Mythic blocks and $2,000,000), the tier's cue (the Ranked rarity, never
  tradable), the chat tag and ability spins. ECONOMY.md section 4.8.
- **Rank and money show** in the top left rank HUD (badge, name, XP bar), over every head
  (badge then username), under each portrait in the match bar, and as Rank and Money columns
  in Roblox's player list (designer, 2026-09-27).

## 12. Economy

**Lucky-block test presentation (designer, 2026-10-03):** the current test blocks use a
Roblox native owner-only hold prompt (0.5 s), large two-handed models and vivid colours in
the world and hotbar/bag. Their opening spin starts fast and lasts 1.4 s; the cue reveal
uses soft rarity rays without a square dark halo, over a dimmed world for contrast.
Multiple blocks can be placed at once; each opens independently with its own native hold.
Placed-but-unopened blocks remain saved and return to inventory on reconnect. Standard does
not cast physical light; every higher tier does, with particles preserved.
Every kind's odds and timer are ECONOMY.md section 7.2 (designer, 2026-10-04: lucky blocks
replaced cases entirely; the test timers are gone). Only Painicane may bypass those timers for
testing, while countdowns stay visible. Early opening offers a Robux timer skip priced by the
time left (4 / 9 / 15 R$). Late receipts retain a saved skip credit if the original target has
already finished.

Every number is in [ECONOMY.md](ECONOMY.md), rewritten 2026-10-08 for **economy v4, "the
forgiving economy"** (the plan the designer approved on 2026-10-08,
`docs/prompts/ECONOMY_V4_PLAN.md`), on top of the first economy plan (2026-10-02) and the lucky
blocks (2026-10-04).

**Decided**
- **Money** is earned for every ball pocketed, more for nice shots, wins and win streaks, in
  every mode including Solo and PC; a loss still pays. All numbers are x10 of the old ones
  (plan, 2026-10-02): **$100 a ball**, bank or kick +$150, combo or carom +$200, **win +$500**,
  **loss +$150**, win streak +$250 from the 3rd win in a row against people, and the **ball
  streak** bonus: from STREAK x3 each ball pays a quarter of the ball pay more for each level
  from x3 (x3 +$25 up to x8 +$150; to the shooter, not in Solo; designer, 2026-10-09). About
  **$7,750 an hour** in Classic ($7,300 before the ball streak). Play against PC pays $250 / $80 match bonuses and half
  after $10,000 of PC money a day; Solo pays $30 a ball until $3,000 a day, then $10; matches that end
  before the one-minute mark pay $10 a ball past $2,000 a day. Each pot flies a "+$100" from
  the pocket into your total, bottom left. Money farming with macros is not punished.
  ECONOMY.md section 3.
- **Difficulty multiplies money** (designer, 2026-09-26; switched on 2026-10-03): 1x Classic,
  1.5x Difficult, 2x Challenger *(tune)*, shown under each difficulty in the host menu
  (`Config.Difficulty.MoneyMultiplier`). This is separate from the XP multiplier in section 11.
- **Boosts add, then difficulty multiplies**: base x difficulty x (1 + VIP 1 + Money Party 1 +
  the Starter Pack's hour 1 + group 0.1), on match money only (designer, 2026-10-03: VIP and
  the Starter hour together are x3).
- **Money is shown** in full up to $999,999, then $1.2M. Money never trades.
- **Money packs are sold for Robux.** So Mystery and Grand Opening blocks, restock blocks, the
  block timer skips, VIP (its daily block) and ability spins are paid random items under Roblox
  policy: odds are shown as percentages that sum to 100, and where PolicyService says paid
  random items are restricted they are refused (VIP's block becomes $5,000, the Starter Pack
  $40,000 with no block). Free rewards still work there, and so does the Limited shelf (a known
  cue at a fixed price). Paid-origin items can't be traded where `IsPaidItemTradingAllowed` is
  false, and an unopened paid block only moves between two unrestricted players. Random-item
  developer products are Not Listed on Roblox. ECONOMY.md section 13.
- **Odds are percentages everywhere** (designer, 2026-10-02): the Mystery block's tier roll,
  every block, every cue, the restock slots, ability spins. Since v4 a tiny chance also shows
  "1 in N" beside its % (v4 plan section 13, approved 2026-10-08).
- **First release collectibles are cue skins only (decided 2026-09-23).** There are no table
  skins at release: every table uses the standard model. Table skins are parked in
  section 18 for after release.
- **Lucky blocks replaced cases** (designer, 2026-10-04): there are no cases in the code, the
  icons or the words. A block waits in the hotbar (and its bag), is held, thrown into the world
  and opened there with a hold prompt; the reel plays, a Rare or better cue plays its pull
  cutscene, then the "YOU GOT" card. The magic 8-ball reveal is gone. A block still on its
  timer is never thrown (2026-10-09): a throw shakes it and offers the timer skip for Robux;
  VIP has no timers, so its blocks say READY! from the moment they arrive.
- **The daily win track** (economy v4, designer 2026-10-08): the first 10 real wins of each
  day give lucky blocks in a set order, **Rare, Mystery, Mystery, Uncommon, Mystery, Mystery,
  Rare, Mystery, Mystery, Epic**; win 11 and later pay money and XP only. A win moves the
  track exactly when the anti-farm rules allow a block (solo never; the PC and disguised-bot
  limits still apply); VIP gets no extra steps. The first win ever is always a Rare block.
  **Every daily thing resets at 08:00 UTC** (the track, the login day, playtime, VIP's block,
  the anti-farm limits; was midnight UTC). ECONOMY.md section 7.5.
- **The Mystery block** (v4): it has no timer (designer, 2026-10-07): its hotbar slot says
  **OPEN!** and a tap opens its **upgrade screen** (like Star Drop, our own look). The block
  floats over a blur **still a Mystery block**; **4 presses** open it (designer,
  2026-10-09): the first shows its starting tier, each of the other 3 lifts it one tier or
  not, never down. The server rolls the final tier first, **Standard 50%, Uncommon 40%, Rare
  9.52%, Epic 0.42%, Legendary 0.05%, Mythic 0.01%**, with pity for every Mystery block, bought
  ones too (a Rare block by the 10th without one, an Epic block by the 100th; never a
  Legendary), starts it as low as the 3 later presses allow (Standard for Epic and below,
  Uncommon for a Legendary, Rare for a Mythic), then picks which later presses climb, every
  choice equally likely, so half of all Mystery blocks visibly climb and none fizzles. After the last press it jumps back into
  its slot as that tier's block, on that tier's timer. ECONOMY.md section 7.1.
- **The blocks** (plan, 2026-10-02; v4 odds 2026-10-08): six tier blocks, Standard, Uncommon,
  Rare, Epic, Legendary and Mythic, each guaranteeing at least the rarity below its name, and
  **every block can reach the Secret** (the Standard block 1 in 1,000,000). Standard opens at
  once; Uncommon, Rare, Epic, Legendary and Mythic after 1 min, 5 min, 30 min (v4; was 1 h),
  6 h and 12 h (the Gift keeps 12 h, every other kind none), all timers running at once; VIP
  has no timers at all (designer, 2026-10-07). Other kinds have their own odds rows: Mystery
  (the tier roll), Grand Opening (Rare or better, with the Firework Cue 6% and the Beta Cue
  0.4%), Starter (the Starter Pack, Rare or better), Sky, Lucky 8 and Gift. The four money
  cases, Buy-10, case sales and the Event Case are gone. Blocks come from the win track,
  rewards, the shop's Mystery and Grand Opening deals and the restock shop. At release:
  46 block cues (7/9/10/9/7/3/1 from Common to Secret, the cue skins plan, 2026-09-30). Mythic
  and Secret pulls are announced in every server, Legendary pulls in the server only
  ("X unboxed a Legendary Cue!"). The every-server line (designer, 2026-10-05) reads
  **[GLOBAL]: <username> pulled a Mythical Cue!** in a pastel rainbow, or **... a Secret
  Cue!** in red, on the top banner and in chat. No announcement names the cue, only its
  rarity. A Legendary or Mythic block in the restock is announced in every server too (v4).
- **The reel** (designer, 2026-10-08): a block's reel shows only its own pool, every rarity
  it can drop; one showcase tile (an Epic-to-Secret cue printing its own odds) passes by each
  spin, never near where it stops; every other tile is at the real odds; no slot-machine looks.
  ECONOMY.md section 7.2.
- **Pull cutscene sounds, for later** (designer, 2026-10-05): when the Mythic and Secret
  cutscenes are redone, they also get the Legendary's two bonus reveal sounds: the "Cinematic
  Hit" on the white flash (`Audio.Ui.LegendaryHit`) and the very faint looping angelic
  "Aurora" ambience under the card that tapers after it closes (`Audio.Ui.LegendaryAurora`).
  The Legendary has no sky effect (its gold aurora was dropped, 2026-10-05).
- **The player stands still through every pull cutscene** (designer, 2026-10-05): no walking
  or jumping, and no turning with the camera, even with shift lock on.
- **What money buys** (v4 prices, 2026-10-08): **Mystery blocks** ($4,900; 10 for $44,100),
  the **Grand Opening block** while it runs ($24,900; 3 for $69,900; 10 for $219,000), the
  **restock shop** (new blocks every 10 minutes on the clock, the same in every server: three
  slots that each roll a **Rare, Epic, Legendary or Mythic** block, a Mythic about every 5
  days, and a VIP-only fourth from a richer table; Rare $19,900 up to Mythic $4,990,000) and
  **ability spins** ($12,500 each). A block's timer is skipped for Robux only, **4 / 9 / 15 R$
  by time left**; there is no money skip and no Limited cue for sale at release. Buying with
  money costs about 2-3x the Robux price for everyday blocks and up to about 6x for the rarest
  known blocks (designer: "about 3x, you set the final ratio"). ECONOMY.md section 9.
- **Rarities** (designer, 2026-09-27): **Common, Uncommon, Rare, Epic, Legendary, Mythic,
  Secret**, from lucky blocks. Three sit outside that ladder and never come from a tier
  block: **Unique** (numbered copies: the Firework Cue, 1,000 ever, and the Beta Cue, 100
  ever, from the Grand Opening block; there is no Founder's Cue, ever), **Ranked** (the ten rank cues Bronze
  Cue to Reyes Cue, each card in its tier's colours; designer, 2026-10-08; they keep the
  Exclusive group's rules: never traded or sold, one each) and **Exclusive** (the VIP Cue, the
  Starter Cue, later season cues). "Ultra" is dropped; VIP is an Exclusive cue, not a rarity.
  Colours in `docs/UI_STYLE.md`. Rarer cues have special trail and pocket VFX. A cue card shows
  its rarity in its bar and its chance per Mystery block in a corner chip (UI_STYLE section
  17).
- **Duplicates can be sold back** for money (designer, 2026-09-27; no trade-up): Common $150 up
  to Secret $25,000,000 (plan, 2026-10-02).
- **No direct buying of block cues** (designer, 2026-09-27): Common to Secret cues come only
  from lucky blocks and trading. The **Limited shelf** can sell exclusive, numbered Unique cues
  (never in a tier block) for a set time, sometimes copy-capped, then never again, so they
  become trade-only; it is empty at release (designer, 2026-10-04). Every cue shows how many
  copies exist. Retired (vaulted) cues never come back (plan, 2026-10-02). ECONOMY.md
  section 9.
- **A cue carries its own effects.** Every cue defines the cue ball's TRAIL and the burst
  when a ball is pocketed, so the cue you equip changes how the table looks while you play,
  not just what the stick looks like. The default cue and every common one use the same
  minimalist trail: a thin white translucent wisp, like wind off the ball. Rarer cues
  replace it with their own trail and their own pocket effect, and that pairing is the main
  reason to want one. Effects are catalog data (a named style), never code per cue.
- **The Grand Opening at release** (v4, designer 2026-10-08): the **Firework Cue** and the
  **Beta Cue** come only from the **Grand Opening block** (Rare or better; 6% and 0.4% a
  block, **capped at 1,000 and 100 copies ever** on a counter every server shares; a player
  who owns one, or once all are found, sees that row as Rare; a player's 1,000th block
  guarantees Beta while any are left), sold for **30 days** from a start the designer sets at
  publish (off until then; placeholder colours for now). The **launch bonus** runs on the same
  window: every money pack gives +30% money and the 45 R$ Mystery10 gives 13 blocks (it
  replaced the 30% release sale, whose products are retired). There is no Founder's Cue
  (designer, 2026-10-05). After launch, about one new Limited every 2 weeks when art exists
  ($149,000-$499,000, some for Robux); none is scheduled yet. Seasons, the Cue Pass and event
  blocks come after release.
- **Free rewards** (plan, 2026-10-02; designer, 2026-10-03; blocks and no popups, 2026-10-04;
  v4, 2026-10-08): **the first week**, a new player's first 7 login days within 14 days of
  joining, in a row or not ($5,000 + 1 Mystery block, **an Epic block**, $10,000, 2 Mystery
  blocks, a Rare block, 3 Mystery blocks, **a Legendary block** + 2 ability spins); a day
  counts only after a finished match that day; then **later weeks** ($5,000, a Rare block,
  $10,000, 2 Mystery blocks, $15,000, 3 Mystery blocks, an Epic block + 2 ability spins; one
  free streak freeze a week); a **28-day track** of total days (day 8 a Rare block, 2 Rare,
  2 Rare, day 28 an Epic block); **playtime gifts**, all within the first hour (5 min $1,000
  up to 60 min a Rare block + 1 spin); **VIP's Rare block** each day; the game's **group**
  (Join and Claim: 3 Mystery blocks once, +10% match money while a member); a **favorite**
  reward ($10,000 + a Lucky 8 block); six **like codes** the designer switches on live at like milestones; **invites** (a
  brand-new friend's first real win gives both a Rare block; the inviter's once ever, at most
  5 a month); **codes** (WELCOME, 8BALL, ROOFTOP, RELEASE). Codes give only money, lucky blocks
  and spins. **Everything is claimed in the Rewards menu**: nothing is given by itself on join
  or at a playtime mark, and there are no reward popups, reminder toasts or come-back screens
  (designer, 2026-10-04). The one exception is the **Gift lucky block** (designer, 2026-10-07):
  given once, the first time a player leaves the game (not a teleport to a match), on a 12-hour
  timer that runs from that leave. On their next visit to a lobby (after the tutorial) it falls
  from the sky in a short cutscene: black bars, a glowing gold trail, a crash with a flash,
  shake, shockwave and particles. It waits on the floor until they pick it up (hold E, X or touch).
  Not picked up: it falls again next visit.
  ECONOMY.md section 10.
- **Ult spins** ("Ability Spins" to players; designer, 2026-09-28, section 9): the spin
  screen gives ults; spins come from play (starter, daily, VIP's extra daily spin, rank-ups,
  login day 7, playtime, codes), Robux packs (9 R$ a spin up to 299 R$ for 50) and money
  ($12,500 a spin), with true odds shown as
  %, pity and Lucky Spins. The plan (2026-10-02) moved Magnet to Uncommon and Heat Seeker to
  Common; Portals is flagged for a re-measure. Ults are kept in 3 slots; a spin replaces the
  selected slot's ult. ECONOMY.md section 11.8.
- **VIP** (one-time pass, **399 R$** *(tune)*; v4, 2026-10-08: was 499, and 599 before the
  Quick Cases pass retired into it): 2x money, **no block timers** (every block opens at once;
  designer, 2026-10-07), **a Rare lucky block every day** (designer, 2026-10-08; $5,000 where
  paid random items are restricted), Skip and Auto Spin on the spin
  screen, +1 free ability spin a day, the VIP slot in the restock shop (a fourth block every
  restock), the VIP Cue, a [VIP] chat tag before the rank tag ("[VIP] [GOLD] Name"; the name
  in chat keeps Roblox's colour) and a rainbow name over the head whose colours drift slowly
  (designer, 2026-09-28). Never better odds, no XP boost, no discount, no extra win-track
  steps. A **welcome offer** at half price (199 R$) for 24 hours from the first join, plus one 24-hour comeback window 7 days later (designer, 2026-09-27; Roblox's rules
  call short pressure windows unfair, so not 15 minutes). ECONOMY.md section 11.
- **Starter Pack** (**19 R$**, v4; once, in the first 7 days *(tune)*): a Starter lucky block
  (Rare or better, Epic 9%), $25,000 and 1 hour of 2x money; where paid random items are
  restricted, $40,000 and the hour, no block.
- **Other Robux products** at release (v4 prices, 2026-10-08: everything cheaper, the top
  price **1,699 R$**, one phone Robux pack): 3 game passes (VIP, Ability Slot 2 and 3 at 49 and
  79 R$) and 34 developer products: VIP offer, Starter Pack, 7 money packs 25 to 1,699 R$
  (about 1.7x the money per Robux of before; the first-pack double is off; "Best value" is the
  biggest), Mystery blocks (5 R$, 10 for 45), Grand Opening blocks (19 / 49 / 149 R$), the
  restock Rare, Epic, Legendary and Mythic blocks (15 / 99 / 599 / 1,699 R$), three timer
  skips (4 / 9 / 15 R$), Money Party (49 R$), 4 spin packs, 2 Lucky Spin packs, and the six
  retired release-sale copies (kept, never deleted), plus a Get Roblox Plus button. Bundle
  savings are always against the one-by-one price. The shop is one scrolling page with no
  tabs.
  Never anything that protects rank, no luck economy, no money bets, no offline income; the one
  luck purchase is ability spins (odds always shown, pity kept). Later: a Cue Pass, gifts,
  the Beta Cue on its own. ECONOMY.md section 11.
- **Items:** one catalog for cues and abilities (stable id, type, rarity, model, effect); the
  type field leaves room for table skins later. A cue is saved as a count per catalog id
  (2026-09-28, ECONOMY.md section 18: small saves, a duplicate is a count above 1); numbered
  Unique cues keep their copy number (#412). Every block and cue copy carries a free or paid
  origin. Abilities are owned flags. **Block cues and Unique cues can be traded; Exclusive and
  Ranked cues never (VIP, rank and season cues; designer, 2026-09-28), except the Starter Cue. Ults are
  account-bound (never traded). Money is never traded.**
- **Trading is in the first release** (built 2026-10-03, the screen is the GUI lane's): open to
  **anyone in the server, no gate** (designer, 2026-10-03; the plan's 25-win gate was dropped).
  Cues and ready lucky blocks, up to 8 a side, never money; any change restarts a 3-second confirm on
  both sides; a warning when the sides are far apart by copies in existence (a block's worth
  worked out live from its odds and the copies of each rarity, v4); an unopened paid block
  only moves between two players whose paid random items are not restricted; the last 50
  trades in a history. The swap is server-side and atomic with a ledger: both saves change or neither.
  A trade pays no finder's money. ECONOMY.md section 12.
- **Index** (designer, 2026-09-26): a collection screen of the game's cues.
- **Cue models:** every cue is its own small mesh plus a named effect style. Hundreds are
  expected, added as data rows plus assets.
- **Shop, inventory, the index, trading, save data and the first-time flow exist before the
  game is public.**

- **The Index** (designer, 2026-09-28): every cue in the catalog by rarity; a cue never owned
  is a "?" card; a cue counts once ever owned (selling keeps it). Tapping a card shows it on
  the side: its name (even before it is found) and the cue turning in 3D, a black silhouette
  until found, its real look after. Completing a rarity row pays once (Commons $10,000,
  Uncommons $25,000, Rares $75,000, Epics $250,000; plan, 2026-10-02; the rows above Epic have
  no reward). The rows' "Collector" titles are gone (designer, 2026-09-28: they added nothing).
  ECONOMY.md section 18.
- **The Cues tab** (designer, 2026-09-28): no rarity filter chips; one sort button turns
  through Rarest first (the default), Common first, Most copies and Name A-Z. Sorting by
  rarity puts Ranked and Exclusive between Epic and Legendary (the rank cues highest tier
  first), and Unique on top.
- **Finder's money** (designer, 2026-09-28; amounts from the plan, 2026-10-02): the first time
  a player gets a cue it pays extra money by rarity, once per cue ever (Common $500 up to
  Secret $500,000; Ranked and Exclusive $5,000, Unique $10,000; *(tune)*); never for a cue got in a trade.
  ECONOMY.md section 18.
- **The menus** (designer, 2026-09-28; the shop changed 2026-10-02; blocks 2026-10-04): four
  buttons in one column on the left, Shop (one scrolling page, no tabs; emptied to its frame
  and jump buttons for the GUI overhaul), Inventory (two tabs, Cues then the Index; lucky
  blocks live in the hotbar and its bag, not here), Rewards (login loop, 28-day track,
  playtime, codes, group, favorite, invites) and Trade.
- **Bots' cues** (v4, 2026-10-08): a bot's cue rarity follows what real players at its tier
  own (Bronze 25% Epic or better up to Reyes 99%); a bot never shows the Secret cue.
  ECONOMY.md section 15.
- **Targets** (approved with v4, 2026-10-08; replacing the day-30 targets of 2026-10-02): the
  share of players active in the last 7 days who own one, at day 7 / 30 / 60: Epic 15-22% /
  25-35% / 35-45%, Legendary 2-3% / 6-9% / 10-14% (week 1 the designer's), Mythic 1% or less /
  0.7-1.2% / 1.2-2%, the Secret far rarer (0.05-0.15% at day 30). `tools/economy_model.py`
  checks them against the numbers in Config. ECONOMY.md section 1.
- **Analytics**: every money source and sink goes to `AnalyticsService:LogEconomyEvent`.
- **R15 only** (designer, 2026-10-02): Roblox pays more per Robux on purchases by age-checked
  US adults only in games without R6.

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

The whole first session is the tutorial (built 2026-10-03, the tutorial lane; the brief is
`docs/prompts/TUTORIAL_PROMPT.md`, the step-by-step record `docs/parallel/tutorial.md`). It
runs in the real public server the player lands in, not a separate place. The server keeps the
step in the save (`Flags.Tutorial`) and owns every rigged part; the client only shows guidance.

**Decided**
- **Who gets it:** a brand-new save (no match played). Anyone with a match or a win is done.
- **The look:** big white Fredoka text at the top with a thick ink outline (no strip), a light
  dim with a lit hole round the target, and a white cartoon pointing hand (our own drawing in
  the style of the designer's reference) that taps, drags and pulls. A line of white arrows on
  the floor leads to the table. Every prompt has its own words and gesture for mouse, touch
  and gamepad. A small **Skip tutorial** button sits top right the whole time.
- **What is hidden:** in the first server Shop, Inventory, Rank, Free Reward and Trade are
  hidden; Abilities appears at its lesson. No offers show while the tutorial runs (the player
  attribute `TutorialActive`), and no money is given on join: the day-1 claim waits in the
  Rewards menu (for everyone, designer 2026-10-04: no reward popups).
- **Game 1 (rigged, against a disguised bot):** the arrow leads to the nearest empty 1v1 table,
  reserved for them (lobby bots leave it alone). On the pad the host card shows only Request
  opponent; 2 s later the tutorial bot (a random real avatar and name, a Silver badge) joins
  and the player breaks. The break is fixed: any pull plays the rigged break, which pots 3
  solids and leaves a 4th by a corner and the 8 by a pocket. Then: "Drag to aim!" with the
  long guideline and strong ball highlights; a hidden pull (Magnet's strength, no visuals)
  helps the player's balls near pockets; the bar fills and "Use your ability!" teaches Heat
  Seeker (the hand taps a ball, then Confirm). The first miss gives the bot a visit where it
  pots one and scratches, which teaches ball in hand. After that the bot only plays weak shots
  that never touch the player's balls or the 8. "SELECT WHICH POCKET!" lights the pocket
  nearest the 8. Losing on the 8 is impossible in game 1 (an early 8, a scratch on it or a
  wrong pocket puts it back as a plain foul). On the winning shot the bot shouts "AUGHHHH!",
  jumps and vanishes; the result screen shows Leave only.
- **After game 1** (lucky blocks, 2026-10-04): NEW RANK! Bronze ("Claim your rewards in
  Rank!") -> **Block**: Bronze's Standard lucky block sits in the hotbar; the hand shows
  holding it from its slot, throwing it and holding the prompt to open it; it opens to an
  Uncommon cue (forced) -> **Equip**: Inventory appears and the hand leads to it, the new cue's
  card and Equip ("Equip your new cue!"; closing the Inventory without equipping moves on;
  designer 2026-10-03) -> **RareBlock**: the hand rests on the match's Rare block in its hotbar
  slot, counting down its 5-minute timer (a tap reports it seen) -> **Abilities**: the icon appears,
  the hand on it -> **Spin**: the one starter spin lands on Fire Shot (Magnet until 2026-10-08)
  -> **Code**: "Type RELEASE
  for 3 more spins!" -> **Back**: "Click Back".
- **Game 2:** the arrow to a pad; the host card shows only Join Global Queue; the search turns
  into a match after 1 s against the Bots lane's disguised Bronze bot in a global arena. Win or
  lose, no rematch: "Press Lobby!" teleports them to a public server.
- **The real server:** everything shows; the day-1 claim ($5,000) waits in Rewards. Then
  nudges, one at a time and only in the lobby (an ignored one comes back): Rank (claim the
  held rank rewards), Inventory ("Your cues live in the Inventory!"), Shop, Free Reward. Then
  **BlockWait** while the Rare block's hotbar slot counts down, and **BlockReady** ("Your
  block is ready!" on that slot) once it ends; opening it ends the tutorial.
- **Leaving and coming back:** game 1 starts over from the arrow; the reward steps resume where
  they were; game 2 goes back to its arrow (or continues in the arena); after game 2 it picks
  up in the real server.
- **Skip and cancel:** Skip asks "Skip the tutorial?" Yes / No. Skipping (mid-game 1 the game
  goes on with guidance off), joining another table or a friend joining their pad ends it:
  everything shows at once and the normal rules apply (the first win's Bronze, its Standard
  block, the Rare block).
- **Rules changed for everyone with the tutorial (2026-10-03):** Bronze gives its Standard
  block at once; every other rank reward (money, blocks, cue, tag, spins) and every later rank-up is held
  until claimed in Rank (a claim card on the roadmap, the rewards fly to where they live); 1
  starter ability spin; Heat Seeker is the default ability; the code RELEASE (3 spins) replaces
  ABILITIES.
- **Funnels (Roblox analytics, server only, `src/server/Funnel.luau`):** the onboarding funnel
  of 22 steps, from Joined to Came back the next day (`Shared/Tutorial/Steps`, each logged once
  per player); side events (ball in hand shown, the bot's scratch, lost game 2); the
  TutorialExit funnel for skipped or cancelled players (then first game, first win, second
  match, next day); Shop (opened, viewed an item, pressed buy, bought; per session); Block
  (Got, Ready, Opened, Equipped; per block); Ability spins (opened Abilities, spun, equipped,
  used in a match).
- **Daily streak and playtime gifts:** in the Rewards menu, claimed there and never given by
  themselves; numbers in ECONOMY.md section 10.
- **No reminders** (designer, 2026-10-04): the leave-menu and focus-loss reminder toast, the
  come-back screen are gone; the Rewards dot is the only nudge. The first-leave gift came back
  as the Gift lucky block (designer, 2026-10-07; section 12).

**Open**
- Whether the VIP Cue's finder's money should pay a VIP player on their very first join (it
  gives $5,000 before the tutorial's real server; see the lane file's integrator notes).

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
  - **Regular lobby, wood frames:** the tournament blue cloth (photo-16 blue, the pro
    lobby's and the arena's) on the 1v1 tables (designer, 2026-10-06; it was bright
    yellow-green), raspberry red on the 2v2, slate charcoal on the 3v3.
  - **Pro lobby, black frames:** bright blue cloth (photo-16 blue) on the 1v1 tables, and the
    same raspberry red and slate charcoal on the 2v2 and 3v3.
  - The red and charcoal were picked by colour difference against every ball so none blends
    in: a truer red hides the red and maroon balls, a darker charcoal the 8.
  - Until the hub map, the baseplate shows every combination (section 10). The cloth is a fine
  repeating texture tinted per look, lightly played: a faint break line, a rack patch, chalk
  near the pockets and a spot sticker.
- **Cues (2026-09-29):** every cue skin is one shared, detailed cue mesh (tip, ferrule,
  shaft, silver joint, forearm, ring, wrap, sleeve, rubber bumper) with its own pictures on
  it, painted from a five-panel paint kit (ChatGPT per `assets/cue/template/CHATGPT.md`).
  Classic, the default cue, is the first: maple shaft, rosewood forearm, black linen wrap,
  silver rings, glossy black sleeve. Cues without a skin keep their coloured-band look until
  they get one; a new skin is data and pictures, never code.
- **The cue skins (imported 2026-10-01):** every block, rank and Exclusive cue has its own skin
  (only the Unique cues still wear bands). Climbing the tiers adds, in order: the surface
  (Common), a tint and moving glow (Uncommon), an aura and a coloured trail (Rare), a stronger
  aura, its own pocket burst and orbiting ribbons (Epic), a 3D piece and a moving surface
  (Legendary), rigged hologram creatures (Mythic: the Celestial Dragon swimming along the cue,
  the Kitsune's running fox, a rising creature when a ball drops), and Eclipse's small glowing
  eclipse in a gold corona (Secret). The full aura shows everywhere, in the hands while aiming
  and on the back (designer, 2026-10-01), and it must read clearly in the bright lobby: a
  saturated colour cloud, an HDR glow the lobby's Bloom picks up and crisp star accents, with
  the 3D creature outlined (the "VFX v2" standard, judged only in the real lobby lighting). The
  shop, block reels and inventory show a rendered picture of each cue; the Index shows the live
  3D cue.
- **The cue's size (designer, 2026-10-01):** 7 studs long, 1.6x wider than a real cue's
  proportions through the shaft and butt (0.32 stud butt) with a slim tip, so its art reads
  next to a Roblox character.
- **The cue on the back (designer, 2026-09-28):** every player carries their equipped cue on
  their back, diagonal with the tip over the left shoulder, on any body (R15, R6, tall,
  small). It disappears the moment the cue is in their hands and comes back when they put it
  down; sitting down it tilts a little further so it clears the seat.
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

- **Copy numbers on early cues** (asked and approved 2026-10-08, planned after the Cues
  menu): the first 100 copies of every Rare, Epic, Legendary, Mythic
  and Secret cue are numbered #1 to #100 from the public release; Commons and Uncommons never
  (an earlier answer the same day was the first 1,000 of every block cue). Unique cues keep
  numbering every copy; Ranked, VIP, Starter and Classic stay plain. A numbered copy is its own
  card (gold number above the name) before that cue's plain stack. Sell dupes never sells a
  numbered copy (one sells only from its own card, after a warning); a sold number is gone for
  good. How many exist shows on the big card for every cue. Today only Unique cues are numbered and
  other cues are saved as a count, so this changes saves, selling, trading and the copy
  counters (`docs/prompts/CUES_LIVELY_PROMPT.md`). A numbered copy also wears its number on the
  cue itself (asked 2026-10-08): a gold nameplate near the butt end only, never near the tip
  (designer, 2026-10-08).
- **Global boards in a new home** (parked 2026-10-07, one of the last things before release):
  the Top Wins and Top Rank boards left the player list (it is now like Roblox's own list);
  the lobby signs still show them. Where they go next (a menu page, say) is open.
- **Money sound as a coin burst** (tried and reverted 2026-10-02): a chip landing would play
  one coin for $1-$5 and a rapid burst for more (about 6 for $10, 40 for $100, 70 for $1,000).
  Slicing CashLand sounded ugly; of five Creator Store coins the designer liked "coin2"
  (134583420216867, a double clink) best, but even quiet it was too much. Back to the single
  CashLand for now.
- **Snack counter** (parked 2026-09-26, taken off the rooftop map at its Checkpoint A): a
  counter that hands out non-alcoholic drinks and snacks the player can drink or eat (a tool
  with a short animation).

- Private friend-locked tables. Party up with friends.
- Replay or "clip that" feature. Cinematic replay camera.
- Trading UI polish, item showcases, serial plaques.
- Seasons with themed sets beyond Season 0.
- More ults beyond the planned 13 (section 9). New ideas go here. Sabotage ideas (fog, shaky
  aim, shrinking the opponent's guideline) are out: ults help the user.
- **After the 13 abilities** (parked 2026-09-29, ABILITIES_REPORT section 9): a generated or
  downloaded detailed tiger model for Guangdong Tiger; Portals made stronger if playtests find
  it weak (a free pot through the kept portals, or a move to Rare); the PC opponent and bots
  using abilities beyond Magnet, with a picker for Heat Seeker and Portals; a looping "how it
  works" clip per ability on the spin screen; sound sheets per rarity.
- Offline play if Roblox ships it.
- New game modes and table types.
- **Collectible table skins** (parked 2026-09-23, after release): each a retexture of the one
  standard table model (changed 2026-09-24; it used to be a full model per skin), the host's
  table used for the match, rare ones with VFX, a
  table loot box, Beta/VIP tables, tradable, serial plaques for limited ones.
- **Walk to the next shot** (parked 2026-09-24): when the same player shoots again from a
  different spot, their body currently jumps there; a short walk round the table would read
  better for watchers.
- **Swerve and a curved aim guideline for side spin** (parked 2026-09-23): squirt off the aim
  and a path that curves on the cloth, with the guideline curving to match. The physics exists
  behind Config.Cue.SideSpinBendsPath.

## 19. Open questions (collected)

- Age-rating and DevEx rate verification (section 2).
- The rest of the ult list, its rules and how ults are earned (section 9).
- Pro lobby look (section 10).
- A pro-lobby teaser door at release (section 10).
- The bots' details (section 11).
