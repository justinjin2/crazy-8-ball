# UI icons

Every icon here is drawn in code by `tools/gen_ui_art.py` in one shared style (docs/UI_STYLE.md
section 6): a thick ink outline `#1B2033` with a small drop lip, a light-to-dark gradient on each
colour, and a white shine. No words or digits in any image. Each `<name>.png` (256 px,
transparent) has its `<name>.svg` source beside it.

Re-render after changing a drawing:

```bash
python3 tools/gen_ui_art.py economy         # all the economy icons below (2026-09-28)
python3 tools/gen_ui_art.py cases           # a group: column, cases, packs, shop_icons, cue_layers
python3 tools/gen_ui_art.py shop case_rare  # or just the ones named
python3 tools/gen_ui_art.py                 # everything, including assets/ui/art (rewrites all)
```

Upload the PNGs, then put each id in `Config.UI.Kit.Icons` (the key in the second column) and
in the table below.

## Match and menus (before the economy)

| File | Config key | What it is, where it is used | Roblox id |
|---|---|---|---|
| `cue.png` | Cue | a cue and ball: your turn, aiming, Shoot | 116758585284705 |
| `hourglass.png` | Hourglass | someone else's turn | 96213788446334 |
| `stopwatch.png` | Stopwatch | the shot clock | 74222974804673 |
| `whistle.png` | Whistle | a foul | 123711745342070 |
| `crown.png` | Crown | the host | 88932863469480 |
| `people.png` | People | how many are in | 126967121282359 |
| `person.png` | Person | Play solo | 134579193841579 |
| `robot.png` | Robot | Play against PC | 118948986409177 |
| `play.png` | Play | Start | 87915961490645 |
| `door.png` | Door | Leave | 108459063618521 |
| `flag.png` | Flag | surrender, and a draw | 121800890987382 |
| `trophy.png` | Trophy | a win | 133568661073411 |
| `sad.png` | Sad | a loss | 83322300789151 |
| `coin.png` | Coin | the coin flip (never money) | 94354793241176 |
| `hand.png` | Hand | ball in hand | 98407510851293 |
| `target.png` | Target | choose a pocket | 101004180917014 |
| `rolling.png` | Rolling | balls moving | 117937533191868 |
| `lightning.png` | Lightning | abilities | 79533357402482 |
| `check.png` | Check | ready, even split | 102199824142465 |
| `x.png` | X | a pocketed ball, a wrong target | 114855661740318 |
| `arrow.png` | Arrow | points right; turned for the others | 135119886891841 |
| `chevron_right.png` | ChevronRight | the roadmap's > button | 83677689417587 |
| `chevron_left.png` | ChevronLeft | the roadmap's < button | 139144449776506 |
| `chevron_up.png` | ChevronUp | the controller guide's arrows by a stick | 86978612733332 |
| `chevron_down.png` | ChevronDown | the controller guide's arrows by a stick | 133654278514766 |
| `sliders.png` | Sliders | fine controls (removed from the game) | 72906258640929 |
| `level_classic.png` | Classic | difficulty: every line | 77520789288930 |
| `level_difficult.png` | Difficult | difficulty: the aim line only | 96329200527250 |
| `level_challenger.png` | Challenger | difficulty: no lines | 111544414092808 |
| `money.png` | (none) | the old flat cash icon, replaced by `cash_stack` | 73979676771161 |
| `cash_stack.png` | Money, CashStack | three bundles: money everywhere, the money HUD | 140297726302884 |
| `cash_single.png` | CashSingle | one bundle: the flying "+$10" chip | 120556642167836 |
| `chat_tag.png` | ChatTag | a speech bubble: the chat-tag reward tile | 108097317615793 |
| `scroll_zoom.png` | ScrollZoom | the zoom guide on a computer: a mouse wheel | 76220420219490 |
| `pinch_zoom.png` | PinchZoom | the zoom guide on touch: a pinching hand | 115866473257495 |

## The economy (2026-09-28)

