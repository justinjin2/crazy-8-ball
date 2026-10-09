# Economy v5 for release: every screen, then the checks (an attended run)

Written 2026-10-09 by the designer (Justin, Roblox name Painicane) with Claude. You are a Claude
Code session in `~/Desktop/8ball` on branch `gui-v4`. Economy v5, "every block climbs", is built
underneath (Config, the shared rules, the server, saves v11, the model, `docs/ECONOMY.md`) and
its **Robux prices are live on Roblox**. What is missing is the **screens**: today's client still
shows v4 and runs on ten small shims. Your job:

1. rebuild **every screen** the economy touches so the game shows v5 exactly (the list:
   section 3, the per-screen spec: `docs/prompts/ECONOMY_V5_HANDOFF.md` section 1, the audit of
   every leftover: section 4),
2. remove each shim as its screen lands,
3. add the one missing server piece (the tutorial's scripted climb, step 1),
4. check everything in Studio on phone, PC and gamepad (the report's "try in Studio" list),
5. leave the game ready to publish for release.

**The designer is here and approves each screen.** Their rule (2026-10-08): **a concept of
each screen first, approved, then built, one screen at a time**; never batch-build screens they
have not seen. Follow the project skill `.claude/skills/lively-gui/SKILL.md` and its gates.
While a concept waits for their pick you may do non-GUI work (step 1, tests, the audit list), but
never build an unapproved screen.

---

## 0. Where you work, and what you never touch

- **Your folder:** `~/Desktop/8ball`, branch `gui-v4`. Commit and push only `gui-v4`. Never
  push or change `main`, `release`, `tutorial-v2`, `before-economy-v5` or any other branch; never
  force-push or rewrite history.
- **`place/8ball.rbxl` has the designer's own uncommitted change.** Never stage, commit, stash,
  reset, check out or delete it, until the end (step 15) when the designer saves the place and
  says so. Stage files by name: never `git add -A`, `git add .`, `git commit -a`, `git stash`
  or `git reset --hard`.
- **Other sessions:** `~/Desktop/8ball-tutorial` (branch `tutorial-v2`, Rojo port 34877) may be
  running: never touch it or its Studio window. Studio's MCP mouse input can land in whichever
  Studio window is in front: ask the designer for a quiet minute before any
  `user_mouse_input`, and prefer code-driven checks (GuiQA hooks). Send one `screen_capture` per
  message (several in one message hang).
- **Studio and Rojo:** `rojo serve default.project.json` (port 34872) in the background; the
  designer clicks Connect in the Rojo plugin. Confirm sync with the MCP `script_grep` for a
  string you just added before every playtest. Scripts only under `src/` (never through the MCP).
- **Robux:** the v5 prices are live (designer, 2026-10-09). **Never change a price, create or
  retire a product** unless the designer asks in this run (the one planned change is v4's held
  sync at publish, step 15); never delete one; always dry-run first. Icons for `Mystery5` and
  `LuckyBlockSkip1` are allowed once the designer approves their pictures
  (`python3 tools/roblox_products.py --icons --only Mystery5,LuckyBlockSkip1 --dry-run`, then
  without `--dry-run`). The API key is in the macOS Keychain (`ROBLOX_API_KEY`): never print,
  echo, log or write it. Screens always show Roblox's live price (`ShopState`), never a typed
  number.
- **Images:** new art goes through the skill's art pipeline (`art-pipeline.md`); the spend cap
  is $500 of images unless the designer sets another. Uploads only for pictures the designer
  approved.
- **The economy's numbers are settled.** Never change a Config economy number (odds, prices,
  rewards, timers) to make a screen easier; if a screen shows a number that looks wrong, ask.

---

## 1. How the run goes

For each screen in section 3, in order:

1. **Look first**: open today's screen in Studio (phone emulator and PC), screenshot it, and
   read its handoff entry and its audit lines (section 4).
2. **Gate A, the concept**: a private Artifact page with the finished screen as a picture (real
   cue pictures, real block icons, real words from Strings, the v5 numbers), two or three
   versions when the look is open. Ask at most three short questions. **Stop and wait for the
   designer's pick.** (A small HUD piece or popup: one concept, then straight to gate D. A
   restyle the designer calls "just make it move" keeps its layout: see the memory rule on the
   moving 8-ball frame.)
