# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-10 (the controller pass; tutorial v2 closed and in `gui-v4`; work goes on in
`~/Desktop/8ball`).

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-10, `gui-v4`):** lint OK (four old LocalShadow warnings); all 1198
  Lune tests pass.
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

- **Fredoka One** (`Config.UI.FontTest`); **blur, not dims**; **NEW RANK! waits** for a free
  lobby (no real arena trip back yet); **the 1v1 result cutscene** (no real 1v1 yet).
- **Cue outlines, the "pop" aura** (`Config.CueSkins.Pop.Ids`), **new cue card pictures**,
  **ball callouts**, the shorter pull-bar cue: not yet in a real game.
- **No fat-fingered shots** (`Config.Input.TouchPull`) and **the player list** (hidden on a
  phone; PC size not looked at): need a real phone.
- **The matchmaking bar and spawn pill**: parked (2026-10-07); open: the pill's 20 s, Play
  Global's X on a phone. **The queue portal**: not yet on a phone or gamepad.
- **The ball streak** (2026-10-09; GDD 8, UI_STYLE 28): checked in Studio and on an iPhone; a
  tablet next. **Coin flip tokens, phone letterbox bars, the Mystery screen** (2026-10-09):
  Studio's phone emulator only.
- **Lighting** day 10 min, sunset 5. **Pull cutscenes**: Mythic and Secret wait a redo.
- **Our own lucky blocks** and **the Mystery upgrade screen**: not yet on a phone or at full
  frame rate. **The Gift drop on the first opening of Roblox's menu** (2026-10-10, DECISIONS):
  `/giftdrop`, then press Escape; not yet by a real Escape press (Studio's test tools cannot
  press it), on a phone (the Roblox button) or a controller (Start).

## Open, waiting on the designer

- **The controller pass** (2026-10-10, GDD section 5, DECISIONS): one button map (A / Y power,
  R2 shoots, the stick + A calls the 8, Y Rank only, L2 Play Global / Join, D-pad left the right
  side, View Skip, R3 Next), the stuck-after-Rank fix, button pictures on ink discs. Checked in
  Studio with a forced pad (GuiQA "padMode" / "pad", STUDIO_NOTES) through game 1, Rank, the
  Mystery, Place, Cues, Abilities and the soft part's lobby. Open: the designer's real PS4 pad
  through the whole tutorial; "Press A" still in words on the reel, Mystery and bag hints.
- **The tutorial on phones, and the spin screen** (2026-10-10, DECISIONS; checked in Studio's
  phone emulator). Open: the designer's real phone and a PC window. Painicane's Studio save (a
  Studio-only store) is at the Soft part.
- **Daily rewards rework on `gui-v4`** (2026-10-10, DECISIONS). Open: the designer's look in
  Studio on phone, PC and controller.
- **Economy v5.1 "Lively"** (2026-10-09; screenshots in `~/Desktop/8ball-refs/economy-v5-gui/v5.1`).
  Open: the designer's OK; the tutorial's scripted first Mystery (hand-off in DECISIONS.md).
- **Economy v5.2** (2026-10-09: only the Mystery has upgrade chances; checked on PC). Open:
  phone and gamepad; live servers need "Restart Servers for Updates" after the publish.
- **The Grand Opening soft launch is on** (2026-10-09, `Deals.GrandOpening.SoftLaunch`): money
  and Robux, no end date, no luck, no launch bonus. For the release: set `StartsAt`.
- **Economy v5 and its screens on `gui-v4`** (2026-10-09; `docs/prompts/ECONOMY_V5_PLAN.md`,
  roadmap 7.9; the GUI run's Notes in `ECONOMY_V5_GUI_PROMPT.md`, screenshots in
  `~/Desktop/8ball-refs/economy-v5-gui/`). Still open, in order: phone and gamepad checks with
  the designer (step 13); the release (step 15): place saved and published, the Grand Opening's
  `StartsAt`, random-item products Not Listed, `tools/roblox_products.py --sync` (Starter Pack
  19 R$ on Roblox, Config 29; Lucky1 and Lucky3 off sale). Prices here show at about 0.8x
  (regional). Lucky Shot, Golden Shot, Lucky Rain and the stay bonus are planned only.
- **The Cues redo** (2026-10-08, `docs/prompts/CUES_LIVELY_PROMPT.md`, in `gui-v4`). Open: the
  see-through reel's verdict, a phone and a gamepad, the numbered card's mark A or B, the copy
  numbers' plan; `shop-lively` is not yet merged into `release`.
- **The abilities rework** (in `gui-v4` since 2026-10-08, `docs/prompts/ABILITIES_REWORK_PLAN.md`;
  the abilities themselves are in GDD and ECONOMY): not yet checked on phone and controller,
  the sounds by ear, the tutorial spin's reveal, the sneak with two players, the designer's
  voice lines. The one-by-one review (since 2026-09-30) goes on; unreviewed ones are provisional.
- **Decision still open:** whether the VIP cue pays finder's money on the first join.
- **Tutorial v2** (closed 2026-10-10; open items in the last section of
  `docs/prompts/TUTORIAL_V2_REPORT.md`): the first session's money rescale, two-player paths,
  Max Players, the funnels in the dashboard.
- **The cue rarity rework** continues after the Unique cues (Beta, Grand Opening, Eclipse,
  Celestial Dragon, Kitsune). Apex's first look was reverted.
- **The place file:** save `place/8ball.rbxl` and publish once this milestone is done.

## Not yet checked (the Studio tools cannot do these)

- A real phone and a real controller on everything since the UI redo, including the lucky
  block hold and reel skip, the shop and the pull cutscene skip. Studio's MCP cannot press a
  real gamepad (GuiQA "pad" stands in) and cannot switch the phone emulator in Play mode.
- Real multiplayer: a two-player block or cue trade, 2v2 and 4-player matches, the global
  queue in the published game (`docs/MULTIPLAYER_TESTING.md`), real Robux purchases.
- Sounds by ear (the levels were measured, not listened to), the new click "boop" included.
- The analytics funnels in the Creator Dashboard (roadmap 8.2; `docs/TUTORIAL_FUNNELS.md`).

## Known gaps and test switches to remember

- `Config.LuckyBlocks.Test` (Refill, SeedOnJoin) is off since 2026-10-08: the designer's
  blocks are used up like a player's (`/giveblock` gives more); timers still skip for them.
