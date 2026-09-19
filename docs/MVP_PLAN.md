# MVP Plan: solo hot-seat 8-ball (ROADMAP Phase 0, Phase 1, milestone 2.1)

## Context

The project folder `/Users/justinjin/Desktop/8ball/` holds only `GDD.md` and `ROADMAP.md`. Nothing from Phase 0 exists yet: no Git repo, no Rojo project, no linters, and Studio is installed (v0.739) but not connected to me over MCP. The goal is a complete, regular 8-ball match on one table where one person plays both sides, built so the physics, controls, camera, sound and look can be tuned before anything multiplayer. Everything is structured so the same simulation can later run on the server unchanged.

## Decisions already made (from your answers) and assumptions

| Topic | Decision |
| --- | --- |
| Table geometry | Generated at runtime by a `TableBuilder` module from `Config` dimensions. MCP is used for the room, lighting, post-processing, inspecting, playtesting and screenshots. |
| Tool install | Homebrew: `rojo stylua selene lune aftman`, then `luau-lsp` through Aftman. I run the commands, you approve each. |
| Aim camera | **One 3D orbit view with automatic framing** (decided 2026-09-19, replacing the fixed "behind the ball" view): the camera sits on the side of the table opposite the aim and looks across the table along the aim line, so the aim always runs up the screen. Every frame it solves for the closest distance and the shallowest pitch (`PitchPreferred`, steepening to `PitchMax` only when the screen shape needs it) that keep the whole table on screen, then slides so the table is centred with a small bias toward the cue ball (`FocusBallWeight`). Fully zoomed out always shows the entire table; pinch or scroll zooms in on the cue ball (`Config.Camera.View`). No toggle, no top-down mode. Avatar about 90% transparent, fading out completely when it is close to the camera. After the strike the camera pulls out to the whole-table view (if the player was zoomed in) so every ball's path is visible, then eases back to the player's zoom when the balls stop (`Config.Camera.Shot`). |
| Ball look | Number and stripe images generated locally with Python (Pillow is installed), uploaded to your Roblox account as decals through Studio, wrapped onto Ball parts. I ask before uploading. Flat colours are the fallback until moderation clears. |
| Scale (assumption) | `Config.Table.StudsPerInch = 0.1`. A 9-foot table is 100 x 50 inch playing surface = 10 x 5 studs, ball diameter 2.25 inch = 0.225 studs, table height 30 inch = 3 studs. That matches R15 avatars (about 5 studs tall) at roughly real proportions. One number to change if it looks off. |
| Docs location (assumption) | `GDD.md` and `ROADMAP.md` move into `docs/`, as your prompt refers to them there. |
| Place file (assumption) | `place/8ball.rbxl` is committed to Git so the room and lighting built through MCP are versioned too. |
| Rematch (assumption) | Milestone 2.1 gets a single "Rematch" button on the win screen. It is not a menu, just the way to start another game. Tell me if you want even that left out. |
| Git identity | Your Mac has no global Git name or email. I will set them for this repo only, using `justinjin28@gmail.com` and the name you give me. |

## What I need from you before building starts

1. Open Roblox Studio, create a new empty Baseplate place, and save it as `/Users/justinjin/Desktop/8ball/place/8ball.rbxl` (File, Save to File As). I create the `place` folder in milestone 0 first.
2. Turn on Studio's MCP server: File, Studio Settings, Beta Features, tick "MCP Server" (or Assistant Settings, MCP Servers, "Enable Studio as MCP server"). Studio listens on localhost:3004. The Claude side is already configured in this session, so once the toggle is on I should see your Studio when I list instances.
3. Tell me the name to use for Git commits.
4. Nothing else. Sounds are chosen later from a list I give you.

## Repository layout

```
8ball/
  docs/               GDD.md, ROADMAP.md, MVP_PLAN.md, SOUNDS.md (candidate list)
  place/8ball.rbxl    the Studio place (room, lighting) - saved by you from Studio
  default.project.json  Rojo map: src/shared -> ReplicatedStorage.Shared, src/server -> ServerScriptService, src/client -> StarterPlayer.StarterPlayerScripts
  src/shared/         pure logic and shared config (no Instances inside Physics/Rules)
    Config.luau       every tunable number, commented, grouped by system
    Physics/          Vec.luau, Ball.luau, Table.luau (rails, pockets, jaws), Collision.luau (swept tests), Simulation.luau (step, events, result), Rack.luau (positions), Cue.luau (inputs -> initial velocity and spin)
    Rules/            Rules.luau (8-ball state machine), ShotJudge.luau (fouls from a shot result)
  src/server/         Bootstrap.server.luau (builds table via TableBuilder at start; later becomes the authority)
  src/client/         Main.client.luau plus one module per system:
    Input.luau, Camera.luau, Avatar.luau, Guideline.luau, BallRenderer.luau, Audio.luau, Effects.luau, UI.luau, Match.luau (hot-seat glue: owns Rules + Simulation on the client for now)
  src/shared/TableBuilder.luau   builds slate/felt/rails/pockets parts from Config (uses Instances, so it is NOT inside Physics)
  tests/              run with Lune; a tiny harness fakes `script.Parent` so shared modules load unchanged
    harness.luau, physics_*.luau, rules_*.luau, run.luau
  tools/              gen_ball_decals.py (writes assets/balls/*.png), lint.sh (stylua --check + selene + luau-lsp analyze), test.sh (lune run tests/run.luau)
  assets/balls/       generated PNGs (committed), asset ids recorded in Config once uploaded
  CLAUDE.md, .stylua.toml, selene.toml, .luaurc, .gitignore, aftman.toml
```

