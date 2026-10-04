# Shop GUI v3 handoff (2026-10-04, from the desktop-app session to the CLI)

You are continuing a run that integrates the designer's new shop GUI into the main game, one
section at a time, straight on branch `release` in `~/Desktop/8ball` (Rojo port 34872). Read
`CLAUDE.md`, `docs/STATUS.md`, `docs/UI_STYLE.md` sections 13 and 14, and this file first.
The designer (Justin, user id 544959133, Painicane) is a beginner: explain steps simply, make
routine calls yourself, interview him only where the reference images leave a real choice.

**Order of work: finish the shop GUI first, section by section. Nothing else until it is done
on PC, phone and gamepad.** Then the block models, then the new developer products, then docs.

## What is done and committed (release)

- `cc7b411` Lucky-block economy data layer: 12 block kinds (`Config.LuckyBlocks`), the deals
  (Grand Opening timed, Mystery always open), 3 rolled restock slots + a VIP slot, the Beta Cue
  guarantee on the 400th Grand Opening open, Unique rerolls, VIP halves block timers and opens
  fast (Quick Cases retired). 984 Lune tests pass (`tools/test.sh`, about 2 min).
- `35f8432` Shop GUI v3: `src/client/ShopBlockCards.luau` (Opening and Mystery bands, Slot
  tiles), `src/client/BlockIcon.luau` (turning 3D block in a ViewportFrame, kit-icon fallback
  while a model is not imported), `ShopPage.luau` sections in `Config.Shop.Order`
  (GrandOpening, Mystery, Restock, Offer, Money, Boosts, RobloxPlus), rail jumps Featured /
  Blocks / Money / Passes, `ShopMenu.luau` build-in from the top left (`Config.UI.Shop.Page.
  Build`), idle shimmer and icon pops (`Shimmer`, `IconPop`), BuyBlocks requests, a gold "+"
  candy on the money HUD (`MoneyHud.luau`) that opens the Shop on the Money tab.
- `274b046` Starter Pack and VIP as two "Pass" bands side by side (`shape = "Pass"` in
  ShopBlockCards): art left, title / big number / line, odds pills (Secret with a rainbow rim)
  or VIP's six-perk list in two columns, timer or LAUNCH SALE ribbon + crossed price bottom
  left, button bottom right, cream VIP card. Matches reference image 14 below.

Verified in Studio play (PC window only): every section draws with no console errors, the "+"
lands on the Money header, the Grand Opening band shows when the deal is open, the VIP band in
both the owned and the not-owned state. Lint is clean (`tools/lint.sh`, four old LocalShadow
warnings elsewhere are known).

Uncommitted and to leave alone: `place/8ball.rbxl` (Studio saved it) and
`assets/cue/concepts/openai_log.jsonl` (image tool log). Do not commit either unless asked.

## The reference images (use these, not the ChatGPT result sheets)

All the images the designer pasted into the previous session are saved in
`~/Desktop/8ball-refs/gui-v3/pasted/` (saved by the tool, numbered in paste order):

| File | What it is |
| --- | --- |
| `12-...webp` | **Grand Opening hero band**: block with crown + NEW sticker + "Ends in" at left, rainbow "GRAND OPENING LUCKY BLOCK" title with stars, "YOU COULD PULL...", two chase cards (Beta Cue 0.3%, Grand Opening Cue 3%, UNIQUE / LIMITED pills, cue art, dark fill, pink rim), three columns 1 / 3 / 10 blocks: green Robux button ("1 block · 49", crossed old price beside), gold money button under it, "save 12%" / "save 29%" notes. Dark navy festive background with fireworks and confetti inside the band. |
| `13-...webp` | **Mystery block band** ("LUCKY BLOCKS" header): "Always in stock" pill, title, subtitle "Opens into one of the six blocks below · 5 min timer when won, instant when bought", odds rows **with a mini block icon per row** and the kind's name in its colour, "Epic cue or better" line, x1 / x10 columns (gold money button on top, green Robux under, "-30% SALE" sticker on the x10 column). |
| `14-...webp` | **Starter Pack + VIP bands** (done, keep as the reference when polishing). |
| `15-...webp` | **Money row and Passes**: money packs with "FIRST BUY x2" pill and red "-30%" corner ribbons, crossed Robux prices; Passes as wide tiles with the art at the left and the name + line at the right (Money Party, Ability Slot 2, Ability Slot 3, Roblox Plus "+10% money and a tag", "Get"). |
| `16-...png` | **Rail buttons**: Deals (NEW), Blocks (NEW), Money, Passes. The designer's message said the tabs are Featured, Blocks, Money, Passes; the picture says "Deals". Ask him which word. |
| `07-...webp` | Studio screenshot of the GoldMajestic block (Legendary) from the bought pack. |
| `08-...png` | Sky block: DiamondGhost recoloured a lighter baby blue, white wings. |
| `09-...png` | Mythic: pastel rainbow painted block (plus a cycling aura in game). |
| `10-...png` | Lucky 8: black cube, white "8" discs on the faces, silver rims. |
| `11-...png` | Starter block: Standard reskinned red with a gold gift tie. |
| `01` to `05` | The earlier references the hero prompt was built from; `06` the hero result the designer called "close enough". |

The ChatGPT sheets in `~/Desktop/GUI-refs/results/` (P3 to P23) were only the prompt pipeline's
output; the designer does not want the shop built from them. More references may be pasted
later: copy any new one into `~/Desktop/8ball-refs/gui-v3/pasted/` with the next number
(memory rule: save refs yourself, do not ask).

