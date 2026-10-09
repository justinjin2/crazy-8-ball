# Guangdong Tiger v2: the skinned tiger (2026-10-08)

This is a realistic Bengal tiger for the Guangdong Tiger ability. It is one skinned mesh on a
hand-built quadruped rig, with five actions. It replaces the rigid-part tiger made by
`tools/blender/abilities/tiger.py` (`GuangdongTiger.glb` / `.blend` and `textures/tiger*.png`).
Those old files are still here and are still what `src/` loads until the runtime switches over.
`slash.png`, `fur_frame.png` and the cut ball's halves also still come from `tiger.py`.

## How it was made

1. **Reference:** `ref/tiger_ref.png`, made with `tools/openai_image.py` (one call, about
   $0.04). It shows a side three-quarter view of a full-body tiger with fangs and golden eyes.
2. **Mesh:** Meshy image-to-3D, task `01a11bda-d3a4-744f-9911-a526af30e268` (30 credits),
   polycount 30000, 2k textures.
   - The full download is in `assets/cue/models/tiger_v2/`. Its glb and maps are gitignored.
   - The committed source is `source/tiger_v2_meshy.blend`: Meshy's mesh untouched, with only
     its base colour at 1024.
3. **Build:** everything else is rebuilt headless by `tools/blender/abilities/tiger_v2.py` in
   about 20 s. The rebuild is byte-identical to the uploaded glb.

   ```
   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/abilities/tiger_v2.py
   ```

   Set `TIGER_NO_RENDER=1` to skip the renders. `TIGER_STAGE=mesh` stops after the mesh and
   prints the cross-sections that were used to place the bones.

## Files

| File | What |
|---|---|
| `tiger_v2.glb` | One skinned mesh (`TigerMesh`) plus its armature (`TigerRig`). One material (`TigerFur`) with the base colour embedded. No animations. 2.9 MB. |
| `tiger_v2_anims.json` | Every action, baked per frame per bone (format below). |
| `tiger_v2.blend` | The built scene, with the five actions as real Blender actions (for a look). |
| `textures/tiger_v2_basecolor.png` | 1024 x 1024 base colour. |
| `source/tiger_v2_meshy.blend` | The build's input (see above). |
| `renders/` | `tiger_v2_stills.png` (3 angles) and `anim_<Action>.png` contact sheets. The folder is gitignored, so rebuild to see them. |
| `upload_list.txt`, `upload_manifest.json` | The upload's input and result. |

## Mesh

- **Size:** 9,999 triangles and 5,091 vertices in Blender. The glb has 9,998 triangles and
  14,262 vertices after its UV and normal splits.
- **Texture:** 1024 x 1024 PNG, base colour only. Meshy's metallic, roughness and normal maps
  were dropped.
- **Clean-up:**
  - Meshy's UV-seam splits were welded, so the skin deforms as one surface.
  - The whiskers were deleted. They were paper-thin strips, smaller than a pixel in the game,
    and they stretched into white spikes when the jaw opened.
  - The head was turned 25 degrees straight: the reference's head looked at the camera.

## Axes and scale

- **Blender:** the tiger faces **-Y**, up is **+Z**, and its own left is **+X**.
  - Feet are at Z = 0, and it is centred on X (the average of the four legs).
  - The nose is at Y = -0.5 and the tail base at Y = +0.5, so **nose to tail base = 1.0**
    exactly.
  - Full bounds: X -0.166..0.182, Y -0.5..0.843 (the tail tip), Z 0..0.601 (the ear tips).
- **Roblox (STUDIO_NOTES):**
  - Blender +X arrives as Roblox -X, +Y as +Z, and +Z as +Y. So the loaded tiger faces Roblox
    **-Z** (the LookVector).
  - 1 unit = 1 stud before the runtime scale.
  - Bones arrive half a turn round as well. Build each `Bone.Transform` in the loaded bone's own
    rest frame.

## Bones (24)

Every bone's X axis is the tiger's +X side, and Y runs along the bone. In armature space, a
positive turn about X pitches a forward-pointing bone nose-down and swings a hanging leg back.

| Bone | Parent | Notes |
|---|---|---|
| Root | none | On the ground under the hips. Non-deforming (no weights). Never animated. |
| Hips | Root | The pelvis. The only bone that moves (vertically only). |
| Spine1, Spine2, Chest | Hips, Spine1, Spine2 | |
| Neck, Head | Chest, Neck | |
| Jaw | Head | The lower jaw. It splits just under the upper fangs. |
| Tail1..Tail4 | Hips, Tail1, Tail2, Tail3 | Four equal lengths along the tail. |
| ShoulderL, ForearmL, FrontPawL | Chest, ShoulderL, ForearmL | Shoulder to elbow, elbow to wrist, wrist to toes. |
| ShoulderR, ForearmR, FrontPawR | Chest, ShoulderR, ForearmR | |
| ThighL, ShinL, HindPawL | Hips, ThighL, ShinL | Hip to knee, knee to hock, hock to toes. |
| ThighR, ShinR, HindPawR | Hips, ThighR, ShinR | |

