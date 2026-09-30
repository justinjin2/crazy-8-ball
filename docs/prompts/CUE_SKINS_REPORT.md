# Cue skins: the report

The cue-skins run (brief: `CUE_SKINS_PROMPT.md`, branch `cue-skins`, worktree
`~/Desktop/8ball-skins`). Every skin is built on the shared cue mesh as textures, glow and a VFX
spec, with renders and a clip to review. **Nothing is imported into Roblox yet**: the import is
a later session, and the second half of this report is written for it.

**Status: 58 of the 61 new skins are built.** The three Unique cues (Founder's Cue, Beta Cue,
Grand Opening) are waiting for their concept sheet, `assets/cue/concepts/Q1.png`.

---

## 1. What to look at first

1. **The tier sheets**, `assets/cue/renders/tiers/<tier>.png` (these are committed). Each shows
   every skin of one tier the same way up, then a row of aura stills, so you can judge the
   balance of a tier at a glance. Start with `mythic.png`, `secret.png` and `legendary.png`.
2. **A skin's sheet**, `assets/cue/renders/skins/<id>/sheet.png`. Each render sits beside its
   concept crop: the full cue, the joint, forearm and butt, a 3/4 view and an aura still.
3. **A skin's clip**, `assets/cue/renders/skins/<id>/clip.mp4`. It turns the cue, shows the
   aura from two angles, the cue on a player's back, a shot with the ball trail and a ball
   dropping with the pocket finisher.
4. **The review checklist**, `docs/prompts/CUE_SKINS_REVIEW.md`. It has one row per skin with
   what was built and where it differs from the concept. Write `OK` or `fix: ...` in the
   Designer column, and the next session does the fixes first.

Renders and clips are not in git (they are rebuilt from the skin files). To rebuild one:
`python3 tools/cue_skin.py <id> --paint --maps --stills --sheet`, then `--clip`. The tier
sheets are rebuilt with `python3 tools/tier_sheets.py`.

## 2. Every skin's status

All built skins are **ready for your review** (none reviewed yet). The painter is **proc** (drawn
by script), **AI** (OpenAI panels painted from the concept crops) or **mix** (both).

| Tier | Skins | Painter | What each has |
|---|---|---|---|
| Common (7) | Midnight, Arctic, Cherry, Carbon, Heritage, Monarch, Cobalt | proc | surface only; the shared white wisp |
| Uncommon (9) | Gummy, Flare, Hornet, Venom, Lagoon, Splice, Cosmo, Gilded, Pixel | proc / mix | one glowing ring; the wisp tinted |
| Rare (10) | Honeycomb, Neon, Plasma, Blaze, Frostbite, Nature, Candy, Phantom, Tidal, Sakura | proc / mix | its own aura (11-20 particles/s); the wisp tinted |
| Epic (9) | Void, Shooting Star, Magma, Toxic, Blood Moon, Prism, Aurora, Disco, Hacked | proc / mix | a moving material (overlay Beams and emissive pulses), an aura (19-31/s), a trail or pocket where plan.json lists one |
| Legendary (7) | Chroma, Thunderstrike, Phoenix, Kraken, Seraph, Infernal, Clockwork | mix (Clockwork proc) | SurfaceAppearance frames, a layered aura (30-51/s) with sprites made for it, its own trail and a staged pocket finisher |
| Mythic (3) | Celestial Dragon, Kitsune, Apex | mix + a scripted 3D piece | all of the above plus a moving 3D piece on the butt |
| Secret (1) | Eclipse | mix + a scripted 3D piece | a floating eclipse with a particle corona |
| Exclusive (2) | Starter Cue, VIP Cue | mix | Starter: blue ring and wisp. VIP: a rainbow-cycling ring, gold aura, own trail, a crown finisher |
| Rank (10) | Bronze, Silver, Gold, Platinum, Diamond, Expert, Veteran, Master, Grandmaster, Reyes | proc (one shared trophy design) | climbing from no VFX (Bronze) to a shine sweep, sparkles, flames, own trails and finishers (Grandmaster, Reyes) |
| Unique (3) | Founder's Cue, Beta Cue, Grand Opening | - | **not built: waiting for `Q1.png`** |

The details of each skin (every VFX piece and number, and where it differs from its concept)
are in its review row and in `assets/cue/skins/<id>.json`.

## 3. OpenAI spend and model

- **Model:** `gpt-image-2.5-sunburst` (the newest image model on the key; it keeps precise
  edits), used through the edits endpoint with the panel layout and the concept crops.
- **Spend:** about **$2.79** for 81 images (the log is
  `assets/cue/concepts/openai_log.jsonl`). That is far below the $25 note and $150 stop.
- The chosen panels are committed in `assets/cue/skins/<id>/ai/`, so a repaint never pays
  again. `take: n` in a skin's `ai` block picks which take is used.

## 4. 3D parts to generate

The AI 3D generators (Rodin, Hunyuan3D, Tripo) only work through the Blender MCP, which this run
could not use. Every piece is therefore modelled by script (`assets/cue/CuePiecesMythic.py`),
and each one is complete and moves. These would still look better as a generated model, in
this order:

1. **The Celestial Dragon's head** (`pieces/celestial_dragon`, joints Head and Jaw): the
   scripted head is smooth metaball sculpting, so the scales, brow ridges and teeth are simpler
   than the concept's. Keep the energy body (the two coiling ribbons): it is right as it is.
2. **The Kitsune mask** (`pieces/kitsune`, joints Mask, EarL, EarR, Jaw): a generated
   porcelain mask would have crisper carved markings; the crimson markings are strips laid on
   the sculpt today.
3. **The Apex claw arm** (`pieces/apex`): the scripted version is clean hard-surface work
   (bevelled plates and blades). A generated one could add panel detail, but this is the
   lowest priority.

Eclipse's piece (a sphere, rings and a moon) needs no generator.

For a replacement, keep the joint layout: split the model by moving part (the jaw, the ears, the
claws), put each part's pivot where `piece.json` says, and reuse the motion lists as they are.

## 5. Particle budgets

Per cue in hand, as the brief set them (at most about 20 a second on Rare, 35 on Epic and 60 on
Legendary and up). A cue worn on a back runs at `BackRateScale` = **0.5** (every skin).

| Tier | Highest aura rate | Notes |
|---|---|---|
| Rare | 20/s (Blaze) | Honeycomb, Frostbite and Candy 18 |
| Epic | 31.4/s (Void) | Magma 30 |
| Legendary | 51/s (Infernal) | Chroma 44; the others 30-41 |
| Mythic | 46/s (Celestial Dragon) | Apex 39.6, Kitsune 37 |
| Secret | 40.5/s (Eclipse) | |
| Exclusive | 27/s (VIP) | the Starter has none |
| Rank | 29.6/s (Reyes) | Bronze and Silver have none |

Orbiters, Arcs, Beams and Lights are not particles and are listed separately in each skin's
`Budget` (at most 5 Orbiters, 10 Beams, 2 Lights on one cue). Ball-trail emitters run only while
a ball rolls (up to 32/s: Chroma, Thunderstrike).

---

## 6. For the import session

Everything below is what the game code and the shared docs need. This run changed none of
them (`src/`, `tests/` and the shared docs belonged to the abilities run).

### 6.1 Catalog changes

- **Replace the 30 placeholder case cues** in `src/shared/Progression/Catalog.luau` with the
  case cues built here (Common to Secret, 46 skins), one row per skin. The id, name, tier and
  catalog id are in each `assets/cue/skins/<id>.json` (`catalog_id`, for example `KitsuneCue`).
  Strings go in the shared strings module.
- **Exclusive and Rank cues** already have ids (`StarterCue`, `VipCue`, `BronzeCue` ...
  `ReyesCue`); their rows just need to point at the new looks.
- **The Starter Cue becomes tradable** (designer, 2026-09-29): set `Tradable = true` on its
  Catalog row, and give the "no Exclusive cue trades" test (`tests/catalog_test.luau`) a
  Starter exception. It is never sold back.

### 6.2 Config.Effects rows

Each skin's `vfx.Style` is written as a `Config.Effects.Styles` row (only what differs from the
default). The keys `Trail.Color`, `Trail.Colors`, `Trail.Core`, `Trail.NearTransparency`,
`Trail.LightEmission`, `Pocket.Colors` and `Pocket.ColorShare` already exist. Rows here also use:

- `Trail.Texture`, `Trail.TextureMode`, `Trail.TextureLength`, `Trail.WidthScale`,
  `Trail.Lifetime`, `Trail.WidthStuds`: a textured, shaped trail (Legendary and up).
- `vfx.Trail.Emitters`: small emitters on the ball while it rolls.
- `vfx.Pocket.Layers`, `Rings`, `Flash`: a skin's own pocket layers (emitters with Delay for
  staging), extra rings and a flash, added on top of the default burst (which the row tints).

The Effects module needs those extra keys read; the row format stays data only.

### 6.3 What `CueStickBuilder` needs

The cue mesh and its SurfaceAppearance per skin are as the cue-mesh run left them. On top, one
generic cue-VFX script can build everything from the skin data:

- **Maps:** `textures/<id>_color|normal|roughness|metalness|emissive.png`, from
  `CueTextures.py -- --skin skins/<id>.json`. Glow is the emissive map with `EmissiveStrength`
  and `EmissiveTint` (`surface` in the skin file).
- **Surface pulses** (`surface.Pulse`): tween `EmissiveStrength` on a wave (sine, flicker,
  beat); `EmissiveTintHue` turns `EmissiveTint` round the hue wheel (VIP, Reyes); Chroma also
  sets `surface.Color`.
- **SurfaceAppearance frames** (7 Legendaries, `frames` in the skin file): up to 4 pre-built
  SurfaceAppearances per skin (`textures/<id>_f<n>_*`), swapped by cloning in the order and
  at the speed in `vfx.Moving.Frames`.
