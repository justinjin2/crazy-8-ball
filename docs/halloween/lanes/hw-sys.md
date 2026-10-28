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

## Shared-file changes

PLAN §7 shared files: add your own block or line, and as each lands replace its planned line
below with file:line and the commit. The coordinator resolves overlaps.
- planned `src/shared/Config.luau`: `Config.Multiplayer.Roam` after `Fence`, the `Config.Badges` block, `Config.Save.MaxBadgeEntries`
- planned `src/shared/Strings.luau`: `Strings.Badges`
- planned `src/shared/Progression/SaveSchema.luau`: `Badges` (template, `MAP_KEYS`, `fixMap`) and `Stats.UltMatches` (core adds `Halloween` to the same spots)
- planned `src/server/PlayerData.luau`: the `markBadges` + `countUltMatch` block
- planned `src/server/Ranking.luau`: one `Badges.matchSettled` line in the per-entry loop (`:580-590`), apart from core's `settleOne` hook
- planned `src/server/UltService.luau`: the `UltService.Used` signal, fired in the success branch (`:319`); this lane adds it and it is the build's only UltService edit (core subscribes)
- planned `src/server/Bootstrap.server.luau`: `Badges.start()` next to `Leaderboards.start` (`:65`)
- planned `src/client/Progression.luau`: the `Portals.setBlocked` call near `:651`
- planned `src/shared/Progression/Inventory.luau`: the public `everOwned` alias
- planned `tests/save_schema_test.luau`: the `"Badges"` line in the key list (`:360-366`, core adds `"Halloween"` there), the old-save test
- planned `tests/config_test.luau`: `Roam.Enabled` boolean, `Badges.check` empty, `StaggerSeconds` 3
- planned `src/server/DevCommands.luau`: only if the `/badges` readout is built (cut 1)
- `src/server/TableService.luau`: owned by this lane; list the roam edits here too

## Requests

- To core: subscribe to `UltService.Used (player, tableId, epoch)` through a guarded require for
  "Use an ability in 3 matches"; make no edit of your own in `UltService.luau` (PLAN §5).
- To core: keep `Halloween.KingWins`, `Halloween.Earned` and `Halloween.Bought` named as they are;
  Pumpkin Slayer and Halloween 2026 back-pay from them (`{ halloween = "KingWins" | "Candy", atLeast = 1 }`).

## Assumptions

## Gate shots
