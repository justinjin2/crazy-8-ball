# Multiplayer specification

Agreed with the designer on 2026-09-22; implementation authorized by **begin**.
This specification supersedes conflicting GDD/roadmap details for this update only.
The original 18-section request remains the quality and acceptance requirement.
Revised the same day after the designer's first real playtest: home view camera,
top-down only for the 8-ball call, 3D cue-ball placement without a lock button, the
bonus and group reveal at the moment the ball drops, and a red X on pocketed balls.

## Scope and preservation

Three dedicated tables on the existing baseplate: 1v1, 2v2, 3v3; a player alone at
any of them may instead play it solo (see Solo, added 2026-09-23). Since 2026-09-25 every
table seats any of the three from one queue box (see Queue and teams). One configurable
system, independent balls, players, clocks, camera state, sound and results. Preserve
the imported black/blue table, existing deterministic physics, spin, orbit aiming,
power cue, audio and visual identity. Stay on the baseplate. No bots, bot
countdown, abilities, difficulty settings, progression, saved wins, money, ratings,
rewards, matchmaking or rematch screen. Results are match-only. PC mouse/keyboard,
portrait/landscape touch and gamepad are in scope; optional precision controls give
button alternatives to dragging. All tuning belongs in Config and all copy in Strings.

## Queue and teams

Changed 2026-09-26 (designer): every table plays one mode again, with one rectangular pad.

- Of the sixteen tables, ten are 1v1, four 2v2 and two 3v3 (`Config.Hub.Tables` teamSize).
  Each has one rectangular pad in front of it, lying along the long side toward the entrance
  (`Queue.PadSide`, `Queue.PadSizeStuds`; designer, 2026-09-26), holding both teams (2, 4
  or 6); the mode is written big on it with STEP IN or the count. Outlines pulse out of it and an
  arrow bobs over it while it has room; its rim is blue, green once somebody is on, gold
  when full or playing. A floating sign (mode, host, count, abilities, difficulty) shows
  only when you walk right up to its table.
- Standing on the pad joins at once (the server polls at 10 Hz with no dwell, and the
  client shows the menu the same frame). Leaving the pad releases the seat after a short
  grace. First on hosts; if they leave, the next to arrive hosts and the settings stay.
  Reject duplicate and cross-table joins, and anybody once the pad is full.
- Everyone on the pad sees the queue menu; only the host can use it: difficulty
  (Classic default, Difficult, Challenger), abilities on/off (a placeholder, on by
  default), Start. Settings reset when the pad empties and after every game.
- Start needs the pad full. Teams go by arrival: first on (the host) team A, the next team
  B, alternately. Alone on a 1v1 table the host gets Play solo and Play against PC (a
  placeholder that does nothing until bots exist); the team tables have no solo.
- No countdown: Start goes straight to the coin flip. No duplicate starts.
- Host team is heads. Server chooses coin result once; show the same 2–3 second
  animation, heads/tails ownership and breaker to all participants as a HUD overlay;
  everyone keeps their own camera until the breaker's turn starts in the home view.
- First queued member of the winning team breaks. Teammates rotate after EVERY shot,
  including scoring shots; team keeps possession only on a legal own-ball pocket.
  Rotation is independent per team and skips departed players.

## Rules

- Table stays open after the break. First legally pocketed object ball after the break
  assigns groups. Mixed pockets use chronological order; deterministic event order
  breaks exact ties. Fouls never assign. All pocketed object balls remain down on fouls.
- Open table permits either group first, never the 8. After assignment hit your group
  first, or the 8 only if your group was cleared BEFORE the shot.
- Wrong/no first contact or a scratch is a foul. Neither a pocket nor a rail after first
  contact is a foul in RANKED only; casual/public tables (all of them for now) skip that
  rule (Config.Multiplayer.RailAfterContact, 2026-09-23). A foul: opponent gets ball-in-hand anywhere. Resolve motion before changing turns.
- Break cue ball moves laterally on x=-25 inches (head string on 100-inch table).
  Show dotted legal range; enforce bounds and overlap checks. Fifteen seconds placement,
  then 20 seconds aim; early shooting is allowed.
