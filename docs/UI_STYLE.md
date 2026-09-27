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
- **A faint pattern of soft 8 balls** over every panel (designer, 2026-09-27, after a
  reference; it was tiny flat pool balls): pale-blue shaded balls of a few sizes, each turned
  its own way with its number disc toward the top left, and a few small bubbles, scattered so
  the repeat does not show (an even grid of small blurred balls was tried and the designer
  preferred this). Faint: felt more than seen. Every panel gets it from the kit's
  card (`HudParts.card`), so new screens have it too.
- **Menus get a header band and a sheet** (designer, 2026-09-27, after their Ranked
  reference): a menu is a screen with a title (the roadmap, the host menu, and later the shop,
  inventory and settings). Its panel's top is a pale-blue band holding the title and the close
  button; everything else sits on a near-white sheet with big rounded top corners (the curved
  header) and a thin light-blue edge, inset a little from the panel's outline. The 8-ball
  pattern shows on both. Built with `HudParts.menuCard` and `HudParts.setSheetTop`; small
  panels and popups stay plain cards.
- **Popups never darken the screen** (designer, 2026-09-27, said for the dialogs and again for
  the rank screens): no dim behind a popup, a dialog, the end-of-match screen or NEW RANK!, because
  the dark layer shows where it stops at the screen's edges on different devices. The one
  exception is the Ranked roadmap's slight dim.

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
- Outline: about a tenth of the text size, at least 2 px; text under 20 px gets a 1 px outline,
  because Roblox strokes the inside edges of letters too and a thicker one closes the holes of
  o, a, e, 0 and 8 (designer, 2026-09-27: Fredoka One kept). Ink `#1B2033`.

**Decided exceptions** (2026-09-25)
- Ball numbers may be smaller than 16 px: they are part of the ball graphic.
- A long player name ends in "..." instead of shrinking or wrapping: names are data, not
  reading text, and are never translated.

- Fredoka One stays for all text (designer, 2026-09-27): small text blotting its letters was
  the outline, not the font, and the thin outline above fixed it.

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
- Reyes' rank badge uses the VIP rainbow (2026-09-26). If VIP items also look rainbow,
  decide whether the two should differ so a rank is never mistaken for a VIP item.
