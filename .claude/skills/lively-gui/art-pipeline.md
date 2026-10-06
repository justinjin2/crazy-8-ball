# Art pipeline: target pictures, pieces, effects, uploads

## Contents

1. Setup
2. Target mocks
3. Choosing each piece's source
4. Cutting pieces from a target
5. Generating and filling with the image tool
6. Rendering from the real game (Blender)
7. Drawing by code, unmult, flipbook sheets
8. Baking pieces together, glows and masks
9. Uploads, image ids, Config
10. Spend
11. Where files go

## 1. Setup

- Python for `tools/gui/` lives in `tools/gui/.venv` (git-ignored): `uv venv tools/gui/.venv`,
  then `VIRTUAL_ENV=tools/gui/.venv uv pip install pillow numpy` (cutting also needs `torch
  torchvision transformers timm kornia einops opencv-python-headless scipy pymatting`). Run with
  `tools/gui/.venv/bin/python`. Small scripts that need only Pillow and numpy also run with
  `python3`.
- `tools/gui/README.md` lists every script. `ffmpeg` comes from Homebrew.
- Real-ESRGAN for upscaling cut pieces: `tools/gui/bin/realesrgan-ncnn-vulkan -i in.png -o
  out.png -n realesrgan-x4plus-anime -m tools/gui/bin/models` (4x, about 3 s; git-ignored).

## 2. Target mocks

A big screen starts from one target picture. The designer gives one when they have it;
otherwise make **two or three mocks** for them to pick from or mix (designer, 2026-10-06):

- `tools/openai_image.py` (GPT Image 2.5 Sunburst) with a reference pack attached every call:
  the Shop target `13b` (in `~/Desktop/8ball-refs/`), a screenshot of the current screen in
  Studio, and the kit's look (white inked panels, pale-blue header with 8-balls, navy hero
  card, gold and green candy buttons, Fredoka One words with the ink outline).
- Prompt for the layout and mood, not for words: real text replaces every word later.
- Say the size: the panel is at most 66% of the screen's width and as tall as its first card;
  the target should show the first screen exactly.
- Show the mocks side by side on a private gate page and wait.

## 3. Choosing each piece's source

For every piece pick whichever is sharpest and closest to the target, and record it in the
piece list (`tools/gui/<screen>/pieces.json`):

| Source | When | Shop examples |
|---|---|---|
| Cut from the target | the target's pixels are sharp enough at in-game size | stars, 8-balls |
| Regenerated | the target's piece is soft, hidden or crossed by something | crown, block, plate, confetti |
| Rendered from the game | an in-game item (a cue, a block) | both cues, tip left, from the real mesh and skin |
| Drawn by code | glows, rays, bokeh, sparkles, fireworks, patterns, panels | `draw_pieces.py`, `effects.py`, `frame_art.py` |
| Native | frames, pills, chips, buttons, every word | `HudParts`, `ShopParts`, `ArchTitle` |

## 4. Cutting pieces from a target

`tools/gui/cut_pieces.py` is the worked example (free, local, no image API): BiRefNet HR mattes
on a crop (Apple MPS), a soft disc for blurred balls, a colour key for confetti, a polygon where
an edge is hidden; colours decontaminated with pymatting so no background fringe rides on a soft
edge; glows as "unmult over the local background". It writes each layer with a clear border,
`layers.json` (boxes, z order, method), the plate with holes and fill masks.

- `rebuild_check.py`: stack the plate and layers, compare with the target side by side and as
  a difference heat map, and show each layer on black, white and a checkerboard.
- `masked_fill.py LAYER "what"`: repaint only a cut layer's hidden pixels with a masked GPT
  edit and paste back only those, so every visible pixel stays the target's.
- Upscale a cut piece with Real-ESRGAN when it would show larger than the target holds it.

## 5. Generating and filling with the image tool

```bash
python3 tools/openai_image.py --prompt "..." --out OUT.png \
    --image layout.png --image ref.png [--mask mask.png] \
    --size 1536x1024 --quality high --background transparent --tag <screen>
python3 tools/openai_image.py --total   # the running spend
```

- Clean transparent PNGs: `--background transparent`, and say "no background, no surface, no
  shadow" in the prompt; the same reference pack every call keeps the style.
- `--mask` (edits only): the mask's clear pixels are the area to repaint.
- Every call is logged to `assets/cue/concepts/openai_log.jsonl`; commit the log with the art.

## 6. Rendering from the game (Blender)

