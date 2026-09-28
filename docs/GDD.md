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
  cue-ball icon for spin.
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
  a small ring where it comes down, and a red cross where it would fly off.
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
  tables nearest the spawn. The four 2v2 stand together (2 x 2) in the back-left corner and
  the two 3v3 in the back-right corner, seen from the spawn (changed 2026-09-26).
- **Joining: step onto the table's queue pad.** Each table has one glowing rectangular pad in
  front of it, lying along the long side that faces the entrance (changed 2026-09-26 for the
  rooftop map; a round pad was tried the same day and dropped), longer for bigger modes,
  holding both teams (2, 4 or 6). It is see-through glass tinted like its rim (blue with room,
  green with someone on, gold when full or playing; designer, 2026-09-27). Its mode is written
  big on it with JOIN or the count;
  outlines pulse out of it and a big arrow bobs over it while it has room. Joining is instant: the host's card pops up the moment you step on. Stepping on plays a
  sound and a VFX and the rim turns green so everyone can see someone is queueing. There is no
  accept step; anyone may step onto a waiting pad with room, and walking off leaves at once. Everyone else can stand around and watch. Players in a match stay by their table:
  invisible walls, a few studs beyond its area and its pad, let someone waiting for their turn
  walk about a little but never reach another table (designer, 2026-09-26). The small sign
  over a table's pad (the mode big, the host, count and difficulty, and a WAITING, STARTING 3,
  FULL or PLAYING pill; an empty pad's sign has no pill and no "join" words, since stepping on
  is the way in; no abilities; designer, 2026-09-27) shows when you walk right up to it, and
  to guests while they wait on the pad. That pad's bobbing arrow hides while its sign shows.
