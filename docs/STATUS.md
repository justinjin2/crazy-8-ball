# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-10 (tutorial v2 closed and in `gui-v4`; work goes on in `~/Desktop/8ball`).

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-10, branch `tutorial-v2` with `gui-v4` merged in):** lint OK (three
  old LocalShadow warnings); all 1185 Lune tests pass.
- **In the game:** server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3
  and solo; the global queue and arena with rematch; bots (ten tiers, Play against PC, lobby
  bots, disguised bots); ranks (XP only from winning) and money; economy v5.1 and its screens
  (on `gui-v4`); saves at version 11;
  13 abilities (Ultimates) with the spin screen; cue skins with VFX and outlines; lucky blocks
  as the only gacha (cases, the Magic 8 Ball and reward popups are gone); the Free Reward menu
  (daily, playtime, the 28-day track, group and invites), Cues (My Cues, Index; the Inventory renamed), trading, settings, our own player list and boards; the first-time tutorial;
  the rooftop map with a day and sunset cycle; pull cutscenes Rare to Legendary; the ball streak.

## Being tried right now (the designer's look, nothing final)

One line each; the long form is the 2026-10-08 entry at the top of
`docs/archive/STATUS_HISTORY.md`. Each still needs the designer on a real phone, PC and controller.

- **Fredoka One** stays (`Config.UI.FontTest`); **blur, not dims**; **NEW RANK! waits** for a
  free lobby (not yet a real arena trip back); **the 1v1 result cutscene**: not yet a real 1v1.
- **Cue outlines and the "pop" aura** (six cues, `Config.CueSkins.Pop.Ids`), **new cue card
  pictures** and **ball callouts** and the shorter pull-bar cue: not yet seen in a real game.
- **No fat-fingered shots on a phone** (`Config.Input.TouchPull`): needs a real phone.
- **The player list like Roblox's**: hidden on a phone for now; a PC size not yet looked at.
- **The matchmaking bar and spawn pill**: parked by the designer (2026-10-07); open: the spawn
  pill's 20 s, Play Global's X on a phone. **The queue portal**: not yet on a phone or gamepad.
- **The ball streak** (2026-10-09; GDD 8, UI_STYLE 28, ECONOMY 3.1): STREAK x1 to x8 in the popup
  row, low flames, YOUR TURN only for a new shooter; on a phone only from a drop to the next
  turn; checked in Studio and on an iPhone; a tablet check is next.
- **The coin flip's player tokens** (2026-10-09): a headshot each side, no heads or tails;
  **phone letterbox bars** cover most of the HUD's edge rows; **the Mystery screen** without
  its two lines, a bigger block. Checked in Studio's phone emulator; not yet on a real phone.