`tools/gui/render_cues.py` runs in headless Blender
(`/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python-exit-code 1
--python tools/gui/render_cues.py -- <jobs>`) on the real cue mesh, skins and pieces: one camera
and canvas (2304 x 640) for every picture so overlays line up exactly, a transparent film, the
picture and its white silhouette (`*_mask.png`) for shine sweeps, and frame loops for moving
parts. `cue_sheets.py` packs loops into sheets with JSON. Renders go to
`~/Desktop/8ball-refs/gui-lively/work/renders/` (`tip_left/` is the card's framing).

## 7. Drawing by code, unmult, flipbook sheets

- `effects.py`: fireworks in five colours and a sparkle, drawn with a fixed seed at 2x with
  light adding up, glowed, shrunk, then **unscreened** (brightness becomes alpha) so a sheet
  sits on any background. Colours are baked: `ImageColor3` can only darken white.
- A flipbook is one 1024 x 1024 sheet of 8 x 8 frames of 128 px (or 4 x 4 of 256), with a JSON
  beside it (columns, rows, frame size, frame count, fps, loop). Play at 30 fps; a slow
  flipbook looks choppy (pitfalls.md).
- `draw_pieces.py`: bokeh, the block's glow, card backgrounds and panels, the glyph-code strip;
  `--mask IN OUT` makes a white silhouette for a shine sweep. `frame_art.py`: the sheet's dot
  tile with a 3 x 3 seam check.
- Patterns that scroll: a seamless tile repeated across the picture (the header's 200-texel
  period across 1024) so the scroll window always stays inside.

## 8. Baking pieces together, glows and masks

When two pictures must move as one, bake them into one picture with a clear border instead
of animating two labels in step:

- `crowned_block.py`: the crown placed on the block where the card had it, one 884 x 1024
  picture with a 24 px clear border (the breathe zooms inside it) and its silhouette mask; it
  prints the picture's box in the card's units for `Layout.CrownedBlock`.
- `cue_glow.py`: a soft glow from a silhouette (grow, blur, gain), white so the game tints it
  (`Layout.FireworkGlow`): the way to make a busy picture stand out.
- `firework_still.py`: one frame of a render loop cropped to its part (the ribbons), with its
  box on the cue canvas printed for Config, so it lies exactly over the cue and can pulse on
  its own.

Pattern: each baking tool reads the sources, writes the picture(s) into `assets/ui/<screen>/`,
and **prints the numbers Config needs** (box, pixel size, border). Resize in premultiplied
alpha (`im.convert("RGBa").resize(...).convert("RGBA")`) so glows keep no dark fringe.

## 9. Uploads, image ids, Config

```bash
printf "%s\n" "$PWD/assets/ui/<screen>/a.png" "$PWD/assets/ui/<screen>/b.png" > /tmp/list.txt
python3 tools/roblox_upload.py --list /tmp/list.txt --manifest tools/upload_manifest.json \
    --group-id 675425213 --dry-run          # always first
python3 tools/roblox_upload.py --list /tmp/list.txt --manifest tools/upload_manifest.json \
    --group-id 675425213
```

- The key is read from the macOS Keychain by the script; never print or write it.
- An upload returns a **Decal id**; an ImageLabel needs the **image id** inside it. Get them
  in Studio and record them:

```bash
python3 tools/manifest_image_ids.py emit --prefix assets/ui/<screen>/ > batch.luau
# run batch.luau with the Studio MCP execute_luau (in Play's Server datamodel, where
# InsertService.LoadAsset worked in the lively run; Edit also worked before): it returns
# "decalId=imageId" lines
python3 tools/manifest_image_ids.py apply result.txt
```

- Then put `rbxassetid://<imageId>` into Config (`Config.UI.<Screen>.Images`), with a comment
  naming the source file and the tool that made it. Check every id preloads (`ContentProvider:
  PreloadAsync`) with Success in Studio.
- Every image at most 1024 px on its longest side. Image uploads cost nothing. No sound
  effects, ever (designer, 2026-10-04).
- Developer products for a new page: `tools/roblox_products.py` from `tools/products_spec.json`
  (`--dry-run` first, `--only Key1,Key2`), ids into `tools/products_ids.json` and
  `Config.Products`; ask the designer before creating them. Never change a price or odds.

## 10. Spend

The image tool's stop-and-ask point for a GUI run is set in its brief (the Shop run: $500,
`--stop 500`); say the running total every $50 (`--note-every 50`). The Shop's whole run cost
$7.00 of images: cutting, drawing and rendering are free, so prefer them and generate only what
cannot be cut, drawn or rendered.

## 11. Where files go

- Finished pieces that the game uses: `assets/ui/<screen>/` (committed with the tool that made
  them). Effects: `assets/ui/effects/` with their JSON.
- Big intermediates (cuts, renders, recordings, gate pages): `~/Desktop/8ball-refs/gui-lively/work/`
  or a git-ignored `out/`, never the repo.
- Remove pictures a screen stopped using (and their Config keys); the manifest keeps the
  upload record.
