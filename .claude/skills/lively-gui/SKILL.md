---
name: lively-gui
description: The Crazy 8 Ball method and house format for any GUI work. Use when building, restyling or animating any screen, menu, popup, card, HUD element or icon in this Roblox game (the Shop's pages, Inventory, Index, Trading, Settings, Daily, rewards, popups, HUD pieces). It covers the target picture, the piece list, the art, the browser animatic, the build with Stage and the idle library, verification with recordings, and the designer's approval gates, scaled to the size of the screen.
---

# Lively GUI

The lively Shop (branch `shop-lively`, 2026-10-06, brief `docs/prompts/SHOP_LIVELY_PROMPT.md`)
is the template for every GUI in this game. The designer said: "every future gui should follow
this same workflow and format, with the background frame, animation popup". This skill is what
actually worked in that run. Read it whole before planning a screen, then the reference file
for the step you are on:

- [motion.md](motion.md): the motion tokens and their Config names, easing, the smooth-motion
  technique with code, Stage and the idle library.
- [art-pipeline.md](art-pipeline.md): target pictures, cutting, generating, rendering, baking
  pieces, flipbook sheets, uploads and image ids, spend.
- [verification.md](verification.md): GuiQA hooks, recordings and contact sheets, the emulator,
  devices, Lower effects, Reduce Motion, budgets, performance numbers, gate pages.
- [pitfalls.md](pitfalls.md): what broke or looked wrong, and the fix.

CLAUDE.md's rules still apply on top (scripts only under `src/` through Rojo, every number in
`Config.luau`, every word in `Strings`, phone + PC + gamepad, commit after each verified step).

## 1. The house format

### The frame (every full menu)

A full menu uses the **lively frame**, a kit switch per menu: add the menu's name to
`Config.UI.Menu.LivelyMenus` and give it an open schedule at `Config.UI.<Name>.Open` (see
`Config.UI.Shop.Open`; `MenuFrame` looks for `Config.UI[<name>].Open`, the name as
`Menus.register`). `MenuFrame` then builds the panel, header, money pill, X and flair, makes
`frame.stage` and plays it; the menu adds its own pieces (tabs, page) to that Stage:

- **The panel unrolls**: a thin bar with the ink outline at its final width, opening up and
  down at once with a slight overshoot (0.2 s); only the chrome unrolls, the contents wait.
  It folds back to a line on close (0.15 s, everything fades, no stagger).
- **The header band**: pale blue, its 8-balls scrolling up-left at 45 degrees (a window into a
  seamless tile, `Config.UI.Menu.Lively.Header*`). Compact: the title and its icon fill the
  row; the red X is a little smaller than the money pill; a gold **+** on the money pill jumps
  to the Money page (`moneyPlus` in `MenuFrame.new` opts).
- **The white sheet** with the still tiny pool-ball dots (`Lively.Dots*`). It never moves.
- **The tabs stand outside the panel's right edge** (a column inside when the screen has no
  room there), pop in top to bottom, each NEW badge with a bounce right after; the lit tab's
  icon rocks gently. The Shop builds this rail itself (`ShopMenu`: `HudParts.tile` jump buttons
  in `frame.panel`, `railOutside`, `Config.UI.Shop.Page.Rail*`, Stage ids `Tab<n>` and
  `Tab<n>Badge`); reuse that code for a menu with tabs.
- **The 8-ball flair** pinned on the panel's left edge (`Lively.FlairDownShare`): it drops on
  last, rocks, and now and then hops with a sparkle.
- **Compact size**: at most 66% of the screen's width (`Lively.MaxWidthShare`), never in
  Roblox's top bar row, only as tall as the page's first card (`frame.fitHeight`), with the
  next section's header peeking in at the bottom (`PeekPx`) so players know to scroll.
- **One thing at a time**: while a full menu is open every other screen of ours is hidden
  (`HudFocus`, automatic for anything opened through `Menus`; exceptions in
  `Config.UI.Menu.Focus.Keep` / `KeepWith`). Too much on screen at once tires the eyes.
- **The world blurs behind** (`ScreenBlur`); never a dark dim.

**Other menus switch to this frame one at a time, each when it is rebuilt with this skill**
(designer, 2026-10-06), never all at once, so no menu looks half-done.

### The house entrances