**Skinning:** Blender bone-heat weights, then these fixes:

- No leg weight across the midline, or along the chest and belly midline.
- Front legs kept off the belly behind the elbows. Hind legs kept off the belly in front of the
  thighs.
- Lower leg bones only below the body. The paws own everything below the wrist and hock.
- The tail only behind the rump. The jaw is set by the mouth line.
- Four smoothing passes. At most 4 influences per vertex, normalised.

## Actions (24 fps)

| Action | Frames | Loop | What |
|---|---|---|---|
| Run | 16 | yes | A rotary gallop (hind L, hind R, front R, front L). Two flights per stride: stretched out, then gathered. The back flexes, the head stays level, the jaw is open in a snarl and the tail streams. |
| Pounce | 20 | no | Crouch (0-6), explode up (7-9), front legs reach out past the nose with the hind legs trailing (9-14), front paws strike down (15-17), land (19). |
| Swipe | 20 | no | Rear onto the haunches (0-6), the right paw cocked by the head (7). The body throws forward and down and the right paw slams through the ball (BALL_AHEAD ahead of the origin; its claws on it at 8) into the cloth past it (9), pressed there while the left paw cocks (11). The left paw slams back across the same spot (on it at 12, pressed at 13). Rise back to all fours (15-19). |
| Roar | 24 | no | Inhale with the head up (0-5). Thrust forward with the jaw wide open (40 degrees) and a head shake (9-17). Settle (18-23). |
| Idle | 48 | yes | One slow breath, a head turn, a slight jaw move and a lazy tail sway. |

- **Root motion:** Root never moves. Hips moves only vertically (Pounce lifts it 0.15). The
  game moves the model.
- **Run speed:** a stride of **1.2 units per 16-frame cycle**, which is 1.8 units a second at
  24 fps. Move the tiger 1.2 x scale per cycle, or the planted paws slide.
- **Loops** hold frames 0..n-1. Frame n is frame 0, so don't add it again.
- **Legs** are placed by a two-bone IK when the actions are baked. Planted paws stay put on
  Z = 0.

## tiger_v2_anims.json

Top-level fields:

- `boneOrder`: the bone names.
- `armatureWorld`: 16 numbers, row-major (identity).
- `bones[name]`: `parent`, `rest` and `length`.
- `actions[name]`: `fps`, `frames`, `loop` and `poses[bone]`, a list of one matrix per frame.
- `run.stridePerCycle`.

Every matrix is 12 numbers in Blender armature space: a row-major 3x4,
`r00 r01 r02 tx  r10 r11 r12 ty  r20 r21 r22 tz`. The 3x3 columns are the bone's X, Y and Z
axes. `rest` is `bone.matrix_local`; a pose is `pose_bone.matrix`. Values are rounded to 4
decimals.

**A frame-independent way to play it in Roblox:**

1. Take D = P x R^-1, the bone's move from rest in armature space.
2. Convert D to Roblox axes with C: (x, y, z) -> (-x, z, y).
3. The bone's wanted world CFrame is model x C(D) x (the bone's rest CFrame relative to the
   model).
4. `Bone.Transform` = (the parent's posed world CFrame x `Bone.CFrame`)^-1 x the wanted CFrame.

## Upload

- **Model asset id `121333510236552`**, uploaded with group 675425213 as owner through Open
  Cloud (`upload_manifest.json`).
- **Not yet checked in Studio:** `src/` and Studio belong to another session. To check:
  1. Run `pcall(InsertService.LoadAsset, InsertService, 121333510236552)` in Edit.
  2. Expect a Model with a RootPart, the Bones and one MeshPart.
  3. Preload its TextureID before the tiger shows.

## Known limits

- **Jaw:** the mesh's mouth is modelled only slightly open. Opened to the Roar's 40 degrees, the
  teeth and the inside stretch. From the game camera it reads as a wide, dark mouth with fangs.
- **Shoulder crease:** a front leg raised to head height creases the chest where the upper arm
  meets it. The Swipe's wind-up stays forward-up to keep this small.
- **Stance:** Meshy's stance is a little uneven. The left front paw stands about 0.05 ahead of
  the right, and the left hind about 0.05 behind. The rig keeps those rest positions.
- **Fur:** the chest and neck ruff is spiky fringe geometry. It reads as fur at game size.
- **Pounce launch:** it is explosive on purpose. The body snaps up over frames 7-9 (the head
  moves about 0.29 units in one frame).