- The rarity order is decided (2026-09-27, GDD section 12): Common, Uncommon, Rare, Epic,
  Legendary, Mythic, Secret; Unique (pink) and Exclusive sit outside the ladder, and VIP is an
  Exclusive cue (it keeps the rainbow). Still open: **Secret's colour** (suggestion: near-black
  with a slow red-white glitch shimmer, unlike Mythic's pastel one) and how an Exclusive rank
  cue shows its group (suggestion: its tier's colour with a small crown mark).

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
  (bigger each tier, Veteran included; Reyes the biggest); pips on the ring's bottom edge like
  the reference's single star, following its curve: 1 to 5 stars from Bronze to Diamond, 1 to
  5 gems from Expert to Grandmaster (1 = division I). The middle pip is the biggest and each
  step outwards a little smaller; they never overlap; each has an ink outline and a soft glow,
  so it pops on any colour with nothing behind it (no tray). Stars are crisp and straight-edged,
  bevelled like a pyramid (each facet lit or shaded), never puffy. On a badge with pips the
  frame ends just under the middle one, so the pips are the badge's lower edge and nothing
  hangs below them; Unranked and Reyes keep the frame's point. Glare like the reference:
  polished metal with a bright band, white streaks on the lit bevels, a glint on the frame's
  lit corner and on each pip, and a big glossy reflection on the 8 ball. Diamond is cyan. Grandmaster is black and gold
  (a gold trim, crown and ring, black feathers with gold veins, gold gems). Reyes is a rainbow
  badge in the house rainbow (section 4's VIP colours: a rainbow frame, ring and crown, its
  crystals and blades red to purple), with no pips and no signature (2026-09-26). No banner
  and no words: the rank's name is game text beside the badge where needed.

## 7. Motion

**Decided**
- Every animation comes from one shared `UIAnim` module (pop in, slide, shine sweep, pulse,
  float, spinning rays, confetti, count-up), so all screens move alike. Looping effects stop
  when their screen closes.

- **How lively** (2026-09-25): panels and popups pop in with a small overshoot and pop out
  quickly. Only important things shine, bounce or breathe: your turn (the YOUR TURN popup
  pops in and its cue bounces), the win card (the trophy over turning rays), Start once it can be
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
- **Screens:** the match top bar, the turn popup, the foul popup (no panel, 3 s), the hints,
  the leave and surrender dialog, the coin and result cards, the host menu, the floor box, the
  table sign (only near its table), the power bar, the spin panel and the pocket targets.
- **Calling the 8** (designer, 2026-09-27): choosing, every pocket gets a 44 px ring with its
  name. Once called, while you shoot, the chosen pocket keeps a ring sized to sit inside its
  hole on screen (it grows and shrinks with the zoom), with no caption, so nothing covers
  the pocket's jaws.
- **Phones** (2026-09-26): the top bar is compact and sits in Roblox's own top row beside its
  menu, chat and voice buttons (it asks Roblox for that room, ScreenInsets.TopbarSafeInsets),
  so the table keeps the screen. The host menu stays one column on the right, short enough to
  fit, beside the jump button (or above it when that lets it be bigger).
- **The top bar** (designer, 2026-09-26): one row on every screen. Left to right: our team
  (portraits, then the balls), the shot clock, their team, and Leave (the red door, touch area
  still 44 px) at the right end. Only as tall as the balls plus a sliver of white (37 px on a
  computer, 30 on a phone). It is laid out once at those sizes and scaled down to fit the room
  beside Roblox's buttons (a UIScale), which is how it fits every resolution. Solo: the one
  team with its 15 balls, then Leave. The clock is big and centred between the teams, and only
  shows while a clock runs. No names under the portraits (a rank badge goes there later).
- **No status card** (designer, 2026-09-26): whose turn it is shows as a small popup under the
  bar for 2 s when a turn starts ("YOUR TURN" in green with the cue, "OPPONENT'S TURN",
  "ALLY'S TURN"), like the foul popup but smaller. The same popup says "YOU ARE SOLIDS" or
  "YOU ARE STRIPES" in gold, with a solid or striped ball, for 3.5 s when the break's first
  legal ball decides the groups (2026-09-27); during the turn, the shooter's green
  clock ring round the portrait shows it, draining with the clock. With ball in hand a blue
  "MOVE 12s" pill with the hand under the big clock counts the time left to move the cue
  ball; the big clock holds at the full shot clock, and the ring stays full, until it ends. The
  break has no pill: moving and shooting share the big clock. NICE SHOT! is gold Fredoka
  in the world just over the pocket, tilted, over turning gold rays; it pops, floats up and
  fades in 1.5 s. The ball-in-hand hint is one thin line,
  only as wide as its words.
- **The power bar** (designer, 2026-09-26): on a phone high on the right under the top bar; on
  a computer or tablet bigger and centred on the right edge.
- **The zoom guide** (designer, 2026-09-26): over the spin button while it is your turn, a
  small icon and "Zoom In/Out" with nothing behind them, lightly greyed so it reads as a
  control guide rather than a button, but clear (2026-09-27): a deliberate exception to the
  kit's cards. A mouse whose big ridged wheel is circled in red, with arrows up and down, on a
  computer; a pinching hand on touch. Hidden on a gamepad, where the controller guide covers
  zoom. Once the player zooms it stays hidden for the session (2026-09-27).
- **The controller guide** (designer, 2026-09-27; `PadGuide`): while it is your turn on a
  gamepad, a faint strip at the bottom left above the money HUD, in the zoom guide's style:
  left stick with left/right chevrons "Turn", the D-pad "Fine aim", right stick with up/down
  chevrons "Zoom", L1 "Spin & angle", R2 and X "Shoot"; and a Circle just right of Leave. The
  button pictures are Roblox's own, so they match the controller (PlayStation or Xbox); the
  chevrons are the kit's white ones.
- **An icon-only button** (Leave's red door) shows its icon at 95% of the button (designer,
  2026-09-27).
- **The host menu:** a small red door beside a wide Start; the money each difficulty pays
  (cash icon and 1x, 1.5x, 2x) under its tile; one short line describing the chosen level.
- **Ranks and money** (2026-09-27, branch `ranks-money`; sizes in `Config.UI.Progress`):
  - *The rank badge* (`RankBadge`): every screen's badge, with the shine from section 7 on one
    shared clock; the HUD's badge pops up under the mouse and squishes when pressed.
  - *The rank HUD*, top left beside Roblox's buttons (reference 02): the badge bigger than and
    over the pill's left end, the rank name and an XP bar "520 / 1,000 XP" that counts when it
    changes. Hidden in a match and under the popups. Pressing it opens the roadmap.
  - *The money HUD*, bottom left, always on: the cash stack over a pill with "$1,250" (from 10
    million "$12.5M"). It takes no input, so the thumbstick under it still works.
  - *Nameplates*: the small badge, then the username, over every head, drawn over the world;
    the players of your match are hidden while you play.
  - *The flying cash*: "+$10" with the single bundle pops out of the pocket, hangs, and arcs
    into the money HUD, which bumps, sparkles and counts up; nice shots are gold ("+$15").
  - *The end-of-match screen*: the same for every player (reference 05, light): cards with VS,
    the winner crowned over turning rays with WINNER, then your XP bar and the money list
    counting up, the total flying into the HUD. Solo: one card and the money.
  - *NEW RANK!*: the big badge over turning rays, confetti, the name and the reward chip; a new
    tier bursts from the old badge with "PLATINUM!"; a lost division is a small quiet card.
  - *The roadmap* (redesigned after reference 03, designer 2026-09-27): the ten tiers side by
    side (about five at once, < and > arrows plus swipe), each with its badge, name and five
    division dots; your tier bigger over turning rays with "Current Rank", the next with "Next
    Rank", later ones greyed. Below: your rank card (badge, XP bar, an arrow to the next
    division and its money) and "Rewards for <tier>" (money, a Case, the [TIER] chat tag, the
    tier's Cue; Case and Cue marked Soon); tapping a tier shows its rewards. No line of rules
    under the cards (designer, 2026-09-27). The < and > arrows carry one white chevron image
    each, drawn as a single stroke. Its slight dim is the only dim in the game.
  - *Chat tags*: "[PLATINUM]" in the tier's colour before your name in chat (Reyes in the
    rainbow, letter by letter); none for Unranked.
  - *The rank HUD bounces as a whole* (designer, 2026-09-27): badge and pill grow together
    under the mouse and squish and bounce when pressed. Badges sparkle, with only a faint light
    sweep now and then. On a computer the HUD is 1.5 times its phone size, an easier target
    (designer, 2026-09-27).
  - *The hover sound* (designer, 2026-09-27): short and soft, Roblox's own "RBLX UI Hover 01"
    (0.2 s), on a badge or a roadmap tier.
