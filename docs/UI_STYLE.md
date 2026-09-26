# UI style

How every screen looks. Read this before building or changing any UI. Like the GDD, each
section is split into Decided and Open; never guess an Open item, ask. Starting values are
first guesses; the kit's live values are in `Config.UI.Kit` (section 8).

References live in `assets/ui/reference/`. More are coming (a shop, a victory or reward
screen, a popup).

## 1. The look

**Decided**
- **Cartoony, bubbly, bright and colourful**: casual mobile game style. Chunky shapes, thick
  outlines, very round corners, glossy icons.
- Reference `01-match-bar.webp`: take its chunky shapes, thick outlines, glossy balls and
  compact layout. Do not take its dark panels (ours are white, section 2).
- Clean, thumb-friendly, icons before words, readable at phone size (GDD section 16).

## 2. Panels

**Decided**
- **White panels.**
- **A thick outline in the dark ink** of the text outlines, so the whole UI looks inked like a
  cartoon (2026-09-25).
- **A soft white-to-pale-blue fade and a soft drop shadow**, so panels look puffy, not flat.
- **A faint pattern of tiny pool balls** (some striped) over every panel, about 8% strong:
  felt more than seen.

## 3. Text

**Decided**
- **Fredoka One for all text.** Roblox has it in one weight only (checked in Studio
  2026-09-25), so titles stand out by size, colour and outline, not boldness.
- **White text with a dark outline** for titles, names, numbers and buttons.
- **Small descriptive text is dark ink with no outline** (descriptions, notes, detail lines):
  on small text an outline squeezes the letters together and fills the o's and a's, and
  Roblox cannot space letters out (designer, 2026-09-26).
- Every word is real Roblox text (TextLabel, TextButton, TextBox), never part of an image,
  and lives in `Strings`. This is what makes Roblox automatic translation work.
- Text must survive translations about 40% longer than English: it shrinks to a minimum size
  or its box grows. It never gets cut off.
- A sentence with a number or name in it is stored whole, with a placeholder
  ("You won {1} money"), never glued together from pieces.
- Player names are never translated (`AutoLocalize` off on those labels).

**Starting values**
- Sizes: title 32, heading 22, button 20, body 16, never below 14 px (2026-09-26: the whole
  PC GUI shrunk to about 80% of the first build; it was 40, 28, 24, 18 and 16).
- Outline: about a tenth of the text size, at least 2 px. Ink `#1B2033`.

**Decided exceptions** (2026-09-25)
- Ball numbers may be smaller than 16 px: they are part of the ball graphic.
- A long player name ends in "..." instead of shrinking or wrapping: names are data, not
  reading text, and are never translated.

**Open**
- If Fredoka One looks blobby at small sizes on a phone, switch only the small text to
  Nunito (suggestion).

## 4. Colours

**Decided**: rarity colours. The hex values are starting values. The table is not the rarity
order; that is Open.

| Rarity | Colour | Starting hex |
|---|---|---|
| Common | grey | `#9CA3AF` |
| Uncommon | green | `#3DD66B` |
| Rare | blue | `#3B9BFF` |
| Epic | purple | `#A259FF` |
| Legendary | gold / dark yellow | `#F2B200` |
| Mythic | celestial prismatic | shimmer `#7FE7FF` `#B79CFF` `#FF9CE6` `#FFFFFF` on space `#1A1446` |
| Unique | pink | `#FF5CB8` |
| VIP | rainbow | `#FF4D4D` `#FF9F1C` `#FFE14D` `#3DD66B` `#3B9BFF` `#A259FF` |

- **Mythic and VIP must never look alike.** VIP is a bold, fully saturated rainbow. Mythic is
  pale and holographic: a slow pastel shimmer over a deep-space background with small
  twinkling stars.

**Decided for now** (2026-09-25; may change)
- **Traffic button colours:** green for Start, Play and Yes; red for Leave and Surrender (in a
  dialog, the button that leaves or surrenders is red and the one that keeps playing blue);
  blue for choices and whatever is selected; yellow for special things (SOON, the coin).
- **The house accent is blue.** A gamepad-selected or hovered button gets a thick gold outline.

**Open**
- Grandmaster's rank badge uses the VIP rainbow (2026-09-26). If VIP items also look rainbow,
  decide whether the two should differ so a rank is never mistaken for a VIP item.
- The order of the rarities (where mythic and unique sit) and what VIP means (GDD section 12).

## 5. Buttons

**Decided**
- Touch targets at least 44 px (as in `Config.UI.Spin.ButtonSizePx`).

- **Raised candy buttons** (2026-09-25): lighter on top, a darker lip along the bottom, an ink
  outline, and a squish when pressed. An icon may sit left of the words. Colours: section 4.

