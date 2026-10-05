# Cue rarity rework: the tier bar, and the rarer cues brought up to it

Brief for the Unique cues lane's second job (branch `lane-unique`, worktree
`~/Desktop/8ball-unique`, Studio copy `lane-unique.rbxl`, Rojo 34878; the lane rules in
`docs/parallel/unique.md` and `docs/parallel/README.md` still apply). Asked by the designer on
2026-10-04 after both Unique cues passed gate 3: the rarer existing cues are now underwhelming
next to them. "Celestial Dragon is pulsating way too fast and it's annoying, colours need to be
brighter and look more spiritual, like energy; right now it's a bunch of particle effects
masking the detail. Same for Eclipse: as a Secret it's overwhelming and the aura is generic,
like a Roblox particle effect." The job: write the rules for what each rarity looks like, then
go back from the rarest down and bring every cue up to its rule with the techniques in
`docs/CUE_VFX_TECHNIQUES.md` (real 3D depth, never warped moving pictures).

Status: **plan approved 2026-10-04 (answers in Decisions); building, Eclipse first.**

## 0. Read first

1. `docs/CUE_VFX_TECHNIQUES.md` (the craft), `docs/prompts/UNIQUE_CUES_PROMPT.md` sections 2
   to 4 (the bar the Unique cues set) and the Beta and Grand Opening skin files.
2. `docs/prompts/CUE_SKINS_PROMPT.md` and `CUE_SKINS_REPORT.md` (how the 61 skins were built),
   `docs/DECISIONS.md` lines on cues from 2026-09-30 on (the v2 lobby standard, outlines,
   quiet shares, "Epics never get 3D pieces", "set pieces become 3D").
3. `assets/cue/skins/<id>.json` of the cue in hand, its `CuePaint.py` recipe, its piece
   module (`CuePiecesLegendary.py`, `CuePiecesMythic.py`, `CuePiecesPocket.py`).

## 1. Facts that shape the plan

- The code's ladder is Common, Uncommon, Rare, Epic, Legendary, **Mythic**, Secret
  (`Config.Cases.Rarities`); the designer says "Mythical". The label is one string in
  `Strings.luau` if it is to change. Exclusive (VIP, Starter, the ten rank cues) and Unique
  (Beta, Grand Opening, Founder's) sit outside the ladder; the skin's `tier` field (Rank,
  Exclusive, Unique) is what the runtime keys outlines and quieting on.
- Every skin already has its own trail; only Classic, the Commons, Bronze and Silver use the
  rarity rows in `Config.Effects.Styles`. Finishers: 5 of 9 Epics, every Legendary and above,
  Grandmaster, Reyes and VIP have staged ones; the rest tint the default gust.
- The top cues are heavy and flat: Eclipse runs about 247 particles a second, the Dragon 300,
  Kitsune 219 (the Unique cues: 68 and 73), nearly all of it generic smoke, dust, flare and
  glint sprites hosted on the cue's cylinder. The Dragon's "pulsing" is ten spine flame
  emitters playing a 64-frame flipbook in 0.5 to 0.8 s plus 36 star flares a second popping in
  0.15 s, over a 90-a-second mist that hides the dragon. Eclipse's piece (orb, rings, moon,
  shards) lives only at the butt; the rest of the cue is cloud.
- Tip, ferrule and bumper are never painted from the panels: `CueTextures.py` fills them with
  the skin's flat `colours` plus chalk, ivory and rubber grain, and only Beta's glow and
  alpha reach them. The collar is repainted as plain metal by every recipe (`ai_finish`).
  Making them themed from Legendary up is a generic change to the painter (section 4).
- Lower effects is one global rate multiplier plus `Low = "hide"` on piece joints. There is
  no per-skin low variant beyond that.

## 2. The rules per rarity (the designer's words, filled in)

Each tier includes everything below it unless the rule says otherwise. "Budget" is particles
a second with the full aura on the lobby floor; it is a ceiling, not a target (the Unique
cues read as the richest in the game at about 70).

