# Economy v5 for release: update every screen to the new numbers (an attended run)

Written 2026-10-09 by the designer (Justin, Roblox name Painicane) with Claude. You are a Claude
Code session in `~/Desktop/8ball` on branch `gui-v4`. Economy v5, "every block climbs", is built
underneath (Config, the shared rules, the server, saves v11, the model, `docs/ECONOMY.md`) and
its **Robux prices are live on Roblox**.

**The GUI is already built.** Every screen exists, has its look and works today, and Studio
already shows it (Rojo is connected on port 34872). This run does **not** redesign or rebuild
any screen. It **updates what is already there** so every number, odd, price, reward and word
the player sees is economy v5's:

1. **Change the numbers, odds and details** on each existing screen (the list: section 3; what
   each one must show: `docs/prompts/ECONOMY_V5_HANDOFF.md` section 1; every line still on v4:
   the audit, section 4). Keep each screen's layout, style and animations as they are.
2. **Add only the few small pieces v5 needs that do not exist yet** (a Secret rung on the climb
   ladder, an unclimbed/climbed mark on blocks, the quick reveal, an "Open all" button, the
   Grand Opening Luck clover, a money tile on the win track, a "Win track" line on the result
   screen), each made from the parts and style of the screen it sits in.
3. Remove each of the ten small shims as its screen is updated (the handoff's table, 1.13).
4. Add one server hook for the tutorial's scripted first block (step 1).
5. Merge cleanly with the tutorial work (step 12), check everything in Studio on phone, PC and
   gamepad, and leave the game ready to publish.

**Trading is not in the release** (designer, 2026-10-08 and 2026-10-09): leave `TradeMenu`
and the trade code as they are (shim 6 stays), and skip trades in every check.

**The designer is here.** No concept art and no art sheets for this run: the screens' looks
are already approved. For each of the **new small pieces** in point 2, build it in its screen's
existing style, then show the designer one Studio screenshot (phone emulator and PC) and wait
for their OK or notes before you move on. For number, odds and word changes, just do them and
show them in the step's report. Ask whenever a v5 number does not fit a screen's layout.

---

## 0. Where you work, and what you never touch

- **Your folder:** `~/Desktop/8ball`, branch `gui-v4`. Commit and push only `gui-v4`. Never
  push or change `main`, `release`, `tutorial-v2`, `before-economy-v5` or any other branch; never
  force-push or rewrite history.
- **`place/8ball.rbxl` has the designer's own uncommitted change.** Never stage, commit, stash,
  reset, check out or delete it, until the end (step 15) when the designer saves the place and
  says so. Stage files by name: never `git add -A`, `git add .`, `git commit -a`, `git stash`
  or `git reset --hard`.
- **Studio and Rojo are already running.** `rojo serve` is serving this folder on port 34872 and
  the designer's Studio is connected to it. Do not start another one; check it with
  `lsof -nP -iTCP:34872 -sTCP:LISTEN` (if it is ever down, start
  `rojo serve default.project.json` in the background and ask the designer to click Connect).
  Before every playtest, confirm the sync with the MCP `script_grep` for a string you just
  changed. Scripts only under `src/` (never through the MCP). Stop Play before an edit syncs.
- **Studio windows:** the tutorial's Studio (port 34877) may be open too. Studio's MCP mouse
  input can land in whichever Studio window is in front: ask the designer for a quiet minute
  before any `user_mouse_input`, and prefer code-driven checks (GuiQA hooks, `execute_luau`).
  Send one `screen_capture` per message (several in one message hang).
- **Robux:** the v5 prices are live (designer, 2026-10-09). **Never change a price, create or
  retire a product** unless the designer asks in this run (the one planned change is v4's held
  sync at publish, step 15); never delete one; always dry-run first. Icons for `Mystery5` and
  `LuckyBlockSkip1` are allowed once the designer approves their pictures
  (`python3 tools/roblox_products.py --icons --only Mystery5,LuckyBlockSkip1 --dry-run`, then
  without `--dry-run`). The API key is in the macOS Keychain (`ROBLOX_API_KEY`): never print,
  echo, log or write it. Screens always show Roblox's live price (`ShopState`), never a typed
  number.
- **The economy's numbers are settled.** Never change a Config economy number (odds, prices,
  rewards, timers) to make a screen easier; if a screen shows a number that looks wrong, ask.