- Legal break: any ball may be hit first (changed 2026-09-23; the aim guide never marks a
  break target invalid), then an object ball pocketed OR four DISTINCT object balls
  reaching rails. Illegal break/scratch
  gives opponent ball-in-hand without rerack. Legal break pocket keeps team possession.
- Eight on break is respotted. Otherwise legal eight-on-break keeps team possession;
  a simultaneous foul overrides retention. Teammate rotation still applies.
- Eight pocketed early, in the wrong pocket, or on any foul loses. Scratch while
  eligible but WITHOUT pocketing eight is ordinary foul. Last group ball and eight
  on the same shot loses. A legal called eight wins.

## Solo (added 2026-09-23)

- A host alone on a 1v1 table's pad (Waiting, one seat, theirs) presses Start and picks
  **Play solo**. It starts at once: no CoinFlip, and nobody can join until the result.
- Normal break and legal-break rule; the 8 on the break is re-spotted. Every foul
  (illegal break, scratch, wrong first contact, no rail) gives the SAME player ball in
  hand and play continues. The table is open after the break; the first legally pocketed
  object ball picks the FIRST group. Clear all of it, then all of the other group, then
  call the 8 as usual (top-down, final).
- The 8 early, on a foul or in the wrong pocket: YOU LOSE. A legal called 8 after all
  fourteen: YOU WIN. Leave → Yes ends the game at once with no winner (MATCH ENDED).
  Then the normal Result and table reset.
- No clock: PocketChoice, Placement and Aiming have no deadline; the Foul notice still
  passes on its own. YOUR TURN plays only at the break.
- HUD: one panel and a 15-ball row in playing order (first group, other group, the 8),
  wrapping to 8 + 7 on narrow screens, with the open-table row until the first group is
  known; no clock. Once groups exist every group ball the player pockets plays their
  bonus; the winning 8 as in matches.

## Phase/timing order

Waiting → (host's Start) CoinFlip → Intro → optional PocketChoice → optional Placement
→ Aiming → Resolving → optional Foul → next turn or Result → reset. Solo goes straight
from Waiting to Intro.

- Intro: YOUR TURN and sound for newly designated local shooter, two seconds before
  shooting clock. Others see shooter identity. Early shot allowed unless an eight
  call is still required. Continuing 1v1 shooter skips repeated intro/sound.
- Placement: 15 seconds with valid server-chosen fallback. The shooter drags the cue
  ball in the normal 3D camera (from any zoom), or uses camera-relative buttons, and
  may aim and shoot at any time. There is no lock/confirm button. The ball follows the
  finger immediately (client prediction) and slides around balls and cushions rather
  than going somewhere illegal. At the deadline it stays where it is and the
  20-second aim follows. Dragging is also allowed in the Intro when no call is owed.
- Pocket choice: every eight attempt, six blue pulsing targets, 10 seconds, nearest
  pocket to EIGHT on timeout (stable pocket-id tie break). Confirm early, then aim.
  The call is final once made (changed 2026-09-23). When both
  are needed the call comes FIRST (top-down), then placement in the home view; no
  shooting before a required call exists.
- Aiming: 20 seconds, whole seconds above five; red tenths at/below five, stable width.
  Accepted shot immediately stops clock. No timeout while rolling.
- Shooting timeout is foul; two successive team shooting timeouts with no accepted
  shot by that team in between automatically forfeit. Setup auto-completion is not
  a shooting timeout. Accepted shot clears that team's timeout streak.
- Resolve after balls stop INCLUDING pocket falls; add one second if any pocket.
  Unique shot/result identifiers prevent repeated resolution/audio/announcements.
- Fouling player hears foul sound; everyone sees who fouled. Central message priority
  must be phase-driven, with result/foul/setup above ordinary turn status.
- Turn sound 120722072794939; foul 128802141795458. Coin candidate 7022812395 was
  found through Creator Store and successfully loaded in the intended experience.
  Keep configurable and fail gracefully if unavailable. Listening remains a QA task.

## HUD and controls

Use supplied screenshot for layout, not its table style or unrelated Roblox UI.
Two dark horizontal team panels, square avatar portraits at outer sides, shared stable
ball rows, central fixed timer/status area, accessible leave button. Local team stays
left. Show all six players compactly in 3v3, identifying labels, clear active shooter,
smooth decreasing square perimeter clock plus separate active marker. Avatar fallback
must be neutral and visible. Open-table label until the assigning ball drops: on that
shot both teams' numbered rows appear the instant the ball falls in the replay and never
revert. Numbered solids/stripes then eight after assignment; a pocketed ball turns grey
with a red X across the whole ball the moment it drops, stable slots and one restrained
pop per ball; distinguish locked/eligible eight. Highlight local remaining balls
subtly in world. Safe insets, constraints, long-name handling, readable small screens.
Shared reusable components/styles/motion; cancellable animations, no obsolete overlays.

Only designated shooter gets aim/place/call/shoot controls and private guides. Retain
legal ghost/trajectory guides; wrong first target crosses out ghost and explains invalid
target without showing a normal scoring solution. No private aim guides for others.

## Camera, movement and audio

- The **home view** (Config.Camera.View.ZoomDefault, the pre-multiplayer framing:
  behind the cue ball, halfway between the close cue view and the whole table) starts
  every turn. During a shot the camera holds, pulls out to the whole table (clear of the
  HUD), then eases back to the home view. Break placement and ball in hand happen in
  this 3D view; the camera holds still while the ball is dragged. A turn that opens
  with the ball in hand (the break, a foul) starts two wheel notches wider than the home
  view (View.BallInHandZoomNotches).
- An invisible, camera-transparent wall (Multiplayer.Barrier) surrounds each table so
  nobody can touch it or jump onto it; a released shooter is stepped outside it.
- The ONLY top-down view is the shooter's 8-ball pocket call (PocketChoice, and the Intro
  just before it while a call is owed). After the call or its timeout: the home view.
  Smooth ~0.55-second transition, table framed below the HUD, all pockets reachable
  across aspect ratios. Incoming non-break aim suggests closest own remaining ball
  (eight when eligible); manual aim remains.