- **No settings and no Start: just play** (designer, 2026-09-27). The first person on is the
  **host** and gets a small card: the game ("Classic 1v1"), how many are on the pad, and
  "Waiting for opponent..." ("Waiting for players..." on 2v2 and 3v3). It keeps out of the
  way (designer, 2026-09-27): in the very top right corner (beside Roblox's top bar), at 85%,
  on a phone-sized screen, shrinking only to end above the jump button; on the right, halfway
  down and a bit bigger (1.3x), on a big one (PC, console, tablet), kept above a tablet's jump
  button. The waiting line's three dots light up one by one
  so the wait looks alive. Public tables play
  Classic (whether ults can be turned off: section 9). If the host leaves, the next to arrive becomes host.
- **A full pad starts by itself**, **3 s** *(tune)* after the last one stepped on ("Starting in
  3"), so someone who walked on by accident can step off. Then straight to the coin flip,
  about 3 s and a few words at a time: "YOU ARE HEADS" (or TAILS), the flip, then "YOU BREAK"
  or "<NAME> BREAKS" for over a second (designer, 2026-09-27). **Teams go by arrival**: the
  first on (the host) is team A, the next team B, and so on alternately.
- While the pad has room the host's card offers **Request opponent** (**Request players** on
  2v2 and 3v3) and **Join Global Queue** (below). Alone on a **1v1 table** it also offers
  **Play against PC** (does nothing until bots exist) and **Play solo** (starts immediately);
  the 2v2 and 3v3 tables have no solo. There is no automatic start against PC.
- **Request opponent / players** (designer, 2026-09-27): everyone in the server who is not at
  a table gets a small popup at the bottom of the screen, the host's face and "<name> needs an
  opponent..." (or "needs players...") with **Join** (stands them on the host's pad) and
  **Dismiss**, small and low so it never covers the player's legs. It goes by itself after 15 s *(tune)* or as soon as the pad fills or the host
  leaves. While a request stands the host's card folds up (animated) to the game and a greyed
  "Requested!"; if nobody came it unfolds again after the same 15 s, with the full choices and
  Request ready to press again. Under "Requested!" a red **Cancel** (designer, 2026-09-27)
  takes the request back: everyone's popup goes at once and the card unfolds to the full
  choices; Request can be pressed again 3 s *(tune)* after the last request.
- Every match is played on the one standard table model, in one of its looks (section 16).
  Collectible table skins are parked until after release (section 18).
- **Modes at release: Solo, 1v1, 2v2, 3v3**, each with friends or PC fill.
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
- **Global queue** (designer, 2026-09-28; it had been planned for after release): the host's
  4th choice, **Join Global Queue**, looks in every server for a side of similar rank and
  teleports both into an **arena**.
  - 1v1 alone; **2v2 needs 2 on the pad and 3v3 needs 3** (a whole side). The first whole
    side by arrival goes; anyone extra stays and hosts the pad. Greyed with "Needs 2 on the
    pad" until then.
  - **Stay on the pad while searching**: the card folds to "Searching worldwide..." with the
    time and a red Cancel; stepping off cancels. Anyone in the server may still step on: a
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
  is in its box. PC never plays PC.

- **Spectator seating:** the chairs and sofas are sittable, and sitting is free look - the
  player is seated and the camera is left alone. Watching a table through its own camera is
  a separate feature and waits for spectating proper (Roadmap 2.3).

**Open**
- Difficult and Challenger may be for pro lobbies only (designer thinking, 2026-09-27); until
  then public tables play Classic. Whether a table can turn ults off is open (section 9).
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
- **One end-of-match screen for both players** (designer, 2026-09-27; replaces the separate
  win and lose cards): both sides with VS, the winner's picture gets a shining crown, then
  your XP bar animates up, down or holds and the match's money is pocketed into your total. A
  rank-up brings a big NEW RANK! popup. No finisher effect.
- Emotes during the opponent's turn for players and spectators.

## 9. Ultimates (abilities)

**Decided**
- **Abilities stay, are now called ultimates ("ults"), and come in the release** (designer,
  2026-09-28; this replaces the 2026-09-26 "not in the release, up for debate" call and the
  old cooldown design). The designer has more details coming; this is the general shape.
- **An ult is a comeback trump card**, not a regular ability: its job is to level the playing
  field so a player who is well behind can catch up. A player normally uses it **once** a
  match, and **twice** only in rare long matches where nobody pockets for a long time.
- **One ult bar per player, filled by the same rules for everyone** (never by what they own or
  paid for), and proportional to what both players make:
  - **Your own balls** fill a little, and less and less for balls in a row: a player on a run
    gains little.
  - **Trickshots** (the nice-shot kinds: Bank, Kick, Combo, Carom) fill a big chunk, and the
    player sees the bar jump up with the "Nice shot" popup. A normal ball is a small visible tick.
  - **The opponent's balls** fill yours, more the further behind you are. A player who falls
    **4-5 balls behind** should have a full bar when the turn comes back to them.
  - **A small trickle every turn**, so a long match with few pockets can reach a second ult.
  - Starting numbers to test *(tune)*: a bar of 100; your own ball +5, then +3, +2, +1 for
    the next balls in the same turn; a trickshot +20; an opponent's ball +5, plus 7 for every
    ball you are then behind; +2 for each of your turns that ends; the bar empties when used;
    at most 2 ults a match. Check "about one ult a match" with a small simulation (like
    `tools/economy_model.py`) before building.
- **Using it:** a full bar **shakes and glows** to invite the tap. The player activates it on
  their own turn **before they shoot**; a short **cutscene** plays (the ult's name, the
  player's avatar, its sound), then a clear "ULT" mark stays on the cue ball and HUD so both
  players know the next shot is the ult shot. A full bar can be held as long as the player
  likes: the idea is to spend it on a turn with no clear shot.
- **Ults act on the balls and help the user.** They almost never sabotage the opponent (no
  fog, shaky aim or shrunken guidelines).
- **Rarities** are the item rarities (section 12): Common, Uncommon, Rare, Epic, Legendary,
  Mythic. Some ults are stronger than others, but higher rarities put the emphasis on cooler
  visuals and sound, not on power: Magnet is a fully useful ult, just less cool than a Mythic.
  Planned set: 3 Common and 2 each of Uncommon, Rare, Epic, Legendary and Mythic (13).
- Every player equips exactly one ult per match. Every player has a starter ult, **Magnet**,
  free forever (kept from the ability plan). Friend tests may unlock every built ult with a
  developer flag in Config. The server validates every ult; each one hooks into the custom
  physics for one shot.
- **The designer's first six** (2026-09-28):
  - **Eagle's Eye** (Common): shows the full path of the shot, every bounce included (Classic
    shows only short lines). An eagle screech.
  - **Magnet** (Common): a low vibrating magnetic hum; a ball heading for a pocket that is not
    a direct hit is pulled in (a nudge that rescues near misses, never a vacuum).
  - **Steel Ball** (Legendary): a "nyo-ho" call on activation; after contact the object ball is
    guided into the pocket you were trying for, and the cue ball spins to line up your next
    nearest ball (the 8 when it is next).
  - **Black Flash** (Legendary): the first ball hit shatters in an immense black flash and is
    gone from the table, counted as pocketed for whoever owns it.
  - **Black Hole** (Mythic): whatever the cue ball hits first opens a black hole that sucks in
    the balls near it, except the opponent's.
  - **Guangdong Tiger** (Mythic): a giant tiger appears at the first ball hit and swipes the
    balls around it off the table, except the opponent's.

**Open**
- The designer's further details (coming). The other seven ults: 1 Common, 2 Uncommon, 2 Rare,
  2 Epic. Candidates from the 2026-09-28 brainstorm: Anchor, Big Mouth, Safety Net, Rubber
  Rails (Common); Flash Step, Extra Life, Phantom, Gust (Uncommon); Heat Seeker, Split Shot,
  Drift, Rewind (Rare); Meteor, Time Stop, Chain Lightning, Wormhole (Epic).
- The 8-ball and ults: can an ult pocket or destroy the 8 (suggested: only on your own legal
  8 shot, never early)? Do fouls still count on an ult shot (scratch, wrong ball first)? What
  Black Flash does when the first ball hit is the opponent's (suggested: a normal foul, no
  flash). Balls an ult pockets probably fill no bar.
