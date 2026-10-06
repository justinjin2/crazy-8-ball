# The lively Shop: the frame and the Featured page

**Written 2026-10-06 by the designer with Claude** (a prompt-maker session: research, then an
interview). Branch `shop-lively`, made from `release` in `~/Desktop/8ball` (nothing else works in
this folder during the run), Rojo 34872, the main Studio place. Stop hook
`tools/overnight/shop_lively.json`.

This is an **attended run**: the designer is awake and answers quickly. The Progress list at the
end is the source of truth; the Stop hook sends you back to work while any `- [ ]` remains. When
you need the designer (an approval gate below, access you cannot get, or a call where guessing
would lower the quality), run `touch .git/overnight-waiting`, ask one clear question with
pictures or videos, and stop; the hook lets that stop through. Otherwise never stop between
steps.

The designer's goal, in their words: "create an actual lively feeling GUI that does not feel
static", where "every icon made has to be individual and appear one by one". **If it works, this
becomes the general rules and layout for every GUI made after it**, kept as a project skill that
you write at the end (section 12). They have unlimited budget and time and want it honed the
first time: quality over speed, and prove risky techniques before building on them.

## 0. Read first, in this order

1. `CLAUDE.md`, `docs/STATUS.md`, `docs/UI_STYLE.md` (sections 1 to 7, 13 and 15),
   `docs/STUDIO_NOTES.md` (MCP, Rojo, uploads with Open Cloud), the client part of
   `docs/ARCHITECTURE.md`.
