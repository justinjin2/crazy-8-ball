# Cue VFX upgrade pass

**2026-10-04 — APPROVED. Width rebuild verified; Eclipse is next.**

Branch: `cue-vfx`, created from `release` at `d3b6c57`. Work in the main
`~/Desktop/8ball` checkout and main Studio place, with Rojo on 34872. This brief supersedes
the older cue-skins brief wherever they disagree. Accepted interview decisions are recorded
below. The art interview is complete. The designer approved this brief with “begin” on 2026-10-04.

## 1. The visual ladder

The cue is a collectible players should immediately want to own. Every Rare must have an
obvious aura in the bright rooftop lobby, on a moving player's back and in the hands. Each
higher tier must be recognizably more impressive without needing its rarity label.

| Visual level | What it must feel like |
|---|---|
| Common | Good surface art and the existing simple white trail; no new aura. |
| Uncommon | Existing small glow and tinted trail; no additional VFX layers. |
| Rare | One strong themed silhouette around the cue, supporting accents, a distinctive short trail and a small themed pocket burst. Clearly visible at ordinary lobby distance. |
| Epic | Larger, layered and constantly moving: an outer form, inner movement and small accents. A composed pocket sequence, visibly above Rare. |
| Legendary | Premium: a signature sculpted form or ornament, animated surface and substantial finisher. Beautiful shape and controlled motion, not just more particles. |
| Mythic | Show-stopping: a living creature, elaborate mechanism or equivalent animated spectacle. Expressive movement, rich surface, layered aura and a spectacular finisher. |
| Secret standard | The highest visual standard: an unmistakable, carefully staged spectacle beyond Mythic. Eclipse remains the case Secret; Beta is Unique. Both get the same highest visual quality with distinct signature effects; Beta is intended to be rarer to own. |

The painted fire-slash reference establishes **shape, painted edges, negative space and
layering**, not a fire theme for every cue. Build a large readable form, contrasting inner
forms, crisp detached accents and restrained atmospheric support. A soft glow cloud does not
count as the main form. Bright cores must retain colour and structure in the real daylight.
Use dark or saturated painted contours where they help; do not blacken the entire cue.

Keep each cue's identity and palette. Theme-specific exceptions are deliberate: Beta's
blueprint lines are precise drafted graphics; Apex is mechanical; Grand Opening is fireworks.
They still need the same authored shapes, hierarchy and clean motion. All-ages imagery: no
gore, brands, borrowed characters or religious crosses.

## 2. Confirmed scope and taste

- **Width approved: 0.36-stud butt**, up from 0.32 (+12.5%), length 7, tip 0.09. Preserve
  the slim front from the approved comparison. Width is the first production step.
- Upgrade all 30 case cues from Rare through Secret. Common and Uncommon receive the mesh,
  map and thumbnail rebuild only; preserve their existing effect content.
- Build **Beta** and **Grand Opening** from scratch, for this release, from the supplied
  references. Both remain **Unique**, not case drops. Beta is intended to be the rarest owned
  cue, with Secret-quality visuals. Grand Opening gets Mythic-quality visuals. Both are
  limited and never return after their sale. **Founder's Cue is cancelled**, not deferred.
- Rank equivalents: Bronze Common; Silver Uncommon; Gold and Platinum Rare; Diamond and
  Expert Epic; Veteran and Master Legendary; Grandmaster Mythic; Reyes above ordinary Mythic
  but below Eclipse. Starter Rare; VIP Epic. These are visual levels, not changes to their
  catalog rarity, rank requirements or earning rules.
- Upper-tier lobby effects may frame the upper body, remaining centred on the cue. Preserve
  the existing carry-follow behaviour: no long smeared aura left behind a walking player.
- Keep a restrained aiming version. Quiet nearby table participants on the shooter's screen;
  preserve the existing viewer-specific rule and elevated-cue visibility protection.
- Keep the current short-trail feel (runtime currently caps trail lifetime at 0.45 s).
  Improve artwork, shape and motion rather than restoring the old long streaks.
- Finishers may rise above the pocket and the legal winning 8 gets a bigger version. They
  clear promptly, leave rolling balls readable and do not take the camera or change the sky.
- Creatures and ornaments may be rebuilt for quality. Kitsune stays pastel pink. Eclipse
  keeps black/gold/violet and may regain a grand silhouette if it behaves correctly.
- VIP is mainly gold with restrained rainbow accents. **Crowns belong to Reyes alone in
  the cue collection**: remove VIP crown art/particles and crown motifs on other cue skins.
  This does not redesign unrelated rank badges, winner UI or purchased lucky-block models.
- Faint, local sounds are allowed. A tiny flourish on an actual Inventory cue change is
  optional, reused from the cue's own assets and omitted if it delays the core work. No new
  flourish every time the same cue moves between hands and back; no continuous aura hum.
- Visual quality takes priority within a sensible performance balance. Lower effects must
  retain the identity and tier ladder. Designer will test on an iPhone; model is unspecified.
- Standing authorization: existing paid generation APIs and all necessary Roblox uploads to
  **group 675425213** are approved after brief approval, with no per-batch questions. Ask only
  for an important unsettled design decision or a new purchased tool/key. Never expose keys.
- The designer will handle saving `place/8ball.rbxl` and publishing. Secret pull-cutscene
  redesign is mentioned as separate upcoming work and is not part of this cue-effects pass.

### Reference files

- [Painted VFX language](../../assets/cue/concepts/vfx-upgrade/painted-vfx-reference.webp).
- [Beta: hologram and blueprints](../../assets/cue/concepts/vfx-upgrade/beta-reference.png).
- [Grand Opening: fireworks](../../assets/cue/concepts/vfx-upgrade/grand-opening-reference.png).
- Approved width comparison: `~/Desktop/8ball-refs/cue-vfx/width-comparisons/03-current-032-vs-036-{back,hands}.png`.
  These are proportion studies, using temporary edited meshes and captured avatar poses in
  Edit-mode lobby daylight. They are not proof of final UVs, grip fit or collision clearance.

## 3. Width first: the complete rebuild

1. Snapshot the current shape-2 envelope, skin JSON and piece definitions before migration.
   Set Config and its profile to the approved shape. The comparison held the first 2.1 studs
   unchanged, eased radial gain through the next 1.75 studs and used 1.125 gain thereafter.
   Match that silhouette with a monotonic Config profile; do not simply scale the tip or
   increase the butt number without refitting the profile. CueShape remains the common source
   for the mesh, fallback, hand placement and rail clearance.