Rule kept: I only ever edit scripts as files. Rojo `serve` streams them into Studio.

## The clean shot boundary

`Simulation.run(tableState, shot) -> ShotResult`, where

- `shot = { angle: number (radians), power: number (0..1), spin: { x: number, y: number } (offset on cue ball face in ball radii, -1..1) , cueBallPlacement?: {x, y} }`
- `ShotResult = { frames: array of per-fixed-step ball positions (for playback), events: ordered array of {t, type = "ballHit"|"railHit"|"pocket"|"cueStrike", a, b, speed}, finalBalls: array of {id, x, y, pocketed: boolean}, firstContact: ballId or nil, durationSeconds }`

The client runs the full simulation instantly when you release the power bar, then plays the frames back over time while Audio and Effects react to the timestamped events. Later, the server runs the same call and clients replay the same frames. Networking becomes "send `shot`, receive `finalBalls`", nothing in Physics changes.

## Physics design (pure Luau, no Roblox types, fixed timestep)

- Units inside the simulation are inches and seconds. Conversion to studs happens only in `BallRenderer` and `TableBuilder`. Real-world friction and speeds then come straight from pool literature.
- State per ball: position (x, y), velocity (vx, vy), angular velocity (wx, wy, wz), pocketed flag. Own tiny `Vec` module with plain numbers, so it runs in Lune.
- Motion model, per ball, per step:
  - Sliding when the contact-point relative velocity is not zero: kinetic friction `Config.Physics.SlidingFriction` (about 0.2) decelerates the ball and changes spin until it rolls.
  - Rolling: rolling resistance `RollingFriction` (about 0.01). Side spin (wz) decays with `SpinFriction`.
  - Stop threshold `RestSpeed` snaps a ball to rest so games end.
- Cue strike (`Cue.luau`): power maps to speed (`MaxCueSpeed`, break about 30 mph). Spin offset gives initial spin: `w = 2.5 * v * offset / R`. Top, back and side spin all fall out of this one formula. Miscue guard: offset clamped to `MaxSpinOffset` (0.5 R).
- Ball-ball collision: elastic impulse along the line of centres with restitution `BallRestitution` (0.93). Spin is carried through untouched (simplified, no throw). This is what makes a stop shot stop and back spin draw.
- Ball-rail collision: reflect the normal velocity with `RailRestitution` (0.75), keep tangential minus a small rail friction, side spin nudges the rebound angle slightly (`RailSpinEffect`).
- Pockets: six capture circles at regulation positions with `PocketRadius` (corner 4.5 to 5 inch, side 5 to 5.5 inch mouths). Each pocket mouth has two jaw points modelled as small fixed circles so balls rattle out of jaws realistically. A ball whose centre enters the capture circle is pocketed, the event is recorded, and it leaves the simulation.
- No tunnelling: each fixed step (1/240 s) is processed event-driven. Compute the earliest time of impact among all ball pairs (quadratic), ball vs rail segments, ball vs jaw points; advance exactly to it, resolve, repeat until the step is consumed. Exact swept circles, so a full-power break cannot pass through anything regardless of speed.
- Determinism: fixed dt, arrays iterated in id order, no `os.clock`, no random. Same inputs always produce the same result on any machine.

### Automated physics tests (run without Studio, in Lune)

1. Energy never increases between any two consecutive steps of a random shot set (kinetic plus rotational).
2. At rest after any shot, no two balls overlap (centre distance >= 2R - 1e-6).
3. No ball centre ever leaves the playing rectangle (minus R) during a shot, including full-power break from many angles.
4. Full-power break scatters the rack: at least 12 of 15 balls move more than one ball diameter, and the minimum pairwise separation at every step never drops below 2R - 1e-6 (the tunnelling check).
5. A ball fired at a rail returns with lower speed and mirrored direction.
6. Spin: cue ball with top spin follows through after a head-on hit; with back spin it comes back; with none it stops. Asserts on sign of post-collision velocity.
7. Determinism: same shot run twice gives identical final positions.
8. Rules tests (milestone 2.1): scratch gives ball in hand, wrong group first is a foul, 8 early loses, 8 after clearing wins, open table assigns groups on first legal pot, turn passes on a miss.

