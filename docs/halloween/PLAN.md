# Halloween 2026 update: the shared plan every terminal follows

**Written 2026-10-28 07:00 EDT by the designer (Justin) with Claude, after a 9-agent feasibility
pass and an interview.** Every lane reads this file first, then `REQUIREMENTS.md` (the numbered
list of everything Justin asked for), then its own brief in `docs/prompts/HW_<LANE>_PROMPT.md`.
The plan page Justin reviewed: https://claude.ai/artifact/9f2FRDkuHesqL2JfWmnFfg
Research, agent reports (file:line for every code claim), mocks and approved concept art:
`~/Desktop/8ball-refs/halloween/` (`research/agents/*.md`, `mocks/v2/*.png`).

## 1. The release

- **Go-live: Wed Oct 28 2026, 7:00 PM EDT = `1793228400`** (23:00 UTC). In-game countdown from
  6:30 PM (`1793226600`). The event flips on from the server clock: no publish at 7 PM.
- **End: Tue Nov 3, 7:00 PM EST = `1793750400`** (Nov 4 00:00 UTC). Ends by itself.
- New quest board every day at **23:00 UTC** (board N opens at `1793228400 + (N-1)*86400`, 6 boards).
- **Halloween double Candy:** Oct 31 in US Eastern time, `1793419200` to `1793505600`.
- **Builds stop at 17:00 EDT.** Justin playtests 17:00–18:30 on the test place (75362358216917),
  publishes about 18:30 ("restart only outdated servers"). Only Justin publishes, ever.
- Base: branch `halloween`, cut from `gui-v4` @ 12ee4888 (it already holds the emote audio update).
  The unmerged `claude/rewards-0a7d6e` ("Match prize") branch stays OUT of this update (Justin).

## 2. Decisions Justin made (do not reopen; log anything you must change as OVERRULED)

