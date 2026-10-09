# Verity: assets

The cue ball becomes the Verity ball (yellow smiley). When it hits a ball it unfolds into the
Verity monster, grabs the hit ball, hurls it off the table and sprints off. Built 2026-10-08.

Rebuild: `/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python
tools/blender/abilities/verity.py [-- ball|monster|renders]` (no step = all three).

## Files

| File | What |
| --- | --- |
| `verity_ball_plush.png` | 1024 x 512 ball map for `assets/balls/ball_sphere.obj` (step `ball`): the plush smiley, 2026-10-08 |
| `verity_ball.png` | the first ball map (the flat smiley), kept as history |
| `verity_monster.glb` | the skinned monster, rest pose, no animations (step `monster`) |
| `verity_anims.json` | every action as per-frame bone matrices (step `monster`), 2.4 MB |
| `textures/verity_monster_basecolor.png` | the monster's one map, 1024 px (embedded in the glb) |
| `verity_line.mp3` | "Hi, I'm Verity! Trust me, I know everything!" (3.72 s) |
| `look_over_there.mp3` | "Look over there!" urgent (1.61 s) |
| `look_over_there_alt.mp3` | second take, another voice (2.07 s) |
| `upload_manifest.json` | this folder's upload results |
| `ref/` | the two reference images |
| `renders/` | previews (gitignored, rebuilt by step `renders`) |

## Uploaded (Open Cloud, group 675425213, 2026-10-08)

| File | Type | Asset id |
| --- | --- | --- |
| verity_monster.glb | Model | 97902969201000 (re-uploaded 2026-10-08 with welded, consistently outward faces; the first upload, 130065008141591, showed holes where seam-split islands had flipped) |
| verity_ball.png | Decal | 108837263159693 (a Decal id: read the image id via `InsertService:LoadAsset` in Edit before use in `TextureID`) |
| verity_ball_plush.png | Decal | 136005252737182 (the plush smiley; its image id 107401761851714 is in Config; in `../rework_upload_manifest.json`) |
| verity_line.mp3 | Audio | 135865093470317 |
| look_over_there.mp3 | Audio | 84561965728329 |
| look_over_there_alt.mp3 | Audio | 107522256357964 |

## The ball

Same layout as `tex_<n>.png`: the face is painted twice, centred on mesh -Z (u = 0.25) and +Z
(u = 0.75), the number-disc spots, so a ball at rest (identity rotation) shows it like a number.
Each face is drawn in its own orthographic view, so it reads round on the sphere. Warm yellow
#FFD21F at each face, shading to #E2A00C 90 degrees away; bold black ink (eyes are tall ovals
0.23 x 0.43 ball radii, smile stroke 0.16 radii) so it survives 20-55 px on a phone
(`renders/ball_phone.png` is 48 px).

**The plush smiley** (`verity_ball_plush.png`, the designer's second round, 2026-10-08: "needs to
look exactly like this", a plush smiley toy ball) keeps that layout. A bright warm yellow plush
(#FAD31E, lighter toward the top, fine fibre noise), two black upright ovals (0.16 x 0.31 radii,
centres 0.345 out and 0.247 up) and a wide embroidered grin, all measured off the reference in
the face's own view: a black outline (0.056 radii thick, thinning to 0.034 at the corners)
whose top edge dips to -0.284 in the middle and whose bottom edge is a rounded ellipse down to
-0.676, ending at each corner in a short stem under a bar; inside, two rows of white teeth, the
upper parted down the middle between two big front teeth (0.2 wide) and narrowing to the
corners, the lower with a tooth in the middle, all a little puffy at their corners. Checked
against the reference with an orthographic front render and an ink overlay.

**Mirroring:** this UV wrap reads mirrored from outside: in Blender, `tex_2`'s "2" shows backwards
from both sides. The Verity face is left-right symmetric, so it does not matter here, but the
numbered balls may draw mirrored in game; worth a look in Studio.

## The monster

- Source: Meshy image-to-3D from `ref/verity_monster_ref.png` (task
  01a11bda-ad77-74da-a35e-4576c392c51c, 30 credits), Meshy auto-rig (01a11bdd-1f07-7254-8974-c346302fa7ed,
  5 credits), 10 library clips (3 credits each). 65 credits in all. Downloads are local only in
  `assets/cue/models/verity_monster/` (`rig/`, `anims/`, gitignored, about 10 MB each; task ids in
  `rig/rig_meta.json` and `anims/anims_meta.json`; `tools/meshy_rig.py resume` re-downloads while
  Meshy keeps them).
- **8,000 triangles**, welded at the UV seams before decimating so every face points out (Roblox
  culls back faces), one mesh `VerityBody`, one material `VerityMonster` (base colour only).
- **Axes:** Blender Z up, faces **-Y**, feet at Z = 0, centred on X/Y, exactly **1.0 unit tall**
  (scale it in Roblox: 1 unit = 1 stud). Roblox's importer turns it half a turn about Y (see
  STUDIO_NOTES), bones included.
