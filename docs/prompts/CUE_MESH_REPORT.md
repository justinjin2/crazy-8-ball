# Cue mesh: the report (2026-09-29, branch `cue-mesh`)

## Look at these first

1. **Play in Studio.** Equip **Classic** (Inventory). It is on your back when you walk round, and
   in your hands at a table. Then equip any other cue: it has its coloured bands, on your
   back too.
2. `assets/cue/renders/classic.png`: Classic from every side, with close-ups of the tip, the
   joint and the butt.
3. `assets/cue/template/sheet.png`: the paint kit, showing where each picture goes on the cue.
   `assets/cue/template/CHATGPT.md` is the how-to for your first ChatGPT skin.

## Save and publish (please do this once)

These were added in **Edit mode** and live only in the place file, not in git:

- `ReplicatedStorage > CueSkins` (a Folder), holding the Model **`Classic`**:
  - its MeshPart **`Cue`** (the uploaded mesh, 0.2 x 0.2 x 7 studs, anchored, no collide,
    query or touch, massless, casts a shadow, pivot at the tip)
  - with a **SurfaceAppearance** holding Classic's four maps.

Nothing else in the place was changed. The test parts used on the way were deleted.
**File > Save to File As… > `place/8ball.rbxl`, then File > Publish to Roblox.** Without the
publish, the live game draws Classic with its bands (one warning, no error).

## What was built

- **One cue mesh for every skin** (`assets/cue/`): built headlessly in Blender from the game's
  own cue outline, so it is exactly the shape of the band cues. It has a rounded tip, a
  ferrule, a tapered shaft, a silver joint, the forearm, a ring, a wrap with a small step, the
  sleeve and a rubber bumper.
  - **3,456 triangles** (budget 4,000).
  - One 1024 atlas: about **567 pixels per stud on the handle** and **363 on the shaft**. The
    handle, which you look at most, gets 78% of the picture.
- **The paint kit:** five flat pictures (shaft tile, shaft top, forearm, butt, butt end cap).
  Each has a grey `_input` for ChatGPT, a labelled `_guide` for you and a `_test` checker.
  `CueTextures.py` turns five painted pictures into the game's maps. The test render proves
  nothing lands stretched, mirrored or upside down.
- **Classic**, the first skin, drawn by script: maple shaft, rosewood forearm, black linen
  wrap, silver rings, glossy black sleeve, blue tip.
- **In the game:** Classic is drawn from the mesh in your hands, in other players' hands and
  in the Index viewer. The other 47 cues keep their bands.
- **The cue on the back:** every player nearby carries their equipped cue on their back, tip
  over the left shoulder. It vanishes the same frame the cue appears in their hands and comes
  back when they put it down. On R15, R6, tall and small bodies it clears the head and never
  touches the floor. Sitting down, it tilts further to clear the seat. Welded and weightless,
  it never changes how you walk, jump or how the camera behaves.

## What was verified

- Lint clean; **739 tests pass**.
- The mesh passes every scripted check: the outline, closed and outward-facing, under budget,
  no UV overlap or mirroring, stretch (mean at most 1.029), and the glb round trip.
- In Studio, each check was screenshotted:
  - Classic in hand (aim view and close view).
  - A band cue unchanged.
  - A watched stick painted Classic.
  - The Index.
  - The back cue from behind, the front and the side on four bodies.
  - The hand/back swap over 6 turns (never both, never neither).
  - Walking and jumping (no jitter, no camera zoom).
  - Seated on a lounger and a sofa (the backrest hides the middle of the stick, the tip shows).
  - A clean console.
- Your saved equipped cue in Studio was switched to Classic for the test and put back to
  BetaCue.

**Check by hand:** a second real player (their back cue, and them shooting with Classic), and
a quick look on a real phone.

## Uploads (group 675425213)

| File | Decal / model id | Image / mesh id |
|---|---|---|
| `Cue.glb` (model) | 112855847049580 | mesh 113499415983055 |
| `classic_color.png` | 113726250410970 | 105908889801184 |
| `classic_normal.png` | 136175165555480 | 114159920269427 |
| `classic_roughness.png` | 114675891803427 | 119517224467514 |
| `classic_metalness.png` | 109852363568662 | 138757447950095 |

That is 1 model and 4 images, within the limits of 3 and 12. No audio.

## Assumptions (each is a dated line in `docs/DECISIONS.md`)

- UVs are conformal strips. "No stretch" is measured as an average per strip (at most 1.05;
  the worst strip is 1.029). The single worst face is 1.105, which is reported.
- The handle gets about 1.56 times the shaft's pixels per stud.
- The tip dome uses a real tip's curve. The bumper is a skin colour. The butt's end cap is
  small in the atlas (about 87 px): enough for a badge, not for text.
- The tip, ferrule and bumper are plain colours, not pictures.
- Classic is drawn straight into the maps by script, not baked with Cycles. The linen threads
  are a little bigger than real so they show in play.
- `CueTemplate.py` uses the Mac's own Python with Pillow.
- A skin template is `ReplicatedStorage.CueSkins.<cue id>`. Swapping between two mesh skins is
  written as a note plus a test that fails when a second skin arrives, since only one exists.
  The Index's black "not found yet" silhouette uses the bands.
- The back cue uses its own pool of sticks and re-welds them instead of `wear()`. Its numbers,
  all in `Config.Cue.Back`: 36 degrees, 0.3 studs off the back, +30 degrees seated, within
  90 studs, 12 sticks.

## What comes next

Your first ChatGPT skin. Follow `assets/cue/template/CHATGPT.md`, then "Make a new skin" in
`assets/cue/Readme.md`. The second mesh skin is when the SurfaceAppearance swap in
`CueStickBuilder` gets written (the note in `paintStick` says how).
