# Making a cue skin with ChatGPT

A skin is five flat pictures, one per part of the cue. Look at `sheet.png` first: it shows where
each picture goes. In every picture, **left is the tip end and right is the butt end**, and the
top and bottom edges wrap round and meet underneath the cue. The middle row is the top of the cue
you see in your hands.

| Picture | Size | What it covers |
|---|---|---|
| `shaft_tile` | 1024 x 512 | The shaft, repeated about 3 times (tiles on all four edges) |
| `shaft_top` | 1536 x 512 | The end of the shaft; its right edge meets the joint |
| `forearm` | 1536 x 512 | The joint collar (the two thin zones on the left), then the forearm |
| `butt` | 1376 x 512 | The ring, the wrap, the sleeve and the rounded end |
| `cap_end` | 512 x 512 | The flat end of the butt: paint inside the circle |

## 1. Pick your palette first

Choose 4 to 6 colours and write down their hex codes, for example
`#0B0B12 #1E6BFF #FFD23F #00F0FF #F4F4F4`. Use the same list in every prompt. The skin file
turns one of them into **metal** (shiny, like the silver rings) and one into **glow**, so pick
a colour for each that nothing else uses.

## 2. For each picture

Start a new chat. Attach **image 1**: `template/<picture>_input.png` (the grey one). Attach
**image 2**: your concept cue, cropped to the part you are making. Paste this, changing only the
parts in brackets:

> Image 1 is a layout template. Paint it as a flat unrolled texture for a cylinder: the
> [forearm] of a pool cue, in the style of the cue in image 2. Keep the exact layout and zone
> lines of image 1 and the exact size, [1536 x 512] pixels. The left edge is the tip end and the
> right edge is the butt end. The top and bottom edges join seamlessly. No lighting, no shading,
> no highlights, no reflections, no shadows: flat colour only. Use only these colours:
> [#0B0B12 #1E6BFF #FFD23F #00F0FF #F4F4F4]. No text, no letters, no logos with words.

For `shaft_tile`, add: *It tiles seamlessly on all four edges.*
For `cap_end`, say *a round badge* instead of *a flat unrolled texture*, and *paint only inside
the circle*.

## 3. When it drifts

ChatGPT often adds shading, text or new colours, or moves the zone lines. Fix one thing per
edit ("remove all shading, keep everything else the same"), then paste the rules again. If the
size is wrong, ask for exactly the size in the table. Two or three edits is normal.

## 4. Save and build

Save the pictures as `assets/cue/skins/<id>/<picture>.png`, for example
`assets/cue/skins/neon/forearm.png`. Copy `assets/cue/skins/_test.json` to
`assets/cue/skins/<id>.json`, and change the `id`, the five panel paths, the tip, ferrule and
bumper colours, and the `metal` and `glow` keys to your palette colours. Then run:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1 \
    --python assets/cue/CueTextures.py -- --skin assets/cue/skins/<id>.json
```

Look at `assets/cue/renders/<id>.png`. The maps are in `assets/cue/textures/`. The rest (upload,
Studio, the game) is in `assets/cue/Readme.md`, "Make a new skin".