- Outgoing shooter watches through settling. Others have ordinary Roblox camera and
  movement within a boundary just outside their match table. All keep match HUD.
  Prevent collisions with shooter/balls and prevent shooter shift-lock turning.
- Save/restore changed camera, movement, collision and animation properties. Clean
  handling on seat changes, reset, disconnect, result and return to roaming.
- Physical pocket sounds retained. Bonus is PRIVATE to all ball-owning teammates,
  even on opponent shots/fouls, and plays in the same frame as the pocket drop at the
  ball, climbing the streak ladder. Ownership comes from the server's judgement at shot
  acceptance, so on the assigning shot the first ball and every later group ball get
  their owners' bonus at the drop. Break and other open-table shots stay physical-only
  (the break never assigns). Cue scratch/illegal eight has no bonus; winning eight gives
  winner bonus. No money awarded. Bound overlapping audio.

## Surrender, disconnect, death and reset

- L or leave button opens confirmation, No cancels, modal blocks gameplay click-through.
  Timers continue. In team modes explain that Yes requests team surrender, not instant
  individual leave. Unanimous connected teammates within 10 seconds; No/expiry cancels,
  30-second request cooldown. 1v1 Yes forfeits immediately.
- Actual disconnect/leaving Roblox: continue shorthanded, skip missing slots, no
  replacements/bots. Empty team forfeits. Departing current shooter fouls if shot
  not accepted; accepted shot resolves normally. If both teams empty, reset cleanly.
- Reset/death retains seat, respawns inside match area, deadlines continue. Current
  unplayed turn fouls; accepted shot resolves normally. Avoid double death/removal fouls.
- Result: YOU WIN / YOU LOSE for connected participants including surrender; brief
  2–3-second treatment. Release cameras/controls/boundaries, cleanup timers/connections,
  fresh rack and fresh queue; require leaving/reentering pads to prevent accidental rejoin.

## Engineering and acceptance

Scripts edited only in src, Rojo owns sync. Pure physics/rules, numeric deterministic
state and explicit clock inputs. Server owns joins, teams, coin, turns, placement,
calls, acceptance, clocks, rules and results. Validate finite/ranged inputs, identity,
match/turn version, proximity, phase and rate. One player's messages cannot affect
another table. Include full late-join snapshots and stale/duplicate replay protection.
Never make progress depend on a client acknowledging animation completion.

