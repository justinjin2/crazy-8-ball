# Architecture

Technical design for Crazy 8 Ball. Read this before touching `src/`. Plain words first, detail
after. Design intent is in GDD.md; this file says how it is built.

## 1. Non-negotiables

- **Our physics, not Roblox physics.** Balls are simulated by `src/shared/Physics`: pure Luau,
  no Instances, no Roblox types (`Vector3`, `CFrame`, `task`, `game`), fixed timestep, units are
  inches and seconds. It runs in Lune (`tools/test.sh`) and on the server unchanged. The 3D
  ball models only follow what the simulation says.
- **A shot is inputs.** `Simulation.run(state, shot) -> ShotResult`. Rendering, audio, effects,
  rules and abilities consume the result. `shot = {angle, power, spin = {x, y}, elevation?, ability?}`.
  Elevation is 4-60 degrees in whole steps (ShotInput.roundElevation); ability ids require
  server authorization.
- **Determinism.** No `os.clock`, no `math.random`, no hash-order iteration inside Physics or
  Rules. Same inputs give the same result on every device.
- **Never trust the client.** The server owns match state, validates every shot and ability,
  and decides what happened.
- **One module per system.** No cross-cutting globals. Every tunable number lives in
  `src/shared/Config.luau` with a comment.
- **Every feature works on phone, PC and gamepad** and is checked on all three.

## 2. Scale and coordinates

- `Config.Table.StudsPerInch = 0.16`. A 9 ft table is 100 x 50 in of playing surface, about
  18.2 x 10.2 studs with rails. Physics ball radius is 1.125 in (regulation); RenderScale 1.08 enlarges only the mesh
  and visual placement. Collision clearance and physics use the physical radius.
- Physics x runs along the table length (head rail negative, foot rail positive), physics y
  across the width. World: physics x maps to world X, physics y to world -Z, Y is up. Each table
  has its own origin and yaw; `TableBuilder.toWorld` and `toTable` convert per table.

## 3. Physics (what exists)

