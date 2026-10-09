# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-08.

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-08, `abilities-rework`):** lint OK with three old LocalShadow
  warnings (PadGuide, MatchHUD, Main.client); all 1066 Lune tests pass.
- **In the game:** server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3
  and solo; the global queue and arena with rematch; bots (ten tiers, Play against PC, lobby
  bots, disguised bots); ranks (XP only from winning) and money; saves at version 7;
  13 abilities (Ultimates) with the spin screen; cue skins with VFX and outlines; lucky blocks
  as the only gacha (cases, the Magic 8 Ball and reward popups are gone); Rewards, Cues (My Cues,
  Index; the Inventory renamed), trading, settings, our own player list and boards; the first-time tutorial;
  the rooftop map with a day and sunset cycle; pull cutscenes Rare to Legendary.

## Being tried right now (the designer's look, nothing final)

One line each; the long form is the 2026-10-08 entry at the top of
`docs/archive/STATUS_HISTORY.md`. Each still needs the designer on a real phone, PC and controller.

- **The UI font**: Fredoka One stays (`Config.UI.FontTest`, `Config.UI.Menu.LabelFont`).
- **Blur instead of dims** (`ScreenBlur`, `Config.UI.Blur`).
- **NEW RANK! waits** for a free lobby, one popup per division; not yet a real arena trip back.
- **The 1v1 result cutscene** and the result screen's moving 8-balls; not yet in a real 1v1.
- **Cue outlines and the "pop" aura** (on test on six cues, `Config.CueSkins.Pop.Ids`).
- **New cue card pictures** (2026-10-07): uploaded, not yet seen in a playtest.
- **Ball callouts** (YOU ARE SOLIDS / STRIPES, the last-ball pulse): not yet in a real game.
- **No fat-fingered shots on a phone** (`Config.Input.TouchPull`): needs a real phone.
- **The player list like Roblox's**: hidden on a phone for now; a PC size not yet looked at.
- **The matchmaking bar and spawn pill**: parked by the designer (2026-10-07); open: the spawn
  pill's 20 s, Play Global's X on a phone.
- **The queue portal**: not yet on a phone, a gamepad or during a real game.
- **Lighting**: day 10 min, sunset 5 min, no night. **Pull cutscenes**: Mythic and Secret wait
  for their redo.
- **Our own lucky blocks** (all 12 kinds, 2D icons), **the Gift drop** (`/giftdrop`; a test
  Gift waits in the designer's Studio save) and **the Mystery block's upgrade screen**: not yet
  on a phone, a controller or at full frame rate.
- **The pull bar's cue**, drawn shorter: not yet seen in a match.

## Open, waiting on the designer

- **The GUI redo** (2026-10-08, `docs/prompts/CUES_LIVELY_PROMPT.md`, branch `shop-lively`),
  **paused by the designer** for the economy plan (a cheaper, more balanced economy); the
  designer continues the other lively GUIs from another session. Built and checked in Studio:
  the new cue card (the rank cues are the Ranked rarity), the Cues menu (My Cues and Index
  tiles, Sort, Sell dupes, the big card, the Equip sound), the striking CUES icon, the money
  chip flying smoothly into the cash icon (it was drawn only every other frame, fixed), the
  lucky block reel and YOU GOT with the new card (reel cards still and, on trial, see-through;
  rarer cues show more often on the reel). Still open: the see-through trial's verdict, a phone
  and a gamepad, the numbered card's mark A or B, the copy numbers' own plan, then Free
  Reward, Abilities and Ranked. `shop-lively` is not yet merged into `release`.
- **The abilities rework** (branch `abilities-rework`, not merged;
  `docs/prompts/ABILITIES_REWORK_PLAN.md`): the 13-ability ladder and the designer's second and
  third rounds (2026-10-08). Look Over There! (Rare now) is the sneaky ball in hand with no
  cutscene; Catch-a-Ball (Epic now) catches a second ball (DOUBLE CATCH!); Verity (Rare now)
  turns evil, eats the ball she hits and shoves the rest out of her way; Black Hole and the
  Tiger have no caps. Measured rarity means 0.34 / 0.50 / 0.64 / 0.94 / 1.15 / 1.78. Checked
  in Studio: Verity's act and her two new looks (the plush smiley, the
  creepy face, to the designer's reference images), Catch-a-Ball's leap and both catches (the
  replay now holds each slow-motion moment; a long frame used to skip it). Waiting: the
  designer's hands-on test of the sneak (two players: Studio's Test tab, Clients and Servers),
  their voice lines.
- **Abilities review:** going one by one since 2026-09-30 (Magnet first). Abilities not yet
  reviewed are provisional.
- **The lively Shop is done** and merged into `release` (2026-10-06, from `shop-lively`),
  all five gates approved (`docs/prompts/SHOP_LIVELY_REPORT.md`). Next: the Shop's Blocks,
  Money and Passes pages with the `lively-gui` skill (the money "+" jumps to Money, which has
  no page yet). Other menus switch to the new frame one at a time as each is rebuilt. Save
  `place/8ball.rbxl` and publish once for this milestone (the renamed Firework Cue instances).
- **Decisions still open:** trim Epic ownership (6.7% of active players against a ~5% plan)
  or keep it; whether the VIP cue pays finder's money on the first join.
- **The cue rarity rework** continues after the Unique cues (Beta, Grand Opening, Eclipse,
  Celestial Dragon, Kitsune). Apex's first look was reverted.
- **The place file:** save `place/8ball.rbxl` and publish once this milestone is done (lucky
  block templates and models, Unique cue templates live in the place).

## Not yet checked (the Studio tools cannot do these)

- A real phone and a real controller on everything since the UI redo, including the lucky
  block hold and reel skip, the shop and the pull cutscene skip. Studio's MCP cannot fake a
  gamepad and cannot switch the phone emulator in Play mode.
- Real multiplayer: a two-player block or cue trade, 2v2 and 4-player matches, the global
  queue in the published game (`docs/MULTIPLAYER_TESTING.md`), real Robux purchases.
- Sounds by ear (the levels were measured, not listened to), the new click "boop" included.
- The analytics funnels in the Creator Dashboard (roadmap 8.2).

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test.Refill` tops the designer's hotbar up in Studio and can hide a
  tutorial test's real blocks.
