# Halloween lane W6: Roam + Badges

**Written 2026-10-28 for the Halloween build.** Lane `hw-sys`: folder `~/Desktop/8ball-hw-sys`,
branch `hw-sys` (cut from `halloween`), Rojo **34887** only, Studio window
`place/lane-hw-sys.rbxl` only, model **Opus 5.5, effort xhigh**. The shared contract is
[`docs/halloween/PLAN.md`](../halloween/PLAN.md): its decisions, numbers, lanes, ownership,
interfaces, rules and timeline beat anything here. Requirements: `docs/halloween/REQUIREMENTS.md`.
Your lane file: `docs/halloween/lanes/hw-sys.md`. You own `TableService.luau` for this build.

Launch: the coordinator starts you with `tools/halloween/lanes.sh launch`. Every launch or restart
of this lane runs exactly the line `tools/halloween/lanes.sh command hw-sys` prints (its folder,
`caffeinate`, the `hw_sys.json` Stop hook, model, effort and start prompt); never write your own
flags.

**Attended until 11:00.** The Stop hook (`tools/overnight/keep_going.sh`) sends you back to work
while the Progress list below has a `- [ ]` line. Until 11:00 EDT Justin answers fast: when you
truly need him (access, a click only he can make, a call where guessing lowers quality), run
`touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (in a worktree `.git` is a file,
so the plain `.git/overnight-waiting` fails), ask ONE clear question with a picture, and stop.
**After 11:00** he may be asleep until about 16:30: never create that file again; decide the way
he would (past decisions, UI style, simple for kids), log it under Assumptions in your lane
file, keep going. A truly blocked line becomes `- [x] BLOCKED: <why>` and you move on.

**Hard rules.** Times are EDT. Lanes stop building at **16:00**; **17:00** freeze (only fixes the
coordinator asks for). Never publish. Never touch the Team Create place ("Crazy 8 Ball" window)
or port 34872. Blender headless only (you should not need it). No audio uploads. The only Robux
you may spend: the **52 badges, about 4,700 R$ of group funds** (Justin approved, these 52 only).
Never print, log or write an API key. Scripts are files under `src/` (never through MCP).

**Shared files** (PLAN §7). The ones this lane touches: `Config.luau`, `Strings.luau`,
`SaveSchema.luau`, `PlayerData.luau`, `Ranking.luau`, `Bootstrap.server.luau`, `Progression.luau`,
`UltService.luau` (only the `Used` signal), `tests/save_schema_test.luau`, `tests/config_test.luau`,
and `DevCommands.luau` only if the `/badges` readout survives the cut. In each one, add your own
block or line, change existing lines only when you must, and list every change in your lane
file's "Shared-file changes" (file:line, commit). The coordinator resolves overlaps: core also
adds lines to SaveSchema and to both tests' key lists. `HubCorners.luau` and `Net.luau` are shared
too, but this lane has no reason to touch them. `TableService.luau` is yours; others request.

## 0. Read first

In this order, fully: `CLAUDE.md`, `docs/halloween/PLAN.md`, `docs/halloween/REQUIREMENTS.md`
(R6, R8, R0.5, R0.6, section 9), `docs/parallel/README.md` (its rules, with PLAN's lanes, ports
and branch `halloween` instead of `release`), your lane file, `docs/halloween/BADGES.md` (the 52),
`docs/ARCHITECTURE.md`, `docs/STUDIO_NOTES.md` (pad mode at :518, DevCommandsQA),
`docs/UI_STYLE.md` sections 1, 4 (tier colours) and 6 (icons: glossy cartoon, thick ink outline,
no words), `docs/GDD.md:276-283` (the fence decision you reverse).

Agent reports (file:line for every claim, gui-v4 @ 12ee4888; lines below were re-checked on
`halloween` @ 12ee4888, re-grep after every merge):
- `/Users/justinjin/Desktop/8ball-refs/halloween/research/agents/code-roam.md` (your roam design)
- `/Users/justinjin/Desktop/8ball-refs/halloween/research/agents/code-badges.md` (your badge design)
- `/Users/justinjin/Desktop/8ball-refs/halloween/research/agents/research-badges.md` (Roblox rules,
  Open Cloud create API, limits, icon rules, naming). The API spec it used is
  `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/cloud/openapi.json`
  (path `/legacy-badges/v1/universes/{universeId}/badges`); read it as data.

Code to read before editing: `src/server/TableService.luau` (:55-76, :199-228, :401-436,
:611, :731-866, :955-966, :1020-1056, :1897-1935, :2130-2175), `src/shared/Rules/MatchEngine.luau`
(:376 `shooterHeld`, :410 `beginTurn`, :424 `t.tutorial`), `src/client/Portals.luau` (:331
`step`), `src/client/Progression.luau` (:77, :645-655), `src/server/LuckyBlockService.luau`
(:908-920), `src/server/Ranking.luau` (:489-560 `settle`, :580-590 the per-entry loop),
`src/shared/Progression/Settle.luau` (:65 `botKind`, :159 `forfeitTeam`), `src/server/UltService.luau`
(:315-320), `src/server/PlayerData.luau` (:171 `Loaded`, :175 `Changed`, :814 `commit`, :1059
`handOff`, :1201 `read`, :3804 `setFlag` as a mutation pattern), `src/shared/Progression/SaveSchema.luau`
(:55-67 `STAT_KEYS`, :70-89 `MAP_KEYS`, :145 `PeakDivision`, :237 template, :1424 `fixMap`),
`src/shared/Progression/Inventory.luau` (:188-191 `everOwned`, local), `Catalog.luau` (:10-14
groups, :226-233 Unique rows, :265 `list`, :270 `get`), `Ranks.luau:294` `indexOf`,
`src/server/Social.luau` (:34 `InGroup` attribute, :58-90), `src/server/Funnel.luau:222` `event`,
`src/server/Bootstrap.server.luau:55-66`, `src/server/Leaderboards.luau:3` (Wins = `Stats.Wins`),
`tools/roblox_upload.py` (:151 `read_api_key`, :63 multipart), `tools/openai_image.py`,
`tools/export_ult_config.luau` (the Lune export pattern), `tests/save_schema_test.luau`
(:360-366 key list, :1742 old-save test), `tests/config_test.luau`.

Pictures (no concept art exists for this lane; these are icon references only):
`/Users/justinjin/Desktop/8ball/assets/ui/ranks/<tier>_1.png` and `reyes.png` (512×512 RGBA rank
emblems: reuse them on the rank badges), `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/P1_pumpkin_king.png`
(Pumpkin Slayer motif), `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/C3b_broom.png`
(Broom Rider motif), `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/MAP2_lobby.png`
(the event's purple-orange night palette for Halloween 2026).

## 1. Goal

You own **R6.1, R6.2, R6.3** (roaming) and **R8.1 to R8.13** (badges), plus your part of R0.5
and R0.6 (every device, no new bugs). Done looks like this for a player:

- **Roam.** In any lobby match (1v1, 2v2, 3v3, the Pumpkin King's table), while it is not your
  shot, you walk anywhere on the roof: no invisible walls. You can't join another pad, a
  portal pad asks nothing, a lucky block won't open, benches are fine. When your turn starts you
  are back at your table at once, camera locked, normal shot clock. Fall off the roof: you land
  back at your table. Walk away after the match: the rematch is still offered. The tutorial
  match and arena servers keep the walls. Off switch: `Config.Multiplayer.Roam.Enabled`.
- **Badges.** 52 real badges exist on the game page with clean matching icons. A new player
  gets "Welcome" and "First Win!" right after the tutorial (never during it). A veteran joining
  after the update gets every badge their save already earned, one every 3 s, never over a
  lucky-block reel. Event badges come from live hooks; Pumpkin Slayer and Halloween 2026 also
  back-pay from core's `Halloween` save field. Adding a badge later = one Config row +
  one `tools/roblox_badges.py` run.

## 2. Design

### 2.1 Roam (R6), switch `Config.Multiplayer.Roam.Enabled`

Config, inside `Config.Multiplayer` right after `Fence` (`Config.luau:8094-8107`):

```lua
	Roam = { -- in-match players walk anywhere while they wait (designer, 2026-10-28)
		Enabled = false, -- true once the roam checks in HW_SYS_PROMPT section 4 pass; false = the fence for all
		HomeExtraStuds = 2, -- a shooter this far outside the match walls at turn start goes to the pad
	},