### Working beside the tutorial terminal

A separate Claude terminal is working on the tutorial **right now**: `~/Desktop/8ball-tutorial`,
branch `tutorial-v2` (a git worktree of this same repo), its own Studio on Rojo port 34877. It
has its own brief (`docs/prompts/TUTORIAL_V2_PROMPT.md` on its branch). Both branches will be
merged into one, so:

- **Never touch its folder, its branch or its Studio.** Read its branch with git only
  (`git log gui-v4..tutorial-v2`, `git diff gui-v4...tutorial-v2 -- <file>`,
  `git show tutorial-v2:<file>`).
- **Files it owns:** `src/client/Tutorial*.luau`, `src/server/Tutorial*.luau`,
  `src/shared/Tutorial/`, `tools/tutorial_v2*`. Leave them alone on `gui-v4`, except one small,
  marked change where v5 truly needs it (and then say so in Notes and in the handoff's section
  2). You may add tutorial-facing pieces **outside** those files (a server hook, a string, a
  Config value) for the tutorial to use.
- **Files you both change:** `src/shared/Config.luau`, `src/shared/Strings.luau`,
  `src/shared/Net.luau`, `src/client/Main.client.luau`, `src/client/Input.luau`,
  `src/server/DevCommands.luau`, `docs/DECISIONS.md`, `docs/STUDIO_NOTES.md`. Here, keep your
  edits in the economy, shop, block and reward sections; add new keys next to their siblings;
  never reorder, rename or reformat lines you are not changing (never run `tools/format.sh` on a
  whole file it shares: StyLua only the files you edited, and check `git diff` shows only your
  lines).
- **Check the merge after every step's commit** (read-only, changes nothing):
  `git merge-tree --write-tree --name-only gui-v4 tutorial-v2`. On 2026-10-09 (commit 82d0d43
  against ead8a67) it already conflicts in 5 files: `docs/DECISIONS.md`,
  `src/client/Tutorial.luau`, `src/server/TutorialService.luau`, `src/shared/Config.luau`,
  `src/shared/Strings.luau`. Write the list in Notes each step; a **new** conflicting file means
  your step strayed into the tutorial's lines: fix that before you go on.
- **The real merge is step 12**, with the designer's yes, when the tutorial terminal has
  committed and is at a stopping point.

---

## 1. How the run goes

For each step in section 3, in order:

1. **Look first**: open the screen in Studio as it is now (phone emulator and PC), screenshot
   it, read its handoff entry (the section in brackets) and its audit lines (section 4), and
   read its client file. The screen already works: find where it reads the old numbers.
2. **Update it in place**: every number from Config or the shared functions (`BlockDrop`,
   `BlockOdds`, `LuckyBlocks`, `Restock`, `ShopView`, `RewardView`, `Daily`), never a typed
   number; every word in `Strings`; every new size or timing in `Config.UI`. Same layout, same
   style, same animations. A new small piece reuses the screen's own parts (its chips, bars,
   tiles, fonts, colors) and the house rules in `docs/UI_STYLE.md`.
3. **Check it in Studio**: playtest it for real (blocks: `/giveblock <kind> [count]`), on the
   phone emulator, PC and a gamepad path; read the console; screenshot. A new small piece: show
   the designer and wait for their OK (`touch .git/overnight-waiting` first, see below).
