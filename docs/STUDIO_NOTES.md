# Studio, Rojo, MCP, Lune and Blender notes

Read when something misbehaves. Everything here was learned the hard way.

## Rojo

- `rojo serve default.project.json` (port 34872) must be running; start it in the background
  from the agent session. After every Studio restart or Rojo restart the user must click
  Connect in the Rojo plugin. Confirm sync before playtesting with the MCP `script_grep` for a
  string you just added. Studio's Play copy is a snapshot: stop Play, let it sync, start Play.
- StyLua reformatting breaks exact-string scripted edits: after every scripted edit, grep for
  the new text. Run `tools/format.sh` then `tools/lint.sh`.

## The place file

- Things scripts cannot create live in the place: `ServerStorage.PoolTableModel` (with
  SurfaceAppearances and collision fidelity), `ServerStorage.BallMesh`, the `PoolClothBlue`
  MaterialVariant, imported lounge meshes. MeshId, SurfaceAppearance maps, MaterialVariant maps
  and CollisionFidelity are plugin-only writes: set them in Edit mode and save. `TextureID` on
  a MeshPart is scriptable, which is how per-ball textures work at runtime.
- The user must save (`place/8ball.rbxl`) and publish after any Edit-mode change.

## Studio MCP

- Every call needs `studio_id` from `list_roblox_studios`.
- `screen_capture` is black in Play mode. Preview visuals in Edit mode: build the table with
  `TableBuilder.build(workspace)`, add preview parts in a `CameraPreview` folder, set the
  camera, capture, then destroy the preview and the table. Beams do not render in captures.
- Edit-mode `require` results are cached for the Studio session: when Config changed since
  the last Edit-mode require, patch the cached table in the preview script.
- `execute_luau` on the Edit datamodel is unavailable during Play. Numeric checks in Play go
  through the Client datamodel (for example `WorldToViewportPoint`).
- `upload_image` needs http URLs: `python3 -m http.server 8765 --bind 127.0.0.1 --directory
  assets`, batches of four or Studio disconnects. `generate_material` needs `materialId`.
- MCP tools can leave Edit `UserInputService.MouseBehavior = LockCurrentPosition` (cursor
  trapped in the viewport); reset it to Default after previews.
- Mouse and keyboard input tools are flaky (coordinates scale with the device emulator,
  "duplicate button state"); prefer scripted checks.
- Simulating the join prompt from a Client script: teleport the character next to the prompt,
  wait half a second, `InputHoldBegin`, wait, `InputHoldEnd`. A hold in the same tick as the
  teleport does not trigger.
- The user gave standing permission to stop an active Studio play session when verifying.
- EditableMesh (`AssetService:CreateEditableMeshAsync`) reads triangle counts of the user's own
  meshes in Edit mode.

## Lune tests

- `tests/harness.luau` builds a fake `script.Parent` tree from `src/shared` and compiles each
  module with `local script, require = ...` prepended after `--!strict`; no Roblox globals
  exist there, so a Roblox type slipping into Physics fails immediately. Tests are
  `tests/*_test.luau` returning `{name = fn}`.

## Blender

- Blender 5.2 at `/Applications/Blender.app`. Headless:
  `/Applications/Blender.app/Contents/MacOS/Blender -b file.blend --python-expr "..."`.
- Packages in `assets/table` and `assets/lounge` have rebuild scripts, a `Readme.md` with
  import steps, and `Markers.json` (lounge) with Roblox-space positions. Import through the 3D
  Importer with Scale Unit: Stud, scale 1. Table instances are placed by script from the
  markers, not imported twelve times.
- `docs/prompts/` holds the briefs used for Blender agent jobs; reuse them as templates.
