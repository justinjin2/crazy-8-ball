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
animation, including the hover sway every hoverable part calls), `PadEffects` (the queue pads' rim, rings, arrow, glow, motes and join sound),
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
   `PeakDivision`, `RankTier`, `RankDivision`, `RankIndex`, `WinStreak`, `DataLoaded`) and `leaderstats`
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

## The economy: items, cases, shop, rewards (2026-09-28)

Built to `docs/ECONOMY.md` (every number) on branch `economy`. The server decides everything;
clients send ids and counts, never an amount, price, rarity or result.

**Modules.**
- Pure, Lune-tested (`src/shared/Progression/`): `Catalog` (every cue as a data row: rarity,
  group, tradable, sellable, which cases drop it, vaulted, its effect style and placeholder
  look; `Catalog.style` turns a look into CueArt segments), `Cases` (odds as integer thousandths
  of a percent, `roll(caseId, rng)` with the rng passed in, per-cue odds for the Odds panel,
  prices with bulk and sale, sell-back, the free-case rule), `Inventory` (functions over the
  save: counts, duplicates, selling, equipping, the Index rows, the client snapshot), `Daily`
  (login streak with day 28, playtime gifts, codes), `Shop` (offer windows, VIP, product
  grants, Money Party, the Limited shelf, and `processReceipt`, the once-only receipt logic
  with its Roblox calls passed in so Lune can test it), `ShopView` (the ShopState payload,
  the Buy check with its reasons, when a window next opens or closes) and `RewardView` (the
  RewardState payload, rewards as lists), `Requests` (the inventory service's
  token bucket, argument checks, Limited refusals and reply reasons), `Counts` (the counters'
  shard choice, their UpdateAsync transforms and the shard sums), plus the rewritten `Ranks`
  and `Money` and `SaveSchema` v2.
- Server: `PlayerData` (the only writer of saves: named, validated mutations for every item,
  reward and purchase), `Items` (the inventory service: `ItemRequest`, rate limits, buying,
  opening, selling, equipping, the Index claims, PolicyService), `Counters` (copies in
  existence, the Limited copy counter, the first Reyes), `Store` (ProcessReceipt, game passes,
  VIP, the offers, Money Party, Fast Open, `StoreRequest`), `Rewards` (daily streak, playtime,
  codes, `RewardRequest`), `Announce` (the banner, MessagingService for every-server news),
  and `Ranking`/`Economy` for match XP, money, free cases and rank-up rewards.