1. Inspect/interview/preflight (done; limitations below).
2. Shared queues and independent state.
3. Complete rules/turn flow for all three modes.
4. HUD/camera/control/audio/VFX integration.
5. Automated and Studio tests, fixes, responsive/visual polish.

Run lint/tests, verify Rojo, Studio console and screenshots at each verified step;
commit/push regularly. Update progress, STATUS, ROADMAP and dated decisions. Do not
tick unrelated milestones whose acceptance is unmet. Maintain actual saved source;
ask once at milestone handoff to save place/8ball.rbxl and publish. No asset import
is currently needed. Do not claim completion with outstanding required features.

Test complete games each mode, concurrent tables, join/leave/countdown cancel, host
transfer, rotations, every foul/timeout, placement/call, eight outcomes, votes,
disconnect/reset, duplicate/stale/cross-table attacks and table reuse. Inspect screenshots
of 1v1/2v2/3v3, six portraits, long names/fallbacks, low clock, foul, placement, pocket
choice, confirmation and results. Observe animation separately. Distinguish pure tests,
scripted Studio integration, real clients and hands-on phone/controller acceptance.

## Preflight evidence and limitations

Correct project /Users/justinjin/Desktop/8ball; place 107430170196919, universe
10767330648. Baseline commit 57f2693; clean tree, 132 tests, lint clean. All 35 source
files matched Edit Studio checksums; Rojo connected, git push dry-run successful.
Table and ball assets present. Supplied sounds and coin candidate preload successfully.
Native screenshot worked; native toolbar interaction intermittently noWindowsAvailable.
User launched six local test clients: server log records Player -1 through -6 and six
connected players, correct place/universe. MCP lists ONLY original Edit instance;
separate server/client control is NOT yet verified. Startup logs contain existing
asset/font/avatar warnings, no project Lua stack traces. Saving commands available;
latest local place predates this task. Physical device and six-client gameplay QA pending.

## Implementation contract

TableState snapshots: id, epoch, revision, teamSize, phase, phaseStartedAt, deadline,
seats[{userId,name,displayName,side,team?,slot?,host,joinedAt,connected}] (team and slot
from Start on), hostId, settings{difficulty,abilities}, activeTeam,
shooter, turnId, breakShot, ballInHand, groups (team-indexed solids/stripes or nil),
calledPocket, coin{headsTeam,winnerTeam,breaker}, foul{by,team,reason},
result{winner,reason}, vote{team,deadline,yes}, balls (x,y,z,pocketed per ball ID+1),
shotSeq, rackSeed, rackPositions, optional shot (complete replay payload), optional
solo{team,first} (first = the group played first, nil until picked; in solo, groups hold
the group being played for the solo team and the other group for the empty team).
Phases use exactly the title-case names above. Snapshot revisions monotonically increase.
MatchAction client requests: {tableId,epoch,turnId,kind,x?,y?,seq?,pocket?,yes?}; kinds
Place, Pocket, Surrender, Vote, LeaveQueue, Start, StartSolo, SetDifficulty {value},
SetAbilities {value} (no ConfirmPlacement). Start, StartSolo and the two settings are
valid only in Waiting from the host; StartSolo only when the host is alone. Place carries a
per-turn seq; a Place or stream move with seq <= the last accepted one is ignored.
SnapshotRequest requests initial/full state after client listeners exist. Gameplay action
requests require current epoch/turnId; shot payload additionally supports optional
cueX/cueY for atomic early shot (after the window closes, only the locked spot is accepted).
AimUpdate (unreliable) is (tableId, angle, epoch, turnId, seq?, x?, y?): x/y stream the
ball in hand without a snapshot broadcast. AimBroadcast is a flat stride-5 list
[tableId, shooter, angle, cueX, cueY] at Config.Aim.BroadcastsPerSecond. Rate limits are
per channel (action, place, shot, aim, snapshot) so dragging can never starve a shot.
ShotResult includes epoch, seq, turnId, shooter, startedAt, seed, start (packed balls),
duration, final (packed balls), checksum, overrides and, on the assigning shot only,
assign {groups, ball, index}. Snapshot groups change only at resolution. MatchFeedback
{tableId, epoch, id, seq, index, ball, team, at} goes only to the owning team at shot
acceptance, before ShotResult. Client owns presentation only.
