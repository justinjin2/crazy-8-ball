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

- Things scripts cannot create live in the place: `ServerStorage.PoolTable` and
  `ServerStorage.TableLooks` (the table template and its looks, below; the old
  `PoolTableModel` stays as the rollback until sign-off), `ServerStorage.BallMesh`, the
  `PoolClothBlue` MaterialVariant. MeshId, SurfaceAppearance maps, MaterialVariant maps
  and CollisionFidelity are plugin-only writes: set them in Edit mode and save. `TextureID` on
  a MeshPart is scriptable, which is how per-ball textures work at runtime.
- The user must save (`place/8ball.rbxl`) and publish after any Edit-mode change.

### Preparing an imported table

After importing `assets/table/PoolTable.fbx` (3D Importer, Scale Unit: Stud, scale 1, model
named `PoolTable`), or after changing any map id or look in `Config.TableModel`, run this in
Edit mode from the command bar or `execute_luau`:

```lua
print(require(game.ReplicatedStorage.Shared.TableBuilder).prepareImport(require(game.ReplicatedStorage.Shared.Config:Clone()).TableModel))
```

- It is safe to run twice. It moves the model to ServerStorage, flattens nested parts, rebuilds
  the pivot (cloth centre on the floor, +X to the LogoPlate, undoing the importer's half
  turn), sets collision, shadows and LOD, and rebuilds `ServerStorage.TableLooks`. The
  printed report ends with any `PROBLEM:` lines from `TableBuilder.checkTemplate`.
- The `Config:Clone()` is there because Edit-mode requires are cached: it reads the Config on
  disk now. TableBuilder itself is still the cached copy, so after changing TableBuilder
  restart Studio before running it.

## Studio MCP

- Every call needs `studio_id` from `list_roblox_studios`.
- `screen_capture` works in Play mode now (it captured the game view and the GUI on
  2026-09-25; it used to come back black). Pair it with the QA fixture
  (`ServerStorage.PoolMatchQA`, Server datamodel) to put a match in any phase first. A
  forced "Foul" needs the fixture's `nextTeam` (set since 2026-09-25) or the engine errors
  every frame when the foul ends.
- Edit-mode previews of the screens: clone `StarterPlayerScripts.Client` into ServerStorage
  and require the clone (the originals stay cached), copy a fresh `require` of a cloned
  `Config` and `Strings` into the cached tables, build into a ScreenGui in StarterGui (a
  Frame of 844x390 or 667x375 stands in for a phone), capture, then DELETE the preview:
  anything left in StarterGui is copied into the game at the next Play. MatchHUD and
  QueueMenu take user id 0 when there is no LocalPlayer, for these previews.