| What | Entrance | Stage kind |
|---|---|---|
| A full menu | the panel unrolls, then its pieces stagger in | `Unroll`, then `Pop`/`Fade`/`Grow` |
| A popup (dialog, odds card, gift list, reward) | slams in from big, a bulge as it lands | `Slam` (or `UIAnim.slam`) |
| Cards, buttons, tabs, chips | pop in one by one, a few hundredths apart | `Pop` with `Stagger` |
| Backgrounds and lines | open from their centre | `Grow` |
| Something that lands on top (a crown, the flair) | drops on with a bounce | `Drop` |
| Small HUD pieces | just pop | `Pop` (or `UIAnim.popIn`) |
| The hero piece and big cards | arrive with a small firework burst behind them | `Burst = "<colour>"` |

The open lasts about 1 to 2 s in all (the Shop's is 1.07 s: the frame first, then the page's
pieces twice as fast). A tab switch replays only the new page's pieces (0.5 s, no unroll). A
button works the moment it is visible: no skip, no waiting. Reopening mid-close or spamming a
tab must always end on a clean screen.

### Idle: something always moves, calmly

Every screen keeps at least one idle loop. A piece's loops start when it lands (in its
`onLand`), at a random phase, run only while on screen, calm down with Lower effects
(`Quality`) and stop with Reduce Motion (glows may still pulse softly). The library is in
`UIAnim` (motion.md): glow pulse, rays turning, breathe, masked shine sweep, float, scroll,
flipbook, rock (`UIAnim.turn` with degrees), sparkle, confetti drift, burst loop, scan line,
glitch, rainbow.

### The designer's taste rules (learned at gate 4, 2026-10-06)

Each rule came from a note on the Shop; apply it everywhere.

- **No wasted space.** Tight rows, small gaps, a compact header; the first card fills the
  panel. Big empty margins read as unfinished.
- **The first card fits a phone's page whole**: keep the computer arrangement and scale it to
  fit (`layout(width, height)`), no restack, nothing scrolls inside the first screen. This
  newer rule wins over older restack settings on a screen being rebuilt (the Inventory's
  `StackFromPx`); if a layout truly cannot fit, ask with a mock of both. Its
  smallest text may go to 12 px on a phone (`Layout.MinTextPx`; pills 9 over art).
- **No clutter labels.** No "save 12%" lines, no LIMITED pill when UNIQUE already says it,
  no description line unless truly needed. Make the button and its words bigger instead.
- **Robux comes first**: Robux buttons are bigger than money buttons, and **only Robux
  buttons shine** (the money buttons stay still so the eye goes to Robux). A purple gift
  square sits left of every Robux button for a developer product (the Gift Player popup).
- **Sibling cards match**: the same chip (odds, price) in the same corner on every card.
- **Labels never cover the art they label**: pills and chips sit clear of the cue, block or
  icon; shrink them first.
