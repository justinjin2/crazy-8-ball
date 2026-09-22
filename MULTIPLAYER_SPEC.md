# Multiplayer specification

Agreed with the designer on 2026-09-22; implementation authorized by **begin**.
This specification supersedes conflicting GDD/roadmap details for this update only.
The original 18-section request remains the quality and acceptance requirement.

## Scope and preservation

Three dedicated tables on the existing baseplate: 1v1, 2v2, 3v3. One configurable
system, independent balls, players, clocks, camera state, sound and results. Preserve
the imported black/blue table, existing deterministic physics, spin, orbit aiming,
power cue, audio and visual identity. Keep the lounge stored/disabled. No bots, bot
countdown, abilities, difficulty settings, progression, saved wins, money, ratings,
rewards, matchmaking or rematch screen. Results are match-only. PC mouse/keyboard,
portrait/landscape touch and gamepad are in scope; optional precision controls give
button alternatives to dragging. All tuning belongs in Config and all copy in Strings.

## Queue and teams

- Two labeled team areas with one square slot per required player. Players choose a
  team by standing in a slot. 1v1 has two pads; 2v2 four; 3v3 six.
- Empty white, occupied green, readable mode/occupancy/status text; soft gradients,
  glowing edges and restrained pulse. Smooth occupancy transitions, bounded VFX.
- Leaving the queue area releases the slot. First joiner hosts; if they leave,
  longest-waiting remaining player hosts. Reject duplicate/cross-table joins.
- Floating host panel shows mode, occupancy, waiting/countdown/in-progress status.
  No fake functional settings. Five-second synchronized countdown only when full;
  departure cancels it, and refilling starts a fresh countdown. No duplicate starts.
- Host team is heads. Server chooses coin result once; show the same 2–3 second
  animation, heads/tails ownership and breaker to all participants in top-down view.
- First queued member of the winning team breaks. Teammates rotate after EVERY shot,
  including scoring shots; team keeps possession only on a legal own-ball pocket.
  Rotation is independent per team and skips departed players.

## Rules

- Table stays open after the break. First legally pocketed object ball after the break
  assigns groups. Mixed pockets use chronological order; deterministic event order
  breaks exact ties. Fouls never assign. All pocketed object balls remain down on fouls.
- Open table permits either group first, never the 8. After assignment hit your group
  first, or the 8 only if your group was cleared BEFORE the shot.
- Wrong/no first contact, scratch, or neither a pocket nor a rail after first contact
  is a foul: opponent gets ball-in-hand anywhere. Resolve motion before changing turns.
- Break cue ball moves laterally on x=-25 inches (head string on 100-inch table).
  Show dotted legal range; enforce bounds and overlap checks. Ten seconds placement,
  then 15 seconds aim; early shooting is allowed.
- Legal break: apex ball first AND object ball pocketed OR four DISTINCT object balls
  reaching rails (the AND applies to either spread condition). Illegal break/scratch
  gives opponent ball-in-hand without rerack. Legal break pocket keeps team possession.
- Eight on break is respotted. Otherwise legal eight-on-break keeps team possession;
  a simultaneous foul overrides retention. Teammate rotation still applies.
- Eight pocketed early, in the wrong pocket, or on any foul loses. Scratch while
  eligible but WITHOUT pocketing eight is ordinary foul. Last group ball and eight
  on the same shot loses. A legal called eight wins.

## Phase/timing order

Waiting → Countdown → CoinFlip → Intro → optional Placement → optional PocketChoice
→ Aiming → Resolving → optional Foul → next turn or Result → reset.

- Intro: YOUR TURN and sound for newly designated local shooter, two seconds before
  shooting clock. Others see shooter identity. Early shot allowed unless an eight
  call is still required. Continuing 1v1 shooter skips repeated intro/sound.
- Placement: 10 seconds with valid server-chosen fallback; dragging and buttons,
  legal/invalid feedback. Early confirmation or early shot ends placement. Timeout
  locks last valid position, then pocket choice if needed, otherwise 15-second aim.
