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

- **Interfaces ready: 0119a786** (pushed 08:58 EDT, late against 08:15: the lane started 08:43).
  - `37d80752` `Money.friendBoost(count) -> number`, `Money.boostParts(flags) -> { { kind, add } }`
    (order Vip, Group, Plus, Friends, Starter, Party; active parts only; fresh table),
    `friends: number?` in `Money.Boosts`, `Money.boost` = their sum (old sum order kept, so old
    pay is bit for bit the same). `Config.Economy.FriendBoostEnabled = false` (switch),
    `FriendBoost = 0.1`, `FriendBoostMaxFriends = 4`, `FriendRetrySeconds = 30`. Tests in
    `tests/money_test.luau` (2 new cases; suite 1347/1347).
  - `0119a786` `FriendsHere` player attribute (number, uncapped, server-set, replicated; checked
    in Studio: 0 → `FriendsQA count 2` → 2 on server and client → nil → 0), `Friends.count(player)`,
    one retry after `FriendRetrySeconds`, Studio `ServerStorage.FriendsQA` `("count", player or
    userId, n?)`, the `FriendBoost` custom event on leaving.
  - **Chip contract (no stub module):** the Rush chip shell (in `src/client/BoostPill.luau`) polls
    core's `src/client/Halloween/RushChip.luau` `RushChip.content(now) -> { text: string,
    endsAt: number }?` once a second through a guarded require
    (`script.Parent:FindFirstChild("Halloween")` → `RushChip`, in a pcall; `now` from
    `Shared.Halloween.Clock.now()`, else `workspace:GetServerTimeNow()`). Missing, error or nil →
    hidden. Icon: `Config.Halloween.CandyIcon` (guarded; missing or `""` → no icon slot).
  - **CuePreview signatures** (module `src/client/CuePreview.luau`, lands with the preview merge):
    `CuePreview.open(id: string, opts: { from: string?, onClose: (() -> ())?, note: string? }?)
    -> boolean`, `CuePreview.enabled() -> boolean`, `CuePreview.isOpen() -> boolean`,
    `CuePreview.close()`. From core's `src/client/Halloween/*`:
    `script.Parent.Parent:FindFirstChild("CuePreview")`, required in a pcall; show the track
    card's Preview button only when `CuePreview.enabled()`.

- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
## Shared-file changes

PLAN §7 shared files: your own block or line only; the coordinator resolves overlaps. Planned
(add the commit sha as each lands, plus any other existing line you had to change):

- `HubCorners.luau` (core edits it too): the pill as ONE `padStops` entry right after
  `self.plusTile.button` (core's event tile is the first entry, its line); own lines in
  `blurPad` and `padFocusedOn`.
- `Net.luau:395` (core and map edit it too): the new event names in the comment only.
- `Config.luau`: the `Config.Economy` friend lines after `PlusBoost` (**37d80752**, added only); `Config.UI.BoostPill`;
  `Config.UI.CuePreview`.
- `Strings.luau`: `Strings.BoostPill`, `Strings.CuePreview`.
- `Progression.luau`: :265-267, :302-309 (BoostPill instead of VipTag, `deps`), :615
  (`setInMatch`, `CuePreview.close()`).
- `Main.client.luau:1265`: one guarded line (the preview's cue in `ids`).

## Requests

- **To core (hw-core):** read the Candy friend and group part through `Money`, guarded:
  `Money.boost({ friends = player:GetAttribute("FriendsHere"), group = player:GetAttribute("InGroup") == true })`
  (or `Money.friendBoost(n)` plus the Group part of `Money.boostParts`). It already treats a
  missing or non-number count as 0 and caps at 4. No friend or group numbers in
  `Config.Halloween`: one source, one switch (`Config.Economy.FriendBoostEnabled`) for both
  currencies (PLAN §5).
- **To core:** fill `Config.Halloween.CandyIcon` before gate 1 (the Rush chip shows it).
- **To core:** the track's cue cards call `CuePreview.open(id, { from = "Track", note = ... })`
  through a guarded require, their button shown only when `CuePreview.enabled()`.
- **To core:** in `HubCorners.padStops` your event tile is the FIRST entry; the pill goes right
  after `self.plusTile.button` (my one line).
- **To the coordinator:** the `docs/ECONOMY.md` 3.5 and `DECISIONS.md` lines for the friend boost
  (+10% a friend in the server, max 4, added, permanent, money and Candy, own switch
  `Config.Economy.FriendBoostEnabled`).
- **To the coordinator:** HUD overlaps among the existing pieces that `tests/hud_layout_test.luau`
  prints (filled in at step 5).
- **To the coordinator:** a touch sweep of the Cue Preview in the device emulator (not scriptable
  from a lane).
- **To the coordinator:** the HubCorners and Net overlaps with core at merge (my lines are listed
  under Shared-file changes).

## Assumptions

## Gate shots
