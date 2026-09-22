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
  Server inputs use fixed 4-degree elevation; ability ids require server authorization.
- **Determinism.** No `os.clock`, no `math.random`, no hash-order iteration inside Physics or
  Rules. Same inputs give the same result on every device.
- **Never trust the client.** The server owns match state, validates every shot and ability,
  and decides what happened.
- **One module per system.** No cross-cutting globals. Every tunable number lives in
  `src/shared/Config.luau` with a comment.
- **Every feature works on phone, PC and gamepad** and is checked on all three.

## 2. Scale and coordinates

- `Config.Table.StudsPerInch = 0.16`. A 9 ft table is 100 x 50 in of playing surface, about
  17.8 x 9.8 studs with rails. Ball radius 1.3 in (slightly oversized for readability).
- Physics x runs along the table length (head rail negative, foot rail positive), physics y
  across the width. World: physics x maps to world X, physics y to world -Z, Y is up. Each table
  has its own origin and yaw; `TableBuilder.toWorld` and `toTable` convert per table.

## 3. Physics (what exists)

Event-driven fixed step (1/240 s) with exact time of impact for ball-ball, ball-segment and
ball-point contacts (no tunnelling at any power). Sliding-to-rolling friction in closed form,
rolling resistance, radius-independent side-spin decay. Ball-ball contacts use a tabulated
speed-dependent friction impulse for throw and spin transfer, retaining full contact torque
while translation stays on the cloth. Cue impact uses stick/ball mass, tip restitution and
fixed default 4-degree elevation, with squirt and tilted spin feeding cloth swerve. The
straight Classic guideline predicts launch direction, not the later curved path. Pure side spin does not delay shot completion. Cushions
use Han's tilted contact normal through the centre, full tangential friction, and tabulated
normal-speed restitution. Translation remains planar; only tangential impulses create torque.
Six pockets use capture circles with jaw facings and a physical drop (z, vz, funnel). Corner
openings have a flat shelf scaled to ball diameter, and facings extend to their rim. Wedge guards
against zero-time hit loops. `Aim.trace` gives the guideline from the same code as the shot.
Tests in `tests/`: energy never increases, no overlap at rest, no ball leaves the table, the
break scatters the rack, rail bounce mirrors, spin signs, determinism, trace matches simulation.
Per-shot cushion overrides are copied from a named material, sent with the replay seed,
and cleared on completion. Live ability requests remain disabled pending server authorization.
Generated table parts share this geometry; the imported table mesh needs separate art updates.

## 4. Networking: server-owned tables

Each table in the lounge is a `Table` instance on the server with: id, origin and yaw, host,
settings (mode, difficulty, abilities on/off), seats with teams, match state (rules state
machine, physics state, turn, clocks), spectators.

Shot flow:
1. The shooter's client sends only inputs to the server (angle, power, spin, ability id).
2. The server checks turn, seat, cooldowns and ranges, runs `Simulation.run`, applies rules,
   and stores the result.
3. The server broadcasts the inputs (plus the final positions) to every client in the server.
   Each client replays the same simulation locally, so motion is smooth with no lag. When the
   balls stop, clients snap to the server's final positions.
4. During a turn the shooter's aim angle and ball-in-hand position are replicated at a low rate
   (about 10 per second) so opponents and spectators see the cue turn. Never the guideline or
   power.

PC opponents run on the server using the same `Simulation` to try candidate shots (skill =
aim noise and how many candidates it considers), with a per-shot compute budget so twelve
tables of PCs stay cheap.

## 5. Module map

Shared (`src/shared`): `Config`, `Physics/` (Vec, Ball, Table, Collision, Cue, Rack, Aim,
Simulation), `Rules/` (Rules state machine, ShotJudge; pure, to be written), `Abilities/`
(catalog and pure effect hooks into the simulation, to be written), `TableBuilder`,
`CueStickBuilder`, `AvatarPose`, `ShotInput` (validation/seed quantization), `Strings` (HUD
copy), `Catalog`
(item data rows, to be written).

Server (`src/server`): `Bootstrap` (builds the lounge tables, publishes assets), `TableService`
(per-table state, joins, seats, match loop), `ShotService` (validation, simulation, broadcast),
`BotService`, `PlayerData` (session-locked saves), `Economy`, `Ranking`, `Analytics`.

Client (`src/client`): `Main` (wiring), `Match` (replays shots), `BallRenderer`, `Input`
(mouse, touch, gamepad), `SpinSelector`, `Guideline`, `Camera`, `Avatar`, `UI`, `Audio`, `Effects`, `Lounge`
(pads, seats, snack counter, doors).

## 6. Data model

- **Catalog:** one table of item rows for cues, tables and abilities: stable string id, type,
  rarity, display name key, model or asset ids, effect parameters, limited quantity and
  serial rules. Adding an item is adding a row plus assets, never code.
- **Inventory:** every cue and table is a unique object (`{uid, itemId, serial?, acquiredAt,
  tradable}`); abilities are owned flags. Equipped cue, table and ability are ids on the
  profile.
- **Profile (saved):** money, rating and peak rank per season, stats (wins vs people, wins vs
  PC, losses, best win streak, match history last 20), opponents-played-today counters,
  daily streak state, first-time flow progress, flags (founder, VIP), settings (country).
- **Saves:** a session-locked, versioned save library (ProfileStore style) from the first
  saved money. Every layout change bumps a version with a migration. Robux receipts are
  processed exactly once.
- **Analytics:** Roblox built-in analytics for the funnel and economy events, server-side.

## 7. Performance budgets

- Table model: at most about 20,000 triangles and eight 1024 px maps per table model; every
  table is a full model, so the twelve in a server must share nothing but the budget. Automatic
  render fidelity (LOD) on all meshes, decorative parts do not cast shadows, no per-table
  shadow-casting lights, StreamingEnabled on.
- Balls: one shared sphere mesh (about 550 triangles) with per-ball textures.
- Server: about 30 players; PCs never play PCs; per-shot bot budget.

## 8. Conventions

- Edit scripts as files only, synced by Rojo. Studio (through the MCP tools) is for building
  parts and lighting, inspecting, playtesting, console and screenshots. Assets that scripts
  cannot create (imported meshes, SurfaceAppearance maps, MaterialVariants) live in the place
  file, saved to `place/8ball.rbxl` and published.
- Lint: `tools/lint.sh` (StyLua, Selene, luau-lsp). Tests: `tools/test.sh` (Lune). Both green
  before every commit.
- Asset generators live in `tools/` and write into `assets/`; package delivery notes live next
  to each package (`assets/*/Readme.md`) and are read only when importing that package.
