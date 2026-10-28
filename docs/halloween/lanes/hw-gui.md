# Lane hw-gui (W7 Boost pill + Cue Preview)

Folder `~/Desktop/8ball-hw-gui`, branch `hw-gui`, Rojo 34888, Studio `place/lane-hw-gui.rbxl`,
Opus 5.5 xhigh. Brief: `docs/prompts/HW_GUI_PROMPT.md`. Contract: `docs/halloween/PLAN.md`.
Launch and restart line: exactly what `tools/halloween/lanes.sh command hw-gui` prints (never
your own flags). Waiting file: `touch "$(git rev-parse --absolute-git-dir)/overnight-waiting"`.

## Owns

From PLAN §4 (everything else is read-only; ask below under Requests):

- `Money.boostParts`, `Money.friendBoost` and the friends part of `Money.boost`
  (`src/shared/Progression/Money.luau`) and of `Economy.boost` (`src/server/Economy.luau`), with
  the new `src/shared/Progression/BoostFlags.luau`; the `Config.Economy` friend lines
  (`FriendBoostEnabled`, `FriendBoost`, `FriendBoostMaxFriends`, `FriendRetrySeconds`): the
  only friend-boost numbers and the one friend switch for money AND Candy (core reads them and
  the existing `GroupBoost` through `Money.friendBoost` / `Money.boostParts`).
- The `FriendsHere` count in `src/server/Friends.luau` (`Friends.count`, the Studio `FriendsQA`
  hook, the `FriendBoost` analytics event).
- `Config.UI.BoostPill`, `Strings.BoostPill`; the pill + its "YOUR BOOSTS" card + the Rush chip's
  SHELL and position (`src/client/BoostPill.luau`; it replaces the VIP tag in the row above
  money; core fills the chip's words through `RushChip.content`; its icon is core's
  `Config.Halloween.CandyIcon`, read guarded).
- The pure HUD layout function `src/shared/HudLayout.luau` + `tests/hud_layout_test.luau`.
- `src/client/CuePreview.luau`, `src/shared/CuePreviewMath.luau`,
  `tests/cue_preview_math_test.luau`, `Config.UI.CuePreview`, `Strings.CuePreview`, the Preview
  buttons in My Cues (`InventoryCues.luau`) and the Index (`InventoryIndex.luau`).
- Not yours: the chip's words and timing, Candy maths and `Config.Halloween` incl. `CandyIcon`
  (core); the event tile and its FIRST place in `HubCorners.padStops` (core); the track cards'
  Preview button, which calls your `CuePreview.open` through a guarded require (core);
  `TableService.luau` (Roam + Badges); the custom-model cue path and `CueAssets` (Cues A);
  `docs/STATUS.md`, `ROADMAP.md`, `DECISIONS.md`, `ECONOMY.md` (coordinator).

## Status

