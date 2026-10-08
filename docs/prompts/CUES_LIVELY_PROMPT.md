# The GUI redo: cue cards, Cues, the lucky block spin, Free Reward, Abilities, Ranked

**Started 2026-10-08 with the designer** (branch `shop-lively`). Method: the `lively-gui` skill
(`.claude/skills/lively-gui/`), with one rule from the designer on top: **every screen gets a
concept first and is built only after the designer approves it, one screen at a time**
("let me get a concept art of each gui ... get my approval before you actually implement it").

## The request (designer, 2026-10-08, in short)

- Bring back the Abilities and Rank screens (done: they were hidden by `HudFocus`); upgrades only
  as concepts to approve ("the original guis for rank and ability were good").
- **Inventory -> Cues**: the backpack icon becomes a cue, the menu is named Cues, no tab row,
  and at least the first two rows of cards show when it opens. Lively frame and animation.
- **The cue card** (shared by Cues, the lucky block spin and YOU GOT): far less wasted space;
  the rarity's name inside the rarity bar, in its colour; better colours, particles and motion
  per rarity, especially Legendary; very faint, slow moving 8-balls behind every card.
- **Ranked**: the ten rank cues are one rarity, Ranked, each card in its tier's colours and
  effects.
- **The lucky block spin**: the same cards on the reel and on the YOU GOT screen (its outline
  colours and effects instead of a see-through background); rarer cues show up more often on
  the reel (purely visual, every block, so a Standard block still feels like it has a chance).
  The real odds and the odds shown never change.
- **Free Reward**: the Lucky 8 Block's icon on the favorite card, and the block goes to the
  hotbar/bag when the favorite is done.

## Order and gates

1. The cue card. 2. The Cues menu. 3. The lucky block spin and YOU GOT. 4. Free Reward.
5. Abilities upgrade ideas. 6. Ranked upgrade ideas. Each: concept page (private Artifact) ->
designer approves or notes -> build -> Studio check (phone, PC size, gamepad by the designer)
-> commit. Concept sources go to `~/Desktop/8ball-refs/gui-lively/work/cues-*/page/`.

## Decisions (dated lines also in `docs/DECISIONS.md`)

- 2026-10-08: The Index becomes a book button inside Cues, beside Sort (its red "!" with it).
- 2026-10-08: Favorite: $10,000 + a Lucky 8 Block (was a Mystery block). Group: 3 Mystery blocks,
  unchanged.