- Pocket choice: every eight attempt, six blue pulsing targets, 10 seconds, nearest
  pocket to EIGHT on timeout (stable pocket-id tie break). Confirm early, then aim.
  Choice may change while aiming without restarting the shooting clock. Placement
  precedes choice if both needed; no shooting before a required call exists.
- Aiming: 15 seconds, whole seconds above five; red tenths at/below five, stable width.
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
must be neutral and visible. Open-table label before assignment; numbered solids/stripes
then eight after assignment; pocketed icons grey with X, stable slots and restrained
update emphasis; distinguish locked/eligible eight. Highlight local remaining balls
subtly in world. Safe insets, constraints, long-name handling, readable small screens.
Shared reusable components/styles/motion; cancellable animations, no obsolete overlays.

Only designated shooter gets aim/place/call/shoot controls and private guides. Retain
legal ghost/trajectory guides; wrong first target crosses out ghost and explains invalid
target without showing a normal scoring solution. No private aim guides for others.

## Camera, movement and audio

- Orbit/down-the-cue remains normal aiming. Top-down for shared coin sequence, break
  placement, ball-in-hand and pocket choice. Smooth ~0.55-second transition with table
  framed below HUD, all pockets reachable across aspect ratios. Incoming non-break
  aim suggests closest own remaining ball (eight when eligible); manual aim remains.
- Outgoing shooter watches through settling. Others have ordinary Roblox camera and
  movement within a boundary just outside their match table. All keep match HUD.
  Prevent collisions with shooter/balls and prevent shooter shift-lock turning.
- Save/restore changed camera, movement, collision and animation properties. Clean
  handling on seat changes, reset, disconnect, result and return to roaming.
- Physical pocket sounds retained. Bonus is PRIVATE to all ball-owning teammates,
  even on opponent shots/fouls. Open-table shots physical-only; on assignment shot,
  dispatch correct bonuses after ownership resolves. Cue scratch/illegal eight has
  no bonus; winning eight gives winner bonus. No money awarded. Bound overlapping audio.

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
Table/ball/lounge assets present. Supplied sounds and coin candidate preload successfully.
Native screenshot worked; native toolbar interaction intermittently noWindowsAvailable.
User launched six local test clients: server log records Player -1 through -6 and six
connected players, correct place/universe. MCP lists ONLY original Edit instance;
separate server/client control is NOT yet verified. Startup logs contain existing
asset/font/avatar warnings, no project Lua stack traces. Saving commands available;
latest local place predates this task. Physical device and six-client gameplay QA pending.

## Implementation contract

TableState snapshots: id, epoch, revision, teamSize, phase, phaseStartedAt, deadline,
seats[{userId,name,displayName,team,slot,host,joinedAt,connected}], hostId, activeTeam,
shooter, turnId, breakShot, ballInHand, groups (team-indexed solids/stripes or nil),
calledPocket, coin{headsTeam,winnerTeam,breaker}, foul{by,team,reason},
result{winner,reason}, vote{team,deadline,yes}, balls (x,y,z,pocketed per ball ID+1),
shotSeq, rackSeed, rackPositions, optional shot (complete replay payload).
Phases use exactly the title-case names above. Snapshot revisions monotonically increase.
MatchAction client requests: {tableId,epoch,turnId,kind,x?,y?,pocket?,yes?}; kinds
Place, ConfirmPlacement, Pocket, Surrender, Vote, LeaveQueue. SnapshotRequest requests
initial/full state after client listeners exist. Gameplay action requests require current
epoch/turnId; shot payload additionally supports optional cueX/cueY for atomic early shot.
ShotResult includes epoch, seq, turnId, shooter, startedAt, seed, start (packed balls),
duration, final (packed balls), checksum and overrides. MatchFeedback targets bonus/audio
events with unique IDs. Client owns presentation only.
