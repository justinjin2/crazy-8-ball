# Lane hw-sys: Roam + Badges (W6)

Folder `~/Desktop/8ball-hw-sys`, branch `hw-sys`, Rojo 34887, Studio `place/lane-hw-sys.rbxl`,
Opus 5.5 xhigh. Brief: `docs/prompts/HW_SYS_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.

## Owns

From PLAN section 4 (everything else is read-only to this lane; ask through Requests):
- `Config.Multiplayer.Roam`
- the roam edits in `src/server/TableService.luau`; **`TableService.luau` belongs to this lane
  for the whole build** (other lanes request changes here)
- the `src/client/Portals.luau` and `src/server/LuckyBlockService.luau` guards
- `Config.Badges`, `Strings.Badges`
- `src/shared/Progression/Badges.luau`, `src/server/Badges.luau`
- the `Badges` save field
- badge icons and `tools/roblox_badges.py` (creates badges through Open Cloud, writes ids back)

New files the brief adds for these: `src/shared/Matchmaking/Roam.luau`, `tests/roam_test.luau`,
`tests/badges_test.luau`, `tools/export_badges.luau`, `tools/gen_badge_icons.py`,
`tools/badges_manifest.json`, `assets/ui/badges/`.

## Status

- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
- 09:10 hw-sys: **interface 1 pushed** (9b79ca6b): `Config.Multiplayer.Roam` (off),
  `Config.Badges` (52 inert rows, off), `Strings.Badges`, the `Badges` save map,
  `Stats.UltMatches`, `Config.Save.MaxBadgeEntries`, old-save test. **Interface 2 pushed** (see the
  commit after it): `src/server/Badges.luau` (`start`, `grant`, `matchSettled`; off = does
  nothing), the Bootstrap start line, `UltService.Used (player, tableId, epoch)`. Lint and
  tests green, Studio play console clean. **Ready to merge.**
- Probe (09:00): free quota today **5**, `badgeCreationPrice` **100**, the invalid create
  answered HTTP 400 code 14 ("Invalid badge name."): **scope OK on ROBLOX_USER_KEY**, nothing
  charged. Cost for 52: 5 free + 47 x 100 = **4,700 R$**, inside the approved spend.

## Shared-file changes

PLAN §7 shared files: add your own block or line, and as each lands replace its planned line
below with file:line and the commit. The coordinator resolves overlaps.
- `src/shared/Config.luau:8109` `Config.Multiplayer.Roam` after `Fence`; `:17047` the `Config.Badges` block (new, before the Cutscenes block); `:1769` `Config.Save.MaxBadgeEntries` (one new line) — 9b79ca6b
- `src/shared/Strings.luau:2546` `Strings.Badges` (new block at the end) — 9b79ca6b
- `src/shared/Progression/SaveSchema.luau:67` `"UltMatches"` in `STAT_KEYS`; `:90` `"Badges"` in `MAP_KEYS`; the template's `Badges = {}` after `EmoteFavorites`; `:1432` `fixMap(data.Badges, ...)` (core adds `Halloween` to the same spots) — 9b79ca6b
- `src/server/UltService.luau:51-55` the `Used` BindableEvent + `UltService.Used`; `:326` fired in the UltActivate success branch next to `Funnel.spins` — interface 2
- `src/server/Bootstrap.server.luau:67` `Badges.start()` right after `Leaderboards.start` — interface 2
- `tests/save_schema_test.luau:25` `"UltMatches"` in its `STAT_KEYS`; `:366` `"Badges"` in the key list (core adds `"Halloween"` there); `:1773` the old-save badges test (new, last) — 9b79ca6b
- `tests/config_test.luau`: one new test "the roam switch and the badge registry are well formed" (before "shared modules cannot see Roblox globals") — 9b79ca6b
- planned `src/server/PlayerData.luau`: the `markBadges` + `countUltMatch` block
- planned `src/server/Ranking.luau`: one `Badges.matchSettled` line in the per-entry loop (`:580-590`), apart from core's `settleOne` hook
- planned `src/client/Progression.luau`: the `Portals.setBlocked` call near `:651`
- planned `src/shared/Progression/Inventory.luau`: the public `everOwned` alias
- planned `tests/config_test.luau`: `Badges.check` returns nothing (with the pure evaluator)
- planned `src/server/DevCommands.luau`: only if the `/badges` readout is built (cut 1)
- `src/server/TableService.luau`: owned by this lane; list the roam edits here too

## Requests

- To map: in `BossService`, on a King win call
  `pcall(function() require(ServerScriptService.Server.Badges).grant(p, "PumpkinSlayer", "Boss") end)`
  (guarded require + pcall; `grant` returns false while the queue is off, never errors). The
  `{ halloween = "KingWins", atLeast = 1 }` rule also back-pays from core's save field, so a
  missed call is caught on the next save change or join.
- To map: the Pumpkin King's prompt must refuse a seated player (`TableService.tableOf(p) ~= nil`):
  with roaming on, an in-match player can walk to the throne while waiting.
- To map (note, no change asked): `CandyDrop` skips seated players by PLAN, so a roaming player
  collects no lobby Candy during their match; MoneyRain still pays roamers (distance only).
- To core: subscribe to `UltService.Used (player, tableId, epoch)` through a guarded require for
  "Use an ability in 3 matches"; make no edit of your own in `UltService.luau` (PLAN §5).
- To core: keep `Halloween.KingWins`, `Halloween.Earned` and `Halloween.Bought` named as they are;
  Pumpkin Slayer and Halloween 2026 back-pay from them (`{ halloween = "KingWins" | "Candy", atLeast = 1 }`).

## Assumptions

## Gate shots
