# Sound effects

The game's sounds are our own recordings, uploaded to the group that owns the place, so they
are referenced by id from `Config.Audio` and there is nothing to insert into Studio by hand.

| Event | Clips | Notes |
|---|---|---|
| `BallClack` | 6 | `ball_clack_soft` is banded to gentle contacts; the other five from 6 in/s |
| `RailThud` | 1 | one soft take covers every cushion hit — see below |
| `CueStrike` | 2 | `cue_strike_1/2` |
| `PocketDrop` | 2 | `pocket_drop_1/2` |
| `Roll` tier 1 | 1 | `ball_rolling_1`, for slow rolling |
| `Roll` tier 2 | 2 | `ball_rolling_2/3`, for fast rolling |
| `AimTick` | 1 | still a Roblox library click; a UI sound, not a pool sound |
| `ClockTick` | 1 | APM's "TICK TOCK 06 120BPM" from Roblox's licensed library; only its first tick plays (`Config.Audio.ClockTick.Region`) |

## How the mix works

**Variation** comes from several clips per event, never the same one twice running. This
matters more than any amount of pitch shifting: the ear spots exact repetition instantly, and
one break makes over a hundred ball contacts, so a single clack sample is a machine gun
however cleverly it is pitched.

**Dynamics** come from impact speed driving volume and pitch, on a logarithmic curve. Linear
was tried and measured wrong: the median ball-on-ball contact in this game is 3.6 in/s and
the 90th percentile is 66.8, while a break tops 500, so dividing by a "full volume speed" put
half of all audible contacts in the bottom fifth of the range.

**Gain** is a measured correction per clip, not a taste setting, and it is why the two above
do not fight each other. The recordings are nowhere near equally loud — the rail clip peaks
at 0.18 and the pocket drops at 0.91, 14 dB apart — so without it the random choice, not the
impact speed, would decide how loud a hit sounds. Re-measure with `tools/measure_audio.luau`
whenever a clip is replaced and put the new number in `Config.Audio`.

**The roll is not a one-shot.** It is one continuous sound for the whole table whose volume
and pitch follow the fastest ball still moving, emitted from that ball. It is built from two
alternating clips that crossfade, because a seam in a loop clicks every couple of seconds and
during the long quiet stretch of a shot that click would be the only thing you hear.

**One cushion take covers the whole range.** The older, harder recording was dropped because
it did not sound like a ball meeting a cushion; a clean sample carried across the range by
volume and pitch beats an unconvincing one used at its "correct" speed. The cost is
variation, so the rail band carries extra pitch wobble of its own — measured over six shots,
34 cushion hits came out across 13.6 dB of volume and 16 distinct pitches.

**Gentle contacts are audible.** Two thirds of all ball-on-ball contacts in this game happen
below 12 in/s (the median is 3.6), so the sound floor sits at 1 in/s and the clack curve has
its own quiet end an order of magnitude below the shared one. Contacts under about 0.05 in/s
stay silent - those are two balls already touching being re-detected, not a new contact.

**A hard break stacks.** Contacts at or above 110 in/s skip the minimum gap between clacks
and sound together, up to ten inside a tenth of a second, which is what makes a launch land
as a single crack. Measured: nine clacks at once on a full-power break, about 10 dB on the
old peak. It cannot trigger below 52% power, because a contact is never faster than the ball
that struck it — so it stays out of ordinary play.

**Rails sit right at the back** — 22 to 30 dB below a clack at the same speed. They used to be
2.4 dB below, which was far too close for the most frequent contact in the game.
`Config.Audio.Rail.MaxVolume` is the single number to change if they become inaudible rather
than subtle.

## What would help most if you record more

1. **A second slow-roll take.** The first roll tier has one clip, and the table spends about
   two thirds of a shot in it, so it crossfades into itself. Each pass starts at a random
   offset to disguise that, but a second recording would fix it properly.
2. **A second cushion take.** There is one, and rails are the most frequent contact in the
   game after ball hits, so it repeats more than anything else. Pitch and volume disguise it,
   but another take of the same character would fix it properly.
3. **An aim tick** of your own, to retire the last library sound.

`ball_rolling_1` measured 15x quieter than 2 and 3, which is why its gain is large. Its noise
floor sits 10.4 dB below its own average, so the material survives the boost — but if it ever
hisses in game, that is the clip to re-record.

## Recording and preparing new clips

