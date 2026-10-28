# Lane coordinator (W1)

Folder `~/Desktop/8ball`, branch `halloween`, Rojo 34872, Studio = the Team Create place
("Crazy 8 Ball"), Opus 5.5 with ultracode. Brief: `docs/prompts/HW_COORDINATOR_PROMPT.md`.
Contract: `docs/halloween/PLAN.md`.

## Owns

From PLAN §4 (lanes ask for these through their own lane file's Requests):

- The `halloween` branch: every merge, push and revert. Lanes never push to it. Merges on
  request from 08:45 (Cues A drop 2 at about 08:45, drop 3 and the GUI pill at about
  10:00-10:20), not only at the timed passes.
- Resolving overlaps in the shared files (PLAN §7, brief §2.2 step 4): each lane adds its own
  block or line and lists it in its lane file; you keep every lane's whole. `HubCorners`
  `padStops`: core's event tile first, GUI's pill right after Plus. `tools/upload_manifest.json`:
  the union (an `"ok"` row wins, keys sorted). `src/shared/CueSkins/*`: rerun
  `python3 tools/cue_skins_data.py`.
- `docs/STATUS.md`, `docs/DECISIONS.md`, `docs/ROADMAP.md`, `docs/archive/STATUS_HISTORY.md`,
  the Status column of `docs/halloween/REQUIREMENTS.md`, `docs/halloween/RELEASE.md` (new), this
  file and `docs/prompts/HW_COORDINATOR_PROMPT.md`.
- `tests/halloween_contract_test.luau` (new: the PLAN numbers every lane must keep).
- `tools/halloween/studio_size.sh`, `tools/halloween/device.sh` and `tools/halloween/store_page.py`
  (new), and `tools/overnight/hw_*.json`.
- The Team Create place and its Edit-mode content: the cue templates and pieces of the 5 new
  ids only (`ReplicatedStorage.CueSkins` / `CuePieces`, built with the ONLY filter),
  `ServerStorage.EventProps`, table looks, props and anything a lane's Requests spell out;
  `place/8ball.rbxl`.
- Device sweeps of the merged build (phone 844x390, iPad 1024x768, PC 1920x1080, TV 1920x1080 with
  GuiQA "pad", and Studio's Device menu presets).
- The store page: the Experience Event "Haunted Rooftop", the title prefix, the Halloween icon and
  the countdown icons, the thumbnail.
- The gate pages, the release checklist, the 19:00 watch.
- `~/Desktop/8ball-refs/halloween/shots/coordinator/`.

## Status

- 09:12 interface merge pushed: halloween @808ed389 (+ ticks @792bbb35) = sys 1c9f99b7, core 1c9945a0, cues-a
  1039f19b, gui b2c51102 (NOT b3bb0288 "Friend boost on": live pay, own review later), map 6d45e218. Reviews: 2
  workflows (5 lanes), 0 critical; minor findings sent as Requests. lint OK, 1370 passed / 0 failed, Studio
  Team Create: Rojo synced (Config 984285 bytes both sides), Play solo clean (only the old 203785492 warning).
- 09:05 new tests/client_compiles_test.luau (14e2d157): every src script compiles; Main.client must keep 8
  top-level locals of headroom (it had 14; map's block takes 2). Every lane told to wrap Main hooks in do...end.
- 08:58-09:02 store: originals recorded (store/original.json: "[EMOTES] CRAZY 8 Ball", icon 123614794049673 TN3);
  icons 5H-1H, LIVE, plain from M6 (512, corners square), uploaded with a copy of today's icon: all 8 APPROVED
  (store/icons.json). tools/halloween/store_page.py (dry-run default, log store/log.txt), selftest OK.
  Contract test tests/halloween_contract_test.luau (da021510): skips per lane until merged.
- 08:52 coordinator (CLI, started 08:44): baseline `halloween` @b16b5544, lint OK, tests 1345 passed / 0 failed.
  Hand-over verified: briefs, lane files, hooks committed and pushed (origin/halloween = local), six worktrees at
  b16b5544 with brief + lane file + hook, six lane Studio windows + the Team Create window in `list_roblox_studios`,
  Rojo 34872 serving `halloween` with live sync proven (probe comment read back in Studio, then reverted). Lanes
  started 08:43 (73 min late): new times posted in every lane file (gate 1 10:00, gate 2 11:15).
- 08:47 hw-map's Rojo had panicked at 08:44 on a Claude temp file (`Config.luau.tmp.<pid>`, change_processor.rs:172);
  could not reproduce with plain tmp+rename writes. Started `tools/halloween/rojo_watchdog.sh` (restarts any of the
  7 servers within 10 s, log `shots/coordinator/rojo-watchdog.log`); map restarted 08:47, Justin asked to Connect.
- 08:50 resize helper: System Events reads Terminal windows (Accessibility OK) and CoreGraphics reads Studio titles
  (Screen Recording OK), but all 7 Studio windows are full screen in their own Spaces, so AX sees 0 windows; Justin
  asked to exit full screen. cliclick installed (/opt/homebrew/bin/cliclick).
- 07:50 desktop session (hand-over): the briefs, lane files and hooks committed and pushed on
  `halloween`, the six worktrees fast-forwarded to it, the six lane Studio windows opened.
  Verify it at the 07:30 Progress line; do not redo it.

## Shared-file changes

None yet. Only if Cues A has no ONLY filter by 14:30: that one small commit to
`tools/build_cue_templates.luau`, listed here.

## Requests

## Assumptions

## Gate shots
