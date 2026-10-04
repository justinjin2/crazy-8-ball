# The Unique cues: Beta Cue and Grand Opening Cue

**Written 2026-10-04 by the designer with Claude.** Lane `unique`: folder
`~/Desktop/8ball-unique`, branch `lane-unique`, Rojo 34878, Studio window `lane-unique.rbxl`
(and only that one). Rules: `docs/parallel/README.md`, `docs/parallel/unique.md`.

This is an **attended run**: the designer is awake and answers quickly. The Progress list at
the end is the source of truth; the Stop hook sends you back to work while any `- [ ]` remains.
When you need the designer (an approval gate below, access you cannot get, or a call where
guessing would lower the quality), run `touch .git/overnight-waiting`, ask one clear question
with pictures, and stop; the hook lets that stop through. Otherwise never stop between steps.

## 0. Read first, in this order

`CLAUDE.md`, `AGENTS.md`, `docs/parallel/README.md`, `docs/parallel/unique.md`, the
`docs/STATUS.md` entries dated 2026-10-01 ("the new cue skins are in the game" and "cue VFX v2,
outlines and wider cues"), `docs/prompts/CUE_SKINS_PROMPT.md`, `CUE_SKINS_REPORT.md`,
`CUE_SKINS_REVIEW.md` (the Eclipse, Kitsune, Celestial Dragon and Apex rows: what the top cues
have today), `assets/cue/Readme.md` and `assets/cue/template/CHATGPT.md` (the paint pipeline),
`assets/cue/skins/eclipse.json` (the Secret cue's data: your floor), `tools/cue_skin.py`,
`tools/cue_vfx_v2.py`, `tools/vfx_sprites.py`, `tools/vfx_lab.luau`, `tools/cue_skins_data.py`,
`tools/build_cue_templates.luau`, `tools/cue_pieces_glb.py`, `tools/meshy_generate.py`,
`tools/openai_image.py`, `tools/roblox_upload.py`, `docs/STUDIO_NOTES.md`, and the runtime:
`src/client/CueVfx.luau`, `CueSkinLook.luau`, `CuePiece.luau`, `Effects.luau`, `Quality.luau`,
`src/shared/CueStickBuilder.luau`, `src/shared/CueSkins/`, `Progression/Catalog.luau` (the
two `specialCue` rows at the end), `docs/UI_STYLE.md` section 4 (tier colours: Unique is pink
`#FF5CB8`).

Then look at the references, closely, before anything else:

- `assets/cue/concepts/unique/beta-concept.webp`: the Beta Cue board. Full cue, handle
  close-up, a 3D view with blueprint panels floating round it, the ball trail, the pocket.
- `assets/cue/concepts/unique/grand-opening-concept.webp`: the Grand Opening board. Full cue,
  handle close-up, the cue with gold ribbons and fireworks, the ball trail, the pocket.
- `assets/cue/concepts/unique/painted-vfx-style.webp`: the KIND of VFX the designer loves
  (a painted anime fire slash: real shape, layers, crisp edges, embers, depth), not a request
  for fire. Use its quality and layering.

The same three files are in `~/Desktop/8ball-refs/cue-vfx/` (01 to 03). Codex left Beta
paint panels in the main checkout's `assets/cue/skins/beta*/` (git-ignored, not in this lane);
the designer rejected that work. Start fresh.

## 1. What these cues are

The game's first two Limited cues, the first ever sold. Catalog group **Unique**, pink tier,
numbered, one per player, never returning. The Grand Opening Cue goes on the Limited shelf for
14 days when the designer sets its start; the Beta Cue is scheduled later. Today both are
`specialCue` rows with placeholder colour bands and no skin.

**The designer's ruling on tier (2026-10-04): Unique is a tier of its own, above Secret.** The
`"Epic"` and `"Legendary"` tags on their catalog rows are overwritten for every visual purpose
and must not be edited (they are economy data). If the runtime keys anything off the rarity
(aura quieting in the shooter's own hands, the outline colour, the finisher's size), add a
visual-tier value to the skin data and read that first. In the shooter's own hands while aiming
these quiet like a Secret (a quarter); everywhere else, full.

The owner's number is **not** on the mesh (the designer: where the number shows is GUI's call).

## 2. The bar

Both cues must beat Eclipse in every respect: aura, moving light, trail, pocket finisher,
pieces, card picture. Put Eclipse (and Apex, Kitsune, the Dragon) next to them in the lab at
every check. Quality and visual appeal over cost and over performance (the designer: "purely
cosmetic visual appeal"; still keep a Lower-effects variant that holds the identity, and the
shooter must still see the balls). Spend on OpenAI images and Meshy freely, upload to group
`675425213` freely (standing authorisation). Never print or write an API key. If a paid tool
would raise the result, ask the designer; they will buy it.

**The depth rule (the designer's strongest note):** nothing may read as a moving 2D picture.
Orbit the camera round an avatar wearing the cue and round the cue on a stand: at every angle
the aura must have depth and layers (real geometry at several distances from the cue, things
in front of and behind the cue, parallax). Camera-facing particles are fine for sparks, motes,
glints and bursts; the main forms (hologram shell, rings, panels, ribbons, funnel) are real 3D
things or beams in 3D space.

**Light:** the cues must actually emit light in the game: Neon and emissive maps at strengths
Bloom picks up (Bloom is on in the lobby), PointLights that light the floor and the avatar,
Highlights for edge light, additive beams and particles (LightEmission 1). Test in the bright
lobby daylight with `tools/vfx_lab.luau`, never on the dark Blender preview.

## 3. The Beta Cue (hologram blueprint)

The designer's words: "looks holographic and actually somewhat translucent and see through as
if it's a blueprint. Aura around it shows blueprint diagrams, techy, pulsating, like writing
lines of code popping in and out. The cue MUST be glowing in Roblox and actually look like pure
light, a hologram that emits light in game and in render. It should NOT look like a moving 2D
picture: an actual animated visual effect aura, constantly moving light energy flowing
throughout the entire cue and the aura around it, with depth from any perspective."

Answers (2026-10-04):
- **Body:** like the reference: about half transparent, electric blue, blueprint linework over
  the whole cue (cross-section circles, longitudinal lines, grids, dimension lines, small
  schematic marks), the brightest lines white-hot. The whole cue is hologram, shaft included.
- **Rings and tip:** magenta rings (two at the joint, two at the butt collar, as the board)
  and a magenta-white glowing tip. The tip still reads as a cue tip on the ball.
- **Panels:** blueprint panels float **well beyond the cue** (the board's right-hand view), at
  several distances, heights and tilts, so they have depth from any angle. On them: cue
  cross-sections, circles, grids, dimension lines, and lines of "code" typing in and out. The
  text is **gibberish or unreadable futuristic glyphs**, never English words, nothing corny.
- **Motion:** light energy constantly flowing along the whole cue and through the aura; rings
  pulsing; a scan line sweeping tip to butt; occasional glitch flicker; panels popping in,
  typing, dissolving out, like code appearing.
- **Trail and finisher:** big, massive, at least Eclipse's size. Trail: a blue-magenta light
  stream shedding wireframe fragments and cross-section rings. Pocket: a wireframe funnel
  rising out of the pocket (the board), rings, a flash, a digital burst.
- **Sound:** a very faint hologram hum (local, in the aura, respects the sound settings).

Recommended build (you decide the details; change anything that gives a better result):
- *Body:* the shared cue mesh with a SurfaceAppearance in Transparency alpha mode (body alpha
  about 0.5, the linework, rings and edges opaque), a strong blue emissive map, magenta rings
  in the emissive; plus a slightly thinner inner **Neon core** cue (real light) and a slightly
  larger **ForceField** shell (the shimmer), and a Highlight with a blue outline. PointLights
  along the cue (blue) and at the rings (magenta). Check transparency sorting on the back,
  in the hands and in the Index viewport.
- *Depth on the cue:* a Blender-made **wireframe lattice shell** round the body (longitudinal
  lines, rings, the board's cross-section circles; the Wireframe modifier on a coarse
  cue-shaped mesh), Neon, slowly turning against the body; real 3D rings (tori) at the joint
  and collar that pulse. A thin bright ring (the scan line) travels tip to butt every couple
  of seconds. The glitch: a brief offset/flicker of the shell, now and then.
- *Light flow:* scrolling energy on the cue-wide overlay Beams the Epics use (TextureSpeed),
  and emissive pulses travelling along the body.
- *Panels:* real parts, not sprites: thin tinted glass panes with Neon edge frames carrying
  SurfaceGuis: a label typing glyph strings (a Roblox font such as Code, Michroma or Oxanium
  with made-up glyph text, or an image font you draw; never readable words) and diagram images
  (circles, sections, dimension lines; draw them in Pillow or paint them). Six to ten live at
  once at three or more radii round the cue, tilted differently, slowly orbiting with the
  aura, each scaling in with a flicker, typing, then dissolving. Thin leader-line Beams tie
  panels to points on the cue. On the back, big panels obey the behind-body rule so they never
  cover the avatar's face.
- *Particles:* data motes, glyph flecks, small wireframe rings drifting off, blue haze body,
  white-hot glints.
- *Trail:* a wide additive blue-to-magenta beam/trail with a scrolling wireframe texture, plus
  emitters shedding cross-section rings (own sprite), glyph flecks and motes; at least
  Eclipse's 1.2 s and width.
- *Pocket:* a Blender wireframe funnel mesh (or stacked growing Neon rings) rising about five
  ball heights over the pocket, turning, with a magenta flash, a light column, digital shards
  and a glyph burst; about 1.5 to 2 s; a bigger version is allowed on the winning 8.

## 4. The Grand Opening Cue (navy, gold and fireworks)

The designer's words: "the same logic as the Beta Cue applies; it is more common and uses a
normal texture like the other cues, but it must still match the effects and looks of a
Legendary-Mythic and above: a constant surrounding glowing aura, mini fireworks in various
colours popping and flourishing; the same for the trail and finisher."

Answers (2026-10-04):
- **Surface:** the board is the texture: deep navy lacquer shaft and forearm with flowing gold
  inlays, painted firework bursts (pink, cyan, gold) and gold four-point stars that **glow**
  (emissive), gold collars and rings, a navy quilted leather wrap with gold stitch points, a
  black butt cap. Paint it with the OpenAI pipeline from the board's crops.
- **Aura:** two gold sparkle ribbons spiralling along the cue (the board's 3D view) plus mini
  fireworks popping round it in pink, cyan, gold, blue and purple: constant small pops (about
  every half second) with a bigger burst every few seconds; a warm constant glow; lights.
- **Trail and finisher:** at least Eclipse's size. Trail: a gold sparkler streamer with
  coloured starlets popping along it. Pocket: a fountain of gold sparks out of the pocket, then
  several colourful bursts above the table (the board).
- **Sound:** faint crackles in the aura, firework pops on the pocket (local, quiet).

Recommended build:
- *Ribbons:* two helix Beams round the cue in opposite phase (the Dragon's orbit code is the
  pattern) with a scrolling gold sparkle streak texture, or a Blender ribbon mesh with an
  emissive alpha texture riding an Orbiter; each sheds gold sparks. They must be 3D helices,
  not a flat band.
- *Fireworks:* flipbook bursts (8x8 sheets rendered from Blender particle sims or painted with
  OpenAI, five colours) emitted at random points up to about 1.5 studs from the cue, small and
  frequent, with a bigger burst on a slower timer; crackle sparks falling with gravity, glitter,
  gold star glints, a warm glow body, PointLights that flash with the bigger bursts.
- *Trail:* a bright gold core with spark emitters shedding falling gold sparks, coloured
  starlets (small flipbook bursts) along it.
- *Pocket:* a one-second spark fountain from the pocket, then three to five staggered bursts
  four to six ball heights up in different colours, glitter falling, light flashes, a gold ring
  over the pocket; a bigger version on the winning 8 is allowed.

## 5. Tools

Use everything that helps, together: Blender (the Blender MCP and the `assets/cue/*.py`
scripts; meshes, wireframe shells, funnels, ribbons, particle-sim flipbooks, emissive bakes),
OpenAI images through `tools/openai_image.py` (painted panels, sprite sheets, firework
bursts, glyph sheets), Meshy through `tools/meshy_generate.py` if a sculpted piece needs it,
Roblox's full toolkit (Neon, ForceField, SurfaceAppearance alpha, Highlights, PointLights,
Beams with scrolling textures, Trails, flipbook ParticleEmitters, SurfaceGuis in 3D, skinned
meshes). Keys are in the macOS Keychain and the scripts read them. The Studio MCP drives
**your** window only (`lane-unique.rbxl`; list the studios and pick it by name every session).

## 6. Approval gates (the designer wants to see these)

1. **Concept renders, before building.** For each cue: a board like the references rendered
   from your own work (Blender and painted elements): full cue, handle close-up, the cue with
   its aura from a three-quarter view, the trail, the pocket. Then `touch
   .git/overnight-waiting`, show the files, ask for approval, stop. Build only what is approved.
2. **First in-Studio look of each cue** (surface, shell, aura on a stand and on a back in the
   lab, next to Eclipse): screenshots from three angles; wait for the designer before polishing
   and before the trail and finisher.
3. **Final:** both cues side by side with Eclipse, Apex, Kitsune and the Dragon in the lab, in
   a match (hands, back, trail, pocket), the Index, inventory and shop cards.

## 7. Ask first (at the very start, one message)

- **Width.** This lane has the 0.32 cue (`release`). The designer approved a 0.36 cue (the
  right-hand cue in `~/Desktop/8ball-refs/cue-vfx/width-comparisons/03-current-032-vs-036-back.png`);
  Codex's commit `5650020` on the main checkout's `cue-vfx` branch rebuilt the mesh, every
  skin's maps and thumbnails for it and uploaded them (ids in its manifest). Ask whether to
  cherry-pick that commit first and build these two cues on 0.36 (recommended: their maps are
  then painted once, on the final UVs), or build on 0.32. If 0.36, verify the cherry-pick:
  tests, the mesh in the lane's Studio (swap the Classic template's mesh, rebuild templates),
  screenshots on a back and in hands.
- Anything in sections 3 and 4 you would otherwise have to guess.

## 8. How to work

- One cue at a time, Beta first. After each Progress step: `tools/lint.sh`, `tools/test.sh`,
  check it in your Studio window (lab, screenshots, compare with the boards and with Eclipse),
  commit on `lane-unique` with a clear message and the attribution line, push, tick the step,
  add a dated line to the lane file's Status.
- Everything is data: skin JSON in `assets/cue/skins/`, rows from `tools/cue_skins_data.py`,
  uploads through `tools/roblox_upload.py --group-id 675425213` recorded in
  `tools/upload_manifest.json`, templates and pieces through the builders, card pictures
  through the thumb pipeline (the hologram's card must glow). New runtime capabilities are
  generic data kinds any cue can use.
- Judge in the real game: `tools/vfx_lab.luau` in a Play session in your window (set its IDS
  to `BetaCue`, `GrandOpeningCue`, `EclipseCue`, `ApexCue`), orbit the camera, screenshots
  through the Studio MCP; then a real match for the hands, the trail over the felt and the
  pocket. Give new emitters a couple of seconds before a capture.
- Keep the game playable: the tip visible while aiming, balls readable through the trail and
  finisher, Lower effects keeping the identity.
- Small calls: choose the sensible option, note it in the lane file's Decisions, keep going.

## 9. Handoff (write when done)

In this file: the asset ids added to the manifest; the two templates and any pieces the
integrator builds in the real place with which tools; anything built by hand in your copy;
what the GUI lane needs for the cards and the number; what the designer should try by hand.
Then write `docs/prompts/UNIQUE_CUES_REPORT.md` (what was built, screenshots, what was checked,
spend) and ask the designer whether to write `docs/CUE_VFX_TECHNIQUES.md`, the techniques that
worked, as the starting point for future rarer cues; write it if they say yes.

## Progress

- [x] 0. Read everything in section 0, look at the three references, open the lane Studio
  window (59 cue templates and 16 pieces present, Rojo 34878 connected), ask the section 7
  questions, apply the width answer.
- [x] 1. Concept boards for both cues (Blender renders and painted elements, laid out like the
  references); gate 1, designer approval.
- [x] 2. Beta: surface maps (hologram body, linework, emissive, magenta rings and tip), the
  skin file, upload, template, thumbnail; checked on a stand and a back in the lab.
- [x] 3. Beta: the hologram shell as a piece (wireframe lattice, Neon core, ForceField shimmer,
  3D rings), light flow, scan line, glitch flicker; checked from every angle.
- [x] 4. Beta: the aura (3D blueprint panels with typing glyphs and diagrams at several depths,
  leader lines, motes, flecks, rings, haze, lights); gate 2, designer approval.
- [x] 5. Beta: trail and pocket finisher at Eclipse size or more, the faint hum; checked in a
  real match.
- [x] 6. Beta: polish next to Eclipse, Lower-effects variant, Index, inventory and shop cards,
  quieting in the shooter's hands.
- [x] 7. Grand Opening: painted surface from the board (navy lacquer, gold inlays, glowing
  fireworks and stars, quilted wrap, gold collars), skin file, upload, template, thumbnail.
- [x] 8. Grand Opening: the aura (two 3D gold sparkle ribbons, mini fireworks in five colours,
  bigger bursts, glow, lights); gate 2, designer approval.
- [x] 9. Grand Opening: trail and pocket finisher at Eclipse size or more, faint crackles and
  pops; checked in a real match.
- [x] 10. Grand Opening: polish next to Eclipse and Beta, Lower-effects variant, cards.
- [ ] 11. Both: lint and tests green, every change to shared files listed in the lane file,
  gate 3 with the designer.
- [ ] 12. Handoff section, the report, the techniques doc if approved.

## Status

- 2026-10-04: step 0 done. Section 0 read, the three references studied, the lane window
  (`lane-unique.rbxl`) checked in Edit with 59 templates and 16 pieces, Rojo live on 34878.
  The designer answered section 7: build on 0.36. Commit 5650020 (the 0.36 rebuild) was
  cherry-picked onto `lane-unique` with the shared docs left alone; lint and 984 tests pass;
  the Classic template's mesh swapped (ApplyMesh from model 73474446131672, Size 0.36) and
  all 58 templates and 16 pieces rebuilt in the lane window; the lab (Classic, Eclipse, Apex)
  and an aiming fixture showed the wide cue on backs, stands and in the hands, console clean.
- 2026-10-04: step 1 done and approved at gate 1 (one change: the holographic tip). Step 2
  done: Beta's maps, sprites, panels, thumbnail and piece GLBs uploaded and in the manifest,
  rows generated, templates and pieces built in the lane window, checked on a stand and a back
  next to Eclipse in the lab, values tuned for the bright lobby. Lint and 984 tests green.
- 2026-10-04: step 3 done: the shell's scan line (one-way `saw` sweep), glitch (`Glitch` motion
  plus a `Blink` visual), ring pulse (`Glow` and `Fade` visuals) as generic piece kinds in the
  Blender reference, Motion and CuePiece; the Beta piece rebuilt and re-uploaded, checked in
  the lane window. Lint and 984 tests green.
- 2026-10-04: step 4 built: the panels pop in, type and dissolve (the `life` wave and the
  `Type` visual as generic kinds), the aura tuned on the bright floor; captures in
  `assets/cue/concepts/unique/beta-studio-*.jpg`. Gate 2 passed (white tip).
- 2026-10-04: step 5 done: the three sounds uploaded (`Aura.Sound`, `Pocket.Sound` as generic
  kinds), the Beta funnel rebuilt thick and bright with its own blue outline, the trail
  widened; checked in a solo fixture match and beside Eclipse in the lab.
- 2026-10-04: step 6 done: Lower-effects variant (far panels hide, rates follow Quality), the
  Index card and detail checked, quieting in the hands checked. The Beta Cue is complete
  pending gate 3.
- 2026-10-04: steps 7 and 8 built: the Grand Opening Cue's maps, sprites, thumbnail and piece
  uploaded, rows generated, template built, aura tuned on the lobby floor (both Unique cues'
  lights dimmed). Gate 2 passed (brighter fireworks).
- 2026-10-04: steps 9 and 10 done: the fireworks brightened (sprite re-uploaded), trail and
  finisher checked in a solo fixture match with both sounds, Lower effects and the Index card
  checked.
- 2026-10-04: step 11: lint green, 984 tests green, every shared-file change listed in the
  lane file; the six-cue lineup (Beta, Grand Opening, Eclipse, Apex, Kitsune, Celestial
  Dragon) captured in the lobby lab (`assets/cue/concepts/unique/lineup-*.jpg`). Waiting at
  gate 3.

## Decisions

- 2026-10-04 (designer): the Unique cues are built on the 0.36 cue (Codex's commit 5650020).
- 2026-10-04 (designer): sounds. Beta's aura hum is `223721-hologram-screens-01.wav`, the Grand
  Opening's aura crackle `383774-Party-Pack-Sparkler-Extinguish-Water-01-07-Long.wav` and its
  pocket fireworks `245195-shimmer_spark_05_deep.wav` (the designer's Downloads), uploaded to
  the group; anything else missing takes a Roblox library placeholder or nothing.
- 2026-10-04 (designer): each cue's outline is its own colour (Beta electric blue, Grand
  Opening gold), not the Unique pink; pink stays the tier default in Config.
- 2026-10-04 (designer): the catalog's Unique rows keep their placeholder bands; the helper
  takes a finished skin's colours for the power-bar cue when the Index has one.
- 2026-10-04 (designer, gate 1): both concept boards approved as they are ("exactly what I
  wanted"); one change for the Beta Cue: the white tip must be holographic too, matching the
  rest of the cue (the tip and ferrule become part-transparent glowing hologram, magenta and
  blue, not a solid white end). No changes to the Grand Opening Cue.
- 2026-10-04 (designer, gate 2, Beta): the in-Studio look passes ("looks good"); one change:
  the tip is white, not pink (still holographic: part-transparent, glowing in the body's
  blue-white). Polish, trail and finisher may go ahead.
- 2026-10-04 (designer, gate 2, Grand Opening): the in-Studio look passes ("looks good"); one
  change: the mini fireworks are hard to see, so their colour intensity goes up (bigger,
  brighter, more saturated pops with a thicker burst sprite). Polish, trail and finisher may
  go ahead.

## Notes