- How many balls an area ult (Black Hole, Guangdong Tiger) may take at most (suggested 2-3),
  so a Mythic stays a spectacle rather than a match-ender.
- Whether the leader's bar fills at all, and the second-ult rule.
- On or off per table: public tables play with no settings since 2026-09-27 (section 6).
- How ults are earned. The old plan was an ability gacha with Robux spins (section 12), but
  ECONOMY.md never sells anything that helps win; since some ults are stronger, they should
  come from play or money, or all be equal in power.
- Sounds must be original or licensed (section 8): the "nyo-ho" and screech are recorded or
  made for the game, never clipped from a show.

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
- Players are **Unranked** until their first rated match, then Bronze I after one game.
- **Rank badges** are drawn (2026-09-26, `assets/ui/ranks/`): 1 to 5 stars show the division
  from Bronze to Diamond, 1 to 5 gems from Expert to Grandmaster; crowns from Expert up; Reyes
  and Unranked have one badge each. Look and shine: `docs/UI_STYLE.md` sections 6 and 7.
- **One number, rank XP, is the only progression** (designer, 2026-09-28: the separate
  account Level and EXP are gone). Rank is the game's main way to show status. **XP is never
  lost**: losses give a little to Platinum (+100/+75/+50/+25) and nothing from Diamond, so
  nobody ever drops a rank. Division sizes grow up the ladder: flat and quick to Platinum,
  then about 17% bigger every division from Diamond I (8,000 XP) to Grandmaster V; **Reyes is
  a fixed 2,352,500 XP** (designer, 2026-09-28; it replaced leaderboard seats). All numbers:
  [ECONOMY.md](ECONOMY.md) section 4.
