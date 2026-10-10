# Pull cutscenes v2: Mythic "Starfall" and Secret "The Dream"

Brief for the redo of the two rarest pull cutscenes (designer, 2026-10-10 night: "similar to
the Legendary but tenfold ... cutscene movie worthy"). The designer picked the Secret's
backrooms dream, the Great Vibes font and the wording, and left the directing to Claude, with
full permission to upload and commit overnight. Built on `gui-v4` in `~/Desktop/8ball`.

## Rules that shape every shot

- Both play from the black the reel fades into (`Config.Cutscenes.Black`), own the veil, and end
  on a white flash with the card under it, like the Legendary. Skippable once seen.
- Everything is our own instances or saved-and-restored values (camera, Lighting, Atmosphere,
  Bloom, DepthOfField, Sky, sounds, the player's Humanoid). A skip, a second pull or a match
  starting puts it all back.
- No 2D cue card anywhere in a scene (the old Mythic's falling card "looked stupid"): the cue is
  the real 3D stick with its full aura (`CueStickBuilder` + `CueSkinLook`), warmed with
  `CueAssets` from the reel's start. If it is not ready in time, its moment is pure light.
- Every number in `Config.Cutscenes.Mythic` / `.Secret`, every word in `Strings.Cutscenes`,
  every sound in `Config.Audio.Ui`. Particles scale with `Quality.rate()`.
- Phone, PC and gamepad: nothing to press but the skip (tap, A, B, Escape).

## Mythic: "Starfall" (about 10.7 s from the black)

Sounds: the designer's "Transition Logo Reveal" (`MythicLogo`, 1021265, 8.6 s: a hit at 0.35 s,
a deep drone, a shimmer rising 3.2-3.9 s, the air sucked out 3.9-4.2 s, reveal hits 4.25-5.1 s,
its last sub hit at 5.12 s, a reverb tail to 8 s) from the black; the "Robo Rise"
(`MythicRise`, 274661, 4.04 s: peak and hard stop at 3.55 s) timed so its stop is the flash; the
Legendary's "Cinematic Hit" on the flash; the "Aurora" ambience under the card.

| t (s) | Shot | What happens |
| --- | --- | --- |
| 0-0.35 | black | the bars are already in; the track's pre-hit swell; every game sound fades out |
| 0.35 | 1. Nightfall: low wide, in front, the player in the lower third, a slow push | hard cut in on the hit; the day sky falls to night in 1.6 s (the clock runs to midnight, the light goes indigo, bloom up); the world round the player (420 studs) dissolves away from 0.5 to 1.9 s, farthest first, for them alone: only they, the bare ground and the sky are left; a pastel Milky Way, nebulae and big twinkling stars fade in; the first shooting stars cross (from 1.4) |
| 2.0 | 2. Wonder: over the shoulder from behind and below, wide, looking up | shooting stars streak across the sky one after another (pastel trails, white heads, a whoosh on every second one) |
| 3.2 | 2 continued: tilting toward the point | the shimmer rise: every star bends toward one point 60 studs above the player and spirals in |
| 3.9 | 2 continued | the air sucked out: the trails wind into a tiny point (the gather sound peaks on the breath, 4.2) |
| 4.25 | 3. The newborn star: low behind the player's left shoulder, up past them | the reveal hit: the stars fuse into one rainbow star (flare, rays, a ring bursting through the sky); it pulses on the next hits (4.47, 4.59) |
| 4.66 | 4. The fall: wide and low from the side | it falls as a rainbow comet |
| 5.12 | 4 | impact on the last sub hit: glare, a nova of light, a shockwave over the ground, a pillar, sparks and shards, a boom, a heavy shake |
| 5.3 | 5. Bullet time: slow orbit round the frozen burst | everything slows to 5%: the shell, rings and shards hang in the air while the camera circles and pushes in; a reverse swell |
| 6.6 | 6. Forging: front left, then a rising orbit round cue and player | time runs again; the light falls into a point beside the player and the real cue forms there, white-hot, then its own look and aura; a celestial sigil lights on the ground; the Robo Rise starts (6.95); the cue turns, starlight orbits it ever faster, the colours cycle faster |
| 10.1 | | the cue flares; the camera rushes into it |
| 10.55 | flash | white on the rise's stop, the Cinematic Hit; the card under the white; the Aurora ambience |

## Secret: "The Dream" (about 17 s from the black)

Sounds: "DREAMCORE (Fever Dream)" (`SecretDream`, 86247184974274, public, no upload; a 1 s
fade-in of its own, then a steady droning bed) from the black; the heartbeat (`Heartbeat`); a
fluorescent hum, light flicker clicks, a power-down clunk per dying light, VHS glitch bursts
(Roblox library); the "Tonal Rise" (`SecretRise`, 274686, 5.39 s, loudest at its end) into the
cut; silence; the "Cinematic Hit" on the flash; the dream music on, quiet, under the card,
tapering after it closes (replaces the angelic Aurora for the Secret).

| t (s) | Shot | What happens |
| --- | --- | --- |
| 0 | black | every game sound fades out; silence; heartbeats (0.3, 1.25, 2.15), a faint red pulse at the edges |
| 0.8 | black | DREAMCORE fades in |
| 2.2 | 1. The hallway: eye height, a slow handheld drift forward | a CRT line opens into the picture with a static burst: an endless yellow backrooms hall (wallpaper, damp carpet, ceiling tiles, buzzing fluorescent panels, openings into dark side halls), VHS grade (scanlines, grain, a rolling tracking band, vignette, haze, "PLAY ▶" and "AM 3:33") |
| 3.5 | 1 | "You've dreamed of it..." in Great Vibes, written on left to right, glitching (red/cyan split, sliced) |
| 6.25 | 1 | the line glitches away |
| 6.55 | 2. The dark: a jump in the tape, further down the hall | |
| 7.3 | 2 | from the far end the panels go out one by one toward the camera, faster as they near, a clunk each; dark; one flickering panel above; heartbeats again (8.75) |
| 8.6 | 2 | "...and now it's finally yours." low in the dark, a red glow in the letters |
| 9.4 | 2 | a red glow far down the hall: the cue floats there, turning, lit red, embers rising |
| 11.0 | 3. The pull: a snap zoom on the cue, then a long push down the hall with a dolly zoom | the Tonal Rise (from 11.0); the glitch storm grows (tracking errors, slices, red strobes on the beats), the heartbeat races, the music warbles like a worn tape, the cue fills the frame |
| 16.4 | black | hard cut to black, every sound stops |
| 16.85 | flash | red to white, the Cinematic Hit, the card under the white; the dream music quietly under it |

## Assets

Generated art (numpy + Pillow, fixed seeds; `tools/gen_cutscene_art.py` and
`tools/gen_backrooms_art.py`, `assets/cutscenes/`, ids in its README), uploaded as Decals to
group 675425213 and turned into image ids:

- Mythic: `milky_way.png` (1024 x 256, colour baked: a pastel galactic band of pink, lilac and
  cyan clouds with dense star dust, soft edges), `nebula_puff_a.png` / `_b.png` (512 square,
  colour baked soft pastel clouds), `celestial_sigil.png` (1024 square, white: rings,
  constellation lines and star dots, tick marks; tinted in Roblox), `light_shard.png` (128 x
  512, white: a thin glowing crystal shard).
- Secret: `backrooms_wallpaper.png` (512 square, tileable mono-yellow with a faint vertical
  pattern and stains), `backrooms_carpet.png` (512 square, tileable damp beige-yellow carpet),
  `backrooms_ceiling.png` (512 square, tileable 2 x 2 off-white ceiling tiles with grooves and
  specks), `vhs_scanlines.png` (tileable horizontal lines, white on alpha), `vhs_noise.png` (256
  square tileable grain), `vhs_tracking.png` (1024 x 64 band of torn noise), `vignette.png`
  (512 square, white at the edges, clear in the middle; tinted black or red).

Reused: `Config.UI.Kit.Art` (SoftGlow, RingGlow, Spark, Rays), `Config.Cutscenes.Art`
(BeamEnergy, BeamSoft, LightStreak, StarFlare), the Legendary's Cinematic Hit and Aurora.

## Code

- `src/client/PullKit.luau`: the pieces every scene shares (screen frames, glows, ghost parts,
  emitters, unlit ground art, the camera's clamp, the floating 3D cue, sounds, and the world
  falling away: `clearWorld` / `fadeWorld`, LocalTransparencyModifier for this player alone,
  signs, lights and effects put out, everything back at the end).
- `src/shared/PullMath.luau` (pure, tested in `tests/pull_math_test.luau`): the warped clock
  of bullet time, the lights' death order, beats, glitch slots, the dolly zoom's field of view.
- `src/client/PullMythic.luau`, `src/client/PullSecret.luau` (with `Backrooms.luau` building the
  hall), each `build`, `step(s, t)`, `flashAt()`, `reveal(s)`.
- `PullCutscene.luau` keeps the shared flow (black, veil, skip, restore, card) and Rare to
  Legendary; `prepare(rarity, cueId)` warms a big pull's cue, sounds and art from the reel.
- A Studio-only `GuiQA` action plays a scene and can hold it at a time for screenshots.

## Progress

- [x] Brief
- [x] Art and sounds (generated, uploaded, ids in Config)
- [x] Mythic built
- [x] Secret built
- [x] Lint, tests, Studio check (PC shot by shot at the phone's wide frame; Studio cannot
  switch the phone emulator in Play), console clean
- [x] Docs (GDD, STATUS, DECISIONS), commit, push
- [ ] The designer's look and ears; a real phone and controller