2. **The research and the interview**: `~/Desktop/8ball-refs/gui-lively/00-research-and-questions.md`
   (the designer's answers are at its end) and `research/01` to `04` there, with sources. Read
   `research/04-smooth-subpixel-motion.md` twice: it decides how anything slow may move.
3. **The code you build on**: `src/client/MenuFrame.luau` (the menu panel, header, pages, open
   and close), `HudParts.luau` (card, `menuCard`, `pattern`, `text`, `pill`, `candy`, `tile`,
   `icon`), `UIAnim.luau` (every animation so far: pop, shine, pulse, sway, spin, confetti,
   sparkle, glowBurst, slam, rainbow, bob, sunRays, loop), `ShopMenu.luau`, `ShopParts.luau`,
   `Menus.luau`, `Quality.luau` (Lower effects), `GuiQA.luau` (the Studio test hook),
   `HoleFill.luau` (the ink lip and hole fill every outlined text gets), `BlockIcon.luau`,
   `PowerCue.luau` and `ScreenFx.luau` (flipbooks in UI already), and in `src/shared/Config.luau`:
   `Config.UI.Kit` (colours, text, `Motion`, `Icons`, `Art`, `Numbers`), `Config.UI.Shop.Page`,
   `Config.Shop.Deals.GrandOpening`, `Config.Products.GrandOpening1/3/10`,
   `Config.LuckyBlocks.Kinds.GrandOpening` and the `GrandOpening` odds row; `Strings.Menus.Shop`.
4. **The old shop**: commit `92c3aff^` still has the deleted section modules (`ShopPage`,
   `ShopCards`, `ShopBlockCards`, `ShopOdds`, `ShopNeed`, `ShopGift`, `ShopThanks`) and commit
   `c862285` the last Grand Opening band. Read them for the buy flow and the server calls
   (`src/server/Store.luau`, `src/shared/Progression/Shop.luau`), not for the look.
5. **Tools**: `tools/openai_image.py` (GPT Image 2.5 Sunburst; edits with reference images; the
   key is in the Keychain, never print it), `tools/roblox_upload.py` and
   `tools/upload_manifest.json`, `tools/roblox_products.py`, `tools/gen_ui_art.py` (SVG drawn
   through headless Chrome; the original dot tile is its `art_pattern()` at commit `106a294`).

## 1. The references (look closely before anything else)

All in `~/Desktop/8ball-refs/gui-lively/`. Frames 01 to 08 and 09 to 12 are stills from two
videos of other designers' shops; each whole sequence takes about one second.

| File | What it shows |
|---|---|
| `01-store-open-1-thin-line` | The first frame: the window is only a thin horizontal bar in the middle (its header strip, squashed, with corner ornaments). |
| `02-store-open-2-unrolls-up-and-down` | It unrolls up and down at the same time like a scroll; the header with its icon and "Store" is already there; puffs at the top corners. |
| `03-store-open-3-empty-frame-first-tab-pops` | The whole frame is open and empty (frame decorations came with it); only the first tab is popping in. |
| `04-store-open-4-tabs-one-by-one-empty-card` | The three tabs appeared one after another, very fast; the "Featured" header and the big card frame are in, still empty; flair (bats) starts. |
| `05-store-open-5-poof-clouds` | Puffs burst where the card's items are about to appear. **Ours uses small firework bursts instead.** |
| `06-store-open-6-crates-and-odds` | The crate art, the title and the four odds cards appeared, each on its own; the first buy button starts. |
| `07-store-open-7-robux-buttons-next-card` | The buy buttons appear one by one, then their "SAVE" tags; the next card starts below. |
| `08-store-open-8-final-with-flair` | Final: little flair pieces sit on the frame (a crow on the top edge, a lantern, a hat on a corner, a ghost peeking) and the frame glows. |
| `09` to `12-exclusive-shop-*` | A second example of the same idea: frame and empty banner, then the chest and title and the first odds tile, then the odds row and the first price button, then everything. |
| `13-TARGET-grand-opening-featured-card.webp`, **`13b-TARGET-grand-opening-original-2172px.png`** | **The target for the Featured card**, approved earlier. Copy its look (section 6). 13b is the lossless original: use it. |
| `14-current-shop-empty-2026-10-06` | Today's Shop: the frame, the header, the white sheet, the four tabs on the right. |
| `15-sheet-pattern-options-dots-vs-8balls.png` | The designer chose **A**: the original tiny pool-ball dots for the white sheet. |

What every piece does in those clips: it appears out of thin air, fading in within about 0.1 s
while it bulges a little past its size and settles. Nothing slides in from off-screen.

In-game references for the card's pieces (the designer: "a model render of it is in game and a
mp4 and png of it, so it can reference from there if needed"):

- **The Grand Opening block** is the `GoldKingLuckyBlock` model
  (`Config.LuckyBlocks.Kinds.GrandOpening.Model`; it lives in the place; the pack is
  `~/Downloads/LuckyBlock3.0/LuckyBlock3.0.rbxl`, never edited). Render it (Studio, `BlockIcon`,
  or Blender) when you need a sharper or differently posed block than 13b gives.
- **The two cues**: `assets/cue/concepts/unique/` (`beta-clip.mp4`, `grand-opening-clip.mp4`, the
  concept boards, the `*-studio-*.jpg` in-game shots), the card pictures
  `assets/cue/thumbs/beta.png` and `grand_opening.png`, their skins and VFX data
  (`assets/cue/skins/`, `assets/cue/vfx/grand_opening/`), and sections 3 and 4 of
  `docs/prompts/UNIQUE_CUES_PROMPT.md` (what each cue's effects are). The card animations should
  feel like the cues' real in-game effects.

## 2. Scope of this run

1. **The Shop frame**: the unroll open and the fold close, the dots on the white sheet, the
   header's 8-balls scrolling, the title, money and close button, the four tabs on the right with
   their NEW badges, and a little 8-ball flair.
2. **The Featured page**: the "- FEATURED -" header and the Grand Opening card (section 6),
   fully animated, with live text, odds and working buttons.
3. **The shared motion engine and effect library** that every later screen will use.
4. **The skill and its tools** (section 12), written last, from what actually worked.

Not in this run: the Blocks, Money and Passes pages (they stay empty and get their own runs with
the skill), sounds (later), and the other menus (Inventory, Abilities, Free Reward) keep their
current frame until they are redone (the new frame is a kit switch, on for the Shop only).

## 3. The house rules for a lively GUI (these become the skill)

- **Every piece is separate**: its own Instance (often its own image), named, with a reveal step
  and, where it makes sense, an idle behaviour.
- **Reveal**: a choreographed timeline whose numbers live in Config. A piece fades in (about
  0.1 s) while it grows from about 60% past about 110% and settles at 100% (UIScale, Back Out),
  each piece a few tens of milliseconds after the one before. Big pieces arrive with a small
  firework burst.
- **Idle**: something always moves, sparkles or breathes on every screen. Loops start the
  moment their piece lands, at random phases so they never pulse in sync, run only while on
  screen, calm down with Lower effects (`Quality`), and stop for players with Roblox's Reduce
  Motion setting (`GuiService.ReducedMotionEnabled`: simple fades, no floating or scrolling).
- **Smooth, never choppy**: Roblox snaps GUI positions and sizes to whole pixels, and there is no
  sub-pixel GUI rendering (staff, 2026-07-21). So nothing moves slowly by Position or Size. Slow
  motion is done by keeping the label still and sliding or zooming the picture inside it with
  fractional `ImageRectOffset`/`ImageRectSize`, or by rotation (which renders smoothly). Fast
  moves (pops, bursts, confetti falling) may use Position. Gate 1 proves which technique wins.
- **No CanvasGroup for reveals or fades** (black, blank or flickering on phones, blurry at low
  graphics, and it clips the overshoot). Fade a group by code: cache each descendant's
  transparencies (Background, Image, Text, TextStroke, UIStroke, UIShadow) and drive one alpha.
- **Budgets**: each image at most 1024 px on its longest side (Roblox downscales anything
  bigger); one ImageLabel per flipbook, stepping only `ImageRectOffset`; about 6 flipbook sheets
  visible at once; about 100 animated labels on screen; at most 100 UIShadows; at most one
  ViewportFrame per screen (none is planned here unless gate 1 picks the ViewportFrame scroll).
- **Text is real text** in the game's current kit style (`HudParts.text`: Fredoka One, white with
  the ink outline, the ink lip and hole fill from `HoleFill`), every word in `Strings`. Text never
  moves slowly and never pulses its scale endlessly; never tween a UIStroke's thickness on text.
- **No Studio-beta features** in the build (the upgraded UIGradient cannot be published yet).
  New features that are live and welcome: UIShadow (glows), multiple UIStrokes per object,
  per-corner radii, `StarterGui.ClipsDescendantsSupportsRotation` (rotating rays clipped).
- **Phone, PC and gamepad** for everything, as always.

## 4. The open, close and tab-switch sequences

The designer wants the open to last **about 1 to 2 seconds** in total (the references take
about one). Start around 1.4 s; the animatic (section 7.3) has a slider and the designer picks.
The order (the designer's default, approved):

1. **Unroll.** The panel appears as a thin white bar with the ink outline at its final width, in
   the middle of where it will sit, then opens up and down at once with a slight overshoot
   (about 0.2 s). Only the panel's chrome (fill, outline, shadow) unrolls; its contents wait.
   Build the chrome from native shapes so it is crisp at every height.
2. **The header band** fades in and its 8-ball pattern starts scrolling.
3. The **basket icon**, **"Shop"**, the **money pill** and the **red X** pop in, in that order.
4. The **tabs** pop in top to bottom (Featured, Blocks, Money, Passes), each **NEW badge** with
   a little bounce right after its tab.
5. **"- FEATURED -"**: the word pops, then its two lines grow outwards from it.
6. **The card's background** opens from its centre (about 0.15 s).
7. **The lucky block** slams in with a firework burst behind it; **its crown** drops on; the
   **NEW tag** pops in tilted.
8. **The title** pops in letter by letter, left to right, with a firework burst behind it; then
   the **subtitle**.
9. **The Beta card** pops in with a burst, then its name, pills, odds chip and cue in quick
   succession; then **the Grand Opening card** the same way.
10. **The buttons**: the three green Robux buttons left to right, the three gold money buttons,
    the "save" labels, then the **"Ends in"** timer.
11. **Flair**: the little 8-ball flair lands on the frame; the confetti and sparkles are running.

Each piece's idle loop starts as it lands. **Fireworks** (in place of the references' puffs)
burst only where big things appear: the block, each cue card, and behind the title.

- **Close**: everything fades fast while the panel folds back into a line and vanishes (about
  0.15 s, no stagger).
- **Every open** plays the full sequence. **Switching tabs** staggers only the new page's
  contents in (about 0.5 s), no unroll.
- **No waiting**: a button works as soon as it is visible; no skip is needed. Opening again
  mid-close, or spamming the tab, must always end in a clean, correct screen.
- **Reduce Motion**: the panel and pieces simply fade in; no unroll, no bulge, no floating or
  scrolling; glows may still breathe softly.

## 5. The frame

- **The white sheet**: back to the original dots (option A in `15`): the tiny solid and striped
  pool balls on an even staggered grid from commit `106a294` (`tools/gen_ui_art.py`
  `art_pattern()`), tinted pale blue `74,123,192` at about 8% strength (`PatternTransparency`
  0.92), one 256 px tile shown about 88 px across. Redraw the tile at twice the size so it is
  crisp, and match A's look at in-game size. It stays still.
- **The header band**: today's pale blue, with today's soft 8-ball pattern (`pattern.png`) a
  little more visible than now, **scrolling diagonally up-left at 45 degrees**, about one
  ball-spacing every 4 s, perfectly smooth (gate 1 decides how; a seamless texture window slid
  by fractional `ImageRectOffset` is the favourite).
- **Title, money, close**: as today, revealed as in section 4.
- **The four tabs** keep their look; they pop in one by one and the selected tab's icon rocks
  gently; NEW badges as today (`PinnedBadges`).
- **Flair**: the designer said "no crown, just a little 8-ball flair". One small glossy 8-ball
  ornament sitting on the frame (on the top edge near a corner, like the crow in `08`) with a
  tiny idle of its own (a little rock, now and then a hop with a sparkle). Gold streamers, confetti
  poppers on open and corner twinkles were offered too: build them as switches, **off by
  default**, and show them at gate 3 so the designer can decide.
- **The kit**: the new frame (unroll, dots sheet, moving header, flair) goes into the shared kit
  (`HudParts.menuCard` and `MenuFrame`) behind a per-menu switch in Config, on for the Shop only.

## 6. The Featured page: the Grand Opening card

**The target is 13b's look**: its layout, colours, shapes, glow and energy. The designer allowed
any source for each piece's pixels: (a) cut from 13b, (b) regenerated sharper with GPT Image 2.5
using 13b plus the in-game references as references, or (c) rendered from the real in-game
model or effect. For every piece pick whichever is sharpest and closest to 13b, and record the
choice. Additions to 13b: the two cue odds chips and the odds pop-up on the block.

**The pieces** (rough boxes in 13b's 2172 x 724 pixels; measure them properly):

| Piece | Where in 13b | Kind |
|---|---|---|
| Card: rounded navy panel, pale rim | whole image | native frame plus a background image |
| Background plate: navy depth, bokeh, light flares | behind everything | image (clean, nothing on it) |
| Floating 8-balls (blurred, at depths) | top centre ~(395-500, 15-115), bottom ~(500-600, 600-700), top right ~(1720-1840, 20-150), bottom right ~(1990-2160, 540-710) | one image each |
| Fireworks | behind the block ~(120-330, 20-200), left ~(0-120, 220-320), top ~(600-720, 10-100), top right ~(1880-2060, 30-200) | flipbooks |
| Gold confetti ribbons | scattered | a few sprites, animated by code |
| The Grand Opening lucky block | ~(60-520, 230-630) | image, with its own glow, rays and sparkles behind it |
| Its crown | ~(220-470, 130-300) | its own image (it drops on) |
| NEW tag | ~(40-275, 100-210), tilted | native pill plus real text |
| "Ends in 20d 23h" | ~(115-435, 620-670), cyan | real text, live |
| Two gold stars beside the title | ~(575-655, 70-150) and ~(1490-1570, 65-150) | images |
| Title "GRAND OPENING" | ~(660-1500, 15-125), gold, slight arch | real text first (below) |
| Subtitle "LUCKY BLOCK · LIMITED · YOU COULD PULL..." | ~(735-1440, 105-165) | real text, LIMITED in yellow |
| Beta card: rim cyan to magenta, navy inside with blueprint panels | ~(595-1295, 178-458) | native frame, a background image, blueprint layers |
| "BETA CUE", UNIQUE and LIMITED pills | top-left of the card | real text and native pills |
| The Beta Cue | diagonal, ~(620,440) to (1290,215), magenta rings | image plus a light-sweep mask |
| Grand Opening card: rim magenta to cyan, navy with fireworks | ~(1315-2122, 178-458) | native frame, a background image, firework flipbooks |
| "GRAND OPENING CUE" (gold and white), pills | top-left of the card | real text and native pills |
| The Grand Opening Cue with two gold sparkle ribbons | ~(1430,425) to (2085,225) | cue image plus a ribbon flipbook |
| Green Robux buttons ×3 | y ~483-553 | kit candy buttons, Robux glyph, real text, red strike prices |
| Gold money buttons ×3 | y ~565-640 | kit candy buttons, cash icon, real text |
| "save 12%", "save 29%" | ~(1210-1370, 650-690), ~(1710-1875, 650-690) | real text; 29% in the moving rainbow |
| **New:** odds chips "0.3%" and "3%" | each cue card's top-right corner | native chip, sky blue (`Kit.Numbers` odds colour) |
| **New:** the block's odds badge and pop-up | on the block | see Odds below |

**Words**: every word is real text in the game's kit style, read from `Strings`; prices, crossed
prices and odds are read from Config (`Config.Shop.Deals.GrandOpening.Money`,
`Config.Products.GrandOpening1/3/10` `Robux` and `Was`, the `GrandOpening` odds row), never typed
in. 13b has no gift squares beside the Robux buttons: leave them off this card and say so at
gate 2.

**The title**: the designer wants **real text first**, replicating 13b "as much as possible with
the curves and colours": letter by letter (so each letter can pop), set on a gentle arch like
13b, a gold gradient (pale yellow at the top to orange), the thick navy outline, the kit's ink
lip, a white gloss band, small sparkles. Show it next to 13b's painted title at gate 2. If real
text cannot get close, switch to the painted lettering cut letter by letter as a logo (the
exception to "every word is real text" is then the designer's call).

**Odds** (designer, 2026-10-06; this replaces "odds always visible on cards, no odds button" for
this card: log it in `docs/DECISIONS.md`):
- Each cue card shows its own chance in a sky-blue chip in its top-right corner: Beta 0.3%, Grand
  Opening Cue 3%.
- **All the odds appear when the player hovers or clicks the lucky block** (tap on a phone; select
  it with the gamepad and press A; B or tapping away closes it): a small card beside the block
  listing all eight outcomes in their rarity colours (Uncommon 56.35%, Rare 37.45%, Epic 2.5%,
  Legendary 0.35%, Mythic 0.046%, Secret 0.004%, Grand Opening Cue 3%, Beta Cue 0.3%), read
  from Config, summing to exactly 100%.
- Roblox's paid-random-items policy wants every outcome and its percentage shown before
  purchase, summing to exactly 100%; when they do not fit the view, a clickable pop-up is allowed
  behind an "Info" or "Details" icon that is visible and accessible before purchase. Hover alone
  is not enough (phones cannot hover), so it also opens by click, tap and gamepad, and the block
  carries a small, clear odds badge (for example a sky-blue "i") that never hides. Show the badge
  and pop-up design at gate 2.
- The designer also said: if the odds must be visible the whole time, show them first what the
  rarity chips would look like. They do not have to be (the pop-up with a badge is allowed), but
  put a mock of an always-visible chip row on the gate 2 sheet anyway so the designer can compare.
- No guarantee line (the 400th-block guarantee is not shown on this card).

**The block** (choice A): a 2D image of the Grand Opening block as in 13b, alive: a soft gold glow
pulsing behind it, gold rays turning slowly, sparkles twinkling around it, a gentle breathe
(smooth technique), a shine sweeping across it now and then, the NEW tag wiggling every few
seconds (`UIAnim.shake` "Wiggle").

**The Beta card**: the blueprint panels dim and brighten in slow waves (each panel its own phase),
a scan line sweeps down every ~3 s, a light pulse runs along the cue every ~1.5 s (a sweep clipped
to the cue's shape with a mask image, as the rank badges' shine is), the magenta rings glow,
gibberish glyph "code" (never English) scrolls in the background (smooth technique), a quick
glitch every 4 to 6 s (a short offset and a colour split), and a soft cyan-magenta aura breathes.

**The Grand Opening card**: mini fireworks in five colours bursting around the cue at random spots
every 0.5 to 1 s, two gold sparkle ribbons swirling along the cue (a looping flipbook), twinkling
stars, a gold glow breathing.

**The card background**: the 8-balls float slowly at three depths (smooth technique; the far ones
smaller and slower), the corner fireworks burst on a loop, gold confetti drifts down and tumbles,
bokeh twinkles. Medium busy: always moving, never fighting the prices. Lower effects halves the
counts and rates.

**The buttons**: kit candy buttons (green with the Robux glyph, gold with the cash bundle); a
shine sweeps across each every ~3 s, staggered; hover sway, press squish and the colour glow burst
as today; "save 29%" in the moving rainbow (a deal), "save 12%" plain white. They buy through the
existing server flow (products `GrandOpening1/3/10` and the money deal). **The three developer
products still have `Id = 0`** (not created yet): Studio test purchases cannot prompt without
them, so at gate 4 ask whether to create them with `tools/roblox_products.py` (dry-run first; the
ids go into Config and `tools/products_ids.json`).

**The timer**: live, cyan: "Ends in 20d 23h", in the last day "23h 59m", in the last hour "59:59".

**Phones**: the card restacks taller (the block and title on top, the two cue cards side by side,
then the six buttons in two rows); the page may scroll a little. Layers make this possible: no
piece is baked into another. Text never goes under the new screens' minimum (`Kit.Big`, 16 px;
UI_STYLE 13).

**The page**: only this card under "- FEATURED -".

## 7. Tools and pipeline

### 7.1 Tech spike first (gate 1)

Build a Studio-only test screen (behind a designer-only dev command or a `Config.Debug` switch;
removed or kept as a test tool afterwards) that shows these side by side, at the same speed:

1. The header scroll, 45 degrees up-left, four ways: (a) a still ImageLabel (ScaleType Stretch)
   showing a window into a seamless pattern texture, its `ImageRectOffset` moved by speed × dt
   on both axes and wrapped at one pattern period; (b) a Scale-based tile scroll (Tiffblocks'
   DevForum script); (c) a two-layer crossfade (two Tile copies 1 px apart, the top one's
   transparency set from the fractional part); (d) a ViewportFrame with a scrolling Texture.
2. A floating ball: whole-pixel Position plus the leftover fraction in `ImageRectOffset` (a
   texture with a few pixels of transparent border) against a plain Position tween.
3. A breathing icon: zooming the picture with `ImageRectSize` against a UIScale pulse.
4. A pop: UIScale plus the code fade against a CanvasGroup fade (sharpness at rest, any
   flicker).
5. The unroll of the native panel chrome.
6. A 64-frame firework flipbook, and a particle burst (Spark2D, MIT, `devforum.roblox.com/t/4830864`,
   or your own pooled emitter on one Heartbeat loop; pick one).

Record each at 60 fps (section 7.5) and make a contact sheet. The worst cases are a 100% DPI
screen and a phone at low graphics: ask the designer to switch Studio's device emulator (they do
it by hand; it cannot be scripted) for one recording on a 1x PC size and one on a phone, and set
the graphics quality low for one. Show the videos and your pick at gate 1.

### 7.2 Art (gate 2): may run in parallel with 7.1

You may give the art to a subagent while you run the Studio spike (only one agent ever drives
Studio). New scripts go in `tools/gui/` (Python; a `uv` virtual environment in
`tools/gui/.venv`, git-ignored):

- **Cutting pieces**: masks from LayerD (CyberAgent, made for banners, pip, runs on the CPU) and/or
  BiRefNet HR-matting or BEN2 (MIT, Apple MPS); "unmult" (render on black, brightness becomes
  alpha) for glows, sparkles and fireworks. Hidden areas behind pieces and the clean background
  plate are filled with masked GPT Image 2.5 edits (add `--mask` to `tools/openai_image.py` if it
  lacks it); paste back only the filled pixels. Upscale cut pieces with Real-ESRGAN
  `RealESRGAN_x4plus_anime_6B` (the macOS binary) when they would be shown larger than 13b holds.
  GPT Image 2.5 Sunburst makes clean transparent PNGs (`--background transparent`, checked on
  our icons); prompt "no background, no surface, no shadow"; same reference pack every call.
- **A rebuild check**: stack every layer at its place and compare with 13b (side by side and a
  difference heat map), and show each layer on black, white and a checkerboard.
- **Effects library** (reusable by every later screen): firework bursts in five colours, sparkles
  and twinkles, soft glows, light-sweep masks for the block and both cues, the gold sparkle
  ribbons (Blender: `/Applications/Blender.app/Contents/MacOS/Blender -b` or the Blender MCP,
  transparent film), the glyph-code strip, confetti pieces, the turning rays. Procedural ones may
  be drawn like `tools/gen_ui_art.py` does. Pack frames into sheets of at most 1024 px (4 × 4 of
  256, 8 × 8 of 128) with a script that also writes columns, rows, frame size and frame rate.
- **The frame's tiles**: the dot tile (section 5) and the header's seamless 8-ball texture.
- **Uploads**: `tools/roblox_upload.py --group-id 675425213`, always a dry-run first; ids in
  `tools/upload_manifest.json` and Config. Image uploads need no permission.
- **Spend**: the image tool's stop-and-ask point is **$500** for this run (the designer raised it
  from $150; add an override, keep the log). Say the running total in chat every $50. If the free
  cutting tools fall short, ask the designer whether they will open a fal.ai account (they
  create it, you never do) for Qwen-Image-Layered and pro upscaling; ask only if needed.

