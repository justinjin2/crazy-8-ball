# Status

Current state only, rewritten in place. Keep it to about two screens (under 100 lines). When a
step is finished and verified, move its dated entry to the top of
`docs/archive/STATUS_HISTORY.md` and keep only what is still true or still open here.

Updated 2026-10-10 (economy v6 built for the soft launch; work goes on in `~/Desktop/8ball`,
branch `gui-v4`).

## Where the build is

- **Branch `release`** is the integration branch, and every lane of the parallel build is
  merged into it (Bots, Economy, GUI and cutscenes, Tutorial, Unique cues). Stage 5 of the
  road to release (`docs/ROADMAP.md`): tutorial, funnel, performance, game page.
- **Lint and tests (2026-10-10, `gui-v4`):** lint OK (four old LocalShadow warnings); all 1214
  Lune tests pass.
- **In the game:** server-owned tables with our own physics and 8-ball rules; 1v1, 2v2, 3v3
  and solo; the global queue and arena with rematch; bots (ten tiers, Play against PC, lobby
  bots, disguised bots); ranks (XP only from winning) and money; **economy v6** (docs/ECONOMY.md; every save started
  over on the `_v2` stores); saves at version 11;
  13 abilities (Ultimates) with the spin screen; cue skins with VFX and outlines; lucky blocks
  as the only gacha (cases, the Magic 8 Ball and reward popups are gone); the Free Reward menu
  (daily, playtime, the 28-day track, group and invites), Cues (My Cues, Index; the Inventory renamed), trading, settings, our own player list and boards; the first-time tutorial;
  the rooftop map with a day and sunset cycle; pull cutscenes Rare to Secret; the ball streak.

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
- **Lighting** day 10 min, sunset 5.
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
- **Economy v6** (2026-10-10, `docs/prompts/ECONOMY_V6_PLAN.md`): built, Robux prices synced to
  Roblox, checked in Studio on PC (the real tutorial Mystery and Bronze's block ready at once,
  a duplicate paid as money, the Index's finder's money, the Sky clock). Open, in order:
  **publish** (the Grand Opening's 46 days already run from 2026-10-10 08:15 EDT,
  `Config.Shop.Deals.GrandOpening.StartsAt`), "Restart Servers for Updates", the server size 24 in the
  Creator Dashboard; the designer's look at the Sky banner, the Index's Collect card and the
  offer tile's new spot on a phone; a Sky block falling for real after 30 minutes. Roblox shows
  the products at about 0.8x their price (regional pricing or price optimization).
- **The Mythic and Secret pull cutscenes, redone** (2026-10-10, DECISIONS, the brief in
  `docs/prompts/PULL_CUTSCENES_V2.md`): checked in Studio on PC. Open: the designer's look and
  ears (`/cutscene mythic`, `/cutscene secret`), a phone and a controller.
- **Reel skip on Standard blocks only; the tutorial reel's Legendary near miss** (2026-10-10,
  DECISIONS). Open: the designer's look at a tutorial first block and an Uncommon reel.
- **Trading** is off for the release (`Config.Trade.Enabled`): no Trade button, the server refuses.
- **The Daily Challenge** is off for the release (`Config.UI.Corners.ChallengeOn`).
- **Solo and Practice portals** (2026-10-10, DECISIONS): built; checked in Studio (the lobby portals, the solo and
  practice arenas via StudioArenaPractice). The live match record now accepts their empty bot side
  (was bounced home). Open: a real teleport on the live game.
- **Launch review** (2026-10-10): saves, receipts, rewards, queue and server load reviewed; fixes in
  DECISIONS. Open after launch: server CPU per shot (MicroProfiler live), favorite reward unverifiable,
  "+10% Permanent" group wording, day 7 cue not in the claim flyer, Sky ping trusts the client.
- **The Cues redo** (2026-10-08, `docs/prompts/CUES_LIVELY_PROMPT.md`, in `gui-v4`). Open: the
  see-through reel's verdict, a phone and a gamepad, the numbered card's mark A or B, the copy
  numbers' plan; `shop-lively` is not yet merged into `release`.
- **The abilities rework** (in `gui-v4` since 2026-10-08, `docs/prompts/ABILITIES_REWORK_PLAN.md`;
  the abilities themselves are in GDD and ECONOMY): not yet checked on phone and controller,
  the sounds by ear, the tutorial spin's reveal, the sneak with two players, the designer's
  voice lines. The one-by-one review (since 2026-09-30) goes on; unreviewed ones are provisional.
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
