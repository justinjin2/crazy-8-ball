# Abilities rework assets (2026-10-08)

The assets for the abilities rework (`docs/prompts/ABILITIES_REWORK_PLAN.md`): the Catch-a-Ball
model and effects, the Steel Ball spiral and spin overlays, three new icons and the sound
candidates. Everything was built headless; the scripts rebuild it from nothing.

| Script | Run | Makes |
|---|---|---|
| `tools/blender/abilities/catchball.py` | `Blender -b --python tools/blender/abilities/catchball.py` | the catch ball `.glb`/`.blend`, its atlas, CatchGlow/Star/Beam |
| `tools/blender/abilities/steelball_fx.py` | `python3 tools/blender/abilities/steelball_fx.py` (numpy + PIL, no Blender) | golden spiral, spin blur, spin arrows |
| `tools/blender/abilities/icons_v2.py` | `Blender -b --python tools/blender/abilities/icons_v2.py -- [Id ...]` | the three new icons, on the `icons.py` rig |

Previews (not committed) are in each folder's `renders/`.

## Uploaded ids

Uploaded through Open Cloud to group 675425213. Every result is in
`assets/abilities/rework_upload_manifest.json`, and the upload list is
`assets/abilities/rework_upload_list.txt`. `tools/upload_manifest.json` was not touched.