Event-driven fixed step (1/240 s) with exact time of impact for ball-ball, ball-segment and
ball-point contacts (no tunnelling at any power). Sliding-to-rolling friction in closed form,
rolling resistance, radius-independent side-spin decay. Ball-ball contacts use a tabulated
speed-dependent friction impulse for throw and spin transfer, retaining full contact torque
while translation stays on the cloth. A contact involving a ball already within
`ClusterGapInches` of a third ball (the rack, frozen balls) is instead resolved by
`Physics/Cluster` as one atomic soft phase: Hertz springs with restitution-calibrated damping
and the same contact friction, integrated at a fixed 2 us sub-step until every contact lets go,
while the rest of the table catches up through the normal event loop. A step containing one
may end up to `SoftContactMaxSeconds` late; server settle and client replay overrun
identically. Cue impact uses stick/ball mass, tip restitution and
a default 4-degree elevation. Side spin does not bend the path: with
`Config.Cue.SideSpinBendsPath` off (the designer's setting) there is no squirt and no tilted
spin axis, so the cue ball leaves along the aim and runs straight to first contact, and the
straight Classic guideline is exact for any spin; side spin (wz) acts only at contacts. Turning
the switch on restores squirt and cloth swerve for the later curved-guideline feature. Pure side spin does not delay shot completion. Cushions
use Han's tilted contact normal through the centre, full tangential friction, and tabulated
normal-speed restitution. Translation stays planar for a ball on the cloth; only tangential impulses create torque.
Six pockets use capture circles with jaw facings and a physical drop (z, vz, funnel). Corner
openings have a flat shelf scaled to ball diameter, and facings extend to their rim. Wedge guards
against zero-time hit loops. `Aim.trace` gives the guideline from the same code as the shot.
Balls can fly (jump shots, `Physics/Flight`), after Dr. Dave's TP B.10 model. `Cue.strike`
sends the stroke's downward part into the slate, which rebounds at `SlateRestitution` (0.6);
a near-level stroke gets only `FlatStrikeBounce` of that, rising to all of it at
`Cue.JumpCapDegrees`, and a raised cue's top stroke speed falls to `Cue.JumpMaxStickSpeed`
(12 mph) by the same angle. A rebound under `MinHopSpeed` is swallowed and nothing changes,
so ordinary shots are bit-identical to the planar engine. A ball in the air flies a parabola (no cloth friction), lands with slate
friction, and while any ball is airborne the event window is cut to `AirStepSeconds` and its
ball contacts use `Collision.sphereTOI` and a 3-D normal. A ball on the cloth never takes
vertical velocity (the slate holds it), so only the flyer flies and object balls stay down.
A ball in the air below the cushion top meets a cushion like a ball on the cloth and keeps
its own vertical speed (no launch). Higher, it never touches the cushion: `Simulation.goesOver`
rules it `offTable` (pocketed, no pocket, `offTable` event) once it is over a real cushion
face or jaw moving outward, or a radius past the cushion line anywhere but the hole. A ball
coming slowly down onto another's top slides off, paid for from the contact's lost energy. A low hop into a rack still breaks it by soft contact: the flyer is laid flat for the
phase and kicked up after, energy-bounded. The replay seed carries `vz`. `Aim.trace` walks
the hops for the guideline (landings, "off") with the same `goesOver`/`touchesCushion`. A
ball that flies off is drawn falling to the floor and rolling; the server holds the foul for
`Flight.floorTime` + `Effects.FlyOffRollSeconds` + `FlyOffFadeSeconds`. Rules: `OffTable` foul, `EightOffTable` loss,
object balls respotted by `CuePlacement` at the foot spot.
Tests in `tests/`: energy never increases, no overlap at rest, no ball leaves the table except by flying (jump tests), the
break scatters the rack, rail bounce mirrors, spin signs, determinism, trace matches simulation.
Per-shot cushion overrides are copied from a named material, sent with the replay seed,
and cleared on completion. Live ability requests remain disabled pending server authorization.
Rack uses a seeded integer PRNG for tiny non-overlapping offsets. TableState carries both
the seed and exact initial positions; a reset received during replay queues until completion.
The developer rerack request is Studio-only, seat-checked and resolved on the server.
Generated table parts share this geometry; the imported table mesh needs separate art updates.

## 4. Networking: server-owned tables

Each table in the hub is a `Table` instance on the server with: id, origin and yaw, host,
settings (mode, difficulty, abilities on/off), seats with teams, match state (rules state
machine, physics state, turn, clocks), spectators.

Shot flow:
1. The shooter's client sends only inputs to the server (angle, power, spin, ability id).
2. The server checks turn, seat, cooldowns and ranges, runs `Simulation.run`, applies rules,
   and stores the result.
3. The server broadcasts the inputs (plus the final positions) to every client in the server.
   Each client replays the same simulation locally, so motion is smooth with no lag. When the
   balls stop, clients snap to the server's final positions.
4. During a turn the shooter's aim angle and ball-in-hand position ride the unreliable aim
   stream (up to 15 per second, with a per-turn sequence number) so opponents and spectators
   see the cue turn and the ball glide (eased). The shooter's own ball is predicted locally
   and never snapped back by an echo; a reliable Place commits it on release. The wind-up
   (how far the power is drawn, in 1/50 steps, `AimStream`) rides along so watchers see the
   cue draw back; it is cosmetic, the shot's power comes only from ShotFired. Never the
   guideline.
5. The shooter's body (2026-09-24). While a player is the locked shooter the server anchors
   their root and places it with the same pure stance the clients use (`ShooterStance.solve`
   on `AvatarPose.measureBody`), following the aim at most 5 times a second. At shot
   acceptance it puts the root on the shot spot facing the table centre and publishes that
   CFrame as the root's `ShotSpot` attribute; when the turn passes it lets go in place. Every
   client poses the body itself (`ShooterPoser`: limbs anchored locally, forward kinematics
   and two-bone IK, one `BulkMoveTo`): the shooter's own client through `Avatar`, everyone
   else through `WatchedShooters` for the tables they render. After the stroke each client
   writes the root once, to `ShotSpot`, so the owner hands the body back exactly where the
   server holds it. A held shooter is in the `PoolShooter` collision group, which touches
   nothing, so moving it never shoves a spectator.
6. Pocket bonuses are decided at shot acceptance from the server's judgement and sent only
   to the owning team before the replay; each client plays them on the matching replay
   pocket drop. The assigning shot carries `assign`, so the HUD reveals groups at that drop.

PC opponents run on the server using the same `Simulation` to try candidate shots (skill =
aim noise and how many candidates it considers), with a per-shot compute budget so sixteen
tables of PCs stay cheap.

## 5. Module map

Shared (`src/shared`): `Config`, `Physics/` (Vec, Ball, Table, Collision, Cluster, Cue, Rack,
Aim, Simulation), `Rules/` (Rules state machine, ShotJudge; pure, to be written), `Abilities/`
(catalog and pure effect hooks into the simulation, to be written), `TableBuilder`,
`CueStickBuilder`,
`AvatarPose` (rig, measurements, IK pose), and the pure stance modules `CueShape`,
`CueClearance` (the drawn cue's visual pitch), `ShooterStance` (where the body stands,
stretches or kneels, and where both hands hold the cue), `PoseMath`, `AimStream`; `ShotInput` (validation/seed
quantization), `Strings` (HUD copy), `Catalog`
(item data rows, to be written). The hub map: `MapBuilder` (Edit-mode setup of the imported
map), `MapMotion` (the boats' paths, pure), `LightCycle` (the day/sunset cycle: server time
to a blend, the two light states mixed, the sun's path; pure), `MapLighting` (puts a light
state onto the place; `preview` in Edit mode).

Server (`src/server`): `Bootstrap` (builds the tables, publishes assets), `TableService`
(per-table state, joins, seats, match loop), `ShotService` (validation, simulation, broadcast),
`DevCommands` (the developer's `/day` and `/sunset` chat commands, checked on the server),
`BotService`, `PlayerData` (session-locked saves), `Economy`, `Ranking`, `Analytics`.

Client (`src/client`): `Main` (wiring), `Match` (replays shots), `BallRenderer`, `Input`
(mouse, touch, gamepad), `SpinSelector`, `Guideline`, `Camera`, `Avatar` (the local
shooter), `ShooterPoser` (one character's aim/stroke/idle states), `WatchedShooters` (other
shooters), `UI` (the shared ScreenGui), `Audio`, `Effects`, `Hub` (one Match per table,
seats), `MatchHUD` (the top bar, beside Roblox's own buttons when it fits, the foul popup,
the hints, dialogs, the coin and result cards), `QueueMenu` (the card everyone on a queue pad
sees: host, difficulty, abilities, Start; beside the jump button on a phone), `TableSign`
(the one sign over the table the player walks up to, drawn from the snapshots), `HudParts` (the UI kit every screen is built from: cards, pills, kit text, candy
buttons and tiles, icons, HUD balls; tokens in `Config.UI.Kit`), `UIAnim` (every UI
animation), `PadEffects` (the queue pads' rim, rings, arrow, glow, motes and join sound),
`MapAmbience` (the drifting boats), `DayCycle` (runs the day/sunset cycle from the server's
clock, no network traffic), `FirePit` (the fire pit's fire, Roblox's own, lit at sunset).

UI art: `tools/gen_ui_art.py` draws the icons and effect images as SVG from one shared style
(ink outline, drop lip, gloss) and renders them to PNG with headless Chrome into
`assets/ui/icons` and `assets/ui/art`. They are uploaded through Studio and referenced by id
from `Config.UI.Kit.Icons` and `.Art`; swapping an image is a Config change, never code.

## 6. Data model

- **Catalog:** one table of item rows for cues and abilities (table skins are post-release; the
  `type` field leaves room for them): stable string id, type,
  rarity, display name key, model or asset ids, effect parameters, limited quantity and
  serial rules. Adding an item is adding a row plus assets, never code.
- **Inventory:** every cue is a unique object (`{uid, itemId, serial?, acquiredAt,
  tradable}`); abilities are owned flags. Equipped cue and ability are ids on the profile.
- **Profile (saved):** money, rating and peak rank per season, stats (wins vs people, wins vs
  PC, losses, best win streak, match history last 20), opponents-played-today counters,
  daily streak state, first-time flow progress, flags (founder, VIP), settings (country).
- **Saves:** a session-locked, versioned save library (ProfileStore style) from the first
  saved money. Every layout change bumps a version with a migration. Robux receipts are
  processed exactly once.
- **Analytics:** Roblox built-in analytics for the funnel and economy events, server-side.

## 7. Performance budgets

- Table model: every table uses the one standard model (two looks at release; later table
  skins are retextures of it). At most 13,000 triangles over 8 MeshParts (Roblox caps each
  mesh at 20,000). About 16 to 18 texture images at 1024, shared by every look; masters are
  authored at 4096. Studio uploads render at 1024 (tested 2026-09-24, STUDIO_NOTES), which is
  also the most a low-end phone gets. The cloth is one repeating near-white tile (every 1.5
  studs, 683 px per stud) tinted per look with SurfaceAppearance.Color; the rails have their
  own wood sheet (about 400 px per stud). Automatic
  render fidelity (LOD) on all meshes, decorative parts do not cast shadows, no per-table
  shadow-casting lights, StreamingEnabled on.
- Balls: one shared sphere mesh (about 550 triangles) with per-ball textures.
- Server: about 30 players; PCs never play PCs; per-shot bot budget.
- Shooter posing: one rig build per character (event-invalidated), no per-frame allocation,
  one `BulkMoveTo` per posed body, unchanged frames skipped, far bodies posed at 15 Hz, only
  rendered tables posed. A pose costs about 0.05 ms in Studio; a stance solve about 0.2 ms
  in Lune.

## 8. Conventions

- Edit scripts as files only, synced by Rojo. Studio (through the MCP tools) is for building
  parts and lighting, inspecting, playtesting, console and screenshots. Assets that scripts
  cannot create (imported meshes, SurfaceAppearance maps, MaterialVariants) live in the place
  file, saved to `place/8ball.rbxl` and published.
- Lint: `tools/lint.sh` (StyLua, Selene, luau-lsp). Tests: `tools/test.sh` (Lune). Both green
  before every commit.
- Asset generators live in `tools/` and write into `assets/`; package delivery notes live next
  to each package (`assets/*/Readme.md`) and are read only when importing that package.

## Multiplayer match boundary (2026-09-22)

`Rules/MatchEngine` owns one plain-data state per table, with explicit phase, epoch,
revision, turn id, seats, groups, deadline, replay, vote and the host's settings
(difficulty, abilities). Each table plays one mode, `teamSize` a side (`Engine.new(id,
teamSize)`, from `Config.Hub.Tables`); its pad holds twice that. Seats get a team and slot
only when the host starts, alternately by arrival (`Engine.startState(seats, teamSize)` is the
rule the server enforces and the queue menu greys Start from: the pad must be full).
It receives time and coin outcomes as arguments, so the same lifecycle runs under Lune. `ShotJudge` consumes ordered
simulation events; `CuePlacement` validates and deterministically finds legal fallbacks.
Physics remains unchanged and instance-free.

`TableService` is the Roblox adapter for server-observed queue pads (one rectangular pad per table
in front of its long side, `Placement.queuePad`, polled at 10 Hz with no dwell), global membership, rate
limits, character constraints and snapshots. `ShotService` validates ownership/version
through the engine, simulates once and broadcasts the replay. Accepted shots stop the
shooting clock; resolution waits for motion/falls and the pocket buffer. Epoch/sequence
checks reject stale actions and duplicate replay packets. Group assignment and 8-ball
eligibility are decided from pre-shot state and server events.

`Hub` keeps one client Match per table. Snapshots include full ball state for late
listeners, placement and table reuse. `Main` derives private controls from the replicated
phase. `MatchHUD`, `MatchTargets`, `QueueMenu` and `TableSign` build from `HudParts` and share
Config styles and Strings copy; the server only keeps the queue pad's words and attributes
(`TableService`), and each client draws the table sign and the pad's rings and arrow
(`PadEffects`), and pops the queue menu the frame you step on (`Main`, predicted from the
table's snapshot until the server's seat arrives); existing Camera,
Input, Avatar, Audio, Effects and renderer modules retain their separate responsibilities.

`StudioMatchQA` creates a server-only BindableFunction in ServerStorage exclusively when
RunService:IsStudio(). It drives deterministic fixture identities, phases and snapshots
for inspection; it is not a bot or public remote. Synthetic fixtures are always reported
separately from real multi-client playtests.

## Saves, ranks and money (2026-09-27)

**Modules.**
- Pure, Lune-tested (`src/shared/Progression/`): `SaveSchema` (the save layout, its `Version`,
  migrations N to N+1, and `validate`, which repairs any bad value to a safe one and reports
  what it fixed), `Ranks` (46 divisions from one total `RankXp`; match XP, the tier floor,
  one-time rank-up rewards, the roadmap's list), `Money` (what a shot pays its shooter, the
  match bonus, the solo daily cap), `Format` (commas, "$1,250", "$12.5M"). `Rules/NiceShot`
  also names the kind of nice shot (bank, kick, combo, carom) for the bonus.
- Server: `Vendor/ProfileStore` (loleris, never edited, pinned in `Vendor/README.md`),
  `PlayerData` (the only module that touches it: session per player, kick on failure,
  validated named mutations, replication), `Economy` (pays each accepted shot), `Ranking`
  (settles each finished match once, charges leavers), `DevCommands` (the rank and money chat
  commands).
- Client: `Progression` (builds and routes everything below), `RankBadge` (one badge with its
  shine on a shared clock, used by every screen), `RankHud` (top left), `MoneyHud` (bottom
  left), `CashFlyer` (the "+$10" chips), `Nameplates`, `ResultScreen`, `NewRankPopup`,
  `Roadmap`, `UISound`, `ChatTags` (the [TIER] tag before names in chat, from each speaker's
  RankTier attribute); MatchHUD shows a small badge under each portrait.

**Data flow.**
1. *Save.* On join `PlayerData` opens the player's session (`Player_<UserId>` in
   `Config.Save.StoreName`, or the Studio store), adds the user id, then migrates, reconciles
   and validates a copy and takes it only if every step worked; otherwise it kicks with
   `Strings.Save.LoadFailed`. ProfileStore autosaves, saves on leave and on shutdown, and its
   session lock stops two servers from writing one save. No seat is given before the save
   loads.
2. *Grant.* Nothing a client sends carries an amount. `ShotService` accepts a shot, then
   `Economy.onShot` reads the server's own judgement (before the shot resolves, so the groups
   are still the pre-shot ones), prices it with `Money.shotPay`, and calls
   `PlayerData.addMoney` once (the difficulty multiplier stays 1 while
   `Config.Economy.UseDifficultyMultiplier` is off). When a table's engine first shows the Result phase
   (`TableService.broadcast`, which every state change goes through), `Ranking.check` settles
   it once per table epoch: `Ranks.applyMatch` per connected player (real match or a costly
   forfeit), `applyRank`, rank-up rewards, the match bonus, stats. A player who disconnects
   mid-match is charged in `PlayerRemoving`, before PlayerData ends their session a frame
   later. The engine's result carries `seconds` (server time since the break,
   `brokeAt`) and `forfeit` (the team that surrendered or timed out).