| Tier | Surface | Collar, ferrule, tip | Aura | Trail | Pocket finisher | 3D piece | Sound |
|---|---|---|---|---|---|---|---|
| Common | painted texture only, no emissive | standard (chalk tip, ivory ferrule, rubber bumper) in the cue's colours | none | the shared white wisp | the plain gust | no | no |
| Uncommon | texture plus one glowing accent (a ring, inlay or band) with a slow emissive pulse | standard, recoloured to the theme | none | tinted wisp | plain gust, tinted | no | no |
| Rare | texture, glow accents | standard, recoloured; a glowing band on the ferrule allowed | **the first aura**: a dark body plus one glow layer plus one themed accent (own sprite or oriented shapes), one orbiter at most; budget 25 | own colours and texture; a core from Rare up | none: the gust in its colours | no | no |
| Epic | moving material (overlay beams, emissive pulse), richer theming | standard, recoloured and glowing to the theme | the Rare aura plus a second themed accent and a moving-light pass; budget 40 | unique trail with one ball-riding emitter | **some** (where the theme pays off at the pocket; today 5 of 9) | no (decision 2026-09-30 stands) | no |
| Legendary | surface frames (moving painted detail), own sprites | **themed and glowing**: collar, ferrule and tip painted from the panels in the cue's motif (feathers, brass, scales, ice), emissive, never the standard set | an aura that is its own kind of effect (not the body-glow-motes recipe repainted), brighter than any Epic; one real mesh element (wings, halo, gears, crystals, tentacles) with three motions at three periods; budget 60 | unique, with two or three ball-riding emitters | **all**: a staged 1.5 to 2 s finisher, the piece or a creature rising | yes, on at least the butt | yes: a faint aura loop and a pocket sound (Roblox library placeholders for now) |
| Mythic ("Mythical") | all of the above, more layering; the cue mesh **may deviate** from the base shape (a sword, a staff, a spine: creative liberty, no limits) | themed, glowing, and shaped (the ferrule can be a jaw, a crystal, a thruster) | a full set: body, glow, two accents, orbiters, moving light, a hero creature or construct that is the aura's centre and readable (nothing masking it); budget 80 | layered: texture plus core plus three emitters | staged with a 3D rise and a sound | yes, rigged or multi-joint, with visuals (Glow, Fade, life) | yes, aura loop and pocket sound |
| Secret | everything Mythic, plus completely unique modelling, colours and techniques not used by any other cue | shaped and glowing; part of the modelling | **engulfing**: noticeably bigger than every other cue, around the cue and around the player carrying it (orbiting bodies, a field, a sky), still clear enough to read the cue; budget 120 | layered, with a pocket-sized event behind the ball | the biggest in the game, 2 s, a sky-sized rise | yes, several pieces along the whole cue, not one at the butt | yes |
| Unique | the Legendary-to-Secret rules (Beta and Grand Opening already meet them) | themed | own tier, own kind | layered | staged with a rise and a sound | yes | yes |

Rules that cut across tiers:

- **The depth rule** at every tier that has an aura: a dark body behind the light, volume
  hosts, oriented shapes, orbiters, lights, and from Legendary a real mesh.