3. **Build** it to the pick: every number from Config or the shared functions, every word in
   `Strings`, every tunable (sizes, timings) in `Config.UI`, the lively house format (frame,
   entrances, idle).
4. **Gate D, the Studio first look**: playtest it for real (the block flows with real blocks:
   `/giveblock <kind> [count]`), on the phone emulator, PC and a gamepad path; read the
   console; record or screenshot; show the designer; take notes.
5. **Gate E, the final check**: the notes done, Reduce Motion and Lower effects, the console
   clean.
6. **Remove its shim** (the handoff's table, section 1.13) and anything it left unused.
7. `tools/lint.sh`, `tools/test.sh` (add Lune tests for any shared or server change), commit
   (files by name) and push `gui-v4`, tick the step, add a Notes line, and a dated
   `docs/DECISIONS.md` line for every design call the designer made.

**The Stop hook** (this run is started with `--settings tools/overnight/economy_v5_gui.json`,
attended mode): while a Progress box is unticked it sends you back to work when you stop. To
stop and ask the designer something (a gate, a question), first run
`touch .git/overnight-waiting`, then ask; the hook lets that one stop through. Keep going on
your own wherever you can do it at full quality.

**If a step is truly blocked**, tick it `- [x] BLOCKED: <why>`, say why in Notes, and move on.

---

## 2. Read first

- `CLAUDE.md`, then `docs/STATUS.md`.
- **`docs/prompts/ECONOMY_V5_HANDOFF.md`**: section 1 is the spec of every screen (what the
  player sees, what it reads, what it calls, the shim it replaces); section 1.13 the shim
  table; section 2 the tutorial's list; section 4 the Week One Cue's art.
- `docs/prompts/ECONOMY_V5_REPORT.md` (what changed, the "try in Studio" list) and
  `docs/ECONOMY.md` sections 0, 7 (blocks), 9 (the shop), 10 (rewards), 11 (Robux), 12 (trading),
  18 and 19 (the menus, the shims).
- `docs/UI_STYLE.md`, the skill `.claude/skills/lively-gui/SKILL.md` and its reference files
  (`motion.md`, `art-pipeline.md`, `verification.md`, `pitfalls.md`).
- The last week of `docs/DECISIONS.md` (the designer's v5 answers and the GUI notes of
  2026-10-08 and 2026-10-09).
- The code each screen reads: `src/shared/Progression/` (`BlockDrop`, `BlockOdds`,
  `LuckyBlocks`, `Restock`, `ShopView`, `RewardView`, `Daily`, `Trade`), `src/shared/Net.luau`
  (the remotes and their payloads), and the client files named in section 4.

---

## 3. The screens, in order

Each is one Progress step. The spec is the handoff section in brackets.

1. **The server's scripted climb (no GUI).** The designer picked a scripted Mystery block for
   the tutorial's first block (2026-10-09), as `tutorial-v2` already plans: its climb screen
   climbs once, Standard to Uncommon, and it lands ready at once. Replace the `stay` hook of
   `LuckyBlockService.setOpenHooks(force, opened, stay)` with a `script` hook,
   `(player, kind) -> string?`, the forced final tier of that climb (nil: a normal roll), and
   pass it to `PlayerData.climbBlock` (a Mystery uses `BlockDrop.roll`'s `forced` tier, still
   counting pity; any other kind its tier; the climbed block lands ready at once). Keep
   `gui-v4`'s interim tutorial working: `TutorialService.stayFor` becomes a script returning the
   block's own tier. Lune tests. Write the hook's use into the handoff's section 2 for the
   tutorial session.
2. **The climb screen for every block, the unclimbed/climbed mark and the Secret** (1.1, 1.2).
   The biggest screen: `MysteryReveal` for any unclimbed block from its own tier, 4 presses, 7
   tiers with the Secret on top, **no pity on this screen**, the climbed block landing on its
   timer, a Secret result going straight to its pull; OPEN! and a small unclimbed/climbed mark in
   the hotbar and bag. Removes shims 1, 2 and 3.
3. **The quick reveal and "Open all"** (1.3): a 1-2 s reveal for Common and Uncommon results;
   an Open all button by the hotbar or bag with its summary.
4. **Odds & Details for every block** (1.4, 1.6): live odds (the Grand Opening Luck, pity when
   due), an unclimbed block's climb odds or a climbed block's one rarity, every cue's % and
   "1 in N", **the pity bars here** (Rare by 10, Epic by 40, the head start). Removes shim 4.
5. **The Grand Opening Luck clover** (1.5): next to the money and VIP bars, only while the luck
   runs; its popup with the countdown and the two boosted steps.
6. **The shop** (1.8, 1.9): the Mystery band (7 R$ and the 29 R$ 5-pack with their live prices,
   $14,900 and 5 for $66,900, 6 for 5 during the launch bonus, **the pity bars on its card**),
   the restock's three cards (slot 1 "Epic or better", slot 2, VIP's), the VIP card's perk
   text, the Grand Opening card, the Starter Pack card (unchanged odds) and **the timer skip
   dialog** (1 / 4 / 9 / 15 R$ by time left). Removes shims 8 and 9.
