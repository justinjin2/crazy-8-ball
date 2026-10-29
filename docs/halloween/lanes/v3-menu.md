# Lane v3-menu (the Halloween event menu, card effects, the 2026 emblem)

Folder `~/Desktop/8ball`, branch `halloween` (no worktree; Rojo 34872 into the Team Create
Studio, the only lane on Studio). Base 90e23dc8. Commits on `halloween`, not pushed (the
coordinator pushes after merging).

## What was built (2026-10-29, 12:24-13:10)

1. **The cards' pink edge is never cut** (df41b14f). The edge is a UIStroke drawn outward from
   the fill; the fill (and its 8-balls) is now inset by the edge's thickness, the white inner
   line with it, so the edge lies inside the card's box (InventoryCard's way). The scroller cut
   the first card's left and the row's top before.
2. **The Sword's purple burst** plays on its own card (HwCard4) since the easiest-first order
   (51acd2a3, `Config.UI.Halloween.Open`).
3. **The King's drop card only when its cue is not on sale** (ad0752bc): with the drop switched
   back on, the Jack would have shown twice. Off today: no change on screen.
4. **The cards move like the Cues inventory's** (ab6caee4, tuned in e4ed797a): their 8-balls
   drift up-left (CardMath.ballsWindow, 30 s a period) and each cue's own effect art plays live
   in 2D over its still picture (`Halloween/CardFx`, maths `shared/HwCardFxMath`, numbers
   `Config.UI.Halloween.CardFx`):
   - Pitchfork 4 sprites: two flames on the outer prongs' points (`TipFlameA` art; one still
     flipbook frame breathing smoothly, no frame stepping), two sparks (`ForkSparks`);
   - Witch's Broom 6: gold/violet/teal stars twinkling round the stick (`StarGlints`,
     `SpellPopGold`), violet dust (`VioletMotes`);
   - Jack-o'-Lantern 8: flames up the shaft (`Flame1`, 4x4 flipbook at 18 fps), embers (`Embers`);
   - Halloween Sword 12: a deep-purple aura along the blade (Kit SoftGlow, behind the cue),
     purple flames flowing up both edges (`EdgeFlamesL`, 16 fps), lilac sparkles (`EdgeSparks`).
   Each layer reads its texture and flipbook grid from the cue's generated skin row by emitter
   name (Aura, then TrailEmitters, then Pocket Layers; the first name found), so the cues lanes'
   re-uploads come through; if none of the names is left, the layer uses its own `Texture`/`Grid`
   (today's ids). A flipbook sprite is a clip frame holding the whole sheet, moved by whole
   frames, so a sheet of any size lines up (never rotated). Positions are shares of the cue
   picture's square along `Axis` (butt to tip, measured from today's thumbs).
5. **The "Halloween 2026" emblem** (1ba7958b): `tools/gui/hw_emblem.py` (SVG, headless Chrome,
   the game's flat ink style), `assets/ui/halloween/Emblem2026.png` 320 x 128, uploaded as an
   Open Cloud **Image** asset **91473013507424** (the asset id is the image id; it loaded in
   Studio). `Config.UI.EventEmblem` (Enabled, Images by Catalog Event, Aspect, CardUnits);
   `shared/EventEmblem.image(cueId)` picks it by the Catalog row's Event, no code per cue.
   Shown top left: the event menu's cards (`Layout.Card/ShortCard.EmblemUnits`), and through
   `InventoryCard` on My Cues, the Index (not on a locked card) and the YOU GOT card (and the
   big card), in the chance chip's place with NEW and Equipped under it.

## Cost (a low-end phone)

- Sprites: 30 ImageLabels + 17 clip frames for all four cards; Lower effects 15. Per frame per
  visible sprite: Position, Size, ImageTransparency (+ Rotation or a frame move). One
  `UIAnim.loop` for the whole menu, only while it is open (stopped on close), only for cards
  that have landed and are inside the scroller's window; Lower effects at most 30 steps a second.
- Textures: only ones already in the game (the skins' emitter sheets, Kit SoftGlow) plus the
  emblem (320 x 128). No new sounds.

## How to check by hand

- Open the event menu (the Halloween tile): four cards with their 8-balls drifting, the effects
  moving, the 2026 emblem top left, all four pink edges whole. Not owned: Robux (with gift) and
  Candy buttons on all four including the Jack; owned: OWNED.
- Cues menu: the four event cues carry the emblem, Equipped under it; the Index shows it only on
  found event cues.
- Settings, Lower effects on: about half the effects; Reduce Motion: only the Sword's glow.

## Studio checks (13:00, Team Create place, designer's account)

Lint OK, 1513/1513 tests. Console clean (only the known 203785492 ContentId line).
Shots in `~/Desktop/8ball-refs/halloween/v3/menu/`: 01/02 PC unowned, 03 and 10 phone 844x390
(Root trick; every TextLabel fits), 04 My Cues, 05 Index, 06 YOU GOT (luckyReel with the Sword),
07 PC owned, 08/09 a 360 px lab of the four effects at two moments. Counted in play: 30 sprites
shown, 15 with Lower effects, 1 with Reduce Motion, 0 after close, 30 after a close and quick
reopen; the 8-balls' offset moves.

## Open issues / for the coordinator

- The cues lanes may rename emitters or re-render thumbnails: after merging, look at the four
  cards. A renamed emitter falls back to today's texture (no error); a moved thumbnail needs the
  Pitchfork's `Spots` (the prong points) or an `Axis` retuned in `Config.UI.Halloween.CardFx`.
- The NEW CUE! card after a Candy buy (core's `Halloween/CandyToast`) has no emblem: core's file.
  One line there would add it: an ImageLabel with `EventEmblem.image(cueId)`.
- Not checked here: a real gamepad (no new selectable parts), an iPad size, a fresh-player run
  (the designer's Studio save owns the cues; resetting it was not worth it).
- **Prices to check (not changed here):** in Studio the cards' Robux buttons read 40 / 200 / 320 /
  480 and the Candy packs 40 / 120, while `Config.Products.List` says 49 / 249 / 399 / 599 and
  49 / 149. The menu shows what `Store.readPrices` gets from Roblox
  (`MarketplaceService:GetProductInfoAsync(...).PriceInRobux`), so these look like the products'
  prices on Roblox right now (a uniform ~20% lower: regional or price-optimised pricing, or
  products set to other prices). Worth a look in Creator Hub before the publish.