- **Skin:** 24 bones, at most 4 influences a vertex, weights normalised. Armature object `Verity`,
  world matrix identity.

Bones (child < parent), parent first as in the JSON:

```
Hips (root)
  Spine02 < Hips;  Spine01 < Spine02;  Spine < Spine01;  neck < Spine;  Head < neck
  head_end < Head;  headfront < Head
  LeftShoulder < Spine;  LeftArm < LeftShoulder;  LeftForeArm < LeftArm;  LeftHand < LeftForeArm
  RightShoulder < Spine; RightArm < RightShoulder; RightForeArm < RightArm; RightHand < RightForeArm
  LeftUpLeg < Hips;  LeftLeg < LeftUpLeg;  LeftFoot < LeftLeg;  LeftToeBase < LeftFoot
  RightUpLeg < Hips; RightLeg < RightUpLeg; RightFoot < RightLeg; RightToeBase < RightFoot
```

## verity_anims.json

```
armature: {name, world}                 world matrix of the armature object (identity)
bones:    [{name, parent, rest}]        rest = bone.matrix_local, armature space
actions:  [{name, source, fps, frames, loop, in_place, tracks: {bone: [matrix per frame]}}]
```

Every matrix is 12 numbers: the 3x3 rotation row-major, then the translation (Blender armature
space, units as the model), rounded to 4 decimals. Tracks are `pose_bone.matrix` (posed,
armature space). To drive a bone, use the skinning transform `posed @ rest^-1`; the renders apply
it to a re-import of the glb (whose bone axes differ) as `posed @ rest^-1 @ rest'`, which is what
the game must do in each Bone's own frame (STUDIO_NOTES, "The cue skins import").

Meshy's clips are 30 fps; they are resampled to **24 fps**. Loops are sampled over exactly one
period (the source's last key repeats its first), so frame N wraps to frame 0 cleanly.

| Action | Frames | Seconds | Loop | Meshy clip | Notes |
| --- | --- | --- | --- | --- | --- |
| Idle | 96 | 4.0 | yes | 0 Idle | |
| Run | 11 | 0.46 | yes | 16 Run Fast | in place |
| Sprint | 14 | 0.58 | yes | 509 Lean Forward Sprint | in place (2.45 m of forward root motion removed); the creepier lean |
| PickUp | 172 | 7.17 | no | 276 Male Bend Over Pick Up | right hand lowest at f36 |
| Grab | 145 | 6.04 | no | 284 Collect Object | deep crouch, hands lowest f75-81 |
| PickThrow | 117 | 4.88 | no | 280 Female Crouch Pick Throw Forward | **the grab-and-hurl:** right hand at the floor f24, release about f58 (fastest hand); then settles |
| Throw | 104 | 4.33 | no | 421 Over Shoulder Throw | release about f84; ends crouched, not back at rest |
| ThrowDown | 112 | 4.67 | no | 389 Grip and Throw Down | right-hand slam about f84 |
| Taunt | 117 | 4.88 | no | 88 Chest Pound Taunt | |
| Cheer | 225 | 9.38 | no | 59 Victory Cheer | |

Non-loop clips keep their small authored hip moves (under 0.21 units). For the ability:
PickThrow (grab + hurl), then Sprint (loop), with Idle and Taunt/Cheer around them. Drop unused
actions from the JSON to save size if needed.

## Voices (placeholders)

OpenAI `gpt-4o-mini-tts` with delivery instructions: `verity_line` voice shimmer (creepy-cheerful
sing-song), `look_over_there` voice coral, `look_over_there_alt` voice ash. Silence trimmed both
ends with ffmpeg; `verity_line` was 4.27 s after trimming and was sped up 1.15x (pitch kept) to
3.72 s. Whisper transcribed all three back as the intended words. They have not been listened
to by a person.

## Renders

`renders/ball_front.png`, `ball_shot.png` (35 degrees up, as the shooting camera),
`ball_side.png`, `ball_phone.png` (48 px); `monster_front.png`, `monster_threequarter.png`,
`monster_side.png`; `anim_<Action>.png`, 8 evenly spaced frames per action (4 x 2), posed from the
JSON on the re-imported glb.

## Problems and notes

- The arms are very long, so in a few Idle and Run frames a hand passes through a thigh.
- Meshy's `change_fps` post-process only changes its FBX output; the GLB clips stay 30 fps, so the
  script resamples them.
- The glTF importer adds an `Icosphere` object (its bone display shape); it is not in the glb.
- The game-side work (orienting the ball so the face shows, loading the rig, driving Bones from the
  JSON) is not done here.