Gate 2 sheet: every piece with its source (cut, regenerated or rendered), the rebuild check, the
real-text title next to 13b's painted one (render the real text in Studio and screenshot it, so
the comparison is honest), the effect flipbooks as short looping previews, the dot tile, the header
texture, the odds badge and pop-up, the always-visible chip row mock, and the 8-ball flair.

### 7.3 The animatic (gate 3)

A browser page in `tools/gui/animatic/` that plays the whole open sequence and the idle loops with
the real pieces at their real places, using Roblox's easing curves (Back, Quart, Quint, Sine and so
on, written out in JS so they match TweenService). It has sliders for the total length (1 to 2
s), the stagger, the pop length, the overshoot, the fade and the unroll; 0.1×, 0.25× and 1×
speed; frame-by-frame stepping; replay; switches for the optional flair (streamers, poppers,
twinkles). It exports its values as JSON, and the approved values go into Config unchanged. Open
it locally in Chrome and, if your Artifact tool is available, also publish it as a private
claude.ai link the designer can open on their phone.

### 7.4 The build

- **`Stage`** (a new client module, or a part of `UIAnim`): reveal timelines (`Pop`, `Fade`,
  `Slam`, `Letters`, `Unroll`, `Grow`, `Burst`, each with a start time, length and overshoot),
  the code fader, close and tab-switch versions, cancel and restart, Quality and Reduce Motion.