- **Lighting**: day 10 min, sunset 5 min. **Pull cutscenes**: Mythic and Secret wait a redo.
- **Our own lucky blocks** (all 12 kinds, 2D icons), **the Gift drop** (`/giftdrop`; a test
  Gift waits in the designer's Studio save) and **the Mystery block's upgrade screen**: not yet
  on a phone, a controller or at full frame rate.

## Open, waiting on the designer

- **Daily rewards rework on `gui-v4`** (2026-10-10, DECISIONS): one thing a day, the Week One
  Cue only for 7 days in a row (else an Epic block), Claim All 499 / 449 / 399 and 99 / 79 / 49
  R$ (synced), playtime $7,500 a day, VIP's daily Mystery block, the restock without its odds
  line and sorted by rarity, the rank HUD's phone label. Lint and tests pass. Open: the
  designer's look in Studio on phone, PC and controller.
- **Economy v5.1 "Lively" on `gui-v4`** (approved 2026-10-09 evening; plan section 15): a
  Mystery turns into a real block (its roll 30 / 25 / 10 / 5%) that then climbs; $19,900 / 9 R$
  (synced on Roblox); the 15-minute gift $2,000; pity counts the final cue. Screenshots for the
  designer's OK in `~/Desktop/8ball-refs/economy-v5-gui/v5.1`. Open: that OK; the tutorial
  session's scripted first Mystery (hand-off lines in DECISIONS.md).
- **Economy v5.2 on `gui-v4`** (designer, 2026-10-09: only the Mystery has upgrade chances):
  every other block waits its own name's timer and climbs as it opens, the reel showing that
  climb's odds (a Rare block: Rare 8.2% and Epic 1.8% cards); the odds are unchanged. "Open
  all" reels any Standard or Uncommon block that climbed to Rare or better. Checked in Studio on
  PC (a Rare block gave an Epic cue through the reel). Open: phone and gamepad; live servers
  need "Restart Servers for Updates" after the publish.
- **The Grand Opening soft launch is on** (2026-10-09, `Deals.GrandOpening.SoftLaunch`): money
  and Robux, no end date, no luck, no launch bonus. For the release: set `StartsAt`.
- **Economy v5 and its screens on `gui-v4`** (2026-10-09; `docs/prompts/ECONOMY_V5_PLAN.md`,
  roadmap 7.9). The GUI run (`docs/prompts/ECONOMY_V5_GUI_PROMPT.md`, its Notes say what each
  step built) updated every screen and checked each on PC; screenshots for review in
  `~/Desktop/8ball-refs/economy-v5-gui/step2` .. `step13`. The `tutorial-v2` merge is in
  (step 12, c3ee723; checked on PC). "Open all" is removed (designer, 2026-10-10; it showed
  during the tutorial's Place step). Still open, in order: phone and gamepad checks with the designer
  (step 13); the release (step 15): place saved and published, the Grand
  Opening's `StartsAt` (also starts the luck and launch bonus), random-item products Not Listed,
  `tools/roblox_products.py --sync` (Starter Pack 19 R$ on Roblox, Config 29; Lucky1 and Lucky3
  off sale). This account sees Robux prices at about 0.8x (regional pricing). Lucky Shot, Golden
  Shot, Lucky Rain and the stay bonus are planned only. Backup: `before-economy-v5`.
- **The GUI hand-off after economy v4** (2026-10-08, branch `gui-v4`; the designer's picks on
  https://claude.ai/artifact/Q79pcvwxeos8AB7o8357Lw, prompts and pictures in
  `~/Desktop/8ball-refs/gui-mocks-v4`): its screens are done and checked in Studio on PC (the
  list moved to `docs/archive/STATUS_HISTORY.md`, 2026-10-09); still to see on a phone, a
  controller and with a real purchase. Trade is not built (not in the release).
- **The Cues redo** (2026-10-08, `docs/prompts/CUES_LIVELY_PROMPT.md`, on `shop-lively`, in
  `gui-v4`): the new cue card, the Cues menu, the CUES icon, the smooth money chip, the reel and
  YOU GOT, checked in Studio. Still open: the see-through reel trial's verdict, a phone and a
  gamepad, the numbered card's mark A or B, the copy numbers' own plan. `shop-lively` is not
  yet merged into `release`.
- **The abilities rework** (in `gui-v4` since 2026-10-08, `docs/prompts/ABILITIES_REWORK_PLAN.md`;
  the abilities themselves are in GDD and ECONOMY): not yet checked on phone and controller,
  the sounds by ear, the tutorial spin's reveal, the sneak with two players, the designer's
  voice lines. The one-by-one review (since 2026-09-30) goes on; unreviewed ones are provisional.
- **The lively Shop** is in `release` (2026-10-06); other menus take its frame as rebuilt.
- **Decision still open:** whether the VIP cue pays finder's money on the first join.
- **Tutorial v2: approved and closed** (2026-10-10; in `gui-v4`; `docs/prompts/TUTORIAL_V2_REPORT.md`,
  its last section lists what is open). Still open: the first session's money rescale
  (`8ball-0d`, hand-off section 3a), a real phone and controller, two-player paths, Max
  Players, the funnels in the dashboard. "Open all" is removed (designer, 2026-10-10).
- **The cue rarity rework** continues after the Unique cues (Beta, Grand Opening, Eclipse,
  Celestial Dragon, Kitsune). Apex's first look was reverted.
- **The place file:** save `place/8ball.rbxl` and publish once this milestone is done.

## Not yet checked (the Studio tools cannot do these)

- A real phone and a real controller on everything since the UI redo, including the lucky
  block hold and reel skip, the shop and the pull cutscene skip. Studio's MCP cannot fake a
  gamepad and cannot switch the phone emulator in Play mode.
- Real multiplayer: a two-player block or cue trade, 2v2 and 4-player matches, the global
  queue in the published game (`docs/MULTIPLAYER_TESTING.md`), real Robux purchases.
- Sounds by ear (the levels were measured, not listened to), the new click "boop" included.
- The analytics funnels in the Creator Dashboard (roadmap 8.2; `docs/TUTORIAL_FUNNELS.md`).

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test` (Refill, SeedOnJoin) is off since 2026-10-08: the designer's
  blocks are used up like a player's (`/giveblock` gives more); timers still skip for them.