3. *Replicate.* `PlayerData` sets Player attributes (`Money`, `RankXp`, `RatedMatches`,
   `PeakDivision`, `RankTier`, `RankDivision`, `RankIndex`, `DataLoaded`) and `leaderstats`
   (`Rank` text, `Money`). Clients only read them.
4. *Animate.* The shooter alone gets `MoneyGrant` (each grant's pocket and the server time its
   ball drops); `CashFlyer` pops a chip there and flies it to the money HUD, which only rises
   when a chip lands and settles on the attribute when nothing is in flight. Every player of a
   finished match gets `MatchSummary` once; `ResultScreen` animates it, then `NewRankPopup`
   follows a rank change. `/xp` and `/newrank` send `RankEvent`, held until the player is not
   shooting.

**Studio test hooks** (created only when `RunService:IsStudio()`, in ServerStorage, never
reachable by clients): `PlayerDataQA` (read, mutate, end and reload a session, force a failed
load with the `PlayerDataFailNextLoad` attribute), `DevCommandsQA` (run a chat command as a
player, since scripts cannot type into Roblox's chat), and `PoolMatchQA`'s `brokeAgo` (set the
match clock for the one-minute mark).

## Global queue and arenas (2026-09-28)

The designer's global queue: a host's **Join Global Queue** looks in every server for a side
of similar rank; both sides teleport into an **arena**, a reserved server of this same place:
the rooftop with its day cycle (started at day, `LightCycle.offsetToDayStart`) and one table
in the middle in `Config.Arena.Look` (`TableBuilder.build`'s look). After each game (lobby tables too) the result screen has a Rematch row and
the series score.

**Modules.**
- Pure, Lune-tested (`src/shared/Matchmaking/`): `Matchmaker` (the rank window by wait,
  `pair` oldest-first to the closest rank, the rating from rank XP), `Ticket` (a search as
  stored, and the UpdateAsync changes: claim, finalize, revert, cancel, beat, the arena's
  player list), `QueueCore` (the leader's tick and the owner's moves over an injected store;
  `tests/queue_core_test.luau` runs many servers on a fake MemoryStore).
- `Rules/MatchEngine`: the series (`t.series`, counted in `finish`), the rematch vote
  (`Rematch`/`Decline` actions in Result, `rematchReady`, `rematch()`: a new epoch with the
  same seats, teams and settings, the other side breaking), `Result` lasting
  `Multiplayer.RematchSeconds` for a two-sided game, arena tables (`t.fixed`, seats joined
  with a team, `startFixed`), and the pad's search (`canSearch`, `searchParty`, `setSearch`,
  `searchFound`; a party member stepping off clears it).
- `Placement.setLayout`: the arena's one table (`Config.Arena.Table`) replaces the hub's
  sixteen for every loop, on the server and each client (`PlaceMode` and `ArenaTeamSize`
  workspace attributes, set before the Tables folder exists).
- Server: `GlobalQueue` (MemoryStore sorted maps, the leader lease, a pool of reserved
  servers, one poll-and-beat thread per search, teleports with retries and
  `TeleportInitFailed`, `sendHome` to the origin server by `ServerInstanceId`), `ArenaService`
  (detect, start the day, read the player list, stand arrivals at the table and seat them,
  start, Play another and Lobby, the choosing time). `TableService` runs the pad's search (`startSearch`,
  `stopSearch`, `watchSearch`, `searchFound`) and an arena mode (no pad, `seatArena`).