2. Export `Shape.json`, rebuild through `assets/cue/CueModel.py`, run its geometry and UV
   checks, rebuild the paint kit. Repaint/remap all **59 existing skins**, including Classic,
   on the new UVs. Reuse good AI panel art; regenerate art only where the mapping or quality
   requires it. New Beta and Grand Opening art starts on this final shape.
3. Rebuild all thumbnails, checking `THUMB_THICKEN` against the actual new cue so the pictures
   neither exaggerate nor hide the change. Check the Index and power-bar cue too.
4. Version `tools/cue_widen.py` for a **shape 2 -> 3** migration. Its current shape-1 baseline
   and stamp 2 cannot be reapplied. Preserve gaps above the old surface, attachments, beam
   widths and orbit radii; a second run must make no changes. Do not blindly rerun
   `cue_vfx_v2.py`, which would replace later authored fixes with old recipes.
5. Refit and rebuild every existing 3D piece, bone/path clearance and surface overlay;
   preserve useful clearances rather than enlarging an entire creature unnecessarily.
   Refresh generated Segment hosts for the dragon and phoenix from the rebuilt assets.
6. Upload through `tools/roblox_upload.py --group-id 675425213`, record asset and resolved
   image IDs in `tools/upload_manifest.json`, generate rows with `tools/cue_skins_data.py`.
   Replace the Classic mesh template explicitly, then rebuild other templates and pieces with
   the existing builders. The template builder deliberately leaves Classic untouched.
7. Run lint/tests, verify Rojo, then inspect the final mesh on the back, while walking,
   seated, aiming, pulling and striking, at rails, with extreme spin and elevated cues.
   Check the skin seam and rings close up. Test ordinary and small avatars, phone camera and
   gamepad views. No ball physics, shot outcomes or actual cue impact properties change.

Width acceptance: actual 0.36 butt and unchanged slim tip; consistent mesh and mathematical
envelope; passing cue-shape, mesh, stance and clearance tests; no new rail, ball, body or
piece intersections. All subsequent VFX is judged on this final width.

## 4. Runtime work required by the art

Extend the existing systems generically and only where a planned effect needs it. Every
cue remains data plus assets: skin JSON -> generated CueSkins rows -> shared rendering code.
No `if cueId == ...` effect implementations. Global tuning belongs in Config; per-cue authored
curves and layer values remain in their skin data as in the established pipeline.

- **Quiet and reduced variants:** classify essential silhouette/surface, secondary structure
  and fine accents in data. Apply viewer quieting and Lower effects coherently to emitters,
  moving/aura beams, orbiters, arcs, lights, animated pieces and pocket bursts. Keep a readable
  reduced shape. Fix the current conflict between a quiet rate captured after quality scaling
  and Quality.Changed resetting the emitter's base rate; repeated toggles must not compound.
- **Sculpted effects:** support reusable mesh/ribbon animation and staged finisher layers as
  needed for painted slashes, water curls, blueprint planes and firework sweeps. Use shared
  timelines for coherent motion. Static surfaces and outlines must not obscure the cue art.
- **Beta surface:** add a data-driven material/transparency treatment for its partially
  transparent body and opaque-bright drafted contours. Test transparent sorting on the back,
  through moving layers and in the Index. Use sparse shells, not stacks of transparent tubes.
  Do not dim every surface simply to obtain a hologram.
- **Winning 8 variant:** select from the accepted shot judgement; ordinary legal pots retain
  their usual version. Never celebrate scratches, an early/illegal 8 or a losing shot. Avoid
  multiplying overlapping finishers during a multi-pot shot into a screen-covering mass.
- **Sound and equip:** optional data-driven cues, local range, conservative volume, shared
  cooldowns and existing sound settings. Existing pool clacks and pocket sounds stay clear.
  Equip flair triggers on a genuine equipped-item change after loading, not a carry swap.
- **Loading/lifecycle:** retain warmup, one-frame skin swaps and pocket preloading. No grey
  creature flashes, beams at the origin, detached parts, stale pooled effects or leftover
  connections. Add any new sprite/surface/mesh roles to the common preload path.
- **Performance:** keep one shared update mechanism, reusable hosts and pooled components.
  Cull invisible/distant effects and simplify secondary geometry/animation where appropriate.
  Measure transparent screen coverage, draw calls, geometry, active particles and frame-time
  spikes; particle count alone is not a performance budget. Eight auras is a required scene.

Test changes to shared lifecycle/quality/winning-shot logic meaningfully. Do not add tests
that merely repeat authored colours or particle counts. Run the existing complete suite
after each completed production step/cue, as requested.

## 5. Tools and common Studio acceptance

Tool abbreviations in the cue plans:

- **Paint:** OpenAI Images via `tools/openai_image.py` for painted sprite masters, theme art,
  creature concepts and surface panels. Inspect all outputs; curate and clean them. Do not
  accept an incoherent generated flipbook just because it has the correct number of cells.
- **Blender:** deterministic animated meshes, curves, rigging, emissive baking, coherent
  flipbook renders from approved art, atlases, UVs, maps, thumbnails and LODs. Meshy is useful
  for organic creature forms; Blender is preferred for exact technical geometry and rigs.
- **Meshy:** `tools/meshy_generate.py`, preferably curated image/multi-image input when a
  rebuilt creature will benefit; retopologize, clean, rig and finish in Blender.
- **Wire:** JSON authoring, generators, uploads/manifest, template and piece builders, then
  real Studio captures. This is required for every row, even where omitted for brevity.

**Every cue must pass checks L, H, P and Q below on PC and phone emulation.** Its individual
plan adds a specific comparison or risk check. Include gamepad view/input regression checks;
MCP keyboard-synthesized pad keys are not evidence of a physical controller test.

- **L — Lobby:** use `tools/vfx_lab.luau` in Play, adjusted to a verified clear lobby location
  (its old coordinates now intersect map props). Back, stand and walking views in bright day,
  then sunset. Judge near and normal social distance; compare with the reference and the
  tier directly above and below. Record a still and a short motion sample, not a lucky frame.
- **H — Hands:** a real playable match using the final mesh: the shooter's ordinary/close
  view and an observer view; aim, full draw, stroke, moving back cue, raised-cue case. Inspect
  restrained variants, grip, tip/ball visibility and camera-facing layers from either side.