- **A busy picture gets a tinted glow** so it stands out of a busy background (the Firework
  Cue's yellow aura, `tools/gui/cue_glow.py`).
- **Calm, never choppy**: a flipbook at a low frame rate looks choppy. The Firework Cue's gold
  ribbons were a 6.7 fps loop, then a breathe, then a rock; the designer settled on **one still
  picture that dims and glows** (`UIAnim.glowPulse`). Prefer a still picture with a pulse,
  shine or rotation over a slow flipbook.
- **The small decorative part moves, not the hero**: animate the ribbons, not the cue; the
  crown breathes with the block because it is baked into the block's picture.
- **Faster beats slower**: when in doubt, speed up (the card's part of the open went 2x; the
  block's breathe went 3.1 s to 2.3 s).
- **A rename is total**: when the designer renames an item, rename it in Strings, ids, Config
  keys, asset files, the manifest, tools and place instances, with a save migration and the old
  DataStore keys kept where numbering or counts depend on them (`Config.Items.RenamedCues`).

## 2. Scale the process to the screen

The designer chose (2026-10-06): **big screens go through every gate; small popups and HUD
pieces get a Studio first look, then the final check.**

| | Big screen (a menu, a page, a hero card) | Small piece (a popup, a dialog, a HUD element, an icon) |
|---|---|---|
| Target picture | yes (gate A) | only if the look is new |
| Piece list | yes | a short one in the plan |
| Art sheet | yes (gate B) | no: reuse the effects library and kit parts |
| Browser animatic | yes (gate C) | no: use the house entrance and tokens |
| Studio first look | yes (gate D) | yes (gate D) |
| Final check | yes (gate E) | yes (gate E) |

A **tech spike** (the Shop's gate 1) is needed only for a motion the library cannot already do
smoothly; the techniques are settled (motion.md).

The gates are lettered here; the Shop run numbered them (its gate 1 was the tech spike, gate 2
the art sheet = B, gate 3 the animatic = C, gate 4 the Studio first look = D, gate 5 the final
check = E). A restyle of an existing menu is a big screen too.

At every gate: stop, show, wait; ask at most three short questions and take the designer's
notes as the next step. When the session runs under the overnight stop hook
(`tools/overnight/keep_going.sh` feedback appears when you stop), run `touch
.git/overnight-waiting` before stopping so the hook lets you wait; otherwise just ask. A newer
note beats an older decision: update the docs and add a dated line to `docs/DECISIONS.md`.

**The brief.** A big screen gets its own brief, `docs/prompts/<SCREEN>_LIVELY_PROMPT.md`, made
from the Shop's (`SHOP_LIVELY_PROMPT.md`: scope, references, pieces, the open, gates, hard rules,
a Progress list, Status, Decisions, Notes); its spend cap defaults to $500 of images unless the
designer sets another. A small piece needs no brief: its gates go in `docs/STATUS.md`.

## 3. The method

### A. The target picture (big screens)

The target is one picture of the finished screen at full quality, like the Shop's `13b`.
**It comes from the designer when they have one; otherwise mock two or three in the game's
style and let them pick (or mix)** (art-pipeline.md, "Target mocks"). Study the references
closely: measure boxes, list colours, note which parts move in the references' videos.
Before mocking, read the screen's current module and Config so the mock shows what the screen
really holds today; anything the request adds or drops (a tab, a kind of item) is a question
for gate A, not a guess. Also ask which piece is the hero.

### B. The piece list

List every piece of the target in a JSON beside its tools (the Shop's is
`tools/gui/grand_opening/pieces.json`): its box in the target's pixels, its **source** (cut from
the target, regenerated sharper, rendered from the real in-game model, or drawn by code), its
reveal step and its idle loop. Rules:

- **Every piece is separate**: its own Instance (often its own image), named, with a reveal
  step and, where it makes sense, an idle loop.
- **Frames, pills, chips and buttons are native** kit parts (`HudParts`, `ShopParts`), never
  pictures, so they stay crisp and take real text.
- **Every word is real text** in the kit style (`HudParts.text`, Fredoka One, the ink outline),
  read from `Strings`; numbers (prices, odds, timers) from Config. A big title may be arched
  letter by letter (`ArchTitle`).
- Plan the screen's own **units** (the Shop's card is 1275 x 498 units, `Layout` in Config):
  everything is placed in units and scaled by one factor `k = width / units`, so a phone and a
  computer show the same arrangement.

### C. The art (gate B: the art sheet)

Make each piece from its source (art-pipeline.md), at most 1024 px on its longest side. Then a
**rebuild check** (all layers stacked against the target, a difference heat map, each layer on
black, white and a checkerboard) and an **art sheet** for the designer: every piece with its
source, the real-text title rendered in Studio beside the target's, effect flipbooks as looping
previews, odds badges and pop-ups. Publish the sheet as a private page (verification.md).
Upload only after approval.

### D. The animatic (gate C)

A browser page (copy `tools/gui/animatic/index.html` to `tools/gui/animatic/<screen>.html`
and change its `FILES` and piece table; a grid shows a fixed sample of cards) that plays the whole open and
the idle loops with the real pieces at their real places and real size, using Roblox's easing
curves written out in JS. Sliders: total length, stagger, pop length, overshoot, fade, unroll;
0.1x / 0.25x / 1x; frame stepping; replay; switches for optional flair. It exports JSON; **the
approved values go into Config unchanged** (`Config.UI.Motion`, `Config.UI.<Name>.Open`, the
screen's `Loops`). Serve it locally (`python3 -m http.server 8765` from the repo root; `?t=1.2`
freezes a moment) and publish it so the designer can open it on a phone.

### E. The build

1. **Config**: the open schedule `Config.UI.<Name>.Open` (`OpenSeconds`, `Steps` of
   `{ Ids, Kind, At, Stagger?, Length?, Burst?, Badge?, BadgeAfter? }`), the screen's `Images`,
   `Layout` (units) and `Loops`, each number with a comment. Reuse `Config.UI.Motion` tokens.
   The frame's ids are the same for every menu (`Panel`, `Header`, `Basket` = the menu's icon,
   `Title`, `Money`, `Close`, `Flair`). `Burst` picks one of the five baked firework colours
   (Gold, Pink, Cyan, Purple, Orange); a new colour is a new sheet from `tools/gui/effects.py`
   (a tint cannot brighten).
