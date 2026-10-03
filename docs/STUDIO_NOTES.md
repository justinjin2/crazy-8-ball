# Studio, Rojo, MCP, Lune and Blender notes

Read when something misbehaves. Everything here was learned the hard way.

## Rojo

- `rojo serve default.project.json` (port 34872) must be running; start it in the background
  from the agent session. After every Studio restart or Rojo restart the user must click
  Connect in the Rojo plugin. Confirm sync before playtesting with the MCP `script_grep` for a
  string you just added. Studio's Play copy is a snapshot: stop Play, let it sync, start Play.
  Files saved while a playtest runs reach the Edit scripts only after Stop (seen 2026-09-27:
  a Play started right after an edit ran the old code); check the Edit copy, then Play.
- **Start `rojo serve` outside the agent's sandbox** (Bash `dangerouslyDisableSandbox`), or
  have the designer run it in their own Terminal. Started inside the sandbox it serves its
  first snapshot but never sees a file change after that: Studio keeps old code, and
  reconnecting the plugin only reloads the stale snapshot (2026-10-01; found by comparing the
  Edit script's length with the file's). Check live sync by appending a comment to a file and
  reading it back from the Edit copy a few seconds later. A background command is stopped
  after 2 hours, so a long session needs it restarted (and the plugin reconnected).
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
- `screen_capture` does not draw BillboardGuis with `AlwaysOnTop` (2026-09-27: a red
  AlwaysOnTop probe was missing, the same without it showed), so world labels leave it off.
  The QA fixture's `spots = { [ballId] = { x, y } }` (inches; false sinks the ball) sets up
  a shot by hand, e.g. a combo into the +y side pocket: cue {0,6}, 5 {0,13}, 3 {0,19},
  angle pi/2, power 0.3. Time a capture about 1.1 s after the shot to catch a pocket effect.
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
- In the phone emulator (750x361) `user_mouse_input` lands a fixed (-62, -20) px from what it
  is given, and clicks by `instance_path` miss the same way, so they hit the wrong button or
  nothing (measured 2026-09-27 with a UserInputService.InputBegan log). Click a GUI centre by
  raw x/y = AbsolutePosition + AbsoluteSize / 2 + (62, 20), and confirm each click by its effect.
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
- In the PC window (no emulator, 2026-09-28) `user_mouse_input` takes GUI coordinates: the
  top bar's inset (58 px) is added to y, and `screen_capture` returns the viewport scaled up
  (1920x943 for a 1529x751 viewport). Click a point seen in a capture at
  (x / scale, y / scale - 58); read `workspace.CurrentCamera.ViewportSize` for the scale.
- `user_keyboard_input` cannot press Escape either (a CoreGui action); close menus with their
  close button or a click outside.
- `script_grep` finds nothing while a Play session runs; check Rojo's sync in Edit, or look
  for a startup print in the console.
- The economy's Studio test hooks (ServerStorage BindableFunctions, Studio only):
  `PlayerDataQA` (every save mutation, `read`, `snapshot`, `reset`), `ItemsQA` (`request`
  runs an ItemRequest as that player, `setSale`, `setRestricted`, `flush`/`refresh` the
  copies counter, `unbox`/`reyes`/`party` banners), `StoreQA` (`state`, `grant` a product with
  a purchase id, `setPass`, `buy`, `receipt`), `RewardsQA` (`state`, `request`, `credit`).
  A real 1v1 win for the settle: `PoolMatchQA:Invoke("fixture", 1, { phase = "Aiming",
  finalEight = true, brokeAgo = 120, calledPocket = 2 })`, then `Invoke("shot", 1, { angle =
  math.pi / 2, power = 0.35, epoch = snap.epoch, turnId = snap.turnId })`. To read what the
  client got, connect the remote in a Client `execute_luau` and store the payload as JSON in
  a LocalPlayer attribute.

## Uploading assets with Open Cloud (set up 2026-09-28)