7. **The win track and the result screen** (1.10): money tiles between the block tiles, win 10's
   Epic block; the result screen's own "Win track +$1,000" line. Removes shim 5.
8. **Free Reward** (1.11): the first week with the Week One Cue on day 7's card from day 1, the
   later weeks, the 28-day track, five playtime tiles, VIP's Uncommon block, the group's 2
   Mystery blocks, the invite's Uncommon block, Claim All's live prices (later weeks 79 / 69 /
   35 R$). Removes shim 7.
9. **Trading** (1.12): the unclimbed/climbed mark and names, the Week One Cue tradable. Removes
   shim 6.
10. **Cues and the Index** (1.12): the Week One Cue in the Legendary row with "Day 7 of your
    first week" where block cues show odds; every chance chip from `BlockDrop`.
11. **Rank rewards and every other place a block or reward shows** (the Ranked roadmap, NEW
    RANK!, the claim block, reward chips and flyers, the Gift drop, banners): v5 names and
    counts, no v4 odds or floors.
12. **Every word**: a sweep of `src/shared/Strings.luau` and the client for any v4 fact left
    (section 4's word list), each fixed in `Strings`.
13. **The full Studio check** (`ECONOMY_V5_REPORT.md`, "try in Studio"): a Mystery block and a
    tier block from a win (climb, timer, open), the restock (buy one with money), the Mystery
    band, Free Reward's first week, a two-player trade of an unclimbed and a climbed block (Test
    > Clients and Servers > 2 players), the Grand Opening Luck's odds with a test `StartsAt` in a
    Studio test only, `OpenAll`, a few `/giveblock Mythic` for a Secret climb, the tutorial's
    game-1 block. Phone emulator, PC and a gamepad path for every screen. Real Robux purchases
    (the 1 R$ skip, the 29 R$ 5-pack) only if the designer makes them.
14. **The docs:** `docs/ECONOMY.md` (sections 18 and 19: the shims gone, the screens as built),
    `docs/UI_STYLE.md` for any new house piece, `docs/GDD.md` section 12 if a screen's rule
    changed, `docs/ROADMAP.md` 7.9, `docs/STATUS.md` (current state only, under about 100
    lines; move finished entries to `docs/archive/STATUS_HISTORY.md`), the handoff file (what
    is done).
