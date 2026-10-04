# Lane: Unique cues (the Beta Cue and the Grand Opening Cue)

Folder `~/Desktop/8ball-unique`, branch `lane-unique`, Rojo port 34878, Studio file
`place/lane-unique.rbxl` (a copy of the Team Create place saved 2026-10-04). Rules for all
lanes: [README.md](README.md). The job itself is the brief
[docs/prompts/UNIQUE_CUES_PROMPT.md](../prompts/UNIQUE_CUES_PROMPT.md): read it after this
file and follow it exactly; its Progress list is the source of truth.

## The job

The game's first two Limited cues, the **Beta Cue** (a see-through blueprint hologram) and the
**Grand Opening Cue** (navy and gold with fireworks), exist in the catalog only as placeholder
colour bands. Build their complete looks: surface maps, 3D pieces, aura, moving light, ball
trail, pocket finisher, faint sounds and card pictures, to a visual standard above the Secret
cue (Eclipse). The designer's references and answers are in the brief.

## You own

- Skin files and art: `assets/cue/skins/beta*.json`, `assets/cue/skins/grand_opening*.json` and
  their panel folders; `assets/cue/textures/beta_*`, `grand_opening_*`; `assets/cue/thumbs/`
  for these two; `assets/cue/pieces/beta*`, `grand_opening*`; `assets/cue/models/` entries
  you generate; `assets/cue/vfx/beta*`, `grand_opening*`; `assets/cue/concepts/unique/`.
- The generated rows `src/shared/CueSkins/Skins/BetaCue.luau` and `GrandOpeningCue.luau`
  (always through `tools/cue_skins_data.py`, never by hand).
- New tools under `tools/` or `assets/cue/` that only these cues need (name them `unique_*`
  or `beta_*` / `grand_opening_*`).
- `tools/upload_manifest.json`: add your entries; never change others'.

## Shared files you may extend

The cue runtime is generic and stays generic: `src/client/CueVfx.luau`, `CueSkinLook.luau`,
`CuePiece.luau`, `Effects.luau`, `src/shared/CueStickBuilder.luau`, `tools/cue_skins_data.py`,
`tools/build_cue_templates.luau`, the piece builders, `Config.CueSkins`, `Config.Effects`. Add
new capabilities as new data kinds or new functions, as blocks, driven by the skin data, so any
future cue can use them. No `if cueId == "BetaCue"` branches. List every change to a shared
file in this lane file's Changes section.

## Not yours

- `Progression/Catalog.luau` rarities, prices, `StartsAt`, numbering, trading and every
  economy number (the designer: the Epic and Legendary tags on these two rows are overwritten
  for visuals; do not edit the rows). If the runtime needs to know these two are above Secret,
  put that in the skin data, not the catalog.
- Every screen (GUI lane): where a cue's number is shown is GUI's decision. Write what the
  cards and the Index need from you in Requests.
- `docs/STATUS.md`, `DECISIONS.md`, `ROADMAP.md`, `ECONOMY.md`.

## Integration (what the integrator does in the real place)

Written in the brief's Handoff section when the work is done: the uploaded asset ids (in
the manifest), the two templates and any pieces to build with the builders, and anything made
by hand in your copy (which is otherwise lost at the merge).

## Status

(one dated line per finished step)

- 2026-10-04 step 0: docs read, lane window and Rojo 34878 checked, section 7 answered (0.36,
  the three sound files, own outline colours, catalog helper). Commit 5650020 (0.36 width)
  cherry-picked without the shared docs; lint and 984 tests green; the lane window's Classic
  mesh swapped and all templates and pieces rebuilt; the wide cue checked on backs, stands
  and in hands (PC). The integrator must do the same mesh swap and template rebuild in the
  real place at the merge (Requests).
- 2026-10-04 step 1 (boards ready, gate 1 pending): both skins exist end to end in Blender
  (OpenAI panels, paint recipes, maps, pieces, sprites, VFX data, stills, clips); the boards
  `assets/cue/concepts/unique/beta-board.png` and `grand_opening-board.png` (+ the two clips)
  are composed from our own renders by `tools/unique_board.py`. OpenAI spend so far about
  $0.29 (8 panels). Approved by the designer the same day (one change: a holographic tip).

