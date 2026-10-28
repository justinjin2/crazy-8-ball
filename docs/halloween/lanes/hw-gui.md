# Lane hw-gui (W7 Boost pill + Cue Preview)

Folder `~/Desktop/8ball-hw-gui`, branch `hw-gui`, Rojo 34888, Studio `place/lane-hw-gui.rbxl`,
Opus 5.5 xhigh. Brief: `docs/prompts/HW_GUI_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.
Launch and restart line: exactly what `tools/halloween/lanes.sh command hw-gui` prints (never
your own flags). Waiting file: `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`.

## Owns

From PLAN §4 (everything else is read-only; ask below under Requests):

- `Money.boostParts`, `Money.friendBoost` and the friends part of `Money.boost`
  (`src/shared/Progression/Money.luau`) and of `Economy.boost` (`src/server/Economy.luau`), with
  the new `src/shared/Progression/BoostFlags.luau`; the `Config.Economy` friend lines
  (`FriendBoostEnabled`, `FriendBoost`, `FriendBoostMaxFriends`, `FriendRetrySeconds`): the
  only friend-boost numbers and the one friend switch for money AND Candy (core reads them and
  the existing `GroupBoost` through `Money.friendBoost` / `Money.boostParts`).
- The `FriendsHere` count in `src/server/Friends.luau` (`Friends.count`, the Studio `FriendsQA`
  hook, the `FriendBoost` analytics event).
- `Config.UI.BoostPill`, `Strings.BoostPill`; the pill + its "YOUR BOOSTS" card + the Rush chip's
  SHELL and position (`src/client/BoostPill.luau`; it replaces the VIP tag in the row above
  money; core fills the chip's words through `RushChip.content`; its icon is core's
  `Config.Halloween.CandyIcon`, read guarded).
- The pure HUD layout function `src/shared/HudLayout.luau` + `tests/hud_layout_test.luau`.
- `src/client/CuePreview.luau`, `src/shared/CuePreviewMath.luau`,
  `tests/cue_preview_math_test.luau`, `Config.UI.CuePreview`, `Strings.CuePreview`, the Preview
  buttons in My Cues (`InventoryCues.luau`) and the Index (`InventoryIndex.luau`).
- Not yours: the chip's words and timing, Candy maths and `Config.Halloween` incl. `CandyIcon`
  (core); the event tile and its FIRST place in `HubCorners.padStops` (core); the track cards'
  Preview button, which calls your `CuePreview.open` through a guarded require (core);
  `TableService.luau` (Roam + Badges); the custom-model cue path and `CueAssets` (Cues A);
  `docs/STATUS.md`, `ROADMAP.md`, `DECISIONS.md`, `ECONOMY.md` (coordinator).

## Status

## Shared-file changes

PLAN §7 shared files: your own block or line only; the coordinator resolves overlaps. Planned
(add the commit sha as each lands, plus any other existing line you had to change):

- `HubCorners.luau` (core edits it too): the pill as ONE `padStops` entry right after
  `self.plusTile.button` (core's event tile is the first entry, its line); own lines in
  `blurPad` and `padFocusedOn`.
- `Net.luau:395` (core and map edit it too): the new event names in the comment only.
- `Config.luau`: the `Config.Economy` friend lines after `PlusBoost`; `Config.UI.BoostPill`;
  `Config.UI.CuePreview`.
- `Strings.luau`: `Strings.BoostPill`, `Strings.CuePreview`.
- `Progression.luau`: :265-267, :302-309 (BoostPill instead of VipTag, `deps`), :615
  (`setInMatch`, `CuePreview.close()`).
- `Main.client.luau:1265`: one guarded line (the preview's cue in `ids`).

## Requests

## Assumptions

## Gate shots
