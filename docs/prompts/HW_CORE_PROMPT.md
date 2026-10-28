# Halloween lane W2: Event core (Candy, quests, track, packs, the end)

**Written 2026-10-28 07:20 EDT by the coordinator with Claude, from the shared plan.** Lane
`hw-core`: folder `~/Desktop/8ball-hw-core`, branch `hw-core` (cut from `halloween`), Rojo port
**34883** only, Studio window `place/lane-hw-core.rbxl` only, **Opus 5.5 at xhigh**. Start: the
coordinator launches it with `tools/halloween/lanes.sh launch`; every launch or restart line is
the command printed by `tools/halloween/lanes.sh command hw-core` (never write your own flags).
Contract: [`docs/halloween/PLAN.md`](../halloween/PLAN.md) (decisions, numbers, lanes, owners,
interfaces, timeline). Requirements: [`docs/halloween/REQUIREMENTS.md`](../halloween/REQUIREMENTS.md).
Your lane file: [`docs/halloween/lanes/hw-core.md`](../halloween/lanes/hw-core.md). Times are EDT.

**Attended until 11:00, then unattended.** The Progress list at the end is the source of truth;
the Stop hook sends you back to work while any `- [ ]` line remains. Until 11:00 Justin answers
fast: when you truly need him (a call where guessing lowers the quality, a click only he can
make), run `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (in this worktree
`.git` is a file, so plain `touch .git/overnight-waiting` fails), ask ONE clear question with a
picture, and stop.
**After 11:00 never ask and never touch that file**: he may be asleep until about 16:30. Decide
the way he would (PLAN §2, past decisions, `docs/UI_STYLE.md`, simple for kids), write the call
in your lane file's Assumptions, keep going.

**Hard rules.** Lanes stop building at **16:00** (17:00 freeze; after that only fixes the
coordinator asks for). Never publish. Never touch the Team Create place or another lane's
Studio window or Rojo port. Blender only headless (`/Applications/Blender.app/Contents/MacOS/Blender -b -P ...`),
never the Blender MCP. Scripts only under `src/` through Rojo. Every number in `Config`, every
word in `Strings`. Saves only gain fields. Images may be uploaded to group 675425213 without
asking (`tools/roblox_upload.py --group-id 675425213`); no audio uploads; the two Candy
products may be created without asking (`tools/roblox_products.py`); no other spending. Never
print or write an API key.

## 0. Read first

In this order: `CLAUDE.md`, `docs/halloween/PLAN.md` (whole), `docs/halloween/REQUIREMENTS.md`
(whole), `docs/parallel/README.md` (its rules apply with PLAN §4's lanes and ports and branch
`halloween` instead of `release`), your lane file, `docs/ARCHITECTURE.md`, `docs/UI_STYLE.md`,
`.claude/skills/lively-gui/SKILL.md` plus `motion.md`, `verification.md` and `pitfalls.md` next
to it (every screen you build follows it), `docs/ECONOMY.md` §2-3 (pace and payouts),
`docs/STUDIO_NOTES.md` when Studio, Rojo or Lune misbehave.

Agent reports (file:line for every claim; spot-checked 07:15 on `halloween` @ 12ee4888):
- `~/Desktop/8ball-refs/halloween/research/agents/economy-candy.md`: the Candy model, track
  reach (Broom ≈ 560 owners, Spider ≈ 3,600), inflation, packs. Its StartsAt/EndsAt and its
  Oct 31 *UTC* window are stale: **PLAN's times win**.
- `.../code-hud-boosts.md`: the right-side slot (`ChallengeOn`), HUD sizes, LuckClover as a
  template, pad stops, products table, the Rush chip's place.
- `.../code-badges.md`: the additive save-field pattern (EmoteFavorites precedent), hooks
  (`PlayerData.Changed`, settle loop, UltService), the tutorial counts as a real match.
- `.../code-bot-map.md`: `BotService.matchEnded`, the boss path (map lane builds it and calls
  your `CandyService.bossWon`), MoneyRain (map lane's CandyDrop calls your `CandyService.pickup`).
- `.../candy_sim.py`, `.../reach.py`: re-run when you change a quest or track number.

Mocks (layout and mood only; their numbers and cue names are OLD, PLAN's win):
- `~/Desktop/8ball-refs/halloween/mocks/M4_quest_board.png`: the event menu. Orange-to-purple
  dripping header "HALLOWEEN EVENT" with a jack-o'-lantern, "ENDS IN 5d 23h" pill, red X. Row 1:
  a Candy pill (candy-corn icon + "1,240") and the track bar with cue cards over it (reached =
  gold frame + green check) and small purple gift boxes between, the last node a big gold
  "GRAND PRIZE" card. Left: QUESTS with DAY 1..6 tabs (future ones greyed with a lock and
  "Unlocks in 13:22:10"), four rows: icon, text, orange progress bar, "7/10", a yellow
  "+100" Candy chip or a green CLAIM button. Right: a purple "PLAY 3.1 HOURS" panel with the
  cue's card and a ring "1h 12m / 3h 06m". Bottom: a purple night strip with "2x CANDY starts
  in 2:14:05". Copy the layout, the chips, the CLAIM button, the locks; replace Phantom with
  the **Spider Cue**, "3.1 HOURS" with **"PLAY 3H 01M"**, "Witching hour" with **"CANDY RUSH"**,
  the track with PLAN's 11 steps.
- `~/Desktop/8ball-refs/halloween/mocks/M5_conversion.png`: the end screen. Purple ribbon "THE
  HALLOWEEN EVENT HAS ENDED!" with pumpkins; a candy pile, a fat orange arrow, a cash stack;
  "1,240 CANDY" → "$12,400" pills; "Your leftover candy was turned into money. Thanks for
  playing!"; the event cues the player owns as cards marked "YOURS FOREVER"; a big green
  COLLECT. Copy all of it (the cues shown are the player's own, up to five).
- `~/Desktop/8ball-refs/halloween/mocks/v2/H1_boost_hud.png`: the HUD around you: the right
  side's Daily Challenge target (off today) with the Starter Pack tile under it, the GUI lane's
  "2x CANDY 07:42" chip bottom-left. Your event tile goes in that right-side slot.
- Cue art for cards (approved concepts, until the cue lanes' thumbnails land):
  `~/Desktop/8ball-refs/halloween/mocks/v2/C5_candy_corn.png`, `C4_jack.png`,
  `C2c_black_cat.png`, `C1b_spider.png`, `C3b_broom.png`.

## 1. Goal

You own these rows of `REQUIREMENTS.md`: **R1.1** (fixed end), **R1.2** (Candy + quests),
**R1.3** (the cues come only from the event; every grant path closes at the end), **R1.4**
(Candy → $10 each, once per save, the end screen with the arrow, auto-end), **R1.5** (the two
packs), **R1.6** (countdown from 18:30, everything on at 19:00 by the server clock), **R1.8**
(the Halloween button on the right side), **R1.10** (the Rush chip's CONTENT; GUI owns its
shell), **R1.11** (track gifts), **R2.6** (Spider at 3 h 01 m of active play), **R2.7** and
**R2.8** (the track's order and the 7,000 Broom), **R3.5** (pickups: your cap and pay; the map
lane spawns them), **R4.4** (the King's +50 Candy; the explosion is the map lane's), **R5.1**
and **R5.4** for Candy (friends +10% each max 4, group +10%).

Done, in player terms: a player who finished or skipped the tutorial sees, at 18:30, "HALLOWEEN
EVENT IN 29:59" at the top; at 19:00 it says the event has started and a pumpkin HALLOWEEN tile
pops in on the right with a NEW badge. Every real match against people pays Candy at the
result ("+57", "2x" in a Candy Rush or on Oct 31). The tile opens the event menu: their Candy,
the track to the Witch's Broom with cues and gifts, today's quest board (older boards still
open), the Spider ring of active play, the Rush clock, two Candy packs. Crossing a track step
gives its prize at once with a small reveal. Quests are claimed with a bouncing CLAIM. On Nov 3
at 19:00 EST it all stops; their Candy turns into money ($10 each) with the end screen, once,
whenever they next play. New players in the tutorial see none of it (their Candy still counts).

Numbers this should move (CLAUDE.md "data-driven"; baseline Oct 25-26): DAU 24,887, 91% new,
23.1 min per DAU, D1 13%, D7 3-4%, payers 3.5% of DAU. Measured after release by the custom
events in §2.9 and Creator Hub retention for Oct 29-Nov 4 against Oct 19-25. R2.7's target:
≥ 100 Broom owners by the end (count `HwTrack` at 7000).

## 2. Design

### 2.1 Files (new unless marked)

| File | What |
|---|---|
| `src/shared/Halloween/Event.luau` | **pure**, the interface (2.2): state, Rush, double day, multiplier, boards, chip text |
| `src/shared/Halloween/Clock.luau` | `Clock.now()`: `workspace:GetServerTimeNow()` plus the test offset (2.3) |
| `src/shared/Halloween/CandyMath.luau` | **pure**: match Candy, the boost sum and its percent |
| `src/shared/Halloween/Track.luau` | **pure**: steps due for a total and a given-set, next step, Spider due |
| `src/shared/Halloween/Quests.luau` | **pure**: board list with alts, routing an event to boards, done/claimable |
| `src/server/Halloween/CandyService.luau` | the interface API (2.4), settle hook, tick, remote, attributes, conversion |
| `src/client/Halloween/State.luau` | the client's copy of the view, `changed` signal, `HwOn` |
| `src/client/Halloween/EventButton.luau` | the right-side tile (spec in HubCorners) |
| `src/client/Halloween/EventMenu.luau` (+ `MenuTrack`, `MenuQuests`, `MenuSpider`, `MenuPacks` as needed) | the lively menu |
| `src/client/Halloween/RushChip.luau` | the chip's content for the GUI lane's shell |
| `src/client/Halloween/Countdown.luau` | the 18:30-19:00 banner and the 19:00 start moment |
| `src/client/Halloween/EndScreen.luau` | the M5 screen |
| `src/client/Halloween/CandyToast.luau` | "+57" chips and the track-step reveal |
| `tests/halloween_event_test.luau`, `halloween_candy_test.luau`, `halloween_track_test.luau`, `halloween_quests_test.luau` | Lune |

Shared or unowned files you touch, each as an additive block or line, every touch listed in your
lane file's "Shared-file changes": `Config.luau`, `Strings.luau`, `SaveSchema.luau`,
`PlayerData.luau`, `Ranking.luau`, `Net.luau`, `Bootstrap.server.luau`, client `Progression.luau`,
`HubCorners.luau`, `Shop.luau` (shared/Progression), `SkyDropService.luau` (one getter),
`DevCommands.luau` (one block), `tools/products_spec.json`, `tools/products_ids.json`,
`tests/save_schema_test.luau`, `tests/config_test.luau`. You make **no edit in `UltService.luau`**
(you subscribe to hw-sys's `UltService.Used`, 2.7). PLAN §7's shared list includes
`HubCorners.luau`, `Net.luau`, `DevCommands.luau`, `tests/save_schema_test.luau` and
`tests/config_test.luau`: other lanes add their own blocks there too, so add only yours, list it,
and let the coordinator resolve overlaps at merge. Nobody else owns Shop or SkyDropService; touch
only what is named here. Known neighbours: hw-sys adds the `Badges` save field at the same three
SaveSchema spots, the `UltService.Used` signal and its own `save_schema_test`/`config_test`
cases; GUI owns `Money.luau`, `Friends.luau`, the pill (its `HubCorners.padStops` entry right
after Plus, `blurPad`, `padFocusedOn`) and a comment line in `Net.luau`; map owns `BossService`,
`CandyDrop`, `Config.HalloweenMap`, its own `Net` remotes, `/king` in `DevCommands` and its
`config_test` cases.

### 2.2 `Event.luau` (pure, the interface; deliver first)

`now` is unix seconds; nothing reads a clock. All times from `Config.Halloween`.
- `Event.state(now) -> "Before"|"Countdown"|"Live"|"Ended"` (Countdown from `CountdownAt`,
  Live from `StartsAt`, Ended from `EndsAt`; `"Before"` also when `Enabled` is false).
- `Event.isLive(now)`; `Event.endsIn(now) -> number` (seconds, ≥ 0).
- `Event.rushActive(now)`: Live and `(now // 60) % 60 < Rush.Minutes`; `Event.rushEndsAt(now) -> number?`
  (end of the Rush in progress, else nil); `Event.nextRushAt(now) -> number` (next start).
- `Event.doubleDay(now)`: Live and `Double.From <= now < Double.To` (Oct 31 US Eastern).
- `Event.multiplier(now) -> 1|2`: `EventMultiplier` when rushActive or doubleDay, else 1, 1 when
  not Live. Never 4.
- `Event.boardIndex(now) -> number`: 0 before StartsAt, else `min(Boards, 1 + (now - StartsAt) // BoardSeconds)`;
  `Event.boardOpensAt(n) -> number`.
- `Event.rushChip(now) -> { text: string, endsAt: number }?`: on the double day
  `"2x CANDY 9:12:44"` (to `Double.To`), in a Rush `"2x CANDY 8:12"` (mm:ss), else nil
  (formats in `Strings.Halloween.Chip`).
Tests: every boundary second (18:29:59, 18:30:00, 19:00:00, a Rush's 9:59 and 10:00, Oct 31
00:00 EDT both sides, board 6, EndsAt both sides), no 4x, the chip strings.

### 2.3 `Clock.luau` and test time

`Clock.now()` = `workspace:GetServerTimeNow()` + `workspace:GetAttribute("HwTimeOffset")`, the
attribute honoured only in Studio or when `game.GameId == Config.Save.TestPlace.GameId`
(Config.luau:1725). **On the test place the server sets the offset at boot so the event is Live**
(Justin playtests there 17:00-18:30, before the real 19:00); `/hw time` changes it. Live game:
the attribute is ignored. Every lane gates on `Event.*(Clock.now())`; say so in the lane file.
Server-side `now` for saves and caps is `os.time()` plus the same offset (`Clock.serverNow()`).

### 2.4 `CandyService` (server; the interface; deliver first, real, no stub)

Started from `Bootstrap.server.luau` in lobby AND arena servers (settle runs in both; the
`isLobby` flag only gates UI pushes that need the lobby).
- `CandyService.add(player, amount, source: string, opts?) -> number`: whole amount ≥ 1, only
  while Live and the save is loaded; `opts.boost` applies `CandyMath.multiplier` (2.6); adds to
  `Earned`, routes nothing else; returns what was added (0 when refused). Sources: `Match`,
  `Quest`, `Boss`, `Pickup`, `Dev`.
- `CandyService.bossWon(player) -> { granted: boolean, amount: number, cooldownEndsAt: number }`:
  Live only; every win counts toward King quests and `KingWins`; the first
  `Boss.PaidWinsPerDay` (2) wins of the UTC day pay `Boss.Candy` (50) flat; every win starts
  `Boss.CooldownSeconds` (900) personal cooldown stored in the save (`KingReadyAt`).
- `CandyService.bossCooldown(player) -> number`: `KingReadyAt` as unix time (0 when none or
  already past); map's King prompt reads it (HW_MAP:348). Part of the interface push.
- `CandyService.pickup(player) -> (ok: boolean, reason: "Cap"|"NotLive"|"NotLoaded"|nil)`:
  `false, "NotLive"` outside Live, `false, "NotLoaded"` before the save loads, `false, "Cap"` at
  `Pickup.HourCap` (40) for this UTC hour (`PickHour`/`PickCount` in the save, so a server hop
  doesn't reset it); else `true, nil`, +1 flat, +1 to pickup quests. Map shows its "bag full"
  note only for `"Cap"`. **The hour cap lives only in `Config.Halloween.Pickup.HourCap` and only
  this function enforces it** (map's `HalloweenMap.Candy.CapPerHour` is pacing only).
- `CandyService.isLive() -> boolean`.
Each grant is ONE PlayerData mutation (2.5) so Candy, track prizes, cues and marks land in one
commit. Everything you add runs in `pcall` at its call site; an error never blocks a settle,
a purchase or a boss result.

### 2.5 Save field `Halloween` and PlayerData mutations

Additive, no version bump (the EmoteFavorites pattern, code-badges §4): template entry after
`EmoteFavorites` (SaveSchema.luau:237), `"Halloween"` in `MAP_KEYS` (:70-89), a
`fixHalloween(data.Halloween, fixes)` after :1424, plus an old-shape load test in
`tests/save_schema_test.luau`. Shape (string keys only):

```lua
Halloween = {
	Earned = 0, Bought = 0, -- Candy from play / from packs; never spent; the track counts both
	Active = 0, -- seconds of active play while Live (the Spider ring)
	Given = {}, -- ["1".."11"] = true: track steps granted
	Spider = false,
	Q = {}, -- ["<board>.<slot>"] = progress (whole)
	Claimed = {}, -- ["<board>.<slot>"] = true
	KingDay = 0, KingPaid = 0, KingWins = 0, KingReadyAt = 0,
	PickHour = 0, PickCount = 0,
	Seen = false, -- opened the menu once (the NEW badge)
	Converted = false, ConvertedMoney = 0, ConvertedAt = 0, EndSeen = false,
}
```
Validate: integers clamped (`StatCap`, `UnixTimeCap`), booleans, `Given`/`Claimed` with
`onlyTrue`, `Q` whole numbers; unknown keys kept. New mutations in one PlayerData block, each a
single `commit`: `hwAddCandy(player, amount, bucket)` (adds to `Earned` or `Bought`, then
grants every newly due track step: cue via `giveReward({cues})` only if not owned and
`Catalog.ready(id)` is true (Cues A, HW_CUES_A:184; `Catalog.get` is non-nil for all five from
drop 1, before the cues are built, so never key on it), else hold it ungiven and retry it on
load and on every tick (2.8); spins via `{spins}`; money via
`{money}` flat, reason `"Halloween"`), `hwActive(player, seconds)` (Spider grant at 10,860),
`hwQuest(player, kind, amount)` (routing, 2.7), `hwClaim(player, key)` (flat Candy + due
steps), `hwBoss(player, now)` and `hwPickup(player, now)` (cap or cooldown, Candy, quest and
due steps together), `hwSeen`, `hwEndSeen`, `hwConvert(player)` (2.10). Expose read-only
`PlayerData.halloween(player)` (a copy). The badges lane back-pays PumpkinSlayer and
Halloween2026 from this field through its rule kind `{ halloween = "KingWins" | "Candy", atLeast = n }`
(hw-sys adds it; `"KingWins"` reads `KingWins`, `"Candy"` reads `Earned + Bought`): keep these
names stable.

### 2.6 Match Candy at settle

`CandyMath.match({ balls, finished, won, farmBalls, farmBonus }) = 3·balls·farmBalls + 10·finished·farmBonus + 25·won·farmBonus`
(`Match.PerBall` / `Finished` / `Win`), then `× multiplier`, `Money.round`.
**`finished`** (0 or 1, PLAN "10 per finished match"): 1 when the match settled real and the
player's side did not forfeit (`entry.forfeited ~= true`): a win, loss or draw played out, and
the winning side of a real forfeit (a surrender, running out of timeouts, or the other side
emptying after the one-minute mark) gets the 10 and the 25. The side that forfeited a real match
gets `finished = 0` (it keeps its 3 a ball; `won` is 0). Short forfeits are not real and pay
nothing. Log this reading in Assumptions; `halloween_candy_test` has a case for each, and the
coordinator's contract test mirrors it (your Request).
`multiplier = Event.multiplier(now) × (1 + friendsAdd + groupAdd)`. **Both numbers live only in
`Config.Economy`** (PLAN §5 single sources) and you read them through Money: `friendsAdd =
Money.friendBoost(friends)` (GUI lane: `FriendBoost` 0.1 a friend, at most
`FriendBoostMaxFriends` 4, 0 while `FriendBoostEnabled` is false, so one switch turns the friend
part off for money and Candy together); `groupAdd` = the `"Group"` part's `add` in
`Money.boostParts({ group = true })` (the existing `Config.Economy.GroupBoost`, 0.1) when the
player is in the group, else 0. Guarded fallback (Money's new functions missing before GUI's
interface merges, or a call erroring, in `pcall`): friends = `if E.FriendBoostEnabled == true
then E.FriendBoost * math.min(math.floor(friends), E.FriendBoostMaxFriends) else 0` (0 when a
key is missing), group = `E.GroupBoost or 0`. No friend or group number in `Config.Halloween`.
friends = `tonumber(player:GetAttribute("FriendsHere")) or 0`, at least 0 (GUI lane's attribute,
uncapped; missing, an error or a slow check = 0), group = `player:GetAttribute("InGroup") == true`.
Hook: one `pcall(CandyService.matchSettled, p, facts)` in `Ranking.settleOne`
(Ranking.luau:371) **right after the disguised count (:444-447)**, i.e. after the
`if not real then countShort ... return end` at :439, before the lucky block. Facts:
`balls = Economy.tally(m.key, p.UserId).balls` and `.nice`, `won`, `outcome`, `real`,
`forfeited = entry.forfeited` (for `finished`),
`payKind` (:417), `botKind = Settle.botKind(m.e)`, `teamSize = m.e.teamSize`, `farm = entry.farm`
(`Balls`, `Bonus`; Money.luau:100), `matchKey = m.key`. Pays only when `real` and
`payKind == "Player"` and `botKind ~= "Disguised"` (the tutorial bot, kind `"Tutorial"`, counts:
PLAN "Candy still counts from the first match"). Solo, PC, short forfeits (not real), the
leaver (`Ranking.departed` never reaches settleOne) and disguised bots pay 0 and send **no
"+0" toast** (a visible 0 would out the disguised bot). Draws pay the 10. Teammates each get
their own tally (the team's balls). The multiplier is read at settle time. Quest events from
the same facts: `Matches`, `Wins`, `Balls`, `NiceShots`, `TeamMatches`/`TeamWins` (teamSize ≥ 2),
`UltMatches` (2.7). Only Candy-paying matches count for quests.

### 2.7 Quests (6 boards, flat 60/100/150/250)

Boards open at `Event.boardOpensAt(n)` (19:00 EDT Oct 28-31, 18:00 EST Nov 1-2). **Routing
(your design reading of "in order, oldest unfinished first"):** every event counts once, toward
the oldest open board whose quest of that kind is unfinished; an amount (balls, seconds) fills
that quest and the rest flows to the next open board's quest of the same kind. So a late joiner
can't clear several boards with one win, and a hard quest (the King) never blocks later boards'
other quests. Log this in Assumptions. Claimed one by one (CLAIM), flat, into `Earned` (fills
the track). Unclaimed finished quests are claimed automatically at conversion.

Finalise from PLAN §6 with only hooks that exist; order each board's four easiest → hardest by
expected minutes (6.3 min a match, 50% wins, about 5.75 balls a match, the nice-shot rate from
a few Studio-store saves or `Stats.NiceShots / Stats.Matches`) and give 60/100/150/250 in that
order. Pickup quests are cut to fit about 25 pickups an hour (PLAN's 25/50/100 would take up to
4 h): **15 / 30 / 50**. This changes PLAN §6, so it is pre-logged as **OVERRULED** in your lane
file's Assumptions for Justin (keep that line true if you retune). Starting set:

| Board | Quests |
|---|---|
| 1 Wed | Play 3 matches · Pocket 15 balls · Win 1 match · Pick up 15 lobby Candy |
| 2 Thu | Win 2 matches · Pocket 30 balls · Beat the Pumpkin King · Play a 2v2 or 3v3 |
| 3 Fri | Win 3 matches · Use an ability in 3 matches · Make 5 nice shots · Pick up 30 lobby Candy |
| 4 Sat (opens Halloween night) | Win 5 matches · Play 30 min · Pocket 50 balls · Beat the Pumpkin King twice |
| 5 Sun | Win 6 matches · Win a 2v2 or 3v3 · Pick up 50 lobby Candy · Pocket 75 balls |
| 6 Mon | Win 8 matches · Play 45 min · Beat the Pumpkin King 3 times · Pocket 100 balls |

Each row is data (`{ Kind, Need, Icon, Alt = { Kind, Need } }`). The Alt replaces the quest
while its hook is off (`HM = Config.HalloweenMap`, map's keys, HW_MAP:446-448; a missing table
or key counts as off): King quests → `Wins` (1 → 2, 2 → 3, 3 → 4) unless
`HM.Enabled and HM.Boss.Enabled`; pickups → `Balls` (×2) unless `HM.Enabled and HM.Candy.Enabled`;
abilities → `Wins 3` while `UltService.Used` is missing. "Play N min" = active seconds (2.8,
idle time doesn't count) while that board is the one routed to, not wall-clock minutes "today"
(PLAN §6's wording): also pre-logged as **OVERRULED** in your lane file's Assumptions. Ability
hook: **no edit in `UltService.luau`**. hw-sys adds a `UltService.Used` signal fired in its
success branch with `(player, tableId, epoch)` (HW_SYS:289-291); at CandyService start,
subscribe through a guarded require (`pcall(require, ...)`, then `UltService.Used` present and
connectable, else the Alt) and remember the player's `"<tableId>:<epoch>"`; settle counts
`UltMatches` once when that equals the match key (`Economy.matchKey`, `"%d:%d"` of id and
epoch). Write it in Requests as consumed from hw-sys.

### 2.8 Track, gifts and the Spider ring

`Config.Halloween.Track.Steps` (Earned + Bought): 50 → 1 spin · **150 → `CandyCornCue`** ·
300 → $2,500 · **500 → `JackOLanternCue`** · 1,000 → 2 spins · 1,500 → $5,000 ·
**2,000 → `BlackCatCue`** · 3,000 → 3 spins · 4,500 → $10,000 · 5,500 → 5 spins ·
**7,000 → `WitchBroomCue`**. Granted automatically the moment the total crosses (never a
claim, so nobody loses a prize), each once (`Given`), cues one copy (skip if owned; still marks
given). Spider: `SpiderCue` at **10,860 s** of active play while Live, any server. Active
clock: add a read-only getter to `SkyDropService.luau` (it already tracks `lastActive` per
player from the client's input pings, :77-85, :131-139): `SkyDropService.isActive(player) -> boolean`
(`now - lastActive <= Config.SkyBlock.IdleSeconds`); your 5 s tick adds 5 s for each active
player (`hwActive`). Not `Daily.PlaySeconds` (not idle-gated). The cue ids come from Cues A's
Catalog rows (with a Classic fallback look). **Grant a track cue (and the Spider) only when
`Catalog.ready(id)` is true**: `Catalog.get` is non-nil for all five from Cues A's drop 1, while
an unbuilt or cut cue is hidden in the Index and drawn as Classic, so a grant keyed on `get`
would hand out a broken cue with a NEW CUE card. Until it is ready the step stays ungiven (its
other prizes are unaffected) and every held grant is retried on load and on every 5 s tick, so
it lands the moment the cue's drop merges. `Catalog.ready` itself missing (Cues A's interface not
merged) = not ready.

### 2.9 Analytics (Funnel.event, Funnel.luau:222; Funnel.once :140)

`HwCandy` (value = amount; a = source; b = `"x1"`/`"x2"`; c = `Funnel.device`), `HwMatch` (value =
friends capped; a = `Paid`/`Disguised`/`PC`/`Short`/`Solo`; b = group yes/no: measures the
friend share nobody logs today), `HwQuest` (value = board; a = quest key; b = `Done`/`Claimed`),
`HwTrack` (value = step's Candy; a = prize), `HwSpider`, `HwPack` (value = Robux; a = key),
`HwConvert` (value = money; a = Candy band), `HwMenu` (a = `Open`/`PackPrompt`/`Claim`); funnel
`Funnel.once(p, "Halloween", ...)`: `1_Button`, `2_Opened`, `3_FirstCandy`, `4_Cue150`,
`5_Cue500`, `6_Cue2000`, `7_Broom`. Never per shot.

### 2.10 Packs and conversion

Packs: rows in `tools/products_spec.json` (`Candy500` "500 Halloween Candy" 49 R$, `Candy2000`
"2,000 Halloween Candy" 149 R$; description: counts toward every prize including the Witch's
Broom, leftover Candy becomes $10 each at the end), create with `tools/roblox_products.py --only Candy500,Candy2000`
(dry run first), ids into `Config.Products.List` (Config.luau:3946+) as
`{ Kind = "Product", Id = ..., Robux = 49, Candy = 500 }`. Replay-safe through the existing
receipt path: add `candy: number?` to `Shop.Grant` (Shop.luau:49), set it in `Shop.grantFor`
(:558) from `row.Candy`; in `Shop.receiptCheck` (:468) return `"Closed"` outside Live (the
receipt then pays `Shop.fallbackMoney`, as every closed offer does); add `candy` to PlayerData's
`GRANT_FIELDS` and, inside `PlayerData.applyPurchase` (:3555) after `Shop.recordPurchase`, add
`grant.candy` to `Halloween.Bought` and grant newly due track steps in the same commit. Flat:
no Rush, double day, friends or group; not quests. Test with `StoreQA("grant", uid, "Candy500", "id1")`
twice with the same id (Store.luau:1182): Candy once. The menu sells them through the shop's
existing Buy request. Switch `Packs.Enabled`.

Conversion (`Convert.Enabled`, `MoneyPerCandy = 10`): once per save, when `now >= EndsAt`, on
load and on the tick for online players, in lobby or arena: one commit that claims finished
unclaimed quests, then adds `(Earned + Bought) × 10` with reason `"HalloweenCandy"`, sets
`Converted`, `ConvertedMoney`, `ConvertedAt`. Zero Candy: mark converted, no screen. Keep this
code after the event: a save first seen in December still converts. Earning, quests, packs,
the King's Candy and the Spider clock all stop at `EndsAt`.

### 2.11 Client: tutorial gate, button, menu, chip, banner, end screen

- **Gate:** the server sets player attributes `Candy` (Earned + Bought) and `HwOn` (save loaded,
  `Halloween.Enabled`, tutorial flag `"Done"` or `"Skipped"`; `TutorialService` STEP_FLAG
  `"Tutorial"`, Steps.luau:186-188). Nothing Halloween shows on screen unless `HwOn`. Pushes
  of the full view on the `Halloween` remote (new in `Net.luau`; client → server only
  `{ claim = key }`, `{ seen = true }`, `{ endSeen = true }`, throttled), at most one a player
  every 2 s.
- **Event tile (R1.8):** a new tile spec in `HubCorners.luau` (do NOT flip `ChallengeOn`,
  Config.luau:16430): pumpkin-with-candy icon (OpenAI art, 256 px), word `HALLOWEEN`, a small
  "ends in 5d 23h" pill, a red "!" when a claim waits or a new board opened, NEW until `Seen`.
  Place: the challenge's spot (`ChallengeYShare` 0.42, HubCorners.luau:620-660) when no offer
  tile shows; while the Starter/VIP offer tile shows, directly ABOVE it, and the offer never
  moves (moving it down puts it on the phone's jump button, Config.luau:16427-16429). Write the
  placement as a pure function with a Lune overlap test at 844×390, 1024×768, 1920×1080 (offer
  shown/hidden) against the offer tile, the jump button, the top bar row (SkyBanner, Players
  list) and the left column. Pad: the event tile is the **first** entry of the
  `HubCorners.padStops` list (:781-797), before `self.challenge.button`, so it is the first stop
  on the D-pad's left; add only that one line (plus your tile's own spec) and list it. The GUI
  lane adds its boost pill to the same list right after `self.plusTile.button` and edits
  `blurPad`/`padFocusedOn`: leave those to them; the coordinator resolves the overlap. Hidden in
  a match and under popups like the other corners (Progression.update).
- **Event menu:** lively frame per the skill (`Menus.register("Halloween")`, add to
  `Config.UI.Menu.LivelyMenus` (Config.luau:9660), `Config.UI.Halloween.Open`); M4's layout on
  PC/iPad; one scrolling column on a phone (Candy + track, quests, Spider, Get Candy) with the
  Rush strip pinned at the panel's bottom. Track nodes evenly spaced (the bar fills each
  segment by share), cue nodes as cards (CueThumb when the cue lanes' thumbs exist, else the
  approved concept crop), each with a small Preview button that calls
  `CuePreview.open(id, { from = "Track", note = ... })` (GUI lane's `src/client/CuePreview.luau`,
  HW_GUI:359-361) through a guarded require, shown only when the module exists and
  `CuePreview.enabled()` is true (no button otherwise, never a dead one); the GUI lane logs the
  `CuePreviewTrack` event. Gifts as small boxes with "x2" / "$5,000", the Broom bigger and gold;
  on a phone the track scrolls sideways to the next node. Day tabs: locked future boards with
  "Unlocks in", a check on finished ones. Quest rows: icon, text, bar, "7/10", the reward chip
  or a bouncing green CLAIM (claim flies Candy into the pill: RewardsFlyer pattern). Spider:
  card + ring "1h 12m / 3h 01m", "Only active play counts". Rush strip: "CANDY RUSH 2x
  CANDY · starts in 12:05" / "ends in 7:42"; Oct 31: "HALLOWEEN NIGHT 2x CANDY ALL DAY ·
  9:12:44". Get Candy: two pack cards with Robux prices from the shop's price read. Header in
  orange/purple if MenuFrame takes a per-menu tint (add the opt, default unchanged, list it).
  Built once on first open, reused; one 1 s clock, never per frame.
- **Rush chip content (R1.10):** `RushChip.content(now) -> { text, endsAt }?` =
  `HwOn and Event.rushChip(Clock.now())`; the GUI lane's shell (above their boost pill) polls it
  each second through a guarded require. You never place or style the chip.
- **Countdown (R1.6):** 18:30-19:00 for `HwOn` players out of matches: an Ink pill (SkyBanner's
  look) centred under Roblox's top bar row, "HALLOWEEN EVENT IN 29:59", clear of SkyBanner and
  the Players list at all four sizes. At 19:00 sharp (`Clock`): "THE HALLOWEEN EVENT HAS
  STARTED!" for 6 s with a Burst, then the tile pops in with NEW. No auto-opened menu (the
  no-unasked-popups rule); log it.
- **Candy toast:** after the result screen closes (or at once in the lobby for quest, King and
  track Candy), a candy chip "+57" (with a "2x" tag) flies to the tile, which bounces; never
  "+0", never in the tutorial. A track step: gifts fly to their HUD target (RewardsFlyer); a cue
  gets a small Slam card ("NEW CUE!", thumb, name, tier tag, OK), when the player is free (not
  in a match, the tutorial or a lucky-block reel).
- **End screen (R1.4):** M5 as a Slam popup, once (`Converted and not EndSeen`), when free;
  numbers count up, COLLECT flies the cash to the money HUD (CashFlyer; the money is already
  saved); then the tile goes away for good.

### 2.12 Config blocks (every number from PLAN; place after `Config.SkyBlock`, Config.luau:3743)

```lua
Config.Halloween = {
	Enabled = true, -- false: no earning and no event UI; saved Candy still converts after EndsAt
	CountdownAt = 1793226600, -- Wed Oct 28 18:30 EDT
	StartsAt = 1793228400, -- Wed Oct 28 19:00 EDT (23:00 UTC); no publish at 19:00
	EndsAt = 1793750400, -- Tue Nov 3 19:00 EST (Nov 4 00:00 UTC); ends by itself
	Boards = 6, BoardSeconds = 86400, -- board N opens StartsAt + (N-1)*BoardSeconds
	Double = { From = 1793419200, To = 1793505600 }, -- Oct 31 US Eastern, 2x all day
	Rush = { Enabled = true, Minutes = 10 }, -- UTC minutes 0-9 of every hour
	EventMultiplier = 2, -- Rush or the double day; they never stack
	-- Friends and group: NO keys here. Config.Economy.FriendBoost / FriendBoostMaxFriends /
	-- FriendBoostEnabled (GUI lane) and the existing GroupBoost are the only source, read via
	-- Money.friendBoost / Money.boostParts (2.6); added, never multiplied.
	CandyIcon = "", -- the Candy icon (candy corn, your 256 px upload, in the interface push as soon as it exists); map's +1/+50 billboards, GUI's chip and your pill read it; "" = each uses its own fallback
	Match = { Enabled = false, PerBall = 3, Finished = 10, Win = 25 }, -- Finished needs finished = 1 (2.6); on once verified
	Boss = { Candy = 50, PaidWinsPerDay = 2, CooldownSeconds = 900 }, -- flat
	Pickup = { Candy = 1, HourCap = 40 }, -- flat, per player per UTC hour; the ONLY cap (CandyService.pickup enforces it)
	Quests = { Enabled = false, Rewards = { 60, 100, 150, 250 }, Boards = { --[[ 2.7 ]] } },
	Track = { Steps = { --[[ 2.8 ]] } },
	Spider = { Enabled = false, Cue = "SpiderCue", Seconds = 10860 }, -- 3 h 01 m active
	TickSeconds = 5, PushSeconds = 2,
	Packs = { Enabled = false, Keys = { "Candy500", "Candy2000" } },
	Convert = { Enabled = true, MoneyPerCandy = 10 },
}
```
Plus `Config.UI.Halloween` (after `Config.UI.Corners`, :16416+: tile, menu, chip, banner, end
screen, toast sizes and motion, phone twins) and `Strings.Halloween` (after `Strings.Corners`,
Strings.luau:1787-1802). Switches start false and flip true only once that part is verified;
the coordinator reads them at merge.

### 2.13 Dev command (designer-only)

One `/hw` block in `DevCommands.luau` (server-checked like the rest): `time live|countdown|rush|double|board N|end|real`
(sets `HwTimeOffset`; Studio and test place only), `candy N`, `quest done`, `active N`,
`kingwin` (a fake King win through `bossWon`; named so it is never confused with map's `/king`
in the same file), `convert`, `reset` (clears the `Halloween` field in the Studio/test store
only). `DevCommands.luau` is shared (map adds `/king`): add only your block and list it.

## 3. Interfaces

**Deliver FIRST (pushed and marked "ready" in your lane file by 08:15, merged 08:15-08:30):**
1. `Config.Halloween` (times, numbers, switches, `CandyIcon`), `Strings.Halloween` skeleton,
   `src/shared/Halloween/Event.luau` and `Clock.luau` with `halloween_event_test.luau` green.
2. The `Halloween` save field (template, MAP_KEYS, validate, old-save test), the PlayerData
   block, and a real `CandyService` (`add`, `bossWon`, `bossCooldown(player) -> number` (unix
   time, 0 if none), `pickup(player) -> (ok, reason)` with `"Cap"|"NotLive"|"NotLoaded"|nil`,
   `isLive`) started in Bootstrap, with tests for caps (each reason), cooldown and the two paid
   wins. If (2) cannot be real by 08:15, push (1) alone, say so, and push (2) as soon as it is;
   never a stub.

After the 08:15-08:30 interface merge the coordinator merges **on request from 08:45** (Cues A
drop 2 about 08:45; drop 3 and the GUI pill about 10:00-10:20; then each lane as it passes its
checks). Ask through your lane file's Requests, and merge `halloween` into `hw-core` after those
merges so `Catalog.ready` cues and Money's friend functions reach your branch.

**You consume (code against them now with a guarded require or attribute read):**
- GUI → `FriendsHere` (number attribute, uncapped; `tonumber(...) or 0`), `Money.friendBoost`
  and `Money.boostParts` with the `Config.Economy` friend lines (2.6; guarded fallback until
  they merge), `CuePreview.open(id, opts)` / `CuePreview.enabled()` for the track cards (2.11).
- Cues A → the five Catalog rows and names, and `Catalog.ready(id)`: false or missing → the
  grant is held and retried on load and every tick, and the card shows the concept art.
- Map → `Config.HalloweenMap.Enabled`, `.Boss.Enabled`, `.Candy.Enabled` (the Alts use
  `HM.Enabled and HM.Boss.Enabled` and `HM.Enabled and HM.Candy.Enabled`; missing = off); map
  calls your `bossWon` from `BotService.matchEnded` (BotService.luau:83: `not info.won and info.reason ~= "EmptyTeam"`
  is the player's win), `bossCooldown` for the King's prompt, and `pickup` from CandyDrop
  (its bag-full note only on `"Cap"`).
- Sys → the `UltService.Used` signal `(player, tableId, epoch)` (guarded require; missing → the
  ability quest's Alt); sys's badge rule kind `{ halloween = "KingWins" | "Candy", atLeast = n }`
  reads your save field (2.5).
- GUI ← you: `RushChip.content`, `HwOn` and `Config.Halloween.CandyIcon`. Map ← you:
  `bossCooldown`, `pickup`'s reason, `CandyIcon`. Map, GUI, sys ← you: `Event` + `Clock`. Write
  these in your lane file's Status when they land.

## 4. Checks

- After each step: `tools/lint.sh`, `tools/test.sh`, then Studio in YOUR window (list the
  studios through MCP, pick `lane-hw-core.rbxl` by name), console clean, commit (one feature a
  commit, attribution line), `git push -u origin hw-core`, tick the line, a dated Status line.
- Lune: the four new tests (boundaries, multiplier never 4, match Candy for every pay kind and
  bot kind incl. Tutorial and Disguised, `finished` for a played-out match, a draw, both sides
  of a real forfeit and a short forfeit, the friend/group parts through Money and through the
  fallback, farm rows, routing with overflow and alts (incl. `HalloweenMap.Enabled` false with
  `Boss.Enabled` true), track due steps and holds (`Catalog.ready` false → held, true → granted
  on the next tick), each `pickup` reason, Spider once, conversion maths); `save_schema_test`
  old-shape load and fixes;
  `config_test` (track ascending, quest rows and Alts valid, times in order, product rows with
  `Candy`, every `Config.Halloween` switch a boolean, no friend or group key under
  `Config.Halloween`, `Pickup.HourCap` a whole number ≥ 1, `CandyIcon` a string; your own cases
  only, the file is shared); a pack replay test; the right-slot overlap test.
- Studio: `/hw time ...` to walk Before → Countdown → Live → Rush → double → board 4 → Ended;
  play the tutorial game (a real "Player" match) and see Candy land while nothing shows; skip
  or finish and see the tile appear; `/hw candy` across 150 and 7,000 (cue reveals, gifts,
  no duplicates); `/hw active 10850` then wait for the Spider; StoreQA pack grant twice;
  `/hw time end` for conversion and the end screen; rejoin (no second conversion, no second
  screen).
- **Four device sizes for every screen** (tile, menu, banner, end screen, toast):
  `tools/halloween/studio_size.sh lane-hw-core.rbxl <w> <h>`, then read
  `workspace.CurrentCamera.ViewportSize` through MCP until it is 844×390 (phone), 1024×768
  (iPad), 1920×1080 (PC), and 1920×1080 with GuiQA `"pad"` (TV/controller: open, scroll, CLAIM,
  buy and close with the pad alone). If the helper fails, use your layout test and say so.
- **Fresh-player run** (this touches join, the tutorial, the first match, saves, purchases and
  the lobby popups): `/resetdata`, rejoin, tutorial game 1 (Candy counts, no event UI, no toast),
  finish; again with skip; then the tile, the menu, a match, a claim. Console clean.
- Screenshots to `~/Desktop/8ball-refs/halloween/shots/hw-core/` (gate ones in `gate1/`, `gate2/`),
  one line each in the lane file's Gate shots.

## 5. Cut order (first to go; a cut is switched off and listed, never half-visible)

1. Menu flourishes beyond the skill's basic entrances (idle loops, bursts) → plain lively frame.
2. The 19:00 start moment (keep the countdown pill; the tile just appears).
3. The Candy toast's flight (a static "+57" chip instead).
4. The Spider ring graphic (text "1h 12m / 3h 01m" instead; the grant stays).
5. The ability quest (its Alt) and the nice-shot quest (→ `Balls`).
6. Packs (`Packs.Enabled = false`, section hidden; products may stay created, unsold).
Never cut: Candy at settle, the track and its grants, quests with CLAIM, the Spider grant,
conversion with an end screen, the tutorial gate, the tile, the menu.

## 6. Gates

- **09:00 (gate 1):** interfaces merged; `/hw time` walking the states (console); a tutorial
  game paying Candy in Studio with the save's `Halloween` printed; the tile's placement at phone
  and PC sizes (shots in `gate1/`).
- **11:00 (gate 2):** the event menu with track + quest board + Spider ring + Rush strip at phone
  844×390 and PC 1920×1080, a CLAIM and a track step granting (shots in `gate2/`). The quest
  board may run on fake data (a GuiQA-pinned view) if the quest server logic is not finished by
  10:50; say so in the gate line, and the real CLAIM then follows before 13:00. Before 11:00 is
  the last time to ask Justin about the menu's look; after it, decide and log.

## Progress

- [ ] Interface 1: `Config.Halloween`, `Strings.Halloween` skeleton, `Event.luau`, `Clock.luau` (+ test-place offset at boot), `halloween_event_test.luau`; pushed, lane file says ready
- [ ] Interface 2: `Halloween` save field (template, MAP_KEYS, validate, old-save test), the PlayerData block, real `CandyService` (add, bossWon, bossCooldown -> unix time or 0, pickup -> ok + reason "Cap"/"NotLive"/"NotLoaded", isLive) in Bootstrap, tests; pushed, lane file says ready
- [ ] `/hw` dev command block (time offsets, candy, quest, active, kingwin, convert, reset), checked in Studio
- [ ] Take the 08:30 interface merge (`git fetch && git merge halloween`), lint, tests, push; later merges on Request from 08:45 (cues-a drop 2, drop 3 + GUI pill about 10:00-10:20), merge `halloween` again after each
- [ ] Match Candy at settle (Ranking hook, CandyMath with `finished`, Rush/double, friends/group through `Money.friendBoost`/`boostParts` with the guarded fallback, no "+0"), HwCandy/HwMatch events; tutorial game pays in Studio
- [ ] Client state: `Halloween` remote, `Candy`/`HwOn` attributes, `State.luau`; nothing visible before the tutorial is Done/Skipped
- [ ] Event tile in the right-side slot (HubCorners spec, pure placement + overlap test, first `padStops` entry, NEW, "!"); gate 1 shots
- [ ] Track steps + gifts + cue grants (only when `Catalog.ready(id)`, held otherwise and retried on load and every tick) and the Spider active clock (SkyDropService getter, 5 s tick, grant at 10,860 s); tests
- [ ] Event menu part 1: lively frame, Candy pill, the 11-step track (phone sideways scroll, guarded `CuePreview.open` on cue cards)
- [ ] Quests: 6 boards finalised and ordered, routing with overflow and Alts (`HM.Enabled and HM.Boss/Candy.Enabled`, `UltService.Used` missing), hooks (settle, pickup, King, `UltService.Used` subscription, active minutes), CLAIM remote; tests
- [ ] Event menu part 2: quest board with day tabs (fake data allowed for gate 2), CLAIM flying Candy, Spider ring, Rush strip; gate 2 shots at phone and PC by 10:50
- [ ] Rush chip content (`RushChip.content`) for the GUI shell, and the Candy toast + track-step reveal card
- [ ] Candy packs: products created, Config rows, Shop/PlayerData grant in one commit, replay test, Get Candy section
- [ ] Conversion at the end (once per save, claims finished quests first, lobby and arena), HwConvert; tests incl. rejoin
- [ ] End screen (M5) with count-up, owned cue cards, COLLECT; once per save
- [ ] Countdown pill 18:30-19:00 and the 19:00 start moment, walked with `/hw time`
- [ ] Every switch verified and set true; analytics events seen in the Funnel log
- [ ] Fresh-player run (tutorial played and skipped): Candy from game 1, no event UI until Done/Skipped, then tile, menu, match, claim; console clean
- [ ] Four device sizes + pad for the tile, menu, chip text, countdown, toast and end screen; screenshots
- [ ] Lane file Status final (what works, switches, shared-file changes, requests) + all screenshots
- [ ] Merge halloween, re-test (lint, tests, Studio main path), push

## Notes
