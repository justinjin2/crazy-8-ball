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