`tools/roblox_upload.py` uploads models, images, audio and animations straight to Roblox
without Studio's import dialogs. It only uses the Python standard library.

- **Owner:** the place is group-owned (`game.CreatorType = Group`, `CreatorId = 675425213`),
  so every upload uses `--group-id 675425213`. The script requires an owner and has no default.
  If the owner is wrong, the upload still says "ok", but the game fails to load the asset with
  "User is not authorized to access Asset". Studio's `upload_image` uploads as user 544959133
  instead (see SurfaceAppearance facts).
- **Key:** it's a Creator Hub Open Cloud API key, created with the group selected, with Assets
  API Read and Write. It's stored in the macOS login Keychain under service `ROBLOX_API_KEY`.
  To store it, copy the key, then run `security add-generic-password -U -a "$USER" -s
  ROBLOX_API_KEY -w "$(pbpaste)"`. Don't use the interactive `-w` prompt: it cuts input at
  128 characters, and Roblox keys are longer, so the result is a 401. The script reads it with `security find-generic-password -s ROBLOX_API_KEY -w`. Never print the key,
  echo it, log it or write it to a file. To check that it exists, run
  `security find-generic-password -s ROBLOX_API_KEY >/dev/null 2>&1 && echo True || echo False`.
- **Run:** `python3 tools/roblox_upload.py --list files.txt --group-id 675425213 --dry-run`,
  then the same command without `--dry-run`. Other options are `--dir <folder>` (not
  recursive), `--type Model|Decal|Audio|Animation`, `--limit N`, and `--force-type Animation`
  for a `.rbxmx` KeyframeSequence.
- **File types:** `.fbx`, `.glb`, `.gltf` and `.rbxm` upload as Model. `.png`, `.jpg`, `.bmp`
  and `.tga` upload as Decal. `.mp3`, `.ogg`, `.wav` and `.flac` upload as Audio. `.obj` isn't
  accepted, so convert it to `.glb` in Blender first. Files over 20 MB are skipped.
- **Results:** they're written to `tools/upload_manifest.json`, keyed by absolute path. A rerun
  skips files that already succeeded and picks up "pending" ones, which are still in
  moderation. Every upload makes a new asset ID, because the API can't overwrite an old asset.
- **Rules:** ask the designer before any real upload. Never point the script at a big folder
  like Downloads. Audio has a monthly quota: 100 uploads on an ID-verified account, 10
  otherwise. Always dry-run first and ask before every audio upload.
- **Errors:** 401 means the key is wrong or expired, so the designer makes a new one and
  replaces it in the Keychain with the same `pbpaste` command. A stored length of exactly 128
  means the key was cut off. 403 means the key lacks Assets Read and Write for
  that owner, or was made under the user instead of the group.
