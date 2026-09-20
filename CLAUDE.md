# Crazy 8 Ball (working name): 3D 8-ball pool on Roblox

These rules apply to every AI coding tool working in this repository (Claude Code reads this
file; Codex reads AGENTS.md, which is the same file).

## Read first, every session

1. `docs/STATUS.md`: where the build is and the current milestone.
2. The current milestone in `docs/ROADMAP.md` (the first unticked box).
3. `docs/ARCHITECTURE.md` before touching `src/`.
4. `docs/GDD.md` for design intent; sections are split into Decided and Open. Never guess an
   Open item, ask.
Read `docs/STUDIO_NOTES.md` when Studio, Rojo, MCP, Lune or Blender misbehave. Read
`assets/*/Readme.md` only when importing that package. `docs/DECISIONS.md` is the dated log.

## Non-negotiable rules

- **Scripts are files.** Edit only under `src/`. Never create or edit scripts through the
  Studio MCP. Studio tools are for building parts and lighting, inspecting, playtesting, the
  console and screenshots. Rojo streams `src/` into Studio.
- **Our physics, not Roblox physics.** `src/shared/Physics` and `src/shared/Rules` are pure
  Luau: no Instances, no Roblox types, fixed timestep, inches and seconds, deterministic (no
  `os.clock`, `math.random`, or hash-order iteration). They run in Lune and on the server.
- **A shot is inputs.** `Simulation.run(state, shot) -> ShotResult`; everything else consumes
  the result. Keep the boundary clean for networking.
- **Never trust the client.** The server owns match state and validates every shot, ability
  and purchase.
- **One module per system**, no cross-cutting globals. **Every tunable number lives in
  `src/shared/Config.luau`** with a comment.
- **Every feature works on phone, PC and gamepad**, and is checked on all three before a
  milestone is done. Every drag has a button alternative.
- **Player-facing text lives in the shared strings module.** Items (cues, tables, abilities)
  are catalog data rows plus assets, never new code per item.
- **Saves** go through the session-locked, versioned save layer; never a raw DataStore call.
- The currency is **money** in code, UI and docs.

## How we work

One milestone at a time. Plan in plan mode first for anything that touches more than one
module. The milestone loop: `tools/lint.sh`, `tools/test.sh`, confirm Rojo sync, playtest in
Studio through MCP on phone, PC and gamepad emulation, read the console, screenshot, fix. Then
tell the user plainly what was built, what was verified and what to try by hand. Commit as soon
as a step is verified (the user does not want to be asked for approval), push, tick the box in
`docs/ROADMAP.md`, rewrite `docs/STATUS.md`, and add a dated line to `docs/DECISIONS.md` for
any design decision made along the way. Ask the user to save and publish the place when
Edit-mode assets changed. Stopping an active Studio play session to verify is allowed.

The user is a beginner: explain installs, clicks and decisions in simple steps. New ideas go
into the GDD's parked list, not into the current milestone.

Git hygiene: never commit logs, caches or checkpoint renders (see `.gitignore`); commit a
`.blend` only when the model changed; Git LFS only if a file passes 50 MB.

## Commands

```bash
rojo serve default.project.json   # then the user clicks Connect in the Rojo plugin
tools/lint.sh                     # StyLua --check, Selene, luau-lsp analyze
tools/format.sh                   # StyLua format
tools/test.sh                     # Lune test runner: tests/*_test.luau
tools/get-types.sh                # one-time download of Roblox type defs for luau-lsp
```

## Layout

- `src/shared/Config.luau` all tuning numbers; `src/shared/Physics/` pure simulation;
  `src/shared/Rules/` pure rules (not yet written); `src/shared/TableBuilder.luau`,
  `CueStickBuilder.luau`, `AvatarPose.luau` build Instances from Config
- `src/server/` Bootstrap and services; `src/client/` Main plus one module per system
- `tests/` Lune tests and harness; `tools/` lint, test and asset-generator scripts
- `assets/balls`, `assets/ui` generated images and the ball mesh; `assets/table`,
  `assets/lounge` Blender packages with their own Readme; `place/8ball.rbxl` the Studio place
- `docs/` GDD, ROADMAP, ARCHITECTURE, STATUS, DECISIONS, STUDIO_NOTES, `prompts/` (briefs for
  Blender jobs), `ideas/` (raw dumps already merged, do not read)