Drop raw takes in `raw/` and run `tools/splice_audio.py`. Record however is convenient: one
long take with twenty hits in it is better than twenty careful files. The splicer finds each
hit by its attack, keeps 8 ms of lead-in so the transient is not clipped off, cuts when the
sound has died away, normalises, and fades the tail so nothing clicks.

```bash
tools/splice_audio.py --list    # say what it found, write nothing
tools/splice_audio.py           # write the one-shots
```

**Name a raw file after the event it belongs to**, using the same names as the uploads:
`ball_clack`, `ball_clack_rattle`, `ball_hitting_edge`, `cue_strike`, `pocket_drop`,
`ball_rolling`, `tick`. Anything after the prefix is free (`ball_clack_hard_take2.wav`), and
the output is numbered from whatever is already there, so running it twice adds rather than
overwrites.

A `ball_rolling` file is treated as continuous material rather than a series of hits: it is
trimmed to its steadiest stretch instead of being cut up. WAV works with nothing installed;
other formats need `ffmpeg` (`brew install ffmpeg`).

## Uploading

Roblox audio has to be uploaded from an account or group, so this part cannot be automated.
Upload to the **group that owns the game**, not a personal account, or the place cannot use
the asset: Creator Dashboard, or **View → Asset Manager → Audio → right-click → Add Audio**
(multi-select works). Then paste the ids here and they go into `Config.Audio`.

## Interface sounds (placeholders, 2026-09-27)

Picked overnight from the Creator Store for the rank and money screens
(`Config.Audio.Ui`, played by `src/client/UISound.luau`). All from Roblox's own library or
the APM Music library Roblox licenses, all checked to load in this game (IsLoaded, TimeLength).
Nobody has listened to them yet: swap any by changing its id in `Config.Audio.Ui`.

| Key | When | Asset | Length |
|---|---|---|---|
| CashLand | a "+$10" chip lands in the money HUD | 127645268874265 "CoinTransfer_01" (Roblox) | 1.7 s |
| MoneyTick | the money total counting up (pitched 1.4) | 15675032796 "Roblox_UI_Small_Click" | 0.13 s |
| XpTick | the XP bar filling (pitch rising 0.9 to 1.5) | 15675059323 "Roblox_UI_Bright_Click" | 0.37 s |
| XpFull | the XP bar reaching a division's top | 15675043410 "Roblox_UI_Tonal_Stinger" | 1.5 s |
| RankUp | NEW RANK! | 1844692556 "Game Show" (APM Music) | 2.2 s |
| NewTier | a new tier (bigger fanfare) | 1844584807 "Glamour Fanfare 4" (APM Music) | 3.7 s |
| RankDown | a division lost (pitched 0.8) | 15675081158 "Roblox_UI_Cute_Goodbye" | 0.3 s |
| BadgeHover | the rank badge under the mouse | 15675055424 "Roblox_UI_Cute_Pop" | 2.7 s (tail) |
| Click | a button pressed | 15675032796 "Roblox_UI_Small_Click" | 0.13 s |
| ReelTick | the case reel: one card passing the marker (pitched 1.7) | 15675032796 "Roblox_UI_Small_Click" | 0.13 s |
| ReelSettle | the reel settling on the prize | 15675046931 "Roblox_UI_Sweep" | 0.61 s |
| ReelBuild | the longer build-up before a Mythic or Secret | 15674975792 "Roblox_UI_Whoosh_03" | 1.1 s |
| RevealLow | a Common or Uncommon revealed | 15675055424 "Roblox_UI_Cute_Pop" | 2.7 s |
| RevealRare | a Rare revealed | 1846251729 "Fortune Fun Logo" (APM) | 3.1 s |
| RevealEpic | an Epic revealed | 1848281810 "Everything Works Out - Tag2" (APM) | 3.7 s |
| RevealLegendary | a Legendary revealed | 9045294353 "Shooting Stars" (APM) | 4.9 s |
| RevealMythic | a Mythic or Secret revealed | 1839881844 "Spinning Around (b)" (APM) | 5.4 s |
| Claim | a reward claimed (daily, playtime, index row, code) | 15675043410 "Roblox_UI_Tonal_Stinger" | 1.5 s |
| Banner | a top banner (Money Party, an unboxing, Reyes) | 15675085146 "Roblox_UI_Indicator" | 3.4 s |

The reel and reveal sounds were added on 2026-09-28 (overnight placeholders, each checked loading
in this game with `IsLoaded` and `TimeLength`); nobody has listened to them yet.
