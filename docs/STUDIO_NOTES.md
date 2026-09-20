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

## Testing by hand (the two checks an agent cannot do)

Every milestone has to be checked on phone, PC and gamepad, and 1.5 adds a two-player check.
Neither of these can be driven from an agent session, so they are written out here.

**Two players in one server.** Studio's Test tab, the "Clients and Servers" group: set
**Players** to 2, then click **Start**. Studio opens one server window and two client
windows. In client A walk onto a pad and take a shot; in client B watch that table. Then put
B on a different table's pad and have both shoot. What to look for:

- both clients see the SAME balls end up in the same places (the server is the authority)
- the watching client sees the shooter's cue turn while they aim
- a pad turns green for both clients when either one steps on it
- walking a client across a pad on the way somewhere else does NOT seat them
- the console has no `replay drifted from the server` warning: that line means a client's
  replay of a shot did not match the server's run of it, and is the thing to report

Stop with the **Cleanup** button in the same group, not by closing the windows.

**Gamepad.** Plug in any controller before pressing Play; Roblox picks up Xbox and
PlayStation pads without setup. `UserInputService.GamepadEnabled` should read true. Walk to a
pad, then check: left stick turns the aim (and keeps turning while held, rather than only
while it moves), D-pad left/right nudges it a hair, right stick zooms, holding and releasing
the right trigger shoots with the power it was pulled to, ButtonA does the same on a pad with
digital triggers, and B leaves the table. The bindings are in `Config.Input.Gamepad`.

Studio's device emulator has a gamepad mode as a fallback, but a real pad is the honest test.

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