- **Game passes and developer products** (2026-10-03): the same key also has game-pass and
  developer-product read and write. `tools/roblox_products.py` creates every row of
  `tools/products_spec.json` that the universe (10767330648) lacks by name, for sale with
  Managed Pricing off, and writes the ids to `tools/products_ids.json` for `Config.Products`.
  `--dry-run` first; `--only Key1,Key2` for a few. Roblox never deletes a product, so a mistake
  is fixed by renaming it or taking it off sale on the Creator Dashboard. `GetProductInfo` in
  Studio shows the price for the account asking (the designer's read 80% of the set price),
  while the Open Cloud config shows `defaultPriceInRobux`.
- **Images come back as a Decal ID, not an image ID** (tested 2026-09-28). The Decal ID fails
  in `ImageLabel.Image`. To get the image ID, run `InsertService:LoadAsset(decalId)` in Edit
  and read the `Decal.Texture` inside. Store it as `imageId` in the manifest entry. The first
  test was `guide_ring.png`: Decal 116046292783231, image 126657412569998, and the image
  preloaded with Success. It was then archived, because Decals can be archived:
  `POST https://apis.roblox.com/assets/v1/assets/{id}:archive` with body `{}`, and it can be
  undone with `:restore`.
- **Models from Blender (tested 2026-09-28)** with a `.glb` exported by headless Blender. The
  model uploaded "ok" and `LoadAsset` worked in the place.
  - **Scale is 1 Blender metre = 1 stud.** A 2 x 0.8 x 1.4 m planter came in at 2 x 0.8 x
    1.4 studs, so build in studs or scale on export.
  - **It splits by material:** one joined object with 3 materials became 3 MeshParts.
  - **Plain Principled colours are lost:** every part came in as grey Plastic with no texture.
    Bake colour into image textures, or set Color and Material in Studio after the load.
  - **Models can't be archived through the API** ("not an archivable asset type"). Remove a
    test model in Creator Hub by hand.
- **A `.glb` brings its image texture through (tested 2026-09-29, the ability pilot).** A
  headless-Blender `.glb` with one Principled material whose Base Colour is a packed PNG
  uploaded through Open Cloud as a Model; `LoadAsset` gave one MeshPart per object, each with
  `TextureID` set to a new image asset the upload made (one texture shared by every part),
  and the colours showed once the image loaded (`ContentProvider:PreloadAsync` -> Success; the
  first capture was grey only because it had not loaded yet). No SurfaceAppearance is made,
  and the part's `Color` does not tint a TextureID. So bake colour into the image, keep one
  material per look, and preload the TextureID before the moment it shows.
  - **Face direction matters:** Roblox draws only the front of a face. Faces built by script
    in the wrong winding showed from one side only (the pilot's arrowheads looked hollow).
    Run `bmesh.ops.recalc_face_normals` (or Mesh > Normals > Recalculate Outside) before export.
  - **Axes:** Blender +X arrives as Roblox -X, Blender +Y as Roblox +Z and Blender +Z (up) as
    Roblox +Y: the importer's half turn about the up axis on top of glTF's Y-up. A model
    lying in Blender's XY plane arrives flat. Place and turn loaded parts with CFrames in Luau.
  - **Texture alpha needs Transparency above 0** (2026-09-29, Ghost's wisps): a MeshPart at
    Transparency 0 draws opaque and ignores its TextureID's alpha (soft fades came out as solid
    grey sheets); at 0.02 the alpha fade shows.
- **A rerun uploads "pending" files again** (seen 2026-09-28): an upload still in moderation
  is recorded as pending, and the next run uploads it anew rather than polling it, so one
  image became three assets (aura_flame) and another two (field_lines). Poll a pending one
  instead: `roblox_upload.call(OPERATION_URL.format(operationId), key)` until `done`, then
  write its id into the manifest by hand. Note the duplicates in the manifest.
- **Check in Studio:** for a model, run `pcall(InsertService.LoadAsset, InsertService, id)` in
  Edit. For an image, preload an ImageLabel with the image ID through
  `ContentProvider:PreloadAsync` and expect `AssetFetchStatus.Success`.

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

## Loading a SurfaceAppearance before it is seen (tested 2026-10-01)

Found while making a switched cue appear already textured (`src/client/CueAssets.luau`):
- **`ContentProvider:PreloadAsync` does not load a SurfaceAppearance's maps.** On the template
  Model it loads only the mesh (one id, 0.02 s). On the map id strings every one reports
  `Failure` in 0.1 s. Decals with those ids report `Success`, but the cue still drew white when
  shown: the renderer fetches its own form of the maps.
- **The renderer fetches the maps only when the SurfaceAppearance is drawn.** A part with
  Transparency 1, or one in ReplicatedStorage, fetches nothing. A copy 0.99 see-through in front
  of the camera does fetch them, and it is never seen. It waits about 1 s before asking.
- **`ContentProvider:GetAssetFetchStatus(id)` follows the renderer's fetch** (None, Loading,
  Success), so it is the ready signal. But a texture Roblox loads from its own disk cache never
  changes from None. In Studio the statuses also carry over between Play sessions.
- **A failed download is remembered.** The console shows "Unable to load ... (HttpError:
  NetFail)" and "Unable to generate ... SurfaceAppearance ... Change a TextureId property to
  retry". After that a new SurfaceAppearance with the same id stays blank, and the status stays
  `Failure`. Preloading the id as a Decal's image clears it (`Success`), and a fresh copy then
  loads. Frostbite's maps hit NetFail twice in Studio on 2026-10-01.
