# 8ball (working title): 3D 8-ball pool on Roblox

Read `docs/HANDOFF.md` first (current state, what the user asked for next, Studio quirks), then
`docs/GDD.md`, `docs/ROADMAP.md` and `docs/MVP_PLAN.md` before doing anything.

## Non-negotiable rules

- **Scripts are files.** Edit only under `src/`. Never create or edit scripts through the Studio
  MCP. MCP is for building parts and lighting, inspecting the scene, playtesting, reading the
  console and taking screenshots. Rojo (`rojo serve`) streams `src/` into Studio.
- **Our physics, not Roblox physics.** Balls are simulated by `src/shared/Physics`. That folder is
  pure Luau: no Instances, no Roblox types (`Vector3`, `CFrame`, `task`, `game`...), fixed
  timestep, units are inches and seconds. It must run in Lune (`tools/test.sh`) and later on the
  server unchanged. `src/shared/Rules` follows the same rule.
- **A shot is inputs.** `Simulation.run(state, shot) -> ShotResult`. Everything else (rendering,
  audio, effects, rules) consumes the result. Keep that boundary clean for networking later.
- **One module per system.** Physics, Rules, Input, Camera, Avatar, Guideline, BallRenderer,
  Audio, Effects, UI, Match. No cross-cutting globals.
- **Every tunable number lives in `src/shared/Config.luau`** with a comment saying what it does.
- **Determinism.** No `os.clock`, no `math.random`, no hash-order iteration inside Physics/Rules.

## How we work

One milestone at a time from `docs/MVP_PLAN.md`. After each: `tools/lint.sh`, `tools/test.sh`,
start a playtest through MCP, check the console for errors, screenshot, fix. Then stop and tell
the user plainly what was built, what was verified and what to try by hand. Commit only after
it is verified (the user does not want to be asked for the word "approve"), then tick the box in
`docs/ROADMAP.md`. On 2026-09-19 the user brought the lounge and twelve playable tables into
scope (see `docs/HANDOFF.md`), which means server-owned tables. Still not in scope unless the
user asks: bots, abilities, coins, shop, data saving, menus beyond joining a table.

The user is a beginner. Explain installs, clicks and decisions in simple steps.

## Commands

```bash
rojo serve                 # then click Connect in the Rojo plugin inside Studio
tools/lint.sh              # StyLua --check, Selene, luau-lsp analyze
tools/format.sh            # StyLua format
tools/test.sh              # Lune test runner: tests/*_test.luau
tools/get-types.sh         # one-time download of Roblox type defs for luau-lsp
```

## Layout

- `src/shared/Config.luau` all tuning numbers
- `src/shared/Physics/` Vec, Ball, Table, Collision, Simulation, Rack, Cue (pure)
- `src/shared/Rules/` Rules, ShotJudge (pure)
- `src/shared/TableBuilder.luau` builds the table parts from Config (uses Instances, not physics)
- `src/server/` Bootstrap
- `src/client/` Main plus one module per system
- `tests/` Lune tests; `tests/harness.luau` fakes `script.Parent` so shared modules load unchanged
- `tools/` scripts; `assets/balls/` generated decal PNGs; `place/8ball.rbxl` the Studio place