## Test harness in Lune

`tests/harness.luau` uses `luau.load` from `@lune/luau` with a custom environment whose `require` accepts fake `script.Parent.X` instance tables mapped to files under `src/shared`. Shared modules keep normal Roblox-style `require(script.Parent.Config)` lines and load unchanged in both Studio and Lune. Physics and Rules never touch `game`, `Vector3`, `Instance` or `task`, and the harness environment deliberately has none of those, so a slip fails the test immediately. Studio's `run_as_job` can re-run the same suite inside Studio as a cross-check.

## Milestones

Each milestone ends with the same loop: `tools/lint.sh` (StyLua check, Selene, luau-lsp analyze), `tools/test.sh` (Lune), start a playtest via MCP, read the console for errors, screenshot, fix, then stop and report: what I built, what I verified, what you should try by hand. You approve, I commit and tick `docs/ROADMAP.md`.

### M0. Setup (ROADMAP 0.1 and 0.2)
Build: `brew install` the tools, `git init`, move docs into `docs/`, write `default.project.json`, `.stylua.toml`, `selene.toml` (roblox std), `.luaurc`, `aftman.toml` with luau-lsp, download the Roblox `globalTypes.d.luau` for the type checker (I ask first), `CLAUDE.md` with the project rules from your prompt, `Config.luau` skeleton, `tests/harness.luau` with one trivial passing test, `tools/lint.sh` and `tools/test.sh`. Start `rojo serve`, you connect from the Rojo plugin in Studio (I explain the two clicks).
Done means: a `print` I add to a client script appears in Studio's Output after saving the file; lint, type check and test commands all pass; through MCP I can start and stop a playtest, read the console, and take a screenshot.

### M1. One ball rolls (ROADMAP 1.1)
Build: `Vec`, `Ball`, `Table` (rails only, pockets closed), `Simulation` step with sliding/rolling friction and rail bounces, swept ball-vs-rail; `TableBuilder` grey-box (slate, four rail blocks, legs) at the correct scale; `BallRenderer` (one Ball part following simulation frames, rolling rotation for looks); a test key (press F in play mode) fires the cue ball at a random angle and power; a tiny debug HUD showing speed.
Tests: 1, 3, 5, 7 above.
Done means: a fired ball bounces around believably, slows and comes to rest; nothing leaves the table.

### M2. Balls collide and sink (ROADMAP 1.2)
Build: ball-ball swept collisions with restitution, six pockets with jaw points, `Rack` (standard triangle, 8 in the middle, corners of different groups), pocket capture and visual drop, a break test key (press B). Ball look pass one: `tools/gen_ball_decals.py` makes number and stripe PNGs, with your approval I upload them through Studio and record asset ids in Config; balls get SmoothPlastic with a little reflectance for gloss. Flat colours as fallback while moderation runs.
Tests: 2, 4, 6 (spin sign tests need collisions).
Done means: a hard break scatters the rack convincingly, balls drop into pockets, solids and stripes read instantly, and the tunnelling test passes at max power.

### M3. Aim and shoot (ROADMAP 1.3)
Build: `Input` (drag on the table area rotates aim, angular speed proportional to drag speed so slow drags are fine aim; two small nudge buttons for very fine aim; power bar on the right side, press and pull down, release to shoot; cancel by sliding off), `Guideline` (cue ball path, ghost ball at first contact, short object-ball direction line, short cue-ball deflection line, computed by a dry sweep in Physics so it always matches the real result), the full shot pipeline (Input -> `Simulation.run` -> playback), replaces the F/B test keys. Mouse and touch through the same code path.
Done means: in Studio's device emulator (phone) and with the mouse, you can play shot after shot, and the guideline's first contact matches what actually happens.

### M4. Camera and avatar (ROADMAP 1.4)
Build: `Camera` (scriptable) with **one 3D orbit view** (`Config.Camera.View`): the camera orbits the table on the side opposite the aim, looking across the table along the aim line, and solves each frame for the tightest whole-table framing for the current viewport (distance by bisection, pitch from `PitchPreferred` up to `PitchMax` only when a steeper angle shows the table clearly larger, then a slide so the table outline is centred with a small bias toward the cue ball). Zoom 1 = whole table fitted; scroll on PC and pinch on touch zoom in toward the cue ball down to `ZoomMin`, with the pitch easing toward `PitchMin` for the close view. Aim drags work at any zoom. After the strike: the camera pulls out to the whole-table view if the player was zoomed in, holds there so every ball's path is visible, then eases back to the player's zoom and the new framing when the balls stop (`Config.Camera.Shot`). `Avatar`: moves your R15 character to the aim line behind the cue ball, procedural aiming pose by forward kinematics over the rig joints (bent at the waist, back arm drawn, bridge hand forward, stretching over the rail when the stand point is on the table), faded to `Config.Avatar.AimTransparency` (90%) while aiming and fading out completely within `FadeNearStuds` of the camera so it never covers the cue ball.
Done means: a full shot is playable on phone and PC at any zoom, zooming is one gesture, aiming is never blocked by the avatar, the close view shows the cue and the ball like the reference, and watching the shot feels like a replay.