- `CaptureService` screenshots cannot be read back (`CreateEditableImageAsync` refuses
  temporary ids), so "did it draw white" can only be checked by eye. Studio's screen capture
  arrives about 0.5 s after the call.

## Part materials are mapped in world space (tested 2026-09-26)

Two Brick Parts with different sizes and centres (one moved 0.37 studs sideways, one 5.3
longer) meeting at a seam show one continuous pattern across it: a Part's material (and a
MaterialVariant) is projected from world coordinates, not from the part. So a tiled floor
can be any number of Parts with one MaterialVariant and its grid lines up everywhere; the
rooftop floor uses that (MapBuilder, Config.Map.Floor) instead of a mesh.

## UI facts (tested 2026-09-25)

- A ScreenGui with `ScreenInsets = TopbarSafeInsets` covers exactly the free part of Roblox's
  top bar; its AbsolutePosition and AbsoluteSize share the coordinates of every other
  ScreenGui (in the phone emulator, 750x361: x 208 to 750, 58 high, y -58). MatchHUD measures
  its bar's room from one. An unparented ScreenGui still reports a size, so check the parent.
- The Studio device emulator (a phone) applies in Edit mode too: the viewport reports the
  phone's size, and Play shows the touch thumbstick and jump button. Handy for phone layout.
- A BillboardGui with AlwaysOnTop did not appear in `screen_capture` (2026-09-26); the table
  sign stays AlwaysOnTop = false.

- **`TextScaled` and `TextWrapped` are coupled** (tested 2026-09-27): setting
  `TextWrapped = false` turns `TextScaled` off, and setting `TextScaled = true` turns
  `TextWrapped` back on. A kit text (`HudParts.text`, TextScaled) given `TextWrapped = false`
  then draws at its fixed `TextSize` and no longer shrinks to its box. For text that must
  scale with its box (the nameplates), leave TextWrapped alone.
- **A BillboardGui's pixel part barely shows** (seen 2026-09-27, Retina Mac): a nameplate sized
  `{0.75 studs + 18 px}` drew at about the size of its 0.75 studs alone at 20 studs, and its
  AbsoluteSize did not match what was drawn. Size world labels in studs and check them in a
  capture (with AlwaysOnTop off), not from AbsoluteSize.