15. **Ready for release:** ask the designer once to save the place to `place/8ball.rbxl` (then
    commit it by name) and to publish; remind them of their release clicks: the Grand
    Opening's `StartsAt` at publish (it also starts the Grand Opening Luck and the launch
    bonus), every random-item developer product **Not Listed** on the Creator Hub (Mystery5 is
    new), the icons. **v4's held product changes** go live at the same moment, with the
    designer's yes: `python3 tools/roblox_products.py --sync --dry-run` lists them (on
    2026-10-09: the Starter Pack 19 -> 29 R$, the money packs' texts, Lucky1 and Lucky3 off
    sale; nothing else), then `--sync`. Tick 7.9 in the roadmap once the designer confirms.

---

## 4. The audit: every place a screen still shows v4

An audit of `src/client`, `Strings` and `Config.UI` (2026-10-09, read-only, line numbers as of
commit time; re-check each before you edit). Each line names the step that fixes it. Fixed
already: `RewardsParts.reward` dropped the server's `cues`, so the Week One Cue showed nowhere
(fixed with this brief; shim 7 now names it in words).

**Step 2, the climb screen (`MysteryReveal.luau`) and the block flow**
- The ladder is `BlockOdds.Order` (6 tiers, :49, :459); v5 is `Config.BlockOdds.Climb.Tiers`
  (7, Secret on top). `Config.LuckyBlocks.Reveal.Ladder` and its comments assume six; there is
  no `Reveal.Tiers.Secret` look and no Secret icon (`iconOf` :96, `look()` :101 falls back to
  Standard).
- Mystery only: the pill "Mystery Lucky Block - n/4" (:52, :924), the tint (:243), the
  "MYSTERY" title (:863-866), the start pose (:1130, :1211, :1252; fallbacks :1448, :1519). A
  tier block must arrive as itself and start from its own tier.
- It reads `reply.tiers` (shim 2, :1100-1108) and refuses a non-block tier; reading `path`
  must accept "Secret". Config `Reveal.Arrive.TitleAt`'s comment still mentions pity counters.
- `LuckyClient:269-272` `isMystery` means `row.Roll` (only Mystery): it gates `revealBlock`
  (:300), `holdBlock` (:320), the gamepad aim (:519). Use `LuckyBlocks.unclimbed`.
- `LuckyClient:654-663` drops `climbed` from BlockState; `LuckyHotbar`'s `Entry` type (:56)
  has no such field; the rebuild key (:441-447) ignores it; no unclimbed/climbed mark.
- `LuckyHotbar:219-233` OPEN! only for Roll kinds (others show READY!, :944-950); `:539-571` a
  tap opens the climb screen only for Roll kinds.
- The Secret shim (`LuckyClient:79-95, 347-354, 555-556, 572-575`): the Secret reel plays after
  the climb or Hold on the "Mythic" row, so the Secret cue is not on the strip.
- GuiQA's "mystery" test (`LuckyClient:589-592`) sends a fake `tiers` and v4's pity `{3, 87}`.

**Step 3, the quick reveal and Open all**
- `LuckyOpening.luau` `play` (:159-201) and `startReel` (:221-275) always run the full
  BlockReel; the `LuckyBlocks.quickReveal(rarity)` branch belongs there. :174 does nothing for
  kinds without `Odds` (Mystery, Lucky 8, Sky, Gift).
- `BlockReel.luau:86-102` builds the strip from the climbed row, now one rarity, so every card
  is the same rarity; the showcase card (:327-345) only for Epic and up.
- No Open all button or request exists; natural homes: the bag button (`LuckyHotbar:275-305`)
  or the bag panel (`buildBag` :360-410). Its Strings exist (1018-1021). The summary screen is
  new.

**Step 4, Odds & Details**
- `OddsDetails.luau:392-437` (`blockSpec`): every tier kind shows its climb, right for an
  unclimbed block, wrong for a climbed one (the skip dialog `LuckyHotbar:879-894`, trades).
  One bar per rarity, no per-cue % or "1 in N"; the repaint key (:399-405) has no luck.