- **Attachments** along the cue: `AtStuds` from the tip (the butt is 7), `Up` and `Side` in
  studs. The Roblox MeshPart frame is Position = (-Side, Up, 3.5 - AtStuds).
- **ParticleEmitters** with every property named as Roblox names it. `Host` says where: an
  `Attachment`, or a `Part` (an invisible cylinder along the cue, `FromStuds`/`ToStuds`/`Width`,
  surface or volume) for emitters that cover the whole cue.
- **Beams:** straight or curved (`Curve0`/`Curve1` give each Attachment's Axis and
  CurveSize); `Twist` turns the curve round the cue; the far end may sit off the axis
  (`Up1`/`Side1`) and `Sway` swings it (the curve lags a quarter period); `Pulse` tweens
  Transparency. **Overlay Beams** (the Epic moving materials) are cue-wide Beams just in front of
  the cue (`ZOffset`) with a scrolling texture (`TextureSpeed`).
- **Orbiters:** an Attachment pair a script flies along a helix round the cue (From/To,
  TravelSeconds, TurnsPerSecond, Radius or `RadiusFromSurface`, Wobble, Phase, Delay), carrying
  a Trail and optionally a glowing head.
- **Arcs** (Plasma, Thunderstrike): lightning as chains of short Beams whose Attachments a
  script re-jitters every 0.09-0.2 s.
- **PointLights**, with an optional `Flicker` (a wave on Brightness) and `Hue` (Chroma).
- **Pieces** (Mythic, Secret): `pieces/<id>/*.obj` become MeshParts welded to the cue, one per
  joint and material, each placed by its `Offset` in the Roblox cue frame, with the Roblox
  Material, Color, Transparency and Reflectance from `piece.json`. A small script animates each
  joint from its `Motion` list (Hinge, Sway, Spin, Bob with sine, snap or pulse waves) about its
  `PivotRoblox`, parents first; `joint_matrix` in `CuePieces.py` is the reference maths.
- **Back-worn cues:** every emitter's Rate times `BackRateScale` (0.5).
- **Where the aura shows (designer, 2026-09-30):** on the back, the cue sits in front of the
  body and the big aura sprites (Eclipse's giant eclipse and galaxy, any large camera-facing
  sprite) sit behind the body: give them a negative `ZOffset` against the torso, or host them
  on an Attachment just behind the back, so the avatar is never covered. **On the player's turn
  to shoot the aura is switched off** (every aura emitter, Orbiter, Arc, Beam, Light and the
  piece's glow effects), so nothing distracts from aiming; it comes back when the cue returns
  to the back. The cue itself, its surface and its trail and pocket effects stay on.
- **Skinned pieces (designer, 2026-09-30):** parts with `Skinned` in `piece.json` are `.glb`
  files (a MeshPart with Bones, import with rig); each Bone's `Transform = Rest^-1 *
  J_parent^-1 * J_bone * Rest` every frame, J from the joint's `Motion` list. Their
  SurfaceAppearance has `AlphaMode = Transparency` (the hologram look is baked in the maps) and
  a `<name>Shell` ForceField mesh follows the same bones.

### 6.4 The upload list

- **Surface maps:** 76 map sets in `assets/cue/textures/` (colour, normal, roughness,
  metalness, emissive where it glows; Legendary frames add up to 3 more sets each). They are
  rebuilt from the skin files, not committed.
- **VFX textures:** 110 PNGs in `assets/cue/vfx/` (`_shared/` plus one folder per skin and
  `rank/`).
- **Piece meshes:** 58 OBJs in `assets/cue/pieces/` (four pieces).

`tools/roblox_upload.py` and `tools/upload_manifest.json` already handle uploads; add these
paths to the manifest.

### 6.5 Doc updates

- **GDD:** the cue list and tiers (61 skins), the Mythic and Secret pieces, the VFX pieces (the
  list in 6.3), the Starter Cue now tradable.
- **ECONOMY:** the case contents by tier (the new ids), the Starter trading rule.
- **STATUS:** the cue skins built and waiting for review and import.
- **DECISIONS:** the run's assumptions are already logged (2026-09-29, "(assumption)").

## 7. Known issues

- **Unique cues (Q1) not built:** the concept sheet is missing.
- **The preview is Blender, not Roblox.** It builds each effect from the same pieces, but bloom
  and additive blending look a little softer in Roblox, and a ForceField part shimmers with
  Roblox's own animated pattern (the dragon's body).
- **Shared mesh proportions:** the sleeve is shorter than on most concepts, so sleeve art is
  smaller (noted per skin in the review file).
- **Flat OpenAI takes:** a few panels came out flatter or more graphic than their concept (the
  VIP most). The metal is set in the maps, so it still shines. A new take (`--force-ai --ai
  <panel>`) costs about $0.03.
- **Particle-only set pieces:** wings, tentacles, the fox spirit, the dragon roar and the
  eclipse corona are camera-facing flipbooks. They turn to face the camera, as Roblox particles
  do.
- Per-skin differences from the concepts are listed in the review file.