- **The idle library**: glow pulse, ray spin, shine sweep, masked light sweep, breathe, float,
  scroll, flipbook, sparkle, confetti, glitch, scan line, rainbow; every slow motion through the
  gate 1 technique. Reuse and extend `UIAnim`; do not fork it.
- **Config**: shared motion tokens (`Config.UI.Kit.Motion` or a new `Config.UI.Motion`), the
  Shop's timeline, the card's layout and effect numbers, asset ids. Every word in `Strings`.
- **Tests**: Lune tests for the pure parts (timeline maths, easing curves, flipbook frame maths,
  the odds sum of exactly 100%, the timer's format).

### 7.5 Seeing it: recordings and contact sheets

- **Before the run starts** the designer turns on Screen Recording for their terminal app (System
  Settings, Privacy and Security, Screen and System Audio Recording) and reopens it. Install
  ffmpeg with Homebrew yourself (`brew install ffmpeg`).
- Record the Studio window's game view for a few seconds while `GuiQA` opens the Shop
  (`screencapture -v -V<seconds> -R<x,y,w,h> out.mov`, or OBS, which is installed), split it into
  frames with ffmpeg, and build a contact sheet of every second frame (about 33 ms apart),
  numbered with times, like the designer's stills `01` to `08`. Compare with them yourself before
  showing the designer.
- A Studio-only slow-motion switch (all reveal times × 10) lets Studio MCP `screen_capture`
  catch each step.
- If the design plugin's `design-critique` skill is available, run it on the gate pictures against
  the references before each gate, and fix what it finds first.
- Performance: frame time and GUI texture memory (MicroProfiler or `Stats`) with the Shop open,
  with Lower effects on and off; count the animated labels.

## 8. Approval gates (stop, show, wait)

1. **Tech spike**: the recordings and contact sheet, and your recommended technique for each
   motion.
2. **Art sheet** (section 7.2). Gates 1 and 2 may be shown together if both are ready.
3. **The animatic**: the designer plays with the sliders and approves the choreography; their
   numbers go into Config.
4. **First look in Studio**: a recording and contact sheet of the real open, the idle loops, a tab
   switch and a close; the designer tries it. Ask about creating the three developer products here.
5. **Final**: phone and PC (the designer switches the emulator), gamepad (the block's odds with
   A), Lower effects, Reduce Motion, performance numbers. Then the skill.

## 9. Ask first

Nothing should need asking before you start: the designer answered the interview (the answers
are in `00-research-and-questions.md`). If something is still unclear, ask it in one message at
the start, then begin.

## 10. How to work

- Start: you are on `shop-lively` (made by the launch command from `release`). Commit after each
  verified step with a clear message and the attribution line; push the branch. Never push
  `main`, never force-push.
- `place/8ball.rbxl` and `assets/cue/concepts/openai_log.jsonl` were already modified before the
  run; the log is appended by the image tool and is committed with your art; leave the place file
  to the designer's per-milestone save.
- Scripts are files under `src/` and reach Studio through Rojo (the designer clicks Connect when
  asked); never create or edit scripts through the Studio MCP. You may stop play sessions freely.
- Keep big intermediate files out of git: work in `~/Desktop/8ball-refs/gui-lively/work/` or a
  git-ignored folder; commit only the tools, the final source art that the repo keeps for
  icons, and the code.
- Small calls: choose the sensible option, note it in the Decisions list below, keep going.
- Docs as you go: `docs/STATUS.md` (current state only), `docs/DECISIONS.md` (dated lines: the dots
  back on the sheet, the moving header, the unroll reveal, odds on the block, the smooth-motion
  technique, the new menu look as a kit switch), `docs/UI_STYLE.md` (rewrite sections 7 and 13 for
  the new motion rules; the rule "an icon never moves up and down" is replaced by the proven
  technique; update 2 and 15), `docs/STUDIO_NOTES.md` (recording, the ImageRectOffset findings).

## 11. Hard rules

- Never change an economy number (prices, odds, timers, products); read them from Config.
- Uploads: dry-run first, the group id, the manifest. Never print or write a key.
- Never buy anything real; Studio test purchases only.
- Never create accounts or enter credentials; the designer does that.
- Admin and test commands work only for the designer's account (CLAUDE.md).
- Spend: stop and ask at $500 of images.

## 12. The skill (after gate 5)

Write the project skill `.claude/skills/lively-gui/` from what actually worked in this run:

- `SKILL.md` (under 500 lines; frontmatter `name: lively-gui` and a third-person description that
  says when to use it: building, restyling or animating any Crazy 8 Ball screen, menu, popup,
  card, HUD element or icon). It holds the method: references, then the piece list, art, the
  animatic, the build with `Stage`, verification with recordings, the gates. Also the house
  entrances: menus unroll, popups slam in from big, cards and buttons stagger in, small HUD pieces
  just pop, every screen keeps at least one idle loop.
- Reference files one level deep: `motion.md` (the tokens with their Config names, easing, the
  smooth-motion technique with code), `art-pipeline.md` (commands, prompts, cutting, unmult, sheets,
  uploads), `verification.md` (recording, contact sheets, budgets, devices), `pitfalls.md`
  (pixel snapping, CanvasGroup, ViewportFrame, the 1024 cap, text, Studio-beta features).
  Scripts stay in `tools/gui/` and are referenced from the skill.
- Add a line to `CLAUDE.md`'s "Read first" list pointing every tool (Codex too, through
  AGENTS.md) to the skill for any GUI work, and point `docs/UI_STYLE.md` section 7 to it.