| File | Type | Asset id | Image id |
|---|---|---|---|
| `CatchABall/catchball.glb` | Model | 93342911188193 | (the embedded atlas becomes the parts' `TextureID` on load) |
| `CatchABall/CatchGlow.png` | Decal | 126247127851969 | needs Studio |
| `CatchABall/CatchStar.png` | Decal | 133183700633587 | needs Studio |
| `CatchABall/CatchBeam.png` | Decal | 92411465206885 | needs Studio |
| `SteelBall/golden_spiral.png` | Decal | 109945245461564 | needs Studio |
| `SteelBall/golden_spiral_only.png` | Decal | 103684829037298 | needs Studio |
| `SteelBall/spin_blur.png` | Decal | 130147846106707 | needs Studio |
| `SteelBall/spin_arrows.png` | Decal | 109720204127941 | needs Studio |
| `icons/CatchABall.png` | Decal | 81283085243167 | needs Studio |
| `icons/LookOverThere.png` | Decal | 85056727532784 | needs Studio |
| `icons/Verity.png` | Decal | 129053492763689 | needs Studio |

**Image ids.** An uploaded PNG is a Decal, and an `ImageLabel` or `ParticleEmitter` needs the
image inside it (STUDIO_NOTES, "Images come back as a Decal ID"). The API key cannot read assets
(asset-delivery returned 403), so the image ids still need Studio. Run this in Edit mode (the
Studio MCP `execute_luau` or the command bar). Then write each `imageId` into the manifest
entry that has that `assetId`.

```lua
local InsertService = game:GetService("InsertService")
local out = {}
for _, id in { 126247127851969, 133183700633587, 92411465206885, 109945245461564, 103684829037298,
	130147846106707, 109720204127941, 81283085243167, 85056727532784, 129053492763689 } do
	local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
	local decal = ok and model:FindFirstChildWhichIsA("Decal", true)
	table.insert(out, ("%d=%s"):format(id, decal and string.match(decal.Texture, "%d+") or "ERR " .. tostring(model)))
	if ok then
		model:Destroy()
	end
end
return table.concat(out, "\n")
```

The model is checked with `pcall(InsertService.LoadAsset, InsertService, 93342911188193)`.
Preload its parts' `TextureID` before the catch first shows.

## A. Catch ball (`assets/abilities/CatchABall/`)

The ball takes the capture-ball idea without copying it. It is red over white with a black
band. The button is a **square** with rounded corners, a white face, a grey ring and a dark
square plate curved to the shell. The back carries a visible **notched hinge**: five
alternating knuckles on a steel pin and a zig-zag-edged leaf plate below them.

- **Units and axes:** the shell's outer radius is 1.0, so the ball is 2 studs across; scale it
  to the ball in code (`common.BALL_STUDS`). In Blender, front is -Y, up is +Z and the hinge is
  at the back (+Y). In Roblox, Blender +Y arrives as +Z and +Z as +Y. So the **button faces
  Roblox -Z** (an unturned part's LookVector), up is +Y and the hinge sits at Roblox +Z.
- **Pivot:** the hinge pin's axis point, H = Blender (0, 1.035, 0) = Roblox (0, 0, 1.035) in
  the model's frame. Every part's origin is at H (the glb nodes are translated there). The
  importer may re-centre MeshParts on their bounds, so read the **`J_Hinge`** marker (a
  0.02 cube at H) instead of trusting the pivots, as the tiger's `J_*` markers do.
- **Opening:** turn `CatchTop` about the X axis through H. In Blender, -70 degrees about X
  lifts the front edge (see `renders/catch_open.png`). In Roblox the same opening is a
  rotation about the X axis through the hinge, front edge up; check the sign once in Studio.
- **Material:** there is one material and one 256 px atlas (`textures/catch_atlas.png`,
  embedded in the glb), so each object loads as one MeshPart sharing one `TextureID`. The
  colours are red #E3262E, white #F4F4F4, the band #17171C and the inside #2A2B33. For the
  gloss, set `Material = SmoothPlastic` (or Glass with low transparency) in Roblox, because
  gloss is not baked.

| Object | What it is |
|---|---|
| `CatchTop` | the upper shell (z >= 0): red outside, a thin black lip at the rim (it continues the band when closed), dark inside, and the lid's two knuckles. The part that opens. |
| `CatchBottom` | the lower shell (z <= -0.085 rad): white outside, dark inside |
| `CatchBand` | the black band on the bottom half (from -0.085 rad up to the seam), flush with the shell. It carries three base knuckles, the steel pin and the zig-zag leaf plate at the back. |
| `CatchButton` | the square button at the front, centred on the seam |
| `CatchInner` | a two-sided dark disc just under the seam (z = -0.02), with a faint red ring and a light dot, seen when the lid is open |
| `J_Hinge` | the 0.02 marker cube at H |

The model has 14.1k triangles in total, most of them in the two shells, so decimate the
shells if it shows in profiling. There is also `catchball.blend`.

**Effect images (RGBA, transparent):**

- `CatchGlow.png` (256 x 256): a soft white radial glow with a brighter middle. Tint it in code.
- `CatchStar.png` (128 x 128): a white four-point sparkle star with a soft core.
- `CatchBeam.png` (256 x 64): a red energy beam with a white-hot core, clear at the top and
  bottom edges. Its wobble uses whole periods, so it **tiles along U** (a Beam with
  `TextureMode` Wrap, scrolled with `TextureSpeed`).

## B. Steel Ball (`assets/abilities/SteelBall/`)

- **`golden_spiral.png`** (1024 x 640): the golden-ratio diagram in #FFD200 lines, a pale hot
  core and a soft orange-gold glow on clear. The rectangle is 900 x 556.2 px with its top
  left at (62, 41.9). The biggest square is on the left, as in `ref/golden_spiral_ref.png`.
  The spiral starts at the rectangle's bottom-left corner (62, 598) and winds clockwise into
  its eye near (713, 444) px, low right of centre. The lines are 11 px for the squares and
  18 px for the spiral, and squares under 34 px are left out so they don't blur into a dot.
- **`golden_spiral_only.png`**: the same size and the same pixel alignment, with only the
  spiral, so the game can fade the squares and the spiral separately (draw both, cross-fade).
  To have the spiral "draw itself", reveal it along the path from (62, 598) to the eye.
- **`spin_blur.png`** (512 x 512): white comet-like arc streaks in three-fold symmetry, bright
  at the head and fading behind it. The head leads **counter-clockwise** as drawn. A faint
  blur band runs under the streaks, and the middle is clear to radius 0.42 of the half-size.
  Put it on a disc round the ball and spin the disc.
- **`spin_arrows.png`** (256 x 256): two white curved arrows chasing each other round a circle,
  counter-clockwise as drawn.

The existing `SteelBall.glb` and `textures/` (the old green ball) are untouched.

## C. Icons (`assets/abilities/icons/`)

These are 512 x 512 transparent images on the `icons.py` rig (the same camera, lights, ink
outline and framing), with the rim light in the rarity colour.

| Icon | Rarity | Picture |
|---|---|---|
| `CatchABall.png` | Rare | the catch ball (this model), closed, turned and tilted, with two sparkle stars at its top right and a soft red glow |
| `LookOverThere.png` | Epic | a white cartoon glove on a purple sleeve pointing hard up and right at a big glossy yellow "!" on a red comic burst |
| `Verity.png` | Legendary | the yellow smiley ball (tall black oval eyes, a wide smile with ticked ends) with four long, bony, knuckled yellow fingers with dark claws curling over its top from behind |

## D. Sounds

See `sounds_v2.json` (machine-readable, the first candidate in each slot is the recommended
one) and `SOUNDS_V2.md` (the table, and how they were found and checked). All of them are
public Creator Store clips played by id. Nothing was uploaded. Audition each one in Studio
before wiring it in.

## E. Verity v2: the evil Verity ball (`assets/abilities/VerityEvil/`)

The designer's second rework round (2026-10-08): the Verity monster model never showed in the
game, so Verity stays a ball. At the first contact the smiley cue ball turns evil, swells up and
eats the ball it hit. This is that evil ball: a toothy chomper crossed with an evil smiley, built
headless from nothing by `tools/blender/abilities/verity_evil.py`:

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/verity_evil.py [-- render names]

It makes `verity_evil.glb` and `verity_evil.blend`, `textures/verity_evil_atlas.png` (embedded in
the .glb) and the previews in `renders/` (not committed).

**Uploaded:** `VerityEvil/verity_evil.glb`, a Model, asset id **131086829663737** (group
675425213; in `rework_upload_manifest.json`, queued in `rework_upload_list.txt`). Open Cloud
reports it `Active` and moderation `Approved`. Check it in Studio with
`pcall(InsertService.LoadAsset, InsertService, 131086829663737)` and preload its parts'
`TextureID`. (The old monster, 97902969201000, also reports Active and Approved, so its failure
in the game was a loading problem, not moderation.)

**Axes** (the same as the catch ball): unit radius (the shell's outer radius is 1.0), front =
Blender -Y = **Roblox -Z** (the LookVector of an unturned part), up = +Z = Roblox +Y. Every
object's origin is the hinge pin H, at Blender (0, 1.035, 0): the back, just outside the shell
(Roblox +Z). About 13,600 triangles in all: VerityTop 6,634, VerityBottom 6,396, VerityEyes 576,
J_Hinge 12. One material, one 256 x 256 atlas, so each object is one MeshPart.

| Object | What | Intended look in Roblox |
|---|---|---|
| `VerityTop` | the upper jaw: the shell, a gum ring at the seam with the upper teeth hanging from its front (11 teeth over about 200 degrees, the front fangs longest, none near the hinge), the two eye sockets (dark rings standing proud) and the thick black brows slanting down to a V | the atlas as is (`TextureID`); glossy yellow outside, so SmoothPlastic or similar |
| `VerityBottom` | the lower jaw: the shell, a gum ring with the lower teeth (10) standing inside the upper row, half a tooth round, so they interleave, and the tongue lying in the bowl | the atlas as is |
| `VerityEyes` | the two angry slanted almond eyes, one flat red, sitting recessed in the sockets | `Material = Neon`, `Color` a strong red (about 255, 40, 20), so they glow; turn it with VerityTop |
| `J_Hinge` | a 0.02 cube at H: the importer may not keep object origins, so read the pivot from this one | `Transparency = 1` (it shows as a speck at the back otherwise) |

Atlas colours: the outside is a yellow gradient by latitude (FFE24D at the top, the smiley's
FFD21F at the equator, D9900B at the bottom pole), with a thin dark band (4E0B16) along the seam
on both jaws so a shut mouth still reads. The inside is maroon by depth (8E1C2E at the lip to
3A0710 at the bottom: never black, it reads as a mouth). The gums are 9C2338, the teeth go from
a warm ivory at the gum to bright white at the tip, the brows are 120D0C, the sockets 2A0A0D,
the eye cell FF2A14, and the tongue is pink-red with a darker groove down its middle.

**The jaw** opens by turning `VerityTop` and `VerityEyes` together about the X axis through H,
the front edge rising (Blender `rotation_euler.x = -angle`; Roblox: about the hinge's X axis).
These poses were checked in the renders:

- **Shut, 0 degrees** (`shut_front34`, `shut_side`): nothing inside pokes out. The dark seam
  band shows as a thin mouth line.
- **Grin, 10 degrees** (`grin_front34`, `grin_high`): the two rows of teeth show interleaved in
  the gap, a sinister grin. From the high table camera, **12-14 degrees** shows more of the
  teeth (`grin14_high`).
- **Gape, 70 degrees** (`gape_front34`, `gape_high`): the maroon mouth, the tongue and both
  rows of teeth. The eyes ride up with the top jaw.

The face reads at phone size from the high camera (`grin_high_phone`, `gape_high_phone`, 96
px). Sounds for it: SOUNDS_V2.md, "Verity v2".