| File | Config key | What it is, where it is used | Roblox id |
|---|---|---|---|
| `case.png` | Case | the generic case (the Standard chest), the roadmap's reward tile. redrawn 2026-09-28 (the old placeholder was 123526196779472) | 119138673224082 |
| `shop.png` | Shop | the left column: a red shopping basket with a white rim and handle | 107658760787268 |
| `inventory.png` | Inventory | the left column: an orange backpack | 105879289234800 |
| `rewards.png` | Rewards | the left column: a pink gift box with a gold ribbon and bow | 92894769753979 |
| `trade.png` | Trade | the left column: two fat arrows swapping, blue and orange | 98977101809699 |
| `case_standard.png` | CaseStandard | the Standard case: the chest after reference 07 in pale steel grey | 119138673224082 |
| `case_rare.png` | CaseRare | the Rare case: the chest in strong blue | 121070015585025 |
| `case_epic.png` | CaseEpic | the Epic case: the chest in purple | 86949000248568 |
| `case_legendary.png` | CaseLegendary | the Legendary case: the chest in gold, with two twinkles | 115568776906467 |
| `case_event.png` | CaseEvent | the Event case: the chest in pink | 102627378767988 |
| `pack_1.png` | Pack1 | money pack 1 (smallest): one bundle | 104093005133758 |
| `pack_2.png` | Pack2 | money pack 2: a small stack of three bundles | 107106986765797 |
| `pack_3.png` | Pack3 | money pack 3: a tall stack and a shorter one in front | 78352765658351 |
| `pack_4.png` | Pack4 | money pack 4: an open brown briefcase heaped with cash | 78298939867579 |
| `pack_5.png` | Pack5 | money pack 5: a steel safe with a vault wheel, cash in front | 79088631223048 |
| `pack_6.png` | Pack6 | money pack 6: three gold bars and a stack of cash | 75989511488683 |
| `pack_7.png` | Pack7 | money pack 7 (biggest): a heap of cash in a golden glow with twinkles | 70683561627175 |
| `vip.png` | Vip | VIP: a gold crown with gems in the house rainbow (bold, never pastel, never Mythic) | 114618538604206 |
| `starter_pack.png` | StarterPack | the starter pack: a blue gift box with a cue standing out of it | 112625803604762 |
| `money_party.png` | MoneyParty | money party: a party popper bursting with bills, streamers and dots | 70489851952209 |
| `fast_open.png` | FastOpen | fast open: a case chest with a big lightning bolt | 119005216671556 |
| `limited.png` | Limited | a limited item: a red ticket with a gold star and a # on its stub | 105313592367901 |
| `calendar.png` | Calendar | the daily streak: a calendar page, done days ticked, today a flame | 81931904688937 |
| `code.png` | Code | promo codes: a purple card with a dark slot of hidden letters (after reference 06) | 139681599835662 |
| `index.png` | Index | the Index tab: a green book with gold corners and a cue on its cover | 94908077553080 |
| `sell.png` | Sell | selling: a gold price tag on a string with a bill on it | 106552564585529 |
| `lock.png` | Lock | locked: a gold padlock (Exclusive and Unique cues, locked things) | 106188433501601 |
| `odds.png` | Odds | optional: the drop odds, a pie in the rarity colours with the rarest slice pulled out | 116548417104330 |

## Cue thumbnail layers (CueThumb)