- 2026-10-04 step 2: Beta surface done. The holographic tip and ferrule (part-transparent,
  magenta and blue, gate-1 change), the five painted panels, 22 VFX sprites and 8 blueprint
  panel textures, the thumbnail and the two piece GLBs (`beta`, `beta_pocket`) uploaded to the
  group and recorded in the manifest; rows generated (`Skins/BetaCue.luau`, `Pieces/beta.luau`,
  `Pieces/beta_pocket.luau`, the Index entry); 59 templates and the two pieces built in the
  lane window with no problems; checked in the lab on a stand and a back next to Eclipse from
  four angles, console clean. The body blew out white in the bright lobby, so emissive
  strength, glint and mote rates and beam brightness were tuned live and written back into
  `assets/cue/skins/beta.json`. Lint and 984 tests green.
- 2026-10-04 step 3: the hologram shell moves. New generic kinds in the Blender reference and
  the runtime: the `saw` wave shape (one-way sweep), the `Glitch` motion (sideways jolts in a
  short window once a period) and per-joint `Visual` rows (`Fade`, `Blink`, `Glow`) that
  CuePiece applies to the joint's parts every frame. The Beta piece: the scan line sweeps tip
  to butt every 2.6 s and fades at both ends, the lattice and the rings glitch (jolt and
  blink) every 4 s, the lattice's light pulses slowly, the magenta rings pulse toward white
  with their pale edges fading in and out behind them. The scan disc had been built 7 studs
  off its rim (a sign slip in step 1); fixed. The Beta piece is in the motion fixture, so
  Lune checks the saw and the glitch against Blender. Rebuilt, re-uploaded (new GLB id),
  templates rebuilt in the lane window, probed in Play (the disc rides its rim, the lattice
  blinks and jolts), console clean, lint and 984 tests green.
- 2026-10-04 step 4 (built, gate 2 pending): the Beta aura's panels live. New generic kinds:
  the `life` effect-wave shape (pop in with a blink, hold, dissolve with a blink) in the
  Python reference and Motion, and the `Type` joint visual: CuePiece builds a thin part
  riding the joint at the pane's frame with a SurfaceGui that types made-up glyph tokens
  (Config.CueSkins.Typing: the Code font, the alphabet, canvas density, glow), new text each
  life, a blinking cursor, fading with the panel; the gui switches off with the aura and when
  the stick is camera-faded. Each of the eight panels has its own life (6 to 9.5 s) and phase,
  so five or six are up at once and none are born together. The aura was tuned on the bright
  lobby floor (the body had blown out white): calmer glints, motes and glyph flecks, beams at
  1.2, the body's emissive at 0.8 to 1.3 in a deeper blue. Captures for the gate:
  `assets/cue/concepts/unique/beta-studio-{stand,close,back,panel}.jpg`. Lint and 984 tests
  green.

## Decisions

(dated; small calls you made on your own)

- 2026-10-04: the overnight Stop hook looked for its marker files under `.git/`, which is a
  file in a worktree; it now resolves the real git directory (tools/overnight/keep_going.sh).
- 2026-10-04: the Beta card picture is the `--noaura` thumbnail (the GUI lane's card
  convention): it still shows the glowing hologram body and the blueprint panels, so the card
  reads as the cue without the aura's haze filling the frame.
- 2026-10-04: a skin file may carry `"draft": true`; `tools/cue_skins_data.py` skips it (no
  row, no Index entry, no piece rows) so a half-built cue never reaches the game. The Grand
  Opening skin carries the flag until step 7.

## Changes to shared files

(file, what, why)

- `assets/cue/CuePaint.py`: the paint kit's Canvas carries an `alpha` companion (`put(alpha=)`,
  written as `<panel>_alpha.png` only when a recipe sets it); two recipes `beta` and
  `grand_opening` and a `quilt` wrap helper. Why: the hologram's see-through body.
- `assets/cue/CueTextures.py`: `COMPANIONS` gains `alpha`; `panel_skin` returns it and
  `write_maps` writes an RGBA colour map when a skin has one (the tip, ferrule and bumper stay
  solid). Why: Roblox reads the colour map's alpha as transparency in AlphaMode Transparency.
