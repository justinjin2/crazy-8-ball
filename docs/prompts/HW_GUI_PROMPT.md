# Halloween W7: the Boost pill and the Cue Preview

**Written 2026-10-28 07:20 EDT by the coordinator with Claude, for Justin's Halloween update.**
Lane `hw-gui` (window W7): folder `~/Desktop/8ball-hw-gui`, branch `hw-gui` (cut from
`halloween`), Rojo **34888**, Studio window **`place/lane-hw-gui.rbxl`** and only that one, model
**Opus 5.5, effort xhigh**. The coordinator starts it with `tools/halloween/lanes.sh launch`;
the launch line, and any restart line (the coordinator adds `--continue`), is exactly the
command `tools/halloween/lanes.sh command hw-gui` prints (model, effort, Stop hook settings and
start prompt included). Never write your own flags.
The shared contract: [`docs/halloween/PLAN.md`](../halloween/PLAN.md) (decisions, numbers,
lanes, ownership, interfaces, rules, timeline). Requirements:
[`docs/halloween/REQUIREMENTS.md`](../halloween/REQUIREMENTS.md). Your lane file:
[`docs/halloween/lanes/hw-gui.md`](../halloween/lanes/hw-gui.md).

**Attended until 11:00 EDT.** The Progress list at the end is the source of truth; the Stop hook
sends you back to work while any `- [ ]` remains. Until 11:00 Justin answers fast: when you truly
need him (a gate question, access you cannot get, a call where guessing lowers the quality), run
`touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"` (this folder is a worktree, so
`.git` is a file: never `touch .git/overnight-waiting`, whatever an older message says), ask
ONE clear question with a screenshot path, and stop. **After 11:00** he may be asleep until about 16:30:
decide the way he would (past decisions, `docs/UI_STYLE.md`, simple for kids), log it under
Assumptions in the lane file, keep going. Never stop between steps otherwise.

**Hard rules.** Times are EDT. Interfaces pushed by **08:15**. Lanes stop building at **16:00**
(every open line done or ticked `CUT:`/`BLOCKED:` with a reason); **17:00** freeze, only fixes the
coordinator asks for. Never publish. Never touch the Team Create place (the "Crazy 8 Ball"
window), another lane's window or port 34872. Blender headless only, never the Blender MCP.
Images may be uploaded to group 675425213 without asking (`tools/roblox_upload.py`); no audio
uploads. No price, payout or product change beyond the friend boost Justin approved. Do not edit
`docs/STATUS.md`, `ROADMAP.md`, `DECISIONS.md`, `ECONOMY.md` (Requests to the coordinator).
When the coordinator says `halloween` moved: `git fetch && git merge halloween`, fix your area,
lint, tests, push.

## 0. Read first, in this order

1. `docs/halloween/PLAN.md` whole (§2 rows "Friend boost", "Group", "Boost display", "Cue
   preview", "Tutorial"; §4 your row and ownership; §5 interfaces; §7 how lanes work; §8
   timeline). `docs/halloween/REQUIREMENTS.md` (R1.10, R5.1-R5.7, R7.1-R7.2, R0.5 and §9).
   `CLAUDE.md`. `docs/parallel/README.md` (its rules apply with PLAN's lanes, ports and branch
   `halloween` instead of `release`). Your lane file.
2. `.claude/skills/lively-gui/SKILL.md` whole, then `motion.md`, `verification.md`,
   `pitfalls.md` (`art-pipeline.md` only if you draw an icon). `docs/UI_STYLE.md`. Every screen
   here goes through that skill, scaled to its size: the mocks below are the approved target
   pictures; skip the browser animatic for the pill and chip.
3. Agent reports in `~/Desktop/8ball-refs/halloween/research/agents/`:
   - `code-hud-boosts.md` (main): the HUD rows and free widths per size, every pay site and
     where boosts do and do not apply, Friends, device detection, the LuckClover template, the
     layout proposal and its risks.
   - `code-cues.md`: the "Cue Preview screen" section and "Risks" (holdShots, match start,
     Highlights cap).
   - `research-boosts-hype.md` part A: A1 (IsFriendsWithAsync caching), A4 (the 2024 incident: a
     slow friend check paid a whole server; error or slow must give 0), A5 (timed chips).
4. The mocks (open them; compare at every check):
   - `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/H1_boost_hud.png`. Copy its LOOK:
     a white rounded pill with the ink outline like the money pill, a green up-arrow and
     "+130%" (a crown instead of the arrow for VIP); the white "YOUR BOOSTS" card above it with
     one row per source (icon, name, green "+N%", "Friends (2)"), a rule, "Total +130%" in green
     and a small grey footer "Each friend in your server +10% (max 4)"; the orange rounded
     "2x CANDY / 07:42" chip with a candy icon. Do NOT copy its POSITION (the pill in the money
     row): PLAN §2 puts the pill in the row ABOVE the money pill, replacing the VIP tag, the chip
     above the pill, Invite and Plus unmoved.
   - `/Users/justinjin/Desktop/8ball-refs/halloween/mocks/v2/PREV1_cue_preview.png`: a framed
     panel; header "CUE PREVIEW" with a wand icon and the red X; left, a big window onto the live
     3D stage (the cue over a table corner, the ball rolling with its trail into a pocket, the
     finisher bursting out, "Drag to rotate" at its bottom); right, the cue's name in big
     outlined letters, its group/rarity pill, a note line ("Never coming back"), three tabs
     MODEL / TRAIL / FINISHER (the lit one blue), an "AURA ON" toggle, a big green EQUIP. The
     mock's haunted-room backdrop is not ours: the preview is permanent, so a neutral dark stage.
   - For checking the preview with the event cues once Cues A/B merge (same folder):
     `C5_candy_corn.png`, `C4_jack.png`, `C2c_black_cat.png`, `C1b_spider.png`, `C3b_broom.png`.