- **10:00 Cue Preview steps 12, 14-16 done (switch still OFF, `Config.UI.CuePreview.Enabled =
  false`).** Checked in Studio at 1523x814 with it switched on locally:
  - **Core (12):** the stage at Origin (stripped clone of a lobby table, lights, backdrop), MODEL
    turning, drag (GuiQA `previewDrag 100,20`: 40 deg yaw, 8 deg pitch, a flick spin, through the
    drag's own function), right stick (`previewTurn 90`: 90 deg), LB/RB bound. Closes on the X
    and Menus' close (B, Escape), a match start (solo fixture: closed, reopen refused at the
    table), a death and a respawn. 10 open/close cycles: camera Custom on the live body, walking
    20.8, touch back, render step unbound, 0 connections, stage and gui gone, memory lower than
    before. **Found and fixed:** opened over a Scriptable camera it handed back a Scriptable
    (frozen) camera; it now never does and follows the current body (as Camera and Freecam do).
  - **Loop (14):** TRAIL (stroke, trail, pocket, finisher) and FINISHER through Effects; FINISHER
    framed at 9 studs so Eclipse's finisher fits whole. TRAIL/FINISHER wait for
    `CueAssets.shotReady` as well as the look; spinner in the window while loading, the stick
    hidden; after 8 s it plays anyway (GuiQA `previewLoad true` stalls it: spinner on, stick
    hidden, then shown at the timeout). Main's holdShots line: Eclipse (not equipped) kept its
    shot effects 80 s with the preview open (past the 60 s keep).
  - **Screen (15):** the lively chrome by hand (no MenuFrame: its blur would blur the stage):
    the veil fades, the panel unrolls (overshoot), the window opens on the stage, the pieces
    pop in (`Config.UI.CuePreview.Open`, 0.7 s), the header's 8-balls scroll, the sheet's dots,
    the title's cue icon, the lit tab's icon and the 8-ball flair rock (the flair hops with a
    sparkle); a close folds the panel back (0.15 s) while the camera is already given back;
    open/close spam ends clean. EQUIP: green, grey EQUIPPED (Classic), hidden when not owned and
    `opts.note` takes its place (checked with "Track: 2,000 Candy"). Strings in
    `Strings.CuePreview`.
  - **Entry points (16):** My Cues big card: Preview beside Equip (Equip keeps 58% of the row);
    Index detail: Preview under the name; both only while `CuePreview.enabled()` (switch off =
    today's layout exactly). Closing comes back to the big card / the Index on that cue unless
    another menu took over. Events log: `CuePreview [Opened, Cues, PC]`, `[Opened, Index, PC]`.
  - **API for core, confirmed (unchanged):** `CuePreview.open(id, { from = "Track", note = ...,
    onClose = ... }) -> boolean` (false when switched off, in a match, under a popup or reel, an
    unknown id, or opened again within 0.3 s), `enabled()`, `isOpen()`, `close()`. Require it
    guarded from `src/client/Halloween/*` as
    `script.Parent.Parent:FindFirstChild("CuePreview")`; show the track card's Preview only
    when `enabled()`. `from = "Track"` logs `CuePreview [Opened, Track, device]`.
- 09:40 to the coordinator's 09:12 notes. **b3bb0288 switches on one thing:**
  `Config.Economy.FriendBoostEnabled = true`, +10% of base MATCH money per Roblox friend in the
  server (max 4), added to the other boosts like Group's; rewards, WinTrack, packs and sell-back
  never read it. **Old pay unchanged:** `Money.boost` keeps the old sum order and adds the friend
  part last (`+ 0` with no friends), the old `tests/money_test.luau` cases pass untouched, and in
  Studio the same player paid +20% (Group + Plus) with `FriendsHere` 0 before and after; 2 friends
  +40%; switch off at 2 friends +20%. **Friends.luau requests done** (`c44206f9`, `a69838e9`,
  `e47586f8`): the FriendBoost event clears Funnel's log line after it (no leaked
  Player whichever PlayerRemoving runs first); the `or 4` / `or 30` fallbacks are gone; an
  answer that comes back after either player left is dropped (no stale failure, a rejoin asks
  afresh). FYI, not mine: `Funnel.left` (TutorialLeft, from TutorialService's PlayerRemoving)
  has the same log-line pattern.
- 09:22 coordinator: halloween @403da7da has cues-a drop 2 (skin keys, --also-manifest, budget stop, the builder ONLY filter, Aim joint; Firework row unchanged but a comment); lint OK, 1370 tests, Studio synced. Run `git fetch && git merge origin/halloween`. Cues B: you can generate rows now.
- 09:12 coordinator: halloween @792bbb35 has every lane's interfaces (sys 1c9f99b7, core 1c9945a0, cues-a drop 1 1039f19b, gui b2c51102, map 6d45e218); lint OK, 1370 tests, Studio boot clean. Run `git fetch && git merge origin/halloween` now. Gate 1 is at 10:00: shots + one caption line each in your Gate shots by 09:55.
- 09:12 coordinator: merged up to b2c51102 only. b3bb0288 ("Friend boost on") is NOT merged yet: it changes live money pay, so it goes through its own review with the pill; say in Status what it switches on and how you verified old pay is unchanged. REQUESTS (minor): Friends.luau PlayerRemoving calls Funnel.event after Funnel may have cleared the player's log (keep() re-creates logs[player], leaking a Player for the server's life): send it before or guard; drop the `or 4` / `or 30` literal fallbacks (:60, :94); a pair erroring while one player leaves keeps a stale failures entry (no retry on rejoin).
- 09:05 coordinator REQUEST (all lanes, blocks a merge): `src/client/Main.client.luau` is 12-14 top-level locals from Luau's 200-local limit; past it the client fails to compile in Studio and live and lint/tests stay green. Put every Main.client addition inside `do ... end` (zero new top-level locals), e.g. `do local ok, err = pcall(...) ... end`. New test `tests/client_compiles_test.luau` (on halloween @HEAD) compiles every src script and fails if Main.client has fewer than 8 locals left; run it before you push.
- **Interfaces ready: 0119a786** (pushed 08:58 EDT, late against 08:15: the lane started 08:43).
  - `37d80752` `Money.friendBoost(count) -> number`, `Money.boostParts(flags) -> { { kind, add } }`
    (order Vip, Group, Plus, Friends, Starter, Party; active parts only; fresh table),
    `friends: number?` in `Money.Boosts`, `Money.boost` = their sum (old sum order kept, so old
    pay is bit for bit the same). `Config.Economy.FriendBoostEnabled = false` (switch),
    `FriendBoost = 0.1`, `FriendBoostMaxFriends = 4`, `FriendRetrySeconds = 30`. Tests in
    `tests/money_test.luau` (2 new cases; suite 1347/1347).
  - `0119a786` `FriendsHere` player attribute (number, uncapped, server-set, replicated; checked
    in Studio: 0 → `FriendsQA count 2` → 2 on server and client → nil → 0), `Friends.count(player)`,
    one retry after `FriendRetrySeconds`, Studio `ServerStorage.FriendsQA` `("count", player or
    userId, n?)`, the `FriendBoost` custom event on leaving.
  - **Chip contract (no stub module):** the Rush chip shell (in `src/client/BoostPill.luau`) polls
    core's `src/client/Halloween/RushChip.luau` `RushChip.content(now) -> { text: string,
    endsAt: number }?` once a second through a guarded require
    (`script.Parent:FindFirstChild("Halloween")` → `RushChip`, in a pcall; `now` from
    `Shared.Halloween.Clock.now()`, else `workspace:GetServerTimeNow()`). Missing, error or nil →
    hidden. Icon: `Config.Halloween.CandyIcon` (guarded; missing or `""` → no icon slot).
  - **CuePreview signatures** (module `src/client/CuePreview.luau`, lands with the preview merge):
    `CuePreview.open(id: string, opts: { from: string?, onClose: (() -> ())?, note: string? }?)
    -> boolean`, `CuePreview.enabled() -> boolean`, `CuePreview.isOpen() -> boolean`,
    `CuePreview.close()`. From core's `src/client/Halloween/*`:
    `script.Parent.Parent:FindFirstChild("CuePreview")`, required in a pcall; show the track
    card's Preview button only when `CuePreview.enabled()`.

- 08:50 coordinator: lanes started 08:43 (73 min behind the plan). New times: interface commits as soon as they pass (target 09:30, merged by 09:45); gate 1 at 10:00 (shots + captions by 09:55); gate 2 at 11:15 with whatever is ready (Justin sleeps after it); merges on request all day; 16:00 done/cut and the 17:00 freeze stay for now (re-timed at 13:00 if needed). Rojo: a watchdog restarts any crashed server by itself (log ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log; Rojo 7.7 can panic on an editor temp file); if MCP shows your window no longer syncs (append a comment, read it back), write `ROJO RECONNECT` in your Requests and keep working on files. Resize helper: not yet (Studio windows were full screen; Justin is un-fullscreening them); use your layout tests until the outer sizes are posted here.
- **Step 4 (friend boost live in code):** `BoostFlags.of(player, now)` (new
  `src/shared/Progression/BoostFlags.luau`) is the one reader; `Economy.boost(player)` =
  `Money.boost(BoostFlags.of(player, os.time()))`. **Studio pay check** (Server datamodel, the
  live player's attributes through the same modules; this Studio player is in the group and
  Premium, so its base is +20%): 0 friends +20% → `FriendsQA count 2` +40% (a $100 ball pays
  $140 instead of $120, x1.4/1.2 = the friend part's exact +0.2) → VIP + 2 friends +140% → 7
  friends capped at +160% (VIP+Group+Plus+40%) → switch off: +120%, no friend part. Console
  clean (only the usual Studio DataStore lines). `FriendBoostEnabled = true`. A played match's
  pay is covered by the fresh-player run at step 10.
- **R5.2 money effect (record, hand maths; `docs/ECONOMY.md` 3.5's rule: boosts add, then x(1+boost)):**
  the friend part only reaches match money (every shot, match bonus, streak bonus), never
  rewards, WinTrack, packs or sell-back. Nobody measures friends in a server today, so assume
  15% of sessions with 1 friend and 5% with 2+ (avg 2.5 → +25%): the average friend part is
  0.15 x 0.10 + 0.05 x 0.25 = **+0.0275 of base match money (about +2.75%)**, less once divided
  by today's average (1 + boost) (VIP/Group/Plus already ≈ +0.2–0.3 on average) → **about +2–2.5%
  more match money in the game**. Worst case a 4-friend party: +40% of base for those players
  (a VIP in that party: x2.4 instead of x2.0, +20%). The `FriendBoost` event (session peak
  0..4 and device, logged on leaving) gives the real share after publishing.

- **Steps 5-7 (HUD layout, BoostPill, Rush chip shell):** `src/shared/HudLayout.luau` +
  `tests/hud_layout_test.luau` (5 HUD areas x 288 cases: pill and chip inside and >= 2 px clear
  of money, Invite, Plus, hotbar, WinTrack, column; card inside). `src/client/BoostPill.luau`
  (pill, card, chip shell, GuiQA `boosts`, `boostCard`, `boostPerks`, `rushChip`, `hudRects`,
  `hudOverlap`); `Config.UI.BoostPill` (still `Enabled = false` until step 10), `Strings.BoostPill`.
  Seen in Studio at 1523x814 (PC-sized window): "+20%" with the green arrow, VIP "+130%" with
  the rocking crown, the card as H1, the chip "2x CANDY 8:12" over the pill, `hudOverlap` empty,
  console clean. On a phone the layout test puts the pill right of the left column (x 94 on
  750x311) and the chip compact ("2x 8:12") when the WinTrack is open; on Oct 31's long clock
  with the WinTrack open on a phone the chip rises over the WinTrack (last resort).
- **Device sizes: the Studio resize helper cannot run from this lane.** System Events lists the
  Studio processes but no windows (Terminal lacks Accessibility for window control), so
  `tools/halloween/studio_size.sh` finds nothing. Phone (844x390, 844x332, 1334x750), iPad and
  TV sizes are covered by `tests/hud_layout_test.luau` with the real Config numbers; Studio shots
  are at this window's 1523x814. The coordinator's device sweep must cover the pill, card and
  chip at phone and iPad sizes (Request below).

- **Steps 9-10 (pad, sweep): pill ON (`Config.UI.BoostPill.Enabled = true`). Ready for the pill
  merge.** Checked in Studio (1523x814 window): D-pad left (GuiQA `pad DPadLeft`) focuses the
  corners and the pill becomes a stop (`Selectable` true, `SelectionImageObject` the corners'
  ring); selected, it stays held (`padFocusedOn`); D-pad left again (the `blurPad` B uses)
  closes its card, drops the selection and makes it unselectable; walking unaffected
  (WalkSpeed 20.8). Studio's simulated gamepad keys reach no button (A did not fire Invite
  either), so a real A press and B on a pad are for the coordinator's sweep. Tutorial: hidden
  at Arrow, pops in at Done and after a real Skip (fresh save, `TutorialEvent "Skip"`); console
  clean; the `BoostCard` custom event logs on the first open. In a match (solo fixture) the pill
  and chip show, `Active` false, clear of the spin widget and ability bar at this size. Not
  reachable here: the four device sizes and a phone-size match (layout test only), a played
  shot's pay (the fixture's solo break pocketed nothing; the pay path is checked through
  `Economy.boost` and the money tests).
- 09:52 coordinator: **merged f2562efb** into `halloween` (pill ON, friend boost ON, Cue Preview core off). I add the friend boost's ECONOMY.md 3.5 and DECISIONS lines myself. Please fix:
  1. **(before go-live)** `BoostPill.showPerks` does nothing while the pill is hidden, and `allowed()` hides it for the whole Soft step (until game 2). A VIP bought during Soft gets no HUD confirmation (VipTag forced itself on and opened its card), and VIPs still in Soft lose the tag they see today. Show the pill when Vip is true, or let `showPerks` force it like VipTag did.
  2. The card goes off the HUD area on short phones with 5+ rows (844x390: 23 px over; all 6 parts: 47 px). Drop FriendRule/CandyToo too when it does not fit, or cap the rows.
  3. `BoostCardOpened` counts a mouse hover and the after-purchase auto-open; count only tap/click/A opens.
  4. Rush chip: `refresh` pops the chip in without `breathe(true)` (flat orange all of Oct 31), and the hide path leaves the breathe tween running.
  5. The ` · ` separator (~550) into a `Strings.BoostPill` pattern.
- 09:55 coordinator: `halloween` @82ab885c (+ docs f8566968) has core interface 2 (7f01d27b: Halloween save field, CandyService, /hw; switches off), sys 4cdf5620 (roam off, badges off) and gui f2562efb (boost pill ON, friend boost ON, Cue Preview core off). Lint OK, 1,404 tests, Studio play console clean, pill shows +120%. Run `git fetch && git merge origin/halloween` before your next READY. Main.client still has 12 top-level locals to spare: hooks stay inside `do ... end`.

## Shared-file changes

PLAN §7 shared files: your own block or line only; the coordinator resolves overlaps. Planned
(add the commit sha as each lands, plus any other existing line you had to change):

- `Progression.luau` (shared): `local BoostPill = require(...)` beside LuckClover's; the
  `vipTag = if Config.UI.BoostPill.Enabled then BoostPill.new(money) else VipTag.new(money)`
  line (was `VipTag.new(money)`); `boostPill = ...` in `deps`. `vipTag:setInMatch` untouched (the
  pill has the same method).
- `MenuColumn.luau` (not in PLAN's shared list; brief 2.7): the keep-above name lists at the
  constructor and `moneyTop` gain `"BoostPill", "RushChip"`; `moneyTop` now skips a tag lying
  wholly right of the column (a phone's pill and chip), so the column never lifts for them.
  VipTag and LuckClover sit over the column's x, so their behaviour is unchanged.
- `PadGuide.luau`: its keep-above list gains `"BoostPill", "RushChip"`.
- `TutorialService.luau` `FUNNEL_EVENTS`: `BoostCardOpened`, `CuePreviewCues`,
  `CuePreviewIndex`, `CuePreviewTrack`, `CuePreviewEquip` (custom events `BoostCard` and
  `CuePreview`).
- `HubCorners.luau` (core edits it too) **b0674d4c**: the pill as ONE `padStops` entry right after
  `self.plusTile.button` (core's event tile is the first entry, its line); the same entry in
  `blurPad`'s list plus `deps.boostPill:closeCard()` after it; `padFocusedOn` also holds the pill
  (it lives in money's root); in `new`, the pill gets the corners' pad ring
  (`SelectionImageObject = padRing()`). The two lists gained `:: { GuiObject }` casts.
- `Net.luau:395` (core and map edit it too): the new event names in the comment only.
- `Config.luau`: the `Config.Economy` friend lines after `PlusBoost` (**37d80752**, added only);
  `Config.UI.BoostPill` and `Config.UI.CuePreview` after `Config.UI.LuckClover` (**3fd23656**).
- `Strings.luau`: `Strings.BoostPill`, `Strings.CuePreview` after `LuckClover` (**3fd23656**).
- `Progression.luau`: :265-267, :302-309 (BoostPill instead of VipTag, `deps`), :615
  (`setInMatch`, `CuePreview.close()`).
- `Main.client.luau:1265` (**618bbcf1**): inside `holdShots` (no top-level local), the open
  preview's cue (`CuePreviewId` attribute) joins `ids`.
- `Progression.luau` (**618bbcf1**): `local CuePreview = require(...)` after BoostPill's;
  `CuePreview.close()` in `closeScreens()`.
- `InventoryCues.luau`, `InventoryIndex.luau` (mine per PLAN §4, the Preview buttons): a
  `CuePreview` and `GuiQA` require each; the Preview candy, its place in `arrangeDetail`, an
  `openPreview` method, a Studio-only GuiQA hook (`cuesPreview`, `indexPreview`); My Cues'
  gamepad first-selection list gains `self.preview`; the Index gains a `Menus` require.

## Requests

- **To core (hw-core):** read the Candy friend and group part through `Money`, guarded:
  `Money.boost({ friends = player:GetAttribute("FriendsHere"), group = player:GetAttribute("InGroup") == true })`
  (or `Money.friendBoost(n)` plus the Group part of `Money.boostParts`). It already treats a
  missing or non-number count as 0 and caps at 4. No friend or group numbers in
  `Config.Halloween`: one source, one switch (`Config.Economy.FriendBoostEnabled`) for both
  currencies (PLAN §5).
- **To core:** fill `Config.Halloween.CandyIcon` before gate 1 (the Rush chip shows it).
- **To core:** the track's cue cards call `CuePreview.open(id, { from = "Track", note = ... })`
  through a guarded require, their button shown only when `CuePreview.enabled()`.
- **To core:** in `HubCorners.padStops` your event tile is the FIRST entry; the pill goes right
  after `self.plusTile.button` (my one line).
- **To the coordinator:** the `docs/ECONOMY.md` 3.5 and `DECISIONS.md` lines for the friend boost
  (+10% a friend in the server, max 4, added, permanent, money and Candy, own switch
  `Config.Economy.FriendBoostEnabled`).
- **To the coordinator:** HUD overlaps among the pieces there TODAY (not the pill or chip), as
  `tests/hud_layout_test.luau` prints them from Config (not fixed by this lane):
  iPad 1024x768: the 9-slot hotbar overlaps the money HUD, Invite and the Plus tile;
  phones 844x390 and 1334x750: the hotbar (3 or 9 slots) touches the Plus tile. Worth a look
  in the device sweep (a player holding blocks on an iPad).
- **To the coordinator:** the device sweep must cover the pill, its card and the Rush chip at
  844x390 and 1024x768 (this lane could not resize Studio: no Accessibility for window control).
- **To the coordinator:** a touch sweep of the Cue Preview in the device emulator (not scriptable
  from a lane).
- **To the coordinator (09:09): please merge `hw-gui` for the pill** (BoostPill ON, friend boost
  ON, HudLayout, pad stop, events). After the merge core's `RushChip.content` and
  `CandyIcon` light the chip up by themselves; nothing else to wire.
- **To the coordinator:** the HubCorners and Net overlaps with core at merge (my lines are listed
  under Shared-file changes).

## Assumptions

- 09:55 "+0%" at zero boosts: **shown, dimmed** (`ShowAtZero = true`, the brief's default) so a
  player with no boost still finds the card and its "Join the group: +10%" / "Friends here" /
  "VIP" lines. One switch to hide it (`Config.UI.BoostPill.ShowAtZero = false`). Asked as the
  gate-1 question below rather than stopping the lane on it.
- The chip's idle is a gentle colour breathe, not a scale pulse (UI taste rule: text never
  pulses its scale endlessly); `PulseSeconds` is the breathe's period.

## Gate shots

Gate 1 (`~/Desktop/8ball-refs/halloween/shots/hw-gui/gate1/`, Studio window 1523x814; the phone
size could not be reached, see Status):
- `pill-1523x814-novip-2friends-chip.jpg`: no VIP, 2 faked friends: green arrow "+20%" in the
  white pill over the money pill (VIP tag's place), the orange "2x CANDY 8:12" chip over it
  (no candy icon yet: core's `Config.Halloween.CandyIcon` not merged, the text centres).
  Compare H1: same look, the pill in the row above money as PLAN §2 says.
- `pill-1523x814-vip-group-2friends-card.jpg`: VIP + Group + 2 friends: crown "+130%", the
  "YOUR BOOSTS" card open (VIP +100%, Group +10%, Friends (2) +20%, rule, Total +130%, "Each
  friend in your server +10% (max 4)", grey "Friends here: +10% each"). The open card covers
  the chip (a popup).
- **Question for Justin (one):** at zero boosts, show "+0%" dimmed (now) or hide the pill?
