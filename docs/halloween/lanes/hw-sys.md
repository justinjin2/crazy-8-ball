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

- 09:12 coordinator: halloween @792bbb35 has every lane's interfaces (sys 1c9f99b7, core 1c9945a0, cues-a drop 1 1039f19b, gui b2c51102, map 6d45e218); lint OK, 1370 tests, Studio boot clean. Run `git fetch && git merge origin/halloween` now. Gate 1 is at 10:00: shots + one caption line each in your Gate shots by 09:55.
- 09:12 coordinator REQUEST (minor): fix the `UltService.Used` comment (UltService.luau:52-55): the table id does NOT tell solo practice apart; listeners must check `TableService.get(id).engine.solo` (free practice abilities fire it). Say the same in your Request to core, and make Badges' Ability1/countUltMatch ignore solo.
- 09:05 coordinator REQUEST (all lanes, blocks a merge): `src/client/Main.client.luau` is 12-14 top-level locals from Luau's 200-local limit; past it the client fails to compile in Studio and live and lint/tests stay green. Put every Main.client addition inside `do ... end` (zero new top-level locals), e.g. `do local ok, err = pcall(...) ... end`. New test `tests/client_compiles_test.luau` (on halloween @HEAD) compiles every src script and fails if Main.client has fewer than 8 locals left; run it before you push.
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

- 09:15 hw-sys: **roam built and first Studio pass passed** (switch still off in Config; on
  locally for the checks): checks 1 (roam 70 studs in the opponent's turn, home in 0.13 s on
  my turn, camera locked, clock normal), 2 (bench: seat did not move, weld released), 3 (off
  the roof: back at my table in 0.57 s), 4 (another table's pad: not seated; PC portal pad: no
  dialog; lucky block Open refused "Busy", Hold still fine), 8 (tutorial match: fence holds,
  10 studs then the wall, group PoolParticipants). `RoamHome` logs (56, 71 studs, 1v1, PC).
  **Badges**: pure rules + tests, server queue, hooks (settle, UltService.Used, OwnerHere,
  InGroup) pushed with the switch off. Studio (switch on locally, QA stand-in ids): 22 veteran
  badges held during the tutorial, then from the skip Welcome at 2.75 s and one every 3.07 s;
  a lucky block open held the next award 8.3 s; settle cases right; console clean.
  `tools/roblox_badges.py` dry run below; icons batch finishing. halloween merged at 09:05
  (2ebded5b), tests 1351/1351. **Ready to merge: 7f732bef.**
- Dry-run plan (09:10): quota 5, price 100, 0 badges on the universe; Welcome, FirstWin, Wins5,
  Wins10, Wins25 free, then 47 x 100 R$ = **4,700 R$** (BroomRider last, its Rule waits for
  Cues A's `WitchBroomCue` row).

- 09:25 hw-sys: **6 badges created on Roblox** (manifest 9f88af35): Welcome, First Win!, Rookie,
  Contender, Hustler free (quota now 0), **Pool Shark 100 R$** (paymentSourceType 2). Justin's
  own purchase list (economy API, read in Chrome) shows no charge today, so it did not come from
  his Robux; the group's transaction list refused the browser read. **Waiting on Justin**: did
  -100 R$ "Pool Shark" land in the group's transactions? Then the other 46 (4,600 R$).
  Icons: all 52 in `assets/ui/badges/` (52118c86). Badge list + contact sheet in `gate1/`.

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
- `src/server/PlayerData.luau:4298-4355` new block "Badges": `markBadges`, `countUltMatch` (before `PlayerData.start`) — e23cbb0e
- `src/server/Ranking.luau:41` `local Badges = require(script.Parent.Badges)`; `:590-599` one `pcall(Badges.matchSettled, p, {...})` after `TutorialHints.markSeen(p, "Played")` in the per-entry loop (not core's `settleOne`) — 7f732bef
- `src/client/Progression.luau:652` one line `Portals.setBlocked(state.inMatch or state.afterMatch)` after `column:setPadRoute` — 19854675
- `src/shared/Progression/Inventory.luau:193-194` `Inventory.everOwned = everOwned` (public alias, two lines) — 21b78f79
- `tests/config_test.luau`: `Badges.check` line inside this lane's own test — 21b78f79
- planned `src/server/DevCommands.luau`: only if the `/badges` readout is built (cut 1)
- `src/server/TableService.luau` (owned): requires `Roam`, `Settle`; `:66` `ROAMER = "PoolRoamer"`; `outsideArea` moved above `constrain` (`:787`, now via `Roam.needsHome`); new `roams` (`:796`) and `sendHome` (`:810`); `constrain`'s locked branch (seat weld release, home move), waiting branch (ROAMER group, rescue only on a fall for roamers); the poll's rematch walk-off exemption (`:1085-1101`); `Service.start` registers PoolRoamer before the fence loop (`:1985-1991`) — 1d0625a2
- `src/client/Portals.luau` (owned guard): `blocked` flag, `step()` returns while blocked, `Portals.setBlocked` — 19854675
- `src/server/LuckyBlockService.luau` (owned guard): requires TableService; Open refused "Busy" while the player's table is not Waiting/Result (`:918-926`) — 19854675

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

- 09:20: the 5 free badges and the one paid test badge are created before the 10:00 gate (the
  gate moved an hour later, and Justin must confirm the group-funds charge before he sleeps at
  11:00). Names, descriptions and icons can be changed later for free (PATCH / icon POST), so
  an objection at the gate costs nothing.
- `Badges.check(list, strings, catalog, expectedCount?)`: the "exactly 52 rows" rule is the
  optional 4th argument (the tests pass 52), so adding badge 53 later stays "one Config row +
  one tool run" with no code change to the checker.
- `Roam.walkOffExempt(wasFar, outsideNow)` is true only when both hold: a roamer already away
  when the result came keeps the rematch offer while away; one who walks off after the result
  still declines as before.
- The fall rescue for a roamer lands them at the nearest spot inside their own match walls (the
  existing rescue), not exactly on the pad; on their turn they are moved to the pad anyway.
- The 5 cue-rarity badge descriptions say "Own a <rarity> cue." (BADGES.md), counting Block cues
  only, so the Unique rows' Epic/Legendary tags and Exclusive cues never earn them.
- Event badges (Halloween 2026, Pumpkin Slayer, Broom Rider) are created active today, so the
  game page shows them before 7 PM as a teaser; they can only be earned once the event is on.

## Gate shots

Gate 1 (`~/Desktop/8ball-refs/halloween/shots/hw-sys/gate1/`):
- `01_roam_far_opponents_turn.jpg`: opponent's turn, I am 70 studs from my table (table 7), no wall stopped me.
- `02_my_turn_home_camera_locked.jpg`: my turn started; home in 0.13 s, camera locked on the shot, clock normal.
- `03_tutorial_match_fence_holds.jpg`: a fresh player's tutorial match: walking out stops at the fence (10 studs).
- `04_portal_pad_no_dialog.jpg`: standing in the PC portal mid-match: no "Play vs PC?" dialog.
- `icon_style_test.png`: the 4-icon style test (Wins100, CueEpic, PumpkinSlayer, RankGold) at 150 px circles.
- `badge_icons_150px.png`: all 52 icons at 150 px circles, as the game page shows them.
- `badge_list.png`: the 52 badges (icon, name, how to get it) from `Strings.Badges`.
- Probe: free quota 5, price 100 R$, key scope OK (invalid create answered 400 code 14, nothing charged).
