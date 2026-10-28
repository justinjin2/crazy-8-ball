# Lane hw-core (W2 Event core)

Folder `~/Desktop/8ball-hw-core`, branch `hw-core`, Rojo 34883, Studio `place/lane-hw-core.rbxl`,
Opus 5.5 xhigh. Brief: `docs/prompts/HW_CORE_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.
Launch or restart: the command printed by `tools/halloween/lanes.sh command hw-core`.

## Owns

From PLAN §4 (everything else is read-only; ask below under Requests):

- `Config.Halloween`, `Config.UI.Halloween`, `Strings.Halloween`.
- `src/shared/Halloween/*` (pure: `Event`, `CandyMath`, `Track`, `Quests`; plus `Clock`).
- `src/server/Halloween/*` (`CandyService`: Candy, quests, track grants, Spider clock, packs
  grant, conversion).
- `src/client/Halloween/*`: the event tile in the right-side slot, the event menu (track, quest
  board, Spider ring, Rush strip, Get Candy), the Rush chip CONTENT (`RushChip.content`; the
  shell and position are hw-gui's), the countdown pill (18:30) and the 19:00 start moment, the
  Candy toast and track-step reveal, the end screen.
- The `Halloween` save field (SaveSchema template, MAP_KEYS, validate) and its PlayerData
  mutations; the `candy` grant field in `Shop.Grant` / `PlayerData.applyPurchase`.
- The two Candy products (`Candy500` 49 R$, `Candy2000` 149 R$): `tools/products_spec.json`,
  `tools/products_ids.json`, `Config.Products.List` rows.
- The Candy settle hook in `Ranking.settleOne`; the `SkyDropService.isActive` getter; the
  `/hw` block in `DevCommands`; the event tile spec in `HubCorners` and its line at the top of
  `padStops`; the `Halloween` remote in `Net`.
- NOT `UltService.luau`: core subscribes to hw-sys's `UltService.Used` signal through a guarded
  require and makes no edit there.
- Tests: `tests/halloween_*_test.luau`, additions to `save_schema_test` and `config_test`.

## Status

## Shared-file changes

Shared per PLAN §7 (add only core's own block or line; the coordinator resolves overlaps).
Planned, each to be confirmed here with its commit when it lands:
- `Config.luau`: `Config.Halloween` (with `CandyIcon`, no friend/group keys), `Config.UI.Halloween`, product rows.
- `Strings.luau`: `Strings.Halloween`.
- `SaveSchema.luau`: `Halloween` template entry, `MAP_KEYS`, `fixHalloween` (hw-sys adds `Badges` at the same spots).
- `PlayerData.luau`: the Halloween mutation block, `candy` in `GRANT_FIELDS` / `applyPurchase`.
- `Ranking.luau`: one `pcall(CandyService.matchSettled, ...)` line in `settleOne`.
- `HubCorners.luau`: the event tile spec and ONE line, the tile first in `padStops` (GUI adds the pill right after Plus, and `blurPad`/`padFocusedOn`).
- `Net.luau`: the `Halloween` remote (map adds its remotes, GUI a comment line).
- `DevCommands.luau`: the `/hw` block (`/hw kingwin`, not map's `/king`).
- `Bootstrap.server.luau`, client `Progression.luau`, `Shop.luau`, `SkyDropService.luau` (one getter).
- `tests/save_schema_test.luau`, `tests/config_test.luau`: core's own cases only (sys and map add theirs).

## Requests

- Coordinator: mirror `finished` (HW_CORE 2.6: 1 unless the player's side forfeited a real match; the winner of a real forfeit gets 10 + 25) in the Candy contract test.
- hw-sys: core consumes `UltService.Used (player, tableId, epoch)` and makes no UltService edit; the rule kind `{ halloween = "KingWins" | "Candy", atLeast = n }` for PumpkinSlayer and Halloween2026 reads `Halloween.KingWins` and `Halloween.Earned + Halloween.Bought`.
- hw-gui: core reads friends and group only through `Money.friendBoost` / `Money.boostParts` (guarded fallback to the same `Config.Economy` keys), so `Config.Halloween` has no friend switch and `FriendBoostEnabled` turns the friend part off for money and Candy together. Core's event tile is the first `padStops` entry; the pill goes right after Plus. Core's track cards call `CuePreview.open(id, { from = "Track", note = ... })` through a guarded require when `CuePreview.enabled()`. The Candy icon is `Config.Halloween.CandyIcon`.
- hw-map: the Alts read `HM.Enabled and HM.Boss.Enabled` and `HM.Enabled and HM.Candy.Enabled`; `CandyService.pickup` returns `(ok, reason)` with `"Cap"|"NotLive"|"NotLoaded"|nil` (show the bag-full note only on `"Cap"`; the cap is only `Config.Halloween.Pickup.HourCap`); `CandyService.bossCooldown(player) -> number` (unix time, 0 if none); the Candy icon is `Config.Halloween.CandyIcon`.
- hw-cues-a: core grants and shows a track cue only when `Catalog.ready(id)` is true and retries held grants on load and every tick.

## Assumptions

- OVERRULED (PLAN §6, for Justin): the pickup quests are 15 / 30 / 50 lobby Candy instead of 25 / 50 / 100. Pickups only come in the lobby at about 25 an hour for an active player (capped at 40), so 100 would take up to 4 hours of lobby time; 15 / 30 / 50 take about 35 min / 1 h 10 min / 2 h.
- OVERRULED (PLAN §6, for Justin): "Play 30 min today" and "Play 45 min today" count ACTIVE minutes (the Spider's idle-gated clock, `SkyDropService.isActive`) while that board is the one routed to, not wall-clock minutes in a calendar day, so standing idle does not finish them and they follow the oldest-unfinished-first order like every other quest.

## Gate shots
