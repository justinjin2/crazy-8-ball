# Lane: Unique cues (the Beta Cue and the Grand Opening Cue)

Folder `~/Desktop/8ball-unique`, branch `lane-unique`, Rojo port 34878, Studio file
`place/lane-unique.rbxl` (a copy of the Team Create place saved 2026-10-04). Rules for all
lanes: [README.md](README.md). The job itself is the brief
[docs/prompts/UNIQUE_CUES_PROMPT.md](../prompts/UNIQUE_CUES_PROMPT.md): read it after this
file and follow it exactly; its Progress list is the source of truth.

## The job

The game's first two Limited cues, the **Beta Cue** (a see-through blueprint hologram) and the
**Grand Opening Cue** (navy and gold with fireworks), exist in the catalog only as placeholder
colour bands. Build their complete looks: surface maps, 3D pieces, aura, moving light, ball
trail, pocket finisher, faint sounds and card pictures, to a visual standard above the Secret
cue (Eclipse). The designer's references and answers are in the brief.

## You own

- Skin files and art: `assets/cue/skins/beta*.json`, `assets/cue/skins/grand_opening*.json` and
  their panel folders; `assets/cue/textures/beta_*`, `grand_opening_*`; `assets/cue/thumbs/`
  for these two; `assets/cue/pieces/beta*`, `grand_opening*`; `assets/cue/models/` entries
  you generate; `assets/cue/vfx/beta*`, `grand_opening*`; `assets/cue/concepts/unique/`.
- The generated rows `src/shared/CueSkins/Skins/BetaCue.luau` and `GrandOpeningCue.luau`
  (always through `tools/cue_skins_data.py`, never by hand).
- New tools under `tools/` or `assets/cue/` that only these cues need (name them `unique_*`
  or `beta_*` / `grand_opening_*`).
- `tools/upload_manifest.json`: add your entries; never change others'.

## Shared files you may extend

The cue runtime is generic and stays generic: `src/client/CueVfx.luau`, `CueSkinLook.luau`,
`CuePiece.luau`, `Effects.luau`, `src/shared/CueStickBuilder.luau`, `tools/cue_skins_data.py`,
`tools/build_cue_templates.luau`, the piece builders, `Config.CueSkins`, `Config.Effects`. Add
new capabilities as new data kinds or new functions, as blocks, driven by the skin data, so any
future cue can use them. No `if cueId == "BetaCue"` branches. List every change to a shared
file in this lane file's Changes section.

## Not yours

- `Progression/Catalog.luau` rarities, prices, `StartsAt`, numbering, trading and every
  economy number (the designer: the Epic and Legendary tags on these two rows are overwritten
  for visuals; do not edit the rows). If the runtime needs to know these two are above Secret,
  put that in the skin data, not the catalog.
- Every screen (GUI lane): where a cue's number is shown is GUI's decision. Write what the
  cards and the Index need from you in Requests.
- `docs/STATUS.md`, `DECISIONS.md`, `ROADMAP.md`, `ECONOMY.md`.

## Integration (what the integrator does in the real place)

Written in the brief's Handoff section when the work is done: the uploaded asset ids (in
the manifest), the two templates and any pieces to build with the builders, and anything made
by hand in your copy (which is otherwise lost at the merge).

## Status

(one dated line per finished step)

- 2026-10-04 step 0: docs read, lane window and Rojo 34878 checked, section 7 answered (0.36,
  the three sound files, own outline colours, catalog helper). Commit 5650020 (0.36 width)
  cherry-picked without the shared docs; lint and 984 tests green; the lane window's Classic
  mesh swapped and all templates and pieces rebuilt; the wide cue checked on backs, stands
  and in hands (PC). The integrator must do the same mesh swap and template rebuild in the
  real place at the merge (Requests).

## Decisions

(dated; small calls you made on your own)

- 2026-10-04: the overnight Stop hook looked for its marker files under `.git/`, which is a
  file in a worktree; it now resolves the real git directory (tools/overnight/keep_going.sh).

## Changes to shared files

(file, what, why)

## Requests

(for the GUI lane and the integrator)

- Integrator, at the merge (the 0.36 cue, commit 5650020 cherry-picked here): in the real
  place, Edit mode, swap `ReplicatedStorage.CueSkins.Classic.Cue` to the new mesh
  (`InsertService:LoadAsset(73474446131672)`, `cue:ApplyMesh(thatMeshPart)`, then
  `cue.Size = Vector3.new(0.36, 0.36, 7)`), set Classic's four maps from
  `src/shared/CueSkins/Skins/Classic.luau` (plugin writes of `*MapContent`), then run
  `tools/build_cue_templates.luau` to rebuild every template and piece. Checked in the lane
  window 2026-10-04: 58 templates, 16 pieces, no problems.