- Client: `QueueMenu` (the 4th button and the searching fold), `PostMatch` (the row, hosted
  by `ResultScreen` in Continue's place), `QueueStatus` (the small top card), `TeleportScreen`
  (set with `SetTeleportGui`), `src/first/Arrival` (ReplicatedFirst: keeps the teleport
  screen until the arena is ready), `MatchHUD` (the Series pill).

**Data flow.**
1. *Search.* The host's `GlobalSearch` action: TableService checks `Engine.canSearch`, takes
   the first whole side, posts a ticket (`GQ_Tickets_v1_<mode>`, sort key = rating) and marks
   the pad (`search` in the snapshot). The owning server reads its ticket every 0.5 s and
   marks it alive every 2 s.
2. *Pair.* The server holding the lease (`GQ_Lease_v1`) scans every mode each second,
   `Matchmaker.pair`s the fresh waiting tickets and, per pair: takes a reserved server, writes
   the player list (`GQ_Matches_v1`, keyed by the reserved server id), claims A, claims B
   (else reverts A), then finalizes both. A cancel wins only while waiting; a claim stuck 5 s
   (the leader died) is undone by its owner's next beat.
3. *Teleport.* The owner sees "matched": `searchFound` (the pad will not start locally),
   `QueueNotice{Found}` (the teleport screen), `PlayerData.handOff` (the save is released
   now), `TeleportAsync` with the access code. A failure retries three times, then
   `PlayerData.resume` and the card returns.
4. *Arena.* `Bootstrap` sees a reserved server (`PrivateServerId`, no owner), sets
   `PlaceMode` and the day offset, reads the list (up to 10 s), sets the layout, builds the
   one blue table and starts `TableService` in arena mode. Arrivals are seated on their side once their save
   is open; everyone in (or 25 s with both sides) starts the game. `Ranking` pays every game
   as in the lobby (its settle is per epoch, so each rematch is paid once).
5. *After.* The table's vote handles Rematch; `ArenaAction` handles Play another (a new
   ticket from the arena, avoiding the last opponent for 10 s) and Lobby (`sendHome`).
   `ArenaState` tells every client the arrivals, choices, searches and each one's time left.
   Every lobby server marks itself open with its player count (`GQ_Servers_v1`, every 10 s
   and a second after anyone joins or leaves); Lobby targets the home server only while its
   mark is fresh, not empty and has room (`Ticket.homeOpen`), else any lobby server, and a
   failed try at home goes to any lobby server at once (a closed server is Roblox's error
   771, with its own popup on every try).

**Studio.** Teleports and reserved servers do not work in Studio: matching runs against
Studio's own MemoryStore, then the teleport reports "Studio". `ServerStorage.GlobalQueueQA`
posts a search from a pretend server; the `StudioArena` attribute (a team size) on
ServerStorage before Play boots an arena with pretend opponents, driven by
`ServerStorage.ArenaQA`. Every step logs a `[8ball] GQ` line with its timing.