- **P — Play:** actual ball trail over green, raspberry and slate cloth, plus blue arena
  cloth; short and hard shots, multi-pot and legal winning-8 finishers. Also check an illegal
  8 and scratch produce no special win celebration. Synthetic QA fixtures are labelled as
  fixtures and supplement, not replace, real gameplay checks.
- **Q — Quality:** repeat with Lower effects on/off, including toggling during quiet mode and
  a live burst. Eight mixed and eight top-tier auras in view; walk and equip repeatedly;
  check memory/instance cleanup, load behaviour, console and frame times. Real iPhone check
  by the designer remains explicitly pending until performed. Studio emulation is not an
  iPhone GPU benchmark; account for unfocused Studio's frame-rate cap when measuring.

Starting performance targets from the interview are 60 FPS on capable devices and steady
30 on weaker devices, not a claimed certification. Prefer reducing invisible work and tiny
accents before damaging the cue's main form. Do not lower scene-wide graphics to make one
cue pass. The user's visual-quality preference does not excuse a crowded-lobby regression.

## 6. Secret-standard cues

### Eclipse — Secret

- **Today:** obsidian/gold surface, floating dark sphere, precessing rings, moon/planets and
  asteroid pieces; small eclipse/corona against dense violet space haze and stars. Black/gold
  trail with chips/sparks and residual fire accents; layered eclipse pocket burst, no 3D
  pocket centerpiece. The former giant eclipse was reduced; later fixes are the baseline.
- **Aura and particles:** rebuild a broad, clean black eclipse silhouette with a thin
  white-gold edge, painted prominence arcs, two clearly separated orbital paths and a deep
  violet galaxy curl behind it. Sparse stars and tumbling chips provide depth. The silhouette
  can frame the upper body; it must never read as a solid black screen pasted over the avatar.
- **Trail:** short crescent-edged black/gold wake, an inner violet star channel and a few
  detached celestial fragments. Remove generic ball fire in favour of consistent space art.
- **Finisher:** a compact dark aperture opens, a dimensional eclipse rises/turns inside a
  sharp corona, orbital arcs sweep once and resolve into stars. Winning 8 expands the orbital
  reveal and adds a second staged corona sweep, without a sky/camera change.
- **Surface and pieces:** richer obsidian and metallic inlay contrast; slowly travelling
  molten-gold veins, sculpted ring geometry and deliberate planet/asteroid paths. Preserve
  dark material readability under glow. Rebuild instead of enlarging the old cloud.
- **Tools/check:** Paint + Blender + Wire; L/H/P/Q, above all Mythics, especially Grandmaster.
  Test 360-degree corona alignment, near-camera overlap and eight simultaneous eclipses.

### Beta — Unique, Secret visual standard; new from scratch

- **Today:** a placeholder band cue, no finished skin or blueprint effect. It replaces the
  cancelled Founder's release role. Acquisition and sale rules are outside this art pass.
- **Aura and particles:** floating, staggered blueprint planes with cue section diagrams,
  drafting arcs, crosshairs and construction lines. A large clean schematic ring assembles
  around the back half, with smaller planes rotating or sliding into alignment. Electric blue
  is dominant; magenta is concentrated at joints and important pulse intersections. Use
  sparse points/short line fragments, not illegible text or green code rain like Hacked.
- **Trail:** a short extruded wireframe wake, drafted cross-sections peeling away and a
  magenta tracer running through the blue structure. Keep the white ball fully readable.
- **Finisher:** the reference's wireframe funnel grows from the pocket, segmented rings
  travel upward and a broad magenta rim locks into a clean circular blueprint; the geometry
  disassembles into line fragments. Winning 8 adds an outer schematic assembly and a final
  controlled sweep. No black background panels in the world.
- **Surface and pieces:** a genuinely partially transparent cue body, bright blue contour
  wires and section rings, technical grid/diamond wrap and magenta collars; preserve the real
  tip and a stable readable silhouette. Create original mesh layers, alpha/emissive maps and
  animation from the supplied reference. Use thicker major lines than the concept's tiny
  annotations so it works on cream floor and phone. No permanent mounting block or creature.
- **Tools/check:** Paint for surface art + Blender for exact drafted meshes, line atlases and
  animation + Wire. L/H/P/Q, compare Eclipse and Hacked; verify transparency from all angles,
  bright-floor contrast, hands through the body, no panel covering the ball and reduced-mode
  blueprint readability. Match Eclipse's highest visual standard without copying its forms.

## 7. Mythic-standard cues

### Celestial Dragon — Mythic

- **Today:** pearl/gold/sapphire cue, a rigged whole spirit dragon swimming a tip-to-butt
  loop, animated head/jaw/mane, dense blue mist and starlight; starlight trail; rising rigged
  dragon pocket finisher. Current source is the calmer v2 treatment, not the old static coil.
- **Aura and particles:** a clearly drawn swimming dragon with layered blue-white flame fins,
  pearl/gold highlights and a few broad celestial brushstroke curls following its path.
  Star points mark changes of direction; reduce shapeless mist hiding the face and body.
- **Trail:** scalloped starlight wake with scale/fin-shaped accents and a tapering white-blue
  core. **Finisher:** the dragon rises in a readable S-curve, opens its jaw, sweeps its mane
  and releases a star arc; winning 8 gets a larger full-body reveal and longer graceful exit.
- **Surface/pieces:** preserve the pearl/navy/gold identity; improve scale and lattice maps.
  Rebuild the creature if needed for face quality and flowing motion; keep its path and tail
  fluid and its snout safely short of the tip. Use painted luminous spirit material with
  clear contours, rather than the current indistinct hologram/cloud treatment.
- **Tools/check:** Paint + Meshy if useful + Blender rig/paths + Wire; L/H/P/Q; compare
  Phoenix and Eclipse, inspect every turn in the swim loop and head/tip clearance.

### Kitsune — Mythic

- **Today:** porcelain/crimson/gold cue, fox mask, nine beam tails and a small running fox;
  v2 pastel-pink foxfire/clouds/petals, trail artwork inherited from earlier violet foxfire,
  and a rising rigged nine-tailed fox pocket piece.
- **Aura and particles:** a readable fox galloping through a fan of nine sculpted pink spirit
  tails, each with a darker pink edge and warm white inner brushstroke. Petals and small foxfire
  beads punctuate movement. No opaque pink cotton cloud around the entire animal.
- **Trail:** petal-edged pink foxfire with pale-gold sparks; align every remaining violet
  legacy texture with the accepted pink palette. **Finisher:** the fox springs upward, spreads
  its nine tails and looks back as petals curl around it; the winning 8 gets the full tail fan.
