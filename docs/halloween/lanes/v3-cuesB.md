# Lane v3 cuesB: the Halloween Sword's effects (2026-10-29)

Branch `hw3-cues-b` from 90e23dc8 (halloween). Worktree
`~/Desktop/8ball/.claude/worktrees/wf_a0729e1c-dc8-4`. No Studio in this lane: judged with the
headless Blender preview (`assets/cue/CuePreview.py`, which simulates the game's particles,
beams, trails and pocket layers) on the dark backdrop and on a cream lobby-like floor, and with
the painted frames themselves. Renders: `~/Desktop/8ball-refs/halloween/v3/cues-b/`.

## What was built

The designer (2026-10-29 ~12:00): the four event cues stay Unique but their effects climb like
a rarity ladder, the Halloween Sword the best and richest: more aura, a darker deep-purple
trail, and the finisher bigger and redone with no spinning ghosts: a detailed fiery Halloween
face like the carved purple jack-o'-lantern on the sword's hilt, laughing (no sound), with lots
of purple flames. All of it is skin data (`assets/cue/skins/halloween_sword.json`) on the
existing runtime; no Luau runtime change.

1. **Two sprites** (`tools/hw_sword_fx.py`, deterministic numpy + Pillow, loops seamlessly):
   - `vfx/halloween_sword/fire_face_4x4.png` (1024, 4x4 cells of 256): the hilt's jack-o'-lantern
     made of purple fire. Ribbed five-lobe rind (deep violet, lobe-shaded, seams inked), lit
     from inside around the carved holes, a lilac backlit rim on the crown, a curled stem;
     angry slanted eyes, a triangle nose, a jagged grin with two hanging and three rising teeth;
     the holes white-hot with a lit cut wall, the mouth glowing up from the jaw; a crown of nine
     banded flame tongues, licks breaking away, four flames licking up the cheeks; a dark-violet
     ink line round everything and a soft violet halo. The 16 frames are two cackles (the jaw
     drops, the eyes squint, the head bobs and tilts, the fire flares). Image 109113140681429.
   - `vfx/halloween_sword/toon_flame_4x4.png` (512, cells of 128): one bold banded flame tongue
     in the same palette and ink, for the blade, the trail and the finisher. Image 87257680474573.
   Both uploaded as Image assets (the id is the image id; no Decal step).
2. **Aura** (commit 0a9b1cb2): the edge flames wear the toon flame (12/s a side, was 5.5,
   mostly opaque, LightEmission 0.15: reads on the cream floor, not as additive mush); a third
   beam `BladeAura`, a soft deep-violet glow band behind the blade and its flame border,
   breathing (Pulse 1.6 s); `BladeGlow`, 3 faint deep glow motes a second; deeper sparks and
   blade light; the guard mist lighter (it read as a dark smudge on the cream floor). 39
   particles a second (was 21), half on the back; Lower effects hides the edge flames, the
   motes and the glow band (12/s and the two border beams stay).
3. **Trail** (105cfc43): the ribbon painted with the sword's own `flame_strip` (already
   uploaded), deep violet fading to near-black violet, LightEmission 0.15, 0.6 wide, a thin lilac
   core; it sheds toon flames (14/s) and a faint dark-violet smoke wake (6/s) beside the sparks
   (12/s): 32/s while the ball moves (the Jack's 39).
4. **Finisher** (98a7cf96, e9a1433b), about 2.6 s: a violet flash, three rings, a bed of 22
   toon flames out of the pocket, then the fire face (one particle, 4.2 studs at most, Loop at
   13 fps = two cackles every 1.2 s) rising out of the pocket (emitted 0.4 under it, so the
   table hides its chin at first; it settles with its chin about a stud over the cloth), a
   5.4-stud deep-violet glow behind it, flames licking round it (22 at 0.35 s, a second wave of
   22 at 0.9 s, both from a 3.4-stud host so they show past the face) and over its chin (7, in
   front), 50 embers floating up, 26 sparkles, then faint dark-violet smoke. 159 particles
   once, 2 of them big; no 3D piece and no swirl ribbons. The `halloween_sword_pocket` row (the
   three ghosts) is no longer generated; its source files stay in `assets/cue/pieces/`.

`tests/halloween_sword_test.luau` (4 tests) checks the face layer (one looping 4x4 particle,
3.5-5 studs, rising, fading, in front of the flames), the finisher's budget (at most 200 once,
at most 4 particles of 3+ studs, 3 rings), the aura (30-60/s, at most 15/s left under Lower
effects, 2 lights, 3 beams, the edge flames opaque and hidden under Lower effects) and the dark
trail (painted, LightEmission at most 0.3, a near-black tail, its flames, at most 40/s).