| Topic | Decision |
|---|---|
| Length | 6 days, times above |
| Candy | Never spent. Fills the track. At the end ALL Candy (earned + bought) becomes **$10 each**, once per save, with an end screen (Candy → money arrow). Auto-end. |
| Candy rules | Real player matches only (`Settle.isReal` and money kind "Player"), paid at settle: **3 per ball pocketed, 10 per finished match, +25 for a win**. Solo, PC, short forfeits, leavers and disguised bots pay 0. Multiplier = E × (1 + 0.1·min(friends,4) + 0.1·group), E = 2 during Candy Rush (UTC minutes 0–9 of every hour) or the Halloween day, else 1, never 4. Quests, boss and packs are flat (no multiplier). |
| Quests | 4 a day, rewards 60 / 100 / 150 / 250 (560 a day). Boards are done **in order, oldest unfinished first**; old boards stay open. Draft list in §5. |
| Track | 50 → 1 ability spin · **150 → Candy Corn Cue** · 300 → $2,500 · **500 → Jack-o'-Lantern Cue** · 1,000 → 2 spins · 1,500 → $5,000 · **2,000 → Black Cat Cue** · 3,000 → 3 spins · 4,500 → $10,000 · 5,500 → 5 spins · **7,000 → Witch's Broom**. Counts Earned + Bought. |
| Playtime cue | **Spider Cue at 3 h 01 m = 10,860 s of ACTIVE event play** (idle time doesn't count; use the active clock, not `Daily.PlaySeconds`). |
| Pumpkin King | Always on a throne that replaces the piano at the end of the spawn aisle (≈ 0, 2, -86), from minute one of the event. Hold E / tap / X → "Challenge the Pumpkin King" → seated at a free lobby table vs him (bot kind **"Pc"**, so no money/rank farming; rematch "Never"). Difficulty: two ranks above the player, at least Gold (measure with `tests/bot_duel.luau`). Lose = retry at once. Win = **+50 Candy for each of the first 2 wins a UTC day** with a candy-explosion over the table, then a **personal 15:00 cooldown** shown on his prompt. Max 3 King matches per server at once; keep 2 spare tables. Badge "Pumpkin Slayer". |
| Candy pickups | Server-spawned in the lobby (a copy of MoneyRain), 1 each, ~25 an hour for an active player, **cap 40 per player per UTC hour**, teleport check, skip seated/freecam players. |
| Candy packs | 2 dev products: **500 Candy for 49 R$, 2,000 for 149 R$**. Flat, fill the whole track (yes, to the Broom), not quests. Replay-safe purchase. |
| Friend boost | **+10% per friend in your server, max 4 (+40%)**, added (never multiplied) to the other boosts. **Permanent, on money AND Candy.** If the friend check errors or is slow → 0. Own off switch. |
| Group | Money +10% is already live. Candy gets +10% too. |
| Boost display | One pill showing the summed **percentage** ("+130%") with a crown when VIP, in the row above the money pill (it REPLACES the VIP tag; VIP becomes a card line). Tap/A opens a "Your boosts" card (VIP, Group, Plus, Friends (n), Starter, Party). The Candy Rush chip sits above the pill and says **"2x CANDY 8:12"**. Invite and Plus buttons don't move. |
| Tables | 1v1 **orchid purple** cloth (185,90,230), 2v2 **charcoal** cloth (90,94,102) with glowing **orange** rails/trim, orange pad glow, pumpkin corners, 3v3 **toxic green** cloth (110,220,40). Orange cloth is banned (5/13 balls vanish). Every cloth must keep CIEDE2000 ≥ 17 from every ball under the Night lighting (`~/Desktop/8ball-refs/halloween/research/agents/cloth_contrast.py`). Haunted look = existing black frames + an attached decor kit (no collision, below the rail top, inside the body footprint). No new table mesh. |
| Night | As readable as day: a Night preset made from Sunset (sun path kept), purple atmosphere, a new purple skybox. Event cycle: Night 10 min → Sunset 5 min. Bloom unchanged. |
| Roaming | Permanent: in-match players walk anywhere while waiting; teleported back at the start of their turn; tutorial and arena keep the fence. Switch `Config.Multiplayer.Roam.Enabled`. |
| Cue preview | Permanent, reusable: a client-only 3D stage far from the lobby (stroke → trail → pocket → finisher loop, drag to rotate, Model / Trail / Finisher, Equip). Ships ON only if it passes on phone and controller. |
| Badges | **All 52 created today** from group funds (~4,700 R$, Justin approved). List: `docs/halloween/BADGES.md`. Back-paid on next join from save data; staggered 1 per 3 s; never during the tutorial or a lucky-block reel. |
| Uploads | Images, meshes, skybox and badge icons may be uploaded to the group (675425213) **without asking**. **No audio uploads** (Roblox library sounds only). No other spending except the badges above. |
| No new ability | Out of scope. |
| Tutorial | The Halloween button/popups wait until the tutorial is Done or Skipped. Candy still counts from the first match. |

## 3. The five cues (all Catalog group "Exclusive", one copy each, never tradable or sold)

| Id | Name | Effects level (`Effect`) | How | Approved concept (`~/Desktop/8ball-refs/halloween/mocks/v2/`) |
|---|---|---|---|---|
| `CandyCornCue` | Candy Corn Cue | Epic | track 150 | `C5_candy_corn.png` |
| `JackOLanternCue` | Jack-o'-Lantern Cue | Legendary | track 500 | `C4_jack.png` |
| `BlackCatCue` | Black Cat Cue | Mythic | track 2,000 | `C2c_black_cat.png` (revision 3: NO head/face, just a swaying tail at the butt; aura/trail/finisher are plain black cat silhouettes, no faces, no eyes, thin gold rim light; tough, not cute, no pink) |
| `SpiderCue` | Spider Cue | Mythic | 3 h 01 m active play | `C1b_spider.png` (huge Hela-crown blades sweeping far past the butt, black smoke aura with silver silk, webs; one small crimson hourglass; blades near the camera fold back or fade while aiming so they never block the shot) |
| `WitchBroomCue` | Witch's Broom | Secret | track 7,000 | `C3b_broom.png` (crooked, wavy natural branch handle with knots and twig stubs; straight enough at the two hand zones; violet crystal tip; straw bristles; witch-hat charm on a swaying joint) |

The id `CandyCue` already exists (the Candy Cane invite cue) and `PhantomCue` exists: never reuse
them. Every cue must beat today's best cues (Eclipse, Beta, Grand Opening): unique model and tip,
aura, trail, pocket finisher, animated parts, flipbook VFX, card art, Index entry. The tier sets
the size of the effects: Candy Corn must not flex like the Broom.

## 4. Lanes, folders, ports, owners

| Window | Lane | Folder | Branch | Rojo | Studio file | Model / effort |
|---|---|---|---|---|---|---|
| W1 | Coordinator | `~/Desktop/8ball` | `halloween` | 34872 | the Team Create place | Opus 5.5 · ultracode |
| W2 | Event core | `~/Desktop/8ball-hw-core` | `hw-core` | 34883 | `place/lane-hw-core.rbxl` | Opus 5.5 · xhigh |
| W3 | Cues A | `~/Desktop/8ball-hw-cues-a` | `hw-cues-a` | 34884 | `place/lane-hw-cues-a.rbxl` | Fable 5.1 · xhigh |
| W4 | Cues B | `~/Desktop/8ball-hw-cues-b` | `hw-cues-b` | 34885 | `place/lane-hw-cues-b.rbxl` | Fable 5.1 · xhigh |
| W5 | Map + Pumpkin King | `~/Desktop/8ball-hw-map` | `hw-map` | 34886 | `place/lane-hw-map.rbxl` | Opus 5.5 · xhigh |
| W6 | Roam + Badges | `~/Desktop/8ball-hw-sys` | `hw-sys` | 34887 | `place/lane-hw-sys.rbxl` | Opus 5.5 · xhigh |
| W7 | Boost pill + Cue preview | `~/Desktop/8ball-hw-gui` | `hw-gui` | 34888 | `place/lane-hw-gui.rbxl` | Opus 5.5 · xhigh |

What each lane owns (everything else is read-only to it; ask through your lane file's Requests):

- **Core:** `Config.Halloween`, `Strings.Halloween`, `src/shared/Halloween/*` (pure: window, rush, track, quests, candy maths), `src/server/Halloween/*` (CandyService, quests, packs grant, conversion), `src/client/Halloween/*` (event button in the right-side slot, event menu with track + quest board + Spider ring, Rush chip CONTENT, countdown banner, end screen), the `Halloween` save field, the two Candy products. The Candy settle hook in `Ranking.settleOne`.
- **Cues A:** the custom-model path (`CueStickBuilder`, `CueSkinLook`, `CuePiece`, `CueAssets`, `tools/cue_skins_data.py`, `tools/build_cue_templates.luau` ONLY-filter, `CuePreview.py` thumbnails), the 5 Catalog rows + `Strings` cue names, `CandyCornCue` and `JackOLanternCue` (skins JSON, pieces in `assets/cue/CuePiecesHalloween_A.py`, VFX, pocket pieces, card art).
- **Cues B:** `BlackCatCue`, `SpiderCue`, `WitchBroomCue` only (skins JSON, `assets/cue/CuePiecesHalloween_B.py`, VFX sprites/flipbooks, pocket pieces, card art). No runtime code edits; needs a code change → request to Cues A.
- **Map + King:** `Config.HalloweenMap` (Night preset, skybox ids, table looks by mode, decor kit, props replace-list, candy-drop spawning, King look/throne/difficulty/MaxAtOnce), `Lighting.Night`, `TableBuilder.addDecor`, event props (as `.rbxm` under `src/` or built by code), the King's body/head/cape/throne/prompt, `BossService`, the `BotService` boss hooks, `CandyDrop` (copy of MoneyRain).
- **Roam + Badges:** `Config.Multiplayer.Roam`, the roam edits in `TableService`, `Portals` and `LuckyBlockService` guards, `Config.Badges`, `Strings.Badges`, `src/shared/Progression/Badges.luau`, `src/server/Badges.luau`, the `Badges` save field, badge icons and `tools/roblox_badges.py` (creates badges through Open Cloud, writes ids back).
- **Boost pill + Preview:** `Money.boostParts` + the friends part of `Money.boost`/`Economy.boost`, the `FriendsHere` count in `Friends.luau`, `Config.UI.BoostPill`, the pill + card + the Rush chip's SHELL/position (core fills its text), the pure HUD layout function + its overlap test, `src/client/CuePreview.luau`, `Config.UI.CuePreview`, Preview buttons in My Cues / Index.
- **Coordinator:** merges, `docs/STATUS.md`/`DECISIONS.md`/`ROADMAP.md`, the Team Create place (templates, props, EventProps), device sweeps, store page (Experience Event, title, countdown icons, thumbnail), release checklist.

## 5. Interfaces (agree now, build first, merge by 08:30)

Each lane below pushes these FIRST (small commit, tests green), says so in its lane file, and the
coordinator merges them into `halloween` around 08:15–08:30. Then every lane runs
`git fetch && git merge halloween`.

- **Core → everyone:**
  - `src/shared/Halloween/Event.luau` (pure): `Event.state(now) -> "Before"|"Countdown"|"Live"|"Ended"`, `Event.isLive(now)`, `Event.rushActive(now)`, `Event.rushEndsAt(now)`, `Event.multiplier(now)` (1 or 2), `Event.boardIndex(now)`.
  - `src/server/Halloween/CandyService.luau`: `CandyService.add(player, amount, source: string, opts?) -> number` (applies the boost only when `opts.boost`), `CandyService.bossWon(player) -> {granted: boolean, amount: number, cooldownEndsAt: number}`, `CandyService.pickup(player) -> boolean` (cap check), `CandyService.isLive()`.
- **Cues A → core, B, GUI:** the 5 Catalog rows and names, with a fallback look (Classic) until each body exists, so ids are valid from the first merge.
- **GUI → core:** player attribute `FriendsHere` (number, uncapped count; core caps it) and pure `Money.boostParts(flags) -> {{kind: string, add: number}}`.
- **Map → core:** `Config.HalloweenMap.Enabled`, `.Boss.Enabled`, `.Candy.Enabled` (core swaps in fallback quests while either is off).
- **Sys → core:** `UltService.Used` signal (core subscribes; core does not edit UltService).
- Single sources: friend/group boost numbers only in `Config.Economy` (core reads them through `Money`); the pickup hour cap only in `Config.Halloween.Pickup.HourCap` (`CandyService.pickup` returns `ok, reason`).
- Until a dependency lands, code against the interface with a guarded `require`, and never ship a stub.

## 6. Quest drafts (core finalises; only hooks that exist)

1. Play 3 matches · Pocket 15 balls · Pick up 25 lobby Candy · Win 1 match
2. Win 2 matches · Pocket 30 balls · Beat the Pumpkin King · Play a 2v2 or 3v3
3. Win 3 matches · Use an ability in 3 matches · Make 5 nice shots · Pick up 50 lobby Candy
4. (Oct 31) Win 5 matches · Play 30 min today · Pocket 50 balls · Beat the Pumpkin King twice
5. Win 6 matches · Win a 2v2 or 3v3 · Pick up 100 lobby Candy · Pocket 75 balls
6. Win 8 matches · Play 45 min today · Beat the Pumpkin King 3 times · Pocket 100 balls

## 7. How every lane works

- Read `CLAUDE.md`, `docs/parallel/README.md` (its rules apply, but with these lanes, ports and
  branch `halloween` instead of `release`), this file, `REQUIREMENTS.md`, your brief, and your
  agent reports in `~/Desktop/8ball-refs/halloween/research/agents/`.
- Small verified steps: `tools/lint.sh`, `tools/test.sh`, a Studio check in YOUR window, commit,
  `git push -u origin <your branch>`, tick the Progress line, update your lane file's Status.
- **Studio:** only your window (its title has your place file name). Rojo only on your port.
  Everything the real game needs must travel with your branch (code, or `.rbxm` under `src/`, or an
  exact Request to the coordinator). Never touch the Team Create place.
- **Blender:** headless only (`/Applications/Blender.app/Contents/MacOS/Blender -b -P ...`, as the
  repo tools do). The live Blender MCP is shared by every terminal, so don't use it.
- **Devices:** check every screen you add at phone 844×390, iPad 1024×768, PC 1920×1080 and TV
  1920×1080 with controller mode (GuiQA "pad"). Resize your own Studio window with
  `tools/halloween/studio_size.sh <your place file> <width> <height>`, then read
  `workspace.CurrentCamera.ViewportSize` through MCP and adjust until it matches. Save proof
  screenshots to `~/Desktop/8ball-refs/halloween/shots/<lane>/`. If the resize helper fails
  (macOS permission), use your layout tests and say so in your lane file; the coordinator sweeps
  every device at the end.
- **Switches:** every feature has its own `Enabled` switch, default true only once verified.
- **Saves** only gain fields (template + validate + MAP_KEYS pattern, no version bump, an old-save
  test). Never wipe or migrate data destructively.
- **Shared files** (`Config.luau`, `Strings.luau`, `SaveSchema.luau`, `PlayerData.luau`,
  `Ranking.luau`, `TableService.luau`, `Main.client.luau`, `Bootstrap.server.luau`, `Progression.luau`,
  `HubCorners.luau`, `Net.luau`, `DevCommands.luau`, `UltService.luau`, `tests/save_schema_test.luau`,
  `tests/config_test.luau`, `tools/upload_manifest.json`, generated `src/shared/CueSkins/*`):
  add your own block; change existing lines only when you must, and list every such change in your
  lane file. `TableService.luau` belongs to Roam + Badges; others request.
- **Asking Justin:** until 11:00 he answers fast (`touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`, one clear
  question with a picture, stop). After 11:00 he may be asleep until about 16:30: decide yourself
  the way he would (past decisions, UI style, simple for kids), log it as an assumption in your
  lane file, and keep going.
- **Gates:** 09:00 and 11:00. Before each, put your best screenshots in
  `~/Desktop/8ball-refs/halloween/shots/<lane>/gate1|gate2/` and one line per image in your lane file.
  The coordinator shows them to Justin.
- **Cut order** is in your brief. A cut never leaves a broken or half-visible thing on screen; it
  is switched off and listed.
- **16:00:** your Progress list is done or every open line is ticked as CUT/BLOCKED with a reason.
  **17:00:** nothing new lands; only fixes the coordinator asks for.

## 8. Timeline (EDT)

| Time | What |
|---|---|
| 07:30 | Lanes start |
| 08:15–08:30 | Interfaces (§5) merged; every lane merges `halloween` |
| 09:00 | Gate 1: Candy Corn + Jack in Studio, night lighting + table colours, pill on phone size, roam working, badge list + icons drafted |
| 11:00 | Gate 2: Broom/Cat/Spider bodies, King at a table, quest board + track, badges created on Roblox |
| 08:45–16:00 | Coordinator merges on request (cues-a drop 2 ≈ 08:45, drop 3 + GUI pill ≈ 10:00–10:20, then each lane as it passes checks), sweeps devices |
| 11:00–16:00 | Lanes finish |
| 14:00 | Icon countdown starts (5H) if its test passed |
| 16:00 | Lanes done or cut; final merges |
| 17:00 | Freeze; merged build on the test place for Justin |
| 18:30 | Justin publishes; in-game countdown runs |
| 19:00 | Live; coordinator watches errors and server FPS |
