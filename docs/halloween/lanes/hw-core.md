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

- 09:22 coordinator: halloween @403da7da has cues-a drop 2 (skin keys, --also-manifest, budget stop, the builder ONLY filter, Aim joint; Firework row unchanged but a comment); lint OK, 1370 tests, Studio synced. Run `git fetch && git merge origin/halloween`. Cues B: you can generate rows now.
- 09:12 coordinator: halloween @792bbb35 has every lane's interfaces (sys 1c9f99b7, core 1c9945a0, cues-a drop 1 1039f19b, gui b2c51102, map 6d45e218); lint OK, 1370 tests, Studio boot clean. Run `git fetch && git merge origin/halloween` now. Gate 1 is at 10:00: shots + one caption line each in your Gate shots by 09:55.
- 09:12 coordinator REQUEST (minor, before the menu uses them): `Event.nextRushAt` returns EndsAt in the last hour and a time while Rush is off: return nil then (number?) or document it; `Event.short`/`Event.clock` unit letters ('%dd %dh', '%dh %dm', '%dm', m:ss) belong in Strings (Strings.luau:719-721/811-813 have templates); quest Alts on boards 2 and 3 duplicate an existing row ('Win 2'/'Win 3') when the King or UltService.Used is off: pick distinct Alts; `UltService.Used` also fires for free solo practice: ignore it when `TableService.get(id).engine.solo`.
- 09:05 coordinator REQUEST (all lanes, blocks a merge): `src/client/Main.client.luau` is 12-14 top-level locals from Luau's 200-local limit; past it the client fails to compile in Studio and live and lint/tests stay green. Put every Main.client addition inside `do ... end` (zero new top-level locals), e.g. `do local ok, err = pcall(...) ... end`. New test `tests/client_compiles_test.luau` (on halloween @HEAD) compiles every src script and fails if Main.client has fewer than 8 locals left; run it before you push.
- 08:50 **Interface 1 READY to merge** (`4f63cb79` on `hw-core`): `Config.Halloween` (times, numbers,
  switches, `CandyIcon = ""`), `Strings.Halloween` skeleton, `src/shared/Halloween/Event.luau` (pure:
  `state/isLive/over/endsIn/startsIn/rushActive/rushEndsAt/nextRushAt/doubleDay/multiplier/boardIndex/
  boardOpensAt/rushChip/clock/short`) and `Clock.luau` (`Clock.now()` for gates, `Clock.serverNow()` for
  saves; `HwTimeOffset` only in Studio and on the test place). Bootstrap calls `Clock.boot()`: in Studio
  and on the test place a server booted before 19:00 starts Live (`Config.Halloween.Test.BootLive`).
  **Every lane gates on `Event.*(Clock.now())`.** Lint and all 1,354 tests green. Interface 2
  (save field + real `CandyService`) next.
- 09:05 **Interface 2 READY to merge** (`06a05a85`, `/hw` in `1bf0e34f`): the additive `Halloween` save
  field (template, MAP_KEYS, `fixHalloween`, old-save test), PlayerData's Halloween block (one commit per
  grant: Candy, quests, track steps, Spider; `PlayerData.halloween(player)` read-only copy with stable
  `KingWins`, `Earned`, `Bought` for hw-sys's badge rules), and the real
  `src/server/Halloween/CandyService.luau` started in Bootstrap (lobby + arena): `add(player, amount,
  source, opts?) -> number`, `bossWon(player) -> {granted, amount, cooldownEndsAt}`,
  `bossCooldown(player) -> unix time or 0`, `pickup(player) -> (ok, "Cap"|"NotLive"|"NotLoaded"|nil)`,
  `isLive()`. Studio-checked in lane-hw-core through `ServerStorage.HwQA` and `/hw`: boosted add
  100 -> 220 in a Rush with the group, pickup ok, King 50/50/0 + 900 s cooldown, steps 1 and 3 given,
  Candy Corn held (no `Catalog.ready` yet), `/hw time` walked Before -> Countdown -> Live -> Rush ->
  double -> board 4 -> Ended, conversion once ($10 a Candy). Console clean. Lint + 1,365 tests green.
  `Config.Halloween.Match/Quests/Spider/Packs.Enabled` are still false (flip once verified).

- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
## Shared-file changes

Shared per PLAN §7 (add only core's own block or line; the coordinator resolves overlaps).
Planned, each to be confirmed here with its commit when it lands:
- `Config.luau`: `Config.Halloween` (with `CandyIcon`, no friend/group keys), `Config.UI.Halloween`, product rows.
- `Strings.luau`: `Strings.Halloween` after `Corners` (4f63cb79, `Dev` lines 06a05a85).
- `SaveSchema.luau`: `freshHalloween()`, `Halloween` template entry after `EmoteFavorites`, `"Halloween"` last in `MAP_KEYS`, `fixHalloween` + its call last in `validate` (06a05a85; hw-sys adds `Badges` at the same spots).
- `PlayerData.luau`: four `Shared.Halloween` requires after `RankClaim`; the Halloween mutation block after `PlayerData.actingRegular` (06a05a85); later `candy` in `GRANT_FIELDS` / `applyPurchase`.
- `Ranking.luau`: one `pcall(CandyService.matchSettled, ...)` line in `settleOne`.
- `HubCorners.luau`: the event tile spec and ONE line, the tile first in `padStops` (GUI adds the pill right after Plus, and `blurPad`/`padFocusedOn`).
- `Net.luau`: the `Halloween` remote (map adds its remotes, GUI a comment line).
- `DevCommands.luau`: the `/hw` block (`/hw kingwin`, not map's `/king`) after `/funnel` (1bf0e34f); `Config.Debug.Commands.Halloween = "/hw"` after `Funnel`.
- `Bootstrap.server.luau`: one `Clock.boot()` line after `Net.build()` (4f63cb79) and one `CandyService.start()` line after `Rewards.start()` (06a05a85); client `Progression.luau`, `Shop.luau`, `SkyDropService.luau` (one getter).
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