## Shop GUI: what is left, in order

1. **Phone and gamepad.** Not checked yet. Use Studio's device emulator (the designer switches
   it, or ask him to), or the Edit-mode preview recipe in `docs/STUDIO_NOTES.md` ("Edit-mode
   previews of the screens"). The Pass bands must stack to one column on a phone
   (`Config.UI.Shop.Page.Block.PassMinPx`); check the odds pills wrap and the restock tiles.
   Gamepad: every button reachable, a jump lands on the section's first button.
2. **Grand Opening band to reference 12**: the dark festive fill inside the band, the crossed
   old price beside the Robux button, money buttons gold (money = gold candy, Robux = green,
   as in the references), the NEW sticker on the art side, the timer under the art.
3. **Mystery band to reference 13**: mini block icons (BlockIcon, small) and coloured kind
   names in the odds rows, the subtitle words, the x10 sale sticker on the column, money
   button above the Robux button.
4. **Money row to reference 15**: "FIRST BUY x2" pill, "-30%" corner ribbons, crossed prices.
5. **Passes to reference 15**: wide tiles (art left, words right), Roblox Plus "Get" tile back
   in (it was dropped from the page while folding Starter + VIP into Passes; the Passes jump
   is `Config.UI.Shop.Page.Jump` = Offer, Boosts, RobloxPlus).
6. **Section per screen**: each section about one screen tall with a bit of the next visible
   (the designer's words); tune `Config.UI.Shop.Page` sizes.
7. **Mythic client aura** (cycling rainbow) on its block icon; hotbar icons for the new kinds.
8. Rail word: Featured or Deals (ask, reference 16).

Every tunable number goes in `src/shared/Config.luau` with a comment, every word in
`src/shared/Strings.luau`. Scripts only under `src/` (never through the Studio MCP). Commit on
`release` as soon as a step is verified, without asking. Then `docs/STATUS.md`,
`docs/DECISIONS.md` (dated lines for every design call), `docs/UI_STYLE.md` (add a section 15:
shop v3 block cards, pass bands, build-in, the "+" on the HUD).

## After the shop GUI (do not start until the shop is done)

- **Block models** (Edit mode, Studio tools allowed): `assets/luckyblocks/Readme.md` has the
  import recipe (`tools/studio_relay.py` + `execute_luau`). Models already extracted in
  `assets/luckyblocks/models/`: GoldMajestic (Legendary), DiamondGhost (Sky), GoldTitan
  (Mythic). Colormaps ready in `assets/luckyblocks/textures/`: `sky_colormap.png`,
  `mythic_colormap.png`, `mystery_colormap.png`, `starter_colormap.png`, `lucky8_face.png`.
  **Ask before any upload** (`tools/roblox_upload.py`, group 675425213, key `ROBLOX_API_KEY`
  in Keychain, never print it): the 4 colormaps, the lucky8 decal, and
  `anims/GoldMajesticLuckyBlockIdle.rbxm`. Then set the ColorMap on the imported clones, build
  the Lucky 8 part cube (black, silver rims, "8" decals, code bob), set `Idle` ids in
  `Config.LuckyBlocks.Kinds`, LuckyWorld bob for `Bob` kinds. Gift kind: no model yet (assumed
  the Starter block as a placeholder; flag it).
- **Developer products** through Open Cloud (ask first): GrandOpening1 / 3 / 10 (49 / 129 /
  349 R$), RestockRare (99 R$); then remove the `pending` list in `tests/shop_test.luau`.
  The designer changes the VIP pass price to 499 in Creator Hub himself.
- `docs/ECONOMY.md`: the new odds numbers (Config.Cases) and the block table.

## Studio recipes that work (and the traps)

- Studio id `4ed02ec1-d685-4844-8a3b-fcd877e6fc4f` (`list_roblox_studios` if it changed).
  Rojo is serving `default.project.json` on 34872; the plugin is connected.
- `execute_luau` requires modules into **its own VM**: `require(Items).setLimitedWindow(...)`
  there does nothing to the running game. Use the Studio hooks instead:
  - Server: `game.ServerStorage.DevCommandsQA:Invoke(544959133, "/limited start 30240")` opens
    the Grand Opening deal and the release sale for 21 days; `/vip off` and `/vip on` fake the
    pass for the session; `/giveblock <kind>`, `/money`, `/restock` exist too.
  - Client: `game.Players.LocalPlayer.PlayerScripts.GuiQA:Invoke("open", "Shop", "Money")`,
    `("close")`, `("list")`.
  - The "+" on the HUD: `user_mouse_input` with
    `instance_path = "LocalPlayer.PlayerGui.PoolHud.MoneyHud.Plus"`.
  - Scroll the page: the ScrollingFrame under `PlayerGui.ShopMenu`; headers are
    `HeaderGrandOpening`, `HeaderMystery`, `HeaderRestock`, `HeaderOffer`, `HeaderMoney`,
    `HeaderBoosts`; set `CanvasPosition` then `screen_capture`.
- Module edits need a play restart (`start_stop_play` false then true, wait ~4 s for the
  player, then run the server hook again).
- A tab jump must clamp in layout units, not Absolute sizes: the frame's pop-in UIScale
  shrinks them (fixed in `ShopMenu.jump`; keep it that way).
- Tests: run `tools/test.sh > <scratch>/test.log 2>&1; echo DONE >> <scratch>/test.log` in the
  background and poll with `until grep -q DONE`. Foreground `sleep` is blocked.
