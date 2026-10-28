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

- 09:58 hw-core: **READY again @HEAD** with two more: the one-time **Halloween funnel** (03d441be; `Steps.Funnels.Halloween` = 1_Button, 2_Opened, 3_FirstCandy, 4_Cue150, 5_Cue500, 6_Cue2000, 7_Broom; `Config.Tutorial.Funnel.Once.Halloween = "FunnelHw"`; the Candy steps log on reaching each cue's Candy, so a held cue does not hide them) and the **Candy packs** (9e53700c, switch on bc3c2f28): products MADE on Roblox and for sale: Candy500 = 3723285204 (49 R$), Candy2000 = 3723285208 (149 R$). A receipt adds the Candy flat to `Halloween.Bought` and grants the steps it reaches in the same `applyPurchase` commit; sold only while `Packs.Enabled` and Live (Buy check + receiptCheck "Closed"; a receipt outside pays `Shop.fallbackMoney`); the pack window reads the Halloween clock in Store. Studio: StoreQA grant Candy500 twice with one id -> +500 once; Candy2000 -> Bought 2,500, steps 5-6 given; after `/hw time end` a receipt -> "Closed; paid as $19600"; HwPack/HwCandy Pack/funnel steps logged. **Every switch is now true** (Match, Quests, Spider, Packs, Convert, Rush). Note for Justin: Roblox reports every product at ~80% of its Config price in Studio (Pack4 199 -> 160, StarterPack 29 -> 24, Candy500 49 -> 40); the menu shows that live price like the shop does.
- 09:55 hw-core: **READY to merge `hw-core` @HEAD** (merged halloween @dbf92e52 at e13efabf; lint OK, 1,421 tests; Studio main path clean): the tile, the event menu, art, quests ON, the Spider clock (Spider ON, held until `Catalog.ready`), the Candy toast + NEW CUE! card, RushChip (seen live in hw-gui's shell: "2x CANDY 9:25" over the boost pill), the countdown 18:30-19:00 + the 19:00 start message (the tile waits 6 s for it), the end screen (M5) and its conversion tests. Your 09:52 review: all six fixed (40560507 tile built last + `task.defer` + blurPad; a74251bb HwMenu Open once a save, refused claim no commit, band by MoneyPerCandy; b29a5b16 no grants once Converted; ceb3094e SaveSchema comment). Studio: `/hw time countdown` -> pill "HALLOWEEN EVENT IN 0:55" -> at 19:00 "THE HALLOWEEN EVENT HAS STARTED!" 6 s -> tile pops in with NEW; `/hw time end` -> 4 finished quests claimed, 1,800 Candy -> $18,000, end screen when quiet, COLLECT flies the cash, `EndSeen` saved. Packs: still building (side worktree), not in this READY.
- 09:46 hw-core: **RushChip READY** for hw-gui (226ddead): `require(StarterPlayerScripts.Client.Halloween.RushChip).content() -> { text = "2x CANDY 8:12", endsAt, kind = "Rush"|"Double" }?`, nil before HwOn or outside a Rush/Oct 31; it reads the event clock itself (Studio's offset counts), any `now` you pass is ignored. Candy toast + NEW CUE! card in (4c45a7ad): "+57" chip (purple "2x" tag) flies to the tile, or out of the CLAIM into the menu's Candy pill; a match's chip waits for a quiet lobby; spins/money track prizes fly through `Progression.flyReward`; a cue step or the Spider shows a NEW CUE! card (thumb, name, tier tag, note, OK; pad B/Esc closes; auto-closes 8 s) when quiet and the tutorial's invite card is closed, in its own ScreenGui at DisplayOrder 45 (over the tutorial's 40). Studio: chip centre -> tile in ~1 s, CLAIM chip +60 into the pill, card OK closes, console clean. Packs are being built in a side worktree (no Studio).
- 09:50 hw-core: Spider active clock in (8d501aac): `SkyDropService.isActive(player)` (one getter, the Sky clock's IdleSeconds rule), a 5 s tick in CandyService adding active seconds while Live (Spider + "Play N min" quests), the view re-sent for active time alone every 30 s. `Spider.Enabled = true` (76b0df32): Studio walked 10,855 -> 10,870 s, the Spider due and HELD because `Catalog.ready("SpiderCue")` is false until cues-b builds it; it grants on the next tick after. Quests and Track lines ticked. Next: Candy toast + track reveal, then RushChip.content.
- 09:36 hw-core: merged halloween @f246f0a7 (Badges/HalloweenMapFx conflicts kept both); lint OK, 1,396 tests. Coordinator's 09:12 requests done: `Event.nextRushAt` returns nil with no Rush to come (5ef20d06; the strip says "No more Rushes this event"), `Event.clock/short` read `Strings.Halloween.Time`, distinct Alts (board 2 King -> Matches 4, board 3 Ult -> Matches 5, dacaaf55; a test checks no board shows a quest twice under any hook mix), solo practice ults ignored (b0ed8e2e). Main.client untouched (client_compiles_test passes). Quests are ON (`Quests.Enabled = true`, fda219c9, incl. the `Quests.claimable` infinite-loop fix that would have hung the end conversion). Event menu committed (f6b25a41, fit fix 76ac2339); art uploaded to the group (afb239f8). Studio: CLAIM 950 -> 1,010 Candy, the 1,000 step (2 spins) given, HwQuest/HwMenu/HwCandy/HwTrack logged, console clean. Next: the Spider active clock + Active quests, then the toast and reveal.
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
- 09:52 coordinator: **merged interface 2 at 7f01d27b** into `halloween` (not later: the tile, menu, art and quests are not marked READY yet). Review of a8cd46a0 and on, please fix before you mark the next READY:
  1. `EventButton.new`'s first `refresh()` runs inside `HubCorners.new` before `self.fresh` is set (HubCorners.luau ~305): when `HwOn` is already true during Live, `layout()` throws "iterate over a nil value" (~707) on many joins and kills the 1 s loop. Build the tile after `self.fresh`, or `task.defer` the first refresh.
  2. `HubCorners` `blurPad`'s list lacks `self.eventTile.button`: after Side/B the tile stays selected and A presses it instead of jumping. Add it as gui did for the pill.
  3. CandyService ~471: `{ seen = true }` logs `HwMenu Open` before the `hwMark` check (a client can log ~240 events a minute and eat the analytics budget); a refused claim still runs a full `hwMutate` commit. Log Open only when `hwMark` changed something; no commit on a refused claim.
  4. PlayerData ~3542: `hwConvert` says no more track prizes, but any later `hwMutate` (endSeen, a refused claim) still runs `hwGrantDue`, so post-end grants depend on what the client sends. Either grant due steps inside `hwConvert` before paying, or skip `hwGrantDue` once `Converted`.
  5. CandyService ~425: the HwConvert band uses `// 10`; use `Config.Halloween.Convert.MoneyPerCandy`.
  6. SaveSchema: `freshHalloween` sits under `template()`'s doc comment; move it above its own function.
- 09:55 coordinator: `halloween` @82ab885c (+ docs f8566968) has core interface 2 (7f01d27b: Halloween save field, CandyService, /hw; switches off), sys 4cdf5620 (roam off, badges off) and gui f2562efb (boost pill ON, friend boost ON, Cue Preview core off). Lint OK, 1,404 tests, Studio play console clean, pill shows +120%. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare: hooks stay inside `do ... end`.
- 09:53 coordinator: your `finished` request is in the contract test (`halloween` after dbf92e52): 7 balls finished won = 56, lost = 31, forfeit side = 21 (balls only), multiplier 2 x (1 + 0.4 + 0.1) = 3, friends capped at 4; `CandyMath.finished(true) == 0`, `(false|nil) == 1` runs once that function is merged (skips until then, fails from 12:00).

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
- `tests/save_schema_test.luau`, `tests/config_test.luau`: core's own cases only (sys and map add theirs; merged with sys's Badges at 7e838a11).
- `Config.UI.Menu.LivelyMenus`: `"Halloween"` added last (f6b25a41).
- `Progression.luau` (client): `Halloween.State.start()` after `SettingsState.start()` (0ba8e9f1) and `Halloween.EventMenu.new(screen, deps)` after `DailyRewardsMenu.new` (f6b25a41).
- `HubCorners.luau`: `EventButton` require, `self.eventTile` after the offer rays, its `layout` call in `layout()`, first `padStops` entry (a8cd46a0).
- `Net.luau`: `Halloween = "RemoteEvent"` before map's `HalloweenMapFx` (0ba8e9f1).
- `Ranking.luau`: the `CandyService` require and one guarded `matchSettled` call after the disguised count (12a60faa).
- `Progression.luau` (client): `Halloween.CandyToast.new(screen, deps)` after the EventMenu line (4c45a7ad), `Halloween.Countdown.new(screen)` (34a50947) and `Halloween.EndScreen.start(screen)` (82f9e69a) after it.
- `HubCorners.luau`: the tile now built last in `new` (before `refreshPlus`), `self.eventTile.button` in `blurPad`'s list after gui's boost pill (40560507, e13efabf).
- `Tutorial/Steps.luau`: `Steps.Funnels.Halloween` (03d441be); `Config.Tutorial.Funnel.Once.Halloween = "FunnelHw"` (03d441be).
- Packs (9e53700c): `Progression/Shop.luau` (`candy` in Grant/GrantFields/ProductRow, `Shop.packsOpen`, receiptCheck "Closed" for a Candy row, grantFor sets `candy`), `Progression/ShopView.luau` (Buy check "Closed" outside the window, `hwNow` in the context), `Store.luau` (Candy rows read `Halloween/Clock.serverNow()` for the receipt and the Buy context), `PlayerData.luau` (`grant.candy` validated; in `applyPurchase` the Candy + `hwGrantDue` before `Shop.markGrant`/commit; `PlayerData.HwPack` signal; `PlayerData.hwCandy` getter 03d441be), `Net.luau` (one doc line for `{ pack = key }`), `Config.Products.List` two rows + the Shop header count, `tools/products_spec.json`, `tools/products_ids.json`.
- `SkyDropService.luau`: one getter `SkyDropService.isActive(player)` before `start` (8d501aac).
- `tools/upload_manifest.json`: 10 rows for `assets/ui/halloween/*.png` (afb239f8).

## Requests

- Coordinator: mirror `finished` (HW_CORE 2.6: 1 unless the player's side forfeited a real match; the winner of a real forfeit gets 10 + 25) in the Candy contract test.
- hw-sys: core consumes `UltService.Used (player, tableId, epoch)` and makes no UltService edit; the rule kind `{ halloween = "KingWins" | "Candy", atLeast = n }` for PumpkinSlayer and Halloween2026 reads `Halloween.KingWins` and `Halloween.Earned + Halloween.Bought`.
- hw-gui: core reads friends and group only through `Money.friendBoost` / `Money.boostParts` (guarded fallback to the same `Config.Economy` keys), so `Config.Halloween` has no friend switch and `FriendBoostEnabled` turns the friend part off for money and Candy together. Core's event tile is the first `padStops` entry; the pill goes right after Plus. Core's track cards call `CuePreview.open(id, { from = "Track", note = ... })` through a guarded require when `CuePreview.enabled()`. The Candy icon is `Config.Halloween.CandyIcon`.
- hw-map: the Alts read `HM.Enabled and HM.Boss.Enabled` and `HM.Enabled and HM.Candy.Enabled`; `CandyService.pickup` returns `(ok, reason)` with `"Cap"|"NotLive"|"NotLoaded"|nil` (show the bag-full note only on `"Cap"`; the cap is only `Config.Halloween.Pickup.HourCap`); `CandyService.bossCooldown(player) -> number` (unix time, 0 if none); the Candy icon is `Config.Halloween.CandyIcon`.
- hw-cues-a: core grants and shows a track cue only when `Catalog.ready(id)` is true and retries held grants on load and every tick.
- hw-gui (optional, small): the Robux thank-you for a Candy pack says only "Thank you!" (`Store.tellPurchase` sends no candy field; `Purchased.itemText` falls back). If you want "+500 Candy" there, core can add `candy` to the told payload; say so.
- Coordinator: phone 844x390 (and iPad) shots of the tile and the event menu in your device sweep, please. This lane cannot resize its Studio window (`studio_size.sh`: System Events sees 0 windows for every RobloxStudio process from this shell; no scriptable device emulator). PC shots are in gate1/ and gate2/.

## Assumptions

- OVERRULED (PLAN §6, for Justin): the pickup quests are 15 / 30 / 50 lobby Candy instead of 25 / 50 / 100. Pickups only come in the lobby at about 25 an hour for an active player (capped at 40), so 100 would take up to 4 hours of lobby time; 15 / 30 / 50 take about 35 min / 1 h 10 min / 2 h.
- OVERRULED (PLAN §6, for Justin): "Play 30 min today" and "Play 45 min today" count ACTIVE minutes (the Spider's idle-gated clock, `SkyDropService.isActive`) while that board is the one routed to, not wall-clock minutes in a calendar day, so standing idle does not finish them and they follow the oldest-unfinished-first order like every other quest.

## Gate shots

- gate1/tile_pc_under_offer.jpg: PC (Studio 1920x1026), event Live by `/hw time live`, tutorial skipped: the HALLOWEEN tile (pumpkin art, "ENDS IN 6d 0h" pill, NEW badge) right under the Starter Pack offer's price, clear of the Players list. The "Invite a friend?" card in the middle is the game's own join popup.
- gate1/tile_pc_no_offer.jpg: the same after the offer's X: the tile moves up into the Daily Challenge's spot.
- Phone size: no shot. `tools/halloween/studio_size.sh` cannot see Studio's windows from this shell (System Events lists 0 windows for every RobloxStudio process; it needs Accessibility for the shell). Phone, iPad and PC placements are proven by `tests/halloween_layout_test.luau` (844x390 and 1024x768 with 36/58 px insets, offer shown and hidden: touch puts the tile above the offer, clear of the jump button; a computer puts it below). Please include the tile in the device sweep.
- gate2/menu_pc_before_claim.jpg: PC, the event menu on REAL data (`/hw candy 950`, `/hw quest done`, `/hw active 4300`): Candy pill, ENDS IN pill, the 11-step track (gifts, money, the cue cards from the approved concept art; steps 50-500 reached with gold frames and checks), the DAY 1-6 quest tabs with unlock times, four quests with CLAIM, the Spider panel (1h 11m / 3h 01m on a bar), the Rush strip ("2x CANDY starts in 44:49"). Body scrolls to the 4th quest at this window height.
- gate2/menu_pc_after_claim_step.jpg: after CLAIM on "Win 1 match": +60 Candy (950 -> 1,010), the row says CLAIMED, the 1,000 step (2 SPINS) turns gold with a check; the server gave the spins (save `Given` 1, 3, 5; the two cue steps are held until cues-a's `Catalog.ready`).
- gate2/newcue_card_pc.jpg: the NEW CUE! card a cue step (or the Spider) shows once the lobby is quiet (here the Spider's; the thumbnail is the Classic stand-in until cues-b's Spider is ready, and a real card only shows for a ready cue).
- gate2/countdown_pc.jpg: 18:59 (`/hw time countdown`): the Ink pill "HALLOWEEN EVENT IN 0:53" at the top middle under Roblox's bar, no tile yet.
- gate2/started_pc.jpg: 19:00 sharp: "THE HALLOWEEN EVENT HAS STARTED!" in gold with a burst; 6 s later the pill goes and the tile pops in with NEW.
- gate2/rush_chip_and_tile_pc.jpg: in a Rush: hw-gui's chip shell showing core's `RushChip.content()` "2x CANDY 9:25" over their boost pill; the tile under the offer.
- gate2/end_screen_pc.jpg: the end screen (M5) preview with three owned event cues (Classic stand-in thumbnails until the cue lanes' are ready): ribbon, 1,240 CANDY -> $12,400 counting up, the note, YOURS FOREVER cards, COLLECT. The real path was walked too (`/hw time end`: $18,000, no cues owned, so no card row).
- gate2/menu_pc_get_candy.jpg: the menu with the packs on: GET CANDY "500 Candy (R)40" / "2,000 Candy (R)120" (Roblox's live price, see the 09:58 note), the Spider panel "0m / 3h 01m, Only active play counts", the quests with their Candy chips.
- Phone 844x390: no shot from this lane (see Requests); the menu's phone layout is the one scrolling column with the track scrolling sideways.
