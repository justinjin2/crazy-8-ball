# Lane v3 cuesA (2026-10-29): the Pitchfork, the Jack-o'-Lantern and the Witch's Broom

Branch `hw3-cues-a` from `halloween` @ 90e23dc8. No Studio: judged with headless Blender
(`tools/cue_skin.py <sid> --stills --clip --quick`, the piece previews) and by reading the
runtime (`CueSkinLook`, `CuePiece`, `Effects.pocketBurst`/`skinFinisher`, `CueVfx.emitter`).
Renders: `~/Desktop/8ball-refs/halloween/v3/cues-a/` (`before_*` at the base, `after_*` now).

## What changed (one commit each)

1. **Pitchfork** (b8576dcf). The Tines joint (yoke and outer prongs) is a plain joint: no
   `Aim: fade`, so the prongs stay solid while aiming and shooting. Rebuilt in Blender: body
   rules and the fork check pass, the OBJs and the flame flipbook are byte-identical, so the
   shipped model 116270933265788 stays (joint keys are data: no re-upload, no template rebuild).
   TipFlameA/B: 7/s, lives 1.0-1.25 s (the 16-frame OneShot flipbook at ~14 fps, was 32),
   `LockedToPart`, fade in over 15% / out over 30%, at most 0.19 studs (was 0.32): ~8
   overlapping particles read as one small steady flame. Aura 19/s (was 21). Lowest rung.
2. **Jack-o'-Lantern** (d1329efa). Laugh `Volume` 0.25 (was 0.6, 58% quieter), `RollOffMinStuds`
   10, `RollOffMaxStuds` 25 (was 8/60; InverseTapered): full within 10 studs, silent from 25
   (at 15 studs ~0.11 where it was ~0.28). Finisher: the three circling mini jacks gone (the
   Orbit joint and part of `jack_o_lantern_rise`, `CuePiecesJack.py RISE_ORBIT = False`; 2 parts,
   3,354 tris, was 6,552), fire column 8 (was 18), flame wrap 6 (was 18), embers 20 / seeds 8
   (were 50 / 20), smoke 4 (was 8), all smaller: 46 particles once (was 114). The live template's
   `Orbit_Jack` part is simply never cloned (CuePiece clones only the parts the row names).
3. **Witch's Broom finisher** (e115fab9). The Beta-like rows are gone: the portal piece (two Neon
   rings turning round the pocket over a ForceField disc), the flat swirl disc layer, both ring
   decals, the shared gust's corkscrew ribbons (`KeepRibbons: false`). What the shared gust still
   adds for every cue: its streaks, sparkles, flash and the one shockwave ring on the cloth
   (runtime, not this lane's). New: `pieces/witch_broom_stars`, a witch's-hat constellation
   (Upright, facing the camera; eight twinkling, turning Neon stars, violet chart lines, eight
   dust stars; 11 parts, 652 tris, was 13 parts / 4,928), rising 1.5 studs and growing to 1.6x;
   a star fountain (new `vfx/witch_broom/star5.png`, 256 px), twinkling star dust round the hat,
   a star burst, bats, stars raining down (127 particles once, was 134). The witch: no moon,
   `vfx/witch_broom/witch_fly_8x8.png` (`tools/hw_sprites_b.py witch_fly`): 64 frames of 128 px
   over 1.05 s (was 16 over 2.2 s), a fuller silhouette with cloak, hair, hat tip, boot and
   bristles fluttering and a gold-to-violet sparkle trail; 5 studs, 3.4 up, across the hat's tip.
4. **Witch's Broom body** (2d9205d0). `BRISTLE_LEN 0.78` past the binding and `BRISTLE_SPLAY 0.92`:
   the head ends 1.15 studs past the butt (was 1.48); on a back (36 degrees, grip 4.3) the lowest
   straw sits ~0.28 studs higher. check_envelope OK; 9,096 tris (was 9,144); only
   `Bristles_Bark.obj` changed (HatCharm.glb and the atlases byte-identical, ids kept). Card
   re-rendered the recorded way (`cue_skin.py witch_broom --thumb --noaura`, no pop pass).
5. **Witch's Broom aura** (71559213), lane cuesA's call for the designer's ladder: the haze/glow
   cloud and the green wisps thinned, the teal glow and the emerald mid-handle light gone:
   115 particles a second (was 157), two lights (was three). The aura piece, potion smoke, bats,
   crystal flare, spell pops, beam and sparkle heads stay. One-file revert if unwanted.

Tests: `tests/halloween_cues_v3_test.luau` (7: Pitchfork no Aim joint and steady flames; Jack
laugh volume/roll-off and no Orbit; Broom finisher nothing ring-like, the witch on a Grid8x8
OneShot, the bristles 0.8-1.2 past the butt). Lint OK, all tests pass.

## Uploads (group 675425213, Open Cloud; Image ids = asset ids)

- `vfx/witch_broom/witch_fly_8x8.png` -> 124879285784866 (Image)
- `vfx/witch_broom/star5.png` -> 111229449430002 (Image)
- `pieces/witch_broom_stars/witch_broom_stars_parts.glb` -> 95267594206877 (Model)
- `pieces/witch_broom/witch_broom_parts.glb` -> 119274159538699 (Model; replaces 106017662921644, its row dropped)
- `thumbs/witch_broom.png` -> 131711880887023 (Image; replaces 82560329966868, its row dropped)

## Coordinator

- Template rebuild ONLY = `{ "WitchBroomCue" }` (pieces witch_broom, witch_broom_aura,
  witch_broom_stars). The Pitchfork and the Jack need none.
- `Config.Halloween.Art.WitchBroomCue` (core's row) -> `rbxassetid://131711880887023`.
- The old `witch_broom_pocket` template and the old moon flipbook stay unused (cleanup later).

## Check by hand (Studio, after the rebuild)

- Pitchfork in hand: aim and shoot; the outer prongs stay; the two tip flames small and steady
  (no blinking). The bridge hand sits between the outer prongs (0.31-0.445 off the axis);
  check it does not poke through the yoke at a short bridge.
- Jack: pocket a ball; the laugh is soft at the table and silent from ~25 studs; the head rises
  with little fire round it, no circling mini jacks.
- Broom: pocket a ball; the hat constellation rises facing the camera, the witch sweeps across
  its tip; no rings. Back carry on a normal R15: the straws clear the floor. Aura calmer.

## Open

- The ladder Broom < Jack: even trimmed, the Broom's aura (115/s plus its 3D aura piece) is
  busier than the Jack's (28/s, four mini jacks, the big pumpkin). Lifting the Jack's aura is
  the designer's call (not built).
- Not seen in Studio: LockedToPart flames on an attachment host, the constellation's Highlight
  outline, the witch flipbook's size at the real camera distance.
