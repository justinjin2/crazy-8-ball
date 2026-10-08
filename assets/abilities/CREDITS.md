# Abilities: credits and sources (2026-09-29; the rework 2026-10-08)

Everything the 13 abilities ship with, and where it came from. Ids live in
`Config.Ults.Assets` (models, icons, images) and `Config.Ults.Sounds` (audio).

## Made for this game

- **The scripted models** (the VFX meshes and the catch ball) were modelled by script in
  Blender 5.2 (`tools/blender/abilities/*.py`) for this game. The sources are the `.blend` and
  `.glb` files in each folder here.
- **The two creatures of the rework are generated** (the project's own Meshy account, 2026-10-08):
  Guangdong Tiger's tiger (Meshy image-to-3D from a reference made with `tools/openai_image.py`,
  then rigged and animated in Blender: `GuangdongTiger/Readme.md`) and the Verity monster (Meshy
  image-to-3D from the designer's reference, Meshy's auto-rig and library animation clips:
  `Verity/Readme.md`). No download or library model was used.
- **Every image** (the 13 icons, textures, flipbooks, screen overlays, the Verity ball, the
  golden spiral and the catch effects) was rendered or painted by those scripts. No
  third-party art.
- **Voices:** Verity's line ("Hi, I'm Verity! Trust me, I know everything!") and the "Look over
  there!" shout are text-to-speech stand-ins (OpenAI `gpt-4o-mini-tts`), uploaded to the group,
  until the designer records their own (`Config.Ults.Sounds.VerityLine`, `LookShout`).
- **The reference images** in `reference/` are the designer's mood references (shows and
  games). They were only looked at while building; nothing from them is uploaded or shipped.
- **The designer's own sounds:** ult_activate and ult_ready (uploaded to the group).

## Sounds (Roblox public audio library)

Every ability sound is a public Roblox library clip, checked loading in this game, played
with its id (nothing re-uploaded). Names as the library lists them, with the uploader.
The time stop and the "nyo-ho" are soundalikes. **Exception (the rework, the designer's
choice):** Catch-a-Ball's open, wobble and catch, Look Over There!'s alert and its vine boom
are public fan uploads of the game and meme sounds themselves. Roblox may mute such uploads;
the licensed backups are named beside each in `Config.Ults.Sounds`.

| Ability | Use | Clip (uploader) |
|---|---|---|
| Magnet | hum | Force Field Sci Fi Constant Deep Pulsing Hum (Pro Sound Effects) |
| Magnet | pull | Electric Zapping loop (FastFoxVita) |
| Magnet | drop | Metal Impact Heavy Clunking Hits 4, Electric Zaps 12 (Pro Sound Effects) |
| Magnet, Chain Lightning | arming | Electric Zaps 6 (Pro Sound Effects) |
| Eagle's Eye | arming | Eagle Screech 1 |
| Super Bounce | arming | Cartoon Spring Bounce Sound (MysteryMilo) |
| Super Bounce | bounce | SS_rubberduck_variety_spring_02 (Roblox) |
| Rewind | arming | Eject Cassette SFX (zImBored, from Pixabay) |
| Rewind | rewind | Tape Rewind (AppleBraid) |
| Rewind | landing | Cassette Play SFX (WaddelsG) |
| Rewind | spent | cassette click (zKevin) |
| Time Stop | swell | 504_Reverse_Cymbal (kyleamida) |
| Time Stop | freeze | Boom Impact Deep Distant Thumping Hits 1 (Pro Sound Effects) |
| Time Stop | tick | Clock Ticking [2 Ticks] (heiroftheeternalname) |
| Time Stop, Black Hole | resume, pull | Reversed Whoosh Backwards Hissing Burst 2 (Pro Sound Effects) |
| Time Stop | tick-tock | Clock Tick Tock - ULTRAKILL (ImJustDou) |
| Chain Lightning | charge | thunder crack (DundeiEh) |
| Chain Lightning | jump | Quick Electric Zap (ConeExpierence) |
| Chain Lightning | hum | energy buzz (mastermilosz) |
| Portals | hum | Metallic Glow Constant Deep Ticking Bassy Hum (Pro Sound Effects) |
| Portals | enter, close | swish teleport tp flashstep sfx (Axellatic) |
| Portals, Black Hole | exit, pop | Pop Sound Effect (Siegegeddon) |
| Portals | open | teleport (Joshua00924) |
| Steel Ball | whirr, clank, pot | library clips (a spinning top, a metal hit, a twinkle); the call is the designer's own clip |
| Steel Ball | spin-up | Synth Power Up Multi Tone Wind Ups Rise 2 (Pro Sound Effects) |
| Steel Ball | spiral | Magic Glow Short Pulsing Bursts 9 (Pro Sound Effects) |
| Black Flash | impact, shatter, crackle | library clips (a deep boom, a glass shatter, an electric crackle) |
| Black Hole | drone | Hollow Rumble 1 (Pro Sound Effects) |
| Black Hole | opening | Tutti Suck (APM) |
| Guangdong Tiger | roar | Tiger Roars 10 (Pro Sound Effects) |
| Guangdong Tiger | snarl | Tiger Roars 9 (Pro Sound Effects) |
| Guangdong Tiger | rake | CLAW SLASH (TheBaconHair_745) |
| Guangdong Tiger | slash | Red Mist Vertical Split |
| Guangdong Tiger | landing | Body Impact 2 (Pro Sound Effects) |
| Catch-a-Ball | open | Pokeball Open (TheTrustyCapricorn, a fan upload) |
| Catch-a-Ball | suck-in | Rising Whoosh Hissing Suck Burst Swooshing In 4 (Pro Sound Effects) |
| Catch-a-Ball | wobble | Pokeball shake (TheTrustyCapricorn, a fan upload) |
| Catch-a-Ball | caught | pokeball catch (gamer712138, a fan upload) |
| Catch-a-Ball | ding | Synth Sparkle Tone High Pitch Bell Tone Ding 1 (Pro Sound Effects) |
| Catch-a-Ball | the 8 breaks free | Reversed Whoosh Backwards Hissing Burst 2 (Pro Sound Effects) |
| Verity | giggle | Ghost Giggle Breathy Cu Creepy Possessed 10 (Pro Sound Effects) |
| Verity | footsteps | Dinosaur Footsteps Boomy Thumps 16 (Pro Sound Effects) |
| Verity | throw | Whoosh Heavy Punches 1 (Pro Sound Effects) |
| Verity | kick | Foot Stomp 3 (Pro Sound Effects) |
| Look Over There! | alert | Newer Metal Gear Solid Alert Sound (Fizzlestat, a fan upload) |
| Look Over There! | camera whoosh | Whoosh Back Zoom Swoosh Fast Camera In And Out 2 (Pro Sound Effects) |
| Look Over There! | sneaky sting | Tiptoes and Eyebrows Sting c (APM) |
| Look Over There! | reveal | vine-boom-sound-effect (Johnrey2ndacc, a meme upload) |

Library clips can be taken down by Roblox; if one stops loading, search the library for a
replacement and change its id in `Config.Ults.Sounds`.

**To replace:** the two text-to-speech voices (Verity's line, the "Look over there!" shout),
once the designer records their own (then change `Config.Ults.Sounds.VerityLine` and
`LookShout`).