- **Surface/pieces:** refined porcelain mask, crimson markings and pink blossom emissive;
  rebuild mask/fox/tails as needed. Tail movement must read as separate flowing forms and the
  running animal must have a convincing stride rather than spinning like a charm.
- **Tools/check:** Paint + Meshy as needed + Blender + Wire; L/H/P/Q; compare Sakura and
  Dragon, count/read nine tails, inspect silhouette at phone size and animation intersections.

### Apex — Mythic

- **Today:** steel/orange/cyan cue, articulated three-claw mechanism, rotating lens, thrusters,
  HUD rings and data motes; jet trail; targeting-reticle/column pocket burst without a 3D piece.
- **Aura and particles:** articulated energy rails and angular cyan/orange thrust fins around
  the mechanism; timed scanner rings lock, claws react and vents pulse. Sparse hot chips and
  geometric fragments support a solid mechanical silhouette, distinct from Beta's blueprints.
- **Trail:** short shock-diamond jet wake with angular orange fins and cyan compression rings.
  **Finisher:** a dimensional mechanical aperture unfolds above the pocket, locks a reticle,
  then releases a tightly shaped reactor plume; winning 8 adds a wider segmented assembly.
- **Surface/pieces:** improve bevels, armour segmentation, dark metal and emissive recesses.
  Rebuild the mechanism and its actions where useful; this stays mechanical, not an animal.
- **Tools/check:** Blender hard-surface/rig/flipbooks + Paint masks + Wire; L/H/P/Q; compare
  Clockwork and Beta, verify mechanical articulation and readable cyan/orange balance.

### Grand Opening — Unique, Mythic visual standard; new from scratch

- **Today:** black/gold/green placeholder bands and no finished firework skin. Acquisition
  and sale configuration are outside this art pass and remain untouched.
- **Aura and particles:** two flowing warm-gold celebratory ribbons around a navy cue,
  with staggered cyan and magenta firework blossoms. Each firework has a bright launch point,
  distinct expanding spokes and a short sparkling decay. Keep a legible flourish present
  between bursts without running eight overlapping explosions continuously.
- **Trail:** gold spark streamer with occasional cyan/magenta starlets, matching the reference.
  **Finisher:** a gold fountain rises from the pocket then opens into a composed cluster of
  blue, pink and gold fireworks; winning 8 adds a brief staged finale above the same pocket.
- **Surface/pieces:** original deep-navy lacquer, gold flowing inlays and collars, quilted navy
  wrap with tiny gold star stitching, cyan/magenta firework art on forearm/sleeve. Animate the
  surface blossoms and ribbon highlights. Build curved ribbon geometry where it beats flat
  particles. No crown, creature or unrelated ornament; fireworks supply the Mythic spectacle.
- **Tools/check:** Paint + Blender ribbon meshes/coherent firework flipbooks/maps + Wire;
  L/H/P/Q; compare Disco, Shooting Star, Chroma and the three Mythics. Test bright-day colour,
  overlapping firework bursts and restrained aiming on every felt.

## 8. Legendary case cues

### Chroma

- **Today:** animated rainbow surface, orbiting crystal pieces and four colourful ribbons;
  rainbow glitter trail and rays/shards pocket burst.
- **Aura/particles:** a prismatic crystal arrangement with broad, painted spectrum arcs
  passing behind sharp facets; distinct hue bands and sparse lens-like sparkles.
- **Trail/finisher:** a short separated-spectrum ribbon with angular flecks; pocket crystals
  unfold into a dimensional prism bloom, refract a single sweep and collapse to glitter.
- **Surface/pieces:** preserve rainbow animation but stop colours merging into white;
  rebuild/refit crystals with clear facets and synchronized rotation. No crowns.
- **Tools/check:** Paint + Blender crystals/ribbons + Wire; L/H/P/Q; must exceed Prism while
  staying unlike Reyes and Grand Opening; check facet visibility at every camera angle.

### Clockwork

- **Today:** turning 3D brass cogs and axle details, steam, sparks, brass loops; amber trail
  and rising 3D cog finisher.
- **Aura/particles:** a readable miniature orrery of meshing gears and etched time arcs;
  steam escapes in small shaped puffs at deliberate mechanical beats, with hot brass flecks.
- **Trail/finisher:** segmented amber timing marks and a short steam curl; pocket cogs rise
  in an interlocking stack, engage, turn once and release a clock-hand sweep.
- **Surface/pieces:** deep brushed brass, dark recesses, travelling dial marks; refine teeth,
  axle alignment and speed relationships. Preserve clear gaps around the wider cue.
- **Tools/check:** Blender machinery/motion + Paint steam/engraving + Wire; L/H/P/Q; compare
  Apex and Epic structured effects; verify gear relationships and no clipping teeth.

### Infernal

- **Today:** skull ornament, hellfire, smoke and fire ribbons; black/red trail and an eruption
  with a rising skull piece.
- **Aura/particles:** the reference's sharp painted flame language at Legendary scale:
  forked red-black outer tongues, bright orange inner blades, narrow hot cores, detached embers
  and smoke behind the skull. A threatening but all-ages face remains readable.
- **Trail/finisher:** a short torn flame wake; a jagged seal cracks into a skull-shaped rising
  eruption, with staged flame fans and a clean ember decay.
- **Surface/pieces:** obsidian/charred metal relief, animated heat cracks and a refined skull
  with lit cavities. Rebuild through Meshy only if it improves the actual visible silhouette.
- **Tools/check:** Paint + Blender + optional Meshy + Wire; L/H/P/Q; unmistakably above
  Blaze/Magma, unlike Phoenix's feathers; inspect skull readability through the fire.

### Kraken

- **Today:** four segmented purple tentacles with cyan suckers, bubbles and ink; inky water
  trail; tentacles rising from a splash/ink pocket effect.
- **Aura/particles:** flowing tentacles with coherent curls, cyan sucker accents, a broad
  painted deep-blue water spiral and small suspended bubbles. Ink provides depth behind it.
- **Trail/finisher:** short curling water/ink wake with bright foam edges; a pocket whirlpool
  opens, tentacles uncoil around its rim and snap inward under a shaped splash.
- **Surface/pieces:** wet purple/abyssal material and controlled bioluminescence; replace
  visibly jointed blocks with smoother rigged forms where necessary, avoiding excessive bones.
- **Tools/check:** Blender sculpt/rig + Paint water/ink + optional Meshy + Wire; L/H/P/Q;
  compare Tidal and Void, test tentacle/body/rail intersections and distinguish ink from shadow.

