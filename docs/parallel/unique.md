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

## The second job (2026-10-04): the cue rarity rework

After gate 3 the designer asked for the same bar across the rarer existing cues: the brief is
[docs/prompts/CUE_RARITY_REWORK_PROMPT.md](../prompts/CUE_RARITY_REWORK_PROMPT.md) (the tier
rules, the order, the answers). The lane owns, in addition: every skin file, piece module,
paint recipe, sprite and upload it touches for that job, from Eclipse down, with the same
generic-runtime rule; the catalog rows stay untouched.

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
  green. Gate 2 passed the same day ("looks good"); the one change, a white tip instead of
  pink, is in the skin file (`colours.tip`, the glow key).
- 2026-10-04 step 5: Beta's trail, pocket finisher and hum in the game. The three designer
  sounds converted to mono 16-bit 44.1 kHz WAVs (`assets/cue/sounds/`), uploaded to the group
  and recorded in the manifest; new generic kinds: a skin's `Aura.Sound` (CueSkinLook: a
  looping Sound on the cue, playing with the aura, volume following the quiet share, in the
  Sfx group) and `Pocket.Sound` (Effects: played once at the pocket); Config
  `CueSkins.Sound` and `Effects.Finisher.Sound` hold the roll-offs. A finisher's `Piece` row
  may now set `Outline` {Color, Transparency}, `ShellFade` and `EmissiveScale` (the default
  dark contrast outline turned the wire funnel black). The funnel is rebuilt three times
  thicker (0.09-stud Neon wire, fat rings, a denser skin; new GLB id), rises bigger (scale
  0.8 to 1.7, 2.2 s), with a navy ring and column under the glow so it reads on the white
  floor; the trail is a 0.7-stud holo ribbon with a 0.3 core (every trail is capped at
  Config.Effects.TrailMaxSeconds, 0.45 s, so lengths are equal across cues). Checked in a
  solo fixture match (table 1: the trail's rings and glints round the rolling white, the
  finisher on a scratch, the hum at a quarter volume in the hands) and in a lab beside the
  Eclipse finisher; console clean. Lint and tests green.
- 2026-10-04 step 6: Beta's Lower-effects variant and cards. A piece joint may carry
  `Low = "hide"` (CuePieces `joint(low=)`, Motion rigs, CuePiece): under the Lower effects
  setting the joint, its children and its typing panel go, and come back when the setting
  changes (Quality.Changed). Beta hides its four farthest panels; its particle rates already
  follow Quality through CueVfx (glints 6 -> 2.1 a second). Checked in the lab with the
  setting toggled (`beta-studio-low.jpg`). The Index shows the Beta Cue in the Unique row with
  its thumbnail silhouette until found, and the detail panel "Beta Cue / Unique / Not found
  yet" (`beta-index.jpg`); the owned card uses the same no-aura thumbnail. Quieting in the
  hands: the aura's emitters and the hum drop to a quarter (Config Quiet share 0.25); the
  piece and panels stay. Lint and tests green.
- 2026-10-04 steps 7 and 8 (built, gate 2 pending): the Grand Opening Cue is in the game.
  `"draft": true` removed from its skin; its five painted maps, three sprites, the thumbnail
  and the ribbon piece GLB uploaded to the group with image ids; rows generated
  (`Skins/GrandOpeningCue.luau`, `Pieces/grand_opening.luau`, the Index entry); the template
  and the piece built in the lane window; `GrandOpeningCue` added to the mesh test's built
  set. The aura on the lobby floor: the two gold ribbon helices turn round the cue, glitter,
  star glints and crackle sparks round it, mini fireworks popping in five colours with a
  bigger burst every few seconds, a warm gold halo beam, gold emissive stars pulsing on the
  body. It blew out white on the floor: glitter, glints, crackle and glow rates and
  brightness cut to about a third, the halo and the ribbon heads dimmed, the body's emissive
  1.2 to 2.0, and the PointLights of both Unique cues dimmed (switching the lights off in the
  lab proved they, not the particles, flooded the floor). Captures for the gate:
  `assets/cue/concepts/unique/grand-opening-studio-{stand,close,back}.jpg`. Lint and the cue
  tests green.
