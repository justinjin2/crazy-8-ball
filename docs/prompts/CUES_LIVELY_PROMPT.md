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
  proposal, waiting for the designer's OK: only the **first 100 of every Rare, Epic,
  Legendary, Mythic and Secret cue**, Commons and Uncommons never numbered, and each numbered
  copy is **its own card** before that cue's plain stack.

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

## Concept 2: the Cues menu (round 2, waiting)

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
  proposal (round 2b of the page, waiting for the OK):** number only the first 100 copies of
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
Questions asked: which icon (1 to 4); does the switch feel clear.

## Progress

- [x] Abilities and Ranked screens show again (`HudFocus`, `Config.UI.Menu.Focus.KeepWith`).
- [x] Concept 1 (the card) approved (round 4, 2026-10-08).
- [x] The card built (2026-10-08): `InventoryCard` (Cues grid, Index), its motion `CueCardFx`,
  the maths `CardMath`, every number in `Config.UI.CueCard`; the Ranked rarity in the data.
  Checked in Studio on every look (`GuiQA "cueCards"`), the real Cues grid and the Index's
  Ranked row, Lower effects and Reduce Motion. Waiting: the designer's look on a phone, a PC
  size and a gamepad. The reel's cards come with concept 3.
- [ ] Concept 2 (Cues menu) approved, then built. Round 1 shown 2026-10-08; round 2 shown
  2026-10-08 (the switch, four icons, 5 per row, copy numbers above the name, phone text).
- [ ] Copy numbers: the proposal (first 100 of every Rare-or-rarer cue, each its own card) shown
  2026-10-08 on the concept page; on the OK, a plan after the Cues menu is built.
- [ ] Concept 3 (spin and YOU GOT) approved, then built.
- [ ] Concept 4 (Free Reward) approved, then built.
- [ ] Concept 5 (Abilities ideas) shown; built if approved.
- [ ] Concept 6 (Ranked ideas) shown; built if approved.