- 2026-10-08: Every card shows its chance (top-left chip, in the rarity's colour), in Cues and on
  the spin alike; the moving 8-balls stay very faint (designer: "too distracting").
- 2026-10-08: Ranked sorts where Exclusive did (between Epic and Legendary), highest tier first
  (lowest first in "Common first"); approved with the card. VIP and Starter stay Exclusive.
  Ranked pays Exclusive's finder's money ($5,000) and has its own Index row (no reward).
- 2026-10-08: Cues menu: the tiles stand outside the panel's right edge, 5 cards per row; the
  Index is reached by a My Cues / Index switch (replaces the book button beside Sort); the
  Index's chosen cue is a flat swaying picture, not 3D; a copy number sits above the name on the
  right; card words scale with the card on every screen (no 12 px floor for names on a phone).
- 2026-10-08: Numbers on the first 1,000 copies of every block cue (Common to Secret; Unique
  cues keep numbering every copy; Ranked, VIP, Starter, Classic plain); Sell all never sells a
  numbered copy; a sold number is gone for good; "N exist" on the big card for every cue.
  Reopened the same day by the designer (100 or 500 instead? piles of numbered Commons?); my
  proposal, **approved** (designer: "ok"): only the **first 100 of every Rare, Epic,
  Legendary, Mythic and Secret cue**, Commons and Uncommons never numbered, and each numbered
  copy is **its own card** before that cue's plain stack.
- 2026-10-08: Concept 2 approved at round 2 (designer: "ok"): the My Cues / Index switch, 5 per
  row, the Index's flat swaying picture, the copy number above the name, card words at the
  card's scale on a phone. The icon (1 to 4) is picked in the build's plan.
- 2026-10-08: The CUES icon approved at round 5: the Classic Cue at the other icons' size,
  striking a cue ball on hover and harder on press. The Index's chosen cue is its card,
  standing still (not a swaying picture); a never-found cue is its whole card, slightly greyed,
  with a padlock (not a silhouette); Sort starts on Rarest first on every open; a numbered
  copy's engraving sits near the butt end only, never near the tip.

## Concept 1: the card (round 1, waiting)

https://claude.ai/artifact/FLwcXzUbGm4ji4V6YgDsV2. The cue picture fills the top of the card
(the in-game card pictures, `assets/cue/thumbs`), the name over its lower edge, a rarity bar
along the bottom with the word in it, pills in the corners (x2 / #412, the lock, NEW,
Equipped). About 20% shorter than today's card. Faint 8-balls (the lively header tile, tinted)
drift up-left behind every card. Motion grows with rarity: Common only the 8-balls; Uncommon a
glow and a shine; Rare plus sparkles; Epic plus turning rays; Legendary gold rays, glow,
sparkles, embers, a fast shine, a light running round its gold edge and the bar; Mythic deep
space with a hologram sheen, stars and a rainbow edge; Secret near-black with a red glow, scan
lines, red embers and a glitch. Ranked: the tier's colours with its badge beside RANKED, the
effects growing with the tier (Reyes gets everything and a rainbow edge).
Questions asked: bar style A (coloured bar) or B (dark bar, coloured word); is Legendary and
up exciting enough; the chance % off the Cues cards but on the spin's cards.

Round 4 (2026-10-08), **the look to build**: bar A (the rarity's colour, the word in white with
the ink outline); the 8-balls in each card's colour, very faint (light cards 13%, dark 7%); the
motion as shown (designer: "just right"); a rank badge whole over the bar's left end, never
clipped (designer: "make sure the ranks do not get cut off"); a chance chip only on cues that
drop from a block (Unique cues show their Grand Opening odds), none on Ranked, VIP or Starter
(designer: "no need to put an extra pill to say x rank").

Round 3 (2026-10-08): the 8-balls about three times fainter (light cards 13%, dark 7%), the
chance on every card.

Round 2 (2026-10-08, designer: "the balls dont look like 8 balls though they need to actually
show the 8 ball detail"): the flat silhouettes are replaced by a new tile of real 8-balls, each
with its white disc and a clear 8, bigger on the card (`tools/gui/card_balls.py`, now `card_art.py`,
`assets/ui/cards/`), in two looks to pick from: tinted to the card's colour, or classic black.

## Concept 2: the Cues menu (approved round 2)

https://claude.ai/artifact/AAsZhs9Dqn1xJkT9gzQ1Xv (sources in
`~/Desktop/8ball-refs/gui-lively/work/cues-menu-A/`). The Inventory renamed Cues in the Shop's
lively frame (header 8-balls, money pill with +, the 8-ball flair, the unroll and the card pops),
no tab row, the panel as tall as two whole rows of cards with the third peeking (computer: cards
169 x 214 in a 920 x 549 panel; Studio's 750 x 362 phone: 83 x 105, under the 118 px of today's
phone cards, names at the 12 px floor so long ones take two lines). The Index opens inside the
menu (title Index, a back arrow top-left; B does the same; Sort and Sell step aside). Tapping a
card slams in its big card beside "You own 5", the chance, Equip and Sell duplicates (no pills on
the big card: the right side says them). Three cue icons drawn in the column's sticker style
(A one golden cue, B two crossed cues, C a cue on a card; scratch drawing, not yet in
`tools/gen_ui_art.py`).
Questions asked: where Sort, Index and Sell go (tiles outside the right edge like the Shop's, my
pick; in the title row, where on a phone Index and Sell become icons; or their own row like today,
where on a phone the cards shrink to 71 px); which icon; 5 or 6 cards per row.

Round 2 (2026-10-08), from the designer's notes on round 1:
- Tiles outside the right edge (designer: "ok"), **5 cards per row**.
- The Index is a **two-part switch** on top of the tiles (designer: "its like a toggle where it
  switches back and forth from index, and "cues" that you own"): the top half My Cues with the
  cue icon, the bottom half Index with the book and its red "!"; a blue knob slides to the place
  you are in, the title changes to match, Sort and Sell step aside in the Index, B goes back to
  My Cues. No back arrow.
- The icon: crossed cues, but not the purple design (designer: "something different show me
  first thats more appealing to click on"). Four new looks: 1 red and blue, 2 with a white cue
  ball, 3 on a gold burst, 4 gold and black (scratch drawing, not yet in `tools/gen_ui_art.py`).
- The Index shows the chosen cue as a **flat picture that sways** (turns a few degrees and
  squeezes sideways); the 3D turning cue goes (designer: "no more 3d rotating version you can
  even rotate a 2d picture").
- A copy number (#412) moves from the top-right corner, where it covered the cue's tip, to a
  chip **just above the name on the right** (designer: "above the name on the bottom right").
- Card words on a phone are the **same share of the card as on a computer** (designer: "the
  font looks a little big on phone for the names ... should be similar scale on pc"): this
  replaces the 12 px floor for card names on a phone (`Config.UI.CueCard.Layout.MinTextPx`).
- New request: **numbers on the first 1,000 copies of every cue, every rarity** (designer: "so
  early goers feel special to know that they owned like one of the first thousand cues even if
  it was a common cue, this could give these cues even more tradeable value"), and how many
  exist shown for every rarity. The page's numbers are examples. A server and save change,
  planned on its own after the Cues menu (GDD 18). **Rules (designer, 2026-10-08):** every cue
  that drops from a block (Common to Secret) is numbered on its first 1,000 copies; Unique cues
  keep numbering every copy; Ranked, VIP, Starter and Classic stay plain. Sell all never sells
  a numbered copy (one sells only from its own card, after a warning). A sold number is gone
  for good. "N exist" shows on the big card for every cue, never on the grid's cards.
  My defaults for the plan: numbering starts at the public release (test numbers wiped); in a
  trade a numbered copy is its own card and you pick which copy goes.
  **Reopened the same day** (designer: "maybe instead of 1000 maybe just 100 ... what if someone
  who plays rolls like multiple first number serial copies ... are they separate cues from the
  actual, even for common? ... you should research and decide for me a proposal"). **My
  proposal (round 2b of the page), approved 2026-10-08 (designer: "ok"):** number only the first 100 copies of
  every Rare, Epic, Legendary, Mythic and Secret cue (#1 to #100; 30 cues, 3,000 numbered
  copies in all, 30 of them a #1); Commons and Uncommons never; Unique cues unchanged. A
  numbered copy is the same cue but its own card (never stacks), its gold number above the
  name, placed just before that cue's plain stack (Phoenix #12, then Phoenix x4); its big card
  says "Copy #12, one of the first 100" with Equip and Sell this copy. Why, from
  `tools/economy_model.py` at the plan's launch size (1,700 new players on day one, about 500
  peak online in week 1; a scratch copy reporting every rarity): the first 100 per cue are
  gone on day 1 for Rare, about day 13 Epic, day 29 Legendary, day 49 Mythic, about 3 months
  Secret; with 1,000 per cue Rare lasts 5 days and Epic 38. Each Common gets about 1,200
  copies on day one, so 1,000 numbered Commons and Uncommons would give every day-one player
  about 9 numbered copies Sell all can't clear. Outside games show the same pull (low serials
  sell far above high ones; Roblox Limited collectors chase #1 and special numbers), and it
  rests on scarcity. Also found: two players can end up with the same Unique number when one
  trades it away and unboxes that cue again (`Counts.takeNext` remembers the first owner);
  fixed with this work.
Questions asked: which icon (1 to 4); does the switch feel clear. Answer: "ok" (round 2
approved; the icon is asked in the build's plan).

## Concept 2b: the CUES button and numbered copies (icon approved round 5; built)

https://claude.ai/artifact/4Yt2zXLQ2nHTxHichzK8ob (sources in
`~/Desktop/8ball-refs/gui-lively/work/cues-icon/`; the art from a scratch script on
`tools/gen_ui_art.py`'s helpers, to move into it once picked). The designer turned down the
crossed cues: "maybe instead of 2 just one with a unique animation hovering/ clicking on it hits
like a white cue ball, and jusst make the cue skin the generate black wood one? show me this
first". One cue aimed at a white cue ball, in layers (cue, ball, and optionally a round patch of
table felt with a wooden rim and its sights): on hover the cue draws back, snaps forward and the
ball shoots off with a spark, then pops back; a click or tap is a harder hit, starting on
press-down. Picks: the cue A all black (like the Midnight Cue) or B black wood with a maple
shaft; nothing or the felt behind it (my pick: the felt, as bold as the basket and the 8-ball).
Also the numbered copy's look (designer: "make sure to add serial number cues are separate from
the actual cue skin with some unique indicator ... like #1/100"): its own card with a gold
plaque "#12/100" above the name, mark A the plaque with a glint, B plus a gold line with a
running glint inside the card's edge; the big card says "#12/100" and "One of the first 100 in
the game" over the chance and how many exist, with Equip and Sell this copy.

Round 2 notes (2026-10-08): "no when i mean the cue hitting a ball no table behind it, just the
cue and white ball thats wrong". The felt is gone: the icon is only the cue and the cue ball,
redrawn bigger, the cue lined up on the ball at a shallow angle so both sit clear of the
column's red dot (top right) and the word CUES (bottom). Then: "for cues with serial numbers add
an engraving somewhere on all the cues, show me an example before implementing on all of
them". Example shown on the same page, from Studio on the game's own cues: a small gold
nameplate with a dark rim on the butt sleeve, the number cut in ("#12/100", Fredoka One, dark
brown with a light edge), on the cue in hand (facing up) and on the back in the lobby (facing
out of the back). Built for every numbered copy with the copy numbers, once approved. Still to
pick: the cue A or B, the card's mark A or B, and the engraving.

Round 3 notes (2026-10-08): "cue looks way too short, should be look like the classic cue first
of all, and the icon doesnt have a ball when not hovered over it, but when you hover over it the
ball appears and it hits it". The cue is now the Classic Cue (its black wrap, brown forearm,
maple shaft, white ferrule and navy tip; long and slim, tapering) lying across the tile at -33
degrees, and the icon at rest is the cue alone (also the still icon in the header and the
switch). On hover the cue draws back, the ball pops in just ahead of the tip once it is clear,
a short aim, the snap with a spark, the ball shoots off up and away and fades, and the cue
slides back to rest (0.95 s; a click 0.7 s and harder). The cue A / B pick is gone. Still to
pick: whether the icon is right now, the card's mark A or B, and the engraving.

Round 4 notes (2026-10-08, a sketch over the column): "still too small look at how i drew it it
needs to be like what the old double cue was but just one cue instead and add like a sparkle
effect". The cue is now the crossed-cue icons' chunky cue (half widths 18 to 9.5 on the 256
canvas) at -46 degrees in the Classic colours, with a soft gold glow that breathes and three
twinkling sparkles. In the column it is drawn 1.46 tiles big, placed as sketched: the butt just
above the word's top left, the cue passing left of the red dot, the tip just under the end of
SHOP. The ball still shows only on hover.

Round 5 notes (2026-10-08, beside a shot of the real Classic Cue on an avatar's back): "notice how
small the light beige part is of a cue, it doesnt look like an actual cue, make the dark brown and
black part shorter like an actual looking cue and its a little long now overextending near the
shop it should be same like width and length as all the other icons (the white ball overextends
and doesnt count as total size)". The cue now has the Classic Cue's proportions as measured on
the game's cue (about 54% maple shaft, 21% forearm, 19% wrap and cap; `Catalog.style` says 48 /
22 / 22.5), the tip, ferrule and rings drawn a little longer so they read at 84 px. Its canvas is
the other icons' (`IconShare` 1.08 at `IconCentreShare` 0.46) and the cue fits their box: the butt
where round 4 had it, just above the C of CUES, the tip at the tile's top just left of the red dot
(round 4 without the part that stuck out toward SHOP). Half widths 20 to 8.5, picked from 17.5,
20 and 22 against the basket. The sparkles and the glow stay inside the box; the ball has its own
canvas at the same scale so it can fly out, over the red dot.

Approved (2026-10-08, "looks good. replace the backpack now"): built as `CuesStrike` on the
CUES tile, the art in `tools/gen_ui_art.py` (`cues`, `cues_cue`, `cues_ball`, `cues_twinkle`),
uploaded, and the still icon in the menu's header and the switch. Still to pick for numbered
copies: the card's mark A or B. The engraving's place is decided: **near the butt end only,
never near the tip** (designer, pointing at the lineup of three cues with the plate on the
butt sleeve); it is built with the copy numbers.

The same day's notes on the built menu, all done: the rail's tiles evenly spaced; Sort starts on
Rarest first on every open; the Index's big card is the new card, standing still; never-found
cues are their whole card, slightly greyed with a padlock (no more silhouettes); the big card
and the Index's panel on the Shop sheet's tiny pool-ball dots; Equip clear of the card; a click
no longer leaves the card gold and the big card no longer bursts gold or shakes hard; the money
from a sale counts up in the header as its chip lands; the click sound a warm little "boop".
"Sell all made a mistake and sold the numbered unique copies": no numbered copy exists yet. The
"#12"-style chips were Studio-only stand-in numbers (`GuiQA "cuesCopies"`, left on during the
check; every play session starts with them off), drawn on Rare-or-rarer cues that were really
plain duplicates, so Sell all sold plain copies as it should. The server's Sell all only ever
sells Block cues' extras and keeps one (`Inventory.duplicates`); Unique cues are never sold.
When copy numbers are built, Sell all skips every numbered copy (already in the GDD).

## Progress

- [x] Abilities and Ranked screens show again (`HudFocus`, `Config.UI.Menu.Focus.KeepWith`).
- [x] Concept 1 (the card) approved (round 4, 2026-10-08).
- [x] The card built (2026-10-08): `InventoryCard` (Cues grid, Index), its motion `CueCardFx`,
  the maths `CardMath`, every number in `Config.UI.CueCard`; the Ranked rarity in the data.
  Checked in Studio on every look (`GuiQA "cueCards"`), the real Cues grid and the Index's
  Ranked row, Lower effects and Reduce Motion. Waiting: the designer's look on a phone, a PC
  size and a gamepad. The reel's cards come with concept 3.
- [x] Concept 2 (Cues menu) approved (round 2, 2026-10-08).
- [x] The Cues menu built (2026-10-08, f41db44): the lively frame with no tab row, `CuesRail`
  (the My Cues / Index switch, Sort and Sell all with hanging pills, outside the right edge),
  5 cards a row with the third row peeking, the copy chip over the name, the slammed-in big
  card, the Index at 4 cells a row with the flat swaying picture (`CueViewport` deleted), the
  NEW count on the CUES tile. Checked in Studio at a PC size: the open (no stall, glows wait
  for their cards), Sort, the switch spammed, Reduce Motion, stand-in copy numbers
  (`GuiQA "cuesCopies"`). Gate D page: https://claude.ai/artifact/EAskweNWeTsDZUdsDP5Kbk
  (sources `~/Desktop/8ball-refs/gui-lively/work/cues-build/`). Waiting: the designer's look on
  a phone and a real gamepad.
- [x] Concept 2b's CUES icon approved (round 5) and built (2026-10-08): the striking cue on the
  CUES tile (`CuesStrike`, `StageMath.strikePose`, `Config.UI.Menu.Column.Strike`), the still
  icon in the header and the switch; with the designer's ten notes on the built menu (above).
  Checked in Studio at 1365 x 768: hover and Reduce Motion on the strike, the rail, the big
  card, the Index's locked cards and still card, a card's hover and click, the money count.
- [x] The designer's next notes (2026-10-08): the switch split into My Cues and Index tiles,
  all four tiles evenly spaced (Sort and Sell dupes still step aside in the Index); "Sell
  all" renamed "Sell dupes"; the Equip sound (117649901456711, after the server says yes);
  locked cards keep their moving background under the veil; the money chip speeds into the
  cash icon and fades into it, and the icon swells smoothly instead of the pill jumping in one
  frame. Checked in Studio at 60 fps with real-speed recordings
  (`~/Desktop/8ball-refs/gui-lively/work/cues-money/`).
- [ ] Copy numbers (approved 2026-10-08: first 100 of every Rare-or-rarer cue, each its own card):
  planned and built after the Cues menu.
- [ ] Concept 3 (spin and YOU GOT) approved, then built. The cards went in first at the
  designer's word, no concept (2026-10-08): the reel's cards are the cue cards with their
  chance chip, all standing still (the prize too: a moving one gives the pull away); YOU GOT
  shows the cue's card big with all its motion. Built a few a frame (`Reel.EagerCards`,
  `CardsPerFrame`). Test: `GuiQA "luckyReel" <kind> <cueId>` (nothing asked of the server).
  On trial (designer: "the white backgrounds are a little bit too busy"): the reel's cards
  with a dark see-through face and their rarity's edge (`Reel.ClearCards`,
  `Config.UI.CueCard.Clear`); YOU GOT keeps the full card. Rarer cues show more often on the reel (designer: "yes", 2026-10-08; `Reel.WeightPower` 0.3,
  purely for show).
- [ ] Concept 4 (Free Reward) approved, then built.
- [ ] Concept 5 (Abilities ideas) shown; built if approved.
- [ ] Concept 6 (Ranked ideas) shown; built if approved.