- `ShopMysteryOdds.luau`: tier bars (:105-116, no Secret icon), the pity meters (:117-127, the
  place for the pity bars), no cue list, the key (:54-60) has no luck, the header (:8) says
  "56/100".
- Opened from ShopMenu:128, FreeRewardMenu:118-126, the skip dialog, ShopOffers:286 and :326.

**Step 5, the clover**
- `MoneyHud.new` (`MoneyHud.luau:83-120`, bottom left) holds `VipTag.new(money)`
  (`VipTag.luau:49-66`, `top()` :208), both made at `Progression.luau:240-241`.
  `MenuColumn.luau:211-212, 532` measures the HUD's top through the VipTag: count the clover
  there too. Sizes in `Config.UI.Progress.MoneyHud` and `Config.UI.VipTag`; no Strings yet.

**Step 6, the shop**
- `ShopMystery.luau`: the ladder is built once (:99-129) and `refresh` (:340-412) never shows
  live luck; 7 rows now but `Config.UI.ShopBlocks.Mystery` (height 374, RowTop 17, step 58) fits
  6 and `Config.UI.Shop.Open` stages only Row1..6 and "MysteryX10" (the id is "MysteryX5",
  never staged). A row's dice opens that tier's climb, not its one rarity; the Secret row's
  opens an empty list (:120-124). The "Epic guaranteed in N" strip (:386-411) becomes the two
  pity bars (Rare by 10, Epic by 40, the head start). "Coming soon" for an Id 0 product (:36,
  :355-362; shim 9, Mystery5 has its id now) and the gift square (:377). Header comments say
  "six tiers", "x10", "13 for 10".
- `ShopRestock.luau`: 3 cards drawn (:38) on a 4-card layout (:252; `Config.UI.ShopBlocks.
  Restock` 4 x 297 in 1275; `UI.Shop.Open` stages RestockSlot1..4), the right quarter empty;
  slot 1's placeholder is "Rare" (:140) with no "Epic or better" mark; one odds line (:194,
  shim 8); the OddsY comment says "Each slot: Rare 87%"; header (:4) "three slots".
- `ShopOffers.luau`: comment :21 "VIP's Rare block every day", fallback :156 "Rare".
  `Purchased.luau` (:10, :58) knows "+10 Mystery" only (now 5).
- The skip dialog (`LuckyHotbar.offerSkip` :826-876) reads `Config.LuckyBlocks.Skips`, so the
  1 R$ tier works; only comments say "4 / 9 / 15" (`LuckyHotbar:14-15`, `LuckyClient:275`).

**Step 7, the win track and the result screen**
- `WinTrack.luau`: "Money" steps draw a blank tile (:138); the folded "Next ->" hides when the
  next step is money (:326-328, :417-418); it reads Config, not RewardState's `wins.kinds`, so
  tile 1 shows Uncommon while a first-ever win gives a Rare; header (:3-5) lists v4's track;
  `Config.UI.WinTrack` has nothing for a money tile; `Strings.WinTrack.Count`/`Next` are unused.
- `ResultScreen.luau`: the bonus line folds in the track money (shim 5, :671-673); it needs its
  own line from `m.track` (no string yet); `newMoneyOf` (:986-991) and the header (:36-37) too.
  The `/result` preview (`DevCommands.luau:405-416`) has no `track`.

**Step 8, Free Reward**
- `RewardsParts`: `pictures()` (:282-307) has no cue; `bestBlock` (:194) ranks Mystery above
  Mythic. `FreeParts`: `setPictures` (:88-133) and `extras` (:323-342) know money, blocks and
  spins only. `FreeDaily.luau:423-435`: day 7 of the first week shows the cash stack, hides the
  dice and omits the cue; `Config.FreeReward.Daily.Hero.Art` is "the best block".
  `RewardsFlyer:154` flies blocks and spins only. `Config.Daily.WeekBonus` is no longer read.
- Fine already: FreePlaytime (5 tiles), FreeTrack, FreeSocial, FreeHeroes.