- Test it: in a fresh subagent, ask it to plan the Inventory screen with the skill and check the
  plan follows the method; fix the skill where it does not.

## 13. Handoff (write when done)

Write `docs/prompts/SHOP_LIVELY_REPORT.md`: what was built, each gate's result and the designer's
notes, links to the recordings and sheets, the spend, the asset ids, what to try by hand, and what
comes next (Blocks, Money and Passes with the skill; the other menus switching to the new frame).

## Progress

- [ ] 1. Read section 0, study the references, list every piece of 13b with its planned source
      (cut, regenerated or rendered) and its reveal and idle behaviour; set up `tools/gui/`.
- [ ] 2. Tech spike in Studio (section 7.1), recordings and contact sheet; **gate 1**.
- [ ] 3. The card's pieces, the rebuild check, the title A/B, the odds badge and pop-up, the
      chip-row mock, the 8-ball flair, the dot tile and the header texture; **gate 2**.
- [ ] 4. The effects library (fireworks in five colours, sparkles, glows, sweep masks, ribbons,
      glyph code, confetti, rays) packed and uploaded.
- [ ] 5. The animatic with sliders and optional flair switches; **gate 3**; the approved values
      in Config.
- [ ] 6. `Stage`, the idle library and the motion tokens in Config, with Lune tests.
- [ ] 7. The frame: unroll and fold, dots sheet, moving header, tabs and badges, the 8-ball flair,
      the tab-switch stagger, the kit switch (Shop on).
- [ ] 8. The Grand Opening card: every piece and loop, real text, the odds chips and the block's
      odds pop-up, the buttons on the existing buy flow, the live timer, the phone layout.
- [ ] 9. Recordings and contact sheets against the references, performance, Lower effects,
      Reduce Motion, gamepad; **gate 4**.
- [ ] 10. Polish from the designer's notes; phone and PC (the designer switches the emulator);
      final recordings; **gate 5**.
- [ ] 11. The skill `.claude/skills/lively-gui/`, the `CLAUDE.md` pointer and the docs
      (UI_STYLE, DECISIONS, STATUS, STUDIO_NOTES).
- [ ] 12. `docs/prompts/SHOP_LIVELY_REPORT.md` and the handoff.

## Status

(The run writes dated lines here.)

## Decisions

(Small calls made during the run, one dated line each.)

## Notes

(Anything the next step or the skill should know: what worked, what did not, numbers.)