- **Readable first**: the hero (creature, construct, the cue itself) is never masked by cloud.
  A body layer is at most 20 a second from Legendary up (the Dragon's 90 was the problem).
- **Slow is rich**: nothing flickers under 1 s unless it is fire or sparks; flipbooks at
  Lower-than-24 fps or OneShot over 1.5 s; pulses 1.6 to 5 s; three periods per cue.
- **Colour**: saturated mains, white-hot births, an accent at death. "Spiritual energy" is
  pale cyan-white cores with a deep blue-violet body and gold motes, not mid-blue fog.
- **Brightness bands**: Rare glow 1 to 2, Epic 2 to 3, Legendary 3 to 5, Mythic and up 5 to 7
  on the small hot things only; bodies stay under the bloom threshold.
- **Lower effects** keeps the identity: the mesh, the surface glow, the trail core, the
  pocket flash. Far detail gets `Low = "hide"`.
- **In the hands** the aura quiets (0.5 to Epic, 0.25 from Legendary; the Dragon's and
  Kitsune's 0.07 goes back to 0.25 once they no longer hide the table).

**Rank cues** (Exclusive, rank rewards) follow the ladder by rank; the trophy design stays
shared and the tier adds to it:

The designer chose "one step higher" than the plain mapping (2026-10-04): rank rewards
outshine case cues of the same step.

| Rank cue | Follows | Note |
|---|---|---|
| Bronze | Uncommon | the glowing ring (today: texture only; gains the ring) |
| Silver | Uncommon | ring plus the shine sweep |
| Gold | Rare | the first aura (today 12/s, grows a themed accent) |
| Platinum | Rare | aura plus the ring |
| Diamond | Epic | moving light, unique trail (today 17/s) |
| Expert | Epic | finisher added |
| Veteran | Legendary | themed collar, a mesh element, finisher, sound |
| Master | Legendary | same, richer |
| Grandmaster | Mythic | a construct (laurels and a crown that turn), shaped ferrule, sound |
| Reyes | Secret-level | the summit: engulfing, unique modelling, the biggest finisher after Eclipse |
| VIP (Exclusive) | Legendary, in gold | the crown finisher exists; themed collar, a mesh crown, sound |
| Starter (Exclusive) | Uncommon | the ring; nothing more |

The catalog's `Effect` fallbacks (Bronze to Gold "Uncommon", Platinum and Diamond "Rare", and
so on) only matter for cues without a skin style; they stay as they are unless the designer
wants Bronze and Silver's trail turned plain.

## 3. The order of work and what each top cue gets

Rarest first, one cue at a time at the top, then tier batches. Every cue: a concept board
rendered from own work (full cue, handle, aura three-quarter, trail, pocket) → gate → build
→ in-Studio gate (lab beside its tier-mates and the Unique cues) → polish, Lower effects,
cards → next.

1. **Eclipse (Secret).** Diagnosis: a butt-only piece under a generic cloud. Rework: space as
   a *system* along the whole cue, not a cloud. Three to four orbit rings at different tilts
   along the shaft carrying planets and a moon (lathe rings, Spin at 20 to 40 degrees a
   second, Glow visuals); an asteroid belt (a ring of shards on a Spin, Bob each); the
   corona as a real mesh ring behind the obsidian orb with a saw-sweep "flare" visual;
   stars as two volume layers (near: few, bright, slow; far: many, dim, locked) for parallax;
   nebula as a dark violet body at 12 a second with one additive gold-violet glow layer; an
   eclipse-shadow sweep (a dark band scrolling tip to butt on a saw) so the cue itself is
   "eclipsed" every few seconds. Engulfing: a wide orbit ring with two planets round the
   carrier when the cue is on the back (section 4). Surface: obsidian with gold corona
   crack-lines that glow and pulse 1.8 to 3 over 4 s; collar as a gold corona ring with a
   black-sun disc; the ferrule a glowing gold ring, the tip obsidian with a gold rim. Sound:
   a deep space hum. Budget 120 (down from 247, bigger and slower). The cue mesh stays the
   base shape unless the designer wants a remodel (question 5).
2. **Celestial Dragon (Mythic).** Diagnosis above. Rework: the dragon is the hero. Its
   body gets a slow Glow visual (period 4 s) on emissive vein lines and a scrolling energy
   ribbon mesh along the spine (sweep with a Stretch texture); the ten spine flame emitters
   become slow spirit wisps (two a second each, 1.5 to 2.5 s life, OneShot flipbook over the
   whole life) in pale cyan-white into violet; stars at 8 a second, slow; mist to 18 a
   second, deep indigo; gold motes stay. Colours lifted: `#EAFBFF` cores, `#3FD6FF` main,
   `#1A1F7A` body, gold `#FFD27A`. Collar: gold dragon scales with a pearl; ferrule a glowing
   pearl band; tip a pearl. The pocket head roar keeps, slower. Sound: a low spirit tone.
3. **Kitsune (Mythic).** Nine tails as real swept meshes with Sway (today nine beams), the
   foxfire orbs as glowing spheres on orbit paths with Glow, the petal and body layers cut to
   a third, shrine-red torii lacquer on the collar with gold, a fox-fire ferrule. Sound: a
   soft bell.
4. **Apex (Mythic).** Not in the v2 pass. HUD rings as real ring meshes with Spin and
   Glitch, the thrusters as cone meshes with flame emitters, a data-stream beam, cyan-orange
   plating on the collar (already glows), a thruster ferrule. Sound: a soft turbine.
5. **Reyes, then Grandmaster and VIP** (Mythic, Legendary, Legendary rules).
6. **The seven Legendaries**: themed collars for all; Thunderstrike gets its mesh element
   (a storm ring or a charged coil); each aura checked against "its own kind of effect", the
   body layers cut, finishers reviewed for a real rise.
7. **The nine Epics**: the depth pass (dark body, volume hosts, oriented shapes), glowing
   recoloured ends, finishers for those that have none only where the theme asks (ask per
   cue in the batch gate).
8. **The ten Rares**: the depth pass and one themed accent each; no finishers.
9. **Uncommon and Common**: a check only (every Uncommon has a glowing ring; Commons untouched).
10. Founder's Cue has no skin: out of scope unless the designer gives its concept.

## 4. Generic capabilities to add (data kinds, no `if cueId`)

- **Themed ends**: a skin key (`ends: "painted"`) that makes `CueTextures.py` take tip,
  ferrule and bumper from the painted panels and glow map instead of the flat fill; the
  layout gains the three zones as paintable panels. Legendary and up use it.
- **Carrier aura** (Secret, Unique on request): aura rows with `Host.Kind = "Carrier"` attach
  to the carrying character's root when the cue is on the back (and quiet with the rest in
  the hands). `CueSkinLook` already knows the carrier through `BackCue`.