- Every match against a person or PC gives XP. Solo never does. **Skill sets the speed**:
  harder difficulties pay more (Classic 1, Difficult 1.25, Challenger 1.5; Classic wins fade
  to x0.5 in Diamond and x0.2 from Expert), a win streak gives +25% from the 3rd win in a
  row, and beating stronger players pays more and much weaker ones less (an Elo gap factor).
  PC matches give x0.75 XP to Diamond and x0.5 from Expert at launch. Teams: every player by
  the same rules against the other team's average.
- **XP boosts** (add together): the Rookie Boost (+100% for the first 25 matches), the first
  win of each day (double), VIP (+50%).
- Targets: Silver in about 30 minutes, Diamond in about 7.5 hours, Expert in about 2 months at
  an hour a day, Reyes about a year for a 3-hour-a-day grinder; only a few ever reach Reyes.
- **Difficulty unlocks by rank** (designer, 2026-09-27): host Difficult from Gold I,
  Challenger from Diamond I; guests may join with a warning.
- **Ten bots, one per tier** (designer, 2026-09-26): the Bronze bot is the easiest and the Reyes
  bot the hardest, and each player meets the bot of their rank.
- Rating is saved under a season label ("Season 0"). **Ranks never reset** (designer,
  2026-09-28); seasons may give rewards for the highest tier reached that season.
- **Forfeits** (built 2026-09-27, the small version of 13): whoever surrenders, leaves or runs
  out of timeouts gets no XP. The winner is paid only after the one-minute mark; under it the
  match pays nobody.
- **Rank-up rewards**, once, the first time you reach them: money for each new division (the
  money Levels used to pay); for each new tier money, cases, the tier's cue (Exclusive, never
  tradable) and the chat tag. ECONOMY.md section 4.8.
- **Rank and money show** in the top left rank HUD (badge, name, XP bar), over every head
  (badge then username), under each portrait in the match bar, and as Rank and Money columns
  in Roblox's player list (designer, 2026-09-27).

**Open**
- **Bots:** whether the bot follows the current or the peak rank; which bot an Unranked player
  meets; which bot fills a seat in a 2v2 or 3v3; whether the table's difficulty changes the
  bot; the bots' names and looks.

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
  where paid random items are restricted cannot buy cases with money (free cases still open;
  the Limited shelf, a known cue at a fixed price, stays; ECONOMY.md section 13).
- **First release collectibles are cue skins only (decided 2026-09-23).** There are no table
  skins at release: every table uses the standard model. Table skins are parked in
  section 18 for after release.
- **Cases** (designer, 2026-09-27): four permanent cases bought with money (Standard,
  Rare, Epic, Legendary; each guarantees one rarity below its name, never a guaranteed
  legendary), and **the winner of every real match gets a free Standard Case** (every win for
  a new player's first 50 wins, then the first 10 wins a day and every 2nd win after; solo
  never). Odds and prices: [ECONOMY.md](ECONOMY.md) section 7. Goal at release: 30 cues.
- **Rarities** (designer, 2026-09-27): **Common, Uncommon, Rare, Epic, Legendary, Mythic,
  Secret**, from cases and the shop. Two groups sit outside that ladder and never come from
  cases: **Unique** (numbered limited copies: Founder's, Beta) and **Exclusive** (the VIP Cue,
  the Starter Cue, the rank cues Bronze Cue to Reyes Cue, later season cues). "Ultra" is
  dropped; VIP is an Exclusive cue, not a rarity. Colours in `docs/UI_STYLE.md`. Rarer cues
  have special trail and pocket VFX.
