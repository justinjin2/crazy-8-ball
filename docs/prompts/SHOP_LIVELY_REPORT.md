# Lively Shop: report (2026-10-06)

The run that rebuilt the Shop's frame and its Featured page in the style of reference 13b, on
branch `shop-lively` (brief: `docs/prompts/SHOP_LIVELY_PROMPT.md`). All five gates were approved
by the designer. The method is now the project skill `.claude/skills/lively-gui/`, which every
future GUI follows.

## What was built

**The frame** (a kit switch, `Config.UI.Menu.LivelyMenus = { "Shop" }`; `MenuFrame`):
- The panel unrolls from a thin bar (about 0.2 s, a slight overshoot) and folds shut on close.
  The open lasts 1.07 s in all; every piece pops in on a schedule (`Stage`,
  `Config.UI.Shop.Open`). A tab switch replays only the page; reopening or spamming always ends
  in a clean screen.
- A compact panel: at most 66% of the screen's width, under Roblox's top bar, as tall as its
  first card, the next section ("BLOCKS") peeking in below so players know to scroll.
- The pale header scrolls an 8-ball pattern up-left; the white sheet has the still pool-ball
  dots. Basket icon and a big "Shop" title; the money pill with a gold "+" that jumps to Money;
  a smaller red X.
- The four tabs (Featured, Blocks, Money, Passes) stand outside the panel on the right, with
  NEW badges; the 8-ball flair is pinned on the left edge, rocking and hopping.
- Party poppers, gold streamers and corner twinkles on open (switches, on).
- **One thing at a time** (`HudFocus`): while any full menu is open, every other HUD screen is
  hidden and comes back when it closes. This applies to every menu, not only the Shop.

**The Grand Opening card** (`GrandOpeningCard`, Featured page):
- The plate with floating 8-balls at three depths, corner fireworks, drifting confetti, bokeh.
- The crowned lucky block: gold glow, turning rays, a breathe (2.3 s) and a shine sweep; the
  NEW tag wiggles; the live "Ends in 20d 23h" timer; the sky-blue "i" opens all eight odds
  (summing to exactly 100%) by hover, click, tap or gamepad A **on the badge only**.
- The arched "GRAND OPENING" title in real text, stars, subtitle.
- The Beta Cue card: blueprint panels in waves, a turning ring, scrolling glyph code, a scan
  line, a light pulse along the cue, a glitch.
- The **Firework Cue** card (renamed from "Grand Opening Cue" everywhere, ids included): mini
  fireworks, a yellow glow so the cue stands out, and its gold ribbons as a still picture that
  dims and glows (no movement).
- Each cue card's odds chip in its bottom-right corner (0.3% and 3%), a UNIQUE pill only.
- Three green Robux buttons (49, 129, 349; the old prices struck through in red), each with a
  purple gift square that opens the Gift Player list; the pack sizes between the rows; three
  gold money buttons ($49,000 / $139,000 / $441,000). Only the Robux buttons shine.
- A phone shows the whole card at once (the cue cards stay beside the block).

**Controllers**: every control is selectable; the lit tab is chosen first; A presses, B closes
the odds then the Shop. Every X that B closes now wears the controller's back button (Circle,
or B on Xbox) on its corner while a gamepad is in use (`HudParts.padBack`): every menu, the cue
detail, the roadmap, Gift Player and the ult screen.

**Also in this run**
- The internal rename `GrandOpeningCue` -> `FireworkCue` (skin, piece and asset ids `firework`)
  with save version 8 (owned copies, equipped cue and trade history move over), the Limited
  numbering kept on the old DataStore key so copy numbers carry on, and old copy counts folded
  in (`Config.Items.RenamedCues`).
- Products GrandOpening1/3/10 created on Roblox: 3716907625, 3716907627, 3716907629 (the
  crowned block as their icon). Studio's GetProductInfo shows every product at about 0.8x its
  price; that is Studio, not a bug.

## The gates

| Gate | Result | The designer's notes |
|---|---|---|
| 1. Tech spike | approved | Smooth motion by sliding or zooming the picture inside a still label (`ImageRectOffset` / `ImageRectSize`) or by rotation; our own pooled particles; flipbooks at 30 fps; no CanvasGroup. |
| 2. Art sheet | approved after one round | Crown and block regenerated whole (four ball-tipped prongs), straight subtitle, header pattern at 0.6, the "i" odds badge over a chip row, a denser Beta card. Real-text title in Fredoka One. |
| 3. Animatic | approved | Default timings; the title pops as one piece; the Firework card's fireworks at half speed. |
| 4. First look | approved after several rounds | A faster open; the card fits a phone; gift squares; a smaller panel with tabs outside; the crown baked into the block; HudFocus; a compact header with the money "+"; no LIMITED pill, no save labels; Robux buttons bigger and alone in shining; the Firework Cue renamed (ids too) with a yellow glow and still, pulsing ribbons; the block breathes faster. |
| 5. Final | approved | Phone and computer sizes, a real gamepad. Odds from the "i" only; the controller's back button on every X. |

