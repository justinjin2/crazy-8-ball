# Cue VFX techniques (what made the Beta and Firework Cues work)

Written 2026-10-04 at the end of the Unique cues lane (`docs/prompts/UNIQUE_CUES_PROMPT.md`,
report `docs/prompts/UNIQUE_CUES_REPORT.md`), as the starting point for every rarer cue from
here on. The designer's one-line brief for all of it: **"not 2D pictures warped and moving,
real 3D depth"**. Everything below serves that line. Read `docs/ARCHITECTURE.md` first for
the cue runtime's shape; this file is about the craft.

## 1. The depth rule, in practice

A cue aura reads as flat when it is one layer of billboard sprites drifting at one distance.
It reads as a thing in space when the eye gets depth cues: things behind the cue, things in
front, things that turn and show a side, light that changes with the view. The checklist:

1. **A real body.** At least one solid or wireframe mesh that is not the cue: a shell, a
   lattice, ribbons, rings, panels. Meshes catch perspective; sprites never do. Beta's hexagon
   lattice and section rings, the Grand Opening's two gold helices. Built in Blender from
   `assets/cue/CuePieces*.py`, exported as one GLB, driven by joints (section 4).
2. **Volume, not a plane.** Every cloud (haze, glow, motes, glitter) is hosted on a cylinder
   part that runs the cue's length (`Host.Shape = "Cylinder"`, `ShapeStyle = "Volume"`,
   `FromStuds`/`ToStuds`/`Width`), so particles are born all around the cue and some are
   behind it. A point host at the butt gives a flat puff.
3. **Dark behind light.** A low-rate, dark, non-additive body layer (`LightEmission 0`, navy
   or deep brown) sits inside the bright additive layers. On the white lobby floor the bright
   layers alone wash out to a white bar; the dark body gives them something to glow against.
   The same trick at the pocket: a navy `DarkRing` and `DarkColumn` under the flash.
4. **Things that fly off and come back.** Orbiters (`Aura.Orbiters`: a head emitter riding a
   path round the cue) and shed particles with `LockedToPart = false` give parallax as the cue
   moves. Beta's three data streams; the Grand Opening's two sparkle heads riding the ribbons.
5. **Oriented particles.** Rings and discs use `Orientation = "VelocityPerpendicular"` or
   `FacingCameraWorldUp` with an `EmissionDirection`, so they stand in space instead of
   facing the camera. Beta's cross-section rings peel off along the cue's axis.
6. **Light that is really there.** Two to four `PointLight`s in the aura's colours (dim, 0.45
   to 0.7, range 7 to 8; more floods the floor white), and `Highlight` outlines in the cue's
   own colour so the silhouette separates from the aura.
7. **Flipbooks only for the small things.** An 8x8 OneShot flipbook is right for a firework
   burst or a smoke puff (something that is itself a short event). It is wrong for the whole
   aura: a looping flipbook sheet at the cue's size is exactly the "moving picture" the rule
   bans.

Judge it in the real game, never on the dark Blender preview: `tools/vfx_lab.luau` in a Play
session puts each cue on an avatar's back and on a stand in the lobby, and the lobby floor
is bright. Screenshots from three angles (back, stand side-on, front), then a match for the
hands, the trail over the felt and the pocket.

## 2. The pipeline (where each piece of the look lives)

| Part of the look | Source | Tool | Lands in |
|---|---|---|---|
| Painted surface | `assets/cue/skins/<id>.json` (`panels`, `ai`, `colours`, `glow`, `plain_alpha`) | `python3 tools/cue_skin.py <id> --paint --maps` | `assets/cue/textures/<id>_{color,emissive,metalness,normal,roughness}.png` |
| 3D piece | `assets/cue/CuePieces*.py` (`@piece` functions) | Blender `-b --factory-startup --python assets/cue/CuePieces.py -- <id> --no-preview`, then `python3 tools/cue_pieces_glb.py <id>` | `assets/cue/pieces/<id>/<id>_parts.glb` + `piece.json` |
| Sprites, sheets | `tools/unique_sprites.py <sprite names>` (procedural), `tools/openai_image.py` (painted) | | `assets/cue/vfx/<id>/*.png` |
| Aura, trail, pocket, sounds | `assets/cue/skins/<id>.json` `vfx` block | `python3 tools/cue_skins_data.py` | `src/shared/CueSkins/Skins/<Id>.luau` (never hand-edited) |
| Card picture | the skin | `tools/cue_skin.py <id> --thumb --noaura` | `assets/cue/thumbs/<id>.png` |
| Uploads | the files above | `tools/roblox_upload.py --list <file> --group-id 675425213 --manifest tools/upload_manifest.json`, then `tools/manifest_image_ids.py emit` / `apply` | `tools/upload_manifest.json` |
| Templates and pieces in Studio | the rows | `tools/build_cue_templates.luau` in the command bar (Edit mode) | `ReplicatedStorage.CueSkins`, `ReplicatedStorage.CuePieces` |