### Phoenix

- **Today:** animated 3D wing pieces with segment-hosted flame and feathers; feather trail;
  rising rigged firebird finisher.
- **Aura/particles:** layered flame-feather wings with crisp red-orange outer shapes and
  golden inner vanes; a coherent wingbeat throws a few curling feathers and embers.
- **Trail/finisher:** a short feather-edged golden wake; a firebird rises, spreads both wings
  in one strong beat and dissolves outward into feathers.
- **Surface/pieces:** rich feather inlays with travelling fire veins; improve feather
  thickness, wing articulation and the pocket bird's face/body, preserving the cue grip zone.
- **Tools/check:** Paint + Blender wings/rig + Meshy if needed + Wire; L/H/P/Q; compare
  Infernal and Dragon, confirm wingbeat silhouette and no sheet-like edge-on disappearance.

### Seraph

- **Today:** 3D halo, feathers, motes, gold light and three ribbons; light trail and a luminous
  feather/column finisher without a creature.
- **Aura/particles:** a refined halo with sculpted feather-shaped light fans and broad ivory
  brushstroke ribbons. Gold framing and soft blue shadows keep white forms legible by day.
- **Trail/finisher:** a short layered feather wake; a halo rises above the pocket as feather
  fans open underneath, then sweeps closed into falling gold-white accents.
- **Surface/pieces:** pearl and gold inlay, softly travelling feather veins, dimensional halo
  and luminous feather fans. No cross, crown or generic white bloom ball.
- **Tools/check:** Paint + Blender halo/fans + Wire; L/H/P/Q; compare Phoenix and Dragon;
  bright-floor contrast and reduced-mode silhouette are the deciding tests.

### Thunderstrike

- **Today:** crawling/leaping arcs, storm cloud/static and charge particles; lightning trail;
  bolt/chip/static pocket finisher, no 3D ornament.
- **Aura/particles:** thick branched painted bolts wrapping a sculpted storm spine, offset
  dark-blue strokes behind pale electric cores; a few charged chips and shaped storm curls.
- **Trail/finisher:** short forked electrical wake with detached sparks; an arcing charge
  forms above the pocket, discharges downward and sends a low jagged ring outward.
- **Surface/pieces:** charged cracks run through dark metal; add small floating conductive
  fragments/bolt forms as the signature 3D structure without hiding the shaft.
- **Tools/check:** Paint bolt masters + Blender curved bolt meshes/animation + Wire;
  L/H/P/Q; visibly above Plasma; avoid rapid full-white flickering and flat noisy lightning.

## 9. Epic case cues

### Aurora

- **Today:** four aurora ribbons, veil/motes/sparkles, flowing surface and a custom trail;
  no substantial authored pocket sequence.
- **Aura/particles:** two or three wide, pleated polar-light curtains with distinct cyan,
  green and violet bands, dark cool undersides and sparse stars; continuously folding motion.
- **Trail/finisher:** short layered aurora ribbon; pocket curtains rise in a small fan, ripple
  once and release star points. **Surface/pieces:** slowly travelling polar bands; lightweight
  curved ribbon meshes where needed, no permanent creature or ornament.
- **Tools/check:** Paint + Blender ribbons + Wire; L/H/P/Q; above Neon, below Chroma;
  colours must remain separated on light floor and green felt.

### Blood Moon

- **Today:** red motes/flame, moon glow, two tendrils and arcs; crimson trail and moon/mist burst.
- **Aura/particles:** a crimson crescent with black-red painted moon ribbons and pale-red
  star points; slow tidal motion around the cue, no gore or dripping blood.
- **Trail/finisher:** a short crescent-cut crimson wake; a moon disc rises through a low
  ribbon ring and dissolves into red motes. **Surface/pieces:** moving lunar markings and
  dark lacquer; thin dimensional crescent effect mesh rather than a bulky ornament.
- **Tools/check:** Paint + Blender crescents + Wire; L/H/P/Q; compare Phantom and Eclipse;
  preserve red identity on raspberry felt and avoid a miniature Eclipse clone.

### Disco

- **Today:** four orbiting spotlights, mirror glints and light specks; coloured wisp and confetti/rays burst.
- **Aura/particles:** choreographed coloured light fans and mirror-tile sparkles with a clear
  rotating disco pattern; beat-like sweeps without real flashing lights across the whole room.
- **Trail/finisher:** short tiled-spectrum wake; pocket light fans sweep once beneath a
  compact glitter/confetti blossom. **Surface/pieces:** moving mirror-facet highlights;
  lightweight reflective tile accents, not fireworks or a crown.
- **Tools/check:** Blender facet/light-fan geometry + Paint accents + Wire; L/H/P/Q; compare
  Candy and Grand Opening, reject strobing and white additive washout.

### Hacked

- **Today:** green digit rain/glitch fragments and three data streams; data trail with digits;
  no substantial authored pocket sequence.
- **Aura/particles:** chunky broken green terminal ribbons, deliberate stepped offsets and
  blocks that decompile/reassemble around the cue; sparse symbols large enough to read as
  graphic marks. **Trail/finisher:** short glitch slices; pocket grid assembles, corrupts and
  breaks into squares. **Surface/pieces:** scrolling code masks and controlled scan resets;
  flat/volumetric block accents, no blue drafting plans or transparent cue body.
- **Tools/check:** Paint graphic masters + Blender block animation/atlas + Wire; L/H/P/Q;
  compare Neon and Beta; no flickering entire cue or tiny unreadable detail as the main effect.

### Magma

- **Today:** lava drips, flame licks, smoke and embers; lava trail and glob/flame/smoke pocket burst.
- **Aura/particles:** thick molten curls bordered by dark cooling crust, floating crust chips
  and slower heat pulses, distinct from Blaze's fast flame. **Trail/finisher:** short viscous
  molten wake; a pocket lava swell cracks open into glowing lobes, then cools to dark fragments.
- **Surface/pieces:** animate light beneath basalt cracks; small crust meshes with sparse
  smoke behind. **Tools/check:** Paint + Blender lobes/crust/flipbooks + Wire; L/H/P/Q;
  compare Blaze and Infernal; lava stays orange rather than yellow-white over green cloth.

### Prism

- **Today:** four refracting orbit ribbons, shards, glints and haze; colourful wisp and shard/ray burst.
- **Aura/particles:** crisp triangular refractions splitting into a few broad colour fans,
  with a smaller set of orbiting shards. **Trail/finisher:** short three-band prismatic wake;
  a pocket crystal fan opens and throws separated colour wedges before fading.