One chunky cue, butt bottom-left and tip top-right at 45 degrees, split into layers that all share
the same 256 px canvas and line up exactly. Stack them in one frame in this order, bottom to top.
The white layers are pure white (every shade lives in `cue_outline` and `cue_gloss`), so tinting
one with `ImageColor3` gives exactly that colour. The segments follow `Catalog.style`'s
proportions (tip 0.015, ferrule 0.02, shaft 0.48, joint 0.025, forearm 0.22 with a 0.04 accent in
its middle, ring 0.015, wrap 0.17, cap 0.055, tapering from 0.42 of the butt's width at the tip),
except that the tip, ferrule, joint and ring are drawn a little longer (taken out of the shaft) so
they still show at 64 px.

| Order | File | Config key | Tint | What it is | Roblox id |
|---|---|---|---|---|---|
| 1 | `cue_outline.png` | CueOutline | none | the ink outline with its lip, a soft drop shadow, and the **ferrule** already painted in Catalog's fixed ferrule colour (242, 238, 226), since every cue has the same one || 79236419588604 |
| 2 | `cue_shaft.png` | CueShaft | Look.Shaft | the shaft, white || 103302145306091 |
| 3 | `cue_tip.png` | CueTip | Look.Tip | the leather tip, white || 139935284491020 |
| 4 | `cue_ring.png` | CueRing | Look.Ring | the joint collar and the ring between forearm and wrap, white || 83061685733531 |
| 5 | `cue_forearm.png` | CueForearm | Look.Forearm | the whole forearm, white (the accent sits over its middle) || 126056531698047 |
| 6 | `cue_accent.png` | CueAccent | Look.Accent | a band in the middle of the forearm, white; leave it out when the look has no accent || 91223791753924 |
| 5-6 alt | `cue_rainbow.png` | CueRainbow | none | the forearm pre-coloured in the house rainbow (red to purple, tip to butt); used instead of the forearm and accent for Look.Rainbow cues (VIP, Reyes) || 99026288213964 |
| 7 | `cue_wrap.png` | CueWrap | Look.Wrap | the wrap, white || 115386170032197 |
| 8 | `cue_cap.png` | CueCap | Look.Cap (or the wrap at 0.6) | the butt cap with its rounded end, white || 93663666480532 |
| 9 | `cue_gloss.png` | CueGloss | none | on top: a white shine along the lit side, a soft shade along the far side, and a thin ink line between each part (hides any seam between two tinted layers) || 80942448683389 |
| alone | `cue_silhouette.png` | CueSilhouette | none | the whole cue as one flat dark slate shape with the outline and shadow: the Index's unowned cues || 116727821385649 |

## GUI lane icons (2026-10-03)

Made with `tools/openai_image.py` in the kit's sticker style (existing icons as style references,
transparent background, no words), trimmed and padded to 256 px; the 1024 px raws stay local in
`raw/` (not in git). Uploaded to the group; the Roblox ids are the image ids in Config.

| File | Config key | What it is | Roblox id |
|---|---|---|---|
| `shop_basket.png` | Shop, ShopBasket | the Shop: a glossy red basket with a silver handle (ref 02) | 130453738066274 |
| `deals.png` | Deals | a price tag with a star burst: the Deals jump button | 127731721548070 |
| `cases_jump.png` | CasesJump | two stacked cases: the Cases jump button | 138027148960139 |
| `passes.png` | Passes | a golden ticket: the Passes jump button | 93981799998814 |
| `mystery_case.png` | MysteryCase | a purple case with a question mark | 108447374917770 |
| `restock.png` | Restock | a refresh arrow round a chest | 75423782122752 |
| `roblox_plus.png` | RobloxPlus | a gold badge with a plus | 132944105986264 |
| `gift.png` | Gift | the Free Reward gift | 120885254928899 |
| `group.png` | Group | three busts: join the group | 98530804278165 |
| `invite.png` | Invite | an envelope with a plus | 121644690849571 |
| `star.png` | Star | the favorite star | 125192913454809 |
| `daily_target.png` | Challenge | the Daily Challenge target | 127346327357150 |
| `gear.png` | Gear | Settings | 125677637012120 |
| `thank_you.png` | Heart | a heart with sparkles: the thank-you burst | 93822415051422 |
| `magic_ball.png` | MagicBall | the Case Drop's magic 8-ball, front with the 8 (512 px) | 137828587348917 |
| `magic_ball_window.png` | MagicBallWindow | the same ball turned to its empty blue answer window (512 px) | 98157748117655 |
| `magic_triangle.png` | MagicTriangle | a white down-pointing die triangle, tinted in code (512 px) | 78612448466823 |
| `hand_pointer.png` | HandPointer | a white cartoon hand pointing up: the shake hint (512 px) | 100619983981739 |

`tools/products_icons.json` maps every pass and developer product to its icon here or above;
`python3 tools/roblox_products.py --icons` sets them on Roblox.
