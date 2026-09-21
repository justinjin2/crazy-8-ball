# Sound effects

The game's sounds are our own recordings, uploaded to the group that owns the place, so they
are referenced by id from `Config.Audio` and there is nothing to insert into Studio by hand.

| Event | Clips | Notes |
|---|---|---|
| `BallClack` | 6 | `ball_clack_soft`, `ball_clack_1/2`, `clack_3`, `ball_clack_rattle_1/2` |
| `RailThud` | 1 | `ball_hitting_edge_table_hard` — the thin spot, see below |
| `CueStrike` | 2 | `cue_strike_1/2` |
| `PocketDrop` | 2 | `pocket_drop_1/2` |
| `Roll` tier 1 | 1 | `ball_rolling_1`, for slow rolling |
| `Roll` tier 2 | 2 | `ball_rolling_2/3`, for fast rolling |
| `AimTick` | 1 | still a Roblox library click; a UI sound, not a pool sound |

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

## What would help most if you record more

1. **More cushion takes.** There is only one rail recording and rails are the second most
   frequent contact in the game — 37 of them in a nine-shot test. It leans entirely on pitch
   and volume variation to disguise the repeat. Three or four takes would buy more here than
   anywhere else.
2. **A second slow-roll take.** The first roll tier has one clip, and the table spends about
   two thirds of a shot in it, so it crossfades into itself. Each pass starts at a random
   offset to disguise that, but a second recording would fix it properly.
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