- **Surface/pieces:** clean glass/facet masks with a moving spectral sweep; lightweight
  effect shards, below Chroma's elaborate crystal structure. **Tools/check:** Paint + Blender
  facets + Wire; L/H/P/Q; compare Neon/Chroma, keep negative space and distinct spectrum bands.

### Shooting Star

- **Today:** five orbiting comets, two star-stream beams and twinkles; wisp and star pocket burst.
- **Aura/particles:** fewer but stronger painted comet heads with tapered gold-blue tails,
  crossing at different depths and leaving sparse star sparks. **Trail/finisher:** a short
  bright comet wake; a compact pocket star launches and blooms into a ring of smaller stars.
- **Surface/pieces:** constellation points illuminate along dark blue inlays; curved comet
  effect meshes as needed, no permanent ornament. **Tools/check:** Paint + Blender motion
  curves + Wire; L/H/P/Q; compare Aurora/Grand Opening, distinguish comets from fireworks.

### Toxic

- **Today:** bubbles, goo drips and fumes, a glow beam; custom goo trail; no substantial authored finisher.
- **Aura/particles:** glossy lime goo lobes and scalloped vapour curls with dark green edges,
  a few large rising bubbles and tiny droplets. **Trail/finisher:** short broken goo ribbon;
  pocket bubbles swell, pop into a shaped splash and leave a brief low vapour curl.
- **Surface/pieces:** luminous liquid channels in the existing dark surface; small moving
  liquid meshes where needed. **Tools/check:** Paint + Blender liquid/bubble shapes + Wire;
  L/H/P/Q; compare Nature and Kraken, test dark outlines against green felt.

### Void

- **Today:** inward-drifting dark matter, rocks, two beams and two orbit ribbons; smoke trail;
  no substantial authored pocket sequence.
- **Aura/particles:** torn violet-black space folds with luminous cut edges, a few floating
  rocks and inward-flowing points; an angular rift silhouette, not Eclipse's round solar form.
- **Trail/finisher:** short split-edge void wake; a narrow pocket rift opens, pulls its own
  decorative fragments inward and seals. **Surface/pieces:** travelling dark violet fractures;
  layered rift meshes and rock accents. **Tools/check:** Paint + Blender + Wire; L/H/P/Q;
  compare Phantom/Eclipse; the effect never visually swallows unrelated moving balls.

## 10. Rare case cues

Each Rare gains a small authored finisher rather than only a recoloured default burst.
Each has a bold main aura form and a few accents; none needs a creature. All use Paint for
theme-specific sprite/trail art, Blender where curved geometry or coherent flipbooks help,
and Wire. All pass L/H/P/Q plus the comparisons below.

### Blaze

**Today:** flame flipbook, heat beam and embers; coloured trail, default pocket treatment.
**Upgrade:** sharp painted orange/red flame tongues around the back half with bright inner
strokes and detached embers; a short torn-flame trail; pocket flame fan and ember snap.
Flickering surface heat follows the flame rhythm. Small curved flame cards only if needed;
no permanent ornament. Check against Magma/Infernal and bright cream floor.

### Candy

**Today:** two striped orbit ribbons, sprinkles and sugar haze; coloured trail/default pocket.
**Upgrade:** broad twisting candy-striped ribbons with glossy pink/cream folds, a few
sprinkles and sugar glints; short striped trail; a pocket ribbon curl opening into confetti.
Surface stripes receive travelling highlights. Lightweight ribbon geometry, no creature.
Check against Disco and Kitsune; playful candy must not read as pink foxfire.

### Frostbite

**Today:** snowflakes, cold mist/glints, frost beam and two orbit ribbons; coloured trail/default pocket.
**Upgrade:** jagged blue-white frost fins with dark cyan edges, drifting snowflakes and small
crystal chips; short serrated frost trail; pocket ice rosette breaking into flakes.
Surface frost veins brighten slowly. Thin crystal/frost effect meshes if useful. Check
against Aurora/Seraph; white cores must retain their blue outline in daylight.

### Honeycomb

**Today:** bees, honey drops/glints, honey halo and ribbon; coloured trail/default pocket.
**Upgrade:** readable amber hexagonal honey panels and a thick curling honey ribbon, with
small bee paths and occasional drops; short segmented amber trail; a pocket honey blossom
and honeycomb ring. Surface cells fill with moving warm light. Simple hex/ribbon geometry;
keep bees charming and sparse. Check against Gold/Clockwork for a distinct organic identity.

### Nature

**Today:** two vine beams/orbits, leaves, blossoms and pollen; coloured trail/default pocket.
**Upgrade:** two strong leafy brushstroke vines with a few growing buds, clear leaves and
sparse pollen; short leaf-edged green trail; pocket sprout unfurling into a leaf fan.
Surface veins brighten along the stem direction. Curved leaf/vine cards, no large creature.
Check against Toxic/Veteran; preserve a fresh botanical look rather than green flames.

### Neon

**Today:** four orbit tubes, pink/cyan sparks and haze; coloured trail/default pocket.
**Upgrade:** two bold pink/cyan luminous loops with darker painted edge strokes and short
geometric spark accents; short twin-channel trail; a pocket neon loop spring and spark snap.
Surface lines chase cleanly. Curved loop geometry only where it improves depth. Check
against Prism/Hacked; loops stay visible while the cue rotates edge-on.

### Phantom

**Today:** ghost sprites, smoke/motes, two wisps and two orbit trails; coloured trail/default pocket.
**Upgrade:** a clear pale spectral ribbon with one readable ghost-shaped curl, darker cool
edges and detached motes; short ragged ghost wake; pocket spirit curl rising then dissolving.
Surface ghost markings breathe gently. Sculpted wisp effect geometry if useful, no creature
rig. Check against Blood Moon/Void; mystery comes from silhouette, not a grey smoke cloud.

### Plasma

**Today:** three arc groups, sparks, haze and veil; coloured trail/default pocket.
**Upgrade:** a stable coloured plasma sheath broken by a few thick travelling electric
branches, sparse charged chips; short energy trail; a small pocket charge ring and forked burst.
Surface cells pulse in sequence. Curved plasma blades if needed. Check against Thunderstrike:
clearly energetic at Rare scale, without copying the Legendary storm structure.

### Sakura