- `assets/cue/CuePreview.py`: `cue_material` links the colour map's alpha to the shader when
  the skin's `surface.AlphaMode` is `Transparency` (blended). Why: the preview shows the
  hologram as the game will.
- `assets/cue/CuePieces.py`: `build` imports `CuePiecesUnique` (the new builders module).
- `tools/build_cue_templates.luau`: `surfaceAppearance` sets `AlphaMode` from the skin row's
  `Surface.AlphaMode`. Why: the Beta template's hologram.
- `assets/cue/concepts/crops.json`: boxes for the two Unique reference boards
  (`unique/beta-concept`, `unique/grand-opening-concept`).
- `tools/cue_skins_data.py`: skips skins marked `"draft": true`; writes only the pieces an
  included skin wears; `uploaded()` finds a skin's maps through the manifest when the
  gitignored textures are absent locally; `recorded_look()` keeps the Index's recorded Look for
  a skin whose colour map is absent; `asset_id` prefers manifest keys under the main checkout
  when several match. Why: the generator ran from a worktree without the other lanes' textures
  and must change only the Beta rows.
- `src/shared/Config.luau`: `CueSkins.Quiet.Shares.Unique = 0.25` (the brief: Unique auras
  quiet to a quarter in the hands) and `CueSkins.Outline.Colors.Unique = "#FF5CB8"` (the
  tier's pink; each Unique skin sets its own `Aura.Outline`).
- `src/shared/Progression/Catalog.luau`: `specialCue` takes a Unique row's Look from the
  CueSkins Index when the skin exists (the designer's section-7 answer); the placeholder bands
  stay for rows without a skin.
- `tests/cue_mesh_test.luau`: a `built` set of Unique cues that must have a skin (`BetaCue`);
  unbuilt Unique cues must have none. Why: the Grand Opening row stays skinless until step 7.
- `assets/cue/CuePieces.py`: `_wave` gains the `saw` shape; `glitch_offset` and the `Glitch`
  motion kind in `motion_matrix`; `Kit.joint(visual=)` and `Visual` rows exported in
  piece.json. Why: the Beta scan line, glitch and ring pulse (any piece can use them).
- `src/shared/CueSkins/Motion.luau`: `pieceWave` `saw`; `glitchOffset`, `blinkGone`; the
  `Glitch` motion in `own`; rigs carry each joint's `visuals`.
- `src/client/CuePiece.luau`: joint `Visual` rows (`Fade`, `Blink`, `Glow`) applied to the
  joint's rigid parts each step, composed with the dressed base and the piece's fade
  (`setFade` leaves those parts to the next step).
- `tools/cue_motion_fixture.py` + `tests/cue_motion_fixture.json`: the `beta` piece joins the
  fixture (saw and Glitch checked against Blender); `tests/cue_motion_test.luau` tests the saw,
  glitch and blink maths.
- `assets/cue/CueVfx.py` `wave` and `src/shared/CueSkins/Motion.luau` `vfxWave`: the `life`
  shape (a hologram panel's pop-in, hold and dissolve). Why: the Beta panels' life cycle.
- `src/client/CuePiece.luau`: the `Type` joint visual (a typing SurfaceGui riding the joint:
  `buildTyper`, `stepTyper`, `showTypers`), `shownShare`; `src/shared/Config.luau`
  `CueSkins.Typing` (font, alphabet, token lengths, canvas density, glow, line height, cursor).
  Why: the Beta panels type gibberish; any piece can carry a typing panel.

## Requests

(for the GUI lane and the integrator)

- Integrator, at the merge (the 0.36 cue, commit 5650020 cherry-picked here): in the real
  place, Edit mode, swap `ReplicatedStorage.CueSkins.Classic.Cue` to the new mesh
  (`InsertService:LoadAsset(73474446131672)`, `cue:ApplyMesh(thatMeshPart)`, then
  `cue.Size = Vector3.new(0.36, 0.36, 7)`), set Classic's four maps from
  `src/shared/CueSkins/Skins/Classic.luau` (plugin writes of `*MapContent`), then run
  `tools/build_cue_templates.luau` to rebuild every template and piece. Checked in the lane
  window 2026-10-04: 58 templates, 16 pieces, no problems.