The runtime (`src/client/CueSkinLook.luau`, `CuePiece.luau`, `CueVfx.luau`, `Effects.luau`,
`src/shared/CueSkins/Motion.luau`) is generic: it reads kinds from the rows. A new look is
data; a new *kind* of behaviour is a new row key handled for every cue, never an `if cueId`.

## 3. Surfaces: painting, glow and see-through

- **Painted panels.** The cue is painted as four panels (shaft tile, shaft top, forearm,
  butt) plus the cap end. The AI painter (`tools/openai_image.py`, the edits endpoint, the
  panel layout plus the concept crop as inputs) paints each panel; `assets/cue/CuePaint.py`
  and `CueTextures.py` lay them onto the shared UV atlas and derive roughness, metalness,
  height (to a normal map) and the glow mask. About $0.04 a panel.
- **Glow map.** The emissive map is a separate painted or keyed layer (`glow` keys in the
  skin pick colours out of the panels: the fireworks and stars on the Grand Opening, the
  blueprint linework on Beta). `surface.EmissiveStrength` sets the level and
  `surface.Pulse.EmissiveStrength {Min, Max, Period}` swells it. Beta pulses 0.8 to 1.3
  with a `#6FB8FF` tint; the Grand Opening 1.2 to 2.0. Above about 2 the body turns into a
  white bar on the lobby floor.