- **A ViewportFrame under a rotated frame is neither rotated nor clipped** (tested 2026-09-28):
  in the ult cutscene's -8 degree panel, the avatar drew upright and spilled past the tilted
  edges (ClipsDescendants does not clip rotated frames either). Keep a viewport in an upright
  frame and fit it inside the tilted shape by hand (UltCutscene's avatar window).
- **Catching a short animation in `screen_capture`**: the capture lands a second or two after
  it is called, so fire the event from the same `execute_luau` call (the arm, the shot) and
  call `screen_capture` in the same batch; a `task.delay` in the server call nudges it later.
  To hold the camera on a spot for a look check, set a CFrame from the Client datamodel both on
  `Camera:GetPropertyChangedSignal("CFrame")` and on `RunService.Heartbeat` (the aim camera
  beat a RenderStep binding); disconnect both and set CameraType back to Custom after.
  A RenderStepped watcher in the Client datamodel that logs when named instances appear
  (`MagnetFx_*`, `PocketRing*`) proves an effect ran even when a capture misses it.
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
- **A kit text's minimum is in screen pixels** (tested 2026-09-28): a UITextSizeConstraint's
  MinTextSize holds on screen even inside a UIScale below 1, and even with TextScaled off
  (a probe at UIScale 0.5: TextSize 20 drew at 10 px bare, at 14 px with a MinTextSize 14
  constraint). So a screen laid out at a natural size and scaled down (the result screen on
  a phone) draws its small words bigger than their boxes: pills overlap and one line wraps.
  Measure words at the size they are drawn (`drawnPx` in ResultScreen).

## Sky faces (tested 2026-09-25)

Tested with six labelled faces and Edit-mode `screen_capture`
looking along each axis. Nothing is mirrored:
- SkyboxFt shows when looking towards -Z, SkyboxBk towards +Z, SkyboxRt towards -X and
  SkyboxLf towards +X. All four are upright.
- SkyboxUp: looking up, the image top points to +X and the image right to -Z.
- SkyboxDn: looking down, the image top points to -X and the image right to -Z.

When testing a Sky, move the place's own Sky to ServerStorage first, because two Skies in
Lighting clash. Put it back afterwards. (`MapLighting.preview` updates the place's own Sky
instead of adding one, and removes extras.)

## Water and distance at low quality (tested 2026-09-26)

Tested with a sand slope and a dark seabed under Terrain water, at Edit quality 21 and 4
(`settings().Rendering.EditQualityLevel`; Automatic by default, put it back after).
- Parts under Terrain water show through only at high quality. At low quality the water is
  opaque, so shallows have to be painted on a thin band over the water, not seen through it.
  A dark seabed does not deepen the blue.
- Roblox's default WaterReflectance of 1 mirrors the pale sky, so the far sea reads almost as
  pale as the sky. At 0.3, with a clear blue colour, it reads the art's bright blue.
- At low quality Roblox draws Terrain water only near the camera, in blocky patches, and
  drops distant parts: the islands 3,500 studs and more away vanish. Only the skybox is
  always drawn. The sky's lower half is therefore painted the water's rendered blue, and
  anything that must be seen far away on a phone belongs in the skybox.
- **Draw distance by quality level** (tested 2026-09-26 with coloured test blocks at 400, 700,
  1,000, 2,000 and 4,000 studs):
  - At levels 1 to 10, none of them draws, not even the 250-stud block 400 studs out. The
    near world, the block city and the islands all vanish; only the skybox, the Terrain
    water near the camera and the rooftop itself remain.
  - From about level 12 the near city starts to draw. At level 16 and above every block
    draws, out to 4,000 studs.
  - Phones usually run at low levels, so on most phones the backdrop is the skybox alone.
    Anything the art needs on the horizon (the skyline, the islands) has to be painted into
    the sky as well as built.
- Distant Terrain water streams in over about 20 seconds after Play starts. Capture far views
  only after that.
- Roblox renders a skybox paler and greyer than painted: #3894FC showed as #56A9DD. Paint
  sky colours deeper and more saturated than the target.

## Mesh LOD warps boxy meshes (tested 2026-09-26)

- A MeshPart at RenderFidelity **Performance** (and **Automatic** beyond a few hundred studs)
  is drawn from a decimated mesh. The decimation crumples box buildings into slanted shards
  and smears their UVs; a small camera move flips the level, so a tower looks fine from one
  spot and broken from the next. **Precise** always draws the real mesh. The map's backdrop
  uses Precise (`Config.Map.Near/Backdrop` rows' `Fidelity`).
- RenderFidelity can be written in Edit through the MCP (plugin security), not by a game
  script.

## Lighting in Edit and in Play (tested 2026-09-26)

- **No Technology setting.** This place is on Roblox's unified lighting: Lighting has no
  `Technology` property (its `RBX_OriginalTechnologyOnFileLoad` attribute says it was
  ShadowMap), only `LightingStyle` (Soft) and `PrioritizeLightingQuality`. The brief's "set
  Future" step no longer applies.
- **Tune light in Play, not in the Edit preview.** Edit's viewport draws no DepthOfField at
  all, and draws Atmosphere haze far thinner: Haze 0.3 at Density 0.1 looked fine in Edit
  and fogged the whole 3D city and sea into one flat colour in Play.
- **A LocalScript may write SurfaceAppearance `EmissiveStrength`, `EmissiveTint` and
  `Color`** at runtime (the day cycle does, for the glowing tables and windows).
  `EmissiveMaskContent` is set once in Edit (`Content.fromUri`).
- `MapLighting.preview` lights the place in Edit (Day, Sunset or a blend); in Play every
  client's `DayCycle` runs the cycle. A client frozen at a blend for captures:
  `MapLighting.apply(LightCycle.state(b, Config.Lighting), MapLighting.collect(Config.Map), nil)`
  holds while the cycle holds.
- Studio's chat box has CoreGui focus, so the MCP's keyboard input cannot type into it, and
  `TextChannel:SendAsync("/day")` from a test script hangs. Test the commands' work by
  calling `DevCommands.toward("Day")` in the Server datamodel.

## What the lowest graphics levels draw (tested 2026-09-26)

At Edit quality 1, Roblox draws a part only if some point of its bounding box is within about
300 studs of the camera: long test walls whose nearest point was 283 studs away drew in full out
to 1,800 studs, and ones whose nearest point was 356 studs or more did not draw at all. So a
huge slab that touches the roof always draws, and a backdrop chunk draws only if its bounds
reach near the camera. The rooftop's mid city chunks (1,200-stud cells) that touch the tower
draw; the outer ring does not. (A zoom cap was tried and dropped; the sky's painted ground, grey
streets and pale blocks, now covers what the low levels leave undrawn.)

## Importing during Play, and particles at low graphics (2026-09-26)

- A 3D import made while Studio is in Play lands in the play session and is lost when Play
  stops. Stop first, then import (and only then run the prepare functions in Edit).
- Roblox shows fewer particles at low graphics levels and on phones: an effect built from many
  short-lived particles thins out to almost nothing. Few long-lived particles hold up better.
  (The fire pit ended up on Roblox's own Fire, the designer's choice.)

## The 3D Importer and scripts right after an import (2026-09-26)

The importer can still be adding the model when the user says "imported". A setup script run
straight away may miss it: `prepareNear` reported the old triangle count and no "Replaced the
previous import" line. Run it again, or check that the fresh model is in Workspace first. `SurfaceAppearance` has `EmissiveMaskContent`,
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

## The global queue in Studio (2026-09-28)

- **TeleportService does not work in Studio** (no ReserveServer, no TeleportAsync). The code
  knows: a match found in Studio logs "GQ Studio cannot teleport" and the player gets "Teleports
  only work in the published game." The real teleport can only be checked in the published
  game with two accounts (MULTIPLAYER_TESTING.md, Global queue).
- **MemoryStore works in Studio** with API access, and Roblox keeps Studio's memory stores
  apart from the live game's, so testing never touches the real queue.
- `ServerStorage.GlobalQueueQA` (Server datamodel): `Invoke("inject", mode, {userIds}, rating)`
  posts a search from a pretend other server and keeps it alive; `"status"`, `"read"`,
  `"record"`, `"clear"`. Join Global Queue with the real player, then inject: they match in
  about a second.
- **An arena in Studio**: in Edit mode set `game.ServerStorage:SetAttribute("StudioArena", 1)`
  (the team size), then Play: the rooftop at day with one blue table in the middle, the
  player stood at it and seated, and a pretend opponent (-1) fills the other side 1.5 s later.
  `ServerStorage.ArenaQA`: `Invoke("vote", -1, "Rematch")` votes for the pretend player;
  PoolMatchQA works on table 1 (its "action" for the pretend player's Surrender). **Clear the
  attribute after** (`SetAttribute("StudioArena", nil)`): Team Create would save it.
- The rematch window is 20 s and MCP round trips take seconds: put the whole setup (fixture,
  concede) in one `execute_luau` and click right after.
- `user_keyboard_input` sends ButtonA/ButtonY as keyboard input: `GetLastInputType` reads
  Keyboard and a selected button is NOT pressed by it (the host card's Play solo is not
  either), and ButtonB is refused. A gamepad's A on a selected button needs a real pad.
- **A new Rojo mapping** (a new service folder in `default.project.json`, like
  ReplicatedFirst for `src/first`) is only picked up after `rojo serve` restarts and the
  plugin reconnects.

## The shared cue mesh in Studio (2026-09-29)

- **glb to MeshPart:** `InsertService:LoadAsset(<model asset id>)` in Edit gives a Model with
  one MeshPart per material (the cue has one). The uploaded model's MeshId is the "mesh" id in
  `tools/upload_manifest.json` (Cue.glb: model 112855847049580, mesh 113499415983055).
- **The importer turns a glb 180 degrees about Y and centres the part on its bounds.** A cue
  built tip at the origin along Blender -Y lands with the tip at local +Z 3.5 of a
  0.2 x 0.2 x 7 part, and the UV seam (Blender -Z) stays at local -Y. So the template's
  `PivotOffset` is `CFrame.new(0, 0, 3.5) * CFrame.Angles(0, math.pi, 0)`: the pivot at the
  tip, +Z toward the butt, the frame CueStickBuilder uses.
- **A SurfaceAppearance's maps are Edit-only.** ColorMap and the others can be set by a plugin
  (the MCP) in Edit mode but not by a game script, so every skin is a template built in Edit
  (`ReplicatedStorage.CueSkins.<cue id>`). A game script may `:Clone()` a whole
  SurfaceAppearance and parent it, which is how a second mesh skin will swap onto a stick.
- **Rojo keeps `CueSkins`.** The `ReplicatedStorage` node in `default.project.json` has no
  `$path`, so children made in Studio survive a sync (checked with the plugin connected).
  Anything Rojo does not know about must still be saved with the place.
- **Welding a cosmetic to a character** (BackCue): WeldConstraints to the torso, the parts
  unanchored, Massless, CanCollide/CanQuery/CanTouch false. Walking, jumping and the camera were
  unchanged. Never set CFrame on a part that is welded to a character (it drags the body):
  detach, move, weld again.

## The cue skins import (2026-10-01)

- **Edit mode caches a module's first require for the session.** After Rojo changes a module,
  `require` in Edit (the MCP, the command bar) still returns the old one. Require a fresh
  clone parented next to it (`tools/build_cue_templates.luau` does: `fresh()`), and destroy the
  clones afterwards.
- **No SurfaceAppearance from a game script.** `AssetService:CreateSurfaceAppearance` does not
  exist, and a script cannot set the map properties; templates are built in Edit and saved in
  the place (`ReplicatedStorage.CueSkins`, `ReplicatedStorage.CuePieces`). A plugin sets the
  maps with `Content.fromUri("rbxassetid://...")` on `ColorMapContent` and friends.
- **A skinned glb survives Open Cloud.** Uploaded as a Model and loaded with
  `InsertService:LoadAsset`, it comes back as a Model holding a `RootPart` with the Bones, the
  skinned MeshParts joined by Motor6Ds, an `InitialPoses` folder and an AnimationController
  (the template builder removes the last two). Names and sizes are kept. The 180 degree turn
  about Y applies to the rig too, so a bone's position reads with X negated against
  Blender's (CuePiece welds the RootPart at FLIP). **Bones come back turned as well** (the
  dragon's top bone is half a turn about Y), so a Bone.Transform must be built in the bone's
  own rest frame read from the template (`B^-1 * J * B`), never assuming square bones; and
  `Bone.WorldPosition` leaves out `Transform` (read `TransformedWorldCFrame` to see a pose).
- **A rigid glb keeps one MeshPart per named object**, so a whole piece folder uploads as one
  `<piece>_parts.glb` (`tools/cue_pieces_glb.py`) and its parts are found by name.
- **Open Cloud does not take `.obj`**; convert to glb first.
- **Uploads take about 8 seconds each.** Hundreds go faster as three workers, each with its own
  list (`--list`) and manifest (`--manifest`), run with `python3 -u` so their logs stream;
  merge the manifests into `tools/upload_manifest.json` afterwards. Then
  `tools/manifest_image_ids.py emit` / `apply` turns the Decal ids into image ids, about 100 a
  batch through `execute_luau` in Edit.

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

## Abilities: Blender to Roblox, input in the emulator, screen layers (2026-09-29)

Lessons from building the 13 abilities (docs/prompts/ABILITIES_PROMPT.md). The Blender-to-Roblox
basics (glb textures, face direction, axes, texture alpha) are under "Uploading assets" above.

- **Load models at runtime, not into the place.** `server/AbilityAssets` loads every id in
  `Config.Ults.Assets` once per server through `InsertService:LoadAsset` (scripts stripped)
  into `ReplicatedStorage.AbilityAssets`; looks clone from there. Nothing to save in the place.
- **An inverted-hull outline draws solid black.** Roblox ignores a flipped copy's winding, so
  the classic outline trick fills the whole shape. Use a `Highlight` (OutlineOnly) instead.
- **One-sided faces vanish from the other side.** A ribbon whose faces point down is culled
  from the overhead camera; build flat ribbons two-sided (a back copy) in Blender.
- **Neon lifts colours unevenly**: a configured gold drew lemon yellow and a violet read pale.
  Pick Neon colours in Studio, not Blender. Additive orange over the green cloth reads yellow;
  a baked light blue washes to near white on the lit cloth (flat, deeper colours instead).
- **Animation without Animation assets.** Nothing was uploaded as an Animation: the tiger is
  rigid parts turned round joint markers (empty objects exported with the model) by CFrames
  every frame, which needs no rig, no upload permission and follows `/slowmo` and `/hold`.
- **Detail below a pixel is lost.** From the shooting camera on a phone a ball is 20 to 55 px;
  fine texture (halftone, forks, thin bolts) disappears. Make shapes fat and high-contrast.
- **Full-screen layers need `ScreenInsets.None`.** A ScreenGui's default inset is the device
  safe area, so on a phone a "full-screen" frame stops short of the edges (Eagle's Eye's
  vignette drew a hard box). Screen effects set `ScreenInsets = Enum.ScreenInsets.None`.
- **Touch in the phone emulator through MCP:** `user_mouse_input` in the emulator arrives as
  touch. An `InputObject.Position` is in GUI space (below the top bar inset, 58 px there), and
  the MCP tool's raw coordinates are offset from GUI space (in the 750 x 361 emulator, GUI
  position + (62, 20)). Read a button's `AbsolutePosition` and add the offset, or hit it by
  `instance_path` on PC.
- **A gamepad cannot be driven through MCP.** `user_keyboard_input`'s pad keys arrive as
  Keyboard with no gamepad connected, so a pad's picks and aim stay a hand check.
- **Player attributes set from `execute_luau` on the client do not reach the game's copy of
  a module**; the dev commands' state lives in `workspace` attributes (`ReplaySlowmo_<id>`,
  `ReplayHold_<id>`) so a test can set them from either side.
- **Studio caps an unfocused window at 15 fps** (66.7 ms a frame): a frame time measured
  while the MCP drives Studio reads as the cap; look for spikes above it, not the mean.
- **Sound sheets were not needed**: every ability sound is a public library clip played by id
  (`SoundSheet.library`), trimmed with `StartOffset` and pitched at runtime. The sheet player
  is ready for uploaded sheets (`Config.Ults.Assets.Sheets`).