- 2026-10-04 steps 9 and 10: the Grand Opening Cue's trail, finisher, sounds, Lower-effects
  variant and cards. Gate 2 passed the same day ("looks good"); the one change, the mini
  fireworks were hard to see, is in: the burst sprite's rays and tips three times as fat with
  a stronger halo (re-uploaded, new image id), the five pops bigger (1.0 to 1.6 studs),
  brighter (7) and more saturated, 0.8 a second each, the big burst 2 to 3.2 studs
  (`grand-opening-studio-fireworks.jpg`). In a solo fixture match: the gold sparkler streamer
  with coloured starlets behind the rolling white, the spark fountain and staggered coloured
  bursts on a scratch (`grand-opening-studio-trail.jpg`, `-pocket.jpg`), the crackle hum in
  the aura and the fireworks sound at the pocket (the generator had dropped `Pocket.Sound`;
  fixed, so the sound row reaches the game). Lower effects cuts its particle rates to a third
  through Quality (no piece joint hides: the two ribbons are the cue's main form). The Index
  shows it in the Unique row with its no-aura thumbnail. Lint and the cue tests green.
- 2026-10-04 step 11: lint and the 984 tests green; the six-cue lineup captured in the lab
  (`lineup-six-high.jpg`, `lineup-beta-grand-opening-eclipse.jpg`,
  `lineup-apex-kitsune-dragon.jpg`); gate 3 passed ("both cues get a pass").
- 2026-10-04 step 12: the Handoff section in the brief, `docs/prompts/UNIQUE_CUES_REPORT.md`
  and `docs/CUE_VFX_TECHNIQUES.md` (the designer asked for it at gate 3). The lane's next
  job, the rarity rework of the existing cues, has its own brief
  (`docs/prompts/CUE_RARITY_REWORK_PROMPT.md`).
- 2026-10-04 rework, Eclipse (step 1 and the start of step 2): the plan approved; the
  generic capabilities built: themed ends (an optional `ends` panel the recipe paints for the
  tip's side and the ferrule; `CuePaint.Kit.ends()`, `CueTextures` takes it over the flat
  chalk and ivory), the Carrier piece and Carrier emitter host (a stick on a back carries an
  ObjectValue `Carrier` set by BackCue; `CueSkinLook` builds the skin row's `Carrier` piece on
  the character's root and welds Carrier-host emitter parts to it; hidden when quiet or off
  the back), the preview's carrier (the back segment wears it). Eclipse: the collar and ends
  painted (obsidian with molten cracks, a gold corona ring round a black-sun band), the piece
  reworked (a mesh corona and flare rings on the black sun, thicker breathing orbit rings
  with four planets, one ringed, thicker great orbits, twelve asteroids, an eclipse-shadow
  ring sweeping the cue), the `eclipse_carrier` piece (a black sun with corona over the head,
  two orbit rings with planets round the body, a third small orbit, an asteroid belt), the
  aura rewritten as a star system (about 99 particles a second, from 247; carrier rows for
  the player), sounds as Roblox library placeholders. Lint and the 984 tests green. Gate 1
  passed at the third look (vanta-black suns with finisher coronas, neon rings, the head sun
  blooming like the butt). Built in the lane window: uploads, template, both pieces; the
  coronas tuned on the floor; quiet checked. Waiting at gate 2.
- 2026-10-04: gate 2 feedback built: the carrier piece centred (a `carrier` piece frame; it
  was exported in the cue frame, 3.5 studs forward) and the engulfing aura gone while a shot
  is in flight at the owner's table, back between shots (`CarrierQuiet`, generic). Lint and
  the 986 tests green; checked in the lab. Waiting at gate 2 again.
- 2026-10-04: gate 2, third look: the designer dropped the aura on the player altogether;
  Eclipse's carrier piece and rows removed (the generic Carrier capability stays, now with a
  head-height lift); the bright glow wraps the cue instead (a ForceField sheath with a Neon
  core on the piece, sleeve sprites along the stick). Piece re-uploaded, template rebuilt in
  the lane window, clip re-rendered. Waiting at gate 2.