**Today:** two silk ribbons, petals and blossom haze; coloured trail/default pocket.
**Upgrade:** a clean pink silk/petal spiral with recognisable blossom clusters and loose
petals; short petal-edged ribbon trail; a pocket blossom opening and scattering petals.
Surface blossoms glow individually. Silk/flower cards where helpful, no fox or tail shapes.
Check against Candy/Kitsune; preserve cherry-blossom softness without losing daylight contrast.

### Tidal

**Today:** three water ribbons, bubbles/drops and sea haze; coloured trail/default pocket.
**Upgrade:** one broad painted cyan wave curl with blue underside and sharp foam crests,
smaller orbiting droplets; short foamy water wake; pocket wave crest curling into a splash.
Surface water highlights travel slowly. Curved wave mesh/flipbook as needed, no tentacle.
Check against Aurora/Kraken; foam remains a clear edge rather than white fog.

## 11. Rank and Exclusive cues

These receive the same L/H/P/Q checks and art care as their assigned visual level. Rank
progression needs distinct silhouettes; do not recolour one flame effect ten times. Preserve
their earning rules. Existing rank crowns on cue textures are replaced by non-crown gem or
chevron emblems except Reyes; rank UI badges are outside this pass.

| Cue / visual level | Today | Aura, trail and particles to build | Finisher to build | Surface and pieces / tools / specific check |
|---|---|---|---|---|
| Bronze / Common | Bronze chevrons and badge, no aura | Preserve the simple trail and no aura | Existing basic pocket effect | Repaint on final UVs, improve only mapping; no new pieces. Blender/Wire. Confirm no unintended new glow. |
| Silver / Uncommon | Silver chevrons and moving shine | Preserve existing shine and simple trail | Existing basic pocket effect | Final-width maps/thumb only; no new pieces. Blender/Wire. Compare Bronze without approaching Rare. |
| Gold / Rare | Gold-on-black, sparkle/haze, gold trail | A clean metallic gold sweep, glints and small geometric dust; short gold trail | A modest gold chevron fan and sparks | Polished chevrons and animated shine; no crown or gem pavilion. Paint/Blender/Wire. Distinct from VIP's faceted luxury and Reyes. |
| Platinum / Rare | Ice-white metal, shimmer and one ribbon | Broad cool-silver ribbon with blue reflections and sparse metal glints; short platinum wake | A silver ring opening into cool facets | Brushed/plated contrast; light ribbon geometry. Paint/Blender/Wire. Distinct from Frostbite's ice. |
| Diamond / Epic | Blue inlays, floating crystals and two ribbons | Layered diamond facets and sharp blue refraction fans; short crystal trail and angular chips | A dimensional diamond fan assembling above the pocket | Refined diamond inlays, rotating small facets; remove haze hiding them. Paint/Blender/Wire. Above Platinum, below Chroma. |
| Expert / Epic | Ruby/gold, red energy and two runners | Ruby-edged angular energy ribbons and sparing gem sparks; short deep-red faceted wake | Ruby prisms lock into a chevron burst | Replace crown-bearing cue emblem with ruby/chevron; add subtle facet motion. Paint/Blender/Wire. Unlike Blood Moon and Infernal. |
| Veteran / Legendary | Emerald/gold with green flames, leaves and runners | A dimensional emerald laurel arrangement with sweeping leaf-shaped light arcs and gem flecks | Emerald fronds unfold around a rising faceted core | Rich emerald enamel and gold veins; rebuild a proper laurel/gem piece, no crown. Short leaf/facet trail. Paint/Blender/Wire. Clearly above Nature/Expert. |
| Master / Legendary | Amethyst flame/crystals and two runners, custom violet trail | Sculpted amethyst blade/facet arrangement with restrained violet energy fans and crystal chips | A crystalline iris opens, turns once and releases a violet sweep | Animated internal gem light, deep metal recesses, new articulated crystal piece; short cut-edged violet trail. Paint/Blender/Wire. Distinct from Void and Kitsune. |
| Grandmaster / Mythic | Black/gold smoke, two ribbons and gold pocket rays | An elaborate articulated black-gold geometric array with large interlocking arcs, hot edges and sparse dark fragments | A layered geometric monolith/iris assembles, opens and folds away | Black lacquer/gold veins, dimensional articulated facets; short black-gold angular wake. No crown, celestial disc or planets. Paint/Blender/Wire. Match Mythic craft without copying Eclipse. |
| Reyes / above ordinary Mythic, below Eclipse | Pearl/gold, rainbow loops, crown sprite, rays and rainbow crown pocket burst | A dimensional rainbow-gemmed gold crown with pearl light fans, regal orbit arcs and selected gems; short separated-spectrum trail | A substantial crown rises, opens its gem-lit arches over broad gold rays and settles into sparkle | Highest rank's pearl/gold filigree and moving gem light; rebuild crown as a real animated centerpiece. Paint/Blender/Wire. Crown is exclusive to this cue; compare Grandmaster/Eclipse and VIP. |
| Starter / Rare | Sky-blue/cream/yellow surface, blue ring and tinted wisp | Bright sky-blue curved energy panels/ribbons, diamond-shaped glints; short blue-white trail | A small blue diamond flare with two sweeping ribbons | Clean enamel and silver, animated blue inlays, lightweight ribbon accents; no crown. Paint/Blender/Wire. An unmistakable Rare-level introduction. |
| VIP / Epic | Black/gold art-deco diamonds, rainbow accents, crown art and crown pocket sprite | Gold-dominant faceted art-deco loops, floating diamond accents and thin iridescent edges; short gold trail with selective rainbow glints | An art-deco diamond fan opens over a gold ring; no crown | Refined dark lacquer, gold frames and iridescent gem inlays; replace butt crown and all crown particles. Paint/Blender/Wire. Above Gold, below Reyes, recognisably VIP without a rainbow cloud. |

All these trails stay short. Mythic/Legendary rank pieces get the same creature/rig lifecycle,
quiet and quality tests as the case cues even when their form is a mechanism rather than an animal.

## 12. Final interview and scope boundary

The designer confirmed exactly **two** new cues, Beta and Grand Opening. Beta and Eclipse
share the highest visual standard; Beta's intended ownership rarity does not demand a
larger or louder effect than Eclipse. Creatures are painted luminous spirits with clear
contours; Apex stays mechanical.