- `user_keyboard_input` can press ButtonY but not ButtonB ("permanently bound to a CoreGUI
  core action").
- Earlier previews in Edit mode: build the table with
  `TableBuilder.build(workspace)`, add preview parts in a `CameraPreview` folder, set the
  camera, capture, then destroy the preview and the table. Beams do not render in captures.
- Edit-mode `require` results are cached for the Studio session: when Config changed since
  the last Edit-mode require, patch the cached table in the preview script.
- `execute_luau` on the Edit datamodel is unavailable during Play. Numeric checks in Play go
  through the Client datamodel (for example `WorldToViewportPoint`).
- `upload_image` needs http URLs: `python3 -m http.server 8765 --bind 127.0.0.1 --directory
  assets`, batches of four or Studio disconnects. `generate_material` needs `materialId`.
  Images uploaded this way render at 1024 at most (see SurfaceAppearance facts).
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
- Studio play-solo frame rate is not a performance measure: it can read 15 fps on a light scene
  (the window throttles). Measure on a real phone.
- The shooter's own body is see-through while aiming, so judge a pose from outside: in a Client
  `execute_luau`, connect RenderStepped and PreRender (connected after the game's, so they run
  last) to set `workspace.CurrentCamera.CFrame` and each character part's
  `LocalTransparencyModifier` to 0 (1 for accessories, to see the body under a costume).
  `BindToRenderStep` at any priority loses to the game's camera. Disconnect when done.
- The controller's ButtonA through `user_keyboard_input` fires a shot (hold to ramp the power);
  a mouse drag on the power bar near the top of the screen hits Roblox's CoreGui.

## SurfaceAppearance facts (tested 2026-09-24)

These come from the table remake's de-risk tests. They ran in Edit mode through `execute_luau`:
- EditableMesh quads were turned into MeshParts with
  `AssetService:CreateMeshPartAsync(Content.fromObject(em))`.
- EditableImages were set through `SurfaceAppearance.ColorMapContent` and the other
  `*MapContent` properties.
- Uploaded test images were used as well.

What was found:
- **UVs outside 0..1 repeat.** This holds for EditableImages and for uploaded images. A quad
  with UVs 0..4 shows the texture 4x4 times. A seamless tile on continuous UVs shows no seams at
  any distance. So a tiling texture needs no cuts in the mesh.
- **`SurfaceAppearance.Color` multiplies the ColorMap.** A 0.94 grey map tinted #01A9F7 matches
  a SmoothPlastic part of that colour. The tint is script-writable.
- **Vertex colours are ignored once a SurfaceAppearance is present.** They show only on a bare
  MeshPart. Shading on a SurfaceAppearance mesh has to come from its maps or from an overlay.
- **Normal maps are OpenGL (+Y toward the image top), and UV (0,0) is the image's top-left
  corner.** A painted dome shaded exactly like a real bump.
- **A missing Metalness map means non-metal.** A missing Roughness map looks fairly matte,
  rougher than an explicit 0.5.
- **Chrome** (albedo 214,209,203, metalness 1) reads as polished chrome under this place's Sky at
  roughness 0.08 to 0.18. At 0.3 it is softer.
- **Transparent overlays work.** `AlphaMode.Transparency` on a quad 0.002 studs above another
  surface shows no z-fighting. Very faint alpha (0.04 to 0.08) gets a fine even dither grain from
  the renderer; alpha 0.2 and up is smooth.
- **Images uploaded from Studio render at 1024.**
  - `upload_image` accepted 2048 and 4096 PNGs.
  - Close up, a 1-pixel checker in the 2048 image shows a resampling beat pattern, while the same
    checker at 1024 is crisp, even at QualityLevel 21 after waiting.
  - An EditableImage read-back cannot tell you the stored size: EditableImages cap at 1024.
  - DevForum reports say only Creator Dashboard uploads keep 4K.
  - So design every map to look right at 1024.
- **Studio uploads belong to the user who uploads them** (user 544959133), not the group that owns
  the game. The current table's maps and meshes are owned the same way and work in play.

## UI facts (tested 2026-09-25)

- A ScreenGui with `ScreenInsets = TopbarSafeInsets` covers exactly the free part of Roblox's
  top bar; its AbsolutePosition and AbsoluteSize share the coordinates of every other
  ScreenGui (in the phone emulator, 750x361: x 208 to 750, 58 high, y -58). MatchHUD measures
  its bar's room from one. An unparented ScreenGui still reports a size, so check the parent.
- The Studio device emulator (a phone) applies in Edit mode too: the viewport reports the
  phone's size, and Play shows the touch thumbstick and jump button. Handy for phone layout.
- A BillboardGui with AlwaysOnTop did not appear in `screen_capture` (2026-09-26); the table
  sign stays AlwaysOnTop = false.

- In a Sibling-ZIndex ScreenGui, ZIndex -1 and 0 draw under default (1) siblings: the kit's
  card shadow and fill rely on it.
- A TextLabel or TextButton can carry two UIStrokes at once: one Contextual (the text's
  outline) and one Border (the box's outline).
- A UIGradient on a TextButton also tints its own text, so candy buttons draw their face as a
  child frame and their words as a separate label.
- AbsoluteSize includes every UIScale above an object, but offsets inside it are scaled again:
  lay out from AbsoluteSize divided by those scales (HudParts does).
- ClipsDescendants clips to the rectangle, not the UICorner: a round clip needs a UICorner on
  the clipped image itself (the card pattern) or a pre-clipped image (the ball's stripe band).
- Headless Chrome renders the SVG icons in about a second, but hangs for minutes after the
  screenshot when given `--user-data-dir`; `tools/gen_ui_art.py` leaves it out.

## Sky faces (tested 2026-09-25)

Tested with six labelled faces and Edit-mode `screen_capture`
looking along each axis. Nothing is mirrored:
- SkyboxFt shows when looking towards -Z, SkyboxBk towards +Z, SkyboxRt towards -X and
  SkyboxLf towards +X. All four are upright.
- SkyboxUp: looking up, the image top points to +X and the image right to -Z.
- SkyboxDn: looking down, the image top points to -X and the image right to -Z.

When testing a Sky, move the place's own Sky to ServerStorage first, because two Skies in
Lighting clash. Put it back afterwards. `SurfaceAppearance` has `EmissiveMaskContent`,
`EmissiveStrength` and `EmissiveTint`, useful for lit windows.

## Testing by hand (the two checks an agent cannot do)

Every milestone has to be checked on phone, PC and gamepad, and 1.5 adds a two-player check.
Neither of these can be driven from an agent session, so they are written out here.

**Two players in one server.** Studio's Test tab, the "Clients and Servers" group: set
**Players** to 2, then click **Start**. Studio opens one server window and two client
windows. In client A step into a table's box and play solo; in client B watch that table.
Then put B in a different table's box and have both shoot. What to look for:

- both clients see the SAME balls end up in the same places (the server is the authority)
- the watching client sees the shooter's cue turn while they aim
- a box turns green for both clients when either one steps in
- walking a client across a box on the way somewhere else does NOT seat them
- the console has no `replay drifted from the server` warning: that line means a client's
  replay of a shot did not match the server's run of it, and is the thing to report

Stop with the **Cleanup** button in the same group, not by closing the windows.

**Gamepad.** Plug in any controller before pressing Play; Roblox picks up Xbox and
PlayStation pads without setup. `UserInputService.GamepadEnabled` should read true. Walk into
a box, press Y to put the selection on the queue menu (B takes it off), start a solo game,
then check: left stick turns the aim (and keeps turning while held, rather than only
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
- The package in `assets/table` has rebuild scripts and a `Readme.md` with import steps.
  Import through the 3D Importer with Scale Unit: Stud, scale 1. Table instances are placed
  by script (Config.Hub.Tables), not imported once per table.
- `docs/prompts/` holds the briefs used for Blender agent jobs; reuse them as templates.

## Audio

**Measuring how loud a clip actually is.** Roblox gives no way to read an asset's level from
a `Sound`, but the newer audio graph does: wire `AudioPlayer -> AudioAnalyzer` and read
`PeakLevel` and `RmsLevel` while it plays. Nothing else is needed and nothing else is
possible - an `AudioAnalyzer` is a TERMINAL tap with no output pins, which is exactly why
this is silent: no path to the speakers can be built past it. Wiring one onward to a fader
or a device output logs "Invalid Wire Connection: AudioAnalyzer has no output pins" and the
extra wires are ignored. `tools/measure_audio.luau` does this for every clip in Config;
paste it into the command bar in Edit mode. It is reproducible to four decimal places
between runs.

**`SoundService.DopplerScale` cannot actually be set to zero.** Writing 0 reads back as
0.001. That is a thousandth of normal and inaudible, so it is fine, but do not treat the
read-back as a failed write.

**The enum is `Enum.RollOffMode`, not `Enum.SoundRollOffMode`.** Selene catches the wrong one;
luau-lsp does not.

**Config cannot name `Enum`.** `src/shared/Config.luau` is loaded by the Lune tests, whose
harness forbids Roblox globals, so anything enum-shaped is stored as a string and mapped on
the Roblox side (see `Config.Audio.RollOffMode` and how `Audio.luau` reads it).

**`Sound:Play()` does not rewind.** It restores whatever `TimePosition` a script last wrote,
so a pooled Sound plays from the middle forever once anything seeks it. `Sound:Stop()` is
what resets it to 0. Relatedly, `Ended` never fires for a looped Sound or when `Stop()` is
called, so a continuous loop must be driven by polling `TimePosition`, never by `Ended`.

**Mobile can go fully silent after the player switches apps and comes back.** This is a known
Roblox client bug with no in-experience fix. If a phone playtest comes back with no sound,
check whether the app was backgrounded before assuming the audio code broke; verify from a
cold launch.

**`execute_luau` gets its OWN copy of every ModuleScript.** A `require` from the MCP command
path does not share state with the running game: `require(PlayerScripts.Client.Camera)` there
returns a fresh instance whose upvalues are at their defaults. This costs hours if it is not
known, because the module answers questions about itself perfectly plausibly - a Camera that
reports `isLocked() == false` and a zoom of the default while the real camera, driven by the
game's own copy, is locked and somewhere else entirely. Calling a setter on it changes
nothing on screen. Drive the game through real INPUT (`user_mouse_input`) and measure the
live `Workspace.CurrentCamera`, never the module's own view of itself.

**MCP round trips take several seconds.** A trace armed by one `execute_luau` call and
triggered by the next can easily expire before the input lands: a 6-second window missed a
scroll entirely and read as "nothing happened". Arm windows of 20 seconds or more for
anything that needs a separate call to trigger it, or wait for the result inside the same
script.
