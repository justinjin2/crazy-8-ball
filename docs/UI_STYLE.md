# UI style

How every screen looks. Read this before building or changing any UI. Like the GDD, each
section is split into Decided and Open; never guess an Open item, ask. Starting values are
first guesses, tuned on the first screen built, and move into `Config.UI` when the shared UI
kit is built (Roadmap 4.2).

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

**Open** (suggestions)
- Outline: thick, in the same dark ink as the text outlines, so the whole UI looks inked like
  a cartoon. The other choice is a coloured outline.
- A soft white-to-pale-blue gradient and a soft drop shadow, so panels look puffy, not flat.

## 3. Text

**Decided**
- **Fredoka One for all text.** Roblox has it in one weight only (checked in Studio
  2026-09-25), so titles stand out by size, colour and outline, not boldness.
- **White text with a dark outline**, for now.
- Every word is real Roblox text (TextLabel, TextButton, TextBox), never part of an image,
  and lives in `Strings`. This is what makes Roblox automatic translation work.
- Text must survive translations about 40% longer than English: it shrinks to a minimum size
  or its box grows. It never gets cut off.
- A sentence with a number or name in it is stored whole, with a placeholder
  ("You won {1} money"), never glued together from pieces.
- Player names are never translated (`AutoLocalize` off on those labels).

**Starting values**
- Sizes: title 40, heading 28, button 24, body 18, never below 16 px.
- Outline: about a tenth of the text size, at least 2 px. Ink `#1B2033`.

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

**Open**
- The order of the rarities (where mythic and unique sit) and what VIP means (GDD section 12).
- Button colours. The designer is still choosing; do not finalise them.
- A house accent colour for highlights and selected tabs (suggestion: blue, as in the
  reference).

## 5. Buttons

**Decided**
- Touch targets at least 44 px (as in `Config.UI.Spin.ButtonSizePx`).

**Open** (suggestions)
- Raised candy buttons: lighter on top, a darker lip underneath, and a squish down when
  pressed.
- Colours: see section 4.

## 6. Icons and images

**Decided**
- **Money is a stack of green cash.** Never coins.
- No words in any image. Transparent PNGs in `assets/ui/`, made from one shared style prompt
  so they match.
- Frames and buttons are built from Roblox shapes (UICorner, UIStroke, UIGradient), not
  images, so they stay sharp on every screen and recolour with one value. Images are for
  icons and effects only.

**Open**
- Glossy cartoon icons like the reference's balls and cue (suggestion), or flat.

## 7. Motion

**Decided**
- Every animation comes from one shared `UIAnim` module (pop in, slide, shine sweep, pulse,
  float, spinning rays, confetti, count-up), so all screens move alike. Looping effects stop
  when their screen closes.

**Open**
- How lively (suggestion: things pop and slide in, and only important things shine or bounce:
  Rematch, rewards, shop deals).
- Whether the VIP rainbow and the mythic shimmer move (suggestion: yes, both slow).
