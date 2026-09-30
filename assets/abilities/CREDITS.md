# Abilities: credits and sources (2026-09-29)

Everything the 13 abilities ship with, and where it came from. Ids live in
`Config.Ults.Assets` (models, icons, images) and `Config.Ults.Sounds` (audio).

## Made for this game

- **Every model** (the VFX meshes and the tiger) was modelled by script in Blender 5.2
  (`tools/blender/abilities/*.py`) for this game; no generator, download or library model was
  used (the generators and Sketchfab were off in the Blender addon). The sources are the
  `.blend` and `.glb` files in each folder here.
- **Every image** (the 13 icons, textures, flipbooks, screen overlays) was rendered or painted
  by those scripts. No third-party art.
- **The reference images** in `reference/` are the designer's mood references (shows and
  games). They were only looked at while building; nothing from them is uploaded or shipped.
- **The designer's own sounds:** ult_activate and ult_ready (uploaded to the group).

## Sounds (Roblox public audio library)

Every ability sound is a public Roblox library clip, checked loading in this game, played
with its id (nothing re-uploaded). Names as the library lists them, with the uploader.
No clip of a show's audio is used: the time stop and the "nyo-ho" are soundalikes.

| Ability | Use | Clip (uploader) |
|---|---|---|
| Magnet | hum | Force Field Sci Fi Constant Deep Pulsing Hum (Pro Sound Effects) |
| Magnet | pull | Electric Zapping loop (FastFoxVita) |
| Magnet | drop | Metal Impact Heavy Clunking Hits 4, Electric Zaps 12 (Pro Sound Effects) |
| Magnet, Chain Lightning | arming | Electric Zaps 6 (Pro Sound Effects) |
| Eagle's Eye | arming | Eagle Screech 1 |
| Super Bounce | arming | Cartoon Spring Bounce Sound (MysteryMilo) |
| Super Bounce | bounce | SS_rubberduck_variety_spring_02 (Roblox) |
| Ghost | wail | Dream Weirdness Constant 6 (Pro Sound Effects) |
| Ghost | pass | Fast Pass By Airy Whooshes Windy 2 (Pro Sound Effects) |
| Heat Seeker | beeps | shortbeep (maybealian) |
| Heat Seeker | lock | 1000 hz sine tone (BuilderBillbert) |
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
| Steel Ball | call, whirr, clank, pot | library clips (a two-note whistle as the "nyo-ho" stand-in, a spinning top, a metal hit, a twinkle) |
| Black Flash | impact, shatter, crackle | library clips (a deep boom, a glass shatter, an electric crackle) |
| Black Hole | drone | Hollow Rumble 1 (Pro Sound Effects) |
| Black Hole | opening | Tutti Suck (APM) |
| Guangdong Tiger | roar | Tiger Roars 9 (Pro Sound Effects) |
| Guangdong Tiger | slash | Red Mist Vertical Split |
| Guangdong Tiger | landing | Body Impact 2 (Pro Sound Effects) |

Library clips can be taken down by Roblox; if one stops loading, search the library for a
replacement and change its id in `Config.Ults.Sounds`.

**To replace:** Steel Ball's whistle is a stand-in; the designer means to record their own
"nyo-ho" and upload it (then change `Config.Ults.Sounds.SteelCall`).