```

Pure module `src/shared/Matchmaking/Roam.luau` (next to PadBar/PadExits; no Instances):
- `Roam.allowed(f: {enabled, arena, engineTutorial, botKind, tutorialActive, freecam}) -> boolean`:
  true only when enabled, not arena, `engineTutorial == nil`, `botKind ~= "Tutorial"`,
  `tutorialActive == false` (nil counts as tutorial), freecam not true.
- `Roam.needsHome(x, y, fx, fy, fcx, fcy, extra) -> boolean` in table studs (same maths as
  `outsideArea`).
- `Roam.walkOffExempt(wasFarAtResult: boolean, outsideNow: boolean) -> boolean`.

`TableService.luau` edits (one owner: you):
1. `:60-61`: add `local ROAMER = "PoolRoamer"`. In `Service.start` (`:1907`), register it right
   after `PARTICIPANTS` and **before** the PoolFence loop (`:1923-1929`, which then makes
   PoolFence ignore it), set ROAMER×PARTICIPANTS and ROAMER×ROAMER non-collidable; it keeps
   Default (floor, the table barrier `:175-190`). Registering before the HELD loop (`:1930`)
   makes HELD ignore it too. Four groups of Roblox's 32. Keep building the fence (arena,
   tutorial, switch-off need it).
2. A local `roams(p, t)` that feeds `Roam.allowed` from `M.Roam.Enabled`, `arena`,
   `t.engine.tutorial`, `Settle.botKind(t.engine)`, `p:GetAttribute("TutorialActive")`,
   `p:GetAttribute(Config.Freecam.Attribute)`.
3. Move `outsideArea` (`:959`) above `constrain` (`:781`) and use it for the duplicate maths at
   `:849-854`.
4. Turn start, the `locked` branch (`:826-835`): before anchoring, `local wasFree = not root.Anchored`;
   if `hum.SeatPart`, destroy its `SeatWeld` and set `hum.Sit = false` (lobby Seats are anchored,
   `MapBuilder.luau:635`; a root welded to one cannot move). After `setGroup(saved, HELD)`: if
   `wasFree and roams(p, t) and outsideArea(t, root, M.Roam.HomeExtraStuds)`, `placeRoot(t, root,
   Service.padSpot(t))` (`:731`, `:1897`), then `followStance` refines on the first aim packet.
   Log `Funnel.event(p, "RoamHome", studs, mode, Funnel.device(p))` (the `logResultChoice`
   pattern `:401`; `studs` rounded distance moved, `mode` "1v1"/"2v2"/"3v3"). This covers
   PocketChoice, AFK, mid-jump and a respawn. If the table or floor is not streamed in after a
   long move (StreamingEnabled), call `p:RequestStreamAroundAsync(pos)` in a `task.spawn`
   before the move; never yield the 10 Hz poll.
5. Waiting branch (`:843`): `setGroup(saved, if roams(p, t) then ROAMER else PARTICIPANTS)`.
   Rescue (`:849-866`): a roamer skips the "outside the fence" teleport but **keeps the fall
   rescue** (`root.Position.Y < t.placement.y - Q.FallTolerance`), so a roamer who falls off the
   roof lands at their table, not at spawn. `FallGuard.luau` stays the backup.
6. Result walk-off (`:1027-1046`): on the first Result poll of each epoch, record
   `t.farAtResult[userId] = true` for seated players already outside the area; skip the
   `WalkedOff` decline for them (`Roam.walkOffExempt`). Clear it on the next epoch. No teleport
   at Result; a Rematch brings them back through step 4.

Guards (yours):
- `src/client/Portals.luau`: new `Portals.setBlocked(on: boolean)`; `step()` (`:331`) does nothing
  while blocked (no dialog, no `PortalAsk` event). Call it from `Progression.luau` near `:651`
  with `state.inMatch or state.afterMatch` (`:77`). The server already refuses (`PortalService.luau:67`).
- `src/server/LuckyBlockService.luau` (`:908-920`): before `busy[player] = true`, refuse `"Busy"`
  for the `Open` action while `Tables.tableOf(player)` (`TableService.luau:103`) is a table whose
  phase is not `Waiting` or `Result`. Its requires never reach LuckyBlockService, so no cycle.
- Already safe, do not touch (code-roam.md lists the proofs): pads refuse seated players
  (`:1048-1053`, `:1126`, `:1226`, `:1781`), global search, solo search, freecam, lobby bots,
  menus/shop/hotbar hidden in a match, emotes, gift/sky drops, MoneyRain (distance only, works
  for roamers), shots (no distance check), the player's own table always rendered.

Edge cases to handle or note: 2v2/3v3 (a teammate's turn is waiting; only `e.shooter` is held);
the shooter may walk while balls roll (`Engine.shooterHeld`), so a potting shooter far away is
pulled home on the next turn; death during the opponent's turn = no foul, respawn on the pad
(`:2136`); leaving the server unchanged (`:2150-2175`); Look Over There! aims at a far opponent
(cosmetic, note it). Other lanes' rules you must not change but must list for the coordinator:
CandyDrop (map) skips seated players by PLAN, so roamers collect no lobby Candy; the Pumpkin
King's prompt (map) must refuse a seated player (write that as a Request to map).

Data: no baseline was pulled (code-roam.md). If it takes under 10 minutes, read the last 7 days
of `ResultChoice` and Timeout fouls with the read-only analytics key; otherwise write "missing".
After publish: `ResultChoice` "WalkedOff" drops by design, watch Timeout fouls and match
completion, and `RoamHome` per day.

### 2.2 Badges (R8)

**Registry**, a new top-level block in `Config.luau` (near the other progression blocks). One
row per line, exactly `{ Key = "<Key>", BadgeId = 0, Rule = {...} },`, so the tool's write-back
finds one match per key. Keys never change. `BadgeId = 0` = inert.

```lua
Config.Badges = {
	-- Roblox badges (designer, 2026-10-28; docs/halloween/BADGES.md). Text in Strings.Badges.
	Enabled = false, -- the award queue; true once HW_SYS_PROMPT section 4's badge checks pass
	UniverseId = 10767330648, -- awards run only in this experience; Studio and the test place log
	OwnerUserId = 544959133, -- Painicane: Met the Owner, Beat the Owner
	StaggerSeconds = 3, -- at most one award per player every 3 s (PLAN section 2)
	Budget = { Base = 40, PerPlayer = 30 }, -- badge API calls a minute per server (Roblox: 50 + 35 x players)
	DebounceSeconds = 2, -- re-check a save this long after its last change (PlayerData.read copies it)
	RevealMarginSeconds = 2, -- after the slowest pull's card (Badges.revealSeconds, about 28 s; was a flat 8 s)
	Retries = { 5, 20, 60 }, -- seconds before each retry of a failed call; then wait for the next join
	Paused = {}, -- [Key] = true: cut or misbehaving; the row never awards (a one-line publish)
	List = {
		{ Key = "Welcome", BadgeId = 0, Rule = { always = true } },
		{ Key = "FirstWin", BadgeId = 0, Rule = { stat = "Wins", atLeast = 1 } },
		-- Wins5 .. Wins1000: { stat = "Wins", atLeast = 5 / 10 / 25 / 50 / 100 / 250 / 500 / 1000 }
		-- RankBronze .. RankReyes: { peak = "Bronze" } ... { peak = "Reyes" }
		-- Streak3 / 5 / 10: { stat = "BestWinStreak", atLeast = 3 / 5 / 10 }
		-- CueRare .. CueSecret: { seenRarity = "Rare" } ... { seenRarity = "Secret" }
		-- CueUnique: { seenGroup = "Unique" }; Cues5 / 10 / 25 / 50: { seenCount = n }
		-- Balls100 / 1000 / 10000: { stat = "BallsPocketed", atLeast = n }
		-- Matches10 / 100 / 1000: { stat = "Matches", atLeast = n }
		-- Nice10 / 100: { stat = "NiceShots", atLeast = n }
		-- Money1M / 10M: { stat = "MoneyEarned", atLeast = 1000000 / 10000000 }
		-- Squad: { event = "TeamMatch" }; Ability1: { event = "UltUsed" }
		-- Ability100: { stat = "UltMatches", atLeast = 100 }; Crew: { event = "InGroup" }
		-- MetOwner: { event = "OwnerHere" }; BeatOwner: { event = "BeatOwner" }
		-- Halloween2026: { halloween = "Candy", atLeast = 1 } (core's Halloween.Earned + Bought)
		-- PumpkinSlayer: { halloween = "KingWins", atLeast = 1 } (core's Halloween.KingWins)
		-- BroomRider: { seenCue = "WitchBroomCue" }
	},
}
```

Write all 52 rows out in BADGES.md order (the comments above are shorthand for you, not for the
file). What each rule reads, so a badge never disagrees with what the player sees:

| Rule | Reads | Notes |
|---|---|---|
| `stat` | `Stats.<name>` (`SaveSchema.luau:55-67`) | `Wins` = people wins incl. the tutorial win (`Settle.recordAs`), the same number as the Wins board (`Leaderboards.luau:3`) and player list. Disguised-bot wins are `PcWins` and do not count. Check in `PlayerData.recordMatch` (`:1655`) what `Matches` counts. |
| `peak` | `PeakDivision >= Ranks.indexOf(tier, 1)` | XP never drops, so peak = highest ever; Reyes = 46. |
| `seenRarity` | a `Group == "Block"` cue of that `Rarity` ever owned | Ever owned = `Index.Seen` or held (`everOwned`; expose it as `Inventory.everOwned`, a one-line public alias). Block only, because the Unique rows' Epic/Legendary tags are economy data and the Exclusive rows are their own thing. |
| `seenGroup` | any cue of that Catalog `Group` ever owned | `Unique` = FireworkCue, BetaCue. |
| `seenCount` | distinct Catalog ids ever owned, `Group "Default"` (Classic) excluded | |
| `seenCue` | that id ever owned | BroomRider back-pays on its own when core grants the Broom. Add this row's rule after the 08:30 merge brings `WitchBroomCue` (Cues A); until then the row has no Rule (allowed only while `BadgeId == 0`). |
| `always` | true | Welcome. |
| `halloween` | core's `Halloween` save field: `"KingWins"` reads `Halloween.KingWins`, `"Candy"` reads `Halloween.Earned + Halloween.Bought` (HW_CORE §2.5 keeps these names stable) | Pumpkin Slayer `{ halloween = "KingWins", atLeast = 1 }`, Halloween 2026 `{ halloween = "Candy", atLeast = 1 }` (Candy is earned only while the event is live, so it means "played during the event"). Nil-safe: no `Halloween` field (an old save, or core not merged yet) counts as 0 and the row waits. Back-pays like any save rule. |
| `event` | never from the save; only through the server hooks below | Squad, Ability1, Crew, MetOwner, BeatOwner. |

**Text:** `Strings.Badges[Key] = { Name = "...", Description = "..." }` from BADGES.md's name and
"How to get it" column, short and kid-simple ("Win 5 matches."). Name at most 50 characters,
description at most 1000. It is also the sheet the creation tool sends to Roblox.

**Save** (additive, no version bump; the EmoteFavorites precedent of 2026-10-26):
- `Badges = {}` in `template()` after `:237`; `"Badges"` in `MAP_KEYS` after `"EmoteFavorites"`
  (`:88`); `fixMap(data.Badges, "Badges", SaveCfg.MaxBadgeEntries, onlyTrue, fixes)` after
  `:1424`; `Config.Save.MaxBadgeEntries = 500` (with a comment). Unknown keys stay, so a retired
  badge never strips anything.
- `Stats.UltMatches` (new counter in `STAT_KEYS` and the template's stats): +1 once per match in
  which the player fired at least one ability.
- `PlayerData.markBadges(player, keys)` (keys must exist in the registry; commit op
  `"markBadges"`) and `PlayerData.countUltMatch(player)` (op `"countUltMatch"`), each a new
  function block.
- The core lane adds its `Halloween` field to the same three spots in SaveSchema: land yours in
  the first interface push so the merge is trivial.

**Pure evaluator** `src/shared/Progression/Badges.luau` (no clock, no Instances; time comes in):
- `Badges.fromSave(save, list) -> { string }` keys whose save rules pass, in list order.
- `Badges.fromMatch(facts, ownerId) -> { string }` with `facts = { outcome, real, teamSize,
  opponents, forfeitTeam, userId }`: `TeamMatch` when `real and teamSize >= 2`; `BeatOwner` when
  `outcome == "Win" and real and table.find(opponents, ownerId) and forfeitTeam == nil and
  userId ~= ownerId`. `forfeitTeam ~= nil` covers his surrender, his timeouts, his team leaving
  (`EmptyTeam`) and an early-8 loss (`Settle.forfeitTeam`, `:159-176`). Bots never appear in
  `opponents` (`Economy.opponentIds`), so PC and solo can't fake it.
- `Badges.pending(keys, save, list, paused) -> { string }` minus owned (`save.Badges`), inert
  (`BadgeId == 0`) and paused rows.
- `Badges.check(list, strings, catalog) -> { string }` problems: duplicate key or id, unknown rule
  kind, stat or tier or rarity or group or cue, a `halloween` value other than `"KingWins"` or
  `"Candy"`, an `atLeast` that is not a whole number of at least 1, a missing or too-long name or description, a row
  without a Rule that has an id, more rows than `MaxBadgeEntries`, and not exactly 52 rows today.

**Server queue** `src/server/Badges.luau`, started in `Bootstrap.server.luau` next to
`Leaderboards.start` (`:65`), so it runs in lobby and arena servers. API: `Badges.start()`,
`Badges.grant(player, key, source?) -> boolean` (`event` and `halloween` rows: a live hook may
award a save-backed row before the save pass does; false when off, paused, unknown, inert or
owned), `Badges.matchSettled(player, facts)`.
- **On load** (`PlayerData.Loaded`): candidates = `pending(fromSave(PlayerData.read(p)))`, queued
  in registry order, marked `retro = true`.
- **On change** (`PlayerData.Changed(player, op)`): skip `addPlaySeconds` (every 30 s) and
  `markBadges`; trailing debounce `DebounceSeconds`; `task.defer`, never re-enter PlayerData
  inside its own event. Op `"openLuckyBlock"` sets a hold until `now + Badges.revealSeconds()` (the slowest reel and pull scene to its card, about 28 s; coordinator review 09:52).
  This one listener covers settle, cue grants (the reel included; `CueFound` misses reel finds),
  rank-ups, rewards, trades, codes and the tutorial's end.
- **Holds:** nothing is awarded until the save's `Flags.Tutorial` is `"Done"` or `"Skipped"`
  AND `TutorialActive ~= true` (PLAN: popups wait for the tutorial; 91% of players are new). Then
  Welcome, First Win! and Power Up arrive 3 s apart right after it. Also hold during a reel.
  Optional polish: hold while the player is aiming their own shot (`TableService` exposes
  `Service.isAiming(userId)`, a tiny function).
- **Queue:** one server loop that only runs while a queue is non-empty (no per-frame work),
  round-robin across players, at most one award per player every `StaggerSeconds`, a token bucket
  of `Base + PerPlayer × #players` calls a minute shared by `AwardBadgeAsync` and
  `UserHasBadgeAsync`. Player leaves → drop their queue (the next join retries).
- **Award:** `pcall(BadgeService.AwardBadgeAsync, BadgeService, userId, id)`. true → `markBadges`
  + `Funnel.event(p, "BadgeAwarded", 1, key, if retro then "Retro" else "Live")`; false →
  `UserHasBadgeAsync`, mark only if true; error → retry after 5 / 20 / 60 s, then drop for this
  session. A teleport mid-award (`handOff`) is fine: the next server gets false, then has = true,
  and marks.
- **Where it may call Roblox:** only when `not RunService:IsStudio() and game.GameId ==
  UniverseId`. Studio and the test place (GameId 10769973956) run the same queue, stagger and
  holds but print `[8ball] Badges: would award <Key> to <Name> (retro|live)` and do not mark the
  save. So Justin's 17:00 playtest on the test place shows logs, not toasts; real toasts are
  checked on the live game after publish (write that in your handoff).
- **Studio-only QA hook** `ServerStorage.BadgesQA` (BindableFunction, created only in Studio):
  `"veteran"` pushes a synthetic veteran save through the queue, `"settle", facts` runs the match
  rules, `"state"` returns the queues and holds. The pattern is `DevCommandsQA`.
- Never let a badge error reach a match: every hook call is in its own `pcall`.

**Event hooks** (one line each, in pcall):
- `Ranking.luau`, the per-entry loop (`:580-590`, next to `TutorialHints.markSeen(p, "Played")`):
  `Badges.matchSettled(p, { outcome = entry.outcome, real = m.real, teamSize = e.teamSize,
  opponents = entry.opponents, forfeitTeam = forfeitTeam, userId = p.UserId })`. Squad and
  Beat the Owner. This is not core's Candy hook in `settleOne`; keep them apart.
- `UltService.luau:319` success branch: fire a new `UltService.Used` signal `(player, tableId,
  epoch)`: a module-level `BindableEvent`, exposed as `UltService.Used = usedEvent.Event` (the
  `PlayerData.Loaded` pattern, `PlayerData.luau:171`), fired next to
  `Funnel.spins(player, "UsedInMatch")`. This lane adds the signal and it is the only
  `UltService.luau` edit of the build (PLAN §5). Your listener grants `Ability1` and calls
  `countUltMatch` once per `(tableId, epoch)`. Core's quest "Use an ability in 3 matches"
  subscribes to the same signal through a guarded require and makes no edit of its own in
  UltService (write it as a Request to core).
- `OwnerHere`: when Painicane joins, grant every other player in the server; when anyone joins
  a server he is in, grant them.
- `InGroup`: the `InGroup` attribute (`Social.luau:34`, set after load) true now or when it turns
  true.
- Halloween 2026: no hook and no timer. Its `{ halloween = "Candy", atLeast = 1 }` rule awards it
  through the Changed listener after core's first Candy commit, and back-pays a save that
  already has Candy.
- Pumpkin Slayer: the map lane's `BossService` calls `Badges.grant(p, "PumpkinSlayer", "Boss")` on a
  King win (guarded require + pcall, Request to map), the instant path. Its
  `{ halloween = "KingWins", atLeast = 1 }` rule back-pays and catches a missed call.

**Edge cases:** "Restart Servers for Updates" makes every veteran rejoin at once with 15-30
badges each: the stagger and budget handle it, anyone leaving early gets the rest next join.
`PlayerData.read` deep-copies the save, so never read it outside the debounce. Painicane never
gets Beat the Owner. A moderated or renamed badge keeps its Key.

### 2.3 Badge icons

52 PNGs, `assets/ui/badges/<Key>.png`, 512×512 RGBA, made by a new `tools/gen_badge_icons.py`
(Pillow + `tools/openai_image.py --size 1024x1024 --background transparent --quality high`,
downscaled). Roblox crops to a circle: keep everything important inside a 460 px circle. One
consistent style: the game's glossy cartoon look (UI_STYLE §1, §6: chunky shapes, thick ink
outline `#1B2033`, a shine and a small drop lip), one shared round frame drawn in Pillow, one
ring colour per family. No words; a bold numeral on milestone badges is allowed if it reads at
150 px.

Families: Welcome (rooftop + 8 ball, purple), Wins (trophy; ring bronze → silver → gold →
prismatic as the number grows), Ranks (the existing emblem `assets/ui/ranks/<tier>_1.png` /
`reyes.png` composited on the frame: no generation), Streaks (flame), Cue rarity (cue + 8 ball
in the tier colours of UI_STYLE §4: Rare `#3B9BFF`, Epic `#A259FF`, Legendary `#F2B200`, Mythic
prismatic on `#1A1446`, Secret `#1E1820` with `#FF283C` glitch, Unique `#FF5CB8`), Collection
(a cue rack), Balls (ball dropping into a pocket), Matches (a table), Nice shots (a star burst),
Money (a stack of green cash, never coins), Abilities (a lightning bolt), Owner (a crown), Crew
(group shield), Halloween (pumpkin on the purple night, the King's crowned pumpkin, the broom).
Style-test 4 icons first (one per look), then batch the rest in the background while you code.
Contact sheet at 150 px circle crop (how the game page shows them) for gate 1. Log the spend.

### 2.4 `tools/roblox_badges.py` (creates badges, writes ids back)

- Rows come from `lune run tools/export_badges.luau` (JSON: key, name, description, badgeId,
  icon path; the export pattern of `tools/export_ult_config.luau`), so Config and Strings stay
  the single source.
- Key: Keychain `ROBLOX_USER_KEY` (Painicane's user key: Creator Hub offers the legacy badge
  scopes only on user keys; `ROBLOX_API_KEY` is the group key and has no badge scopes), read
  like `read_api_key()` in `tools/roblox_upload.py` with that service name
  (`security find-generic-password -s ROBLOX_USER_KEY -w`); `python3
  tools/halloween/key_scopes.py ROBLOX_USER_KEY` shows its scopes. Sent only as the `x-api-key` header; never print headers, the key or a raw request.
- `--probe` (write and run it first, at Progress 1, within the first 30 minutes: create
  `tools/roblox_badges.py` with just `read_api_key` and this flag; the rest of the tool comes at
  Progress 9): GET
  `https://badges.roblox.com/v1/universes/10767330648/free-badges-quota` (no auth; expect 5) and
  `https://badges.roblox.com/v1/badges/metadata` (expect `badgeCreationPrice` 100), then one
  deliberately invalid create (empty name, `paymentSourceType=0`): a 400 (code 14 or 16) means the
  key and scope work and nothing was charged; 401, or 403 code 0 or 12, means the scope is
  missing. Then write in the lane file exactly: "the API key needs scope
  `legacy-universe.badge:manage-and-spend-robux` on universe 10767330648, and its owner needs the
  group's spend-funds permission", create the waiting file, ask, stop.
- Default is a dry run: it prints the plan (key, name, cost, running total) and spends nothing.
- `--create`: first lists the universe's existing badges
  (`https://badges.roblox.com/v1/universes/10767330648/badges?limit=100&sortOrder=Asc`, paginated)
  and the manifest `tools/badges_manifest.json`, and skips any key already created (by manifest
  or exact name), so a re-run after a crash never pays twice. Then per row with `BadgeId == 0`:
  `expectedCost = 0` while the quota lasts, else the metadata price; refuse any cost above 100
  and any running total above `--max-spend 4700`. POST
  `https://apis.roblox.com/legacy-badges/v1/universes/10767330648/badges`, multipart: `name`,
  `description`, `paymentSourceType=2` (group funds: an inference from the spec's field order,
  see the money check below), `expectedCost`, `isActive=true`, `files` = the PNG. 1 s between
  calls (limit 100 a minute). Write the manifest entry (id, iconImageId, cost, time) right after
  each 200, before the next call.
- Errors: 18 (cost changed) → re-read quota and price, stop. 17 (funds) or 16 (payment source)
  → stop and ask. 6 (text moderated) → record, skip, continue; pick a kid-safe new name, log it.
  401/403 0/12 → the scope message above. 429 → wait 60 s and retry.
- `--write-config`: replaces `Key = "<Key>", BadgeId = 0,` with the id in
  `src/shared/Config.luau`, requires exactly one match per key, then `tools/format.sh` on that
  file. `--self-test`: offline checks of the cost guard, the duplicate skip and the write-back on
  a temp copy.

**The money check (protects Justin's own Robux).** Create the 5 free badges, then exactly ONE
paid badge, then ask Justin (waiting file, before 11:00) to confirm the 100 R$ left the group's
funds (Creator Hub → the group → Transactions) and not his own balance. Only then create the
other 46. If `paymentSourceType=2` turns out to be user funds, stop and ask; never "fix" it by
guessing. If the free quota is below 5 (someone created badges today), the total would pass
4,700: create up to 4,700 R$ and leave the lowest-value rows inert (Matches1000, Balls10000,
Money10M, Nice100, Cues50, in that order), listed in the lane file; they ship later at 5 free a
day. Names, descriptions and icons can be edited later for free (PATCH
`/legacy-badges/v1/badges/{id}`, icon POST `/legacy-publish/v1/badges/{id}/icon`), so do not hold
creation for polish.

### 2.5 Docs for the coordinator (you do not edit GDD or DECISIONS)

Write these into your lane file's Requests, ready to paste:
- `docs/GDD.md:279-281`, replacing "Players in a match stay by their table: ... (designer,
  2026-09-26)": "Players in a match walk anywhere while they wait for their turn; when their
  turn starts the server puts them back on their table's pad, and a fall lands them at their
  table. While seated they cannot join another pad, use a portal or open a lucky block. The
  tutorial match and arena servers keep the invisible walls (designer, 2026-10-28; switch
  `Config.Multiplayer.Roam.Enabled`)."
- DECISIONS: "2026-10-28 (designer): roaming in matches, reversing 2026-09-26 'stay by your
  table'." and "2026-10-28 (designer): 52 Roblox badges created from group funds; rules are
  Config.Badges rows, back-paid from saves, 1 per 3 s, held in the tutorial and lucky-block reels."
- A badges section for the GDD (what exists, how to add one: a Config row, a Strings entry, an
  icon, `tools/roblox_badges.py --create --only <Key>`, then `--write-config`).

## 3. Interfaces

**Deliver first, pushed by 08:15** (small commits, lint and tests green, "pushed" in your lane
file Status), so the coordinator merges them at 08:15-08:30 (PLAN §5):
1. `Config.Multiplayer.Roam` (Enabled false), `Config.Badges` (Enabled false, all 52 rows inert),
   `Strings.Badges`, the `Badges` save field + `Stats.UltMatches` + `Config.Save.MaxBadgeEntries`
   with the old-save test. This lands your SaveSchema lines before core's `Halloween` field.
2. `src/server/Badges.luau` with its real public API (`start`, `grant`, `matchSettled`) that does
   nothing while `Config.Badges.Enabled` is false (the switched-off behaviour, not a stub), the
   Bootstrap start line, and the `UltService.Used` signal. Map can then code
   `Badges.grant(p, "PumpkinSlayer", "Boss")` and core can subscribe to `UltService.Used`.
3. TableService is yours: at every merge read every lane file's Requests
   (`docs/halloween/lanes/*.md`) for TableService needs (the King's seating uses the existing
   `freeTable` `:1838` / `placeOnPad` `:1758`, so probably none) and build them as small blocks
   the same hour.

**You consume, always behind a guarded require or a nil check:** core's `Halloween` save field
(`KingWins`, `Earned`, `Bought`) for the two `halloween` rules (missing → 0, the rows wait);
Cues A's `WitchBroomCue` Catalog row (valid from the first merge, with a Classic look);
map's `Badges.grant` call for Pumpkin Slayer (missing → the `KingWins` rule still awards it,
nothing breaks). After 08:30: `git fetch && git merge halloween`. Later merges: the coordinator
merges on request from 08:45; say "ready to merge" with the commit in your lane file's Status.

## 4. Checks

- **Lune** (`tools/test.sh`): `tests/roam_test.luau` (`allowed` false when off, in the arena, in
  the engine tutorial, against a Tutorial bot, with TutorialActive true or nil, in freecam;
  `needsHome` false on the pad and within walls + extra, true two tables away; for every table and
  team size `padSpot` is inside `matchWalls` and clear of the table barrier; the walk-off truth
  table). `tests/badges_test.luau` (empty save → Welcome only; a veteran save → the exact keys in
  order; Reyes = 46; Block-only rarity; Unique group; Classic excluded from counts; Seen or held;
  UltMatches; the Beat the Owner truth table: win + real + owner + no forfeit → yes; his surrender,
  timeouts, EmptyTeam, early 8 → no; PC or solo → no; the owner himself → no; the `halloween`
  rules: no `Halloween` field → neither, `KingWins = 1` → Pumpkin Slayer, `Earned = 0, Bought = 2`
  → Halloween 2026; `check` catches each bad row, `halloween = "Wins"` and `atLeast = 0` included;
  exactly 52 rows). `tests/config_test.luau` (your own lines: `Roam.Enabled` boolean, `Badges.check`
  returns nothing, StaggerSeconds 3). `tests/save_schema_test.luau` (your own `"Badges"` line in
  the key list `:360-366`, where core adds `"Halloween"`; an old save with no `Badges` and no
  `UltMatches` loads clean with no notes, bad entries dropped, the 500 cap). Both test files are
  shared (PLAN §7): list your lines in the lane file. `python3 tools/roblox_badges.py --self-test`.
- **Lint** `tools/lint.sh` green; `tools/format.sh` only on files you changed.
- **Studio, your window only** (list the studios, pick the one titled `lane-hw-sys.rbxl`, Rojo
  34887 connected). Roam, with `Roam.Enabled = true` locally: (1) a lobby 1v1 vs PC (`/bot`
  through `ServerStorage.DevCommandsQA`): walk across the roof in the bot's turn; on your turn you
  are at the table within about 0.1 s, camera locked, clock normal; (2) sit on a bench while
  waiting: on your turn the bench does not move; (3) jump off the roof: you land at your table;
  reset: on the pad, no foul; (4) another table's pad: not seated; a portal pad: no dialog; a
  landed lucky block: Open refused; (5) a money rain mid-match far from the table pays; (6) far
  away when the match ends: Rematch still offered, pressing it brings you back on your turn;
  (7) 2v2 (bots fill, or a Studio multi-client test if MCP can run one; otherwise say so): roam in
  your teammate's turn, home on yours; (8) fresh player: the tutorial match keeps its fence; (9)
  `StudioArena`: fence holds; (10) switch off: today's behaviour. Badges: join logs Welcome only
  after the tutorial is Done or Skipped; `/tutorial reset` then play it: nothing during, then
  Welcome, First Win!, Power Up 3 s apart; `BadgesQA "veteran"`: 20+ keys at 1 per 3 s, budget
  never exceeded; open a lucky block: nothing for 8 s; `BadgesQA "settle"` cases; console clean.
- **Devices.** You add no screens, but roaming and the turn-start move must work by touch, mouse
  and pad: `tools/halloween/studio_size.sh lane-hw-sys.rbxl <w> <h>`, then read
  `workspace.CurrentCamera.ViewportSize` through MCP until it reads phone 844×390, iPad 1024×768,
  PC 1920×1080 and TV 1920×1080 with `PlayerScripts.GuiQA:Invoke("padMode", true)` (walk with
  `("pad", "Thumbstick1", "Change", x, y)`). At each: walk far, get pulled home, aim and shoot.
  If the helper fails (macOS permission), use the tests, say so in the lane file; the coordinator
  sweeps at the end.
- **Fresh-player run** (you touch join, the tutorial, the first match, saves and popups): fresh
  Studio save (`/tutorial reset` per STUDIO_NOTES), join, tutorial or skip, the first match after
  it (roaming on), the lobby popups unchanged, no badge log during the tutorial, console clean.
- **Screenshots** to `/Users/justinjin/Desktop/8ball-refs/halloween/shots/hw-sys/` (gate sets in
  `gate1/` and `gate2/`), one line per image in your lane file.

## 5. Cut order

Drop from the top when time runs short. A cut is switched off and listed, never half-visible.
1. The "hold while aiming" polish and any `/badges` readout.
2. `MetOwner` → `Paused`.
3. `Ability100` and the `UltMatches` counter → `Paused` (the field may stay, harmless).
4. `Squad` and `Ability1` hooks → `Paused`.
5. Generated icons for the low-value families → create those badges with Roblox's default icon
   and upload the real icon later through the icon endpoint.
6. Roam failing a check at 14:00 → `Roam.Enabled = false` (the fence as today); the guards stay.
7. The queue not verified by 15:00 → `Badges.Enabled = false`; the badges stay created and ship
   later with a Config-only publish.

Never cut: the tutorial and arena fence, the fall rescue, the seat-weld release, the save
validation, the no-award guard outside the live experience, the spend guard.

## 6. Gates

- **09:00, gate 1** (`shots/hw-sys/gate1/`): roam far across the roof in the bot's turn; back at
  the table on your turn, camera locked; the tutorial fence holding; the `RoamHome` log line. The
  badge list (52 names, rendered from `Strings.Badges`), the icon contact sheet at 150 px circle
  crop, the probe result (quota, price, scope OK or the exact missing scope). Unless Justin objects
  to a name or icon, start creating at once after the gate.
- **11:00, gate 2** (`shots/hw-sys/gate2/`): the 52 badges on Roblox (the universe's public badge
  list rendered as a sheet, or a Creator Hub screenshot), ids in Config (commit hash), the spend
  from the manifest and Justin's group-funds confirmation, the queue's Studio log (stagger, holds),
  roam guards (portal no dialog, lucky block refused, bench stays), the fall rescue.

## Progress

- [x] 1. Interface push 1 (by 08:15): `Config.Multiplayer.Roam` (off), `Config.Badges` with 52 inert rows, `Strings.Badges`, the `Badges` save field + `Stats.UltMatches` + `Config.Save.MaxBadgeEntries` + old-save test; first, write `tools/roblox_badges.py` with only `read_api_key` and `--probe`, and run the probe (section 2.4; a missing scope goes to Justin now).
- [x] 2. Interface push 2 (by 08:15): `src/server/Badges.luau` public API honouring the switch, the Bootstrap line, the `UltService.Used` signal (this lane adds it; the build's only UltService edit); lane file Status says both pushed; Requests to map (grant call, King prompt refuses seated players) and core (subscribe to `UltService.Used` through a guarded require, no UltService edit of its own; keep `Halloween.KingWins`, `Earned`, `Bought` names stable); every shared-file line listed in the lane file.
- [x] 3. Icons: 4-icon style test, then the batch of 52 in the background (`tools/gen_badge_icons.py`, `assets/ui/badges/`), contact sheet.
- [x] 4. `src/shared/Matchmaking/Roam.luau` + `tests/roam_test.luau`.
- [x] 5. TableService roam: PoolRoamer group, `roams`, `outsideArea` moved up, waiting branch, fall rescue kept, turn-start seat-weld release + home move, `RoamHome` event.
- [x] 6. Guards: `Portals.setBlocked` + the Progression call; LuckyBlockService `Busy` during a match.
- [x] 7. First Studio roam pass (checks 1, 3, 4, 8) and gate 1 shots; merge `halloween` after 08:30.
- [x] 8. Gate 1 (09:00): shots in `gate1/`, one line each in the lane file.
- [x] 9. `tools/export_badges.luau` + the rest of `tools/roblox_badges.py` around the step-1 probe (dry run, duplicate skip, manifest, cost guard, write-back, `--self-test`); dry-run plan in the lane file.
- [x] 10. Create the 5 free badges and ONE paid one; Justin confirms group funds (waiting file); create the other 46; `--write-config`; manifest + ids committed (by 10:45).
- [ ] 11. Gate 2 (11:00): shots in `gate2/`, one line each in the lane file.
- [x] 12. Pure `src/shared/Progression/Badges.luau` + `tests/badges_test.luau` + config_test and save_schema_test lines; `Inventory.everOwned`; the `halloween` rule kind (Pumpkin Slayer, Halloween 2026) and its tests; the BroomRider rule after the Cues A merge.
- [x] 13. Server queue in `src/server/Badges.luau`: load pass, Changed debounce, holds (tutorial, reel), budget, stagger, award/has/retry, Studio and test-place logging, `BadgeAwarded`, `BadgesQA`.
- [x] 14. Hooks: Ranking settle (Squad, BeatOwner), `UltService.Used` (Ability1, `countUltMatch`), OwnerHere, InGroup, PumpkinSlayer grant (map's call; the `KingWins` rule back-pays).
- [x] 15. Result walk-off exemption; roam checks 2, 5, 6, 7, 9, 10; `Roam.Enabled = true` once all pass.
- [x] 16. Badge Studio checks (tutorial hold, veteran stagger and budget, reel hold, settle cases, console clean); `Badges.Enabled = true` once they pass.
- [x] 17. Fresh-player run with both switches on (join, tutorial or skip, first match, popups).
- [ ] 18. Devices: phone, iPad, PC, TV + pad mode for roaming and the turn-start move; screenshots.
- [ ] 19. Lane file Requests: the GDD and DECISIONS text (section 2.5), the live checks for Justin (a Welcome toast on join, a veteran's back-pay, Creator Hub award counts), every shared-file change listed.
- [ ] 20. Lane file Status final + all screenshots.
- [ ] 21. Merge `halloween`, re-test (lint, tests, the Studio roam and badge paths), push.

## Notes