### M5. Spin (ROADMAP 1.5)
Build: spin selector UI (tap the cue-ball icon, a larger cue ball face appears, tap or drag the strike point, offset clamped to the miscue limit), offset fed into `Cue.luau`, small red dot on the icon showing current spin, resets each shot. Physics spin already exists from M1/M2; this milestone tunes `SlidingFriction`, spin transfer and the cue formula until the feel is right.
Done means: top spin visibly follows through, back spin visibly draws back, side spin visibly changes the rail rebound, and test 6 passes with the tuned numbers.

### M6. Look pass: room and lighting (GDD section 11)
Target: the reference screenshot (2026-09-18): teal cloth, glossy balls with visible reflections, warm bar lighting, dark surroundings.
Build through MCP in the place file: a small dim room (walls, floor, ceiling) around the table, a warm SpotLight rig over the table, two or three neon strip accents, Lighting set to Future technology with low ambient, ColorCorrection and Bloom for glow, felt via a Roblox Fabric material tinted green or blue, wooden rails, glossy balls. `TableBuilder` gains material and colour Config entries.
Done means: a screenshot from the aim camera matches the GDD mood (warm pool of light, dark surroundings, glowing accents) and the balls read clearly on a phone-sized viewport.

### M7. Sound and juice, pass one (ROADMAP 1.6)
Build: `Audio` (one Sound per event type, volume and pitch scaled by event speed from Config curves, aim ticks every N degrees, all fired from `ShotResult.events` during playback), `Effects` (sink burst ParticleEmitter, bigger for the 8; "Nice shot" popup on a pot; short screen-space pop when the cue strikes), placeholder audio ids. I search the Creator Store for cue strike, ball clack, rail thud, pocket drop and aim tick, and write `docs/SOUNDS.md` with 3 to 5 candidates each and asset ids so you can audition them in Studio's asset manager. You pick, I swap ids in Config.
Done means: you catch yourself shooting balls around with no goal.

### M8. Rules, hot-seat (ROADMAP 2.1)
Build: `Rules` state machine (break, open table, groups assigned on first legal pot, shoot again on a legal pot, turn passes on a miss, fouls: scratch, wrong group first, no ball hit; ball in hand after a foul, anywhere; break placement behind the head string; 8 early or scratch on 8 loses; legal 8 after clearing wins), `ShotJudge` turns a `ShotResult` into a verdict, `Match` glue drives turns, `UI` HUD (Player 1 / Player 2 turn banner, group icons, remaining balls, foul and ball-in-hand messages, win screen with Rematch). Ball-in-hand placement by dragging the cue ball with overlap checking. Pocketed cue ball respawns.
Tests: rules tests (8) plus a scripted full game that ends in a win.
Done means: a full legal game can be played start to finish as both players, every foul in the GDD is detected and handled, and the win and loss screens appear correctly.

## Honest limits, what you will need to source or make

- Audio: I cannot make sounds. Creator Store search gives candidates; final ASMR-grade audio you will likely want from a sound designer or a licensed library.
- Ball decals: clean vector-style numbers and stripes, but not photoreal. A proper sphere-mapped ball texture needs a UV-mapped MeshPart and an artist.
- Cue stick and table: parts only. Wooden rails and a tapered cue read fine at this stage; real models need a 3D artist later.
- Felt and wood: Roblox built-in materials, no custom textures.
- Avatar pose: procedural, good enough to read as aiming; a hand-made animation will look better eventually.
- Studio setup steps and the Rojo plugin install are clicks only you can do; I walk you through them.

## Verification summary

- Static: `tools/lint.sh` green (StyLua, Selene, luau-lsp) after every milestone.
- Physics: `tools/test.sh` green; tests 1 to 8 as listed.
- In Studio via MCP: start play, run a scripted shot and a break, read the console for zero errors and warnings, screenshot from the aim camera and from the shot camera, check the device emulator at phone size for M3 onwards.
- By hand: each milestone's report lists exactly what to click and what you should see.

## Small open questions (answer any time, defaults in brackets)

1. Felt colour [teal/blue like the reference screenshot; green is the classic choice].
2. Should the guideline show the full cue ball path after the first contact, or only the short deflection stub like GamePigeon [short stub].
3. Ball-in-hand after a foul on the break: anywhere, or behind the head string [anywhere, as the GDD says].
