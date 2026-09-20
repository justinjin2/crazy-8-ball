# Sound effects

Drop your own recordings in `raw/`. Any sample rate, any length, one file or one long take
with many hits in it — `tools/splice_audio.py` cuts them into clean one-shots and writes
them beside this file, ready to upload.

**WAV works today.** MP3, M4A and the rest need `ffmpeg` (`brew install ffmpeg`); the
splicer says so rather than failing quietly.

## Why several clips per sound

Each event plays one clip picked from a list, never the same one twice running. That matters
more than pitch variation: the ear spots exact repetition instantly, and a break makes over a
hundred ball contacts, so a single clack sample becomes a machine gun however cleverly it is
pitched. Three or four takes per event is plenty.

Pitch and volume then follow the impact speed on top of that. Keep pitch shifts small — past
about 15% a sample stops sounding like the same object being struck.

## What to record

| Name | What it is | Notes |
|---|---|---|
| `clack_*.wav` | ball striking ball | 3-4 takes, soft through hard if you can |
| `rail_*.wav` | ball into a cushion | duller and softer than a clack |
| `strike_*.wav` | the cue tip hitting the cue ball | short, woody |
| `pocket_*.wav` | a ball dropping and rattling in | can be a second or so |
| `roll_loop.wav` | steady roll on cloth | **must loop cleanly**, a few seconds |
| `tick.wav` | a soft click for aiming | very short, 20ms or so |

`roll_loop` is the one the Roblox library has nothing for, and the one that does the most for
how the table feels: it is a continuous sound whose volume tracks ball speed, not a one-shot.

## Uploading

Roblox audio has to be uploaded from your own account, so this part cannot be automated:
**View → Asset Manager → Audio → right-click → Add Audio** (multi-select works). Once they are
up, say what you named them and they can be found in your inventory by name; ids do not need
copying by hand.