- Client: `Menus` (one full menu at a time, close rules, the slight dim, the gamepad
  selection put back), `MenuFrame` (the header band, tabs, sheet and red X every menu uses),
  `MenuColumn` (the left column: Shop, Inventory, Rewards, Trade with red dots),
  `ItemState` (the client's copy of the ItemState, ShopState and RewardState snapshots and the
  request wrappers), `CueThumb` (a cue's tinted thumbnail from the layer images), `Banner`,
  `InventoryMenu`, `CaseOpening` (the reel and Fast Open's grid), `ShopMenu`, `RewardsMenu`,
  `TradeMenu`, `CueViewport` (the Index's cue turning in 3D: a ViewportFrame holding
  `CueStickBuilder.display`, a thickened stick, black for a cue not found yet; it turns on
  RenderStepped only while the Index tab shows).

**Remotes** (`Net`): `ItemRequest`, `StoreRequest`, `RewardRequest` (RemoteFunctions: the
client asks, the server answers `{ ok, reason?, ... }`), `ItemState`, `ShopState`,
`RewardState` (a player's snapshots, sent on load and after every change), `Banner` (to
everyone), `CueFound` (to one player: cues new to their Index and the finder's money each
paid, for every source but a case reel). The protocol is written next to each remote in
`src/shared/Net.luau`.

**Finder's money** (2026-09-28). `Inventory.addCue` and `addUnique` answer a second value,
true when the cue was never in the save's Index (`Inventory.found`), and
`Inventory.findMoney(id)` prices it from `Config.Index.FindMoney`. Every PlayerData path that
gives a cue (`giveCue`, `giveUnique`, `openCases`) pays it in the same mutation and notes it;
`commit` then fires `PlayerData.CueFound` unless a reel shows it (`openCases`, and a reward
with `firstWinCase`), and `Items` sends that on as the `CueFound` remote (the client's
`Banner` words it). A reel's finds ride its answer instead (`OpenCase` results' `found`,
`MatchSummary.firstWin.found`): `CaseOpening` holds that much of the money HUD back
(`MoneyHud.expect`) from the answer until the card pops, then `release`s it and flies it.

**Attributes** (server-set, clients read): on the player `EquippedCue` (everyone's stick and
trail follow it), `Vip`, `FastOpen`, `RookieLeft` (the rank HUD's ROOKIE x2 pill),
`CasesUnopened` and `RewardReady` (the column's red dots), `PaidRandomRestricted` and
`PaidItemTradingAllowed` (PolicyService on join; `Items`); on `ReplicatedStorage.CueCounts`
one attribute per cue id (copies in existence) and on `ReplicatedStorage.LimitedSold` one per
Limited cue; on `ReplicatedStorage` `CaseSale`, `CaseSalePercent` and `CaseSaleEndsAt` while a
case sale runs; on `workspace` `MoneyPartyEndsAt` and `MoneyPartyBuyer`.

**Copies in existence** (`Counters`). Each server keeps pending +/- per cue (up when unboxed
or bought, down when sold) and every `Config.Items.FlushSeconds` (plus jitter, and on
BindToClose) adds them with one `UpdateAsync` to its own shard key, `shard_<n>` with n from
the JobId (`Config.Items.CountsShards` = 8), in `CueCounts_v1` (`CueCounts_Studio_v1` in
Studio). Every `ReadSeconds` (plus jitter) one `GetAsync` per shard sums the totals into the
attributes; each is that read's total plus what this server added since (flushed after the
read began, being flushed, or pending), so an unboxing moves the local number at once. Nothing
is published before the first read. A background flush or read waits while Roblox's DataStore
budget is under `Config.Items.BudgetFloor`, so the saves always come first.
Budget per server: 1 write a minute and 8 reads (plus one per Limited cue) every 2 minutes,
and nothing at all while nothing changed; far under Roblox's per-server
limits (60 + 10 x players a minute each). The limit is per key: 8 shards take about 8 x 60
writes a minute in total, so about 480 servers flushing once a minute; past that raise
`CountsShards`. Counts lag by up to a few minutes and a crash loses at most one flush.
**Limited copies**: one key per Limited cue in `LimitedCounts_v1`, holding the count and which
user got which number (`{ n, by = { [userId] = copy } }`, about 20 bytes a buyer); `UpdateAsync`
hands a player who already has a number that same number again (a retry or a rejoin after a
failed buy, so leaving mid-purchase wastes none), and anyone else the next number only if
under the cap and before the end time (`Counts.takeNext`). The money is checked before and
taken only after a number is given, and a failure takes nothing. The sold counts are read on
the copies' loop and after each take; `Counters.limitedSold` is nil until the first read. **Firsts**: `Firsts_v1`, one key per first ("Reyes"),
set only if empty (`Counts.claim`); `Announce` gives the first Reyes the one-of-one title
through `PlayerData.addTitle` and tells every server over MessagingService
(`Config.Items.AnnounceTopic`).

**Robux.** `Config.Products` lists every developer product and game pass with `Id = 0` until
the designer creates them in Creator Hub. `Store` sets `MarketplaceService.ProcessReceipt`
once: player not here or save not loaded -> NotProcessedYet; the PurchaseId already in the
save -> PurchaseGranted; else one PlayerData mutation grants and records the id, then the save
is written (`Profile:Save()` and its `OnAfterSave`, with a timeout) before PurchaseGranted.
A receipt waits for its player's save to load (`PlayerData.waitLoaded`), and is checked again
when it arrives (`Shop.receiptCheck`), because a client can open any product's purchase box
itself: the VIP offer when already VIP or outside its windows, the Starter Pack when bought or
past its week (each window gets `Config.Shop.OfferGraceSeconds` more here than at the prompt)
pay money instead (`Shop.fallbackMoney`: the Robux price at the first pack's money per Robux),
logged, so nobody pays for nothing. A Robux Limited (the Founder's Cue) takes its copy number
from `Counters.takeLimited` (with `LimitedReceiptGraceSeconds` past its end); sold out, ended,
not started or already owned pay the same money; a counter error or a busy counter leave the
receipt NotProcessedYet (Roblox retries it). A Money Party receipt always adds its full 15
minutes (the one-hour cap only stops the prompt), and starts or extends this server's party
(workspace `MoneyPartyEndsAt`, `MoneyPartyBuyer`, `Announce.party`).
VIP = owns the pass or bought the welcome offer. Passes are asked with `UserOwnsGamePassAsync`
on join (retried); a pass bought in game counts at once when the server's
`PromptGamePassPurchaseFinished` says it was purchased (Roblox's own guide), and the next
join's check confirms it. The dev
command `/buy` runs the same grant with a fake purchase id (`Store.grant`); `/vip` and
`/fastopen` fake pass ownership for the session (`Store.setPass`). `StoreRequest` checks a
Buy with `ShopView.check` before this server prompts it; ShopState is re-sent at
`ShopView.nextChange` when an offer, a Limited, the sale or the party opens or closes. The
Studio hooks `ServerStorage.StoreQA` and `RewardsQA` drive both services from `execute_luau`.

## Ultimates (2026-09-28)

Built to `docs/GDD.md` section 9 and `docs/ECONOMY.md` 11.7-11.8 on branch `ultimates`: a bar
that fills in a match, one press arms your equipped ult for your next shot, and a spin screen
rolls ults into three slots. The server decides everything; a remote never carries an amount,
price, rarity, ult id to grant or a result.

**Modules.**
- Pure, Lune-tested (`src/shared/Ults/`): `Catalog` (the 13 rows of `Config.Ults.Catalog`:
  rarity, `Built`, `Effect`; `usable` hides placeholders unless the developer flag is on),
  `Fill` (what a shot or a timeout adds to a bar: own balls by run length, NICE SHOT, the
  opponent's balls scaled by how far behind you are, turn and teammate gains, the difficulty
  and after-first-ult multipliers, the per-turn cap), `Roll` (odds in parts per million,
  Normal and Lucky, pity at `PityAt` from `PityFrom`, the rng passed in), `Slots` (functions
  over the save's `Ults` table: take and place a spin's result, locks, select, the
  confirm-replace rule, the daily free spin, counts), `Match` (the rules on the engine's
  table: bars, `check`/`activate`, the arming wait with the clock paused, `shotOverrides`,
  spending, teams, practice in solo, the PC policy `pcShouldActivate`, `view` for the
  snapshot, the dev hooks), `SpinView` (the UltState payload and the request reasons) and
  `Effects/Magnet` (the pull, stepped by the physics).
- `Rules/MatchEngine` calls `Ults/Match` at a new game, each turn's start, a foul, a timeout,
  the clock tick, `acceptShot` (refuses "UltArming" during the wait; arms the effect; tags
  `t.shot.ult`) and a shot's resolution; the snapshot carries `ults = Match.view(t)`.
- `SaveSchema` v3: `Ults = { Slots, Selected, Locked, Spins, LuckySpins, Pity, FreeSpinDay,
  SpinsDone, QueueUlts }`, migrated from v2 with Magnet in slot 1 and 3 starter spins.
- Server: `UltService` (UltActivate, the gains after each flushed shot through
  `TableService.onFlush`, UltNotice, the dev and QA hooks), `UltSpins` (UltRequest, UltState,
  UltAuto; spins, locks, money packs, Robux through `Store`, the daily free spin, Auto Spin,
  the developer flag; started from `Rewards.start()`), `PlayerData` (every ult mutation:
  `ultSpin`, `ultSelect`, `ultLock`, `buyUltSpins`, `addUltSpins`, `addUltLucky`, the dev
  setters), `Store` (the Spin and Lucky products, the UltSlot2/3 passes). Spins also come
  from rewards: a reward row carries `spins` and `lucky` (`Progression/Daily`: streak day 7,
  the day's last playtime gift, codes; `Progression/Ranks`: rank-up spins), paid in the
  same PlayerData mutation as its money and cases. `Ranking` passes them on to the popups;
  `Announce` (the Legendary and Mythic banner), `GlobalQueue` (the Ults On and Off pools).
- Client: `UltHud` and `UltBar` (the bar, its gains, READY and the press prompt, the armed
  pills, Practice), `UltCutscene` (the manga panel everyone at the table sees), `MagnetFx`
  (Magnet's armed look, each hit ball's charge rings, the pull's beams, dust, pocket ring and vortex, and its sounds), `MatchHUD` (the opponent's ult
  icon, the NO ABILITIES pill, the clock held while an ult arms), `PadGuide` (the Ability line),
  `ResultScreen` (NO ABILITIES), the reward screens' spin chips, and the spin screen (UltScreen,
  UltStage and their parts; see below).

**The physics hook.** A shot's `state.overrides` may carry `Effect`, `Targets` and
`EightPocket`. `MatchEngine.acceptShot` calls `Simulation.armEffect` right after
`Simulation.strike`, with the targets the rules chose (the shooter's own group's balls, or
only the 8 with the called pocket on their legal 8 shot; never the cue ball or the
opponent's). `Simulation.step` runs `Effects[Effect].step` before `advance` every fixed step,
so the effect is as deterministic as the rest; the replay carries the overrides and every
client steps the same pull. A new ult with physics is one `Effects/<Id>.luau` plus its
catalog row's `Effect`.

**Remotes** (`Net`): `UltActivate` (no arguments), `UltGain`, `UltNotice` for the match;
`UltRequest` (RemoteFunction: Spin, Select, Lock, BuySpins, BuyProduct, AutoStart, AutoStop),
`UltState` and `UltAuto` for the spin screen. The protocol is written next to each.

**Attributes** (server-set): on the player `UltSpins`, `UltLucky`, `UltFreeSpin` (the column's
red dot), `UltEquipped` (the equipped ult id), `UltDevAll` (the developer flag).

**Studio.** `ServerStorage.UltQA` (state, setBar, full, arm, activate, pcTurn) and
`UltSpinsQA` drive both services; the ult dev commands (`/ulthelp`) go through the same APIs.

## Ability framework (2026-09-29)

What every ability plugs into (docs/prompts/ABILITIES_PROMPT.md 5.2). "Ult" in code,
"Ability" on screen.

**Physics hooks** (`Physics/Simulation`, pure). An armed effect (`Ults/Effects/<Name>`) may
define `step(state, dt)` (before each fixed step), `after(state, dt, events, ops)` (after it,
with that step's events) and `finish(state, events, ops)` (at rest). Scratch lives in
`state.fx` (reset at each strike and arming; array order, never hash order);
`state.fx.ghost[id]` takes a ball out of every contact; `state.fx.material[id]` (a
`BallMaterial`: cushion restitution and friction, ball restitution, cloth frictions, until
`Until`) gives an object ball its own material (Super Bounce's caught ball). An effect may plan once
at its first step and keep the plan in `fx` (Heat Seeker's A* path to the locked ball: nothing
moves before the first contact), or schedule by shot time in `fx` (Chain Lightning's jumps,
one every `LinkSeconds` after the charge, each target chosen from the positions at that step).
An effect that must not miss a fast ball records the positions in `step` and tests each
centre's path in `after` (Portals: a pass through a portal's inner circle teleports the ball).
`Simulation.Ops`: `remove` (the ball
leaves the table with a "removed" event that `ShotJudge` counts as a pot), `teleport`, `halt`
(the settle stops with `outcome.halted`, keeping overrides and fx) and `emit` (an "ult" event
with a kind; kind "slow" adds `value` wall seconds at shot time `x`, summed into
`outcome.extraSeconds`). The overrides carry `Targets` and `OppTargets` (whose balls, 5.7),
`EightPocket`, `Pick`, `PhaseCue` (the cue ball passes through balls), the cue ball's material
(`CueRailRestitution`, `CueRailFriction`, `CueBallRestitution`, `CueSlidingFriction`,
`CueRollingFriction`, until `CueUntil`) and `Params`.

**Arming** (`Ults/Arming`, pure). `targets` (the shooter's and opponent's balls, the legal 8),
`pick` (validates a client's aim-phase pick: "OwnBall" or "Portals"), `extras` (each
ability's own overrides from Config). The shared skill rule numbers are
`Config.Ults.Shared` (`OpponentFactor`, per-owner caps, reach share).

**The engine** (`Rules/MatchEngine`). Refuses "PickRequired" until an armed pick ability has
one (the `UltPick` table action). A halted outcome from Time Stop's effect puts the table in
the Frozen phase: the shooter's second strike comes through `ShotFired` (`strikeFrozen`), or
the deadline resumes it (`resumeFrozen`, then `TableService.onLateShot` pays and sends the
late result through `ShotService`). Rewind rows (`Redo`) snapshot the table at acceptance; a
shot with none of the shooter's balls down restores it (`rewindTo`), plays the Rewinding phase
and gives the redo clock (the snapshot's `rewound` and `redoClock`; the wire shot carries
`rewind = true` from the start, since the server has already judged it).

**Client replay** (`client/Match`). Hides "removed" balls, slows the clock at "slow" events,
stops at a halt and continues with the server's second-strike parts; `setTimeScale` is the
`/slowmo` hook. A shot marked `rewind` is taped as it replays (every ball's position, spin and
shown-or-not each frame); the Rewinding snapshot then flies the table back through the tape
(`startRewind`, `stepRewind`, busy meanwhile) and lands on the server's pre-shot table. A
client with no tape (it joined late) just takes the snapshot's table. In the Frozen phase
`Main` gives the shooter a frozen turn (`frozenTurn`: the replay halted in stopped time, the
cue ball on the table, no second strike yet): the normal aim, pull and spin controls, sent as
an ordinary shot that the server takes as `strikeFrozen`. The server streams no aims in
Frozen, so watchers see the struck cue ball but not the cue before it.

**Looks** (client). `AbilityFx` is the registry (`Config.UI.AbilityFx.Looks`) and the kit
handed to each look's `start(hub, parent, kit)`: a per-table anchor that lingers and releases,
parts, beams, particles, lights, timers, ball and pocket positions, the event feed, and the
reach preview ring (drawn on the ghost ball while aiming, cut at the cushions, opponent balls
in reach in red). `ScreenFx` holds the table-wide screen effects (grade, overlay, flash,
shake, FOV punch, invert) for players at or near the table; `SoundSheet` plays clips cut from
the uploaded sound sheets; `AbilityModels` clones the models `server/AbilityAssets` loads once
per server through InsertService into `ReplicatedStorage.AbilityAssets` (ids in
`Config.Ults.Assets`). A look times its effects on a clock advanced by `dt x match.timeScale`
when they should slow with `/slowmo` (ChainLightningFx's bolts and glows). `UltPick` is the top-down pick view (`PickMath` is its pure maths).

**Tools.** `/slowmo <scale>` and `/abilitysetup <id|name>` (Config.Ults.Setups) for the look
checks; `tests/ult_value.luau` plus `tools/ult_value.luau` measure an ability's worth with
the careful and careless shooters into `tools/ult_value_results.json`, which
`tools/ult_model.py` reads. The Blender scripts are `tools/blender/abilities/`.