2. **Strings**: every word.
3. **The page module** (one per screen, like `GrandOpeningCard`): `new(parent, actions)` builds
   every piece closed; `layout(width, height?)` places them in units scaled by `k` (given a
   height, it shrinks to fit whole) and returns its height; a static `heightFor(width)` for the
   frame's `fitHeight`; `register(stage, keep)` adds every piece to the Stage by its schedule
   id, starting its idle loops in `onLand` and handing their handles to `keep` (the frame stops
   them on close); `closed()` tidies popups.
4. **A data-driven page** (a grid of cards, a list): give schedule ids only to what the first
   screen shows (the header, the controls, the first rows of cards, capped so the open stays
   under 2 s), registered in reading order; cards past that, and cards rebuilt after a change
   (`ItemState.Changed`), just `UIAnim.popIn` with no stagger. Idle loops go on the hero and a
   few chosen pieces, never on every card (about 100 animated labels at most); a card scrolled
   out of view may keep a cheap loop, but stop anything costly. `fitHeight` is the first
   screen's height (the hero area or the first rows), up to the room under the bar.
5. **The menu module** (like `ShopMenu`): `MenuFrame.new(screen, { name, title, icon, money,
   moneyPlus })`, the page in a scroller, `frame.stage` for the tabs and the page's
   `register`, `frame.onOpen/onClose/onLayout`, `frame.fitHeight`, a tab switch calling
   `stage:replay(stage:idsUnder(scroll))`, registration with `Menus`.
6. **Buttons** buy or act through the existing server flows (never trust the client); a
   refusal shows the server's reason as a notice.
7. **Gamepad**: every control is a Selectable with sensible neighbours; A presses, B closes a
   popup then the menu, LB/RB switch tabs; a hover-only thing (the odds pop-up) also opens by
   click, tap and A.
8. **Test hooks**: add Studio-only `GuiQA` actions for anything the checks need (fake data,
   a slowed open, Lower effects, Reduce Motion); never in a live server.
9. **Tests**: pure maths goes in `src/shared` (`StageMath`) with Lune tests
   (`tests/stage_math_test.luau`): timelines, easing, flipbook frames, windows that stay
   inside their pictures, odds that sum to exactly 100%, timer text.

### F. Verify (gate D, then gate E)

verification.md has the commands. In short: lint and tests; Rojo synced; Play; open through
`GuiQA`; read the console; screenshots and a 60 fps recording of the open, a tab switch, the
idle loops and a close; contact sheets compared with the target and the references yourself
first; performance with Lower effects off and on; Reduce Motion; phone emulator, then the
designer switches to a PC size and tries a real gamepad (the two checks an agent cannot do).
Show it on a private gate page with the recordings, the numbers and one short list of
questions.

### G. Finish

Commit after each verified step (only your own files; never commit `place/8ball.rbxl` in a GUI
run: the designer saves the place once per milestone, as CLAUDE.md says, and it is committed
with that save), push the branch, tick the brief's box (or update STATUS for a small piece), update `docs/STATUS.md` (current state only), `docs/UI_STYLE.md`
(the screen's decided look) and `docs/DECISIONS.md` (dated lines). Ask once per milestone to
save the place and publish.

## 4. Where things are

| What | Where |
|---|---|
| Reveal player | `src/client/Stage.luau` (pure maths in `src/shared/StageMath.luau`) |
| Idle library | `src/client/UIAnim.luau` |
| The lively frame | `src/client/MenuFrame.luau`, `HudParts.livelyCard`, `HudParts.lively(name)` |
| One thing at a time | `src/client/HudFocus.luau`, `Config.UI.Menu.Focus` |
| The worked example | `src/client/ShopMenu.luau`, `src/client/GrandOpeningCard.luau`, `src/client/ShopGift.luau` |
| Test hooks | `src/client/GuiQA.luau`, `src/client/ShopLab.luau` (`lab`, `quality`, `reduced`) |
| Motion tokens | `Config.UI.Motion`; the Shop's open `Config.UI.Shop.Open`; frame `Config.UI.Menu.Lively` |
| Effects library | `Config.UI.Effects` (fireworks in five colours, sparkle, rays), `assets/ui/effects/` |
| The card's numbers | `Config.UI.GrandOpeningCard` (`Images`, `Loops`, `Layout`) |
| Art tools | `tools/gui/` (README there), `tools/openai_image.py`, `tools/roblox_upload.py` |
| The animatic | `tools/gui/animatic/index.html` |
| The run's history | `docs/prompts/SHOP_LIVELY_PROMPT.md` (Status, Decisions, Notes) |