**Economy is explicitly outside this task** (designer's final clarification). Do not ask
about or change prices, copy caps, sale dates/windows, receipts, products, progression,
ownership or saves. Deliver meshes, textures, animation and effects imported into Studio and
ready to use through the existing cue systems. Art-facing catalog look/style integration is
allowed where necessary to display the finished cues; it does not authorize sale changes.
Record Founder's cancellation in the release design documents and create no Founder assets.
No third cue is waiting. No art question remains open before review of this brief.

## 13. Build order and verification gate

After the final interview and approval of this brief:

1. Width rebuild and complete baseline verification; commit/push that verified step.
2. Shared VFX/quality/quiet/lifecycle extensions needed by the first top-tier cue. Work
   incrementally with its assets, test the shared logic, then verify it in Studio.
3. Eclipse, then Beta, to the same highest visual standard with different signature effects.
4. Dragon, Kitsune, Apex and Grand Opening; then Reyes and Grandmaster to the agreed ladder.
5. Seven Legendary case cues, then Veteran and Master.
6. Nine Epic case cues, then Diamond, Expert and VIP.
7. Ten Rare case cues, then Gold, Platinum and Starter.
8. Final Common/Uncommon/Bronze/Silver width regressions; full tier contact sheets, crowded
   lobby, phone/gamepad checks and final art integration in Studio.

For **each cue**: author assets; upload and wire data/templates; inspect in the Play lab and
real match; compare adjacent tiers; iterate until beautiful; run `tools/lint.sh` and
`tools/test.sh`; verify Rojo and console; capture evidence; commit with a descriptive message
and push; add one dated status line below. Then continue without asking permission between
cues. Do not mark a cue complete because an asset was generated or a screenshot exists.

Founder's cancellation is documented as the current release direction; no Founder art is
built. Legacy catalog, ownership and economic removal is separate release work, outside the
designer's final scope for this art pass. Historical records retain their dates and receive
a superseding note so an old art brief cannot restart the cancelled design.

The final report is `docs/prompts/CUE_VFX_REPORT.md`: per-cue changes, tier comparisons in the
real lobby, PC/phone/gamepad evidence, performance findings, known limitations and exact
manual checks. Rewrite `CUE_SKINS_REVIEW.md` rows to current truth (including new Unique rows),
not an accumulation of contradictory historical descriptions. Update GDD, architecture,
cue asset Readme, roadmap, Status and dated decisions to match what actually shipped.

Ask the designer once for the milestone's final place save/publish. For a particularly costly
new import, mention its checkpoint value once. Do not suggest Team Create requires repeated
manual saves. A completed code commit does not prove the corresponding place assets are
saved or live; record those states separately.

## 14. Decisions

- **2026-10-04, designer:** selected 0.36 after viewing 0.48/0.64, 0.38 and 0.36 studies.
  Length/tip remain unchanged. Earlier wider proposals are rejected.
- **2026-10-04, designer:** accepted tier ladder, non-case mapping, restrained aiming,
  nearby-cue quieting, short detailed trails, taller finishers and a larger legal winning-8
  variant. New geometry and creatures may be rebuilt using the best available tools.
- **2026-10-04, designer:** Beta and Grand Opening must ship; Founder is cancelled. Beta is
  a translucent blue/magenta blueprint Unique at Secret quality; Grand Opening is a
  navy/gold/cyan/magenta fireworks Unique at Mythic quality. Both never return after sale.
- **2026-10-04, designer:** pastel-pink Kitsune; grander stable Eclipse with existing colours;
  gold-focused VIP with some rainbow; crowns reserved for Reyes in the cue designs.
- **2026-10-04, designer:** balance performance but lean toward visuals; iPhone hand check;
  standing asset generation/upload authorization; faint sounds and small equip moments only
  if they do not materially delay results.
- **2026-10-04, final interview:** exactly two new cues; Beta and Eclipse have equal top
  visual quality; painted luminous spirit creatures and mechanical Apex. Economy is out of
  scope: do not ask for sale terms or change economic systems. Deliver the art imported and
  ready to use in Studio.
- **2026-10-04, planning:** genuine cue-change flourish only, using existing themed assets;
  hand/back transfers remain seamless. Blueprint details prioritize readable major lines
  over the reference's fine text. Preserve current source JSON over old generator recipes.

- **2026-10-04, implementation:** shape 3 uses 4,160 triangles (budget 4,200; previously
  3,840/4,000), retaining the 32-sided cross-section and adding rings for the approved smooth
  widening. Existing card exaggeration stays at 1.15 with aura-free thumbnails.

## 15. Status

- **2026-10-04 — Planning only:** repository/reference review complete; `cue-vfx` branch
  created; temporary width comparisons cleaned from Studio; 0.36 selected. Two new reference
  images and the painted-style reference preserved in the repository. Interview complete;
  draft brief written and approval pending. No production scripts, skins, uploads,
  templates or game settings changed. Existing place save/publish work remains pending.
  Baseline verification: `tools/lint.sh` passed with four existing LocalShadow warnings;
  `tools/test.sh` passed all 983 tests. Brief coverage, reference links and diff whitespace checked.

- **2026-10-04 — Implementation started:** designer approved the brief. Shape-2 source JSON
  and piece definitions snapshotted; rebuilding the approved 0.36 profile before VFX work.

- **2026-10-04 — Width verified:** 0.36 butt / 0.09 tip / 7 length, slim first 2.1 studs
  retained. Mesh/UV/manifold/envelope checks pass at 4,160 triangles; all 59 maps/thumbnails
  and 16 pieces rebuilt, 21 moving-surface frames imported. 427 replacement assets uploaded
  to group 675425213, all 408 image IDs resolved, source hashes recorded. Shape 2 -> 3
  migration preserves 123 emitter clearances and is a no-op on rerun; Phoenix Segment hosts
  refit. Classic explicitly replaced; all 59 templates report the correct mesh and size.
  Lint passes (four existing warnings); **984 tests pass**. Studio: bright-lobby back/stand,
  moving and seated carry, 65%-scale avatar (butt 0.8 studs above floor), real aiming,
  off-centre spin, 60° elevation, corner-rail pull/release and completed shot; console clean.
  PC and phone-emulator views checked; controller emulator connected, physical pad/iPhone
  acceptance remains pending. Frozen live-pose grip study is labelled as an inspection
  (accessories/effects hidden), not a live-match screenshot. Evidence is locally preserved
  under `assets/cue/renders/vfx-upgrade/width036_*.png` (ignored checkpoint captures).
  The lab now waits for warm assets and reuses one back pool with hidden unused slots.
  Edit-mode templates are in Studio/Team Create; the final place save/publish is still the
  designer's handoff. No cue VFX redesign is marked complete by this width step.
