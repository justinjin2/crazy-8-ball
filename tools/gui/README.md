# tools/gui: the lively GUI pipeline

Scripts for building animated, layered screens (docs/prompts/SHOP_LIVELY_PROMPT.md; the
`lively-gui` skill will point here once it is written).

- Python lives in its own environment: `uv venv tools/gui/.venv` then
  `VIRTUAL_ENV=tools/gui/.venv uv pip install pillow numpy` (git-ignored). Run scripts with
  `tools/gui/.venv/bin/python`.
- Big intermediate files go to `~/Desktop/8ball-refs/gui-lively/work/` or an `out/` folder
  (git-ignored), never into the repo.
- `grand_opening/pieces.json`: every piece of the Grand Opening card (13b) with its box, its
  source (cut, regenerated, rendered or drawn), its reveal step and its idle loop.
- The cutting step also needs `torch torchvision transformers timm kornia einops
  opencv-python-headless scipy pymatting` in the venv (BiRefNet HR, MIT, downloads once from
  Hugging Face and runs on Apple MPS).
- `cut_pieces.py`: cuts the Grand Opening card's pieces out of 13b (no image API): layers, their
  positions (`layers.json`), the plate with holes, the plate-fill mask and each layer's own fill
  mask, into `~/Desktop/8ball-refs/gui-lively/work/pieces/`.
- `rebuild_check.py`: stacks the plate and the layers, compares with 13b (side by side and a heat
  map), shows each layer on black, white and a checkerboard, prints the difference numbers.
- `frame_art.py`: the white sheet's dot tile, `assets/ui/frame/dots_512.png`, plus a 3 x 3 seam
  check and a preview against the designer's option A.
- `bin/` (git-ignored): `realesrgan-ncnn-vulkan` (xinntao/Real-ESRGAN v0.2.5.0 macOS) with the
  `realesrgan-x4plus-anime` and `realesrgan-x4plus` models: `tools/gui/bin/realesrgan-ncnn-vulkan
  -i in.png -o out.png -n realesrgan-x4plus-anime -m tools/gui/bin/models` (4x, about 3 s).
- `masked_fill.py LAYER "what"`: repaints only a cut layer's hidden pixels (its fill mask) with a
  masked GPT Image edit and pastes back only those, so every visible pixel stays 13b's
  (`pieces/filled/<id>.png`; the block's top under the crown was filled this way).
- `draw_pieces.py`: the drawn pieces from code with a fixed seed (bokeh disc, block glow, Beta
  background and blueprint panels, the glyph-code strip, the GO background) into
  `assets/ui/grand_opening/`; `--mask IN OUT` makes a white silhouette for a shine sweep.
- `assets/ui/grand_opening/` holds the card's finished pieces (at most 1024 px). The plate is a
  new 2:1 painting in 13b's mood (13b's own plate is 3:1); the three balls are one clean ball
  at three blurs; the confetti is a regenerated sheet unscreened from black.
- `render_cues.py` (run inside headless Blender) and `cue_sheets.py`: the two cues rendered from
  the real in-game mesh, skins and pieces (`--tip left` like 13b), their silhouettes, and the Grand
  Opening cue's gold ribbon loop (`loose`: 13b-like wide loops), packed into sheets with a JSON
  beside each. The card uses the tip-left renders and the loose ribbons, played at a 2.4 s turn
  (13.3 fps; the in-game 7.2 s turn would be 4.4 fps, too choppy).
