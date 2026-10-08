# Ability sounds v2: candidate clips (2026-10-08)

Candidate sounds for the reworked abilities, all public Roblox Creator Store audio.

- **How they were found:** curl searches of the Creator Store audio API (`toolbox-service/v1/marketplace/Audio`), several keywords per slot, filtered to verified creators and to the licensed libraries Roblox ships (ProSoundEffects, APMOfficial; Roblox's own account has very few SFX).
- **How they were checked:** `toolbox-service/v1/items/details` (name, length, creator, verified badge, free, published, hash approved) and `economy.roblox.com/v2/assets/<id>/details` (every clip reports `IsPublicDomain: true`, i.e. free to use by id). The toolbox reports `visibilityStatus: 0` for all of them; no other public/distribution flag is exposed without login.
- **Nothing was uploaded.** Like the existing `SoundSheet.library` clips, these play straight from their id (`rbxassetid://<id>`).
- **Audition every one in Studio before wiring it in** (the API gives names and lengths, not how they sound). Then put the picks in `Config.Ults.Sounds` and the credits in `CREDITS.md`.
- ProSoundEffects and APMOfficial clips are licensed by Roblox for every experience: the safest choices. Clips marked *fan upload* are rips of game audio (Pokemon, Metal Gear) or memes; they work today but could be muted later.

First row per slot = recommended. Durations in seconds.

| Slot | Use | Id | Name | Sec | Creator |
|---|---|---|---|---|---|
| **catchOpen** | Ball opens: pop/whoosh plus a red-energy capture zap that sucks the target in | 9120984892 | Zap High Pitch Glassy Reversed Whoosh 9 (SFX) | 1.2 | ProSoundEffects (verified) |
| catchOpen |  | 9125807267 | Rising Whoosh Hissing Suck Burst Swooshing In 4 | 1.3 | ProSoundEffects (verified) |
| catchOpen |  | 94812253885911 | Pokeball Open (fan upload) | 1 | TheTrustyCapricorn (verified) |
| **catchShake** | Each of the three wobbles: a small click-clack (played three times) | 9125759320 | Plastic Switch Single Clicks Metallic Ringing 22 | 1.1 | ProSoundEffects (verified) |
| catchShake |  | 9120783657 | Wobble Board 8 (SFX) | 0.8 | ProSoundEffects (verified) |
| catchShake |  | 105930060641663 | Pokeball shake (fan upload) | <1 | TheTrustyCapricorn (verified) |
| **catchSuccess** | Final capture: click + ding success sting | 9126073318 | Synth Sparkle Tone High Pitch Bell Tone Ding 1 | 1.6 | ProSoundEffects (verified) |
| catchSuccess |  | 18448089848 | Success Ding | 2 | lamScripted (verified) |
| catchSuccess |  | 81046688241314 | pokeball catch (fan upload) | 1 | gamer712138 (verified) |
| **alert** | Metal Gear Solid style '!' alert | 7630658014 | Newer Metal Gear Solid Alert Sound (fan upload) | 1 | Fizzlestat (verified) |
| alert |  | 84062208287178 | Metal Gear Solid Alert Sound Effect | 2 | TurboSarp (verified) |
| alert |  | 9113652301 | Buzz Click Sci Fi Alert 2 (SFX) | 1.2 | ProSoundEffects (verified) |
| **vineBoom** | Vine boom meme hit | 140367458608473 | vine-boom-sound-effect_KT89XIq (meme upload) | 1 | Johnrey2ndacc (verified) |
| vineBoom |  | 132889984353619 | vine-boom (meme upload) | 1 | Robloxian201570164 (verified) |
| vineBoom |  | 9125404320 | Boom Impact Deep Distant Thumping Hits Booming 36 | 3.0 | ProSoundEffects (verified) |
| **cameraWhoosh** | Fast whoosh while the camera swings | 9126228631 | Whoosh Back Zoom Swoosh Fast Camera In And Out 2 | 1.9 | ProSoundEffects (verified) |
| cameraWhoosh |  | 9126229255 | Whoosh By Fast Airy Swooshing Whipping Thuds 2 | 1.2 | ProSoundEffects (verified) |
| **sneaky** | Sneaky tiptoe / short sneaky music sting | 1841485452 | Tiptoes and Eyebrows Sting c | 4 | APMOfficial (verified) |
| sneaky |  | 9045118430 | Sneaky Schemes - Tag2 | 5.0 | APMOfficial (verified) |
| sneaky |  | 9043512590 | Tiptoe Glow (sting b) | 3.0 | APMOfficial (verified) |
| **verityScreech** | Creepy smiley monster: screech or creepy laugh | 9114571613 | Ghost Giggle Breathy Cu Creepy Possessed 10 (SFX) | 2.5 | ProSoundEffects (verified) |
| verityScreech |  | 9125474863 | Creature Screech Pterodactyl Vocals Screams 10 | 2.4 | ProSoundEffects (verified) |
| verityScreech |  | 9118850613 | Screechy Screaming Suck Swelling Shrieks 1 (SFX) | 2.5 | ProSoundEffects (verified) |
| **footsteps** | Heavy footstep thumps | 9125404769 | Boomy Footsteps Giant Thumpy Dinosaur Footsteps 1 | 4.6 | ProSoundEffects (verified) |
| footsteps |  | 9114080709 | Dinosaur Footsteps Boomy Thumps 16 (SFX) | 2.8 | ProSoundEffects (verified) |
| footsteps |  | 9114523345 | Foot Stomp 3 (SFX) | 0.9 | ProSoundEffects (verified) |
| **throwWhoosh** | Big throw whoosh | 9120728815 | Whoosh Heavy Punches 1 (SFX) | 1.3 | ProSoundEffects (verified) |
| throwWhoosh |  | 9120745193 | Whoosh Vocal Flying Swooshy Heavy 2 (SFX) | 3.1 | ProSoundEffects (verified) |
| **tigerRoar** | Tiger roar | 9120048719 | Tiger Roars 10 (SFX) | 2.1 | ProSoundEffects (verified) |
| tigerRoar |  | 9120049061 | Tiger Roars 2 (SFX) | 2.5 | ProSoundEffects (verified) |
| **clawSlash** | Claw slash / scratch | 88967797911082 | CLAW SLASH | 1 | TheBaconHair_745 (verified) |
| clawSlash |  | 9119697796 | Swishes Thin Fast Singles Knife 10 (SFX) | 1.4 | ProSoundEffects (verified) |
| clawSlash |  | 137592229104819 | claw_strike1 | 1 | coolguyVicaso (verified) |
| **spinUp** | Rising spin-up whine (fidget spinner / turbine) | 9119816546 | Synth Power Up Multi Tone Wind Ups Rise 2 (SFX) | 2.7 | ProSoundEffects (verified) |
| spinUp |  | 9116989294 | Motor Wind Up 11 (SFX) | 2.1 | ProSoundEffects (verified) |
| spinUp |  | 9125390323 | Bell Huey Helicopter Wind Ups Whine Fast Rise 2 | 4.2 | ProSoundEffects (verified) |
| **steelClang** | Metallic clang/ting when the steel ball hits | 9125361455 | Anvil Hits Ringing Metal Clinks Blacksmith 12 | 0.7 | ProSoundEffects (verified) |
| steelClang |  | 9119072660 | Shield Clang As Hit Metal Sword Hubcap 1 (SFX) | 0.8 | ProSoundEffects (verified) |
| **spiralHum** | Magical power hum for the glowing golden spiral | 9116393976 | Magic Glow Short Pulsing Bursts 9 (SFX) | 1.8 | ProSoundEffects (verified) |
| spiralHum |  | 9113122880 | Angel Sparkle 5 (SFX) | 4.4 | ProSoundEffects (verified) |
| spiralHum |  | 9125784811 | Power Throb Tonal Hum Slow Pulse Electrical 3 | 4.3 | ProSoundEffects (verified) |
