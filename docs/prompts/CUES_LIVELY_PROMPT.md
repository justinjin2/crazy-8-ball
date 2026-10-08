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

## Concept 2: the Cues menu (round 1, waiting)

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

## Progress

- [x] Abilities and Ranked screens show again (`HudFocus`, `Config.UI.Menu.Focus.KeepWith`).
- [x] Concept 1 (the card) approved (round 4, 2026-10-08).
- [x] The card built (2026-10-08): `InventoryCard` (Cues grid, Index), its motion `CueCardFx`,
  the maths `CardMath`, every number in `Config.UI.CueCard`; the Ranked rarity in the data.
  Checked in Studio on every look (`GuiQA "cueCards"`), the real Cues grid and the Index's
  Ranked row, Lower effects and Reduce Motion. Waiting: the designer's look on a phone, a PC
  size and a gamepad. The reel's cards come with concept 3.
- [ ] Concept 2 (Cues menu) approved, then built. Round 1 shown 2026-10-08.
- [ ] Concept 3 (spin and YOU GOT) approved, then built.
- [ ] Concept 4 (Free Reward) approved, then built.
- [ ] Concept 5 (Abilities ideas) shown; built if approved.
- [ ] Concept 6 (Ranked ideas) shown; built if approved.