## 6. Icons and images

**Decided**
- **Money is a stack of green cash.** Never coins.
- No words in any image. Transparent PNGs in `assets/ui/`, made from one shared style prompt
  so they match.
- Frames and buttons are built from Roblox shapes (UICorner, UIStroke, UIGradient), not
  images, so they stay sharp on every screen and recolour with one value. Images are for
  icons and effects only.

- **Glossy cartoon icons** with a thick ink outline, a small drop lip and a shine (2026-09-25).
  They are drawn in code from one shared style (`tools/gen_ui_art.py`) so they match; any can
  be swapped for a better image by changing its id in `Config.UI.Kit.Icons`.
- The difficulty levels are pictures of what you get on a little table: Classic every line,
  Difficult the aim line only, Challenger no lines and a crossed-out eye.
- **Rank badges** (designer, 2026-09-26; `assets/ui/ranks/`, made by `tools/gen_rank_badges.py`,
  not in the game yet). 47 images: Unranked (plain grey), five per tier from Bronze to
  Grandmaster, and one Reyes. Each tier is its own badge after the designer's reference sheet
  (a faceted frame round a big 8 ball; side plates for Bronze to Gold, crystal feathers for
  Platinum, crystal shards for Diamond, fins for Expert, a laurel for Veteran, a crystal burst
  for Master, swept wings for Grandmaster), not one more ornament per tier. The same rules on
  every badge: the ball and its ring the same size in the same place; a crown from Expert up
  (bigger each tier, Veteran included; Reyes the biggest, in gold); pips in an arc under the
  ball: 1 to 5 stars from Bronze to Diamond, 1 to 5 gems from Expert to Grandmaster (1 =
  division I), big and bright, spaced so they never overlap and set in one smooth curved tray
  in a deep shade of the tier's colour (darker by the ball, a lit rim, a soft glow and shadow
  under each pip), so the count reads when the badge is small. Diamond is cyan; Grandmaster is a rainbow badge in the house
  rainbow (section 4's VIP colours: a rainbow frame and ring, feathers red to purple,
  prismatic gems) (2026-09-26). Reyes is black and gold with no pips and no signature. No
  banner and no words: the rank's name is game text beside the badge where needed.

## 7. Motion

**Decided**
- Every animation comes from one shared `UIAnim` module (pop in, slide, shine sweep, pulse,
  float, spinning rays, confetti, count-up), so all screens move alike. Looping effects stop
  when their screen closes.

- **How lively** (2026-09-25): panels and popups pop in with a small overshoot and pop out
  quickly. Only important things shine, bounce or breathe: your turn (the cue pops and a shine
  sweeps the status card), the win card (the trophy over turning rays), Start once it can be
  pressed, a ball going down. Later: Rematch, rewards, shop deals.
- **Rank badges always shine** (designer, 2026-09-26), more as you climb: a light sweep (the
  same band as the shine sweep, clipped to the badge's shine mask) from Bronze to Diamond,
  plus twinkling sparkles from Expert up, plus turning gold rays behind Reyes. Unranked is
  still. Timings are in `assets/ui/ranks/README.md`.

**Open**
- Whether the VIP rainbow and the mythic shimmer move (suggestion: yes, both slow).

## 8. Built (2026-09-25)

- **The kit:** `src/client/HudParts.luau`: card (shadow, fill, outline, pattern), pill, kit
  text, candy button and tile, icon, HUD ball (ink ring, stripe band, number disc, gloss, red
  X when down). Tokens in `Config.UI.Kit`; `src/client/UIAnim.luau` for every animation.
- **The art:** `tools/gen_ui_art.py` renders the icons (`assets/ui/icons`) and the effect
  images (`assets/ui/art`: the pattern tile, ball gloss and band, rays, 9-slice shadow).
- **Screens:** the match top bar and status card, the foul popup (no panel, 3 s), the hints,
  the leave and surrender dialog, the coin and result cards, the host menu, the floor box, the
  table sign (only near its table), the power bar, the spin panel and the pocket targets.
- **Phones** (2026-09-26): the top bar is compact and sits in Roblox's own top row beside its
  menu, chat and voice buttons (it asks Roblox for that room, ScreenInsets.TopbarSafeInsets),
  so the table keeps the screen. The host menu stays one column on the right, short enough to
  fit, beside the jump button (or above it when that lets it be bigger).
- **The status card** (2026-09-26): one line ("YOUR TURN", "THEIR TURN", "FOUL!"), a big clock,
  and a small red door for Leave whose touch area is still 44 px. No names under the
  portraits (a rank badge goes there later).
- **The host menu:** a small red door beside a wide Start; the money each difficulty pays
  (cash icon and 1x, 1.5x, 2x) under its tile; one short line describing the chosen level.