## Checks (last run)

- Lint clean; **1001 Lune tests pass** (StageMath: easing, reveal curves, flipbook maths,
  breathe windows, the timer, the odds sum; the save migration 7 -> 8; renamed counts; trades
  in flight across the rename).
- Studio, phone emulator (750 x 362) and a computer size (the designer's switch): 60 fps with the Shop open
  (16.7 ms average, worst frame 19.5 ms); 100 pictures on screen, 69 with Lower effects;
  +53 MB texture memory while open (gate 4). Reduce Motion only fades (soft glows still pulse).
  No console errors.

## Links

- Gate 2 sheet: https://claude.ai/artifact/VsFSVNxe1VBMgYNxt4oCUA
- The animatic: https://claude.ai/artifact/ABF5JjwmsSNMqNXw2SU2tJ (local:
  `tools/gui/animatic/index.html`)
- Gate 4 page: https://claude.ai/artifact/6MinwiDaKQLB8uLoozzu6E
- Recordings and contact sheets: `~/Desktop/8ball-refs/gui-lively/work/` (`spike/gate1/`,
  `gate2/`, `gate4/`, `gate4b/`, `gate4c/`); the cue renders in `renders/tip_left/`.

## Spend and assets

- Images: **$7.00** of the $500 limit (GPT Image regenerations at gate 2). Every upload was $0.
- 62 pictures uploaded to the group (675425213), dry run first, all in
  `tools/upload_manifest.json` with their image ids: 52 card pieces (`assets/ui/grand_opening/`),
  8 effect sheets (`assets/ui/effects/`), 2 frame tiles (`assets/ui/frame/`). The ids the game
  uses are in `Config.UI.GrandOpeningCard.Images`, `Config.UI.Effects` and
  `Config.UI.Menu.Lively`.
- Not used by the game any more (kept for the animatic or as history): the ribbon loop sheets
  `assets/ui/effects/firework_ribbons_*`, and three uploads of a baked "still" cue that was
  replaced the same day (their files were removed; the manifest keeps the record).

## Where things live

- Code: `src/client/Stage.luau`, `src/shared/StageMath.luau`, `src/client/UIAnim.luau` (the idle
  library), `src/client/MenuFrame.luau` (the lively frame), `src/client/HudFocus.luau`,
  `src/client/GrandOpeningCard.luau`, `src/client/ShopMenu.luau`, `src/client/ShopGift.luau`,
  `src/client/GuiQA.luau` and `ShopLab.luau` (Studio-only test hooks).
- Numbers: `Config.UI.Motion`, `Config.UI.Menu.Lively`, `Config.UI.Shop.Open`,
  `Config.UI.GrandOpeningCard` (Layout, Loops, Images), `Config.UI.Kit.PadBack`.
- Tools: `tools/gui/` (cutting, effects, render_cues and cue_sheets in Blender, crowned_block,
  cue_glow, firework_still, the animatic, recording and contact sheets; see its README).
- The method: `.claude/skills/lively-gui/` (SKILL.md, motion, art-pipeline, verification,
  pitfalls).

## Try by hand

1. Press Play, open the Shop: the unroll and the card's pop-in; watch the idle loops for a
   while (the block breathing, the ribbons dimming and glowing, the Robux buttons shining).
2. Hover or tap the "i" on the block: the odds; tap away or press B to close.
3. Press a gift square: the Gift Player list (it needs another player in the server).
4. Press a green button: Roblox's test purchase window (cancel it).
5. With a controller: the back-button picture on the X; B closes the odds, then the Shop.
6. Open any other menu: the rest of the HUD hides, and comes back on close.

## For the designer

- **Save and publish once for this milestone**: in Studio, File > Save to File As... over
  `place/8ball.rbxl`, then File > Publish to Roblox. That makes the renamed Firework Cue
  instances (`ReplicatedStorage.CueSkins.FireworkCue`, `CuePieces.firework`) live.
- `shop-lively` was merged into `release` on 2026-10-06 (a fast-forward); `main` moves only
  when the designer ships.

## What comes next

- **The rest of the Shop with the skill**: the Blocks, Money and Passes pages (the gold "+"
  already jumps to Money, which has no page yet).
- Other menus switch to the new frame one at a time, each when it is rebuilt with the skill.
- Big screens go through every gate; small popups and HUD pieces get a Studio first look, then
  the final check. A target picture comes from the designer, or Claude mocks two or three.