**Step 9, trading** (`TradeMenu.luau`): "Block:" and "Climbed:" items draw the same icon, no
mark (:92-101); "Climbed %s" names (shim 6, :44, :72-88); the comment at :43 calls "Block:" "a
ready lucky block". The Week One Cue already works through CueThumb.

**Step 10, Cues and the Index**: `InventoryCues.luau:164-196` `chanceText` uses
`BlockDrop.rarityPercent` without luck and gives the Week One Cue Legendary's % (callers :761,
`CueCardLab:132`); `oddsLine` (:199-212) returns nil for it, so `InventoryIndex:691` and the big
card (:504) show nothing. "Day 7 of your first week" needs a string.

**Step 11, rank screens**: Roadmap (:1207-1224), RankClaimBlock (:54-70) and NewRankPopup
(:137-160) show only block chips, no odds or floors: look, likely nothing to change.

**Step 12, the words** (`src/shared/Strings.luau`)
- 1010 `Reasons.Reveal` ("Tap the Mystery block's slot...") and 1011 `NotMystery`: Mystery only.
  1025: the "MYSTERY" title.
- 1124-1127: "Guaranteed Rare/Epic or better", "...%s or better!": v5's pity gives exactly that
  rarity. 745: the shop card's pity line. 749: "Each slot: %s" (the slots differ now).
- 1107 `ShopV4.RestockOdds` (unread, four fixed kinds); comments 743-744 and 1097 ("x10",
  "13 for 10"). 941 `Items.Odds` is a per-rarity chance.
- Missing: the clover popup, "Day 7 of your first week", the win track's money line and money
  tiles' words, the Open all summary, the quick reveal.
- Already v5: the VIP lines (771, 789, 1091, 1103). Not found: "up to Mythic", "opens in 5
  minutes", "3 slots", "Epic by 100". UltOdds' pity of 100 is the ability spins' own
  (`Config.Ults.Roll`), not the blocks'.

**The tutorial (the `tutorial-v2` session's; list only, never edit `Tutorial.luau` here
beyond keeping `gui-v4`'s interim tutorial working)**: `Tutorial.luau:322-357` uses
`BronzeBlockKind` (Uncommon); :359-380 expects the Rare block counting down
(`slotOf("Rare", true)`); :478-490 nudges `slotOf("Rare")` though it may climb higher;
`LuckyClient:330-334` sets BlockTapped only while a timer runs; Strings 1755 "Standard lucky
block", 1789-1791 (RareBlock), 1834 (BlockReady). Put what you find into the handoff's section 2.

---

## Progress (tick each box when it is verified, committed and pushed)

- [ ] 0. Setup: Rojo connected, sync confirmed, lint and tests green; today's screens
  screenshotted in Studio (phone emulator and PC); any breakage found goes first.
- [ ] 1. The server's scripted climb (the tutorial's Mystery block), with tests.
- [ ] 2. The climb screen for every block, the mark, the Secret (concept approved, built,
  checked; shims 1-3 gone).
- [ ] 3. The quick reveal and "Open all".
- [ ] 4. Odds & Details for every block, with the pity bars (shim 4 gone).
- [ ] 5. The Grand Opening Luck clover.
- [ ] 6. The shop: the Mystery band, the restock, VIP, the Grand Opening and Starter cards, the
  skip dialog (shims 8 and 9 gone).
- [ ] 7. The win track and the result screen (shim 5 gone).
- [ ] 8. Free Reward (shim 7 gone).
- [ ] 9. Trading (shim 6 gone).
- [ ] 10. Cues and the Index.
- [ ] 11. Rank rewards and every other block or reward display.
- [ ] 12. Every word (the Strings sweep).
- [ ] 13. The full Studio check on phone, PC and gamepad.
- [ ] 14. The docs.
- [ ] 15. Ready for release: the place saved and committed, the designer's release clicks
  listed, roadmap 7.9.

---

## Notes (yours: the starting commit, each gate's pick, every call, open items)