- **Mesh variants**: a skin key `mesh` naming an uploaded cue mesh (the builder already swaps
  the Classic mesh by id); the templates keep the shared size for the hands and back
  attachments. Needed for Mythic creative liberty and a future sword.
- **Glowing veins on textured pieces** (the Dragon's body): Roblox has no per-part emissive
  strength, so the Glow visual lerps the part's colour and a thin Neon twin under the
  translucent shell carries the pulse. A kit option (`vein=`) builds the twin.
- **Sounds** for Mythic and Secret (and Legendary if the designer says yes): the existing
  `Aura.Sound` and `Pocket.Sound` rows; the sound files from the designer or a Roblox
  library placeholder.
- **Budget check**: `tools/cue_skins_data.py` prints each skin's summed particle rate against
  its tier's ceiling and warns (the written `Budget` numbers are stale and go).

## 5. How to work

As the Unique brief: one cue at a time at the top, gates with the marker, lint and tests,
the lab beside tier-mates and the Unique cues from three angles, a solo fixture match, Lower
effects, the Index card, commit and push after each step, dated Status lines in the lane
file, every shared-file change listed there. Spend on OpenAI and Meshy freely. The designer
reviews boards at gate 1 and the Studio look at gate 2 per cue for Secret and Mythic; for
Legendary and below the gates are per tier batch (one board sheet and one lineup).

## 6. Questions for the designer (asked and answered 2026-10-04; see Decisions)

1. **Gates and pace.** Per cue for Eclipse and the three Mythics, then one board sheet and
   one lineup per tier batch below that: agreed?
2. **Rank cues.** The mapping in section 2 (Bronze and Silver as Common, Gold and Platinum
   Uncommon, Diamond and Expert Rare, Veteran and Master Epic, Grandmaster Legendary, Reyes
   Mythic): agreed?
3. **Engulfing means the player too.** For Secret, the aura reaches round the player
   carrying the cue (orbiting planets round the body on the lobby floor, quiet in a match):
   yes or cue-only?
4. **Sounds.** Faint loops and pocket sounds from Mythic up, or from Legendary up?
5. **Remodelling.** Mythic and Secret may change the cue's shape. For this pass, keep the
   base shape on the existing cues (new ends and pieces only), or remodel Eclipse and the
   Mythics' silhouettes too?
6. **"Mythical".** Rename the Mythic label in the game to "Mythical"?

## Progress

- [x] 0. The plan approved (2026-10-04); the rules go into the GDD at the merge (the integrator, not this lane).
- [x] 1. Generic capabilities: themed ends in the painter, the carrier piece and host
  (2026-10-04). Still to do when first needed: the budget check in the generator, mesh
  variants.
- [x] 2. Eclipse: board, gate 1 (passed 2026-10-04 at the third look).
- [ ] 3. Eclipse: build, gate 2, polish, trail, pocket, sound, cards.
- [ ] 4. Celestial Dragon: board, gate 1; build, gate 2, polish.
- [ ] 5. Kitsune: board, gate 1; build, gate 2, polish.
- [ ] 6. Apex: board, gate 1; build, gate 2, polish.
- [ ] 7. Reyes, Grandmaster, VIP.
- [ ] 8. Legendaries (7): board sheet, gate; build; lineup gate.
- [ ] 9. Epics (9): board sheet, gate; build; lineup gate.
- [ ] 10. Rares (10): board sheet, gate; build; lineup gate.
- [ ] 11. Uncommon and Common check; rank cues' lower tiers.
- [ ] 12. Final lineup of every tier, lint, tests, handoff and report.

## Status

- 2026-10-04: the plan written from a survey of the catalog, every skin file, the painter
  and the docs; the questions in section 6 put to the designer and answered.
- 2026-10-04: step 1 built (themed ends, the Carrier piece and host, the preview's carrier);
  Eclipse rebuilt in data (collar and ends, the piece, the carrier piece, the aura as a star
  system at about 99 particles a second, placeholder sounds). The board
  (`assets/cue/concepts/rework/eclipse-board.png`) at gate 1; passed at the third look.
- 2026-10-04: step 3 begun: Eclipse built in the lane window (maps and both pieces uploaded,
  the template and pieces rebuilt, the lab beside Beta and the Dragon). Tuned on the lobby
  floor: the orbit rings thicker (they read thin in Roblox), the coronas drawn behind the
  black disc with fewer, dimmer sprites so the hole stays black from every side; quiet hides
  all 26 carrier parts and cuts the carrier emitters to a quarter. Captures
  `assets/cue/concepts/rework/eclipse-studio-{back,stand,side,front}.jpg`. Waiting at gate 2.

## Decisions

- 2026-10-04 (designer): gates per cue for Eclipse and the Mythics, per tier batch below.
- 2026-10-04 (designer): rank cues follow the rules one step higher than their plain step
  (table in section 2).
- 2026-10-04 (designer): a Secret's aura engulfs the cue and the player carrying it (a
  generic Carrier host).
- 2026-10-04 (designer): sounds from Legendary up; Roblox library placeholders picked by the
  lane, listed per cue, swappable later.
- 2026-10-04 (designer): remodelling allowed for Mythic and Secret in this pass (approved at
  each cue's board gate).
- 2026-10-04 (designer): the tier label reads "Mythical" (the item rarity, the case name,
  the reveal band and the unbox line in `Strings.luau`); ids stay `Mythic`. The ability
  rarity label was left as "Mythic" (not asked).
- 2026-10-04 (designer, Eclipse gate 1, first look): the gold rings more glowing and neon;
  the eclipses are not physical black spheres but vanta black, a black hole, at the butt and
  over the player's head, each with a glowing yellow aura like the pocket finisher's corona;
  and the clip is re-rendered after every change (the designer judges by the video:
  `assets/cue/concepts/rework/<id>-clip.mp4` is committed with the board each time).
- 2026-10-04 (designer, Eclipse gate 1, third look): passes ("good move on") with the head
  sun blooming like the butt's.
