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
- **The lively frame** (designer, 2026-10-06; the Shop first, every menu as it is rebuilt with
  the `lively-gui` skill, `Config.UI.Menu.LivelyMenus`): the panel unrolls; the header's
  8-balls scroll slowly up-left; the white sheet has the original tiny pool-ball dots, still;
  the tabs stand outside the right edge; an 8-ball flair is pinned on the left edge; a compact
  header (the title fills it, the X smaller than the money pill, a gold + on the money pill).
- **Blur, never darken** (designer, 2026-10-06, after a reference; replaces the dims of
  2026-09-27/28): behind every menu, the Ranked roadmap, the lucky block reel, the
  end-of-match screen and NEW RANK!, the 3D world blurs and the GUI stays sharp. A very quick
  fade in and out (0.2 s), like a camera pulling focus. No dark layer anywhere (it showed
  where it stopped at a screen's edges); the clear layers stay only to take taps. Built with
  `ScreenBlur.set(key, on)`, numbers in `Config.UI.Blur`. Small popups and dialogs inside a
  menu add nothing. The tutorial's spotlight keeps its own dim, as that is its whole point.
  **NEW RANK! is the one exception** (designer, 2026-10-06): it also darkens the screen behind
  it (it was made to stack on the match results; since 2026-10-07 it waits until they close) (50% black, `Config.UI.Progress.NewRank`'s
  `BackdropTransparency`) on top of the blur.

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
- **Solid ink holes** (designer, 2026-10-06): every outlined text with a 2 px outline or
  more (from 20 px) has its letters' holes (o, a, e, p, 0, 8...) filled with ink, the same
  way on every screen and in any font, by `HoleFill` (Main watches all of PlayerGui, so new
  screens get it with no code). Smaller text keeps its holes: filling them made it blobby.
- **Thick ink lip under letters** (designer, 2026-10-06): every outlined text, small text
  too, has an ink copy with its outline a little lower: 0.45 of the outline's thickness, at
  least 1.5 px (`Config.UI.Kit.HoleFill.Drop`). Both are sized from the outline, never from
  TextSize, which on a scaled text is only its largest size.

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
| VIP | gold with a crown mark (placeholder, 2026-10-03; was rainbow) | `#FFC400` `#FFEC8C` `#FFAA00` |
| Secret | near-black with a slow red-white glitch shimmer (designer, 2026-10-03) | `#1E1820`, glitch `#FF283C` `#FFFFFF` |
| Ranked | the rank cues' rarity (2026-10-08): a medal gold for its Index row; each card wears its tier's colours (section 17) | `#FFB81C` |

- **Mythic and VIP must never look alike.** Mythic is pale and holographic: a slow pastel
  shimmer over a deep-space background with small twinkling stars. VIP is gold for now
  (designer, 2026-10-03: VIP no longer uses the rainbow; its new look comes later). The
  **rainbow is for deals and multipliers** (section 13).

**Decided for now** (2026-09-25; may change)
- **Traffic button colours:** green for Start, Play and Yes; red for Leave and Surrender (in a
  dialog, the button that leaves or surrenders is red and the one that keeps playing blue);
  blue for choices and whatever is selected; yellow for special things (SOON, the coin).
- **The house accent is blue.** A gamepad-selected or hovered button gets a thick gold outline.

**Open**
- Reyes' rank badge uses the VIP rainbow (2026-09-26). If VIP items also look rainbow,
  decide whether the two should differ so a rank is never mistaken for a VIP item.
- The rarity order is decided (2026-09-27, GDD section 12): Common, Uncommon, Rare, Epic,
  Legendary, Mythic, Secret; Unique (pink), Ranked (the ten rank cues, 2026-10-08) and
  Exclusive (VIP, Starter) sit outside the ladder. Secret's card and the Ranked cards' look
  were decided with the new cue card (section 17, 2026-10-08).

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

**The method is the `lively-gui` skill** (`.claude/skills/lively-gui/`, from the lively Shop,
2026-10-06): every new or rebuilt screen follows it, with its motion tokens
(`Config.UI.Motion`), its reveal player (`Stage`) and its idle library (`UIAnim`). The rules
below are the summary; the skill has the numbers and code.

**Decided**
- **Every screen enters as a sequence** (designer, 2026-10-06): a full menu's panel unrolls from
  a thin bar, then its pieces pop in one by one a few hundredths apart (60% to 110% to 100%,
  with a fade); popups slam in from big; backgrounds and lines grow from their centre; the hero
  piece and big cards arrive with a small firework burst; small HUD pieces just pop. The whole
  open takes about 1 to 2 s (the Shop's 0.91 s); a tab switch replays only the new page (0.5 s); a
  close fades everything while the panel folds (0.15 s). Buttons work the moment they show.
- **Something always moves, calmly.** Every screen keeps at least one idle loop (glows pulse,
  rays turn, the hero breathes, a shine sweeps, 8-balls float, the header's pattern scrolls),
  each starting as its piece lands, at a random phase, only while on screen, fewer with Lower
  effects and none but soft glows with Reduce Motion.
- **Smooth, never choppy** (gate 1, measured 2026-10-06; replaces "an icon never moves up and
  down", 2026-10-03): GUI positions snap to whole pixels, so nothing moves slowly by Position,
  Size or UIScale. Slow motion moves the picture inside a still label (fractional
  `ImageRectOffset` / `ImageRectSize`: scroll, float, breathe) or turns it (Rotation); fast moves
  (pops, slams, drops, confetti) may move the label. A flipbook plays at 30 fps; a slower one
  looks choppy, so a slow moving part is a still picture that pulses instead (the Firework
  Cue's ribbons dim and glow).
- **The small part moves, not the hero**: decorations rock, pulse and sparkle; the hero
  breathes at most (the crowned block, 1.5% over 2.3 s).
- **Shine only what should draw the eye** (designer, 2026-10-06): on the Shop only the Robux
  buttons shine.
- **No CanvasGroup** for reveals or fades (black or blank on phones, blurry at low graphics, it
  clips the overshoot): groups fade by code.
- **Hover sway** (designer, 2026-09-28): anything pressable (candy buttons, menu tiles, cue
  cards, the column's icons, roadmap stops) rocks gently side to side while the mouse is over
  it or a gamepad rests on it, a small dance on top of the hover grow: about 3 degrees (a wide
  button less, its ends move at most 5 px), one rock every 1.4 s, easing in and out. The rank
  HUD grows as a whole but only its badge shakes, quicker (7 degrees, 0.6 s). Touch has no
  hover, so a tap never starts it. `UIAnim.sway`, numbers in `Config.UI.Kit.Motion.Sway`.
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
  a computer or tablet bigger and centred on the right edge. The fill runs green to yellow to
  red as you pull, then from 75% fades into the house rainbow, all rainbow at 100%, its bands
  drifting down the bar (designer, 2026-09-30).
- **The zoom guide** (designer, 2026-09-26): over the spin button while it is your turn, a
  small icon and "Zoom In/Out" with nothing behind them, lightly greyed so it reads as a
  control guide rather than a button, but clear (2026-09-27): a deliberate exception to the
  kit's cards. A mouse whose big ridged wheel is circled in red, with arrows up and down, on a
  computer; a pinching hand on touch. Hidden on a gamepad, where the controller guide covers
  zoom. Once the player zooms it stays hidden for the session (2026-09-27).
- **The controller guide** (designer, 2026-09-27; `PadGuide`): while it is your turn on a
  gamepad, a faint strip at the bottom left above the money HUD, in the zoom guide's style:
  left stick with left/right chevrons "Turn", the D-pad "Fine aim", right stick with up/down
  chevrons "Zoom", L1 "Spin & angle", X "Shoot"; and a Circle just right of Leave. The
  button pictures are Roblox's own, so they match the controller (PlayStation or Xbox); the
  chevrons are the kit's white ones. While L1 holds the spin panel open the strip shows the
  spin controls instead: left stick "Spin", right stick with up/down chevrons "Angle", Y
  "Center spin" (designer, 2026-09-27).
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
    the players of your match are hidden while you play. A win streak (2026-09-28) adds a
    line above them: the fire emoji and the count in gold, from 1, bouncing as it rises.
  - *The flying cash*: "+$10" with the single bundle pops out of the pocket, hangs, and arcs
    into the money HUD, which bumps, sparkles and counts up; nice shots are gold ("+$15").
  - *The end-of-match screen*: the same for every player (reference 05, light): cards with VS,
    the winner crowned over turning rays with WINNER, then your XP bar and the money list
    counting up, the total flying into the HUD. Solo: one card and the money.
  - *NEW RANK!*: the big badge over turning rays, confetti, the name and the reward chip; a new
    tier bursts from the old badge with "PLATINUM!". There is no rank-down card: XP is never
    lost (2026-09-28). The reward chips under the name (2026-09-28; blocks 2026-10-04): money,
    each lucky block drawn as its 3D icon (`BlockIcon`), the tier's cue and the [TIER] tag,
    which fly to where they live when it closes (a block to the hotbar, a cue to the column).
  - *The roadmap* (redesigned after reference 03, designer 2026-09-27): the ten tiers side by
    side (about five at once, < and > arrows plus swipe), each with its badge, name and five
    division dots; your tier bigger over turning rays with "Current Rank", the next with "Next
    Rank", later ones greyed. Below: your rank card (badge, XP bar, an arrow to the next
    division and its money) and "Rewards for <tier>" (money, the real lucky blocks as their 3D
    icons, the [TIER] chat tag, the tier's cue on its thumbnail; 2026-09-28; blocks
    2026-10-04); tapping a tier shows its
    rewards. No line of rules
    under the cards (designer, 2026-09-27). The < and > arrows carry one white chevron image
    each, drawn as a single stroke. Its slight dim is shared since 2026-09-28 by the full
    menus; the block opening has its own dark one (section 14); NEW RANK! has its own
    (section 2).
  - *Chat tags*: "[PLATINUM]" in the tier's colour before your name in chat (Reyes in the
    rainbow, letter by letter); none for Unranked. A VIP's rainbow "[VIP]" comes first
    (section 10).
  - *The rank HUD bounces as a whole* (designer, 2026-09-27): badge and pill grow together
    under the mouse and squish and bounce when pressed. Badges sparkle, with only a faint light
    sweep now and then. On a computer the HUD is 1.5 times its phone size, an easier target
    (designer, 2026-09-27).
  - *The hover sound* (designer, 2026-09-27): short and soft, Roblox's own "RBLX UI Hover 01"
    (0.2 s), on a badge or a roadmap tier.

## 9. The global queue and rematch (2026-09-28)

- **Even spacing** (designer, 2026-09-28): rows of buttons (the rematch row) share one gap
  and stay centred.
- **The matchmaking bar** (designer, 2026-10-07, look A of three mocks; `MatchBar`,
  `Config.UI.MatchBar`): replaces the host card. One slim white pill with the ink outline,
  bottom centre just above the lucky block hotbar (0.8x on a phone): the old pad card's
  Classic icon (designer, 2026-10-07), a pale-blue "1/2" chip with the people icon, then the line in ink ("Waiting
  for opponent..." with the lit dots, "Starting in 3", "Searching... 0:07", "Match found!").
  The host's **Play Global** is a big green candy with a glossy globe icon, joined to the
  pill's right end and a little taller than it, "Don't want to wait?" in outlined white just
  above it; it pops in as the bar widens round its centre (0.2 s), then breathes gently
  (`UIAnim.pulse` at 1.015 over 1.6 s, gentler than the house 1.03 over 0.9 s, by the
  designer's note; none with Reduce Motion). While searching a small red X candy takes its
  place. The whole bar pops in and out (the house entrance for a HUD piece). A small round
  red X candy (`DismissPx` 24) sits on Play Global's top-right corner and dismisses it
  (designer, 2026-10-07); a gamepad reaches it right of Play Global.
- **The spawn pill** (designer, 2026-10-07): the same "Don't want to wait?" and Play Global
  with its X, alone in the bar's spot with no waiting pill, for a player alone in a public
  server. Searching from it shows the pill with the Classic icon and "Searching... 0:03" (no
  count chip) and the red X.
- **The teleport screen**: a dark full screen (no card: it stands in for Roblox's loading
  screen) with MATCH FOUND in bright green and one breathing line ("Joining the
  arena...", or "Back to the lobby..."). It stays through the load and fades out once the
  arena's table is there.
- **The status card**: one small white card at the top middle for one line: an arena's
  "Waiting for players 1/2", a teammate's search time, or for 4 s why a teleport did not happen.
- **The rematch row**: under both columns of the result screen, in Continue's place; a small
  status line on the left ("Opponent left", "Searching 0:07") and the seconds left in gold on
  the right; the buttons share the width: green Rematch ("Waiting 1/2" once pressed), blue
  Play another (or red Cancel while it searches), red Lobby; on a lobby table green Rematch
  and red Leave. The series score, your side first, in gold where VS stood. During a
  rematch a small gold "Series 1-0" pill hangs under the clock (where the blue move pill goes
  with ball in hand, which wins that spot).

## 10. The economy: the column, the menus and the reel (2026-09-28, overnight)

Built on the branch `economy` (docs/prompts/ECONOMY_UI_PROMPT.md). Sizes in
`Config.UI.Menu`, `Config.UI.Shop`, `Config.UI.Inventory`, `Config.UI.Rewards` and
`Config.UI.Reel`. Lines marked *(assumption)* are overnight calls, logged in DECISIONS.

**Cases are gone (designer, 2026-10-04).** Lucky blocks replaced them entirely: the reel lives
with the lucky blocks now (section 14; `BlockReel` with its Dark look, `ReelFx`, tuned in
`Config.UI.Reel`, words in `Strings.Reel`), the case opening screens, Fast Open's grid and
the chest art are gone, and no block is ever in the Inventory (the hotbar and its bag hold
them). The reward popups, reminder toast and come-back screen are gone too: every reward is
claimed in the Rewards menu. The lines below that still say "case" describe what was built
then; the reel's rules hold for the blocks.

- **The left column** (designer; reference 06): top to bottom Shop, Inventory, Rewards,
  Trade, each just its big glossy icon with no box behind it (designer, 2026-09-28: the blue
  candy tile went so the icons could be bigger) and the word in white with an ink outline
  across the icon's lower edge. Hover grows it, a press squishes it. 78 px slots on a
  computer, 52 px on a phone (under the rank HUD there; centred on the left edge on a big
  screen), always above the money HUD. Each tile draws over the one below, so a word is never
  under the next tile's red dot.
  **CUES** (concept 2b, approved 2026-10-08): the Classic Cue where every icon sits, a soft
  gold glow breathing behind it and three twinkles in the box's empty corners. A hover (or a
  gamepad resting on it) strikes a cue ball with it: the ball pops in by the tip, the cue draws
  back and hits it with a white spark, the ball flies off up the cue's line and fades, the cue
  slides home (0.95 s). A press strikes harder and quicker (0.7 s), from the touch so it shows
  before the menu opens; the D-pad route too. Still with Reduce Motion (`CuesStrike`,
  `Config.UI.Menu.Column.Strike`). The same still icon is the Cues menu's header icon and the
  My Cues tile's.
  A red dot sits top right on Rewards while something can be claimed, and on CUES (the
  Inventory, renamed 2026-10-08) with how many owned cues are NEW ("9+" past nine); the Shop
  carries a gold timer pill while an offer window is open. Hidden in a match. On a gamepad the tiles are never selected (a
  selected button would take the stick from walking): the D-pad opens them in the hub (up
  Shop, right Inventory, down Rewards, left Trade) and each tile shows its D-pad glyph
  *(assumption)*.
- **One thing at a time** (designer, 2026-10-06): while any full menu is open (Shop,
  Inventory, Rewards, Trade, Settings, Free Reward, Abilities, the roadmap, the bag) every
  other screen of ours is off: the rank bar and settings, the left column, the money, the
  right corners, the hotbar, the player list, the thumbstick. Closing the menu brings them
  back. Only popups that must still reach the player stay (`HudFocus`,
  `Config.UI.Menu.Focus.Keep`).
- **A full menu** (`MenuFrame`): the roadmap's layout. On a phone the panel takes the whole
  screen with its title in Roblox's top-bar row (the tabs share that row when they fit); on
  a computer a panel up to 920 x 600 is centred under the bar. **A lively frame (the Shop,
  designer 2026-10-06) covers far less:** never in Roblox's top-bar row, at most 66% of the
  screen's width (`Config.UI.Menu.Lively.MaxWidthShare`), only as tall as its hero card, the
  jump buttons outside its right edge, the 8-ball pinned on its left edge; the page scrolls on
  below the hero. Title with its icon, tabs as
  candy buttons, a money pill in the Shop's and Cues's header, the red X. Cards are white
  with a pale blue edge (the roadmap's reward tiles); a cue card is the cue card of section 17
  (2026-10-08). The server's answers show as a short line at the bottom of the panel. Confirm
  dialogs are the kit's dialog card with no dim.
- **The Cues menu** (the Inventory renamed, concept 2 approved 2026-10-08; brief
  `docs/prompts/CUES_LIVELY_PROMPT.md`): the lively frame with no tab row. Outside the panel's
  right edge stand four tiles of one size, evenly spaced: My Cues and Index (two tiles since
  2026-10-08, it was one switch; the view you are in is blue with its icon rocking, as the
  Shop's jump buttons; a red dot with the NEW count on My Cues, "!" on the Index while a row
  can be claimed), then Sort and Sell dupes ("Sell all" until 2026-10-08), each with a pill
  hanging under it (the order's name in blue; the money Sell dupes would pay in gold, greyed
  at $0). The clear space down the rail is the same each time, counted from a hanging pill's
  bottom; a short panel shrinks the tiles. In the Index Sort and Sell dupes step aside. The title and its icon say which view shows; LB / RB
  flip the views and B goes back one step (the big card, then the Index to My Cues, then the
  menu). **My Cues**: 5 cards a row, the panel as tall as two whole rows with the third
  peeking; a short screen shrinks the cards. Every open starts on Rarest first; Sort turns the
  order (Rarest first, Common first, Most copies, Name A-Z, then round), keeps the chosen card
  and scrolls the grid to its top;
  by rarity, Ranked and Exclusive sit between Epic and Legendary, the rank cues highest tier
  first. A pressed card slams in its **big card** over the page, calmly (no gold burst, a
  small nudge: it opens often), on the lively sheet's tiny pool-ball dots: the same card, bare
  (no pills), and beside it the name, the rarity, "4.2% chance · 1,284 exist", "You own 3" (a
  numbered copy's "Copy #412"), "Can't be sold" with the padlock, Equip and Sell duplicates
  (its count chooser: - 3 +, Max, "Sell 3 for $360"). The buttons sit a little in from their
  column's sides, so their outline and their hover growth are never cut. Money from a sale
  flies into the header's pill, which counts up as it lands (it shows the money HUD's number).
- **The Index** (designer, 2026-09-28; concept 2): 4 cells a row; a cue never found is its
  whole card, locked (section 17). The chosen cue shows in a panel on the right, on the lively
  sheet's tiny pool-ball dots: its card, bare and standing still (designer, 2026-10-08: it
  swayed), locked until found, then the name, the rarity, "In your collection" or "Not found
  yet", "4.2% chance · 1,284 exist", and for a cue
  not found yet "Find it for +$250" in green with the cash. A tap chooses a card; a controller
  chooses the card it lands on. On a phone the panel is narrower.
- **Finder's money**: a block's prize that is new to the Index reads "NEW! +$250" on the
  "YOU GOT" card, and the money reaches the HUD with the card, never before (the reel is never
  given away). Any other find (a rank-up cue, the
  VIP Cue, a Limited cue, a gift) is a banner line "New in your Index: VIP Cue! +$500" in the
  cue's rarity colour.
- **The dim** *(assumption)*: a full menu is the same kind of screen as the roadmap, so it
  reuses its slight dim; a tap on the dim closes it; one menu at a time; all close when a
  match starts. The block opening's backdrop is the dark see-through layer of section 14.
- **The chest art is gone** (2026-10-04): the five case chests (reference 07, the CHESTS job in
  `tools/gen_ui_art.py`) and their kit icons were deleted with the cases; a lucky block is
  drawn as its own 3D model everywhere (section 14). Rarity colours stay UI_STYLE 4's.
- **The reel** (designer: Rivals / CS style; now `BlockReel`, section 14): a strip of cue
  cards drawn from the block's true odds slides under a gold centre marker and eases to a
  stop on the prize, ticking as cards pass; the timings are `Config.UI.Reel`. Then the prize
  pops with its rarity sting: the pull cutscene from Rare, then the "YOU GOT" card over the
  dimmed world. A Rare or better pull fades everything to black from a second before the reel stops;
  Rare then swells a soft blue glow from the middle to a full blue screen, flashes white on
  the riser's peak and fades the white off the card (about 1.6 s, never skipped). Epic is a
  purple vortex: a bass hit and a longer riser with the fade, a ring pulse in the black, purple
  rays spinning up while sparkles spiral in from the corners, a collapse into a bright point
  and a white burst on the riser's peak (about 2 s from the fade, never skipped). Legendary is
  a film behind letterbox bars (side to front, low up at a gold star, from the sky as its beam
  hits on the track's impact, a heavy shake and sparks), a fade to black with the rise starting under it,
  a gold starlight warp, a white flash and the card (about 9 s, skippable once seen). Tap (or A) skips, in two stages (section 14). Fast Open's grid, the first
  win's reel inside the result screen and the "Still opening" wait are gone: a block is
  opened in the world, and the server has already answered when the reel starts.
- **Prices**: money with the cash bundle; Robux with Roblox's own Robux glyph inside the text
  *(assumption)*; a product whose id is still 0 keeps its price and adds a small "Soon" tag.
  A real sale shows the struck old price, the new one and its countdown; "Need $X more" on a
  block the player cannot afford jumps to Money.
- **Chat and names** (designer, 2026-09-28): in chat a VIP's line reads "[VIP] [GOLD] Name":
  [VIP] first in the house rainbow letter by letter, then the rank tag, and the name in
  Roblox's own colour. Over the head a VIP's name is the house rainbow, its colours drifting
  slowly along it (one loop in 8 s, calm, never a flash); the badge stays before it. the top banner (Money
  Party, a Mythic or Secret unboxing, Reyes) is one small kit card at the top middle under
  Roblox's bar, with the line in the rarity's colour (Reyes in the rainbow); it waits during a
  match, and an unboxing or Reyes also posts a chat line.

## 11. Abilities: the bar, the cutscene, the spin screen and auras (2026-09-28, overnight)

Built on branch `ultimates` (docs/prompts/ULTIMATES_PROMPT.md). Sizes and timings in
`Config.UI.Ults`; lines marked *(assumption)* are overnight calls, logged in DECISIONS.

**Players see "Ability" / "Abilities"** (ABILITY in the all-caps spots) on every screen, never
"Ult" or "Ultimate" (the designer, 2026-09-28: "Ult doesn't look right"). In code, Config and
these notes they are still called ults (UltHud, UltScreen, `Strings.Ults`); the words come from
`Strings.Ults` and friends, so the change is text only. The quoted labels below are the ones
players read.

- **The ult bar** (reference 08, placed differently): bottom centre and compact, about 300 x
  46 px on a computer and 220 x 36 on a phone, above the bottom edge and clear of the money
  HUD, the controller guide, the spin button, the power bar and Roblox's buttons; never over
  the middle of the table. It shows only on your own turn and fades to 25% while the cue is
  pulled back. The 8-ball badge with its blue splash sits on the left end, "ABILITY" in
  outlined white above, a thick ink-outlined pill with a blue fill and a moving shine, the %
  centred. Each gain flashes the fill's edge, bounces the badge and floats a "+34" (gold beside
  NICE SHOT! for a nice shot). Gains from the opponent's turn animate when your turn starts.
  **Ready:** the fill turns gold ("READY! 100%"), the badge's splash turns to flame, sparkles
  and a soft pulsing glow, a shake every ~2 s, and a white pill above: PRESS [G] TO ACTIVATE
  (keyboard), TAP TO ACTIVATE (touch: the whole bar is the button) or PRESS [X/Square] TO
  ACTIVATE (gamepad, Roblox's own glyph), following the last input type. **Armed:** the bar
  becomes a pill in the ult's rarity colour, "MAGNET: NEXT SHOT"; the opponent sees a small
  "Opponent's ability: MAGNET" pill. The top bar shows a small ult icon beside each opponent that
  lights up when their ult is ready.
- **The cutscene** (reference 10, Jujutsu Shenanigans' domain expansion): about 0.8 s, for
  everyone in the match. A tilted manga panel (about -8 degrees, 40% of the screen's height,
  a thick white border with an ink outline) slams in across the middle; inside, the kit's
  white with a thick line in the ability's rarity colour round it, a soft glow of that colour
  and speed lines in it behind the activating player's avatar (upper body, big, in a
  ViewportFrame, its bottom fading out) with a slow push-in (the designer, 2026-09-28: no dark
  swirl); "ABILITY" top-left and the ult's name
  bottom-right in Fredoka One with thick outlines. It shrinks to a thin line and snaps away.
  No dim.
- **The spin screen** (reference 09, Untitled Boxing Game): full screen over the real world
  where the player stands (every player and name plate hidden meanwhile; the designer,
  2026-09-28); the avatar big in the middle in its idle with a rarity aura; top centre "CURRENT
  ABILITY:", the name huge in its rarity colour with an ink outline, the description under it;
  three slot cards on the left (name, rarity strip, EQUIPPED or SELECT, a lock toggle; a slot
  not owned shows NONE and a green PURCHASE with its R$ price); collapsible rarity bars with
  their odds on the right, a "Lucky odds" switch; the code box on its own, centred between the
  slot cards and SPIN (under the odds when there is no room there, and in the Odds popup on a
  phone); LUCKY SPINS
  over the big gold SPIN (FREE SPIN while the daily one is unused) with SPINS LEFT under it;
  Pity N / 100, the money and the buy row (BUY 1/5/10/50, an R$ / $ toggle, crossed-out
  original prices in red) bottom right; a red BACK TO MENU bottom left. On a phone the slots
  are a compact column, the odds open from an "Odds" button and the buy row from "Buy spins".
- **Auras** (JoJo style, rising flame wisps from a flipbook): Common small and grey,
  Uncommon green, Rare blue, Epic purple with sparks, Legendary gold with rays, Mythic
  red-black with crackling arcs *(assumption: the brief's colours for Mythic's aura, not its
  pastel card shimmer)*. They grow with rarity.

## 12. Abilities: icons, the effects' look and screen effects (2026-09-29)

Built on branch `abilities` (docs/prompts/ABILITIES_PROMPT.md 5.1, 5.4). Numbers in
`Config.UI.AbilityFx`, `Config.UI.<Id>Fx` and `Config.UI.ScreenFx`.

- **Icons:** 3D, rendered in Blender from one rig (`tools/blender/abilities/icons.py`): one
  camera and light, framed by each object's on-screen extent so all 13 fill the frame alike,
  glows clamped inside it, an ink outline and a rim light in the rarity colour, 512 px on a
  transparent background. Ids in `Config.Ults.Assets.Icons`. They replace every placeholder:
  the cutscene (the icon stamps in beside the avatar, 1.3x to 1x with a rarity-colour glow
  burst), the slot cards, CURRENT ABILITY, the odds rows, the armed and opponent pills, the top
  bar's opponent badge and the Legendary and Mythic banners.
- **The effects' look** (one `src/client/<Id>Fx.luau` each, started by `AbilityFx`):
  - **Layered, never one trick:** a Blender mesh, Blender-rendered images and flipbooks,
    particles, beams and trails, a light burst (and a Highlight where it reads), the camera
    (a small shake, an FOV punch or a hit-stop for the big ones) and sound.
  - **Three beats:** armed (on the cue ball while aiming), during the shot, the payoff.
  - **Driven by the replay's events**, so both players see the same thing at the same moment;
    the server never builds any of it. The looks follow the replay's time scale (`/slowmo`),
    and `/hold` stops them.
  - **Readable:** nothing hides the ball being aimed at or the aim line while aiming, and the
    payoff never hides the result.
  - **The opponent's balls** get the same effect, slightly dimmer or thinner (thinner bolts,
    fainter sparks), so the weaker half-strength effect reads as weaker.
  - **Colours on the cloth:** Neon lifts colours unevenly and bright additive colours over
    the green cloth turn yellow, so the pieces that must read as one colour are flat
    (Neon only where a glow is wanted), and the colours were picked in Studio, not in Blender.
  - **Budget** (phones): about 10k triangles of effect meshes on screen at once per ability,
    textures 1024 px or less, few long-lived particles; everything goes when the shot ends
    (no leftover parts, connections or sounds).
- **The reach preview:** while an area ability is armed and its shooter aims, a soft ring on
  the cloth at the predicted first contact at the full reach, a dashed inner ring at the
  opponent's reach, and a small red outline on each opponent's ball inside; Magnet shows each
  pocket's capture zone instead. Only an indicator of reach, never of the outcome.
- **The pick view** (`UltPick`: Heat Seeker's ball, Portals' two spots): the camera goes
  top-down; a title pill at the top in the rarity colour ("TAP ONE OF YOUR BALLS", "PLACE
  PORTAL A", "PLACE PORTAL B"), a green CONFIRM on the right and a blue RESET for Portals. The
  balls that can be picked pulse; a spot the server would refuse turns red and greys CONFIRM.
  Touch and mouse tap or drag; a gamepad moves a cursor with the stick (A picks or places, Y
  switches portal, L1 resets, X confirms).
- **Screen effects** (`ScreenFx`: Rewind's VHS screen, Time Stop's grey and lens edge, Black
  Flash's pale red frame, the Tiger's fur frame): a colour grade, a full-screen flash, an image
  overlay, a shake and an FOV punch. Only the players at that table and those watching inside
  its fence see them. Full-screen layers reach the very edge of a phone's screen
  (`ScreenInsets.None`), never a box inside the safe area; the ScreenGui never takes input and
  sits over the match HUD but under the cutscene and the menus.
- **Moments in the HUD:** Time Stop's frozen aim shows the pill "TIME STOPPED · STRIKE THE CUE
  BALL AGAIN" in place of the clock and the ability pill; Rewind's redo shows a pink "SECOND
  CHANCE: 10s" pill with the shot's full path drawn.

## 13. Big, clear and never still (designer, 2026-10-03, GUI lane brief)

Applies to every screen, new or restyled (`docs/prompts/GUI_PROMPT.md`; numbers in
`Config.UI.Kit.Motion`, `Kit.Big`, `Kit.Numbers`).

**Decided**
- **Never still.** Something on every screen always moves, sparkles or breathes: the 8-ball
  pattern on menus and popups stays still (its slow drift looked choppy and was removed,
  designer 2026-10-03); big words
  rattle now and then (`UIAnim.shake`); special things sparkle (`UIAnim.sparkle`); bars carry
  moving stripes (`UIAnim.stripes`). Loops run only while on screen and calm down with Lower
  effects (`Quality`).
- **Smooth, never choppy** (designer, 2026-10-03; the technique since 2026-10-06 is in
  section 7 and the `lively-gui` skill). A label never moves slowly by Position: a GUI move
  snaps to whole pixels and looks like a 2 fps sprite. Slow motion moves the picture inside
  its label or turns it (`UIAnim.bob`, `Kit.Motion.Bob` for idle icons), and every shake is
  slow enough that no frame jumps far (`Kit.Motion.Shake`). Glows pulse smoothly, never blink.
- **Hovering an icon** (the left column, the corner icons) keeps the small hover sway and adds
  soft sun rays fading in behind it, turning slowly, like the Legendary ability's rays
  (`UIAnim.sunRays`, `Kit.Motion.SunRays`). No hard shake on hover (designer, 2026-10-03).
- **No lobby music** (designer, 2026-10-03: dropped). Settings has no Music switch.
- **Bigger, cooler presses, opens and closes.** Every candy button bursts a glow of its own
  colour from behind when pressed; a menu opening glows; a big word or card slams in
  (`UIAnim.slam`: from huge to its size, a glow and a jolt).
- **Big menus are centred on the screen.** On a computer the panel is centred on the whole
  screen, clear of Roblox's bar, and never nearer the bottom than `Frame.BottomGapPx` (its
  shadow included). Phones keep the full-screen panel, except the lively frame (2026-10-06):
  at most 66% of the width, never in the top bar row, as tall as its first card, on every
  device (`Config.UI.Menu.Lively.MaxWidthShare`).
- **One thing at a time** (designer, 2026-10-06): while a full menu is open, every other screen
  of ours is hidden (`HudFocus`); it comes back when the menu closes.
- **Big and simple, phone first.** Big text (`Kit.Big`: hero 56, title 40, heading 28, button
  24, body 19, never under 16 on the new screens; a lively hero card scaled to fit a phone may
  go to its own `Layout.MinTextPx`), big icons, one big arrow pointing at things (before ->
  after). Space between things, but no wasted space (designer, 2026-10-06: tight rows, a
  compact header, the next section peeking in). Avoid small text and description lines; use
  one only where it is truly needed.
- **Colours tell what a number is** (`Kit.Numbers`), one meaning each so the screen reads as a
  theme: bright yellow for prices and money, green for what you get, FREE and bonuses, sky
  blue for counts, odds and timers, red for a crossed-out price, rarity colours for rarity,
  and the moving rainbow (`UIAnim.rainbow`) only for deals and multipliers ("x2", "BEST
  DEAL").
- **Crossed-out prices are always true** and used only where they matter most (big money
  packs, VIP, 10 Mystery blocks, the release sale): the one-at-a-time total or a real sale price.
- **Anything that looks lacklustre** gets the same treatment: big, clear, moving, animated.

## 14. Lucky blocks (designer, 2026-10-03)

- Opening a thrown block uses Roblox's **default ProximityPrompt**, a 0.5 s hold on E,
  controller X or touch. This is an explicit exception to the custom kit control style.
- Held blocks are large, 2.8 studs per edge. World, hotbar and bag keep bright, saturated
  blue/gold textures; neutral preview light and a gentle emissive fill prevent muddy colours.
- The opening block spins immediately and rises for 1.4 s before bursting.
- The cue result keeps rarity-coloured turning rays, with no square shadow halo. A dark full-screen dim stays through the reel and result for cue contrast. The soft,
  transparent 1024px rays fade toward the edges rather than enlarging the old pixelated kit image.
- Hotbar/bag models leave padding around each icon. Gold King uses lower preview illumination
  so the bright gold albedo keeps its details.
- **The bag** (designer, 2026-10-07) works like Roblox's backpack: a click or tap on a block
  equips it (held out, its tile and slot edged in gold; again puts it away) and the bag stays
  open, so the number keys and a click on the world (throw) still work; a Mystery block closes
  the bag and opens its upgrade screen. A thrown block leaves the bag while it is on the floor.
  Dragging a block into the hotbar still works. On PC the **` / ~ key** opens
  and closes the bag like Roblox's own backpack (not while typing in a box); a gamepad's L3.

- Legendary uses 1.8x world/held scale to compensate for its crown and cape in the bounding
  box. Its body aligns with the hands; its inventory preview is framed 1.25x closer.

- Lucky-block reel skip works once per spin (designer, 2026-10-04): the tap/click never jumps to
  the prize; the strip races on from where it is and brakes onto the winner within
  `Config.UI.Reel.SkipSeconds` (0.7 s), a blur that shows the roll was skipped, then lands,
  centres and holds as usual. Any further tap during the spin or the hold does nothing.

- **The Mystery block's upgrade screen** (designer, 2026-10-07, like Star Drop but our own;
  `MysteryReveal`, `Config.LuckyBlocks.Reveal`). A ready Mystery block's hotbar slot says
  **OPEN!** in pulsing gold along its bottom; a tap, a click, its number key, or LB/RB to pick
  it then R2 opens the screen (a Mystery block is never held). Its 2D icon jumps out of the
  slot on an arc, growing past its size and settling, while the world blurs (a faint wash of the
  tier's colour, no dark dim). Every other screen hides. Over the block: the tier's name, big,
  tilted 4 degrees, in its colour (MYSTERY and MYTHIC in a moving rainbow); behind it a soft
  glow and slowly turning rays in the tier's colour; below "UPGRADE CHANCES" and 4 dots (empty
  ink; the next one a pulsing "?" over a rainbow; a used one filled in the colour that press
  showed, with a ball's gloss); under them "Tap!" / "Click!" / "Press A". The block floats up
  and down with a slight rock, each tier with its own particles (Standard warm motes, Uncommon
  green sparkles, Rare blue stars and an orbit, Epic purple streaks, Legendary a gold fountain,
  Mythic rainbow). A press squashes it; a press that keeps the tier gives a small hop and a
  rattle; one that raises it does one quick hop with a rattle, then the **impact**: a white flash
  over the screen and on the block, a screen shake, a ring and a burst of sparks, the new
  block landing a little big as its name slams in (designer: no spin). After the last press,
  "Tap to collect" (or 4 s): the words and dots pop away and the block arcs back into its slot,
  which bounces with a glow. Every press is done in under a second (designer, 2026-10-07: an
  upgrade about 0.55 s, a kept tier 0.25 s). Smooth: the block's place and size move by whole
  pixels and the fraction moves the picture inside its label, and the float runs under the
  presses. The shake is smooth noise that fades out (never random jumps a frame): the whole
  screen turns a degree or so and the block jolts, while the camera slides (never turns) a third
  of a stud, applied after the camera script so it never drifts. Taps during an animation wait their turn. Reduce Motion: no float,
  hops, shake or arcs; the twinkles stay. Lower effects: fewer particles.

## 15. Shop v3: block cards, pass bands, the build-in and the HUD's "+" (2026-10-04)

The Shop is one scrolling page (section 10's format) rebuilt round the lucky blocks, after the
designer's pasted references (`~/Desktop/GUI-refs/pasted/`; never the ChatGPT result sheets).
Sizes in `Config.UI.Shop.Page` and `.Block`; words in `Strings.Menus.Shop`.

**Emptied for the GUI overhaul (designer, 2026-10-04).** The client's shop page is down to its
frame, background and the four jump buttons (Featured, Blocks, Money, Passes, with their NEW
badges); the page, card, block card, odds, need, gift and thank-you modules were deleted. The
server shop is unchanged (products, receipts, restock, gifting, VIP, Money Party, the Starter
Pack, the Mystery and Grand Opening deals). The designs below are the reference for the
rebuild, not a description of the current screen.

**Decided**
- **Four jump buttons** down the right: Featured, Blocks, Money, Passes (outside the panel on
  a computer, a column inside it on a phone). Featured and Blocks keep a red NEW badge all
  through the Grand Opening window (`PinnedBadges`); other badges clear once seen.
- **Headers:** "— FEATURED —" over the Grand Opening band, "— LUCKY BLOCKS —" over the Mystery
  band and the restock tiles, "— STARTER & VIP —", "— MONEY —", "— PASSES —". The restock has
  no header word: a dark navy bar with the stopwatch, "New blocks in 6:12" (the time in gold)
  and each slot's chances (`BarPx`, `BarColor`).
- **Money is gold, Robux is green**, everywhere on the page: a gold candy with the cash
  bundle for a money price, a green candy with the Robux glyph for Robux. A gift square
  (purple on the Grand Opening card, 2026-10-06) sits left of every Robux button for a
  developer product; it opens the Gift Player popup.
- **The Grand Opening band** (reference 12; **built** as the lively Featured card,
  2026-10-06, after target 13b: see the `lively-gui` skill and `GrandOpeningCard`; it dropped
  the LIMITED pills, the save labels and the guarantee line, and its Robux buttons are bigger
  than its money buttons): the only dark card on the page (`FestiveFill`,
  navy fading deeper, a pale blue edge, gold sparkles). The NEW sticker, the crowned block
  and "Ends in 20d 23h" down the left; at the right the gold title "GRAND OPENING LUCKY
  BLOCK" between two stars, "YOU COULD PULL...", two chase cards (ink fill, pink Unique rim,
  the cue's name in its colour, UNIQUE and LIMITED pills, the cue's picture, the chance in a
  rimmed pill), then three columns: a green button "3 blocks · 129 ~~147~~" and a gold money
  button, "save 12%" under (by the Robux prices). The guarantee line under all. On a narrow
  card the block stacks over the rest.
- **The Mystery band** (reference 13): the block at the left under "Always in stock", the
  title and "Opens into one of the six blocks below" (no timer since 2026-10-07); pale odds rows with a small still block and the kind's name in its colour ("Icons"
  odds style); "Epic cue or better: 0.13%"; x1 and x10 in pale boxes with gold labels, the
  gold money button over the green Robux button, "-30% SALE" stuck on the x10 column during
  the release sale (no crossed-out price there).
- **Restock tiles** (references 20, 21): the block, "**Uncommon** Lucky Block" with the kind
  word in its colour, the coloured odds rows, three chase pictures (one cue from each of the
  top three rarities, rimmed in the cue's colour, its chance under), the gold money and green
  Robux buttons side by side, "3 left for you". The VIP slot for a non-VIP: a grey tile, the
  gold padlock over the block, "VIP only · a 4th block every restock" in gold, Get VIP.
- **Starter Pack and VIP** (reference 14): two wide pass bands side by side (one per row on a
  phone): art left, title / big number / line, odds pills (Secret with a rainbow rim) or
  VIP's six perks in two columns, the timer or LAUNCH SALE ribbon and the crossed price
  bottom left, the button bottom right; VIP's card is cream.
- **Money packs** (reference 15): the art, the gold amount and the green button only (no
  pack name or bonus line); a red "FIRST BUY x2" pill in the top left of every pack until the
  first buy is used; a red "-30%" band across the top right corner during the sale, with the
  old Robux price struck through above the button.
- **Passes** (reference 15): wide tiles, the art at the left, the name and its line at the
  right, the button across the bottom: Money Party ("x2 money for everyone in your server,
  15 min"), Ability Slot 2 and 3, Roblox Plus ("+10% money and a tag", Get; hidden for
  members).
- **Opening the Shop** lays the first screen's headers and cards in from the top left to the
  bottom right like blocks (`Build`); now and then a card shimmers and its block pops
  (`Shimmer`, `IconPop`); the blocks turn slowly; the Mythic block's icons carry a cycling
  pastel aura (`Config.LuckyBlocks.UI.RainbowAura`), in the hotbar and bag too.
- **The HUD's "+"**: a small gold candy right of the money HUD opens the Shop on Money. It is
  hidden during a game, and the pill closes up without it (designer, 2026-10-06).
- A block kind whose model is not in the place yet shows the gift-box kit icon in the Shop,
  the hotbar and the bag (`Block.Fallback`; the case chests are gone, 2026-10-04), so nothing
  is ever an empty square. Every kind has its model today.

**Open**
- The exact tuning of "each section about one screen tall" on a computer.

## 16. The player list (designer, 2026-10-07)

Like Roblox's own list, flush in the top-right corner of Roblox's top bar row (`PlayerList`,
`Config.UI.PlayerList`). The Shop's lively card: the pale blue header band with its 8-balls
scrolling ("Players (n)" and a chevron) over the white sheet with the still dots; pressing the
header opens or folds it (0.15 s). One list, no tabs: a small "Wins" and "Money" titles row,
then the rank badge and username with its flag just after it (the flag is never cut; a long
name ends in "..."), your row pale blue and your name blue, wins and money right-aligned
(money from $100,000 up as "$123K", only here); each person in their own white box with a
thin pale blue edge and a small gap; 360 px wide on a tablet or computer. Folded at first on every screen; left open, it opens again on the next join. Not shown on a phone for now (designer, 2026-10-07: too
much of the screen); its phone sizes (3.3 rows) stay in Config for when it comes back. It narrows (down to 176 px) before it would touch the
Settings gear. Pressing a real player opens the Trade / Add friend / View profile card beside
it.

On a phone the rank HUD and the Settings gear sit in line with Roblox's own top-bar buttons
(designer, 2026-10-07): the pill and the gear 44 px tall from 12 px down the row, the badge's box
58 px (its art shows 44). On a computer or tablet the HUD is 1.3x and its badge 1.35x more.
The player list's header lines up with them: "Players (n)" in the rank name's size, the band
tight round it (30 px) and centred on the same line.

## 17. The cue card (designer, 2026-10-08)

One card for every cue: the Cues grid and the Index now, the lucky block spin and YOU GOT
next (`InventoryCard`, its motion `CueCardFx`, `Config.UI.CueCard`; brief
`docs/prompts/CUES_LIVELY_PROMPT.md`, concept 1 approved in round 4). Card units 150 x 190.

- **No wasted space**: the cue's picture fills the top (a square 94% of the card's width); the
  name sits over its lower edge in white with the ink outline (one line that shrinks, then
  wraps); the **rarity bar** along the bottom is a pill in the rarity's colour with the
  rarity's word inside, upper case, white with the ink outline (style A).
- **Corners**: top left the chance chip (dark, the percent in the rarity's light colour; only
  on cues that drop from a block, a Unique cue showing its Grand Opening odds), then NEW and
  Equipped under it; top right the count ("x3") and the padlock on Exclusive and Unique
  cues. A numbered copy's number ("#412") is a dark chip with gold words just above the name,
  on the right.
- **Words keep the card's scale** (concept 2, 2026-10-08): a phone's small card shrinks its
  words with it, down to 6 px (`Config.UI.CueCard.Layout.MinTextPx`), rather than holding a
  floor that crowds the card.
- **The card** is filled in its look's colours and rimmed by the rarity edge with a thin white
  line inside it. Faint 8-balls in the card's colour drift slowly up-left behind every card
  (13% on light cards, 7% on dark ones; "very transparent", 30 s a period).
- **Motion grows with rarity**: Common only the 8-balls; Uncommon a glow and a shine every 7 s;
  Rare plus sparkles; Epic plus turning rays; Legendary gold rays, a breathing glow, sparkles,
  rising embers, a strong shine, a light running round its gold edge, a halo and a shine
  across the bar; Mythic deep space with a hologram sheen, twinkling stars, a rainbow edge and
  flowing bar colours; Secret near-black with a red glow from the bottom, scan lines, red
  embers, a glitch and a breathing red edge; Unique pink with a glow, sparkles and a shine;
  Exclusive blue with a glow and a shine.
- **Ranked**: the bar says RANKED with the tier's badge whole over its left end (never cut),
  the card in its tier's colours, more moving higher up (Bronze to Gold a metal shine,
  Platinum and Diamond glints, Expert to Master turning rays, Grandmaster dark with gold rays
  and embers, Reyes everything with a rainbow edge and bar). No chance chip.
- **A never-found cue** in the Index (designer, 2026-10-08): its whole card with its name,
  standing still under a light grey veil that leaves its colours showing, a big padlock over
  the picture, no pills (`Config.UI.CueCard.Locked`). It was a grey card with a dark
  silhouette.
- Hover and gamepad selection: a gold ring, a small grow and a slow, small lean (1.2 degrees);
  a press puts the gold ring out until the pointer comes back, and touch never lights a card;
  the chosen card a blue ring.
- Only cards in view move (one loop each); Lower effects shows fewer sparkles, embers and
  stars and slows the shines; Reduce Motion stills everything but the glows.