- 2026-10-04: gate 2, fourth look: the sheath hid the paint; now two thin gold wires spiral
  round the cue and the halo sprites draw behind it. The designer dropped sounds for good
  (no imports, no placeholders): Eclipse's two removed. Gate 2 passed; the designer keeps
  Eclipse's old trail and pocket finisher. On to the Celestial Dragon (board, gate 1).
- 2026-10-04: the Celestial Dragon reworked in data (beats slowed two to three times,
  cyan-white spirit palette, spirit filaments, four slow wisps for ten flames, the cloud cut
  to a third, gold-scale and pearl ends); board and clip rendered. Second look: the dragon
  lengthened to coil the whole cue, a light-blue hologram aura round the stick. Third look:
  the long body dropped (it looked broken), twelve see-through blue energy ribbons turning
  and fading round the cue after the designer's reference. Gate 1 passed; built in the
  lane window (uploads, template, pieces), tuned on the floor (halo dimmed, sheath thinned);
  then the whole dragon recoloured to the head's pale blue, its white filaments dropped and
  the energy ribbons doubled and widened in the same blue, then (too much) cut to 32
  thin see-through threads hugging the cue like a barrier, then made mostly clear and kept
  inside the cue's length, doming over the butt. Gate 2 passed 2026-10-04 ("good enough").
  Kitsune (step 5) first look 2026-10-04: nine tails and three foxfire orbs as real meshes
  (the Beams and sprite orbiters gone), the cloud cut to a third, themed ends. Second look
  2026-10-05 (the designer's reference): a great spirit fox of violet flame along the cue
  (new Meshy head, a waving flame body), wind wisps and flame sprites blowing toward the
  butt, fox-face orbs, the aura violet; dropped by the designer ("terrible"). The first look
  is the Kitsune: uploaded (parts, textures) and built in the lane window 2026-10-05.
  Apex (step 6): a first look on 2026-10-05 was dropped by the designer ("no more changes,
  the older version was better"; reverted). 2026-10-05: the designer stopped the rework and
  asked for the finished cues (Beta, Grand Opening, Eclipse, Celestial Dragon, Kitsune) to be
  merged into the game and nothing else: the lane merged into `release` (branch
  `cues-merge`); the only conflicts were Strings.luau (release's side kept: the "Mythical"
  label rename is left out) and cue_mesh_test (both sides' wording); the lane's OpenAI
  spend-log lines were left out so the main checkout's uncommitted log is untouched. The
  Studio step (the 0.36 Classic mesh, Classic's maps, every template and piece rebuilt in
  the real place) is in Requests below.

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
- `tools/cue_skins_data.py`: `ASSET` resolves `.wav/.ogg/.mp3` paths (`sounds/x.wav` ->
  `rbxassetid://<audio id>`); the pocket row keeps its `Sound`. Why: sounds in the skin data.
- `src/client/CueSkinLook.luau`: `buildSound` (Aura.Sound), played in `applyVisible`, volume
  eased in `ease`. `src/client/Effects.luau`: the finisher's `Sound` row; the piece row's
  `Outline`, `ShellFade`, `EmissiveScale` overrides (hex outline colours through CueVfx).
  `src/shared/Config.luau`: `CueSkins.Sound`, `Effects.Finisher.Sound`. Why: the Beta hum and
  the Grand Opening's fireworks; a hologram finisher keeps its own colour.
- `assets/cue/CuePieces.py` `joint(low=)` -> `Low` in piece.json; `Motion.rig` carries `low`;
  `src/client/CuePiece.luau` `hidden`/`applyHidden` (aura off or Lower effects), a
  Quality.Changed connection released in `destroy`. Why: a per-cue Lower-effects variant as
  data.

- `assets/cue/CuePaint.py`: `Params.panels['ends']` (`ends_panel`), `Kit.ends()`: the optional
  ends panel (the tip's side and the ferrule) a recipe paints. Why: themed ends from Legendary
  up (the rarity rework).
- `assets/cue/CueTextures.py`: `themed_ends`, `ends_params`; `paint_panels` maps the tip and
  ferrule to the ends panel when the skin lists it; `plain_parts(painted=)` keeps the paint.
  Why: the same.
- `assets/cue/CueVfx.py`: Host kind `Carrier` in `spawn_local`; `Emitter.fixed_host` (a
  callable host matrix) in `step` and `quads`. Why: the engulfing aura round the player in
  the preview.
- `assets/cue/CuePreview.py`: `make_aura(carrier_m=)`; the back segment builds a carrier
  root at the avatar's hips, wears `skin['carrier']` through `CuePieces.attach` and the
  Carrier-host rows, framed wider. Why: the same.
- `src/client/CueSkinLook.luau`: `carrierRoot()`, the `Carrier` ObjectValue watched, the row's
  `Carrier` piece built on the character's root (`carrierPiece`: stepped, hidden when the
  quiet target is under 1 or the aura is off, destroyed in clear), Host kind `Carrier`
  (`host` may return nil; `buildEmitter` skips). Why: a Secret's aura engulfs the player.
- `src/client/BackCue.luau`: `attach` sets the stick's `Carrier` ObjectValue to the character
  before the paint; `detach` clears it. Why: the same.
- `tools/cue_skins_data.py`: skin `carrier` -> row `Carrier`, its piece generated. Why: the same.
- `src/shared/Strings.luau`: the Mythic tier's labels read "Mythical" (item rarity, case,
  reveal band, unbox line). Why: the designer, 2026-10-04.
- `tools/build_cue_templates.luau`: a skin row's `Carrier` piece is built with the others.
  Why: the carrier piece.
- `assets/cue/CuePiecesMythic.py`: `eclipse` reworked, `eclipse_carrier` added. (Owned by
  the rework job; listed because the integrator rebuilds both pieces.)
- `assets/cue/CuePieces.py` and `src/shared/CueSkins/Motion.luau`: a third piece frame,
  `carrier` (`Kit.frame`, `ZOFF`; `Motion.rig` gives it no tip shift, like `pocket`). Why: a
  Carrier piece sits on the character's root, not the cue mesh.
- `src/shared/Config.luau`: `CueSkins.Carrier.ShotPhases`. Why: the designer, 2026-10-04:
  the aura round the player goes while a shot is watched at their table.
- `src/shared/AuraQuiet.luau`: `carrierQuiet(owner, snapshots)` and the stick's
  `CarrierQuiet` attribute written by `apply` (now requires Config). Why: the same.
- `src/client/CueSkinLook.luau`: `carrierShown()` (AuraQuiet or CarrierQuiet hides the
  Carrier piece and the Carrier-host emitters, flagged `carrier` in `emitters`). Why: the same.
- `tests/aura_quiet_test.luau`: two tests for the carrier rule.
- `assets/cue/CuePieces.py`: `k.model(... hologram={'ShellTransparency': x})`, the hologram
  shell's Transparency (0 as before). Why: the Dragon's head shell read solid in the sun.
- `tests/cue_motion_fixture.json`: regenerated (the Dragon's slower motions).
- `src/client/CuePiece.luau`: `CuePiece.new(id, root, parent, lift?)`: the whole piece raised
  on its root, applied after each joint's pose. `src/client/CueSkinLook.luau`:
  `carrierLift()` (the carrying body's head top against `Config.CueSkins.Carrier.HeadTopStuds`)
  lifts the Carrier piece and Carrier hosts. Why: the designer, 2026-10-04: a piece over the
  head must follow a tall or short avatar's head. (No cue uses a Carrier piece now; Eclipse's
  was dropped the same day.)

## Requests

(for the GUI lane and the integrator)

- Integrator, at the merge (the 0.36 cue, commit 5650020 cherry-picked here): in the real
  place, Edit mode, swap `ReplicatedStorage.CueSkins.Classic.Cue` to the new mesh
  (`InsertService:LoadAsset(73474446131672)`, `cue:ApplyMesh(thatMeshPart)`, then
  `cue.Size = Vector3.new(0.36, 0.36, 7)`), set Classic's four maps from
  `src/shared/CueSkins/Skins/Classic.luau` (plugin writes of `*MapContent`), then run
  `tools/build_cue_templates.luau` to rebuild every template and piece. Checked in the lane
  window 2026-10-04: 58 templates, 16 pieces, no problems.