- **See-through bodies.** `surface.AlphaMode = "Transparency"` with an alpha channel in the
  colour map (`CuePaint`'s alpha companion, `put(alpha=)`) makes a hologram: the painted
  linework is opaque, the fill is 35 to 60 percent clear, and the lattice piece behind it shows
  through. `plain_alpha` keys give the tip and ferrule their own alpha so a white tip can
  still be part-transparent (the designer's gate-2 note: the tip is white, and holographic).
- **Collar, ferrule, tip.** `colours.tip/ferrule/bumper` paint them plain; a themed cue
  should instead key them into the panels and glow map so they match (the designer, 2026-10-04:
  from Legendary up they are themed and glowing, never the standard collar).
- **Bloom is the game's, not the cue's.** `Lighting.Bloom` is on (`Config` Lighting,
  Threshold 2.6). Anything above that brightness blooms: particle `Brightness` 3 to 7 with
  `LightEmission 1`, Neon parts, emissive above 2. Use it on the small hot things (cores,
  sparks, glints, the firework pops at 7) and keep large layers under it, or the whole aura
  blooms into one blob.

## 4. 3D pieces: meshes that move

`assets/cue/CuePieces.py` is a bmesh kit: `_lathe` (profiles turned round the cue's axis:
rings, funnels, the scan disc), `_torus`, `_box`, `sweep` (a profile along a path: ribbons,
helices, tentacles), `metaball_mesh`, wireframe shells (edges thickened to tubes). A piece is
a function decorated `@piece` that adds parts to a `Kit`, each part under a **joint**, and the
kit exports one GLB and a `piece.json` of joints, motions and visuals. The builder script
imports the GLB and rigs it under the cue; `CuePiece.luau` plays it every frame from
`Motion.luau` with the same maths as the Blender preview (`tests/cue_motion_test.luau` keeps
them equal through `tests/cue_motion_fixture.json`).

**Motions** (per joint, composable): `Hinge`, `Spin` (steady turn), `Bob` (a slide along an
axis on a wave), `Sway`, `Path`, `Glitch` (a jolt of `Amp` studs in `Dir`, `Steps` sub-jolts,
for `Seconds` once every `Period`). Wave shapes: `sin`, `tri`, `saw` (one way then snap back:
the scan line), `heartbeat`, `life`.

**Visuals** (per joint, `visual=` in the kit, `Visual` in the row): `Fade {Min, Max, Period,
Shape, Phase}` (transparency on a wave), `Blink {Period, Seconds, Phase, Count}` (gone for a
window), `Glow {Min, Max, Period, Shape, Color?}` (the part's colour lerped toward white or a
colour), `Type {Frame, Size, Rows, Cols, Rate, Delay, Period, Phase, Color, Area}` (a thin
part with a SurfaceGui that types gibberish glyphs, cursor and all, every life cycle; glyph
set, font and brightness in `Config.CueSkins.Typing`).

**The `life` shape** is how a panel is born, lives and dies: pop in over the first 6 percent
with two blinks, hold, dissolve with a flicker. Give each panel a different `Period` and
`Phase` and the field never repeats.

**Low** (`low='hide'` on a joint): the Lower-effects setting hides that joint, its children
and its typers. Hide the far-out detail (Beta's outer panels), keep the main form.

**What was built this way.** Beta: a hexagon lattice turning and glitching, section rings
with a glow pulse and fading edges, a scan disc sweeping the length, eight blueprint panels on
a life cycle typing glyphs, and a wireframe funnel for the pocket. Grand Opening: two gold
helices turning like a screw with sparkle heads riding them. Ribbons, blades, wings, halos,
creatures and planets are all the same recipe: a mesh per part, a joint per movement.

**Rules of thumb.** Wire thickness 0.07 to 0.09 studs reads from across a table; 0.03 does
not. A piece's `Outline`, `ShellFade` and `EmissiveScale` on a pocket piece row override the
finisher's default dark outline (Beta's funnel is outlined in its own blue, not black). A
`Glow` on a wireframe at 0 to 0.6 over 1.6 s is the "breathing" that sells it as energy.

## 5. The aura recipe (layer order, inside to outside)

1. **Body haze** (rate 10 to 22): `smoke_8x8` OneShot flipbook, dark colours, `LightEmission 0`,
   `LightInfluence 0`, `LockedToPart true`, drag 1.2, size 0.7 to 1.9, transparency 0.45 to
   0.8. The depth behind everything.
2. **Additive glow** (5 to 14): the same sprite, the cue's bright colours fading into its
   accent (blue into magenta; gold into violet), `LightEmission 1`, Brightness 0.8 to 1.
3. **Motes and glints** (6 to 12 of each): `dust` and `spark` sprites, tiny, with a white-hot
   core colour at birth, some with gravity (crackle sparks falling), some locked.
4. **Themed flecks**: a sprite sheet made for the cue (Beta's glyph sheet typing in and out,
   the Grand Opening's 8x8 burst flipbook in five colours at 0.8 a second per colour, a big
   burst every 4 s).
5. **Section shapes**: oriented rings or discs that stand on the cue's axis.
6. **Orbiters**: two or three heads riding paths round the cue with glowing heads (2.5
   brightness), trailing a short stream.
7. **Lights**: two to four `PointLight`s, 0.45 to 0.7, range 7 to 8, flickering for fire or
   sparklers.
8. **The piece** (section 4) and its `Highlight`.
9. **Sound**: `Aura.Sound {Asset, Volume, Looped, RollOff}`: a loop at 0.12 to 0.14 from an
   attachment 3.5 studs along the cue, `InverseTapered` roll-off 3 to 24 studs
   (`Config.CueSkins.Sound`). Faint: it is felt, not heard.

Budgets that held up on the lobby floor: about 170 to 215 particles a second, one or two
beams, two to four lights, two or three orbiters, before the Lower-effects pass. In the
shooter's hands the aura quiets to a quarter (`Config.CueSkins.Quiet.Shares.Unique = 0.25`),
sound volume included.

**Colour.** Every layer has a three-stop colour sequence: white-hot or pale at birth, the
cue's main colour in the middle, its accent at death. Saturated accents (`#FF2D9A`,
`#19D8FF`, `#FFC32E`) read; pastel ones vanish on the floor. The designer's gate-2 fix on the
fireworks was exactly this: bigger, brighter (7), more saturated.

## 6. Moving light along the cue

- **Overlay beams**: two cue-wide `Beam`s running tip to butt with a scrolling texture
  (`TextureSpeed`), one in each direction and at different widths (Beta's blue wireframe
  strip and a thinner magenta one the other way). The strip textures are procedural
  (`tools/unique_sprites.py wire_strip holo_strip sparkle_strip`).
- **Emissive pulse** (section 3) in a different period from the beams so the two never lock.
- **Piece motion**: the scan disc's saw sweep, the helices' spin. Three movements at three
  periods (1.6, 2.6, 4 s) is the floor for "alive"; one movement looks mechanical.

## 7. Trails

`Style.Trail` is a Roblox `Trail` between two attachments on the ball: `Colors` (two stops),
`WidthStuds`, `WidthScale` curve, `Lifetime` (capped at `Config.Effects.TrailMaxSeconds`,
0.45 s, whatever the row says), a `Texture` in `Stretch` mode (one picture along the whole
trail: Beta's holo strip) or `Wrap` with `TextureLength` (a repeating sparkle strip), and a
`Core` (a second, thin, white trail inside). A wire texture in `Wrap` at 0.5 width vanished on
the cloth; `Stretch` at 0.7 with a 0.3 core did not. `Trail.Emitters` ride the ball: rings
peeling off, shards, falling sparks (gravity `Acceleration [0,-6,0]`), coloured starlets.

## 8. Pocket finishers

A timeline of `Pocket.Layers`, each with `Delay`, `Burst` (count) or `Rate`, `Lifetime`,
`Host.Offset` (studs up from the pocket), over about 2 s:

1. A dark ring and a dark column under everything (section 1, point 3).
2. The flash and a coloured ring on the cloth.
3. The rise: the `Pocket.Piece` row (`Seconds`, `Rise` to about 0.8 to 4 studs, `Scale`
   0.8 to 1.7, `Spin`, `Outline {Color, Transparency}`, `ShellFade`, `EmissiveScale`) brings
   the pocket piece (a funnel, a creature, a crown) up out of the pocket turning.
4. Fountains (`Burst 50`, `Speed 7..13`, `SpreadAngle 22`, `EmissionDirection Top`,
   gravity −14) and staggered bursts (five, 0.25 s apart, three to four and a half studs up,
   each a flash plus rays plus falling sparks) in the cue's palette.
5. Motes or glitter raining down to close.
6. `Pocket.Sound {Asset, Volume}` once, from the pocket, roll-off 8 to 60 studs
   (`Config.Effects.Finisher.Sound`).

Keep the balls readable through it: nothing opaque below 0.5 studs over the cloth for longer
than 0.3 s.

## 9. Lower effects

Rates follow the Quality setting (the Grand Opening's 12/16/0.8 drop to 4.2/5.6/0.28);
`Low = "hide"` joints go; the piece's main form, the surface glow, the trail core and the
pocket's flash stay, so the identity survives.

## 10. Pitfalls met on the way

- Judging on the Blender preview: the lobby floor is white and bright; everything that looked
  rich on black washed out. Tune on the floor.
- PointLights flood the floor white long before particles do; prove it by switching them off.
- Lathe profiles take a signed distance along the cue; a wrong sign builds the part seven
  studs away.
- A glitch window under 0.2 s is invisible; a wire under 0.07 studs is invisible from the
  far rail.
- The skin row's `Id` is the skin id (`grand_opening`); the look's catalog id is `cueId`
  (`GrandOpeningCue`). Live-tuning probes that match on the row's `Id` match nothing.
- `tools/unique_sprites.py` takes sprite names, not skin ids.
- The generator filters keys: a new row key (`Pocket.Sound`) must be added to its allow-list
  or it silently never reaches the game.
- `Effects.luau` colour helpers take RGB tables; hex goes through `CueVfx.color`.
- Captures: the Studio camera override only renders particles near the real character, so
  the lab moves the avatar beside the row; off the floor's edge (z ≥ 96) you get the railing.

## 11. The checklist for the next rare cue

1. Concept board (full cue, handle, aura three-quarter, trail, pocket) from your own
   renders and paintings; approval before building.
2. Surface: panels, glow map, themed collar/ferrule/tip, alpha if see-through, pulse.
3. Piece: at least one mesh body with three motions at three periods, visuals, `Low` flags.
4. Aura: the nine layers of section 5 in order, dark body first; budget under about 220/s.
5. Trail with a core and ball-riding emitters; pocket timeline with a rise, a dark ring and a
   sound.
6. Lab on the lobby floor next to Eclipse from three angles; a solo fixture match; Lower
   effects; the Index card.
