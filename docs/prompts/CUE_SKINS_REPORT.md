# Cue skins: the report

The cue-skins run (brief: `CUE_SKINS_PROMPT.md`, branch `cue-skins`, worktree
`~/Desktop/8ball-skins`). Every skin is built on the shared cue mesh as textures, glow and a VFX
spec, with renders and a clip to review. **Nothing is imported into Roblox yet**: the import is
a later session, and the second half of this report is written for it.

**Status: 58 of the 61 new skins are built,** and the designer's upgrade pass (2026-09-30:
brighter, longer trails; bigger, denser auras; the creatures as rigged 3D holograms; Eclipse as
space) is done for every tier from Rare up, the Rank cues and the VIP Cue. The three Unique cues
(Founder's Cue, Beta Cue, Grand Opening) are waiting for their concept sheet,
`assets/cue/concepts/Q1.png`, and the designer will come back to them.

**The import is the next session:** its brief is `docs/prompts/CUE_SKINS_IMPORT_PROMPT.md`.

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
| Rare (10) | Honeycomb, Neon, Plasma, Blaze, Frostbite, Nature, Candy, Phantom, Tidal, Sakura | proc / mix | its own aura (14-20 particles/s, most with ribbons of light winding round the cue); the wisp tinted with a bright core; the pocket gust in its colours |
| Epic (9) | Void, Shooting Star, Magma, Toxic, Blood Moon, Prism, Aurora, Disco, Hacked | proc / mix | a moving material (overlay Beams and emissive pulses), an aura (19-31/s), a trail or pocket where plan.json lists one |
| Legendary (7) | Chroma, Thunderstrike, Phoenix, Kraken, Seraph, Infernal, Clockwork | mix (Clockwork proc) | SurfaceAppearance frames, a layered aura (28-57/s) with sprites made for it, 3D pieces (wings, tentacles, halo, crystals, skull, gears), its own trail and a staged pocket finisher (3D creatures rising for Phoenix, Kraken, Infernal, Clockwork) |
| Mythic (3) | Celestial Dragon, Kitsune, Apex | mix + a 3D piece (generated or scripted) | all of the above plus a moving 3D piece on the butt; the dragon and fox (on the cue and rising from the pocket) are rigged, animated holograms |
| Secret (1) | Eclipse | mix + a scripted 3D piece | space: a giant eclipse behind the cue's back half, a galaxy, gold orbits with planets, an asteroid belt, a small eclipse on the butt |
| Exclusive (2) | Starter Cue, VIP Cue | mix | Starter: blue ring and wisp. VIP: a rainbow-cycling ring, gold aura, own trail, a crown finisher |
| Rank (10) | Bronze, Silver, Gold, Platinum, Diamond, Expert, Veteran, Master, Grandmaster, Reyes | proc (one shared trophy design) | climbing from no VFX (Bronze) to a shine sweep, sparkles, ribbons, flames, own trails and finishers (Grandmaster, Reyes); tinted trails from Gold up |
| Unique (3) | Founder's Cue, Beta Cue, Grand Opening | - | **not built: waiting for `Q1.png`** |

The details of each skin (every VFX piece and number, and where it differs from its concept)
are in its review row and in `assets/cue/skins/<id>.json`.

## 3. OpenAI spend and model

- **Model:** `gpt-image-2.5-sunburst` (the newest image model on the key; it keeps precise
  edits), used through the edits endpoint with the panel layout and the concept crops.
- **Spend:** about **$3.30** for 89 images (the log is
  `assets/cue/concepts/openai_log.jsonl`; the last 7 were reference images for the 3D
  generator, the last a side-view gallop for the running fox). That is far below the $25 note and $150 stop.
- The chosen panels are committed in `assets/cue/skins/<id>/ai/`, so a repaint never pays
  again. `take: n` in a skin's `ai` block picks which take is used.

## 4. 3D pieces and the generator

**Meshy** (its API, `tools/meshy_generate.py`, key in the Keychain as `MESHY_API_KEY`) made 8
models from reference images: the Celestial Dragon head, the Kitsune mask, the Kitsune's running
fox, the Infernal skull, and the pocket dragon, fox, firebird and skull. **280 credits** in all (35 each; the log is
`assets/cue/models/meshy_log.jsonl`). The full downloads stay local; `CueModels.py compact`
commits a reduced `source.glb` and 1024 px maps per model.

| Piece | Triangles | Made by | Moves |
|---|---|---|---|
| celestial_dragon | 26.9k | scripted spirit body (scale texture, sheath, core, fins) + Meshy head (rigged hologram) | the whole dragon swims round the cue from the tip end to the butt end and back, turning at each end (30 spine bones riding a looping path, a lap in 10 s), a quick wave down its body, the tail flicks, the head nods, looks round and rears back roaring, the mane streams |
| celestial_dragon_pocket | 27.5k | Meshy (rigged hologram) | sways, nods, roars, claws |
| kitsune | 39.0k | Meshy mask and a small Meshy running fox (rigged holograms) | ears twitch, jaw opens; the fox gallops round the forearm; the tails are Beams |
| kitsune_pocket | 27.5k | Meshy (rigged hologram) | head tilts, nine tails sway |
| phoenix | 7.4k | scripted | two flame wings beat |
| phoenix_pocket | 27.5k | Meshy (rigged hologram) | wings beat, head and tail move |
| infernal | 19.5k | Meshy skull (solid obsidian ornament) | still |
| infernal_pocket | 27.5k | Meshy (rigged hologram) | jaw snaps |
| kraken / kraken_pocket | 10.8k / 6.3k | scripted | tentacles wave and curl |
| clockwork / clockwork_pocket | 12.7k / 4.6k | scripted | every gear turns, meshing |
| seraph | 2.5k | scripted | the halo bobs and sways |
| chroma | 0.2k | scripted | crystals orbit |
| apex | 9.4k | scripted | claws flex, rotor spins |
| eclipse | 37.6k | scripted | the sphere floats, rings precess, planets and asteroids orbit |

"Rigged hologram": a skinned mesh (bones follow the joints) drawn as see-through tinted light
with scanlines and a ForceField shell (report 6.3).

## 5. Particle budgets

Per cue in hand, as the brief set them (at most about 20 a second on Rare, 35 on Epic and 60 on
Legendary and up). A cue worn on a back runs at `BackRateScale` = **0.5** (every skin).

| Tier | Highest aura rate | Notes |
|---|---|---|
| Rare | 20/s (Blaze, Candy, Plasma, Sakura) | the lowest 14 (Phantom) |
| Epic | 34/s (Magma, Disco) | the lowest 28 |
| Legendary | 57/s (Infernal) | Phoenix 54; the lowest 28 |
| Mythic | 52/s (Kitsune) | Celestial Dragon 48, Apex 46.8 |
| Secret | 57.9/s (Eclipse) | |
| Exclusive | 27/s (VIP) | the Starter has none |
| Rank | 29.6/s (Reyes) | Gold 12, Platinum 16, Diamond 17; Bronze and Silver have none |

Orbiters, Arcs, Beams and Lights are not particles and are listed separately in each skin's
`Budget` (at most 5 Orbiters, 10 Beams, 2 Lights on one cue). Ball-trail emitters run only while
a ball rolls (up to 36/s on a Legendary).

---

## 6. For the import session

Everything below is what the game code and the shared docs need. This run changed none of
them (`src/`, `tests/` and the shared docs belonged to the abilities run).

### 6.1 Catalog changes

- **The tiers (designer, 2026-09-30: the plan `cue_skins_plan.html` is the source of truth):**
  62 cues, 47 of them case cues (8 Common, 9 Uncommon, 10 Rare, 9 Epic, 7 Legendary, 3 Mythic,
  1 Secret). Every skin file's `tier` matches it:

  | Tier | Count | Cues (`catalog_id`) |
  |---|---|---|
  | Common | 8 | Classic (`Classic`), Midnight (`MidnightCue`), Arctic (`ArcticCue`), Cherry (`CherryCue`), Carbon (`CarbonCue`), Heritage (`HeritageCue`), Monarch (`MonarchCue`), Cobalt (`CobaltCue`) |
  | Uncommon | 9 | Gummy (`GummyCue`), Flare (`FlareCue`), Hornet (`HornetCue`), Venom (`VenomCue`), Lagoon (`LagoonCue`), Splice (`SpliceCue`), Cosmo (`CosmoCue`), Gilded (`GildedCue`), Pixel (`PixelCue`) |
  | Rare | 10 | Honeycomb (`HoneycombCue`), Neon (`NeonCue`), Nature (`NatureCue`), Candy (`CandyCue`), Frostbite (`FrostbiteCue`), Plasma (`PlasmaCue`), Blaze (`BlazeCue`), Phantom (`PhantomCue`), Tidal (`TidalCue`), Sakura (`SakuraCue`) |
  | Epic | 9 | Void (`VoidCue`), Shooting Star (`ShootingStarCue`), Magma (`MagmaCue`), Toxic (`ToxicCue`), Blood Moon (`BloodMoonCue`), Prism (`PrismCue`), Aurora (`AuroraCue`), Disco (`DiscoCue`), Hacked (`HackedCue`) |
  | Legendary | 7 | Chroma (`ChromaCue`), Thunderstrike (`ThunderstrikeCue`), Phoenix (`PhoenixCue`), Kraken (`KrakenCue`), Seraph (`SeraphCue`), Infernal (`InfernalCue`), Clockwork (`ClockworkCue`) |
  | Mythic | 3 | Celestial Dragon (`CelestialDragonCue`), Kitsune (`KitsuneCue`), Apex (`ApexCue`) |
  | Secret | 1 | Eclipse (`EclipseCue`) |
  | Exclusive | 2 | Starter Cue (`StarterCue`), VIP Cue (`VipCue`) |
  | Rank | 10 | Bronze Cue (`BronzeCue`), Silver Cue (`SilverCue`), Gold Cue (`GoldCue`), Platinum Cue (`PlatinumCue`), Diamond Cue (`DiamondCue`), Expert Cue (`ExpertCue`), Veteran Cue (`VeteranCue`), Master Cue (`MasterCue`), Grandmaster Cue (`GrandmasterCue`), Reyes Cue (`ReyesCue`) |
  | Unique | 3 | Founder's Cue, Beta Cue, Grand Opening: not built yet (deferred by the designer) |

- **Replace the 30 placeholder case cues** in `src/shared/Progression/Catalog.luau` (7 Common,
  6 Uncommon, 6 Rare, 5 Epic, 3 Legendary, 2 Mythic, 1 Secret today) with the case cues above,
  one row per skin, in the plan's order. The id, name, tier and catalog id are in each
  `assets/cue/skins/<id>.json` (`catalog_id`, for example `KitsuneCue`). Strings go in the
  shared strings module. Update the case drop pools and odds tables that count cues per tier.
- **Classic is labelled Common but stays the default (designer, 2026-09-30):** its row's
  `Rarity` becomes `Common` (shop, inventory and Index show it as a Common), but everyone still
  owns it from the start, it is in no case (`Cases = {}`), and it stays not tradable and not
  sellable. So the cases drop 7 Commons. Check every place that tests `Rarity == "Default"`.
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
- `Trail.Brightness` and `Trail.Transparency` (a curve), and `Trail.Core`: a second, narrower
  Trail on the ball with its own `Color`, `Width` (of the trail's), `NearTransparency`,
  `Transparency`, `WidthScale`, `LightEmission` and `Brightness` (every trail from Uncommon up).
  Warm trails keep `LightEmission` low (about 0.2): Roblox keeps the felt behind a trail at
  1 - alpha x (1 - LightEmission), so additive red over blue felt reads pink.
- `vfx.Pocket.Piece` (6 skins): a 3D creature rises out of the pocket: `Piece` (a folder in
  `pieces/`), `Delay`, `Seconds`, and curves over its life for `Rise` (studs), `Scale`, `Spin`
  (degrees) and `Transparency`; its joints move as on the cue. `KeepRibbons: false` hides the
  default swirl ribbons that would cross it.
- `Style.Pocket.Colors` with `ColorShare` 0.7 on every Rare: the default gust mostly in the
  skin's colours.

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
  `Attachment`, a `Part` (an invisible cylinder along the cue, `FromStuds`/`ToStuds`/`Width`,
  surface or volume) for emitters that cover the whole cue, a `Point`, or a `Segment` (a thin
  cylinder `From`-`To` riding a piece's `Joint`, Phoenix's wing edges).
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
- **Pieces** (Legendary and up): `pieces/<id>/*.obj` become MeshParts welded to the cue, one per
  joint and material, each placed by its `Offset` in the Roblox cue frame, with the Roblox
  Material, Color, Transparency and Reflectance from `piece.json`. A small script animates each
  joint from its `Motion` list (Hinge, Sway, Spin, Bob with sine, snap or pulse waves; Path, below) about its
  `PivotRoblox`, parents first; `joint_matrix` in `CuePieces.py` is the reference maths.
- **Back-worn cues:** every emitter's Rate times `BackRateScale` (0.5).
- **Where the aura shows (designer, 2026-09-30):** on the back, the cue sits in front of the
  body and the big aura sprites (Eclipse's giant eclipse and galaxy, any large camera-facing
  sprite) sit behind the body: give them a negative `ZOffset` against the torso, or host them
  on an Attachment just behind the back, so the avatar is never covered. **On the player's turn
  to shoot the aura is switched off** (every aura emitter, Orbiter, Arc, Beam, Light and the
  piece's glow effects), so nothing distracts from aiming; it comes back when the cue returns
  to the back. The cue itself, its surface and its trail and pocket effects stay on.
- **Aura joints (designer, 2026-09-30):** a joint with `Aura: true` in `piece.json` (the
  Celestial Dragon's whole swimming dragon, the Kitsune's running fox) is part of the aura: hide
  it, its parts and its child joints with the rest of the aura on the shooter's turn.
- **Skinned pieces (designer, 2026-09-30):** parts with `Skinned` in `piece.json` are `.glb`
  files (a MeshPart with Bones, import with rig); each Bone's `Transform = Rest^-1 *
  J_parent^-1 * J_bone * Rest` every frame, J from the joint's `Motion` list. Their
  SurfaceAppearance has `AlphaMode = Transparency` (the hologram look is baked in the maps) and
  a `<name>Shell` ForceField mesh follows the same bones.
- **Path motions (designer, 2026-09-30: the Celestial Dragon swims back and forth along the
  cue):** `piece.json` has `Paths`: a looping track sampled every `Step` studs of arc length as
  `[x, y, z, qw, qx, qy, qz]` in the Blender cue frame (the rotation's columns are side, the way
  along the path and away from the cue). A `Path` motion `{Path, Rest, Speed}` puts the joint on
  the track: `X(t) = F(Rest + Speed * t) * F(Rest)^-1`, F the track's frame at that arc length
  (wrapping round the loop; between samples lerp the point and slerp the turn, `CFrame:Lerp`),
  applied before the joint's other motions in the list (so a Bob after it rides with the
  joint). Turn it into the Roblox cue frame like any joint matrix. `path_frame` and
  `motion_matrix` in `CuePieces.py` are the reference maths.

### 6.4 The upload list

- **Surface maps:** 76 map sets in `assets/cue/textures/` (colour, normal, roughness,
  metalness, emissive where it glows; Legendary frames add up to 3 more sets each). They are
  rebuilt from the skin files, not committed.
- **VFX textures:** 119 PNGs in `assets/cue/vfx/` (`_shared/` plus one folder per skin and
  `rank/`).
- **Pieces:** 16 folders in `assets/cue/pieces/`: 197 OBJs, 6 skinned GLBs and 23 maps
  (the generated models' spirit colour, emissive and normal maps). `preview.png` in each is
  for review only.

`tools/roblox_upload.py` and `tools/upload_manifest.json` already handle uploads; add these
paths to the manifest.

### 6.5 Doc updates

- **GDD:** the cue list and tiers (61 skins), the Mythic and Secret pieces, the VFX pieces (the
  list in 6.3), the Starter Cue now tradable.
- **ECONOMY:** the case contents by tier (the new ids), the Starter trading rule.
- **STATUS:** the cue skins built and waiting for review and import.
- **DECISIONS:** the run's assumptions and the designer's choices are already logged
  (2026-09-29 and 2026-09-30).

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
- **Camera-facing set pieces:** the eclipse coronas, Eclipse's giant eclipse and galaxy, and
  the flame and feather flipbooks turn to face the camera, as Roblox particles do (right for an
  eclipse, which is round from every side). The wings, tentacles, halo and creatures are 3D.
- **Hologram look in Roblox:** it is baked into the maps (see-through colour, glowing lines),
  so it should carry over, but check the transparency sorting against the aura in Studio.
- Per-skin differences from the concepts are listed in the review file.
