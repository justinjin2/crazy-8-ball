# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-06.

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-06):** lint OK with four old LocalShadow warnings (TableService,
  PadGuide, MatchHUD, Main.client); all 990 Lune tests pass.
- **In the game:** server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3
  and solo; the global queue and arena with rematch; bots (ten tiers, Play against PC, lobby
  bots, disguised bots); ranks (XP only from winning) and money; saves at version 7;
  13 abilities (Ultimates) with the spin screen; cue skins with VFX and outlines; lucky blocks
  as the only gacha (cases, the Magic 8 Ball and reward popups are gone); Rewards, Inventory
  (Cues, Index), trading, settings, our own player list and boards; the first-time tutorial;
  the rooftop map with a day and sunset cycle; pull cutscenes Rare to Legendary.

## Being tried right now (the designer's look, nothing final)

- **The UI font.** Fredoka One stays the kit font. `Config.UI.FontTest` tries a font on one
  screen or all of them; the left column's words have their own `Config.UI.Menu.LabelFont`.
  Every outlined text has a thick ink lip under its letters, and from a 2 px outline up
  (text from 20 px) solid ink holes (`HoleFill`, `Config.UI.Kit.HoleFill`).
- **Blur instead of dims** (2026-10-06): menus, the roadmap, the lucky block reel, the match
  results and NEW RANK! blur the world (`ScreenBlur`, `Config.UI.Blur`). Seen in Studio on the
  menus; the reel, results and NEW RANK! not yet watched live.
- **Cue outlines and the "pop" aura.** Every cue has a theme-coloured outline (a moving
  gradient from Legendary up). The deeper aura is on test on Frostbite, Candy, Flare, Plasma,
  Gummy and Magma (`Config.CueSkins.Pop.Ids`).
- **Lighting.** Day 10 min, sunset 5 min, a 10 s fade; no night and no sun disc. The sunset
  was softened and made less yellow on 2026-10-05.
- **Pull cutscenes.** Rare, Epic and Legendary are redone ("good for now"); Mythic and Secret
  still wait for their redo (DECISIONS.md 2026-10-05 has the notes for them).

## Open, waiting on the designer

- **Abilities review:** going one by one since 2026-09-30 (Magnet first). Abilities not yet
  reviewed are provisional.
- **The Shop is empty** after the cases were retired (frame, background, the four section
  buttons; the server-side shop, receipts and restock still work). `docs/ECONOMY.md` is the
  spec for its overhaul.
- **Decisions still open:** trim Epic ownership (6.7% of active players against a ~5% plan)
  or keep it; whether the VIP cue pays finder's money on the first join; whether the free
  Mystery block keeps its 5-minute timer (`Config.LuckyBlocks.Kinds.Mystery.Timer`).
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
- Sounds by ear (the levels were measured, not listened to).
- The analytics funnels in the Creator Dashboard (roadmap 8.2).

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test.Refill` tops the designer's hotbar up in Studio and can hide a
  tutorial test's real blocks.