## Cost (phone)

Textures: +1 MB-class 1024 face sheet (loaded with the Sword's shot sprites, only at a table
with a Sword owner), the 512 toon flame replaces the 1024 soft flame sheet on the aura (net
less). Aura 39/s (Lower effects 12/s), one more beam. Trail 32/s while the ball moves. Finisher
159 particles once per pot (every pot of the owner's balls: a break that drops three shows three
faces), two of them big quads (overdraw on a phone: the face and its glow). No per-frame Luau.

## How to check by hand (Studio, the coordinator)

1. No template rebuild for the Sword (no piece changed). The unused template
   `Piece_halloween_sword_pocket` may stay (nothing draws it) or be deleted.
2. Equip the Halloween Sword, open the lobby: the blade's painted flames lick off both edges, a
   deep-violet glow band sits behind the blade; on the back the same, quieter. Lower effects:
   only the border beams, sparks and mist stay.
3. Play a solo game, pot a ball: the cue ball trails a dark deep-purple flaming slash with a
   lilac core; the pocket bursts flames and the fire face rises out of it, cackles twice or
   three times and fades into smoke. Check it on the bright lobby floor and from the match
   camera: the face should read (ink line), not wash out, and not hide the table too long.
4. The two images are fresh uploads: if the face or flames show blank in the first minutes,
   that is Roblox still generating them (`ContentProvider:PreloadAsync` should give Success).

## Renders (`~/Desktop/8ball-refs/halloween/v3/cues-b/`)

- `face_contact.png`: the face's 16 frames on dark and on cream; `face_00/04/08/12_{dark,cream}.png`
  full-size frames (closed grin, first cackle, closed, second cackle); `face_loop_{dark,cream}.gif`
  the loop at its in-game 13 fps; `flame_contact.png` the toon flame's 16 frames.
- `compare_aura.jpg`, `compare_trail.jpg`, `compare_finisher.jpg`: before (v5) and after (v3)
  stills from the same preview frames, dark backdrop, plus the bright-floor read.
- `after/finisher_frames_{dark,bright}.jpg` (every 1/6 s from the drop), `after/finisher_{dark,bright}.gif`,
  `after/finisher_*_00285.png` / `_00300.png`, `after/aura_turn_*.png`, `after/trail_*.png`,
  `after/aura_still_*.png`, `after/clip_after_{dark,bright}.mp4` (the whole preview clip).
- `before/`: the v5 clip, its frames and stills.

## Open issues / not verified

- Not seen in Roblox: the Blender preview follows the game's particle rules, but bloom, real
  ZOffset sorting against the table and the match camera's framing need the Studio check above.
- The face is big (the designer asked for bigger): 4.2 studs for about 2.4 s on every pot. If it
  hides the table too much in a match, shrink `Pocket.Layers[Face].Size` (and `FaceGlow`) or
  shorten its Lifetime; it is one number each.
- `assets/cue/pieces/halloween_sword_pocket/` and its builder block in
  `assets/cue/CuePiecesHalloweenSword.py` are now unused (cleanup later, own commit).
- The old `vfx/halloween_sword/flame_4x4.png` is no longer used by any skin (cleanup later).