4. **Remove its shim** (the handoff's table, 1.13) and anything it left unused.
5. `tools/lint.sh`, `tools/test.sh` (add Lune tests for any shared or server change), commit
   (files by name) and push `gui-v4`, the trial merge (section 0), tick the step, a Notes line,
   and a dated `docs/DECISIONS.md` line for every call the designer made.

The lively-gui skill (`.claude/skills/lively-gui/SKILL.md`) is for building or restyling a
screen; this run only needs its `verification.md` and `pitfalls.md` for the Studio checks.

**The Stop hook** (this run is started with `--settings tools/overnight/economy_v5_gui.json`,
attended mode): while a Progress box is unticked it sends you back to work when you stop. To
stop and ask the designer something, first run `touch .git/overnight-waiting`, then ask; the
hook lets that one stop through. Keep going on your own wherever you can.

**If a step is truly blocked**, tick it `- [x] BLOCKED: <why>`, say why in Notes, and move on.

---

## 2. Read first

- `CLAUDE.md`, then `docs/STATUS.md`.
- **`docs/prompts/ECONOMY_V5_HANDOFF.md`**: section 1 says what each screen must show (what it
  reads, what it calls, the shim it replaces); 1.13 the shim table; section 2 the tutorial's
  list. (Its 1.12 trading part is not in the release.)
- `docs/prompts/ECONOMY_V5_REPORT.md` (what changed, the "try in Studio" list) and
  `docs/ECONOMY.md` sections 0, 7 (blocks), 9 (the shop), 10 (rewards), 11 (Robux), 18 and 19
  (the menus, the shims).
- `docs/UI_STYLE.md`, and the lively-gui skill's `verification.md` and `pitfalls.md`.
- The last week of `docs/DECISIONS.md` (the designer's v5 answers of 2026-10-09).
- The code each screen reads: `src/shared/Progression/` (`BlockDrop`, `BlockOdds`,
  `LuckyBlocks`, `Restock`, `ShopView`, `RewardView`, `Daily`), `src/shared/Net.luau` (the
  remotes and their payloads), and the client files named in section 4.

---

## 3. The steps, in order

Each is one Progress step. The handoff section is in brackets.

1. **The server hook for the tutorial's first block (no GUI).** The designer picked a scripted
   Mystery block for the tutorial's first block (2026-10-09), as `tutorial-v2` already plans:
   it climbs once, Standard to Uncommon, and lands ready at once. **Add** an optional fourth
   hook to `LuckyBlockService.setOpenHooks(force, opened, stay, script)`:
   `script(player, kind) -> string?`, the forced final tier of that climb (nil: a normal
   roll), passed to `PlayerData.climbBlock` (a Mystery uses `BlockDrop.roll`'s `forced` tier,
   still counting pity; the climbed block lands ready at once). **Keep `stay` working** and do
   not edit `TutorialService.luau`: the tutorial terminal wires `script` in after the merge.
   Lune tests. Write how to use it into the handoff's section 2.
2. **The climb screen for every block, the mark and the Secret** (1.1, 1.2). Today's Mystery
   climb screen (`MysteryReveal`) opens any unclimbed block from its own tier (its own name,
   tint and start pose), 7 tiers with the Secret on top (the new rung), **no pity on this
   screen**, the climbed block landing on its timer, a Secret going straight to its pull. OPEN!
   for every unclimbed block and a small unclimbed/climbed mark in the hotbar and bag. Removes
   shims 1, 2 and 3.
3. **The quick reveal and "Open all"** (1.3), two new small pieces: a 1-2 s reveal for Common
   and Uncommon results (from the reel's own parts) and an Open all button by the bag with its
   summary.
4. **Odds & Details** (1.4, 1.6): the existing popup shows live odds (the Grand Opening Luck,
   pity when due), an unclimbed block's climb odds or a climbed block's one rarity, every cue's
   % and "1 in N", **and the pity bars** (Rare by 10, Epic by 40, the head start). Removes
   shim 4.
5. **The Grand Opening Luck clover** (1.5), a new small piece next to the money and VIP bars,
   only while the luck runs, with its popup (the countdown and the two boosted steps).
6. **The shop** (1.8, 1.9): the Mystery band's 7 rows (Secret added), its live Robux prices (7
   R$, the 29 R$ 5-pack, "35 one by one"), $14,900 and 5 for $66,900, 6 for 5 during the launch
   bonus, **the pity bars on its card** (in place of the "Epic guaranteed" strip); the restock's
   three cards fitting the band (slot 1 "Epic or better", slot 2, VIP's); the VIP card's perk
   text; the Grand Opening and Starter Pack cards; the timer skip dialog (1 / 4 / 9 / 15 R$).
   Removes shims 8 and 9.
7. **The win track and the result screen** (1.10): money tiles between the block tiles, the
   first-ever win's Rare, win 10's Epic; the result screen's own "Win track +$1,000" line.
   Removes shim 5.
8. **Free Reward** (1.11): the Week One Cue on day 7's card from day 1 (picture and words), the
   later weeks, the 28-day track, five playtime tiles, VIP's Uncommon block, the group's 2
   Mystery blocks, the invite's Uncommon block, Claim All's live prices. Removes shim 7.
9. **Cues and the Index** (1.12): the Week One Cue in the Legendary row with "Day 7 of your
   first week" where block cues show odds; every chance chip live from `BlockDrop`.
10. **Rank rewards and every other place a block or reward shows** (the Ranked roadmap, NEW
    RANK!, the claim block, reward chips and flyers, the Gift drop, banners): v5 names and
    counts, no v4 odds or floors.
11. **Every word**: a sweep of `src/shared/Strings.luau` and the client for any v4 fact left
    (section 4's word list), each fixed in `Strings`.
12. **The merge with `tutorial-v2`.** Ask the designer whether the tutorial terminal is at a
    stopping point (everything committed). With their yes: `git merge tutorial-v2` into
    `gui-v4` (a normal merge commit, never a rebase; if it would touch `place/8ball.rbxl`, stop
    and ask). Resolve every conflict by keeping both sides' work: in Config, Strings and
    DECISIONS keep both sets of lines (DECISIONS in date order); in the tutorial's own files
    take `tutorial-v2`'s version, then re-apply only what v5 needs on top (the block kind, the
    hook from step 1, the "Rare" slot lookups, the audit's tutorial list) and tell the
    designer each call. Then lint, the full tests, and a Studio check of a fresh player's
    tutorial (its first game, its scripted Mystery block, its hints) and the block flow. Push
    `gui-v4`; never commit on or push `tutorial-v2`. Write in the handoff's section 2 what the
    tutorial terminal must pull next (`git merge gui-v4` on its side, its call). If the
    tutorial is not at a stopping point yet, do steps 13 and 14 first and come back; the release
    (15) waits for this merge.
13. **The full Studio check** (`ECONOMY_V5_REPORT.md`, "try in Studio", trades left out): a
    Mystery block and a tier block from a win (climb, timer, open), the restock (buy one with
    money), the Mystery band, Free Reward's first week, the Grand Opening Luck's odds with a test
    `StartsAt` in a Studio test only, Open all, a few `/giveblock Mythic` for a Secret climb, the
    tutorial's first block. Phone emulator, PC and a gamepad path for every screen. Real Robux
    purchases (the 1 R$ skip, the 29 R$ 5-pack) only if the designer makes them.
14. **The docs:** `docs/ECONOMY.md` (sections 18 and 19: the shims gone, the screens as
    updated), `docs/UI_STYLE.md` for any new small piece, `docs/ROADMAP.md` 7.9,
    `docs/STATUS.md` (current state only, under about 100 lines; move finished entries to
    `docs/archive/STATUS_HISTORY.md`), the handoff file (what is done).
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
(fixed with this brief; shim 7 now names it in words). Trading is not in the release, so its
lines are left out.

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
  unclimbed block, wrong for a climbed one (the skip dialog `LuckyHotbar:879-894`).
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

**Step 9, Cues and the Index**: `InventoryCues.luau:164-196` `chanceText` uses
`BlockDrop.rarityPercent` without luck and gives the Week One Cue Legendary's % (callers :761,
`CueCardLab:132`); `oddsLine` (:199-212) returns nil for it, so `InventoryIndex:691` and the big
card (:504) show nothing. "Day 7 of your first week" needs a string.

**Step 10, rank screens**: Roadmap (:1207-1224), RankClaimBlock (:54-70) and NewRankPopup
(:137-160) show only block chips, no odds or floors: look, likely nothing to change.

**Step 11, the words** (`src/shared/Strings.luau`)
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

**The tutorial (the `tutorial-v2` session's; list only: leave `Tutorial.luau` alone on
`gui-v4`, see section 0's merge rules)**: `Tutorial.luau:322-357` uses
`BronzeBlockKind` (Uncommon); :359-380 expects the Rare block counting down
(`slotOf("Rare", true)`); :478-490 nudges `slotOf("Rare")` though it may climb higher;
`LuckyClient:330-334` sets BlockTapped only while a timer runs; Strings 1755 "Standard lucky
block", 1789-1791 (RareBlock), 1834 (BlockReady). Put what you find into the handoff's section 2.

---

## Progress (tick each box when it is verified, committed and pushed)

- [x] 0. Setup: Rojo on 34872 serving this folder and Studio synced (`script_grep`), lint and
  tests green, the trial merge with `tutorial-v2` noted; every screen in section 3
  screenshotted as it is now (phone emulator and PC); any breakage found goes first.
- [x] 1. The server hook for the tutorial's scripted first block, with tests.
- [x] 2. The climb screen for every block, the mark, the Secret rung (shims 1-3 gone).
- [x] 3. The quick reveal and "Open all".
- [ ] 4. Odds & Details for every block, with the pity bars (shim 4 gone).
- [ ] 5. The Grand Opening Luck clover.
- [ ] 6. The shop: the Mystery band, the restock, VIP, the Grand Opening and Starter cards, the
  skip dialog (shims 8 and 9 gone).
- [ ] 7. The win track and the result screen (shim 5 gone).
- [ ] 8. Free Reward (shim 7 gone).
- [ ] 9. Cues and the Index.
- [ ] 10. Rank rewards and every other block or reward display.
- [ ] 11. Every word (the Strings sweep).
- [ ] 12. The merge with `tutorial-v2` (the designer's yes), checked in Studio.
- [ ] 13. The full Studio check on phone, PC and gamepad.
- [ ] 14. The docs.
- [ ] 15. Ready for release: the place saved and committed, the designer's release clicks
  listed, roadmap 7.9.

---

## Notes (yours: the starting commit, each step's trial-merge list, every call, open items)


- **Start** (2026-10-09): commit `fef029e` on `gui-v4`; Rojo serving this folder on 34872
  (the tutorial's on 34877); the main Studio is "Crazy 8 Ball (placeId 107430170196919)".
  Lint OK (the three old LocalShadow warnings), 1156 tests pass. `script_grep` only sees Edit
  mode (stop Play to check a sync).
- **Step 0**: the PC screens as they were, in `~/Desktop/8ball-refs/economy-v5-gui/before/`
  (HUD, Shop: Grand Opening, Mystery band, restock, Starter Pack, passes; the Mystery odds,
  the climb screen at its start and end, the skip dialog, the win track, Free Reward's group,
  daily and playtime/track, the Index and its Legendary row, the result screen, Ranked). No
  breakage beyond the audit's lines: the Mystery band's 7th row (Secret) is clipped at the
  card's bottom (step 6); the designer's old unclimbed Epic block says READY! where v5 says
  OPEN! (step 2); Studio's `StudioOpening` opens the Grand Opening through `Shop.setDeal`, not
  Config, so the Grand Opening Luck stays off in Studio on both sides (step 5 needs its own
  test switch). Trial merge: the same 5 conflicts as the brief (DECISIONS, Tutorial.luau,
  TutorialService.luau, Config, Strings). The phone emulator's (750 x 361) as `phone_*.jpg`
  beside them (14 screens). On a phone the result card nearly fills the height (step 7's
  new line needs room) and the climb screen's button says "Click!" in the touch emulator.
- **Step 1**: `BlockDrop.climbFor` (pure: stay, a scripted tier, or a roll; 5 Lune tests),
  `PlayerData.climbBlock(player, id, stay, forced)`, `setOpenHooks`' fourth hook `script`,
  asked on the climb screen's Reveal too (with `stay`, which Reveal never asked before). A
  Studio-only `ServerStorage.LuckyBlockQA:Invoke("script", tier?)` forces every climb (for
  the Secret checks). Checked in Studio: a Mystery block scripted to Uncommon climbed
  Standard, Standard, Uncommon, Uncommon, landed ready at once and counted its pity (5/87/87
  to 6/88/88); a plain Rare block still rolls. How to use it: the handoff's section 2.
- **Step 2**: every unclimbed block (OPEN!, the new mark) opens `MysteryReveal` from its own
  tier (name, art, ladder lit to it; Lucky 8 / Sky / Gift titles from Strings); `Hold` and
  `Throw` refuse it (`Reveal`); the Reveal answer is `path`, `kind?`, `readyAt?` (no `tiers`).
  The Secret rung: the Mythic art darkened (`Reveal.Secret.Tint`) with a red "?"; a Secret
  climb slams SECRET! (red look), then after 0.9 s hands off to `LuckyOpening.pull` (the pull
  cutscene, then the YOU GOT card). The mark: an ink disc with a white ring and a gold up-arrow
  at a slot's top-right (`LuckyBlocks.UI.ClimbMark`), hotbar and bag. Shims 1-3 gone (Hold's
  climb, `BlockDrop.shown`, `Roll`). New Studio hooks: GuiQA `blockPress` (index) and
  `blockBag`. Checked on the phone emulator (Epic, Mystery, a scripted Secret from a Rare, the
  bag) and PC (the hotbar, a Legendary that really climbed to the Secret, 1 in 267: 200,000
  server rolls gave 0.38%); console clean; gamepad: LB/RB aim, R2 opens, A presses. Lint OK,
  1160 tests. Trial merge: the same 5. Shots: `economy-v5-gui/step2/`.
- **The designer, before leaving (2026-10-09):** keep v5; build every new small piece in its
  screen's style on my judgment and tick it, screenshots in `economy-v5-gui/` for review later;
  Studio stays on PC (the emulator off), the phone checks all go in step 13 when they are back;
  **no merge with `tutorial-v2`**: the tutorial terminal is still working, so step 12 waits
  (do 13 and 14, then stop before 15); Mystery5's icon: the 1-pack's picture (dry run first).
  Screen control (computer use) is held by another session, so no emulator clicks.
- **Step 3**: the quick reveal (`LuckyOpening.quick`): a Common or Uncommon cue skips the reel;
  the result card alone (rays, sting) at `UI.QuickScale` 0.8, no hint, pops out by itself
  after `QuickRevealSeconds` (closed 1.68 s after it showed), a tap sooner. "Open all": a green
  kit button right of the bag button (hangs past the bar so the bar stays centred), shown
  while a ready climbed Standard or Uncommon block is not in the hands or on the floor; in the
  open bag a gamepad selects it. Its summary (`LuckyOpening.summary`): "37 BLOCKS OPENED!" over
  one cue card per cue ("x7" for repeats, NEW on a first find), rarest first, in the columns
  (up to `UI.OpenAll.MaxColumns` 8) that make the cards biggest, a tap closes it. Checked on
  PC: the quick card, the button, a fake 16-cue summary (4 rows at first; now 8 across), a real
  Open all of 37 blocks, the button gone after; console clean. The phone view waits for step
  13 (by the numbers the button ends about 70 px left of the jump button). New GuiQA hooks:
  `quickReveal`, `openAllSummary`, `openAll`. 40 real Standard climbs gave 22 / 12 / 3 / 3
  (Standard / Uncommon / Rare / Epic): the odds are right (a Legendary-to-Secret and a
  Standard-to-Legendary climb earlier were luck). Lint OK, 1160 tests. Shots: `step3/`.