5. The code you change or copy (spot-checked on `halloween` @ 12ee4888; lines drift, grep names):
   - Boosts: `src/shared/Progression/Money.luau:135-154` (`Boosts`, `Money.boost`; `E =
     Config.Economy` at :33), `src/server/Economy.luau:90-100` (`Economy.boost`) and `:210-211`
     (shot pay), `src/server/Ranking.luau:380, 420-436` (match and streak bonus),
     `src/shared/Config.luau:2021-2030` (`VipBoost` ... `PlusBoost`), `tests/money_test.luau:369-383`.
   - Friends: `src/server/Friends.luau` (94 lines; `refresh` :24-38 sets the `FriendHere`
     boolean the match bar reads; `arrive` :40-60 asks `IsFriendsWithAsync` once per pair and
     never retries; `PlayerRemoving` :75).
   - HUD: `src/client/UI.luau:36-43` (`PoolHud`), `MoneyHud.luau:251-291`, `VipTag.luau`
     (`top` :217, `setInMatch` :284, `showPerks` :298), `LuckClover.luau` (the template: badge in
     `money.root`, `HudParts.popupCard` at :108, hover and pin, 1 s poll, GuiQA hooks :171-176),
     `HudParts.luau:248` (`popupCard`), `HubCorners.luau:713-731` (Invite/Plus right of money),
     `:782` `padStops`, `:803` `focusPad`, `:820` `blurPad`, `:844` `padFocusedOn` (checks
     `IsDescendantOf(self.root)`; the pill lives in `money.root`, so add it explicitly),
     `MenuColumn.luau:219` and `:568` and `PadGuide.luau:312` (the `{ "VipTag", "LuckClover" }`
     keep-above lists), `Progression.luau:265-267` (money, VIP tag, clover), `:302-309`
     (`deps.vipTag`), `:331` (MenuColumn after), `:615` (`vipTag:setInMatch`), `:652-653` (money
     shows in a match; tutorial-hidden), `Purchased.luau:273-275` (after buying VIP:
     `deps.vipTag:showPerks()`), `Config.luau:3088-3100` (hotbar: `SlotPx 64`, `PhoneSlotPx 48`,
     `PhoneWidthPx 900`, `PhoneHotbarSlots 3`, `BottomPx 10`), `WinTrack.luau`,
     `Config.Multiplayer.Style.ShortHeight = 430` (:8306), `Config.UI.VipTag` (:9365),
     `Config.UI.LuckClover` (:9400), `src/shared/Tutorial/Steps.luau:71` (`Steps.active`).
   - Analytics: `src/server/Funnel.luau:222` (`Funnel.event`), `:94` (`Funnel.device`),
     `src/server/TutorialService.luau:770-781` (`FUNNEL_EVENTS`: client-seen moments any player
     reports through `TutorialEvent`, already rate limited).
   - Preview: `src/client/Menus.luau:231` (`register`), `HudFocus.luau` (a ScreenGui named
     `...Menu` stays), `UltScreen.luau:445-520` (saves/restores `TouchControlsEnabled`),
     `UltStage.luau:337-382` (holds WalkSpeed/Jump, restores), `PullKit.luau:126` `takeCamera`,
     `:166` `putBack`, `src/shared/CueStickBuilder.luau:318` `build`, `:429` `frame`, `:453`
     `placeAt`, `src/client/CueSkinLook.luau:175` `attach(stick, { aura = true })` (as
     `Hub.luau:83`), `:1248` `destroy`, `src/client/Effects.luau:121` `styleOfCue`, `:132` `new`,
     `:213` `attachTrail`, `:351` `updateTrail`, `:577` `pocketBurst`, `:796` `skinFinisher`
     (returns its length), `:929` `destroy`, `src/client/CueAssets.luau:508` `ready`, `:517`
     `preload`, `:532` `whenReady`, `:549` `shotReady`, `:586` `holdShots` (it REPLACES the held
     list; `Main.client.luau:1259-1289` rebuilds it every `ShotRefreshSeconds`),
     `InventoryCues.luau:455` (Equip/Sell), `:870` `choose`, `:889` `show`, `:897` `openDetail`,
     `:1133-1148` `doEquip` (`ItemState.request("ItemRequest", "EquipCue", id)`),
     `InventoryIndex.luau:220-226` (the detail card's `onPress` does nothing), `ItemState.luau`.

## 1. Goal

This lane owns **R5.1-R5.7** (the boosts HUD; R5.7's mock is H1, approved), **R1.10** (the Rush
chip's shell and place; core owns its text), **R7.1-R7.2** (the Cue Preview), and R0.5/R0.6 for
its own screens. Both features are permanent, not event-only.

Done, in player terms:
- A player with two Roblox friends in the server sees **"+20%"** in a small white pill just above
  the money pill (with VIP: a crown and "+120%"). Tapping it, clicking it or pressing A on it
  opens "YOUR BOOSTS": VIP +100%, Group +10%, Friends (2) +20%, Total +130%, and the friend
  rule. Every match pays exactly that boost on money (and core pays the same friends and group
  part on Candy, read from the same `Config.Economy` lines). A friend leaving drops it at once; a broken or slow friend check gives 0, never more.
- During a Candy Rush an orange chip above the pill reads **"2x CANDY 8:12"** (core's words).
- Nothing on the HUD overlaps at phone, iPad, PC and TV sizes, with or without VIP, a full
  hotbar or the open WinTrack. Invite and Plus never move. A controller reaches the pill.
- In My Cues and the Index a **Preview** button opens a stage: the cue turns slowly in its full
  aura (drag to turn it by mouse, finger or right stick); TRAIL shows a stroke, the ball rolling
  with that cue's trail into a pocket and the finisher; FINISHER frames the pocket. EQUIP equips
  an owned cue. B, Escape or the red X close it and return to where it came from; a match start
  or respawn closes it too. Core's event track opens the same screen. It ships ON only if it
  passes on a phone size and with a controller.

## 2. Design

### 2.1 Friend boost: pure maths (interface, first)

In `src/shared/Progression/Money.luau`:
- `Boosts` gains `friends: number?` (friends in your server, uncapped; nil = 0).
- `Money.friendBoost(count: number?): number`: 0 when `E.FriendBoostEnabled ~= true` or `count`
  is not a finite number; else `E.FriendBoost * math.min(math.max(0, math.floor(count)),
  E.FriendBoostMaxFriends)`. **One source** (PLAN §5): these `Config.Economy` lines are the only
  friend-boost numbers in the game and the group value is the existing `Config.Economy.GroupBoost`.
  Core's Candy maths reads both through `Money.friendBoost` / `Money.boostParts` (for example
  `Money.boost({ friends = n, group = inGroup })` is exactly the Candy friend + group part),
  with a guarded fallback on its side; `Config.Halloween` keeps no copy of them, so
  `FriendBoostEnabled` is the one friend switch for money and Candy.
- `Money.boostParts(on: Boosts): { { kind: string, add: number } }`: the active parts only
  (`add > 0`), in the card's order `"Vip"`, `"Group"`, `"Plus"`, `"Friends"`, `"Starter"`,
  `"Party"`; a fresh table per call.
- `Money.boost(on)` becomes the sum of `boostParts(on)`: identical results for every old flag set.
- Tests next to `money_test.luau:369`: order and values; sum == `boost`; friends nil/0/1/2/4/7,
  -1, NaN, 2.7; switch off gives 0 and no Friends part; VIP + 4 friends = 1.4; all six = 3.6;
  `{ friends = 2, group = true }` = 0.3 (the part core's Candy reads); every old case unchanged.

`Config.Economy`, right after `PlusBoost` (Config.luau:2030), the only lines you add there:

```lua
	-- The friend boost (Halloween 2026, PLAN §2, designer 2026-10-28; hw-gui lane): +FriendBoost
	-- per Roblox friend in your server, at most FriendBoostMaxFriends, added to the other boosts
	-- (never multiplied), permanent, on match money (Money.boost) and on Candy (core reads these
	-- same lines through Money.friendBoost; Config.Halloween has no copy). A friend check still
	-- waiting or failed counts 0 (research A4).
	FriendBoostEnabled = false, -- own switch: true once the Studio pay check passes; false = no friend part in money or Candy
	FriendBoost = 0.1,
	FriendBoostMaxFriends = 4, -- +40% at most (24-player servers: no cap would allow +230%)
	FriendRetrySeconds = 30, -- a failed IsFriendsWithAsync is asked once more after this, then 0
```

### 2.2 FriendsHere (interface, first)

In `src/server/Friends.luau`: `refresh` also counts the pairs Roblox answered `true` among
`Players:GetPlayers()` and sets the number attribute **`FriendsHere`** (uncapped) next to the
existing `FriendHere` boolean (unchanged). Add `Friends.count(player): number`. A pair still
being asked, or that errored, counts 0 (never assume a friend). A failed pair is asked once more
after `FriendRetrySeconds`, then stays 0 for the session (keep the one-warn-a-minute rule). Lobby
bots are not `Player`s, so they never count. Studio only (`RunService:IsStudio()`), a
`ServerStorage.FriendsQA` BindableFunction: `("count", player, n?)` forces that player's
`FriendsHere` (nil returns to the real count), because `IsFriendsWithAsync` fails in Studio.
Keep each player's session peak (capped at 4) for the analytics event (2.10).

### 2.3 One reader of the boost flags

New `src/shared/Progression/BoostFlags.luau` (tiny, reads Instances): `BoostFlags.of(player,
now): Money.Boosts` from the `Vip`, `InGroup`, `MoneyBoostEnds` (vs `now`) and `FriendsHere`
attributes, `player.MembershipType == Premium`, and `workspace:GetAttribute("MoneyPartyEndsAt")`
(vs `now`). `Economy.boost(player)` becomes `Money.boost(BoostFlags.of(player, os.time()))`; the
pill uses `BoostFlags.of(LocalPlayer, workspace:GetServerTimeNow())`. The pill can then never
disagree with the pay. The friend part reaches exactly the sites `Money.boost` reaches today
(every shot, match bonus, streak bonus) and nothing else (rewards, WinTrack, packs, sell-back stay
unboosted, as the rule at Config.luau:2021-2023 says).

**R5.2 economy check** (a record, not a reopen): before flipping the switch, write in the lane
file the money effect: the average boost if, say, 15% of sessions have 1 friend and 5% have 2+
(about +2.5% match money), and the worst case +40% for a 4-friend party; `tools/economy_model.py`
if quick, else hand maths from `docs/ECONOMY.md` 3.5. Today nobody measures friends in a server
(`FriendHere` is not logged): the `FriendBoost` event (2.10) will.

### 2.4 The HUD layout, pure and tested

`src/shared/HudLayout.luau` (no Instances, runs in Lune). Rects are `{ x, y, w, h }` in the
PoolHud screen's pixels (the area under Roblox's top bar and inside the safe insets).
- `HudLayout.others(screen, s)`: the money HUD, Invite, Plus, hotbar, WinTrack and the left
  column, mirrored from Config exactly as MoneyHud, HubCorners, LuckyHotbar, WinTrack and
  MenuColumn place them (`code-hud-boosts.md` §1 has every formula). `s` (the scene): `vip`,
  `moneyText`, `plusShown`, `blocks` (0..n), `winTrackOpen`, `chipText?`.
- `HudLayout.boost(screen, s, others) -> { pill, chip?, chipCompact: boolean, card }`. Rules:
  the pill in the row above money, `LeftPx` right of the money HUD's left edge; on a short screen
  (height under `ShortHeight`) at least the left column's right edge + `ColumnGapPx`, so the
  column never has to lift for it; its width fixed by `WidestText` ("+360%"); the chip right
  above the pill at the same left x, width fixed by its `WidestText`; if the chip would touch
  the WinTrack, hotbar or column it becomes the compact chip (icon + "2x 8:12"); the card above
  the pill, clamped inside the screen. Widths come from a `CharWidthShare` estimate in both the
  test and the game, so both run the same numbers.
- `HudLayout.overlaps(rects) -> { { string, string } }`.
- BoostPill places itself by calling `HudLayout.boost` with the LIVE rects of the others
  (measured `AbsolutePosition`/`AbsoluteSize`), relaid on every size or visibility change.
- `tests/hud_layout_test.luau`, HUD areas from the report: 844x390 → 750x311 (also 844x332, no
  side insets), 1334x750 → 1334x692, 1024x768 → 1024x700, 1920x1080 → 1920x1022. Every
  combination of VIP on/off, chip none / "2x CANDY 8:12" / "2x CANDY 23:59:59", blocks 0/3/9,
  WinTrack open/folded, Plus shown/hidden, money "$125,000" and "$1,050,000": pill and chip
  inside the screen and at least 2 px clear of money, Invite, Plus, hotbar, WinTrack and the
  column; the card inside the screen. Overlaps among the OTHERS that exist today (report §1: on
  iPad a 9-slot hotbar under money and Invite; with the hotbar hidden the open WinTrack can touch
  Plus) are printed, not failed: write them as a Request to the coordinator, do not fix them.

### 2.5 The Boost pill and its card (`src/client/BoostPill.luau`)

Copy LuckClover's structure.
- Progression builds it **instead of** VipTag when `Config.UI.BoostPill.Enabled` (off = today's
  VIP tag, untouched). It lives in `money.root`, named `BoostPill`, and has the VipTag shape the
  rest of the code uses: `.tag` (the pill), `:top()`, `:setInMatch(on)`, `:showPerks()` (after
  buying VIP: the card pins open `PurchaseSeconds` with the VIP row flashing gold), `:layout()`.
  Progression sets `deps.vipTag = pill` and `deps.boostPill = pill`, so `Purchased.luau` needs no
  change, and `LuckClover.new(money, pill)` puts the clover right of the pill.
- The pill: the crown (`K.Icons.Crown`, rocking like the VIP tag's) when VIP, else the green
  up-arrow (`K.Icons.Arrow`, tinted), then "+N%" with N = `math.floor(Money.boost(flags) * 100 +
  0.5)`, in the kit's white pill with the ink outline. At 0: "+0%" dimmed when `ShowAtZero`,
  else hidden (gate 1 asks Justin; default shown).
- It follows attribute changes (`Vip`, `InGroup`, `FriendsHere`, `MoneyBoostEnds`, workspace
  `MoneyPartyEndsAt`, `MembershipType`), plus a `PollSeconds` poll only while a timed part
  (Starter, Party) runs. A higher total counts up over `CountSeconds`, then pops (`PopScale`,
  motion.md tokens); a lower one just changes.
- The card, `HudParts.popupCard(pill, "Boosts", ...)`, "YOUR BOOSTS": one row per part from
  `Money.boostParts` (icon, Strings name, green "+N%"; "Friends (n)"; Starter and Party with
  time left), a rule, "Total +N%", the footer "Each friend in your server +10% (max 4)" built
  from Config. While the event is live (`Event.isLive(now)` through a guarded require of
  `Shared.Halloween.Event`; missing → no line): "Friends and Group boost Candy too". Then, grey,
  the boosts you could still get: "Join the group: +10%", "Friends here: +10% each", "VIP: +100%".
- Input: hover shows, leave hides; a click, tap or A pins it for `PinSeconds`, a second press or
  B closes. In a match (`setInMatch(true)`) the pill still shows (money shows in a match) but
  takes no input and its card closes, as `VipTag.setInMatch` does.
- Hidden while the tutorial runs (`Steps.active(player:GetAttribute("TutorialStep"))`) and while
  money is tutorial-hidden; pops in with the lively stagger when it ends.
- Pad: `Selectable` false while walking; reached through `deps.boostPill`, so D-pad left reaches
  it with the corner buttons. In `HubCorners.padStops` (:782) add ONE entry, the pill, right
  after `self.plusTile.button`; core's event tile is the FIRST entry, before
  `self.challenge.button`, and that line is core's (do not add or move it). Plus your own lines
  in `blurPad` and `padFocusedOn`. HubCorners is a shared file (PLAN §7): touch only these
  lines, list them in the lane file, and the coordinator resolves the overlap with core.
- GuiQA hooks (Studio only): `boosts` ({vip, group, plus, friends, starter, party} or nil =
  real) fakes the client view; `boostCard` (open?) pins it; `boostPerks` calls `showPerks`;
  `rushChip` (text?) drives the chip; `hudRects` returns the live rects of pill, chip, money,
  Invite, Plus, hotbar, WinTrack and the column tiles; `hudOverlap` returns overlapping pairs.

### 2.6 The Rush chip shell

- `RushChip` in `money.root`, placed by `HudLayout.boost` above the pill; H1's orange rounded
  chip (an icon slot and one text label); sizes in `Config.UI.BoostPill.Chip`.
- The contract is core's (HW_CORE_PROMPT 2.11 and §3): `src/client/Halloween/RushChip.luau`
  exposes **`RushChip.content(now) -> { text: string, endsAt: number }?`** (`HwOn and
  Event.rushChip(Clock.now())`: "2x CANDY 8:12" in a Rush, "2x CANDY 9:12:44" on Oct 31, nil
  otherwise). Your shell polls it once a second through a guarded require
  (`script.Parent:FindFirstChild("Halloween")` → `RushChip`, in a pcall; `now` from
  `Shared.Halloween.Clock.now()`, else `workspace:GetServerTimeNow()`). Module missing, an error
  or nil → the chip hides. One 1 s loop, never per frame.
- The first show pops in, then a gentle pulse every `PulseSeconds`; text changes never re-pop.
  No input, no card. It shows in a match too (Candy is earned there) and hides with the pill in
  the tutorial. The candy icon: `Config.Halloween.CandyIcon` (core's key, the one Candy icon in
  the game), read guarded: `Config.Halloween` or the key missing, or `""`, collapses the icon
  slot and centres the text. Never draw or upload a second Candy icon. You own its look and
  place; core owns when and what it says. GuiQA `rushChip` (text?) overrides the content in
  Studio.

### 2.7 Wiring touchpoints (list each in the lane file's Shared-file changes)

"(shared)" marks a PLAN §7 shared file: add your own block or line, change nothing else, list
it; the coordinator resolves overlaps at merge.

| File | Change |
|---|---|
| `Money.luau`, `Economy.luau:90-100`, new `BoostFlags.luau` | 2.1, 2.3 |
| `Friends.luau` | 2.2, the `FriendBoost` event |
| `Progression.luau:265-267, :302-309` (shared) | BoostPill instead of VipTag when enabled; `deps.vipTag`/`deps.boostPill`; clover beside the pill |
| `Progression.luau:615` (shared) | `setInMatch` on whichever is built; `CuePreview.close()` when `state.inMatch` turns true |
| `MenuColumn.luau:219, :568`, `PadGuide.luau:312` | add `"BoostPill"`, `"RushChip"` to the keep-above lists |
| `HubCorners.luau:782-850` (shared) | the pill as one `padStops` entry right after Plus; your lines in `blurPad` and `padFocusedOn` (core's event tile spec is in the same file and its tile is the first pad stop: touch only your lines) |
| `TutorialService.luau:770` | `FUNNEL_EVENTS` entries (2.10) |
| `Net.luau:395` (shared) | your event names in that comment only (core adds its `Halloween` remote and map its own lines in the same file) |
| `Main.client.luau:1265` (shared) | the open preview's cue second in `ids` (one guarded line) |
| `InventoryCues.luau:455`, `InventoryIndex.luau:220` | the Preview buttons |
| `Config.luau`, `Strings.luau` (shared) | your own blocks only |

### 2.8 The Cue Preview (`src/client/CuePreview.luau`, pure `src/shared/CuePreviewMath.luau`)

**Public:** `CuePreview.open(id: string, opts: { from: string?, onClose: (() -> ())?, note:
string? }?) -> boolean`, `CuePreview.enabled() -> boolean` (the switch; entry buttons show only
when true), `CuePreview.isOpen()`, `CuePreview.close()`. `open` returns false when disabled, in a
match, under a popup or reel (the `Menus` blocker), or for an id with no catalog row.

**Screen.** `Menus.register("CuePreview")`; its ScreenGui is `CuePreviewMenu` (HudFocus keeps
it, hides the rest). NOT in `Config.UI.Menu.LivelyMenus`: MenuFrame's ScreenBlur would blur the
stage. Build the lively chrome by hand from the kit: the unroll open, the header band with the
scrolling 8-balls, "CUE PREVIEW" with an icon, the red X, the 8-ball flair. The left **window** is
only a rounded ink border, transparent inside: the real 3D camera view shows through it (no
ViewportFrame: it draws no particles, beams or trails). The right **info sheet** (white with the
dots): the name (outlined, fitted), the rarity/group pill from the card kit, `opts.note` (core
passes "Never coming back", "Track: 2,000 Candy"), the tabs MODEL / TRAIL / FINISHER (icons
`Cue`, `Lightning`, `Target`), the AURA toggle (cut first), EQUIP (green; "EQUIPPED" grey when
it is; hidden when not owned, `opts.note` takes its place). Outside the panel: a flat navy
veil (`OutsideTransparency`), never a blur. `CuePreviewMath.panel(screen)` returns every rect;
tested at the four sizes: window at least `WindowMinShare` of the panel width and 200 px tall,
buttons at least `MinHitPx` tall, nothing overlapping, all inside the screen.

**Stage** (client-only, built on open, destroyed on close) in `workspace.CuePreviewStage` at
`Origin`: a dark backdrop (a big inward-facing box or cylinder) and floor, a key SpotLight and a
rim PointLight (its own light; it must read under the Night preset); a table: a clone of the
first model under `workspace.Tables` whose cloth and pockets are streamed in (StreamingEnabled
is on; the template is in ServerStorage, so the client cannot build one), stripped of scripts,
ProximityPrompts, ClickDetectors, sounds, GUIs, CollectionService tags and attributes (or the
lobby's table code picks the clone up), all Anchored with CanCollide/CanQuery/CanTouch off;
when none is ready, a felt slab with a rail and one pocket ring from parts. The ball: a white
sphere at the game's ball size. The cue: `CueStickBuilder.build(stage, id)` +
`CueSkinLook.attach(stick, { aura = true })` (Cues A's custom bodies come through these). The
effects: `Effects.new(stage, Effects.styleOfCue(id))`.

**Loop** (timings in Config): TRAIL: the stick behind the ball at its gap, a pull back
(`StrokeBackSeconds`) and strike (`StrokeHitSeconds`) through `CueStickBuilder.frame` with an
eased gap; the ball tweened to a pocket (`RollSeconds`) with `attachTrail` +
`updateTrail({ pocketed = false }, true)`; the drop (`DropSeconds`), `updateTrail({ pocketed =
true }, false)`, `pocketBurst(pocket, 1)`; hold for the finisher's length (else
`FinisherHoldSeconds`) + `GapSeconds`; reset; repeat. FINISHER: the camera close on the pocket,
the ball's last `FinisherRollShare` of the roll only, the finisher, repeat. MODEL: no ball; the
cue level and tilted, turning at `TurnDegPerSecond`.

**Camera.** Taken and restored like `PullKit.takeCamera`/`putBack` (type, subject, CFrame, focus,
FOV). `CuePreviewMath.camera(focus, yaw, pitch, distance, fovDeg, viewport, window)` returns a
CFrame that puts `focus` at the window's centre, not the screen's (shift sideways by the window
centre's offset through the FOV); tests: the focus projects within 4 px of the window centre at
the four sizes and at the yaw/pitch limits. Per tab: `Focus`, `Distance`, `Pitch`.

**Input.** A transparent Active frame over the window takes MouseButton1 and touch drags (yaw by
`DragDegPerPx`, pitch clamped `PitchMinDeg..PitchMaxDeg`), with inertia (`SpinDecay`); the right
stick turns at `StickDegPerSecond`; LB/RB cycle tabs (ContextActionService at menu priority,
unbound on close); A presses the selected button (EQUIP selected on open, or the first tab when
not owned); B, Escape and the red X close. Auto-turn resumes after `IdleResumeSeconds`. Walking
held as UltStage does (WalkSpeed, JumpPower, JumpHeight saved and restored) and
`GuiService.TouchControlsEnabled` off as UltScreen does.

**Loading.** `CueAssets.whenReady(id, show)` with a spinner in the window; after
`LoadTimeoutSeconds` show it anyway. The finisher's creature needs the shot assets, and
`CueAssets.holdShots` replaces Main's list: add the open preview's id second in Main's `ids`
(one guarded line at `Main.client.luau:1265`); the first loop waits for `CueAssets.shotReady(id)`
up to the same timeout.

**Close** (idempotent; also when the build failed halfway, inside pcall): stop the loop, unbind
the render step, disconnect every connection, `Effects:destroy()`, the look's `destroy()`, the
stage's `Destroy()`, restore camera, walking, touch controls and the pad selection, then
`opts.onClose`. Triggers: the red X, B, Escape (Menus' close action), another menu opening, a
match starting (Progression.update), `CharacterAdded` or the humanoid dying, a rank popup
(Progression :672 closes menus), a teleport screen.

**Entry points.** My Cues detail: a blue "Preview" candy button beside Equip/Sell
(InventoryCues.luau:455), `from = "Cues"`, `onClose` reopens Inventory on Cues and
`show(id)`. Index detail (InventoryIndex.luau:220): a Preview button under the name, `from =
"Index"`, `onClose` reopens the Index on that row. Core's track cards call `CuePreview.open(id,
{ from = "Track", note = ... })` through a guarded require, their button shown only when
`CuePreview.enabled()`.

### 2.9 Config and Strings blocks (starting values, tune in Studio)

```lua
-- The boost pill (Halloween 2026, PLAN §2 "Boost display"; hw-gui lane; mock H1_boost_hud):
-- one pill over the money pill with the summed money boost ("+130%", a crown for VIP) in place
-- of the VIP tag; tap, click or A opens "YOUR BOOSTS"; the Rush chip's shell sits over it
-- (core fills its words). Pixels and seconds; "Short" for a phone on its side.
Config.UI.BoostPill = {
	Enabled = false, -- true once the four sizes and the pad pass; false = today's VIP tag
	ZIndex = 12,
	HeightPx = 34, ShortHeightPx = 26, -- the VIP tag's
	TextPx = 22, ShortTextPx = 16,
	IconShare = 0.8, PadPx = 8, InnerGapPx = 4,
	LeftPx = 6, GapPx = 6, -- from the money HUD's left edge; over the money pill
	ColumnGapPx = 6, -- short screens: at least this far right of the left column
	WidestText = "+360%", -- the pill's fixed width (VIP + Party + Starter + Group + Plus + 4 friends)
	CharWidthShare = 0.62, -- a character's width per text px (layout estimate, test and game alike)
	ShowAtZero = true, -- "+0%" shows dimmed after the tutorial (gate 1 question)
	ZeroTransparency = 0.35,
	Green = { 70, 205, 110 },
	CountSeconds = 0.4, PopScale = 1.12,
	PinSeconds = 6, PurchaseSeconds = 8, PollSeconds = 1,
	Card = { CornerPx = 14, PadPx = 12, GapPx = 6, TitlePx = 20, TextPx = 16, RowPx = 24,
		IconPx = 18, AbovePx = 8, WidthPx = 250, ShortWidthPx = 210 },
	Chip = { HeightPx = 40, ShortHeightPx = 30, TextPx = 18, ShortTextPx = 14,
		WidestText = "2x CANDY 23:59:59", CompactText = "2x 23:59:59", GapPx = 6,
		Color = { 255, 150, 40 }, PulseSeconds = 1.6, PulseScale = 1.05 },
}

-- The Cue Preview (R7, permanent; PLAN §2 "Cue preview"; mock PREV1_cue_preview): a client-only
-- stage far from the lobby seen through the panel's window. Studs, degrees, seconds, pixels.
Config.UI.CuePreview = {
	Enabled = false, -- ON only after it passes on a phone size and with a controller
	Origin = { 2400, 2400, 0 }, -- clear of the map and the Backrooms hall ({0, 2400, 0})
	OutsideTransparency = 0.35, WindowShare = 0.6, ShortWindowShare = 0.56,
	WindowMinShare = 0.5, MinHitPx = 44,
	FovDeg = 40, PitchMinDeg = -10, PitchMaxDeg = 50,
	DragDegPerPx = 0.4, StickDegPerSecond = 120, SpinDecay = 4, IdleResumeSeconds = 3,
	TurnDegPerSecond = 20,
	Tabs = { -- the camera per tab: focus offset from the stage centre, distance, pitch
		Model = { Focus = { 0, 1, 0 }, Distance = 9, Pitch = 12 },
		Trail = { Focus = { 0, 0.5, 0 }, Distance = 8, Pitch = 30 },
		Finisher = { Focus = { 0, 0.5, 0 }, Distance = 4.5, Pitch = 25 },
	},
	StrokeBackSeconds = 0.35, StrokeHitSeconds = 0.1, RollSeconds = 1.2, DropSeconds = 0.15,
	FinisherRollShare = 0.3, FinisherHoldSeconds = 2.2, GapSeconds = 0.6,
	LoadTimeoutSeconds = 8,
	Backdrop = { 18, 22, 44 }, KeyLight = { Brightness = 3, Range = 30, Angle = 60 },
	RimLight = { Color = { 150, 120, 255 }, Brightness = 2, Range = 20 },
}
```

Strings (your own blocks): `BoostPill` = Title "YOUR BOOSTS", Percent "+%d%%", Parts (Vip "VIP",
Group "Group", Plus as the Shop already says it ("Roblox Plus", Strings.luau:898), Friends
"Friends (%d)", Starter "Starter Pack", Party "Money Party"), TimeLeft "%s left", Total "Total",
FriendRule "Each friend in your server +%d%% (max %d)", CandyToo, Get (Group, Friends, Vip).
`CuePreview` = Title "CUE PREVIEW", Tabs (MODEL, TRAIL, FINISHER), Aura "AURA ON"/"AURA OFF",
Equip "EQUIP", Equipped "EQUIPPED", Hint "Drag to rotate", Loading, Button "Preview".

### 2.10 Analytics custom events

- `FriendBoost` (server, Friends.luau, on PlayerRemoving): value = the session's peak counted
  friends 0..4, field a = `Funnel.device(player)`. Measures the share of sessions with a friend
  (unknown today) and so the real money/Candy effect.
- Client-seen, through `TutorialEvent` → `FUNNEL_EVENTS` (TutorialService.luau:770):
  `BoostCardOpened` → `Funnel.event(player, "BoostCard", 1, "Opened", Funnel.device(player))`;
  `CuePreviewCues` / `CuePreviewIndex` / `CuePreviewTrack` → `Funnel.event(player, "CuePreview",
  1, "Opened", <source>, device)`; `CuePreviewEquip` → `"Equip"`. After publishing, the
  coordinator reads them: sessions with 1+ friends, card opens per DAU, preview opens and equips.

### 2.11 Switches

`Config.Economy.FriendBoostEnabled` (the friend part of money AND Candy, the one friend switch:
core's Candy reads it through `Money.friendBoost`; false in the interface commit, true after the
Studio pay check), `Config.UI.BoostPill.Enabled` (false until the four sizes and the pad pass;
off = the VIP tag), `Config.UI.CuePreview.Enabled` (false; true only after phone size +
controller pass, PLAN §2). If the friend check fails its Studio test: leave
`FriendBoostEnabled` false (no friend part in either currency), say so in Requests to core and
the coordinator, keep the pill (its Friends row then never shows).

### 2.12 Edge cases

- Pill: Studio has no friends (FriendsQA); client clock vs server (`GetServerTimeNow`); 0.1 x 3
  rounding ("+30%", never "+29%"); Premium bought mid-session (`MembershipType` signal); InGroup
  only refreshes on join or Claim (the pill shows what is paid, so it agrees); a Party or Starter
  hour ending drops the row on time; screen resize or rotation relays everything; HudFocus hides
  it with money under a menu; on a phone the pill sits in the thumbstick zone as the VIP tag did
  (it only opens on a tap's release); 6 friends show "Friends (6)" at +40% (the footer says max 4).
- In a match at phone size the pill and chip must clear the match HUD (ability bar, power bar,
  buttons); if they cannot, hide the pill (not the chip) in a match on short screens, and say so.
- Chip: core's module missing or erroring (hidden, one warn); a longer text than `WidestText`
  scales down; compact form when space is short; never pops on a text update; the Studio test
  clock (`HwTimeOffset`, core's `Clock`) moves it like the real one.
- Preview: opened twice (switches cue), spammed (debounced), unowned (no Equip), already equipped
  ("EQUIPPED"), a band cue with no trail or finisher (the default style plays), a cue whose
  assets never load (timeout), the table not streamed (slab), Lower effects (the look follows
  Quality), the Night preset (own lights), a match or respawn while open (closes), the screen
  resized while open (relayout + reframe), roaming players in a match (W6) cannot open it
  (`Menus` blocker). Ten open/close cycles leave no stage, no render step, no connections, the
  camera Custom on the humanoid, WalkSpeed and touch controls as before.

## 3. Interfaces

**Deliver FIRST** (small commits, tests green, pushed by 08:15; write "Interfaces ready: <sha>"
in the lane file Status; the coordinator merges 08:15-08:30, then `git fetch && git merge
halloween`):
1. `Money.boostParts(flags) -> { { kind: string, add: number } }`, `Money.friendBoost(count) ->
   number`, `friends` in `Money.Boosts`, the `Config.Economy` friend lines (switch false; the
   only friend numbers, which core's Candy reads through `Money`), tests.
2. The **`FriendsHere`** player attribute (number, uncapped, set by the server, replicated) +
   `Friends.count(player)` + the Studio `FriendsQA` hook.
3. In the lane file (no stub modules, PLAN §5): "the chip shell polls core's
   `RushChip.content(now)` once a second" and the `CuePreview.open(id, opts?) / enabled() /
   isOpen() / close()` signatures with the path `src/client/CuePreview.luau` (from core's
   `src/client/Halloween/*`: `script.Parent.Parent:FindFirstChild("CuePreview")` in a pcall;
   core's track cards call `CuePreview.open(id, ...)` that way once your module exists).
   The real modules land with the pill merge (about 10:00-10:20, beside Cues A's drop 3) and
   the preview merge.

**You consume, each guarded** (a missing piece hides a line, never errors):
- Core `src/shared/Halloween/Event.luau` `Event.isLive(now)` and `Clock.now()`: the card's Candy
  line and the chip's clock.
- Core `src/client/Halloween/RushChip.luau` `RushChip.content(now)`: the chip's words; until it
  lands the chip stays hidden (GuiQA `rushChip` tests the shell).
- Core's `Config.Halloween.CandyIcon`: the chip's icon (missing or `""` → no icon slot).
- Cues A's five Catalog rows (Classic look until each body exists) and bodies: the preview draws
  them through `CueStickBuilder`/`CueSkinLook`; check them after each merge, nothing depends on it.
- Map's `Lighting.Night`: check the stage's lights under Night after that merge.
- Roam + Badges (W6): roaming in a match keeps the pill input-dead and the preview closed.

**Requests to write at the start** (lane file): to core: read the Candy friend and group part
through `Money` (`Money.friendBoost(player:GetAttribute("FriendsHere"))` plus the Group part of
`Money.boostParts`, or `Money.boost({ friends = n, group = inGroup })`; it already treats a
missing or non-number count as 0 and caps at 4), guarded, with no friend or group numbers in
`Config.Halloween` (PLAN §5: one source, one switch `Config.Economy.FriendBoostEnabled` for
both currencies); fill `Config.Halloween.CandyIcon` before gate 1 (the chip shows it); the
track's cue cards call `CuePreview.open(id, { from = "Track", note = ... })` through a guarded
require, their button shown only when `CuePreview.enabled()`; in `HubCorners.padStops` your
event tile is the first entry and the pill goes right after Plus. To the coordinator: the
ECONOMY.md 3.5 and DECISIONS lines for the friend boost; the HUD overlaps among others the
test prints; a touch sweep of the preview in the device emulator (the emulator is not
scriptable from a lane); the HubCorners and Net overlaps with core at merge (your lines are
listed under Shared-file changes).

## 4. Checks

- **Lune:** `tests/money_test.luau` (2.1), `tests/hud_layout_test.luau` (2.4),
  `tests/cue_preview_math_test.luau` (panel rects, camera framing, loop timeline). `tools/lint.sh`
  and `tools/test.sh` green before every commit. `tools/format.sh` on your files only.
- **Studio, your own window only:** list the studios every session and pick `lane-hw-gui.rbxl`;
  Rojo on 34888 only. Console clean at every check.
  - Pay: Play; `FriendsQA count 2` → the pill "+20%", a solo or PC match's pots pay x1.2 against
    the same shot without (console or money difference); VIP + 2 friends x2.2; switch off: +0%,
    no Friends row, pay as today.
  - The four sizes: `tools/halloween/studio_size.sh lane-hw-gui.rbxl <w> <h>`, read
    `workspace.CurrentCamera.ViewportSize` through MCP and adjust until it reads 844x390,
    1024x768, 1920x1080; TV = 1920x1080 with GuiQA `pad`. At each: VIP and not (GuiQA `boosts`),
    the chip with both texts (GuiQA `rushChip`), hotbar 0/3/9 blocks, WinTrack open; GuiQA
    `hudOverlap` empty for pill and chip; screenshots. A match at phone size (2.12). If a size
    cannot be reached (screen too small, macOS permission), rely on the Lune test for it and say
    so in the lane file; the coordinator sweeps every device at the end.
  - Pad: D-pad left reaches the pill, A opens, B closes, walking unaffected; GuiQA `boostPerks`
    shows the VIP card path.
  - **Fresh-player run** (this touches the HUD in the tutorial and match pay): a fresh save →
    join → tutorial (no pill) → finish, and once more with skip → the pill pops in → first match
    pays → the popups come as before; console clean.
  - Preview: open from My Cues and the Index, every tab, mouse drag; pad through GuiQA `pad`
    (LB/RB/A/B) and a GuiQA `previewTurn(deg)` that goes through the same turning code as the
    stick (the real stick and touch: the coordinator's sweep or Justin at 17:00); 10 open/close
    cycles with a GuiQA `previewLeaks` (stage gone, render step unbound, connections 0, camera
    and walking restored) and `collectgarbage("count")` steady; close on a match start and on a
    respawn (`Humanoid.Health = 0` in Play); Classic, EclipseCue, BetaCue, GrandOpeningCue, and
    the Halloween cues once merged (beside their concept images); at the four sizes.
- **Screenshots:** `~/Desktop/8ball-refs/halloween/shots/hw-gui/` (`gate1/`, `gate2/`,
  `final/`), named `<feature>-<size>-<case>.png`, one line each in the lane file's Gate shots.

## 5. Cut order (a cut is switched off and listed, never half-visible)

1. The preview's AURA toggle (not built).
2. The card's grey "boosts you could get" rows (active rows only).
3. The Index entry point (My Cues + the public `open` for core stay).
4. The FINISHER tab's own camera (two tabs; the finisher still ends the TRAIL loop).
5. The cloned table (the felt slab stage).
6. The whole Cue Preview: `Enabled = false`, every Preview button hidden by `enabled()`, the
   module kept for the next update.

Never cut: the interfaces, the friend boost (only switched off if its pay check fails), the pill
and card, the chip shell, the layout test, pad access to the pill.

## 6. Gates

- **09:00, gate 1** (`shots/hw-gui/gate1/`): the pill at 844x390 without VIP ("+20%", 2 faked
  friends) and with VIP (crown, "+120%"), the card open, the chip shell above ("2x CANDY 8:12"
  through GuiQA `rushChip`; Progress step 7 builds it before this gate), each next to H1; one
  1920x1080 shot. One question if needed: "+0%" dimmed or hidden at zero?
- **11:00, gate 2** (`gate2/`): pill and chip at the four sizes and the pad selection on the
  pill; the card with VIP + Group + Friends (2); the friend-boost pay check line; the Cue
  Preview's first look (MODEL, and a TRAIL frame if built) at phone and PC sizes.
- **Final, by 16:00** (`final/`): the four sizes; the preview's three tabs with two Halloween
  cues; the preview switch decision and its reason.

## Progress

- [x] 1. Setup: §0 read, the mocks studied; `lane-hw-gui.rbxl` found, Rojo 34888 connected, Play clean; `git log -1` on `halloween`; the §3 Requests written in the lane file.
- [x] 2. INTERFACE: `Money.friendBoost`, `Money.boostParts`, `friends` in `Money.Boosts`, `Money.boost` as their sum, the `Config.Economy` friend lines (switch false), money_test cases; lint, tests, commit, push.
- [x] 3. INTERFACE: `FriendsHere` count, `Friends.count`, one retry, Studio `FriendsQA`; checked in Studio; pushed by 08:15; lane file "Interfaces ready: <sha>" plus the chip contract and the `CuePreview` signatures.
- [x] 4. `BoostFlags.of` and `Economy.boost` through it; Studio pay check (x1.2, x2.2, switch off = today); the `FriendBoost` event; the R5.2 money note; switch true; push.
- [x] 5. `HudLayout` pure module and `tests/hud_layout_test.luau` at the four sizes, every case; the others' existing overlaps written as a Request.
- [x] 6. BoostPill: pill (crown or arrow, "+N%", count-up pop), YOUR BOOSTS card, hover/tap/pin, tutorial gate, `setInMatch`, the VipTag shape and `deps.vipTag`, LuckClover beside it, Config and Strings blocks, GuiQA hooks.
- [x] 7. Rush chip shell (before gate 1, which shows it): polls core's `RushChip.content` each second (guarded, hidden when missing or nil), pop then pulse, compact form, the icon from `Config.Halloween.CandyIcon` (guarded, slot collapses when missing or ""), GuiQA `rushChip`.
- [x] 8. Gate 1 (09:00; PC-window shots only, the phone size is not reachable from this lane: lane file Status) : phone and PC shots in `gate1/` (pill, card, the chip shell through GuiQA `rushChip`), lines in the lane file, the one question if needed.
- [x] 9. Pad and lists: the pill as one `HubCorners.padStops` entry right after Plus (core's event tile stays first), your `blurPad` and `padFocusedOn` lines, each listed under Shared-file changes; MenuColumn and PadGuide names; the `BoostCardOpened` event; GuiQA `hudRects` and `hudOverlap`.
- [x] 10. (sizes by the layout test only, see lane Status) Studio sweep of the pill: four sizes and pad, `hudOverlap` empty, a match at phone size, the fresh-player run (tutorial and skip); `BoostPill.Enabled = true`; push; lane file asks the coordinator to merge it (the pill merge, about 10:00-10:20).
- [x] 11. `CuePreviewMath` (panel rects, window framing, loop timeline) and `tests/cue_preview_math_test.luau`.
- [x] 12. CuePreview core: registered menu and `CuePreviewMenu` gui, the stage at Origin (stripped table clone or slab, lights, backdrop), camera taken and restored, walking and touch controls held, MODEL tab with auto-turn and drag by mouse, touch and right stick, every close path; switch off.
- [ ] 13. Gate 2 (11:00): the pill at the four sizes and on the pad, the card with VIP/Group/Friends (2), the preview's first look at phone and PC in `gate2/`.
- [x] 14. TRAIL and FINISHER: stroke, trail, pocket, finisher loop through Effects; the preview's cue in Main's holdShots; spinner and timeout.
- [x] 15. The preview screen per lively-gui: header, window, info sheet (name, rarity pill, note), tabs on LB/RB, EQUIP (EquipCue, EQUIPPED, hidden when not owned), red X, B and Escape, Strings, open animation, the `CuePreview*` events.
- [x] 16. Entry points: Preview in the My Cues detail and the Index detail (only when `enabled()`), each returning where it came from; the public API confirmed in the lane file for core.
- [x] 17. Preview checks: four sizes, pad hooks, 10 cycles with no leaks, closes on match start and respawn, Classic/Eclipse/Beta/Grand Opening and the merged Halloween cues; coordinator touch sweep requested; switch ON only if phone and controller pass, else OFF with the reason.
- [x] 18. R1.10, R5.1-R5.7, R7.1-R7.2 checked one by one with results in the lane file; every shared-file change listed; lint and tests green.
- [ ] 19. Lane file Status final + all screenshots (gate1, gate2, final) with one line each.
- [ ] 20. Merge halloween (`git fetch && git merge halloween`), re-test (lint, tests, a Studio pass of the pill and the preview, and the chip with core's real `RushChip.content` and `CandyIcon` on the Studio test clock; if core's module is not in `halloween` yet, write that in the lane file Status), push.

## Notes