- **Duplicates can be sold back** for a little money (designer, 2026-09-27; no trade-up).
- **No direct buying of case cues** (designer, 2026-09-27; it replaced a rotating "today's
  deals" shop the same day): Common to Secret cues come only from cases and trading. A
  **Limited shelf** sells exclusive, numbered Unique cues (never in cases) for a set time,
  sometimes copy-capped, then never again, so they become trade-only. Every cue shows how many
  copies exist. Deals are only on cases (bulk opening, occasional genuine sales, timed
  special event cases with their own cues), never a guaranteed case cue. ECONOMY.md section 9.
- **A cue carries its own effects.** Every cue defines the cue ball's TRAIL and the burst
  when a ball is pocketed, so the cue you equip changes how the table looks while you play,
  not just what the stick looks like. The default cue and every common one use the same
  minimalist trail: a thin white translucent wisp, like wind off the ball. Rarer cues
  replace it with their own trail and their own pocket effect, and that pairing is the main
  reason to want one. Effects are catalog data (a named style), never code per cue.
- **Limited seasonal boxes** that leave and may or may not return. Season 0 has one, for cues.
- **The Limited shelf** holds the high-priced, quantity-limited items that sell out and become
  limited forever. At release: the Founder's Cue (1,499 R$, 50 copies) and the Beta Cue
  ($40,000, 1,000 copies, first 30 days) *(tune)*. All economy screens live under one menu.
- **Ability gacha** (the old plan for ults; how ults are earned is open, section 9): spins cost Robux (packs of 1, 5, 10,
  50) and there is one free spin per day. You keep every ability you roll; duplicates give spin
  credit that only buys more spins.
- **VIP** (one-time pass, 599 R$ *(tune)*): 2x money, +50% rank XP, the VIP Cue, a [VIP]
  chat tag before the rank tag ("[VIP] [GOLD] Name"; the name in chat keeps Roblox's colour)
  and a rainbow name over the head whose colours drift slowly (designer, 2026-09-28). Never
  better odds, never cases. A **welcome offer** at 50% off for 24 hours from the
  first join, plus one 24-hour comeback window 7 days later (designer, 2026-09-27; Roblox's
  rules call short pressure windows unfair, so not 15 minutes). ECONOMY.md section 11.
- **Starter Pack:** the Starter Cue and $3,000 for 79 R$, in the first 7 days *(tune)*, with
  no case inside.
- **Other Robux products** at launch: money packs 49 to 4,999 R$, Money Party (a server-wide
  money boost) and Fast Open; later a Cue Pass, gifts, emotes and more. Never anything that
  helps win, protects rank or changes odds. ECONOMY.md section 11.
- **Items:** one catalog for cues and abilities (stable id, type, rarity, model, effect); the
  type field leaves room for table skins later. A cue is saved as a count per catalog id
  (2026-09-28, ECONOMY.md section 18: small saves, a duplicate is a count above 1); numbered
  Unique cues keep their copy number (#412). Abilities are owned flags. **Case cues and
  Unique cues can be traded; Exclusive cues never (VIP, Starter, rank and season cues;
  designer, 2026-09-28). Abilities are account-bound. Money is never traded.**
  Trading is in the first release (designer, 2026-09-26; it was planned for after).
- **Index** (designer, 2026-09-26): a collection screen of the game's cues (what it shows:
  the 2026-09-28 line below).
- **Cue models:** every cue is its own small mesh plus a named effect style. Hundreds are
  expected, added as data rows plus assets.
- **Shop, inventory, the index, trading, save data and the first-time flow exist before the
  game is public.**
- **Money per ball** (built 2026-09-27, kept by the economy plan *(tune)*): $10 for every ball that counts
  for the shooter (their group, any ball on a legal pot while the table is open, the break's
  balls, the 8 when it wins), nothing for the other side's balls or on a foul shot. A nice shot
  pays extra on top: bank or kick +$15, combo or carom +$20. Match bonus: win +$50, loss +$15
  (money even when you lose), against PC half; the leaver gets nothing. Solo pays 30% ($3 a
  ball) until $300 in a UTC day, then $1 a ball. Difficulty multiplies it (every table is
  Classic today). Each pot flies a "+$10" from the pocket into your total, bottom left. The
  rest of the money rules (PC and short-match limits, team pay, the win streak, anti-farm
  rules, boosts) are in ECONOMY.md section 3.
- **Trading is open from the start** (no level gate; designer, 2026-09-27); Exclusive cues
  never trade (2026-09-28); players Roblox bars from trading paid items can't trade (ECONOMY.md section 12).

- **The Index** (designer, 2026-09-28): every cue in the catalog by rarity; a cue never owned
  is a "?" card; a cue counts once ever owned (selling keeps it). Tapping a card shows it on
  the side: its name (even before it is found) and the cue turning in 3D, a black silhouette
  until found, its real look after. Completing a rarity row pays once (Commons $1,000,
  Uncommons $2,500, Rares $7,500, Epics $25,000, each with a title; Legendary, Mythic and
  Secret a title only). ECONOMY.md section 18.
- **Finder's money** (designer, 2026-09-28): the first time a player gets a cue it pays extra
  money by rarity, once per cue ever (Common $50 up to Secret $50,000; Exclusive $500, Unique
  $1,000; *(tune)*). ECONOMY.md section 18.
- **The menus** (designer, 2026-09-28): four buttons in one column on the left, Shop
  (Cases, Limited, Money, VIP), Inventory (Cues, Cases, Index), Rewards (Daily, Playtime,
  Codes) and Trade (later). Cases open on a spinning reel; Fast Open opens ten at once without
  it. Promo codes give only money or free cases.

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
  sounds and the money, and (once their bar fills) try their starter ult. The PC blunders and pockets the
  8 so they win early. Normal rules stand: if they lose, the same throwing PC repeats until the
  first win.
- **Stronger ball highlights for learning (2026-09-23):** during the first playthrough and
  tutorial, turn on `Config.Multiplayer.Style.StrongBallHighlights`. The player's balls get a
  vivid solid green outline, and the other group is washed grey, so "these are yours" is
  unmissable. Normal play keeps the subtle outline with nothing greyed (the designer's choice).
- **Longer guideline lines for learning (2026-09-23):** the tutorial and first playthrough use
  the longer object/cue lines (`Config.Guideline.TutorialStubLengthInches`, 16 in). Normal play
  uses the shorter `StubLengthInches` (8 in) to keep aiming a challenge.
- **First win:** a free **Rare Case**, rolled by the server when the match settles and opened
  on the reel inside the post-match screen with an Equip button, plus the first-win and Rookie
  XP boosts (built 2026-09-28; ECONOMY.md sections 7.1 and 18).
- Unranked to Bronze after one game. The first opponent shows a much higher rank so the win
  feels earned. PC is labelled "PC" everywhere else; disguised PCs never appear on
  leaderboards and are stored as PC in match records.
- **Daily 7-day streak:** every day's reward is meaningful: $250, 2 Standard Cases, $500, a
  Rare Case, $1,000, 2 Rare Cases, an Epic Case, and a Legendary Case on day 28 of four full
  weeks (the streak then starts week 1 again). Playtime gifts at 10, 30 and 60 minutes a day.
  Numbers: ECONOMY.md section 10 (built 2026-09-28, in the Rewards menu).
- **Reminders:** Roblox cannot put text inside its own leave menu, but the game knows when the
  menu opens (`GuiService.MenuOpened`) and when the window loses focus. Both trigger a subtle
  in-game reminder ("Come back tomorrow for your free rare box"). The same reminder sits on
  the post-match screen. Built 2026-09-28: the line names tomorrow's real reward, or says
  today's is ready while it is unclaimed.
- A funnel is tracked with Roblox's built-in analytics: joined, reached a table, first shot,
  first pocket, used ult, won, opened box, equipped, second match.

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

- Private friend-locked tables. Party up with friends.
- Replay or "clip that" feature. Cinematic replay camera.
- Trading UI polish, item showcases, serial plaques.
- Seasons with themed sets beyond Season 0.
- More ults beyond the planned 13 (section 9). New ideas go here. Sabotage ideas (fog, shaky
  aim, shrinking the opponent's guideline) are out: ults help the user.
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
- The rest of the ult list, its rules and how ults are earned (section 9).
- Pro lobby look (section 10).
- Whether a table can turn ults off (sections 6 and 9).
- A pro-lobby teaser door at release (section 10).
- The bots' details (section 11).
