# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-07.

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-06):** lint OK with four old LocalShadow warnings (TableService,
  PadGuide, MatchHUD, Main.client); all 1016 Lune tests pass.
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
  results and NEW RANK! blur the world (`ScreenBlur`, `Config.UI.Blur`); the reel waits 0.15 s
  for the blur. NEW RANK! also darkens (it stacks on the results). Seen in Studio on the
  menus, the reel and NEW RANK! alone; NEW RANK! over a real result not yet.
- **The 1v1 result cutscene** is the fade to black and the pan down onto the table only; the
  posed winner and loser are off (`Config.Cutscenes.Result.Posed`, 2026-10-06).
- **Cue outlines and the "pop" aura.** Every cue has a theme-coloured outline (a moving
  gradient from Legendary up). The deeper aura is on test on Frostbite, Candy, Flare, Plasma,
  Gummy and Magma (`Config.CueSkins.Pop.Ids`).
- **Ball callouts** (2026-10-06): your own group pulses bright green with YOU ARE SOLIDS /
  STRIPES, and a team's last ball pulses green once per game as a warning; 4 pulses of 2 s
  each (`Config.Multiplayer.Style.BallPulse`). Seen in Studio from the QA hook; not yet in a real
  game played out by hand.
- **No fat-fingered shots on a phone** (2026-10-06): a dead zone at the top of the pull, a
  click-in bump, sideways drags and very short presses never shoot (`Config.Input.TouchPull`).
  Checked in the Studio phone emulator (wobble, sideways, a soft 8% shot); the 0.15 s rule and
  the feel need a real phone.
- **Quick fixes (2026-10-06):** the phone's power bar stays inside the safe area; any raised
  cue (chosen or lifted over a rail) has every effect off; 1v1 tables are blue cloth
  (`BlueWood`, lives in the place: save and publish); no money "+" during a game.
- **The player list like Roblox's** (2026-10-07): top-right corner in the top bar row, the
  Shop's lively header, badge + name, Wins, Money, no tabs, each person in a box; folded at
  first (remembers being left open), **not shown on a phone for now**. On a phone the rank HUD
  and the gear sit in line with Roblox's buttons; on a computer or tablet the HUD is bigger and
  its badge bigger still. The red "!" stays on screen.
  A phone's lucky block hotbar shows only slots 1-3 (the rest in the bag). Seen in the Studio
  phone and iPad emulators; a PC size not yet looked at.
- **The matchmaking bar** (2026-10-07, look A; a small piece under the lively-gui skill, at
  **gate D, Studio first look**): one slim bar above the hotbar replaces the pad card. The
  server sends "<name> needs an opponent!" on step-on when no Roblox friend is in the server;
  Play Global shows after 3 s (5 s with a friend), searching shows the time and a red X, and a
  1v1 meets a bot at 5 s. Lobby tables play Classic; solo, vs PC and Fill with PC are off the
  pad for now; lobby bots no longer answer requests; the tutorial needs no button press.
  Checked in the Studio phone emulator: every state (GuiQA "matchbar"), the auto-request and
  its 15 s cooldown, 3 s vs 5 s, Play Global to the bot match, the X, Y focus, tutorial games 1
  and 2. Not yet: a PC size, a real gamepad's A and B, a real friend in a live server.
- **Lighting.** Day 10 min, sunset 5 min, a 10 s fade; no night and no sun disc. The sunset
  was softened and made less yellow on 2026-10-05.
- **Pull cutscenes.** Rare, Epic and Legendary are redone ("good for now"); Mythic and Secret
  still wait for their redo (DECISIONS.md 2026-10-05 has the notes for them).

## Open, waiting on the designer

- **Abilities review:** going one by one since 2026-09-30 (Magnet first). Abilities not yet
  reviewed are provisional.
- **The lively Shop is done** and merged into `release` (2026-10-06, from `shop-lively`),
  all five gates approved (`docs/prompts/SHOP_LIVELY_REPORT.md`). Next: the Shop's Blocks,
  Money and Passes pages with the `lively-gui` skill (the money "+" jumps to Money, which has
  no page yet). Other menus switch to the new frame one at a time as each is rebuilt. Save
  `place/8ball.rbxl` and publish once for this milestone (the renamed Firework Cue instances).
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
